import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { isServiceRequest } from "../_shared/service_auth.ts";
import { RESOLVE_ERROR_DETAIL, sendNotification } from "../_shared/push.ts";
import { CRON_RETRY_BUDGET_MS, withRetry } from "../_shared/retry.ts";
import { formatJstDate } from "../_shared/session_reminder_format.ts";
import {
  type AlertRow,
  buildTrainerDigests,
  DIGEST_TITLE,
  DIGEST_TTL_SECONDS,
  DIGEST_URL,
  digestDedupKey,
  digestTag,
  type DigestOutcome,
  emptyOutcome,
  formatDigestBody,
  type LogRow,
  parseNotifyRequest,
  summarizeOutcome,
} from "../_shared/client_alert_digest.ts";

// トレーナー向けアラートの朝のまとめ通知（フェーズ9.1 拡張 push `client_alert`）。
// 設計: docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md §4・§5
//
// 対象日 D（JST の暦日）の自動チェック（cron detect-client-alerts。alert_detection_runs に target_date = D の行）が
// 成功していれば、status = 'open' かつ surfaced_on = D のアラートを今の担当トレーナーごとに集計し
// （顧客ごとの最重大度で人数を数える）、トレーナー1人につき1通の Web Push を送る。
// 送信は統一ディスパッチャ（_shared/push.ts）に委譲し、冪等化は dedup_key
// `client_alert_digest:<trainer_id>:<D>` で行う（同じ D で何度呼んでも1通）。
// 呼び出しは pg_cron（21:10 UTC = JST 06:10、secret キーを apikey ヘッダーで、
// body {"dry_run": false, "target_date": "<JST の今日>"}。20261004000000 参照）または手動実行。
// 認証は _shared/service_auth.ts（config.toml で verify_jwt = false）。
// body: { dry_run?: boolean, target_date?: 'YYYY-MM-DD', trainer_id?: uuid }（検証は parseNotifyRequest）
//   - dry_run: 真偽値の false のときだけ送る（省略時は dry run）
//   - target_date: 本送信では必須。JST の今日より後は 400。過去は受け付ける（手動の送り直し・確認用）
//   - trainer_id: 指定するとそのトレーナー1人だけ（本番での確認・送り直し用。cron は付けない）
// 返却: { status, dryRun, targetDate, trainerId, detectionReady, trainerCount, alreadyLogged, digests[, outcome] }
//   - digests はトレーナー ID と人数だけ（顧客 ID・名前は返さない）
//   - outcome は §5.3（sent / partial / skipped / failed / pending / duplicate / missing / skippedBy）
// DB の読み取りは一時障害のとき _shared/retry.ts で再試行する（受付から CRON_RETRY_BUDGET_MS で打ち切り、
// pg_net のタイムアウト 60 秒内に応答する）。push 送信（sendNotification）は再試行で包まない（二重送信を避ける）。
// supabase-js は push.ts が要求する esm.sh 版の SupabaseClient 型に合わせて esm.sh から import する。

/** notification_logs を dedup_key の IN で引くときの 1 リクエストあたり件数（URL 長を抑える） */
const LOG_QUERY_CHUNK = 50;
/** alerts を読む 1 ページの件数（PostgREST の最大行数 1000 に合わせる） */
const ALERT_PAGE_SIZE = 1000;

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/**
 * 指定した dedup_key 群に一致する notification_logs 行（dedup_key / status / detail）を返す。
 * send-session-reminders/index.ts の fetchReminderLogs の複製（共有の置き場が無いため。§5.4）。
 * どちらかを直したらもう片方も直す。違いはラベル文字列だけ（読めなかったときの扱いは呼び出し側で決める）。
 * 一時障害はチャンクごとに再試行し、それでも取得に失敗したら例外。
 */
async function fetchNotificationLogs(
  supabase: SupabaseClient,
  dedupKeys: string[],
  retryDeadline: number
): Promise<LogRow[]> {
  const logs: LogRow[] = [];
  for (let i = 0; i < dedupKeys.length; i += LOG_QUERY_CHUNK) {
    const chunk = dedupKeys.slice(i, i + LOG_QUERY_CHUNK);
    // postgrest-js の内部再試行は切り、再試行を withRetry に一本化する（_shared/retry.ts 参照）
    const { data, error } = await withRetry(
      () =>
        supabase
          .from("notification_logs")
          .select("dedup_key, status, detail")
          .in("dedup_key", chunk)
          .retry(false),
      {
        label: `notify-trainer-alerts notification_logs select chunk ${i / LOG_QUERY_CHUNK + 1}`,
        deadline: retryDeadline,
      }
    );
    if (error) {
      throw new Error(`notification_logs select failed: ${error.message}`);
    }
    logs.push(...((data ?? []) as LogRow[]));
  }
  return logs;
}

