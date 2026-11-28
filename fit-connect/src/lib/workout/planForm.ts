/**
 * ワークアウトプラン（テンプレート）の作成・編集フォームのロジック（純関数）。
 * PlanFormModal から分離してユニットテスト可能にしている。
 */

import { z } from 'zod'

/**
 * 数値欄の値を number | undefined にそろえる（react-hook-form の setValueAs 用）。
 *
 * RHF は setValueAs を、入力欄（DOM）の文字列にも、defaultValues / reset で渡した number にも呼ぶので、
 * 両方を受ける。空欄（'' や空白だけ）と数として読めない値は undefined（未入力）にする。
 * valueAsNumber は空欄を NaN にし、z.number() は NaN を通さないため、任意の欄を空のまま保存できなかった。
 */
export function toOptionalNumber(value: unknown): number | undefined {
  if (typeof value === 'number') {
    return Number.isNaN(value) ? undefined : value
  }
  if (typeof value !== 'string' || value.trim() === '') {
    return undefined
  }
  const parsed = Number(value)
  return Number.isNaN(parsed) ? undefined : parsed
}

const INTEGER_MESSAGE = '整数で入力してください'

// 回数・推定時間（DB は integer）。空（undefined）は通す
const optionalInteger = z.number().int(INTEGER_MESSAGE).optional()

const exerciseFormSchema = z.object({
  name: z.string().min(1, '種目名は必須です'),
  sets: z
    // 空欄は toOptionalNumber で undefined になる（valueAsNumber なら NaN）。どちらも未入力として扱う
    .number({
      required_error: 'セット数を入力してください',
      invalid_type_error: 'セット数を入力してください',
    })
    .int(INTEGER_MESSAGE)
    .min(1, 'セット数は1以上'),
  reps: optionalInteger,
  // 重量（DB は numeric）は小数も可
  weight: z.number().optional(),
  memo: z.string().optional(),
})

export const planFormSchema = z.object({
  title: z.string().min(1, 'タイトルは必須です'),
  description: z.string().optional(),
  category: z.string().optional(),
  planType: z.enum(['session', 'self_guided']),
  estimatedMinutes: optionalInteger,
  exercises: z.array(exerciseFormSchema).min(1, '種目を1つ以上追加してください'),
})

export type PlanFormValues = z.infer<typeof planFormSchema>

/** POST /api/workout-plans・PUT /api/workout-plans/[id] の本文 */
export type PlanRequestBody = {
  title: string
  description: string | null
  category?: string
  planType: PlanFormValues['planType']
  estimatedMinutes: number | null
  exercises: {
    name: string
    sets: number
    reps: number | null
    weight: number | null
    memo?: string
    orderIndex: number
  }[]
}

/**
 * フォームの値から API の本文を組み立てる。
 *
 * 空の任意欄は null にする。PUT は undefined の項目（JSON から消えるキー）の列を更新しないので、
 * 編集で説明や推定時間を消したときは null を送らないと前の値が残る。
 */
export function buildPlanPayload(values: PlanFormValues): PlanRequestBody {
  return {
    title: values.title,
    description: values.description?.trim() ? values.description : null,
    category: values.category,
    planType: values.planType,
    estimatedMinutes: values.estimatedMinutes ?? null,
    exercises: values.exercises.map((ex, index) => ({
      name: ex.name,
      sets: ex.sets,
      reps: ex.reps ?? null,
      weight: ex.weight ?? null,
      memo: ex.memo,
      orderIndex: index,
    })),
  }
}
