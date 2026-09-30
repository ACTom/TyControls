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
  tyControls.Types, tyControls.Css.Values, tyControls.StyleModel, tyControls.Controller,
  tyControls.Terminal.Core, tyControls.Terminal.Render, tyControls.Terminal.ColorScheme,
  tyControls.Terminal,
  test.terminal.keyboard, test.terminal.view, test.terminal.colorscheme;

type
  TTyTerminalViewSchemeTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    procedure Pump;
    function Reports: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Task 5:属性、流式化、加载 }
    procedure TestTheSchemesStream;
    procedure TestLoadingNotifiesNothing;
  end;

implementation

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
end;

procedure TTyTerminalViewSchemeTests.TearDown;
begin
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
  text: string;
  s: TTyTerminalSchemeSlot;
  inp: TStringStream;
  bin: TMemoryStream;
  b: TBGRABitmap;
begin
  text := 'object View: TTyTerminalViewProbe'#10'  ColorSource = tsrcScheme'#10
    + '  ColorScheme.Name = ''Campbell'''#10;
  for s := Low(s) to High(s) do
    text := text + '  ColorScheme.' + SlotProps[s] + ' = ' + IntToStr($100000 + Ord(s) * $0A0B03) + #10;
  text := text + 'end'#10;
  inp := TStringStream.Create(text);
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
  AssertEquals('loading queued no notification', 0, F.View.SchemeNotifyRequests);
  Pump;
  AssertEquals('nothing sent after loading', '', TyTermHex(F.Data));
  AssertFalse('nothing queued', F.View.NotifyQueued);
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

initialization
  RegisterTest(TTyTerminalViewSchemeTests);
end.
