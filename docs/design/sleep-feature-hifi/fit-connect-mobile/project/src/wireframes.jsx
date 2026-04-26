// Low-fi wireframes — grayscale, structural. Uses rectangles and lines to lay out
// the information hierarchy before the hi-fi pass.

const WF = {
  bg:     '#FFFFFF',
  line:   '#CBD5E1',
  fill:   '#E2E8F0',
  strong: '#94A3B8',
  text:   '#475569',
  label:  '#64748B',
  mono:   window.T.mono,
};

const wfLine = (w = '100%', h = 8, color = WF.fill) => (
  <div style={{ width: w, height: h, background: color, borderRadius: 2 }}/>
);

const wfBox = (style = {}) => (
  <div style={{
    border: `1.5px dashed ${WF.line}`, background: 'transparent',
    borderRadius: 4, ...style,
  }}/>
);

const WFLabel = ({ children, style }) => (
  <div style={{
    fontFamily: WF.mono, fontSize: 10, letterSpacing: 0.4,
    color: WF.label, textTransform: 'uppercase', ...style,
  }}>{children}</div>
);

const WFFrame = ({ children, label, w = 320, h = 640 }) => (
  <div style={{ flexShrink: 0 }}>
    {label && <WFLabel style={{ marginBottom: 8 }}>{label}</WFLabel>}
    <div style={{
      width: w, height: h, background: WF.bg,
      border: `1.5px solid ${WF.strong}`, borderRadius: 24,
      padding: '24px 16px 20px', position: 'relative',
      fontFamily: WF.mono, color: WF.text,
      overflow: 'hidden',
    }}>{children}</div>
  </div>
);

// ─── C1 SleepSummaryCard (3 states) ───────────────────────────
const WF_SummaryCards = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 20, width: 320 }}>
    {[
      { tag: '4-1-a  HealthKit連携', body: (
        <>
          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <div style={{ width: 14, height: 14, borderRadius: '50%', background: WF.fill }}/>
              <div style={{ fontSize: 10 }}>昨夜の睡眠</div>
            </div>
            <div style={{ width: 12, height: 12, background: WF.fill, borderRadius: 2 }}/>
          </div>
          <div style={{ marginTop: 14, display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <div style={{ fontSize: 20, fontWeight: 700, color: '#0F172A' }}>7h23m</div>
            <div style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
              <div style={{ width: 14, height: 14, borderRadius: '50%', background: WF.fill }}/>
              <div style={{ fontSize: 11 }}>すっきり</div>
            </div>
          </div>
          <div style={{ marginTop: 6, fontSize: 10, color: WF.label }}>23:45 → 7:08</div>
        </>
      )},
      { tag: '4-1-b  手動 / 評価のみ', body: (
        <>
          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <div style={{ width: 14, height: 14, borderRadius: '50%', background: WF.fill }}/>
              <div style={{ fontSize: 10 }}>昨夜の睡眠</div>
            </div>
            <div style={{ width: 12, height: 12, background: WF.fill, borderRadius: 2 }}/>
          </div>
          <div style={{ marginTop: 12, display: 'flex', gap: 6, alignItems: 'center' }}>
            <div style={{ width: 18, height: 18, borderRadius: '50%', background: WF.fill }}/>
            <div style={{ fontSize: 14, fontWeight: 600 }}>すっきり</div>
          </div>
          <div style={{ marginTop: 8, fontSize: 10, color: WF.label }}>タップして詳細を記録</div>
        </>
      )},
      { tag: '4-1-c  未記録（CTA）', body: (
        <>
          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <div style={{ width: 14, height: 14, borderRadius: '50%', background: WF.fill }}/>
            <div style={{ fontSize: 10 }}>昨夜の睡眠</div>
          </div>
          <div style={{
            marginTop: 14, height: 40, borderRadius: 6,
            border: `1.5px dashed ${WF.strong}`, background: '#F8FAFC',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 11, fontWeight: 500, gap: 6,
          }}>
            目覚めを記録する
            <span style={{ fontSize: 12 }}>→</span>
          </div>
        </>
      )},
    ].map((s, i) => (
      <div key={i}>
        <WFLabel style={{ marginBottom: 6 }}>{s.tag}</WFLabel>
        <div style={{ border: `1.5px solid ${WF.strong}`, borderRadius: 8, padding: 14, minHeight: 96 }}>
          {s.body}
        </div>
      </div>
    ))}
  </div>
);

// ─── S1 SleepRecordScreen ────────────────────────────────────
const WF_SleepScreen = () => (
  <WFFrame label="S1  SleepRecordScreen" w={320} h={640}>
    {/* AppBar */}
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
      <div style={{ fontSize: 11 }}>‹  睡眠記録</div>
      <div style={{ width: 14, height: 14, borderRadius: '50%', background: WF.fill }}/>
    </div>

    {/* Summary */}
    <div style={{ border: `1.5px solid ${WF.strong}`, borderRadius: 8, padding: 12, marginBottom: 14 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10 }}>
        <span>🌙 昨夜の睡眠</span><span style={{ color: WF.label }}>🫀 HealthKit</span>
      </div>
      <div style={{ fontSize: 24, fontWeight: 700, color: '#0F172A', marginTop: 6 }}>7h23m</div>
      <div style={{ display: 'flex', gap: 16, fontSize: 10, color: WF.label, marginTop: 4 }}>
        <span>就寝 23:45</span><span>起床 7:08</span>
      </div>
      <div style={{ marginTop: 10, height: 12, display: 'flex', borderRadius: 2, overflow: 'hidden' }}>
        <div style={{ flex: 25, background: '#64748B' }}/>
        <div style={{ flex: 50, background: '#94A3B8' }}/>
        <div style={{ flex: 20, background: '#CBD5E1' }}/>
        <div style={{ flex: 5, background: '#E2E8F0' }}/>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 4, marginTop: 8, fontSize: 9 }}>
        <span>■ 深 25%</span><span>■ 浅 50%</span>
        <span>■ REM 20%</span><span>■ 覚 5%</span>
      </div>
      <div style={{
        marginTop: 10, paddingTop: 8, borderTop: `1px dashed ${WF.line}`,
        display: 'flex', justifyContent: 'space-between', fontSize: 10,
      }}>
        <span>目覚め：😊 すっきり</span><span style={{ color: '#2563EB' }}>編集</span>
      </div>
    </div>

    {/* Week */}
    <div style={{ fontSize: 10, fontWeight: 600, marginBottom: 6 }}>直近7日間</div>
    <div style={{
      border: `1.5px solid ${WF.strong}`, borderRadius: 8, padding: 10,
      marginBottom: 14, height: 100, position: 'relative',
    }}>
      <svg width="100%" height="100%" viewBox="0 0 280 70" preserveAspectRatio="none">
        <polyline points="10,25 50,40 90,10 130,10 170,18 210,48 250,30"
                  fill="none" stroke={WF.strong} strokeWidth="1.5" strokeDasharray="0"/>
        <line x1="120" y1="10" x2="135" y2="10" stroke={WF.line} strokeWidth="1.5" strokeDasharray="3 2"/>
        {[10,50,90,130,170,210,250].map((x,i)=>(
          <circle key={i} cx={x} cy={[25,40,10,10,18,48,30][i]} r="3" fill="#fff" stroke={WF.strong} strokeWidth="1.5"/>
        ))}
      </svg>
    </div>

    {/* History */}
    <div style={{ fontSize: 10, fontWeight: 600, marginBottom: 6 }}>履歴</div>
    {[0,1,2].map(i => (
      <div key={i} style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        padding: '8px 4px', borderBottom: `1px solid ${WF.line}`, fontSize: 10,
      }}>
        <span>4/{18-i}</span>
        <span style={{ color: '#0F172A', fontWeight: 700 }}>{[7,6,8][i]}h{[23,30,0][i]}m</span>
        <span>😊 🫀 ›</span>
      </div>
    ))}
  </WFFrame>
);

