# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```bash
# Start development server
npm run dev                 # Runs on http://localhost:3000

# Build for production
npm run build

# Start production server
npm start

# Run linting
npm run lint
```

## Architecture Overview

FIT-CONNECT is a fitness trainer management platform consisting of a Next.js 15 web application for trainers and a planned KMM (Kotlin Multiplatform Mobile) native app for clients, both backed by Supabase.

### Core Technology Stack

**Trainer Web App (Current)**
- **Framework:** Next.js 15 (App Router)
- **Database:** Supabase (PostgreSQL with Row Level Security)
- **Authentication:** Supabase Auth
- **Messaging:** Supabase Realtime
- **State Management:** Zustand with localStorage persistence
- **UI:** Tailwind CSS + Radix UI components
- **Forms:** React Hook Form + Zod validation

**Client Mobile App (Planned - See ROADMAP.md)**
- **Shared Logic:** Kotlin Multiplatform Mobile (KMM)
- **iOS UI:** SwiftUI
- **Android UI:** Jetpack Compose
- **Backend:** Supabase (shared with web app)

### Project Structure

```
src/
├── app/
│   ├── (auth)/              # Auth routes (login, signup)
│   ├── (user_console)/      # Protected dashboard routes
│   │   ├── clients/         # Client management and detail pages
│   │   ├── dashboard/       # Trainer dashboard
│   │   ├── message/         # Real-time messaging UI
│   │   ├── schedule/        # Session scheduling (placeholder)
│   │   ├── report/          # Analytics and reports (placeholder)
│   │   ├── workoutplan/     # Training plan management (placeholder)
│   │   ├── settings/        # Account settings (placeholder)
│   │   └── layout.tsx       # Sidebar layout
│   └── api/
│       └── messages/send/   # Message sending API endpoint
├── lib/
│   ├── supabase.ts          # Browser Supabase client
│   ├── supabaseAdmin.ts     # Server-side admin client
│   └── supabase/            # Database query functions (one file per operation)
├── store/
│   └── userStore.ts         # Zustand state management
├── types/
│   └── client.ts            # TypeScript type definitions for client domain
└── components/
    ├── clients/             # Client-specific components
    └── ui/                  # Reusable UI components (Radix-based)
```

### Database Schema

**profiles** (trainers)
- `id` (UUID, PK) - References auth.users.id
- `name` (TEXT) - Trainer name

**clients** (trainer's clients)
- `client_id` (UUID, PK)
- `trainer_id` (UUID, FK) → profiles.id
- `name` (TEXT)
- `gender` (TEXT) - 'male', 'female', 'other'
- `age` (INT)
- `occupation` (TEXT)
- `height` (NUMERIC)
- `target_weight` (NUMERIC)
- `purpose` (TEXT) - 'diet', 'contest', 'body_make', 'health_improvement', 'mental_improvement', 'performance_improvement'
- `goal_description` (TEXT)
- `profile_image_url` (TEXT)
- `line_user_id` (TEXT, UNIQUE) - Legacy LINE integration (deprecated)
- `created_at` (TIMESTAMPTZ)

**messages** (bidirectional messaging)
- `id` (UUID, PK)
- `sender_id` (UUID) - Trainer or client ID
- `receiver_id` (UUID) - Trainer or client ID
- `sender_type` (TEXT) - 'trainer' or 'client'
- `receiver_type` (TEXT) - 'trainer' or 'client'
- `message` (TEXT)
- `timestamp` (TIMESTAMPTZ)

**weight_records** (client weight tracking)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `weight` (NUMERIC)
- `recorded_at` (TIMESTAMPTZ)

**meal_records** (client meal logging)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `meal_type` (TEXT) - 'breakfast', 'lunch', 'dinner', 'snack'
- `description` (TEXT)
- `calories` (INT)
- `images` (TEXT[]) - Array of image URLs
- `recorded_at` (TIMESTAMPTZ)

**exercise_records** (client workout logging)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `exercise_type` (TEXT) - 'walking', 'running', 'strength_training', etc.
- `duration` (INT) - Minutes
- `distance` (NUMERIC) - Kilometers
- `calories` (INT)
- `memo` (TEXT)
- `recorded_at` (TIMESTAMPTZ)

**tickets** (session ticket management)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `ticket_name` (TEXT)
- `ticket_type` (TEXT)
- `total_sessions` (INT)
- `remaining_sessions` (INT)
- `valid_from` (TIMESTAMPTZ)
- `valid_until` (TIMESTAMPTZ)
- `created_at` (TIMESTAMPTZ)

All tables use Row Level Security (RLS) for access control. See `src/types/client.ts` for complete TypeScript type definitions.

## Key Architectural Patterns

### Dual Supabase Client Pattern
- **Browser client** (`src/lib/supabase.ts`): Uses `NEXT_PUBLIC_SUPABASE_ANON_KEY` for client-side operations
- **Admin client** (`src/lib/supabaseAdmin.ts`): Uses `SUPABASE_SERVICE_ROLE_KEY` for server-side/API operations
- API routes act as the security boundary for sensitive operations

### Database Operations
Each database operation is isolated in its own file under `src/lib/supabase/`:
- `getClients.ts` - Fetch trainer's clients
- `getClientDetail.ts` - Fetch single client with details
- `searchClients.ts` - Search/filter clients by name, gender, age, purpose
- `getMessages.ts` - Bidirectional message query
- `sendMessage.ts` - Insert message record
- `createProfile.ts` - Create trainer profile on signup
- `getProfile.ts` - Fetch trainer profile
- `getWeightRecords.ts` - Fetch client weight history
- `getMealRecords.ts` - Fetch client meal logs (with pagination)
- `getExerciseRecords.ts` - Fetch client exercise logs (with pagination)
- `getTickets.ts` - Fetch client session tickets

### Authentication Flow
1. **Trainer:** `supabase.auth.signUp()` → `createProfile()` → redirect to dashboard
2. **Client:** Will be handled via KMM mobile app (future implementation)

### Messaging Architecture
**Trainer → Client:**
1. Trainer sends message in web UI ([/message](src/app/(user_console)/message/page.tsx))
2. POST to `/api/messages/send`
3. Save to `messages` table via `supabaseAdmin`
4. Client receives via Realtime subscription (future: push notification to mobile app)

**Client → Trainer:**
1. Client sends message via mobile app (future implementation)
2. Save to `messages` table
3. Trainer sees message in web UI via Realtime subscription

**Real-time Updates:**
```typescript
supabase
  .channel('message-room')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'messages',
    filter: `receiver_id=eq.${userId}`,
  }, handleNewMessage)
  .subscribe()
