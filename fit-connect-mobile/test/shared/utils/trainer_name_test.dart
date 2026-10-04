import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';

void main() {
  group('trainerDisplayName', () {
    test('null・空・空白だけなら「トレーナー」', () {
      expect(trainerDisplayName(null), 'トレーナー');
      expect(trainerDisplayName(''), 'トレーナー');
      expect(trainerDisplayName('   '), 'トレーナー');
      expect(trainerDisplayName('　\n'), 'トレーナー');
    });

    test('名前だけなら「トレーナー」を足す', () {
      expect(trainerDisplayName('田中'), '田中トレーナー');
    });

    test('すでに「トレーナー」で終わっていれば足さない（二重にならない）', () {
      expect(trainerDisplayName('田中トレーナー'), '田中トレーナー');
      expect(trainerDisplayName('トレーナー'), 'トレーナー');
      // 結果をもう一度通しても変わらない
      expect(trainerDisplayName(trainerDisplayName('田中')), '田中トレーナー');
    });

    test('姓名の間の空白は残し、前後の空白は除く', () {
      expect(trainerDisplayName('田中 太郎'), '田中 太郎トレーナー');
      expect(trainerDisplayName('  田中  '), '田中トレーナー');
      expect(trainerDisplayName(' 田中トレーナー '), '田中トレーナー');
    });

    test('助詞が続く文言でも二重にならない', () {
      for (final raw in ['田中', '田中トレーナー']) {
        final name = trainerDisplayName(raw);
        expect('$nameのメモ', '田中トレーナーのメモ');
        expect('$nameに返信', '田中トレーナーに返信');
        expect('$nameが共有したカルテ', '田中トレーナーが共有したカルテ');
      }
    });
  });
}
