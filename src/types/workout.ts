// ================================================
// FIT-CONNECT ワークアウトプラン機能 TypeScript型定義
// ================================================

// ワークアウトテンプレート（トレーナーが作成する種目プラン）
export type WorkoutPlan = {
  id: string
  trainer_id: string
  title: string
  description: string | null
  category: string
  plan_type: 'self_guided' | 'session'
  estimated_minutes: number | null
  created_at: string
  updated_at: string
  // JOIN
  exercises?: WorkoutExercise[]
  exercise_count?: number
}

// テンプレート内の種目
export type WorkoutExercise = {
  id: string
  plan_id: string
  name: string
  sets: number
  reps: number | null
  weight: number | null
  duration_seconds: number | null
  rest_seconds: number | null
  memo: string | null
  order_index: number
  created_at: string
}

// カレンダーへの割り当て（テンプレート → 特定日付）
export type WorkoutAssignment = {
  id: string
  client_id: string
  trainer_id: string
  plan_id: string
  assigned_date: string // "YYYY-MM-DD"
  status: 'pending' | 'partial' | 'completed' | 'skipped'
  trainer_note: string | null
  client_feedback: string | null
  started_at: string | null
  finished_at: string | null
  created_at: string
  session_id: string | null
  updated_at: string
  // JOIN
  plan?: WorkoutPlan
  exercises?: WorkoutAssignmentExercise[]
}

// 割り当てられた種目（セッション実行記録含む）
export type WorkoutAssignmentExercise = {
  id: string
  assignment_id: string
  exercise_name: string
  target_sets: number
  target_reps: number
  target_weight: number | null
  order_index: number
  actual_sets: ActualSet[] | null
  is_completed: boolean
  memo: string | null
  linked_exercise_id: string | null
  created_at: string
}

// 実際のセット記録
export type ActualSet = {
  set_number: number
  weight: number | null
  reps: number | null
  done: boolean
}

// ================================================
// パラメータ型定義
// ================================================

export type CreateWorkoutPlanParams = {
  trainerId: string
  title: string
  description?: string
  category?: string
  planType?: 'self_guided' | 'session'
  estimatedMinutes?: number
  exercises: CreateWorkoutExerciseParams[]
}

export type CreateWorkoutExerciseParams = {
  name: string
  sets: number
  reps?: number
  weight?: number
  durationSeconds?: number
  restSeconds?: number
  memo?: string
  orderIndex: number
}

export type UpdateWorkoutPlanParams = {
  id: string
  title?: string
  description?: string
  category?: string
  planType?: 'self_guided' | 'session'
  estimatedMinutes?: number
  exercises?: CreateWorkoutExerciseParams[]
}

export type CreateAssignmentParams = {
  clientId: string
  trainerId: string
  planId: string
  assignedDate: string
}

export type UpdateAssignmentParams = {
  id: string
  assignedDate?: string
  status?: WorkoutAssignment['status']
  trainerNote?: string
  clientFeedback?: string
  startedAt?: string
  finishedAt?: string
}

export type UpdateAssignmentExerciseParams = {
  id: string
  actualSets?: ActualSet[]
  isCompleted?: boolean
  memo?: string
}

// ================================================
// 定数定義
// ================================================

export const PLAN_TYPE_OPTIONS = {
  session: 'セッション',
  self_guided: '宿題',
} as const

export const PLAN_TYPE_COLORS = {
  session: {
    bg: 'bg-blue-100',
    text: 'text-blue-700',
    label: 'セッション',
    headerBg: 'bg-blue-600',
    borderColor: 'border-blue-200',
    hoverBorder: 'hover:border-blue-400',

  },
  self_guided: {
    bg: 'bg-teal-100',
    text: 'text-teal-700',
    label: '宿題',
    headerBg: 'bg-teal-500',
    borderColor: 'border-teal-200',
    hoverBorder: 'hover:border-teal-400',

  },
} as const

export const WORKOUT_CATEGORY_OPTIONS = {
  chest: '胸',
  back: '背中',
  shoulders: '肩',
  arms: '腕',
  legs: '脚',
  abs: '腹筋',
  cardio: '有酸素',
  stretch: 'ストレッチ',
  full_body: '全身',
  other: 'その他',
} as const

export const ASSIGNMENT_STATUS_OPTIONS = {
  pending: '未実施',
  partial: '一部完了',
  completed: '完了',
  skipped: 'スキップ',
} as const

export const ASSIGNMENT_STATUS_COLORS = {
  pending: { bg: 'bg-gray-100', text: 'text-gray-600', icon: '⚪' },
  partial: { bg: 'bg-yellow-100', text: 'text-yellow-800', icon: '🟡' },
  completed: { bg: 'bg-green-100', text: 'text-green-800', icon: '🟢' },
  skipped: { bg: 'bg-red-100', text: 'text-red-800', icon: '🔴' },
} as const
