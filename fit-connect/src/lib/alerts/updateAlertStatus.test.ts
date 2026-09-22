import { describe, it, expect, vi, afterEach } from 'vitest'
import { updateAlertStatus, AlertUpdateError } from '@/lib/alerts/updateAlertStatus'

const fetchMock = vi.fn()

afterEach(() => {
  fetchMock.mockReset()
  vi.unstubAllGlobals()
})

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })

describe('updateAlertStatus', () => {
  it('PATCH /api/alerts/<id> に action だけを送り、今の status を返す', async () => {
    vi.stubGlobal('fetch', fetchMock)
    fetchMock.mockResolvedValue(
      jsonResponse({ status: 'ok', alert: { id: 'alert-1', status: 'acknowledged' } })
    )

    expect(await updateAlertStatus('alert-1', 'acknowledge')).toEqual({
      id: 'alert-1',
      status: 'acknowledged',
    })
    expect(fetchMock).toHaveBeenCalledWith('/api/alerts/alert-1', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'acknowledge' }),
    })
  })

  it('id はパスに入れる前にエンコードする', async () => {
    vi.stubGlobal('fetch', fetchMock)
    fetchMock.mockResolvedValue(jsonResponse({ status: 'ok', alert: { id: 'a/b', status: 'open' } }))
    await updateAlertStatus('a/b', 'reopen')
    expect(fetchMock.mock.calls[0][0]).toBe('/api/alerts/a%2Fb')
  })

  it('非 2xx は AlertUpdateError（HTTP ステータス付き）', async () => {
    vi.stubGlobal('fetch', fetchMock)
    fetchMock.mockResolvedValue(jsonResponse({ error: 'NOT_FOUND' }, 404))
    const error = await updateAlertStatus('alert-1', 'acknowledge').catch((e: unknown) => e)
    expect(error).toBeInstanceOf(AlertUpdateError)
    expect((error as AlertUpdateError).status).toBe(404)
  })

  it('想定外のレスポンスも失敗として扱う', async () => {
    vi.stubGlobal('fetch', fetchMock)
    fetchMock.mockResolvedValue(jsonResponse({ status: 'ok' }))
    await expect(updateAlertStatus('alert-1', 'acknowledge')).rejects.toBeInstanceOf(
      AlertUpdateError
    )
  })

  it('通信エラーはそのまま throw する', async () => {
    vi.stubGlobal('fetch', fetchMock)
    fetchMock.mockRejectedValue(new TypeError('Failed to fetch'))
    await expect(updateAlertStatus('alert-1', 'reopen')).rejects.toBeInstanceOf(TypeError)
  })
})
