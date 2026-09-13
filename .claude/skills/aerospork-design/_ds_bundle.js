/* @ds-bundle: {"format":4,"namespace":"AeroSporkDesignSystem_078bd7","components":[{"name":"SAMPLE_APPS","sourcePath":"components/brand/AppIcon.jsx"},{"name":"appDisplayName","sourcePath":"components/brand/AppIcon.jsx"},{"name":"AppIcon","sourcePath":"components/brand/AppIcon.jsx"},{"name":"CodeEditor","sourcePath":"components/brand/CodeEditor.jsx"},{"name":"GapsPreview","sourcePath":"components/brand/GapsPreview.jsx"},{"name":"MonitorArrangement","sourcePath":"components/brand/MonitorArrangement.jsx"},{"name":"WindowChrome","sourcePath":"components/brand/WindowChrome.jsx"},{"name":"WorkspaceChips","sourcePath":"components/brand/WorkspaceChips.jsx"},{"name":"Button","sourcePath":"components/controls/Button.jsx"},{"name":"CopyButton","sourcePath":"components/controls/CopyButton.jsx"},{"name":"IconButton","sourcePath":"components/controls/IconButton.jsx"},{"name":"KeyCaps","sourcePath":"components/controls/KeyCaps.jsx"},{"name":"PrettyKey","sourcePath":"components/controls/KeyRecorderField.jsx"},{"name":"KeyRecorderField","sourcePath":"components/controls/KeyRecorderField.jsx"},{"name":"NumberField","sourcePath":"components/controls/NumberField.jsx"},{"name":"SegmentedPicker","sourcePath":"components/controls/SegmentedPicker.jsx"},{"name":"Select","sourcePath":"components/controls/Select.jsx"},{"name":"TextField","sourcePath":"components/controls/TextField.jsx"},{"name":"Toggle","sourcePath":"components/controls/Toggle.jsx"},{"name":"Badge","sourcePath":"components/feedback/Badge.jsx"},{"name":"Banner","sourcePath":"components/feedback/Banner.jsx"},{"name":"ContentUnavailable","sourcePath":"components/feedback/ContentUnavailable.jsx"},{"name":"StatusLabel","sourcePath":"components/feedback/StatusLabel.jsx"},{"name":"SF_TO_LUCIDE","sourcePath":"components/icons/Icon.jsx"},{"name":"ICON_SHAPES","sourcePath":"components/icons/Icon.jsx"},{"name":"Icon","sourcePath":"components/icons/Icon.jsx"},{"name":"BarStrip","sourcePath":"components/layout/BarStrip.jsx"},{"name":"DataTable","sourcePath":"components/layout/DataTable.jsx"},{"name":"FormSection","sourcePath":"components/layout/FormSection.jsx"},{"name":"LabeledContent","sourcePath":"components/layout/LabeledContent.jsx"},{"name":"ListActionBar","sourcePath":"components/layout/ListActionBar.jsx"},{"name":"PanelHeader","sourcePath":"components/layout/PanelHeader.jsx"},{"name":"MenuPanel","sourcePath":"components/layout/MenuPanel.jsx"},{"name":"SectionLabel","sourcePath":"components/layout/SectionLabel.jsx"},{"name":"SettingsFooter","sourcePath":"components/layout/SettingsFooter.jsx"},{"name":"SettingsHint","sourcePath":"components/layout/SettingsHint.jsx"},{"name":"TabBar","sourcePath":"components/layout/TabBar.jsx"}],"sourceHashes":{"components/brand/AppIcon.jsx":"3f8a33f929bd","components/brand/CodeEditor.jsx":"533a49e91a92","components/brand/GapsPreview.jsx":"87cb37bc5537","components/brand/MonitorArrangement.jsx":"b56a8267991e","components/brand/WindowChrome.jsx":"6dc335057e30","components/brand/WorkspaceChips.jsx":"4173765b5cfe","components/controls/Button.jsx":"24bc808b095e","components/controls/CopyButton.jsx":"648e4540aa27","components/controls/KeyRecorderField.jsx":"a54067d8c308","components/controls/NumberField.jsx":"6e7b6e8407c9","components/controls/SegmentedPicker.jsx":"2fd45ae04e9f","components/controls/Select.jsx":"b02f6be972aa","components/controls/TextField.jsx":"1cee11e0b9b5","components/controls/Toggle.jsx":"45c2f697e827","components/feedback/Badge.jsx":"ae58a538773b","components/feedback/Banner.jsx":"ba979ef15e20","components/feedback/ContentUnavailable.jsx":"5904028fa356","components/feedback/StatusLabel.jsx":"a2fd1e208954","components/icons/Icon.jsx":"99ca5796d91f","components/layout/BarStrip.jsx":"c1424c6a9bb1","components/layout/DataTable.jsx":"30a32a636c0e","components/layout/FormSection.jsx":"2bbd30f8edc1","components/layout/LabeledContent.jsx":"a90dccb39353","components/layout/ListActionBar.jsx":"183839398b6d","components/layout/MenuPanel.jsx":"7643a26656de","components/layout/SectionLabel.jsx":"727a9bb3439b","components/layout/SettingsFooter.jsx":"db6e590eb557","components/layout/SettingsHint.jsx":"f3c7437163dd","components/layout/TabBar.jsx":"829940627b04","ui_kits/cli/CliKit.jsx":"31f63b3ab2bc","ui_kits/menu_bar/MenuBarKit.jsx":"e3be52c77c48","ui_kits/settings_app/App.jsx":"8158b1634b89","ui_kits/settings_app/EventsTab.jsx":"a89c0c784f08","ui_kits/settings_app/GapsTab.jsx":"85919fed77c6","ui_kits/settings_app/GeneralTab.jsx":"1aa5cd4428c4","ui_kits/settings_app/KeysTab.jsx":"cc663ef6ac53","ui_kits/settings_app/MonitorsTab.jsx":"4f18e4603d2f","ui_kits/settings_app/RawTomlTab.jsx":"343d00456002","ui_kits/settings_app/RulesTab.jsx":"5dd2d748bc6a","ui_kits/settings_app/data.js":"5f28deb3995f","components/controls/KeyCaps.jsx":"7c451ee37892"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.AeroSporkDesignSystem_078bd7 = window.AeroSporkDesignSystem_078bd7 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/brand/AppIcon.jsx
try { (() => {
// Icon.jsx's block runs later in this file, so referencing it eagerly (`const { Icon } =
// __ds_scope` at module-eval time) would capture `undefined` — __ds_scope.Icon has to be looked
// up lazily, inside the function body, at actual render time instead.

/* Placeholder app-icon tile: a glyph on a rounded-square plate, in the same squircle convention
   as the product's own icon (tokens/radius.css --icon-corner-ratio). Stands in for a real macOS
   app icon in this mock ONLY — every glyph below is a generic pictogram (an envelope, a compass,
   a folder…), not traced from any real app's actual icon art. Bundling real app icons in a public
   design-system repo is both a trademark problem and pointless duplication of art nobody here owns.

   DO NOT carry this component's *approach* into the real Swift app. The shipping Settings window
   should bundle no icon assets at all — it should resolve each app's REAL, currently-installed
   icon at runtime:
     let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId)
     let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
   That is not a legal workaround, it is also simply correct: it shows the user's own icon (right
   theme, right version), works for any app ID including ones nobody thought to hardcode, and it
   stays right if an app's icon ever changes. SAMPLE_APPS below exists only so this mock has
   *something* recognizable to render; it is deliberately small and must not grow into a "real app
   icon library" — that instinct is exactly the thing NSWorkspace makes unnecessary. */
const SAMPLE_APPS = [{
  id: 'com.apple.mail',
  name: 'Mail',
  glyph: 'envelope',
  tint: ['#67b6ff', '#0a6cf0']
}, {
  id: 'com.apple.Safari',
  name: 'Safari',
  glyph: 'safari',
  tint: ['#6fe0ff', '#0077c2']
}, {
  id: 'com.mitchellh.ghostty',
  name: 'Ghostty',
  glyph: 'terminal',
  tint: ['#5a5a60', '#232326']
}, {
  id: 'com.spotify.client',
  name: 'Spotify',
  glyph: 'music.note',
  tint: ['#6bef95', '#159c46']
}, {
  id: 'com.tinyspeck.slackmacgap',
  name: 'Slack',
  glyph: 'message',
  tint: ['#d3aeff', '#7c3aed']
}, {
  id: 'com.apple.finder',
  name: 'Finder',
  glyph: 'folder',
  tint: ['#8fd9ff', '#1f6fe0']
}, {
  id: 'com.apple.systempreferences',
  name: 'System Settings',
  glyph: 'gearshape',
  tint: ['#b8b8bd', '#6e6e73']
}];
const BY_ID = Object.fromEntries(SAMPLE_APPS.map(a => [a.id, a]));

/** Best-effort display name for a bundle ID: SAMPLE_APPS, else its last path component,
    title-cased — the same fallback a hand-typed app ID needs everywhere this shows a name. */
function appDisplayName(appId) {
  if (!appId) return 'Any app';
  const known = BY_ID[appId];
  if (known) return known.name;
  const last = appId.split('.').filter(Boolean).pop() || appId;
  return last.charAt(0).toUpperCase() + last.slice(1);
}

// ponytail: five hand-picked tints, chosen by a stable hash of the app ID so an unrecognized app
// keeps the same color across renders instead of reshuffling — not a real color-quantization
// algorithm, which would be pointless for a fallback nobody is meant to stare at.
const FALLBACK_TINTS = [['#ffc06b', '#e0821e'], ['#9fd6ff', '#3f7fd4'], ['#ddb8ff', '#8b5cf6'], ['#ffb0c2', '#e0446a'], ['#c3f0a4', '#3fa34d']];
function hashTint(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = h * 31 + s.charCodeAt(i) >>> 0;
  return FALLBACK_TINTS[h % FALLBACK_TINTS.length];
}

/** A rounded-square glyph tile standing in for a real app icon.
    - Known sample app (SAMPLE_APPS): its glyph, on its tint.
    - Unknown but non-empty appId (hand-typed, not in the sample set): a monogram of its
      resolved name, on a tint hashed from the id — stable, not random, across re-renders.
    - No appId at all ('' / null / undefined — the "any app" matcher): a neutral plate with a
      generic window glyph, never a monogram, so it can't be mistaken for a specific unknown app. */
