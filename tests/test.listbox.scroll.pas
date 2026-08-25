unit test.listbox.scroll;
{$mode objfpc}{$H+}
{ Two capabilities that had to land together, and the guards for each.

  ScrollWidth + horizontal scrolling (LCL stdctrls.pp:676/:721, customlistbox.inc:253-274):
  a row wider than the box could not be read at all. A scrolling container owes three
  separate things, and each is a separate test below -- the gutter comes off the OTHER
  axis's viewport, the row extends along the scrolled axis to the CONTENT width, and the
  origin follows the offset. Missing any one of them leaves a list that looks like it
  scrolls and does not.

  RowHeight -- the per-row height seam (LCL's OnMeasureItem / lbOwnerDrawVariable). The row
  loop lives in TTyListBox.RenderTo and every geometry function derived from ONE ItemHeight,
  so nothing above could have per-row heights until this existed. What the tests pin is that
  all FIVE derived quantities went through the seam, not just the paint: a hit test still
  reading a uniform height puts the click on the wrong row of a list that paints correctly. }
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ListBox, tyControls.ScrollBar;

type
  { Reaches the protected geometry so a claim can be pinned on the numbers the PAINT uses,
    not on a property that merely stored something. }
  TScrollAccess = class(TTyListBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallUpdateScrollBar;
    function ContentBounds(AWidth, APPI: Integer): TRect;   // Left/Right in .Left/.Right
    function CallRowAtY(AY: Integer): Integer;
    function CallContentTopOffset: Integer;
    function Offset: Integer;
    procedure SetOffset(AValue: Integer);
    function Wheel(Shift: TShiftState; ADelta: Integer): Boolean;
    function HBar: TTyScrollBar;
    function VBar: TTyScrollBar;
  end;

  { Rows 0 and 2 are TALL, row 1 and everything else is short -- an alternating pattern, so
    a formula that quietly kept using one height lands on the wrong row rather than
    accidentally agreeing. }
  TVariableRowList = class(TTyListBox)
  public
    Asked: Integer;
    function RowHeight(AIndex: Integer): Integer; override;
    function CallRowAtY(AY: Integer): Integer;
    function CallContentTopOffset: Integer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { Answers 0 for every row -- the shape a handler with one branch missing returns. }
  TZeroRowList = class(TTyListBox)
  public
    function RowHeight(AIndex: Integer): Integer; override;
  end;

  { SHORT rows at the top, TALL ones at the bottom. The shape that separates "count forward
    from where we are" from "count backward from the row we must reveal": six short rows fit
    at the top, only two tall ones fit at the bottom, so a scroll-into-view that reuses the
    forward count lands four rows too high and leaves its target off the edge. }
  TTopHeavyRowList = class(TTyListBox)
  public
    function RowHeight(AIndex: Integer): Integer; override;
  end;

  { Paints a solid marker at the row's LEADING edge and another at its TRAILING edge, so a
    render can be asked where the row actually starts and ends. Edges, never centres: a
    centre probe survives every origin drift that has shipped here. }
  TEdgeMarkList = class(TTyListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TListBoxHScrollTest = class(TTestCase)
  private
    FForm: TForm;
    function MakeList(AScrollWidth: Integer): TScrollAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestScrollWidthDefaultsOffAndBuildsNoBar;
    procedure TestExtentNarrowerThanTheBoxIsInert;
    procedure TestExtentWiderThanTheBoxRaisesTheBar;
    procedure TestBarRangeIsTheOverhang;
    procedure TestOriginFollowsTheOffset;
    procedure TestRowExtendsToTheContentWidth;
    procedure TestHorizontalGutterComesOffTheRowCount;
    procedure TestOffsetClampsToTheOverhang;
    procedure TestNarrowingTheExtentPullsTheViewBack;
    procedure TestShiftWheelScrollsSideways;
    procedure TestPlainWheelStillScrollsVertically;
    procedure TestRightToLeftSlidesFromTheOtherEdge;
    procedure TestScrolledRowContentActuallyMoves;
  end;

  TListBoxVariableRowTest = class(TTestCase)
  private
    FForm: TForm;
    function MakeList: TVariableRowList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestUniformListIsUnchangedByTheSeam;
    procedure TestItemRectUsesEachRowsOwnHeight;
    procedure TestRowAtYUsesEachRowsOwnHeight;
    procedure TestVisibleRowsCountsRealHeights;
    procedure TestMaxTopIndexCountsFromTheLastRow;
    procedure TestPaintedRowsMatchItemRect;
    procedure TestZeroHeightAnswerCannotHangThePaint;
    procedure TestScrollIntoViewRevealsTheRowItWasAskedFor;
  end;

  { The two-truths bug TTyMemo just had, on the list box: ViewportHeight counted rows
    against the control's FULL height while RenderTo lays them into the padding-inset
    content area. Every other test here runs the environment theme, whose 2px padding
    happens to leave 100px boxes on exact row boundaries -- these run the product shape
    (4px padding) at heights where the two formulas actually disagree. }
  TListBoxPaddingTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMaxTopIndexRespectsPadding;
    procedure TestScrollBarAppearsWhenPaddingOverflowsTheRows;
  end;

implementation

const
  Tall  = 40;
  Short = 16;
  MarkW = 3;

{ TScrollAccess }

procedure TScrollAccess.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

procedure TScrollAccess.CallUpdateScrollBar;
begin UpdateScrollBar; end;

function TScrollAccess.ContentBounds(AWidth, APPI: Integer): TRect;
var l, r: Integer;
begin
  RowContentBounds(AWidth, APPI, l, r);
  Result := Rect(l, 0, r, 0);
end;

function TScrollAccess.CallRowAtY(AY: Integer): Integer;
begin Result := RowAtY(AY); end;

function TScrollAccess.CallContentTopOffset: Integer;
begin Result := ContentTopOffset; end;

function TScrollAccess.Offset: Integer;
begin Result := HScrollOffset; end;

procedure TScrollAccess.SetOffset(AValue: Integer);
begin HScrollOffset := AValue; end;

function TScrollAccess.Wheel(Shift: TShiftState; ADelta: Integer): Boolean;
begin Result := DoMouseWheel(Shift, ADelta, Point(0, 0)); end;

function TScrollAccess.HBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbHorizontal) then
      Exit(TTyScrollBar(Components[i]));
end;

function TScrollAccess.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Components[i]));
end;

