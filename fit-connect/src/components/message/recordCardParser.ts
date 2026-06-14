export type RecordCardType = 'weight' | 'meal' | 'exercise' | 'achievement'

export interface RecordCardData {
  type: RecordCardType
  label: string
  details: string[]
}

/**
 * content と tags から記録カード情報を返す。記録でなければ null。
 *
 * 判定方針（基盤フェーズ「tags統一」）:
 *   1. ワークアウト達成（#なしモバイル形式）は content で判定
 *   2. tags が非空なら、それを正準として判定（cardinality(tags) > 0 = 記録）
 *   3. tags が空なら従来の content 先頭タグ判定にフォールバック（後方互換）
 */
export function parseRecordMessage(content: string, tags?: string[] | null): RecordCardData | null {
  // --- ワークアウト達成（#なし現行モバイル形式）---
  const workoutAchievementMatch = content.match(/^本日のワークアウトプラン「([^」]+)」を達成しました！/)
  if (workoutAchievementMatch) {
    const details: string[] = [`「${workoutAchievementMatch[1]}」を達成しました！`]
    const caloriesMatch = content.match(/🔥\s*消費カロリー:\s*(\d+)\s*kcal/)
    if (caloriesMatch) details.push(`🔥 ${caloriesMatch[1]}kcal`)
    const feedbackMatch = content.match(/💬\s*(.+)/)
    if (feedbackMatch) details.push(`💬 ${feedbackMatch[1].trim()}`)
    return { type: 'achievement', label: 'ワークアウト達成！', details }
  }

  // --- tags 優先判定 ---
  if (tags && tags.length > 0) {
    const fromTag = parseFromTag(tags[0], content)
    if (fromTag) return fromTag
  }

  // --- 従来の content ベース判定（tags空・後方互換）---
  if (!content.startsWith('#')) return null
  return parseFromContent(content)
}

/** tag（#付き正準形）から記録カードを構築。本文は content から先頭タグを除いた残り。 */
function parseFromTag(tag: string, content: string): RecordCardData | null {
  const m = tag.match(/^#(体重|食事|運動)(?::(.+))?$/)
  if (!m) return null
  const category = m[1]
  const detail = m[2]?.trim()
  // content がタグで始まればタグを除去、無ければ content 全体が body
  const body = content.replace(/^#(食事|運動|体重)(?::[^\s]+)?\s*/, '').trim()

  if (category === '体重') {
    return { type: 'weight', label: '体重記録', details: body ? [body] : [] }
  }
  if (category === '食事') {
    return {
      type: 'meal',
      label: detail ? `食事記録 ─ ${detail}` : '食事記録',
      details: body ? [body] : [],
    }
  }
  // category === '運動'
  // 意図的な非対称: #運動:完了 は parseFromTag では本文不要（tags が記録の正準）だが、
  // parseFromContent では本文必須（content 単体から達成内容を取り出す必要があるため）
  if (detail === '完了') {
    const quoted = content.match(/「([^」]+)」/)
    return {
      type: 'achievement',
      label: 'ワークアウト達成！',
      details: quoted ? [`「${quoted[1]}」を達成しました！`] : (body ? [body] : []),
    }
  }
  return buildExerciseCard(detail ?? '', body)
}

/** 従来の content 先頭タグ判定（既存ロジックを保持）。 */
function parseFromContent(content: string): RecordCardData | null {
  const weightMatch = content.match(/^#体重\s+(.+)$/)
  if (weightMatch) {
    return { type: 'weight', label: '体重記録', details: [weightMatch[1].trim()] }
  }
  const mealMatch = content.match(/^#食事:([^\s]+)\s+(.+)$/)
  if (mealMatch) {
    return { type: 'meal', label: `食事記録 ─ ${mealMatch[1].trim()}`, details: [mealMatch[2].trim()] }
  }
  const mealOnlyMatch = content.match(/^#食事:([^\s]+)$/)
  if (mealOnlyMatch) {
    return { type: 'meal', label: `食事記録 ─ ${mealOnlyMatch[1].trim()}`, details: [] }
  }
  const achievementMatch = content.match(/^#運動:完了\s+(.+)$/)
  if (achievementMatch) {
    const text = achievementMatch[1].trim()
    const quotedMatch = text.match(/「([^」]+)」/)
    return {
      type: 'achievement',
      label: 'ワークアウト達成！',
      details: quotedMatch ? [`「${quotedMatch[1]}」を達成しました！`] : [text],
    }
  }
  const exerciseMatch = content.match(/^#運動:([^\s]+)\s+(.+)$/)
  if (exerciseMatch) {
    return buildExerciseCard(exerciseMatch[1].trim(), exerciseMatch[2].trim())
  }
  return null
}

/** 運動カードを構築（本文から duration/calories を抽出）。 */
function buildExerciseCard(exerciseType: string, rest: string): RecordCardData {
  const durationMatch = rest.match(/(\d+)\s*分/)
  const caloriesMatch = rest.match(/(\d+)\s*(?:キロカロリー|kcal|cal)/i)
  const bodyText = rest
    .replace(/\d+\s*分/, '')
    .replace(/\d+\s*(?:キロカロリー|kcal|cal)/gi, '')
    .replace(/\s{2,}/g, ' ')
    .trim()
  const details: string[] = []
  if (bodyText) details.push(bodyText)
  const metaParts: string[] = []
  if (durationMatch) metaParts.push(`${durationMatch[1]}分`)
  if (caloriesMatch) metaParts.push(`${caloriesMatch[1]}kcal`)
  if (metaParts.length > 0) details.push(metaParts.join(' ・ '))
  return {
    type: 'exercise',
    label: `運動記録 ─ ${exerciseType}`,
    details: details.length > 0 ? details : [rest],
  }
}
