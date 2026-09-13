import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isServiceRequest } from "../_shared/service_auth.ts";
import { CRON_RETRY_BUDGET_MS, withRetry } from "../_shared/retry.ts";

// message-photos の {uid}/ai/ 配下で、messages.image_urls / meal_records.images の
// どちらからも参照されていない孤児画像（AI推定のキャンセル・離脱で残ったもの）を削除する。
// 参照判定は migration の SQL 関数 find_orphan_ai_images(cutoff interval) に委譲。
// 呼び出しは pg_cron（secret キーを apikey ヘッダーで）または手動実行を想定。
// 認証は _shared/service_auth.ts で行う（config.toml で verify_jwt = false）。
// body: { dry_run?: boolean } — 省略時 true（削除せず候補一覧のみ返す）。
// RPC と storage.remove は一時障害（5xx / 通信失敗）のとき _shared/retry.ts で再試行する
// （2026-09-13 の本番初回実行で RPC が 504 を受けて 500 終了したため）。
// 再試行はリクエスト受付から CRON_RETRY_BUDGET_MS までで打ち切り、pg_net のタイムアウト（60 秒）内に応答を返す
// （締切後のバッチは1回だけ試し、失敗分は従来どおり次回実行に回る）。

const BUCKET = "message-photos";
// storage.remove() の1回あたり削除件数（大量孤児時のリクエスト肥大を防ぐ）
const REMOVE_BATCH_SIZE = 100;

Deno.serve(async (req: Request) => {
  // 再試行の締切（受付から CRON_RETRY_BUDGET_MS。以降の RPC・remove の再試行はすべてこれで打ち切る）
  const retryDeadline = Date.now() + CRON_RETRY_BUDGET_MS;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (!isServiceRequest(req)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // body は省略可（cron からは {"dry_run": false} が届く）。明示的に false のときだけ削除実行
  const body = await req.json().catch(() => ({}));
  const dryRun = body?.dry_run !== false;

  // 孤児候補の抽出（アップロードから48時間以上経過したもののみ対象）
  const { data, error } = await withRetry(
    () =>
      supabase.rpc("find_orphan_ai_images", {
        cutoff: "48 hours",
      }),
    { label: "cleanup-ai-images rpc find_orphan_ai_images", deadline: retryDeadline }
  );

  if (error) {
    console.error("find_orphan_ai_images error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 返却行は name カラムを持つ想定だが、text 直返しにも防御的に対応する
  const paths: string[] = (data ?? [])
    .map((row: unknown) =>
      typeof row === "string" ? row : (row as { name?: string })?.name ?? null
    )
    .filter((p: string | null): p is string => typeof p === "string" && p.length > 0);

  if (dryRun) {
    console.log(`Dry run: found ${paths.length} orphan AI images`);
    return new Response(
      JSON.stringify({
        status: "ok",
        dry_run: true,
        count: paths.length,
        paths,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  // バッチ削除（ベストエフォート: 失敗バッチはログのみ残して続行し、次回実行で再試行される）。
  // remove は冪等なので一時障害はその場でも再試行する。失敗扱いの試行が実際には削除済みだった分は
  // 再試行の返却に含まれず failed に数えられるが、次回の候補にも出ないので実害はない
  let deleted = 0;
  let failed = 0;
  for (let i = 0; i < paths.length; i += REMOVE_BATCH_SIZE) {
    const batch = paths.slice(i, i + REMOVE_BATCH_SIZE);
    const { data: removed, error: removeError } = await withRetry(
      () => supabase.storage.from(BUCKET).remove(batch),
      { label: `cleanup-ai-images storage remove batch ${i / REMOVE_BATCH_SIZE + 1}`, deadline: retryDeadline }
    );
    if (removeError) {
      console.error(
        `storage remove failed (batch ${i / REMOVE_BATCH_SIZE + 1}):`,
        removeError
      );
      failed += batch.length;
      continue;
    }
    // remove は存在しないパス等を黙って除外するため、返却件数との差分を失敗扱いにする
    const removedCount = removed?.length ?? 0;
    deleted += removedCount;
    failed += batch.length - removedCount;
  }

  console.log(
    `Cleaned up orphan AI images: deleted=${deleted}, failed=${failed} (candidates: ${paths.length})`
  );

  return new Response(
    JSON.stringify({
      status: "ok",
      dry_run: false,
      count: paths.length,
      deleted,
      failed,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }
  );
});
