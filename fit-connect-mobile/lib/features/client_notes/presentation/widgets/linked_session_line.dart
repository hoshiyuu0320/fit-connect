import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/utils/note_labels.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// ノートに紐づくセッションの見出し行（calendar-days ＋「9月8日（火）19:00 · パーソナル」）。
///
/// カルテ一覧の [NoteCard] の先頭に出す。廃止した `#N`（session_number）の代わりに
/// 「どのセッションのノートか」を日時で示す。紐づけの無いノートでは呼び出し側が
/// 行ごと出さない（null は受け取らない）。
///
/// 正本: アイコン 15・文字 13（行高 1.5）・どちらも accent・間 6。
/// 種別（パーソナルなど）は日時の後ろに「 · 」でつなぐ（別のチップにしない）。
/// 年はセッションの年が [now] と違うときだけ付く。
/// 文字拡大では折り返して縦に伸びる（アイコンは 1 行目に揃える）。
class LinkedSessionLine extends StatelessWidget {
  final LinkedSession session;

  /// 年の付与判定に使う現在時刻。呼び出し側が1フレームにつき1回だけ取得したものを渡す
  /// （行ごとに引き直すと日跨ぎで年表示が食い違う）
  final DateTime now;

  const LinkedSessionLine({
    super.key,
    required this.session,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.of(context).accent;
    final label = formatLinkedSessionLabel(session, now: now);
    final style = AppTextStyles.supplement(context).copyWith(color: tint);
    // 文字の 1 行目の高さ（拡大に追従）の中央にアイコンを置く
    final lineHeight = MediaQuery.textScalerOf(context).scale(13) * 1.5;
    final iconTop = ((lineHeight - 15) / 2).clamp(0.0, double.infinity);

    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: iconTop),
            child: Icon(LucideIcons.calendarDays, size: 15, color: tint),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: style)),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewLines({required Brightness brightness, double scale = 1}) {
  final now = DateTime(2026, 9, 13);
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 今年なら年なし
              LinkedSessionLine(
                session: LinkedSession(
                  sessionDate: DateTime(2026, 9, 8, 19),
                  sessionType: 'パーソナル',
                ),
                now: now,
              ),
              const SizedBox(height: AppSpacing.lg),
              // 'other' は「その他」に変換される
              LinkedSessionLine(
                session: LinkedSession(
                  sessionDate: DateTime(2026, 9, 8, 19),
                  sessionType: 'other',
                ),
                now: now,
              ),
              const SizedBox(height: AppSpacing.lg),
              // 種別なし（日時だけ）
              LinkedSessionLine(
                session:
                    LinkedSession(sessionDate: DateTime(2026, 9, 8, 9, 30)),
                now: now,
              ),
              const SizedBox(height: AppSpacing.lg),
              // 長い種別・昨年のセッション（年付き・折り返し）
              LinkedSessionLine(
                session: LinkedSession(
                  sessionDate: DateTime(2025, 12, 20, 11),
                  sessionType: 'パーソナルトレーニング（体験・初回カウンセリング付き）',
                ),
                now: now,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'LinkedSessionLine - ライト')
Widget previewLinkedSessionLineLight() =>
    _previewLines(brightness: Brightness.light);

@Preview(name: 'LinkedSessionLine - ダーク')
Widget previewLinkedSessionLineDark() =>
    _previewLines(brightness: Brightness.dark);

@Preview(name: 'LinkedSessionLine - 文字拡大 1.35')
Widget previewLinkedSessionLineLarge() =>
    _previewLines(brightness: Brightness.light, scale: 1.35);
