// App — composes the design canvas with wireframes + hi-fi sections.

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "split",
  "chart": "bar",
  "cardState": "healthkit"
}/*EDITMODE-END*/;
window.TWEAK_DEFAULTS = TWEAK_DEFAULTS;

// Pair of phone frames (light + dark) for split theme view
const PhonePair = ({ label, children, height = 760 }) => {
  const [tw] = React.useState(() => {
    try { return JSON.parse(localStorage.getItem('sleep_tweaks')) || TWEAK_DEFAULTS; }
    catch (e) { return TWEAK_DEFAULTS; }
  });
  // Observe tweaks via custom event if needed — simpler: re-read on render from localStorage
  // but since App re-renders on tweak change, this is fine.
  return null;
};

// Helper: render phone(s) per theme setting
const ThemedPhones = ({ render, theme }) => {
  if (theme === 'split') {
    return (
      <div style={{ display: 'flex', gap: 24 }}>
        <PhoneFrame label="LIGHT" dark={false}>{render(false)}</PhoneFrame>
        <PhoneFrame label="DARK"  dark={true}>{render(true)}</PhoneFrame>
      </div>
    );
  }
  return <PhoneFrame label={theme === 'dark' ? 'DARK' : 'LIGHT'} dark={theme === 'dark'}>{render(theme === 'dark')}</PhoneFrame>;
};

// Standalone summary card on a neutral canvas (per brief: card in isolation, no home screen)
const CardStage = ({ dark, state }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      height: '100%', background: c.background,
      display: 'flex', flexDirection: 'column',
    }}>
      <div style={{
        padding: '60px 16px 0', fontSize: 12, fontWeight: 500,
        color: c.textHint, letterSpacing: 0.3, textTransform: 'uppercase',
      }}>ホーム画面ウィジェット</div>
      <div style={{ padding: '12px 16px' }}>
        <SummaryCard state={state} dark={dark}/>
      </div>
    </div>
  );
};

