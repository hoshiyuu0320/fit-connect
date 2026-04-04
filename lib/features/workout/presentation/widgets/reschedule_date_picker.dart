import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary500,
            foregroundColor: Colors.white,
          ),
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
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () {
          showDialog<DateTime>(
            context: context,
            builder: (_) => const RescheduleDatePicker(),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary500,
          foregroundColor: Colors.white,
        ),
        child: const Text('日付変更ダイアログを開く'),
      ),
    );
  }
}

@Preview(name: 'RescheduleDatePicker - Dialog')
Widget previewRescheduleDatePicker() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _RescheduleDatePickerPreviewWrapper(),
      ),
    ),
  );
}
