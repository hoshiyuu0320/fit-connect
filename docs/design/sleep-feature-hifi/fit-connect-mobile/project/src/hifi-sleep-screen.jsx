// Hi-fi SleepRecordScreen — S1, full screen with summary / week / history sections.

const SleepScreen = ({ dark = false, chartVariant = 'bar', state = 'healthkit' }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  const { h, m } = window.SAMPLE.duration;
  const history = [
    { date: '4/18', dow: '土', h: 7,  m: 23, rating: 'smile', src: 'hk' },
    { date: '4/17', dow: '金', h: 6,  m: 0,  rating: 'frown', src: 'hk' },
    { date: '4/16', dow: '木', h: 7,  m: 48, rating: 'smile', src: 'hk' },
    { date: '4/15', dow: '水', h: null, m: null, rating: 'meh', src: 'manual' },
    { date: '4/14', dow: '火', h: 8,  m: 0,  rating: 'smile', src: 'hk' },
    { date: '4/13', dow: '月', h: 6,  m: 30, rating: null,    src: 'hk' },
    { date: '4/12', dow: '日', h: 7,  m: 12, rating: 'smile', src: 'hk' },
  ];

  return (
    <div style={{ height: '100%', background: c.background, display: 'flex', flexDirection: 'column' }}>
      <NavBar
        dark={dark} title="睡眠記録"
        trailing={<button style={{
          background: 'transparent', border: 'none', padding: 8, cursor: 'pointer',
        }}><RefreshIcon size={18} color={c.textSecondary} stroke={2}/></button>}
      />
      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 16px 80px' }}>
        {/* Summary */}
        {state === 'empty' ? (
          <Card dark={dark} style={{ marginBottom: window.T.pad.section }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{
                width: 32, height: 32, borderRadius: 6, background: c.indigo50,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}><MoonIcon size={17} color={c.indigo600}/></div>
              <span style={{ fontSize: 14, fontWeight: 600, color: c.textPrimary }}>今日の記録はまだありません</span>
            </div>
            <button style={{
              marginTop: 14, width: '100%', height: 44,
              background: c.primary, color: '#fff', border: 'none',
              borderRadius: 6, fontFamily: window.T.font, fontSize: 14, fontWeight: 600,
              letterSpacing: 0.02, cursor: 'pointer',
            }}>目覚めを記録する</button>
          </Card>
        ) : (
          <Card dark={dark} style={{ marginBottom: window.T.pad.section }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <MoonIcon size={15} color={c.indigo600}/>
                <span style={{ fontSize: 12, fontWeight: 500, color: c.textSecondary }}>昨夜の睡眠</span>
              </div>
              <Chip dark={dark}
                bg={c.primary50} color={c.primary}
                style={{ padding: '3px 8px', borderRadius: 6 }}>
                <HeartPulseIcon size={11} color={c.primary}/>
                <span style={{ fontSize: 11, fontWeight: 600 }}>HealthKit</span>
              </Chip>
            </div>

            {state === 'healthkit' && (
              <>
                <div style={{
                  marginTop: 10,
                  fontSize: 32, fontWeight: 700, color: c.textPrimary,
                  letterSpacing: '-0.02em', lineHeight: 1.1, fontFeatureSettings: '"tnum"',
                }}>
                  {h}<span style={{ fontSize: 18, fontWeight: 600, color: c.textSecondary, margin: '0 2px' }}>時間</span>
                  {m}<span style={{ fontSize: 18, fontWeight: 600, color: c.textSecondary, marginLeft: 2 }}>分</span>
                </div>
                <div style={{
                  display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8,
                  marginTop: 12, padding: '10px 12px', borderRadius: 6,
                  background: c.slate100,
                }}>
                  <div>
                    <div style={{ fontSize: 11, color: c.textSecondary, fontWeight: 500 }}>就寝</div>
                    <div style={{ fontSize: 16, fontWeight: 700, color: c.textPrimary, fontFeatureSettings: '"tnum"', letterSpacing: '-0.01em' }}>{window.SAMPLE.bedtime}</div>
                  </div>
                  <div>
                    <div style={{ fontSize: 11, color: c.textSecondary, fontWeight: 500 }}>起床</div>
                    <div style={{ fontSize: 16, fontWeight: 700, color: c.textPrimary, fontFeatureSettings: '"tnum"', letterSpacing: '-0.01em' }}>{window.SAMPLE.wakeup}</div>
                  </div>
                </div>
                <div style={{
                  marginTop: 16, paddingTop: 14,
                  borderTop: `1px solid ${c.slate100}`,
                }}>
                  {chartVariant === 'bar'
                    ? <StageBarChart dark={dark}/>
                    : <StagePieChart dark={dark}/>}
                </div>
              </>
            )}
            {state === 'manual' && (
              <>
                <div style={{ marginTop: 14, display: 'flex', gap: 12, alignItems: 'center' }}>
                  <RatingIcon rating={window.SAMPLE.rating} size={32}/>
                  <span style={{ fontSize: 22, fontWeight: 700, color: ratingColor('smile', dark ? 'dark' : 'light'), letterSpacing: '-0.01em' }}>
                    すっきり
                  </span>
                </div>
                <div style={{
                  marginTop: 16, padding: '10px 12px', borderRadius: 6,
                  background: c.slate100, display: 'flex', alignItems: 'flex-start', gap: 8,
                }}>
                  <InfoIcon size={14} color={c.textSecondary} style={{ marginTop: 2 }}/>
                  <div style={{ fontSize: 11, color: c.textSecondary, lineHeight: 1.5 }}>
                    詳細データを取得するにはヘルスケア連携を有効にしてください
                  </div>
                </div>
              </>
            )}
            <div style={{
              marginTop: 14, paddingTop: 12, borderTop: `1px solid ${c.slate100}`,
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            }}>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <span style={{ fontSize: 12, color: c.textSecondary, fontWeight: 500 }}>目覚め</span>
                <RatingIcon rating="smile" size={16}/>
                <span style={{ fontSize: 13, fontWeight: 600, color: ratingColor('smile', dark ? 'dark' : 'light') }}>すっきり</span>
              </div>
              <button style={{
                background: 'transparent', border: 'none', padding: '4px 8px', cursor: 'pointer',
                fontSize: 13, fontWeight: 600, color: c.primary, fontFamily: window.T.font,
                display: 'flex', alignItems: 'center', gap: 4,
              }}>
                <PencilIcon size={13} color={c.primary}/>
                編集
              </button>
            </div>
          </Card>
        )}

        {/* Week */}
        <SectionTitle dark={dark}>直近7日間</SectionTitle>
        <Card dark={dark} style={{ padding: '16px 8px 12px', marginBottom: window.T.pad.section }}>
          <WeekChart dark={dark}/>
        </Card>

        {/* History */}
        <SectionTitle dark={dark} right={
          <span style={{ fontSize: 12, color: c.textHint, fontWeight: 500 }}>{history.length}件</span>
        }>履歴</SectionTitle>
        <Card dark={dark} noPad>
          {history.map((r, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '0 16px', minHeight: 56,
              borderBottom: i < history.length - 1 ? `1px solid ${c.slate100}` : 'none',
            }}>
              <div style={{ width: 54 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: c.textPrimary, letterSpacing: '-0.01em', fontFeatureSettings: '"tnum"' }}>{r.date}</div>
                <div style={{ fontSize: 10, color: c.textHint, fontWeight: 500 }}>({r.dow})</div>
              </div>
              <div style={{ flex: 1, fontSize: 16, fontWeight: 700, color: r.h ? c.textPrimary : c.textHint, letterSpacing: '-0.01em', fontFeatureSettings: '"tnum"' }}>
                {r.h != null ? `${r.h}時間${r.m}分` : '--'}
              </div>
              <div style={{ width: 22, display: 'flex', justifyContent: 'center' }}>
                {r.rating
                  ? <RatingIcon rating={r.rating} size={18}/>
                  : <div style={{ width: 18, height: 18, borderRadius: '50%', border: `1.5px dashed ${c.slate200}` }}/>}
              </div>
              <div style={{ width: 14, display: 'flex', justifyContent: 'center' }}>
                {r.src === 'hk'
                  ? <HeartPulseIcon size={12} color={c.textHint}/>
                  : <PenLineIcon    size={12} color={c.textHint}/>}
              </div>
              <ChevronRightIcon size={14} color={c.slate400}/>
            </div>
          ))}
        </Card>
      </div>
    </div>
  );
};

