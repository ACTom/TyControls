unit test.terminal.view.scheme;
{$mode objfpc}{$H+}
{ TTyTerminalView 的独立配色方案(6 期):ColorSource / ColorScheme / ColorSchemePaired /
  DarkColorScheme 的流式化与加载,色表按「OSC 覆盖 > 方案 > 主题」取,明暗配对,通知 Core 的
  时机,以及方案下的最低对比度、禁用、选区、组字串。

  夹具照 test.terminal.view 的 TTyTermViewFixture(真父窗体、自建 controller、主题补丁
  TyTermFixtureCss:底 #102030 是深的)。方案的颜色与夹具主题的颜色都不同、R 不等于 B,
  换反字节序、取错一层都看得出来。 }

interface

uses
  Classes, SysUtils, Types, Math, TypInfo, Forms, Controls, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Css.Values, tyControls.StyleModel, tyControls.Controller, tyControls.Base,
  tyControls.Terminal.Core, tyControls.Terminal.Render, tyControls.Terminal.ColorScheme,
  tyControls.Terminal,
  test.terminal.keyboard, test.terminal.view, test.terminal.colorscheme;

type
  TTyTerminalViewSchemeTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    FClockMs: Double;
    procedure Pump;
    function Reports: Integer;
    function Clock: Double;
    procedure Load(AScheme: TTyTerminalColorScheme; const AName: string);
    function Res(AIndex: Integer): string;
    procedure Settle;
    procedure Step(const AWhat: string; AWant: Integer);
    procedure Quiet(const AWhat: string);
    function Pumpless996: RawByteString;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Task 5:属性、流式化、加载 }
    procedure TestTheSchemesStream;
    procedure TestLoadingNotifiesNothing;
    { Task 6:取色、明暗配对、通知时机 }
    procedure TestFollowingTheThemeIgnoresTheScheme;
    procedure TestSlotsComeFromTheScheme;
    procedure TestUnsetSlotsFollowTheTheme;
    procedure TestTheCursorInkComesFromTheScheme;
    procedure TestTheSelectionIsThreeTenths;
    procedure TestProgramColoursBeatTheScheme;
    procedure TestModeQueriesAnswerTheGroundInEffect;
    procedure TestNotificationsComeOncePerChange;
    procedure TestPairingFollowsTheThemeGround;
    procedure TestTheDarkSideIsWhatOnCalls;
    procedure TestContrastWorksOnTheScheme;
    procedure TestDisabledFadesTheScheme;
    procedure TestMarkedTextTakesTheSchemesGround;
    { 6 期审查 }
    procedure TestChangedRefreshesASystemColour;
  end;

implementation

