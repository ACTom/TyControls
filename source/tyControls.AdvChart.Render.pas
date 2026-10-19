unit tyControls.AdvChart.Render;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — drawing a paint list through TTyPainter.

  The second of the two bridge units that may see the LCL (the other is
  AdvChart.Measure). Everything it renders is decided elsewhere: the shape comes
  from the paint list, the order comes from the paint list, and the same shape
  record answers the pointer. This unit adds no geometry of its own -- that is
  the whole point of splitting it out, because geometry invented at render time
  is geometry the hit test cannot see. }
interface
uses
  SysUtils, Math, Types, Classes, Graphics, tyControls.FontUnits,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
  tyControls.Types,     // TTyColor: the render side speaks the library's colour type
  tyControls.AdvChart.Measure,  // the anchor-to-LCL-alignment converters
  BGRABitmap,
  tyControls.Painter;

{ Trace one shape into the painter's current path. Does NOT begin the path: a
  caller composing a ring from two contours needs to add both before filling. }
procedure TyTraceShape(P: TTyPainter; const AShape: TTyChartShape);

{ Draw one element: its shape, filled and/or stroked per its style. }
procedure TyRenderElement(P: TTyPainter; const AElement: TTyChartElement);

var
  { A LARGE BATCH IS PAINTED IN TILES this many device px square; 0 paints
    it as the one path [Batch 117]. }
  TyLargeTilePx: Integer = 64;

