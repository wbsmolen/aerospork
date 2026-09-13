const { FormSection, SectionLabel, TextField, Button, Icon, IconButton, Toggle, SettingsHint } = window.AeroSporkDesignSystem_078bd7;

function CommandRows({ title, sf, footer, list, onChange, placeholder }) {
  const set = (i, v) => onChange(list.map((c, j) => (j === i ? v : c)));
  const rows = list.length ? list : [null];
  return (
    <FormSection header={<SectionLabel title={title} sf={sf} />} footer={footer}>
      {rows.map((c, i) => (c === null
        ? <span key="empty" style={{ fontSize: 'var(--text-callout)', color: 'var(--label-tertiary)' }}>Nothing here yet. Anything you add runs every time this event fires — exec-and-forget for a shell command, or an aerospork command directly.</span>
        : <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <TextField mono value={c} placeholder={placeholder} onChange={(v) => set(i, v)} style={{ flex: 1 }} />
            <IconButton systemImage="minus.circle" role="destructive"
              label={c.trim() ? 'Remove “' + c + '”' : 'Remove command'}
              onClick={() => onChange(list.filter((_, j) => j !== i))} />
          </div>)) }
      <Button variant="borderless" style={{ color: 'var(--label)' }} onClick={() => onChange([...list, ''])}>
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
        placeholder="exec-and-forget open -a Terminal"
        footer="Runs once, after AeroSpork finishes launching. Multiple commands run in order, top to bottom." />
      <CommandRows title="Focused workspace changed" sf="rectangle.on.rectangle" list={events.workspaceChanged} onChange={set('workspaceChanged')}
        placeholder="exec-and-forget open -a Terminal"
        footer="Every workspace switch, including switches within one monitor. `move-mouse window-lazy-center` here is what makes the pointer follow you." />
      <CommandRows title="Focused monitor changed" sf="display.2" list={events.monitorChanged} onChange={set('monitorChanged')}
        placeholder="move-mouse monitor-lazy-center"
        footer="Only when focus moves to a different monitor." />
      <CommandRows title="Focus changed" sf="scope" list={events.focusChanged} onChange={set('focusChanged')}
        placeholder="move-mouse window-lazy-center"
        footer="Any focus change at all: window, workspace or monitor. Fires the most often — keep it cheap." />
      <FormSection header={<SectionLabel title="Environment for exec commands" sf="terminal" />}
        footer="`exec-and-forget` and every command above run with this environment. `PATH` is the one people usually need. Commands with a window or workspace target also get `AEROSPORK_WINDOW_ID` or `AEROSPORK_WORKSPACE`, and workspace-change commands get `AEROSPORK_FOCUSED_WORKSPACE` and `AEROSPORK_PREV_WORKSPACE`. `aerospork list-exec-env-vars` shows the environment they all start from.">
        <Toggle label="Inherit AeroSpork's environment" checked={inherit} onChange={setInherit} />
        {inherit && <SettingsHint>Every command on this page runs with AeroSpork's full environment, including anything sensitive in it. Turn this off and list only what you need below.</SettingsHint>}
        {env.map((v) => (
          <div key={v.id} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <TextField mono value={v.name} placeholder="NAME" width={150} onChange={(nv) => setEnv(env.map((e) => (e.id === v.id ? { ...e, name: nv } : e)))} />
            <TextField mono value={v.value} placeholder="/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}" style={{ flex: 1 }} onChange={(nv) => setEnv(env.map((e) => (e.id === v.id ? { ...e, value: nv } : e)))} />
            <IconButton systemImage="minus.circle" role="destructive"
              label={v.name.trim() ? 'Remove “' + v.name + '”' : 'Remove variable'}
              onClick={() => setEnv(env.filter((e) => e.id !== v.id))} />
          </div>
        ))}
        <Button variant="borderless" style={{ color: 'var(--label)' }} onClick={() => setEnv([...env, { id: 'v' + Date.now(), name: '', value: '' }])}>
          <Icon sf="plus.circle" size={13} /> Add variable
        </Button>
      </FormSection>
    </div>
  );
}
Object.assign(window, { EventsTab });
