unit tyControls.DefaultTheme;

{ Built-in default skin compiled into the binary (no runtime file dependency) so
  controls render sensibly with no theme loaded (no Controller, or the Lazarus
  designer). GENERATED from themes/light.tycss by gen-defaulttheme.ps1 - do NOT edit
  by hand; edit light.tycss and re-run the generator. Sync-tested byte-identical to
  light.tycss (test.defaulttheme). }

{$mode objfpc}{$H+}

interface

function TyBuiltinThemeCss: string;
{ Per-mode contrast tokens for the seeded base — NOT part of the light theme (which is
  single-mode and byte-synced to light.tycss). The model layers these UNDER a dual-mode user
  theme so a skin that overrides the surface but omits the ink inherits a readable per-mode
  value for the controls it does not restyle (menu/tree/tabset/…). Values match auto.tycss, so
  the default theme is unchanged; a single-mode theme keeps the light :root defaults. Derived
  tokens (--muted etc.) re-derive from these. Hand-written (not generated). }
function TyBuiltinBaseModeCss: string;

implementation

function TyBuiltinBaseModeCss: string;
begin
  Result :=
    '@mode light { :root { --on-surface: #1F2937; --surface: #FFFFFF; --border: #D1D5DB; } }' + LineEnding +
    '@mode dark  { :root { --on-surface: #E5E7EB; --surface: #1E1E1E; --border: #3F3F46; } }' + LineEnding;
end;

