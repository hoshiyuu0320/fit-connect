/// メッセージ本文から記録タグ（#付き正準形）を抽出する。
/// 記録メッセージでなければ null を返す。
///
/// 正準形（#付き・1要素）:
///   '#食事:昼食 サラダ' → ['#食事:昼食']
///   '#食事 朝食'        → ['#食事:朝食']
///   '#体重 62.4kg'      → ['#体重']
///   '#運動 筋トレ'      → ['#運動:筋トレ']
///   '#運動 ランニング'  → ['#運動:ランニング']
///   '#運動:完了 脚の日' → ['#運動:完了']
List<String>? parseMessageTags(String text) {
  if (text.contains('#食事') || text.contains('#meal')) {
    if (text.contains('朝食') || text.contains('breakfast')) return ['#食事:朝食'];
    if (text.contains('昼食') || text.contains('lunch')) return ['#食事:昼食'];
    if (text.contains('夕食') || text.contains('dinner')) return ['#食事:夕食'];
    if (text.contains('間食') || text.contains('snack')) return ['#食事:間食'];
    return ['#食事'];
  } else if (text.contains('#体重') || text.contains('#weight')) {
    return ['#体重'];
  } else if (text.contains('#運動') || text.contains('#exercise')) {
    if (text.contains('完了')) return ['#運動:完了'];
    if (text.contains('筋トレ')) return ['#運動:筋トレ'];
    if (text.contains('ランニング')) return ['#運動:ランニング'];
    if (text.contains('有酸素')) return ['#運動:有酸素'];
    return ['#運動'];
  }
  return null;
}
