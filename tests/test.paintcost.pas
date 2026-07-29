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
  Classes, SysUtils, Graphics, fpcunit, testregistry, tyControls.Base, tyControls.Panel;
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

initialization
  RegisterTest(TPaintCacheTest);
end.