{ TVariableRowList }

function TVariableRowList.RowHeight(AIndex: Integer): Integer;
begin
  Inc(Asked);
  { Even indices tall, odd short -- and the SAME answer past the end of the list, because
    the row walkers count past it on purpose (an empty box still reports how many rows fit). }
  if AIndex mod 2 = 0 then Result := Tall else Result := Short;
end;

function TVariableRowList.CallRowAtY(AY: Integer): Integer;
begin Result := RowAtY(AY); end;

function TVariableRowList.CallContentTopOffset: Integer;
begin Result := ContentTopOffset; end;

procedure TVariableRowList.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

function TZeroRowList.RowHeight(AIndex: Integer): Integer;
begin
  Result := 0;
end;

function TTopHeavyRowList.RowHeight(AIndex: Integer): Integer;
begin
  if AIndex < 6 then Result := 10 else Result := 45;
end;

{ TEdgeMarkList }

procedure TEdgeMarkList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  f: TTyFill;
begin
  { A hard green block on each END of the row. Where they land IS the row's origin and its
    far edge, which is exactly what horizontal scrolling moves; nothing about the text or
    the fill can stand in for that. }
  f := Default(TTyFill);
  f.Kind := tfkSolid;
  f.Color := TTyColor($FF00C800);
  P.FillBackground(Rect(ARowRect.Left, ARowRect.Top + 2,
    ARowRect.Left + MarkW, ARowRect.Bottom - 2), f, 0);
  P.FillBackground(Rect(ARowRect.Right - MarkW, ARowRect.Top + 2,
    ARowRect.Right, ARowRect.Bottom - 2), f, 0);
