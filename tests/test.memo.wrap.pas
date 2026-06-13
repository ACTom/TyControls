unit test.memo.wrap;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, LCLType, LazUTF8,
  BGRABitmap, BGRABitmapTypes, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ScrollBar, tyControls.Memo;
type
  { Probe subclass exposing the wrap-render surface for headless pixel tests.
    WordWrap=True draws one TTyVisualRow segment per painted row; the wrap point
    must match the draw clip (ContentRect.Right - SBWidth). Everything is pure
    measurement + an offscreen RenderTo into a TBitmap, then read back as BGRA. }
  TTyMemoWrapProbe = class(TTyMemo)
  public
    procedure ProbeSetWordWrap(AValue: Boolean);
    function ProbeWordWrap: Boolean;
    function ProbeLineHeight(APPI: Integer): Integer;
    function ProbeContentWidthFor(APPI: Integer): Integer;
    function ProbeTotalVisualRows(APPI: Integer): Integer;
    function ProbeVisibleRows: Integer;
    function ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
    function ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    procedure ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    // The embedded vertical scrollbar (nil until first overflow), found by type.
    function ProbeScrollBar: TTyScrollBar;
    // Device-px width subtracted for a visible scrollbar (0 when hidden); the
    // SAME term RenderTo uses to clip the row and ContentWidthFor uses to wrap.
    function ProbeSBWidth(APPI: Integer): Integer;
    procedure ProbeUpdateScrollBar;
    procedure ProbeInvalidateVisualRows;
    // Force the SINGLE-CALL hidden->visible flip: hide the bar (if it exists),
    // invalidate the row cache so the next build runs at the WIDE (no-scrollbar)
    // content width, then call UpdateScrollBar exactly once. This reproduces the
    // SBWidth-feedback path in isolation (no prior convergence call), so the range
    // it leaves must already cover every settled (narrow-width) visual row.
    procedure ProbeForceHiddenThenUpdateOnce;
  end;

  TTyMemoWrapTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoWrapProbe;
    procedure SetUpMemo(const ACss: string; AWidth, AHeight: Integer);
    procedure LoadLines(const AItems: array of string);
    // Render the memo into a fresh black-cleared bitmap of its current bounds and
    // return it as a BGRA bitmap the caller must free.
    function RenderToBGRA(AWidth, AHeight: Integer): TBGRABitmap;
    // True if any pixel in horizontal band [X0..X1] at row Y is "light" (all
    // channels above AThresh) — i.e. text glyphs painted there over a dark bg.
    function BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
  protected
    procedure TearDown; override;
  published
    procedure TestWrapDrawsTwoRowsForOneLogicalLine;  // (a)
    procedure TestNoGlyphPastContentRightMinusSB;      // (b)
    procedure TestOverLongTokenCharBreaksAcrossRows;   // (c)
    procedure TestToggleWrapReflowsThenRestores;       // (d)
    procedure TestSingleFlipScrollbarRangeCoversAllRows; // (e)
    procedure TestFirstCreationScrollbarRangeCoversAllRows; // (e2)
  end;

implementation

{ TTyMemoWrapProbe }

procedure TTyMemoWrapProbe.ProbeSetWordWrap(AValue: Boolean);
begin
  WordWrap := AValue;
end;

function TTyMemoWrapProbe.ProbeWordWrap: Boolean;
begin
  Result := WordWrap;
end;

function TTyMemoWrapProbe.ProbeLineHeight(APPI: Integer): Integer;
begin
  Result := LineHeight(APPI);
end;

function TTyMemoWrapProbe.ProbeContentWidthFor(APPI: Integer): Integer;
begin
  Result := ContentWidthFor(APPI);
end;

function TTyMemoWrapProbe.ProbeTotalVisualRows(APPI: Integer): Integer;
begin
  Result := TotalVisualRows(APPI);
end;

function TTyMemoWrapProbe.ProbeVisibleRows: Integer;
begin
  Result := VisibleRows;
end;

function TTyMemoWrapProbe.ProbeBuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
begin
  Result := BuildVisualRows(AContentWidth, APPI);
end;

function TTyMemoWrapProbe.ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
begin
  Result := MeasureLineWidths(ALine, APPI);
end;

procedure TTyMemoWrapProbe.ProbeRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TTyMemoWrapProbe.ProbeScrollBar: TTyScrollBar;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyScrollBar then
    begin
      Result := TTyScrollBar(Controls[i]);
      Exit;
    end;
end;

function TTyMemoWrapProbe.ProbeSBWidth(APPI: Integer): Integer;
var
  SB: TTyScrollBar;
