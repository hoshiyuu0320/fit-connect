import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_card.dart';
import 'fc_marks.dart';
import 'fc_pressable.dart';
import 'fc_separator.dart';
import 'fc_skeleton.dart';

// ============================================
// 行・行を並べるカード・統計リスト
// 正本: more-screens.js の `Row` / `RowsCard`、home-screens.js の `SumRow`、
//       record-screens.js の `ListCard`、components の `StatList`
// ============================================

/// 行の高さ・縦余白の組み合わせ（画面ごとに数値を変えないための型）
enum FcRowDensity {
  /// 設定・一覧の標準行（最小高さ 54・縦余白 10）。`more-screens.js` の `Row`
  standard(54, 10),

  /// ホーム「今日のまとめ」の行（最小高さ 56・縦余白 13）。`home-screens.js` の `SumRow`
  summary(56, 13),

  /// 記録の履歴行（最小高さ 52・縦余白 12）。`record-screens.js` の `ListCard` の行
  record(52, 12);

  const FcRowDensity(this.minHeight, this.verticalPadding);

  final double minHeight;
  final double verticalPadding;
}

/// 数値＋単位の 1 組（例: `FcValuePart('7', '時間')`）
class FcValuePart {
  const FcValuePart(this.value, [this.unit]);

  final String value;
  final String? unit;
}

enum _FcRowValueKind { metric, text, missing, action, loading }

/// [FcListRow.trailing] に置く「右側の値」の定型。
///
/// - [FcRowValue.metric]: 数値 20 / 500（tabular・字間 -0.4）＋ 単位 13。ホームの今日のまとめ
/// - [FcRowValue.text]: 16 / 500 の文字列（tabular）。記録の履歴の値。[muted] で無効色
/// - [FcRowValue.missing]: 「未記録」（15 / textSecondary）。0 と区別するために 0 を出さない
/// - [FcRowValue.action]: accent の操作文字（15 / 500）。「目覚めを記録」など
/// - [FcRowValue.loading]: 読み込み中の帯（64×18）
///
/// 横幅が足りなければ折り返す（縮めない）。
class FcRowValue extends StatelessWidget {
  /// 数値＋単位（ホームの今日のまとめ）。複数の組は `7 時間 30 分` のように並ぶ
  const FcRowValue.metric(List<FcValuePart> parts, {super.key})
      : _kind = _FcRowValueKind.metric,
        _parts = parts,
        _text = null,
        _muted = false;

  /// 16 / 500 の文字列
  const FcRowValue.text(String text, {super.key, bool muted = false})
      : _kind = _FcRowValueKind.text,
        _parts = const [],
        _text = text,
        _muted = muted;

  /// 値が無い（既定は「未記録」）
  const FcRowValue.missing({super.key, String text = '未記録'})
      : _kind = _FcRowValueKind.missing,
        _parts = const [],
        _text = text,
        _muted = true;

  /// 青緑の操作文字（行全体を `onTap` で押せるようにして使う）
  const FcRowValue.action(String text, {super.key})
      : _kind = _FcRowValueKind.action,
        _parts = const [],
        _text = text,
        _muted = false;

  /// 読み込み中（スケルトン）。値の読み上げは「読み込み中」
  const FcRowValue.loading({super.key})
      : _kind = _FcRowValueKind.loading,
        _parts = const [],
        _text = null,
        _muted = false;

  final _FcRowValueKind _kind;
  final List<FcValuePart> _parts;
  final String? _text;
  final bool _muted;

