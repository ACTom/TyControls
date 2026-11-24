unit test.richedit.display;

{ TTyRichEdit as a page: a help page (read-only, selectable and copyable, no caret, links on a
  plain click, bars as needed) and a home page (read-only, nothing to select, no caret, never
  focused, no bars, as tall as its content inside a scroll box). Each switch alone -
  CaretWhenReadOnly, FocusOnClick, AllowSelection, ScrollBars, AutoHeight - the content's size
  (ContentHeight / ContentWidth, ContentSizeIsEstimate, OnContentSizeChange), and the two pages
  as a whole.

  Headless, on the control suite's probe (the test device): no window, no focus, no clipboard.
  The pictures of the two pages (real fonts, off-screen) are written only when the environment
  names a folder (TY_RICH_SHOTS). }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry, Controls, Graphics, Forms, StdCtrls,
  LCLType, LMessages, Menus, BGRABitmap, BGRABitmapTypes, BGRAWritePNG,
  tyControls.Controller, tyControls.ScrollBar, tyControls.ScrollBox, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.Layout, tyControls.RichEdit,
  test.richedit.control;

type
  { The probe with the mouse, the keys, the pointer's answer and a focus that can be asked
    for (CanFocus) and counted (SetFocus) without a window. }
  TDisplayProbe = class(TRichProbe)
  public
    Focusable: Boolean;
    FocusCalls: Integer;
    function CanFocus: Boolean; override;
    procedure SetFocus; override;
    procedure MDown(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
    procedure MMove(AShift: TShiftState; X, Y: Integer);
    procedure MUp(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
    procedure KeyOf(AKey: Word; AShift: TShiftState);
    function PointerAt(X, Y: Integer): TCursor;
    // the pixels DrawCaret inks on a white bitmap of the control's size
    function CaretInk: Integer;
    // the wheel: whether the control took it, and what the message answers (0: the parent's)
    function WheelTaken(ADelta: Integer; AShift: TShiftState): Boolean;
    function WheelHTaken(ADelta: Integer): Boolean;
    function WheelMessage(ADelta: Integer): PtrInt;
  end;

  // (the box's wheel and the LCL's align pass, protected)
  TBoxAccess = class(TTyScrollBox)
  public
    function Wheel(ADelta: Integer): Boolean;
    procedure Align;
    // the width an aligned child gets (the client rectangle the box adjusts)
    function AlignWidth: Integer;
  end;

  // (the bar's own drawing, protected)
  TBarAccess = class(TTyCustomScrollBar)
  end;

  { A real control (real fonts) whose kept surface a test reads: what a paint drew. }
  TShotRich = class(TTyRichEdit)
  public
    function Shot(APPI: Integer): TBGRABitmap;
    procedure PutBar(ATarget: TBGRABitmap; ABar: TControl; APPI: Integer);
  end;

  TTyRichDisplayTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TDisplayProbe;
    FClicks, FSizeEvents, FResizeInHandler: Integer;
    FClickURL: string;
    FMenusAsked: Integer;
    FDarkTheme: string;
    FInPaint: Boolean;
    FInPaintEvents: Integer;
    procedure MenuAsked(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure LinkClicked(Sender: TObject; const AURL: string; AButton: TMouseButton);
    procedure SizeChanged(Sender: TObject);
    procedure SizeChangedResizes(Sender: TObject);
    function NewProbe: TDisplayProbe;
    procedure LoadRtf(const S: RawByteString);
    procedure SetLongText(AParas: Integer; const AWord: string = 'text ');
    function PointIn(AChar: TTyRichPos): TPoint;
    function Insets: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheDefaultsAreTodaysControl;
    procedure TestNoCaretWhenReadOnlyAndAsked;
    procedure TestAClickDoesNotTakeFocus;
    procedure TestNoSelectionByMouseOrKeys;
    procedure TestScrollBarsNoneNeverShows;
    procedure TestContentHeightIsExactOnceLaidOut;
    procedure TestAutoHeightFollowsContentWidthZoomAndTheme;
    procedure TestTheSizeEventFiresOncePerChange;
    procedure TestAHelpPage;
    procedure TestAHomePage;
    procedure TestShotsOfBothPages;
    procedure TestTheWheelOverAHomePageIsTheBoxs;
    procedure TestNoMenuOfItsOwnWithNothingToEditOrSelect;
    procedure TestAutoHeightWaitsForAnExactSizeAndHasALimit;
    procedure TestAutoHeightUnderAlignAndAtAnotherPPI;
    procedure TestTheContentWidthCountsAShownBar;
  end;

implementation

uses
  tyControls.BuiltinThemes;

const
  BS = #92;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then Move(S[1], Result[0], Length(S));
end;

{ A page: a heading, two paragraphs, a link in the second; a picture goes in after. }
function PageRtf: RawByteString;
begin
  Result := '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' +
    '{' + BS + 'colortbl;' + BS + 'red5' + BS + 'green99' + BS + 'blue193;}' +
    BS + 'pard' + BS + 'qc' + BS + 'sa120' + BS + 'f0' + BS + 'fs40' + BS + 'b Welcome' + BS + 'par' +
    BS + 'pard' + BS + 'sa120' + BS + 'plain' + BS + 'f0' + BS + 'fs24 This page is built from ' +
    'code and shown by a rich edit, not by a browser.' + BS + 'par' +
    BS + 'pard' + BS + 'sa120 Read the {' + BS + 'field{' + BS + '*' + BS +
    'fldinst HYPERLINK "https://example.com/guide"}{' + BS + 'fldrslt {' + BS + 'ul' + BS +
    'cf1 guide}}} or start a new document.' + BS + 'par' +
    BS + 'pard ' + BS + 'par}';
end;

{ ---- the probe ---- }

function TDisplayProbe.CanFocus: Boolean;
begin
  // (a test's focus: whatever a press without it refuses is refused here too)
  Result := Focusable and not PressRefusesFocus;
end;

function TDisplayProbe.WheelTaken(ADelta: Integer; AShift: TShiftState): Boolean;
begin
  Result := DoMouseWheel(AShift, ADelta, Point(10, 10));
end;

function TDisplayProbe.WheelHTaken(ADelta: Integer): Boolean;
begin
  Result := DoMouseWheelHorz([], ADelta, Point(10, 10));
end;


function TDisplayProbe.WheelMessage(ADelta: Integer): PtrInt;
var
  m: TLMMouseEvent;
begin
  FillChar(m, SizeOf(m), 0);
  m.Msg := LM_MOUSEWHEEL;
  m.WheelDelta := ADelta;
  m.X := 10;
  m.Y := 10;
  Dispatch(m);
  Result := m.Result;
end;

function TBoxAccess.Wheel(ADelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(10, 10));
end;

function TBoxAccess.AlignWidth: Integer;
var
  r: TRect;
begin
  r := ClientRect;
  AdjustClientRect(r);
  Result := r.Right - r.Left;
end;

// what the LCL's align pass does: the raw client rectangle (AlignControls applies the box's own)
procedure TBoxAccess.Align;
var
  r: TRect;
begin
  r := ClientRect;
  AlignControls(nil, r);
end;

procedure TDisplayProbe.SetFocus;
begin
  Inc(FocusCalls);
end;

procedure TDisplayProbe.MDown(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
begin
  MouseDown(AButton, AShift, X, Y);
end;

procedure TDisplayProbe.MMove(AShift: TShiftState; X, Y: Integer);
begin
  MouseMove(AShift, X, Y);
end;

procedure TDisplayProbe.MUp(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
begin
  MouseUp(AButton, AShift, X, Y);
end;

procedure TDisplayProbe.KeyOf(AKey: Word; AShift: TShiftState);
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

function TDisplayProbe.PointerAt(X, Y: Integer): TCursor;
begin
  Result := CursorAt(X, Y);
end;

function TDisplayProbe.CaretInk: Integer;
var
  bmp: TBitmap;
  x, y: Integer;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(Width, Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, Width, Height);
    DrawCaret(bmp.Canvas);
    Result := 0;
    for y := 0 to Height - 1 do
      for x := 0 to Width - 1 do
        if bmp.Canvas.Pixels[x, y] <> clWhite then Inc(Result);
  finally
    bmp.Free;
  end;
end;

function TShotRich.Shot(APPI: Integer): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(Width, Height);
    PaintArea(bmp.Canvas, Rect(0, 0, Width, Height), Rect(0, 0, Width, Height), APPI, False);
  finally
    bmp.Free;
  end;
  Result := Surface.GetPart(Rect(0, 0, Width, Height)) as TBGRABitmap;
  // the bars are controls of their own over it: each drawn where it is
  if (VerticalBar <> nil) and VerticalBar.Visible then
    PutBar(Result, VerticalBar, APPI);
  if (HorizontalBar <> nil) and HorizontalBar.Visible then
    PutBar(Result, HorizontalBar, APPI);
end;

procedure TShotRich.PutBar(ATarget: TBGRABitmap; ABar: TControl; APPI: Integer);
var
  bar: TBGRABitmap;
begin
  bar := TBGRABitmap.Create(ABar.Width, ABar.Height, BGRA(255, 0, 255, 255));
  try
    TBarAccess(ABar).RenderTo(bar.Canvas, Rect(0, 0, ABar.Width, ABar.Height), APPI);
    ATarget.PutImage(ABar.Left, ABar.Top, bar, dmSet);
  finally
    bar.Free;
  end;
end;

{ ---- fixtures ---- }

procedure TTyRichDisplayTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
  FClicks := 0;
  FSizeEvents := 0;
  FResizeInHandler := 0;
end;

procedure TTyRichDisplayTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

function TTyRichDisplayTest.NewProbe: TDisplayProbe;
begin
  Result := TDisplayProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
end;

procedure TTyRichDisplayTest.LinkClicked(Sender: TObject; const AURL: string;
  AButton: TMouseButton);
begin
  Inc(FClicks);
  FClickURL := AURL;
end;

procedure TTyRichDisplayTest.SizeChanged(Sender: TObject);
begin
  Inc(FSizeEvents);
  if FInPaint then Inc(FInPaintEvents);
end;

procedure TTyRichDisplayTest.SizeChangedResizes(Sender: TObject);
begin
  Inc(FSizeEvents);
  // a handler that sizes the control by the content: no loop
  Inc(FResizeInHandler);
  FRich.Height := FRich.ContentHeight;
end;

procedure TTyRichDisplayTest.LoadRtf(const S: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(RawBytes(S));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
end;

procedure TTyRichDisplayTest.SetLongText(AParas: Integer; const AWord: string);
var
  s: string;
  i, k: Integer;
begin
  s := '';
  for i := 1 to AParas do
  begin
    for k := 1 to 1 + i mod 7 do s := s + AWord;
    if i < AParas then s := s + LineEnding;
  end;
  FRich.Lines.Text := s;
  FRich.UpdateView;
end;

function TTyRichDisplayTest.PointIn(AChar: TTyRichPos): TPoint;
var
  r, r2: TRect;
begin
  r := FRich.PositionRect(AChar);
  r2 := FRich.PositionRect(AChar + 1, True);
  AssertTrue('the character is in view', r.Bottom > r.Top);
  Result.X := (r.Left + r2.Left) div 2;
  Result.Y := (r.Top + r.Bottom) div 2;
end;

// what the control is taller than its text area (the padding; no horizontal bar)
function TTyRichDisplayTest.Insets: Integer;
begin
  Result := FRich.Height - (FRich.Area.Bottom - FRich.Area.Top);
end;

{ ---- each switch ---- }

procedure TTyRichDisplayTest.TestTheDefaultsAreTodaysControl;
begin
  AssertTrue('CaretWhenReadOnly', FRich.CaretWhenReadOnly);
  AssertTrue('FocusOnClick', FRich.FocusOnClick);
  AssertTrue('AllowSelection', FRich.AllowSelection);
  AssertTrue('ScrollBars', FRich.ScrollBars = ssBoth);
  AssertFalse('AutoHeight', FRich.AutoHeight);
  AssertTrue('TabStop', FRich.TabStop);
end;

procedure TTyRichDisplayTest.TestNoCaretWhenReadOnlyAndAsked;
begin
  FRich.Lines.Text := 'Some text';
  FRich.UpdateView;
  FRich.ForceFocus := True;
  AssertTrue('editable: the caret', FRich.CaretInk > 0);
  FRich.ReadOnly := True;
  AssertTrue('read-only, as today: the caret', FRich.CaretInk > 0);
  FRich.CaretWhenReadOnly := False;
  AssertEquals('read-only and asked: no caret', 0, FRich.CaretInk);
  // the selection still grows from the caret's place with Shift and the arrows
  FRich.SelStart := 2;
  FRich.KeyOf(VK_RIGHT, [ssShift]);
  FRich.KeyOf(VK_RIGHT, [ssShift]);
  AssertEquals('Shift+Right twice: a selection from the hidden caret', 2, FRich.SelLength);
  AssertEquals('from where it was', 2, FRich.SelStart);
  FRich.ReadOnly := False;
  FRich.SelLength := 0;
  AssertTrue('editable again: the caret', FRich.CaretInk > 0);
end;

procedure TTyRichDisplayTest.TestAClickDoesNotTakeFocus;
var
  p: TPoint;
begin
  FRich.Lines.Text := 'Some text to press on';
  FRich.UpdateView;
  FRich.Focusable := True;
  p := PointIn(3);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MUp(mbLeft, [], p.X, p.Y);
  AssertTrue('as today: a press takes the focus', FRich.FocusCalls > 0);
  FRich.FocusOnClick := False;
  FRich.FocusCalls := 0;
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MUp(mbLeft, [], p.X, p.Y);
  FRich.MDown(mbRight, [ssRight], p.X, p.Y);
  FRich.MUp(mbRight, [], p.X, p.Y);
  AssertEquals('FocusOnClick False: never', 0, FRich.FocusCalls);
  AssertEquals('the caret is placed all the same', Int64(3), FRich.CaretIndex);
  // the wheel still scrolls under the pointer
  SetLongText(200);
  FRich.Wheel(-120, []);
  AssertTrue('the wheel scrolls', FRich.ScrollY > 0);
  AssertEquals('still no focus asked for', 0, FRich.FocusCalls);
end;

procedure TTyRichDisplayTest.TestNoSelectionByMouseOrKeys;
var
  p, p2: TPoint;
begin
  LoadRtf(PageRtf);
  FRich.OnLinkClick := @LinkClicked;
  FRich.AllowSelection := False;
  FRich.SelStart := 0;
  // the mouse: a drag, a double click, a Shift+click select nothing; a press places nothing
  p := PointIn(10);
  p2 := PointIn(20);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MMove([ssLeft], p2.X, p2.Y);
  FRich.MUp(mbLeft, [], p2.X, p2.Y);
  AssertEquals('a drag: nothing selected', 0, FRich.SelLength);
  AssertEquals('a press: the caret not moved', Int64(0), FRich.CaretIndex);
  FRich.MDown(mbLeft, [ssLeft, ssDouble], p.X, p.Y);
  FRich.MUp(mbLeft, [], p.X, p.Y);
  AssertEquals('a double click: no word', 0, FRich.SelLength);
  FRich.MDown(mbLeft, [ssLeft, ssShift], p2.X, p2.Y);
  FRich.MUp(mbLeft, [ssShift], p2.X, p2.Y);
  AssertEquals('Shift+click: nothing', 0, FRich.SelLength);
  // the keys: Shift+arrows, Ctrl+A
  FRich.KeyOf(VK_RIGHT, [ssShift]);
  FRich.KeyOf(VK_END, [ssShift, ssCtrl]);
  AssertEquals('Shift+arrows: nothing', 0, FRich.SelLength);
  FRich.KeyOf(VK_A, [ssCtrl]);
  AssertEquals('Ctrl+A: nothing', 0, FRich.SelLength);
  // copying: unavailable, also of what code selected
  FRich.SelStart := 0;
  FRich.SelLength := 7;
  AssertEquals('code selects: drawn, its own asking', 7, FRich.SelLength);
  FRich.ClipWrites := 0;
  FRich.KeyOf(VK_C, [ssCtrl]);
  FRich.CopyToClipboard;
  AssertEquals('no copy', 0, FRich.ClipWrites);
  AssertFalse('the menu''s Copy unavailable', FRich.TeHasSelection);
  AssertFalse('the menu''s Select All unavailable', FRich.TeHasText);
  // the pointer: the arrow over text, the hand over the link
  AssertTrue('the arrow over text', FRich.PointerAt(p.X, p.Y) = crDefault);
  p := PointIn(FRich.FindText('guide', 0, -1, []) + 1);
  AssertTrue('the hand over the link', FRich.PointerAt(p.X, p.Y) = crHandPoint);
  // a link: a plain left click fires, editable too
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MUp(mbLeft, [], p.X, p.Y);
  AssertEquals('the link''s click', 1, FClicks);
  AssertEquals('its target', 'https://example.com/guide', FClickURL);
  // allowed again: a drag selects
  FRich.AllowSelection := True;
  FRich.SelLength := 0;
  p := PointIn(10);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MMove([ssLeft], p2.X, p2.Y);
  FRich.MUp(mbLeft, [], p2.X, p2.Y);
  AssertTrue('allowed: a drag selects', FRich.SelLength > 0);
end;

procedure TTyRichDisplayTest.TestScrollBarsNoneNeverShows;
var
  y: Int64;
begin
  SetLongText(300);
  AssertTrue('as today: a bar for a long text', (FRich.VBar <> nil) and FRich.VBar.Visible);
  FRich.ScrollBars := ssNone;
  FRich.UpdateView;
  AssertFalse('ssNone: no bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
  AssertEquals('the text area to the right edge', FRich.Width - FRich.Area.Left,
    FRich.Area.Right);
  AssertFalse('the wheel: the parent''s (no direction to scroll)', FRich.WheelTaken(-120, []));
  AssertEquals('so nothing moved', Int64(0), FRich.ScrollY);
  y := FRich.ScrollY;
  FRich.KeyOf(VK_END, [ssCtrl]);
  AssertTrue('the keys still scroll', FRich.ScrollY > y);
  FRich.ScrollY := 0;
  AssertEquals('ScrollY still settable', Int64(0), FRich.ScrollY);
  // one direction only
  FRich.ScrollBars := ssHorizontal;
  FRich.UpdateView;
  AssertFalse('ssHorizontal: no vertical bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
  FRich.ScrollBars := ssAutoVertical;
  FRich.UpdateView;
  AssertTrue('ssAutoVertical: the vertical bar, as needed', (FRich.VBar <> nil) and FRich.VBar.Visible);
  FRich.ScrollBars := ssVertical;
  FRich.Lines.Text := 'short';
  FRich.UpdateView;
  AssertFalse('ssVertical, nothing to scroll: none', (FRich.VBar <> nil) and FRich.VBar.Visible);
  // horizontal: a line that does not wrap
  FRich.WrapMode := rwmNone;
  FRich.Lines.Text := StringOfChar('w', 500);
  FRich.ScrollBars := ssVertical;
  FRich.UpdateView;
  AssertFalse('ssVertical: no horizontal bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
  AssertFalse('the horizontal wheel: the parent''s', FRich.WheelHTaken(120));
  FRich.KeyOf(VK_END, []);
  AssertTrue('the keys scroll sideways', FRich.ScrollX > 0);
  FRich.UpdateView;
  AssertTrue('... and it stays scrolled with no bar', FRich.ScrollX > 0);
  FRich.ScrollBars := ssBoth;
  FRich.UpdateView;
  AssertTrue('ssBoth: the horizontal bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
end;

{ The content's height is exact once laid out: the control made that tall shows all of it -
  no vertical bar - and a pixel less needs one. }
procedure TTyRichDisplayTest.TestContentHeightIsExactOnceLaidOut;
var
  h: Integer;
begin
  FRich.ScrollBars := ssVertical;
  SetLongText(120);
  AssertTrue('only what is in view is measured', FRich.Document.Text.MeasuredParaCount <
    FRich.Document.Text.ParaCount);
  h := FRich.ContentHeight;
  AssertFalse('exact now', FRich.ContentSizeIsEstimate);
  AssertEquals('every paragraph measured', FRich.Document.Text.ParaCount,
    FRich.Document.Text.MeasuredParaCount);
  AssertEquals('the text and the padding', FRich.Document.Text.TotalHeight + Insets, Int64(h));
  FRich.Height := h;
  FRich.UpdateView;
  AssertFalse('that tall: everything in view, no bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
  FRich.Height := h - 1;
  FRich.UpdateView;
  AssertTrue('a pixel less: a bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
  // the width: the widest line and the padding (no wrap)
  FRich.WrapMode := rwmNone;
  FRich.Lines.Text := 'a short line' + LineEnding + StringOfChar('w', 80);
  FRich.UpdateView;
  AssertTrue('wider than the short line', FRich.ContentWidth > FRich.Width div 2);
end;

procedure TTyRichDisplayTest.TestAutoHeightFollowsContentWidthZoomAndTheme;
var
  h0, h1: Integer;
begin
  SetLongText(12);
  FRich.AutoHeight := True;
  FRich.UpdateView;
  h0 := FRich.Height;
  AssertEquals('as tall as the content', FRich.ContentHeight, h0);
  AssertFalse('never a vertical bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
  // narrower: more lines
  FRich.Width := 160;
  FRich.UpdateView;
  AssertTrue('narrower: taller', FRich.Height > h0);
  AssertEquals('narrower: the content', FRich.ContentHeight, FRich.Height);
  h1 := FRich.Height;
  // the zoom
  FRich.Zoom := 200;
  FRich.UpdateView;
  AssertTrue('200 %: taller', FRich.Height > h1);
  AssertEquals('200 %: the content', FRich.ContentHeight, FRich.Height);
  FRich.Zoom := 100;
  FRich.UpdateView;
  AssertEquals('100 % again', h1, FRich.Height);
  // the theme's padding
  FRich.StyleOverride := 'padding: 30px';
  FRich.UpdateView;
  AssertEquals('the padding: the content and it', FRich.ContentHeight, FRich.Height);
  AssertTrue('more padding: taller', FRich.Height > h1);
  FRich.StyleOverride := '';
  // the content
  FRich.Lines.Text := 'one line';
  FRich.UpdateView;
  AssertTrue('less text: lower', FRich.Height < h1);
  // Constraints hold
  SetLongText(40);
  FRich.Constraints.MaxHeight := 100;
  FRich.UpdateView;
  AssertEquals('within Constraints', 100, FRich.Height);
  AssertFalse('held lower than its content: still no vertical bar',
    (FRich.VBar <> nil) and FRich.VBar.Visible);
  FRich.Constraints.MaxHeight := 0;
  // a horizontal bar (no wrap, a long line): the height holds it too
  FRich.WrapMode := rwmNone;
  FRich.Lines.Text := 'one' + LineEnding + StringOfChar('w', 300);
  FRich.UpdateView;
  AssertTrue('a horizontal bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
  AssertEquals('the bar in the height: the text area holds the text',
    FRich.Document.Text.TotalHeight, Int64(FRich.Area.Bottom - FRich.Area.Top));
  FRich.WrapMode := rwmWindow;
  // the parent decides: alClient sets nothing
  FRich.Height := 50;
  FRich.Align := alClient;
  FRich.UpdateView;
  AssertEquals('alClient: not set', 50, FRich.Height);
end;

procedure TTyRichDisplayTest.TestTheSizeEventFiresOncePerChange;
var
  n: Integer;

  // a paint of the whole control, as the window's (its view made inside it)
  procedure Paint;
  var
    bmp: TBitmap;
  begin
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(FRich.Width, FRich.Height);
      FInPaint := True;
      try
        FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), False);
      finally
        FInPaint := False;
      end;
    finally
      bmp.Free;
    end;
  end;

begin
  FRich.OnContentSizeChange := @SizeChanged;
  FRich.Lines.Text := 'one';
  FRich.UpdateView;
  AssertEquals('the first size', 1, FSizeEvents);
  FRich.UpdateView;
  FRich.UpdateView;
  AssertEquals('nothing changed: none', 1, FSizeEvents);
  FRich.Lines.Text := 'one' + LineEnding + 'two';
  FRich.UpdateView;
  AssertEquals('a paragraph more: one', 2, FSizeEvents);
  // a paint never fires it
  FRich.Lines.Text := 'one' + LineEnding + 'two' + LineEnding + 'three';
  Paint;
  AssertEquals('inside a paint: queued, not fired', 2, FSizeEvents);
  AssertTrue('queued', FRich.Posts > 0);
  FRich.UpdateView;
  AssertEquals('then once', 3, FSizeEvents);
  AssertEquals('never inside the paint', 0, FInPaintEvents);
  // a handler that resizes the control: no loop
  FRich.OnContentSizeChange := @SizeChangedResizes;
  SetLongText(30);
  FRich.UpdateView;
  FRich.UpdateView;
  n := FSizeEvents;
  { (sized to its content, its bar goes and the text wraps wider: the content's size changes
    once more, then settles) }
  AssertTrue('the change, and what the handler''s sizing changed: at most two', (n > 3) and (n <= 5));
  FRich.UpdateView;
  FRich.UpdateView;
  AssertEquals('settled: no more', n, FSizeEvents);
  AssertEquals('the handler sized it', FRich.ContentHeight, FRich.Height);
  // nobody listens: nothing is queued or measured
  FRich.OnContentSizeChange := nil;
  TRichProbe.Posts := 0;
  SetLongText(300);
  Paint;
  AssertEquals('no listener: nothing queued', 0, TRichProbe.Posts);
  AssertTrue('no listener: nothing measured beyond the view',
    FRich.Document.Text.MeasuredParaCount < FRich.Document.Text.ParaCount);
end;

{ ---- the two pages ---- }

{ A help page: read-only, selectable and copyable, no caret, links on a plain click, bars as
  needed. }
procedure TTyRichDisplayTest.TestAHelpPage;
var
  p, p2: TPoint;
  s: string;
  i: Integer;
begin
  FRich.ReadOnly := True;
  FRich.CaretWhenReadOnly := False;
  FRich.OnLinkClick := @LinkClicked;
  LoadRtf(PageRtf);
  FRich.ForceFocus := True;
  AssertEquals('no caret', 0, FRich.CaretInk);
  // selectable with the mouse, copied with the keys
  p := PointIn(0);
  p2 := PointIn(6);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MMove([ssLeft], p2.X, p2.Y);
  FRich.MUp(mbLeft, [], p2.X, p2.Y);
  AssertTrue('a drag selects', FRich.SelLength > 0);
  FRich.KeyOf(VK_C, [ssCtrl]);
  AssertTrue('copied', Pos('Welcom', FRich.ClipText) = 1);
  AssertEquals('still no caret, with a selection', 0, FRich.CaretInk);
  // the link on a plain click
  p := PointIn(FRich.FindText('guide', 0, -1, []) + 1);
  AssertTrue('the hand', FRich.PointerAt(p.X, p.Y) = crHandPoint);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MUp(mbLeft, [], p.X, p.Y);
  AssertEquals('the link''s click', 1, FClicks);
  // the bars as needed: none for the page, one for a long help text
  AssertFalse('the page fits: no bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
  s := '';
  for i := 1 to 100 do s := s + 'Topic ' + IntToStr(i) + LineEnding;
  FRich.Lines.Text := s;
  FRich.UpdateView;
  AssertTrue('a long help text: a bar', (FRich.VBar <> nil) and FRich.VBar.Visible);
end;

{ A home page: read-only, nothing to select, no caret, never focused, no bars, as tall as its
  content inside a scroll box that scrolls the whole page. }
procedure TTyRichDisplayTest.TestAHomePage;
var
  box: TScrollBox;
  bmp: TBitmap;
  p: TPoint;
begin
  box := TScrollBox.Create(nil);
  try
    box.SetBounds(0, 0, 420, 120);
    FRich.Parent := box;
    FRich.ReadOnly := True;
    FRich.AllowSelection := False;
    FRich.CaretWhenReadOnly := False;
    FRich.FocusOnClick := False;
    FRich.TabStop := False;
    FRich.ScrollBars := ssNone;
    FRich.AutoHeight := True;
    FRich.Focusable := True;
    FRich.OnLinkClick := @LinkClicked;
    LoadRtf(PageRtf);
    bmp := TBitmap.Create;
    try
      bmp.SetSize(30, 20);
      bmp.Canvas.Brush.Color := clRed;
      bmp.Canvas.FillRect(0, 0, 30, 20);
      AssertTrue('a picture', FRich.Document.Execute(TTyRichInsertPicture.Create(
        FRich.Document.Text.ParaStart(3), bmp)));
    finally
      bmp.Free;
    end;
    FRich.UpdateView;
    AssertEquals('as tall as its content', FRich.ContentHeight, FRich.Height);
    AssertFalse('exact', FRich.ContentSizeIsEstimate);
    AssertTrue('taller than the box: the box scrolls the page', FRich.Height > box.ClientHeight);
    AssertFalse('no bar of its own', (FRich.VBar <> nil) and FRich.VBar.Visible);
    AssertFalse('no horizontal bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
    FRich.ForceFocus := True;
    AssertEquals('no caret', 0, FRich.CaretInk);
    FRich.ForceFocus := False;
    p := PointIn(FRich.FindText('guide', 0, -1, []) + 1);
    FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
    FRich.MUp(mbLeft, [], p.X, p.Y);
    AssertEquals('the link''s click', 1, FClicks);
    AssertEquals('never focused', 0, FRich.FocusCalls);
    p := PointIn(2);
    FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
    FRich.MMove([ssLeft], p.X + 60, p.Y);
    FRich.MUp(mbLeft, [], p.X + 60, p.Y);
    AssertEquals('nothing selected', 0, FRich.SelLength);
    AssertTrue('the arrow over text', FRich.PointerAt(p.X, p.Y) = crDefault);
    // the box narrower: the page wraps and grows, once
    FRich.Width := 250;
    FRich.UpdateView;
    AssertEquals('narrower: still its content''s height', FRich.ContentHeight, FRich.Height);
    FRich.Parent := nil;
  finally
    box.Free;
  end;
end;

{ The two pages drawn with real fonts, off-screen, at 100 % and 150 %, light and dark - into
  TY_RICH_SHOTS when the environment names a folder (for a person to look at). }
procedure TTyRichDisplayTest.TestShotsOfBothPages;
var
  dir: string;
  names: TStringArray;
  i: Integer;

  procedure Shot(const AName: string; AHome: Boolean; APPI: Integer; ADark: Boolean);
  var
    r: TShotRich;
    shotBmp: TBGRABitmap;
    pic: TBitmap;
    st: TBytesStream;
    i: Integer;
    s: string;
  begin
    if ADark then FCtl.Mode := 'dark' else FCtl.Mode := 'light';
    FCtl.ThemeName := FDarkTheme;
    r := TShotRich.Create(nil);
    try
      r.Controller := FCtl;
      r.Font.PixelsPerInch := APPI;
      r.SetBounds(0, 0, MulDiv(420, APPI, 96), MulDiv(220, APPI, 96));
      r.ReadOnly := True;
      r.CaretWhenReadOnly := False;
      if AHome then
      begin
        r.AllowSelection := False;
        r.FocusOnClick := False;
        r.TabStop := False;
        r.ScrollBars := ssNone;
        r.AutoHeight := True;
      end;
      st := TBytesStream.Create(RawBytes(PageRtf));
      try
        r.LoadFromStream(st);
      finally
        st.Free;
      end;
      r.FinishLoading;
      pic := TBitmap.Create;
      try
        pic.SetSize(48, 32);
        pic.Canvas.Brush.Color := RGBToColor(40, 140, 220);
        pic.Canvas.FillRect(0, 0, 48, 32);
        pic.Canvas.Brush.Color := RGBToColor(250, 200, 40);
        pic.Canvas.Ellipse(14, 6, 34, 26);
        r.Document.Execute(TTyRichInsertPicture.Create(r.Document.Text.ParaStart(3), pic));
      finally
        pic.Free;
      end;
      if not AHome then
      begin
        // a help page: longer than its window, so its bar shows
        s := '';
        for i := 1 to 12 do s := s + LineEnding + 'Topic ' + IntToStr(i);
        r.Document.Execute(TTyRichInsertText.Create(r.Document.Text.Length, s));
      end;
      r.UpdateView;
      r.UpdateView;
      shotBmp := r.Shot(APPI);
      try
        shotBmp.SaveToFile(dir + AName);
      finally
        shotBmp.Free;
      end;
      if AHome then
        AssertEquals(AName + ': as tall as its content', r.ContentHeight, r.Height);
    finally
      r.Free;
    end;
  end;

begin
  dir := GetEnvironmentVariable('TY_RICH_SHOTS');
  if dir = '' then Ignore('no folder for the pictures (TY_RICH_SHOTS)');
  dir := IncludeTrailingPathDelimiter(dir);
  ForceDirectories(dir);
  TyRegisterBuiltinThemes;
  // the first built-in theme whose dark mode has light text (the default one may have none)
  FDarkTheme := '';
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
  begin
    FCtl.ThemeName := names[i];
    FCtl.Mode := 'dark';
    FRich.UpdateView;
    if FRich.Style.TextColor.green > 128 then
    begin
      FDarkTheme := names[i];
      Break;
    end;
  end;
  AssertTrue('a theme with a dark mode', FDarkTheme <> '');
  Shot('t7-home-100-light.png', True, 96, False);
  Shot('t7-home-150-light.png', True, 144, False);
  Shot('t7-home-100-dark.png', True, 96, True);
  Shot('t7-home-150-dark.png', True, 144, True);
  Shot('t7-help-100-light.png', False, 96, False);
  Shot('t7-help-150-light.png', False, 144, False);
  Shot('t7-help-100-dark.png', False, 96, True);
  Shot('t7-help-150-dark.png', False, 144, True);
  FCtl.Mode := 'light';
end;

{ The wheel over a home page reaches the scroll box: the page, as tall as its content in a
  TTyScrollBox (Align alTop, as the documentation sets it), has nothing to scroll - it does
  not take the wheel (the message answers 0, so the widgetset hands it to the parent) and the
  box scrolls. A help page takes it and scrolls - also at its end (a page never starts moving
  because an inner one stopped). Ctrl + wheel zooms on both. }
procedure TTyRichDisplayTest.TestTheWheelOverAHomePageIsTheBoxs;
var
  box: TBoxAccess;
  y: Int64;
begin
  box := TBoxAccess.Create(nil);
  try
    box.SetBounds(0, 0, 420, 120);
    FRich.Parent := box;
    FRich.ReadOnly := True;
    FRich.CaretWhenReadOnly := False;
    FRich.AllowSelection := False;
    FRich.FocusOnClick := False;
    FRich.TabStop := False;
    FRich.ScrollBars := ssNone;
    FRich.AutoHeight := True;
    FRich.Align := alTop;
    SetLongText(30);
    box.Align;
    FRich.UpdateView;
    // (the box's bar came with the page's height: the LCL aligns again)
    box.UpdateScrollbars;
    box.Align;
    FRich.UpdateView;
    AssertEquals('alTop in the box: its width', box.AlignWidth, FRich.Width);
    AssertEquals('as tall as its content', FRich.ContentHeight, FRich.Height);
    AssertTrue('taller than the box', FRich.Height > box.ClientHeight);
    AssertFalse('the page does not take the wheel', FRich.WheelTaken(-120, []));
    AssertEquals('and does not scroll', Int64(0), FRich.ScrollY);
    AssertEquals('the message answers 0: the parent''s', 0, FRich.WheelMessage(-120));
    AssertTrue('the box takes it', box.Wheel(-120));
    AssertTrue('and scrolls the page', box.ScrollY > 0);
    AssertTrue('Ctrl + wheel: still the zoom', FRich.WheelTaken(120, [ssCtrl]));
    AssertEquals('zoomed', 110, FRich.Zoom);
    FRich.Parent := nil;
  finally
    box.Free;
  end;
  // a help page: the wheel is its own, at its end too
  FRich.Align := alNone;
  FRich.AutoHeight := False;
  FRich.ScrollBars := ssBoth;
  FRich.Zoom := 100;
  FRich.SetBounds(0, 0, 300, 120);
  SetLongText(60);
  AssertTrue('a help page takes the wheel', FRich.WheelTaken(-120, []));
  AssertTrue('and scrolls', FRich.ScrollY > 0);
  AssertEquals('the message answers 1', 1, FRich.WheelMessage(-120));
  FRich.KeyOf(VK_END, [ssCtrl]);
  y := FRich.ScrollY;
  AssertTrue('at its end: still taken', FRich.WheelTaken(-120, []));
  AssertEquals('at its end: nothing moves', y, FRich.ScrollY);
  // content that fits: nothing to scroll, the parent's
  FRich.Lines.Text := 'short';
  FRich.UpdateView;
  AssertFalse('content that fits: not taken', FRich.WheelTaken(-120, []));
  AssertFalse('sideways, nothing wider: not taken', FRich.WheelHTaken(120));
end;

procedure TTyRichDisplayTest.MenuAsked(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  Inc(FMenusAsked);
end;

{ A page with nothing to edit or select (ReadOnly, AllowSelection False) shows no menu of the
  control's own - every item of it would be grey; OnContextPopup is still asked, and an
  application's PopupMenu is still the one shown (LCL's own). A help page keeps the text
  menu (Copy, Select All). }
procedure TTyRichDisplayTest.TestNoMenuOfItsOwnWithNothingToEditOrSelect;
var
  handled: Boolean;
  menu: TPopupMenu;
begin
  FRich.Lines.Text := 'Some text on a page';
  FRich.UpdateView;
  FRich.ReadOnly := True;
  FRich.AllowSelection := False;
  FRich.OnContextPopup := @MenuAsked;
  FMenusAsked := 0;
  FRich.MenuShows := 0;
  handled := FRich.PopupAt(10, 10);
  AssertEquals('OnContextPopup asked', 1, FMenusAsked);
  AssertEquals('no menu of its own', 0, FRich.MenuShows);
  AssertFalse('not handled: the LCL goes on (a PopupMenu, the parent)', handled);
  menu := TPopupMenu.Create(nil);
  try
    FRich.PopupMenu := menu;
    handled := FRich.PopupAt(10, 10);
    AssertEquals('with a PopupMenu: not ours either', 0, FRich.MenuShows);
    FRich.PopupMenu := nil;
  finally
    menu.Free;
  end;
  // a help page: selectable - the text menu (Copy, Select All)
  FRich.AllowSelection := True;
  handled := FRich.PopupAt(10, 10);
  AssertEquals('a help page: the text menu', 1, FRich.MenuShows);
  AssertTrue('handled', handled);
  // editable, nothing selectable: the menu too (Paste may be there)
  FRich.ReadOnly := False;
  FRich.AllowSelection := False;
  FRich.PopupAt(10, 10);
  AssertEquals('editable: the text menu', 2, FRich.MenuShows);
end;

{ AutoHeight sets nothing while the content's size is an estimate - a file still loading
  (read on demand): the height stays, the layout does not grow to the whole file, nothing
  raises; once the load is done and the size exact the height follows. And never above the
  limit: a page taller than CRichAutoHeightLimit keeps that height. }
procedure TTyRichDisplayTest.TestAutoHeightWaitsForAnExactSizeAndHasALimit;
var
  s: RawByteString;
  st: TMemoryStream;
  i, h0, steps: Integer;
begin
  FRich.SetBounds(0, 0, 300, 200);
  FRich.AutoHeight := True;
  s := '{' + #92 + 'rtf1' + #92 + 'ansi{' + #92 + 'fonttbl{' + #92 + 'f0 Arial;}}';
  for i := 1 to 600 do
    s := s + 'Paragraph ' + IntToStr(i) + ' with some words in it to make bytes.' + #92 + 'par ';
  s := s + '}';
  FRich.Slices(4 * 1024, 4 * 1024);
  st := TMemoryStream.Create;
  try
    st.WriteBuffer(s[1], Length(s));
    st.Position := 0;
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('still loading', FRich.Document.Loading);
  AssertTrue('an estimate', FRich.ContentSizeIsEstimate);
  h0 := FRich.Height;
  steps := 0;
  while FRich.Document.Loading and (steps < 200) do
  begin
    FRich.Step;
    FRich.UpdateView;
    Inc(steps);
    if FRich.Document.Loading then
    begin
      AssertEquals(Format('loading, step %d: the height stays', [steps]), h0, FRich.Height);
      AssertTrue(Format('step %d: no more laid out than the view shows', [steps]),
        FRich.Document.Text.MeasuredParaCount < FRich.Document.Text.ParaCount);
    end;
  end;
  AssertFalse('loaded', FRich.Document.Loading);
  FRich.UpdateView;
  FRich.ContentHeight;
  FRich.UpdateView;
  AssertFalse('exact now', FRich.ContentSizeIsEstimate);
  AssertEquals('exact: the height follows', FRich.ContentHeight, FRich.Height);
  // a page taller than the limit: the limit
  SetLongText(4000);
  FRich.UpdateView;
  AssertTrue('the content is taller than the limit', FRich.ContentHeight > CRichAutoHeightLimit);
  AssertEquals('the control at the limit', CRichAutoHeightLimit, FRich.Height);
  SetLongText(10);
  FRich.UpdateView;
  AssertEquals('short again: its height', FRich.ContentHeight, FRich.Height);
end;

{ Align alLeft or alRight gives the height to the parent: AutoHeight sets nothing (alClient
  and both vertical anchors are tested with the switch; the LCL anchors a side-aligned
  control top and bottom, so either rule alone keeps it). A change of PPI under AutoHeight: the
  height follows the content at the new PPI. }
procedure TTyRichDisplayTest.TestAutoHeightUnderAlignAndAtAnotherPPI;
var
  a: TAlign;
  h0: Integer;
begin
  SetLongText(12);
  for a in [alLeft, alRight] do
  begin
    FRich.AutoHeight := False;
    FRich.Align := a;
    FRich.SetBounds(0, 0, 300, 77);
    FRich.AutoHeight := True;
    FRich.UpdateView;
    AssertTrue('the LCL anchors a side-aligned control top and bottom', (akTop in FRich.Anchors) and
      (akBottom in FRich.Anchors));
    AssertTrue('the content is taller', FRich.ContentHeight > 77);
    AssertEquals('aligned to a side: the height is the parent''s', 77, FRich.Height);
  end;
  FRich.Align := alNone;
  FRich.UpdateView;
  AssertEquals('no align: the content''s', FRich.ContentHeight, FRich.Height);
  h0 := FRich.Height;
  FRich.Font.PixelsPerInch := 144;
  FRich.UpdateView;
  AssertTrue('144 PPI: taller', FRich.Height > h0);
  AssertEquals('144 PPI: the content''s', FRich.ContentHeight, FRich.Height);
  FRich.Font.PixelsPerInch := 96;
  FRich.UpdateView;
  AssertEquals('96 again', h0, FRich.Height);
end;

{ ContentWidth counts a vertical bar that shows (the width the control needs not to wrap
  under it): with the bar it is as much more as the text area is narrower - the bar lies over
  the padding on its side, so that is the bar's width beyond the padding. }
procedure TTyRichDisplayTest.TestTheContentWidthCountsAShownBar;
var
  wBar, wNone, aBar, aNone: Integer;
begin
  FRich.WrapMode := rwmNone;
  SetLongText(60);
  FRich.UpdateView;
  AssertTrue('a vertical bar shows', (FRich.VBar <> nil) and FRich.VBar.Visible);
  wBar := FRich.ContentWidth;
  aBar := FRich.Area.Right - FRich.Area.Left;
  FRich.ScrollBars := ssNone;
  FRich.UpdateView;
  AssertFalse('no bar now', (FRich.VBar <> nil) and FRich.VBar.Visible);
  wNone := FRich.ContentWidth;
  aNone := FRich.Area.Right - FRich.Area.Left;
  AssertTrue('the bar takes room from the text', aNone > aBar);
  AssertEquals('the content width: that much more with the bar', aNone - aBar, wBar - wNone);
end;

initialization
  RegisterTest(TTyRichDisplayTest);

end.
