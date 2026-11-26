import { NextRequest, NextResponse } from 'next/server';
import type { User } from '@supabase/supabase-js';
import { supabaseAdmin } from '@/lib/supabaseAdmin';
import { requireTrainer } from '@/lib/api/guards';

// 新規登録画面は signUp の後、確認メールを案内する alert（閉じるまで処理が止まる）が閉じられてからこの API を呼ぶ。そのときセッションが無い（メール確認が有効なとき）か、同じブラウザに別のトレーナーのセッションが残っていることがある。
// どちらでも、body の userId が作られて1時間以内（alert が開いたままの時間を見込み、確認リンクの有効期限に合わせた）でメール未確認、かつメールが一致する Auth ユーザーなら、そのユーザーの行を作る。
const PENDING_SIGNUP_WINDOW_MS = 60 * 60 * 1000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function findPendingSignupUser(userId: unknown, email: unknown): Promise<User | null> {
  if (typeof userId !== 'string' || typeof email !== 'string' || !userId || !email || !UUID_RE.test(userId)) return null;
  const { data, error } = await supabaseAdmin.auth.admin.getUserById(userId);
  const user = data?.user;
  if (error || !user) return null;
  if (user.email_confirmed_at) return null;
  if (!user.email || user.email.toLowerCase() !== email.toLowerCase()) return null;
  const createdAt = Date.parse(user.created_at);
  if (!Number.isFinite(createdAt) || Date.now() - createdAt > PENDING_SIGNUP_WINDOW_MS) return null;
  return user;
}

export async function POST(req: NextRequest) {
  const auth = await requireTrainer();
  const body = await req.json().catch(() => null);

  const pending =
    body?.userId && body.userId !== auth.user?.id
      ? await findPendingSignupUser(body.userId, body?.email)
      : null;
  const user = pending ?? auth.user;
  if (!user) {
    return auth.response ?? NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });
  }

  const name = body?.name;
  if (!name) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }

  const { error } = await supabaseAdmin
    .from('trainers')
    .insert([{ id: user.id, name, email: user.email ?? '' }]);

  if (error) {
    // unique制約違反（既存行あり）はサインアップ二重送信・auth/callback upsert との
    // 競合に耐えるため冪等に成功扱いとする
    if (error.code === '23505') {
      return NextResponse.json({ status: 'ok' });
    }
    console.error('Trainer create error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ status: 'ok' });
}
