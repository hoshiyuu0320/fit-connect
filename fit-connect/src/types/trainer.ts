export type Trainer = {
  id: string
  name: string
  email: string
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
  profileImageUrl?: string | null
}
