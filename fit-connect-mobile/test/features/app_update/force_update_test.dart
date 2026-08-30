import 'package:fit_connect_mobile/features/app_update/providers/force_update_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isUpdateRequired - 基本比較', () {
    test('現在 = 最低サポート は更新不要', () {
      expect(isUpdateRequired('1.0.0', '1.0.0'), isFalse);
    });

    test('現在 > 最低サポート は更新不要（patch / minor / major）', () {
      expect(isUpdateRequired('1.0.1', '1.0.0'), isFalse);
      expect(isUpdateRequired('1.1.0', '1.0.9'), isFalse);
      expect(isUpdateRequired('2.0.0', '1.9.9'), isFalse);
    });

    test('現在 < 最低サポート は要更新（patch / minor / major）', () {
      expect(isUpdateRequired('1.0.0', '1.0.1'), isTrue);
      expect(isUpdateRequired('1.0.9', '1.1.0'), isTrue);
      expect(isUpdateRequired('1.9.9', '2.0.0'), isTrue);
    });
  });

  group('isUpdateRequired - ビルド番号（+n）の除去', () {
    test('現在バージョンの +ビルド番号 は比較前に除去される', () {
      expect(isUpdateRequired('1.0.0+12', '1.0.0'), isFalse);
      expect(isUpdateRequired('1.0.0+5', '1.0.1'), isTrue);
    });

    test('最低サポート側の +ビルド番号 も除去される', () {
      expect(isUpdateRequired('1.0.0', '1.0.0+3'), isFalse);
      expect(isUpdateRequired('1.0.0+1', '1.0.1+9'), isTrue);
    });
  });

  group('isUpdateRequired - 数値比較（文字列比較でない）', () {
    test('1.10.0 は 1.9.0 より新しい', () {
      expect(isUpdateRequired('1.10.0', '1.9.0'), isFalse);
    });

    test('1.2.0 は 1.10.0 より古い', () {
      expect(isUpdateRequired('1.2.0', '1.10.0'), isTrue);
    });

    test('0.9.0 は 0.10.0 より古い', () {
      expect(isUpdateRequired('0.9.0', '0.10.0'), isTrue);
    });
  });

  group('isUpdateRequired - 不正な形式は fail-open（false）', () {
    test('パース不能な現在バージョンは更新不要扱い', () {
      expect(isUpdateRequired('abc', '1.0.0'), isFalse);
      expect(isUpdateRequired('', '1.0.0'), isFalse);
      expect(isUpdateRequired('1.0', '1.0.0'), isFalse);
      expect(isUpdateRequired('1.0.0.0', '1.0.0'), isFalse);
      expect(isUpdateRequired('1.0.x', '1.0.0'), isFalse);
    });

    test('パース不能な最低サポートバージョンは更新不要扱い', () {
      expect(isUpdateRequired('1.0.0', 'abc'), isFalse);
      expect(isUpdateRequired('1.0.0', ''), isFalse);
      expect(isUpdateRequired('1.0.0', '2.0'), isFalse);
    });

    test('負数を含むバージョンは更新不要扱い', () {
      expect(isUpdateRequired('1.-1.0', '1.0.0'), isFalse);
    });
  });

  group('isUpdateRequired - 空白の扱い', () {
    test('前後の空白は無視して比較する', () {
      expect(isUpdateRequired(' 1.0.0 ', '1.0.0'), isFalse);
      expect(isUpdateRequired('1.0.0', ' 1.0.1 '), isTrue);
    });
  });
}
