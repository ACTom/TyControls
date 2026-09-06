unit test.advchart.render;
{$mode objfpc}{$H+}
{ Rendering a paint list through the painter.

  The test that matters here is TestInkAndHitTestAgree: render the list, then ask
  the hit test about the very pixels that came out. If those two ever disagree,
  the pointer reports one datum while the eye sees another -- which is the single
  defect this whole layer is arranged to prevent, and the reason the shape is
  DATA shared by both rather than two pieces of code that happen to match. }
interface
uses Classes, SysUtils, Math, Types, Graphics, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Painter,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Render;
type
  TAdvChartRenderTest = class(TTestCase)
  private
    FHost: TBitmap;
    FPainter: TTyPainter;
    FList: TTyPaintList;
    procedure Start(AW, AH, APPI: Integer);
    function AlphaAt(X, Y: Integer): Integer;
    function Opaque(X, Y: Integer): Boolean;
    function FilledRect(AL, AT, AR, AB: Double; AColor: TTyChartColor): TTyChartElement;
  protected
    procedure TearDown; override;
  published
    procedure TestRendersAFilledRectWhereTheShapeSaysItIs;
    procedure TestAnElementWithNeitherFillNorStrokeDrawsNothing;
    procedure TestPaintOrderPutsTheHighZOnTop;
    procedure TestElementAlphaIsApplied;
    procedure TestDashDoesNotLeakToTheNextElement;
    procedure TestAlphaDoesNotLeakToTheNextElement;
    procedure TestSectorRendersAsARingWithAHole;
    procedure TestInkAndHitTestAgree;
    procedure TestInkAndHitTestAgreeOnABackwardsWedge;
    procedure TestSnappingMakesAHairlineCrisp;
  end;
implementation

const
  Red  = TTyChartColor($FFFF0000);
  Blue = TTyChartColor($FF0000FF);

procedure TAdvChartRenderTest.Start(AW, AH, APPI: Integer);
begin
  FHost := TBitmap.Create;
  FHost.SetSize(AW, AH);
  FPainter := TTyPainter.Create;
  FPainter.BeginPaint(FHost.Canvas, Rect(0, 0, AW, AH), APPI);
  FList := TTyPaintList.Create;
end;

procedure TAdvChartRenderTest.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FPainter);
  FreeAndNil(FHost);
  inherited TearDown;
end;

function TAdvChartRenderTest.AlphaAt(X, Y: Integer): Integer;
begin
  Result := FPainter.Bitmap.GetPixel(X, Y).alpha;
end;

function TAdvChartRenderTest.Opaque(X, Y: Integer): Boolean;
begin
  Result := AlphaAt(X, Y) > 200;
end;

function TAdvChartRenderTest.FilledRect(AL, AT, AR, AB: Double;
  AColor: TTyChartColor): TTyChartElement;
begin
  Result := TyChartElement(TyShapeRect(TyRectF(AL, AT, AR, AB)));
  Result.Style.HasFill := True;
  Result.Style.FillColor := AColor;
  Result.Silent := False;
end;

procedure TAdvChartRenderTest.TestRendersAFilledRectWhereTheShapeSaysItIs;
begin
  Start(100, 100, 96);
  FList.Add(FilledRect(20, 20, 80, 80, Red));
  TyRenderPaintList(FPainter, FList);
  AssertTrue('inside', Opaque(50, 50));
  AssertEquals('outside untouched', 0, AlphaAt(5, 5));
end;

procedure TAdvChartRenderTest.TestAnElementWithNeitherFillNorStrokeDrawsNothing;
var e: TTyChartElement;
begin
  Start(100, 100, 96);
  { A hit area with no ink is a legitimate thing to register -- an invisible
    band that catches the pointer for a sparse series. It must not draw. }
  e := TyChartElement(TyShapeRect(TyRectF(20, 20, 80, 80)));
  e.Silent := False;
  e.Datum := TyChartDatum(0, 0);
  FList.Add(e);
  TyRenderPaintList(FPainter, FList);
  AssertEquals('no ink at all', 0, AlphaAt(50, 50));
  AssertTrue('but it still answers the pointer',
             TyChartDatumValid(FList.HitTest(50, 50, 96)));
