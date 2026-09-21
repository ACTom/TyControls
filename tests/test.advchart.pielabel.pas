unit test.advchart.pielabel;
{$mode objfpc}{$H+}
{ Where a pie slice's label goes.

  A DIFFERENT ALGORITHM FROM EVERY OTHER SERIES, which is the first thing to
  know about it: pie/labelLayout computes x, y and rotation itself, so none of
  the thirteen generic positions apply and two of the generic options are dead
  -- though not the two a reasonable reading would pick.

  The five that a reasonable reading gets wrong, all upstream's:

    - only `inside` and `inner` are inside. EVERY other value, including one
      nobody recognises and including the generic anchors like `top`, falls
      through to the OUTER placement;
    - `center` is not an inside label. It takes the OUTSIDE ink, because a
      centred donut label sits on the hole rather than on the ring;
    - the guide line exists only for the literal words `outer` and `outside`,
      so `position: 'top'` places a label out past the rim with nothing
      pointing at it;
    - there is a fixed three-pixel nudge along the slice's own normal that no
      option controls and nothing documents;
    - the elbow sits on a circle of radius r + length where r is the SERIES
      radius, not the slice's -- which is what keeps a rose chart's labels in
      a column instead of following its spikes. }
interface
uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Labels,
  tyControls.AdvChart.Data, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Series,
  tyControls.AdvChart.Pie, tyControls.AdvChart.PieLabel;

type
  TPieLabelMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

type
  TAdvChartPieLabelTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure SetUp; override;
    procedure TearDown; override;
    function SpecOf(const AText: string): TTyPieLabelSpec;
    { A quarter-slice pointing due right (angles 0..Pi/2 would point down-right;
      this one is centred on the +x axis), on a ring 60..100 centred at
      (200, 150), in a 400x300 view. }
    function Layout: TTyPieLayout;
    function Slice(AStart, AEnd: Double): TTyPieSector;
    { A two-slice pie with names, laid out and ready to label. }
    function TwoSliceLayout: TTyPieLayout;
  published
    procedure TestOnlyInsideAndInnerAreInside;
    procedure TestCentreIsTheCentreAndNothingElse;
    procedure TestAnInsideLabelSitsOnTheRingPlusTheNudge;
    procedure TestTheOuterElbowSitsOnTheSeriesRadiusNotTheSlices;
    procedure TestTheSecondSegmentIsHorizontal;
    procedure TestTheSideIsDecidedByTheCosineOfTheMidAngle;
    procedure TestTheLineIsOnlyForTheLiteralOuterWords;
    procedure TestANarrowSliceShowsNothing;
    procedure TestTheOptionIsActuallyRead;
    procedure TestRotationFollowsTheTable;
    procedure TestBleedMarginIsComputedNotConstant;
    procedure TestOffsetReachesAPieLabelEvenThoughDistanceDoesNot;
    procedure TestTheLeftHandSideMirrorsEveryHorizontalTerm;
    procedure TestTheNudgeScalesWithTheDisplay;
    procedure TestAnInvalidSliceIsSkippedEvenWhenItIsWideEnough;
    { ---- the builder ---- }
    procedure TestABuiltPieLabelSaysItsNameAndAnswersForItsRow;
    procedure TestOnlyAnInsideLabelTakesTheContrastInk;
    procedure TestTheGuideLineIsSilentAndInTheSlicesOwnColour;
  end;

implementation

const
  Eps = 1e-9;
  CX = 200.0;
  CY = 150.0;
  R0 = 60.0;
  R1 = 100.0;
  Nudge = 3.0;

procedure TAdvChartPieLabelTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
end;

procedure TAdvChartPieLabelTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartPieLabelTest.SpecOf(const AText: string): TTyPieLabelSpec;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message,
    FOpt.SetOptionText(AText));
  Result := TyPieLabelSpecOf(FOpt, 0, TyPieLabelSpecDefault);
end;

function TAdvChartPieLabelTest.Layout: TTyPieLayout;
begin
  Result := Default(TTyPieLayout);
  Result.Valid := True;
  Result.ViewRect := TyRectF(0, 0, 400, 300);
  Result.CX := CX;
  Result.CY := CY;
  Result.R0 := R0;
  Result.R1 := R1;
end;

