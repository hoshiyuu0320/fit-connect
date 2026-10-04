# Web Push の土台（トレーナー向けアラート push の PR1）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 既存の Web Push を「トレーナーのブラウザにだけ、最後に登録したトレーナーへ、今の鍵で」届く状態に直し、PR2（朝のまとめ）の土台にする。

**Architecture:** 送信側は `_shared/push.ts` の宛先解決を `user_type` で絞る1行だけ。Web 側は、購読の鍵の照合と送り直しを純関数（`pushSubscriptionKey.ts` / `syncPushSubscription.ts`）に切り出して単体テストで固め、設定画面はそれを呼んで結果を表示するだけにする。購読の登録 API は `device_tokens` を主にして、同じ endpoint を持つ他のトレーナーの行を消す。DB の変更は無い。

**Tech Stack:** Next.js 15（App Router）/ TypeScript / vitest（`environment: 'node'`、React Testing Library は無い）/ Supabase Edge Functions（Deno、`npm:web-push@3.6.7`）

**Spec:** `docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md`（本計画は §15 の PR1。§6.3・§7.2 のうち PR1 の部分・§7.6・§11.1・§12 の PR1 行）

## Global Constraints

- 返答・コメント・UI の文言・コミットメッセージは日本語。UI の文言は下のタスクに書いた文字列を一字一句そのまま使う
- Web のコマンドは `fit-connect/` で `npx -y pnpm@10.32.1 ...` を使う（`npm` は lock が無くて失敗する）。テストは `npx -y pnpm@10.32.1 vitest run <ファイル>`、全体は `npx -y pnpm@10.32.1 test`
- 依存パッケージを足さない（`date-fns` なども新しい純関数モジュールでは import しない）
- `.env` / `.env.local` は開かない・コピーしない。VAPID の鍵の値をコミット・チャットに出さない
- 共有のローカル Supabase スタック `supabase_db_fit-connect`（ポート 54321〜54326）には書き込まない・reset しない。検証は scratch の隔離スタックで行う
- `main` / `develop/1.0.0` で作業しない。作業ブランチは `feature/web-push-foundation`（worktree `.claude/worktrees/web-push-foundation`）。素の `git stash` を使わない
- コミットメッセージの末尾は `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`（実装者が別モデルならそのモデル名）。push 前に `git reset --soft` で1コミットにまとめる（コントローラーが行う）
- 実装者はサブエージェントを起動しない（レビューはコントローラーが手配する）
- PR1 に migration は無い。`supabase db push` は誰も実行しない

## Review Focus

1. **Service Worker が未登録のブラウザ（初めて設定画面を開いた人）** — 設定画面の自動の登録し直しが `navigator.serviceWorker.ready`（SW が無いと永久に解決しない）を待つと、親トグルが `disabled` のまま戻らない。`getRegistration()` を使い、無ければ何もしない → Task 5 の実装と Task 7 の画面の確認
2. **React StrictMode（dev）の effect の2回実行** — 自動の登録し直しの POST / DELETE / `unsubscribe` が2回走らない → Task 5 の実装（通信の手前で `cancelled` を見る）と Task 7 の画面の確認（POST が1回）
3. **同じ endpoint を別のトレーナーが登録** — 前のトレーナーの `web_push` 行だけが消え、顧客の `ios` / `android` 行や自分の行は消えない → Task 4 のテスト（delete の条件の4つ）
4. **無効化で `DELETE /api/push-subscriptions` が 500** — ブラウザの購読を残し、トグルはオンのまま、エラー文が出る（今は `response.ok` を見ずに解除してしまう）→ Task 5 の実装と Task 7 の画面の確認（`fetch` を差し替えて 500 にする）
5. **Vercel の公開鍵が引用符つき・空・壊れている** — 比べられない（`unknown`）として送り直し、正常な購読を自動で解除しない → Task 2・Task 3 のテスト

---

## ファイル構成

| ファイル | 役割 | Task |
|---|---|---|
| `supabase/functions/_shared/push.ts`（変更） | `resolveTargets` の `device_tokens` を `user_type` で絞る | 1 |
| `fit-connect/src/lib/notifications/pushSubscriptionKey.ts`（新規） | base64url の変換・VAPID 公開鍵の読み取り・購読の鍵との比較（純関数） | 2 |
| `fit-connect/src/lib/notifications/pushSubscriptionKey.test.ts`（新規） | 上のテスト | 2 |
| `fit-connect/src/lib/notifications/syncPushSubscription.ts`（新規） | 設定画面を開いたときの「送り直す／解除する／何もしない」の分岐（依存を引数で受ける） | 3 |
| `fit-connect/src/lib/notifications/syncPushSubscription.test.ts`（新規） | 上のテスト | 3 |
| `fit-connect/src/lib/supabase/savePushSubscription.ts`（変更） | `device_tokens` を主に・同じ endpoint の他のトレーナーの行を消す・旧表の失敗は応答を失敗にしない | 4 |
| `fit-connect/src/lib/supabase/deletePushSubscription.ts`（変更） | `device_tokens` を主に（失敗を握りつぶさない）・旧表の失敗は応答を失敗にしない | 4 |
| `fit-connect/src/lib/supabase/savePushSubscription.test.ts`・`deletePushSubscription.test.ts`（新規） | `supabaseAdmin` を差し替えたテスト | 4 |
| `fit-connect/src/components/settings/NotificationSection.tsx`（変更） | 自動の登録し直し・鍵の照合の結果の表示・有効化/無効化の失敗の表示 | 5 |
| `docs/tasks/2026-07-19-webpush-vapid-setup.md`・`fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md`・`fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md`・`docs/tasks/IMPLEMENTATION_TASKS.md`（変更） | 手順書と進捗 | 6 |

Task 2 → 3 → 5 は順に依存する。Task 1・4・6 は独立。

**計画上の判断（設計書に明記の無い点）**
- 削除（`deletePushSubscription`）も `device_tokens` を主にし、`device_tokens` の失敗を握りつぶさない（設計書 §7.6「`device_tokens` が送信側の唯一の宛先になった今、失敗を黙って成功にしない」の趣旨に合わせる。§7.2 の「`DELETE` が失敗したらブラウザの購読を解除しない」が、`device_tokens` の失敗でも効くようにするため）。削除の対象（自分の行・endpoint 単位）は変えない
- 自動の登録し直しは、通知の許可が `granted` のときだけ設定画面のマウント時に1回走らせる（effect の依存は `trainerId` だけ。有効化の直後に二重に POST しない）

---

### Task 1: `push.ts` の宛先を `user_type` で絞る（設計書 §6.3）

**Files:**
- Modify: `supabase/functions/_shared/push.ts`（`resolveTargets` の JSDoc と `device_tokens` の select。行番号は 2026-10-04 時点で 302〜330 付近）

**Interfaces:**
- Consumes: なし
- Produces: `sendNotification` のシグネチャは変えない。挙動だけ「`device_tokens` は `user_type = args.userType` の行だけを宛先にする」に変わる

- [ ] **Step 1: `resolveTargets` の select に `user_type` の絞り込みを足す**

`resolveTargets` の中の次の部分を

```ts
      supabaseAdmin
        .from('device_tokens')
        .select('id, platform, token, web_push_p256dh, web_push_auth')
        .eq('user_id', userId)
        .retry(false),
```

次のように変える（`.eq('user_type', userType)` を1行足すだけ）。

```ts
      supabaseAdmin
        .from('device_tokens')
        .select('id, platform, token, web_push_p256dh, web_push_auth')
        .eq('user_id', userId)
        .eq('user_type', userType)
        .retry(false),
```

- [ ] **Step 2: `resolveTargets` の JSDoc の1行目の説明を直す**

```ts
/**
 * 宛先トークンを解決する。
 * device_tokens の全行を優先し、0件のときのみ clients/trainers.fcm_token を読む。
```

を

```ts
/**
 * 宛先トークンを解決する。
 * device_tokens のうち user_type が宛先の種別（userType）と同じ行を優先し、0件のときのみ clients/trainers.fcm_token を読む。
 * user_type で絞るのは、顧客とトレーナーを兼務するアカウント（同じ auth uid に clients 行と trainers 行がある）で、
 * トレーナー宛の通知が顧客用のスマホ（Mobile は常に user_type='client' で登録）に、
 * 顧客宛の通知がトレーナーのブラウザ（Web は常に user_type='trainer' で登録）に届かないようにするため。
```

に変える（以降の行はそのまま）。

- [ ] **Step 3: 型検査を通す**

Run（リポジトリのルートで）: `npx -y deno check supabase/functions/_shared/push.ts supabase/functions/parse-message-tags/index.ts supabase/functions/send-session-reminders/index.ts`
Expected: エラーなしで終わる（初回は esm.sh / npm の取得で時間がかかる）。ネットワークの都合で取得できないときは、その旨と出力をレポートに書く

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/_shared/push.ts
git commit -m "fix(supabase): Web Push / FCM の宛先を user_type で絞る（兼務アカウントへの誤配信を防ぐ）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 購読の鍵の照合（`pushSubscriptionKey.ts`。設計書 §7.2）

**Files:**
- Create: `fit-connect/src/lib/notifications/pushSubscriptionKey.ts`
- Test: `fit-connect/src/lib/notifications/pushSubscriptionKey.test.ts`

**Interfaces:**
- Consumes: なし
- Produces:
  - `export const VAPID_PUBLIC_KEY_BYTES = 65`
  - `export function urlBase64ToUint8Array(base64String: string): Uint8Array`（不正な入力では例外）
  - `export function decodeVapidPublicKey(value: string | null | undefined): Uint8Array | null`（例外を投げない）
  - `export type KeyComparison = 'same' | 'different' | 'unknown'`
  - `export function compareApplicationServerKey(subscriptionKey: ArrayBuffer | ArrayBufferView | null | undefined, vapidPublicKeyBase64Url: string | null | undefined): KeyComparison`

