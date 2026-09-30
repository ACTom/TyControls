unit test.terminal.view.theme;
{$mode objfpc}{$H+}
{ 终端的主题键与 token,跨全部内置主题 × 明暗:21 个键都解析得出;深底拿到 Tango,浅底拿到
  light-palette.js 算出来的那套(对白底 ≥ 4.5:1);密度;选区跟焦点;字体 token 原样读。 }

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Terminal.Core, tyControls.Terminal.Render;

type
  TTyTerminalViewThemeTests = class(TTestCase)
  private
    function Rec601(ARgb: Cardinal): Double;
  published
    procedure TestEveryThemeResolvesTheTerminalKeys;
    procedure TestDarkGroundsGetTango;
    procedure TestLightGroundsGetTheTunedSet;
    procedure TestTheTerminalLengthsHaveDensityValues;
    procedure TestSelectionFollowsFocus;
    procedure TestTheSelectionStandsOutOnEveryTheme;
    procedure TestTheFontTokensAreReadRaw;
    { 5 期:最低对比度兜得住每个主题的 16 色 }
    procedure TestContrastLiftsTheSixteenColours;
  end;

implementation

const
  Tango: array[0..15] of Cardinal = (
    $2E3436, $CC0000, $4E9A06, $C4A000, $3465A4, $75507B, $06989A, $D3D7CF,
    $555753, $EF2929, $8AE234, $FCE94F, $729FCF, $AD7FA8, $34E2E2, $EEEEEC);
  { 由 tools/terminal-oracle/light-palette.js 算出(xterm.js 的 ensureContrastRatio,对白底
    4.5:1,0 / 7 / 8 / 15 不动);它的 --check 守着 light.tycss 里的同一组数 }
  LightGround: array[0..15] of Cardinal = (
    $2E3436, $CC0000, $3F7C04, $8E7400, $3465A4, $75507B, $047A7C, $D3D7CF,
    $555753, $D72424, $50831C, $756D24, $517396, $8B6687, $1C8383, $EEEEEC);

function Fg(M: TTyStyleModel; const AKey: string; out AColor: Cardinal): Boolean;
var
  st: TTyStyleSet;
begin
  st := M.ResolveStyle(AKey, '', []);
  Result := tpTextColor in st.Present;
  AColor := Cardinal(st.TextColor) and $FFFFFF;
end;

function Bg(M: TTyStyleModel; const AKey: string; out AColor: Cardinal): Boolean;
var
  st: TTyStyleSet;
begin
  st := M.ResolveStyle(AKey, '', []);
  Result := (tpBackground in st.Present) and (st.Background.Kind = tfkSolid);
  AColor := Cardinal(st.Background.Color) and $FFFFFF;
end;

function TTyTerminalViewThemeTests.Rec601(ARgb: Cardinal): Double;
begin
  { what the three-argument on() looks at (Css.Values: > 0.5 takes the second argument) }
  Result := (0.299 * ((ARgb shr 16) and $FF) + 0.587 * ((ARgb shr 8) and $FF) + 0.114 * (ARgb and $FF)) / 255;
end;

procedure TTyTerminalViewThemeTests.TestEveryThemeResolvesTheTerminalKeys;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, n, compared, missing: Integer;
  col: Cardinal;
  miss: TStringList;
  where: string;

  procedure Need(AOk: Boolean; const AWhat: string);
  begin
    Inc(compared);
    if not AOk then
    begin
      Inc(missing);
      if miss.Count < 30 then miss.Add(where + ': ' + AWhat);
    end;
  end;

begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  miss := TStringList.Create;
  try
    names := TyBuiltinThemeNames;
    compared := 0;
    missing := 0;
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        c.ThemeName := names[i];
        if m = 0 then c.Mode := 'light' else c.Mode := 'dark';
        where := names[i] + '/' + c.Mode;
        Need(Bg(c.Model, 'TyTerminal', col) and Fg(c.Model, 'TyTerminal', col), 'TyTerminal background and colour');
        for n := 0 to 15 do
          Need(Fg(c.Model, 'TyTerminalAnsi' + IntToStr(n), col), 'TyTerminalAnsi' + IntToStr(n));
        Need(Bg(c.Model, 'TyTerminalCursor', col), 'TyTerminalCursor background');
        Need(Bg(c.Model, 'TyTerminalSelection', col), 'TyTerminalSelection background');
        Need(Bg(c.Model, 'TyTerminalPreedit', col), 'TyTerminalPreedit background');
        Need(Fg(c.Model, 'TyTerminalLink', col), 'TyTerminalLink colour');
      end;
    AssertEquals(IntToStr(missing) + ' missing:' + LineEnding + miss.Text, 0, missing);
    AssertTrue('themes to check', Length(names) > 0);
    AssertEquals('comparisons = themes x 2 modes x 21 keys', Length(names) * 2 * 21, compared);
  finally
    miss.Free;
    c.Free;
  end;
end;

