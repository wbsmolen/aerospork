/* @ds-bundle: {"format":4,"namespace":"AeroSporkDesignSystem_078bd7","components":[{"name":"CodeEditor","sourcePath":"components/brand/CodeEditor.jsx"},{"name":"GapsPreview","sourcePath":"components/brand/GapsPreview.jsx"},{"name":"WindowChrome","sourcePath":"components/brand/WindowChrome.jsx"},{"name":"WorkspaceChips","sourcePath":"components/brand/WorkspaceChips.jsx"},{"name":"Button","sourcePath":"components/controls/Button.jsx"},{"name":"CopyButton","sourcePath":"components/controls/CopyButton.jsx"},{"name":"PrettyKey","sourcePath":"components/controls/KeyRecorderField.jsx"},{"name":"KeyRecorderField","sourcePath":"components/controls/KeyRecorderField.jsx"},{"name":"NumberField","sourcePath":"components/controls/NumberField.jsx"},{"name":"SegmentedPicker","sourcePath":"components/controls/SegmentedPicker.jsx"},{"name":"Select","sourcePath":"components/controls/Select.jsx"},{"name":"TextField","sourcePath":"components/controls/TextField.jsx"},{"name":"Toggle","sourcePath":"components/controls/Toggle.jsx"},{"name":"Badge","sourcePath":"components/feedback/Badge.jsx"},{"name":"Banner","sourcePath":"components/feedback/Banner.jsx"},{"name":"ContentUnavailable","sourcePath":"components/feedback/ContentUnavailable.jsx"},{"name":"StatusLabel","sourcePath":"components/feedback/StatusLabel.jsx"},{"name":"SF_TO_LUCIDE","sourcePath":"components/icons/Icon.jsx"},{"name":"ICON_SHAPES","sourcePath":"components/icons/Icon.jsx"},{"name":"Icon","sourcePath":"components/icons/Icon.jsx"},{"name":"BarStrip","sourcePath":"components/layout/BarStrip.jsx"},{"name":"DataTable","sourcePath":"components/layout/DataTable.jsx"},{"name":"FormSection","sourcePath":"components/layout/FormSection.jsx"},{"name":"LabeledContent","sourcePath":"components/layout/LabeledContent.jsx"},{"name":"ListActionBar","sourcePath":"components/layout/ListActionBar.jsx"},{"name":"MenuPanel","sourcePath":"components/layout/MenuPanel.jsx"},{"name":"SectionLabel","sourcePath":"components/layout/SectionLabel.jsx"},{"name":"SettingsFooter","sourcePath":"components/layout/SettingsFooter.jsx"},{"name":"SettingsHint","sourcePath":"components/layout/SettingsHint.jsx"},{"name":"TabBar","sourcePath":"components/layout/TabBar.jsx"}],"sourceHashes":{"components/brand/CodeEditor.jsx":"533a49e91a92","components/brand/GapsPreview.jsx":"87cb37bc5537","components/brand/WindowChrome.jsx":"6dc335057e30","components/brand/WorkspaceChips.jsx":"4173765b5cfe","components/controls/Button.jsx":"24bc808b095e","components/controls/CopyButton.jsx":"648e4540aa27","components/controls/KeyRecorderField.jsx":"483a48c09cf4","components/controls/NumberField.jsx":"6e7b6e8407c9","components/controls/SegmentedPicker.jsx":"2fd45ae04e9f","components/controls/Select.jsx":"b02f6be972aa","components/controls/TextField.jsx":"1cee11e0b9b5","components/controls/Toggle.jsx":"45c2f697e827","components/feedback/Badge.jsx":"ae58a538773b","components/feedback/Banner.jsx":"ba979ef15e20","components/feedback/ContentUnavailable.jsx":"5904028fa356","components/feedback/StatusLabel.jsx":"a2fd1e208954","components/icons/Icon.jsx":"72743b35e185","components/layout/BarStrip.jsx":"c1424c6a9bb1","components/layout/DataTable.jsx":"30a32a636c0e","components/layout/FormSection.jsx":"2bbd30f8edc1","components/layout/LabeledContent.jsx":"a90dccb39353","components/layout/ListActionBar.jsx":"183839398b6d","components/layout/MenuPanel.jsx":"7643a26656de","components/layout/SectionLabel.jsx":"727a9bb3439b","components/layout/SettingsFooter.jsx":"db6e590eb557","components/layout/SettingsHint.jsx":"f3c7437163dd","components/layout/TabBar.jsx":"829940627b04","ui_kits/cli/CliKit.jsx":"31f63b3ab2bc","ui_kits/menu_bar/MenuBarKit.jsx":"e3be52c77c48","ui_kits/settings_app/App.jsx":"f91f02c9693c","ui_kits/settings_app/EventsTab.jsx":"a89c0c784f08","ui_kits/settings_app/GapsTab.jsx":"85919fed77c6","ui_kits/settings_app/GeneralTab.jsx":"1aa5cd4428c4","ui_kits/settings_app/KeysTab.jsx":"8bb618cd4465","ui_kits/settings_app/MonitorsTab.jsx":"4f18e4603d2f","ui_kits/settings_app/RawTomlTab.jsx":"343d00456002","ui_kits/settings_app/RulesTab.jsx":"0de2a95b49e0","ui_kits/settings_app/data.js":"ca3ad4c2d4b1"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.AeroSporkDesignSystem_078bd7 = window.AeroSporkDesignSystem_078bd7 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/brand/CodeEditor.jsx
try { (() => {
/* Editable text that is code, not prose: 12px monospaced, 10/12px container inset, on
   textBackgroundColor. In the app this is an NSTextView with every macOS text substitution
   turned off — smart quotes would turn a valid TOML string into an invalid one. */
function CodeEditor({
  value = '',
  onChange,
  readOnly = false,
  style
}) {
  return /*#__PURE__*/React.createElement("textarea", {
    value: value,
    readOnly: readOnly,
    spellCheck: false,
    onChange: e => onChange && onChange(e.target.value),
    style: {
      flex: 1,
      width: '100%',
      minHeight: 120,
      boxSizing: 'border-box',
      resize: 'none',
      border: 'none',
      outline: 'none',
      background: 'var(--text-bg)',
      color: 'var(--label)',
      padding: '12px 10px',
      fontFamily: 'var(--font-mono)',
      fontSize: 'var(--text-callout)',
      lineHeight: 1.45,
      tabSize: 4,
      ...style
    }
  });
}
Object.assign(__ds_scope, { CodeEditor });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/CodeEditor.jsx", error: String((e && e.message) || e) }); }

// components/brand/GapsPreview.jsx
try { (() => {
/* A screen with three tiles in it. Deliberately schematic: it shows the RELATIONSHIP between
   the six gap numbers, not a to-scale rendering of any display. Gaps are drawn at the ratio
   they would have on a 1600pt-wide monitor. */
function GapsPreview({
  innerHorizontal = 8,
  innerVertical = 8,
  outerTop = 8,
  outerBottom = 8,
  outerLeft = 8,
  outerRight = 8,
  width = 520,
  height = 156,
  nominalWidth = 1600
}) {
  const s = width / nominalWidth;
  const tile = {
    flex: 1,
    borderRadius: 'var(--radius-tile)',
    background: 'var(--tile-fill)',
    boxShadow: 'inset 0 0 0 1px var(--tile-stroke)'
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width,
      height,
      boxSizing: 'border-box',
      borderRadius: 'var(--radius-card)',
      background: 'var(--fill-subtle)',
      boxShadow: 'inset 0 0 0 1px rgba(0,0,0,.14)',
      padding: outerTop * s + 'px ' + outerRight * s + 'px ' + outerBottom * s + 'px ' + outerLeft * s + 'px',
      display: 'flex',
      gap: innerHorizontal * s
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: tile
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      gap: innerVertical * s
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: tile
  }), /*#__PURE__*/React.createElement("div", {
    style: tile
  })));
}
Object.assign(__ds_scope, { GapsPreview });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/GapsPreview.jsx", error: String((e && e.message) || e) }); }

// components/brand/WindowChrome.jsx
try { (() => {
/* A macOS window shell: 10px continuous corners, a translucent title bar with traffic lights,
   and the standard window shadow. Use to frame a screen for docs, README or App Store shots. */
function WindowChrome({
  title,
  width = 880,
  height,
  children,
  style
}) {
  const light = bg => ({
    width: 12,
    height: 12,
    borderRadius: '50%',
    background: bg,
    boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,.12)'
  });
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width,
      height,
      display: 'flex',
      flexDirection: 'column',
      overflow: 'hidden',
      borderRadius: 'var(--radius-window)',
      background: 'var(--window-bg)',
      boxShadow: 'var(--shadow-window)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-8)',
      height: 28,
      padding: '0 var(--space-12)',
      flex: '0 0 auto',
      background: 'var(--bar-bg)',
      backdropFilter: 'blur(var(--bar-blur))',
      WebkitBackdropFilter: 'blur(var(--bar-blur))',
      borderBottom: 'var(--divider)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: light('#ff5f57')
  }), /*#__PURE__*/React.createElement("span", {
    style: light('#febc2e')
  }), /*#__PURE__*/React.createElement("span", {
    style: light('#28c840')
  }), title && /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      textAlign: 'center',
      marginRight: 52,
      fontFamily: 'var(--font-system)',
      fontSize: 'var(--text-default)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--label)'
    }
  }, title)), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      display: 'flex',
      flexDirection: 'column'
    }
  }, children));
}
Object.assign(__ds_scope, { WindowChrome });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/WindowChrome.jsx", error: String((e && e.message) || e) }); }

// components/brand/WorkspaceChips.jsx
try { (() => {
/* MenuBarLabel: which workspace is on each monitor, and which of them has focus. Chips are
   drawn, never composed from N.square.fill SF Symbols — those only exist for 0...50 and single
   capitals, so a workspace named "web" would look nothing like one named "3".
   The menu bar is monochrome and follows the MENU BAR's appearance, not the app's. */
function WorkspaceChips({
  items = [],
  ink = 'light',
  height = 22
}) {
  const color = ink === 'light' ? '#fff' : '#000';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: height * 0.125,
      height
    }
  }, items.map((it, i) => {
    const radius = it.type === 'mode' ? height / 2 : height / 4;
    const common = {
      height,
      display: 'grid',
      placeItems: 'center',
      padding: '0 ' + radius * 0.9 + 'px',
      borderRadius: radius,
      fontFamily: 'var(--font-rounded)',
      fontWeight: 'var(--weight-semibold)',
      fontSize: height * 0.62,
      letterSpacing: '.01em',
      boxSizing: 'border-box'
    };
    return it.active ? /*#__PURE__*/React.createElement("span", {
      key: i,
      style: {
        ...common,
        background: color,
        color: ink === 'light' ? '#000' : '#fff'
      }
    }, it.name) : /*#__PURE__*/React.createElement("span", {
      key: i,
      style: {
        ...common,
        color,
        opacity: 0.75,
        boxShadow: 'inset 0 0 0 ' + Math.max(height * 0.075, 1) + 'px ' + color
      }
    }, it.name);
  }));
}
Object.assign(__ds_scope, { WorkspaceChips });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/WorkspaceChips.jsx", error: String((e && e.message) || e) }); }

// components/controls/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* macOS push button. `bordered` is the default AppKit look; `prominent` is
   .buttonStyle(.borderedProminent) (Apply, the only prominent button in the app);
   `borderless` is .buttonStyle(.borderless), which this app uses for inline text
   actions (Override, Show, Reload) and for icon-only buttons in a bar. */
