/**
 * 統一通知ディスパッチャ
 *
 * Edge Functions から呼び出す push 通知の単一入口。以下を一手に担う:
 *   1. 冪等化（notification_logs.dedup_key による二重送信防止）
 *   2. ユーザー設定（notification_preferences: enabled / quiet hours[JST]）の尊重
 *   3. 宛先解決（device_tokens 優先。stage2 期間中は clients/trainers.fcm_token へフォールバック）
 *   4. FCM HTTP v1 送信（ios / android）+ 無効トークンの DB 掃除
 *   5. Web Push 送信（web_push、VAPID）+ 失効購読の DB 掃除
 *   6. 送信結果の notification_logs への記録
 *
 * 呼び出し元の処理（タグ解析・レコード作成等）を絶対に失敗させないため、
 * この関数は例外を外に投げない（内部で捕捉して console.error + status='failed' 記録）。
 *
 * 一時障害（5xx / 通信失敗）の扱い:
 *   - 冪等な読み取り（notification_preferences / device_tokens / clients・trainers.fcm_token）だけを
 *     _shared/retry.ts で再試行する。ログ行の upsert・status 更新・FCM / Web Push の送信は包まない
 *     （upsert は反映済みかどうか区別できず、送信の再送は二重送信になり得るため）。
 *     再試行の待機は失敗したときだけ掛かる（webhook の parse-message-tags も同じ）
 *   - 再試行しても宛先を読めなかった場合は、端末未登録（skipped / no_tokens）と区別して
 *     status='failed' / detail='resolve_error' で記録する。この行は何も送っていないので、
 *     同じ dedup_key で再度呼ばれたとき（cron の手動再実行など）は行を取り直して送り直す
 *     （reclaimUnsentLog）。送信済み・skipped など他の行は従来どおり重複としてスキップする
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { isWithinQuietHours, jstSecondsOfDay } from './quiet_hours.ts'
import { type RetryOptions, withRetry } from './retry.ts'

// ============================================================
// 公開API
// ============================================================

export interface SendArgs {
  /** service_role クライアント（呼び出し元が生成済みのものを受け取る） */
  supabaseAdmin: SupabaseClient
  userId: string
  userType: 'client' | 'trainer'
  kind: 'message' | 'goal_achievement' | 'session_reminder'
  title: string
  body: string
  /** FCM data ペイロード（値は文字列のみ）。Web Push では JSON ペイロードに含める */
  data?: Record<string, string>
  /** 冪等キー（例: `message:${messageId}` / `goal:${messageId}`） */
  dedupKey: string
  /**
   * 読み取りの再試行の締切（Date.now() 基準の epoch ms。_shared/retry.ts の deadline）。
   * cron（send-session-reminders）が関数全体を pg_net のタイムアウト内に収めるために渡す。
   * 省略時は締切なし
   */
  retryDeadline?: number
}

/**
 * 宛先解決（device_tokens / fcm_token の読み取り）に失敗して何も送らなかった行の detail。
 * status='failed' とこの detail の組の行だけが、同じ dedup_key の再呼び出しで送り直しの対象になる
 */
export const RESOLVE_ERROR_DETAIL = 'resolve_error'

