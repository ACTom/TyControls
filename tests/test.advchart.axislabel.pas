unit test.advchart.axislabel;
{$mode objfpc}{$H+}
{ Which labels an axis draws, and which point of each sits on its anchor.

  A label is placed by two decisions and they are not the same decision. WHERE
  the anchor is belongs to the side -- under the plot for a bottom axis, left
  of it for a left one. WHICH POINT OF THE TEXT goes there is a separate
  question, and the answer depends on the ROTATION as much as on the side.

  The port used to answer the second question from the side alone, and for an
  unturned label that is right. Turn one 45 degrees and it becomes wrong in a
  way that is hard to see and easy to dismiss: anchored by its centre and then
  turned, a label STRADDLES its anchor, so half the string swings up across the
  axis line and into the plot -- where the series paints over it. The labels
  come out looking truncated. Draw the same axis with no series and they are
  whole.

  So there are two kinds of test here. The first asks what the anchors ARE,
  against upstream's one rule. The second asks the question that would actually
  have caught it: does a label's ink depend on whether there is a series? }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Coord,
     tyControls.AdvanceChart,
     test.advancechart;
type
  { Fixed metrics, because the anchors are the subject and the local font is
    not. }
  TAnchorMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartAxisLabelTest = class(TTestCase)
  private
    FM: ITyTextMeasurer;
    procedure SetUp; override;
    function Spec(ASide: TTyAxisSide; ARotateDeg: Double;
      AInside: Boolean = False): TTyAxisLayoutSpec;
    { The first placement's anchors, as a two-letter code -- `CT`, `RM`, ... }
    function AnchorsOf(ASide: TTyAxisSide; ARotateDeg: Double;
      AInside: Boolean = False): string;
    function Crowded(AStride: Integer): TTyAxisLayoutSpec;
    function ShownIndices(const ASpec: TTyAxisLayoutSpec): string;
  published
    procedure TestUnturnedLabelsKeepTheAnchorsTheyAlwaysHad;
    procedure TestInsideFlipsEveryOneOfThem;
    procedure TestATurnedLabelHangsByItsEndNotItsMiddle;
    procedure TestTurningTheOtherWayHangsTheOtherWay;
    procedure TestAQuarterTurnOnAVerticalAxisReadsAlongTheAxis;
    procedure TestAHalfTurnIsStillCentredButFlipped;
    procedure TestAHalfTurnTheOtherWayIsTheSameHalfTurn;
    { ---- an authored stride ---- }
    procedure TestAnAuthoredStrideBeatsTheMeasuredRule;
    procedure TestAStrideOfOneKeepsThemAllHoweverCrowded;
    procedure TestAStrideOfThreeKeepsEveryThird;
    { ---- the two ends ---- }
    procedure TestTheLastLabelIsDroppedWhenTheStrideMissesIt;
    procedure TestShowMaxLabelBringsItBack;
    procedure TestShowMinLabelCanDropAnOnStrideFirstLabel;
    procedure TestNeitherEndRuleAppliesToASingleLabel;
  end;

  { From the option text to the drawn label. The suite above proves the
    layout honours a stride it is handed; this one proves anything ever
    hands it one -- which in this repository is the half that goes missing. }
  TAdvChartIntervalOptionTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    { A bar chart of ACount categories, with AAxisLabel spliced into the
      category axis. }
    procedure DrawCats(ACount: Integer; const AAxisLabel: string;
      const AAxisTick: string = ''; AVertical: Boolean = False);
    function CatSpec: PTyAxisLayoutSpec;
    { Which category indices got drawn, as `0,3,6`. }
    function ShownIndices: string;
    { How many red tick marks stand just under the axis line. }
    function RedMarks: Integer;
  published
    procedure TestWithNoIntervalTheAxisStillThinsItself;
    procedure TestIntervalZeroDrawsEveryLabel;
    procedure TestIntervalCountsWhatItSkipsNotWhatItKeeps;
    procedure TestIntervalTwoIsEveryThird;
    procedure TestANegativeIntervalMeansEveryOne;
    procedure TestANonIntegerIntervalTakesItsWholePart;
    procedure TestAValueAxisIgnoresTheOptionEntirely;
    procedure TestTheTicksFollowTheLabelsUnlessToldOtherwise;
    procedure TestShowMaxLabelReachesTheLayout;
    procedure TestANonCategoryAxisIsHandedNoStrideEvenWhenAsked;
    procedure TestAnExplicitTickStrideChangesTheMarksOnScreen;
    procedure TestATickGoesWithItsHiddenLabel;
  end;

  { The same fact, asked of the pixels. }
  TAdvChartRotatedInkTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    { Grey enough to be a glyph and dark enough not to be a grid line. }
    function IsLabelInk(const AP: TBGRAPixel): Boolean;
    { Pixels that are label ink in the FIRST render and are not in the
      second -- that is, label ink the series destroyed. }
    function InkLostTo(const ABare, AWithSeries: string): Integer;
  published
    procedure TestARotatedLabelIsNotEatenByTheSeries;
  end;

implementation

const
  cW = 900;
  cH = 520;

procedure TAnchorMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := Length(AText) * 7;
  AH := 14;
end;

function TAnchorMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

procedure TAdvChartAxisLabelTest.SetUp;
begin
  inherited SetUp;
  FM := TAnchorMeasurer.Create;
end;

function TAdvChartAxisLabelTest.Spec(ASide: TTyAxisSide; ARotateDeg: Double;
  AInside: Boolean): TTyAxisLayoutSpec;
begin
  Result := Default(TTyAxisLayoutSpec);
  Result.Side := ASide;
  Result.ShowLabels := True;
  Result.Labels := TTyStringArray.Create('A', 'B');
  Result.Positions := TTyDoubleArray.Create(0, 1);
  Result.FontSizeLogical := 12;
  Result.FontWeight := 400;
  Result.LabelMarginLogical := 8;
  Result.RotationRad := ARotateDeg * Pi / 180;
  Result.LabelInside := AInside;
  { A value axis' labels, never thinned by index, and two far enough apart
  that neither end gives way: index 0 is always placed and always shown. }
end;

function TAdvChartAxisLabelTest.AnchorsOf(ASide: TTyAxisSide;
  ARotateDeg: Double; AInside: Boolean): string;
var p: TTyAxisLabelPlacementArray;
begin
  p := TyLayoutAxisLabels(Spec(ASide, ARotateDeg, AInside),
                          TyRectF(10, 10, 200, 150), FM, 96);
  case p[0].AnchorH of
    tahLeft: Result := 'L';
    tahRight: Result := 'R';
  else
    Result := 'C';
  end;
  case p[0].AnchorV of
    tavTop: Result := Result + 'T';
    tavBottom: Result := Result + 'B';
  else
    Result := Result + 'M';
  end;
end;

procedure TAdvChartAxisLabelTest.TestUnturnedLabelsKeepTheAnchorsTheyAlwaysHad;
begin
  { THE WHOLE POINT OF ADOPTING UPSTREAM'S RULE: fed a rotation of nought it
    reproduces the four-side table it replaced, exactly. If it did not, every
    unrotated chart in the library would have moved. }
  AssertEquals('bottom: centred, hanging below', 'CT', AnchorsOf(asBottom, 0));
  AssertEquals('top: centred, sitting above', 'CB', AnchorsOf(asTop, 0));
  AssertEquals('left: right-aligned, middled', 'RM', AnchorsOf(asLeft, 0));
  AssertEquals('right: left-aligned, middled', 'LM', AnchorsOf(asRight, 0));
end;

procedure TAdvChartAxisLabelTest.TestInsideFlipsEveryOneOfThem;
begin
  { `axisLabel.inside` puts the labels on the other side of the line, and the
    anchors have to follow or they read outward from a point that is now
    inward. In the rule this is one sign flip, not four cases. }
  AssertEquals('CB', AnchorsOf(asBottom, 0, True));
  AssertEquals('CT', AnchorsOf(asTop, 0, True));
  AssertEquals('LM', AnchorsOf(asLeft, 0, True));
  AssertEquals('RM', AnchorsOf(asRight, 0, True));
end;

procedure TAdvChartAxisLabelTest.TestATurnedLabelHangsByItsEndNotItsMiddle;
begin
  { A bottom axis turned 45 degrees anticlockwise: the text's RIGHT end sits on
    the anchor and the run goes down and to the left, entirely clear of the
    axis line. Centred -- which is what the old table gave -- sends half of it
    the other way, up into the plot. }
  AssertEquals('RM', AnchorsOf(asBottom, 45));
end;

procedure TAdvChartAxisLabelTest.TestTurningTheOtherWayHangsTheOtherWay;
begin
  { And the mirror image, which is the assertion that says the rule is reading
    the SIGN of the turn and not merely noticing that there is one. }
  AssertEquals('LM', AnchorsOf(asBottom, -45));
end;

procedure TAdvChartAxisLabelTest.TestAQuarterTurnOnAVerticalAxisReadsAlongTheAxis;
begin
  { THE ANGLE THAT DECIDES THE ANCHORS IS THE TEXT'S RELATIVE TO THE AXIS. A
    left axis lies along a quarter turn, so a label turned a quarter turn is
    parallel WITH it -- back in the centred arm, reading up the side. An
    implementation that compared the text's angle against the screen instead
    would keep it middled and hang it by an end. }
  AssertEquals('left, quarter turn: centred again', 'CB', AnchorsOf(asLeft, 90));
  AssertEquals('right, quarter turn', 'CT', AnchorsOf(asRight, 90));
end;

procedure TAdvChartAxisLabelTest.TestAHalfTurnIsStillCentredButFlipped;
begin
  { Upside down along the line: still centred, but the box flips over, or the
    text would sit on the wrong side of its own anchor. }
  AssertEquals('CB', AnchorsOf(asBottom, 180));
  AssertEquals('CT', AnchorsOf(asTop, 180));
end;

procedure TAdvChartAxisLabelTest.TestAHalfTurnTheOtherWayIsTheSameHalfTurn;
begin
  { THE ASSERTION THAT MAKES THE NORMALISATION OBSERVABLE. Every other angle
    in this suite gives the same anchors whether or not the difference is
    wrapped into a full turn, so the wrap could be deleted and nothing would
    notice. Minus a half turn is the exception: unwrapped it is neither near
    nought nor near PI and falls into the hangs-by-an-end arm, which reads as
    a label lying on its side when the author asked for it upside down. }
  AssertEquals('CB', AnchorsOf(asBottom, -180));
  AssertEquals('CT', AnchorsOf(asTop, -180));
end;

{ ---- an authored stride, asked of the layout ---- }

{ Twelve labels wide enough that the measured rule is bound to thin them:
  each is 7 chars * 7 px = 49 px and the axis is 190 px long, so nothing
  short of a stride of four fits. That is the point -- an authored stride
  has to win against a rule that disagrees with it. }
function TAdvChartAxisLabelTest.Crowded(AStride: Integer): TTyAxisLayoutSpec;
var i: Integer;
begin
  Result := Spec(asBottom, 0);
  Result.LabelKind := lakCategory;
  Result.ForcedLabelStep := AStride;
  SetLength(Result.Labels, 12);
  SetLength(Result.Positions, 12);
  for i := 0 to 11 do
  begin
    Result.Labels[i] := Format('Cat %3.3d', [i]);
    Result.Positions[i] := i / 11;
  end;
end;

{ The indices that actually get drawn, as `0,3,6`. }
function TAdvChartAxisLabelTest.ShownIndices(
  const ASpec: TTyAxisLayoutSpec): string;
var p: TTyAxisLabelPlacementArray; i: Integer;
begin
  Result := '';
  p := TyLayoutAxisLabels(ASpec, TyRectF(10, 10, 200, 150), FM, 96);
  for i := 0 to High(p) do
    if p[i].Shown then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + IntToStr(i);
    end;
end;

procedure TAdvChartAxisLabelTest.TestAnAuthoredStrideBeatsTheMeasuredRule;
begin
  { Left to itself this axis thins hard -- twelve labels that each need a
    quarter of the axis. The assertion is that the measured answer and the
    authored answer are DIFFERENT, so that the next two tests are testing
    the author's number rather than agreeing with the measurer by luck. }
  AssertEquals('measured, for contrast', '0,4,8', ShownIndices(Crowded(0)));
  { AND THE FIRST GIVES WAY: at every other label these 49-px labels stand
    34.5 px apart, and an end that crowds its neighbour is dropped.
    [Revised in batch 39: 0,2,4,6,8,10 -- the ends were never weighed.] }
  AssertEquals('authored', '2,4,6,8,10', ShownIndices(Crowded(2)));
end;

procedure TAdvChartAxisLabelTest.TestAStrideOfOneKeepsThemAllHoweverCrowded;
var sp: TTyAxisLayoutSpec;
begin
  { `interval: 0` -- the commonest value anybody writes -- means DRAW THEM
    ALL, collisions and all. No value the measured rule can return says
    that, because the measured rule exists precisely to avoid collisions. }
  sp := Crowded(1);
  sp.ShowAllLabels := True;
  AssertEquals('0,1,2,3,4,5,6,7,8,9,10,11', ShownIndices(sp));
  { A NEGATIVE ONE BUILDS THEM ALL TOO, but only nought skips the ends: the
    two that crowd their neighbours go }
  AssertEquals('interval -1', '1,2,3,4,5,6,7,8,9,10', ShownIndices(Crowded(1)));
end;

procedure TAdvChartAxisLabelTest.TestAStrideOfThreeKeepsEveryThird;
begin
  AssertEquals('0,3,6,9', ShownIndices(Crowded(3)));
end;

{ ---- the two ends ---- }

procedure TAdvChartAxisLabelTest.TestTheLastLabelIsDroppedWhenTheStrideMissesIt;
begin
  { Twelve labels and a stride of five: 0, 5, 10 -- and 11, the one that says
    where the data STOPS, is not on the grid and goes. That is upstream's
    default and it is deliberate, not an oversight: a last label half a
    stride from its neighbour reads as a mistake. }
  AssertEquals('0,5,10', ShownIndices(Crowded(5)));
end;

procedure TAdvChartAxisLabelTest.TestShowMaxLabelBringsItBack;
var sp: TTyAxisLayoutSpec;
begin
  { `showMaxLabel: true` is a promise, and this is the whole reason the
    option exists -- the end of the axis is the one label a reader looks for
    and the stride is the thing most likely to have taken it. }
  sp := Crowded(5);
  sp.ShowMaxLabel := aelShow;
  { AND THE ONE IT CROWDS GIVES WAY INSTEAD: 11 and 10 are 17 px apart
    [Revised in batch 39: 0,5,10,11 -- both kept, overlapping.] }
  AssertEquals('0,5,11', ShownIndices(sp));
end;

procedure TAdvChartAxisLabelTest.TestShowMinLabelCanDropAnOnStrideFirstLabel;
var sp: TTyAxisLayoutSpec;
begin
  { And it cuts the other way. A stride anchored at nought ALWAYS lands on
    the first label, so `false` is the only thing that can remove it -- which
    makes this the assertion that says the option is read as three states
    and not as a Boolean defaulting to true. }
  sp := Crowded(5);
  sp.ShowMinLabel := aelHide;
  AssertEquals('5,10', ShownIndices(sp));
end;

procedure TAdvChartAxisLabelTest.TestNeitherEndRuleAppliesToASingleLabel;
var sp: TTyAxisLayoutSpec;
begin
  { One label is both ends at once. Upstream weighs an end against its inner
    neighbour and bails when there is not one, so neither option applies --
    and a port that applied both would have them fight over one index. }
  sp := Spec(asBottom, 0);
  sp.Labels := TTyStringArray.Create('only');
  sp.Positions := TTyDoubleArray.Create(0);
  sp.ShowMinLabel := aelHide;
  sp.ShowMaxLabel := aelShow;
  AssertEquals('0', ShownIndices(sp));
end;

{ ======================= from the option text ======================= }

procedure TAdvChartIntervalOptionTest.SetUp;
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

procedure TAdvChartIntervalOptionTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartIntervalOptionTest.DrawCats(ACount: Integer;
  const AAxisLabel: string; const AAxisTick: string; AVertical: Boolean);
var cats, data, cat, val, opt: string; i: Integer;
begin
  cats := '';
  data := '';
  for i := 1 to ACount do
  begin
    if i > 1 then
    begin
      cats := cats + ',';
      data := data + ',';
    end;
    cats := cats + Format('"Category %d"', [i]);
    data := data + IntToStr(10 + (i * 37) mod 50);
  end;
  cat := '{"type":"category","data":[' + cats + ']';
  if AAxisLabel <> '' then cat := cat + ',"axisLabel":' + AAxisLabel;
  if AAxisTick <> '' then cat := cat + ',"axisTick":' + AAxisTick;
  cat := cat + '}';
  val := '{"type":"value"}';
  if AVertical then
    opt := '{"xAxis":' + val + ',"yAxis":' + cat
  else
    opt := '{"xAxis":' + cat + ',"yAxis":' + val;
  opt := opt + ',"series":[{"type":"bar","data":[' + data + ']}]}';
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 0, 255, 255));
  FChart.Option := opt;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartIntervalOptionTest.CatSpec: PTyAxisLayoutSpec;
var g: TTyGridBuild; a: TTyAxis;
begin
  g := FChart.Build.Grid(0);
  a := g.XAxis(0);
  if a.AxisType <> atCategory then a := g.YAxis(0);
  Result := g.SpecFor(a);
end;

function TAdvChartIntervalOptionTest.ShownIndices: string;
var p: PTyAxisLayoutSpec; i: Integer;
begin
  Result := '';
  p := CatSpec;
  if p = nil then Exit;
  for i := 0 to High(p^.Placements) do
    if p^.Placements[i].Shown then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + IntToStr(i);
    end;
end;

function TAdvChartIntervalOptionTest.RedMarks: Integer;
var
  x, y: Integer;
  p: TBGRAPixel;
  plot: TTyRectF;
  inRun: Boolean;
begin
  Result := 0;
  plot := FChart.Build.Grid(0).PlotRect;
  { Two pixels below the axis line: inside the mark, clear of the line. }
  y := Round(plot.Bottom) + 2;
  inRun := False;
  for x := 1 to cW - 2 do
  begin
    p := FBmp.GetPixel(x, y);
    if (p.alpha > 0) and (p.red > p.green + 60) and (p.red > p.blue + 60) then
    begin
      if not inRun then Inc(Result);
      inRun := True;
    end
    else
      inRun := False;
  end;
end;

procedure TAdvChartIntervalOptionTest.TestWithNoIntervalTheAxisStillThinsItself;
begin
  { THE CONTRAST EVERY TEST BELOW LEANS ON. Thirty categories on a 900px
    axis do not fit, so left alone the measured rule drops most of them. If
    this ever came back as `all of them`, every `interval` assertion below
    would be agreeing with the default rather than testing the option. }
  DrawCats(30, '');
  AssertEquals('0,4,8,12,16,20,24,28', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestIntervalZeroDrawsEveryLabel;
begin
  { The commonest thing anybody writes, and until now a no-op. }
  DrawCats(8, '{"interval":0}');
  AssertEquals('0,1,2,3,4,5,6,7', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestIntervalCountsWhatItSkipsNotWhatItKeeps;
begin
  { `interval: 1` is EVERY OTHER ONE, not every one. The option counts what
    it skips, so the stride is one more than the number written -- and a
    port that reads it as `every Nth` makes 0 mean `none` and 1 mean `all`,
    which is exactly backwards on the two most-used values. }
  DrawCats(8, '{"interval":1}');
  AssertEquals('0,2,4,6', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestIntervalTwoIsEveryThird;
begin
  DrawCats(10, '{"interval":2}');
  AssertEquals('0,3,6,9', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestANegativeIntervalMeansEveryOne;
begin
  { Upstream clamps the stride at one rather than validating the number, so
    a negative interval is legal and means the same as nought. }
  DrawCats(8, '{"interval":-5}');
  AssertEquals('0,1,2,3,4,5,6,7', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestANonIntegerIntervalTakesItsWholePart;
begin
  { A DELIBERATE DIVERGENCE, pinned so it cannot drift into an accident.
    Upstream makes a stride of 3.7 out of `interval: 2.7` and walks an
    ordinal axis by it, emitting tick values that name no category. The port
    takes the whole part. }
  DrawCats(10, '{"interval":2.7}');
  AssertEquals('0,3,6,9', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestAValueAxisIgnoresTheOptionEntirely;
var p: PTyAxisLayoutSpec;
begin
  { CATEGORY AXES ONLY, and the reason is not arbitrary: on a value axis the
    TICKS come first and the labels are made from them, so there is nothing
    for a label stride to thin. Asked of the spec rather than of the drawn
    labels, because a value axis with few enough labels draws them all
    anyway and the assertion would pass either way. }
  DrawCats(8, '', '', True);
  p := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).XAxis(0));
  AssertEquals('a value axis was handed no stride', 0, p^.ForcedLabelStep);
end;

procedure TAdvChartIntervalOptionTest.TestTheTicksFollowTheLabelsUnlessToldOtherwise;
var p: PTyAxisLayoutSpec;
begin
  { `axisTick.interval` defaults to `auto`, and `auto` on the ticks does not
    mean `work one out`: upstream re-runs the LABEL pipeline and harvests its
    ticks. So the label stride drives the marks and the split lines one way,
    and nought here means `follow them`. }
  DrawCats(10, '{"interval":2}');
  p := CatSpec;
  AssertEquals('labels', 3, p^.ForcedLabelStep);
  AssertEquals('and the ticks just follow', 0, p^.TickStep);
  { Named outright, the ticks go their own way and the labels do not move. }
  DrawCats(10, '{"interval":2}', '{"interval":4}');
  p := CatSpec;
  AssertEquals('labels unchanged', 3, p^.ForcedLabelStep);
  AssertEquals('ticks on their own stride', 5, p^.TickStep);
  AssertEquals('and the labels really did not move', '0,3,6,9', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestShowMaxLabelReachesTheLayout;
begin
  { Twelve categories on a stride of five: 0, 5, 10, and the eleventh --
    which says where the data stops -- is off the grid and goes. }
  DrawCats(12, '{"interval":4}');
  AssertEquals('0,5,10', ShownIndices);
  { KEPT, AND THE TENTH GIVES WAY: the two crowd each other, and upstream's
    showMaxLabel keeps its end by dropping the neighbour.
    [Revised in batch 39: 0,5,10,11, the two overlapping.] }
  DrawCats(12, '{"interval":4,"showMaxLabel":true}');
  AssertEquals('0,5,11', ShownIndices);
  DrawCats(12, '{"interval":4,"showMinLabel":false}');
  AssertEquals('5,10', ShownIndices);
end;

procedure TAdvChartIntervalOptionTest.TestANonCategoryAxisIsHandedNoStrideEvenWhenAsked;
var p: PTyAxisLayoutSpec;
begin
  { The first version of this test drew a value axis that carried no
    axisLabel node at all, so `read it only on a category axis` and `read it
    everywhere` gave the same answer and the guard was untested. The option
    has to be PRESENT on the wrong kind of axis for the guard to mean
    anything.

    Upstream's reason for the guard: on a value or time axis the TICKS come
    first and the labels are made from them, so a label stride has nothing to
    thin. On a time axis it would be worse than useless -- dropping every
    other tick takes the month markers with it. }
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 0, 255, 255));
  FChart.Option :=
    '{"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value","axisLabel":{"interval":3}},'
    + '"series":[{"type":"bar","data":[1,2,3]}]}';
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  p := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).YAxis(0));
  AssertEquals('a value axis asked for a stride and was refused',
               0, p^.ForcedLabelStep);
  { And the same on a time axis, where honouring it would undo the levels. }
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 0, 255, 255));
  FChart.Option :=
    '{"useUTC":true,"xAxis":{"type":"time","axisLabel":{"interval":3}},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":['
    + '["2024-03-01T00:00:00Z",1],["2024-03-03T00:00:00Z",2]]}]}';
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  p := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).XAxis(0));
  AssertEquals('nor a time axis', 0, p^.ForcedLabelStep);
