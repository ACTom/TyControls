unit test.advchart.graphforce;
{$mode objfpc}{$H+}
{ The graph's force layout -- and, because the force layout shares them, the
  curveness table and the box -- held to upstream's own output.

  THE ORACLE IS UPSTREAM, RUN. tools/advchart-oracle/graph-force.js drives the
  real ECharts 6.1 build in node's server-side mode, with Math.random replaced
  by the xorshift this port uses and seeded the same way, and writes where
  every node and every control point landed to
  tests/fixtures/advchart-graph-force.json. The force layout is five hundred
  steps of arithmetic whose every multiplier is the author's; a transcription
  that does the same operations in the same order lands on the same Doubles,
  and one that does not drifts visibly within a few dozen steps. So the first
  test here compares against upstream's numbers directly rather than against
  anything derived by hand.

  The rest are the rules the oracle cannot name -- it says THAT a case is
  wrong, not which line -- and the things it cannot see at all: that nothing
  raises, that the control really runs this, and that a pass which changes
  nothing costs nothing. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Graph,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartGraphOracleTest = class(TTestCase)
  published
    procedure TestEveryCaseLandsWhereUpstreamLaidItOut;
  end;

  TAdvChartGraphForceTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure TearDown; override;
    function SpecOf(const ABody: string): TTyGraphSpec;
  published
    procedure TestTheRandomNumbersAreTheOnesUpstreamIsGiven;
    procedure TestTheStepCountIsUpstreamsAndNeverUnderTwo;
    procedure TestLinearMapHasAMiddleAndTwoExactEnds;
    procedure TestForceReadsItsRangesTheWayUpstreamDoes;
    procedure TestInitLayoutKnowsTwoWordsAndEverythingElseIsNothing;
    procedure TestFixedClimbsFromTheNodeToItsCategoryToTheSeries;
    procedure TestACategoryNamedRatherThanIndexedIsNoParent;
    procedure TestAPassThatChangesNothingRunsNoSteps;
    procedure TestAViewWithNoAspectIsFourFifthsOfTheHeight;
    procedure TestTheAlignmentIsTheWordNotThePosition;
    procedure TestNoLegalForceOptionRaisesOrLeavesTheTrapsOff;
    procedure TestAControlPointNobodyCanDrawTakesItsEdgeWithIt;
    procedure TestTheHostsNextTrapIsReportedForWhatItIs;
  end;

  TAdvChartGraphForceDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(AW, AH: Integer);
    function InkAt(AX, AY: Double): Boolean;
  published
    procedure TestAForceGraphDrawsWhereTheLayoutPutIt;
    procedure TestAResizeContinuesAndANewOptionStartsAgain;
  end;

implementation

const
  { A force graph with nothing placed: the ordinary case, and the one whose
    random start and whose box both come from the rules above. }
  cSix = '{"series":[{"type":"graph","layout":"force",'
    + '"force":{"layoutAnimation":false},'
    + '"data":[{"name":"n1","value":1},{"name":"n2","value":2},'
    + '{"name":"n3","value":3},{"name":"n4","value":4},'
    + '{"name":"n5","value":5},{"name":"n6","value":6}],'
    + '"links":[{"source":0,"target":1},{"source":1,"target":2},'
    + '{"source":2,"target":3},{"source":3,"target":4},'
    + '{"source":4,"target":5},{"source":5,"target":0},'
    + '{"source":0,"target":3}]}]}';

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-graph-force.json';
end;

{ The store the control builds for a graph: one value column, and everything
  else a node wrote as an override under its own name. }
function GraphStoreOf(AOption: TTyChartOption): TTyDataStore;
begin
  Result := TTyDataStore.Create;
  TyGraphFillStore(AOption, 0, Result);
end;

function Near(AExpected, AActual, ARel: Double): Boolean;
begin
  if IsNan(AActual) or IsInfinite(AActual) then Exit(False);
  Result := Abs(AExpected - AActual) <= ARel * Max(Double(1), Abs(AExpected));
end;

{ ==================== the oracle ==================== }

procedure TAdvChartGraphOracleTest.TestEveryCaseLandsWhereUpstreamLaidItOut;
const
  { DATA SPACE IS COMPARED EXACTLY -- the same operations in the same order
    are the same Doubles, and a case the fixture marks exact is held to that:
    turning `/ d / d` into `/ (d * d)` moves nothing by a billionth and still
    has to fail. A case with a ring in it gets a billionth, because cosine and
    sine are not correctly rounded in either runtime. PIXELS are held to the
    same rule. [Revised in batch 45: pixels had a millionth, because this port
    carried a point through a scale and a translate where upstream carries it
    through a matrix; the view now uses the matrix.] }
  cDataTol = 1e-9;
var
  sl: TStringList;
  root: TJSONData;
  cases, phases, arr, want: TJSONArray;
  cs, ph: TJSONObject;
  c, p, i, compared, bad: Integer;
  opt: TTyChartOption;
  st: TTyDataStore;
  state: TTyGraphForceState;
  solved: TTyGraphSolved;
  w, h: Double;
  r: TTyRectF;
  report: string;
  dataTol: Double;

  procedure Miss(const AWhat: string);
  begin
    Inc(bad);
    if bad <= 12 then
      report := report + LineEnding + '  ' + cs.Strings['name'] + ' @'
        + FloatToStr(w) + 'x' + FloatToStr(h) + ': ' + AWhat;
  end;

  procedure Pair(const AWhat: string; AWantX, AWantY, AGotX, AGotY,
    ATol: Double);
  begin
    Inc(compared);
    if not (Near(AWantX, AGotX, ATol) and Near(AWantY, AGotY, ATol)) then
      Miss(Format('%s wants (%.12g, %.12g) got (%.12g, %.12g)',
        [AWhat, AWantX, AWantY, AGotX, AGotY]));
  end;

begin
  AssertTrue('the fixture is where the suite expects it: ' + FixturePath,
    FileExists(FixturePath));
  sl := TStringList.Create;
  root := nil;
  try
    sl.LoadFromFile(FixturePath);
    root := GetJSON(sl.Text);
    cases := TJSONObject(root).Arrays['cases'];
    { A FIXTURE OF NOTHING IS A PASS OF NOTHING. }
    AssertTrue('the fixture carries its cases', cases.Count >= 100);
    compared := 0;
    bad := 0;
    report := '';
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      opt := TTyChartOption.Create;
      st := nil;
      try
        AssertTrue(cs.Strings['name'] + ' parses',
          opt.SetOptionText(cs.Objects['option'].AsJSON));
        st := GraphStoreOf(opt);
        { ONE STATE ACROSS THE PHASES, which is the whole point of the second
          one: upstream re-lays a resized chart out from where the last pass
          left it, not from a new random start. }
        state := Default(TTyGraphForceState);
        if cs.Booleans['exact'] then dataTol := 0 else dataTol := cDataTol;
        phases := cs.Arrays['phases'];
        for p := 0 to phases.Count - 1 do
        begin
          ph := phases.Objects[p];
          w := ph.Floats['width'];
          h := ph.Floats['height'];
          solved := TyGraphSolve(opt, 0, st, TyRectF(0, 0, w, h), state);
          try
            arr := ph.Arrays['dataRect'];
            r := solved.View.GetDataRect;
            Pair('the data rect origin', arr.Items[0].AsFloat,
              arr.Items[1].AsFloat, r.Left, r.Top, dataTol);
            Pair('the data rect size', arr.Items[2].AsFloat,
              arr.Items[3].AsFloat, r.Right - r.Left, r.Bottom - r.Top,
              dataTol);

            arr := ph.Arrays['nodes'];
            if arr.Count <> Length(solved.Nodes) then
              Miss(Format('%d nodes, not %d',
                [Length(solved.Nodes), arr.Count]))
            else
              for i := 0 to arr.Count - 1 do
                if arr.Items[i].JSONType = jtNull then
                begin
                  Inc(compared);
                  if not IsNan(solved.Nodes[i].PX) then
                    Miss(Format('node %d is nowhere upstream, here at '
                      + '(%.6g, %.6g)', [i, solved.Nodes[i].PX,
                      solved.Nodes[i].PY]));
                end
                else
                begin
                  want := TJSONArray(arr.Items[i]);
                  Pair('node ' + IntToStr(i) + ' in data space',
                    want.Items[0].AsFloat, want.Items[1].AsFloat,
                    solved.Nodes[i].X, solved.Nodes[i].Y, dataTol);
                  Pair('node ' + IntToStr(i) + ' in pixels',
                    want.Items[2].AsFloat, want.Items[3].AsFloat,
                    solved.Nodes[i].PX, solved.Nodes[i].PY, dataTol);
                end;

            arr := ph.Arrays['edges'];
            if arr.Count <> Length(solved.Edges) then
              Miss(Format('%d edges, not %d',
                [Length(solved.Edges), arr.Count]))
            else
              for i := 0 to arr.Count - 1 do
                if arr.Items[i].JSONType = jtNull then
                begin
                  Inc(compared);
                  if solved.Edges[i].Curved then
                    Miss(Format('edge %d is straight upstream, curved here',
                      [i]));
                end
                else
                begin
                  want := TJSONArray(arr.Items[i]);
                  if not solved.Edges[i].Curved then
                    Miss(Format('edge %d is curved upstream (%.6g), straight '
                      + 'here (%.6g)', [i, want.Items[2].AsFloat,
                      solved.Edges[i].SolvedCurveness]))
                  else
                    Pair('edge ' + IntToStr(i) + ' control point',
                      want.Items[2].AsFloat, want.Items[3].AsFloat,
                      solved.Edges[i].CPX, solved.Edges[i].CPY, dataTol);
                end;
          finally
            solved.View.Free;
          end;
        end;
      finally
        st.Free;
        opt.Free;
      end;
    end;
    AssertTrue('and a great deal of it was compared (' + IntToStr(compared)
      + ')', compared > 1600);
    AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
      + ' disagree with upstream:' + report, 0, bad);
  finally
    root.Free;
    sl.Free;
  end;
