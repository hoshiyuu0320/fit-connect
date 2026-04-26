// Hi-fi charts — SleepStageChart A (horizontal bar) & B (pie)
// Plus SleepWeekChart.

const StageLegend = ({ dark, stages = window.SAMPLE.stages, mins = window.SAMPLE.stageMin, inline = false }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  const s = dark ? window.STAGE_DARK : window.STAGE;
  const items = [
    { key: 'deep',  label: '深い',  color: s.deep  },
    { key: 'light', label: '浅い',  color: s.light },
    { key: 'rem',   label: 'REM',   color: s.rem   },
    { key: 'awake', label: '覚醒',  color: s.awake },
  ];
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: inline ? '1fr' : '1fr 1fr',
      gap: '6px 12px', marginTop: 10,
    }}>
      {items.map(it => (
        <div key={it.key} style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 12 }}>
          <div style={{ width: 10, height: 10, borderRadius: 2, background: it.color, flexShrink: 0 }}/>
          <span style={{ color: c.textSecondary, fontWeight: 500 }}>{it.label}</span>
          <span style={{ color: c.textPrimary, fontWeight: 600, fontFeatureSettings: '"tnum"' }}>{stages[it.key]}%</span>
          <span style={{ color: c.textHint, fontFeatureSettings: '"tnum"', fontSize: 11 }}>({mins[it.key]})</span>
        </div>
      ))}
    </div>
  );
};

// ── A. Horizontal stacked bar ─────────────────────────────────
const StageBarChart = ({ dark, height = 28 }) => {
  const s = dark ? window.STAGE_DARK : window.STAGE;
  const { deep, light, rem, awake } = window.SAMPLE.stages;
  return (
    <div>
      <div style={{
        display: 'flex', height, borderRadius: 6, overflow: 'hidden',
        border: dark ? '1px solid rgba(255,255,255,0.04)' : '1px solid rgba(0,0,0,0.03)',
      }}>
        <div style={{ flex: deep,  background: s.deep  }}/>
        <div style={{ flex: light, background: s.light }}/>
        <div style={{ flex: rem,   background: s.rem   }}/>
        <div style={{ flex: awake, background: s.awake }}/>
      </div>
      <StageLegend dark={dark}/>
    </div>
  );
};

// ── B. Pie / donut chart ──────────────────────────────────────
const StagePieChart = ({ dark, size = 120 }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  const s = dark ? window.STAGE_DARK : window.STAGE;
  const { h, m } = window.SAMPLE.duration;
  const { deep, light, rem, awake } = window.SAMPLE.stages;
  const r = size / 2 - 1;
  const cx = size / 2, cy = size / 2;
  const cir = 2 * Math.PI * r;
  const segs = [
    { v: deep,  color: s.deep  },
    { v: light, color: s.light },
    { v: rem,   color: s.rem   },
    { v: awake, color: s.awake },
  ];
  let offset = 0;
  // Inner radius for donut
  const innerR = r * 0.62;
  return (
    <div style={{ display: 'flex', gap: 20, alignItems: 'center' }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ flexShrink: 0, transform: 'rotate(-90deg)' }}>
        {segs.map((seg, i) => {
          const len = (seg.v / 100) * cir;
          const el = (
            <circle key={i}
              cx={cx} cy={cy} r={r}
              fill="none" stroke={seg.color}
              strokeWidth={r - innerR}
              strokeDasharray={`${len} ${cir - len}`}
              strokeDashoffset={-offset}
            />
          );
          offset += len;
          return el;
        })}
      </svg>
      <div>
        <div style={{
          fontSize: 20, fontWeight: 700, color: c.textPrimary,
          letterSpacing: '-0.02em', lineHeight: 1, fontFeatureSettings: '"tnum"',
        }}>
          {h}<span style={{ fontSize: 13, color: c.textSecondary, fontWeight: 600 }}>時間</span>
          {m}<span style={{ fontSize: 13, color: c.textSecondary, fontWeight: 600 }}>分</span>
        </div>
        <div style={{ fontSize: 11, color: c.textHint, marginTop: 4, fontFeatureSettings: '"tnum"' }}>
          {window.SAMPLE.bedtime} → {window.SAMPLE.wakeup}
        </div>
        <StageLegend dark={dark} inline/>
      </div>
    </div>
  );
};