end;

procedure TAdvChartRenderTest.TestPaintOrderPutsTheHighZOnTop;
var a, b: TTyChartElement;
begin
  Start(100, 100, 96);
  { Added low-z LAST, so only the sort can put it underneath. }
  b := FilledRect(20, 20, 80, 80, Blue);
  b.Z := 9;
  FList.Add(b);
  a := FilledRect(20, 20, 80, 80, Red);
  a.Z := 1;
  FList.Add(a);
  TyRenderPaintList(FPainter, FList);
  AssertEquals('the high-z blue is what survives',
               255, FPainter.Bitmap.GetPixel(50, 50).blue);
  AssertEquals('and the red is under it',
               0, FPainter.Bitmap.GetPixel(50, 50).red);
end;

procedure TAdvChartRenderTest.TestElementAlphaIsApplied;
var e: TTyChartElement;
begin
  Start(100, 100, 96);
  e := FilledRect(20, 20, 80, 80, Red);
  e.Style.Alpha := 0.5;
  FList.Add(e);
  TyRenderPaintList(FPainter, FList);
  AssertTrue('about half, got ' + IntToStr(AlphaAt(50, 50)),
             (AlphaAt(50, 50) > 100) and (AlphaAt(50, 50) < 160));
end;

procedure TAdvChartRenderTest.TestDashDoesNotLeakToTheNextElement;
var
  dashed, solid: TTyChartElement;
  x, runs: Integer;
  wasIn, isIn: Boolean;
begin
  Start(260, 60, 96);
  dashed := TyChartElement(TyShapePolyline([TyPointF(10, 10), TyPointF(250, 10)]));
  dashed.Style.StrokeWidthLogical := 3;
  dashed.Style.StrokeColor := Red;
  SetLength(dashed.Style.DashLogical, 2);
  dashed.Style.DashLogical[0] := 6;
  dashed.Style.DashLogical[1] := 6;
  FList.Add(dashed);

  solid := TyChartElement(TyShapePolyline([TyPointF(10, 40), TyPointF(250, 40)]));
  solid.Style.StrokeWidthLogical := 3;
  solid.Style.StrokeColor := Blue;
  FList.Add(solid);

  TyRenderPaintList(FPainter, FList);

  runs := 0;
  wasIn := False;
  for x := 0 to 259 do
  begin
    isIn := AlphaAt(x, 40) > 128;
    if isIn and not wasIn then Inc(runs);
    wasIn := isIn;
  end;
  { The canvas state is shared across elements. Without the save/restore around
    each one, the dash set for the first would still be in force for the second
    and this would come back as many runs. }
  AssertEquals('the second line is unbroken', 1, runs);
end;

procedure TAdvChartRenderTest.TestAlphaDoesNotLeakToTheNextElement;
var
  faded, solid: TTyChartElement;
begin
  { Alpha is set only when it is BELOW 1, so an opaque element does not reset it
    -- it relies entirely on the save/restore around each element. That makes
    this the load-bearing case, and the dash test does not cover it, because
    every element sets its dash explicitly whether or not it has one.

    Found by mutation: deleting P.SaveState left every other test green. }
  Start(200, 100, 96);
  faded := FilledRect(10, 10, 90, 90, Red);
  faded.Style.Alpha := 0.3;
  FList.Add(faded);
  solid := FilledRect(110, 10, 190, 90, Blue);
  FList.Add(solid);                       // Alpha stays 1 -- never assigned
  TyRenderPaintList(FPainter, FList);
  AssertTrue('the faded one is faded, got ' + IntToStr(AlphaAt(50, 50)),
             AlphaAt(50, 50) < 130);
  AssertTrue('and the opaque one is opaque, got ' + IntToStr(AlphaAt(150, 50)),
             AlphaAt(150, 50) > 250);
