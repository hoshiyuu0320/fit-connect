export type RecordCardType = 'weight' | 'meal' | 'exercise' | 'achievement'

export interface RecordCardData {
  type: RecordCardType
  label: string
  details: string[]
}

/**
 * content が記録メッセージなら RecordCardData を返す。
 * そうでなければ null を返す。
 *
 * 対応パターン:
 *   #体重 {value}
 *   #食事:{mealType} {description}
 *   #運動:完了 {text}
 *   #運動:{exerciseType} {rest}
 *   本日のワークアウトプラン「{title}」を達成しました！（#なし現行モバイル形式）
 */
export function parseRecordMessage(content: string): RecordCardData | null {
  // --- ワークアウト達成（#なし現行モバイル形式）---
  const workoutAchievementMatch = content.match(/^本日のワークアウトプラン「([^」]+)」を達成しました！$/)
  if (workoutAchievementMatch) {
    return {
      type: 'achievement',
      label: 'ワークアウト達成！',
      details: [`「${workoutAchievementMatch[1]}」を達成しました！`],
    }
  }

  if (!content.startsWith('#')) return null

  // --- 体重 ---
  const weightMatch = content.match(/^#体重\s+(.+)$/)
  if (weightMatch) {
    const value = weightMatch[1].trim()
    return {
      type: 'weight',
      label: '体重記録',
      details: [`${value} kg`],
    }
  }

  // --- 食事 ---
  const mealMatch = content.match(/^#食事:([^\s]+)\s+(.+)$/)
  if (mealMatch) {
    const mealType = mealMatch[1].trim()
    const description = mealMatch[2].trim()
    return {
      type: 'meal',
      label: `食事記録 ─ ${mealType}`,
      details: [description],
    }
  }

  // --- 運動:完了 ---
  const achievementMatch = content.match(/^#運動:完了\s+(.+)$/)
  if (achievementMatch) {
    const text = achievementMatch[1].trim()
    // 「〜」で囲まれたワークアウト名を抽出して整形
    const quotedMatch = text.match(/「([^」]+)」/)
    if (quotedMatch) {
      return {
        type: 'achievement',
        label: 'ワークアウト達成！',
        details: [`「${quotedMatch[1]}」を達成しました！`],
      }
    }
    return {
      type: 'achievement',
      label: 'ワークアウト達成！',
      details: [text],
    }
  }

  // --- 運動:{exerciseType} ---
  const exerciseMatch = content.match(/^#運動:([^\s]+)\s+(.+)$/)
  if (exerciseMatch) {
    const exerciseType = exerciseMatch[1].trim()
    const rest = exerciseMatch[2].trim()

    // rest をパース: "{内容}　{duration}分　{calories}キロカロリー" のような形式
    // 数字+分 と 数字+キロカロリー を抽出し、それ以外を内容とする
    const durationMatch = rest.match(/(\d+)\s*分/)
    const caloriesMatch = rest.match(/(\d+)\s*(?:キロカロリー|kcal|cal)/i)

    // 内容部分: duration/calories のパターンを除いた文字列
    const bodyText = rest
      .replace(/\d+\s*分/, '')
      .replace(/\d+\s*(?:キロカロリー|kcal|cal)/gi, '')
      .replace(/\s{2,}/g, ' ')
      .trim()

    const details: string[] = []
    if (bodyText) {
      details.push(bodyText)
    }

    const metaParts: string[] = []
    if (durationMatch) {
      metaParts.push(`${durationMatch[1]}分`)
    }
    if (caloriesMatch) {
      metaParts.push(`${caloriesMatch[1]}kcal`)
    }
    if (metaParts.length > 0) {
      details.push(metaParts.join(' ・ '))
    }

    return {
      type: 'exercise',
      label: `運動記録 ─ ${exerciseType}`,
      details: details.length > 0 ? details : [rest],
    }
  }

  // # で始まるが既知のパターンに当てはまらない場合は null
  return null
}
