# tags統一（基盤フェーズ）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** メッセージの「記録/会話」判定を `tags` カラム（`cardinality(tags) > 0`）に一本化し、送信時に `#` 付きタグを確実に付与する。webhookは補完役に降格し、既存データはマイグレーションで補完する。

**Architecture:** 3つの独立サブシステムを順に実装。(A) Mobile＝tags生成を `#` 付き共通純関数へ切り出し、ワークアウト達成にもタグ付与。(B) Web＝`tags` を型・パーサ・Realtimeに取り込み、判定を「tags優先＋content後方互換」に。(C) Backend＝webhookのtags書き込みを補完役（空時のみ）に降格し records 生成も tags 起点に、既存データを backfill。共通契約は **正準タグ＝`#`付き**（`#食事:昼食` / `#体重` / `#運動:筋トレ` / `#運動:完了`）。

**Tech Stack:** Flutter 3.41.9 (fvm) + Riverpod / Next.js 15 + TypeScript + Vitest / Supabase (PostgreSQL + Deno Edge Functions)

**確定済み設計判断（前提）:**
- ① 正準タグ＝`#`付きに統一
- ② webhook＝補完役（`tags`が空の時だけ補完。records生成・FCM通知は維持）
- ③ ワークアウト達成＝`#運動:完了` タグ付与 ＋ `exercise_records` に `other` で記録（B-1、消費カロリー取込）。`duration`/`distance`必須制約は削除済みのため追加対処不要。

---

## File Structure

**Phase A — Mobile (`fit-connect-mobile/`)**
- Create: `lib/features/messages/utils/message_tag_parser.dart` — tags生成の純関数（唯一の正準ロジック）
- Create: `test/features/messages/utils/message_tag_parser_test.dart`
- Modify: `lib/features/messages/presentation/screens/message_screen.dart` — `_parseTags`削除→共通関数へ
- Modify: `lib/features/workout/presentation/screens/workout_screen.dart` — 達成に`tags`付与

**Phase B — Web (`fit-connect/`)**
- Modify: `src/types/client.ts` — `Message`型に`tags`追加
- Modify: `src/components/message/recordCardParser.ts` — tags対応（tags優先＋content後方互換）
- Create: `src/components/message/recordCardParser.test.ts`
- Modify: `src/components/message/MessageBubble.tsx` — 呼び出しに`tags`渡す
- Modify: `src/app/(user_console)/message/page.tsx` — DB行→Message整形4箇所に`tags`

**Phase C — Backend (`supabase/`)**
- Modify: `functions/parse-message-tags/index.ts` — tags起点の判定＋補完役化
- Create: `migrations/20260607000000_backfill_message_tags.sql` — 既存データのtags補完
- Modify: `fit-connect/CLAUDE.md` — 古い`messages`スキーマ記述を修正

> 各Phaseは独立して実装・テスト可能。推奨実装順は A → B → C（A・Bが揃えば送受信が新形式で噛み合い、Cで旧データ・webhookを整える）。

---

## Phase A — Mobile

### Task A1: tags生成ロジックを純関数に切り出し（`#`付き正準形）＋ テスト

**Files:**
- Create: `fit-connect-mobile/lib/features/messages/utils/message_tag_parser.dart`
- Test: `fit-connect-mobile/test/features/messages/utils/message_tag_parser_test.dart`

- [ ] **Step 1: 失敗するテストを書く**

`fit-connect-mobile/test/features/messages/utils/message_tag_parser_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/messages/utils/message_tag_parser.dart';

void main() {
  group('parseMessageTags', () {
    test('#食事:種別が本文にあれば #付きで返す', () {
      expect(parseMessageTags('#食事:昼食 サラダチキン'), ['#食事:昼食']);
    });
    test('#食事 + 朝食キーワード → #食事:朝食', () {
      expect(parseMessageTags('#食事 朝食を食べた'), ['#食事:朝食']);
    });
    test('#食事 のみ（種別不明）→ #食事', () {
      expect(parseMessageTags('#食事 なにか'), ['#食事']);
    });
    test('#体重 → #体重', () {
      expect(parseMessageTags('#体重 62.4kg'), ['#体重']);
    });
    test('#運動 + 筋トレ → #運動:筋トレ', () {
      expect(parseMessageTags('#運動 筋トレした'), ['#運動:筋トレ']);
    });
    test('#運動 + ランニング → #運動:有酸素', () {
      expect(parseMessageTags('#運動 ランニング 30分'), ['#運動:有酸素']);
    });
    test('#運動 + 完了 → #運動:完了', () {
      expect(parseMessageTags('#運動:完了 脚の日'), ['#運動:完了']);
    });
    test('タグ無しは null', () {
      expect(parseMessageTags('こんにちは'), isNull);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd fit-connect-mobile && fvm flutter test test/features/messages/utils/message_tag_parser_test.dart`
