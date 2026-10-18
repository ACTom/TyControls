unit tyControls.ImageDraw;
{$mode objfpc}{$H+}

{ The ONE two-path image draw. Every image-list property in this library is typed
  TCustomImageList now, so a list may be OURS (TTyVirtualImageList -- renders on demand at any
  pixel size) or anything else (a baked LCL list -- serves its registered resolutions). This is
  the single place that tells the two apart, written once because each of the traps below cost
  this library a shipped bug when it was written per call site:

  * the polarity trap. Ghosted and Enabled are negations, both Boolean, and an overload
    differing only in the sense of one has shipped the "every icon disabled" bug twice
    (ImageCollection.pas, TreeView, Menu). Encoded here as a TABLE indexed by Ghosted, so there
    is no `not` left to drop.

  * the EndPaint ordering rule. The baked branch is a GDI blit; TTyPainter.EndPaint alpha-blits
    the whole BGRA layer over the canvas afterwards and erases anything drawn to the DC before
    it. So TyDrawImage is a POST-EndPaint call. TyPutImage is the in-layer fast path for the Ty
    branch during the paint, and its Boolean result tells the caller when a baked icon is still
    owed to the post-EndPaint pass.

  * the measure trap. TCustomImageList's ResolutionForPPI/SizeForPPI CREATE a scaled resolution
    for any width they do not already have -- so a layout pass written the obvious way grows the
    host's image list, permanently, once per distinct pixel size a control ever computes
    (measured 4 -> 5 for one 20px request against [16,24,32,48]). The measure helper here only
    ever reads (WidthForPPI/HeightForPPI bottom out in FData.Find), and the DRAW helper routes
    through FindResolution -- it never hands a raw pixel size to ResolutionForPPI. }

interface

uses
  Classes, SysUtils, Types, Graphics, ImgList, GraphType, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.ImageCollection, tyControls.Painter;

const
  { LCL's EffectMap (imglist.inc) written BACKWARDS: it indexes by Enabled, this library carries
    Ghosted, and the two are negations. A table, not a `not`, is the whole point. }
  TyGhostEffect: array[Boolean] of TGraphicsDrawEffect = (gdeNormal, gdeDisabled);

{ True when AList is a BAKED list (a stock LCL TImageList, TLCLGlyphs -- anything not ours).
  nil is not baked: there is nothing to defer to a post-EndPaint pass. Ask once per paint. }
function TyImageIsBaked(AList: TCustomImageList): Boolean;

{ How many indices AList has, asked of the branch that will draw it: Names.Count for ours, the
  baked slot count otherwise. 0 for nil. Use this to bounds-check, never the raw .Count -- the
  two disagree during the window before a bake completes. }
function TyImageCount(AList: TCustomImageList): Integer;

{ Name <-> index resolution, the SINGLE place that judges the list's type for it. Names live only
  on ours: TTyVirtualImageList carries an ordered Names list and a name outlives a reorder, which
  is why a control keeps the NAME as its durable icon state and treats the index as a view. A
  foreign TCustomImageList has no names, so both helpers are inert against one -- IndexOfName
  returns -1 and NameOfIndex returns '', and a control that only ever set an index keeps working
  by index. Case-sensitive, matching TTyVirtualImageList.IndexOf. }
function TyImageIndexOfName(AList: TCustomImageList; const AName: string): Integer;
function TyImageNameOfIndex(AList: TCustomImageList; AIndex: Integer): string;

{ The size an icon will ACTUALLY occupy in device px if you ask for APreferredPx at APPI.
  (0,0) means reserve no slot: nil, or a baked list with no images. NON-MUTATING -- this is
  why it uses WidthForPPI/HeightForPPI and never SizeForPPI. Safe from a layout pass. }
function TyImageSizePx(AList: TCustomImageList; APreferredPx, APPI: Integer): TSize;

