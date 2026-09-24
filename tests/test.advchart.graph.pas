unit test.advchart.graph;
{$mode objfpc}{$H+}
{ The graph: nodes, the edges between them, and the box they are laid out in.

  THE BOX IS THE HALF NOBODY EXPECTS. A graph has no axes and no scales, so
  there is nothing to nice and nothing to tick -- and yet the geometry is the
  fiddliest part of the series, because `left: 'center'` does TWO different
  jobs in one function and the data rectangle it is fitted to usually does not
  exist. Most of what follows is about that. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Option, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Graph,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartGraphRuleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure TearDown; override;
    function SpecOf(const ABody: string): TTyGraphSpec;
  published
    procedure TestAnUnwrittenSeriesIsTheDefaultsAndTheDefaultsAreUpstreams;
    procedure TestTheCurvenessTableIsNotTheOneItsCommentDescribes;
    procedure TestTheDataRectIsPoisonedByOneUnplacedNode;
    procedure TestAFlatAxisIsWidenedBeforeTheAspectIsTaken;
    procedure TestTheBoxTakesFourFifthsOfOneAxisAndTheAspectDoesTheRest;
    procedure TestCentreIsAPositionAndThenAnAlignment;
    procedure TestTheBuilderEmitsAnEdgeAndTwoNodes;
    procedure TestTheViewIsAPureScaleAndTranslateOnEachAxisSeparately;
    procedure TestTheRingGivesEachNodeItsOwnSymbolsShareOfTheTurn;
    procedure TestOneRingNodeAndTwoAreTheCasesThatDivideByNothing;
    procedure TestTheCircularControlPointGoesToTheCentreNotSideways;
    procedure TestThePerpendicularControlPointIsNotSymmetric;
    procedure TestAnArrowheadPointsAlongTheCurveNotAtTheOtherNode;
    procedure TestTrimmingPullsTheEndsBackByTheNodesOwnRadius;
    procedure TestParallelEdgesTakeOppositeSidesAndAWrittenZeroKillsThem;
    procedure TestTheReaderTakesItsNamesAndIdsFromTheStore;
    procedure TestAnEdgeNamesItsEndsByIdOrByIndexAndADanglingOneIsDropped;
    procedure TestAnEdgeValueIsParsedLikeAnyDatum;
    procedure TestEdgesAndLinksAreOneKeyUnderTwoNames;
    procedure TestAScalarEdgeSymbolNamesBothEnds;
    procedure TestAnEdgeCanTakeTheColourOfTheNodeItLeaves;
    procedure TestTheRingIsInscribedInTheShorterSide;
    procedure TestAFixedNodeIsLeftWhereItIs;
    procedure TestASizeThatIsNotANumberBecomesTwoBeforeItIsCompared;
    procedure TestAnEvenNumberOfParallelEdgesIsSymmetricAboutTheLine;
    procedure TestAWrittenCurvenessTableIsNeverPadded;
    procedure TestAnEdgesOwnCurvenessBeatsTheSeries;
    procedure TestTheBuilderTrimsByTheNodesAveragedRadius;
    procedure TestOnlyTheLineAndTheNodesTakeThePointer;
    procedure TestABoxWrittenFromTheFarSideIsStillCentred;
    procedure TestTheRingIsLaidOutInDataSpaceAndCarriedThroughTheMap;
    procedure TestACurvedEdgeIsTrimmedAlongItsOwnCurve;
    procedure TestACurvenessThatIsNotANumberDrawsAStraightLine;
  end;

  TAdvChartGraphDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    function Diagnostics: string;
    function InkPixels: Integer;
  published
    procedure TestAGraphDrawsAtAll;
    procedure TestItSaysNothingAboutHavingNoRenderer;
    procedure TestALabelPutsTheNodesNameOnTheCanvas;
    procedure TestACircularGraphLandsInsideItsBoxWithNoPositionsAtAll;
  private
    function DarkPixels: Integer;
  end;

implementation

const
  Eps = 1e-6;
  cW = 480;
  cH = 320;
  cSimple =
    '{"series":[{"type":"graph","layout":"none","symbolSize":30,'
    + '"itemStyle":{"color":"#3366cc"},'
    + '"data":[{"name":"a","x":0,"y":0},{"name":"b","x":100,"y":0},'
    + '{"name":"c","x":50,"y":80}],'
    + '"links":[{"source":0,"target":1},{"source":1,"target":2}]}]}';

{ ==================== the rules ==================== }

procedure TAdvChartGraphRuleTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartGraphRuleTest.SpecOf(const ABody: string): TTyGraphSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses',
    FOpt.SetOptionText('{"series":[{"type":"graph"' + ABody + '}]}'));
  Result := TyGraphSpecOf(FOpt, 0);
end;

procedure TAdvChartGraphRuleTest.TestAnUnwrittenSeriesIsTheDefaultsAndTheDefaultsAreUpstreams;
var s: TTyGraphSpec;
begin
  s := SpecOf('');
  AssertEquals('layout null means none', Ord(glNone), Ord(s.Layout));
  AssertFalse('labels are not turned by default', s.RotateLabel);
  AssertEquals('a ten-pixel circle', 10.0, s.Symbol.WidthPx, Eps);
  AssertEquals(10.0, s.Symbol.HeightPx, Eps);
  AssertEquals('no arrowheads', 'none', s.EdgeSymbolFrom);
  AssertEquals('none', s.EdgeSymbolTo);
  AssertEquals('but a size for them anyway', 10.0, s.EdgeSizeFrom, Eps);
  AssertFalse('no curveness written', s.HasCurveness);
  AssertFalse('and the automatic table is OFF', s.AutoCurveness);
  AssertEquals('a one-pixel line', 1.0, s.LineWidthLogical, Eps);
  AssertEquals('at half opacity', 0.5, s.LineOpacity, Eps);
  AssertEquals('z is two', 2, s.Z);
  { `left: 'center'`, `top: 'center'` AND NOTHING ELSE. The commented-out
    `width: '80%'` in the source is not dead documentation -- see the box
    tests below for where the four fifths really comes from. }
  AssertEquals('the centre, already a percentage', Ord(gpkPct),
    Ord(s.PosLeft.Kind));
  AssertEquals(50.0, s.PosLeft.V, Eps);
  AssertEquals(Ord(gpkPct), Ord(s.PosTop.Kind));
  AssertEquals(50.0, s.PosTop.V, Eps);
  AssertEquals('and no width at all', Ord(gpkNaN), Ord(s.PosWidth.Kind));
  AssertEquals(Ord(gpkNaN), Ord(s.PosHeight.Kind));
  AssertEquals('centred both ways', 'center', s.AlignH);
  AssertEquals('center', s.AlignV);
end;

procedure TAdvChartGraphRuleTest.TestTheCurvenessTableIsNotTheOneItsCommentDescribes;
var s: TTyGraphSpec;
begin
  { THE NUMERATOR DIFFERS BETWEEN THE TWO BRANCHES. Odd entries are
    -(i + 1) / 10 and even ones are i / 10, so the table pairs up as
    (0), (-0.2, 0.2), (-0.4, 0.4) -- and index zero is the only entry that is
    exactly nothing. }
  AssertEquals(0.0, TyGraphCurvenessAt(0), Eps);
  AssertEquals(-0.2, TyGraphCurvenessAt(1), Eps);
  AssertEquals(0.2, TyGraphCurvenessAt(2), Eps);
  AssertEquals(-0.4, TyGraphCurvenessAt(3), Eps);
  AssertEquals(0.4, TyGraphCurvenessAt(4), Eps);

  { AND THE LENGTH IS ODD, whatever the comment says. `length mod 2 ? + 2 : + 3`
    is odd for every integer input, so the twenty the source documents is
    really twenty-three entries. }
  s := SpecOf(',"autoCurveness":true');
  AssertTrue('true turns it on', s.AutoCurveness);
  AssertEquals('and leaves the length at twenty', 20.0, s.AutoLength, Eps);
  AssertEquals('which is a table of twenty-three', 23,
    TyGraphCurvenessLength(s, -1));

  s := SpecOf(',"autoCurveness":5');
  AssertEquals(7, TyGraphCurvenessLength(s, -1));
  s := SpecOf(',"autoCurveness":4');
  AssertEquals(7, TyGraphCurvenessLength(s, -1));

  { ZERO TURNS IT OFF, because the read is laundered through a truthiness
    test; an empty ARRAY does not, because an empty array is truthy. }
  AssertFalse('zero is off', SpecOf(',"autoCurveness":0').AutoCurveness);
  AssertFalse('false is off', SpecOf(',"autoCurveness":false').AutoCurveness);
  s := SpecOf(',"autoCurveness":[]');
  AssertTrue('an empty array is ON', s.AutoCurveness);
  AssertTrue(s.HasAutoList);
  AssertEquals('with a table of nothing', 0, TyGraphCurvenessLength(s, -1));