  /// 読み上げ用の文字（例: `7時間30分` `未記録` `読み込み中`）
  String get semanticText {
    switch (_kind) {
      case _FcRowValueKind.metric:
        return _parts.map((p) => '${p.value}${p.unit ?? ''}').join();
      case _FcRowValueKind.text:
      case _FcRowValueKind.missing:
      case _FcRowValueKind.action:
        return _text!;
      case _FcRowValueKind.loading:
        return '読み込み中';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    switch (_kind) {
      case _FcRowValueKind.metric:
        final numStyle = AppTextStyles.numHome(context).copyWith(
          fontSize: 20,
          letterSpacing: -0.4,
          height: 1.3,
        );
        final unitStyle = AppTextStyles.numUnit(context);
        final spans = <InlineSpan>[];
        for (var i = 0; i < _parts.length; i++) {
          final part = _parts[i];
          spans.add(TextSpan(text: part.value, style: numStyle));
          if (part.unit != null) {
            spans.add(const WidgetSpan(child: SizedBox(width: 2)));
            spans.add(TextSpan(text: part.unit, style: unitStyle));
            if (i != _parts.length - 1) {
              spans.add(const WidgetSpan(child: SizedBox(width: 2)));
            }
          }
        }
        return Text.rich(TextSpan(children: spans), textAlign: TextAlign.end);
      case _FcRowValueKind.text:
        return Text(
          _text!,
          textAlign: TextAlign.end,
          style: AppTextStyles.bodyNumber(context).copyWith(
            fontWeight: FontWeight.w500,
            color: _muted ? colors.textSecondary : colors.textPrimary,
          ),
        );
      case _FcRowValueKind.missing:
        return Text(
          _text!,
          textAlign: TextAlign.end,
          style: AppTextStyles.actionLabel(context).copyWith(
            fontWeight: FontWeight.w400,
            color: colors.textSecondary,
          ),
        );
      case _FcRowValueKind.action:
        return Text(
          _text!,
          textAlign: TextAlign.end,
          style:
              AppTextStyles.actionLabel(context).copyWith(color: colors.accent),
        );
      case _FcRowValueKind.loading:
        return Semantics(
          label: '読み込み中',
          child: const FcSkeleton(width: 64, height: 18, radius: 6),
        );
    }
  }
}

/// 1 行（アイコン ＋ タイトル ＋ 補足 ＋ 右側 ＋ 末尾アイコン）。[FcRowsCard] の中に並べて使う。
///
/// - 左: [icon]（18 / accent。[color] を渡すとタイトルと同じ色）または任意の [leading]
/// - 中: [title]（16・行高 1.5）＋ [caption]（12 / textSecondary）。折り返す
/// - 右: [trailing]（[FcRowValue] か任意の Widget。幅は画面の半分まで）
/// - 末尾: 右向き chevron（16 / textSecondary）、[externalLink] なら外部リンク。
///   [chevron] が null のときは **onTap があれば表示**（`chevron: false` で消せる）
/// - 最小高さと縦余白は [density]（標準 54/10、まとめ 56/13、記録 52/12）
/// - [onTap] があれば行全体が押せる（押下で scale 0.98）。読み上げは「タイトル 補足 値」を 1 つにまとめる
/// - 文字拡大では縮めずに折り返して縦に伸びる
///
/// 例: `FcListRow(icon: LucideIcons.utensils, title: '食事', caption: '朝食・昼食を記録',
///   trailing: FcRowValue.metric([FcValuePart('2', '回')]), onTap: open)`
class FcListRow extends StatelessWidget {
  const FcListRow({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.caption,
    this.trailing,
    this.color,
    this.chevron,
    this.externalLink = false,
    this.onTap,
    this.density = FcRowDensity.standard,
    this.semanticLabel,
  })  : toggleValue = null,
        onToggle = null;

  /// 右端にトグルを置いた行。行のどこを押しても切り替わる。
  /// 読み上げは「タイトル 補足、オン/オフ」（`onChanged: null` で無効）
  const FcListRow.toggle({
    super.key,
    required this.title,
    required bool value,
    required ValueChanged<bool>? onChanged,
    this.icon,
    this.leading,
    this.caption,
    this.color,
    this.density = FcRowDensity.standard,
    this.semanticLabel,
  })  : toggleValue = value,
        onToggle = onChanged,
        trailing = null,
        chevron = false,
        externalLink = false,
        onTap = null;

  final String title;

  /// 左のアイコン（18）。色は accent、[color] を渡せばその色
  final IconData? icon;

  /// アイコンの代わりに置く任意の左側（日付の列・[FcDoneMark] など）。[icon] より優先
  final Widget? leading;

  /// タイトルの下の補足（caption）
  final String? caption;

  /// 右側の値・操作。[FcRowValue] を使うと定型の見た目になる
  final Widget? trailing;

  /// タイトルとアイコンの色。null ならタイトルは textPrimary・アイコンは accent
  /// （「アカウントを削除」のように error 色にしたいときに渡す）
  final Color? color;

