import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabaseAdmin';

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { userId, name, email } = body;

  if (!userId || !name || !email) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }

  const { error } = await supabaseAdmin
    .from('trainers')
    .insert([{ id: userId, name, email }]);

  if (error) {
    console.error('Trainer create error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ status: 'ok' });
}
