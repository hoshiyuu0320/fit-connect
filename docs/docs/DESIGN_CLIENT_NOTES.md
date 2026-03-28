# カルテ（トレーナーノート）機能 - モバイル側設計書

**作成日**: 2026年2月14日
**対象**: Flutter モバイルアプリ（クライアント側）
**前提**: Web側（トレーナー側）のカルテCRUD + ファイルアップロード + 共有管理は実装済み

---

## 1. 概要

### 機能説明
トレーナーが Web アプリで作成した「カルテ（セッションノート）」のうち、**共有済み（`is_shared = true`）のもの**をクライアントのモバイルアプリで閲覧できる機能。

### クライアント側の操作範囲
- **読み取り専用**（閲覧のみ）
- 作成・編集・削除はトレーナー Web 側のみ
- 添付ファイル（PDF / 画像）の閲覧・ダウンロード

---

## 2. データベース（既存）

### `client_notes` テーブル（作成済み）

| カラム | 型 | 説明 |
|--------|------|------|
| `id` | UUID PK | ノートID |
| `client_id` | UUID FK → clients | クライアントID |
| `trainer_id` | UUID FK → trainers | トレーナーID |
| `title` | TEXT | タイトル |
| `content` | TEXT | 本文 |
| `file_urls` | TEXT[] | 添付ファイルURL配列 |
| `is_shared` | BOOLEAN | 共有フラグ |
| `shared_at` | TIMESTAMPTZ | 共有日時 |
| `session_number` | INT | セッション番号 |
| `created_at` | TIMESTAMPTZ | 作成日時 |
| `updated_at` | TIMESTAMPTZ | 更新日時 |

### RLS ポリシー追加が必要

```sql
-- クライアントは自分宛てかつ共有済みのノートのみ閲覧可能
CREATE POLICY "clients_select_shared_notes" ON client_notes
  FOR SELECT USING (is_shared = true AND client_id = auth.uid());
```

### Storage バケット
- バケット名: `client-notes`
- 公開バケット（public = true）
- 許可形式: JPEG, PNG, WebP, PDF
- 最大サイズ: 10MB

---

## 3. 画面配置

### Records 画面のタブに追加

**現在**: `Meals | Weight | Exercise`（3タブ）
**変更後**: `Meals | Weight | Exercise | Notes`（4タブ）

```
┌─────────────────────────────────┐
│            Records              │
│                                 │
│ Meals   Weight   Exercise  Notes│
│                            ━━━━━│
└─────────────────────────────────┘
```

---

## 4. 実装ステップ

### Step 1: Model 作成

**ファイル**: `lib/features/client_notes/models/client_note_model.dart`

**参照パターン**: `lib/features/meal_records/models/meal_record_model.dart`

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'client_note_model.g.dart';

@JsonSerializable()
class ClientNote {
  final String id;

  @JsonKey(name: 'client_id')
  final String clientId;

  @JsonKey(name: 'trainer_id')
  final String trainerId;

  final String title;
  final String content;

  @JsonKey(name: 'file_urls')
  final List<String> fileUrls;

  @JsonKey(name: 'is_shared')
  final bool isShared;

  @NullableDateTimeConverter()
  @JsonKey(name: 'shared_at')
  final DateTime? sharedAt;