end;

procedure TEdgeMarkList.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

function IsGreen(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 140) and (P.green > P.red + 40) and (P.green > P.blue + 40);
end;

{ The x of the FIRST green pixel on row-0's mid-line, or -1. }
function FirstGreenX(ABmp: TBitmap; AY, AW: Integer): Integer;
var
  Img: TBGRABitmap;
  x: Integer;
begin
  Result := -1;
  Img := TBGRABitmap.Create(ABmp);
  try
    for x := 0 to AW - 1 do
      if IsGreen(Img.GetPixel(x, AY)) then Exit(x);
  finally Img.Free; end;
end;

function LastGreenX(ABmp: TBitmap; AY, AW: Integer): Integer;
var
  Img: TBGRABitmap;
  x: Integer;
begin
  Result := -1;
  Img := TBGRABitmap.Create(ABmp);
  try
    for x := AW - 1 downto 0 do
      if IsGreen(Img.GetPixel(x, AY)) then Exit(x);
  finally Img.Free; end;
end;

{ =================== horizontal scrolling ============================================= }

procedure TListBoxHScrollTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TListBoxHScrollTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TListBoxHScrollTest.MakeList(AScrollWidth: Integer): TScrollAccess;
begin
  Result := TScrollAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Font.PixelsPerInch := 96;
  Result.ItemHeight := 24;
  Result.SetBounds(0, 0, 160, 100);
  Result.Items.Add('one'); Result.Items.Add('two'); Result.Items.Add('three');
  Result.ScrollWidth := AScrollWidth;
  Result.CallUpdateScrollBar;
end;

procedure TListBoxHScrollTest.TestScrollWidthDefaultsOffAndBuildsNoBar;
var l: TScrollAccess;
begin
  l := MakeList(0);
  AssertEquals('ScrollWidth defaults to LCL''s 0', 0, l.ScrollWidth);
  AssertNull('no horizontal bar is built for a list that never asked for one', l.HBar);
  AssertEquals('and nothing is scrolled', 0, l.Offset);
end;

procedure TListBoxHScrollTest.TestExtentNarrowerThanTheBoxIsInert;
var l: TScrollAccess; b: TRect;
begin
  { A row is never NARROWER than the box it is painted in, so an extent below the box width
    must change nothing at all -- not the bar, not the row bounds. }
  l := MakeList(40);
  AssertNull('an extent inside the box raises no bar', l.HBar);
  b := l.ContentBounds(160, 96);
  AssertTrue('and the row still spans the box', b.Right - b.Left > 40);
end;

procedure TListBoxHScrollTest.TestExtentWiderThanTheBoxRaisesTheBar;
var l: TScrollAccess;
begin
  l := MakeList(400);
  AssertNotNull('an extent past the box raises the bar', l.HBar);
  AssertTrue('and it is visible', l.HBar.Visible);
  AssertTrue('docked along the bottom', l.HBar.Align = alBottom);
  AssertFalse('an embedded bar never takes focus off the list', l.HBar.TabStop);
end;

procedure TListBoxHScrollTest.TestBarRangeIsTheOverhang;
var l: TScrollAccess; b: TRect; viewW: Integer;
begin
  { The bar's range must be the part of the content that does NOT fit -- measured against
    the row area AFTER the vertical bar's gutter, not against the raw control width. Read
    it back from the same bounds the paint uses so the two cannot state different widths. }
  l := MakeList(400);
  b := l.ContentBounds(160, 96);
  viewW := l.HBar.PageSize;
  AssertTrue('the page is one screenful of row', viewW > 0);
  AssertEquals('the range is exactly the overhang', 400 - viewW, l.HBar.Max);
  AssertEquals('starting at zero', 0, l.HBar.Min);
  AssertTrue('one arrow click moves a line of text, not a pixel', l.HBar.SmallChange > 1);
end;

procedure TListBoxHScrollTest.TestOriginFollowsTheOffset;
var l: TScrollAccess; b0, b1: TRect;
begin
  { Obligation three. Without it the bar moves and the rows do not. }
  l := MakeList(400);
  b0 := l.ContentBounds(160, 96);
  l.SetOffset(37);
  AssertEquals('the offset was taken', 37, l.Offset);
  b1 := l.ContentBounds(160, 96);
  AssertEquals('the row origin slid by exactly the offset', b0.Left - 37, b1.Left);
end;

procedure TListBoxHScrollTest.TestRowExtendsToTheContentWidth;
var l: TScrollAccess; b: TRect;
begin
  { Obligation two. A row still cut at the viewport has nothing to scroll TO: the offset
    would move an origin whose far edge moved with it, and the tail would never appear. }
  l := MakeList(400);
  b := l.ContentBounds(160, 96);
  AssertEquals('the row is as wide as the CONTENT, not as the box', 400, b.Right - b.Left);
end;

procedure TListBoxHScrollTest.TestHorizontalGutterComesOffTheRowCount;
var lPlain, lScrolled: TScrollAccess;
begin
  { Obligation one, on the axis it actually bites here. The bar is a real child window along
    the bottom; a row counted into its band is painted behind it. }
  lPlain := MakeList(0);
  lScrolled := MakeList(400);
  AssertNotNull('the scrolled list has a bar', lScrolled.HBar);
  AssertTrue(Format('the bar''s band comes off the rows (plain %d, scrolled %d)',
    [lPlain.VisibleRows, lScrolled.VisibleRows]),
    lScrolled.VisibleRows < lPlain.VisibleRows);
end;

procedure TListBoxHScrollTest.TestOffsetClampsToTheOverhang;
var
  l, plain: TScrollAccess;
  b: TRect;
  overhang: Integer;
begin
  { The ceiling is measured INDEPENDENTLY of the bar. Reading it back off HBar.Max would let
    a clamp that inflates the range and the offset TOGETHER agree with itself and be wrong
    only against the box -- the two numbers come from the same expression, so comparing them
    proves nothing. An unscrolled sibling gives the viewport width; the extent minus it is
    how far the content may go. }
  plain := MakeList(0);
  b := plain.ContentBounds(160, 96);
  overhang := 400 - (b.Right - b.Left);
  AssertTrue('the fixture really does overhang', overhang > 0);

  l := MakeList(400);
  l.SetOffset(99999);
  AssertEquals('the view stops with the content''s far edge at the box edge',
    overhang, l.Offset);
  AssertEquals('and the bar''s range says the same', overhang, l.HBar.Max);
  l.SetOffset(-50);
  AssertEquals('nor before its start', 0, l.Offset);
end;

procedure TListBoxHScrollTest.TestNarrowingTheExtentPullsTheViewBack;
var l: TScrollAccess;
begin
  l := MakeList(400);
  l.SetOffset(l.HBar.Max);
  AssertTrue('scrolled to the end', l.Offset > 0);
  l.ScrollWidth := 0;
  AssertEquals('switching the extent off pulls the rows home', 0, l.Offset);
  AssertFalse('and drops the bar', (l.HBar <> nil) and l.HBar.Visible);
end;

procedure TListBoxHScrollTest.TestShiftWheelScrollsSideways;
var l: TScrollAccess; before: Integer;
begin
  l := MakeList(400);
  before := l.Offset;
  AssertTrue('the gesture is consumed', l.Wheel([ssShift], -120));
  AssertTrue('shift+wheel-down slides the content right', l.Offset > before);
  before := l.Offset;
  l.Wheel([ssShift], 120);
  AssertTrue('and shift+wheel-up brings it back', l.Offset < before);
end;

procedure TListBoxHScrollTest.TestPlainWheelStillScrollsVertically;
var l: TScrollAccess;
begin
  { The horizontal gesture must not swallow the ordinary one. }
  l := MakeList(400);
  while l.Items.Count < 40 do l.Items.Add('row');
  l.CallUpdateScrollBar;
  l.Wheel([], -120);
  AssertTrue('a plain wheel still moves TopIndex', l.TopIndex > 0);
  AssertEquals('and does not slide sideways', 0, l.Offset);
end;

procedure TListBoxHScrollTest.TestRightToLeftSlidesFromTheOtherEdge;
var l: TScrollAccess; b0, b1: TRect;
begin
  { Right to left the content starts at the RIGHT and slides right, so it is still the
    LEADING edge the offset moves. Applying it to the left edge in both modes would scroll a
    mirrored list the wrong way and reveal the end of a row when the user asked for the
    start of it. }
  l := MakeList(400);
  l.BiDiMode := bdRightToLeft;
  l.CallUpdateScrollBar;
  b0 := l.ContentBounds(160, 96);
  l.SetOffset(37);
  b1 := l.ContentBounds(160, 96);
  AssertEquals('the trailing (right) edge moved OUT by the offset', b0.Right + 37, b1.Right);
  AssertEquals('and the row is still one content-width wide', 400, b1.Right - b1.Left);
end;

procedure TListBoxHScrollTest.TestScrolledRowContentActuallyMoves;
const
  W = 160; H = 100;
var
  l: TEdgeMarkList;
  Bmp: TBitmap;
  midY, x0, x1: Integer;
begin
  { The geometry tests above read the numbers the paint is SUPPOSED to use. This one reads
    the pixels, because a RowContentBounds that moves while RenderTo keeps its own copy of
    the arithmetic is precisely the drift this control has been bitten by before. }
  l := TEdgeMarkList.Create(FForm);
  Bmp := TBitmap.Create;
  try
    l.Parent := FForm;
    l.Font.PixelsPerInch := 96;
    l.ItemHeight := 24;
    l.SetBounds(0, 0, W, H);
    l.Items.Add('one'); l.Items.Add('two');
    l.ScrollWidth := 400;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;

    midY := 12;   { inside row 0, which starts at the padding-top }
    Bmp.Canvas.FillRect(0, 0, W, H);
    l.Render(Bmp.Canvas, Rect(0, 0, W, H), 96);
    x0 := FirstGreenX(Bmp, midY, W);
    AssertTrue('the leading marker is painted at offset 0', x0 >= 0);

    TScrollAccess(l).SetOffset(30);
    Bmp.Canvas.FillRect(0, 0, W, H);
    l.Render(Bmp.Canvas, Rect(0, 0, W, H), 96);
    x1 := FirstGreenX(Bmp, midY, W);
    AssertTrue(Format('scrolling moved the row''s leading edge left (was %d, now %d)',
      [x0, x1]), (x1 < x0) or (x1 = -1));
    { And the far end came INTO view: at offset 0 the trailing marker sits 400px out and is
      clipped away, so nothing green may touch the right edge. }
    AssertTrue('the clip keeps the overflow out of the box',
      LastGreenX(Bmp, midY, W) < W);
  finally
    Bmp.Free;
  end;
end;

{ =================== per-row heights =================================================== }

procedure TListBoxVariableRowTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TListBoxVariableRowTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TListBoxVariableRowTest.MakeList: TVariableRowList;
var i: Integer;
begin
  Result := TVariableRowList.Create(FForm);
  Result.Parent := FForm;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 160, 100);
  for i := 1 to 8 do Result.Items.Add('row ' + IntToStr(i));
