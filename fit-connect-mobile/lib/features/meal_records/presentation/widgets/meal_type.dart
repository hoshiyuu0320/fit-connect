// 食事の区分（meal_type）の表示名。
//
// 色や絵文字は割り振らず、言葉だけで区別する（正本: 食事のカテゴリ色をやめる）。

/// 「今日の食事」の 4 区分（正本の並び順）
const List<({String type, String label})> mealTypeSlots = [
  (type: 'breakfast', label: '朝食'),
  (type: 'lunch', label: '昼食'),
  (type: 'dinner', label: '夕食'),
  (type: 'snack', label: '間食'),
];

/// 区分の表示名。未知の値はそのまま出さず「食事」にする
String mealTypeLabel(String mealType) {
  for (final slot in mealTypeSlots) {
    if (slot.type == mealType.toLowerCase()) return slot.label;
  }
  return '食事';
}