Expected: コンパイルエラー（`message_tag_parser.dart` が存在しない / `parseMessageTags` 未定義）

- [ ] **Step 3: 実装を書く**

`fit-connect-mobile/lib/features/messages/utils/message_tag_parser.dart`:
```dart
/// メッセージ本文から記録タグ（#付き正準形）を抽出する。
/// 記録メッセージでなければ null を返す。
///
/// 正準形（#付き・1要素）:
///   '#食事:昼食 サラダ' → ['#食事:昼食']
///   '#食事 朝食'        → ['#食事:朝食']
///   '#体重 62.4kg'      → ['#体重']
///   '#運動 筋トレ'      → ['#運動:筋トレ']
///   '#運動:完了 脚の日' → ['#運動:完了']
List<String>? parseMessageTags(String text) {
  if (text.contains('#食事') || text.contains('#meal')) {
    if (text.contains('朝食') || text.contains('breakfast')) return ['#食事:朝食'];
    if (text.contains('昼食') || text.contains('lunch')) return ['#食事:昼食'];
    if (text.contains('夕食') || text.contains('dinner')) return ['#食事:夕食'];
    if (text.contains('間食') || text.contains('snack')) return ['#食事:間食'];
    return ['#食事'];
  } else if (text.contains('#体重') || text.contains('#weight')) {
    return ['#体重'];
  } else if (text.contains('#運動') || text.contains('#exercise')) {
    if (text.contains('完了')) return ['#運動:完了'];
    if (text.contains('筋トレ')) return ['#運動:筋トレ'];
    if (text.contains('有酸素') || text.contains('ランニング')) return ['#運動:有酸素'];
    return ['#運動'];
  }
  return null;
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd fit-connect-mobile && fvm flutter test test/features/messages/utils/message_tag_parser_test.dart`
Expected: All tests passed! (8 tests)

- [ ] **Step 5: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/utils/message_tag_parser.dart fit-connect-mobile/test/features/messages/utils/message_tag_parser_test.dart
git commit -m "feat(mobile): tags生成を#付き正準形の純関数として切り出し"
```

---

### Task A2: message_screen を共通パーサに置き換え（`#`付き化）

**Files:**
- Modify: `fit-connect-mobile/lib/features/messages/presentation/screens/message_screen.dart`

- [ ] **Step 1: import を追加**

ファイル冒頭の import 群に追加:
```dart
import 'package:fit_connect_mobile/features/messages/utils/message_tag_parser.dart';
```

- [ ] **Step 2: 旧 `_parseTags` メソッドを削除**

`/// タグを解析するプライベートメソッド` のコメント行から始まる `List<String>? _parseTags(String text) { ... }`（約L109〜L135、`return null;` と閉じ `}` まで）を**まるごと削除**する。

- [ ] **Step 3: 呼び出し2箇所を共通関数に置換**

`_editMessage` 内（約L141）:
```dart
    final newTags = parseMessageTags(newContent);
```
`_handleSend` 内（約L190）:
```dart
    final tags = parseMessageTags(text);
```
（`_parseTags(...)` を `parseMessageTags(...)` に変えるだけ。引数・代入先は変更しない）

- [ ] **Step 4: 静的解析で検証**

Run: `cd fit-connect-mobile && fvm flutter analyze lib/features/messages/presentation/screens/message_screen.dart`
Expected: No issues found!
（これ以降、通常メッセージの送信／編集時に `tags` が `#` 付きで保存される。`message_bubble.dart` の `_buildTag` は `#` 有無を吸収するため表示は不変）

