import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 記録のリマインダーの時刻を選ぶボトムシートを開く（設計 §8）。
///
/// 「決定」で選んだ時刻を返す。「キャンセル」・シートの外を押す・下へ払うと null。
/// 時刻は 24 時間表記・5分刻みのホイール（`CupertinoDatePicker`）。MaterialApp にローカライズの
/// 設定が無く、Material の時刻の選択（`showTimePicker`）は英語になるので使わない。
Future<ReminderTime?> showReminderTimePickerSheet(
  BuildContext context, {
  required ReminderTime initial,
  required String title,
}) {
  return showModalBottomSheet<ReminderTime>(
    context: context,
    // 面の色と上の角丸 23 はテーマ（BottomSheetTheme）に任せる
    isScrollControlled: true,
    useSafeArea: true,
    // 正本のシートの暗幕 rgba(0,0,0,.32)
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => ReminderTimePickerSheet(initial: initial, title: title),
  );
}

/// 時刻を選ぶシートの中身（つまみ・見出し・ホイール・「キャンセル」「決定」）。
///
/// 見た目は正本のシート（surface の面・上の角丸 23・上端のつまみ・見出し 20 / 500）に合わせる。
/// 選んだ時刻は「決定」で `Navigator.pop` の結果として返す（「キャンセル」は null）。
/// ホイールは OS の文字サイズに合わせて大きくならない（`CupertinoDatePicker` が拡大を止める。
/// iOS の時刻の選択と同じ）。見出しとボタンは拡大に追従する
class ReminderTimePickerSheet extends StatefulWidget {
  const ReminderTimePickerSheet({
    super.key,
    required this.initial,
    required this.title,
  });

  /// 開いたときの時刻（5分刻み）
  final ReminderTime initial;

  /// 見出し（例「夕食の時刻」）
  final String title;

  @override
  State<ReminderTimePickerSheet> createState() =>
      _ReminderTimePickerSheetState();
}

class _ReminderTimePickerSheetState extends State<ReminderTimePickerSheet> {
  /// ホイールの高さ（iOS の時刻の選択と同じ 216）
  static const double _wheelHeight = 216;

  late ReminderTime _selected = widget.initial;

  void _onChanged(DateTime value) {
    // ホイールは5分刻みだが、ReminderTime は5分刻みしか持てないので念のため刻みに揃える
    _selected = ReminderTime(
      hour: value.hour,
      minute: value.minute - value.minute % ReminderTime.minuteStep,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final horizontal = AppSpacing.pageHorizontalOf(context);

    // 正本のシート: 余白 上10・左右20・下30。端末の下端の安全領域（ホームインジケータ）が
    // 30 より大きければそちらを使う
    final bottom = math.max(30.0, MediaQuery.viewPaddingOf(context).bottom);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上端のつまみ（36×5・separator）。操作はできないので読み上げ対象外
          ExcludeSemantics(
            child: Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.separator,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              widget.title,
              style: AppTextStyles.sectionHeading(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: _wheelHeight,
            child: _ReminderTimeWheel(
              initial: widget.initial,
              onChanged: _onChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FcButton.pill(
                  label: 'キャンセル',
                  quiet: true,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FcButton.pill(
                  label: '決定',
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(_selected),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 24 時間表記・5分刻みの時刻のホイール。
///
/// 数字は DS の数値（20 / 500・等幅数字・textPrimary）、面は surface にして、
/// ライト・ダークのどちらでも読めるようにする（`CupertinoTheme` の `dateTimePickerTextStyle`）。
/// 選択中の帯は `CupertinoDatePicker` の既定（半透明の灰色）のまま。上に重なるので不透明の色にできない
class _ReminderTimeWheel extends StatelessWidget {
  const _ReminderTimeWheel({required this.initial, required this.onChanged});

  final ReminderTime initial;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final cupertino = CupertinoTheme.of(context);

    return Localizations.override(
      context: context,
      delegates: const [_JapaneseTimeWheelLocalizations.delegate],
      child: CupertinoTheme(
        data: cupertino.copyWith(
          textTheme: cupertino.textTheme.copyWith(
            dateTimePickerTextStyle: AppTextStyles.metric(
              context,
              size: FcNumSize.compact.fontSize,
            ),
          ),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          use24hFormat: true,
          minuteInterval: ReminderTime.minuteStep,
          // 時刻だけを選ぶので日付は使わない。端末が夏時間のある時間帯のとき、切り替わる日に
          // 時刻がずれないよう、切り替えの無い日（1月1日）に固定する
          initialDateTime: DateTime(2000, 1, 1, initial.hour, initial.minute),
          backgroundColor: colors.surface,
          onDateTimeChanged: onChanged,
        ),
      ),
    );
  }
}

/// ホイールの読み上げを日本語にする（「20時」「30分」）。
/// MaterialApp にローカライズの設定が無く、既定（英語）のままだと「20 o'clock」「30 minutes」と読まれる
class _JapaneseTimeWheelLocalizations extends DefaultCupertinoLocalizations {
  const _JapaneseTimeWheelLocalizations();

  static const LocalizationsDelegate<CupertinoLocalizations> delegate =
      _JapaneseTimeWheelLocalizationsDelegate();

  @override
  String datePickerHourSemanticsLabel(int hour) => '$hour時';

  @override
  String datePickerMinuteSemanticsLabel(int minute) => '$minute分';
}

class _JapaneseTimeWheelLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _JapaneseTimeWheelLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(
        const _JapaneseTimeWheelLocalizations(),
      );

  @override
  bool shouldReload(_JapaneseTimeWheelLocalizationsDelegate old) => false;
}

// ============================================
// Previews
// ============================================

/// 本物のシートと同じ面・角丸（23）・暗幕で、シートを画面の下に重ねて見せる
class _PreviewSheetHost extends StatelessWidget {
  const _PreviewSheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.32),
            child: const SizedBox.expand(),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: AppColors.of(context).surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.card),
              ),
              child: const ReminderTimePickerSheet(
                initial: ReminderTime(hour: 20, minute: 0),
                title: '夕食の時刻',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@Preview(name: 'ReminderTimePickerSheet - 夕食 20:00')
Widget previewReminderTimePickerSheet() => const FcPreviewApp(
      brightness: Brightness.light,
      home: _PreviewSheetHost(),
    );

/// ダーク: ホイールの数字（textPrimary）と面（surface）が暗い配色で読めることを確認する
@Preview(name: 'ReminderTimePickerSheet - 夕食 20:00（ダーク）')
Widget previewReminderTimePickerSheetDark() => const FcPreviewApp(
      brightness: Brightness.dark,
      home: _PreviewSheetHost(),
    );

/// 文字拡大: 見出しとボタンだけが大きくなる（ホイールは拡大しない）
@Preview(name: 'ReminderTimePickerSheet - 文字拡大 1.35')
Widget previewReminderTimePickerSheetLargeText() => const FcPreviewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      home: _PreviewSheetHost(),
    );
