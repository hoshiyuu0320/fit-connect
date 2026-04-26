// Shared primitive components — phone frame shells, section headings, pills, toggle.

const PhoneFrame = ({ children, dark = false, width = 390, height = 844, label }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ flexShrink: 0 }}>
      {label && (
        <div style={{
          fontFamily: window.T.mono, fontSize: 11, letterSpacing: 0.6,
          textTransform: 'uppercase', color: 'rgba(60,50,40,0.6)',
          marginBottom: 10,
        }}>{label}</div>
      )}
      <div style={{
        width, height, borderRadius: 44, overflow: 'hidden',
        background: c.background,
        boxShadow: '0 1px 2px rgba(0,0,0,0.08), 0 20px 48px rgba(0,0,0,0.12), 0 0 0 1px rgba(0,0,0,0.08)',
        position: 'relative',
        fontFamily: window.T.font,
        color: c.textPrimary,
      }}>
        <StatusBar dark={dark}/>
        <div style={{ paddingTop: 44, height: '100%', overflow: 'hidden' }}>
          {children}
        </div>
        {/* home indicator */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 100,
          background: dark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.25)',
        }}/>
      </div>
    </div>
  );
};

const StatusBar = ({ dark = false }) => {
  const col = dark ? '#fff' : '#000';
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      height: 44, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 24px', fontWeight: 600, fontSize: 15, color: col,
      fontFamily: '-apple-system, system-ui', zIndex: 5,
    }}>
      <span style={{ letterSpacing: -0.3 }}>9:41</span>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
        {/* signal */}
        <svg width="17" height="11" viewBox="0 0 17 11">
          <rect x="0" y="7" width="3" height="4" rx="0.5" fill={col}/>
          <rect x="4.5" y="5" width="3" height="6" rx="0.5" fill={col}/>
          <rect x="9" y="2.5" width="3" height="8.5" rx="0.5" fill={col}/>
          <rect x="13.5" y="0" width="3" height="11" rx="0.5" fill={col}/>
        </svg>
        {/* wifi */}
        <svg width="16" height="11" viewBox="0 0 16 11">
          <path d="M8 2c2.5 0 4.7 1 6.3 2.5l.7-.7C13.3 2 10.8 1 8 1S2.7 2 1 3.8l.7.7C3.3 3 5.5 2 8 2zM8 5c1.5 0 2.8.6 3.8 1.6l.7-.7C11.3 4.6 9.7 4 8 4s-3.3.6-4.5 1.9l.7.7C5.2 5.6 6.5 5 8 5z" fill={col}/>
          <circle cx="8" cy="9" r="1.5" fill={col}/>
        </svg>
        {/* battery */}
        <svg width="25" height="12" viewBox="0 0 25 12">
          <rect x="0.5" y="0.5" width="21" height="11" rx="3" stroke={col} strokeOpacity="0.4" fill="none"/>
          <rect x="2" y="2" width="18" height="8" rx="1.5" fill={col}/>
          <path d="M23 4v4c0.8-0.3 1.5-1.2 1.5-2S23.8 4.3 23 4z" fill={col} fillOpacity="0.5"/>
        </svg>
      </div>
    </div>
  );
};

const NavBar = ({ title, dark = false, trailing, leading }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      height: 44, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 12px', borderBottom: `1px solid ${c.slate100}`,
      background: c.cardBackground,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', width: 60 }}>
        {leading ?? (
          <button style={{
            background: 'transparent', border: 'none', cursor: 'pointer',
            padding: 8, display: 'flex', alignItems: 'center', gap: 4,
            color: c.primary, fontSize: 15, fontFamily: window.T.font, fontWeight: 500,
          }}>
            <ChevronLeftIcon size={18} color={c.primary} stroke={2.5}/>
          </button>
        )}
      </div>
      <div style={{ fontWeight: 600, fontSize: 16, color: c.textPrimary, letterSpacing: '-0.01em' }}>{title}</div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', width: 60 }}>
        {trailing}
      </div>
    </div>
  );
};

const SectionTitle = ({ children, right, dark }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 0 10px', marginTop: 4,
    }}>
      <div style={{ fontSize: 14, fontWeight: 600, color: c.textPrimary, letterSpacing: '0.01em' }}>{children}</div>
      {right}
    </div>
  );
};

const Card = ({ children, dark, style, noPad }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      background: c.cardBackground,
      border: `1px solid ${c.slate100}`,
      borderRadius: window.T.radius.card,
      padding: noPad ? 0 : window.T.pad.card,
      boxShadow: c.shadow,
      ...style,
    }}>{children}</div>
  );
};

const Chip = ({ children, color, bg, dark, style }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '3px 8px', borderRadius: 6,
      background: bg ?? c.slate100, color: color ?? c.textSecondary,
      fontSize: 11, fontWeight: 500, letterSpacing: 0.02,
      ...style,
    }}>{children}</span>
  );
};

const Toggle = ({ on, dark }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      width: 44, height: 26, borderRadius: 13,
      background: on ? c.primary : c.slate200,
      position: 'relative', transition: 'background 0.2s',
      flexShrink: 0,
    }}>
      <div style={{
        position: 'absolute', top: 2, left: on ? 20 : 2,
        width: 22, height: 22, borderRadius: '50%', background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.2)', transition: 'left 0.2s',
      }}/>
    </div>
  );
};

Object.assign(window, { PhoneFrame, StatusBar, NavBar, SectionTitle, Card, Chip, Toggle });
