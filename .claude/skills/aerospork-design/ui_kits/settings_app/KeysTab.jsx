const { BarStrip, TextField, Button, Icon, KeyRecorderField, PrettyKey, KeyCaps, FormSection, SectionLabel, Badge, ContentUnavailable, SettingsHint, StatusLabel, IconButton, MenuPanel } = window.AeroSporkDesignSystem_078bd7;

// Categories, derived from the command's leading verb (before the first ';'). Verified against
// Sources/AppBundle/command/cmdManifest.swift's CmdArgs.Kind switch: every case there maps to one
// of these four buckets or falls through to Other (list-*, move-mouse, debug-windows).
const CATEGORY_VERBS = {
  'Focus': ['focus', 'focus-monitor', 'focus-back-and-forth'],
  'Move & workspace': ['move', 'move-node-to-workspace', 'move-node-to-monitor', 'move-workspace-to-monitor', 'workspace', 'workspace-back-and-forth', 'summon-workspace'],
  'Layout & resize': ['layout', 'split', 'join-with', 'fullscreen', 'resize', 'balance-sizes', 'flatten-workspace-tree', 'macos-native-fullscreen', 'macos-native-minimize'],
  'Mode & system': ['mode', 'reload-config', 'enable', 'close', 'close-all-windows-but-current', 'volume', 'exec-and-forget', 'trigger-binding', 'config', 'open-settings'],
};
const CATEGORY_ORDER = ['Focus', 'Move & workspace', 'Layout & resize', 'Mode & system', 'Other'];
// One glyph per category card header — crosshair for aim, a workspace grid, the 3-pane split
// General's own Layout section uses, a terminal for the exec/system bucket.
const CATEGORY_ICONS = { 'Focus': 'scope', 'Move & workspace': 'square.grid.2x2', 'Layout & resize': 'rectangle.split.3x1', 'Mode & system': 'terminal', 'Other': 'ellipsis.circle' };

function categoryFor(command) {
  const verb = command.split(';')[0].trim().split(/\s+/)[0] || '';
  for (const cat of CATEGORY_ORDER) {
    if ((CATEGORY_VERBS[cat] || []).includes(verb)) return cat;
  }
  return 'Other';
}

// A starting point for the command field's autocomplete, grounded in the real command set
// (cmdManifest.swift) — not a constraint. Selecting one fills the field; the user can still type
// or append anything, chained commands included. `quick` marks the six shown before any typing,
// one per category so the empty-state list isn't just every focus-* variant.
const COMMAND_SUGGESTIONS = [
  { cmd: 'focus left', cat: 'Focus', quick: true },
  { cmd: 'focus down', cat: 'Focus' },
  { cmd: 'focus up', cat: 'Focus' },
  { cmd: 'focus right', cat: 'Focus' },
  { cmd: 'focus-monitor next', cat: 'Focus' },
  { cmd: 'focus-back-and-forth', cat: 'Focus' },
  { cmd: 'move left', cat: 'Move & workspace' },
  { cmd: 'move-node-to-workspace 3', cat: 'Move & workspace', quick: true },
  { cmd: 'move-node-to-monitor next', cat: 'Move & workspace' },
  { cmd: 'workspace 1', cat: 'Move & workspace' },
  { cmd: 'workspace-back-and-forth', cat: 'Move & workspace' },
  { cmd: 'layout floating tiling', cat: 'Layout & resize', quick: true },
  { cmd: 'layout accordion', cat: 'Layout & resize' },
  { cmd: 'split horizontal', cat: 'Layout & resize' },
  { cmd: 'resize smart -50', cat: 'Layout & resize' },
  { cmd: 'fullscreen', cat: 'Layout & resize' },
  { cmd: 'mode service', cat: 'Mode & system', quick: true },
  { cmd: 'reload-config', cat: 'Mode & system', quick: true },
  { cmd: 'close-all-windows-but-current', cat: 'Mode & system' },
  { cmd: 'volume up', cat: 'Mode & system' },
  { cmd: 'exec-and-forget open -na Ghostty', cat: 'Mode & system', quick: true },
];
function commandSuggestions(query) {
  const q = query.trim().toLowerCase();
  const pool = q ? COMMAND_SUGGESTIONS.filter((s) => s.cmd.toLowerCase().includes(q)) : COMMAND_SUGGESTIONS.filter((s) => s.quick);
  return pool.slice(0, 6);
}