export async function sendNotification(args: SendArgs): Promise<void> {
  const { supabaseAdmin, userId, userType, kind, title, body, dedupKey } = args
  const data = args.data ?? {}
  // 冪等な読み取り用の再試行設定（ラベルの dedup_key は通知の特定用。秘密情報は含まない）
  const readRetry = (label: string): RetryOptions => ({
    label: `push ${label} (${dedupKey})`,
    deadline: args.retryDeadline,
  })

  try {
    // --------------------------------------------------------
    // 1. 冪等化: dedup_key の UNIQUE 制約 + ON CONFLICT DO NOTHING。
    //    挿入できなければ処理済み（webhook リトライ等）とみなして即 return。
    //    ただし宛先解決の失敗で何も送らなかった行（failed / resolve_error）は取り直して送り直す。
    // --------------------------------------------------------
    const { data: inserted, error: insertError } = await supabaseAdmin
      .from('notification_logs')
      .upsert(
        { user_id: userId, kind, dedup_key: dedupKey, title, body, status: 'pending' },
        { onConflict: 'dedup_key', ignoreDuplicates: true }, // → INSERT ... ON CONFLICT (dedup_key) DO NOTHING
      )
      .select('id')

    if (insertError) {
      // ログ挿入失敗で通知自体を止めない（冪等性は失われるが通知欠落より軽微）
      console.error('[push] Failed to insert notification log:', insertError)
    } else if (!inserted || inserted.length === 0) {
      if (!(await reclaimUnsentLog(supabaseAdmin, dedupKey, title, body))) {
        console.log('[push] Duplicate dedup_key, skipping:', dedupKey)
        return
      }
      console.log('[push] Resending notification that failed before sending (resolve_error):', dedupKey)
    }

    const finalize = (status: LogStatus, detail: string) =>
      updateLog(supabaseAdmin, dedupKey, status, detail)

    // --------------------------------------------------------
    // 2. notification_preferences: 行が無ければ有効（デフォルトON）
    //    select は postgrest-js の内部再試行を切り、再試行を withRetry に一本化する（retry.ts 参照）
    // --------------------------------------------------------
    const { data: pref, error: prefError } = await withRetry(
      () =>
        supabaseAdmin
          .from('notification_preferences')
          .select('enabled, quiet_hours_start, quiet_hours_end')
          .eq('user_id', userId)
          .eq('kind', kind)
          .maybeSingle()
          .retry(false),
      readRetry('notification_preferences select'),
    )

    if (prefError) {
      // 設定取得失敗は「有効」扱いで続行（安全側 = 通知を落とさない）
      console.error('[push] Failed to fetch notification preferences:', prefError)
    } else if (pref) {
      if (pref.enabled === false) {
        await finalize('skipped', 'disabled')
        return
      }
      if (
        pref.quiet_hours_start != null &&
        pref.quiet_hours_end != null &&
        isWithinQuietHours(pref.quiet_hours_start, pref.quiet_hours_end, jstSecondsOfDay())
      ) {
        await finalize('skipped', 'quiet_hours')
        return
      }
    }

    // --------------------------------------------------------
    // 3. 宛先解決: device_tokens 優先、0件なら fcm_token フォールバック（stage2 両読み）
    // --------------------------------------------------------
    const resolved = await resolveTargets(supabaseAdmin, userId, userType, readRetry)

    if (!resolved.ok) {
      // 読み取りの失敗で宛先の有無を判断できなかった。端末未登録（no_tokens）とは区別して failed で記録し、
      // 同じ dedup_key の再呼び出しで送り直せるようにする（reclaimUnsentLog）
      await finalize('failed', RESOLVE_ERROR_DETAIL)
      return
    }

    const targets = resolved.targets
    if (targets.length === 0) {
      await finalize('skipped', 'no_tokens')
      return
    }

    // --------------------------------------------------------
    // 4. FCM 送信（ios / android）
    // --------------------------------------------------------
    const fcmTargets = targets.filter((t) => t.platform === 'ios' || t.platform === 'android')
    const webPushTargets = targets.filter((t) => t.platform === 'web_push')

    const outcomes: SendOutcome[] = []
    const notes: string[] = []
    let envSkipped = 0

    if (fcmTargets.length > 0) {
      const auth = await getFcmAccessToken()
      if (auth.status === 'no_key') {
        // FIREBASE_SERVICE_ACCOUNT_KEY 未設定なら skip（既存挙動を踏襲）
        envSkipped += fcmTargets.length
        notes.push('fcm:skipped(no_service_account_key)')
      } else if (auth.status === 'error') {
        outcomes.push(...fcmTargets.map((): SendOutcome => 'failed'))
        notes.push('fcm:oauth_failed')
      } else {
        // アクセストークンは複数トークン送信間で再利用
        for (const target of fcmTargets) {
          const outcome = await sendFcmToToken(auth, target.token, title, body, data)
          outcomes.push(outcome)
          if (outcome === 'invalid') {
            await cleanupInvalidTarget(supabaseAdmin, target, userId, userType)
          }
        }
      }
    }

    // --------------------------------------------------------
    // 5. Web Push 送信（web_push）
    // --------------------------------------------------------
    if (webPushTargets.length > 0) {
      const vapid = getVapidConfig()
      if (!vapid) {
        // VAPID 環境変数未設定なら web_push はスキップし detail に記録
        envSkipped += webPushTargets.length
        notes.push('web_push:skipped(vapid_not_configured)')
      } else {
        for (const target of webPushTargets) {
          const outcome = await sendWebPushToTarget(vapid, target, title, body, data)
          outcomes.push(outcome)
          if (outcome === 'invalid') {
            await cleanupInvalidTarget(supabaseAdmin, target, userId, userType)
          }
        }
      }
    }

    // --------------------------------------------------------
    // 6. 結果記録
    // --------------------------------------------------------
    const sent = outcomes.filter((o) => o === 'sent').length
    const invalid = outcomes.filter((o) => o === 'invalid').length
    const failed = outcomes.length - sent // invalid も失敗として数える

    const detailParts = [`sent=${sent}/${targets.length}`]
    if (invalid > 0) detailParts.push(`invalid_cleaned=${invalid}`)
    if (failed - invalid > 0) detailParts.push(`failed=${failed - invalid}`)
    detailParts.push(...notes)
    const detail = detailParts.join(' ')

    let status: LogStatus
    if (sent > 0 && failed === 0 && envSkipped === 0) {
      status = 'sent'
    } else if (sent > 0) {
      status = 'partial'
    } else if (failed > 0) {
      status = 'failed'
    } else {
      // 送信試行ゼロ（全宛先が環境変数未設定でスキップ）
      status = 'skipped'
    }

    await finalize(status, detail)
  } catch (e) {
    // 呼び出し元（タグ解析等）を絶対に失敗させない: 例外はここで握りつぶす
    console.error('[push] sendNotification failed:', e)
    try {
      const message = e instanceof Error ? e.message : String(e)
      await updateLog(supabaseAdmin, dedupKey, 'failed', `exception: ${message}`)
    } catch (logError) {
      console.error('[push] Failed to record failure status:', logError)
    }
  }
}

