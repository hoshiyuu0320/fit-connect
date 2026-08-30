export type Trainer = {
  id: string
  name: string
  email: string
  // profile-images バケットの `パス#元ファイル名` 形式で保存へ移行済み。
  // レガシー行はフルURL、Google OAuth 由来の外部URL（lh3.googleusercontent.com）も共存する。
  // 表示は src/lib/supabase/storagePaths.ts のヘルパー経由で行うこと。
  profile_image_url: string | null
  subscription_plan: 'free' | 'pro' | 'business'
  trial_ends_at: string | null
  created_at: string
  updated_at: string
}

export type UpdateTrainerParams = {
  id: string
  name?: string
  email?: string
  profileImageUrl?: string | null  // パス保存へ移行（レガシー行はフルURL共存）
}
