const { FormSection, SectionLabel, NumberField, SettingsFooter, GapsPreview } = window.AeroSporkDesignSystem_078bd7;

function GapsTab({ s, set }) {
  return (
    <div className="tab-column">
      <div className="form-page">
        <FormSection>
          <div style={{ display: 'flex', justifyContent: 'center', padding: '4px 0' }}>
            <GapsPreview width={560} height={156}
              innerHorizontal={s.innerH} innerVertical={s.innerV}
              outerTop={s.outerTop} outerBottom={s.outerBottom} outerLeft={s.outerLeft} outerRight={s.outerRight} />
          </div>
        </FormSection>
        <FormSection header={<SectionLabel title="Between windows" sf="rectangle.split.2x1" />}>
          <NumberField title="Horizontal" value={s.innerH} onChange={(v) => set('innerH', v)} />
          <NumberField title="Vertical" value={s.innerV} onChange={(v) => set('innerV', v)} />
        </FormSection>
        <FormSection header={<SectionLabel title="Around the screen" sf="rectangle.inset.filled" />}
          footer="The top gap is measured below the menu bar, so 0 is flush with the usable area.">
          <NumberField title="Top" value={s.outerTop} onChange={(v) => set('outerTop', v)} />
          <NumberField title="Bottom" value={s.outerBottom} onChange={(v) => set('outerBottom', v)} />
          <NumberField title="Left" value={s.outerLeft} onChange={(v) => set('outerLeft', v)} />
          <NumberField title="Right" value={s.outerRight} onChange={(v) => set('outerRight', v)} />
        </FormSection>
      </div>
      <SettingsFooter>Per-monitor gaps, such as a list of values under outer.top, survive untouched until you change one of these — editing any gap rewrites the whole gaps section. Use Raw TOML for per-monitor rules.</SettingsFooter>
    </div>
  );
}
Object.assign(window, { GapsTab });
