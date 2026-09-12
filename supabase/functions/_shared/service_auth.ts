/**
 * pg_cron / pg_net などサーバー間呼び出しの認証判定。
 *
 * 新しい secret キー（sb_secret_...）は JWT ではないため、呼び出し側は apikey ヘッダーで送り、
 * 関数側は verify_jwt=false にしてここで照合する（Supabase 公式の新 API キー移行ガイドの方針）。
 * - SUPABASE_SECRET_KEYS: 名前→キーの JSON オブジェクト（例 {"default":"sb_secret_..."}）
 * - SUPABASE_SECRET_KEY: キー1つの文字列（ローカルの CLI が渡すことがある）
 * auto-skip-workouts / cleanup-ai-images から利用する。
 */

/**
 * 長さを比べたうえで全文字を XOR で比較する定数時間比較。
 * 先頭からの一致文字数で応答時間が変わらないようにする（長さの違いは即 false）。
 */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return diff === 0
}

/**
 * 受け付ける secret キーの一覧を返す。
 * SUPABASE_SECRET_KEYS は値が文字列のものだけ採用し、parse できなければ無視する。
 * 空文字は除く。
 */
function acceptedSecretKeys(): string[] {
  const keys: string[] = []

  const json = Deno.env.get('SUPABASE_SECRET_KEYS')
  if (json) {
    try {
      const parsed: unknown = JSON.parse(json)
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        for (const value of Object.values(parsed)) {
          if (typeof value === 'string' && value.length > 0) keys.push(value)
        }
      }
    } catch {
      // 不正な JSON は無視する（SUPABASE_SECRET_KEY / 旧キーでの判定は続行）
    }
  }

  const single = Deno.env.get('SUPABASE_SECRET_KEY')
  if (single) keys.push(single)

  return keys
}

/**
 * サーバー（cron / 手動実行）からの呼び出しかを判定する。
 *
 * - apikey ヘッダーが受け付ける secret キーのどれかと一致すれば true
 * - 互換: Authorization が `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` と一致すれば true
 *   （ローカル開発と従来の呼び方のため。本番の SUPABASE_SERVICE_ROLE_KEY は Vault の旧キーと
 *    現状一致しないので本番では通らない。旧キーは 2026 年末で廃止されるため、その時点で削除する）
 */
export function isServiceRequest(req: Request): boolean {
  const apiKey = req.headers.get('apikey')
  if (apiKey && acceptedSecretKeys().some((key) => timingSafeEqual(apiKey, key))) {
    return true
  }

  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authHeader = req.headers.get('Authorization')
  if (serviceRoleKey && authHeader) {
    return timingSafeEqual(authHeader, `Bearer ${serviceRoleKey}`)
  }

  return false
}
