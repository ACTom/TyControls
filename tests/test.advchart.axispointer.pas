unit test.advchart.axispointer;
{$mode objfpc}{$H+}
{ The pointer that follows the cursor along an axis, and the tooltip it brings.

  THE OPTION RESOLUTION IS WHERE THE BUGS LIVE, not the drawing. Three places
  can write an axisPointer and the precedence is not the one the names suggest;
  nine of the tooltip's keys cross to the axis and the rest are silently dead;
  and three of those nine are then overwritten. Every one of those rules is a
  question with a definite answer, so most of this file asks them of the pure
  reader and never renders anything.

  What IS rendered is the other half of the same question: whether the answers
  reach the picture. A rule that resolves correctly into a spec nothing draws
  from is this repository's most frequent defect. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Color, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Tooltip, tyControls.AdvChart.AxisPointer,
     tyControls.AdvanceChart;
type
  TAdvChartAxisPointerRuleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure TearDown; override;
    function SpecOf(const AText: string; AIsCategory, ATriggerTooltip,
      ACross: Boolean): TTyAxisPointerSpec;
  published
    procedure TestTheAxisOutranksTheTooltipWhichOutranksTheRoot;
    procedure TestOnlyTheNineNamedFieldsCrossFromTheTooltip;
    procedure TestCrossIsNeverAShape;
    procedure TestSnapIsRecomputedFromTheAxisKind;
    procedure TestTheAxisOwnSnapStillWins;
    procedure TestTheLabelIsOffForATooltipAxisAndOnForACross;
    procedure TestAnExplicitLabelShowSurvivesBothDefaults;
    procedure TestAPointerShowDoesNotSwallowItsLabelShow;
    procedure TestTheBandIsHalfWidthAtTheEnds;
    procedure TestADashWordIsMultiplesOfTheLineWidth;
  end;

  TAxisProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
    function AxisContent(const AHits: TTyAxisHitArray;
      const ASpec: TTyTooltipSpec): TTyTooltipBlock;
    function ValueText(AAxis: TTyAxis; AValue: Double): string;
  end;

  TAdvChartAxisTriggerTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAxisProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    function BarPoint(ACat: Integer; AValue: Double): TPoint;
    function InkAddedByHover(const AOption: string; AX, AY: Integer): Integer;
  published
    procedure TestAnAxisTriggerDrawsAPointerAndABox;
    procedure TestTheSectionIsHeadedByTheAxisValue;
    procedure TestEachRowIsNamedByItsSeriesNotByTheCategory;
    procedure TestOnlyTheNearestSeriesReachesTheBox;
    procedure TestACloserSeriesEvictsTheOnesAlreadyCollected;
    procedure TestASeriesShorterThanTheAxisDropsOut;
    procedure TestACrossStillMakesOneSection;
    procedure TestShowContentFalseKeepsThePointerAndDropsTheBox;
    procedure TestAModelChangeTakesThePointerAway;
    procedure TestThePointerLabelRoundsToTheScalesPrecision;
    procedure TestOrderReordersTheRowsWithinTheSection;
    procedure TestACrossPutsAPointerOnBothAxes;
    procedure TestACrossDrawsEvenWithoutAnAxisTrigger;
    procedure TestAShadowNeedsACategoryAxis;
    procedure TestLeavingTheChartTakesThePointerAway;
  end;

implementation

const
  cW = 480;
  cH = 320;
  cTwoSeries =
    '{"tooltip":{"trigger":"axis"},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]},' +
    '{"type":"bar","name":"Cost","data":[10,30,50,70]}]}';

{ ==================== the rules ==================== }

procedure TAdvChartAxisPointerRuleTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartAxisPointerRuleTest.SpecOf(const AText: string;
  AIsCategory, ATriggerTooltip, ACross: Boolean): TTyAxisPointerSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses', FOpt.SetOptionText(AText));
  Result := TyAxisPointerSpecOf(FOpt, 'xAxis', 0, AIsCategory, True,
    ATriggerTooltip, ACross);
end;

procedure TAdvChartAxisPointerRuleTest.TestTheAxisOutranksTheTooltipWhichOutranksTheRoot;
var s: TTyAxisPointerSpec;
begin
  { "TOOLTIP WINS" IS ONLY TRUE AGAINST THE ROOT. Upstream resolves a
    tooltip-driven axis as the AXIS' own block with the tooltip layer as its
    PARENT, so the axis beats both -- which reads backwards until you see the
    model chain, and is the single most likely thing for a port to get the
    wrong way round. }
  s := SpecOf('{"axisPointer":{"type":"none"},' +
              '"tooltip":{"axisPointer":{"type":"line"}},' +
              '"xAxis":{"type":"category","axisPointer":{"type":"shadow"}}}',
              True, True, False);
  AssertTrue('the axis wins', s.PointerType = aptShadow);

  s := SpecOf('{"axisPointer":{"type":"none"},' +
              '"tooltip":{"axisPointer":{"type":"shadow"}},' +
              '"xAxis":{"type":"category"}}', True, True, False);
  AssertTrue('the tooltip beats the root', s.PointerType = aptShadow);

  s := SpecOf('{"axisPointer":{"type":"shadow"},"xAxis":{"type":"category"}}',
              True, True, False);
  AssertTrue('and the root is reachable when neither wrote it',
             s.PointerType = aptShadow);
end;

procedure TAdvChartAxisPointerRuleTest.TestOnlyTheNineNamedFieldsCrossFromTheTooltip;
var s: TTyAxisPointerSpec;
begin
  { `show` IS NOT ONE OF THE NINE. Written under `tooltip.axisPointer` it is
    silently dead upstream -- the clone copies nine named keys and that is not
    one of them -- so the root's answer stands. A port that read the whole
    block would switch an axis pointer off with a key that does nothing. }
  s := SpecOf('{"axisPointer":{"show":true},' +
              '"tooltip":{"axisPointer":{"show":false}},' +
              '"xAxis":{"type":"category"}}', True, True, False);
  AssertTrue('the tooltip could not switch it off', s.Show = apsYes);
end;

procedure TAdvChartAxisPointerRuleTest.TestCrossIsNeverAShape;
var s: TTyAxisPointerSpec;
begin
  { There is no cross BUILDER anywhere upstream -- only `line` and `shadow` --
    and the word is rewritten to 'line' per axis on the tooltip path. A root
    `axisPointer: {type:'cross'}` reaching the un-rewritten table is an
    upstream crash; coercing it here is the port's own guard. }
  s := SpecOf('{"tooltip":{"axisPointer":{"type":"cross"}},' +
              '"xAxis":{"type":"category"}}', True, True, True);
  AssertTrue('cross became a line', s.PointerType = aptLine);
end;

procedure TAdvChartAxisPointerRuleTest.TestSnapIsRecomputedFromTheAxisKind;
var s: TTyAxisPointerSpec;
begin
  { A CATEGORY AXIS DOES NOT AUTO-SNAP -- upstream's own reason is that a tick
    with no value beneath it could not otherwise be hovered. A value axis does,
    when the tooltip is what asked. }
  s := SpecOf('{"tooltip":{"trigger":"axis"},"xAxis":{"type":"category"}}',
              True, True, False);
  AssertFalse('category', s.Snap);
  s := SpecOf('{"tooltip":{"trigger":"axis"},"xAxis":{"type":"value"}}',
              False, True, False);
  AssertTrue('value', s.Snap);
  { The second arm of a cross triggers no tooltip, so it does not snap. }
  s := SpecOf('{"tooltip":{"axisPointer":{"type":"cross"}},' +
              '"yAxis":{"type":"value"}}', False, False, True);
  AssertFalse('the other arm of a cross', s.Snap);
  { AND `tooltip.axisPointer.snap` IS DEAD CODE. It is cloned into the volatile
    layer and then overwritten one loop later, unconditionally. }
  s := SpecOf('{"tooltip":{"trigger":"axis","axisPointer":{"snap":true}},' +
              '"xAxis":{"type":"category"}}', True, True, False);
  AssertFalse('a tooltip cannot ask for snap', s.Snap);
end;

procedure TAdvChartAxisPointerRuleTest.TestTheAxisOwnSnapStillWins;
var s: TTyAxisPointerSpec;
begin
  { The recompute is a DEFAULT, not a rule: it fills what nobody wrote. The
    axis' own block was claimed first and keeps its answer. }
  s := SpecOf('{"tooltip":{"trigger":"axis"},' +
              '"xAxis":{"type":"category","axisPointer":{"snap":true}}}',
              True, True, False);
  AssertTrue(s.Snap);
end;

procedure TAdvChartAxisPointerRuleTest.TestTheLabelIsOffForATooltipAxisAndOnForACross;
var s: TTyAxisPointerSpec;
begin
  { THE CROSS INVERTS THE DEFAULT rather than nudging it -- which is why a
    cross has those two little chips at the axis ends and an ordinary axis
    tooltip has none. }
  s := SpecOf('{"tooltip":{"trigger":"axis"},"xAxis":{"type":"category"}}',
              True, True, False);
  AssertFalse('an ordinary tooltip axis', s.LabelSpec.Show);
  s := SpecOf('{"tooltip":{"axisPointer":{"type":"cross"}},' +
              '"xAxis":{"type":"category"}}', True, True, True);
  AssertTrue('a cross', s.LabelSpec.Show);
end;

procedure TAdvChartAxisPointerRuleTest.TestAnExplicitLabelShowSurvivesBothDefaults;
var s: TTyAxisPointerSpec;
begin
  s := SpecOf('{"tooltip":{"trigger":"axis",' +
              '"axisPointer":{"label":{"show":true}}},' +
              '"xAxis":{"type":"category"}}', True, True, False);
  AssertTrue('written on, stays on', s.LabelSpec.Show);
  s := SpecOf('{"tooltip":{"axisPointer":{"type":"cross",' +
              '"label":{"show":false}}},"xAxis":{"type":"category"}}',
              True, True, True);
  AssertFalse('written off, stays off even under a cross', s.LabelSpec.Show);
end;

procedure TAdvChartAxisPointerRuleTest.TestAPointerShowDoesNotSwallowItsLabelShow;
var s: TTyAxisPointerSpec;
begin
  { `show` IS A KEY OF BOTH BLOCKS -- the pointer's and its label's -- and one
    flat list of claimed names lets the first swallow the second. Both are
    written here, which is the only shape that asks the question: a fixture
    with one of them passes against a reader that cannot tell them apart. }
  s := SpecOf('{"tooltip":{"trigger":"axis"},"xAxis":{"type":"category",' +
              '"axisPointer":{"show":true,"label":{"show":true}}}}',
              True, True, False);
  AssertTrue('the pointer is on', s.Show = apsYes);
  AssertTrue('and so is its label', s.LabelSpec.Show);
end;

procedure TAdvChartAxisPointerRuleTest.TestTheBandIsHalfWidthAtTheEnds;
var lo, hi: Double;
begin
  { CLAMPED, NOT CENTRED-AND-OVERFLOWING. The two ends clamp independently, so
    the band at the first category is half width and ASYMMETRIC -- it is not
    shifted inward to keep its size. A port that centred and then clipped would
    move the band off its own category. }
  AssertTrue(TyAxisPointerBand(100, 40, 0, 400, lo, hi));
  AssertEquals('middle, left', 80.0, lo, 1e-9);
  AssertEquals('middle, right', 120.0, hi, 1e-9);

  AssertTrue(TyAxisPointerBand(10, 40, 0, 400, lo, hi));
  AssertEquals('clamped at the start', 0.0, lo, 1e-9);
  AssertEquals('and not pushed inward', 30.0, hi, 1e-9);

  AssertTrue(TyAxisPointerBand(395, 40, 0, 400, lo, hi));
  AssertEquals('clamped at the end', 375.0, lo, 1e-9);
  AssertEquals('', 400.0, hi, 1e-9);

  { A DESCENDING EXTENT IS THE ORDINARY CASE ON A Y AXIS, and the clamp must
    not depend on which way round it arrived. }
  AssertTrue(TyAxisPointerBand(100, 40, 400, 0, lo, hi));
  AssertEquals('descending, left', 80.0, lo, 1e-9);
  AssertEquals('descending, right', 120.0, hi, 1e-9);

  AssertFalse('no band, nothing to draw', TyAxisPointerBand(100, 0, 0, 400, lo, hi));
end;

procedure TAdvChartAxisPointerRuleTest.TestADashWordIsMultiplesOfTheLineWidth;
var d: TTyDoubleArray;
begin
  { THE TWO WORDS SCALE WITH THE PEN AND THE NUMBERS DO NOT -- zrender settles
    it in one function and so does this, because the alternative is what the
    port had: the enum read at four sites, understood at none, and every
    `type: 'dashed'` drawing solid. }
  d := TyDashPattern(todDashed, nil, 1);
  AssertEquals(2, Length(d));
  AssertEquals(4.0, d[0], 1e-9);
  AssertEquals(2.0, d[1], 1e-9);
  d := TyDashPattern(todDashed, nil, 3);
  AssertEquals(12.0, d[0], 1e-9);
  AssertEquals(6.0, d[1], 1e-9);
  d := TyDashPattern(todDotted, nil, 2);
  AssertEquals('one entry means on and off alike', 1, Length(d));
  AssertEquals(2.0, d[0], 1e-9);
  d := TyDashPattern(todExplicit, TTyDoubleArray.Create(7, 3), 5);
  AssertEquals('verbatim, whatever the pen', 7.0, d[0], 1e-9);
  AssertEquals(3.0, d[1], 1e-9);
  AssertEquals('solid is no pattern', 0, Length(TyDashPattern(todSolid, nil, 2)));
  AssertEquals('and so is a pen of nothing', 0,
               Length(TyDashPattern(todDashed, nil, 0)));
end;

{ ==================== the chart ==================== }

procedure TAxisProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TAxisProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TAxisProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function TAxisProbe.AxisContent(const AHits: TTyAxisHitArray;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
begin
  Result := AxisTooltipContent(AHits, ASpec);
end;

function TAxisProbe.ValueText(AAxis: TTyAxis; AValue: Double): string;
begin
  Result := AxisValueText(AAxis, AValue, True);
end;

procedure TAdvChartAxisTriggerTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TAxisProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartAxisTriggerTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAxisTriggerTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartAxisTriggerTest.BarPoint(ACat: Integer;
  AValue: Double): TPoint;
var g: TTyGridBuild;
begin
  g := FChart.Build.Grid(0);
  Result.X := Round(g.XAxis(0).DataToCoord(ACat));
  Result.Y := Round(g.YAxis(0).DataToCoord(AValue));
end;

function TAdvChartAxisTriggerTest.InkAddedByHover(const AOption: string;
  AX, AY: Integer): Integer;
var
  cold: TBGRABitmap;
  x, y: Integer;
  a, b: PBGRAPixel;
begin
  Draw(AOption);
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    cold.PutImage(0, 0, FBmp, dmSet);
    FChart.Hover(AX, AY);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    Result := 0;
    for y := 0 to cH - 1 do
    begin
      a := cold.ScanLine[y];
      b := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green)
          or (a^.blue <> b^.blue) then Inc(Result);
        Inc(a);
        Inc(b);
      end;
    end;
  finally
    cold.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestAnAxisTriggerDrawsAPointerAndABox;
var p: TPoint;
begin
  Draw(cTwoSeries);
  { ABOVE EVERY BAR, which is the point of an axis trigger: there is no mark
    under the cursor and there is still a tooltip. An item trigger draws
    nothing here, and the test before this one in the tooltip file pins that. }
  p := BarPoint(2, 95);
  AssertTrue('a pointer and a box appeared where no mark is',
             InkAddedByHover(cTwoSeries, p.X, p.Y) > 200);
end;

procedure TAdvChartAxisTriggerTest.TestTheSectionIsHeadedByTheAxisValue;
var
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  p: TPoint;
begin
  Draw(cTwoSeries);
  p := BarPoint(2, 95);
  hits := FChart.Pointers(p.X, p.Y);
  AssertEquals('one axis', 1, Length(hits));
  block := FChart.AxisContent(hits, TyTooltipSpecDefault);
  try
    AssertTrue('there is content', block <> nil);
    { A HEADERLESS ROOT holding one section per axis -- three layers, and the
      spacing falls out of that shape rather than being written down. }
    AssertTrue('the root carries no header', block.NoHeader);
    AssertEquals('one section', 1, block.BlockCount);
    AssertEquals('headed by the category', 'C', block.Blocks[0].Header);
  finally
    block.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestEachRowIsNamedByItsSeriesNotByTheCategory;
var
  hits: TTyAxisHitArray;
  block, sec: TTyTooltipBlock;
  p: TPoint;
begin
  Draw(cTwoSeries);
  p := BarPoint(2, 95);
  hits := FChart.Pointers(p.X, p.Y);
  block := FChart.AxisContent(hits, TyTooltipSpecDefault);
  try
    sec := block.Blocks[0];
    AssertEquals('both series', 2, sec.BlockCount);
    { UPSTREAM PASSES `multipleSeries = true` HERE, which both suppresses the
      per-series header and SWITCHES the inline name from the item's to the
      series'. The category is already the section's header; repeating it on
      every row would say it once per series. }
    AssertEquals('Sales', sec.Blocks[0].Name);
    AssertEquals('60', sec.Blocks[0].Value);
    AssertEquals('Cost', sec.Blocks[1].Name);
    AssertEquals('50', sec.Blocks[1].Value);
  finally
    block.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestOnlyTheNearestSeriesReachesTheBox;
var
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  g: TTyGridBuild;
  x, y: Integer;
begin
  { TWO SERIES ON A VALUE AXIS WITH DATA IN DIFFERENT PLACES. An axis tooltip
    is NOT "every series in this column" -- upstream empties the batch the
    moment a closer series appears, so what survives is the series nearest the
    hovered value. On a category axis both are always at the same distance and
    the rule is invisible; this is the fixture where it is not. }
  Draw('{"tooltip":{"trigger":"axis"},' +
       '"xAxis":{"type":"value","min":0,"max":100},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"line","name":"Near","data":[[10,20],[12,25]]},' +
       '{"type":"line","name":"Far","data":[[80,50],[82,55]]}]}');
  g := FChart.Build.Grid(0);
  x := Round(g.XAxis(0).DataToCoord(11));
  y := Round(g.YAxis(0).DataToCoord(50));
  hits := FChart.Pointers(x, y);
  AssertEquals('one axis', 1, Length(hits));
  block := FChart.AxisContent(hits, TyTooltipSpecDefault);
  try
    AssertTrue('there is content', block <> nil);
    AssertEquals('one section', 1, block.BlockCount);
    AssertEquals('and only the near series is in it', 1,
                 block.Blocks[0].BlockCount);
    AssertEquals('Near', block.Blocks[0].Blocks[0].Name);
  finally
    block.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestACloserSeriesEvictsTheOnesAlreadyCollected;
var
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  g: TTyGridBuild;
  x, y: Integer;
begin
  { THE FAR SERIES IS DECLARED FIRST, and the order is what makes the question
    askable. Upstream EMPTIES the batch when a closer series turns up; with the
    near one declared first the far one is merely never added, the emptying
    branch is never reached, and a port that dropped it passes. }
  Draw('{"tooltip":{"trigger":"axis"},' +
       '"xAxis":{"type":"value","min":0,"max":100},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"line","name":"Far","data":[[80,50],[82,55]]},' +
       '{"type":"line","name":"Near","data":[[10,20],[12,25]]}]}');
  g := FChart.Build.Grid(0);
  x := Round(g.XAxis(0).DataToCoord(11));
  y := Round(g.YAxis(0).DataToCoord(50));
  hits := FChart.Pointers(x, y);
  block := FChart.AxisContent(hits, TyTooltipSpecDefault);
  try
    AssertTrue('there is content', block <> nil);
    AssertEquals('the far series was evicted', 1, block.Blocks[0].BlockCount);
    AssertEquals('Near', block.Blocks[0].Blocks[0].Name);
  finally
    block.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestASeriesShorterThanTheAxisDropsOut;
var
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  p: TPoint;
begin
  { WHAT THE HALF-PIXEL WINDOW IS FOR. The value has already been rounded to a
    band centre, so half a pixel means "the same band" -- and its purpose is
    exactly this: a series with fewer points than the axis has categories
    contributes NOTHING at a category it does not reach, rather than its last
    row. Without the window the nearest-row search answers row 1 for D. }
  Draw('{"tooltip":{"trigger":"axis"},' +
       '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"bar","name":"Long","data":[20,40,60,80]},' +
       '{"type":"bar","name":"Short","data":[10,30]}]}');
  p := BarPoint(3, 95);
  hits := FChart.Pointers(p.X, p.Y);
  block := FChart.AxisContent(hits, TyTooltipSpecDefault);
  try
    AssertTrue('there is content', block <> nil);
    AssertEquals('only the series that reaches D', 1,
                 block.Blocks[0].BlockCount);
    AssertEquals('Long', block.Blocks[0].Blocks[0].Name);
  finally
    block.Free;
  end;

  { AND ALONE, because with a longer series beside it the CROSS-SERIES filter
    drops the short one for a different reason -- its nearest row is further
    from the hovered value -- and the window is never the thing under test.
    One series and nowhere else for the row to come from. }
  Draw('{"tooltip":{"trigger":"axis"},' +
       '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"bar","name":"Short","data":[10,30]}]}');
  p := BarPoint(3, 95);
  hits := FChart.Pointers(p.X, p.Y);
  AssertEquals('the axis is still pointed at', 1, Length(hits));
  AssertEquals('and nothing was found on it', 0, Length(hits[0].Slots));
  block := FChart.AxisContent(hits, TyTooltipSpecDefault);
  try
    AssertTrue('so there is no box at all', block = nil);
  finally
    block.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestACrossStillMakesOneSection;
var
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  p: TPoint;
begin
  Draw('{"tooltip":{"trigger":"axis","axisPointer":{"type":"cross"}},' +
       '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}');
  p := BarPoint(2, 50);
  hits := FChart.Pointers(p.X, p.Y);
  AssertEquals('two arms', 2, Length(hits));
  block := FChart.AxisContent(hits, TyTooltipSpecDefault);
  try
    { TWO POINTERS, ONE TOOLTIP. Upstream hard-codes the other arm's
      triggerTooltip to false, which is why a cross does not report the value
      axis as a second section. }
    AssertEquals('one section', 1, block.BlockCount);
  finally
    block.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestShowContentFalseKeepsThePointerAndDropsTheBox;
var p: TPoint; withBox, pointerOnly: Integer; opt, base: string;
begin
  { THE ONE CONFIGURATION THAT ISOLATES THE POINTER. `showContent: false` hides
    the box and keeps the axisPointer, so what is drawn is the line and nothing
    else -- and a test that only ever measured the two together could not say
    which of them had stopped appearing. }
  { EMPHASIS OFF IN BOTH, so the comparison is pointer against pointer-plus-
    box. An axis trigger also LIGHTS UP every row it describes, and leaving
    that in would put the same highlight on both sides of a ratio meant to
    isolate the box. }
  base := '{"tooltip":{"trigger":"axis"},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","emphasis":{"disabled":true},' +
    '"data":[20,40,60,80]},{"type":"bar","name":"Cost",' +
    '"emphasis":{"disabled":true},"data":[10,30,50,70]}]}';
  Draw(base);
  p := BarPoint(2, 95);
  withBox := InkAddedByHover(base, p.X, p.Y);
  opt := '{"tooltip":{"trigger":"axis","showContent":false},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","emphasis":{"disabled":true},' +
    '"data":[20,40,60,80]},{"type":"bar","name":"Cost",' +
    '"emphasis":{"disabled":true},"data":[10,30,50,70]}]}';
  pointerOnly := InkAddedByHover(opt, p.X, p.Y);
  AssertTrue('the pointer is still drawn', pointerOnly > 20);
  AssertTrue('and it is a fraction of the pointer plus the box',
             pointerOnly < withBox div 2);
end;

procedure TAdvChartAxisTriggerTest.TestAModelChangeTakesThePointerAway;
var
  p: TPoint;
  cold: TBGRABitmap;
  x, y, diff: Integer;
  a, b: PBGRAPixel;
begin
  { THE OTHER WAY A HOVER ENDS. MouseLeave clears it and so does Invalidate --
    and the second matters more, because the hits hold AXIS POINTERS into a
    build that a rebuild is about to free. }
  Draw(cTwoSeries);
  p := BarPoint(2, 95);
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    cold.PutImage(0, 0, FBmp, dmSet);
    FChart.Hover(p.X, p.Y);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    FChart.Invalidate;
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    diff := 0;
    for y := 0 to cH - 1 do
    begin
      a := cold.ScanLine[y];
      b := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green)
          or (a^.blue <> b^.blue) then Inc(diff);
        Inc(a);
        Inc(b);
      end;
    end;
    AssertEquals('a rebuilt chart has no pointer on it', 0, diff);
  finally
    cold.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestThePointerLabelRoundsToTheScalesPrecision;
var g: TTyGridBuild;
begin
  { `precision: 'auto'` IS THE SCALE'S INTERVAL PRECISION, not "every digit the
    number happens to have". An axis ticking in twenties labels its pointer 37;
    without the rounding it labels it 37.246964, which is true and useless. }
  Draw('{"tooltip":{"trigger":"axis"},' +
       '"xAxis":{"type":"value","min":0,"max":100},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"line","name":"S","data":[[10,20],[50,60]]}]}');
  g := FChart.Build.Grid(0);
  AssertEquals('37', FChart.ValueText(g.YAxis(0), 37.246964));
  AssertEquals('and the grouping survives it', '1,234',
               FChart.ValueText(g.YAxis(0), 1234.4));
end;

procedure TAdvChartAxisTriggerTest.TestOrderReordersTheRowsWithinTheSection;
var
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  spec: TTyTooltipSpec;
  p: TPoint;
begin
  Draw(cTwoSeries);
  p := BarPoint(2, 95);
  hits := FChart.Pointers(p.X, p.Y);
  spec := TyTooltipSpecDefault;
  spec.HasOrder := True;
  spec.Order := ttoValueAsc;
  block := FChart.AxisContent(hits, spec);
  try
    { Sales is 60 and Cost is 50, so ascending puts Cost first. `order` sorts
      the rows WITHIN a section and nothing else -- never axes, never
      coordinate systems -- and it runs after the sections are reversed. }
    AssertEquals('Cost', block.Blocks[0].Blocks[0].Name);
    AssertEquals('Sales', block.Blocks[0].Blocks[1].Name);
  finally
    block.Free;
  end;
  spec.Order := ttoValueDesc;
  block := FChart.AxisContent(hits, spec);
  try
    AssertEquals('Sales', block.Blocks[0].Blocks[0].Name);
  finally
    block.Free;
  end;
end;

procedure TAdvChartAxisTriggerTest.TestACrossPutsAPointerOnBothAxes;
var hits: TTyAxisHitArray; p: TPoint;
begin
  Draw('{"tooltip":{"trigger":"axis","axisPointer":{"type":"cross"}},' +
       '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}');
  p := BarPoint(2, 50);
  hits := FChart.Pointers(p.X, p.Y);
  AssertEquals('both arms', 2, Length(hits));
  { CROSS IS NOT A SHAPE -- it is two axes each drawing a line, which is why
    there is no cross builder anywhere upstream. }
  AssertTrue('the base arm is a line', hits[0].Spec.PointerType = aptLine);
  AssertTrue('and so is the other', hits[1].Spec.PointerType = aptLine);
  AssertFalse('the base arm triggers the tooltip', hits[0].Cross);
  AssertTrue('the other one never does', hits[1].Cross);
end;

procedure TAdvChartAxisTriggerTest.TestACrossDrawsEvenWithoutAnAxisTrigger;
var hits: TTyAxisHitArray; p: TPoint;
begin
  { Upstream's gate is `triggerAxis || cross`, and the second disjunct is the
    only reason the commonest way of writing this -- an axisPointer with no
    trigger beside it -- draws anything at all. }
  Draw('{"tooltip":{"axisPointer":{"type":"cross"}},' +
       '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}');
  p := BarPoint(2, 50);
  hits := FChart.Pointers(p.X, p.Y);
  AssertEquals('both arms, with no trigger written', 2, Length(hits));
end;

procedure TAdvChartAxisTriggerTest.TestAShadowNeedsACategoryAxis;
var hits: TTyAxisHitArray; p: TPoint; g: TTyGridBuild;
begin
  Draw('{"tooltip":{"trigger":"axis","axisPointer":{"type":"shadow"}},' +
       '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}');
  p := BarPoint(2, 50);
  hits := FChart.Pointers(p.X, p.Y);
  AssertEquals(1, Length(hits));
  AssertTrue('a shadow was asked for', hits[0].Spec.PointerType = aptShadow);
  AssertTrue('and a category axis has a band to draw',
             hits[0].Axis.BandWidth > 0);

  { A VALUE AXIS HAS NO BAND, and this port does not invent one. Upstream
    derives it from a statistics pass over the hovered series' smallest
    positive gap; without that pass the honest answer is no band rather than
    the one-pixel sliver the missing number would produce. A RECORDED
    RESTRICTION, and this is where it is recorded. }
  Draw('{"tooltip":{"trigger":"axis","axisPointer":{"type":"shadow"}},' +
       '"xAxis":{"type":"value","min":0,"max":100},' +
       '"yAxis":{"type":"value","min":0,"max":100},' +
       '"series":[{"type":"line","name":"S","data":[[10,20],[50,60]]}]}');
  g := FChart.Build.Grid(0);
  p.X := Round(g.XAxis(0).DataToCoord(10));
  p.Y := Round(g.YAxis(0).DataToCoord(20));
  hits := FChart.Pointers(p.X, p.Y);
  AssertEquals(1, Length(hits));
  AssertEquals('no band on a value axis', 0.0, hits[0].Axis.BandWidth, 1e-9);
end;

procedure TAdvChartAxisTriggerTest.TestLeavingTheChartTakesThePointerAway;
var
  p: TPoint;
  cold: TBGRABitmap;
  x, y, diff: Integer;
  a, b: PBGRAPixel;
begin
  Draw(cTwoSeries);
  p := BarPoint(2, 95);
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    cold.PutImage(0, 0, FBmp, dmSet);
    FChart.Hover(p.X, p.Y);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    FChart.MouseLeave;
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    diff := 0;
    for y := 0 to cH - 1 do
    begin
      a := cold.ScanLine[y];
      b := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green)
          or (a^.blue <> b^.blue) then Inc(diff);
        Inc(a);
        Inc(b);
      end;
    end;
    AssertEquals('the pointer left no trace', 0, diff);
  finally
    cold.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartAxisPointerRuleTest);
  RegisterTest(TAdvChartAxisTriggerTest);
end.