function TAdvChartPieLabelTest.Slice(AStart, AEnd: Double): TTyPieSector;
begin
  Result := Default(TTyPieSector);
  Result.Valid := True;
  { BOTH ROW SPACES. A layout built by hand here stands for one whose store
    was never filtered, so the two agree -- but they have to be SET to agree,
    and a fixture that sets only one describes a pie that could not exist. }
  Result.RawIndex := 0;
  Result.Index := 0;
  Result.CX := CX;
  Result.CY := CY;
  Result.R0 := R0;
  Result.R1 := R1;
  Result.StartRad := AStart;
  Result.EndRad := AEnd;
end;

procedure TAdvChartPieLabelTest.TestOnlyInsideAndInnerAreInside;
begin
  { Two exact string tests and an else -- not a table. So the generic anchors
    the type surface accepts all take the OUTER path, and so does a typo. }
  AssertEquals('inside', Ord(tplInside),
    Ord(SpecOf('{ "series": [ { "type": "pie", "label":'
      + ' { "position": "inside" } } ] }').Position));
  AssertEquals('inner is the same thing', Ord(tplInside),
    Ord(SpecOf('{ "series": [ { "type": "pie", "label":'
      + ' { "position": "inner" } } ] }').Position));
  AssertEquals('center is its own case', Ord(tplCentre),
    Ord(SpecOf('{ "series": [ { "type": "pie", "label":'
      + ' { "position": "center" } } ] }').Position));
  AssertEquals('a generic anchor falls through to outer', Ord(tplOuter),
    Ord(SpecOf('{ "series": [ { "type": "pie", "label":'
      + ' { "position": "top" } } ] }').Position));
  AssertEquals('and so does a name nobody knows', Ord(tplOuter),
    Ord(SpecOf('{ "series": [ { "type": "pie", "label":'
      + ' { "position": "nonsense" } } ] }').Position));
  AssertEquals('the default is outer', Ord(tplOuter),
    Ord(TyPieLabelSpecDefault.Position));
end;

procedure TAdvChartPieLabelTest.TestCentreIsTheCentreAndNothingElse;
var
  spec: TTyPieLabelSpec;
  p: TTyPieLabelPlacement;
begin
  spec := TyPieLabelSpecDefault;
  spec.Position := tplCentre;
  spec.PositionWord := 'center';
  p := TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96);
  AssertTrue('placed', p.Valid);
  AssertEquals('the pie''s own centre', CX, p.X, Eps);
  AssertEquals('', CY, p.Y, Eps);
  AssertEquals('centred', Ord(tahCentre), Ord(p.AnchorH));
  AssertFalse('and no line, whatever labelLine says', p.HasLine);

  { NO NUDGE. The three-pixel push along the normal is computed on the other
    branch; a centre label never reaches it. }
  spec.Position := tplCentre;
  p := TyPlacePieLabel(spec, Layout, Slice(Pi, Pi * 1.5), 96);
  AssertEquals('the same point for every slice', CX, p.X, Eps);
  AssertEquals('', CY, p.Y, Eps);
end;

procedure TAdvChartPieLabelTest.TestAnInsideLabelSitsOnTheRingPlusTheNudge;
var
  spec: TTyPieLabelSpec;
  p: TTyPieLabelPlacement;
begin
  { The MIDDLE of the ring -- (r + r0) / 2 -- and then three pixels further out
    along the same ray. The nudge is controlled by no option and explained
    nowhere upstream; a port that placed the label at the ring midpoint is
    three pixels off on every slice. }
  spec := TyPieLabelSpecDefault;
  spec.Position := tplInside;
  spec.PositionWord := 'inside';
  { A slice centred on the +x axis: mid-angle 0, so cos = 1 and sin = 0. }
  p := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  AssertTrue('placed', p.Valid);
  AssertEquals('mid-ring plus the nudge', CX + (R1 + R0) / 2 + Nudge, p.X, Eps);
  AssertEquals('level with the centre', CY, p.Y, Eps);
  AssertEquals('centred on the anchor', Ord(tahCentre), Ord(p.AnchorH));
  AssertEquals('and always middle-aligned', Ord(tavMiddle), Ord(p.AnchorV));
  AssertFalse('an inside label has no line', p.HasLine);
end;

procedure TAdvChartPieLabelTest.TestTheOuterElbowSitsOnTheSeriesRadiusNotTheSlices;
var
  spec: TTyPieLabelSpec;
  p: TTyPieLabelPlacement;
  short_: TTyPieSector;
