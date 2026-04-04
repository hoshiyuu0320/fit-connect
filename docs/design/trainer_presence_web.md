# トレーナー Presence（オンライン/オフライン）Web側 設計書

## 概要

トレーナーがWebアプリ（Next.js）を開いている間は `is_online = true`、
閉じたら `is_online = false` + `last_seen_at = now()` に更新する。

クライアント側（Flutter）は Supabase Realtime で `trainers` テーブルの変更を購読済み。
Web側は **DB更新のみ** を担当する。

---

## アーキテクチャ

```
トレーナーWebアプリ (Next.js)
│
├── ページロード時 → UPDATE trainers SET is_online = true
├── ハートビート (60秒毎) → UPDATE trainers SET last_seen_at = now()
├── ページ離脱時 → UPDATE trainers SET is_online = false, last_seen_at = now()
│   ├── visibilitychange (タブ非表示)
│   ├── beforeunload (タブ/ブラウザ閉じ)
│   └── pagehide (iOS Safari対応)
│
└── trainers テーブル (Supabase)
    ├── is_online: boolean
    └── last_seen_at: timestamptz
        │
        └── Realtime → Flutter クライアントアプリに即時反映
```

---

## DB（対応済み）

| カラム | 型 | 説明 |
|--------|-----|------|
| `is_online` | `boolean NOT NULL DEFAULT false` | アプリ起動中 = true |
| `last_seen_at` | `timestamptz` | 最後にオンラインだった日時 |

RLSポリシー `trainers_update_own` により、トレーナーは自分の行のみ更新可能（対応済み）。

---

## 実装（Next.js側）

### 1. Presence フック作成

**ファイル:** `src/hooks/usePresence.ts`

```typescript
"use client";

import { useEffect, useRef } from "react";
import { createClient } from "@/lib/supabase";

export function usePresence() {
  const supabase = createClient();
  const heartbeatRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    // オンラインに設定
    const goOnline = async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      await supabase
        .from("trainers")
        .update({ is_online: true, last_seen_at: new Date().toISOString() })
        .eq("id", user.id);
    };

    // オフラインに設定
    const goOffline = async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      await supabase
        .from("trainers")
        .update({ is_online: false, last_seen_at: new Date().toISOString() })
        .eq("id", user.id);
    };

    // ハートビート（60秒毎に last_seen_at を更新）
    const startHeartbeat = () => {
      heartbeatRef.current = setInterval(async () => {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return;

        await supabase
          .from("trainers")
          .update({ last_seen_at: new Date().toISOString() })
          .eq("id", user.id);
      }, 60_000);
    };

    // タブの表示/非表示
    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        goOnline();
        startHeartbeat();
      } else {
        goOffline();
        if (heartbeatRef.current) clearInterval(heartbeatRef.current);
      }
    };

    // ブラウザ/タブ閉じ（sendBeacon でベストエフォート送信）
    const handleBeforeUnload = () => {
      const { data } = supabase.auth.getSession(); // sync not available
      // sendBeacon で確実に送信（fetch は cancel される可能性あり）
      navigator.sendBeacon(
        `/api/presence/offline`
      );
    };

    // 初期化
    goOnline();
    startHeartbeat();

    // イベントリスナー登録
    document.addEventListener("visibilitychange", handleVisibilityChange);
    window.addEventListener("beforeunload", handleBeforeUnload);
    window.addEventListener("pagehide", handleBeforeUnload);

    // クリーンアップ
    return () => {
      if (heartbeatRef.current) clearInterval(heartbeatRef.current);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.removeEventListener("beforeunload", handleBeforeUnload);
      window.removeEventListener("pagehide", handleBeforeUnload);
      goOffline();
    };
  }, []);
}
```

### 2. sendBeacon 用 API Route

`beforeunload` では `async/await` が使えないため、`sendBeacon` + サーバー側 API Route で確実にオフライン処理する。

**ファイル:** `src/app/api/presence/offline/route.ts`

```typescript
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

export async function POST() {
  const cookieStore = await cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll() } }
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  await supabase
    .from("trainers")
    .update({ is_online: false, last_seen_at: new Date().toISOString() })
    .eq("id", user.id);

  return NextResponse.json({ ok: true });
}
```

### 3. レイアウトに組み込み

認証済みレイアウト（`/dashboard` 配下など）で `usePresence` を呼ぶだけ。

**ファイル:** `src/app/(authenticated)/layout.tsx` （既存のレイアウトに追加）

```tsx
"use client";

import { usePresence } from "@/hooks/usePresence";

export default function AuthenticatedLayout({ children }) {
  usePresence(); // これだけ追加

  return <>{children}</>;
}
```

---

## イベント別の動作

| イベント | 処理 | 備考 |
|----------|------|------|
| ページロード | `is_online = true` | useEffect 初回実行 |
| 60秒毎 | `last_seen_at = now()` | ハートビート（クラッシュ対策） |
| タブ非表示 | `is_online = false, last_seen_at = now()` | `visibilitychange` |
| タブ再表示 | `is_online = true` | `visibilitychange` |
| タブ/ブラウザ閉じ | `is_online = false, last_seen_at = now()` | `sendBeacon` → API Route |
| useEffect cleanup | `goOffline()` | SPA遷移時 |

---

## クラッシュ/強制終了への対策

ブラウザがクラッシュした場合、`beforeunload` は発火しない。
→ ハートビート（60秒毎の `last_seen_at` 更新）により、Flutter側で以下の安全策が可能:

```
if (is_online == true && last_seen_at < 2分前) → 実質オフラインとみなす
```

※ 現時点のFlutter実装では `is_online` をそのまま信頼。
必要に応じて上記チェックを `TrainerPresenceNotifier` に追加可能。

---

## ファイル一覧（新規/変更）

| ファイル | 種別 | 説明 |
|----------|------|------|
| `src/hooks/usePresence.ts` | 新規 | Presenceフック |
| `src/app/api/presence/offline/route.ts` | 新規 | sendBeacon用APIルート |
| `src/app/(authenticated)/layout.tsx` | 変更 | `usePresence()` 呼び出し追加 |
