import 'fc/fc_segmented_control.dart';

export 'fc/fc_segmented_control.dart';

/// 互換エイリアス。実体は新デザインの [FcSegmentedControl]（高さ 45・角丸 10・surfaceSecondary の面）。
///
/// 既存の呼び出し（PeriodFilterChips / SessionsScreen）が API を変えずに動くよう、
/// 旧名のまま使える。新規コードは `FcSegmentedControl` / `FcSegmentedItem` を使うこと。
typedef SegmentedControl<T> = FcSegmentedControl<T>;

/// 互換エイリアス。新規コードは [FcSegmentedItem] を使う。
typedef SegmentedControlItem<T> = FcSegmentedItem<T>;
