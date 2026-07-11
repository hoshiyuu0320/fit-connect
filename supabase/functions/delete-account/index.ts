// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const FUNCTION_NAME = 'delete-account'

function errorResponse(code: string, message: string, status: number) {
  return new Response(JSON.stringify({ error: code, message }), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  })
}

/**
 * 指定フォルダ直下のファイルのフルパス一覧を返す（ベストエフォート）。
 * Storage の list はフォルダ単位（非再帰）なので、サブフォルダは呼び出し側で列挙する。
 * エラー時は空配列を返して削除処理を続行させる。
 */
async function listFilePaths(
  supabase: any,
  bucket: string,
  folder: string,
): Promise<string[]> {
  const { data, error } = await supabase.storage.from(bucket).list(folder, { limit: 1000 })
  if (error) {
    console.error(`[${FUNCTION_NAME}] storage list failed (${bucket}/${folder}):`, error)
    return []
  }
  return (data ?? [])
    // フォルダエントリは id が null（ファイルのみ残す）
    .filter((item: any) => item.id)
    .map((item: any) => `${folder}/${item.name}`)
}

/**
 * 複数フォルダ配下のファイルをまとめて削除（ベストエフォート）。
 * Storage の削除失敗でアカウント削除全体を失敗させない（孤児ファイルは残るが実害は小さい）。
 */
async function removeFolders(supabase: any, bucket: string, folders: string[]) {
  try {
    const paths: string[] = []
    for (const folder of folders) {
      paths.push(...(await listFilePaths(supabase, bucket, folder)))
    }
    if (paths.length === 0) return
    const { error } = await supabase.storage.from(bucket).remove(paths)
    if (error) {
      console.error(`[${FUNCTION_NAME}] storage remove failed (${bucket}):`, error)
    }
  } catch (e) {
    console.error(`[${FUNCTION_NAME}] storage cleanup error (${bucket}):`, e)
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }
  try {
    // 1. Auth: 呼び出し元の JWT を自前検証（verify_jwt=false のため必須）
    //    削除対象は JWT から得た authUid のみ。リクエストボディでの uid 指定は受け付けない
    //    （他人のアカウントを削除させないため）。
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return errorResponse('FORBIDDEN', 'No auth token', 403)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userErr } = await userClient.auth.getUser()
    if (userErr || !userData.user) {
      return errorResponse('FORBIDDEN', 'Invalid token', 403)
    }
    const authUid = userData.user.id

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 2. clients 行を取得して trainer_id を控える（Storage の client-notes パス構築に必要）。
    //    行が無くても後続は続行する: 前回の削除試行が途中で失敗した場合のリトライを
    //    成功させるため（clients 削除済み・auth 未削除の状態から再開できる）。
    const { data: client, error: clientErr } = await supabase
      .from('clients')
      .select('client_id, trainer_id')
      .eq('client_id', authUid)
      .maybeSingle()
    if (clientErr) {
      console.error(`[${FUNCTION_NAME}] clients fetch failed:`, clientErr)
      return errorResponse('DELETE_FAILED', 'Failed to fetch client', 500)
    }
    const trainerId: string | null = client?.trainer_id ?? null

    // クライアント専用機能: トレーナーアカウント（clients に行が無く trainers に行がある uid）
    // からの呼び出しは拒否する。
    if (!client) {
      const { data: trainer, error: trainerErr } = await supabase
        .from('trainers')
        .select('id')
        .eq('id', authUid)
        .maybeSingle()
      if (trainerErr) {
        console.error(`[${FUNCTION_NAME}] trainers fetch failed:`, trainerErr)
        return errorResponse('DELETE_FAILED', 'Failed to verify account type', 500)
      }
      if (trainer) {
        return errorResponse('FORBIDDEN', 'Trainer accounts cannot be deleted here', 403)
      }
    }

    // ============================================================
    // 削除順序は FK 制約上必須（順序を変えると FK 違反で失敗する）:
    //   (a) clients 行 DELETE
    //       → weight/meal/exercise/sleep_records・sessions・tickets・
    //         ticket_subscriptions・workout_assignments(+assignment_exercises)・
    //         client_notes・ai_estimation_logs が ON DELETE CASCADE で消える
    //   (b) messages DELETE
    //       → messages には sender_id/receiver_id の FK が無く CASCADE されないため明示削除。
    //         かつ *_records.message_id → messages(id) の FK は NO ACTION なので、
    //         records が残っている間に messages を消すと FK 違反になる。
    //         したがって (a) clients 削除（= records の CASCADE 削除）より後でなければならない。
    //   (c) Storage 削除（ベストエフォート）
    //   (d) auth.users 削除（最後。ここまでのどこかで失敗しても JWT が生きていて再試行できる）
    // ============================================================

    // 3. (a) clients 行を DELETE（子テーブルは CASCADE で削除される）
    const { error: deleteClientErr } = await supabase
      .from('clients')
      .delete()
      .eq('client_id', authUid)
    if (deleteClientErr) {
      console.error(`[${FUNCTION_NAME}] clients delete failed:`, deleteClientErr)
      return errorResponse('DELETE_FAILED', 'Failed to delete client data', 500)
    }

    // 4. (b) messages を DELETE（送信・受信の両方）
    const { error: deleteMessagesErr } = await supabase
      .from('messages')
      .delete()
      .or(`sender_id.eq.${authUid},receiver_id.eq.${authUid}`)
    if (deleteMessagesErr) {
      console.error(`[${FUNCTION_NAME}] messages delete failed:`, deleteMessagesErr)
      return errorResponse('DELETE_FAILED', 'Failed to delete messages', 500)
    }

    // 5. (c) Storage をベストエフォート削除（エラーはログのみで続行）
    // message-photos: {authUid}/ 直下 + AI 推定用サブフォルダ {authUid}/ai/
    await removeFolders(supabase, 'message-photos', [authUid, `${authUid}/ai`])
    // client-avatars: {authUid}/ 直下
    await removeFolders(supabase, 'client-avatars', [authUid])
    // client-notes: パスが {trainer_id}/{client_id}/ 構造のため trainer_id が取れた場合のみ
    if (trainerId) {
      await removeFolders(supabase, 'client-notes', [`${trainerId}/${authUid}`])
    }

    // 6. (d) auth.users から削除（最後に実行。これが成功した時点で再ログイン不可になる）
    const { error: deleteAuthErr } = await supabase.auth.admin.deleteUser(authUid)
    if (deleteAuthErr) {
      console.error(`[${FUNCTION_NAME}] auth user delete failed:`, deleteAuthErr)
      return errorResponse('DELETE_FAILED', 'Failed to delete auth user', 500)
    }

    // 7. 完了
    return new Response(JSON.stringify({ success: true }), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    console.error(`[${FUNCTION_NAME}] error:`, e)
    return errorResponse('DELETE_FAILED', 'Internal error', 500)
  }
})
