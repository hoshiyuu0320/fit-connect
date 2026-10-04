import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';

/// ページの大見出し。アイブロウ（13・字間なし）＋ タイトル（32 / 500 / 字間 -1 / 行高 1.2）＋ 補足（16）。
/// 正本は `components/navigation/PageHeading.jsx`。
///
/// - アイブロウは 13 / textSecondary で下余白 6（12px・字間 1.6 の "FIT CONNECT" は `AppTextStyles.brand`）。
///   補足は 16 / textSecondary で上余白 6
/// - 後ろに [bottomSpacing]（既定 24）の余白を含む。画面側で別に空けない
/// - 左右余白は含まない（画面側の `Padding` で 20 / 狭い画面 16 を付ける）
/// - タイトルは見出しとして読み上げられる。文字拡大では折り返す
class FcPageHeading extends StatelessWidget {
  const FcPageHeading({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.bottomSpacing = AppSpacing.afterHeading,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;

  /// タイトルの右に置く操作（44×44 以上にすること）
  final Widget? trailing;

  /// 見出しの後ろの余白
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Semantics(
      header: true,
      child: Text(title, style: AppTextStyles.pageHeading(context)),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(eyebrow!, style: AppTextStyles.eyebrow(context)),
            const SizedBox(height: 6),
          ],
          if (trailing == null)
            titleWidget
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleWidget),
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: AppTextStyles.body(context)
                  .copyWith(color: AppColors.of(context).textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// セクション見出し（20 / 500 / 行高 1.3）。右側に補足（[note]）や「すべて見る」などの操作を置ける。
/// 正本は `parts.js` の `SectionTitle`。
///
/// - **前後の余白を含む**: 正本の `margin: 12px 2px 0`（カード間 16 と合わせて上は 28 空く）。
///   画面側で上の余白を足さない。見出しの下はカード間隔 16 を画面側で空ける
/// - [note] は 13 / textSecondary（見出しの文字のベースラインに揃える）。[trailing] は操作（44×44 以上）
class FcSectionTitle extends StatelessWidget {
  const FcSectionTitle(
    this.text, {
    super.key,
    this.note,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(2, 12, 2, 0),
  });

  final String text;

  /// 右側の補足文字（13 / textSecondary）。例: 「平均 6時間58分」
  final String? note;

  /// 右側の操作・表示。[note] と同時には使わない（[trailing] を優先）
  final Widget? trailing;

  /// 外側の余白（既定は正本の 上 12・左右 2）
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      header: true,
      child: Text(text, style: AppTextStyles.sectionHeading(context)),
    );

    final Widget content;
    if (trailing != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      );
    } else if (note != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: title),
          const SizedBox(width: AppSpacing.md),
          Text(note!, style: AppTextStyles.supplement(context)),
        ],
      );
    } else {
      content = title;
    }
    return Padding(padding: margin, child: content);
  }
}

/// カードの見出し行。**accent** のアイコン（17）＋ ラベル（14・同じく accent）＋ 右側の補足。
/// 正本は `parts.js` の `CardHead`。
///
/// - アイコンとラベルの間隔 6。ラベルは行高 1.5・折り返せる
/// - 右側の [note] は 13 / textSecondary。操作や [FcPill] を置くときは [trailing]
/// - **後ろに [bottomSpacing]（既定 12）の余白を含む**。画面側で別に空けない
/// - 色を割り振らず、アイコンと言葉で区別する
class FcCardHead extends StatelessWidget {
  const FcCardHead({
    super.key,
    required this.icon,
    required this.label,
    this.note,
    this.trailing,
    this.bottomSpacing = 12,
  });

  final IconData icon;
  final String label;

  /// 右側の補足文字（13 / textSecondary）。例: 「今日」「3 / 5 回」
  final String? note;

  /// 右側の操作・表示。[note] と同時には使わない（[trailing] を優先）
  final Widget? trailing;