begin
  SB := ProbeScrollBar;
  if (SB <> nil) and SB.Visible then
    Result := MulDiv(12, APPI, 96)
  else
    Result := 0;
end;

procedure TTyMemoWrapProbe.ProbeUpdateScrollBar;
begin
  UpdateScrollBar;
end;

procedure TTyMemoWrapProbe.ProbeInvalidateVisualRows;
begin
  InvalidateVisualRows;
end;

procedure TTyMemoWrapProbe.ProbeForceHiddenThenUpdateOnce;
var
  SB: TTyScrollBar;
begin
  SB := ProbeScrollBar;
  if SB <> nil then
    SB.Visible := False;           // pretend the bar was hidden going in
  InvalidateVisualRows;            // next build runs at the WIDE content width
  UpdateScrollBar;                 // single hidden->visible flip (the SBWidth path)
end;

{ TTyMemoWrapTest }

procedure TTyMemoWrapTest.SetUpMemo(const ACss: string; AWidth, AHeight: Integer);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FMemo := TTyMemoWrapProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;   // pin 96; macOS default is 72
  FMemo.SetBounds(0, 0, AWidth, AHeight);
end;

procedure TTyMemoWrapTest.LoadLines(const AItems: array of string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    for i := Low(AItems) to High(AItems) do
      L.Add(AItems[i]);
    FMemo.Lines := L;
  finally
    L.Free;
  end;
end;

function TTyMemoWrapTest.RenderToBGRA(AWidth, AHeight: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AWidth, AHeight);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, AWidth, AHeight);
    FMemo.ProbeRenderTo(Bmp.Canvas, Rect(0, 0, AWidth, AHeight), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

function TTyMemoWrapTest.BandHasLightPixel(ABmp: TBGRABitmap; Y, X0, X1, AThresh: Integer): Boolean;
var
  x: Integer;
  Px: TBGRAPixel;
begin
  Result := False;
  if (Y < 0) or (Y >= ABmp.Height) then Exit;
  if X0 < 0 then X0 := 0;
  if X1 >= ABmp.Width then X1 := ABmp.Width - 1;
  for x := X0 to X1 do
  begin
    Px := ABmp.GetPixel(x, Y);
    if (Px.red > AThresh) and (Px.green > AThresh) and (Px.blue > AThresh) then
      Exit(True);
  end;
end;

procedure TTyMemoWrapTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

// (a) WordWrap=True, narrow memo: a long logical line 'one two three four five'
// renders across >= 2 VISUAL ROWS — light-pixel text bands at BOTH y=ContentTop
// (row 0) AND y=ContentTop+LH (row 1), proving ONE logical line occupies two
// rows. Padding 0 so ContentTop = 0 and content width == control width.
procedure TTyMemoWrapTest.TestWrapDrawsTwoRowsForOneLogicalLine;
var
  Reread: TBGRABitmap;
  Rows: TTyVisualRowArray;
  Line: string;
  W: TTyIntArray;
  LH, CW, Y0, Y1, ContentTop: Integer;
begin
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }',
    200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line := 'one two three four five';
  LoadLines([Line]);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  // Content width fitting only part of the line -> forces a wrap into >= 2 rows.
  CW := (W[7] + W[High(W)]) div 2;
  FMemo.SetBounds(0, 0, CW, 120);    // control width == content width (padding 0)
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('setup: one logical line wraps into >= 2 visual rows', Length(Rows) >= 2);
  AssertEquals('setup: both wrapped rows belong to logical line 0',
    Rows[0].Line, Rows[1].Line);
  LH := FMemo.ProbeLineHeight(96);
  ContentTop := 0;                   // padding 0
  Reread := RenderToBGRA(CW, 120);
  try
    Y0 := ContentTop + LH div 2;          // row 0 mid-band
    Y1 := ContentTop + LH + (LH div 2);   // row 1 mid-band (continuation)
    AssertTrue('row 0 (logical line 0, segment 0) drew text at y=ContentTop',
      BandHasLightPixel(Reread, Y0, 0, CW - 1, 120));
    AssertTrue('row 1 (logical line 0, segment 1) drew text at y=ContentTop+LH',
      BandHasLightPixel(Reread, Y1, 0, CW - 1, 120));
  finally
    Reread.Free;
  end;
end;

