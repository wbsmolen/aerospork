const {
  SectionLabel, PanelHeader, ListActionBar, ContentUnavailable, FormSection, LabeledContent,
  TextField, Toggle, Badge, SegmentedPicker, Button, Icon, AppIcon, appDisplayName,
  SAMPLE_APPS,
} = window.AeroSporkDesignSystem_078bd7;

// `run` is a restricted grammar (parseOnWindowDetected.swift): any number of `layout floating` /
// `layout tiling`, plus at most one `move-node-to-workspace`, which must come last. That's exactly
// "make the window float/tile" + "move it somewhere" — two plain-language controls — so the common
// case never needs the raw command field at all. Anything else (leftover) can't be represented by
// the guided controls, so it flips the section into "custom" mode instead of silently truncating it.
function parseRun(run) {
  const parts = (run || '').split(';').map((s) => s.trim()).filter(Boolean);
  let floatAction = 'none';
  let moveWorkspace = '';
  const leftover = [];
  for (const p of parts) {
    if (p === 'layout floating') floatAction = 'float';
    else if (p === 'layout tiling') floatAction = 'tile';
    else if (p.startsWith('move-node-to-workspace ')) moveWorkspace = p.slice('move-node-to-workspace '.length).trim();
    else leftover.push(p);
  }
  return { floatAction, moveWorkspace, custom: leftover.length > 0 };
}
function composeRun({ floatAction, moveWorkspace }) {
  const parts = [];
  if (floatAction === 'float') parts.push('layout floating');
  else if (floatAction === 'tile') parts.push('layout tiling');
  if (moveWorkspace.trim()) parts.push('move-node-to-workspace ' + moveWorkspace.trim());
  return parts.join(' ; ');
}
// The plain-language line under each app name in the list — "explain the consequence", not the
// command syntax.
function describeAction(rule) {
  const p = parseRun(rule.run);
  if (p.custom) return 'Runs a custom command';
  const bits = [];
  if (p.floatAction === 'float') bits.push('opens as a floating window');
  else if (p.floatAction === 'tile') bits.push('is forced to tile');
  if (p.moveWorkspace) bits.push('moves to workspace “' + p.moveWorkspace + '”');
  if (!bits.length) return 'Doesn’t do anything yet';
  const sentence = bits.join(' and ');
  return sentence.charAt(0).toUpperCase() + sentence.slice(1);
}
function advancedMatcherCount(rule) {
  return [rule.appNameRegex, rule.windowTitleRegex, rule.workspace].filter(Boolean).length +
    (rule.duringStartup !== undefined ? 1 : 0);
}

// Web stand-in for the native application-chooser sheet used by production. Search narrows the
// sample applications, while direct bundle-ID entry remains available for apps that are not
// installed on the machine rendering the mock.
function AppPicker({ title, query, setQuery, onPick, onClose }) {
  const needle = query.trim().toLowerCase();
  const matches = needle
    ? SAMPLE_APPS.filter((a) => a.name.toLowerCase().includes(needle) || a.id.toLowerCase().includes(needle))
    : SAMPLE_APPS;
  const exact = SAMPLE_APPS.some((a) => a.id.toLowerCase() === needle || a.name.toLowerCase() === needle);
  return (
    <div className="app-picker-backdrop"
      onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
      onKeyDown={(e) => { if (e.key === 'Escape') onClose(); }}>
      <div className="app-picker-panel" onMouseDown={(e) => e.stopPropagation()}>
        <div className="app-picker-search">
          <PanelHeader title={title} sf="macwindow.badge.plus" style={{ padding: '0 0 8px' }} />
          <div className="filter" style={{ width: '100%', boxSizing: 'border-box' }}>
            <Icon sf="magnifyingglass" size={12} style={{ color: 'var(--label-secondary)' }} />
            {/* eslint-disable-next-line jsx-a11y/no-autofocus -- this panel IS the modal focus target */}
            <TextField variant="plain" autoFocus placeholder="Search apps, or paste a bundle ID"
              value={query} onChange={setQuery} style={{ flex: 1 }} />
            {query && <button type="button" className="clear" onClick={() => setQuery('')}><Icon sf="xmark.circle.fill" size={12} /></button>}
          </div>
        </div>
        <div className="app-picker-grid">
          {!needle && (
            <button type="button" className="app-picker-tile" onClick={() => onPick('')}>
              <AppIcon appId="" size={40} /><span>Any app</span>
            </button>
          )}
          {matches.map((a) => (
            <button key={a.id} type="button" className="app-picker-tile" onClick={() => onPick(a.id)}>
              <AppIcon appId={a.id} size={40} /><span>{a.name}</span>
            </button>
          ))}
          {needle && matches.length === 0 && (
            <div className="app-picker-empty">
              <Icon sf="magnifyingglass" size={22} weight="light" />
              <span>No sample app matches “{query.trim()}”.</span>
            </div>
          )}
        </div>
        {needle && !exact && (
          <button type="button" className="app-picker-custom" onClick={() => onPick(query.trim())}>
            <AppIcon appId={query.trim()} size={26} />
            Use “{query.trim()}” as a custom app ID
          </button>
        )}
        <div className="app-picker-footer">
          <span style={{ font: 'var(--weight-regular) var(--text-callout)/1.35 var(--font-system)', color: 'var(--label-secondary)' }}>
            <code style={{ font: 'var(--text-callout)/1 var(--font-mono)' }}>aerospork list-apps</code> prints the exact ID for anything running.
          </span>
        </div>
      </div>
    </div>
  );
}

