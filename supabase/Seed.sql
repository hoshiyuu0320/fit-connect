-- =============================================
-- FIT-CONNECT Seed Data
-- =============================================
-- このファイルは supabase db reset 時に自動的に実行されます
-- 実行順序: schema.sql → seed.sql

-- =============================================
-- 1. トレーナーのプロフィール作成
-- =============================================
-- Supabase Auth互換のユーザー作成
-- パスワード: password123

-- auth.users にトレーナーユーザーを作成
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  confirmation_sent_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'yamada@fitconnect.jp',
  -- パスワード password123 のbcryptハッシュ（正しいハッシュ）
  '$2b$10$fCroF9xXzza.6/SE1XV9auuIjOUqY4bmEPl4PuogUY6oPnk/T2l7q',
  NOW(),
  NOW(),
  NOW(),
  NOW(),
  '{"provider":"email","providers":["email"]}',
  '{"name":"山田太郎"}',
  FALSE,
  '',
  '',
  '',
  ''
);

-- auth.identities にもエントリを追加（Supabase Authが正常に動作するために必要）
INSERT INTO auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  jsonb_build_object(
    'sub', '11111111-1111-1111-1111-111111111111',
    'email', 'yamada@fitconnect.jp'
  ),
  'email',
  NOW(),
  NOW(),
  NOW()
);

-- トレーナーのプロフィール
-- 2026-07-10 修復: profiles は 20260131000001 で trainers へ移行・DROP されたため trainers へ INSERT
INSERT INTO public.trainers (id, name, email) VALUES
  ('11111111-1111-1111-1111-111111111111', '山田太郎', 'yamada@fitconnect.jp');

-- =============================================
-- 1.5 クライアント用の認証ユーザー作成
-- =============================================
-- auth.users にクライアントユーザーを作成
-- パスワード: password123
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  confirmation_sent_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'sato@test.com',
  -- パスワード password123 のbcryptハッシュ
  '$2b$10$fCroF9xXzza.6/SE1XV9auuIjOUqY4bmEPl4PuogUY6oPnk/T2l7q',
  NOW(),
  NOW(),
  NOW(),
  NOW(),
  '{"provider":"email","providers":["email"]}',
  '{"name":"佐藤花子"}',
  FALSE,
  '',
  '',
  '',
  ''
);

-- auth.identities にもエントリを追加
INSERT INTO auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  '22222222-2222-2222-2222-222222222222',
  '22222222-2222-2222-2222-222222222222',
  jsonb_build_object(
    'sub', '22222222-2222-2222-2222-222222222222',
    'email', 'sato@test.com'
  ),
  'email',
  NOW(),
  NOW(),
  NOW()
);

-- クライアントのプロフィール
-- 2026-07-10 修復: profiles は DROP 済み。クライアントは直後の public.clients INSERT で登録されるため不要

-- =============================================
-- 2. クライアントの登録（トレーナーに紐づけ）
-- =============================================
INSERT INTO public.clients (
  client_id,
  name,
  trainer_id,
  line_user_id,
  gender,
  age,
  occupation,
  height,
  target_weight,
  initial_weight,
  purpose,
  goal_description,
  goal_deadline,
  created_at
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  '佐藤花子',
  '11111111-1111-1111-1111-111111111111',
  'U1234567890abcdef',
  'female',
  28,
  '会社員（事務職）',
  160,
  52,
  58,
  'diet',
  '3ヶ月で-6kg！結婚式までに健康的に体を絞りたい。特にお腹周りと二の腕が気になっています。',
  CURRENT_DATE + INTERVAL '90 days',
  CURRENT_TIMESTAMP - INTERVAL '7 days'
);