- [ ] **Step 5: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/presentation/screens/message_screen.dart
git commit -m "refactor(mobile): message_screenのタグ生成を共通parseMessageTagsに統一"
```

---

### Task A3: ワークアウト達成メッセージに `#運動:完了` タグを付与

**Files:**
- Modify: `fit-connect-mobile/lib/features/workout/presentation/screens/workout_screen.dart`

- [ ] **Step 1: 達成送信に `tags` を追加**

`_handleSubmitCompletion` 内の `MessageRepository().sendMessage(...)`（約L61-67）を以下に変更:
```dart
        await MessageRepository().sendMessage(
          senderId: clientId,
          receiverId: trainerId,
          senderType: 'client',
          receiverType: 'trainer',
          content: messageContent,
          tags: ['#運動:完了'],
        );
```
（`content` の形式は変えない＝Webの達成カード表示は従来どおり content で判定される。`tags` 追加により tags 統一フィルタで「記録」に分類され、webhookが `exercise_records` を生成する）

- [ ] **Step 2: 静的解析で検証**

Run: `cd fit-connect-mobile && fvm flutter analyze lib/features/workout/presentation/screens/workout_screen.dart`
Expected: No issues found!

- [ ] **Step 3: コミット**

```bash
git add fit-connect-mobile/lib/features/workout/presentation/screens/workout_screen.dart
git commit -m "feat(mobile): ワークアウト達成に#運動:完了タグを付与"
```

---

## Phase B — Web

### Task B1: `Message` 型に `tags` を追加

**Files:**
- Modify: `fit-connect/src/types/client.ts`

- [ ] **Step 1: `image_urls` の直後に `tags` を追加**

`Message` 型（L87-106）の `image_urls: string[]`（L95）の直後に1行追加:
```ts
  image_urls: string[]
  tags?: string[] | null
  is_edited: boolean
```
（Realtime payload で欠落しうるため nullable。Mobile の `List<String>?` と整合）

- [ ] **Step 2: 型チェックで検証**

Run: `cd fit-connect && npx tsc --noEmit`
Expected: エラーなし（既存箇所は `tags` を未使用のため影響なし）

- [ ] **Step 3: コミット**

```bash
git add fit-connect/src/types/client.ts
git commit -m "feat(web): Message型にtagsフィールドを追加"
```

---

### Task B2: `recordCardParser` を tags 対応にする ＋ テスト

**Files:**
- Modify: `fit-connect/src/components/message/recordCardParser.ts`
- Test: `fit-connect/src/components/message/recordCardParser.test.ts`

- [ ] **Step 1: 失敗するテストを書く**

`fit-connect/src/components/message/recordCardParser.test.ts`:
```ts
import { describe, it, expect } from 'vitest'
import { parseRecordMessage } from '@/components/message/recordCardParser'

describe('parseRecordMessage — tags優先', () => {
  it('tagsが#食事:昼食なら、contentが#始まりでなくてもmeal判定', () => {
    const r = parseRecordMessage('サラダチキン', ['#食事:昼食'])
    expect(r?.type).toBe('meal')
    expect(r?.label).toBe('食事記録 ─ 昼食')
    expect(r?.details).toEqual(['サラダチキン'])
  })
  it('tagsが#体重なら weight 判定（本文はdetailsに）', () => {
    const r = parseRecordMessage('#体重 62.4kg', ['#体重'])
    expect(r?.type).toBe('weight')
    expect(r?.details).toEqual(['62.4kg'])
  })
  it('tagsが#運動:筋トレ なら exercise 判定', () => {
    const r = parseRecordMessage('#運動:筋トレ ベンチ 30分 150kcal', ['#運動:筋トレ'])
    expect(r?.type).toBe('exercise')
    expect(r?.label).toBe('運動記録 ─ 筋トレ')
  })
  it('tagsが#運動:完了 なら achievement 判定', () => {
    const r = parseRecordMessage('本日のワークアウトプラン「脚の日」を達成しました！', ['#運動:完了'])
    expect(r?.type).toBe('achievement')
  })
})

describe('parseRecordMessage — content後方互換（tags空）', () => {
  it('#体重 を従来どおり判定', () => {
    expect(parseRecordMessage('#体重 62.4kg')?.type).toBe('weight')
  })
  it('#食事:朝食 テキスト付き', () => {
    expect(parseRecordMessage('#食事:朝食 トースト')?.label).toBe('食事記録 ─ 朝食')
  })
  it('ワークアウト達成のcontentパターン（#なし）', () => {
    expect(parseRecordMessage('本日のワークアウトプラン「脚の日」を達成しました！')?.type).toBe('achievement')
  })
  it('通常メッセージは null', () => {
    expect(parseRecordMessage('こんにちは')).toBeNull()
  })
})
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd fit-connect && npx vitest run src/components/message/recordCardParser.test.ts`
Expected: FAIL（現状 `parseRecordMessage` は第2引数を無視し、`'サラダチキン'` は `#` 始まりでないため `null` を返す → 最初のテストが失敗）