{ THE helper. Draw item AIndex of AList onto ACanvas, centred in the ASizePx square at (AX,AY).
  MUST be called AFTER TTyPainter.EndPaint (the baked branch is a GDI blit EndPaint would
  erase). AGhosted, never AEnabled. Guards nil canvas, nil list, bad index, empty slot, zero
  slot; never raises. }
procedure TyDrawImage(ACanvas: TCanvas; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx, APPI: Integer; AGhosted: Boolean);

{ The in-layer fast path, for the paint pass BEFORE EndPaint -- composited into ADest (pass
  P.Bitmap) with no GDI. RESULT IS NOT DECORATION: False means AList is baked and this icon is
  STILL UNDRAWN, so collect it and hand it to TyDrawImage after EndPaint. True means done,
  including the legitimate "nothing to draw" cases. }
function TyPutImage(ADest: TBGRABitmap; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx: Integer; AGhosted: Boolean): Boolean;

{ Draw item AIndex into ADest during the paint, BOTH branches in-layer -- for a control that
  has no post-EndPaint pass and would rather materialise a foreign list than grow a deferral
  array. See the body for the alpha caveat materialising carries (our own list never hits it).
  Centres in the ASizePx slot; guards everything; never raises. }
procedure TyBlitImage(ADest: TBGRABitmap; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx, APPI: Integer; AGhosted: Boolean);
{ TyBlitImage onto a painter's layer, with the position and size in LAYOUT pixels: they are
  mapped by the painter's device scale and the icon is taken at its raster PPI, so it stays
  sharp on a Retina layer (#83). At S = 1 it is TyBlitImage(P.Bitmap, ..., P.PPI, ...). }
procedure TyBlitImageScaled(P: TTyPainter; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx: Integer; AGhosted: Boolean);
{ ARes's item AIndex into ADst (LAYOUT pixels) on ACanvas, drawing with AEffect. At S = 1 it is
  ARes.Draw at ADst's corner. At a device scale ARes is the resolution the caller picked for the
  raster PPI; an item not S times ADst's size is stretched to it (an unscaled list hands back
  its one size), and the result goes into ADst on a canvas in layout units, 1:1 at S times the
  place on one in device units (#83). }
procedure TyDrawResolutionScaled(ACanvas: TCanvas; const ARes: TScaledImageListResolution;
  AIndex: Integer; const ADst: TRect; AEffect: TGraphicsDrawEffect);
{ FOR THE TESTS: how many LCL-list icons have been scaled for a device scale, and how many are
  kept now. }
function TyForeignScaledBuildCount: Integer;
function TyForeignScaledCacheCount: Integer;

{ A fresh, CALLER-OWNED BGRABitmap of item AIndex at ASizePx, for a control that owns its own
  compositing (scales the image to fit, tiles it, ...) rather than blitting at a slot. Our list
  renders the vector; a foreign list is materialised. nil when there is nothing to draw. The
  caller frees it. }
function TyRenderImage(AList: TCustomImageList; AIndex, ASizePx, APPI: Integer;
  AGhosted: Boolean): TBGRABitmap;
{ TyRenderImage for a painter's layer: ASizePx in LAYOUT pixels, the result in raster pixels --
  DeviceScale times the size the image has at S = 1 (#83). Our list renders the vector at that
  size; a foreign list hands its resolution for that size when it has one, else its S = 1
  bitmap stretched (the right size, if not the sharpest). The caller frees it. }
function TyRenderImageScaled(P: TTyPainter; AList: TCustomImageList; AIndex, ASizePx: Integer;
  AGhosted: Boolean): TBGRABitmap;

implementation


function TyImageIsBaked(AList: TCustomImageList): Boolean;
begin
  Result := (AList <> nil) and not (AList is TTyCustomVirtualImageList);
end;

function TyImageCount(AList: TCustomImageList): Integer;
begin
  if AList = nil then Exit(0);
  if AList is TTyCustomVirtualImageList then
    { The NAME index, which is what RenderIndex/CachedIndex address. After the reparent this is
      also the baked count, but Names.Count is the one that is right during a load, before the
      first bake, so it is the one asked for here. }
    Result := TTyCustomVirtualImageList(AList).Names.Count
  else
    Result := AList.Count;
end;

function TyImageIndexOfName(AList: TCustomImageList; const AName: string): Integer;
begin
  if (AList <> nil) and (AName <> '') and (AList is TTyCustomVirtualImageList) then
    Result := TTyCustomVirtualImageList(AList).IndexOf(AName)
  else
    Result := -1;
end;

function TyImageNameOfIndex(AList: TCustomImageList; AIndex: Integer): string;
begin
  if (AList <> nil) and (AIndex >= 0) and (AList is TTyCustomVirtualImageList) then
    Result := TTyCustomVirtualImageList(AList).NameOf(AIndex)
  else
    Result := '';
end;

{ Device-pixel slot -> the 96-PPI width LCL's read-only accessors speak, snapped to a REGISTERED
  width when one is within a pixel. Two reasons for the snap, both measured: an unsnapped width
  that GetResolution has never seen would MINT a resolution (mutation from a measure), and a
  slot derived from a row height drifts a pixel between themes and DPIs, so without the snap
  every distinct drifting value sprays a new resolution into a list this library does not own. }
function TyLclWidth96(AList: TCustomImageList; ASizePx, APPI: Integer): Integer;
var
  want, i, best, bestDelta, d: Integer;
  res: TCustomImageListResolution;
begin
  if ASizePx < 1 then Exit(0);       { 0 = "the list's own width" to LCL }
  if APPI <= 0 then APPI := 96;
  want := MulDiv(ASizePx, 96, APPI);
  { The list's own base width first -- the natural case, and FindResolution never mints. }
  if Abs(want - AList.Width) <= 1 then Exit(0);
  if AList.FindResolution(want, res) then Exit(want);
  { Otherwise snap to the nearest ALREADY-REGISTERED width, so nothing is created. Reading
    ResolutionByIndex is a plain array index (FData[i]); it does not create. }
  best := 0; bestDelta := MaxInt;
  for i := 0 to AList.ResolutionCount - 1 do
  begin
    d := Abs(AList.ResolutionByIndex[i].Width - want);
    if d < bestDelta then begin bestDelta := d; best := AList.ResolutionByIndex[i].Width; end;
  end;
  if best > 0 then Result := best else Result := 0;
end;

function TyImageSizePx(AList: TCustomImageList; APreferredPx, APPI: Integer): TSize;
var
  w96: Integer;
begin
  Result.cx := 0;
  Result.cy := 0;
  if (AList = nil) or (TyImageCount(AList) = 0) then Exit;
  if APPI <= 0 then APPI := 96;

  if AList is TTyCustomVirtualImageList then
  begin
    { On demand: we get exactly what we ask for, so the answer is the question. The only thing
      this branch imposes is the floor. }
    if APreferredPx < 1 then APreferredPx := 1;
    Result.cx := APreferredPx;
    Result.cy := APreferredPx;
    Exit;
  end;

  { Baked: the LIST answers. WidthForPPI/HeightForPPI only LOOK (FData.Find); they never create
    the way SizeForPPI/ResolutionForPPI do, so this is safe from a layout pass. w96 = 0 means
    "the list's own", which is what an unregistered near-natural slot snaps to. }
  w96 := TyLclWidth96(AList, APreferredPx, APPI);
  Result.cx := AList.WidthForPPI[w96, APPI];
  Result.cy := AList.HeightForPPI[w96, APPI];
end;

{ The Ty branch of both draw entry points. Returns the bitmap to blit; ADim is a bitmap the
  caller must free (nil when the borrowed one is used directly). CachedIndex hands back the
  collection's OWN cache entry -- borrowed -- so fading it in place would ghost that icon in
  every control that draws it; hence the duplicate when ghosting. }
function TyTakeVectorBitmap(AList: TTyCustomVirtualImageList; AIndex, ASizePx: Integer;
  AGhosted: Boolean; out ADim: TBGRABitmap): TBGRABitmap;
begin
  ADim := nil;
  Result := nil;
  if (AIndex < 0) or (AIndex >= AList.Names.Count) then Exit;
  Result := AList.CachedIndex(AIndex, ASizePx);   { borrowed; nil = nothing to draw }
  if (Result = nil) or (not AGhosted) then Exit;
  ADim := Result.Duplicate as TBGRABitmap;
  TyFadeBitmapAlpha(ADim, TyGhostedAlpha);
  Result := ADim;
end;

{ Item AIndex of a foreign list for a layer or canvas at AScale -- BORROWED, kept by the cache
  below: do not free it. }
function ForeignScaled(AList: TCustomImageList; AIndex, ASizePx, APPI, AScale: Integer;
  AGhosted: Boolean; out ALogicalW, ALogicalH: Integer): TBGRABitmap; forward;

{ ABmp, S times ADst's size, onto ACanvas at device scale AScale: into the layout rectangle ADst on
  a canvas in layout units -- the system puts each layout pixel back on S device pixels -- and
  1:1 at S times the place on a canvas in device units. Alpha-blended. }
procedure PutOnCanvas(ACanvas: TCanvas; ABmp: TBGRABitmap; const ADst: TRect;
  const AScale: TTyCanvasScale);
begin
  if AScale.DeviceUnits then
    ABmp.Draw(ACanvas, ADst.Left * AScale.Scale, ADst.Top * AScale.Scale, False)
  else
    ABmp.Draw(ACanvas, ADst, False);
end;

procedure TyDrawImage(ACanvas: TCanvas; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx, APPI: Integer; AGhosted: Boolean);
var
  bmp, dim: TBGRABitmap;
  res: TScaledImageListResolution;
  w96, lw, lh: Integer;
  sc: TTyCanvasScale;
begin
  { ASizePx < 1 EXITS rather than clamping: a zero slot means the layout gave the icon no room,
    and drawing nothing is the honest answer, not a 1px smudge. }
  if (ACanvas = nil) or (AList = nil) or (AIndex < 0) or (ASizePx < 1) then Exit;
  if APPI <= 0 then APPI := 96;

  { A canvas at a device scale (#83): the icon is taken at S times its size -- our list renders
    the vector there, a foreign list hands its resolution for it or its S = 1 bitmap stretched --
    and put into its layout place. }
  sc := TyCanvasDeviceScale(ACanvas);
  if sc.Scale > 1 then
  begin
    dim := nil;
    if AList is TTyCustomVirtualImageList then
    begin
      bmp := TyTakeVectorBitmap(TTyCustomVirtualImageList(AList), AIndex, ASizePx * sc.Scale,
        AGhosted, dim);
      lw := ASizePx;
      lh := ASizePx;
    end
    else
    begin
      bmp := ForeignScaled(AList, AIndex, ASizePx, APPI, sc.Scale, AGhosted, lw, lh);   // borrowed
    end;
    try
      if bmp <> nil then
        PutOnCanvas(ACanvas, bmp, Rect(AX + (ASizePx - lw) div 2, AY + (ASizePx - lh) div 2,
          AX + (ASizePx - lw) div 2 + lw, AY + (ASizePx - lh) div 2 + lh), sc);
    finally
      dim.Free;
    end;
    Exit;
  end;

  if AList is TTyCustomVirtualImageList then
  begin
    dim := nil;
    try
      bmp := TyTakeVectorBitmap(TTyCustomVirtualImageList(AList), AIndex, ASizePx, AGhosted, dim);
      if bmp = nil then Exit;
      { The square is already ASizePx (RenderMaster centres the aspect-preserved master in it),
        so no second centring. False = blend with alpha, do not paint opaque. }
      bmp.Draw(ACanvas, AX, AY, False);
    finally
      dim.Free;
    end;
    Exit;
  end;

  if AIndex >= AList.Count then Exit;
  { Canvas factor 1, deliberately: our controls composite at device pixels and EndPaint blits
    the layer 1:1, so there is no scaled backing store to compensate for -- and a factor <> 1
    turns Draw into a NON-virtual StretchDraw (the hi-DPI trap). w96 is already snapped to a
    registered width, so this ResolutionForPPI does not mint. }
  w96 := TyLclWidth96(AList, ASizePx, APPI);
  res := AList.ResolutionForPPI[w96, APPI, 1];
  if not res.Valid then Exit;
  { ASizePx is a SLOT here, not a size: a baked list has the widths it has. Centre what it
    gives; never stretch. }
  res.Draw(ACanvas,
           AX + (ASizePx - res.Width) div 2,
           AY + (ASizePx - res.Height) div 2,
           AIndex, TyGhostEffect[AGhosted]);
end;

function TyPutImage(ADest: TBGRABitmap; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx: Integer; AGhosted: Boolean): Boolean;
var
  bmp, dim: TBGRABitmap;
begin
  { True = nothing left for the post-EndPaint pass. The ONLY False is a baked list. ADest is
    nil after EndPaint (the layer bitmap is gone), so a call made too late reports True and
    draws nothing -- TyDrawImage is the one to reach for outside a paint pass. }
  Result := True;
  if (ADest = nil) or (AList = nil) or (AIndex < 0) or (ASizePx < 1) then Exit;
  if not (AList is TTyCustomVirtualImageList) then Exit(False);

  dim := nil;
  try
    bmp := TyTakeVectorBitmap(TTyCustomVirtualImageList(AList), AIndex, ASizePx, AGhosted, dim);
    if bmp = nil then Exit;
    ADest.PutImage(AX, AY, bmp, dmDrawWithTransparency);
  finally
    dim.Free;
  end;
end;

procedure TyBlitImage(ADest: TBGRABitmap; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx, APPI: Integer; AGhosted: Boolean);
var
  bmp, dim, wrap: TBGRABitmap;
  res: TScaledImageListResolution;
  tmp: TBitmap;
  w96: Integer;
begin
  { The in-layer draw for a control that has NO post-EndPaint pass. Both branches composite
    into ADest during the paint, so a simple control does not have to grow a deferral array
    just to accept a foreign list. The Ty branch is the free, exact one; a baked list is
    MATERIALISED into BGRA here.

    The cost of materialising, said once: LCL's GetBitmap goes through the widgetset, and on a
    widgetset that cannot hand back a 32-bit image it drops to a device format and loses the
    alpha edges (imglist.inc). Modern Win/GTK/Qt/Cocoa all do 32-bit; the degradation is on
    ancient targets only, and only for a FOREIGN list on one of these simple controls -- our
    own list never takes this branch. A control that draws MANY icons per paint (a tree) uses
    the GDI TyDrawImage path instead, which neither allocates per icon nor round-trips alpha. }
  if (ADest = nil) or (AList = nil) or (AIndex < 0) or (ASizePx < 1) then Exit;
  if APPI <= 0 then APPI := 96;

  if AList is TTyCustomVirtualImageList then
  begin
    dim := nil;
    try
      bmp := TyTakeVectorBitmap(TTyCustomVirtualImageList(AList), AIndex, ASizePx, AGhosted, dim);
      if bmp = nil then Exit;
      ADest.PutImage(AX, AY, bmp, dmDrawWithTransparency);
    finally
      dim.Free;
    end;
    Exit;
  end;

  if AIndex >= AList.Count then Exit;
  w96 := TyLclWidth96(AList, ASizePx, APPI);
  res := AList.ResolutionForPPI[w96, APPI, 1];
  if not res.Valid then Exit;
  tmp := TBitmap.Create;
  try
    tmp.PixelFormat := pf32bit;
    tmp.SetSize(res.Width, res.Height);
    res.GetBitmap(AIndex, tmp, TyGhostEffect[AGhosted]);
    wrap := TBGRABitmap.Create(tmp);
    try
      { Centre what the list gave in the ASizePx slot; never stretch. }
      ADest.PutImage(AX + (ASizePx - res.Width) div 2,
                     AY + (ASizePx - res.Height) div 2, wrap, dmDrawWithTransparency);
    finally
      wrap.Free;
    end;
  finally
    tmp.Free;
  end;
end;

function TyRenderImage(AList: TCustomImageList; AIndex, ASizePx, APPI: Integer;
  AGhosted: Boolean): TBGRABitmap;
var
  res: TScaledImageListResolution;
  tmp: TBitmap;
  w96: Integer;
begin
  Result := nil;
  if (AList = nil) or (AIndex < 0) or (ASizePx < 1) then Exit;
  if APPI <= 0 then APPI := 96;

  if AList is TTyCustomVirtualImageList then
  begin
    if AIndex >= TTyCustomVirtualImageList(AList).Names.Count then Exit;
    { RenderIndex returns a caller-owned square; that IS the contract here. Ghosting is applied
      to the owned copy -- no borrowed cache to protect, unlike the blit path. }
    Result := TTyCustomVirtualImageList(AList).RenderIndex(AIndex, ASizePx);
    if (Result <> nil) and AGhosted then TyFadeBitmapAlpha(Result, TyGhostedAlpha);
    Exit;
  end;

  if AIndex >= AList.Count then Exit;
  w96 := TyLclWidth96(AList, ASizePx, APPI);
  res := AList.ResolutionForPPI[w96, APPI, 1];
  if not res.Valid then Exit;
  tmp := TBitmap.Create;
  try
    tmp.PixelFormat := pf32bit;
    tmp.SetSize(res.Width, res.Height);
    res.GetBitmap(AIndex, tmp, TyGhostEffect[AGhosted]);
    Result := TBGRABitmap.Create(tmp);   { caller owns; see the alpha caveat on TyBlitImage }
  finally
    tmp.Free;
  end;
end;

{ ---- On a painter's layer at a device scale (#83) ------------------------------------------ }

{ Item AIndex of a FOREIGN list as a caller-owned bitmap for a layer at AScale: S times the size
  the list gives at S = 1 for ASizePx at APPI (returned as ALogicalW/H). The list's own
  resolution for the raster size when it has one at exactly that size (a list carrying 2x
  bitmaps, or a Scaled one); otherwise the S = 1 bitmap stretched -- an unscaled 16 px list must
  still show 16 points, not 16 device pixels. nil when there is nothing to draw. }
type
  TTyForeignIcon = class
    Bmp: TBGRABitmap;
    LW, LH: Integer;
    destructor Destroy; override;
  end;

const
  CForeignIconCap = 512;

var
  GForeignBuilds: Integer = 0;
  { The LCL-list icons scaled for a device scale, kept so a repaint does not scale them again
    (#83). Keyed by the picture itself -- a checksum of the list's pixels for the item -- not by
    the list: TCustomImageList.Replace notifies nobody, and a freed list's address goes to the
    next one. key -> TTyForeignIcon, owned. }
  GForeignIcons: TStringList = nil;

destructor TTyForeignIcon.Destroy;
begin
  Bmp.Free;
  inherited Destroy;
end;

{ FNV-1a over ARes's pixels for item AIndex, in hex, with the size: the picture, not its owner. }
function ForeignPictureKey(const ARes: TScaledImageListResolution; AIndex: Integer): string;
var
  raw: TRawImage;
  h: QWord;
  p: PByte;
  i: PtrUInt;
begin
  ARes.Resolution.GetRawImage(AIndex, raw);
  h := QWord($CBF29CE484222325);
  p := PByte(raw.Data);
  if p <> nil then
    for i := 0 to raw.DataSize - 1 do
    begin
      h := (h xor p[i]) * QWord($100000001B3);
    end;
  Result := IntToStr(ARes.Width) + 'x' + IntToStr(ARes.Height) + ':' + IntToHex(h, 16);
end;

function TyForeignScaledBuildCount: Integer;
begin
  Result := GForeignBuilds;
end;

function TyForeignScaledCacheCount: Integer;
begin
  if GForeignIcons = nil then Result := 0 else Result := GForeignIcons.Count;
end;

function BuildForeignScaled(AList: TCustomImageList; AIndex, ASizePx, APPI, AScale: Integer;
  AGhosted: Boolean; out ALogicalW, ALogicalH: Integer): TBGRABitmap;
var
  res1, res2: TScaledImageListResolution;
  tmp: TBitmap;
  one: TBGRABitmap;
begin
  Inc(GForeignBuilds);
  Result := nil;
  ALogicalW := 0;
  ALogicalH := 0;
  if (AList = nil) or (AIndex < 0) or (AIndex >= AList.Count) or (ASizePx < 1) then Exit;
  if APPI <= 0 then APPI := 96;
  res1 := AList.ResolutionForPPI[TyLclWidth96(AList, ASizePx, APPI), APPI, 1];
  if not res1.Valid then Exit;
  ALogicalW := res1.Width;
  ALogicalH := res1.Height;
  res2 := AList.ResolutionForPPI[TyLclWidth96(AList, ASizePx * AScale, APPI * AScale),
    APPI * AScale, 1];
  if not (res2.Valid and (res2.Width = res1.Width * AScale) and (res2.Height = res1.Height * AScale)) then
    res2 := res1;
  tmp := TBitmap.Create;
  try
    tmp.PixelFormat := pf32bit;
    tmp.SetSize(res2.Width, res2.Height);
    res2.GetBitmap(AIndex, tmp, TyGhostEffect[AGhosted]);
    one := TBGRABitmap.Create(tmp);
  finally
    tmp.Free;
  end;
  if (one.Width = res1.Width * AScale) and (one.Height = res1.Height * AScale) then
    Result := one
  else
  begin
    Result := one.Resample(res1.Width * AScale, res1.Height * AScale, rmSimpleStretch) as TBGRABitmap;
    one.Free;
  end;
end;

{ BuildForeignScaled, kept: the bitmap is BORROWED -- do not free it, do not change it. }
function ForeignScaled(AList: TCustomImageList; AIndex, ASizePx, APPI, AScale: Integer;
  AGhosted: Boolean; out ALogicalW, ALogicalH: Integer): TBGRABitmap;
var
  res1, res2: TScaledImageListResolution;
  key: string;
  i: Integer;
  icon: TTyForeignIcon;
begin
  Result := nil;
  ALogicalW := 0;
  ALogicalH := 0;
  if (AList = nil) or (AIndex < 0) or (AIndex >= AList.Count) or (ASizePx < 1) then Exit;
  if APPI <= 0 then APPI := 96;
  { The same two resolutions BuildForeignScaled picks: the key is what it would draw from. }
  res1 := AList.ResolutionForPPI[TyLclWidth96(AList, ASizePx, APPI), APPI, 1];
  if not res1.Valid then Exit;
  res2 := AList.ResolutionForPPI[TyLclWidth96(AList, ASizePx * AScale, APPI * AScale),
    APPI * AScale, 1];
  key := ForeignPictureKey(res1, AIndex);
  if res2.Valid and (res2.Width = res1.Width * AScale) and (res2.Height = res1.Height * AScale) then
    key := key + '|' + ForeignPictureKey(res2, AIndex);
  key := key + '|' + IntToStr(AScale) + '|' + IntToStr(Ord(AGhosted));
  if GForeignIcons = nil then
  begin
    GForeignIcons := TStringList.Create;
    GForeignIcons.Sorted := True;
    GForeignIcons.OwnsObjects := True;
  end;
  i := GForeignIcons.IndexOf(key);
  if i >= 0 then
    icon := TTyForeignIcon(GForeignIcons.Objects[i])
  else
  begin
    icon := TTyForeignIcon.Create;
    icon.Bmp := BuildForeignScaled(AList, AIndex, ASizePx, APPI, AScale, AGhosted, icon.LW, icon.LH);
    if icon.Bmp = nil then
    begin
      icon.Free;
      Exit;
    end;
    if GForeignIcons.Count >= CForeignIconCap then GForeignIcons.Clear;
    GForeignIcons.AddObject(key, icon);
  end;
  ALogicalW := icon.LW;
  ALogicalH := icon.LH;
  Result := icon.Bmp;
end;

procedure TyBlitImageScaled(P: TTyPainter; AList: TCustomImageList; AIndex: Integer;
  AX, AY, ASizePx: Integer; AGhosted: Boolean);
var
  bmp: TBGRABitmap;
  lw, lh: Integer;
begin
  if (P.DeviceScale <= 1) or (AList is TTyVirtualImageList) then
  begin
    { S = 1 is TyBlitImage exactly; our own list renders the vector at the raster size. }
    TyBlitImage(P.Bitmap, AList, AIndex, P.Dev(AX), P.Dev(AY), P.Dev(ASizePx), P.RasterPPI,
      AGhosted);
    Exit;
  end;
  if P.Bitmap = nil then Exit;
  bmp := ForeignScaled(AList, AIndex, ASizePx, P.PPI, P.DeviceScale, AGhosted, lw, lh);   // borrowed
  if bmp = nil then Exit;
  { Centred in the ASizePx slot by its S = 1 size, as TyBlitImage centres it -- never stretched to
    the slot. }
  P.Bitmap.PutImage(P.Dev(AX + (ASizePx - lw) div 2), P.Dev(AY + (ASizePx - lh) div 2), bmp,
    dmDrawWithTransparency);
end;

procedure TyDrawResolutionScaled(ACanvas: TCanvas; const ARes: TScaledImageListResolution;
  AIndex: Integer; const ADst: TRect; AEffect: TGraphicsDrawEffect);
var
  sc: TTyCanvasScale;
  tmp: TBitmap;
  one, big: TBGRABitmap;
  w, h: Integer;
begin
  if (ACanvas = nil) or not ARes.Valid then Exit;
  sc := TyCanvasDeviceScale(ACanvas);
  if sc.Scale <= 1 then
  begin
    ARes.Draw(ACanvas, ADst.Left, ADst.Top, AIndex, AEffect);
    Exit;
  end;
  w := (ADst.Right - ADst.Left) * sc.Scale;
  h := (ADst.Bottom - ADst.Top) * sc.Scale;
  if (w <= 0) or (h <= 0) then Exit;
  tmp := TBitmap.Create;
  try
    tmp.PixelFormat := pf32bit;
    tmp.SetSize(ARes.Width, ARes.Height);
    ARes.GetBitmap(AIndex, tmp, AEffect);
    one := TBGRABitmap.Create(tmp);
  finally
    tmp.Free;
  end;
  try
    if (one.Width <> w) or (one.Height <> h) then
    begin
      big := one.Resample(w, h, rmSimpleStretch) as TBGRABitmap;
      one.Free;
      one := big;
    end;
    PutOnCanvas(ACanvas, one, ADst, sc);
  finally
    one.Free;
  end;
end;

function TyRenderImageScaled(P: TTyPainter; AList: TCustomImageList; AIndex, ASizePx: Integer;
  AGhosted: Boolean): TBGRABitmap;
var
  lw, lh: Integer;
begin
  if (P.DeviceScale <= 1) or (AList is TTyVirtualImageList) then
    Exit(TyRenderImage(AList, AIndex, P.Dev(ASizePx), P.RasterPPI, AGhosted));
  Result := ForeignScaled(AList, AIndex, ASizePx, P.PPI, P.DeviceScale, AGhosted, lw, lh);
  if Result <> nil then Result := Result.Duplicate as TBGRABitmap;   // the caller's to free
end;

finalization
  FreeAndNil(GForeignIcons);

end.
