import { supabase } from '@/lib/supabase'
import {
  buildNoteLinkOptions,
  type ClientSessionOption,
  type SessionRow,
} from '@/lib/sessions/noteLinkOptions'

// カルテの「対象セッション」セレクト用のセッション情報（紐づき済み判定を含む）
export type { ClientSessionOption }

/**
 * 1クライアントあたりの取得上限
 *
 * PostgREST の `max_rows` は既定 1000 で、無指定だと黙って切り捨てられる。
 * 切り捨てられたことに気付けるよう明示的に上限を置く。
 * この上限に達するほどセッションが多いクライアントでは、
 * 古い方から溢れて選択肢に出なくなり、
 * 溢れた分の has_note も落ちる（＝「カルテ作成済み」が出なくなる）。
 * 実運用の想定（週1〜2回 × 数年）では届かないため、
 * 本格的なページングは行っていない。
 */
const SESSION_FETCH_LIMIT = 1000

/**
 * 指定クライアントの「カルテを書ける」セッション一覧を新しい順で取得
 *
 * - 対象は `completed`、または過去日時かつ `cancelled` 以外（判定は buildNoteLinkOptions）
 * - 各セッションに「既にカルテが紐づいているか」を付ける
 * - RLS により自分が担当するセッション／自分が書いたカルテのみ返る
 *   （カルテ有無は共有・非共有を問わず見える）
 */
export const getClientSessions = async (clientId: string): Promise<ClientSessionOption[]> => {
  const { data, error } = await supabase
    .from('sessions')
    .select('id, session_date, session_type, status')
    .eq('client_id', clientId)
    .neq('status', 'cancelled')
    .order('session_date', { ascending: false })
    .limit(SESSION_FETCH_LIMIT)

  if (error) {
    console.error('セッション一覧取得エラー：', error)
    throw error
  }

  const notedSessionIds = await getNotedSessionIds(clientId)

  return buildNoteLinkOptions((data ?? []) as SessionRow[], notedSessionIds)
}

/**
 * 既にカルテが紐づいている session_id
 *
 * これは選択肢のラベルに「（カルテ作成済み）」を付けるための装飾用データ。
 * ここで throw すると選択肢そのものが出せなくなり、
 * 「対象セッションが選べないまま紐づけ無しで保存される」という
 * より悪い結果になるため、失敗しても空扱いで続行する
 * （＝重複の注意書きが出ないだけで、セッションは選べる）。
 */
const getNotedSessionIds = async (clientId: string): Promise<string[]> => {
  const { data, error } = await supabase
    .from('client_notes')
    .select('session_id')
    .eq('client_id', clientId)
    .not('session_id', 'is', null)
    .limit(SESSION_FETCH_LIMIT)

  if (error) {
    console.error('カルテ紐づけ取得エラー（「カルテ作成済み」表示のみ省略します）：', error)
    return []
  }

  return (data ?? []).map((row) => row.session_id as string)
}