// ── Week trend line chart (fl_chart style) ────────────────────
const WeekChart = ({ dark, height = 160, showRatings = true }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  const data = window.SAMPLE.week;
  const dates = window.SAMPLE.weekDates;
  const ratings = window.SAMPLE.weekRate;
  const W = 320, H = height - (showRatings ? 40 : 20);
  const padX = 18, padY = 12;
  const xs = data.map((_, i) => padX + i * ((W - 2*padX) / (data.length - 1)));
  const yScale = v => {
    const min = 4, max = 10;
    return padY + (max - v) / (max - min) * (H - 2*padY);
  };
  // Build line paths, breaking on null
  const segments = [];
  let cur = [];
  data.forEach((v, i) => {
    if (v == null) { if (cur.length > 1) segments.push(cur); cur = []; }
    else cur.push([xs[i], yScale(v)]);
  });
  if (cur.length > 1) segments.push(cur);

  // Area path under line (for gradient fill)
  const areaPath = segments.map(seg => {
    const pts = seg.map(([x,y]) => `${x},${y}`).join(' L');
    return `M${seg[0][0]},${H - padY} L${pts} L${seg[seg.length-1][0]},${H - padY} Z`;
  }).join(' ');

  const gradId = `wg-${dark ? 'd' : 'l'}`;

  return (
    <div>
      <svg width="100%" viewBox={`0 0 ${W} ${H}`} style={{ display: 'block' }}>
        <defs>
          <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={c.primary} stopOpacity="0.24"/>
            <stop offset="100%" stopColor={c.primary} stopOpacity="0"/>
          </linearGradient>
        </defs>
        {/* y-axis ref lines */}
        {[5,6,7,8,9].map(v => (
          <line key={v} x1={padX} x2={W-padX} y1={yScale(v)} y2={yScale(v)}
                stroke={c.slate100} strokeWidth="1"/>
        ))}
        {/* filled area */}
        <path d={areaPath} fill={`url(#${gradId})`}/>
        {/* line segments */}
        {segments.map((seg, i) => (
          <polyline key={i}
            points={seg.map(([x,y]) => `${x},${y}`).join(' ')}
            fill="none" stroke={c.primary} strokeWidth="2"
            strokeLinecap="round" strokeLinejoin="round"/>
        ))}
        {/* gap line (dashed) for missing day */}
        {data.map((v, i) => {
          if (v != null || i === 0 || i === data.length-1) return null;
          const prev = data.slice(0, i).reverse().findIndex(x => x != null);
          const next = data.slice(i+1).findIndex(x => x != null);
          if (prev < 0 || next < 0) return null;
          const pi = i - 1 - prev, ni = i + 1 + next;
          return (
            <line key={`g${i}`}
              x1={xs[pi]} y1={yScale(data[pi])}
              x2={xs[ni]} y2={yScale(data[ni])}
              stroke={c.slate200} strokeWidth="1.5" strokeDasharray="3 3"/>
          );
        })}
        {/* nodes */}
        {data.map((v, i) => v == null ? (
          <circle key={i} cx={xs[i]} cy={H/2} r="3" fill={c.cardBackground} stroke={c.slate200} strokeWidth="1.5"/>
        ) : (
          <circle key={i} cx={xs[i]} cy={yScale(v)} r="3.5" fill={c.cardBackground} stroke={c.primary} strokeWidth="2"/>
        ))}
      </svg>
      {/* x-axis labels + rating glyphs */}
      <div style={{
        display: 'flex', justifyContent: 'space-between',
        padding: `6px ${padX-6}px 0`, fontSize: 10, color: c.textHint,
        fontFeatureSettings: '"tnum"',
      }}>
        {dates.map((d, i) => (
          <div key={d} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, width: 32 }}>
            <span style={{ fontWeight: i === dates.length-1 ? 600 : 400, color: i === dates.length-1 ? c.textSecondary : c.textHint }}>{d}</span>
            {showRatings && (
              <div style={{ height: 14 }}>
                {ratings[i] && <RatingIcon rating={ratings[i]} size={12}/>}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};

Object.assign(window, { StageBarChart, StagePieChart, WeekChart, StageLegend });