end;

procedure TAdvChartGraphRuleTest.TestTheDataRectIsPoisonedByOneUnplacedNode;
var nodes: TTyGraphNodeArray; r: TTyRectF; a: Double;
begin
  { ONE BAD NODE POISONS ALL FOUR BOUNDS, and that is not a defect to route
    around: it is what sends the whole chart down the "there is nothing to
    fit" branch, where the data rectangle becomes the box and the map becomes
    the identity. A port that skipped the unplaced nodes would fit the one
    node somebody placed to the whole canvas and park it in the middle. }
  SetLength(nodes, 3);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[2] := Default(TTyGraphNode);
  nodes[0].X := 10; nodes[0].Y := 20;
  nodes[1].X := 40; nodes[1].Y := 60;
  nodes[2].X := NaN; nodes[2].Y := NaN;
  AssertFalse('one unplaced node and there is no data rect at all',
    TyGraphDataRect(nodes, r, a));
  AssertTrue('and no aspect either', IsNan(a));

  nodes[2].X := 25;
  nodes[2].Y := 30;
  AssertTrue('place it and the box appears', TyGraphDataRect(nodes, r, a));
  AssertEquals(10.0, r.Left, Eps);
  AssertEquals(20.0, r.Top, Eps);
  AssertEquals(40.0, r.Right, Eps);
  AssertEquals(60.0, r.Bottom, Eps);
  AssertEquals('the aspect is width over height', 30.0 / 40.0, a, Eps);
end;

procedure TAdvChartGraphRuleTest.TestAFlatAxisIsWidenedBeforeTheAspectIsTaken;
var nodes: TTyGraphNodeArray; r: TTyRectF; a: Double;
begin
  { A ROW OF NODES SHARING A Y has no height, and the aspect is a division by
    it. Upstream widens a flat axis by exactly one on each side FIRST -- so the
    span becomes two, never nothing -- and takes the aspect after. }
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].X := 0; nodes[0].Y := 5;
  nodes[1].X := 8; nodes[1].Y := 5;
  AssertTrue(TyGraphDataRect(nodes, r, a));
  AssertEquals('widened by one on each side', 4.0, r.Top, Eps);
  AssertEquals(6.0, r.Bottom, Eps);
  AssertEquals('and the aspect divides by the two, not by nothing',
    8.0 / 2.0, a, Eps);

  { ONE NODE IS FLAT ON BOTH AXES, so both are widened and the aspect is one. }
  SetLength(nodes, 1);
  AssertTrue(TyGraphDataRect(nodes, r, a));
  AssertEquals(-1.0, r.Left, Eps);
  AssertEquals(1.0, r.Right, Eps);
  AssertEquals(1.0, a, Eps);
end;

procedure TAdvChartGraphRuleTest.TestTheBoxTakesFourFifthsOfOneAxisAndTheAspectDoesTheRest;
var s: TTyGraphSpec; r: TTyRectF;
begin
  { THE FOUR FIFTHS IS NOT A DEFAULT WIDTH. With neither size written, ONE axis
    takes four fifths of the container -- whichever one the aspect says will
    then fit -- and the other follows from the aspect. Which axis it is
    depends on the data, which is why this cannot be a constant. }
  s := SpecOf('');
  { A WIDE aspect against a square container: the width is capped. }
  r := TyGraphViewRect(s, TyRectF(0, 0, 400, 400), 2.0);
  AssertEquals(320.0, r.Right - r.Left, Eps);
  AssertEquals('and the height follows the aspect', 160.0, r.Bottom - r.Top, Eps);

  { A TALL one against the same container: the HEIGHT is capped instead. }
  r := TyGraphViewRect(s, TyRectF(0, 0, 400, 400), 0.5);
  AssertEquals(320.0, r.Bottom - r.Top, Eps);
  AssertEquals(160.0, r.Right - r.Left, Eps);

  { AND WITH NO ASPECT AT ALL -- the ordinary chart, where no node carries a
    position -- the branch STILL RUNS, and this assertion used to say the
    opposite. It said the box was the whole container, which is what skipping
    the branch gives; upstream does not skip it. `NaN > x` is false, so the
    HEIGHT takes four fifths and the width, left not-a-number by the aspect,
    is filled in from the container at the very end. Every circular and every
    force graph with no positions is laid out in this box, and the oracle in
    test.advchart.graphforce is what caught it. }
  r := TyGraphViewRect(s, TyRectF(0, 0, 400, 300), NaN);
  AssertEquals(400.0, r.Right - r.Left, Eps);
  AssertEquals('four fifths of the height', 240.0, r.Bottom - r.Top, Eps);
  AssertEquals('centred in it', 30.0, r.Top, Eps);
end;

procedure TAdvChartGraphRuleTest.TestCentreIsAPositionAndThenAnAlignment;
var s: TTyGraphSpec; r: TTyRectF;
begin
  { THE SAME WORD DOES TWO JOBS IN ONE FUNCTION. `left: 'center'` is first
    parsed as a POSITION -- fifty per cent of the container -- and then read
    again as a centring instruction that overwrites it. Only the second
    reading survives, which is why a centred box really is centred rather than
    starting at the middle. }
  s := SpecOf('');
  r := TyGraphViewRect(s, TyRectF(0, 0, 400, 400), 2.0);
  AssertEquals('centred, not started at the half way point',
    (400.0 - 320.0) / 2, r.Left, Eps);
  AssertEquals((400.0 - 160.0) / 2, r.Top, Eps);

  { A WRITTEN SIDE IS A POSITION AND STAYS ONE. }
  s := SpecOf(',"left":20,"top":10,"width":100,"height":50');
  r := TyGraphViewRect(s, TyRectF(0, 0, 400, 400), 2.0);
  AssertEquals(20.0, r.Left, Eps);
  AssertEquals(10.0, r.Top, Eps);
  AssertEquals('and a written size beats the aspect outright',
    100.0, r.Right - r.Left, Eps);
  AssertEquals(50.0, r.Bottom - r.Top, Eps);
end;

procedure TAdvChartGraphRuleTest.TestTheBuilderEmitsAnEdgeAndTwoNodes;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
  n: Integer;
