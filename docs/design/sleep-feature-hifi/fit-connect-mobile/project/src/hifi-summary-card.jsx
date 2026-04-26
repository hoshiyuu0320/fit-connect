// Hi-fi SleepSummaryCard — 3 states as defined in brief section 4-1.
// Widget placed on home screen. Honors 8px radius, 16px padding, 1px slate100 border.

const SummaryCard = ({ state = 'healthkit', dark = false, onClick }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  const container = {
    background: c.cardBackground,
    border: `1px solid ${c.slate100}`,
    borderRadius: window.T.radius.card,
    padding: window.T.pad.card,
    boxShadow: c.shadow,
    cursor: 'pointer',
  };
  const headerRow = (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <div style={{
          width: 28, height: 28, borderRadius: 6,
          background: c.indigo50,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <MoonIcon size={15} color={c.indigo600} stroke={2.2}/>
        </div>
        <span style={{ fontSize: 12, fontWeight: 500, color: c.textSecondary, letterSpacing: 0.02 }}>昨夜の睡眠</span>
      </div>
      {state === 'healthkit'
        ? <HeartPulseIcon size={14} color={c.textHint}/>
        : state === 'manual' ? <PenLineIcon size={14} color={c.textHint}/> : null}
    </div>
  );

  if (state === 'empty') {
    return (
      <div style={container} onClick={onClick}>
        {headerRow}
        <button style={{
          marginTop: 12,
          width: '100%', height: 44,
          background: c.primary50, color: c.primary,
          border: 'none', borderRadius: window.T.radius.button,
          fontSize: 14, fontWeight: 600, fontFamily: window.T.font,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          cursor: 'pointer', letterSpacing: 0.02,
        }}>
          目覚めを記録する
          <ArrowRightIcon size={15} color={c.primary} stroke={2.2}/>
        </button>
      </div>
    );
  }

  if (state === 'manual') {
    return (
      <div style={container} onClick={onClick}>
        {headerRow}
        <div style={{ marginTop: 10, display: 'flex', alignItems: 'center', gap: 10 }}>
          <RatingIcon rating={window.SAMPLE.rating} size={22}/>
          <span style={{
            fontSize: 18, fontWeight: 700, color: ratingColor('smile', dark ? 'dark' : 'light'),
            letterSpacing: '-0.01em',
          }}>{ratingLabel('smile')}</span>
        </div>
        <div style={{ marginTop: 6, fontSize: 12, color: c.textHint }}>タップして詳細を記録</div>
      </div>
    );
  }

  // healthkit
  const { h, m } = window.SAMPLE.duration;
  return (
    <div style={container} onClick={onClick}>
      {headerRow}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: 10 }}>
        <div>
          <div style={{
            fontSize: 24, fontWeight: 700, color: c.textPrimary,
            letterSpacing: '-0.02em', lineHeight: 1.1,
            fontFeatureSettings: '"tnum"',
          }}>
            {h}<span style={{ fontSize: 15, fontWeight: 600, color: c.textSecondary, margin: '0 1px 0 2px' }}>時間</span>
            {m}<span style={{ fontSize: 15, fontWeight: 600, color: c.textSecondary, marginLeft: 1 }}>分</span>
          </div>
          <div style={{ fontSize: 12, fontWeight: 400, color: c.textHint, marginTop: 4, fontFeatureSettings: '"tnum"' }}>
            {window.SAMPLE.bedtime} → {window.SAMPLE.wakeup}
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, paddingBottom: 4 }}>
          <RatingIcon rating={window.SAMPLE.rating} size={18}/>
          <span style={{ fontSize: 14, fontWeight: 600, color: ratingColor('smile', dark ? 'dark' : 'light') }}>
            {ratingLabel('smile')}
          </span>
        </div>
      </div>
    </div>
  );
};

Object.assign(window, { SummaryCard });
