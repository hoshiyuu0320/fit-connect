// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendNotification } from '../_shared/push.ts'

Deno.serve(async (req) => {
  try {
    const payload = await req.json()

    // Check if this is a webhook payload (INSERT or UPDATE on messages)
    if ((payload.type === 'INSERT' || payload.type === 'UPDATE') && payload.table === 'messages') {
      const message = payload.record
      // Skip if message is from system or doesn't have content
      if (!message.content) {
        return new Response(JSON.stringify({ skipped: true }), { headers: { 'Content-Type': 'application/json' } })
      }

      // Initialize Supabase Client with Service Role Key
      const supabaseUrl = Deno.env.get('SUPABASE_URL')
      const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

      if (!supabaseUrl || !supabaseKey) {
        throw new Error('Missing Supabase environment variables')
      }

      const supabase = createClient(supabaseUrl, supabaseKey)

      // If UPDATE, delete existing records linked to this message
      if (payload.type === 'UPDATE') {
        console.log('UPDATE event: Deleting existing records for message:', message.id)

        const deleteResults = await Promise.all([
          supabase.from('weight_records').delete().eq('message_id', message.id),
          supabase.from('meal_records').delete().eq('message_id', message.id),
          supabase.from('exercise_records').delete().eq('message_id', message.id),
        ])

        deleteResults.forEach((result, index) => {
          const tables = ['weight_records', 'meal_records', 'exercise_records']
          if (result.error) {
            console.error(`Error deleting from ${tables[index]}:`, result.error)
          } else {
            console.log(`Deleted existing records from ${tables[index]}`)
          }
        })
      }

      // 0. Re-fetch full row (webhook payload may omit columns like tags/metadata)
      const { data: fullRow, error: fetchErr } = await supabase
        .from('messages')
        .select('metadata, tags')
        .eq('id', message.id)
        .maybeSingle()
      if (fetchErr) {
        console.error('Failed to re-fetch message row:', fetchErr)
      } else if (fullRow) {
        message.metadata = fullRow.metadata
        message.tags = fullRow.tags
      }

      // 1. Determine tag — 送信側付与のtagsを正準とし、無ければcontentから解析
      const tagData = parseTagFromTags(message.tags, message.content) ?? parseTag(message.content)

      if (tagData) {
        // 2. tags が空のときだけ補完（送信側付与を主とする。空でなければ上書きしない）
        if (!message.tags || message.tags.length === 0) {
          const { error: updateError } = await supabase.from('messages').update({
            tags: [tagData.fullTag]
          }).eq('id', message.id)
          if (updateError) {
            console.error('Error backfilling message tags:', updateError)
          }
        }

        // 3. Create specific record based on category
        const commonData = {
          client_id: message.sender_id, // Assuming sender is the client
          source: 'message',
          message_id: message.id,
          recorded_at: message.created_at,
          notes: tagData.remainingContent,
          image_urls: message.image_urls || [], // 画像URLを追加
          meal_estimation: message.metadata?.meal_estimation, // ← 追加
        }

        let createResult;
        if (tagData.category === '食事') {
          createResult = await createMealRecord(supabase, commonData, tagData)
        } else if (tagData.category === '体重') {
          createResult = await createWeightRecord(supabase, commonData, tagData)
        } else if (tagData.category === '運動') {
          createResult = await createExerciseRecord(supabase, commonData, tagData)
        }

        if (createResult && createResult.error) {
          console.error('Error creating record:', createResult.error)
        }
      } else {
        // UPDATE時にタグがない場合は削除のみで終了（既に削除済み）
        if (payload.type === 'UPDATE') {
          console.log('UPDATE: No tags found, existing records were deleted')
        }
      }

      // INSERT時のみメッセージ通知を送信（UPDATE時は送信しない）
      if (payload.type === 'INSERT') {
        await sendMessageNotification(supabase, message)
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Error processing webhook:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

/**
 * タグを解析する
 * @example
 * parseTag('#食事:昼食 サラダチキン')
 * // => { category: '食事', detail: '昼食', fullTag: '#食事:昼食', remainingContent: 'サラダチキン' }
 *
 * parseTag('#体重 65.2kg 順調です!')
 * // => { category: '体重', detail: undefined, fullTag: '#体重', remainingContent: '65.2kg 順調です!' }
 */
function parseTag(content: string) {
  // Matches #Category:Detail or #Category
  const match = content.match(/#(食事|運動|体重)(?::(.+?))?(?:\s|$)/)
  if (!match) return null

  return {
    category: match[1], // 食事, 運動, 体重
    detail: match[2], // 朝食, 筋トレ etc (undefined if not present)
    fullTag: match[0].trim(),
    remainingContent: content.replace(match[0], '').trim()
  }
}

/**
 * tags配列（#付き正準形）から tagData を構築する。送信側付与のtagsを正準として扱う。
 * @example parseTagFromTags(['#運動:完了'], '本日の…達成しました！🔥 消費カロリー: 300kcal')
 *   // => { category: '運動', detail: '完了', fullTag: '#運動:完了', remainingContent: '本日の…300kcal' }
 */
function parseTagFromTags(tags, content) {
  if (!tags || tags.length === 0) return null
  const fullTag = tags[0]
  const m = fullTag.match(/^#(食事|運動|体重)(?::(.+))?$/)
  if (!m) return null
  return {
    category: m[1],
    detail: m[2],
    fullTag,
    remainingContent: (content || '').replace(fullTag, '').trim(),
  }
}

/**
 * 食事記録を作成する
 *
 * タグから食事タイプを判定：
 * - #食事:朝食 → breakfast
 * - #食事:昼食 → lunch
 * - #食事:夕食 → dinner
 * - #食事:間食 or #食事 → snack
 */
async function createMealRecord(supabase, commonData, tagData) {
  let mealType = 'snack'
  if (tagData.detail) {
    if (tagData.detail.includes('朝')) mealType = 'breakfast'
    else if (tagData.detail.includes('昼')) mealType = 'lunch'
    else if (tagData.detail.includes('夕') || tagData.detail.includes('晩')) mealType = 'dinner'
  }

  // metadata.meal_estimation があれば PFC込みで保存
  // 上流（mobile送信パス + estimate-meal-nutrition）が形式を保証する想定だが、
  // 万一 metadata.meal_estimation が空オブジェクト等で届いた場合に
  // estimated_by_ai=true / PFC=NULL の矛盾レコードを生まないよう防御する
  const estimation = commonData.meal_estimation
  const hasValidEstimation =
    estimation &&
    typeof estimation.calories === 'number' &&
    Array.isArray(estimation.foods) &&
    estimation.foods.length > 0

  if (hasValidEstimation) {
    return await supabase.from('meal_records').insert({
      client_id: commonData.client_id,
      source: commonData.source,
      message_id: commonData.message_id,
      recorded_at: commonData.recorded_at,
      notes: commonData.notes,
      meal_type: mealType,
      images: commonData.image_urls,
      calories: estimation.calories,
      protein_g: estimation.protein_g,
      fat_g: estimation.fat_g,
      carbs_g: estimation.carbs_g,
      ai_foods: estimation.foods,
      estimated_by_ai: true,
      ai_source: typeof estimation.source === 'string' ? estimation.source : null,
    })
  }

  // 既存挙動（PFCなし）
  return await supabase.from('meal_records').insert({
    client_id: commonData.client_id,
    source: commonData.source,
    message_id: commonData.message_id,
    recorded_at: commonData.recorded_at,
    notes: commonData.notes,
    meal_type: mealType,
    images: commonData.image_urls,
  })
}

/**
 * 体重記録を作成する
 *
 * メッセージから体重値を抽出：
 * - "#体重 65.2kg" → 65.2
 * - "#体重 65.2kg 順調です!" → 65.2
 * - "#体重 65.2" → 65.2 (kg省略可)
 *
 * 作成後、目標達成判定を行う
 */
async function createWeightRecord(supabase, commonData, tagData) {
  // Parse weight value from the remaining content
  // 強化版: "65.2kg" や "65.2 kg" や "65.2" にマッチ
  const weightMatch = commonData.notes.match(/(\d+\.?\d*)\s*(?:kg|キロ)?/i)
  if (!weightMatch) {
    console.log('Could not parse weight from notes:', commonData.notes)
    return { error: 'Could not parse weight value from message (e.g. "65.2kg")' }
  }

  const weight = parseFloat(weightMatch[1])

  // 体重の妥当性チェック（20kg〜300kg）
  if (weight < 20 || weight > 300) {
    console.log('Invalid weight value:', weight)
    return { error: `Invalid weight value: ${weight}kg (must be between 20-300kg)` }
  }

  console.log('Creating weight record:', weight, 'kg')

  // 体重記録を作成
  const { data, error } = await supabase.from('weight_records').insert({
    client_id: commonData.client_id,
    source: commonData.source,
    message_id: commonData.message_id,
    recorded_at: commonData.recorded_at,
    notes: commonData.notes,
    weight: weight,
  }).select()

  if (error) {
    return { error }
  }

  // 目標達成判定を呼ぶ
  try {
    const { data: isAchieved, error: rpcError } = await supabase.rpc('check_goal_achievement', {
      p_client_id: commonData.client_id,
      p_current_weight: weight
    })

    if (rpcError) {
      console.error('Error checking goal achievement:', rpcError)
    } else if (isAchieved) {
      console.log('🎉 Goal achieved! Client:', commonData.client_id)
      await sendGoalAchievementNotification(supabase, commonData.client_id, commonData.message_id)
    } else {
      // 達成率を計算してログに出力
      const { data: rate } = await supabase.rpc('calculate_achievement_rate', {
        p_client_id: commonData.client_id,
        p_current_weight: weight
      })
      console.log('Achievement rate:', rate, '%')
    }
  } catch (e) {
    console.error('Error in goal achievement check:', e)
  }

  return { data, error: null }
}

/**
 * 運動記録を作成する
 *
 * タグから運動タイプを判定：
 * - #運動:筋トレ → strength_training
 * - #運動:有酸素 → cardio
 * - #運動:ランニング → running
 * - #運動:ウォーキング → walking
 * - #運動 → other (本文から推測)
 *
 * ※ duration/distance は NULL 可（必須制約は削除済み）
 */
async function createExerciseRecord(supabase, commonData, tagData) {
  let exerciseType = 'other'
  if (tagData.detail) {
    if (tagData.detail.includes('筋トレ') || tagData.detail.includes('筋肉')) {
      exerciseType = 'strength_training'
    } else if (tagData.detail.includes('有酸素')) {
      exerciseType = 'cardio'
    } else if (tagData.detail.includes('ランニング') || tagData.detail.includes('走')) {
      exerciseType = 'running'
    } else if (tagData.detail.includes('ウォーキング') || tagData.detail.includes('歩')) {
      exerciseType = 'walking'
    } else if (tagData.detail.includes('自転車') || tagData.detail.includes('サイクリング')) {
      exerciseType = 'cycling'
    } else if (tagData.detail.includes('水泳') || tagData.detail.includes('プール')) {
      exerciseType = 'swimming'
    } else if (tagData.detail.includes('ヨガ')) {
      exerciseType = 'yoga'
    } else if (tagData.detail.includes('ピラティス')) {
      exerciseType = 'pilates'
    }
  }

  // 本文からも運動タイプを推測（タグに詳細がない＝'#運動'単体のときだけ）
  // detail がある場合（例: '完了'）は notes からの推測は不要かつ有害
  // （達成メッセージの「ワークアウトプラン」が「ラン」に誤マッチする等）
  if (exerciseType === 'other' && !tagData.detail && commonData.notes) {
    const notes = commonData.notes
    if (notes.includes('走') || notes.includes('ラン')) exerciseType = 'running'
    else if (notes.includes('歩')) exerciseType = 'walking'
    else if (notes.includes('筋トレ') || notes.includes('ウェイト')) exerciseType = 'strength_training'
  }

  // 時間を本文から抽出（オプション）
  let duration = null
  const durationMatch = commonData.notes.match(/(\d+)\s*(?:分|min)/i)
  if (durationMatch) {
    duration = parseInt(durationMatch[1])
  }

  // 距離を本文から抽出（オプション）
  let distance = null
  const distanceMatch = commonData.notes.match(/(\d+\.?\d*)\s*(?:km|キロ(?!カロリー))/i);
  if (distanceMatch) {
    distance = parseFloat(distanceMatch[1])
  }

  // カロリーを本文から抽出（オプション）
  // 例: "300kcal", "300カロリー", "300 kcal"
  let calories = null
  const caloriesMatch = commonData.notes.match(/(\d+\.?\d*)\s*(?:kcal|カロリー|キロカロリー|cal)/i);
  if (caloriesMatch) {
    calories = parseFloat(caloriesMatch[1])
  }

  console.log('Creating exercise record:', exerciseType, 'duration:', duration, 'min', 'distance:', distance, 'km', 'calories:', calories, 'kcal')

  return await supabase.from('exercise_records').insert({
    client_id: commonData.client_id,
    source: commonData.source,
    message_id: commonData.message_id,
    recorded_at: commonData.recorded_at,
    memo: commonData.notes,
    exercise_type: exerciseType,
    duration: duration, // テキストから抽出した時間（分）
    distance: distance, // 抽出できた場合のみ設定
    calories: calories, // テキストから抽出したカロリー
    images: commonData.image_urls, // 画像URLを保存
  })
}

/**
 * メッセージ受信者にプッシュ通知を送信する
 *
 * 実送信は統一ディスパッチャ（_shared/push.ts）に委譲。
 * 冪等化・通知設定・トークン解決（device_tokens 優先 + fcm_token フォールバック）・
 * FCM / Web Push 送信・無効トークン掃除・notification_logs 記録はディスパッチャが担う。
 */
async function sendMessageNotification(
  supabase: any,
  message: any
): Promise<void> {
  try {
    const receiverId = message.receiver_id
    const receiverType = message.receiver_type // 'client' or 'trainer'

    if (!receiverId || !receiverType) {
      console.log('[push] No receiver info, skipping notification')
      return
    }

    // 送信者名を取得（通知タイトル用）
    const senderType = message.sender_type // 'client' or 'trainer'
    const senderTable = senderType === 'client' ? 'clients' : 'trainers'
    const senderIdColumn = senderType === 'client' ? 'client_id' : 'id'

    const { data: sender } = await supabase
      .from(senderTable)
      .select('name')
      .eq(senderIdColumn, message.sender_id)
      .maybeSingle()

    const senderName = sender?.name || '不明'
    const bodyText = message.content?.length > 50
      ? message.content.substring(0, 50) + '...'
      : message.content || ''

    await sendNotification({
      supabaseAdmin: supabase,
      userId: receiverId,
      userType: receiverType,
      kind: 'message',
      title: `${senderName}からのメッセージ`,
      body: bodyText,
      data: { type: 'message', messageId: message.id },
      dedupKey: `message:${message.id}`,
    })
  } catch (e) {
    console.error('[push] Error sending message notification:', e)
  }
}

/**
 * 目標達成通知を送信する
 *
 * 実送信は統一ディスパッチャ（_shared/push.ts）に委譲。
 * dedupKey はメッセージIDベース（同一メッセージの再解析で二重送信しない）。
 */
async function sendGoalAchievementNotification(
  supabase: any,
  clientId: string,
  messageId: string
): Promise<void> {
  try {
    await sendNotification({
      supabaseAdmin: supabase,
      userId: clientId,
      userType: 'client',
      kind: 'goal_achievement',
      title: '目標達成！🎉',
      body: '体重目標を達成しました！おめでとうございます！',
      data: { type: 'goal_achievement', clientId },
      dedupKey: `goal:${messageId}`,
    })
  } catch (e) {
    console.error('[push] Error sending goal achievement notification:', e)
  }
}
