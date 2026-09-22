import { create } from 'zustand'
import { getTriageBadgeCount } from '@/lib/supabase/getTriageBadgeCount'
import { nextTriageBadgeCount } from '@/lib/triage/triageLoadState'

type TriageBadgeState = {
  /** 「今日の対応」に並ぶ顧客の数（サイドバー「ダッシュボード」のバッジ） */
  count: number
  /**
   * count がアラートと未返信の両方を取れた数え直しに基づくか。
   * 一部だけ取れたときに、前の値を残すか取れた分を出すかの判断に使う（nextTriageBadgeCount）
   */
  complete: boolean
  /**
   * サーバーから数え直す。両方とも失敗したら前の値のまま残し、一部だけ失敗したら nextTriageBadgeCount で決める。
   * 呼ぶのは、レイアウトの表示時・pathname の変化・タブに戻ったとき・「今日の対応」の操作の後・
   * メッセージ画面で返信を送った後。Realtime は使わない（アラートの検知は1日1回。未返信は上の契機で取り直す）
   */
  refresh: () => Promise<void>
  /**
   * 0 に戻し、処理中の数え直しの結果も捨てる。ログアウトのときに呼ぶ
   * （クライアント側の遷移ではストアが残るので、次にログインしたアカウントに前の人数を出さない）
   */
  reset: () => void
}

// 数え直しが重なったときは、後から始めた分の結果だけを反映する（古い応答で数を戻さない）
let latestRequestId = 0

/**
 * 「今日の対応」のバッジの数。
 * 表示のたびにサーバーから取り直す値なので persist しない（古い数を localStorage から出さない）。
 */
export const useTriageBadgeStore = create<TriageBadgeState>((set) => ({
  count: 0,
  complete: false,
  refresh: async () => {
    const requestId = ++latestRequestId
    try {
      const result = await getTriageBadgeCount()
      if (requestId === latestRequestId) {
        set((state) => nextTriageBadgeCount(state, result))
      }
    } catch {
      // 前の値のまま残す（エラーの内容は getTriageBadgeCount が console に出している）
    }
  },
  reset: () => {
    latestRequestId++
    set({ count: 0, complete: false })
  },
}))