end;

procedure TAdvChartRenderTest.TestSectorRendersAsARingWithAHole;
var e: TTyChartElement;
begin
  Start(200, 200, 96);
  e := TyChartElement(TyShapeSector(100, 100, 30, 80, 0, 2 * Pi));
  e.Style.HasFill := True;
  e.Style.FillColor := Red;
  e.Silent := False;
  e.Datum := TyChartDatum(0, 0);
  FList.Add(e);
  TyRenderPaintList(FPainter, FList);
  AssertTrue('the band has ink', Opaque(100, 100 - 55));
  { And the hole really is a hole -- in the pixels AND in the hit test. }
  AssertEquals('the hole has none', 0, AlphaAt(100, 100));
  AssertFalse('and the hit test agrees',
              TyChartDatumValid(FList.HitTest(100, 100, 96)));
end;

procedure TAdvChartRenderTest.TestInkAndHitTestAgree;
var
  e: TTyChartElement;
  x, y, mismatches, inked, hit: Integer;
  hasInk, hasHit: Boolean;
begin
  { THE ONE THAT MATTERS. Render a ring, then sweep the bitmap asking both
    questions of every pixel: is there ink here, and does the hit test claim
    this datum here. Where they disagree, the pointer reports one thing while
    the eye sees another.

    A one-pixel band of disagreement along every edge is expected and allowed:
    the renderer antialiases, so an edge pixel is genuinely half in. What must
    not happen is a REGION of disagreement -- a hole the hit test fills in, or a
    band it misses. }
  Start(200, 200, 96);
  e := TyChartElement(TyShapeSector(100, 100, 30, 80, 0, 2 * Pi));
  e.Style.HasFill := True;
  e.Style.FillColor := Red;
  e.Silent := False;
  e.Datum := TyChartDatum(0, 0);
  FList.Add(e);
  TyRenderPaintList(FPainter, FList);

  mismatches := 0;
  inked := 0;
  hit := 0;
  for y := 0 to 199 do
    for x := 0 to 199 do
    begin
      hasInk := AlphaAt(x, y) > 200;
      hasHit := TyChartDatumValid(FList.HitTest(x + 0.5, y + 0.5, 96));
      if hasInk then Inc(inked);
      if hasHit then Inc(hit);
      if hasInk <> hasHit then Inc(mismatches);
    end;

  AssertTrue('the ring really was drawn (' + IntToStr(inked) + ' px)', inked > 5000);
  AssertTrue('and the hit test claims a similar area (' + IntToStr(hit) + ' px)',
             Abs(hit - inked) < inked div 10);
  { Two rims plus antialiasing, on a ring whose outlines are about 690 px of
    perimeter -- a couple of pixels deep at most. Anything approaching a region
    would blow well past this. }
  AssertTrue('disagreement is a thin edge, not a region ('
             + IntToStr(mismatches) + ' px of ' + IntToStr(inked) + ')',
             mismatches < inked div 10);
end;

procedure TAdvChartRenderTest.TestSnappingMakesAHairlineCrisp;
var
  e: TTyChartElement;
  fuzzyRows, crispRows, y: Integer;

  function RowsWithInk(AX: Integer): Integer;
  var yy: Integer;
  begin
    Result := 0;
    for yy := 0 to 59 do
      if AlphaAt(AX, yy) > 16 then Inc(Result);
  end;

