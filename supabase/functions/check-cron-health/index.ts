import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { isServiceRequest } from "../_shared/service_auth.ts";
import { sendNotification } from "../_shared/push.ts";
import { CRON_RETRY_BUDGET_MS, withRetry } from "../_shared/retry.ts";
import {
  CRON_FAILURE_TITLE,
  CRON_FAILURE_URL,
  dispatchAndCheckDelivered,
  formatProblemsBody,
  parseCheckRequest,
  parseRecipientIds,
  problemsDedupKey,
  problemsTag,
  TEST_NOTIFICATION_BODY,
  TEST_NOTIFICATION_TAG,
  TEST_NOTIFICATION_TITLE,
  testNotificationDedupKey,
} from "../_shared/cron_health.ts";

// cron 失敗の監視（統合判断7-3 / フェーズ5.3 の残り）。
// 設計: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md §5
//
// 確認そのものは RPC run_cron_health_check が行う（失敗・動かなかったジョブ・HTTP の応答を見て
// cron_health_problems に記録し、未通知の問題を返す。冪等。20261101000000 参照）。
// この関数は、未通知の問題を1通のまとめにして運営（secret CRON_ALERT_TRAINER_IDS のトレーナー）へ送り、
// 1人にでも届いたら notified_at を埋める。届かなかった分は次の確認で別の dedup キーになり送り直される。
// 呼び出しは pg_cron（40 11,21 * * * = JST 06:40 / 20:40、secret キーを apikey ヘッダーで、
// body {"dry_run": false}）または手動実行。認証は _shared/service_auth.ts（config.toml で verify_jwt = false）。
// body: { dry_run?: boolean, test_notification?: boolean }（検証は parseCheckRequest）
//   - dry_run: 真偽値の false のときだけ送る（省略時は dry run。問題の記録は冪等に行われる）
//   - test_notification: dry_run が false のときだけ有効。確認も記録もせず、テスト通知だけを送る
//     （実際の失敗が起きるまで通知の経路を試せないため）
// 返却: { status, dryRun, recipients, pendingCount, notified, problems: [{ jobname, kind, summary, occurred_at }] }
//   - pendingCount は未通知の問題の数（このリクエストで notified_at を埋める前の値）
//   - notified はこのリクエストで notified_at を埋めたか
//   - detail は返さない（例外の文言や応答の本文。SQL で cron_health_problems を読む）
//   - test_notification のときは { status, dryRun, testNotification: true, recipients, notified }（notified は届いたか）
// DB の読み取りは一時障害のとき _shared/retry.ts で再試行する（受付から CRON_RETRY_BUDGET_MS で打ち切り、
// pg_net のタイムアウト 60 秒内に応答する）。push 送信（sendNotification）は再試行で包まない（二重送信を避ける）。
// supabase-js は push.ts が要求する esm.sh 版の SupabaseClient 型に合わせて esm.sh から import する。

/** run_cron_health_check の1行 */
interface ProblemRow {
  id: number;
  jobname: string;
  kind: string;
  summary: string;
  detail: string | null;
  occurred_at: string;
}

interface OutgoingNotification {
  title: string;
  body: string;
  tag: string;
  dedupKeyOf: (trainerId: string) => string;
}

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** dedup キーに一致する notification_logs の status を読み直す。読めなければ例外 */
async function readLogStatuses(
  supabase: SupabaseClient,
  dedupKeys: string[],
  retryDeadline: number
): Promise<unknown[]> {
  // postgrest-js の内部再試行は切り、再試行を withRetry に一本化する（_shared/retry.ts 参照）
  const { data, error } = await withRetry(
    () =>
      supabase
        .from("notification_logs")
        .select("status")
        .in("dedup_key", dedupKeys)
        .retry(false),
    { label: "check-cron-health notification_logs select", deadline: retryDeadline }
  );
  if (error) {
    throw new Error(error.message);
  }
  return (data ?? []).map((log: { status: unknown }) => log.status);
}

/** 宛先ごとに1通送り、1人にでも届いたかを返す（判定は _shared/cron_health.ts の dispatchAndCheckDelivered） */
function dispatchToRecipients(
  supabase: SupabaseClient,
  recipientIds: readonly string[],
  notification: OutgoingNotification,
  retryDeadline: number
): Promise<boolean> {
  return dispatchAndCheckDelivered({
    recipientIds,
    dedupKeyOf: notification.dedupKeyOf,
    send: (trainerId, dedupKey) =>
      sendNotification({
        supabaseAdmin: supabase,
        userId: trainerId,
        userType: "trainer",
        kind: "cron_failure",
        title: notification.title,
        body: notification.body,
        data: { type: "cron_failure", url: CRON_FAILURE_URL, tag: notification.tag },
        dedupKey,
        retryDeadline,
      }),
    readStatuses: (dedupKeys) => readLogStatuses(supabase, dedupKeys, retryDeadline),
  });
}

