unit test.richedit.display;

{ TTyRichEdit as a page: a help page (read-only, selectable and copyable, no caret, links on a
  plain click, bars as needed) and a home page (read-only, nothing to select, no caret, never
  focused, no bars, as tall as its content inside a scroll box). Each switch alone -
  ReadOnlyCaret, FocusOnClick, AllowSelection, ScrollBars, AutoHeight - the content's size
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
  LCLType, BGRABitmap, BGRABitmapTypes, BGRAWritePNG,
  tyControls.Controller, tyControls.ScrollBar, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
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
    FDarkTheme: string;
    FInPaint: Boolean;
    FInPaintEvents: Integer;
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
  AssertTrue('ReadOnlyCaret', FRich.ReadOnlyCaret);
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
  FRich.ReadOnlyCaret := False;
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
  FRich.Wheel(-120, []);
  AssertTrue('the wheel still scrolls', FRich.ScrollY > 0);
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
  FRich.WheelH(120);
  AssertTrue('the horizontal wheel still scrolls', FRich.ScrollX > 0);
  FRich.UpdateView;
  AssertTrue('... and stays scrolled with no bar', FRich.ScrollX > 0);
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
  FRich.ReadOnlyCaret := False;
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
    FRich.ReadOnlyCaret := False;
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
      r.ReadOnlyCaret := False;
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

initialization
  RegisterTest(TTyRichDisplayTest);

end.
