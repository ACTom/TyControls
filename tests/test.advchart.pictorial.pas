unit test.advchart.pictorial;
{$mode objfpc}{$H+}
{ The pictorial bar.

  FOUR RECTANGLES AND THREE OF THEM LEAVE NO INK, which is what makes this
  type worth its own suite: the value rect, the bounding length, the bar rect
  and the clip all agree on a plain chart and disagree the moment any of
  `symbolBoundingData`, `symbolRepeat` or `symbolClip` is written. A picture
  cannot tell them apart, so most of what follows asks the paint list and the
  arithmetic, and the pixels are kept for the two questions only pixels
  answer: did the ink reach the canvas, and did the clip really cut it.

  THE ARITHMETIC IS TESTED WITHOUT A CHART because it is available without
  one: AdvChart.Pictorial is a reader and three functions, and a glyph count
  that has to be inferred from a bitmap is a count nobody can debug. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Series, tyControls.AdvChart.Marks,
     tyControls.AdvChart.Option, tyControls.AdvChart.Layout,
     tyControls.AdvChart.BarLayout,
     tyControls.AdvChart.Symbol, tyControls.AdvChart.Pictorial,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartPictorialRuleTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    procedure TearDown; override;
    function SpecOf(const AText: string): TTyPictorialSpec;
    { The same, with ABody spliced into a pictorialBar series, so a test reads
      as the option fragment it is about and nothing else. }
    function SeriesSpec(const ABody: string): TTyPictorialSpec;
  published
    procedure TestAnUnwrittenSeriesIsTheDefaultsAndTheDefaultsAreUpstreams;
    procedure TestSymbolMarginStripsOneTrailingBangAndOnlyAtTheEnd;
    procedure TestSymbolMarginGoesThroughTheStringParserEvenAsANumber;
    procedure TestSymbolRepeatIsFourThingsWearingOneName;
    procedure TestSymbolPositionHasTwoKindsOfNothing;
    procedure TestTheRepeatDirectionIsComparedAgainstStartAlone;
    procedure TestSymbolSizeTakesAScalarForBothAxes;
    procedure TestAOneElementSymbolOffsetAppliesToBothAxes;
    procedure TestBoundingDataSortsItsPairAndRefusesAShortArray;
    procedure TestTheRotationIsClampedBeforeItIsMultiplied;
    procedure TestTimesRoundsWithinATenThousandthAndOtherwiseCeils;
    procedure TestTimesHasADomainWhereTheOriginalHasNone;
    procedure TestNoRepeatIsOneGlyphOfItsOwnLength;
    procedure TestTheMarginIsSolvedASecondTimeSoTheCountSpansExactly;
    procedure TestAnEndGapPutsAGapAtBothEndsAndStopsTheTrim;
    procedure TestALoneGlyphStillGetsItsMarginSolved;
    procedure TestOnlyTrueCutsTheCountBackToWhatTheDataPaidFor;
    procedure TestAWrittenCountKillsTheMarginsValueButNotItsFlag;
    procedure TestARepeatTooShortForOneGlyphIsNoneRatherThanADivideByZero;
    procedure TestTheSlotsAreEvenlySpacedAndCentredOnTheAnchor;
  end;

  TAdvChartPictorialMarksTest = class(TTestCase)
  private
    FCart: TTyCartesian2D;
    FStore: TTyDataStore;
    FList: TTyPaintList;
    FOpt: TTyChartOption;
    FValueAxis: TTyAxis;
    FBinding: TTySeriesBinding;
    procedure SetUp; override;
    procedure TearDown; override;
    { A category x against a value y from AMin to AMax, over 400 x 300. }
    procedure Given(const AValues: array of Double; AMin, AMax: Double);
    { The same chart on its side: categories on y, values on x. }
    procedure GivenSideways(const AValues: array of Double;
      AMin, AMax: Double);
    { Build the fixture's one series with ABody as its option text, and answer
      how many elements landed. }
    function Build(const ABody: string): Integer;
    { The glyphs are the silent elements; the bar rect is the hittable one. }
    function GlyphCount: Integer;
    function GlyphAt(AIndex: Integer): TTyChartElement;
    function BarRectAt(AIndex: Integer): TTyChartElement;
    function CentreOf(const AElement: TTyChartElement): TTyPointF;
    { How many of a polygon's vertices sit above its own centre. }
    function VerticesAbove(const AElement: TTyChartElement): Integer;
  published
    procedure TestOneGlyphAndOneRectPerDatum;
    procedure TestTheRectIsTheOnlyThingAPointerCanLandOn;
    procedure TestTheRectCarriesNoInkAtAll;
    procedure TestTheGlyphStartsOnTheBaselineRatherThanOnTheBarsMiddle;
    procedure TestPositionEndHangsItOffTheFarEnd;
    procedure TestPositionCentreSplitsTheDifference;
    procedure TestASizeInPercentMeasuresTheBandAcrossAndTheBarAlong;
    procedure TestARepeatMeasuresBothPercentagesAgainstTheBand;
    procedure TestRepeatDrawsAColumnAndTheGlyphsAreEvenlySpaced;
    procedure TestBoundingDataMovesTheGlyphWithoutMovingTheData;
    procedure TestTheBarRectGrowsToCoverAGlyphThatOverhangsIt;
    procedure TestClipCutsAtTheValueAndLeavesTheBandAlone;
    procedure TestWithoutClipNothingIsCutAndTheRectNeverIs;
    procedure TestASidewaysChartCountsAlongXAndBandsAlongY;
    procedure TestAnInvertedAxisMirrorsTheGlyphRatherThanTurningIt;
    procedure TestABarOfNoLengthStillPointsTheWayPositiveValuesGo;
    procedure TestTheDirectionComesFromTheBoundingLengthNotFromTheData;
    procedure TestTheRepeatDirectionDecidesWhichGlyphIsDrawnFirst;
    procedure TestABoundingPairTakesTheEndTheBarRunsTowards;
    procedure TestARepeatWithoutBoundingDataFillsThePlotNotTheBar;
    procedure TestAGapDrawsNothingAtAllForThatRow;
    procedure TestTheOffsetMovesTheGlyphAndLeavesTheBandAlone;
    procedure TestEveryGlyphAnswersForItsOwnRow;
    procedure TestASymbolOfNoneDrawsTheRectAndNothingElse;
    procedure TestTheDefaultGlyphIsSolidRatherThanTheLinesRing;
    procedure TestAStackedPictorialStandsOnTheOneBelowIt;
    procedure TestARowCanWriteEveryOneOfTheseOptionsForItself;
  end;

  TAdvChartPictorialDrawTest = class(TTestCase)
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
    function InkIn(AL, AT, AR, AB: Integer): Integer;
  published
    procedure TestAPictorialBarDrawsAtAll;
    procedure TestItSaysNothingAboutHavingNoRenderer;
    procedure TestTheGlyphsAreWhereTheDataIsAndNotWhereItIsNot;
    procedure TestClipReallyRemovesInk;
    procedure TestASeriesCanSayWhichOfTwoPicturesIsOnTop;
    procedure TestOnlyAWrittenClipCutsTheGlyphAtThePlotEdge;
    procedure TestTheSolvedColumnIsWhatTheGlyphIsMeasuredAgainst;
  end;

implementation

const
  Eps = 1e-6;
  cW = 480;
  cH = 320;

{ ==================== the rules ==================== }

procedure TAdvChartPictorialRuleTest.TearDown;
begin
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartPictorialRuleTest.SpecOf(const AText: string): TTyPictorialSpec;
begin
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses', FOpt.SetOptionText(AText));
  Result := TyPictorialSpecOf(FOpt, 0);
end;

function TAdvChartPictorialRuleTest.SeriesSpec(const ABody: string): TTyPictorialSpec;
begin
  Result := SpecOf('{"series":[{"type":"pictorialBar","data":[1,2,3]'
    + ABody + '}]}');
end;

procedure TAdvChartPictorialRuleTest.TestAnUnwrittenSeriesIsTheDefaultsAndTheDefaultsAreUpstreams;
var s: TTyPictorialSpec;
begin
  s := SeriesSpec('');
  { EVERY ONE OF THESE IS A VALUE FROM PictorialBarSeries.defaultOption, and
    they are asserted together because that is the whole claim of the record:
    a series that says nothing still draws the chart ECharts draws. }
  AssertEquals('no symbol of its own', '', s.SymbolName);
  AssertEquals('a full-size glyph', Ord(buPercent), Ord(s.SizeW.Kind));
  AssertEquals(100.0, s.SizeW.Value, Eps);
  AssertEquals(100.0, s.SizeH.Value, Eps);
  AssertFalse('and nobody wrote a size', s.HasSize);
  AssertEquals('upright', 0.0, s.RotateDeg, Eps);
  AssertEquals('at the start', Ord(pspStart), Ord(s.Position));
  AssertFalse('no offset written', s.HasOffset);
  AssertEquals('a 15% margin', Ord(buPercent), Ord(s.Margin.Kind));
  AssertEquals(15.0, s.Margin.Value, Eps);
  AssertFalse('and no end gap', s.MarginEndGap);
  AssertEquals('one glyph', Ord(prNone), Ord(s.Repeat_));
  AssertFalse('drawn from the end', s.RepeatFromStart);
  AssertFalse('and not clipped', s.Clip);
  AssertEquals('no bounding data', 0, s.BoundHas);
end;

procedure TAdvChartPictorialRuleTest.TestSymbolMarginStripsOneTrailingBangAndOnlyAtTheEnd;
var s: TTyPictorialSpec;
begin
  s := SeriesSpec(',"symbolMargin":"20%!"');
  AssertTrue('the bang asked for end gaps', s.MarginEndGap);
  AssertEquals(Ord(buPercent), Ord(s.Margin.Kind));
  AssertEquals('and the rest is still a percentage', 20.0, s.Margin.Value, Eps);

  { THE TEST IS ON THE LAST CHARACTER, not a search for a bang anywhere. A
    port that used Pos() would strip this one too and then fail to parse what
    was left behind. }
  s := SeriesSpec(',"symbolMargin":"10!%"');
  AssertFalse('a bang in the middle is not an end gap', s.MarginEndGap);

  { ONE BANG, not all of them: the source removes a single character and
    parses whatever remains -- and what remains here is `30%!`, which does not
    END in a percent sign, so parseFloat reads its leading thirty as PIXELS.
    Thirty per cent and thirty pixels are two very different margins, which is
    why the KIND is asserted beside the number. }
  s := SeriesSpec(',"symbolMargin":"30%!!"');
  AssertTrue('the last one still counts', s.MarginEndGap);
  AssertEquals('and what is left is no longer a percentage',
    Ord(buPx), Ord(s.Margin.Kind));
  AssertEquals(30.0, s.Margin.Value, Eps);
end;

procedure TAdvChartPictorialRuleTest.TestSymbolMarginGoesThroughTheStringParserEvenAsANumber;
var s: TTyPictorialSpec;
begin
  { A NUMBER IS STRINGIFIED FIRST -- upstream appends '' to whatever it finds
    before parsing -- so the string forms are not a lenient extra. }
  s := SeriesSpec(',"symbolMargin":4');
  AssertEquals(Ord(buPx), Ord(s.Margin.Kind));
  AssertEquals(4.0, s.Margin.Value, Eps);

  s := SeriesSpec(',"symbolMargin":"20px"');
  AssertEquals('px is read by parseFloat and thrown away',
    Ord(buPx), Ord(s.Margin.Kind));
  AssertEquals(20.0, s.Margin.Value, Eps);

  { THE NUMBER ENDS WHERE THE NUMBER ENDS. parseFloat reads a prefix and stops
    at the first character it cannot use -- including a SECOND decimal point,
    which is the one case where taking the whole string and letting the parser
    refuse it gives a different answer. }
  s := SeriesSpec(',"symbolMargin":"1.2.3"');
  AssertEquals(Ord(buPx), Ord(s.Margin.Kind));
  AssertEquals(1.2, s.Margin.Value, Eps);

  { AN OBJECT IS NOT A MARGIN, and it must not raise on the way past: fpjson's
    AsString raises on a container, which is how a reader loses the window. }
  s := SeriesSpec(',"symbolMargin":{"a":1}');
  AssertEquals('so the default stands', 15.0, s.Margin.Value, Eps);
  AssertEquals(Ord(buPercent), Ord(s.Margin.Kind));
end;

procedure TAdvChartPictorialRuleTest.TestSymbolRepeatIsFourThingsWearingOneName;
var s: TTyPictorialSpec;
begin
  s := SeriesSpec(',"symbolRepeat":false');
  AssertEquals('false is one glyph', Ord(prNone), Ord(s.Repeat_));

  s := SeriesSpec(',"symbolRepeat":true');
  AssertEquals('true fills and then cuts', Ord(prAuto), Ord(s.Repeat_));

  s := SeriesSpec(',"symbolRepeat":"fixed"');
  AssertEquals('fixed fills and does not cut',
    Ord(prFixedAuto), Ord(s.Repeat_));

  s := SeriesSpec(',"symbolRepeat":7');
  AssertEquals('a number is a count', Ord(prCount), Ord(s.Repeat_));
  AssertEquals(7.0, s.RepeatCount, Eps);

  { A NUMBER IN QUOTES IS A NUMBER. Upstream's test is isNumeric, which parses
    the string and then does arithmetic on it, so '5' really is five glyphs
    and not an unknown word. }
  s := SeriesSpec(',"symbolRepeat":"5"');
  AssertEquals(Ord(prCount), Ord(s.Repeat_));
  AssertEquals(5.0, s.RepeatCount, Eps);

  { AND AN UNKNOWN WORD IS NOT A REPEAT AT ALL: isNumeric('auto') is false and
    it is not 'fixed', so the whole block falls through. }
  s := SeriesSpec(',"symbolRepeat":"auto"');
  AssertEquals(Ord(prNone), Ord(s.Repeat_));
end;

procedure TAdvChartPictorialRuleTest.TestSymbolPositionHasTwoKindsOfNothing;
begin
  AssertEquals(Ord(pspStart), Ord(SeriesSpec(',"symbolPosition":"start"').Position));
  AssertEquals(Ord(pspEnd), Ord(SeriesSpec(',"symbolPosition":"end"').Position));
  AssertEquals(Ord(pspCentre), Ord(SeriesSpec(',"symbolPosition":"center"').Position));

  { THE TWO NOTHINGS. An ABSENT value is `start`, because the read is
    `get(...) || 'start'`; a MISSPELLED one falls off the end of a two-armed
    ternary and lands on `center`. Collapsing them -- the obvious tidy-up --
    moves every typo's glyph down onto the baseline. }
  AssertEquals('absent is start', Ord(pspStart), Ord(SeriesSpec('').Position));
  AssertEquals('so is an empty string', Ord(pspStart),
    Ord(SeriesSpec(',"symbolPosition":""').Position));
  AssertEquals('but the British spelling is not a word it knows',
    Ord(pspCentre), Ord(SeriesSpec(',"symbolPosition":"centre"').Position));
  AssertEquals('and neither is anything else',
    Ord(pspCentre), Ord(SeriesSpec(',"symbolPosition":"middle"').Position));
end;

procedure TAdvChartPictorialRuleTest.TestTheRepeatDirectionIsComparedAgainstStartAlone;
begin
  AssertTrue('start is the one word tested',
    SeriesSpec(',"symbolRepeatDirection":"start"').RepeatFromStart);
  AssertFalse('end is the default and the fallback',
    SeriesSpec(',"symbolRepeatDirection":"end"').RepeatFromStart);
  { EVERY OTHER VALUE BEHAVES AS `end`, typos included, because the source
    compares against 'start' and never against 'end'. }
  AssertFalse('a typo is an end',
    SeriesSpec(',"symbolRepeatDirection":"strat"').RepeatFromStart);
  AssertFalse('and so is nothing at all', SeriesSpec('').RepeatFromStart);
end;

procedure TAdvChartPictorialRuleTest.TestSymbolSizeTakesAScalarForBothAxes;
var s: TTyPictorialSpec;
begin
  s := SeriesSpec(',"symbolSize":24');
  AssertTrue('a size was written', s.HasSize);
  AssertEquals(Ord(buPx), Ord(s.SizeW.Kind));
  AssertEquals(24.0, s.SizeW.Value, Eps);
  AssertEquals('and it is the same on both axes', 24.0, s.SizeH.Value, Eps);

  s := SeriesSpec(',"symbolSize":["80%",12]');
  AssertEquals(Ord(buPercent), Ord(s.SizeW.Kind));
  AssertEquals(80.0, s.SizeW.Value, Eps);
  AssertEquals(Ord(buPx), Ord(s.SizeH.Kind));
  AssertEquals(12.0, s.SizeH.Value, Eps);

  { THE FLAG IS NOT THE VALUE. HasSize decides nothing about the size and
    everything about whether the author asked at all. }
  s := SeriesSpec(',"symbolSize":null');
  AssertTrue('null was still written', s.HasSize);
  AssertEquals('and the default stands', 100.0, s.SizeW.Value, Eps);
end;

procedure TAdvChartPictorialRuleTest.TestAOneElementSymbolOffsetAppliesToBothAxes;
var s: TTyPictorialSpec;
begin
  { normalizeSymbolOffset reads the second component through
    retrieve2(off[1], off[0]), so a one-element array is not "x only". }
  s := SeriesSpec(',"symbolOffset":[10]');
  AssertTrue(s.HasOffset);
  AssertEquals(10.0, s.OffsetX.Value, Eps);
  AssertEquals('the second falls back to the first', 10.0, s.OffsetY.Value, Eps);

  s := SeriesSpec(',"symbolOffset":[10,"-50%"]');
  AssertEquals(10.0, s.OffsetX.Value, Eps);
  AssertEquals(Ord(buPercent), Ord(s.OffsetY.Kind));
  AssertEquals(-50.0, s.OffsetY.Value, Eps);

  s := SeriesSpec(',"symbolOffset":6');
  AssertEquals('a scalar is both', 6.0, s.OffsetX.Value, Eps);
  AssertEquals(6.0, s.OffsetY.Value, Eps);
end;

procedure TAdvChartPictorialRuleTest.TestBoundingDataSortsItsPairAndRefusesAShortArray;
var s: TTyPictorialSpec;
begin
  s := SeriesSpec(',"symbolBoundingData":60');
  AssertEquals(1, s.BoundHas);
  AssertEquals(60.0, s.BoundA, Eps);

  s := SeriesSpec(',"symbolBoundingData":[60,-40]');
  AssertEquals(2, s.BoundHas);
  AssertEquals('sorted, because the pair names an interval', -40.0, s.BoundA, Eps);
  AssertEquals(60.0, s.BoundB, Eps);

  { A ONE-ELEMENT ARRAY IS REFUSED. Upstream reads element one regardless and
    gets undefined, which parses to NaN and poisons every coordinate the
    bounding length touches; answering "nothing was written" draws the chart
    the author almost certainly meant and cannot take the window down. }
  s := SeriesSpec(',"symbolBoundingData":[60]');
  AssertEquals('so it is as if nothing was written', 0, s.BoundHas);
  s := SeriesSpec(',"symbolBoundingData":["a","b"]');
  AssertEquals('and so are two things that are not numbers', 0, s.BoundHas);
end;

procedure TAdvChartPictorialRuleTest.TestTheRotationIsClampedBeforeItIsMultiplied;
begin
  AssertEquals(45.0, SeriesSpec(',"symbolRotate":45').RotateDeg, Eps);
  AssertEquals(-90.0, SeriesSpec(',"symbolRotate":-90').RotateDeg, Eps);
  { CLAMPED BEFORE IT IS MULTIPLIED, and that order is the whole point: a
    rotation of 1e308 degrees times Pi/180 overflows to infinity, and the
    infinity reaches every coordinate of the glyph. }
  AssertEquals(360.0, SeriesSpec(',"symbolRotate":1e308').RotateDeg, Eps);
  AssertEquals(-360.0, SeriesSpec(',"symbolRotate":-1e308').RotateDeg, Eps);
  AssertEquals('and a full turn is still a legal angle',
    360.0, SeriesSpec(',"symbolRotate":360').RotateDeg, Eps);
end;

procedure TAdvChartPictorialRuleTest.TestTimesRoundsWithinATenThousandthAndOtherwiseCeils;
begin
  { BOTH BRANCHES. Replacing the pair with one Round or one Ceil changes the
    glyph count by one on every inexact fit, which is every bar anybody
    actually draws. }
  AssertEquals('an exact fit is itself', 4, TyPictorialTimes(4.0));
  AssertEquals('and so is one within a ten-thousandth',
    4, TyPictorialTimes(4.00005));
  AssertEquals('from below too', 4, TyPictorialTimes(3.99995));
  AssertEquals('anything else rounds UP', 5, TyPictorialTimes(4.2));
  AssertEquals('including a hair over', 5, TyPictorialTimes(4.001));
  AssertEquals('and a hair under does not round down',
    4, TyPictorialTimes(3.9));
end;

procedure TAdvChartPictorialRuleTest.TestTimesHasADomainWhereTheOriginalHasNone;
begin
  { JS's Math.round HAS NO DOMAIN; this one targets an Int64 and raises
    outside it. The input is a ratio the author controls -- a division by a
    length that can be zero -- so infinity and not-a-number are ordinary here
    rather than exotic. }
  AssertEquals('no glyphs for nothing', 0, TyPictorialTimes(0));
  AssertEquals('nor for a negative run', 0, TyPictorialTimes(-3));
  AssertEquals('nor for not-a-number', 0, TyPictorialTimes(NaN));
  AssertEquals('nor for infinity', 0, TyPictorialTimes(Infinity));
  AssertEquals('and minus infinity is nothing too',
    0, TyPictorialTimes(-Infinity));
  AssertEquals('an absurd count is capped rather than overflowed',
    100000, TyPictorialTimes(1e30));
end;

procedure TAdvChartPictorialRuleTest.TestNoRepeatIsOneGlyphOfItsOwnLength;
var s: TTyPictorialSpec; r: TTyPictorialRun;
begin
  s := SeriesSpec('');
  r := TyPictorialRunOf(s, 20, 200, 200, 20);
  AssertEquals('one glyph', 1, r.Count);
  AssertEquals('as long as itself', 20.0, r.Unit_, Eps);
  AssertEquals('and the run is that long', 20.0, r.PathLen, Eps);
  AssertEquals('no margin was solved', 0.0, r.Margin, Eps);

  { AND THE BOUNDING LENGTH DOES NOT REACH IT. Without a repeat the run is one
    glyph however long the bar is, so a mutant that dropped the early exit has
    to be caught here rather than in a picture. }
  r := TyPictorialRunOf(s, 20, 5, 5, 20);
  AssertEquals(1, r.Count);
  AssertEquals(20.0, r.PathLen, Eps);
end;

procedure TAdvChartPictorialRuleTest.TestTheMarginIsSolvedASecondTimeSoTheCountSpansExactly;
var s: TTyPictorialSpec; r: TTyPictorialRun; want: Double;
begin
  { A GLYPH OF 20 WITH A MARGIN OF 5 EACH SIDE fits three times in 100 with a
    remainder, so the count rounds up to four -- and the margin is then
    RE-SOLVED so four span exactly 100. Four glyphs of 20 is 80, so 20 of
    margin is shared over the three inner gaps, and the answer is not the
    number that was written. }
  s := SeriesSpec(',"symbolRepeat":"fixed","symbolMargin":5');
  r := TyPictorialRunOf(s, 20, 100, 100, 20);
  AssertEquals('four fit', 4, r.Count);
  { THE EXPECTED VALUE IS BUILT IN A DOUBLE. A real constant beside two integer
    literals evaluates in SINGLE on this compiler, and the assertion then fails
    by a ten-millionth against a perfectly correct answer. }
  want := 20 / Double(2) / Double(3);
  AssertEquals('and the margin moved', want, r.Margin, 1e-9);
  AssertEquals('so the run spans the bounding length exactly',
    100.0, r.PathLen, 1e-9);

  { THE RE-SOLVED MARGIN CAN COME OUT NEGATIVE, and overlapping glyphs are the
    intended answer rather than a fault: a count that had to be rounded up has
    no other way to fit. }
  s := SeriesSpec(',"symbolRepeat":"fixed","symbolMargin":0');
  r := TyPictorialRunOf(s, 20, 70, 70, 20);
  AssertEquals('four glyphs of twenty in seventy pixels', 4, r.Count);
  AssertTrue('so they have to overlap', r.Margin < 0);
  AssertEquals(70.0, r.PathLen, 1e-9);
end;

procedure TAdvChartPictorialRuleTest.TestAnEndGapPutsAGapAtBothEndsAndStopsTheTrim;
var plain, gapped: TTyPictorialRun;
begin
  { WITHOUT the bang the run is trimmed by one margin at each end, so the
    outermost glyphs sit flush with the ends; WITH it they do not. The same
    count therefore spans the same bounding length by a different arithmetic,
    and the two must not come out the same numbers. }
  plain := TyPictorialRunOf(
    SeriesSpec(',"symbolRepeat":"fixed","symbolMargin":"25%"'),
    20, 100, 100, 20);
  gapped := TyPictorialRunOf(
    SeriesSpec(',"symbolRepeat":"fixed","symbolMargin":"25%!"'),
    20, 100, 100, 20);
  AssertEquals('both span the bounding length', 100.0, plain.PathLen, 1e-9);
  AssertEquals(100.0, gapped.PathLen, 1e-9);
  AssertTrue('but not with the same margin',
    Abs(plain.Margin - gapped.Margin) > 1e-6);
  AssertTrue('nor the same spacing',
    Abs(plain.Unit_ - gapped.Unit_) > 1e-6);
end;

procedure TAdvChartPictorialRuleTest.TestALoneGlyphStillGetsItsMarginSolved;
var r: TTyPictorialRun;
begin
  { WHY THE DIVISOR HAS A FLOOR. Without an end gap the margin is shared over
    the gaps BETWEEN glyphs, and one glyph has none -- `max(count - 1, 1)`
    keeps the divisor at one so the second pass still runs on a lone glyph.

    DROPPING THE FLOOR DOES NOT CRASH, which is exactly why it needs its own
    test: the divide-by-zero guard catches it and leaves the margin at nothing,
    and that is a different answer arrived at quietly. }
  r := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":"fixed","symbolMargin":0'),
    40, 30, 30, 40);
  AssertEquals('one glyph of forty in thirty pixels', 1, r.Count);
  AssertEquals('so it is pulled in by five on each side',
    -5.0, r.Margin, 1e-9);
  AssertEquals('and its unit is the bounding length itself',
    30.0, r.Unit_, 1e-9);

  { AND IT CHANGES WHAT THE THIRD PASS COUNTS, which is where it becomes
    visible: a bar half a glyph long earns NO glyph, because the trimmed ends
    cancel the data's own length exactly. }
  r := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":true,"symbolMargin":0'),
    40, 20, 20, 40);
  AssertEquals('half a glyph earns none', 0, r.Count);
end;

procedure TAdvChartPictorialRuleTest.TestOnlyTrueCutsTheCountBackToWhatTheDataPaidFor;
var auto, fixed_, counted: TTyPictorialRun;
begin
  { THE THIRD PASS IS WHAT MAKES `true` DIFFERENT. All three fill the bounding
    length; only `true` is then re-counted against the data's own, which is
    what lets a clipped column show how much was earned. }
  auto := TyPictorialRunOf(
    SeriesSpec(',"symbolRepeat":true,"symbolMargin":0'), 20, 100, 40, 20);
  fixed_ := TyPictorialRunOf(
    SeriesSpec(',"symbolRepeat":"fixed","symbolMargin":0'), 20, 100, 40, 20);
  counted := TyPictorialRunOf(
    SeriesSpec(',"symbolRepeat":5,"symbolMargin":0'), 20, 100, 40, 20);
  AssertEquals('true is cut to the data', 2, auto.Count);
  AssertEquals('fixed keeps the full column', 5, fixed_.Count);
  AssertEquals('and a written count keeps its own', 5, counted.Count);
end;

procedure TAdvChartPictorialRuleTest.TestAWrittenCountKillsTheMarginsValueButNotItsFlag;
var a, b, c: TTyPictorialRun;
begin
  { PASS ONE IS SKIPPED OUTRIGHT for a written count and pass two re-solves the
    margin, so the NUMBER in symbolMargin cannot change anything. The trailing
    bang still can, because it changes pass two's divisor. }
  a := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":4,"symbolMargin":0'),
    20, 120, 120, 20);
  b := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":4,"symbolMargin":"90%"'),
    20, 120, 120, 20);
  c := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":4,"symbolMargin":"0!"'),
    20, 120, 120, 20);
  AssertEquals(4, a.Count);
  AssertEquals(4, b.Count);
  AssertEquals('the written value is dead', a.Margin, b.Margin, 1e-9);
  AssertEquals('and so is the run it produces', a.PathLen, b.PathLen, 1e-9);
  AssertEquals(4, c.Count);
  AssertTrue('but the flag is not', Abs(a.Margin - c.Margin) > 1e-6);