/**
 * 前回の宛先解決の失敗で何も送れなかった行（push.ts が取り直して送り直す）。
 * send-session-reminders/index.ts の isResendable の複製（§5.4）
 */
const isResendable = (log: LogRow) => log.status === "failed" && log.detail === RESOLVE_ERROR_DETAIL;

/**
 * D の自動チェックが成功したか（alert_detection_runs に target_date = D の行が1行以上あるか）。
 * 同じ D の行は複数ありうるので、有無だけを配列で読む（.single() / .maybeSingle() は使わない。§5.2-2）
 */
async function isDetectionReady(
  supabase: SupabaseClient,
  targetDate: string,
  retryDeadline: number
): Promise<boolean> {
  const { data, error } = await withRetry(
    () =>
      supabase
        .from("alert_detection_runs")
        .select("id")
        .eq("target_date", targetDate)
        .limit(1)
        .retry(false),
    { label: "notify-trainer-alerts alert_detection_runs select", deadline: retryDeadline }
  );
  if (error) {
    throw new Error(`alert_detection_runs select failed: ${error.message}`);
  }
  return (data ?? []).length > 0;
}

/**
 * status = 'open' かつ surfaced_on = D のアラートを、担当の判定に使う clients.trainer_id 付きで読む。
 * PostgREST の最大行数（1000）を超えても漏れないよう、id 順に 1000 件ずつ（id より後ろを）取り切る
 */
async function fetchSurfacedAlerts(
  supabase: SupabaseClient,
  targetDate: string,
  retryDeadline: number
): Promise<AlertRow[]> {
  const rows: AlertRow[] = [];
  let lastId: string | null = null;
  for (let page = 1; ; page++) {
    const after = lastId;
    const { data, error } = await withRetry(
      () => {
        let query = supabase
          .from("alerts")
          .select("id, trainer_id, client_id, severity, clients!inner(trainer_id)")
          .eq("status", "open")
          .eq("surfaced_on", targetDate);
        if (after !== null) query = query.gt("id", after);
        return query.order("id", { ascending: true }).limit(ALERT_PAGE_SIZE).retry(false);
      },
      { label: `notify-trainer-alerts alerts select page ${page}`, deadline: retryDeadline }
    );
    if (error) {
      throw new Error(`alerts select failed: ${error.message}`);
    }
    const pageRows = (data ?? []) as unknown as (AlertRow & { id: string })[];
    rows.push(...pageRows);
    if (pageRows.length < ALERT_PAGE_SIZE) return rows;
    lastId = pageRows[pageRows.length - 1].id;
  }
}

