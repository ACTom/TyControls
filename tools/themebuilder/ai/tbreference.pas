unit tbreference;
{ The short tycss reference the model gets with every request (spec §7.2): what a file looks
  like, what it may not do, the seeds and the variables that derive from them, every
  property and colour function, every TypeKey with the variants the base theme gives it,
  and one complete small theme. English (models follow English rules best; the parts read
  from the engine are English anyway) and ASCII only.

  Put together at run time, once, rather than generated into a file at build time (as the
  spec first had it): half of it is lists the library already holds -- TyCatalogTypeKeys,
  TyCatalogTokens, TyKnownStyleProps, TyStyleValueHints, TyKnownColorFns,
  TyKnownPseudoStates, and the base theme itself (TyBuiltinThemeCss('default'), parsed:
  the seeds and derived variables of its light and dark @mode blocks, the variants of its
  rules) -- so that half cannot drift from the engine. A generator would have had to read
  Pascal source to get at TyStyleValueHints, which is code, not data.

  The other half is written here: the syntax and its limits, a sentence per property, a
  signature per colour function, the example. The tests hold it to the engine
  (test.themebuilder.reference): every property and function has its note and no other;
  every claim about what parses comes with a snippet that must parse (or must fail); the
  example parses, lints clean and resolves in both modes. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, StrUtils;

type
  TTbRefClaim = record
    Claim: string;                { the sentence in the reference }
    Snippet: string;              { tycss that shows it }
    MustParse: Boolean;           { True: parses and lints without errors; False: fails }
  end;
  TTbRefClaims = array of TTbRefClaim;

function TbReferenceText: string;               { built once, then cached }
function TbReferenceApproxTokens: Integer;      { Length(TbReferenceText) div 4 }
function TbReferenceExample: string;            { the complete small theme in it }
function TbPropertyNote(const AProp: string): string;    { '' when none }
function TbColorFnSignature(const AFn: string): string;  { '' when none }
function TbReferenceClaims: TTbRefClaims;       { FOR THE TESTS }
function TbNotedProperties: TStringArray;       { FOR THE TESTS }
function TbSignedColorFns: TStringArray;        { FOR THE TESTS }

implementation

uses
  tyControls.Css.Catalog, tyControls.Css.Parser, tyControls.Css.Values, tyControls.StyleModel,
  tyControls.BuiltinThemes, tbseeds;

type
  TNote = record
    Name, Text: string;
  end;
  TFnNote = record
    Name, Signature, Text: string;
  end;

const
  { one sentence per TyKnownStyleProps entry (docs/tycss-reference.md §5, and the engine's
    TyApplyDeclaration where the manual is silent) }
  cPropNotes: array[0..22] of TNote = (
    (Name: 'background'; Text: 'a colour, transparent, none, or linear-gradient(angle, colour, colour[, more stops]). background-color is the same for a plain colour.'),
    (Name: 'background-image'; Text: 'url(file) slice(top right bottom left) [repeat] is a nine-patch image; url(file) alone covers the control. The path is relative to the theme file and must not contain spaces.'),
    (Name: 'background-size'; Text: 'how a background image fits the control.'),
    (Name: 'background-blur'; Text: 'a whole number of pixels to blur the background image by.'),
    (Name: 'glass-blur'; Text: 'a length: the blur of a translucent (glass) window background.'),
    (Name: 'glass-tint'; Text: 'a colour laid over the glass blur.'),
    (Name: 'background-under-titlebar'; Text: 'TyForm only: whether the form background also fills the area behind the title bar.'),
    (Name: 'window-shadow'; Text: 'TyForm only: whether the system draws its drop shadow around the window.'),
    (Name: 'shadow'; Text: 'x y blur colour, in pixels (x and y may be negative). The colour must be ONE token: #rrggbbaa, var(--name) or --name; a function with commas does not work here.'),
    (Name: 'color'; Text: 'the text colour, also used for single-colour glyphs (check marks, arrows, close crosses).'),
    (Name: 'border'; Text: 'width [style] colour, for example 1px solid var(--border).'),
    (Name: 'border-color'; Text: 'a colour; without one no border is drawn.'),
    (Name: 'border-width'; Text: 'a length; 0 draws no border.'),
    (Name: 'border-radius'; Text: 'one length, or four (top-left top-right bottom-right bottom-left). Two or three values are an error.'),
    (Name: 'border-style'; Text: 'solid is the default; outset and inset are square two-colour 3D bevels derived from border-color.'),
    (Name: 'render-style'; Text: 'a classic 3D frame preset for the whole control; flat is the default.'),
    (Name: 'padding'; Text: 'one to four lengths, as in CSS (all; top-bottom left-right; top left-right bottom; top right bottom left).'),
    (Name: 'font-family'; Text: 'a font name WITHOUT quotes, for example Segoe UI.'),
    (Name: 'font-size'; Text: 'a number in POINTS; a px suffix is ignored (10px means 10pt).'),
    (Name: 'font-weight'; Text: 'normal, bold or a number; 600 and above draws bold, anything else normal.'),
    (Name: 'outline'; Text: 'width colour: the focus ring, drawn inside the control; usually in :focus rules; outline: 0 turns it off.'),
    (Name: 'outline-offset'; Text: 'a length: how far inside the edge the outline sits; only works together with outline.'),
    (Name: 'opacity'; Text: 'a number from 0 to 1 for the whole control, typically in :disabled rules.'));

  { one signature per TyKnownColorFns entry (docs/tycss-reference.md §6, Css.Values) }
  cFnNotes: array[0..8] of TFnNote = (
    (Name: 'var'; Signature: 'var(--name)'; Text: 'the value of a variable; a bare --name means the same.'),
    (Name: 'lighten'; Signature: 'lighten(colour, 0..100)'; Text: 'towards white by that percentage; alpha stays.'),
    (Name: 'darken'; Signature: 'darken(colour, 0..100)'; Text: 'towards black by that percentage; alpha stays.'),
    (Name: 'alpha'; Signature: 'alpha(colour, 0..1)'; Text: 'the same colour with that opacity (write a decimal like 0.3).'),
    (Name: 'mix'; Signature: 'mix(colour1, colour2, 0..100)'; Text: 'that percentage of colour2 mixed into colour1.'),
    (Name: 'rgb'; Signature: 'rgb(0..255, 0..255, 0..255)'; Text: 'a colour from red, green and blue.'),
    (Name: 'rgba'; Signature: 'rgba(0..255, 0..255, 0..255, 0..1)'; Text: 'the same with an opacity.'),
    (Name: 'elevate'; Signature: 'elevate(colour, 0..100)'; Text: 'a raised surface: darker in light mode, lighter in dark mode.'),
    (Name: 'on'; Signature: 'on(colour)'; Text: 'black or white, whichever reads better on that colour; on(colour, inkOnLight, inkOnDark) picks one of the two you give.'));

  cSyntax =
    '## How a .tycss file is built'#10 +
    '- A file is a sequence of :root blocks, rules and @mode blocks, in any order. @import lines must come first.'#10 +
    '- :root { --name: value; } defines variables. Use them as var(--name) or as a bare --name.'#10 +
    '- @mode light { :root { ... } } and @mode dark { :root { ... } } hold the variables of each mode. Only :root may appear inside @mode.'#10 +
    '- A rule is: selector-list { property: value; ... }.'#10 +
    '- Selector: TypeKey, optionally .variant, optionally :state. Examples: TyButton, TyButton.primary, TyButton:hover, TyButton.primary:hover. A comma list applies the same declarations to each selector.'#10 +
    '- States: %s. One state per selector; :checked means :selected. A state rule is applied after the plain and variant rules, so a variant needs its own state rules (TyButton.primary:hover), or the plain :hover rule wins over it.'#10 +
    '- Every declaration ends with a semicolon, the last one in a block too.'#10 +
    '- Comments are /* ... */ only.'#10 +
    '- Names (types, variants, states, properties, functions) are not case-sensitive.'#10 +
    '- Colours: #rgb, #rrggbb, #rrggbbaa, transparent, or a colour function.'#10 +
    '- Lengths are plain numbers or numbers with px. font-size is in points.'#10 +
    '- The file sits on top of the built-in base theme: anything the file does not define comes from the base.'#10 +
    '- A rule for a TypeKey replaces ALL of the base theme''s rules for that TypeKey (every state and variant), not just the properties you write. Restate everything the control needs, or leave the TypeKey alone and change variables instead.'#10 +
    'Not supported (the parser rejects them, or the engine reports them as errors):'#10 +
    '- descendant or child selectors (TyPanel TyButton, TyPanel > TyButton), *, .variant without a type, :state without a type, two variants (TyButton.a.b), chained states (:hover:focus)'#10 +
    '- @media, !important, // comments, escapes in strings'#10 +
    '- margin, width, height, gap, per-corner radius properties (border-top-left-radius), percentage radius'#10 +
    '- border-style dashed / dotted / groove / ridge (ignored: drawn solid)'#10 +
    '- quotes around font-family names (the quotes become part of the name)'#10 +
    '- linear-gradient angles: 0deg = left to right, 90deg = top to bottom, 180deg = right to left (not the CSS convention); the angle comes first; no "to right" keywords'#10;

  cExample =
    '/* A complete small theme. The two @mode blocks set the six seeds and a few derived'#10 +
    '   variables; everything else derives from them or comes from the base theme.'#10 +
    '   The button rules restyle buttons completely: a rule for a TypeKey replaces all of'#10 +
    '   the base theme''s rules for it, so every state and variant is written out. */'#10 +
    '@mode light {'#10 +
    '  :root {'#10 +
    '    --accent: #0F766E; --surface: #FFFFFF; --on-surface: #1F2937;'#10 +
    '    --border: #CBD5E1; --danger: #DC2626; --radius: 8px;'#10 +
    '    --form-bg: #F1F5F9;'#10 +
    '    --focus-ring: alpha(var(--accent), 0.6);'#10 +
    '  }'#10 +
    '}'#10 +
    '@mode dark {'#10 +
    '  :root {'#10 +
    '    --accent: #2DD4BF; --surface: #1E293B; --on-surface: #E2E8F0;'#10 +
    '    --border: #475569; --danger: #F87171; --radius: 8px;'#10 +
    '    --form-bg: #0F172A;'#10 +
    '    --focus-ring: alpha(var(--accent), 0.6);'#10 +
    '  }'#10 +
    '}'#10 +
    #10 +
    'TyButton, TySpeedButton {'#10 +
    '  background: var(--surface);'#10 +
    '  color: var(--on-surface);'#10 +
    '  border-color: var(--border);'#10 +
    '  border-width: 1px;'#10 +
    '  border-radius: var(--radius);'#10 +
    '  padding: 6px 12px;'#10 +
    '  font-size: var(--font-size-base);'#10 +
    '}'#10 +
    'TyButton:hover, TySpeedButton:hover { background: var(--surface-hover); border-color: var(--border-hover); }'#10 +
    'TyButton:active, TySpeedButton:active { background: var(--surface-active); }'#10 +
    'TyButton:focus, TySpeedButton:focus { border-color: var(--accent); outline: 2px var(--focus-ring); }'#10 +
    'TyButton:disabled, TySpeedButton:disabled { opacity: 0.5; }'#10 +
    'TyButton.primary, TySpeedButton.primary { background: var(--accent); color: on(var(--accent)); border-color: var(--accent); }'#10 +
    'TyButton.primary:hover, TySpeedButton.primary:hover { background: lighten(--accent, 8%); }'#10 +
    'TyButton.primary:active, TySpeedButton.primary:active { background: darken(--accent, 8%); }'#10 +
    'TyButton.danger, TySpeedButton.danger { background: var(--danger); color: on(var(--danger)); border-color: var(--danger); }'#10 +
    'TyButton.danger:hover, TySpeedButton.danger:hover { background: lighten(--danger, 8%); }'#10 +
    'TyButton.ghost, TySpeedButton.ghost { background: transparent; border-color: transparent; }'#10 +
    'TyButton.ghost:hover, TySpeedButton.ghost:hover { background: var(--surface-hover); }'#10;

var
  GText: string = '';
  GBuilt: Boolean = False;

function TbReferenceExample: string;
begin
  Result := cExample;
end;

function TbPropertyNote(const AProp: string): string;
var
  i: Integer;
begin
  for i := 0 to High(cPropNotes) do
    if SameText(cPropNotes[i].Name, AProp) then
      Exit(cPropNotes[i].Text);
  Result := '';
end;

function TbColorFnSignature(const AFn: string): string;
var
  i: Integer;
begin
  for i := 0 to High(cFnNotes) do
    if SameText(cFnNotes[i].Name, AFn) then
      Exit(cFnNotes[i].Signature);
  Result := '';
end;

function TbNotedProperties: TStringArray;
var
  i: Integer;
begin
  SetLength(Result, Length(cPropNotes));
  for i := 0 to High(cPropNotes) do
    Result[i] := cPropNotes[i].Name;
end;

function TbSignedColorFns: TStringArray;
var
  i: Integer;
begin
  SetLength(Result, Length(cFnNotes));
  for i := 0 to High(cFnNotes) do
    Result[i] := cFnNotes[i].Name;
end;

function Claim(const AClaim, ASnippet: string; AMustParse: Boolean): TTbRefClaim;
begin
  Result.Claim := AClaim;
  Result.Snippet := ASnippet;
  Result.MustParse := AMustParse;
end;

function TbReferenceClaims: TTbRefClaims;
var
  n: Integer;

  procedure Add(const AClaim, ASnippet: string; AMustParse: Boolean);
  begin
    SetLength(Result, n + 1);
    Result[n] := Claim(AClaim, ASnippet, AMustParse);
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  { what the reference says works }
  Add(':root defines variables, var(--name) uses them', ':root { --a: #fff; } TyButton { background: var(--a); }', True);
  Add('a bare --name uses a variable', 'TyButton { background: --accent; }', True);
  Add('a comma list of selectors', 'TyEdit:focus, TyComboBox:focus { border-color: #123456; }', True);
  Add(':checked means :selected', 'TyButton:checked { color: #000; }', True);
  Add('@mode blocks hold :root', '@mode dark { :root { --a: #000; } }', True);
  Add('padding: four lengths', 'TyButton { padding: 2px 4px 6px 8px; }', True);
  Add('padding: two lengths', 'TyButton { padding: 2px 4px; }', True);
  Add('border-radius: four lengths', 'TyButton { border-radius: 2px 4px 6px 8px; }', True);
  Add('a variant with a state', 'TyButton.primary:hover { background: lighten(--accent, 8%); }', True);
  Add('a linear gradient, angle first', 'TyButton { background: linear-gradient(90deg, #FFFFFF, #000000); }', True);
  Add('colour functions nest', 'TyButton { color: on(mix(--surface, var(--accent), 20)); }', True);
  { what it says does not }
  Add('no descendant selectors', 'TyPanel TyButton { color: #000; }', False);
  Add('no child selectors', 'TyPanel > TyButton { }', False);
  Add('no *', '* { }', False);
  Add('no .variant without a type', '.primary { }', False);
  Add('no :state without a type', ':hover { }', False);
  Add('one variant per selector', 'TyButton.a.b { }', False);
  Add('one state per selector', 'TyButton:hover:focus { }', False);
  Add('no @media', '@media x { }', False);
  Add('no !important', 'TyButton { color: #000 !important; }', False);
  Add('no // comments', '// c'#10'TyButton { }', False);
  Add('no margin', 'TyButton { margin: 1px; }', False);
  Add('no width', 'TyButton { width: 10px; }', False);
  Add('no per-corner radius', 'TyButton { border-top-left-radius: 2px; }', False);
  Add('border-radius: not two values', 'TyButton { border-radius: 2px 4px; }', False);
  Add('padding: three values, as in CSS', 'TyButton { padding: 1px 2px 3px; }', True);
  Add('every declaration ends with a semicolon', 'TyButton { color: #000 }', False);
  Add('@import comes first', ':root { --a: #fff; }'#10'@import "x.tycss";', False);
  Add('only :root inside @mode', '@mode dark { TyButton { color: #000; } }', False);
end;

{ ---- putting it together ---- }

function JoinNames(const ANames: array of string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ANames) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + ANames[i];
  end;
end;

function FindMode(ASheet: TTyCssStylesheet; const AMode: string): TTyCssModeBlock;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to ASheet.ModeBlocks.Count - 1 do
    if SameText(TTyCssModeBlock(ASheet.ModeBlocks[i]).Mode, AMode) then
      Exit(TTyCssModeBlock(ASheet.ModeBlocks[i]));
end;

function IsSeed(const AName: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(TbSeedNames) do
    if SameText(TbSeedNames[i], AName) then
      Exit(True);
  Result := False;
end;

function OneLine(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] < ' ' then
      Result[i] := ' ';
  Result := Trim(Result);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
end;

function BuildText: string;
var
  sheet: TTyCssStylesheet;
  parser: TTyCssParser;
  light, dark: TTyCssModeBlock;
  sb: TStringList;
  listed, variants, hints: TStringList;
  i, j, k: Integer;
  name, line, hint, others: string;
  rule: TTyCssRule;
  sel: TTyCssSelector;
begin
  sb := TStringList.Create;
  listed := TStringList.Create;
  variants := TStringList.Create;
  hints := TStringList.Create;
  parser := TTyCssParser.Create(TyBuiltinThemeCss('default'));
  sheet := nil;
  try
    listed.CaseSensitive := False;
    listed.Sorted := True;
    listed.Duplicates := dupIgnore;
    sheet := parser.Parse;
    light := FindMode(sheet, 'light');
    dark := FindMode(sheet, 'dark');

    sb.Add('# tycss reference (TyControls themes)');
    sb.Add('');
    sb.Add('## Answer format');
    sb.Add('The rules for answering are in the system prompt above this reference.');
    sb.Add('');
    sb.Add(Format(cSyntax, [JoinNames(TyKnownPseudoStates)]));

    { the seeds, with both modes' values }
    sb.Add('## Seeds');
    sb.Add('Change these first: most colours derive from them.');
    for i := 0 to High(TbSeedNames) do
    begin
      name := TbSeedNames[i];
      line := '--' + name + ': light ';
      if light <> nil then line := line + OneLine(light.Vars.Values[name]);
      line := line + ', dark ';
      if dark <> nil then line := line + OneLine(dark.Vars.Values[name]);
      sb.Add(line);
      listed.Add(name);
    end;
    sb.Add('');

    { what the light block derives from them }
    sb.Add('## Derived variables (light mode of the base theme)');
    sb.Add('Defined in both modes the same way; dark mode uses its own seeds. Override any of them in your file to change what derives from it.');
    if light <> nil then
      for i := 0 to light.Vars.Count - 1 do
      begin
        name := light.Vars.Names[i];
        if IsSeed(name) or (listed.IndexOf(name) >= 0) then Continue;
        sb.Add('--' + name + ': ' + OneLine(light.Vars.ValueFromIndex[i]));
        listed.Add(name);
      end;
    sb.Add('');

    { the rest of the catalogue: names only }
    sb.Add('## Other variables');
    sb.Add('Defined by the base theme; use them with var(), override them if needed.');
    others := '';
    for i := 0 to High(TyCatalogTokens) do
    begin
      name := Copy(TyCatalogTokens[i], 3, MaxInt);
      if listed.IndexOf(name) >= 0 then Continue;
      listed.Add(name);
      if others <> '' then others := others + ', ';
      others := others + TyCatalogTokens[i];
    end;
    sb.Add(others);
    sb.Add('');

    { properties }
    sb.Add('## Properties');
    sb.Add('Any other property name is ignored.');
    for i := 0 to High(TyKnownStyleProps) do
    begin
      line := '- ' + TyKnownStyleProps[i] + ': ' + TbPropertyNote(TyKnownStyleProps[i]);
      hints.Clear;
      TyStyleValueHints(TyKnownStyleProps[i], hints);
      hint := '';
      for j := 0 to hints.Count - 1 do
      begin
        if hint <> '' then hint := hint + ', ';
        if (hints[j] <> '') and (hints[j][Length(hints[j])] = '(') then
          hint := hint + hints[j] + '...)'
        else
          hint := hint + hints[j];
      end;
      if hint <> '' then
        line := line + ' Values: ' + hint + '.';
      sb.Add(line);
    end;
    sb.Add('');

    { colour functions }
    sb.Add('## Colour functions');
    sb.Add('Arguments are colour expressions themselves, so functions nest. A percentage may be written with or without %.');
    for i := 0 to High(TyKnownColorFns) do
      for j := 0 to High(cFnNotes) do
        if SameText(cFnNotes[j].Name, TyKnownColorFns[i]) then
          sb.Add('- ' + cFnNotes[j].Signature + ': ' + cFnNotes[j].Text);
    sb.Add('');

    { the TypeKeys, with the variants the base theme styles }
    for i := 0 to sheet.Rules.Count - 1 do
    begin
      rule := TTyCssRule(sheet.Rules[i]);
      for j := 0 to High(rule.Selectors) do
      begin
        sel := rule.Selectors[j];
        if sel.Variant = '' then Continue;
        name := LowerCase(sel.TypeName);
        k := variants.IndexOfName(name);
        if k < 0 then
          variants.Add(name + '=.' + sel.Variant)
        else if Pos(' .' + sel.Variant + ' ', ' ' + variants.ValueFromIndex[k] + ' ') = 0 then
          variants[k] := name + '=' + variants.ValueFromIndex[k] + ' .' + sel.Variant;
      end;
    end;
    sb.Add('## TypeKeys');
    sb.Add('The controls and their parts; in brackets the variants the base theme styles (a variant is any StyleClass word, these are the usual ones).');
    line := '';
    for i := 0 to High(TyCatalogTypeKeys) do
    begin
      name := TyCatalogTypeKeys[i];
      k := variants.IndexOfName(LowerCase(name));
      if k >= 0 then
        name := name + '(' + variants.ValueFromIndex[k] + ')';
      if line <> '' then line := line + ', ';
      line := line + name;
    end;
    sb.Add(line);
    sb.Add('');

    sb.Add('## A complete small theme');
    sb.Add('```tycss');
    sb.Add(TrimRight(cExample));
    sb.Add('```');
    Result := StringReplace(sb.Text, LineEnding, #10, [rfReplaceAll]);
  finally
    sheet.Free;
    parser.Free;
    hints.Free;
    variants.Free;
    listed.Free;
    sb.Free;
  end;
end;

function TbReferenceText: string;
begin
  if not GBuilt then
  begin
    GText := BuildText;
    GBuilt := True;
  end;
  Result := GText;
end;

function TbReferenceApproxTokens: Integer;
begin
  Result := Length(TbReferenceText) div 4;
end;

end.