end;

procedure TAdvChartPictorialRuleTest.TestARepeatTooShortForOneGlyphIsNoneRatherThanADivideByZero;
var r: TTyPictorialRun;
begin
  { UPSTREAM DIVIDES BY ZERO HERE. With an end gap, pass two's divisor is the
    COUNT itself, and a bar of no length at all counts zero -- JS carries an
    infinity through to a not-a-number path length, and the ordered comparison
    that follows RAISES on this compiler rather than answering false. Nothing
    is drawn, which is also what the JS ends up drawing.

    A BAR MERELY SHORTER THAN ITS GLYPH IS NOT THIS CASE, and that is worth
    writing down because it is the obvious fixture to reach for: such a count
    rounds UP to one, so the divisor is one and the margin simply comes out
    negative. }
  r := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":true,"symbolMargin":"0!"'),
    40, 0, 0, 40);
  AssertEquals('no glyphs', 0, r.Count);
  AssertFalse('and a finite answer to take away', IsNan(r.PathLen));
  r := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":true,"symbolMargin":"0!"'),
    40, 10, 10, 40);
  AssertEquals('a short bar rounds up to one and overlaps', 1, r.Count);

  { A ZERO-LENGTH GLYPH is the other way in: the unit is zero and pass one
    divides by it. }
  r := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":true,"symbolMargin":0'),
    0, 100, 100, 0);
  AssertEquals(0, r.Count);
  AssertFalse(IsNan(r.PathLen));
