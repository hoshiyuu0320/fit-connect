import { describe, it, expect } from 'vitest'
import {
  clientIdFromNotificationUrl,
  decideNotificationOpen,
  hasMessageDraft,
  type MessageDraftState,
} from '@/lib/message/notificationOpen'

const CLIENT_ID = '0b6f8e1c-3a2d-4c5e-9f10-1234567890ab'
const OTHER_CLIENT_ID = '11111111-2222-4333-8444-555555555555'

describe('clientIdFromNotificationUrl', () => {
  it('/message?clientId=<uuid> の clientId を返す', () => {
    expect(clientIdFromNotificationUrl(`/message?clientId=${CLIENT_ID}`)).toBe(CLIENT_ID)
  })

  it('大文字の UUID は小文字にそろえる', () => {
    expect(clientIdFromNotificationUrl(`/message?clientId=${CLIENT_ID.toUpperCase()}`)).toBe(CLIENT_ID)
  })

  it('他のクエリ（&record=…）が付いていても clientId を読む', () => {
    expect(clientIdFromNotificationUrl(`/message?clientId=${CLIENT_ID}&record=sleep%3A7d`)).toBe(CLIENT_ID)
    expect(clientIdFromNotificationUrl(`/message?record=sleep%3A7d&clientId=${CLIENT_ID}`)).toBe(CLIENT_ID)
  })

  it('null・空文字は null', () => {
    expect(clientIdFromNotificationUrl(null)).toBeNull()
    expect(clientIdFromNotificationUrl('')).toBeNull()
  })

  it('clientId が無い・UUID の形でなければ null', () => {
    expect(clientIdFromNotificationUrl('/message')).toBeNull()
    expect(clientIdFromNotificationUrl('/message?clientId=')).toBeNull()
    expect(clientIdFromNotificationUrl('/message?clientId=alice')).toBeNull()
    expect(clientIdFromNotificationUrl(`/message?clientId=${CLIENT_ID}x`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/message?clientId=%20${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/message?client_id=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/message#clientId=${CLIENT_ID}`)).toBeNull()
  })

  it('パス名が厳密に /message でなければ null（末尾スラッシュ・別の画面も）', () => {
    expect(clientIdFromNotificationUrl(`/message/?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/messages?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/message/${CLIENT_ID}?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/dashboard?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/clients/${CLIENT_ID}?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`?clientId=${CLIENT_ID}`)).toBeNull()
  })

  it('絶対 URL・//host は null（自分のオリジンの相対パスとしてだけ読む）', () => {
    expect(clientIdFromNotificationUrl(`https://evil.example/message?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`//evil.example/message?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl(`/\\evil.example/message?clientId=${CLIENT_ID}`)).toBeNull()
    expect(clientIdFromNotificationUrl('javascript:alert(1)')).toBeNull()
  })

  it('解析できない値は null（例外を投げない）', () => {
    expect(clientIdFromNotificationUrl('http://[')).toBeNull()
    expect(clientIdFromNotificationUrl('//[')).toBeNull()
  })
})

describe('hasMessageDraft', () => {
  const EMPTY: MessageDraftState = {
    input: '',
    imageCount: 0,
    hasReply: false,
    hasRecordQuote: false,
    isEditing: false,
    isSending: false,
  }

  it('何も無ければ書きかけでない', () => {
    expect(hasMessageDraft(EMPTY)).toBe(false)
  })

  it('空白・改行・全角スペースだけの入力は書きかけでない', () => {
    expect(hasMessageDraft({ ...EMPTY, input: '   ' })).toBe(false)
    expect(hasMessageDraft({ ...EMPTY, input: ' \n\t ' })).toBe(false)
    expect(hasMessageDraft({ ...EMPTY, input: '　' })).toBe(false)
  })

  it('前後に空白があっても、文字があれば書きかけ', () => {
    expect(hasMessageDraft({ ...EMPTY, input: '  了解です \n' })).toBe(true)
  })

  it.each<[string, Partial<MessageDraftState>]>([
    ['入力', { input: 'こんにちは' }],
    ['画像', { imageCount: 1 }],
    ['返信先', { hasReply: true }],
    ['引用チップ', { hasRecordQuote: true }],
    ['編集中', { isEditing: true }],
    ['送信中', { isSending: true }],
  ])('%s だけでも書きかけ', (_label, patch) => {
    expect(hasMessageDraft({ ...EMPTY, ...patch })).toBe(true)
  })
})

describe('decideNotificationOpen', () => {
  // 別の顧客（OTHER_CLIENT_ID）を表示中に、一覧にある顧客（CLIENT_ID）の通知が来た
  const BASE = {
    targetClientId: CLIENT_ID,
    selectedClientId: OTHER_CLIENT_ID,
    isKnownClient: true,
    hasDraft: false,
  }

  it('書きかけが無ければ select', () => {
    expect(decideNotificationOpen(BASE)).toEqual({ action: 'select', clientId: CLIENT_ID })
  })

  it('書きかけがあれば hold（切り替えない）', () => {
    expect(decideNotificationOpen({ ...BASE, hasDraft: true })).toEqual({ action: 'hold', clientId: CLIENT_ID })
  })

  it('まだ誰も表示していなければ select（書きかけがあれば hold）', () => {
    expect(decideNotificationOpen({ ...BASE, selectedClientId: null })).toEqual({
      action: 'select',
      clientId: CLIENT_ID,
    })
    expect(decideNotificationOpen({ ...BASE, selectedClientId: null, hasDraft: true })).toEqual({
      action: 'hold',
      clientId: CLIENT_ID,
    })
  })

  it('開く顧客が無ければ none / no_target', () => {
    expect(decideNotificationOpen({ ...BASE, targetClientId: null })).toEqual({
      action: 'none',
      reason: 'no_target',
    })
  })

  it('その顧客を表示中なら none / already_selected', () => {
    expect(decideNotificationOpen({ ...BASE, selectedClientId: CLIENT_ID })).toEqual({
      action: 'none',
      reason: 'already_selected',
    })
  })

  it('一覧に無い顧客なら none / unknown_client', () => {
    expect(decideNotificationOpen({ ...BASE, isKnownClient: false })).toEqual({
      action: 'none',
      reason: 'unknown_client',
    })
  })

  describe('判定の順', () => {
    it('開く顧客が無ければ、誰も表示していなくても（null 同士でも）none / no_target', () => {
      expect(
        decideNotificationOpen({ targetClientId: null, selectedClientId: null, isKnownClient: false, hasDraft: true })
      ).toEqual({ action: 'none', reason: 'no_target' })
    })

    it('書きかけがあっても、表示中の顧客なら none / already_selected', () => {
      expect(decideNotificationOpen({ ...BASE, selectedClientId: CLIENT_ID, hasDraft: true })).toEqual({
        action: 'none',
        reason: 'already_selected',
      })
    })

    it('表示中の顧客なら、一覧に無くても none / already_selected', () => {
      expect(decideNotificationOpen({ ...BASE, selectedClientId: CLIENT_ID, isKnownClient: false })).toEqual({
        action: 'none',
        reason: 'already_selected',
      })
    })

    it('一覧に無ければ、書きかけがあっても none / unknown_client', () => {
      expect(decideNotificationOpen({ ...BASE, isKnownClient: false, hasDraft: true })).toEqual({
        action: 'none',
        reason: 'unknown_client',
      })
    })
  })
})
