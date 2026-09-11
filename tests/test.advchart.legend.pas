unit test.advchart.legend;
{$mode objfpc}{$H+}
{ The legend -- box layout with wrap, the icon chain, and the selection state
  that is settled before anyone clicks anything.

  MEASURED THROUGH A FAKE, so every number here is exact: ten pixels per
  character, twelve tall. The real measurer answers whatever this machine's
  fonts say, and a wrap test that depended on that would be a test of the font.

  THE FIXTURE IS DELIBERATELY LOPSIDED. A legend is full of rules about sides,
  order and pairing -- which edge is pinned, which item wraps, which of two
  colours an item takes -- and a fixture whose items are all the same width,
  whose padding is symmetric and whose items are all selected cannot tell a
  correct rule from its mirror image. So the items here have different widths,
  the padding test is [1, 2, 3, 4], and every selection test has both an on and
  an off item in it.

  THE THREE THAT A REASONABLE READING GETS WRONG, all upstream's:

    - a legend's `width` is a WRAP LIMIT, not a width: the second layout pass
      overwrites it with what the items measured;
    - `selectedMode: 'single'` changes the FIRST FRAME. It forces exactly one
      item on at load, before any click, so a legend that only drew would show
      the wrong picture immediately;
    - an unrecognised icon name is a RECT, not nothing -- which is why
      `icon: 'inherit'` on a bar series draws a sharp-cornered box. }
interface
uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Legend;

type
  TLegendMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartLegendTest = class(TTestCase)
  private
    FOpt: TTyChartOption;
    FM: ITyTextMeasurer;
    procedure SetUp; override;
    procedure TearDown; override;
    function Spec(const AText: string; AIndex: Integer = 0): TTyLegendSpec;
    { Parse, and lg the legend out on a 400x300 container at 96 PPI with one
      bar-shaped source per entry. }
    function Lay(const AText: string;
      const APotential: array of string): TTyLegendLayout;
    function LayWith(const AText: string; const APotential: array of string;
      const ASources: TTyLegendSourceArray): TTyLegendLayout;
  published
    procedure TestTheDefaultLegendSitsCentredOnTheBottomEdge;
    procedure TestTheDefaultSpecIsCoherentOnItsOwn;
    procedure TestTheCatalogsFourStaleDefaultsAreNotUsed;
    procedure TestTwoItemsAreOneItemGapApart;
    procedure TestAWidthIsAWrapLimitAndNotAWidth;
    procedure TestAnEmptyNameBreaksTheLine;
    procedure TestAVerticalLegendStacks;
    procedure TestTheKeywordDecidesWhichEdgeIsPinned;
    procedure TestARightEdgeAloneDoesNotMoveTheLegend;
    procedure TestAlignRightOnlyFollowsAVerticalLeftRight;
    procedure TestARightAlignedItemHangsLeftOfItsOwnOrigin;
    procedure TestTheFrameSurroundsTheItemsByItsPadding;
    procedure TestShowFalseLaysOutNothing;
    procedure TestEntriesComeFromTheDataWhenThereIsSome;
    procedure TestAnEmptyDataArrayAsksForNoItems;
    procedure TestDuplicateNamesAreDroppedIncludingLineBreaks;
    procedure TestSelectedFalseSwitchesAnItemOff;
    procedure TestAnyFalsyValueSwitchesAnItemOff;
    procedure TestANameTheChartCannotOfferIsNeverSelected;
    procedure TestSingleModeForcesOneItemOnAtLoad;
    procedure TestSingleModeKeepsTheFirstAlreadySelectedItem;
    procedure TestTheFormatterReplacesTheFirstNameOnly;
    procedure TestTheIconChainPrefersTheRowThenTheLegendThenTheSeries;
    procedure TestInheritOnASeriesWithNoIconOfItsOwnIsASharpRect;
    procedure TestALegendIconIsBuiltInItsBoxNotInTheUnitBox;
    procedure TestALineSeriesDrawsARuleWithAMarkerOnIt;
    procedure TestTheMarksCarryTheItemsOwnColourAndWords;
    procedure TestADeselectedItemIsGreyedRightThrough;
    procedure TestTheMarksAreSilentAndSitAboveTheSeries;
    procedure TestLeftWinsTheKeywordSwitchWhenBothEdgesNameOne;
    procedure TestTheWrapLimitIsTheContainerLessItsPadding;
    procedure TestAnItemLandingExactlyOnTheLimitDoesNotWrap;
    procedure TestTheMeasuredBlockIsWhatGetsPlaced;
    procedure TestARightAlignedRowKeepsTheGapBetweenItsInk;
    procedure TestAVerticalLegendWrapsIntoColumns;
    procedure TestTheFirstOfTwoRowsWithTheSameNameIsTheOneKept;
    procedure TestSingleModeSelectsTheFirstWhenNothingIsSelected;
    procedure TestANamedIconStopsTheSeriesDrawingItsOwn;
    procedure TestTheLineItemIsMeasuredWithItsRuleAndItsMarker;
    procedure TestARingOnASeriesWithNoLineStillGetsAPen;
    procedure TestWhichIconASeriesTypePublishes;
  end;

implementation

const
  CharW = 10.0;
  CharH = 12.0;
  Eps = 1e-9;
  Red = TTyChartColor($FFFF0000);
  Blue = TTyChartColor($FF0000FF);
  Grey = TTyChartColor($FF808080);

procedure TLegendMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := Length(AText) * CharW;
  AH := CharH;
end;

function TLegendMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

procedure TAdvChartLegendTest.SetUp;
begin
  inherited SetUp;
  FOpt := TTyChartOption.Create;
  FM := TLegendMeasurer.Create;
end;

procedure TAdvChartLegendTest.TearDown;
begin
  FM := nil;
  FreeAndNil(FOpt);
  inherited TearDown;
end;

function TAdvChartLegendTest.Spec(const AText: string;
  AIndex: Integer): TTyLegendSpec;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message,
    FOpt.SetOptionText(AText));
  Result := TyLegendSpecOf(FOpt, AIndex);
end;

