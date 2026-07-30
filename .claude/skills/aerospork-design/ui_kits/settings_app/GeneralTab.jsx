const { FormSection, SectionLabel, LabeledContent, Toggle, SegmentedPicker, Select, NumberField, CopyButton } = window.AeroSporkDesignSystem_078bd7;

function GeneralTab({ s, set }) {
  return (
    <div className="form-page">
      <FormSection header={<SectionLabel title="Startup & behaviour" sf="power" />}>
        <Toggle label="Start AeroSpork at login" checked={s.startAtLogin} onChange={(v) => set('startAtLogin', v)} />
        <Toggle label="Automatically unhide macOS hidden apps" checked={s.unhide} onChange={(v) => set('unhide', v)}
          help="Undo Command-H automatically, so hidden windows keep tiling" />
        <Toggle label="Move workspaces to assigned monitors on connect" checked={s.autoMove} onChange={(v) => set('autoMove', v)}
          help="Re-applies workspace-to-monitor assignments when the monitor set changes" />
      </FormSection>

      <FormSection header={<SectionLabel title="Appearance" sf="menubar.rectangle" />}
        footer="AeroSpork has no window of its own, so these two icons are the only ways back into Settings without the command line. `aerospork open-settings` opens this window from anywhere.">
        <Toggle label="Show icon in the menu bar" checked={s.menuBarIcon} onChange={(v) => set('menuBarIcon', v)}
          help="The workspace chips, and the menu with workspace switching and Settings in it" />
        <Toggle label="Show icon in the Dock" checked={s.dockIcon} onChange={(v) => set('dockIcon', v)} />
      </FormSection>

      <FormSection header={<SectionLabel title="Layout" sf="rectangle.split.3x1" />}
        footer="Auto gives wide monitors a horizontal split and tall monitors a vertical one. The accordion peek is how much of the window behind stays visible; 0 stacks them exactly.">
        <LabeledContent label="New workspaces use">
          <SegmentedPicker options={[{ value: 'tiles', label: 'Tiles' }, { value: 'accordion', label: 'Accordion' }]}
            value={s.layout} onChange={(v) => set('layout', v)} />
        </LabeledContent>
        <LabeledContent label="Split direction">
          <SegmentedPicker options={[{ value: 'auto', label: 'Auto' }, { value: 'horizontal', label: 'Horizontal' }, { value: 'vertical', label: 'Vertical' }]}
            value={s.orientation} onChange={(v) => set('orientation', v)} />
        </LabeledContent>
        <NumberField title="Accordion peek" value={s.accordionPadding} onChange={(v) => set('accordionPadding', v)} />
      </FormSection>

      <FormSection header={<SectionLabel title="Normalization" sf="wand.and.stars" />}
        footer="Housekeeping applied after every layout change. Turn both off if you want the tree to stay exactly as you built it.">
        <Toggle label="Flatten single-child containers" checked={s.flatten} onChange={(v) => set('flatten', v)} />
        <Toggle label="Alternate orientation for nested containers" checked={s.alternate} onChange={(v) => set('alternate', v)} />
      </FormSection>

      <FormSection header={<SectionLabel title="Keyboard" sf="keyboard" />}
        footer="How the key names in your bindings map to physical keys. `alt-h` means the key labelled H on this layout.">
        <LabeledContent label="Keyboard layout">
          <Select width={160} value={s.keyMapping} onChange={(v) => set('keyMapping', v)}
            options={[{ value: 'qwerty', label: 'QWERTY' }, { value: 'dvorak', label: 'Dvorak' }, { value: 'colemak', label: 'Colemak' }]} />
        </LabeledContent>
      </FormSection>

      <FormSection header={<SectionLabel title="About" sf="info.circle" />}>
        <LabeledContent label="Version">
          <span className="mono">0.4.1 (a91f2c)</span>
          <CopyButton value="AeroSpork v0.4.1 a91f2c8d" help="Copy full version for a bug report" />
        </LabeledContent>
        <LabeledContent label="Config file">
          <span className="mono path">~/.aerospork.toml</span>
          <CopyButton value="/Users/you/.aerospork.toml" help="Copy path" />
        </LabeledContent>
      </FormSection>
    </div>
  );
}
Object.assign(window, { GeneralTab });
