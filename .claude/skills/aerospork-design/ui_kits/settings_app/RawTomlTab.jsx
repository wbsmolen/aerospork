const { BarStrip, Icon, Button, CodeEditor, StatusLabel, MenuPanel } = window.AeroSporkDesignSystem_078bd7;

// Every `[section]` / `[[array-of-table]]` header line, in document order — feeds both the
// Sections… menu below and CodeEditor's `sectionHeaders` prop, so the menu and the editor's own
// header-line highlighting can never disagree about what counts as a header.
function findSectionHeaders(text) {
  const headerRe = /^\[{1,2}[^\[\]=]+\]{1,2}$/;
  return text.split('\n').reduce((acc, line, i) => {
    const code = line.split('#')[0].trim();
    if (headerRe.test(code)) acc.push({ label: code, line: i + 1 });
    return acc;
  }, []);
}

function RawTomlTab({ toml, setToml, original }) {
  const edited = toml !== original;
  const lines = toml.split('\n');
  const badLine = lines.findIndex((l) => /^\s*=/.test(l));
  const errorLine = badLine === -1 ? null : badLine + 1;
  const error = errorLine ? `line ${errorLine}: expected a key before ‘=’` : null;
  const sectionHeaders = React.useMemo(() => findSectionHeaders(toml), [toml]);

  const [cursor, setCursor] = React.useState({ line: 1, col: 1 });
  const [sectionsOpen, setSectionsOpen] = React.useState(false);
  const [sectionsMenuPos, setSectionsMenuPos] = React.useState(null);
  const [errorHover, setErrorHover] = React.useState(false);
  const editorRef = React.useRef(null);
  const sectionsButtonRef = React.useRef(null);

  const jumpToLine = (line) => editorRef.current && editorRef.current.scrollToLine(line);

  // Portaled to document.body, not rendered in place: this bar strip sits directly above
  // CodeEditor's own scrolling, absolutely-positioned overlay (the highlighted-<pre>-under-a-
  // transparent-<textarea> trick), which paints its z-index:auto layer ahead of an ordinary
  // in-place z-indexed popup here regardless of the z-index value -- confirmed empirically
  // (`elementsFromPoint` put the textarea above a z-index:10/20 popup every time). A portal is
  // the standard fix for exactly this: it sits in body's own stacking order, so no ancestor's
  // stacking context can bury it. Position is computed from the button's own rect since a
  // portaled node can't rely on a `position: relative` ancestor for placement.
  const openSectionsMenu = () => {
    const r = sectionsButtonRef.current && sectionsButtonRef.current.getBoundingClientRect();
    if (r) setSectionsMenuPos({ top: r.bottom + 4, right: window.innerWidth - r.right });
    setSectionsOpen((v) => !v);
  };

  return (
    <div className="tab-column">
      <BarStrip edge="top" padded={false}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 14px' }}>
          <span style={{ color: 'var(--label-secondary)' }}><Icon sf="doc.plaintext" size={13} /></span>
          <span className="mono" style={{ fontSize: 'var(--text-callout)', color: 'var(--label-secondary)' }}>/Users/you/.aerospork.toml</span>
          <span style={{ flex: 1 }} />
          <span style={{ fontSize: 'var(--text-callout)', color: 'var(--label-secondary)', fontFamily: 'var(--font-system)' }}>
            Ln {cursor.line}, Col {cursor.col}
          </span>
          <div style={{ position: 'relative' }}>
            {/* `Button` isn't `forwardRef`-wrapped (nor should it become so just for this one
                caller), so the position probe sits on a plain wrapper span instead. */}
            <span ref={sectionsButtonRef} style={{ display: 'inline-block' }}>
              <Button variant="borderless" disabled={sectionHeaders.length === 0}
                title={sectionHeaders.length === 0 ? 'This file has no sections' : 'Jump to a section'}
                onClick={openSectionsMenu}>Sections…</Button>
            </span>
            {sectionsOpen && sectionHeaders.length > 0 && sectionsMenuPos && ReactDOM.createPortal(
              <div style={{ position: 'fixed', top: sectionsMenuPos.top, right: sectionsMenuPos.right, zIndex: 1000 }}>
                <MenuPanel width={240} items={sectionHeaders.map((h) => ({
                  label: h.label, mono: true,
                  onClick: () => { jumpToLine(h.line); setSectionsOpen(false); },
                }))} />
              </div>,
              document.body,
            )}
          </div>
          <Button variant="borderless" title="External edits are picked up automatically: the config file is watched">Open in TextEdit</Button>
          <Button variant="borderless" title="Re-read the config file. Normally automatic.">Reload</Button>
        </div>
      </BarStrip>
      {/* Search-in-editor (⌘F): system-drawn by AppKit's NSTextView find bar in the real app
          (usesFindBar) — no fake find-bar overlay belongs in this design system. */}
      <CodeEditor ref={editorRef} value={toml} onChange={setToml}
        errorLine={errorLine} warningLines={[]} sectionHeaders={sectionHeaders}
        onCursorMove={(line, col) => setCursor({ line, col })} />
      <BarStrip padded={false}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '9px 14px' }}>
          {/* errorLine is always known for this mock's fake heuristic below, so the clickable path
              is the only one exercised here — the plain/unclickable fallback is the semantic-error,
              no-position case from proposal-rawtoml.md §2.3, not reachable from this buffer alone. */}
          {error
            ? <span onClick={() => jumpToLine(errorLine)}
                onMouseEnter={() => setErrorHover(true)} onMouseLeave={() => setErrorHover(false)}
                title={`Jump to line ${errorLine}`}
                style={{ cursor: 'pointer', textDecoration: errorHover ? 'underline' : 'none' }}>
                <StatusLabel kind="error">{error}</StatusLabel>
              </span>
            : edited ? <StatusLabel kind="ok">Valid. Press Apply (⌘S) to write it.</StatusLabel>
            : <StatusLabel kind="neutral">Matches the file on disk</StatusLabel>}
          <span style={{ flex: 1 }} />
          <Button variant="borderless" title="Load a previous version of this config into the editor">Restore…</Button>
          <Button disabled={!edited} onClick={() => setToml(original)}>Revert</Button>
          <Button variant="prominent" disabled={!edited || !!error}>Apply</Button>
        </div>
      </BarStrip>
    </div>
  );
}
Object.assign(window, { RawTomlTab });