end;

procedure TAdvChartIntervalOptionTest.TestATickGoesWithItsHiddenLabel;
begin
  { OFF THE BAND, A TICK GOES WITH ITS LABEL. Twelve categories with no
    boundary gap at interval 4 build 0, 5, 10 and the eleventh, which is off
    the interval and hidden -- and its mark is not drawn either: three on
    screen, not four. On a band the marks are edges and stay. }
  FCtl.StyleOverride :=
    'TyAdvChartAxisTick { border-color: #FF0000; border-width: 1px; }';
  DrawCats(12, '{"interval":4}', '{"show":true},"boundaryGap":false');
  AssertEquals('the labels', '0,5,10', ShownIndices);
  AssertEquals('and their marks alone', 3, RedMarks);
  DrawCats(12, '{"interval":4}', '{"show":true}');
  AssertEquals('on the band, every edge and the closing one', 4, RedMarks);
end;

procedure TAdvChartIntervalOptionTest.TestAnExplicitTickStrideChangesTheMarksOnScreen;
var all, thinned: Integer;
begin
  { The spec carrying a tick stride is not the same fact as the paint pass
    walking by it, and only the second one a reader can see. Counted as
    MARKS rather than read off a field: the marks are the thing the option
    names.

    The labels are pinned to every one in both renders, so the only thing
    that moves is the ticks -- which is also what says the two strides are
    genuinely independent rather than one driving the other. }
  FCtl.StyleOverride :=
    'TyAdvChartAxisTick { border-color: #FF0000; border-width: 1px; }';
  { SHOWN OUTRIGHT, because a banded category axis hides its ticks by
    default -- a mark between two bands points at neither of them. The
    subject here is the STRIDE, so the marks have to exist first. }
  DrawCats(12, '{"interval":0}', '{"show":true}');
  all := RedMarks;
  AssertEquals('every band edge got a mark', 13, all);
  DrawCats(12, '{"interval":0}', '{"show":true,"interval":4}');
  thinned := RedMarks;
  { ONE EDGE IN FIVE AND THE CLOSING ONE: upstream always adds the edge past
    the last category, so 0, 5, 10 and 12.
    [Revised in batch 40: 3 -- the closing edge only when the count suited
    the stride.] }
  AssertEquals('one edge in five, and the last', 4, thinned);
  AssertEquals('and the labels stayed where they were',
               '0,1,2,3,4,5,6,7,8,9,10,11', ShownIndices);
