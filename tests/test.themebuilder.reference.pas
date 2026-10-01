unit test.themebuilder.reference;
{ The short tycss reference the AI gets (phase 3): put together from the engine's own lists,
  and the hand-written half held to the engine -- every property and colour function noted,
  every claim about what parses shown by a snippet that must parse or must fail, the
  example usable in both modes; plus the guard that the units the WSL program compiles
  use no LCL. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTbReferenceTests = class(TTestCase)
  published
    procedure TestEveryPropertyHasItsNote;       { R1 }
    procedure TestEveryColourFunctionIsSigned;   { R2 }
    procedure TestEveryTypeKeyIsListed;          { R3 }
    procedure TestTheSeedsAreTheBaseThemes;      { R4 }
    procedure TestTheClaimsHold;                 { R5 }
    procedure TestTheLength;                     { R6 }
    procedure TestTheExampleWorks;               { R7 }
    procedure TestAsciiOnly;                     { R8 }
    procedure TestTheWslUnitsUseNoLcl;           { R9 }
    procedure TestItIsBuiltOnce;                 { R10 }
    { after the phase 3 reviews }
    procedure TestWhatReplacesTheBase;           { R11 }
  end;

implementation

uses
  StrUtils, tyControls.Css.Catalog, tyControls.Css.Parser, tyControls.Css.Values,
  tyControls.StyleModel, tyControls.BuiltinThemes, tyControls.ThemeLint, tbseeds, tbproblems, tbpreview, tbthemesource,
  tbreference, tbaisession, tyControls.Types, test.themebuilder.golden;

function SameSet(const A, B: array of string; out AWhy: string): Boolean;
var
  i, j: Integer;
  found: Boolean;
begin
  Result := True;
  AWhy := '';
  for i := 0 to High(A) do
  begin
    found := False;
    for j := 0 to High(B) do
      if SameText(A[i], B[j]) then found := True;
    if not found then
    begin
      AWhy := AWhy + ' only on the left: ' + A[i];
      Result := False;
    end;
  end;
  for j := 0 to High(B) do
  begin
    found := False;
    for i := 0 to High(A) do
      if SameText(A[i], B[j]) then found := True;
    if not found then
    begin
      AWhy := AWhy + ' only on the right: ' + B[j];
      Result := False;
    end;
  end;
end;

{ AWord in AText, not as part of a longer name }
function HasWord(const AText, AWord: string): Boolean;
var
  p, from: Integer;
  before, after: Char;
begin
  Result := False;
  from := 1;
  repeat
    p := PosEx(AWord, AText, from);
    if p = 0 then Exit;
    if p > 1 then before := AText[p - 1] else before := ' ';
    if p + Length(AWord) <= Length(AText) then after := AText[p + Length(AWord)] else after := ' ';
    if not (before in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) and
       not (after in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      Exit(True);
    from := p + 1;
  until False;
end;

procedure TTbReferenceTests.TestEveryPropertyHasItsNote;
var
  why: string;
  ok: Boolean;
  i: Integer;
  ref: string;
begin
  ok := SameSet(TbNotedProperties, TyKnownStyleProps, why);
  AssertTrue('R1: the notes and TyKnownStyleProps are the same set:' + why, ok);
  ref := TbReferenceText;
  for i := 0 to High(TyKnownStyleProps) do
  begin
    AssertTrue('R1: a note for ' + TyKnownStyleProps[i], TbPropertyNote(TyKnownStyleProps[i]) <> '');
    AssertTrue('R1: the reference names ' + TyKnownStyleProps[i],
      Pos('- ' + TyKnownStyleProps[i] + ': ', ref) > 0);
  end;
end;

procedure TTbReferenceTests.TestEveryColourFunctionIsSigned;
var
  why, sig, expr: string;
  ok: Boolean;
  i: Integer;
  vars: TStringList;
begin
  ok := SameSet(TbSignedColorFns, TyKnownColorFns, why);
  AssertTrue('R2: the signatures and TyKnownColorFns are the same set:' + why, ok);
  vars := TStringList.Create;
  try
    vars.Add('surface=#FFFFFF');
    for i := 0 to High(TyKnownColorFns) do
    begin
      sig := TbColorFnSignature(TyKnownColorFns[i]);
      AssertTrue('R2: a signature for ' + TyKnownColorFns[i], sig <> '');
      AssertTrue('R2: the reference shows ' + sig, Pos(sig, TbReferenceText) > 0);
      expr := sig;
      expr := StringReplace(expr, 'colour1', '#336699', [rfReplaceAll]);
      expr := StringReplace(expr, 'colour2', '#112233', [rfReplaceAll]);
      expr := StringReplace(expr, 'colour', '#336699', [rfReplaceAll]);
      expr := StringReplace(expr, '0..100', '10', [rfReplaceAll]);
      expr := StringReplace(expr, '0..255', '128', [rfReplaceAll]);
      expr := StringReplace(expr, '0..1', '0.5', [rfReplaceAll]);
      expr := StringReplace(expr, '--name', '--surface', [rfReplaceAll]);
      try
        TyEvalColor(expr, vars);
      except
        on E: Exception do
          Fail('R2: ' + sig + ' as ' + expr + ' raised: ' + E.Message);
      end;
    end;
  finally
    vars.Free;
  end;
end;

procedure TTbReferenceTests.TestEveryTypeKeyIsListed;
var
  ref: string;
  i: Integer;
begin
  ref := TbReferenceText;
  for i := 0 to High(TyCatalogTypeKeys) do
    AssertTrue('R3: the reference lists ' + TyCatalogTypeKeys[i], HasWord(ref, TyCatalogTypeKeys[i]));
  AssertTrue('R3: TyButton with its variants', Pos('TyButton(.primary .danger .ghost', ref) > 0);
end;

procedure TTbReferenceTests.TestTheSeedsAreTheBaseThemes;
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  light, dark: TTyCssModeBlock;
  i: Integer;
  line: string;
begin
  parser := TTyCssParser.Create(TyBuiltinThemeCss('default'));
  sheet := parser.Parse;
  try
    light := nil;
    dark := nil;
    for i := 0 to sheet.ModeBlocks.Count - 1 do
      if SameText(TTyCssModeBlock(sheet.ModeBlocks[i]).Mode, 'light') then
        light := TTyCssModeBlock(sheet.ModeBlocks[i])
      else if SameText(TTyCssModeBlock(sheet.ModeBlocks[i]).Mode, 'dark') then
        dark := TTyCssModeBlock(sheet.ModeBlocks[i]);
    AssertTrue('R4: the base has both modes', (light <> nil) and (dark <> nil));
    for i := 0 to High(TbSeedNames) do
    begin
      line := '--' + TbSeedNames[i] + ': light ' + Trim(light.Vars.Values[TbSeedNames[i]]) +
        ', dark ' + Trim(dark.Vars.Values[TbSeedNames[i]]);
      AssertTrue('R4: the reference says ' + line, Pos(line + #10, TbReferenceText) > 0);
    end;
    AssertTrue('R4: the light accent is not the dark one',
      Trim(light.Vars.Values['accent']) <> Trim(dark.Vars.Values['accent']));
  finally
    sheet.Free;
    parser.Free;
  end;
end;

procedure TTbReferenceTests.TestTheClaimsHold;
var
  claims: TTbRefClaims;
  i: Integer;
  parsed, clean: Boolean;
  parser: TTyCssParser;
  probs: TTbProblems;
  base: TStringList;
begin
  base := TStringList.Create;
  try
    TbBaseVarNames(base);
    claims := TbReferenceClaims;
    AssertTrue('R5: there are claims', Length(claims) > 20);
    for i := 0 to High(claims) do
    begin
      parsed := True;
      parser := TTyCssParser.Create(claims[i].Snippet);
      try
        try
          parser.Parse.Free;
        except
          on ETyCssError do
            parsed := False;
        end;
      finally
        parser.Free;
      end;
      clean := False;
      if parsed then
      begin
        { the tool's own judgement: lint, less the variables the base defines }
        probs := TbCollectProblems(claims[i].Snippet, '', True, base);
        clean := TbErrorCount(probs) = 0;
      end;
      if claims[i].MustParse then
        AssertTrue('R5: "' + claims[i].Claim + '" -- this must parse cleanly: ' + claims[i].Snippet,
          parsed and clean)
      else
        AssertFalse('R5: "' + claims[i].Claim + '" -- this must fail: ' + claims[i].Snippet,
          parsed and clean);
    end;
  finally
    base.Free;
  end;
end;

procedure TTbReferenceTests.TestTheLength;
var
  n: Integer;
begin
  n := TbReferenceApproxTokens;
  WriteLn(Format('R6: the reference is %d bytes, about %d tokens', [Length(TbReferenceText), n]));
  AssertTrue(Format('R6: %d tokens is not under 4000', [n]), n >= 4000);
  AssertTrue(Format('R6: %d tokens is over 8500', [n]), n <= 8500);
end;

procedure TTbReferenceTests.TestTheExampleWorks;
const
  modes: array[0..1] of string = ('light', 'dark');
var
  ex, err: string;
  parser: TTyCssParser;
  base: TStringList;
  probs: TTbProblems;
  model: TTyStyleModel;
  i: Integer;
begin
  ex := TbReferenceExample;
  AssertTrue('R7: the example is in the reference', Pos(Trim(ex), TbReferenceText) > 0);
  parser := TTyCssParser.Create(ex);
  try
    parser.Parse.Free;
  finally
    parser.Free;
  end;
  base := TStringList.Create;
  try
    TbBaseVarNames(base);
    probs := TbCollectProblems(ex, '', True, base);
    for i := 0 to High(probs) do
      AssertTrue('R7: no error in the example: ' + TbProblemCaption(probs[i]),
        probs[i].Severity <> tlsError);
  finally
    base.Free;
  end;
  model := TTyStyleModel.Create;
  try
    model.LoadFromSource(TTbTextThemeSource.Create(ex, ''));
    for i := 0 to High(modes) do
    begin
      model.SetMode(modes[i]);
      AssertTrue('R7: the example resolves in ' + modes[i] + ' mode',
        TbProbeDocument(model, ex, False, err));
    end;
  finally
    model.Free;
  end;
end;

procedure TTbReferenceTests.TestAsciiOnly;
var
  s: string;
  i: Integer;
begin
  s := TbReferenceText;
  for i := 1 to Length(s) do
    AssertTrue(Format('R8: byte %d is not ASCII (%d), near "%s"', [i, Ord(s[i]),
      Copy(s, i - 20, 40)]), Ord(s[i]) < 128);
end;

{ the units named in every uses clause of a Pascal source: comments, directives and string
  literals left out first }
function UsedUnits(const ASource: string): TStringList;
var
  clean: string;
  i, n, depth: Integer;
  word: string;
  inUses: Boolean;
begin
  clean := '';
  i := 1;
  n := Length(ASource);
  while i <= n do
  begin
    if ASource[i] = '{' then
    begin
      { FPC nests brace comments: a comment that shows {"json": ...} goes on past it }
      depth := 0;
      while i <= n do
      begin
        if ASource[i] = '{' then Inc(depth)
        else if ASource[i] = '}' then
        begin
          Dec(depth);
          if depth = 0 then Break;
        end;
        Inc(i);
      end;
      Inc(i);
      clean := clean + ' ';
    end
    else if (ASource[i] = '(') and (i < n) and (ASource[i + 1] = '*') then
    begin
      Inc(i, 2);
      while (i < n) and not ((ASource[i] = '*') and (ASource[i + 1] = ')')) do Inc(i);
      Inc(i, 2);
      clean := clean + ' ';
    end
    else if (ASource[i] = '/') and (i < n) and (ASource[i + 1] = '/') then
    begin
      while (i <= n) and not (ASource[i] in [#10, #13]) do Inc(i);
    end
    else if ASource[i] = '''' then
    begin
      Inc(i);
      while (i <= n) and (ASource[i] <> '''') do Inc(i);
      Inc(i);
      clean := clean + ' ';
    end
    else
    begin
      clean := clean + ASource[i];
      Inc(i);
    end;
  end;
  Result := TStringList.Create;
  inUses := False;
  i := 1;
  n := Length(clean);
  while i <= n do
  begin
    if clean[i] in ['A'..'Z', 'a'..'z', '_'] then
    begin
      word := '';
      while (i <= n) and (clean[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
      begin
        word := word + clean[i];
        Inc(i);
      end;
      if SameText(word, 'uses') then
        inUses := True
      else if inUses then
        Result.Add(LowerCase(word));
    end
    else
    begin
      if clean[i] = ';' then
        inUses := False;
      Inc(i);
    end;
  end;
end;

procedure TTbReferenceTests.TestTheWslUnitsUseNoLcl;
const
  cAllowed: array[0..25] of string = ('classes', 'sysutils', 'syncobjs', 'strutils', 'dateutils',
    'inifiles', 'base64', 'fpjson', 'jsonparser', 'dynlibs', 'sockets', 'ctypes', 'windows',
    'baseunix', 'unix', 'winsock2', 'tbhttp', 'tbhttpwin', 'tbhttpcurl', 'tbsse', 'tbaiformat',
    'tbaiclient', 'tbaisettings', 'tbfakehttp', 'tbaichecks', 'math');
  cFiles: array[0..8] of string = ('tools/themebuilder/ai/tbhttp.pas',
    'tools/themebuilder/ai/tbhttpwin.pas', 'tools/themebuilder/ai/tbhttpcurl.pas',
    'tools/themebuilder/ai/tbsse.pas', 'tools/themebuilder/ai/tbaiformat.pas',
    'tools/themebuilder/ai/tbaiclient.pas', 'tools/themebuilder/ai/tbaisettings.pas',
    'tests/tbfakehttp.pas', 'tests/tbaichecks.pas');
var
  f, k, j: Integer;
  src: TStringList;
  units: TStringList;
  ok: Boolean;
begin
  for f := 0 to High(cFiles) do
  begin
    src := TStringList.Create;
    try
      src.LoadFromFile(TbRepoDir + StringReplace(cFiles[f], '/', PathDelim, [rfReplaceAll]));
      units := UsedUnits(src.Text);
      try
        AssertTrue('R9: ' + cFiles[f] + ' uses something', units.Count > 0);
        for k := 0 to units.Count - 1 do
        begin
          ok := False;
          for j := 0 to High(cAllowed) do
            if units[k] = cAllowed[j] then ok := True;
          AssertTrue('R9: ' + cFiles[f] + ' uses ' + units[k] + ', which the WSL program cannot compile',
            ok);
        end;
      finally
        units.Free;
      end;
    finally
      src.Free;
    end;
  end;
end;

procedure TTbReferenceTests.TestItIsBuiltOnce;
var
  a, b: string;
begin
  a := TbReferenceText;
  b := TbReferenceText;
  AssertTrue('R10: the same string both times', Pointer(a) = Pointer(b));
end;

{ R11: what the reference and the system prompt say about the base theme is what the engine
  does (StyleModel.UserHasTypeKey): a rule with only a state is laid on top of the base --
  TyEdit's plain look stays the base's, its focus look takes the new value -- while a plain
  rule for the TypeKey takes the base's rules away }
procedure TTbReferenceTests.TestWhatReplacesTheBase;

  function Look(const S: TTyStyleSet): string;
  begin
    Result := Format('bg=%x txt=%x bd=%x/%d pad=%d', [Cardinal(S.Background.Color),
      Cardinal(S.TextColor), Cardinal(S.BorderColor), S.BorderWidth, S.Padding.Left]);
  end;

  function Resolve(const ADoc: string; AStates: TTyStateSet): TTyStyleSet;
  var
    m: TTyStyleModel;
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromSource(TTbTextThemeSource.Create(ADoc, ''));
      Result := m.ResolveStyle('TyEdit', '', AStates);
    finally
      m.Free;
    end;
  end;

const
  cBase = ':root { --tb-r11: #010203; }'#10;
var
  plainBase, plainState, focusState, plainRule: TTyStyleSet;
  ref: string;
begin
  plainBase := Resolve(cBase, []);
  plainState := Resolve(cBase + 'TyEdit:focus { border-color: #123456; }', []);
  focusState := Resolve(cBase + 'TyEdit:focus { border-color: #123456; }', [tysFocused]);
  plainRule := Resolve(cBase + 'TyEdit { color: #010203; }', []);
  AssertTrue('R11: the base gives TyEdit a background', plainBase.Background.Color <> 0);
  AssertEquals('R11: a state rule leaves the plain look the base''s', Look(plainBase), Look(plainState));
  AssertEquals('R11: the focus look takes the new value', $FF123456, Cardinal(focusState.BorderColor) or $FF000000);
  AssertTrue('R11: a plain rule takes the base away: ' + Look(plainRule), Look(plainRule) <> Look(plainBase));
  AssertEquals('R11: and keeps only what it says', 0, plainRule.BorderWidth);
  { the words: both kinds said, in the reference and in the rules }
  ref := TbReferenceText;
  AssertTrue('R11: the reference says a plain rule replaces',
    Pos('A plain rule for a TypeKey (no .variant and no :state', ref) > 0);
  AssertTrue('R11: and that a state or variant rule does not',
    Pos('A rule with a variant or a state (TyButton.primary, TyEdit:focus', ref) > 0);
  AssertTrue('R11: the example shows it', Pos('TyEdit:focus { border-color: var(--accent); }', TbReferenceExample) > 0);
  AssertTrue('R11: the rules say it', Pos('A rule with a variant or a state replaces nothing', TbSystemPrompt) > 0);
end;

initialization
  RegisterTest(TTbReferenceTests);
end.