end;

procedure TAdvChartPictorialRuleTest.TestTheSlotsAreEvenlySpacedAndCentredOnTheAnchor;
var r: TTyPictorialRun; a, b, c, d: Double;
begin
  r := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":"fixed","symbolMargin":0'),
    20, 80, 80, 20);
  AssertEquals(4, r.Count);
  a := TyPictorialSlot(r, 0, 500);
  b := TyPictorialSlot(r, 1, 500);
  c := TyPictorialSlot(r, 2, 500);
  d := TyPictorialSlot(r, 3, 500);
  AssertEquals('one unit apart', 20.0, b - a, Eps);
  AssertEquals(20.0, c - b, Eps);
  AssertEquals(20.0, d - c, Eps);
  { CENTRED ON THE ANCHOR, which is what the (index - count/2 + 0.5) term is
    for -- and the division must be REAL: an odd count shifts the whole run by
    half a glyph if the two is an integer divide. }
  AssertEquals('the run straddles the anchor', 500.0, (a + d) / 2, Eps);

  r := TyPictorialRunOf(SeriesSpec(',"symbolRepeat":3,"symbolMargin":0'),
    20, 60, 60, 20);
  AssertEquals(3, r.Count);
  AssertEquals('an odd count puts its middle glyph ON the anchor',
    500.0, TyPictorialSlot(r, 1, 500), Eps);
