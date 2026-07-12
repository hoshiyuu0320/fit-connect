import { ImageResponse } from 'next/og';

export const runtime = 'edge';

export const alt = 'FIT-CONNECT | パーソナルトレーナーのための顧客管理ツール';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

const HEADLINE_JA = 'パーソナルトレーナーのための顧客管理ツール';
// フォント取得に失敗した場合のフォールバック（デフォルトフォントは日本語グリフ非対応のため）
const HEADLINE_EN = 'Client Management Tool for Personal Trainers';
const LOGO_MARK = 'FC';
const LOGO_TEXT = 'FitConnect';

/**
 * Google Fonts から Noto Sans JP を使用グリフのみサブセット取得する。
 * UA なしの fetch では TrueType が返るため satori（next/og）でそのまま利用できる。
 * 失敗しても throw せず null を返し、ビルドを壊さない。
 */
async function loadNotoSansJP(text: string): Promise<ArrayBuffer | null> {
  try {
    const cssRes = await fetch(
      `https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@700&text=${encodeURIComponent(text)}`
    );
    if (!cssRes.ok) return null;
    const css = await cssRes.text();
    const resource = css.match(/src: url\((.+?)\) format\('(?:opentype|truetype)'\)/);
    if (!resource) return null;
    const fontRes = await fetch(resource[1]);
    if (!fontRes.ok) return null;
    return await fontRes.arrayBuffer();
  } catch {
    return null;
  }
}

export default async function OpengraphImage() {
  // fonts オプション指定時はデフォルトフォントが使われないため、描画する全文字をサブセットに含める
  const fontData = await loadNotoSansJP(HEADLINE_JA + LOGO_MARK + LOGO_TEXT);
  const headline = fontData ? HEADLINE_JA : HEADLINE_EN;

  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          backgroundColor: '#0F172A',
          padding: '72px 80px',
          fontFamily: fontData ? '"Noto Sans JP"' : undefined,
        }}
      >
        {/* 左上: ロゴ */}
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div
            style={{
              width: 72,
              height: 72,
              backgroundColor: '#14B8A6',
              borderRadius: 14,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#0F172A',
              fontSize: 30,
              fontWeight: 700,
            }}
          >
            {LOGO_MARK}
          </div>
          <div
            style={{
              marginLeft: 24,
              color: '#FFFFFF',
              fontSize: 44,
              fontWeight: 700,
              letterSpacing: '-0.02em',
            }}
          >
            {LOGO_TEXT}
          </div>
        </div>

        {/* 中央: キャッチコピー */}
        <div
          style={{
            display: 'flex',
            color: '#FFFFFF',
            fontSize: 60,
            fontWeight: 700,
            lineHeight: 1.4,
            letterSpacing: '-0.01em',
            maxWidth: 1000,
          }}
        >
          {headline}
        </div>

        {/* 下部: teal アクセントライン */}
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div
            style={{
              width: 180,
              height: 10,
              backgroundColor: '#14B8A6',
              borderRadius: 5,
            }}
          />
        </div>
      </div>
    ),
    {
      ...size,
      ...(fontData
        ? {
            fonts: [
              {
                name: 'Noto Sans JP',
                data: fontData,
                weight: 700 as const,
                style: 'normal' as const,
              },
            ],
          }
        : {}),
    }
  );
}
