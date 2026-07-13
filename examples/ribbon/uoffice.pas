unit uoffice;
{ Office skin compiled INTO the ribbon example, so it can default to Office with no themes/
  folder present. GENERATED from themes/office.tycss by gen-uoffice.ps1 -- do not edit by hand. }
{$mode objfpc}{$H+}
interface
function OfficeThemeCss: string;
implementation
function OfficeThemeCss: string;
begin
  Result :=
    '/* office — Microsoft Office (Fluent). A neutral near-white workspace with a single' + LineEnding +
    '   signature move: an ACCENT-COLOURED caption band (Word/Excel/PowerPoint), kept in' + LineEnding +
    '   BOTH modes. Set --accent to rebrand the whole identity at runtime — Word-blue by' + LineEnding +
    '   default (#2B579A), Excel-green, PowerPoint-orange, etc.' + LineEnding +
    '' + LineEnding +
    '   Genuinely native, NOT zoomed: Fluent''s flat surfaces, small 2px radii, thin' + LineEnding +
    '   #C8C6C4→#8A8886 hairlines and tight command-bar padding. Nativeness comes from' + LineEnding +
    '   colour + border + radius, never from size — controls inherit the base 9px font.' + LineEnding +
    '' + LineEnding +
    '   DUAL-MODE. The palette (surfaces, fields, ink, borders, accent) lives in the' + LineEnding +
    '   @mode light / @mode dark blocks; control rules only reference var(--…), so' + LineEnding +
    '   switching Controller.Mode recolours everything. @mode light = the classic' + LineEnding +
    '   near-white Fluent look. @mode dark = Office dark: #252423 window / #1B1A19' + LineEnding +
    '   content / #292827 wells + light ink, with the accent caption band kept in BOTH' + LineEnding +
    '   modes. The runtime accent-picker recolours through var(--accent). */' + LineEnding +
    '' + LineEnding +
    '/* ── Palette: light = classic Fluent, dark = Office dark ─────────────────── */' + LineEnding +
    '@mode light {' + LineEnding +
    '  :root {' + LineEnding +
    '    --accent:        #2B579A;   /* Office blue — the runtime accent-picker recolours everything */' + LineEnding +
    '    --surface:       #F3F2F1;   /* Fluent neutral window; also default-button hover face */' + LineEnding +
    '    --field:         #FFFFFF;   /* white content + input wells + default button face */' + LineEnding +
    '    --pressed:       #EDEBE9;   /* pressed neutral: button :active + progress track */' + LineEnding +
    '    --ink:           #201F1E;   /* near-black text */' + LineEnding +
    '    --muted:         #A19F9D;   /* disabled / secondary ink */' + LineEnding +
    '    --line:          #C8C6C4;   /* thin neutral hairline */' + LineEnding +
    '    --line-field:    #8A8886;   /* stronger field / default-button border */' + LineEnding +
    '    --hover-overlay: #0000000A; /* faint neutral wash for ghost hover */' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '@mode dark {' + LineEnding +
    '  :root {' + LineEnding +
    '    --accent:        #2B579A;   /* same brand seed — the picker recolours through it */' + LineEnding +
    '    --surface:       #252423;   /* Office-dark window; also default-button hover face */' + LineEnding +
    '    --field:         #292827;   /* raised dark input wells + default button face */' + LineEnding +
    '    --pressed:       #1B1A19;   /* deep content tone: button :active + progress track */' + LineEnding +
    '    --ink:           #FFFFFF;   /* light text on the dark canvas */' + LineEnding +
    '    --muted:         #797775;   /* disabled / secondary ink */' + LineEnding +
    '    --line:          #3B3A39;   /* subtle hairline on dark */' + LineEnding +
    '    --line-field:    #484644;   /* stronger field / default-button border on dark */' + LineEnding +
    '    --hover-overlay: #FFFFFF14; /* faint light wash for ghost hover on dark */' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Window: flat neutral canvas. */' + LineEnding +
    'TyForm { background: var(--surface); }' + LineEnding +
    '' + LineEnding +
    '/* Title bar: the accent caption band — the whole identity, white text in BOTH modes. */' + LineEnding +
    'TyTitleBar {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  color: on(var(--accent));' + LineEnding +
    '  border-radius: 0;' + LineEnding +
    '}' + LineEnding +
    'TyCaptionButton {' + LineEnding +
    '  background: transparent;' + LineEnding +
    '  color: on(var(--accent));' + LineEnding +
    '  border-radius: 0;' + LineEnding +
    '}' + LineEnding +
    'TyCaptionButton:hover  { background: alpha(on(var(--accent)), 0.18); color: on(var(--accent)); }' + LineEnding +
    'TyCaptionButton:active { background: alpha(on(var(--accent)), 0.30); color: on(var(--accent)); }' + LineEnding +
    '' + LineEnding +
    '/* Labels: theme ink on the canvas. */' + LineEnding +
    'TyLabel { color: var(--ink); }' + LineEnding +
    '' + LineEnding +
    '/* Default button: white face, thin field-strength border, tight command-bar padding.' + LineEnding +
    '   Hover recedes to the neutral window tone; pressed reads a touch deeper. Flat, quiet. */' + LineEnding +
    'TyButton {' + LineEnding +
    '  background: var(--field);' + LineEnding +
    '  color: var(--ink);' + LineEnding +
    '  border: 1px solid var(--line-field);' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '  font-weight: normal;' + LineEnding +
    '  padding: 5px 10px;' + LineEnding +
    '}' + LineEnding +
    'TyButton:hover {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--ink);' + LineEnding +
    '  border: 1px solid var(--line);' + LineEnding +
    '}' + LineEnding +
    'TyButton:active {' + LineEnding +
    '  background: var(--pressed);' + LineEnding +
    '  color: var(--ink);' + LineEnding +
    '  border: 1px solid var(--line-field);' + LineEnding +
    '}' + LineEnding +
    'TyButton:focus  { outline: 2px var(--accent); outline-offset: 1px; }' + LineEnding +
    'TyButton:disabled {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: var(--muted);' + LineEnding +
    '  border: 1px solid var(--line);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Primary: solid accent, white ink, Fluent''s semibold weight + a hairline shadow. */' + LineEnding +
    'TyButton.primary {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  color: on(var(--accent));' + LineEnding +
    '  border: 1px solid var(--accent);' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '  font-weight: 600;' + LineEnding +
    '  padding: 5px 10px;' + LineEnding +
    '  shadow: 0 1 2 #00000024;' + LineEnding +
    '}' + LineEnding +
    'TyButton.primary:hover  { background: darken(var(--accent), 8);  border: 1px solid darken(var(--accent), 8); }' + LineEnding +
    'TyButton.primary:active { background: darken(var(--accent), 16); border: 1px solid darken(var(--accent), 16); shadow: 0 0 0 #00000000; }' + LineEnding +
    'TyButton.primary:disabled {' + LineEnding +
    '  background: alpha(var(--accent), 0.40);' + LineEnding +
    '  color: alpha(on(var(--accent)), 0.75);' + LineEnding +
    '  border: 1px solid alpha(var(--accent), 0.40);' + LineEnding +
    '  shadow: 0 0 0 #00000000;' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '/* Ghost: chrome-less until touched — a command-bar affordance, faint neutral wash. */' + LineEnding +
    'TyButton.ghost {' + LineEnding +
    '  background: transparent;' + LineEnding +
    '  color: var(--accent);' + LineEnding +
    '  border: 1px solid transparent;' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '  font-weight: normal;' + LineEnding +
    '  padding: 5px 10px;' + LineEnding +
    '}' + LineEnding +
    'TyButton.ghost:hover  { background: var(--hover-overlay); color: var(--accent); border: 1px solid transparent; }' + LineEnding +
    'TyButton.ghost:active { background: var(--pressed);       color: var(--accent); border: 1px solid transparent; }' + LineEnding +
    'TyButton.ghost:disabled { background: transparent; color: var(--muted); border: 1px solid transparent; }' + LineEnding +
    '' + LineEnding +
    '/* Fields: bright wells, stronger hairline, accent focus. */' + LineEnding +
    'TyEdit {' + LineEnding +
    '  background: var(--field);' + LineEnding +
    '  color: var(--ink);' + LineEnding +
    '  border: 1px solid var(--line-field);' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '  padding: 5px 8px;' + LineEnding +
    '}' + LineEnding +
    'TyEdit:hover    { border: 1px solid var(--ink); }' + LineEnding +
    'TyEdit:focus    { border: 1px solid var(--accent); outline: 2px alpha(var(--accent), 0.35); outline-offset: 0px; }' + LineEnding +
    'TyEdit:disabled { background: var(--surface); color: var(--muted); border: 1px solid var(--line); }' + LineEnding +
    '' + LineEnding +
    'TyComboBox {' + LineEnding +
    '  background: var(--field);' + LineEnding +
    '  color: var(--ink);' + LineEnding +
    '  border: 1px solid var(--line-field);' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '  padding: 5px 8px;' + LineEnding +
    '}' + LineEnding +
    'TyComboBox:hover    { border: 1px solid var(--ink); }' + LineEnding +
    'TyComboBox:focus    { border: 1px solid var(--accent); outline: 2px alpha(var(--accent), 0.35); outline-offset: 0px; }' + LineEnding +
    'TyComboBox:disabled { background: var(--surface); color: var(--muted); border: 1px solid var(--line); }' + LineEnding +
    '' + LineEnding +
    '/* Check box: white indicator, thin field border, accent tick (color inks the check). */' + LineEnding +
    'TyCheckBox {' + LineEnding +
    '  background: var(--field);' + LineEnding +
    '  color: var(--accent);' + LineEnding +
    '  border: 1px solid var(--line-field);' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '}' + LineEnding +
    'TyCheckBox:hover    { background: var(--field); color: var(--accent); border: 1px solid var(--accent); border-radius: 2px; }' + LineEnding +
    'TyCheckBox:active   { background: alpha(var(--accent), 0.12); color: var(--accent); border: 1px solid var(--accent); border-radius: 2px; }' + LineEnding +
    'TyCheckBox:disabled { background: var(--surface); color: var(--muted); border: 1px solid var(--line); border-radius: 2px; }' + LineEnding +
    '' + LineEnding +
    '/* Radio: mirror the check box — white well, accent dot, thin field border, circular. */' + LineEnding +
    'TyRadioButton {' + LineEnding +
    '  background: var(--field);' + LineEnding +
    '  color: var(--accent);' + LineEnding +
    '  border: 1px solid var(--line-field);' + LineEnding +
    '  border-radius: 8px;' + LineEnding +
    '}' + LineEnding +
    'TyRadioButton:hover    { background: var(--field); color: var(--accent); border: 1px solid var(--accent); border-radius: 8px; }' + LineEnding +
    'TyRadioButton:active   { background: alpha(var(--accent), 0.12); color: var(--accent); border: 1px solid var(--accent); border-radius: 8px; }' + LineEnding +
    'TyRadioButton:disabled { background: var(--surface); color: var(--muted); border: 1px solid var(--line); border-radius: 8px; }' + LineEnding +
    '' + LineEnding +
    '/* Progress: flat neutral groove, solid accent fill. */' + LineEnding +
    'TyProgressBar {' + LineEnding +
    '  background: var(--pressed);' + LineEnding +
    '  border: 1px solid var(--line);' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '}' + LineEnding +
    'TyProgressFill {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '  border-radius: 2px;' + LineEnding +
    '}';
end;
end.
