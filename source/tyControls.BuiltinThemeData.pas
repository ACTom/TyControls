unit tyControls.BuiltinThemeData;

{ GENERATED from themes/auto.tycss + themes/system.tycss by gen-builtinthemes.ps1 - do NOT
  edit by hand; edit the .tycss files and re-run the generator. Sync-tested byte-identical
  to those files (test.builtinthemes). }

{$mode objfpc}{$H+}

interface

function TyBuiltinDualBaseCss: string;
function TyBuiltinSystemCss: string;

implementation

function TyBuiltinDualBaseCss: string;
begin
  Result :=
    '/* TyControls — auto.tycss: single-file dual-mode (P3 @mode, D7).' + LineEnding +
    '   ONE file carries both light and dark. The shared rule bodies below use' + LineEnding +
    '   var(--…) tokens; each @mode block at the bottom supplies that mode''s :root' + LineEnding +
    '   token values. Set the active mode via Controller.Mode / Model.SetMode' + LineEnding +
    '   (''light'' or ''dark''). auto.tycss in light mode is pixel-identical to' + LineEnding +
    '   light.tycss; in dark mode pixel-identical to dark.tycss. */' + LineEnding +
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
    '/* Ghost (VS Code 风格): 平时透明,仅 hover/active/选中显示。 */' + LineEnding +
    'TyButton.ghost {' + LineEnding +
    '  background: var(--transparent-fill);' + LineEnding +
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
    '  background: var(--transparent-fill);' + LineEnding +
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
    '  background: var(--transparent-fill);' + LineEnding +
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
    'TyToggleSwitch {' + LineEnding +
    '  background: var(--surface-toggle-off);' + LineEnding +
    '  color: #FFFFFF;' + LineEnding +
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
    '  background: var(--transparent-fill);' + LineEnding +
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
    '/* 数字角标 (TTyButton badge): accent 胶囊。 */' + LineEnding +
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
    '   TyMenuPopup mirrors it for the popup-host selector named in the spec.' + LineEnding +
    '   light mode = --surface (white); dark mode = --input-bg (raised surface). */' + LineEnding +
    'TyMenuView {' + LineEnding +
    '  background: var(--menu-popup-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyMenuPopup {' + LineEnding +
    '  background: var(--menu-popup-bg);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* A single menu row / bar cell. The base border-color is the separator-line ink. */' + LineEnding +
    'TyMenuItem {' + LineEnding +
    '  background: var(--transparent-fill);' + LineEnding +
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
    '/* ── @mode conditional token blocks (D7) ──────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    '@mode light {' + LineEnding +
    '  :root {' + LineEnding +
    '  /* ── SEED ── 5 colors + 1 metric */' + LineEnding +
    '  --accent: #3B82F6; --surface: #FFFFFF; --on-surface: #1F2937;' + LineEnding +
    '  --border: #D1D5DB; --danger: #EF4444; --radius: 6px;' + LineEnding +
    '' + LineEnding +
    '  /* ── MAP: directional darken/lighten the body inlines ── */' + LineEnding +
    '  --surface-hover:            darken(--surface, 4%);' + LineEnding +
    '  --surface-active:           darken(--surface, 10%);' + LineEnding +
    '  --surface-chrome:           darken(--surface, 6%);' + LineEnding +
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
    '' + LineEnding +
    '  /* ── COMPONENT: scalars ── */' + LineEnding +
    '  --input-border-width: 1px;' + LineEnding +
    '  --radius-sm: 3px; --radius-pill: 8px; --radius-round: 12px; --radius-scroll: 4px;' + LineEnding +
    '  --font-size-base: 9px; --font-size-title: 9px;' + LineEnding +
    '  --font-weight-normal: 400; --font-weight-bold: 700;' + LineEnding +
    '    /* P3 dual-mode: per-mode transparent fill (light=white/dark=black, alpha 0) */' + LineEnding +
    '    --transparent-fill: alpha(#FFFFFF, 0);' + LineEnding +
    '    /* Menu popup surface: light = the white surface (matches light.tycss). */' + LineEnding +
    '    --menu-popup-bg: var(--surface);' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '@mode dark {' + LineEnding +
    '  :root {' + LineEnding +
    '  /* ── SEED ── 5 colors + 1 metric */' + LineEnding +
    '  --accent:     #60A5FA;' + LineEnding +
    '  --surface:    #1E1E1E;' + LineEnding +
    '  --on-surface: #E5E7EB;' + LineEnding +
    '  --border:     #3F3F46;' + LineEnding +
    '  --danger:     #F87171;' + LineEnding +
    '  --radius:     6px;' + LineEnding +
    '' + LineEnding +
    '  /* ── MAP: directional darken/lighten the body inlines ── */' + LineEnding +
    '  --surface-hover:            lighten(--surface, 8%);' + LineEnding +
    '  --surface-active:           darken(--surface, 6%);' + LineEnding +
    '  --surface-chrome:           darken(--surface, 4%);' + LineEnding +
    '  --surface-sunk:             darken(--surface, 4%);' + LineEnding +
    '  --surface-track:            darken(--surface, 4%);' + LineEnding +
    '  --surface-listitem-hover:   lighten(--surface, 10%);' + LineEnding +
    '  --surface-tab-rest:         lighten(--surface, 12%);' + LineEnding +
    '  --surface-tab-hover:        lighten(--surface, 18%);' + LineEnding +
    '  --surface-toggle-off:       lighten(--surface, 20%);' + LineEnding +
    '  --surface-toggle-off-hover: lighten(--surface, 24%);' + LineEnding +
    '  --surface-caption-hover:    lighten(--surface, 16%);' + LineEnding +
    '  --surface-caption-active:   lighten(--surface, 24%);' + LineEnding +
    '  --border-hover:             lighten(--border, 12%);' + LineEnding +
    '  --scroll-handle-hover:      lighten(--border, 25%);' + LineEnding +
    '  --accent-hover:  lighten(--accent, 8%);   --accent-active: darken(--accent, 8%);' + LineEnding +
    '  --danger-hover:  lighten(--danger, 8%);   --danger-active: darken(--danger, 8%);' + LineEnding +
    '  --danger-press-close: darken(--danger, 10%);' + LineEnding +
    '' + LineEnding +
    '  /* ── ALIAS: semantic ── */' + LineEnding +
    '  --focus-ring: var(--accent);' + LineEnding +
    '  --selection:     alpha(var(--accent), 0.30);' + LineEnding +
    '  --muted:         alpha(var(--on-surface), 0.5);' + LineEnding +
    '  --overlay-hover: alpha(#FFFFFF, 0.14);' + LineEnding +
    '  --disabled-opacity: 0.5;' + LineEnding +
    '  --form-bg:          var(--surface);              /* dark Form = raw surface (no darken) */' + LineEnding +
    '  --titlebar-bg:      lighten(--surface, 4%);      /* dark TitleBar lifts */' + LineEnding +
    '  --input-bg:         lighten(--surface, 4%);      /* dark raised input bg */' + LineEnding +
    '  --scroll-handle:    lighten(--border, 10%);      /* resting scroll thumb/handle */' + LineEnding +
    '  --input-border-hover: var(--border-hover);       /* neutral inputs hover border */' + LineEnding +
    '  /* on-* declared here but WIRED only in the §3 bug-fix commit */' + LineEnding +
    '  /* dark accent/danger are LIGHT blues/reds (luma>0.5), so on() picks inkOnLight =' + LineEnding +
    '     the dark ink #0B1120 (matches the correct sites, and fixes the white-on-accent' + LineEnding +
    '     checkbox/radio bug); inkOnDark #FFFFFF is the fallback for a dark fill. */' + LineEnding +
    '  --on-accent: on(var(--accent), #0B1120, #FFFFFF);' + LineEnding +
    '  --on-danger: on(var(--danger), #0B1120, #FFFFFF);' + LineEnding +
    '' + LineEnding +
    '  /* ── COMPONENT: scalars ── */' + LineEnding +
    '  --input-border-width: 1px;' + LineEnding +
    '  --radius-sm: 3px; --radius-pill: 8px; --radius-round: 12px; --radius-scroll: 4px;' + LineEnding +
    '  --font-size-base: 9px; --font-size-title: 9px;' + LineEnding +
    '  --font-weight-normal: 400; --font-weight-bold: 700;' + LineEnding +
    '    /* P3 dual-mode: per-mode transparent fill (light=white/dark=black, alpha 0) */' + LineEnding +
    '    --transparent-fill: alpha(#000000, 0);' + LineEnding +
    '    /* Menu popup surface: dark = the raised input bg (matches dark.tycss). */' + LineEnding +
    '    --menu-popup-bg: var(--input-bg);' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding;
end;

function TyBuiltinSystemCss: string;
begin
  Result :=
    '/* TyControls — system.tycss: the built-in "follow the OS" theme (P4, D8, §3.7).' + LineEnding +
    '   Dual-mode (@mode light/dark) like auto.tycss, but the SEED accent is the dynamic' + LineEnding +
    '   token `system-accent`, which StyleModel resolves to the OS accent colour at merge' + LineEnding +
    '   time, and `--ty-mode` is wired to `system-mode` so elevate()/on() follow the OS' + LineEnding +
    '   light/dark scheme. on()/elevate() derive ink + steps from the (OS) accent + mode,' + LineEnding +
    '   so the whole skin tracks the system: change the Windows accent or flip light/dark' + LineEnding +
    '   and (with Controller.Follow = tfFollowSystem) the theme re-resolves and repaints.' + LineEnding +
    '' + LineEnding +
    '   Set the active mode via Controller.Mode / Controller.Follow := tfFollowSystem.' + LineEnding +
    '   Body rule bodies are identical in shape to auto.tycss (var(--…) only); the @mode' + LineEnding +
    '   :root blocks supply each mode''s palette, with the accent coming from the OS. */' + LineEnding +
    '' + LineEnding +
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
    'TyButton.primary  { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }' + LineEnding +
    'TyButton.primary:hover    { background: var(--accent-hover); }' + LineEnding +
    'TyButton.primary:active   { background: var(--accent-active); }' + LineEnding +
    'TyButton.danger   { background: var(--danger); color: var(--on-danger); border-color: var(--danger); }' + LineEnding +
    'TyButton.danger:hover     { background: var(--danger-hover); }' + LineEnding +
    'TyButton.danger:active    { background: var(--danger-active); }' + LineEnding +
    '/* Ghost (VS Code 风格): 平时透明,仅 hover/active/选中显示。 */' + LineEnding +
    'TyButton.ghost {' + LineEnding +
    '  background: var(--transparent-fill);' + LineEnding +
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
    '  background: var(--transparent-fill);' + LineEnding +
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
    '  background: var(--transparent-fill);' + LineEnding +
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
    '  background: var(--transparent-fill);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyListItem:hover  { background: var(--surface-listitem-hover); }' + LineEnding +
    'TyListItem:active { background: var(--accent); color: var(--on-accent); }' + LineEnding +
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
    'TyToggleSwitch {' + LineEnding +
    '  background: var(--surface-toggle-off);' + LineEnding +
    '  color: #FFFFFF;' + LineEnding +
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
    '  background: var(--transparent-fill);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: var(--input-border-width);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
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
    'TyTab {' + LineEnding +
    '  background: var(--surface-tab-rest);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  border-radius: var(--radius) var(--radius) 0 0;' + LineEnding +
    '}' + LineEnding +
    'TyTab:hover  { background: var(--surface-tab-hover); }' + LineEnding +
    'TyTab:active { background: var(--surface); color: var(--accent); }' + LineEnding +
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
    '/* 数字角标 (TTyButton badge): accent 胶囊(accent 跟随 OS)。 */' + LineEnding +
    'TyBadge {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  color: var(--on-accent);' + LineEnding +
    '  border-radius: var(--radius-round);' + LineEnding +
    '  font-size: var(--font-size-base);' + LineEnding +
    '  font-weight: var(--font-weight-bold);' + LineEnding +
    '  padding: 0px 4px;' + LineEnding +
    '}' + LineEnding +
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
    '/* ── @mode conditional token blocks (D7) ──────────────────────────────────────' + LineEnding +
    '   The accent SEED is `system-accent` (StyleModel swaps it for the OS accent at' + LineEnding +
    '   merge time). --ty-mode = `system-mode` so elevate()/on() pick the OS scheme.' + LineEnding +
    '   The surface / on-surface / border palettes differ per mode; ink colours are' + LineEnding +
    '   derived with on() off the (OS) accent so they stay readable for ANY accent. */' + LineEnding +
    '' + LineEnding +
    '@mode light {' + LineEnding +
    '  :root {' + LineEnding +
    '  /* ── SEED ── accent from the OS; the rest is the light neutral palette */' + LineEnding +
    '  --accent: system-accent; --surface: #FFFFFF; --on-surface: #1F2937;' + LineEnding +
    '  --border: #D1D5DB; --danger: #EF4444; --radius: 6px;' + LineEnding +
    '  --ty-mode: system-mode;   /* drives elevate()/on() direction = OS scheme */' + LineEnding +
    '' + LineEnding +
    '  /* ── MAP: directional elevate()/darken/lighten ── */' + LineEnding +
    '  --surface-hover:            elevate(--surface, 4%);' + LineEnding +
    '  --surface-active:           elevate(--surface, 10%);' + LineEnding +
    '  --surface-chrome:           elevate(--surface, 6%);' + LineEnding +
    '  --surface-sunk:             elevate(--surface, 8%);' + LineEnding +
    '  --surface-track:            elevate(--surface, 10%);' + LineEnding +
    '  --surface-listitem-hover:   elevate(--surface, 5%);' + LineEnding +
    '  --surface-tab-rest:         elevate(--surface, 5%);' + LineEnding +
    '  --surface-tab-hover:        elevate(--surface, 2%);' + LineEnding +
    '  --surface-toggle-off:       elevate(--surface, 18%);' + LineEnding +
    '  --surface-toggle-off-hover: elevate(--surface, 22%);' + LineEnding +
    '  --surface-caption-hover:    elevate(--surface, 12%);' + LineEnding +
    '  --surface-caption-active:   elevate(--surface, 20%);' + LineEnding +
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
    '  --form-bg:          var(--surface-hover);' + LineEnding +
    '  --titlebar-bg:      var(--surface-chrome);' + LineEnding +
    '  --input-bg:         var(--surface);' + LineEnding +
    '  --scroll-handle:    var(--border);' + LineEnding +
    '  --input-border-hover: var(--border-hover);' + LineEnding +
    '  /* on() picks readable ink for ANY OS accent -> never a contrast bug */' + LineEnding +
    '  --on-accent:        on(var(--accent));' + LineEnding +
    '  --on-danger:        on(var(--danger));' + LineEnding +
    '' + LineEnding +
    '  /* ── COMPONENT: scalars ── */' + LineEnding +
    '  --input-border-width: 1px;' + LineEnding +
    '  --radius-sm: 3px; --radius-pill: 8px; --radius-round: 12px; --radius-scroll: 4px;' + LineEnding +
    '  --font-size-base: 9px; --font-size-title: 9px;' + LineEnding +
    '  --font-weight-normal: 400; --font-weight-bold: 700;' + LineEnding +
    '  --transparent-fill: alpha(#FFFFFF, 0);' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '@mode dark {' + LineEnding +
    '  :root {' + LineEnding +
    '  /* ── SEED ── accent from the OS; the rest is the dark neutral palette */' + LineEnding +
    '  --accent: system-accent; --surface: #1E1E1E; --on-surface: #E5E7EB;' + LineEnding +
    '  --border: #3F3F46; --danger: #F87171; --radius: 6px;' + LineEnding +
    '  --ty-mode: system-mode;' + LineEnding +
    '' + LineEnding +
    '  /* ── MAP: directional elevate()/darken/lighten ── */' + LineEnding +
    '  --surface-hover:            elevate(--surface, 8%);' + LineEnding +
    '  --surface-active:           darken(--surface, 6%);' + LineEnding +
    '  --surface-chrome:           darken(--surface, 4%);' + LineEnding +
    '  --surface-sunk:             darken(--surface, 4%);' + LineEnding +
    '  --surface-track:            darken(--surface, 4%);' + LineEnding +
    '  --surface-listitem-hover:   elevate(--surface, 10%);' + LineEnding +
    '  --surface-tab-rest:         elevate(--surface, 12%);' + LineEnding +
    '  --surface-tab-hover:        elevate(--surface, 18%);' + LineEnding +
    '  --surface-toggle-off:       elevate(--surface, 20%);' + LineEnding +
    '  --surface-toggle-off-hover: elevate(--surface, 24%);' + LineEnding +
    '  --surface-caption-hover:    elevate(--surface, 16%);' + LineEnding +
    '  --surface-caption-active:   elevate(--surface, 24%);' + LineEnding +
    '  --border-hover:             lighten(--border, 12%);' + LineEnding +
    '  --scroll-handle-hover:      lighten(--border, 25%);' + LineEnding +
    '  --accent-hover:  lighten(--accent, 8%);   --accent-active: darken(--accent, 8%);' + LineEnding +
    '  --danger-hover:  lighten(--danger, 8%);   --danger-active: darken(--danger, 8%);' + LineEnding +
    '  --danger-press-close: darken(--danger, 10%);' + LineEnding +
    '' + LineEnding +
    '  /* ── ALIAS: semantic ── */' + LineEnding +
    '  --focus-ring: var(--accent);' + LineEnding +
    '  --selection:     alpha(var(--accent), 0.30);' + LineEnding +
    '  --muted:         alpha(var(--on-surface), 0.5);' + LineEnding +
    '  --overlay-hover: alpha(#FFFFFF, 0.14);' + LineEnding +
    '  --disabled-opacity: 0.5;' + LineEnding +
    '  --form-bg:          var(--surface);' + LineEnding +
    '  --titlebar-bg:      lighten(--surface, 4%);' + LineEnding +
    '  --input-bg:         lighten(--surface, 4%);' + LineEnding +
    '  --scroll-handle:    lighten(--border, 10%);' + LineEnding +
    '  --input-border-hover: var(--border-hover);' + LineEnding +
    '  --on-accent: on(var(--accent));' + LineEnding +
    '  --on-danger: on(var(--danger));' + LineEnding +
    '' + LineEnding +
    '  /* ── COMPONENT: scalars ── */' + LineEnding +
    '  --input-border-width: 1px;' + LineEnding +
    '  --radius-sm: 3px; --radius-pill: 8px; --radius-round: 12px; --radius-scroll: 4px;' + LineEnding +
    '  --font-size-base: 9px; --font-size-title: 9px;' + LineEnding +
    '  --font-weight-normal: 400; --font-weight-bold: 700;' + LineEnding +
    '  --transparent-fill: alpha(#000000, 0);' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding;
end;

end.
