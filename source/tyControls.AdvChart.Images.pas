unit tyControls.AdvChart.Images;
{$mode objfpc}{$H+}
{ [F6a] THE PICTURES A CHART OPTION NAMES: a `data:` URL, and an image of
  a TImageList named `image://<list>/<index>`.

  Upstream takes an image as a URL and loads it; the port fetches nothing.
  Two kinds of source answer here:

    data:image/png;base64,...   decoded once and kept (the pattern image of
                                batch 105, moved here from AdvChart.Render);
    image://mapList/12          the 13th image of the image list that answers
                                to `mapList` -- the name registered with
                                TyChartRegisterImageList, else a
                                TCustomImageList component of that Name on the
                                chart's Owner (a form or a frame: the designer
                                finds it too). `mapList/12` without the prefix
                                is the same reference where an option takes a
                                bare URL (a pattern's `image`, a graphic
                                image's `style.image`).

  `image://data:...` is the data URL. Anything else -- an http URL, a file
  path -- is no picture: upstream's image that has not loaded yet.

  THE OWNER is the chart's, and a resolve does not take a chart: the chart
  opens a SCOPE around the work that resolves (its build, its paint, an
  export) with TyChartImageScopeEnter / Leave, and a lookup by name falls back
  to the scope's owner. One chart builds at a time on the main thread; scopes
  nest (a connected chart's export inside another's).

  THE RESOLUTION: an image list holds its images at one or more widths (its
  resolutions). The bitmap for a draw is the resolution that covers the
  device pixels the picture lands on -- the smallest whose width is at least
  that many, else the largest -- so a 16 px icon drawn at 150 % takes the 24
  px resolution where the list has one. The list is never asked to make a
  resolution it does not hold (Resolution[] would scale one and keep it).
  THE NATURAL SIZE -- what upstream reads off a loaded image, in CSS px -- is
  the list's Width x Height (its 96 PPI size).

  Bitmaps are cached per (list, index, resolution) and dropped when the list
  changes or is freed. }
interface

uses
  Classes, SysUtils, Math, base64, ImgList, GraphType, LCLType,
  BGRABitmap, BGRABitmapTypes;

{ the registry: AName (case-insensitive, as component names are) -> AList.
  Registering a name again replaces it; nil unregisters. The registry does
  not own the list and forgets it when the list is freed. }
procedure TyChartRegisterImageList(const AName: string; AList: TCustomImageList);
procedure TyChartUnregisterImageList(const AName: string);
{ the registered list of that name, or nil }
function TyChartRegisteredImageList(const AName: string): TCustomImageList;

{ the owner a name falls back to; Enter answers the scope it replaced, which
  Leave puts back }
function TyChartImageScopeEnter(AOwner: TComponent): TComponent;
procedure TyChartImageScopeLeave(APrevious: TComponent);
function TyChartImageScopeOwner: TComponent;

{ `image://name/index` or `name/index`: the name and the index; False for
  anything else (a data URL, an http URL, a name with characters a
  component name cannot have, a negative or missing index) }
function TyChartImageListRef(const ASource: string; out AName: string;
  out AIndex: Integer): Boolean;
{ the list a name resolves to: the registry, then the scope owner's
  component of that name; nil when neither has one }
function TyChartFindImageList(const AName: string): TCustomImageList;