function AppIcon({
  appId,
  size = 32,
  style
}) {
  const known = appId ? BY_ID[appId] : null;
  const customTyped = !!appId && !known;
  const [from, to] = known ? known.tint : customTyped ? hashTint(appId) : ['#c7c7cc', '#98989d'];
  const radius = Math.round(size * 0.225); // tokens/radius.css --icon-corner-ratio
  return /*#__PURE__*/React.createElement("div", {
    "aria-hidden": "true",
    style: {
      width: size,
      height: size,
      flex: '0 0 auto',
      borderRadius: radius,
      position: 'relative',
      background: `linear-gradient(180deg, ${from}, ${to})`,
      overflow: 'hidden',
      display: 'grid',
      placeItems: 'center',
      boxShadow: 'inset 0 1px 0 rgba(255,255,255,.32), inset 0 -1px 1px rgba(0,0,0,.22), 0 0.5px 1.5px rgba(0,0,0,.22)',
      ...style
    }
  }, known ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: known.glyph,
    size: Math.round(size * 0.56),
    style: {
      color: 'rgba(255,255,255,.95)'
    }
  }) : customTyped ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: `var(--weight-semibold) ${Math.round(size * 0.46)}px/1 var(--font-rounded)`,
      color: 'rgba(255,255,255,.95)'
    }
  }, appDisplayName(appId).charAt(0).toUpperCase()) : /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: "macwindow",
    size: Math.round(size * 0.5),
    style: {
      color: 'rgba(255,255,255,.85)'
    }
  }));
}
Object.assign(__ds_scope, { SAMPLE_APPS, appDisplayName, AppIcon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/AppIcon.jsx", error: String((e && e.message) || e) }); }

// components/brand/CodeEditor.jsx
try { (() => {
// Row height in px for the gutter/pre/textarea to share. --text-default is 13px and the editor's
// own line-height is the unitless multiplier 1.45 (both from tokens/typography.css); this is a
// literal rather than a getComputedStyle read so gutter rows line up without a measuring effect.
// ponytail: bump this if --text-default or the 1.45 line-height ever change.
const LINE_HEIGHT = 1.45;
const FONT_PX = 13;
const ROW_PX = FONT_PX * LINE_HEIGHT;

// Tightened vs. the proposal's own sketch (`^\s*[\[\[]?[^\[\]=]+[\]\]]?\s*$`, proposal-rawtoml.md
// §2.2), which — read literally — also matches plain non-bracket lines since the brackets are each
// optional. Requiring the brackets is what "is this a header line" actually means.
const HEADER_RE = /^\[{1,2}[^\[\]=]+\]{1,2}$/;
const KEY_RE = /^(\s*)([A-Za-z0-9_.\-"]+)(\s*=)/;
function isHeaderLine(code) {
  return HEADER_RE.test(code.trim());
}

// ponytail: naive — doesn't skip a `#` inside a quoted string (`key = "a # not a comment"`).
// Called out as an acknowledged mockup simplification in proposal-rawtoml.md §2.2; the real
// tokenizer needs to walk string spans before looking for `#`.
function splitComment(line) {
  const i = line.indexOf('#');
  return i === -1 ? [line, ''] : [line.slice(0, i), line.slice(i)];
}

// Three tiers, not four — structure (headers), the thing you'd search for (keys), and comments get
// a span; everything else (strings/numbers/booleans/dates/punctuation/the `=` itself) inherits the
// <pre>'s own secondary-opacity color. Deliberately not a per-value-type rainbow scheme — see
// proposal-rawtoml.md §1/§2.2 for why.
const TOKEN_STYLE = {
  header: {
    color: 'var(--accent)',
    fontWeight: 'var(--weight-medium)'
  },
  comment: {
    color: 'var(--label-tertiary)',
    fontWeight: 'var(--weight-regular)'
  },
  key: {
    color: 'var(--label)',
    fontWeight: 'var(--weight-medium)'
  }
};
function renderLine(line, headerLineSet, lineNum) {
  const [code, comment] = splitComment(line);
  const nodes = [];
  if (headerLineSet.has(lineNum)) {
    nodes.push(/*#__PURE__*/React.createElement("span", {
      key: "h",
      style: TOKEN_STYLE.header
    }, code));
  } else {
    const m = code.match(KEY_RE);
    if (m) {
      nodes.push(m[1]);
      nodes.push(/*#__PURE__*/React.createElement("span", {
        key: "k",
        style: TOKEN_STYLE.key
      }, m[2]));
      nodes.push(code.slice(m[1].length + m[2].length));
    } else if (code) {
      nodes.push(code);
    }
  }
  if (comment) nodes.push(/*#__PURE__*/React.createElement("span", {
    key: "c",
    style: TOKEN_STYLE.comment
  }, comment));
  return nodes;
}

/* Editable text that is code, not prose: 13px monospaced (matches every other monospaced element
   in the window — key/command rows, the version string), 10/12px container inset, on
   textBackgroundColor. In the app this is an NSTextView with every macOS text substitution
   turned off — smart quotes would turn a valid TOML string into an invalid one.

   Also owns (proposal-rawtoml.md §2.1-§2.3): a line-number gutter, restrained 3-tier TOML
   highlighting, and inline error/warning gutter markers. Built via the highlighted-<pre>-under-a-
   transparent-<textarea> overlay technique — the textarea stays the single source of truth for
   editing/selection/caret; the <pre> underneath only paints. The outer element auto-grows to its
   content and owns vertical scroll (no nested scrollbars), which is also what keeps the gutter in
   lockstep with the text for free. Search-in-editor (⌘F) is not part of this component — see the
   comment in RawTomlTab.jsx.

   `ref` exposes one imperative method, `scrollToLine(line)`, for callers that need to jump the
   caret to a known line (a picked "Sections…" entry, a clicked error) — the React equivalent of
   the real NSTextView's `scrollRangeToVisible`/`setSelectedRange`, which only the view that owns
   the text storage can drive. */
const CodeEditor = React.forwardRef(function CodeEditor({
  value = '',
  onChange,
  readOnly = false,
  errorLine = null,
  warningLines = [],
  onCursorMove,
  sectionHeaders,
  style
}, ref) {
  const taRef = React.useRef(null);
  const scrollRef = React.useRef(null);
  const [height, setHeight] = React.useState(120);
  const lines = React.useMemo(() => value.split('\n'), [value]);

  // Section headers are derived by the tab from the same buffer (so the Sections… menu and this
  // highlighting can't disagree) and passed down; fall back to our own scan so the component still
  // works standalone.
  const headerLineSet = React.useMemo(() => {
    if (sectionHeaders) return new Set(sectionHeaders.map(h => h.line));
    const set = new Set();
    lines.forEach((line, i) => {
      if (isHeaderLine(splitComment(line)[0])) set.add(i + 1);
    });
    return set;
  }, [sectionHeaders, lines]);
  React.useLayoutEffect(() => {
    const ta = taRef.current;
    if (!ta) return;
    ta.style.height = 'auto'; // release the explicit height so scrollHeight reflects real content
    setHeight(Math.max(120, ta.scrollHeight));
  }, [value]);
  React.useImperativeHandle(ref, () => ({
    scrollToLine(line) {
      const ta = taRef.current;
      if (!ta) return;
      const clamped = Math.max(1, Math.min(line, lines.length));
      const pos = lines.slice(0, clamped - 1).reduce((n, l) => n + l.length + 1, 0);
      ta.focus();
      ta.setSelectionRange(pos, pos);
      if (onCursorMove) onCursorMove(clamped, 1);
      const rowTop = (clamped - 1) * ROW_PX;
      if (scrollRef.current) scrollRef.current.scrollTo({
        top: Math.max(0, rowTop - ROW_PX * 3),
        behavior: 'smooth'
      });
    }
  }), [lines, onCursorMove]);
  const reportCursor = e => {
    if (!onCursorMove) return;
    const before = value.slice(0, e.target.selectionStart).split('\n');
    onCursorMove(before.length, before[before.length - 1].length + 1);
  };
  const digits = Math.max(3, String(lines.length).length);
  // Shared so the <pre> and <textarea> glyphs land exactly on top of one another.
  const fontStack = {
    fontFamily: 'var(--font-mono)',
    fontSize: 'var(--text-default)',
    lineHeight: LINE_HEIGHT,
    tabSize: 4,
    padding: '12px 10px',
    boxSizing: 'border-box',
    // ponytail: wrapping stays on (unchanged from the plain-textarea original), so the gutter is a
    // naive one-row-per-source-line numbering rather than wrap-fragment-aware — a long wrapped
    // line's continuation rows won't get their own gutter row. Real fix is an NSRulerView driven by
    // NSLayoutManager's line fragments (see proposal-rawtoml.md §4); not worth it for a mockup of
    // config files that are typically short `key = value` lines.
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
    overflowWrap: 'break-word'
  };
  return /*#__PURE__*/React.createElement("div", {
    ref: scrollRef,
    style: {
      flex: 1,
      minHeight: 0,
      display: 'flex',
      overflowY: 'auto',
      background: 'var(--text-bg)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: '0 0 auto',
      width: `calc(${digits}ch + 22px)`,
      background: 'var(--fill-subtle)',
      borderRight: '1px solid var(--separator)',
      paddingTop: 12,
      paddingBottom: 12,
      boxSizing: 'border-box'
    }
  }, lines.map((_, i) => {
    const n = i + 1;
    const kind = n === errorLine ? 'error' : warningLines.includes(n) ? 'warning' : null;
    const color = kind === 'error' ? 'var(--status-error)' : kind === 'warning' ? 'var(--status-warning)' : 'var(--label-tertiary)';
    return /*#__PURE__*/React.createElement("div", {
      key: n,
      style: {
        position: 'relative',
        lineHeight: ROW_PX + 'px',
        fontSize: 'var(--text-subheadline)',
        fontFamily: 'var(--font-system)',
        color,
        textAlign: 'right',
        paddingRight: 8,
        paddingLeft: 6
      }
    }, kind && /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'absolute',
        left: 0,
        top: 0,
        bottom: 0,
        width: 3,
        background: color
      }
    }), n);
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      position: 'relative',
      height
    }
  }, /*#__PURE__*/React.createElement("pre", {
    style: {
      margin: 0,
      position: 'absolute',
      inset: 0,
      pointerEvents: 'none',
      color: 'var(--label-secondary)',
      ...fontStack
    }
  }, lines.map((line, i) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: i
  }, i > 0 && '\n', renderLine(line, headerLineSet, i + 1)))), /*#__PURE__*/React.createElement("textarea", {
    ref: taRef,
    value: value,
    readOnly: readOnly,
    spellCheck: false,
    onChange: e => {
      onChange && onChange(e.target.value);
      reportCursor(e);
    },
    onSelect: reportCursor,
    onClick: reportCursor,
    onKeyUp: reportCursor,
    style: {
      position: 'absolute',
      top: 0,
      left: 0,
      width: '100%',
      height,
      resize: 'none',
      border: 'none',
      outline: 'none',
      background: 'transparent',
      color: 'transparent',
      caretColor: 'var(--label)',
      ...fontStack
    }
  })));
});
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
      boxShadow: 'inset 0 0 0 1px var(--border-control)',
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

// components/brand/MonitorArrangement.jsx
try { (() => {
/* A schematic "Displays preference pane" diagram: one rectangle per connected monitor, scaled
   and positioned from its real `rect` (topLeftX/Y, width, height — points, top-left origin, the
   same numbers `aerospork list-monitors --format '%{monitor-fingerprint}'` prints). This is the
   thing a table of "Position 2" numbers can't give you: where a monitor actually sits relative
   to the others. Every rectangle is a real <button>, not a decorative shape, so selecting one
   works the same by click or by Tab + Enter/Space. The main monitor gets a thin accent bar along
   its top edge — the same "this is where the menu bar lives" cue macOS's own Displays pane uses,
   which is also the most direct answer to "why is this one called main". */
function MonitorArrangement({ monitors = [], selected, onSelect, width = 560, height = 130 }) {
  if (!monitors.length) return null;
  const pad = 14;
  const minX = Math.min(...monitors.map((m) => m.rect.x));
  const minY = Math.min(...monitors.map((m) => m.rect.y));
  const maxX = Math.max(...monitors.map((m) => m.rect.x + m.rect.width));
  const maxY = Math.max(...monitors.map((m) => m.rect.y + m.rect.height));
  const scale = Math.min((width - pad * 2) / (maxX - minX), (height - pad * 2) / (maxY - minY));
  const offX = (width - (maxX - minX) * scale) / 2;
  const offY = (height - (maxY - minY) * scale) / 2;
  return /*#__PURE__*/React.createElement("div", { style: {
    position: "relative",
    width,
    height,
    flex: "0 0 auto",
    boxSizing: "border-box",
    borderRadius: "var(--radius-card)",
    background: "var(--fill-subtle)",
    boxShadow: "inset 0 0 0 1px var(--border-control)"
  } }, monitors.map((m, i) => {
    const on = m.id === selected;
    const w = m.rect.width * scale;
    const h = m.rect.height * scale;
    const showName = w >= 56;
    const showRes = w >= 96 && h >= 46;
    return /*#__PURE__*/React.createElement(
      "button",
      {
        key: m.id,
        type: "button",
        "aria-pressed": on,
        "aria-label": m.name + ", position " + (i + 1) + (m.isMain ? ", main display" : "") + ", " + m.resolution,
        title: m.name + " — " + m.resolution,
        onClick: () => onSelect && onSelect(m.id),
        style: {
          position: "absolute",
          left: offX + (m.rect.x - minX) * scale,
          top: offY + (m.rect.y - minY) * scale,
          width: w,
          height: h,
          boxSizing: "border-box",
          padding: 0,
          margin: 0,
          cursor: "pointer",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 2,
          background: on ? "var(--accent-selection-fill)" : "var(--control-bg)",
          border: on ? "1.5px solid var(--accent)" : "1px solid var(--border-control)",
          borderRadius: "var(--radius-field)",
          boxShadow: on ? "0 2px 8px rgba(0,0,0,.14)" : "0 0.5px 1.5px rgba(0,0,0,.1)",
          transition: "background var(--dur-control) var(--ease-standard), box-shadow var(--dur-control) var(--ease-standard)"
        }
      },
      m.isMain && /*#__PURE__*/React.createElement("span", { "aria-hidden": "true", style: {
        position: "absolute",
        top: 0,
        left: "18%",
        right: "18%",
        height: 3,
        borderRadius: "0 0 2px 2px",
        background: "var(--accent)"
      } }),
      /*#__PURE__*/React.createElement("span", { "aria-hidden": "true", style: {
        position: "absolute",
        top: 3,
        left: 4,
        font: "var(--weight-medium) var(--text-caption2)/1 var(--font-mono)",
        color: "var(--label-tertiary)"
      } }, i + 1),
      showName && /*#__PURE__*/React.createElement("span", { style: {
        font: "var(--weight-medium) var(--text-caption)/1.2 var(--font-system)",
        color: "var(--label)",
        maxWidth: "90%",
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
        textAlign: "center"
      } }, m.name),
      showRes && /*#__PURE__*/React.createElement("span", { style: {
        font: "var(--weight-regular) var(--text-caption2)/1 var(--font-mono)",
        color: "var(--label-tertiary)"
      } }, m.resolution)
    );
  }));
}
Object.assign(__ds_scope, { MonitorArrangement });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/MonitorArrangement.jsx", error: String((e && e.message) || e) }); }

// components/brand/WindowChrome.jsx
try { (() => {
/* Neutral screenshot approximation of a native macOS window. */
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
      height: 32,
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

// components/controls/IconButton.jsx
try { (() => {
/* Icon-only .buttonStyle(.borderless) button. `label` is mandatory: it doubles as the tooltip
   and the accessible name, recreating SwiftUI's .help() + .accessibilityLabel() pair, so it is
   written as a name ("Remove “alt-h”"), not an instruction. `role="destructive"` tints the icon
   red only on hover/press — it stays label-secondary at rest, matching AppKit's own
   borderless-destructive button rather than flagging the row as already wrong. */
function IconButton({
  systemImage,
  label,
  size = 14,
  role,
  onClick,
  style
}) {
  const [hover, setHover] = React.useState(false);
  const destructive = role === 'destructive';
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    title: label,
    "aria-label": label,
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      height: 22,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '0 var(--space-5)',
      background: 'transparent',
      border: '1px solid transparent',
      borderRadius: 'var(--radius-field)',
      cursor: 'pointer',
      boxSizing: 'border-box',
      color: destructive && hover ? 'var(--sys-red)' : 'var(--label-secondary)',
      ...style
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    sf: systemImage,
    size: size
  }));
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/IconButton.jsx", error: String((e && e.message) || e) }); }

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
      color: 'color-mix(in srgb, var(--label) 72%, transparent)',
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
  'trash': 'trash-2',
  'line.3.horizontal': 'menu',
  'eye': 'eye',
  'envelope': 'mail',
  'safari': 'compass',
  'music.note': 'music',
  'message': 'message-circle',
  'folder': 'folder'
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
  "panel-left": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /><path d=\"M9 3v18\" />",
  "menu": "<path d=\"M4 12h16\" /><path d=\"M4 18h16\" /><path d=\"M4 6h16\" />",
  "eye": "<path d=\"M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0\" /><circle cx=\"12\" cy=\"12\" r=\"3\" />",
  "mail": "<rect width=\"20\" height=\"16\" x=\"2\" y=\"4\" rx=\"2\" /><path d=\"m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7\" />",
  "compass": "<path d=\"m16.24 7.76-1.804 5.411a2 2 0 0 1-1.264 1.264L7.76 16.24l1.804-5.411a2 2 0 0 1 1.264-1.264z\" /><circle cx=\"12\" cy=\"12\" r=\"10\" />",
  "music": "<path d=\"M9 18V5l12-2v13\" /><circle cx=\"6\" cy=\"18\" r=\"3\" /><circle cx=\"18\" cy=\"16\" r=\"3\" />",
  "message-circle": "<path d=\"M7.9 20A9 9 0 1 0 4 16.1L2 22Z\" />",
  "folder": "<path d=\"M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.9 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z\" />"
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

// components/controls/KeyCaps.jsx
try { (() => {
const GLYPHS = {
  ctrl: '⌃',
  alt: '⌥',
  shift: '⇧',
  cmd: '⌘'
};

/* One keyboard key = one keycap chip: a real-key metaphor for a binding's key notation, read
   verbatim off the keyboard rather than parsed out of a packed mono string like "⌥⇧h". Modifiers
   render as glyphs, exactly like PrettyKey; the difference is one bordered cap per token instead
   of one run-on span, which is both more scannable in a list and more literally "what you'd
   press". Read-only: the editable equivalent is KeyRecorderField, which renders its filled state
   with this same component (bordered=false, so it doesn't nest a box inside its own box). */
function KeyCaps({
  notation = '',
  size = 12,
  bordered = true
}) {
  if (!notation) return null;
  const parts = notation.split('-');
  const key = parts.pop();
  const caps = [...parts.map(p => GLYPHS[p] || p), key.length === 1 ? key.toUpperCase() : key];
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 3
    }
  }, caps.map((c, i) => /*#__PURE__*/React.createElement("kbd", {
    key: i,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      minWidth: size + 10,
      height: size + 10,
      padding: '0 5px',
      boxSizing: 'border-box',
      borderRadius: 4,
      border: 'none',
      fontStyle: 'normal',
      background: bordered ? 'var(--control-bg)' : 'var(--fill)',
      boxShadow: bordered ? '0 0.5px 1.5px rgba(0,0,0,.14), inset 0 0 0 var(--border-hairline) var(--border-control)' : 'none',
      font: `var(--weight-medium) ${size}px/1 var(--font-mono)`,
      color: 'var(--label)'
    }
  }, c)));
}
Object.assign(__ds_scope, { GLYPHS, KeyCaps });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/KeyCaps.jsx", error: String((e && e.message) || e) }); }

// components/controls/KeyRecorderField.jsx
try { (() => {
/** aerospork notation ("alt-shift-h") rendered with real modifier glyphs ("⌥⇧h").
    Capitalized because only capitalized exports reach the design-system namespace. */
function PrettyKey(notation = '') {
  const parts = notation.split('-');
  if (parts.length < 2) return notation;
  const key = parts.pop();
  return parts.map(p => __ds_scope.GLYPHS[p] || p + '-').join('') + key;
}

/* Click, then press a shortcut. Armed state is accent-tinted with a 2px accent border —
   the same treatment the hand-drawn NSView uses. A filled, un-armed value renders as keycap
   chips (bordered=false, since the field itself already draws the border) rather than one run-on
   PrettyKey string — the same "one key, one cap" treatment as a read-only KeyCaps row. */
function KeyRecorderField({
  notation = '',
  recording = false,
  onArm,
  onClear,
  showsClear = true,
  width = 170
}) {
  const placeholder = recording ? 'Press a shortcut…' : 'Click to record';
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
  }, notation ? /*#__PURE__*/React.createElement(__ds_scope.KeyCaps, {
    notation: notation,
    size: 11,
    bordered: false
  }) : placeholder), showsClear && notation && /*#__PURE__*/React.createElement("button", {
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
   separators, and a full-width accent selection. A row is also a keyboard stop — Tab to it,
   Enter or Space selects it, the same handler a click uses. */
function DataTable({ columns = [], rows = [], selected, onSelect, emptyState }) {
  if (!rows.length && emptyState) return emptyState;
  const grid = columns.map((c) => c.width || "1fr").join(" ");
  return /*#__PURE__*/React.createElement("div", { style: { flex: 1, minHeight: 0, overflow: "auto", background: "var(--control-bg)" } }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gridTemplateColumns: grid,
      gap: "var(--space-8)",
      padding: "4px var(--space-12)",
      borderBottom: "var(--divider)",
      font: "var(--weight-regular) var(--text-subheadline)/1.2 var(--font-system)",
      color: "var(--label-secondary)",
      position: "sticky",
      top: 0,
      background: "var(--control-bg)"
    }
  }, columns.map((c) => /*#__PURE__*/React.createElement("span", { key: c.key }, c.title))), rows.map((r) => {
    const on = selected === r.id;
    return /*#__PURE__*/React.createElement(
      "div",
      {
        key: r.id,
        tabIndex: 0,
        onClick: () => onSelect && onSelect(r.id),
        onKeyDown: (e) => {
          if ((e.key === "Enter" || e.key === " ") && onSelect) {
            e.preventDefault();
            onSelect(r.id);
          }
        },
        style: {
          display: "grid",
          gridTemplateColumns: grid,
          gap: "var(--space-8)",
          alignItems: "center",
          padding: "3px var(--space-12)",
          borderBottom: "var(--divider)",
          cursor: "default",
          background: on ? "var(--selection)" : "transparent",
          color: on ? "var(--selection-fg)" : "var(--label)"
        }
      },
      columns.map((c) => /*#__PURE__*/React.createElement("div", { key: c.key, style: { minWidth: 0 } }, c.render ? c.render(r, on) : r[c.key]))
    );
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

// components/layout/PanelHeader.jsx
try { (() => {
/* SectionLabel pre-wrapped with the padding a Form section header gets for free from
   .formStyle(.grouped) — for a tab whose layout isn't a Form (a list pane, a split-view list),
   so its header still lines up with a Form tab's header. Fixed: horizontal 16 / top 14 / bottom 8. */
function PanelHeader({
  title,
  sf,
  style
}) {
  return /*#__PURE__*/React.createElement(__ds_scope.SectionLabel, {
    title: title,
    sf: sf,
    style: {
      padding: 'var(--space-14) var(--space-16) var(--space-8)',
      ...style
    }
  });
}
Object.assign(__ds_scope, { PanelHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/PanelHeader.jsx", error: String((e && e.message) || e) }); }

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
      padding: '7px 14px ' + (hint ? '3px' : '7px')
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
/* Stable, non-customizable pane toolbar used by a macOS app Settings window. */
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
      flex: '0 0 auto',
      padding: '8px var(--space-12) 9px',
      background: 'var(--bar-bg)',
      backdropFilter: 'blur(var(--bar-blur))',
      WebkitBackdropFilter: 'blur(var(--bar-blur))',
      borderBottom: 'var(--divider)',
      overflowX: 'auto'
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
        background: on ? 'var(--fill)' : 'transparent',
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
    lines: ['Fork notes', '— monitor identity by UUID', '— settings GUI, seven panes']
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
const { WindowChrome, TabBar, Banner } = window.AeroSporkDesignSystem_078bd7;
const TABS = [
  { id: "general", label: "General", sf: "gearshape" },
  { id: "gaps", label: "Gaps", sf: "rectangle.split.3x3" },
  { id: "keys", label: "Keys", sf: "keyboard" },
  { id: "monitors", label: "Monitors", sf: "display.2" },
  { id: "events", label: "Events", sf: "bolt" },
  { id: "rules", label: "Window Rules", sf: "macwindow.badge.plus" },
  { id: "raw", label: "Raw TOML", sf: "doc.plaintext" }
];

function SettingsApp({ framed = true, initialTab = "general", banner = null, width = 880, height = 620 }) {
  const D = window.AS_DATA;
  const [tab, setTab] = React.useState(initialTab);
  const currentTab = TABS.find((t) => t.id === tab) || TABS[0];
  const [settings, setSettings] = React.useState({
    startAtLogin: true,
    unhide: true,
    autoMove: true,
    menuBarIcon: true,
    dockIcon: false,
    layout: "tiles",
    orientation: "auto",
    accordionPadding: 30,
    flatten: true,
    alternate: true,
    keyMapping: "qwerty",
    innerH: 8,
    innerV: 8,
    outerTop: 32,
    outerBottom: 8,
    outerLeft: 8,
    outerRight: 8
  });
  const set = (k, v) => setSettings((s) => ({ ...s, [k]: v }));
  const [bindings, setBindings] = React.useState(D.bindings);
  const [assignments, setAssignments] = React.useState(D.assignments);
  const [rules, setRules] = React.useState(D.rules);
  const [events, setEvents] = React.useState(D.events);
  const [env, setEnv] = React.useState(D.env);
  const [inherit, setInherit] = React.useState(true);
  const [toml, setToml] = React.useState(D.toml);

  const body = /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(TabBar, { tabs: TABS, value: tab, onChange: setTab }), /*#__PURE__*/React.createElement("div", { className: "tab-body" }, banner === "error" && /*#__PURE__*/React.createElement(Banner, { kind: "error" }, "Your config was not loaded — AeroSpork is running built-in defaults. Fix the errors below and save; the config reloads by itself.\nline 12: unknown key ‘mods’"), tab === "general" && /*#__PURE__*/React.createElement(GeneralTab, { s: settings, set }), tab === "gaps" && /*#__PURE__*/React.createElement(GapsTab, { s: settings, set }), tab === "keys" && /*#__PURE__*/React.createElement(KeysTab, { bindings, setBindings }), tab === "monitors" && /*#__PURE__*/React.createElement(MonitorsTab, { monitors: D.monitors, assignments, setAssignments, workspaces: D.workspaces }), tab === "events" && /*#__PURE__*/React.createElement(EventsTab, { events, setEvents, env, setEnv, inherit, setInherit }), tab === "rules" && /*#__PURE__*/React.createElement(RulesTab, { rules, setRules }), tab === "raw" && /*#__PURE__*/React.createElement(RawTomlTab, { toml, setToml, original: D.toml })));
  if (!framed) return /*#__PURE__*/React.createElement("div", { className: "settings-plain" }, body);
  return /*#__PURE__*/React.createElement(WindowChrome, { title: currentTab.label, width, height }, body);
}
Object.assign(window, { SettingsApp, SETTINGS_TABS: TABS });
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/App.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/EventsTab.jsx
try { (() => {
const {
  FormSection,
  SectionLabel,
  TextField,
  Button,
  Icon,
  IconButton,
  Toggle,
  SettingsHint
} = window.AeroSporkDesignSystem_078bd7;
function CommandRows({
  title,
  sf,
  footer,
  list,
  onChange,
  placeholder
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
  }, "Nothing here yet. Anything you add runs every time this event fires \u2014 exec-and-forget for a shell command, or an aerospork command directly.") : /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      display: 'flex',
      gap: 8,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    value: c,
    placeholder: placeholder,
    onChange: v => set(i, v),
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(IconButton, {
    systemImage: "minus.circle",
    role: "destructive",
    label: c.trim() ? 'Remove “' + c + '”' : 'Remove command',
    onClick: () => onChange(list.filter((_, j) => j !== i))
  }))), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    style: {
      color: 'var(--label)'
    },
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
    placeholder: "exec-and-forget open -a Terminal",
    footer: "Runs once, after AeroSpork finishes launching. Multiple commands run in order, top to bottom."
  }), /*#__PURE__*/React.createElement(CommandRows, {
    title: "Focused workspace changed",
    sf: "rectangle.on.rectangle",
    list: events.workspaceChanged,
    onChange: set('workspaceChanged'),
    placeholder: "exec-and-forget open -a Terminal",
    footer: "Every workspace switch, including switches within one monitor. `move-mouse window-lazy-center` here is what makes the pointer follow you."
  }), /*#__PURE__*/React.createElement(CommandRows, {
    title: "Focused monitor changed",
    sf: "display.2",
    list: events.monitorChanged,
    onChange: set('monitorChanged'),
    placeholder: "move-mouse monitor-lazy-center",
    footer: "Only when focus moves to a different monitor."
  }), /*#__PURE__*/React.createElement(CommandRows, {
    title: "Focus changed",
    sf: "scope",
    list: events.focusChanged,
    onChange: set('focusChanged'),
    placeholder: "move-mouse window-lazy-center",
    footer: "Any focus change at all: window, workspace or monitor. Fires the most often \u2014 keep it cheap."
  }), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Environment for exec commands",
      sf: "terminal"
    }),
    footer: "`exec-and-forget` and every command above run with this environment. `PATH` is the one people usually need. Commands with a window or workspace target also get `AEROSPORK_WINDOW_ID` or `AEROSPORK_WORKSPACE`, and workspace-change commands get `AEROSPORK_FOCUSED_WORKSPACE` and `AEROSPORK_PREV_WORKSPACE`. `aerospork list-exec-env-vars` shows the environment they all start from."
  }, /*#__PURE__*/React.createElement(Toggle, {
    label: "Inherit AeroSpork's environment",
    checked: inherit,
    onChange: setInherit
  }), inherit && /*#__PURE__*/React.createElement(SettingsHint, null, "Every command on this page runs with AeroSpork's full environment, including anything sensitive in it. Turn this off and list only what you need below."), env.map(v => /*#__PURE__*/React.createElement("div", {
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
    placeholder: "/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}",
    style: {
      flex: 1
    },
    onChange: nv => setEnv(env.map(e => e.id === v.id ? {
      ...e,
      value: nv
    } : e))
  }), /*#__PURE__*/React.createElement(IconButton, {
    systemImage: "minus.circle",
    role: "destructive",
    label: v.name.trim() ? 'Remove “' + v.name + '”' : 'Remove variable',
    onClick: () => setEnv(env.filter(e => e.id !== v.id))
  }))), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    style: {
      color: 'var(--label)'
    },
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
  GapsPreview,
  Toggle,
  StatusLabel
} = window.AeroSporkDesignSystem_078bd7;
function GapsTab({
  s,
  set
}) {
  const D = window.AS_DATA;
  // Seeded once from the loaded values, not recomputed on every render — otherwise typing a
  // field toward a matching value would make its row disappear mid-edit.
  const [innerLinked, setInnerLinked] = React.useState(() => s.innerH === s.innerV);
  const [outerLinked, setOuterLinked] = React.useState(() => s.outerTop === s.outerBottom && s.outerBottom === s.outerLeft && s.outerLeft === s.outerRight);
  return /*#__PURE__*/React.createElement("div", {
    className: "tab-column"
  }, /*#__PURE__*/React.createElement("div", {
    className: "form-page"
  }, /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Preview",
      sf: "eye"
    }),
    footer: D.gapsHavePerMonitorOverrides ? /*#__PURE__*/React.createElement(StatusLabel, {
      kind: "neutral"
    }, "Some of these gaps have per-monitor rules set in Raw TOML \u2014 editing any value below replaces the whole section with flat numbers.") : null
  }, /*#__PURE__*/React.createElement("div", {
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
  }, /*#__PURE__*/React.createElement(Toggle, {
    label: "Same value for both",
    checked: innerLinked,
    onChange: v => {
      setInnerLinked(v);
      if (v) set('innerV', s.innerH);
    }
  }), innerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "Horizontal & vertical",
    value: s.innerH,
    onChange: v => {
      set('innerH', v);
      set('innerV', v);
    }
  }), !innerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "Horizontal",
    value: s.innerH,
    onChange: v => set('innerH', v)
  }), !innerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "Vertical",
    value: s.innerV,
    onChange: v => set('innerV', v)
  })), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Around the screen",
      sf: "rectangle.inset.filled"
    }),
    footer: "The top gap is measured below the menu bar, so 0 is flush with the usable area."
  }, /*#__PURE__*/React.createElement(Toggle, {
    label: "Same on all sides",
    checked: outerLinked,
    onChange: v => {
      setOuterLinked(v);
      if (v) {
        set('outerBottom', s.outerTop);
        set('outerLeft', s.outerTop);
        set('outerRight', s.outerTop);
      }
    }
  }), outerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "All sides",
    value: s.outerTop,
    onChange: v => {
      set('outerTop', v);
      set('outerBottom', v);
      set('outerLeft', v);
      set('outerRight', v);
    }
  }), !outerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "Top",
    value: s.outerTop,
    onChange: v => set('outerTop', v)
  }), !outerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "Bottom",
    value: s.outerBottom,
    onChange: v => set('outerBottom', v)
  }), !outerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "Left",
    value: s.outerLeft,
    onChange: v => set('outerLeft', v)
  }), !outerLinked && /*#__PURE__*/React.createElement(NumberField, {
    title: "Right",
    value: s.outerRight,
    onChange: v => set('outerRight', v)
  }))), /*#__PURE__*/React.createElement(SettingsFooter, null, "Raw TOML can set a different value per monitor for any of these six gaps. Editing a gap here always writes one flat number for every monitor. Use Raw TOML for per-monitor rules."));
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
  // v3: the page header (icon + "General") now lives once in App.jsx, shared by every tab, so
  // this file starts straight into content. The six sections are unchanged in count, order and
  // copy — the only new thing is a two-column card grid instead of one long column, which the
  // extra width the sidebar redesign keeps available (see tokens/spacing.css) makes room for.
  // Pairs read top to bottom, left column then right: startup+menu bar, layout+normalization,
  // keyboard+about — related, similarly short sections next to each other.
  return /*#__PURE__*/React.createElement("div", {
    className: "form-page",
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 'var(--space-16)',
      alignItems: 'start'
    }
  }, /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "Startup & behaviour",
      sf: "power"
    }),
    footer: "Automatically unhiding macOS hidden apps undoes \u2318H so a hidden window keeps tiling. Moving workspaces on monitor connect puts each one back on the monitor you pinned it to; off, a workspace stays wherever it landed when that monitor disappeared."
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
      title: "Menu bar & Dock",
      sf: "menubar.rectangle"
    }),
    footer: "AeroSpork has no window of its own, so these two icons are the quickest way back into Settings. Opening AeroSpork again, or `aerospork open-settings`, also opens this window."
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
    footer: "Auto gives wide monitors a horizontal split and tall monitors a vertical one. Layout and split direction apply to new workspaces; existing ones keep theirs. The accordion peek is how much of the window behind stays visible; 0 stacks them exactly. It applies to any accordion container, not just new workspaces."
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
    footer: "Housekeeping applied after every layout change. Turning one off leaves the tree as it is; it does not undo earlier changes. Turn both off if you want the tree to stay exactly as you built it."
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
  TextField,
  Button,
  Icon,
  KeyRecorderField,
  PrettyKey,
  KeyCaps,
  FormSection,
  SectionLabel,
  Badge,
  ContentUnavailable,
  SettingsHint,
  StatusLabel,
  IconButton,
  MenuPanel
} = window.AeroSporkDesignSystem_078bd7;