procedure TTyTerminalViewThemeTests.TestDarkGroundsGetTango;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, n, dark: Integer;
  ground, col: Cardinal;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    dark := 0;
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        c.ThemeName := names[i];
        if m = 0 then c.Mode := 'light' else c.Mode := 'dark';
        AssertTrue('the ground resolves', Bg(c.Model, 'TyTerminal', ground));
        if Rec601(ground) > 0.5 then Continue;
        Inc(dark);
        for n := 0 to 15 do
        begin
          AssertTrue(Fg(c.Model, 'TyTerminalAnsi' + IntToStr(n), col));
          AssertEquals(Format('%s/%s ansi %d on a dark ground', [names[i], c.Mode, n]),
            IntToHex(Tango[n], 6), IntToHex(col, 6));
        end;
      end;
    AssertTrue('at least one dark ground was checked', dark > 0);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalViewThemeTests.TestLightGroundsGetTheTunedSet;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, n, light: Integer;
  ground, col: Cardinal;
  worst: Double;
  line: string;
begin
  for n := 0 to 15 do
    if (n in [1..6]) or (n in [9..14]) then
      AssertTrue(Format('ansi %d reaches 4.5:1 on white', [n]),
        (TyTermRelativeLuminance($FFFFFF) + 0.05) / (TyTermRelativeLuminance(LightGround[n]) + 0.05) >= 4.5);
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    light := 0;
    WriteLn('TTyTerminalViewThemeTests: the light-ground 16 colours on each light ground (worst of 1-6, 9-14)');
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        c.ThemeName := names[i];
        if m = 0 then c.Mode := 'light' else c.Mode := 'dark';
        AssertTrue('the ground resolves', Bg(c.Model, 'TyTerminal', ground));
        if Rec601(ground) <= 0.5 then Continue;
        Inc(light);
        worst := 99;
        for n := 0 to 15 do
        begin
          AssertTrue(Fg(c.Model, 'TyTerminalAnsi' + IntToStr(n), col));
          AssertEquals(Format('%s/%s ansi %d on a light ground', [names[i], c.Mode, n]),
            IntToHex(LightGround[n], 6), IntToHex(col, 6));
          if (n in [1..6]) or (n in [9..14]) then
            worst := Min(worst, (Max(TyTermRelativeLuminance(ground), TyTermRelativeLuminance(col)) + 0.05)
              / (Min(TyTermRelativeLuminance(ground), TyTermRelativeLuminance(col)) + 0.05));
        end;
        line := Format('  %-14s %-5s ground #%s  worst %.2f:1', [names[i], c.Mode, IntToHex(ground, 6), worst]);
        WriteLn(line);
      end;
    AssertTrue('at least one light ground was checked', light > 0);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalViewThemeTests.TestContrastLiftsTheSixteenColours;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, n, checked: Integer;
  ground, col, lifted: Cardinal;
  after: Double;

  function Ratio(A, B: Cardinal): Double;
  begin
    Result := TyTermContrastRatio(TyTermRelativeLuminance(A), TyTermRelativeLuminance(B));
  end;

begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    checked := 0;
    WriteLn('TTyTerminalViewThemeTests: colour 3 on the light grounds of xp / macos / breeze, before and after 4.5');
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        c.ThemeName := names[i];
        if m = 0 then c.Mode := 'light' else c.Mode := 'dark';
        AssertTrue('the ground resolves', Bg(c.Model, 'TyTerminal', ground));
        for n := 0 to 15 do
          if (n in [1..6]) or (n in [9..14]) then
          begin
            AssertTrue(Fg(c.Model, 'TyTerminalAnsi' + IntToStr(n), col));
            if not TyTermEnsureContrastRatio(ground, col, 4.5, lifted) then lifted := col;
            after := Ratio(ground, lifted);
            Inc(checked);
            AssertTrue(Format('%s/%s ansi %d on #%s: %.2f:1 after 4.5', [names[i], c.Mode, n, IntToHex(ground, 6), after]),
              after >= 4.5);
            if (n = 3) and (m = 0) and ((names[i] = 'xp') or (names[i] = 'macos') or (names[i] = 'breeze')) then
              WriteLn(Format('  %-8s ground #%s  #%s %.2f:1 -> #%s %.2f:1', [names[i], IntToHex(ground, 6),
                IntToHex(col, 6), Ratio(ground, col), IntToHex(lifted, 6), after]));
          end;
      end;
    AssertEquals('every theme, both modes, twelve colours', Length(names) * 2 * 12, checked);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalViewThemeTests.TestTheTerminalLengthsHaveDensityValues;
var
  c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.Mode := 'light';
    c.ThemeName := 'default';
    AssertEquals('classic pad', 4, c.Metric('--terminal-pad', -1));
    AssertEquals('classic cursor width', 1, c.Metric('--terminal-cursor-width', -1));
    AssertEquals('classic underline width', 1, c.Metric('--terminal-underline-width', -1));
    c.Density := tdModern;
    AssertEquals('modern pad', 8, c.Metric('--terminal-pad', -1));
    AssertEquals('modern cursor width', 1, c.Metric('--terminal-cursor-width', -1));
    AssertEquals('modern underline width', 1, c.Metric('--terminal-underline-width', -1));
  finally
    c.Free;
  end;