  /// 右端の chevron を出すか。null なら [onTap] があるときだけ出す
  final bool? chevron;

  /// 末尾を外部リンクのアイコンにする（chevron は出ない）
  final bool externalLink;

  final VoidCallback? onTap;
  final FcRowDensity density;

  /// 読み上げの上書き（null ならタイトル・補足・値から作る）
  final String? semanticLabel;

  /// [FcListRow.toggle] のときだけ非 null
  final bool? toggleValue;
  final ValueChanged<bool>? onToggle;

  /// タイトル・補足・右側の値（[FcRowValue] か `Text`）をつなげた読み上げ
  String _composedLabel() {
    final right = trailing;
    return [
      title,
      if (caption != null) caption!,
      if (right is FcRowValue) right.semanticText,
      if (right is Text && right.data != null) right.data!,
    ].join('、');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isToggle = toggleValue != null;
    final tappable = onTap != null;
    final showChevron = !externalLink && (chevron ?? tappable);

    final leadingWidget = leading ??
        (icon == null
            ? null
            : ExcludeSemantics(
                child: Icon(icon, size: 18, color: color ?? colors.accent),
              ));

    final tailIcon = externalLink
        ? LucideIcons.externalLink
        : (showChevron ? LucideIcons.chevronRight : null);

    final trailingMaxWidth = MediaQuery.sizeOf(context).width * 0.5;

    Widget? right;
    if (isToggle) {
      right = ExcludeSemantics(
        child: FcToggle(
          value: toggleValue!,
          onChanged: onToggle,
          semanticLabel: title,
        ),
      );
    } else if (trailing != null) {
      right = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: trailingMaxWidth),
        child: trailing,
      );
    }

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: density.minHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: density.verticalPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leadingWidget != null) ...[
              leadingWidget,
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body(context)
                        .copyWith(color: color ?? colors.textPrimary),
                  ),
                  if (caption != null)
                    Text(caption!, style: AppTextStyles.caption(context)),
                ],
              ),
            ),
            if (right != null) ...[
              const SizedBox(width: AppSpacing.md),
              right,
            ],
            if (tailIcon != null) ...[
              const SizedBox(width: AppSpacing.md),
              ExcludeSemantics(
                child: Icon(tailIcon, size: 16, color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );

    if (isToggle) {
      final enabled = onToggle != null;
      final label =
          semanticLabel ?? (caption == null ? title : '$title、$caption');
      return Semantics(
        container: true,
        label: label,
        toggled: toggleValue,
        enabled: enabled,
        excludeSemantics: true,
        onTap: enabled ? () => onToggle!(!toggleValue!) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onToggle!(!toggleValue!) : null,
          child: content,
        ),
      );
    }

    if (tappable) {
      // ラベルを明示して 1 つの「ボタン + ラベル」ノードにする
      // （FcPressable は semanticLabel なしだと button とラベルが別ノードに割れる）
      return FcPressable(
        onTap: onTap,
        semanticLabel: semanticLabel ?? _composedLabel(),
        minSize: const Size(0, AppSizes.minTouch),
        child: content,
      );
    }

    if (semanticLabel != null) {
      return Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: content,
      );
    }
    // 右側が操作（ボタンなど）かもしれないときは、読み上げをまとめない
    if (trailing == null || trailing is FcRowValue) {
      return MergeSemantics(child: content);
    }
    return content;
  }
}

/// 行を並べるカード。**行と行の間だけ**に区切り線を引く（先頭の上・最後の下には引かない）。
///
/// - 角丸 23・不透明の [FcCard]。余白は [padding]（既定は上下 2・左右 20）
/// - ホームの「今日のまとめ」のように見出しを持つカードは [title]（16 / 500）か [header] を渡し、
///   [padding] に [FcRowsCard.summaryPadding]（上 16・下 4）を使う。見出しと最初の行の間に線は引かない
/// - [children] は [FcListRow] など。区切り線は自動で挟むので、行側で線を描かない
///
/// 例: `FcRowsCard(children: [FcListRow(title: '利用規約', externalLink: true, onTap: open), ...])`
class FcRowsCard extends StatelessWidget {
  const FcRowsCard({
    super.key,
    required this.children,
    this.title,
    this.header,
    this.padding = defaultPadding,
    this.headerEndBleed = 0,
    this.semanticLabel,
  });

