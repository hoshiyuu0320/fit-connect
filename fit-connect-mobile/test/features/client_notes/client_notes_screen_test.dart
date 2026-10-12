import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_notes_screen.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/widgets/note_card.dart';
import 'package:fit_connect_mobile/features/client_notes/providers/client_notes_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 記録タブの「ノート」サブタブ（ClientNotesScreen）の表示テスト
/// （正本: record-screens.js `NotesTab`）。
ClientNote _note(
  String id, {
  String title = 'ノート',
  List<String> files = const [],
  LinkedSession? session,
  DateTime? created,
}) {
  final at = created ?? DateTime(2026, 9, 8, 21);
  return ClientNote(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: title,
    content: '本文 $id',
    fileUrls: files,
    isShared: true,
    sharedAt: at,
    sessionId: session == null ? null : 'session-$id',
    session: session,
    createdAt: at,
    updatedAt: at,
  );
}

const _trainer = Trainer(id: 'trainer-1', name: '山田太郎');

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<List<ClientNote>> Function() notes,
    Trainer? trainer = _trainer,
    double textScale = 1.0,
    EdgeInsets bottomInset = EdgeInsets.zero,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedClientNotesProvider.overrideWith((ref) => notes()),
          trainerProfileProvider.overrideWith((ref) async => trainer),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: bottomInset,
            ),
            child: child!,
          ),
          home: const Scaffold(body: ClientNotesScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('ClientNotesScreen 一覧', () {
    testWidgets('上に「{トレーナー名}が共有したカルテ」、続けてノートのカードが並ぶ', (tester) async {
      await pumpScreen(
        tester,
        notes: () async => [
          _note(
            '1',
            title: '上半身のフォーム確認',
            files: ['a.jpg', 'b.pdf'],
            session: LinkedSession(
              sessionDate: DateTime(2026, 9, 8, 19),
              sessionType: 'パーソナル',
            ),
          ),
          _note('2', title: '目標の見直し'),
          _note('3', title: '食事のポイント'),
        ],
      );

      expect(find.text('山田太郎トレーナーが共有したカルテ'), findsOneWidget);
      expect(find.byType(NoteCard), findsNWidgets(3));
      expect(find.text('上半身のフォーム確認'), findsOneWidget);
      // 補足は「日付 · トレーナー名」
      expect(find.textContaining('· 山田太郎トレーナー'), findsNWidgets(3));
      // 旧デザインの淡青のサマリーカード（件数表示）は出さない
      expect(find.textContaining('共有されたカルテ:'), findsNothing);
      expect(find.text('トレーナーより'), findsNothing);
    });

    testWidgets('名前が「田中」でも「田中トレーナー」でも「田中トレーナーが共有したカルテ」', (tester) async {
      for (final raw in ['田中', '田中トレーナー']) {
        await pumpScreen(
          tester,
          notes: () async => [_note('1', title: '目標の見直し')],
          trainer: Trainer(id: 'trainer-1', name: raw),
        );

        expect(find.text('田中トレーナーが共有したカルテ'), findsOneWidget, reason: raw);
        expect(find.textContaining('トレーナートレーナー'), findsNothing, reason: raw);
      }
    });

    testWidgets('トレーナー名が取れていなければ「トレーナーが共有したカルテ」', (tester) async {
      await pumpScreen(
        tester,
        notes: () async => [_note('1')],
        trainer: null,
      );

      expect(find.text('トレーナーが共有したカルテ'), findsOneWidget);
      expect(find.byType(NoteCard), findsOneWidget);
    });

    testWidgets('カードを押すとカルテの詳細へ進む（既存の遷移）', (tester) async {
      await pumpScreen(
        tester,
        notes: () async => [_note('1', title: '上半身のフォーム確認')],
      );

      await tester.tap(find.byType(NoteCard));
      await tester.pumpAndSettle();

      expect(find.byType(ClientNoteDetailScreen), findsOneWidget);
      final detail = tester.widget<ClientNoteDetailScreen>(
        find.byType(ClientNoteDetailScreen),
      );
      expect(detail.note.id, '1');
      expect(detail.trainerName, '山田太郎');
    });

    testWidgets('カード間は 16・左右の余白は 20', (tester) async {
      await pumpScreen(
        tester,
        notes: () async => [_note('1'), _note('2')],
      );

      final first = tester.getRect(find.byType(NoteCard).at(0));
      final second = tester.getRect(find.byType(NoteCard).at(1));
      expect(second.top - first.bottom, 16);
      expect(first.left, 20);
      expect(first.right, 390 - 20);
    });

    testWidgets('下に下部ナビぶんの余白を自分で受け取る（MediaQuery の下余白）', (tester) async {
      await pumpScreen(
        tester,
        notes: () async => [for (var i = 0; i < 12; i++) _note('$i')],
        bottomInset: const EdgeInsets.only(bottom: 121),
      );

      final list = tester.widget<ListView>(find.byType(ListView));
      final padding = list.padding!.resolve(TextDirection.ltr);
      expect(padding.bottom, 121);
      expect(padding.top, 0, reason: '上の余白は記録タブの枠が空ける');
    });

    testWidgets('文字拡大 1.35 でも横にはみ出さない', (tester) async {
      await pumpScreen(
        tester,
        notes: () async => [
          _note(
            '1',
            title: '体組成測定結果と今後のトレーニング方針について',
            files: ['a.jpg'],
            session: LinkedSession(
              sessionDate: DateTime(2026, 9, 8, 19),
              sessionType: 'パーソナルトレーニング',
            ),
          ),
        ],
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(NoteCard), findsOneWidget);
    });

    testWidgets('ダークでも描画できる', (tester) async {
      await pumpScreen(
        tester,
        notes: () async => [_note('1')],
        theme: AppTheme.darkTheme,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(NoteCard), findsOneWidget);
    });
  });

  group('ClientNotesScreen 状態', () {
    testWidgets('共有されたノートが無ければ空の案内（FcStateMessage.empty）', (tester) async {
      await pumpScreen(tester, notes: () async => []);

      expect(find.byType(NoteCard), findsNothing);
      expect(find.text('共有されたノートはありません'), findsOneWidget);
      expect(find.text('トレーナーからまだセッションノートが共有されていません。'), findsOneWidget);
      final state = tester.widget<FcStateMessage>(find.byType(FcStateMessage));
      expect(state.kind, FcStateKind.empty);
    });

    testWidgets('読み込み中はスケルトンで配置を保ち、カードは出ない', (tester) async {
      final pending = Completer<List<ClientNote>>();
      await pumpScreen(tester, notes: () => pending.future);

      expect(find.byType(NoteCard), findsNothing);
      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.bySemanticsLabel('読み込み中'), findsWidgets);

      pending.complete([]);
      await tester.pump();
    });

    testWidgets('読み込みに失敗したら案内と「再試行」が出て、押すと取り直す', (tester) async {
      var calls = 0;
      await pumpScreen(
        tester,
        notes: () async {
          calls++;
          if (calls == 1) throw Exception('network');
          return [_note('1')];
        },
      );

      expect(find.text('カルテを読み込めませんでした'), findsOneWidget);
      // 生のエラー文は出さない
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.text('再試行'), findsOneWidget);

      await tester.tap(find.text('再試行'));
      await tester.pump();
      await tester.pump();

      expect(calls, 2);
      expect(find.byType(NoteCard), findsOneWidget);
    });
  });
}