end;

procedure TTyTerminalViewThemeTests.TestSelectionFollowsFocus;
var
  c: TTyStyleController;
  a, b: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.Mode := 'light';
    c.ThemeName := 'default';
    a := c.Model.ResolveStyle('TyTerminalSelection', '', []);
    b := c.Model.ResolveStyle('TyTerminalSelection', '', [tysFocused]);
    AssertTrue('both have a background', (tpBackground in a.Present) and (tpBackground in b.Present));
    AssertTrue('the focused selection is another colour', a.Background.Color <> b.Background.Color);
  finally
    c.Free;
  end;
end;

{ WCAG 2 relative luminance and contrast ratio }
function Luminance(ARgb: Cardinal): Double;

  function Lin(AByte: Cardinal): Double;
  var
    v: Double;
  begin
    v := AByte / 255;
    if v <= 0.03928 then Result := v / 12.92 else Result := Power((v + 0.055) / 1.055, 2.4);
  end;

begin
  Result := 0.2126 * Lin((ARgb shr 16) and $FF) + 0.7152 * Lin((ARgb shr 8) and $FF) + 0.0722 * Lin(ARgb and $FF);
end;

function Contrast(A, B: Cardinal): Double;
var
  la, lb: Double;
begin
  la := Luminance(A);
  lb := Luminance(B);
  Result := (Max(la, lb) + 0.05) / (Min(la, lb) + 0.05);
end;

{ The selection -- focused and not -- has to be seen on every built-in theme in both
  modes: its colour made opaque on the terminal's ground (what the view paints, upstream's
  selectionBackgroundOpaque) against that ground, as a WCAG contrast ratio.
  THE BOUNDS, one per state, below the worst measured when the unfocused selection went
  to upstream's alpha 0.3 (spec 11, phase 4): unfocused 1.70 (worst 1.80, macos/light;
  the old alpha 0.18 gave 1.41 there, macos/light -- a shade off the ground,
  which is why it changed -- and this bound fails it); focused 1.25 (worst 1.27,
  office/dark: its accent is a blue about as dark as its surface -- told apart by hue,
  which a luminance ratio does not see; this batch does not touch the focused colour,
  the bound only keeps a skin from making it worse). A selection is a tint over text,
  not text: WCAG's 3:1 for non-text would ask for one that hides what it selects. }
procedure TTyTerminalViewThemeTests.TestTheSelectionStandsOutOnEveryTheme;
const
  Bound: array[Boolean] of Double = (1.70, 1.25);
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, f, compared: Integer;
  ground, opaque: Cardinal;
  st: TTyStyleSet;
  sel: TTyColor;
  ratio: Double;
  worst: array[Boolean] of Double;
  worstAt: array[Boolean] of string;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    compared := 0;
    worst[False] := 1000;
    worst[True] := 1000;
    worstAt[False] := '';
    worstAt[True] := '';
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        c.ThemeName := names[i];
        if m = 0 then c.Mode := 'light' else c.Mode := 'dark';
        AssertTrue('the ground resolves', Bg(c.Model, 'TyTerminal', ground));
        for f := 0 to 1 do
        begin
          if f = 1 then
            st := c.Model.ResolveStyle('TyTerminalSelection', '', [tysFocused])
          else
            st := c.Model.ResolveStyle('TyTerminalSelection', '', []);
          AssertTrue('a selection colour', (tpBackground in st.Present) and (st.Background.Kind = tfkSolid));
          sel := st.Background.Color;
          opaque := TyTermBlendOver(ground, BGRA(TyRedOf(sel), TyGreenOf(sel), TyBlueOf(sel), TyAlphaOf(sel)));
          ratio := Contrast(opaque, ground);
          Inc(compared);
          if ratio < worst[f = 1] then
          begin
            worst[f = 1] := ratio;
            worstAt[f = 1] := Format('%s/%s: #%.6x on #%.6x', [names[i], c.Mode, opaque, ground]);
          end;
        end;
      end;
    AssertEquals('themes x 2 modes x 2 states', Length(names) * 4, compared);
    AssertTrue(Format('the unfocused selection stands out everywhere: worst %.3f (%s), bound %.2f',
      [worst[False], worstAt[False], Bound[False]]), worst[False] >= Bound[False]);
    AssertTrue(Format('the focused selection stands out everywhere: worst %.3f (%s), bound %.2f',
      [worst[True], worstAt[True], Bound[True]]), worst[True] >= Bound[True]);
  finally
    c.Free;
  end;
end;

procedure TTyTerminalViewThemeTests.TestTheFontTokensAreReadRaw;
var
  c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.Mode := 'light';
    c.ThemeName := 'default';
    AssertEquals('family', 'monospace', Trim(c.Model.RawVar('--terminal-font-family')));
    AssertEquals('wide family', 'monospace-wide', Trim(c.Model.RawVar('--terminal-font-family-wide')));
    AssertFalse('no rule writes font-family (it would not evaluate var())',
      tpFontName in c.Model.ResolveStyle('TyTerminal', '', []).Present);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalViewThemeTests);
end.
