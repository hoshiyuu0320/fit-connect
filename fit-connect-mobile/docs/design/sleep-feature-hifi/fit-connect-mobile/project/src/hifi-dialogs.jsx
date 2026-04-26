// Hi-fi dialogs — MorningWakeupDialog + permission denied state.

const MorningDialog = ({ dark = false, selected }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  const options = [
    { key: 'smile', emoji: '😊', label: 'すっきり', color: c.success },
    { key: 'meh',   emoji: '😐', label: 'まあまあ', color: c.warning },
    { key: 'frown', emoji: '😫', label: 'だるい',   color: c.error   },
  ];
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: dark ? 'rgba(0,0,0,0.55)' : 'rgba(15,23,42,0.42)',
      backdropFilter: 'blur(6px)',
      WebkitBackdropFilter: 'blur(6px)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 24, zIndex: 10,
    }}>
      <div style={{
        width: '100%', background: c.cardBackground,
        borderRadius: 8, padding: 24,
        boxShadow: '0 20px 40px rgba(0,0,0,0.18)',
        fontFamily: window.T.font,
      }}>
        {/* header */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'center' }}>
          <SunIcon size={22} color={c.warning}/>
          <div style={{ fontSize: 20, fontWeight: 600, color: c.textPrimary, letterSpacing: '-0.01em' }}>
            おはようございます
          </div>
        </div>
        <div style={{ marginTop: 6, fontSize: 13, color: c.textSecondary, textAlign: 'center' }}>
          今朝の目覚めは？
        </div>

        {/* options */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 20 }}>
          {options.map(opt => {
            const isSel = opt.key === selected;
            return (
              <button key={opt.key} style={{
                height: 56, width: '100%', border: 'none',
                background: isSel ? c.primary50 : c.slate100,
                borderRadius: 6,
                padding: '0 16px', display: 'flex', alignItems: 'center', gap: 14,
                cursor: 'pointer', fontFamily: window.T.font,
                outline: isSel ? `2px solid ${c.primary}` : 'none',
                outlineOffset: -2,
              }}>
                <span style={{ fontSize: 24 }}>{opt.emoji}</span>
                <span style={{
                  fontSize: 16, fontWeight: 500,
                  color: isSel ? c.primary : c.textPrimary,
                  letterSpacing: '-0.01em',
                }}>{opt.label}</span>
              </button>
            );
          })}
        </div>

        {/* secondary actions */}
        <div style={{
          display: 'flex', justifyContent: 'space-between', marginTop: 20,
          paddingTop: 4,
        }}>
          <button style={{
            background: 'transparent', border: 'none', padding: '8px 4px',
            cursor: 'pointer', fontSize: 13, fontWeight: 500, color: c.primary,
            fontFamily: window.T.font,
          }}>あとで</button>
          <button style={{
            background: 'transparent', border: 'none', padding: '8px 4px',
            cursor: 'pointer', fontSize: 13, fontWeight: 500, color: c.textSecondary,
            fontFamily: window.T.font,
          }}>今日は聞かない</button>
        </div>
      </div>
    </div>
  );
};

// Full phone view with MorningDialog
const DialogScreen = ({ dark, selected }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', background: c.background, position: 'relative' }}>
      {/* Dimmed home screen behind */}
      <NavBar dark={dark} title="ホーム" leading={<span/>} trailing={<span/>}/>
      <div style={{ padding: 16, opacity: 0.7, filter: 'blur(1px)' }}>
        <Card dark={dark} style={{ minHeight: 96 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <MoonIcon size={15} color={c.indigo600}/>
            <span style={{ fontSize: 12, color: c.textSecondary }}>昨夜の睡眠</span>
          </div>
        </Card>
      </div>
      <MorningDialog dark={dark} selected={selected}/>
    </div>
  );
};

// Permission denied alert
const PermissionDenied = ({ dark }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: dark ? 'rgba(0,0,0,0.55)' : 'rgba(15,23,42,0.42)',
      backdropFilter: 'blur(6px)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 24, zIndex: 10,
    }}>
      <div style={{
        width: '100%', background: c.cardBackground,
        borderRadius: 8, padding: 20,
      }}>
        <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          <div style={{
            width: 36, height: 36, borderRadius: 8, background: dark ? '#3b0d0d' : '#FEE2E2',
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <LockIcon size={17} color={c.error}/>
          </div>
          <div>
            <div style={{ fontSize: 15, fontWeight: 600, color: c.textPrimary }}>
              ヘルスケアへのアクセスが許可されていません
            </div>
            <div style={{ fontSize: 12, color: c.textSecondary, marginTop: 6, lineHeight: 1.6 }}>
              設定アプリの「ヘルスケア」→「データアクセスとデバイス」から FIT-CONNECT に睡眠データの読み取りを許可してください。
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
          <button style={{
            flex: 1, height: 40, border: `1px solid ${c.slate200}`,
            background: c.cardBackground, color: c.textPrimary,
            borderRadius: 6, fontFamily: window.T.font, fontSize: 13, fontWeight: 500, cursor: 'pointer',
          }}>あとで</button>
          <button style={{
            flex: 1, height: 40, border: 'none',
            background: c.primary, color: '#fff',
            borderRadius: 6, fontFamily: window.T.font, fontSize: 13, fontWeight: 600, cursor: 'pointer',
          }}>設定を開く</button>
        </div>
      </div>
    </div>
  );
};

const PermissionScreen = ({ dark }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', background: c.background, position: 'relative' }}>
      <NavBar dark={dark} title="睡眠記録"
        trailing={<button style={{ background:'transparent', border:'none', padding:8 }}><RefreshIcon size={18} color={c.textSecondary}/></button>}
      />
      <div style={{ padding: 16, opacity: 0.6 }}>
        <Card dark={dark} style={{ minHeight: 140 }}/>
      </div>
      <PermissionDenied dark={dark}/>
    </div>
  );
};

Object.assign(window, { MorningDialog, DialogScreen, PermissionDenied, PermissionScreen });
