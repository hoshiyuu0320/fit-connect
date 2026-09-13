import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isServiceRequest } from "../_shared/service_auth.ts";
import { CRON_RETRY_BUDGET_MS, withRetry } from "../_shared/retry.ts";

// assigned_date から3日以上過ぎた pending の workout_assignments を skipped にする。
// 対象は plan_type = 'self_guided' のプランのみ。session 型はトレーナーが Web で記録するため、
// 未記録のまま自動スキップ扱いにしないよう除外する（plan が取れないものも対象外）。
// 呼び出しは pg_cron（secret キーを apikey ヘッダーで, body '{}'）または手動実行を想定。
// 認証は _shared/service_auth.ts で行う（config.toml で verify_jwt = false）。
// body: { dry_run?: boolean } — 省略時 false（実行する）。true のときは更新せず候補一覧のみ返す。
// DB 呼び出しは一時障害（5xx / 通信失敗）のとき _shared/retry.ts で再試行する（cron は失敗に気づけないため）。
// 再試行はリクエスト受付から CRON_RETRY_BUDGET_MS までで打ち切り、pg_net のタイムアウト（60 秒）内に応答を返す。

// update の1回あたり件数（.in() の URL 肥大を防ぐ）
const UPDATE_BATCH_SIZE = 100;

Deno.serve(async (req: Request) => {
  // 再試行の締切（受付から CRON_RETRY_BUDGET_MS。以降の DB 呼び出しの再試行はすべてこれで打ち切る）
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

  // body は省略可（cron からは {} が届く）。明示的に true のときだけ dry run
  const body = await req.json().catch(() => ({}));
  const dryRun = body?.dry_run === true;

  // 3日前の日付を計算
  const threeDaysAgo = new Date();
  threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);
  const cutoffDate = threeDaysAgo.toISOString().split("T")[0];

  // 対象候補の抽出（self_guided プランの期限切れ pending のみ）。
  // postgrest-js の内部再試行は切り、再試行を withRetry に一本化する（_shared/retry.ts 参照）
  const { data: candidates, error: selectError } = await withRetry(
    () =>
      supabase
        .from("workout_assignments")
        .select("id, workout_plans!inner(plan_type)")
        .eq("workout_plans.plan_type", "self_guided")
        .eq("status", "pending")
        .lt("assigned_date", cutoffDate)
        .retry(false),
    { label: "auto-skip-workouts select candidates", deadline: retryDeadline }
  );

  if (selectError) {
    console.error("Auto-skip select error:", selectError);
    return new Response(JSON.stringify({ error: selectError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const candidateIds: string[] = (candidates ?? []).map((d: { id: string }) => d.id);

  if (dryRun) {
    console.log(`Dry run: found ${candidateIds.length} overdue self_guided assignments (cutoff: ${cutoffDate})`);
    return new Response(
      JSON.stringify({
        status: "ok",
        dryRun: true,
        cutoffDate,
        candidateCount: candidateIds.length,
        skippedCount: 0,
        candidateIds,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  // バッチ更新。select 後に顧客が完了・日付変更した行を上書きしないよう status と assigned_date を再確認する
  // （日付変更は status を pending のまま assigned_date だけ変えるため、status だけでは防げない）。
  // この条件付き update は冪等なので一時障害は再試行する。失敗扱いの試行が DB 側では反映済みだった場合、
  // 再試行の返却にその行は含まれず skippedCount が少なく出るだけで、行の状態は正しい
  const skippedIds: string[] = [];
  for (let i = 0; i < candidateIds.length; i += UPDATE_BATCH_SIZE) {
    const chunk = candidateIds.slice(i, i + UPDATE_BATCH_SIZE);
    const { data: updated, error: updateError } = await withRetry(
      () =>
        supabase
          .from("workout_assignments")
          .update({
            status: "skipped",
            updated_at: new Date().toISOString(),
          })
          .in("id", chunk)
          .eq("status", "pending")
          .lt("assigned_date", cutoffDate)
          .select("id"),
      { label: `auto-skip-workouts update batch ${i / UPDATE_BATCH_SIZE + 1}`, deadline: retryDeadline }
    );

    if (updateError) {
      console.error(
        `Auto-skip update error (batch ${i / UPDATE_BATCH_SIZE + 1}, already skipped: ${skippedIds.length}):`,
        updateError
      );
      return new Response(JSON.stringify({ error: updateError.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    skippedIds.push(...(updated ?? []).map((d: { id: string }) => d.id));
  }

  const skippedCount = skippedIds.length;
  console.log(
    `Auto-skipped ${skippedCount} overdue self_guided assignments (candidates: ${candidateIds.length}, cutoff: ${cutoffDate})`
  );

  return new Response(
    JSON.stringify({
      status: "ok",
      dryRun: false,
      cutoffDate,
      candidateCount: candidateIds.length,
      skippedCount,
      skippedIds,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }
  );
});