// Wraps the first hit of `needle` in a light accent mark — used in the search-primary flat list,
// never in the browse-by-category cards (there is no needle there to highlight).
function highlightMatch(text, needle) {
  if (!needle) return text;
  const i = text.toLowerCase().indexOf(needle);
  if (i === -1) return text;
  return (
    <React.Fragment>
      {text.slice(0, i)}
      <mark style={{ background: 'var(--accent-selection-fill)', color: 'inherit', borderRadius: 2 }}>{text.slice(i, i + needle.length)}</mark>
      {text.slice(i + needle.length)}
    </React.Fragment>
  );
}

// Modes are i3-style: a named set of bindings that is either always active ("main") or entered
// and left by a binding elsewhere. Most users have never met the concept, so instead of just a
// switcher, name the entry and exit keys for the mode actually on screen — read out of the real
// bindings, not asserted in prose that can drift from them.
function describeMode(name, bindings) {
  if (name === 'main') return 'Always active — every other mode is entered from here and returns to it.';
  const entry = Object.entries(bindings)
    .flatMap(([m, rows]) => (m === name ? [] : rows.map((row) => ({ mode: m, row }))))
    .find(({ row }) => row.command.split(';')[0].trim() === 'mode ' + name);
  const exits = (bindings[name] || []).filter((row) => row.command.split(';').some((c) => c.trim() === 'mode main'));
  let s = entry ? 'Entered with ' + PrettyKey(entry.row.key) + ' from “' + entry.mode + '”.' : 'Entered by a “mode ' + name + '” command elsewhere.';
  if (exits.length === 1) s += ' ' + PrettyKey(exits[0].key) + ' returns to “main”.';
  else if (exits.length > 1) s += ' ' + PrettyKey(exits[0].key) + ' and ' + (exits.length - 1) + ' more return to “main”.';
  return s;
}

const stepLabelStyle = { font: 'var(--weight-medium) var(--text-subheadline)/1 var(--font-system)', color: 'var(--label-tertiary)' };
const cardShellStyle = { background: 'var(--control-bg)', borderRadius: 'var(--radius-card)', boxShadow: '0 0 0 0.5px var(--separator)', overflow: 'hidden' };

// One binding in the *active* mode: editable if it has a line to edit, read-only chips otherwise.
// Used both inside a category card (no outer padding — FormSection supplies it) and in the
// search-primary flat list (`dense`: the tighter `.binding-row` padding, so many matches still
// fit at a glance). `needle` only ever arrives non-empty in the dense/search case, to ring the key
// chips when the match was in the key rather than the command.
function BindingRow({ b, needle, dense, onUpdate, onRemove, onOverride, onDuplicate }) {
  const keyHit = needle && b.key.toLowerCase().includes(needle);
  return (
    <div className={dense ? 'binding-row' : undefined} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <span style={{
        width: 'var(--w-recorder)', flex: '0 0 auto', display: 'flex', borderRadius: 6,
        boxShadow: keyHit ? 'inset 0 0 0 1.5px var(--accent)' : 'none', padding: keyHit ? 2 : 0,
      }}>
        {b.origin === 'explicit' ? <KeyRecorderField notation={b.key} showsClear={false} /> : <KeyCaps notation={b.key} />}
      </span>
      <span style={{ flex: 1, minWidth: 0 }}>
        {b.origin === 'explicit'
          ? <TextField mono value={b.command} onChange={(v) => onUpdate(b.id, { command: v })} style={{ width: '100%' }} />
          : <span className="mono cmdcell">{highlightMatch(b.command, needle)}</span>}
      </span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flex: '0 0 auto' }}>
        {b.origin === 'generated' && <Badge help="Generated from mod and workspaces. It is not written in your config file.">generated</Badge>}
        <IconButton systemImage="plus.square.on.square" label={'Duplicate “' + b.command + '”'} onClick={() => onDuplicate(b)} />
        {b.origin === 'explicit'
          ? <IconButton systemImage="minus.circle" role="destructive" label={'Remove “' + b.key + '”'} onClick={() => onRemove(b.id)} />
          : <Button variant="borderless" onClick={() => onOverride(b)}>Override</Button>}
      </div>
    </div>
  );
}

