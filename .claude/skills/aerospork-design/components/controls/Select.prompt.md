Use for a list of options that can grow at runtime (connected monitors, modes, keyboard layouts) or where labels are long.

```jsx
<Select value={monitor} onChange={setMonitor} options={[
  { value: 'main', label: 'Primary' },
  { value: 'secondary', label: 'Non-main' },
  { separator: true },
  { value: 'DELL U2720Q', label: 'DELL U2720Q' },
]} />
```

Keep whatever value is already in the config selectable even if the machine no longer reports it — never silently drop an unknown value.
