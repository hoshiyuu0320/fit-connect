import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 3段階の目覚め評価セレクタ（すっきり / まあまあ / だるい）。ダイアログ + 編集ボトムシートで再利用。
///
/// 絵文字・アイコンをやめ、**言葉だけ**の選択肢にした（基盤の [FcSegmentedControl]）。
/// 選択中 = actionFill の塗り + onAction の文字、未選択 = surface の面 + 1px の枠。
/// 押すとすぐ [onSelect] を呼ぶ（保存の挙動は呼び出し側が持つ）。
/// 文字拡大では項目が折り返して高さが伸びる。
class WakeupRatingSelector extends StatelessWidget {
  final WakeupRating? selected;
  final ValueChanged<WakeupRating> onSelect;

  const WakeupRatingSelector({
    super.key,
    this.selected,
    required this.onSelect,
  });

  /// 並び順（良い → 悪い）
  static const List<WakeupRating> options = [
    WakeupRating.refreshed,
    WakeupRating.okay,
    WakeupRating.groggy,
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '目覚めの評価',
      child: FcSegmentedControl<WakeupRating?>(
        items: [
          for (final r in options)
            FcSegmentedItem<WakeupRating?>(value: r, label: r.labelJa),
        ],
        selected: selected,
        onChanged: (value) {
          if (value != null) onSelect(value);
        },
      ),
    );
  }
}

// =====================================
// プレビュー
// =====================================

Widget _previewSelector({
  required Brightness brightness,
  WakeupRating? selected,
  double scale = 1,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: FcCard(
            child: WakeupRatingSelector(selected: selected, onSelect: (_) {}),
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'WakeupRatingSelector - 未選択')
Widget previewWakeupRatingSelectorUnselected() =>
    _previewSelector(brightness: Brightness.light);

@Preview(name: 'WakeupRatingSelector - すっきり（選択中）')
Widget previewWakeupRatingSelectorRefreshed() => _previewSelector(
      brightness: Brightness.light,
      selected: WakeupRating.refreshed,
    );

@Preview(name: 'WakeupRatingSelector - ダーク')
Widget previewWakeupRatingSelectorDark() => _previewSelector(
      brightness: Brightness.dark,
      selected: WakeupRating.okay,
    );

@Preview(name: 'WakeupRatingSelector - 文字拡大 1.35')
Widget previewWakeupRatingSelectorLarge() => _previewSelector(
      brightness: Brightness.light,
      selected: WakeupRating.groggy,
      scale: 1.35,
    );