end;

procedure TListBoxVariableRowTest.TestUniformListIsUnchangedByTheSeam;
var l: TTyListBox;
begin
  { The regression pin. A plain list does not override RowHeight, so every number it
    produces must be the one the single-ItemHeight arithmetic produced -- 100 div 24 = 4. }
  l := TTyListBox.Create(FForm);
  l.Parent := FForm;
  l.Font.PixelsPerInch := 96;
  l.ItemHeight := 24;
  l.SetBounds(0, 0, 160, 100);
  AssertEquals('VisibleRows is still Height div ItemHeight', 4, l.VisibleRows);
  l.Items.Add('a'); l.Items.Add('b');
  AssertEquals('and an ItemRect is still one ItemHeight tall',
    24, l.ItemRect(0).Bottom - l.ItemRect(0).Top);
  AssertEquals('rows still start where they did',
    l.ItemRect(0).Bottom, l.ItemRect(1).Top);
end;

procedure TListBoxVariableRowTest.TestItemRectUsesEachRowsOwnHeight;
var l: TVariableRowList; r0, r1, r2: TRect;
begin
  l := MakeList;
  r0 := l.ItemRect(0); r1 := l.ItemRect(1); r2 := l.ItemRect(2);
  AssertEquals('row 0 is the tall one', Tall, r0.Bottom - r0.Top);
  AssertEquals('row 1 the short one',   Short, r1.Bottom - r1.Top);
  AssertEquals('row 2 tall again',      Tall, r2.Bottom - r2.Top);
  AssertEquals('and they stack without a gap or an overlap', r0.Bottom, r1.Top);
  AssertEquals('...all the way down', r1.Bottom, r2.Top);
