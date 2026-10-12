import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/full_screen_image_viewer.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';
import 'meal_type.dart';
import 'record_date_format.dart';

/// 食事の記録 1 件のカード。正本は `record-screens.js` の `MealCard`。
///
/// - 写真があるときは上に写真 176（角丸 0・カード上端でクリップ）。読込中・読込失敗のときだけ
///   [FcPhotoPlaceholder]。**写真が 1 枚も無い記録は写真欄を出さない**（文字だけのカード）
/// - 文字の部分は余白 上 14・左右 20・下 18（写真の有無で変えない）: 見出し（utensils + 区分、右に日時「9月13日（日）12:30」）、メモ（16）、
///   栄養の行（13・textSecondary・tabular）
/// - **AI が推定した値は「推定」と明記**する（`estimatedByAi`）。栄養の値が 1 つも無ければ行ごと出さない
/// - 写真は押すと全画面で見られる。複数枚は横にめくれる（下に点）
/// - 区分の色分け・絵文字・写真の枚数バッジはやめ、アイコンと言葉で示す
class MealCard extends StatefulWidget {
  final MealRecord record;

  const MealCard({super.key, required this.record});

  /// 写真の高さ（正本 `Photo height={176}`）
  static const double photoHeight = 176;

  @override
  State<MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<MealCard> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final memo = record.notes?.trim();
    final estimate = mealEstimateLabel(record);
    final photo = _buildPhoto(context);

    return FcCard(
      padding: FcCardPadding.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (photo != null) photo,
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FcCardHead(
                  icon: LucideIcons.utensils,
                  label: mealTypeLabel(record.mealType),
                  note: recordDateTimeLabel(record.recordedAt),
                  bottomSpacing: 4,
                ),
                if (memo != null && memo.isNotEmpty)
                  Text(
                    memo,
                    style: AppTextStyles.body(context).copyWith(height: 1.6),
                  ),
                if (estimate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      estimate,
                      style: AppTextStyles.supplement(context).copyWith(
                        fontFeatures: AppTextStyles.tabularFigures,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 写真の欄。写真が 1 枚も無いときは null（欄ごと出さない）
  Widget? _buildPhoto(BuildContext context) {
    final images = widget.record.images;
    if (images == null || images.isEmpty) return null;

    Widget photoAt(int index) {
      return FcPressable(
        onTap: () => FullScreenImageViewer.show(
          context: context,
          values: images,
          bucket: StorageBuckets.messagePhotos,
          initialIndex: index,
        ),
        semanticLabel: images.length > 1
            ? '食事の写真 ${index + 1} / ${images.length}、拡大して見る'
            : '食事の写真、拡大して見る',
        child: StorageImage(
          value: images[index],
          bucket: StorageBuckets.messagePhotos,
          width: double.infinity,
          height: MealCard.photoHeight,
          fit: BoxFit.cover,
          placeholder: const FcPhotoPlaceholder(
            height: MealCard.photoHeight,
            radius: 0,
            label: '写真を読み込み中',
          ),
          errorWidget: const FcPhotoPlaceholder(
            height: MealCard.photoHeight,
            radius: 0,
            label: '写真を表示できません',
          ),
        ),
      );
    }

    if (images.length == 1) {
      return SizedBox(height: MealCard.photoHeight, child: photoAt(0));
    }

    return SizedBox(
      height: MealCard.photoHeight,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: images.length,
            onPageChanged: (index) =>
                setState(() => _currentImageIndex = index),
            itemBuilder: (context, index) => photoAt(index),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 写真の上に重ねる点なので、テーマ色ではなく白（現在の写真だけ不透明）
                        color: i == _currentImageIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 栄養の行。例:「推定 640 kcal · たんぱく質 38 g · 脂質 18 g · 炭水化物 82 g」
///
/// - 値がある項目だけを「 · 」でつなぐ。1 つも無ければ null（行ごと出さない）
/// - AI が推定した値（`estimatedByAi`）のときだけ先頭に「推定」を付ける。
///   手で入力した値に「推定」とは書かない
String? mealEstimateLabel(MealRecord record) {
  final number = NumberFormat('#,###');
  final parts = <String>[
    if (record.calories != null)
      '${number.format(record.calories!.round())} kcal',
    if (record.proteinG != null)
      'たんぱく質 ${number.format(record.proteinG!.round())} g',
    if (record.fatG != null) '脂質 ${number.format(record.fatG!.round())} g',
    if (record.carbsG != null)
      '炭水化物 ${number.format(record.carbsG!.round())} g',
  ];
  if (parts.isEmpty) return null;
  final line = parts.join(' · ');
  return record.estimatedByAi ? '推定 $line' : line;
}

// ============================================
// Previews
// ============================================

Widget _previewApp(Brightness brightness, double textScale, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
}

@Preview(name: 'MealCard - 推定あり（写真なし = 文字だけ）')
Widget previewMealCardEstimated() =>
    _previewApp(Brightness.light, 1, MealCard(record: _mockLunch));

@Preview(name: 'MealCard - 推定なし・メモだけ')
Widget previewMealCardMemoOnly() =>
    _previewApp(Brightness.light, 1, MealCard(record: _mockBreakfast));

@Preview(name: 'MealCard - ダーク')
Widget previewMealCardDark() =>
    _previewApp(Brightness.dark, 1, MealCard(record: _mockLunch));

@Preview(name: 'MealCard - 文字拡大 1.35')
Widget previewMealCardLargeText() =>
    _previewApp(Brightness.light, 1.35, MealCard(record: _mockLunch));

// Mock data for previews
final _mockBreakfast = MealRecord(
  id: '1',
  clientId: 'client-1',
  mealType: 'breakfast',
  notes: 'ごはん・卵・ヨーグルト',
  images: null,
  calories: null,
  recordedAt: DateTime.now(),
  source: 'message',
  messageId: 'msg-0',
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

final _mockLunch = MealRecord(
  id: '2',
  clientId: 'client-1',
  mealType: 'lunch',
  notes: '鶏むね肉のグリル定食',
  images: null,
  calories: 640,
  proteinG: 38,
  fatG: 18,
  carbsG: 82,
  estimatedByAi: true,
  recordedAt: DateTime.now(),
  source: 'message',
  messageId: 'msg-1',
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);
