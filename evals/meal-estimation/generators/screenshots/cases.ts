/**
 * 合成スクリーンショットのケース定義（データのみ）。
 *
 * - 画面に描画する数値はすべてここから来る。期待値（expected）は generate.ts が
 *   同じデータから導出するので、描画内容と正解が食い違うことはない。
 * - アプリ名はすべて架空（ごはんログ / ミールノート / MealDiary / そらもよう / トークル / てくてくメーター）。
 * - 乱数は使わない。値はすべて手書きの固定値。
 */

export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack'
export type Theme = 'light' | 'dark'

/** 1 品目。kcal は整数、P/F/C は整数（decimals レコードのみ小数第1位まで） */
export interface FoodItem {
  name: string
  amount: string
  kcal: number
  p: number
  f: number
  c: number
}

/** 1 食分の記録。画面に出す小計・合計は foods の合計（小数は 0.1 単位で合算） */
export interface MealRecord {
  meal: MealType
  /** 食事の記録時刻 'HH:MM'（24h） */
  time: string
  foods: FoodItem[]
  /** true => グラムを小数第1位で表示（kcal は整数のまま） */
  decimals?: boolean
  /** ミールノートの「栄養」タブにだけ出す追加栄養素（ディストラクタ） */
  extras?: { fiber: number; salt: number }
}

interface ScreenBase {
  theme?: Theme
  /** ステータスバーの時計 'H:MM' */
  clock: string
  /** ステータスバーのバッテリー残量 % */
  battery: number
  /** アプリ内に表示する日付 YYYY-MM-DD */
  date: string
  /** 小さい文字・詰まったレイアウト */
  dense?: boolean
}

export interface WeatherData {
  place: string
  now: number
  condition: string
  high: number
  low: number
  hourly: { hour: string; icon: WeatherIcon; temp: number; pop: number }[]
  daily: { label: string; icon: WeatherIcon; high: number; low: number; pop: number }[]
  humidity: number
  wind: string
  uv: number
  pressure: number
}
export type WeatherIcon = 'sun' | 'partly' | 'cloud' | 'rain'

export interface ChatData {
  partner: string
  unread: number
  messages: { from: 'me' | 'them'; text: string; time: string; read?: boolean }[]
}

export interface StepsData {
  steps: number
  goal: number
  distanceKm: number
  burnedKcal: number
  activeMin: number
  fatBurnG: number
  week: { label: string; steps: number }[]
}

export interface DayGoal {
  kcal: number
  p: number
  f: number
  c: number
}

export type Screen =
  /** ごはんログ: 1食の画面（kcal リング + P/F/C 棒 + 品目ごとの kcal のみ） */
  | (ScreenBase & { layout: 'a-meal'; record: MealRecord; targetKcal: number; showTarget: boolean })
  /** ごはんログ: 記録タブ（品目と合計 kcal のみ。PFC なし） */
  | (ScreenBase & { layout: 'a-list'; record: MealRecord })
  /** ごはんログ: 栄養バランスタブ（PFC ドーナツ + グラム + kcal） */
  | (ScreenBase & { layout: 'a-nutrition'; record: MealRecord })
  /** ごはんログ: 1日のまとめ */
  | (ScreenBase & { layout: 'a-day'; records: MealRecord[]; targetKcal: number })
  /** ミールノート: 1食の詳細（品目ごとに kcal と P/F/C） */
  | (ScreenBase & { layout: 'b-meal'; record: MealRecord; totalsPosition: 'top' | 'bottom' })
  /** ミールノート: 食品タブ（品目と合計 kcal のみ） */
  | (ScreenBase & { layout: 'b-list'; record: MealRecord })
  /** ミールノート: 栄養タブ（PFC 比率バー + 栄養素表） */
  | (ScreenBase & { layout: 'b-nutrition'; record: MealRecord })
  /** ミールノート: 1日の記録 */
  | (ScreenBase & { layout: 'b-day'; records: MealRecord[]; totalPosition: 'top' | 'bottom' })
  /** MealDiary: 1食の表（Calories/Protein/Fat/Carbs） */
  | (ScreenBase & { layout: 'c-meal'; record: MealRecord; dailyGoal?: { goal: number; otherMealsKcal: number } })
  /** MealDiary: Diary（品目と Calories のみ） */
  | (ScreenBase & { layout: 'c-list'; record: MealRecord })
  /** MealDiary: Nutrition > Macros（ドーナツ + グラム + %） */
  | (ScreenBase & { layout: 'c-nutrition'; record: MealRecord })
  /** MealDiary: 1日の表（食事ごとの小計 + Daily Total + Goal + Remaining） */
  | (ScreenBase & { layout: 'c-day'; records: MealRecord[]; goal: DayGoal })
  | (ScreenBase & { layout: 'weather'; data: WeatherData })
  | (ScreenBase & { layout: 'chat'; data: ChatData })
  | (ScreenBase & { layout: 'steps'; data: StepsData })