function TyBuiltinThemeCss: string;
begin
  Result :=
    '/* TyControls — Light theme */' + LineEnding +
    ':root {' + LineEnding +
    '  /* ── SEED ── 7 colors + 1 metric */' + LineEnding +
    '  --accent: #3B82F6; --surface: #FFFFFF; --on-surface: #1F2937;' + LineEnding +
    '  --border: #D1D5DB; --danger: #EF4444; --radius: 6px;' + LineEnding +
    '  /* The two STATUS seeds (added for TTyAlert/TTyNotification, 2026-07-17). They are seeds, not' + LineEnding +
    '     derivations: no hue-shift of --accent or --danger produces a credible green/amber, and a' + LineEnding +
    '     control must never invent a colour. There is deliberately no --info seed — in this vocabulary' + LineEnding +
    '     (as in Ant''s) "info" IS the brand colour, so --info aliases --accent below. */' + LineEnding +
    '  --success: #22C55E; --warning: #F59E0B;' + LineEnding +
    '' + LineEnding +
    '  /* ── MAP: directional darken/lighten the body inlines ── */' + LineEnding +
    '  --surface-hover:            darken(--surface, 4%);' + LineEnding +
    '  --surface-active:           darken(--surface, 10%);' + LineEnding +
    '  --surface-chrome:           darken(--surface, 6%);' + LineEnding +
    '  /* 斑马纹的隔行底色。比 chrome 淡得多 —— 它是让长表读起来更顺的辅助,不是分区。 */' + LineEnding +
    '  --surface-alt:              darken(--surface, 3%);' + LineEnding +
    '  /* 评分星的金色。评分是少数几个有约定俗成颜色的元素,但仍走 token —— 皮肤能改。 */' + LineEnding +
    '  --rating-star:              #F59E0B;' + LineEnding +
    '  --surface-sunk:             darken(--surface, 8%);' + LineEnding +
    '  --surface-track:            darken(--surface, 10%);' + LineEnding +
    '  --surface-listitem-hover:   darken(--surface, 5%);' + LineEnding +
    '  --surface-tab-rest:         darken(--surface, 5%);' + LineEnding +
    '  --surface-tab-hover:        darken(--surface, 2%);' + LineEnding +
    '  --surface-toggle-off:       darken(--surface, 18%);' + LineEnding +
    '  --surface-toggle-off-hover: darken(--surface, 22%);' + LineEnding +
    '  --surface-caption-hover:    darken(--surface, 12%);' + LineEnding +
    '  --surface-caption-active:   darken(--surface, 20%);' + LineEnding +
    '  --border-hover:             darken(--border, 10%);' + LineEnding +
    '  --scroll-handle-hover:      darken(--border, 15%);' + LineEnding +
    '  --accent-hover:  lighten(--accent, 8%);   --accent-active: darken(--accent, 8%);' + LineEnding +
    '  --danger-hover:  lighten(--danger, 8%);   --danger-active: darken(--danger, 8%);' + LineEnding +
    '  --danger-press-close: darken(--danger, 10%);' + LineEnding +
    '' + LineEnding +
    '  /* ── ALIAS: semantic ── */' + LineEnding +
    '  --focus-ring:       var(--accent);' + LineEnding +
    '  --selection:        alpha(var(--accent), 0.30);' + LineEnding +
    '  --muted:            alpha(var(--on-surface), 0.5);' + LineEnding +
    '  --overlay-hover:    alpha(var(--on-surface), 0.12);' + LineEnding +
    '  --disabled-opacity: 0.5;' + LineEnding +
    '  --form-bg:          var(--surface-hover);   /* TyForm bg */' + LineEnding +
    '  --titlebar-bg:      var(--surface-chrome);  /* TyTitleBar bg */' + LineEnding +
    '  --input-bg:         var(--surface);         /* Edit/Check/Radio/Combo/List/Spin/Memo bg */' + LineEnding +
    '  --scroll-handle:    var(--border);          /* resting scroll thumb/handle */' + LineEnding +
    '  --input-border-hover: var(--border-hover);  /* neutral inputs hover border */' + LineEnding +
    '  /* on-* declared here but WIRED only in the §3 bug-fix commit */' + LineEnding +
    '  --on-accent:        on(var(--accent));      /* light -> #FFFFFF (== current literal) */' + LineEnding +
    '  --on-danger:        on(var(--danger));      /* light -> #FFFFFF */' + LineEnding +
    '  --on-success:       on(var(--success));     /* the status seeds get the same on() pairing */' + LineEnding +
    '  --on-warning:       on(var(--warning));     /* amber is light -> on() picks a DARK ink here */' + LineEnding +
    '  --info:             var(--accent);          /* "info" is the brand colour, not a seed of its own */' + LineEnding +
    '  --on-info:          var(--on-accent);' + LineEnding +
    '' + LineEnding +
    '  /* ── COMPONENT: scalars ── */' + LineEnding +
    '  --input-border-width: 1px;' + LineEnding +
    '  --radius-sm: 3px; --radius-pill: 8px; --radius-round: 12px; --radius-scroll: 4px;' + LineEnding +
    '  --font-size-base: 9px; --font-size-title: 9px;' + LineEnding +
    '' + LineEnding +
    '  /* ── 尺寸令牌(密度尺度第一期)───────────────────────────────────────' + LineEnding +
    '     经典密度 = 今天的实际值,一个都不动。现代密度由 density-modern.tycss' + LineEnding +
    '     覆盖这些名字 —— 它只碰令牌,不碰规则、也不碰颜色,所以对 15 个皮肤' + LineEnding +
    '     一视同仁。' + LineEnding +
    '' + LineEnding +
    '     这里**刻意没有** --space-* 数字尺度:经典侧有 5px 9px / 4px 10px /' + LineEnding +
    '     0px 14px 这些历史随手值,强推 4 的倍数会让经典漂移 1px,而' + LineEnding +
    '     「经典逐字节不变」正是整轮迁移的守卫。尺度只在现代侧存在。 */' + LineEnding +
    '' + LineEnding +
    '  /* 字号。经典三档全是 9px —— 这种扁平本身就是 Win32 时代的特征,' + LineEnding +
    '     字号层级是 Web 时代才有的东西。 */' + LineEnding +
    '  --font-size-sm: 9px;' + LineEnding +
    '' + LineEnding +
    '  /* 内边距:按**角色**命名,不按尺度命名(见上)。41 条规则归并成 19 个角色。' + LineEnding +
    '     值全部取自今天各规则的字面量。 */' + LineEnding +
    '  --pad-none:            0px;' + LineEnding +
    '  --pad-tight:           2px;' + LineEnding +
    '  --pad-control:         4px;' + LineEnding +
    '  --pad-tooltip:         5px 9px;' + LineEnding +
    '  --pad-button:          6px;' + LineEnding +
    '  --pad-container:       8px;' + LineEnding +
    '  --pad-card:            12px;' + LineEnding +
    '  --pad-empty:           16px;' + LineEnding +
    '  --pad-cell:            0px 6px;' + LineEnding +
    '  --pad-chip:            0px 8px;' + LineEnding +
    '  --pad-badge:           0px 4px;' + LineEnding +
    '  --pad-breadcrumb:      2px 4px;' + LineEnding +
    '  --pad-breadcrumb-item: 0px 4px;' + LineEnding +
    '  --pad-groupbox:        4px 12px;' + LineEnding +
    '  --pad-datetime:        4px 6px;' + LineEnding +
    '  --pad-segmented:       4px 10px;' + LineEnding +
    '  --pad-alert:           8px 12px;' + LineEnding +
    '  --pad-notification:    12px 14px;' + LineEnding +
    '  --pad-group-header:    0px 14px;' + LineEnding +
    '' + LineEnding +
    '  /* 控件高与图标槽。值取自各控件今天的 published default:' + LineEnding +
    '     DefaultRowHeight=22、Header.Height=22、ItemHeight=24、TyDlgEditH=30、' + LineEnding +
    '     TyCheckBoxBox/TyAlertIconSize=16。第 3 期把 Pascal 侧的常量迁过来时用。 */' + LineEnding +
    '  --control-height: 30px;' + LineEnding +
    '  --row-height:     22px;' + LineEnding +
    '  --header-height:  22px;' + LineEnding +
    '  --item-height:    24px;' + LineEnding +
    '  --icon-size:      16px;' + LineEnding +
    '  --font-weight-normal: 400; --font-weight-bold: 700;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Window/form backdrop — a soft off-white behind the white controls. */' + LineEnding +
    'TyForm { background: var(--form-bg); }' + LineEnding +
    '' + LineEnding +
    'TyButton {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 6px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    'TyButton:hover    { background: var(--surface-hover); border-color: var(--input-border-hover); }' + LineEnding +
    'TyButton:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyButton:active   { background: var(--surface-active); }' + LineEnding +
    'TyButton:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyButton.primary  { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyButton.primary:hover    { background: var(--accent-hover); }' + LineEnding +
    'TyButton.primary:active   { background: var(--accent-active); }' + LineEnding +
    'TyButton.danger   { background: var(--danger); color: var(--on-danger); border-color: var(--danger); }' + LineEnding +
    'TyButton.danger:hover     { background: var(--danger-hover); }' + LineEnding +
    'TyButton.danger:active    { background: var(--danger-active); }' + LineEnding +
    '/* Ghost (VS Code 风格): 平时透明,仅 hover/active/选中显示底色与边框。透明用 alpha(...,0)' + LineEnding +
    '   保持纯色,使现有 hover 背景 alpha 淡入有效;边框透明但保留宽度,避免 hover 尺寸跳动。 */' + LineEnding +
    'TyButton.ghost {' + LineEnding +
    '  background: alpha(var(--surface-hover), 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: alpha(var(--border), 0);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 6px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    'TyButton.ghost:hover    { background: var(--surface-hover); border-color: var(--input-border-hover); }' + LineEnding +
    'TyButton.ghost:active   { background: var(--surface-active); }' + LineEnding +
    'TyButton.ghost:selected { background: var(--surface-active); border-color: var(--accent); }' + LineEnding +
    'TyButton.ghost:focus    { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyButton.ghost:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyLabel {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    'TyLabel:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyEdit {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyEdit:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TyEdit:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyEdit:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyCheckBox {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyCheckBox:hover    { border-color: var(--accent); }' + LineEnding +
    'TyCheckBox:active   { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyCheckBox:focus    { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyCheckBox:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyRadioButton {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius-pill);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyRadioButton:hover    { border-color: var(--accent); }' + LineEnding +
    'TyRadioButton:active   { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyRadioButton:focus { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyRadioButton:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyPanel {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 8px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyComboBox {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyComboBox:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TyComboBox:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyComboBox:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyScrollBar {' + LineEnding +
    '  background: var(--surface-chrome);' + LineEnding +
    '  color: var(--scroll-handle);' + LineEnding +
    '  border-radius: var(--radius-scroll);' + LineEnding +
    '}' + LineEnding +
    'TyScrollBar:hover  { color: var(--scroll-handle-hover); }' + LineEnding +
    'TyScrollBar:active { color: var(--accent); }' + LineEnding +
    'TyScrollBar:focus  { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyScrollBar:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyTitleBar {' + LineEnding +
    '  background: var(--titlebar-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  font-size: var(--font-size-title);' + LineEnding +
    '  font-weight: var(--font-weight-bold);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyCaptionButton {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: 0px;' + LineEnding +
    '}' + LineEnding +
    'TyCaptionButton:hover  { background: var(--surface-caption-hover); }' + LineEnding +
    'TyCaptionButton:active { background: var(--surface-caption-active); }' + LineEnding +
    'TyCaptionButton.close:hover  { background: var(--danger); color: var(--on-danger); }' + LineEnding +
    'TyCaptionButton.close:active { background: var(--danger-press-close); color: var(--on-danger); }' + LineEnding +
    'TyCaptionButton.min:hover    { background: var(--surface-caption-hover); }' + LineEnding +
    'TyCaptionButton.max:hover    { background: var(--surface-caption-hover); }' + LineEnding +
    '' + LineEnding +
    '/* ── v1.1 controls ─────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyListBox {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 2px;' + LineEnding +
    '}' + LineEnding +
    'TyListBox:hover   { border-color: var(--input-border-hover); }' + LineEnding +
    'TyListBox:focus   { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyListBox:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyListItem {' + LineEnding +
    '  background: alpha(#000000, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyListItem:hover  { background: var(--surface-listitem-hover); }' + LineEnding +
    'TyListItem:active { background: var(--accent); color: var(--on-accent); border-radius: 0; }' + LineEnding +
    '' + LineEnding +
    'TyProgressBar {' + LineEnding +
    '  background: var(--surface-sunk);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    'TyProgressBar:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyProgressFill {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyGauge {' + LineEnding +
    '  background: var(--surface-sunk);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    'TyGauge:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyGaugeFill {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Themed tooltip surface (TTyHintWindow — replaces the native LCL hint). */' + LineEnding +
    'TyHint {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: 5px 9px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Ribbon (Phase-3): the command band surface + the labelled group box. */' + LineEnding +
    'TyRibbon {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: 0;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyRibbonGroup {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--muted);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '' + LineEnding +
    'TyToggleSwitch {' + LineEnding +
    '  background: var(--surface-toggle-off);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: var(--radius-round);' + LineEnding +
    '}' + LineEnding +
    'TyToggleSwitch:hover    { background: var(--surface-toggle-off-hover); }' + LineEnding +
    'TyToggleSwitch:active   { background: var(--accent); }' + LineEnding +
    'TyToggleSwitch:focus { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyToggleSwitch:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyTrackBar {' + LineEnding +
    '  background: var(--surface-track);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: 0px;' + LineEnding +
    '}' + LineEnding +
    'TyTrackBar:focus    { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyTrackBar:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyTrackThumb {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  border-radius: var(--radius-pill);' + LineEnding +
    '}' + LineEnding +
    'TyTrackThumb:hover  { background: var(--accent-hover); }' + LineEnding +
    'TyTrackThumb:active { background: var(--accent-active); }' + LineEnding +
    '' + LineEnding +
    'TyGroupBox {' + LineEnding +
    '  padding: 4px 12px;' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* ── v1.2 controls ─────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyTabControl {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    'TyTabControl:hover  { border-color: var(--input-border-hover); }' + LineEnding +
    'TyTabControl:focus  { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyTabControl:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    '/* TTyPageControl mirrors TyTabControl (the tab container); TyTabSheet is the page' + LineEnding +
    '   body inside the frame — opaque surface fill only (no border) so it never leaves' + LineEnding +
    '   transparent pixels for the OS window backdrop to show through. */' + LineEnding +
    'TyPageControl {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    'TyPageControl:hover  { border-color: var(--input-border-hover); }' + LineEnding +
    'TyPageControl:focus  { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyPageControl:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyTabSheet {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyTab {' + LineEnding +
    '  background: var(--surface-tab-rest);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  border-radius: var(--radius) var(--radius) 0 0;' + LineEnding +
    '}' + LineEnding +
    'TyTab:hover  { background: var(--surface-tab-hover); }' + LineEnding +
    'TyTab:active { background: var(--surface); color: var(--accent); }' + LineEnding +
    '' + LineEnding +
    '/* ── v1.9 controls ─────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TySpinEdit {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TySpinEdit:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TySpinEdit:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TySpinEdit:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyMemo {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyMemo:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TyMemo:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyMemo:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyTextSelection { background: var(--selection); }' + LineEnding +
    'TyTextHint      { color: var(--muted); }' + LineEnding +
    'TyTabClose      { background: var(--overlay-hover); border-radius: var(--radius); }' + LineEnding +
    '' + LineEnding +
    'TyScrollThumb { background: var(--scroll-handle); border-radius: var(--radius-scroll); }' + LineEnding +
    'TyScrollThumb:hover  { background: var(--scroll-handle-hover); }' + LineEnding +
    'TyScrollThumb:active { background: var(--accent); }' + LineEnding +
    'TyToggleKnob  { background: #FFFFFF; border-radius: var(--radius-round); }' + LineEnding +
    '' + LineEnding +
    '/* 数字角标 (TTyButton badge): 默认 accent 蓝胶囊;padding 上下0、左右4 留横向呼吸。 */' + LineEnding +
    'TyBadge {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  color: var(--on-accent);' + LineEnding +
    '  border-radius: var(--radius-round);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-bold);' + LineEnding +
    '  padding: 0px 4px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* ── Menu system ───────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    '/* The top application-menu bar (TTyMenuBar surface). */' + LineEnding +
    'TyMenuBar {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '  padding: 2px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* The dropdown/context popup surface (TTyMenuView, the rendered popup body).' + LineEnding +
    '   TyMenuPopup mirrors it for the popup-host selector named in the spec. */' + LineEnding +
    'TyMenuView {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyMenuPopup {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* A single menu row / bar cell. The base border-color is the separator-line ink. */' + LineEnding +
    'TyMenuItem {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    'TyMenuItem:hover    { background: var(--surface-hover); }' + LineEnding +
    'TyMenuItem:active   { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyMenuItem:disabled { color: var(--muted); }' + LineEnding +
    '' + LineEnding +
    '/* ── Lightweight trio ──────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TySplitter {' + LineEnding +
    '  background: none;' + LineEnding +
    '  color: var(--muted);' + LineEnding +
    '}' + LineEnding +
    'TySplitter:hover {' + LineEnding +
    '  color: var(--accent);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyStatusBar {' + LineEnding +
    '  background: var(--surface-chrome);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyToolBar {' + LineEnding +
    '  background: var(--surface-chrome);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* ── Calendar + DateTimePicker ─────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyCalendar { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: 6px; font-size: var(--font-size-base); }' + LineEnding +
    'TyCalendarTitle { color: var(--on-surface); font-weight: var(--font-weight-bold); }' + LineEnding +
    'TyCalendarTitle:hover { color: var(--accent); }' + LineEnding +
    'TyCalendarWeekday { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    'TyCalendarCell { background: none; color: var(--on-surface); border-radius: var(--radius-sm); }' + LineEnding +
    'TyCalendarCell:hover { background: var(--surface-hover); }' + LineEnding +
    'TyCalendarCell:selected { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyCalendarCell:disabled { color: var(--muted); }' + LineEnding +
    'TyDateTimePicker { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: 4px 6px; font-size: var(--font-size-base); }' + LineEnding +
    'TyDateTimePicker:hover { border-color: var(--input-border-hover); }' + LineEnding +
    'TyDateTimePicker:focus { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyDateTimePicker:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyDateTimeButton { background: var(--surface-chrome); color: var(--on-surface); }' + LineEnding +
    'TyDateTimeButton:hover { background: var(--surface-hover); color: var(--accent); }' + LineEnding +
    '' + LineEnding +
    '/* ── TreeView ──────────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyTreeView { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: 2px; font-size: var(--font-size-base); }' + LineEnding +
    'TyTreeNode { background: none; color: var(--on-surface); }' + LineEnding +
    'TyTreeNode:hover { background: var(--surface-hover); }' + LineEnding +
    'TyTreeNode:selected { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyTreeNode:disabled { color: var(--muted); }' + LineEnding +
    'TyTreeHeader { background: var(--surface-chrome); border-color: var(--border); border-width: var(--input-border-width); color: var(--on-surface); font-size: var(--font-size-base); font-weight: var(--font-weight-bold); }' + LineEnding +
    'TyTreeHeaderSection { background: none; color: var(--on-surface); border-color: var(--border); }' + LineEnding +
    'TyTreeHeaderSection:hover { background: var(--surface-hover); }' + LineEnding +
    'TyTreeHeaderSection:selected { background: var(--surface-active); }' + LineEnding +
    '' + LineEnding +
    '/* --- 数据网格 TTyGrid ------------------------------------------------------' + LineEnding +
    '   基层给全套键,新皮肤即使一条网格规则都不写也能正常显示(基层垫在每个主题之下)。' + LineEnding +
    '   网格自成一套 typeKey,不借用树/列表的键 —— 借来的键在外观主题层够不着。 */' + LineEnding +
    'TyGrid { background: var(--surface); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius-sm); font-size: var(--font-size-base); }' + LineEnding +
    '/* 正文单元格。resting 透明,让网格表面透出来;选中/悬停才上色。 */' + LineEnding +
    'TyGridCell { background: none; color: var(--on-surface); padding: 0px 6px; }' + LineEnding +
    'TyGridCell:hover    { background: var(--surface-hover); }' + LineEnding +
    'TyGridCell:selected { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    '/* 失焦时的选区(HideSelectionWhenInactive)。给它**自己的键**,不写成' + LineEnding +
    '   TyGridCell:selected:disabled —— 语法每个选择器只认一个 :state,' + LineEnding +
    '   链式伪状态解析不了(而且借别的键会让外观层够不着,见 TyGridActiveCell)。 */' + LineEnding +
    'TyGridCellSelectedInactive { background: alpha(var(--accent), 0.35); color: var(--on-surface); }' + LineEnding +
    '/* 焦点格(光标所在)。整行选中模式下,不区分就看不出光标在哪一格。 */' + LineEnding +
    'TyGridActiveCell { background: var(--surface-active); color: var(--on-surface); }' + LineEnding +
    '/* 选区盖在"用户显式指定了底色"的格上时用这一层(逐格色/行色/条件着色)。' + LineEnding +
    '   不透明的选区色会把用户自己标的颜色整块抹掉,而光标总落在刚上色的那一格上。 */' + LineEnding +
    'TyGridCellMarked { background: alpha(--accent, 0.42); }' + LineEnding +
    '/* 选区外框 + 填充柄。外框给"这块是选中的"一条边界线索(底色只给面);' + LineEnding +
    '   柄画在右下角,拖它把选区的值往下铺。' + LineEnding +
    '   color 是**柄的描边色** —— 柄与选区底色同为 accent,不描边就等于没画。 */' + LineEnding +
    'TyGridSelectionFrame { border-color: var(--accent); border-width: 1px; background: var(--accent); color: var(--surface); }' + LineEnding +
    '/* 斑马纹。自己的 typeKey 而不是 TyGridCell:alternate:加伪类要动共享的状态枚举与' + LineEnding +
    '   CSS 解析器,会波及每一个控件;而网格的各部件本来就各有各的键。 */' + LineEnding +
    'TyGridCellAlt { background: var(--surface-alt); }' + LineEnding +
    '/* 冻结区(固定行列)与行头槽:比正文略重,读者一眼能分出"这块不滚动"。 */' + LineEnding +
    'TyGridFixed     { background: var(--surface-chrome); color: var(--on-surface); border-color: var(--border); }' + LineEnding +
    'TyGridIndicator { background: var(--surface-chrome); color: var(--muted); border-color: var(--border); }' + LineEnding +
    '/* 列头带 —— 与树表头同族的观感,但用自己的键。 */' + LineEnding +
    'TyGridHeader        { background: var(--surface-chrome); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); font-size: var(--font-size-base); font-weight: var(--font-weight-bold); }' + LineEnding +
    'TyGridHeaderSection { background: none; color: var(--on-surface); border-color: var(--border); }' + LineEnding +
    'TyGridHeaderSection:hover    { background: var(--surface-hover); }' + LineEnding +
    'TyGridHeaderSection:selected { background: var(--surface-active); }' + LineEnding +
    '/* 分组表头带(横跨若干列的上层标题)。自己的键 —— 与叶子列头分开配才有意义。 */' + LineEnding +
    'TyGridHeaderGroup { background: var(--surface-active); color: var(--on-surface); border-color: var(--border); }' + LineEnding +
    '/* 内嵌筛选行。它是"能打字的地方",所以底色跟表面走、边框跟输入框走 ——' + LineEnding +
    '   与列头带(chrome 色)刻意区分开,否则用户看不出它可以输入。 */' + LineEnding +
    'TyGridFilterRow { background: var(--surface); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); font-size: var(--font-size-base); }' + LineEnding +
    '/* 格线与选区。格线单独成键,皮肤想去掉格子只需把它设成透明。 */' + LineEnding +
    'TyGridLine      { background: var(--border); }' + LineEnding +
    '/* 单元格图形。各自成键,不借复选框/进度条的键 —— 借来的键在外观层够不着,' + LineEnding +
    '   而且改它会波及那些控件。状态只由单元格自身决定,不掺网格的瞬时状态。 */' + LineEnding +
    'TyGridCheckBox           { background: var(--input-bg); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius-sm); color: var(--on-surface); }' + LineEnding +
    'TyGridCheckBox:selected  { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyGridHyperlink          { color: var(--accent); }' + LineEnding +
    'TyGridCommentMark        { color: var(--warning); }' + LineEnding +
    'TyGridProgress           { background: var(--surface-chrome); border-radius: var(--radius-sm); }' + LineEnding +
    'TyGridProgressFill       { background: var(--accent); }' + LineEnding +
    'TyGridRating             { color: var(--rating-star); }' + LineEnding +
    'TyGridRatingEmpty        { color: var(--border); }' + LineEnding +
    '/* 按钮单元格。三态用自己的键 —— 借 TyButton 的键会让"改网格里的按钮"波及全库按钮。 */' + LineEnding +
    'TyGridButton          { background: var(--surface-chrome); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius-sm); }' + LineEnding +
    'TyGridButton:hover    { background: var(--surface-hover); }' + LineEnding +
    'TyGridButton:active   { background: var(--surface-active); }' + LineEnding +
    'TyGridSelection { background: var(--selection); border-color: var(--accent); }' + LineEnding +
    'TyTreeCheckBox { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius-sm); }' + LineEnding +
    'TyTreeCheckBox:active   { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyTreeCheckBox:selected { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyTreeCheckBox:disabled { color: var(--muted); }' + LineEnding +
    '' + LineEnding +
    '/* ── Card + Tag (Ant Design-gap batch 1) ───────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    '/* One themed surface for the whole card; the header/actions strips are bands drawn' + LineEnding +
    '   on it, so they carry only their separator (border-*) and the title''s ink. A flat,' + LineEnding +
    '   modern card: hairline border, no header band — the separator alone splits it. */' + LineEnding +
    'TyCard {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 12px;' + LineEnding +
    '}' + LineEnding +
    'TyCard:hover { border-color: var(--border-hover); }' + LineEnding +
    'TyCard:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '/* No background => a transparent title band over the card''s own surface. */' + LineEnding +
    'TyCardHeader {' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-bold);' + LineEnding +
    '}' + LineEnding +
    'TyCardActions { border-color: var(--border); border-width: var(--input-border-width); }' + LineEnding +
    '' + LineEnding +
    '/* Neutral tag = a faint on-surface wash; the variants are StyleClasses, and these two' + LineEnding +
    '   land on seeds the palette already has (a ''success''/''warning'' tag would need a new' + LineEnding +
    '   seed colour + its on() pairing first). */' + LineEnding +
    'TyTag {' + LineEnding +
    '  background: var(--overlay-hover);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: var(--radius-round);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  padding: 0px 8px;' + LineEnding +
    '}' + LineEnding +
    'TyTag.accent { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyTag.danger { background: var(--danger); color: var(--on-danger); }' + LineEnding +
    'TyTag:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyTagClose       { color: var(--muted); }' + LineEnding +
    'TyTagClose:hover { background: var(--overlay-hover); color: var(--on-surface); border-radius: var(--radius-sm); }' + LineEnding +
    '' + LineEnding +
    '/* ── Alert + Notification + Empty + Segmented (Ant Design-gap batch 1) ──── */' + LineEnding +
    '' + LineEnding +
    '/* The inline alert bar. The four variant names are a HARD contract: TTyAlert.AlertType maps' + LineEnding +
    '   onto them and draws their icons. A Bootstrap-style tinted banner (pale wash, mid-tint border,' + LineEnding +
    '   deep semantic ink) rather than AntD''s coloured-icon/neutral-text look — the icon shares the' + LineEnding +
    '   bar''s `color`, so one ink has to serve both. error rides the EXISTING --danger seed; info is' + LineEnding +
    '   --accent (info IS the brand colour here); only success/warning needed new seeds. */' + LineEnding +
    'TyAlert {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  padding: 8px 12px;' + LineEnding +
    '}' + LineEnding +
    'TyAlert.info    { background: alpha(var(--accent), 0.10);  border-color: alpha(var(--accent), 0.35);  color: var(--accent); }' + LineEnding +
    'TyAlert.success { background: alpha(var(--success), 0.10); border-color: alpha(var(--success), 0.35); color: var(--success); }' + LineEnding +
    'TyAlert.warning { background: alpha(var(--warning), 0.10); border-color: alpha(var(--warning), 0.35); color: var(--warning); }' + LineEnding +
    'TyAlert.error   { background: alpha(var(--danger), 0.10);  border-color: alpha(var(--danger), 0.35);  color: var(--danger); }' + LineEnding +
    'TyAlert:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyAlertClose       { color: var(--muted); }' + LineEnding +
    'TyAlertClose:hover { background: var(--overlay-hover); color: var(--on-surface); border-radius: var(--radius-sm); }' + LineEnding +
    '' + LineEnding +
    '/* The corner toast. Shaped like TyCard (its nearest kin: a titled surface) so the two agree.' + LineEnding +
    '   The variant''s `color` is the MARK''s ink; the card''s own `color` inks title + message. */' + LineEnding +
    'TyNotification {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 12px 14px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyNotification:hover   { border-color: var(--border-hover); }' + LineEnding +
    'TyNotification.info    { color: var(--accent); }' + LineEnding +
    'TyNotification.success { color: var(--success); }' + LineEnding +
    'TyNotification.warning { color: var(--warning); }' + LineEnding +
    'TyNotification.error   { color: var(--danger); }' + LineEnding +
    '' + LineEnding +
    'TyNotificationClose       { color: var(--muted); }' + LineEnding +
    'TyNotificationClose:hover { background: var(--overlay-hover); color: var(--on-surface); border-radius: var(--radius-sm); }' + LineEnding +
    '' + LineEnding +
    '/* The empty-state placeholder: transparent, because it lies ON the empty list''s own surface. */' + LineEnding +
    'TyEmpty {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--muted);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  padding: 16px;' + LineEnding +
    '}' + LineEnding +
    'TyEmpty:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '/* The picture gets its own ink: it must sit far lighter than the message, and one rule' + LineEnding +
    '   cannot carry two inks. */' + LineEnding +
    'TyEmptyImage { color: var(--border); }' + LineEnding +
    '' + LineEnding +
    '/* The segmented control: a groove holding a lifted thumb. The item radius is deliberately' + LineEnding +
    '   SMALLER than the track''s, which is what reads as "chip sitting in a slot". */' + LineEnding +
    'TySegmented {' + LineEnding +
    '  background: var(--overlay-hover);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TySegmented:focus    { outline: 2px var(--focus-ring); }' + LineEnding +
    'TySegmented:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TySegmentedItem          { color: var(--muted); border-radius: var(--radius-sm);' + LineEnding +
    '                           padding: 4px 10px; font-size: var(--font-size-base); }' + LineEnding +
    'TySegmentedItem:hover    { background: var(--overlay-hover); color: var(--on-surface); }' + LineEnding +
    'TySegmentedItem:selected { background: var(--surface); color: var(--on-surface); }' + LineEnding +
    'TySegmentedItem:disabled { color: var(--muted); }' + LineEnding +
    '' + LineEnding +
    '/* ── Pagination + Steps + Breadcrumb + Transfer + TreeSelect + Cascader + Popover ─────── */' + LineEnding +
    '/* (Ant Design-gap batches 2 & 3. Each control paints NOTHING without its surface key, so' + LineEnding +
    '   these live here in the base: every theme inherits them and can then restyle any of them.) */' + LineEnding +
    '' + LineEnding +
    '/* Pagination: a transparent strip of cells — the page numbers are the chrome, not a bar. */' + LineEnding +
    'TyPagination         { background: alpha(#FFFFFF, 0); color: var(--on-surface); font-size: var(--font-size-base); }' + LineEnding +
    'TyPagination:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyPaginationItem          { background: alpha(#FFFFFF, 0); color: var(--on-surface);' + LineEnding +
    '                            border-color: var(--border); border-width: var(--input-border-width);' + LineEnding +
    '                            border-radius: var(--radius-sm); font-size: var(--font-size-base); padding: 0px 6px; }' + LineEnding +
    'TyPaginationItem:hover    { border-color: var(--accent); color: var(--accent); }' + LineEnding +
    'TyPaginationItem:selected { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyPaginationItem:disabled { color: var(--muted); border-color: var(--border); }' + LineEnding +
    '' + LineEnding +
    '/* Steps: markers on a rail. The done/current/waiting reading is carried by the item states. */' + LineEnding +
    'TySteps         { background: alpha(#FFFFFF, 0); color: var(--on-surface); font-size: var(--font-size-base); }' + LineEnding +
    'TySteps:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '/* The step''s status IS its state (TyStepStates): done => :normal, current => :selected,' + LineEnding +
    '   waiting => :disabled. So the RESTING rule is the DONE look — an accent ring with an accent' + LineEnding +
    '   check — not a neutral one. Getting that backwards (a muted resting rule) makes done and' + LineEnding +
    '   waiting identical but for the glyph, which is the whole information the rail exists to carry. */' + LineEnding +
    'TyStepsItem          { background: var(--surface); color: var(--accent);' + LineEnding +
    '                       border-color: var(--accent); border-width: var(--input-border-width);' + LineEnding +
    '                       border-radius: var(--radius-round); font-size: var(--font-size-base); }' + LineEnding +
    'TyStepsItem:selected { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyStepsItem:hover    { border-color: var(--accent-hover); }' + LineEnding +
    'TyStepsItem:disabled { background: var(--surface-track); color: var(--muted); border-color: var(--border); }' + LineEnding +
    '/* The connector is a plain filled line: it reads ONLY `background` and draws no text, so it' + LineEnding +
    '   deliberately declares no `color` — a colour here would be dead, and (since it would have to' + LineEnding +
    '   match the fill to be right) the lint would flag the pair as low-contrast text.' + LineEnding +
    '   It takes the states of the step it LEADS TO, so these three rules are what make the trail' + LineEnding +
    '   light up exactly as far as you have walked. */' + LineEnding +
    'TyStepsConnector          { background: var(--accent); }   /* into a done step: already walked */' + LineEnding +
    'TyStepsConnector:selected { background: var(--accent); }   /* into the current step */' + LineEnding +
    'TyStepsConnector:disabled { background: var(--border); }   /* not walked yet */' + LineEnding +
    '' + LineEnding +
    '/* Breadcrumb: a transparent trail; the mark takes the BAR''s ink (it has no key of its own). */' + LineEnding +
    'TyBreadcrumb         { background: alpha(#FFFFFF, 0); color: var(--muted); font-size: var(--font-size-base); padding: 2px 4px; }' + LineEnding +
    'TyBreadcrumb:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyBreadcrumbItem          { color: var(--accent); font-size: var(--font-size-base); padding: 0px 4px; }' + LineEnding +
    'TyBreadcrumbItem:hover    { color: var(--accent-hover); }' + LineEnding +
    '/* The last crumb IS the current location: not a link, so it reads as plain ink. */' + LineEnding +
    'TyBreadcrumbItem:selected { color: var(--on-surface); }' + LineEnding +
    'TyBreadcrumbItem:disabled { color: var(--muted); }' + LineEnding +
    '' + LineEnding +
    '/* Transfer: a frame around two list panes and the move rail. The panes/arrows reuse' + LineEnding +
    '   TyListBox / TyButton, which every theme already dresses. */' + LineEnding +
    'TyTransfer {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  padding: 0px;' + LineEnding +
    '}' + LineEnding +
    'TyTransfer:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyTransferTitle { background: var(--surface-chrome); color: var(--on-surface);' + LineEnding +
    '                  border-color: var(--border); border-width: var(--input-border-width);' + LineEnding +
    '                  font-size: var(--font-size-base); font-weight: var(--font-weight-bold); padding: 0px 8px; }' + LineEnding +
    '' + LineEnding +
    '/* TTyTreeSelect deliberately has NO key of its own: GetStyleTypeKey returns ''TyComboBox'',' + LineEnding +
    '   because it IS a combo field — one every theme already dresses, with no key a skin could' + LineEnding +
    '   forget. Its popup is a real TyTreeView and is themed by that key. So there is nothing to' + LineEnding +
    '   declare here; a `TyTreeSelect { … }` rule would be dead CSS that never resolves. Same' + LineEnding +
    '   reasoning as TTyTransfer''s move arrows keeping TTyButton''s key. */' + LineEnding +
    '' + LineEnding +
    '/* Cascader: the field + its multi-column panel. */' + LineEnding +
    'TyCascader {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyCascader:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TyCascader:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyCascader:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyCascaderPanel { background: var(--surface); color: var(--on-surface);' + LineEnding +
    '                  border-color: var(--border); border-width: var(--input-border-width);' + LineEnding +
    '                  border-radius: var(--radius); }' + LineEnding +
    'TyCascaderItem          { background: alpha(#FFFFFF, 0); color: var(--on-surface);' + LineEnding +
    '                          font-size: var(--font-size-base); padding: 0px 8px; }' + LineEnding +
    'TyCascaderItem:hover    { background: var(--surface-listitem-hover); }' + LineEnding +
    'TyCascaderItem:selected { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyCascaderItem:disabled { color: var(--muted); }' + LineEnding +
    '' + LineEnding +
    '/* Popover: a floating surface that HOSTS controls (that is the gap it fills — Hint/BalloonHint' + LineEnding +
    '   can only carry text). The arrow is cut from this same surface, so it needs no key. */' + LineEnding +
    'TyPopover {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 8px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyPopoverTitle { color: var(--on-surface); font-size: var(--font-size-base);' + LineEnding +
    '                 font-weight: var(--font-weight-bold); }' + LineEnding +
    '' + LineEnding +
    '/* Chart: the chart''s own chrome resolves TyPanel and its series ride a fixed code palette,' + LineEnding +
    '   so the hover tooltip is the ONE key it owns. It reads exactly like TyHint because that is' + LineEnding +
    '   what it is — a hint — only painted inside the chart instead of in an OS window. The chart' + LineEnding +
    '   paints NO box without this key (no background = nothing to draw on), so it lives here in' + LineEnding +
    '   the base for every theme to inherit and then restyle. A skin wanting the box to float can' + LineEnding +
    '   add `shadow:` — the control honours it; the base layer stays flat like the rest of light. */' + LineEnding +
    'TyChartTooltip {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: 5px 9px;' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* ── ListGroupPanel (navigation accordion; own keys, not the tree column header''s) ────── */' + LineEnding +
    '/* A modern sider: group rows carry NO fill (just muted ink + a right chevron; the OPEN group' + LineEnding +
    '   turns accent), and a selected item is a SOFT, INSET, ROUNDED pill — never the old full-bleed' + LineEnding +
    '   saturated bar. TTyListGroupPanel insets and rounds the pill in code; the colour/radius here.' + LineEnding +
    '   These are their OWN keys so a theme can restyle the sider without touching TreeView/ListView' + LineEnding +
    '   column headers, which is what TyTreeHeaderSection (the borrowed key) would have wrecked. */' + LineEnding +
    'TyListGroupHeader          { color: var(--muted); font-size: var(--font-size-base); font-weight: var(--font-weight-bold); padding: 0px 14px; }' + LineEnding +
    'TyListGroupHeader:hover    { color: var(--on-surface); }' + LineEnding +
    'TyListGroupHeader:selected { color: var(--accent); }   /* the group is OPEN */' + LineEnding +
    'TyListGroupItem          { color: var(--on-surface); border-radius: var(--radius); font-size: var(--font-size-base); padding: 0px 14px; }' + LineEnding +
    'TyListGroupItem:hover    { background: var(--surface-hover); }' + LineEnding +
    'TyListGroupItem:active   { background: var(--selection); color: var(--accent); }   /* selected: soft accent pill */' + LineEnding +
    'TyListGroupItem:disabled { color: var(--muted); }' + LineEnding;
end;

end.
