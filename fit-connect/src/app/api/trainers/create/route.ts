import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabaseAdmin';
import { requireTrainer } from '@/lib/api/guards';

export async function POST(req: NextRequest) {
  const auth = await requireTrainer();
  if (auth.response) return auth.response;

  const body = await req.json();
  const { name } = body;

  if (!name) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }

  const { error } = await supabaseAdmin
    .from('trainers')
    .insert([{ id: auth.user.id, name, email: auth.user.email ?? '' }]);

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