-- =============================================
-- 3. 食事記録（3日間分）
-- =============================================
-- 3日前の食事記録
INSERT INTO public.meal_records (
  id,
  client_id,
  meal_type,
  notes,
  calories,
  images,
  recorded_at,
  source
) VALUES
  -- 3日前
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'breakfast', 
   '全粒粉パン、スクランブルエッグ、サラダ、ヨーグルト', 450, 
   ARRAY['meals/breakfast_001.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '7 hours', 'message'),
  
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'lunch', 
   'グリルチキンサラダ、玄米おにぎり、味噌汁', 520, 
   ARRAY['meals/lunch_001.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '12 hours', 'message'),
  
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'dinner', 
   '鮭のムニエル、温野菜、もち麦ごはん、わかめスープ', 580, 
   ARRAY['meals/dinner_001.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '19 hours', 'message'),
  
  -- 2日前
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'breakfast', 
   'オートミール、バナナ、プロテインシェイク', 380, 
   ARRAY['meals/breakfast_002.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '7 hours 30 minutes', 'message'),
  
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'lunch', 
   '豆腐ハンバーグ定食、サラダ、ひじき煮', 550, 
   ARRAY['meals/lunch_002.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '12 hours 30 minutes', 'message'),
  
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'snack', 
   'ミックスナッツ、ギリシャヨーグルト', 200, 
   NULL, 
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '15 hours', 'message'),
  
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'dinner', 
   '鶏むね肉のトマト煮込み、ブロッコリー、もち麦ごはん', 520, 
   ARRAY['meals/dinner_002.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '19 hours 30 minutes', 'message'),
  
  -- 1日前
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'breakfast', 
   '納豆ごはん、焼き魚、みそ汁、サラダ', 420, 
   ARRAY['meals/breakfast_003.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '7 hours', 'message'),
  
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'lunch', 
   'サーモンアボカド丼、野菜スープ', 600, 
   ARRAY['meals/lunch_003.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '12 hours', 'message'),
  
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'dinner', 
   '豆乳鍋（鶏肉、豆腐、野菜たっぷり）、雑穀米', 480, 
   ARRAY['meals/dinner_003.jpg', 'meals/dinner_003_2.jpg'], 
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '19 hours', 'message');

-- =============================================
-- 4. 体重記録（3日間分 + 初回計測）
-- =============================================
INSERT INTO public.weight_records (
  id,
  client_id,
  weight,
  recorded_at,
  notes,
  source
) VALUES
  -- 初回計測（7日前）
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 58.0, 
   CURRENT_TIMESTAMP - INTERVAL '7 days' + INTERVAL '10 hours', 
   '初回計測。ここからスタート！', 'manual'),
  
  -- 3日前
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 57.5, 
   CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '6 hours 30 minutes', 
   '朝イチ計測。順調に減ってる！', 'message'),
  
  -- 2日前
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 57.3, 
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '6 hours 45 minutes', 
   '昨日より-0.2kg。良い感じ♪', 'message'),
  
  -- 1日前
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 57.2, 
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '6 hours 30 minutes', 
   'キープできてる！', 'message');

-- =============================================
-- 5. 運動記録（3日間分）
-- =============================================
INSERT INTO public.exercise_records (
  id,
  client_id,
  exercise_type,
  duration,
  distance,
  calories,
  memo,
  recorded_at,
  source
) VALUES
  -- 3日前：有酸素運動
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'running', 
   30, 4.2, 250, 
   '朝ランニング。気持ちよく走れました！皇居周り一周。', 
   CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '6 hours', 'message'),
  
  -- 3日前：筋トレ
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'strength_training', 
   45, NULL, 180, 
   '下半身トレーニング：スクワット 15回×3セット、ランジ 12回×3セット、レッグカール', 
   CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '18 hours', 'message'),
  
  -- 2日前：有酸素運動
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'cycling', 
   40, 8.5, 280, 
   'サイクリング。多摩川沿いを走りました。天気も良くて最高！', 
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '9 hours', 'message'),
  
  -- 2日前：筋トレ
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'strength_training', 
   40, NULL, 150, 
   '上半身トレーニング：腕立て伏せ 10回×3セット、ダンベルカール 12回×3セット、プランク 1分×3', 
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '19 hours', 'message'),
  
  -- 1日前：有酸素運動
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'walking', 
   50, 4.0, 200, 
   'ウォーキング。駅まで歩いて往復。毎日の積み重ねが大事！', 
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '8 hours', 'message'),
  
  -- 1日前：筋トレ
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'strength_training', 
   50, NULL, 200, 
   '全身トレーニング：バーピー 10回×3セット、マウンテンクライマー 30秒×3セット、体幹トレ', 
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '19 hours 30 minutes', 'message');