// (b) No glyph paints past ContentRect.Right - SBWidth: with a long single line
// wrapping into MANY rows (so the vertical scrollbar appears), the wrap point
// must agree with the draw clip. Assert the gutter band
// [ContentRight - SBWidth .. ContentRight] has NO light pixel on any visible row
// (text never spills under/over the scrollbar). This is the SBWidth-feedback
// guard: BuildVisualRows must wrap at the SAME right edge RenderTo clips to.
procedure TTyMemoWrapTest.TestNoGlyphPastContentRightMinusSB;
var
  Reread: TBGRABitmap;
  Rows: TTyVisualRowArray;
  Wd: TTyIntArray;
  Line: string;
  i, LH, W, H, SBWidth, ContentWidth, ContentRight, GutterX0, GutterX1: Integer;
  y, row, VR, Total, SegWidth, MaxSegWidth: Integer;
  SB: TTyScrollBar;
  AnyLightInGutter: Boolean;
begin
  // Padding 0: ContentRect = full rect, ContentRight = control width.
  W := 160;
  H := 120;
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }',
    W, H);
  FMemo.ProbeSetWordWrap(True);
  // One very long no-space token: it CHAR-breaks, so every wrapped segment packs
  // right up to the content-right edge (word-wrap would leave slack and never
  // reach the gutter). This makes the SBWidth-feedback bug observable: if the
  // wrap width and the draw clip disagree by SBWidth, a segment's drawn width
  // exceeds ContentRight-SBWidth and the last glyph spills into the gutter. The
  // token is long enough to wrap past the visible height so the scrollbar shows.
  Line := '';
  for i := 0 to 199 do
    Line := Line + 'X';
  LoadLines([Line]);
  // Render so the scrollbar materialises and the row cache settles at the
  // narrowed (post-scrollbar) content width — the same path Paint takes.
  Reread := RenderToBGRA(W, H);
  try
    SB := FMemo.ProbeScrollBar;
    AssertTrue('setup: vertical scrollbar created for the wrapped overflow', SB <> nil);
    AssertTrue('setup: vertical scrollbar is visible', SB.Visible);
    SBWidth := FMemo.ProbeSBWidth(96);
    AssertTrue('setup: SBWidth > 0', SBWidth > 0);
    Total := FMemo.ProbeTotalVisualRows(96);   // rows at the SETTLED narrow width
    VR := FMemo.ProbeVisibleRows;
    AssertTrue('setup: wraps to more rows than fit', Total > VR);

    // --- Deterministic invariant 1: the wrap width fed to BuildVisualRows is the
    // narrowed (post-scrollbar) content width, so EVERY wrapped segment's drawn
    // pixel width is <= the content width == the clip width (ContentRight-SBWidth).
    // If the wrap used the wider pre-scrollbar width, some segment would exceed it.
    ContentWidth := FMemo.ProbeContentWidthFor(96);
    AssertEquals('wrap width == ContentRight - SBWidth (padding 0)',
      W - SBWidth, ContentWidth);
    Rows := FMemo.ProbeBuildVisualRows(ContentWidth, 96);
    Wd := FMemo.ProbeMeasureLineWidths(Line, 96);
    MaxSegWidth := 0;
    for i := 0 to High(Rows) do
    begin
      SegWidth := Wd[Rows[i].EndCol] - Wd[Rows[i].StartCol];
      if SegWidth > MaxSegWidth then MaxSegWidth := SegWidth;
    end;
    AssertTrue('every wrapped segment fits within the content width (no overrun)',
      MaxSegWidth <= ContentWidth);

    // --- Deterministic invariant 2: the scrollbar range covers ALL settled rows
    // (Max == Total - VR). If the range were computed at the pre-scrollbar wider
    // width it would be too small and the last rows could not scroll into view.
    AssertEquals('scrollbar Max covers all settled visual rows (Total - VR)',
      Total - VR, SB.Max);

    // --- Pixel guard: no glyph paints in the [ContentRight-SBWidth .. mid-SB]
    // gutter on any visible row (text never spills under the scrollbar).
    LH := FMemo.ProbeLineHeight(96);
    ContentRight := W;                       // padding 0
    GutterX0 := ContentRight - SBWidth + 1;
    GutterX1 := ContentRight - SBWidth + (SBWidth div 2);
    AnyLightInGutter := False;
    for row := 0 to (H div LH) do
    begin
      y := row * LH + LH div 2;
      if y >= H then Break;
      if BandHasLightPixel(Reread, y, GutterX0, GutterX1, 120) then
        AnyLightInGutter := True;
    end;
    AssertFalse('no glyph paints in the [ContentRight-SBWidth .. ContentRight] gutter',
      AnyLightInGutter);
  finally
    Reread.Free;
  end;
end;

