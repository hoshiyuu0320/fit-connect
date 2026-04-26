ALTER TABLE public.workout_assignments
  ADD COLUMN IF NOT EXISTS calories NUMERIC;;
