unit test.advchart.color;
{$mode objfpc}{$H+}
{ A colour the AUTHOR wrote.

  Before this row every colour in the chart came from the .tycss theme and an
  option naming one was read by nobody -- so `color: ['#c23531', ...]`, the
  single most-written line in anybody's ECharts option, did nothing at all.

  Two halves are tested here and they fail differently. The GRAMMAR is
  arithmetic and is asserted exactly, against values worked out from zrender's
  own parser. The PALETTE is a stateful cursor whose rules are all about what
  does NOT happen -- a repeated name consumes no slot, an authored colour
  consumes no slot, a hidden series consumes one anyway -- so its fixtures are
  built to make each of those observable on its own. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpjson,
     fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Color, tyControls.AdvChart.Builder,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartColorTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Draw(const AOption: string;
                   AW: Integer = 400; AH: Integer = 300; APPI: Integer = 96);
    { The colour at the middle of each solid run along a row, left to right --
      one entry per bar. }
    function BarFills(const AOption: string;
                      AW: Integer = 400): TTyChartColorArray;
    function Parsed(const AText: string): TTyChartColor;
    function PieFills(const AOption: string;
                      ACount: Integer): TTyChartColorArray;
  published
    { the grammar }
    procedure TestHexInAllFourLengths;
    procedure TestTheShortHexIsTheLongOneDoubled;
    procedure TestTheNamedColours;
    procedure TestRgbAndItsArgumentHandling;
    procedure TestThreeArgumentRgbaIsLegalBecauseUpstreamShipsOne;
    procedure TestHslWrapsItsHueAndClampsTheRest;
    procedure TestWhatIsNotAColour;
    procedure TestNoneIsNotTransparent;
    { the cursor }
    procedure TestARepeatedNameConsumesNothing;
    procedure TestAnEmptyNameConsumesWithoutBeingRemembered;
    procedure TestTheCursorWrapsRatherThanRunningOut;
    procedure TestAnUnnamedSeriesIsNotNameless;
    { the chart }
    procedure TestTheOptionPaletteReplacesTheThemeRamp;
    procedure TestAnAuthoredColourTakesNoPaletteSlot;
    procedure TestASwitchedOffSeriesStillTakesItsSlot;
    procedure TestTwoSeriesOfOneNameShareOneColour;
    procedure TestASeriesOwnPaletteStartsAtItsOwnBeginning;
    procedure TestTheThemeRampStillAnswersWhenNobodyWrote;
    { the style blocks }
    procedure TestABarTakesItsBorderFromItemStyle;
    procedure TestItemStyleOpacityReachesTheMark;
    procedure TestOneDatumCanNameItsOwnColour;
    { the pie, which colours by DATUM rather than by series }
    procedure TestAPieRunsThePaletteAcrossItsSlices;
    procedure TestAPieSliceCanNameItsOwnColour;
    { what counts as `the author wrote a colour` }
    procedure TestWhatDoesNotCountAsAWrittenColour;
    procedure TestAutoMeansThePaletteAndStillCostsASlot;
    procedure TestAutoOnABorderIsNotTheSameAsNonsense;
    procedure TestALinesPaletteSlotComesFromItemStyle;
    procedure TestTheLinesOwnWidthAndTheAreasOwnColour;
    procedure TestAnAreaStyleHasNoStrokeToRead;
    procedure TestTheRampComesRoundAfterNine;
  end;

implementation

const
  Eps = 1e-9;

procedure TAdvChartColorTest.SetUp;
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

procedure TAdvChartColorTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartColorTest.Draw(const AOption: string; AW, AH, APPI: Integer);
begin
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(AW, AH, BGRA(255, 0, 255, 255));
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, AW, AH), APPI);
end;

function TAdvChartColorTest.Parsed(const AText: string): TTyChartColor;
begin
  AssertTrue('"' + AText + '" is a colour', TyTryParseChartColor(AText, Result));
end;

function TAdvChartColorTest.BarFills(const AOption: string;
  AW: Integer): TTyChartColorArray;
var
  gb: TTyGridBuild;
  y, x, l, r, runStart: Integer;
  ground, p: TBGRAPixel;
  inRun: Boolean;

  procedure Close(AEnd: Integer);
  var q: TBGRAPixel;
  begin
    { The MIDDLE of the run, so an antialiased edge is never sampled. }
    q := FBmp.GetPixel((runStart + AEnd) div 2, y);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] :=
      TTyChartColor(($FF shl 24) or (q.red shl 16) or (q.green shl 8) or q.blue);
  end;

begin
  Result := nil;
  Draw(AOption, AW);
  gb := FChart.Build.Grid(0);
  { Near the BOTTOM of the plot, where every bar of a one-category chart
    is tall enough to be present whatever its value. }
  y := Round(gb.PlotRect.Bottom) - 6;
  l := Round(gb.PlotRect.Left) + 1;
  r := Round(gb.PlotRect.Right) - 1;
  ground := FBmp.GetPixel(l, Round(gb.PlotRect.Top) + 4);
  inRun := False;
  runStart := 0;
  for x := l to r do
  begin
    p := FBmp.GetPixel(x, y);
    if (Abs(p.red - ground.red) + Abs(p.green - ground.green)
        + Abs(p.blue - ground.blue)) > 24 then
    begin
      if not inRun then
      begin
        inRun := True;
        runStart := x;
      end;
    end
    else if inRun then
    begin
      inRun := False;
      Close(x - 1);
    end;
  end;
  if inRun then Close(r);