begin
  { THE BUILDER ON ITS OWN, with no control and no theme: two nodes, one edge
    between them, and nothing else in the way. }
  s := SpecOf('');
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].PX := 10; nodes[0].PY := 10; nodes[0].Row := 0;
  nodes[1].PX := 90; nodes[1].PY := 50; nodes[1].Row := 1;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Source := 0;
  edges[0].Target := 1;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 2);
  ink.NodeFills[0] := TTyChartColor($FF3366CC);
  ink.NodeFills[1] := TTyChartColor($FF3366CC);
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100), TyRectF(0, 0, 100, 100));
  list := TTyPaintList.Create;
  try
    n := TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('one edge and two nodes', 3, n);
    AssertEquals('and they all reached the list', 3, list.Count);
    AssertEquals('the edge comes first, under the nodes',
      Ord(cskPolyline), Ord(list.Element(0).Shape.Kind));
    AssertTrue('and the nodes are filled', list.Element(1).Style.HasFill);
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestTheViewIsAPureScaleAndTranslateOnEachAxisSeparately;
var view: TTyGraphView; p: TTyPointF; d: TTyDoubleArray;
begin
  { THE TWO AXES SCALE INDEPENDENTLY. Upstream fits the data rect to the view
    rect with sx = b.width / a.width and sy = b.height / a.height and does not
    preserve the aspect -- so a NON-SQUARE pair of rectangles is the only
    fixture that can tell a uniform fit from this one. }
  view := TTyGraphView.Create(TyRectF(0, 0, 10, 100),
                              TyRectF(100, 50, 300, 250));
  try
    AssertEquals('the view rect is what GetRect answers', 100.0,
      view.GetRect.Left, Eps);
    AssertEquals('and the DATA rect is a different question', 0.0,
      view.GetDataRect.Left, Eps);
    p := view.DataToPoint([0, 0]);
    AssertEquals(100.0, p.X, Eps);
    AssertEquals(50.0, p.Y, Eps);
    p := view.DataToPoint([10, 100]);
    AssertEquals(300.0, p.X, Eps);
    AssertEquals(250.0, p.Y, Eps);
    { TWENTY TIMES ACROSS AND TWICE DOWN. }
    p := view.DataToPoint([1, 50]);
    AssertEquals(120.0, p.X, Eps);
    AssertEquals(150.0, p.Y, Eps);
    AssertTrue('and it inverts', view.PointToData(TyPointF(120, 150), d));
    AssertEquals(1.0, d[0], Eps);
    AssertEquals(50.0, d[1], Eps);
  finally
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestTheRingGivesEachNodeItsOwnSymbolsShareOfTheTurn;
var
  nodes: TTyGraphNodeArray;
  view: TTyGraphView;
  s: TTyGraphSpec;
  i: Integer;
  a0, a1, a2: Double;

  { A DIFFERENCE OF ANGLES, FOLDED INTO ONE FORWARD TURN. ArcTan2 answers in
    (-Pi, Pi], so the third node of four comes back negative and a raw
    subtraction reports a turn and a quarter backwards. }
  function Turn(AValue: Double): Double;
  begin
    Result := TyModTwoPi(AValue);
    if Result < 0 then Result := Result + 2 * Pi;
  end;

begin
  { EVERY NODE THE SAME SIZE MAKES THE SHARE CANCEL OUT. With one symbol size
    the half-share is PI/count whatever the radius and whatever the size, so
    the nodes come out evenly spaced -- and a port that got the arithmetic
    wrong still looks right on this fixture. It is the UNEQUAL case that tells
    them apart, which is the second half below. }
  s := SpecOf('');
  SetLength(nodes, 4);
  for i := 0 to 3 do
  begin
    nodes[i] := Default(TTyGraphNode);
    nodes[i].X := NaN;
    nodes[i].Y := NaN;
  end;
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  try
    TyGraphLayoutCircular(nodes, view, s);
    { THE FIRST NODE IS NOT AT ANGLE ZERO. The angle advances by the node's own
      half-share BEFORE the node is placed, so it sits in the middle of its
      share rather than on its edge -- with four equal nodes that is a quarter
      turn in, at PI/4. }
    a0 := ArcTan2(nodes[0].PY - 100, nodes[0].PX - 100);
    a1 := ArcTan2(nodes[1].PY - 100, nodes[1].PX - 100);
    a2 := ArcTan2(nodes[2].PY - 100, nodes[2].PX - 100);
    AssertEquals('a quarter turn in', Pi / 4, a0, 1e-9);
    AssertEquals('and a quarter turn apart', Pi / 2,
      Turn(a1 - a0), 1e-9);
    AssertEquals(Pi / 2, Turn(a2 - a1), 1e-9);
    AssertEquals('on the ring', 100.0,
      Sqrt(Sqr(nodes[0].PX - 100) + Sqr(nodes[0].PY - 100)), 1e-9);
  finally
    view.Free;
  end;

  { ONE FAT NODE TAKES A WIDER SLICE, and the others give it up. }
  nodes[0].HasSize := True;
  nodes[0].SizeW := 120;
  nodes[0].SizeH := 120;
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  try
    TyGraphLayoutCircular(nodes, view, s);
    a0 := ArcTan2(nodes[0].PY - 100, nodes[0].PX - 100);
    a1 := ArcTan2(nodes[1].PY - 100, nodes[1].PX - 100);
    AssertTrue('the fat node is pushed further round than a quarter turn',
      a0 > Pi / 4 + 0.01);
    AssertTrue('and the gap after it is wider than the one after a thin one',
      Turn(a1 - a0) > Pi / 2 + 0.01);
  finally
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestOneRingNodeAndTwoAreTheCasesThatDivideByNothing;
var nodes: TTyGraphNodeArray; view: TTyGraphView; s: TTyGraphSpec;
begin
  { NO NODES AT ALL is the only guard upstream has against dividing the turn by
    nothing, and it has to come before the two passes rather than inside
    them. }
  s := SpecOf('');
  nodes := nil;
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  try
    TyGraphLayoutCircular(nodes, view, s);
    AssertEquals('nothing to place', 0, Length(nodes));
  finally
    view.Free;
  end;

  { A SYMBOL WIDER THAN THE RING asks for the arcsine of something over one.
    Upstream gets not-a-number back and replaces it with a quarter turn; the
    port clamps instead, which is the same answer without the trip. }
  SetLength(nodes, 1);
  nodes[0] := Default(TTyGraphNode);
  nodes[0].X := NaN;
  nodes[0].Y := NaN;
  nodes[0].HasSize := True;
  nodes[0].SizeW := 5000;
  nodes[0].SizeH := 5000;
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  try
    TyGraphLayoutCircular(nodes, view, s);
    AssertFalse('it still lands somewhere real', IsNan(nodes[0].PX));
    AssertFalse(IsNan(nodes[0].PY));
    AssertEquals('on the ring', 100.0,
      Sqrt(Sqr(nodes[0].PX - 100) + Sqr(nodes[0].PY - 100)), 1e-9);
  finally
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestTheCircularControlPointGoesToTheCentreNotSideways;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
  mid: TTyPointF;
  pts: TTyPointFArray;
begin
  { THE RING'S EDGES BOW INWARD, and that is a COMPLETELY different rule from
    every other layout's: the curveness is tripled and the midpoint slid
    towards the ring's own centre, so a third puts the control point exactly
    on the centre. A port that reused the perpendicular offset here draws a
    chord diagram whose chords bulge outward. }
  { THE CHORD IS OFF THE CENTRE ON PURPOSE. Run it THROUGH the centre and its
    midpoint IS the centre, so the lerp interpolates between two identical
    points and the factor of three cannot matter -- the fixture's own symmetry
    eats the feature it is testing. }
  s := SpecOf(',"layout":"circular","lineStyle":{"curveness":0.3333333333333}');
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].X := 0;   nodes[0].Y := 0;
  nodes[1].X := 200; nodes[1].Y := 0;
  nodes[0].PX := 0;   nodes[0].PY := 0;
  nodes[1].PX := 200; nodes[1].PY := 0;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 2);
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  list := TTyPaintList.Create;
  try
    TyGraphSolveCurveness(edges, s, True);
    AssertEquals('a written curveness is taken as written',
      0.3333333333333, edges[0].SolvedCurveness, 1e-9);
    TyGraphEdgeGeometry(edges, nodes, view, True);
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    { THE RING'S CENTRE IS (100, 100) AND THE CHORD RUNS ALONG y = 0, so a
      tripled third puts the control point exactly ON the centre and the curve's
      middle halfway there, at y = 50. Untripled it would sit at y = 33 and the
      middle at y = 17; offset perpendicularly it would not be on the ring's
      axis at all. }
    mid := TyGraphPointAt(TyPointF(0, 0), TyPointF(200, 0),
                          TyPointF(100, 100), True, 0.5);
    AssertEquals(100.0, mid.X, Eps);
    AssertEquals(50.0, mid.Y, Eps);
    pts := list.Element(0).Shape.Points;
    AssertEquals(100.0, pts[8].X, 0.001);
    AssertEquals('bowed halfway to the ring''s own centre',
      50.0, pts[8].Y, 0.001);
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestThePerpendicularControlPointIsNotSymmetric;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
  pts: TTyPointFArray;