// ─── D1 MorningWakeupDialog ──────────────────────────────────
const WF_Dialog = () => (
  <WFFrame label="D1  MorningWakeupDialog" w={320} h={560}>
    <div style={{
      position: 'absolute', inset: 0, background: 'rgba(15,23,42,0.12)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <div style={{
        width: 264, background: '#fff', borderRadius: 8,
        border: `1.5px solid ${WF.strong}`, padding: 20,
      }}>
        <div style={{ textAlign: 'center', fontSize: 16, fontWeight: 600 }}>☀️ おはようございます</div>
        <div style={{ textAlign: 'center', fontSize: 11, color: WF.label, marginTop: 6 }}>今朝の目覚めは？</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 16 }}>
          {[['😊','すっきり'],['😐','まあまあ'],['😫','だるい']].map(([e,l])=>(
            <div key={l} style={{
              height: 44, border: `1.5px solid ${WF.line}`, borderRadius: 6,
              display: 'flex', alignItems: 'center', padding: '0 16px', gap: 12, fontSize: 12,
            }}>
              <span style={{ fontSize: 16 }}>{e}</span>
              <span>{l}</span>
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 16, fontSize: 11 }}>
          <span style={{ color: '#2563EB' }}>あとで</span>
          <span style={{ color: WF.label }}>今日は聞かない</span>
        </div>
      </div>
    </div>
  </WFFrame>
);

// ─── C2 HealthSettingsScreen ─────────────────────────────────
const WF_Settings = () => (
  <WFFrame label="C2  HealthSettingsScreen 拡張" w={320} h={560}>
    <div style={{ fontSize: 11 }}>‹  ヘルスケア連携</div>
    <div style={{ marginTop: 16 }}>
      <WFLabel style={{ marginBottom: 8 }}>既存</WFLabel>
      <div style={{ border: `1.5px solid ${WF.line}`, borderRadius: 8, padding: 12, marginBottom: 12 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <div style={{ fontSize: 12, fontWeight: 600, color: '#0F172A' }}>体重データ</div>
            <div style={{ fontSize: 10, color: WF.label, marginTop: 3 }}>HealthKitから体重を取得します</div>
          </div>
          <div style={{ width: 40, height: 24, background: WF.fill, borderRadius: 12 }}/>
        </div>
      </div>
      <WFLabel style={{ marginBottom: 8 }}>新規追加</WFLabel>
      {[
        ['睡眠データ','HealthKitから睡眠データを取得します'],
        ['朝の目覚めダイアログ','起床後(4:00-12:00)にアプリを開いた時、目覚めの記録を促します'],
      ].map(([t,s])=>(
        <div key={t} style={{ border: `1.5px solid ${WF.strong}`, borderRadius: 8, padding: 12, marginBottom: 10 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }}>
            <div>
              <div style={{ fontSize: 12, fontWeight: 600, color: '#0F172A' }}>{t}</div>
              <div style={{ fontSize: 10, color: WF.label, marginTop: 3, lineHeight: 1.4 }}>{s}</div>
            </div>
            <div style={{ width: 40, height: 24, background: WF.fill, borderRadius: 12 }}/>
          </div>
        </div>
      ))}
    </div>
  </WFFrame>
);

Object.assign(window, { WF_SummaryCards, WF_SleepScreen, WF_Dialog, WF_Settings, WFFrame, WFLabel });
