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
  useTriageBadgeStore.setState({ count: 0, complete: false })
})

const complete = (count: number) => ({ count, complete: true })
const partial = (count: number) => ({ count, complete: false })

describe('triageBadgeStore', () => {
  it('refresh でサーバーの数に揃える', async () => {
    mocks.getTriageBadgeCount.mockResolvedValue(complete(3))
    await useTriageBadgeStore.getState().refresh()
    expect(useTriageBadgeStore.getState().count).toBe(3)
    expect(useTriageBadgeStore.getState().complete).toBe(true)
  })

  it('取得に失敗したら前の値のまま', async () => {
    useTriageBadgeStore.setState({ count: 2, complete: true })
    mocks.getTriageBadgeCount.mockRejectedValue(new Error('network'))
    await useTriageBadgeStore.getState().refresh()
    expect(useTriageBadgeStore.getState().count).toBe(2)
  })

  it('表示直後の数え直しで未返信だけ失敗しても、取れたアラートの顧客の人数を出す（0 のまま消さない）', async () => {
    mocks.getTriageBadgeCount.mockResolvedValue(partial(2))
    await useTriageBadgeStore.getState().refresh()
    expect(useTriageBadgeStore.getState().count).toBe(2)
    expect(useTriageBadgeStore.getState().complete).toBe(false)
  })

  it('両方を取れた後の一部だけの失敗では、前の値を残す', async () => {
    mocks.getTriageBadgeCount.mockResolvedValueOnce(complete(3)).mockResolvedValueOnce(partial(1))
    await useTriageBadgeStore.getState().refresh()
    await useTriageBadgeStore.getState().refresh()
    expect(useTriageBadgeStore.getState().count).toBe(3)
  })

  it('重なったときは後から始めた分の結果だけを反映する（古い応答で戻さない）', async () => {
    const first = deferred<{ count: number; complete: boolean }>()
    const second = deferred<{ count: number; complete: boolean }>()
    mocks.getTriageBadgeCount
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise)

    const p1 = useTriageBadgeStore.getState().refresh()
    const p2 = useTriageBadgeStore.getState().refresh()
    second.resolve(complete(1)) // 対応済みの後の数え直し（新しい）
    await p2
    first.resolve(complete(5)) // 先に始めた古い数え直しが後から届く
    await p1

    expect(useTriageBadgeStore.getState().count).toBe(1)
  })

  it('reset で 0 に戻し、処理中の数え直しの結果も反映しない（ログアウト後に前のアカウントの数を出さない）', async () => {
    useTriageBadgeStore.setState({ count: 5, complete: true })
    const pending = deferred<{ count: number; complete: boolean }>()
    mocks.getTriageBadgeCount.mockReturnValueOnce(pending.promise)

    const p = useTriageBadgeStore.getState().refresh()
    useTriageBadgeStore.getState().reset()
    expect(useTriageBadgeStore.getState().count).toBe(0)
    expect(useTriageBadgeStore.getState().complete).toBe(false)

    pending.resolve(complete(5)) // ログアウト前に始めた数え直しが後から届く
    await p
    expect(useTriageBadgeStore.getState().count).toBe(0)
  })
})
