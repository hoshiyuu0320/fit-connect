import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/consent/legal_links.dart';

// Health Connect の権限画面で「プライバシーポリシー」を押すと、Android は
// マニフェストで宣言した入り口（Android 13 以下は rationale の intent、
// 14 以上は activity-alias）を開く。どちらも PermissionsRationaleActivity に向き、
// アプリ内のリンクと同じプライバシーポリシーを開くことを、マニフェストと
// Kotlin のソースから確かめる。
// flutter test はパッケージのルート（fit-connect-mobile/）で動くので、相対パスで読む

const _activityPath = 'android/app/src/main/kotlin/com/fitconnect/'
    'fit_connect_mobile/PermissionsRationaleActivity.kt';
const _manifestPath = 'android/app/src/main/AndroidManifest.xml';

const _rationaleAction = 'androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path が無い');
  return file.readAsStringSync();
}

/// XML のコメント（`<!-- ... -->`）を取り除いたマニフェスト。
/// コメントに書いた名前を、要素として数えないため
String _manifest() =>
    _read(_manifestPath).replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// タグ名が [tag] の要素を、開始タグから終了タグまで切り出す（自己終了タグはそのタグだけ）。
/// `activity` を指定しても `activity-alias` は含まない
List<String> _elements(String manifest, String tag) {
  final name = RegExp.escape(tag);
  return RegExp('<$name\\s[^>]*?(?:/>|>.*?</$name>)', dotAll: true)
      .allMatches(manifest)
      .map((m) => m.group(0)!)
      .toList();
}

/// 要素の開始タグにある属性 [name] の値
String? _attribute(String element, String name) {
  final startTag = RegExp(r'^<[^>]*>').firstMatch(element)!.group(0)!;
  return RegExp('\\s${RegExp.escape(name)}="([^"]*)"')
      .firstMatch(startTag)
      ?.group(1);
}

/// 要素の中に `<[tag] android:name="[name]">`（action・category）がある
bool _hasChild(String element, String tag, String name) {
  return RegExp(
    '<${RegExp.escape(tag)}\\s[^>]*android:name="${RegExp.escape(name)}"',
  ).hasMatch(element);
}

/// `android:name` が [name] の要素（1つだけあること）
String _named(List<String> elements, String name) {
  final found =
      elements.where((e) => _attribute(e, 'android:name') == name).toList();
  expect(found, hasLength(1), reason: 'android:name="$name" の要素');
  return found.single;
}

void main() {
  group('Health Connect の権限画面の「プライバシーポリシー」（Android）', () {
    test(
        'PermissionsRationaleActivity が開く URL は、アプリ内のリンク（LegalLinks.privacyUrl）と同じ',
        () {
      final source = _read(_activityPath);
      expect(source, contains('"${LegalLinks.privacyUrl}"'));
    });

    test(
        'Android 13 以下の rationale の intent は PermissionsRationaleActivity だけが受け、MainActivity は受けない',
        () {
      // <activity> の要素だけを見るので、<queries> の中の <intent> は数えない
      final activities = _elements(_manifest(), 'activity');
      final receivers = activities
          .where((e) => _hasChild(e, 'action', _rationaleAction))
          .map((e) => _attribute(e, 'android:name'))
          .toList();
      expect(receivers, ['.PermissionsRationaleActivity']);
      expect(
        _hasChild(
          _named(activities, '.MainActivity'),
          'action',
          _rationaleAction,
        ),
        isFalse,
      );
    });

    test(
        'Android 14 以上の activity-alias は PermissionsRationaleActivity を開き、権限の使い道の intent を受ける',
        () {
      final alias = _named(
        _elements(_manifest(), 'activity-alias'),
        'ViewPermissionUsageActivity',
      );
      expect(
        _attribute(alias, 'android:targetActivity'),
        '.PermissionsRationaleActivity',
      );
      // 開けるのは START_VIEW_PERMISSION_USAGE を持つシステム（Health Connect）だけ
      expect(
        _attribute(alias, 'android:permission'),
        'android.permission.START_VIEW_PERMISSION_USAGE',
      );
      expect(_attribute(alias, 'android:exported'), 'true');
      expect(
        _hasChild(
          alias,
          'action',
          'android.intent.action.VIEW_PERMISSION_USAGE',
        ),
        isTrue,
      );
      expect(
        _hasChild(
          alias,
          'category',
          'android.intent.category.HEALTH_PERMISSIONS',
        ),
        isTrue,
      );
    });

    test('PermissionsRationaleActivity は Health Connect（他のアプリ）から開ける（exported）',
        () {
      final activity = _named(
        _elements(_manifest(), 'activity'),
        '.PermissionsRationaleActivity',
      );
      expect(_attribute(activity, 'android:exported'), 'true');
    });
  });
}