begin
  { THE TWO AXES SUBTRACT DIFFERENT DIFFERENCES: x takes (p1.y - p2.y) and y
    takes (p2.x - p1.x). Copying one line onto the other mirrors every curve,
    and a HORIZONTAL or VERTICAL edge cannot see it -- one of the two terms is
    zero either way. This edge is diagonal for exactly that reason. }
  s := SpecOf(',"lineStyle":{"curveness":0.5}');
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].X := 0;   nodes[0].Y := 0;
  nodes[1].X := 100; nodes[1].Y := 100;
  nodes[0].PX := 0;   nodes[0].PY := 0;
  nodes[1].PX := 100; nodes[1].PY := 100;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 2);
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  list := TTyPaintList.Create;
  try
    TyGraphSolveCurveness(edges, s, False);
    TyGraphEdgeGeometry(edges, nodes, view, False);
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    { THE BOUNDING BOX CANNOT SEE IT. Both control points -- the right one at
      (100, 0) and its mirror at (100, 100) -- give the identical box over this
      chord, so the box is exactly the wrong thing to assert. A POINT on the
      curve is what separates them.

      midpoint (50,50); the offset is x: 50 - (0 - 100) * 0.5 = 100 and
      y: 50 - (100 - 0) * 0.5 = 0, so the control point is at (100, 0) -- up
      and to the RIGHT of the chord -- and the curve's own middle is then at
      (75, 25) rather than the mirror's (75, 75). }
    pts := list.Element(0).Shape.Points;
    AssertEquals('sampled with a point in the middle', 17, Length(pts));
    AssertEquals(75.0, pts[8].X, 0.001);
    AssertEquals('above the chord, not below it', 25.0, pts[8].Y, 0.001);
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestAnArrowheadPointsAlongTheCurveNotAtTheOtherNode;
var tg: TTyPointF; deg: Double;
begin
  { THE TANGENT IS THE DERIVATIVE, NOT THE CHORD. At the two ends a quadratic's
    tangent is the leg of its control polygon -- (cp - p1) and (p2 - cp) -- so
    an arrowhead on a curved edge leaves along the curve. A port that used the
    chord points it at the other node, which on a strongly bowed edge is
    visibly wrong. }
  tg := TyGraphTangentAt(TyPointF(0, 0), TyPointF(100, 0), TyPointF(50, -80),
                         True, 0);
  AssertEquals('at the tail it is the first leg', 2 * 50.0, tg.X, Eps);
  AssertEquals(2 * -80.0, tg.Y, Eps);
  tg := TyGraphTangentAt(TyPointF(0, 0), TyPointF(100, 0), TyPointF(50, -80),
                         True, 1);
  AssertEquals('and at the head the second', 2 * 50.0, tg.X, Eps);
  AssertEquals(2 * 80.0, tg.Y, Eps);

  { A STRAIGHT EDGE HAS ONE TANGENT EVERYWHERE. }
  tg := TyGraphTangentAt(TyPointF(0, 0), TyPointF(10, 0), TyPointF(0, 0),
                         False, 0.3);
  AssertEquals(10.0, tg.X, Eps);
  AssertEquals(0.0, tg.Y, Eps);

  { AND THE TWO ENDS TURN THEIR ARROWS OPPOSITE WAYS. The sign selector is the
    only thing that tells the tail's arrowhead from the head's. }
  { A TANGENT ALONG x IS THE ONE THAT CANNOT SEE IT: atan2 is zero there, so
    subtracting it changes nothing and an arrowhead that ignored the tangent
    altogether would give the same answer. }
  deg := TyGraphArrowRotation(TyPointF(0, 1), False);
  AssertEquals('the tail''s turn takes the tangent off the quarter',
    0.0, deg, 1e-9);
  deg := TyGraphArrowRotation(TyPointF(0, 1), True);
  AssertEquals('and the head''s the other way', -180.0, deg, 1e-9);
  deg := TyGraphArrowRotation(TyPointF(1, 0), False);
  AssertEquals('along x the two happen to agree', 90.0, deg, 1e-9);
end;

procedure TAdvChartGraphRuleTest.TestTrimmingPullsTheEndsBackByTheNodesOwnRadius;
var p1, p2, cp: TTyPointF;
begin
  { THE DISTANCE IS THE RADIUS, NOT THE DIAMETER. Upstream halves its scale
    parameter once, at the top of the function, so a fifty-pixel node pulls
    the edge back twenty-five. }
  p1 := TyPointF(0, 0);
  p2 := TyPointF(100, 0);
  cp := TyPointF(0, 0);
  TyGraphTrimEdge(p1, p2, cp, False, 25, 10, True, True);
  AssertEquals(25.0, p1.X, Eps);
  AssertEquals(90.0, p2.X, Eps);
  AssertEquals('and neither end moves off the line', 0.0, p1.Y, Eps);

  { ONLY THE ENDS THAT CARRY A SYMBOL ARE TRIMMED. A plain line runs centre to
    centre and is covered by the discs at both ends, which is what makes an
    unarrowed graph look right. }
  p1 := TyPointF(0, 0);
  p2 := TyPointF(100, 0);
  TyGraphTrimEdge(p1, p2, cp, False, 25, 10, False, True);
  AssertEquals('the tail stayed where it was', 0.0, p1.X, Eps);
  AssertEquals(90.0, p2.X, Eps);

  { AND NEITHER IS ASKED FOR AT ALL, so nothing happens. }
  p1 := TyPointF(0, 0);
  p2 := TyPointF(100, 0);
  TyGraphTrimEdge(p1, p2, cp, False, 25, 10, False, False);
  AssertEquals(0.0, p1.X, Eps);
  AssertEquals(100.0, p2.X, Eps);

  { A SELF-LOOP HAS NO DIRECTION TO PULL ALONG, so neither end moves rather
    than both ending up not-a-number. }
  p1 := TyPointF(40, 40);
  p2 := TyPointF(40, 40);
  TyGraphTrimEdge(p1, p2, cp, False, 25, 25, True, True);
  AssertEquals(40.0, p1.X, Eps);
  AssertEquals(40.0, p2.X, Eps);
end;

procedure TAdvChartGraphRuleTest.TestParallelEdgesTakeOppositeSidesAndAWrittenZeroKillsThem;
var
  edges: TTyGraphEdgeArray;
  nodes: TTyGraphNodeArray;
  view: TTyGraphView;
  s: TTyGraphSpec;
  i: Integer;
begin
  { THREE EDGES ON ONE PAIR take three different entries of the table, and the
    table alternates sides -- which is the whole point of it. }
  s := SpecOf(',"autoCurveness":true');
  SetLength(edges, 3);
  for i := 0 to 2 do
  begin
    edges[i] := Default(TTyGraphEdge);
    edges[i].Source := 0;
    edges[i].Target := 1;
  end;
  { THE RING READS THE TABLE AS IT IS: 0, -0.2, 0.2 -- entry zero is exactly
    straight, which is why the pair either side of it is what has to be
    asserted. }
  TyGraphSolveCurveness(edges, s, True);
  AssertEquals('the first of three is dead straight', 0.0,
    edges[0].SolvedCurveness, Eps);
  AssertEquals('the second bows one way', -0.2, edges[1].SolvedCurveness, Eps);
  AssertEquals('and the third the other', 0.2, edges[2].SolvedCurveness, Eps);
  { AND EVERY OTHER LAYOUT NEGATES IT. `-getCurvenessForEdge(...)` is written
    at both call sites, unconditionally, so the same three edges under `none`
    or `force` bow the opposite way to the same three on a ring. }
  TyGraphSolveCurveness(edges, s, False);
  AssertEquals(0.0, edges[0].SolvedCurveness, Eps);
  AssertEquals('negated', 0.2, edges[1].SolvedCurveness, Eps);
  AssertEquals(-0.2, edges[2].SolvedCurveness, Eps);

  { THERE AND BACK: TWO EQUAL NUMBERS, AND THAT IS RIGHT. Neither key is ever
    flagged forward -- the flag is set only on an insertion that finds its own
    key already there -- so both read the far side of the table, entry two,
    and both come out 0.2. They still do not land on one line, because the
    perpendicular turns round with the edge: the same curveness on an edge
    running the other way bows to the other side. That is the property worth
    asserting, and the numbers are not where it lives. }
  SetLength(edges, 2);
  edges[0] := Default(TTyGraphEdge);
  edges[1] := Default(TTyGraphEdge);
  edges[0].Source := 0; edges[0].Target := 1;
  edges[1].Source := 1; edges[1].Target := 0;
  TyGraphSolveCurveness(edges, s, False);
  AssertEquals(0.2, edges[0].SolvedCurveness, Eps);
  AssertEquals('the same number both ways', 0.2, edges[1].SolvedCurveness, Eps);
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[1].X := 100;
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100), TyRectF(0, 0, 100, 100));
  try
    TyGraphEdgeGeometry(edges, nodes, view, False);
    AssertEquals('one bows up', -20.0, edges[0].CPY, Eps);
    AssertEquals('and the other down', 20.0, edges[1].CPY, Eps);
  finally
    view.Free;
  end;
  { AND ON A RING THE SAME TWO LAND ON ONE CURVE. The ring's control point
    slides towards the centre whichever way the edge runs, so two equal
    numbers make one curve drawn twice -- upstream's answer, and the one place
    a there-and-back pair is not separated. }
  TyGraphSolveCurveness(edges, s, True);
  AssertEquals(0.2, edges[0].SolvedCurveness, Eps);
  AssertEquals(0.2, edges[1].SolvedCurveness, Eps);

  { AND A WRITTEN ZERO BEATS THE WHOLE TABLE. The three consumers all test for
    absence and nothing else, so `curveness: 0` at the series level kills every
    automatic curve -- which is exactly what the option's own comment says. }
  s := SpecOf(',"autoCurveness":true,"lineStyle":{"curveness":0}');
  SetLength(edges, 3);
  for i := 0 to 2 do
  begin
    edges[i] := Default(TTyGraphEdge);
    edges[i].Source := 0;
    edges[i].Target := 1;
  end;
  TyGraphSolveCurveness(edges, s, False);
  for i := 0 to 2 do
    AssertEquals('every one of them is straight', 0.0,
      edges[i].SolvedCurveness, Eps);
end;

{ A store shaped the way the control fills one for a graph: a value column, a
  name and an id per row, and everything else as a scalar override. }
function GraphStore: TTyDataStore;
begin
  Result := TTyDataStore.Create;
  Result.AddDimension('value', ddtFloat);
  Result.AppendRow([1.0]);
  Result.AppendRow([2.0]);
  Result.AppendRow([3.0]);
  Result.SetName(0, 'Alpha');
  Result.SetName(1, 'Beta');
  Result.SetName(2, 'Gamma');
  Result.SetId(0, 'n0');
  Result.SetId(1, 'n1');
  Result.SetId(2, 'n2');
  { TWO OF THE THREE ARE PLACED. The third is what makes the data rectangle
    impossible, which is the ordinary case rather than the exotic one. }
  Result.SetOverride(0, TyOverrideKey('x'), TyDataNum(10));
  Result.SetOverride(0, TyOverrideKey('y'), TyDataNum(20));
  Result.SetOverride(1, TyOverrideKey('x'), TyDataNum(40));
  Result.SetOverride(1, TyOverrideKey('y'), TyDataNum(60));
end;

procedure TAdvChartGraphRuleTest.TestTheReaderTakesItsNamesAndIdsFromTheStore;
var st: TTyDataStore; nodes: TTyGraphNodeArray; r: TTyRectF; a: Double;
begin
  st := GraphStore;
  try
    nodes := TyGraphNodesOf(st, nil);
    AssertEquals(3, Length(nodes));
    AssertEquals('names come from the store''s own name column',
      'Alpha', nodes[0].Name_);
    { THE ID IS NOT AN OVERRIDE. The store keeps value, name and id out of the
      override table -- they are the datum's identity, not options written on
      it -- so a reader that goes looking in the table finds nothing and every
      edge that names an id then resolves to nowhere. }
    AssertEquals('and so do ids', 'n1', nodes[1].Id);

    { A NODE WITH NO x IS NOT A NODE AT ZERO. }
    AssertEquals(10.0, nodes[0].X, Eps);
    AssertTrue('the unplaced one has no position at all', IsNan(nodes[2].X));
    AssertTrue(IsNan(nodes[2].Y));

    { AND NONE OF THEM IS PINNED. `fixed` is what a DRAG writes; a written x and
      y says where a node goes under `layout: none` and feeds the box, and it
      does not stop a layout placing the node. }
    AssertFalse('a placed node is not a pinned one', nodes[0].Fixed);
    AssertFalse(nodes[2].Fixed);

    AssertFalse('and one unplaced node leaves no box to fit',
      TyGraphDataRect(nodes, r, a));
  finally
    st.Free;
  end;
end;

{ An edge's `value` is a datum like any other: parseDataValue's Number() of
  anything but the empty string. [Batch 53: it was Trim + TryStrToFloat,
  which read '0x10' and '   ' as not numbers.] }
procedure TAdvChartGraphRuleTest.TestAnEdgeValueIsParsedLikeAnyDatum;
var st: TTyDataStore; nodes: TTyGraphNodeArray; edges: TTyGraphEdgeArray;
begin
  st := GraphStore;
  try
    nodes := TyGraphNodesOf(st, nil);
    FreeAndNil(FOpt);
    FOpt := TTyChartOption.Create;
    AssertTrue(FOpt.SetOptionText(
      '{"series":[{"type":"graph","links":['
      + '{"source":0,"target":1,"value":"0x10"},'
      + '{"source":0,"target":2,"value":"   "},'
      + '{"source":1,"target":2,"value":""},'
      + '{"source":1,"target":0,"value":"Inf"},'
      + '{"source":2,"target":0,"value":"Infinity"}]}]}'));
    edges := TyGraphEdgesOf(FOpt, 0, nodes);
    AssertEquals('five edges', 5, Length(edges));
    AssertEquals('hex', 16, edges[0].Value, 0);
    AssertEquals('blanks are nought', 0, edges[1].Value, 0);
    AssertTrue('empty is no number', IsNan(edges[2].Value));
    AssertTrue('Inf is no number', IsNan(edges[3].Value));
    AssertTrue('Infinity is infinite', IsInfinite(edges[4].Value));
  finally
    st.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestAnEdgeNamesItsEndsByIdOrByIndexAndADanglingOneIsDropped;
var st: TTyDataStore; nodes: TTyGraphNodeArray; edges: TTyGraphEdgeArray;
begin
  st := GraphStore;
  try
    nodes := TyGraphNodesOf(st, nil);
    FreeAndNil(FOpt);
    FOpt := TTyChartOption.Create;
    AssertTrue(FOpt.SetOptionText(
      '{"series":[{"type":"graph","links":['
      + '{"source":"n0","target":"n2"},'
      + '{"source":0,"target":1},'
      + '{"source":"Alpha","target":"Beta"},'
      + '{"source":"n0","target":"nowhere"}]}]}'));
    edges := TyGraphEdgesOf(FOpt, 0, nodes);
    { TWO OF THE FOUR SURVIVE, and this assertion used to say three. An id and
      an index resolve; the one naming a node that is not there is DROPPED
      rather than kept with an endpoint of minus one. And the one written by
      NAME is dropped too: upstream files every node under ONE key,
      `retrieve(id, name, index)`, so a node that has an id cannot be reached
      by its name at all. Reading the name as well kept an edge upstream never
      draws. }
    AssertEquals(2, Length(edges));
    AssertEquals('an id resolves', 0, edges[0].Source);
    AssertEquals(2, edges[0].Target);
    AssertEquals('an index resolves', 0, edges[1].Source);
    AssertEquals(1, edges[1].Target);

    { WITHOUT AN ID THE NAME IS THE KEY, and with neither the node's POSITION
      spelled as a string is. }
    nodes[0].Id := '';
    nodes[1].Id := '';
    nodes[2].Id := '';
    nodes[2].Name_ := '';
    FreeAndNil(FOpt);
    FOpt := TTyChartOption.Create;
    AssertTrue(FOpt.SetOptionText(
      '{"series":[{"type":"graph","links":['
      + '{"source":"Alpha","target":"Beta"},'
      + '{"source":"Beta","target":"2"},'
      + '{"source":"n0","target":"Gamma"}]}]}'));
    edges := TyGraphEdgesOf(FOpt, 0, nodes);
    AssertEquals('the name and the position resolve, the gone id does not',
      2, Length(edges));
    AssertEquals(0, edges[0].Source);
    AssertEquals(1, edges[0].Target);
    AssertEquals('the third node is reached as "2"', 2, edges[1].Target);
  finally
    st.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestEdgesAndLinksAreOneKeyUnderTwoNames;
var st: TTyDataStore; nodes: TTyGraphNodeArray; edges: TTyGraphEdgeArray;
begin
  st := GraphStore;
  try
    nodes := TyGraphNodesOf(st, nil);
    FreeAndNil(FOpt);
    FOpt := TTyChartOption.Create;
    AssertTrue(FOpt.SetOptionText(
      '{"series":[{"type":"graph","edges":[{"source":0,"target":1}]}]}'));
    edges := TyGraphEdgesOf(FOpt, 0, nodes);
    AssertEquals('the other spelling is read too', 1, Length(edges));
    AssertEquals(0, edges[0].Source);
    AssertEquals(1, edges[0].Target);
  finally
    st.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestAScalarEdgeSymbolNamesBothEnds;
var s: TTyGraphSpec;
begin
  { A BARE STRING NAMES BOTH ENDS. The pair form is the documented one, which
    is why the scalar is easy to leave out -- and leaving it out puts an
    arrowhead on one end of every edge in the chart. }
  s := SpecOf(',"edgeSymbol":"arrow"');
  AssertEquals('arrow', s.EdgeSymbolFrom);
  AssertEquals('arrow', s.EdgeSymbolTo);
  s := SpecOf(',"edgeSymbolSize":8');
  AssertEquals(8.0, s.EdgeSizeFrom, Eps);
  AssertEquals(8.0, s.EdgeSizeTo, Eps);
  { AND THE PAIR FORM STILL NAMES THEM SEPARATELY. }
  s := SpecOf(',"edgeSymbol":["circle","arrow"],"edgeSymbolSize":[4,10]');
  AssertEquals('circle', s.EdgeSymbolFrom);
  AssertEquals('arrow', s.EdgeSymbolTo);
  AssertEquals(4.0, s.EdgeSizeFrom, Eps);
  AssertEquals(10.0, s.EdgeSizeTo, Eps);
end;

procedure TAdvChartGraphRuleTest.TestAnEdgeCanTakeTheColourOfTheNodeItLeaves;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
begin
  { `lineStyle.color` TAKES TWO WORDS THAT ARE NOT COLOURS, and they are the
    only reason a chord diagram reads as anything but a grey smudge. }
  s := SpecOf(',"lineStyle":{"color":"source"}');
  AssertEquals(Ord(gecSource), Ord(s.ColourBy));
  AssertFalse('and it is not a colour', s.HasLineColour);
  AssertEquals(Ord(gecTarget),
    Ord(SpecOf(',"lineStyle":{"color":"target"}').ColourBy));
  AssertEquals('anything else still is', Ord(gecFixed),
    Ord(SpecOf(',"lineStyle":{"color":"#ff0000"}').ColourBy));

  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].PX := 10; nodes[0].PY := 10;
  nodes[1].PX := 90; nodes[1].PY := 10;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 2);
  ink.NodeFills[0] := TTyChartColor($FF111111);
  ink.NodeFills[1] := TTyChartColor($FF222222);
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100), TyRectF(0, 0, 100, 100));
  list := TTyPaintList.Create;
  try
    s := SpecOf(',"lineStyle":{"color":"source"}');
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('the edge leaves node zero', LongWord($FF111111),
      LongWord(list.Element(0).Style.StrokeColor));
    list.Clear;
    s := SpecOf(',"lineStyle":{"color":"target"}');
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('and arrives at node one', LongWord($FF222222),
      LongWord(list.Element(0).Style.StrokeColor));
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestTheRingIsInscribedInTheShorterSide;
var nodes: TTyGraphNodeArray; view: TTyGraphView; s: TTyGraphSpec; i: Integer;
begin
  { AN OBLONG BOX, and that is the whole fixture: on a square one the shorter
    side and the longer one are the same number and the ring is right either
    way. }
  s := SpecOf('');
  SetLength(nodes, 4);
  for i := 0 to 3 do
  begin
    nodes[i] := Default(TTyGraphNode);
    nodes[i].X := NaN;
    nodes[i].Y := NaN;
  end;
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 120), TyRectF(0, 0, 200, 120));
  try
    TyGraphLayoutCircular(nodes, view, s);
    for i := 0 to 3 do
      AssertEquals('every node is sixty from the centre, not a hundred',
        60.0, Sqrt(Sqr(nodes[i].PX - 100) + Sqr(nodes[i].PY - 60)), 1e-9);
  finally
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestAFixedNodeIsLeftWhereItIs;
var nodes: TTyGraphNodeArray; view: TTyGraphView; s: TTyGraphSpec; i: Integer;
begin
  { THE FIELD THE DRAG WILL WRITE. There is no drag yet, so nothing sets this
    and the guard has no fixture of its own -- but the guard has to hold before
    the drag exists rather than after, or the first drag moves a node and the
    next layout pass puts it back. }
  s := SpecOf('');
  SetLength(nodes, 3);
  for i := 0 to 2 do
  begin
    nodes[i] := Default(TTyGraphNode);
    nodes[i].X := NaN;
    nodes[i].Y := NaN;
  end;
  nodes[1].Fixed := True;
  nodes[1].X := 7;
  nodes[1].Y := 9;
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  try
    TyGraphLayoutCircular(nodes, view, s);
    AssertEquals('the pinned node kept its place', 7.0, nodes[1].PX, 1e-9);
    AssertEquals(9.0, nodes[1].PY, 1e-9);
    AssertEquals('while the rest went round the ring', 100.0,
      Sqrt(Sqr(nodes[0].PX - 100) + Sqr(nodes[0].PY - 100)), 1e-9);
  finally
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestASizeThatIsNotANumberBecomesTwoBeforeItIsCompared;
var nodes: TTyGraphNodeArray; view: TTyGraphView; s: TTyGraphSpec; i: Integer;
    a0, a1: Double;