// ============================================================
// 内部型・共通ヘルパー
// ============================================================

type LogStatus = 'pending' | 'sent' | 'partial' | 'failed' | 'skipped'
type SendOutcome = 'sent' | 'failed' | 'invalid'

interface PushTarget {
  /** device_tokens.id。フォールバック（clients/trainers.fcm_token）由来は null */
  deviceTokenId: string | null
  platform: 'ios' | 'android' | 'web_push'
  /** FCM 登録トークン。web_push の場合は Push Subscription の endpoint URL */
  token: string
  webPushP256dh: string | null
  webPushAuth: string | null
}

async function updateLog(
  supabaseAdmin: SupabaseClient,
  dedupKey: string,
  status: LogStatus,
  detail: string,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from('notification_logs')
    .update({ status, detail })
    .eq('dedup_key', dedupKey)
  if (error) {
    console.error('[push] Failed to update notification log:', error)
  }
}

/**
 * dedup_key の行が既にあるとき、それが「宛先解決に失敗して何も送っていない行」
 * （status='failed' かつ detail=RESOLVE_ERROR_DETAIL）なら pending に戻して取り直す。取り直せたら true。
 *
 * - 条件付き UPDATE なので、同じキーで同時に呼ばれても取り直せるのは1つだけ（残りは重複としてスキップ）
 * - 送信済み・partial・設定による skipped・送信を試みた failed の行は条件に合わず、従来どおり重複扱い
 * - 取り直しに失敗したら二重送信を避ける側に倒して重複扱いにする（UPDATE なので再試行もしない。
 *   失敗扱いの試行が反映済みだと、再試行では 0 行になり pending のまま残るため）
 */
