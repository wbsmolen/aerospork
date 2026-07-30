const { BarStrip, SegmentedPicker, TextField, Button, Icon, KeyRecorderField, PrettyKey, Badge, ContentUnavailable, SettingsHint, StatusLabel } = window.AeroSporkDesignSystem_078bd7;

function KeysTab({ bindings, setBindings }) {
  const [mode, setMode] = React.useState('main');
  const [query, setQuery] = React.useState('');
  const [newKey, setNewKey] = React.useState('');
  const [newCommand, setNewCommand] = React.useState('');
  const [recording, setRecording] = React.useState(false);

  const all = bindings[mode] || [];
  const needle = query.trim().toLowerCase();
  const rows = needle ? all.filter((b) => b.key.toLowerCase().includes(needle) || b.command.toLowerCase().includes(needle)) : all;
  const generated = all.filter((b) => b.origin === 'generated').length;
  const explicit = all.length - generated;
  const conflict = newKey ? all.find((b) => b.key === newKey) : null;

  const update = (id, patch) => setBindings({ ...bindings, [mode]: all.map((b) => (b.id === id ? { ...b, ...patch } : b)) });
  const remove = (id) => setBindings({ ...bindings, [mode]: all.filter((b) => b.id !== id) });
  const override = (b) => setBindings({ ...bindings, [mode]: [...all, { id: 'o' + Date.now(), key: b.key, command: b.command, origin: 'explicit' }] });
  const add = () => {
    if (!newKey || !newCommand.trim()) return;
    const rest = all.filter((b) => !(b.key === newKey && b.origin === 'explicit'));
    setBindings({ ...bindings, [mode]: [...rest, { id: 'n' + Date.now(), key: newKey, command: newCommand, origin: 'explicit' }] });
    setNewKey(''); setNewCommand('');
  };

  return (
    <div className="tab-column">
      <BarStrip edge="top" padded={false}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '9px 14px' }}>
          <SegmentedPicker options={['main', 'service']} value={mode} onChange={setMode} />
          <Button variant="borderless" iconOnly title="Mode actions"><Icon sf="ellipsis.circle" size={15} /></Button>
          <span style={{ flex: 1 }} />
          <div className="filter">
            <Icon sf="magnifyingglass" size={12} style={{ color: 'var(--label-secondary)' }} />
            <TextField variant="plain" placeholder="Filter" value={query} onChange={setQuery} width={150} /* capped: minWidth 70, idealWidth 150, maxWidth 150 in the Swift */ />
            {query && <button className="clear" onClick={() => setQuery('')}><Icon sf="xmark.circle.fill" size={12} /></button>}
          </div>
        </div>
      </BarStrip>

      <div className="list">
        {rows.length === 0
          ? <ContentUnavailable sf="magnifyingglass" title="No matches" message={'Nothing in “' + mode + '” matches “' + query + '”.'} />
          : rows.map((b) => (
            <div key={b.id} className="binding-row">
              {b.origin === 'explicit' ? (
                <>
                  <KeyRecorderField notation={b.key} showsClear={false} />
                  <TextField mono value={b.command} onChange={(v) => update(b.id, { command: v })} style={{ flex: 1 }} />
                  <Button variant="borderless" iconOnly title="Remove this binding" onClick={() => remove(b.id)}>
                    <Icon sf="minus.circle" size={14} style={{ color: 'var(--label-secondary)' }} />
                  </Button>
                </>
              ) : (
                <>
                  <span className="mono keycell">{PrettyKey(b.key)}</span>
                  <span className="mono cmdcell">{b.command}</span>
                  <span style={{ flex: 1 }} />
                  <Badge help="Generated from mod and workspaces. It is not written in your config file.">generated</Badge>
                  <Button variant="borderless" onClick={() => override(b)}>Override</Button>
                </>
              )}
            </div>
          ))}
      </div>

      <BarStrip padded={false}>
        <div style={{ display: 'flex', gap: 8, padding: '10px 14px 0' }}>
          <KeyRecorderField notation={newKey} width={170} recording={recording}
            onArm={(v) => { setRecording(v); if (v) setTimeout(() => { setNewKey('alt-shift-d'); setRecording(false); }, 700); }}
            onClear={() => setNewKey('')} />
          <TextField mono placeholder="command, e.g. focus left" value={newCommand} onChange={setNewCommand} style={{ flex: 1 }} />
          <Button onClick={add} disabled={!newKey || !newCommand.trim()}>{conflict ? 'Replace' : 'Add'}</Button>
        </div>
        {conflict && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '7px 14px 0' }}>
            <StatusLabel kind="warning">{PrettyKey(conflict.key) + ' is already bound to '}<span className="mono">{conflict.command}</span></StatusLabel>
            {conflict.origin === 'generated' && <span style={{ fontSize: 'var(--text-callout)', color: 'var(--label-secondary)' }}>(generated)</span>}
            <Button variant="borderless" onClick={() => setQuery(conflict.key)}>Show</Button>
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