begin
  { THE TWO DEFENSIVE LINES RUN IN ONE ORDER AND NOT THE OTHER. A size that is
    not a number becomes two FIRST -- upstream says the two is arbitrary -- and
    only then is a negative one flattened. Reversed, the comparison has to look
    at a not-a-number, which raises here; and failing that the node takes a
    QUARTER of the turn instead of a hair of it. }
  s := SpecOf('');
  SetLength(nodes, 4);
  for i := 0 to 3 do
  begin
    nodes[i] := Default(TTyGraphNode);
    nodes[i].X := NaN;
    nodes[i].Y := NaN;
  end;
  nodes[0].HasSize := True;
  nodes[0].SizeW := NaN;
  nodes[0].SizeH := NaN;
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  try
    TyGraphLayoutCircular(nodes, view, s);
    AssertFalse('it landed somewhere real', IsNan(nodes[0].PX));
    a0 := ArcTan2(nodes[0].PY - 100, nodes[0].PX - 100);
    a1 := ArcTan2(nodes[1].PY - 100, nodes[1].PX - 100);
    { A TWO-PIXEL SYMBOL ON A HUNDRED-PIXEL RING takes almost none of the turn,
      so the first node sits a hair under a quarter turn in -- nowhere near the
      three eighths a quarter-turn share would give it. }
    AssertTrue('a hair under a quarter turn', (a0 > Pi / 4 - 0.05)
      and (a0 < Pi / 4 + 0.001));
    AssertTrue('and the next is about a quarter turn on',
      (a1 - a0 > Pi / 2 - 0.05) and (a1 - a0 < Pi / 2 + 0.05));
  finally
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestAnEvenNumberOfParallelEdgesIsSymmetricAboutTheLine;
var edges: TTyGraphEdgeArray; s: TTyGraphSpec; i: Integer;
begin
  { THE PARITY CORRECTION, and only an EVEN count can see it. With two edges the
    table is entered one slot later, so they take -0.2 and 0.2 -- one either
    side -- rather than 0 and -0.2, which would leave one of the pair lying on
    the line it was supposed to be drawn beside. }
  s := SpecOf(',"autoCurveness":true');
  SetLength(edges, 2);
  for i := 0 to 1 do
  begin
    edges[i] := Default(TTyGraphEdge);
    edges[i].Source := 0;
    edges[i].Target := 1;
  end;
  TyGraphSolveCurveness(edges, s, True);
  AssertEquals(-0.2, edges[0].SolvedCurveness, 1e-9);
  AssertEquals(0.2, edges[1].SolvedCurveness, 1e-9);
  { And the other family, negated: the pair still straddles the line. }
  TyGraphSolveCurveness(edges, s, False);
  AssertEquals(0.2, edges[0].SolvedCurveness, 1e-9);
  AssertEquals(-0.2, edges[1].SolvedCurveness, 1e-9);