async function reclaimUnsentLog(
  supabaseAdmin: SupabaseClient,
  dedupKey: string,
  title: string,
  body: string,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('notification_logs')
    .update({ status: 'pending', detail: null, title, body })
    .eq('dedup_key', dedupKey)
    .eq('status', 'failed')
    .eq('detail', RESOLVE_ERROR_DETAIL)
    .select('id')
  if (error) {
    console.error('[push] Failed to reclaim notification log:', error)
    return false
  }
  return (data?.length ?? 0) > 0
}

/** 宛先解決の結果。読み取りに失敗して宛先の有無を判断できなかったときは ok: false */
type ResolveResult = { ok: true; targets: PushTarget[] } | { ok: false }

/**
 * 宛先トークンを解決する。
 * device_tokens の全行を優先し、0件のときのみ clients/trainers.fcm_token を読む。
 * どちらの読み取りも一時障害は再試行し（readRetry）、それでも読めなかった場合は
 * 「端末なし」と区別して ok: false を返す:
 *   - device_tokens が読めず、fcm_token も空 → ok: false（device_tokens に端末があるかもしれない）
 *   - device_tokens が読めず、fcm_token はある → そのトークンへ送る（通知を落とさない側に倒す）
 *   - fcm_token が読めない → ok: false
 *
 * NOTE: fcm_token フォールバックは stage2（両読み）期間の暫定措置。
 *       stage3（device_tokens 単独）移行時にフォールバック部分ごと削除する。
 *       フォールバック由来のトークンは platform='ios' 相当（= FCM 経路）として扱う。
 */
async function resolveTargets(
  supabaseAdmin: SupabaseClient,
  userId: string,
  userType: 'client' | 'trainer',
  readRetry: (label: string) => RetryOptions,
): Promise<ResolveResult> {
  const { data: rows, error } = await withRetry(
    () =>
      supabaseAdmin
        .from('device_tokens')
        .select('id, platform, token, web_push_p256dh, web_push_auth')
        .eq('user_id', userId)
        .retry(false),
    readRetry('device_tokens select'),
  )

  if (error) {
    console.error('[push] Failed to fetch device_tokens:', error)
  } else if (rows && rows.length > 0) {
    return {
      ok: true,
      targets: rows.map((row) => ({
        deviceTokenId: row.id,
        platform: row.platform,
        token: row.token,
        webPushP256dh: row.web_push_p256dh,
        webPushAuth: row.web_push_auth,
      })),
    }
  }

  // stage2 フォールバック: 旧 fcm_token 単一カラム
  const table = userType === 'client' ? 'clients' : 'trainers'
  const idColumn = userType === 'client' ? 'client_id' : 'id'

  const { data: legacy, error: legacyError } = await withRetry(
    () =>
      supabaseAdmin
        .from(table)
        .select('fcm_token')
        .eq(idColumn, userId)
        .maybeSingle()
        .retry(false),
    readRetry(`${table}.fcm_token select`),
  )

  if (legacyError) {
    console.error(`[push] Failed to fetch legacy fcm_token from ${table}:`, legacyError)
    return { ok: false }
  }
  if (!legacy?.fcm_token) {
    return error ? { ok: false } : { ok: true, targets: [] }
  }

  return {
    ok: true,
    targets: [
      {
        deviceTokenId: null, // フォールバック由来の目印（掃除時は該当カラムを null 更新）
        platform: 'ios',
        token: legacy.fcm_token,
        webPushP256dh: null,
        webPushAuth: null,
      },
    ],
  }
}

/**
 * 無効トークンの DB 掃除。
 * - device_tokens 由来 → 該当行を DELETE
 * - フォールバック（fcm_token 単一カラム）由来 → 該当カラムを null に UPDATE
 */
