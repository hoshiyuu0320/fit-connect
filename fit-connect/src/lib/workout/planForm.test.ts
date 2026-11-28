import { describe, it, expect } from 'vitest'
import { z } from 'zod'
import {
  buildPlanPayload,
  planFormSchema,
  toOptionalNumber,
  type PlanFormValues,
} from '@/lib/workout/planForm'

// 数値欄を空のままにした新規作成フォームの値（toOptionalNumber を通した後）
function emptyNumberValues(): PlanFormValues {
  return {
    title: '胸・三頭筋',
    description: '',
    category: 'chest',
    planType: 'session',
    estimatedMinutes: undefined,
    exercises: [{ name: 'ベンチプレス', sets: 3, reps: undefined, weight: undefined, memo: '' }],
  }
}

// 種目の1件目だけを差し替える（schema に型の外の値も渡せるよう unknown のまま）
function withExercise(patch: Record<string, unknown>): unknown {
  const values = emptyNumberValues()
  return { ...values, exercises: [{ ...values.exercises[0], ...patch }] }
}

// RHF の resolver と同じく、その欄の最初のエラーの文言を返す
function firstMessage(values: unknown, path: string): string | undefined {
  const result = planFormSchema.safeParse(values)
  if (result.success) return undefined
  return result.error.issues.find((issue) => issue.path.join('.') === path)?.message
}

describe('toOptionalNumber', () => {
  it.each([
    ['空文字', ''],
    ['空白だけ', '   '],
    ['null', null],
    ['undefined', undefined],
    ['NaN', Number.NaN],
  ])('%s は undefined（未入力）', (_label, input) => {
    expect(toOptionalNumber(input)).toBeUndefined()
  })

  it('入力欄の数字の文字列は number にする', () => {
    expect(toOptionalNumber('10')).toBe(10)
    expect(toOptionalNumber('62.5')).toBe(62.5)
    expect(toOptionalNumber('-3')).toBe(-3)
    // 0 は空ではない
    expect(toOptionalNumber('0')).toBe(0)
  })

  it('defaultValues / reset の number はそのまま', () => {
    expect(toOptionalNumber(3)).toBe(3)
    expect(toOptionalNumber(62.5)).toBe(62.5)
    expect(toOptionalNumber(0)).toBe(0)
  })

  it('数として読めない文字列は undefined', () => {
    expect(toOptionalNumber('abc')).toBeUndefined()
  })
})

describe('planFormSchema', () => {
  it('任意の数値欄（推定時間・回数・重量）が空でも通る', () => {
    expect(planFormSchema.safeParse(emptyNumberValues()).success).toBe(true)
  })

  it('数値欄に値があれば通る（重量の小数も可）', () => {
    const result = planFormSchema.safeParse({
      ...emptyNumberValues(),
      estimatedMinutes: 45,
      exercises: [{ name: 'ベンチプレス', sets: 3, reps: 10, weight: 62.5, memo: '' }],
    })
    expect(result.success).toBe(true)
  })

  it('セット数が空なら「セット数を入力してください」', () => {
    expect(firstMessage(withExercise({ sets: undefined }), 'exercises.0.sets')).toBe(
      'セット数を入力してください'
    )
    // valueAsNumber の空欄（NaN）も未入力として扱う
    expect(firstMessage(withExercise({ sets: Number.NaN }), 'exercises.0.sets')).toBe(
      'セット数を入力してください'
    )
  })

  it('セット数が小数なら「整数で入力してください」', () => {
    expect(firstMessage(withExercise({ sets: 2.5 }), 'exercises.0.sets')).toBe(
      '整数で入力してください'
    )
  })

  it('セット数が 0 なら「セット数は1以上」', () => {
    expect(firstMessage(withExercise({ sets: 0 }), 'exercises.0.sets')).toBe('セット数は1以上')
  })

  it('回数・推定時間が小数なら「整数で入力してください」', () => {
    expect(firstMessage(withExercise({ reps: 10.5 }), 'exercises.0.reps')).toBe(
      '整数で入力してください'
    )
    expect(
      firstMessage({ ...emptyNumberValues(), estimatedMinutes: 30.5 }, 'estimatedMinutes')
    ).toBe('整数で入力してください')
  })
})