- [ ] **Step 1: 失敗するテストを書く**

`fit-connect/src/lib/notifications/pushSubscriptionKey.test.ts`:

```ts
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
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run（`fit-connect/` で）: `npx -y pnpm@10.32.1 vitest run src/lib/notifications/pushSubscriptionKey.test.ts`
Expected: FAIL（`./pushSubscriptionKey` が見つからない）

- [ ] **Step 3: 実装を書く**

`fit-connect/src/lib/notifications/pushSubscriptionKey.ts`:

```ts
/**
 * Web Push の購読の公開鍵（applicationServerKey）を扱う純関数。
 *
 * - ブラウザ専用の API（window）に依存しない。base64 の復号はグローバルの atob を使う
 *   （vitest は environment: 'node' で window が無い）
 * - 設定画面を開いたときの「購読が今の公開鍵で作られたか」の照合に使う（syncPushSubscription）
 */

/** VAPID 公開鍵（P-256 の非圧縮点）のバイト長 */
export const VAPID_PUBLIC_KEY_BYTES = 65

/** base64url（パディングは任意）だけを受け付ける。引用符・空白・'+' '/' を含むものは読めない扱い */
const BASE64URL_RE = /^[A-Za-z0-9_-]+={0,2}$/

/**
 * base64url の文字列をバイト列にする（pushManager.subscribe の applicationServerKey 用）。
 * 読めない文字列では例外を投げる（呼び出し側の try/catch で扱う）。
 */
export function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

/**
 * VAPID 公開鍵（base64url）を読む。65 バイトの鍵として読めなければ null（例外を投げない）。
 * 空・引用符つき・base64url でない・長さが違う、はすべて null。
 */
export function decodeVapidPublicKey(value: string | null | undefined): Uint8Array | null {
  if (typeof value !== 'string' || !BASE64URL_RE.test(value)) return null
  try {
    const bytes = urlBase64ToUint8Array(value)
    return bytes.length === VAPID_PUBLIC_KEY_BYTES ? bytes : null
  } catch {
    return null
  }
}

export type KeyComparison = 'same' | 'different' | 'unknown'

/**
 * ブラウザの購読の鍵（subscription.options.applicationServerKey）と、今の VAPID 公開鍵を比べる。
 *
 * - 'same': バイト単位で一致
 * - 'different': どちらも読めて、一致しない（古い鍵で作った購読。送っても push サービスに 403 で拒まれる）
 * - 'unknown': 比べられない（購読の鍵が無い・空、公開鍵が空や壊れている、想定外の例外）。
 *   不一致として扱うと正常な購読を自動で解除してしまうので、different とは分ける
 */