export type CaseKind = 'single' | 'day-view' | 'two-image' | 'mismatch' | 'non-meal'

export interface CaseSpec {
  id: string
  kind: CaseKind
  meal_type: MealType
  content: string
  /** 画面に出ている架空アプリ名（参考情報） */
  app_name: string | null
  /** 自動付与タグ（layout / kind / dark / dense / decimal / english）以外に付けるタグ */
  extraTags?: string[]
  screens: Screen[]
}

// ---------------------------------------------------------------------------
// 食品ライブラリ（1人前の値。kcal ≈ 4P + 9F + 4C になるよう調整済み）
// ---------------------------------------------------------------------------

const f = (name: string, amount: string, kcal: number, p: number, fat: number, c: number): FoodItem => ({
  name,
  amount,
  kcal,
  p,
  f: fat,
  c,
})

const J = {
  genmai150: f('玄米ごはん', '150g', 228, 4, 1, 51),
  hakumai150: f('白ごはん', '150g', 234, 4, 0, 55),
  hakumai200: f('白ごはん', '200g', 312, 5, 0, 74),
  rice150: f('ライス', '150g', 234, 4, 0, 55),
  zenryuToast: f('全粒粉トースト', '6枚切り1枚', 158, 6, 3, 27),
  butterToast: f('バタートースト', '6枚切り1枚', 218, 6, 8, 30),
  hotcake: f('ホットケーキ', '2枚', 452, 12, 14, 70),
  onigiriSake: f('おにぎり(鮭)', '1個', 180, 5, 1, 38),
  inari: f('いなり寿司', '2個', 220, 5, 6, 36),

  torimune: f('鶏むね肉のグリル', '1枚(120g)', 176, 30, 5, 2),
  yakijake: f('焼き鮭', '1切れ(80g)', 136, 20, 6, 0),
  saba: f('鯖の塩焼き', '1切れ(80g)', 206, 17, 15, 0),
  shogayaki: f('豚の生姜焼き', '1人前', 315, 18, 22, 10),
  karaage: f('鶏の唐揚げ', '4個(120g)', 326, 20, 21, 13),
  hamburg: f('和風ハンバーグ', '1個(150g)', 378, 20, 26, 15),
  steak: f('ビーフステーキ', '200g', 498, 36, 38, 1),
  mabo: f('麻婆豆腐', '1人前', 300, 16, 21, 11),
  sasami: f('鶏ささみのソテー', '2本', 140, 26, 3, 2),
  saladChicken: f('サラダチキン(プレーン)', '1袋(110g)', 114, 25, 1, 1),
  bacon: f('ベーコン', '2枚', 160, 5, 15, 0),
  medamayaki: f('目玉焼き', '1個', 90, 6, 7, 0),

  oyakodon: f('親子丼', '1杯', 638, 30, 16, 92),
  curry: f('カレーライス', '1皿', 760, 18, 26, 112),
  zarusoba: f('ざるそば', '1人前', 330, 13, 2, 64),
  kakiage: f('かき揚げ', '1枚', 280, 4, 18, 25),
  ramen: f('醤油ラーメン', '1杯', 474, 20, 12, 70),
  gyoza: f('焼き餃子', '5個', 278, 11, 15, 24),
  saladPasta: f('サラダパスタ', '1パック', 360, 12, 14, 46),

  misoTofu: f('味噌汁(豆腐とわかめ)', '1杯', 42, 3, 1, 5),
  misoNameko: f('味噌汁(なめこ)', '1杯', 38, 2, 1, 5),
  misoAge: f('味噌汁(油揚げ)', '1杯', 60, 3, 3, 5),
  tonjiru: f('豚汁', '1杯', 110, 6, 6, 8),
  chukaSoup: f('中華スープ', '1杯', 30, 1, 1, 4),
  cornSoup: f('コーンスープ', '1杯', 92, 2, 4, 12),
  greenSalad: f('グリーンサラダ', '1皿', 68, 1, 5, 5),
  wafuSalad: f('サラダ(和風ドレッシング)', '1皿', 45, 1, 2, 6),
  ohitashi: f('ほうれん草のおひたし', '小鉢', 20, 2, 0, 3),
  hiyayakko: f('冷奴', '1/3丁', 56, 5, 3, 2),
  chikuzenni: f('筑前煮', '小鉢', 120, 6, 4, 15),
  natto: f('納豆', '1パック', 86, 7, 4, 6),
  harusame: f('春雨サラダ', '小鉢', 95, 2, 3, 15),
  kinpira: f('きんぴらごぼう', '小鉢', 80, 1, 4, 10),
  cabbage: f('キャベツの千切り', '50g', 12, 1, 0, 3),
  tsukemono: f('漬物', '小皿', 12, 0, 0, 3),
  fukujin: f('福神漬け', '小皿', 20, 0, 0, 5),
  potatoSalad: f('ポテトサラダ', '小鉢', 130, 2, 9, 11),
  brocco: f('ブロッコリー(ゆで)', '80g', 28, 3, 0, 4),
  dashimaki: f('だし巻き卵', '2切れ', 98, 6, 6, 5),

  scrambled: f('スクランブルエッグ', '卵2個分', 190, 12, 15, 1),
  yudetamago: f('ゆで卵', '1個', 71, 6, 5, 0),
  milk: f('牛乳', '200ml', 137, 7, 8, 10),
  banana: f('バナナ', '1本', 93, 1, 0, 22),
  greekYogurt: f('ギリシャヨーグルト(無糖)', '100g', 59, 10, 0, 4),
  sweetYogurt: f('ヨーグルト(加糖)', '1個', 98, 4, 3, 14),
  nuts: f('ミックスナッツ', '25g', 155, 5, 13, 5),
  proteinBar: f('プロテインバー', '1本', 199, 15, 9, 15),
  proteinShake: f('プロテインシェイク', '1杯', 120, 20, 2, 6),
  oatmeal: f('オートミール', '30g', 114, 4, 2, 21),
  latte: f('カフェラテ', 'Mサイズ', 120, 6, 6, 10),
  coffee: f('コーヒー(ブラック)', '1杯', 6, 0, 0, 1),
  yasaiJuice: f('野菜ジュース', '200ml', 68, 1, 0, 16),
  orangeJuice: f('オレンジジュース', '200ml', 84, 1, 0, 20),
}

