import React from 'react';

/* AeroSpork is a native app: every glyph in it is an SF Symbol, which cannot be redistributed
   with a web design system. This maps the symbol names the app actually uses onto the closest
   Lucide icon (2px stroke, rounded caps — the nearest match to SF Symbols' Regular weight).
   The shapes are inlined (also in assets/icons/*.svg) rather than loaded from a CDN, so a mock
   works offline and in renderers that refuse cross-origin mask images.
   SUBSTITUTION: shapes are close but not identical. In production Swift, use the SF Symbol name.
   Lucide is ISC licensed. */
export const SF_TO_LUCIDE = {
  'gearshape': 'settings', 'rectangle.split.3x3': 'layout-grid', 'keyboard': 'keyboard',
  'display.2': 'monitor', 'display': 'monitor', 'bolt': 'zap',
  'macwindow.badge.plus': 'app-window', 'macwindow': 'app-window', 'doc.plaintext': 'file-text',
  'plus': 'plus', 'minus': 'minus', 'minus.circle': 'circle-minus', 'plus.circle': 'circle-plus',
  'xmark': 'x', 'xmark.circle.fill': 'circle-x', 'magnifyingglass': 'search',
  'doc.on.doc': 'copy', 'plus.square.on.square': 'copy-plus', 'checkmark': 'check', 'checkmark.circle': 'circle-check',
  'equal.circle': 'circle-equal', 'exclamationmark.triangle.fill': 'triangle-alert',
  'exclamationmark.octagon.fill': 'octagon-alert', 'arrow.triangle.branch': 'git-branch',
  'list.bullet': 'list', 'sidebar.left': 'panel-left', 'power': 'power',
  'menubar.rectangle': 'panel-top', 'rectangle.split.3x1': 'columns-3',
  'rectangle.split.2x1': 'columns-2', 'rectangle.inset.filled': 'square',
  'wand.and.stars': 'wand-sparkles', 'info.circle': 'info', 'play.circle': 'circle-play',
  'rectangle.on.rectangle': 'layers', 'scope': 'crosshair', 'terminal': 'terminal',
  'ellipsis.circle': 'ellipsis', 'line.3.horizontal.decrease.circle': 'filter',
  'square.grid.2x2': 'grid-2x2', 'pause.circle.fill': 'circle-pause',
  'chevron.down': 'chevron-down', 'chevron.right': 'chevron-right', 'trash': 'trash-2',
  'line.3.horizontal': 'menu', 'eye': 'eye',
  // Window Rules v3 — generic app-icon glyphs (AppIcon.jsx). Universal pictograms, not traced
  // from any real app's actual logo: an envelope, not Mail.app's specific stamp art; a compass,
  // not Safari's specific compass painting; a folder, not Finder's two-tone face.
  'envelope': 'mail', 'safari': 'compass', 'music.note': 'music', 'message': 'message-circle',
  'folder': 'folder',
};

/** Glyph geometry, keyed by Lucide name. Stroke is currentColor, so tint by setting `color`. */
export const ICON_SHAPES = {
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
  "copy-plus": "<line x1=\"15\" x2=\"15\" y1=\"12\" y2=\"18\" /><line x1=\"12\" x2=\"18\" y1=\"15\" y2=\"15\" /><rect width=\"14\" height=\"14\" x=\"8\" y=\"8\" rx=\"2\" ry=\"2\" /><path d=\"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2\" />",
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
  "folder": "<path d=\"M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.9 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z\" />",
};

export function Icon({ sf, name, size = 14, weight = 'regular', style }) {
  const shape = ICON_SHAPES[name || SF_TO_LUCIDE[sf]] || ICON_SHAPES.square;
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width={size} height={size} fill="none"
      stroke="currentColor" strokeWidth={weight === 'light' ? 1.5 : 2}
      strokeLinecap="round" strokeLinejoin="round"
      style={{ display: 'inline-block', flex: '0 0 auto', verticalAlign: 'middle', ...style }}
      dangerouslySetInnerHTML={{ __html: shape }} />
  );
}