- [ ] **Step 3: `recordCardParser.ts` を全面改修**

`fit-connect/src/components/message/recordCardParser.ts` を以下の内容に置き換える（既存の判定ロジックは `parseFromContent`/`buildExerciseCard` に保持し、tags ルートを追加。DRY）:
```ts
export type RecordCardType = 'weight' | 'meal' | 'exercise' | 'achievement'

export interface RecordCardData {
  type: RecordCardType
  label: string
  details: string[]
}

/**
 * content と tags から記録カード情報を返す。記録でなければ null。
 *
 * 判定方針（基盤フェーズ「tags統一」）:
 *   1. ワークアウト達成（#なしモバイル形式）は content で判定
 *   2. tags が非空なら、それを正準として判定（cardinality(tags) > 0 = 記録）
 *   3. tags が空なら従来の content 先頭タグ判定にフォールバック（後方互換）
 */
export function parseRecordMessage(content: string, tags?: string[] | null): RecordCardData | null {
  // --- ワークアウト達成（#なし現行モバイル形式）---
  const workoutAchievementMatch = content.match(/^本日のワークアウトプラン「([^」]+)」を達成しました！/)
  if (workoutAchievementMatch) {
    const details: string[] = [`「${workoutAchievementMatch[1]}」を達成しました！`]
    const caloriesMatch = content.match(/🔥\s*消費カロリー:\s*(\d+)\s*kcal/)
    if (caloriesMatch) details.push(`🔥 ${caloriesMatch[1]}kcal`)
    const feedbackMatch = content.match(/💬\s*(.+)/)
    if (feedbackMatch) details.push(`💬 ${feedbackMatch[1].trim()}`)
    return { type: 'achievement', label: 'ワークアウト達成！', details }
  }

  // --- tags 優先判定 ---
  if (tags && tags.length > 0) {
    const fromTag = parseFromTag(tags[0], content)
    if (fromTag) return fromTag
  }

  // --- 従来の content ベース判定（tags空・後方互換）---
  if (!content.startsWith('#')) return null
  return parseFromContent(content)
}

/** tag（#付き正準形）から記録カードを構築。本文は content から先頭タグを除いた残り。 */
function parseFromTag(tag: string, content: string): RecordCardData | null {
  const m = tag.match(/^#(体重|食事|運動)(?::(.+))?$/)
  if (!m) return null
  const category = m[1]
  const detail = m[2]?.trim()
  const body = content.replace(/^#(食事|運動|体重)(?::[^\s]+)?\s*/, '').trim()

  if (category === '体重') {
    return { type: 'weight', label: '体重記録', details: body ? [body] : [] }
  }
  if (category === '食事') {
    return {
      type: 'meal',
      label: detail ? `食事記録 ─ ${detail}` : '食事記録',
      details: body ? [body] : [],
    }
  }
  // category === '運動'
  if (detail === '完了') {
    const quoted = content.match(/「([^」]+)」/)
    return {
      type: 'achievement',
      label: 'ワークアウト達成！',
      details: quoted ? [`「${quoted[1]}」を達成しました！`] : (body ? [body] : []),
    }
  }
  return buildExerciseCard(detail ?? '', body)
}

/** 従来の content 先頭タグ判定（既存ロジックを保持）。 */
function parseFromContent(content: string): RecordCardData | null {
  const weightMatch = content.match(/^#体重\s+(.+)$/)
  if (weightMatch) {
    return { type: 'weight', label: '体重記録', details: [weightMatch[1].trim()] }
  }
  const mealMatch = content.match(/^#食事:([^\s]+)\s+(.+)$/)
  if (mealMatch) {
    return { type: 'meal', label: `食事記録 ─ ${mealMatch[1].trim()}`, details: [mealMatch[2].trim()] }
  }
  const mealOnlyMatch = content.match(/^#食事:([^\s]+)$/)
  if (mealOnlyMatch) {
    return { type: 'meal', label: `食事記録 ─ ${mealOnlyMatch[1].trim()}`, details: [] }
  }
  const achievementMatch = content.match(/^#運動:完了\s+(.+)$/)
  if (achievementMatch) {
    const text = achievementMatch[1].trim()
    const quotedMatch = text.match(/「([^」]+)」/)
    return {
      type: 'achievement',
      label: 'ワークアウト達成！',
      details: quotedMatch ? [`「${quotedMatch[1]}」を達成しました！`] : [text],
    }
  }
  const exerciseMatch = content.match(/^#運動:([^\s]+)\s+(.+)$/)
  if (exerciseMatch) {
    return buildExerciseCard(exerciseMatch[1].trim(), exerciseMatch[2].trim())
  }
  return null
}

/** 運動カードを構築（本文から duration/calories を抽出）。 */
function buildExerciseCard(exerciseType: string, rest: string): RecordCardData {
  const durationMatch = rest.match(/(\d+)\s*分/)
  const caloriesMatch = rest.match(/(\d+)\s*(?:キロカロリー|kcal|cal)/i)
  const bodyText = rest
    .replace(/\d+\s*分/, '')
    .replace(/\d+\s*(?:キロカロリー|kcal|cal)/gi, '')
    .replace(/\s{2,}/g, ' ')
    .trim()
  const details: string[] = []
  if (bodyText) details.push(bodyText)
  const metaParts: string[] = []
  if (durationMatch) metaParts.push(`${durationMatch[1]}分`)
  if (caloriesMatch) metaParts.push(`${caloriesMatch[1]}kcal`)
  if (metaParts.length > 0) details.push(metaParts.join(' ・ '))
  return {
    type: 'exercise',
    label: `運動記録 ─ ${exerciseType}`,
    details: details.length > 0 ? details : [rest],
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd fit-connect && npx vitest run src/components/message/recordCardParser.test.ts`
Expected: PASS（8 tests）

