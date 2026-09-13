import { create } from 'zustand'
import { getTriageBadgeCount } from '@/lib/supabase/getTriageBadgeCount'

type TriageBadgeState = {
  /** 「今日の対応」に並ぶ顧客の数（サイドバー「ダッシュボード」のバッジ） */
  count: number
  /**
   * サーバーから数え直す。失敗したら前の値のまま残す。
   * 呼ぶのは、レイアウトの表示時・pathname の変化・タブに戻ったとき・「今日の対応」の操作の後
   * （検知は1日1回なので Realtime は使わない）
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
  refresh: async () => {
    const requestId = ++latestRequestId
    try {
      const count = await getTriageBadgeCount()
      if (requestId === latestRequestId) {
        set({ count })
      }
    } catch {
      // 前の値のまま残す（エラーの内容は getTriageBadgeCount が console に出している）
    }
  },
  reset: () => {
    latestRequestId++
    set({ count: 0 })
  },
}))
