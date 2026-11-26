const { SectionLabel, CopyButton, Icon, DataTable, ListActionBar, TextField, Select, ContentUnavailable, Badge, Button, MonitorArrangement, MenuPanel } = window.AeroSporkDesignSystem_078bd7;

function MonitorsTab({ monitors, assignments, setAssignments, workspaces = [] }) {
  const [selected, setSelected] = React.useState(null);
  const [selectedMonitor, setSelectedMonitor] = React.useState(null);
  const [pinMenuOpen, setPinMenuOpen] = React.useState(false);

  // Auto-select the main (or only) monitor: the pin menu is reachable in zero clicks on a
  // laptop, and visible selection is what teaches that the schematic is clickable.
  React.useEffect(() => {
    if (selectedMonitor == null && monitors.length > 0) {
      setSelectedMonitor((monitors.find((m) => m.isMain) || monitors[0]).id);
    }
  }, []);

  // One monitor, one option: the position number ties each entry to the schematic, and the token
  // is uuid-when-available, same as the pin menu. A token some earlier config wrote (main,
  // secondary, a position, a regex) stays selectable as the row's own preserved entry.
  const monitorTokens = new Set(monitors.map((m) => m.uuid || m.name));
  const legacyTokenLabel = (token) => {
    if (token === 'main') return 'Main display';
    if (token === 'secondary') return 'Non-main display';
    if (/^[1-9]\d*$/.test(token)) return 'Position ' + token;
    return token;
  };
  const monitorOptions = (current) => [
    ...monitors.map((m, i) => ({ value: m.uuid || m.name, label: `${i + 1} · ${m.name}` })),
    ...(current && !monitorTokens.has(current)
      ? [{ separator: true }, { value: current, label: legacyTokenLabel(current) }]
      : []),
  ];

  // Mirrors ConfigurationViewModel.monitorRow(forToken:) — the runtime treats a name token as a
  // case-insensitive substring match, so exact equality here would deny pins the runtime
  // resolves. Metacharacter regexes get no chip; the `complex` badge owns those.
  const resolveMonitorId = (token) => {
    if (!token) return null;
    if (token === 'main') return (monitors.find((m) => m.isMain) || monitors[0])?.id ?? null;
    if (token === 'secondary') return monitors.length === 2 ? (monitors.find((m) => !m.isMain)?.id ?? null) : null;
    const seq = Number(token);
    if (Number.isInteger(seq) && String(seq) === token && seq >= 1) return monitors[seq - 1]?.id ?? null;
    const exact = monitors.find((m) => m.uuid === token);
    if (exact) return exact.id;
    const byName = monitors.find((m) => m.name === token || m.name.toLowerCase().includes(token.toLowerCase()));
    return byName ? byName.id : null;
  };

  const update = (id, patch) => setAssignments(assignments.map((a) => (a.id === id ? { ...a, ...patch } : a)));
  const add = (monitor = 'main') => {
    const id = 'a' + Date.now();
    setAssignments([...assignments, { id, workspace: '', monitor }]);
    setSelected(id);
  };
  const pin = (workspace, monitor) => {
    const existing = assignments.find((a) => a.workspace === workspace);
    if (existing) { update(existing.id, { monitor }); setSelected(existing.id); return; }
    const id = 'a' + Date.now();
    setAssignments([...assignments, { id, workspace, monitor }]);
    setSelected(id);
  };
  const remove = () => { setAssignments(assignments.filter((a) => a.id !== selected)); setSelected(null); };
  const toggleMonitor = (id) => setSelectedMonitor((cur) => (cur === id ? null : id));

  const activeMonitor = monitors.find((m) => m.id === selectedMonitor) || null;
  const pinnedHere = activeMonitor ? assignments.filter((a) => resolveMonitorId(a.monitor) === activeMonitor.id) : [];
  const assignedNames = new Set(assignments.map((a) => a.workspace));
  const unpinned = workspaces.filter((w, i) => workspaces.indexOf(w) === i && !assignedNames.has(w));
  const movable = activeMonitor
    ? assignments.filter((a) => a.workspace && resolveMonitorId(a.monitor) !== activeMonitor.id)
    : [];
  const pinToken = activeMonitor ? (activeMonitor.uuid || activeMonitor.name) : null;

  const pinMenuItems = [
    ...unpinned.map((w) => ({ label: w, mono: true, onClick: () => { pin(w, pinToken); setPinMenuOpen(false); } })),
    ...(movable.length > 0
      ? [
          ...(unpinned.length > 0 ? [{ divider: true }] : []),
          { label: 'Pinned elsewhere: move here', disabled: true },
          ...movable.map((a) => ({ label: a.workspace, mono: true, onClick: () => { pin(a.workspace, pinToken); setPinMenuOpen(false); } })),
        ]
      : []),
    { divider: true },
    { label: 'Other…', onClick: () => { add(pinToken); setPinMenuOpen(false); } },
  ];

  return (
    <div className="tab-column">
      <div className="form-page">
        <section className="monitors-section">
          <SectionLabel title="Connected monitors" sf="display.2" style={{ padding: '0 var(--space-2)' }} />
          <div className="card-surface monitors-surface">
            {monitors.length === 0 ? (
              <ContentUnavailable sf="display" title="No monitors detected"
                message="Monitors appear here as soon as macOS reports one. Their UUIDs are what pins a workspace to a physical panel." />
            ) : (
              <>
                <div className="monitor-diagram-wrap">
                  <MonitorArrangement monitors={monitors} selected={selectedMonitor} onSelect={toggleMonitor} height={150} />
                </div>
                <div className="monitor-detail">
                  {activeMonitor ? (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 5, width: '100%' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, position: 'relative' }}>
                        <Icon sf="display" size={13} style={{ color: 'var(--label-tertiary)', flex: '0 0 auto' }} />
                        <strong style={{ color: 'var(--label)', fontWeight: 'var(--weight-medium)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{activeMonitor.name}</strong>
                        <span style={{ color: 'var(--label-secondary)' }}>{activeMonitor.resolution}</span>
                        {activeMonitor.uuid && (
                          <>
                            <span className="mono" style={{ fontSize: 'var(--text-caption)', color: 'var(--label-secondary)' }}>{activeMonitor.uuid.slice(0, 8)}…</span>
                            <CopyButton value={activeMonitor.uuid} help={'Copy monitor UUID\n' + activeMonitor.uuid + '\nA DisplayLink monitor reports no vendor or serial, so its UUID is the only thing that pins a workspace to that exact panel.'} />
                          </>
                        )}
                        <span style={{ flex: 1 }} />
                        <Button onClick={() => setPinMenuOpen((v) => !v)}
                          title="Pins to this display; the assignments table can change how it matches.">Pin a workspace here</Button>
                        {pinMenuOpen && (
                          <MenuPanel items={pinMenuItems} style={{ position: 'absolute', top: '100%', right: 0, zIndex: 30, marginTop: 4 }} />
                        )}
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                        {pinnedHere.length === 0 ? (
                          <span>No workspaces pinned here yet.</span>
                        ) : (
                          <>
                            <span>Pinned here:</span>
                            {pinnedHere.map((a) => (
                              <button key={a.id} type="button" className="workspace-chip" onClick={() => setSelected(a.id)}
                                title={'Select the assignment for ' + (a.workspace ? '“' + a.workspace + '”' : 'this row') + ' in the table below'}>
                                {a.workspace || '(unnamed)'}
                              </button>
                            ))}
                          </>
                        )}
                      </div>
                    </div>
                  ) : (
                    <span>Select a monitor above to see and change what's pinned to it.</span>
                  )}
                </div>
              </>
            )}
          </div>
        </section>

        <section className="assignments-section">
          <SectionLabel title="Workspace assignments" sf="arrow.triangle.branch" style={{ padding: '0 var(--space-2)' }} />
          <div className="card-surface assignments-surface">
            <DataTable selected={selected} onSelect={setSelected}
              columns={[
                // Inert handle column: mirrors the real Table's leading column, which carries no
                // control so a click has somewhere to land for row selection. Decorative only.
                // A plain dot, not a drag handle -- this row can't be reordered, and
                // `line.3.horizontal` would say otherwise. Matches the real Swift's tiny 6pt
                // `circle` glyph: a near-invisible marker, not a visible icon.
                { key: 'handle', title: '', width: '20px', render: () => <span style={{ display: 'inline-block', width: 6, height: 6, borderRadius: '50%', background: 'var(--label-tertiary)' }} /> },
                { key: 'workspace', title: 'Workspace', width: '140px', render: (r) => <TextField mono value={r.workspace} placeholder="name" onChange={(v) => update(r.id, { workspace: v })} style={{ width: '100%' }} /> },
                { key: 'monitor', title: 'Monitor', render: (r) => (
                  <span style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                    <Select value={r.monitor} options={monitorOptions(r.monitor)} onChange={(v) => update(r.id, { monitor: v })} />
                    {r.complex && <Badge help="Written with more detail than this editor can show: a fallback list of monitors, or a fingerprint keyed on more than its UUID. Any structured save in this window is refused until this changes; edit it in Raw TOML.">complex</Badge>}
                  </span>
                ) },
              ]}
              rows={assignments}
              emptyState={<ContentUnavailable sf="arrow.triangle.branch" title="No assignments"
                message="Workspaces land wherever they were last used. Add an assignment to pin one to a specific monitor."
                actionTitle="Add assignment" onAction={() => add()} />} />
            <ListActionBar addHelp="Pin a workspace to a monitor" removeHelp="Remove the selected assignment"
              onAdd={() => add()} onRemove={selected ? remove : null}
              hint="Hardware fingerprints already in your config are preserved, and show up here under the monitor's name. A workspace named here stays available even with no windows on it." />
          </div>
        </section>
      </div>
    </div>
  );
}
Object.assign(window, { MonitorsTab });
