unit test.terminal.view.theme;
{$mode objfpc}{$H+}
{ 终端的主题键与 token,跨全部内置主题 × 明暗:21 个键都解析得出;深底拿到 Tango,浅底拿到
  light-palette.js 算出来的那套(对白底 ≥ 4.5:1);密度;选区跟焦点;字体 token 原样读。 }

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Terminal.Core;

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
    procedure TestTheFontTokensAreReadRaw;
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
