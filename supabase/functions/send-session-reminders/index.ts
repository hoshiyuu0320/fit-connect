import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { isServiceRequest } from "../_shared/service_auth.ts";
import { RESOLVE_ERROR_DETAIL, sendNotification } from "../_shared/push.ts";
import { CRON_RETRY_BUDGET_MS, withRetry } from "../_shared/retry.ts";
import {
  formatJstDate,
  formatSessionReminderBody,
  parseTargetDate,
} from "../_shared/session_reminder_format.ts";

// 対象日（JST 暦日）に scheduled / confirmed のセッションがある顧客へ前日リマインダー push を送る。
// 対象抽出は migration の SQL 関数 find_sessions_for_reminder(target_date date) に委譲し、
// 送信は統一ディスパッチャ（_shared/push.ts）に委譲する。冪等化は notification_logs.dedup_key
// （`session_reminder:<session_id>:<対象日 YYYY-MM-DD(JST)>`）で行い、別日へリスケされたら再送される。
// 呼び出しは pg_cron（20:00 JST、secret キーを apikey ヘッダーで、
// body '{"dry_run": false, "target_date": "<JST の明日>"}'。20260913000100 参照）または手動実行を想定。
// 認証は _shared/service_auth.ts で行う（config.toml で verify_jwt = false）。
// body: { dry_run?: boolean, target_date?: 'YYYY-MM-DD' }
//   - dry_run: 省略時 true（送信せず候補一覧のみ返す）。push を伴うため cleanup-ai-images と同じ既定
//   - target_date: 'YYYY-MM-DD' で実在する日付のみ受理（'tomorrow' / '2026/09/13' / 時刻付き等は 400）。
//     dry_run=false の本送信では必須（省略 / null は 400）。対象日を暗黙にすると JST 0 時以降の
//     手動実行で翌々日分を送る事故になり、dedup_key が対象日を含むため二重送信 / 送信漏れにつながる。
//     dry run では省略可（SQL 関数の既定 = JST の明日）
// 返却（dry run）: { status, dryRun: true, targetDate, candidateCount, candidates }
// 返却（本送信）: 上記 + outcome: { sent, partial, skipped, failed, duplicate }
//   - sent / partial / skipped / failed: 今回の呼び出しで作られた notification_logs 行の status 別件数
//     （failed には送信前の例外で行が作られなかった分と、宛先を読み取れなかった分（detail resolve_error。
//       端末未登録の skipped / no_tokens とは別）も含む）
//   - duplicate: 呼び出し前から同じ dedup_key の行があった件数（= 送信済みとしてスキップされた分）。
//     ただし前回の宛先解決の失敗で何も送れなかった行（status failed / detail resolve_error）は
//     push.ts が取り直して送り直すので duplicate に含めず、今回の結果（sent 等）として数える
//   - targetDate は常に YYYY-MM-DD（候補 0 件でも body 指定を正規化した値。dry run で省略時は JST の明日を自前計算）
// 候補抽出の RPC と notification_logs の読み取りは一時障害（5xx / 通信失敗）のとき _shared/retry.ts で再試行する
// （push.ts 内の宛先解決などの読み取りも同様）。再試行はリクエスト受付から CRON_RETRY_BUDGET_MS までで打ち切り、
// pg_net のタイムアウト（60 秒）内に応答を返す。
// push 送信（sendNotification）は二重送信になり得るため再試行で包まない（冪等性は dedup_key に任せる）。
// supabase-js は push.ts が要求する esm.sh 版の SupabaseClient 型に合わせて esm.sh から import する
// （jsr 版の createClient を渡すと型不一致になり得る）。

const NOTIFICATION_TITLE = "明日のセッションのお知らせ";
const DAY_MS = 24 * 60 * 60 * 1000;
/** notification_logs を dedup_key の IN で引くときの 1 リクエストあたり件数（URL 長を抑える） */
const LOG_QUERY_CHUNK = 50;

