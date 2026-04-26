import { supabase } from '@/lib/supabase';

export interface SessionWorkoutPlan {
  id: string;
  title: string;
  category: string;
  estimated_minutes: number | null;
}

export const getSessionWorkoutPlans = async (): Promise<SessionWorkoutPlan[]> => {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { data, error } = await supabase
    .from('workout_plans')
    .select('id, title, category, estimated_minutes')
    .eq('trainer_id', user.id)
    .eq('plan_type', 'session')
    .order('title', { ascending: true });

  if (error) {
    console.error('Error fetching session workout plans:', error);
    throw error;
  }

  return data as SessionWorkoutPlan[];
};