// (c) Char-break: a 30-char no-space token occupies MULTIPLE visual rows. Assert
// >= 2 rows for the single token AND that light-pixel text appears in both row 0
// and row 1 bands (the continuation chunk is drawn, not clipped away).
procedure TTyMemoWrapTest.TestOverLongTokenCharBreaksAcrossRows;
var
  Reread: TBGRABitmap;
  Rows: TTyVisualRowArray;
  Line: string;
  i, LH, CW, Y0, Y1: Integer;
begin
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }',
    200, 120);
  FMemo.ProbeSetWordWrap(True);
  Line := '';
  for i := 1 to 30 do
    Line := Line + 'X';              // 30-char no-space token
  LoadLines([Line]);
  // Narrow content so the token cannot fit on one row (forces char-break).
  CW := 60;
  FMemo.SetBounds(0, 0, CW, 120);
  Rows := FMemo.ProbeBuildVisualRows(CW, 96);
  AssertTrue('30-char token char-breaks into >= 2 rows', Length(Rows) >= 2);
  AssertEquals('all wrapped rows belong to the single logical line 0',
    0, Rows[High(Rows)].Line);
  LH := FMemo.ProbeLineHeight(96);
  Reread := RenderToBGRA(CW, 120);
  try
    Y0 := LH div 2;
    Y1 := LH + (LH div 2);
    AssertTrue('token row 0 drew text', BandHasLightPixel(Reread, Y0, 0, CW - 1, 120));
    AssertTrue('token continuation drew in row 1 band',
      BandHasLightPixel(Reread, Y1, 0, CW - 1, 120));
  finally
    Reread.Free;
  end;
end;

// (d) Toggling WordWrap False -> True -> False reflows then RESTORES: with a long
// line, WordWrap=False is a single visual row (the rest clipped at the right
// edge); True wraps it into >= 2 rows; toggling back to False restores exactly
// one visual row again (single clipped row). Asserts TotalVisualRows for the one
// long line flips 1 -> N -> 1, and the row-1 band has text only while wrapped.
procedure TTyMemoWrapTest.TestToggleWrapReflowsThenRestores;
var
  Reread: TBGRABitmap;
  Line: string;
  W: TTyIntArray;
  LH, CW, Y1, TotalOff1, TotalOn, TotalOff2: Integer;
begin
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }',
    200, 120);
  Line := 'one two three four five six seven';
  LoadLines([Line]);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  CW := (W[7] + W[High(W)]) div 2;
  FMemo.SetBounds(0, 0, CW, 120);
  LH := FMemo.ProbeLineHeight(96);
  Y1 := LH + (LH div 2);             // row 1 continuation band

  // --- WordWrap=False: ONE visual row for the one logical line (clipped). ---
  FMemo.ProbeSetWordWrap(False);
  TotalOff1 := FMemo.ProbeTotalVisualRows(96);
  AssertEquals('off: one long logical line == one visual row', 1, TotalOff1);
  Reread := RenderToBGRA(CW, 120);
  try
    AssertFalse('off: no continuation text in the row-1 band (single clipped row)',
      BandHasLightPixel(Reread, Y1, 0, CW - 1, 120));
  finally
    Reread.Free;
  end;

  // --- WordWrap=True: REFLOWS into >= 2 visual rows; row 1 now has text. ---
  FMemo.ProbeSetWordWrap(True);
  TotalOn := FMemo.ProbeTotalVisualRows(96);
  AssertTrue('on: long line reflows into >= 2 visual rows', TotalOn >= 2);
  Reread := RenderToBGRA(CW, 120);
  try
    AssertTrue('on: continuation text drew in the row-1 band',
      BandHasLightPixel(Reread, Y1, 0, CW - 1, 120));
  finally
    Reread.Free;
  end;

  // --- WordWrap=False again: RESTORES to a single clipped row. ---
  FMemo.ProbeSetWordWrap(False);
  TotalOff2 := FMemo.ProbeTotalVisualRows(96);
  AssertEquals('off again: restores to one visual row', 1, TotalOff2);
  Reread := RenderToBGRA(CW, 120);
  try
    AssertFalse('off again: row-1 band empty again (single clipped row restored)',
      BandHasLightPixel(Reread, Y1, 0, CW - 1, 120));
  finally
    Reread.Free;
  end;
end;

