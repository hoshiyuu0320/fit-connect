import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_spacing.dart';

/// 押した瞬間に `scale(0.98)` へ縮むタップ領域（120ms ease）。
///
/// - 「動きを減らす」設定（`MediaQuery.disableAnimations`）のときは縮まない
/// - [minSize] を指定すると、見た目が小さくても **タッチ領域をその大きさまで広げる**
///   （アイコンだけのボタンなどは `Size.square(AppSizes.minTouch)` を渡す）
/// - [semanticLabel] を渡すと、中身の `Semantics` を置き換えてそのラベルを読み上げる。
///   渡さなければ中身の文字（`Text`）がそのまま読み上げ対象になる
class FcPressable extends StatefulWidget {
  const FcPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.minSize = Size.zero,
    this.semanticLabel,
    this.selected,
    this.isButton = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final Size minSize;
  final String? semanticLabel;

  /// 選択状態をスクリーンリーダーへ伝える（タブ・セグメントなど）。null なら伝えない
  final bool? selected;

  /// ボタンとして読み上げるか（false なら通常のタップ領域）
  final bool isButton;

  final HitTestBehavior behavior;

  @override
  State<FcPressable> createState() => _FcPressableState();
}

class _FcPressableState extends State<FcPressable> {
  bool _pressed = false;

  bool get _active =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.reduceOf(context);
    final scale = (_pressed && !reduceMotion) ? AppMotion.pressScale : 1.0;

    Widget content = widget.child;
    if (widget.minSize != Size.zero) {
      content = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minSize.width,
          minHeight: widget.minSize.height,
        ),
        child: Align(
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: content,
        ),
      );
    }

    content = AnimatedScale(
      scale: scale,
      duration: reduceMotion ? Duration.zero : AppMotion.press,
      curve: Curves.easeOut,
      child: content,
    );

    // タップの意味付けは下の Semantics（onTap / onLongPress）が持つ。
    // GestureDetector も同じ tap アクションを出すと、親 Semantics と衝突して
    // 「ボタン」と「ラベル」が別ノードに割れるため、ここでは意味付けを出さない
    final gesture = GestureDetector(
      behavior: widget.behavior,
      excludeFromSemantics: true,
      onTapDown: _active ? (_) => _setPressed(true) : null,
      onTapUp: _active ? (_) => _setPressed(false) : null,
      onTapCancel: _active ? () => _setPressed(false) : null,
      onTap: _active ? widget.onTap : null,
      onLongPress: _active ? widget.onLongPress : null,
      child: content,
    );

    return Semantics(
      button: widget.isButton,
      enabled: _active,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      onTap: _active ? widget.onTap : null,
      onLongPress: _active ? widget.onLongPress : null,
      child: gesture,
    );
  }
}
