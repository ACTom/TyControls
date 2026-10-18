unit test.paintcost;
{$mode objfpc}{$H+}
{ Guards TTyPaintCache, the rule that keeps a container from re-rendering itself for every
  frame a moving child asks of it.

  The numbers behind it, measured on Windows with a TTyPanel rendered to a bitmap: a full
  900x700 render costs 14.9 ms and scales at ~23 ns/px, while blitting the cached result costs
  3.8 ms for the whole page and, in the real path, only the damaged rectangle -- the DC is
  clipped to it. Three 60 fps instruments on one page therefore went from asking 282% of a core
  to asking for essentially nothing.

  These are timings, so they are recorded here rather than asserted; what IS asserted is the
  logic they depend on. }
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  Forms, tyControls.Base, tyControls.Panel, tyControls.Painter, test.devicescale.support;
type
  { Reaches the container's cache so the INVALIDATION WIRING can be asserted, not just the
    cache class. Without this a container that never dropped its cache -- a container frozen
    on its first frame -- passed every test in the suite; the mutation that removed the Drop
    call went unnoticed. }
  TPanelProbe = class(TTyPanel)
  public
    function CacheWouldRender(AW, AH: Integer): Boolean;
    procedure PrimeCache(AW, AH: Integer);
  end;

  TPaintCacheTest = class(TTestCase)
  published
    procedure FirstFrameRenders;
    procedure SecondFrameReusesWithoutRendering;
    procedure DropForcesARender;
    procedure ResizeForcesARender;
    procedure DegenerateSizeNeverRenders;
    procedure ContainerInvalidateDropsItsCache;
    { #83: at the device scale S the cache holds S times the pixels and its canvas is a raster
      canvas, so the painter that renders into it draws at S and lands 1:1. }
    procedure CacheAtScaleTwoIsRasterSized;
    { A window moved to a screen of another scale (Review Focus 1): the cache re-renders at the
      new size and its canvas stops answering for the old scale. }
    procedure ScaleChangeRerenders;
    procedure OldOverloadIsScaleOne;
    procedure DestroyUnregistersTheCanvas;
    { The blit: onto a canvas in device units 1:1; onto a canvas in layout units (a window on a
      Retina screen) stretched into the layout rectangle. }
    procedure BlitOntoDeviceUnitsIsOneToOne;
    procedure BlitOntoLayoutUnitsStretches;
    { The whole path: a panel drawn through its cache at S = 2 is the panel rendered straight onto
      a 2x raster canvas. }
    procedure CachedPanelMatchesDirectRender;
  end;
implementation

function TPanelProbe.CacheWouldRender(AW, AH: Integer): Boolean;
begin
  Result := (FPaintCache = nil) or FPaintCache.NeedsRender(AW, AH);
end;

procedure TPanelProbe.PrimeCache(AW, AH: Integer);
begin
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  FPaintCache.NeedsRender(AW, AH);   // pretend a frame was rendered into it
end;

procedure TPaintCacheTest.FirstFrameRenders;
var c: TTyPaintCache;
begin
  c := TTyPaintCache.Create;
  try
    AssertTrue('a cold cache must be rendered into', c.NeedsRender(100, 80));
    AssertTrue('and it hands back a canvas to render on', c.Canvas <> nil);
  finally c.Free; end;
end;

procedure TPaintCacheTest.SecondFrameReusesWithoutRendering;
var c: TTyPaintCache;
begin
  { This is the whole point: a repaint caused by a CHILD's damage never invalidates the
    container, so the second frame must cost a blit and nothing else. }
  c := TTyPaintCache.Create;
  try
    c.NeedsRender(100, 80);
    AssertFalse('an unchanged container re-renders nothing', c.NeedsRender(100, 80));
    AssertFalse('and stays that way', c.NeedsRender(100, 80));
  finally c.Free; end;
end;

