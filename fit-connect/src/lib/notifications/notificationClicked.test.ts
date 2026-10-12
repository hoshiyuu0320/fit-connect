import { describe, it, expect, vi, afterEach } from 'vitest'
import { isNotificationClickedMessage, subscribeNotificationClicked } from './notificationClicked'

describe('isNotificationClickedMessage', () => {
  it('type が notification-clicked のときだけ true', () => {
    expect(isNotificationClickedMessage({ type: 'notification-clicked', url: '/dashboard' })).toBe(true)
    expect(isNotificationClickedMessage({ type: 'other' })).toBe(false)
    expect(isNotificationClickedMessage('notification-clicked')).toBe(false)
    expect(isNotificationClickedMessage(null)).toBe(false)
    expect(isNotificationClickedMessage(undefined)).toBe(false)
  })
})

describe('subscribeNotificationClicked', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('serviceWorker が無ければ何もしない（外す関数は呼べる）', () => {
    vi.stubGlobal('navigator', {})
    const onClicked = vi.fn()
    const unsubscribe = subscribeNotificationClicked(onClicked)
    expect(() => unsubscribe()).not.toThrow()
    expect(onClicked).not.toHaveBeenCalled()
  })

  it('notification-clicked を受けたら呼び、他のメッセージでは呼ばない。外したら呼ばない', () => {
    const target = new EventTarget()
    vi.stubGlobal('navigator', { serviceWorker: target })
    const onClicked = vi.fn()
    const unsubscribe = subscribeNotificationClicked(onClicked)

    target.dispatchEvent(new MessageEvent('message', { data: { type: 'other' } }))
    expect(onClicked).not.toHaveBeenCalled()

    target.dispatchEvent(new MessageEvent('message', { data: { type: 'notification-clicked', url: '/dashboard' } }))
    expect(onClicked).toHaveBeenCalledTimes(1)

    unsubscribe()
    target.dispatchEvent(new MessageEvent('message', { data: { type: 'notification-clicked' } }))
    expect(onClicked).toHaveBeenCalledTimes(1)
  })
})
