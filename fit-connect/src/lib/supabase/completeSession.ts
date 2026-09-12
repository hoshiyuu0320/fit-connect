import { supabase } from '@/lib/supabase';
import { updateTicket } from '@/lib/supabase/updateTicket';

/**
 * チケットを1回分消化する（remaining_sessions を 1 減らす）
 *
 * - 残回数は呼び出し時点の DB の値を読む（画面側で保持している古い残数に依存しない）
 * - 残回数が 0 以下なら何もしない（マイナスにはしない）
 * - RLS により自分のチケット以外は見えない。見つからなければ消化せず戻る
 *   （消化できなかったことは console に残す）
 *
 * セッション完了に伴う減算は必ずここを通すこと（減算ロジックを画面ごとに持たない）。
 */
export const consumeTicketSession = async (ticketId: string): Promise<void> => {
  const { data, error } = await supabase
    .from('tickets')
    .select('id, remaining_sessions')
    .eq('id', ticketId)
    .maybeSingle();

  if (error) {
    console.error('Error fetching ticket for consumption:', error);
    throw error;
  }

  if (!data) {
    console.warn('消化対象のチケットが見つかりません:', ticketId);
    return;
  }

  const remaining = data.remaining_sessions as number;
  if (remaining <= 0) return;

  await updateTicket({
    id: ticketId,
    remaining_sessions: remaining - 1,
  });
};

/**
 * セッションを完了にする（紐づくチケットの消化を含む）
 *
 * 1. status を completed に更新する。ただし「まだ completed でない行」だけを対象にする
 *    条件付き UPDATE にし、更新できた行が返ったときだけ次へ進む
 *    （読んでから書く方式だと、2箇所からほぼ同時に完了させたときに両方が
 *      「未完了」を読んでチケットを二重に消化しうる。UPDATE 自体に条件を付ければ
 *      DB 側で必ず片方しか通らない）
 * 2. 更新できた行に ticket_id があれば consumeTicketSession で 1 回分消化
 *
 * ワークアウト実施画面（SessionTab）の「完了として保存」から呼ぶ。
 * スケジュール側（SessionModal）は自前でフォームの値から更新するため、
 * こちらは呼ばず consumeTicketSession だけを共有する。
 */
export const completeSession = async (sessionId: string): Promise<void> => {
  // 「未完了の行だけ」を completed にする。既に completed なら 0 行更新で data は null
  const { data, error } = await supabase
    .from('sessions')
    .update({ status: 'completed', updated_at: new Date().toISOString() })
    .eq('id', sessionId)
    .neq('status', 'completed')
    .select('id, ticket_id')
    .maybeSingle();

  if (error) {
    console.error('Error completing session:', error);
    throw error;
  }

  // 既に完了済み（または RLS で見えない）→ 何もしない。ここで戻ることでチケットの二重消化を防ぐ
  if (!data) return;

  if (data.ticket_id) {
    await consumeTicketSession(data.ticket_id as string);
  }
};
