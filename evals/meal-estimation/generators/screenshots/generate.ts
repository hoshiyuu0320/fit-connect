/**
 * 合成スクリーンショット生成器。
 *
 *   npm run gen:screenshots
 *
 * 1. cases.ts の各画面を HTML で描画し、Chromium で iPhone 相当（390x844 CSS px, DPR 3 → 1170x2532 PNG）として撮影
 * 2. モバイルアプリのアップロード前処理（image_picker: maxWidth 1920 / maxHeight 1080 / imageQuality 80）と同じ
 *    「1920x1080 に収まるよう縮小（拡大なし）→ JPEG q80」を sharp で適用
 * 3. datasets/screenshots-synthetic/{cases.json, images/*.jpg} を出力（raw/*.png は gitignore 済みの参考用）
 *
 * 期待値はすべて cases.ts の同じデータから導出する。乱数は使わない。
 */
import { chromium } from 'playwright-core'
import sharp from 'sharp'
import { mkdir, readdir, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  CASES,
  type CaseSpec,
  type ChatData,
  type DayGoal,
  type FoodItem,
  type MealRecord,
  type MealType,
  type Screen,
  type StepsData,
  type Theme,
  type WeatherData,
  type WeatherIcon,
} from './cases.js'

// ---------------------------------------------------------------------------
// 設定
// ---------------------------------------------------------------------------

const HERE = path.dirname(fileURLToPath(import.meta.url))
const EVAL_ROOT = path.resolve(HERE, '../..')
const OUT_DIR = path.join(EVAL_ROOT, 'datasets', 'screenshots-synthetic')
const IMG_DIR = path.join(OUT_DIR, 'images')
const RAW_DIR = path.join(OUT_DIR, 'raw')
const CHROMIUM_PATH = process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'

/** iPhone 14/15 相当 */
const VIEWPORT = { width: 390, height: 844 }
const DEVICE_SCALE = 3
/** fit-connect-mobile/lib/services/storage_service.dart の StorageService と同じ値 */
const UPLOAD = { maxWidth: 1920, maxHeight: 1080, quality: 80 }

const KEEP_RAW = process.env.KEEP_RAW !== '0'

// ---------------------------------------------------------------------------
// 出力契約（src/dataset.ts と共有）
// ---------------------------------------------------------------------------

type Totals = { calories: number; protein_g: number; fat_g: number; carbs_g: number }

interface OutCase {
  id: string
  images: string[]
  meal_type: MealType
  content: string
  expected: {
    is_meal: boolean
    totals: Totals | null
    alt_totals?: Totals[]
    foods_count?: number | null
    expect_warning?: boolean | null
    app_name?: string | null
  }
  tags: string[]
}

interface DatasetFile {
  dataset: 'screenshots-synthetic-v1'
  input_kind: 'screenshot'
  description: string
  source: string
  preprocessing: string
  cases: OutCase[]
}

// ---------------------------------------------------------------------------
// 数値ユーティリティ
// ---------------------------------------------------------------------------

/** 画面に表示する合計（decimals レコードは 0.1 単位） */
interface Shown {
  kcal: number
  p: number
  f: number
  c: number
}

const tenths = (v: number): number => Math.round(v * 10)

function sumFoods(foods: FoodItem[]): Shown {
  const s = (k: keyof Shown): number => foods.reduce((a, x) => a + tenths(x[k]), 0) / 10
  return { kcal: s('kcal'), p: s('p'), f: s('f'), c: s('c') }
}

function sumShown(list: Shown[]): Shown {
  const s = (k: keyof Shown): number => list.reduce((a, x) => a + tenths(x[k]), 0) / 10
  return { kcal: s('kcal'), p: s('p'), f: s('f'), c: s('c') }
}

/** 正解値: 画面の合計を整数に切り捨て（SCREENSHOT_SYSTEM_PROMPT「小数点以下は切り捨て」） */
function toTotals(s: Shown): Totals {
  return { calories: Math.floor(s.kcal), protein_g: Math.floor(s.p), fat_g: Math.floor(s.f), carbs_g: Math.floor(s.c) }
}

const atwater = (s: Shown): number => 4 * s.p + 9 * s.f + 4 * s.c

