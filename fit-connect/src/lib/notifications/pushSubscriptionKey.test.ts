import { describe, it, expect } from 'vitest'
import {
  VAPID_PUBLIC_KEY_BYTES,
  compareApplicationServerKey,
  decodeVapidPublicKey,
  urlBase64ToUint8Array,
} from './pushSubscriptionKey'

/** テスト用: バイト列 → base64url（パディング無し） */
function toBase64Url(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** 65 バイトのテスト用の鍵（先頭は非圧縮点の 0x04。base64url に '-' と '_' が出るバイトを含める） */
function makeKey(): Uint8Array {
  const key = new Uint8Array(VAPID_PUBLIC_KEY_BYTES)
  for (let i = 0; i < key.length; i++) key[i] = (i * 53 + 7) % 256
  key[0] = 0x04
  key[1] = 0xfb
  key[2] = 0xff
  key[3] = 0xbf
  return key
}

const KEY = makeKey()
const KEY_B64URL = toBase64Url(KEY)

/** ArrayBuffer として切り出したコピー（PushSubscription.options.applicationServerKey と同じ形） */
function asArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.slice().buffer
}

describe('テストの前提', () => {
  it('window の無い Node で動き、テスト用の鍵の base64url に - と _ が含まれる', () => {
    expect(typeof (globalThis as { window?: unknown }).window).toBe('undefined')
    expect(KEY_B64URL).toMatch(/[-_]/)
    expect(KEY_B64URL).not.toMatch(/[+/=]/)
  })
})

describe('urlBase64ToUint8Array', () => {
  it('パディング無しの base64url をバイト列に戻す', () => {
    expect(Array.from(urlBase64ToUint8Array(KEY_B64URL))).toEqual(Array.from(KEY))
  })

  it('読めない文字列では例外を投げる', () => {
    expect(() => urlBase64ToUint8Array('!!!!')).toThrow()
  })
})

describe('decodeVapidPublicKey', () => {
  it('65 バイトの鍵を読む', () => {
    expect(Array.from(decodeVapidPublicKey(KEY_B64URL) ?? [])).toEqual(Array.from(KEY))
  })

  it.each([
    ['空文字', ''],
    ['undefined', undefined],
    ['null', null],
    ['引用符つき', `"${KEY_B64URL}"`],
    ['前後に空白', ` ${KEY_B64URL} `],
    ['base64url でない文字', `${KEY_B64URL.slice(0, -1)}!`],
    ['64 バイト', toBase64Url(KEY.slice(0, 64))],
    ['66 バイト', toBase64Url(new Uint8Array([...KEY, 1]))],
  ])('%s → null（例外にしない）', (_label, value) => {
    expect(decodeVapidPublicKey(value as string | null | undefined)).toBeNull()
  })
})

describe('compareApplicationServerKey', () => {
  it('同じ鍵（ArrayBuffer）→ same', () => {
    expect(compareApplicationServerKey(asArrayBuffer(KEY), KEY_B64URL)).toBe('same')
  })

  it('同じ鍵（Uint8Array のビュー）→ same', () => {
    const padded = new Uint8Array(KEY.length + 8)
    padded.set(KEY, 4)
    const view = new Uint8Array(padded.buffer, 4, KEY.length)
    expect(compareApplicationServerKey(view, KEY_B64URL)).toBe('same')
  })

  it('1 バイト違い → different', () => {
    const other = KEY.slice()
    other[64] = (other[64] + 1) % 256
    expect(compareApplicationServerKey(asArrayBuffer(other), KEY_B64URL)).toBe('different')
  })

  it('長さ違い（64 バイト）→ different', () => {
    expect(compareApplicationServerKey(asArrayBuffer(KEY.slice(0, 64)), KEY_B64URL)).toBe('different')
  })

  it.each([
    ['購読の鍵が null', null, KEY_B64URL],
    ['購読の鍵が undefined', undefined, KEY_B64URL],
    ['購読の鍵が空', new ArrayBuffer(0), KEY_B64URL],
    ['環境変数が空', asArrayBuffer(KEY), ''],
    ['環境変数が undefined', asArrayBuffer(KEY), undefined],
    ['環境変数が引用符つき', asArrayBuffer(KEY), `"${KEY_B64URL}"`],
    ['環境変数が 65 バイトでない', asArrayBuffer(KEY), toBase64Url(KEY.slice(0, 32))],
    ['環境変数が base64url として読めない', asArrayBuffer(KEY), '%%%%'],
  ])('%s → unknown（different にしない）', (_label, subscriptionKey, envKey) => {
    expect(
      compareApplicationServerKey(
        subscriptionKey as ArrayBuffer | null | undefined,
        envKey as string | undefined,
      ),
    ).toBe('unknown')
  })
})
