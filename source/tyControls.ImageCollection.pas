unit tyControls.ImageCollection;
{$mode objfpc}{$H+}

{ TTyImageCollection + TTyVirtualImageList — the RASTER companion to the icon
  font (tyControls.IconFont / tyControls.GlyphImageList).

  TTyImageCollection is a DPI-aware NAMED raster image store. You Add named
  images from a TBGRABitmap or a TPicture; the collection keeps each as a master
  (highest-res source) bitmap. Consumers then ask for a name at a target PIXEL
  size and get a bitmap scaled to that size (aspect preserved, centered on a
  transparent square) — so one master serves every DPI without the caller
  juggling per-size raster sets. It is a plain non-visual TComponent; headless-safe,
  no timers. It complements the vector icon font: photos / true-colour PNGs live
  here, monochrome scalable glyphs live in the icon font.

  Scaled renders are CACHED per (name, sizePx), bounded by CacheCapacity with LRU
  eviction, and invalidated whenever Version changes (every mutation bumps it). Two
  accessors sit on that cache:
    * GetBitmap       — a caller-OWNED copy. Free it; mutating it (e.g. tinting via
                        TyTintBitmapAlpha) is safe and cannot reach the cache.
    * GetCachedBitmap — a BORROWED reference. Never free it, never mutate it, don't
                        hold it across another call. Allocation-free, so this is the
                        one paint code should use to blit an icon.
  Neither is thread-safe; both assume the LCL main thread, like the controls that
  consume them.

  TTyVirtualImageList is an ordered list that REFERENCES a TTyImageCollection
  and exposes a subset of its images (by name), rendering / drawing any item on
  demand at the consumer's target pixel size. It mirrors TTyGlyphImageList's
  shape exactly, but sourced from a raster collection instead of an icon font.
  A FreeNotification nils the reference automatically if the collection is freed
  first. Because both render on demand rather than caching a fixed-resolution
  set, they are plain TComponents with Draw methods, not TCustomImageList
  descendants — the ty-controls custom-drawn controls consume these, not LCL's
  native TImageList. }

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Types;

{ Recolor a BGRA icon bitmap's RGB to AColor while KEEPING its alpha (antialiased edges
  included), so an icon authored as an opaque alpha mask takes on any theme text color.
  In-place; a nil / empty bitmap is a no-op. }
procedure TyTintBitmapAlpha(ABmp: TBGRABitmap; AColor: TTyColor);

const
  { Default number of (name, sizePx) renders the collection keeps alive. Icons are
    small (16-48px is the norm), so this bounds a few hundred KB; a control that
    walks many sizes evicts rather than growing without limit. }
  TyImageCacheDefaultCapacity = 64;