function RulesTab({ rules, setRules }) {
  const [selected, setSelected] = React.useState(rules[0] ? rules[0].id : null);
  const [pickerMode, setPickerMode] = React.useState(null); // null | 'new' | 'change'
  const [pickerQuery, setPickerQuery] = React.useState('');
  const [advancedOpen, setAdvancedOpen] = React.useState(false);

  const rule = rules.find((r) => r.id === selected) || null;

  // Re-derived only when the *selected rule* changes, not on every keystroke — so a rule that
  // already narrows itself with a regex or a startup filter starts open, but expanding it to type
  // in one more matcher doesn't fight the user by trying to snap back closed mid-edit.
  React.useEffect(() => {
    setAdvancedOpen(rule ? advancedMatcherCount(rule) > 0 : false);
  }, [selected]); // eslint-disable-line react-hooks/exhaustive-deps

  const update = (patch) => setRules(rules.map((r) => (r.id === selected ? { ...r, ...patch } : r)));
  const remove = () => { setRules(rules.filter((r) => r.id !== selected)); setSelected(null); };

  const openPicker = (mode) => { setPickerQuery(''); setPickerMode(mode); };
  const pickApp = (appId) => {
    if (pickerMode === 'new') {
      const id = 'r' + Date.now();
      setRules([...rules, {
        id, appId, appNameRegex: '', windowTitleRegex: '', workspace: '',
        run: '', checkFurther: false, duringStartup: undefined,
      }]);
      setSelected(id);
    } else if (pickerMode === 'change') {
      update({ appId });
    }
    setPickerMode(null);
  };

  const parsed = rule ? parseRun(rule.run) : null;
  const advancedCount = rule ? advancedMatcherCount(rule) : 0;

  return (
    <div className="split">
      <div className="split-list">
        <PanelHeader title="All rules" sf="list.bullet" />
        <div className="hairline" />
        {rules.length === 0 ? (
          <ContentUnavailable sf="macwindow" title="No window rules"
            message="Rules run once, when a window first appears: pick an app and AeroSpork remembers what to do with it every time."
            actionTitle="Add rule" onAction={() => openPicker('new')} />
        ) : (
          <div className="rule-list">
            {rules.map((r) => {
              const on = r.id === selected;
              const count = advancedMatcherCount(r);
              return (
                <button key={r.id} type="button" className={'rule-row' + (on ? ' is-selected' : '')} onClick={() => setSelected(r.id)}>
                  <AppIcon appId={r.appId} size={30} />
                  <span className="rule-row-text">
                    <span className="rule-row-name">{appDisplayName(r.appId)}</span>
                    <span className="rule-row-summary">{describeAction(r)}</span>
                  </span>
                  <span className="rule-row-badges">
                    {r.duringStartup === true && <Badge tone="muted" help="Only applies while AeroSpork is starting up">startup</Badge>}
                    {r.duringStartup === false && <Badge tone="muted" help="Only applies after AeroSpork has finished starting up">runtime</Badge>}
                    {count > 0 && <Badge tone="muted" help={count + ' more thing' + (count > 1 ? 's' : '') + ' this rule checks, beyond the app — see Advanced matching.'}>+{count}</Badge>}
                  </span>
                </button>
              );
            })}
          </div>
        )}
        <ListActionBar addHelp="Add a window rule" removeHelp="Remove the selected rule"
          onAdd={() => openPicker('new')} onRemove={selected ? remove : null} />
      </div>
      <div className="split-detail">
        {rule ? (
          <div className="form-page">
            <div className="rule-detail-header">
              <AppIcon appId={rule.appId} size={44} />
              <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <span className="name ellipsis">{appDisplayName(rule.appId)}</span>
                {rule.appId && <span className="bundle-id mono ellipsis">{rule.appId}</span>}
              </div>
              <span style={{ flex: 1 }} />
              <Button variant="bordered" onClick={() => openPicker('change')}>Change app…</Button>
            </div>

            <FormSection header={<SectionLabel title="What happens" sf="bolt" />}
              footer={parsed.custom
                ? 'This does more than the guided controls below can compose — only `layout floating`, `layout tiling`, and one final `move-node-to-workspace`, are supported. Edit the exact text, or start over.'
                : 'Applied once, the moment the window appears. Leaving the workspace blank does not move the window.'}>
              {parsed.custom && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-8)' }}>
                  <Badge tone="muted" help="Written with more detail than the guided controls below can show.">custom</Badge>
                  <Button variant="borderless" onClick={() => update({ run: '' })}>Start over with guided controls</Button>
                </div>
              )}
              {!parsed.custom && (
                <LabeledContent label="Make the window">
                  <SegmentedPicker
                    options={[{ value: 'none', label: 'Leave as is' }, { value: 'float', label: 'Float' }, { value: 'tile', label: 'Tile' }]}
                    value={parsed.floatAction}
                    onChange={(v) => update({ run: composeRun({ floatAction: v, moveWorkspace: parsed.moveWorkspace }) })} />
                </LabeledContent>
              )}
              {!parsed.custom && (
                <LabeledContent label="Move it to workspace">
                  <TextField mono placeholder="don’t move it" value={parsed.moveWorkspace} width={160}
                    onChange={(v) => update({ run: composeRun({ floatAction: parsed.floatAction, moveWorkspace: v }) })} />
                </LabeledContent>
              )}
              <TextField mono placeholder="e.g. move-node-to-workspace 3" value={rule.run}
                onChange={(v) => update({ run: v })} style={{ width: '100%' }} />
              <Toggle label="Keep checking later rules" checked={rule.checkFurther} onChange={(v) => update({ checkFurther: v })}
                help="Off (default): the first matching rule wins. On: AeroSpork keeps evaluating rules after this one, so a later rule can add to what this one already did." />
            </FormSection>

            <section style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
              <button type="button" className="disclosure-header" onClick={() => setAdvancedOpen((v) => !v)} aria-expanded={advancedOpen}>
                <Icon sf="chevron.right" size={10} style={{
                  color: 'var(--label-secondary)', transform: advancedOpen ? 'rotate(90deg)' : 'none',
                  transition: 'transform var(--dur-control) var(--ease-standard)',
                }} />
                <SectionLabel title="Advanced matching" sf="line.3.horizontal.decrease.circle" />
                {!advancedOpen && advancedCount > 0 && <Badge tone="muted">{advancedCount} set</Badge>}
              </button>
              {advancedOpen && (
                <FormSection footer="Empty fields are left out of the match — a rule with only an app picked applies to every window from that app. `aerospork list-apps` prints app IDs.">
                  <LabeledContent label="App name"><TextField mono placeholder="regex, optional" value={rule.appNameRegex} onChange={(v) => update({ appNameRegex: v })} width={200} /></LabeledContent>
                  <LabeledContent label="Window title"><TextField mono placeholder="regex, optional" value={rule.windowTitleRegex} onChange={(v) => update({ windowTitleRegex: v })} width={200} /></LabeledContent>
                  <LabeledContent label="Only on workspace">
                    <TextField mono placeholder="optional" value={rule.workspace} onChange={(v) => update({ workspace: v })} width={200} />
                  </LabeledContent>
                  <LabeledContent label="Startup timing">
                    <SegmentedPicker options={[{ value: 'any', label: 'Any' }, { value: 'true', label: 'Startup' }, { value: 'false', label: 'Runtime' }]}
                      value={rule.duringStartup === true ? 'true' : rule.duringStartup === false ? 'false' : 'any'}
                      onChange={(v) => update({ duringStartup: v === 'any' ? undefined : v === 'true' })} />
                  </LabeledContent>
                </FormSection>
              )}
            </section>
          </div>
        ) : (
          <ContentUnavailable sf="sidebar.left" title="No rule selected"
            message="Pick a rule on the left, or add one, to see what it matches and what it does." />
        )}
      </div>
      {pickerMode && (
        <AppPicker title={pickerMode === 'new' ? 'Add a window rule' : 'Change app'}
          query={pickerQuery} setQuery={setPickerQuery} onPick={pickApp} onClose={() => setPickerMode(null)} />
      )}
    </div>
  );
}
Object.assign(window, { RulesTab });
