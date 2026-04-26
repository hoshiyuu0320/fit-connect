-- Migration: Add client-side RLS policies for mobile app
-- Created: 2025-12-30
-- Purpose: Enable clients to access and manage their own data

-- ============================================================================
-- 1. Add 'role' column to profiles table
-- ============================================================================

ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS role TEXT CHECK (role IN ('trainer', 'client'));

COMMENT ON COLUMN profiles.role IS 'User role: trainer or client';

-- ============================================================================
-- 2. profiles table - Allow users to update their own profile
-- ============================================================================

CREATE POLICY "Users can update own profile"
ON profiles FOR UPDATE
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- ============================================================================
-- 3. clients table - Allow clients to view their own profile
-- ============================================================================

CREATE POLICY "Clients can view own profile"
ON clients FOR SELECT
USING (client_id = auth.uid());

-- ============================================================================
-- 4. weight_records - Client policies
-- ============================================================================

CREATE POLICY "Clients can view own weight records"
ON weight_records FOR SELECT
USING (client_id = auth.uid());

CREATE POLICY "Clients can insert own weight records"
ON weight_records FOR INSERT
WITH CHECK (client_id = auth.uid());

CREATE POLICY "Clients can update own weight records"
ON weight_records FOR UPDATE
USING (client_id = auth.uid())
WITH CHECK (client_id = auth.uid());

CREATE POLICY "Clients can delete own weight records"
ON weight_records FOR DELETE
USING (client_id = auth.uid());

-- ============================================================================
-- 5. meal_records - Client policies
-- ============================================================================

CREATE POLICY "Clients can view own meal records"
ON meal_records FOR SELECT
USING (client_id = auth.uid());

CREATE POLICY "Clients can insert own meal records"
ON meal_records FOR INSERT
WITH CHECK (client_id = auth.uid());

CREATE POLICY "Clients can update own meal records"
ON meal_records FOR UPDATE
USING (client_id = auth.uid())
WITH CHECK (client_id = auth.uid());

CREATE POLICY "Clients can delete own meal records"
ON meal_records FOR DELETE
USING (client_id = auth.uid());

-- ============================================================================
-- 6. exercise_records - Client policies
-- ============================================================================

CREATE POLICY "Clients can view own exercise records"
ON exercise_records FOR SELECT
USING (client_id = auth.uid());

CREATE POLICY "Clients can insert own exercise records"
ON exercise_records FOR INSERT
WITH CHECK (client_id = auth.uid());

CREATE POLICY "Clients can update own exercise records"
ON exercise_records FOR UPDATE
USING (client_id = auth.uid())
WITH CHECK (client_id = auth.uid());

CREATE POLICY "Clients can delete own exercise records"
ON exercise_records FOR DELETE
USING (client_id = auth.uid());

-- ============================================================================
-- Note: Message policies already exist in the previous migration
-- (Users can view/send/edit their own messages)
-- ============================================================================