  /// 既定の余白（上下 2・左右 20）
  static const EdgeInsets defaultPadding =
      EdgeInsets.symmetric(vertical: 2, horizontal: AppSpacing.cardPadding);

  /// 見出し付きカードの余白（上 16・下 4・左右 20）。ホームの今日のまとめ
  static const EdgeInsets summaryPadding = EdgeInsets.fromLTRB(
    AppSpacing.cardPadding,
    AppSpacing.lg,
    AppSpacing.cardPadding,
    AppSpacing.xs,
  );

  final List<Widget> children;

  /// カードの見出し（16 / 500）。下に 2 の余白を含む
  final String? title;

  /// 見出しを自由に組みたいとき（[title] より優先）。件数や閉じるボタンを右に置くなど
  final Widget? header;

  final EdgeInsetsGeometry padding;

  /// 見出し（[header]）の右端を、カードの右余白へ食い込ませる量。
  /// 見出しの右に [FcCloseButton] を置くとき `FcCloseButton.endBleed`（12）を渡すと、
  /// 「×」の字が行の右端に揃う（行と区切り線の右端は変わらない。「×」の押せる範囲も欠けない）
  final double headerEndBleed;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget? head = header;
    if (head == null && title != null) {
      head = Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Semantics(
          header: true,
          child: Text(
            title!,
            style: AppTextStyles.body(context)
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    var cardPadding = padding;
    var bleed = 0.0;
    if (headerEndBleed > 0) {
      final resolved = padding.resolve(Directionality.of(context));
      bleed = headerEndBleed.clamp(0.0, resolved.right).toDouble();
      cardPadding = resolved.copyWith(right: resolved.right - bleed);
    }

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const FcSeparator(),
          children[i],
        ],
      ],
    );

    return FcCard(
      paddingOverride: cardPadding,
      semanticLabel: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (head != null) head,
          if (bleed > 0)
            Padding(padding: EdgeInsets.only(right: bleed), child: rows)
          else
            rows,
        ],
      ),
    );
  }
}

/// [FcStatList] の 1 項目
class FcStatItem {
  const FcStatItem({
    required this.label,
    this.value,
    this.icon,
    this.description,
  });

  final String label;

  /// 右の値（単位込みの文字列。例: `95 g` `3回`）。null は「未記録」
  final String? value;

  /// 左のアイコン（17 / accent）
  final IconData? icon;

  /// ラベルの下の説明（12 / textSecondary）
  final String? description;
}

/// 項目と値の一覧（`StatList.jsx`）。PFC バランスや運動の内訳など。
///
/// - 行: 縦余白 14・下に区切り線（**最後の行は線なし**）
/// - 左: [FcStatItem.icon]（17 / accent）、[FcStatItem.label]（16）、説明（caption・上 3）
/// - 右: 値 17 / 500（tabular）。null は「未記録」（textSecondary）
/// - カードの余白・見出しは画面側（`FcCard` ＋ `FcCardHead`）。文字拡大では折り返して縦に伸びる
///
/// 例: `FcStatList(items: [FcStatItem(label: 'たんぱく質', description: '記録した10日の平均', value: '95 g')])`
class FcStatList extends StatelessWidget {
  const FcStatList({super.key, required this.items});

  final List<FcStatItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const FcSeparator(),
          _FcStatRow(item: items[i]),
        ],
      ],
    );
  }
}

class _FcStatRow extends StatelessWidget {
  const _FcStatRow({required this.item});

  final FcStatItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final missing = item.value == null;
    final valueMaxWidth = MediaQuery.sizeOf(context).width * 0.5;

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (item.icon != null) ...[
              ExcludeSemantics(
                child: Icon(item.icon, size: 17, color: colors.accent),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.label, style: AppTextStyles.body(context)),
                  if (item.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.description!,
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: valueMaxWidth),
              child: Text(
                item.value ?? '未記録',
                textAlign: TextAlign.end,
                style: AppTextStyles.exerciseName(context).copyWith(
                  fontFeatures: AppTextStyles.tabularFigures,
                  color: missing ? colors.textSecondary : colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