end;

{ ==================== the marks ==================== }

procedure TAdvChartPictorialMarksTest.SetUp;
begin
  inherited SetUp;
  FCart := nil;
  FStore := nil;
  FOpt := nil;
  FValueAxis := nil;
  FList := TTyPaintList.Create;
end;

procedure TAdvChartPictorialMarksTest.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FOpt);
  FreeAndNil(FStore);
  FreeAndNil(FCart);
  inherited TearDown;
end;

procedure TAdvChartPictorialMarksTest.Given(const AValues: array of Double;
  AMin, AMax: Double);
var
  ax, ay: TTyAxis;
  sy: TTyIntervalScale;
  cats: TTyStringArray;
  i: Integer;
begin
  FreeAndNil(FStore);
  FreeAndNil(FCart);
  FCart := TTyCartesian2D.Create;
  ax := TTyAxis.Create('x', TTyOrdinalScale.Create, True);
  ax.AxisType := atCategory;
  SetLength(cats, Length(AValues));
  for i := 0 to High(AValues) do cats[i] := Chr(Ord('a') + i);
  ax.SetCategories(cats);
  ax.OnBand := True;
  sy := TTyIntervalScale.Create;
  sy.SetExtent(TyRange(AMin, AMax));
  ay := TTyAxis.Create('y', sy, False);
  FCart.AddAxis(ax);
  FCart.AddAxis(ay);
  FCart.SetRect(TyRectF(0, 0, 400, 300));

  FStore := TTyDataStore.Create;
  FStore.AddDimension('x', ddtOrdinal);
  FStore.AddDimension('y', ddtFloat);
  FStore.UseOrdinalMeta(0, ax.Categories);
  for i := 0 to High(AValues) do
    FStore.AppendRow([Double(i), AValues[i]]);

  FValueAxis := ay;
  FBinding := Default(TTySeriesBinding);
  FBinding.SeriesIndex := 0;
  FBinding.SeriesType := TyPictorialSeriesTypeName;
  FBinding.Resolved := True;
  FBinding.HasAxes := True;
  FBinding.Cart := FCart;
  FBinding.XAxis := ax;
  FBinding.YAxis := ay;
  FBinding.BaseAxis := ax;
  FBinding.ValueAxis := ay;
end;

procedure TAdvChartPictorialMarksTest.GivenSideways(
  const AValues: array of Double; AMin, AMax: Double);
var
  ax, ay: TTyAxis;
  sx: TTyIntervalScale;
  cats: TTyStringArray;
  i: Integer;
begin
  FreeAndNil(FStore);
  FreeAndNil(FCart);
  FCart := TTyCartesian2D.Create;
  sx := TTyIntervalScale.Create;
  sx.SetExtent(TyRange(AMin, AMax));
  ax := TTyAxis.Create('x', sx, True);
  ay := TTyAxis.Create('y', TTyOrdinalScale.Create, False);
  ay.AxisType := atCategory;
  SetLength(cats, Length(AValues));
  for i := 0 to High(AValues) do cats[i] := Chr(Ord('a') + i);
  ay.SetCategories(cats);
  ay.OnBand := True;
  FCart.AddAxis(ax);
  FCart.AddAxis(ay);
  FCart.SetRect(TyRectF(0, 0, 400, 300));

  FStore := TTyDataStore.Create;
  FStore.AddDimension('x', ddtFloat);
  FStore.AddDimension('y', ddtOrdinal);
  FStore.UseOrdinalMeta(1, ay.Categories);
  for i := 0 to High(AValues) do
    FStore.AppendRow([AValues[i], Double(i)]);

  FValueAxis := ax;
  FBinding := Default(TTySeriesBinding);
  FBinding.SeriesIndex := 0;
  FBinding.SeriesType := TyPictorialSeriesTypeName;
  FBinding.Resolved := True;
  FBinding.HasAxes := True;
  FBinding.Cart := FCart;
  FBinding.XAxis := ax;
  FBinding.YAxis := ay;
  FBinding.BaseAxis := ay;
  FBinding.ValueAxis := ax;
end;

function TAdvChartPictorialMarksTest.Build(const ABody: string): Integer;
var v: TTySeriesVisual;
begin
  FList.Clear;
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue('the fixture parses',
    FOpt.SetOptionText('{"series":[{"type":"pictorialBar","data":[1]'
      + ABody + '}]}'));
  v := TySeriesVisual($FF3366CC);
  v.Pictorial := TyPictorialSpecOf(FOpt, 0);
  Result := TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList);
end;

function TAdvChartPictorialMarksTest.GlyphCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to FList.Count - 1 do
    if FList.Element(i).Silent then Inc(Result);
end;

function TAdvChartPictorialMarksTest.GlyphAt(AIndex: Integer): TTyChartElement;
var i, n: Integer;
begin
  n := 0;
  Result := Default(TTyChartElement);
  for i := 0 to FList.Count - 1 do
    if FList.Element(i).Silent then
    begin
      if n = AIndex then Exit(FList.Element(i));
      Inc(n);
    end;
  AssertTrue('there is a glyph ' + IntToStr(AIndex), False);
end;

function TAdvChartPictorialMarksTest.BarRectAt(AIndex: Integer): TTyChartElement;
var i, n: Integer;
begin
  n := 0;
  Result := Default(TTyChartElement);
  for i := 0 to FList.Count - 1 do
    if not FList.Element(i).Silent then
    begin
      if n = AIndex then Exit(FList.Element(i));
      Inc(n);
    end;
  AssertTrue('there is a bar rect ' + IntToStr(AIndex), False);
end;

function TAdvChartPictorialMarksTest.CentreOf(
  const AElement: TTyChartElement): TTyPointF;
var b: TTyRectF;
begin
  if AElement.Shape.Kind in [cskCircle, cskEllipse] then
    Exit(TyPointF(AElement.Shape.CX, AElement.Shape.CY));
  b := TyShapeBounds(AElement.Shape);
  Result := TyPointF((b.Left + b.Right) / 2, (b.Top + b.Bottom) / 2);
end;

function TAdvChartPictorialMarksTest.VerticesAbove(
  const AElement: TTyChartElement): Integer;
var i: Integer; c: TTyPointF;
begin
  Result := 0;
  c := CentreOf(AElement);
  for i := 0 to High(AElement.Shape.Points) do
    if AElement.Shape.Points[i].Y < c.Y - 0.5 then Inc(Result);
end;

procedure TAdvChartPictorialMarksTest.TestOneGlyphAndOneRectPerDatum;
begin
  Given([10, 20, 30], 0, 100);
  AssertEquals('three data, six elements', 6, Build(''));
  AssertEquals('three of them glyphs', 3, GlyphCount);
