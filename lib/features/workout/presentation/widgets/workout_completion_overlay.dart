import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:confetti/confetti.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// ワークアウト完了時に表示するお祝いオーバーレイ
///
/// Confettiアニメーションとお祝いメッセージを表示する
class WorkoutCompletionOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final String? planTitle;

  const WorkoutCompletionOverlay({
    super.key,
    required this.onDismiss,
    this.planTitle,
  });

  @override
  State<WorkoutCompletionOverlay> createState() =>
      _WorkoutCompletionOverlayState();
}

class _WorkoutCompletionOverlayState extends State<WorkoutCompletionOverlay>
    with TickerProviderStateMixin {
  late ConfettiController _confettiController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Confetti controller
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );

    // Scale animation for the card
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Start animations
    _confettiController.play();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      child: Stack(
        children: [
          // Tap to dismiss
          GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),

          // Confetti from center top
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi / 2, // straight down
              blastDirectionality: BlastDirectionality.explosive,
              maxBlastForce: 20,
              minBlastForce: 5,
              emissionFrequency: 0.03,
              numberOfParticles: 30,
              gravity: 0.1,
              shouldLoop: false,
              colors: [
                AppColors.primary500,
                AppColors.amber100,
                AppColors.rose100,
                AppColors.emerald500,
                AppColors.indigo600,
                AppColors.purple500,
                AppColors.orange500,
              ],
            ),
          ),

          // Celebration card
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.emerald500,
                      AppColors.primary600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.emerald500.withOpacity(0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Zap icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.zap,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'ワークアウト完了！',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Subtitle
                    Text(
                      widget.planTitle ?? '本日のプランを達成しました',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Message
                    Text(
                      'お疲れ様でした！',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.85),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Close button
                    ElevatedButton(
                      onPressed: widget.onDismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.emerald600,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '閉じる',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'WorkoutCompletionOverlay - With Title')
Widget previewWorkoutCompletionOverlayWithTitle() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: WorkoutCompletionOverlay(
        onDismiss: () {},
        planTitle: '上半身トレーニング',
      ),
    ),
  );
}

@Preview(name: 'WorkoutCompletionOverlay - No Title')
Widget previewWorkoutCompletionOverlayNoTitle() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: WorkoutCompletionOverlay(
        onDismiss: () {},
      ),
    ),
  );
}
