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

FIT-CONNECT is a Next.js 15 fitness trainer management application with Supabase backend and LINE integration for real-time messaging between trainers and clients.

### Core Technology Stack
- **Framework:** Next.js 15 (App Router)
- **Database:** Supabase (PostgreSQL with Row Level Security)
- **Authentication:** Supabase Auth + LINE LIFF
- **Messaging:** LINE Bot SDK + Supabase Realtime
- **State Management:** Zustand with localStorage persistence
- **UI:** Tailwind CSS + Radix UI components
- **Forms:** React Hook Form + Zod validation

### Project Structure

```
src/
├── app/
│   ├── (auth)/              # Auth routes (login, signup)
│   ├── (user_console)/      # Protected dashboard routes
│   │   ├── message/         # Real-time messaging UI
│   │   └── layout.tsx       # Sidebar layout
│   ├── api/
│   │   ├── messages/send/   # Message API with LINE push
│   │   └── line/webhook/    # LINE webhook handler
│   └── liff/                # LINE LIFF registration app
├── lib/
│   ├── supabase.ts          # Browser Supabase client
│   ├── supabaseAdmin.ts     # Server-side admin client
│   └── supabase/            # Database query functions
├── store/
│   └── userStore.ts         # Zustand state management
└── components/
    └── ui/                  # Reusable UI components
```

### Database Schema

**profiles** (trainers)
- `id` (UUID, PK) - References auth.users.id
- `name` (TEXT) - Trainer name

**clients** (trainer's clients)
- `client_id` (UUID, PK)
- `trainer_id` (UUID, FK) → profiles.id
- `name` (TEXT)
- `line_user_id` (TEXT, UNIQUE) - For LINE messaging
- `created_at` (TIMESTAMPTZ)

**messages** (bidirectional messaging)
- `id` (UUID, PK)
- `sender_id` (UUID) - Trainer or client ID
- `receiver_id` (UUID) - Trainer or client ID
- `sender_type` (TEXT) - 'trainer' or 'client'
- `receiver_type` (TEXT) - 'trainer' or 'client'
- `message` (TEXT)
- `timestamp` (TIMESTAMPTZ)

All tables use Row Level Security (RLS) for access control.

## Key Architectural Patterns

### Dual Supabase Client Pattern
- **Browser client** (`src/lib/supabase.ts`): Uses `NEXT_PUBLIC_SUPABASE_ANON_KEY` for client-side operations
- **Admin client** (`src/lib/supabaseAdmin.ts`): Uses `SUPABASE_SERVICE_ROLE_KEY` for server-side/API operations
- API routes act as the security boundary for sensitive operations

### Database Operations
Each database operation is isolated in its own file under `src/lib/supabase/`:
- `getClients.ts` - Fetch trainer's clients
- `getMessages.ts` - Bidirectional message query
- `sendMessage.ts` - Insert message record
- `createProfile.ts` - Create trainer profile on signup
- `saveLineUser.ts` - Register client via LINE

### Authentication Flow
1. **Email/Password:** `supabase.auth.signUp()` → `createProfile()` → redirect to dashboard
2. **LINE LIFF:** Share `/liff?trainerId=<uuid>` link → LIFF initialization → `saveLineUser()` → LINE friend addition

### Messaging Architecture
**Trainer → Client (Web to LINE):**
1. Trainer sends message in web UI
2. POST to `/api/messages/send`
3. Save to `messages` table via `supabaseAdmin`
4. Push to LINE via `lineClient.pushMessage()` if client has `line_user_id`

**Client → Trainer (LINE to Web):**
1. Client sends message in LINE app
2. LINE webhook → POST to `/api/line/webhook`
3. Extract `lineUserId` → query `clients` table
4. Save to `messages` table
5. Trainer sees message in web UI via Realtime subscription

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
NEXT_PUBLIC_LIFF_ID               # LINE LIFF app ID
SUPABASE_SERVICE_ROLE_KEY         # Admin key (server-only)
LINE_CHANNEL_ACCESS_TOKEN         # LINE Bot channel token
```

## Important Notes

### Client vs Server Components
- All auth pages (`/login`, `/signup`) use `"use client"` for form handling
- Dashboard routes use `"use client"` for interactivity and Realtime subscriptions
- API routes are server-side only and use `supabaseAdmin`
- LIFF app (`/liff`) is client-side only (requires browser APIs)

### LINE Integration
- LIFF app must be opened within LINE app for proper initialization
- Webhook endpoint (`/api/line/webhook`) receives all LINE events
- Only `message` events of type `text` are currently processed
- `line_user_id` is the key that links clients to LINE accounts

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

### Known Limitations (from database design docs)
- No foreign key constraints on `messages.sender_id` and `messages.receiver_id`
- Missing indexes on `messages` table for performance optimization
- Some pages are placeholder implementations (schedule, report, workout plan, settings)

## API Endpoints

### POST /api/messages/send
Send message from trainer to client with optional LINE push notification.

**Body:**
```json
{
  "trainerId": "uuid",
  "clientId": "uuid",
  "message": "text"
}
```

**Returns:** `{ status: 'ok' }` on success

### POST /api/line/webhook
LINE webhook endpoint for receiving messages from clients.

**Handles:** LINE webhook events (message events are processed and saved to database)

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