Deno.serve(async (req: Request) => {
  // 再試行の締切（受付から CRON_RETRY_BUDGET_MS。以降の DB 読み取りの再試行はすべてこれで打ち切る）
  const retryDeadline = Date.now() + CRON_RETRY_BUDGET_MS;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (!isServiceRequest(req)) {
    return jsonResponse(401, { error: "Unauthorized" });
  }

  // JSON でない body は {}（= dry run）。null・配列などオブジェクトでない JSON も parseNotifyRequest が {} として扱う
  const body: unknown = await req.json().catch(() => ({}));
  const request = parseNotifyRequest(body, formatJstDate(new Date()));
  if (!request.ok) {
    return jsonResponse(400, { error: request.error });
  }
  const { dryRun, targetDate, trainerId } = request;

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // 1. D の自動チェックの成否（読めなければ 500。まだ何も送っていない）
  let detectionReady: boolean;
  try {
    detectionReady = await isDetectionReady(supabase, targetDate, retryDeadline);
  } catch (e) {
    console.error("[notify-trainer-alerts] Failed to read alert_detection_runs:", e);
    return jsonResponse(500, { error: errorMessage(e) });
  }

  const base = { status: "ok", dryRun, targetDate, trainerId };

  if (!detectionReady) {
    // 送らない。この D のキーは使わないので、検知が遅れて成功したら同じ D を指定して送れる
    console.warn(`[notify-trainer-alerts] Alert detection has not succeeded for ${targetDate}; nothing sent`);
    return jsonResponse(200, {
      ...base,
      detectionReady: false,
      trainerCount: 0,
      alreadyLogged: 0,
      digests: [],
      ...(dryRun ? {} : { outcome: emptyOutcome() }),
    });
  }

  // 2. 対象のアラート → トレーナーごとの人数（→ trainer_id の指定があればその1人だけ）
  let rows: AlertRow[];
  try {
    rows = await fetchSurfacedAlerts(supabase, targetDate, retryDeadline);
  } catch (e) {
    console.error("[notify-trainer-alerts] Failed to read alerts:", e);
    return jsonResponse(500, { error: errorMessage(e) });
  }
  const digests = buildTrainerDigests(rows).filter(
    (d) => trainerId === null || d.trainer_id === trainerId
  );
  const keys = digests.map((d) => digestDedupKey(d.trainer_id, targetDate));

  if (dryRun) {
    // 既に行がある人数（本送信が重複になるかを事前に知るため）。読めなければ null
    let alreadyLogged: number | null;
    try {
      alreadyLogged = (await fetchNotificationLogs(supabase, keys, retryDeadline)).length;
    } catch (e) {
      console.warn("[notify-trainer-alerts] Dry run: failed to read notification_logs:", e);
      alreadyLogged = null;
    }
    console.log(
      `Dry run: ${digests.length} trainer digest(s) for ${targetDate} (alerts read: ${rows.length})`
    );
    return jsonResponse(200, {
      ...base,
      detectionReady: true,
      trainerCount: digests.length,
      alreadyLogged,
      digests,
    });
  }

  // 3. 送る前に、既に行があるキー（= 送信済み・skipped など）を「重複」として控える。
  //    failed / resolve_error の行は push.ts が取り直して送り直すので重複にしない。
  //    読めなくても中断しない（二重送信は sendNotification 側の dedup が防ぐ。duplicate: null）
  let duplicateKeys: Set<string> | null;
  let alreadyLogged: number | null;
  try {
    const existing = await fetchNotificationLogs(supabase, keys, retryDeadline);
    alreadyLogged = existing.length;
    duplicateKeys = new Set(existing.filter((l) => !isResendable(l)).map((l) => l.dedup_key));
  } catch (e) {
    console.warn("[notify-trainer-alerts] Failed to read existing notification_logs; continuing:", e);
    duplicateKeys = null;
    alreadyLogged = null;
  }

  // 4. トレーナーごとに1通。sendNotification は例外を外に出さないので、ここで捕まるのは呼び出し前の例外だけ
  const dispatchErrorKeys = new Set<string>();
  for (const digest of digests) {
    const dedupKey = digestDedupKey(digest.trainer_id, targetDate);
    try {
      await sendNotification({
        supabaseAdmin: supabase,
        userId: digest.trainer_id,
        userType: "trainer",
        kind: "client_alert",
        title: DIGEST_TITLE,
        body: formatDigestBody(digest),
        data: { type: "client_alert", url: DIGEST_URL, tag: digestTag(targetDate) },
        dedupKey,
        ttlSeconds: DIGEST_TTL_SECONDS,
        retryDeadline,
      });
    } catch (e) {
      console.error(`[notify-trainer-alerts] Failed to dispatch (trainer ${digest.trainer_id}):`, e);
      dispatchErrorKeys.add(dedupKey);
    }
  }

  // 5. 送った後に引き直して数える。読めなくても送信は済んでいるので 200（outcome: null）
  let outcome: DigestOutcome | null;
  try {
    const logs = await fetchNotificationLogs(supabase, keys, retryDeadline);
    outcome = summarizeOutcome(keys, logs, duplicateKeys, dispatchErrorKeys);
  } catch (e) {
    console.warn("[notify-trainer-alerts] Notifications dispatched but failed to read notification_logs:", e);
    outcome = null;
  }

  if (outcome) {
    if (outcome.missing > 0) {
      console.warn(
        `[notify-trainer-alerts] ${outcome.missing} notification_logs row(s) missing after dispatch (target: ${targetDate})`
      );
    }
    if (outcome.pending > 0) {
      console.warn(
        `[notify-trainer-alerts] ${outcome.pending} notification_logs row(s) still pending (target: ${targetDate})`
      );
    }
    console.log(
      `Trainer alert digests: sent=${outcome.sent}, partial=${outcome.partial}, skipped=${outcome.skipped}, ` +
        `failed=${outcome.failed}, pending=${outcome.pending}, duplicate=${outcome.duplicate}, ` +
        `missing=${outcome.missing} (trainers: ${digests.length}, target: ${targetDate})`
    );
  }

  return jsonResponse(200, {
    ...base,
    detectionReady: true,
    trainerCount: digests.length,
    alreadyLogged,
    digests,
    outcome,
  });
});