{ THE PICTURE for a source, at the resolution for ADevicePx device pixels of
  width (0 or less: the list's own width), or nil (no such picture). The
  bitmap is the cache's: do not free it, do not keep it past the next
  resolve. ANatW, ANatH: its natural size in CSS px (0 when nil). }
function TyChartImage(const ASource: string; ADevicePx: Double;
  out ANatW, ANatH: Double): TBGRABitmap;
{ the natural size alone }
function TyChartImageSize(const ASource: string; out AW, AH: Double): Boolean;

{ [Batch 152] an image the chart made itself (a heatmap layer), kept under
  AKey -- a 'data:' key no decoder reads -- for TyChartImage to answer; the
  cache owns ABmp }
procedure TyChartImageRegisterBitmap(const AKey: string; ABmp: TBGRABitmap);

{ every cached image-list bitmap dropped (a test's fresh start) }
procedure TyChartImageFlush;

implementation

uses tyControls.AdvChart.Symbol;

type
  { the registry's and the cache's watch on the lists they hold: a list
    freed or changed drops what was taken from it }
  TTyImgWatch = class(TComponent)
  private
    FLinks: TList;
    procedure ListChanged(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Watch(AList: TCustomImageList);
    procedure Unwatch(AList: TCustomImageList);
  end;

var
  GRegistry: TStringList = nil;   { name -> list, case-insensitive }
  GListCache: TStringList = nil;  { 'ptr/index/width' -> TBGRABitmap, owned }
  GDataCache: TStringList = nil;  { data URL -> TBGRABitmap (or nil), owned }
  GWatch: TTyImgWatch = nil;
  GScope: TComponent = nil;

function Watcher: TTyImgWatch;
begin
  if GWatch = nil then GWatch := TTyImgWatch.Create(nil);
  Result := GWatch;
end;

function NewCache(AOwns: Boolean): TStringList;
begin
  Result := TStringList.Create;
  Result.OwnsObjects := AOwns;
  { by bytes, as upstream keys a name: the locale compare took
    U+00C5 and U+212B for one letter, and whatever came after [P2] }
  Result.UseLocale := False;
  Result.Sorted := True;
  Result.CaseSensitive := True;
  Result.Duplicates := dupIgnore;
end;

function ListKeyPrefix(AList: TCustomImageList): string;
begin
  Result := IntToHex(PtrUInt(AList), SizeOf(Pointer) * 2) + '/';
end;

{ every cached bitmap of AList }
procedure DropList(AList: TCustomImageList);
var
  i: Integer;
  pre: string;
begin
  if GListCache = nil then Exit;
  pre := ListKeyPrefix(AList);
  for i := GListCache.Count - 1 downto 0 do
    if Copy(GListCache[i], 1, Length(pre)) = pre then GListCache.Delete(i);
end;

{ ---- the watch ---- }

constructor TTyImgWatch.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLinks := TList.Create;
end;

destructor TTyImgWatch.Destroy;
var i: Integer;
begin
  { a link's destructor unregisters it from a list still alive }
  for i := 0 to FLinks.Count - 1 do TChangeLink(FLinks[i]).Free;
  FLinks.Free;
  inherited Destroy;
end;

procedure TTyImgWatch.ListChanged(Sender: TObject);
begin
  if Sender is TChangeLink then
    DropList(TChangeLink(Sender).Sender)
  else if Sender is TCustomImageList then
    DropList(TCustomImageList(Sender));
end;

procedure TTyImgWatch.Watch(AList: TCustomImageList);
var
  i: Integer;
  lk: TChangeLink;
begin
  if AList = nil then Exit;
  for i := 0 to FLinks.Count - 1 do
    if TChangeLink(FLinks[i]).Sender = AList then Exit;
  lk := TChangeLink.Create;
  lk.OnChange := @ListChanged;
  AList.RegisterChanges(lk);
  FLinks.Add(lk);
  AList.FreeNotification(Self);
end;

procedure TTyImgWatch.Unwatch(AList: TCustomImageList);
var i: Integer;
begin
  for i := FLinks.Count - 1 downto 0 do
    if TChangeLink(FLinks[i]).Sender = AList then
    begin
      TChangeLink(FLinks[i]).Free;
      FLinks.Delete(i);
    end;
  AList.RemoveFreeNotification(Self);
end;

procedure TTyImgWatch.Notification(AComponent: TComponent; Operation: TOperation);
var i: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  if AComponent = GScope then GScope := nil;
  if not (AComponent is TCustomImageList) then Exit;
  DropList(TCustomImageList(AComponent));
  { the links go before the list's own change list does (TComponent's
    notification runs inside the list's destructor, before it empties that
    list): a link's destructor unregisters itself }
  for i := FLinks.Count - 1 downto 0 do
    if (TChangeLink(FLinks[i]).Sender = AComponent)
      or (TChangeLink(FLinks[i]).Sender = nil) then
    begin
      TChangeLink(FLinks[i]).Free;
      FLinks.Delete(i);
    end;
  if GRegistry <> nil then
    for i := GRegistry.Count - 1 downto 0 do
      if GRegistry.Objects[i] = AComponent then GRegistry.Delete(i);
end;

{ ---- the registry ---- }

procedure TyChartRegisterImageList(const AName: string; AList: TCustomImageList);
var k: Integer;
begin
  if AList = nil then
  begin
    TyChartUnregisterImageList(AName);
    Exit;
  end;
  if Trim(AName) = '' then Exit;
  if GRegistry = nil then
  begin
    GRegistry := TStringList.Create;
    GRegistry.Sorted := True;
    GRegistry.CaseSensitive := False;
  end;
  if GRegistry.Find(AName, k) then GRegistry.Objects[k] := AList
  else GRegistry.AddObject(AName, AList);
  Watcher.Watch(AList);
end;

procedure TyChartUnregisterImageList(const AName: string);
var k: Integer;
begin
  if GRegistry = nil then Exit;
  if GRegistry.Find(AName, k) then GRegistry.Delete(k);
end;

function TyChartRegisteredImageList(const AName: string): TCustomImageList;
var k: Integer;
begin
  Result := nil;
  if GRegistry = nil then Exit;
  if GRegistry.Find(AName, k) then Result := TCustomImageList(GRegistry.Objects[k]);
end;

{ ---- the scope ---- }

function TyChartImageScopeEnter(AOwner: TComponent): TComponent;
begin
  Result := GScope;
  if (AOwner <> nil) and (AOwner <> GScope) then
    AOwner.FreeNotification(Watcher);
  GScope := AOwner;
end;

procedure TyChartImageScopeLeave(APrevious: TComponent);
begin
  GScope := APrevious;
end;

function TyChartImageScopeOwner: TComponent;
begin
  Result := GScope;
end;

{ ---- names ---- }

function TyChartImageListRef(const ASource: string; out AName: string;
  out AIndex: Integer): Boolean;
var
  s: string;
  slash, i, v: Integer;
begin
  Result := False;
  AName := '';
  AIndex := -1;
  s := ASource;
  if Copy(s, 1, 8) = 'image://' then Delete(s, 1, 8);
  slash := Pos('/', s);
  if (slash <= 1) or (slash = Length(s)) then Exit;
  { a component name: a letter or an underscore, then letters, digits and
    underscores }
  if not (s[1] in ['A'..'Z', 'a'..'z', '_']) then Exit;
  for i := 2 to slash - 1 do
    if not (s[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit;
  v := 0;
  for i := slash + 1 to Length(s) do
  begin
    if not (s[i] in ['0'..'9']) then Exit;
    if v > 100000000 then Exit;
    v := v * 10 + Ord(s[i]) - Ord('0');
  end;
  AName := Copy(s, 1, slash - 1);
  AIndex := v;
  Result := True;
end;

function TyChartFindImageList(const AName: string): TCustomImageList;
var c: TComponent;
begin
  Result := TyChartRegisteredImageList(AName);
  if Result <> nil then Exit;
  if GScope = nil then Exit;
  c := GScope.FindComponent(AName);
  if c is TCustomImageList then Result := TCustomImageList(c);
end;

{ ---- the pictures ---- }

{ the resolution covering ADevicePx: the smallest at least that wide, else
  the widest; the list's own width when ADevicePx says nothing }
function PickResolution(AList: TCustomImageList; ADevicePx: Double): TCustomImageListResolution;
var
  i: Integer;
  r, best, widest: TCustomImageListResolution;
  want: Double;
begin
  Result := nil;
  best := nil;
  widest := nil;
  if ADevicePx > 0 then want := ADevicePx else want := AList.Width;
  for i := 0 to AList.ResolutionCount - 1 do
  begin
    r := AList.ResolutionByIndex[i];
    if (r = nil) or (r.Width <= 0) or (r.Height <= 0) then Continue;
    if (widest = nil) or (r.Width > widest.Width) then widest := r;
    if (r.Width >= want - 1e-9) and ((best = nil) or (r.Width < best.Width)) then best := r;
  end;
  if best <> nil then Result := best else Result := widest;
end;

{ one image of one resolution as a BGRA bitmap: the raw image is 32-bit
  B, G, R, A top to bottom (FillDescription), read pixel by pixel so the
  platform's own BGRA order does not matter }
function ResolutionBitmap(ARes: TCustomImageListResolution; AIndex: Integer): TBGRABitmap;
var
  raw: TRawImage;
  q: PRGBAQuad;
  px: PBGRAPixel;
  x, y, w, h: Integer;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex >= ARes.Count) then Exit;
  ARes.GetRawImage(AIndex, raw);
  w := ARes.Width;
  h := ARes.Height;
  if (raw.Data = nil) or (w <= 0) or (h <= 0)
    or (raw.DataSize < PtrUInt(w * h * SizeOf(TRGBAQuad))) then Exit;
  Result := TBGRABitmap.Create(w, h);
  q := PRGBAQuad(raw.Data);
  for y := 0 to h - 1 do
  begin
    px := Result.ScanLine[y];
    for x := 0 to w - 1 do
    begin
      px^ := BGRA(q^.Red, q^.Green, q^.Blue, q^.Alpha);
      Inc(px);
      Inc(q);
    end;
  end;
  Result.InvalidateBitmap;
end;

function ListImage(AList: TCustomImageList; AIndex: Integer;
  ADevicePx: Double): TBGRABitmap;
var
  res: TCustomImageListResolution;
  key: string;
  k: Integer;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex >= AList.Count) then Exit;
  res := PickResolution(AList, ADevicePx);
  if res = nil then Exit;
  key := ListKeyPrefix(AList) + IntToStr(AIndex) + '/' + IntToStr(res.Width);
  if GListCache = nil then GListCache := NewCache(True);
  if GListCache.Find(key, k) then Exit(TBGRABitmap(GListCache.Objects[k]));
  Result := ResolutionBitmap(res, AIndex);
  if Result = nil then Exit;
  Watcher.Watch(AList);
  GListCache.AddObject(key, Result);
end;

function DataImage(const ASource: string): TBGRABitmap;
var
  k, comma: Integer;
  head, raw: string;
  ms: TStringStream;
  bmp: TBGRABitmap;
begin
  Result := nil;
  if Copy(ASource, 1, 5) <> 'data:' then Exit;
  if GDataCache = nil then GDataCache := NewCache(True);
  if GDataCache.Find(ASource, k) then
    Exit(TBGRABitmap(GDataCache.Objects[k]));
  comma := Pos(',', ASource);
  if comma <= 0 then Exit;
  head := LowerCase(Copy(ASource, 1, comma - 1));
  if (Length(head) < 7) or (Copy(head, Length(head) - 6, 7) <> ';base64') then Exit;
  bmp := nil;
  try
    raw := DecodeStringBase64(Copy(ASource, comma + 1, MaxInt));
    ms := TStringStream.Create(raw);
    try
      bmp := TBGRABitmap.Create(ms);
    finally
      ms.Free;
    end;
  except
    FreeAndNil(bmp);
  end;
  { kept even when it failed, so a broken image is not decoded every frame;
    a long-running chart cycling through patterns does not grow forever }
  if GDataCache.Count >= 64 then GDataCache.Clear;
  GDataCache.AddObject(ASource, bmp);
  Result := bmp;
end;

function TyChartImage(const ASource: string; ADevicePx: Double;
  out ANatW, ANatH: Double): TBGRABitmap;
var
  s, nm: string;
  idx: Integer;
  L: TCustomImageList;
begin
  Result := nil;
  ANatW := 0;
  ANatH := 0;
  s := ASource;
  if Copy(s, 1, 8) = 'image://' then Delete(s, 1, 8);
  if Copy(s, 1, 5) = 'data:' then
  begin
    Result := DataImage(s);
    if Result <> nil then
    begin
      ANatW := Result.Width;
      ANatH := Result.Height;
    end;
    Exit;
  end;
  if not TyChartImageListRef(s, nm, idx) then Exit;
  L := TyChartFindImageList(nm);
  if L = nil then Exit;
  Result := ListImage(L, idx, ADevicePx);
  if Result = nil then Exit;
  ANatW := L.Width;
  ANatH := L.Height;
end;

function TyChartImageSize(const ASource: string; out AW, AH: Double): Boolean;
var
  s, nm: string;
  idx: Integer;
  L: TCustomImageList;
  bmp: TBGRABitmap;
begin
  AW := 0;
  AH := 0;
  s := ASource;
  if Copy(s, 1, 8) = 'image://' then Delete(s, 1, 8);
  if Copy(s, 1, 5) = 'data:' then
  begin
    bmp := DataImage(s);
    Result := bmp <> nil;
    if Result then
    begin
      AW := bmp.Width;
      AH := bmp.Height;
    end;
    Exit;
  end;
  Result := False;
  if not TyChartImageListRef(s, nm, idx) then Exit;
  L := TyChartFindImageList(nm);
  if (L = nil) or (idx >= L.Count) or (L.Width <= 0) or (L.Height <= 0) then Exit;
  AW := L.Width;
  AH := L.Height;
  Result := True;
end;

procedure TyChartImageRegisterBitmap(const AKey: string; ABmp: TBGRABitmap);
var k: Integer;
begin
  if GDataCache = nil then GDataCache := NewCache(True);
  if GDataCache.Find(AKey, k) then
  begin
    ABmp.Free;
    Exit;
  end;
  if GDataCache.Count >= 64 then GDataCache.Clear;
  GDataCache.AddObject(AKey, ABmp);
end;

procedure TyChartImageFlush;
begin
  if GListCache <> nil then GListCache.Clear;
end;

initialization
  { the pure symbol unit's natural size (symbolKeepAspect) }
  TySymbolImageSize := @TyChartImageSize;

finalization
  TySymbolImageSize := nil;
  FreeAndNil(GWatch);
  FreeAndNil(GListCache);
  FreeAndNil(GDataCache);
  FreeAndNil(GRegistry);
end.