```

## Environment Variables

Required in `.env.local`:
```
NEXT_PUBLIC_SUPABASE_URL          # Supabase project URL
NEXT_PUBLIC_SUPABASE_ANON_KEY     # Supabase anonymous key
SUPABASE_SERVICE_ROLE_KEY         # Admin key (server-only, never expose to client)
```

**Note:** LINE-related environment variables (LIFF_ID, LINE_CHANNEL_ACCESS_TOKEN) are deprecated as the project is transitioning to a KMM mobile app architecture.

## Important Notes

### Client vs Server Components
- All auth pages (`/login`, `/signup`) use `"use client"` for form handling
- Dashboard routes use `"use client"` for interactivity and Realtime subscriptions
- API routes are server-side only and use `supabaseAdmin`

### Client Management Features
- **Client List** ([/clients](src/app/(user_console)/clients/page.tsx)): Search and filter clients by name, gender, age range, and fitness purpose
- **Client Detail** ([/clients/[client_id]](src/app/(user_console)/clients/[client_id]/page.tsx)): View comprehensive client profile including:
  - Basic info (age, gender, height, target weight, goals)
  - Weight progression tracking
  - Meal records with images and calorie data
  - Exercise logs with duration, distance, and calories
  - Session tickets with remaining sessions and expiry dates

### Path Aliases
- Use `@/` prefix for imports (maps to `./src/*`)
- Example: `import { supabase } from '@/lib/supabase'`

### Route Groups
- `(auth)` and `(user_console)` are Next.js route groups
- They organize routes without affecting URLs
- Each can have its own layout

### State Management
- Zustand store (`userStore.ts`) persists user data to localStorage
- Minimal global state - most data fetched from Supabase
- Realtime subscriptions handle live updates

### Known Limitations
- No foreign key constraints on `messages.sender_id` and `messages.receiver_id`
- Missing indexes on `messages` table for performance optimization
- Placeholder implementations: `/schedule`, `/report`, `/workoutplan`, `/settings`
- Client-side record creation (meals, exercises, weight) requires KMM mobile app (not yet implemented)
- Graph visualization for weight tracking not yet implemented (shows table data only)

### Development Roadmap
See [ROADMAP.md](ROADMAP.md) for comprehensive implementation plan including:
- Phase 1: Schedule/session management and dashboard improvements
- Phase 2: KMM mobile app for clients with meal/exercise logging
- Phase 3: Analytics, reports, and training plan features
- Phase 4: Settings page and performance optimizations

## API Endpoints

### POST /api/messages/send
Send message from trainer to client.

**Body:**
```json
{
  "trainerId": "uuid",
  "clientId": "uuid",
  "message": "text"
}
```

**Returns:** `{ status: 'ok' }` on success

**Note:** Currently saves to database only. Push notifications to mobile app will be added in Phase 2.

## Common Development Patterns

### Adding a new database query
1. Create file in `src/lib/supabase/` (e.g., `getTrainerStats.ts`)
2. Export async function that uses `supabase` or `supabaseAdmin`
3. Handle errors with try/catch or check `error` property
4. Import and use in components or API routes

### Adding a new API route
1. Create `route.ts` in `src/app/api/your-route/`
2. Use `supabaseAdmin` from `@/lib/supabaseAdmin`
3. Export named functions: `GET`, `POST`, `PUT`, `DELETE`
4. Return `NextResponse.json()` for responses

### Adding real-time functionality
1. Create Supabase channel with unique name
2. Subscribe to `postgres_changes` event
3. Filter by table and optionally by row conditions
4. Update local state in callback
5. Clean up subscription on unmount

# 開発フロー
- レイアウトは既存のレイアウトを踏襲すること