begin
  { THE ROSE COMPENSATION. The elbow is x1 + nx * (length + seriesR - sliceR),
    which puts it on a circle of radius seriesR + length for EVERY slice --
    even one whose own radius is shorter. Drop the two extra terms and a rose
    chart's labels follow its spikes instead of forming a column. }
  spec := TyPieLabelSpecDefault;
  spec.LineLength := TyBoxPx(15);
  p := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  AssertTrue('placed', p.Valid);
  AssertTrue('there is a line', p.HasLine);
  AssertEquals('the line starts on the slice''s own rim', CX + R1, p.P1.X, Eps);
  AssertEquals('and the elbow a length further out', CX + R1 + 15, p.P2.X, Eps);

  { A SHORTER SLICE, as roseType makes: its line starts closer in and ENDS in
    the same place. }
  short_ := Slice(-Pi / 4, Pi / 4);
  short_.R1 := 70;
  p := TyPlacePieLabel(spec, Layout, short_, 96);
  AssertEquals('a short slice starts closer in', CX + 70, p.P1.X, Eps);
  AssertEquals('and its elbow lands on the same circle', CX + R1 + 15,
    p.P2.X, Eps);
end;

procedure TAdvChartPieLabelTest.TestTheSecondSegmentIsHorizontal;
var
  spec: TTyPieLabelSpec;
  p: TTyPieLabelPlacement;
begin
  { y3 is COPIED from y2 rather than computed along the normal. That is what
    levels the tails and lets a column of labels line up; computing it would
    fan them out along their own rays. }
  spec := TyPieLabelSpecDefault;
  spec.LineLength := TyBoxPx(15);
  spec.LineLength2 := TyBoxPx(30);
  p := TyPlacePieLabel(spec, Layout, Slice(Pi / 6, Pi / 3), 96);
  AssertTrue('there is a line', p.HasLine);
  AssertEquals('the tail is level with the elbow', p.P2.Y, p.P3.Y, Eps);
  AssertEquals('and length2 long', p.P2.X + 30, p.P3.X, Eps);
  AssertTrue('while the elbow is NOT level with the start',
    Abs(p.P1.Y - p.P2.Y) > 1);
end;

procedure TAdvChartPieLabelTest.TestTheSideIsDecidedByTheCosineOfTheMidAngle;
var
  spec: TTyPieLabelSpec;
  right_, left_: TTyPieLabelPlacement;
begin
  { The side comes from the sign of cos(midAngle) -- the slice's own direction
    -- and NOT from comparing the label's x against the centre. The two agree
    here and stop agreeing once an overlap solver has moved anything. }
  spec := TyPieLabelSpecDefault;
  right_ := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  left_ := TyPlacePieLabel(spec, Layout, Slice(Pi * 0.75, Pi * 1.25), 96);

  AssertTrue('the right-hand label is right of centre', right_.X > CX);
  AssertEquals('and hangs to the right of its anchor', Ord(tahLeft),
    Ord(right_.AnchorH));
  AssertTrue('the left-hand one is left of centre', left_.X < CX);
  AssertEquals('and hangs to the left', Ord(tahRight), Ord(left_.AnchorH));

  { alignTo: edge pins the text to the view rect instead, and flips the
    alignment -- the words then hang INWARD from the edge. }
  spec.AlignTo := tpaEdge;
  spec.EdgeDistance := TyBoxPx(20);
  right_ := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  AssertEquals('flush to the right edge', 400.0 - 20.0, right_.X, Eps);
  AssertEquals('and hanging back inward', Ord(tahRight), Ord(right_.AnchorH));
end;

procedure TAdvChartPieLabelTest.TestTheLineIsOnlyForTheLiteralOuterWords;
var spec: TTyPieLabelSpec;
begin
  { PieView removes the guide line unless the position is literally `outer` or
    `outside`, while labelLayout still computes the outer anchor for every
    other value. So `position: 'top'` puts a pie label out past the rim with
    nothing pointing at it -- which looks like a bug and is upstream's. }
  spec := TyPieLabelSpecDefault;
  spec.PositionWord := 'outer';
  AssertTrue('outer has a line',
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).HasLine);
  spec.PositionWord := 'outside';
  AssertTrue('and so does outside',
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).HasLine);
  spec.PositionWord := 'top';
  AssertFalse('but top does not, though it is placed the same way',
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).HasLine);

  { And labelLine.show switches off the ones that would have had it. }
  spec.PositionWord := 'outer';
  spec.ShowLine := False;
  AssertFalse('switched off',
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).HasLine);
end;