end;

procedure TListBoxVariableRowTest.TestRowAtYUsesEachRowsOwnHeight;
var l: TVariableRowList; off: Integer;
begin
  { Edges, not centres: every boundary between two rows of DIFFERENT heights is probed on
    both sides, which is where a formula still using one height lands on the wrong row. }
  l := MakeList;
  off := l.CallContentTopOffset;
  AssertEquals('the padding band still clamps to the first row', 0, l.CallRowAtY(off - 1));
  AssertEquals('row 0 top edge',            0, l.CallRowAtY(off));
  AssertEquals('row 0 last px',             0, l.CallRowAtY(off + Tall - 1));
  AssertEquals('row 1 first px',            1, l.CallRowAtY(off + Tall));
  AssertEquals('row 1 last px',             1, l.CallRowAtY(off + Tall + Short - 1));
  AssertEquals('row 2 first px',            2, l.CallRowAtY(off + Tall + Short));
  AssertEquals('row 2 last px',             2, l.CallRowAtY(off + 2 * Tall + Short - 1));
  AssertEquals('row 3 first px',            3, l.CallRowAtY(off + 2 * Tall + Short));
end;

procedure TListBoxVariableRowTest.TestVisibleRowsCountsRealHeights;
var l: TVariableRowList;
begin
  { 100px of box, rows 40/16/40/16... -> 40+16+40 = 96 fits, the next 16 does not. }
  l := MakeList;
  AssertEquals('three whole rows fit, not 100 div anything', 3, l.VisibleRows);
