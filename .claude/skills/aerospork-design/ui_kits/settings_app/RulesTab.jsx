const { SectionLabel, DataTable, ListActionBar, ContentUnavailable, FormSection, LabeledContent, TextField, Toggle, Badge } = window.AeroSporkDesignSystem_078bd7;

function summary(r) {
  const parts = [];
  if (r.appId) parts.push(r.appId);
  if (r.appNameRegex) parts.push('name~' + r.appNameRegex);
  if (r.windowTitleRegex) parts.push('title~' + r.windowTitleRegex);
  if (r.workspace) parts.push('ws=' + r.workspace);
  return parts.length ? parts.join(' ') : '(any window)';
}

function RulesTab({ rules, setRules }) {
  const [selected, setSelected] = React.useState('r1');
  const rule = rules.find((r) => r.id === selected);
  const update = (patch) => setRules(rules.map((r) => (r.id === selected ? { ...r, ...patch } : r)));
  const add = () => {
    const id = 'r' + Date.now();
    setRules([...rules, { id, appId: '', appNameRegex: '', windowTitleRegex: '', workspace: '', run: '', checkFurther: false }]);
    setSelected(id);
  };
  const remove = () => { setRules(rules.filter((r) => r.id !== selected)); setSelected(null); };

  return (
    <div className="split">
      <div className="split-list">
        <SectionLabel title="Rules" sf="list.bullet" style={{ padding: '10px 14px' }} />
        <div className="hairline" />
        <DataTable selected={selected} onSelect={setSelected} rows={rules}
          columns={[
            { key: 'match', title: 'Matches', width: '1fr', render: (r) => (
              <span style={{ display: 'flex', gap: 5, alignItems: 'center', minWidth: 0 }}>
                <span className="mono ellipsis">{summary(r)}</span>
                {r.duringStartup && <Badge tone="muted" help="Only applies while AeroSpork is starting up">startup</Badge>}
              </span>) },
            { key: 'run', title: 'Run', width: '150px', render: (r) => <span className="mono ellipsis">{r.run}</span> },
          ]}
          emptyState={<ContentUnavailable sf="macwindow" title="No window rules"
            message="Rules run once, when a window first appears — the usual use is sending an app straight to its workspace."
            actionTitle="Add rule" onAction={add} />} />
        <ListActionBar addHelp="Add a window rule" removeHelp="Remove the selected rule" onAdd={add} onRemove={selected ? remove : null} />
      </div>
      <div className="split-detail">
        {rule ? (
          <div className="form-page">
            <FormSection header={<SectionLabel title="Match when…" sf="line.3.horizontal.decrease.circle" />}
              footer="Empty matchers are left out. A rule with no matchers at all applies to every window. `aerospork list-apps` prints app IDs.">
              <LabeledContent label="App ID"><TextField mono placeholder="com.apple.finder" value={rule.appId} onChange={(v) => update({ appId: v })} width={200} /></LabeledContent>
              <LabeledContent label="App name"><TextField mono placeholder="regex, optional" value={rule.appNameRegex} onChange={(v) => update({ appNameRegex: v })} width={200} /></LabeledContent>
              <LabeledContent label="Window title"><TextField mono placeholder="regex, optional" value={rule.windowTitleRegex} onChange={(v) => update({ windowTitleRegex: v })} width={200} /></LabeledContent>
              <LabeledContent label="Workspace"><TextField mono placeholder="optional" value={rule.workspace} onChange={(v) => update({ workspace: v })} width={200} /></LabeledContent>
            </FormSection>
            <FormSection header={<SectionLabel title="Then run" sf="bolt" />}
              footer="Chain commands with ;. By default a matching rule stops the search.">
              <TextField mono placeholder="move-node-to-workspace 3" value={rule.run} onChange={(v) => update({ run: v })} style={{ width: '100%' }} />
              <Toggle label="Keep checking later rules" checked={rule.checkFurther} onChange={(v) => update({ checkFurther: v })} />
            </FormSection>
          </div>
        ) : (
          <ContentUnavailable sf="sidebar.left" title="No rule selected" message="Pick a rule on the left to edit what it matches and what it does." />
        )}
      </div>
    </div>
  );
}
Object.assign(window, { RulesTab });