- [ ] **Step 5: コミット**

```bash
git add fit-connect/src/components/message/recordCardParser.ts fit-connect/src/components/message/recordCardParser.test.ts
git commit -m "feat(web): recordCardParserをtags優先判定に対応（content後方互換）"
```

---

### Task B3: `MessageBubble` の呼び出しに `tags` を渡す

**Files:**
- Modify: `fit-connect/src/components/message/MessageBubble.tsx`

- [ ] **Step 1: 呼び出しを更新**

L46 を変更:
```ts
  const recordCardData = !isTrainer ? parseRecordMessage(message.content, message.tags) : null
```

- [ ] **Step 2: 型チェックで検証**

Run: `cd fit-connect && npx tsc --noEmit`
Expected: エラーなし

- [ ] **Step 3: コミット**

```bash
git add fit-connect/src/components/message/MessageBubble.tsx
git commit -m "feat(web): MessageBubbleからtagsをparserに渡す"
```

---

### Task B4: `page.tsx` のDB行→Message整形に `tags` を反映（4箇所）

**Files:**
- Modify: `fit-connect/src/app/(user_console)/message/page.tsx`

- [ ] **Step 1: 楽観更新（トレーナー送信、約L109）に `tags: []` を追加**

`newMsg` オブジェクトの `image_urls: imageUrls,`（L109）の直後に追加:
```ts
                    image_urls: imageUrls,
                    tags: [],
```
（トレーナー送信は記録対象外。型整合のため空配列）

- [ ] **Step 2: 初回フェッチ整形（約L304）に `tags` を追加**

`image_urls: msg.image_urls || [],`（L304）の直後に追加:
```ts
                        image_urls: msg.image_urls || [],
                        tags: msg.tags || [],
```

- [ ] **Step 3: Realtime INSERT（約L373）に `tags` を追加**

`image_urls: msg.image_urls || [],`（L373）の直後に追加:
```ts
                                image_urls: msg.image_urls || [],
                                tags: msg.tags || [],
```

