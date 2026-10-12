import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../meal_test_support.dart';
import 'meal_summary_card_test.dart' show pumpCard;

void main() {
  group('mealEstimateLabel', () {
    test('AI の推定は「推定」と明記し、値のある項目を「 · 」でつなぐ', () {
      final record = testMeal(
        '1',
        'lunch',
        todayAt(12, 30),
        calories: 640,
        protein: 38,
        fat: 18,
        carbs: 82,
        estimatedByAi: true,
      );
      expect(
        mealEstimateLabel(record),
        '推定 640 kcal · たんぱく質 38 g · 脂質 18 g · 炭水化物 82 g',
      );
    });

    test('手で入力した値には「推定」と書かない', () {
      final record = testMeal('1', 'lunch', todayAt(12, 30), calories: 520);
      expect(mealEstimateLabel(record), '520 kcal');
    });

    test('1 つも値が無ければ null（行ごと出さない）', () {
      expect(
          mealEstimateLabel(testMeal('1', 'lunch', todayAt(12, 30))), isNull);
    });

    test('一部だけでもある分を出す。千の位は区切る', () {
      final record = testMeal(
        '1',
        'dinner',
        todayAt(19, 0),
        calories: 1250,
        protein: 60.4,
        estimatedByAi: true,
      );
      expect(mealEstimateLabel(record), '推定 1,250 kcal · たんぱく質 60 g');
    });
  });

  group('MealCard', () {
    testWidgets('区分・日時・メモ・推定が正本どおりに並ぶ', (tester) async {
      final recordedAt = todayAt(12, 30);
      await pumpCard(
        tester,
        MealCard(
          record: testMeal(
            '1',
            'lunch',
            recordedAt,
            notes: '鶏むね肉のグリル定食',
            calories: 640,
            protein: 38,
            fat: 18,
            carbs: 82,
            estimatedByAi: true,
          ),
        ),
      );

      expect(find.text('昼食'), findsOneWidget);
      const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
      expect(
        find.text(
          '${recordedAt.month}月${recordedAt.day}日'
          '（${weekdays[recordedAt.weekday - 1]}）12:30',
        ),
        findsOneWidget,
      );
      expect(find.text('鶏むね肉のグリル定食'), findsOneWidget);
      expect(
        find.text('推定 640 kcal · たんぱく質 38 g · 脂質 18 g · 炭水化物 82 g'),
        findsOneWidget,
      );
    });

    testWidgets('絵文字を使わない（区分・時刻・カロリー・写真の件数）', (tester) async {
      await pumpCard(
        tester,
        MealCard(
          record: testMeal(
            '1',
            'breakfast',
            todayAt(8, 10),
            notes: 'ごはん',
            calories: 380,
            images: const ['a.jpg', 'b.jpg'],
          ),
        ),
      );

      final emoji =
          RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
      expect(texts.where(emoji.hasMatch), isEmpty);
    });

    testWidgets('推定が無い食事は推定の行を出さない', (tester) async {
      await pumpCard(
        tester,
        MealCard(
          record: testMeal('1', 'breakfast', todayAt(8, 10), notes: 'ごはん・卵'),
        ),
      );

      expect(find.text('ごはん・卵'), findsOneWidget);
      expect(find.textContaining('推定'), findsNothing);
      expect(find.textContaining('kcal'), findsNothing);
    });

    testWidgets('写真が 1 枚も無い記録は写真欄を出さず、見出しがカードの上端から始まる', (tester) async {
      await pumpCard(
        tester,
        MealCard(
          record: testMeal('1', 'breakfast', todayAt(8, 10), notes: 'ごはん'),
        ),
      );

      expect(find.byType(FcPhotoPlaceholder), findsNothing);
      expect(find.text('写真なし'), findsNothing);
      // 余白は上 14・左右 20・下 18（写真ありの文字の部分と同じ）
      final card = tester.getRect(find.byType(FcCard));
      final head = tester.getRect(find.byType(FcCardHead));
      expect(head.left - card.left, 20);
      expect(card.right - head.right, 20);
      expect(head.top - card.top, 14);
      final memo = tester.getRect(find.text('ごはん'));
      expect(card.bottom - memo.bottom, greaterThanOrEqualTo(18));
    });

    testWidgets('空の images（[]）も写真なしとして扱う', (tester) async {
      await pumpCard(
        tester,
        MealCard(
          record: testMeal('1', 'lunch', todayAt(12, 0),
              notes: '定食', images: const []),
        ),
      );
      expect(find.byType(FcPhotoPlaceholder), findsNothing);
    });

    testWidgets('写真があるときは高さ 176 の写真欄が上端にあり、取得できないあいだ・失敗時は代替面', (tester) async {
      await pumpCard(
        tester,
        MealCard(
          record: testMeal('1', 'lunch', todayAt(12, 0),
              notes: '定食', images: const ['a.jpg']),
        ),
      );

      final placeholder =
          tester.widget<FcPhotoPlaceholder>(find.byType(FcPhotoPlaceholder));
      expect(placeholder.height, 176);
      expect(placeholder.radius, 0);
      final card = tester.getRect(find.byType(FcCard));
      final photo = tester.getRect(find.byType(FcPhotoPlaceholder));
      expect(photo.top, card.top);
      expect(photo.height, 176);
      // 写真の下から文字の部分が始まる（上余白 14）
      final head = tester.getRect(find.byType(FcCardHead));
      expect(head.top - photo.bottom, 14);
    });

    testWidgets('メモも推定も無ければ、区分と日時の 2 つの文字だけになる', (tester) async {
      await pumpCard(
        tester,
        MealCard(record: testMeal('1', 'snack', todayAt(15, 0))),
      );

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts, hasLength(2));
      expect(texts, contains('間食'));
    });

    testWidgets('文字 1.35 倍でも長いメモが折り返し、はみ出さない', (tester) async {
      await pumpCard(
        tester,
        MealCard(
          record: testMeal(
            '1',
            'dinner',
            todayAt(19, 45),
            notes: '鮭のムニエル、温野菜のサラダ、もち麦ごはん、わかめと豆腐の味噌汁、ヨーグルト',
            calories: 1250,
            protein: 60,
            fat: 30,
            carbs: 150,
            estimatedByAi: true,
          ),
        ),
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('鮭のムニエル'), findsOneWidget);
    });
  });
}
