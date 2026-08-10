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
    '  /* The fill of the chrome BARS (tool bar, status bar, scroll track), split out from' + LineEnding +
    '     --surface-chrome so a skin can sit them flush on the surface WITHOUT writing a rule for' + LineEnding +
    '     those typeKeys. That matters: any rule a skin writes for a typeKey suppresses the whole' + LineEnding +
    '     base layer for it (see UserHasTypeKey), so a skin that set only `background` on' + LineEnding +
    '     TyStatusBar silently lost its colour/border/font too — an invisible status bar. Retuning' + LineEnding +
    '     one token has no such cliff. Defaults to --surface-chrome, so nothing moves by itself. */' + LineEnding +
    '  --chrome-bar-bg:            var(--surface-chrome);' + LineEnding +
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
    '  /* Tool-bar 1px rules — TTyToolSeparator''s inset line and the tbsDropDown split divider —' + LineEnding +
    '     when the variant''s border-color resolves FULLY transparent. That is the `ghost` case a' + LineEnding +
    '     flat bar (the default) hands every tool, and a rule drawn in it is drawn in nothing; the' + LineEnding +
    '     control then falls back to the resolved TEXT colour dimmed by this alpha (0..255), and 0' + LineEnding +
    '     suppresses the rule entirely. Deliberately NOT in the geometry block below: it is a' + LineEnding +
    '     chrome scalar, not a length, so the density packs must not sweep it up.' + LineEnding +
    '' + LineEnding +
    '     The value must equal TyToolRuleGhostAlpha, the default TyToolRuleInk documents — the' + LineEnding +
    '     token was plumbed before it was declared, so declaring it with any other number would' + LineEnding +
    '     retune every default flat bar with no control-code change. Pinned by' + LineEnding +
    '     test.themes.TestToolRuleAlphaTokenMatchesTheControlDefault.' + LineEnding +
    '' + LineEnding +
    '     ONE value serves BOTH modes, and that is measured, not assumed. The fallback ink is the' + LineEnding +
    '     mode''s own text colour and the ground is the mode''s own chrome, so the pair swaps' + LineEnding +
    '     together: across the 12 built-ins whose ghost ink is --on-surface the composite lands' + LineEnding +
    '     36-50 luma off the bar face in light AND 36-50 in dark. The four skins that come in thin' + LineEnding +
    '     (office 29->9, macos 24->12, aero 21->15, ubuntu 25->18) are not a MODE problem — their' + LineEnding +
    '     ghost ink is a mid-luma accent they do not lift for dark — and a per-mode global alpha' + LineEnding +
    '     big enough to rescue office (~161) would take the base theme''s dark hairline from 40 to' + LineEnding +
    '     128, three times a real border. Those four retune THIS token in their own @mode dark' + LineEnding +
    '     instead; that is what having it in the theme layer buys. Full numbers and the reasoning' + LineEnding +
    '     are in docs/controls/toolbar.md; the sweep is' + LineEnding +
    '     test.modecoherence.TestToolRuleFallbackIsVisibleInBothModes. */' + LineEnding +
    '  --tool-rule-alpha: 50;' + LineEnding +
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
    '' + LineEnding +
    '  /* -- size tokens: control geometry (density phase 3) --' + LineEnding +
    '     classic value == each control''s Pascal constant today; the modern' + LineEnding +
    '     density pack overrides these names. Runtime geometry is not in the' + LineEnding +
    '     golden, so the guard is value==constant + full suite green. */' + LineEnding +
    '  --alert-close-gap: 8px;' + LineEnding +
    '  --alert-close-size: 14px;' + LineEnding +
    '  --alert-icon-gap: 8px;' + LineEnding +
    '  --alert-icon-size: 16px;' + LineEnding +
    '  --alert-text-gap: 2px;' + LineEnding +
    '  --backstage-back-height: 48px;' + LineEnding +
    '  --backstage-icon-size: 18px;' + LineEnding +
    '  --backstage-icon-x: 14px;' + LineEnding +
    '  --backstage-row-height: 42px;' + LineEnding +
    '  --backstage-sidebar-width: 190px;' + LineEnding +
    '  --backstage-text-inset: 40px;' + LineEnding +
    '  --balloon-arrow-size: 8px;' + LineEnding +
    '  --badge-dot-size: 8px;' + LineEnding +
    '  --badge-inset: 2px;' + LineEnding +
    '  --breadcrumb-separator-gap: 2px;' + LineEnding +
    '  --breadcrumb-separator-size: 14px;' + LineEnding +
    '  --caption-button-width: 46px;' + LineEnding +
    '  --card-actions-height: 44px;' + LineEnding +
    '  --card-header-height: 36px;' + LineEnding +
    '  --cascader-column-width: 120px;' + LineEnding +
    '  --cascader-expand-gap: 4px;' + LineEnding +
    '  --cascader-expand-size: 12px;' + LineEnding +
    '  --cascader-row-height: 24px;' + LineEnding +
    '  --chart-tooltip-gap: 10px;' + LineEnding +
    '  --chart-tooltip-swatch: 8px;' + LineEnding +
    '  --chart-tooltip-swatch-gap: 5px;' + LineEnding +
    '  --checkbox-gap: 6px;' + LineEnding +
    '  --checkbox-size: 16px;' + LineEnding +
    '  --dialog-edit-width: 320px;' + LineEnding +
    '  --dialog-padding: 16px;' + LineEnding +
    '  --drop-arrow-width: 18px;' + LineEnding +
    '  --empty-action-height: 32px;' + LineEnding +
    '  --empty-gap: 8px;' + LineEnding +
    '  --empty-image-size: 48px;' + LineEnding +
    '  --expander-header-height: 26px;' + LineEnding +
    '  --field-button-width: 18px;' + LineEnding +
    '  --gallery-arrow-width: 18px;' + LineEnding +
    '  --gallery-cell-width: 56px;' + LineEnding +
    '  --gallery-glyph-pad: 4px;' + LineEnding +
    '  --gallery-grid-cell-height: 44px;' + LineEnding +
    '  --glyph-button-gap: 6px;' + LineEnding +
    '  --grid-comment-mark-size: 7px;' + LineEnding +
    '  --header-control-height: 26px;' + LineEnding +
    '  --header-section-width: 100px;' + LineEnding +
    '  --listgroup-chevron-size: 14px;' + LineEnding +
    '  --listgroup-header-height: 26px;' + LineEnding +
    '  --listgroup-icon-gap: 6px;' + LineEnding +
    '  --listgroup-icon-size: 16px;' + LineEnding +
    '  --listgroup-item-height: 24px;' + LineEnding +
    '  --listgroup-item-indent: 16px;' + LineEnding +
    '  --listgroup-item-inset: 6px;' + LineEnding +
    '  --listview-cell-padding: 3px;' + LineEnding +
    '  --listview-check-size: 14px;' + LineEnding +
    '  --listview-group-header-height: 22px;' + LineEnding +
    '  --listview-hgap: 10px;' + LineEnding +
    '  --listview-icon-label-width: 88px;' + LineEnding +
    '  --listview-label-height: 16px;' + LineEnding +
    '  --listview-large-icon-size: 48px;' + LineEnding +
    '  --listview-small-icon-size: 16px;' + LineEnding +
    '  --listview-small-label-width: 150px;' + LineEnding +
    '  --listview-text-margin: 4px;' + LineEnding +
    '  --listview-tile-label-width: 150px;' + LineEnding +
    '  --listview-vgap: 8px;' + LineEnding +
    '  --menu-arrow-slot: 16px;' + LineEnding +
    '  --menu-check-slot: 18px;' + LineEnding +
    '  --menu-separator-height: 7px;' + LineEnding +
    '  --menu-shortcut-gap: 24px;' + LineEnding +
    '  --notification-close-size: 14px;' + LineEnding +
    '  --notification-gap: 8px;' + LineEnding +
    '  --notification-icon-size: 24px;' + LineEnding +
    '  --notification-margin: 16px;' + LineEnding +
    '  --notification-stack-gap: 8px;' + LineEnding +
    '  --notification-width: 340px;' + LineEnding +
    '  --pagination-gap: 4px;' + LineEnding +
    '  --pagination-glyph-size: 12px;' + LineEnding +
    '  --popover-arrow-size: 8px;' + LineEnding +
    '  --popover-offset: 4px;' + LineEnding +
    '  --popover-title-gap: 6px;' + LineEnding +
    '  --qat-height: 26px;' + LineEnding +
    '  --qat-width: 120px;' + LineEnding +
    '  --ribbon-appmenu-height: 26px;' + LineEnding +
    '  --ribbon-appmenu-width: 64px;' + LineEnding +
    '  --ribbon-caption-band-height: 18px;' + LineEnding +
    '  --scrollbar-size: 12px;' + LineEnding +
    '  --segmented-pad: 2px;' + LineEnding +
    '  --steps-connector-gap: 8px;' + LineEnding +
    '  --steps-connector-length: 32px;' + LineEnding +
    '  --steps-gap: 8px;' + LineEnding +
    '  --steps-marker-size: 24px;' + LineEnding +
    '  --tab-arrow-band: 16px;' + LineEnding +
    '  --tab-close-size: 14px;' + LineEnding +
    '  --tab-gap: 6px;' + LineEnding +
    '  --tab-margin: 6px;' + LineEnding +
    '  --tab-min-width: 48px;' + LineEnding +
    '  --tab-padding: 12px;' + LineEnding +
    '  --tag-close-size: 14px;' + LineEnding +
    '  --tag-gap: 4px;' + LineEnding +
    '  --titlebar-padding: 8px;' + LineEnding +
    '  --transfer-arrow-margin: 3px;' + LineEnding +
    '  --transfer-arrow-size: 12px;' + LineEnding +
    '  --transfer-button-gap: 6px;' + LineEnding +
    '  --transfer-button-height: 26px;' + LineEnding +
    '  --transfer-button-width: 32px;' + LineEnding +
    '  --transfer-rail-width: 56px;' + LineEnding +
    '  --transfer-title-height: 26px;' + LineEnding +
    '  --treeselect-drop-height: 220px;' + LineEnding +
    '  --font-weight-normal: 400; --font-weight-bold: 700;' + LineEnding +
    '  --on-titlebar: var(--on-surface);   /* ink for controls hosted on the title bar */' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Window/form backdrop — a soft off-white behind the white controls. */' + LineEnding +
    'TyForm { background: var(--form-bg); }' + LineEnding +
    '' + LineEnding +
    'TyButton, TySpeedButton, TyGlyphContainerButton, TyRibbonAppMenu, TyButtonGroup, TyUpDown {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-button);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    'TyButton:hover, TySpeedButton:hover, TyGlyphContainerButton:hover, TyRibbonAppMenu:hover, TyButtonGroup:hover, TyUpDown:hover    { background: var(--surface-hover); border-color: var(--input-border-hover); }' + LineEnding +
    'TyButton:focus, TySpeedButton:focus, TyGlyphContainerButton:focus, TyRibbonAppMenu:focus, TyButtonGroup:focus, TyUpDown:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyButton:active, TySpeedButton:active, TyGlyphContainerButton:active, TyRibbonAppMenu:active, TyButtonGroup:active, TyUpDown:active   { background: var(--surface-active); }TyButton:disabled, TySpeedButton:disabled, TyGlyphContainerButton:disabled, TyRibbonAppMenu:disabled, TyButtonGroup:disabled, TyUpDown:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyButton.primary, TySpeedButton.primary, TyGlyphContainerButton.primary, TyRibbonAppMenu.primary, TyButtonGroup.primary, TyUpDown.primary  { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }TyButton.primary:hover, TySpeedButton.primary:hover, TyGlyphContainerButton.primary:hover, TyRibbonAppMenu.primary:hover, TyButtonGroup.primary:hover, TyUpDown.primary:hover    { background: var(--accent-hover); }TyButton.primary:active, TySpeedButton.primary:active, TyGlyphContainerButton.primary:active, TyRibbonAppMenu.primary:active, TyButtonGroup.primary:active, TyUpDown.primary:active   { background: var(--accent-active); }' + LineEnding +
    'TyButton.danger, TySpeedButton.danger, TyGlyphContainerButton.danger, TyRibbonAppMenu.danger, TyButtonGroup.danger, TyUpDown.danger   { background: var(--danger); color: var(--on-danger); border-color: var(--danger); }TyButton.danger:hover, TySpeedButton.danger:hover, TyGlyphContainerButton.danger:hover, TyRibbonAppMenu.danger:hover, TyButtonGroup.danger:hover, TyUpDown.danger:hover     { background: var(--danger-hover); }TyButton.danger:active, TySpeedButton.danger:active, TyGlyphContainerButton.danger:active, TyRibbonAppMenu.danger:active, TyButtonGroup.danger:active, TyUpDown.danger:active    { background: var(--danger-active); }' + LineEnding +
    '/* Ghost (VS Code 风格): 平时透明,仅 hover/active/选中显示底色与边框。透明用 alpha(...,0)' + LineEnding +
    '   保持纯色,使现有 hover 背景 alpha 淡入有效;边框透明但保留宽度,避免 hover 尺寸跳动。 */' + LineEnding +
    'TyButton.ghost, TySpeedButton.ghost, TyGlyphContainerButton.ghost, TyRibbonAppMenu.ghost, TyButtonGroup.ghost, TyUpDown.ghost {' + LineEnding +
    '  background: alpha(var(--surface-hover), 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: alpha(var(--border), 0);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-button);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}TyButton.ghost:hover, TySpeedButton.ghost:hover, TyGlyphContainerButton.ghost:hover, TyRibbonAppMenu.ghost:hover, TyButtonGroup.ghost:hover, TyUpDown.ghost:hover    { background: var(--surface-hover); border-color: var(--input-border-hover); }TyButton.ghost:active, TySpeedButton.ghost:active, TyGlyphContainerButton.ghost:active, TyRibbonAppMenu.ghost:active, TyButtonGroup.ghost:active, TyUpDown.ghost:active   { background: var(--surface-active); }TyButton.ghost:selected, TySpeedButton.ghost:selected, TyGlyphContainerButton.ghost:selected, TyRibbonAppMenu.ghost:selected, TyButtonGroup.ghost:selected, TyUpDown.ghost:selected { background: var(--surface-active); border-color: var(--accent); }TyButton.ghost:focus, TySpeedButton.ghost:focus, TyGlyphContainerButton.ghost:focus, TyRibbonAppMenu.ghost:focus, TyButtonGroup.ghost:focus, TyUpDown.ghost:focus    { outline: 2px var(--focus-ring); }TyButton.ghost:disabled, TySpeedButton.ghost:disabled, TyGlyphContainerButton.ghost:disabled, TyRibbonAppMenu.ghost:disabled, TyButtonGroup.ghost:disabled, TyUpDown.ghost:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyLabel, TyHtmlLabel, TyLinkLabel, TyShadowLabel, TyGlowLabel, TyDivider, TyCharImage {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    'TyLabel:disabled, TyHtmlLabel:disabled, TyLinkLabel:disabled, TyShadowLabel:disabled, TyGlowLabel:disabled, TyDivider:disabled, TyCharImage:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyEdit {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-control);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyEdit:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TyEdit:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyEdit:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    '/* An edit EMBEDDED in another control''s field. The editable combo box puts a real TTyEdit over' + LineEnding +
    '   its text zone, and that editor was drawing its OWN field frame INSIDE the combo''s -- two' + LineEnding +
    '   rounded borders, with the drop chevron squeezed into the gap between them. The host already' + LineEnding +
    '   drew the field (background, border, radius) and owns the focus ring; the embedded editor' + LineEnding +
    '   carries the text and the caret only.' + LineEnding +
    '   The BACKGROUND is deliberately left to the base rule rather than set transparent: this is a' + LineEnding +
    '   windowed control, and a transparent windowed control erases to its parent''s LCL Color, not to' + LineEnding +
    '   the field its host painted. */' + LineEnding +
    'TyEdit.embedded         { border-width: 0; border-radius: 0; }' + LineEnding +
    'TyEdit.embedded:hover   { border-color: transparent; }' + LineEnding +
    'TyEdit.embedded:focus   { border-color: transparent; outline: 0px transparent; }' + LineEnding +
    '' + LineEnding +
    'TyCheckBox {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: var(--pad-control);' + LineEnding +
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
    '  padding: var(--pad-control);' + LineEnding +
    '}' + LineEnding +
    'TyRadioButton:hover    { border-color: var(--accent); }' + LineEnding +
    'TyRadioButton:active   { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyRadioButton:focus { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyRadioButton:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    '/* TyScrollBox (the scrolling WELL, which conventionally sinks where a panel lifts) and' + LineEnding +
    '   TyExPanel (a collapsible card) used to render as plain panels because they returned' + LineEnding +
    '   ''TyPanel''. Same values, three separable names. TTyScrollPanel and TTyPaintPanel are' + LineEnding +
    '   deliberately NOT here: they add no chrome of their own and keep inheriting. */' + LineEnding +
    'TyPanel, TyScrollBox, TyExPanel, TyChart, TyCalculator, TyBevel, TySizeBox, TyControlBar, TyCoolBar, TyColorGrid, TyShape, TyStarShape, TyArrow, TyImageView, TyImage, TyPreviewBox, TyListGroupPanel {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-container);' + LineEnding +
    '}' + LineEnding +
    '/* The scrolling containers'' VIEWPORT (TTyScrollContent — the windowed child that clips the' + LineEnding +
    '   scrolled content inside TTyScrollBox / TTyScrollPanel). Background only, ON PURPOSE: the' + LineEnding +
    '   frame belongs to the box around it, and a second frame here would land exactly where the' + LineEnding +
    '   content is meant to run under — so this is TyScrollBox''s surface, alone, under its own key.' + LineEnding +
    '   This rule EXISTING AT ALL is the fix, not its value. TTyScrollContent.Paint fills its' + LineEnding +
    '   resolved background and nothing else, guarded by `if tpBackground in S.Present`; no layer' + LineEnding +
    '   defined this key, so the guard was always False and the viewport painted NOTHING — leaving' + LineEnding +
    '   whatever the widgetset erased the window with. TTyForm.ApplyChromeTheme re-seeds that erase' + LineEnding +
    '   colour only for SOLID form backgrounds, so on a gradient-form skin (aero) it stays a stale' + LineEnding +
    '   light grey: in dark mode the viewport surfaced as a LIGHT patch lining every scroll well.' + LineEnding +
    '   Solid on purpose too: the viewport is a real window compositing over that erase colour, so' + LineEnding +
    '   a translucent value here would blend with garbage rather than with the page.' + LineEnding +
    '   test.modecoherence sweeps this key in BOTH modes and holds it to an opacity floor' + LineEnding +
    '   (cMustPaintKeys) — for a paint-nothing-else control, "absent" IS the bug, and the sweep''s' + LineEnding +
    '   transparent-skip lenience would otherwise wave it straight through. */' + LineEnding +
    'TyScrollContent { background: var(--surface); }' + LineEnding +
    '/* The collapsible panel''s HEADER BAND — caption + chevron ink, and the band''s own hover.' + LineEnding +
    '   Only `color` is declared, and it is TyPanel''s colour, so the caption and caret draw' + LineEnding +
    '   exactly as they did when they read the panel''s own style. Background is left out ON' + LineEnding +
    '   PURPOSE: the band tint is opt-in in the painter (declare one and the band fills; say' + LineEnding +
    '   nothing and the panel''s single surface shows through un-reblended, which is what' + LineEnding +
    '   happens today). font-size / font-weight are likewise omitted so the caption keeps' + LineEnding +
    '   following the control''s font, as TyPanel declares neither.' + LineEnding +
    '   '':hover'' on this key is the new axis — the control has tracked band hover all along' + LineEnding +
    '   but had no name to repaint through. */' + LineEnding +
    'TyExPanelHeader { color: var(--on-surface); }' + LineEnding +
    '' + LineEnding +
    'TyComboBox {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-control);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyComboBox:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TyComboBox:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyComboBox:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyScrollBar {' + LineEnding +
    '  background: var(--chrome-bar-bg);' + LineEnding +
    '  color: var(--scroll-handle);' + LineEnding +
    '  border-radius: var(--radius-scroll);' + LineEnding +
    '}' + LineEnding +
    'TyScrollBar:hover  { color: var(--scroll-handle-hover); }' + LineEnding +
    'TyScrollBar:active { color: var(--accent); }' + LineEnding +
    'TyScrollBar:focus  { outline: 2px var(--focus-ring); }' + LineEnding +
    'TyScrollBar:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyTitleBar, TyRibbonQuickAccess {' + LineEnding +
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
    '/* TTyValueListEditor is a PROPERTY GRID that happens to be built on the list box, so it' + LineEnding +
    '   gets its own frame + row keys (the other five list-box subclasses keep sharing these' + LineEnding +
    '   two — they really are lists of strings). Its remaining parts — TyValueListEditorKey,' + LineEnding +
    '   -Value, -Expander, -Divider — are deliberately left undefined; see the note at the end' + LineEnding +
    '   of this file. */' + LineEnding +
    'TyListBox, TyValueListEditor, TyRibbonGallery {' + LineEnding +
    '  background: var(--input-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-tight);' + LineEnding +
    '}' + LineEnding +
    'TyListBox:hover, TyValueListEditor:hover, TyRibbonGallery:hover   { border-color: var(--input-border-hover); }' + LineEnding +
    'TyListBox:focus, TyValueListEditor:focus, TyRibbonGallery:focus   { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyListBox:disabled, TyValueListEditor:disabled, TyRibbonGallery:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    'TyListItem, TyValueListEditorRow {' + LineEnding +
    '  background: alpha(#000000, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-control);' + LineEnding +
    '}' + LineEnding +
    'TyListItem:hover, TyValueListEditorRow:hover  { background: var(--surface-listitem-hover); }' + LineEnding +
    'TyListItem:active, TyValueListEditorRow:active { background: var(--accent); color: var(--on-accent); border-radius: 0; }' + LineEnding +
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
    '/* --- Instrument family -----------------------------------------------------' + LineEnding +
    '   Fourteen unrelated controls used to HARDCODE ''TyGauge'' as their own type key, so a' + LineEnding +
    '   skin could not tell a star rating from an analogue clock. Each now owns its key and' + LineEnding +
    '   they share ONE rule block as a selector list: identical resolved values today, a' + LineEnding +
    '   separable hook from today on. Override just TyRating (or just TyRatingStar) in a skin' + LineEnding +
    '   and nothing else in the family moves.' + LineEnding +
    '   The four selectors after TyHSColorPicker are SUB-PARTS that read the face, not the' + LineEnding +
    '   fill: TyMeterTick + TyAnalogClockHand take `color`, TyGearDialTeeth takes `background`.' + LineEnding +
    '   They are resolved with an empty state set, which is why they are absent from the' + LineEnding +
    '   :disabled rule below. TyColorArea is the colour dialog''s HSV square / hue bar — the' + LineEnding +
    '   key existed in code since v1 but no theme had ever defined it. */' + LineEnding +
    'TyGauge, TyMeter, TyLevelMeter, TyDial, TyGearDial, TyAnalogClock, TyCircularProgress,' + LineEnding +
    'TyActivityIndicator, TyActivityBar, TyGearActivityIndicator, TySparkline, TyRating,' + LineEnding +
    'TyLColorPicker, TyHSColorPicker, TyMeterTick, TyAnalogClockHand, TyGearDialTeeth, TyColorArea {' + LineEnding +
    '  background: var(--surface-sunk);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    'TyGauge:disabled, TyMeter:disabled, TyLevelMeter:disabled, TyDial:disabled, TyGearDial:disabled,' + LineEnding +
    'TyAnalogClock:disabled, TyCircularProgress:disabled, TyActivityIndicator:disabled,' + LineEnding +
    'TyActivityBar:disabled, TyGearActivityIndicator:disabled, TySparkline:disabled,' + LineEnding +
    'TyRating:disabled, TyLColorPicker:disabled, TyHSColorPicker:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '' + LineEnding +
    '/* The lit part of each instrument. Same story: one accent rule, thirteen reachable' + LineEnding +
    '   names. TyRatingStar takes no :hover rule on purpose — with none it falls back to this' + LineEnding +
    '   block, exactly as the stars painted before; a skin that WANTS a hover tint adds' + LineEnding +
    '   ''TyRatingStar:hover'' and that is the newly-opened axis. */' + LineEnding +
    'TyGaugeFill, TyMeterNeedle, TyLevelMeterFill, TyLevelMeterPeak, TyDialPointer,' + LineEnding +
    'TyGearDialPointer, TyAnalogClockSecondHand, TyCircularProgressFill, TyActivityIndicatorFill,' + LineEnding +
    'TyActivityBarFill, TyGearActivityIndicatorFill, TySparklineFill, TySparklineDot, TyRatingStar {' + LineEnding +
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
    '  padding: var(--pad-tooltip);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Ribbon (Phase-3): the command band surface + the labelled group box. */' + LineEnding +
    'TyRibbon, TyRibbonBackstage {' + LineEnding +
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
    '  /* NO background -- deliberately. The control INHERITS whatever surface it sits on, the same' + LineEnding +
    '     way TyGridPanelCell does: leave the property unset and TyFillParentBg hands it the parent''s' + LineEnding +
    '     painted slice (gradient, photo, whatever), instead of plating over it.' + LineEnding +
    '     It used to fill its whole client rect with --surface-track. Two complaints came out of that' + LineEnding +
    '     single line: the bar read as a darker SLAB on every theme (and as a neutral grey slab on' + LineEnding +
    '     aero, whose surface is cold blue), and the tick marks -- drawn inside that same rect -- sat' + LineEnding +
    '     ON the track rather than beside it, because there WAS no track, only the control. The' + LineEnding +
    '     recess now lives on TyTrackGroove below, which is what --surface-track was always for. */' + LineEnding +
    '  /* The ShowValue readout''s ink. Without it TextColor resolves to the unset default' + LineEnding +
    '     $00000000 -- alpha 0 -- so ShowValue reserved the strip, shortened the track and then' + LineEnding +
    '     painted the number in a fully transparent colour. It has never been visible in any' + LineEnding +
    '     theme, which is why the trackbar example hand-rolled a readout out of a separate' + LineEnding +
    '     label instead of using the one the control already has. */' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  padding: var(--pad-none);' + LineEnding +
    '}' + LineEnding +
    '/* The groove: a thin recessed band the thumb rides in, centred in whatever height is left' + LineEnding +
    '   after the tick bands are reserved. Rounded to its own half-thickness, which is what every' + LineEnding +
    '   platform draws and what --radius-sm was never going to give a 4px band. */' + LineEnding +
    'TyTrackGroove {' + LineEnding +
    '  background: var(--surface-track);' + LineEnding +
    '  border-radius: var(--radius-round);' + LineEnding +
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
    '/* Hyperlink ink for TTyLinkLabel. Its own key rather than a borrowed accent fill: a theme' + LineEnding +
    '   that restyles gauges must not repaint every link, and a theme that wants a different link' + LineEnding +
    '   colour must not have to repaint gauges. */' + LineEnding +
    'TyLinkLabelLink { color: var(--accent); }' + LineEnding +
    '' + LineEnding +
    '' + LineEnding +
    '/* TTyToolGroupPanel is a ribbon-style command cluster, not a form group box; it gets its' + LineEnding +
    '   own name so a skin can flatten the cluster without flattening every group box. Caption' + LineEnding +
    '   PLACEMENT stays TTyGroupBox''s top band — this key changes ink and chrome, not layout. */' + LineEnding +
    'TyGroupBox, TyToolGroupPanel {' + LineEnding +
    '  padding: var(--pad-groupbox);' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* ── v1.2 controls ─────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyTabControl, TyTabSet {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    'TyTabControl:hover, TyTabSet:hover  { border-color: var(--input-border-hover); }' + LineEnding +
    'TyTabControl:focus, TyTabSet:focus  { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyTabControl:disabled, TyTabSet:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
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
    '  padding: var(--pad-control);' + LineEnding +
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
    '  padding: var(--pad-control);' + LineEnding +
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
    '  padding: var(--pad-control);' + LineEnding +
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
    '  padding: var(--pad-badge);' + LineEnding +
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
    '  padding: var(--pad-tight);' + LineEnding +
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
    '  padding: var(--pad-control);' + LineEnding +
    '}' + LineEnding +
    'TyMenuPopup {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: var(--pad-control);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* A single menu row / bar cell. The base border-color is the separator-line ink. */' + LineEnding +
    'TyMenuItem {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: var(--pad-control);' + LineEnding +
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
    '  background: var(--surface-hover);' + LineEnding +
    '  color: var(--accent);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyStatusBar {' + LineEnding +
    '  background: var(--chrome-bar-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-normal);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* The separator needs BOTH declarations from this block: `border-color` draws its rule and' + LineEnding +
    '   `background` is what keeps it seamless with the bar behind it. Sharing the block is what' + LineEnding +
    '   makes that automatic; owning the name is what lets a skin dot/fade/hide just the rule. */' + LineEnding +
    'TyToolBar, TyToolSeparator {' + LineEnding +
    '  background: var(--chrome-bar-bg);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* ── Calendar + DateTimePicker ─────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyCalendar { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: var(--pad-button); font-size: var(--font-size-base); }' + LineEnding +
    'TyCalendarTitle { color: var(--on-surface); font-weight: var(--font-weight-bold); font-size: var(--font-size-title); }' + LineEnding +
    'TyCalendarTitle:hover { color: var(--accent); }' + LineEnding +
    'TyCalendarWeekday { color: var(--muted); font-size: var(--font-size-base); }' + LineEnding +
    'TyCalendarCell { background: none; color: var(--on-surface); border-radius: var(--radius-sm); }' + LineEnding +
    'TyCalendarCell:hover { background: var(--surface-hover); }' + LineEnding +
    'TyCalendarCell:selected { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyCalendarCell:disabled { color: var(--muted); }' + LineEnding +
    'TyDateTimePicker { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: var(--pad-datetime); font-size: var(--font-size-base); }' + LineEnding +
    'TyDateTimePicker:hover { border-color: var(--input-border-hover); }' + LineEnding +
    'TyDateTimePicker:focus { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyDateTimePicker:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyDateTimeButton { background: var(--surface-chrome); color: var(--on-surface); }' + LineEnding +
    'TyDateTimeButton:hover { background: var(--surface-hover); color: var(--accent); }' + LineEnding +
    '' + LineEnding +
    '/* ── TreeView + ListView ───────────────────────────────────────────────── */' + LineEnding +
    '/* TTyListView used to wear the tree''s clothes entirely — frame, rows, header, checkbox —' + LineEnding +
    '   and worse, its column-header band and its collapsible GROUP band resolved the SAME' + LineEnding +
    '   ''TyTreeHeader'' literal, so the two could never be styled apart. Both now have names' + LineEnding +
    '   (TyListViewHeader / TyListViewGroupHeader) and share this one rule, so today they still' + LineEnding +
    '   look the same and a skin can finally separate them.' + LineEnding +
    '   TyListViewLine and TyListViewMarquee are deliberately left undefined; see the note at' + LineEnding +
    '   the end of this file. */' + LineEnding +
    '' + LineEnding +
    'TyTreeView, TyListView { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: var(--pad-tight); font-size: var(--font-size-base); }' + LineEnding +
    'TyTreeNode, TyListViewItem { background: none; color: var(--on-surface); }' + LineEnding +
    'TyTreeNode:hover, TyListViewItem:hover { background: var(--surface-hover); }' + LineEnding +
    'TyTreeNode:selected, TyListViewItem:selected { background: var(--accent); color: var(--on-accent); }' + LineEnding +
    'TyTreeNode:disabled, TyListViewItem:disabled { color: var(--muted); }' + LineEnding +
    'TyTreeHeader, TyListViewHeader, TyListViewGroupHeader, TyHeaderControl { background: var(--surface-chrome); border-color: var(--border); border-width: var(--input-border-width); color: var(--on-surface); font-size: var(--font-size-base); font-weight: var(--font-weight-bold); }' + LineEnding +
    'TyTreeHeaderSection, TyListViewHeaderSection { background: none; color: var(--on-surface); border-color: var(--border); }' + LineEnding +
    'TyTreeHeaderSection:hover, TyListViewHeaderSection:hover { background: var(--surface-hover); }' + LineEnding +
    'TyTreeHeaderSection:selected, TyListViewHeaderSection:selected { background: var(--surface-active); }' + LineEnding +
    '' + LineEnding +
    '/* --- 数据网格 TTyGrid ------------------------------------------------------' + LineEnding +
    '   基层给全套键,新皮肤即使一条网格规则都不写也能正常显示(基层垫在每个主题之下)。' + LineEnding +
    '   网格自成一套 typeKey,不借用树/列表的键 —— 借来的键在外观主题层够不着。 */' + LineEnding +
    'TyGrid { background: var(--surface); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius-sm); font-size: var(--font-size-base); }' + LineEnding +
    '/* 正文单元格。resting 透明,让网格表面透出来;选中/悬停才上色。 */' + LineEnding +
    'TyGridCell { background: none; color: var(--on-surface); padding: var(--pad-cell); }' + LineEnding +
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
    '/* 按下态("列头按下去"的观感)。这条规则以前不存在,于是按下的列头解析回 base 的' + LineEnding +
    '   `background: none` —— 与静止态一模一样,看不出被按下。与其发布一个控件不照办的标志,' + LineEnding +
    '   不如先把缝补上;这条规则补的就是那个缝,控件侧的 goHeaderPushedLook 随后接上。' + LineEnding +
    '   取值走 --surface-active(darken(--surface,10%))—— 本库"按下"一律用它' + LineEnding +
    '   (见 TyButton:active),不新造硬编码值。它比列头带自己的 --surface-chrome' + LineEnding +
    '   (darken 6%)更深,所以按下的那一段在带子上读得出来。' + LineEnding +
    '   只写在**基层**这一份:--surface-active 是派生式,各模式的 seed 自己会换,dark 下无需再写一条。' + LineEnding +
    '   与 :selected 同值是有意的:两者都是"这一段正被使用",而真正的差别是相对 base' + LineEnding +
    '   的 `none` —— 按下去现在有底色了。tests/test.themes 的 golden 第 2 号状态槽' + LineEnding +
    '   (STATES[2] = [tysActive])把这条钉住。 */' + LineEnding +
    'TyGridHeaderSection:active   { background: var(--surface-active); }' + LineEnding +
    '/* 分组表头带(横跨若干列的上层标题)。自己的键 —— 与叶子列头分开配才有意义。 */' + LineEnding +
    'TyGridHeaderGroup { background: var(--surface-active); color: var(--on-surface); border-color: var(--border); }' + LineEnding +
    '/* 内嵌筛选行。它是"能打字的地方",所以底色跟表面走、边框跟输入框走 ——' + LineEnding +
    '   与列头带(chrome 色)刻意区分开,否则用户看不出它可以输入。 */' + LineEnding +
    'TyGridFilterRow { background: var(--surface); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); font-size: var(--font-size-base); }' + LineEnding +
    '/* Group band (TTyStringGrid grouping) and summary/footer band. Both keys have been' + LineEnding +
    '   resolved by the code since grouping landed, but NO theme ever defined them, so they' + LineEnding +
    '   fell through to an empty style: no band fill at all, and the ink borrowed the grid' + LineEnding +
    '   frame''s colour. These two rules SAY that out loud instead of leaving it to a silent' + LineEnding +
    '   fallback, and they say it in tokens so a skin can change it.' + LineEnding +
    '   `background: none` is the current appearance, deliberately: giving either band the' + LineEnding +
    '   conventional chrome tint would be an appearance change, and this pass is a pure' + LineEnding +
    '   themability refactor. A skin wanting the tint writes `background: var(--surface-chrome)`.' + LineEnding +
    '   Font is left undeclared on purpose (same as TyGridCell) so the bands keep following the' + LineEnding +
    '   grid''s own font; both keys DO read font-name/-size/-weight if a skin declares them.' + LineEnding +
    '   TyGridSummaryRow deliberately has no border-color: RenderFooter never reads one, so a' + LineEnding +
    '   declaration here would be dead. A footer hairline needs a code change first. */' + LineEnding +
    'TyGridGroupRow   { background: none; color: var(--on-surface); }' + LineEnding +
    'TyGridSummaryRow { background: none; color: var(--on-surface); }' + LineEnding +
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
    'TyTreeCheckBox, TyListViewCheckBox { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius-sm); }' + LineEnding +
    'TyTreeCheckBox:active, TyListViewCheckBox:active   { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyTreeCheckBox:selected, TyListViewCheckBox:selected { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyTreeCheckBox:disabled, TyListViewCheckBox:disabled { color: var(--muted); }' + LineEnding +
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
    '  padding: var(--pad-card);' + LineEnding +
    '}' + LineEnding +
    'TyCard:hover { border-color: var(--border-hover); }' + LineEnding +
    'TyCard:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    '/* No background => a transparent title band over the card''s own surface. */' + LineEnding +
    'TyCardHeader {' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  font-size: var(--font-size-title);' + LineEnding +
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
    '  padding: var(--pad-chip);' + LineEnding +
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
    '  padding: var(--pad-alert);' + LineEnding +
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
    '  padding: var(--pad-notification);' + LineEnding +
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
    '  padding: var(--pad-empty);' + LineEnding +
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
    '                           padding: var(--pad-segmented); font-size: var(--font-size-base); }' + LineEnding +
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
    '                            border-radius: var(--radius-sm); font-size: var(--font-size-base); padding: var(--pad-cell); }' + LineEnding +
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
    'TyBreadcrumb         { background: alpha(#FFFFFF, 0); color: var(--muted); font-size: var(--font-size-base); padding: var(--pad-breadcrumb); }' + LineEnding +
    'TyBreadcrumb:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyBreadcrumbItem          { color: var(--accent); font-size: var(--font-size-base); padding: var(--pad-breadcrumb-item); }' + LineEnding +
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
    '  padding: var(--pad-none);' + LineEnding +
    '}' + LineEnding +
    'TyTransfer:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyTransferTitle { background: var(--surface-chrome); color: var(--on-surface);' + LineEnding +
    '                  border-color: var(--border); border-width: var(--input-border-width);' + LineEnding +
    '                  font-size: var(--font-size-title); font-weight: var(--font-weight-bold); padding: var(--pad-chip); }' + LineEnding +
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
    '  padding: var(--pad-control);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyCascader:hover    { border-color: var(--input-border-hover); }' + LineEnding +
    'TyCascader:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }' + LineEnding +
    'TyCascader:disabled { opacity: var(--disabled-opacity); }' + LineEnding +
    'TyCascaderPanel { background: var(--surface); color: var(--on-surface);' + LineEnding +
    '                  border-color: var(--border); border-width: var(--input-border-width);' + LineEnding +
    '                  border-radius: var(--radius); }' + LineEnding +
    'TyCascaderItem          { background: alpha(#FFFFFF, 0); color: var(--on-surface);' + LineEnding +
    '                          font-size: var(--font-size-base); padding: var(--pad-chip); }' + LineEnding +
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
    '  padding: var(--pad-container);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    'TyPopoverTitle { color: var(--on-surface); font-size: var(--font-size-title);' + LineEnding +
    '                 font-weight: var(--font-weight-bold); }' + LineEnding +
    '' + LineEnding +
    '/* Chart: the chart''s own chrome resolves TyPanel; the hover tooltip and the eight series' + LineEnding +
    '   slots are the keys it owns. The tooltip reads exactly like TyHint because that is what it' + LineEnding +
    '   is — a hint — only painted inside the chart instead of in an OS window. The chart' + LineEnding +
    '   paints NO box without this key (no background = nothing to draw on), so it lives here in' + LineEnding +
    '   the base for every theme to inherit and then restyle. A skin wanting the box to float can' + LineEnding +
    '   add `shadow:` — the control honours it; the base layer stays flat like the rest of light. */' + LineEnding +
    'TyChartTooltip {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius-sm);' + LineEnding +
    '  padding: var(--pad-tooltip);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* The series palette. A series with no explicit Color rides slot (index mod 8), and each slot' + LineEnding +
    '   is a KEY so a skin can retint the data itself — previously these eight hues were a const' + LineEnding +
    '   array in the control and no theme could reach them. The values are the Tableau-10 hues the' + LineEnding +
    '   code carried, so the base layer draws exactly what it always drew; a skin overrides only the' + LineEnding +
    '   slots it cares about. Pie slices use the same slots. `background` is the ink (a series is a' + LineEnding +
    '   filled shape); the control keeps its own const as a last-resort fallback. */' + LineEnding +
    'TyChartSeries1 { background: #4E79A7; }   /* blue   */' + LineEnding +
    'TyChartSeries2 { background: #F28E2B; }   /* orange */' + LineEnding +
    'TyChartSeries3 { background: #E15759; }   /* red    */' + LineEnding +
    'TyChartSeries4 { background: #76B7B2; }   /* teal   */' + LineEnding +
    'TyChartSeries5 { background: #59A14F; }   /* green  */' + LineEnding +
    'TyChartSeries6 { background: #EDC948; }   /* yellow */' + LineEnding +
    'TyChartSeries7 { background: #B07AA1; }   /* purple */' + LineEnding +
    'TyChartSeries8 { background: #FF9DA7; }   /* pink   */' + LineEnding +
    '' + LineEnding +
    '/* ── ListGroupPanel (navigation accordion; own keys, not the tree column header''s) ────── */' + LineEnding +
    '/* A modern sider: group rows carry NO fill (just muted ink + a right chevron; the OPEN group' + LineEnding +
    '   turns accent), and a selected item is a SOFT, INSET, ROUNDED pill — never the old full-bleed' + LineEnding +
    '   saturated bar. TTyListGroupPanel insets and rounds the pill in code; the colour/radius here.' + LineEnding +
    '   These are their OWN keys so a theme can restyle the sider without touching TreeView/ListView' + LineEnding +
    '   column headers, which is what TyTreeHeaderSection (the borrowed key) would have wrecked. */' + LineEnding +
    'TyListGroupHeader          { color: var(--muted); font-size: var(--font-size-base); font-weight: var(--font-weight-bold); padding: var(--pad-group-header); }' + LineEnding +
    'TyListGroupHeader:hover    { color: var(--on-surface); }' + LineEnding +
    'TyListGroupHeader:selected { color: var(--accent); }   /* the group is OPEN */' + LineEnding +
    'TyListGroupItem          { color: var(--on-surface); border-radius: var(--radius); font-size: var(--font-size-base); padding: var(--pad-group-header); }' + LineEnding +
    'TyListGroupItem:hover    { background: var(--surface-hover); }' + LineEnding +
    'TyListGroupItem:active   { background: var(--selection); color: var(--accent); }   /* selected: soft accent pill */' + LineEnding +
    'TyListGroupItem:disabled { color: var(--muted); }' + LineEnding +
    '' + LineEnding +
    '/* ── Keys the CODE resolves that this file deliberately does NOT define ─────────────────' + LineEnding +
    '   Not drift — each of these is an OPT-IN hook whose painter has an explicit fallback, and' + LineEnding +
    '   in every case the fallback is STATE-DEPENDENT, so declaring a fixed value here would' + LineEnding +
    '   move pixels rather than preserve them. A skin may declare any of them; the base layer' + LineEnding +
    '   stays silent so the fallback keeps winning by default.' + LineEnding +
    '' + LineEnding +
    '     TyListViewLine        background -> else the list view frame''s border-color' + LineEnding +
    '     TyListViewMarquee     background -> else TyListViewItem:selected''s background' + LineEnding +
    '     TyValueListEditorKey       color -> else the ROW''s colour for the row''s current state' + LineEnding +
    '     TyValueListEditorValue     color -> else the same' + LineEnding +
    '     TyValueListEditorExpander  color -> else the same' + LineEnding +
    '     TyValueListEditorDivider   background -> else the row''s colour at alpha 0x28' + LineEnding +
    '' + LineEnding +
    '   The row-derived four are the sharp edge: on a selected row the fallback ink is' + LineEnding +
    '   --on-accent, so a flat `color: var(--on-surface)` here would turn a selected property' + LineEnding +
    '   row''s key text unreadable. A skin that wants them must declare the :active/:hover' + LineEnding +
    '   variants too.' + LineEnding +
    '' + LineEnding +
    '   Also undefined ON PURPOSE and NOT part of this list: TyGridPanel and TyGridPanelCell' + LineEnding +
    '   (the layout grid and its cells are scaffolding, not surfaces — both stay transparent so' + LineEnding +
    '   the gutters and the cells alike take the colour of whatever the grid sits on, gradient' + LineEnding +
    '   included; their Paint falls back to TyFillParentBg. tests/test.gridpanel.pas asserts no' + LineEnding +
    '   theme gives EITHER of them a background, and that a theme which defines one still gets' + LineEnding +
    '   it) and TyFormSurface.' + LineEnding +
    '' + LineEnding +
    '   TyGridPanelCell is NOT the data grid''s TyGridCell, which IS defined above: the layout' + LineEnding +
    '   cell used to answer to that name, which both leaked the data cell''s rules onto it and' + LineEnding +
    '   left it unreachable from the theme layer. */' + LineEnding +
    '' + LineEnding +
    '/* Controls hosted ON the title bar. A skin that paints the bar in a strong colour leaves an' + LineEnding +
    '   ordinary button''s surface-tuned ink nearly invisible there; the control appends the' + LineEnding +
    '   ''on-titlebar'' variant automatically (TyStyleClassFor), so this is the only place a theme' + LineEnding +
    '   has to say what belongs on its own bar. Composed with whatever class the host set, so a' + LineEnding +
    '   ghost button on a title bar stays a ghost button and only its ink moves. */' + LineEnding +
    'TyButton.on-titlebar, TySpeedButton.on-titlebar, TyGlyphButton.on-titlebar,' + LineEnding +
    'TyGlyphContainerButton.on-titlebar, TyDropDownButton.on-titlebar,' + LineEnding +
    'TyMenuButton.on-titlebar, TyColorButton.on-titlebar, TyButtonGroup.on-titlebar,' + LineEnding +
    'TyLabel.on-titlebar, TyCheckBox.on-titlebar, TyToggleSwitch.on-titlebar {' + LineEnding +
    '  color: var(--on-titlebar);' + LineEnding +
    '}' + LineEnding;
end;

end.