procedure TPaintCacheTest.DropForcesARender;
var c: TTyPaintCache;
begin
  { Drop is what Invalidate calls -- the container's own look changed. }
  c := TTyPaintCache.Create;
  try
    c.NeedsRender(100, 80);
    c.Drop;
    AssertTrue('after Invalidate the cache is stale', c.NeedsRender(100, 80));
  finally c.Free; end;
end;

procedure TPaintCacheTest.ResizeForcesARender;
var c: TTyPaintCache;
begin
  { A resized surface holds nothing usable, and nothing calls Drop for it. }
  c := TTyPaintCache.Create;
  try
    c.NeedsRender(100, 80);
    AssertTrue('a different size cannot reuse the old pixels', c.NeedsRender(140, 80));
    AssertFalse('and the new size then caches too', c.NeedsRender(140, 80));
  finally c.Free; end;
end;

procedure TPaintCacheTest.DegenerateSizeNeverRenders;
var c: TTyPaintCache;
begin
  { A collapsed container must not allocate, and must not report work to do. }
  c := TTyPaintCache.Create;
  try
    AssertFalse('zero width', c.NeedsRender(0, 80));
    AssertFalse('zero height', c.NeedsRender(100, 0));
    AssertTrue('no surface was allocated', c.Canvas = nil);
  finally c.Free; end;
end;

procedure TPaintCacheTest.ContainerInvalidateDropsItsCache;
var
  p: TPanelProbe;
begin
  { The container half of the contract. A child's damage reaches Paint WITHOUT going through
    Invalidate, which is precisely why the cache may survive it -- so Invalidate is the only
    thing that may drop it, and it must. }
  p := TPanelProbe.Create(nil);
  try
    p.PrimeCache(120, 90);
    AssertFalse('primed: an unchanged container would reuse', p.CacheWouldRender(120, 90));
    p.Invalidate;
    AssertTrue('Invalidate must make the container re-render', p.CacheWouldRender(120, 90));
  finally
    p.Free;
  end;
end;

function Sc(AScale: Integer; ADeviceUnits: Boolean = False): TTyCanvasScale;
begin
  Result.Scale := AScale;
  Result.DeviceUnits := ADeviceUnits;
end;

procedure TPaintCacheTest.CacheAtScaleTwoIsRasterSized;
var
  c: TTyPaintCache;
begin
  c := TTyPaintCache.Create;
  try
    AssertTrue('a cold cache renders', c.NeedsRender(100, 80, Sc(2)));
    AssertEquals('raster width', 200, c.RasterWidth);
    AssertEquals('raster height', 160, c.RasterHeight);
    AssertEquals('the cache canvas is a raster canvas at 2', 2, TyRegisteredRasterScale(c.Canvas));
    AssertEquals('a painter on it draws at 2', 2, TyCanvasDeviceScale(c.Canvas).Scale);
    AssertTrue('in device units', TyCanvasDeviceScale(c.Canvas).DeviceUnits);
    AssertFalse('an unchanged container at the same scale reuses', c.NeedsRender(100, 80, Sc(2)));
  finally
    c.Free;
  end;
end;

procedure TPaintCacheTest.ScaleChangeRerenders;
var
  c: TTyPaintCache;
begin
  c := TTyPaintCache.Create;
  try
    c.NeedsRender(100, 80, Sc(2));
    AssertTrue('S 2 -> 1 re-renders', c.NeedsRender(100, 80, Sc(1)));
    AssertEquals('back to the layout width', 100, c.RasterWidth);
    AssertEquals('back to the layout height', 80, c.RasterHeight);
    AssertEquals('no longer a raster canvas', 0, TyRegisteredRasterScale(c.Canvas));
    AssertTrue('S 1 -> 2 re-renders', c.NeedsRender(100, 80, Sc(2)));
    AssertEquals('a raster canvas again', 2, TyRegisteredRasterScale(c.Canvas));
  finally
    c.Free;
  end;
end;

procedure TPaintCacheTest.OldOverloadIsScaleOne;
var
  c: TTyPaintCache;
begin
  c := TTyPaintCache.Create;
  try
    c.NeedsRender(100, 80, Sc(2));
    AssertTrue('the old call is S = 1: a change of scale', c.NeedsRender(100, 80));
    AssertEquals('layout width', 100, c.RasterWidth);
    AssertEquals('not a raster canvas', 0, TyRegisteredRasterScale(c.Canvas));
    AssertFalse('and S = 1 then caches as before', c.NeedsRender(100, 80, Sc(1)));
  finally
    c.Free;
  end;
end;

procedure TPaintCacheTest.DestroyUnregistersTheCanvas;
var
  c: TTyPaintCache;
  cv: TCanvas;
begin
  { The registry holds the canvas by address; a freed canvas left in it would make the next
    object allocated there answer for a scale it never had. }
  c := TTyPaintCache.Create;
  c.NeedsRender(40, 30, Sc(2));
  cv := c.Canvas;
  AssertEquals('registered while alive', 2, TyRegisteredRasterScale(cv));
  c.Free;
  AssertEquals('gone with the cache', 0, TyRegisteredRasterScale(cv));
end;

{ A 50 x 40 layout cache at S = 2, white, with a blue block in its last 10 x 10 device pixels. }
function MarkedCache: TTyPaintCache;
begin
  Result := TTyPaintCache.Create;
  Result.NeedsRender(50, 40, Sc(2));
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, 100, 80);
  Result.Canvas.Brush.Color := clBlue;
  Result.Canvas.FillRect(90, 70, 100, 80);
