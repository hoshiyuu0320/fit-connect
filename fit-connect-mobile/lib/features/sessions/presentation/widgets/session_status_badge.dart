import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';

/// セッションのステータスバッジ。
///
/// ラベルは SessionModel.statusLabel（モデルが単一の真実）を使い、
/// 色だけをここで解決する。背景色はダークモードに追従させる必要があるため
/// AppColors.of(context) 経由で取得している。
///
/// ※ NextSessionCard / SessionsScreen の両方から使うので、色の対応表は
///   このファイル1箇所にだけ置くこと（重複実装しない）。
class SessionStatusBadge extends StatelessWidget {
  final SessionModel session;

  const SessionStatusBadge({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // 未知のステータス（CHECK制約に将来値が増えた場合）はグレーに倒す
    final status = session.statusType;
    final background = switch (status) {
      SessionStatus.scheduled => AppColors.primary50,
      SessionStatus.confirmed => AppColors.emerald50,
      SessionStatus.completed => colors.border,
      SessionStatus.cancelled => AppColors.rose100,
      null => colors.border,
    };
    final foreground = switch (status) {
      SessionStatus.scheduled => AppColors.primary700,
      SessionStatus.confirmed => AppColors.emerald600,
      SessionStatus.completed => colors.textSecondary,
      SessionStatus.cancelled => AppColors.rose800,
      null => colors.textHint,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        session.statusLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用のダミーセッション生成
SessionModel _makeBadgePreviewSession(String status) {
  final now = DateTime.now();
  return SessionModel(
    id: 'preview-$status',
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: now,
    durationMinutes: 60,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

@Preview(name: 'SessionStatusBadge - All Statuses')
Widget previewSessionStatusBadgeAll() {
  // 末尾の 'unknown' は CHECK制約外の未知値（生値がそのまま出る）フォールバック確認用
  const statuses = [
    'scheduled',
    'confirmed',
    'completed',
    'cancelled',
    'unknown',
  ];

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in statuses)
                SessionStatusBadge(session: _makeBadgePreviewSession(status)),
            ],
          ),
        ),
      ),
    ),
  );
}