// Categories, derived from the command's leading verb (before the first ';'). Verified against
// Sources/AppBundle/command/cmdManifest.swift's CmdArgs.Kind switch: every case there maps to one
// of these four buckets or falls through to Other (list-*, move-mouse, debug-windows).
const CATEGORY_VERBS = {
  'Focus': ['focus', 'focus-monitor', 'focus-back-and-forth'],
  'Move & workspace': ['move', 'move-node-to-workspace', 'move-node-to-monitor', 'move-workspace-to-monitor', 'workspace', 'workspace-back-and-forth', 'summon-workspace'],
  'Layout & resize': ['layout', 'split', 'join-with', 'fullscreen', 'resize', 'balance-sizes', 'flatten-workspace-tree', 'macos-native-fullscreen', 'macos-native-minimize'],
  'Mode & system': ['mode', 'reload-config', 'enable', 'close', 'close-all-windows-but-current', 'volume', 'exec-and-forget', 'trigger-binding', 'config', 'open-settings']
};
const CATEGORY_ORDER = ['Focus', 'Move & workspace', 'Layout & resize', 'Mode & system', 'Other'];
// One glyph per category card header — crosshair for aim, a workspace grid, the 3-pane split
// General's own Layout section uses, a terminal for the exec/system bucket.
const CATEGORY_ICONS = {
  'Focus': 'scope',
  'Move & workspace': 'square.grid.2x2',
  'Layout & resize': 'rectangle.split.3x1',
  'Mode & system': 'terminal',
  'Other': 'ellipsis.circle'
};
function categoryFor(command) {
  const verb = command.split(';')[0].trim().split(/\s+/)[0] || '';
  for (const cat of CATEGORY_ORDER) {
    if ((CATEGORY_VERBS[cat] || []).includes(verb)) return cat;
  }
  return 'Other';
}

