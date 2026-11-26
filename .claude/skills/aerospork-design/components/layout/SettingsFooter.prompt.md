**Removed from the app.** The Gaps pane's caveat, its only use, is now a `SettingsHint` in its last section footer:
a section footer is a `SettingsHint`. This component stays only so older mocks still render. Do not use it in new work.

Was used once per tab, for a caveat about what the GUI cannot express — not for per-control help.

~~~jsx
<SettingsFooter>Per-monitor gaps survive untouched until you change one of these. Use Raw TOML for per-monitor rules.</SettingsFooter>
~~~
