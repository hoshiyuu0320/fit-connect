// app/api/messages/send/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabaseAdmin';

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { trainerId, clientId, content } = body;

  if (!trainerId || !clientId || !content) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }

  // DBに保存
  const { error } = await supabaseAdmin.from('messages').insert([
    {
      sender_id: trainerId,
      receiver_id: clientId,
      content: content,
      sender_type: 'trainer',
      receiver_type: 'client',
    },
  ]);
  
  if (error) {
    console.error('DB insert error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ status: 'ok' });
}