end;

{ ==================== the grammar ==================== }

procedure TAdvChartColorTest.TestHexInAllFourLengths;
begin
  AssertEquals('#rrggbb', $FF1A2B3C, Parsed('#1a2b3c'));
  AssertEquals('#rrggbbaa -- the LAST pair is the alpha, not the first',
    $801A2B3C, Parsed('#1a2b3c80'));
  AssertEquals('#rgb', $FFAABBCC, Parsed('#abc'));
  AssertEquals('#rgba', $DDAABBCC, Parsed('#abcd'));
  AssertEquals('upper case is the same colour', $FF1A2B3C, Parsed('#1A2B3C'));
end;

procedure TAdvChartColorTest.TestTheShortHexIsTheLongOneDoubled;
begin
  { Each nibble doubled is exactly nibble x 17, and for the ALPHA nibble
    n/15 and (n*17)/255 agree bit for bit -- so the two spellings are not
    merely close, they are the same number. Asserted as an identity rather
    than against a literal, because a literal would let both sides drift. }
  AssertEquals('#abcd is #aabbccdd', Parsed('#aabbccdd'), Parsed('#abcd'));
  AssertEquals('#f00 is #ff0000', Parsed('#ff0000'), Parsed('#f00'));
  AssertEquals('#0000 is fully transparent black',
    Parsed('#00000000'), Parsed('#0000'));
end;

procedure TAdvChartColorTest.TestTheNamedColours;
var c: TTyChartColor;
begin
  AssertEquals('red', $FFFF0000, Parsed('red'));
  AssertEquals('case is folded', $FFFF0000, Parsed('RED'));
  { Every space is stripped, not merely the ends -- which is the only reason
    'Light Sky Blue' finds the table at all. }
  AssertEquals('and every space is stripped', $FF87CEFA, Parsed('Light Sky Blue'));
  AssertEquals('transparent is BLACK at zero alpha, not white',
    $00000000, Parsed('transparent'));
  AssertEquals('both spellings of grey', Parsed('gray'), Parsed('grey'));
  AssertEquals('and of the dark one', Parsed('darkslategray'),
    Parsed('darkslategrey'));
  { CSS Level 3, and rebeccapurple came later. Every browser takes it and
    upstream does not, so a port that added it would draw a chart ECharts
    cannot. }
  AssertFalse('rebeccapurple is not in upstream''s table',
    TyTryParseChartColor('rebeccapurple', c));
end;

procedure TAdvChartColorTest.TestRgbAndItsArgumentHandling;
begin
  AssertEquals('rgb', $FF010203, Parsed('rgb(1,2,3)'));
  AssertEquals('and the spaces authors actually write',
    $33000000, Parsed('rgba(0, 0, 0, 0.2)'));
  AssertEquals('a fourth argument on rgb() IS the alpha',
    $80010203, Parsed('rgb(1,2,3,0.502)'));
  { parseInt truncates -- it does not round. }
  AssertEquals('a fractional channel truncates', $FF010202,
    Parsed('rgb(1,2,2.9)'));
  AssertEquals('percentages are of 255', $FFFF8000,
    Parsed('rgb(100%,50.2%,0%)'));
  AssertEquals('and an out-of-range channel clamps', $FF00FF00,
    Parsed('rgb(-40,300,0)'));
  AssertEquals('an alpha percentage is of one', $80010203,
    Parsed('rgba(1,2,3,50.2%)'));
end;

procedure TAdvChartColorTest.TestThreeArgumentRgbaIsLegalBecauseUpstreamShipsOne;
var c: TTyChartColor;
begin
  { `rgba(160,197,232)` is in ECharts' own parallel defaults. A parser that
    insisted on four arguments would fail on a stock chart, so this is not a
    tolerance for sloppiness -- it is required. }
  AssertEquals('three arguments, opaque', $FFA0C5E8, Parsed('rgba(160,197,232)'));

  { AND THE TWO NAMES DISAGREE ON GARBAGE. A wrong-arity `rgba()` is a
    SUCCESS returning opaque black; a wrong-arity `rgb()` is a failure. Same
    rubbish, opposite outcomes, decided by the function name -- so the pair
    has to be asserted together or neither half is pinned. }
  AssertEquals('rgba() with two arguments is opaque black',
    $FF000000, Parsed('rgba(1,2)'));
  AssertEquals('and with five', $FF000000, Parsed('rgba(1,2,3,4,5)'));
  AssertFalse('while rgb() with two is not a colour at all',
    TyTryParseChartColor('rgb(1,2)', c));
end;