- [ ] **Step 4: Realtime UPDATE（約L410-416）に `tags` 反映を追加（★最重要）**

`setMessages` の `map` 内、`read_at: msg.read_at || null,`（L415）の直後に追加:
```ts
                                        read_at: msg.read_at || null,
                                        tags: msg.tags ?? m.tags,
```
（webhookが補完するケースでも `tags` がUPDATEイベントで届く。これが無いと補完時に記録カードへ反映されない。`?? m.tags` で欠落時は既存値を保持）

- [ ] **Step 5: 型チェックで検証**

Run: `cd fit-connect && npx tsc --noEmit`
Expected: エラーなし

- [ ] **Step 6: コミット**

```bash
git add "fit-connect/src/app/(user_console)/message/page.tsx"
git commit -m "feat(web): メッセージ整形4箇所にtagsを反映（Realtime UPDATE含む）"
```

---

## Phase C — Backend

### Task C1: webhook を「tags起点判定 ＋ 補完役」に改修

**Files:**
- Modify: `supabase/functions/parse-message-tags/index.ts`

設計: 送信側が付けた `tags` を正準とする。webhookは (1) records生成の判定を tags 起点（無ければcontent）に、(2) tags書き込みは「空の時だけ補完」に降格。createMeal/Weight/Exercise の各関数は `tagData` を受ける既存実装をそのまま再利用（達成は `detail='完了'` → `exercise_type='other'`、カロリーはnotesから抽出。制約削除済みのためカロリーのみで保存可）。

- [ ] **Step 1: `parseTagFromTags` ヘルパーを追加**

既存の `parseTag` 関数（L131-142）の直後に追加:
```ts
/**
 * tags配列（#付き正準形）から tagData を構築する。送信側付与のtagsを正準として扱う。
 * @example parseTagFromTags(['#運動:完了'], '本日の…達成しました！🔥 消費カロリー: 300kcal')
 *   // => { category: '運動', detail: '完了', fullTag: '#運動:完了', remainingContent: '本日の…300kcal' }
 */
function parseTagFromTags(tags, content) {
  if (!tags || tags.length === 0) return null
  const fullTag = tags[0]
  const m = fullTag.match(/^#(食事|運動|体重)(?::(.+))?$/)
  if (!m) return null
  return {
    category: m[1],
    detail: m[2],
    fullTag,
    remainingContent: (content || '').replace(fullTag, '').trim(),
  }
}
```

- [ ] **Step 2: メインの判定・tags書き込みを差し替え**

`Deno.serve` 内の「`// 1. Parse Tag`」から `// 3. Create specific record` の前まで（現状 L46-72 付近）を以下に置き換える:
```ts
      // 0. Re-fetch full row (webhook payload may omit columns like tags/metadata)
      const { data: fullRow, error: fetchErr } = await supabase
        .from('messages')
        .select('metadata, tags')
        .eq('id', message.id)
        .maybeSingle()
      if (fetchErr) {
        console.error('Failed to re-fetch message row:', fetchErr)
      } else if (fullRow) {
        message.metadata = fullRow.metadata
        message.tags = fullRow.tags
      }

      // 1. Determine tag — 送信側付与のtagsを正準とし、無ければcontentから解析
      const tagData = parseTagFromTags(message.tags, message.content) ?? parseTag(message.content)

      if (tagData) {
        // 2. tags が空のときだけ補完（送信側付与を主とする。空でなければ上書きしない）
        if (!message.tags || message.tags.length === 0) {
          const { error: updateError } = await supabase.from('messages').update({
            tags: [tagData.fullTag]
          }).eq('id', message.id)
          if (updateError) {
            console.error('Error backfilling message tags:', updateError)
          }
        }
```
（この置換後、続く `// 3. Create specific record based on category` の `const commonData = {...}` 以降は**現状のまま**。`if (tagData) {` のブロック開始は上の置換に含めたので、元の `if (tagData) {`〜再フェッチ block と重複しないよう、元の L49 `if (tagData) {` と L50-61 の旧再フェッチを削除すること）