async function cleanupInvalidTarget(
  supabaseAdmin: SupabaseClient,
  target: PushTarget,
  userId: string,
  userType: 'client' | 'trainer',
): Promise<void> {
  try {
    if (target.deviceTokenId) {
      const { error } = await supabaseAdmin
        .from('device_tokens')
        .delete()
        .eq('id', target.deviceTokenId)
      if (error) {
        console.error('[push] Failed to delete invalid device token:', error)
      } else {
        console.log('[push] Deleted invalid device token:', target.deviceTokenId)
      }
    } else {
      const table = userType === 'client' ? 'clients' : 'trainers'
      const idColumn = userType === 'client' ? 'client_id' : 'id'
      const { error } = await supabaseAdmin
        .from(table)
        .update({ fcm_token: null })
        .eq(idColumn, userId)
      if (error) {
        console.error(`[push] Failed to clear legacy fcm_token on ${table}:`, error)
      } else {
        console.log(`[push] Cleared invalid legacy fcm_token on ${table}:`, userId)
      }
    }
  } catch (e) {
    console.error('[push] Error cleaning up invalid token:', e)
  }
}

// ============================================================
// FCM HTTP v1（parse-message-tags/index.ts から移設。送信挙動は不変）
// ============================================================

type FcmAuthResult =
  | { status: 'no_key' }
  | { status: 'error' }
  | { status: 'ok'; accessToken: string; projectId: string }

/**
 * FIREBASE_SERVICE_ACCOUNT_KEY から RS256 JWT を手組みし、
 * Google OAuth2 でアクセストークンを取得する。
 * 取得したトークンは呼び出し側で複数デバイスへの送信に再利用する。
 */
async function getFcmAccessToken(): Promise<FcmAuthResult> {
  // 1. サービスアカウントキーを取得
  const serviceAccountKeyJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_KEY')
  if (!serviceAccountKeyJson) {
    console.log('[FCM] FIREBASE_SERVICE_ACCOUNT_KEY not set, skipping notification')
    return { status: 'no_key' }
  }

  try {
    const serviceAccount = JSON.parse(serviceAccountKeyJson)
    const projectId = serviceAccount.project_id

    // 2. JWT生成（RS256）
    const now = Math.floor(Date.now() / 1000)
    const header = { alg: 'RS256', typ: 'JWT' }
    const payload = {
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }

    // Base64URL encode
    const encode = (obj: unknown) => {
      const json = JSON.stringify(obj)
      const bytes = new TextEncoder().encode(json)
      return btoa(String.fromCharCode(...bytes))
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
    }

    const unsignedToken = `${encode(header)}.${encode(payload)}`

    // RS256署名（Deno Web Crypto API）
    const pemContents = serviceAccount.private_key
      .replace('-----BEGIN PRIVATE KEY-----', '')
      .replace('-----END PRIVATE KEY-----', '')
      .replace(/\n/g, '')

    const binaryDer = Uint8Array.from(atob(pemContents), (c: string) => c.charCodeAt(0))

    const cryptoKey = await crypto.subtle.importKey(
      'pkcs8',
      binaryDer,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    )

    const signature = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      cryptoKey,
      new TextEncoder().encode(unsignedToken),
    )

    const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

    const jwt = `${unsignedToken}.${signatureBase64}`

    // 3. Google OAuth2 アクセストークン取得
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    })

    const tokenData = await tokenResponse.json()
    if (!tokenData.access_token) {
      console.error('[FCM] Failed to get access token:', tokenData)
      return { status: 'error' }
    }

    return { status: 'ok', accessToken: tokenData.access_token, projectId }
  } catch (e) {
    console.error('[FCM] Error obtaining access token:', e)
    return { status: 'error' }
  }
}

/**
 * FCM HTTP v1 APIで単一トークンへ通知を送信する。
 * ペイロード構造（notification / data / android.channel_id / apns.aps）は
 * parse-message-tags の旧実装と同一（通知の見た目を変えない）。
 */