function Button({
  children,
  variant = 'bordered',
  size = 'regular',
  disabled = false,
  destructive = false,
  iconOnly = false,
  title,
  style,
  onClick,
  ...rest
}) {
  const h = size === 'small' ? 20 : 22;
  const base = {
    font: 'var(--weight-regular) var(--text-default)/1 var(--font-system)',
    height: h,
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 'var(--space-5)',
    padding: iconOnly ? '0 var(--space-5)' : '0 10px',
    borderRadius: 'var(--radius-field)',
    cursor: disabled ? 'default' : 'pointer',
    opacity: disabled ? 0.4 : 1,
    whiteSpace: 'nowrap',
    boxSizing: 'border-box'
  };
  const variants = {
    bordered: {
      background: 'var(--control-bg)',
      color: destructive ? 'var(--sys-red)' : 'var(--label)',
      border: 'var(--field-border)',
      boxShadow: '0 0.5px 1.5px rgba(0,0,0,.14)'
    },
    prominent: {
      background: 'var(--accent)',
      color: '#fff',
      border: '1px solid transparent',
      boxShadow: '0 0.5px 1.5px rgba(0,0,0,.18)'
    },
    borderless: {
      background: 'transparent',
      color: destructive ? 'var(--sys-red)' : 'var(--accent)',
      border: '1px solid transparent',
      padding: iconOnly ? 0 : '0 var(--space-2)'
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    disabled: disabled,
    title: title,
    onClick: onClick,
    style: {
      ...base,
      ...variants[variant],
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Button.jsx", error: String((e && e.message) || e) }); }

// components/controls/SegmentedPicker.jsx
try { (() => {
/* `.pickerStyle(.segmented)` — used for short, mutually exclusive choices with 2-3 options
   (layout, split direction, the Keys mode switcher). */
function SegmentedPicker({
  options = [],
  value,
  onChange,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'inline-flex',
      padding: 2,
      gap: 2,
      borderRadius: 'var(--radius-field)',
      background: 'var(--fill)',
      boxSizing: 'border-box',
      ...style
    }
  }, options.map(o => {
    const v = typeof o === 'string' ? o : o.value;
    const label = typeof o === 'string' ? o : o.label;
    const on = v === value;
    return /*#__PURE__*/React.createElement("button", {
      key: v,
      type: "button",
      onClick: () => onChange && onChange(v),
      style: {
        font: `var(--weight-${on ? 'medium' : 'regular'}) var(--text-default)/1 var(--font-system)`,
        color: 'var(--label)',
        padding: '0 10px',
        height: 18,
        border: 'none',
        borderRadius: 4,
        cursor: 'pointer',
        background: on ? 'var(--control-bg)' : 'transparent',
        boxShadow: on ? '0 0.5px 1.5px rgba(0,0,0,.16)' : 'none'
      }
    }, label);
  }));
}
Object.assign(__ds_scope, { SegmentedPicker });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/SegmentedPicker.jsx", error: String((e && e.message) || e) }); }

// components/controls/Select.jsx
try { (() => {
/* SwiftUI `Picker` in its default (menu) style. Options may include `{ separator: true }`
   to reproduce a `Divider()` inside the menu. */
function Select({
  options = [],
  value,
  onChange,
  width,
  mono = false,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'inline-flex',
      width,
      ...style
    }
  }, /*#__PURE__*/React.createElement("select", {
    value: value,
    onChange: e => onChange && onChange(e.target.value),
    style: {
      appearance: 'none',
      WebkitAppearance: 'none',
      font: `var(--weight-regular) var(--text-default)/1 ${mono ? 'var(--font-mono)' : 'var(--font-system)'}`,
      color: 'var(--label)',
      width: '100%',
      height: 'var(--h-control)',
      padding: '0 22px 0 var(--space-8)',
      boxSizing: 'border-box',
      background: 'var(--control-bg)',
      border: 'var(--field-border)',
      borderRadius: 'var(--radius-field)',
      boxShadow: '0 0.5px 1.5px rgba(0,0,0,.14)',
      outline: 'none'
    }
  }, options.map((o, i) => typeof o === 'object' && o.separator ? /*#__PURE__*/React.createElement("option", {
    key: `s${i}`,
    disabled: true
  }, "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500") : /*#__PURE__*/React.createElement("option", {
    key: (o.value ?? o) + '' + i,
    value: o.value ?? o
  }, o.label ?? o))), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      right: 6,
      top: 0,
      height: '100%',
      display: 'grid',
      placeItems: 'center',
      font: '8px/1 var(--font-system)',
      color: 'var(--label-secondary)',
      pointerEvents: 'none'
    }
  }, "\u25BC"));
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Select.jsx", error: String((e && e.message) || e) }); }

// components/controls/TextField.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* `.textFieldStyle(.roundedBorder)`, plus the `plain` variant used by the Keys filter.
   `mono` is the default for anything that is a command, key notation, path or app id. */
function TextField({
  value = '',
  onChange,
  placeholder,
  mono = false,
  variant = 'rounded',
  align = 'left',
  width,
  disabled = false,
  style,
  ...rest
}) {
  const rounded = variant === 'rounded';
  return /*#__PURE__*/React.createElement("input", _extends({
    value: value,
    placeholder: placeholder,
    disabled: disabled,
    onChange: e => onChange && onChange(e.target.value),
    style: {
      font: `var(--weight-regular) var(--text-default)/1.2 ${mono ? 'var(--font-mono)' : 'var(--font-system)'}`,
      color: 'var(--label)',
      textAlign: align,
      width,
      minWidth: 0,
      height: 'var(--h-control)',
      boxSizing: 'border-box',
      padding: '0 var(--space-6)',
      background: rounded ? 'var(--text-bg)' : 'transparent',
      border: rounded ? 'var(--field-border)' : '1px solid transparent',
      borderRadius: rounded ? 'var(--radius-field)' : 0,
      boxShadow: rounded ? 'inset 0 1px 1px rgba(0,0,0,.04)' : 'none',
      outline: 'none',
      opacity: disabled ? 0.5 : 1,
      ...style
    }
  }, rest));
}
Object.assign(__ds_scope, { TextField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/TextField.jsx", error: String((e && e.message) || e) }); }

// components/controls/Toggle.jsx
try { (() => {
/* SwiftUI `Toggle` in a grouped Form: label on the left, switch on the trailing edge. */
function Toggle({
  label,
  checked = false,
  onChange,
  disabled = false,
  help
}) {
  return /*#__PURE__*/React.createElement("label", {
    title: help,
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 'var(--space-12)',
      font: 'var(--weight-regular) var(--text-default)/1.2 var(--font-system)',
      color: 'var(--label)',
      opacity: disabled ? 0.4 : 1,
      cursor: disabled ? 'default' : 'pointer'
    }
  }, /*#__PURE__*/React.createElement("span", null, label), /*#__PURE__*/React.createElement("span", {
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      width: 38,
      height: 22,
      flex: '0 0 auto',
      borderRadius: 'var(--radius-pill)',
      background: checked ? 'var(--accent)' : 'var(--label-quaternary)',
      boxShadow: checked ? 'none' : 'inset 0 0 0 0.5px rgba(0,0,0,.06)',
      position: 'relative',
      transition: 'background var(--dur-control) var(--ease-standard)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 1.5,
      left: checked ? 18 : 1.5,
      width: 19,
      height: 19,
      borderRadius: '50%',
      background: '#fff',
      boxShadow: '0 0.5px 2px rgba(0,0,0,.28)',
      transition: 'left var(--dur-control) var(--ease-standard)'
    }
  })));
}
Object.assign(__ds_scope, { Toggle });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Toggle.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Badge.jsx
try { (() => {
/* Capsule badge marking where a row came from. In AeroSpork it names the one layer a binding
   can arrive from that has no line anywhere in the config file: "generated". */
function Badge({
  children,
  tone = 'default',
  help
}) {
  return /*#__PURE__*/React.createElement("span", {
    title: help,
    style: {
      display: 'inline-block',
      padding: '2px var(--space-6)',
      borderRadius: 'var(--radius-pill)',
      background: tone === 'muted' ? 'rgba(142,142,147,.2)' : 'var(--fill-strong)',
      color: 'var(--label-secondary)',
      fontFamily: 'var(--font-system)',
      fontSize: 'var(--text-caption2)',
      lineHeight: 1.3,
      whiteSpace: 'nowrap'
    }
  }, children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Badge.jsx", error: String((e && e.message) || e) }); }

// components/icons/Icon.jsx
try { (() => {
/* AeroSpork is a native app: every glyph in it is an SF Symbol, which cannot be redistributed
   with a web design system. This maps the symbol names the app actually uses onto the closest
   Lucide icon (2px stroke, rounded caps — the nearest match to SF Symbols' Regular weight).
   The shapes are inlined (also in assets/icons/*.svg) rather than loaded from a CDN, so a mock
   works offline and in renderers that refuse cross-origin mask images.
   SUBSTITUTION: shapes are close but not identical. In production Swift, use the SF Symbol name.
   Lucide is ISC licensed. */
const SF_TO_LUCIDE = {
  'gearshape': 'settings',
  'rectangle.split.3x3': 'layout-grid',
  'keyboard': 'keyboard',
  'display.2': 'monitor',
  'display': 'monitor',
  'bolt': 'zap',
  'macwindow.badge.plus': 'app-window',
  'macwindow': 'app-window',
  'doc.plaintext': 'file-text',
  'plus': 'plus',
  'minus': 'minus',
  'minus.circle': 'circle-minus',
  'plus.circle': 'circle-plus',
  'xmark': 'x',
  'xmark.circle.fill': 'circle-x',
  'magnifyingglass': 'search',
  'doc.on.doc': 'copy',
  'checkmark': 'check',
  'checkmark.circle': 'circle-check',
  'equal.circle': 'circle-equal',
  'exclamationmark.triangle.fill': 'triangle-alert',
  'exclamationmark.octagon.fill': 'octagon-alert',
  'arrow.triangle.branch': 'git-branch',
  'list.bullet': 'list',
  'sidebar.left': 'panel-left',
  'power': 'power',
  'menubar.rectangle': 'panel-top',
  'rectangle.split.3x1': 'columns-3',
  'rectangle.split.2x1': 'columns-2',
  'rectangle.inset.filled': 'square',
  'wand.and.stars': 'wand-sparkles',
  'info.circle': 'info',
  'play.circle': 'circle-play',
  'rectangle.on.rectangle': 'layers',
  'scope': 'crosshair',
  'terminal': 'terminal',
  'ellipsis.circle': 'ellipsis',
  'line.3.horizontal.decrease.circle': 'filter',
  'square.grid.2x2': 'grid-2x2',
  'pause.circle.fill': 'circle-pause',
  'chevron.down': 'chevron-down',
  'chevron.right': 'chevron-right',
  'trash': 'trash-2'
};

/** Glyph geometry, keyed by Lucide name. Stroke is currentColor, so tint by setting `color`. */
const ICON_SHAPES = {
  "settings": "<path d=\"M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915\" /><circle cx=\"12\" cy=\"12\" r=\"3\" />",
  "layout-grid": "<rect width=\"7\" height=\"7\" x=\"3\" y=\"3\" rx=\"1\" /><rect width=\"7\" height=\"7\" x=\"14\" y=\"3\" rx=\"1\" /><rect width=\"7\" height=\"7\" x=\"14\" y=\"14\" rx=\"1\" /><rect width=\"7\" height=\"7\" x=\"3\" y=\"14\" rx=\"1\" />",
  "keyboard": "<path d=\"M10 8h.01\" /><path d=\"M12 12h.01\" /><path d=\"M14 8h.01\" /><path d=\"M16 12h.01\" /><path d=\"M18 8h.01\" /><path d=\"M6 8h.01\" /><path d=\"M7 16h10\" /><path d=\"M8 12h.01\" /><rect width=\"20\" height=\"16\" x=\"2\" y=\"4\" rx=\"2\" />",
  "monitor": "<rect width=\"20\" height=\"14\" x=\"2\" y=\"3\" rx=\"2\" /><line x1=\"8\" x2=\"16\" y1=\"21\" y2=\"21\" /><line x1=\"12\" x2=\"12\" y1=\"17\" y2=\"21\" />",
  "plus": "<path d=\"M5 12h14\" /><path d=\"M12 5v14\" />",
  "zap": "<path d=\"M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z\" />",
  "app-window": "<rect x=\"2\" y=\"4\" width=\"20\" height=\"16\" rx=\"2\" /><path d=\"M10 4v4\" /><path d=\"M2 8h20\" /><path d=\"M6 4v4\" />",
  "file-text": "<path d=\"M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z\" /><path d=\"M14 2v4a2 2 0 0 0 2 2h4\" /><path d=\"M10 9H8\" /><path d=\"M16 13H8\" /><path d=\"M16 17H8\" />",
  "minus": "<path d=\"M5 12h14\" />",
  "circle-plus": "<circle cx=\"12\" cy=\"12\" r=\"10\" /><path d=\"M8 12h8\" /><path d=\"M12 8v8\" />",
  "circle-minus": "<circle cx=\"12\" cy=\"12\" r=\"10\" /><path d=\"M8 12h8\" />",
  "circle-x": "<circle cx=\"12\" cy=\"12\" r=\"10\" /><path d=\"m15 9-6 6\" /><path d=\"m9 9 6 6\" />",
  "copy": "<rect width=\"14\" height=\"14\" x=\"8\" y=\"8\" rx=\"2\" ry=\"2\" /><path d=\"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2\" />",
  "circle-equal": "<path d=\"M7 10h10\" /><path d=\"M7 14h10\" /><circle cx=\"12\" cy=\"12\" r=\"10\" />",
  "git-branch": "<line x1=\"6\" x2=\"6\" y1=\"3\" y2=\"15\" /><circle cx=\"18\" cy=\"6\" r=\"3\" /><circle cx=\"6\" cy=\"18\" r=\"3\" /><path d=\"M18 9a9 9 0 0 1-9 9\" />",
  "list": "<path d=\"M3 5h.01\" /><path d=\"M3 12h.01\" /><path d=\"M3 19h.01\" /><path d=\"M8 5h13\" /><path d=\"M8 12h13\" /><path d=\"M8 19h13\" />",
  "power": "<path d=\"M12 2v10\" /><path d=\"M18.4 6.6a9 9 0 1 1-12.77.04\" />",
  "panel-top": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /><path d=\"M3 9h18\" />",
  "columns-3": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /><path d=\"M9 3v18\" /><path d=\"M15 3v18\" />",
  "columns-2": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /><path d=\"M12 3v18\" />",
  "square": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" />",
  "wand-sparkles": "<path d=\"m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72\" /><path d=\"m14 7 3 3\" /><path d=\"M5 6v4\" /><path d=\"M19 14v4\" /><path d=\"M10 2v2\" /><path d=\"M7 8H3\" /><path d=\"M21 16h-4\" /><path d=\"M11 3H9\" />",
  "info": "<circle cx=\"12\" cy=\"12\" r=\"10\" /><path d=\"M12 16v-4\" /><path d=\"M12 8h.01\" />",
  "layers": "<path d=\"M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z\" /><path d=\"M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12\" /><path d=\"M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17\" />",
  "circle-play": "<path d=\"M9 9.003a1 1 0 0 1 1.517-.859l4.997 2.997a1 1 0 0 1 0 1.718l-4.997 2.997A1 1 0 0 1 9 14.996z\" /><circle cx=\"12\" cy=\"12\" r=\"10\" />",
  "crosshair": "<circle cx=\"12\" cy=\"12\" r=\"10\" /><line x1=\"22\" x2=\"18\" y1=\"12\" y2=\"12\" /><line x1=\"6\" x2=\"2\" y1=\"12\" y2=\"12\" /><line x1=\"12\" x2=\"12\" y1=\"6\" y2=\"2\" /><line x1=\"12\" x2=\"12\" y1=\"22\" y2=\"18\" />",
  "terminal": "<path d=\"M12 19h8\" /><path d=\"m4 17 6-6-6-6\" />",
  "filter": "<path d=\"M10 20a1 1 0 0 0 .553.895l2 1A1 1 0 0 0 14 21v-7a2 2 0 0 1 .517-1.341L21.74 4.67A1 1 0 0 0 21 3H3a1 1 0 0 0-.742 1.67l7.225 7.989A2 2 0 0 1 10 14z\" />",
  "ellipsis": "<circle cx=\"12\" cy=\"12\" r=\"1\" /><circle cx=\"19\" cy=\"12\" r=\"1\" /><circle cx=\"5\" cy=\"12\" r=\"1\" />",
  "search": "<path d=\"m21 21-4.34-4.34\" /><circle cx=\"11\" cy=\"11\" r=\"8\" />",
  "circle-check": "<circle cx=\"12\" cy=\"12\" r=\"10\" /><path d=\"m9 12 2 2 4-4\" />",
  "chevron-down": "<path d=\"m6 9 6 6 6-6\" />",
  "check": "<path d=\"M20 6 9 17l-5-5\" />",
  "x": "<path d=\"M18 6 6 18\" /><path d=\"m6 6 12 12\" />",
  "triangle-alert": "<path d=\"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3\" /><path d=\"M12 9v4\" /><path d=\"M12 17h.01\" />",
  "octagon-alert": "<path d=\"M12 16h.01\" /><path d=\"M12 8v4\" /><path d=\"M15.312 2a2 2 0 0 1 1.414.586l4.688 4.688A2 2 0 0 1 22 8.688v6.624a2 2 0 0 1-.586 1.414l-4.688 4.688a2 2 0 0 1-1.414.586H8.688a2 2 0 0 1-1.414-.586l-4.688-4.688A2 2 0 0 1 2 15.312V8.688a2 2 0 0 1 .586-1.414l4.688-4.688A2 2 0 0 1 8.688 2z\" />",
  "trash-2": "<path d=\"M10 11v6\" /><path d=\"M14 11v6\" /><path d=\"M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6\" /><path d=\"M3 6h18\" /><path d=\"M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2\" />",
  "chevron-right": "<path d=\"m9 18 6-6-6-6\" />",
  "circle-pause": "<circle cx=\"12\" cy=\"12\" r=\"10\" /><line x1=\"10\" x2=\"10\" y1=\"15\" y2=\"9\" /><line x1=\"14\" x2=\"14\" y1=\"15\" y2=\"9\" />",
  "grid-2x2": "<path d=\"M12 3v18\" /><path d=\"M3 12h18\" /><rect x=\"3\" y=\"3\" width=\"18\" height=\"18\" rx=\"2\" />",
  "panel-left": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /><path d=\"M9 3v18\" />"
};
function Icon({
  sf,
  name,
  size = 14,
  weight = 'regular',
  style
}) {
  const shape = ICON_SHAPES[name || SF_TO_LUCIDE[sf]] || ICON_SHAPES.square;
  return /*#__PURE__*/React.createElement("svg", {
    "aria-hidden": "true",
    viewBox: "0 0 24 24",
    width: size,
    height: size,
    fill: "none",
    stroke: "currentColor",
    strokeWidth: weight === 'light' ? 1.5 : 2,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    style: {
      display: 'inline-block',
      flex: '0 0 auto',
      verticalAlign: 'middle',
      ...style
    },
    dangerouslySetInnerHTML: {
      __html: shape
    }
  });
}
Object.assign(__ds_scope, { SF_TO_LUCIDE, ICON_SHAPES, Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/icons/Icon.jsx", error: String((e && e.message) || e) }); }

// components/controls/CopyButton.jsx
try { (() => {
/* Borderless "copy this string" button. Flips to a checkmark for 1.4s, which is the entire
   feedback — no toast, no alert. */
function CopyButton({
  value = '',
  help = 'Copy to clipboard'
}) {
  const [copied, setCopied] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    title: help,
    "aria-label": copied ? 'Copied' : help,
    onClick: () => {
      if (navigator.clipboard) navigator.clipboard.writeText(value);
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    },
    style: {
      width: 18,
      height: 18,
      display: 'grid',
      placeItems: 'center',
      padding: 0,
      background: 'transparent',
      border: 'none',
      cursor: 'pointer',
      color: copied ? 'var(--sys-green)' : 'var(--label-secondary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: copied ? 'checkmark' : 'doc.on.doc',
    size: 13
  }));
}
Object.assign(__ds_scope, { CopyButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/CopyButton.jsx", error: String((e && e.message) || e) }); }

// components/controls/KeyRecorderField.jsx
try { (() => {
const GLYPHS = {
  ctrl: '⌃',
  alt: '⌥',
  shift: '⇧',
  cmd: '⌘'
};

/** aerospork notation ("alt-shift-h") rendered with real modifier glyphs ("⌥⇧h").
    Capitalized because only capitalized exports reach the design-system namespace. */
function PrettyKey(notation = '') {
  const parts = notation.split('-');
  if (parts.length < 2) return notation;
  const key = parts.pop();
  return parts.map(p => GLYPHS[p] || p + '-').join('') + key;
}

/* Click, then press a shortcut. Armed state is accent-tinted with a 2px accent border —
   the same treatment the hand-drawn NSView uses. */
function KeyRecorderField({
  notation = '',
  recording = false,
  onArm,
  onClear,
  showsClear = true,
  width = 150
}) {
  const label = notation ? PrettyKey(notation) : recording ? 'Press a shortcut…' : 'Click to record';
  return /*#__PURE__*/React.createElement("div", {
    onClick: () => onArm && onArm(!recording),
    style: {
      position: 'relative',
      width,
      height: 'var(--h-control)',
      boxSizing: 'border-box',
      display: 'flex',
      alignItems: 'center',
      padding: '0 var(--space-8)',
      cursor: 'pointer',
      borderRadius: 'var(--radius-recorder)',
      background: recording ? 'var(--recorder-armed-fill)' : 'var(--text-bg)',
      boxShadow: recording ? 'inset 0 0 0 var(--border-recorder-armed) var(--accent)' : 'inset 0 0 0 var(--border-hairline) var(--separator)',
      font: 'var(--weight-regular) var(--text-default)/1 var(--font-mono)',
      color: notation ? 'var(--label)' : 'var(--label-placeholder)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      overflow: 'hidden',
      whiteSpace: 'nowrap'
    }
  }, label), showsClear && notation && /*#__PURE__*/React.createElement("button", {
    type: "button",
    title: "Clear",
    onClick: e => {
      e.stopPropagation();
      onClear && onClear();
    },
    style: {
      position: 'absolute',
      right: 4,
      top: 0,
      height: '100%',
      display: 'grid',
      placeItems: 'center',
      background: 'none',
      border: 'none',
      padding: 0,
      cursor: 'pointer',
      color: 'var(--label-tertiary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: "xmark.circle.fill",
    size: 12
  })));
}
Object.assign(__ds_scope, { PrettyKey, KeyRecorderField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/KeyRecorderField.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Banner.jsx
try { (() => {
/* The persistent banner at the top of the settings window. The startup error dialog is
   modal-and-gone; without this, an app running the bundled default keymap looks exactly like
   one running the user's config. */
function Banner({
  kind = 'warning',
  children
}) {
  const map = {
    error: {
      sf: 'exclamationmark.octagon.fill',
      color: 'var(--sys-red)',
      bg: 'var(--banner-error-bg)'
    },
    warning: {
      sf: 'exclamationmark.triangle.fill',
      color: 'var(--sys-orange)',
      bg: 'var(--banner-warning-bg)'
    }
  };
  const s = map[kind] || map.warning;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-start',
      gap: 'var(--space-9)',
      padding: 'var(--space-11) var(--space-14)',
      background: s.bg,
      borderBottom: 'var(--divider)',
      fontFamily: 'var(--font-system)',
      fontSize: 'var(--text-callout)',
      lineHeight: 'var(--leading-prose)',
      color: 'var(--label)',
      whiteSpace: 'pre-line',
      textWrap: 'pretty'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: s.color,
      display: 'grid',
      placeItems: 'center',
      height: 17
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: s.sf,
    size: 15
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, children));
}
Object.assign(__ds_scope, { Banner });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Banner.jsx", error: String((e && e.message) || e) }); }

// components/feedback/ContentUnavailable.jsx
try { (() => {
/* The one empty state in the app: a 34px light glyph, a headline, one sentence of prose that
   says what the thing is for, and optionally the action that creates the first one. */
function ContentUnavailable({
  sf,
  title,
  message,
  actionTitle,
  onAction
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 'var(--space-8)',
      padding: 'var(--pad-empty-state)',
      width: '100%',
      height: '100%',
      textAlign: 'center',
      fontFamily: 'var(--font-system)',
      boxSizing: 'border-box'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--label-tertiary)',
      marginBottom: 'var(--space-2)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: sf,
    size: 34,
    weight: "light"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 'var(--text-headline)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--label)'
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 'var(--text-callout)',
      color: 'var(--label-secondary)',
      maxWidth: 320,
      lineHeight: 'var(--leading-prose)',
      textWrap: 'pretty'
    }
  }, message), actionTitle && /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 'var(--space-4)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Button, {
    onClick: onAction
  }, actionTitle)));
}
Object.assign(__ds_scope, { ContentUnavailable });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/ContentUnavailable.jsx", error: String((e && e.message) || e) }); }

// components/feedback/StatusLabel.jsx
try { (() => {
/* Label(text, systemImage:) with a semantic tint: the inline validity readout of a pane. */
function StatusLabel({
  kind = 'neutral',
  sf,
  children,
  style
}) {
  const map = {
    ok: {
      color: 'var(--sys-green)',
      sf: 'checkmark.circle'
    },
    error: {
      color: 'var(--sys-red)',
      sf: 'exclamationmark.triangle.fill'
    },
    warning: {
      color: 'var(--sys-orange)',
      sf: 'exclamationmark.triangle.fill'
    },
    neutral: {
      color: 'var(--label-secondary)',
      sf: 'equal.circle'
    }
  };
  const s = map[kind] || map.neutral;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 'var(--space-5)',
      color: s.color,
      fontFamily: 'var(--font-system)',
      fontSize: 'var(--text-callout)',
      lineHeight: 1.3,
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: sf || s.sf,
    size: 12
  }), children);
}
Object.assign(__ds_scope, { StatusLabel });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/StatusLabel.jsx", error: String((e && e.message) || e) }); }

// components/layout/BarStrip.jsx
try { (() => {
/* .background(.bar) — the translucent chrome strip macOS puts above or below content.
   Always paired with a hairline divider on the content side. */
function BarStrip({
  children,
  edge = 'bottom',
  padded = true,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--bar-bg)',
      backdropFilter: 'blur(var(--bar-blur))',
      WebkitBackdropFilter: 'blur(var(--bar-blur))',
      borderTop: edge === 'bottom' ? 'var(--divider)' : 'none',
      borderBottom: edge === 'top' ? 'var(--divider)' : 'none',
      padding: padded ? 'var(--pad-bar-y) var(--pad-bar-x)' : 0,
      boxSizing: 'border-box',
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { BarStrip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/BarStrip.jsx", error: String((e && e.message) || e) }); }

// components/layout/DataTable.jsx
try { (() => {
/* Table(...).tableStyle(.inset): a header row of 11px secondary titles, hairline row
   separators, and a full-width accent selection. */
function DataTable({
  columns = [],
  rows = [],
  selected,
  onSelect,
  emptyState
}) {
  if (!rows.length && emptyState) return emptyState;
  const grid = columns.map(c => c.width || '1fr').join(' ');
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflow: 'auto',
      background: 'var(--control-bg)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: grid,
      gap: 'var(--space-8)',
      padding: '4px var(--space-12)',
      borderBottom: 'var(--divider)',
      font: 'var(--weight-regular) var(--text-subheadline)/1.2 var(--font-system)',
      color: 'var(--label-secondary)',
      position: 'sticky',
      top: 0,
      background: 'var(--control-bg)'
    }
  }, columns.map(c => /*#__PURE__*/React.createElement("span", {
    key: c.key
  }, c.title))), rows.map(r => {
    const on = selected === r.id;
    return /*#__PURE__*/React.createElement("div", {
      key: r.id,
      onClick: () => onSelect && onSelect(r.id),
      style: {
        display: 'grid',
        gridTemplateColumns: grid,
        gap: 'var(--space-8)',
        alignItems: 'center',
        padding: '3px var(--space-12)',
        borderBottom: 'var(--divider)',
        cursor: 'default',
        background: on ? 'var(--selection)' : 'transparent',
        color: on ? 'var(--selection-fg)' : 'var(--label)'
      }
    }, columns.map(c => /*#__PURE__*/React.createElement("div", {
      key: c.key,
      style: {
        minWidth: 0
      }
    }, c.render ? c.render(r, on) : r[c.key])));
  }));
}
Object.assign(__ds_scope, { DataTable });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/DataTable.jsx", error: String((e && e.message) || e) }); }

// components/layout/LabeledContent.jsx
try { (() => {
/* SwiftUI LabeledContent: label on the leading edge, control trailing, one row of a Form. */
function LabeledContent({
  label,
  children,
  align = 'center'
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: align,
      justifyContent: 'space-between',
      gap: 'var(--space-12)',
      minHeight: 'var(--h-control)',
      font: 'var(--weight-regular) var(--text-default)/1.2 var(--font-system)',
      color: 'var(--label)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 1 auto'
    }
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-6)',
      minWidth: 0
    }
  }, children));
}
Object.assign(__ds_scope, { LabeledContent });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/LabeledContent.jsx", error: String((e && e.message) || e) }); }

// components/controls/NumberField.jsx
try { (() => {
/* `NumberField` from SettingsChrome.swift: a typable number, a unit label and a stepper.
   Clamped, because a text field can produce anything and an out-of-range value would only
   surface later as a config validation error. */
function NumberField({
  title,
  value = 0,
  unit = 'pt',
  min = 0,
  max = 500,
  onChange
}) {
  const set = n => onChange && onChange(Math.min(Math.max(n, min), max));
  const stepBtn = {
    width: 15,
    height: 11,
    display: 'grid',
    placeItems: 'center',
    cursor: 'pointer',
    background: 'var(--control-bg)',
    border: 'var(--field-border)',
    font: '7px/1 var(--font-system)',
    color: 'var(--label-secondary)',
    padding: 0
  };
  return /*#__PURE__*/React.createElement(__ds_scope.LabeledContent, {
    label: title
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-6)'
    }
  }, /*#__PURE__*/React.createElement("input", {
    value: value,
    inputMode: "numeric",
    onChange: e => set(parseInt(e.target.value || '0', 10) || 0),
    style: {
      font: 'var(--weight-regular) var(--text-default)/1.2 var(--font-system)',
      color: 'var(--label)',
      textAlign: 'right',
      width: 'var(--w-number-field)',
      height: 'var(--h-control)',
      boxSizing: 'border-box',
      padding: '0 var(--space-6)',
      background: 'var(--text-bg)',
      border: 'var(--field-border)',
      borderRadius: 'var(--radius-field)',
      outline: 'none'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--text-callout)/1 var(--font-system)',
      color: 'var(--label-secondary)'
    }
  }, unit), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'grid',
      borderRadius: 4,
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    style: {
      ...stepBtn,
      borderRadius: '4px 4px 0 0'
    },
    onClick: () => set(value + 1)
  }, "\u25B2"), /*#__PURE__*/React.createElement("button", {
    type: "button",
    style: {
      ...stepBtn,
      borderTop: 'none',
      borderRadius: '0 0 4px 4px'
    },
    onClick: () => set(value - 1)
  }, "\u25BC"))));
}
Object.assign(__ds_scope, { NumberField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/NumberField.jsx", error: String((e && e.message) || e) }); }

// components/layout/MenuPanel.jsx
try { (() => {
/* An AppKit menu: vibrant panel, 4px inset rows, checkmark column, hairline dividers and
   right-aligned key equivalents. Used by MenuBarExtra and by pull-down menus. */
function MenuPanel({
  items = [],
  width = 236,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width,
      padding: 'var(--space-4)',
      borderRadius: 'var(--radius-recorder)',
      background: 'var(--bar-bg)',
      backdropFilter: 'blur(30px)',
      WebkitBackdropFilter: 'blur(30px)',
      boxShadow: 'var(--shadow-menu)',
      fontFamily: 'var(--font-system)',
      fontSize: 'var(--text-default)',
      ...style
    }
  }, items.map((it, i) => {
    if (it.divider) return /*#__PURE__*/React.createElement("div", {
      key: i,
      style: {
        height: 1,
        background: 'var(--separator)',
        margin: '5px var(--space-8)'
      }
    });
    return /*#__PURE__*/React.createElement("div", {
      key: i,
      onClick: it.onClick,
      title: it.help,
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-6)',
        padding: '3px var(--space-8)',
        borderRadius: 4,
        color: it.disabled ? 'var(--label-tertiary)' : 'var(--label)',
        fontFamily: it.mono ? 'var(--font-mono)' : 'inherit',
        lineHeight: 1.5
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        width: 13,
        flex: '0 0 auto'
      }
    }, it.checked && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      sf: "checkmark",
      size: 11
    })), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1,
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis'
      }
    }, it.label), it.suffix && /*#__PURE__*/React.createElement("span", {
      style: {
        color: 'var(--label-secondary)'
      }
    }, it.suffix), it.shortcut && /*#__PURE__*/React.createElement("span", {
      style: {
        color: 'var(--label-secondary)'
      }
    }, it.shortcut));
  }));
}
Object.assign(__ds_scope, { MenuPanel });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/MenuPanel.jsx", error: String((e && e.message) || e) }); }

// components/layout/SectionLabel.jsx
try { (() => {
/* A section header that carries an icon, so scanning down a long grouped Form gives you shape
   as well as text. A plain Section("…") header is a wall of identical grey labels. */
function SectionLabel({
  title,
  sf,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-6)',
      font: 'var(--weight-semibold) var(--text-headline)/1.2 var(--font-system)',
      color: 'var(--label)',
      ...style
    }
  }, sf && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: sf,
    size: 13
  }), /*#__PURE__*/React.createElement("span", null, title));
}
Object.assign(__ds_scope, { SectionLabel });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/SectionLabel.jsx", error: String((e && e.message) || e) }); }

// components/layout/SettingsHint.jsx
try { (() => {
const TICK = String.fromCharCode(96);

/* The one hint style in this window: 12px secondary, with backtick code spans rendered mono. */
function SettingsHint({
  children,
  style
}) {
  const parts = typeof children === 'string' ? children.split(new RegExp('(' + TICK + '[^' + TICK + ']+' + TICK + ')', 'g')) : [children];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      font: 'var(--weight-regular) var(--text-callout)/var(--leading-prose) var(--font-system)',
      color: 'var(--label-secondary)',
      textWrap: 'pretty',
      ...style
    }
  }, parts.map((p, i) => typeof p === 'string' && p.startsWith(TICK) && p.endsWith(TICK) && p.length > 2 ? /*#__PURE__*/React.createElement("code", {
    key: i,
    style: {
      font: 'var(--text-callout)/1 var(--font-mono)'
    }
  }, p.slice(1, -1)) : /*#__PURE__*/React.createElement(React.Fragment, {
    key: i
  }, p)));
}
Object.assign(__ds_scope, { SettingsHint });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/SettingsHint.jsx", error: String((e && e.message) || e) }); }

// components/layout/FormSection.jsx
try { (() => {
/* One Section of a grouped Form: header above, a white rounded box with hairline-separated
   rows, footer hint below. */
function FormSection({
  header,
  footer,
  children,
  style
}) {
  const rows = React.Children.toArray(children);
  return /*#__PURE__*/React.createElement("section", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-6)',
      ...style
    }
  }, header && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 var(--space-2)'
    }
  }, header), /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--control-bg)',
      borderRadius: 'var(--radius-card)',
      boxShadow: '0 0 0 0.5px var(--separator)',
      overflow: 'hidden'
    }
  }, rows.map((r, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      padding: 'var(--space-8) var(--space-12)',
      borderTop: i === 0 ? 'none' : 'var(--divider)'
    }
  }, r))), footer && /*#__PURE__*/React.createElement(__ds_scope.SettingsHint, {
    style: {
      padding: '0 var(--space-4)'
    }
  }, footer));
}
Object.assign(__ds_scope, { FormSection });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/FormSection.jsx", error: String((e && e.message) || e) }); }

// components/layout/ListActionBar.jsx
try { (() => {
/* The macOS "table with a +/- strip glued to its bottom edge" idiom. The caveat text lives
   inside this strip rather than in a second bar below it. */
function ListActionBar({
  addHelp = 'Add',
  removeHelp = 'Remove',
  onAdd,
  onRemove,
  hint
}) {
  const btn = (sf, help, action) => /*#__PURE__*/React.createElement("button", {
    type: "button",
    title: help,
    "aria-label": help,
    disabled: !action,
    onClick: () => action && action(),
    style: {
      width: 20,
      height: 18,
      display: 'grid',
      placeItems: 'center',
      padding: 0,
      background: 'none',
      border: 'none',
      color: 'var(--label)',
      opacity: action ? 1 : 0.3,
      cursor: action ? 'pointer' : 'default'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: sf,
    size: 12
  }));
  return /*#__PURE__*/React.createElement(__ds_scope.BarStrip, {
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-10)',
      padding: '7px 12px ' + (hint ? '3px' : '7px')
    }
  }, btn('plus', addHelp, onAdd), btn('minus', removeHelp, onRemove)), hint && /*#__PURE__*/React.createElement(__ds_scope.SettingsHint, {
    style: {
      padding: '0 var(--space-14) var(--space-9)'
    }
  }, hint));
}
Object.assign(__ds_scope, { ListActionBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/ListActionBar.jsx", error: String((e && e.message) || e) }); }

// components/layout/SettingsFooter.jsx
try { (() => {
/* A hint pinned to the bottom of a tab that has no action bar of its own to hang it off. */
function SettingsFooter({
  children
}) {
  return /*#__PURE__*/React.createElement(__ds_scope.BarStrip, {
    padded: false
  }, /*#__PURE__*/React.createElement(__ds_scope.SettingsHint, {
    style: {
      padding: 'var(--space-9) var(--space-16)'
    }
  }, children));
}
Object.assign(__ds_scope, { SettingsFooter });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/SettingsFooter.jsx", error: String((e && e.message) || e) }); }

// components/layout/TabBar.jsx
try { (() => {
/* The toolbar-style TabView of a macOS settings window: icon over title, selected tab filled. */
function TabBar({
  tabs = [],
  value,
  onChange
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-2)',
      justifyContent: 'center',
      padding: '10px var(--space-12)',
      background: 'var(--bar-bg)',
      backdropFilter: 'blur(var(--bar-blur))',
      WebkitBackdropFilter: 'blur(var(--bar-blur))',
      borderBottom: 'var(--divider)'
    }
  }, tabs.map(t => {
    const on = t.id === value;
    return /*#__PURE__*/React.createElement("button", {
      key: t.id,
      type: "button",
      onClick: () => onChange && onChange(t.id),
      style: {
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 3,
        width: 76,
        padding: '5px 4px 4px',
        border: 'none',
        cursor: 'pointer',
        borderRadius: 'var(--radius-field)',
        background: on ? 'var(--label-quaternary)' : 'transparent',
        color: on ? 'var(--label)' : 'var(--label-secondary)',
        fontFamily: 'var(--font-system)',
        fontSize: 'var(--text-subheadline)',
        fontWeight: on ? 500 : 400,
        lineHeight: 1.1
      }
    }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      sf: t.sf,
      size: 17
    }), /*#__PURE__*/React.createElement("span", {
      style: {
        whiteSpace: 'nowrap'
      }
    }, t.label));
  }));
}
Object.assign(__ds_scope, { TabBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/TabBar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/cli/CliKit.jsx
try { (() => {
const COMMANDS = [{
  cmd: 'aerospork list-monitors',
  out: [['1 | Built-in Retina Display'], ['2 | DELL U2720Q'], ['3 | DisplayLink Monitor']]
}, {
  cmd: "aerospork list-monitors --format '%{monitor-fingerprint}'",
  out: [['uuid=BBBBBBBB-0000-4000-8000-000000000002 vendor=0x0610 model=0xA050 serial=0 1728x1117'], ['uuid=AAAAAAAA-0000-4000-8000-000000000001 vendor=0x10AC model=0xD0C1 serial=1273 2560x1440'], ['uuid=CCCCCCCC-0000-4000-8000-000000000003 vendor= model= serial= 1920x1080', 'dim'], ['# the DisplayLink panel reports no EDID — its UUID is the only usable key', 'dim']]
}, {
  cmd: 'aerospork list-workspaces --monitor all',
  out: [['1'], ['2'], ['web']]
}, {
  cmd: 'aerospork focus left',
  out: []
}, {
  cmd: 'aerospork layout tiles horizontal vertical',
  out: []
}, {
  cmd: 'aerospork config --config-path',
  out: [['/Users/you/.aerospork.toml']]
}, {
  cmd: 'aerospork reload-config --dry-run',
  out: [['config parsed; 0 warnings', 'ok']]
}, {
  cmd: 'aerospork --version',
  out: [['aerospork CLI 0.4.1 a91f2c8d'], ['aerospork server 0.4.1 a91f2c8d']]
}];
function CliKit() {
  const [ran, setRan] = React.useState([0, 1]);
  const bodyRef = React.useRef(null);
  React.useEffect(() => {
    if (bodyRef.current) bodyRef.current.scrollTop = bodyRef.current.scrollHeight;
  }, [ran]);
  return /*#__PURE__*/React.createElement("div", {
    className: "term"
  }, /*#__PURE__*/React.createElement("div", {
    className: "term-bar"
  }, /*#__PURE__*/React.createElement("span", {
    className: "tl",
    style: {
      background: '#ff5f57'
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "tl",
    style: {
      background: '#febc2e'
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "tl",
    style: {
      background: '#28c840'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      textAlign: 'center',
      marginRight: 56
    }
  }, "you \u2014 -zsh \u2014 86\xD724")), /*#__PURE__*/React.createElement("div", {
    className: "term-body",
    ref: bodyRef
  }, ran.map((i, n) => {
    const c = COMMANDS[i];
    return /*#__PURE__*/React.createElement("div", {
      key: n
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "prompt"
    }, "~ \u276F"), " ", c.cmd), c.out.map((line, j) => /*#__PURE__*/React.createElement("div", {
      key: j,
      className: line[1] || ''
    }, line[0])), !c.out.length && /*#__PURE__*/React.createElement("div", {
      className: "dim"
    }, '\u00a0'));
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
    className: "prompt"
  }, "~ \u276F"), " ", /*#__PURE__*/React.createElement("span", {
    style: {
      background: '#d7dbe4',
      color: '#14161c'
    }
  }, "\xA0"))), /*#__PURE__*/React.createElement("div", {
    className: "picker"
  }, COMMANDS.map((c, i) => /*#__PURE__*/React.createElement("button", {
    key: i,
    className: ran[ran.length - 1] === i ? 'on' : '',
    onClick: () => setRan([...ran, i])
  }, c.cmd.replace('aerospork ', ''))), /*#__PURE__*/React.createElement("button", {
    onClick: () => setRan([]),
    style: {
      marginLeft: 'auto'
    }
  }, "clear")));
}
Object.assign(window, {
  CliKit
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/cli/CliKit.jsx", error: String((e && e.message) || e) }); }

// ui_kits/menu_bar/MenuBarKit.jsx
try { (() => {
const {
  WorkspaceChips,
  MenuPanel,
  Icon
} = window.AeroSporkDesignSystem_078bd7;
const WORKSPACES = {
  '1': [{
    title: 'Ghostty',
    dark: true,
    lines: ['~ ❯ aerospork list-workspaces --focused', '1', '~ ❯ ']
  }, {
    title: 'Xcode',
    lines: ['ConfigurationWindow.swift', '', 'struct ConfigurationWindow: View {', '    @StateObject private var viewModel']
  }, {
    title: 'Safari',
    lines: ['github.com/wbsmolen/aerospork']
  }],
  '2': [{
    title: 'Notes',
    lines: ['Fork notes', '— monitor identity by UUID', '— settings GUI, seven tabs']
  }, {
    title: 'Mail',
    lines: ['Inbox (3)']
  }],
  'web': [{
    title: 'Safari',
    lines: ['aerospork — docs / guide.adoc']
  }, {
    title: 'Figma',
    lines: ['AeroSpork brand']
  }, {
    title: 'Slack',
    lines: ['#aerospork']
  }]
};
function Tile({
  w,
  focused,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: 'win' + (focused ? ' focused' : ''),
    style: style
  }, /*#__PURE__*/React.createElement("div", {
    className: "bar"
  }, /*#__PURE__*/React.createElement("span", {
    className: "tl",
    style: {
      background: '#ff5f57'
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "tl",
    style: {
      background: '#febc2e'
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "tl",
    style: {
      background: '#28c840'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      marginLeft: 4
    }
  }, w.title)), /*#__PURE__*/React.createElement("div", {
    className: 'body' + (w.dark ? ' dark' : '')
  }, w.lines.map((l, i) => /*#__PURE__*/React.createElement("div", {
    key: i
  }, l || '\u00a0'))));
}
function MenuBarKit() {
  const [workspace, setWorkspace] = React.useState('1');
  const [open, setOpen] = React.useState(false);
  const [enabled, setEnabled] = React.useState(true);
  const [mode, setMode] = React.useState(null);
  const gap = 8;
  const wins = WORKSPACES[workspace];
  const chips = [...Object.keys(WORKSPACES).map(n => ({
    name: n,
    active: n === workspace
  })), ...(mode ? [{
    name: mode,
    type: 'mode',
    active: true
  }] : [])];
  const items = [...(mode ? [{
    label: 'Leave “' + mode + '” mode',
    onClick: () => {
      setMode(null);
      setOpen(false);
    }
  }, {
    divider: true
  }] : []), ...Object.keys(WORKSPACES).map(n => ({
    label: n,
    mono: true,
    checked: n === workspace,
    onClick: () => {
      setWorkspace(n);
      setOpen(false);
    }
  })), {
    divider: true
  }, {
    label: enabled ? 'Pause tiling' : 'Resume tiling',
    shortcut: '⌘E',
    onClick: () => {
      setEnabled(!enabled);
      setOpen(false);
    }
  }, {
    divider: true
  }, {
    label: 'Settings…',
    shortcut: '⌘,',
    onClick: () => {
      window.open('../settings_app/index.html', '_blank');
      setOpen(false);
    }
  }, {
    label: 'Quit AeroSpork',
    shortcut: '⌘Q',
    onClick: () => setOpen(false)
  }];
  return /*#__PURE__*/React.createElement("div", {
    className: "desktop",
    onClick: () => setOpen(false)
  }, /*#__PURE__*/React.createElement("div", {
    className: "menubar"
  }, /*#__PURE__*/React.createElement("span", {
    className: "apple"
  }), /*#__PURE__*/React.createElement("span", {
    className: "app"
  }, "Ghostty"), /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .85
    }
  }, "File"), /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .85
    }
  }, "Edit"), /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .85
    }
  }, "View"), /*#__PURE__*/React.createElement("span", {
    className: "right"
  }, /*#__PURE__*/React.createElement("button", {
    className: 'chips-btn' + (open ? ' open' : ''),
    onClick: e => {
      e.stopPropagation();
      setOpen(!open);
    }
  }, enabled ? /*#__PURE__*/React.createElement(WorkspaceChips, {
    ink: "light",
    height: 16,
    items: chips
  }) : /*#__PURE__*/React.createElement("span", {
    className: "paused",
    style: {
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "pause.circle.fill",
    size: 14
  }))), /*#__PURE__*/React.createElement("span", null, "Tue 16:41"))), open && /*#__PURE__*/React.createElement("div", {
    className: "menu-anchor",
    style: {
      right: 78
    },
    onClick: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement(MenuPanel, {
    width: 228,
    items: items
  })), /*#__PURE__*/React.createElement("div", {
    className: "stage",
    style: {
      padding: 32 + 'px ' + 8 + 'px ' + 8 + 'px',
      gap
    }
  }, enabled ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Tile, {
    w: wins[0],
    focused: true,
    style: {
      flex: 1.28
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      gap
    }
  }, wins.slice(1).map((w, i) => /*#__PURE__*/React.createElement(Tile, {
    key: i,
    w: w,
    style: {
      flex: 1
    }
  })))) : /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      flex: 1
    }
  }, wins.map((w, i) => /*#__PURE__*/React.createElement(Tile, {
    key: i,
    w: w,
    focused: i === 0,
    style: {
      position: 'absolute',
      left: 40 + i * 46,
      top: 20 + i * 34,
      width: 460,
      height: 280
    }
  })))), /*#__PURE__*/React.createElement("div", {
    className: "hint"
  }, "Click the chips in the menu bar. Workspaces switch instantly \u2014 no macOS Spaces animation.", mode ? '' : ' ', !mode && /*#__PURE__*/React.createElement("button", {
    onClick: e => {
      e.stopPropagation();
      setMode('service');
    },
    style: {
      background: 'none',
      border: 'none',
      color: 'var(--brand-focused)',
      cursor: 'pointer',
      fontSize: 11,
      fontFamily: 'var(--font-system)'
    }
  }, "Enter \u201Cservice\u201D mode")));
}
Object.assign(window, {
  MenuBarKit
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/menu_bar/MenuBarKit.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/App.jsx
try { (() => {
const {
  WindowChrome,
  TabBar,
  Banner
} = window.AeroSporkDesignSystem_078bd7;
const TABS = [{
  id: 'general',
  label: 'General',
  sf: 'gearshape'
}, {
  id: 'gaps',
  label: 'Gaps',
  sf: 'rectangle.split.3x3'
}, {
  id: 'keys',
  label: 'Keys',
  sf: 'keyboard'
}, {
  id: 'monitors',
  label: 'Monitors',
  sf: 'display.2'
}, {
  id: 'events',
  label: 'Events',
  sf: 'bolt'
}, {
  id: 'rules',
  label: 'Window Rules',
  sf: 'macwindow.badge.plus'
}, {
  id: 'raw',
  label: 'Raw TOML',
  sf: 'doc.plaintext'
}];
function SettingsApp({
  framed = true,
  initialTab = 'general',
  banner = null
}) {
  const D = window.AS_DATA;
  const [tab, setTab] = React.useState(initialTab);
  const [settings, setSettings] = React.useState({
    startAtLogin: true,
    unhide: true,
    autoMove: true,
    menuBarIcon: true,
    dockIcon: false,
    layout: 'tiles',
    orientation: 'auto',
    accordionPadding: 30,
    flatten: true,
    alternate: true,
    keyMapping: 'qwerty',
    innerH: 8,
    innerV: 8,
    outerTop: 32,
    outerBottom: 8,
    outerLeft: 8,
    outerRight: 8
  });
  const set = (k, v) => setSettings(s => ({
    ...s,
    [k]: v
  }));
  const [bindings, setBindings] = React.useState(D.bindings);
  const [assignments, setAssignments] = React.useState(D.assignments);
  const [rules, setRules] = React.useState(D.rules);
  const [events, setEvents] = React.useState(D.events);
  const [env, setEnv] = React.useState(D.env);
  const [inherit, setInherit] = React.useState(true);
  const [toml, setToml] = React.useState(D.toml);
  const body = /*#__PURE__*/React.createElement(React.Fragment, null, banner === 'error' && /*#__PURE__*/React.createElement(Banner, {
    kind: "error"
  }, 'Your config was not loaded — AeroSpork is running built-in defaults. Fix the errors below and save; the config reloads by itself.\nline 12: unknown key ‘mods’'), /*#__PURE__*/React.createElement(TabBar, {
    tabs: TABS,
    value: tab,
    onChange: setTab
  }), /*#__PURE__*/React.createElement("div", {
    className: "tab-body"
  }, tab === 'general' && /*#__PURE__*/React.createElement(GeneralTab, {
    s: settings,
    set: set
  }), tab === 'gaps' && /*#__PURE__*/React.createElement(GapsTab, {
    s: settings,
    set: set
  }), tab === 'keys' && /*#__PURE__*/React.createElement(KeysTab, {
    bindings: bindings,
    setBindings: setBindings
  }), tab === 'monitors' && /*#__PURE__*/React.createElement(MonitorsTab, {
    monitors: D.monitors,
    assignments: assignments,
    setAssignments: setAssignments
  }), tab === 'events' && /*#__PURE__*/React.createElement(EventsTab, {
    events: events,
    setEvents: setEvents,
    env: env,
    setEnv: setEnv,
    inherit: inherit,
    setInherit: setInherit
  }), tab === 'rules' && /*#__PURE__*/React.createElement(RulesTab, {
    rules: rules,
    setRules: setRules
  }), tab === 'raw' && /*#__PURE__*/React.createElement(RawTomlTab, {
    toml: toml,
    setToml: setToml,
    original: D.toml
  })));
  if (!framed) return /*#__PURE__*/React.createElement("div", {
    className: "settings-plain"
  }, body);
  return /*#__PURE__*/React.createElement(WindowChrome, {
    width: 880,
    height: 620
  }, body);
}
Object.assign(window, {
  SettingsApp,
  SETTINGS_TABS: TABS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/App.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/EventsTab.jsx
try { (() => {
const {
  FormSection,
  SectionLabel,
  TextField,
  Button,
  Icon
} = window.AeroSporkDesignSystem_078bd7;
function CommandRows({
  title,
  sf,
  footer,
  list,
  onChange
}) {
  const set = (i, v) => onChange(list.map((c, j) => j === i ? v : c));
  const rows = list.length ? list : [null];
  return /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: title,
      sf: sf
    }),
    footer: footer
  }, rows.map((c, i) => c === null ? /*#__PURE__*/React.createElement("span", {
    key: "empty",
    style: {
      fontSize: 'var(--text-callout)',
      color: 'var(--label-tertiary)'
    }
  }, "Nothing here yet. Anything you add runs every time this event fires — exec-and-forget for a shell command, or an aerospork command directly.") : /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      display: 'flex',
      gap: 8,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    value: c,
    placeholder: "command",
    onChange: v => set(i, v),
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    iconOnly: true,
    title: "Remove",
    onClick: () => onChange(list.filter((_, j) => j !== i))
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "minus.circle",
    size: 14,
    style: {
      color: 'var(--label-secondary)'
    }
  })))), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: () => onChange([...list, ''])
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "plus.circle",
    size: 13
  }), " Add command"));
}
function EventsTab({
  events,
  setEvents,
  env,
  setEnv,
  inherit,
  setInherit
}) {
  const set = k => v => setEvents({
    ...events,
    [k]: v
  });
  return /*#__PURE__*/React.createElement("div", {
    className: "form-page"
  }, /*#__PURE__*/React.createElement(CommandRows, {
    title: "After startup",
    sf: "play.circle",
    list: events.afterStartup,
    onChange: set('afterStartup'),
    footer: "Runs once, after AeroSpork finishes launching."
  }), /*#__PURE__*/React.createElement(CommandRows, {
    title: "Focused workspace changed",
    sf: "rectangle.on.rectangle",
    list: events.workspaceChanged,
    onChange: set('workspaceChanged'),
    footer: "Every workspace switch, including switches within one monitor. `move-mouse window-lazy-center` here is what makes the pointer follow you."
  }), /*#__PURE__*/React.createElement(CommandRows, {
    title: "Focused monitor changed",
    sf: "display.2",
    list: events.monitorChanged,
    onChange: set('monitorChanged'),
    footer: "Only when focus moves to a different monitor."
  }), /*#__PURE__*/React.createElement(CommandRows, {
    title: "Focus changed",
    sf: "scope",
    list: events.focusChanged,
    onChange: set('focusChanged'),
    footer: "Any focus change at all: window, workspace or monitor. Fires the most often \u2014 keep it cheap."
  }), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Environment for exec commands",
      sf: "terminal"
    }),
    footer: "`exec-and-forget` and every command above run with this environment. `PATH` is the one people usually need."
  }, /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'flex',
      gap: 8,
      alignItems: 'center',
      fontSize: 'var(--text-default)'
    }
  }, /*#__PURE__*/React.createElement("input", {
    type: "checkbox",
    checked: inherit,
    onChange: e => setInherit(e.target.checked)
  }), "Inherit this app's environment"), env.map(v => /*#__PURE__*/React.createElement("div", {
    key: v.id,
    style: {
      display: 'flex',
      gap: 8,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    value: v.name,
    placeholder: "NAME",
    width: 150,
    onChange: nv => setEnv(env.map(e => e.id === v.id ? {
      ...e,
      name: nv
    } : e))
  }), /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    value: v.value,
    placeholder: "value",
    style: {
      flex: 1
    },
    onChange: nv => setEnv(env.map(e => e.id === v.id ? {
      ...e,
      value: nv
    } : e))
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    iconOnly: true,
    title: "Remove",
    onClick: () => setEnv(env.filter(e => e.id !== v.id))
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "minus.circle",
    size: 14,
    style: {
      color: 'var(--label-secondary)'
    }
  })))), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: () => setEnv([...env, {
      id: 'v' + Date.now(),
      name: '',
      value: ''
    }])
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "plus.circle",
    size: 13
  }), " Add variable")));
}
Object.assign(window, {
  EventsTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/EventsTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/GapsTab.jsx
try { (() => {
const {
  FormSection,
  SectionLabel,
  NumberField,
  SettingsFooter,
  GapsPreview
} = window.AeroSporkDesignSystem_078bd7;
function GapsTab({
  s,
  set
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "tab-column"
  }, /*#__PURE__*/React.createElement("div", {
    className: "form-page"
  }, /*#__PURE__*/React.createElement(FormSection, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'center',
      padding: '4px 0'
    }
  }, /*#__PURE__*/React.createElement(GapsPreview, {
    width: 560,
    height: 156,
    innerHorizontal: s.innerH,
    innerVertical: s.innerV,
    outerTop: s.outerTop,
    outerBottom: s.outerBottom,
    outerLeft: s.outerLeft,
    outerRight: s.outerRight
  }))), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Between windows",
      sf: "rectangle.split.2x1"
    })
  }, /*#__PURE__*/React.createElement(NumberField, {
    title: "Horizontal",
    value: s.innerH,
    onChange: v => set('innerH', v)
  }), /*#__PURE__*/React.createElement(NumberField, {
    title: "Vertical",
    value: s.innerV,
    onChange: v => set('innerV', v)
  })), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Around the screen",
      sf: "rectangle.inset.filled"
    }),
    footer: "The top gap is measured below the menu bar, so 0 is flush with the usable area."
  }, /*#__PURE__*/React.createElement(NumberField, {
    title: "Top",
    value: s.outerTop,
    onChange: v => set('outerTop', v)
  }), /*#__PURE__*/React.createElement(NumberField, {
    title: "Bottom",
    value: s.outerBottom,
    onChange: v => set('outerBottom', v)
  }), /*#__PURE__*/React.createElement(NumberField, {
    title: "Left",
    value: s.outerLeft,
    onChange: v => set('outerLeft', v)
  }), /*#__PURE__*/React.createElement(NumberField, {
    title: "Right",
    value: s.outerRight,
    onChange: v => set('outerRight', v)
  }))), /*#__PURE__*/React.createElement(SettingsFooter, null, "Per-monitor gaps, such as a list of values under outer.top, = [", '{', " monitor.main = 16 ", '}', ", 8] survive untouched until you change one of these \u2014 editing any gap rewrites the whole gaps section. Use Raw TOML for per-monitor rules."));
}
Object.assign(window, {
  GapsTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/GapsTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/GeneralTab.jsx
try { (() => {
const {
  FormSection,
  SectionLabel,
  LabeledContent,
  Toggle,
  SegmentedPicker,
  Select,
  NumberField,
  CopyButton
} = window.AeroSporkDesignSystem_078bd7;
function GeneralTab({
  s,
  set
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "form-page"
  }, /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Startup & behaviour",
      sf: "power"
    })
  }, /*#__PURE__*/React.createElement(Toggle, {
    label: "Start AeroSpork at login",
    checked: s.startAtLogin,
    onChange: v => set('startAtLogin', v)
  }), /*#__PURE__*/React.createElement(Toggle, {
    label: "Automatically unhide macOS hidden apps",
    checked: s.unhide,
    onChange: v => set('unhide', v),
    help: "Undo Command-H automatically, so hidden windows keep tiling"
  }), /*#__PURE__*/React.createElement(Toggle, {
    label: "Move workspaces to assigned monitors on connect",
    checked: s.autoMove,
    onChange: v => set('autoMove', v),
    help: "Re-applies workspace-to-monitor assignments when the monitor set changes"
  })), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Appearance",
      sf: "menubar.rectangle"
    }),
    footer: "AeroSpork has no window of its own, so these two icons are the only ways back into Settings without the command line. `aerospork open-settings` opens this window from anywhere."
  }, /*#__PURE__*/React.createElement(Toggle, {
    label: "Show icon in the menu bar",
    checked: s.menuBarIcon,
    onChange: v => set('menuBarIcon', v),
    help: "The workspace chips, and the menu with workspace switching and Settings in it"
  }), /*#__PURE__*/React.createElement(Toggle, {
    label: "Show icon in the Dock",
    checked: s.dockIcon,
    onChange: v => set('dockIcon', v)
  })), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Layout",
      sf: "rectangle.split.3x1"
    }),
    footer: "Auto gives wide monitors a horizontal split and tall monitors a vertical one. The accordion peek is how much of the window behind stays visible; 0 stacks them exactly."
  }, /*#__PURE__*/React.createElement(LabeledContent, {
    label: "New workspaces use"
  }, /*#__PURE__*/React.createElement(SegmentedPicker, {
    options: [{
      value: 'tiles',
      label: 'Tiles'
    }, {
      value: 'accordion',
      label: 'Accordion'
    }],
    value: s.layout,
    onChange: v => set('layout', v)
  })), /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Split direction"
  }, /*#__PURE__*/React.createElement(SegmentedPicker, {
    options: [{
      value: 'auto',
      label: 'Auto'
    }, {
      value: 'horizontal',
      label: 'Horizontal'
    }, {
      value: 'vertical',
      label: 'Vertical'
    }],
    value: s.orientation,
    onChange: v => set('orientation', v)
  })), /*#__PURE__*/React.createElement(NumberField, {
    title: "Accordion peek",
    value: s.accordionPadding,
    onChange: v => set('accordionPadding', v)
  })), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Normalization",
      sf: "wand.and.stars"
    }),
    footer: "Housekeeping applied after every layout change. Turn both off if you want the tree to stay exactly as you built it."
  }, /*#__PURE__*/React.createElement(Toggle, {
    label: "Flatten single-child containers",
    checked: s.flatten,
    onChange: v => set('flatten', v)
  }), /*#__PURE__*/React.createElement(Toggle, {
    label: "Alternate orientation for nested containers",
    checked: s.alternate,
    onChange: v => set('alternate', v)
  })), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Keyboard",
      sf: "keyboard"
    }),
    footer: "How the key names in your bindings map to physical keys. `alt-h` means the key labelled H on this layout."
  }, /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Keyboard layout"
  }, /*#__PURE__*/React.createElement(Select, {
    width: 160,
    value: s.keyMapping,
    onChange: v => set('keyMapping', v),
    options: [{
      value: 'qwerty',
      label: 'QWERTY'
    }, {
      value: 'dvorak',
      label: 'Dvorak'
    }, {
      value: 'colemak',
      label: 'Colemak'
    }]
  }))), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "About",
      sf: "info.circle"
    })
  }, /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Version"
  }, /*#__PURE__*/React.createElement("span", {
    className: "mono"
  }, "0.4.1 (a91f2c)"), /*#__PURE__*/React.createElement(CopyButton, {
    value: "AeroSpork v0.4.1 a91f2c8d",
    help: "Copy full version for a bug report"
  })), /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Config file"
  }, /*#__PURE__*/React.createElement("span", {
    className: "mono path"
  }, "~/.aerospork.toml"), /*#__PURE__*/React.createElement(CopyButton, {
    value: "/Users/you/.aerospork.toml",
    help: "Copy path"
  }))));
}
Object.assign(window, {
  GeneralTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/GeneralTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/KeysTab.jsx
try { (() => {
const {
  BarStrip,
  SegmentedPicker,
  TextField,
  Button,
  Icon,
  KeyRecorderField,
  PrettyKey,
  Badge,
  ContentUnavailable,
  SettingsHint,
  StatusLabel
} = window.AeroSporkDesignSystem_078bd7;
function KeysTab({
  bindings,
  setBindings
}) {
  const [mode, setMode] = React.useState('main');
  const [query, setQuery] = React.useState('');
  const [newKey, setNewKey] = React.useState('');
  const [newCommand, setNewCommand] = React.useState('');
  const [recording, setRecording] = React.useState(false);
  const all = bindings[mode] || [];
  const needle = query.trim().toLowerCase();
  const rows = needle ? all.filter(b => b.key.toLowerCase().includes(needle) || b.command.toLowerCase().includes(needle)) : all;
  const generated = all.filter(b => b.origin === 'generated').length;
  const explicit = all.length - generated;
  const conflict = newKey ? all.find(b => b.key === newKey) : null;
  const update = (id, patch) => setBindings({
    ...bindings,
    [mode]: all.map(b => b.id === id ? {
      ...b,
      ...patch
    } : b)
  });
  const remove = id => setBindings({
    ...bindings,
    [mode]: all.filter(b => b.id !== id)
  });
  const override = b => setBindings({
    ...bindings,
    [mode]: [...all, {
      id: 'o' + Date.now(),
      key: b.key,
      command: b.command,
      origin: 'explicit'
    }]
  });
  const add = () => {
    if (!newKey || !newCommand.trim()) return;
    const rest = all.filter(b => !(b.key === newKey && b.origin === 'explicit'));
    setBindings({
      ...bindings,
      [mode]: [...rest, {
        id: 'n' + Date.now(),
        key: newKey,
        command: newCommand,
        origin: 'explicit'
      }]
    });
    setNewKey('');
    setNewCommand('');
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "tab-column"
  }, /*#__PURE__*/React.createElement(BarStrip, {
    edge: "top",
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      padding: '9px 14px'
    }
  }, /*#__PURE__*/React.createElement(SegmentedPicker, {
    options: ['main', 'service'],
    value: mode,
    onChange: setMode
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    iconOnly: true,
    title: "Mode actions"
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "ellipsis.circle",
    size: 15
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "filter"
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "magnifyingglass",
    size: 12,
    style: {
      color: 'var(--label-secondary)'
    }
  }), /*#__PURE__*/React.createElement(TextField, {
    variant: "plain",
    placeholder: "Filter",
    value: query,
    onChange: setQuery,
    width: 150
  }), query && /*#__PURE__*/React.createElement("button", {
    className: "clear",
    onClick: () => setQuery('')
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "xmark.circle.fill",
    size: 12
  }))))), /*#__PURE__*/React.createElement("div", {
    className: "list"
  }, rows.length === 0 ? /*#__PURE__*/React.createElement(ContentUnavailable, {
    sf: "magnifyingglass",
    title: "No matches",
    message: 'Nothing in “' + mode + '” matches “' + query + '”.'
  }) : rows.map(b => /*#__PURE__*/React.createElement("div", {
    key: b.id,
    className: "binding-row"
  }, b.origin === 'explicit' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(KeyRecorderField, {
    notation: b.key,
    showsClear: false
  }), /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    value: b.command,
    onChange: v => update(b.id, {
      command: v
    }),
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    iconOnly: true,
    title: "Remove this binding",
    onClick: () => remove(b.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "minus.circle",
    size: 14,
    style: {
      color: 'var(--label-secondary)'
    }
  }))) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", {
    className: "mono keycell"
  }, PrettyKey(b.key)), /*#__PURE__*/React.createElement("span", {
    className: "mono cmdcell"
  }, b.command), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Badge, {
    help: "Generated from mod and workspaces. It is not written in your config file."
  }, "generated"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: () => override(b)
  }, "Override"))))), /*#__PURE__*/React.createElement(BarStrip, {
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      padding: '10px 14px 0'
    }
  }, /*#__PURE__*/React.createElement(KeyRecorderField, {
    notation: newKey,
    width: 170,
    recording: recording,
    onArm: v => {
      setRecording(v);
      if (v) setTimeout(() => {
        setNewKey('alt-shift-d');
        setRecording(false);
      }, 700);
    },
    onClear: () => setNewKey('')
  }), /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "command, e.g. focus left",
    value: newCommand,
    onChange: setNewCommand,
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    onClick: add,
    disabled: !newKey || !newCommand.trim()
  }, conflict ? 'Replace' : 'Add')), conflict && /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      padding: '7px 14px 0'
    }
  }, /*#__PURE__*/React.createElement(StatusLabel, {
    kind: "warning"
  }, PrettyKey(conflict.key) + ' is already bound to ', /*#__PURE__*/React.createElement("span", {
    className: "mono"
  }, conflict.command)), conflict.origin === 'generated' && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--text-callout)',
      color: 'var(--label-secondary)'
    }
  }, "(generated)"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: () => setQuery(conflict.key)
  }, "Show")), /*#__PURE__*/React.createElement(SettingsHint, {
    style: {
      padding: '7px 14px 10px'
    }
  }, (generated ? generated + ' generated by mod, ' : '') + explicit + ' written in your config' + (generated ? '. Generated bindings have no line to edit — Override copies one here first.' : '') + ' Chain commands with ;.')));
}
Object.assign(window, {
  KeysTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/KeysTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/MonitorsTab.jsx
try { (() => {
const {
  SectionLabel,
  SettingsHint,
  CopyButton,
  Icon,
  DataTable,
  ListActionBar,
  TextField,
  Select,
  ContentUnavailable
} = window.AeroSporkDesignSystem_078bd7;
function MonitorsTab({
  monitors,
  assignments,
  setAssignments
}) {
  const [selected, setSelected] = React.useState(null);
  const monitorOptions = [{
    value: 'main',
    label: 'Main'
  }, {
    value: 'secondary',
    label: 'Non-main'
  }, {
    separator: true
  }, ...monitors.flatMap(m => [{
    value: m.name,
    label: m.name
  }, {
    value: m.uuid,
    label: m.name + ' — exact display'
  }])];
  const update = (id, patch) => setAssignments(assignments.map(a => a.id === id ? {
    ...a,
    ...patch
  } : a));
  const add = () => setAssignments([...assignments, {
    id: 'a' + Date.now(),
    workspace: '',
    monitor: 'main'
  }]);
  const remove = () => {
    setAssignments(assignments.filter(a => a.id !== selected));
    setSelected(null);
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "tab-column"
  }, /*#__PURE__*/React.createElement("div", {
    className: "monitors"
  }, /*#__PURE__*/React.createElement(SectionLabel, {
    title: "Connected monitors",
    sf: "display.2",
    style: {
      padding: '14px 16px 8px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "monitor-list"
  }, monitors.map(m => /*#__PURE__*/React.createElement("div", {
    key: m.id,
    className: "monitor-row"
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--label-secondary)',
      width: 26,
      display: 'grid',
      placeItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "display",
    size: 17
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 'var(--weight-medium)'
    }
  }, m.name), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--text-callout)',
      color: 'var(--label-secondary)'
    }
  }, m.resolution)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "mono",
    style: {
      fontSize: 'var(--text-caption)',
      color: 'var(--label-tertiary)'
    }
  }, m.uuid.slice(0, 8), "\u2026"), /*#__PURE__*/React.createElement(CopyButton, {
    value: m.uuid,
    help: 'Copy display UUID\n' + m.uuid
  }))))), /*#__PURE__*/React.createElement("div", {
    className: "hairline"
  }), /*#__PURE__*/React.createElement("div", {
    className: "assignments"
  }, /*#__PURE__*/React.createElement(SectionLabel, {
    title: "Workspace assignments",
    sf: "arrow.triangle.branch",
    style: {
      padding: '12px 16px 8px'
    }
  }), /*#__PURE__*/React.createElement(DataTable, {
    selected: selected,
    onSelect: setSelected,
    columns: [{
      key: 'workspace',
      title: 'Workspace',
      width: '140px',
      render: r => /*#__PURE__*/React.createElement(TextField, {
        mono: true,
        value: r.workspace,
        placeholder: "name",
        onChange: v => update(r.id, {
          workspace: v
        }),
        style: {
          width: '100%'
        }
      })
    }, {
      key: 'monitor',
      title: 'Monitor',
      render: r => /*#__PURE__*/React.createElement(Select, {
        value: r.monitor,
        options: monitorOptions,
        onChange: v => update(r.id, {
          monitor: v
        }),
        width: "100%"
      })
    }],
    rows: assignments,
    emptyState: /*#__PURE__*/React.createElement(ContentUnavailable, {
      sf: "arrow.triangle.branch",
      title: "No assignments",
      message: "Workspaces land wherever they were last used. Add an assignment to pin one to a specific monitor.",
      actionTitle: "Add assignment",
      onAction: add
    })
  })), /*#__PURE__*/React.createElement(ListActionBar, {
    addHelp: "Pin a workspace to a monitor",
    removeHelp: "Remove the selected assignment",
    onAdd: add,
    onRemove: selected ? remove : null,
    hint: "Hardware fingerprints already in your config are preserved \u2014 they just show up here under the monitor's name. A DisplayLink panel reports no vendor or serial, so its UUID is the only thing that pins a workspace to that exact screen."
  }));
}
Object.assign(window, {
  MonitorsTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/MonitorsTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/RawTomlTab.jsx
try { (() => {
const {
  BarStrip,
  Icon,
  Button,
  CodeEditor,
  StatusLabel
} = window.AeroSporkDesignSystem_078bd7;
function RawTomlTab({
  toml,
  setToml,
  original
}) {
  const edited = toml !== original;
  const error = /^\s*=/m.test(toml) ? 'line 3: expected a key before ‘=’' : null;
  return /*#__PURE__*/React.createElement("div", {
    className: "tab-column"
  }, /*#__PURE__*/React.createElement(BarStrip, {
    edge: "top",
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: '8px 14px'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--label-secondary)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "doc.plaintext",
    size: 13
  })), /*#__PURE__*/React.createElement("span", {
    className: "mono",
    style: {
      fontSize: 'var(--text-callout)',
      color: 'var(--label-secondary)'
    }
  }, "/Users/you/.aerospork.toml"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    title: "External edits are picked up automatically \u2014 the config file is watched"
  }, "Open in TextEdit"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    title: "Re-read the config file. Normally automatic."
  }, "Reload"))), /*#__PURE__*/React.createElement(CodeEditor, {
    value: toml,
    onChange: setToml
  }), /*#__PURE__*/React.createElement(BarStrip, {
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '10px 14px'
    }
  }, error ? /*#__PURE__*/React.createElement(StatusLabel, {
    kind: "error"
  }, error) : edited ? /*#__PURE__*/React.createElement(StatusLabel, {
    kind: "ok"
  }, "Valid \u2014 press Apply (\u2318S) to write it") : /*#__PURE__*/React.createElement(StatusLabel, {
    kind: "neutral"
  }, "Matches the file on disk"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    title: "Load a previous version of this config into the editor"
  }, "Restore\u2026"), /*#__PURE__*/React.createElement(Button, {
    disabled: !edited,
    onClick: () => setToml(original)
  }, "Revert"), /*#__PURE__*/React.createElement(Button, {
    variant: "prominent",
    disabled: !edited || !!error
  }, "Apply"))));
}
Object.assign(window, {
  RawTomlTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/RawTomlTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/RulesTab.jsx
try { (() => {
const {
  SectionLabel,
  DataTable,
  ListActionBar,
  ContentUnavailable,
  FormSection,
  LabeledContent,
  TextField,
  Toggle,
  Badge
} = window.AeroSporkDesignSystem_078bd7;
function summary(r) {
  const parts = [];
  if (r.appId) parts.push(r.appId);
  if (r.appNameRegex) parts.push('name~' + r.appNameRegex);
  if (r.windowTitleRegex) parts.push('title~' + r.windowTitleRegex);
  if (r.workspace) parts.push('ws=' + r.workspace);
  return parts.length ? parts.join(' ') : '(any window)';
}
function RulesTab({
  rules,
  setRules
}) {
  const [selected, setSelected] = React.useState('r1');
  const rule = rules.find(r => r.id === selected);
  const update = patch => setRules(rules.map(r => r.id === selected ? {
    ...r,
    ...patch
  } : r));
  const add = () => {
    const id = 'r' + Date.now();
    setRules([...rules, {
      id,
      appId: '',
      appNameRegex: '',
      windowTitleRegex: '',
      workspace: '',
      run: '',
      checkFurther: false
    }]);
    setSelected(id);
  };
  const remove = () => {
    setRules(rules.filter(r => r.id !== selected));
    setSelected(null);
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "split"
  }, /*#__PURE__*/React.createElement("div", {
    className: "split-list"
  }, /*#__PURE__*/React.createElement(SectionLabel, {
    title: "Rules",
    sf: "list.bullet",
    style: {
      padding: '10px 14px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "hairline"
  }), /*#__PURE__*/React.createElement(DataTable, {
    selected: selected,
    onSelect: setSelected,
    rows: rules,
    columns: [{
      key: 'match',
      title: 'Matches',
      width: '1fr',
      render: r => /*#__PURE__*/React.createElement("span", {
        style: {
          display: 'flex',
          gap: 5,
          alignItems: 'center',
          minWidth: 0
        }
      }, /*#__PURE__*/React.createElement("span", {
        className: "mono ellipsis"
      }, summary(r)), r.duringStartup && /*#__PURE__*/React.createElement(Badge, {
        tone: "muted",
        help: "Only applies while AeroSpork is starting up"
      }, "startup"))
    }, {
      key: 'run',
      title: 'Run',
      width: '150px',
      render: r => /*#__PURE__*/React.createElement("span", {
        className: "mono ellipsis"
      }, r.run)
    }],
    emptyState: /*#__PURE__*/React.createElement(ContentUnavailable, {
      sf: "macwindow",
      title: "No window rules",
      message: "Rules run once, when a window first appears \u2014 the usual use is sending an app straight to its workspace.",
      actionTitle: "Add rule",
      onAction: add
    })
  }), /*#__PURE__*/React.createElement(ListActionBar, {
    addHelp: "Add a window rule",
    removeHelp: "Remove the selected rule",
    onAdd: add,
    onRemove: selected ? remove : null
  })), /*#__PURE__*/React.createElement("div", {
    className: "split-detail"
  }, rule ? /*#__PURE__*/React.createElement("div", {
    className: "form-page"
  }, /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Match when\u2026",
      sf: "line.3.horizontal.decrease.circle"
    }),
    footer: "Empty matchers are left out. A rule with no matchers at all applies to every window. `aerospork list-apps` prints app IDs."
  }, /*#__PURE__*/React.createElement(LabeledContent, {
    label: "App ID"
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "com.apple.finder",
    value: rule.appId,
    onChange: v => update({
      appId: v
    }),
    width: 200
  })), /*#__PURE__*/React.createElement(LabeledContent, {
    label: "App name"
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "regex, optional",
    value: rule.appNameRegex,
    onChange: v => update({
      appNameRegex: v
    }),
    width: 200
  })), /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Window title"
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "regex, optional",
    value: rule.windowTitleRegex,
    onChange: v => update({
      windowTitleRegex: v
    }),
    width: 200
  })), /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Workspace"
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "optional",
    value: rule.workspace,
    onChange: v => update({
      workspace: v
    }),
    width: 200
  }))), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Then run",
      sf: "bolt"
    }),
    footer: "Chain commands with ;. By default a matching rule stops the search."
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "move-node-to-workspace 3",
    value: rule.run,
    onChange: v => update({
      run: v
    }),
    style: {
      width: '100%'
    }
  }), /*#__PURE__*/React.createElement(Toggle, {
    label: "Keep checking later rules",
    checked: rule.checkFurther,
    onChange: v => update({
      checkFurther: v
    })
  }))) : /*#__PURE__*/React.createElement(ContentUnavailable, {
    sf: "sidebar.left",
    title: "No rule selected",
    message: "Pick a rule on the left to edit what it matches and what it does."
  })));
}
Object.assign(window, {
  RulesTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/RulesTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/data.js
try { (() => {
// Mock state for the AeroSpork Settings recreation. Values match the shipped default config.
window.AS_DATA = {
  monitors: [{
    id: 'm1',
    name: 'Built-in Retina Display',
    resolution: '1728 × 1117 pt',
    uuid: 'BBBBBBBB-0000-4000-8000-000000000002'
  }, {
    id: 'm2',
    name: 'DELL U2720Q',
    resolution: '2560 × 1440 pt',
    uuid: 'AAAAAAAA-0000-4000-8000-000000000001'
  }, {
    id: 'm3',
    name: 'DisplayLink Monitor',
    resolution: '1920 × 1080 pt',
    uuid: 'CCCCCCCC-0000-4000-8000-000000000003'
  }],
  assignments: [{
    id: 'a1',
    workspace: '1',
    monitor: 'main'
  }, {
    id: 'a2',
    workspace: 'web',
    monitor: 'AAAAAAAA-0000-4000-8000-000000000001'
  }],
  bindings: {
    main: [{
      id: 'g1',
      key: 'alt-h',
      command: 'focus left',
      origin: 'generated'
    }, {
      id: 'g2',
      key: 'alt-j',
      command: 'focus down',
      origin: 'generated'
    }, {
      id: 'g3',
      key: 'alt-k',
      command: 'focus up',
      origin: 'generated'
    }, {
      id: 'g4',
      key: 'alt-l',
      command: 'focus right',
      origin: 'generated'
    }, {
      id: 'g5',
      key: 'alt-shift-h',
      command: 'move left',
      origin: 'generated'
    }, {
      id: 'g6',
      key: 'alt-minus',
      command: 'resize smart -50',
      origin: 'generated'
    }, {
      id: 'g7',
      key: 'alt-slash',
      command: 'layout tiles horizontal vertical',
      origin: 'generated'
    }, {
      id: 'g8',
      key: 'alt-tab',
      command: 'workspace-back-and-forth',
      origin: 'generated'
    }, {
      id: 'e1',
      key: 'alt-shift-semicolon',
      command: 'mode service',
      origin: 'explicit'
    }, {
      id: 'e2',
      key: 'alt-enter',
      command: 'exec-and-forget open -na Ghostty',
      origin: 'explicit'
    }],
    service: [{
      id: 's1',
      key: 'esc',
      command: 'reload-config ; mode main',
      origin: 'explicit'
    }, {
      id: 's2',
      key: 'r',
      command: 'flatten-workspace-tree ; mode main',
      origin: 'explicit'
    }, {
      id: 's3',
      key: 'f',
      command: 'layout floating tiling ; mode main',
      origin: 'explicit'
    }, {
      id: 's4',
      key: 'backspace',
      command: 'close-all-windows-but-current ; mode main',
      origin: 'explicit'
    }]
  },
  rules: [{
    id: 'r1',
    appId: 'com.apple.mail',
    appNameRegex: '',
    windowTitleRegex: '',
    workspace: '',
    run: 'move-node-to-workspace 3',
    checkFurther: false,
    duringStartup: false
  }, {
    id: 'r2',
    appId: 'com.apple.systempreferences',
    appNameRegex: '',
    windowTitleRegex: '',
    workspace: '',
    run: 'layout floating',
    checkFurther: false,
    duringStartup: false
  }, {
    id: 'r3',
    appId: 'com.spotify.client',
    appNameRegex: '',
    windowTitleRegex: '',
    workspace: '',
    run: 'move-node-to-workspace media',
    checkFurther: false,
    duringStartup: true
  }],
  events: {
    afterStartup: ['exec-and-forget sketchybar --reload'],
    workspaceChanged: ['move-mouse window-lazy-center'],
    monitorChanged: [],
    focusChanged: []
  },
  env: [{
    id: 'v1',
    name: 'PATH',
    value: '/opt/homebrew/bin:/usr/bin:/bin'
  }],
  toml: ['# AeroSpork — tiling window manager for macOS', '', 'mod = "alt"', 'workspaces = "1-9"', '', '[gaps]', 'inner = 8', 'outer = { top = 32, bottom = 8, left = 8, right = 8 }', '', '[keys]', 'alt-shift-semicolon = "mode service"', 'alt-enter = "exec-and-forget open -na Ghostty"', '', '[keys.service]', 'esc = ["reload-config", "mode main"]', 'r = ["flatten-workspace-tree", "mode main"]', '', '[monitors]', '1 = "main"', 'web = { uuid = "AAAAAAAA-0000-4000-8000-000000000001" }', '', '[on-window]', '"com.apple.mail" = "move-node-to-workspace 3"'].join('\n')
};
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/data.js", error: String((e && e.message) || e) }); }

__ds_ns.CodeEditor = __ds_scope.CodeEditor;

__ds_ns.GapsPreview = __ds_scope.GapsPreview;

__ds_ns.WindowChrome = __ds_scope.WindowChrome;

__ds_ns.WorkspaceChips = __ds_scope.WorkspaceChips;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.CopyButton = __ds_scope.CopyButton;

__ds_ns.PrettyKey = __ds_scope.PrettyKey;

__ds_ns.KeyRecorderField = __ds_scope.KeyRecorderField;

__ds_ns.NumberField = __ds_scope.NumberField;

__ds_ns.SegmentedPicker = __ds_scope.SegmentedPicker;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.TextField = __ds_scope.TextField;

__ds_ns.Toggle = __ds_scope.Toggle;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Banner = __ds_scope.Banner;

__ds_ns.ContentUnavailable = __ds_scope.ContentUnavailable;

__ds_ns.StatusLabel = __ds_scope.StatusLabel;

__ds_ns.SF_TO_LUCIDE = __ds_scope.SF_TO_LUCIDE;

__ds_ns.ICON_SHAPES = __ds_scope.ICON_SHAPES;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.BarStrip = __ds_scope.BarStrip;

__ds_ns.DataTable = __ds_scope.DataTable;

__ds_ns.FormSection = __ds_scope.FormSection;

__ds_ns.LabeledContent = __ds_scope.LabeledContent;

__ds_ns.ListActionBar = __ds_scope.ListActionBar;

__ds_ns.MenuPanel = __ds_scope.MenuPanel;

__ds_ns.SectionLabel = __ds_scope.SectionLabel;

__ds_ns.SettingsFooter = __ds_scope.SettingsFooter;

__ds_ns.SettingsHint = __ds_scope.SettingsHint;

__ds_ns.TabBar = __ds_scope.TabBar;

})();
