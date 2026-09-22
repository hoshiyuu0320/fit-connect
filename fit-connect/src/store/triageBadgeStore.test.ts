import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  getTriageBadgeCount: vi.fn(),
}))

vi.mock('@/lib/supabase/getTriageBadgeCount', () => ({
  getTriageBadgeCount: mocks.getTriageBadgeCount,
}))

import { useTriageBadgeStore } from '@/store/triageBadgeStore'

/** 外から resolve できる Promise */
function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((res) => {
    resolve = res
  })
  return { promise, resolve }
}

beforeEach(() => {
  mocks.getTriageBadgeCount.mockReset()
  useTriageBadgeStore.setState({ count: 0 })
})

describe('triageBadgeStore', () => {
  it('refresh でサーバーの数に揃える', async () => {
    mocks.getTriageBadgeCount.mockResolvedValue(3)
    await useTriageBadgeStore.getState().refresh()
    expect(useTriageBadgeStore.getState().count).toBe(3)
  })

  it('取得に失敗したら前の値のまま', async () => {
    useTriageBadgeStore.setState({ count: 2 })
    mocks.getTriageBadgeCount.mockRejectedValue(new Error('network'))
    await useTriageBadgeStore.getState().refresh()
    expect(useTriageBadgeStore.getState().count).toBe(2)
  })

  it('重なったときは後から始めた分の結果だけを反映する（古い応答で戻さない）', async () => {
    const first = deferred<number>()
    const second = deferred<number>()
    mocks.getTriageBadgeCount
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise)

    const p1 = useTriageBadgeStore.getState().refresh()
    const p2 = useTriageBadgeStore.getState().refresh()
    second.resolve(1) // 対応済みの後の数え直し（新しい）
    await p2
    first.resolve(5) // 先に始めた古い数え直しが後から届く
    await p1

    expect(useTriageBadgeStore.getState().count).toBe(1)
  })

  it('reset で 0 に戻し、処理中の数え直しの結果も反映しない（ログアウト後に前のアカウントの数を出さない）', async () => {
    useTriageBadgeStore.setState({ count: 5 })
    const pending = deferred<number>()
    mocks.getTriageBadgeCount.mockReturnValueOnce(pending.promise)

    const p = useTriageBadgeStore.getState().refresh()
    useTriageBadgeStore.getState().reset()
    expect(useTriageBadgeStore.getState().count).toBe(0)

    pending.resolve(5) // ログアウト前に始めた数え直しが後から届く
    await p
    expect(useTriageBadgeStore.getState().count).toBe(0)
  })
})
