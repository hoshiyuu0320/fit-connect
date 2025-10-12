// app/api/line/webhook/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabaseAdmin';

export async function POST(req: NextRequest) {
  const body = await req.json();

  for (const event of body.events) {
    if (event.type === 'message' && event.message.type === 'text') {
      const lineUserId = event.source.userId;
      const text = event.message.text;

      // クライアント特定
      const { data: client } = await supabaseAdmin
        .from('clients')
        .select('client_id, trainer_id')
        .eq('line_user_id', lineUserId)
        .single();

        console.log("client", client)

        if (client) {
        await supabaseAdmin.from('messages').insert([
            {
            sender_id: client.client_id,
            receiver_id: client.trainer_id,
            message: text,
            sender_type: 'client',
            receiver_type: 'trainer',
            },
        ]);
        }
    }
  }

  return NextResponse.json({ status: 'ok' });
}