Deno.serve(async (req: Request) => {
  // 再試行の締切（受付から CRON_RETRY_BUDGET_MS。以降の DB 呼び出しの再試行はすべてこれで打ち切る）
  const retryDeadline = Date.now() + CRON_RETRY_BUDGET_MS;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (!isServiceRequest(req)) {
    return jsonResponse(401, { error: "Unauthorized" });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method Not Allowed" });
  }

  // JSON でない body は {}（= dry run）。null・配列などオブジェクトでない JSON も parseCheckRequest が {} として扱う
  const body: unknown = await req.json().catch(() => ({}));
  const { dryRun, testNotification } = parseCheckRequest(body);

  const { ids: recipientIds, invalidCount } = parseRecipientIds(Deno.env.get("CRON_ALERT_TRAINER_IDS"));
  if (invalidCount > 0) {
    console.warn(`[check-cron-health] Ignored ${invalidCount} invalid value(s) in CRON_ALERT_TRAINER_IDS`);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  // dedup キーの時刻は1リクエストで1つにそろえる（送信中に時間をまたいでも、引き直しで同じキーを読む）
  const now = new Date();

  // 1. テスト通知（確認も記録もしない）
  if (testNotification) {
    if (recipientIds.length === 0) {
      console.warn("[check-cron-health] CRON_ALERT_TRAINER_IDS has no recipients; test notification not sent");
    }
    const delivered = await dispatchToRecipients(
      supabase,
      recipientIds,
      {
        title: TEST_NOTIFICATION_TITLE,
        body: TEST_NOTIFICATION_BODY,
        tag: TEST_NOTIFICATION_TAG,
        dedupKeyOf: (trainerId) => testNotificationDedupKey(trainerId, now),
      },
      retryDeadline
    );
    return jsonResponse(200, {
      status: "ok",
      dryRun,
      testNotification: true,
      recipients: recipientIds.length,
      notified: delivered,
    });
  }

  // 2. 確認（冪等なので withRetry で包む。読めなければ 500。次の確認でやり直す）
  let problems: ProblemRow[];
  try {
    const { data, error } = await withRetry(
      () => supabase.rpc("run_cron_health_check"),
      { label: "check-cron-health rpc run_cron_health_check", deadline: retryDeadline }
    );
    if (error) {
      throw new Error(error.message);
    }
    problems = (data ?? []) as ProblemRow[];
  } catch (e) {
    console.error("[check-cron-health] Failed to run run_cron_health_check:", e);
    return jsonResponse(500, { error: errorMessage(e) });
  }

  const respond = (notified: boolean) =>
    jsonResponse(200, {
      status: "ok",
      dryRun,
      recipients: recipientIds.length,
      pendingCount: problems.length,
      notified,
      problems: problems.map(({ jobname, kind, summary, occurred_at }) => ({ jobname, kind, summary, occurred_at })),
    });

  // 3. dry run は送らない。4. 問題が無ければ何もしない
  if (dryRun || problems.length === 0) {
    console.log(`[check-cron-health] ${dryRun ? "Dry run: " : ""}${problems.length} pending problem(s)`);
    return respond(false);
  }

  // 5. 宛先なし（問題は未通知のまま残り、宛先を設定した後の確認で送られる）
  if (recipientIds.length === 0) {
    console.warn(`[check-cron-health] CRON_ALERT_TRAINER_IDS has no recipients; ${problems.length} problem(s) left unnotified`);
    return respond(false);
  }

  // 6. 宛先ごとに1通。7. 1人にでも届いたら通知済みにする
  // 並びは id の昇順（run_cron_health_check）なので、問題が増えると「最後の問題の id」が変わり、別のキーになる
  const firstId = problems[0].id;
  const lastId = problems[problems.length - 1].id;
  const delivered = await dispatchToRecipients(
    supabase,
    recipientIds,
    {
      title: CRON_FAILURE_TITLE,
      body: formatProblemsBody(problems),
      tag: problemsTag(firstId, lastId),
      dedupKeyOf: (trainerId) => problemsDedupKey(trainerId, firstId, lastId, now),
    },
    retryDeadline
  );

  if (!delivered) {
    console.warn(`[check-cron-health] Not delivered to any recipient; ${problems.length} problem(s) left unnotified`);
    return respond(false);
  }

  // 更新に失敗しても 200（次の確認で同じ問題をもう1回通知する。通知が欠けるより軽い）。
  // run_cron_health_check は未通知の問題を id の昇順で返すので、範囲で同じ行になる（後から記録された問題は
  // id が lastId より大きいので入らない）。in() と違い、問題が多くても URL が伸びない
  try {
    const { error } = await withRetry(
      () =>
        supabase
          .from("cron_health_problems")
          .update({ notified_at: new Date().toISOString() })
          .gte("id", firstId)
          .lte("id", lastId)
          .is("notified_at", null),
      { label: "check-cron-health cron_health_problems update", deadline: retryDeadline }
    );
    if (error) {
      throw new Error(error.message);
    }
  } catch (e) {
    console.warn("[check-cron-health] Notified but failed to update notified_at:", e);
    return respond(false);
  }

  console.log(`[check-cron-health] Notified ${problems.length} problem(s) to ${recipientIds.length} recipient(s)`);
  return respond(true);
});
