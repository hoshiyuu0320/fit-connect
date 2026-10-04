import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// プランの日付を変えるときの日付選択ダイアログ（今日から 30 日先まで）。
///
/// 色・角丸は新しいテーマ（`DatePickerTheme` / `DialogTheme` / ボタンのテーマ）がそのまま当たる。
class RescheduleDatePicker extends StatefulWidget {
  const RescheduleDatePicker({super.key});

  @override
  State<RescheduleDatePicker> createState() => _RescheduleDatePickerState();
}

class _RescheduleDatePickerState extends State<RescheduleDatePicker> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return AlertDialog(
      title: const Text('日付を変更'),
      content: SizedBox(
        width: 300,
        height: 300,
        child: CalendarDatePicker(
          initialDate: _selectedDate,
          firstDate: today,
          lastDate: today.add(const Duration(days: 30)),
          onDateChanged: (date) {
            setState(() => _selectedDate = date);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selectedDate),
          child: const Text('変更する'),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

class _RescheduleDatePickerPreviewWrapper extends StatelessWidget {
  const _RescheduleDatePickerPreviewWrapper();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FcButton.pill(
        label: '日付変更ダイアログを開く',
        onPressed: () {
          showDialog<DateTime>(
            context: context,
            builder: (_) => const RescheduleDatePicker(),
          );
        },
      ),
    );
  }
}

@Preview(name: 'RescheduleDatePicker - Dialog')
Widget previewRescheduleDatePicker() {
  return FcPreviewApp(
    brightness: Brightness.light,
    home: const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.pageHorizontal),
          child: _RescheduleDatePickerPreviewWrapper(),
        ),
      ),
    ),
  );
}

@Preview(name: 'RescheduleDatePicker - Dialog (Dark)')
Widget previewRescheduleDatePickerDark() {
  return FcPreviewApp(
    brightness: Brightness.dark,
    home: const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.pageHorizontal),
          child: _RescheduleDatePickerPreviewWrapper(),
        ),
      ),
    ),
  );
}