end;

{ ==================== the rules ==================== }

procedure TAdvChartGraphForceTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartGraphForceTest.SpecOf(const ABody: string): TTyGraphSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the option parses', FOpt.SetOptionText(
    '{"series":[{"type":"graph"' + ABody + '}]}'));
  Result := TyGraphSpecOf(FOpt, 0);
end;

procedure TAdvChartGraphForceTest.TestTheRandomNumbersAreTheOnesUpstreamIsGiven;
var s: LongWord; v: Double;
begin
  { THE SAME SEQUENCE THE ORACLE HANDS UPSTREAM, checked value by value -- the
    state and the Double both, because a division done in Single precision
    agrees with the state and not with the number. }
  s := TyGraphForceSeed(0);
  AssertEquals('series zero''s seed', Int64(2463534242), Int64(s));
  v := TyGraphRandom(s);
  AssertEquals(Int64(723471715), Int64(s));
  AssertEquals(0.16844638506881893, v, 0);
  v := TyGraphRandom(s);
  AssertEquals(Int64(2497366906), Int64(s));
  AssertEquals(0.58146354416385293, v, 0);
  v := TyGraphRandom(s);
  AssertEquals(Int64(2064144800), Int64(s));
  AssertEquals(0.48059616237878799, v, 0);
  { EACH SERIES ITS OWN START, or two force graphs on one chart would be laid
    out as mirror images of each other's random start. }
  AssertEquals('series one starts elsewhere', Int64(823002715),
    Int64(TyGraphForceSeed(1)));
end;

procedure TAdvChartGraphForceTest.TestTheStepCountIsUpstreamsAndNeverUnderTwo;
begin
  { 0.6 x 0.992^k first drops under a hundredth at k = 510; a drag's warm-up
    restarts at 0.48, which takes 482. }
  AssertEquals('from the default', 510, TyGraphForceSteps(0.6));
  AssertEquals('from a warm-up', 482, TyGraphForceSteps(0.48));
  { TWO AT LEAST: the layout stage takes a step and the view takes another
    before it ever looks at the answer -- so a friction that is already cold,
    or nothing at all, or backwards, still runs two. }
  AssertEquals('no friction', 2, TyGraphForceSteps(0));
  AssertEquals('already cold', 2, TyGraphForceSteps(0.01));
  AssertEquals('backwards', 2, TyGraphForceSteps(-0.6));
  AssertEquals('one step from cold', 3, TyGraphForceSteps(0.0101 / 0.992));
  { AND A CEILING, because upstream has none: an infinite friction never
    cools, and a vast one takes longer than anybody waits. }
  AssertEquals('an infinite friction hits the ceiling', 2000,
    TyGraphForceSteps(Infinity));
  AssertEquals('so does a vast one', 2000, TyGraphForceSteps(1e300));
  AssertEquals('and so does not-a-number', 2000, TyGraphForceSteps(NaN));
end;

procedure TAdvChartGraphForceTest.TestLinearMapHasAMiddleAndTwoExactEnds;
begin
  { A FLAT DOMAIN IS THE MIDDLE OF THE RANGE -- so the default repulsion of
    [0, 50] over nodes that all carry one value is twenty-five, neither end. }
  AssertEquals(25.0, TyGraphLinearMap(5, 3, 3, 0, 50), 0);
  AssertEquals('and a flat range is its one value', 7.0,
    TyGraphLinearMap(5, 3, 3, 7, 7), 0);
  { THE ENDS ARE EXACT. Through the division these come out a unit or seven
    in the last place off; upstream returns the end itself. }
  AssertEquals(0.9, TyGraphLinearMap(0.7, 0.1, 0.7, 0.3, 0.9), 0);
  AssertEquals(0.3, TyGraphLinearMap(7, 1, 7, 10, 0.3), 0);
  AssertEquals('the near end too', 10.0, TyGraphLinearMap(1, 1, 7, 10, 0.3), 0);
  AssertEquals('and the middle is the formula', 0.6,
    TyGraphLinearMap(2, 1, 3, 0.3, 0.9), 1e-15);
  { AN EXTENT OF NO VALUES AT ALL is [+inf, -inf], and it maps everything to
    not-a-number -- which the callers then send to the middle. }
  AssertTrue(IsNan(TyGraphLinearMap(4, Infinity, NegInfinity, 0, 50)));
  AssertTrue('and so does a value that is not one',
    IsNan(TyGraphLinearMap(NaN, 1, 3, 0, 50)));
end;

procedure TAdvChartGraphForceTest.TestForceReadsItsRangesTheWayUpstreamDoes;
var s: TTyGraphSpec;
begin
  s := SpecOf('');
  { THE DEFAULTS: a repulsion RANGE and a length that is one number at both
    ends. }
  AssertEquals(0.0, s.Force.RepulsionLo, 0);
  AssertEquals(50.0, s.Force.RepulsionHi, 0);
  AssertEquals(30.0, s.Force.EdgeLengthLo, 0);
  AssertEquals(30.0, s.Force.EdgeLengthHi, 0);
  AssertEquals(0.1, s.Force.Gravity, 0);
  AssertEquals(0.6, s.Force.Friction, 0);
  { A SCALAR IS BOTH ENDS. }
  s := SpecOf(',"force":{"repulsion":7,"edgeLength":12}');
  AssertEquals(7.0, s.Force.RepulsionLo, 0);
  AssertEquals(7.0, s.Force.RepulsionHi, 0);
  AssertEquals(12.0, s.Force.EdgeLengthLo, 0);
  AssertEquals(12.0, s.Force.EdgeLengthHi, 0);
  { AN ARRAY IS TAKEN AS IT IS, and a missing end is not a copy of the other:
    `[30]` makes every length not-a-number. }
  s := SpecOf(',"force":{"edgeLength":[30],"repulsion":[4,9,99]}');
  AssertEquals(30.0, s.Force.EdgeLengthLo, 0);
  AssertTrue('the second end is undefined', IsNan(s.Force.EdgeLengthHi));
  AssertEquals(4.0, s.Force.RepulsionLo, 0);
  AssertEquals('a third entry is ignored', 9.0, s.Force.RepulsionHi, 0);
  { A WRITTEN NULL IS A ZERO in arithmetic -- except for gravity and friction,
    whose solver asks `== null` first and puts the default back. }
  s := SpecOf(',"force":{"repulsion":null,"gravity":null,"friction":null}');
  AssertEquals(0.0, s.Force.RepulsionLo, 0);
  AssertEquals(0.0, s.Force.RepulsionHi, 0);
  AssertEquals('a null gravity is the default', 0.1, s.Force.Gravity, 0);
  AssertEquals('and a null friction', 0.6, s.Force.Friction, 0);
  s := SpecOf(',"force":{"gravity":0,"friction":0.25}');
  AssertEquals('a written zero is a zero', 0.0, s.Force.Gravity, 0);
  AssertEquals(0.25, s.Force.Friction, 0);
end;

procedure TAdvChartGraphForceTest.TestInitLayoutKnowsTwoWordsAndEverythingElseIsNothing;
begin
  AssertEquals('absent', Ord(gilNone), Ord(SpecOf('').Force.InitLayout));
  AssertEquals('none', Ord(gilNone),
    Ord(SpecOf(',"force":{"initLayout":"none"}').Force.InitLayout));
  AssertEquals('falsy', Ord(gilNone),
    Ord(SpecOf(',"force":{"initLayout":false}').Force.InitLayout));
  AssertEquals('null', Ord(gilNone),
    Ord(SpecOf(',"force":{"initLayout":null}').Force.InitLayout));
  AssertEquals('circular', Ord(gilCircular),
    Ord(SpecOf(',"force":{"initLayout":"circular"}').Force.InitLayout));
  { ANY OTHER WORD falls through both tests -- and so does a truthy value that
    is not a word at all. }
  AssertEquals('a word nobody knows', Ord(gilOther),
    Ord(SpecOf(',"force":{"initLayout":"grid"}').Force.InitLayout));
  AssertEquals('the right word in the wrong case', Ord(gilOther),
    Ord(SpecOf(',"force":{"initLayout":"Circular"}').Force.InitLayout));
  AssertEquals('a number', Ord(gilOther),
    Ord(SpecOf(',"force":{"initLayout":1}').Force.InitLayout));
end;

procedure TAdvChartGraphForceTest.TestFixedClimbsFromTheNodeToItsCategoryToTheSeries;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  cats: TTyGraphCategoryArray;
  s: TTyGraphSpec;
  i: Integer;
begin
  s := TyGraphSpecDefault;
  SetLength(cats, 2);
  cats[0] := Default(TTyGraphCategory);
  cats[1] := Default(TTyGraphCategory);
  cats[0].HasFixed := True;
  cats[0].Fixed := True;
  SetLength(nodes, 4);
  for i := 0 to 3 do
  begin
    nodes[i] := Default(TTyGraphNode);
    nodes[i].ModelCategory := -1;
  end;
  { own true; own FALSE under a pinning category; the category's; none. }
  nodes[0].HasOwnFixed := True;
  nodes[0].OwnFixed := True;
  nodes[1].HasOwnFixed := True;
  nodes[1].OwnFixed := False;
  nodes[1].ModelCategory := 0;
  nodes[2].ModelCategory := 0;
  nodes[3].ModelCategory := 1;
  SetLength(edges, 2);
  edges[0] := Default(TTyGraphEdge);
  edges[1] := Default(TTyGraphEdge);
  edges[1].HasOwnIgnore := True;
  edges[1].IgnoreForce := False;

  TyGraphResolvePins(nodes, edges, cats, s);
  AssertTrue('its own', nodes[0].Pinned);
  AssertFalse('a written false stops the climb', nodes[1].Pinned);
  AssertTrue('the category''s', nodes[2].Pinned);
  AssertFalse('a category that said nothing, and a series that said nothing',
    nodes[3].Pinned);

  { THE SERIES IS THE LAST PARENT, for nodes and for edges alike. }
  s.HasFixed := True;
  s.Fixed := True;
  s.HasIgnoreForce := True;
  s.IgnoreForce := True;
  TyGraphResolvePins(nodes, edges, cats, s);
  AssertTrue('now the series holds it', nodes[3].Pinned);
  AssertFalse('but not over a node''s own false', nodes[1].Pinned);
  AssertTrue('an edge that said nothing takes the series''', edges[0].IgnoreForce);
  AssertFalse('and one that said false keeps it', edges[1].IgnoreForce);
end;

procedure TAdvChartGraphForceTest.TestACategoryNamedRatherThanIndexedIsNoParent;
var st: TTyDataStore; cats: TTyGraphCategoryArray; nodes: TTyGraphNodeArray;
begin
  { COLOUR RESOLVES A NAMED CATEGORY; THE OPTION CHAIN DOES NOT. Upstream
    indexes its category models with whatever the node wrote, and an array
    indexed by a name finds nothing -- so the node is coloured by the category
    and not pinned by it. }
  SpecOf(',"categories":[{"name":"held","fixed":true}],'
    + '"data":[{"name":"a","category":"held"},{"name":"b","category":0}]');
  cats := TyGraphCategoriesOf(FOpt, 0);
  AssertTrue('the category says fixed', cats[0].HasFixed and cats[0].Fixed);
  st := GraphStoreOf(FOpt);
  try
    nodes := TyGraphNodesOf(st, cats);
    AssertEquals('the name finds the category for colour', 0, nodes[0].Category);
    AssertEquals('but not as a parent', -1, nodes[0].ModelCategory);
    AssertEquals('the index finds both', 0, nodes[1].ModelCategory);
  finally
    st.Free;
  end;
end;

procedure TAdvChartGraphForceTest.TestAPassThatChangesNothingRunsNoSteps;
var
  st: TTyDataStore;
  state: TTyGraphForceState;
  a, b, c: TTyGraphSolved;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue(FOpt.SetOptionText(cSix));
  st := GraphStoreOf(FOpt);
  try
    state := Default(TTyGraphForceState);
    a := TyGraphSolve(FOpt, 0, st, TyRectF(0, 0, 600, 400), state);
    a.View.Free;
    AssertTrue('the pass left its answer', state.Valid);
    AssertEquals(6, Length(state.X));
    { DOCTOR THE ANSWER, and ask again over the same rectangle. A pass that ran
      the solver would move node zero off the doctored point; a pass that
      reuses the answer hands it straight back. }
    state.X[0] := 123.5;
    state.Y[0] := 45.25;
    b := TyGraphSolve(FOpt, 0, st, TyRectF(0, 0, 600, 400), state);
    try
      AssertEquals('the same rectangle is the same answer', 123.5,
        b.Nodes[0].X, 0);
      AssertEquals(45.25, b.Nodes[0].Y, 0);
    finally
      b.View.Free;
    end;
    { A NEW RECTANGLE RUNS AGAIN -- from the doctored point, not from nothing:
      the start is the last answer, not the random box. }
    c := TyGraphSolve(FOpt, 0, st, TyRectF(0, 0, 500, 300), state);
    try
      AssertTrue('the solver ran', Abs(c.Nodes[0].X - 123.5) > 1e-6);
      AssertEquals('and left a new answer for the new box', 500.0,
        state.Rect.Right, 0);
    finally
      c.View.Free;
    end;
  finally
    st.Free;
  end;
end;

procedure TAdvChartGraphForceTest.TestAViewWithNoAspectIsFourFifthsOfTheHeight;
var r: TTyRectF; s: TTyGraphSpec;
begin
  { NO POSITIONS, NO ASPECT, and the aspect branch still runs: `NaN > x` is
    false, so the HEIGHT takes four fifths, the width comes out not-a-number
    and is filled in from the container at the end, and the centring on the
    width is laundered to zero on the way. Full width, four fifths high,
    centred vertically. }
  s := SpecOf('');
  r := TyGraphViewRect(s, TyRectF(0, 0, 600, 400), NaN);
  AssertEquals(0.0, r.Left, 1e-9);
  AssertEquals(40.0, r.Top, 1e-9);
  AssertEquals(600.0, r.Right, 1e-9);
  AssertEquals(360.0, r.Bottom, 1e-9);
  { AND A REAL ASPECT WIDER THAN THE CONTAINER takes four fifths of the WIDTH
    instead, the height following, the whole thing centred both ways. }
  r := TyGraphViewRect(s, TyRectF(0, 0, 600, 400), 2);
  AssertEquals(60.0, r.Left, 1e-9);
  AssertEquals(540.0, r.Right, 1e-9);
  AssertEquals(80.0, r.Top, 1e-9);
  AssertEquals(320.0, r.Bottom, 1e-9);
end;

procedure TAdvChartGraphForceTest.TestTheAlignmentIsTheWordNotThePosition;
var r: TTyRectF;
begin
  { `left: 'center'` WRITTEN OUT is the same as the default: a position of
    half the container, then a centring that overwrites it. Read as a
    position alone it would put the box's LEFT EDGE in the middle. }
  r := TyGraphViewRect(SpecOf(',"left":"center","width":100,"height":50'),
    TyRectF(0, 0, 500, 400), NaN);
  AssertEquals('centred, not starting at the middle', 200.0, r.Left, 1e-9);
  { `right` as the word aligns to the right edge -- as a position it is the
    whole width, and the box would start off the canvas. }
  r := TyGraphViewRect(SpecOf(',"left":"right","width":100,"height":50'),
    TyRectF(0, 0, 500, 400), NaN);
  AssertEquals('flush right', 400.0, r.Left, 1e-9);
  { `50%` is the same position as `center` and NOT the same word -- no
    alignment follows, so the box starts in the middle. }
  r := TyGraphViewRect(SpecOf(',"left":"50%","width":100,"height":50'),
    TyRectF(0, 0, 500, 400), NaN);
  AssertEquals('a percentage is only a position', 250.0, r.Left, 1e-9);
  { AND THE SAME ON THE OTHER AXIS, with `bottom` as the word. }
  r := TyGraphViewRect(SpecOf(',"top":"bottom","width":100,"height":50'),
    TyRectF(0, 0, 500, 400), NaN);
  AssertEquals('flush to the bottom', 350.0, r.Top, 1e-9);
  { A FALSY NEAR SIDE HANDS THE WORD TO THE FAR ONE: `left: 0` is no word, so
    `right: 'center'` is read -- and centres. }
  r := TyGraphViewRect(SpecOf(',"left":0,"right":"center","width":100,'
    + '"height":50'), TyRectF(0, 0, 500, 400), NaN);
  AssertEquals('the far side''s word', 200.0, r.Left, 1e-9);
end;

procedure TAdvChartGraphForceTest.TestNoLegalForceOptionRaisesOrLeavesTheTrapsOff;
const
  cBodies: array[0..14] of string = (
    ',"force":{"friction":1e308}',
    ',"force":{"friction":-5}',
    ',"force":{"gravity":1e308}',
    ',"force":{"gravity":-1e308,"friction":50}',
    ',"force":{"repulsion":[1e308,-1e308]}',
    ',"force":{"edgeLength":1e308}',
    ',"force":{"edgeLength":[],"repulsion":"a"}',
    ',"force":{"initLayout":"circular"},"_values":1e308',
    ',"lineStyle":{"curveness":1e308}',
    ',"autoCurveness":1e308',
    ',"force":{"repulsion":1e308,"friction":0.9}',
    ',"_positions":1',
    ',"fixed":true',
    ',"categories":[{"fixed":true}],"force":{"initLayout":"other"}',
    ',"_sizes":1');
var
  i, k: Integer;
  body, data: string;
  st: TTyDataStore;
  state: TTyGraphForceState;
  solved: TTyGraphSolved;
  before: TFPUExceptionMask;
  list: TTyPaintList;
  ink: TTyGraphInk;
begin
  before := GetExceptionMask;
  for i := 0 to High(cBodies) do
  begin
    body := cBodies[i];
    { Two of the cases are about the DATA rather than the series, and say so
      with a marker the option never sees. }
    if Pos('"_values"', body) > 0 then
    begin
      body := StringReplace(body, ',"_values":1e308', '', []);
      data := '[{"name":"a","value":1e308},{"name":"b","value":1e308},'
        + '{"name":"c","value":1e308}]';
    end
    else if Pos('"_positions"', body) > 0 then
    begin
      body := '';
      data := '[{"name":"a","x":-1e308,"y":1e308},{"name":"b","x":1e308,'
        + '"y":-1e308},{"name":"c","x":0,"y":0,"symbolSize":1e308}]';
    end
    else if Pos('"_sizes"', body) > 0 then
    begin
      { SIZES NOBODY CAN DRAW, ON NODES THAT ARE DRAWN: pinned where they were
        written, so the case really reaches the paint path -- the positions
        case above cannot, because its nodes are not a box anybody can fit.
        Arrows at both ends and a curve, so the trim squares a radius. }
      body := ',"fixed":true,"symbolSize":1e308,"edgeSymbol":["arrow","arrow"],'
        + '"edgeSymbolSize":[1e308,1e40],"lineStyle":{"curveness":0.3}';
      data := '[{"name":"a","x":0,"y":0},{"name":"b","x":100,"y":50,'
        + '"symbolSize":1e308},{"name":"c","x":30,"y":80,"symbolSize":-1e308}]';
    end
    else
      data := '[{"name":"a","value":1},{"name":"b","value":2},'
        + '{"name":"c","value":3,"category":0}]';
    SpecOf(',"layout":"force"' + body + ',"data":' + data
      + ',"links":[{"source":0,"target":1},{"source":0,"target":1},'
      + '{"source":1,"target":2},{"source":2,"target":0}]');
    st := GraphStoreOf(FOpt);
    list := TTyPaintList.Create;
    try
      state := Default(TTyGraphForceState);
      solved := TyGraphSolve(FOpt, 0, st, TyRectF(0, 0, 400, 300), state);
      try
        { NOTHING THAT LEAVES THE PASS IS UNDRAWABLE: a node is a point a
          canvas can take or it is nowhere, and so is a control point. }
        for k := 0 to High(solved.Nodes) do
          AssertTrue(cBodies[i] + ': node ' + IntToStr(k) + ' is drawable or gone',
            IsNan(solved.Nodes[k].PX)
            or ((Abs(solved.Nodes[k].PX) <= cTyGraphFarPx)
                and (Abs(solved.Nodes[k].PY) <= cTyGraphFarPx)));
        for k := 0 to High(solved.Edges) do
          if solved.Edges[k].Curved then
            AssertTrue(cBodies[i] + ': control point ' + IntToStr(k),
              (Abs(solved.Edges[k].CPX) <= cTyGraphFarPx)
              and (Abs(solved.Edges[k].CPY) <= cTyGraphFarPx));
        { AND THE PAINT PATH, which runs with the traps ON, takes it. }
        ink := Default(TTyGraphInk);
        ink.EdgeColour := TTyChartColor($FF808080);
        SetLength(ink.NodeFills, Length(solved.Nodes));
        TyBuildGraphMarks(0, solved.Spec, solved.Nodes,
          solved.Edges, ink, st, list);
        if Pos('"_sizes"', cBodies[i]) > 0 then
          AssertTrue('the sizes case really drew something', list.Count > 0);
      finally
        solved.View.Free;
      end;
    finally
      list.Free;
      st.Free;
    end;
    AssertTrue(cBodies[i] + ': the traps are back as they were',
      GetExceptionMask = before);
  end;
end;

procedure TAdvChartGraphForceTest.TestAControlPointNobodyCanDrawTakesItsEdgeWithIt;
var
  view: TTyGraphView;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  ink: TTyGraphInk;
  list: TTyPaintList;
  s: TTyGraphSpec;
  i: Integer;
begin
  { AN INFINITE CURVENESS IS NOT FALSY, so upstream makes a control point of
    it -- infinite -- and the canvas refuses the segment: the edge is simply
    not there. Drawn straight instead, it would be a line upstream never
    shows. And a FINITE curveness that throws the point ten million pixels
    out is treated the same way, because everything downstream squares
    distances. }
  s := TyGraphSpecDefault;
  SetLength(nodes, 3);
  nodes[0] := Default(TTyGraphNode);
  nodes[1] := Default(TTyGraphNode);
  nodes[1].X := 100;
  nodes[1].Y := 50;
  nodes[1].PX := 100;
  nodes[1].PY := 50;
  nodes[2] := Default(TTyGraphNode);
  nodes[2].X := 100;
  nodes[2].PX := 100;
  SetLength(edges, 3);
  for i := 0 to 2 do
  begin
    edges[i] := Default(TTyGraphEdge);
    edges[i].Target := 1;
  end;
  edges[0].SolvedCurveness := Infinity;
  edges[1].SolvedCurveness := 1e5;
  edges[2].SolvedCurveness := 0.5;
  ink := Default(TTyGraphInk);
  ink.EdgeColour := TTyChartColor($FF808080);
  SetLength(ink.NodeFills, 3);
  view := TTyGraphView.Create(TyRectF(0, 0, 100, 100), TyRectF(0, 0, 100, 100));
  list := TTyPaintList.Create;
  try
    TyGraphEdgeGeometry(edges, nodes, view, False);
    AssertTrue('an infinite curveness hides its edge', edges[0].Hidden);
    AssertFalse('rather than drawing it straight', edges[0].Curved);
    AssertTrue('and so does one a thousand screens out', edges[1].Hidden);
    AssertTrue('an ordinary one curves', edges[2].Curved and not edges[2].Hidden);
    AssertEquals('at the perpendicular', 75.0, edges[2].CPX, 1e-9);
    AssertEquals(-25.0, edges[2].CPY, 1e-9);
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    { ONE EDGE AND THREE NODES: the two hidden edges put nothing in the list. }
    AssertEquals(4, list.Count);

    { [Revised in batch 31: the rule above holds only while the point is a
      NUMBER.] A LEVEL EDGE bowed by an infinite curveness gets
      `50 - 0 * Infinity` for its x -- not-a-number -- and upstream's
      isStraightLine asks exactly that: it draws the edge STRAIGHT. Unless
      an end carries a symbol, when adjustEdge cuts the curve at the node's
      rim and the arithmetic turns both ends into not-a-number. }
    SetLength(edges, 1);
    edges[0] := Default(TTyGraphEdge);
    edges[0].Target := 2;
    edges[0].SolvedCurveness := Infinity;
    TyGraphEdgeGeometry(edges, nodes, view, False);
    AssertFalse('a level edge is not hidden', edges[0].Hidden);
    AssertFalse('it is not curved', edges[0].Curved);
    AssertTrue('it is a broken curve', edges[0].NaNCurve);
    list.Clear;
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('drawn straight, beside three nodes', 4, list.Count);
    s.EdgeSymbolTo := 'arrow';
    list.Clear;
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('and with an arrow, not at all', 3, list.Count);
    s.EdgeSymbolTo := 'none';
    s.EdgeSymbolFrom := 'arrow';
    list.Clear;
    TyBuildGraphMarks(0, s, nodes, edges, ink, nil, list);
    AssertEquals('whichever end carries it', 3, list.Count);
  finally
    list.Free;
    view.Free;
  end;
end;

procedure TAdvChartGraphForceTest.TestTheHostsNextTrapIsReportedForWhatItIs;
var
  st: TTyDataStore;
  state: TTyGraphForceState;
  solved: TTyGraphSolved;
  z, r: Double;
begin
  { A PASS THAT OVERFLOWS AND MAKES NOT-A-NUMBERS ON PURPOSE, with the traps
    off, and then the host's own division by zero. The masked arithmetic sets
    the sticky SSE flags; left standing, the invalid-operation one makes the
    host's next trap -- anywhere, later, in code that has nothing to do with a
    chart -- come out as an invalid operation instead of what it is. }
  SpecOf(',"layout":"force","force":{"friction":1e308,"gravity":1e308},'
    + '"data":[{"name":"a"},{"name":"b"}],"links":[{"source":0,"target":1}]');
  st := GraphStoreOf(FOpt);
  try
    state := Default(TTyGraphForceState);
    solved := TyGraphSolve(FOpt, 0, st, TyRectF(0, 0, 400, 300), state);
    solved.View.Free;
  finally
    st.Free;
  end;
  {$IFDEF CPUX86_64}
  AssertEquals('no invalid-operation flag left standing', 0,
    Integer(GetMXCSR and 1));
  {$ENDIF}
  z := 0;
  try
    r := 1 / z;
    Fail('a division by zero did not trap at all: ' + FloatToStr(r));
  except
    on E: EZeroDivide do ;
    on E: Exception do
      Fail('the host''s division by zero was reported as ' + E.ClassName);
  end;
end;

{ ==================== the control ==================== }

procedure TAdvChartGraphForceDrawTest.SetUp;
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

procedure TAdvChartGraphForceDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphForceDrawTest.Draw(AW, AH: Integer);
begin
  FreeAndNil(FBmp);
  { SENTINEL, not white -- the light theme's surface is white. }
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), 96);
end;

{ Is there a NODE at this point -- a saturated, darker-than-the-surface blue
  of the theme's ramp, not the white surface and not the faint grey of an
  edge running under it? }
function TAdvChartGraphForceDrawTest.InkAt(AX, AY: Double): Boolean;
var p: TBGRAPixel;
begin
  p := FBmp.GetPixel(Round(AX), Round(AY));
  Result := (p.blue > p.red + 40) and (p.red < 200);
end;

procedure TAdvChartGraphForceDrawTest.TestAForceGraphDrawsWhereTheLayoutPutIt;
var
  opt: TTyChartOption;
  st: TTyDataStore;
  state: TTyGraphForceState;
  want: TTyGraphSolved;
  i: Integer;
begin
  { WHAT THE CONTROL DRAWS IS WHAT THE PASS COMPUTES, node for node. Without
    the force layout wired in, not one of these nodes has a position -- none
    was written -- and the chart would draw nothing at all. }
  opt := TTyChartOption.Create;
  st := nil;
  try
    AssertTrue(opt.SetOptionText(cSix));
    st := GraphStoreOf(opt);
    state := Default(TTyGraphForceState);
    want := TyGraphSolve(opt, 0, st, TyRectF(0, 0, 600, 400), state);
    FChart.Option := cSix;
    Draw(600, 400);
    for i := 0 to High(want.Nodes) do
    begin
      AssertFalse('node ' + IntToStr(i) + ' was placed', IsNan(want.Nodes[i].PX));
      AssertTrue('and drawn there: node ' + IntToStr(i),
        InkAt(want.Nodes[i].PX, want.Nodes[i].PY));
    end;
    want.View.Free;
  finally
    st.Free;
    opt.Free;
  end;
end;

procedure TAdvChartGraphForceDrawTest.TestAResizeContinuesAndANewOptionStartsAgain;
var
  opt: TTyChartOption;
  st: TTyDataStore;
  carried, fresh: TTyGraphForceState;
  a, b, f: TTyGraphSolved;
  i, apart: Integer;
begin
  { TWO WAYS TO ARRIVE AT 500 x 300, and they are different pictures. Laid out
    at 600 x 400 and then resized, the graph CONTINUES from where it stood;
    laid out at 500 x 300 from a new option, it starts from the random box
    again. The control keeps the first across a resize and drops it when the
    option changes. }
  opt := TTyChartOption.Create;
  st := nil;
  try
    AssertTrue(opt.SetOptionText(cSix));
    st := GraphStoreOf(opt);
    carried := Default(TTyGraphForceState);
    a := TyGraphSolve(opt, 0, st, TyRectF(0, 0, 600, 400), carried);
    a.View.Free;
    b := TyGraphSolve(opt, 0, st, TyRectF(0, 0, 500, 300), carried);
    fresh := Default(TTyGraphForceState);
    f := TyGraphSolve(opt, 0, st, TyRectF(0, 0, 500, 300), fresh);
    try
      { THE FIXTURE CAN TELL THEM APART: some node sits well away from where
        it would have started afresh. }
      apart := 0;
      for i := 0 to High(b.Nodes) do
        if Sqrt(Sqr(b.Nodes[i].PX - f.Nodes[i].PX)
          + Sqr(b.Nodes[i].PY - f.Nodes[i].PY)) > 12 then Inc(apart);
      AssertTrue('the two pictures differ', apart > 0);

      FChart.Option := cSix;
      Draw(600, 400);
      Draw(500, 300);
      for i := 0 to High(b.Nodes) do
        AssertTrue('a resize continues: node ' + IntToStr(i),
          InkAt(b.Nodes[i].PX, b.Nodes[i].PY));

      { A CHANGED OPTION IS A NEW START, even when the text changes by nothing
        but a space -- it is a new option, and upstream's replaced series
        models keep no points. }
      FChart.Option := cSix + ' ';
      Draw(500, 300);
      for i := 0 to High(f.Nodes) do
        AssertTrue('a new option starts again: node ' + IntToStr(i),
          InkAt(f.Nodes[i].PX, f.Nodes[i].PY));
    finally
      b.View.Free;
      f.View.Free;
    end;
  finally
    st.Free;
    opt.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartGraphOracleTest);
  RegisterTest(TAdvChartGraphForceTest);
  RegisterTest(TAdvChartGraphForceDrawTest);
end.
