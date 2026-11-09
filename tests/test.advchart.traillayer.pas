unit test.advchart.traillayer;

{ Round 7 R7-AJ (spec section 290): WHAT ELSE IS ON A TRAIL'S LAYER.

  allocateZlevels gives a lines series with a trail a zlevel of its own,
  and LinesView configures that zlevel's layer with motionBlur: every frame
  the layer is drawn back at lastFrameAlpha and every displayable on that
  zlevel is painted again over it, in display-list order. A graphic
  element keeps its own zlevel (updateCommonAttrs leaves a set one alone,
  zrender's default is 0), so it can share the trail's layer (the
  view-layers fixture's zl-graphic, zl-graphic-own): one that sorts before
  the lines is painted every frame after the fade and before them -- it
  covers the faded trail, the lines of the frame lie over it; one after
  them covers both. }

{$mode objfpc}{$H+}

interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.AdvanceChart;
type
  TTlProbe = class(TTyAdvanceChart)
  public
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function ZLevelOf(const AKey: string): Integer;
  end;

  TAdvChartTrailLayerTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TTlProbe;
    { an opaque 24-bit canvas, as a window's }
    FBmp: TBitmap;
    function Pix(AX, AY: Integer): TBGRAPixel;
    procedure Play(const AOption: string; AFrames: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAGraphicUnderTheTrailIsPaintedOnItsLayer;
    procedure TestAGraphicOnTheTrailsOwnLevelIsPaintedOnIt;
    procedure TestAGraphicOverATrailOfALowerZLevelStaysOver;
    procedure TestAGraphicUnderTheAxesIsOverALowerZLevel;
    procedure TestAGraphicUnderTheAxesBetweenAndOverTheirLevels;
    procedure TestAGraphicUnderTheCutIsDrawnOnce;
  end;

implementation

const
  cT0 = 1700000000000;
  { the lines of a trail along y 5 (150 px), from x 1 (72 px) to 9 (328 px),
    the symbol 256 px a second; no axis drawn; on an opaque white ground }
  cBase = '{"animation":true,"animationDuration":0,"animationDurationUpdate":0,"backgroundColor":"#ffffff",'
    + '"grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"yAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"graphic":[%s],'
    + '"series":[{"type":"lines","coordinateSystem":"cartesian2d","z":%d,'
    + '"lineStyle":{"color":"#ff0000","width":2,"opacity":1},'
    + '"effect":{"show":true,"trailLength":0.4,"period":1,"symbol":"circle","symbolSize":12,"delay":0,"color":"#ff0000"},'
    + '"data":[{"coords":[[1,5],[9,5]]}]}]}';

procedure PinClocks(AChart: TTyCustomAdvanceChart; AAt: Double);
begin
  AChart.AnimNow := AAt;
  AChart.TooltipNow := AAt;
  AChart.DataZoomNow := AAt;
  AChart.BrushNow := AAt;
  AChart.ParallelExpandNow := AAt;
  AChart.TimelineNow := AAt;
end;

procedure TTlProbe.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

function TTlProbe.ZLevelOf(const AKey: string): Integer;
begin
  Result := ZLevelOfModel(AKey);
end;

procedure TAdvChartTrailLayerTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartTrailLayerTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartTrailLayerTest.Play(const AOption: string; AFrames: Integer);
var t: Integer;
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FChart := TTlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 400, 300);
  PinClocks(FChart, cT0);
  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf24bit;
  FBmp.SetSize(400, 300);
  FBmp.Canvas.Brush.Color := clWhite;
  FBmp.Canvas.FillRect(Rect(0, 0, 400, 300));
  FChart.AnimationMode := camAlways;
  FChart.SetOption(AOption, True);
  AssertEquals('parses', '', FChart.OptionError);
  FChart.Layered(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  for t := 1 to AFrames do
  begin
    PinClocks(FChart, cT0 + t * 16);
    FChart.AnimTick(cT0 + t * 16);
    FChart.Layered(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  end;
  if GetEnvironmentVariable('TY_TL_SAVE') <> '' then
    FBmp.SaveToFile(GetEnvironmentVariable('TY_TL_SAVE') + 'trail-gfx-' + IntToStr(Length(AOption)) + '.bmp');
end;

function TAdvChartTrailLayerTest.Pix(AX, AY: Integer): TBGRAPixel;
var c: TColor;
begin
  c := ColorToRGB(FBmp.Canvas.Pixels[AX, AY]);
  Result := BGRA(Red(c), Green(c), Blue(c), 255);
end;

function Px(const P: TBGRAPixel): string;
begin
  Result := Format('(%d,%d,%d)', [P.red, P.green, P.blue]);
end;

{ THE LINES OF z -1 ON zlevel 0, the axes on 1; two rects of the graphic on
  zlevel 0 too (zrender's default): one of z -5 under the lines, one of
  z 0 over them -- both on the trail's layer, painted every frame [was: the
  one under the lines drawn once, the faded trail over it] }
procedure TAdvChartTrailLayerTest.TestAGraphicUnderTheTrailIsPaintedOnItsLayer;
var p: TBGRAPixel;
begin
  Play(Format(cBase, ['{"type":"rect","z":-5,"shape":{"x":100,"y":120,"width":60,"height":60},'
    + '"style":{"fill":"#00ff00"}},{"type":"rect","shape":{"x":250,"y":120,"width":40,"height":60},'
    + '"style":{"fill":"#0000ff"}},{"type":"rect","z":-5,"shape":{"x":200,"y":60,"width":40,"height":40},'
    + '"style":{"fill":"#00ff00","opacity":0.5}}', -1]), 30);
  AssertEquals('the lines on zlevel 0', 0, FChart.ZLevelOf('S0'));
  AssertEquals('the axes on zlevel 1', 1, FChart.ZLevelOf('xAxis0'));
  { the symbol passed x 130 some 250 ms ago: there the rect, painted after
    the fade, covers the trail }
  p := Pix(130, 146);
  AssertTrue('the rect under the lines over the faded trail: ' + Px(p),
    (p.green > 230) and (p.red < 30) and (p.blue < 30));
  { the frame's line over it }
  p := Pix(130, 150);
  AssertTrue('the line over the rect under it: ' + Px(p), (p.red > 200) and (p.green < 60));
  { the rect of z 0 over the line }
  p := Pix(270, 150);
  AssertTrue('the rect after the lines over them: ' + Px(p), (p.blue > 230) and (p.red < 30));
  { off the rects, the trail fades as before }
  p := Pix(180, 146);
  AssertTrue('the trail beside the rects: ' + Px(p), (p.red > 200) and (p.red - p.green > 40));
  { a rect of opacity 0.5 painted every frame over the layer drawn back at
    0.94 (trailLength 0.4): its alpha a = 0.5 + 0.5 * 0.94 * a, near 0.943
    after 31 frames -- over white about (14, 255, 14) [was: drawn once,
    (127, 255, 127)] }
  p := Pix(220, 80);
  AssertTrue('the half-clear rect on the trail''s layer, its frames summed: ' + Px(p),
    (p.red >= 10) and (p.red <= 19) and (p.green > 250) and (Abs(p.red - p.blue) <= 2));
end;

{ THE LINES OF THE DEFAULT z ON zlevel 1 (the axes on 0), a rect of the
  graphic written onto zlevel 1 at z 1: under the lines (z 2) on their
  layer, over the faded trail [was: drawn over the lines, every frame] }
procedure TAdvChartTrailLayerTest.TestAGraphicOnTheTrailsOwnLevelIsPaintedOnIt;
var p: TBGRAPixel;
begin
  Play(Format(cBase, ['{"type":"rect","zlevel":1,"z":1,"shape":{"x":100,"y":120,"width":60,"height":60},'
    + '"style":{"fill":"#00ff00"}}', 2]), 30);
  AssertEquals('the lines on zlevel 1', 1, FChart.ZLevelOf('S0'));
  AssertEquals('the axes on zlevel 0', 0, FChart.ZLevelOf('xAxis0'));
  p := Pix(130, 150);
  AssertTrue('the line over the rect of a lower z: ' + Px(p), (p.red > 200) and (p.green < 60));
  p := Pix(130, 146);
  AssertTrue('the rect over the faded trail: ' + Px(p),
    (p.green > 230) and (p.red < 30) and (p.blue < 30));
  p := Pix(180, 146);
  AssertTrue('the trail beside the rect: ' + Px(p), (p.red > 200) and (p.red - p.green > 40));
end;

{ THE LINES WRITTEN ONTO zlevel -1 (the axes and the graphic on 0): the
  graphic's rect of z -5 is on a layer over the trail's -- over the trail
  and the line, the frames' as the trail's [was: drawn once under them] }
procedure TAdvChartTrailLayerTest.TestAGraphicOverATrailOfALowerZLevelStaysOver;
var p: TBGRAPixel; opt: string;
begin
  opt := StringReplace(Format(cBase, ['{"type":"rect","z":-5,"shape":{"x":100,"y":120,"width":60,"height":60},'
    + '"style":{"fill":"#00ff00"}},{"type":"rect","z":-5,"shape":{"x":200,"y":60,"width":40,"height":40},'
    + '"style":{"fill":"#00ff00","opacity":0.5}}', 2]), '"coordinateSystem":"cartesian2d",',
    '"coordinateSystem":"cartesian2d","zlevel":-1,', []);
  Play(opt, 30);
  AssertEquals('the lines on zlevel -1', -1, FChart.ZLevelOf('S0'));
  AssertEquals('the axes on zlevel 0', 0, FChart.ZLevelOf('xAxis0'));
  p := Pix(130, 150);
  AssertTrue('the rect over the line: ' + Px(p), (p.green > 230) and (p.red < 30));
  p := Pix(130, 146);
  AssertTrue('the rect over the trail: ' + Px(p), (p.green > 230) and (p.red < 30));
  p := Pix(180, 146);
  AssertTrue('the trail beside the rect: ' + Px(p), (p.red > 200) and (p.red - p.green > 40));
  { a rect of opacity 0.5 on a layer of no motion blur: drawn once a frame }
  p := Pix(220, 80);
  AssertTrue('the half-clear rect drawn once: ' + Px(p),
    (p.red >= 124) and (p.red <= 131) and (p.green > 250) and (Abs(p.red - p.blue) <= 2));
end;

{ AT REST, THE LEVELS DRAWN APART (a series written onto zlevel -1, the axes
  on 0): the graphic's rect of z -5 under the axes is on zlevel 0, over the
  series' canvas [was: drawn first of all, under it] }
procedure TAdvChartTrailLayerTest.TestAGraphicUnderTheAxesIsOverALowerZLevel;
const
  cHalfMixed = '{"animation":false,"backgroundColor":"#ffffff","grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"show":false},"yAxis":{"type":"value","min":0,"max":10,"show":false},'
    + '"graphic":[{"type":"rect","z":-5,"shape":{"x":180,"y":130,"width":40,"height":40},"style":{"fill":"#00ff00"}},'
    + '{"type":"rect","z":-5,"shape":{"x":300,"y":60,"width":40,"height":40},"style":{"fill":"#00ff00","opacity":0.5}}],'
    + '"series":[{"type":"scatter","zlevel":-1,"symbolSize":60,"itemStyle":{"color":"#ff0000","opacity":1},"data":[[5,5]]}]}';
var p, q: TBGRAPixel;
begin
  Play(cHalfMixed, 0);
  p := Pix(200, 150);
  AssertTrue('the rect over the series of a lower zlevel: ' + Px(p), (p.green > 230) and (p.red < 30));
  p := Pix(200, 125);
  AssertTrue('the series round it: ' + Px(p), (p.red > 230) and (p.green < 30));
  { a rect of opacity 0.5 drawn once, as when nothing is drawn apart }
  q := Pix(320, 80);
  Play(StringReplace(cHalfMixed, '"zlevel":-1,', '', []), 0);
  p := Pix(320, 80);
  AssertTrue('the half-clear rect drawn once: ' + Px(q) + ' against ' + Px(p),
    (Abs(p.red - q.red) <= 1) and (p.red < 250));
end;

{ THE AXES ON zlevels -1 AND 1, the graphic's rect of z -5 on 0 between
  them: over the x axis' split lines, under the y axis'; the axes both on
  -1: over them [was: under every level's] }
procedure TAdvChartTrailLayerTest.TestAGraphicUnderTheAxesBetweenAndOverTheirLevels;
const
  cOpt = '{"animation":false,"backgroundColor":"#ffffff","grid":{"left":40,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":10,"interval":5,"zlevel":-1,"axisLabel":{"show":false},'
    + '"splitLine":{"lineStyle":{"color":"#0000ff","width":6}}},'
    + '"yAxis":{"type":"value","min":0,"max":10,"interval":5,"zlevel":%d,"axisLabel":{"show":false},'
    + '"splitLine":{"lineStyle":{"color":"#ff0000","width":6}}},'
    + '"graphic":[{"type":"rect","z":-5,"shape":{"x":180,"y":130,"width":40,"height":40},"style":{"fill":"#00ff00"}}],'
    + '"series":[{"type":"scatter","data":[[1,1]]}]}';
var p: TBGRAPixel;
begin
  Play(Format(cOpt, [1]), 0);
  { the x axis' split line at x 5 (200 px), the y axis' at y 5 (150 px) }
  p := Pix(200, 140);
  AssertTrue('the rect over the x axis'' split line: ' + Px(p), (p.green > 230) and (p.blue < 30));
  p := Pix(190, 150);
  AssertTrue('the y axis'' split line over the rect: ' + Px(p), (p.red > 230) and (p.green < 30));
  Play(Format(cOpt, [-1]), 0);
  p := Pix(190, 150);
  AssertTrue('the rect over both: ' + Px(p), (p.green > 230) and (p.red < 30));
end;

{ THE LINES' TRAIL ON zlevel 1, the axes on 0 and 3: a graphic's rect of
  opacity 0.5 on zlevel 0, under the cut, is the static layer's -- drawn
  once, as with no animation }
procedure TAdvChartTrailLayerTest.TestAGraphicUnderTheCutIsDrawnOnce;
var p, q: TBGRAPixel; opt: string;
begin
  opt := StringReplace(Format(cBase, ['{"type":"rect","z":-5,"shape":{"x":200,"y":60,"width":40,"height":40},'
    + '"style":{"fill":"#00ff00","opacity":0.5}}', 2]), '"yAxis":{"type":"value",', '"yAxis":{"zlevel":3,"type":"value",', []);
  Play(opt, 30);
  AssertEquals('the lines on zlevel 1', 1, FChart.ZLevelOf('S0'));
  AssertEquals('the y axis on zlevel 3', 3, FChart.ZLevelOf('yAxis0'));
  q := Pix(220, 80);
  Play(StringReplace(opt, '"animation":true', '"animation":false', []), 0);
  p := Pix(220, 80);
  AssertTrue('the half-clear rect drawn once: ' + Px(q) + ' against ' + Px(p),
    (Abs(p.red - q.red) <= 1) and (p.red < 250));
end;

initialization
  RegisterTest(TAdvChartTrailLayerTest);
end.