end;

procedure TListBoxVariableRowTest.TestMaxTopIndexCountsFromTheLastRow;
var
  lAlt: TVariableRowList;
  lTop: TTopHeavyRowList;
  i: Integer;
begin
  { The rows at the END decide how far down the list can go, and with per-row heights they
    need not be the same size as the ones under the cursor.

    The alternating list first, as a plain regression pin: 8 rows of 40/16, box 100, so the
    last three (16+40+16 = 72, the next 40 overshoots) fill it and TopIndex stops at 5. }
  lAlt := MakeList;
  lAlt.TopIndex := 999;
  AssertEquals('TopIndex stops where the last rows fill the box', 5, lAlt.TopIndex);

  { ...and then the case that can actually TELL the two counts apart. An alternating
    pattern is periodic, so counting forward from the top and backward from the end give
    the same number and a `Count - VisibleRows` would pass the assertion above -- it did.
    Short rows at the top and tall ones at the bottom separate them: SIX short rows fit up
    there, only TWO tall ones fit down here, so the forward count lets TopIndex run four
    rows too far and the last row ends up unreachable. }
  lTop := TTopHeavyRowList.Create(FForm);
  lTop.Parent := FForm;
  lTop.Font.PixelsPerInch := 96;
  lTop.SetBounds(0, 0, 160, 100);
  for i := 1 to 10 do lTop.Items.Add('row ' + IntToStr(i));
  AssertEquals('six short rows fit counting forward from the top', 6, lTop.VisibleRows);
  lTop.TopIndex := 999;
  AssertEquals('but only the last TWO tall rows fill the box, so TopIndex stops at 8',
    8, lTop.TopIndex);