type
  { the view's test queries are protected: a descendant in this unit reaches them }
  TSchemeAccess = class(TTyTerminalViewProbe);

const
  SlotProps: array[TTyTerminalSchemeSlot] of string = (
    'Black', 'Red', 'Green', 'Yellow', 'Blue', 'Purple', 'Cyan', 'White',
    'BrightBlack', 'BrightRed', 'BrightGreen', 'BrightYellow',
    'BrightBlue', 'BrightPurple', 'BrightCyan', 'BrightWhite',
    'Foreground', 'Background', 'CursorColor', 'CursorText',
    'SelectionBackground', 'SelectionInactiveBackground');

function Hex6(V: Cardinal): string;
begin
  Result := '$' + IntToHex(V and $FFFFFF, 6);
end;

procedure TTyTerminalViewSchemeTests.SetUp;
begin
  TyTermNeedWidgetSet;
  F := TTyTermViewFixture.Create;
  F.SizeTo(20, 5);
  { pixel tests want whole frames: the glyph budget reads a clock that stands still
    (as test.terminal.view.paint does) }
  FClockMs := 100000;
  F.View.Core.Clock := @Clock;
end;

procedure TTyTerminalViewSchemeTests.TearDown;
begin
  if F <> nil then F.View.Core.Clock := nil;
  FreeAndNil(F);
end;

procedure TTyTerminalViewSchemeTests.Pump;
var
  i: Integer;
begin
  for i := 1 to 5 do
    Application.ProcessMessages;
end;

{ 2031 的明暗报告(ESC [ ? 997 ; n n)在记录里出现了几条 }
function TTyTerminalViewSchemeTests.Reports: Integer;
var
  p: Integer;
  s: string;
begin
  Result := 0;
  s := F.Data;
  p := Pos(#27'[?997;', s);
  while p > 0 do
  begin
    Inc(Result);
    Delete(s, 1, p + 5);
    p := Pos(#27'[?997;', s);
  end;
end;

{ ---- Task 5 ------------------------------------------------------------------------ }

procedure TTyTerminalViewSchemeTests.TestTheSchemesStream;
var
  src, dst: TTyTerminalView;
  ms, txt: TMemoryStream;
  lines: TStringList;
  i, dark: Integer;
begin
  src := TTyTerminalView.Create(nil);
  dst := TTyTerminalView.Create(nil);
  ms := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  lines := TStringList.Create;
  try
    src.ColorSource := tsrcScheme;
    src.ColorSchemePaired := True;
    src.ColorScheme.LoadFromText(TyTermDocCampbell);
    src.DarkColorScheme.Red := TColor($1F0FC5);
    src.DarkColorScheme.Name := 'Mine';
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    txt.Position := 0;
    lines.LoadFromStream(txt);
    dark := 0;
    for i := 0 to lines.Count - 1 do
      if Pos('DarkColorScheme.', TrimLeft(lines[i])) = 1 then Inc(dark);
    AssertEquals('only what was set is streamed:' + LineEnding + lines.Text, 2, dark);
    ms.Position := 0;
    ms.ReadComponent(dst);
    AssertTrue('ColorSource', dst.ColorSource = tsrcScheme);
    AssertTrue('ColorSchemePaired', dst.ColorSchemePaired);
    AssertTrue('ColorScheme', dst.ColorScheme.Equals(src.ColorScheme));
    AssertEquals('ColorScheme.Name', 'Campbell', dst.ColorScheme.Name);
    AssertTrue('DarkColorScheme', dst.DarkColorScheme.Equals(src.DarkColorScheme));
    AssertEquals('DarkColorScheme.Red', IntToHex($1F0FC5, 8), IntToHex(dst.DarkColorScheme.Red, 8));
    AssertTrue('the setter assigns, the object stays the view''s own',
      dst.ColorScheme <> src.ColorScheme);
  finally
    lines.Free;
    txt.Free;
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestLoadingNotifiesNothing;
var
  lfm: string;
  s: TTyTerminalSchemeSlot;
  inp: TStringStream;
  bin: TMemoryStream;
  b: TBGRABitmap;
begin
  lfm := 'object View: TTyTerminalViewProbe'#10'  ColorSource = tsrcScheme'#10
    + '  ColorScheme.Name = ''Campbell'''#10;
  for s := Low(s) to High(s) do
    lfm := lfm + '  ColorScheme.' + SlotProps[s] + ' = ' + IntToStr($100000 + Ord(s) * $0A0B03) + #10;
  lfm := lfm + 'end'#10;
  inp := TStringStream.Create(lfm);
  bin := TMemoryStream.Create;
  try
    ObjectTextToBinary(inp, bin);
    bin.Position := 0;
    F.ClearRecords;
    bin.ReadComponent(F.View);
  finally
    bin.Free;
    inp.Free;
  end;
  AssertEquals('loaded', 'Campbell', F.View.ColorScheme.Name);
  AssertTrue('loaded: the source', F.View.ColorSource = tsrcScheme);
  AssertEquals('loading queued no notification', 0, TSchemeAccess(F.View).SchemeNotifyRequests);
  Pump;
  AssertEquals('nothing sent after loading', '', TyTermHex(F.Data));
  AssertFalse('nothing queued', TSchemeAccess(F.View).NotifyQueued);
  F.View.WriteSync(#27'[?2031h');
  F.ClearRecords;
  b := F.Render;
  b.Free;
  Pump;
  AssertEquals('the first palette after loading is not a change', '', TyTermHex(F.Data));
  F.View.ColorScheme.Background := TColor($0C0D0E);
  Pump;
  AssertEquals('a change after loading is reported once: ' + TyTermHex(F.Data), 1, Reports);
end;

{ ---- Task 6 ------------------------------------------------------------------------ }

const
  { 浅底的主题补丁(夹具的底 #102030 是深的) }
  LightCss = 'TyTerminal { background: #f4f4f4; color: #202020; }'#10;
  CampbellRgb: array[0..15] of Cardinal = (
    $0C0C0C, $C50F1F, $13A10E, $C19C00, $0037DA, $881798, $3A96DD, $CCCCCC,
    $767676, $E74856, $16C60C, $F9F1A5, $3B78FF, $B4009E, $61D6D6, $F2F2F2);

function PixRgb(const P: TBGRAPixel): Cardinal;
begin
  Result := (Cardinal(P.red) shl 16) or (Cardinal(P.green) shl 8) or P.blue;
end;

function CountIn(B: TBGRABitmap; const R: TRect; ARgb: Cardinal): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := Max(0, R.Top) to Min(B.Height, R.Bottom) - 1 do
    for x := Max(0, R.Left) to Min(B.Width, R.Right) - 1 do
      if PixRgb(B.GetPixel(x, y)) = ARgb then Inc(Result);
end;

function CellIs(B: TBGRABitmap; V: TTyTerminalViewProbe; ACol, ARow: Integer; ARgb: Cardinal): Boolean;
var
  r: TRect;
begin
  r := V.CellRect(ACol, ARow);
  Result := CountIn(B, r, ARgb) = (r.Right - r.Left) * (r.Bottom - r.Top);
end;

function UnderlineAt(B: TBGRABitmap; V: TTyTerminalViewProbe; ACol, ARow: Integer): Cardinal;
var
  r: TRect;
begin
  r := V.CellRect(ACol, ARow);
  Result := PixRgb(B.GetPixel((r.Left + r.Right) div 2, r.Top + V.CellMetrics.UnderlineY));
end;

function Mix(AColor, ABase: Cardinal; AAlpha: Integer): Cardinal;
begin
  Result := ((((AColor shr 16) and $FF) * Cardinal(AAlpha) + ((ABase shr 16) and $FF) * Cardinal(255 - AAlpha) + 127) div 255) shl 16
    or ((((AColor shr 8) and $FF) * Cardinal(AAlpha) + ((ABase shr 8) and $FF) * Cardinal(255 - AAlpha) + 127) div 255) shl 8
    or (((AColor and $FF) * Cardinal(AAlpha) + (ABase and $FF) * Cardinal(255 - AAlpha) + 127) div 255);
end;

function TTyTerminalViewSchemeTests.Clock: Double;
begin
  Result := FClockMs;
end;

procedure TTyTerminalViewSchemeTests.Load(AScheme: TTyTerminalColorScheme; const AName: string);
begin
  AScheme.LoadFromText(TyTermWtFixtureText, AName);
end;

function TTyTerminalViewSchemeTests.Res(AIndex: Integer): string;
begin
  Result := Hex6(F.View.Core.ResolveColor(AIndex));
end;

procedure TTyTerminalViewSchemeTests.Settle;
begin
  Pump;
  F.ClearRecords;
end;

procedure TTyTerminalViewSchemeTests.TestFollowingTheThemeIgnoresTheScheme;
var
  before: array[0..258] of Cardinal;
  i: Integer;
begin
  for i := 0 to 258 do
    before[i] := F.View.Core.ResolveColor(i);
  Load(F.View.ColorScheme, 'Campbell');
  Settle;
  AssertTrue('the default source is the theme', F.View.ColorSource = tsrcTheme);
  AssertNull('no scheme in use', TSchemeAccess(F.View).ActiveColorScheme);
  for i := 0 to 258 do
    AssertEquals('colour ' + IntToStr(i) + ' is the theme''s', Hex6(before[i]), Res(i));
  { the same scheme, switched on, does change them (the assertion above can fail) }
  F.View.ColorSource := tsrcScheme;
  AssertEquals('switched on: the scheme''s ground', Hex6($0C0C0C), Res(257));
  AssertTrue('and it differs from the theme''s', before[257] <> $0C0C0C);
end;

procedure TTyTerminalViewSchemeTests.TestSlotsComeFromTheScheme;
var
  i: Integer;
begin
  Load(F.View.ColorScheme, 'Campbell');
  F.View.ColorSource := tsrcScheme;
  AssertSame('the scheme in use', F.View.ColorScheme, TSchemeAccess(F.View).ActiveColorScheme);
  AssertEquals('1 red', Hex6($C50F1F), Res(1));
  AssertEquals('5 purple', Hex6($881798), Res(5));
  AssertEquals('256 foreground', Hex6($CCCCCC), Res(256));
  AssertEquals('257 background', Hex6($0C0C0C), Res(257));
  AssertEquals('258 cursor', Hex6($FFFFFF), Res(258));
  AssertEquals('100 is the formula', Hex6(TyTermDefaultPaletteColor(100)), Res(100));
  for i := 0 to 15 do
    AssertEquals('ANSI ' + IntToStr(i), Hex6(CampbellRgb[i]), Res(i));
end;

procedure TTyTerminalViewSchemeTests.TestUnsetSlotsFollowTheTheme;
begin
  AssertTrue('the fixture''s cursor is not its foreground',
    F.ThemeBg('TyTerminalCursor') <> F.ThemeFg('TyTerminal'));
  F.View.ColorSource := tsrcScheme;
  { an empty scheme draws as the theme does, cursor included }
  AssertNull('an empty scheme is not in use', TSchemeAccess(F.View).ActiveColorScheme);
  AssertEquals('empty: the theme''s cursor', Hex6(F.ThemeBg('TyTerminalCursor')), Res(258));
  F.View.ColorScheme.Red := TColor($1F0FC5);
  AssertEquals('red from the scheme', Hex6($C50F1F), Res(1));
  AssertEquals('green from the theme', Hex6(F.Ansi(2)), Res(2));
  AssertEquals('foreground from the theme', Hex6(F.ThemeFg('TyTerminal')), Res(256));
  AssertEquals('background from the theme', Hex6(F.ThemeBg('TyTerminal')), Res(257));
  AssertEquals('an unset cursor is the foreground in effect', Hex6(F.ThemeFg('TyTerminal')), Res(258));
  F.View.ColorScheme.Foreground := TColor($3D2E1F);
  AssertEquals('the scheme''s foreground', Hex6($1F2E3D), Res(256));
  AssertEquals('and the cursor follows it', Hex6($1F2E3D), Res(258));
end;

procedure TTyTerminalViewSchemeTests.TestTheCursorInkComesFromTheScheme;
var
  b: TBGRABitmap;
  r: TRect;
  n: Integer;
begin
  F.View.ColorScheme.Background := TColor($563412);
  F.View.ColorScheme.CursorColor := TColor($D0E0F0);
  F.View.ColorScheme.CursorText := TColor($3D2E1F);
  F.View.ColorSource := tsrcScheme;
  Settle;
  F.View.Enter;
  F.View.WriteSync(#$E2#$96#$88#27'[D');
  b := F.Render;
  try
    r := F.View.CellRect(0, 0);
    n := CountIn(b, r, $1F2E3D);
    AssertTrue(Format('the block under the cursor is drawn in the scheme''s cursor text (%d px)', [n]),
      n * 2 > (r.Right - r.Left) * (r.Bottom - r.Top));
  finally
    b.Free;
  end;
  F.View.ColorScheme.CursorText := clNone;
  b := F.Render;
  try
    r := F.View.CellRect(0, 0);
    n := CountIn(b, r, $123456);
    AssertTrue(Format('unset: drawn in the scheme''s ground (%d px)', [n]),
      n * 2 > (r.Right - r.Left) * (r.Bottom - r.Top));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestTheSelectionIsThreeTenths;
var
  b: TBGRABitmap;
  c: Integer;
  white, red: Cardinal;
begin
  F.View.ColorScheme.Background := TColor($000000);
  F.View.ColorScheme.SelectionBackground := TColor($FFFFFF);
  F.View.ColorSource := tsrcScheme;
  Settle;
  white := TyTermBlendOver($000000, BGRA(255, 255, 255, $4D));
  red := TyTermBlendOver($000000, BGRA(255, 0, 0, $4D));
  AssertEquals('0.3 of white over black', Hex6($4D4D4D), Hex6(white));
  F.View.WriteSync(#27'[?25l'#27'[5;1H');
  F.View.Select(2, F.View.Core.Buffer.YBase, 4);
  b := F.Render;
  try
    for c := 2 to 5 do
      AssertTrue(Format('unfocused cell %d: the focused colour, as nothing else is set', [c]),
        CellIs(b, F.View, c, 0, white));
    AssertTrue('cell 1: the ground', CellIs(b, F.View, 1, 0, $000000));
  finally
    b.Free;
  end;
  F.View.Enter;
  b := F.Render;
  try
    AssertTrue('focused: 0.3 of white', CellIs(b, F.View, 3, 0, white));
  finally
    b.Free;
  end;
  F.View.ColorScheme.SelectionInactiveBackground := clRed;
  F.View.Leave;
  b := F.Render;
  try
    AssertTrue('unfocused, set: 0.3 of red', CellIs(b, F.View, 3, 0, red));
  finally
    b.Free;
  end;
  F.View.Enter;
  b := F.Render;
  try
    AssertTrue('focused again: still white', CellIs(b, F.View, 3, 0, white));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestProgramColoursBeatTheScheme;
var
  b: TBGRABitmap;
begin
  Load(F.View.ColorScheme, 'Campbell');
  F.View.ColorSource := tsrcScheme;
  Settle;
  F.View.WriteSync(#27']11;#f0f0f0'#7);
  AssertEquals('the program''s ground', Hex6($F0F0F0), Res(257));
  b := F.Render;
  try
    AssertEquals('the padding is the program''s ground', Hex6($F0F0F0), Hex6(PixRgb(b.GetPixel(0, 0))));
  finally
    b.Free;
  end;
  F.View.WriteSync(#27']111'#7);
  AssertEquals('reset: the scheme''s ground, not the theme''s', Hex6($0C0C0C), Res(257));
  b := F.Render;
  try
    AssertEquals('the padding is the scheme''s ground', Hex6($0C0C0C), Hex6(PixRgb(b.GetPixel(0, 0))));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestModeQueriesAnswerTheGroundInEffect;

  function Ask: string;
  begin
    F.ClearRecords;
    F.View.WriteSync(#27'[?996n');
    Result := TyTermHex(F.Data);
  end;

begin
  F.Ctl.StyleOverride := TyTermFixtureCss + LightCss;
  try
    Load(F.View.ColorScheme, 'Campbell');
    Settle;
    AssertEquals('a light theme, following it: light', TyTermHex(#27'[?997;2n'), Ask);
    F.View.ColorSource := tsrcScheme;
    Settle;
    AssertEquals('the same theme, Campbell: dark', TyTermHex(#27'[?997;1n'), Ask);
    F.View.WriteSync(#27']11;#ffffff'#7);
    AssertEquals('the program''s white ground: light', TyTermHex(#27'[?997;2n'), Ask);
  finally
    F.Ctl.StyleOverride := TyTermFixtureCss;
  end;
end;

procedure TTyTerminalViewSchemeTests.Step(const AWhat: string; AWant: Integer);
begin
  AssertEquals(AWhat + ': nothing sent from inside the change', '', TyTermHex(F.Data));
  AssertTrue(AWhat + ': a notification is queued', TSchemeAccess(F.View).NotifyQueued);
  Pump;
  AssertEquals(AWhat + ': reports (' + TyTermHex(F.Data) + ')', AWant, Reports);
  F.ClearRecords;
end;

{ 改的是没用到的方案:不排通知、不报、整窗一次都不失效(数控件的 Invalidate) }
procedure TTyTerminalViewSchemeTests.Quiet(const AWhat: string);
var
  inv: Integer;
begin
  AssertEquals(AWhat + ': nothing sent', '', TyTermHex(F.Data));
  AssertFalse(AWhat + ': no notification queued', TSchemeAccess(F.View).NotifyQueued);
  inv := F.View.Invalidations;
  Pump;
  AssertEquals(AWhat + ': no report (' + TyTermHex(F.Data) + ')', 0, Reports);
  AssertEquals(AWhat + ': the window is not invalidated', inv, F.View.Invalidations);
  F.ClearRecords;
end;

procedure TTyTerminalViewSchemeTests.TestNotificationsComeOncePerChange;
var
  b: TBGRABitmap;
  i, inv: Integer;
begin
  F.View.WriteSync(#27'[?2031h');
  Settle;
  Load(F.View.ColorScheme, 'Campbell');
  Quiet('a scheme loaded while following the theme');
  F.View.ColorSource := tsrcScheme;
  Step('theme -> scheme', 1);
  F.View.WriteSync(#27']4;1;#123456'#7);
  AssertEquals('the program''s colour is in', Hex6($123456), Res(1));
  F.ClearRecords;
  F.View.ColorScheme.Green := TColor($010203);
  Step('one colour', 1);
  AssertEquals('the program''s colour went with it', Hex6($C50F1F), Res(1));
  F.View.ColorScheme.BeginUpdate;
  F.View.ColorScheme.Red := TColor($000011);
  F.View.ColorScheme.Green := TColor($000022);
  F.View.ColorScheme.Yellow := TColor($000033);
  F.View.ColorScheme.Blue := TColor($000044);
  F.View.ColorScheme.Purple := TColor($000055);
  F.View.ColorScheme.EndUpdate;
  Step('five colours in one update', 1);
  Load(F.View.ColorScheme, 'Tango Dark');
  Step('another scheme loaded', 1);
  Load(F.View.ColorScheme, 'Campbell');
  Step('back to Campbell', 1);
  { not pumped yet: the palette, and 996, are the new scheme's already }
  Load(F.View.ColorScheme, 'Tango Light');
  AssertEquals('not pumped: the palette is already Tango Light''s', Hex6($FFFFFF), Res(257));
  AssertEquals('not pumped: 996 answers light', TyTermHex(#27'[?997;2n'), TyTermHex(Pumpless996));
  Step('a light scheme', 1);
  Load(F.View.ColorScheme, 'Campbell');
  Step('Campbell again', 1);
  { a dark theme, Campbell, not paired; in one go: a light scheme in use, a dark one beside
    it, pairing on (the dark theme then takes the dark one) -- two palette changes, one report }
  Load(F.View.ColorScheme, 'Tango Light');
  Load(F.View.DarkColorScheme, 'Tango Dark');
  F.View.ColorSchemePaired := True;
  AssertEquals('not pumped: the dark side already', Hex6($000000), Res(257));
  Step('three settings in one go', 1);
  { the side in use changed: reported, and the window repainted }
  inv := F.View.Invalidations;
  F.View.DarkColorScheme.Red := TColor($0102CD);
  Step('the side in use changed', 1);
  AssertTrue('the side in use changed: the window is invalidated', F.View.Invalidations > inv);
  { a colour the palette does not use: the light side while the theme is dark }
  b := F.Render;
  b.Free;
  F.View.ColorScheme.Red := TColor($0000AA);
  Quiet('the unused side changed');
  b := F.Render;
  b.Free;
  AssertEquals('and nothing repainted', 0, F.View.PaintedLast);
  { following the theme: nothing in a scheme is used }
  F.View.ColorSource := tsrcTheme;
  Step('scheme -> theme', 1);
  b := F.Render;
  b.Free;
  F.View.ColorScheme.Red := TColor($0000BB);
  Quiet('a scheme colour while following the theme');
  b := F.Render;
  b.Free;
  AssertEquals('and nothing repainted', 0, F.View.PaintedLast);
  { a scheme with every colour the theme has: switching to it changes no colour }
  F.View.ColorSchemePaired := False;
  Step('pairing off while following the theme', 0);
  F.View.ColorScheme.BeginUpdate;
  F.View.ColorScheme.Clear;
  for i := 0 to 15 do
    F.View.ColorScheme.Colors[TTyTerminalSchemeSlot(i)] := TyTermRgbToSchemeColor(F.Ansi(i));
  F.View.ColorScheme.Foreground := TyTermRgbToSchemeColor(F.ThemeFg('TyTerminal'));
  F.View.ColorScheme.Background := TyTermRgbToSchemeColor(F.ThemeBg('TyTerminal'));
  F.View.ColorScheme.CursorColor := TyTermRgbToSchemeColor(F.ThemeBg('TyTerminalCursor'));
  F.View.ColorScheme.CursorText := TyTermRgbToSchemeColor(F.ThemeFg('TyTerminalCursor'));
  F.View.ColorScheme.EndUpdate;
  Quiet('the theme''s colours loaded while following the theme');
  F.View.ColorSource := tsrcScheme;
  Step('switched to a scheme that is the theme', 0);
  { not paired: DarkColorScheme is not used }
  F.View.DarkColorScheme.Red := TColor($0000DD);
  Quiet('the dark scheme while not paired');
end;

function TTyTerminalViewSchemeTests.Pumpless996: RawByteString;
var
  was: RawByteString;
begin
  was := F.Data;
  F.View.WriteSync(#27'[?996n');
  Result := Copy(F.Data, Length(was) + 1, MaxInt);
  F.Data := was;
  F.DataEvents := 0;
end;

procedure TTyTerminalViewSchemeTests.TestPairingFollowsTheThemeGround;
begin
  F.View.WriteSync(#27'[?2031h');
  Load(F.View.ColorScheme, 'Tango Light');
  Load(F.View.DarkColorScheme, 'Campbell');
  F.View.ColorSchemePaired := True;
  F.View.ColorSource := tsrcScheme;
  F.Ctl.StyleOverride := TyTermFixtureCss + LightCss;
  try
    Settle;
    AssertFalse('a light theme', TSchemeAccess(F.View).ThemeGroundIsDark);
    AssertSame('light: ColorScheme', F.View.ColorScheme, TSchemeAccess(F.View).ActiveColorScheme);
    AssertEquals('light: Tango Light''s ground', Hex6($FFFFFF), Res(257));
    F.Ctl.StyleOverride := TyTermFixtureCss;
    Pump;
    AssertTrue('a dark theme', TSchemeAccess(F.View).ThemeGroundIsDark);
    AssertSame('dark: DarkColorScheme', F.View.DarkColorScheme, TSchemeAccess(F.View).ActiveColorScheme);
    AssertEquals('dark: Campbell''s ground', Hex6($0C0C0C), Res(257));
    AssertEquals('one report, dark: ' + TyTermHex(F.Data), TyTermHex(#27'[?997;1n'), TyTermHex(F.Data));
    F.ClearRecords;
    F.Ctl.StyleOverride := TyTermFixtureCss + LightCss;
    Pump;
    AssertEquals('one report, light: ' + TyTermHex(F.Data), TyTermHex(#27'[?997;2n'), TyTermHex(F.Data));
    F.ClearRecords;
    F.View.ColorSchemePaired := False;
    Settle;
    F.Ctl.StyleOverride := TyTermFixtureCss;
    Pump;
    AssertEquals('not paired: a mode switch changes no colour', '', TyTermHex(F.Data));
    AssertSame('not paired: ColorScheme in both', F.View.ColorScheme, TSchemeAccess(F.View).ActiveColorScheme);
  finally
    F.Ctl.StyleOverride := TyTermFixtureCss;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestTheDarkSideIsWhatOnCalls;

  procedure Ground(const AColor: string);
  var
    st: TTyStyleSet;
    white: Boolean;
  begin
    F.Ctl.StyleOverride := TyTermFixtureCss + 'TyTerminal { background: ' + AColor + '; }'#10;
    st := F.Ctl.Model.ResolveOverride('color: on(' + AColor + ', #000000, #ffffff)');
    AssertTrue('on() answers for ' + AColor, tpTextColor in st.Present);
    white := (Cardinal(st.TextColor) and $FFFFFF) = $FFFFFF;
    AssertEquals(AColor + ': dark exactly when on() picks the ink for a dark ground', white,
      TSchemeAccess(F.View).ThemeGroundIsDark);
  end;

var
  r, g, b, found: Integer;
  exact: string;
begin
  try
    Ground('#7f7f7f');
    Ground('#808080');
    AssertTrue('the two greys fall on either side',
      TyLuminance(TyRGB($7F, $7F, $7F)) < 0.5);
    AssertTrue('the two greys fall on either side',
      TyLuminance(TyRGB($80, $80, $80)) > 0.5);
    { a ground whose Rec.601 luma is exactly 0.5 in Single: on() calls it dark }
    found := 0;
    exact := '';
    for r := 0 to 255 do
      for g := 0 to 255 do
      begin
        if (127500 - 299 * r - 587 * g) mod 114 <> 0 then Continue;
        b := (127500 - 299 * r - 587 * g) div 114;
        if (b < 0) or (b > 255) then Continue;
        if TyLuminance(TyRGB(r, g, b)) = 0.5 then
        begin
          Inc(found);
          if exact = '' then exact := Format('#%.2x%.2x%.2x', [r, g, b]);
        end;
      end;
    { V11b (> written as >=) is caught only by such a ground: there must be one, or the case
      below would quietly test nothing }
    AssertTrue('a ground whose luma is exactly 0.5 exists', found > 0);
    Ground(exact);
    AssertTrue('exactly 0.5 is dark (' + exact + ')', TSchemeAccess(F.View).ThemeGroundIsDark);
    { a single-mode dark skin: no mode name, the ground says it }
    F.Ctl.StyleOverride := 'TyTerminal { background: #1e1e1e; }'#10;
    AssertTrue('a single-mode dark skin is dark', TSchemeAccess(F.View).ThemeGroundIsDark);
  finally
    F.Ctl.StyleOverride := TyTermFixtureCss;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestContrastWorksOnTheScheme;
var
  b: TBGRABitmap;
  i, pick: Integer;
  ground, colour, want: Cardinal;
  ratio: Double;
begin
  Load(F.View.ColorScheme, 'Solarized Light');
  F.View.ColorSource := tsrcScheme;
  Settle;
  ground := $FDF6E3;
  { Solarized Light's first colour under 4.5:1 on its own ground, found here rather than
    written in: 1, red #DC322F, about 4.29:1 (WCAG, computed by hand beside the test) }
  pick := -1;
  ratio := 0;
  for i := 1 to 15 do
  begin
    F.View.ColorScheme.SlotRgb(TTyTerminalSchemeSlot(i), colour);
    ratio := TyTermContrastRatio(TyTermRelativeLuminance(ground), TyTermRelativeLuminance(colour));
    if (ratio < 4.5) and TyTermEnsureContrastRatio(ground, colour, 4.5, want) then
    begin
      pick := i;
      Break;
    end;
  end;
  AssertTrue('a colour to lift', pick >= 0);
  if pick < 8 then
    F.View.WriteSync(#27'[?25l'#27'[4;' + IntToStr(30 + pick) + 'mAb' + #27'[0m')
  else
    F.View.WriteSync(#27'[?25l'#27'[4;' + IntToStr(82 + pick) + 'mAb' + #27'[0m');
  b := F.Render;
  try
    AssertEquals(Format('at 1: colour %d as it is (%.2f:1)', [pick, ratio]), Hex6(colour), Hex6(UnderlineAt(b, F.View, 0, 0)));
    AssertEquals('the ground is the scheme''s', Hex6(ground), Hex6(PixRgb(b.GetPixel(0, 0))));
  finally
    b.Free;
  end;
  F.View.MinimumContrastRatio := 4.5;
  b := F.Render;
  try
    AssertEquals(Format('at 4.5: lifted against the scheme''s ground (colour %d)', [pick]), Hex6(want),
      Hex6(UnderlineAt(b, F.View, 0, 0)));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestDisabledFadesTheScheme;
var
  b: TBGRABitmap;
  st: TTyStyleSet;
  a: Integer;
  pc: TTyColor;
  base: Cardinal;
begin
  F.Ctl.StyleOverride := TyTermFixtureCss + 'TyTerminal:disabled { opacity: 0.4; }'#10;
  try
    Load(F.View.ColorScheme, 'Campbell');
    F.View.ColorSource := tsrcScheme;
    Settle;
    st := F.Ctl.Model.ResolveStyle('TyTerminal', '', [tysDisabled]);
    a := EnsureRange(Round(st.Opacity * 255), 0, 255);
    AssertTrue('a real fade', a < 255);
    AssertTrue('the parent has a colour', TyResolveParentBg(F.View, pc));
    base := Cardinal(pc) and $FFFFFF;
    F.View.Enabled := False;
    b := F.Render;
    try
      AssertEquals('the scheme''s ground faded toward the parent', Hex6(Mix($0C0C0C, base, a)),
        Hex6(PixRgb(b.GetPixel(0, 0))));
    finally
      b.Free;
    end;
    AssertEquals('the program still gets the scheme''s colour', Hex6($0C0C0C), Res(257));
  finally
    F.View.Enabled := True;
    F.Ctl.StyleOverride := TyTermFixtureCss;
  end;
end;

procedure TTyTerminalViewSchemeTests.TestMarkedTextTakesTheSchemesGround;
var
  b: TBGRABitmap;
  r: TRect;
begin
  F.View.WriteSync(#27'[?25l');
  F.View.ImeBegin;
  try
    F.View.ImeReplaceText(0, 0, 'zh');
    b := F.Render;
    try
      r := F.View.CellRect(0, 0);
      AssertEquals('following the theme: TyTerminalPreedit''s ground', Hex6($203040),
        Hex6(PixRgb(b.GetPixel(r.Left, r.Top))));
    finally
      b.Free;
    end;
    Load(F.View.ColorScheme, 'Campbell');
    F.View.ColorSource := tsrcScheme;
    b := F.Render;
    try
      r := F.View.CellRect(0, 0);
      AssertEquals('a scheme: its ground', Hex6($0C0C0C), Hex6(PixRgb(b.GetPixel(r.Left, r.Top))));
      AssertEquals('the underline is still the theme''s', Hex6($00FF00),
        Hex6(PixRgb(b.GetPixel(r.Left, r.Bottom - 1))));
    finally
      b.Free;
    end;
  finally
    F.View.ImeEnd;
  end;
end;

{ A system colour is stored as itself (clWindow), so after the system's colours change,
  setting it again is no change at all; ColorScheme.Changed is the way to have the terminal
  take the colours again. }
procedure TTyTerminalViewSchemeTests.TestChangedRefreshesASystemColour;
var
  rev: Cardinal;
  inv: Integer;
  rgb: Cardinal;
begin
  F.View.ColorScheme.Background := clWindow;
  F.View.ColorSource := tsrcScheme;
  Settle;
  AssertTrue('clWindow resolves', TyTermSchemeColorRgb(clWindow, rgb));
  AssertEquals('the ground is the system''s window colour', Hex6(rgb), Res(257));
  rev := F.View.ColorScheme.Revision;
  F.View.ColorScheme.Background := clWindow;
  AssertEquals('setting the same system colour again changes nothing', rev, F.View.ColorScheme.Revision);
  AssertFalse('and queues nothing', TSchemeAccess(F.View).NotifyQueued);
  inv := F.View.Invalidations;
  F.View.ColorScheme.Changed;
  AssertEquals('Changed: a new revision', rev + 1, F.View.ColorScheme.Revision);
  AssertTrue('Changed: a notification is queued', TSchemeAccess(F.View).NotifyQueued);
  Pump;
  AssertTrue('Changed: the window is invalidated', F.View.Invalidations > inv);
  AssertEquals('the ground is still the window colour', Hex6(rgb), Res(257));
end;

initialization
  RegisterTest(TTyTerminalViewSchemeTests);
end.
