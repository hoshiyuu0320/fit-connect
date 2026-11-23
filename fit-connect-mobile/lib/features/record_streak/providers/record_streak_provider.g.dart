// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record_streak_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$recordStreakHash() => r'8d22ef575370691ab73d4c9764887276a6fab847';

/// 今のクライアントの記録の連続（DB の get_record_streak。設計 §6.1・§6.2）。
///
/// 自動破棄なので、ホームを作るたびに読み直す（記録タブ・メッセージ・プランで付けた記録は、
/// ホームに戻れば反映される）。アプリが前面に戻ったとき（app.dart）と、目覚めの評価を付けたとき
/// （SleepRecords.upsertWakeupRating）にも `ref.invalidate` で読み直す。
/// ログインしていない（クライアントが分からない）ときは null
///
/// Copied from [recordStreak].
@ProviderFor(recordStreak)
final recordStreakProvider =
    AutoDisposeFutureProvider<RecordStreakStatus?>.internal(
  recordStreak,
  name: r'recordStreakProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$recordStreakHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RecordStreakRef = AutoDisposeFutureProviderRef<RecordStreakStatus?>;
String _$recordStreakViewHash() => r'85cf783a467f7d8ccf8116739ec02afaf21e0f98';

/// ホームの「記録の連続」の行に出す状態（[recordStreakProvider] と送ったタグの先取りを合わせる。
/// 設計 §6.1・§6.3・§6.4）。
///
/// [recordStreakProvider] の状態を AsyncValue.whenData で写す。Riverpod 2.6.1 の whenData が
/// 前の値を残すのは、前の値の AsyncData（読み直しの間）だけ:
/// - 読み直し（invalidate。前面に戻ったとき・目覚めの評価を付けたとき）の間 → 前の値の AsyncData（isRefreshing）
/// - 読み直しに失敗した → 前の値を持たない AsyncError（ホームは行を消す。前の値は残さない）
/// - client id が変わった（ログインし直したなど）→ 前の値を持たない AsyncLoading
///   （ホームはスケルトン。前の人の値を出さない）
/// - 初めての読み込み中・読めない → AsyncLoading / AsyncError
/// - ログインしていない → AsyncData(null)
///
/// 先取りが効くのは、覚えた client id が今の人で、覚えた日付が DB の今日（asOfDate）と同じで、
/// 送ってから [RecordStreakTagOverlay.window] 以内のときだけ（[RecordStreakTagOverlay.countsToday]）。
/// 送ってからの時間は、この状態を作るたびに調べる（過ぎたときに自分では作り直さない）
///
/// Copied from [recordStreakView].
@ProviderFor(recordStreakView)
final recordStreakViewProvider =
    AutoDisposeProvider<AsyncValue<RecordStreakView?>>.internal(
  recordStreakView,
  name: r'recordStreakViewProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$recordStreakViewHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RecordStreakViewRef
    = AutoDisposeProviderRef<AsyncValue<RecordStreakView?>>;
String _$recordStreakTagOverlayHash() =>
    r'35bfdffc88f29384c491ca318e367a578edb39dc';

/// 送ったタグの先取り（設計 §6.3）。記録になるタグを送ったときの
/// (client id, サーバーが付けた送信時刻の日本時間の日付, 端末の時計で送った時刻)。
///
/// メッセージから作られる記録は、DB の webhook の後で数秒遅れて入る。送った直後にホームへ戻っても
/// 今日記録済みに見えるよう、送ったことを覚えておく（[recordStreakViewProvider] が DB の結果と合わせる）。
/// 効くのは送ってから 60 秒（[RecordStreakTagOverlay.window]）のあいだだけで、過ぎたら DB の値だけを見る。
/// そのため、タグが記録にならなかったとき（全角の数字・範囲外の値など）や、送ったあとにタグを消す編集を
/// したときも、次に読み直せば DB のとおりに戻る。
/// 覚えるのはアプリを終えるまで（keepAlive）。ログアウトしても消さず、効くかどうかは
/// client id・日付・送ってからの時間で決める
///
/// Copied from [RecordStreakTagOverlay].
@ProviderFor(RecordStreakTagOverlay)
final recordStreakTagOverlayProvider = NotifierProvider<RecordStreakTagOverlay,
    ({String clientId, String jstDateKey, DateTime sentAt})?>.internal(
  RecordStreakTagOverlay.new,
  name: r'recordStreakTagOverlayProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$recordStreakTagOverlayHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$RecordStreakTagOverlay
    = Notifier<({String clientId, String jstDateKey, DateTime sentAt})?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