export function compareApplicationServerKey(
  subscriptionKey: ArrayBuffer | ArrayBufferView | null | undefined,
  vapidPublicKeyBase64Url: string | null | undefined,
): KeyComparison {
  try {
    if (!subscriptionKey) return 'unknown'
    const expected = decodeVapidPublicKey(vapidPublicKeyBase64Url)
    if (!expected) return 'unknown'

    const actual = ArrayBuffer.isView(subscriptionKey)
      ? new Uint8Array(subscriptionKey.buffer, subscriptionKey.byteOffset, subscriptionKey.byteLength)
      : new Uint8Array(subscriptionKey)
    if (actual.length === 0) return 'unknown'
    if (actual.length !== expected.length) return 'different'
    for (let i = 0; i < expected.length; i++) {
      if (actual[i] !== expected[i]) return 'different'
    }
    return 'same'
  } catch {
    return 'unknown'
  }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/notifications/pushSubscriptionKey.test.ts`
Expected: PASS（すべて）

- [ ] **Step 5: Commit**

```bash
git add fit-connect/src/lib/notifications/pushSubscriptionKey.ts fit-connect/src/lib/notifications/pushSubscriptionKey.test.ts
git commit -m "feat(web): Web Push の購読の鍵と今の VAPID 公開鍵を比べる純関数を追加

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 設定画面を開いたときの登録し直しの分岐（`syncPushSubscription.ts`。設計書 §7.2）

**Files:**
- Create: `fit-connect/src/lib/notifications/syncPushSubscription.ts`
- Test: `fit-connect/src/lib/notifications/syncPushSubscription.test.ts`

**Interfaces:**
- Consumes: `compareApplicationServerKey`（Task 2）
- Produces:
  - `export type SubscriptionSnapshot = { endpoint: string; applicationServerKey: ArrayBuffer | null; p256dh: string | null; auth: string | null }`
  - `export type SyncPushSubscriptionDeps = { getSubscription: () => Promise<SubscriptionSnapshot | null>; vapidPublicKey: string | null | undefined; post: (body: { endpoint: string; p256dh: string; auth: string }) => Promise<boolean>; del: (body: { endpoint: string }) => Promise<boolean>; unsubscribe: () => Promise<boolean> }`
  - `export type SyncPushSubscriptionResult = 'reposted' | 'purged' | 'noop' | 'failed'`
  - `export async function syncPushSubscription(deps: SyncPushSubscriptionDeps): Promise<SyncPushSubscriptionResult>`

- [ ] **Step 1: 失敗するテストを書く**

`fit-connect/src/lib/notifications/syncPushSubscription.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest'
import { syncPushSubscription, type SubscriptionSnapshot, type SyncPushSubscriptionDeps } from './syncPushSubscription'

/** テスト用: バイト列 → base64url（パディング無し） */
function toBase64Url(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

const KEY = new Uint8Array(65).map((_, i) => (i === 0 ? 4 : (i * 31 + 5) % 256))
const KEY_B64URL = toBase64Url(KEY)
const OTHER_KEY = KEY.slice()
OTHER_KEY[10] = (OTHER_KEY[10] + 1) % 256

function snapshot(overrides: Partial<SubscriptionSnapshot> = {}): SubscriptionSnapshot {
  return {
    endpoint: 'https://push.example.test/sub/1',
    applicationServerKey: KEY.slice().buffer,
    p256dh: 'p256dh-value',
    auth: 'auth-value',
    ...overrides,
  }
}

function makeDeps(overrides: Partial<SyncPushSubscriptionDeps> = {}) {
  const calls: string[] = []
  const deps: SyncPushSubscriptionDeps = {
    vapidPublicKey: KEY_B64URL,
    getSubscription: vi.fn(async () => snapshot()),
    post: vi.fn(async () => {
      calls.push('post')
      return true
    }),
    del: vi.fn(async () => {
      calls.push('del')
      return true
    }),
    unsubscribe: vi.fn(async () => {
      calls.push('unsubscribe')
      return true
    }),
    ...overrides,
  }
  return { deps, calls }
}

describe('syncPushSubscription', () => {
  it('同じ鍵 → post を1回だけ呼び、reposted', async () => {
    const { deps, calls } = makeDeps()
    await expect(syncPushSubscription(deps)).resolves.toBe('reposted')
    expect(calls).toEqual(['post'])
    expect(deps.post).toHaveBeenCalledWith({
      endpoint: 'https://push.example.test/sub/1',
      p256dh: 'p256dh-value',
      auth: 'auth-value',
    })
  })

  it('購読の鍵が null（比べられない）→ post を1回だけ呼び、reposted', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: null })),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('reposted')
    expect(calls).toEqual(['post'])
  })

  it('環境変数が壊れている（引用符つき）→ 比べられないので post だけ（自動で解除しない）', async () => {
    const { deps, calls } = makeDeps({ vapidPublicKey: `"${KEY_B64URL}"` })
    await expect(syncPushSubscription(deps)).resolves.toBe('reposted')
    expect(calls).toEqual(['post'])
  })

  it('違う鍵 → del → unsubscribe の順に呼び、post は呼ばない（purged）', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('purged')
    expect(calls).toEqual(['del', 'unsubscribe'])
    expect(deps.del).toHaveBeenCalledWith({ endpoint: 'https://push.example.test/sub/1' })
  })

  it.each([
    ['undefined', undefined],
    ['空文字', ''],
  ])('公開鍵が %s → 何もしない（noop）', async (_label, vapidPublicKey) => {
    const { deps, calls } = makeDeps({ vapidPublicKey })
    await expect(syncPushSubscription(deps)).resolves.toBe('noop')
    expect(calls).toEqual([])
    expect(deps.getSubscription).not.toHaveBeenCalled()
  })

  it('ブラウザに購読が無い → 何もしない（noop）', async () => {
    const { deps, calls } = makeDeps({ getSubscription: vi.fn(async () => null) })
    await expect(syncPushSubscription(deps)).resolves.toBe('noop')
    expect(calls).toEqual([])
  })

  it('post が失敗（false）→ failed', async () => {
    const { deps } = makeDeps({ post: vi.fn(async () => false) })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('post が例外 → failed', async () => {
    const { deps } = makeDeps({
      post: vi.fn(async () => {
        throw new Error('network')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('購読の鍵データ（p256dh / auth）が欠けている → post せず failed', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ auth: null })),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(calls).toEqual([])
  })

  it('違う鍵で del が失敗（false）→ unsubscribe を呼ばず failed', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      del: vi.fn(async () => false),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(calls).toEqual([])
    expect(deps.unsubscribe).not.toHaveBeenCalled()
  })

  it('違う鍵で del が例外 → unsubscribe を呼ばず failed', async () => {
    const { deps } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      del: vi.fn(async () => {
        throw new Error('network')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(deps.unsubscribe).not.toHaveBeenCalled()
  })

  it('違う鍵で unsubscribe が失敗（false）→ failed', async () => {
    const { deps } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      unsubscribe: vi.fn(async () => false),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('違う鍵で unsubscribe が例外 → failed', async () => {
    const { deps } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      unsubscribe: vi.fn(async () => {
        throw new Error('boom')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('getSubscription が例外 → failed（何も送らない）', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => {
        throw new Error('no sw')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(calls).toEqual([])
  })
})
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run（`fit-connect/` で）: `npx -y pnpm@10.32.1 vitest run src/lib/notifications/syncPushSubscription.test.ts`
Expected: FAIL（`./syncPushSubscription` が見つからない）

- [ ] **Step 3: 実装を書く**

`fit-connect/src/lib/notifications/syncPushSubscription.ts`:

```ts
/**
 * 設定画面を開いたときの、ブラウザの Web Push 購読の登録し直し（設計書 §7.2）。
 *
 * ブラウザの購読の鍵を今の VAPID 公開鍵と比べ、
 * - 同じ／比べられない: サーバーへ送り直す（ブラウザでは購読済みなのにサーバーに行が無い状態を直す）
 * - 違う（古い鍵で作った購読）: サーバーの行を消してから、ブラウザの購読を解除する
 * - 公開鍵が無い・購読が無い: 何もしない
 *
 * ブラウザ API と fetch は引数で受ける（コンポーネントから切り離して単体テストするため）。
 * 例外は投げず、結果を返す。
 */
import { compareApplicationServerKey } from './pushSubscriptionKey'

/** ブラウザの購読から、照合と送り直しに要る値だけを抜き出したもの */
export type SubscriptionSnapshot = {
  endpoint: string
  /** subscription.options.applicationServerKey（ブラウザが返さなければ null） */
  applicationServerKey: ArrayBuffer | null
  p256dh: string | null
  auth: string | null
}

export type SyncPushSubscriptionDeps = {
  /** 今のブラウザの購読（Service Worker や購読が無ければ null） */
  getSubscription: () => Promise<SubscriptionSnapshot | null>
  /** NEXT_PUBLIC_VAPID_PUBLIC_KEY */
  vapidPublicKey: string | null | undefined
  /** POST /api/push-subscriptions。成功（2xx）で true */
  post: (body: { endpoint: string; p256dh: string; auth: string }) => Promise<boolean>
  /** DELETE /api/push-subscriptions。成功（2xx）で true */
  del: (body: { endpoint: string }) => Promise<boolean>
  /** ブラウザの購読の解除。解除できたら true */
  unsubscribe: () => Promise<boolean>
}

/**
 * - 'reposted': サーバーへ送り直した
 * - 'purged': 古い鍵の購読を、サーバーとブラウザの両方から消した（利用者にオンにし直してもらう）
 * - 'noop': 何もしなかった（公開鍵が無い・購読が無い）
 * - 'failed': どこかで失敗した（サーバーに行が残ったままブラウザの購読だけを消すことはしない）
 */
export type SyncPushSubscriptionResult = 'reposted' | 'purged' | 'noop' | 'failed'

export async function syncPushSubscription(
  deps: SyncPushSubscriptionDeps,
): Promise<SyncPushSubscriptionResult> {
  // 公開鍵が無い（dev 環境など）は比べられないので、送り直しもしない
  if (!deps.vapidPublicKey) return 'noop'

  try {
    const subscription = await deps.getSubscription()
    if (!subscription) return 'noop'

    const comparison = compareApplicationServerKey(subscription.applicationServerKey, deps.vapidPublicKey)

    if (comparison === 'different') {
      // サーバーの行を先に消す。消せなければブラウザの購読は残す
      const deleted = await deps.del({ endpoint: subscription.endpoint })
      if (!deleted) return 'failed'
      const unsubscribed = await deps.unsubscribe()
      return unsubscribed ? 'purged' : 'failed'
    }

    // same / unknown: 送り直す（API は upsert なので何度送っても行は増えない）
    if (!subscription.p256dh || !subscription.auth) return 'failed'
    const posted = await deps.post({
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
    })
    return posted ? 'reposted' : 'failed'
  } catch {
    return 'failed'
  }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/notifications/syncPushSubscription.test.ts src/lib/notifications/pushSubscriptionKey.test.ts`
Expected: PASS（すべて）

- [ ] **Step 5: Commit**

```bash
git add fit-connect/src/lib/notifications/syncPushSubscription.ts fit-connect/src/lib/notifications/syncPushSubscription.test.ts
git commit -m "feat(web): 設定画面を開いたときの Web Push 購読の登録し直し・古い鍵の解除の分岐を追加

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 購読の所有者と登録・削除の失敗の扱い（設計書 §7.6）

**Files:**
- Modify: `fit-connect/src/lib/supabase/savePushSubscription.ts`（全体を置き換え）
- Modify: `fit-connect/src/lib/supabase/deletePushSubscription.ts`（全体を置き換え）
- Test: `fit-connect/src/lib/supabase/savePushSubscription.test.ts`（新規）
- Test: `fit-connect/src/lib/supabase/deletePushSubscription.test.ts`（新規）

**Interfaces:**
- Consumes: `supabaseAdmin`（`@/lib/supabaseAdmin`）
- Produces: シグネチャは変えない。`savePushSubscription(data: PushSubscriptionData): Promise<void>` / `deletePushSubscription(trainerId: string, endpoint: string): Promise<void>`。`device_tokens` の失敗で throw する（API ルートは既存の catch で 500 を返す。`route.ts` は変更しない）

- [ ] **Step 1: 失敗するテストを書く（登録）**

`fit-connect/src/lib/supabase/savePushSubscription.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

type Call = { method: string; args: unknown[] }
type ChainRecord = { table: string; calls: Call[] }

const mocks = vi.hoisted(() => ({
  // from() ごとに、呼ばれたメソッドと引数の記録
  chains: [] as Array<{ table: string; calls: Array<{ method: string; args: unknown[] }> }>,
  // `${table}.${最初の操作}` ごとに返す結果（既定は { error: null }）。Error なら reject する
  results: {} as Record<string, { error: unknown } | Error>,
}))

vi.mock('@/lib/supabaseAdmin', () => ({
  supabaseAdmin: {
    from: (table: string) => {
      const record = { table, calls: [] as Array<{ method: string; args: unknown[] }> }
      mocks.chains.push(record)
      const builder: Record<string, unknown> = {}
      for (const method of ['upsert', 'delete', 'eq', 'neq']) {
        builder[method] = (...args: unknown[]) => {
          record.calls.push({ method, args })
          return builder
        }
      }
      // await されたときに結果を返す（PostgREST のクエリビルダと同じく thenable）
      builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) => {
        const op = record.calls[0]?.method
        const result = mocks.results[`${table}.${op}`] ?? { error: null }
        if (result instanceof Error) return Promise.reject(result).then(resolve, reject)
        return Promise.resolve(result).then(resolve, reject)
      }
      return builder
    },
  },
}))

import { savePushSubscription } from './savePushSubscription'

const DATA = {
  trainerId: '11111111-1111-4111-8111-111111111111',
  endpoint: 'https://push.example.test/sub/abc',
  p256dh: 'p256dh-value',
  auth: 'auth-value',
}

function chain(index: number): ChainRecord {
  return mocks.chains[index] as ChainRecord
}

function call(record: ChainRecord, method: string): Call[] {
  return record.calls.filter((c) => c.method === method)
}

describe('savePushSubscription', () => {
  beforeEach(() => {
    mocks.chains.length = 0
    mocks.results = {}
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('device_tokens に upsert → 同じ endpoint の他のトレーナーの行を delete → 旧 push_subscriptions に upsert の順', async () => {
    await savePushSubscription(DATA)

    expect(mocks.chains.map((c) => `${c.table}.${c.calls[0]?.method}`)).toEqual([
      'device_tokens.upsert',
      'device_tokens.delete',
      'push_subscriptions.upsert',
    ])

    const [upsertValues, upsertOptions] = call(chain(0), 'upsert')[0].args as [Record<string, unknown>, unknown]
    expect(upsertValues).toMatchObject({
      user_id: DATA.trainerId,
      user_type: 'trainer',
      platform: 'web_push',
      token: DATA.endpoint,
      web_push_p256dh: DATA.p256dh,
      web_push_auth: DATA.auth,
    })
    expect(typeof upsertValues.last_seen_at).toBe('string')
    expect(upsertOptions).toEqual({ onConflict: 'user_id,token' })

    const deleteChain = chain(1)
    expect(call(deleteChain, 'eq').map((c) => c.args)).toEqual(
      expect.arrayContaining([
        ['platform', 'web_push'],
        ['token', DATA.endpoint],
        ['user_type', 'trainer'],
      ]),
    )
    expect(call(deleteChain, 'eq')).toHaveLength(3)
    expect(call(deleteChain, 'neq').map((c) => c.args)).toEqual([['user_id', DATA.trainerId]])

    const [legacyValues, legacyOptions] = call(chain(2), 'upsert')[0].args as [Record<string, unknown>, unknown]
    expect(legacyValues).toMatchObject({
      trainer_id: DATA.trainerId,
      endpoint: DATA.endpoint,
      p256dh: DATA.p256dh,
      auth: DATA.auth,
    })
    expect(legacyOptions).toEqual({ onConflict: 'endpoint' })
  })

  it('device_tokens の upsert が失敗 → throw し、delete も旧表も呼ばない', async () => {
    mocks.results['device_tokens.upsert'] = { error: { message: 'upsert failed' } }
    await expect(savePushSubscription(DATA)).rejects.toEqual({ message: 'upsert failed' })
    expect(mocks.chains).toHaveLength(1)
  })

  it('他のトレーナーの行の delete が失敗 → throw し、旧表は呼ばない', async () => {
    mocks.results['device_tokens.delete'] = { error: { message: 'delete failed' } }
    await expect(savePushSubscription(DATA)).rejects.toEqual({ message: 'delete failed' })
    expect(mocks.chains.map((c) => c.table)).toEqual(['device_tokens', 'device_tokens'])
  })

  it('device_tokens の upsert が例外 → throw', async () => {
    mocks.results['device_tokens.upsert'] = new Error('network')
    await expect(savePushSubscription(DATA)).rejects.toThrow('network')
  })

  it('旧 push_subscriptions の upsert が失敗しても throw しない（console.error だけ）', async () => {
    mocks.results['push_subscriptions.upsert'] = { error: { message: 'legacy failed' } }
    await expect(savePushSubscription(DATA)).resolves.toBeUndefined()
    expect(console.error).toHaveBeenCalled()
  })

  it('旧 push_subscriptions の upsert が例外でも throw しない（console.error だけ）', async () => {
    mocks.results['push_subscriptions.upsert'] = new Error('legacy network')
    await expect(savePushSubscription(DATA)).resolves.toBeUndefined()
    expect(console.error).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: 失敗するテストを書く（削除）**

`fit-connect/src/lib/supabase/deletePushSubscription.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  chains: [] as Array<{ table: string; calls: Array<{ method: string; args: unknown[] }> }>,
  results: {} as Record<string, { error: unknown } | Error>,
}))

