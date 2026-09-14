unit test.advchart.funnel;
{$mode objfpc}{$H+}
{ The funnel.

  IT IS NOT A PIE WITH STRAIGHT EDGES. A pie turns each value into an ANGLE and
  the disc is the total; a funnel turns each value into a WIDTH against a
  shared scale, and the stack's height has nothing to do with the data -- it is
  the view divided by the row count. One huge value and four small ones is five
  equally tall bands, four of them nearly invisible.

  THE LAST BAND HAS NO NEXT ROW, and upstream reaches that case by indexing one
  past the end of a JavaScript array: undefined, then NaN out of the store, then
  zero out of `|| 0`. So the tip is the width of value ZERO -- a point, with the
  default minSize. A port has to synthesise that edge deliberately, because
  indexing past the end here is a range error and clamping to the last row would
  draw a rectangle where upstream draws a triangle. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Option, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Funnel, tyControls.AdvChart.Paint,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartFunnelRuleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FStore: TTyDataStore;
    procedure TearDown; override;
    function SpecOf(const AText: string): TTyFunnelSpec;
    function LabelSpecOf(const AText: string): TTyFunnelLabelSpec;
    { A store of ACount rows holding AValues. }
    function StoreOf(const AValues: array of Double): TTyDataStore;
  published
    procedure TestADomainOfNoWidthAnswersTheMiddleOfTheRange;
    procedure TestTheMapClampsBothWaysRound;
    procedure TestADescendingRangeIsNotSortedIntoOrder;
    procedure TestTheDefaultOrderIsWidestFirst;
    procedure TestOnlyTheWordNoneTurnsSortingOff;
    procedure TestTiesKeepTheirDataOrder;
    procedure TestTheBoxDefaultsAreARealInset;
    procedure TestOrientIsStrictEqualityAgainstHorizontal;
    procedure TestFunnelAlignTakesEitherVocabulary;
    procedure TestMinAndMaxAreAbsentNotZero;
    procedure TestTheLastBandTapersToTheWidthOfZero;
    procedure TestZeroRowsIsNotADivisionByZero;
    procedure TestAWrittenMinWidensTheDomainAndNarrowsTheBands;
    procedure TestTheSizeIsMeasuredAcrossTheStackNotAlongIt;
    procedure TestTheCornerOrderIsTheContractTheLabelsRead;
    procedure TestAscendingFlipsFourThingsAtOnce;
    procedure TestALabelLineIsOffWhenTheLabelIs;
  end;

  TAdvChartFunnelDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    procedure Draw2(const AOption: string);
    function ColouredPixels: Integer;
    function Diagnostics: string;
  published
    procedure TestAFunnelDrawsAtAll;
    procedure TestItSaysNothingAboutHavingNoRenderer;
    procedure TestTheWidestBandIsAtTheTopAndAscendingMovesIt;
    procedure TestEachBandCarriesItsOwnDatum;
    procedure TestABandKeepsItsOwnDatumsColourAfterSorting;
  end;

implementation

const
  cW = 520;
  cH = 380;
  cFunnel =
    '{"tooltip":{"show":false},' +
    '"series":[{"type":"funnel","name":"P","data":[' +
    '{"name":"a","value":100},{"name":"b","value":80},' +
    '{"name":"c","value":60},{"name":"d","value":40}]}]}';

{ ==================== the rules ==================== }

procedure TAdvChartFunnelRuleTest.TearDown;
begin
  FreeAndNil(FOpt);
  FreeAndNil(FStore);
  inherited TearDown;
end;

function TAdvChartFunnelRuleTest.SpecOf(const AText: string): TTyFunnelSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses', FOpt.SetOptionText(AText));
  Result := TyFunnelSpecOf(FOpt, 0);
end;

function TAdvChartFunnelRuleTest.LabelSpecOf(
  const AText: string): TTyFunnelLabelSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses', FOpt.SetOptionText(AText));
  Result := TyFunnelLabelSpecOf(FOpt, 0, TyFunnelLabelSpecDefault);
end;

function TAdvChartFunnelRuleTest.StoreOf(
  const AValues: array of Double): TTyDataStore;
var i: Integer;
begin
  FreeAndNil(FStore);
  FStore := TTyDataStore.Create;
  FStore.AddDimension('value', ddtFloat);
  for i := 0 to High(AValues) do FStore.AppendRow([AValues[i]]);
  Result := FStore;
end;

procedure TAdvChartFunnelRuleTest.TestADomainOfNoWidthAnswersTheMiddleOfTheRange;
begin
  { THE BRANCH A PORT GETS WRONG, and it is not an edge case: every value the
    same is what a funnel of equal steps looks like. Upstream answers the
    MIDPOINT of the range -- not its start, not zero -- so ECharts draws
    half-width bands where a "denominator is zero, answer nothing" guard draws
    an empty chart. }
  AssertEquals(50.0, TyFunnelMap(7, 5, 5, 0, 100), 1e-9);
  { Unless the range has no width either, in which case there is one answer. }
  AssertEquals(30.0, TyFunnelMap(7, 5, 5, 30, 30), 1e-9);
end;

procedure TAdvChartFunnelRuleTest.TestTheMapClampsBothWaysRound;
begin
  AssertEquals('below', 0.0, TyFunnelMap(-5, 0, 100, 0, 200), 1e-9);
  AssertEquals('above', 200.0, TyFunnelMap(500, 0, 100, 0, 200), 1e-9);
  AssertEquals('between', 100.0, TyFunnelMap(50, 0, 100, 0, 200), 1e-9);
  { A DESCENDING DOMAIN clamps the other way round, and the branch is chosen
    by the sign of the span rather than by sorting the ends. }
  AssertEquals('below a descending domain', 0.0,
               TyFunnelMap(500, 100, 0, 0, 200), 1e-9);
  AssertEquals('above it', 200.0, TyFunnelMap(-5, 100, 0, 0, 200), 1e-9);
end;

procedure TAdvChartFunnelRuleTest.TestADescendingRangeIsNotSortedIntoOrder;
begin
  { `minSize` may legitimately exceed `maxSize` -- a funnel that widens
    downward -- and upstream handles it by sign rather than by normalising.
    Sorting the pair would silently turn that chart upside down. }
  AssertEquals(100.0, TyFunnelMap(0, 0, 100, 100, 0), 1e-9);
  AssertEquals(0.0, TyFunnelMap(100, 0, 100, 100, 0), 1e-9);
  AssertEquals(50.0, TyFunnelMap(50, 0, 100, 100, 0), 1e-9);
end;

procedure TAdvChartFunnelRuleTest.TestTheDefaultOrderIsWidestFirst;
var o: TTyIntegerArray;
begin
  o := TyFunnelOrder(StoreOf([10, 30, 20]), 0, fsDescending);
  AssertEquals(3, Length(o));
  AssertEquals('largest first', 1, o[0]);
  AssertEquals(2, o[1]);
  AssertEquals(0, o[2]);
  o := TyFunnelOrder(StoreOf([10, 30, 20]), 0, fsAscending);
  AssertEquals('smallest first', 0, o[0]);
  AssertEquals(2, o[1]);
  AssertEquals(1, o[2]);
  o := TyFunnelOrder(StoreOf([10, 30, 20]), 0, fsNone);
  AssertEquals('data order', 0, o[0]);
  AssertEquals(1, o[1]);
  AssertEquals(2, o[2]);
end;

procedure TAdvChartFunnelRuleTest.TestOnlyTheWordNoneTurnsSortingOff;
var s: TTyFunnelSpec;
begin
  { Upstream's guard is `sort !== 'none'`, not a whitelist -- so a misspelling
    sorts DESCENDING rather than leaving the data alone. Reproduced rather
    than tightened: tightening it would draw a different chart from ECharts
    for the same option text. }
  s := SpecOf('{"series":[{"type":"funnel","sort":"asc"}]}');
  AssertTrue('a typo sorts descending', s.Sort = fsDescending);
  s := SpecOf('{"series":[{"type":"funnel","sort":"none"}]}');
  AssertTrue(s.Sort = fsNone);
  s := SpecOf('{"series":[{"type":"funnel","sort":"ascending"}]}');
  AssertTrue(s.Sort = fsAscending);
end;

procedure TAdvChartFunnelRuleTest.TestTiesKeepTheirDataOrder;
var o: TTyIntegerArray;
begin
  { STABLE. JavaScript's sort is, so upstream's ties keep data order -- and an
    unstable one would shuffle equal bands differently on every render of the
    same chart, which is the kind of defect nobody reports and everybody
    notices. }
  o := TyFunnelOrder(StoreOf([10, 10, 10, 5]), 0, fsDescending);
  AssertEquals(0, o[0]);
  AssertEquals(1, o[1]);
  AssertEquals(2, o[2]);
  AssertEquals('and the small one is last', 3, o[3]);
end;

procedure TAdvChartFunnelRuleTest.TestTheBoxDefaultsAreARealInset;
var s: TTyFunnelSpec;
begin
  { 80 / 60 / 80 / 65 -- not the pie's zero box. It is why a default funnel
    leaves room for its own labels, and why porting the pie's defaults across
    would push every label off the control. }
  s := TyFunnelSpecDefault;
  AssertEquals(80.0, s.Box.Left.Value, 1e-9);
  AssertEquals(60.0, s.Box.Top.Value, 1e-9);
  AssertEquals(80.0, s.Box.Right.Value, 1e-9);
  AssertEquals(65.0, s.Box.Bottom.Value, 1e-9);
  AssertTrue('and no size, so the edges decide', s.Box.Width.Kind = buAuto);
end;

procedure TAdvChartFunnelRuleTest.TestOrientIsStrictEqualityAgainstHorizontal;
var s: TTyFunnelSpec;
begin
  s := SpecOf('{"series":[{"type":"funnel","orient":"horizontal"}]}');
  AssertTrue(s.Horizontal);
  { Upstream's test is `=== 'horizontal'`, so everything else -- including
    garbage and including the word that means the other thing -- is vertical. }
  s := SpecOf('{"series":[{"type":"funnel","orient":"Horizontal"}]}');
  AssertFalse('capitalised is not it', s.Horizontal);
  s := SpecOf('{"series":[{"type":"funnel","orient":"sideways"}]}');
  AssertFalse(s.Horizontal);
end;

procedure TAdvChartFunnelRuleTest.TestFunnelAlignTakesEitherVocabulary;
var s: TTyFunnelSpec;
begin
  { UPSTREAM HAS ONE OPTION WITH TWO DISJOINT VOCABULARIES -- left/center/right
    when vertical, top/center/bottom when horizontal -- and each switch handles
    only its own three, leaving the other three to fall through to an
    UNINITIALISED local. That is NaN geometry there and stack garbage here, so
    the port collapses both onto one axis. A deliberate divergence, and the
    better answer: `funnelAlign: 'top'` on a vertical funnel plainly means the
    same as `left`. }
  s := SpecOf('{"series":[{"type":"funnel","funnelAlign":"left"}]}');
  AssertTrue(s.Align = faStart);
  s := SpecOf('{"series":[{"type":"funnel","funnelAlign":"top"}]}');
  AssertTrue('the other vocabulary means the same thing', s.Align = faStart);
  s := SpecOf('{"series":[{"type":"funnel","funnelAlign":"right"}]}');
  AssertTrue(s.Align = faEnd);
  s := SpecOf('{"series":[{"type":"funnel","funnelAlign":"bottom"}]}');
  AssertTrue(s.Align = faEnd);
  s := SpecOf('{"series":[{"type":"funnel","funnelAlign":"middle"}]}');
  AssertTrue('and the word upstream leaves uninitialised is the centre',
             s.Align = faCentre);
end;

procedure TAdvChartFunnelRuleTest.TestMinAndMaxAreAbsentNotZero;
var s: TTyFunnelSpec;
begin
  { ABSENCE IS LOAD-BEARING and a sentinel cannot carry it: `min: 0` is a real
    instruction, and the fallback it replaces is not zero -- it is
    Min(smallest, 0), with NO matching ceiling on max. The two are asymmetric
    upstream on purpose. }
  s := TyFunnelSpecDefault;
  AssertFalse('no min', s.HasMin);
  AssertFalse('no max', s.HasMax);
  s := SpecOf('{"series":[{"type":"funnel","min":0}]}');
  AssertTrue('a written zero is written', s.HasMin);
  AssertEquals(0.0, s.Min_, 1e-9);
end;

procedure TAdvChartFunnelRuleTest.TestTheLastBandTapersToTheWidthOfZero;
var
  lay: TTyFunnelLayout;
  lastTop, lastBottom: Double;
begin
  { THE PHANTOM EDGE. The last band has no next row; upstream indexes one past
    the end, gets undefined, gets NaN and then zero -- so the far edge is the
    width of value ZERO, which with the default minSize is a point. Clamping
    to the last row instead would draw a rectangle. }
  lay := TyFunnelLayoutOf(TyFunnelSpecDefault, TyRectF(0, 0, 400, 400),
    StoreOf([100, 50]), 0);
  AssertTrue('it laid out', lay.Valid);
  AssertEquals('two bands', 2, Length(lay.Items));
  lastTop := lay.Items[1].Points[1].X - lay.Items[1].Points[0].X;
  lastBottom := lay.Items[1].Points[2].X - lay.Items[1].Points[3].X;
  AssertTrue('the last band has a top edge', lastTop > 1);
  AssertEquals('and tapers to nothing', 0.0, lastBottom, 1e-6);
end;

procedure TAdvChartFunnelRuleTest.TestAWrittenMinWidensTheDomainAndNarrowsTheBands;
var
  spec: TTyFunnelSpec;
  plain, wider: TTyFunnelLayout;
  a, b: Double;
begin
  { `min` HAS NO DEFAULT and its fallback is not zero -- it is Min(smallest, 0),
    which for all-positive data IS zero. So a written `min` can only be
    observed by writing one that differs.

    A NEGATIVE min WIDENS THE BAND, which reads backwards until you write it
    out: the domain's FLOOR moves down, so a positive value sits further up
    the range and maps to more of it. 50 in 0..100 is half; 50 in -100..100 is
    three quarters. }
  spec := TyFunnelSpecDefault;
  plain := TyFunnelLayoutOf(spec, TyRectF(0, 0, 400, 400),
    StoreOf([100, 50]), 0);
  spec.HasMin := True;
  spec.Min_ := -100;
  wider := TyFunnelLayoutOf(spec, TyRectF(0, 0, 400, 400),
    StoreOf([100, 50]), 0);
  AssertTrue(plain.Valid and wider.Valid);
  { The widest band is pinned to maxSize either way -- it is the domain's top
    -- so the one to watch is the SECOND. }
  a := plain.Items[1].Points[1].X - plain.Items[1].Points[0].X;
  b := wider.Items[1].Points[1].X - wider.Items[1].Points[0].X;
  AssertTrue(Format('a lower floor widens the smaller band (%g -> %g)',
                    [a, b]), b > a + 1);
end;

procedure TAdvChartFunnelRuleTest.TestTheSizeIsMeasuredAcrossTheStackNotAlongIt;
var
  lay: TTyFunnelLayout;
  spec: TTyFunnelSpec;
  widest: Double;
begin
  { THE PERCENT BASE IS THE CROSS AXIS. A value becomes a WIDTH on a vertical
    funnel, so `maxSize: '100%'` is the full width of the box and has nothing
    to do with its height.

    A SQUARE VIEWPORT CANNOT SEE THE DIFFERENCE, and the first version of this
    file used one throughout -- so a mutant that measured along the stack
    instead lived through every test in it. The box here is deliberately twice
    as wide as it is tall. }
  spec := TyFunnelSpecDefault;
  spec.Box.Left := TyBoxPx(0);
  spec.Box.Top := TyBoxPx(0);
  spec.Box.Right := TyBoxPx(0);
  spec.Box.Bottom := TyBoxPx(0);
  lay := TyFunnelLayoutOf(spec, TyRectF(0, 0, 400, 200), StoreOf([100, 50]), 0);
  AssertTrue(lay.Valid);
  widest := lay.Items[0].Points[1].X - lay.Items[0].Points[0].X;
  AssertEquals('the widest band is the full WIDTH of the box', 400.0,
               widest, 1.0);
end;

procedure TAdvChartFunnelRuleTest.TestZeroRowsIsNotADivisionByZero;
var lay: TTyFunnelLayout;
begin
  { `(viewSize - gap*(count-1)) / count` is NaN in JavaScript and the loop
    then runs no times; in Pascal it raises before anything else happens. }
  lay := TyFunnelLayoutOf(TyFunnelSpecDefault, TyRectF(0, 0, 400, 400),
    StoreOf([]), 0);
  AssertFalse('nothing to lay out', lay.Valid);
  AssertEquals(0, Length(lay.Items));
end;

procedure TAdvChartFunnelRuleTest.TestTheCornerOrderIsTheContractTheLabelsRead;
var lay: TTyFunnelLayout;
begin
  { THE WINDING DIFFERS BETWEEN ORIENTATIONS and the label pass reads the
    corners by INDEX -- `(p1+p2)/2` is the right edge vertically and the
    bottom edge horizontally. Normalising them to one convention would move
    every label without moving a single band. }
  lay := TyFunnelLayoutOf(TyFunnelSpecDefault, TyRectF(0, 0, 400, 400),
    StoreOf([100, 50]), 0);
  AssertTrue(lay.Valid);
  AssertTrue('p0 is above p3', lay.Items[0].Points[0].Y < lay.Items[0].Points[3].Y);
  AssertTrue('p0 is left of p1', lay.Items[0].Points[0].X < lay.Items[0].Points[1].X);
  AssertEquals('p0 and p1 share the top edge',
               lay.Items[0].Points[0].Y, lay.Items[0].Points[1].Y, 1e-9);
  AssertEquals('p2 and p3 share the bottom',
               lay.Items[0].Points[2].Y, lay.Items[0].Points[3].Y, 1e-9);
end;

procedure TAdvChartFunnelRuleTest.TestAscendingFlipsFourThingsAtOnce;
var
  down, up: TTyFunnelLayout;
  spec: TTyFunnelSpec;
begin
  { FOUR COUPLED CHANGES, not one: the step and the gap flip sign, the cursor
    starts at the FAR edge, and the order is reversed. Doing three of the four
    draws a funnel off the edge of its own box. What the picture comes to is
    that the widest band moves from the top to the bottom while the stack
    still fills the same rectangle. }
  spec := TyFunnelSpecDefault;
  down := TyFunnelLayoutOf(spec, TyRectF(0, 0, 400, 400), StoreOf([100, 20]), 0);
  spec.Sort := fsAscending;
  up := TyFunnelLayoutOf(spec, TyRectF(0, 0, 400, 400), StoreOf([100, 20]), 0);
  AssertTrue(down.Valid and up.Valid);
  AssertEquals('both fill the same box', 2, Length(up.Items));
  { Descending: the first band drawn is the widest and it is at the top. }
  AssertTrue('descending starts wide',
    (down.Items[0].Points[1].X - down.Items[0].Points[0].X) >
    (down.Items[1].Points[1].X - down.Items[1].Points[0].X));
  { Ascending: the first band drawn is still the widest -- the order was
    reversed -- but it now sits at the BOTTOM, because the cursor started at
    the far edge and the step is negative. }
  AssertTrue('ascending still draws the widest first',
    (up.Items[0].Points[1].X - up.Items[0].Points[0].X) >
    (up.Items[1].Points[1].X - up.Items[1].Points[0].X));
  AssertTrue('but puts it below the other',
    up.Items[0].Points[0].Y > up.Items[1].Points[0].Y);
end;

procedure TAdvChartFunnelRuleTest.TestALabelLineIsOffWhenTheLabelIs;
var s: TTyFunnelLabelSpec;
begin
  { UPSTREAM ANDs THE TWO AT OPTION TIME, not at draw time -- it bakes
    `labelLine.show := labelLine.show and label.show` into the resolved series
    option during init. Applying it at the draw site instead leaves the two
    able to disagree, which is how a hidden label keeps its guide line. }
  s := LabelSpecOf('{"series":[{"type":"funnel","label":{"show":false}}]}');
  AssertFalse('the label is off', s.Show);
  AssertFalse('and so is its line', s.LineShow);
  s := LabelSpecOf('{"series":[{"type":"funnel",' +
    '"label":{"show":false},"labelLine":{"show":true}}]}');
  AssertFalse('even when the line asked to stay', s.LineShow);
end;

{ ==================== the picture ==================== }

procedure TAdvChartFunnelDrawTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartFunnelDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartFunnelDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ ANOTHER FRAME OF THE SAME CHART. Assigning the option again would rebuild
  it, and rebuilding is exactly what clears what the pointer is over. }
