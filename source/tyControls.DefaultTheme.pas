unit tyControls.DefaultTheme;

{ Built-in default skin. Compiled into the binary (no disk dependency) so that
  controls render with a sensible look even when no theme is loaded — e.g. a
  control with no Controller bound, or any control dropped onto a form in the
  Lazarus designer. This text MUST stay byte-identical to themes/light.tycss
  (enforced by test.defaulttheme's sync test). When light.tycss changes, update
  this string to match. }

{$mode objfpc}{$H+}

interface

function TyBuiltinThemeCss: string;

implementation

function TyBuiltinThemeCss: string;
begin
  Result :=
    '/* TyControls — Light theme */' + LineEnding +
    ':root {' + LineEnding +
    '  --accent:     #3B82F6;' + LineEnding +
    '  --surface:    #FFFFFF;' + LineEnding +
    '  --on-surface: #1F2937;' + LineEnding +
    '  --border:     #D1D5DB;' + LineEnding +
    '  --danger:     #EF4444;' + LineEnding +
    '  --radius:     6px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Window/form backdrop — a soft off-white behind the white controls. */' + LineEnding +
    'TyForm { background: darken(--surface, 4%); }' + LineEnding +
    '' + LineEnding +
    'TyButton {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 6px;' + LineEnding +
    '  font-size: 10px;' + LineEnding +
    '  font-weight: 400;' + LineEnding +
    '}' + LineEnding +
    'TyButton:hover    { background: darken(--surface, 4%); }' + LineEnding +
    'TyButton:focus    { border-color: var(--accent); }' + LineEnding +
    'TyButton:active   { background: darken(--surface, 10%); }' + LineEnding +
    'TyButton:disabled { opacity: 0.5; }' + LineEnding +
    'TyButton.primary  { background: var(--accent); color: #FFFFFF; border-color: var(--accent); }' + LineEnding +
    'TyButton.primary:hover    { background: lighten(--accent, 8%); }' + LineEnding +
    'TyButton.primary:active   { background: darken(--accent, 8%); }' + LineEnding +
    'TyButton.danger   { background: var(--danger); color: #FFFFFF; border-color: var(--danger); }' + LineEnding +
    'TyButton.danger:hover     { background: lighten(--danger, 8%); }' + LineEnding +
    'TyButton.danger:active    { background: darken(--danger, 8%); }' + LineEnding +
    '' + LineEnding +
    'TyLabel {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  font-size: 10px;' + LineEnding +
    '  font-weight: 400;' + LineEnding +
    '}' + LineEnding +
    'TyLabel:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyEdit {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: 10px;' + LineEnding +
    '}' + LineEnding +
    'TyEdit:hover    { border-color: darken(--border, 10%); }' + LineEnding +
    'TyEdit:focus    { border-color: var(--accent); }' + LineEnding +
    'TyEdit:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyCheckBox {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: 3px;' + LineEnding +
    '}' + LineEnding +
    'TyCheckBox:hover    { border-color: var(--accent); }' + LineEnding +
    'TyCheckBox:active   { background: var(--accent); }' + LineEnding +
    'TyCheckBox:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyRadioButton {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: 8px;' + LineEnding +
    '}' + LineEnding +
    'TyRadioButton:hover    { border-color: var(--accent); }' + LineEnding +
    'TyRadioButton:active   { background: var(--accent); }' + LineEnding +
    'TyRadioButton:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyPanel {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 8px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyComboBox {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: 10px;' + LineEnding +
    '}' + LineEnding +
    'TyComboBox:hover    { border-color: darken(--border, 10%); }' + LineEnding +
    'TyComboBox:focus    { border-color: var(--accent); }' + LineEnding +
    'TyComboBox:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyScrollBar {' + LineEnding +
    '  background: darken(--surface, 6%);' + LineEnding +
    '  color: var(--border);' + LineEnding +
    '  border-radius: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyScrollBar:hover  { color: darken(--border, 15%); }' + LineEnding +
    'TyScrollBar:active { color: var(--accent); }' + LineEnding +
    '' + LineEnding +
    'TyTitleBar {' + LineEnding +
    '  background: darken(--surface, 6%);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  font-size: 10px;' + LineEnding +
    '  font-weight: 700;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyCaptionButton {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-radius: 0px;' + LineEnding +
    '}' + LineEnding +
    'TyCaptionButton:hover  { background: darken(--surface, 12%); }' + LineEnding +
    'TyCaptionButton:active { background: darken(--surface, 20%); }' + LineEnding +
    'TyCaptionButton.close:hover  { background: var(--danger); color: #FFFFFF; }' + LineEnding +
    'TyCaptionButton.close:active { background: darken(--danger, 10%); color: #FFFFFF; }' + LineEnding +
    'TyCaptionButton.min:hover    { background: darken(--surface, 12%); }' + LineEnding +
    'TyCaptionButton.max:hover    { background: darken(--surface, 12%); }' + LineEnding +
    '' + LineEnding +
    '/* ── v1.1 controls ─────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyListBox {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 2px;' + LineEnding +
    '}' + LineEnding +
    'TyListBox:focus   { border-color: var(--accent); }' + LineEnding +
    'TyListBox:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyListItem {' + LineEnding +
    '  background: alpha(#000000, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyListItem:hover  { background: darken(--surface, 5%); }' + LineEnding +
    'TyListItem:active { background: var(--accent); color: #FFFFFF; }' + LineEnding +
    '' + LineEnding +
    'TyProgressBar {' + LineEnding +
    '  background: darken(--surface, 8%);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyProgressFill {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyToggleSwitch {' + LineEnding +
    '  background: darken(--surface, 18%);' + LineEnding +
    '  color: #FFFFFF;' + LineEnding +
    '  border-radius: 12px;' + LineEnding +
    '}' + LineEnding +
    'TyToggleSwitch:active   { background: var(--accent); }' + LineEnding +
    'TyToggleSwitch:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyTrackBar {' + LineEnding +
    '  background: darken(--surface, 10%);' + LineEnding +
    '  border-radius: 3px;' + LineEnding +
    '  padding: 0px;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyTrackThumb {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  border-radius: 8px;' + LineEnding +
    '}' + LineEnding +
    'TyTrackThumb:hover  { background: lighten(--accent, 8%); }' + LineEnding +
    'TyTrackThumb:active { background: darken(--accent, 8%); }' + LineEnding +
    '' + LineEnding +
    'TyGroupBox {' + LineEnding +
    '  background: alpha(#FFFFFF, 0);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* ── v1.2 controls ─────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TyTabControl {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    'TyTab {' + LineEnding +
    '  background: darken(--surface, 5%);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '}' + LineEnding +
    'TyTab:hover  { background: darken(--surface, 2%); }' + LineEnding +
    'TyTab:active { background: var(--surface); color: var(--accent); }' + LineEnding +
    '' + LineEnding +
    '/* ── v1.9 controls ─────────────────────────────────────────────────────── */' + LineEnding +
    '' + LineEnding +
    'TySpinEdit {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: 10px;' + LineEnding +
    '}' + LineEnding +
    'TySpinEdit:hover    { border-color: darken(--border, 10%); }' + LineEnding +
    'TySpinEdit:focus    { border-color: var(--accent); }' + LineEnding +
    'TySpinEdit:disabled { opacity: 0.5; }' + LineEnding +
    '' + LineEnding +
    'TyMemo {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--on-surface);' + LineEnding +
    '  border-color: var(--border);' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: var(--radius);' + LineEnding +
    '  padding: 4px;' + LineEnding +
    '  font-size: 10px;' + LineEnding +
    '}' + LineEnding +
    'TyMemo:hover    { border-color: darken(--border, 10%); }' + LineEnding +
    'TyMemo:focus    { border-color: var(--accent); }' + LineEnding +
    'TyMemo:disabled { opacity: 0.5; }' + LineEnding;
end;

end.