// (e) SBWidth feedback in a SINGLE UpdateScrollBar call: when the vertical bar
// flips hidden->visible, it steals SBWidth from the content width, which narrows
// the WordWrap=True layout into MORE rows than the (wider) pre-scrollbar count.
// The bar's Max must cover EVERY settled (narrow-width) row after that one call —
// otherwise the last wrapped rows can never scroll into view. ProbeForceHidden-
// ThenUpdateOnce reproduces the flip with no prior convergence call, so this
// fails if UpdateScrollBar sizes the range from the wide pre-scrollbar Total.
procedure TTyMemoWrapTest.TestSingleFlipScrollbarRangeCoversAllRows;
var
  Line: string;
  i, W, H, VR, TotalNarrow, SBWidth: Integer;
  SB: TTyScrollBar;
begin
  W := 160;
  H := 120;
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }',
    W, H);
  FMemo.ProbeSetWordWrap(True);
  // Long no-space token so the wrap count is SENSITIVE to the SBWidth narrowing
  // (each removed pixel can push another char onto a new row).
  Line := '';
  for i := 0 to 199 do
    Line := Line + 'X';
  LoadLines([Line]);
  // Isolate the single hidden->visible flip (no prior convergence).
  FMemo.ProbeForceHiddenThenUpdateOnce;
  SB := FMemo.ProbeScrollBar;
  AssertTrue('flip: scrollbar exists', SB <> nil);
  AssertTrue('flip: scrollbar visible after the single flip', SB.Visible);
  SBWidth := FMemo.ProbeSBWidth(96);
  AssertTrue('flip: SBWidth > 0', SBWidth > 0);
  // Rows the model actually has at the SETTLED (post-flip, narrow) content width.
  TotalNarrow := FMemo.ProbeTotalVisualRows(96);
  VR := FMemo.ProbeVisibleRows;
  AssertTrue('flip: still overflows after narrowing', TotalNarrow > VR);
  // The single-call range must already account for the narrowed wrap.
  AssertEquals('flip: scrollbar Max == settled TotalVisualRows - VisibleRows',
    TotalNarrow - VR, SB.Max);
end;

// (e2) The GENUINE first-ever creation flip: the scrollbar does NOT exist going
// into the layout (FScrollBar=nil), so this exercises the path test (e) cannot —
// (e) hides an ALREADY-created bar before flipping, so WasVisible is genuinely
// False there regardless of how the code reads it. Here the bar is created inside
// the very first UpdateScrollBar (driven by assigning Lines on a fresh memo).
// TControl.Visible defaults to True, so a flip detector that reads Visible AFTER
// creation would treat this as "already visible", skip the narrow rebuild, and
// size Max from the WIDE pre-scrollbar Total — undersized by exactly the rows the
// stolen SBWidth pushes off-screen (the last wrapped row can never scroll in).
// The fix captures WasVisible BEFORE creating the bar (nil == previously-hidden),
// so the range must cover EVERY settled narrow-width row after that single call.
procedure TTyMemoWrapTest.TestFirstCreationScrollbarRangeCoversAllRows;
var
  Line: string;
  i, W, H, VR, TotalNarrow, SBWidth: Integer;
  SB: TTyScrollBar;
begin
  W := 160;
  H := 120;
  SetUpMemo('TyMemo { background:#101010; color:#F0F0F0; border-width:0px; padding:0px; font-size:14px; }',
    W, H);
  FMemo.ProbeSetWordWrap(True);
  // Long no-space token so the wrap count is SENSITIVE to the SBWidth narrowing.
  Line := '';
  for i := 0 to 199 do
    Line := Line + 'X';
  // FIRST creation: no scrollbar exists before this; assigning Lines runs
  // SetLines -> UpdateScrollBar with FScrollBar=nil exactly once.
  AssertTrue('first-creation: no scrollbar exists beforehand',
    FMemo.ProbeScrollBar = nil);
  LoadLines([Line]);
  SB := FMemo.ProbeScrollBar;
  AssertTrue('first-creation: scrollbar created', SB <> nil);
  AssertTrue('first-creation: scrollbar visible', SB.Visible);
  SBWidth := FMemo.ProbeSBWidth(96);
  AssertTrue('first-creation: SBWidth > 0', SBWidth > 0);
  // Rows the model actually has at the SETTLED (narrow, scrollbar-visible) width.
  TotalNarrow := FMemo.ProbeTotalVisualRows(96);
  VR := FMemo.ProbeVisibleRows;
  AssertTrue('first-creation: still overflows after narrowing', TotalNarrow > VR);
  // Without the fix this is undersized by the SBWidth-induced extra row(s).
  AssertEquals('first-creation: scrollbar Max == settled TotalVisualRows - VisibleRows',
    TotalNarrow - VR, SB.Max);
end;

initialization
  RegisterTest(TTyMemoWrapTest);
end.