procedure TAdvChartFunnelDrawTest.Draw2(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartFunnelDrawTest.ColouredPixels: Integer;
var
  x, y, lo, hi: Integer;
  row: PBGRAPixel;
begin
  Result := 0;
  for y := 0 to cH - 1 do
  begin
    row := FBmp.ScanLine[y];
    for x := 0 to cW - 1 do
    begin
      lo := Min(row^.red, Min(row^.green, row^.blue));
      hi := Max(row^.red, Max(row^.green, row^.blue));
      if (row^.alpha <> 0) and (hi - lo > 25) then Inc(Result);
      Inc(row);
    end;
  end;
end;

function TAdvChartFunnelDrawTest.Diagnostics: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

procedure TAdvChartFunnelDrawTest.TestAFunnelDrawsAtAll;
begin
  { IT COULD NOT, AND THE REASON WAS ONE LINE. The store branch for a series
    off every coordinate system was gated on the literal name `'pie'`, while
    the registry had said `scuBox` about a funnel since the day it was
    written -- so a funnel got a store of zero columns, its layout found no
    value dimension, and it drew nothing while claiming to have a renderer. }
  Draw(cFunnel);
  AssertTrue('the bands are on the canvas', ColouredPixels > 3000);
end;

procedure TAdvChartFunnelDrawTest.TestItSaysNothingAboutHavingNoRenderer;
begin
  Draw(cFunnel);
  AssertEquals('a funnel draws now', '', Diagnostics);
end;

procedure TAdvChartFunnelDrawTest.TestTheWidestBandIsAtTheTopAndAscendingMovesIt;
var
  topRun, bottomRun, y, x: Integer;
  row: PBGRAPixel;

  { How many coloured pixels there are on one scan line. }
  function RunAt(AY: Integer): Integer;
  var i, lo, hi: Integer; r: PBGRAPixel;
  begin
    Result := 0;
    r := FBmp.ScanLine[AY];
    for i := 0 to cW - 1 do
    begin
      lo := Min(r^.red, Min(r^.green, r^.blue));
      hi := Max(r^.red, Max(r^.green, r^.blue));
      if (r^.alpha <> 0) and (hi - lo > 25) then Inc(Result);
      Inc(r);
    end;
  end;

begin
  { A FUNNEL'S SHAPE IS ITS WHOLE POINT, and it is visible in two scan lines:
    near the top and near the bottom of the stack. Descending, the top line is
    the wider one; ascending, the bottom is. }
  Draw(cFunnel);
  topRun := RunAt(cH div 4);
  bottomRun := RunAt(cH * 3 div 4);
  AssertTrue(Format('descending is wide at the top (%d vs %d)',
                    [topRun, bottomRun]), topRun > bottomRun);

  Draw('{"tooltip":{"show":false},' +
       '"series":[{"type":"funnel","name":"P","sort":"ascending","data":[' +
       '{"name":"a","value":100},{"name":"b","value":80},' +
       '{"name":"c","value":60},{"name":"d","value":40}]}]}');
  topRun := RunAt(cH div 4);
  bottomRun := RunAt(cH * 3 div 4);
  AssertTrue(Format('ascending is wide at the bottom (%d vs %d)',
                    [topRun, bottomRun]), bottomRun > topRun);
  { The unused locals keep the scan-line helper's shape readable. }
  y := 0; x := 0; row := nil;
  if (y or x) <> 0 then ;
  if row <> nil then ;
end;

procedure TAdvChartFunnelDrawTest.TestABandKeepsItsOwnDatumsColourAfterSorting;
var
  px: TBGRAPixel;
  y: Integer;
begin
  { A FUNNEL IS SORTED, so a band's place in the stack is NOT its row -- and a
    colour keyed on the position would hand the top band the first row's
    colour whatever the data said. The fixture puts the small value first and
    gives each row a colour of its own, so the two orders disagree by
    construction: `a` is red and small, `b` is green and large, and descending
    puts GREEN on top.

    Nothing weaker asks the question. With the rows already in sorted order,
    position and row are the same number and both answers agree. }
  Draw('{"tooltip":{"show":false},' +
       '"series":[{"type":"funnel","name":"P","data":[' +
       '{"name":"a","value":40,"itemStyle":{"color":"#ff0000"}},' +
       '{"name":"b","value":100,"itemStyle":{"color":"#00ff00"}}]}]}');
  { A little below the top of the stack, on the centre line. }
  y := 0;
  repeat
    Inc(y);
    px := FBmp.GetPixel(cW div 2, y);
    { The first scan line down the middle that is not the card's own white. }
  until (y >= cH - 8) or (px.red < 230) or (px.green < 230) or (px.blue < 230);
  px := FBmp.GetPixel(cW div 2, y + 6);
  AssertTrue(Format('the top band is the LARGE row''s green (%d,%d,%d)',
                    [px.red, px.green, px.blue]),
             (px.green > 150) and (px.red < 120));
end;

procedure TAdvChartFunnelDrawTest.TestEachBandCarriesItsOwnDatum;
var
  d: TTyChartDatumRef;
  found, i: Integer;
begin
  { A BAND IS HITTABLE AND NAMES ITS ROW. A funnel is sorted, so the band's
    place in the stack is neither the view row nor the raw one -- which is the
    same reason a pie carries both numbers. }
  Draw(cFunnel);
  found := 0;
  for i := 0 to cH - 1 do
  begin
    d := FChart.HitTestAt(cW div 2, i);
    if TyChartDatumValid(d) then
    begin
      Inc(found);
      AssertEquals('the one series', 0, d.SeriesIndex);
      AssertTrue('a real row', (d.DataIndex >= 0) and (d.DataIndex < 4));
      Break;
    end;
  end;
  AssertEquals('a band was under the pointer', 1, found);
end;

initialization
  RegisterTest(TAdvChartFunnelRuleTest);
  RegisterTest(TAdvChartFunnelDrawTest);
end.
