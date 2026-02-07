// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
    try {
        const payload = await req.json()
        console.log('Received payload:', JSON.stringify(payload))

        // Check if this is a webhook payload (INSERT or UPDATE on messages)
        if ((payload.type === 'INSERT' || payload.type === 'UPDATE') && payload.table === 'messages') {
            const message = payload.record
            // Skip if message is from system or doesn't have content
            if (!message.content) {
                console.log('Skipping message: No content')
                return new Response(JSON.stringify({ skipped: true }), { headers: { 'Content-Type': 'application/json' } })
            }

            console.log('Processing message:', payload.type, message.id, message.content)

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

            // 1. Parse Tag
            const tagData = parseTag(message.content)

            if (tagData) {
                console.log('Tag detected:', JSON.stringify(tagData))

                // 2. Update message with normalized tags
                const { error: updateError } = await supabase.from('messages').update({
                    tags: [tagData.fullTag]
                }).eq('id', message.id)

                if (updateError) {
                    console.error('Error updating message tags:', updateError)
                } else if (payload.type === 'UPDATE') {
                    console.log('UPDATE: Message tags updated (this should not trigger another webhook)')
                }

                // 3. Create specific record based on category
                const commonData = {
                    client_id: message.sender_id, // Assuming sender is the client
                    source: 'message',
                    message_id: message.id,
                    recorded_at: message.created_at,
                    notes: tagData.remainingContent,
                    image_urls: message.image_urls || [], // 画像URLを追加
                }

                let createResult;
                if (tagData.category === '食事') {
                    createResult = await createMealRecord(supabase, commonData, tagData)
                } else if (tagData.category === '体重') {
                    createResult = await createWeightRecord(supabase, commonData, tagData)
                } else if (tagData.category === '運動') {
                    createResult = await createExerciseRecord(supabase, commonData, tagData)
                } else {
                    console.log('Unknown category:', tagData.category)
                }

                if (createResult && createResult.error) {
                    console.error('Error creating record:', createResult.error)
                } else {
                    console.log('Record created successfully')
                }
            } else {
                console.log('No tag detected in message')
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

    console.log('Creating meal record:', mealType, 'with', commonData.image_urls?.length || 0, 'images')

    return await supabase.from('meal_records').insert({
        client_id: commonData.client_id,
        source: commonData.source,
        message_id: commonData.message_id,
        recorded_at: commonData.recorded_at,
        notes: commonData.notes,
        meal_type: mealType,
        images: commonData.image_urls, // 画像URLを保存
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
            await sendGoalAchievementNotification(supabase, commonData.client_id)
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
 * ※ DB制約: duration または distance が必須
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

    // 本文からも運動タイプを推測（タグに詳細がない場合）
    if (exerciseType === 'other' && commonData.notes) {
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
    const distanceMatch = commonData.notes.match(/(\d+\.?\d*)\s*(?:km|キロ)/i)
    if (distanceMatch) {
        distance = parseFloat(distanceMatch[1])
    }

    // カロリーを本文から抽出（オプション）
    // 例: "300kcal", "300カロリー", "300 kcal"
    let calories = null
    const caloriesMatch = commonData.notes.match(/(\d+\.?\d*)\s*(?:kcal|カロリー|cal)/i)
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
 * FCM HTTP v1 APIで通知を送信する
 */
async function sendFCMNotification(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  // 1. サービスアカウントキーを取得
  const serviceAccountKeyJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_KEY')
  if (!serviceAccountKeyJson) {
    console.log('[FCM] FIREBASE_SERVICE_ACCOUNT_KEY not set, skipping notification')
    return
  }

  const serviceAccount = JSON.parse(serviceAccountKeyJson)
  const projectId = serviceAccount.project_id

  // 2. JWT生成（RS256）
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  // Base64URL encode
  const encode = (obj: unknown) => {
    const json = JSON.stringify(obj)
    const bytes = new TextEncoder().encode(json)
    return btoa(String.fromCharCode(...bytes))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  }

  const unsignedToken = `${encode(header)}.${encode(payload)}`

  // RS256署名（Deno Web Crypto API）
  const pemContents = serviceAccount.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '')

  const binaryDer = Uint8Array.from(atob(pemContents), (c: string) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  )

  const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

  const jwt = `${unsignedToken}.${signatureBase64}`

  // 3. Google OAuth2 アクセストークン取得
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const tokenData = await tokenResponse.json()
  if (!tokenData.access_token) {
    console.error('[FCM] Failed to get access token:', tokenData)
    return
  }

  // 4. FCM HTTP v1 APIで通知送信
  const fcmResponse = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tokenData.access_token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          data,
          android: {
            priority: 'high',
            notification: {
              channel_id: 'high_importance_channel',
            },
          },
          apns: {
            payload: {
              aps: {
                alert: { title, body },
                sound: 'default',
                badge: 1,
              },
            },
          },
        },
      }),
    }
  )

  const fcmResult = await fcmResponse.json()

  if (!fcmResponse.ok) {
    console.error('[FCM] Error sending notification:', fcmResult)
    // UNREGISTERED or NOT_FOUND → トークン無効、DBから削除すべき
    if (fcmResult?.error?.details?.some((d: any) =>
      d.errorCode === 'UNREGISTERED' || d.errorCode === 'NOT_FOUND'
    )) {
      console.log('[FCM] Token is invalid, should be cleared from DB')
      return // 呼び出し元でトークンクリアを処理
    }
  } else {
    console.log('[FCM] Notification sent successfully:', fcmResult)
  }
}

/**
 * メッセージ受信者にプッシュ通知を送信する
 */
async function sendMessageNotification(
  supabase: any,
  message: any
): Promise<void> {
  try {
    const receiverId = message.receiver_id
    const receiverType = message.receiver_type // 'client' or 'trainer'

    if (!receiverId || !receiverType) {
      console.log('[FCM] No receiver info, skipping notification')
      return
    }

    // 受信者のFCMトークンを取得
    const table = receiverType === 'client' ? 'clients' : 'trainers'
    const idColumn = receiverType === 'client' ? 'client_id' : 'id'

    const { data: receiver, error } = await supabase
      .from(table)
      .select('fcm_token, name')
      .eq(idColumn, receiverId)
      .maybeSingle()

    if (error || !receiver?.fcm_token) {
      console.log('[FCM] No FCM token for receiver:', receiverId)
      return
    }

    // 送信者名を取得
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

    await sendFCMNotification(
      receiver.fcm_token,
      `${senderName}からのメッセージ`,
      bodyText,
      { type: 'message', messageId: message.id }
    )
  } catch (e) {
    console.error('[FCM] Error sending message notification:', e)
  }
}

/**
 * 目標達成通知を送信する
 */
async function sendGoalAchievementNotification(
  supabase: any,
  clientId: string
): Promise<void> {
  try {
    const { data: client, error } = await supabase
      .from('clients')
      .select('fcm_token, name')
      .eq('client_id', clientId)
      .maybeSingle()

    if (error || !client?.fcm_token) {
      console.log('[FCM] No FCM token for client:', clientId)
      return
    }

    await sendFCMNotification(
      client.fcm_token,
      '目標達成！🎉',
      '体重目標を達成しました！おめでとうございます！',
      { type: 'goal_achievement', clientId }
    )
  } catch (e) {
    console.error('[FCM] Error sending goal achievement notification:', e)
  }
}