procedure TAdvChartPieLabelTest.TestANarrowSliceShowsNothing;
var spec: TTyPieLabelSpec;
begin
  { minShowLabelAngle hides the words AND the line, and it is measured on the
    DRAWN sweep -- which padAngle has already eaten into. }
  spec := TyPieLabelSpecDefault;
  spec.MinShowLabelDeg := 10;
  AssertFalse('a five-degree slice is too narrow',
    TyPlacePieLabel(spec, Layout, Slice(0, 5 * Pi / 180), 96).Valid);
  AssertTrue('a fifteen-degree one is not',
    TyPlacePieLabel(spec, Layout, Slice(0, 15 * Pi / 180), 96).Valid);

  { And an invalid slice is skipped whatever its angles say. }
  AssertFalse('a gap has no label',
    TyPlacePieLabel(spec, Layout, Default(TTyPieSector), 96).Valid);
end;

procedure TAdvChartPieLabelTest.TestTheOptionIsActuallyRead;
var spec: TTyPieLabelSpec;
begin
  spec := SpecOf('{ "series": [ { "type": "pie", "minShowLabelAngle": 4,'
    + ' "label": { "show": true, "position": "inner", "alignTo": "edge",'
    + ' "rotate": 30, "distanceToLabelLine": 9, "edgeDistance": "10%",'
    + ' "bleedMargin": 7, "formatter": "{b}", "overflow": "none" },'
    + ' "labelLine": { "show": false, "length": 20, "length2": 40 } } ] }');
  AssertTrue('show', spec.Show);
  AssertEquals('position', Ord(tplInside), Ord(spec.Position));
  AssertEquals('the word is kept too', 'inner', spec.PositionWord);
  AssertEquals('alignTo', Ord(tpaEdge), Ord(spec.AlignTo));
  AssertEquals('rotate is a number of degrees', Ord(tprNumber),
    Ord(spec.Rotate));
  AssertEquals('', 30.0, spec.RotateDeg, Eps);
  AssertEquals('distanceToLabelLine', 9.0, spec.DistanceToLineLogical, Eps);
  AssertEquals('bleedMargin', 7.0, spec.BleedMargin, Eps);
  AssertEquals('formatter', '{b}', spec.Formatter);
  AssertEquals('overflow', Ord(tloNone), Ord(spec.Overflow));
  AssertFalse('labelLine.show', spec.ShowLine);
  AssertEquals('length', 20.0, spec.LineLength.Value, Eps);
  AssertEquals('length2', 40.0, spec.LineLength2.Value, Eps);
  AssertEquals('minShowLabelAngle is on the SERIES, not the label', 4.0,
    spec.MinShowLabelDeg, Eps);

  { PIE OVERRIDES THE SHARED OVERFLOW DEFAULT. The generic node is `none`; a
    pie's own defaultOption sets `truncate`, and pie is the one series type
    whose labels routinely run past the view. The catalog records the generic
    value for both. }
  AssertEquals('truncate by default', Ord(tloTruncate),
    Ord(TyPieLabelSpecDefault.Overflow));
  { And `edgeDistance` is a percentage OF THE VIEW WIDTH -- not of the radius
    and not of the shorter side, which is what the radius uses. }
  AssertEquals('a tenth of a 400-wide view', 40.0,
    TyPieResolve(spec.EdgeDistance, 400), Eps);
end;

procedure TAdvChartPieLabelTest.TestRotationFollowsTheTable;
var
  spec: TTyPieLabelSpec;
  p: TTyPieLabelPlacement;