procedure TAdvChartColorTest.TestHslWrapsItsHueAndClampsTheRest;
begin
  { Worked from upstream's own arithmetic, which rounds each channel after
    the conversion. }
  AssertEquals('a mid green', $FF40BF40, Parsed('hsl(120,50%,50%)'));
  { The hue WRAPS through a double modulo rather than clamping, so a hue past
    the circle and a negative one both land somewhere real. Asserted as two
    identities plus one absolute, so neither `no wrap` nor `clamp to 0..360`
    can pass. }
  AssertEquals('480 degrees is 120 degrees', Parsed('hsl(120,50%,50%)'),
    Parsed('hsl(480,50%,50%)'));
  AssertEquals('and -120 is 240, which is blue', $FF4040BF,
    Parsed('hsl(-120,50%,50%)'));
  AssertEquals('a bare fraction reads as a percentage would',
    Parsed('hsl(120,50%,50%)'), Parsed('hsl(120,0.5,0.5)'));
  { EITHER SIDE OF A HALF, because AT a half the two branches agree:
    0.5*(0.5+1) and 0.5+0.5-0.25 are both 0.75, so a fixture at 50%
    lightness cannot tell them apart and a mutation that deleted the branch
    survived it. A dark green and a light one do. }
  AssertEquals('a quarter lightness takes the low branch', $FF206020,
    Parsed('hsl(120,50%,25%)'));
  AssertEquals('and three quarters takes the high one', $FF9FDF9F,
    Parsed('hsl(120,50%,75%)'));

  AssertEquals('saturation over one clamps', $FF00FF00,
    Parsed('hsl(120,150%,50%)'));
  AssertEquals('hsla carries an alpha', $8040BF40,
    Parsed('hsla(120,50%,50%,0.502)'));
end;

procedure TAdvChartColorTest.TestWhatIsNotAColour;
var c: TTyChartColor;
begin
  AssertFalse('an empty string', TyTryParseChartColor('', c));
  AssertFalse('a word that is not a colour', TyTryParseChartColor('bananas', c));
  { STRICTER THAN UPSTREAM, DELIBERATELY. zrender's hex path uses parseInt,
    which stops at the first non-hex character and checks only the resulting
    NUMBER -- so '#12g' silently becomes #001122 and is cached. Both lines
    carry upstream's own `TODO: Stricter parsing`. Here a typo falls through
    to the theme, which is a sane answer rather than a confident wrong one. }
  AssertFalse('a hex digit that is not one', TyTryParseChartColor('#12g', c));
  AssertFalse('and in the long form', TyTryParseChartColor('#aabbgg', c));
  AssertFalse('a hex of the wrong length', TyTryParseChartColor('#12345', c));
  { CSS Color 4 is not upstream's grammar either -- the space-separated form,
    hwb(), lab(), oklch() and color-mix() are all rejected there too, so
    accepting them here would draw charts ECharts cannot. }
  AssertFalse('the space-separated form', TyTryParseChartColor('rgb(255 0 0)', c));
  AssertFalse('a function nobody implements', TyTryParseChartColor('oklch(0.7 0.1 200)', c));
  { The first ')' must be the last character, which is how a nested call is
    turned away rather than half-read. }
  AssertFalse('anything with a nested paren',
    TyTryParseChartColor('linear-gradient(to right,rgb(1,2,3),blue)', c));
  AssertFalse('a trailing tail', TyTryParseChartColor('rgb(1,2,3)x', c));
end;

procedure TAdvChartColorTest.TestNoneIsNotTransparent;
var c: TTyChartColor;
begin
  { `none` means DO NOT PAINT and is not in the keyword table at all;
    `transparent` IS a colour, paints nothing, and still hit-tests. Same
    pixels, different geometry -- so the two must not collapse into one. }
  AssertTrue('none is the no-paint word', TyChartColorIsNone('none'));
  AssertTrue('whatever the case', TyChartColorIsNone('NONE'));
  AssertFalse('none does not parse as a colour', TyTryParseChartColor('none', c));
  AssertFalse('and transparent is not the no-paint word',
    TyChartColorIsNone('transparent'));
  AssertTrue('because transparent IS a colour',
    TyTryParseChartColor('transparent', c));
end;

{ ==================== the cursor ==================== }

procedure TAdvChartColorTest.TestARepeatedNameConsumesNothing;
var
  cur: TTyPaletteCursor;
  pal: TTyChartColorArray;
  c: TTyChartColor;
begin
  SetLength(pal, 3);
  pal[0] := $FF000001; pal[1] := $FF000002; pal[2] := $FF000003;
  cur := TyPaletteStart(pal);
  AssertTrue('a', TyPaletteTake(cur, 'a', c));
  AssertEquals('the first', pal[0], c);
  AssertTrue('b', TyPaletteTake(cur, 'b', c));
  AssertEquals('the second', pal[1], c);
  { THE POINT: asking for `a` again returns a's colour AND leaves the cursor
    where it was, so the next NEW name gets the third and not the fourth.
    Both halves asserted -- a memo that returned the right colour while still
    advancing would pass the first line and fail the second. }
  AssertTrue('a again', TyPaletteTake(cur, 'a', c));
  AssertEquals('the same colour as before', pal[0], c);
  AssertTrue('c', TyPaletteTake(cur, 'c', c));
  AssertEquals('and the cursor never moved for the repeat', pal[2], c);