const E = {
  chickenSalad: f('Grilled chicken salad', '1 bowl', 320, 32, 14, 16),
  wwBread: f('Whole wheat bread', '1 slice', 98, 4, 1, 18),
  minestrone: f('Minestrone soup', '1 cup', 110, 4, 3, 17),
  apple: f('Apple', '1 medium', 95, 0, 0, 25),
  whiteRice: f('White rice', '200 g', 312, 5, 0, 74),
  karaage: f('Karaage fried chicken', '4 pcs', 326, 20, 21, 13),
  potatoSalad: f('Potato salad', '1 side', 130, 2, 9, 11),
  cabbage: f('Shredded cabbage', '50 g', 12, 1, 0, 3),
  misoSoup: f('Miso soup', '1 bowl', 42, 3, 1, 5),
  pickles: f('Pickled radish', '3 slices', 10, 0, 0, 2),
  tamagoyaki: f('Tamagoyaki', '2 pcs', 98, 6, 6, 5),
  soySauce: f('Soy sauce', '1 tsp', 4, 0, 0, 1),
  mandarin: f('Mandarin orange', '1 small', 35, 0, 0, 9),
  greenTea: f('Green tea', '1 cup', 0, 0, 0, 0),
  oatmealMilk: f('Oatmeal with milk', '1 bowl', 254, 11, 10, 31),
  banana: f('Banana', '1 small', 93, 1, 0, 22),
  turkeySandwich: f('Turkey sandwich', '1 sandwich', 420, 28, 14, 46),
  vegSoup: f('Vegetable soup', '1 cup', 48, 2, 1, 8),
  salmonTeriyaki: f('Salmon teriyaki', '1 fillet', 306, 26, 14, 18),
  brownRice: f('Brown rice', '150 g', 228, 4, 1, 51),
  broccoli: f('Steamed broccoli', '80 g', 28, 3, 0, 4),
  proteinShake: f('Protein shake', '1 scoop', 120, 20, 2, 6),
  almonds: f('Almonds', '20 g', 125, 4, 11, 4),
  grilledSalmon: f('Grilled salmon', '1 fillet', 276, 30, 17, 0),
  spaghetti: f('Spaghetti bolognese', '1 plate', 650, 28, 22, 84),
  caesar: f('Caesar salad', '1 bowl', 210, 5, 17, 10),
  garlicBread: f('Garlic bread', '1 slice', 160, 4, 7, 20),
  icedLatte: f('Iced latte', '12 oz', 100, 5, 5, 8),
}