begin
  spec := TyPieLabelSpecDefault;

  { A number is degrees. }
  spec.Rotate := tprNumber;
  spec.RotateDeg := 45;
  AssertEquals('degrees to radians', Pi / 4,
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).RotationRad, Eps);

  { `center` forces zero, and it is tested BEFORE the word cases -- but AFTER
    the numeric one, so an explicit number still rotates a centre label. }
  spec.Position := tplCentre;
  spec.PositionWord := 'center';
  AssertEquals('a number still turns a centre label', Pi / 4,
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).RotationRad, Eps);
  spec.Rotate := tprRadial;
  AssertEquals('but radial does not', 0.0,
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).RotationRad, Eps);

  { radial: the negated mid-angle, flipped by Pi on the left half so the words
    never read upside down. }
  spec.Position := tplOuter;
  spec.PositionWord := 'outer';
  spec.Rotate := tprRadial;
  p := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  AssertEquals('on the right, the negated mid-angle', 0.0, p.RotationRad, Eps);
  p := TyPlacePieLabel(spec, Layout, Slice(Pi * 0.75, Pi * 1.25), 96);
  AssertEquals('on the left, half a turn further', -Pi + Pi, p.RotationRad, Eps);

  { TRANSCRIBED WITH ITS PRECEDENCE BUG. Upstream meant the position guard to
    cover both tangential spellings; `&&` binds tighter than `||`, so it covers
    only `tangential-noflip`. Plain `tangential` therefore rotates an OUTER
    label, where tangential rotation makes no sense. }
  spec.Rotate := tprTangential;
  AssertTrue('plain tangential turns an outer label anyway',
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).RotationRad <> 0);
  spec.Rotate := tprTangentialNoFlip;
  AssertEquals('while noflip leaves it alone', 0.0,
    TyPlacePieLabel(spec, Layout, Slice(0, Pi / 2), 96).RotationRad, Eps);
end;

procedure TAdvChartPieLabelTest.TestBleedMarginIsComputedNotConstant;
begin
  { The catalog says the default is ten. The source leaves it unset on purpose
    -- the line is commented out with its reason -- and works it out from the
    view rect. The small case is not hypothetical: it is exactly what a pie
    nested in a calendar or matrix cell gets. }
  AssertEquals('a normal chart', 10.0,
    TyPieBleedMargin(TyRectF(0, 0, 400, 300)), Eps);
  AssertEquals('a small one', 2.0,
    TyPieBleedMargin(TyRectF(0, 0, 180, 180)), Eps);
  { The test is on the SHORTER side, strictly greater. }
  AssertEquals('exactly two hundred is still small', 2.0,
    TyPieBleedMargin(TyRectF(0, 0, 900, 200)), Eps);
  AssertEquals('one more is not', 10.0,
    TyPieBleedMargin(TyRectF(0, 0, 900, 201)), Eps);
end;

procedure TAdvChartPieLabelTest.TestOffsetReachesAPieLabelEvenThoughDistanceDoesNot;
var
  spec: TTyPieLabelSpec;
  plain, moved: TTyPieLabelPlacement;
begin
  { TWO OPTIONS THAT LOOK EQUALLY DISCARDED AND ARE NOT. PieView resets only
    `position` and `rotation`, and the reset MERGES -- so both survive into
    zrender. `distance` is then read only inside the gate the null position
    closes; `offset` is applied outside it. An earlier note in this repository
    said both were dead, and an audit against the source found otherwise. }
  spec := TyPieLabelSpecDefault;
  spec.Position := tplInside;
  spec.PositionWord := 'inside';
  plain := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  spec.OffsetXLogical := 11;
  spec.OffsetYLogical := -4;
  moved := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  AssertEquals('offset across', plain.X + 11, moved.X, Eps);
  AssertEquals('and up', plain.Y - 4, moved.Y, Eps);

  { LOGICAL px, so it scales with the display -- measured as the DIFFERENCE
    at one density rather than against the other density's answer, because the
    three-pixel nudge scales too and comparing across the two would be reading
    both scalings at once. }
  spec.OffsetXLogical := 0;
  spec.OffsetYLogical := 0;
  plain := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 192);
  spec.OffsetXLogical := 11;
  spec.OffsetYLogical := -4;
  moved := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 192);
  AssertEquals('the offset itself doubled', plain.X + 22, moved.X, 0.001);
  AssertEquals('both ways', plain.Y - 8, moved.Y, 0.001);

  { AND `distance` IS NOT READ. Its field is not even on the spec -- the only
    spacing a pie label has is distanceToLabelLine, which moves the words away
    from the END OF THE LINE rather than away from the slice. }
  spec.OffsetXLogical := 0;
  spec.OffsetYLogical := 0;
  spec.Position := tplOuter;
  spec.PositionWord := 'outer';
  plain := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  spec.DistanceToLineLogical := spec.DistanceToLineLogical + 10;
  moved := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  AssertEquals('ten further from the line end', plain.X + 10, moved.X, Eps);
  AssertEquals('and the line itself is where it was', plain.P3.X, moved.P3.X,
    Eps);