-- =============================================
-- 7. メッセージのやり取り（3ラリー）
-- =============================================
INSERT INTO public.messages (
  sender_id,
  receiver_id,
  sender_type,
  receiver_type,
  content,
  tags,
  image_urls,
  created_at
) VALUES
  -- 1回目のやり取り（2日前）
  (
   '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111',
   'client', 'trainer',
   '山田先生、おはようございます！今朝の体重は57.5kgでした💪 朝ごはんも頑張りました！',
   ARRAY['#体重', '#食事:朝食'],
   ARRAY['meals/breakfast_002.jpg'],
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '7 hours 30 minutes'),
  
  (
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'trainer', 'client',
   '佐藤さん、おはようございます！順調ですね👏 朝食のバランスも完璧です。この調子で頑張りましょう！',
   NULL,
   NULL,
   CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '8 hours'),
  
  -- 2回目のやり取り（1日前）
  (
   '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111',
   'client', 'trainer',
   '今日はランチにサーモンアボカド丼を食べました🐟🥑 タンパク質と良質な脂質が取れて満足です！',
   ARRAY['#食事:昼食'],
   ARRAY['meals/lunch_003.jpg'],
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '12 hours 30 minutes'),
  
  (
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'trainer', 'client',
   'いいですね！サーモンは良質なタンパク質とオメガ3が豊富で、ダイエット中に最適です✨ アボカドも適量なら全然OK。栄養バランスを考えた素晴らしい選択です👍',
   NULL,
   NULL,
   CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '13 hours'),
  
  -- 3回目のやり取り（今日）
  (
   '22222222-2222-2222-2222-222222222222',
   '11111111-1111-1111-1111-111111111111',
   'client', 'trainer',
   '先生、質問なんですが、仕事終わりのトレーニングのタイミングで何か軽く食べた方がいいですか？🤔 空腹だとパワー出なくて...',
   NULL,
   NULL,
   CURRENT_TIMESTAMP - INTERVAL '3 hours'),
  
  (
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'trainer', 'client',
   '良い質問ですね！トレーニング1時間前にバナナ🍌やプロテインバーなど、消化の良い炭水化物を少量摂るのがおすすめです。エネルギー補給になりつつ、胃に負担もかかりません。次のセッションで詳しく説明しますね！',
   NULL,
   NULL,
   CURRENT_TIMESTAMP - INTERVAL '2 hours 30 minutes');

-- =============================================
-- 8. トレーナーのスケジュール登録（今日の日付）
-- =============================================
INSERT INTO public.sessions (
  id,
  trainer_id,
  client_id,
  session_date,
  duration_minutes,
  status,
  session_type,
  memo
) VALUES
  -- 今日のセッション（午前）
  (gen_random_uuid(),
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   CURRENT_DATE + INTERVAL '10 hours',
   60,
   'scheduled',
   '全身トレーニング',
   '下半身メインで。前回のフォーム確認とウェイト調整'),
  
  -- 今日のセッション（午後）
  (gen_random_uuid(),
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   CURRENT_DATE + INTERVAL '14 hours',
   60,
   'confirmed',
   '食事カウンセリング',
   '今週の食事内容振り返り。来週のメニュー提案'),
  
  -- 明日のセッション
  (gen_random_uuid(),
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   CURRENT_DATE + INTERVAL '1 day' + INTERVAL '10 hours',
   60,
   'scheduled',
   '上半身トレーニング',
   '二の腕集中メニュー'),
  
  -- 3日後のセッション
  (gen_random_uuid(),
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   CURRENT_DATE + INTERVAL '3 days' + INTERVAL '10 hours',
   60,
   'scheduled',
   '有酸素運動',
   'インターバルトレーニング導入'),
  
  -- 1週間後のセッション
  (gen_random_uuid(),
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   CURRENT_DATE + INTERVAL '7 days' + INTERVAL '10 hours',
   90,
   'scheduled',
   '総合評価',
   '1週間の成果測定。体重・体脂肪率・写真撮影。次週のプラン作成');

-- =============================================
-- ボーナス: チケット情報も追加
-- =============================================
INSERT INTO public.tickets (
  id,
  client_id,
  ticket_name,
  ticket_type,
  total_sessions,
  remaining_sessions,
  valid_from,
  valid_until,
  created_at
) VALUES
  (gen_random_uuid(),
   '22222222-2222-2222-2222-222222222222',
   '3ヶ月集中コース（24回券）',
   'premium_3month',
   24,
   18,  -- 6回消化済み
   CURRENT_DATE - INTERVAL '21 days',
   CURRENT_DATE + INTERVAL '69 days',
   CURRENT_TIMESTAMP - INTERVAL '21 days');

-- =============================================
-- 完了メッセージ
-- =============================================
-- Seed data insertion completed successfully!
--
-- 作成されたデータ:
-- - トレーナー: 1名（山田太郎） - yamada@fitconnect.jp / password123
-- - クライアント: 1名（佐藤花子） - sato@test.com / password123
-- - 食事記録: 10件（3日間分）
-- - 体重記録: 4件（初回 + 3日間分）
-- - 運動記録: 6件（3日間分：有酸素3回、筋トレ3回）
-- - メッセージ: 6件（3ラリー）
-- - セッション: 5件（今日〜1週間後）
-- - チケット: 1件
--
-- ログイン情報:
-- [トレーナー] yamada@fitconnect.jp / password123
-- [クライアント] sato@test.com / password123