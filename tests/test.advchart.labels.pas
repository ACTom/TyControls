unit test.advchart.labels;
{$mode objfpc}{$H+}
{ Words on a mark: where they go, what they say, what colour they come out.

  THE POSITION TABLE IS THIRTEEN ROWS AND EVERY ONE IS ASSERTED, because the
  table is the whole feature and a wrong row is invisible until somebody uses
  that position. Each row asserts BOTH answers -- the anchor and which edge of
  the text is pinned to it -- since they are different questions and getting the
  second wrong puts every outside label on top of the mark it names.

  The four that a reasonable reading gets wrong, all upstream's:

    - an UNKNOWN position name is not `inside`. zrender's switch has no default
      case, so it lands at the host's top-left;
    - `distance` does nothing at all in the default position, which is `inside`;
    - the ARRAY form pins the caption's TOP-LEFT rather than centring it, so
      ['50%','50%'] is not the same picture as `inside` even though the anchor
      is the same point;
    - the inside colour is a THREE-band table by luminance, and the middle band
      is the LIGHTEST of the three. }
interface
uses tyControls.FontUnits,
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Labels,
  tyControls.AdvChart.LabelOpt;

type
  TLabelMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartLabelsTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FStore: TTyDataStore;
    FList: TTyPaintList;
    FM: ITyTextMeasurer;
    procedure SetUp; override;
    procedure TearDown; override;
    { The anchor and the pinned edge for one position on a 100x40 host at
      (10, 20), with a distance of 5. }
    procedure At(APosition: TTyLabelPosition; out AX, AY: Double;
      out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
    function SpecOf(const AText: string): TTyLabelSpec;
  published
    procedure TestTheFourOutsidePositions;
    procedure TestTheNineInsidePositions;
    procedure TestDistanceDoesNothingInTheDefaultPosition;
    procedure TestAnUnknownNameIsNotTheDefault;
    procedure TestOutsideIsNotAPositionButARequestForOne;
    procedure TestTheArrayFormPinsTheTopLeft;
    procedure TestLuminanceCountsAlphaAsDarkness;
    procedure TestTheInsideInkIsThreeBandsNotTwo;
    procedure TestTheBandBoundaryIsStrictlyGreater;
    procedure TestAnOutsideLabelIgnoresWhatItIsLabelling;
    procedure TestInheritTakesTheMarksOwnColour;
    procedure TestTheOptionIsActuallyRead;
    procedure TestTheDefaultTextIsTheValueOrTheName;
    procedure TestALetterTokenIsReplacedOnceAndADimensionEveryTime;
    procedure TestACaptionBecomesASecondEntryForTheSameDatum;
    procedure TestTheOffsetMovesTheCaptionAfterThePositionHasPlacedIt;
    procedure TestAMarkWithNothingToSayCostsNothing;
    procedure TestTheExpansionDoesNotExpandItsOwnOutput;
  end;

implementation

const
  CharW = 10.0;
  CharH = 12.0;
  Eps = 1e-9;
  { A host to hang labels off: x 10..110, y 20..60. }
  HostL = 10.0;
  HostT = 20.0;
  HostW = 100.0;
  HostH = 40.0;
  Dist = 5.0;

procedure TLabelMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := Length(AText) * CharW;
  AH := CharH;
end;

function TLabelMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

procedure TAdvChartLabelsTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FStore := nil;
  FList := nil;
  FM := TLabelMeasurer.Create;
end;

procedure TAdvChartLabelsTest.TearDown;
begin
  FM := nil;
  FreeAndNil(FList);
  FreeAndNil(FStore);
  FreeAndNil(FOpt);
  inherited TearDown;
end;

procedure TAdvChartLabelsTest.At(APosition: TTyLabelPosition;
  out AX, AY: Double; out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
begin
  TyLabelAnchor(TyRectF(HostL, HostT, HostL + HostW, HostT + HostH),
    APosition, Dist, 0, 0, AX, AY, AH, AV);
end;

function TAdvChartLabelsTest.SpecOf(const AText: string): TTyLabelSpec;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message,
    FOpt.SetOptionText(AText));
  Result := TyLabelSpecOf(FOpt, 0, TyLabelSpecNone);
end;

procedure TAdvChartLabelsTest.TestTheFourOutsidePositions;
var
  x, y: Double;
  h: TTyTextAnchorH;
  v: TTyTextAnchorV;
begin
  { The anchor moves OUT by the distance and the text is pinned by the edge
    FACING the mark -- that pairing is what turns the distance into a gap. A
    version that anchored correctly and pinned the near edge would draw every
    one of these on top of the thing it names. }
  At(tlpLeft, x, y, h, v);
  AssertEquals('left: a distance off the left edge', HostL - Dist, x, Eps);
  AssertEquals('halfway down', HostT + HostH / 2, y, Eps);
  AssertEquals('pinned by its RIGHT edge', Ord(tahRight), Ord(h));
  AssertEquals('and its middle', Ord(tavMiddle), Ord(v));

  At(tlpRight, x, y, h, v);
  AssertEquals('right: past the right edge', HostL + HostW + Dist, x, Eps);
  AssertEquals('pinned by its LEFT edge', Ord(tahLeft), Ord(h));
  AssertEquals('', Ord(tavMiddle), Ord(v));

  At(tlpTop, x, y, h, v);
  AssertEquals('top: centred across', HostL + HostW / 2, x, Eps);
  AssertEquals('a distance above', HostT - Dist, y, Eps);
  AssertEquals('', Ord(tahCentre), Ord(h));
  AssertEquals('pinned by its BOTTOM edge, so it sits above', Ord(tavBottom),
    Ord(v));

  At(tlpBottom, x, y, h, v);
  AssertEquals('bottom: a distance below', HostT + HostH + Dist, y, Eps);
  AssertEquals('pinned by its TOP edge', Ord(tavTop), Ord(v));
  AssertEquals('', Ord(tahCentre), Ord(h));
end;

procedure TAdvChartLabelsTest.TestTheNineInsidePositions;
var
  x, y: Double;
  h: TTyTextAnchorH;
  v: TTyTextAnchorV;
begin
  { Inside, the distance is an INSET from the named edge rather than a gap
    outside it, and the pinned edge is the one NEAREST that edge -- the
    opposite pairing from the four above. }
  At(tlpInside, x, y, h, v);
  AssertEquals('inside: the middle', HostL + HostW / 2, x, Eps);
  AssertEquals('', HostT + HostH / 2, y, Eps);
  AssertEquals('', Ord(tahCentre), Ord(h));
  AssertEquals('', Ord(tavMiddle), Ord(v));

  At(tlpInsideLeft, x, y, h, v);
  AssertEquals('insideLeft: inset from the left', HostL + Dist, x, Eps);
  AssertEquals('pinned by its own left', Ord(tahLeft), Ord(h));
  AssertEquals('', Ord(tavMiddle), Ord(v));

  At(tlpInsideRight, x, y, h, v);
  AssertEquals('insideRight: inset from the right', HostL + HostW - Dist, x, Eps);
  AssertEquals('pinned by its own right', Ord(tahRight), Ord(h));

  At(tlpInsideTop, x, y, h, v);
  AssertEquals('insideTop: inset from the top', HostT + Dist, y, Eps);
  AssertEquals('', Ord(tahCentre), Ord(h));
  AssertEquals('pinned by its own top', Ord(tavTop), Ord(v));

  At(tlpInsideBottom, x, y, h, v);
  AssertEquals('insideBottom', HostT + HostH - Dist, y, Eps);
  AssertEquals('pinned by its own bottom', Ord(tavBottom), Ord(v));

  At(tlpInsideTopLeft, x, y, h, v);
  AssertEquals('insideTopLeft', HostL + Dist, x, Eps);
  AssertEquals('', HostT + Dist, y, Eps);
  AssertEquals('', Ord(tahLeft), Ord(h));
  AssertEquals('', Ord(tavTop), Ord(v));

  At(tlpInsideTopRight, x, y, h, v);
  AssertEquals('insideTopRight', HostL + HostW - Dist, x, Eps);
  AssertEquals('', HostT + Dist, y, Eps);
  AssertEquals('', Ord(tahRight), Ord(h));
  AssertEquals('', Ord(tavTop), Ord(v));

  At(tlpInsideBottomLeft, x, y, h, v);
  AssertEquals('insideBottomLeft', HostL + Dist, x, Eps);
  AssertEquals('', HostT + HostH - Dist, y, Eps);
  AssertEquals('', Ord(tahLeft), Ord(h));
  AssertEquals('', Ord(tavBottom), Ord(v));

  At(tlpInsideBottomRight, x, y, h, v);
  AssertEquals('insideBottomRight', HostL + HostW - Dist, x, Eps);
  AssertEquals('', HostT + HostH - Dist, y, Eps);
  AssertEquals('', Ord(tahRight), Ord(h));
  AssertEquals('', Ord(tavBottom), Ord(v));
end;

procedure TAdvChartLabelsTest.TestDistanceDoesNothingInTheDefaultPosition;
var
  near_, far_: Double;
  y: Double;
  h: TTyTextAnchorH;
  v: TTyTextAnchorV;
begin
  { `inside` is the only position with no distance term, and it is the DEFAULT
    -- so a chart that sets `distance` and leaves `position` alone sees nothing
    move. Worth a test of its own because it looks like a bug when you meet it
    and the temptation is to "fix" it. }
  TyLabelAnchor(TyRectF(HostL, HostT, HostL + HostW, HostT + HostH),
    tlpInside, 0, 0, 0, near_, y, h, v);
  TyLabelAnchor(TyRectF(HostL, HostT, HostL + HostW, HostT + HostH),
    tlpInside, 999, 0, 0, far_, y, h, v);
  AssertEquals('a thousand pixels of distance move it nowhere', near_, far_, Eps);

  { And it DOES move everything else, so the test above is about `inside` and
    not about the distance never being read. }
  TyLabelAnchor(TyRectF(HostL, HostT, HostL + HostW, HostT + HostH),
    tlpInsideLeft, 0, 0, 0, near_, y, h, v);
  TyLabelAnchor(TyRectF(HostL, HostT, HostL + HostW, HostT + HostH),
    tlpInsideLeft, 30, 0, 0, far_, y, h, v);
  AssertEquals('insideLeft moves by exactly the distance', near_ + 30, far_, Eps);
end;

procedure TAdvChartLabelsTest.TestAnUnknownNameIsNotTheDefault;
var
  known: Boolean;
  x, y: Double;
  h: TTyTextAnchorH;
  v: TTyTextAnchorV;
begin
  { zrender's switch has NO default case. An unrecognised name therefore leaves
    x and y at the host's top-left with the text hanging down and right -- a
    visibly different picture from `inside`, and the one upstream draws. A port
    that quietly substituted the default would hide the typo. }
  TyLabelPositionOf('insideMiddle', known);
  AssertFalse('not one of the thirteen', known);
  TyLabelPositionOf('inside', known);
  AssertTrue('this one is', known);

  At(tlpNone, x, y, h, v);
  AssertEquals('the fallthrough is the top-left corner', HostL, x, Eps);
  AssertEquals('', HostT, y, Eps);
  AssertEquals('hanging right', Ord(tahLeft), Ord(h));
  AssertEquals('and down', Ord(tavTop), Ord(v));
end;

procedure TAdvChartLabelsTest.TestOutsideIsNotAPositionButARequestForOne;
begin
  { `outside` is used by bar series and is not a zrender position at all --
    upstream maps it to the series' own default outside position. Passed
    through untranslated it would land at the top-left with every other
    unrecognised name. }
  AssertEquals('outside becomes top', Ord(tlpTop),
    Ord(SpecOf('{ "series": [ { "type": "bar", "label":'
      + ' { "position": "outside" } } ] }').Position));
  { ... for a mark that has no outside of its own. A bar has one -- past the
    end it grows to -- so the request is remembered, and a written 'top' is
    not it. }
  AssertTrue('and is remembered as a request',
    SpecOf('{ "series": [ { "type": "bar", "label":'
      + ' { "position": "outside" } } ] }').Outside);
  AssertFalse('top is only top',
    SpecOf('{ "series": [ { "type": "bar", "label":'
      + ' { "position": "top" } } ] }').Outside);
end;

procedure TAdvChartLabelsTest.TestTheArrayFormPinsTheTopLeft;
var
  x, y: Double;
  h: TTyTextAnchorH;
  v: TTyTextAnchorV;
  spec: TTyLabelSpec;
begin
  { The two numbers are an offset from the host's TOP-LEFT and the percentages
    are of the host's OWN width and height. And the alignment is not centred:
    upstream sets both to null here, which resolves to left/top -- so
    ['50%','50%'] puts the anchor where `inside` does and then hangs the text
    down and right of it instead of centring on it. }
  spec := SpecOf('{ "series": [ { "type": "bar", "label":'
    + ' { "position": ["50%", "25%"] } } ] }');
  AssertEquals('read as the array form', Ord(tlpAt), Ord(spec.Position));
  AssertEquals('kept as a fraction until the host is known', 0.5, spec.AtX, Eps);
  AssertEquals('', 0.25, spec.AtY, Eps);

  TyLabelAnchor(TyRectF(HostL, HostT, HostL + HostW, HostT + HostH),
    tlpAt, Dist, spec.AtX * HostW, spec.AtY * HostH, x, y, h, v);
  AssertEquals('half the host across', HostL + HostW / 2, x, Eps);
  AssertEquals('a quarter of it down', HostT + HostH / 4, y, Eps);
  AssertEquals('and pinned by its top-left, NOT centred', Ord(tahLeft), Ord(h));
  AssertEquals('', Ord(tavTop), Ord(v));
end;

procedure TAdvChartLabelsTest.TestLuminanceCountsAlphaAsDarkness;
begin
  { zrender's lum() with a background luminance of ZERO for this call: the
    alpha multiplies in and nothing is added back, so a half-transparent colour
    reads as half as bright. The comment beside upstream's formula says
    "assumed white background" and is wrong for this call site -- it is right
    for the two dark-mode ones, which pass one. }
  AssertEquals('white', 1.0, TyLabelLuminance($FFFFFFFF), 1e-6);
  AssertEquals('black', 0.0, TyLabelLuminance($FF000000), 1e-6);
  { 0.299R + 0.587G + 0.114B, so green weighs most. }
  AssertEquals('pure green', 0.587, TyLabelLuminance($FF00FF00), 1e-6);
  AssertEquals('pure red', 0.299, TyLabelLuminance($FFFF0000), 1e-6);
  AssertEquals('half-transparent white is half as bright', 0.5,
    TyLabelLuminance($80FFFFFF), 0.005);
end;

procedure TAdvChartLabelsTest.TestTheInsideInkIsThreeBandsNotTwo;
var
  spec: TTyLabelSpec;
begin
  { THREE BANDS, and the middle one is the LIGHTEST. It reads backwards until
    you see the reason: on a mid-dark fill you want maximum contrast, but on a
    nearly black one the brightest ink glares and a softer light reads better.
    Collapse it to a light/dark pair and the dark end comes out wrong. }
  spec := TyLabelSpecNone;
  spec.AutoColour := True;
  spec.InsideColour[0] := $FF111111;   { on a light mark }
  spec.InsideColour[1] := $FF222222;   { on a mid mark }
  spec.InsideColour[2] := $FF333333;   { on a dark mark }
  spec.OutsideColour := $FF445566;

  AssertEquals('white is over 0.5, so the dark ink', $FF111111,
    TyLabelAutoColour(spec, $FFFFFFFF, True, True));
  { Pure red is 0.299: over 0.2, under 0.5 -- the middle band. }
  AssertEquals('a mid mark takes the second band', $FF222222,
    TyLabelAutoColour(spec, $FFFF0000, True, True));
  AssertEquals('and a near-black one the third', $FF333333,
    TyLabelAutoColour(spec, $FF000000, True, True));

  { THE BOUNDARY IS STRICTLY GREATER, and two adjacent byte values straddle
    it: grey 128 is 128/255 = 0.5020 and takes the dark ink, grey 127 is 0.4980
    and takes the middle band. Asserting the pair is what pins `>` rather than
    `>=`; a single grey somewhere in the middle of a band cannot. }
  AssertEquals('grey 128 is over a half', $FF111111,
    TyLabelAutoColour(spec, $FF808080, True, True));
  AssertEquals('and grey 127 is under it', $FF222222,
    TyLabelAutoColour(spec, $FF7F7F7F, True, True));

  { AN UNFILLED MARK MAKES THE LABEL AN OUTSIDE ONE: zrender asks whether
    the host has a fill before anything inside. [Revised in batch 47: this
    pinned the light band's ink.] }
  AssertEquals('no fill, so the outside ink', spec.OutsideColour,
    TyLabelAutoColour(spec, 0, False, True));
end;

procedure TAdvChartLabelsTest.TestAnOutsideLabelIgnoresWhatItIsLabelling;
var spec: TTyLabelSpec;
begin
  { Upstream never looks at the mark for an outside label -- it returns the
    theme's own ink. Deriving it from the fill would make a label beside a dark
    bar come out light, on a light ground, where nothing can read it. }
  spec := TyLabelSpecNone;
  spec.AutoColour := True;
  spec.InsideColour[0] := $FF111111;
  spec.InsideColour[1] := $FF222222;
  spec.InsideColour[2] := $FF333333;
  spec.OutsideColour := $FF445566;
  AssertEquals('outside a white mark', $FF445566,
    TyLabelAutoColour(spec, $FFFFFFFF, True, False));
  AssertEquals('and outside a black one, the same', $FF445566,
    TyLabelAutoColour(spec, $FF000000, True, False));

  { And the set of positions that count as inside is upstream's own -- decided
    by the NAME containing "inside", not by the geometry. }
  AssertTrue('insideTopLeft is inside', TyLabelIsInside(tlpInsideTopLeft));
  AssertFalse('top is not', TyLabelIsInside(tlpTop));
  AssertFalse('and neither is the array form', TyLabelIsInside(tlpAt));
end;

procedure TAdvChartLabelsTest.TestInheritTakesTheMarksOwnColour;
var spec: TTyLabelSpec;
begin
  spec := SpecOf('{ "series": [ { "type": "bar", "label":'
    + ' { "color": "inherit" } } ] }');
  AssertTrue('recorded as a request, not a colour', spec.InheritColour);
  AssertFalse('and it is not the automatic rule', spec.AutoColour);
  AssertEquals('resolved to the mark''s own fill', $FF123456,
    TyLabelAutoColour(spec, $FF123456, True, True));
end;

procedure TAdvChartLabelsTest.TestTheOptionIsActuallyRead;
var spec: TTyLabelSpec;
begin
  { Every one of these is read by the same function, and that function had
    tests only for the keys with visible geometry the last three times this
    library built one. }
  spec := SpecOf('{ "series": [ { "type": "bar", "label": { "show": true,'
    + ' "position": "insideTop", "distance": 9, "offset": [3, -4],'
    + ' "rotate": 90, "overflow": "truncate", "formatter": "{c} kg",'
    + ' "fontSize": 14, "fontWeight": "bold" } } ] }');
  AssertTrue('show', spec.Show);
  AssertEquals('position', Ord(tlpInsideTop), Ord(spec.Position));
  AssertEquals('distance', 9.0, spec.DistanceLogical, Eps);
  AssertEquals('offset x', 3.0, spec.OffsetXLogical, Eps);
  AssertEquals('offset y', -4.0, spec.OffsetYLogical, Eps);
  { DEGREES in the option, radians here -- and NOT clamped to -90..90, which
    the option catalog claims and the source does not enforce. }
  AssertEquals('rotate', Pi / 2, spec.RotationRad, 1e-9);
  AssertEquals('overflow', Ord(tloTruncate), Ord(spec.Overflow));
  AssertEquals('formatter', '{c} kg', spec.Formatter);
  { CSS PX, not the theme's points: 14 read as a point size drew a third too
    large [Batch 83] }
  AssertTrue('font size is px', TyFontSizeIsPx(spec.FontSizeLogical));
  AssertEquals('font size', 14.0, TyFontPxOf(spec.FontSizeLogical), 1e-9);
  AssertEquals('bold is 700', 700, spec.FontWeight);

  { OFF UNLESS ASKED. Neither bar nor line nor scatter declares label.show, and
    an absent show is falsy -- so a chart that never mentioned labels must not
    grow them. }
  AssertFalse('no label block at all',
    SpecOf('{ "series": [ { "type": "bar" } ] }').Show);
  AssertFalse('a label block that does not say show',
    SpecOf('{ "series": [ { "type": "bar", "label": { "position": "top" } } ] }').Show);
end;

procedure TAdvChartLabelsTest.TestTheDefaultTextIsTheValueOrTheName;
begin
  FStore := TTyDataStore.Create;
  FStore.AddDimension('v', ddtFloat);
  FStore.AppendRow([42.0]);
  FStore.SetName(0, 'Rent');

  { A BAR SHOWS ITS VALUE AND A PIE SHOWS ITS NAME, and one default for both
    renders every unformatted pie label as a number. }
  AssertEquals('a value series', '42',
    TyLabelText('', False, tldValue, FStore, 0, 'Cost', 0, 0, False));
  AssertEquals('a named one', 'Rent',
    TyLabelText('', False, tldName, FStore, 0, 'Cost', 0, 0, False));
end;

procedure TAdvChartLabelsTest.TestALetterTokenIsReplacedOnceAndADimensionEveryTime;
begin
  FStore := TTyDataStore.Create;
  FStore.AddDimension('v', ddtFloat);
  FStore.AddDimension('extra', ddtFloat);
  FStore.AppendRow([42.0, 7.0]);
  FStore.SetName(0, 'Rent');

  AssertEquals('the four letters', 'Cost Rent 42',
    TyLabelText('{a} {b} {c}', True, tldValue, FStore, 0, 'Cost', 0, 0, False));

  { ONCE EACH. Upstream hands String.replace a plain string rather than a
    regex, so a repeated token is emitted LITERALLY -- and a port using a
    global replace diverges on any template that repeats one. Nothing in the
    harvested gallery repeats a token, so only a test can pin this. }
  AssertEquals('the second {c} is left standing', '42 {c}',
    TyLabelText('{c} {c}', True, tldValue, FStore, 0, 'Cost', 0, 0, False));

  { AND {@dim} IS THE OTHER WAY ROUND, because its pattern upstream IS a global
    regex. Two rules, and they are upstream's two rules. }
  AssertEquals('every {@extra}', '7 and 7',
    TyLabelText('{@extra} and {@extra}', True, tldValue, FStore, 0, 'Cost', 0, 0, False));

  { An unknown dimension is blank rather than left as a token. }
  AssertEquals('', '', TyLabelText('{@nope}', True, tldValue, FStore, 0, 'Cost', 0,
    0, False));

  { {d} is the percent, and a series that has none leaves it alone rather than
    printing a zero. }
  AssertEquals('{d} untouched without a percent', '{d}',
    TyLabelText('{d}', True, tldValue, FStore, 0, 'Cost', 0, 0, False));
  AssertEquals('and filled in with one', '25',
    TyLabelText('{d}', True, tldValue, FStore, 0, 'Cost', 0, 25, True));
end;

procedure TAdvChartLabelsTest.TestACaptionBecomesASecondEntryForTheSameDatum;
var
  host: TTyChartElement;
  specs: TTyLabelSpecArray;
  cap: TTyChartElement;
begin
  { The whole seam in one assertion: one mark with words becomes two entries,
    and the second answers for the same row. Hovering a bar's number has to
    report that bar. }
  FList := TTyPaintList.Create;
  host := TyChartElement(TyShapeRect(TyRectF(HostL, HostT,
    HostL + HostW, HostT + HostH)));
  host.Style.HasFill := True;
  host.Style.FillColor := $FF000000;
  host.Silent := False;
  host.Datum := TyChartDatum(3, 7);
  host.Caption.Text := 'abc';
  FList.Add(host);

  SetLength(specs, 4);
  specs[3] := TyLabelSpecNone;
  specs[3].Show := True;
  specs[3].Position := tlpTop;
  specs[3].DistanceLogical := Dist;
  specs[3].AutoColour := True;
  specs[3].OutsideColour := $FF445566;
  TyExpandLabels(FList, specs, FM, 96);

  AssertEquals('one mark became two entries', 2, FList.Count);
  cap := FList.Element(1);
  AssertEquals('the caption carries the words', 'abc', cap.Caption.Text);
  AssertEquals('for the same series', 3, cap.Datum.SeriesIndex);
  AssertEquals('and the same row', 7, cap.Datum.DataIndex);
  AssertFalse('and it answers the pointer, like its mark', cap.Silent);

  { ITS SHAPE IS ITS OWN BOX, which is the reason it is an entry at all: the
    ink and the hit test describe the same rectangle. `top` centres it across
    the host and pins its bottom edge a distance above. }
  AssertEquals('three characters wide', 3 * CharW,
    TyRectFWidth(cap.Shape.Bounds), Eps);
  AssertEquals('centred on the host', HostL + HostW / 2,
    (cap.Shape.Bounds.Left + cap.Shape.Bounds.Right) / 2, Eps);
  AssertEquals('its foot a distance above the host', HostT - Dist,
    cap.Shape.Bounds.Bottom, Eps);

  { ABOVE ITS OWN MARK, and said rather than left to insertion order. }
  AssertTrue('painted over the thing it names', cap.Z2 > host.Z2);
  { Outside, so the theme ink rather than anything read off the black bar. }
  AssertEquals('the theme ink', $FF445566, cap.Caption.Colour);
end;

procedure TAdvChartLabelsTest.TestAMarkWithNothingToSayCostsNothing;
var
  host: TTyChartElement;
  specs: TTyLabelSpecArray;
begin
  FList := TTyPaintList.Create;
  host := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
  host.Datum := TyChartDatum(0, 0);
  FList.Add(host);
  SetLength(specs, 1);
  specs[0] := TyLabelSpecNone;
  specs[0].Show := True;
  TyExpandLabels(FList, specs, FM, 96);
  AssertEquals('no words, no second entry', 1, FList.Count);

  { And a series switched off does not grow one either, even with words. }
  FList.Clear;
  host.Caption.Text := 'abc';
  FList.Add(host);
  specs[0].Show := False;
  TyExpandLabels(FList, specs, FM, 96);
  AssertEquals('switched off', 1, FList.Count);
end;

procedure TAdvChartLabelsTest.TestTheExpansionDoesNotExpandItsOwnOutput;
var
  host: TTyChartElement;
  specs: TTyLabelSpecArray;
  i: Integer;
begin
  { The pass appends to the list it is walking. Taking the count once is what
    stops it from expanding the captions it just made -- which would terminate
    only because a caption has no caption of its own, and that is luck rather
    than a rule. }
  FList := TTyPaintList.Create;
  for i := 0 to 2 do
  begin
    host := TyChartElement(TyShapeRect(TyRectF(0, 0, 10, 10)));
    host.Datum := TyChartDatum(0, i);
    host.Caption.Text := 'x';
    FList.Add(host);
  end;
  SetLength(specs, 1);
  specs[0] := TyLabelSpecNone;
  specs[0].Show := True;
  specs[0].Position := tlpInside;
  TyExpandLabels(FList, specs, FM, 96);
  AssertEquals('three marks and three captions, not more', 6, FList.Count);
  for i := 3 to 5 do
    AssertEquals('every caption carries words', 'x', FList.Element(i).Caption.Text);
end;

procedure TAdvChartLabelsTest.TestTheBandBoundaryIsStrictlyGreater;
var spec: TTyLabelSpec;
begin
  { A LUMINANCE OF EXACTLY A HALF, which decides between `>` and `>=` and
    which no round grey can reach: a grey of 128 is 0.5020 and 127 is 0.4980.
    Alpha supplies the missing precision -- this colour computes to 0.5 to
    the last bit, and there are twenty-one others that do.

    At exactly the boundary the first test FAILS, so the value falls through
    to the second band. An inclusive comparison would take the first. }
  spec := TyLabelSpecNone;
  spec.AutoColour := True;
  spec.InsideColour[0] := $FF111111;
  spec.InsideColour[1] := $FF222222;
  spec.InsideColour[2] := $FF333333;
  AssertEquals('the colour really is a half', 0.5,
    TyLabelLuminance($9683FDFF), 0.0);
  AssertEquals('and a half is NOT over a half', $FF222222,
    TyLabelAutoColour(spec, $9683FDFF, True, True));
end;

procedure TAdvChartLabelsTest.TestTheOffsetMovesTheCaptionAfterThePositionHasPlacedIt;
var
  host: TTyChartElement;
  specs: TTyLabelSpecArray;
  plain, moved: TTyRectF;

  function CaptionBoxWith(AOffX, AOffY: Double): TTyRectF;
  begin
    FList.Clear;
    FList.Add(host);
    specs[0].OffsetXLogical := AOffX;
    specs[0].OffsetYLogical := AOffY;
    TyExpandLabels(FList, specs, FM, 96);
    Result := FList.Element(1).Shape.Bounds;
  end;

begin
  { `offset` is read by the option reader and then has to REACH the anchor.
    Reading it into a field nobody adds is this repository's most repeated
    failure, and a reader test alone cannot tell the difference. }
  FList := TTyPaintList.Create;
  host := TyChartElement(TyShapeRect(TyRectF(HostL, HostT,
    HostL + HostW, HostT + HostH)));
  host.Datum := TyChartDatum(0, 0);
  host.Caption.Text := 'ab';
  SetLength(specs, 1);
  specs[0] := TyLabelSpecNone;
  specs[0].Show := True;
  specs[0].Position := tlpInside;

  plain := CaptionBoxWith(0, 0);
  moved := CaptionBoxWith(7, -3);
  AssertEquals('moved across by exactly the offset', plain.Left + 7,
    moved.Left, Eps);
  AssertEquals('and up by it', plain.Top - 3, moved.Top, Eps);

  { AND IT IS LOGICAL px, so it scales with the display like every other
    logical number in a spec. }
  FList.Clear;
  FList.Add(host);
  TyExpandLabels(FList, specs, FM, 192);
  AssertEquals('doubled at twice the density', plain.Left + 14,
    FList.Element(1).Shape.Bounds.Left, Eps);
end;

initialization
  RegisterTest(TAdvChartLabelsTest);
end.