end;

procedure TPieLabelMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := Length(AText) * 10;
  AH := 12;
end;

function TPieLabelMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

function TAdvChartPieLabelTest.TwoSliceLayout: TTyPieLayout;
begin
  Result := Layout;
  SetLength(Result.Sectors, 2);
  { One pointing right, one pointing left -- so every horizontal term in the
    placement is exercised in both directions by the same fixture. }
  Result.Sectors[0] := Slice(-Pi / 4, Pi / 4);
  Result.Sectors[0].RawIndex := 0;
  Result.Sectors[0].Index := 0;
  Result.Sectors[1] := Slice(Pi * 0.75, Pi * 1.25);
  Result.Sectors[1].RawIndex := 1;
  Result.Sectors[1].Index := 1;
end;

procedure TAdvChartPieLabelTest.TestTheLeftHandSideMirrorsEveryHorizontalTerm;
var
  spec: TTyPieLabelSpec;
  p: TTyPieLabelPlacement;
begin
  { EVERY SLICE IN THE TESTS ABOVE POINTS RIGHT, and on the right every one of
    these terms is added -- so a version that dropped the sign entirely drew
    the same picture. The left half is where a sign is a sign. }
  spec := TyPieLabelSpecDefault;
  spec.LineLength := TyBoxPx(15);
  spec.LineLength2 := TyBoxPx(30);
  spec.DistanceToLineLogical := 5;
  p := TyPlacePieLabel(spec, Layout, Slice(Pi * 0.75, Pi * 1.25), 96);
  AssertTrue('placed', p.Valid);
  AssertEquals('the elbow is left of the rim', CX - R1 - 15, p.P2.X, Eps);
  AssertEquals('and the tail runs further LEFT, not right', p.P2.X - 30,
    p.P3.X, Eps);
  AssertEquals('the words sit a distance further left again', p.P3.X - 5,
    p.X, Eps);
  AssertEquals('hanging to the left of their anchor', Ord(tahRight),
    Ord(p.AnchorH));
end;

procedure TAdvChartPieLabelTest.TestTheNudgeScalesWithTheDisplay;
var
  spec: TTyPieLabelSpec;
  at96, at192: TTyPieLabelPlacement;
begin
  { The three-pixel push is a LOGICAL three, like every other fixed number in
    this library -- upstream has no density to scale it by, and its canvas
    transform would have doubled it anyway. Measured on an inside label with
    no offset, where the nudge is the only term that can move. }
  spec := TyPieLabelSpecDefault;
  spec.Position := tplInside;
  spec.PositionWord := 'inside';
  at96 := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 96);
  at192 := TyPlacePieLabel(spec, Layout, Slice(-Pi / 4, Pi / 4), 192);
  AssertEquals('three at one density', CX + (R1 + R0) / 2 + 3, at96.X, Eps);
  AssertEquals('six at twice it', CX + (R1 + R0) / 2 + 6, at192.X, Eps);
end;

procedure TAdvChartPieLabelTest.TestAnInvalidSliceIsSkippedEvenWhenItIsWideEnough;
var
  spec: TTyPieLabelSpec;
  gap: TTyPieSector;
begin
  { A GAP IS NOT A NARROW SLICE, and the earlier test could not tell them
    apart: the invalid sector it tried had a sweep of zero, so the
    minShowLabelAngle guard fired first and the validity guard was never
    reached. A NaN datum on an ordinary pie keeps the ring's own radius and
    only goes NaN under roseType -- so validity, not the radius, is the test. }
  spec := TyPieLabelSpecDefault;
  spec.MinShowLabelDeg := 0;
  gap := Slice(-Pi / 4, Pi / 4);
  AssertTrue('the same slice, valid, is labelled',
    TyPlacePieLabel(spec, Layout, gap, 96).Valid);
  gap.Valid := False;
  AssertFalse('and invalid it is not, though it is just as wide',
    TyPlacePieLabel(spec, Layout, gap, 96).Valid);
end;

{ ============================ the builder ============================ }