end;

function TargetPixel(ATarget: TBitmap; AX, AY: Integer): TColor;
var
  b: TBGRABitmap;
begin
  b := TBGRABitmap.Create(ATarget);
  try
    Result := BGRAToColor(b.GetPixel(AX, AY));
  finally
    b.Free;
  end;
end;

procedure TPaintCacheTest.BlitOntoDeviceUnitsIsOneToOne;
var
  c: TTyPaintCache;
  target: TBitmap;
begin
  c := MarkedCache;
  target := TBitmap.Create;
  try
    target.PixelFormat := pf24bit;
    target.SetSize(100, 80);
    target.Canvas.Brush.Color := clLime;
    target.Canvas.FillRect(0, 0, 100, 80);
    TyForceDeviceScaleForTest(2, True);
    try
      c.Blit(target.Canvas);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    AssertEquals('the blue block lands where it is in the cache', clBlue, TargetPixel(target, 95, 75));
    AssertEquals('and nowhere smaller', clWhite, TargetPixel(target, 45, 35));
  finally
    target.Free;
    c.Free;
  end;
end;

procedure TPaintCacheTest.BlitOntoLayoutUnitsStretches;
var
  c: TTyPaintCache;
  target: TBitmap;
begin
  c := MarkedCache;
  target := TBitmap.Create;
  try
    target.PixelFormat := pf24bit;
    target.SetSize(50, 40);
    target.Canvas.Brush.Color := clLime;
    target.Canvas.FillRect(0, 0, 50, 40);
    TyForceDeviceScaleForTest(2, False);
    try
      c.Blit(target.Canvas);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    AssertEquals('the cache fills the layout rectangle: blue in its last 5 x 5', clBlue,
      TargetPixel(target, 47, 37));
    AssertEquals('white elsewhere', clWhite, TargetPixel(target, 20, 20));
  finally
    target.Free;
    c.Free;
  end;
end;

procedure TPaintCacheTest.CachedPanelMatchesDirectRender;
const
  W = 120;
  H = 60;
var
  f: TForm;
  p1, p2: TPanelProbe;
  direct: TBitmap;
  a, b: TBGRABitmap;
  x, y, n: Integer;
  pa, pb: TBGRAPixel;
begin
  f := TForm.CreateNew(nil);
  direct := TBitmap.Create;
  a := nil;
  b := nil;
  try
    f.SetBounds(0, 0, 2 * W + 40, H + 40);
    p1 := TPanelProbe.Create(f);
    p1.Parent := f;
    p1.SetBounds(0, 0, W, H);
    p1.Caption := 'Cached';
    p2 := TPanelProbe.Create(f);
    p2.Parent := f;
    p2.SetBounds(W + 10, 0, W, H);
    p2.Caption := 'Cached';
    { The panel's own Paint -- the cache, then the blit -- at S = 2 onto a raster canvas. }
    a := TyPaintOwnSurface(p1, 2);
    { The same panel rendered straight onto a 2x raster canvas, no cache. }
    direct.PixelFormat := pf32bit;
    direct.SetSize(2 * W, 2 * H);
    direct.Canvas.Brush.Color := clWhite;
    direct.Canvas.FillRect(0, 0, 2 * W, 2 * H);
    TyForceDeviceScaleForTest(2, True);
    try
      p2.RenderTo(direct.Canvas, Rect(0, 0, W, H), 96);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    b := TBGRABitmap.Create(direct);
    AssertEquals('raster width', b.Width, a.Width);
    n := 0;
    for y := 0 to a.Height - 1 do
      for x := 0 to a.Width - 1 do
      begin
        pa := a.GetPixel(x, y);
        pb := b.GetPixel(x, y);
        if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then Inc(n);
      end;
    AssertEquals('through the cache = rendered straight at S = 2', 0, n);
  finally
    a.Free;
    b.Free;
    direct.Free;
    f.Free;
  end;
end;

initialization
  RegisterTest(TPaintCacheTest);
end.