async function sendFcmToToken(
  auth: { accessToken: string; projectId: string },
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<SendOutcome> {
  try {
    // 4. FCM HTTP v1 APIで通知送信
    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${auth.projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${auth.accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body },
            data,
            android: {
              priority: 'high',
              notification: {
                channel_id: 'high_importance_channel',
              },
            },
            apns: {
              payload: {
                aps: {
                  alert: { title, body },
                  sound: 'default',
                  badge: 1,
                },
              },
            },
          },
        }),
      },
    )

    const fcmResult = await fcmResponse.json()

    if (!fcmResponse.ok) {
      console.error('[FCM] Error sending notification:', fcmResult)
      // UNREGISTERED or NOT_FOUND → トークン無効。呼び出し側で DB から掃除する
      // deno-lint-ignore no-explicit-any
      const isInvalidToken = fcmResult?.error?.details?.some((d: any) =>
        d.errorCode === 'UNREGISTERED' || d.errorCode === 'NOT_FOUND'
      ) || fcmResult?.error?.status === 'NOT_FOUND'
      if (isInvalidToken) {
        console.log('[FCM] Token is invalid, will be cleared from DB')
        return 'invalid'
      }
      return 'failed'
    }

    console.log('[FCM] Notification sent successfully:', fcmResult)
    return 'sent'
  } catch (e) {
    console.error('[FCM] Error sending notification:', e)
    return 'failed'
  }
}

// ============================================================
// Web Push（VAPID / npm:web-push）
// ============================================================

interface VapidConfig {
  subject: string
  publicKey: string
  privateKey: string
}

function getVapidConfig(): VapidConfig | null {
  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY')
  const privateKey = Deno.env.get('VAPID_PRIVATE_KEY')
  const subject = Deno.env.get('VAPID_SUBJECT')
  if (!publicKey || !privateKey || !subject) {
    console.log('[WebPush] VAPID env vars not fully configured, skipping web push')
    return null
  }
  return { subject, publicKey, privateKey }
}

// web-push は web_push 宛先があるときのみ遅延ロード（FCM のみの環境で npm 依存を持ち込まない）
// deno-lint-ignore no-explicit-any
let webPushModule: any = null

// deno-lint-ignore no-explicit-any
async function getWebPush(): Promise<any> {
  if (!webPushModule) {
    const mod = await import('npm:web-push@3.6.7')
    webPushModule = mod.default ?? mod
  }
  return webPushModule
}

/**
 * Web Push で単一購読へ通知を送信する。
 * endpoint = device_tokens.token、keys = {p256dh, auth}。
 * 410 Gone / 404 Not Found は購読失効 → 呼び出し側で device_tokens 行を DELETE。
 */
async function sendWebPushToTarget(
  vapid: VapidConfig,
  target: PushTarget,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<SendOutcome> {
  if (!target.webPushP256dh || !target.webPushAuth) {
    console.error('[WebPush] Missing p256dh/auth keys for subscription, skipping:', target.deviceTokenId)
    return 'failed'
  }

  try {
    const webpush = await getWebPush()
    await webpush.sendNotification(
      {
        endpoint: target.token,
        keys: {
          p256dh: target.webPushP256dh,
          auth: target.webPushAuth,
        },
      },
      JSON.stringify({ title, body, data }),
      {
        vapidDetails: {
          subject: vapid.subject,
          publicKey: vapid.publicKey,
          privateKey: vapid.privateKey,
        },
      },
    )
    console.log('[WebPush] Notification sent successfully')
    return 'sent'
  } catch (e) {
    // web-push は WebPushError（statusCode 付き）を投げる
    // deno-lint-ignore no-explicit-any
    const statusCode = (e as any)?.statusCode
    if (statusCode === 404 || statusCode === 410) {
      console.log('[WebPush] Subscription expired (status', statusCode, '), will be cleared from DB')
      return 'invalid'
    }
    console.error('[WebPush] Error sending notification:', e)
    return 'failed'
  }
}
