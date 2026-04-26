# FIT-CONNECT Project Overview

## Purpose
FIT-CONNECT is a fitness trainer management platform. Trainers use a Next.js web app; clients will use a Flutter mobile app (planned).

## Tech Stack
- Next.js 15 (App Router), React 19, TypeScript 5
- Supabase (PostgreSQL + Realtime + Auth + Storage)
- Tailwind CSS 3 + Radix UI
- Zustand 5 (state management)
- date-fns 4, lucide-react, recharts 3, react-hook-form + zod

## Key Patterns
- `src/lib/supabase/` — one file per DB operation
- Dual Supabase client: browser (`supabase.ts`) + admin (`supabaseAdmin.ts`)
- `@/` path alias → `./src/*`
- Route groups: `(auth)`, `(user_console)`
- Components export via `export function` (named exports)
- 'use client' on interactive components

## Design System
- Primary: #0F172A, Accent: #14B8A6, Background: #F8FAFC, Surface: #FFFFFF, Border: #E2E8F0
- No Tailwind default colors (all hex values), no shadows, rounded-md (6px max), no gradients
- Font: Plus Jakarta Sans + Noto Sans JP

## Commands
- `npm run dev` — start dev server (port 3000)
- `npm run build` — production build
- `npm run lint` — ESLint
- `npx tsc --noEmit` — type check
