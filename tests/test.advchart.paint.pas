unit test.advchart.paint;
{$mode objfpc}{$H+}
{ The paint list: ordering, and the ONE hit-test path.
  Pure -- no painter is involved in deciding order or answering the pointer. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Paint;
type
  TAdvChartPaintTest = class(TTestCase)
  private
    FList: TTyPaintList;
    function AddBox(AL, AT, AR, AB: Double; AZ, AZ2: Integer;
      ASeries, AData: Integer): Integer;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ---- order ---- }
    procedure TestPaintOrderFollowsZ;
    procedure TestZ2BreaksTiesWithinAZ;
    procedure TestInsertionOrderBreaksTheRest;
    procedure TestOrderSurvivesAddingAfterAQuery;
    { ---- hit test ---- }
    procedure TestHitReturnsTheTopmostOverlapping;
    procedure TestSilentElementsAreSkipped;
    procedure TestSilentElementDoesNotShadowTheOneBelow;
    procedure TestMissReturnsNoDatum;
    procedure TestNoDatumIsBothMinusOneTogether;
    procedure TestHitSlopIsScaledByThePPI;
    procedure TestElementHitAndDatumHitAreOnePath;
    { ---- defaults and lifecycle ---- }
    procedure TestNewElementIsSilentByDefault;
    procedure TestDefaultStyleDrawsNothing;
    procedure TestClearEmptiesIt;
    procedure TestOutOfRangeQueriesAreSafe;
  end;
implementation

procedure TAdvChartPaintTest.SetUp;
begin
  inherited SetUp;
  FList := TTyPaintList.Create;
end;

procedure TAdvChartPaintTest.TearDown;
begin
  FreeAndNil(FList);
  inherited TearDown;
end;

function TAdvChartPaintTest.AddBox(AL, AT, AR, AB: Double; AZ, AZ2: Integer;
  ASeries, AData: Integer): Integer;
var e: TTyChartElement;
begin
  e := TyChartElement(TyShapeRect(TyRectF(AL, AT, AR, AB)));
  e.Z := AZ;
  e.Z2 := AZ2;
  e.Silent := False;
  e.Datum := TyChartDatum(ASeries, AData);
  Result := FList.Add(e);
end;

{ ============================ order ============================ }

procedure TAdvChartPaintTest.TestPaintOrderFollowsZ;
begin
  AddBox(0, 0, 10, 10, 5, 0, 0, 0);      // index 0, z 5
  AddBox(0, 0, 10, 10, 1, 0, 0, 1);      // index 1, z 1
  AddBox(0, 0, 10, 10, 3, 0, 0, 2);      // index 2, z 3
  AssertEquals('lowest z painted first', 1, FList.PaintOrder(0));
  AssertEquals('then the middle', 2, FList.PaintOrder(1));
  AssertEquals('highest z last', 0, FList.PaintOrder(2));
end;

procedure TAdvChartPaintTest.TestZ2BreaksTiesWithinAZ;
begin
  AddBox(0, 0, 10, 10, 1, 9, 0, 0);
  AddBox(0, 0, 10, 10, 1, 2, 0, 1);
  AssertEquals('lower z2 first', 1, FList.PaintOrder(0));
  AssertEquals('higher z2 last', 0, FList.PaintOrder(1));
end;

procedure TAdvChartPaintTest.TestInsertionOrderBreaksTheRest;
var i: Integer;
begin
  { Ten elements all at the same z and z2. Without the insertion index in the
    comparison the order would be whatever the sort happens to do -- which is
    how a chart repaints its bars in one order and hit-tests them in another. }
  for i := 0 to 9 do
    AddBox(0, 0, 10, 10, 0, 0, 0, i);
  for i := 0 to 9 do
    AssertEquals('stable at ' + IntToStr(i), i, FList.PaintOrder(i));
end;

procedure TAdvChartPaintTest.TestOrderSurvivesAddingAfterAQuery;
begin
  AddBox(0, 0, 10, 10, 5, 0, 0, 0);
  AssertEquals('first query', 0, FList.PaintOrder(0));
  AddBox(0, 0, 10, 10, 1, 0, 0, 1);
  { The order is cached; adding must invalidate it, or the new element is
    painted last however low its z. }
  AssertEquals('re-sorted after the add', 1, FList.PaintOrder(0));
  AssertEquals('and the old one moved up', 0, FList.PaintOrder(1));
end;

{ ============================ hit test ============================ }

procedure TAdvChartPaintTest.TestHitReturnsTheTopmostOverlapping;
var d: TTyChartDatumRef;
begin
  AddBox(0, 0, 100, 100, 1, 0, 7, 70);    // underneath
  AddBox(0, 0, 100, 100, 5, 0, 8, 80);    // on top
  d := FList.HitTest(50, 50, 96);
  AssertEquals('the top one wins, series', 8, d.SeriesIndex);
  AssertEquals('the top one wins, datum', 80, d.DataIndex);
end;

procedure TAdvChartPaintTest.TestSilentElementsAreSkipped;
var
  e: TTyChartElement;
  d: TTyChartDatumRef;
begin
  e := TyChartElement(TyShapeRect(TyRectF(0, 0, 100, 100)));
  e.Silent := True;
  e.Datum := TyChartDatum(1, 1);
  FList.Add(e);
  d := FList.HitTest(50, 50, 96);
  AssertFalse('a silent element is never the answer', TyChartDatumValid(d));
end;

procedure TAdvChartPaintTest.TestSilentElementDoesNotShadowTheOneBelow;
var
  e: TTyChartElement;
  d: TTyChartDatumRef;
