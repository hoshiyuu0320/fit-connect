// app/api/messages/send/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabaseAdmin';
import { requireTrainer, notFoundResponse, trainerOwnsClient } from '@/lib/api/guards';

export async function POST(req: NextRequest) {
  const auth = await requireTrainer();
  if (auth.response) return auth.response;
  const trainerId = auth.user.id;

  const body = await req.json();
  const { clientId, content, image_urls, reply_to_message_id } = body;

  // contentかimage_urlsのどちらかは必須
  const hasContent = content && content.trim().length > 0;
  const hasImages = Array.isArray(image_urls) && image_urls.length > 0;

  if (!clientId || (!hasContent && !hasImages)) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }

  // image_urlsのバリデーション
  if (hasImages && image_urls.length > 3) {
    return NextResponse.json({ error: '画像は最大3枚までです' }, { status: 400 });
  }

  if (!(await trainerOwnsClient(trainerId, clientId))) {
    return notFoundResponse();
  }

  // DBに保存
  const { data, error } = await supabaseAdmin.from('messages').insert([
    {
      sender_id: trainerId,
      receiver_id: clientId,
      content: content || '',
      sender_type: 'trainer',
      receiver_type: 'client',
      ...(hasImages && { image_urls }),
      ...(reply_to_message_id && { reply_to_message_id }),
    },
  ]).select('id, created_at').single();

  if (error) {
    console.error('DB insert error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ status: 'ok', id: data.id, created_at: data.created_at });
}
