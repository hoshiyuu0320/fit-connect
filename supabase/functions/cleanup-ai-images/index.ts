import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// message-photos の {uid}/ai/ 配下で、messages.image_urls / meal_records.images の
// どちらからも参照されていない孤児画像（AI推定のキャンセル・離脱で残ったもの）を削除する。
// 参照判定は migration の SQL 関数 find_orphan_ai_images(cutoff interval) に委譲。
// 呼び出しは pg_cron（service_role Bearer）または手動実行を想定。
// body: { dry_run?: boolean } — 省略時 true（削除せず候補一覧のみ返す）。

const BUCKET = "message-photos";
// storage.remove() の1回あたり削除件数（大量孤児時のリクエスト肥大を防ぐ）
const REMOVE_BATCH_SIZE = 100;

Deno.serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (authHeader !== `Bearer ${serviceRoleKey}`) {
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
  const { data, error } = await supabase.rpc("find_orphan_ai_images", {
    cutoff: "48 hours",
  });

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

  // バッチ削除（ベストエフォート: 失敗バッチはログのみ残して続行し、次回実行で再試行される）
  let deleted = 0;
  let failed = 0;
  for (let i = 0; i < paths.length; i += REMOVE_BATCH_SIZE) {
    const batch = paths.slice(i, i + REMOVE_BATCH_SIZE);
    const { data: removed, error: removeError } = await supabase.storage
      .from(BUCKET)
      .remove(batch);
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
