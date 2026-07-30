const { WorkspaceChips, MenuPanel, Icon } = window.AeroSporkDesignSystem_078bd7;

const WORKSPACES = {
  '1': [
    { title: 'Ghostty', dark: true, lines: ['~ ❯ aerospork list-workspaces --focused', '1', '~ ❯ '] },
    { title: 'Xcode', lines: ['ConfigurationWindow.swift', '', 'struct ConfigurationWindow: View {', '    @StateObject private var viewModel'] },
    { title: 'Safari', lines: ['github.com/wbsmolen/aerospork'] },
  ],
  '2': [
    { title: 'Notes', lines: ['Fork notes', '— monitor identity by UUID', '— settings GUI, seven tabs'] },
    { title: 'Mail', lines: ['Inbox (3)'] },
  ],
  'web': [
    { title: 'Safari', lines: ['aerospork — docs / guide.adoc'] },
    { title: 'Figma', lines: ['AeroSpork brand'] },
    { title: 'Slack', lines: ['#aerospork'] },
  ],
};

function Tile({ w, focused, style }) {
  return (
    <div className={'win' + (focused ? ' focused' : '')} style={style}>
      <div className="bar">
        <span className="tl" style={{ background: '#ff5f57' }} /><span className="tl" style={{ background: '#febc2e' }} /><span className="tl" style={{ background: '#28c840' }} />
        <span style={{ marginLeft: 4 }}>{w.title}</span>
      </div>
      <div className={'body' + (w.dark ? ' dark' : '')}>{w.lines.map((l, i) => <div key={i}>{l || '\u00a0'}</div>)}</div>
    </div>
  );
}

function MenuBarKit() {
  const [workspace, setWorkspace] = React.useState('1');
  const [open, setOpen] = React.useState(false);
  const [enabled, setEnabled] = React.useState(true);
  const [mode, setMode] = React.useState(null);
  const gap = 8;
  const wins = WORKSPACES[workspace];

  const chips = [
    ...Object.keys(WORKSPACES).map((n) => ({ name: n, active: n === workspace })),
    ...(mode ? [{ name: mode, type: 'mode', active: true }] : []),
  ];

  const items = [
    ...(mode ? [{ label: 'Leave “' + mode + '” mode', onClick: () => { setMode(null); setOpen(false); } }, { divider: true }] : []),
    ...Object.keys(WORKSPACES).map((n) => ({
      label: n, mono: true, checked: n === workspace,
      onClick: () => { setWorkspace(n); setOpen(false); },
    })),
    { divider: true },
    { label: enabled ? 'Pause tiling' : 'Resume tiling', shortcut: '⌘E', onClick: () => { setEnabled(!enabled); setOpen(false); } },
    { divider: true },
    { label: 'Settings…', shortcut: '⌘,', onClick: () => { window.open('../settings_app/index.html', '_blank'); setOpen(false); } },
    { label: 'Quit AeroSpork', shortcut: '⌘Q', onClick: () => setOpen(false) },
  ];

  return (
    <div className="desktop" onClick={() => setOpen(false)}>
      <div className="menubar">
        <span className="apple"></span>
        <span className="app">Ghostty</span>
        <span style={{ opacity: .85 }}>File</span><span style={{ opacity: .85 }}>Edit</span><span style={{ opacity: .85 }}>View</span>
        <span className="right">
          <button className={'chips-btn' + (open ? ' open' : '')} onClick={(e) => { e.stopPropagation(); setOpen(!open); }}>
            {enabled
              ? <WorkspaceChips ink="light" height={16} items={chips} />
              : <span className="paused" style={{ color: '#fff' }}><Icon sf="pause.circle.fill" size={14} /></span>}
          </button>
          <span>Tue 16:41</span>
        </span>
      </div>

      {open && (
        <div className="menu-anchor" style={{ right: 78 }} onClick={(e) => e.stopPropagation()}>
          <MenuPanel width={228} items={items} />
        </div>
      )}

      <div className="stage" style={{ padding: 32 + 'px ' + 8 + 'px ' + 8 + 'px', gap }}>
        {enabled ? (
          <>
            <Tile w={wins[0]} focused style={{ flex: 1.28 }} />
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap }}>
              {wins.slice(1).map((w, i) => <Tile key={i} w={w} style={{ flex: 1 }} />)}
            </div>
          </>
        ) : (
          <div style={{ position: 'relative', flex: 1 }}>
            {wins.map((w, i) => (
              <Tile key={i} w={w} focused={i === 0}
                style={{ position: 'absolute', left: 40 + i * 46, top: 20 + i * 34, width: 460, height: 280 }} />
            ))}
          </div>
        )}
      </div>

      <div className="hint">
        Click the chips in the menu bar. Workspaces switch instantly — no macOS Spaces animation.
        {mode ? '' : ' '}
        {!mode && <button onClick={(e) => { e.stopPropagation(); setMode('service'); }}
          style={{ background: 'none', border: 'none', color: 'var(--brand-focused)', cursor: 'pointer', fontSize: 11, fontFamily: 'var(--font-system)' }}>
          Enter “service” mode
        </button>}
      </div>
    </div>
  );
}
Object.assign(window, { MenuBarKit });
