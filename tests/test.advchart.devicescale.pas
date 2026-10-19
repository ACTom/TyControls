unit test.advchart.devicescale;
{$mode objfpc}{$H+}

{ #83, plan B Task 10: the AdvanceChart at the device scale.

  The chart draws through the painter's vector API (Canvas2D, preset to scale(S)) and that part
  needed nothing of its own; what it does on its own layers needed porting: the static cache,
  the dirty-rect window's work and dynamic layers, the progressive and trail layers, the label
  halo's mask, images and decal tiles made at a size, and the large-batch fast path, which
  writes pixels straight onto the layer. Each check draws a chart at S = 2 against S = 1
  (test.devicescale.support) or holds a path to the frame it must equal. }

interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, fpcunit, testregistry, base64,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Painter, tyControls.AdvChart.Paint, tyControls.AdvChart.Render,
  tyControls.AdvanceChart, test.devicescale.support;

type
  TDsChart = class(TTyAdvanceChart)
  public
    { the window's paint path: the static cache, or the dirty-rect window }
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    { elements a progressive run draws through its incremental layer }
    function LayeredCount: Integer;
    { the centre of series 0's datum AIndex, client px }
    function DatumCentre(AIndex: Integer): TPoint;
    function RepaintRectCount: Integer;
  end;

  TAdvChartDeviceScaleTest = class(TDeviceScaleCase)
  private
    FCtl: TTyStyleController;
    FOption: string;
    FDirtyRect: Boolean;
    function Controller: TTyStyleController;
    function BuildChart(AParent: TWinControl; APPI: Integer): TControl;
    function NewChart(AOwner: TWinControl; const AOption: string; AW, AH: Integer): TDsChart;
    function PatternOption: string;
    procedure DirtyRectAcrossScales(AFrom, ATo: Integer);
  protected
    procedure TearDown; override;
  published
    procedure TestChartAtTheDeviceScale;
    procedure TestDirtyRectAtTheDeviceScaleEqualsAFullPaint;
    procedure TestLargeBatchKeepsTheFastPathAtTheDeviceScale;
    procedure TestChartForgetsTheScale;
    { a progressive run's incremental layer, and a lines effect's trail: each a layer of
      its own the size of the painter's bitmap }
    procedure TestProgressiveLayerAtTheDeviceScale;
    procedure TestTrailLayerAtTheDeviceScale;
    { Review: a Retina window's canvas is in device px (DeviceUnits False): the dirty-rect
      window's layers are put into device-px rects there, the S-times pixels stretched. Every
      other check paints on a raster canvas, 1:1. The picture must be the S = 1 one. }
    procedure TestDirtyRectOnALayoutCanvas;
    { Review: the window moved between a Retina screen and a normal one. The dirty-rect
      window's layers were made at the old scale; at the new one they are made again, and
      every frame from then on -- the first, which also takes a hover, and a partial one --
      is the one painted afresh at the new scale. Both ways. }
    procedure TestDirtyRectLayersForgetTheScale;
    procedure TestDirtyRectLayersFollowTheScaleUp;
  end;

implementation

const
  cLine = '{"animation":false,"xAxis":{"type":"category","data":["A","B","C","D","E","F"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","smooth":true,"symbolSize":8,'
    + '"lineStyle":{"width":3},"data":[12,30,18,42,25,36]}]}';
  cBars = '{"animation":false,"legend":{},"xAxis":{"type":"category","data":["A","B","C","D"]},'
    + '"yAxis":{"type":"value","min":0,"max":100},"series":[{"type":"bar","name":"s",'
    + '"itemStyle":{"borderRadius":4},"label":{"show":true,"position":"top"},"data":[20,40,60,80]}]}';
  cPie = '{"animation":false,"series":[{"type":"pie","radius":["30%","70%"],'
    + '"label":{"show":true},"data":[{"value":40,"name":"one"},{"value":25,"name":"two"},'
    + '{"value":20,"name":"three"},{"value":15,"name":"four"}]}]}';
  cHalo = '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value","max":10},"series":[{"type":"bar","data":[5,7],'
    + '"itemStyle":{"color":"#3060c0"},"label":{"show":true,"position":"inside",'
    + '"fontSize":20,"color":"#ffffff","textBorderColor":"#c02020","textBorderWidth":4}}]}';
  cBarsPointer = '{"animation":false,"tooltip":{"trigger":"axis","axisPointer":{"type":"shadow"}},'
    + '"xAxis":{"type":"category","data":["A","B","C","D"]},"yAxis":{"type":"value","min":0,"max":100},'
    + '"series":[{"type":"bar","emphasis":{"itemStyle":{"color":"#c02060"}},"data":[20,40,60,80]}]}';
  cDecal = '{"animation":false,"xAxis":{"data":["a","b","c"]},"yAxis":{"max":10},'
    + '"series":[{"type":"bar","itemStyle":{"color":"#ff8000",'
    + '"decal":{"color":"#000000","dashArrayX":[4,4],"dashArrayY":[4,4]}},"data":[6,9,4]}]}';

procedure TDsChart.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TDsChart.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TDsChart.DatumCentre(AIndex: Integer): TPoint;
var
  k: Integer;
begin
  k := SeriesList.IndexOfDatum(0, AIndex);
  TAssert.AssertTrue('precondition: the datum is drawn', k >= 0);
  with SeriesList.Element(k).Shape.Bounds do
    Result := Point(Round((Left + Right) / 2), Round((Top + Bottom) / 2));
end;

function TDsChart.RepaintRectCount: Integer;
begin
  Result := Length(LastRepaintRects);
end;

function TDsChart.LayeredCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  if SeriesList = nil then Exit;
  for i := 0 to SeriesList.Count - 1 do
    if SeriesList.Element(i).ProgChunk > 0 then Inc(Result);
end;

{ A's S = 2 picture averaged down against B's S = 1 one, as CheckScale scores them }
procedure AssertSameAtBothScales(const AWhat: string; ARaster, ARef: TBGRABitmap);
var
  half: TBGRABitmap;
  ink, blocks: Integer;
begin
  half := TyHalve(ARaster);
  try
    ink := TyInkMismatch(half, ARef);
    blocks := TyBlockMismatch(half, ARef);
  finally
    half.Free;
  end;
  TAssert.AssertTrue(Format('%s draws at the device scale (score %d > %d: ink %d, blocks %d)',
    [AWhat, ink + blocks, CMaxMismatch, ink, blocks]), ink + blocks <= CMaxMismatch);
end;

{ The chart's window paint at the device scale AScale, as on a raster canvas: a bitmap AScale
  times its size, starting a colour no chart draws. }
function ShotAt(C: TDsChart; AScale: Integer): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(C.Width * AScale, C.Height * AScale);
    bmp.Canvas.Brush.Color := RGBToColor(1, 2, 3);
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    if AScale > 1 then TyForceDeviceScaleForTest(AScale, True, False);
    try
      C.Layered(bmp.Canvas, Rect(0, 0, C.Width, C.Height), 96);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function DiffCount(A, B: TBGRABitmap; out AFirst: string; ATolerance: Integer = 0): Integer;
var
  x, y, dr, dg, db: Integer;
  pa, pb: TBGRAPixel;
begin
  AFirst := '';
  if (A.Width <> B.Width) or (A.Height <> B.Height) then
  begin
    AFirst := Format('sizes %dx%d and %dx%d', [A.Width, A.Height, B.Width, B.Height]);
    Exit(A.Width * A.Height);
  end;
  Result := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      pa := A.GetPixel(x, y);
      pb := B.GetPixel(x, y);
      dr := pa.red;
      dr := Abs(dr - pb.red);
      dg := pa.green;
      dg := Abs(dg - pb.green);
      db := pa.blue;
      db := Abs(db - pb.blue);
      if (dr > ATolerance) or (dg > ATolerance) or (db > ATolerance) then
      begin
        if Result = 0 then
          AFirst := Format('first at (%d,%d): (%d,%d,%d) against (%d,%d,%d)',
            [x, y, pa.red, pa.green, pa.blue, pb.red, pb.green, pb.blue]);
        Inc(Result);
      end;
    end;
end;

{ N scattered points, the same every run }
function Scatter(N: Integer; const AExtra: string): string;
var
  i: Integer;
  s: string;
  seed: Cardinal;
begin
  s := '';
  seed := 7;
  for i := 0 to N - 1 do
  begin
    if i > 0 then s := s + ',';
    seed := seed * 1103515245 + 12345;
    s := s + '[' + IntToStr((seed shr 8) mod 1000);
    seed := seed * 1103515245 + 12345;
    s := s + ',' + IntToStr((seed shr 8) mod 1000) + ']';
  end;
  Result := '{"animation":false,"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","symbolSize":4' + AExtra + ',"data":[' + s + ']}]}';
end;

procedure TAdvChartDeviceScaleTest.TearDown;
begin
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartDeviceScaleTest.Controller: TTyStyleController;
begin
  if FCtl = nil then
  begin
    FCtl := TTyStyleController.Create(nil);
    FCtl.Mode := 'light';
    FCtl.ThemeName := 'default';
  end;
  Result := FCtl;
end;

function TAdvChartDeviceScaleTest.NewChart(AOwner: TWinControl; const AOption: string;
  AW, AH: Integer): TDsChart;
begin
  Result := TDsChart.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := Controller;
  Result.TooltipNow := 0;
  Result.SetBounds(0, 0, AW, AH);
  Result.Option := AOption;
end;

function TAdvChartDeviceScaleTest.BuildChart(AParent: TWinControl; APPI: Integer): TControl;
var
  c: TDsChart;
begin
  c := TDsChart.Create(AParent);
  c.Parent := AParent;
  c.Controller := Controller;
  c.Font.PixelsPerInch := APPI;
  c.UseDirtyRect := FDirtyRect;
  c.Option := FOption;
  Result := c;
end;

{ a bar filled with an 8 x 8 checker of 2-px squares, given as a data URL }
function TAdvChartDeviceScaleTest.PatternOption: string;
var
  b: TBGRABitmap;
  x, y: Integer;
  ms: TMemoryStream;
  raw: string;
begin
  b := TBGRABitmap.Create(8, 8);
  ms := TMemoryStream.Create;
  try
    for y := 0 to 7 do
      for x := 0 to 7 do
        if ((x div 2) + (y div 2)) mod 2 = 0 then
          b.SetPixel(x, y, BGRA(200, 30, 40, 255))
        else
          b.SetPixel(x, y, BGRA(30, 60, 200, 255));
    b.SaveToStreamAsPng(ms);
    SetLength(raw, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, raw[1], ms.Size);
  finally
    ms.Free;
    b.Free;
  end;
  Result := '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},"yAxis":{},'
    + '"series":[{"type":"bar","itemStyle":{"color":{"image":"data:image/png;base64,'
    + EncodeStringBase64(raw) + '"}},"data":[3,5]}]}';
end;

procedure TAdvChartDeviceScaleTest.TestChartAtTheDeviceScale;
begin
  FOption := cLine;
  CheckScale('TTyAdvanceChart-line', @BuildChart, 320, 200);
  FOption := cBars;
  CheckScale('TTyAdvanceChart-bars', @BuildChart, 320, 200);
  FOption := cPie;
  CheckScale('TTyAdvanceChart-pie', @BuildChart, 320, 200);
  FOption := cHalo;
  CheckScale('TTyAdvanceChart-halo', @BuildChart, 320, 200);
  FOption := cDecal;
  CheckScale('TTyAdvanceChart-decal', @BuildChart, 320, 200);
  FOption := PatternOption;
  CheckScale('TTyAdvanceChart-pattern', @BuildChart, 320, 200);
  { the window's paint in dirty-rect mode composites its own layers }
  FOption := cBars;
  FDirtyRect := True;
  CheckScale('TTyAdvanceChart-dirtyrect-window', @BuildChart, 320, 200);
  FDirtyRect := False;
end;

procedure TAdvChartDeviceScaleTest.TestDirtyRectAtTheDeviceScaleEqualsAFullPaint;
var
  f: TForm;
  a, b: TDsChart;
  hostA: TBitmap;
  pa, pb: TBGRABitmap;
  n: Integer;
  first: string;

  procedure Frame(const AWhat: string);
  begin
    FreeAndNil(pa);
    FreeAndNil(pb);
    { THE DIRTY PATH paints what changed onto a canvas that holds its last
      frame: A's canvas is kept from frame to frame, B's is new each time }
    TyForceDeviceScaleForTest(2, True, False);
    try
      a.Layered(hostA.Canvas, Rect(0, 0, a.Width, a.Height), 96);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    pa := TBGRABitmap.Create(hostA);
    pb := ShotAt(b, 2);
    n := DiffCount(pa, pb, first);
    AssertEquals(AWhat + ': S = 2, the dirty-rect frame is the full one (' + first + ')', 0, n);
  end;

begin
  f := TForm.CreateNew(nil);
  hostA := TBitmap.Create;
  pa := nil;
  pb := nil;
  try
    f.SetBounds(0, 0, 500, 400);
    { the bar's emphasis repaints the static layer in rects, the axis pointer's shadow
      draws on the dynamic one }
    a := NewChart(f, cBarsPointer, 320, 200);
    b := NewChart(f, cBarsPointer, 320, 200);
    a.UseDirtyRect := True;
    hostA.PixelFormat := pf32bit;
    hostA.SetSize(2 * a.Width, 2 * a.Height);
    hostA.Canvas.Brush.Color := RGBToColor(1, 2, 3);
    hostA.Canvas.FillRect(0, 0, hostA.Width, hostA.Height);
    Frame('the first frame');
    { over the third bar, then off it: a partial repaint each time }
    a.Hover(a.DatumCentre(2).X, a.DatumCentre(2).Y);
    b.Hover(b.DatumCentre(2).X, b.DatumCentre(2).Y);
    Frame('a hover');
    AssertFalse('precondition: the hover was a partial repaint', a.LastRepaintFull);
    AssertTrue('precondition: ...of something', a.RepaintRectCount > 0);
    a.Hover(a.DatumCentre(0).X, a.DatumCentre(0).Y);
    b.Hover(b.DatumCentre(0).X, b.DatumCentre(0).Y);
    Frame('the first bar');
    AssertFalse('precondition: so was the move', a.LastRepaintFull);
    AssertTrue('precondition: ...of something too', a.RepaintRectCount > 0);
  finally
    pb.Free;
    pa.Free;
    hostA.Free;
    f.Free;
  end;
end;

procedure TAdvChartDeviceScaleTest.TestLargeBatchKeepsTheFastPathAtTheDeviceScale;
var
  before: Integer;

begin
  FOption := Scatter(3000, ',"large":true,"largeThreshold":100');
  before := TyAdvChartLargeFastPathsForTest;
  CheckScale('TTyAdvanceChart-large', @BuildChart, 320, 200);
  { CheckScale paints it twice, once at each scale: both on the fast path }
  AssertTrue(Format('the large batch took the fast path at both scales (%d)',
    [TyAdvChartLargeFastPathsForTest - before]), TyAdvChartLargeFastPathsForTest - before >= 2);
  { A GRADIENT does not go through the flat layers: the tiles. Rects: circles traced into one
    path join up (BGRA's circle is an arc with no move to it -- a defect of its own, outside
    #83, reported), and the joins follow the tile edges, which differ with S }
  FOption := Scatter(400, ',"symbol":"rect","large":true,"largeThreshold":100,"itemStyle":{"color":'
    + '{"type":"linear","x":0,"y":0,"x2":1,"y2":0,"colorStops":[{"offset":0,"color":"#ff0000"},'
    + '{"offset":1,"color":"#0000ff"}]}}');
  before := TyAdvChartLargeFastPathsForTest;
  CheckScale('TTyAdvanceChart-large-tiles', @BuildChart, 320, 200);
  AssertTrue(Format('the gradient batch took the tiles at both scales (%d)',
    [TyAdvChartLargeFastPathsForTest - before]), TyAdvChartLargeFastPathsForTest - before >= 2);
end;

procedure TAdvChartDeviceScaleTest.TestChartForgetsTheScale;
var
  f: TForm;
  a, b: TDsChart;
  pa, pb: TBGRABitmap;
  n: Integer;
  first: string;
begin
  f := TForm.CreateNew(nil);
  pa := nil;
  pb := nil;
  try
    f.SetBounds(0, 0, 500, 400);
    a := NewChart(f, cHalo, 320, 200);
    b := NewChart(f, cHalo, 320, 200);
    ShotAt(a, 2).Free;
    pa := ShotAt(a, 1);
    pb := ShotAt(b, 1);
    n := DiffCount(pa, pb, first);
    AssertEquals('S = 1 after S = 2 is S = 1 from the start (' + first + ')', 0, n);
  finally
    pb.Free;
    pa.Free;
    f.Free;
  end;
end;

procedure TAdvChartDeviceScaleTest.TestProgressiveLayerAtTheDeviceScale;
var
  f: TForm;
  a, b: TDsChart;
  pa, pb: TBGRABitmap;
  k: Integer;
begin
  f := TForm.CreateNew(nil);
  pa := nil;
  pb := nil;
  try
    f.SetBounds(0, 0, 500, 400);
    a := NewChart(f, Scatter(3000, ',"progressive":400,"progressiveThreshold":1000'), 320, 200);
    b := NewChart(f, Scatter(3000, ',"progressive":400,"progressiveThreshold":1000'), 320, 200);
    a.ProgressiveStepCostMs := 0.4;
    b.ProgressiveStepCostMs := 0.4;
    for k := 1 to 3 do
    begin
      FreeAndNil(pa);
      FreeAndNil(pb);
      pa := ShotAt(a, 2);
      pb := ShotAt(b, 1);
      a.ProgressTick;
      b.ProgressTick;
    end;
    AssertTrue(Format('precondition: the run draws through its layer (%d elements)',
      [a.LayeredCount]), a.LayeredCount > 0);
    AssertSameAtBothScales('a progressive run', pa, pb);
  finally
    pb.Free;
    pa.Free;
    f.Free;
  end;
end;

procedure TAdvChartDeviceScaleTest.TestTrailLayerAtTheDeviceScale;
const
  T0 = 1700000000000.0;
  cTrail = '{"animation":false,"xAxis":{"type":"value","min":0,"max":100},"yAxis":{"type":"value","min":0,"max":100},'
    + '"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
    + '"lineStyle":{"color":"#0000ff","width":4,"opacity":0.5},'
    + '"effect":{"show":true,"trailLength":0.5,"period":4,"symbolSize":8},'
    + '"data":[{"coords":[[10,50],[90,50]]},{"coords":[[20,20],[80,80]]}]}]}';
var
  f: TForm;
  a, b: TDsChart;
  pa, pb: TBGRABitmap;
  k: Integer;

  function Make: TDsChart;
  begin
    Result := TDsChart.Create(f);
    Result.Parent := f;
    Result.Controller := Controller;
    Result.TooltipNow := 0;
    Result.SetBounds(0, 0, 320, 200);
    Result.AnimationMode := camAlways;
    Result.AnimNow := T0;
    Result.SetOption(cTrail, True);
  end;

begin
  f := TForm.CreateNew(nil);
  pa := nil;
  pb := nil;
  try
    f.SetBounds(0, 0, 500, 400);
    a := Make;
    b := Make;
    for k := 1 to 12 do
    begin
      a.AnimTick(T0 + k * 16);
      b.AnimTick(T0 + k * 16);
      FreeAndNil(pa);
      FreeAndNil(pb);
      pa := ShotAt(a, 2);
      pb := ShotAt(b, 1);
      if k = 1 then
      begin
        AssertTrue('precondition: a trail', a.LinesSolvedOf(0).TrailAlpha > 0);
        AssertTrue('precondition: only the effect''s loop runs', a.AnimContinuous);
      end;
    end;
    AssertSameAtBothScales('a lines trail', pa, pb);
  finally
    pb.Free;
    pa.Free;
    f.Free;
  end;
end;

procedure TAdvChartDeviceScaleTest.TestDirtyRectOnALayoutCanvas;
var
  f: TForm;
  a, b: TDsChart;
  hostA: TBitmap;
  pa, pb: TBGRABitmap;

  procedure Frame(const AWhat: string);
  var
    ink, blocks: Integer;
  begin
    FreeAndNil(pa);
    FreeAndNil(pb);
    TyForceDeviceScaleForTest(2, False, False);
    try
      a.Layered(hostA.Canvas, Rect(0, 0, a.Width, a.Height), 96);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    pa := TBGRABitmap.Create(hostA);
    pb := ShotAt(b, 1);
    ink := TyInkMismatch(pa, pb);
    blocks := TyBlockMismatch(pa, pb);
    AssertTrue(Format('%s: a Retina window''s canvas shows the S = 1 picture (score %d > %d: ink %d, blocks %d)',
      [AWhat, ink + blocks, CMaxMismatch, ink, blocks]), ink + blocks <= CMaxMismatch);
  end;

begin
  f := TForm.CreateNew(nil);
  hostA := TBitmap.Create;
  pa := nil;
  pb := nil;
  try
    f.SetBounds(0, 0, 500, 400);
    a := NewChart(f, cBarsPointer, 320, 200);
    b := NewChart(f, cBarsPointer, 320, 200);
    a.UseDirtyRect := True;
    hostA.PixelFormat := pf32bit;
    hostA.SetSize(a.Width, a.Height);
    hostA.Canvas.Brush.Color := RGBToColor(1, 2, 3);
    hostA.Canvas.FillRect(0, 0, hostA.Width, hostA.Height);
    Frame('the first frame');
    a.Hover(a.DatumCentre(2).X, a.DatumCentre(2).Y);
    b.Hover(b.DatumCentre(2).X, b.DatumCentre(2).Y);
    Frame('a hover');
    AssertFalse('precondition: the hover was a partial repaint', a.LastRepaintFull);
    a.Hover(a.DatumCentre(0).X, a.DatumCentre(0).Y);
    b.Hover(b.DatumCentre(0).X, b.DatumCentre(0).Y);
    Frame('the first bar');
  finally
    pb.Free;
    pa.Free;
    hostA.Free;
    f.Free;
  end;
end;

{ A (dirty-rect) and B (full paint) hovered alike: A painted at AFrom -- a full frame, then a
  hover -- and then at ATo on a canvas of its own that it keeps, the first frame there taking a
  hover of its own and the second another; each frame at ATo against B's full frame at ATo. }
procedure TAdvChartDeviceScaleTest.DirtyRectAcrossScales(AFrom, ATo: Integer);
var
  f: TForm;
  a, b: TDsChart;
  hostFrom, hostTo: TBitmap;
  pa, pb: TBGRABitmap;
  n: Integer;
  first: string;

  function NewHost(AScale: Integer): TBitmap;
  begin
    Result := TBitmap.Create;
    Result.PixelFormat := pf32bit;
    Result.SetSize(AScale * a.Width, AScale * a.Height);
    Result.Canvas.Brush.Color := RGBToColor(1, 2, 3);
    Result.Canvas.FillRect(0, 0, Result.Width, Result.Height);
  end;

  procedure PaintA(AHost: TBitmap; AScale: Integer);
  begin
    if AScale > 1 then TyForceDeviceScaleForTest(AScale, True, False);
    try
      a.Layered(AHost.Canvas, Rect(0, 0, a.Width, a.Height), 96);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
  end;

  procedure HoverBoth(AIndex: Integer);
  begin
    a.Hover(a.DatumCentre(AIndex).X, a.DatumCentre(AIndex).Y);
    b.Hover(b.DatumCentre(AIndex).X, b.DatumCentre(AIndex).Y);
  end;

  procedure FrameAtTo(const AWhat: string);
  begin
    FreeAndNil(pa);
    FreeAndNil(pb);
    PaintA(hostTo, ATo);
    pa := TBGRABitmap.Create(hostTo);
    pb := ShotAt(b, ATo);
    n := DiffCount(pa, pb, first);
    AssertEquals(Format('%s: S = %d after S = %d, the dirty-rect frame is the full one (%s)',
      [AWhat, ATo, AFrom, first]), 0, n);
  end;

begin
  f := TForm.CreateNew(nil);
  hostFrom := nil;
  hostTo := nil;
  pa := nil;
  pb := nil;
  try
    f.SetBounds(0, 0, 500, 400);
    a := NewChart(f, cBarsPointer, 320, 200);
    b := NewChart(f, cBarsPointer, 320, 200);
    a.UseDirtyRect := True;
    ShotAt(b, 1).Free;   { B laid out: its datum centres come from its last frame }
    { on the first screen: a full frame, then a hover -- the work, ground and dynamic layers
      all made at AFrom }
    hostFrom := NewHost(AFrom);
    PaintA(hostFrom, AFrom);
    HoverBoth(2);
    PaintA(hostFrom, AFrom);
    AssertFalse('precondition: the hover on the first screen was a partial repaint', a.LastRepaintFull);
    { on the other: the move and a hover in one frame, then a hover alone }
    hostTo := NewHost(ATo);
    HoverBoth(1);
    FrameAtTo('the first frame, with a hover');
    HoverBoth(0);
    FrameAtTo('a hover');
    AssertFalse('precondition: the hover on the other screen was a partial repaint', a.LastRepaintFull);
    AssertTrue('precondition: ...of something', a.RepaintRectCount > 0);
  finally
    pb.Free;
    pa.Free;
    hostTo.Free;
    hostFrom.Free;
    f.Free;
  end;
end;

procedure TAdvChartDeviceScaleTest.TestDirtyRectLayersForgetTheScale;
begin
  DirtyRectAcrossScales(2, 1);
end;

procedure TAdvChartDeviceScaleTest.TestDirtyRectLayersFollowTheScaleUp;
begin
  DirtyRectAcrossScales(1, 2);
end;

initialization
  RegisterTest(TAdvChartDeviceScaleTest);

end.
