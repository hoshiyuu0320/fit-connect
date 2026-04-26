import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabaseAdmin';

const EDIT_TIME_LIMIT_MINUTES = 5;

export async function PUT(req: NextRequest) {
  const body = await req.json();
  const { messageId, content } = body;

  if (!messageId || !content || !content.trim()) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 });
  }

  // メッセージ取得 & 5分以内チェック
  const { data: message, error: fetchError } = await supabaseAdmin
    .from('messages')
    .select('created_at, sender_type')
    .eq('id', messageId)
    .single();

  if (fetchError || !message) {
    return NextResponse.json({ error: 'メッセージが見つかりません' }, { status: 404 });
  }

  if (message.sender_type !== 'trainer') {
    return NextResponse.json({ error: '自分のメッセージのみ編集できます' }, { status: 403 });
  }

  const now = new Date();
  const createdAt = new Date(message.created_at);
  const diffMinutes = (now.getTime() - createdAt.getTime()) / 1000 / 60;

  if (diffMinutes > EDIT_TIME_LIMIT_MINUTES) {
    return NextResponse.json({ error: '編集可能な時間（5分）を過ぎました' }, { status: 403 });
  }

  // 更新
  const { error: updateError } = await supabaseAdmin
    .from('messages')
    .update({
      content: content.trim(),
      is_edited: true,
      edited_at: now.toISOString(),
      updated_at: now.toISOString(),
    })
    .eq('id', messageId);

  if (updateError) {
    console.error('DB update error:', updateError);
    return NextResponse.json({ error: updateError.message }, { status: 500 });
  }

  return NextResponse.json({ status: 'ok' });
}