end;

{ ============================ the ink ============================ }

procedure TAdvChartRotatedInkTest.SetUp;
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

procedure TAdvChartRotatedInkTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartRotatedInkTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 0, 255, 255));
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartRotatedInkTest.IsLabelInk(const AP: TBGRAPixel): Boolean;
var lo, hi: Integer;
begin
  Result := False;
  if AP.alpha = 0 then Exit;
  lo := Min(AP.red, Min(AP.green, AP.blue));
  hi := Max(AP.red, Max(AP.green, AP.blue));
  { Grey rules the bars out -- they are blue, and blue is nowhere near
    neutral. Dark rules the split lines out, which are a very pale grey. }
  Result := (hi - lo < 30) and (AP.red + AP.green + AP.blue < 600);
end;

function TAdvChartRotatedInkTest.InkLostTo(const ABare,
  AWithSeries: string): Integer;
var
  x, y: Integer;
  bare: TBGRABitmap;
begin
  Draw(ABare);
  bare := FBmp;
  FBmp := nil;
  try
    Draw(AWithSeries);
    Result := 0;
    for y := 1 to cH - 2 do
      for x := 1 to cW - 2 do
        if IsLabelInk(bare.GetPixel(x, y))
          and not IsLabelInk(FBmp.GetPixel(x, y)) then Inc(Result);
  finally
    bare.Free;
  end;