procedure TAdvChartPieLabelTest.TestABuiltPieLabelSaysItsNameAndAnswersForItsRow;
var
  list: TTyPaintList;
  store: TTyDataStore;
  bind: TTySeriesBinding;
  ink: TTyPieLabelInk;
  spec: TTyPieLabelSpec;
  m: ITyTextMeasurer;
  i, captions: Integer;
  el: TTyChartElement;
begin
  { A PIE SAYS ITS NAME. Upstream falls back to the datum's name where a bar
    falls back to its number, and one default for both renders every
    unformatted pie label as a figure. }
  list := TTyPaintList.Create;
  store := TTyDataStore.Create;
  m := TPieLabelMeasurer.Create;
  try
    store.AddDimension('value', ddtFloat);
    store.AppendRow([30.0]);
    store.AppendRow([70.0]);
    store.SetName(0, 'Rent');
    store.SetName(1, 'Food');
    bind := Default(TTySeriesBinding);
    bind.Resolved := True;
    bind.SeriesIndex := 2;
    ink := Default(TTyPieLabelInk);
    ink.FontName := 'x';
    ink.FontSizeLogical := 9;
    ink.FontWeight := 400;
    ink.OutsideColour := $FF445566;
    spec := TyPieLabelSpecDefault;

    AssertTrue('something was added',
      TyBuildPieLabels(bind, TwoSliceLayout, spec, ink, [$FF000000],
        store, '', 0, 2, m, 96, list) > 0);

    captions := 0;
    for i := 0 to list.Count - 1 do
    begin
      el := list.Element(i);
      if el.Caption.Text = '' then Continue;
      Inc(captions);
      AssertEquals('every caption answers for this series', 2,
        el.Datum.SeriesIndex);
      AssertFalse('and is not silent', el.Silent);
    end;
    AssertEquals('one caption per slice', 2, captions);

    { The words, and the row each belongs to. }
    for i := 0 to list.Count - 1 do
    begin
      el := list.Element(i);
      if el.Caption.Text = 'Rent' then
        AssertEquals('Rent is row 0', 0, el.Datum.DataIndex)
      else if el.Caption.Text = 'Food' then
        AssertEquals('Food is row 1', 1, el.Datum.DataIndex);
    end;

    { A formatter overrides the name. }
    list.Clear;
    spec.Formatter := '{b}!';
    spec.HasFormatter := True;
    TyBuildPieLabels(bind, TwoSliceLayout, spec, ink, [$FF000000],
      store, '', 0, 2, m, 96, list);
    captions := 0;
    for i := 0 to list.Count - 1 do
      if list.Element(i).Caption.Text = 'Rent!' then Inc(captions);
    AssertEquals('the template ran', 1, captions);
  finally
    m := nil;
    store.Free;
    list.Free;
  end;
end;

procedure TAdvChartPieLabelTest.TestOnlyAnInsideLabelTakesTheContrastInk;

  function InkOf(APosition: TTyPieLabelPosition;
    const AWord: string): TTyChartColor;
  var
    list: TTyPaintList;
    store: TTyDataStore;
    bind: TTySeriesBinding;
    ink: TTyPieLabelInk;
    spec: TTyPieLabelSpec;
    m: ITyTextMeasurer;
    i: Integer;
  begin
    Result := 0;
    list := TTyPaintList.Create;
    store := TTyDataStore.Create;
    m := TPieLabelMeasurer.Create;
    try
      store.AddDimension('value', ddtFloat);
      store.AppendRow([30.0]);
      store.AppendRow([70.0]);
      store.SetName(0, 'a');
      store.SetName(1, 'b');
      bind := Default(TTySeriesBinding);
      bind.Resolved := True;
      ink := Default(TTyPieLabelInk);
      ink.FontName := 'x';
      ink.FontSizeLogical := 9;
      ink.FontWeight := 400;
      ink.InsideColour[0] := $FF111111;
      ink.InsideColour[1] := $FF222222;
      ink.InsideColour[2] := $FF333333;
      ink.OutsideColour := $FF445566;
      spec := TyPieLabelSpecDefault;
      spec.Position := APosition;
      spec.PositionWord := AWord;
      { A near-black slice, so the contrast rule answers the third band and
        cannot be confused with the outside ink. }
      TyBuildPieLabels(bind, TwoSliceLayout, spec, ink, [$FF000000],
        store, '', 0, 2, m, 96, list);
      for i := 0 to list.Count - 1 do
        if list.Element(i).Caption.Text <> '' then
          Exit(list.Element(i).Caption.Colour);
    finally
      m := nil;
      store.Free;
      list.Free;
    end;
  end;