// ---------------------------------------------------------------------------
// 非食事画面のデータ
// ---------------------------------------------------------------------------

const WEATHER: WeatherData = {
  place: '東京都 渋谷区',
  now: 23,
  condition: '晴れ時々くもり',
  high: 26,
  low: 17,
  hourly: [
    { hour: '13時', icon: 'sun', temp: 24, pop: 0 },
    { hour: '14時', icon: 'sun', temp: 25, pop: 0 },
    { hour: '15時', icon: 'partly', temp: 25, pop: 10 },
    { hour: '16時', icon: 'partly', temp: 24, pop: 10 },
    { hour: '17時', icon: 'cloud', temp: 22, pop: 20 },
    { hour: '18時', icon: 'cloud', temp: 21, pop: 20 },
  ],
  daily: [
    { label: '今日', icon: 'partly', high: 26, low: 17, pop: 10 },
    { label: '10/10(土)', icon: 'sun', high: 25, low: 16, pop: 0 },
    { label: '10/11(日)', icon: 'cloud', high: 22, low: 16, pop: 30 },
    { label: '10/12(月)', icon: 'rain', high: 19, low: 15, pop: 80 },
    { label: '10/13(火)', icon: 'partly', high: 23, low: 14, pop: 20 },
  ],
  humidity: 58,
  wind: '北北西 3m/s',
  uv: 5,
  pressure: 1015,
}

const CHAT: ChatData = {
  partner: 'ゆうき',
  unread: 12,
  messages: [
    { from: 'them', text: 'おつかれ！今日のお昼どうする？', time: '11:52' },
    { from: 'me', text: '駅前の定食屋行かない？', time: '11:53', read: true },
    { from: 'them', text: 'いいね！あそこの唐揚げ定食おいしいよね', time: '11:54' },
    { from: 'them', text: 'ご飯大盛り無料だし笑', time: '11:54' },
    { from: 'me', text: 'ちなみに今日の日替わりは鯖の味噌煮らしい', time: '11:56', read: true },
    { from: 'them', text: 'それも捨てがたい…980円だっけ？', time: '11:57' },
    { from: 'me', text: 'たしか。12時半に改札前で！', time: '11:58', read: true },
    { from: 'them', text: '了解〜', time: '11:58' },
  ],
}

const STEPS: StepsData = {
  steps: 8432,
  goal: 10000,
  distanceKm: 5.9,
  burnedKcal: 312,
  activeMin: 72,
  fatBurnG: 21,
  week: [
    { label: '土', steps: 6210 },
    { label: '日', steps: 11840 },
    { label: '月', steps: 7350 },
    { label: '火', steps: 5980 },
    { label: '水', steps: 9120 },
    { label: '木', steps: 6870 },
    { label: '金', steps: 8432 },
  ],
}

// ---------------------------------------------------------------------------
// ケース
// ---------------------------------------------------------------------------