  @JsonKey(name: 'session_number')
  final int? sessionNumber;

  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const ClientNote({
    required this.id,
    required this.clientId,
    required this.trainerId,
    required this.title,
    required this.content,
    this.fileUrls = const [],
    required this.isShared,
    this.sharedAt,
    this.sessionNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClientNote.fromJson(Map<String, dynamic> json) =>
      _$ClientNoteFromJson(json);
  Map<String, dynamic> toJson() => _$ClientNoteToJson(this);
}
```

**コード生成**: `dart run build_runner build --delete-conflicting-outputs`

---

### Step 2: Repository 作成

**ファイル**: `lib/features/client_notes/data/client_note_repository.dart`

**参照パターン**: `lib/features/meal_records/data/meal_repository.dart`

```dart
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

class ClientNoteRepository {
  final _supabase = SupabaseService.client;

  /// 共有済みカルテ一覧を取得（クライアント用）
  Future<List<ClientNote>> getSharedNotes({
    required String clientId,
  }) async {
    final response = await _supabase
        .from('client_notes')
        .select()
        .eq('client_id', clientId)
        .eq('is_shared', true)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => ClientNote.fromJson(json))
        .toList();
  }

  /// 共有済みカルテ件数を取得（Home画面サマリー用、将来実装）
  Future<int> getSharedNotesCount({
    required String clientId,
  }) async {
    final response = await _supabase
        .from('client_notes')
        .select('id')
        .eq('client_id', clientId)
        .eq('is_shared', true);

    return (response as List).length;
  }
}
```

---

### Step 3: Provider 作成

**ファイル**: `lib/features/client_notes/providers/client_notes_provider.dart`

**参照パターン**: `lib/features/meal_records/providers/meal_records_provider.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/data/client_note_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'client_notes_provider.g.dart';

/// ClientNoteRepositoryのProvider
@riverpod
ClientNoteRepository clientNoteRepository(ClientNoteRepositoryRef ref) {
  return ClientNoteRepository();
}

/// 共有済みカルテ一覧を取得するProvider
@riverpod
Future<List<ClientNote>> sharedClientNotes(SharedClientNotesRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final repository = ref.watch(clientNoteRepositoryProvider);
  return repository.getSharedNotes(clientId: clientId);
}
```

**コード生成**: `dart run build_runner build --delete-conflicting-outputs`

---

### Step 4: UI - カルテ一覧 Screen

**ファイル**: `lib/features/client_notes/presentation/screens/client_notes_screen.dart`

**参照パターン**: `lib/features/meal_records/presentation/screens/meal_record_screen.dart`

#### 画面仕様

```
┌─────────────────────────────────┐
│                                 │
│  ┌─────────────────────────────┐│
│  │  From your trainer          ││
│  │  共有されたカルテ: 3件       ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │ #12  下半身強化プログラム    ││
│  │ 2026/02/14                  ││
│  │                             ││
│  │ 下半身の筋力不足が課題。    ││
│  │ スクワットのフォームを...    ││
│  │                             ││
│  │ 📎 2 files attached    [>]  ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │ #11  フォーム改善メモ        ││
│  │ 2026/02/07                  ││
│  │                             ││
│  │ スクワットの膝の角度を...    ││
│  │                             ││
│  │ 📎 1 file attached     [>]  ││
│  └─────────────────────────────┘│
│                                 │
│ (Empty State)                   │
│  ┌─────────────────────────────┐│
│  │     📋                      ││
│  │  No notes shared yet        ││
│  │  Your trainer hasn't shared ││
│  │  any session notes yet.     ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

#### UI構成

```dart
class ClientNotesScreen extends ConsumerWidget {
  // Riverpod ConsumerWidget
  // ref.watch(sharedClientNotesProvider) でデータ取得
  // AsyncValue パターンで loading / error / data を処理
}
```

#### デザイン仕様

| 要素 | 仕様 |
|------|------|
| **背景色** | `AppColors.slate50` |
| **カードスタイル** | 白背景、`BorderRadius.circular(16)`、`BoxShadow` 薄いグレー |
| **サマリーカード** | `AppColors.primary50` 背景、トレーナーアイコン + 件数 |
| **セッション番号** | `AppColors.primary600`、`FontWeight.bold` |
| **タイトル** | `AppColors.slate800`、`fontSize: 16`、`FontWeight.w600` |
| **日付** | `AppColors.slate400`、`fontSize: 12` |
| **本文プレビュー** | `AppColors.slate600`、`fontSize: 14`、`maxLines: 2`、`TextOverflow.ellipsis` |
| **添付ファイルバッジ** | `AppColors.slate100` 背景、クリップアイコン + ファイル数 |
| **矢印アイコン** | `Icons.chevron_right`（Lucide Icons使用可なら `LucideIcons.chevronRight`） |
| **空状態** | 中央配置、アイコン + テキスト2行、`AppColors.slate400` |

---

### Step 5: UI - カルテ詳細 Screen

**ファイル**: `lib/features/client_notes/presentation/screens/client_note_detail_screen.dart`

#### 画面仕様

```
┌─────────────────────────────────┐
│  ← 戻る                        │
│                                 │
│  ┌─────────────────────────────┐│
│  │                             ││
│  │  #12                        ││
│  │  下半身強化プログラム        ││
│  │                             ││
│  │  by 星田優哉                ││
│  │  2026年2月14日              ││
│  │                             ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │ 内容                        ││
│  │                             ││
│  │ 下半身の筋力不足が課題。    ││
│  │ スクワットのフォームを改善  ││
│  │ し、膝の角度を90度に保つ    ││
│  │ ことを意識する。            ││
│  │                             ││
│  │ 次回のセッションでは、      ││
│  │ レッグプレスとランジを追加。││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │ 添付ファイル (2)             ││
│  │                             ││
│  │ ┌─────────────────────────┐ ││
│  │ │ 📄 session_notes.pdf   │ ││
│  │ │ PDF • タップして表示    │ ││
│  │ └─────────────────────────┘ ││
│  │                             ││
│  │ ┌─────────────────────────┐ ││
│  │ │ 🖼 [画像プレビュー]     │ ││
│  │ │    form_check.jpg       │ ││
│  │ └─────────────────────────┘ ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

#### ファイル表示ロジック

| ファイル種別 | 判定方法 | 表示方法 |
|-------------|---------|---------|
| **画像** (jpg/jpeg/png/webp) | URLの拡張子で判定 | `Image.network()` でプレビュー表示。タップで `FullScreenImageViewer` に遷移 |
| **PDF** | URLが `.pdf` で終わる | ファイルアイコン + ファイル名。タップで `url_launcher` で外部表示 or `flutter_pdfview` で内部表示 |

**画像フルスクリーン表示**: 既存の `lib/shared/widgets/full_screen_image_viewer.dart` を再利用

#### デザイン仕様

| 要素 | 仕様 |
|------|------|
| **AppBar** | 白背景、戻るボタン（`Icons.arrow_back_ios`）、タイトルなし |
| **ヘッダーカード** | `AppColors.primary50` 背景、セッション番号（大きめ `primary600`）、タイトル（`slate800` Bold）、トレーナー名 + 日付 |
| **内容カード** | 白背景、「内容」ラベル（`slate500` 小さめ）、本文（`slate700`、行間 1.6） |
| **添付ファイルカード** | 白背景、「添付ファイル (N)」ラベル、ファイルごとにリスト表示 |
| **PDFアイテム** | `slate50` 背景、赤い PDF アイコン、ファイル名、「タップして表示」テキスト |
| **画像アイテム** | `ClipRRect` + `BorderRadius.circular(12)` でラウンド画像表示、高さ200px |

---

### Step 6: UI - ノートカード Widget

**ファイル**: `lib/features/client_notes/presentation/widgets/note_card.dart`

**参照パターン**: `lib/features/meal_records/presentation/widgets/meal_card.dart`

一覧画面で使用するカルテカードWidget。

```dart
class NoteCard extends StatelessWidget {
  final ClientNote note;
  final VoidCallback onTap;