end;

procedure TAdvChartPictorialMarksTest.TestTheRectIsTheOnlyThingAPointerCanLandOn;
var i, hittable: Integer;
begin
  Given([10, 20, 30], 0, 100);
  Build('');
  hittable := 0;
  for i := 0 to FList.Count - 1 do
    if not FList.Element(i).Silent then Inc(hittable);
  { ONE TARGET PER DATUM. Two would report the same datum twice on a hover,
    and a glyph cut in half by the clip is the worse of the two targets --
    upstream keeps the same transparent rect for the same reason. }
  AssertEquals(3, hittable);
  AssertEquals('and it is the rect', Ord(cskRect),
    Ord(BarRectAt(0).Shape.Kind));
end;

procedure TAdvChartPictorialMarksTest.TestTheRectCarriesNoInkAtAll;
var el: TTyChartElement;
begin
  Given([30], 0, 100);
  Build('');
  el := BarRectAt(0);
  AssertFalse('no fill', el.Style.HasFill);
  AssertEquals('and no stroke worth drawing', 0.0,
    el.Style.StrokeWidthLogical, Eps);
  { AND THE GLYPH DOES HAVE INK -- without this the assertion above passes on
    a builder that drew nothing at all. }
  AssertTrue('the glyph is filled', GlyphAt(0).Style.HasFill);
end;