/** 3桁区切り（1,947） */
function int(n: number): string {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

function grams(v: number, decimals: boolean | undefined): string {
  return decimals ? v.toFixed(1) : String(v)
}

/** エネルギー比率 %（最大剰余法で合計 100 に揃える） */
function energyShares(s: Shown): [number, number, number] {
  const e = [4 * s.p, 9 * s.f, 4 * s.c]
  const total = e[0] + e[1] + e[2]
  const raw = e.map((x) => (x / total) * 100)
  const base = raw.map(Math.floor)
  let rest = 100 - base.reduce((a, b) => a + b, 0)
  const order = raw.map((x, i) => ({ i, frac: x - Math.floor(x) })).sort((a, b) => b.frac - a.frac || a.i - b.i)
  for (const o of order) {
    if (rest <= 0) break
    base[o.i] += 1
    rest -= 1
  }
  return [base[0], base[1], base[2]]
}

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

// ---------------------------------------------------------------------------
// 日付・ラベル
// ---------------------------------------------------------------------------

const JP_WD = ['日', '月', '火', '水', '木', '金', '土']
const EN_WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const EN_MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function parseDate(d: string): { y: number; m: number; d: number; wd: number } {
  const [y, m, dd] = d.split('-').map(Number)
  const wd = new Date(Date.UTC(y, m - 1, dd)).getUTCDay()
  return { y, m, d: dd, wd }
}
const jpDate = (d: string): string => {
  const x = parseDate(d)
  return `${x.m}月${x.d}日(${JP_WD[x.wd]})`
}
const enDate = (d: string): string => {
  const x = parseDate(d)
  return `${EN_WD[x.wd]}, ${EN_MON[x.m - 1]} ${x.d}`
}
const enTime = (t: string): string => {
  const [h, m] = t.split(':').map(Number)
  const h12 = h % 12 === 0 ? 12 : h % 12
  return `${h12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`
}

const MEAL_JP: Record<MealType, string> = { breakfast: '朝食', lunch: '昼食', dinner: '夕食', snack: '間食' }
const MEAL_EN: Record<MealType, string> = { breakfast: 'Breakfast', lunch: 'Lunch', dinner: 'Dinner', snack: 'Snacks' }
const MEAL_ORDER: MealType[] = ['breakfast', 'lunch', 'dinner', 'snack']

// ---------------------------------------------------------------------------
// アイコン（インライン SVG、外部リソースなし）
// ---------------------------------------------------------------------------

const ICONS: Record<string, string> = {
  home: '<path d="M3.5 10.5 12 3.5l8.5 7V20.5h-5.5v-6h-6v6H3.5z"/>',
  note: '<rect x="5" y="3" width="14" height="18" rx="2.5"/><path d="M8.5 8h7M8.5 12h7M8.5 16h4"/>',
  chart: '<path d="M5 20v-8M10.5 20V5M16 20v-11M21 20H3"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4.5 20.5c.6-3.8 3.6-5.7 7.5-5.7s6.9 1.9 7.5 5.7"/>',
  gear: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v2.6M12 18.6v2.6M2.8 12h2.6M18.6 12h2.6M5.5 5.5l1.8 1.8M16.7 16.7l1.8 1.8M5.5 18.5l1.8-1.8M16.7 7.3l1.8-1.8"/>',
  more: '<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevL: '<path d="M15 5l-7 7 7 7"/>',
  chevR: '<path d="M9 5l7 7-7 7"/>',
  chevD: '<path d="M6 9l6 6 6-6"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  book: '<path d="M5 4.5h9.5a2.5 2.5 0 0 1 2.5 2.5v13H7.5A2.5 2.5 0 0 1 5 17.5z"/><path d="M5 17.5A2.5 2.5 0 0 1 7.5 15H17"/>',
  phone: '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a1 1 0 0 1-1 1A16 16 0 0 1 4 5a1 1 0 0 1 1-1z"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  send: '<path d="M4 12 20 4l-4 16-4-6.5z"/><path d="M12 13.5 20 4"/>',
  pin: '<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>',
  bell: '<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  map: '<path d="M3 6l6-2.5 6 2.5 6-2.5v14.5l-6 2.5-6-2.5-6 2.5z"/><path d="M9 3.5v14.5M15 6v14.5"/>',
  trophy: '<path d="M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M7 6H4v1.5A3.5 3.5 0 0 0 7.5 11M17 6h3v1.5A3.5 3.5 0 0 1 16.5 11M12 14v4M8 20.5h8"/>',
  umbrella: '<path d="M3 12a9 9 0 0 1 18 0z"/><path d="M12 12v6.5a2 2 0 0 1-4 0"/>',
  edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>',
  camera: '<rect x="3" y="7" width="18" height="13" rx="2.5"/><circle cx="12" cy="13.5" r="3.5"/><path d="M8.5 7l1.5-2.5h4L15.5 7"/>',
  smile: '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 14a4.5 4.5 0 0 0 7 0"/><path d="M9 9.5h.01M15 9.5h.01"/>',
  chat: '<path d="M4 5h16v11H9l-5 4z"/>',
  users: '<circle cx="9" cy="8.5" r="3.5"/><path d="M2.5 20c.5-3.5 3-5.5 6.5-5.5s6 2 6.5 5.5"/><path d="M15.5 5.2a3.5 3.5 0 0 1 0 6.6M17.5 14.8c2.2.6 3.6 2.4 4 5.2"/>',
  shoe: '<path d="M3 16.5V8.5l4 1 2.5-3 3 4.5 5.5 2a4 4 0 0 1 3 3.5V17H3z"/><path d="M3 20h18"/>',
}

function icon(name: string, cls = ''): string {
  return `<svg class="ic ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`
}

function statusBar(clock: string, battery: number): string {
  const w = Math.max(2, Math.round((19 * battery) / 100))
  const low = battery <= 20
  return `<div class="sb"><span class="sb-time">${clock}</span><span class="sb-right">
<svg width="18" height="12" viewBox="0 0 18 12" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
<svg width="17" height="12" viewBox="0 0 17 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M1.5 4.3a10 10 0 0 1 14 0"/><path d="M4.2 7.2a6.2 6.2 0 0 1 8.6 0"/><circle cx="8.5" cy="10.2" r="1.3" fill="currentColor" stroke="none"/></svg>
<span class="sb-batt">${battery}%<svg width="27" height="13" viewBox="0 0 27 13"><rect x="0.5" y="0.5" width="23" height="12" rx="3.5" fill="none" stroke="currentColor" stroke-opacity=".45"/><rect x="2" y="2" width="${w}" height="9" rx="2" fill="${low ? '#FF3B30' : 'currentColor'}"/><rect x="24.8" y="4.5" width="1.7" height="4" rx=".85" fill="currentColor" fill-opacity=".5"/></svg></span>
</span></div>`
}

function tabBar(items: [string, string][], active: number): string {
  return `<nav class="tabbar">${items
    .map(([ic, label], i) => `<div class="tab${i === active ? ' on' : ''}">${icon(ic)}<span>${label}</span></div>`)
    .join('')}<div class="home-ind"></div></nav>`
}

// ---------------------------------------------------------------------------
// 共通 CSS / ドキュメント
// ---------------------------------------------------------------------------

const BASE_CSS = `
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:390px;height:844px;overflow:hidden}
body{font-family:'IPAGothic','IPAPGothic',sans-serif;background:var(--bg);color:var(--text);display:flex;flex-direction:column;font-size:14px;line-height:1.35;-webkit-font-smoothing:antialiased}
.sb{height:47px;flex:none;display:flex;align-items:center;justify-content:space-between;padding:4px 22px 0 36px;font-size:16px;font-weight:700;color:var(--sbtext,var(--text));background:var(--sbbg,transparent)}
.sb-right{display:flex;align-items:center;gap:6px}
.sb-batt{display:flex;align-items:center;gap:4px;font-size:12px;font-weight:700}
main{flex:1;overflow:hidden;position:relative}
.tabbar{height:83px;flex:none;display:flex;justify-content:space-around;align-items:flex-start;padding:7px 8px 0;background:var(--tabbg);border-top:1px solid var(--line);position:relative}
.tab{display:flex;flex-direction:column;align-items:center;gap:3px;font-size:10px;color:var(--tabin);width:76px}
.tab.on{color:var(--accent)}
.tab .ic{width:25px;height:25px}
.home-ind{position:absolute;left:50%;bottom:8px;width:134px;height:5px;margin-left:-67px;border-radius:3px;background:var(--text);opacity:.85}
.ic{display:block}
`

function doc(vars: string, css: string, body: string, bodyClass = ''): string {
  return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><style>${BASE_CSS}:root{${vars}}${css}</style></head><body class="${bodyClass}">${body}</body></html>`
}

// ---------------------------------------------------------------------------
// アプリA「ごはんログ」
// ---------------------------------------------------------------------------

const A_VARS: Record<Theme, string> = {
  light:
    '--bg:#F6F4EF;--card:#FFFFFF;--text:#22252A;--sub:#737880;--line:#ECE8E0;--accent:#DD7128;--track:#F3E6D8;--segbg:#ECE7DE;--P:#D4504B;--F:#DE9F25;--C:#3A84D2;--tabbg:#FFFFFF;--tabin:#A0A4AA',
  dark:
    '--bg:#111214;--card:#1E2023;--text:#F2F2F1;--sub:#A0A5AB;--line:#2D3034;--accent:#F28A3F;--track:#3A2F27;--segbg:#26292C;--P:#F06A64;--F:#F2B94A;--C:#5BA4EE;--tabbg:#17181A;--tabin:#6F747A',
}

const A_CSS = `
.a-top{display:flex;justify-content:space-between;align-items:center;padding:4px 18px 2px;height:42px}
.a-brand{display:flex;align-items:center;gap:8px;font-size:19px;font-weight:700;color:var(--accent);letter-spacing:.03em}
.a-brand svg{width:26px;height:26px;display:block}
.a-top-icons{display:flex;gap:16px;color:var(--sub)} .a-top-icons .ic{width:22px;height:22px}
.a-date{display:flex;align-items:center;justify-content:center;gap:22px;font-size:16px;font-weight:700;padding:4px 0 10px}
.a-date .ic{width:18px;height:18px;color:var(--sub)}
.a-seg{display:flex;margin:0 16px 12px;background:var(--segbg);border-radius:9px;padding:3px}
.a-seg span{flex:1;text-align:center;font-size:14px;padding:7px 0;border-radius:7px;color:var(--sub)}
.a-seg span.on{background:var(--accent);color:#fff;font-weight:700}
.a-sub{display:flex;margin:0 16px 12px;border-bottom:1px solid var(--line)}
.a-sub span{flex:1;text-align:center;font-size:14px;padding:4px 0 9px;color:var(--sub)}
.a-sub span.on{color:var(--accent);font-weight:700;border-bottom:2.5px solid var(--accent);margin-bottom:-1px}
.card{background:var(--card);border-radius:14px;margin:0 16px 12px}
.a-sum{display:flex;align-items:center;gap:18px;padding:16px 16px 16px 14px}
.ring-col{display:flex;flex-direction:column;align-items:center;flex:none}
.ring{width:124px;height:124px;border-radius:50%;display:flex;align-items:center;justify-content:center}
.ring-in{width:100px;height:100px;border-radius:50%;background:var(--card);display:flex;flex-direction:column;align-items:center;justify-content:center}
.ring-num{font-size:30px;font-weight:700;line-height:1.1}
.ring-unit{font-size:12px;color:var(--sub)}
.ring-target{margin-top:7px;font-size:11px;color:var(--sub)}
.pfc{flex:1;display:flex;flex-direction:column;gap:12px}
.pfc-head{display:flex;justify-content:space-between;align-items:baseline;font-size:12px;color:var(--sub);margin-bottom:5px}
.pfc-label{display:flex;align-items:center;gap:5px}
.badge{display:inline-flex;align-items:center;justify-content:center;width:17px;height:17px;border-radius:4px;color:#fff;font-size:11px;font-weight:700}
.pfc-val{font-size:17px;font-weight:700;color:var(--text)} .pfc-val small{font-size:12px;font-weight:400;margin-left:1px}
.bar{height:7px;border-radius:4px;background:var(--track);overflow:hidden} .fill{height:100%;border-radius:4px}
.a-sec{display:flex;justify-content:space-between;align-items:baseline;margin:2px 22px 8px;font-size:15px;font-weight:700}
.a-sec span{font-size:12px;color:var(--sub);font-weight:400}
.a-row{display:flex;justify-content:space-between;align-items:center;padding:10px 16px;border-top:1px solid var(--line)}
.a-row:first-child{border-top:none}
.fname{font-size:15px} .famt{font-size:12px;color:var(--sub);margin-top:2px}
.fkcal{font-size:15px;font-weight:700;white-space:nowrap} .fkcal small{font-size:11px;font-weight:400;color:var(--sub);margin-left:3px}
.a-add{margin:2px 16px;border:1.5px dashed var(--accent);color:var(--accent);border-radius:12px;text-align:center;padding:11px;font-size:14px;font-weight:700}
.a-total{display:flex;justify-content:space-between;align-items:center;padding:16px 18px}
.a-total .lab{font-size:14px;color:var(--sub)} .a-total .num{font-size:30px;font-weight:700} .a-total .num small{font-size:14px;font-weight:400;color:var(--sub);margin-left:4px}
.donut-card{padding:16px 18px 18px}
.donut-title{font-size:15px;font-weight:700;margin-bottom:14px;display:flex;justify-content:space-between;align-items:baseline}
.donut-title span{font-size:12px;color:var(--sub);font-weight:400}
.donut{width:176px;height:176px;border-radius:50%;margin:0 auto 18px;display:flex;align-items:center;justify-content:center}
.donut-in{width:118px;height:118px;border-radius:50%;background:var(--card);display:flex;flex-direction:column;align-items:center;justify-content:center}
.donut-in .num{font-size:30px;font-weight:700;line-height:1.1} .donut-in .u{font-size:12px;color:var(--sub)}
.leg{display:flex;align-items:center;padding:10px 0;border-top:1px solid var(--line);font-size:14px}
.leg .sw{width:12px;height:12px;border-radius:3px;margin-right:9px;flex:none}
.leg .nm{flex:1} .leg .g{font-size:18px;font-weight:700;width:86px;text-align:right} .leg .g small{font-size:12px;font-weight:400;margin-left:1px}
.leg .pc{width:58px;text-align:right;color:var(--sub);font-size:13px}
.a-note{margin:0 22px;font-size:11px;color:var(--sub);line-height:1.6}
/* day view */
.a-day .a-sum{padding:12px 14px 12px 12px;gap:16px}
.a-day .ring{width:108px;height:108px} .a-day .ring-in{width:86px;height:86px} .a-day .ring-num{font-size:24px}
.a-day .pfc{gap:8px} .a-day .pfc-head{margin-bottom:3px} .a-day .pfc-val{font-size:15px}
.a-day .a-seg span{font-size:13px;padding:6px 0}
.dm{padding:8px 14px 7px;border-top:1px solid var(--line)} .dm:first-child{border-top:none}
.dm-head{display:flex;justify-content:space-between;align-items:center}
.dm-name{display:flex;align-items:center;gap:8px;font-size:14px;font-weight:700}
.dm-name i{font-style:normal;font-size:11px;font-weight:400;color:var(--sub)}
.dm-kcal{font-size:15px;font-weight:700} .dm-kcal small{font-size:11px;font-weight:400;color:var(--sub);margin-left:2px}
.dm-pfc{font-size:12px;color:var(--sub);margin:1px 0 3px;display:flex;gap:12px}
.dm-pfc b{color:var(--text);font-weight:700;font-size:13px}
.dm-food{display:flex;justify-content:space-between;font-size:12px;color:var(--sub);padding:1px 0 1px 10px}
`

const A_LOGO = `<svg viewBox="0 0 26 26"><rect width="26" height="26" rx="7" fill="var(--accent)"/><path d="M5.5 12.5h15a7.5 7.5 0 0 1-15 0z" fill="#fff"/><path d="M10 9.5c0-1.6 1.6-1.9 1.6-3.6M14.4 9.5c0-1.6 1.6-1.9 1.6-3.6" stroke="#fff" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>`

const A_TABS: [string, string][] = [
  ['home', 'ホーム'],
  ['note', '記録'],
  ['chart', 'グラフ'],
  ['user', 'マイページ'],
]

function aHeader(date: string): string {
  return `<div class="a-top"><div class="a-brand">${A_LOGO}ごはんログ</div><div class="a-top-icons">${icon('calendar')}${icon('bell')}</div></div>
<div class="a-date">${icon('chevL')}<span>${jpDate(date)}</span>${icon('chevR')}</div>`
}

function aMealSeg(active: MealType | 'day', withDay = false): string {
  const items: [string, string][] = withDay ? [['day', '1日']] : []
  for (const m of MEAL_ORDER) items.push([m, MEAL_JP[m]])
  return `<div class="a-seg">${items.map(([k, l]) => `<span class="${k === active ? 'on' : ''}">${l}</span>`).join('')}</div>`
}

function aPfcBars(t: Shown, targetKcal: number, gt: string): string {
  const tgt = { p: (targetKcal * 0.15) / 4, f: (targetKcal * 0.25) / 9, c: (targetKcal * 0.6) / 4 }
  const row = (k: 'p' | 'f' | 'c', letter: string, label: string): string => {
    const pct = Math.min(100, (t[k] / tgt[k]) * 100).toFixed(1)
    return `<div><div class="pfc-head"><span class="pfc-label"><b class="badge" style="background:var(--${letter})">${letter}</b>${label}</span><span class="pfc-val" data-gt="${gt}-${k}">${t[k]}<small>g</small></span></div><div class="bar"><div class="fill" style="width:${pct}%;background:var(--${letter})"></div></div></div>`
  }
  return `<div class="pfc">${row('p', 'P', 'たんぱく質')}${row('f', 'F', '脂質')}${row('c', 'C', '炭水化物')}</div>`
}

function aRing(kcal: number, target: number, showTarget: boolean, gt: string): string {
  const pct = Math.min(100, (kcal / target) * 100).toFixed(1)
  return `<div class="ring-col"><div class="ring" style="background:conic-gradient(var(--accent) 0 ${pct}%, var(--track) ${pct}% 100%)"><div class="ring-in"><div class="ring-num" data-gt="${gt}-kcal">${int(kcal)}</div><div class="ring-unit">kcal</div></div></div>${
    showTarget ? `<div class="ring-target">目標 ${int(target)} kcal</div>` : ''
  }</div>`
}

function aFoodRows(foods: FoodItem[]): string {
  return foods
    .map(
      (x, i) =>
        `<div class="a-row" data-gt="food-${i}"><div><div class="fname">${esc(x.name)}</div><div class="famt">${esc(x.amount)}</div></div><div class="fkcal">${int(x.kcal)}<small>kcal</small></div></div>`,
    )
    .join('')
}

function renderAMeal(s: Extract<Screen, { layout: 'a-meal' }>): string {
  const t = sumFoods(s.record.foods)
  const body = `${statusBar(s.clock, s.battery)}<main>${aHeader(s.date)}${aMealSeg(s.record.meal)}
<section class="card a-sum">${aRing(t.kcal, s.targetKcal, s.showTarget, 'total')}${aPfcBars(t, s.targetKcal, 'total')}</section>
<div class="a-sec">食べたもの<span>${s.record.foods.length}品 ・ ${s.record.time} 記録</span></div>
<section class="card">${aFoodRows(s.record.foods)}</section>
<div class="a-add">＋ 食事を追加</div></main>${tabBar(A_TABS, 1)}`
  return doc(A_VARS[s.theme ?? 'light'], A_CSS, body)
}

function renderAList(s: Extract<Screen, { layout: 'a-list' }>): string {
  const t = sumFoods(s.record.foods)
  const body = `${statusBar(s.clock, s.battery)}<main>${aHeader(s.date)}${aMealSeg(s.record.meal)}
<div class="a-sub"><span class="on">記録</span><span>栄養バランス</span></div>
<section class="card a-total"><span class="lab">${MEAL_JP[s.record.meal]}の合計</span><span class="num" data-gt="total-kcal">${int(t.kcal)}<small>kcal</small></span></section>
<div class="a-sec">食べたもの<span>${s.record.foods.length}品 ・ ${s.record.time} 記録</span></div>
<section class="card">${aFoodRows(s.record.foods)}</section>
<div class="a-add">＋ 食事を追加</div></main>${tabBar(A_TABS, 1)}`
  return doc(A_VARS[s.theme ?? 'light'], A_CSS, body)
}

function renderANutrition(s: Extract<Screen, { layout: 'a-nutrition' }>): string {
  const t = sumFoods(s.record.foods)
  const shares = energyShares(t)
  const a = shares[0]
  const b = shares[0] + shares[1]
  const leg = (k: 'p' | 'f' | 'c', letter: string, label: string, pc: number): string =>
    `<div class="leg"><span class="sw" style="background:var(--${letter})"></span><span class="nm">${label}(${letter})</span><span class="g" data-gt="total-${k}">${t[k]}<small>g</small></span><span class="pc">${pc}%</span></div>`
  const body = `${statusBar(s.clock, s.battery)}<main>${aHeader(s.date)}${aMealSeg(s.record.meal)}
<div class="a-sub"><span>記録</span><span class="on">栄養バランス</span></div>
<section class="card donut-card"><div class="donut-title">PFCバランス<span>${MEAL_JP[s.record.meal]} ・ エネルギー比</span></div>
<div class="donut" style="background:conic-gradient(var(--P) 0 ${a}%, var(--F) ${a}% ${b}%, var(--C) ${b}% 100%)"><div class="donut-in"><div class="num" data-gt="total-kcal">${int(t.kcal)}</div><div class="u">kcal</div></div></div>
${leg('p', 'P', 'たんぱく質', shares[0])}${leg('f', 'F', '脂質', shares[1])}${leg('c', 'C', '炭水化物', shares[2])}</section>
<p class="a-note">目安のバランス：P 13〜20% ／ F 20〜30% ／ C 50〜65%<br>※エネルギー比は P・C 4kcal/g、F 9kcal/g で計算しています</p></main>${tabBar(A_TABS, 1)}`
  return doc(A_VARS[s.theme ?? 'light'], A_CSS, body)
}

function renderADay(s: Extract<Screen, { layout: 'a-day' }>): string {
  const recs = sortRecords(s.records)
  const subs = recs.map((r) => sumFoods(r.foods))
  const day = sumShown(subs)
  const meals = recs
    .map((r, i) => {
      const t = subs[i]
      const foods = r.foods
        .map((x, j) => `<div class="dm-food" data-gt="food-${r.meal}-${j}"><span>${esc(x.name)}</span><span>${int(x.kcal)} kcal</span></div>`)
        .join('')
      return `<div class="dm"><div class="dm-head"><span class="dm-name">${MEAL_JP[r.meal]}<i>${r.time}</i></span><span class="dm-kcal" data-gt="${r.meal}-kcal">${int(t.kcal)}<small>kcal</small></span></div>
<div class="dm-pfc"><span>P <b data-gt="${r.meal}-p">${t.p}</b>g</span><span>F <b data-gt="${r.meal}-f">${t.f}</b>g</span><span>C <b data-gt="${r.meal}-c">${t.c}</b>g</span></div>${foods}</div>`
    })
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main class="a-day">${aHeader(s.date)}${aMealSeg('day', true)}
<section class="card a-sum">${aRing(day.kcal, s.targetKcal, true, 'total')}${aPfcBars(day, s.targetKcal, 'total')}</section>
<section class="card">${meals}</section></main>${tabBar(A_TABS, 1)}`
  return doc(A_VARS[s.theme ?? 'light'], A_CSS, body)
}

// ---------------------------------------------------------------------------
// アプリB「ミールノート」
// ---------------------------------------------------------------------------

const B_VARS: Record<Theme, string> = {
  light:
    '--bg:#FFFFFF;--card:#F4F8F7;--text:#18282A;--sub:#617173;--line:#E3E9E9;--accent:#13827A;--chipbg:#EDF3F2;--P:#D24E4A;--F:#C98B10;--C:#3478C6;--tabbg:#FBFCFC;--tabin:#9AA6A7',
  dark:
    '--bg:#0D1314;--card:#172022;--text:#EAF0F0;--sub:#95A5A6;--line:#253031;--accent:#3BB3A8;--chipbg:#1E2A2B;--P:#F26E69;--F:#EDB548;--C:#62A3EC;--tabbg:#111919;--tabin:#62706F',
}
const B_THUMBS: Record<Theme, string[]> = {
  light: ['#F4DDBD', '#D9EACB', '#F6D3C8', '#D2E5F0', '#E9DAF1', '#F2E6BE', '#D3EBE3', '#F0D6E0'],
  dark: ['#5B4730', '#394B33', '#5C3A31', '#2F4656', '#4A3A57', '#55492A', '#2E4A41', '#553543'],
}

const B_CSS = `
.b-nav{display:flex;align-items:center;justify-content:space-between;padding:0 14px;height:44px}
.b-back{display:flex;align-items:center;color:var(--accent);font-size:16px;width:70px} .b-back .ic{width:22px;height:22px}
.b-brand{font-size:17px;font-weight:700;display:flex;align-items:center;gap:7px}
.b-brand svg{width:22px;height:22px;display:block}
.b-act{color:var(--accent);font-size:15px;width:70px;text-align:right}
.b-mealhead{padding:8px 20px 12px;display:flex;align-items:baseline;justify-content:space-between}
.b-mealname{font-size:24px;font-weight:700}
.b-mealdate{font-size:13px;color:var(--sub)}
.b-total{margin:0 16px 14px;padding:14px 16px 16px;border-radius:14px;background:var(--card);border:1px solid var(--line)}
.b-total-label{font-size:12px;color:var(--sub)}
.b-total-kcal{font-size:34px;font-weight:700;line-height:1.2} .b-total-kcal small{font-size:15px;font-weight:400;margin-left:5px;color:var(--sub)}
.b-pfc3{display:flex;gap:8px;margin-top:10px}
.b-pfc3>div{flex:1;border-radius:9px;padding:7px 10px 8px;background:var(--bg);border:1px solid var(--line);border-top:3px solid}
.b-pfc3 .lab{font-size:11px;color:var(--sub)} .b-pfc3 .val{font-size:19px;font-weight:700;line-height:1.25} .b-pfc3 .val small{font-size:12px;font-weight:400;margin-left:1px}
.b-listhead{display:flex;justify-content:space-between;padding:2px 20px 6px;font-size:13px;color:var(--sub)}
.b-food{display:flex;gap:12px;padding:11px 16px 11px 20px;border-bottom:1px solid var(--line);align-items:flex-start}
.thumb{width:48px;height:48px;border-radius:10px;flex:none;display:flex;align-items:center;justify-content:center}
.thumb i{width:30px;height:30px;border-radius:50%;background:rgba(255,255,255,.6);display:block;box-shadow:inset 0 0 0 5px rgba(255,255,255,.35)}
.b-fbody{flex:1;min-width:0}
.b-ftop{display:flex;justify-content:space-between;align-items:baseline;gap:8px}
.b-fname{font-size:15px;font-weight:700}
.b-fkcal{font-size:15px;font-weight:700;white-space:nowrap} .b-fkcal small{font-size:11px;font-weight:400;color:var(--sub);margin-left:2px}
.b-famt{font-size:12px;color:var(--sub);margin:2px 0 6px}
.chips{display:flex;gap:6px}
.chip{font-size:12px;padding:2px 7px;border-radius:5px;background:var(--chipbg);white-space:nowrap} .chip b{margin-right:4px}
.b-foot{margin:14px 16px 10px;padding:12px 16px;border-radius:12px;background:var(--card);border:1px solid var(--line)}
.b-foot-top{display:flex;justify-content:space-between;align-items:baseline}
.b-foot-top .lab{font-size:14px;font-weight:700} .b-foot-top .val{font-size:24px;font-weight:700} .b-foot-top .val small{font-size:13px;font-weight:400;color:var(--sub);margin-left:3px}
.b-foot-pfc{display:flex;gap:14px;margin-top:6px;font-size:13px;color:var(--sub)} .b-foot-pfc b{font-size:16px;color:var(--text);margin:0 1px 0 4px}
.b-btn{margin:12px 16px 0;padding:11px;border-radius:10px;background:var(--accent);color:#fff;text-align:center;font-size:15px;font-weight:700}
.b-seg{display:flex;margin:0 16px 14px;border:1px solid var(--accent);border-radius:8px;overflow:hidden}
.b-seg span{flex:1;text-align:center;padding:7px 0;font-size:14px;color:var(--accent)} .b-seg span.on{background:var(--accent);color:#fff;font-weight:700}
.b-sumline{margin:0 20px 10px;display:flex;justify-content:space-between;align-items:baseline}
.b-sumline .lab{font-size:14px;color:var(--sub)} .b-sumline .val{font-size:32px;font-weight:700} .b-sumline .val small{font-size:15px;font-weight:400;color:var(--sub);margin-left:4px}
.b-ratio{margin:0 16px 6px;display:flex;height:26px;border-radius:7px;overflow:hidden;font-size:12px;color:#fff;font-weight:700}
.b-ratio div{display:flex;align-items:center;justify-content:center}
.b-ratio-cap{margin:0 16px 16px;display:flex;justify-content:space-between;font-size:11px;color:var(--sub)}
.ntab{margin:0 16px;border:1px solid var(--line);border-radius:12px;overflow:hidden}
.ntab-row{display:flex;justify-content:space-between;align-items:baseline;padding:12px 16px;border-top:1px solid var(--line);font-size:15px}
.ntab-row:first-child{border-top:none}
.ntab-row .k{display:flex;align-items:center;gap:8px} .ntab-row .k i{width:10px;height:10px;border-radius:2px;display:inline-block}
.ntab-row .v{font-size:18px;font-weight:700} .ntab-row .v small{font-size:12px;font-weight:400;color:var(--sub);margin-left:2px}
.ntab-row.minor{font-size:13px;color:var(--sub);padding:9px 16px} .ntab-row.minor .v{font-size:14px;font-weight:400;color:var(--sub)}
.b-day-card{margin:0 16px 10px;padding:10px 14px 11px;border-radius:12px;background:var(--card);border:1px solid var(--line)}
.b-day-top{display:flex;justify-content:space-between;align-items:baseline}
.b-day-top .nm{font-size:16px;font-weight:700} .b-day-top .nm i{font-style:normal;font-weight:400;font-size:12px;color:var(--sub);margin-left:8px}
.b-day-top .kc{font-size:18px;font-weight:700} .b-day-top .kc small{font-size:12px;font-weight:400;color:var(--sub);margin-left:2px}
.b-day-card .chips{margin:6px 0 5px}
.b-day-foods{font-size:12px;color:var(--sub);line-height:1.45}
/* dense */
.dense .b-mealhead{padding:4px 20px 8px} .dense .b-mealname{font-size:20px}
.dense .b-food{padding:7px 14px 7px 18px;gap:10px}
.dense .thumb{width:34px;height:34px;border-radius:8px} .dense .thumb i{width:20px;height:20px;box-shadow:inset 0 0 0 3px rgba(255,255,255,.35)}
.dense .b-fname{font-size:13px} .dense .b-fkcal{font-size:13px}
.dense .b-famt{font-size:10px;margin:0 0 3px}
.dense .chip{font-size:11px;padding:1px 5px} .dense .chips{gap:5px}
.dense .b-foot{margin:10px 16px 8px;padding:9px 14px}
.dense .b-btn{margin-top:8px;padding:9px;font-size:14px}
`

const B_LOGO = `<svg viewBox="0 0 22 22"><rect width="22" height="22" rx="6" fill="var(--accent)"/><path d="M6.5 7h9M6.5 11h9M6.5 15h5.5" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg>`
const B_TABS: [string, string][] = [
  ['home', 'ホーム'],
  ['book', 'ノート'],
  ['chart', '分析'],
  ['gear', '設定'],
]

function bNav(action = '編集'): string {
  return `<div class="b-nav"><span class="b-back">${icon('chevL')}戻る</span><span class="b-brand">${B_LOGO}ミールノート</span><span class="b-act">${action}</span></div>`
}

function bPfc3(t: Shown, dec: boolean | undefined, gt: string): string {
  const cell = (k: 'p' | 'f' | 'c', letter: string, label: string): string =>
    `<div style="border-top-color:var(--${letter})"><div class="lab">${letter} ${label}</div><div class="val" data-gt="${gt}-${k}">${grams(t[k], dec)}<small>g</small></div></div>`
  return `<div class="b-pfc3">${cell('p', 'P', 'たんぱく質')}${cell('f', 'F', '脂質')}${cell('c', 'C', '炭水化物')}</div>`
}

function bChips(x: { p: number; f: number; c: number }, dec: boolean | undefined, gt?: string): string {
  const chip = (k: 'p' | 'f' | 'c', letter: string): string =>
    `<span class="chip"${gt ? ` data-gt="${gt}-${k}"` : ''}><b style="color:var(--${letter})">${letter}</b>${grams(x[k], dec)}g</span>`
  return `<div class="chips">${chip('p', 'P')}${chip('f', 'F')}${chip('c', 'C')}</div>`
}

function bThumb(i: number, theme: Theme): string {
  const pal = B_THUMBS[theme]
  return `<div class="thumb" style="background:${pal[i % pal.length]}"><i></i></div>`
}

function renderBMeal(s: Extract<Screen, { layout: 'b-meal' }>): string {
  const theme = s.theme ?? 'light'
  const r = s.record
  const t = sumFoods(r.foods)
  const dec = r.decimals
  const top = `<section class="b-total"><div class="b-total-label">この食事の合計</div><div class="b-total-kcal" data-gt="total-kcal">${int(t.kcal)}<small>kcal</small></div>${bPfc3(t, dec, 'total')}</section>`
  const bottom = `<section class="b-foot"><div class="b-foot-top"><span class="lab">合計</span><span class="val" data-gt="total-kcal">${int(t.kcal)}<small>kcal</small></span></div>
<div class="b-foot-pfc"><span>P<b data-gt="total-p">${grams(t.p, dec)}</b>g</span><span>F<b data-gt="total-f">${grams(t.f, dec)}</b>g</span><span>C<b data-gt="total-c">${grams(t.c, dec)}</b>g</span></div></section>`
  const foods = r.foods
    .map(
      (x, i) => `<div class="b-food" data-gt="food-${i}">${bThumb(i, theme)}<div class="b-fbody"><div class="b-ftop"><span class="b-fname">${esc(x.name)}</span><span class="b-fkcal">${int(x.kcal)}<small>kcal</small></span></div>
<div class="b-famt">${esc(x.amount)}</div>${bChips(x, dec)}</div></div>`,
    )
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main>${bNav()}
<div class="b-mealhead"><span class="b-mealname">${MEAL_JP[r.meal]}</span><span class="b-mealdate">${jpDate(s.date)} ${r.time}</span></div>
${s.totalsPosition === 'top' ? top : ''}<div class="b-listhead"><span>食品</span><span>${r.foods.length}件</span></div>${foods}
${s.totalsPosition === 'bottom' ? bottom : ''}<div class="b-btn">＋ 食品を追加</div></main>${tabBar(B_TABS, 1)}`
  return doc(B_VARS[theme], B_CSS, body, s.dense ? 'dense' : '')
}

function renderBList(s: Extract<Screen, { layout: 'b-list' }>): string {
  const theme = s.theme ?? 'light'
  const r = s.record
  const t = sumFoods(r.foods)
  const foods = r.foods
    .map(
      (x, i) => `<div class="b-food" data-gt="food-${i}">${bThumb(i, theme)}<div class="b-fbody"><div class="b-ftop"><span class="b-fname">${esc(x.name)}</span><span class="b-fkcal">${int(x.kcal)}<small>kcal</small></span></div>
<div class="b-famt">${esc(x.amount)}</div></div></div>`,
    )
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main>${bNav()}
<div class="b-mealhead"><span class="b-mealname">${MEAL_JP[r.meal]}</span><span class="b-mealdate">${jpDate(s.date)} ${r.time}</span></div>
<div class="b-seg"><span class="on">食品</span><span>栄養</span></div>
<div class="b-sumline"><span class="lab">合計</span><span class="val" data-gt="total-kcal">${int(t.kcal)}<small>kcal</small></span></div>
<div class="b-listhead"><span>食品</span><span>${r.foods.length}件</span></div>${foods}<div class="b-btn">＋ 食品を追加</div></main>${tabBar(B_TABS, 1)}`
  return doc(B_VARS[theme], B_CSS, body)
}

function renderBNutrition(s: Extract<Screen, { layout: 'b-nutrition' }>): string {
  const theme = s.theme ?? 'light'
  const r = s.record
  const t = sumFoods(r.foods)
  const [sp, sf, sc] = energyShares(t)
  const ex = r.extras
  const row = (k: 'p' | 'f' | 'c', letter: string, label: string): string =>
    `<div class="ntab-row"><span class="k"><i style="background:var(--${letter})"></i>${label}</span><span class="v" data-gt="total-${k}">${grams(t[k], r.decimals)}<small>g</small></span></div>`
  const body = `${statusBar(s.clock, s.battery)}<main>${bNav()}
<div class="b-mealhead"><span class="b-mealname">${MEAL_JP[r.meal]}</span><span class="b-mealdate">${jpDate(s.date)} ${r.time}</span></div>
<div class="b-seg"><span>食品</span><span class="on">栄養</span></div>
<div class="b-sumline"><span class="lab">合計エネルギー</span><span class="val" data-gt="total-kcal">${int(t.kcal)}<small>kcal</small></span></div>
<div class="b-ratio"><div style="width:${sp}%;background:var(--P)">P ${sp}%</div><div style="width:${sf}%;background:var(--F)">F ${sf}%</div><div style="width:${sc}%;background:var(--C)">C ${sc}%</div></div>
<div class="b-ratio-cap"><span>PFCバランス（エネルギー比）</span><span>目標 P15 : F25 : C60</span></div>
<div class="ntab"><div class="ntab-row"><span class="k">エネルギー</span><span class="v">${int(t.kcal)}<small>kcal</small></span></div>
${row('p', 'P', 'たんぱく質')}${row('f', 'F', '脂質')}${row('c', 'C', '炭水化物')}
${ex ? `<div class="ntab-row minor"><span class="k">食物繊維</span><span class="v">${ex.fiber.toFixed(1)}g</span></div><div class="ntab-row minor"><span class="k">食塩相当量</span><span class="v">${ex.salt.toFixed(1)}g</span></div>` : ''}</div>
</main>${tabBar(B_TABS, 2)}`
  return doc(B_VARS[theme], B_CSS, body)
}

function renderBDay(s: Extract<Screen, { layout: 'b-day' }>): string {
  const theme = s.theme ?? 'light'
  const recs = sortRecords(s.records)
  const subs = recs.map((r) => sumFoods(r.foods))
  const day = sumShown(subs)
  const total = `<section class="b-total"><div class="b-total-label">1日の合計</div><div class="b-total-kcal" data-gt="total-kcal">${int(day.kcal)}<small>kcal</small></div>${bPfc3(day, false, 'total')}</section>`
  const cards = recs
    .map(
      (r, i) => `<section class="b-day-card"><div class="b-day-top"><span class="nm">${MEAL_JP[r.meal]}<i>${r.time}</i></span><span class="kc" data-gt="${r.meal}-kcal">${int(subs[i].kcal)}<small>kcal</small></span></div>
${bChips(subs[i], false, r.meal)}<div class="b-day-foods" data-gt="${r.meal}-foods">${r.foods.map((x) => esc(x.name)).join('、')}</div></section>`,
    )
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main>${bNav('共有')}
<div class="b-mealhead"><span class="b-mealname">1日の記録</span><span class="b-mealdate">${jpDate(s.date)}</span></div>
${s.totalPosition === 'top' ? total : ''}${cards}${s.totalPosition === 'bottom' ? total : ''}</main>${tabBar(B_TABS, 1)}`
  return doc(B_VARS[theme], B_CSS, body)
}

// ---------------------------------------------------------------------------
// アプリC「MealDiary」（英語 UI）
// ---------------------------------------------------------------------------

const C_VARS: Record<Theme, string> = {
  light:
    '--bg:#EDF0F5;--card:#FFFFFF;--text:#1A1F2A;--sub:#5F6880;--line:#DFE4EC;--accent:#1D5DC4;--band:#1D5DC4;--bandtext:#FFFFFF;--sbbg:#1D5DC4;--sbtext:#FFFFFF;--totalbg:#EAF1FC;--secbg:#F5F7FA;--good:#1E8A4C;--P:#7A58D3;--F:#E09A22;--C:#2A9DB2;--tabbg:#FFFFFF;--tabin:#98A1B0',
  dark:
    '--bg:#0B0E13;--card:#151A22;--text:#E7EBF2;--sub:#929BAD;--line:#262D39;--accent:#6AA3FF;--band:#122444;--bandtext:#E7EBF2;--sbbg:#122444;--sbtext:#E7EBF2;--totalbg:#1A2436;--secbg:#19202B;--good:#4CC27F;--P:#9A80F0;--F:#F0B24A;--C:#4BC0D4;--tabbg:#10141B;--tabin:#5E6778',
}

const C_CSS = `
.c-hdr{background:var(--band);color:var(--bandtext);padding:0 16px 12px}
.c-hdr-top{display:flex;justify-content:space-between;align-items:center;height:42px}
.c-logo{font-size:20px;font-weight:700;display:flex;align-items:center;gap:7px;letter-spacing:.01em}
.c-logo svg{width:22px;height:22px;display:block}
.c-hdr-icons{display:flex;gap:16px} .c-hdr-icons .ic{width:21px;height:21px}
.c-date{display:flex;justify-content:space-between;align-items:center;font-size:15px;font-weight:700;padding-top:2px}
.c-date .ic{width:20px;height:20px;opacity:.85}
.c-mealtitle{display:flex;justify-content:space-between;align-items:baseline;padding:14px 18px 8px}
.c-mealtitle b{font-size:20px} .c-mealtitle span{font-size:12px;color:var(--sub)}
.c-card{background:var(--card);margin:0 12px 12px;border-radius:10px;overflow:hidden;border:1px solid var(--line)}
table{width:100%;border-collapse:collapse;table-layout:fixed}
th{font-size:11px;color:var(--sub);font-weight:400;text-align:right;padding:9px 6px 1px;white-space:nowrap}
tr.units th{padding:0 6px 6px;font-size:10px}
th.nm,td.nm{text-align:left;padding-left:12px}
th:last-child,td:last-child{padding-right:12px}
td{font-size:14px;text-align:right;padding:9px 6px;border-top:1px solid var(--line);vertical-align:top;white-space:nowrap}
td.nm{white-space:normal}
td .srv{font-size:11px;color:var(--sub);margin-top:2px}
tr.total td{font-weight:700;background:var(--totalbg);font-size:15px;color:var(--text)}
tr.total td.nm{color:var(--accent)}
tr.sec td{background:var(--secbg);font-weight:700;font-size:13px;padding:7px 6px}
tr.sec td.nm{padding-left:12px}
tr.it td{font-size:12px;color:var(--sub);padding:4px 6px;border-top:none}
tr.it td.nm{padding-left:22px}
tr.goal td{font-size:12px;color:var(--sub);padding:6px 6px}
tr.remain td{font-size:13px;color:var(--good);font-weight:700;padding:6px 6px}
.c-goal{margin:0 12px 12px;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.c-goal .t{font-size:13px;font-weight:700;margin-bottom:8px}
.c-goal .eq{display:flex;justify-content:space-between;align-items:flex-end;text-align:center;font-size:15px}
.c-goal .eq div span{display:block;font-size:10px;color:var(--sub);margin-top:2px}
.c-goal .eq .op{color:var(--sub);padding-bottom:12px}
.c-goal .eq .rem{color:var(--good);font-weight:700;font-size:17px}
.c-add{margin:0 12px;padding:10px;text-align:center;color:var(--accent);font-weight:700;font-size:14px;border:1px solid var(--line);border-radius:10px;background:var(--card)}
.c-seg{display:flex;margin:12px 12px 10px;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:3px}
.c-seg span{flex:1;text-align:center;font-size:13px;padding:6px 0;border-radius:6px;color:var(--sub)}
.c-seg span.on{background:var(--accent);color:#fff;font-weight:700}
.c-filter{display:flex;justify-content:space-between;align-items:center;margin:0 18px 10px;font-size:13px;color:var(--sub)}
.c-filter b{color:var(--text);font-size:15px;display:inline-flex;align-items:center;gap:2px} .c-filter .ic{width:16px;height:16px}
.c-donut-wrap{padding:16px 14px 6px}
.c-donut{width:168px;height:168px;border-radius:50%;margin:0 auto 14px;display:flex;align-items:center;justify-content:center}
.c-donut-in{width:112px;height:112px;border-radius:50%;background:var(--card);display:flex;flex-direction:column;align-items:center;justify-content:center}
.c-donut-in .n{font-size:28px;font-weight:700;line-height:1.1} .c-donut-in .u{font-size:12px;color:var(--sub)}
.mac th{padding-top:4px}
.mac td{font-size:14px;padding:10px 6px}
.mac td.nm{display:flex;align-items:center;gap:8px}
.mac .sw{width:11px;height:11px;border-radius:50%;flex:none}
.mac td.g{font-size:17px;font-weight:700}
.mac td.goalpc{color:var(--sub);font-size:13px}
.c-foot{display:flex;justify-content:space-between;align-items:baseline;padding:11px 14px;border-top:1px solid var(--line);font-size:14px}
.c-foot b{font-size:18px}
/* dense */
.dense .c-mealtitle{padding:10px 16px 6px} .dense .c-mealtitle b{font-size:17px}
.dense td{font-size:11px;padding:4px 5px} .dense td .srv{font-size:9.5px;margin-top:0}
.dense th{font-size:10px;padding:6px 5px 1px} .dense tr.units th{font-size:9px;padding:0 5px 3px}
.dense tr.total td{font-size:12px;padding:6px 5px}
.dense .c-add{padding:8px;font-size:13px}
.dense th.nm,.dense td.nm{padding-left:10px} .dense th:last-child,.dense td:last-child{padding-right:10px}
`

const C_LOGO = `<svg viewBox="0 0 22 22"><circle cx="11" cy="11" r="10" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.5 6.5v4a2 2 0 0 0 4 0v-4M9.5 6.5v9M14.5 6.5c-1.5 1-1.6 4.4 0 5v4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`
const C_TABS: [string, string][] = [
  ['book', 'Diary'],
  ['chart', 'Progress'],
  ['search', 'Foods'],
  ['more', 'More'],
]

function cHeader(date: string): string {
  return `<header class="c-hdr"><div class="c-hdr-top"><span class="c-logo">${C_LOGO}MealDiary</span><span class="c-hdr-icons">${icon('calendar')}${icon('user')}</span></div>
<div class="c-date">${icon('chevL')}<span>${enDate(date)}</span>${icon('chevR')}</div></header>`
}

function cColgroup(nameW: number): string {
  return `<colgroup><col style="width:${nameW}px"><col style="width:66px"><col style="width:58px"><col style="width:46px"><col style="width:56px"></colgroup>`
}

function cHead(): string {
  return `<thead><tr><th class="nm">Food</th><th>Calories</th><th>Protein</th><th>Fat</th><th>Carbs</th></tr><tr class="units"><th class="nm"></th><th>kcal</th><th>g</th><th>g</th><th>g</th></tr></thead>`
}

function renderCMeal(s: Extract<Screen, { layout: 'c-meal' }>): string {
  const r = s.record
  const t = sumFoods(r.foods)
  const dec = r.decimals
  const rows = r.foods
    .map(
      (x, i) =>
        `<tr data-gt="food-${i}"><td class="nm"><div>${esc(x.name)}</div><div class="srv">${esc(x.amount)}</div></td><td>${int(x.kcal)}</td><td>${grams(x.p, dec)}</td><td>${grams(x.f, dec)}</td><td>${grams(x.c, dec)}</td></tr>`,
    )
    .join('')
  const total = `<tr class="total"><td class="nm">Total</td><td data-gt="total-kcal">${int(t.kcal)}</td><td data-gt="total-p">${grams(t.p, dec)}</td><td data-gt="total-f">${grams(t.f, dec)}</td><td data-gt="total-c">${grams(t.c, dec)}</td></tr>`
  let goal = ''
  if (s.dailyGoal) {
    const food = s.dailyGoal.otherMealsKcal + t.kcal
    goal = `<section class="c-goal"><div class="t">Calories Remaining (today)</div><div class="eq"><div>${int(s.dailyGoal.goal)}<span>Goal</span></div><div class="op">−</div><div>${int(food)}<span>Food</span></div><div class="op">+</div><div>0<span>Exercise</span></div><div class="op">=</div><div class="rem">${int(s.dailyGoal.goal - food)}<span>Remaining</span></div></div></section>`
  }
  const body = `${statusBar(s.clock, s.battery)}<main>${cHeader(s.date)}
<div class="c-mealtitle"><b>${MEAL_EN[r.meal]}</b><span>Logged ${enTime(r.time)} · ${r.foods.length} items</span></div>
<section class="c-card"><table>${cColgroup(s.dense ? 128 : 136)}${cHead()}<tbody>${rows}${total}</tbody></table></section>
${goal}<div class="c-add">+ Add Food</div></main>${tabBar(C_TABS, 0)}`
  return doc(C_VARS[s.theme ?? 'light'], C_CSS, body, s.dense ? 'dense' : '')
}

function renderCList(s: Extract<Screen, { layout: 'c-list' }>): string {
  const r = s.record
  const t = sumFoods(r.foods)
  const rows = r.foods
    .map(
      (x, i) =>
        `<tr data-gt="food-${i}"><td class="nm"><div>${esc(x.name)}</div><div class="srv">${esc(x.amount)}</div></td><td>${int(x.kcal)}</td></tr>`,
    )
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main>${cHeader(s.date)}
<div class="c-mealtitle"><b>${MEAL_EN[r.meal]}</b><span>Logged ${enTime(r.time)} · ${r.foods.length} items</span></div>
<section class="c-card"><table><colgroup><col><col style="width:110px"></colgroup><thead><tr><th class="nm">Food</th><th>Calories (kcal)</th></tr></thead><tbody>${rows}
<tr class="total"><td class="nm">Total</td><td data-gt="total-kcal">${int(t.kcal)}</td></tr></tbody></table></section>
<div class="c-add">+ Add Food</div></main>${tabBar(C_TABS, 0)}`
  return doc(C_VARS[s.theme ?? 'light'], C_CSS, body)
}

function renderCNutrition(s: Extract<Screen, { layout: 'c-nutrition' }>): string {
  const r = s.record
  const t = sumFoods(r.foods)
  const [sp, sf, sc] = energyShares(t)
  // MealDiary は Carbs → Fat → Protein の順で表示する
  const a = sc
  const b = sc + sf
  const row = (k: 'p' | 'f' | 'c', letter: string, label: string, pc: number, goalPc: number): string =>
    `<tr><td class="nm"><span class="sw" style="background:var(--${letter})"></span>${label}</td><td class="g" data-gt="total-${k}">${grams(t[k], r.decimals)} g</td><td>${pc}%</td><td class="goalpc">${goalPc}%</td></tr>`
  const body = `${statusBar(s.clock, s.battery)}<main>${cHeader(s.date)}
<div class="c-seg"><span>Calories</span><span>Nutrients</span><span class="on">Macros</span></div>
<div class="c-filter"><span>Showing</span><b>${MEAL_EN[r.meal]}${icon('chevD')}</b></div>
<section class="c-card"><div class="c-donut-wrap"><div class="c-donut" style="background:conic-gradient(var(--C) 0 ${a}%, var(--F) ${a}% ${b}%, var(--P) ${b}% 100%)"><div class="c-donut-in"><div class="n" data-gt="total-kcal">${int(t.kcal)}</div><div class="u">kcal</div></div></div></div>
<table class="mac"><colgroup><col><col style="width:84px"><col style="width:58px"><col style="width:58px"></colgroup><thead><tr><th class="nm">Macro</th><th>Total</th><th>%</th><th>Goal</th></tr></thead><tbody>
${row('c', 'C', 'Carbohydrates', sc, 50)}${row('f', 'F', 'Fat', sf, 30)}${row('p', 'P', 'Protein', sp, 20)}</tbody></table>
<div class="c-foot"><span>Total Calories</span><b>${int(t.kcal)} kcal</b></div></section></main>${tabBar(C_TABS, 1)}`
  return doc(C_VARS[s.theme ?? 'light'], C_CSS, body)
}

function renderCDay(s: Extract<Screen, { layout: 'c-day' }>): string {
  const recs = sortRecords(s.records)
  const subs = recs.map((r) => sumFoods(r.foods))
  const day = sumShown(subs)
  const g: DayGoal = s.goal
  const sections = recs
    .map((r, i) => {
      const t = subs[i]
      const items = r.foods
        .map(
          (x, j) =>
            `<tr class="it" data-gt="food-${r.meal}-${j}"><td class="nm">${esc(x.name)}</td><td>${int(x.kcal)}</td><td>${x.p}</td><td>${x.f}</td><td>${x.c}</td></tr>`,
        )
        .join('')
      return `<tr class="sec"><td class="nm">${MEAL_EN[r.meal]}</td><td data-gt="${r.meal}-kcal">${int(t.kcal)}</td><td data-gt="${r.meal}-p">${t.p}</td><td data-gt="${r.meal}-f">${t.f}</td><td data-gt="${r.meal}-c">${t.c}</td></tr>${items}`
    })
    .join('')
  const rem = (goal: number, v: number): string => int(goal - v)
  const body = `${statusBar(s.clock, s.battery)}<main>${cHeader(s.date)}
<div class="c-mealtitle"><b>Daily Diary</b><span>4 meals logged</span></div>
<section class="c-card"><table>${cColgroup(136)}${cHead()}<tbody>${sections}
<tr class="total"><td class="nm">Daily Total</td><td data-gt="total-kcal">${int(day.kcal)}</td><td data-gt="total-p">${day.p}</td><td data-gt="total-f">${day.f}</td><td data-gt="total-c">${day.c}</td></tr>
<tr class="goal"><td class="nm">Goal</td><td>${int(g.kcal)}</td><td>${g.p}</td><td>${g.f}</td><td>${g.c}</td></tr>
<tr class="remain"><td class="nm">Remaining</td><td>${rem(g.kcal, day.kcal)}</td><td>${rem(g.p, day.p)}</td><td>${rem(g.f, day.f)}</td><td>${rem(g.c, day.c)}</td></tr>
</tbody></table></section></main>${tabBar(C_TABS, 0)}`
  return doc(C_VARS[s.theme ?? 'light'], C_CSS, body)
}

// ---------------------------------------------------------------------------
// 食事以外のアプリ
// ---------------------------------------------------------------------------

function weatherIcon(kind: WeatherIcon, size: number): string {
  const sun = (cx: number, cy: number, r: number): string =>
    `<g stroke="#FFC83D" stroke-width="2" stroke-linecap="round">${[0, 45, 90, 135, 180, 225, 270, 315]
      .map((deg) => {
        const rad = (deg * Math.PI) / 180
        const x1 = cx + Math.cos(rad) * (r + 3)
        const y1 = cy + Math.sin(rad) * (r + 3)
        const x2 = cx + Math.cos(rad) * (r + 6)
        const y2 = cy + Math.sin(rad) * (r + 6)
        return `<line x1="${x1.toFixed(2)}" y1="${y1.toFixed(2)}" x2="${x2.toFixed(2)}" y2="${y2.toFixed(2)}"/>`
      })
      .join('')}</g><circle cx="${cx}" cy="${cy}" r="${r}" fill="#FFC83D"/>`
  const cloud = (dx: number, dy: number, fill: string): string =>
    `<path transform="translate(${dx} ${dy})" d="M8 26h17a6 6 0 0 0 0-12 8 8 0 0 0-15.3-2.2A6.2 6.2 0 0 0 8 26z" fill="${fill}"/>`
  let inner = ''
  if (kind === 'sun') inner = sun(18, 18, 7)
  if (kind === 'partly') inner = sun(13, 13, 6) + cloud(3, 4, '#FFFFFF')
  if (kind === 'cloud') inner = cloud(1, 0, '#E8EEF5')
  if (kind === 'rain')
    inner =
      cloud(1, -3, '#D5DEE9') +
      '<g stroke="#7FC4FF" stroke-width="2" stroke-linecap="round"><line x1="12" y1="27" x2="10" y2="32"/><line x1="18" y1="27" x2="16" y2="32"/><line x1="24" y1="27" x2="22" y2="32"/></g>'
  return `<svg width="${size}" height="${size}" viewBox="0 0 36 36">${inner}</svg>`
}

function renderWeather(s: Extract<Screen, { layout: 'weather' }>): string {
  const w: WeatherData = s.data
  const css = `
body{background:linear-gradient(180deg,#2F6FC9 0%,#4C8EDC 45%,#7DB3EC 100%);color:#fff}
.w-top{display:flex;justify-content:space-between;align-items:center;padding:6px 20px 0;font-size:13px;opacity:.95}
.w-top .ic{width:20px;height:20px}
.w-place{display:flex;align-items:center;gap:4px;font-size:18px;font-weight:700;justify-content:center;margin-top:10px}
.w-place .ic{width:18px;height:18px}
.w-now{text-align:center;font-size:84px;line-height:1.05;margin-top:4px;font-weight:400}
.w-cond{text-align:center;font-size:18px}
.w-hl{text-align:center;font-size:15px;margin-top:4px;opacity:.95}
.w-card{margin:14px 16px 0;background:rgba(255,255,255,.17);border-radius:16px;padding:12px 14px}
.w-card h3{font-size:12px;font-weight:400;opacity:.85;margin-bottom:8px}
.w-hours{display:flex;justify-content:space-between;text-align:center;font-size:13px}
.w-hours .t{font-size:16px;font-weight:700}
.w-hours .pop{font-size:11px;color:#CFE8FF}
.w-day{display:flex;align-items:center;padding:5px 0;font-size:14px;border-top:1px solid rgba(255,255,255,.18)}
.w-day:first-of-type{border-top:none}
.w-day .l{width:96px} .w-day .pop{width:56px;color:#CFE8FF;font-size:12px;text-align:right} .w-day .r{flex:1;text-align:right;font-weight:700}
.w-grid{display:grid;grid-template-columns:1fr 1.5fr 1fr 1.2fr;gap:8px;margin:12px 16px 0}
.w-grid div{background:rgba(255,255,255,.17);border-radius:12px;padding:8px 10px;font-size:11px;opacity:.95}
.w-grid b{display:block;font-size:15px;margin-top:2px;white-space:nowrap}
`
  const vars =
    '--bg:#2F6FC9;--text:#FFFFFF;--sub:#DCEBFF;--line:rgba(255,255,255,.25);--accent:#FFFFFF;--tabbg:rgba(20,60,120,.35);--tabin:rgba(255,255,255,.6)'
  const hours = w.hourly
    .map((h) => `<div><div>${h.hour}</div>${weatherIcon(h.icon, 34)}<div class="t">${h.temp}°</div><div class="pop">${h.pop}%</div></div>`)
    .join('')
  const days = w.daily
    .map(
      (d) =>
        `<div class="w-day"><span class="l">${d.label}</span>${weatherIcon(d.icon, 28)}<span class="pop">${d.pop}%</span><span class="r">${d.high}° / <span style="opacity:.8">${d.low}°</span></span></div>`,
    )
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main>
<div class="w-top"><span>そらもよう</span>${icon('more')}</div>
<div class="w-place">${icon('pin')}${esc(w.place)}</div>
<div class="w-now">${w.now}°</div><div class="w-cond">${esc(w.condition)}</div><div class="w-hl">最高 ${w.high}° ／ 最低 ${w.low}°</div>
<section class="w-card"><h3>1時間ごとの天気</h3><div class="w-hours">${hours}</div></section>
<section class="w-card"><h3>週間予報</h3>${days}</section>
<div class="w-grid"><div>湿度<b>${w.humidity}%</b></div><div>風<b>${esc(w.wind)}</b></div><div>UV指数<b>${w.uv}</b></div><div>気圧<b>${w.pressure}hPa</b></div></div>
</main>${tabBar(
    [
      ['home', '天気'],
      ['umbrella', '雨雲'],
      ['bell', '警報'],
      ['gear', '設定'],
    ],
    0,
  )}`
  return doc(vars, css, body)
}

function renderChat(s: Extract<Screen, { layout: 'chat' }>): string {
  const c: ChatData = s.data
  const css = `
.ch-nav{display:flex;align-items:center;justify-content:space-between;height:48px;padding:0 12px;background:var(--navbg);border-bottom:1px solid var(--line)}
.ch-back{display:flex;align-items:center;gap:2px;color:var(--accent);font-size:16px;width:80px} .ch-back .ic{width:22px;height:22px}
.ch-back em{font-style:normal;background:var(--accent);color:#fff;border-radius:10px;font-size:12px;padding:0 7px;margin-left:2px}
.ch-title{font-size:17px;font-weight:700}
.ch-icons{display:flex;gap:16px;width:80px;justify-content:flex-end;color:var(--accent)} .ch-icons .ic{width:22px;height:22px}
.ch-body{padding:10px 14px}
.ch-date{text-align:center;margin:4px 0 12px} .ch-date span{background:rgba(0,0,0,.08);color:var(--sub);font-size:11px;padding:3px 10px;border-radius:10px}
.msg{display:flex;align-items:flex-end;gap:6px;margin-bottom:10px}
.msg.me{flex-direction:row-reverse}
.av{width:34px;height:34px;border-radius:50%;background:#F3B27A;color:#fff;font-size:15px;font-weight:700;display:flex;align-items:center;justify-content:center;flex:none;align-self:flex-start}
.av.hide{visibility:hidden}
.bub{max-width:232px;padding:9px 12px;border-radius:17px;font-size:15px;line-height:1.45;background:var(--them);color:var(--text)}
.me .bub{background:var(--accent);color:#fff}
.meta{font-size:10px;color:var(--sub);line-height:1.3;text-align:right;white-space:nowrap}
.msg:not(.me) .meta{text-align:left}
.ch-input{height:94px;flex:none;background:var(--navbg);border-top:1px solid var(--line);display:flex;align-items:flex-start;gap:10px;padding:9px 12px 0;position:relative}
.ch-input .ic{width:26px;height:26px;color:var(--sub);margin-top:5px}
.ch-field{flex:1;height:36px;border-radius:18px;background:var(--them);border:1px solid var(--line);color:var(--sub);font-size:14px;display:flex;align-items:center;padding:0 14px}
`
  const vars =
    '--bg:#EEF0F4;--navbg:#F8F8FA;--them:#FFFFFF;--text:#1C1D21;--sub:#80848D;--line:#DADCE2;--accent:#5A55D6'
  let prev: string | null = null
  const msgs = c.messages
    .map((m) => {
      const showAv = m.from === 'them' && prev !== 'them'
      prev = m.from
      const meta = m.from === 'me' ? `<div class="meta">${m.read ? '既読<br>' : ''}${m.time}</div>` : `<div class="meta">${m.time}</div>`
      const av = m.from === 'them' ? `<div class="av${showAv ? '' : ' hide'}">${esc(c.partner.slice(0, 1))}</div>` : ''
      return `<div class="msg ${m.from}">${av}<div class="bub">${esc(m.text)}</div>${meta}</div>`
    })
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main>
<div class="ch-nav"><span class="ch-back">${icon('chevL')}<em>${c.unread}</em></span><span class="ch-title">${esc(c.partner)}</span><span class="ch-icons">${icon('phone')}${icon('menu')}</span></div>
<div class="ch-body"><div class="ch-date"><span>今日</span></div>${msgs}</div></main>
<div class="ch-input tabbar-like">${icon('plus')}${icon('camera')}<div class="ch-field">メッセージを入力</div>${icon('smile')}<div class="home-ind"></div></div>`
  return doc(vars, css, body)
}

function renderSteps(s: Extract<Screen, { layout: 'steps' }>): string {
  const d: StepsData = s.data
  const pct = Math.min(100, (d.steps / d.goal) * 100).toFixed(1)
  const max = Math.max(...d.week.map((x) => x.steps))
  const avg = Math.round(d.week.reduce((a, x) => a + x.steps, 0) / d.week.length)
  const h = Math.floor(d.activeMin / 60)
  const m = d.activeMin % 60
  const css = `
.st-top{display:flex;justify-content:space-between;align-items:center;padding:6px 18px 0;height:44px}
.st-brand{display:flex;align-items:center;gap:7px;font-size:18px;font-weight:700;color:var(--accent)} .st-brand .ic{width:24px;height:24px}
.st-date{font-size:14px;color:var(--sub)}
.st-ring{width:210px;height:210px;border-radius:50%;margin:12px auto 0;display:flex;align-items:center;justify-content:center}
.st-ring-in{width:176px;height:176px;border-radius:50%;background:var(--bg);display:flex;flex-direction:column;align-items:center;justify-content:center}
.st-ring-in .l{font-size:13px;color:var(--sub)} .st-ring-in .n{font-size:40px;font-weight:700;line-height:1.15} .st-ring-in .u{font-size:13px;color:var(--sub)}
.st-goal{text-align:center;font-size:13px;color:var(--sub);margin-top:8px}
.st-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:14px 16px 0}
.st-grid div{background:var(--card);border-radius:14px;padding:10px 14px;font-size:12px;color:var(--sub)}
.st-grid b{display:block;font-size:22px;color:var(--text);margin-top:2px} .st-grid b small{font-size:12px;font-weight:400;color:var(--sub);margin-left:3px}
.st-week{margin:12px 16px 0;background:var(--card);border-radius:14px;padding:12px 14px 10px}
.st-week h3{font-size:13px;display:flex;justify-content:space-between;margin-bottom:8px} .st-week h3 span{font-weight:400;color:var(--sub);font-size:12px}
.st-bars{display:flex;justify-content:space-between;align-items:flex-end;height:84px}
.st-bars div{width:28px;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;font-size:11px;color:var(--sub)}
.st-bars i{display:block;width:16px;border-radius:5px 5px 2px 2px;background:var(--track);margin-bottom:4px}
.st-bars .today i{background:var(--accent)} .st-bars .today{color:var(--accent);font-weight:700}
`
  const vars =
    '--bg:#F2F6F3;--card:#FFFFFF;--text:#1D2420;--sub:#6D7771;--line:#E1E8E3;--accent:#24985F;--track:#BFE3CF;--tabbg:#FFFFFF;--tabin:#9AA39E'
  const bars = d.week
    .map(
      (x, i) =>
        `<div class="${i === d.week.length - 1 ? 'today' : ''}"><i style="height:${Math.round((x.steps / max) * 62)}px"></i>${x.label}</div>`,
    )
    .join('')
  const body = `${statusBar(s.clock, s.battery)}<main>
<div class="st-top"><span class="st-brand">${icon('shoe')}てくてくメーター</span><span class="st-date">${jpDate(s.date)}</span></div>
<div class="st-ring" style="background:conic-gradient(var(--accent) 0 ${pct}%, var(--track) ${pct}% 100%)"><div class="st-ring-in"><div class="l">今日の歩数</div><div class="n">${int(d.steps)}</div><div class="u">歩</div></div></div>
<div class="st-goal">目標 ${int(d.goal)} 歩まで あと ${int(Math.max(0, d.goal - d.steps))} 歩</div>
<div class="st-grid"><div>距離<b>${d.distanceKm.toFixed(1)}<small>km</small></b></div><div>消費カロリー<b>${int(d.burnedKcal)}<small>kcal</small></b></div><div>活動時間<b>${h}<small>時間</small>${m}<small>分</small></b></div><div>脂肪燃焼量<b>約${d.fatBurnG}<small>g</small></b></div></div>
<section class="st-week"><h3>今週の歩数<span>平均 ${int(avg)} 歩</span></h3><div class="st-bars">${bars}</div></section>
</main>${tabBar(
    [
      ['home', 'ホーム'],
      ['chart', '記録'],
      ['trophy', 'ランキング'],
      ['gear', '設定'],
    ],
    0,
  )}`
  return doc(vars, css, body)
}

// ---------------------------------------------------------------------------
// ディスパッチ
// ---------------------------------------------------------------------------

function sortRecords(records: MealRecord[]): MealRecord[] {
  return [...records].sort((a, b) => MEAL_ORDER.indexOf(a.meal) - MEAL_ORDER.indexOf(b.meal))
}

function renderScreen(s: Screen): string {
  switch (s.layout) {
    case 'a-meal':
      return renderAMeal(s)
    case 'a-list':
      return renderAList(s)
    case 'a-nutrition':
      return renderANutrition(s)
    case 'a-day':
      return renderADay(s)
    case 'b-meal':
      return renderBMeal(s)
    case 'b-list':
      return renderBList(s)
    case 'b-nutrition':
      return renderBNutrition(s)
    case 'b-day':
      return renderBDay(s)
    case 'c-meal':
      return renderCMeal(s)
    case 'c-list':
      return renderCList(s)
    case 'c-nutrition':
      return renderCNutrition(s)
    case 'c-day':
      return renderCDay(s)
    case 'weather':
      return renderWeather(s)
    case 'chat':
      return renderChat(s)
    case 'steps':
      return renderSteps(s)
  }
}

// ---------------------------------------------------------------------------
// 期待値の導出と整合性チェック
// ---------------------------------------------------------------------------

function fail(id: string, msg: string): never {
  throw new Error(`[${id}] ${msg}`)
}

function checkFood(id: string, x: FoodItem, decimals: boolean | undefined): void {
  for (const k of ['kcal', 'p', 'f', 'c'] as const) {
    const v = x[k]
    if (!Number.isFinite(v) || v < 0) fail(id, `${x.name}.${k} が不正: ${v}`)
    if (k === 'kcal' || !decimals) {
      if (!Number.isInteger(v)) fail(id, `${x.name}.${k} は整数にしてください: ${v}`)
    } else if (Math.abs(v * 10 - Math.round(v * 10)) > 1e-9) {
      fail(id, `${x.name}.${k} は小数第1位までにしてください: ${v}`)
    }
  }
  const atw = 4 * x.p + 9 * x.f + 4 * x.c
  if (Math.abs(x.kcal - atw) > Math.max(0.12 * x.kcal, 8)) {
    fail(id, `${x.name}: kcal ${x.kcal} と 4P+9F+4C=${atw.toFixed(1)} が離れすぎ`)
  }
}

/** 正解として採点する合計は kcal ≈ 4P+9F+4C（±5%） */
function checkAtwater(id: string, label: string, s: Shown): void {
  const atw = atwater(s)
  const dev = Math.abs(s.kcal - atw) / s.kcal
  if (dev > 0.05) fail(id, `${label}: kcal ${s.kcal} vs 4P+9F+4C=${atw.toFixed(1)}（${(dev * 100).toFixed(1)}%）`)
}

function checkRecord(id: string, r: MealRecord): Shown {
  if (r.foods.length === 0) fail(id, 'foods が空')
  for (const x of r.foods) checkFood(id, x, r.decimals)
  const t = sumFoods(r.foods)
  checkAtwater(id, `${r.meal} 合計`, t)
  return t
}

function sameShown(a: Shown, b: Shown): boolean {
  return a.kcal === b.kcal && a.p === b.p && a.f === b.f && a.c === b.c
}

const MEAL_LAYOUT = /^(a|b|c)-/

function deriveTags(c: CaseSpec): string[] {
  const tags: string[] = []
  const layouts = new Set<string>()
  for (const s of c.screens) {
    const m = MEAL_LAYOUT.exec(s.layout)
    if (m) layouts.add(`layout-${m[1]}`)
  }
  tags.push(...[...layouts].sort())
  switch (c.kind) {
    case 'single':
      tags.push('single')
      break
    case 'day-view':
      tags.push('day-view')
      break
    case 'two-image':
      tags.push('two-image', 'consistent')
      break
    case 'mismatch':
      tags.push('two-image', 'mismatch')
      break
    case 'non-meal':
      tags.push('non-meal')
      break
  }
  if (c.screens.some((s) => s.theme === 'dark')) tags.push('dark')
  if (c.screens.some((s) => s.dense)) tags.push('dense')
  if (c.screens.some((s) => 'record' in s && s.record.decimals)) tags.push('decimal')
  if (c.screens.some((s) => s.layout.startsWith('c-'))) tags.push('english')
  for (const t of c.extraTags ?? []) if (!tags.includes(t)) tags.push(t)
  return tags
}

function deriveExpected(c: CaseSpec): OutCase['expected'] {
  const id = c.id
  const n = c.screens.length
  if (n < 1 || n > 3) fail(id, `画像は 1〜3 枚: ${n}`)
  switch (c.kind) {
    case 'single': {
      if (n !== 1) fail(id, 'single は 1 枚')
      const s = c.screens[0]
      if (!('record' in s)) fail(id, 'single は record を持つ画面が必要')
      if (s.layout.endsWith('-list') || s.layout.endsWith('-nutrition')) fail(id, 'single に list/nutrition 画面は使わない')
      const t = checkRecord(id, s.record)
      if (s.record.meal !== c.meal_type) fail(id, `meal_type ${c.meal_type} と画面の ${s.record.meal} が違う`)
      if (s.record.decimals) {
        const fracs = [t.p, t.f, t.c].filter((v) => v - Math.floor(v) >= 0.5 - 1e-9)
        if (fracs.length < 2) fail(id, 'decimal ケースは P/F/C のうち 2 つ以上を .5 以上にして切り捨てと四捨五入を区別できるようにする')
      }
      return { is_meal: true, totals: toTotals(t), foods_count: s.record.foods.length, expect_warning: null, app_name: c.app_name }
    }
    case 'day-view': {
      if (n !== 1) fail(id, 'day-view は 1 枚')
      const s = c.screens[0]
      if (!('records' in s)) fail(id, 'day-view は records を持つ画面が必要')
      const meals = s.records.map((r) => r.meal)
      if (MEAL_ORDER.some((m) => !meals.includes(m)) || meals.length !== 4) fail(id, '朝昼夕間食の 4 食が必要')
      const subs = s.records.map((r) => checkRecord(id, r))
      const day = sumShown(subs)
      checkAtwater(id, '1日合計', day)
      const maxK = Math.max(...subs.map((x) => x.kcal))
      const largest = subs.filter((x) => x.kcal === maxK)
      if (largest.length !== 1) fail(id, '最大の食事が 1 つに決まらない')
      const li = subs.findIndex((x) => x.kcal === maxK)
      if (s.records[li].meal !== c.meal_type) fail(id, `meal_type は最大の食事（${s.records[li].meal}）に合わせる`)
      return {
        is_meal: true,
        totals: toTotals(day),
        alt_totals: [toTotals(subs[li])],
        foods_count: null,
        expect_warning: null,
        app_name: c.app_name,
      }
    }
    case 'two-image': {
      if (n !== 2) fail(id, 'two-image は 2 枚')
      const [s1, s2] = c.screens
      if (!s1.layout.endsWith('-list') || !s2.layout.endsWith('-nutrition')) fail(id, '1枚目 list / 2枚目 nutrition')
      if (!('record' in s1) || !('record' in s2)) fail(id, 'record が必要')
      const t1 = checkRecord(id, s1.record)
      const t2 = checkRecord(id, s2.record)
      if (!sameShown(t1, t2)) fail(id, '2 枚の合計が一致しない（同じ食事のはず）')
      if (s1.date !== s2.date || s1.record.meal !== s2.record.meal) fail(id, '2 枚の日付/食事区分が一致しない')
      if (s1.record.meal !== c.meal_type) fail(id, 'meal_type と画面の食事区分が違う')
      return { is_meal: true, totals: toTotals(t2), foods_count: s1.record.foods.length, expect_warning: false, app_name: c.app_name }
    }
    case 'mismatch': {
      if (n !== 2) fail(id, 'mismatch は 2 枚')
      const [s1, s2] = c.screens
      if (!s1.layout.endsWith('-list') || !s2.layout.endsWith('-nutrition')) fail(id, '1枚目 list / 2枚目 nutrition')
      if (!('record' in s1) || !('record' in s2)) fail(id, 'record が必要')
      const t1 = checkRecord(id, s1.record)
      const t2 = checkRecord(id, s2.record)
      const kdiff = Math.abs(t2.kcal - t1.kcal) / t1.kcal
      if (kdiff < 0.3) fail(id, `2 枚の kcal 差が 30% 未満: ${t1.kcal} vs ${t2.kcal}`)
      const pfcVsImg1 = Math.abs(atwater(t2) - t1.kcal) / t1.kcal
      if (pfcVsImg1 < 0.25) fail(id, `2枚目の PFC が 1枚目の kcal と噛み合ってしまう（${(pfcVsImg1 * 100).toFixed(1)}%）`)
      return { is_meal: true, totals: null, foods_count: null, expect_warning: true, app_name: c.app_name }
    }
    case 'non-meal': {
      if (n !== 1) fail(id, 'non-meal は 1 枚')
      const s = c.screens[0]
      if (MEAL_LAYOUT.test(s.layout)) fail(id, 'non-meal に食事アプリの画面は使わない')
      return { is_meal: false, totals: null, foods_count: 0, expect_warning: null, app_name: c.app_name }
    }
  }
}

// ---------------------------------------------------------------------------
// 撮影
// ---------------------------------------------------------------------------

/**
 * ページ内チェック: 正解の数値（data-gt）がすべてタブバーより上・画面内に収まっているか、
 * 横はみ出しがないか。tsx の関数変換を避けるため文字列で渡す。
 */
const PAGE_CHECK = `(() => {
  const vw = window.innerWidth, vh = window.innerHeight
  const bottomBar = document.querySelector('.tabbar, .ch-input')
  const limit = bottomBar ? bottomBar.getBoundingClientRect().top : vh
  const bad = []
  for (const el of document.querySelectorAll('[data-gt]')) {
    const r = el.getBoundingClientRect()
    if (r.width === 0 || r.height === 0 || r.top < 0 || r.bottom > limit + 0.5 || r.left < 0 || r.right > vw + 0.5) {
      bad.push(el.getAttribute('data-gt') + ' @ ' + [r.left, r.top, r.right, r.bottom].map(v => Math.round(v)).join(','))
    }
    if (el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1) bad.push(el.getAttribute('data-gt') + ' overflows its box')
  }
  if (document.documentElement.scrollWidth > vw) bad.push('horizontal overflow ' + document.documentElement.scrollWidth)
  const main = document.querySelector('main')
  return { bad, mainFill: main ? Math.round(main.scrollHeight) + '/' + Math.round(main.clientHeight) : '' }
})()`

async function emptyDir(dir: string, ext: string): Promise<void> {
  await mkdir(dir, { recursive: true })
  for (const name of await readdir(dir)) {
    if (name.endsWith(ext)) await rm(path.join(dir, name))
  }
}

async function main(): Promise<void> {
  const ids = CASES.map((c) => c.id)
  if (new Set(ids).size !== ids.length) throw new Error('case id が重複しています')
  const sorted = [...CASES].sort((a, b) => a.id.localeCompare(b.id))

  // 先に全ケースの期待値を検証（描画前に失敗させる）
  const outCases: OutCase[] = sorted.map((c) => ({
    id: c.id,
    images: c.screens.map((_, i) => `images/${c.id}-${i + 1}.jpg`),
    meal_type: c.meal_type,
    content: c.content,
    expected: deriveExpected(c),
    tags: deriveTags(c),
  }))

  await emptyDir(IMG_DIR, '.jpg')
  if (KEEP_RAW) await emptyDir(RAW_DIR, '.png')

  const browser = await chromium.launch({ executablePath: CHROMIUM_PATH })
  const sizes = new Map<string, number>()
  let totalBytes = 0
  try {
    const context = await browser.newContext({
      viewport: VIEWPORT,
      deviceScaleFactor: DEVICE_SCALE,
      locale: 'ja-JP',
      timezoneId: 'Asia/Tokyo',
    })
    const page = await context.newPage()
    for (const c of sorted) {
      for (let i = 0; i < c.screens.length; i++) {
        const name = `${c.id}-${i + 1}`
        await page.setContent(renderScreen(c.screens[i]), { waitUntil: 'load' })
        await page.evaluate('document.fonts.ready.then(() => true)')
        const check = (await page.evaluate(PAGE_CHECK)) as { bad: string[]; mainFill: string }
        if (check.bad.length > 0) throw new Error(`[${name}] レイアウト不正:\n  ${check.bad.join('\n  ')}`)
        const png = await page.screenshot({ type: 'png', animations: 'disabled', caret: 'hide' })
        const meta = await sharp(png).metadata()
        if (meta.width !== VIEWPORT.width * DEVICE_SCALE || meta.height !== VIEWPORT.height * DEVICE_SCALE) {
          throw new Error(`[${name}] 撮影サイズが想定外: ${meta.width}x${meta.height}`)
        }
        if (KEEP_RAW) await writeFile(path.join(RAW_DIR, `${name}.png`), png)
        // StorageService.pickImage と同じ: 1920x1080 に収まるよう縮小（拡大なし）→ JPEG q80
        const { data: jpg, info } = await sharp(png)
          .resize({ width: UPLOAD.maxWidth, height: UPLOAD.maxHeight, fit: 'inside', withoutEnlargement: true })
          .jpeg({ quality: UPLOAD.quality })
          .toBuffer({ resolveWithObject: true })
        await writeFile(path.join(IMG_DIR, `${name}.jpg`), jpg)
        sizes.set(`${info.width}x${info.height}`, (sizes.get(`${info.width}x${info.height}`) ?? 0) + 1)
        totalBytes += jpg.length
        console.log(`  ${name}.jpg  ${info.width}x${info.height}  ${(jpg.length / 1024).toFixed(1)} KB  (main ${check.mainFill})`)
      }
    }
  } finally {
    await browser.close()
  }

  const file: DatasetFile = {
    dataset: 'screenshots-synthetic-v1',
    input_kind: 'screenshot',
    description:
      'Synthetic screenshots of fictional meal-tracking apps (ごはんログ / ミールノート / MealDiary) with exactly-known on-screen nutrition values, ' +
      'plus non-meal hard negatives. Covers single meals (light/dark, dense, one-decimal grams), day views (totals = day total, alt = largest meal), ' +
      'consistent two-image pairs (list+kcal / PFC chart), mismatched pairs (expect_warning=true) and non-meal apps (is_meal=false). ' +
      'Ground truth = on-screen totals truncated to integers, as SCREENSHOT_SYSTEM_PROMPT instructs.',
    source: 'Synthetic screenshots rendered by generators/screenshots (fictional apps; HTML rendered with headless Chromium)',
    preprocessing:
      'iPhone 390x844pt @3x = 1170x2532 PNG -> fit inside 1920x1080, no enlargement (=> 499x1080), JPEG q80 (same as StorageService.pickImage: maxWidth 1920, maxHeight 1080, imageQuality 80)',
    cases: outCases,
  }
  await mkdir(OUT_DIR, { recursive: true })
  await writeFile(path.join(OUT_DIR, 'cases.json'), JSON.stringify(file, null, 2) + '\n')

  const tagCount = new Map<string, number>()
  for (const c of outCases) for (const t of c.tags) tagCount.set(t, (tagCount.get(t) ?? 0) + 1)
  console.log(`\n${outCases.length} cases, ${[...sizes.values()].reduce((a, b) => a + b, 0)} images (${[...sizes.entries()].map(([k, v]) => `${k} x${v}`).join(', ')}), ${(totalBytes / 1024).toFixed(0)} KB`)
  console.log('tags: ' + [...tagCount.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([k, v]) => `${k}=${v}`).join(' '))
  console.log(`-> ${path.relative(EVAL_ROOT, path.join(OUT_DIR, 'cases.json'))}`)
}

main().catch((e: unknown) => {
  console.error(e instanceof Error ? e.message : e)
  process.exit(1)
})