> 実装注意: 旧コードは `parseTag` → `if (tagData) {` → 再フェッチ → tags update の順。新コードは「再フェッチ → tagData判定 → if → tags補完」の順に組み替える。`createMealRecord`/`createWeightRecord`/`createExerciseRecord` の呼び出しと `commonData` は変更不要。

- [ ] **Step 3: ローカルで webhook を起動して構文確認**

Run: `cd /Users/hoshidayuuya/Documents/FIT-CONNECT && supabase functions serve parse-message-tags --no-verify-jwt`
Expected: 起動エラーが出ないこと（型/構文エラーがあればここで判明）。確認後 Ctrl+C で停止。
※ Docker未起動の場合は先に Docker Desktop を起動。

- [ ] **Step 4: コミット**

```bash
git add supabase/functions/parse-message-tags/index.ts
git commit -m "feat(backend): webhookをtags起点判定＋補完役に降格"
```

---

### Task C2: 既存データの tags 補完マイグレーション

**Files:**
- Create: `supabase/migrations/20260607000000_backfill_message_tags.sql`

- [ ] **Step 1: マイグレーションファイルを作成**

`supabase/migrations/20260607000000_backfill_message_tags.sql`:
```sql
-- 既存 messages の tags を content から補完する（基盤フェーズ「tags統一」）。
-- 対象: cardinality(tags)=0（タグ未設定）かつ content が既知の記録パターン。
-- 正準形は '#' 付き（messages.tags コメント準拠）。
-- 既存 *_records には一切触れない（tags カラムのみ更新）。
-- tags のみのUPDATEは content列変更時のみ発火するwebhookトリガを誘発しないため安全。
-- POSIX正規表現（否定先読み非対応のため !~ で代替）。content先頭一致(^)で誤検出を防止。

BEGIN;

-- 食事（detail あり）: '#食事:朝食 …' → '#食事:朝食'
UPDATE "public"."messages"
SET tags = ARRAY['#食事:' || substring(content from '^#食事:([^[:space:]]+)')]
WHERE cardinality(tags) = 0
  AND content ~ '^#食事:[^[:space:]]+';

-- 食事（detail なし）: '^#食事' で始まり ':' が続かない → '#食事'
UPDATE "public"."messages"
SET tags = ARRAY['#食事']
WHERE cardinality(tags) = 0
  AND content ~ '^#食事'
  AND content !~ '^#食事:';

-- 体重: '^#体重' → '#体重'
UPDATE "public"."messages"
SET tags = ARRAY['#体重']
WHERE cardinality(tags) = 0
  AND content ~ '^#体重';

-- 運動（detail あり）: '#運動:筋トレ …' / '#運動:完了 …' → '#運動:筋トレ' / '#運動:完了'
UPDATE "public"."messages"
SET tags = ARRAY['#運動:' || substring(content from '^#運動:([^[:space:]]+)')]
WHERE cardinality(tags) = 0
  AND content ~ '^#運動:[^[:space:]]+';

-- 運動（detail なし）: '^#運動' で始まり ':' が続かない → '#運動'
UPDATE "public"."messages"
SET tags = ARRAY['#運動']
WHERE cardinality(tags) = 0
  AND content ~ '^#運動'
  AND content !~ '^#運動:';

-- ワークアウト達成（#なし現行モバイル形式）→ '#運動:完了'
UPDATE "public"."messages"
SET tags = ARRAY['#運動:完了']
WHERE cardinality(tags) = 0
  AND content LIKE '本日のワークアウトプラン「%」を達成しました！%';

COMMIT;
```

- [ ] **Step 2: ローカルDBにクリーン適用して検証**

Run（Docker Desktop 起動後、ルートから）:
```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT && supabase start && supabase db reset
```
Expected: 全マイグレーションがタイムスタンプ順に適用され、`20260607000000_backfill_message_tags.sql` がエラーなく流れること（構文・冪等性の検証）。

- [ ] **Step 3: 取りこぼし確認クエリ**

Supabase Studio (`http://localhost:54323`) のSQLエディタ、または psql で実行:
```sql
SELECT id, left(content, 40) AS content_head, tags
FROM messages
WHERE cardinality(tags) = 0
  AND (content LIKE '#%' OR content LIKE '本日のワークアウトプラン%');
```
Expected: 0行（記録パターンの取りこぼしが無いこと）。残れば WHERE 条件を調整。

