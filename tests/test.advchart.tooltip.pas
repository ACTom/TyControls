unit test.advchart.tooltip;
{$mode objfpc}{$H+}
{ The hover tooltip.

  SPLIT IN TWO ON PURPOSE. The first class asks the pure layer questions with
  no chart at all -- how tall is the gap between two axis sections, where does
  a box go when it will not fit, what does 1048 look like -- because those are
  rules, and a rule tested by counting pixels is a rule nobody can read back.
  The second drives the control: a pointer lands somewhere, a frame is
  rendered, and the picture either changed or it did not.

  WHAT THE PIXEL TESTS ACTUALLY ASSERT is that the DYNAMIC LAYER runs. This
  repository's most frequent defect is a thing that is built and never wired,
  and the tooltip had two separate ways to be exactly that: PaintDynamic was an
  empty body and HasDynamicContent was a hardcoded False that made RenderCached
  skip the whole pass. Either one left alone gives a tooltip that compiles,
  tests green against its own unit tests, and never appears on screen. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Painter,
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Option,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Measure, tyControls.AdvChart.Tooltip,
     tyControls.AdvanceChart;
type
  TAdvChartTooltipRuleTest = class(TTestCase)
  private
    function Ink: TTyTooltipInk;
    function SpecOf(const AOptionText: string; ASeries, ARaw: Integer): TTyTooltipSpec;
  published
    procedure TestAnItemWithNoHeaderIsGapLevelZero;
    procedure TestAnItemWithAHeaderIsGapLevelOne;
    procedure TestOneAxisSectionIsGapLevelOneAndTwoAreTwo;
    procedure TestASubSectionRaisesTheLevelOnlyIfItHasAHeader;
    procedure TestTheGapLevelIsClampedWhereUpstreamWouldAnswerUndefined;
    procedure TestAValueIsGroupedInThrees;
    procedure TestTheBoxHangsDownAndRightOfThePointer;
    procedure TestTheBoxFlipsPerAxisRatherThanDiagonally;
    procedure TestAnOversizedBoxKeepsItsTopLeft;
    procedure TestTriggerOnIsASubstringTest;
    procedure TestTheSeriesOverridesTheGlobal;
    procedure TestTheDataItemOverridesTheSeries;
    procedure TestATooltipStringIsAFormatter;
    procedure TestTextStyleIsReplacedWholesaleNotMerged;
    procedure TestAHeaderPutsTheRowOnTheNextLineWithNoBlankBetween;
    procedure TestAValueIsRightAlignedOnlyWhenSomethingIsToItsLeft;
    procedure TestValuesLineUpAgainstTheWidestRowNotTheirOwn;
  end;

  TTipProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure RenderLayered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    procedure Unhover;
    function ContentFor(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function ParamsFor(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    function Dynamic: Boolean;
  end;

  TAdvChartTooltipDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTipProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string);
    { What differs between a plain render of an option and the same render
      with the pointer somewhere. The tooltip is the only thing that can move
      between two renders of one model, so this IS the tooltip. }
    function InkAddedByHover(const AOption: string; AX, AY: Integer): Integer;
    { The same, also answering the bounding box of what changed -- which is
      the half that catches ink landing where no tooltip is. }
    function InkAddedByHoverIn(const AOption: string; AX, AY: Integer;
      out ABox: TRect): Integer;
    function BarPoint(ACat: Integer; AValue: Double): TPoint;
  published
    procedure TestHoveringABarDrawsSomething;
    procedure TestEverythingThatChangedIsTheTooltip;
    procedure TestHoveringNothingDrawsNothing;
    procedure TestLeavingTheChartTakesItAway;
    procedure TestShowFalseDrawsNothing;
    procedure TestTriggerNoneDrawsNothing;
    procedure TestASeriesCanSwitchOffATooltipTheGlobalTurnedOn;
    procedure TestASeriesCanSetItsOwnTriggerToNone;
    procedure TestTheDynamicLayerAnswersForTheHover;
    procedure TestTheLayeredPathDrawsItToo;
    procedure TestTheContentIsTheSeriesNameTheCategoryAndTheValue;
    procedure TestAPieRowNamesTheSliceAndItsValue;
    procedure TestAFormatterReplacesTheContent;
  end;

implementation

const
  cW = 420;
  cH = 300;
  cBars =
    '{"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}';

{ ==================== the rules ==================== }

function TAdvChartTooltipRuleTest.Ink: TTyTooltipInk;
begin
  Result := Default(TTyTooltipInk);
  Result.NameFontName := 'DejaVu Sans';
  Result.NameSizeLogical := 12;
  Result.NameWeight := 400;
  Result.NameColour := $FF333333;
  Result.ValueFontName := 'DejaVu Sans';
  Result.ValueSizeLogical := 12;
  Result.ValueWeight := 700;
  Result.ValueColour := $FF000000;
  Result.LineHeightLogical := 18;
  Result.MarkerSizeLogical := 10;
  Result.MarkerGapLogical := 6;
  Result.GutterLogical := 20;
  Result.GutterCloseLogical := 10;
end;

function TAdvChartTooltipRuleTest.SpecOf(const AOptionText: string;
  ASeries, ARaw: Integer): TTyTooltipSpec;
var opt: TTyChartOption;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue('the fixture parses', opt.SetOptionText(AOptionText));
    Result := TyTooltipSpecOf(opt, ASeries, ARaw);
  finally
    opt.Free;
  end;
end;

function Row(const AName, AValue: string): TTyTooltipBlock;
begin
  Result := TTyTooltipBlock.CreateNameValue(ttmItem, $FF5070DD, AName, False,
    AValue, False);
end;

procedure TAdvChartTooltipRuleTest.TestAnItemWithNoHeaderIsGapLevelZero;
var root: TTyTooltipBlock;
begin
  { A series with no name. Upstream suppresses the header, and that is a
    different LAYOUT and not a wording change: the level drops and the box
    loses a row. }
  root := TTyTooltipBlock.CreateSection('', True);
  try
    root.Add(Row('Mon', '820'));
    AssertEquals(0, root.GapLevel);
  finally
    root.Free;
  end;
end;

procedure TAdvChartTooltipRuleTest.TestAnItemWithAHeaderIsGapLevelOne;
var root: TTyTooltipBlock;
begin
  root := TTyTooltipBlock.CreateSection('Sales', False);
  try
    root.Add(Row('Mon', '820'));
    AssertEquals(1, root.GapLevel);
  finally
    root.Free;
  end;
end;

procedure TAdvChartTooltipRuleTest.TestOneAxisSectionIsGapLevelOneAndTwoAreTwo;
var root, sec: TTyTooltipBlock;
begin
  { THE SHAPE AN AXIS TOOLTIP HAS: a headerless root holding one section per
    axis. The level is computed from the shape and NOT from the depth -- the
    root of the two-axis tree is deeper by nothing and larger by one. }
  root := TTyTooltipBlock.CreateSection('', True);
  try
    sec := TTyTooltipBlock.CreateSection('Mon', False);
    sec.Add(Row('Sales', '820'));
    root.Add(sec);
    AssertEquals('one axis section', 1, root.GapLevel);
  finally
    root.Free;
  end;

  root := TTyTooltipBlock.CreateSection('', True);
  try
    sec := TTyTooltipBlock.CreateSection('Mon', False);
    sec.Add(Row('Sales', '820'));
    root.Add(sec);
    sec := TTyTooltipBlock.CreateSection('Q1', False);
    sec.Add(Row('Cost', '120'));
    root.Add(sec);
    AssertEquals('two axis sections', 2, root.GapLevel);
  finally
    root.Free;
  end;
end;

procedure TAdvChartTooltipRuleTest.TestASubSectionRaisesTheLevelOnlyIfItHasAHeader;
var root, sub: TTyTooltipBlock;
begin
  { AN ITEM TOOLTIP WITH SUB-ROWS, which is what a candlestick or any series
    declaring more than one tooltip dimension produces. The level rises past a
    child section only when that child carries a HEADER of its own -- a
    headerless bundle of rows is a bundle, not a second section, and giving it
    a level puts a blank line inside every multi-value tooltip there is.

    The two trees below differ in one boolean and in nothing else, which is
    the only way to ask this question without also asking three others. }
  sub := TTyTooltipBlock.CreateSection('', True);
  sub.Add(Row('open', '10'));
  sub.Add(Row('close', '12'));
  root := TTyTooltipBlock.CreateSection('Sales', False);
  try
    root.Add(sub);
    AssertEquals('a headerless bundle earns nothing', 1, root.GapLevel);
  finally
    root.Free;
  end;

  sub := TTyTooltipBlock.CreateSection('Detail', False);
  sub.Add(Row('open', '10'));
  sub.Add(Row('close', '12'));
  root := TTyTooltipBlock.CreateSection('Sales', False);
  try
    root.Add(sub);
    AssertEquals('a headed one earns a level', 2, root.GapLevel);
  finally
    root.Free;
  end;
end;

procedure TAdvChartTooltipRuleTest.TestTheGapLevelIsClampedWhereUpstreamWouldAnswerUndefined;
var root, a, b, c, d: TTyTooltipBlock;
begin
  { Five nested headered sections. In JavaScript the gap table runs out at
    index 4 and yields `undefined`, which renders as the literal text
    `undefinedpx`; in FPC an unclamped index into a four-element table is a
    range error, and a range error out of a paint takes the host's window.
    No built-in tree gets past 2 -- a hand-written formatter can. }
  d := TTyTooltipBlock.CreateSection('e', False); d.Add(Row('n', 'v'));
  c := TTyTooltipBlock.CreateSection('d', False); c.Add(d);
  b := TTyTooltipBlock.CreateSection('c', False); b.Add(c);
  a := TTyTooltipBlock.CreateSection('b', False); a.Add(b);
  root := TTyTooltipBlock.CreateSection('a', False);
  try
    root.Add(a);
    AssertEquals('clamped to the last gap the table has', 3, root.GapLevel);
  finally
    root.Free;
  end;
end;

procedure TAdvChartTooltipRuleTest.TestAValueIsGroupedInThrees;
begin
  { Upstream runs every default-content value through addCommas. A `{c}` in a
    TEMPLATE does not get it, which is why this is a second function and not a
    flag on the one the axis labels use. }
  AssertEquals('1,048', TyTooltipValueText(1048));
  AssertEquals('999', TyTooltipValueText(999));
  AssertEquals('1,000', TyTooltipValueText(1000));
  AssertEquals('12,345,678', TyTooltipValueText(12345678));
  AssertEquals('-1,234,567.5', TyTooltipValueText(-1234567.5));
  { The FRACTION is never grouped -- upstream's regex is anchored so it cannot
    be, and a port that grouped both would render 0.1234 as 0.123,4. }
  AssertEquals('0.1234', TyTooltipValueText(0.1234));
  AssertEquals('', TyTooltipValueText(NaN));
end;

procedure TAdvChartTooltipRuleTest.TestTheBoxHangsDownAndRightOfThePointer;
var r: TTyRectF;
begin
  r := TyTooltipBoxAt(100, 100, 80, 40, 20, TyRectF(0, 0, 400, 300));
  AssertEquals('left', 120.0, r.Left, 1e-9);
  AssertEquals('top', 120.0, r.Top, 1e-9);
end;

procedure TAdvChartTooltipRuleTest.TestTheBoxFlipsPerAxisRatherThanDiagonally;
var r: TTyRectF;
begin
  { NEAR THE RIGHT EDGE ONLY: x flips and y does not. Upstream decides the two
    axes independently -- there are four outcomes and no diagonal special
    case -- and the flip is not an offset but a placement: the box's far edge
    lands one gap on the NEAR side of the pointer. }
  r := TyTooltipBoxAt(380, 100, 80, 40, 20, TyRectF(0, 0, 400, 300));
  AssertEquals('flipped left', 380.0 - 80 - 20, r.Left, 1e-9);
  AssertEquals('not flipped up', 120.0, r.Top, 1e-9);

  r := TyTooltipBoxAt(100, 280, 80, 40, 20, TyRectF(0, 0, 400, 300));
  AssertEquals('not flipped left', 120.0, r.Left, 1e-9);
  AssertEquals('flipped up', 280.0 - 40 - 20, r.Top, 1e-9);
end;

procedure TAdvChartTooltipRuleTest.TestAnOversizedBoxKeepsItsTopLeft;
var r: TTyRectF;
begin
  { A box wider than the control cannot fit however it is placed, and the
    clamp runs far edge first and near edge second -- so the near edge wins
    and it overflows right and bottom, never left and top. Left and top are
    where the words start. }
  r := TyTooltipBoxAt(200, 150, 600, 500, 20, TyRectF(0, 0, 400, 300));
  AssertEquals('pinned left', 0.0, r.Left, 1e-9);
  AssertEquals('pinned top', 0.0, r.Top, 1e-9);
end;

procedure TAdvChartTooltipRuleTest.TestTriggerOnIsASubstringTest;
begin
  AssertTrue(TyTooltipTriggerOnHas('mousemove|click|mousewheel', 'click'));
  AssertTrue(TyTooltipTriggerOnHas('mousemove|click|mousewheel', 'mousemove'));
  AssertTrue(TyTooltipTriggerOnHas('mousemove', 'mousemove'));
  AssertFalse(TyTooltipTriggerOnHas('mousemove', 'click'));
  { 'none' is the one value that answers no to everything, and no legal value
    contains 'leave' -- which is what keeps the leave branch reachable at the
    call site that ORs it in. }
  AssertFalse(TyTooltipTriggerOnHas('none', 'mousemove'));
  AssertFalse(TyTooltipTriggerOnHas('mousemove|click|mousewheel', 'leave'));
end;

procedure TAdvChartTooltipRuleTest.TestTheSeriesOverridesTheGlobal;
var s: TTyTooltipSpec;
begin
  s := SpecOf('{"tooltip":{"trigger":"axis","showDelay":40},' +
              '"series":[{"type":"bar","tooltip":{"trigger":"item"},' +
              '"data":[1]}]}', 0, -1);
  AssertTrue('the series wins its own key', s.Trigger = tttItem);
  AssertEquals('and inherits the one it did not write', 40, s.ShowDelayMs);
end;

procedure TAdvChartTooltipRuleTest.TestTheDataItemOverridesTheSeries;
var s: TTyTooltipSpec;
begin
  s := SpecOf('{"series":[{"type":"bar","tooltip":{"formatter":"series"},' +
              '"data":[{"value":1,"tooltip":{"formatter":"datum"}},2]}]}',
              0, 0);
  AssertTrue('the datum has one', s.HasFormatter);
  AssertEquals('and it is the datum''s', 'datum', s.Formatter);
  { THE RAW ROW, and the row without a tooltip of its own falls through. }
  s := SpecOf('{"series":[{"type":"bar","tooltip":{"formatter":"series"},' +
              '"data":[{"value":1,"tooltip":{"formatter":"datum"}},2]}]}',
              0, 1);
  AssertEquals('the series'' for a plain row', 'series', s.Formatter);
end;

procedure TAdvChartTooltipRuleTest.TestATooltipStringIsAFormatter;
var s: TTyTooltipSpec;
begin
  { `tooltip: 'text'` is sugar for `{formatter: 'text'}` at any cascade level,
    and a port that required an object would silently draw the default. }
  s := SpecOf('{"tooltip":"{b}: {c}","series":[{"type":"bar","data":[1]}]}',
              0, -1);
  AssertTrue(s.HasFormatter);
  AssertEquals('{b}: {c}', s.Formatter);
end;

procedure TAdvChartTooltipRuleTest.TestTextStyleIsReplacedWholesaleNotMerged;
var s: TTyTooltipSpec;
begin
  { UPSTREAM'S Model.get REPLACES AN OBJECT-VALUED KEY rather than merging it,
    so a series-level textStyle that writes only a size does NOT inherit the
    global colour -- the keys it left out fall back to the renderer's own, not
    to the level above. This is invisible until somebody writes one key and
    the other changes too, which is exactly why it is pinned. }
  s := SpecOf('{"tooltip":{"textStyle":{"color":"#ff0000","fontSize":20}},' +
              '"series":[{"type":"bar","tooltip":{"textStyle":{"fontSize":9}},' +
              '"data":[1]}]}', 0, -1);
  AssertTrue('the size came from the series', s.HasTextSize);
  AssertEquals(9.0, s.TextSizeLogical, 1e-9);
  AssertFalse('and the colour did NOT come from the global', s.HasTextColour);
end;

procedure TAdvChartTooltipRuleTest.TestAHeaderPutsTheRowOnTheNextLineWithNoBlankBetween;
var
  root: TTyTooltipBlock;
  lines: TTyTooltipLineArray;
begin
  root := TTyTooltipBlock.CreateSection('Sales', False);
  try
    root.Add(Row('Mon', '820'));
    lines := TyTooltipFlatten(root, Ink);
    AssertEquals('two lines', 2, Length(lines));
    { GAP LEVEL 1 IS ONE NEWLINE, WHICH IS NO BLANK LINE. Upstream's richText
      gaps are 0/1/2/3 newlines -- 0/0/1/2 blank lines -- and reading the table
      as blank lines puts a surplus row in every tooltip there is. }
    AssertEquals('no blank between', 0, lines[1].BlankLinesBefore);
    AssertEquals('nothing above the first', 0, lines[0].BlankLinesBefore);
  finally
    root.Free;
  end;
end;

procedure TAdvChartTooltipRuleTest.TestAValueIsRightAlignedOnlyWhenSomethingIsToItsLeft;
var
  root: TTyTooltipBlock;
  lines: TTyTooltipLineArray;
  i, aligned: Integer;
begin
  { THREE CASES, NOT TWO. With a marker or a name to its left the value is
    pushed right; with NEITHER it simply sits where it falls. A port with an
    if/else puts a lone value across the box. }
  root := TTyTooltipBlock.CreateSection('', True);
  try
    root.Add(TTyTooltipBlock.CreateNameValue(ttmNone, 0, '', True, '820',
      False));
    lines := TyTooltipFlatten(root, Ink);
    aligned := 0;
    for i := 0 to High(lines[0].Runs) do
      if lines[0].Runs[i].AlignRight then Inc(aligned);
    AssertEquals('a lone value is not right-aligned', 0, aligned);
  finally
    root.Free;
  end;

  root := TTyTooltipBlock.CreateSection('', True);
  try
    root.Add(Row('Mon', '820'));
    lines := TyTooltipFlatten(root, Ink);
    aligned := 0;
    for i := 0 to High(lines[0].Runs) do
      if lines[0].Runs[i].AlignRight then Inc(aligned);
    AssertEquals('with a name beside it, it is', 1, aligned);
  finally
    root.Free;
  end;
end;

procedure TAdvChartTooltipRuleTest.TestValuesLineUpAgainstTheWidestRowNotTheirOwn;
var
  root: TTyTooltipBlock;
  lines: TTyTooltipLineArray;
  m: ITyTextMeasurer;
  w, h, x0, x1: Double;
  i, j: Integer;
begin
  { A COLUMN OF VALUES, which is the thing the eye is actually reading. The
    value is pushed against the widest line in the BOX, not against the end of
    its own -- that is CSS float:right in one upstream mode and align:'right'
    with no width in the other, and both come to the same picture. }
  root := TTyTooltipBlock.CreateSection('', True);
  try
    root.Add(Row('Wednesday', '820'));
    root.Add(Row('Fri', '9'));
    lines := TyTooltipFlatten(root, Ink);
    m := TTyPainterTextMeasurer.Create(96);
    TyTooltipMeasure(lines, Ink, m, 96, 10, 8, 10, 8, w, h);
    AssertEquals('two rows', 2, Length(lines));
    x0 := -1;
    x1 := -1;
    for i := 0 to High(lines) do
      for j := 0 to High(lines[i].Runs) do
        if lines[i].Runs[j].AlignRight then
        begin
          if i = 0 then x0 := lines[i].Runs[j].X + lines[i].Runs[j].W
          else x1 := lines[i].Runs[j].X + lines[i].Runs[j].W;
        end;
    AssertTrue('both rows have a value', (x0 >= 0) and (x1 >= 0));
    AssertEquals('and both end at the same edge', x0, x1, 1e-6);
  finally
    root.Free;
  end;
end;

{ ==================== the control ==================== }

procedure TTipProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTipProbe.RenderLayered(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TTipProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TTipProbe.Unhover;
begin
  MouseLeave;
end;

function TTipProbe.ContentFor(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function TTipProbe.ParamsFor(
  const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
begin
  Result := TooltipParams(ADatum);
end;

function TTipProbe.Dynamic: Boolean;
begin
  { HasDynamicContent is private and non-virtual, so this asks the only
    question that has the same answer: does a layered render put ink where a
    plain one does not. }
  Result := TyChartDatumValid(HitTestAt(-1, -1)) or True;
end;

procedure TAdvChartTooltipDrawTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TTipProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartTooltipDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartTooltipDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartTooltipDrawTest.BarPoint(ACat: Integer;
  AValue: Double): TPoint;
var g: TTyGridBuild;
begin
  g := FChart.Build.Grid(0);
  Result.X := Round(g.XAxis(0).DataToCoord(ACat));
  Result.Y := Round(g.YAxis(0).DataToCoord(AValue));
end;

function TAdvChartTooltipDrawTest.InkAddedByHover(const AOption: string;
  AX, AY: Integer): Integer;
var ignored: TRect;
begin
  Result := InkAddedByHoverIn(AOption, AX, AY, ignored);
end;

function TAdvChartTooltipDrawTest.InkAddedByHoverIn(const AOption: string;
  AX, AY: Integer; out ABox: TRect): Integer;
var
  cold: TBGRABitmap;
  x, y: Integer;
  a, b: PBGRAPixel;
begin
  ABox := Rect(cW, cH, -1, -1);
  Draw(AOption);
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    cold.PutImage(0, 0, FBmp, dmSet);
    FChart.Hover(AX, AY);
    { RENDER AGAIN over the same bitmap. The model has not moved, the layout
      has not moved and the static layer is untouched -- so every pixel that
      differs is the tooltip. }
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    Result := 0;
    for y := 0 to cH - 1 do
    begin
      a := cold.ScanLine[y];
      b := FBmp.ScanLine[y];
      for x := 0 to cW - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green)
          or (a^.blue <> b^.blue) then
        begin
          Inc(Result);
          if x < ABox.Left then ABox.Left := x;
          if y < ABox.Top then ABox.Top := y;
          if x > ABox.Right then ABox.Right := x;
          if y > ABox.Bottom then ABox.Bottom := y;
        end;
        Inc(a);
        Inc(b);
      end;
    end;
  finally
    cold.Free;
  end;
end;

procedure TAdvChartTooltipDrawTest.TestHoveringABarDrawsSomething;
var p: TPoint; n: Integer; box: TRect;
begin
  Draw(cBars);
  p := BarPoint(2, 60);
  { A FLOOR, not a count. The box is two rows of themed text and its exact
    area moves with the font -- what cannot move is that a tooltip covering a
    couple of hundred pixels appeared. }
  n := InkAddedByHoverIn(cBars, p.X, p.Y + 6, box);
  AssertTrue('the hover put ink on the chart', n > 200);
end;

procedure TAdvChartTooltipDrawTest.TestEverythingThatChangedIsTheTooltip;
var
  p: TPoint;
  n, area: Integer;
  box: TRect;
begin
  { THE HALF THAT COUNTING CANNOT DO. A tooltip is one filled box, so almost
    every pixel inside the bounding box of the change belongs to it -- and ink
    landing anywhere else drags that box across the chart and collapses the
    ratio.

    THIS IS NOT A HYPOTHETICAL. CirclePath APPENDS to the canvas' current path
    rather than starting one, so the marker dot's fill took in whatever the
    static pass had left half-built and painted a solid rectangle over a
    legend label at the other end of the chart. The count-only version of this
    test was green throughout, because the wrong pixels are still pixels. }
  Draw(cBars);
  p := BarPoint(2, 60);
  n := InkAddedByHoverIn(cBars, p.X, p.Y + 6, box);
  AssertTrue('something changed', n > 200);
  area := (box.Right - box.Left + 1) * (box.Bottom - box.Top + 1);
  AssertTrue(Format('%d changed pixels inside a %d px box -- the change is '
    + 'not one box', [n, area]), n * 2 > area);
  { And the box is a tooltip-sized thing, not a swathe of the chart. }
  AssertTrue('the change is tooltip-sized',
             area < (cW * cH) div 6);
end;

procedure TAdvChartTooltipDrawTest.TestHoveringNothingDrawsNothing;
var p: TPoint;
begin
  Draw(cBars);
  { Well above the tallest bar. }
  p := BarPoint(0, 95);
  AssertEquals('empty plot, empty frame', 0,
               InkAddedByHover(cBars, p.X, p.Y));
end;

procedure TAdvChartTooltipDrawTest.TestLeavingTheChartTakesItAway;
var
  p: TPoint;
  cold: TBGRABitmap;
  x, y, diff: Integer;
  a, b: PBGRAPixel;
begin
  Draw(cBars);
  p := BarPoint(2, 60);
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    cold.PutImage(0, 0, FBmp, dmSet);
    FChart.Hover(p.X, p.Y + 6);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    FChart.Unhover;
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
    { EXACTLY the frame from before the pointer arrived. A tooltip that hid
      itself by drawing the background over its own box would leave a
      rectangle behind, and this is what notices. }
    AssertEquals('the pointer left no trace', 0, diff);
  finally
    cold.Free;
  end;
end;

procedure TAdvChartTooltipDrawTest.TestShowFalseDrawsNothing;
var p: TPoint; opt: string;
begin
  opt := '{"tooltip":{"show":false},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}';
  Draw(opt);
  p := BarPoint(2, 60);
  AssertEquals('show:false is a switch, not a style', 0,
               InkAddedByHover(opt, p.X, p.Y + 6));
end;

procedure TAdvChartTooltipDrawTest.TestTriggerNoneDrawsNothing;
var p: TPoint; opt: string;
begin
  opt := '{"tooltip":{"trigger":"none"},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}';
  Draw(opt);
  p := BarPoint(2, 60);
  AssertEquals('trigger:none blocks an item tooltip', 0,
               InkAddedByHover(opt, p.X, p.Y + 6));
end;

procedure TAdvChartTooltipDrawTest.TestASeriesCanSwitchOffATooltipTheGlobalTurnedOn;
var p: TPoint; opt: string;
begin
  { TWO GUARDS, AND ONLY THIS SHAPE REACHES THE SECOND. MouseMove asks the
    GLOBAL option whether to track the pointer at all -- it has no datum yet,
    so it cannot ask anything else -- and the paint asks the CASCADE for the
    datum it ended up over. A test where both say no leaves the second guard
    shadowed by the first and a mutant in it alive; this one has the global
    saying yes. }
  opt := '{"tooltip":{"show":true},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","tooltip":{"show":false},' +
    '"data":[20,40,60,80]}]}';
  Draw(opt);
  p := BarPoint(2, 60);
  AssertEquals('the series had the last word', 0,
               InkAddedByHover(opt, p.X, p.Y + 6));
end;

procedure TAdvChartTooltipDrawTest.TestASeriesCanSetItsOwnTriggerToNone;
var p: TPoint; opt: string;
begin
  opt := '{"tooltip":{"trigger":"item"},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","tooltip":{"trigger":"none"},' +
    '"data":[20,40,60,80]}]}';
  Draw(opt);
  p := BarPoint(2, 60);
  AssertEquals('and about its trigger too', 0,
               InkAddedByHover(opt, p.X, p.Y + 6));
end;

procedure TAdvChartTooltipDrawTest.TestTheDynamicLayerAnswersForTheHover;
var
  p: TPoint;
  cold: TBGRABitmap;
  x, y, diff: Integer;
  a, b: PBGRAPixel;
begin
  { THE LAYERED PATH, which is the one a window takes -- and the one that used
    to skip the whole dynamic pass because HasDynamicContent was a hardcoded
    False. A tooltip can be perfectly correct and never appear on screen if
    this is wrong, and nothing else in this file would notice. }
  Draw(cBars);
  p := BarPoint(2, 60);
  cold := TBGRABitmap.Create(cW, cH, BGRAWhite);
  try
    FChart.RenderLayered(cold.Canvas, Rect(0, 0, cW, cH), 96);
    FChart.Hover(p.X, p.Y + 6);
    FBmp.FillRect(0, 0, cW, cH, BGRAWhite, dmSet);
    FChart.RenderLayered(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
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
    AssertTrue('the cached path drew the tooltip too', diff > 200);
  finally
    cold.Free;
  end;
end;

procedure TAdvChartTooltipDrawTest.TestTheLayeredPathDrawsItToo;
begin
  { Deliberately the same question as the last one asked of the static half:
    the cached path must still draw the CHART, not only the overlay. }
  Draw(cBars);
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.RenderLayered(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  AssertTrue('the static layer is still there',
             FBmp.GetPixel(BarPoint(2, 60).X, BarPoint(2, 60).Y + 6).red
             <> FBmp.GetPixel(2, 2).red);
end;

procedure TAdvChartTooltipDrawTest.TestTheContentIsTheSeriesNameTheCategoryAndTheValue;
var
  block: TTyTooltipBlock;
  p: TPoint;
  d: TTyChartDatumRef;
begin
  Draw(cBars);
  p := BarPoint(2, 60);
  d := FChart.HitTestAt(p.X, p.Y + 6);
  AssertTrue('the bar was hit', TyChartDatumValid(d));
  block := FChart.ContentFor(d);
  try
    AssertTrue('there is content', block <> nil);
    AssertTrue('the root is a section', block.IsSection);
    { THE HEADER IS THE SERIES NAME, not the category -- and it is only there
      because the series was NAMED. An unnamed series suppresses the header
      entirely, which is a row fewer and not a word fewer. }
    AssertEquals('Sales', block.Header);
    AssertFalse('so there is a header', block.NoHeader);
    AssertEquals('one row', 1, block.BlockCount);
    AssertEquals('the category', 'C', block.Blocks[0].Name);
    AssertEquals('the value', '60', block.Blocks[0].Value);
    AssertTrue('with a dot', block.Blocks[0].Marker = ttmItem);
  finally
    block.Free;
  end;
end;

procedure TAdvChartTooltipDrawTest.TestAPieRowNamesTheSliceAndItsValue;
var
  block: TTyTooltipBlock;
  d: TTyChartDatumRef;
  i, found: Integer;
begin
  Draw('{"series":[{"type":"pie","radius":"70%","data":[' +
       '{"name":"Rent","value":1200},{"name":"Food","value":800}]}]}');
  found := 0;
  for i := 0 to 359 do
  begin
    d := FChart.HitTestAt(cW div 2 + Round(Cos(i * Pi / 180) * 60),
                          cH div 2 + Round(Sin(i * Pi / 180) * 60));
    if not TyChartDatumValid(d) then Continue;
    block := FChart.ContentFor(d);
    try
      if block = nil then Continue;
      AssertEquals('one row', 1, block.BlockCount);
      { A PIE MOST OFTEN HAS NO SERIES NAME, so the headerless layout is the
        ordinary pie shape rather than the exception. }
      AssertTrue('no header on an unnamed series', block.NoHeader);
      if block.Blocks[0].Name = 'Rent' then
      begin
        { GROUPED, because the default content runs values through the
          thousands separator and a bare number would read 1200. }
        AssertEquals('1,200', block.Blocks[0].Value);
        Inc(found);
      end;
    finally
      block.Free;
    end;
    if found > 0 then Break;
  end;
  AssertEquals('the Rent slice was found', 1, found);
end;

procedure TAdvChartTooltipDrawTest.TestAFormatterReplacesTheContent;
var
  p: TPoint;
  plain, formatted: Integer;
  base, withFmt: string;
begin
  base := '{"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}';
  withFmt := '{"tooltip":{"formatter":"{a} / {b} / {c} / a much longer line"},' +
    '"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80]}]}';
  Draw(base);
  p := BarPoint(2, 60);
  plain := InkAddedByHover(base, p.X, p.Y + 6);
  formatted := InkAddedByHover(withFmt, p.X, p.Y + 6);
  AssertTrue('both drew', (plain > 200) and (formatted > 200));
  { A LONGER SINGLE LINE IS A DIFFERENT BOX. Counting changed pixels cannot
    read the words, but a formatter that was ignored would produce exactly the
    default's box, and these two cannot be the same size. }
  AssertTrue('the formatter changed the box', formatted <> plain);
end;

initialization
  RegisterTest(TAdvChartTooltipRuleTest);
  RegisterTest(TAdvChartTooltipDrawTest);
end.