describe('buildPlanPayload', () => {
  it('空の推定時間・説明・回数・重量は null にする（PUT で列を消せるように）', () => {
    expect(buildPlanPayload(emptyNumberValues())).toEqual({
      title: '胸・三頭筋',
      description: null,
      category: 'chest',
      planType: 'session',
      estimatedMinutes: null,
      exercises: [
        { name: 'ベンチプレス', sets: 3, reps: null, weight: null, memo: '', orderIndex: 0 },
      ],
    })
  })

  it('空白だけの説明も null にする', () => {
    expect(buildPlanPayload({ ...emptyNumberValues(), description: '   ' }).description).toBeNull()
  })

  it('値があればそのまま送る（説明は入力のまま、0 は null にしない）', () => {
    const payload = buildPlanPayload({
      title: '脚の日',
      description: ' フォーム重視 ',
      category: 'legs',
      planType: 'self_guided',
      estimatedMinutes: 45,
      exercises: [{ name: 'スクワット', sets: 5, reps: 0, weight: 62.5, memo: '深くしゃがむ' }],
    })
    expect(payload).toEqual({
      title: '脚の日',
      description: ' フォーム重視 ',
      category: 'legs',
      planType: 'self_guided',
      estimatedMinutes: 45,
      exercises: [
        { name: 'スクワット', sets: 5, reps: 0, weight: 62.5, memo: '深くしゃがむ', orderIndex: 0 },
      ],
    })
  })

  it('orderIndex は種目の並び順', () => {
    const payload = buildPlanPayload({
      ...emptyNumberValues(),
      exercises: [
        { name: 'ベンチプレス', sets: 3 },
        { name: 'ダンベルフライ', sets: 3, reps: 12 },
        { name: 'ディップス', sets: 2 },
      ],
    })
    expect(payload.exercises.map((ex) => [ex.name, ex.orderIndex])).toEqual([
      ['ベンチプレス', 0],
      ['ダンベルフライ', 1],
      ['ディップス', 2],
    ])
  })
})

describe('修正前の再現（負の対照）', () => {
  // 修正前の PlanFormModal: 数値欄は register の valueAsNumber、schema は z.number().optional()
  const legacyExerciseSchema = z.object({
    name: z.string().min(1, '種目名は必須です'),
    sets: z.number().min(1, 'セット数は1以上'),
    reps: z.number().optional(),
    weight: z.number().optional(),
    memo: z.string().optional(),
  })
  const legacyFormSchema = z.object({
    title: z.string().min(1, 'タイトルは必須です'),
    description: z.string().optional(),
    category: z.string().optional(),
    planType: z.enum(['session', 'self_guided']),
    estimatedMinutes: z.number().optional(),
    exercises: z.array(legacyExerciseSchema).min(1, '種目を1つ以上追加してください'),
  })
  // RHF の valueAsNumber が入力欄の文字列を変換する規則（空欄は NaN）
  const legacyValueAsNumber = (value: string) => (value === '' ? Number.NaN : Number(value))

  it('空欄を NaN にする変換と z.number().optional() では、空のままの任意欄で検証が落ちる', () => {
    const result = legacyFormSchema.safeParse({
      ...emptyNumberValues(),
      estimatedMinutes: legacyValueAsNumber(''),
      exercises: [
        {
          name: 'ベンチプレス',
          sets: 3,
          reps: legacyValueAsNumber(''),
          weight: legacyValueAsNumber(''),
          memo: '',
        },
      ],
    })

    expect(result.success).toBe(false)
    // 落ちたのは空の数値欄だけで、修正前の画面はこの3つの欄のエラーを出していなかった
    expect(result.error?.issues.map((issue) => issue.path.join('.')).sort()).toEqual([
      'estimatedMinutes',
      'exercises.0.reps',
      'exercises.0.weight',
    ])
  })

  it('同じ空欄でも、今の変換と schema なら通る', () => {
    const result = planFormSchema.safeParse({
      ...emptyNumberValues(),
      estimatedMinutes: toOptionalNumber(''),
      exercises: [
        {
          name: 'ベンチプレス',
          sets: toOptionalNumber(3),
          reps: toOptionalNumber(''),
          weight: toOptionalNumber(''),
          memo: '',
        },
      ],
    })
    expect(result.success).toBe(true)
  })
})
