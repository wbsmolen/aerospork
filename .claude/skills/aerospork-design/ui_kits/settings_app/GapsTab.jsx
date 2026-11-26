const { FormSection, SectionLabel, NumberField, GapsPreview, Toggle, StatusLabel } = window.AeroSporkDesignSystem_078bd7;

function GapsTab({ s, set }) {
  const D = window.AS_DATA;
  // Seeded once from the loaded values, not recomputed on every render — otherwise typing a
  // field toward a matching value would make its row disappear mid-edit.
  const [innerLinked, setInnerLinked] = React.useState(() => s.innerH === s.innerV);
  const [outerLinked, setOuterLinked] = React.useState(() =>
    s.outerTop === s.outerBottom && s.outerBottom === s.outerLeft && s.outerLeft === s.outerRight);

  return (
    <div className="tab-column">
      <div className="form-page">
        <FormSection header={<SectionLabel title="Preview" sf="eye" />}
          footer={D.gapsHavePerMonitorOverrides
            ? <StatusLabel kind="neutral">Some gaps have per-monitor rules in Raw TOML. Editing any value below replaces the whole section with flat numbers.</StatusLabel>
            : null}>
          <div style={{ display: 'flex', justifyContent: 'center', padding: '4px 0' }}>
            <GapsPreview width={560} height={156}
              innerHorizontal={s.innerH} innerVertical={s.innerV}
              outerTop={s.outerTop} outerBottom={s.outerBottom} outerLeft={s.outerLeft} outerRight={s.outerRight} />
          </div>
        </FormSection>
        <FormSection header={<SectionLabel title="Between windows" sf="rectangle.split.2x1" />}>
          <Toggle label="Same value for both" checked={innerLinked} onChange={(v) => {
            setInnerLinked(v);
            if (v) set('innerV', s.innerH);
          }} />
          {innerLinked && <NumberField title="Horizontal & vertical" value={s.innerH}
            onChange={(v) => { set('innerH', v); set('innerV', v); }} />}
          {!innerLinked && <NumberField title="Horizontal" value={s.innerH} onChange={(v) => set('innerH', v)} />}
          {!innerLinked && <NumberField title="Vertical" value={s.innerV} onChange={(v) => set('innerV', v)} />}
        </FormSection>
        {/* With overrides, the Preview footer already says where they live. Without, this is the only
            place that says per-monitor gaps exist. A section footer is a SettingsHint (FormSection). */}
        <FormSection header={<SectionLabel title="Around the screen" sf="rectangle.inset.filled" />}
          footer={D.gapsHavePerMonitorOverrides
            ? 'The top gap is measured below the menu bar, so 0 is flush with the usable area.'
            : 'The top gap is measured below the menu bar, so 0 is flush with the usable area. Per-monitor gaps are set in Raw TOML.'}>
          <Toggle label="Same on all sides" checked={outerLinked} onChange={(v) => {
            setOuterLinked(v);
            if (v) { set('outerBottom', s.outerTop); set('outerLeft', s.outerTop); set('outerRight', s.outerTop); }
          }} />
          {outerLinked && <NumberField title="All sides" value={s.outerTop}
            onChange={(v) => { set('outerTop', v); set('outerBottom', v); set('outerLeft', v); set('outerRight', v); }} />}
          {!outerLinked && <NumberField title="Top" value={s.outerTop} onChange={(v) => set('outerTop', v)} />}
          {!outerLinked && <NumberField title="Bottom" value={s.outerBottom} onChange={(v) => set('outerBottom', v)} />}
          {!outerLinked && <NumberField title="Left" value={s.outerLeft} onChange={(v) => set('outerLeft', v)} />}
          {!outerLinked && <NumberField title="Right" value={s.outerRight} onChange={(v) => set('outerRight', v)} />}
        </FormSection>
      </div>
    </div>
  );
}
Object.assign(window, { GapsTab });