{ FOR THE TESTS: how many times a large batch took one of its fast paths --
  the layer (PaintLargeOnLayer) or the tiles (PaintLargeInTiles) -- since the
  start (#83: they must still be taken at a device scale). }
function TyAdvChartLargeFastPathsForTest: Integer;

{ THE BOX A LOCAL GRADIENT ON THIS ELEMENT NORMALISES AGAINST, device px at
  APPI: the builder's own when it set one, else the shape's bounds grown by
  the stroke -- upstream's getBoundingRect. [Batch 105] }
function TyElementGradientBox(const AElement: TTyChartElement;
  APPI: Integer): TTyXYWH;

{ A pattern's image: a `data:` URL with base64 content, decoded once and
  kept; nil for anything else or anything that does not decode. Owned by the
  cache. [Batch 105] [F6a] AdvChart.Images answers: an image list's
  `image://name/index` (or `name/index`) too, at its own width. }
function TyPatternImage(const ASource: string): TBGRABitmap;
{ [Batch 152] an image the chart made itself (a heatmap layer), kept under
  AKey -- a 'data:' key no decoder reads -- for TyPatternImage to answer;
  the cache owns ABmp }
procedure TyPatternRegisterImage(const AKey: string; ABmp: TBGRABitmap);

{ A DECAL'S TILE at AScale device px per CSS px [Batch 131]: the bitmap
  createOrUpdatePatternFromDecal draws on its canvas -- the tile's size
  times the scale (truncated, as a canvas' width is), cleared, its
  background when it has one, every symbol filled in the decal's colour.
  nil when the tile has no pixel. Owned by the cache. }
function TyDecalTileImage(const ADecal: TTyChartDecal; AScale: Double): TBGRABitmap;

type
  { ONE SYMBOL OF A DECAL'S TILE as createSymbol makes it [F4a]: Name the
    symbol type with 'empty' stripped ('path' for a 'path://', 'image' for
    an 'image://'), Box the box brushSymbol hands it (device px of the
    tile), Shape the path filled and / or stroked -- a 'path://' fitted to
    the box by makePath ('center' keeping its aspect, else 'cover'), BBox
    its bounding rect -- and an image's source. The pens: an empty symbol is
    filled white (tokens.color.neutral00) and stroked in the colour 2 px
    wide (symbolPathSetColor), a 'line' stroked in the colour, anything
    else filled in it. Draws False: a symbol of no area (a dash of 0),
    which upstream hands the painter all the same and nothing comes of. }
  TTyDecalMark = record
    Name: string;
    Empty, IsImage, KeepAspect, Draws: Boolean;
    Box: TTyRectF;
    Shape: TTyChartShape;
    BBox: TTyXYWH;
    HasFill: Boolean;
    Fill: TTyChartColor;
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    LineWidth: Double;
    ImageSrc: string;
  end;
  TTyDecalMarkArray = array of TTyDecalMark;

{ the symbols TyDecalTileImage draws, in brush order, at AScale }
function TyDecalTileMarks(const ADecal: TTyChartDecal; AScale: Double): TTyDecalMarkArray;

{ the pattern matrix a decal's tile is repeated through, DEVICE px: the
  pattern's rotation and its 1 / dpr scale, carried to the device }
procedure TyDecalMatrix(const ADecal: TTyChartDecal; AScale: Double;
  out AM: TTyDoubleArray);

{ Draw the whole list in paint order. }
procedure TyRenderPaintList(P: TTyPainter; AList: TTyPaintList);

{ [F4c] zrender's normalizeLineDash: a textBorderType as written ('dashed'
  [4w, 2w], 'dotted' [w], a number [n], a JSON array its numbers) against
  the stroke's width; False -- a solid line -- for 'solid', '' or a width
  that is not above nought. }
function TyNormalizeLineDash(const AType: string; AWidth: Double;
  out APattern: TTyDoubleArray): Boolean;

{ ZRENDER'S TEXT BLOCK, piece by piece in its paint order: each rect (its
  border first where it has both, as zrender doubles and underlays it) and
  each text, hung at (AX, AY), turned counter-clockwise by ARotationRad and
  scaled by AScale device px per piece px. AAlpha is the element's. A text
  whose fill came from the host's default and has none takes AInk where
  AHasInk -- a free text's skin ink. [Batch 86] }
procedure TyRenderRtPieces(P: TTyPainter; const APieces: TTyRtPieceArray;
  AX, AY, ARotationRad, AScale, AAlpha: Double; AHasInk: Boolean;
  AInk: TTyColor);

{ [R2-P] FOR THE TESTS. A label's halo traces its glyphs' outline off a mask
  once and keeps it (see HaloOutlineKept): how many masks were traced since
  the start; how many outlines are kept now; the keeping switched off (and
  everything kept dropped) or on again. }
function TyAdvChartHaloTracesForTest: Integer;
function TyAdvChartHaloOutlinesKeptForTest: Integer;
procedure TyAdvChartHaloCacheForTest(AOn: Boolean);
{ [R2-P] FOR THE TESTS: the outline traced off AMask (alpha at half
  coverage, AScale mask px per device px), as the halo strokes it with the
  mask's origin at (0, 0) -- per contour its point count, then its points
  x, y in turn. }
function TyTraceMaskOutlineForTest(AMask: TBGRABitmap; AScale: Integer): TTyDoubleArray;

implementation

uses base64, BGRABitmapTypes, Generics.Collections, tyControls.AdvChart.Large,
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Decal, tyControls.AdvChart.Images,
  tyControls.AdvChart.ZrPath, tyControls.AdvChart.GfxEl;

var
  GDecalCache: TStringList = nil;
  GLargeFastPaths: Integer = 0;

function TyAdvChartLargeFastPathsForTest: Integer;
begin
  Result := GLargeFastPaths;
end;

{ [F6a] A PICTURE DRAWN INTO ITS CORNERS: ACorners the image's top-left,
  top-right, bottom-right and bottom-left in device px (a shape's
  polygon); the image through the affine map of its own rect onto them,
  inside the polygon. The resolution is the one for the top edge's length.
  Nothing when the source has no picture -- upstream's image not loaded. }
procedure PaintImageInto(P: TTyPainter; const ASource: string;
  const ACorners: TTyPointFArray);
var
  img: TBGRABitmap;
  nw, nh, ew: Double;
  pm: array[0..5] of Double;
  i: Integer;
begin
  if Length(ACorners) < 4 then Exit;
  { a picture of no area (a symbol scaled to nothing) draws nothing: its
    map has no inverse }
  if Abs((ACorners[1].X - ACorners[0].X) * (ACorners[3].Y - ACorners[0].Y)
    - (ACorners[1].Y - ACorners[0].Y) * (ACorners[3].X - ACorners[0].X)) < 1e-9 then Exit;
  if IsNan(ACorners[0].X + ACorners[0].Y + ACorners[1].X + ACorners[1].Y
    + ACorners[3].X + ACorners[3].Y) then Exit;
  { the resolution for the raster's pixels: the device scale times the edge (#83);
    the map below is from whatever size comes back }
  ew := Sqrt(Sqr(ACorners[1].X - ACorners[0].X) + Sqr(ACorners[1].Y - ACorners[0].Y))
    * P.DeviceScale;
  img := TyChartImage(ASource, ew, nw, nh);
  if (img = nil) or (img.Width <= 0) or (img.Height <= 0) then Exit;
  pm[0] := (ACorners[1].X - ACorners[0].X) / img.Width;
  pm[1] := (ACorners[1].Y - ACorners[0].Y) / img.Width;
  pm[2] := (ACorners[3].X - ACorners[0].X) / img.Height;
  pm[3] := (ACorners[3].Y - ACorners[0].Y) / img.Height;
  pm[4] := ACorners[0].X;
  pm[5] := ACorners[0].Y;
  P.BeginPath;
  P.MoveTo(ACorners[0].X, ACorners[0].Y);
  for i := 1 to 3 do P.LineTo(ACorners[i].X, ACorners[i].Y);
  P.ClosePath;
  P.FillPathPattern(img, 'no-repeat', pm, tfrNonZero);
end;

function TyDecalTileMarks(const ADecal: TTyChartDecal; AScale: Double): TTyDecalMarkArray;
var
  tile: TTyDecalTile;
  i, n: Integer;
  spec: TTySymbolSpec;
  m: TTyDecalMark;
  empty: Boolean;
  path: string;
  zp: TTyZrPath;
  box: TTyXYWH;
  cmds: TTyPathCmdArray;
  pts: TTyPointFArray;
  ident: TTyMat2D;
begin
  Result := nil;
  if not ADecal.Present then Exit;
  tile := TyDecalTile(ADecal);
  SetLength(Result, Length(tile.Symbols));
  n := 0;
  ident[0] := 1; ident[1] := 0; ident[2] := 0; ident[3] := 1; ident[4] := 0; ident[5] := 0;
  for i := 0 to High(tile.Symbols) do
  begin
    { createSymbol at (x, y, w, h) times dpr, in the decal's colour }
    m := Default(TTyDecalMark);
    m.Box := TyRectF(tile.Symbols[i].X * AScale, tile.Symbols[i].Y * AScale,
      (tile.Symbols[i].X + tile.Symbols[i].W) * AScale,
      (tile.Symbols[i].Y + tile.Symbols[i].H) * AScale);
    m.KeepAspect := ADecal.KeepAspect;
    box := TyXYWH(tile.Symbols[i].X * AScale, tile.Symbols[i].Y * AScale,
      tile.Symbols[i].W * AScale, tile.Symbols[i].H * AScale);
    if Copy(tile.Symbols[i].Kind, 1, 8) = 'image://' then
    begin
      { makeImage: a ZRImage of the box; its onload re-centres it where the
        aspect is kept -- drawn so here }
      m.Name := 'image';
      m.IsImage := True;
      m.ImageSrc := Copy(tile.Symbols[i].Kind, 9, MaxInt);
      m.BBox := box;
      m.Draws := True;
      Result[n] := m;
      Inc(n);
      Continue;
    end;
    spec := TySymbolDefault('');
    spec.Kind := TySymbolKindOf(tile.Symbols[i].Kind, empty, path);
    spec.Empty := empty;
    spec.PathData := path;
    spec.KeepAspect := ADecal.KeepAspect;
    spec.RotateDeg := 0;
    spec.OffsetX := 0;
    spec.OffsetY := 0;
    m.Empty := empty;
    if spec.Kind = tsyPath then
    begin
      { makePath(..., rect, keepAspect ? 'center' : 'cover') }
      m.Name := 'path';
      if ADecal.KeepAspect then zp := TyZrMakePathCenter(path, box)
      else zp := TyZrMakePathCover(path, box);
      m.BBox := TyZrBBox(zp);
      TyGfxPathCmds(zp, ident, cmds, pts);
      m.Shape := TyShapePolygon(pts);
      m.Shape.Cmds := cmds;
      m.Draws := Length(cmds) > 0;
    end
    else
    begin
      m.Name := tile.Symbols[i].Kind;
      if empty then m.Name := LowerCase(Copy(m.Name, 6, 1)) + Copy(m.Name, 7, MaxInt);
      m.Shape := TyBuildSymbolInBox(spec, m.Box);
      m.Draws := not ((m.Shape.Kind = cskRect) and not TyRectFIsValid(m.Shape.Bounds));
    end;
    { symbolPathSetColor }
    if empty then
    begin
      m.HasFill := True;
      m.Fill := TTyChartColor($FFFFFFFF);
      m.HasStroke := True;
      m.Stroke := ADecal.Color;
      m.LineWidth := 2;
    end
    else if spec.Kind = tsyLine then
    begin
      m.HasStroke := True;
      m.Stroke := ADecal.Color;
      m.LineWidth := 1;
    end
    else
    begin
      m.HasFill := True;
      m.Fill := ADecal.Color;
    end;
    Result[n] := m;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyDecalTileImage(const ADecal: TTyChartDecal; AScale: Double): TBGRABitmap;
var
  key: string;
  k, i, w, h: Integer;
  bmp, img: TBGRABitmap;
  P: TTyPainter;
  marks: TTyDecalMarkArray;
  fw, fh, s, iw, ih: Double;
  tile: TTyDecalTile;
  r: TTyRectF;
begin
  Result := nil;
  if not ADecal.Present then Exit;
  if GDecalCache = nil then
  begin
    GDecalCache := TStringList.Create;
    GDecalCache.OwnsObjects := True;
    { by bytes, as upstream keys a name: the locale compare took
      U+00C5 and U+212B for one letter, and whatever came after [P2] }
    GDecalCache.UseLocale := False;
    GDecalCache.Sorted := True;
    GDecalCache.CaseSensitive := True;
  end;
  key := TyDecalCacheKey(ADecal, AScale);
  if GDecalCache.Find(key, k) then Exit(TBGRABitmap(GDecalCache.Objects[k]));
  tile := TyDecalTile(ADecal);
  { canvas.width = pSize.width * dpr: an unsigned long, the fraction cut }
  fw := tile.W * AScale;
  fh := tile.H * AScale;
  w := 0;
  h := 0;
  if (not IsNan(fw)) and (fw >= 1) and (fw < 32768) then w := Trunc(fw);
  if (not IsNan(fh)) and (fh >= 1) and (fh < 32768) then h := Trunc(fh);
  bmp := nil;
  if (w > 0) and (h > 0) then
  begin
    bmp := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
    if ADecal.HasBackground then
      bmp.FillRect(0, 0, w, h, TyColorToBGRA(TTyColor(ADecal.Background)), dmSet);
    marks := TyDecalTileMarks(ADecal, AScale);
    P := TTyPainter.Create;
    try
      { no canvas: EndPaint leaves the bitmap where it is }
      P.BeginPaintOn(nil, Rect(0, 0, w, h), 96, bmp);
      for i := 0 to High(marks) do
      begin
        if marks[i].IsImage then
        begin
          { an image symbol: its source stretched over the box, or fitted
            into it keeping its aspect }
          img := TyPatternImage(marks[i].ImageSrc);
          if (img = nil) or (img.Width <= 0) or (img.Height <= 0) then Continue;
          r := marks[i].Box;
          if marks[i].KeepAspect then
          begin
            iw := r.Right - r.Left;
            ih := r.Bottom - r.Top;
            s := Min(iw / img.Width, ih / img.Height);
            r := TyRectF((r.Left + r.Right - img.Width * s) / 2,
              (r.Top + r.Bottom - img.Height * s) / 2,
              (r.Left + r.Right + img.Width * s) / 2,
              (r.Top + r.Bottom + img.Height * s) / 2);
          end;
          if (r.Right - r.Left >= 1) and (r.Bottom - r.Top >= 1) then
            bmp.StretchPutImage(Rect(Round(r.Left), Round(r.Top), Round(r.Right),
              Round(r.Bottom)), img, dmDrawWithTransparency);
          Continue;
        end;
        if not marks[i].Draws then Continue;
        P.BeginPath;
        TyTraceShape(P, marks[i].Shape);
        if marks[i].HasFill then P.FillPath(TTyColor(marks[i].Fill));
        if marks[i].HasStroke then
          P.StrokePath(TTyColor(marks[i].Stroke), marks[i].LineWidth);
      end;
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  if GDecalCache.Count >= 64 then GDecalCache.Clear;
  GDecalCache.AddObject(key, bmp);
  Result := bmp;
end;

procedure TyDecalMatrix(const ADecal: TTyChartDecal; AScale: Double;
  out AM: TTyDoubleArray);
var
  pat: TTyChartPattern;
  i: Integer;
begin
  { pattern.rotation = decal.rotation; scaleX = scaleY = 1 / dpr; the
    canvas then carries it to the device by dpr }
  pat := Default(TTyChartPattern);
  pat.Present := True;
  pat.Rotation := ADecal.Rotation;
  if AScale > 0 then
  begin
    pat.ScaleX := 1 / AScale;
    pat.ScaleY := 1 / AScale;
  end
  else
  begin
    pat.ScaleX := 1;
    pat.ScaleY := 1;
  end;
  TyPatternMatrix(pat, AM);
  for i := 0 to 5 do AM[i] := AM[i] * AScale;
end;

function TyPatternImage(const ASource: string): TBGRABitmap;
var nw, nh: Double;
begin
  { [F6a] the pictures moved to AdvChart.Images, with the image lists }
  Result := TyChartImage(ASource, 0, nw, nh);
end;

procedure TyPatternRegisterImage(const AKey: string; ABmp: TBGRABitmap);
begin
  TyChartImageRegisterBitmap(AKey, ABmp);
end;

function TyElementGradientBox(const AElement: TTyChartElement;
  APPI: Integer): TTyXYWH;
begin
  if AElement.Style.GradBoxSet then Exit(AElement.Style.GradBox);
  Result := TyRectToXYWH(TyShapeBounds(AElement.Shape));
  { Path.getBoundingRect grows by the stroke when there is one: a fill-less
    path by max(width, 5) }
  if (AElement.Style.StrokeWidthLogical > 0)
    and (((AElement.Style.StrokeColor shr 24) > 0)
      or (AElement.Style.StrokeGradient.Kind <> cgkNone)) then
  begin
    if APPI <= 0 then APPI := 96;
    Result := TyGrowByStroke(Result, AElement.Style.HasFill,
      AElement.Style.StrokeWidthLogical * APPI / 96);
  end;
end;

{ util/shape/sausage.ts on the shape's ordered sweep (clockwise from
  StartRad to EndRad): the ring with a half disc on either end [Batch 113] }
procedure TraceSausage(P: TTyPainter; const AShape: TTyChartShape);
var r0, r, dr, rc, sa, ea: Double;
begin
  r0 := Max(Double(0), AShape.R0);
  r := Max(Double(0), AShape.R1);
  dr := (r - r0) * 0.5;
  rc := r0 + dr;
  sa := AShape.StartRad;
  ea := AShape.EndRad;
  if ea - sa < 2 * Pi then
  begin
    P.MoveTo(Cos(sa) * r0 + AShape.CX, Sin(sa) * r0 + AShape.CY);
    P.ArcTo(Cos(sa) * rc + AShape.CX, Sin(sa) * rc + AShape.CY, dr, -Pi + sa, sa, False);
  end
  else
  begin
    sa := ea - 2 * Pi;
    P.MoveTo(Cos(sa) * r + AShape.CX, Sin(sa) * r + AShape.CY);
  end;
  P.ArcTo(AShape.CX, AShape.CY, r, sa, ea, False);
  P.ArcTo(Cos(ea) * rc + AShape.CX, Sin(ea) * rc + AShape.CY, dr, ea - 2 * Pi, ea - Pi, False);
  if r0 <> 0 then P.ArcTo(AShape.CX, AShape.CY, r0, ea, sa, True);
  P.ClosePath;
end;

{ A LARGE-MODE BATCH, row by row [Batch 117]: a bar's rect (LargePath.
  buildPath -- a not-a-number rect adds nothing, as the canvas ignores
  one), a scatter's symbol in its box (the series' size, never the row's
  own; a point outside the soft clip skipped) or, under 4 px, a plain
  square (afterBrush's fillRect), a candle sign's line from low to high. }
function LargeSymbolSpec(const AGeom: TTyLargeGeom): TTySymbolSpec;
begin
  Result := TySymbolDefault('scatter');
  Result.Kind := TTySymbolKind(AGeom.SymKind);
  Result.Empty := False;
  Result.WidthPx := AGeom.SymW;
  Result.HeightPx := AGeom.SymH;
end;

function Bad(AV: Double): Boolean; inline;
begin
  Result := IsNan(AV) or IsInfinite(AV);
end;

{ A LINES ROW [Batch 121]: its numbers in the segs, and how many points --
  two for a line, the count for a polyline }
function LinesRow(const AGeom: TTyLargeGeom; ARow: Integer;
  out AFirst, ACount: Integer): Boolean;
begin
  Result := False;
  AFirst := 0;
  ACount := 0;
  if (ARow < 0) or (ARow > High(AGeom.Idx)) then Exit;
  AFirst := AGeom.Idx[ARow];
  if AGeom.LinesPoly then
  begin
    if (AFirst >= Length(AGeom.Pts)) or Bad(AGeom.Pts[AFirst]) then Exit;
    ACount := Trunc(AGeom.Pts[AFirst]);
    Inc(AFirst);
  end
  else
    ACount := 2;
  if AFirst + ACount * 2 > Length(AGeom.Pts) then
    ACount := (Length(AGeom.Pts) - AFirst) div 2;
  Result := ACount >= 2;
end;

{ a straight row's control point when the batch curves }
function LinesCP(const AGeom: TTyLargeGeom; AFirst: Integer;
  out ACX, ACY: Double): Boolean;
var x0, y0, x1, y1: Double;
begin
  Result := (not AGeom.LinesPoly) and (AGeom.LinesCurve > 0);
  ACX := 0;
  ACY := 0;
  if not Result then Exit;
  x0 := AGeom.Pts[AFirst];
  y0 := AGeom.Pts[AFirst + 1];
  x1 := AGeom.Pts[AFirst + 2];
  y1 := AGeom.Pts[AFirst + 3];
  ACX := (x0 + x1) / 2 - (y0 - y1) * AGeom.LinesCurve;
  ACY := (y0 + y1) / 2 - (x1 - x0) * AGeom.LinesCurve;
end;

{ the box one row is drawn in, and whether it draws anything at all }
function LargeRowBox(const AGeom: TTyLargeGeom; ARow: Integer;
  out AX0, AY0, AX1, AY1: Double): Boolean;
var x, y, w, h: Double; first, cnt, k: Integer;
begin
  Result := False;
  AX0 := 0;
  AY0 := 0;
  AX1 := 0;
  AY1 := 0;
  case AGeom.Kind of
    lgkBar:
      begin
        x := AGeom.Pts[ARow * 3];
        y := AGeom.Pts[ARow * 3 + 1];
        if AGeom.BaseDim = 0 then
        begin
          w := AGeom.BarW;
          h := AGeom.Pts[ARow * 3 + 2];
        end
        else
        begin
          w := AGeom.Pts[ARow * 3 + 2];
          h := AGeom.BarW;
        end;
        if Bad(x) or Bad(y) or Bad(w) or Bad(h) then Exit;
        AX0 := Min(x, x + w);
        AX1 := Max(x, x + w);
        AY0 := Min(y, y + h);
        AY1 := Max(y, y + h);
      end;
    lgkSymbol:
      begin
        x := AGeom.Pts[ARow * 2];
        y := AGeom.Pts[ARow * 2 + 1];
        if Bad(x) or Bad(y) then Exit;
        if AGeom.SoftOn and not ((x >= AGeom.Soft.X) and (x <= AGeom.Soft.X + AGeom.Soft.W)
          and (y >= AGeom.Soft.Y) and (y <= AGeom.Soft.Y + AGeom.Soft.H)) then Exit;
        AX0 := x - AGeom.SymW / 2;
        AX1 := x + AGeom.SymW / 2;
        AY0 := y - AGeom.SymH / 2;
        AY1 := y + AGeom.SymH / 2;
      end;
    lgkCandle:
      begin
        if IsNan(AGeom.Pts[ARow * 4]) or (AGeom.Pts[ARow * 4] <> AGeom.Sign) then Exit;
        x := AGeom.Pts[ARow * 4 + 1];
        y := AGeom.Pts[ARow * 4 + 2];
        h := AGeom.Pts[ARow * 4 + 3];
        if Bad(x) or Bad(y) or Bad(h) then Exit;
        AX0 := x;
        AX1 := x;
        AY0 := Min(y, h);
        AY1 := Max(y, h);
      end;
    lgkLines:
      begin
        { the row's points and its control point }
        if not LinesRow(AGeom, ARow, first, cnt) then Exit;
        for k := 0 to cnt - 1 do
        begin
          x := AGeom.Pts[first + k * 2];
          y := AGeom.Pts[first + k * 2 + 1];
          if Bad(x) or Bad(y) then Exit;
          if k = 0 then
          begin
            AX0 := x; AX1 := x; AY0 := y; AY1 := y;
          end
          else
          begin
            AX0 := Min(AX0, x); AX1 := Max(AX1, x);
            AY0 := Min(AY0, y); AY1 := Max(AY1, y);
          end;
        end;
        if LinesCP(AGeom, first, w, h) then
        begin
          AX0 := Min(AX0, w); AX1 := Max(AX1, w);
          AY0 := Min(AY0, h); AY1 := Max(AY1, h);
        end;
      end;
  else
    Exit;
  end;
  Result := True;
end;

procedure TraceLargeRow(P: TTyPainter; const AGeom: TTyLargeGeom;
  const ASpec: TTySymbolSpec; ARow: Integer);
var
  x, y, w, h: Double;
  sub: TTyChartShape;
  first, cnt, k: Integer;
begin
  case AGeom.Kind of
    lgkBar:
      begin
        x := AGeom.Pts[ARow * 3];
        y := AGeom.Pts[ARow * 3 + 1];
        if AGeom.BaseDim = 0 then
        begin
          w := AGeom.BarW;
          h := AGeom.Pts[ARow * 3 + 2];
        end
        else
        begin
          w := AGeom.Pts[ARow * 3 + 2];
          h := AGeom.BarW;
        end;
        if Bad(x) or Bad(y) or Bad(w) or Bad(h) then Exit;
        P.RectPath(x, y, x + w, y + h);
      end;
    lgkSymbol:
      begin
        x := AGeom.Pts[ARow * 2];
        y := AGeom.Pts[ARow * 2 + 1];
        if Bad(x) or Bad(y) then Exit;
        if AGeom.SoftOn and not ((x >= AGeom.Soft.X) and (x <= AGeom.Soft.X + AGeom.Soft.W)
          and (y >= AGeom.Soft.Y) and (y <= AGeom.Soft.Y + AGeom.Soft.H)) then Exit;
        w := AGeom.SymW;
        h := AGeom.SymH;
        if AGeom.Boost then
          P.RectPath(x - w / 2, y - h / 2, x - w / 2 + w, y - h / 2 + h)
        { [F6a] a picture in a large batch: LargeSymbolPath builds through
          the symbol's path, and an image has none -- nothing }
        else if not (ASpec.Kind in [tsyNone, tsyImage]) then
        begin
          sub := TyBuildSymbolInBox(ASpec, TyRectF(x - w / 2, y - h / 2,
            x - w / 2 + w, y - h / 2 + h));
          if sub.Kind <> cskLarge then TyTraceShape(P, sub);
        end;
      end;
    lgkCandle:
      begin
        if IsNan(AGeom.Pts[ARow * 4]) or (AGeom.Pts[ARow * 4] <> AGeom.Sign) then Exit;
        x := AGeom.Pts[ARow * 4 + 1];
        if Bad(x) or Bad(AGeom.Pts[ARow * 4 + 2]) or Bad(AGeom.Pts[ARow * 4 + 3]) then Exit;
        P.MoveTo(x, AGeom.Pts[ARow * 4 + 2]);
        P.LineTo(x, AGeom.Pts[ARow * 4 + 3]);
      end;
    lgkLines:
      begin
        { LargeLinesPath.buildPath: a move and a line (or a quadratic) per
          row, a move and lines per polyline }
        if not LinesRow(AGeom, ARow, first, cnt) then Exit;
        for k := 0 to cnt * 2 - 1 do
          if Bad(AGeom.Pts[first + k]) then Exit;
        P.MoveTo(AGeom.Pts[first], AGeom.Pts[first + 1]);
        if LinesCP(AGeom, first, w, h) then
          P.QuadTo(w, h, AGeom.Pts[first + 2], AGeom.Pts[first + 3])
        else
          for k := 1 to cnt - 1 do
            P.LineTo(AGeom.Pts[first + k * 2], AGeom.Pts[first + k * 2 + 1]);
      end;
  end;
end;

function LargeRowCount(const AGeom: TTyLargeGeom): Integer;
begin
  { a growing progressive batch draws the rows it holds [Batch 119] }
  Result := TyLargeRows(AGeom);
end;

{ every row into the current path }
procedure TraceLarge(P: TTyPainter; const AShape: TTyChartShape);
var
  i: Integer;
  spec: TTySymbolSpec;
begin
  spec := LargeSymbolSpec(AShape.Large);
  for i := 0 to LargeRowCount(AShape.Large) - 1 do
    TraceLargeRow(P, AShape.Large, spec, i);
end;

procedure TyTraceShape(P: TTyPainter; const AShape: TTyChartShape);
var
  i, n: Integer;
  pts: array of TTyVecPoint;
  ops: TTyPathOpArray;
begin
  if P = nil then Exit;
  case AShape.Kind of
    cskLarge:
      TraceLarge(P, AShape);
    cskRect:
      P.RectPath(AShape.Bounds.Left, AShape.Bounds.Top,
                 AShape.Bounds.Right, AShape.Bounds.Bottom);
    cskRoundRect:
      { TRACED HERE RATHER THAN HANDED TO RoundRectPath, which takes ONE radius
        and could not draw a bar rounded only along its top. The four arcs are
        roundRect.ts:78-87 transcribed; the shape record arrives already
        clamped, so nothing is decided at this level.

        A rect with no rounded corner takes the rect path, as upstream does at
        Rect.ts:64-65 -- four zero-radius arcs would draw the same outline, but
        not necessarily the same PIXELS once antialiasing has had its say. }
      if not TyHasCorner(AShape.Radii) then
        P.RectPath(AShape.Bounds.Left, AShape.Bounds.Top,
                   AShape.Bounds.Right, AShape.Bounds.Bottom)
      else
      begin
        P.MoveTo(AShape.Bounds.Left + AShape.Radii[0], AShape.Bounds.Top);
        P.LineTo(AShape.Bounds.Right - AShape.Radii[1], AShape.Bounds.Top);
        if AShape.Radii[1] > 0 then
          P.ArcTo(AShape.Bounds.Right - AShape.Radii[1],
                  AShape.Bounds.Top + AShape.Radii[1], AShape.Radii[1],
                  -Pi / 2, 0, False);
        P.LineTo(AShape.Bounds.Right, AShape.Bounds.Bottom - AShape.Radii[2]);
        if AShape.Radii[2] > 0 then
          P.ArcTo(AShape.Bounds.Right - AShape.Radii[2],
                  AShape.Bounds.Bottom - AShape.Radii[2], AShape.Radii[2],
                  0, Pi / 2, False);
        P.LineTo(AShape.Bounds.Left + AShape.Radii[3], AShape.Bounds.Bottom);
        if AShape.Radii[3] > 0 then
          P.ArcTo(AShape.Bounds.Left + AShape.Radii[3],
                  AShape.Bounds.Bottom - AShape.Radii[3], AShape.Radii[3],
                  Pi / 2, Pi, False);
        P.LineTo(AShape.Bounds.Left, AShape.Bounds.Top + AShape.Radii[0]);
        if AShape.Radii[0] > 0 then
          P.ArcTo(AShape.Bounds.Left + AShape.Radii[0],
                  AShape.Bounds.Top + AShape.Radii[0], AShape.Radii[0],
                  Pi, Pi * 1.5, False);
        P.ClosePath;
      end;
    cskCircle:
      P.CirclePath(AShape.CX, AShape.CY, AShape.R1);
    cskEllipse:
      P.EllipsePath(AShape.CX, AShape.CY, AShape.R0, AShape.R1);
    cskSector:
      if AShape.Sausage then
        TraceSausage(P, AShape)
      else
      begin
        { THE PATH IS COMPUTED SOMEWHERE ELSE and merely replayed here. Rounding
          a sector's corners is a hundred lines of trig, and pixels are a poor
          place to find out which of them is wrong -- so TySectorPath answers
          in primitives a test can read, and this loop turns them into ink.

          ONE PATH FOR EVERY SECTOR, corners or none: two would be two things
          that have to agree. }
        ops := TySectorPath(AShape);
        for i := 0 to High(ops) do
          case ops[i].Kind of
            pokMoveTo: P.MoveTo(ops[i].X, ops[i].Y);
            pokLineTo: P.LineTo(ops[i].X, ops[i].Y);
            pokArc: P.ArcTo(ops[i].X, ops[i].Y, ops[i].R,
                            ops[i].A0, ops[i].A1, ops[i].Anti);
            pokClose: P.ClosePath;
          end;
      end;
    cskPolyline, cskPolygon:
      begin
        { THE PATH, when the shape carries one: its own moves, lines, curves
          and closes, and nothing added }
        if Length(AShape.Cmds) > 0 then
        begin
          for i := 0 to High(AShape.Cmds) do
            case AShape.Cmds[i].Kind of
              pckMove: P.MoveTo(AShape.Cmds[i].X, AShape.Cmds[i].Y);
              pckLine: P.LineTo(AShape.Cmds[i].X, AShape.Cmds[i].Y);
              pckCurve: P.CurveTo(AShape.Cmds[i].X1, AShape.Cmds[i].Y1,
                AShape.Cmds[i].X2, AShape.Cmds[i].Y2, AShape.Cmds[i].X, AShape.Cmds[i].Y);
              pckClose: P.ClosePath;
            end;
          Exit;
        end;
        n := Length(AShape.Points);
        if n = 0 then Exit;
        SetLength(pts, n - 1);
        for i := 1 to n - 1 do
        begin
          pts[i - 1].X := AShape.Points[i].X;
          pts[i - 1].Y := AShape.Points[i].Y;
        end;
        P.MoveTo(AShape.Points[0].X, AShape.Points[0].Y);
        if n > 1 then
          P.PolylineTo(pts);
        if AShape.Kind = cskPolygon then
          P.ClosePath;
      end;
    cskPath:
      { TURNED AT TRACE TIME, and only this kind is. Every other shape is built
        where it lands; a path cannot be, because its geometry is a string in
        the author's own coordinates that the painter fits to a box. The
        transform is pushed and popped around the trace, so the path comes out
        of it already rotated and the fill and the stroke that follow know
        nothing about it. }
      begin
        if AShape.RotationRad <> 0 then
        begin
          P.SaveState;
          P.Translate(AShape.RotCX, AShape.RotCY);
          P.RotateBy(AShape.RotationRad);
          P.Translate(-AShape.RotCX, -AShape.RotCY);
        end;
        if TyRectFIsValid(AShape.Bounds) then
          P.SvgPathIn(AShape.PathData,
                      Rect(Round(AShape.Bounds.Left), Round(AShape.Bounds.Top),
                           Round(AShape.Bounds.Right), Round(AShape.Bounds.Bottom)))
        else
          P.SvgPath(AShape.PathData);
        if AShape.RotationRad <> 0 then P.RestoreState;
      end;
  end;
end;


{ ==================== the halo: the glyphs' outlines, stroked [F4c] ==================== }

function TyNormalizeLineDash(const AType: string; AWidth: Double;
  out APattern: TTyDoubleArray): Boolean;
var
  s, item: string;
  v: Double;
  fs: TFormatSettings;
  i, n: Integer;
begin
  APattern := nil;
  Result := False;
  s := Trim(AType);
  if (s = '') or (s = 'solid') or not (AWidth > 0) then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if s = 'dashed' then
  begin
    SetLength(APattern, 2);
    APattern[0] := 4 * AWidth;
    APattern[1] := 2 * AWidth;
  end
  else if s = 'dotted' then
  begin
    SetLength(APattern, 1);
    APattern[0] := AWidth;
  end
  else if s[1] = '[' then
  begin
    { a JSON array of numbers, as written }
    s := Copy(s, 2, Length(s) - 2);
    n := 0;
    while s <> '' do
    begin
      i := Pos(',', s);
      if i = 0 then i := Length(s) + 1;
      item := Trim(Copy(s, 1, i - 1));
      Delete(s, 1, i);
      if not TryStrToFloat(item, v, fs) then Continue;
      SetLength(APattern, n + 1);
      APattern[n] := v;
      Inc(n);
    end;
  end
  else if TryStrToFloat(s, v, fs) then
  begin
    SetLength(APattern, 1);
    APattern[0] := v;
  end
  else
    Exit;
  Result := Length(APattern) > 0;
end;

type
  { [R2-P] A TRACED OUTLINE: the closed contours marching squares found on a
    halo's mask, every point in the mask's own px divided by the device
    scale -- what the halo's path is given is a point plus the mask's
    origin, so one outline serves wherever the same mask is drawn. }
  TTyHaloOutline = class
  public
    Pts: array of Double;      // x, y of every point, contour after contour
    Starts: array of Integer;  // contour k: points Starts[k] .. Starts[k + 1] - 1
    Contours: Integer;
  end;

  { the trace's scratch: the padded alpha, the crossings and the segment
    slots per edge key; kept on the main thread (TraceMaskOutline), grown as
    a mask needs, never shrunk below what the largest kept one asked }
  TTraceWork = class
  public
    Al: array of Byte;
    Ex, Ey: array of Double;
    Adj: array of Integer;
    procedure Fit(AAlpha, AKeys: Integer);
  end;

procedure TTraceWork.Fit(AAlpha, AKeys: Integer);
begin
  if Length(Al) < AAlpha then SetLength(Al, AAlpha);
  if Length(Ex) < AKeys then
  begin
    SetLength(Ex, AKeys);
    SetLength(Ey, AKeys);
  end;
  if Length(Adj) < 2 * AKeys then SetLength(Adj, 2 * AKeys);
end;

const
  { a box past this many edge keys gets scratch of its own, freed after }
  TraceWorkMaxKeys = 1024 * 1024;

var
  GHaloTraces: Integer = 0;
  GTraceWork: TTraceWork = nil;

{ THE GLYPHS' OUTLINES from their coverage: marching squares over the mask's
  alpha at half coverage, each crossing placed by linear interpolation
  between the pixel centres, the segments chained into closed contours. A
  contour is a glyph's outline as the painter drew the glyph -- which is
  what zrender strokes: the text's own path. The mask holds AScale of its
  pixels per device px -- P's device scale, the glyphs drawn on it as on
  P's layer (#83) -- so a crossing is divided by it. Only its AWidth x
  AHeight corner is the mask (a kept one may be larger: MaskPainter).

  [R2-P] ONLY ROUND THE INK. A cell makes a segment only where its four
  corners are not all on one side of the half, so no cell without a corner
  at half coverage or more makes any: the walk is the box of those pixels
  grown by a cell up and left, in the same row-by-row order, so the
  segments come in the same order and chain into the same contours. The
  alpha is read once into a padded copy of that box -- a rotated label's
  mask is a square round the anchor, its ink a thin strip across it, and
  the whole-mask walk with a GetPixel per corner was most of a radial
  tree's first frame. An edge's key is its place in the box's grid, not
  the mask's; keys are only compared. }
function TraceMaskOutline(AMask: TBGRABitmap; AWidth, AHeight, AScale: Integer): TTyHaloOutline;
const
  cT = 127.5;
var
  w, h, x0, y0, x1, y1, aw, ah, nKeys, cx, cy, i, k, cur, seg, startKey, key, nSeg: Integer;
  xMin, yMin, xMax, yMax, x, y, np, nPts: Integer;
  al: PByte;
  row: PBGRAPixel;
  ex, ey: PDouble;
  segA, segB: array of Integer;
  adj: PInteger;             // two segment slots per key
  used: array of Boolean;
  wk: TTraceWork;
  ownWork: Boolean;
  v0, v1, v2, v3, centre: Double;
  b0, b1, b2, b3: Boolean;
  kTop, kRight, kBottom, kLeft: Integer;
  o: TTyHaloOutline;

  function A(AX, AY: Integer): Double;
  begin
    Result := al[(AY - y0) * aw + (AX - x0)];
  end;

  { an edge's key: the horizontal edge from sample (AX, AY) to (AX + 1, AY),
    or the vertical one down to (AX, AY + 1) }
  function KeyH(AX, AY: Integer): Integer;
  begin
    Result := ((AY - y0) * aw + (AX - x0)) * 2;
  end;

  function KeyV(AX, AY: Integer): Integer;
  begin
    Result := ((AY - y0) * aw + (AX - x0)) * 2 + 1;
  end;

  procedure Cross(AKey: Integer; AX0, AY0, AV0, AX1, AY1, AV1: Double);
  var t: Double;
  begin
    if AV1 = AV0 then t := 0.5 else t := (cT - AV0) / (AV1 - AV0);
    ex[AKey] := AX0 + (AX1 - AX0) * t + 0.5;
    ey[AKey] := AY0 + (AY1 - AY0) * t + 0.5;
  end;

  procedure Seg2(AK0, AK1: Integer);
  begin
    if nSeg > High(segA) then
    begin
      SetLength(segA, Length(segA) * 2 + 16);
      SetLength(segB, Length(segA));
    end;
    segA[nSeg] := AK0;
    segB[nSeg] := AK1;
    if adj[AK0 * 2] < 0 then adj[AK0 * 2] := nSeg else adj[AK0 * 2 + 1] := nSeg;
    if adj[AK1 * 2] < 0 then adj[AK1 * 2] := nSeg else adj[AK1 * 2 + 1] := nSeg;
    Inc(nSeg);
  end;

  procedure AddPoint(AKey: Integer);
  begin
    if 2 * nPts + 1 > High(o.Pts) then SetLength(o.Pts, Length(o.Pts) * 2 + 64);
    o.Pts[2 * nPts] := ex[AKey] / AScale;
    o.Pts[2 * nPts + 1] := ey[AKey] / AScale;
    Inc(nPts);
  end;

begin
  Inc(GHaloTraces);
  o := TTyHaloOutline.Create;
  Result := o;
  SetLength(o.Starts, 1);
  o.Starts[0] := 0;
  o.Contours := 0;
  if AMask = nil then Exit;
  w := Min(AWidth, AMask.Width);
  h := Min(AHeight, AMask.Height);
  { the ink: the pixels at half coverage or more }
  xMin := w;
  yMin := h;
  xMax := -1;
  yMax := -1;
  for y := 0 to h - 1 do
  begin
    row := AMask.ScanLine[y];
    for x := 0 to w - 1 do
    begin
      if row^.alpha >= 128 then
      begin
        if x < xMin then xMin := x;
        if x > xMax then xMax := x;
        if y < yMin then yMin := y;
        yMax := y;
      end;
      Inc(row);
    end;
  end;
  if xMax < 0 then Exit;
  { the cells from (x0, y0) to (x1, y1); their corners one further }
  x0 := xMin - 1;
  y0 := yMin - 1;
  x1 := xMax;
  y1 := yMax;
  aw := x1 - x0 + 2;
  ah := y1 - y0 + 2;
  nKeys := aw * ah * 2;
  ownWork := (GetCurrentThreadId <> MainThreadID) or (nKeys > TraceWorkMaxKeys);
  if ownWork then
    wk := TTraceWork.Create
  else
  begin
    if GTraceWork = nil then GTraceWork := TTraceWork.Create;
    wk := GTraceWork;
  end;
  try
    wk.Fit(aw * ah, nKeys);
    al := @wk.Al[0];
    ex := @wk.Ex[0];
    ey := @wk.Ey[0];
    adj := @wk.Adj[0];
    FillChar(al^, aw * ah, 0);     // the padding is 0
    for y := y0 to y1 + 1 do
    begin
      if (y < 0) or (y >= h) then Continue;
      row := AMask.ScanLine[y];
      for x := x0 to x1 + 1 do
        if (x >= 0) and (x < w) then
          al[(y - y0) * aw + (x - x0)] := row[x].alpha;
    end;
    { every slot empty; a crossing is written before it is read }
    FillDWord(adj^, nKeys * 2, LongWord(-1));
    segA := nil;
    segB := nil;
    nSeg := 0;
    for cy := y0 to y1 do
      for cx := x0 to x1 do
      begin
        v0 := A(cx, cy);
        v1 := A(cx + 1, cy);
        v2 := A(cx + 1, cy + 1);
        v3 := A(cx, cy + 1);
        b0 := v0 >= cT;
        b1 := v1 >= cT;
        b2 := v2 >= cT;
        b3 := v3 >= cT;
        if (b0 = b1) and (b1 = b2) and (b2 = b3) then Continue;
        kTop := KeyH(cx, cy);
        kBottom := KeyH(cx, cy + 1);
        kLeft := KeyV(cx, cy);
        kRight := KeyV(cx + 1, cy);
        if b0 <> b1 then Cross(kTop, cx, cy, v0, cx + 1, cy, v1);
        if b1 <> b2 then Cross(kRight, cx + 1, cy, v1, cx + 1, cy + 1, v2);
        if b3 <> b2 then Cross(kBottom, cx, cy + 1, v3, cx + 1, cy + 1, v2);
        if b0 <> b3 then Cross(kLeft, cx, cy, v0, cx, cy + 1, v3);
        if (b0 = b2) and (b1 = b3) and (b0 <> b1) then
        begin
          { a saddle: the centre decides which corners join }
          centre := (v0 + v1 + v2 + v3) / 4;
          if (centre >= cT) = b0 then
          begin
            Seg2(kTop, kRight);     // b1's corner cut off
            Seg2(kBottom, kLeft);   // b3's
          end
          else
          begin
            Seg2(kLeft, kTop);      // b0's
            Seg2(kRight, kBottom);  // b2's
          end;
          Continue;
        end;
        { two crossings: one segment }
        k := -1;
        cur := -1;
        if b0 <> b1 then begin if k < 0 then k := kTop else cur := kTop; end;
        if b1 <> b2 then begin if k < 0 then k := kRight else cur := kRight; end;
        if b3 <> b2 then begin if k < 0 then k := kBottom else cur := kBottom; end;
        if b0 <> b3 then begin if k < 0 then k := kLeft else cur := kLeft; end;
        if (k >= 0) and (cur >= 0) then Seg2(k, cur);
      end;
    if nSeg = 0 then Exit;     // the finally lets go of the scratch
    SetLength(used, nSeg);
    for i := 0 to nSeg - 1 do used[i] := False;
    nPts := 0;
    for i := 0 to nSeg - 1 do
    begin
      if used[i] then Continue;
      used[i] := True;
      startKey := segA[i];
      np := 1;
      AddPoint(startKey);
      key := segB[i];
      { follow the contour round to where it began }
      while key <> startKey do
      begin
        AddPoint(key);
        Inc(np);
        seg := adj[key * 2];
        if (seg < 0) or used[seg] then seg := adj[key * 2 + 1];
        if (seg < 0) or used[seg] then Break;
        used[seg] := True;
        if segA[seg] = key then key := segB[seg] else key := segA[seg];
      end;
      Inc(o.Contours);
      SetLength(o.Starts, o.Contours + 1);
      o.Starts[o.Contours] := nPts;
    end;
    SetLength(o.Pts, 2 * nPts);
  finally
    if ownWork then wk.Free;
  end;
end;

{ The outline on P, in DEVICE px, the mask's (0, 0) at (AOX, AOY): each
  contour closed, or -- with a pattern -- in dashes laid along it by its
  length, the pattern's phase starting afresh on each contour, as a canvas
  starts it on each subpath (an odd pattern is said twice); each dash an
  open subpath of its own. [R2-F] The phase is ADashOffsetDevice along the
  pattern (a canvas' lineDashOffset), on every contour. }
procedure TraceHaloOutline(P: TTyPainter; AOutline: TTyHaloOutline; AOX, AOY: Integer;
  const ADashDevice: TTyDoubleArray; ADashOffsetDevice: Double = 0);
var
  px, py: array of Double;
  c, s, np, k: Integer;

  procedure DashContour(ACount: Integer);
  var
    pat: array of Double;
    j, di, n: Integer;
    x0, y0, x1, y1, segLen, pos, left, t, sx, sy: Double;
    on, open, moved: Boolean;

    { [R2-F] a dash's next point: its move made at its first point that goes
      anywhere, so a dash of no length (a zero in the pattern) is no
      subpath at all -- under the halo's butt cap a canvas draws nothing
      there either }
    procedure DashTo(AX, AY: Double);
    begin
      if not moved then
      begin
        if (AX = sx) and (AY = sy) then Exit;
        P.MoveTo(sx, sy);
        moved := True;
      end;
      P.LineTo(AX, AY);
    end;

  begin
    n := Length(ADashDevice);
    if Odd(n) then
    begin
      SetLength(pat, 2 * n);
      for j := 0 to n - 1 do
      begin
        pat[j] := ADashDevice[j];
        pat[n + j] := ADashDevice[j];
      end;
    end
    else
      pat := Copy(ADashDevice, 0, n);
    { a pattern that never advances draws the contour whole }
    t := 0;
    for j := 0 to High(pat) do t := t + Max(Double(0), pat[j]);
    if not (t > 0) then
    begin
      P.MoveTo(px[0], py[0]);
      for j := 1 to ACount - 1 do P.LineTo(px[j], py[j]);
      P.ClosePath;
      Exit;
    end;
    di := 0;
    left := pat[0];
    { [R2-F] the phase: where on the pattern the contour starts }
    if not (IsNan(ADashOffsetDevice) or IsInfinite(ADashOffsetDevice)) then
    begin
      pos := ADashOffsetDevice - Floor(ADashOffsetDevice / t) * t;
      if (pos < 0) or (pos >= t) then pos := 0;
      while pos > 0 do
        if pos < left then
        begin
          left := left - pos;
          pos := 0;
        end
        else
        begin
          pos := pos - left;
          di := (di + 1) mod Length(pat);
          left := pat[di];
        end;
    end;
    on := not Odd(di);
    open := False;
    for j := 0 to ACount - 1 do
    begin
      x0 := px[j];
      y0 := py[j];
      x1 := px[(j + 1) mod ACount];
      y1 := py[(j + 1) mod ACount];
      segLen := Sqrt(Sqr(x1 - x0) + Sqr(y1 - y0));
      pos := 0;
      while pos < segLen do
      begin
        if on and not open then
        begin
          sx := x0 + (x1 - x0) * (pos / segLen);
          sy := y0 + (y1 - y0) * (pos / segLen);
          moved := False;
          open := True;
        end;
        if segLen - pos <= left then
        begin
          left := left - (segLen - pos);
          pos := segLen;
          if on then DashTo(x1, y1);
        end
        else
        begin
          pos := pos + left;
          if on then
          begin
            DashTo(x0 + (x1 - x0) * (pos / segLen), y0 + (y1 - y0) * (pos / segLen));
            open := False;
          end;
          di := (di + 1) mod Length(pat);
          left := pat[di];
          on := not Odd(di);
        end;
      end;
    end;
  end;

begin
  if AOutline = nil then Exit;
  for c := 0 to AOutline.Contours - 1 do
  begin
    s := AOutline.Starts[c];
    np := AOutline.Starts[c + 1] - s;
    if np <= 0 then Continue;
    SetLength(px, np);
    SetLength(py, np);
    for k := 0 to np - 1 do
    begin
      px[k] := AOutline.Pts[2 * (s + k)] + AOX;
      py[k] := AOutline.Pts[2 * (s + k) + 1] + AOY;
    end;
    if Length(ADashDevice) = 0 then
    begin
      P.MoveTo(px[0], py[0]);
      for k := 1 to np - 1 do P.LineTo(px[k], py[k]);
      P.ClosePath;
    end
    else
      DashContour(np);
  end;
end;

function TyTraceMaskOutlineForTest(AMask: TBGRABitmap; AScale: Integer): TTyDoubleArray;
var
  o: TTyHaloOutline;
  c, k, n, s, np: Integer;
begin
  Result := nil;
  o := TraceMaskOutline(AMask, AMask.Width, AMask.Height, AScale);
  try
    n := 0;
    for c := 0 to o.Contours - 1 do
    begin
      s := o.Starts[c];
      np := o.Starts[c + 1] - s;
      SetLength(Result, n + 1 + 2 * np);
      Result[n] := np;
      Inc(n);
      for k := 0 to 2 * np - 1 do
      begin
        Result[n] := o.Pts[2 * s + k];
        Inc(n);
      end;
    end;
  finally
    o.Free;
  end;
end;

{ [R2-P] THE OUTLINES, KEPT. A chart repaints its labels on every hover
  and animation frame, and a halo used to draw its glyphs on a fresh mask
  and trace them every time. The outline is the mask's, and the mask is
  the drawing's arguments: the key is all of them -- the words, the font,
  its size and weight, where on the mask the run is put (to the last bit,
  so the sub-pixel offset is in it), its turn and alignment or its box,
  truncation and line breaking, the mask's size, the PPI and the device
  scale (#83). The pen -- width, dash, colour -- is not: it is laid on the
  outline afterwards. What else reaches the glyphs is the painter's text
  state, whose every change TyInvalidateTextMeasureCache announces: its
  generation moving drops them all. Main thread only, as the painter's own
  run cache; past HaloOutlineMaxCount outlines or HaloOutlineMaxPoints
  points everything is dropped (the measurement memo's clear-not-evict). }
const
  HaloOutlineMaxCount = 4096;
  HaloOutlineMaxPoints = 1024 * 1024;

var
  GHaloOutlines: specialize TDictionary<string, TTyHaloOutline> = nil;
  GHaloPoints: Int64 = 0;
  GHaloGeneration: Cardinal = 0;
  GHaloCacheOff: Boolean = False;

procedure DropHaloOutlines;
var o: TTyHaloOutline;
begin
  if GHaloOutlines <> nil then
  begin
    for o in GHaloOutlines.Values do o.Free;
    GHaloOutlines.Clear;
  end;
  GHaloPoints := 0;
end;

function HaloCacheOn: Boolean;
begin
  Result := not GHaloCacheOff and (GetCurrentThreadId = MainThreadID);
end;

{ the outline kept under AKey, or nil }
function HaloOutlineKept(const AKey: string): TTyHaloOutline;
begin
  Result := nil;
  if GHaloOutlines = nil then Exit;
  if GHaloGeneration <> TyTextMeasureGeneration then
  begin
    DropHaloOutlines;
    GHaloGeneration := TyTextMeasureGeneration;
    Exit;
  end;
  GHaloOutlines.TryGetValue(AKey, Result);
end;

procedure KeepHaloOutline(const AKey: string; AOutline: TTyHaloOutline);
begin
  if GHaloOutlines = nil then
    GHaloOutlines := specialize TDictionary<string, TTyHaloOutline>.Create;
  if GHaloGeneration <> TyTextMeasureGeneration then
  begin
    DropHaloOutlines;
    GHaloGeneration := TyTextMeasureGeneration;
  end;
  if (GHaloOutlines.Count >= HaloOutlineMaxCount)
    or (GHaloPoints + Length(AOutline.Pts) div 2 > HaloOutlineMaxPoints) then
    DropHaloOutlines;
  GHaloOutlines.Add(AKey, AOutline);
  Inc(GHaloPoints, Length(AOutline.Pts) div 2);
end;

function TyAdvChartHaloTracesForTest: Integer;
begin
  Result := GHaloTraces;
end;

function TyAdvChartHaloOutlinesKeptForTest: Integer;
begin
  Result := 0;
  if GHaloOutlines <> nil then Result := GHaloOutlines.Count;
end;

procedure TyAdvChartHaloCacheForTest(AOn: Boolean);
begin
  DropHaloOutlines;
  GHaloCacheOff := not AOn;
end;

{ a Double in a key, to the bit }
function KeyBits(AV: Double): string;
begin
  Result := IntToHex(PInt64(@AV)^, 16);
end;

{ A PAINTER ON A MASK of AW x AH at P's PPI: the glyphs are drawn on it
  exactly as on P, only moved by whole pixels. At P's device scale too: the
  mask is that many times the size, its painter draws at that scale, and the
  outline traced from it is as fine as the glyphs on P's layer (#83).

  [R2-P] ONE MASK, KEPT, on the main thread: a fresh bitmap per halo was a
  DIB section made and freed per label. The kept one only grows (up to
  HaloMaskMaxPixels; a larger mask is made and freed as before), and its
  top-left AW x AH -- times the scale -- is cleared to transparent before
  each use, which is what a fresh one holds. What is drawn there is the
  same; what lands beyond it is never read (TraceMaskOutline reads that
  corner only). AOwned: the caller frees AMask. }
const
  HaloMaskMaxPixels = 2048 * 2048;

var
  GHaloMask: TBGRABitmap = nil;

function MaskPainter(P: TTyPainter; AW, AH: Integer; out AMask: TBGRABitmap;
  out AOwned: Boolean): TTyPainter;
var
  sc: TTyCanvasScale;
  w, h: Integer;
begin
  sc.Scale := P.DeviceScale;
  sc.DeviceUnits := False;
  w := AW * sc.Scale;
  h := AH * sc.Scale;
  AOwned := not HaloCacheOn or (Int64(w) * h > HaloMaskMaxPixels);
  if AOwned then
    AMask := TBGRABitmap.Create(w, h, BGRAPixelTransparent)
  else
  begin
    if GHaloMask = nil then
      GHaloMask := TBGRABitmap.Create(w, h, BGRAPixelTransparent)
    else
    begin
      if (GHaloMask.Width < w) or (GHaloMask.Height < h) then
        GHaloMask.SetSize(Max(GHaloMask.Width, w), Max(GHaloMask.Height, h));
      GHaloMask.FillRect(0, 0, w, h, BGRAPixelTransparent, dmSet);
    end;
    AMask := GHaloMask;
  end;
  Result := TTyPainter.Create;
  Result.BeginPaintOnScaled(nil, Rect(0, 0, AW, AH), P.PPI, AMask, sc);
end;

{ the stroke along the mask's contours, under the glyphs: one path, so
  where two strokes meet the ink is laid once and a translucent halo does
  not darken; dashed as the type says }
procedure StrokeMaskHalo(P: TTyPainter; AOutline: TTyHaloOutline; AOX, AOY: Integer;
  AColour: TTyColor; AWidthLogical: Double; const ADashType: string;
  ADashOffsetLogical: Double = 0);
var
  pat: TTyDoubleArray;
  k: Integer;
begin
  P.SaveState;
  try
    P.ResetTransform;
    P.SetLineDash([]);
    { the dashes are laid by length here, in device px: the painter's pen
      restarts its pattern on every segment, and a contour is all short
      segments }
    if TyNormalizeLineDash(ADashType, AWidthLogical, pat) then
      for k := 0 to High(pat) do pat[k] := pat[k] * P.PPI / 96
    else
      pat := nil;
    P.BeginPath;
    TraceHaloOutline(P, AOutline, AOX, AOY, pat, ADashOffsetLogical * P.PPI / 96);
    { [R2-P] kept: the next frame's halo of the same label at the same place
      replays this one's coverage }
    P.StrokePathKept(AColour, AWidthLogical);
    P.BeginPath;
  finally
    P.RestoreState;
  end;
end;

{ a rotated or anchored text's halo: its glyphs as DrawTextRotated puts them }
procedure HaloRotated(P: TTyPainter; const AText, AFont: string; ASize, AWeight: Integer;
  AX, AY, ARotationRad: Double; AH: TAlignment; AV: TTextLayout;
  AColour: TTyColor; AWidthLogical: Double; const ADashType: string;
  ADashOffsetLogical: Double = 0);
var
  sz: TSize;
  r, ox, oy, mw, mh: Integer;
  mx, my: Double;
  mp: TTyPainter;
  mask: TBGRABitmap;
  owned: Boolean;
  ol: TTyHaloOutline;
  key: string;
begin
  sz := P.MeasureText(AText, AFont, ASize, AWeight);
  { round the anchor, any turn: the text's diagonal, and the stroke }
  r := sz.cx + sz.cy + Ceil(AWidthLogical * P.PPI / 96) + 4;
  ox := Floor(AX) - r;
  oy := Floor(AY) - r;
  mw := 2 * r + 2;
  mh := 2 * r + 2;
  mx := AX - ox;
  my := AY - oy;
  ol := nil;
  key := '';
  if HaloCacheOn then
  begin
    key := 'R' + IntToStr(P.PPI) + ',' + IntToStr(P.DeviceScale) + ',' + IntToStr(mw)
      + ',' + IntToStr(mh) + ',' + IntToStr(ASize) + ',' + IntToStr(AWeight) + ','
      + KeyBits(mx) + KeyBits(my) + KeyBits(ARotationRad) + IntToStr(Ord(AH))
      + IntToStr(Ord(AV)) + ',' + IntToStr(Length(AFont)) + ',' + AFont + AText;
    ol := HaloOutlineKept(key);
  end;
  if ol = nil then
  begin
    mp := MaskPainter(P, mw, mh, mask, owned);
    try
      mp.DrawTextRotated(AText, AFont, ASize, AWeight, TTyColor($FFFFFFFF),
        mx, my, ARotationRad, AH, AV);
      mp.EndPaint;
      ol := TraceMaskOutline(mask, mw * P.DeviceScale, mh * P.DeviceScale, P.DeviceScale);
    finally
      mp.Free;
      if owned then mask.Free;
    end;
    if key <> '' then KeepHaloOutline(key, ol);
  end;
  try
    StrokeMaskHalo(P, ol, ox, oy, AColour, AWidthLogical, ADashType, ADashOffsetLogical);
  finally
    if key = '' then ol.Free;
  end;
end;

{ The ink a caption is drawn in, with the element's alpha baked in.

  BAKED RATHER THAN SET, because the painter's two text entries write straight
  to the bitmap while everything else in TyRenderElement goes through the
  Canvas2D state -- so a caption drawn inside the SaveState block would quietly
  disobey the alpha it appears to be inside. Folding it into the colour byte is
  the honest version, and drawing after RestoreState is where it belongs. }
function CaptionInk(AColour: TTyChartColor; AAlpha: Double): TTyColor;
var a: Integer;
begin
  if AAlpha >= 1 then Exit(TTyColor(AColour));
  if AAlpha < 0 then AAlpha := 0;
  a := Round(((AColour shr 24) and $FF) * AAlpha);
  Result := TTyColor((AColour and $00FFFFFF) or (Cardinal(a) shl 24));
end;

{ The box DrawText wants, hung off an anchor. }
function CaptionBox(const AC: TTyElementCaption; AW, AH: Double): TRect;
begin
  case AC.AnchorH of
    tahCentre: Result.Left := Round(AC.X - AW / 2);
    tahRight: Result.Left := Round(AC.X - AW);
  else
    Result.Left := Round(AC.X);
  end;
  Result.Right := Result.Left + Round(AW);
  case AC.AnchorV of
    tavMiddle: Result.Top := Round(AC.Y - AH / 2);
    tavBottom: Result.Top := Round(AC.Y - AH);
  else
    Result.Top := Round(AC.Y);
  end;
  Result.Bottom := Result.Top + Round(AH);
end;

type
  { [R2-P] WHAT DrawCaptionAt HANDS THE PAINTER, worked out once: the halo's
    outline is kept by it, so its key is the drawing's own arguments. Kind 0
    a turned run at an anchor; 1 the shape's rect; 2 a box hung off the
    anchor (no line breaking). }
  TCaptionDraw = record
    Kind: Integer;
    Text, FontName: string;
    Size, Weight: Integer;
    X, Y, Rot: Double;
    R: TRect;
    H: TAlignment;
    V: TTextLayout;
    Truncate, MultiLine: Boolean;
  end;

function CaptionDrawOf(const AElement: TTyChartElement; ADX, ADY: Integer): TCaptionDraw; forward;
procedure PaintCaptionDraw(P: TTyPainter; const AD: TCaptionDraw; AInk: TTyColor); forward;
procedure DrawCaptionAt(P: TTyPainter; const AElement: TTyChartElement;
  AInk: TTyColor; ADX, ADY: Integer); forward;

function CaptionDrawKey(const AD: TCaptionDraw): string;
begin
  Result := IntToStr(AD.Kind) + ',' + IntToStr(AD.Size) + ',' + IntToStr(AD.Weight) + ',';
  if AD.Kind = 0 then
    Result := Result + KeyBits(AD.X) + KeyBits(AD.Y) + KeyBits(AD.Rot)
  else
    Result := Result + IntToStr(AD.R.Left) + ',' + IntToStr(AD.R.Top) + ','
      + IntToStr(AD.R.Right) + ',' + IntToStr(AD.R.Bottom) + ','
      + IntToStr(Ord(AD.Truncate)) + IntToStr(Ord(AD.MultiLine));
  Result := Result + IntToStr(Ord(AD.H)) + IntToStr(Ord(AD.V)) + ','
    + IntToStr(Length(AD.FontName)) + ',' + AD.FontName + AD.Text;
end;

{ zrender's roundRect: the radii spread CSS-wise already, cut down so that
  every side holds the two corners on it (roundRect.ts:30-76) }
procedure TraceRtRect(P: TTyPainter; AX, AY, AW, AH: Double;
  const AR: array of Double);
var
  r1, r2, r3, r4, total: Double;
begin
  if AW < 0 then begin AX := AX + AW; AW := -AW; end;
  if AH < 0 then begin AY := AY + AH; AH := -AH; end;
  r1 := Max(0.0, AR[0]);
  r2 := Max(0.0, AR[1]);
  r3 := Max(0.0, AR[2]);
  r4 := Max(0.0, AR[3]);
  if (r1 + r2 + r3 + r4) <= 0 then
  begin
    P.RectPath(AX, AY, AX + AW, AY + AH);
    Exit;
  end;
  total := r1 + r2;
  if total > AW then begin r1 := r1 * AW / total; r2 := r2 * AW / total; end;
  total := r3 + r4;
  if total > AW then begin r3 := r3 * AW / total; r4 := r4 * AW / total; end;
  total := r2 + r3;
  if total > AH then begin r2 := r2 * AH / total; r3 := r3 * AH / total; end;
  total := r1 + r4;
  if total > AH then begin r1 := r1 * AH / total; r4 := r4 * AH / total; end;
  P.MoveTo(AX + r1, AY);
  P.LineTo(AX + AW - r2, AY);
  if r2 > 0 then P.ArcTo(AX + AW - r2, AY + r2, r2, -Pi / 2, 0, False);
  P.LineTo(AX + AW, AY + AH - r3);
  if r3 > 0 then P.ArcTo(AX + AW - r3, AY + AH - r3, r3, 0, Pi / 2, False);
  P.LineTo(AX + r4, AY + AH);
  if r4 > 0 then P.ArcTo(AX + r4, AY + AH - r4, r4, Pi / 2, Pi, False);
  P.LineTo(AX, AY + r1);
  if r1 > 0 then P.ArcTo(AX + r1, AY + r1, r1, Pi, Pi * 1.5, False);
  P.ClosePath;
end;

function RtAlign(A: TTyRtAlign): TAlignment;
begin
  case A of
    rtaCenter: Result := taCenter;
    rtaRight: Result := taRightJustify;
  else
    Result := taLeftJustify;
  end;
end;

procedure TyRenderRtPieces(P: TTyPainter; const APieces: TTyRtPieceArray;
  AX, AY, ARotationRad, AScale, AAlpha: Double; AHasInk: Boolean;
  AInk: TTyColor);
var
  i, dx, dy, reach: Integer;
  pc: TTyRtPiece;
  a, gx, gy, r, rr, s: Double;
  ink, halo, shade: TTyColor;
  hasInk: Boolean;
  k: Integer;
  radii: array[0..3] of Double;
begin
  if P = nil then Exit;
  if AScale <= 0 then AScale := 1;
  for i := 0 to High(APieces) do
  begin
    pc := APieces[i];
    a := pc.Opacity * AAlpha;
    if pc.Kind = rpkRect then
    begin
      if not pc.Drawn then Continue;
      P.SaveState;
      try
        if a < 1 then P.SetElementAlpha(a);
        P.SetLineDash([]);
        P.Translate(AX, AY);
        if ARotationRad <> 0 then P.RotateBy(-ARotationRad);
        for k := 0 to 3 do radii[k] := pc.Radius[k] * AScale;
        { THE BORDER UNDER THE FILL where the rect has both: zrender paints
          it first at twice its width, so the fill covers its inner half }
        if pc.HasStroke and pc.StrokeFirst then
        begin
          P.BeginPath;
          TraceRtRect(P, pc.X * AScale, pc.Y * AScale, pc.W * AScale,
            pc.H * AScale, radii);
          P.StrokePath(TTyColor(pc.Stroke), pc.LineWidth);
        end;
        if pc.HasFill then
        begin
          P.BeginPath;
          TraceRtRect(P, pc.X * AScale, pc.Y * AScale, pc.W * AScale,
            pc.H * AScale, radii);
          P.FillPath(TTyColor(pc.Fill));
        end;
        if pc.HasStroke and not pc.StrokeFirst then
        begin
          P.BeginPath;
          TraceRtRect(P, pc.X * AScale, pc.Y * AScale, pc.W * AScale,
            pc.H * AScale, radii);
          P.StrokePath(TTyColor(pc.Stroke), pc.LineWidth);
        end;
      finally
        P.RestoreState;
      end;
      Continue;
    end;
    if pc.Text = '' then Continue;
    TyRtPoint(AX, AY, ARotationRad, AScale, pc.X, pc.Y, gx, gy);
    hasInk := pc.HasFill;
    ink := TTyColor(pc.Fill);
    if not hasInk and pc.DefaultFill and AHasInk then
    begin
      hasInk := True;
      ink := AInk;
    end;
    { THE SHADOW, unblurred: the painter has no blur for glyphs, so what
      survives of a text shadow is its offset copy. zrender sets none at all
      without a blur (Text.ts:611, 850), whatever the offsets say }
    if pc.HasShadow and ((pc.ShadowOffsetX <> 0) or (pc.ShadowOffsetY <> 0))
      and ((pc.ShadowColor shr 24) <> 0) then
    begin
      shade := CaptionInk(pc.ShadowColor, a);
      P.DrawTextRotated(TyInkText(pc.Text), pc.FontFamily,
        TyFontSizeFromPx(pc.FontSizePx), pc.FontWeight, shade,
        gx + pc.ShadowOffsetX * AScale, gy + pc.ShadowOffsetY * AScale,
        ARotationRad, RtAlign(pc.TextAlign), tlCenter);
    end;
    { THE HALO FIRST -- a text's stroke is painted under its fill -- as the
      one-run caption dilates it }
    if pc.HasStroke and (pc.LineWidth > 0) and ((pc.Stroke shr 24) <> 0) then
    begin
      { [F4c] A STROKE ALONG THE GLYPHS' OUTLINES, lineWidth wide and centred
        on them (zrender's strokeText), dashed as textBorderType says --
        where the halo used to be the glyphs stamped at whole-pixel offsets,
        whose overlaps darkened a translucent one }
      halo := CaptionInk(pc.Stroke, a);
      HaloRotated(P, TyInkText(pc.Text), pc.FontFamily,
        TyFontSizeFromPx(pc.FontSizePx), pc.FontWeight, gx, gy, ARotationRad,
        RtAlign(pc.TextAlign), tlCenter, halo, pc.LineWidth, pc.LineDash,
        pc.LineDashOffset);
    end;
    if not hasInk then Continue;
    s := a;
    P.DrawTextRotated(TyInkText(pc.Text), pc.FontFamily,
      TyFontSizeFromPx(pc.FontSizePx), pc.FontWeight, CaptionInk(ink, s),
      gx, gy, ARotationRad, RtAlign(pc.TextAlign), tlCenter);
  end;
end;

{ [F4c] a caption's halo: its glyphs drawn on a mask exactly as
  DrawCaptionAt draws them, moved by whole pixels, and a stroke along their
  outlines -- StrokeWidthLogical wide, centred on them (zrender's
  strokeText), dashed per StrokeType }
procedure HaloCaption(P: TTyPainter; const AElement: TTyChartElement; AHalo: TTyColor);
var
  b: TTyRectF;
  sz: TSize;
  m, ox, oy, mw, mh: Integer;
  mp: TTyPainter;
  mask: TBGRABitmap;
  owned: Boolean;
  d: TCaptionDraw;
  ol: TTyHaloOutline;
  key: string;
begin
  m := Ceil(AElement.Caption.StrokeWidthLogical * P.PPI / 96) + 4;
  b := AElement.Shape.Bounds;
  if (AElement.Caption.RotationRad <> 0) or not TyRectFIsValid(b) then
  begin
    { round the anchor, any turn or alignment: the text's diagonal }
    sz := P.MeasureText(TyInkText(AElement.Caption.Text), AElement.Caption.FontName,
      AElement.Caption.FontSizeLogical, AElement.Caption.FontWeight);
    ox := Floor(AElement.Caption.X) - (sz.cx + sz.cy + m);
    oy := Floor(AElement.Caption.Y) - (sz.cx + sz.cy + m);
    mw := 2 * (sz.cx + sz.cy + m) + 2;
    mh := mw;
  end
  else
  begin
    ox := Round(b.Left) - m;
    oy := Round(b.Top) - m;
    mw := Round(b.Right) - Round(b.Left) + 2 * m;
    mh := Round(b.Bottom) - Round(b.Top) + 2 * m;
  end;
  { the mask's own pixels are the device scale times these (MaskPainter) }
  if (mw <= 0) or (mh <= 0) or (mw * P.DeviceScale > 8192) or (mh * P.DeviceScale > 8192) then Exit;
  d := CaptionDrawOf(AElement, -ox, -oy);
  ol := nil;
  key := '';
  if HaloCacheOn then
  begin
    key := 'C' + IntToStr(P.PPI) + ',' + IntToStr(P.DeviceScale) + ',' + IntToStr(mw)
      + ',' + IntToStr(mh) + ',' + CaptionDrawKey(d);
    ol := HaloOutlineKept(key);
  end;
  if ol = nil then
  begin
    mp := MaskPainter(P, mw, mh, mask, owned);
    try
      PaintCaptionDraw(mp, d, TTyColor($FFFFFFFF));
      mp.EndPaint;
      ol := TraceMaskOutline(mask, mw * P.DeviceScale, mh * P.DeviceScale, P.DeviceScale);
    finally
      mp.Free;
      if owned then mask.Free;
    end;
    if key <> '' then KeepHaloOutline(key, ol);
  end;
  try
    StrokeMaskHalo(P, ol, ox, oy, AHalo, AElement.Caption.StrokeWidthLogical,
      AElement.Caption.StrokeType, AElement.Caption.StrokeDashOffset);
  finally
    if key = '' then ol.Free;
  end;
end;

procedure TyRenderCaption(P: TTyPainter; const AElement: TTyChartElement);
var
  ink, halo: TTyColor;
begin
  if (P = nil) or (AElement.Caption.Text = '') then Exit;
  { A BLOCK DRAWS ITS PIECES, and nothing of the one-run caption }
  if Length(AElement.Caption.RtPieces) > 0 then
  begin
    TyRenderRtPieces(P, AElement.Caption.RtPieces, AElement.Caption.X,
      AElement.Caption.Y, AElement.Caption.RotationRad, AElement.Caption.RtScale,
      AElement.Style.Alpha, True, TTyColor(AElement.Caption.Colour));
    Exit;
  end;
  ink := CaptionInk(AElement.Caption.Colour, AElement.Style.Alpha);
  { THE HALO FIRST, then the glyphs over it -- `paint-order: stroke`: a
    stroke w wide centred on the glyphs' outlines [F4c: it was the glyphs
    stamped at every whole-pixel offset within w/2]. It never widens the
    caption's box. }
  if (AElement.Caption.StrokeWidthLogical > 0)
    and ((AElement.Caption.StrokeColour shr 24) <> 0) then
  begin
    halo := CaptionInk(AElement.Caption.StrokeColour, AElement.Style.Alpha);
    HaloCaption(P, AElement, halo);
  end;
  DrawCaptionAt(P, AElement, ink, 0, 0);
end;

{ The caption's glyphs, in one ink, moved by (ADX, ADY) device px. }
procedure DrawCaptionAt(P: TTyPainter; const AElement: TTyChartElement;
  AInk: TTyColor; ADX, ADY: Integer);
begin
  PaintCaptionDraw(P, CaptionDrawOf(AElement, ADX, ADY), AInk);
end;

function CaptionDrawOf(const AElement: TTyChartElement; ADX, ADY: Integer): TCaptionDraw;
var
  b: TTyRectF;
begin
  Result := Default(TCaptionDraw);
  Result.Text := TyInkText(AElement.Caption.Text);
  Result.FontName := AElement.Caption.FontName;
  Result.Size := AElement.Caption.FontSizeLogical;
  Result.Weight := AElement.Caption.FontWeight;
  Result.H := TyAnchorToAlignment(AElement.Caption.AnchorH);
  Result.V := TyAnchorToLayout(AElement.Caption.AnchorV);
  if AElement.Caption.RotationRad <> 0 then
  begin
    { NO RECT, so no clip and no ellipsis -- the rotated entry takes an anchor.
      A truncating caption that is also rotated therefore overflows, and the
      caption record says so where it is declared rather than here. }
    Result.Kind := 0;
    Result.X := AElement.Caption.X + ADX;
    Result.Y := AElement.Caption.Y + ADY;
    Result.Rot := AElement.Caption.RotationRad;
    Exit;
  end;
  { THE SHAPE'S OWN RECT, not a box recomputed here. The label pass already put
    the caption's bounds in the companion's shape so that the hit test and the
    ink describe the same rectangle; recomputing would be a second answer to a
    question that already has one. }
  b := AElement.Shape.Bounds;
  Result.Truncate := AElement.Caption.Truncate;
  if TyRectFIsValid(b) then
  begin
    Result.Kind := 1;
    Result.R := Rect(Round(b.Left) + ADX, Round(b.Top) + ADY,
      Round(b.Right) + ADX, Round(b.Bottom) + ADY);
    Result.MultiLine := AElement.Caption.MultiLine;
  end
  else
  begin
    Result.Kind := 2;
    Result.R := CaptionBox(AElement.Caption, 0, 0);
    OffsetRect(Result.R, ADX, ADY);
    Result.MultiLine := False;
  end;
end;

procedure PaintCaptionDraw(P: TTyPainter; const AD: TCaptionDraw; AInk: TTyColor);
begin
  if AD.Kind = 0 then
    P.DrawTextRotated(AD.Text, AD.FontName, AD.Size, AD.Weight, AInk, AD.X, AD.Y,
      AD.Rot, AD.H, AD.V)
  else
    P.DrawText(AD.R, AD.Text, AD.FontName, AD.Size, AD.Weight, AInk, AD.H, AD.V,
      AD.Truncate, 0, False, AD.MultiLine);
end;

{ the sector an element's HasClipSector names, run forward as zrender's arc
  runs it from ClipSA to ClipEA in its direction }
function TyClipSectorShape(const AElement: TTyChartElement): TTyChartShape;
var st, en, t: Double;
begin
  Result := TyShapeSector(AElement.ClipCX, AElement.ClipCY, AElement.ClipR0,
    AElement.ClipR1, 0, 1);
  st := AElement.ClipSA;
  en := AElement.ClipEA;
  if AElement.ClipCW then
  begin
    if en - st >= 2 * Pi then en := st + 2 * Pi
    else if st > en then en := st + (2 * Pi - (st - en - Floor((st - en) / (2 * Pi)) * 2 * Pi));
  end
  else
  begin
    if st - en >= 2 * Pi then en := st - 2 * Pi
    else if st < en then en := st - (2 * Pi - (en - st - Floor((en - st) / (2 * Pi)) * 2 * Pi));
    t := st;
    st := en;
    en := t;
  end;
  Result.StartRad := st;
  Result.EndRad := en;
end;

procedure TyRenderElement(P: TTyPainter; const AElement: TTyChartElement);
var
  rule: TTyFillRule;
  gx1, gy1, gx2, gy2, gr: Double;
  stops: array of TTyGradStop;
  img: TBGRABitmap;
  pm: TTyDoubleArray;
  nw, nh, devW: Double;

  procedure PaintPen; forward;

  { the fill and the pen of the path just traced }
  procedure PaintTraced;
  var gi: Integer;
  begin
    if AElement.Style.FillEvenOdd then
      rule := tfrEvenOdd
    else
      rule := tfrNonZero;
    if AElement.Style.HasFill then
    begin
      if AElement.Style.FillGradient.Kind <> cgkNone then
      begin
        { THE ELEMENT'S OWN BOX, which is what upstream normalises against --
          not the plot and not the series. So every bar ramps over itself and
          a two-stop gradient reads the same on all of them, and a stacked
          segment restarts per segment. }
        TyResolveGradientXYWH(AElement.Style.FillGradient,
          TyElementGradientBox(AElement, P.PPI), gx1, gy1, gx2, gy2, gr);
        SetLength(stops, Length(AElement.Style.FillGradient.Stops));
        for gi := 0 to High(stops) do
        begin
          stops[gi].Color :=
            TTyColor(AElement.Style.FillGradient.Stops[gi].Color);
          stops[gi].Pos := AElement.Style.FillGradient.Stops[gi].Offset;
        end;
        P.FillPathGradient(stops, gx1, gy1, gx2, gy2, gr, rule);
      end
      else if AElement.Style.FillPattern.Present then
      begin
        { THE IMAGE, IN THE CANVAS'S SPACE: the pattern matrix in css px,
          scaled to the device. No image -- a URL, or one that does not
          decode -- fills nothing, which is upstream's `hasFill = false`
          while the image is not ready. [Batch 105] }
        { [F6a] the resolution for the device pixels the image covers: a
          unit image's box, else its natural size at this PPI }
        if AElement.Style.FillPattern.HasMatrix and AElement.Style.FillPattern.UnitImage then
          devW := Sqrt(Sqr(AElement.Style.FillPattern.Matrix[0])
            + Sqr(AElement.Style.FillPattern.Matrix[1])) * P.PPI / 96
        else if TyChartImageSize(AElement.Style.FillPattern.Image, nw, nh) then
          devW := nw * P.PPI / 96
        else
          devW := 0;
        { for the raster's pixels (#83); the matrix below maps whichever comes back }
        devW := devW * P.DeviceScale;
        img := TyChartImage(AElement.Style.FillPattern.Image, devW, nw, nh);
        if img <> nil then
        begin
          if AElement.Style.FillPattern.HasMatrix then
          begin
            { the element's own matrix [Batch 122]: a unit square divided by
              the image's size }
            SetLength(pm, 6);
            for gi := 0 to 5 do pm[gi] := AElement.Style.FillPattern.Matrix[gi];
            if AElement.Style.FillPattern.UnitImage then
            begin
              pm[0] := pm[0] / img.Width;
              pm[1] := pm[1] / img.Width;
              pm[2] := pm[2] / img.Height;
              pm[3] := pm[3] / img.Height;
            end;
          end
          else
          begin
            TyPatternMatrix(AElement.Style.FillPattern, pm);
            { a resolution other than the natural size: its pixels are
              smaller than css px by that much [F6a] }
            if (img.Width > 0) and (img.Height > 0) and (nw > 0) and (nh > 0) then
            begin
              pm[0] := pm[0] * nw / img.Width;
              pm[1] := pm[1] * nw / img.Width;
              pm[2] := pm[2] * nh / img.Height;
              pm[3] := pm[3] * nh / img.Height;
            end;
          end;
          for gi := 0 to 5 do pm[gi] := pm[gi] * P.PPI / 96;
          P.FillPathPattern(img, AElement.Style.FillPattern.Repetition, pm, rule);
        end;
      end
      else
        P.FillPath(TTyColor(AElement.Style.FillColor), rule);
    end;
    PaintPen;
  end;

  { the pen of the path just traced }
  procedure PaintPen;
  var gi: Integer;
  begin
    if AElement.Style.StrokeWidthLogical > 0 then
    begin
      if AElement.Style.StrokeGradient.Kind <> cgkNone then
      begin
        TyResolveGradientXYWH(AElement.Style.StrokeGradient,
          TyElementGradientBox(AElement, P.PPI), gx1, gy1, gx2, gy2, gr);
        SetLength(stops, Length(AElement.Style.StrokeGradient.Stops));
        for gi := 0 to High(stops) do
        begin
          stops[gi].Color :=
            TTyColor(AElement.Style.StrokeGradient.Stops[gi].Color);
          stops[gi].Pos := AElement.Style.StrokeGradient.Stops[gi].Offset;
        end;
        P.StrokePathGradient(stops, gx1, gy1, gx2, gy2, gr,
          AElement.Style.StrokeWidthLogical);
      end
      else
        P.StrokePath(TTyColor(AElement.Style.StrokeColor),
                     AElement.Style.StrokeWidthLogical);
    end;
  end;

  { ZRENDER'S DECAL ELEMENT [Batch 131]: a second path the same shape, its
    style the element's own with the fill swapped for the decal's pattern
    and no shadow, drawn right after the element -- so the pen goes on
    twice, once under the decal and once over it. Only where the element
    fills: `fill = style.fill ? style.decal : null`. }
  procedure PaintDecal;
  var tile: TBGRABitmap; di: Integer;
  begin
    if not (AElement.Style.Decal.Present and AElement.Style.HasFill) then Exit;
    { the fill rule here too: a large batch reaches this without PaintTraced }
    if AElement.Style.FillEvenOdd then rule := tfrEvenOdd else rule := tfrNonZero;
    { the tile made for the raster -- upstream's dpr: the PPI's and the device
      scale's (#83) -- and laid one tile pixel to one raster pixel: the matrix
      maps it to device px, so 1/S of them }
    tile := TyDecalTileImage(AElement.Style.Decal, P.PPI / 96 * P.DeviceScale);
    P.BeginPath;
    TyTraceShape(P, AElement.Shape);
    if tile <> nil then
    begin
      TyDecalMatrix(AElement.Style.Decal, P.PPI / 96, pm);
      for di := 0 to 3 do pm[di] := pm[di] / P.DeviceScale;
      P.FillPathPattern(tile, 'repeat', pm, rule);
    end;
    PaintPen;
  end;

  { no transform in force but the device scale's preset (#83): device px
    times the scale are the bitmap's own pixels }
  function IdentityMatrix: Boolean;
  var m: TAffineMatrix; s: Double;
  begin
    m := P.Bitmap.Canvas2D.matrix;
    s := P.DeviceScale;
    Result := (m[1, 1] = s) and (m[1, 2] = 0) and (m[1, 3] = 0)
      and (m[2, 1] = 0) and (m[2, 2] = s) and (m[2, 3] = 0);
  end;

  { A LARGE BATCH IS PAINTED IN TILES, not as one path. BGRA's scanline
    fill sorts every crossing of the path on every row it covers and builds
    its edge table from every point, so one path of a hundred thousand
    symbols costs far more than its pixels; a fill per symbol costs a call
    per symbol, and composites overlapping symbols twice. A tile is the
    bitmap's clip rect, which bounds the scan: each tile's path holds every
    row reaching into it, so every pixel is filled by exactly one fill
    holding every shape that covers it -- the union the single path would
    have painted, its alpha applied once. [Batch 117] }
  { A BATCH OF FLAT COLOURS goes through layers: every shape drawn opaque by
    BGRA's own antialiased primitives (an ellipse, a rect, a polygon, a line
    -- no path machinery, no edge table), then each layer laid on the bitmap
    once with the element's alpha, the fills' first and the pen's after, as
    the canvas fills the one path and then strokes it. The canvas composites
    the union of the shapes once; so does this -- overlapping symbols are not
    darkened twice the way an element per symbol would darken them. A ramp,
    a pattern or a dash goes the slower way, through the painter's path in
    tiles. [Batch 117] }
  function LayerFits: Boolean;
  begin
    Result := ((not AElement.Style.HasFill)
        or ((AElement.Style.FillGradient.Kind = cgkNone)
          and not AElement.Style.FillPattern.Present))
      and ((AElement.Style.StrokeWidthLogical <= 0)
        or (AElement.Style.StrokeGradient.Kind = cgkNone))
      and (Length(AElement.Style.DashLogical) = 0);
  end;

  { a lines row as layer points: its own, or its quadratic in 16 steps;
    AScl the layer's pixels per device px }
  function LinesRowPoints(const AG: TTyLargeGeom; ARow: Integer;
    AOX, AOY, AScl: Double): ArrayOfTPointF;
  var first, cnt, k: Integer; cx, cy, t, u: Double;
  begin
    Result := nil;
    if not LinesRow(AG, ARow, first, cnt) then Exit;
    if LinesCP(AG, first, cx, cy) then
    begin
      SetLength(Result, 17);
      for k := 0 to 16 do
      begin
        t := k / 16;
        u := 1 - t;
        Result[k] := PointF((u * u * AG.Pts[first] + 2 * u * t * cx + t * t * AG.Pts[first + 2]) * AScl - AOX,
          (u * u * AG.Pts[first + 1] + 2 * u * t * cy + t * t * AG.Pts[first + 3]) * AScl - AOY);
      end;
      Exit;
    end;
    SetLength(Result, cnt);
    for k := 0 to cnt - 1 do
      Result[k] := PointF(AG.Pts[first + k * 2] * AScl - AOX, AG.Pts[first + k * 2 + 1] * AScl - AOY);
  end;

  procedure PaintLargeOnLayer(AStroke: Boolean);
  var
    g: TTyLargeGeom;
    spec: TTySymbolSpec;
    bmp, layer: TBGRABitmap;
    n, i, j, op: Integer;
    x0, y0, x1, y1, bx0, by0, bx1, by1, ox, oy, w, h, r, pen, reach, s: Double;
    any: Boolean;
    area: TRect;
    c: TBGRAPixel;
    sub: TTyChartShape;
    pts: ArrayOfTPointF;

    { a row's polygon with BGRA's generator pinned (TyPinBgraRandom) }
    procedure PinnedPoly(AKind: Integer);
    var
      saved: LongWord;
    begin
      saved := TyPinBgraRandom;
      try
        case AKind of
          0: layer.DrawPolyLineAntialias(pts, c, pen);
          1: layer.DrawPolygonAntialias(pts, c, pen);
        else
          layer.FillPolyAntialias(pts, c);
        end;
      finally
        TyUnpinBgraRandom(saved);
      end;
    end;

  begin
    Inc(GLargeFastPaths);
    g := AElement.Shape.Large;
    spec := LargeSymbolSpec(g);
    bmp := P.Bitmap;
    n := LargeRowCount(g);
    { ON THE LAYER: its pixels are the device scale times device px (#83) --
      every coordinate, size and pen below is in them }
    s := P.DeviceScale;
    if AStroke then pen := AElement.Style.StrokeWidthLogical * P.PPI / 96 * s
    else pen := 0;
    reach := 2 + pen / 2;
    { the extent actually drawn, cut to the bitmap's clip and the element's }
    any := False;
    bx0 := 0; by0 := 0; bx1 := 0; by1 := 0;
    for i := 0 to n - 1 do
    begin
      if not LargeRowBox(g, i, x0, y0, x1, y1) then Continue;
      x0 := x0 * s; y0 := y0 * s; x1 := x1 * s; y1 := y1 * s;
      if not any then
      begin
        bx0 := x0; by0 := y0; bx1 := x1; by1 := y1;
        any := True;
      end
      else
      begin
        if x0 < bx0 then bx0 := x0;
        if y0 < by0 then by0 := y0;
        if x1 > bx1 then bx1 := x1;
        if y1 > by1 then by1 := y1;
      end;
    end;
    if not any then Exit;
    area := bmp.ClipRect;
    if AElement.HasClip then
      area := Rect(Max(area.Left, Floor(AElement.ClipRect.Left * s)),
        Max(area.Top, Floor(AElement.ClipRect.Top * s)),
        Min(area.Right, Ceil(AElement.ClipRect.Right * s)),
        Min(area.Bottom, Ceil(AElement.ClipRect.Bottom * s)));
    { the antialiased edge and half the pen; far off the bitmap is no matter }
    if bx0 - reach > area.Left then area.Left := Floor(bx0 - reach);
    if by0 - reach > area.Top then area.Top := Floor(by0 - reach);
    if bx1 + reach < area.Right then area.Right := Ceil(bx1 + reach);
    if by1 + reach < area.Bottom then area.Bottom := Ceil(by1 + reach);
    if (area.Right <= area.Left) or (area.Bottom <= area.Top) then Exit;
    if AStroke then c := TyColorToBGRA(TTyColor(AElement.Style.StrokeColor))
    else c := TyColorToBGRA(TTyColor(AElement.Style.FillColor));
    op := Round(Max(Double(0), Min(Double(1), AElement.Style.Alpha)) * c.alpha);
    if op <= 0 then Exit;
    c.alpha := 255;
    { pixel-centred primitives: the canvas' (0, 0) is a pixel's corner }
    ox := area.Left + 0.5;
    oy := area.Top + 0.5;
    layer := TBGRABitmap.Create(area.Right - area.Left, area.Bottom - area.Top,
      BGRAPixelTransparent);
    try
      layer.LineCap := pecFlat;
      for i := 0 to n - 1 do
      begin
        if not LargeRowBox(g, i, x0, y0, x1, y1) then Continue;
        x0 := x0 * s; y0 := y0 * s; x1 := x1 * s; y1 := y1 * s;
        if (x1 < area.Left - reach) or (x0 > area.Right + reach)
          or (y1 < area.Top - reach) or (y0 > area.Bottom + reach) then Continue;
        if g.Kind = lgkCandle then
        begin
          if AStroke then
            layer.DrawLineAntialias(x0 - ox, g.Pts[i * 4 + 2] * s - oy, x0 - ox,
              g.Pts[i * 4 + 3] * s - oy, c, pen, False);
          Continue;
        end;
        { a lines row: its polyline, a curve sampled [Batch 121] }
        if g.Kind = lgkLines then
        begin
          if AStroke then
          begin
            pts := LinesRowPoints(g, i, ox, oy, s);
            if Length(pts) >= 2 then PinnedPoly(0);
          end;
          Continue;
        end;
        if (g.Kind = lgkBar) or g.Boost or (TTySymbolKind(g.SymKind) = tsyRect) then
        begin
          if AStroke then layer.RectangleAntialias(x0 - ox, y0 - oy, x1 - ox, y1 - oy, c, pen)
          else layer.FillRectAntialias(x0 - ox, y0 - oy, x1 - ox, y1 - oy, c);
          Continue;
        end;
        w := g.SymW * s;
        h := g.SymH * s;
        case TTySymbolKind(g.SymKind) of
          tsyNone, tsyImage: ;
          tsyCircle:
            begin
              r := Min(w, h) / 2;
              if AStroke then
                layer.EllipseAntialias((x0 + x1) / 2 - ox, (y0 + y1) / 2 - oy, r, r, c, pen)
              else
                layer.FillEllipseAntialias((x0 + x1) / 2 - ox, (y0 + y1) / 2 - oy, r, r, c);
            end;
          tsySquare:
            begin
              r := Min(w, h);
              if AStroke then
                layer.RectangleAntialias(x0 - ox, y0 - oy, x0 + r - ox, y0 + r - oy, c, pen)
              else
                layer.FillRectAntialias(x0 - ox, y0 - oy, x0 + r - ox, y0 + r - oy, c);
            end;
          tsyRoundRect:
            begin
              r := Min(w, h) / 4;
              if AStroke then
                layer.RoundRectAntialias(x0 - ox, y0 - oy, x1 - ox, y1 - oy, r, r, c, pen)
              else
                layer.FillRoundRectAntialias(x0 - ox, y0 - oy, x1 - ox, y1 - oy, r, r, c);
            end;
        else
          begin
            { the symbol built in its device-px box, then onto the layer }
            sub := TyBuildSymbolInBox(spec, TyRectF(x0 / s, y0 / s, x1 / s, y1 / s));
            if (sub.Kind in [cskPolygon, cskPolyline]) and (Length(sub.Points) >= 2) then
            begin
              SetLength(pts, Length(sub.Points));
              for j := 0 to High(sub.Points) do
                pts[j] := PointF(sub.Points[j].X * s - ox, sub.Points[j].Y * s - oy);
              if AStroke then
              begin
                if sub.Kind = cskPolyline then PinnedPoly(0)
                else PinnedPoly(1);
              end
              else if sub.Kind = cskPolygon then
                PinnedPoly(2);
            end;
          end;
        end;
      end;
      bmp.PutImage(area.Left, area.Top, layer, dmDrawWithTransparency, op);
    finally
      layer.Free;
    end;
  end;

  procedure PaintLargeInTiles;
  var
    g: TTyLargeGeom;
    spec: TTySymbolSpec;
    bmp: TBGRABitmap;
    n, i, j, tx, ty, tx0, tx1, ty0, ty1, nx, ny, t, tile, k: Integer;
    x0, y0, x1, y1, margin, s: Double;
    counts, starts, rows: array of Integer;
    old, r: TRect;

    function Span(var A0, A1: Double; AExt: Integer; out AT0, AT1: Integer): Boolean;
    begin
      A0 := A0 - margin;
      A1 := A1 + margin;
      Result := (A1 >= 0) and (A0 < AExt);
      if not Result then Exit;
      if A0 < 0 then A0 := 0;
      if A1 > AExt - 1 then A1 := AExt - 1;
      AT0 := Trunc(A0) div tile;
      AT1 := Trunc(A1) div tile;
    end;

  begin
    Inc(GLargeFastPaths);
    g := AElement.Shape.Large;
    spec := LargeSymbolSpec(g);
    bmp := P.Bitmap;
    tile := TyLargeTilePx;
    n := LargeRowCount(g);
    if (n = 0) or (bmp.Width <= 0) or (bmp.Height <= 0) then Exit;
    nx := (bmp.Width + tile - 1) div tile;
    ny := (bmp.Height + tile - 1) div tile;
    { the tiles are the layer's pixels, the device scale times device px
      (#83); the antialiased edge and the pen reach past the shape }
    s := P.DeviceScale;
    margin := 2 + Max(Double(0), AElement.Style.StrokeWidthLogical) * P.PPI / 96 * s;
    SetLength(counts, nx * ny);
    SetLength(starts, nx * ny + 1);
    for t := 0 to nx * ny - 1 do counts[t] := 0;
    for k := 0 to 1 do
    begin
      if k = 1 then
      begin
        starts[0] := 0;
        for t := 0 to nx * ny - 1 do starts[t + 1] := starts[t] + counts[t];
        SetLength(rows, starts[nx * ny]);
        for t := 0 to nx * ny - 1 do counts[t] := starts[t];
      end;
      for i := 0 to n - 1 do
      begin
        if not LargeRowBox(g, i, x0, y0, x1, y1) then Continue;
        x0 := x0 * s; y0 := y0 * s; x1 := x1 * s; y1 := y1 * s;
        if not Span(x0, x1, bmp.Width, tx0, tx1) then Continue;
        if not Span(y0, y1, bmp.Height, ty0, ty1) then Continue;
        for ty := ty0 to ty1 do
          for tx := tx0 to tx1 do
          begin
            t := ty * nx + tx;
            if k = 1 then rows[counts[t]] := i;
            Inc(counts[t]);
          end;
      end;
    end;
    old := bmp.ClipRect;
    try
      for t := 0 to nx * ny - 1 do
      begin
        if starts[t + 1] = starts[t] then Continue;
        tx := t mod nx;
        ty := t div nx;
        r := Rect(Max(old.Left, tx * tile), Max(old.Top, ty * tile),
          Min(old.Right, (tx + 1) * tile), Min(old.Bottom, (ty + 1) * tile));
        if (r.Right <= r.Left) or (r.Bottom <= r.Top) then Continue;
        bmp.ClipRect := r;
        P.BeginPath;
        for j := starts[t] to starts[t + 1] - 1 do
          TraceLargeRow(P, g, spec, rows[j]);
        PaintTraced;
      end;
    finally
      bmp.ClipRect := old;
    end;
  end;

begin
  if P = nil then Exit;
  { [F6a] A PICTURE: the image in its corners, with the element's alpha and
    clip, and nothing else of the style -- zrender's Image draws no path
    (a symbol's colour never reaches it) }
  if AElement.Shape.Image <> '' then
  begin
    P.SaveState;
    try
      if AElement.HasClip then
        P.ClipRect(Rect(Floor(AElement.ClipRect.Left), Floor(AElement.ClipRect.Top),
          Ceil(AElement.ClipRect.Right), Ceil(AElement.ClipRect.Bottom)));
      if AElement.Style.Alpha < 1 then
        P.SetElementAlpha(AElement.Style.Alpha);
      PaintImageInto(P, AElement.Shape.Image, AElement.Shape.Points);
    finally
      P.RestoreState;
    end;
    TyRenderCaption(P, AElement);
    Exit;
  end;
  { Nothing to draw is not an error -- a placeholder element with neither fill
    nor stroke is a legitimate way to register a hit area with no ink. GLYPHS
    COUNT AS INK: a caption fills no path and strokes nothing, and without
    this it would be discarded one line before it was drawn. }
  if (not AElement.Style.HasFill) and (AElement.Style.StrokeWidthLogical <= 0)
    and (AElement.Caption.Text = '') then
    Exit;
  P.SaveState;
  try
    { THE CLIP FIRST, and inside the saved state so it comes off with it. The
      painter's own state stack carries the clip, which is the whole reason
      this costs one line: the alternative was a second stack here that had to
      stay in step with that one. }
    if AElement.HasClip then
    begin
      P.ClipRect(Rect(Floor(AElement.ClipRect.Left), Floor(AElement.ClipRect.Top),
        Ceil(AElement.ClipRect.Right), Ceil(AElement.ClipRect.Bottom)));
      { [F4c] a rounded clip: the rect's own path with its corners }
      if AElement.ClipRadius > 0 then
      begin
        P.BeginPath;
        TraceRtRect(P, AElement.ClipRect.Left, AElement.ClipRect.Top,
          AElement.ClipRect.Right - AElement.ClipRect.Left,
          AElement.ClipRect.Bottom - AElement.ClipRect.Top,
          [AElement.ClipRadius, AElement.ClipRadius, AElement.ClipRadius,
           AElement.ClipRadius]);
        P.ClipPath(tfrNonZero);
        P.BeginPath;
      end;
    end;
    { A POLAR LINE'S SECTOR, traced as zrender's arc takes it [Batch 113] }
    if AElement.HasClipSector then
    begin
      P.BeginPath;
      TyTraceShape(P, TyClipSectorShape(AElement));
      P.ClipPath(tfrNonZero);
      P.BeginPath;
    end;
    if AElement.Style.Alpha < 1 then
      P.SetElementAlpha(AElement.Style.Alpha);
    P.SetLineDash(AElement.Style.DashLogical, AElement.Style.DashOffsetLogical);
    if (AElement.Shape.Kind = cskLarge) and (P.Bitmap <> nil) and IdentityMatrix
      and LayerFits then
    begin
      if AElement.Style.HasFill then PaintLargeOnLayer(False);
      if AElement.Style.StrokeWidthLogical > 0 then PaintLargeOnLayer(True);
      { a large bar's decal over the whole batch, one path [F4a] }
      PaintDecal;
    end
    else if (AElement.Shape.Kind = cskLarge) and (TyLargeTilePx > 0) and (P.Bitmap <> nil)
      and IdentityMatrix then
    begin
      PaintLargeInTiles;
      PaintDecal;
    end
    else
    begin
      P.BeginPath;
      TyTraceShape(P, AElement.Shape);
      PaintTraced;
      PaintDecal;
    end;
  finally
    { Restore even if a trace raised: the canvas state is shared, and leaking a
      dash or an alpha onto the next element is the defect the state stack
      exists to prevent. }
    P.RestoreState;
  end;
  { AFTER RestoreState, and that is not tidiness. The painter writes text
    straight to the bitmap rather than through the Canvas2D state, so a caption
    drawn inside the block would ignore the alpha and the dash it appears to be
    inside. Drawing it out here makes the bypass visible instead of hidden. }
  TyRenderCaption(P, AElement);
end;

procedure TyRenderPaintList(P: TTyPainter; AList: TTyPaintList);
var
  i: Integer;
  pe: PTyChartElement;
begin
  if (P = nil) or (AList = nil) then Exit;
  { Paint order, back to front. The hit test walks the same order in reverse, so
    what the eye sees on top is what the pointer gets. By reference: drawing
    adds nothing to the list [P2]. }
  for i := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(AList.PaintOrder(i));
    if not pe^.Ignore and not pe^.ProgHidden and not pe^.GfxUnder then
      TyRenderElement(P, pe^);
  end;
end;

finalization
  FreeAndNil(GDecalCache);
  DropHaloOutlines;
  FreeAndNil(GHaloOutlines);
  FreeAndNil(GHaloMask);
  FreeAndNil(GTraceWork);

end.