end;

procedure TAdvChartGraphRuleTest.TestAWrittenCurvenessTableIsNeverPadded;
var edges: TTyGraphEdgeArray; s: TTyGraphSpec; i: Integer;
begin
  { AN AUTHOR'S TABLE IS TAKEN AS GIVEN. It is never extended, never padded and
    never validated -- so a third edge on a two-entry table reads past the end
    and comes back straight rather than falling through to the built-in
    table. }
  s := SpecOf(',"autoCurveness":[0.1,0.2]');
  AssertTrue(s.HasAutoList);
  SetLength(edges, 3);
  for i := 0 to 2 do
  begin
    edges[i] := Default(TTyGraphEdge);
    edges[i].Source := 0;
    edges[i].Target := 1;
  end;
  TyGraphSolveCurveness(edges, s, True);
  AssertEquals(0.1, edges[0].SolvedCurveness, 1e-9);
  AssertEquals(0.2, edges[1].SolvedCurveness, 1e-9);
  { ON A RING, NOTHING FALLS THROUGH TO THE ZERO: `retrieve3` skips an
    undefined entry and lands on its third argument. }
  AssertEquals('and the third finds nothing', 0.0,
    edges[2].SolvedCurveness, 1e-9);
  { ANYWHERE ELSE IT IS NEGATED FIRST, and `-undefined` is not a number --
    which the geometry then reads as a straight line, the same picture by a
    different route. }
  TyGraphSolveCurveness(edges, s, False);
  AssertEquals(-0.1, edges[0].SolvedCurveness, 1e-9);
  AssertEquals(-0.2, edges[1].SolvedCurveness, 1e-9);
  AssertTrue('and the third is not a number',
    IsNan(edges[2].SolvedCurveness));
