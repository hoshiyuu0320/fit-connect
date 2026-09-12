import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/session_meta_chip.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';

/// ノートに紐づくセッションの見出し行（日時を主役に + 種別チップ）。
///
/// 廃止した `#N`（session_number）の代わりに「どのセッションのノートか」を
/// 日時で示す。NoteCard（一覧）と ClientNoteDetailScreen（詳細）の両方で
/// 同じ見た目にするため、SessionMetaChip と同様に実装はこのファイル1箇所にだけ置くこと。
/// 紐づけの無いノートでは呼び出し側が行ごと出さない（null は受け取らない）。
///
/// 日時の整形はセッション一覧・ホームと同じ規則（session_formatting.dart）。
/// 作成日（`2026年9月10日`）と並んでも見分けがつくよう、アイコンは calendarCheck にしてある
class LinkedSessionLine extends StatelessWidget {
  final LinkedSession session;

  /// 年の付与判定に使う現在時刻。呼び出し側が1フレームにつき1回だけ取得したものを渡す
  /// （行ごとに引き直すと日跨ぎで年表示が食い違う）
  final DateTime now;

  /// 年を常に付けるか。詳細は単票で前後の文脈が無いので付け、
  /// 一覧は今年と違うときだけ付く（formatSessionDateTime の既定）
  final bool includeYear;

  /// 日時とアイコンの色。省略時は primary600（surface 上での従来色。NoteCard はこちら）。
  /// 淡青カード（colors.primaryTint）の上に置くときは、ダークで背景に溶けないよう
  /// `colors.primaryTintForeground` を渡す（ClientNoteDetailScreen のヘッダー）
  final Color? color;

  const LinkedSessionLine({
    super.key,
    required this.session,
    required this.now,
    this.includeYear = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = sessionTypeLabel(session.sessionType);
    final accent = color ?? AppColors.primary600;

    // 種別が長い場合は次の行へ折り返す（日時を潰さない）
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.calendarCheck,
              size: 16,
              color: accent,
            ),
            const SizedBox(width: 6),
            Text(
              formatSessionDateTime(
                session.sessionDate,
                now: now,
                includeYear: includeYear,
              ),
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (typeLabel != null)
          SessionMetaChip(
            icon: LucideIcons.dumbbell,
            label: typeLabel,
          ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'LinkedSessionLine - With Type')
Widget previewLinkedSessionLineWithType() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 一覧用（今年なら年なし）
              LinkedSessionLine(
                session: LinkedSession(
                  sessionDate: DateTime.now().subtract(const Duration(days: 2)),
                  sessionType: 'パーソナルトレーニング',
                ),
                now: DateTime.now(),
              ),
              const SizedBox(height: 16),
              // 詳細用（常に年あり）。'other' は「その他」に変換される
              LinkedSessionLine(
                session: LinkedSession(
                  sessionDate: DateTime.now().subtract(const Duration(days: 2)),
                  sessionType: 'other',
                ),
                now: DateTime.now(),
                includeYear: true,
              ),
              const SizedBox(height: 16),
              // 種別なし（日時だけ）
              LinkedSessionLine(
                session: LinkedSession(
                  sessionDate: DateTime.now().subtract(const Duration(days: 2)),
                ),
                now: DateTime.now(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
