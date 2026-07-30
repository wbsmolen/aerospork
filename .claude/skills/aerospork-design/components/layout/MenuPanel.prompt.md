Use for the menu bar menu. Keep it a remote control: only what you reach for with the mouse while windows are on screen — jump to a workspace, leave a mode, pause tiling, Settings, Quit. Configuration belongs in Settings.

~~~jsx
<MenuPanel items={[
  { label: '1', mono: true, checked: true, suffix: ' — Built-in' },
  { divider: true },
  { label: 'Pause tiling', shortcut: '⌘E' },
  { label: 'Settings…', shortcut: '⌘,' },
]} />
~~~
