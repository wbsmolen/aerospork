const { SectionLabel, SettingsHint, CopyButton, Icon, DataTable, ListActionBar, TextField, Select, ContentUnavailable } = window.AeroSporkDesignSystem_078bd7;

function MonitorsTab({ monitors, assignments, setAssignments }) {
  const [selected, setSelected] = React.useState(null);
  const monitorOptions = [
    { value: 'main', label: 'Primary' },
    { value: 'secondary', label: 'Non-main' },
    { separator: true },
    ...monitors.flatMap((m) => [{ value: m.name, label: m.name }, { value: m.uuid, label: m.name + ' — exact display' }]),
  ];
  const update = (id, patch) => setAssignments(assignments.map((a) => (a.id === id ? { ...a, ...patch } : a)));
  const add = () => setAssignments([...assignments, { id: 'a' + Date.now(), workspace: '', monitor: 'main' }]);
  const remove = () => { setAssignments(assignments.filter((a) => a.id !== selected)); setSelected(null); };

  return (
    <div className="tab-column">
      <div className="monitors">
        <SectionLabel title="Connected monitors" sf="display.2" style={{ padding: '14px 16px 8px' }} />
        <div className="monitor-list">
          {monitors.map((m) => (
            <div key={m.id} className="monitor-row">
              <span style={{ color: 'var(--label-secondary)', width: 26, display: 'grid', placeItems: 'center' }}><Icon sf="display" size={17} /></span>
              <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                <span style={{ fontWeight: 'var(--weight-medium)' }}>{m.name}</span>
                <span style={{ fontSize: 'var(--text-callout)', color: 'var(--label-secondary)' }}>{m.resolution}</span>
              </span>
              <span style={{ flex: 1 }} />
              <span className="mono" style={{ fontSize: 'var(--text-caption)', color: 'var(--label-tertiary)' }}>{m.uuid.slice(0, 8)}…</span>
              <CopyButton value={m.uuid} help={'Copy display UUID\n' + m.uuid} />
            </div>
          ))}
        </div>
      </div>
      <div className="hairline" />
      <div className="assignments">
        <SectionLabel title="Workspace assignments" sf="arrow.triangle.branch" style={{ padding: '12px 16px 8px' }} />
        <DataTable selected={selected} onSelect={setSelected}
          columns={[
            { key: 'workspace', title: 'Workspace', width: '140px', render: (r) => <TextField mono value={r.workspace} placeholder="name" onChange={(v) => update(r.id, { workspace: v })} style={{ width: '100%' }} /> },
            { key: 'monitor', title: 'Monitor', render: (r) => <Select value={r.monitor} options={monitorOptions} onChange={(v) => update(r.id, { monitor: v })} width="100%" /> },
          ]}
          rows={assignments}
          emptyState={<ContentUnavailable sf="arrow.triangle.branch" title="No assignments"
            message="Workspaces land wherever they were last used. Add an assignment to pin one to a specific monitor."
            actionTitle="Add assignment" onAction={add} />} />
      </div>
      <ListActionBar addHelp="Pin a workspace to a monitor" removeHelp="Remove the selected assignment"
        onAdd={add} onRemove={selected ? remove : null}
        hint="Hardware fingerprints already in your config are preserved — they just show up here under the monitor's name. A DisplayLink panel reports no vendor or serial, so its UUID is the only thing that pins a workspace to that exact screen." />
    </div>
  );
}
Object.assign(window, { MonitorsTab });