end;

procedure TAdvChartGraphRuleTest.TestAnEdgesOwnCurvenessBeatsTheSeries;
var edges: TTyGraphEdgeArray; s: TTyGraphSpec;
begin
  { THREE SOURCES, NEAREST FIRST. The edge's own beats the series', which beats
    the automatic table -- and each of them counts a written zero. }
  s := SpecOf(',"lineStyle":{"curveness":0.4}');
  SetLength(edges, 2);
  edges[0] := Default(TTyGraphEdge);
  edges[1] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  edges[1].Target := 1;
  edges[1].HasCurveness := True;
  edges[1].Curveness := -0.9;
  TyGraphSolveCurveness(edges, s, False);
  AssertEquals('the one that said nothing takes the series''',
    0.4, edges[0].SolvedCurveness, 1e-9);
  AssertEquals('and the one that spoke keeps its own',
    -0.9, edges[1].SolvedCurveness, 1e-9);
end;

procedure TAdvChartGraphRuleTest.TestTheBuilderTrimsByTheNodesAveragedRadius;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
  pts: TTyPointFArray;
begin
  { THE DISTANCE IS THE RADIUS AND AN OBLONG NODE IS AVERAGED FIRST, and both
    of those live in the BUILDER rather than in the trim -- which takes its
    distances already worked out, so a test that calls the trim directly cannot
    see either. }
  s := SpecOf(',"edgeSymbol":["arrow","arrow"],"symbolSize":40');
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].PX := 0;   nodes[0].PY := 0;
  nodes[1].PX := 200; nodes[1].PY := 0;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 2);
  view := TTyGraphView.Create(TyRectF(0, 0, 200, 200), TyRectF(0, 0, 200, 200));
  list := TTyPaintList.Create;
  try
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    pts := list.Element(0).Shape.Points;
    AssertEquals('forty across means twenty back', 20.0, pts[0].X, 1e-6);
    AssertEquals(180.0, pts[1].X, 1e-6);

    { AN OBLONG NODE IS AVERAGED TO ONE NUMBER FIRST: forty by twenty is thirty,
      and half of that is fifteen -- not twenty and not ten. }
    list.Clear;
    nodes[0].HasSize := True;
    nodes[0].SizeW := 40;
    nodes[0].SizeH := 20;
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    pts := list.Element(0).Shape.Points;
    AssertEquals(15.0, pts[0].X, 1e-6);
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestOnlyTheLineAndTheNodesTakeThePointer;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
  i, hittable: Integer;
begin
  { AN ARROWHEAD IS PART OF THE LINE'S PICTURE, not a second thing to point at:
    two hittable things for one edge report it twice. }
  s := SpecOf(',"edgeSymbol":["arrow","arrow"],"symbolSize":10');
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].PX := 10; nodes[0].PY := 10; nodes[0].Row := 0;
  nodes[1].PX := 90; nodes[1].PY := 10; nodes[1].Row := 1;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 2);
  ink.NodeFills[0] := TTyChartColor($FF3366CC);
  ink.NodeFills[1] := TTyChartColor($FF3366CC);
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100), TyRectF(0, 0, 100, 100));
  list := TTyPaintList.Create;
  try
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('one line, two arrowheads and two nodes', 5, list.Count);
    hittable := 0;
    for i := 0 to list.Count - 1 do
      if not list.Element(i).Silent then Inc(hittable);
    AssertEquals('and three of the five answer the pointer', 3, hittable);
    AssertFalse('the line is one of them', list.Element(0).Silent);

    { AND A NODE IS DRAWN ABOVE ITS OWN EDGES. They share a z and the list
      breaks the tie by insertion, so saying it out loud is what keeps it true
      the day an edge is appended after a node. }
    AssertTrue('the node sits above', list.Element(list.Count - 1).Z2
      > list.Element(0).Z2);

    { A SELF-LOOP WITH NO CURVENESS HAS NOWHERE TO GO, so no line is emitted at
      all -- and a node with no position is skipped rather than built on
      not-a-number. }
    list.Clear;
    edges[0].Target := 0;
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('two nodes and no line', 2, list.Count);
    list.Clear;
    edges[0].Target := 1;
    nodes[1].PX := NaN;
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('and an unplaced node takes its edge with it', 1, list.Count);
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestABoxWrittenFromTheFarSideIsStillCentred;
var s: TTyGraphSpec; r: TTyRectF;
begin
  { `right` DOES NOT MOVE A GRAPH, and this is the surprise. Its own default is
    `left: 'center'`, so `left` is never absent -- and the centring arm, which
    is read AFTER the sizes are settled, overwrites whatever the far side would
    have implied. A box written as `right: 20, width: 100` therefore comes out
    CENTRED at 150, not tucked 20 in from the right edge at 280.

    That is upstream's answer too, by the same route: `left` enters
    getLayoutRect as a number, so the derivation of a missing side never fires
    and the `switch` on the alignment word has the last word. }
  s := SpecOf(',"right":20,"width":100');
  r := TyGraphViewRect(s, TyRectF(0, 0, 400, 400), NaN);
  AssertEquals('centred, and the right edge ignored', 150.0, r.Left, Eps);
  AssertEquals(250.0, r.Right, Eps);

  { A WRITTEN `left` IS OBEYED, so the centring really is the default speaking
    rather than the function ignoring the option. }
  s := SpecOf(',"left":20,"right":20,"width":100');
  r := TyGraphViewRect(s, TyRectF(0, 0, 400, 400), NaN);
  AssertEquals(20.0, r.Left, Eps);
  AssertEquals(120.0, r.Right, Eps);
end;

procedure TAdvChartGraphRuleTest.TestTheRingIsLaidOutInDataSpaceAndCarriedThroughTheMap;
var nodes: TTyGraphNodeArray; view: TTyGraphView; s: TTyGraphSpec; i: Integer;
begin
  { THE RING GOES IN THE DATA RECTANGLE AND IS THEN MAPPED. On the ordinary
    circular chart the two rectangles are the SAME one -- nobody wrote a
    position, so the data rect was replaced by the box -- which is exactly why
    a fixture built that way cannot tell the two apart. This one makes them
    differ. }
  s := SpecOf('');
  SetLength(nodes, 4);
  for i := 0 to 3 do
  begin
    nodes[i] := Default(TTyGraphNode);
    nodes[i].X := NaN;
    nodes[i].Y := NaN;
  end;
  { data (0,0)-(100,100) onto view (200,200)-(400,400): twice the size, moved. }
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100),
                              TyRectF(200, 200, 400, 400));
  try
    TyGraphLayoutCircular(nodes, view, s);
    for i := 0 to 3 do
      AssertEquals('placed on a ring of fifty in DATA space', 50.0,
        Sqrt(Sqr(nodes[i].X - 50) + Sqr(nodes[i].Y - 50)), 1e-9);
    for i := 0 to 3 do
      AssertEquals('and carried to one of a hundred in pixels', 100.0,
        Sqrt(Sqr(nodes[i].PX - 300) + Sqr(nodes[i].PY - 300)), 1e-9);
  finally
    view.Free;
  end;