type
  { Internal wrapper: owns one master TBGRABitmap, so a TStringList(OwnsObjects)
    frees every master when the collection is cleared / destroyed. }
  TTyImageEntry = class(TObject)
  private
    FMaster: TBGRABitmap;   // owned; the highest-res source for this name
  public
    constructor Create(AMaster: TBGRABitmap);   // takes ownership of AMaster
    destructor Destroy; override;
    property Master: TBGRABitmap read FMaster;
  end;

  { Internal wrapper: owns one scaled render plus its LRU stamp. }
  TTyImageCacheEntry = class(TObject)
  private
    FBmp: TBGRABitmap;   // owned; the master scaled to one (name, sizePx)
    FTick: Int64;        // last-used stamp; the smallest is evicted first
  public
    constructor Create(AOwnedBmp: TBGRABitmap; ATick: Int64);
    destructor Destroy; override;
  end;

  TTyImageCollection = class(TComponent)
  private
    FItems: TStringList;   // name -> TTyImageEntry (OwnsObjects)
    FVersion: Cardinal;    // bumped by every mutation; see Changed
    FCache: TStringList;   // 'name'#1'sizePx' -> TTyImageCacheEntry (OwnsObjects, Sorted)
    FCacheVersion: Cardinal;
    FCacheCapacity: Integer;
    FTick: Int64;          // monotonic LRU clock
    { Store ABmp (already owned by us) under AName, replacing any prior entry. }
    procedure StoreMaster(const AName: string; AOwnedBmp: TBGRABitmap);
    { Scale the master for AName into an ASizePx square. Caller owns the result.
      Assumes AName exists and ASizePx >= 1. }
    function RenderMaster(const AName: string; ASizePx: Integer): TBGRABitmap;
    { The composite cache key for (AName, ASizePx). }
    class function CacheKey(const AName: string; ASizePx: Integer): string; static;
    { Drop every cached render and re-sync to the current version. }
    procedure FlushCache;
    { Drop stale renders when a mutation has bumped Version since we last looked. }
    procedure SyncCache;
    { Evict least-recently-used entries until at most AMax remain. }
    procedure TrimCacheTo(AMax: Integer);
    procedure SetCacheCapacity(AValue: Integer);
  protected
    { Invalidates the render cache (lazily, via Version). Call after any change to
      the stored masters; descendants overriding this must call inherited. }
    procedure Changed; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Add (or replace) the image AName from ABmp. A COPY is taken (ABmp.Duplicate),
      so the caller keeps ownership of theirs. No-op when AName is '' or ABmp nil. }
    procedure AddBitmap(const AName: string; ABmp: TBGRABitmap);
    { Add (or replace) the image AName built from APicture's current graphic. The
      caller keeps ownership of APicture. No-op when AName is '' or the picture is
      empty / has no graphic. }
    procedure AddPicture(const AName: string; APicture: TPicture);
    { Drop all images (frees every master). }
    procedure Clear;

    { Number of stored images. }
    function Count: Integer;
    { The name at AIndex, or '' when AIndex is out of range. }
    function NameOf(AIndex: Integer): string;
    { Index of the (case-sensitive) name AName, or -1 when absent. }
    function IndexOf(const AName: string): Integer;
    { True when AName is stored. }
    function Contains(const AName: string): Boolean;

    { Return a NEW caller-owned bitmap: the master for AName scaled to fit an
      ASizePx square (aspect preserved, centered on a transparent background).
      Returns an empty transparent square when AName is missing (never nil, never
      raises). ASizePx <= 0 is clamped to a 1px square.

      The scale is served from the render cache, so repeated calls cost one
      allocation + copy rather than a fresh rmFineResample. The COPY is what makes
      it safe to mutate the result in place (see TyTintBitmapAlpha). When you only
      need to blit, prefer GetCachedBitmap and skip the copy entirely. }
    function GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;

    { The cached render of AName at ASizePx — a BORROWED reference owned by this
      collection. The caller must NOT Free it and must NOT modify its pixels; it
      stays valid until the next mutation (Version bump) or until evicted by a
      later GetCachedBitmap / CacheCapacity change, so blit it and drop it.

      Returns nil when there is nothing to draw (AName missing). Unlike GetBitmap
      this allocates nothing on a cache hit, which is the point: a repaint that
      blits N icons does no per-icon allocation and no per-icon resample.
      ASizePx <= 0 is clamped to a 1px square. }
    function GetCachedBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;

    { Number of cached (name, sizePx) renders currently held. Diagnostics / tests. }
    function CacheCount: Integer;
    { True when (AName, ASizePx) is currently cached. A pure query: unlike
      GetCachedBitmap it does NOT count as a use, so it cannot disturb the LRU
      order. Diagnostics / tests. }
    function IsCached(const AName: string; ASizePx: Integer): Boolean;

    { Bumped on every mutation (AddBitmap / AddPicture / Clear). Consumers that
      cache anything derived from this collection can compare it to detect staleness.
      Wraps at 2^32 mutations. }
    property Version: Cardinal read FVersion;
    { Upper bound on cached renders; least-recently-used entries are evicted past
      it. Lowering it evicts immediately. Values < 1 clamp to 1 (a cap of 0 would
      evict the very entry GetCachedBitmap is about to return). }
    property CacheCapacity: Integer read FCacheCapacity write SetCacheCapacity;
  end;

  TTyVirtualImageList = class(TComponent)
  private
    FCollection: TTyImageCollection;
    FNames: TStrings;          // ordered image NAMES to expose (a TStringList)
    FDefaultSize: Integer;
    procedure SetCollection(AValue: TTyImageCollection);
    procedure SetNames(AValue: TStrings);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Number of exposed items (= Names.Count). }
    function Count: Integer;
    { The image name at AIndex, or '' when AIndex is out of range. }
    function NameOf(AIndex: Integer): string;
    { Index of the (case-sensitive) name AName, or -1 when absent. }
    function IndexOf(const AName: string): Integer;
    { Render item AIndex from the Collection into an ASizePx square (aspect
      preserved, centered on transparent). Caller OWNS the returned bitmap. Never
      nil: an empty transparent square when Collection is unset, AIndex is out of
      range, or the name is missing. ASizePx <= 0 is clamped to a 1px square. }
    function RenderIndex(AIndex, ASizePx: Integer): TBGRABitmap;
    { The Collection's cached render of item AIndex at ASizePx — a BORROWED
      reference: do NOT Free it, do NOT modify its pixels, and do not hold it
      across another CachedIndex call. Returns nil when there is nothing to draw
      (no Collection, AIndex out of range, or the name is missing). This is the
      allocation-free path for paint code; use RenderIndex when you need to own or
      mutate the bitmap. ASizePx <= 0 is clamped to a 1px square. }
    function CachedIndex(AIndex, ASizePx: Integer): TBGRABitmap;
    { Render item AIndex and paint it onto ACanvas at (AX, AY). Guards every edge
      case (nil canvas/Collection, bad index, ASizePx <= 0) so it never raises. }
    procedure Draw(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer);
  published
    { The raster image source. Setting it registers a FreeNotification so the
      reference is nil'd automatically if the collection is freed first. }
    property Collection: TTyImageCollection read FCollection write SetCollection;
    { The ordered image NAMES, one per line — each a key into Collection. }
    property Names: TStrings read FNames write SetNames;
    { Default item edge in LOGICAL px, used by consumers that don't pass a size. }
    property DefaultSize: Integer read FDefaultSize write FDefaultSize default 16;
  end;

implementation

procedure TyTintBitmapAlpha(ABmp: TBGRABitmap; AColor: TTyColor);
var
  p: PBGRAPixel;
  i: Integer;
  r, g, b: Byte;
begin
  if (ABmp = nil) or (ABmp.NbPixels <= 0) then Exit;
  r := TyRedOf(AColor);
  g := TyGreenOf(AColor);
  b := TyBlueOf(AColor);
  p := ABmp.Data;
  for i := 0 to ABmp.NbPixels - 1 do
  begin
    // Keep the mask's alpha (incl. antialiased edges); replace only the RGB.
    p^.red := r; p^.green := g; p^.blue := b;
    Inc(p);
  end;
  ABmp.InvalidateBitmap;
end;

{ ---- TTyImageEntry ---- }

constructor TTyImageEntry.Create(AMaster: TBGRABitmap);
begin
  inherited Create;
  FMaster := AMaster;   // takes ownership
end;

destructor TTyImageEntry.Destroy;
begin
  FMaster.Free;
  inherited Destroy;
end;

{ ---- TTyImageCacheEntry ---- }

constructor TTyImageCacheEntry.Create(AOwnedBmp: TBGRABitmap; ATick: Int64);
begin
  inherited Create;
  FBmp := AOwnedBmp;   // takes ownership
  FTick := ATick;
end;

destructor TTyImageCacheEntry.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

{ ---- TTyImageCollection ---- }

constructor TTyImageCollection.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OwnsObjects := True;    // frees each TTyImageEntry (and its master)
  FItems.CaseSensitive := True;  // names are case-sensitive keys (per the contract)

  FCache := TStringList.Create;
  FCache.OwnsObjects := True;    // frees each TTyImageCacheEntry (and its render)
  FCache.CaseSensitive := True;  // must precede Sorted: it selects the compare
  FCache.Sorted := True;         // binary-search lookup on the composite key
  FCache.Duplicates := dupError;
  FCacheCapacity := TyImageCacheDefaultCapacity;
  FCacheVersion := FVersion;
end;

destructor TTyImageCollection.Destroy;
begin
  FCache.Free;   // OwnsObjects frees every cached render
  FItems.Free;   // OwnsObjects frees every entry -> every master bitmap
  inherited Destroy;
end;

class function TTyImageCollection.CacheKey(const AName: string; ASizePx: Integer): string;
begin
  // #1 cannot appear in a practical image name, so it separates the two parts
  // without a collision between e.g. ('a', 11) and ('a1', 1).
  Result := AName + #1 + IntToStr(ASizePx);
end;

procedure TTyImageCollection.Changed;
begin
  // Monotonic; SyncCache compares it lazily on the next read. Cheaper than an
  // observer list, and a mutation that forgets to flush still cannot serve a
  // stale render.
  Inc(FVersion);
end;

procedure TTyImageCollection.FlushCache;
begin
  FCache.Clear;   // OwnsObjects frees every render
  FCacheVersion := FVersion;
end;

procedure TTyImageCollection.SyncCache;
begin
  if FCacheVersion <> FVersion then
    FlushCache;
end;

procedure TTyImageCollection.TrimCacheTo(AMax: Integer);
var
  i, victim: Integer;
  oldest: Int64;
begin
  if AMax < 0 then AMax := 0;
  while FCache.Count > AMax do
  begin
    // Linear scan for the least-recently-used entry. The cache is small (capacity
    // entries) and this only runs on insert-when-full, so it stays cheaper than
    // maintaining an intrusive LRU order.
    victim := 0;
    oldest := TTyImageCacheEntry(FCache.Objects[0]).FTick;
    for i := 1 to FCache.Count - 1 do
      if TTyImageCacheEntry(FCache.Objects[i]).FTick < oldest then
      begin
        oldest := TTyImageCacheEntry(FCache.Objects[i]).FTick;
        victim := i;
      end;
    FCache.Delete(victim);   // OwnsObjects frees the entry + its render
  end;
end;

procedure TTyImageCollection.SetCacheCapacity(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FCacheCapacity = AValue then Exit;
  FCacheCapacity := AValue;
  TrimCacheTo(FCacheCapacity);   // shrink now rather than at the next read
end;

function TTyImageCollection.CacheCount: Integer;
begin
  Result := FCache.Count;
end;

function TTyImageCollection.IsCached(const AName: string; ASizePx: Integer): Boolean;
begin
  if ASizePx < 1 then ASizePx := 1;
  SyncCache;   // a mutation since the last read means nothing is really cached
  Result := FCache.IndexOf(CacheKey(AName, ASizePx)) >= 0;
end;

procedure TTyImageCollection.StoreMaster(const AName: string; AOwnedBmp: TBGRABitmap);
var
  idx: Integer;
begin
  // Replace an existing entry (freeing its old master) or append a new one.
  idx := FItems.IndexOf(AName);
  if idx >= 0 then
  begin
    FItems.Objects[idx].Free;   // free the old wrapper+master before overwrite
    FItems.Objects[idx] := TTyImageEntry.Create(AOwnedBmp);
  end
  else
    FItems.AddObject(AName, TTyImageEntry.Create(AOwnedBmp));
  Changed;   // any cached render of AName is now stale
end;

procedure TTyImageCollection.AddBitmap(const AName: string; ABmp: TBGRABitmap);
begin
  if (AName = '') or (ABmp = nil) then Exit;
  // Take a COPY so the caller keeps ownership of theirs.
  StoreMaster(AName, ABmp.Duplicate as TBGRABitmap);
end;

procedure TTyImageCollection.AddPicture(const AName: string; APicture: TPicture);
var
  master: TBGRABitmap;
  tmp: TBitmap;
begin
  if (AName = '') or (APicture = nil) or (APicture.Graphic = nil)
    or APicture.Graphic.Empty then Exit;
  // Rasterize the picture's graphic (any LCL graphic — PNG/BMP/JPG, alpha kept
  // for 32-bit sources) onto an owned TBitmap, then build the master from it via
  // the TBitmap constructor overload — no dependency on a TGraphic-typed Create.
  tmp := TBitmap.Create;
  try
    tmp.Assign(APicture.Graphic);   // convert/copy the graphic into a bitmap
    if (tmp.Width <= 0) or (tmp.Height <= 0) then Exit;
    master := TBGRABitmap.Create(tmp);
  finally
    tmp.Free;
  end;
  StoreMaster(AName, master);
end;

procedure TTyImageCollection.Clear;
begin
  FItems.Clear;   // OwnsObjects frees every entry+master
  Changed;
  FlushCache;     // "drop everything" should release the render memory now, not lazily
end;

function TTyImageCollection.Count: Integer;
begin
  Result := FItems.Count;
end;

function TTyImageCollection.NameOf(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
    Result := FItems[AIndex]
  else
    Result := '';
end;

function TTyImageCollection.IndexOf(const AName: string): Integer;
begin
  Result := FItems.IndexOf(AName);
end;

function TTyImageCollection.Contains(const AName: string): Boolean;
begin
  Result := FItems.IndexOf(AName) >= 0;
end;

function TTyImageCollection.RenderMaster(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  idx, dw, dh, ox, oy: Integer;
  master, scaled: TBGRABitmap;
  sc: Double;
begin
  // Always a non-nil transparent square of the requested size; we paint the scaled
  // master (if any) centered onto it, so consumers can blit unconditionally.
  Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent);
  idx := FItems.IndexOf(AName);
  if idx < 0 then Exit;   // missing name -> empty square
  master := TTyImageEntry(FItems.Objects[idx]).FMaster;
  if (master = nil) or (master.Width <= 0) or (master.Height <= 0) then Exit;

  // Fit the master into the square, preserving aspect (contain).
  sc := ASizePx / master.Width;
  if (ASizePx / master.Height) < sc then
    sc := ASizePx / master.Height;
  dw := Round(master.Width * sc);
  dh := Round(master.Height * sc);
  if dw < 1 then dw := 1;
  if dh < 1 then dh := 1;

  // Guard the always-created Result across the scale/composite so it is freed (not
  // leaked) if Resample or PutImage raises (e.g. under allocation failure).
  try
    scaled := master.Resample(dw, dh, rmFineResample) as TBGRABitmap;
    try
      ox := (ASizePx - dw) div 2;
      oy := (ASizePx - dh) div 2;
      Result.PutImage(ox, oy, scaled, dmDrawWithTransparency);
    finally
      scaled.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TTyImageCollection.GetCachedBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  key: string;
  idx: Integer;
  entry: TTyImageCacheEntry;
  rendered: TBGRABitmap;
begin
  Result := nil;
  if ASizePx < 1 then ASizePx := 1;
  SyncCache;                                // drop renders staled by a mutation
  if FItems.IndexOf(AName) < 0 then Exit;   // unknown name -> nothing to draw

  key := CacheKey(AName, ASizePx);
  idx := FCache.IndexOf(key);
  if idx >= 0 then
  begin
    entry := TTyImageCacheEntry(FCache.Objects[idx]);
    Inc(FTick);
    entry.FTick := FTick;   // touch: this is now the most recently used
    Exit(entry.FBmp);
  end;

  // Miss. Make room BEFORE inserting, so we can never evict the entry we are about
  // to hand back (capacity is clamped to >= 1, so this leaves at least one slot).
  TrimCacheTo(FCacheCapacity - 1);
  rendered := RenderMaster(AName, ASizePx);
  Inc(FTick);
  entry := TTyImageCacheEntry.Create(rendered, FTick);   // takes ownership
  try
    FCache.AddObject(key, entry);
  except
    entry.Free;   // frees the render too
    raise;
  end;
  Result := entry.FBmp;
end;

function TTyImageCollection.GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  cached: TBGRABitmap;
begin
  if ASizePx < 1 then ASizePx := 1;
  cached := GetCachedBitmap(AName, ASizePx);
  if cached <> nil then
    // Copy, never the cache entry itself: callers tint the result in place.
    Result := cached.Duplicate as TBGRABitmap
  else
    Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent);
end;

{ ---- TTyVirtualImageList ---- }

constructor TTyVirtualImageList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNames := TStringList.Create;
  FDefaultSize := 16;
end;

destructor TTyVirtualImageList.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure TTyVirtualImageList.SetCollection(AValue: TTyImageCollection);
begin
  if FCollection = AValue then Exit;
  if FCollection <> nil then
    FCollection.RemoveFreeNotification(Self);
  FCollection := AValue;
  if FCollection <> nil then
    FCollection.FreeNotification(Self);
end;

procedure TTyVirtualImageList.SetNames(AValue: TStrings);
begin
  FNames.Assign(AValue);
end;

procedure TTyVirtualImageList.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FCollection) then
    FCollection := nil;
end;

function TTyVirtualImageList.Count: Integer;
begin
  Result := FNames.Count;
end;

function TTyVirtualImageList.NameOf(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FNames.Count) then
    Result := FNames[AIndex]
  else
    Result := '';
end;

function TTyVirtualImageList.IndexOf(const AName: string): Integer;
begin
  Result := FNames.IndexOf(AName);
end;

function TTyVirtualImageList.RenderIndex(AIndex, ASizePx: Integer): TBGRABitmap;
var
  nm: string;
begin
  if ASizePx < 1 then ASizePx := 1;
  nm := NameOf(AIndex);
  // No collection, or index out of range -> an empty transparent square of the
  // requested size (never nil). Otherwise delegate the fit/scale to the collection
  // (which itself returns an empty square if the name is unknown).
  if (FCollection = nil) or (nm = '') then
    Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent)
  else
    Result := FCollection.GetBitmap(nm, ASizePx);
end;

function TTyVirtualImageList.CachedIndex(AIndex, ASizePx: Integer): TBGRABitmap;
var
  nm: string;
begin
  Result := nil;
  if ASizePx < 1 then ASizePx := 1;
  if FCollection = nil then Exit;
  nm := NameOf(AIndex);
  if nm = '' then Exit;
  // Borrowed: owned by the collection's render cache (nil when the name is missing).
  Result := FCollection.GetCachedBitmap(nm, ASizePx);
end;

procedure TTyVirtualImageList.Draw(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer);
var
  bmp: TBGRABitmap;
begin
  if ACanvas = nil then Exit;
  if ASizePx < 1 then ASizePx := 1;
  // Borrowed, so nothing to free. nil means "nothing to draw" (no Collection / bad
  // index / missing name) — where we previously blitted a fully transparent square,
  // which was a visual no-op anyway. The False keeps the icon's alpha.
  bmp := CachedIndex(AIndex, ASizePx);
  if bmp <> nil then
    bmp.Draw(ACanvas, AX, AY, False);
end;

end.