export const CASES: CaseSpec[] = [
  // ===== 1枚・1食（13件） =====
  {
    id: 'ss-001',
    kind: 'single',
    meal_type: 'lunch',
    content: '',
    app_name: 'ごはんログ',
    extraTags: ['distractor-target'],
    screens: [
      {
        layout: 'a-meal',
        clock: '12:48',
        battery: 76,
        date: '2026-10-07',
        targetKcal: 700,
        showTarget: true,
        record: { meal: 'lunch', time: '12:30', foods: [J.torimune, J.genmai150, J.misoTofu, J.greenSalad] },
      },
    ],
  },
  {
    id: 'ss-002',
    kind: 'single',
    meal_type: 'breakfast',
    content: '朝ごはんのスクショです',
    app_name: 'ごはんログ',
    extraTags: ['with-note'],
    screens: [
      {
        layout: 'a-meal',
        clock: '8:12',
        battery: 94,
        date: '2026-10-08',
        targetKcal: 600,
        showTarget: false,
        record: { meal: 'breakfast', time: '7:40', foods: [J.zenryuToast, J.scrambled, J.banana, J.latte] },
      },
    ],
  },
  {
    id: 'ss-003',
    kind: 'single',
    meal_type: 'dinner',
    content: '',
    app_name: 'ごはんログ',
    extraTags: ['distractor-target'],
    screens: [
      {
        layout: 'a-meal',
        theme: 'dark',
        clock: '20:21',
        battery: 41,
        date: '2026-10-06',
        targetKcal: 750,
        showTarget: true,
        record: {
          meal: 'dinner',
          time: '19:45',
          foods: [J.yakijake, J.hakumai150, J.tonjiru, J.ohitashi, J.hiyayakko],
        },
      },
    ],
  },
  {
    id: 'ss-004',
    kind: 'single',
    meal_type: 'snack',
    content: '',
    app_name: 'ごはんログ',
    screens: [
      {
        layout: 'a-meal',
        clock: '15:37',
        battery: 63,
        date: '2026-10-05',
        targetKcal: 400,
        showTarget: false,
        record: { meal: 'snack', time: '15:20', foods: [J.greekYogurt, J.nuts, J.proteinBar] },
      },
    ],
  },
  {
    id: 'ss-005',
    kind: 'single',
    meal_type: 'lunch',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['totals-top'],
    screens: [
      {
        layout: 'b-meal',
        clock: '13:05',
        battery: 58,
        date: '2026-10-07',
        totalsPosition: 'top',
        record: { meal: 'lunch', time: '12:20', foods: [J.oyakodon, J.misoNameko, J.tsukemono] },
      },
    ],
  },
  {
    id: 'ss-006',
    kind: 'single',
    meal_type: 'dinner',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['totals-bottom'],
    screens: [
      {
        layout: 'b-meal',
        clock: '19:52',
        battery: 37,
        date: '2026-10-04',
        totalsPosition: 'bottom',
        record: { meal: 'dinner', time: '19:10', foods: [J.shogayaki, J.cabbage, J.hakumai200, J.kinpira] },
      },
    ],
  },
  {
    id: 'ss-007',
    kind: 'single',
    meal_type: 'breakfast',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['totals-top'],
    screens: [
      {
        layout: 'b-meal',
        theme: 'dark',
        clock: '7:24',
        battery: 100,
        date: '2026-10-08',
        totalsPosition: 'top',
        record: { meal: 'breakfast', time: '7:05', foods: [J.oatmeal, J.milk, J.yudetamago, J.proteinShake] },
      },
    ],
  },
  {
    // 小数グラム: 合計 P 41.7 / F 14.6 / C 53.8 → 正解は切り捨てで 41 / 14 / 53
    id: 'ss-008',
    kind: 'single',
    meal_type: 'lunch',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['totals-top'],
    screens: [
      {
        layout: 'b-meal',
        clock: '12:41',
        battery: 69,
        date: '2026-10-02',
        totalsPosition: 'top',
        record: {
          meal: 'lunch',
          time: '12:15',
          decimals: true,
          foods: [
            f('サラダチキン(ハーブ)', '1袋(110g)', 121, 24.8, 1.9, 1.6),
            f('玄米おにぎり(鮭)', '1個', 186, 5.4, 1.8, 37.6),
            f('ブロッコリーとゆで卵のサラダ', '1パック', 148, 9.7, 10.0, 5.3),
            f('野菜スープ', '1杯', 51, 1.8, 0.9, 9.3),
          ],
        },
      },
    ],
  },
  {
    id: 'ss-009',
    kind: 'single',
    meal_type: 'dinner',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['totals-bottom'],
    screens: [
      {
        layout: 'b-meal',
        dense: true,
        clock: '20:47',
        battery: 22,
        date: '2026-10-03',
        totalsPosition: 'bottom',
        record: {
          meal: 'dinner',
          time: '20:00',
          foods: [J.saba, J.hakumai150, J.chikuzenni, J.hiyayakko, J.misoAge, J.natto, J.harusame],
        },
      },
    ],
  },
  {
    id: 'ss-010',
    kind: 'single',
    meal_type: 'lunch',
    content: 'アプリの画面です',
    app_name: 'MealDiary',
    extraTags: ['with-note', 'distractor-goal'],
    screens: [
      {
        layout: 'c-meal',
        clock: '13:16',
        battery: 81,
        date: '2026-10-07',
        dailyGoal: { goal: 1900, otherMealsKcal: 428 },
        record: { meal: 'lunch', time: '12:34', foods: [E.chickenSalad, E.wwBread, E.minestrone, E.apple] },
      },
    ],
  },
  {
    id: 'ss-011',
    kind: 'single',
    meal_type: 'dinner',
    content: '',
    app_name: 'MealDiary',
    extraTags: ['jp-food-names'],
    screens: [
      {
        layout: 'c-meal',
        theme: 'dark',
        clock: '21:03',
        battery: 18,
        date: '2026-10-06',
        record: {
          meal: 'dinner',
          time: '20:40',
          foods: [
            f('牛丼 (並盛)', '1 bowl', 680, 22, 24, 92),
            f('味噌汁', '1 cup', 42, 3, 1, 5),
            f('サラダ (ごまドレッシング)', '1 plate', 98, 1, 8, 6),
            f('生卵', '1 egg', 71, 6, 5, 0),
          ],
        },
      },
    ],
  },
  {
    // 小数グラム: 合計 P 27.5 / F 11.8 / C 33.7 → 正解は切り捨てで 27 / 11 / 33
    id: 'ss-012',
    kind: 'single',
    meal_type: 'breakfast',
    content: '',
    app_name: 'MealDiary',
    screens: [
      {
        layout: 'c-meal',
        clock: '7:58',
        battery: 88,
        date: '2026-10-09',
        record: {
          meal: 'breakfast',
          time: '7:30',
          decimals: true,
          foods: [
            f('Greek yogurt, plain', '170 g', 100, 17.3, 0.7, 6.1),
            f('Granola', '30 g', 138, 2.9, 5.6, 19.8),
            f('Blueberries', '50 g', 29, 0.4, 0.2, 7.2),
            f('Boiled egg', '1 large', 78, 6.6, 5.3, 0.6),
            f('Black coffee', '1 cup', 2, 0.3, 0.0, 0.0),
          ],
        },
      },
    ],
  },
  {
    id: 'ss-013',
    kind: 'single',
    meal_type: 'lunch',
    content: '',
    app_name: 'MealDiary',
    screens: [
      {
        layout: 'c-meal',
        dense: true,
        clock: '12:59',
        battery: 54,
        date: '2026-10-05',
        record: {
          meal: 'lunch',
          time: '12:10',
          foods: [
            E.whiteRice,
            E.karaage,
            E.potatoSalad,
            E.cabbage,
            E.misoSoup,
            E.pickles,
            E.tamagoyaki,
            E.soySauce,
            E.mandarin,
            E.greenTea,
          ],
        },
      },
    ],
  },

  // ===== 1日ビュー（4件）: 正解 = 1日合計、alt = 最大の1食 =====
  {
    id: 'ss-014',
    kind: 'day-view',
    meal_type: 'dinner',
    content: '',
    app_name: 'ごはんログ',
    screens: [
      {
        layout: 'a-day',
        clock: '22:14',
        battery: 31,
        date: '2026-10-06',
        targetKcal: 2000,
        records: [
          { meal: 'breakfast', time: '7:30', foods: [J.zenryuToast, J.yudetamago, J.milk] },
          { meal: 'lunch', time: '12:40', foods: [J.zarusoba, J.kakiage] },
          { meal: 'dinner', time: '19:30', foods: [J.hamburg, J.hakumai150, J.cornSoup, J.greenSalad] },
          { meal: 'snack', time: '15:10', foods: [J.proteinBar] },
        ],
      },
    ],
  },
  {
    id: 'ss-015',
    kind: 'day-view',
    meal_type: 'lunch',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['totals-top'],
    screens: [
      {
        layout: 'b-day',
        clock: '23:02',
        battery: 47,
        date: '2026-10-03',
        totalPosition: 'top',
        records: [
          { meal: 'breakfast', time: '7:50', foods: [J.onigiriSake, J.saladChicken, J.yasaiJuice] },
          { meal: 'lunch', time: '12:30', foods: [J.ramen, J.gyoza] },
          { meal: 'dinner', time: '19:40', foods: [J.sasami, J.genmai150, J.tonjiru, J.brocco] },
          { meal: 'snack', time: '15:30', foods: [J.latte, J.nuts] },
        ],
      },
    ],
  },
  {
    id: 'ss-016',
    kind: 'day-view',
    meal_type: 'dinner',
    content: '',
    app_name: 'MealDiary',
    extraTags: ['distractor-goal'],
    screens: [
      {
        layout: 'c-day',
        clock: '21:47',
        battery: 52,
        date: '2026-10-04',
        goal: { kcal: 2000, p: 120, f: 60, c: 250 },
        records: [
          { meal: 'breakfast', time: '8:00', foods: [E.oatmealMilk, E.banana] },
          { meal: 'lunch', time: '12:30', foods: [E.turkeySandwich, E.vegSoup] },
          { meal: 'dinner', time: '19:00', foods: [E.salmonTeriyaki, E.brownRice, E.broccoli] },
          { meal: 'snack', time: '16:00', foods: [E.proteinShake, E.almonds] },
        ],
      },
    ],
  },
  {
    id: 'ss-017',
    kind: 'day-view',
    meal_type: 'dinner',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['totals-bottom'],
    screens: [
      {
        layout: 'b-day',
        theme: 'dark',
        clock: '22:36',
        battery: 15,
        date: '2026-10-01',
        totalPosition: 'bottom',
        records: [
          { meal: 'breakfast', time: '7:15', foods: [J.hakumai150, J.natto, J.misoTofu] },
          { meal: 'lunch', time: '12:45', foods: [J.saladPasta, J.saladChicken] },
          { meal: 'dinner', time: '20:10', foods: [J.mabo, J.hakumai150, J.chukaSoup, J.harusame] },
          { meal: 'snack', time: '16:20', foods: [J.banana, J.greekYogurt] },
        ],
      },
    ],
  },

  // ===== 2枚・同じ食事（4件）: 1枚目 = 品目 + 合計kcal、2枚目 = PFC =====
  {
    id: 'ss-018',
    kind: 'two-image',
    meal_type: 'lunch',
    content: '',
    app_name: 'ごはんログ',
    screens: [
      {
        layout: 'a-list',
        clock: '13:22',
        battery: 72,
        date: '2026-10-08',
        record: { meal: 'lunch', time: '12:50', foods: [J.curry, J.fukujin, J.wafuSalad] },
      },
      {
        layout: 'a-nutrition',
        clock: '13:22',
        battery: 72,
        date: '2026-10-08',
        record: { meal: 'lunch', time: '12:50', foods: [J.curry, J.fukujin, J.wafuSalad] },
      },
    ],
  },
  {
    id: 'ss-019',
    kind: 'two-image',
    meal_type: 'dinner',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['distractor-extra-nutrients'],
    screens: [
      {
        layout: 'b-list',
        clock: '20:05',
        battery: 44,
        date: '2026-10-06',
        record: {
          meal: 'dinner',
          time: '19:30',
          foods: [J.karaage, J.hakumai200, J.tonjiru, J.cabbage, J.potatoSalad],
          extras: { fiber: 6.8, salt: 4.1 },
        },
      },
      {
        layout: 'b-nutrition',
        clock: '20:06',
        battery: 44,
        date: '2026-10-06',
        record: {
          meal: 'dinner',
          time: '19:30',
          foods: [J.karaage, J.hakumai200, J.tonjiru, J.cabbage, J.potatoSalad],
          extras: { fiber: 6.8, salt: 4.1 },
        },
      },
    ],
  },
  {
    id: 'ss-020',
    kind: 'two-image',
    meal_type: 'dinner',
    content: '',
    app_name: 'MealDiary',
    screens: [
      {
        layout: 'c-list',
        clock: '19:41',
        battery: 66,
        date: '2026-10-07',
        record: { meal: 'dinner', time: '19:15', foods: [E.grilledSalmon, E.brownRice, E.broccoli, E.misoSoup] },
      },
      {
        layout: 'c-nutrition',
        clock: '19:41',
        battery: 66,
        date: '2026-10-07',
        record: { meal: 'dinner', time: '19:15', foods: [E.grilledSalmon, E.brownRice, E.broccoli, E.misoSoup] },
      },
    ],
  },
  {
    id: 'ss-021',
    kind: 'two-image',
    meal_type: 'breakfast',
    content: '',
    app_name: 'ごはんログ',
    screens: [
      {
        layout: 'a-list',
        theme: 'dark',
        clock: '7:46',
        battery: 97,
        date: '2026-10-09',
        record: { meal: 'breakfast', time: '7:20', foods: [J.hakumai150, J.yakijake, J.natto, J.misoTofu, J.dashimaki] },
      },
      {
        layout: 'a-nutrition',
        theme: 'dark',
        clock: '7:47',
        battery: 97,
        date: '2026-10-09',
        record: { meal: 'breakfast', time: '7:20', foods: [J.hakumai150, J.yakijake, J.natto, J.misoTofu, J.dashimaki] },
      },
    ],
  },

  // ===== 2枚・別の食事（3件）: warning 必須、totals は採点しない =====
  {
    // 同じ日付だが 1枚目=昼食, 2枚目=夕食
    id: 'ss-022',
    kind: 'mismatch',
    meal_type: 'lunch',
    content: '',
    app_name: 'ごはんログ',
    extraTags: ['diff-meal-label'],
    screens: [
      {
        layout: 'a-list',
        clock: '21:10',
        battery: 39,
        date: '2026-10-07',
        record: { meal: 'lunch', time: '12:30', foods: [J.zarusoba, J.inari] },
      },
      {
        layout: 'a-nutrition',
        clock: '21:11',
        battery: 39,
        date: '2026-10-07',
        record: { meal: 'dinner', time: '19:30', foods: [J.steak, J.rice150, J.cornSoup, J.greenSalad] },
      },
    ],
  },
  {
    // 日付も食事区分も同じ表示。数値だけが食い違う（412 kcal vs 696 kcal）
    id: 'ss-023',
    kind: 'mismatch',
    meal_type: 'breakfast',
    content: '',
    app_name: 'ミールノート',
    extraTags: ['same-label', 'distractor-extra-nutrients'],
    screens: [
      {
        layout: 'b-list',
        clock: '8:31',
        battery: 90,
        date: '2026-10-05',
        record: { meal: 'breakfast', time: '7:50', foods: [J.butterToast, J.medamayaki, J.sweetYogurt, J.coffee] },
      },
      {
        layout: 'b-nutrition',
        clock: '8:32',
        battery: 90,
        date: '2026-10-05',
        record: {
          meal: 'breakfast',
          time: '7:50',
          foods: [J.hotcake, J.bacon, J.orangeJuice],
          extras: { fiber: 2.1, salt: 2.4 },
        },
      },
    ],
  },
  {
    // 別の日・別の食事（Oct 6 Dinner vs Oct 3 Lunch）
    id: 'ss-024',
    kind: 'mismatch',
    meal_type: 'dinner',
    content: '',
    app_name: 'MealDiary',
    extraTags: ['diff-date'],
    screens: [
      {
        layout: 'c-list',
        clock: '20:18',
        battery: 57,
        date: '2026-10-06',
        record: { meal: 'dinner', time: '19:45', foods: [E.spaghetti, E.caesar, E.garlicBread] },
      },
      {
        layout: 'c-nutrition',
        clock: '20:19',
        battery: 57,
        date: '2026-10-03',
        record: { meal: 'lunch', time: '12:20', foods: [E.turkeySandwich, E.apple, E.icedLatte] },
      },
    ],
  },

  // ===== 食事アプリ以外（3件）: foods は空配列が正解 =====
  {
    id: 'ss-025',
    kind: 'non-meal',
    meal_type: 'lunch',
    content: '',
    app_name: 'そらもよう',
    extraTags: ['weather'],
    screens: [{ layout: 'weather', clock: '12:52', battery: 79, date: '2026-10-09', data: WEATHER }],
  },
  {
    id: 'ss-026',
    kind: 'non-meal',
    meal_type: 'lunch',
    content: '',
    app_name: 'トークル',
    extraTags: ['chat', 'food-words'],
    screens: [{ layout: 'chat', clock: '11:58', battery: 84, date: '2026-10-09', data: CHAT }],
  },
  {
    id: 'ss-027',
    kind: 'non-meal',
    meal_type: 'snack',
    content: '',
    app_name: 'てくてくメーター',
    extraTags: ['burned-kcal'],
    screens: [{ layout: 'steps', clock: '18:24', battery: 46, date: '2026-10-09', data: STEPS }],
  },
]
