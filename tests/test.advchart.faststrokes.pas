unit test.advchart.faststrokes;
{$mode objfpc}{$H+}
{ [R4-P] The fast strokes, and the switch back to the canvas' pixels.

  Two things a chart draws are drawn a faster way unless ExactRendering is
  set: a solid pen narrower than one raster pixel goes through the painter's
  hairline rasteriser (TTyPainter.FastStrokes), and a label's halo is the
  band round the glyphs' outline by distance (StrokePathByDistance) instead
  of a stroke of it. Neither matches BGRA's fill pixel for pixel; what they
  must keep is what the eye reads:

  - the ink: a hairline's and a band's coverage summed is the stroke's within
    a few hundredths (TestAHairlineInksAsTheStroke,
    TestTheBandInksAsTheStroke);
  - no gaps along a curve, and no darker joints where its short segments meet
    at shallow angles (TestAHairlineHasNoGaps, TestAShallowJointIsNotDarker);
  - the band's reach and edge: full within half the width less half a pixel
    of the path, half at half the width, nothing past it
    (TestTheBandIsTheDistance);
  - the band kept and replayed like the stroke's fill (TestAKeptBandReplays),
    and a chart's halos all drawn as bands, rotated ones too, kept on a
    repaint (TestAChartsHalosAreTheBand).

  What the fast ways do not model strokes the old way to the byte
  (TestWhatTheHairlineLeavesAlone), and ExactRendering puts every chart
  painter back on the canvas' way -- toggled on a live chart, the next frames
  are a fresh exact chart's (TestExactRenderingDrawsTheCanvasWay); every
  painter the chart draws with comes from the one place that sets the switch
  (TestEveryChartPainterIsNewPainter). }
interface

uses Classes, SysUtils, Math, Types, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Painter, tyControls.Controller,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Render, tyControls.AdvanceChart;

type
  TFsChart = class(TTyAdvanceChart)
  public
    procedure Layered(ACanvas: TCanvas; const ARect: TRect);
    procedure Render(ACanvas: TCanvas; const ARect: TRect);
  end;

  TAdvChartFastStrokesTest = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAHairlineInksAsTheStroke;
    procedure TestAHairlineHasNoGaps;
    procedure TestAHairlineKeepsToTheBitmapsClip;
    procedure TestAShallowJointIsNotDarker;
    procedure TestWhatTheHairlineLeavesAlone;
    procedure TestTheBandIsTheDistance;
    procedure TestTheBandInksAsTheStroke;
    procedure TestAKeptBandReplays;
    procedure TestAChartsHalosAreTheBand;
    procedure TestExactRenderingDrawsTheCanvasWay;
    procedure TestEveryChartPainterIsNewPainter;
  end;

implementation

const
  cW = 360;
  cH = 240;

