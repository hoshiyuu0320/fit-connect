import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/message_bubble.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/full_screen_image_viewer.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 画像のキャッシュ（Flutter の ImageCache）に、指定の大きさの画像を先に入れておく。
/// `StorageImage`（CachedNetworkImage）が同じ URL を読むと、ネットワークに出ずにこの画像が出る
Future<void> _seedImage(
  WidgetTester tester,
  String url,
  int width,
  int height,
) async {
  final image = await tester.runAsync(() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF2E7D6B),
    );
    return recorder.endRecording().toImage(width, height);
  });
  PaintingBinding.instance.imageCache.putIfAbsent(
    CachedNetworkImageProvider(url),
    () => OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: image!)),
    ),
  );
}

void main() {
  group('describeRecordMessage（記録カードの見出し・アイコン・状態行）', () {
    test('体重: scale ・「あなたの体重記録 · 7:30」・「体重の記録に追加しました」', () {
      final d = describeRecordMessage(tags: const ['#体重'], time: '7:30');
      expect(d.icon, LucideIcons.scale);
      expect(d.heading, 'あなたの体重記録 · 7:30');
      expect(d.status, '体重の記録に追加しました');
      expect(d.isRecord, isTrue);
    });

    test('食事: utensils ・区分ごとの見出し（朝食・昼食・夕食・間食・区分なし）', () {
      for (final (tag, label) in [
        ('#食事:朝食', '朝食'),
        ('#食事:昼食', '昼食'),
        ('#食事:夕食', '夕食'),
        ('#食事:間食', '間食'),
        ('#食事', '食事'),
      ]) {
        final d = describeRecordMessage(tags: [tag], time: '8:10');
        expect(d.icon, LucideIcons.utensils);
        expect(d.heading, 'あなたの$label記録 · 8:10');
        expect(d.status, '食事の記録に追加しました');
      }
    });

    test('運動: 有酸素 = footprints / 筋トレ = dumbbell', () {
      final cardio =
          describeRecordMessage(tags: const ['#運動:有酸素'], time: '18:20');
      expect(cardio.icon, LucideIcons.footprints);
      expect(cardio.heading, 'あなたの運動記録 · 有酸素 · 18:20');
      expect(cardio.status, '運動の記録に追加しました');

      final strength =
          describeRecordMessage(tags: const ['#運動:筋トレ'], time: '18:20');
      expect(strength.icon, LucideIcons.dumbbell);
      expect(strength.heading, 'あなたの運動記録 · 筋トレ · 18:20');
    });

    test('通常のメッセージ: 見出し・アイコンなし。送信時刻を状態行に出す（既読は出さない）', () {
      final d = describeRecordMessage(tags: null, time: '9:24');
      expect(d.icon, isNull);
      expect(d.heading, isNull);
      expect(d.status, '9:24');
      expect(d.isRecord, isFalse);
    });

    test('編集済み: 状態行に足す（タグなしなら時刻の後ろに「 · 編集済み」）', () {
      expect(
        describeRecordMessage(tags: null, time: '9:24', isEdited: true).status,
        '9:24 · 編集済み',
      );
      expect(
        describeRecordMessage(tags: const ['#体重'], time: '7:30', isEdited: true)
            .status,
        '体重の記録に追加しました · 編集済み',
      );
    });

    test('ワークアウト完了: 見出しにプラン名・本文を「消費 280 kcal」＋感想に整える', () {
      const body =
          '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal\n💬 肩の動きがよくなってきました。';
      final d = describeRecordMessage(
        tags: const ['#運動:完了'],
        time: '18:40',
        body: body,
      );
      expect(d.icon, LucideIcons.dumbbell);
      expect(d.heading, 'ワークアウト完了 · 上半身 · 18:40');
      expect(d.status, 'プランの完了を報告しました');
      expect(d.body, '消費 280 kcal\n肩の動きがよくなってきました。');
    });

    test('ワークアウト完了: タグが無くても本文の形で判定する（Web の解析と同じ）', () {
      final d = describeRecordMessage(
        tags: null,
        time: '18:40',
        body: '本日のワークアウトプラン「脚の日」を達成しました！',
      );
      expect(d.heading, 'ワークアウト完了 · 脚の日 · 18:40');
      expect(d.body, '');
    });

    test('ワークアウト完了: 本文が解析できないときは本文をそのまま出す', () {
      final d = describeRecordMessage(
        tags: const ['#運動:完了'],
        time: '18:40',
        body: '脚の日でした',
      );
      expect(d.heading, 'ワークアウト完了 · 18:40');
      expect(d.body, isNull);
    });
  });

  group('MessageBubble', () {
    testWidgets('自分のメッセージは記録カード（見出し・本文・状態行）で、既読は出さない', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '#体重 62.4 kg',
          isUser: true,
          timestamp: '7:30',
          tags: ['#体重'],
          isRead: true,
        ),
      );

      expect(find.text('あなたの体重記録 · 7:30'), findsOneWidget);
      expect(find.text('62.4 kg'), findsOneWidget); // タグは本文から取り除く
      expect(find.text('体重の記録に追加しました'), findsOneWidget);
      expect(find.textContaining('既読'), findsNothing);
    });

    testWidgets('通常のメッセージは見出し行（「あなたのメッセージ · 9:24」）を出さず、本文の下の状態行に時刻を出す',
        (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'あいうえお',
          isUser: true,
          timestamp: '17:04',
        ),
      );

      expect(find.textContaining('あなたのメッセージ'), findsNothing);
      expect(find.byIcon(LucideIcons.messageCircle), findsNothing);
      expect(find.text('あいうえお'), findsOneWidget);
      // 送信時刻は本文の下（12px・textSecondary の状態行）
      final time = find.text('17:04');
      expect(time, findsOneWidget);
      expect(tester.getTopLeft(time).dy,
          greaterThan(tester.getBottomLeft(find.text('あいうえお')).dy));
      final style = tester.widget<Text>(time).style!;
      expect(style.fontSize, 12);
      expect(style.color, AppColorsExtension.light.textSecondary);
      // カードの先頭は本文（見出しの分の余白が残らない）
      final card = tester.getRect(find
          .descendant(
              of: find.byType(RecordMessageCard),
              matching: find.byType(DecoratedBox))
          .first);
      final body = tester.getTopLeft(find.text('あいうえお'));
      expect(body.dy - card.top, lessThan(24));
    });

    testWidgets('通常のメッセージが編集済みなら、同じ状態行に「17:04 · 編集済み」', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'あいうえお',
          isUser: true,
          timestamp: '17:04',
          isEdited: true,
        ),
      );
      expect(find.text('17:04 · 編集済み'), findsOneWidget);
      expect(find.textContaining('あなたのメッセージ'), findsNothing);
    });

    testWidgets('記録カード（体重・食事・運動・ワークアウト完了）の見出しは残る', (tester) async {
      for (final (message, tag, heading) in [
        ('#体重 62.4 kg', '#体重', 'あなたの体重記録 · 7:30'),
        ('#食事:昼食 定食', '#食事:昼食', 'あなたの昼食記録 · 7:30'),
        ('#運動:筋トレ 腕立て', '#運動:筋トレ', 'あなたの運動記録 · 筋トレ · 7:30'),
        ('#運動:完了', '#運動:完了', 'ワークアウト完了 · 7:30'),
      ]) {
        await _pump(
          tester,
          MessageBubble(
            message: message,
            isUser: true,
            timestamp: '7:30',
            tags: [tag],
          ),
        );
        expect(find.text(heading), findsOneWidget, reason: heading);
        // 見出しに時刻があるので、状態行に時刻だけが出ることはない
        expect(find.text('7:30'), findsNothing, reason: heading);
      }
    });

    testWidgets('記録カードは surface・角丸 20・左に 22 のインデント', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'こんにちは',
          isUser: true,
          timestamp: '9:24',
        ),
      );

      final card = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byType(RecordMessageCard),
              matching: find.byType(DecoratedBox))
          .first);
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surface);
      expect(decoration.borderRadius, BorderRadius.circular(20));

      final left = tester.getTopLeft(find.byType(RecordMessageCard)).dx;
      final cardLeft = tester
          .getTopLeft(find
              .descendant(
                  of: find.byType(RecordMessageCard),
                  matching: find.byType(DecoratedBox))
              .first)
          .dx;
      expect(cardLeft - left, 22);
    });

    testWidgets('ダークでも記録カードは surface の面', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'こんにちは',
          isUser: true,
          timestamp: '9:24',
        ),
        brightness: Brightness.dark,
      );

      final card = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byType(RecordMessageCard),
              matching: find.byType(DecoratedBox))
          .first);
      expect((card.decoration as BoxDecoration).color,
          AppColorsExtension.dark.surface);
    });

    testWidgets('トレーナーのメッセージは吹き出し + 「{名前} · 19:05」', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'いいペースですね。',
          isUser: false,
          timestamp: '19:05',
          trainerName: '田中トレーナー',
        ),
      );

      expect(find.byType(CoachReplyBubble), findsOneWidget);
      expect(find.text('いいペースですね。'), findsOneWidget);
      expect(find.text('田中トレーナー · 19:05'), findsOneWidget);

      // 先頭はアバター（円）の面なので、吹き出しは最後の面
      final bubble = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byType(CoachReplyBubble),
              matching: find.byType(DecoratedBox))
          .last);
      final decoration = bubble.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surfaceSecondary);
      // 左上だけ角丸 0・ほかは 20
      expect(
        decoration.borderRadius,
        const BorderRadius.only(
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      );
    });

    testWidgets('返信先があると「{名前}への返信」を記録カードの上に出す', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'ありがとうございます。',
          isUser: true,
          timestamp: '9:24',
          replyToSenderName: '田中トレーナー',
          replyToContent: '朝食の記録、ありがとうございます。',
        ),
      );

      expect(find.textContaining('田中トレーナーへの返信'), findsOneWidget);
      final caption = tester.getTopLeft(find.textContaining('田中トレーナーへの返信'));
      final card = tester.getTopLeft(find.text('ありがとうございます。'));
      expect(caption.dy, lessThan(card.dy));
    });

    testWidgets('🔥 / 💬 の絵文字は文字ではなくアイコンで出す', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '今日の記録\n🔥 消費カロリー: 350kcal\n💬 脚トレを頑張りました',
          isUser: false,
          timestamp: '18:35',
        ),
      );

      expect(find.textContaining('🔥', findRichText: true), findsNothing);
      expect(find.textContaining('💬', findRichText: true), findsNothing);
      expect(find.byIcon(LucideIcons.flame), findsOneWidget);
      expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);
    });

    testWidgets('ワークアウト完了は「ワークアウト完了 · 上半身 · 18:40」と「消費 280 kcal」に整えて見せる',
        (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal\n💬 肩の動きがよくなってきました。',
          isUser: true,
          timestamp: '18:40',
          tags: ['#運動:完了'],
        ),
      );

      expect(find.text('ワークアウト完了 · 上半身 · 18:40'), findsOneWidget);
      expect(find.textContaining('消費 280 kcal'), findsOneWidget);
      expect(find.textContaining('肩の動きがよくなってきました。'), findsOneWidget);
      expect(find.text('プランの完了を報告しました'), findsOneWidget);
      // 絵文字つきの元の行は出さない
      expect(find.textContaining('消費カロリー'), findsNothing);
    });

    testWidgets('長押しで「返信 / 編集」のメニュー（自分のメッセージ）', (tester) async {
      var replied = 0;
      var edited = 0;
      await _pump(
        tester,
        MessageBubble(
          message: 'こんにちは',
          isUser: true,
          timestamp: '9:24',
          onReply: () => replied++,
          onEdit: () => edited++,
        ),
      );

      await tester.longPress(find.text('こんにちは'));
      await tester.pumpAndSettle();
      expect(find.text('返信'), findsOneWidget);
      expect(find.text('編集'), findsOneWidget);

      await tester.tap(find.text('返信'));
      await tester.pumpAndSettle();
      expect(replied, 1);
      expect(find.text('返信'), findsNothing);

      await tester.longPress(find.text('こんにちは'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      expect(edited, 1);
    });

    testWidgets('トレーナーのメッセージは長押しで「返信」だけ', (tester) async {
      await _pump(
        tester,
        MessageBubble(
          message: 'お疲れさまでした',
          isUser: false,
          timestamp: '19:12',
          onReply: () {},
        ),
      );

      await tester.longPress(find.text('お疲れさまでした'));
      await tester.pumpAndSettle();
      expect(find.text('返信'), findsOneWidget);
      expect(find.text('編集'), findsNothing);
    });

    testWidgets('システムメッセージは中央の控えめな面', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '目標を達成しました',
          isUser: false,
          timestamp: '14:20',
          isSystem: true,
        ),
      );
      expect(find.text('目標を達成しました'), findsOneWidget);
      expect(find.byType(RecordMessageCard), findsNothing);
      expect(find.byType(CoachReplyBubble), findsNothing);
    });

    for (final isUser in [true, false]) {
      testWidgets('文字 1.35 で横にはみ出さない（${isUser ? '自分' : 'トレーナー'}）',
          (tester) async {
        await _pump(
          tester,
          MessageBubble(
            message: '#食事:昼食 鶏むね肉のグリル定食とサラダ、ごはん少なめ、味噌汁もつけました。とても長い本文でも折り返して縦に伸びます。',
            isUser: isUser,
            timestamp: '12:30',
            tags: isUser ? const ['#食事:昼食'] : null,
            trainerName: '田中トレーナー',
            isEdited: true,
            replyToSenderName: '田中トレーナー',
            replyToContent: '昼食は何を食べましたか。写真があれば送ってください。',
          ),
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('MessageImages（写真は切り取らない）', () {
    // _pump は左右 20 の余白（390 - 40 = 350）。自分の記録カードは左に 22、トレーナーの吹き出しは左に 38
    const userWidth = 350.0 - 22;
    const coachWidth = 350.0 - 38;

    setUp(() {
      MessagePhotoRatios.clear();
      PaintingBinding.instance.imageCache.clear();
    });
    tearDown(() {
      MessagePhotoRatios.clear();
      PaintingBinding.instance.imageCache.clear();
    });

    /// 1 枚の写真の枠（角丸で切り抜く箱）
    Finder singleBox() => find.descendant(
        of: find.byType(MessageImages),
        matching: find.byType(AnimatedContainer));

    Future<void> pumpPhotos(
      WidgetTester tester,
      List<String> urls, {
      bool isUser = true,
      Brightness brightness = Brightness.light,
    }) =>
        _pump(
          tester,
          MessageBubble(
            message: isUser ? '#食事:昼食 定食' : 'いい写真ですね',
            isUser: isUser,
            timestamp: '12:30',
            tags: isUser ? const ['#食事:昼食'] : null,
            images: urls,
            trainerName: '田中トレーナー',
          ),
          brightness: brightness,
        );

    for (final (name, w, h, expectedW, expectedH) in [
      ('横長 2:1', 200, 100, userWidth, userWidth / 2),
      ('横長 4:3', 400, 300, userWidth, userWidth * 3 / 4),
      ('正方形', 100, 100, userWidth, userWidth),
      // 縦長は高さの上限（幅 × 1.2）で止め、比率を保ったまま縮める（全体が見える）
      ('縦長 3:4（上限を超える）', 300, 400, userWidth * 1.2 * 3 / 4, userWidth * 1.2),
      ('縦長 1:3（極端）', 100, 300, userWidth * 1.2 / 3, userWidth * 1.2),
      // 上限以内の縦長はそのまま
      ('縦長 7:8（上限以内）', 350, 400, userWidth, userWidth * 8 / 7),
    ]) {
      testWidgets('1 枚（$name）: 写真の縦横比のまま、全体が見える大きさで表示する', (tester) async {
        const url = 'https://photos.test/one.png';
        await _seedImage(tester, url, w, h);
        await pumpPhotos(tester, const [url]);

        final size = tester.getSize(singleBox());
        expect(size.width, closeTo(expectedW, 0.5));
        expect(size.height, closeTo(expectedH, 0.5));
        // 写真の比率を覚えている（再表示で高さが跳ねないように）
        expect(MessagePhotoRatios.of(url), closeTo(w / h, 0.001));
        // どの層も BoxFit.cover（切り取り）ではない
        final storage = tester.widget<StorageImage>(find.byType(StorageImage));
        expect(storage.fit, isNot(BoxFit.cover));
        for (final image in tester.widgetList<Image>(find.descendant(
            of: find.byType(MessageImages), matching: find.byType(Image)))) {
          expect(image.fit, BoxFit.contain);
        }
      });
    }

    testWidgets('1 枚: 角丸 20・左寄せ（記録カードと同じ左のインデント 22）', (tester) async {
      const url = 'https://photos.test/one.png';
      await _seedImage(tester, url, 100, 300);
      await pumpPhotos(tester, const [url]);

      final box = tester.widget<AnimatedContainer>(singleBox());
      expect((box.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(20));
      // 縦長で幅が狭くても、左端はカードと同じ（20 + 22）
      expect(tester.getTopLeft(singleBox()).dx, 20 + 22);
    });

    testWidgets('1 枚: 初めて見る写真は、読み込み前を 4:3 の大きさで確保する', (tester) async {
      await pumpPhotos(tester, const ['https://photos.test/unseen.png']);
      final size = tester.getSize(singleBox());
      expect(size.width, closeTo(userWidth, 0.5));
      expect(size.height, closeTo(userWidth * 3 / 4, 0.5));
      // 読み込み中（ネットワークに出られない環境では読み込み失敗）の面が、同じ大きさで出ている
      expect(find.byType(FcPhotoPlaceholder), findsOneWidget);
    });

    testWidgets('1 枚: 前に読み込んだ写真は、読み込み前の最初のフレームから正しい大きさ（高さが跳ねない）',
        (tester) async {
      const url = 'https://photos.test/one.png';
      await _seedImage(tester, url, 100, 300);
      await pumpPhotos(tester, const [url]);
      final loaded = tester.getSize(singleBox());

      // スクロールで部品が作り直される。画像のキャッシュも空にして、読み込み前の状態を作る
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      await pumpPhotos(tester, const [url]);
      expect(find.byType(FcPhotoPlaceholder), findsOneWidget); // 写真は未表示
      final reentered = tester.getSize(singleBox());
      expect(reentered.width, closeTo(loaded.width, 0.5));
      expect(reentered.height, closeTo(loaded.height, 0.5));
    });

    testWidgets('1 枚: トレーナーの吹き出しの写真にも同じ表示（左のインデントだけ違う）', (tester) async {
      const url = 'https://photos.test/one.png';
      await _seedImage(tester, url, 400, 300);
      await pumpPhotos(tester, const [url], isUser: false);

      final size = tester.getSize(singleBox());
      expect(size.width, closeTo(coachWidth, 0.5));
      expect(size.height, closeTo(coachWidth * 3 / 4, 0.5));
      expect(
          tester.getTopLeft(singleBox()).dx, 20 + CoachReplyBubble.bubbleInset);
      expect(tester.widget<StorageImage>(find.byType(StorageImage)).fit,
          isNot(BoxFit.cover));
    });

    for (final count in [2, 3, 4]) {
      testWidgets('$count 枚: 等分して横に並べ、高さは 132・各写真は contain（切り取らない）',
          (tester) async {
        final urls = [
          for (var i = 0; i < count; i++) 'https://photos.test/m$i.png',
        ];
        // 縦長・横長・正方形をまぜる
        const shapes = [(100, 300), (300, 100), (100, 100), (300, 400)];
        for (var i = 0; i < count; i++) {
          await _seedImage(tester, urls[i], shapes[i].$1, shapes[i].$2);
        }
        await pumpPhotos(tester, urls);

        final storages =
            tester.widgetList<StorageImage>(find.byType(StorageImage)).toList();
        expect(storages, hasLength(count));
        for (final storage in storages) {
          expect(storage.fit, BoxFit.contain);
          expect(storage.height, MessageImages.height);
        }
        for (final image in tester.widgetList<Image>(find.descendant(
            of: find.byType(MessageImages), matching: find.byType(Image)))) {
          expect(image.fit, BoxFit.contain);
        }

        const gap = 6.0;
        final tileWidth = (userWidth - gap * (count - 1)) / count;
        for (var i = 0; i < count; i++) {
          final tile =
              tester.getRect(find.bySemanticsLabel('写真 ${i + 1} を拡大して見る'));
          expect(tile.width, closeTo(tileWidth, 0.5));
          expect(tile.height, closeTo(132, 0.5));
        }
      });
    }

    testWidgets('写真をタップすると全画面表示（複数枚は押した写真から）', (tester) async {
      final urls = [
        'https://photos.test/a.png',
        'https://photos.test/b.png',
      ];
      for (final url in urls) {
        await _seedImage(tester, url, 400, 300);
      }
      await pumpPhotos(tester, urls);

      await tester.tap(find.bySemanticsLabel('写真 2 を拡大して見る'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final viewer = tester
          .widget<FullScreenImageViewer>(find.byType(FullScreenImageViewer));
      expect(viewer.initialIndex, 1);
      expect(viewer.values, urls);
    });

    testWidgets('1 枚をタップしても全画面表示', (tester) async {
      const url = 'https://photos.test/one.png';
      await _seedImage(tester, url, 100, 300);
      await pumpPhotos(tester, const [url]);

      await tester.tap(find.bySemanticsLabel('写真 1 を拡大して見る'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FullScreenImageViewer), findsOneWidget);
    });

    test('写真の比率の記憶は、上限を超えたら古いものから忘れる', () {
      MessagePhotoRatios.clear();
      for (var i = 0; i < MessagePhotoRatios.capacity + 5; i++) {
        MessagePhotoRatios.remember('p$i', 1.5);
      }
      expect(MessagePhotoRatios.of('p0'), isNull);
      expect(MessagePhotoRatios.of('p4'), isNull);
      expect(MessagePhotoRatios.of('p5'), 1.5);
      expect(MessagePhotoRatios.of('p${MessagePhotoRatios.capacity + 4}'), 1.5);
      MessagePhotoRatios.clear();
    });
  });

  group('MessageDateDivider', () {
    testWidgets('13px・中央寄せの日付', (tester) async {
      await _pump(tester, const MessageDateDivider('9月13日（日）'));
      final text = tester.widget<Text>(find.text('9月13日（日）'));
      expect(text.textAlign, TextAlign.center);
      expect(text.style?.fontSize, 13);
    });
  });
}