- [ ] **Step 4: コミット**

```bash
git add supabase/migrations/20260607000000_backfill_message_tags.sql
git commit -m "feat(backend): 既存messagesのtagsをcontentから補完するマイグレーション"
```

> ⚠️ 本番反映（`supabase db push`）は**ユーザー承認後にのみ**実行。実行前に本番で件数を計測（下記）。

---

### Task C3: 本番反映前チェックリスト（実行はユーザー承認後）

- [ ] **Step 1: 本番の移行対象規模を計測（read-only）**

本番接続情報を用意し（`.env`は参照しない。`PGPASSWORD` 手動指定 or Studio）、以下を実行:
```sql
SELECT count(*) AS migration_targets
FROM messages
WHERE cardinality(tags) = 0
  AND (content LIKE '#食事%' OR content LIKE '#体重%' OR content LIKE '#運動%'
       OR content LIKE '本日のワークアウトプラン「%」を達成しました！%');
SELECT sender_type, count(*) FROM messages
WHERE cardinality(tags) > 0 OR content LIKE '#%' OR content LIKE '本日のワークアウト%'
GROUP BY sender_type;  -- trainer発の記録が無いことを確認
```

- [ ] **Step 2: webhook をデプロイ → マイグレーションを push**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
supabase functions deploy parse-message-tags --no-verify-jwt
supabase db push
```
Expected: デプロイ成功、`20260607000000` がリモートに適用される。

---

### Task C4: 古いスキーマ記述の修正

**Files:**
- Modify: `fit-connect/CLAUDE.md`

- [ ] **Step 1: `messages` テーブルの記述を実体に合わせる**

`fit-connect/CLAUDE.md` の **messages** セクション（`message` / `timestamp` カラムと記載されている箇所）を、実スキーマに修正:
- `message (TEXT)` → `content (TEXT)`
- `timestamp (TIMESTAMPTZ)` → `created_at (TIMESTAMPTZ)`
- 不足カラムを追記: `tags (TEXT[]) - 記録分類タグ（例 ["#食事:昼食"]）`, `metadata (JSONB) - meal_estimation等`, `image_urls`, `reply_to_message_id`, `read_at`, `edited_at`, `is_edited`

- [ ] **Step 2: コミット**

```bash
git add fit-connect/CLAUDE.md
git commit -m "docs(web): messagesスキーマ記述を実体（content/created_at/tags/metadata）に修正"
```

---

## Self-Review

**1. Spec coverage（design docの基盤フェーズ要件 → タスク対応）:**
- 判定基準を `cardinality(tags)>0` に一本化 → B2（Web判定）/ A1（Mobile生成）/ C1（webhook判定）✓
- 送信時にtagsを確実に付与 → A2（通常）/ A3（ワークアウト達成）✓
- webhookを補完役に → C1 ✓
- 全種類の記録をタグ対象（達成含む）→ A3 + C1（exercise_records生成）✓
- 既存データのマイグレーション → C2 ✓
- 型/モデル更新 → B1（Web型）。Mobileモデルは対応済みのため変更なし ✓
- CLAUDE.md古い記述修正 → C4 ✓
- ③ B-1（達成をexercise_recordsにother+カロリーで記録）→ A3 + C1（制約削除済みで保存可）✓

**2. Placeholder scan:** 各コードステップに完全な実装を記載。"TBD"等なし。Backend のテストはユニット基盤が無いため `functions serve` 起動確認＋`db reset`＋検証クエリで代替（明示済み）。

**3. Type/naming consistency:**
- Mobile: `parseMessageTags(String) → List<String>?`（#付き）。A1で定義しA2/（A3は固定値）で使用 ✓
- Web: `parseRecordMessage(content, tags?)` / `parseFromTag` / `parseFromContent` / `buildExerciseCard`。B2で定義しB3で呼び出し ✓
- Backend: `parseTagFromTags(tags, content)` がC1の `parseTag` と同じ tagData 形 `{category, detail, fullTag, remainingContent}` を返す → 既存 `createMealRecord` 等と互換 ✓
- 正準タグ形式 `#カテゴリ(:detail)?` が3層で一致（Mobile生成 / Web解釈 / Backend解釈 / SQL backfill）✓
