unit test.terminal.view;
{$mode objfpc}{$H+}
{ TTyTerminalView:属性、Core 事件的接线、调度、焦点、主题取色、网格。

  这里还放着三个测试单元共用的东西(interface 段导出):探针类 TTyTerminalViewProbe
  (把受保护的方法开出来、数 ScheduleSlice / InvalidateRows、剪贴板打桩)和夹具
  TTyTermViewFixture(真父窗体、自建 controller、钉死 TyFallbackFontName、记录事件)。
  夹具的颜色写在 controller 的 StyleOverride 里(一份 tycss 补丁,跨明暗、跨主题保留),
  断言都从 controller 现解析,不写死十六进制。 }

interface

uses
  Classes, SysUtils, Types, Math, TypInfo, Forms, Controls, Graphics, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.StyleModel,
  tyControls.ScrollBar, tyControls.Unicode.Width, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  tyControls.Terminal.Render, tyControls.Terminal, test.terminal.keyboard;

type
  TTyTerminalViewProbe = class(TTyTerminalView)
  public
    SliceCalls: Integer;
    PassSlices: Boolean;
    Invalidated: array of TPoint;
    ClipText: string;
    ClipReads, ClipWrites: Integer;
    ClipWritten: string;
    procedure ScheduleSlice; override;
    procedure InvalidateRows(AFirst, ALast: Integer); override;
    function ReadClipboardText: string; override;
    procedure WriteClipboardText(const S: string); override;
    procedure ClearInvalidated;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Tick(ANowMs: Double);
    procedure FireSyncTimer;
    procedure PressKey(var Key: Word; Shift: TShiftState);
    procedure TypeChar(var AChar: TUTF8Char);
    function Wheel(Shift: TShiftState; ADelta: Integer; APos: TPoint): Boolean;
    procedure Enter;
    procedure Leave;
    procedure SetPlatform(AMac, AWindows: Boolean);
    function IsMacFlag: Boolean;
    function IsWindowsFlag: Boolean;
    function PaintedRows: Integer;
    function Cache: TTyTermGlyphCache;
    function CellMetrics: TTyTermCellMetrics;
    function Spec: TTyTermFontSpec;
    function BlinkOn: Boolean;
    function SyncOn: Boolean;
    function HeldRows: TPoint;
    function Bar: TTyScrollBar;
    function Focus: Boolean;
    procedure MakeDesigning;
    function FrameHostStyle: TTyStyleSet;
    function Embeds(ABar: TTyScrollBar): Boolean;
    procedure ImeBegin;
    procedure ImeEnd;
    procedure ImeReplaceText(AStart, ALen: Integer; const AText: string);
  end;

  { 一个测试一个;SetUp 里建,TearDown 里 Free。 }
  TTyTermViewFixture = class
  private
    FSavedFallback: string;
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnGrid(Sender: TObject; ACols, ARows: Integer);
    procedure OnTitle(Sender: TObject; const AText: string);
    procedure OnBell(Sender: TObject);
    procedure OnOsc(Sender: TObject; AIdent: Integer; const AData: string);
  public
    Form: TForm;
    Ctl: TTyStyleController;
    View: TTyTerminalViewProbe;
    Data: RawByteString;
    DataEvents: Integer;
    Grids: array of TPoint;
    Titles: TStringList;
    Bells: Integer;
    OscIdents: array of Integer;
    OscData: TStringList;
    constructor Create(AParented: Boolean = True);
    destructor Destroy; override;
    procedure ClearRecords;
    { 客户区恰好 ACols x ARows 格(外加 AExtraW / AExtraH 像素) }
    procedure SizeTo(ACols, ARows: Integer; AExtraW: Integer = 0; AExtraH: Integer = 0);
    { 画一帧到哨兵底色(品红)的位图上,读回 BGRA;调用者释放。APPI 0 = 控件字体的 PPI }
    function Render(APPI: Integer = 0): TBGRABitmap;
    { 内边距(夹具主题 2px)按控件字体的 PPI 缩放 }
    function Pad: Integer;
    { 从 controller 现解析的颜色,$RRGGBB }
    function ThemeFg(const ATypeKey: string): Cardinal;
    function ThemeBg(const ATypeKey: string): Cardinal;
    function Ansi(AIndex: Integer): Cardinal;
    function RowText(ARow: Integer): string;
  end;

  TTyTerminalViewTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    FDone: array of PtrInt;
    FClockMs: Double;
    procedure WriteDone(Sender: TObject; ATag: PtrInt);
    function Clock: Double;
    procedure ResizeFromTitle(Sender: TObject; const AText: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPublishedDefaultsMatchTheConstructor;
    procedure TestSettersReachTheCore;
    procedure TestStreamedValuesSurviveLoading;
    procedure TestCoreRepliesComeOutOfOnData;
    procedure TestTitleBellAndOsc;
    procedure TestANewControlIsUnfocusedToTheCore;
    procedure TestColourQueriesAnswerFromTheTheme;
    procedure TestAThemeChangeDropsOverridesAndReports;
    procedure TestSwappingControllersRebuildsThePalette;
    procedure TestWindowReportsInDevicePixels;
    procedure TestTheGridFollowsTheClientArea;
    procedure TestTheFirstLayoutIsAnnounced;
    procedure TestDecColmResizesTheGrid;
    procedure TestSizeForGridRoundTrips;
    procedure TestCellAtAndCellRect;
    procedure TestAWriteAsksForOneSlice;
    procedure TestSlicesRunThroughTheMessageQueue;
    procedure TestAFreedControlLeavesNoSliceBehind;
    procedure TestSyncOutputHoldsRowsBack;
    procedure TestSyncOutputTimesOut;
    procedure TestTheSyncTimerStartsAtTheFirstHeldRow;
    procedure TestResizingFromACoreEventIsSafe;
    procedure TestDesignTimePreview;
  end;

const
  { 夹具的主题补丁:每个键一个一眼认得出的颜色 }
  TyTermFixtureCss =
    'TyTerminal { background: #102030; color: #d0e0f0; padding: 2px; }'#10 +
    'TyTerminalCursor { background: #ff8000; color: #001020; }'#10 +
    'TyTerminalPreedit { background: #203040; color: #f0f0f0; border-color: #00ff00; }'#10 +
    'TyTerminalAnsi0 { color: #010203; }'#10 +
    'TyTerminalAnsi1 { color: #c00001; }'#10 +
    'TyTerminalAnsi2 { color: #01c002; }'#10 +
    'TyTerminalAnsi3 { color: #c0c003; }'#10 +
    'TyTerminalAnsi4 { color: #0304c0; }'#10 +
    'TyTerminalAnsi5 { color: #c005c0; }'#10 +
    'TyTerminalAnsi6 { color: #06c0c0; }'#10 +
    'TyTerminalAnsi7 { color: #c7c7c7; }'#10 +
    'TyTerminalAnsi8 { color: #808008; }'#10 +
    'TyTerminalAnsi9 { color: #ff0909; }'#10 +
    'TyTerminalAnsi10 { color: #0aff0a; }'#10 +
    'TyTerminalAnsi11 { color: #ffff0b; }'#10 +
    'TyTerminalAnsi12 { color: #0c0cff; }'#10 +
    'TyTerminalAnsi13 { color: #ff0dff; }'#10 +
    'TyTerminalAnsi14 { color: #0effff; }'#10 +
    'TyTerminalAnsi15 { color: #fffffe; }'#10;

function TyTermNeedWidgetSet: Boolean;

implementation

var
  WidgetSetUp: Boolean = False;

function TyTermNeedWidgetSet: Boolean;
begin
  { 控制台跑的测试直到 widgetset 起来才注册窗口类(test.focus.tabstop 同一个惰性开关) }
  if not WidgetSetUp then
  begin
    Forms.Application.Initialize;
    WidgetSetUp := True;
  end;
  Result := True;
end;

{ ---- 探针 --------------------------------------------------------------------------- }

procedure TTyTerminalViewProbe.ScheduleSlice;
begin
  Inc(SliceCalls);
  if PassSlices then inherited ScheduleSlice;
end;

procedure TTyTerminalViewProbe.InvalidateRows(AFirst, ALast: Integer);
begin
  SetLength(Invalidated, Length(Invalidated) + 1);
  Invalidated[High(Invalidated)] := Point(AFirst, ALast);
  inherited InvalidateRows(AFirst, ALast);
end;

function TTyTerminalViewProbe.ReadClipboardText: string;
begin
  Inc(ClipReads);
  Result := ClipText;
end;

procedure TTyTerminalViewProbe.WriteClipboardText(const S: string);
begin
  Inc(ClipWrites);
  ClipWritten := S;
end;

procedure TTyTerminalViewProbe.ClearInvalidated;
begin
  Invalidated := nil;
end;

procedure TTyTerminalViewProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyTerminalViewProbe.Tick(ANowMs: Double);
begin
  BlinkTick(ANowMs);
end;

procedure TTyTerminalViewProbe.FireSyncTimer;
begin
  SyncTimerFired(nil);
end;

procedure TTyTerminalViewProbe.PressKey(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TTyTerminalViewProbe.TypeChar(var AChar: TUTF8Char);
begin
  UTF8KeyPress(AChar);
end;

function TTyTerminalViewProbe.Wheel(Shift: TShiftState; ADelta: Integer; APos: TPoint): Boolean;
begin
  Result := DoMouseWheel(Shift, ADelta, APos);
end;

procedure TTyTerminalViewProbe.Enter;
begin
  DoEnter;
end;

procedure TTyTerminalViewProbe.Leave;
begin
  DoExit;
end;

procedure TTyTerminalViewProbe.SetPlatform(AMac, AWindows: Boolean);
begin
  FIsMac := AMac;
  FIsWindows := AWindows;
end;

function TTyTerminalViewProbe.IsMacFlag: Boolean;
begin
  Result := FIsMac;
end;

function TTyTerminalViewProbe.IsWindowsFlag: Boolean;
begin
  Result := FIsWindows;
end;

function TTyTerminalViewProbe.PaintedRows: Integer;
begin
  Result := RowsPainted;
end;

function TTyTerminalViewProbe.Cache: TTyTermGlyphCache;
begin
  Result := GlyphCache;
end;

function TTyTerminalViewProbe.CellMetrics: TTyTermCellMetrics;
begin
  Result := Metrics;
end;

function TTyTerminalViewProbe.Spec: TTyTermFontSpec;
begin
  Result := FontSpec;
end;

function TTyTerminalViewProbe.BlinkOn: Boolean;
begin
  Result := BlinkTimerActive;
end;

function TTyTerminalViewProbe.SyncOn: Boolean;
begin
  Result := SyncTimerActive;
end;

function TTyTerminalViewProbe.HeldRows: TPoint;
begin
  Result := PendingSyncRows;
end;

function TTyTerminalViewProbe.Bar: TTyScrollBar;
begin
  Result := ScrollBar;
end;

function TTyTerminalViewProbe.Focus: Boolean;
begin
  Result := HasFocusFlag;
end;

procedure TTyTerminalViewProbe.MakeDesigning;
begin
  SetDesigning(True, True);
end;

function TTyTerminalViewProbe.FrameHostStyle: TTyStyleSet;
begin
  Result := ScrollBarFrameStyle;
end;

function TTyTerminalViewProbe.Embeds(ABar: TTyScrollBar): Boolean;
begin
  Result := EmbedsScrollBar(ABar);
end;

procedure TTyTerminalViewProbe.ImeBegin;
begin
  ImeSessionBegin;
end;

procedure TTyTerminalViewProbe.ImeEnd;
begin
  ImeSessionEnd;
end;

procedure TTyTerminalViewProbe.ImeReplaceText(AStart, ALen: Integer; const AText: string);
begin
  ImeReplace(AStart, ALen, AText);
end;

{ ---- 夹具 --------------------------------------------------------------------------- }

constructor TTyTermViewFixture.Create(AParented: Boolean);
begin
  inherited Create;
  FSavedFallback := TyFallbackFontName;
  TyFallbackFontName := 'Segoe UI';
  Titles := TStringList.Create;
  OscData := TStringList.Create;
  Form := TForm.CreateNew(nil);
  Form.SetBounds(0, 0, 900, 700);
  Ctl := TTyStyleController.Create(nil);
  Ctl.Mode := 'light';
  Ctl.ThemeName := 'default';
  Ctl.StyleOverride := TyTermFixtureCss;
  View := TTyTerminalViewProbe.Create(Form);
  View.Controller := Ctl;
  View.OnData := @OnData;
  View.OnGridResize := @OnGrid;
  View.OnTitleChange := @OnTitle;
  View.OnBell := @OnBell;
  View.OnOsc := @OnOsc;
  if AParented then
    View.Parent := Form;
end;

destructor TTyTermViewFixture.Destroy;
begin
  FreeAndNil(Form);          { owns the view }
  FreeAndNil(Ctl);
  Titles.Free;
  OscData.Free;
  TyFallbackFontName := FSavedFallback;
  inherited Destroy;
end;

procedure TTyTermViewFixture.OnData(Sender: TObject; const AData: RawByteString);
begin
  Data := Data + AData;
  Inc(DataEvents);
end;

procedure TTyTermViewFixture.OnGrid(Sender: TObject; ACols, ARows: Integer);
begin
  SetLength(Grids, Length(Grids) + 1);
  Grids[High(Grids)] := Point(ACols, ARows);
end;

procedure TTyTermViewFixture.OnTitle(Sender: TObject; const AText: string);
begin
  Titles.Add(AText);
end;

procedure TTyTermViewFixture.OnBell(Sender: TObject);
begin
  Inc(Bells);
end;

procedure TTyTermViewFixture.OnOsc(Sender: TObject; AIdent: Integer; const AData: string);
begin
  SetLength(OscIdents, Length(OscIdents) + 1);
  OscIdents[High(OscIdents)] := AIdent;
  OscData.Add(AData);
end;

procedure TTyTermViewFixture.ClearRecords;
begin
  Data := '';
  DataEvents := 0;
  Grids := nil;
  Titles.Clear;
  Bells := 0;
  OscIdents := nil;
  OscData.Clear;
  View.ClearInvalidated;
end;

procedure TTyTermViewFixture.SizeTo(ACols, ARows: Integer; AExtraW: Integer; AExtraH: Integer);
var
  sz: TSize;
begin
  sz := View.SizeForGrid(ACols, ARows);
  View.SetBounds(View.Left, View.Top, sz.cx + AExtraW, sz.cy + AExtraH);
end;

function TTyTermViewFixture.Render(APPI: Integer): TBGRABitmap;
var
  bmp: TBitmap;
  w, h: Integer;
begin
  if APPI <= 0 then APPI := View.Font.PixelsPerInch;
  w := View.ClientWidth;
  h := View.ClientHeight;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(w, h);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, w, h);
    View.Render(bmp.Canvas, Rect(0, 0, w, h), APPI);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TTyTermViewFixture.Pad: Integer;
begin
  Result := MulDiv(2, View.Font.PixelsPerInch, 96);
end;

function TTyTermViewFixture.ThemeFg(const ATypeKey: string): Cardinal;
var
  st: TTyStyleSet;
begin
  st := Ctl.Model.ResolveStyle(ATypeKey, '', []);
  if not (tpTextColor in st.Present) then
    raise Exception.Create('the fixture theme has no colour for ' + ATypeKey);
  Result := Cardinal(st.TextColor) and $FFFFFF;
end;

function TTyTermViewFixture.ThemeBg(const ATypeKey: string): Cardinal;
var
  st: TTyStyleSet;
begin
  st := Ctl.Model.ResolveStyle(ATypeKey, '', []);
  if not ((tpBackground in st.Present) and (st.Background.Kind = tfkSolid)) then
    raise Exception.Create('the fixture theme has no background for ' + ATypeKey);
  Result := Cardinal(st.Background.Color) and $FFFFFF;
end;

function TTyTermViewFixture.Ansi(AIndex: Integer): Cardinal;
begin
  Result := ThemeFg('TyTerminalAnsi' + IntToStr(AIndex));
end;

function TTyTermViewFixture.RowText(ARow: Integer): string;
var
  buf: TTyTerminalBuffer;
begin
  buf := View.Core.Buffer;
  Result := buf.TranslateBufferLineToString(buf.YDisp + ARow, True);
end;

{ ---- 测试 --------------------------------------------------------------------------- }

procedure TTyTerminalViewTests.SetUp;
begin
  F := TTyTermViewFixture.Create;
  FDone := nil;
  FClockMs := 1000;
end;

procedure TTyTerminalViewTests.TearDown;
begin
  FreeAndNil(F);
end;

procedure TTyTerminalViewTests.WriteDone(Sender: TObject; ATag: PtrInt);
begin
  SetLength(FDone, Length(FDone) + 1);
  FDone[High(FDone)] := ATag;
end;

function TTyTerminalViewTests.Clock: Double;
begin
  FClockMs := FClockMs + 20;
  Result := FClockMs;
end;

procedure TTyTerminalViewTests.ResizeFromTitle(Sender: TObject; const AText: string);
var
  sz: TSize;
begin
  sz := F.View.SizeForGrid(30, 7);
  F.View.SetBounds(0, 0, sz.cx, sz.cy);
end;

procedure TTyTerminalViewTests.TestPublishedDefaultsMatchTheConstructor;
var
  v: TTyTerminalView;
  list: PPropList;
  n, i, checked: Integer;
  p: PPropInfo;
begin
  v := TTyTerminalView.Create(nil);
  try
    n := GetPropList(v.ClassInfo, [tkInteger, tkChar, tkWChar, tkEnumeration, tkBool], nil);
    GetMem(list, n * SizeOf(Pointer));
    try
      GetPropList(v.ClassInfo, [tkInteger, tkChar, tkWChar, tkEnumeration, tkBool], list);
      checked := 0;
      for i := 0 to n - 1 do
      begin
        p := list^[i];
        if p^.Default = Longint($80000000) then Continue;
        Inc(checked);
        AssertEquals('published default of ' + p^.Name + ' = what the constructor makes',
          Int64(p^.Default), GetOrdProp(v, p));
      end;
      AssertTrue(Format('at least 17 properties with a default checked (%d)', [checked]), checked >= 17);
    finally
      FreeMem(list);
    end;
  finally
    v.Free;
  end;
end;

procedure TTyTerminalViewTests.TestSettersReachTheCore;
var
  v: TTyTerminalViewProbe;
begin
  v := F.View;
  v.Scrollback := 50;
  v.ConvertEol := True;
  v.TabStopWidth := 4;
  v.ScrollOnUserInput := False;
  v.ReadOnly := True;
  v.AmbiguousWide := True;
  v.UnicodeVersion := tuv15;
  v.CursorStyle := tcsBar;
  v.CursorBlink := True;
  AssertEquals('Scrollback', 50, v.Core.Scrollback);
  AssertTrue('ConvertEol', v.Core.ConvertEol);
  AssertEquals('TabStopWidth', 4, v.Core.TabStopWidth);
  AssertFalse('ScrollOnUserInput', v.Core.ScrollOnUserInput);
  AssertTrue('ReadOnly', v.Core.ReadOnly);
  AssertTrue('AmbiguousWide', v.Core.AmbiguousWide);
  AssertTrue('UnicodeVersion', v.Core.UnicodeVersion = tuv15);
  AssertTrue('CursorStyle', v.Core.CursorStyle = tcoBar);
  AssertTrue('CursorBlink', v.Core.CursorBlink);
end;

procedure TTyTerminalViewTests.TestStreamedValuesSurviveLoading;
var
  src, dst: TTyTerminalView;
  ms: TMemoryStream;
begin
  { 不给父控件:没有滚动条子控件,流里只有这个控件自己 }
  src := TTyTerminalView.Create(nil);
  dst := TTyTerminalView.Create(nil);
  ms := TMemoryStream.Create;
  try
    src.Scrollback := 77;
    src.UnicodeVersion := tuv15Graphemes;
    src.CursorStyle := tcsUnderline;
    src.ReadOnly := True;
    src.TabStopWidth := 3;
    src.CursorBlink := True;
    src.LineHeightPercent := 120;
    src.CursorInactiveStyle := tcisNone;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    AssertEquals('Scrollback in the core', 77, dst.Core.Scrollback);
    AssertTrue('UnicodeVersion in the core', dst.Core.UnicodeVersion = tuv15Graphemes);
    AssertTrue('CursorStyle in the core', dst.Core.CursorStyle = tcoUnderline);
    AssertTrue('ReadOnly in the core', dst.Core.ReadOnly);
    AssertEquals('TabStopWidth in the core', 3, dst.Core.TabStopWidth);
    AssertTrue('CursorBlink in the core', dst.Core.CursorBlink);
    AssertEquals('LineHeightPercent', 120, dst.LineHeightPercent);
    AssertTrue('CursorInactiveStyle', dst.CursorInactiveStyle = tcisNone);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTyTerminalViewTests.TestCoreRepliesComeOutOfOnData;
begin
  F.ClearRecords;
  F.View.WriteSync(#27'[c');
  AssertEquals('the DA1 reply', TyTermHex(#27'[?1;2c'), TyTermHex(F.Data));
end;

procedure TTyTerminalViewTests.TestTitleBellAndOsc;
begin
  F.ClearRecords;
  F.View.WriteSync(#27']2;hi'#7);
  AssertEquals('one title event', 1, F.Titles.Count);
  AssertEquals('the title', 'hi', F.Titles[0]);
  AssertEquals('Title reads the core', 'hi', F.View.Title);
  F.View.WriteSync(#7);
  AssertEquals('one bell', 1, F.Bells);
  F.View.WriteSync(#27']7;file://x'#7);
  AssertEquals('one OSC', 1, Length(F.OscIdents));
  AssertEquals('its number', 7, F.OscIdents[0]);
  AssertEquals('its data', 'file://x', F.OscData[0]);
end;

procedure TTyTerminalViewTests.TestANewControlIsUnfocusedToTheCore;
begin
  F.ClearRecords;
  F.View.WriteSync(#27'[?1004h');
  AssertEquals('a new control is unfocused', TyTermHex(#27'[O'), TyTermHex(F.Data));
  F.ClearRecords;
  F.View.Enter;
  AssertEquals('focus in', TyTermHex(#27'[I'), TyTermHex(F.Data));
  F.ClearRecords;
  F.View.Leave;
  AssertEquals('focus out', TyTermHex(#27'[O'), TyTermHex(F.Data));
end;

procedure TTyTerminalViewTests.TestColourQueriesAnswerFromTheTheme;

  procedure Ask(const AQuery: string; AWant: Cardinal);
  begin
    F.ClearRecords;
    F.View.WriteSync(#27']' + AQuery + #7);
    AssertTrue(Format('%s answers %s, got %s', [AQuery, TyTermToRgbString(AWant), F.Data]),
      Pos(TyTermToRgbString(AWant), F.Data) > 0);
  end;

begin
  Ask('11;?', F.ThemeBg('TyTerminal'));
  Ask('10;?', F.ThemeFg('TyTerminal'));
  Ask('12;?', F.ThemeBg('TyTerminalCursor'));
  Ask('4;1;?', F.Ansi(1));
end;

procedure TTyTerminalViewTests.TestAThemeChangeDropsOverridesAndReports;
begin
  F.View.WriteSync(#27']4;1;#123456'#7);
  AssertEquals('the override is in', IntToHex($123456, 6), IntToHex(F.View.Core.ResolveColor(1), 6));
  F.View.WriteSync(#27'[?2031h');
  F.ClearRecords;
  F.Ctl.Mode := 'dark';
  AssertEquals('the override went with the theme', IntToHex(F.Ansi(1), 6), IntToHex(F.View.Core.ResolveColor(1), 6));
  AssertTrue('a colour-scheme report went out: ' + TyTermHex(F.Data), Pos(#27'[?997;', F.Data) = 1);
  AssertEquals('one report', 1, F.DataEvents);
end;

procedure TTyTerminalViewTests.TestSwappingControllersRebuildsThePalette;
var
  a, b: TTyStyleController;
begin
  a := TTyStyleController.Create(nil);
  b := TTyStyleController.Create(nil);
  try
    a.Mode := 'light';
    a.ThemeName := 'default';
    a.StyleOverride := 'TyTerminal { background: #111111; color: #eeeeee; }';
    b.Mode := 'dark';
    b.ThemeName := 'default';
    b.StyleOverride := 'TyTerminal { background: #222222; color: #dddddd; }';
    AssertEquals('precondition: the two versions are equal (else change the fixture)',
      a.Model.ThemeVersion, b.Model.ThemeVersion);
    F.View.Controller := a;
    AssertEquals('A''s background', IntToHex($111111, 6), IntToHex(F.View.Core.ResolveColor(257), 6));
    F.View.Controller := b;
    AssertEquals('B''s background', IntToHex($222222, 6), IntToHex(F.View.Core.ResolveColor(257), 6));
    F.View.Controller := F.Ctl;
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TTyTerminalViewTests.TestWindowReportsInDevicePixels;
var
  m: TTyTermCellMetrics;
begin
  F.SizeTo(20, 5);
  F.View.Core.WindowOptions := [twoGetWinSizePixels, twoGetCellSizePixels];
  m := F.View.CellMetrics;
  F.ClearRecords;
  F.View.WriteSync(#27'[14t');
  AssertEquals('14t', Format(#27'[4;%d;%dt', [5 * m.CellH, 20 * m.CellW]), F.Data);
  F.ClearRecords;
  F.View.WriteSync(#27'[16t');
  AssertEquals('16t', Format(#27'[6;%d;%dt', [m.CellH, m.CellW]), F.Data);
end;

procedure TTyTerminalViewTests.TestTheGridFollowsTheClientArea;
begin
  F.ClearRecords;
  F.SizeTo(10, 5, 3, 2);
  AssertEquals('Cols', 10, F.View.Cols);
  AssertEquals('Rows', 5, F.View.Rows);
  AssertEquals('the core''s cols', 10, F.View.Core.Cols);
  AssertEquals('the core''s rows', 5, F.View.Core.Rows);
  AssertEquals('one grid event', 1, Length(F.Grids));
  AssertEquals('its cols', 10, F.Grids[0].X);
  AssertEquals('its rows', 5, F.Grids[0].Y);
end;

procedure TTyTerminalViewTests.TestTheFirstLayoutIsAnnounced;
var
  fx: TTyTermViewFixture;
  sz: TSize;
begin
  { 不给父控件地建,量好 80 x 24 的客户区,再放上窗体:网格没变,也要发一次 }
  fx := TTyTermViewFixture.Create(False);
  try
    sz := fx.View.SizeForGrid(80, 24);
    fx.View.SetBounds(0, 0, sz.cx, sz.cy);
    AssertEquals('nothing announced before it is parented', 0, Length(fx.Grids));
    fx.View.Parent := fx.Form;
    AssertEquals('announced once', 1, Length(fx.Grids));
    AssertEquals('80 cols', 80, fx.Grids[0].X);
    AssertEquals('24 rows', 24, fx.Grids[0].Y);
    fx.View.SetBounds(0, 0, sz.cx, sz.cy);
    AssertEquals('the same bounds again: no second event', 1, Length(fx.Grids));
  finally
    fx.Free;
  end;
end;

procedure TTyTerminalViewTests.TestDecColmResizesTheGrid;
begin
  F.SizeTo(20, 6);
  F.View.Core.WindowOptions := [twoSetWinLines];
  F.ClearRecords;
  F.View.WriteSync(#27'[?3h');
  AssertEquals('one grid event', 1, Length(F.Grids));
  AssertEquals('132 columns', 132, F.Grids[0].X);
  AssertEquals('rows kept', 6, F.Grids[0].Y);
end;

procedure TTyTerminalViewTests.TestSizeForGridRoundTrips;
var
  sz: TSize;
begin
  sz := F.View.SizeForGrid(33, 11);
  F.View.SetBounds(0, 0, sz.cx, sz.cy);
  AssertEquals('cols', 33, F.View.Cols);
  AssertEquals('rows', 11, F.View.Rows);
  F.View.SetBounds(0, 0, sz.cx - 1, sz.cy);
  AssertEquals('a pixel narrower: one column fewer', 32, F.View.Cols);
end;

procedure TTyTerminalViewTests.TestCellAtAndCellRect;
var
  r: TRect;
  m: TTyTermCellMetrics;
  p: TPoint;
begin
  F.SizeTo(20, 6);
  m := F.View.CellMetrics;
  r := F.View.CellRect(3, 2);
  AssertEquals('left', F.Pad + 3 * m.CellW, r.Left);
  AssertEquals('top', F.Pad + 2 * m.CellH, r.Top);
  AssertEquals('width', m.CellW, r.Right - r.Left);
  AssertEquals('height', m.CellH, r.Bottom - r.Top);
  p := F.View.CellAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('CellAt col', 3, p.X);
  AssertEquals('CellAt row', 2, p.Y);
  p := F.View.CellAt(-5, 10000);
  AssertEquals('clamped col', 0, p.X);
  AssertEquals('clamped row', F.View.Rows - 1, p.Y);
end;

procedure TTyTerminalViewTests.TestAWriteAsksForOneSlice;
begin
  F.View.SliceCalls := 0;
  F.View.Write('a');
  AssertEquals('one slice asked', 1, F.View.SliceCalls);
  F.View.Write('b');
  AssertEquals('still one: the first is not done', 1, F.View.SliceCalls);
  AssertFalse('the queue drains', F.View.Core.ProcessPending);
  F.View.Write('c');
  AssertEquals('a new slice for a new write', 2, F.View.SliceCalls);
end;

procedure TTyTerminalViewTests.TestSlicesRunThroughTheMessageQueue;
var
  i: Integer;
begin
  TyTermNeedWidgetSet;
  F.View.PassSlices := True;
  F.View.Core.Clock := @Clock;
  F.View.Write('abc', @WriteDone, 1);
  F.View.Write('def', @WriteDone, 2);
  F.View.Write('ghi', @WriteDone, 3);
  i := 0;
  while (Length(FDone) < 3) and (i < 100) do
  begin
    Forms.Application.ProcessMessages;
    Inc(i);
  end;
  F.View.Core.Clock := nil;
  AssertEquals('three callbacks', 3, Length(FDone));
  AssertEquals('in order 1', 1, FDone[0]);
  AssertEquals('in order 2', 2, FDone[1]);
  AssertEquals('in order 3', 3, FDone[2]);
  AssertTrue('it took more than one slice', F.View.SliceCalls > 1);
  AssertEquals('the text', 'abcdefghi', F.RowText(0));
end;

procedure TTyTerminalViewTests.TestAFreedControlLeavesNoSliceBehind;
var
  v: TTyTerminalView;
begin
  TyTermNeedWidgetSet;
  v := TTyTerminalView.Create(nil);
  v.Write('something');
  v.Free;
  Forms.Application.ProcessMessages;
  AssertTrue('no access violation', True);
end;

procedure TTyTerminalViewTests.TestSyncOutputHoldsRowsBack;
var
  i: Integer;
  covered: Boolean;
begin
  F.SizeTo(20, 6);
  F.View.WriteSync(#27'[?2026h');
  F.View.ClearInvalidated;
  F.View.WriteSync(#27'[3;1Hheld');
  AssertEquals('nothing invalidated while held', 0, Length(F.View.Invalidated));
  AssertTrue('the timer runs', F.View.SyncOn);
  F.View.WriteSync(#27'[?2026l');
  covered := False;
  for i := 0 to High(F.View.Invalidated) do
    if (F.View.Invalidated[i].X <= 2) and (F.View.Invalidated[i].Y >= 2) then covered := True;
  AssertTrue('the held row is invalidated when the mode ends', covered);
  AssertFalse('the timer stopped', F.View.SyncOn);
  AssertEquals('nothing held', -1, F.View.HeldRows.X);
end;

procedure TTyTerminalViewTests.TestSyncOutputTimesOut;
var
  i: Integer;
  covered: Boolean;
begin
  F.SizeTo(20, 6);
  F.View.WriteSync(#27'[?2026h'#27'[4;1Hheld');
  F.View.ClearInvalidated;
  F.View.FireSyncTimer;
  AssertFalse('the mode is off', F.View.Core.Modes.SynchronizedOutput);
  covered := False;
  for i := 0 to High(F.View.Invalidated) do
    if (F.View.Invalidated[i].X <= 3) and (F.View.Invalidated[i].Y >= 3) then covered := True;
  AssertTrue('the held row is invalidated', covered);
end;

procedure TTyTerminalViewTests.TestTheSyncTimerStartsAtTheFirstHeldRow;
begin
  { 上游 InputHandler.parse 每次结尾都报光标行(DirtyRowTracker 从光标行起),所以打开 2026
    的那一块自己就带来第一行被攒的行:计时器在那时起(RenderService 的 bufferRows),
    不是在模式变化的事件里起。两者在同一次解析里,本测试守的是「攒到了才起」。 }
  F.SizeTo(20, 6);
  AssertFalse('no timer before', F.View.SyncOn);
  F.View.WriteSync(#27'[2;1H');
  AssertFalse('no timer without the mode', F.View.SyncOn);
  F.View.WriteSync(#27'[?2026h');
  AssertTrue('the block that turned it on held its cursor row', F.View.SyncOn);
  AssertEquals('held from the cursor row', 1, F.View.HeldRows.X);
end;

procedure TTyTerminalViewTests.TestResizingFromACoreEventIsSafe;
begin
  F.SizeTo(20, 6);
  F.View.OnTitleChange := @ResizeFromTitle;
  F.View.WriteSync(#27']2;x'#7'some text');
  AssertEquals('cols follow the new width', 30, F.View.Cols);
  AssertEquals('rows follow the new height', 7, F.View.Rows);
  AssertEquals('the core agrees', 30, F.View.Core.Cols);
end;

procedure TTyTerminalViewTests.TestDesignTimePreview;
var
  fx: TTyTermViewFixture;
  i: Integer;
begin
  fx := TTyTermViewFixture.Create(False);
  try
    fx.View.MakeDesigning;
    fx.View.SliceCalls := 0;
    fx.View.SetBounds(0, 0, 400, 200);
    fx.View.Parent := fx.Form;
    AssertTrue('the preview is written: ' + fx.RowText(0), Pos('black', fx.RowText(0)) = 1);
    for i := 0 to fx.View.ControlCount - 1 do
      AssertFalse('no scroll bar at design time', fx.View.Controls[i] is TTyScrollBar);
    AssertFalse('no blink timer', fx.View.BlinkOn);
    AssertFalse('no sync timer', fx.View.SyncOn);
    AssertEquals('no slice scheduled', 0, fx.View.SliceCalls);
  finally
    fx.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalViewTests);
end.
