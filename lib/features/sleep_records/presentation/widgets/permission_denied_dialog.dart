import 'dart:io' show Platform;
import 'dart:ui';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

/// HealthKit/Health Connect 権限拒否時のダイアログ。
class PermissionDeniedDialog extends StatelessWidget {
  const PermissionDeniedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: Colors.black.withValues(alpha: 0.42),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.red100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        LucideIcons.lock,
                        size: 17,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ヘルスケアへのアクセスが許可されていません',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _platformMessage(),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          side: BorderSide(color: colors.border),
                          foregroundColor: colors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('あとで'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _openSettings,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('設定を開く'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _platformMessage() {
    if (kIsWeb) {
      return 'お使いの端末のヘルスケア設定からアクセスを許可してください。';
    }
    if (Platform.isIOS) {
      return '設定アプリの「ヘルスケア」→「データアクセスとデバイス」から FIT-CONNECT に睡眠データの読み取りを許可してください。';
    }
    return 'Health Connect アプリから FIT-CONNECT に睡眠データの読み取りを許可してください。';
  }

  Future<void> _openSettings() async {
    try {
      await AppSettings.openAppSettings();
    } catch (_) {
      // fallback: 何もしない（設定アプリが開けない端末は稀）
    }
  }
}

/// PermissionDeniedDialog を表示するヘルパー
Future<void> showPermissionDeniedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    builder: (_) => const PermissionDeniedDialog(),
  );
}

@Preview(name: 'PermissionDeniedDialog - Static')
Widget previewPermissionDeniedDialog() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      backgroundColor: Color(0xFFFAFAFA),
      body: PermissionDeniedDialog(),
    ),
  );
}