{ A source per entry, all bar-shaped and all red: the icon chain and the
  geometry are what most of these tests are about, and a uniform source keeps
  them out of each other's way. }
function BarSources(ACount: Integer): TTyLegendSourceArray;
var i: Integer;
begin
  SetLength(Result, ACount);
  for i := 0 to ACount - 1 do
  begin
    Result[i] := Default(TTyLegendSource);
    Result[i].Found := True;
    Result[i].SeriesType := 'bar';
    Result[i].Colour := Red;
    Result[i].LineColour := Red;
  end;
end;

function TAdvChartLegendTest.LayWith(const AText: string;
  const APotential: array of string;
  const ASources: TTyLegendSourceArray): TTyLegendLayout;
var
  sp: TTyLegendSpec;
  entries: TTyLegendEntryArray;
  flags: TTyLegendFlags;
  f: TTyLegendFont;
begin
  sp := Spec(AText);
  entries := TyLegendEntries(FOpt, 0, APotential);
  flags := TyLegendSelected(FOpt, 0, entries, APotential, sp.SelectedMode);
  f.Name := 'x';
  f.SizeLogical := 9;
  f.Weight := 400;
  Result := TyLayoutLegend(sp, entries, flags, ASources,
    TyRectF(0, 0, 400, 300), FM, f, 96);
end;

function TAdvChartLegendTest.Lay(const AText: string;
  const APotential: array of string): TTyLegendLayout;
var
  entries: TTyLegendEntryArray;
begin
  AssertTrue('the option parsed: ' + FOpt.Error.Message,
    FOpt.SetOptionText(AText));
  entries := TyLegendEntries(FOpt, 0, APotential);
  Result := LayWith(AText, APotential, BarSources(Length(entries)));
end;

{ ==================== the box ==================== }

procedure TAdvChartLegendTest.TestTheDefaultLegendSitsCentredOnTheBottomEdge;
var
  lg: TTyLegendLayout;
begin
  { LegendModel.ts:457, :460 -- left 'center', bottom tokens.size.m = 15 --
    plus the default padding of 5, which getLayoutRect takes as a MARGIN and
    so keeps OUTSIDE the items rather than eating into them.

    One item: a 25 x 14 icon, a 5 px gap, four characters at ten. 70 wide and
    14 tall, so it starts at (400 - 70) / 2 and ends 20 up from the bottom. }
  lg := Lay('{ "legend": { } }', ['abcd']);
  AssertTrue('it laid out', lg.Valid);
  AssertEquals('one item', 1, Length(lg.Items));
  AssertEquals('centred across the container', 165.0, lg.Items[0].IconBox.Left,
    Eps);
  AssertEquals('the icon is itemWidth wide', 190.0,
    lg.Items[0].IconBox.Right, Eps);
  AssertEquals('fifteen up plus the padding', 280.0,
    lg.Items[0].IconBox.Bottom, Eps);
  AssertEquals('and itemHeight tall', 266.0, lg.Items[0].IconBox.Top, Eps);
  AssertEquals('the words start five past the icon', 195.0,
    lg.Items[0].TextX, Eps);
  AssertEquals('centred on the icon''s middle', 273.0, lg.Items[0].TextY, Eps);
  AssertEquals('anchored by their left edge', Ord(tahLeft),
    Ord(lg.Items[0].AnchorH));
end;

procedure TAdvChartLegendTest.TestTheDefaultSpecIsCoherentOnItsOwn;
var d: TTyLegendSpec;
begin
  { TyLegendSpecDefault is public and a caller may lg one out without ever
    reading an option, so its box has to be pinned the way the reader would
    pin it. Two ways of spelling `centred` that only agree after a read is one
    of them being wrong half the time. }
  d := TyLegendSpecDefault;
  AssertEquals('the word says centre', 'center', d.LeftWord);
  AssertEquals('and so does the box', Ord(buCentre), Ord(d.Box.Left.Kind));
  AssertEquals('with no competing right edge', Ord(buAuto),
    Ord(d.Box.Right.Kind));
  AssertEquals('pinned to the bottom', Ord(buPx), Ord(d.Box.Bottom.Kind));
  AssertEquals('fifteen up', 15.0, d.Box.Bottom.Value, Eps);
end;

procedure TAdvChartLegendTest.TestTheCatalogsFourStaleDefaultsAreNotUsed;
var d: TTyLegendSpec;
begin
  { The generated catalog transcribes ECharts 5 documentation and is wrong
    about four legend defaults at once. Named here so that a future
    catalog-seeded reader cannot quietly reintroduce them. }
  d := TyLegendSpecDefault;
  AssertEquals('itemGap is 8, not the catalog''s 10', 8.0, d.ItemGap, Eps);
  AssertEquals('borderWidth is 0, not 1', 0.0, d.BorderWidth, Eps);
  AssertEquals('itemWidth', 25.0, d.ItemWidth, Eps);
  AssertEquals('itemHeight', 14.0, d.ItemHeight, Eps);
  AssertEquals('z is 4, not 2', 4, d.Z);
end;

procedure TAdvChartLegendTest.TestTwoItemsAreOneItemGapApart;
var lg: TTyLegendLayout;
begin
  { The gap is between the two items' RECTANGLES, not between their origins --
    which is what the (-next.x + this.x) correction in boxLayout is for. The
    two names have different lengths on purpose: equal ones cannot tell a gap
    measured from the right edge from one measured from the origin. }
  lg := Lay('{ "legend": { } }', ['abcd', 'ef']);
  AssertEquals('two items', 2, Length(lg.Items));
  AssertEquals('the first is 70 wide', 70.0,
    TyRectFWidth(lg.Items[0].Bounds), Eps);
  AssertEquals('the second is 50', 50.0,
    TyRectFWidth(lg.Items[1].Bounds), Eps);
  AssertEquals('and the gap between them is itemGap', 8.0,
    lg.Items[1].Bounds.Left - lg.Items[0].Bounds.Right, Eps);
  AssertEquals('both on one row', lg.Items[0].Bounds.Top,
    lg.Items[1].Bounds.Top, Eps);
  AssertEquals('the block is centred on the container', 200.0,
    (lg.Content.Left + lg.Content.Right) / 2, Eps);
end;

procedure TAdvChartLegendTest.TestAWidthIsAWrapLimitAndNotAWidth;
var lg: TTyLegendLayout;
begin
  { `legend.width` bounds the WRAP and is then overwritten by what the items
    measured -- LegendModel.ts:251-254 says so and defaults() is what does it.
    Three 70-wide items under a 100 limit therefore make three rows of ONE,
    and the block that comes out is 70 wide rather than 100. }
  lg := Lay('{ "legend": { "width": 100 } }', ['abcd', 'ghij', 'klmn']);
  AssertEquals('three items', 3, Length(lg.Items));
  AssertEquals('each on its own row', 3, 1
    + Ord(lg.Items[1].Bounds.Top <> lg.Items[0].Bounds.Top)
    + Ord(lg.Items[2].Bounds.Top <> lg.Items[1].Bounds.Top));
  AssertEquals('the row pitch is itemHeight plus itemGap', 22.0,
    lg.Items[1].Bounds.Top - lg.Items[0].Bounds.Top, Eps);
  AssertEquals('and the block is as wide as its widest row, not as the limit',
    70.0, TyRectFWidth(lg.Content), Eps);
  AssertEquals('three rows tall', 58.0, TyRectFHeight(lg.Content), Eps);
end;

procedure TAdvChartLegendTest.TestAnEmptyNameBreaksTheLine;
var lg: TTyLegendLayout;
begin
  { An empty `legend.data` entry is not an item, it is a line break. It takes
    no place and eats no gap -- it only closes the row above. }
  lg := Lay('{ "legend": { "data": ["a", "", "b"] } }', []);
  AssertEquals('three entries, one of them a break', 3, Length(lg.Items));
  AssertFalse('the break was never placed',
    TyRectFIsValid(lg.Items[1].Bounds));
  AssertEquals('and the item after it starts a new row', 22.0,
    lg.Items[2].Bounds.Top - lg.Items[0].Bounds.Top, Eps);
  AssertEquals('flush with the row above it, not gapped in from it',
    lg.Items[0].Bounds.Left, lg.Items[2].Bounds.Left, Eps);
end;

procedure TAdvChartLegendTest.TestAVerticalLegendStacks;
var lg: TTyLegendLayout;
begin
  lg := Lay('{ "legend": { "orient": "vertical" } }', ['abcd', 'ef']);
  AssertEquals('one under the other', 22.0,
    lg.Items[1].Bounds.Top - lg.Items[0].Bounds.Top, Eps);
  AssertEquals('at the same left edge', lg.Items[0].Bounds.Left,
    lg.Items[1].Bounds.Left, Eps);
  AssertEquals('and the block is as wide as the widest item', 70.0,
    TyRectFWidth(lg.Content), Eps);
end;

procedure TAdvChartLegendTest.TestTheKeywordDecidesWhichEdgeIsPinned;
var lg: TTyLegendLayout;
begin
  { `left: 'right'` does not put the left edge at 100% -- it pins the RIGHT
    edge. Resolving it as a percentage would put the block entirely outside
    the container. }
  lg := Lay('{ "legend": { "left": "right" } }', ['abcd']);
  AssertEquals('flush with the right edge, inside the padding', 395.0,
    lg.Content.Right, Eps);
  AssertEquals('and 70 wide as before', 325.0, lg.Content.Left, Eps);
end;

procedure TAdvChartLegendTest.TestARightEdgeAloneDoesNotMoveTheLegend;
var lg, plain: TTyLegendLayout;
begin
  { The keyword switch consults `left` FIRST, and the default `left: 'center'`
    is still there -- so `right: 10` on its own loses the test and changes
    nothing. It reads like a bug and it is upstream's behaviour. }
  plain := Lay('{ "legend": { } }', ['abcd']);
  lg := Lay('{ "legend": { "right": 10 } }', ['abcd']);
  AssertEquals('still centred', plain.Content.Left, lg.Content.Left, Eps);
end;

procedure TAdvChartLegendTest.TestAlignRightOnlyFollowsAVerticalLeftRight;
var h, v: TTyLegendLayout;
begin
  { align 'auto' is right-handed only when the legend is VERTICAL and pinned
    by the literal word 'right'. A horizontal one pinned the same way stays
    left-handed, which is the counterexample the derivation exists for. }
  h := Lay('{ "legend": { "left": "right" } }', ['abcd']);
  v := Lay('{ "legend": { "left": "right", "orient": "vertical" } }', ['abcd']);
  AssertEquals('horizontal stays left-handed', Ord(tlaLeft), Ord(h.Align));
  AssertEquals('vertical turns right-handed', Ord(tlaRight), Ord(v.Align));
end;

procedure TAdvChartLegendTest.TestARightAlignedItemHangsLeftOfItsOwnOrigin;
var lg: TTyLegendLayout;
begin
  { textX is -5 rather than itemWidth + 5, so the item's rectangle starts 45
    px LEFT of its icon. That negative overhang is the case the wrap's
    correction term and the content shift both exist for: the block still has
    to land inside the container. }
  lg := Lay('{ "legend": { "left": "right", "orient": "vertical" } }',
    ['abcd']);
  AssertEquals('the words are anchored by their right edge', Ord(tahRight),
    Ord(lg.Items[0].AnchorH));
  AssertEquals('five short of the icon''s near edge', -5.0,
    lg.Items[0].TextX - lg.Items[0].IconBox.Left, Eps);
  AssertTrue('so the item starts left of its icon',
    lg.Items[0].Bounds.Left < lg.Items[0].IconBox.Left);
  AssertEquals('and the block still ends at the right edge', 395.0,
    lg.Content.Right, Eps);
  AssertEquals('with nothing hanging outside it on the left', 325.0,
    lg.Content.Left, Eps);
end;

procedure TAdvChartLegendTest.TestTheFrameSurroundsTheItemsByItsPadding;
var lg: TTyLegendLayout;
begin
  { FOUR DIFFERENT PADDINGS, because a symmetric one cannot tell top from
    bottom or left from right, and CSS order is the thing being tested. }
  lg := Lay('{ "legend": { "padding": [1, 2, 3, 4] } }', ['abcd']);
  AssertEquals('the frame clears the top by padding[0]', 1.0,
    lg.Content.Top - lg.Frame.Top, Eps);
  AssertEquals('the right by padding[1]', 2.0,
    lg.Frame.Right - lg.Content.Right, Eps);
  AssertEquals('the bottom by padding[2]', 3.0,
    lg.Frame.Bottom - lg.Content.Bottom, Eps);
  AssertEquals('the left by padding[3]', 4.0,
    lg.Content.Left - lg.Frame.Left, Eps);
  AssertEquals('and the FRAME is what sits fifteen up from the bottom', 285.0,
    lg.Frame.Bottom, Eps);
end;

procedure TAdvChartLegendTest.TestShowFalseLaysOutNothing;
begin
  AssertFalse('show: false draws nothing',
    Lay('{ "legend": { "show": false } }', ['abcd']).Valid);
  AssertFalse('and so does a legend with no entries at all',
    Lay('{ "legend": { } }', []).Valid);
  AssertEquals('no legend component', 0, TyLegendCount(TTyChartOption(nil)));
end;

{ ==================== entries ==================== }

procedure TAdvChartLegendTest.TestEntriesComeFromTheDataWhenThereIsSome;
var e: TTyLegendEntryArray;
begin
  AssertTrue(FOpt.SetOptionText('{ "legend": { "data": ["x", {"name": "y", '
    + '"icon": "circle"}] } }'));
  e := TyLegendEntries(FOpt, 0, ['ignored']);
  AssertEquals('the data wins over what the chart offered', 2, Length(e));
  AssertEquals('a bare string is a name', 'x', e[0].Name);
  AssertEquals('an object carries its own icon', 'circle', e[1].Icon);
  AssertEquals('and its name', 'y', e[1].Name);
  AssertEquals('a row that named no icon has none', '', e[0].Icon);

  AssertTrue(FOpt.SetOptionText('{ "legend": { } }'));
  e := TyLegendEntries(FOpt, 0, ['a', 'b']);
  AssertEquals('with no data the chart''s own names are used', 2, Length(e));
  AssertEquals('in order', 'a', e[0].Name);
  AssertEquals('', 'b', e[1].Name);
end;

procedure TAdvChartLegendTest.TestAnEmptyDataArrayAsksForNoItems;
var e: TTyLegendEntryArray;
begin
  { `get('data') || potentialData` falls back only on a MISSING data, and []
    is truthy in JavaScript -- so an empty array is an instruction and not an
    omission. }
  AssertTrue(FOpt.SetOptionText('{ "legend": { "data": [] } }'));
  e := TyLegendEntries(FOpt, 0, ['a', 'b']);
  AssertEquals('an empty data array means an empty legend', 0, Length(e));
end;

procedure TAdvChartLegendTest.TestDuplicateNamesAreDroppedIncludingLineBreaks;
var e: TTyLegendEntryArray;
begin
  AssertTrue(FOpt.SetOptionText(
    '{ "legend": { "data": ["a", "b", "a", "", "c", ""] } }'));
  e := TyLegendEntries(FOpt, 0, []);
  AssertEquals('the second a and the second break both go', 4, Length(e));
  AssertEquals('first one wins', 'a', e[0].Name);
  AssertEquals('', 'b', e[1].Name);
  AssertTrue('the surviving break is a break', e[2].Newline);
  AssertEquals('and what followed it survives too', 'c', e[3].Name);
end;

{ ==================== selection ==================== }

procedure TAdvChartLegendTest.TestSelectedFalseSwitchesAnItemOff;
var
  e: TTyLegendEntryArray;
  f: TTyLegendFlags;
begin
  AssertTrue(FOpt.SetOptionText(
    '{ "legend": { "selected": { "b": false } } }'));
  e := TyLegendEntries(FOpt, 0, ['a', 'b']);
  f := TyLegendSelected(FOpt, 0, e, ['a', 'b'], tlsMultiple);
  AssertTrue('a was never mentioned and so is on', f[0]);
  AssertFalse('b was switched off', f[1]);
end;

procedure TAdvChartLegendTest.TestAnyFalsyValueSwitchesAnItemOff;
var
  e: TTyLegendEntryArray;
  f: TTyLegendFlags;
begin
  { `!(has(name) && !selected[name])` is JavaScript: null, 0 and the empty
    string are all falsy, so all three hide an item exactly as false does. A
    port that special-cased the boolean would diverge on every one of them. }
  AssertTrue(FOpt.SetOptionText('{ "legend": { "selected": '
    + '{ "a": null, "b": 0, "c": "", "d": 1, "e": "yes" } } }'));
  e := TyLegendEntries(FOpt, 0, ['a', 'b', 'c', 'd', 'e']);
  f := TyLegendSelected(FOpt, 0, e, ['a', 'b', 'c', 'd', 'e'], tlsMultiple);
  AssertEquals('five names offered', 5, Length(e));
  AssertFalse('null is off', f[0]);
  AssertFalse('zero is off', f[1]);
  AssertFalse('an empty string is off', f[2]);
  AssertTrue('a non-zero number is on', f[3]);
  AssertTrue('and a non-empty string is on', f[4]);
end;

procedure TAdvChartLegendTest.TestANameTheChartCannotOfferIsNeverSelected;
var
  e: TTyLegendEntryArray;
  f: TTyLegendFlags;
begin
  { isSelected has a SECOND condition nobody documents: the name has to be one
    the chart can produce. A `legend.data` entry naming a series that does not
    exist is drawn, and drawn greyed. }
  AssertTrue(FOpt.SetOptionText(
    '{ "legend": { "data": ["real", "ghost"] } }'));
  e := TyLegendEntries(FOpt, 0, []);
  f := TyLegendSelected(FOpt, 0, e, ['real'], tlsMultiple);
  AssertTrue('the one the chart has is on', f[0]);
  AssertFalse('the one it does not is off however the map is written', f[1]);
end;

procedure TAdvChartLegendTest.TestSingleModeForcesOneItemOnAtLoad;
var
  e: TTyLegendEntryArray;
  f: TTyLegendFlags;
begin
  { THIS IS THE FIRST FRAME, not a click. optionUpdated forces exactly one
    selection at load, so a `selectedMode: 'single'` chart shows ONE series
    before anybody touches it. }
  AssertTrue(FOpt.SetOptionText('{ "legend": { "selectedMode": "single" } }'));
  e := TyLegendEntries(FOpt, 0, ['a', 'b', 'c']);
  f := TyLegendSelected(FOpt, 0, e, ['a', 'b', 'c'], tlsSingle);
  AssertTrue('the first is on', f[0]);
  AssertFalse('the second is not', f[1]);
  AssertFalse('nor the third', f[2]);

  { and the same option in the ordinary mode leaves all three on }
  f := TyLegendSelected(FOpt, 0, e, ['a', 'b', 'c'], tlsMultiple);
  AssertTrue('multiple leaves them alone', f[0] and f[1] and f[2]);
end;

procedure TAdvChartLegendTest.TestSingleModeKeepsTheFirstAlreadySelectedItem;
var
  e: TTyLegendEntryArray;
  f: TTyLegendFlags;
begin
  { It takes the first item that the map already says is on -- and clears
    everything after it, including another item the map also said was on. }
  AssertTrue(FOpt.SetOptionText('{ "legend": { "selectedMode": "single", '
    + '"selected": { "a": false, "b": true, "c": true } } }'));
  e := TyLegendEntries(FOpt, 0, ['a', 'b', 'c']);
  f := TyLegendSelected(FOpt, 0, e, ['a', 'b', 'c'], tlsSingle);
  AssertFalse('the one that was off stays off', f[0]);
  AssertTrue('the first that was on stays on', f[1]);
  AssertFalse('and the second that was on is cleared', f[2]);
end;

procedure TAdvChartLegendTest.TestTheFormatterReplacesTheFirstNameOnly;
begin
  AssertEquals('no formatter leaves the name alone', 'x',
    TyLegendText('', 'x'));
  AssertEquals('a template wraps it', 'Series: x',
    TyLegendText('Series: {name}', 'x'));
  { String.replace with a STRING pattern, not a global regexp -- so a second
    placeholder survives verbatim. }
  AssertEquals('and only the first placeholder is filled', 'x and {name}',
    TyLegendText('{name} and {name}', 'x'));
  AssertEquals('a template with no placeholder is the whole answer', 'fixed',
    TyLegendText('fixed', 'x'));
end;

{ ==================== the icon ==================== }

procedure TAdvChartLegendTest.TestTheIconChainPrefersTheRowThenTheLegendThenTheSeries;
var
  src: TTyLegendSourceArray;
  lg: TTyLegendLayout;
begin
  src := BarSources(2);
  src[0].DefaultIcon := 'diamond';
  src[1].DefaultIcon := 'diamond';
  { legend.icon beats the series' own symbol... }
  lg := LayWith('{ "legend": { "icon": "triangle", '
    + '"data": [{"name": "a", "icon": "pin"}, "b"] } }', [], src);
  AssertEquals('the row''s own icon wins', 'pin', lg.Items[0].Icon);
  AssertEquals('and legend.icon takes the row that named none', 'triangle',
    lg.Items[1].Icon);

  { ...and with neither, the series' symbol does, and with none of the three
    the floor is a rounded rectangle. }
  lg := LayWith('{ "legend": { "data": ["a", "b"] } }', [], src);
  AssertEquals('the series'' symbol', 'diamond', lg.Items[0].Icon);
  src[1].DefaultIcon := '';
  lg := LayWith('{ "legend": { "data": ["a", "b"] } }', [], src);
  AssertEquals('and a series with no symbol falls to roundRect', 'roundRect',
    lg.Items[1].Icon);
end;

procedure TAdvChartLegendTest.TestInheritOnASeriesWithNoIconOfItsOwnIsASharpRect;
var
  src: TTyLegendSourceArray;
  lg: TTyLegendLayout;
  list: TTyPaintList;
  n: Integer;
  b: TTyRectF;
begin
  { 'inherit' is only a sentinel on the branch a series takes when it draws
    its OWN legend icon. On a bar it survives as a literal string, matches no
    symbol name, and an unrecognised name is a RECT -- so the answer is a
    sharp-cornered box, neither the rounded default nor nothing at all. }
  src := BarSources(1);
  lg := LayWith('{ "legend": { "icon": "inherit" } }', ['a'], src);
  AssertEquals('the word survives', 'inherit', lg.Items[0].Icon);
  AssertFalse('and it is not the series'' own icon', lg.Items[0].OwnIcon);

  list := TTyPaintList.Create;
  try
    n := TyBuildLegendMarks(Spec('{ "legend": { "icon": "inherit" } }'), lg,
      Default(TTyLegendInk), Default(TTyLegendFont), 96, list);
    AssertEquals('an icon and its words', 2, n);
    AssertEquals('the icon is a polygon, not a rounded rect',
      Ord(cskPolygon), Ord(list.Element(0).Shape.Kind));
    b := TyShapeBounds(list.Element(0).Shape);
    AssertEquals('filling the whole item box', 25.0, TyRectFWidth(b), Eps);
    AssertEquals('', 14.0, TyRectFHeight(b), Eps);
  finally
    list.Free;
  end;
end;

procedure TAdvChartLegendTest.TestALegendIconIsBuiltInItsBoxNotInTheUnitBox;
var
  sym: TTySymbolSpec;
  sh: TTyChartShape;
  b: TTyRectF;
begin
  { A DATUM's symbol is built in the unit box and then scaled per axis, so an
    oblong size gives an ellipse and `square` is the same as `rect`. A LEGEND
    icon is built in a real box, where the shape makers' own min(w, h) finally
    bites. 25 x 14 is oblong on purpose: a square box could not tell the two
    apart. }
  sym := Default(TTySymbolSpec);
  sym.Kind := tsyCircle;
  sh := TyBuildSymbolInBox(sym, TyRectF(0, 0, 25, 14));
  AssertEquals('a circle in an oblong box is still a circle',
    Ord(cskCircle), Ord(sh.Kind));
  AssertEquals('of the box''s SHORTER half', 7.0, sh.R1, Eps);
  AssertEquals('centred in it', 12.5, sh.CX, Eps);
  AssertEquals('', 7.0, sh.CY, Eps);

  sym.Kind := tsySquare;
  sh := TyBuildSymbolInBox(sym, TyRectF(0, 0, 25, 14));
  b := TyShapeBounds(sh);
  AssertEquals('a square takes the shorter side', 14.0, TyRectFWidth(b), Eps);
  AssertEquals('', 14.0, TyRectFHeight(b), Eps);
  AssertEquals('and keeps the box''s LEFT edge rather than centring', 0.0,
    b.Left, Eps);

  sym.Kind := tsyRoundRect;
  sh := TyBuildSymbolInBox(sym, TyRectF(0, 0, 25, 14));
  b := TyShapeBounds(sh);
  AssertEquals('a roundRect fills the box', 25.0, TyRectFWidth(b), Eps);
  AssertEquals('', 14.0, TyRectFHeight(b), Eps);
end;

procedure TAdvChartLegendTest.TestALineSeriesDrawsARuleWithAMarkerOnIt;
var
  src: TTyLegendSourceArray;
  lg: TTyLegendLayout;
  list: TTyPaintList;
  n: Integer;
  rule, dot: TTyRectF;
begin
  src := BarSources(1);
  src[0].SeriesType := 'line';
  src[0].DefaultIcon := 'emptyCircle';
  src[0].OwnIcon := True;
  src[0].LineColour := Blue;
  src[0].LineWidthLogical := 2;
  lg := LayWith('{ "legend": { } }', ['a'], src);
  AssertTrue('the series draws its own icon', lg.Items[0].OwnIcon);
  AssertEquals('and the marker is its own symbol', 'emptyCircle',
    lg.Items[0].Icon);

  list := TTyPaintList.Create;
  try
    n := TyBuildLegendMarks(Spec('{ "legend": { } }'), lg,
      Default(TTyLegendInk), Default(TTyLegendFont), 96, list);
    AssertEquals('a rule, a marker and the words', 3, n);
    rule := TyShapeBounds(list.Element(0).Shape);
    AssertEquals('the rule spans the whole item box', 25.0,
      TyRectFWidth(rule), Eps);
    AssertEquals('flat across its middle', 0.0, TyRectFHeight(rule), Eps);
    AssertEquals('in the line''s own colour', Blue,
      list.Element(0).Style.StrokeColor);
    dot := TyShapeBounds(list.Element(1).Shape);
    AssertEquals('the marker is four fifths of the box''s HEIGHT', 11.2,
      TyRectFWidth(dot), 1e-6);
    AssertEquals('centred on the box',
      (lg.Items[0].IconBox.Left + lg.Items[0].IconBox.Right) / 2,
      (dot.Left + dot.Right) / 2, Eps);
    AssertEquals('and on its middle', 
      (lg.Items[0].IconBox.Top + lg.Items[0].IconBox.Bottom) / 2,
      (dot.Top + dot.Bottom) / 2, Eps);
    AssertTrue('and it is a ring rather than a dot',
      list.Element(1).Style.StrokeWidthLogical > 0);
  finally
    list.Free;
  end;
end;

{ ==================== the marks ==================== }

procedure TAdvChartLegendTest.TestTheMarksCarryTheItemsOwnColourAndWords;
var
  src: TTyLegendSourceArray;
  lg: TTyLegendLayout;
  list: TTyPaintList;
  ink: TTyLegendInk;
  fnt: TTyLegendFont;
begin
  { TWO DIFFERENT COLOURS, because one colour cannot tell "each item takes its
    own" from "every item takes the first". }
  src := BarSources(2);
  src[1].Colour := Blue;
  lg := LayWith('{ "legend": { } }', ['aa', 'bb'], src);
  ink := Default(TTyLegendInk);
  ink.Text := Grey;
  fnt.Name := 'fx';
  fnt.SizeLogical := 11;
  fnt.Weight := 400;
  list := TTyPaintList.Create;
  try
    AssertEquals('two icons and two labels', 4,
      TyBuildLegendMarks(Spec('{ "legend": { } }'), lg, ink, fnt, 96, list));
    AssertEquals('the first icon is the first colour', Red,
      list.Element(0).Style.FillColor);
    AssertEquals('the second is its own', Blue,
      list.Element(2).Style.FillColor);
    AssertEquals('the words are the theme''s ink', Grey,
      list.Element(1).Caption.Colour);
    AssertEquals('in the font it was handed', 'fx',
      list.Element(1).Caption.FontName);
    AssertEquals('', 11, list.Element(1).Caption.FontSizeLogical);
    AssertEquals('naming the second series', 'bb',
      list.Element(3).Caption.Text);
    AssertEquals('anchored on its middle', Ord(tavMiddle),
      Ord(list.Element(3).Caption.AnchorV));
  finally
    list.Free;
  end;
end;

procedure TAdvChartLegendTest.TestADeselectedItemIsGreyedRightThrough;
var
  src: TTyLegendSourceArray;
  sp: TTyLegendSpec;
  entries: TTyLegendEntryArray;
  flags: TTyLegendFlags;
  f: TTyLegendFont;
  lg: TTyLegendLayout;
  list: TTyPaintList;
  ink: TTyLegendInk;
begin
  { ONE ON AND ONE OFF in the same legend: a fixture where every item is off
    cannot tell the inactive colour from the ordinary one. }
  sp := Spec('{ "legend": { "selected": { "bb": false } } }');
  entries := TyLegendEntries(FOpt, 0, ['aa', 'bb']);
  flags := TyLegendSelected(FOpt, 0, entries, ['aa', 'bb'], sp.SelectedMode);
  src := BarSources(2);
  src[1].Colour := Blue;
  f.Name := 'x';
  f.SizeLogical := 9;
  f.Weight := 400;
  lg := TyLayoutLegend(sp, entries, flags, src, TyRectF(0, 0, 400, 300),
    FM, f, 96);
  AssertTrue('the first is on', lg.Items[0].Selected);
  AssertFalse('the second is off', lg.Items[1].Selected);

  ink := Default(TTyLegendInk);
  ink.Text := Red;
  ink.Inactive := Grey;
  list := TTyPaintList.Create;
  try
    TyBuildLegendMarks(sp, lg, ink, f, 96, list);
    AssertEquals('the live icon keeps its colour', Red,
      list.Element(0).Style.FillColor);
    AssertEquals('and its words the theme''s ink', Red,
      list.Element(1).Caption.Colour);
    AssertEquals('the dead icon is greyed', Grey,
      list.Element(2).Style.FillColor);
    AssertEquals('and so are its words', Grey,
      list.Element(3).Caption.Colour);
  finally
    list.Free;
  end;
end;

procedure TAdvChartLegendTest.TestTheMarksAreSilentAndSitAboveTheSeries;
var
  lg: TTyLegendLayout;
  list: TTyPaintList;
  i: Integer;
begin
  { SILENT: a legend is not a datum, and a legend icon swallowing the hover
    meant for the bar underneath it would be a bug. Z 4 is upstream's, and it
    is what puts the legend over the series rather than under it. }
  lg := Lay('{ "legend": { } }', ['aa']);
  list := TTyPaintList.Create;
  try
    TyBuildLegendMarks(Spec('{ "legend": { } }'), lg, Default(TTyLegendInk),
      Default(TTyLegendFont), 96, list);
    AssertTrue('something was drawn', list.Count > 0);
    for i := 0 to list.Count - 1 do
    begin
      AssertTrue('element ' + IntToStr(i) + ' is silent',
        list.Element(i).Silent);
      AssertEquals('and sits at legend z', 4, list.Element(i).Z);
      AssertFalse('and belongs to no datum',
        TyChartDatumValid(list.Element(i).Datum));
    end;
  finally
    list.Free;
  end;
end;

procedure TAdvChartLegendTest.TestLeftWinsTheKeywordSwitchWhenBothEdgesNameOne;
var lg: TTyLegendLayout;
begin
  { `switch (positionInfo.left || positionInfo.right)` -- LEFT IS CONSULTED
    FIRST and `right` only answers when left is silent. Both edges have to name
    a keyword for the order to be visible at all: with a NUMBER in `right` the
    two readings agree, because a number is not a keyword. }
  lg := Lay('{ "legend": { "left": "left", "right": "right" } }', ['abcd']);
  AssertEquals('left won, so the block is flush left', 5.0,
    lg.Content.Left, Eps);
  AssertEquals('and not flush right', 75.0, lg.Content.Right, Eps);
end;

procedure TAdvChartLegendTest.TestTheWrapLimitIsTheContainerLessItsPadding;
var lg: TTyLegendLayout;
begin
  { The first box solve asks for a size it has not measured yet, so it lands in
    the degenerate branch -- and upstream does not centre there, it FILLS, inset
    by the padding. Ten pixels of difference, and they decide whether a row
    wraps.

    Three items of 130, 130 and 120: the third ends at 396, which is over the
    390 the padding leaves and under the 400 the container has. THREE
    DIFFERENT NAMES, because the dedup would quietly eat a repeat. }
  lg := Lay('{ "legend": { } }',
    ['0123456789', 'abcdefghij', 'ABCDEFGHI']);
  AssertEquals('three items', 3, Length(lg.Items));
  AssertEquals('the first two share a row', lg.Items[0].Bounds.Top,
    lg.Items[1].Bounds.Top, Eps);
  AssertEquals('and the third is pushed onto the next', 22.0,
    lg.Items[2].Bounds.Top - lg.Items[0].Bounds.Top, Eps);
end;

procedure TAdvChartLegendTest.TestAnItemLandingExactlyOnTheLimitDoesNotWrap;
var lg: TTyLegendLayout;
begin
  { The comparison is a STRICT greater-than and it does NOT include the gap --
    upstream's own FIXME sits beside it. An item that ends exactly on the limit
    stays where it is, and the gap that follows pushes the NEXT one over.

    THE LIMIT HAS TO LEAVE ROOM FOR THE SECOND ITEM TO REACH IT. Once `x` is
    past the limit every item wraps whichever way the comparison reads, so a
    fixture that crowds the first item draws the same picture under both and
    tests nothing. Two items of exactly 100 under a limit of 208: the second
    ends ON the limit, so it shares the row -- and would not if the comparison
    were inclusive. }
  lg := Lay('{ "legend": { "width": 208 } }', ['0123456', 'abcdefg']);
  AssertEquals('the block is one row tall', 14.0,
    TyRectFHeight(lg.Content), Eps);
  AssertEquals('and both items are on it', 208.0,
    TyRectFWidth(lg.Content), Eps);
  AssertEquals('side by side', lg.Items[0].Bounds.Top,
    lg.Items[1].Bounds.Top, Eps);
end;

procedure TAdvChartLegendTest.TestTheMeasuredBlockIsWhatGetsPlaced;
var lg: TTyLegendLayout;
begin
  { `legend.width` bounds the wrap and is then OVERWRITTEN: defaults() only
    fills what is missing and the measured pair is never missing. So a 70-wide
    block under a 100 limit is centred as 70 and not as 100 -- fifteen pixels
    apart, and the only place the difference shows. }
  lg := Lay('{ "legend": { "width": 100 } }', ['abcd']);
  AssertEquals('centred on what was measured', 165.0, lg.Content.Left, Eps);
  AssertEquals('', 235.0, lg.Content.Right, Eps);
end;

procedure TAdvChartLegendTest.TestARightAlignedRowKeepsTheGapBetweenItsInk;
var lg: TTyLegendLayout;
begin
  { THE CORRECTION TERM, and the only fixture that can see it: `x` is where an
    item's ORIGIN goes, not where its ink starts, and a right-aligned item's ink
    starts 45 or 55 px to the LEFT of its origin depending on how long its name
    is. Without the term the gap would come out as itemGap plus the difference
    between the two names' widths; with it, itemGap, every time.

    Two names of DIFFERENT lengths, therefore. Equal ones cancel the error. }
  lg := Lay('{ "legend": { "align": "right" } }', ['abcd', 'ef']);
  AssertEquals('anchored on the right', Ord(tlaRight), Ord(lg.Align));
  AssertTrue('the first item hangs left of its own icon',
    lg.Items[0].Bounds.Left < lg.Items[0].IconBox.Left);
  AssertEquals('and the gap between the two is still itemGap', 8.0,
    lg.Items[1].Bounds.Left - lg.Items[0].Bounds.Right, Eps);
end;

procedure TAdvChartLegendTest.TestAVerticalLegendWrapsIntoColumns;
var lg: TTyLegendLayout;
begin
  { The vertical branch is the horizontal one with the axes swapped: a column
    that runs past its limit starts a new one, and the new column is a WHOLE
    COLUMN to the right -- the widest item in the one being closed, plus the
    gap. The three names have different lengths so that `the widest` is not the
    same as `the last`. }
  lg := Lay('{ "legend": { "orient": "vertical", "height": 50 } }',
    ['ab', 'abcdef', 'gh']);
  AssertEquals('two fit in the first column', lg.Items[0].Bounds.Left,
    lg.Items[1].Bounds.Left, Eps);
  AssertEquals('one under the other', 22.0,
    lg.Items[1].Bounds.Top - lg.Items[0].Bounds.Top, Eps);
  AssertEquals('the third starts a new column', lg.Items[0].Bounds.Top,
    lg.Items[2].Bounds.Top, Eps);
  AssertEquals('a whole column to the right, not one item',
    TyRectFWidth(lg.Items[1].Bounds) + 8.0,
    lg.Items[2].Bounds.Left - lg.Items[0].Bounds.Left, Eps);
end;

procedure TAdvChartLegendTest.TestTheFirstOfTwoRowsWithTheSameNameIsTheOneKept;
var e: TTyLegendEntryArray;
begin
  { First one wins, and the two rows have to DIFFER for that to mean anything --
    two identical rows cannot tell which was kept. }
  AssertTrue(FOpt.SetOptionText('{ "legend": { "data": ['
    + '"a", {"name": "a", "icon": "pin"}] } }'));
  e := TyLegendEntries(FOpt, 0, []);
  AssertEquals('one entry', 1, Length(e));
  AssertEquals('and it is the FIRST one, which named no icon', '', e[0].Icon);
end;

procedure TAdvChartLegendTest.TestSingleModeSelectsTheFirstWhenNothingIsSelected;
var
  e: TTyLegendEntryArray;
  f: TTyLegendFlags;
begin
  { `!hasSelected && select(legendData[0])`. With every item switched off in the
    option, single mode still comes up with exactly one on -- it cannot show
    nothing. }
  AssertTrue(FOpt.SetOptionText('{ "legend": { "selectedMode": "single", '
    + '"selected": { "a": false, "b": false } } }'));
  e := TyLegendEntries(FOpt, 0, ['a', 'b']);
  f := TyLegendSelected(FOpt, 0, e, ['a', 'b'], tlsSingle);
  AssertTrue('the first comes back on', f[0]);
  AssertFalse('and only the first', f[1]);
end;

procedure TAdvChartLegendTest.TestANamedIconStopsTheSeriesDrawingItsOwn;
var
  src: TTyLegendSourceArray;
  lg: TTyLegendLayout;
  list: TTyPaintList;
begin
  { The series' own icon is taken only when the option said NOTHING, or said
    'inherit'. Name any other icon and the line loses its rule. }
  src := BarSources(1);
  src[0].SeriesType := 'line';
  src[0].DefaultIcon := 'emptyCircle';
  src[0].OwnIcon := True;
  src[0].LineWidthLogical := 2;

  lg := LayWith('{ "legend": { "icon": "inherit" } }', ['a'], src);
  AssertTrue('inherit still lets it', lg.Items[0].OwnIcon);

  lg := LayWith('{ "legend": { "icon": "circle" } }', ['a'], src);
  AssertFalse('a named icon does not', lg.Items[0].OwnIcon);
  AssertEquals('and the named one is what is drawn', 'circle',
    lg.Items[0].Icon);
  list := TTyPaintList.Create;
  try
    AssertEquals('an icon and its words, with no rule between them', 2,
      TyBuildLegendMarks(Spec('{ "legend": { "icon": "circle" } }'), lg,
        Default(TTyLegendInk), Default(TTyLegendFont), 96, list));
  finally
    list.Free;
  end;
end;

procedure TAdvChartLegendTest.TestTheLineItemIsMeasuredWithItsRuleAndItsMarker;
var
  src: TTyLegendSourceArray;
  lg: TTyLegendLayout;
begin
  { THE MEASURED BOX AND THE DRAWN INK ARE TWO DIFFERENT PIECES OF CODE, and
    this is what pins them together. The rule spans the whole item box and its
    pen overhangs both ends, so the item reaches one pen-half LEFT of its own
    icon -- a measurement that forgot the rule would start at the marker
    instead, six pixels in. }
  src := BarSources(1);
  src[0].SeriesType := 'line';
  src[0].DefaultIcon := 'emptyCircle';
  src[0].OwnIcon := True;
  src[0].LineWidthLogical := 2;
  lg := LayWith('{ "legend": { } }', ['a'], src);
  AssertEquals('the rule overhangs the icon by half its pen', -1.0,
    lg.Items[0].Bounds.Left - lg.Items[0].IconBox.Left, Eps);
  AssertEquals('and the marker is four fifths of the box, ringed', 13.2,
    TyRectFHeight(lg.Items[0].Bounds), 1e-6);
end;

procedure TAdvChartLegendTest.TestARingOnASeriesWithNoLineStillGetsAPen;
var
  src: TTyLegendSourceArray;
  lg: TTyLegendLayout;
  list: TTyPaintList;
begin
  { A scatter has no line at all, so there is no width to inherit -- and a ring
    drawn with a pen of zero is not a ring, it is nothing. The fallback is the
    same 2 the datum mark builders use for an `empty` marker. }
  src := BarSources(1);
  src[0].SeriesType := 'scatter';
  src[0].DefaultIcon := 'emptyCircle';
  src[0].LineWidthLogical := 0;
  lg := LayWith('{ "legend": { } }', ['a'], src);
  list := TTyPaintList.Create;
  try
    TyBuildLegendMarks(Spec('{ "legend": { } }'), lg, Default(TTyLegendInk),
      Default(TTyLegendFont), 96, list);
    AssertTrue('the ring has a pen',
      list.Element(0).Style.StrokeWidthLogical > 0);
  finally
    list.Free;
  end;
end;

procedure TAdvChartLegendTest.TestWhichIconASeriesTypePublishes;
begin
  { A BAR AND A PIE PUBLISH NOTHING, which is what sends the chain to
    roundRect; only a series with a symbol visual publishes one. }
  AssertEquals('a bar has no symbol at all', '',
    TyLegendDefaultIcon('bar', ''));
  AssertEquals('nor a pie', '', TyLegendDefaultIcon('pie', ''));
  { AND THE TWO THAT DO PUBLISH DO NOT PUBLISH THE SAME WORD. A scatter reaches
    the base class' 'circle'; a line names 'emptyCircle' itself and never gets
    there -- which is why an ECharts line legend shows a ring. }
  AssertEquals('a scatter is a solid dot', 'circle',
    TyLegendDefaultIcon('scatter', ''));
  AssertEquals('a line is a RING', 'emptyCircle',
    TyLegendDefaultIcon('line', ''));
  AssertEquals('and an option symbol beats both', 'triangle',
    TyLegendDefaultIcon('line', 'triangle'));
  AssertEquals('which a bar still ignores', '',
    TyLegendDefaultIcon('bar', 'triangle'));

  AssertTrue('only a line draws its own icon', TyLegendDrawsOwnIcon('line'));
  AssertFalse('not a scatter', TyLegendDrawsOwnIcon('scatter'));
  AssertFalse('not a bar', TyLegendDrawsOwnIcon('bar'));
  AssertFalse('not a pie', TyLegendDrawsOwnIcon('pie'));
end;

initialization
  RegisterTest(TAdvChartLegendTest);
end.