// A starting point for the command field's autocomplete, grounded in the real command set
// (cmdManifest.swift) — not a constraint. Selecting one fills the field; the user can still type
// or append anything, chained commands included. `quick` marks the six shown before any typing,
// one per category so the empty-state list isn't just every focus-* variant.
const COMMAND_SUGGESTIONS = [{
  cmd: 'focus left',
  cat: 'Focus',
  quick: true
}, {
  cmd: 'focus down',
  cat: 'Focus'
}, {
  cmd: 'focus up',
  cat: 'Focus'
}, {
  cmd: 'focus right',
  cat: 'Focus'
}, {
  cmd: 'focus-monitor next',
  cat: 'Focus'
}, {
  cmd: 'focus-back-and-forth',
  cat: 'Focus'
}, {
  cmd: 'move left',
  cat: 'Move & workspace'
}, {
  cmd: 'move-node-to-workspace 3',
  cat: 'Move & workspace',
  quick: true
}, {
  cmd: 'move-node-to-monitor next',
  cat: 'Move & workspace'
}, {
  cmd: 'workspace 1',
  cat: 'Move & workspace'
}, {
  cmd: 'workspace-back-and-forth',
  cat: 'Move & workspace'
}, {
  cmd: 'layout floating tiling',
  cat: 'Layout & resize',
  quick: true
}, {
  cmd: 'layout accordion',
  cat: 'Layout & resize'
}, {
  cmd: 'split horizontal',
  cat: 'Layout & resize'
}, {
  cmd: 'resize smart -50',
  cat: 'Layout & resize'
}, {
  cmd: 'fullscreen',
  cat: 'Layout & resize'
}, {
  cmd: 'mode service',
  cat: 'Mode & system',
  quick: true
}, {
  cmd: 'reload-config',
  cat: 'Mode & system',
  quick: true
}, {
  cmd: 'close-all-windows-but-current',
  cat: 'Mode & system'
}, {
  cmd: 'volume up',
  cat: 'Mode & system'
}, {
  cmd: 'exec-and-forget open -na Ghostty',
  cat: 'Mode & system',
  quick: true
}];
function commandSuggestions(query) {
  const q = query.trim().toLowerCase();
  const pool = q ? COMMAND_SUGGESTIONS.filter(s => s.cmd.toLowerCase().includes(q)) : COMMAND_SUGGESTIONS.filter(s => s.quick);
  return pool.slice(0, 6);
}

// Wraps the first hit of `needle` in a light accent mark — used in the search-primary flat list,
// never in the browse-by-category cards (there is no needle there to highlight).
function highlightMatch(text, needle) {
  if (!needle) return text;
  const i = text.toLowerCase().indexOf(needle);
  if (i === -1) return text;
  return /*#__PURE__*/React.createElement(React.Fragment, null, text.slice(0, i), /*#__PURE__*/React.createElement("mark", {
    style: {
      background: 'var(--accent-selection-fill)',
      color: 'inherit',
      borderRadius: 2
    }
  }, text.slice(i, i + needle.length)), text.slice(i + needle.length));
}

// Modes are i3-style: a named set of bindings that is either always active ("main") or entered
// and left by a binding elsewhere. Most users have never met the concept, so instead of just a
// switcher, name the entry and exit keys for the mode actually on screen — read out of the real
// bindings, not asserted in prose that can drift from them.
function describeMode(name, bindings) {
  if (name === 'main') return 'Always active — every other mode is entered from here and returns to it.';
  const entry = Object.entries(bindings).flatMap(([m, rows]) => m === name ? [] : rows.map(row => ({
    mode: m,
    row
  }))).find(({
    row
  }) => row.command.split(';')[0].trim() === 'mode ' + name);
  const exits = (bindings[name] || []).filter(row => row.command.split(';').some(c => c.trim() === 'mode main'));
  let s = entry ? 'Entered with ' + PrettyKey(entry.row.key) + ' from “' + entry.mode + '”.' : 'Entered by a “mode ' + name + '” command elsewhere.';
  if (exits.length === 1) s += ' ' + PrettyKey(exits[0].key) + ' returns to “main”.';else if (exits.length > 1) s += ' ' + PrettyKey(exits[0].key) + ' and ' + (exits.length - 1) + ' more return to “main”.';
  return s;
}
const stepLabelStyle = {
  font: 'var(--weight-medium) var(--text-subheadline)/1 var(--font-system)',
  color: 'var(--label-tertiary)'
};
const cardShellStyle = {
  background: 'var(--control-bg)',
  borderRadius: 'var(--radius-card)',
  boxShadow: '0 0 0 0.5px var(--separator)',
  overflow: 'hidden'
};

