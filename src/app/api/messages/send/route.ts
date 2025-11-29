// app/api/messages/send/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { messagingApi } from '@line/bot-sdk';
import { supabaseAdmin } from '@/lib/supabaseAdmin';

const lineClient = new messagingApi.MessagingApiClient({
  channelAccessToken: process.env.LINE_CHANNEL_ACCESS_TOKEN!,
});

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { trainerId, clientId, message } = body;

  if (!trainerId || !clientId || !message) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }

  // DBに保存
  const { error } = await supabaseAdmin.from('messages').insert([
    {
      sender_id: trainerId,
      receiver_id: clientId,
      message,
      sender_type: 'trainer',
      receiver_type: 'client',
    },
  ]);
  
  if (error) {
    console.error('DB insert error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // clientのline_user_id取得
  const { data: client } = await supabaseAdmin
    .from('clients')
    .select('line_user_id')
    .eq('client_id', clientId)
    .single();

  if (client?.line_user_id) {
    // LINEに送信
    await lineClient.pushMessage({
      to: client.line_user_id,
      messages: [{
        type: 'text',
        text: message,
      }],
    });
  }

  return NextResponse.json({ status: 'ok' });
}