begin
  AddBox(0, 0, 100, 100, 1, 0, 3, 30);    // a bar
  e := TyChartElement(TyShapeRect(TyRectF(0, 0, 100, 100)));
  e.Z := 99;                              // a grid line drawn over everything
  e.Silent := True;
  FList.Add(e);
  d := FList.HitTest(50, 50, 96);
  { This is what Silent is FOR. Without it the topmost thing under the pointer
    is the gridline, and the bar becomes unhoverable. }
  AssertEquals('the bar underneath still answers', 3, d.SeriesIndex);
  AssertEquals('and its datum', 30, d.DataIndex);
end;

procedure TAdvChartPaintTest.TestMissReturnsNoDatum;
var d: TTyChartDatumRef;
begin
  AddBox(0, 0, 10, 10, 1, 0, 1, 1);
  d := FList.HitTest(500, 500, 96);
  AssertFalse('nothing there', TyChartDatumValid(d));
  AssertEquals('no element either', -1, FList.HitTestElement(500, 500, 96));
end;

procedure TAdvChartPaintTest.TestNoDatumIsBothMinusOneTogether;
var d: TTyChartDatumRef;
begin
  d := TyChartNoDatum;
  { Both or neither, decided in one place. A half-valid datum -- a series with
    no point, or a point with no series -- is the defect TyChartHitValid exists
    to prevent in the old chart. }
  AssertEquals('series', -1, d.SeriesIndex);
  AssertEquals('data', -1, d.DataIndex);
  AssertFalse('and it reads as invalid', TyChartDatumValid(d));
  AssertFalse('a half-valid one too', TyChartDatumValid(TyChartDatum(0, -1)));
  AssertFalse('the other half as well', TyChartDatumValid(TyChartDatum(-1, 0)));
  AssertTrue('a real one is valid', TyChartDatumValid(TyChartDatum(0, 0)));
end;

procedure TAdvChartPaintTest.TestHitSlopIsScaledByThePPI;
var
  e: TTyChartElement;
begin
  e := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
  e.Silent := False;
  e.HitSlopLogical := 5;
  e.Datum := TyChartDatum(0, 0);
  FList.Add(e);
  { The slop is a LOGICAL distance -- how far the user's finger is off, which
    does not shrink because the monitor got denser. At 192 dpi a 5 px slop is
    10 device px, so a probe 8 px out hits there and misses at 96. }
  AssertFalse('8 px out at 96 dpi', TyChartDatumValid(FList.HitTest(18, 5, 96)));
  AssertTrue('the same probe at 192 dpi', TyChartDatumValid(FList.HitTest(18, 5, 192)));
end;

procedure TAdvChartPaintTest.TestElementHitAndDatumHitAreOnePath;
var
  i, idx: Integer;
  d: TTyChartDatumRef;
begin
  { Two ways to ask must be one way to answer, or the element a chart highlights
    and the datum it reports drift apart. }
  AddBox(0, 0, 40, 40, 1, 0, 1, 10);
  AddBox(20, 20, 60, 60, 2, 0, 2, 20);
  AddBox(50, 50, 90, 90, 0, 0, 3, 30);
  for i := 0 to 90 do
  begin
    idx := FList.HitTestElement(i, i, 96);
    d := FList.HitTest(i, i, 96);
    if idx < 0 then
      AssertFalse('no element means no datum at ' + IntToStr(i), TyChartDatumValid(d))
    else
    begin
      AssertEquals('same series at ' + IntToStr(i),
                   FList.Element(idx).Datum.SeriesIndex, d.SeriesIndex);
      AssertEquals('same datum at ' + IntToStr(i),
                   FList.Element(idx).Datum.DataIndex, d.DataIndex);
    end;
  end;
end;

{ ==================== defaults and lifecycle ==================== }

procedure TAdvChartPaintTest.TestNewElementIsSilentByDefault;
var e: TTyChartElement;
begin
  e := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
  { The safe default. A decoration whose author forgot to think about hit
    testing is at worst inert; the other way round it silently steals hovers
    from the data underneath it. }
  AssertTrue('silent', e.Silent);
  AssertFalse('and carries no datum', TyChartDatumValid(e.Datum));
end;

procedure TAdvChartPaintTest.TestDefaultStyleDrawsNothing;
var s: TTyChartElementStyle;
begin
  s := TyChartStyle;
  AssertFalse('no fill', s.HasFill);
  AssertEquals('no stroke', 0.0, s.StrokeWidthLogical, 1e-12);
  AssertEquals('but fully opaque when something is turned on', 1.0, s.Alpha, 1e-12);
end;

procedure TAdvChartPaintTest.TestClearEmptiesIt;
begin
  AddBox(0, 0, 10, 10, 1, 0, 1, 1);
  AssertEquals('one in', 1, FList.Count);
  FList.Clear;
  AssertEquals('none left', 0, FList.Count);
  AssertFalse('and nothing to hit', TyChartDatumValid(FList.HitTest(5, 5, 96)));
end;

procedure TAdvChartPaintTest.TestOutOfRangeQueriesAreSafe;
var e: TTyChartElement;
begin
  AddBox(0, 0, 10, 10, 1, 0, 1, 1);
  AssertEquals('past the end', -1, FList.PaintOrder(99));
  AssertEquals('before the start', -1, FList.PaintOrder(-1));
  e := FList.Element(99);
  AssertFalse('an out-of-range element carries no datum', TyChartDatumValid(e.Datum));
end;

initialization
  RegisterTest(TAdvChartPaintTest);
end.
