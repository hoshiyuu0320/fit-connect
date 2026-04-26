// Tweaks panel — Light/Dark, Chart A/B, Card state switcher.
// Posts __edit_mode_available after registering listener.

function useTweaks() {
  const [state, setState] = React.useState(() => {
    try {
      const saved = localStorage.getItem('sleep_tweaks');
      if (saved) return JSON.parse(saved);
    } catch (e) {}
    return window.TWEAK_DEFAULTS;
  });
  const [show, setShow] = React.useState(false);

  React.useEffect(() => {
    const onMsg = (e) => {
      const d = e.data;
      if (!d || typeof d !== 'object') return;
      if (d.type === '__activate_edit_mode')   setShow(true);
      if (d.type === '__deactivate_edit_mode') setShow(false);
    };
    window.addEventListener('message', onMsg);
    try { window.parent.postMessage({ type: '__edit_mode_available' }, '*'); } catch (e) {}
    return () => window.removeEventListener('message', onMsg);
  }, []);

  const update = (patch) => {
    setState(s => {
      const next = { ...s, ...patch };
      try { localStorage.setItem('sleep_tweaks', JSON.stringify(next)); } catch(e){}
      try { window.parent.postMessage({ type: '__edit_mode_set_keys', edits: patch }, '*'); } catch(e){}
      return next;
    });
  };

  return [state, update, show];
}

function TweaksPanel({ state, update }) {
  const btnBase = {
    padding: '7px 12px', borderRadius: 6, border: '1px solid #d6d3cf',
    background: '#fff', cursor: 'pointer',
    fontFamily: window.T.font, fontSize: 12, fontWeight: 500, color: '#1E293B',
  };
  const active = { ...btnBase, background: '#2563EB', color: '#fff', borderColor: '#2563EB' };

  const Group = ({ label, children }) => (
    <div style={{ marginBottom: 14 }}>
      <div style={{
        fontSize: 10, letterSpacing: 0.6, textTransform: 'uppercase',
        fontWeight: 600, color: '#64748B', marginBottom: 6,
      }}>{label}</div>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>{children}</div>
    </div>
  );
  return (
    <div style={{
      position: 'fixed', right: 20, bottom: 20, zIndex: 1000,
      width: 240, background: '#fefcf7',
      borderRadius: 10, padding: '14px 16px 10px',
      boxShadow: '0 10px 40px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.06)',
      fontFamily: window.T.font,
    }}>
      <div style={{
        fontSize: 13, fontWeight: 700, color: '#1E293B',
        marginBottom: 10, letterSpacing: -0.2,
      }}>Tweaks</div>
      <Group label="Theme">
        {[['light','ライト'],['dark','ダーク'],['split','並列']].map(([k,l]) => (
          <button key={k} style={state.theme === k ? active : btnBase}
            onClick={() => update({ theme: k })}>{l}</button>
        ))}
      </Group>
      <Group label="Stage chart">
        {[['bar','A: 棒'],['pie','B: 円']].map(([k,l]) => (
          <button key={k} style={state.chart === k ? active : btnBase}
            onClick={() => update({ chart: k })}>{l}</button>
        ))}
      </Group>
      <Group label="Summary card state">
        {[['healthkit','HK'],['manual','手動'],['empty','未記録']].map(([k,l]) => (
          <button key={k} style={state.cardState === k ? active : btnBase}
            onClick={() => update({ cardState: k })}>{l}</button>
        ))}
      </Group>
    </div>
  );
}

Object.assign(window, { useTweaks, TweaksPanel });