// History empty-state version
const SleepScreenEmpty = ({ dark }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', background: c.background, display: 'flex', flexDirection: 'column' }}>
      <NavBar dark={dark} title="睡眠記録"/>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, flexDirection: 'column' }}>
        <div style={{
          width: 64, height: 64, borderRadius: 16, background: c.indigo50,
          display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16,
        }}>
          <MoonIcon size={28} color={c.indigo600} stroke={1.8}/>
        </div>
        <div style={{ fontSize: 16, fontWeight: 600, color: c.textPrimary, marginBottom: 8 }}>記録がありません</div>
        <div style={{ fontSize: 13, color: c.textSecondary, textAlign: 'center', lineHeight: 1.6, maxWidth: 240 }}>
          ヘルスケア連携を有効にするか、<br/>
          目覚めを記録してみましょう
        </div>
        <button style={{
          marginTop: 20, height: 44, padding: '0 20px',
          background: c.primary, color: '#fff', border: 'none',
          borderRadius: 6, fontFamily: window.T.font, fontSize: 14, fontWeight: 600,
          cursor: 'pointer',
        }}>目覚めを記録する</button>
      </div>
    </div>
  );
};

// Loading / syncing state
const SleepScreenLoading = ({ dark }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  const ShimmerLine = ({ w, h = 12 }) => (
    <div style={{
      width: w, height: h, borderRadius: 3,
      background: `linear-gradient(90deg, ${c.slate100} 0%, ${c.slate200} 50%, ${c.slate100} 100%)`,
      backgroundSize: '200% 100%',
      animation: 'shimmer 1.4s linear infinite',
    }}/>
  );
  return (
    <div style={{ height: '100%', background: c.background, display: 'flex', flexDirection: 'column' }}>
      <style>{`@keyframes shimmer { 0%{background-position:100% 0} 100%{background-position:-100% 0} }`}</style>
      <NavBar dark={dark} title="睡眠記録"
        trailing={<div style={{ padding: 8 }}><RefreshIcon size={18} color={c.primary} stroke={2} style={{ animation: 'spin 1.2s linear infinite' }}/></div>}
      />
      <style>{`@keyframes spin { 100% { transform: rotate(360deg); } }`}</style>
      <div style={{ padding: 16 }}>
        <Card dark={dark}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 14 }}>
            <ShimmerLine w={100}/>
            <ShimmerLine w={80}/>
          </div>
          <ShimmerLine w={140} h={28}/>
          <div style={{ height: 12 }}/>
          <ShimmerLine w="100%" h={52}/>
          <div style={{ height: 14 }}/>
          <ShimmerLine w="100%" h={28}/>
          <div style={{ height: 8 }}/>
          <ShimmerLine w="80%" h={10}/>
        </Card>
        <div style={{ marginTop: 20, textAlign: 'center', fontSize: 12, color: c.textSecondary }}>
          HealthKitから同期中…
        </div>
      </div>
    </div>
  );
};

Object.assign(window, { SleepScreen, SleepScreenEmpty, SleepScreenLoading });
