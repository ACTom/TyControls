unit test.advchart.measure;
{$mode objfpc}{$H+}
{ The painter-backed text measurer -- the one bridge unit that crosses from the
  pure layout layer into the LCL.

  These tests deliberately assert PROPERTIES, not pixel counts. The numbers a
  real font returns differ by machine and by widgetset, so an assertion like
  "'Value' is 34 px" would pass here and fail on the next person's GTK box. What
  must hold everywhere is that the measurer is monotone, non-zero, DPI-sensitive,
  and never under-reports either of the painter's two disagreeing rasterisers.
  The axis-layout arithmetic itself is pinned against a fake measurer in
  test.advchart.axis, where exact numbers are meaningful. }
interface
uses Classes, SysUtils, Math, Graphics, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Measure, tyControls.Painter;
type
  TAdvChartMeasureTest = class(TTestCase)
  published
    procedure TestMeasuresSomething;
    procedure TestLongerTextIsWider;
    procedure TestHeightDoesNotGrowWithLength;
    procedure TestBiggerFontIsBigger;
    procedure TestHigherPPIMeasuresLarger;
    procedure TestEmptyTextStillHasALineBox;
    procedure TestNeverUnderReportsEitherRasteriser;
    procedure TestAnchorConversions;
  end;
implementation

procedure TAdvChartMeasureTest.TestMeasuresSomething;
var m: ITyTextMeasurer; w, h: Double;
begin
  m := TTyPainterTextMeasurer.Create(96);
  m.MeasureLine('Value', '', 12, 400, w, h);
  AssertTrue('width > 0, got ' + FloatToStr(w), w > 0);
  AssertTrue('height > 0, got ' + FloatToStr(h), h > 0);
end;

procedure TAdvChartMeasureTest.TestLongerTextIsWider;
var m: ITyTextMeasurer; w1, h1, w2, h2: Double;
begin
  m := TTyPainterTextMeasurer.Create(96);
  m.MeasureLine('1', '', 12, 400, w1, h1);
  m.MeasureLine('1000000', '', 12, 400, w2, h2);
  AssertTrue('a seven-digit label is wider than a one-digit one', w2 > w1);
end;

procedure TAdvChartMeasureTest.TestHeightDoesNotGrowWithLength;
var m: ITyTextMeasurer; w1, h1, w2, h2: Double;
begin
  m := TTyPainterTextMeasurer.Create(96);
  m.MeasureLine('1', '', 12, 400, w1, h1);
  m.MeasureLine('1000000', '', 12, 400, w2, h2);
  { One line stays one line. A height that grew with length would mean the
    measurer had wrapped, which would silently double every axis gutter. }
  AssertEquals('same line box', h1, h2, 0.001);
end;

procedure TAdvChartMeasureTest.TestBiggerFontIsBigger;
var m: ITyTextMeasurer; w1, h1, w2, h2: Double;
begin
  m := TTyPainterTextMeasurer.Create(96);
  m.MeasureLine('Value', '', 9, 400, w1, h1);
  m.MeasureLine('Value', '', 24, 400, w2, h2);
  AssertTrue('wider at 24 than at 9', w2 > w1);
  AssertTrue('taller at 24 than at 9', h2 > h1);
end;

procedure TAdvChartMeasureTest.TestHigherPPIMeasuresLarger;
var
  lo, hi: ITyTextMeasurer;
  w1, h1, w2, h2: Double;
begin
  lo := TTyPainterTextMeasurer.Create(96);
  hi := TTyPainterTextMeasurer.Create(192);
  lo.MeasureLine('Value', '', 12, 400, w1, h1);
  hi.MeasureLine('Value', '', 12, 400, w2, h2);
  { The measurer returns DEVICE px, so the same logical font must come back
    bigger at a higher PPI. Returning logical px here would make every axis
    gutter too narrow on a HiDPI monitor and nowhere else. }
  AssertTrue('wider at 192 dpi (96=' + FloatToStr(w1) + ' 192=' + FloatToStr(w2) + ')',
             w2 > w1);
  AssertTrue('taller at 192 dpi', h2 > h1);
end;

procedure TAdvChartMeasureTest.TestEmptyTextStillHasALineBox;
var m: ITyTextMeasurer; w, h: Double;
begin
  m := TTyPainterTextMeasurer.Create(96);
  m.MeasureLine('', '', 12, 400, w, h);
  AssertEquals('no width', 0.0, w, 0.001);
  { ...but a real height. An axis whose one tick happens to be blank must not
    collapse its gutter and then jump back when the value returns. }
  AssertTrue('still a line box, got ' + FloatToStr(h), h > 0);
end;

procedure TAdvChartMeasureTest.TestNeverUnderReportsEitherRasteriser;
var
  m: ITyTextMeasurer;
  w, h: Double;
  blockW, blockH, renderW: Integer;
  s: string;
begin
  { The painter's own header states the rule: the two measurement paths are two
    rasterisers that disagree by about a pixel, and anything whose size floor
    feeds a clip must take the LARGER. An axis label is that case -- measure a
    pixel short and the label the gutter was just sized for is ellipsised. }
  m := TTyPainterTextMeasurer.Create(96);
  for s in ['New', 'Open', 'Value', '1000000', 'Category name'] do
  begin
    m.MeasureLine(s, '', 12, 400, w, h);
    TyMeasureTextBlock(s, '', 12, 400, 96, 0, 0, blockW, blockH);
    renderW := TyMeasureRenderedTextWidth(s, '', 12, 400, 96);
    AssertTrue('"' + s + '" >= canvas width ' + IntToStr(blockW), w >= blockW);
    AssertTrue('"' + s + '" >= renderer width ' + IntToStr(renderW), w >= renderW);
  end;
end;

procedure TAdvChartMeasureTest.TestAnchorConversions;
begin
  AssertTrue('left', TyAnchorToAlignment(tahLeft) = taLeftJustify);
  AssertTrue('centre', TyAnchorToAlignment(tahCentre) = taCenter);
  AssertTrue('right', TyAnchorToAlignment(tahRight) = taRightJustify);
  AssertTrue('top', TyAnchorToLayout(tavTop) = tlTop);
  AssertTrue('middle', TyAnchorToLayout(tavMiddle) = tlCenter);
  AssertTrue('bottom', TyAnchorToLayout(tavBottom) = tlBottom);
end;

initialization
  RegisterTest(TAdvChartMeasureTest);
end.