end;

procedure TAdvChartRotatedInkTest.TestARotatedLabelIsNotEatenByTheSeries;
const
  cAxis = '"xAxis":{"type":"category","data":['
        + '"Category 1","Category 2","Category 3","Category 4",'
        + '"Category 5","Category 6","Category 7","Category 8"],'
        + '"axisLabel":{"rotate":45,"interval":0}},'
        { PINNED, so that the value axis draws the same numbers in the same
          places in both renders. Left to itself it spans 0..1 without a
          series and 0..60 with one, and then every y label counts as
          `destroyed` -- which is how the first version of this test came
          out red against a correct implementation. }
        + '"yAxis":{"type":"value","min":0,"max":60}';
var lost: Integer;
begin
  { THE ASSERTION THAT ACTUALLY CATCHES IT.

    The batch that shipped `axisLabel.rotate` tested the anchor POINT and that
    the gutter grew to fit the turned extent. Both are true of a label pointing
    the WRONG way -- into the plot -- so both stayed green while every rotated
    label on every chart with a series came out with its tail painted over.

    The first attempt at this test did not catch it either, and the reason is
    worth keeping: it counted ink in the band BELOW the axis line, which is
    exactly where the damage is NOT. The erased half is the half that swung
    UP, over the line, into the plot.

    So the question is asked as a difference instead: which pixels are label
    ink when the chart has no data, and stop being label ink when it does?
    Placement does not depend on the series, so with the labels hanging clear
    the answer is none. Grey-and-dark separates a glyph from the blue bars and
    from the pale split lines. }
  lost := InkLostTo('{' + cAxis + ',"series":[]}',
                    '{' + cAxis + ',"series":[{"type":"bar","data":'
                    + '[10,47,34,21,58,45,32,19]}]}');
  { MEASURED, not guessed: correct is exactly 0 and the shipped bug is 32 on
    this fixture. A first pass at this test allowed 40 and let the bug
    straight through -- the tolerance has to be smaller than the defect, and
    the only way to know that is to run it against both. The few pixels of
    slack are for antialiasing, not for glyphs. }
  AssertTrue(Format('the series destroyed %d pixels of label', [lost]),
             lost < 8);
end;

initialization
  RegisterTest(TAdvChartAxisLabelTest);
  RegisterTest(TAdvChartIntervalOptionTest);
  RegisterTest(TAdvChartRotatedInkTest);
end.