begin
  { The whole point of sub-pixel snapping, measured in pixels rather than in
    arithmetic. A 1 px line stroked at y = 20 straddles two rows at half alpha;
    snapped to 20.5 it fills one row completely. }
  Start(120, 60, 96);
  e := TyChartElement(TyShapePolyline([TyPointF(10, 20), TyPointF(110, 20)]));
  e.Style.StrokeWidthLogical := 1;
  e.Style.StrokeColor := Red;
  FList.Add(e);
  TyRenderPaintList(FPainter, FList);
  fuzzyRows := RowsWithInk(60);

  FreeAndNil(FList);
  FreeAndNil(FPainter);
  FreeAndNil(FHost);
  Start(120, 60, 96);
  e := TyChartElement(TySnapShape(
         TyShapePolyline([TyPointF(10, 20), TyPointF(110, 20)]), 1));
  e.Style.StrokeWidthLogical := 1;
  e.Style.StrokeColor := Red;
  FList.Add(e);
  TyRenderPaintList(FPainter, FList);
  crispRows := RowsWithInk(60);

  AssertEquals('unsnapped smears over two rows', 2, fuzzyRows);
  AssertEquals('snapped covers exactly one', 1, crispRows);
  { And that one row is FULLY covered, not two halves stacked. }
  y := 0;
  while (y < 60) and (AlphaAt(60, y) <= 16) do Inc(y);
  AssertTrue('and it is solid, got ' + IntToStr(AlphaAt(60, y)), AlphaAt(60, y) > 240);
end;

procedure TAdvChartRenderTest.TestInkAndHitTestAgreeOnABackwardsWedge;
var
  e: TTyChartElement;
  x, y, mismatches, inked, hit: Integer;
  hasInk, hasHit: Boolean;
begin
  { THE SAME QUESTION, ON A WEDGE. The test above uses a full turn, which takes
    SectorContains' full-turn early-out and never reaches the angle comparison
    -- so the one shape kind whose geometry is not axis-aligned had its
    agreement checked only where the angles cannot matter.

    Backwards on purpose: ECharts writes `clockwise: false` as an end angle
    BELOW the start. SectorContains has always read that as the short wedge
    between the two, while the renderer handed both angles to ArcTo, whose
    sweep is measured by wraparound -- so it painted the 270-degree complement
    of the 90-degree wedge that answered the pointer. Ink and hit test named
    two different, almost disjoint regions, which is the exact drift item 14
    exists to make impossible. }
  Start(200, 200, 96);
  e := TyChartElement(TyShapeSector(100, 100, 30, 80, Pi / 2, 0));
  e.Style.HasFill := True;
  e.Style.FillColor := Red;
  e.Silent := False;
  e.Datum := TyChartDatum(0, 0);
  FList.Add(e);
  TyRenderPaintList(FPainter, FList);

  mismatches := 0;
  inked := 0;
  hit := 0;
  for y := 0 to 199 do
    for x := 0 to 199 do
    begin
      hasInk := AlphaAt(x, y) > 200;
      hasHit := TyChartDatumValid(FList.HitTest(x + 0.5, y + 0.5, 96));
      if hasInk then Inc(inked);
      if hasHit then Inc(hit);
      if hasInk <> hasHit then Inc(mismatches);
    end;

  { The ring is pi*(80^2 - 30^2) ~ 17,300 px, so a quarter is about 4,300 and
    the complement about 13,000. The bounds sit either side of the midpoint
    between them, which is the whole distinction being drawn -- and the floor
    catches the opposite failure, where the two sides agree because nothing was
    drawn at all. }
  AssertTrue('the wedge really was drawn (' + IntToStr(inked) + ' px)',
             inked > 2500);
  AssertTrue('and it is the quarter wedge, not its three-quarter complement ('
             + IntToStr(inked) + ' px)', inked < 8000);
  AssertTrue('the hit test claims a similar area (' + IntToStr(hit) + ' px)',
             Abs(hit - inked) < inked div 5);
  AssertTrue('disagreement is a thin edge, not a region ('
             + IntToStr(mismatches) + ' px of ' + IntToStr(inked) + ')',
             mismatches < inked div 4);
end;

initialization
  RegisterTest(TAdvChartRenderTest);
end.
