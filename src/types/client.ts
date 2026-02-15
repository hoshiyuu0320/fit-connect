// ================================================
// FIT-CONNECT 顧客管理機能 TypeScript型定義
// ================================================

// クライアント基本情報
export type Client = {
  client_id: string
  trainer_id: string
  name: string
  gender: 'male' | 'female' | 'other'
  age: number
  occupation: string | null
  height: number
  target_weight: number
  purpose: 'diet' | 'contest' | 'body_make' | 'health_improvement' | 'mental_improvement' | 'performance_improvement'
  goal_description: string | null
  goal_deadline: string | null
  profile_image_url: string | null
  line_user_id: string | null
  created_at: string
}

// クライアント詳細情報（体重情報を含む）
export type ClientDetail = Client & {
  current_weight?: number  // 最新の体重記録から算出
  initial_weight?: number  // 初回の体重記録
}

// 体重記録
export type WeightRecord = {
  id: string
  client_id: string
  weight: number
  notes: string | null
  recorded_at: string
}

// 食事記録
export type MealRecord = {
  id: string
  client_id: string
  meal_type: 'breakfast' | 'lunch' | 'dinner' | 'snack'
  notes: string | null
  calories: number | null
  images: string[] | null
  recorded_at: string
}

// 運動記録
export type ExerciseRecord = {
  id: string
  client_id: string
  exercise_type: 'walking' | 'running' | 'strength_training' | 'cycling' | 'swimming' | 'yoga' | 'pilates' | 'cardio' | 'other'
  duration: number | null
  distance: number | null
  calories: number | null
  memo: string | null
  recorded_at: string
}

// メッセージ
export type Message = {
  id: string
  sender: string
  content: string
  timestamp: string
  created_at: string
  senderType: 'client' | 'trainer'
  receiverType: 'client' | 'trainer'
  image_urls: string[]
  is_edited: boolean
  edited_at: string | null
  reply_to_message_id: string | null
  reply_to_message?: {
    id: string
    sender: string
    content: string
    image_urls?: string[]
  } | null
}

// チケット
export type Ticket = {
  id: string
  client_id: string
  ticket_name: string
  ticket_type: string
  total_sessions: number
  remaining_sessions: number
  valid_from: string
  valid_until: string
  created_at: string
}

export type CreateTicketParams = {
  clientId: string
  ticketName: string
  ticketType: string
  totalSessions: number
  validFrom: string
  validUntil: string
}

export type UpdateTicketParams = {
  id: string
  ticketName?: string
  ticketType?: string
  totalSessions?: number
  remainingSessions?: number
  validFrom?: string
  validUntil?: string
}

// チケットテンプレート
export type TicketTemplate = {
  id: string
  trainer_id: string
  template_name: string
  ticket_type: string
  total_sessions: number
  valid_months: number
  is_recurring: boolean
  created_at: string
  updated_at: string
}

export type CreateTicketTemplateParams = {
  trainerId: string
  templateName: string
  ticketType: string
  totalSessions: number
  validMonths: number
  isRecurring: boolean
}

export type UpdateTicketTemplateParams = {
  id: string
  templateName?: string
  ticketType?: string
  totalSessions?: number
  validMonths?: number
  isRecurring?: boolean
}

// チケット月契約
export type TicketSubscription = {
  id: string
  template_id: string
  client_id: string
  status: 'active' | 'paused' | 'cancelled'
  start_date: string
  next_issue_date: string
  created_at: string
  // JOINで取得
  template?: TicketTemplate
  client_name?: string
}

export type CreateTicketSubscriptionParams = {
  templateId: string
  clientId: string
  startDate: string
}

export type UpdateTicketSubscriptionParams = {
  id: string
  status: 'active' | 'paused' | 'cancelled'
}

// 発行済みチケット（顧客名付き）
export type TicketWithClient = Ticket & {
  client_name: string
}

// カルテ（トレーナーノート）
export type ClientNote = {
  id: string
  client_id: string
  trainer_id: string
  title: string
  content: string
  file_urls: string[]
  is_shared: boolean
  shared_at: string | null
  session_number: number | null
  created_at: string
  updated_at: string
}

// カルテ作成パラメータ
export type CreateClientNoteParams = {
  clientId: string
  trainerId: string
  title: string
  content: string
  fileUrls?: string[]
  isShared?: boolean
  sessionNumber?: number | null
}

// カルテ更新パラメータ
export type UpdateClientNoteParams = {
  id: string
  title?: string
  content?: string
  fileUrls?: string[]
  isShared?: boolean
  sessionNumber?: number | null
}

// ================================================
// 定数定義
// ================================================

// 性別の選択肢
export const GENDER_OPTIONS = {
  male: '男性',
  female: '女性',
  other: 'その他',
} as const

// 目的の選択肢
export const PURPOSE_OPTIONS = {
  diet: 'ダイエット',
  contest: 'コンテスト',
  body_make: 'ボディメイク',
  health_improvement: '健康維持・生活習慣の改善',
  mental_improvement: 'メンタル・自己肯定感向上',
  performance_improvement: 'パフォーマンス向上（競技・仕事）',
} as const

// 食事区分の選択肢
export const MEAL_TYPE_OPTIONS = {
  breakfast: '朝食',
  lunch: '昼食',
  dinner: '夕食',
  snack: '間食',
} as const

// 運動種目の選択肢
export const EXERCISE_TYPE_OPTIONS = {
  walking: 'ウォーキング',
  running: 'ランニング',
  strength_training: '筋力トレーニング',
  cycling: 'サイクリング',
  swimming: 'スイミング',
  yoga: 'ヨガ',
  pilates: 'ピラティス',
  cardio: '有酸素運動',
  other: 'その他',
} as const

// チケット種別の選択肢
export const TICKET_TYPE_OPTIONS = {
  personal: 'パーソナル',
  group: 'グループ',
  online: 'オンライン',
  other: 'その他',
} as const

// 年齢層の選択肢（フィルタリング用）
export const AGE_RANGE_OPTIONS = [
  { label: 'すべて', min: 0, max: 999 },
  { label: '10代', min: 10, max: 19 },
  { label: '20代', min: 20, max: 29 },
  { label: '30代', min: 30, max: 39 },
  { label: '40代', min: 40, max: 49 },
  { label: '50代', min: 50, max: 59 },
  { label: '60代以上', min: 60, max: 999 },
] as const

// ================================================
// パラメータ型定義
// ================================================

// 顧客検索パラメータ
export type SearchClientsParams = {
  trainerId: string
  searchQuery?: string      // 名前検索
  gender?: 'male' | 'female' | 'other'
  ageRange?: {
    min: number
    max: number
  }
  purpose?: Client['purpose']
}

// 食事記録取得パラメータ
export type GetMealRecordsParams = {
  clientId: string
  mealType?: MealRecord['meal_type']  // フィルター（任意）
  limit?: number      // 取得件数（デフォルト: 20）
  offset?: number     // オフセット（デフォルト: 0）
}

// 食事記録取得結果
export type GetMealRecordsResult = {
  data: MealRecord[]
  count: number  // 総件数
}

// 運動記録取得パラメータ
export type GetExerciseRecordsParams = {
  clientId: string
  limit?: number      // 取得件数（デフォルト: 20）
  offset?: number     // オフセット（デフォルト: 0）
}

// 運動記録取得結果
export type GetExerciseRecordsResult = {
  data: ExerciseRecord[]
  count: number
}