vi.mock('@/lib/supabaseAdmin', () => ({
  supabaseAdmin: {
    from: (table: string) => {
      const record = { table, calls: [] as Array<{ method: string; args: unknown[] }> }
      mocks.chains.push(record)
      const builder: Record<string, unknown> = {}
      for (const method of ['delete', 'eq']) {
        builder[method] = (...args: unknown[]) => {
          record.calls.push({ method, args })
          return builder
        }
      }
      builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) => {
        const op = record.calls[0]?.method
        const result = mocks.results[`${table}.${op}`] ?? { error: null }
        if (result instanceof Error) return Promise.reject(result).then(resolve, reject)
        return Promise.resolve(result).then(resolve, reject)
      }
      return builder
    },
  },
}))

import { deletePushSubscription } from './deletePushSubscription'

const TRAINER_ID = '11111111-1111-4111-8111-111111111111'
const ENDPOINT = 'https://push.example.test/sub/abc'

describe('deletePushSubscription', () => {
  beforeEach(() => {
    mocks.chains.length = 0
    mocks.results = {}
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('device_tokens の自分の行（endpoint 単位）を消してから、旧 push_subscriptions を消す', async () => {
    await deletePushSubscription(TRAINER_ID, ENDPOINT)

    expect(mocks.chains.map((c) => `${c.table}.${c.calls[0]?.method}`)).toEqual([
      'device_tokens.delete',
      'push_subscriptions.delete',
    ])
    expect(mocks.chains[0].calls.filter((c) => c.method === 'eq').map((c) => c.args)).toEqual([
      ['user_id', TRAINER_ID],
      ['token', ENDPOINT],
    ])
    expect(mocks.chains[1].calls.filter((c) => c.method === 'eq').map((c) => c.args)).toEqual([
      ['trainer_id', TRAINER_ID],
      ['endpoint', ENDPOINT],
    ])
  })

  it('device_tokens の delete が失敗 → throw し、旧表は呼ばない', async () => {
    mocks.results['device_tokens.delete'] = { error: { message: 'delete failed' } }
    await expect(deletePushSubscription(TRAINER_ID, ENDPOINT)).rejects.toEqual({ message: 'delete failed' })
    expect(mocks.chains).toHaveLength(1)
  })

  it('旧 push_subscriptions の delete が失敗しても throw しない（console.error だけ）', async () => {
    mocks.results['push_subscriptions.delete'] = { error: { message: 'legacy failed' } }
    await expect(deletePushSubscription(TRAINER_ID, ENDPOINT)).resolves.toBeUndefined()
    expect(console.error).toHaveBeenCalled()
  })

  it('旧 push_subscriptions の delete が例外でも throw しない', async () => {
    mocks.results['push_subscriptions.delete'] = new Error('legacy network')
    await expect(deletePushSubscription(TRAINER_ID, ENDPOINT)).resolves.toBeUndefined()
  })
})
```

- [ ] **Step 3: テストが失敗することを確かめる**

Run（`fit-connect/` で）: `npx -y pnpm@10.32.1 vitest run src/lib/supabase/savePushSubscription.test.ts src/lib/supabase/deletePushSubscription.test.ts`
Expected: FAIL（今の実装は旧表を先に書き、`device_tokens` の失敗を握りつぶし、他のトレーナーの行を消さない）

- [ ] **Step 4: 登録の実装を置き換える**

`fit-connect/src/lib/supabase/savePushSubscription.ts`（全体）:

```ts
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export type PushSubscriptionData = {
  trainerId: string
  endpoint: string
  p256dh: string
  auth: string
}

/**
 * トレーナーのブラウザの Web Push 購読を登録する（設計書 §7.6）。
 *
 * 1. device_tokens に自分の行を upsert（送信側 _shared/push.ts が読む唯一の宛先）
 * 2. 同じ endpoint を持つ「他のトレーナー」の web_push 行を消す。購読はブラウザに付くので、
 *    同じブラウザで後から登録したトレーナー1人のものにする（前のトレーナー宛の通知が出続けないように）。
 *    顧客の ios / android 行は触らない
 * 3. 旧 push_subscriptions に upsert（段階移行の両書き。失敗しても応答は失敗にしない）
 *
 * 1・2 の失敗は throw する（API ルートが 500 を返す）。どちらも何度流しても同じ結果になるので、画面から再試行できる。
 * 1 を先にするのは、削除だけが済んで自分の行が無い（誰にも届かない）状態を作らないため。
 */
export async function savePushSubscription(data: PushSubscriptionData) {
  const now = new Date().toISOString()

  const { error: upsertError } = await supabaseAdmin
    .from('device_tokens')
    .upsert(
      {
        user_id: data.trainerId,
        user_type: 'trainer',
        platform: 'web_push',
        token: data.endpoint,
        web_push_p256dh: data.p256dh,
        web_push_auth: data.auth,
        last_seen_at: now,
      },
      { onConflict: 'user_id,token' }
    )
  if (upsertError) throw upsertError

  const { error: deleteError } = await supabaseAdmin
    .from('device_tokens')
    .delete()
    .eq('platform', 'web_push')
    .eq('token', data.endpoint)
    .eq('user_type', 'trainer')
    .neq('user_id', data.trainerId)
  if (deleteError) throw deleteError

  // 段階移行の両書き（旧 push_subscriptions）。endpoint で一意なので、ここでも最後に登録したトレーナーのものになる
  try {
    const { error: legacyError } = await supabaseAdmin
      .from('push_subscriptions')
      .upsert(
        {
          trainer_id: data.trainerId,
          endpoint: data.endpoint,
          p256dh: data.p256dh,
          auth: data.auth,
          updated_at: now,
        },
        { onConflict: 'endpoint' }
      )
    if (legacyError) {
      console.error('[savePushSubscription] push_subscriptions upsert failed:', legacyError)
    }
  } catch (e) {
    console.error('[savePushSubscription] push_subscriptions upsert threw:', e)
  }
}
```

- [ ] **Step 5: 削除の実装を置き換える**

`fit-connect/src/lib/supabase/deletePushSubscription.ts`（全体）:

```ts
import { supabaseAdmin } from '@/lib/supabaseAdmin'

/**
 * トレーナー自身の Web Push 購読（endpoint 単位）を削除する。
 *
 * device_tokens（送信側が読む唯一の宛先）を先に消し、失敗は throw する（API ルートが 500 を返し、
 * 画面はブラウザの購読を解除しない。サーバーに行が残ったままブラウザの購読だけが消える状態を作らない）。
 * 旧 push_subscriptions の削除は段階移行の両書きで、失敗しても応答は失敗にしない。
 */
export async function deletePushSubscription(trainerId: string, endpoint: string) {
  const { error: deleteError } = await supabaseAdmin
    .from('device_tokens')
    .delete()
    .eq('user_id', trainerId)
    .eq('token', endpoint)
  if (deleteError) throw deleteError

  try {
    const { error: legacyError } = await supabaseAdmin
      .from('push_subscriptions')
      .delete()
      .eq('trainer_id', trainerId)
      .eq('endpoint', endpoint)
    if (legacyError) {
      console.error('[deletePushSubscription] push_subscriptions delete failed:', legacyError)
    }
  } catch (e) {
    console.error('[deletePushSubscription] push_subscriptions delete threw:', e)
  }
}
```

- [ ] **Step 6: テストが通ることを確かめる**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/supabase/savePushSubscription.test.ts src/lib/supabase/deletePushSubscription.test.ts`
Expected: PASS（すべて）

- [ ] **Step 7: Commit**

```bash
git add fit-connect/src/lib/supabase/savePushSubscription.ts fit-connect/src/lib/supabase/deletePushSubscription.ts fit-connect/src/lib/supabase/savePushSubscription.test.ts fit-connect/src/lib/supabase/deletePushSubscription.test.ts
git commit -m "fix(web): Web Push の購読を最後に登録したトレーナー1人のものにし、device_tokens の失敗を応答に返す

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 設定画面（`NotificationSection.tsx`。設計書 §7.2 の PR1 の部分）

**Files:**
- Modify: `fit-connect/src/components/settings/NotificationSection.tsx`（下の全文で置き換える）

**Interfaces:**
- Consumes: `urlBase64ToUint8Array`（Task 2）、`syncPushSubscription` / `SubscriptionSnapshot`（Task 3）、`POST` / `DELETE /api/push-subscriptions`（Task 4 で失敗時 500）
- Produces: なし（PR2 が通知の種別の一覧を `notificationKinds.ts` に移し、「アラート（朝のまとめ）」と親トグルの説明を変える。PR1 では種別の一覧・親トグルの説明・種別の保存の処理を変えない）

変えること（設計書 §7.2）:
- `urlBase64ToUint8Array` をこのファイルから消し、`@/lib/notifications/pushSubscriptionKey` から import する
- マウント時の自動の登録し直し（通知の許可が `granted` のときだけ。`syncPushSubscription` を呼ぶ。専用の effect、`cancelled` フラグ、通信と解除の手前で `cancelled` を見る、処理中は親トグルを `disabled`）
- 購読は `navigator.serviceWorker.getRegistration()` から読む（`ready` は SW が無いと永久に解決しない。Review Focus 1）
- `purged` なら、トグルをオフにして案内 `通知の設定が変わりました。もう一度オンにしてください。` を `role="status"`・中立色で出す。`failed` は `console.error` だけ
- 有効化: 公開鍵が無ければ **通知の許可を求める前に** `現在プッシュ通知を有効にできません。時間をおいて再度お試しください。` を出して終える。登録の API が非 OK なら `プッシュ通知の登録に失敗しました。再度お試しください。`。`subscribe()` の例外・購読の鍵データの欠け・その他の例外は `プッシュ通知の設定を変更できませんでした。再度お試しください。`。許可のダイアログを閉じた（`default`）・拒否（`denied`）は何も出さない
- 無効化: `DELETE` が非 OK・例外なら、ブラウザの購読を解除せず、トグルもオンのまま `プッシュ通知の設定を変更できませんでした。再度お試しください。`
- エラーは既存の保存失敗と同じ場所に `role="alert"` で出す。有効化・無効化・種別の保存を始めるときに、前のエラーと案内を消す

- [ ] **Step 1: ファイルを次の全文で置き換える**

`fit-connect/src/components/settings/NotificationSection.tsx`:

```tsx
'use client'

import { useState, useEffect, useCallback } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { supabase } from '@/lib/supabase'
import { urlBase64ToUint8Array } from '@/lib/notifications/pushSubscriptionKey'
import { syncPushSubscription, type SubscriptionSnapshot } from '@/lib/notifications/syncPushSubscription'

type NotificationKind = 'message' | 'goal_achievement'

const NOTIFICATION_KINDS: {
  kind: NotificationKind
  label: string
  description: string
}[] = [
  {
    kind: 'message',
    label: 'メッセージ受信',
    description: 'クライアントからメッセージが届いたとき',
  },
  {
    kind: 'goal_achievement',
    label: '目標達成のお知らせ',
    description: 'クライアントが目標を達成したとき',
  },
]

const MESSAGE_KEY_MISSING = '現在プッシュ通知を有効にできません。時間をおいて再度お試しください。'
const MESSAGE_REGISTER_FAILED = 'プッシュ通知の登録に失敗しました。再度お試しください。'
const MESSAGE_CHANGE_FAILED = 'プッシュ通知の設定を変更できませんでした。再度お試しください。'
const MESSAGE_PREF_SAVE_FAILED = '通知設定の保存に失敗しました。再度お試しください。'
const NOTICE_RESUBSCRIBE = '通知の設定が変わりました。もう一度オンにしてください。'

/** POST / DELETE /api/push-subscriptions を呼び、2xx なら true（例外はそのまま投げる） */
async function callPushSubscriptionsApi(method: 'POST' | 'DELETE', body: object): Promise<boolean> {
  const response = await fetch('/api/push-subscriptions', {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  return response.ok
}

/**
 * 登録済みの Service Worker から今の購読を読む（SW や購読が無ければ null）。
 * navigator.serviceWorker.ready は SW が1つも無いと永久に解決しないので、getRegistration を使う
 */
async function readCurrentSubscription(): Promise<{
  subscription: PushSubscription
  snapshot: SubscriptionSnapshot
} | null> {
  const registration = await navigator.serviceWorker.getRegistration()
  if (!registration) return null
  const subscription = await registration.pushManager.getSubscription()
  if (!subscription) return null
  const json = subscription.toJSON()
  return {
    subscription,
    snapshot: {
      endpoint: subscription.endpoint,
      applicationServerKey: subscription.options?.applicationServerKey ?? null,
      p256dh: json.keys?.p256dh ?? null,
      auth: json.keys?.auth ?? null,
    },
  }
}

function isPushSupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window
  )
}

type NotificationSectionProps = {
  trainerId: string
}

export function NotificationSection({ trainerId }: NotificationSectionProps) {
  const [permission, setPermission] = useState<NotificationPermission>('default')
  const [isSubscribed, setIsSubscribed] = useState(false)
  const [loading, setLoading] = useState(false)
  // 設定画面を開いたときの購読の登録し直しの最中（親トグルを押せなくする）
  const [syncing, setSyncing] = useState(false)
  const [supported, setSupported] = useState(true)
  // 行が無ければ有効（デフォルトON）
  const [prefs, setPrefs] = useState<Record<NotificationKind, boolean>>({
    message: true,
    goal_achievement: true,
  })
  const [savingKind, setSavingKind] = useState<NotificationKind | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  useEffect(() => {
    // ブラウザがWeb Push APIをサポートしているか確認
    if (!isPushSupported()) {
      setSupported(false)
      return
    }

    setPermission(Notification.permission)

    // 既存のsubscriptionがあるか確認
    navigator.serviceWorker.ready.then((registration) => {
      registration.pushManager.getSubscription().then((subscription) => {
        setIsSubscribed(!!subscription)
      })
    })
  }, [])

  // 設定画面を開いたときの購読の登録し直し（設計書 §7.2）。通知が許可されているときだけ、マウント時に1回
  useEffect(() => {
    if (!trainerId) return
    if (!isPushSupported()) return
    if (Notification.permission !== 'granted') return

    // React の StrictMode（dev）は effect を2回走らせる。1回目は cleanup で cancelled になるので、
    // 通信・解除の手前で止める（POST / DELETE / unsubscribe を二重に走らせない）
    let cancelled = false
    let current: PushSubscription | null = null
    setSyncing(true)

    syncPushSubscription({
      vapidPublicKey: process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY,
      getSubscription: async () => {
        const found = await readCurrentSubscription()
        current = found?.subscription ?? null
        return found?.snapshot ?? null
      },
      post: async (body) => (cancelled ? false : callPushSubscriptionsApi('POST', body)),
      del: async (body) => (cancelled ? false : callPushSubscriptionsApi('DELETE', body)),
      unsubscribe: async () => (cancelled || !current ? false : current.unsubscribe()),
    })
      .then((result) => {
        if (cancelled) return
        if (result === 'purged') {
          setIsSubscribed(false)
          setNotice(NOTICE_RESUBSCRIBE)
        } else if (result === 'failed') {
          console.error('[NotificationSection] プッシュ通知の購読の登録し直しに失敗しました')
        }
      })
      .finally(() => {
        if (!cancelled) setSyncing(false)
      })

    return () => {
      cancelled = true
    }
  }, [trainerId])

  // 通知種別ごとの設定を読み込み（RLSにより自分の行のみ取得可能）
  useEffect(() => {
    if (!trainerId) return
    let cancelled = false

    const loadPreferences = async () => {
      const { data, error } = await supabase
        .from('notification_preferences')
        .select('kind, enabled')
        .eq('user_id', trainerId)

      if (cancelled) return

      if (error) {
        console.error('通知設定の取得エラー:', error)
        return
      }

      if (data && data.length > 0) {
        setPrefs((prev) => {
          const next = { ...prev }
          for (const row of data as { kind: string; enabled: boolean }[]) {
            if (row.kind === 'message' || row.kind === 'goal_achievement') {
              next[row.kind] = row.enabled
            }
          }
          return next
        })
      }
    }

    loadPreferences()
    return () => {
      cancelled = true
    }
  }, [trainerId])

  const handleTogglePref = useCallback(
    async (kind: NotificationKind) => {
      if (!trainerId) return
      const nextValue = !prefs[kind]

      setSavingKind(kind)
      setErrorMessage(null)
      setNotice(null)
      // 楽観的更新
      setPrefs((prev) => ({ ...prev, [kind]: nextValue }))

      const { error } = await supabase.from('notification_preferences').upsert(
        {
          user_id: trainerId,
          kind,
          enabled: nextValue,
        },
        { onConflict: 'user_id,kind' }
      )

      if (error) {
        console.error('通知設定の保存エラー:', error)
        // ロールバック
        setPrefs((prev) => ({ ...prev, [kind]: !nextValue }))
        setErrorMessage(MESSAGE_PREF_SAVE_FAILED)
      }

      setSavingKind(null)
    },
    [trainerId, prefs]
  )

  const handleEnable = useCallback(async () => {
    if (!trainerId) return
    setErrorMessage(null)
    setNotice(null)

    // 公開鍵が無いと購読できない。許可のダイアログを出す前に確かめる
    const vapidPublicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY
    if (!vapidPublicKey) {
      setErrorMessage(MESSAGE_KEY_MISSING)
      return
    }

    setLoading(true)

    try {
      // 1. 通知の許可をリクエスト（閉じた・拒否は何も出さない。拒否は下の説明文で案内する）
      const result = await Notification.requestPermission()
      setPermission(result)

      if (result !== 'granted') {
        return
      }

      // 2. Service Workerを登録
      const registration = await navigator.serviceWorker.register('/sw.js', { scope: '/' })
      await navigator.serviceWorker.ready

      // 3. Push購読を作成
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      })

      const subscriptionJson = subscription.toJSON()
      const p256dh = subscriptionJson.keys?.p256dh
      const auth = subscriptionJson.keys?.auth

      if (!subscription.endpoint || !p256dh || !auth) {
        console.error('Invalid subscription data')
        setErrorMessage(MESSAGE_CHANGE_FAILED)
        return
      }

      // 4. サーバーに購読情報を保存
      const saved = await callPushSubscriptionsApi('POST', {
        endpoint: subscription.endpoint,
        p256dh,
        auth,
      })

      if (saved) {
        setIsSubscribed(true)
      } else {
        setErrorMessage(MESSAGE_REGISTER_FAILED)
      }
    } catch (error) {
      console.error('Error enabling push notifications:', error)
      setErrorMessage(MESSAGE_CHANGE_FAILED)
    } finally {
      setLoading(false)
    }
  }, [trainerId])

  const handleDisable = useCallback(async () => {
    if (!trainerId) return
    setErrorMessage(null)
    setNotice(null)
    setLoading(true)

    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()

      if (subscription) {
        // 1. サーバーから購読情報を削除。失敗したらブラウザの購読は残す（やり直せるように）
        const deleted = await callPushSubscriptionsApi('DELETE', {
          endpoint: subscription.endpoint,
        })
        if (!deleted) {
          setErrorMessage(MESSAGE_CHANGE_FAILED)
          return
        }

        // 2. ブラウザの購読を解除
        await subscription.unsubscribe()
      }

      setIsSubscribed(false)
    } catch (error) {
      console.error('Error disabling push notifications:', error)
      setErrorMessage(MESSAGE_CHANGE_FAILED)
    } finally {
      setLoading(false)
    }
  }, [trainerId])

  if (!supported) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>通知設定</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-gray-500">
            このブラウザはプッシュ通知に対応していません。Chrome、Edge、またはFirefoxの最新版をご利用ください。
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>通知設定</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <Label htmlFor="push-notification" className="text-base font-normal">
            プッシュ通知
          </Label>
          <button
            id="push-notification"
            type="button"
            role="switch"
            aria-checked={isSubscribed}
            disabled={loading || syncing || permission === 'denied'}
            onClick={isSubscribed ? handleDisable : handleEnable}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 ${
              isSubscribed ? 'bg-blue-600' : 'bg-gray-300'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                isSubscribed ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        <p className="text-sm text-gray-500">
          {permission === 'denied'
            ? '通知がブラウザの設定でブロックされています。アドレスバー横の鍵アイコンから通知を「許可」に変更してください。'
            : 'クライアントからメッセージが届いた際にブラウザ通知でお知らせします。'}
        </p>

        {/* 通知種別ごとの設定 */}
        <div className="border-t border-gray-100 pt-4 space-y-3">
          <p className="text-sm font-medium text-gray-700">通知の種類</p>

          {errorMessage && (
            <div role="alert" className="text-sm px-3 py-2 rounded bg-red-50 text-red-600">
              {errorMessage}
            </div>
          )}

          {notice && (
            <div
              role="status"
              className="text-sm px-3 py-2 rounded border border-slate-200 bg-slate-50 text-slate-700"
            >
              {notice}
            </div>
          )}

          <div className={`space-y-3 ${isSubscribed ? '' : 'opacity-50'}`}>
            {NOTIFICATION_KINDS.map(({ kind, label, description }) => (
              <div key={kind} className="flex items-center justify-between">
                <div>
                  <Label
                    htmlFor={`notification-${kind}`}
                    className="text-sm font-normal"
                  >
                    {label}
                  </Label>
                  <p className="text-xs text-gray-500">{description}</p>
                </div>
                <button
                  id={`notification-${kind}`}
                  type="button"
                  role="switch"
                  aria-checked={prefs[kind]}
                  disabled={!isSubscribed || savingKind === kind}
                  onClick={() => handleTogglePref(kind)}
                  className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed ${
                    prefs[kind] ? 'bg-blue-600' : 'bg-gray-300'
                  }`}
                >
                  <span
                    className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                      prefs[kind] ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
              </div>
            ))}
          </div>

          {!isSubscribed && (
            <p className="text-xs text-gray-400">
              プッシュ通知をオンにすると種類ごとの設定を変更できます。
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
```

- [ ] **Step 2: 型検査・lint・全テストを通す**

Run（`fit-connect/` で）:
- `npx -y pnpm@10.32.1 install --frozen-lockfile`（worktree で `node_modules` が無いとき。数秒）
- `npx -y pnpm@10.32.1 exec tsc --noEmit`
- `npx -y pnpm@10.32.1 lint`
- `npx -y pnpm@10.32.1 test`

Expected: すべて成功（`tsc` のエラー0件・lint の新しい警告0件・vitest 全件 PASS）。`subscription.options?.applicationServerKey` の型で `tsc` が `ArrayBuffer | null` と合わないと言う場合は、`?? null` の前の式の型を確かめ、`ArrayBuffer | null` にそろえる（`as` での握りつぶしはしない。必要なら `SubscriptionSnapshot.applicationServerKey` の型を `ArrayBuffer | null` のまま、代入側で `instanceof ArrayBuffer` で絞る）

- [ ] **Step 3: Commit**

```bash
git add fit-connect/src/components/settings/NotificationSection.tsx
git commit -m "feat(web): 設定画面を開いたときに Web Push 購読を登録し直し、古い鍵の購読を解除する。有効化・無効化の失敗を表示する

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 手順書と進捗（設計書 §12 の PR1 の Docs 行）

**Files:**
- Modify: `docs/tasks/2026-07-19-webpush-vapid-setup.md`（全体を下の全文で置き換える）
- Modify: `fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md`（全体を下の全文で置き換える。**今のファイルにある鍵の出力例は消す**）
- Modify: `fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md`（フェーズ7 の旧い記述に注記）
- Modify: `docs/tasks/IMPLEMENTATION_TASKS.md`（進捗）

**Interfaces:** なし

- [ ] **Step 1: `docs/tasks/2026-07-19-webpush-vapid-setup.md` を次の全文で置き換える**

````markdown
# Web Push（VAPID）の鍵の設定と確認（オーナー作業）

**作成日**: 2026/07/19（フェーズ7.3 通知基盤統一）
**更新日**: 2026/10/04（フェーズ9.1 拡張 トレーナー向け push の PR1。鍵の置き場所・変える順序・確認の判定を追記）
**所要時間**: 設定 5分 / 確認 10分

## 背景

通知は Edge Functions の統一ディスパッチャ（`supabase/functions/_shared/push.ts`）から送ります。
トレーナー向けのブラウザ通知（Web Push）は、ブラウザが購読するときに使う **公開鍵** と、
Edge Functions が送るときに署名する **秘密鍵** の組（VAPID の鍵）で動きます。

| 置き場所 | 名前 | 使うところ |
|---|---|---|
| Vercel（Web） | `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | 設定画面でブラウザが購読するとき（ビルド時に埋め込まれる。変えたら再デプロイ） |
| Edge Functions の secrets | `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` | 通知を送るときの署名 |

- Vercel に `VAPID_PRIVATE_KEY` は要りません（`fit-connect/src` に参照がありません。以前の `/api/push-notify` はフェーズ7.3 で削除済み）。残っていれば消して構いません
- 秘密鍵の正本は、Edge Functions の secrets と、それとは別の安全な保管先（パスワードマネージャーなど）に置きます。リポジトリ・このファイル・チャットには書きません
- **未設定の間の挙動**: Web Push は自動的にスキップされます（`notification_logs.detail` に `web_push:skipped(vapid_not_configured)`。エラーにはなりません）

## 手順（初回の設定）

ルート `FIT-CONNECT/` ディレクトリから以下を実行します。

```bash
supabase secrets set \
  VAPID_PUBLIC_KEY=<公開鍵> \
  VAPID_PRIVATE_KEY=<秘密鍵> \
  VAPID_SUBJECT=mailto:<連絡先メールアドレス>
```

- `VAPID_PUBLIC_KEY` は Vercel の `NEXT_PUBLIC_VAPID_PUBLIC_KEY` と同じ値、`VAPID_PRIVATE_KEY` はその対になる秘密鍵
- `VAPID_SUBJECT` は `mailto:` か `https:` の形（例: `mailto:admin@example.com`）
- `supabase secrets list` で3つの名前が表示されれば設定済み（値は表示されません）。Edge Functions の再デプロイは不要です

設定したら、下の「確認（手順0）」を行います。

## 鍵を変えるときの順序

1. Edge Functions の secrets（`VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY`）を新しい鍵に変える
2. Vercel の `NEXT_PUBLIC_VAPID_PUBLIC_KEY` を変えて再デプロイ
3. 下の「確認（手順0）」を行う

- Vercel だけ先に変わると、その間に設定画面を開いた人の、動いていた購読が自動で解除されます（設定画面は、ブラウザの購読の鍵が今の公開鍵と違うとき、購読を解除して「もう一度オンにしてください」と案内します）
- 鍵を変えると、古い鍵で作った購読には届かなくなります（push サービスが 403 で拒否）。各トレーナーが設定画面を開くと解除され、もう一度オンにすると新しい鍵で購読し直せます

## 確認（手順0。鍵を設定・変更するたびに行う）

1. Vercel を再デプロイした場合は、デプロイが終わってから進める
2. 本番の Web の「設定」→「プッシュ通知」を一度オフ→オン（ブラウザに許可を求められたら許可）
3. テスト用の顧客アプリから、**本文のあるテキスト**のメッセージを1通送る。その顧客の担当トレーナーが、手順2でブラウザを登録したトレーナーであること（画像だけのメッセージは通知されない。担当が違うと届かない）
4. 判定は `notification_logs` の、そのメッセージの行で行う（ブラウザに通知が出たかは補助。OS の集中モードなどでも出ない）

```sql
-- 直近のメッセージ通知（そのメッセージの行は dedup_key = 'message:<メッセージID>'）
select dedup_key, status, detail, created_at
from public.notification_logs
where kind = 'message'
order by created_at desc
limit 3;

-- ブラウザの購読の登録数（トレーナーの web_push）
select count(*) from public.device_tokens where user_type = 'trainer' and platform = 'web_push';
```

| `status` / `detail` | 意味 |
|---|---|
| `sent`（`sent=1/1`） | 鍵が一致している（push サービスが署名を受け付けた） |
| `failed` | Edge Functions の Logs の `[WebPush] Error sending notification` の `statusCode` を見る。`403` なら鍵の不一致 |
| `skipped` / `no_tokens` | `device_tokens`（トレーナーの `web_push`）に行が無い。手順2をやり直す |
| `skipped` / `disabled`・`quiet_hours` | 通知設定（メッセージ受信がオフ・静かな時間帯）のため |

## 注意

- **鍵の値をリポジトリにコミットしないこと**（このファイルにも値を書かない）
- 同じブラウザを複数のトレーナーで使うと、購読は最後に登録したトレーナーのものになります（前のトレーナーの行は登録時に消えます）
````

- [ ] **Step 2: `fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md` を次の全文で置き換える**

````markdown
# Web Push 通知の仕組みと確認

**更新日**: 2026/10/04（フェーズ9.1 拡張 トレーナー向け push の PR1。削除済みの `/api/push-notify` 前提を今の経路に直した）

## 概要

トレーナーのブラウザに通知（Web Push）を届ける仕組みです。今はクライアントからのメッセージ受信を通知します。
鍵（VAPID）の設定と、設定後の確認の手順は `docs/tasks/2026-07-19-webpush-vapid-setup.md`（オーナー作業）にあります。

### 通知の流れ

```
クライアントがメッセージ送信
  → messages テーブルに INSERT
  → トリガー → Edge Function (parse-message-tags)
  → _shared/push.ts の sendNotification
      - notification_logs に記録（dedup_key で二重送信を防ぐ）
      - notification_preferences（種別のオン・オフ、静かな時間帯）を確認
      - device_tokens から宛先を読む（user_type = 'trainer' の web_push 行）
      - npm:web-push で、Edge Functions の secrets の VAPID 鍵で署名して送信
  → ブラウザの Service Worker (public/sw.js) が受信して通知を表示
  → 通知をクリック → /message
```

### 購読の登録

1. 設定画面（`/settings`）の「プッシュ通知」をオンにする
2. ブラウザの許可 → Service Worker（`/sw.js`）の登録 → `pushManager.subscribe`（`NEXT_PUBLIC_VAPID_PUBLIC_KEY` を使う）
3. `POST /api/push-subscriptions` で `device_tokens`（`user_type = 'trainer'`・`platform = 'web_push'`）に保存する。同じブラウザ（endpoint）を他のトレーナーが登録していれば、その行は消える（購読は最後に登録したトレーナー1人のもの）。旧 `push_subscriptions` にも両書きする（段階移行。送信側は読まない）

設定画面を開くたびに、ブラウザに購読があれば次のどちらかを自動で行います。
- 購読の鍵が今の公開鍵と同じ（または比べられない）: サーバーへ送り直す（ブラウザでは購読済みなのにサーバーに行が無い状態が直る）
- 購読の鍵が今の公開鍵と違う（鍵を変えた後の古い購読）: サーバーの行とブラウザの購読を消し、「もう一度オンにしてください」と案内する

---

## 環境変数

| 変数名 | 設定場所 | 必須 | 説明 |
|--------|---------|------|------|
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | Vercel（ローカルは `.env.local`） | 必須 | VAPID 公開鍵（ブラウザで購読するときに使う。ビルド時に埋め込まれる） |
| `VAPID_PUBLIC_KEY` | Supabase Edge Functions の secrets | 必須 | 上と同じ公開鍵 |
| `VAPID_PRIVATE_KEY` | Supabase Edge Functions の secrets | 必須 | VAPID 秘密鍵（送信時の署名） |
| `VAPID_SUBJECT` | Supabase Edge Functions の secrets | 必須 | 連絡先（`mailto:` か `https:`） |

- Vercel に `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` / `PUSH_API_KEY`、Edge Functions に `APP_URL` / `PUSH_API_KEY` は要りません（削除済みの `/api/push-notify` 用でした）
- 鍵の値はリポジトリ・ドキュメントに書かないこと
- 鍵を生成するときは `npx web-push generate-vapid-keys`。一度使い始めた鍵を変えると、既存の購読には届かなくなります（変える順序は手順書）

---

## 動作確認

### 購読の登録

1. ログインして設定画面（`/settings`）を開き、「プッシュ通知」をオンにする
2. ブラウザの通知許可ダイアログで「許可」を選ぶ
3. トグルがオンになることを確かめる

DB では、`device_tokens` に `user_type = 'trainer'`・`platform = 'web_push'` の行ができていることを確かめる。

### 通知

1. クライアント（モバイルアプリ）から、本文のあるテキストのメッセージを担当トレーナーに送る
2. ブラウザ通知が表示されることを確かめる
3. `notification_logs` のそのメッセージの行（`dedup_key = 'message:<メッセージID>'`）が `sent` になっていることを確かめる

---

## トラブルシューティング

### 「現在プッシュ通知を有効にできません」と表示される

`NEXT_PUBLIC_VAPID_PUBLIC_KEY` が設定されていません。Vercel に設定して再デプロイする（ローカルは `.env.local` に設定して開発サーバーを再起動する）。

### 「通知の設定が変わりました。もう一度オンにしてください。」と表示される

鍵が変わったため、古い購読を解除しました。「プッシュ通知」をもう一度オンにしてください。

### 通知がブロックされている

ブラウザで一度「拒否」すると、再度許可ダイアログは表示されません。
ブラウザのアドレスバー横の鍵アイコン → サイトの設定 → 通知 → 「許可」に変更してください。

### 通知が届かない

`notification_logs` のその通知の行の `status` / `detail` を見る。

| `status` / `detail` | 対処 |
|---|---|
| `skipped` / `no_tokens` | `device_tokens` に購読が無い。設定画面でオンにする |
| `skipped` / `disabled` | 通知設定で種別がオフ |
| `skipped` / `quiet_hours` | 静かな時間帯 |
| `skipped`（`web_push:skipped(vapid_not_configured)`） | Edge Functions の secrets に VAPID 鍵が無い |
| `failed`（`detail` に `invalid_cleaned=1`） | 購読の失効（push サービスが 404 / 410）。Logs には `[WebPush] Subscription expired` が出る。`device_tokens` の行は自動で消え、次からは `no_tokens` になる。設定画面でオンにし直す |
| `failed`（それ以外） | Edge Functions の Logs の `[WebPush] Error sending notification` の `statusCode`。`403` は鍵の不一致（Vercel の公開鍵と Edge Functions の鍵が対になっていない） |

### ブラウザを閉じると通知が届かない

- **Chrome / Edge**: ブラウザのプロセスがバックグラウンドで動いていれば届きます（macOS ではメニューバー・Dock にアイコンが残っている状態）
- **完全にブラウザを終了した場合**: その場では届きません。push サービスが通知を預かっている間（有効期限内）にブラウザを起動すると、そのときに届きます
- **Firefox**: ブラウザが起動している間に受信します

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `public/sw.js` | Service Worker（通知受信・クリック処理） |
| `src/components/settings/NotificationSection.tsx` | 通知の許可・解除・種別の設定、設定画面を開いたときの購読の登録し直し |
| `src/lib/notifications/pushSubscriptionKey.ts` | 購読の鍵と公開鍵の比較 |
| `src/lib/notifications/syncPushSubscription.ts` | 購読の登録し直し・古い鍵の購読の解除の分岐 |
| `src/app/api/push-subscriptions/route.ts` | 購読の登録・解除 API |
| `src/lib/supabase/savePushSubscription.ts` | 購読の保存（`device_tokens` が主。同じ endpoint の他のトレーナーの行を消す） |
| `src/lib/supabase/deletePushSubscription.ts` | 購読の削除 |
| `supabase/functions/_shared/push.ts` | 統一ディスパッチャ（`sendNotification`） |
| `supabase/functions/parse-message-tags/index.ts` | メッセージ受信時に `sendNotification` を呼ぶ |
````

- [ ] **Step 3: `fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md` の旧い記述に注記する**

次の6か所の行末に、それぞれ注記を足す（元の文は消さない。履歴として残す）。
- 「**API Routes**: `POST/DELETE /api/push-subscriptions`（購読登録・解除）、`POST /api/push-notify`（web-pushライブラリで通知送信）」の行末に ` ※ /api/push-notify はフェーズ7.3（2026/07/19）で削除。送信は Edge Functions の _shared/push.ts に統一（docs: fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md）`
- 「**必要な環境変数**: `NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`（Next.js）、`APP_URL`, `PUSH_API_KEY`（Edge Function Secrets）」の行末に ` ※ 2026/10/04 時点: Vercel は NEXT_PUBLIC_VAPID_PUBLIC_KEY だけ、Edge Functions の secrets に VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT（docs/tasks/2026-07-19-webpush-vapid-setup.md）`
- 「**Edge Function拡張**: `parse-message-tags/index.ts` に `sendWebPushToTrainer()` 関数追加。…」の行末に ` ※ フェーズ7.3 で _shared/push.ts の sendNotification に置き換え。/api/push-notify は削除`
- 「**パッケージ追加**: `web-push`, `@types/web-push`」の行末に ` ※ フェーズ7.3 で Web の依存から削除（送信は Edge Functions の npm:web-push）`
- 表の `| 7.1.6 | Push通知送信API Route | ✅ | ...` の行の最後のセルの末尾に `（フェーズ7.3 で削除）`
- 表の `| 7.3.1 | Edge Function Web Push連携 | ✅ | ...` の行の最後のセルの末尾に `（フェーズ7.3 で _shared/push.ts の sendNotification に置き換え）`

- [ ] **Step 4: `docs/tasks/IMPLEMENTATION_TASKS.md` の進捗を更新する**

- 5行目「**進捗状況**」の `9.1 拡張③ 睡眠悪化を実装・リモート適用待ち。他の拡張は未着手` を `9.1 拡張③ 睡眠悪化はリモート適用済み。トレーナー向け push に着手（PR1 Web Push の土台を実装）。他の拡張は未着手` に変える
- 6行目「**最終更新**」の先頭（`**最終更新**: ` の直後）に次を足す: `2026年10月4日 - フェーズ9.1 拡張 トレーナー向け push を設計（\`docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md\`。朝のまとめ1通・PR を2本に分割）し、PR1 Web Push の土台を実装（ブランチ \`feature/web-push-foundation\`。push.ts の宛先を user_type で絞る・設定画面を開いたときの購読の登録し直しと古い鍵の購読の解除・購読は最後に登録したトレーナー1人のもの。DB 変更なし）。Edge Functions の VAPID secrets をオーナーが登録。`
- 40行目（フェーズ9 の行）の `9.1 拡張③ 睡眠悪化を実装（2026/10/03、\`feature/sleep-decline-alert\`、リモート適用待ち）` を `9.1 拡張③ 睡眠悪化（#96、2026/10/03 リモート適用済み）/ 9.1 拡張 トレーナー向け push に着手（2026/10/04、PR1 \`feature/web-push-foundation\`）` に変え、同じ行の `拡張（カロリー超過の検知、閾値設定、トレーナー向け push、消し込み、` から `トレーナー向け push、` を消す
- 9.1 の見出し行（`- [ ] **9.1 異常検知エンジン**`）の末尾 `カロリー超過・閾値のトレーナー設定・push は未着手` を `カロリー超過・閾値のトレーナー設定は未着手。push は設計済み・PR1 実装中（2026-10-04、下記）` に変える
- `- [ ] **オーナー作業**: develop へマージ後、... \`20261003000000\` の1本だけ ...` の行を `- [x] ✅ オーナーがリモート適用（2026-10-03）。` で始まる形に変える（後ろの元の手順の文は「当時の手順 →」に続けて残す）
- `- [ ] トレーナーへの通知はディスパッチャ経由（...）— Web 内バッジは ✅（MVP）。push は VAPID と APNs キーの設定待ち` の `push は VAPID と APNs キーの設定待ち` を `push は設計済み（2026-10-04、設計書 \`docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md\`。朝のまとめ1通）。トレーナーの Web Push は APNs と無関係で、VAPID は 2026-10-04 に Edge Functions へ登録済み` に変え、その直下に次の2行を足す:
  - `  - [ ] PR1 Web Push の土台（ブランチ \`feature/web-push-foundation\`、計画 \`docs/superpowers/plans/2026-10-04-web-push-foundation.md\`）: push.ts の宛先を user_type で絞る / 設定画面を開いたときの購読の登録し直しと古い鍵の購読の解除・失敗の表示 / 購読は最後に登録したトレーナー1人のもの。DB 変更なし。リリースは 2関数の再デプロイ（parse-message-tags・send-session-reminders）→ Web → 手順0（\`docs/tasks/2026-07-19-webpush-vapid-setup.md\`）`
  - `  - [ ] PR2 朝のまとめ（ブランチ \`feature/trainer-alert-push\`）: 通知の種別 client_alert・Edge Function notify-trainer-alerts・cron 06:10 JST（無効で登録）・sw.js・「今朝」の目印。PR1 のマージ後`

- [ ] **Step 5: 差分を見直して Commit**

Run: `git diff --stat` で4ファイルだけが変わっていること、`git diff fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md | grep -c 'BH4ih9V8'` が `1`（消した側の行だけ）であることを確かめる。

```bash
git add docs/tasks/2026-07-19-webpush-vapid-setup.md fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md docs/tasks/IMPLEMENTATION_TASKS.md
git commit -m "docs: Web Push の手順書を今の経路と鍵の置き場所に合わせ、9.1 push の進捗を更新

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 通しの確認と画面の確認（コントローラーが行う。コードは変えない）

設計書 §10.3 の最後・§10.4 の PR1 の部分・§10.5 の PR1 の部分。結果はレポートにまとめ、確かめられなかったものはその理由と代わりの確かめ方を書く。

- [ ] **Step 1: Web の検証セット**

`fit-connect/` で、`npx -y pnpm@10.32.1 test`・`npx -y pnpm@10.32.1 lint`・`npx -y pnpm@10.32.1 build`（`NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` はダミーを渡す）。`/settings` の First Load JS を、`develop/1.0.0` のビルドと比べて記録する

- [ ] **Step 2: 宛先の絞り込みの通しの確認（設計書 §10.4。隔離スタック）**

- scratch に隔離スタックを作る（`project_id` を別名、ポートを 58xxx 帯、`[db.seed]` 無効。共有スタックには触れない）
- 兼務アカウントを1つ作る: 同じ uid に `trainers` 行と `clients` 行、`device_tokens` に `user_type='trainer'`・`platform='web_push'`（token = scratch の HTTPS の受け口の URL、p256dh / auth はテスト用に作った鍵）と `user_type='client'`・`platform='ios'`（ダミーの FCM トークン）
- scratch の Deno スクリプトから `supabase/functions/_shared/push.ts` の `sendNotification` を直接呼ぶ（`kind: 'message'`）。環境変数は `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`（隔離スタックの値）・テスト用の `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT`。`FIREBASE_SERVICE_ACCOUNT_KEY` は渡さない
  - `userType: 'trainer'` → `notification_logs.detail` が `sent=1/1`（宛先は web_push の1件だけ）、受け口に1回届く
  - `userType: 'client'` → `detail` が `sent=0/1` と `fcm:skipped(no_service_account_key)`（宛先は ios の1件だけ）、受け口には届かない
- HTTPS の受け口に届かない場合（自己署名証明書の扱い。設計書 §10.4 の退路）は、`detail` の `sent=x/宛先数` の分母で宛先の振り分けを確かめ、その旨を書く
- 終わったら隔離スタックを `supabase stop --no-backup` で止める

- [ ] **Step 3: 画面の確認（隔離スタック + 合成 Cookie + 内蔵ブラウザ。設計書 §10.5 の PR1 の部分）**

- dev server（`-p 3100`、`NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:<kong>`）を2通り: (a) `NEXT_PUBLIC_VAPID_PUBLIC_KEY` 無し (b) 65バイトのダミーの公開鍵あり
- **許可とブラウザ API の差し替え方**: 内蔵ブラウザでは `Notification.permission` が最初から `'denied'`（親トグルが押せない）。各確認の前に `javascript_tool` で、`Object.defineProperty(Notification, 'permission', { get: () => '<値>', configurable: true })`、必要なら `Notification.requestPermission` と `navigator.serviceWorker` の `getRegistration` / `ready` / `register` と `pushManager`（`getSubscription` / `subscribe`）、`window.fetch` を差し替える。そのあと**リロードせず**、別の画面（`/dashboard` など）からサイドバーのリンクで `/settings` へクライアント側で遷移して、`NotificationSection` をマウントさせる（リロードすると差し替えが消える）。差し替えた API が呼ばれたかは、差し替えの中で `window.__calls` に記録して読む
- (a) 許可を `'default'` に見せ、`requestPermission` を記録だけする差し替えにして「プッシュ通知」を押す → `requestPermission` が呼ばれず、`現在プッシュ通知を有効にできません。時間をおいて再度お試しください。` が `role="alert"` で出る
- (b) 許可を `'granted'` に見せ、`getRegistration` → `undefined`、`ready` → 解決しない Promise にして設定画面を開く → 親トグルが押せる（`disabled` のまま固まらない。Review Focus 1）
- (b) 許可を `'granted'` に見せ、`getRegistration` が鍵の一致する購読（`options.applicationServerKey` にダミーの公開鍵と同じ65バイト）を持つ登録を返すようにして設定画面を開く → `POST /api/push-subscriptions` が1回だけ（StrictMode の dev でも二重にならない。Review Focus 2）。差し替えられない場合は、`syncPushSubscription` の単体テストで確かめた旨を書く
- (b) 鍵が違う購読に見せると、`DELETE` → トグルがオフ → `role="status"` の案内が出る。`fetch` を差し替えて `DELETE` を 500 にすると、購読が残りトグルもそのまま
- (b) 有効な購読があるとき、無効化で `DELETE` を 500 にすると、トグルはオンのまま `プッシュ通知の設定を変更できませんでした。再度お試しください。` が出る（Review Focus 4）
- 購読の所有者: トレーナー2人の合成 Cookie で同じ endpoint を `POST /api/push-subscriptions` すると、`device_tokens` の `web_push` 行は後の1人だけになり、`push_subscriptions` の `trainer_id` も後の1人になる
- 2人目の登録の失敗: 隔離スタックで `device_tokens` への書き込みを一時的に失敗させる（例: `service_role` から `device_tokens` の `DELETE` 権限を外す。終わったら戻す）と、2人目の `POST` が 500 になり、1人目の行は残る。失敗させられない場合は、Task 4 の単体テスト（throw）と `route.ts` の catch（500）で確かめた旨を書く
- 終わったら dev server と隔離スタックを止め、メインのチェックアウト直下に作った `.claude/launch.json` を消す

- [ ] **Step 4: 学びを `docs/tasks/lessons.md` に足して Commit**

確認で分かったこと（環境の癖・設計とのずれ）があれば、`docs/tasks/lessons.md` の末尾に「## Web Push の土台（フェーズ9.1 拡張 push の PR1、2026-10-04）で得た知見」として足す。無ければ足さない。

```bash
git add docs/tasks/lessons.md
git commit -m "docs: Web Push の土台で得た知見を lessons に追記

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 引き渡し（コントローラー）

- 全体のレビュー（最終）を通した後、`git reset --soft $(git merge-base HEAD origin/develop/1.0.0)` で1コミットにまとめ、`feature/web-push-foundation` を push して `develop/1.0.0` 向けの PR を作る（本文の末尾は `🤖 Generated with [Claude Code](https://claude.com/claude-code)`）
- PR の本文に、オーナー作業（設計書 §11.1: 漏えいした VAPID の鍵の作り直し → 2関数の再デプロイ → Web のリリース → 手順0 → メッセージ通知の回帰の確認）を書く
- `feature/trainer-alert-push`（設計書のコミットだけが載っている）は、PR1 のマージ後に `develop/1.0.0` から作り直して PR2 に使う