end;

procedure TAdvChartGraphRuleTest.TestACurvedEdgeIsTrimmedAlongItsOwnCurve;
var p1, p2, cp: TTyPointF; before: TTyPointF;
begin
  { THE CURVED BRANCH KEEPS THE FAR HALF AT THE TAIL AND THE NEAR HALF AT THE
    HEAD, and getting the halves the wrong way round throws most of the edge
    away rather than trimming it. }
  p1 := TyPointF(0, 0);
  p2 := TyPointF(200, 0);
  cp := TyPointF(100, 100);
  before := p1;
  TyGraphTrimEdge(p1, p2, cp, True, 20, 20, True, True);
  AssertTrue('the tail moved along the curve, away from where it was',
    p1.X > before.X + 5);
  AssertTrue('and it went DOWN the curve rather than staying on the line',
    p1.Y > 1);
  AssertTrue('the head came back the other way', p2.X < 195);
  AssertTrue(p2.Y > 1);
  { AND BOTH ENDS ARE ABOUT THE SYMBOL'S RADIUS FROM WHERE THEY STARTED. }
  AssertEquals('the tail is twenty from the node it left',
    20.0, Sqrt(Sqr(p1.X - 0) + Sqr(p1.Y - 0)), 1.0);
  AssertEquals('and the head twenty from the node it reaches',
    20.0, Sqrt(Sqr(p2.X - 200) + Sqr(p2.Y - 0)), 1.0);
end;

procedure TAdvChartGraphRuleTest.TestACurvenessThatIsNotANumberDrawsAStraightLine;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
begin
  { THE ONE PLACE A NOT-A-NUMBER IS LAUNDERED in the whole edge pipeline.
    Upstream tests the curveness with a unary plus rather than against zero, and
    not-a-number is falsy there -- so the edge comes out STRAIGHT rather than
    with a control point nobody can draw. It is reachable: a written curveness
    table shorter than the edges that share a pair leaves the lookup with
    nothing. }
  s := SpecOf('');
  SetLength(nodes, 2);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[0].X := 10; nodes[0].Y := 10;
  nodes[1].X := 90; nodes[1].Y := 50;
  nodes[0].PX := 10; nodes[0].PY := 10;
  nodes[1].PX := 90; nodes[1].PY := 50;
  SetLength(edges, 1);
  edges[0] := Default(TTyGraphEdge);
  edges[0].Target := 1;
  edges[0].SolvedCurveness := NaN;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 2);
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100), TyRectF(0, 0, 100, 100));
  list := TTyPaintList.Create;
  try
    TyGraphEdgeGeometry(edges, nodes, view, False);
    AssertFalse('the layout authors no control point', edges[0].Curved);
    AssertFalse('and does not hide the edge either', edges[0].Hidden);
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('two points, not seventeen', 2,
      Length(list.Element(0).Shape.Points));
    AssertEquals(10.0, list.Element(0).Shape.Points[0].X, Eps);
    AssertEquals(90.0, list.Element(0).Shape.Points[1].X, Eps);
  finally
    list.Free;
    view.Free;
  end;
end;

{ ==================== the picture ==================== }

procedure TAdvChartGraphDrawTest.SetUp;
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

procedure TAdvChartGraphDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartGraphDrawTest.Diagnostics: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

function TAdvChartGraphDrawTest.InkPixels: Integer;
var x, y: Integer; p: TBGRAPixel;
begin
  Result := 0;
  for y := 0 to cH - 1 do
    for x := 0 to cW - 1 do
    begin
      p := FBmp.GetPixel(x, y);
      if (p.alpha = 255) and (p.blue > p.red + 30) and (p.blue > 100) then
        Inc(Result);
    end;
end;

function TAdvChartGraphDrawTest.DarkPixels: Integer;
var x, y: Integer; p: TBGRAPixel;
begin
  { NEITHER THE GROUND NOR THE NODES. The surface is near-white and the nodes
    are the palette's blue, so what is left that is DARK is the words. }
  Result := 0;
  for y := 0 to cH - 1 do
    for x := 0 to cW - 1 do
    begin
      p := FBmp.GetPixel(x, y);
      if (p.alpha = 255) and (p.red < 120) and (p.green < 120)
        and (p.blue < 120) then Inc(Result);
    end;
end;

procedure TAdvChartGraphDrawTest.TestALabelPutsTheNodesNameOnTheCanvas;
const
  cHead = '{"series":[{"type":"graph","layout":"none","symbolSize":10,'
    + '"data":[{"name":"Wolverhampton","x":0,"y":0,"value":7},'
    + '{"name":"Northumberland","x":100,"y":80,"value":9}]';
var off, on_: Integer;
begin
  { A NODE'S LABEL IS ITS NAME, and the graph is the only series here whose
    default formatter says so. Every other one defaults to the VALUE -- and
    these nodes carry a value too, so a port that took the shared default puts
    `7` and `9` on the canvas instead of two long words. The two are told apart
    by how much dark ink there is. }
  Draw(cHead + '}]}');
  off := DarkPixels;
  { PLACED OUTSIDE THE NODE ON PURPOSE. A graph's label sits INSIDE its symbol
    by default, in the ink that reads against the fill -- white on a blue disc
    -- and a ten-pixel disc has nowhere to put a word anyway. Moved to the
    right it is dark text on the chart's own ground, which is a thing a pixel
    count can see. }
  Draw(cHead + ',"label":{"show":true,"position":"right"}}]}');
  on_ := DarkPixels;
  AssertTrue(Format('nothing is written by default (%d px)', [off]),
    off < 40);
  { TWENTY-NINE CHARACTERS OF NAME against two digits of value: the two
    defaults are an order of magnitude apart in ink, which is what the
    threshold is sitting between. }
  AssertTrue(Format('and two long names are a lot of ink (%d px)', [on_]),
    on_ > off + 100);
end;

procedure TAdvChartGraphDrawTest.TestACircularGraphLandsInsideItsBoxWithNoPositionsAtAll;
var ink: Integer;
begin
  { NO NODE CARRIES A POSITION, which is the ORDINARY case rather than the
    exotic one: there is no bounding box to fit, so the data rectangle is
    replaced by the box and the map becomes the identity. Without that
    substitution the ring is laid out against an invalid rectangle and nothing
    reaches the canvas at all. }
  Draw('{"series":[{"type":"graph","layout":"circular","symbolSize":20,'
    + '"itemStyle":{"color":"#3366cc"},'
    + '"data":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"},'
    + '{"name":"e"},{"name":"f"}],'
    + '"links":[{"source":0,"target":3},{"source":1,"target":4}]}]}');
  ink := InkPixels;
  AssertTrue(Format('six nodes on a ring (%d px), %s', [ink, Diagnostics]),
    ink > 800);
  { AND THEY ARE ON A RING RATHER THAN IN A HEAP: a heap of six twenty-pixel
    discs on one point is about the area of one. }
  AssertTrue('spread out, not stacked', ink > 5 * 20 * 20 * 3 div 4);
end;

procedure TAdvChartGraphDrawTest.TestAGraphDrawsAtAll;
var ink: Integer;
begin
  Draw(cSimple);
  ink := InkPixels;
  AssertTrue(Format('three nodes and two edges reach the canvas (%d px), %s',
    [ink, Diagnostics]), ink > 400);
end;

procedure TAdvChartGraphDrawTest.TestItSaysNothingAboutHavingNoRenderer;
begin
  Draw(cSimple);
  AssertEquals('a graph draws now, got: ' + Diagnostics, '', Diagnostics);
end;

initialization
  RegisterTest(TAdvChartGraphRuleTest);
  RegisterTest(TAdvChartGraphDrawTest);
end.