// A match from a mode other than the active one: read-only regardless of origin (editing a
// binding you can't see the rest of is how you end up with two conflicting keys), tagged with its
// mode, and offering only "Go" — the same restriction the previous round enforced, just restyled.
function CrossModeRow({ mode, row, needle, onGo }) {
  return (
    <div className="binding-row" style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <span style={{ width: 54, flex: '0 0 auto', color: 'var(--label-secondary)', fontSize: 'var(--text-callout)' }}>“{mode}”</span>
      <span style={{ width: 'var(--w-recorder)', flex: '0 0 auto' }}><KeyCaps notation={row.key} /></span>
      <span className="mono cmdcell" style={{ flex: 1, minWidth: 0 }}>{highlightMatch(row.command, needle)}</span>
      {row.origin === 'generated' && <Badge help="Generated from mod and workspaces. It is not written in your config file.">generated</Badge>}
      <Button variant="borderless" onClick={onGo}>Go</Button>
    </div>
  );
}

function KeysTab({ bindings, setBindings }) {
  const [mode, setMode] = React.useState('main');
  const [query, setQuery] = React.useState('');
  const [newKey, setNewKey] = React.useState('');
  const [newCommand, setNewCommand] = React.useState('');
  const [recording, setRecording] = React.useState(false);
  const [modeMenuOpen, setModeMenuOpen] = React.useState(false);
  const [suggestOpen, setSuggestOpen] = React.useState(false);

  const all = bindings[mode] || [];
  const needle = query.trim().toLowerCase();
  const rowMatches = (b) => b.key.toLowerCase().includes(needle) || b.command.toLowerCase().includes(needle);
  const rows = needle ? all.filter(rowMatches) : all;
  const generated = all.filter((b) => b.origin === 'generated').length;
  const explicit = all.length - generated;
  const conflict = newKey ? all.find((b) => b.key === newKey) : null;
  const deleteModeLabel = 'Delete “' + mode + '”' + (explicit > 0 ? ' — ' + explicit + (explicit === 1 ? ' binding' : ' bindings') : '');

  // Real mode list (main first, then alphabetical) — the pills below used to be a SegmentedPicker
  // hardcoded to ['main', 'service'], which meant a config with a third mode (this mock's "apps")
  // had no way to reach it from the GUI at all. Deriving it from the data fixes that, and scrolls
  // rather than overflows if someone has many modes, instead of relying on a fixed width fitting.
  const modeNames = ['main', ...Object.keys(bindings).filter((m) => m !== 'main').sort()];
  const otherModeNames = modeNames.filter((m) => m !== mode);
  const crossModeRowMatches = needle
    ? otherModeNames.flatMap((m) => (bindings[m] || []).filter(rowMatches).map((row) => ({ mode: m, row })))
    : [];
  const otherModesWithMatches = needle ? otherModeNames.filter((m) => (bindings[m] || []).some(rowMatches)) : [];

  const isSearching = !!needle;
  let emptyTitle, emptyMessage, emptyActionTitle, emptyAction;
  if (isSearching) {
    emptyTitle = 'No matches';
    emptyMessage = 'Nothing in “' + mode + '” matches “' + query + '”.'
      + (otherModesWithMatches.length === 1 ? ' It’s bound in “' + otherModesWithMatches[0] + '” instead.'
        : otherModesWithMatches.length >= 2 ? ' It’s bound in other modes.' : '');
    emptyActionTitle = otherModesWithMatches.length === 1 ? 'Go to “' + otherModesWithMatches[0] + '”' : 'Clear filter';
    emptyAction = otherModesWithMatches.length === 1 ? () => setMode(otherModesWithMatches[0]) : () => setQuery('');
  } else {
    // Empty states teach the feature rather than announce emptiness — point straight at the
    // composer that fixes it, the way Window Rules' empty state points at "Add".
    emptyTitle = 'No bindings yet';
    emptyMessage = '“' + mode + '” mode has no bindings. Record a shortcut below and describe what it does to add the first one.';
    emptyActionTitle = undefined;
    emptyAction = undefined;
  }

  const crossModeKeyMatches = newKey ? otherModeNames.filter((m) => (bindings[m] || []).some((b) => b.key === newKey)) : [];
  const crossModeKeyMessage = (() => {
    const count = crossModeKeyMatches.length;
    if (count === 0) return '';
    if (count === 1) return 'Also bound in “' + crossModeKeyMatches[0] + '” mode.';
    const named = crossModeKeyMatches.slice(0, 2).map((m) => '“' + m + '”').join(', ');
    const extra = count > 2 ? ', and ' + (count - 2) + ' more' : '';
    return 'Also bound in ' + named + extra + ' mode' + (count > 1 ? 's' : '') + '.';
  })();

  const update = (id, patch) => setBindings({ ...bindings, [mode]: all.map((b) => (b.id === id ? { ...b, ...patch } : b)) });
  const remove = (id) => setBindings({ ...bindings, [mode]: all.filter((b) => b.id !== id) });
  const override = (b) => setBindings({ ...bindings, [mode]: [...all, { id: 'o' + Date.now(), key: b.key, command: b.command, origin: 'explicit' }] });
  const add = () => {
    if (!newKey || !newCommand.trim()) return;
    const rest = all.filter((b) => !(b.key === newKey && b.origin === 'explicit'));
    setBindings({ ...bindings, [mode]: [...rest, { id: 'n' + Date.now(), key: newKey, command: newCommand, origin: 'explicit' }] });
    setNewKey(''); setNewCommand('');
  };
  // Duplicate to a second key: seed the command, leave the key recorder empty to record.
  const duplicate = (b) => { setNewCommand(b.command); setNewKey(''); };

  const suggestions = commandSuggestions(newCommand);
  const categoriesPresent = CATEGORY_ORDER.filter((cat) => all.some((b) => categoryFor(b.command) === cat));

  return (
    <div className="tab-column">
      <BarStrip edge="top" padded={false}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '9px 14px' }}>
          <div className="mode-pills">
            {modeNames.map((m) => (
              <button key={m} type="button" className={'mode-pill' + (m === mode ? ' on' : '')} onClick={() => setMode(m)}>{m}</button>
            ))}
            <IconButton systemImage="plus.circle" label="New mode…" onClick={() => {}} />
          </div>
          {mode !== 'main' && (
            <div style={{ position: 'relative', flex: '0 0 auto' }}>
              <Button variant="borderless" iconOnly title="Mode actions" onClick={() => setModeMenuOpen((v) => !v)}><Icon sf="ellipsis.circle" size={15} /></Button>
              {modeMenuOpen && (
                <div style={{ position: 'absolute', top: '100%', left: 0, marginTop: 4, zIndex: 10 }}>
                  <MenuPanel width={220} items={[{ label: deleteModeLabel, onClick: () => setModeMenuOpen(false) }]} />
                </div>
              )}
            </div>
          )}
          <div className="filter" style={{ flex: '0 1 300px', minWidth: 160, padding: '5px 10px', gap: 8 }}>
            <Icon sf="magnifyingglass" size={12} style={{ color: 'var(--label-secondary)' }} />
            <TextField variant="plain" placeholder="key or command, e.g. focus left" value={query} onChange={setQuery} style={{ flex: 1, width: 'auto' }} />
            {query && <button className="clear" onClick={() => setQuery('')}><Icon sf="xmark.circle.fill" size={12} /></button>}
          </div>
        </div>
      </BarStrip>

      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6, padding: '7px 14px', borderBottom: 'var(--divider)' }}>
        <Icon sf="info.circle" size={12} style={{ color: 'var(--label-tertiary)', marginTop: 1, flex: '0 0 auto' }} />
        <SettingsHint>{describeMode(mode, bindings)}</SettingsHint>
      </div>

      <div className="form-page" style={{ gap: 'var(--space-16)' }}>
        {rows.length === 0 ? (
          <ContentUnavailable sf={isSearching ? 'magnifyingglass' : 'keyboard'} title={emptyTitle} message={emptyMessage}
            actionTitle={emptyActionTitle} onAction={emptyAction} />
        ) : isSearching ? (
          <React.Fragment>
            <div style={cardShellStyle}>
              <div style={{ padding: '8px 14px 4px' }}><SectionLabel title={'Matches — ' + rows.length} sf="magnifyingglass" /></div>
              {rows.map((b) => (
                <BindingRow key={b.id} b={b} needle={needle} dense onUpdate={update} onRemove={remove} onOverride={override} onDuplicate={duplicate} />
              ))}
            </div>
            {crossModeRowMatches.length > 0 && (
              <div style={cardShellStyle}>
                <div style={{ padding: '8px 14px 4px' }}><SectionLabel title={'In other modes — ' + crossModeRowMatches.length} sf="arrow.triangle.branch" /></div>
                {crossModeRowMatches.map(({ mode: m, row }) => (
                  <CrossModeRow key={m + ':' + row.id} mode={m} row={row} needle={needle} onGo={() => setMode(m)} />
                ))}
              </div>
            )}
          </React.Fragment>
        ) : (
          // Browse-by-category, the default (empty-query) state now that search is primary. One
          // full-width card per category rather than a two-column grid: the 170px recorder width
          // is a fixed control width this design system copies verbatim (see readme.md), and two
          // columns at the 960px floor leave a card only ~360px wide — the recorder alone would
          // eat half of it. Stacked full-width cards keep every row as roomy as the old flat list.
          categoriesPresent.map((cat) => {
            const catRows = all.filter((b) => categoryFor(b.command) === cat);
            return (
              <FormSection key={cat} header={
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <SectionLabel title={cat} sf={CATEGORY_ICONS[cat]} />
                  <Badge tone="muted">{catRows.length}</Badge>
                </div>
              }>
                {catRows.map((b) => (
                  <BindingRow key={b.id} b={b} needle="" onUpdate={update} onRemove={remove} onOverride={override} onDuplicate={duplicate} />
                ))}
              </FormSection>
            );
          })
        )}
      </div>

      <BarStrip padded={false}>
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 10, padding: '12px 14px 0' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <span style={stepLabelStyle}>1 · Shortcut</span>
            <KeyRecorderField notation={newKey} width={170} recording={recording}
              onArm={(v) => { setRecording(v); if (v) setTimeout(() => { setNewKey('esc'); setRecording(false); }, 700); }}
              onClear={() => setNewKey('')} />
          </div>
          <div style={{ height: 22, display: 'flex', alignItems: 'center', flex: '0 0 auto' }}>
            <Icon sf="chevron.right" size={11} style={{ color: 'var(--label-tertiary)' }} />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, flex: 1, minWidth: 0, position: 'relative' }}>
            <span style={stepLabelStyle}>2 · Command</span>
            <TextField mono placeholder="command, e.g. focus left" value={newCommand} onChange={setNewCommand}
              onFocus={() => setSuggestOpen(true)} onBlur={() => setTimeout(() => setSuggestOpen(false), 120)}
              style={{ width: '100%' }} />
            {suggestOpen && suggestions.length > 0 && (
              <div style={{ position: 'absolute', bottom: 'calc(100% + 4px)', left: 0, right: 0, zIndex: 10 }}>
                <MenuPanel width="100%" items={suggestions.map((s) => ({
                  label: s.cmd, suffix: s.cat, mono: true,
                  onClick: () => { setNewCommand(s.cmd); setSuggestOpen(false); },
                }))} />
              </div>
            )}
          </div>
          <Button onClick={add} disabled={!newKey || !newCommand.trim()}>{conflict ? 'Replace' : 'Add'}</Button>
        </div>
        {conflict && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '7px 14px 0' }}>
            <StatusLabel kind="warning">{PrettyKey(conflict.key) + ' is already bound to '}<span className="mono">{conflict.command}</span></StatusLabel>
            {conflict.origin === 'generated' && <Badge help="Generated from mod and workspaces. It is not written in your config file.">generated</Badge>}
            <Button variant="borderless" onClick={() => setQuery(conflict.key)}>Show</Button>
          </div>
        )}
        {newKey && crossModeKeyMatches.length > 0 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '7px 14px 0' }}>
            <StatusLabel kind="neutral">{crossModeKeyMessage}</StatusLabel>
          </div>
        )}
        <SettingsHint style={{ padding: '7px 14px 10px' }}>
          {(generated ? generated + ' generated by mod, ' : '') + explicit + ' written in your config' +
            (generated ? '. Generated bindings have no line to edit — Override copies one here first.' : '') + ' Chain commands with ;.'}
        </SettingsHint>
      </BarStrip>
    </div>
  );
}
Object.assign(window, { KeysTab });