/** find_sessions_for_reminder の戻り行（timestamptz / date は PostgREST 経由で文字列） */
interface ReminderRow {
  session_id: string;
  client_id: string;
  trainer_id: string;
  trainer_name: string | null;
  session_date: string;
  duration_minutes: number;
  session_type: string | null;
  /** 対象日 'YYYY-MM-DD'（SQL 関数の引数または既定値がそのまま返る） */
  target_date: string;
}

/** notification_logs から集計用に読む列 */
interface LogRow {
  dedup_key: string;
  status: string;
  detail: string | null;
}

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * 指定した dedup_key 群に一致する notification_logs 行（dedup_key / status / detail）を返す。
 * 候補が多くても URL 長が伸びすぎないよう LOG_QUERY_CHUNK 件ずつに分けて問い合わせる。
 * 一時障害はチャンクごとに再試行し、それでも取得に失敗したら例外（呼び出し元で 500 にする）。
 */
async function fetchReminderLogs(
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
        label: `send-session-reminders notification_logs select chunk ${i / LOG_QUERY_CHUNK + 1}`,
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

Deno.serve(async (req: Request) => {
  // 再試行の締切（受付から CRON_RETRY_BUDGET_MS。以降の DB 読み取りの再試行はすべてこれで打ち切る）
  const retryDeadline = Date.now() + CRON_RETRY_BUDGET_MS;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (!isServiceRequest(req)) {
    return jsonResponse(401, { error: "Unauthorized" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // body は省略可（手動の dry run では空 body も許す）。明示的に false のときだけ送信実行
  const body = await req.json().catch(() => ({}));
  const dryRun = body?.dry_run !== false;

  // target_date: 未指定（キー無し / null）以外は必ず検証する。本送信では未指定を拒否する
  const rawTargetDate: unknown = body?.target_date;
  const targetDateOmitted = rawTargetDate === undefined || rawTargetDate === null;
  let targetDateArg: string | undefined;
  if (!targetDateOmitted) {
    const parsed = parseTargetDate(rawTargetDate);
    if (parsed === null) {
      return jsonResponse(400, {
        error: "target_date must be an existing date in YYYY-MM-DD format",
      });
    }
    targetDateArg = parsed;
  } else if (!dryRun) {
    return jsonResponse(400, {
      error: "target_date (YYYY-MM-DD) is required when dry_run is false",
    });
  }

  // 対象候補の抽出（scheduled / confirmed かつ session_date が対象日の JST 暦日内）。
  // 未指定（dry run のみ）は引数なしで呼び、SQL 側の既定 = JST の明日に任せる
  const { data, error } = await withRetry(
    () =>
      supabase.rpc(
        "find_sessions_for_reminder",
        targetDateArg === undefined ? {} : { target_date: targetDateArg }
      ),
    { label: "send-session-reminders rpc find_sessions_for_reminder", deadline: retryDeadline }
  );

  if (error) {
    console.error("find_sessions_for_reminder error:", error);
    return jsonResponse(500, { error: error.message });
  }

  const rows: ReminderRow[] = data ?? [];
  // 実際に使った対象日（常に YYYY-MM-DD）。body 指定があればその正規化値、無ければ戻り行の target_date 列、
  // 0 件なら JST の明日を自前で計算する
  const targetDate: string =
    targetDateArg ?? rows[0]?.target_date ?? formatJstDate(new Date(Date.now() + DAY_MS));
  const candidates = rows.map((r) => ({
    session_id: r.session_id,
    client_id: r.client_id,
    session_date: r.session_date,
  }));

  if (dryRun) {
    console.log(`Dry run: found ${rows.length} sessions for reminder (target: ${targetDate})`);
    return jsonResponse(200, {
      status: "ok",
      dryRun: true,
      targetDate,
      candidateCount: rows.length,
      candidates,
    });
  }

  // 今回の dedup_key 群。呼び出し前から行があるもの（= 前回実行分）は sendNotification 内で
  // dedup スキップされるため、送信前に控えておき集計で duplicate として分ける。
  // 宛先解決の失敗で何も送れなかった行（failed / resolve_error）は sendNotification が取り直して
  // 送り直すので duplicate にしない（今回の結果として数える）
  const dedupKeyOf = (row: ReminderRow) => `session_reminder:${row.session_id}:${row.target_date}`;
  const dedupKeys = rows.map(dedupKeyOf);
  const isResendable = (log: LogRow) => log.status === "failed" && log.detail === RESOLVE_ERROR_DETAIL;
  let duplicateKeys: Set<string>;
  try {
    const existing = await fetchReminderLogs(supabase, dedupKeys, retryDeadline);
    duplicateKeys = new Set(existing.filter((l) => !isResendable(l)).map((l) => l.dedup_key));
  } catch (e) {
    // まだ何も送っていないので安全に中断できる（再実行すればよい）
    console.error("[session-reminder] Failed to read existing notification_logs:", e);
    return jsonResponse(500, { error: e instanceof Error ? e.message : String(e) });
  }

  // 1件ずつディスパッチャへ渡す。sendNotification は void を返し例外も外に出さない
  // （送信結果は notification_logs.status/detail にのみ残る）ため、成否はループ後に
  // notification_logs を dedup_key で引いて集計する。
  // 本文整形など呼び出し前の例外で1件が失敗しても残りは続行する
  // （失敗分は notification_logs に行が残らないので dispatchErrors で数え、
  //   同じ target_date で手動再実行すれば送り直せる）。
  // sendNotification は withRetry で包まない（再送は二重送信になり得る。冪等性は dedup_key に任せる）。
  let dispatchErrors = 0;
  for (const row of rows) {
    try {
      await sendNotification({
        supabaseAdmin: supabase,
        userId: row.client_id,
        userType: "client",
        kind: "session_reminder",
        title: NOTIFICATION_TITLE,
        body: formatSessionReminderBody(row.session_date, row.trainer_name),
        // Mobile のタップ処理が読むキー名（type / id）に合わせる。値は文字列のみ
        data: { type: "session_reminder", id: row.session_id },
        dedupKey: dedupKeyOf(row),
        retryDeadline,
      });
    } catch (e) {
      console.error(`[session-reminder] Failed to dispatch (session ${row.session_id}):`, e);
      dispatchErrors += 1;
    }
  }

  // 集計: 今回作られた行の status 別件数 + 呼び出し前からあった行（duplicate）。
  // 前回実行分の行は status が前回の結果なので今回の件数には含めない
  let logs: LogRow[];
  try {
    logs = await fetchReminderLogs(supabase, dedupKeys, retryDeadline);
  } catch (e) {
    // 送信自体は済んでいる（結果は notification_logs に残っている）。集計だけ返せなかったことを 500 で伝える
    console.error("[session-reminder] Notifications dispatched but failed to read notification_logs:", e);
    return jsonResponse(500, {
      error: `notifications dispatched but outcome could not be read: ${
        e instanceof Error ? e.message : String(e)
      }`,
    });
  }

  const outcome = {
    sent: 0,
    partial: 0,
    skipped: 0,
    failed: dispatchErrors,
    duplicate: duplicateKeys.size,
  };
  let pending = 0;
  for (const log of logs) {
    if (duplicateKeys.has(log.dedup_key)) continue;
    switch (log.status) {
      case "sent":
        outcome.sent += 1;
        break;
      case "partial":
        outcome.partial += 1;
        break;
      case "skipped":
        outcome.skipped += 1;
        break;
      case "failed":
        outcome.failed += 1;
        break;
      default:
        // 'pending' のまま残った行（status 更新の失敗など）。返却には含めずログにのみ出す
        pending += 1;
    }
  }
  if (pending > 0) {
    console.warn(`[session-reminder] ${pending} notification_logs row(s) still pending (target: ${targetDate})`);
  }

  console.log(
    `Session reminders: sent=${outcome.sent}, partial=${outcome.partial}, skipped=${outcome.skipped}, ` +
      `failed=${outcome.failed}, duplicate=${outcome.duplicate} (candidates: ${rows.length}, target: ${targetDate})`
  );

  return jsonResponse(200, {
    status: "ok",
    dryRun: false,
    targetDate,
    candidateCount: rows.length,
    candidates,
    outcome,
  });
});