  /// 見出し行の後ろの余白
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 17, color: colors.accent)),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: AppTextStyles.label(context)
                    .copyWith(color: colors.accent, height: 1.5),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ] else if (note != null) ...[
            const SizedBox(width: 6),
            // 補足は右端に寄せ、幅は行の半分まで（ラベルを先に確保し、長ければ補足が折り返す）
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.5,
              ),
              child: Text(
                note!,
                textAlign: TextAlign.end,
                style: AppTextStyles.supplement(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 数値の大きさ（文字サイズ px）
enum FcNumSize {
  /// ホーム（32）
  home(32),

  /// 振り返り（34）
  review(34),

  /// 指標（[FcStat] の既定。26）
  stat(26),

  /// 小さめの指標（20）
  compact(20);

  const FcNumSize(this.fontSize);

  final double fontSize;
}

/// [FcNum.parts] の 1 組（数値 + 単位）。例: `FcNumPart('7', '時間')`
class FcNumPart {
  const FcNumPart(this.value, [this.unit]);

  final String value;
  final String? unit;
}

/// 数値＋単位。桁幅を揃え（tabular）、**単位は常に表示する**。正本は `parts.js` の `Num`。
///
/// - 数値は 500・行高 1.1・字間（30 以上は -1、それ未満は -0.6）。単位は 13 / 400 / textSecondary で、数値との間に 3
/// - 文字拡大にも追従する（縮めない）。横幅が足りなければ単位ごと折り返す
/// - 例: `FcNum(value: '68.4', unit: 'kg')` / 複数の組は `FcNum.parts(parts: [FcNumPart('7', '時間'), FcNumPart('30', '分')])`
class FcNum extends StatelessWidget {
  const FcNum({
    super.key,
    required this.value,
    this.unit,
    this.size = FcNumSize.home,
    this.color,
    this.semanticLabel,
  }) : parts = null;

  /// 「7 時間 30 分」のように数値と単位の組が続くとき
  const FcNum.parts({
    super.key,
    required List<FcNumPart> this.parts,
    this.size = FcNumSize.home,
    this.color,
    this.semanticLabel,
  })  : value = '',
        unit = null;

  final String value;
  final String? unit;

  /// [FcNum.parts] のときの組（通常のコンストラクタでは null）
  final List<FcNumPart>? parts;
  final FcNumSize size;

  /// 数値の色。null なら textPrimary
  final Color? color;

  /// 読み上げ。null なら「値 + 単位」（複数の組は続けて読む）
  final String? semanticLabel;

  List<FcNumPart> get _parts => parts ?? [FcNumPart(value, unit)];

  @override
  Widget build(BuildContext context) {
    var numStyle = AppTextStyles.metric(context, size: size.fontSize);
    if (color != null) numStyle = numStyle.copyWith(color: color);
    final unitStyle = AppTextStyles.numUnit(context);
    final list = _parts;

    return Semantics(
      label:
          semanticLabel ?? list.map((p) => '${p.value}${p.unit ?? ''}').join(),
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: numStyle,
          children: [
            for (var i = 0; i < list.length; i++) ...[
              TextSpan(text: list[i].value, style: numStyle),
              if (list[i].unit != null) ...[
                const WidgetSpan(child: SizedBox(width: 3)),
                TextSpan(text: list[i].unit, style: unitStyle),
                // 次の組との間（最後の単位の後ろには付けない）
                if (i < list.length - 1)
                  const WidgetSpan(child: SizedBox(width: 3)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// ラベル＋数値＋単位（＋補足）を縦に積んだ指標表示。正本は `parts.js` の `Stat`。
///
/// ラベルは 13 / textSecondary、数値は上 4・既定 26。縦積みなので、文字拡大でも横にはみ出さない。
class FcStat extends StatelessWidget {
  const FcStat({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.size = FcNumSize.stat,
  });

  final String label;
  final String value;
  final String? unit;

  /// 数値の下の補足（13 / textSecondary）。例: 「目標まで 2.6 kg」
  final String? caption;

  final FcNumSize size;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.supplement(context)),
          const SizedBox(height: AppSpacing.xs),
          FcNum(value: value, unit: unit, size: size),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(caption!, style: AppTextStyles.supplement(context)),
          ],
        ],
      ),
    );
  }
}