end;

procedure TAdvChartColorTest.TestAnEmptyNameConsumesWithoutBeingRemembered;
var
  cur: TTyPaletteCursor;
  pal: TTyChartColorArray;
  c: TTyChartColor;
begin
  SetLength(pal, 3);
  pal[0] := $FF000001; pal[1] := $FF000002; pal[2] := $FF000003;
  cur := TyPaletteStart(pal);
  { The memo write is guarded by the name; the ADVANCE is not. So an
    explicitly empty name is handed a colour, forgotten, and still costs a
    slot -- which is the opposite of what a repeated name does, and the pair
    is what makes the guard load-bearing. }
  AssertTrue('first blank', TyPaletteTake(cur, '', c));
  AssertEquals('takes the first', pal[0], c);
  AssertTrue('second blank', TyPaletteTake(cur, '', c));
  AssertEquals('and the SECOND, not the first again', pal[1], c);
end;

procedure TAdvChartColorTest.TestTheCursorWrapsRatherThanRunningOut;
var
  cur: TTyPaletteCursor;
  pal: TTyChartColorArray;
  c: TTyChartColor;
begin
  SetLength(pal, 2);
  pal[0] := $FF000001; pal[1] := $FF000002;
  cur := TyPaletteStart(pal);
  TyPaletteTake(cur, 'a', c);
  TyPaletteTake(cur, 'b', c);
  AssertTrue('the third name still gets a colour',
    TyPaletteTake(cur, 'c', c));
  AssertEquals('round to the beginning', pal[0], c);

  { An EMPTY palette answers no, and answers it without advancing anything --
    which is how a series with `color: []` written on it falls through to the
    chart-wide cursor untouched rather than consuming from it. }
  cur := TyPaletteStart(nil);
  AssertFalse('no palette, no colour', TyPaletteTake(cur, 'a', c));
end;

procedure TAdvChartColorTest.TestAnUnnamedSeriesIsNotNameless;
begin
  { Upstream builds `series` + NUL + index precisely so that two unnamed
    series cannot collide in the memo, and its comment says so. Left empty,
    every unnamed series would share the FIRST colour -- which is exactly the
    shape the empty-name rule above produces, and why the two are different
    tests. }
  AssertEquals('slot 0', 'series' + #0 + '0', TyChartSeriesDefaultName(0));
  AssertTrue('and two slots differ',
    TyChartSeriesDefaultName(0) <> TyChartSeriesDefaultName(1));
end;

{ ==================== the chart ==================== }

procedure TAdvChartColorTest.TestTheOptionPaletteReplacesTheThemeRamp;
var fills: TTyChartColorArray;
begin
  { Three bars, three written colours, in order. The colours are chosen to be
    nothing any theme would produce, so `the ramp answered` cannot pass. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5] }, { type: ''bar'', data: [5] },'
    + ' { type: ''bar'', data: [5] }] }');
  AssertEquals('three bars', 3, Length(fills));
  AssertEquals('the first', $FFFF0000, fills[0]);
  AssertEquals('the second', $FF00FF00, fills[1]);
  AssertEquals('the third', $FF0000FF, fills[2]);
end;

procedure TAdvChartColorTest.TestAnAuthoredColourTakesNoPaletteSlot;
var fills: TTyChartColorArray;
begin
  { UPSTREAM SAYS WHY IN A COMMENT: an author who paints one series as a
    backdrop did not mean to shift every other series' colour. So the middle
    bar is its own colour and the third is palette[1], NOT palette[2] -- and
    the palette is three long so that a port which did advance would produce
    a visibly different third bar rather than the same one by luck. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5] },'
    + ' { type: ''bar'', data: [5], itemStyle: { color: ''#808080'' } },'
    + ' { type: ''bar'', data: [5] }] }');
  AssertEquals('three bars', 3, Length(fills));
  AssertEquals('palette[0]', $FFFF0000, fills[0]);
  AssertEquals('the authored one', $FF808080, fills[1]);
  AssertEquals('palette[1], because the authored one consumed nothing',
    $FF00FF00, fills[2]);
end;

procedure TAdvChartColorTest.TestASwitchedOffSeriesStillTakesItsSlot;
var fills: TTyChartColorArray;
begin
  { THE WHOLE MECHANISM OF STABLE COLOURS. A legend click must not repaint the
    chart, so a hidden series goes on owning its slot -- upstream runs the
    palette over the RAW series for exactly this reason. Here the middle
    series is switched off at the legend, and the third bar must still be
    palette[2]: a port that skipped the hidden one would give it palette[1]
    and every colour after a legend click would move. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' legend: { selected: { ''two'': false } },'
    + ' xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ name: ''one'', type: ''bar'', data: [5] },'
    + ' { name: ''two'', type: ''bar'', data: [5] },'
    + ' { name: ''three'', type: ''bar'', data: [5] }] }');
  AssertEquals('two bars are drawn', 2, Length(fills));
  AssertEquals('the first keeps palette[0]', $FFFF0000, fills[0]);
  AssertEquals('and the third keeps palette[2]', $FF0000FF, fills[1]);
