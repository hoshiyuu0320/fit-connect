import 'package:fit_connect_mobile/shared/storage/storage_value_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bucket = 'message-photos';
  const projectBase = 'https://abcd1234.supabase.co/storage/v1/object';

  group('resolveStorageValue - 空値', () {
    test('null は empty', () {
      final resolved = resolveStorageValue(null, bucket);
      expect(resolved.isEmpty, isTrue);
      expect(resolved.path, isNull);
      expect(resolved.externalUrl, isNull);
    });

    test('空文字・空白のみは empty', () {
      expect(resolveStorageValue('', bucket).isEmpty, isTrue);
      expect(resolveStorageValue('   ', bucket).isEmpty, isTrue);
    });

    test('フラグメントのみ（#name）は empty', () {
      expect(resolveStorageValue('#file.pdf', bucket).isEmpty, isTrue);
    });
  });

  group('resolveStorageValue - バケット相対パス', () {
    test('素のパスはそのまま path になる', () {
      final resolved = resolveStorageValue('uid-1/abc-uuid.jpg', bucket);
      expect(resolved.path, 'uid-1/abc-uuid.jpg');
      expect(resolved.isExternal, isFalse);
      expect(resolved.fragment, isNull);
    });

    test('AI 画像パス（uid/ai/uuid.jpg）も path として扱う', () {
      final resolved = resolveStorageValue('uid-1/ai/xyz.jpg', bucket);
      expect(resolved.path, 'uid-1/ai/xyz.jpg');
    });

    test('# フラグメント付きパスはパスとフラグメントに分離される', () {
      final resolved = resolveStorageValue(
        'trainer-1/client-1/1700000000_plan.pdf#%E8%A8%88%E7%94%BB%E6%9B%B8.pdf',
        'client-notes',
      );
      expect(resolved.path, 'trainer-1/client-1/1700000000_plan.pdf');
      expect(resolved.fragment, '%E8%A8%88%E7%94%BB%E6%9B%B8.pdf');
      expect(resolved.decodedFragment, '計画書.pdf');
    });

    test('前後の空白は除去される', () {
      final resolved = resolveStorageValue('  uid-1/img.jpg  ', bucket);
      expect(resolved.path, 'uid-1/img.jpg');
    });
  });

  group('resolveStorageValue - レガシー Storage URL', () {
    test('公開 URL からパスを抽出する', () {
      final resolved = resolveStorageValue(
        '$projectBase/public/$bucket/uid-1/abc.jpg',
        bucket,
      );
      expect(resolved.path, 'uid-1/abc.jpg');
      expect(resolved.isExternal, isFalse);
    });

    test('クエリ付き公開 URL（?t= キャッシュバスター）はクエリを除去する', () {
      final resolved = resolveStorageValue(
        '$projectBase/public/client-avatars/uid-1/avatar.jpg?t=1700000000000',
        'client-avatars',
      );
      expect(resolved.path, 'uid-1/avatar.jpg');
    });

    test('署名 URL（/sign/）からもパスを抽出する', () {
      final resolved = resolveStorageValue(
        '$projectBase/sign/$bucket/uid-1/abc.jpg?token=xyz.abc',
        bucket,
      );
      expect(resolved.path, 'uid-1/abc.jpg');
    });

    test('# フラグメント付き URL はパスとフラグメントに分離される', () {
      final resolved = resolveStorageValue(
        '$projectBase/public/client-notes/t-1/c-1/1700_memo.pdf#memo.pdf',
        'client-notes',
      );
      expect(resolved.path, 't-1/c-1/1700_memo.pdf');
      expect(resolved.fragment, 'memo.pdf');
    });

    test('percent エンコードされたパスはデコードされる', () {
      final resolved = resolveStorageValue(
        '$projectBase/public/$bucket/uid-1/my%20image.jpg',
        bucket,
      );
      expect(resolved.path, 'uid-1/my image.jpg');
    });
  });

  group('resolveStorageValue - 外部 URL', () {
    test('Google アバター等の外部 URL はそのまま返す', () {
      const url = 'https://lh3.googleusercontent.com/a/ACg8ocK_example=s96-c';
      final resolved = resolveStorageValue(url, 'client-avatars');
      expect(resolved.isExternal, isTrue);
      expect(resolved.externalUrl, url);
      expect(resolved.path, isNull);
    });

    test('バケットが一致しない Storage URL は外部 URL として扱う', () {
      const url = '$projectBase/public/client-avatars/uid-1/avatar.jpg';
      final resolved = resolveStorageValue(url, bucket);
      expect(resolved.isExternal, isTrue);
      expect(resolved.externalUrl, url);
    });
  });

  group('isExternalUrl', () {
    test('パスは外部 URL ではない', () {
      expect(isExternalUrl('uid-1/abc.jpg', bucket), isFalse);
    });

    test('同一バケットの Storage URL は外部 URL ではない', () {
      expect(
        isExternalUrl('$projectBase/public/$bucket/uid-1/abc.jpg', bucket),
        isFalse,
      );
    });

    test('Storage 外の http URL は外部 URL', () {
      expect(
        isExternalUrl('https://lh3.googleusercontent.com/a/xyz', bucket),
        isTrue,
      );
    });
  });

  group('splitFragment', () {
    test('フラグメントなしは (value, null)', () {
      expect(splitFragment('a/b.jpg'), ('a/b.jpg', null));
    });

    test('フラグメントありは本体と分離される', () {
      expect(splitFragment('a/b.pdf#name.pdf'), ('a/b.pdf', 'name.pdf'));
    });

    test('最初の # で分離される', () {
      expect(splitFragment('a/b.pdf#x#y'), ('a/b.pdf', 'x#y'));
    });
  });

  group('ResolvedStorageValue.decodedFragment', () {
    test('不正な percent エンコードは生値のまま返す', () {
      const resolved =
          ResolvedStorageValue.path('a/b.pdf', fragment: '%E4%B8%8D%ZZ');
      expect(resolved.decodedFragment, '%E4%B8%8D%ZZ');
    });
  });
}