begin
  { `center` IS NOT AN INSIDE LABEL, which is the surprise here: a centred
    donut label sits on the HOLE rather than on the ring, so upstream marks it
    not-inside and it takes the theme ink like an outer one. Only `inside` and
    `inner` get the contrast rule. }
  AssertEquals('inside takes the dark-slice band', $FF333333,
    InkOf(tplInside, 'inside'));
  AssertEquals('outer takes the theme ink', $FF445566,
    InkOf(tplOuter, 'outer'));
  AssertEquals('and so does centre, though it is inside the circle',
    $FF445566, InkOf(tplCentre, 'center'));
end;

procedure TAdvChartPieLabelTest.TestTheGuideLineIsSilentAndInTheSlicesOwnColour;
var
  list: TTyPaintList;
  store: TTyDataStore;
  bind: TTySeriesBinding;
  ink: TTyPieLabelInk;
  spec: TTyPieLabelSpec;
  m: ITyTextMeasurer;
  i, lines: Integer;
  el: TTyChartElement;
begin
  list := TTyPaintList.Create;
  store := TTyDataStore.Create;
  m := TPieLabelMeasurer.Create;
  try
    store.AddDimension('value', ddtFloat);
    store.AppendRow([30.0]);
    store.AppendRow([70.0]);
    store.SetName(0, 'a');
    store.SetName(1, 'b');
    bind := Default(TTySeriesBinding);
    bind.Resolved := True;
    ink := Default(TTyPieLabelInk);
    ink.FontName := 'x';
    ink.FontSizeLogical := 9;
    ink.FontWeight := 400;
    ink.OutsideColour := $FF445566;
    ink.LineWidthLogical := 1;
    spec := TyPieLabelSpecDefault;
    TyBuildPieLabels(bind, TwoSliceLayout, spec, ink, [$FF00FF00, $FF0000FF],
      store, '', 0, 2, m, 96, list);

    lines := 0;
    for i := 0 to list.Count - 1 do
    begin
      el := list.Element(i);
      if el.Shape.Kind <> cskPolyline then Continue;
      Inc(lines);
      { SILENT. A leader is a pointer at the slice, not a target of its own --
        a hit on it would report the datum a second time from a place the eye
        does not read as the datum. }
      AssertTrue('the leader takes no hovers', el.Silent);
      AssertTrue('and is stroked, not filled', el.Style.StrokeWidthLogical > 0);
    end;
    AssertEquals('one leader per slice', 2, lines);

    { AN EMPTY LABEL KEEPS ITS LINE. `formatter: ''` is an empty text, not
      no label, and upstream still draws the leader that points at it. }
    list.Clear;
    spec.Formatter := '';
    spec.HasFormatter := True;
    TyBuildPieLabels(bind, TwoSliceLayout, spec, ink, [$FF00FF00, $FF0000FF],
      store, '', 0, 2, m, 96, list);
    lines := 0;
    for i := 0 to list.Count - 1 do
      if list.Element(i).Shape.Kind = cskPolyline then Inc(lines);
    AssertEquals('an empty label still has its leader', 2, lines);
    for i := 0 to list.Count - 1 do
      AssertEquals('and no words', '', list.Element(i).Caption.Text);
    spec := TyPieLabelSpecDefault;
    list.Clear;
    TyBuildPieLabels(bind, TwoSliceLayout, spec, ink, [$FF00FF00, $FF0000FF],
      store, '', 0, 2, m, 96, list);

    { IN THE SLICE'S OWN COLOUR, and the two slices have different ones -- so
      a version that used one colour for every leader is visible here and
      nowhere else. }
    for i := 0 to list.Count - 1 do
    begin
      el := list.Element(i);
      if el.Shape.Kind <> cskPolyline then Continue;
      AssertTrue('a leader is green or blue, not the theme ink',
        (el.Style.StrokeColor = $FF00FF00)
        or (el.Style.StrokeColor = $FF0000FF));
    end;
  finally
    m := nil;
    store.Free;
    list.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartPieLabelTest);
end.