// One binding in the *active* mode: editable if it has a line to edit, read-only chips otherwise.
// Used both inside a category card (no outer padding — FormSection supplies it) and in the
// search-primary flat list (`dense`: the tighter `.binding-row` padding, so many matches still
// fit at a glance). `needle` only ever arrives non-empty in the dense/search case, to ring the key
// chips when the match was in the key rather than the command.
function BindingRow({
  b,
  needle,
  dense,
  onUpdate,
  onRemove,
  onOverride,
  onDuplicate
}) {
  const keyHit = needle && b.key.toLowerCase().includes(needle);
  return /*#__PURE__*/React.createElement("div", {
    className: dense ? 'binding-row' : undefined,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 'var(--w-recorder)',
      flex: '0 0 auto',
      display: 'flex',
      borderRadius: 6,
      boxShadow: keyHit ? 'inset 0 0 0 1.5px var(--accent)' : 'none',
      padding: keyHit ? 2 : 0
    }
  }, b.origin === 'explicit' ? /*#__PURE__*/React.createElement(KeyRecorderField, {
    notation: b.key,
    showsClear: false
  }) : /*#__PURE__*/React.createElement(KeyCaps, {
    notation: b.key
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, b.origin === 'explicit' ? /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    value: b.command,
    onChange: v => onUpdate(b.id, {
      command: v
    }),
    style: {
      width: '100%'
    }
  }) : /*#__PURE__*/React.createElement("span", {
    className: "mono cmdcell"
  }, highlightMatch(b.command, needle))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      flex: '0 0 auto'
    }
  }, b.origin === 'generated' && /*#__PURE__*/React.createElement(Badge, {
    help: "Generated from mod and workspaces. It is not written in your config file."
  }, "generated"), /*#__PURE__*/React.createElement(IconButton, {
    systemImage: "doc.on.doc",
    label: 'Duplicate “' + b.command + '”',
    onClick: () => onDuplicate(b)
  }), b.origin === 'explicit' ? /*#__PURE__*/React.createElement(IconButton, {
    systemImage: "minus.circle",
    role: "destructive",
    label: 'Remove “' + b.key + '”',
    onClick: () => onRemove(b.id)
  }) : /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: () => onOverride(b)
  }, "Override")));
}