end;

procedure TAdvChartColorTest.TestTwoSeriesOfOneNameShareOneColour;
var fills: TTyChartColorArray;
begin
  { The memo is keyed on the NAME, so two series called the same thing are the
    same colour and between them consume ONE slot. The third series proves the
    second half: it is palette[1], not palette[2]. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ name: ''same'', type: ''bar'', data: [5] },'
    + ' { name: ''same'', type: ''bar'', data: [5] },'
    + ' { name: ''other'', type: ''bar'', data: [5] }] }');
  AssertEquals('three bars', 3, Length(fills));
  AssertEquals('the first', $FFFF0000, fills[0]);
  AssertEquals('the second shares it', $FFFF0000, fills[1]);
  AssertEquals('and only one slot was spent', $FF00FF00, fills[2]);
end;

procedure TAdvChartColorTest.TestASeriesOwnPaletteStartsAtItsOwnBeginning;
var fills: TTyChartColorArray;
begin
  { A series with its own `color` array runs its own cursor over it from
    NOUGHT, and never touches the chart-wide one -- so the middle bar takes
    the first entry of its own list, and the third still takes palette[1]. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5] },'
    + ' { type: ''bar'', data: [5], color: [''#808080'', ''#404040''] },'
    + ' { type: ''bar'', data: [5] }] }');
  AssertEquals('three bars', 3, Length(fills));
  AssertEquals('palette[0]', $FFFF0000, fills[0]);
  AssertEquals('its own first entry', $FF808080, fills[1]);
  AssertEquals('and the chart-wide cursor was untouched',
    $FF00FF00, fills[2]);
end;

procedure TAdvChartColorTest.TestTheThemeRampStillAnswersWhenNobodyWrote;
var fills: TTyChartColorArray;
begin
  { The rule this whole row draws: what the author wrote wins, what they did
    not write still comes from the theme. With no `color` anywhere the two
    bars must differ from each other and neither may be the magenta sentinel
    or the surface -- that is what `the skin chose them` looks like from
    here, and asserting particular values would pin the skin instead. }
  fills := BarFills('{ xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5] }, { type: ''bar'', data: [5] }] }');
  AssertEquals('two bars', 2, Length(fills));
  AssertTrue('and the ramp gave them different colours', fills[0] <> fills[1]);
end;

procedure TAdvChartColorTest.TestABarTakesItsBorderFromItemStyle;
var
  gb: TTyGridBuild;
  x, y, hits: Integer;
  p: TBGRAPixel;
begin
  { A four-pixel green border round a red bar. Counted along a row through the
    bar: two green runs, one at each edge, with red between -- so `the border
    was ignored` finds none and `the border ate the bar` finds no red. }
  Draw('{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 10 },'
    + ' series: [{ type: ''bar'', data: [8], itemStyle: { color: ''#ff0000'','
    + ' borderColor: ''#00ff00'', borderWidth: 4 } }] }');
  gb := FChart.Build.Grid(0);
  y := Round(gb.PlotRect.Bottom) - 20;
  hits := 0;
  for x := Round(gb.PlotRect.Left) to Round(gb.PlotRect.Right) do
  begin
    p := FBmp.GetPixel(x, y);
    if (p.green > 150) and (p.red < 120) then Inc(hits);
  end;
  AssertTrue(Format('the border is drawn (%d green pixels across the bar)',
    [hits]), hits >= 4);
  AssertTrue('and the bar is still red inside it',
    FBmp.GetPixel(Round((gb.PlotRect.Left + gb.PlotRect.Right) / 2), y).red > 150);
end;

procedure TAdvChartColorTest.TestItemStyleOpacityReachesTheMark;

  { The green channel at the middle of the bar. Red over a light surface, so
    green rises as the bar fades. }
  function GreenAt(const AOpacity: string): Integer;
  var gb: TTyGridBuild;
  begin
    Draw('{ xAxis: { data: [''A''] }, yAxis: { min: 0, max: 10 },'
      + ' series: [{ type: ''bar'', data: [8],'
      + ' itemStyle: { color: ''#ff0000'', opacity: ' + AOpacity + ' } }] }');
    gb := FChart.Build.Grid(0);
    Result := FBmp.GetPixel(
      Round((gb.PlotRect.Left + gb.PlotRect.Right) / 2),
      Round(gb.PlotRect.Bottom) - 20).green;
  end;