procedure TAdvChartPictorialMarksTest.TestTheGlyphStartsOnTheBaselineRatherThanOnTheBarsMiddle;
var c: TTyPointF; bar: TTyRectF;
begin
  { A FULL-HEIGHT BAR on a 0..100 axis over 300px: the value 100 is at y 0 and
    the baseline at y 300. With the default `start` the glyph's NEAR EDGE sits
    on the baseline -- which for a full-length glyph is indistinguishable from
    centring it, so the half-size case below is the one that separates the
    three positions. }
  Given([100], 0, 100);
  Build('');
  bar := TyShapeBounds(BarRectAt(0).Shape);
  AssertEquals('the bar runs the whole plot', 0.0, bar.Top, 1e-6);
  AssertEquals(300.0, bar.Bottom, 1e-6);
  c := CentreOf(GlyphAt(0));
  AssertEquals('and the glyph is a full-length one', 150.0, c.Y, 1e-6);

  { AT 30% OF THE BOUNDING LENGTH the near edge still sits on the baseline, so
    the centre is 45px up and nowhere near the middle. }
  Build(',"symbolSize":["100%","30%"]');
  c := CentreOf(GlyphAt(0));
  AssertEquals(300.0 - 45.0, c.Y, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestPositionEndHangsItOffTheFarEnd;
var c: TTyPointF;
begin
  Given([100], 0, 100);
  Build(',"symbolSize":["100%","30%"],"symbolPosition":"end"');
  c := CentreOf(GlyphAt(0));
  { THE FAR END OF THE BOUNDING REGION, which without bounding data is the
    value itself: the glyph's far edge sits on y 0 and its centre 45px below. }
  AssertEquals(45.0, c.Y, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestPositionCentreSplitsTheDifference;
var c: TTyPointF;
begin
  Given([100], 0, 100);
  Build(',"symbolSize":["100%","30%"],"symbolPosition":"center"');
  c := CentreOf(GlyphAt(0));
  AssertEquals('halfway along the bounding length', 150.0, c.Y, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestASizeInPercentMeasuresTheBandAcrossAndTheBarAlong;
var b: TTyRectF;
begin
  { THE TWO AXES DO NOT SHARE A BASE, and a square glyph would hide it. ACROSS
    the bar a percentage is of the COLUMN; ALONG it, of the bounding length --
    here the bar's own 150px. }
  Given([50], 0, 100);
  Build(',"symbolSize":["50%","40%"]');
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals('40% of the bar is 60px tall', 60.0, b.Bottom - b.Top, 1e-6);
  AssertEquals('and 50% across is half the solved column',
    TyBarColumnForOneSeries(400.0).Width / 2, b.Right - b.Left, 1e-6);
  AssertTrue('which is not 60 either',
    Abs((b.Right - b.Left) - 60.0) > 1.0);
end;

procedure TAdvChartPictorialMarksTest.TestARepeatMeasuresBothPercentagesAgainstTheBand;
var b: TTyRectF;
begin
  { WITH A REPEAT THE VALUE-AXIS BASE CHANGES to the column width as well,
    which is what makes a repeating glyph roughly square and stops it
    stretching down the bar. Same option, two different heights. }
  Given([50], 0, 100);
  Build(',"symbolSize":["50%","40%"]');
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals(60.0, b.Bottom - b.Top, 1e-6);

  Build(',"symbolSize":["50%","40%"],"symbolRepeat":true');
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals('now it is 40% of the column',
    TyBarColumnForOneSeries(400.0).Width * 0.4, b.Bottom - b.Top, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestRepeatDrawsAColumnAndTheGlyphsAreEvenlySpaced;
var a, b, c: TTyPointF;
begin
  Given([100], 0, 100);
  Build(',"symbolSize":[10,20],"symbolRepeat":"fixed","symbolMargin":0');
  AssertEquals('fifteen twenty-pixel glyphs in a 300px bar', 15, GlyphCount);
  a := CentreOf(GlyphAt(0));
  b := CentreOf(GlyphAt(1));
  c := CentreOf(GlyphAt(2));
  AssertEquals('evenly spaced', b.Y - a.Y, c.Y - b.Y, 1e-6);
  AssertEquals('by one glyph each', 20.0, Abs(b.Y - a.Y), 1e-6);
  AssertEquals('and all on one line', a.X, b.X, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestBoundingDataMovesTheGlyphWithoutMovingTheData;
var c: TTyPointF; bar: TTyRectF;
begin
  { THE BOUNDING LENGTH REPLACES THE VALUE RECT FOR SIZING AND ANCHORING and
    for nothing else. A bar of 50 told to bound at 100 draws a full-height
    glyph, and the bar rect grows to cover it because the rect is the union of
    the two. }
  Given([50], 0, 100);
  Build('');
  c := CentreOf(GlyphAt(0));
  AssertEquals('without it the glyph is the bar', 225.0, c.Y, 1e-6);

  Build(',"symbolBoundingData":100');
  c := CentreOf(GlyphAt(0));
  AssertEquals('with it the glyph is the whole axis', 150.0, c.Y, 1e-6);
  bar := TyShapeBounds(BarRectAt(0).Shape);
  AssertEquals('and the rect covers it', 0.0, bar.Top, 1e-6);
  AssertEquals(300.0, bar.Bottom, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestTheBarRectGrowsToCoverAGlyphThatOverhangsIt;
var bar: TTyRectF;
begin
  { A GLYPH PUSHED PAST THE VALUE still has to be inside the rect a label is
    placed against, or the words land on top of the icon. }
  Given([20], 0, 100);
  Build(',"symbolBoundingData":80,"symbolPosition":"end"');
  bar := TyShapeBounds(BarRectAt(0).Shape);
  AssertEquals('the bar reaches the glyph rather than the datum',
    300.0 - 240.0, bar.Top, 1e-6);
  AssertEquals('and still stands on the baseline', 300.0, bar.Bottom, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestClipCutsAtTheValueAndLeavesTheBandAlone;
var r: TTyRectF;
begin
  Given([40], 0, 100);
  Build(',"symbolBoundingData":100,"symbolClip":true');
  AssertTrue('there is a clip', GlyphAt(0).HasClip);
  r := GlyphAt(0).ClipRect;
  AssertEquals('it runs from the baseline to the value',
    300.0, r.Bottom, 1e-6);
  AssertEquals(300.0 - 120.0, r.Top, 1e-6);
  { AND ACROSS THE BAR IT DOES NOT CUT. Upstream spans the whole canvas there:
    a glyph wider than its own column is meant to hang over the edge. }
  AssertTrue('wider than any canvas', r.Right - r.Left > 10000);
end;

procedure TAdvChartPictorialMarksTest.TestWithoutClipNothingIsCutAndTheRectNeverIs;
begin
  Given([40], 0, 100);
  Build(',"symbolBoundingData":100');
  AssertFalse('nothing is cut by default', GlyphAt(0).HasClip);
  { THE RECT NEVER CARRIES ONE EITHER: it is a hover target, and clipping a
    target would make half a bar unhittable. }
  Build(',"symbolBoundingData":100,"symbolClip":true');
  AssertFalse('and the rect is never clipped', BarRectAt(0).HasClip);
  AssertTrue('while the glyph is', GlyphAt(0).HasClip);
end;

procedure TAdvChartPictorialMarksTest.TestASidewaysChartCountsAlongXAndBandsAlongY;
var c: TTyPointF; b, bar: TTyRectF;
begin
  { THE BASE AXIS IS THE SPINE, and the whole builder is written through that
    rather than through x and y. On a 0..100 value x over 400px a bar of 100
    runs from x 0 to x 400 and the band is on y. }
  GivenSideways([100], 0, 100);
  Build(',"symbolSize":["30%","100%"]');
  bar := TyShapeBounds(BarRectAt(0).Shape);
  AssertEquals('the bar runs the plot horizontally', 0.0, bar.Left, 1e-6);
  AssertEquals(400.0, bar.Right, 1e-6);
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals('30% of the bar is 120px wide', 120.0, b.Right - b.Left, 1e-6);
  c := CentreOf(GlyphAt(0));
  AssertEquals('and it starts at the axis, not at the value',
    60.0, c.X, 1e-6);
  AssertEquals('centred in its band', 150.0, c.Y, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestAnInvertedAxisMirrorsTheGlyphRatherThanTurningIt;
var upright, flipped: TTyChartElement; c: TTyPointF; i, n: Integer;
begin
  { A BAR THAT POINTS THE OTHER WAY POINTS ITS ICON THE OTHER WAY. Upstream
    multiplies the glyph's scale along the value axis by the pixel sign, and a
    negative scale is a MIRROR -- so a triangle that pointed up now points
    down. A port that took the absolute value draws both of them upright.

    ASSERTED BY COUNTING VERTICES ON EACH SIDE of the glyph's own centre,
    because that is the one statement a half turn cannot also satisfy: a
    triangle mirrored has two vertices above and one below, and a triangle
    rotated a half turn has the same -- but so would a triangle left alone if
    the count were taken on the bounding box instead. }
  Given([50], 0, 100);
  Build(',"symbol":"triangle","symbolSize":[20,40]');
  upright := GlyphAt(0);
  AssertEquals('it is a polygon', Ord(cskPolygon), Ord(upright.Shape.Kind));
  AssertEquals('three vertices', 3, Length(upright.Shape.Points));
  AssertEquals('one of them above the centre', 1, VerticesAbove(upright));

  { THE SAME DATA ON AN INVERTED AXIS. The bar now grows downward from the top,
    so the pixel sign flips and the glyph turns over with it. }
  FValueAxis.Inverse := True;
  Build(',"symbol":"triangle","symbolSize":[20,40]');
  flipped := GlyphAt(0);
  AssertEquals('still three vertices', 3, Length(flipped.Shape.Points));
  AssertEquals('and now two of them are above', 2, VerticesAbove(flipped));

  { AND THE REFLECTION COMES BEFORE THE TURN. The two do not commute, so the
    port negates the angle and reflects afterwards -- the same transform by the
    identity M(R(-a)) = R(a)(M), not an approximation of it. Leave the angle
    alone and the glyph turns the other way.

    NOTHING ELSE IN THIS FILE CAN SEE IT, because no other fixture both mirrors
    a glyph and turns it. A quarter turn of a triangle on the inverted axis
    puts its apex to the RIGHT; the wrong order puts it to the left. }
  Build(',"symbol":"triangle","symbolSize":[40,40],"symbolRotate":90');
  flipped := GlyphAt(0);
  c := CentreOf(flipped);
  AssertEquals('centred where the run put it', 200.0, c.X, 1e-6);
  AssertEquals(20.0, c.Y, 1e-6);
  n := 0;
  for i := 0 to High(flipped.Shape.Points) do
    if flipped.Shape.Points[i].X > c.X + 0.5 then Inc(n);
  AssertEquals('one vertex to the right, so the apex points that way', 1, n);
end;

procedure TAdvChartPictorialMarksTest.TestABarOfNoLengthStillPointsTheWayPositiveValuesGo;
var c: TTyPointF; bar: TTyRectF;
begin
  { THE PIXEL SIGN IS NEVER ZERO, and upstream says why beside it: a zero sign
    makes the glyph's scale zero, and a zero scale makes an unscaled stroke
    width not a number. So a bar of exactly no length still has a direction,
    and the glyph sits ENTIRELY on the positive side of the base line rather
    than straddling it.

    NO OTHER FIXTURE HAS A BAR OF ZERO LENGTH, which is the only place the
    tie-break runs -- a mutant that answered zero there lived through every
    other test in this file. }
  Given([0], 0, 100);
  Build(',"symbolSize":[20,20]');
  c := CentreOf(GlyphAt(0));
  AssertEquals('ten pixels above the base line, not on it', 290.0, c.Y, 1e-6);
  bar := TyShapeBounds(BarRectAt(0).Shape);
  AssertEquals('and the bar rect covers the glyph', 280.0, bar.Top, 1e-6);
  AssertEquals(300.0, bar.Bottom, 1e-6);

  { THE OTHER HALF OF THE TIE-BREAK. Upstream splits it asymmetrically --
    `>= 0` when pixels grow with the value, `> 0` when they shrink -- and both
    halves say the same thing: the glyph faces the way positive values go. On
    a sideways chart that is to the RIGHT of the axis. }
  GivenSideways([0], 0, 100);
  Build(',"symbolSize":[20,20]');
  c := CentreOf(GlyphAt(0));
  AssertEquals('ten pixels to the right of it', 10.0, c.X, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestTheDirectionComesFromTheBoundingLengthNotFromTheData;
var c: TTyPointF; bar: TTyRectF;
begin
  { THE SIGN IS THE BOUNDING REGION'S, NOT THE DATUM'S, and the two only part
    company when bounding data or a repeat is written -- which is why every
    other fixture here reads the same either way.

    BOUNDING DATA BELOW THE BASE LINE POINTS THE GLYPH DOWN, however odd that
    picture is: the author asked for a region that runs the other way, and the
    glyph is sized and anchored in that region. }
  GivenSideways([50], 0, 100);
  Build(',"symbolBoundingData":-50');
  c := CentreOf(GlyphAt(0));
  AssertEquals('the glyph runs left of the axis, not right',
    -100.0, c.X, 1e-6);
  bar := TyShapeBounds(BarRectAt(0).Shape);
  AssertEquals(-200.0, bar.Left, 1e-6);
  AssertEquals(0.0, bar.Right, 1e-6);

  { AND THE SAME ON THE OTHER ORIENTATION, whose tie-break is the other one.
    Here the base line is at y 300 and a bounding datum of -50 is BELOW it. }
  Given([50], 0, 100);
  Build(',"symbolBoundingData":-50');
  c := CentreOf(GlyphAt(0));
  AssertEquals('below the base line', 375.0, c.Y, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestTheRepeatDirectionDecidesWhichGlyphIsDrawnFirst;
begin
  { A SLOT IS GEOMETRY; THE INDEX IS ORDER. `symbolRepeatDirection` moves no
    glyph at all -- upstream says so beside the same expression -- it decides
    which end of the run is BUILT first, and therefore which glyph is painted
    over which.

    NO OTHER TEST HERE CAN SEE IT, because the positions it produces are
    symmetric: a test that checks only the spacing stays green whichever way
    the run is walked. }
  Given([100], 0, 100);
  Build(',"symbolSize":[10,20],"symbolRepeat":"fixed","symbolMargin":0');
  AssertEquals(15, GlyphCount);
  AssertEquals('by default the run is built from the far end',
    290.0, CentreOf(GlyphAt(0)).Y, 1e-6);
  AssertEquals('and finishes on the base line',
    10.0, CentreOf(GlyphAt(14)).Y, 1e-6);

  Build(',"symbolSize":[10,20],"symbolRepeat":"fixed","symbolMargin":0,'
    + '"symbolRepeatDirection":"start"');
  AssertEquals('the same fifteen glyphs', 15, GlyphCount);
  AssertEquals('built from the base line instead',
    10.0, CentreOf(GlyphAt(0)).Y, 1e-6);
  AssertEquals('and finishing at the far end',
    290.0, CentreOf(GlyphAt(14)).Y, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestABoundingPairTakesTheEndTheBarRunsTowards;
var b: TTyRectF;
begin
  { A PAIR NAMES AN INTERVAL and the bar takes the end on its OWN side of the
    base line -- sorted in pixels rather than in values, because the axis may
    run either way.

    ON A SIDEWAYS CHART, which is the orientation that can show it: a bar on a
    vertical value axis always runs towards smaller y, so it would take the
    same end of the pair whatever the rule said. }
  GivenSideways([50], 0, 100);
  Build(',"symbolBoundingData":[-50,75]');
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals('the far end is 75, three hundred pixels out',
    300.0, b.Right - b.Left, 1e-6);
  AssertEquals('so the glyph starts on the axis and runs right',
    150.0, CentreOf(GlyphAt(0)).X, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestARepeatWithoutBoundingDataFillsThePlotNotTheBar;
begin
  { A REPEAT WITH NO BOUNDING DATA IS COUNTED AGAINST THE PLOT, and `'fixed'`
    is what makes that visible: it keeps the whole column instead of cutting it
    back, so a quarter-height bar still carries a full plot's worth of glyphs
    and the clip is what would show how many were earned.

    THE OTHER TWO REPEAT FIXTURES CANNOT SEE IT. One draws a full-height bar,
    where the plot and the bar are the same length; the other asserts a size
    measured against the band, and its count comes out the same either way. }
  Given([25], 0, 100);
  Build(',"symbolSize":[10,20],"symbolRepeat":"fixed","symbolMargin":0');
  AssertEquals('the whole plot''s worth, not the bar''s', 15, GlyphCount);
end;

procedure TAdvChartPictorialMarksTest.TestAGapDrawsNothingAtAllForThatRow;
begin
  Given([10, 20, 30], 0, 100);
  AssertEquals(6, Build(''));
  { NOT A ZERO-LENGTH BAR AND NOT A LONE GLYPH ON THE BASELINE: a gap is no
    measurement, so neither of the datum's two elements is emitted. }
  Given([10, NaN, 30], 0, 100);
  AssertEquals('one row fewer is two elements fewer', 4, Build(''));
  AssertEquals(2, GlyphCount);
end;

procedure TAdvChartPictorialMarksTest.TestTheOffsetMovesTheGlyphAndLeavesTheBandAlone;
var c0, c1: TTyPointF; b0, b1: TTyRectF;
begin
  { AN OBLONG GLYPH, and that is the whole fixture. Each component of the
    offset is a percentage of the glyph's size on the SAME SCREEN AXIS, and a
    square glyph makes the two bases one number -- a mutant that measured the
    vertical offset against the width lived through this test until the glyph
    stopped being 20 by 20. }
  Given([50], 0, 100);
  Build(',"symbolSize":[20,40]');
  c0 := CentreOf(GlyphAt(0));
  b0 := TyShapeBounds(BarRectAt(0).Shape);

  { AND IT IS IN SCREEN X AND Y, not along and across: upstream adds it to the
    two components of the position without remapping either, so on a
    horizontal bar chart it still moves the glyph the way the author's own x
    and y point. }
  Build(',"symbolSize":[20,40],"symbolOffset":["50%","50%"]');
  c1 := CentreOf(GlyphAt(0));
  b1 := TyShapeBounds(BarRectAt(0).Shape);
  AssertEquals('moved right by half its WIDTH', c0.X + 10.0, c1.X, 1e-6);
  AssertEquals('and down by half its HEIGHT', c0.Y + 20.0, c1.Y, 1e-6);
  { THE BAND IS THE COLUMN'S AND THE OFFSET DOES NOT TOUCH IT: only the run's
    far end can move the bar rect, and here it is still short of the data. }
  AssertEquals('the band did not move', b0.Left, b1.Left, 1e-6);
  AssertEquals(b0.Right, b1.Right, 1e-6);
  AssertEquals('nor did the length', b0.Top, b1.Top, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestEveryGlyphAnswersForItsOwnRow;
var i: Integer;
begin
  Given([10, 20, 30], 0, 100);
  Build(',"symbolRepeat":3,"symbolSize":[8,8]');
  { NINE GLYPHS AND THREE RECTS, and every one of the twelve names the row it
    was built from -- a repeat that stamped the run index instead would put
    the tooltip on the wrong category. }
  AssertEquals(9, GlyphCount);
  for i := 0 to 2 do
  begin
    AssertEquals('rect ' + IntToStr(i), i, BarRectAt(i).Datum.DataIndex);
    AssertEquals('glyph ' + IntToStr(i * 3), i, GlyphAt(i * 3).Datum.DataIndex);
    AssertEquals('glyph ' + IntToStr(i * 3 + 2), i,
      GlyphAt(i * 3 + 2).Datum.DataIndex);
  end;
end;

procedure TAdvChartPictorialMarksTest.TestASymbolOfNoneDrawsTheRectAndNothingElse;
begin
  Given([10, 20], 0, 100);
  { `symbol: 'none'` IS AN INSTRUCTION. The bar rect stays, because the datum
    is still there to be hovered and labelled; the glyph does not. }
  AssertEquals(2, Build(',"symbol":"none"'));
  AssertEquals(0, GlyphCount);
end;

procedure TAdvChartPictorialMarksTest.TestTheDefaultGlyphIsSolidRatherThanTheLinesRing;
begin
  Given([50], 0, 100);
  Build('');
  { EVERY OTHER SERIES' DEFAULT SYMBOL IS THE LINE'S HOLLOW CIRCLE and a
    pictorial bar's is a SOLID one. Taking the shared default drew a ring,
    which reads as a missing fill rather than as a choice. }
  AssertTrue('filled', GlyphAt(0).Style.HasFill);
  AssertEquals('in the series colour', LongWord($FF3366CC),
    LongWord(GlyphAt(0).Style.FillColor));

  { AND AN `empty` SYMBOL IS STILL HOLLOW when the author asks for one. }
  Build(',"symbol":"emptyCircle"');
  AssertEquals('the pen takes the colour instead', LongWord($FF3366CC),
    LongWord(GlyphAt(0).Style.StrokeColor));
end;

procedure TAdvChartPictorialMarksTest.TestAStackedPictorialStandsOnTheOneBelowIt;
var stack: TTySeriesStack; v: TTySeriesVisual; c: TTyPointF; b: TTyRectF;
begin
  { THE FLOOR IS THE SEGMENT'S OWN, not the axis baseline. The store carries
    the cumulative total in a third column and the segment's own value in the
    second, and the glyph has to start where the one below it stopped. }
  Given([40], 0, 100);
  FStore.AddDimension('__stacked', ddtFloat);
  FStore.SetCalculated(2, 0, 70);

  FList.Clear;
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue(FOpt.SetOptionText(
    '{"series":[{"type":"pictorialBar","data":[1]}]}'));
  v := TySeriesVisual($FF3366CC);
  v.Pictorial := TyPictorialSpecOf(FOpt, 0);
  stack := TyNoStack;
  stack.Stacked := True;
  stack.HasBelow := True;
  stack.ResultCol := 2;
  AssertEquals(2, TyBuildSeriesMarks(FBinding, FStore, stack, v, FList));

  { 70 CUMULATIVE OVER 40 OF ITS OWN: the segment runs from 30 to 70, which on
    a 0..100 axis over 300px is y 210 up to y 90 -- so a full-length glyph is
    120 tall and centred at 150, not 210 tall and standing on the axis. }
  c := CentreOf(GlyphAt(0));
  AssertEquals(150.0, c.Y, 1e-6);
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals('and it is 120 tall, not 210', 120.0, b.Bottom - b.Top, 1e-6);

  { AND BOUNDING DATA IS STILL MEASURED FROM ZERO, not from that floor. The
    two are the same place on every unstacked chart, which is why this is the
    test that can tell them apart: the segment stands at 30, and a bounding
    datum of 100 is three hundred pixels from the ZERO line rather than two
    hundred and ten from the segment's own foot. }
  FList.Clear;
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue(FOpt.SetOptionText(
    '{"series":[{"type":"pictorialBar","data":[1],'
    + '"symbolBoundingData":100}]}'));
  v := TySeriesVisual($FF3366CC);
  v.Pictorial := TyPictorialSpecOf(FOpt, 0);
  AssertEquals(2, TyBuildSeriesMarks(FBinding, FStore, stack, v, FList));
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals('three hundred tall', 300.0, b.Bottom - b.Top, 1e-6);
  AssertEquals('and centred sixty pixels down the plot',
    60.0, CentreOf(GlyphAt(0)).Y, 1e-6);
end;

procedure TAdvChartPictorialMarksTest.TestARowCanWriteEveryOneOfTheseOptionsForItself;
var v: TTySeriesVisual; b: TTyRectF;
begin
  { EVERY PICTORIAL OPTION IS READ THROUGH THE ITEM MODEL UPSTREAM, which is
    how one series draws a different icon for every row -- and it is how most
    of the gallery's pictorial charts are written. A port that read only the
    series level draws the same circle nine times and looks like it lost the
    option rather than the row.

    ASSERTED THROUGH THE STORE rather than through the option text, because
    that is the path the builder takes: the data item's scalar leaves are
    parked under their dotted names and read back by row. }
  Given([50, 50, 50], 0, 100);
  FList.Clear;
  FreeAndNil(FOpt);
  FOpt := TTyChartOption.Create;
  AssertTrue(FOpt.SetOptionText(
    '{"series":[{"type":"pictorialBar","symbolSize":[20,20],'
    + '"data":[1,2,3]}]}'));
  v := TySeriesVisual($FF3366CC);
  v.Pictorial := TyPictorialSpecOf(FOpt, 0);
  { The store is the fixture's, so the overrides are written here the way the
    builder parks them -- one scalar leaf per key, under its own name. }
  FStore.SetOverride(1, TyOverrideKey('symbol'), TyDataText('triangle'));
  FStore.SetOverride(1, TyOverrideKey('symbolSize'), TyDataNum(40));
  FStore.SetOverride(1, TyOverrideKey('symbolPosition'), TyDataText('end'));
  FStore.SetOverride(2, TyOverrideKey('symbol'), TyDataText('triangle'));
  FStore.SetOverride(2, TyOverrideKey('symbolSize'), TyDataNum(40));
  { A WORD THE READER DOES NOT KNOW, on a row rather than on the series. It
    lands on the ternary's last arm and CENTRES the glyph -- the same two kinds
    of nothing the series level has, and the row level has to split them the
    same way. }
  FStore.SetOverride(2, TyOverrideKey('symbolPosition'), TyDataText('centre'));
  { AND AN ANGLE THAT OVERFLOWS. A row's value goes through the same clamp the
    series' does, and it has to: 1e308 degrees times Pi/180 is infinity, and
    the sine of infinity does not return -- it raises. }
  FStore.SetOverride(2, TyOverrideKey('symbolRotate'), TyDataNum(1e308));
  AssertEquals(6, TyBuildSeriesMarks(FBinding, FStore, TyNoStack, v, FList));

  { ROW ZERO SAID NOTHING and keeps the series' 20px circle. }
  AssertEquals('a circle', Ord(cskCircle), Ord(GlyphAt(0).Shape.Kind));
  b := TyShapeBounds(GlyphAt(0).Shape);
  AssertEquals(20.0, b.Bottom - b.Top, 1e-6);

  { ROW ONE OVERRODE THREE OF THEM AT ONCE, and all three have to bite: the
    shape, the size, and where along the bar it sits. }
  AssertEquals('a triangle', Ord(cskPolygon), Ord(GlyphAt(1).Shape.Kind));
  b := TyShapeBounds(GlyphAt(1).Shape);
  AssertEquals('at its own size', 40.0, b.Bottom - b.Top, 1e-6);
  AssertEquals('hung off the far end of its own bar',
    150.0 + 20.0, CentreOf(GlyphAt(1)).Y, 1e-6);

  { ROW TWO MISSPELLED ITS POSITION and is therefore centred on the bounding
    length, not parked on the base line where a fallback to `start` would put
    it. }
  AssertEquals('centred, not started', 225.0, CentreOf(GlyphAt(2)).Y, 1e-6);

  { AND ITS ANGLE CAME BACK FINITE. A full turn is indistinguishable from none,
    which is the point: the clamp has to leave a drawable glyph rather than a
    triangle of not-a-numbers. }
  b := TyShapeBounds(GlyphAt(2).Shape);
  AssertFalse('the glyph has real coordinates', IsNan(b.Left) or IsNan(b.Top));
  AssertEquals('forty across', 40.0, b.Right - b.Left, 1e-6);
  AssertEquals('forty down', 40.0, b.Bottom - b.Top, 1e-6);
  AssertEquals('and still one vertex above its centre',
    1, VerticesAbove(GlyphAt(2)));
end;

{ ==================== the picture ==================== }

procedure TAdvChartPictorialDrawTest.SetUp;
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

procedure TAdvChartPictorialDrawTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartPictorialDrawTest.Draw(const AOption: string);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartPictorialDrawTest.Diagnostics: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

function TAdvChartPictorialDrawTest.InkIn(AL, AT, AR, AB: Integer): Integer;
var x, y: Integer; p: TBGRAPixel;
begin
  Result := 0;
  for y := Max(0, AT) to Min(cH - 1, AB - 1) do
    for x := Max(0, AL) to Min(cW - 1, AR - 1) do
    begin
      p := FBmp.GetPixel(x, y);
      { THE SERIES COLOUR AND NOTHING ELSE. A grid line, an axis and a label
        are all grey, so a plain "not white" count would be dominated by the
        furniture and could not see a glyph move. }
      if (p.alpha = 255) and (p.blue > p.red + 30) and (p.blue > 100) then
        Inc(Result);
    end;
end;

function TAdvChartPictorialDrawTest.InkPixels: Integer;
begin
  Result := InkIn(0, 0, cW, cH);
end;

procedure TAdvChartPictorialDrawTest.TestAPictorialBarDrawsAtAll;
var ink: Integer;
begin
  Draw('{"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"pictorialBar","symbol":"rect",'
    + '"itemStyle":{"color":"#3366cc"},"data":[10,20,30]}]}');
  ink := InkPixels;
  AssertTrue(Format('there is series-coloured ink (%d px)', [ink]), ink > 400);
end;

procedure TAdvChartPictorialDrawTest.TestItSaysNothingAboutHavingNoRenderer;
begin
  Draw('{"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"pictorialBar","data":[10,20,30]}]}');
  AssertEquals('a pictorial bar draws now, got: ' + Diagnostics,
    '', Diagnostics);
end;

procedure TAdvChartPictorialDrawTest.TestTheGlyphsAreWhereTheDataIsAndNotWhereItIsNot;
var lo, hi: Integer;
begin
  { THREE CATEGORIES, THE LAST ONE THE TALLEST. Counting in the top half and
    the bottom half is the one thing a picture can say that the paint list
    cannot: that the ink really reached the canvas, the right way up. }
  Draw('{"grid":{"left":40,"right":10,"top":20,"bottom":30},'
    + '"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"min":0,"max":100},'
    + '"series":[{"type":"pictorialBar","symbol":"rect",'
    + '"itemStyle":{"color":"#3366cc"},'
    + '"symbolSize":["60%","100%"],"data":[10,10,100]}]}');
  hi := InkIn(0, 20, cW, cH div 2);
  lo := InkIn(0, cH div 2, cW, cH - 30);
  AssertTrue(Format('the tall one reaches the top half (%d px)', [hi]),
    hi > 200);
  AssertTrue(Format('and there is more of it lower down (%d vs %d)',
    [lo, hi]), lo > hi);
end;

procedure TAdvChartPictorialDrawTest.TestClipReallyRemovesInk;
const
  cHead = '{"grid":{"left":40,"right":10,"top":20,"bottom":30},'
    + '"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"min":0,"max":100},'
    + '"series":[{"type":"pictorialBar","symbol":"rect",'
    + '"itemStyle":{"color":"#3366cc"},"symbolBoundingData":100,'
    + '"symbolSize":["60%","100%"],"data":[25]';
var whole, clipped: Integer;
begin
  { THE CLIP IS THE ONE FEATURE HERE WITH NO GEOMETRY OF ITS OWN -- the element
    keeps its full shape and the renderer cuts it -- so the paint list cannot
    show it working. This is the assertion that the rectangle reaches the
    painter at all. }
  Draw(cHead + '}]}');
  whole := InkPixels;
  Draw(cHead + ',"symbolClip":true}]}');
  clipped := InkPixels;
  AssertTrue(Format('the unclipped glyph is the whole axis (%d px)', [whole]),
    whole > 3000);
  AssertTrue(Format('the clipped one is about a quarter of it (%d of %d)',
    [clipped, whole]),
    (clipped > whole div 8) and (clipped < whole div 2));
end;

procedure TAdvChartPictorialDrawTest.TestASeriesCanSayWhichOfTwoPicturesIsOnTop;
const
  cHead = '{"grid":{"left":40,"right":10,"top":20,"bottom":30},'
    + '"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"min":0,"max":100},"series":[';
  cRed = '{"type":"pictorialBar","symbol":"rect","name":"r",'
    + '"itemStyle":{"color":"#ff0000"},"symbolSize":["60%","100%"],'
    + '"data":[100]';
  cGreen = '{"type":"pictorialBar","symbol":"rect","name":"g",'
    + '"itemStyle":{"color":"#00ff00"},"symbolSize":["60%","100%"],'
    + '"data":[100]}';
var
  p: TBGRAPixel;
begin
  { TWO PICTORIAL SERIES OVERLAP BY DEFAULT -- barGap is '-100%' for this type,
    which is the whole reason anybody writes two of them: a foreground icon
    over a background one. Which of the two a reader sees is then decided by
    `z`, and by nothing else the author can reach.

    THE CHART THAT NEEDS IT is the gallery's own `pictorialBar-body-fill`: the
    same silhouette three times, the grey one last, and only `z: 10` on the
    two clipped series keeps the fill in front of it. }
  Draw(cHead + cRed + '}, ' + cGreen + ']}');
  p := FBmp.GetPixel(cW div 2, cH div 2);
  AssertTrue(Format('without z the later series wins (%.2x%.2x%.2x)',
    [p.red, p.green, p.blue]), (p.green > 180) and (p.red < 120));

  Draw(cHead + cRed + ',"z":10}, ' + cGreen + ']}');
  p := FBmp.GetPixel(cW div 2, cH div 2);
  AssertTrue(Format('and with it the earlier one does (%.2x%.2x%.2x)',
    [p.red, p.green, p.blue]), (p.red > 180) and (p.green < 120));

  { AND z2 BREAKS THE TIE BELOW z, which is what makes the pair two keys
    rather than one with a second name. }
  Draw(cHead + cRed + ',"z2":3}, ' + cGreen + ']}');
  p := FBmp.GetPixel(cW div 2, cH div 2);
  AssertTrue(Format('z2 sorts under z (%.2x%.2x%.2x)',
    [p.red, p.green, p.blue]), (p.red > 180) and (p.green < 120));
end;

procedure TAdvChartPictorialDrawTest.TestOnlyAWrittenClipCutsTheGlyphAtThePlotEdge;
const
  cHead = '{"grid":{"left":40,"right":10,"top":20,"bottom":30},'
    + '"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"min":0,"max":100},'
    + '"series":[{"type":"pictorialBar","symbol":"rect",'
    + '"itemStyle":{"color":"#3366cc"},"symbolBoundingData":200,'
    + '"symbolSize":["60%","100%"],"data":[100]';
var above, whole: Integer;
begin
  { `clip` IS FALSE FOR THIS TYPE and true for a bar, and the source says why
    beside the default: a pictorial chart usually hides its axes, so a glyph
    taller than the plot is expected to stand proud rather than be sliced at
    the edge. A bounding datum of 200 on a 0..100 axis puts half the glyph
    above the grid.

    A BAR ANSWERS THIS BY SHRINKING ITS RECTANGLE. A glyph cannot -- half a
    glyph is not a smaller glyph -- so the option has to reach the element's
    clip, and until it did it was solved for this type and then never read. }
  Draw(cHead + '}]}');
  above := InkIn(0, 0, cW, 20);
  whole := InkPixels;
  AssertTrue(Format('unclipped, it stands above the grid (%d px)', [above]),
    above > 200);

  Draw(cHead + ',"clip":true}]}');
  AssertEquals('asked to clip, nothing is left up there',
    0, InkIn(0, 0, cW, 20));
  AssertTrue('and the part inside the plot survives',
    InkPixels > whole div 4);
end;

procedure TAdvChartPictorialDrawTest.TestTheSolvedColumnIsWhatTheGlyphIsMeasuredAgainst;
const
  cHead = '{"grid":{"left":40,"right":10,"top":20,"bottom":30},'
    + '"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"min":0,"max":100},'
    + '"series":[{"type":"pictorialBar","symbol":"rect",'
    + '"itemStyle":{"color":"#3366cc"},'
    + '"symbolSize":["100%","100%"],"data":[100,100]';
var wide, narrow: Integer;
begin
  { THE COLUMN COMES FROM THE SOLVER, and `barWidth` is the cheapest proof.
    Without a pass of its own a pictorialBar's column is never solved at all,
    and the builder's fallback -- the width a LONE default series gets -- is
    the same 0.69 of the band, so every single-series chart reads the same
    either way. A written width is what separates them. }
  Draw(cHead + '}]}');
  wide := InkPixels;
  Draw(cHead + ',"barWidth":30}]}');
  narrow := InkPixels;
  AssertTrue(Format('the default column is most of the band (%d px)', [wide]),
    wide > 60000);
  AssertTrue(Format('and thirty pixels is thirty pixels (%d px)', [narrow]),
    (narrow > 10000) and (narrow < 25000));
end;

initialization
  RegisterTest(TAdvChartPictorialRuleTest);
  RegisterTest(TAdvChartPictorialMarksTest);
  RegisterTest(TAdvChartPictorialDrawTest);
end.
