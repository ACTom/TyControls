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
    FBmp: TBGRABitmap;
    procedure Play(const AOption: string; AFrames: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAGraphicUnderTheTrailIsPaintedOnItsLayer;
    procedure TestAGraphicOnTheTrailsOwnLevelIsPaintedOnIt;
  end;

implementation

const
  cT0 = 1700000000000;
  { the lines of a trail along y 5 (150 px), from x 1 (72 px) to 9 (328 px),
    the symbol 256 px a second; no axis drawn }
  cBase = '{"animation":true,"animationDuration":0,"animationDurationUpdate":0,'
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
  FBmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
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
    FBmp.SaveToFile(GetEnvironmentVariable('TY_TL_SAVE') + 'trail-gfx.png');
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
    + '"style":{"fill":"#0000ff"}}', -1]), 30);
  AssertEquals('the lines on zlevel 0', 0, FChart.ZLevelOf('S0'));
  AssertEquals('the axes on zlevel 1', 1, FChart.ZLevelOf('xAxis0'));
  { the symbol passed x 130 some 250 ms ago: there the rect, painted after
    the fade, covers the trail }
  p := FBmp.GetPixel(130, 146);
  AssertTrue('the rect under the lines over the faded trail: ' + Px(p),
    (p.green > 230) and (p.red < 30) and (p.blue < 30));
  { the frame's line over it }
  p := FBmp.GetPixel(130, 150);
  AssertTrue('the line over the rect under it: ' + Px(p), (p.red > 200) and (p.green < 60));
  { the rect of z 0 over the line }
  p := FBmp.GetPixel(270, 150);
  AssertTrue('the rect after the lines over them: ' + Px(p), (p.blue > 230) and (p.red < 30));
  { off the rects, the trail fades as before }
  p := FBmp.GetPixel(180, 146);
  AssertTrue('the trail beside the rects: ' + Px(p), (p.red > 200) and (p.red - p.green > 40));
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
  p := FBmp.GetPixel(130, 150);
  AssertTrue('the line over the rect of a lower z: ' + Px(p), (p.red > 200) and (p.green < 60));
  p := FBmp.GetPixel(130, 146);
  AssertTrue('the rect over the faded trail: ' + Px(p),
    (p.green > 230) and (p.red < 30) and (p.blue < 30));
  p := FBmp.GetPixel(180, 146);
  AssertTrue('the trail beside the rect: ' + Px(p), (p.red > 200) and (p.red - p.green > 40));
end;

initialization
  RegisterTest(TAdvChartTrailLayerTest);
end.