var opaque, half, faint: Integer;
begin
  { ORDERED, NOT ARITHMETIC. The first shape of this asserted the linear
    midpoint and failed at (255,169,169) -- BGRA composites through a gamma
    of 1.7, so half an opacity is not half the distance to the surface, and
    the number this test would have to hardcode is a fact about the
    RASTERISER rather than about the option being read. Three opacities and
    the order between them says the option is read and that more of it means
    more colour, which is the whole claim; ignoring the key, or pinning it
    to any one value, collapses all three together. }
  opaque := GreenAt('1');
  half := GreenAt('0.5');
  faint := GreenAt('0.15');
  AssertTrue(Format('an opaque red bar has no green in it (%d)', [opaque]),
    opaque < 40);
  AssertTrue(Format('half fades it (%d)', [half]),
    (half > opaque + 60) and (half < 230));
  AssertTrue(Format('and less fades it further (%d)', [faint]),
    faint > half + 30);
end;

procedure TAdvChartColorTest.TestOneDatumCanNameItsOwnColour;
var fills: TTyChartColorArray;
begin
  { `data: [{ value, itemStyle }]` is how a single bar is picked out, and it is
    the commonest thing anybody writes after the palette itself. One series,
    three categories, the middle one spoken for. }
  fills := BarFills('{ color: [''#ff0000''],'
    + ' xAxis: { data: [''A'', ''B'', ''C''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5,'
    + ' { value: 5, itemStyle: { color: ''#0000ff'' } }, 5] }] }');
  AssertEquals('three bars', 3, Length(fills));
  AssertEquals('the first takes the series colour', $FFFF0000, fills[0]);
  AssertEquals('the second took its own', $FF0000FF, fills[1]);
  AssertEquals('and the third is back to the series colour',
    $FFFF0000, fills[2]);
end;

{ The fill of each pie slice, clockwise from the top. Sampled on a ring
  between the centre and the rim, so a slice is found whatever its angle. }
function TAdvChartColorTest.PieFills(const AOption: string;
  ACount: Integer): TTyChartColorArray;
var
  i, cx, cy, px, py: Integer;
  ang, r: Double;
  q: TBGRAPixel;
begin
  Draw(AOption);
  cx := FBmp.Width div 2;
  cy := FBmp.Height div 2;
  r := Min(cx, cy) * 0.5;
  SetLength(Result, ACount);
  for i := 0 to ACount - 1 do
  begin
    { The MIDDLE of slice i of an equal-valued pie, measured clockwise from
      twelve o'clock -- which is where upstream starts a pie. }
    ang := -Pi / 2 + 2 * Pi * (i + 0.5) / ACount;
    px := cx + Round(r * Cos(ang));
    py := cy + Round(r * Sin(ang));
    q := FBmp.GetPixel(px, py);
    Result[i] := TTyChartColor(($FF shl 24) or (q.red shl 16)
                               or (q.green shl 8) or q.blue);
  end;
end;

procedure TAdvChartColorTest.TestAPieRunsThePaletteAcrossItsSlices;
var fills: TTyChartColorArray;
begin
  { A PIE COLOURS BY DATUM, so the palette runs across its SLICES and not
    across the chart's series. This went wrong in exactly the way a shared
    helper goes wrong: PieVisual asked SeriesColor(rawRow), which was
    harmless while that function was purely the theme's ramp -- a ramp does
    not care what its index means -- and became wrong the moment the same
    function started answering from the per-SERIES resolution. Slice 0 took
    series 0's colour and every later slice fell through to the skin: half
    the pie in the author's palette and half in the theme's. }
  fills := PieFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' series: [{ type: ''pie'', radius: ''70%'','
    + ' label: { show: false },'
    + ' data: [{ name: ''a'', value: 1 }, { name: ''b'', value: 1 },'
    + ' { name: ''c'', value: 1 }] }] }', 3);
  AssertEquals('the first slice', $FFFF0000, fills[0]);
  AssertEquals('the second', $FF00FF00, fills[1]);
  AssertEquals('the third', $FF0000FF, fills[2]);
end;

procedure TAdvChartColorTest.TestAPieSliceCanNameItsOwnColour;
var fills: TTyChartColorArray;
begin
  { The commonest thing anybody writes on a pie. The other two slices are
    asserted as well, because a per-slice colour that also consumed a
    palette slot would move them. }
  fills := PieFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' series: [{ type: ''pie'', radius: ''70%'','
    + ' label: { show: false },'
    + ' data: [{ name: ''a'', value: 1 },'
    + ' { name: ''b'', value: 1, itemStyle: { color: ''#808080'' } },'
    + ' { name: ''c'', value: 1 }] }] }', 3);
  AssertEquals('the first is untouched', $FFFF0000, fills[0]);
  AssertEquals('the second is its own', $FF808080, fills[1]);
  AssertEquals('and the third did not move', $FF0000FF, fills[2]);
end;