end;

procedure TListBoxVariableRowTest.TestPaintedRowsMatchItemRect;
const
  W = 160; H = 100;
var
  l: TVariableRowList;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  r1: TRect;
  yIn, yOut: Integer;
  pIn, pOut: TBGRAPixel;
begin
  { What the paint does and what ItemRect says have to be one accumulation. Probe the
    selected row's own band against the band just past its bottom edge: if RenderTo were
    still stepping by a single height, row 1's highlight would end 24px down while ItemRect
    reports 16, and the two probes would read the same colour. }
  l := MakeList;
  l.SelectItem(1);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, W, H);
    l.Render(Bmp.Canvas, Rect(0, 0, W, H), 96);
    r1 := l.ItemRect(1);
    yIn  := r1.Bottom - 2;    // inside row 1, one px off its bottom edge
    yOut := r1.Bottom + 2;    // inside row 2
    Img := TBGRABitmap.Create(Bmp);
    try
      pIn  := Img.GetPixel(W div 2, yIn);
      pOut := Img.GetPixel(W div 2, yOut);
      AssertTrue(Format('the highlight ends where ItemRect says row 1 ends ' +
        '(y=%d R%dG%dB%d vs y=%d R%dG%dB%d)',
        [yIn, pIn.red, pIn.green, pIn.blue, yOut, pOut.red, pOut.green, pOut.blue]),
        (pIn.red <> pOut.red) or (pIn.green <> pOut.green) or (pIn.blue <> pOut.blue));
    finally Img.Free; end;
  finally
    Bmp.Free;
  end;
end;

procedure TListBoxVariableRowTest.TestZeroHeightAnswerCannotHangThePaint;
var l: TZeroRowList;
begin
  { A row of no height is not a row, it is a walker that never advances. Every one of them
    counts rows by subtracting a height from a budget, so a zero would spin. The floor lives
    in ScaledRowHeightAt, which is the one place all of them go through. }
  l := TZeroRowList.Create(FForm);
  l.Parent := FForm;
  l.Font.PixelsPerInch := 96;
  l.SetBounds(0, 0, 160, 100);
  l.Items.Add('a'); l.Items.Add('b');
  AssertTrue('VisibleRows terminates', l.VisibleRows > 0);
  AssertTrue('and so does the row walk', l.ItemRect(1).Top >= 0);
end;

procedure TListBoxVariableRowTest.TestScrollIntoViewRevealsTheRowItWasAskedFor;
var
  l: TTopHeavyRowList;
  i: Integer;
  r: TRect;
begin
  { Selecting a row below the fold has to bring THAT row fully into view. The count of rows
    that fit has to be taken BACKWARDS from the target: taken forwards from the old top it
    describes the SHORT rows up there, and using it to pick a new top puts the top four rows
    too high -- the target ends up past the bottom edge, which is the one thing this is for. }
  l := TTopHeavyRowList.Create(FForm);
  l.Parent := FForm;
  l.Font.PixelsPerInch := 96;
  l.SetBounds(0, 0, 160, 100);
  for i := 1 to 10 do l.Items.Add('row ' + IntToStr(i));
  AssertEquals('six short rows fit at the top', 6, l.VisibleRows);
  l.SelectItem(8);
  r := l.ItemRect(8);
  AssertTrue(Format('row 8 is fully inside the box (top %d, bottom %d, box 100), ' +
    'TopIndex %d', [r.Top, r.Bottom, l.TopIndex]),
    (r.Top >= 0) and (r.Bottom <= 100));