const App = () => {
  const [tweaks, updateTweaks, showTweaks] = useTweaks();
  const theme = tweaks.theme;
  const chart = tweaks.chart;
  const cardState = tweaks.cardState;

  return (
    <>
      <DesignCanvas>
        {/* ─── HEADER ───────────────────────────────────────── */}
        <div style={{ padding: '0 60px 48px', maxWidth: 1100 }}>
          <div style={{
            fontFamily: T.mono, fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase',
            color: 'rgba(60,50,40,0.55)', marginBottom: 12,
          }}>FIT-CONNECT Mobile · Feature Spec · 2026-04-19</div>
          <h1 style={{
            fontSize: 44, fontWeight: 700, color: '#1f1b16', margin: 0,
            letterSpacing: -1.2, lineHeight: 1.1,
          }}>睡眠データ連携</h1>
          <div style={{
            fontSize: 15, color: 'rgba(60,50,40,0.7)', maxWidth: 680,
            marginTop: 12, lineHeight: 1.65,
          }}>
            HealthKit / Health Connect による自動計測と、起床後の手動入力を組み合わせた睡眠記録機能。
            ワイヤーフレーム（低忠実度）→ ハイファイモックアップ → ダイアログ・設定 → チャート比較の順に並べています。
            右下の Tweaks でテーマ・チャート形式・カード状態を切り替えられます。
          </div>

          {/* assumptions strip */}
          <div style={{
            marginTop: 28, padding: '16px 20px', borderRadius: 8,
            border: '1px solid rgba(0,0,0,0.08)', background: 'rgba(255,255,255,0.6)',
            display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 20,
          }}>
            {[
              ['プラットフォーム', 'iOS / Android (Flutter)'],
              ['タイポ',          'Noto Sans JP'],
              ['カード角丸',       '8px (max)'],
              ['ステージ配色',     'Indigo 700→400 / Blue 400 / Slate 200'],
            ].map(([k,v]) => (
              <div key={k}>
                <div style={{ fontFamily: T.mono, fontSize: 10, color: 'rgba(60,50,40,0.55)', letterSpacing: 0.6, textTransform: 'uppercase' }}>{k}</div>
                <div style={{ fontSize: 13, color: '#1f1b16', fontWeight: 500, marginTop: 4 }}>{v}</div>
              </div>
            ))}
          </div>
        </div>

        {/* ─── SECTION 1: WIREFRAMES ────────────────────────── */}
        <DCSection
          title="01  Wireframes — Low-fi"
          subtitle="構造と情報階層の確認。グレースケール、ダッシュドボーダーで仮置き要素を表現。"
          gap={48}
        >
          <div>
            <WFLabel style={{ marginBottom: 8 }}>C1  SleepSummaryCard（3状態）</WFLabel>
            <WF_SummaryCards/>
          </div>
          <WF_SleepScreen/>
          <WF_Dialog/>
          <WF_Settings/>
          <DCPostIt top={-20} left={-30} rotate={-4} width={190}>
            ワイヤーフレーム段階で「評価アイコンの位置」「ソース表示」を決めておく。Lucide か絵文字かは hi-fi で検証。
          </DCPostIt>
        </DCSection>

        {/* ─── SECTION 2: HI-FI SUMMARY CARD ────────────────── */}
        <DCSection
          title="02  C1  SleepSummaryCard — Hi-fi"
          subtitle="ホーム画面に配置されるウィジェット。3状態を並列で検証。"
          gap={48}
        >
          {[
            { state: 'healthkit', label: '4-1-a  HealthKit連携（時間+評価）' },
            { state: 'manual',    label: '4-1-b  手動 / 評価のみ' },
            { state: 'empty',     label: '4-1-c  未記録（CTA）' },
          ].map(v => (
            <div key={v.state}>
              <WFLabel style={{ marginBottom: 10 }}>{v.label}</WFLabel>
              <div style={{ display: 'flex', gap: 16 }}>
                <div style={{
                  width: 358, padding: '40px 16px', borderRadius: 12,
                  background: TOKENS.light.background,
                  border: '1px solid rgba(0,0,0,0.05)',
                }}>
                  <SummaryCard state={v.state} dark={false}/>
                </div>
                <div style={{
                  width: 358, padding: '40px 16px', borderRadius: 12,
                  background: TOKENS.dark.background,
                  border: '1px solid rgba(0,0,0,0.2)',
                }}>
                  <SummaryCard state={v.state} dark={true}/>
                </div>
              </div>
            </div>
          ))}
        </DCSection>

        {/* ─── SECTION 3: SLEEP RECORD SCREEN ──────────────── */}
        <DCSection
          title="03  S1  SleepRecordScreen"
          subtitle="独立画面。上から：昨夜のサマリー / 直近7日 / 履歴。"
          gap={40}
        >
          <ThemedPhones theme={theme} render={dark =>
            <SleepScreen dark={dark} chartVariant={chart} state="healthkit"/>
          }/>
          <div>
            <WFLabel style={{ marginBottom: 10 }}>手動のみ（HealthKit未使用）</WFLabel>
            <ThemedPhones theme={theme} render={dark =>
              <SleepScreen dark={dark} chartVariant={chart} state="manual"/>
            }/>
          </div>
          <DCPostIt top={-30} right={60} rotate={3} width={200}>
            fl_chart の LineChart を想定。欠損日（4/15）は線を途切れさせ、点線でギャップを示唆。
          </DCPostIt>
        </DCSection>

        {/* ─── SECTION 4: EMPTY / EDGE STATES ──────────────── */}
        <DCSection
          title="04  エッジケース"
          subtitle="未記録 / 同期中 / 権限拒否 / 履歴空。"
          gap={40}
        >
          <div>
            <WFLabel style={{ marginBottom: 10 }}>当日データ無し（サマリーのみ差し替え）</WFLabel>
            <ThemedPhones theme={theme} render={dark =>
              <SleepScreen dark={dark} chartVariant={chart} state="empty"/>
            }/>
          </div>
          <div>
            <WFLabel style={{ marginBottom: 10 }}>履歴が空</WFLabel>
            <ThemedPhones theme={theme} render={dark => <SleepScreenEmpty dark={dark}/>}/>
          </div>
          <div>
            <WFLabel style={{ marginBottom: 10 }}>HealthKit同期中（スケルトン）</WFLabel>
            <ThemedPhones theme={theme} render={dark => <SleepScreenLoading dark={dark}/>}/>
          </div>
          <div>
            <WFLabel style={{ marginBottom: 10 }}>権限拒否</WFLabel>
            <ThemedPhones theme={theme} render={dark => <PermissionScreen dark={dark}/>}/>
          </div>
        </DCSection>

        {/* ─── SECTION 5: DIALOG + SETTINGS ────────────────── */}
        <DCSection
          title="05  D1 MorningWakeupDialog ／ C2 HealthSettingsScreen"
          subtitle="起動時ダイアログ、設定画面の拡張部分。"
          gap={40}
        >
          <div>
            <WFLabel style={{ marginBottom: 10 }}>D1  未選択</WFLabel>
            <ThemedPhones theme={theme} render={dark => <DialogScreen dark={dark}/>}/>
          </div>
          <div>
            <WFLabel style={{ marginBottom: 10 }}>D1  「すっきり」選択中</WFLabel>
            <ThemedPhones theme={theme} render={dark => <DialogScreen dark={dark} selected="smile"/>}/>
          </div>
          <div>
            <WFLabel style={{ marginBottom: 10 }}>C2  設定拡張</WFLabel>
            <ThemedPhones theme={theme} render={dark => <SettingsScreen dark={dark}/>}/>
          </div>
          <DCPostIt top={-20} right={-30} rotate={3} width={190}>
            ダイアログは画面中央配置・背面をブラー。「今日は聞かない」は視覚的に弱める（secondary）。
          </DCPostIt>
        </DCSection>

        {/* ─── SECTION 6: CHART A/B ────────────────────────── */}
        <DCSection
          title="06  W2  SleepStageChart — 案A vs 案B"
          subtitle="ステージ可視化の比較。Tweaks で切り替え可能。"
          gap={40}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            <WFLabel>案A  水平スタックバー（情報密度高・省スペース）</WFLabel>
            <div style={{ display: 'flex', gap: 24 }}>
              <div style={{ width: 358 }}>
                <Card dark={false}><StageBarChart dark={false}/></Card>
              </div>
              <div style={{ width: 358 }}>
                <Card dark={true}><StageBarChart dark={true}/></Card>
              </div>
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            <WFLabel>案B  ドーナツチャート（視覚的インパクト大）</WFLabel>
            <div style={{ display: 'flex', gap: 24 }}>
              <div style={{ width: 358 }}>
                <Card dark={false}><StagePieChart dark={false}/></Card>
              </div>
              <div style={{ width: 358 }}>
                <Card dark={true}><StagePieChart dark={true}/></Card>
              </div>
            </div>
          </div>
          <DCPostIt top={-30} right={-20} rotate={-3} width={200}>
            <strong>推奨：案A</strong><br/>
            情報密度が高く、体重画面のカード構造と統一感が取れる。案Bはウィジェット単体で使うなら映える。
          </DCPostIt>
        </DCSection>

        {/* ─── SECTION 7: FLOW ─────────────────────────────── */}
        <DCSection
          title="07  画面遷移フロー"
          subtitle="主要な3つのエントリポイント。"
        >
          <div style={{
            width: 1100, padding: 32, background: '#fff',
            border: '1px solid rgba(0,0,0,0.08)', borderRadius: 8,
            fontFamily: T.font, fontSize: 13, color: '#1E293B', lineHeight: 1.8,
          }}>
            <pre style={{ margin: 0, fontFamily: T.mono, fontSize: 12, color: '#334155', whiteSpace: 'pre-wrap' }}>
{`[ホーム画面]
  └ SleepSummaryCard タップ
      → [SleepRecordScreen]
          ├ 履歴アイテム タップ → [SleepDetailSheet]（将来実装）
          └ AppBar同期 → HealthKit同期 → スナックバー通知

  └ SleepSummaryCard（未記録時）のCTA タップ
      → [WakeupRatingSelector]（ボトムシート）
          → 選択 → 保存 → スナックバー「記録しました」

[アプリ起動時 · 4:00-12:00 · 当日未記録]
  → [MorningWakeupDialog]
      ├ 評価選択 → 保存 → 閉 → スナックバー
      ├ あとで → 閉（リトライ可）
      └ 今日は聞かない → 閉（当日抑止）`}
            </pre>
          </div>
        </DCSection>

        {/* footer spacer */}
        <div style={{ height: 80 }}/>
      </DesignCanvas>

      {showTweaks && <TweaksPanel state={tweaks} update={updateTweaks}/>}
    </>
  );
};

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