procedure TAdvChartColorTest.TestWhatDoesNotCountAsAWrittenColour;
var fills: TTyChartColorArray;
begin
  { A NULL IS NOT A COLOUR AND NOR IS A TYPO. Upstream OMITS an absent key
    from the style object rather than writing nil into it, and that emptiness
    is what lets the palette fill it in -- so `color: null` has to behave as
    though nothing were written at all, not as a colour of nought.

    A string it cannot read is the same answer for a different reason: in a
    browser the raw string reaches the canvas and an unreadable one leaves
    the shape painted in the PREVIOUS element's colour, which is a browser
    accident with nothing portable in it. Falling back to the palette is the
    only sane reading.

    Both asserted through the THIRD bar, because either mistake would also
    have to consume a palette slot and move it. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5], itemStyle: { color: null } },'
    + ' { type: ''bar'', data: [5], itemStyle: { color: ''bananas'' } },'
    + ' { type: ''bar'', data: [5] }] }');
  AssertEquals('three bars', 3, Length(fills));
  AssertEquals('a null colour falls through to the palette',
    $FFFF0000, fills[0]);
  AssertEquals('and so does one it cannot read', $FF00FF00, fills[1]);
  AssertEquals('both of them having spent a slot doing so',
    $FF0000FF, fills[2]);
end;

procedure TAdvChartColorTest.TestAutoMeansThePaletteAndStillCostsASlot;
var fills: TTyChartColorArray;
begin
  { `auto` IS A THIRD ANSWER: not a colour, and not silence either. It means
    `the palette colour`, so it has to be given one -- which means it spends a
    slot, unlike an authored colour, which does not. The middle bar proves the
    first half and the third bar proves the second. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00'', ''#0000ff''],'
    + ' xAxis: { data: [''A''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [5] },'
    + ' { type: ''bar'', data: [5], itemStyle: { color: ''auto'' } },'
    + ' { type: ''bar'', data: [5] }] }');
  AssertEquals('three bars', 3, Length(fills));
  AssertEquals('palette[0]', $FFFF0000, fills[0]);
  AssertEquals('auto took palette[1]', $FF00FF00, fills[1]);
  AssertEquals('and spent it, so the third is palette[2]',
    $FF0000FF, fills[2]);
end;