// A match from a mode other than the active one: read-only regardless of origin (editing a
// binding you can't see the rest of is how you end up with two conflicting keys), tagged with its
// mode, and offering only "Go" — the same restriction the previous round enforced, just restyled.
function CrossModeRow({
  mode,
  row,
  needle,
  onGo
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "binding-row",
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 54,
      flex: '0 0 auto',
      color: 'var(--label-secondary)',
      fontSize: 'var(--text-callout)'
    }
  }, "\u201C", mode, "\u201D"), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 'var(--w-recorder)',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement(KeyCaps, {
    notation: row.key
  })), /*#__PURE__*/React.createElement("span", {
    className: "mono cmdcell",
    style: {
      flex: 1,
      minWidth: 0
    }
  }, highlightMatch(row.command, needle)), row.origin === 'generated' && /*#__PURE__*/React.createElement(Badge, {
    help: "Generated from mod and workspaces. It is not written in your config file."
  }, "generated"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: onGo
  }, "Go"));
}
function KeysTab({
  bindings,
  setBindings
}) {
  const [mode, setMode] = React.useState('main');
  const [query, setQuery] = React.useState('');
  const [newKey, setNewKey] = React.useState('');
  const [newCommand, setNewCommand] = React.useState('');
  const [recording, setRecording] = React.useState(false);
  const [modeMenuOpen, setModeMenuOpen] = React.useState(false);
  const [suggestOpen, setSuggestOpen] = React.useState(false);
  const all = bindings[mode] || [];
  const needle = query.trim().toLowerCase();
  const rowMatches = b => b.key.toLowerCase().includes(needle) || b.command.toLowerCase().includes(needle);
  const rows = needle ? all.filter(rowMatches) : all;
  const generated = all.filter(b => b.origin === 'generated').length;
  const explicit = all.length - generated;
  const conflict = newKey ? all.find(b => b.key === newKey) : null;
  const deleteModeLabel = 'Delete “' + mode + '”' + (explicit > 0 ? ' — ' + explicit + (explicit === 1 ? ' binding' : ' bindings') : '');

  // Real mode list (main first, then alphabetical) — the pills below used to be a SegmentedPicker
  // hardcoded to ['main', 'service'], which meant a config with a third mode (this mock's "apps")
  // had no way to reach it from the GUI at all. Deriving it from the data fixes that, and scrolls
  // rather than overflows if someone has many modes, instead of relying on a fixed width fitting.
  const modeNames = ['main', ...Object.keys(bindings).filter(m => m !== 'main').sort()];
  const otherModeNames = modeNames.filter(m => m !== mode);
  const crossModeRowMatches = needle ? otherModeNames.flatMap(m => (bindings[m] || []).filter(rowMatches).map(row => ({
    mode: m,
    row
  }))) : [];
  const otherModesWithMatches = needle ? otherModeNames.filter(m => (bindings[m] || []).some(rowMatches)) : [];
  const isSearching = !!needle;
  let emptyTitle, emptyMessage, emptyActionTitle, emptyAction;
  if (isSearching) {
    emptyTitle = 'No matches';
    emptyMessage = 'Nothing in “' + mode + '” matches “' + query + '”.' + (otherModesWithMatches.length === 1 ? ' It’s bound in “' + otherModesWithMatches[0] + '” instead.' : otherModesWithMatches.length >= 2 ? ' It’s bound in other modes.' : '');
    emptyActionTitle = otherModesWithMatches.length === 1 ? 'Go to “' + otherModesWithMatches[0] + '”' : 'Clear filter';
    emptyAction = otherModesWithMatches.length === 1 ? () => setMode(otherModesWithMatches[0]) : () => setQuery('');
  } else {
    // Empty states teach the feature rather than announce emptiness — point straight at the
    // composer that fixes it, the way Window Rules' empty state points at "Add".
    emptyTitle = 'No bindings yet';
    emptyMessage = '“' + mode + '” mode has no bindings. Record a shortcut below and describe what it does to add the first one.';
    emptyActionTitle = undefined;
    emptyAction = undefined;
  }
  const crossModeKeyMatches = newKey ? otherModeNames.filter(m => (bindings[m] || []).some(b => b.key === newKey)) : [];
  const crossModeKeyMessage = (() => {
    const count = crossModeKeyMatches.length;
    if (count === 0) return '';
    if (count === 1) return 'Also bound in “' + crossModeKeyMatches[0] + '” mode.';
    const named = crossModeKeyMatches.slice(0, 2).map(m => '“' + m + '”').join(', ');
    const extra = count > 2 ? ', and ' + (count - 2) + ' more' : '';
    return 'Also bound in ' + named + extra + ' mode' + (count > 1 ? 's' : '') + '.';
  })();
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
  // Duplicate to a second key: seed the command, leave the key recorder empty to record.
  const duplicate = b => {
    setNewCommand(b.command);
    setNewKey('');
  };
  const suggestions = commandSuggestions(newCommand);
  const categoriesPresent = CATEGORY_ORDER.filter(cat => all.some(b => categoryFor(b.command) === cat));
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
  }, /*#__PURE__*/React.createElement("div", {
    className: "mode-pills"
  }, modeNames.map(m => /*#__PURE__*/React.createElement("button", {
    key: m,
    type: "button",
    className: 'mode-pill' + (m === mode ? ' on' : ''),
    onClick: () => setMode(m)
  }, m)), /*#__PURE__*/React.createElement(IconButton, {
    systemImage: "plus.circle",
    label: "New mode\u2026",
    onClick: () => {}
  })), mode !== 'main' && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    iconOnly: true,
    title: "Mode actions",
    onClick: () => setModeMenuOpen(v => !v)
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "ellipsis.circle",
    size: 15
  })), modeMenuOpen && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: '100%',
      left: 0,
      marginTop: 4,
      zIndex: 10
    }
  }, /*#__PURE__*/React.createElement(MenuPanel, {
    width: 220,
    items: [{
      label: deleteModeLabel,
      onClick: () => setModeMenuOpen(false)
    }]
  }))), /*#__PURE__*/React.createElement("div", {
    className: "filter",
    style: {
      flex: '0 1 300px',
      minWidth: 160,
      padding: '5px 10px',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "magnifyingglass",
    size: 12,
    style: {
      color: 'var(--label-secondary)'
    }
  }), /*#__PURE__*/React.createElement(TextField, {
    variant: "plain",
    placeholder: "key or command, e.g. focus left",
    value: query,
    onChange: setQuery,
    style: {
      flex: 1,
      width: 'auto'
    }
  }), query && /*#__PURE__*/React.createElement("button", {
    className: "clear",
    onClick: () => setQuery('')
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "xmark.circle.fill",
    size: 12
  }))))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-start',
      gap: 6,
      padding: '7px 14px',
      borderBottom: 'var(--divider)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "info.circle",
    size: 12,
    style: {
      color: 'var(--label-tertiary)',
      marginTop: 1,
      flex: '0 0 auto'
    }
  }), /*#__PURE__*/React.createElement(SettingsHint, null, describeMode(mode, bindings))), /*#__PURE__*/React.createElement("div", {
    className: "form-page",
    style: {
      gap: 'var(--space-16)'
    }
  }, rows.length === 0 ? /*#__PURE__*/React.createElement(ContentUnavailable, {
    sf: isSearching ? 'magnifyingglass' : 'keyboard',
    title: emptyTitle,
    message: emptyMessage,
    actionTitle: emptyActionTitle,
    onAction: emptyAction
  }) : isSearching ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: cardShellStyle
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px 14px 4px'
    }
  }, /*#__PURE__*/React.createElement(SectionLabel, {
    title: 'Matches — ' + rows.length,
    sf: "magnifyingglass"
  })), rows.map(b => /*#__PURE__*/React.createElement(BindingRow, {
    key: b.id,
    b: b,
    needle: needle,
    dense: true,
    onUpdate: update,
    onRemove: remove,
    onOverride: override,
    onDuplicate: duplicate
  }))), crossModeRowMatches.length > 0 && /*#__PURE__*/React.createElement("div", {
    style: cardShellStyle
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px 14px 4px'
    }
  }, /*#__PURE__*/React.createElement(SectionLabel, {
    title: 'In other modes — ' + crossModeRowMatches.length,
    sf: "arrow.triangle.branch"
  })), crossModeRowMatches.map(({
    mode: m,
    row
  }) => /*#__PURE__*/React.createElement(CrossModeRow, {
    key: m + ':' + row.id,
    mode: m,
    row: row,
    needle: needle,
    onGo: () => setMode(m)
  })))) :
  // Browse-by-category, the default (empty-query) state now that search is primary. One
  // full-width card per category rather than a two-column grid: the 170px recorder width
  // is a fixed control width this design system copies verbatim (see readme.md), and two
  // columns at the 960px floor leave a card only ~360px wide — the recorder alone would
  // eat half of it. Stacked full-width cards keep every row as roomy as the old flat list.
  categoriesPresent.map(cat => {
    const catRows = all.filter(b => categoryFor(b.command) === cat);
    return /*#__PURE__*/React.createElement(FormSection, {
      key: cat,
      header: /*#__PURE__*/React.createElement("div", {
        style: {
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between'
        }
      }, /*#__PURE__*/React.createElement(SectionLabel, {
        title: cat,
        sf: CATEGORY_ICONS[cat]
      }), /*#__PURE__*/React.createElement(Badge, {
        tone: "muted"
      }, catRows.length))
    }, catRows.map(b => /*#__PURE__*/React.createElement(BindingRow, {
      key: b.id,
      b: b,
      needle: "",
      onUpdate: update,
      onRemove: remove,
      onOverride: override,
      onDuplicate: duplicate
    })));
  })), /*#__PURE__*/React.createElement(BarStrip, {
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-end',
      gap: 10,
      padding: '12px 14px 0'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: stepLabelStyle
  }, "1 \xB7 Shortcut"), /*#__PURE__*/React.createElement(KeyRecorderField, {
    notation: newKey,
    width: 170,
    recording: recording,
    onArm: v => {
      setRecording(v);
      if (v) setTimeout(() => {
        setNewKey('esc');
        setRecording(false);
      }, 700);
    },
    onClear: () => setNewKey('')
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 22,
      display: 'flex',
      alignItems: 'center',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "chevron.right",
    size: 11,
    style: {
      color: 'var(--label-tertiary)'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4,
      flex: 1,
      minWidth: 0,
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: stepLabelStyle
  }, "2 \xB7 Command"), /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "command, e.g. focus left",
    value: newCommand,
    onChange: setNewCommand,
    onFocus: () => setSuggestOpen(true),
    onBlur: () => setTimeout(() => setSuggestOpen(false), 120),
    style: {
      width: '100%'
    }
  }), suggestOpen && suggestions.length > 0 && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 'calc(100% + 4px)',
      left: 0,
      right: 0,
      zIndex: 10
    }
  }, /*#__PURE__*/React.createElement(MenuPanel, {
    width: "100%",
    items: suggestions.map(s => ({
      label: s.cmd,
      suffix: s.cat,
      mono: true,
      onClick: () => {
        setNewCommand(s.cmd);
        setSuggestOpen(false);
      }
    }))
  }))), /*#__PURE__*/React.createElement(Button, {
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
  }, conflict.command)), conflict.origin === 'generated' && /*#__PURE__*/React.createElement(Badge, {
    help: "Generated from mod and workspaces. It is not written in your config file."
  }, "generated"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: () => setQuery(conflict.key)
  }, "Show")), newKey && crossModeKeyMatches.length > 0 && /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      padding: '7px 14px 0'
    }
  }, /*#__PURE__*/React.createElement(StatusLabel, {
    kind: "neutral"
  }, crossModeKeyMessage)), /*#__PURE__*/React.createElement(SettingsHint, {
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
const { SectionLabel, CopyButton, Icon, DataTable, ListActionBar, TextField, Select, ContentUnavailable, Badge, Button, MonitorArrangement, MenuPanel } = window.AeroSporkDesignSystem_078bd7;
function MonitorsTab({ monitors, assignments, setAssignments, workspaces = [] }) {
  const [selected, setSelected] = React.useState(null);
  const [selectedMonitor, setSelectedMonitor] = React.useState(null);
  const [pinMenuOpen, setPinMenuOpen] = React.useState(false);
  React.useEffect(() => {
    if (selectedMonitor == null && monitors.length > 0) {
      setSelectedMonitor((monitors.find((m) => m.isMain) || monitors[0]).id);
    }
  }, []);
  const monitorTokens = new Set(monitors.map((m) => m.uuid || m.name));
  const legacyTokenLabel = (token) => {
    if (token === "main") return "Main display";
    if (token === "secondary") return "Non-main display";
    if (/^[1-9]\d*$/.test(token)) return "Position " + token;
    return token;
  };
  const monitorOptions = (current) => [
    ...monitors.map((m, i) => ({ value: m.uuid || m.name, label: `${i + 1} \xB7 ${m.name}` })),
    ...current && !monitorTokens.has(current) ? [{ separator: true }, { value: current, label: legacyTokenLabel(current) }] : []
  ];
  const resolveMonitorId = (token) => {
    if (!token) return null;
    if (token === "main") return (monitors.find((m) => m.isMain) || monitors[0])?.id ?? null;
    if (token === "secondary") return monitors.length === 2 ? monitors.find((m) => !m.isMain)?.id ?? null : null;
    const seq = Number(token);
    if (Number.isInteger(seq) && String(seq) === token && seq >= 1) return monitors[seq - 1]?.id ?? null;
    const exact = monitors.find((m) => m.uuid === token);
    if (exact) return exact.id;
    const byName = monitors.find((m) => m.name === token || m.name.toLowerCase().includes(token.toLowerCase()));
    return byName ? byName.id : null;
  };
  const update = (id, patch) => setAssignments(assignments.map((a) => a.id === id ? { ...a, ...patch } : a));
  const add = (monitor = "main") => {
    const id = "a" + Date.now();
    setAssignments([...assignments, { id, workspace: "", monitor }]);
    setSelected(id);
  };
  const pin = (workspace, monitor) => {
    const existing = assignments.find((a) => a.workspace === workspace);
    if (existing) {
      update(existing.id, { monitor });
      setSelected(existing.id);
      return;
    }
    const id = "a" + Date.now();
    setAssignments([...assignments, { id, workspace, monitor }]);
    setSelected(id);
  };
  const remove = () => {
    setAssignments(assignments.filter((a) => a.id !== selected));
    setSelected(null);
  };
  const toggleMonitor = (id) => setSelectedMonitor((cur) => cur === id ? null : id);
  const activeMonitor = monitors.find((m) => m.id === selectedMonitor) || null;
  const pinnedHere = activeMonitor ? assignments.filter((a) => resolveMonitorId(a.monitor) === activeMonitor.id) : [];
  const assignedNames = new Set(assignments.map((a) => a.workspace));
  const unpinned = workspaces.filter((w, i) => workspaces.indexOf(w) === i && !assignedNames.has(w));
  const movable = activeMonitor ? assignments.filter((a) => a.workspace && resolveMonitorId(a.monitor) !== activeMonitor.id) : [];
  const pinToken = activeMonitor ? activeMonitor.uuid || activeMonitor.name : null;
  const pinMenuItems = [
    ...unpinned.map((w) => ({ label: w, mono: true, onClick: () => {
      pin(w, pinToken);
      setPinMenuOpen(false);
    } })),
    ...movable.length > 0 ? [
      ...unpinned.length > 0 ? [{ divider: true }] : [],
      { label: "Pinned elsewhere \u2014 move here", disabled: true },
      ...movable.map((a) => ({ label: a.workspace, mono: true, onClick: () => {
        pin(a.workspace, pinToken);
        setPinMenuOpen(false);
      } }))
    ] : [],
    { divider: true },
    { label: "Other\u2026", onClick: () => {
      add(pinToken);
      setPinMenuOpen(false);
    } }
  ];
  return /* @__PURE__ */ React.createElement("div", { className: "tab-column" }, /* @__PURE__ */ React.createElement("div", { className: "form-page" }, /* @__PURE__ */ React.createElement("section", { className: "monitors-section" }, /* @__PURE__ */ React.createElement(SectionLabel, { title: "Connected monitors", sf: "display.2", style: { padding: "0 var(--space-2)" } }), /* @__PURE__ */ React.createElement("div", { className: "card-surface monitors-surface" }, monitors.length === 0 ? /* @__PURE__ */ React.createElement(
    ContentUnavailable,
    {
      sf: "display",
      title: "No monitors detected",
      message: "Monitors appear here as soon as macOS reports one \u2014 their UUIDs are what pins a workspace to a physical panel."
    }
  ) : /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("div", { className: "monitor-diagram-wrap" }, /* @__PURE__ */ React.createElement(MonitorArrangement, { monitors, selected: selectedMonitor, onSelect: toggleMonitor, height: 150 })), /* @__PURE__ */ React.createElement("div", { className: "monitor-detail" }, activeMonitor ? /* @__PURE__ */ React.createElement("div", { style: { display: "flex", flexDirection: "column", gap: 5, width: "100%" } }, /* @__PURE__ */ React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 6, position: "relative" } }, /* @__PURE__ */ React.createElement(Icon, { sf: "display", size: 13, style: { color: "var(--label-tertiary)", flex: "0 0 auto" } }), /* @__PURE__ */ React.createElement("strong", { style: { color: "var(--label)", fontWeight: "var(--weight-medium)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" } }, activeMonitor.name), /* @__PURE__ */ React.createElement("span", { style: { color: "var(--label-secondary)" } }, activeMonitor.resolution), activeMonitor.uuid && /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("span", { className: "mono", style: { fontSize: "var(--text-caption)", color: "var(--label-secondary)" } }, activeMonitor.uuid.slice(0, 8), "\u2026"), /* @__PURE__ */ React.createElement(CopyButton, { value: activeMonitor.uuid, help: "Copy monitor UUID\n" + activeMonitor.uuid + "\nA DisplayLink monitor reports no vendor or serial, so its UUID is the only thing that pins a workspace to that exact panel." })), /* @__PURE__ */ React.createElement("span", { style: { flex: 1 } }), /* @__PURE__ */ React.createElement(
    Button,
    {
      onClick: () => setPinMenuOpen((v) => !v),
      title: "Pins to this display; the assignments table can change how it matches."
    },
    "Pin a workspace here"
  ), pinMenuOpen && /* @__PURE__ */ React.createElement(MenuPanel, { items: pinMenuItems, style: { position: "absolute", top: "100%", right: 0, zIndex: 30, marginTop: 4 } })), /* @__PURE__ */ React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap" } }, pinnedHere.length === 0 ? /* @__PURE__ */ React.createElement("span", null, "No workspaces pinned here yet.") : /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("span", null, "Pinned here:"), pinnedHere.map((a) => /* @__PURE__ */ React.createElement(
    "button",
    {
      key: a.id,
      type: "button",
      className: "workspace-chip",
      onClick: () => setSelected(a.id),
      title: "Select the assignment for " + (a.workspace ? "\u201C" + a.workspace + "\u201D" : "this row") + " in the table below"
    },
    a.workspace || "(unnamed)"
  ))))) : /* @__PURE__ */ React.createElement("span", null, "Select a monitor above to see and change what's pinned to it."))))), /* @__PURE__ */ React.createElement("section", { className: "assignments-section" }, /* @__PURE__ */ React.createElement(SectionLabel, { title: "Workspace assignments", sf: "arrow.triangle.branch", style: { padding: "0 var(--space-2)" } }), /* @__PURE__ */ React.createElement("div", { className: "card-surface assignments-surface" }, /* @__PURE__ */ React.createElement(
    DataTable,
    {
      selected,
      onSelect: setSelected,
      columns: [
        // Inert handle column: mirrors the real Table's leading column, which carries no
        // control so a click has somewhere to land for row selection. Decorative only.
        // A plain dot, not a drag handle -- this row can't be reordered, and
        // `line.3.horizontal` would say otherwise. Matches the real Swift's tiny 6pt
        // `circle` glyph: a near-invisible marker, not a visible icon.
        { key: "handle", title: "", width: "20px", render: () => /* @__PURE__ */ React.createElement("span", { style: { display: "inline-block", width: 6, height: 6, borderRadius: "50%", background: "var(--label-tertiary)" } }) },
        { key: "workspace", title: "Workspace", width: "140px", render: (r) => /* @__PURE__ */ React.createElement(TextField, { mono: true, value: r.workspace, placeholder: "name", onChange: (v) => update(r.id, { workspace: v }), style: { width: "100%" } }) },
        { key: "monitor", title: "Monitor", render: (r) => /* @__PURE__ */ React.createElement("span", { style: { display: "flex", gap: 6, alignItems: "center" } }, /* @__PURE__ */ React.createElement(Select, { value: r.monitor, options: monitorOptions(r.monitor), onChange: (v) => update(r.id, { monitor: v }) }), r.complex && /* @__PURE__ */ React.createElement(Badge, { help: "Written with more detail than this editor can show \u2014 a fallback list of monitors, or a fingerprint keyed on more than its UUID. Any structured save in this window is refused until this changes; edit it in Raw TOML." }, "complex")) }
      ],
      rows: assignments,
      emptyState: /* @__PURE__ */ React.createElement(
        ContentUnavailable,
        {
          sf: "arrow.triangle.branch",
          title: "No assignments",
          message: "Workspaces land wherever they were last used. Add an assignment to pin one to a specific monitor.",
          actionTitle: "Add assignment",
          onAction: () => add()
        }
      )
    }
  ), /* @__PURE__ */ React.createElement(
    ListActionBar,
    {
      addHelp: "Pin a workspace to a monitor",
      removeHelp: "Remove the selected assignment",
      onAdd: () => add(),
      onRemove: selected ? remove : null,
      hint: "Hardware fingerprints already in your config are preserved \u2014 they show up here under the monitor's name. A workspace named here stays available even with no windows on it."
    }
  )))));
}
Object.assign(window, { MonitorsTab });
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/MonitorsTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/RawTomlTab.jsx
try { (() => {
const {
  BarStrip,
  Icon,
  Button,
  CodeEditor,
  StatusLabel,
  MenuPanel
} = window.AeroSporkDesignSystem_078bd7;

// Every `[section]` / `[[array-of-table]]` header line, in document order — feeds both the
// Sections… menu below and CodeEditor's `sectionHeaders` prop, so the menu and the editor's own
// header-line highlighting can never disagree about what counts as a header.
function findSectionHeaders(text) {
  const headerRe = /^\[{1,2}[^\[\]=]+\]{1,2}$/;
  return text.split('\n').reduce((acc, line, i) => {
    const code = line.split('#')[0].trim();
    if (headerRe.test(code)) acc.push({
      label: code,
      line: i + 1
    });
    return acc;
  }, []);
}
function RawTomlTab({
  toml,
  setToml,
  original
}) {
  const edited = toml !== original;
  const lines = toml.split('\n');
  const badLine = lines.findIndex(l => /^\s*=/.test(l));
  const errorLine = badLine === -1 ? null : badLine + 1;
  const error = errorLine ? `line ${errorLine}: expected a key before ‘=’` : null;
  const sectionHeaders = React.useMemo(() => findSectionHeaders(toml), [toml]);
  const [cursor, setCursor] = React.useState({
    line: 1,
    col: 1
  });
  const [sectionsOpen, setSectionsOpen] = React.useState(false);
  const [sectionsMenuPos, setSectionsMenuPos] = React.useState(null);
  const [errorHover, setErrorHover] = React.useState(false);
  const editorRef = React.useRef(null);
  const sectionsButtonRef = React.useRef(null);
  const jumpToLine = line => editorRef.current && editorRef.current.scrollToLine(line);

  // Portaled to document.body, not rendered in place: this bar strip sits directly above
  // CodeEditor's own scrolling, absolutely-positioned overlay (the highlighted-<pre>-under-a-
  // transparent-<textarea> trick), which paints its z-index:auto layer ahead of an ordinary
  // in-place z-indexed popup here regardless of the z-index value -- confirmed empirically
  // (`elementsFromPoint` put the textarea above a z-index:10/20 popup every time). A portal is
  // the standard fix for exactly this: it sits in body's own stacking order, so no ancestor's
  // stacking context can bury it. Position is computed from the button's own rect since a
  // portaled node can't rely on a `position: relative` ancestor for placement.
  const openSectionsMenu = () => {
    const r = sectionsButtonRef.current && sectionsButtonRef.current.getBoundingClientRect();
    if (r) setSectionsMenuPos({
      top: r.bottom + 4,
      right: window.innerWidth - r.right
    });
    setSectionsOpen(v => !v);
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
      gap: 8,
      padding: '9px 14px'
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
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--text-callout)',
      color: 'var(--label-secondary)',
      fontFamily: 'var(--font-system)'
    }
  }, "Ln ", cursor.line, ", Col ", cursor.col), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("span", {
    ref: sectionsButtonRef,
    style: {
      display: 'inline-block'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    disabled: sectionHeaders.length === 0,
    title: sectionHeaders.length === 0 ? 'This file has no sections' : 'Jump to a section',
    onClick: openSectionsMenu
  }, "Sections\u2026")), sectionsOpen && sectionHeaders.length > 0 && sectionsMenuPos && ReactDOM.createPortal(/*#__PURE__*/React.createElement("div", {
    style: {
      position: 'fixed',
      top: sectionsMenuPos.top,
      right: sectionsMenuPos.right,
      zIndex: 1000
    }
  }, /*#__PURE__*/React.createElement(MenuPanel, {
    width: 240,
    items: sectionHeaders.map(h => ({
      label: h.label,
      mono: true,
      onClick: () => {
        jumpToLine(h.line);
        setSectionsOpen(false);
      }
    }))
  })), document.body)), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    title: "External edits are picked up automatically \u2014 the config file is watched"
  }, "Open in TextEdit"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    title: "Re-read the config file. Normally automatic."
  }, "Reload"))), /*#__PURE__*/React.createElement(CodeEditor, {
    ref: editorRef,
    value: toml,
    onChange: setToml,
    errorLine: errorLine,
    warningLines: [],
    sectionHeaders: sectionHeaders,
    onCursorMove: (line, col) => setCursor({
      line,
      col
    })
  }), /*#__PURE__*/React.createElement(BarStrip, {
    padded: false
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '9px 14px'
    }
  }, error ? /*#__PURE__*/React.createElement("span", {
    onClick: () => jumpToLine(errorLine),
    onMouseEnter: () => setErrorHover(true),
    onMouseLeave: () => setErrorHover(false),
    title: `Jump to line ${errorLine}`,
    style: {
      cursor: 'pointer',
      textDecoration: errorHover ? 'underline' : 'none'
    }
  }, /*#__PURE__*/React.createElement(StatusLabel, {
    kind: "error"
  }, error)) : edited ? /*#__PURE__*/React.createElement(StatusLabel, {
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
  PanelHeader,
  ListActionBar,
  ContentUnavailable,
  FormSection,
  LabeledContent,
  TextField,
  Toggle,
  Badge,
  SegmentedPicker,
  Button,
  Icon,
  AppIcon,
  appDisplayName,
  SAMPLE_APPS
} = window.AeroSporkDesignSystem_078bd7;

// `run` is a restricted grammar (parseOnWindowDetected.swift): any number of `layout floating` /
// `layout tiling`, plus at most one `move-node-to-workspace`, which must come last. That's exactly
// "make the window float/tile" + "move it somewhere" \u2014 two plain-language controls \u2014 so the common
// case never needs the raw command field at all. Anything else (leftover) can't be represented by
// the guided controls, so it flips the section into "custom" mode instead of silently truncating it.
function parseRun(run) {
  const parts = (run || '').split(';').map(s => s.trim()).filter(Boolean);
  let floatAction = 'none';
  let moveWorkspace = '';
  const leftover = [];
  for (const p of parts) {
    if (p === 'layout floating') floatAction = 'float';else if (p === 'layout tiling') floatAction = 'tile';else if (p.startsWith('move-node-to-workspace ')) moveWorkspace = p.slice('move-node-to-workspace '.length).trim();else leftover.push(p);
  }
  return {
    floatAction,
    moveWorkspace,
    custom: leftover.length > 0
  };
}
function composeRun({
  floatAction,
  moveWorkspace
}) {
  const parts = [];
  if (floatAction === 'float') parts.push('layout floating');else if (floatAction === 'tile') parts.push('layout tiling');
  if (moveWorkspace.trim()) parts.push('move-node-to-workspace ' + moveWorkspace.trim());
  return parts.join(' ; ');
}
// The plain-language line under each app name in the list \u2014 "explain the consequence", not the
// command syntax.
function describeAction(rule) {
  const p = parseRun(rule.run);
  if (p.custom) return 'Runs a custom command';
  const bits = [];
  if (p.floatAction === 'float') bits.push('opens as a floating window');else if (p.floatAction === 'tile') bits.push('is forced to tile');
  if (p.moveWorkspace) bits.push('moves to workspace \u201c' + p.moveWorkspace + '\u201d');
  if (!bits.length) return 'Doesn\u2019t do anything yet';
  const sentence = bits.join(' and ');
  return sentence.charAt(0).toUpperCase() + sentence.slice(1);
}
function advancedMatcherCount(rule) {
  return [rule.appNameRegex, rule.windowTitleRegex, rule.workspace].filter(Boolean).length + (rule.duringStartup !== undefined ? 1 : 0);
}

// A Spotlight/Launchpad-style app grid, not a dropdown: search narrows a grid of icon tiles, and
// typing something not in the sample set always leaves a way to use it verbatim as a custom app
// ID (`aerospork list-apps` is how a real user would get that ID). Scoped to the split view by
// `.app-picker-backdrop`'s position:absolute ancestor (`.split`), so the sidebar and page header
// stay visible, the way a sheet stays attached to one pane rather than covering the whole window.
function AppPicker({
  title,
  query,
  setQuery,
  onPick,
  onClose
}) {
  const needle = query.trim().toLowerCase();
  const matches = needle ? SAMPLE_APPS.filter(a => a.name.toLowerCase().includes(needle) || a.id.toLowerCase().includes(needle)) : SAMPLE_APPS;
  const exact = SAMPLE_APPS.some(a => a.id.toLowerCase() === needle || a.name.toLowerCase() === needle);
  return /*#__PURE__*/React.createElement("div", {
    className: "app-picker-backdrop",
    onMouseDown: e => {
      if (e.target === e.currentTarget) onClose();
    },
    onKeyDown: e => {
      if (e.key === 'Escape') onClose();
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "app-picker-panel",
    onMouseDown: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement("div", {
    className: "app-picker-search"
  }, /*#__PURE__*/React.createElement(PanelHeader, {
    title: title,
    sf: "macwindow.badge.plus",
    style: {
      padding: '0 0 8px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "filter",
    style: {
      width: '100%',
      boxSizing: 'border-box'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "magnifyingglass",
    size: 12,
    style: {
      color: 'var(--label-secondary)'
    }
  }), /*#__PURE__*/React.createElement(TextField, {
    variant: "plain",
    autoFocus: true,
    placeholder: "Search apps, or paste a bundle ID",
    value: query,
    onChange: setQuery,
    style: {
      flex: 1
    }
  }), query && /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "clear",
    onClick: () => setQuery('')
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "xmark.circle.fill",
    size: 12
  })))), /*#__PURE__*/React.createElement("div", {
    className: "app-picker-grid"
  }, !needle && /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "app-picker-tile",
    onClick: () => onPick('')
  }, /*#__PURE__*/React.createElement(AppIcon, {
    appId: "",
    size: 40
  }), /*#__PURE__*/React.createElement("span", null, "Any app")), matches.map(a => /*#__PURE__*/React.createElement("button", {
    key: a.id,
    type: "button",
    className: "app-picker-tile",
    onClick: () => onPick(a.id)
  }, /*#__PURE__*/React.createElement(AppIcon, {
    appId: a.id,
    size: 40
  }), /*#__PURE__*/React.createElement("span", null, a.name))), needle && matches.length === 0 && /*#__PURE__*/React.createElement("div", {
    className: "app-picker-empty"
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "magnifyingglass",
    size: 22,
    weight: "light"
  }), /*#__PURE__*/React.createElement("span", null, "No sample app matches \u201c", query.trim(), "\u201d."))), needle && !exact && /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "app-picker-custom",
    onClick: () => onPick(query.trim())
  }, /*#__PURE__*/React.createElement(AppIcon, {
    appId: query.trim(),
    size: 26
  }), "Use \u201c", query.trim(), "\u201d as a custom app ID"), /*#__PURE__*/React.createElement("div", {
    className: "app-picker-footer"
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: 'var(--weight-regular) var(--text-callout)/1.35 var(--font-system)',
      color: 'var(--label-secondary)'
    }
  }, /*#__PURE__*/React.createElement("code", {
    style: {
      font: 'var(--text-callout)/1 var(--font-mono)'
    }
  }, "aerospork list-apps"), " prints the exact ID for anything running."))));
}
function RulesTab({
  rules,
  setRules
}) {
  const [selected, setSelected] = React.useState(rules[0] ? rules[0].id : null);
  const [pickerMode, setPickerMode] = React.useState(null); // null | 'new' | 'change'
  const [pickerQuery, setPickerQuery] = React.useState('');
  const [advancedOpen, setAdvancedOpen] = React.useState(false);
  const rule = rules.find(r => r.id === selected) || null;

  // Re-derived only when the *selected rule* changes, not on every keystroke \u2014 so a rule that
  // already narrows itself with a regex or a startup filter starts open, but expanding it to type
  // in one more matcher doesn't fight the user by trying to snap back closed mid-edit.
  React.useEffect(() => {
    setAdvancedOpen(rule ? advancedMatcherCount(rule) > 0 : false);
  }, [selected]); // eslint-disable-line react-hooks/exhaustive-deps

  const update = patch => setRules(rules.map(r => r.id === selected ? {
    ...r,
    ...patch
  } : r));
  const remove = () => {
    setRules(rules.filter(r => r.id !== selected));
    setSelected(null);
  };
  const openPicker = mode => {
    setPickerQuery('');
    setPickerMode(mode);
  };
  const pickApp = appId => {
    if (pickerMode === 'new') {
      const id = 'r' + Date.now();
      setRules([...rules, {
        id,
        appId,
        appNameRegex: '',
        windowTitleRegex: '',
        workspace: '',
        run: '',
        checkFurther: false,
        duringStartup: undefined
      }]);
      setSelected(id);
    } else if (pickerMode === 'change') {
      update({
        appId
      });
    }
    setPickerMode(null);
  };
  const parsed = rule ? parseRun(rule.run) : null;
  const advancedCount = rule ? advancedMatcherCount(rule) : 0;
  return /*#__PURE__*/React.createElement("div", {
    className: "split"
  }, /*#__PURE__*/React.createElement("div", {
    className: "split-list"
  }, /*#__PURE__*/React.createElement(PanelHeader, {
    title: "All rules",
    sf: "list.bullet"
  }), /*#__PURE__*/React.createElement("div", {
    className: "hairline"
  }), rules.length === 0 ? /*#__PURE__*/React.createElement(ContentUnavailable, {
    sf: "macwindow",
    title: "No window rules",
    message: "Rules run once, when a window first appears \u2014 pick an app and AeroSpork remembers what to do with it every time.",
    actionTitle: "Add rule",
    onAction: () => openPicker('new')
  }) : /*#__PURE__*/React.createElement("div", {
    className: "rule-list"
  }, rules.map(r => {
    const on = r.id === selected;
    const count = advancedMatcherCount(r);
    return /*#__PURE__*/React.createElement("button", {
      key: r.id,
      type: "button",
      className: 'rule-row' + (on ? ' is-selected' : ''),
      onClick: () => setSelected(r.id)
    }, /*#__PURE__*/React.createElement(AppIcon, {
      appId: r.appId,
      size: 30
    }), /*#__PURE__*/React.createElement("span", {
      className: "rule-row-text"
    }, /*#__PURE__*/React.createElement("span", {
      className: "rule-row-name"
    }, appDisplayName(r.appId)), /*#__PURE__*/React.createElement("span", {
      className: "rule-row-summary"
    }, describeAction(r))), /*#__PURE__*/React.createElement("span", {
      className: "rule-row-badges"
    }, r.duringStartup === true && /*#__PURE__*/React.createElement(Badge, {
      tone: "muted",
      help: "Only applies while AeroSpork is starting up"
    }, "startup"), r.duringStartup === false && /*#__PURE__*/React.createElement(Badge, {
      tone: "muted",
      help: "Only applies after AeroSpork has finished starting up"
    }, "runtime"), count > 0 && /*#__PURE__*/React.createElement(Badge, {
      tone: "muted",
      help: count + ' more thing' + (count > 1 ? 's' : '') + ' this rule checks, beyond the app \u2014 see Advanced matching.'
    }, "+", count)));
  })), /*#__PURE__*/React.createElement(ListActionBar, {
    addHelp: "Add a window rule",
    removeHelp: "Remove the selected rule",
    onAdd: () => openPicker('new'),
    onRemove: selected ? remove : null
  })), /*#__PURE__*/React.createElement("div", {
    className: "split-detail"
  }, rule ? /*#__PURE__*/React.createElement("div", {
    className: "form-page"
  }, /*#__PURE__*/React.createElement("div", {
    className: "rule-detail-header"
  }, /*#__PURE__*/React.createElement(AppIcon, {
    appId: rule.appId,
    size: 44
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "name ellipsis"
  }, appDisplayName(rule.appId)), rule.appId && /*#__PURE__*/React.createElement("span", {
    className: "bundle-id mono ellipsis"
  }, rule.appId)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "bordered",
    onClick: () => openPicker('change')
  }, "Change app\u2026")), /*#__PURE__*/React.createElement(FormSection, {
    header: /*#__PURE__*/React.createElement(SectionLabel, {
      title: "What happens",
      sf: "bolt"
    }),
    footer: parsed.custom ? 'This does more than the guided controls below can compose \u2014 only `layout floating`, `layout tiling`, and one final `move-node-to-workspace`, are supported. Edit the exact text, or start over.' : 'Applied once, the moment the window appears. Leaving the workspace blank does not move the window.'
  }, parsed.custom && /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-8)'
    }
  }, /*#__PURE__*/React.createElement(Badge, {
    tone: "muted",
    help: "Written with more detail than the guided controls below can show."
  }, "custom"), /*#__PURE__*/React.createElement(Button, {
    variant: "borderless",
    onClick: () => update({
      run: ''
    })
  }, "Start over with guided controls")), !parsed.custom && /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Make the window"
  }, /*#__PURE__*/React.createElement(SegmentedPicker, {
    options: [{
      value: 'none',
      label: 'Leave as is'
    }, {
      value: 'float',
      label: 'Float'
    }, {
      value: 'tile',
      label: 'Tile'
    }],
    value: parsed.floatAction,
    onChange: v => update({
      run: composeRun({
        floatAction: v,
        moveWorkspace: parsed.moveWorkspace
      })
    })
  })), !parsed.custom && /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Move it to workspace"
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "don\u2019t move it",
    value: parsed.moveWorkspace,
    width: 160,
    onChange: v => update({
      run: composeRun({
        floatAction: parsed.floatAction,
        moveWorkspace: v
      })
    })
  })), /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "e.g. move-node-to-workspace 3",
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
    }),
    help: "Off (default): the first matching rule wins. On: AeroSpork keeps evaluating rules after this one, so a later rule can add to what this one already did."
  })), /*#__PURE__*/React.createElement("section", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-6)'
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "disclosure-header",
    onClick: () => setAdvancedOpen(v => !v),
    "aria-expanded": advancedOpen
  }, /*#__PURE__*/React.createElement(Icon, {
    sf: "chevron.right",
    size: 10,
    style: {
      color: 'var(--label-secondary)',
      transform: advancedOpen ? 'rotate(90deg)' : 'none',
      transition: 'transform var(--dur-control) var(--ease-standard)'
    }
  }), /*#__PURE__*/React.createElement(SectionLabel, {
    title: "Advanced matching",
    sf: "line.3.horizontal.decrease.circle"
  }), !advancedOpen && advancedCount > 0 && /*#__PURE__*/React.createElement(Badge, {
    tone: "muted"
  }, advancedCount, " set")), advancedOpen && /*#__PURE__*/React.createElement(FormSection, {
    footer: "Empty fields are left out of the match \u2014 a rule with only an app picked applies to every window from that app. `aerospork list-apps` prints app IDs."
  }, /*#__PURE__*/React.createElement(LabeledContent, {
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
    label: "Only on workspace"
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    placeholder: "optional",
    value: rule.workspace,
    onChange: v => update({
      workspace: v
    }),
    width: 200
  })), /*#__PURE__*/React.createElement(LabeledContent, {
    label: "Startup timing"
  }, /*#__PURE__*/React.createElement(SegmentedPicker, {
    options: [{
      value: 'any',
      label: 'Any'
    }, {
      value: 'true',
      label: 'Startup'
    }, {
      value: 'false',
      label: 'Runtime'
    }],
    value: rule.duringStartup === true ? 'true' : rule.duringStartup === false ? 'false' : 'any',
    onChange: v => update({
      duringStartup: v === 'any' ? undefined : v === 'true'
    })
  }))))) : /*#__PURE__*/React.createElement(ContentUnavailable, {
    sf: "sidebar.left",
    title: "No rule selected",
    message: "Pick a rule on the left, or add one, to see what it matches and what it does."
  })), pickerMode && /*#__PURE__*/React.createElement(AppPicker, {
    title: pickerMode === 'new' ? 'Add a window rule' : 'Change app',
    query: pickerQuery,
    setQuery: setPickerQuery,
    onPick: pickApp,
    onClose: () => setPickerMode(null)
  }));
}
Object.assign(window, {
  RulesTab
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/RulesTab.jsx", error: String((e && e.message) || e) }); }

// ui_kits/settings_app/data.js
try { (() => {
// Mock state for the AeroSpork Settings recreation. Values match the shipped default config.
window.AS_DATA = {
  // Gaps tab: whether any of the six gaps currently carries a per-monitor rule in Raw TOML.
  // Off by default so the common (flat-numbers) case shows no extra chrome.
  gapsHavePerMonitorOverrides: false,
  // `rect` is topLeftX/topLeftY/width/height in points, same shape and units as
  // Sources/AppBundle/model/Monitor.swift's `rect` — what MonitorArrangement draws to scale.
  // This arrangement (bottom-aligned, the laptop propped lower than the two externals) is a
  // realistic one, not an idealized row of equal-height rectangles, on purpose: it's the case
  // "Position 2" as a bare number hides and a diagram doesn't.
  monitors: [
    { id: 'm1', name: 'Built-in Retina Display', resolution: '1728 × 1117 pt', uuid: 'BBBBBBBB-0000-4000-8000-000000000002', isMain: true, rect: { x: 0, y: 323, width: 1728, height: 1117 } },
    { id: 'm2', name: 'DELL U2720Q', resolution: '2560 × 1440 pt', uuid: 'AAAAAAAA-0000-4000-8000-000000000001', rect: { x: 1728, y: 0, width: 2560, height: 1440 } },
    { id: 'm3', name: 'DisplayLink Monitor', resolution: '1920 × 1080 pt', uuid: 'CCCCCCCC-0000-4000-8000-000000000003', rect: { x: 4288, y: 360, width: 1920, height: 1080 } },
  ],
  // What `workspaces = [...]` defines after range expansion \u2014 the pin menu offers the unpinned ones.
  workspaces: ["1", "2", "3", "web", "media", "chat"],
  assignments: [
    { id: 'a1', workspace: '1', monitor: 'main' },
    { id: 'a2', workspace: 'web', monitor: 'AAAAAAAA-0000-4000-8000-000000000001' },
    { id: 'a3', workspace: 'media', monitor: 'DELL U2720Q', complex: true },
  ],
  bindings: {
    main: [
      { id: 'g1', key: 'alt-h', command: 'focus left', origin: 'generated' },
      { id: 'g2', key: 'alt-j', command: 'focus down', origin: 'generated' },
      { id: 'g3', key: 'alt-k', command: 'focus up', origin: 'generated' },
      { id: 'g4', key: 'alt-l', command: 'focus right', origin: 'generated' },
      { id: 'g5', key: 'alt-shift-h', command: 'move left', origin: 'generated' },
      { id: 'g6', key: 'alt-minus', command: 'resize smart -50', origin: 'generated' },
      { id: 'g7', key: 'alt-slash', command: 'layout tiles horizontal vertical', origin: 'generated' },
      { id: 'g8', key: 'alt-tab', command: 'workspace-back-and-forth', origin: 'generated' },
      { id: 'e1', key: 'alt-shift-semicolon', command: 'mode service', origin: 'explicit' },
      { id: 'e2', key: 'alt-enter', command: 'exec-and-forget open -na Ghostty', origin: 'explicit' },
    ],
    service: [
      { id: 's1', key: 'esc', command: 'reload-config ; mode main', origin: 'explicit' },
      { id: 's2', key: 'r', command: 'flatten-workspace-tree ; mode main', origin: 'explicit' },
      { id: 's3', key: 'f', command: 'layout floating tiling ; mode main', origin: 'explicit' },
      { id: 's4', key: 'backspace', command: 'close-all-windows-but-current ; mode main', origin: 'explicit' },
    ],
    // A small, single-category mode (all "Mode & system") — demonstrates Change A's flat-list
    // path, and its 'esc'/Ghostty overlap with main and service demonstrates Change B/C's
    // multi-mode branches (2+ other modes matching a search or a recorded key).
    apps: [
      { id: 'p1', key: 'esc', command: 'mode main', origin: 'explicit' },
      { id: 'p2', key: 'o', command: 'exec-and-forget open -na Ghostty', origin: 'explicit' },
      { id: 'p3', key: 's', command: 'exec-and-forget open -na Safari', origin: 'explicit' },
    ],
  },
  // r1-r3 are known sample apps (AppIcon.jsx's SAMPLE_APPS) so their rows carry a real glyph.
  // r4 has no app-id matcher at all ("any app") and r5 names an app outside the sample set, so
  // between them the mock demonstrates every AppIcon fallback: known glyph, generic "any app",
  // and a monogram for an app nobody hardcoded an icon for.
  rules: [
    { id: 'r1', appId: 'com.apple.mail', appNameRegex: '', windowTitleRegex: '', workspace: '', run: 'move-node-to-workspace 3', checkFurther: false, duringStartup: false },
    { id: 'r2', appId: 'com.apple.systempreferences', appNameRegex: '', windowTitleRegex: '', workspace: '', run: 'layout floating', checkFurther: false, duringStartup: false },
    { id: 'r3', appId: 'com.spotify.client', appNameRegex: '', windowTitleRegex: '', workspace: '', run: 'move-node-to-workspace media', checkFurther: false, duringStartup: true },
    { id: 'r4', appId: '', appNameRegex: '', windowTitleRegex: 'Picture[- ]in[- ]Picture', workspace: '', run: 'layout floating', checkFurther: true, duringStartup: undefined },
    { id: 'r5', appId: 'org.mozilla.firefox', appNameRegex: '', windowTitleRegex: '', workspace: '', run: 'layout floating ; move-node-to-workspace web', checkFurther: false, duringStartup: undefined },
  ],
  events: {
    afterStartup: ['exec-and-forget sketchybar --reload'],
    workspaceChanged: ['move-mouse window-lazy-center'],
    monitorChanged: [],
    focusChanged: [],
  },
  env: [{ id: 'v1', name: 'PATH', value: '/opt/homebrew/bin:/usr/bin:/bin' }],
  toml: [
    '# AeroSpork — tiling window manager for macOS',
    '',
    'mod = "alt"',
    'workspaces = "1-9"',
    '',
    '[gaps]',
    'inner = 8',
    'outer = { top = 32, bottom = 8, left = 8, right = 8 }',
    '',
    '[keys]',
    'alt-shift-semicolon = "mode service"',
    'alt-enter = "exec-and-forget open -na Ghostty"',
    '',
    '[keys.service]',
    'esc = ["reload-config", "mode main"]',
    'r = ["flatten-workspace-tree", "mode main"]',
    '',
    '[monitors]',
    '1 = "main"',
    'web = { uuid = "AAAAAAAA-0000-4000-8000-000000000001" }',
    '',
    '[on-window]',
    '"com.apple.mail" = "move-node-to-workspace 3"',
  ].join('\n'),
};

})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings_app/data.js", error: String((e && e.message) || e) }); }

__ds_ns.CodeEditor = __ds_scope.CodeEditor;

__ds_ns.GapsPreview = __ds_scope.GapsPreview;

__ds_ns.MonitorArrangement = __ds_scope.MonitorArrangement;

__ds_ns.WindowChrome = __ds_scope.WindowChrome;

__ds_ns.WorkspaceChips = __ds_scope.WorkspaceChips;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.CopyButton = __ds_scope.CopyButton;

__ds_ns.KeyCaps = __ds_scope.KeyCaps;

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

__ds_ns.PanelHeader = __ds_scope.PanelHeader;

__ds_ns.SettingsFooter = __ds_scope.SettingsFooter;

__ds_ns.SettingsHint = __ds_scope.SettingsHint;

__ds_ns.TabBar = __ds_scope.TabBar;

__ds_ns.SAMPLE_APPS = __ds_scope.SAMPLE_APPS;

__ds_ns.appDisplayName = __ds_scope.appDisplayName;

__ds_ns.AppIcon = __ds_scope.AppIcon;

})();