  // Props:
  // - note: ClientNote モデル
  // - onTap: タップ時のコールバック（詳細画面遷移）
}
```

#### カード内レイアウト

```
┌────────────────────────────────────┐
│ #12   下半身強化プログラム          │  ← Row: セッション番号 + タイトル
│ 2026年2月14日                      │  ← 日付（slate400）
│                                    │
│ 下半身の筋力不足が課題。           │  ← 本文プレビュー（最大2行）
│ スクワットのフォームを...           │
│                                    │
│ 📎 2 files attached           [>]  │  ← Row: ファイル数 + 矢印
└────────────────────────────────────┘
```

| 要素 | Tailwind対応カラー | AppColors |
|------|-------------------|-----------|
| セッション番号 `#12` | `text-blue-600 font-bold` | `AppColors.primary600`, `FontWeight.bold` |
| タイトル | `text-slate-800 font-semibold` | `AppColors.slate800`, `FontWeight.w600` |
| 日付 | `text-slate-400 text-xs` | `AppColors.slate400`, `fontSize: 12` |
| 本文 | `text-slate-600 text-sm` | `AppColors.slate600`, `fontSize: 14` |
| ファイルバッジ背景 | `bg-slate-100` | `AppColors.slate100` |
| ファイルバッジテキスト | `text-slate-500 text-xs` | `AppColors.slate500`, `fontSize: 12` |
| 矢印 | `text-slate-300` | `AppColors.slate300` |
| カード背景 | `bg-white rounded-2xl shadow-sm` | `Colors.white`, `borderRadius: 16` |

---

### Step 7: Records 画面の修正

**ファイル**: `lib/features/home/presentation/screens/records_screen.dart`

#### 変更内容

```dart
// 変更前
_tabController = TabController(length: 3, vsync: this, ...);

// 変更後
_tabController = TabController(length: 4, vsync: this, ...);
```

```dart
// タブ追加
tabs: const [
  Tab(text: 'Meals'),
  Tab(text: 'Weight'),
  Tab(text: 'Exercise'),
  Tab(text: 'Notes'),    // ← 追加
],
```

```dart
// TabBarView に追加
children: const [
  MealRecordScreen(),
  WeightRecordScreen(),
  ExerciseRecordScreen(),
  ClientNotesScreen(),    // ← 追加
],
```

---

## 5. ディレクトリ構成（新規ファイル一覧）

```
lib/features/client_notes/
├── models/
│   ├── client_note_model.dart          # データモデル
│   └── client_note_model.g.dart        # 自動生成
├── data/
│   └── client_note_repository.dart     # Supabaseクエリ
├── providers/
│   ├── client_notes_provider.dart      # Riverpod Provider
│   └── client_notes_provider.g.dart    # 自動生成
└── presentation/
    ├── screens/
    │   ├── client_notes_screen.dart     # カルテ一覧（Notesタブ）
    │   └── client_note_detail_screen.dart  # カルテ詳細
    └── widgets/
        └── note_card.dart              # カルテカードWidget
```

**修正ファイル**:
- `lib/features/home/presentation/screens/records_screen.dart` （タブ追加）

---

## 6. 画面遷移フロー

```
MainScreen (BottomNav)
  └── Records (TabBar)
        ├── Meals
        ├── Weight
        ├── Exercise
        └── Notes (ClientNotesScreen)
              └── [カードタップ] → ClientNoteDetailScreen
                    ├── [画像タップ] → FullScreenImageViewer（既存）
                    └── [PDFタップ] → 外部ブラウザ or PDFビューア
```

---

## 7. プレビュー関数

各UIファイルに Widget Previewer 用のプレビュー関数を作成すること。

### note_card.dart

```dart
@Preview(name: 'NoteCard - With Session Number')
Widget previewNoteCardWithSession() { ... }

@Preview(name: 'NoteCard - Without Files')
Widget previewNoteCardNoFiles() { ... }

@Preview(name: 'NoteCard - Long Content')
Widget previewNoteCardLongContent() { ... }
```

### client_notes_screen.dart

```dart
@Preview(name: 'ClientNotesScreen - With Data')
Widget previewClientNotesWithData() { ... }

@Preview(name: 'ClientNotesScreen - Empty State')
Widget previewClientNotesEmpty() { ... }
```

### client_note_detail_screen.dart

```dart
@Preview(name: 'NoteDetail - With Files')
Widget previewNoteDetailWithFiles() { ... }

@Preview(name: 'NoteDetail - Text Only')
Widget previewNoteDetailTextOnly() { ... }
```

---

## 8. 実装タスク一覧

| # | タスク | 担当Agent | 依存 |
|---|--------|----------|------|
| 1 | RLS ポリシー追加（`clients_select_shared_notes`） | Supabase Agent | - |
| 2 | `ClientNote` モデル作成 + コード生成 | Riverpod Agent | - |
| 3 | `ClientNoteRepository` 作成 | Riverpod Agent | #2 |
| 4 | `sharedClientNotes` Provider 作成 + コード生成 | Riverpod Agent | #3 |
| 5 | `NoteCard` Widget 作成 + プレビュー関数 | Flutter UI Agent | #2 |
| 6 | `ClientNotesScreen` 作成 + プレビュー関数 | Flutter UI Agent | #4, #5 |
| 7 | `ClientNoteDetailScreen` 作成 + プレビュー関数 | Flutter UI Agent | #2 |
| 8 | `RecordsScreen` タブ追加 | Flutter UI Agent | #6 |
| 9 | `IMPLEMENTATION_TASKS.md` 更新 | 直接編集 | #8 |

**並列実行可能**: #1, #2 は並列 / #3, #5 は #2 完了後に並列 / #6, #7 は #4, #5 完了後に並列

---

## 9. 検証項目

- [ ] `flutter analyze` でエラーがないこと
- [ ] Records 画面で「Notes」タブが表示されること
- [ ] 共有済みカルテが一覧表示されること
- [ ] 非共有のカルテは表示されないこと
- [ ] カードタップで詳細画面に遷移すること
- [ ] 添付画像がプレビュー表示されること
- [ ] 添付PDFがタップで開けること
- [ ] カルテがない場合に空状態が表示されること
- [ ] 各UIコンポーネントにプレビュー関数があること

---

## 10. 将来拡張メモ

### Realtime 対応（優先度: 中）
トレーナーがカルテを共有した際に、クライアント側にリアルタイム通知を表示する。

```dart
SupabaseService.client
  .from('client_notes')
  .stream(primaryKey: ['id'])
  .eq('client_id', clientId)
  .eq('is_shared', true)
  .listen((data) { ... });
```

### Home画面サマリーカード（優先度: 低）
Home画面に「新しいカルテが共有されました」カードを表示。
`getSharedNotesCount()` を使用し、前回閲覧時からの新着件数を表示。

### 申請フロー（優先度: 将来）
クライアントからトレーナーにカルテ共有をリクエストする機能。
DB側で `is_shared: boolean` → `shared_status: 'private' | 'pending' | 'shared'` への拡張が必要。