end;

{ =================== theme padding vs the viewport ===================================== }

procedure TListBoxPaddingTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  { border-width 0 so the render probe below has no chrome clip to reason about: the
    only vertical inset left is the padding itself. }
  FCtl.LoadThemeCss('TyListBox { background:#101010; color:#F0F0F0; ' +
    'border-width:0px; padding:4px; }');
end;

procedure TListBoxPaddingTest.TearDown;
begin
  FreeAndNil(FForm);     // the controls first: they hold a reference to the controller
  FreeAndNil(FCtl);
end;

procedure TListBoxPaddingTest.TestMaxTopIndexRespectsPadding;
var
  l: TEdgeMarkList;
  Bmp: TBitmap;
  i, y: Integer;
begin
  { 4px padding top+bottom; 84px of box holds a 76px content area, so FOUR 16px rows fit
    (64), not five (80). Counting against the full height says five -- and then, scrolled to
    the bottom, the fifth row paints past the content edge into the bottom padding band. }
  l := TEdgeMarkList.Create(FForm);
  l.Parent := FForm;
  l.Controller := FCtl;
  l.Font.PixelsPerInch := 96;
  l.ItemHeight := 16;
  for i := 0 to 29 do l.Items.Add('row ' + IntToStr(i));
  l.SetBounds(0, 0, 160, 84);

  AssertEquals('VisibleRows counts rows that fit the padding-inset content area',
    4, l.VisibleRows);
  l.TopIndex := 999;
  AssertEquals('TopIndex stops where the last rows fill the CONTENT area, not the box',
    26, l.TopIndex);

  { And the paint agrees: at the bottom, the last whole row ends at 4 + 4*16 = 68; the
    strip below it (the would-be fifth row plus the bottom padding) holds no row ink. }
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(160, 84);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, 160, 84);
    l.Render(Bmp.Canvas, Rect(0, 0, 160, 84), 96);
    AssertTrue('scrolled to the bottom, the top row drew its marker (anti-vacuity)',
      FirstGreenX(Bmp, 12, 160) >= 0);
    for y := 68 to 83 do
      AssertEquals(Format('no row ink below the last whole row (y=%d)', [y]),
        -1, FirstGreenX(Bmp, y, 160));
  finally
    Bmp.Free;
  end;
end;

procedure TListBoxPaddingTest.TestScrollBarAppearsWhenPaddingOverflowsTheRows;
var
  l: TScrollAccess;
  i: Integer;
begin
  { The severe half of the same formula: five 20px rows in a 100px box LOOK like an exact
    fit, but the padding leaves only 92px of content area -- the fifth row does not fit.
    A bar decision made against the full height answers "no bar", and with no bar there is
    no way to ever see that row. }
  l := TScrollAccess.Create(FForm);
  l.Parent := FForm;
  l.Controller := FCtl;
  l.Font.PixelsPerInch := 96;
  l.ItemHeight := 20;
  for i := 1 to 5 do l.Items.Add('row ' + IntToStr(i));
  l.SetBounds(0, 0, 160, 100);
  l.CallUpdateScrollBar;

  AssertNotNull('rows past the content area raise the vertical bar', l.VBar);
  AssertTrue('and it is visible', l.VBar.Visible);
  AssertEquals('four whole rows fit the content area', 4, l.VBar.PageSize);
  AssertEquals('and the range reaches the fifth', 1, l.VBar.Max);
end;

initialization
  RegisterTest(TListBoxHScrollTest);
  RegisterTest(TListBoxVariableRowTest);
  RegisterTest(TListBoxPaddingTest);
end.