procedure TAdvChartColorTest.TestAutoOnABorderIsNotTheSameAsNonsense;

  function BorderPixels(const AColour: string): Integer;
  var gb: TTyGridBuild; x, y: Integer; q: TBGRAPixel;
  begin
    Draw('{ color: [''#ff0000''],'
      + ' xAxis: { data: [''A''] }, yAxis: { min: 0, max: 10 },'
      + ' series: [{ type: ''bar'', data: [8], itemStyle: {'
      + ' color: ''#ffffff'', borderColor: ''' + AColour + ''','
      + ' borderWidth: 5 } }] }');
    gb := FChart.Build.Grid(0);
    y := Round(gb.PlotRect.Bottom) - 20;
    Result := 0;
    for x := Round(gb.PlotRect.Left) to Round(gb.PlotRect.Right) do
    begin
      q := FBmp.GetPixel(x, y);
      if (q.red > 150) and (q.green < 120) and (q.blue < 120) then
        Inc(Result);
    end;
  end;

begin
  { WHERE `auto` AND NONSENSE PART COMPANY. On a FILL they agree by accident:
    both end up taking the palette colour, one by meaning it and one by
    falling through -- so a fixture built on a fill cannot tell `auto` is
    recognised at all, and a mutation that stopped recognising it survived
    one.

    On a BORDER they do not agree. `auto` means the series colour, so the
    border is drawn in it; an unreadable string is nothing written, so there
    is no border at all. A white bar with a red border, counted in red. }
  AssertTrue('auto draws the border in the series colour',
    BorderPixels('auto') >= 4);
  AssertEquals('and a word that is not a colour draws none',
    0, BorderPixels('bananas'));
end;

procedure TAdvChartColorTest.TestALinesPaletteSlotComesFromItemStyle;
var fills: TTyChartColorArray;
begin
  { THE TRAP OF THIS WHOLE ROW. A line series' access path is `itemStyle`,
    not `lineStyle` -- only `lines` and `parallel` override it, and a line is
    neither. So writing `lineStyle.color` does NOT stop a line taking a
    palette slot, and the bar after it must get palette[1].

    Asserted through the bar rather than through the line, because the line's
    own pixels are the one thing `lineStyle.color` does win and so they
    cannot tell the two readings apart. }
  fills := BarFills('{ color: [''#ff0000'', ''#00ff00''],'
    + ' xAxis: { data: [''A''] }, yAxis: { min: 0, max: 10 },'
    + ' series: [{ type: ''line'', data: [5],'
    + ' lineStyle: { color: ''#111111'' } },'
    + ' { type: ''bar'', data: [8] }] }');
  AssertEquals('one bar', 1, Length(fills));
  AssertEquals('the line spent palette[0] even though it named its pen,'
    + ' so the bar is palette[1]', $FF00FF00, fills[0]);
end;

procedure TAdvChartColorTest.TestTheLinesOwnWidthAndTheAreasOwnColour;

  { How many rows of ink a vertical cut through the series meets. }
  function InkRows(const AOption: string; AX: Integer): Integer;
  var gb: TTyGridBuild; y: Integer; p, ground: TBGRAPixel;
  begin
    Draw(AOption);
    gb := FChart.Build.Grid(0);
    ground := FBmp.GetPixel(Round(gb.PlotRect.Right) - 3,
                            Round(gb.PlotRect.Top) + 3);
    Result := 0;
    for y := Round(gb.PlotRect.Top) + 2 to Round(gb.PlotRect.Bottom) - 2 do
    begin
      p := FBmp.GetPixel(AX, y);
      if (Abs(p.red - ground.red) + Abs(p.green - ground.green)
          + Abs(p.blue - ground.blue)) > 24 then Inc(Result);
    end;
  end;

const
  { THE GRID TURNED OFF, because a column through the plot meets every
    horizontal split line as well and the first shape of this counted eight
    rows for a one-pixel line. }
  cAxes = ' xAxis: { data: [''A'', ''B''] },'
    + ' yAxis: { min: 0, max: 10, splitLine: { show: false } },';
  cThin = '{' + cAxes + ' series: [{ type: ''line'', data: [5, 5],'
    + ' lineStyle: { width: 1 } }] }';
  cThick = '{' + cAxes + ' series: [{ type: ''line'', data: [5, 5],'
    + ' lineStyle: { width: 11 } }] }';
var
  gb: TTyGridBuild;
  thin, thick, x: Integer;
  p: TBGRAPixel;
begin
  { `lineStyle.width` is spelled `width`, not `borderWidth` -- a line has no
    border. Eleven against one, measured a quarter of the way across so the
    symbols at the ends are nowhere near. }
  Draw(cThin);
  gb := FChart.Build.Grid(0);
  { HALFWAY, which for two categories is BETWEEN the two band centres -- so
    the probe misses the symbols a line draws on its points. }
  x := Round((gb.PlotRect.Left + gb.PlotRect.Right) / 2);
  thin := InkRows(cThin, x);
  thick := InkRows(cThick, x);
  AssertTrue(Format('a thin line is a few rows (%d)', [thin]),
    (thin >= 1) and (thin <= 4));
  AssertTrue(Format('and an eleven-pixel one is many more (%d)', [thick]),
    thick >= thin + 5);

  { `areaStyle.color` is the area's OWN key -- naming it does not make the
    line that colour, and not naming it leaves the area in the series'.

    RED, NOT BLUE. Blue was the first choice and the assertion passed with
    the option ignored, because the theme's accent IS a blue: two answers
    agreeing by accident. The colour a fixture asks for has to be one the
    default could not have produced. }
  Draw('{' + cAxes + ' series: [{ type: ''line'', data: [9, 9],'
    + ' areaStyle: { color: ''#ff0000'' } }] }');
  gb := FChart.Build.Grid(0);
  p := FBmp.GetPixel(x, Round(gb.PlotRect.Bottom) - 8);
  AssertTrue(Format('the area took the colour it was given (%d,%d,%d)',
    [p.red, p.green, p.blue]),
    (p.red > p.green + 40) and (p.red > p.blue + 40));
end;

procedure TAdvChartColorTest.TestAnAreaStyleHasNoStrokeToRead;
var node: TJSONObject; st: TTyOptStyle;
begin
  { SIX KEYS AND NO STROKE. `areaStyle.borderColor` is read by nobody
    upstream -- AREA_STYLE_KEY_MAP has fill, opacity and the four shadow keys
    and nothing else -- so reading one here would invent a behaviour rather
    than port one. Asserted against the reader directly, because no renderer
    consumes an area stroke and a pixel test therefore could not tell a
    reader that stops from one that does not. }
  node := TJSONObject(GetJSON('{"areaStyle": {"color": "#ff0000",'
    + ' "borderColor": "#00ff00", "borderWidth": 4}}'));
  try
    st := TyReadOptStyle(node, 'areaStyle');
    AssertTrue('the fill is read', st.Color.Written);
    AssertEquals('and is the colour asked for', $FFFF0000, st.Color.Color);
    AssertFalse('the border colour is not', st.BorderColor.Written);
    AssertTrue('nor the border width', IsNan(st.BorderWidthLogical));
  finally
    node.Free;
  end;
end;

procedure TAdvChartColorTest.TestTheRampComesRoundAfterNine;
var fills: TTyChartColorArray; i: Integer; opt: string;
begin
  { NINE, NOT EIGHT. The cycle length is observable: it decides which series
    comes round to share a colour with the first, and upstream's own default
    palette is nine long. With no `color` written the theme's ramp answers,
    and the NINTH series (index 8) must still differ from the first -- on an
    eight-long ramp it would be the same colour. }
  opt := '{ xAxis: { data: [''A''] }, yAxis: {}, series: [';
  for i := 0 to 8 do
  begin
    if i > 0 then opt := opt + ',';
    opt := opt + '{ type: ''bar'', data: [5] }';
  end;
  fills := BarFills(opt + '] }', 900);
  AssertEquals('nine bars', 9, Length(fills));
  AssertTrue('the ninth is not the first come round again',
    fills[8] <> fills[0]);
  AssertTrue('and the second is still not the first',
    fills[1] <> fills[0]);
end;

initialization
  RegisterTest(TAdvChartColorTest);
end.
