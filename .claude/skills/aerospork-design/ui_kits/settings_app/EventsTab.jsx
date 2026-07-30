const { FormSection, SectionLabel, TextField, Button, Icon } = window.AeroSporkDesignSystem_078bd7;

function CommandRows({ title, sf, footer, list, onChange }) {
  const set = (i, v) => onChange(list.map((c, j) => (j === i ? v : c)));
  const rows = list.length ? list : [null];
  return (
    <FormSection header={<SectionLabel title={title} sf={sf} />} footer={footer}>
      {rows.map((c, i) => (c === null
        ? <span key="empty" style={{ fontSize: 'var(--text-callout)', color: 'var(--label-tertiary)' }}>Nothing here yet. Anything you add runs every time this event fires — exec-and-forget for a shell command, or an aerospork command directly.</span>
        : <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <TextField mono value={c} placeholder="command" onChange={(v) => set(i, v)} style={{ flex: 1 }} />
            <Button variant="borderless" iconOnly title="Remove" onClick={() => onChange(list.filter((_, j) => j !== i))}>
              <Icon sf="minus.circle" size={14} style={{ color: 'var(--label-secondary)' }} />
            </Button>
          </div>)) }
      <Button variant="borderless" onClick={() => onChange([...list, ''])}>
        <Icon sf="plus.circle" size={13} /> Add command
      </Button>
    </FormSection>
  );
}

function EventsTab({ events, setEvents, env, setEnv, inherit, setInherit }) {
  const set = (k) => (v) => setEvents({ ...events, [k]: v });
  return (
    <div className="form-page">
      <CommandRows title="After startup" sf="play.circle" list={events.afterStartup} onChange={set('afterStartup')}
        footer="Runs once, after AeroSpork finishes launching." />
      <CommandRows title="Focused workspace changed" sf="rectangle.on.rectangle" list={events.workspaceChanged} onChange={set('workspaceChanged')}
        footer="Every workspace switch, including switches within one monitor. `move-mouse window-lazy-center` here is what makes the pointer follow you." />
      <CommandRows title="Focused monitor changed" sf="display.2" list={events.monitorChanged} onChange={set('monitorChanged')}
        footer="Only when focus moves to a different monitor." />
      <CommandRows title="Focus changed" sf="scope" list={events.focusChanged} onChange={set('focusChanged')}
        footer="Any focus change at all: window, workspace or monitor. Fires the most often — keep it cheap." />
      <FormSection header={<SectionLabel title="Environment for exec commands" sf="terminal" />}
        footer="`exec-and-forget` and every command above run with this environment. `PATH` is the one people usually need.">
        <label style={{ display: 'flex', gap: 8, alignItems: 'center', fontSize: 'var(--text-default)' }}>
          <input type="checkbox" checked={inherit} onChange={(e) => setInherit(e.target.checked)} />
          Inherit this app's environment
        </label>
        {env.map((v) => (
          <div key={v.id} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <TextField mono value={v.name} placeholder="NAME" width={150} onChange={(nv) => setEnv(env.map((e) => (e.id === v.id ? { ...e, name: nv } : e)))} />
            <TextField mono value={v.value} placeholder="value" style={{ flex: 1 }} onChange={(nv) => setEnv(env.map((e) => (e.id === v.id ? { ...e, value: nv } : e)))} />
            <Button variant="borderless" iconOnly title="Remove" onClick={() => setEnv(env.filter((e) => e.id !== v.id))}>
              <Icon sf="minus.circle" size={14} style={{ color: 'var(--label-secondary)' }} />
            </Button>
          </div>
        ))}
        <Button variant="borderless" onClick={() => setEnv([...env, { id: 'v' + Date.now(), name: '', value: '' }])}>
          <Icon sf="plus.circle" size={13} /> Add variable
        </Button>
      </FormSection>
    </div>
  );
}
Object.assign(window, { EventsTab });
