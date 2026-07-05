unit tyControls.ImageCollection;
{$mode objfpc}{$H+}

{ TTyImageCollection + TTyVirtualImageList — the RASTER companion to the icon
  font (tyControls.IconFont / tyControls.GlyphImageList).

  TTyImageCollection is a DPI-aware NAMED raster image store. You Add named
  images from a TBGRABitmap or a TPicture; the collection keeps each as a master
  (highest-res source) bitmap. Consumers then ask for a name at a target PIXEL
  size and get a fresh bitmap scaled to that size (aspect preserved, centered on
  a transparent square) — so one master serves every DPI without the caller
  juggling per-size raster sets. It is a plain non-visual TComponent with a
  public render method returning a caller-owned TBGRABitmap; headless-safe, no
  timers. It complements the vector icon font: photos / true-colour PNGs live
  here, monochrome scalable glyphs live in the icon font.

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
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes;

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

  TTyImageCollection = class(TComponent)
  private
    FItems: TStringList;   // name -> TTyImageEntry (OwnsObjects)
    { Store ABmp (already owned by us) under AName, replacing any prior entry. }
    procedure StoreMaster(const AName: string; AOwnedBmp: TBGRABitmap);
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
      raises). ASizePx <= 0 is clamped to a 1px square. }
    function GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;
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

{ ---- TTyImageCollection ---- }

constructor TTyImageCollection.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OwnsObjects := True;   // frees each TTyImageEntry (and its master)
end;

destructor TTyImageCollection.Destroy;
begin
  FItems.Free;   // OwnsObjects frees every entry -> every master bitmap
  inherited Destroy;
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

function TTyImageCollection.GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  idx, dw, dh, ox, oy: Integer;
  master, scaled: TBGRABitmap;
  sc: Double;
begin
  if ASizePx < 1 then ASizePx := 1;
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

  scaled := master.Resample(dw, dh, rmFineResample) as TBGRABitmap;
  try
    ox := (ASizePx - dw) div 2;
    oy := (ASizePx - dh) div 2;
    Result.PutImage(ox, oy, scaled, dmDrawWithTransparency);
  finally
    scaled.Free;
  end;
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

procedure TTyVirtualImageList.Draw(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer);
var
  bmp: TBGRABitmap;
begin
  if ACanvas = nil then Exit;
  if ASizePx < 1 then ASizePx := 1;
  // RenderIndex always returns a non-nil bitmap (empty when unrenderable), so the
  // blit is safe even with no Collection / a bad index. The False keeps its alpha.
  bmp := RenderIndex(AIndex, ASizePx);
  try
    bmp.Draw(ACanvas, AX, AY, False);
  finally
    bmp.Free;
  end;
end;

end.