procedure TFsChart.Layered(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
end;

procedure TFsChart.Render(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderTo(ACanvas, ARect, 96);
end;

procedure TAdvChartFastStrokesTest.SetUp;
begin
  inherited SetUp;
  TyAdvChartHaloCacheForTest(True);
  TyPainterKeptStrokesForTest(True);
end;

procedure TAdvChartFastStrokesTest.TearDown;
begin
  TyAdvChartHaloCacheForTest(True);
  TyPainterKeptStrokesForTest(True);
  inherited TearDown;
end;

{ ---- painter-level helpers ---- }

type
  TPathKind = (pkCurves, pkSteep, pkRing, pkZigzag, pkShallow, pkStraight, pkCross, pkFlat, pkPast, pkSpikes, pkLoop, pkVee);

{ the path of AKind on P, device px }
procedure TracePath(P: TTyPainter; AKind: TPathKind);
var
  i: Integer;
  a: Double;
begin
  P.BeginPath;
  case AKind of
    pkCurves:
      begin
        P.MoveTo(10, 30);
        P.CurveTo(120, 30, 200, 200, 350, 210);
        P.MoveTo(10, 200);
        P.CurveTo(90, 10, 260, 230, 350, 20.25);
      end;
    pkSteep:
      begin
        P.MoveTo(30.3, 4);
        P.CurveTo(30, 100, 140, 120, 150, 236);
        P.MoveTo(300, 5);
        P.LineTo(240.7, 230.2);
      end;
    pkRing:
      begin
        for i := 0 to 89 do
        begin
          a := i * 2 * Pi / 90;
          if i = 0 then P.MoveTo(180 + 80 * Cos(a), 120 + 80 * Sin(a))
          else P.LineTo(180 + 80 * Cos(a), 120 + 80 * Sin(a));
        end;
        P.ClosePath;
      end;
    pkZigzag:
      begin
        P.MoveTo(12, 120);
        for i := 1 to 30 do
          P.LineTo(12 + i * 11.1, 120 + ((i mod 4) - 1.5) * 9.7 * (1 + (i mod 3)));
      end;
    pkShallow:
      begin
        { 220 segments of 1.5 px, turning by a degree or two either way }
        P.MoveTo(10, 120);
        for i := 1 to 220 do
          P.LineTo(10 + i * 1.5, 120 + i * 0.03 + (i mod 2) * 0.04);
      end;
    pkStraight:
      begin
        P.MoveTo(10, 120);
        P.LineTo(340, 126.6);
      end;
    pkCross:
      begin
        { a figure of eight: the path crosses itself }
        for i := 0 to 120 do
        begin
          a := i * 2 * Pi / 120;
          if i = 0 then P.MoveTo(180 + 120 * Sin(a), 120 + 70 * Sin(2 * a))
          else P.LineTo(180 + 120 * Sin(a), 120 + 70 * Sin(2 * a));
        end;
        P.ClosePath;
      end;
    pkFlat:
      begin
        { level, on a row's centre: pixel-centred y 50 is device y 50.5 }
        P.MoveTo(20.5, 50.5);
        P.LineTo(300.5, 50.5);
        P.MoveTo(330.5, 20.5);
        P.LineTo(330.5, 220.5);
      end;
    pkVee:
      begin
        { one sharp turn, 8.6 degrees inside, its tip pointing up from (180, 120) }
        P.MoveTo(174, 200);
        P.LineTo(180, 120);
        P.LineTo(186, 200);
      end;
    pkSpikes:
      begin
        { sharp turns: mitred within the limit (33 degrees inside), and cut at it
          (8.6 degrees inside) }
        P.MoveTo(20, 60);
        for i := 1 to 12 do P.LineTo(20 + i * 12, 60 + (i mod 2) * 40);
        P.MoveTo(20, 140);
        for i := 1 to 24 do P.LineTo(20 + i * 3, 140 + (i mod 2) * 40);
      end;
    pkPast:
      begin
        { past every edge of the bitmap }
        P.MoveTo(-40, 100);
        P.LineTo(400, 140.3);
        P.MoveTo(100.2, -30);
        P.LineTo(140, 270);
        P.MoveTo(-20, -10);
        P.CurveTo(200, 300, 250, -100, 420, 260);
        { along the bitmap clip's top and left edges, a third of a pixel inside them }
        P.MoveTo(60, 30.2);
        P.LineTo(280, 30.2);
        P.MoveTo(50.2, 40);
        P.LineTo(50.2, 190);
      end;
    pkLoop:
      begin
        { a tight bend: the flattened points far from straight }
        P.MoveTo(100, 200);
        P.CurveTo(400, -60, -60, -60, 250, 200);
      end;
  end;
end;

type
  TStrokeWay = (swExact, swFast, swBand, swKept);

{ a bitmap AW x AH of AGround with AKind stroked AWay: at AScale raster px per
  device px, dashed, under a non-uniform scale, under a clip rect, at an element
  alpha as asked }
function Stroke(AKind: TPathKind; AWay: TStrokeWay; AColour: TTyColor; AWidth: Double;
  AGround: TBGRAPixel; AScale: Integer = 1; ADash: Boolean = False; ASkew: Boolean = False;
  AClip: Boolean = False; AAlpha: Double = 1; ABmpClip: Boolean = False): TBGRABitmap;
var
  p: TTyPainter;
  sc: TTyCanvasScale;
begin
  Result := TBGRABitmap.Create(cW * AScale, cH * AScale, AGround);
  p := TTyPainter.Create;
  try
    p.FastStrokes := AWay = swFast;
    sc.Scale := AScale;
    sc.DeviceUnits := False;
    p.BeginPaintOnScaled(nil, Rect(0, 0, cW, cH), 96, Result, sc);
    p.SaveState;
    if AAlpha < 1 then p.SetElementAlpha(AAlpha);
    if AClip then p.ClipRect(Rect(60, 40, 260, 180));
    { a pen scaled unequally (the path's transform alone leaves the pen round) }
    if ASkew then p.Bitmap.Canvas2D.strokeScale(1, 1.5);
    if ADash then p.SetLineDash([4, 2]);
    if AKind = pkFlat then p.SetLineCap(tlcRound);
    if ABmpClip then Result.ClipRect := Rect(50, 30, 300, 200);
    TracePath(p, AKind);
    case AWay of
      swBand: p.StrokePathByDistance(AColour, AWidth);
      swKept: p.StrokePathKept(AColour, AWidth);
    else
      p.StrokePath(AColour, AWidth);
    end;
    p.RestoreState;
    p.EndPaint;
    if ABmpClip then Result.NoClip;
  finally
    p.Free;
  end;
end;

function DiffPixels(A, B: TBGRABitmap): Integer;
var
  i: Integer;
  pa, pb: PLongWord;
begin
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(MaxInt);
  Result := 0;
  pa := PLongWord(A.Data);
  pb := PLongWord(B.Data);
  for i := 0 to A.NbPixels - 1 do
  begin
    if pa^ <> pb^ then Inc(Result);
    Inc(pa);
    Inc(pb);
  end;
end;

{ the coverage laid on a transparent ground: the alpha, summed }
function AlphaInk(B: TBGRABitmap): Double;
var
  i: Integer;
  p: PBGRAPixel;
begin
  Result := 0;
  p := B.Data;
  for i := 0 to B.NbPixels - 1 do
  begin
    Result := Result + p^.alpha;
    Inc(p);
  end;
end;

function AlphaAt(B: TBGRABitmap; AX, AY: Integer): Integer;
begin
  Result := B.GetPixel(AX, AY).alpha;
end;

function ColumnInk(B: TBGRABitmap; AX: Integer): Double;
var y: Integer;
begin
  Result := 0;
  for y := 0 to B.Height - 1 do Result := Result + B.GetPixel(AX, y).alpha;
end;

function RowInk(B: TBGRABitmap; AY: Integer): Double;
var x: Integer;
begin
  Result := 0;
  for x := 0 to B.Width - 1 do Result := Result + B.GetPixel(x, AY).alpha;
end;

{ darkness on a white ground, summed over a rect }
function Darkness(B: TBGRABitmap; const R: TRect): Double;
var
  x, y: Integer;
  c: TBGRAPixel;
begin
  Result := 0;
  for y := Max(0, R.Top) to Min(B.Height, R.Bottom) - 1 do
    for x := Max(0, R.Left) to Min(B.Width, R.Right) - 1 do
    begin
      c := B.GetPixel(x, y);
      Result := Result + (765 - c.red - c.green - c.blue);
    end;
end;

const
  cInk = TTyColor($FF102030);
  cHalfInk = TTyColor($80C02040);

{ THE INK: summed over the bitmap, a hairline lays what BGRA's fill of the
  pen's polygon lays, within 3% -- on curves, steep curves, a closed ring and
  a zigzag, at three widths, opaque and translucent ink, at 1x and (narrower
  than a raster pixel there too) at 2x; and the hairline did take them }
procedure TAdvChartFastStrokesTest.TestAHairlineInksAsTheStroke;
const
  cWidths: array[0..2] of Double = (0.25, 0.5, 0.85);
var
  k: TPathKind;
  wi, h0: Integer;
  e, f: TBGRABitmap;
  ie, iff: Double;
  tag: string;
begin
  for k in [pkCurves, pkSteep, pkRing, pkZigzag] do
    for wi := 0 to High(cWidths) do
    begin
      tag := Format('kind %d width %g', [Ord(k), cWidths[wi]]);
      e := Stroke(k, swExact, cInk, cWidths[wi], BGRAPixelTransparent);
      h0 := TyPainterHairlinesForTest;
      f := Stroke(k, swFast, cInk, cWidths[wi], BGRAPixelTransparent);
      try
        AssertEquals(tag + ': the hairline took it', h0 + 1, TyPainterHairlinesForTest);
        ie := AlphaInk(e);
        iff := AlphaInk(f);
        AssertTrue(tag + Format(': ink %.0f against %.0f', [iff, ie]),
          (ie > 0) and (Abs(iff / ie - 1) < 0.03));
        AssertTrue(tag + ': not the same pixels', DiffPixels(e, f) > 0);
      finally
        e.Free;
        f.Free;
      end;
    end;
  { translucent ink over a white ground, under an element alpha }
  e := Stroke(pkCurves, swExact, cHalfInk, 0.5, BGRAWhite, 1, False, False, False, 0.6);
  f := Stroke(pkCurves, swFast, cHalfInk, 0.5, BGRAWhite, 1, False, False, False, 0.6);
  try
    ie := Darkness(e, Rect(0, 0, cW, cH));
    iff := Darkness(f, Rect(0, 0, cW, cH));
    AssertTrue(Format('translucent: darkness %.0f against %.0f', [iff, ie]),
      (ie > 0) and (Abs(iff / ie - 1) < 0.03));
  finally
    e.Free;
    f.Free;
  end;
  { at 2x, 0.4 px is 0.8 raster px }
  e := Stroke(pkCurves, swExact, cInk, 0.4, BGRAPixelTransparent, 2);
  h0 := TyPainterHairlinesForTest;
  f := Stroke(pkCurves, swFast, cInk, 0.4, BGRAPixelTransparent, 2);
  try
    AssertEquals('2x: the hairline took it', h0 + 1, TyPainterHairlinesForTest);
    ie := AlphaInk(e);
    iff := AlphaInk(f);
    AssertTrue(Format('2x: ink %.0f against %.0f', [iff, ie]),
      (ie > 0) and (Abs(iff / ie - 1) < 0.03));
  finally
    e.Free;
    f.Free;
  end;
  { under a clip rect (a Canvas2D clip mask): nothing outside it, the same ink inside }
  e := Stroke(pkCurves, swExact, cInk, 0.5, BGRAPixelTransparent, 1, False, False, True);
  h0 := TyPainterHairlinesForTest;
  f := Stroke(pkCurves, swFast, cInk, 0.5, BGRAPixelTransparent, 1, False, False, True);
  try
    AssertEquals('clipped: the hairline took it', h0 + 1, TyPainterHairlinesForTest);
    ie := AlphaInk(e);
    iff := AlphaInk(f);
    AssertTrue(Format('clipped: ink %.0f against %.0f', [iff, ie]),
      (ie > 0) and (Abs(iff / ie - 1) < 0.03));
    AssertEquals('nothing outside the clip', 0.0,
      ColumnInk(f, 40) + ColumnInk(f, 58) + RowInk(f, 20) + RowInk(f, 200));
  finally
    e.Free;
    f.Free;
  end;
end;

{ NO GAPS: along a curve that runs mostly across, every column it crosses has
  ink, within a third of what the fill lays there; along one that runs mostly
  down, every row }
procedure TAdvChartFastStrokesTest.TestAHairlineHasNoGaps;
var
  e, f: TBGRABitmap;
  x, y: Integer;
  ce, cf, moved, total: Double;
  k: TPathKind;
begin
  { the coverage lies where the fill's does: on the curves and a tight bend, the
    pixels' differences summed are under a quarter of the ink (about a tenth
    here) -- a hairline a few tenths of a pixel off its course differs by most
    of it }
  for k in [pkCurves, pkLoop] do
  begin
    e := Stroke(k, swExact, cInk, 0.5, BGRAPixelTransparent);
    f := Stroke(k, swFast, cInk, 0.5, BGRAPixelTransparent);
    try
      moved := 0;
      total := 0;
      for y := 0 to cH - 1 do
        for x := 0 to cW - 1 do
        begin
          moved := moved + Abs(AlphaAt(f, x, y) - AlphaAt(e, x, y));
          total := total + AlphaAt(e, x, y);
        end;
      AssertTrue(Format('kind %d: the coverage moved %.0f of %.0f', [Ord(k), moved, total]),
        (total > 0) and (moved < 0.25 * total));
    finally
      e.Free;
      f.Free;
    end;
  end;
  e := Stroke(pkStraight, swExact, cInk, 0.5, BGRAPixelTransparent);
  f := Stroke(pkStraight, swFast, cInk, 0.5, BGRAPixelTransparent);
  try
    for x := 12 to 337 do
    begin
      ce := ColumnInk(e, x);
      cf := ColumnInk(f, x);
      AssertTrue(Format('straight: column %d has ink (%.0f against %.0f)', [x, cf, ce]),
        (cf > 0) and (Abs(cf - ce) <= ce / 3));
    end;
  finally
    e.Free;
    f.Free;
  end;
  e := Stroke(pkCurves, swExact, cInk, 0.5, BGRAPixelTransparent);
  f := Stroke(pkCurves, swFast, cInk, 0.5, BGRAPixelTransparent);
  try
    for x := 12 to 347 do
    begin
      ce := ColumnInk(e, x);
      cf := ColumnInk(f, x);
      AssertTrue(Format('curves: column %d has ink (%.0f against %.0f)', [x, cf, ce]),
        (cf > 0) and (Abs(cf - ce) <= ce / 3));
    end;
  finally
    e.Free;
    f.Free;
  end;
  e := Stroke(pkSteep, swExact, cInk, 0.5, BGRAPixelTransparent);
  f := Stroke(pkSteep, swFast, cInk, 0.5, BGRAPixelTransparent);
  try
    for y := 6 to 228 do
    begin
      ce := RowInk(e, y);
      cf := RowInk(f, y);
      AssertTrue(Format('steep: row %d has ink (%.0f against %.0f)', [y, cf, ce]),
        (cf > 0) and (Abs(cf - ce) <= ce / 3));
    end;
  finally
    e.Free;
    f.Free;
  end;
end;

{ THE BITMAP'S CLIP RECT, and its edges: lines and a curve running past every
  edge of the bitmap, under a clip rect on it, lay nothing outside the clip and
  inside it the fill's ink within 3%; past the edges with no clip, the same }
procedure TAdvChartFastStrokesTest.TestAHairlineKeepsToTheBitmapsClip;
var
  e, f: TBGRABitmap;
  x, y: Integer;
  ie, iff, outside: Double;
begin
  e := Stroke(pkPast, swExact, cInk, 0.5, BGRAPixelTransparent, 1, False, False, False, 1, True);
  f := Stroke(pkPast, swFast, cInk, 0.5, BGRAPixelTransparent, 1, False, False, False, 1, True);
  try
    outside := 0;
    for y := 0 to cH - 1 do
      for x := 0 to cW - 1 do
        if (x < 50) or (x >= 300) or (y < 30) or (y >= 200) then
          outside := outside + AlphaAt(f, x, y);
    AssertEquals('nothing outside the bitmap''s clip', 0.0, outside);
    ie := AlphaInk(e);
    iff := AlphaInk(f);
    AssertTrue(Format('clipped: ink %.0f against %.0f', [iff, ie]),
      (ie > 0) and (Abs(iff / ie - 1) < 0.03));
  finally
    e.Free;
    f.Free;
  end;
  e := Stroke(pkPast, swExact, cInk, 0.5, BGRAPixelTransparent);
  f := Stroke(pkPast, swFast, cInk, 0.5, BGRAPixelTransparent);
  try
    ie := AlphaInk(e);
    iff := AlphaInk(f);
    AssertTrue(Format('past the edges: ink %.0f against %.0f', [iff, ie]),
      (ie > 0) and (Abs(iff / ie - 1) < 0.03));
    { the level line runs in at the left edge and out at the right }
    AssertTrue('the first column', ColumnInk(f, 0) > 0);
    AssertTrue('the last column', ColumnInk(f, cW - 1) > 0);
  finally
    e.Free;
    f.Free;
  end;
end;

{ NO DARKER JOINTS: 220 segments of 1.5 px turning a degree or two either way
  lay, column by column, what one straight line of the same course lays --
  no column, and no pixel, darker by more than a twentieth }
procedure TAdvChartFastStrokesTest.TestAShallowJointIsNotDarker;
var
  s, j: TBGRABitmap;
  x, y: Integer;
  cs, cj, maxS, maxJ: Double;
begin
  s := Stroke(pkStraight, swFast, cInk, 0.5, BGRAPixelTransparent);
  j := Stroke(pkShallow, swFast, cInk, 0.5, BGRAPixelTransparent);
  try
    maxS := 0;
    maxJ := 0;
    for x := 14 to 335 do
    begin
      cs := ColumnInk(s, x);
      cj := ColumnInk(j, x);
      AssertTrue(Format('column %d: %.0f against the straight line''s %.0f', [x, cj, cs]),
        cj <= cs * 1.05 + 2);
      for y := 100 to 140 do
      begin
        maxS := Max(maxS, AlphaAt(s, x, y));
        maxJ := Max(maxJ, AlphaAt(j, x, y));
      end;
    end;
    AssertTrue(Format('the darkest pixel %.0f against %.0f', [maxJ, maxS]),
      maxJ <= maxS * 1.05 + 2);
  finally
    s.Free;
    j.Free;
  end;
  { and where two 0.9 px curves cross, the coverage sums to full and stops
    there: the pixel at the crossing is no lighter than either line's darkest }
  s := Stroke(pkCurves, swFast, TTyColor($FF000000), 0.9, BGRAPixelTransparent);
  try
    maxS := 0;
    for x := 0 to cW - 1 do
      for y := 0 to cH - 1 do
        maxS := Max(maxS, AlphaAt(s, x, y));
    AssertEquals('a crossing reaches full and no further', 255.0, maxS);
  finally
    s.Free;
  end;
end;

{ WHAT IT DOES NOT MODEL strokes as before, to the byte: a dashed hairline, a pen
  a raster pixel wide or wider (1 px at 1x, 0.5 px at 2x), a non-uniform scale;
  and a painter without FastStrokes never takes the hairline }
procedure TAdvChartFastStrokesTest.TestWhatTheHairlineLeavesAlone;

  procedure Same(const ATag: string; AWidth: Double; AScale: Integer; ADash, ASkew: Boolean);
  var
    e, f: TBGRABitmap;
    h0: Integer;
  begin
    e := Stroke(pkCurves, swExact, cInk, AWidth, BGRAPixelTransparent, AScale, ADash, ASkew);
    h0 := TyPainterHairlinesForTest;
    f := Stroke(pkCurves, swFast, cInk, AWidth, BGRAPixelTransparent, AScale, ADash, ASkew);
    try
      AssertEquals(ATag + ': the same pixels', 0, DiffPixels(e, f));
      AssertEquals(ATag + ': not the hairline', h0, TyPainterHairlinesForTest);
    finally
      e.Free;
      f.Free;
    end;
  end;

var
  e: TBGRABitmap;
  h0: Integer;
begin
  Same('dashed', 0.5, 1, True, False);
  Same('one pixel', 1, 1, False, False);
  Same('two pixels', 2, 1, False, False);
  Same('half a px at 2x', 0.5, 2, False, False);
  Same('skewed', 0.5, 1, False, True);
  h0 := TyPainterHairlinesForTest;
  e := Stroke(pkCurves, swExact, cInk, 0.5, BGRAPixelTransparent);
  e.Free;
  e := Stroke(pkCurves, swKept, cInk, 0.5, BGRAPixelTransparent);
  e.Free;
  AssertEquals('off: never the hairline', h0, TyPainterHairlinesForTest);
end;

{ THE BAND'S REACH AND EDGE: a level and an upright path on row and column
  centres, 4 px wide -- full within 1.5 px of it, half at 2, nothing at 3; past
  an open end the band goes round (full 1.5 px beyond it, nothing 2.5 px
  beyond). 1 px wide: full on the path, nothing a pixel off it. }
procedure TAdvChartFastStrokesTest.TestTheBandIsTheDistance;
var
  b, e: TBGRABitmap;
  x, y: Integer;
begin
  b := Stroke(pkFlat, swBand, TTyColor($FF000000), 4, BGRAPixelTransparent);
  try
    for x := 40 to 280 do
    begin
      AssertEquals(Format('level, column %d, on it', [x]), 255, AlphaAt(b, x, 50));
      AssertEquals(Format('level, column %d, 1 off', [x]), 255, AlphaAt(b, x, 49));
      AssertEquals(Format('level, column %d, 1 off below', [x]), 255, AlphaAt(b, x, 51));
      AssertTrue(Format('level, column %d, 2 off: half', [x]),
        Abs(AlphaAt(b, x, 48) - 128) <= 1);
      AssertTrue(Format('level, column %d, 2 off below: half', [x]),
        Abs(AlphaAt(b, x, 52) - 128) <= 1);
      AssertEquals(Format('level, column %d, 3 off', [x]), 0, AlphaAt(b, x, 47));
      AssertEquals(Format('level, column %d, 3 off below', [x]), 0, AlphaAt(b, x, 53));
    end;
    for y := 40 to 200 do
    begin
      AssertEquals(Format('upright, row %d, on it', [y]), 255, AlphaAt(b, 330, y));
      AssertTrue(Format('upright, row %d, 2 off: half', [y]),
        Abs(AlphaAt(b, 328, y) - 128) <= 1);
      AssertEquals(Format('upright, row %d, 3 off', [y]), 0, AlphaAt(b, 333, y));
    end;
    { the level path ends at pixel-centred x 300: round past it }
    AssertEquals('1 past the end', 255, AlphaAt(b, 301, 50));
    AssertTrue('2 past the end: half', Abs(AlphaAt(b, 302, 50) - 128) <= 1);
    AssertEquals('3 past the end', 0, AlphaAt(b, 303, 50));
    { the corner of the round end: (2, 2) off is 2.83 away, outside 2.5 }
    AssertEquals('the cap is round', 0, AlphaAt(b, 302, 52));
  finally
    b.Free;
  end;
  b := Stroke(pkFlat, swBand, TTyColor($FF000000), 1, BGRAPixelTransparent);
  try
    AssertEquals('1 px: on it', 255, AlphaAt(b, 100, 50));
    AssertEquals('1 px: a pixel off', 0, AlphaAt(b, 100, 49));
  finally
    b.Free;
  end;
  { A MITER CUT AT THE LIMIT: a turn of 8.6 degrees inside, 5 px wide -- its tip
    would lie 33 px above the vertex, the limit (10) cuts it at 25, as BGRA's
    pen does: inked 20 px up, nothing 28 px up, in the band as in the stroke }
  b := Stroke(pkVee, swBand, TTyColor($FF000000), 5, BGRAPixelTransparent);
  e := Stroke(pkVee, swKept, TTyColor($FF000000), 5, BGRAPixelTransparent);
  try
    AssertTrue('the stroke: 20 up', AlphaAt(e, 179, 100) + AlphaAt(e, 180, 100) > 0);
    AssertEquals('the stroke: 28 up', 0, AlphaAt(e, 179, 92) + AlphaAt(e, 180, 92));
    AssertTrue('the band: 20 up', AlphaAt(b, 179, 100) + AlphaAt(b, 180, 100) > 0);
    AssertEquals('the band: 28 up', 0, AlphaAt(b, 179, 92) + AlphaAt(b, 180, 92));
  finally
    b.Free;
    e.Free;
  end;
end;

{ THE BAND'S INK is the stroke's within 3% on a ring, a figure of eight (that
  crosses itself) and zigzags whose miters run long and are cut, at three widths; laid once, so a translucent band never goes
  past its colour's alpha where the path comes back near itself }
procedure TAdvChartFastStrokesTest.TestTheBandInksAsTheStroke;
const
  cWidths: array[0..2] of Double = (1.5, 3, 5);
var
  k: TPathKind;
  wi, x, y, top: Integer;
  e, f: TBGRABitmap;
  ie, iff: Double;
  tag: string;
begin
  for k in [pkRing, pkCross, pkSpikes] do
    for wi := 0 to High(cWidths) do
    begin
      tag := Format('kind %d width %g', [Ord(k), cWidths[wi]]);
      e := Stroke(k, swKept, cInk, cWidths[wi], BGRAPixelTransparent);
      f := Stroke(k, swBand, cInk, cWidths[wi], BGRAPixelTransparent);
      try
        ie := AlphaInk(e);
        iff := AlphaInk(f);
        AssertTrue(tag + Format(': ink %.0f against %.0f', [iff, ie]),
          (ie > 0) and (Abs(iff / ie - 1) < 0.03));
      finally
        e.Free;
        f.Free;
      end;
    end;
  f := Stroke(pkCross, swBand, cHalfInk, 6, BGRAPixelTransparent);
  try
    top := 0;
    for y := 0 to cH - 1 do
      for x := 0 to cW - 1 do
        top := Max(top, AlphaAt(f, x, y));
    AssertEquals('translucent, crossing itself: laid once', $80, top);
  finally
    f.Free;
  end;
end;

{ THE BAND KEPT: the same path again is replayed, not computed, and paints as
  a fresh one; another colour and an element alpha replay the same coverage;
  another width, or the path moved, is another band; with keeping off every
  call computes. Under a clip mask too. }
procedure TAdvChartFastStrokesTest.TestAKeptBandReplays;
var
  ref, a: TBGRABitmap;
  m0, r0: Integer;
begin
  TyPainterKeptStrokesForTest(False);
  ref := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
  TyPainterKeptStrokesForTest(True);
  try
    m0 := TyPainterDistanceStrokesForTest;
    r0 := TyPainterDistanceReplaysForTest;
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
    AssertEquals('first: computed', m0 + 1, TyPainterDistanceStrokesForTest);
    AssertEquals('first: a fresh band', 0, DiffPixels(a, ref));
    a.Free;
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
    AssertEquals('again: not computed', m0 + 1, TyPainterDistanceStrokesForTest);
    AssertEquals('again: replayed', r0 + 1, TyPainterDistanceReplaysForTest);
    AssertEquals('again: the same pixels', 0, DiffPixels(a, ref));
    a.Free;
    ref.Free;
    TyPainterKeptStrokesForTest(False);
    ref := Stroke(pkRing, swBand, cHalfInk, 3, BGRAWhite, 1, False, False, False, 0.5);
    TyPainterKeptStrokesForTest(True);
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
    a.Free;
    m0 := TyPainterDistanceStrokesForTest;
    a := Stroke(pkRing, swBand, cHalfInk, 3, BGRAWhite, 1, False, False, False, 0.5);
    AssertEquals('another colour, an element alpha: replayed', m0, TyPainterDistanceStrokesForTest);
    AssertEquals('another colour, an element alpha: as fresh', 0, DiffPixels(a, ref));
    a.Free;
    a := Stroke(pkRing, swBand, cInk, 4, BGRAWhite);
    AssertEquals('another width: computed', m0 + 1, TyPainterDistanceStrokesForTest);
    a.Free;
    a := Stroke(pkCross, swBand, cInk, 3, BGRAWhite);
    AssertEquals('another path: computed', m0 + 2, TyPainterDistanceStrokesForTest);
    a.Free;
    { under a clip mask: replayed through the mask's scanner }
    ref.Free;
    TyPainterKeptStrokesForTest(False);
    ref := Stroke(pkRing, swBand, cInk, 3, BGRAWhite, 1, False, False, True);
    m0 := TyPainterDistanceStrokesForTest;
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite, 1, False, False, True);
    AssertEquals('keeping off: computed every time', m0 + 1, TyPainterDistanceStrokesForTest);
    a.Free;
    TyPainterKeptStrokesForTest(True);
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
    a.Free;
    r0 := TyPainterDistanceReplaysForTest;
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite, 1, False, False, True);
    AssertEquals('clipped: replayed', r0 + 1, TyPainterDistanceReplaysForTest);
    AssertEquals('clipped: as fresh', 0, DiffPixels(a, ref));
    a.Free;
    { under another bitmap clip rect: another band }
    ref.Free;
    TyPainterKeptStrokesForTest(False);
    ref := Stroke(pkRing, swBand, cInk, 3, BGRAWhite, 1, False, False, False, 1, True);
    TyPainterKeptStrokesForTest(True);
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
    a.Free;
    m0 := TyPainterDistanceStrokesForTest;
    a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite, 1, False, False, False, 1, True);
    AssertEquals('another bitmap clip: computed', m0 + 1, TyPainterDistanceStrokesForTest);
    AssertEquals('another bitmap clip: as fresh', 0, DiffPixels(a, ref));
    a.Free;
    { every hash alike: the lookup decided by the compare -- another width, another
      clip computed anew and painted as fresh ones }
    TyPainterKeptFillHashesCollideForTest(True);
    try
      a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
      a.Free;
      m0 := TyPainterDistanceStrokesForTest;
      a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite, 1, False, False, False, 1, True);
      AssertEquals('colliding: another clip computed', m0 + 1, TyPainterDistanceStrokesForTest);
      AssertEquals('colliding: another clip as fresh', 0, DiffPixels(a, ref));
      a.Free;
      ref.Free;
      TyPainterKeptStrokesForTest(False);
      ref := Stroke(pkRing, swBand, cInk, 4, BGRAWhite);
      TyPainterKeptStrokesForTest(True);
      TyPainterKeptFillHashesCollideForTest(True);
      a := Stroke(pkRing, swBand, cInk, 3, BGRAWhite);
      a.Free;
      m0 := TyPainterDistanceStrokesForTest;
      a := Stroke(pkRing, swBand, cInk, 4, BGRAWhite);
      AssertEquals('colliding: another width computed', m0 + 1, TyPainterDistanceStrokesForTest);
      AssertEquals('colliding: another width as fresh', 0, DiffPixels(a, ref));
      a.Free;
    finally
      TyPainterKeptFillHashesCollideForTest(False);
    end;
  finally
    ref.Free;
  end;
end;

{ ---- chart-level ---- }

const
  { a radial tree's labels, turned every which way, and a bar chart's turned
    labels, all haloed dark on the light theme }
  cHaloTree = '{"animation": false, "series": [{"type": "tree", "layout": "radial",'
    + ' "expandAndCollapse": false, "symbolSize": 6,'
    + ' "label": {"textBorderColor": "#203040", "textBorderWidth": 3, "color": "#ffffff"},'
    + ' "data": [{"name": "root", "children": ['
    + '{"name": "alpha", "children": [{"name": "alpha one"}, {"name": "alpha two"}, {"name": "alpha three"}]},'
    + '{"name": "beta", "children": [{"name": "beta one"}, {"name": "beta two"}]},'
    + '{"name": "gamma", "children": [{"name": "gamma one"}, {"name": "gamma two"}, {"name": "gamma three"}]},'
    + '{"name": "delta", "children": [{"name": "delta one"}, {"name": "delta two"}]}'
    + ']}]}]}';
  cHaloBars = '{"animation": false, "xAxis": {"type": "category", "data": ["a", "b", "c", "d"]},'
    + ' "yAxis": {"type": "value"}, "series": [{"type": "bar", "data": [3, 5, 2, 4],'
    + ' "label": {"show": true, "position": "inside", "rotate": 40, "fontSize": 16,'
    + ' "formatter": "turned {c}", "color": "#ffffff",'
    + ' "textBorderColor": "#102030", "textBorderWidth": 4}}]}';

function NewChart(AForm: TForm; ACtl: TTyStyleController; const AOption: string;
  AExact: Boolean): TFsChart;
begin
  Result := TFsChart.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.AnimationMode := camOff;
  Result.ExactRendering := AExact;
  Result.SetBounds(0, 0, cW, cH);
  Result.Option := AOption;
end;

{ a frame as the window paints it (the static cache, the progressive layer),
  or drawn afresh }
function Shot(AChart: TFsChart; AFresh: Boolean = False): TBGRABitmap;
var bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cW, cH);
    if AFresh then AChart.Render(bmp.Canvas, Rect(0, 0, cW, cH))
    else AChart.Layered(bmp.Canvas, Rect(0, 0, cW, cH));
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function HaloCount(AChart: TFsChart): Integer;
var
  k: Integer;
  lst: TTyPaintList;
begin
  Result := 0;
  lst := AChart.SeriesList;
  for k := 0 to lst.Count - 1 do
    if (lst.Element(k).Caption.Text <> '') and (lst.Element(k).Caption.StrokeWidthLogical > 0)
      and ((lst.Element(k).Caption.StrokeColour shr 24) <> 0) then
      Inc(Result);
end;

{ A CHART'S HALOS ARE BANDS: every haloed label of the radial tree (turned
  every which way) and of the bars (turned 40 degrees) is one band -- no fill
  of a pen's polygon -- and a repaint computes none, traces none, replays
  each; the dark halos lay the exact stroke's ink within 5%; a dashed halo is
  stroked as before }
procedure TAdvChartFastStrokesTest.TestAChartsHalosAreTheBand;
var
  form: TForm;
  ctl: TTyStyleController;
  fast, exact: TFsChart;
  bf, be: TBGRABitmap;
  opt: string;
  i, n, m0, r0, t0, f0: Integer;
  df, de: Double;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    for i := 0 to 1 do
    begin
      if i = 0 then opt := cHaloTree else opt := cHaloBars;
      fast := NewChart(form, ctl, opt, False);
      exact := NewChart(form, ctl, opt, True);
      m0 := TyPainterDistanceStrokesForTest;
      f0 := TyPainterKeptStrokeFillsForTest;
      bf := Shot(fast, True);
      be := nil;
      try
        n := HaloCount(fast);
        AssertTrue(Format('option %d: haloed labels', [i]), n >= 4);
        AssertEquals(Format('option %d: a band per halo', [i]), n,
          TyPainterDistanceStrokesForTest - m0);
        AssertEquals(Format('option %d: no halo filled', [i]), f0, TyPainterKeptStrokeFillsForTest);
        m0 := TyPainterDistanceStrokesForTest;
        r0 := TyPainterDistanceReplaysForTest;
        t0 := TyAdvChartHaloTracesForTest;
        bf.Free;
        bf := nil;
        bf := Shot(fast, True);
        AssertEquals(Format('option %d: a repaint computes no band', [i]), m0,
          TyPainterDistanceStrokesForTest);
        AssertEquals(Format('option %d: traces no mask', [i]), t0, TyAdvChartHaloTracesForTest);
        AssertEquals(Format('option %d: replays each', [i]), n,
          TyPainterDistanceReplaysForTest - r0);
        m0 := TyPainterDistanceStrokesForTest;
        be := Shot(exact, True);
        AssertEquals(Format('option %d: exact draws no band', [i]), m0,
          TyPainterDistanceStrokesForTest);
        df := Darkness(bf, Rect(0, 0, cW, cH));
        de := Darkness(be, Rect(0, 0, cW, cH));
        { within 5%: the halo of a small glyph's outline -- marching squares, segments a
          pixel long, a pen three wide -- is a polygon BGRA fills with blots where the pen
          folds over itself on the short segments; the band is the strip it means }
        AssertTrue(Format('option %d: darkness %.0f against %.0f', [i, df, de]),
          (de > 0) and (Abs(df / de - 1) < 0.05));
        AssertTrue(Format('option %d: not the same pixels', [i]), DiffPixels(bf, be) > 0);
      finally
        bf.Free;
        be.Free;
        fast.Free;
        exact.Free;
      end;
    end;
    { a dashed halo is stroked as before }
    opt := StringReplace(cHaloBars, '"textBorderWidth": 4', '"textBorderWidth": 4,'
      + ' "textBorderType": "dashed"', []);
    fast := NewChart(form, ctl, opt, False);
    exact := NewChart(form, ctl, opt, True);
    bf := nil;
    be := nil;
    try
      m0 := TyPainterDistanceStrokesForTest;
      bf := Shot(fast, True);
      AssertEquals('a dashed halo: no band', m0, TyPainterDistanceStrokesForTest);
      be := Shot(exact, True);
      AssertEquals('a dashed halo: the stroke''s pixels', 0, DiffPixels(bf, be));
    finally
      bf.Free;
      be.Free;
      fast.Free;
      exact.Free;
    end;
  finally
    form.Free;
    ctl.Free;
  end;
end;

{ EXACTRENDERING: an exact chart takes neither fast way; and toggled on a live
  chart -- static picture, progressive layer and all -- the next frames are a
  fresh chart's of the new setting }
procedure TAdvChartFastStrokesTest.TestExactRenderingDrawsTheCanvasWay;
var
  form: TForm;
  ctl: TTyStyleController;
  live, ref: TFsChart;
  a, b: TBGRABitmap;
  opt, o: string;
  i, k, h0, m0, oi: Integer;

  procedure Drain(C: TFsChart);
  var
    j: Integer;
    bb: TBGRABitmap;
  begin
    j := 0;
    while C.ProgressiveUnfinished and (j < 200) do
    begin
      C.ProgressTick;
      bb := Shot(C);
      bb.Free;
      Inc(j);
    end;
  end;

begin
  { 300 smooth half-pixel lines, drawn progressively; and the haloed bars }
  opt := '{"animation": false, "parallelAxis": [{"dim": 0, "name": "one"},'
    + ' {"dim": 1, "name": "two"}, {"dim": 2, "name": "three"}],'
    + ' "series": [{"type": "parallel", "smooth": true, "progressive": 40,'
    + ' "progressiveThreshold": 100, "lineStyle": {"width": 0.5, "opacity": 0.4}, "data": [';
  for k := 0 to 299 do
  begin
    if k > 0 then opt := opt + ',';
    opt := opt + Format('[%d, %d, %d]', [(k * 37) mod 101, (k * 53) mod 89, (k * 71) mod 97]);
  end;
  opt := opt + ']}]}';
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    { exact: neither fast way }
    h0 := TyPainterHairlinesForTest;
    m0 := TyPainterDistanceStrokesForTest;
    for oi := 0 to 1 do
    begin
      if oi = 0 then o := opt else o := cHaloBars;
      ref := NewChart(form, ctl, o, True);
      a := Shot(ref);
      Drain(ref);
      a.Free;
      a := Shot(ref);
      a.Free;
      ref.Free;
    end;
    AssertEquals('exact: no hairline', h0, TyPainterHairlinesForTest);
    AssertEquals('exact: no band', m0, TyPainterDistanceStrokesForTest);
    { fast: the lines are hairlines, the halos bands }
    ref := NewChart(form, ctl, opt, False);
    a := Shot(ref);
    Drain(ref);
    a.Free;
    AssertTrue('fast: hairlines', TyPainterHairlinesForTest > h0);
    ref.Free;
    ref := NewChart(form, ctl, cHaloBars, False);
    a := Shot(ref);
    a.Free;
    AssertTrue('fast: a band', TyPainterDistanceStrokesForTest > m0);
    ref.Free;
    { toggled on a live chart, both ways, on both }
    for i := 0 to 5 do
    begin
      if (i < 2) or (i > 3) then o := opt else o := cHaloBars;
      live := NewChart(form, ctl, o, Odd(i));
      ref := NewChart(form, ctl, o, not Odd(i));
      a := nil;
      b := nil;
      try
        a := Shot(live);
        if i > 3 then
        begin
          { halfway through the progressive chunks, a chunk armed and not yet drawn }
          for k := 1 to 3 do
          begin
            a.Free;
            live.ProgressTick;
            if k < 3 then a := Shot(live) else a := nil;
          end;
        end
        else
        begin
          Drain(live);
          a.Free;
          a := Shot(live);
          a.Free;
        end;
        live.ExactRendering := not Odd(i);
        a := Shot(live);
        Drain(live);
        a.Free;
        a := Shot(live);
        b := Shot(ref);
        Drain(ref);
        b.Free;
        b := Shot(ref);
        AssertEquals(Format('case %d toggled to exact=%d: a fresh chart''s frame',
          [i div 2, Ord(not Odd(i))]), 0, DiffPixels(a, b));
      finally
        a.Free;
        b.Free;
        live.Free;
        ref.Free;
      end;
    end;
  finally
    form.Free;
    ctl.Free;
  end;
end;

{ EVERY PAINTER THE CHART DRAWS WITH comes from NewPainter, the one place that
  sets FastStrokes from ExactRendering: no other TTyPainter.Create in the
  control's units; and the affine caption's own painter takes the switch of the
  painter it draws for }
procedure TAdvChartFastStrokesTest.TestEveryChartPainterIsNewPainter;
var
  dir, text: string;
  sr: TSearchRec;
  sl: TStringList;
  n, p: Integer;
begin
  dir := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'source' + PathDelim;
  n := 0;
  sl := TStringList.Create;
  try
    if FindFirst(dir + 'tyControls.AdvanceChart.Control.*.inc', faAnyFile, sr) = 0 then
    try
      repeat
        sl.LoadFromFile(dir + sr.Name);
        text := sl.Text;
        p := Pos('TTyPainter.Create', text);
        while p > 0 do
        begin
          Inc(n);
          AssertTrue(sr.Name + ': only NewPainter creates a painter',
            Pos('function TTyAdvanceChart.NewPainter', Copy(text, Max(1, p - 200), 200)) > 0);
          p := Pos('TTyPainter.Create', text, p + 1);
        end;
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    AssertEquals('one creation, in NewPainter', 1, n);
    sl.LoadFromFile(dir + 'tyControls.AdvanceChart.pas');
    AssertEquals('none in the control''s unit', 0, Pos('TTyPainter.Create', sl.Text));
    sl.LoadFromFile(dir + 'tyControls.AdvanceChart.Render.pas');
    AssertTrue('the affine caption''s painter takes the switch',
      Pos('mp.FastStrokes := P.FastStrokes;', sl.Text) > 0);
  finally
    sl.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartFastStrokesTest);
end.
