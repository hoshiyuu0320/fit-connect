// Hi-fi HealthSettingsScreen — extension to existing health toggle list.

const SettingRow = ({ title, subtitle, on, dark, isNew, accent }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{
      padding: '14px 16px', display: 'flex',
      justifyContent: 'space-between', alignItems: 'center', gap: 16,
    }}>
      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flex: 1 }}>
        {accent && (
          <div style={{
            width: 32, height: 32, borderRadius: 6, background: accent.bg, flexShrink: 0,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>{accent.icon}</div>
        )}
        <div>
          <div style={{
            fontSize: 14, fontWeight: 600, color: c.textPrimary,
            letterSpacing: '-0.01em', display: 'flex', alignItems: 'center', gap: 6,
          }}>
            {title}
            {isNew && (
              <span style={{
                background: c.indigo50, color: c.indigo600,
                fontSize: 9, fontWeight: 700,
                padding: '2px 6px', borderRadius: 4, letterSpacing: 0.4,
              }}>NEW</span>
            )}
          </div>
          <div style={{ fontSize: 12, color: c.textSecondary, marginTop: 4, lineHeight: 1.5 }}>
            {subtitle}
          </div>
        </div>
      </div>
      <Toggle on={on} dark={dark}/>
    </div>
  );
};

const SettingsScreen = ({ dark = false }) => {
  const c = window.TOKENS[dark ? 'dark' : 'light'];
  return (
    <div style={{ height: '100%', background: c.background, display: 'flex', flexDirection: 'column' }}>
      <NavBar dark={dark} title="ヘルスケア連携"/>
      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 16px 32px' }}>
        {/* Header card */}
        <Card dark={dark} style={{ marginBottom: 20, padding: '16px', background: c.indigo50, border: 'none' }}>
          <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <HeartPulseIcon size={18} color={c.indigo600}/>
            <div style={{ fontSize: 12, color: dark ? c.textPrimary : c.indigo700, lineHeight: 1.6 }}>
              有効にすると、iPhone のヘルスケアアプリから体重と睡眠のデータを自動で取得します。データは端末内で処理されます。
            </div>
          </div>
        </Card>

        {/* Existing section */}
        <div style={{ fontSize: 11, fontWeight: 600, color: c.textSecondary, letterSpacing: 0.4, textTransform: 'uppercase', padding: '0 4px 8px' }}>
          データ連携
        </div>
        <Card dark={dark} noPad>
          <SettingRow dark={dark}
            title="体重データ"
            subtitle="HealthKitから体重を取得します"
            accent={{ bg: c.slate100, icon: <ScaleIcon size={17} color={c.textSecondary}/> }}
            on
          />
          <div style={{ height: 1, background: c.slate100, marginLeft: 60 }}/>
          <SettingRow dark={dark} isNew
            title="睡眠データ"
            subtitle="HealthKitから睡眠データを取得します"
            accent={{ bg: c.indigo50, icon: <MoonIcon size={17} color={c.indigo600}/> }}
            on
          />
        </Card>

        {/* Notification section */}
        <div style={{ fontSize: 11, fontWeight: 600, color: c.textSecondary, letterSpacing: 0.4, textTransform: 'uppercase', padding: '24px 4px 8px' }}>
          通知
        </div>
        <Card dark={dark} noPad>
          <SettingRow dark={dark} isNew
            title="朝の目覚めダイアログ"
            subtitle="起床後（4:00-12:00）にアプリを開いた時、目覚めの記録を促します"
            accent={{ bg: dark ? '#3a2a0a' : '#FEF3C7', icon: <SunIcon size={17} color={c.warning}/> }}
            on
          />
        </Card>

        {/* Data management */}
        <div style={{ fontSize: 11, fontWeight: 600, color: c.textSecondary, letterSpacing: 0.4, textTransform: 'uppercase', padding: '24px 4px 8px' }}>
          データ管理
        </div>
        <Card dark={dark} noPad>
          <div style={{
            padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            cursor: 'pointer',
          }}>
            <div style={{ fontSize: 14, color: c.textPrimary, fontWeight: 500 }}>データを再同期</div>
            <ChevronRightIcon size={14} color={c.slate400}/>
          </div>
          <div style={{ height: 1, background: c.slate100, marginLeft: 16 }}/>
          <div style={{
            padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            cursor: 'pointer',
          }}>
            <div style={{ fontSize: 14, color: c.error, fontWeight: 500 }}>連携を解除</div>
            <ChevronRightIcon size={14} color={c.slate400}/>
          </div>
        </Card>
      </div>
    </div>
  );
};

Object.assign(window, { SettingsScreen, SettingRow });
