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

{ THE BOX A LOCAL GRADIENT ON THIS ELEMENT NORMALISES AGAINST, device px at
  APPI: the builder's own when it set one, else the shape's bounds grown by
  the stroke -- upstream's getBoundingRect. [Batch 105] }
function TyElementGradientBox(const AElement: TTyChartElement;
  APPI: Integer): TTyXYWH;

{ A pattern's image: a `data:` URL with base64 content, decoded once and
  kept; nil for anything else or anything that does not decode. Owned by the
  cache. [Batch 105] }
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

{ the pattern matrix a decal's tile is repeated through, DEVICE px: the
  pattern's rotation and its 1 / dpr scale, carried to the device }
procedure TyDecalMatrix(const ADecal: TTyChartDecal; AScale: Double;
  out AM: TTyDoubleArray);

{ Draw the whole list in paint order. }
procedure TyRenderPaintList(P: TTyPainter; AList: TTyPaintList);

{ ZRENDER'S TEXT BLOCK, piece by piece in its paint order: each rect (its
  border first where it has both, as zrender doubles and underlays it) and
  each text, hung at (AX, AY), turned counter-clockwise by ARotationRad and
  scaled by AScale device px per piece px. AAlpha is the element's. A text
  whose fill came from the host's default and has none takes AInk where
  AHasInk -- a free text's skin ink. [Batch 86] }
procedure TyRenderRtPieces(P: TTyPainter; const APieces: TTyRtPieceArray;
  AX, AY, ARotationRad, AScale, AAlpha: Double; AHasInk: Boolean;
  AInk: TTyColor);

implementation

uses base64, BGRABitmapTypes, tyControls.AdvChart.Large, tyControls.AdvChart.Symbol,
  tyControls.AdvChart.Decal;

var
  GPatternCache: TStringList = nil;
  GDecalCache: TStringList = nil;

function TyDecalTileImage(const ADecal: TTyChartDecal; AScale: Double): TBGRABitmap;
var
  key: string;
  k, i, w, h: Integer;
  tile: TTyDecalTile;
  bmp: TBGRABitmap;
  P: TTyPainter;
  spec: TTySymbolSpec;
  sh: TTyChartShape;
  empty: Boolean;
  path: string;
  fw, fh: Double;
begin
  Result := nil;
  if not ADecal.Present then Exit;
  if GDecalCache = nil then
  begin
    GDecalCache := TStringList.Create;
    GDecalCache.OwnsObjects := True;
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
    P := TTyPainter.Create;
    try
      { no canvas: EndPaint leaves the bitmap where it is }
      P.BeginPaintOn(nil, Rect(0, 0, w, h), 96, bmp);
      for i := 0 to High(tile.Symbols) do
      begin
        { createSymbol at (x, y, w, h) times dpr, in the decal's colour }
        spec := TySymbolDefault('');
        spec.Kind := TySymbolKindOf(tile.Symbols[i].Kind, empty, path);
        spec.Empty := empty;
        spec.PathData := path;
        spec.KeepAspect := ADecal.KeepAspect;
        spec.RotateDeg := 0;
        spec.OffsetX := 0;
        spec.OffsetY := 0;
        sh := TyBuildSymbolInBox(spec, TyRectF(tile.Symbols[i].X * AScale,
          tile.Symbols[i].Y * AScale,
          (tile.Symbols[i].X + tile.Symbols[i].W) * AScale,
          (tile.Symbols[i].Y + tile.Symbols[i].H) * AScale));
        if (sh.Kind = cskRect) and not TyRectFIsValid(sh.Bounds) then Continue;
        P.BeginPath;
        TyTraceShape(P, sh);
        if spec.Kind = tsyLine then
          { the one symbol setColor strokes }
          P.StrokePath(TTyColor(ADecal.Color), 1)
        else if empty then
        begin
          { an empty symbol: white inside, the colour around it }
          P.FillPath(TTyColor($FFFFFFFF));
          P.StrokePath(TTyColor(ADecal.Color), 1);
        end
        else
          P.FillPath(TTyColor(ADecal.Color));
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
var
  k, comma: Integer;
  head, raw: string;
  ms: TStringStream;
  bmp: TBGRABitmap;
begin
  Result := nil;
  if Copy(ASource, 1, 5) <> 'data:' then Exit;
  if GPatternCache = nil then
  begin
    GPatternCache := TStringList.Create;
    GPatternCache.OwnsObjects := True;
    GPatternCache.Sorted := True;
    GPatternCache.CaseSensitive := True;
  end;
  if GPatternCache.Find(ASource, k) then
    Exit(TBGRABitmap(GPatternCache.Objects[k]));
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
  if GPatternCache.Count >= 64 then GPatternCache.Clear;
  GPatternCache.AddObject(ASource, bmp);
  Result := bmp;
end;

procedure TyPatternRegisterImage(const AKey: string; ABmp: TBGRABitmap);
var k: Integer;
begin
  if GPatternCache = nil then
  begin
    GPatternCache := TStringList.Create;
    GPatternCache.OwnsObjects := True;
    GPatternCache.Sorted := True;
    GPatternCache.CaseSensitive := True;
  end;
  if GPatternCache.Find(AKey, k) then
  begin
    ABmp.Free;
    Exit;
  end;
  if GPatternCache.Count >= 64 then GPatternCache.Clear;
  GPatternCache.AddObject(AKey, ABmp);
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
        else if ASpec.Kind <> tsyNone then
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

procedure DrawCaptionAt(P: TTyPainter; const AElement: TTyChartElement;
  AInk: TTyColor; ADX, ADY: Integer); forward;

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
      halo := CaptionInk(pc.Stroke, a);
      r := pc.LineWidth / 2 * P.PPI / 96;
      reach := Ceil(r);
      rr := r * r + r;
      for dy := -reach to reach do
        for dx := -reach to reach do
          if ((dx <> 0) or (dy <> 0)) and (dx * dx + dy * dy <= rr) then
            P.DrawTextRotated(TyInkText(pc.Text), pc.FontFamily,
              TyFontSizeFromPx(pc.FontSizePx), pc.FontWeight, halo,
              gx + dx, gy + dy, ARotationRad, RtAlign(pc.TextAlign), tlCenter);
    end;
    if not hasInk then Continue;
    s := a;
    P.DrawTextRotated(TyInkText(pc.Text), pc.FontFamily,
      TyFontSizeFromPx(pc.FontSizePx), pc.FontWeight, CaptionInk(ink, s),
      gx, gy, ARotationRad, RtAlign(pc.TextAlign), tlCenter);
  end;
end;

procedure TyRenderCaption(P: TTyPainter; const AElement: TTyChartElement);
var
  ink, halo: TTyColor;
  r, rr: Double;
  dx, dy, reach: Integer;
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
  { THE HALO FIRST, then the glyphs over it -- `paint-order: stroke`. A
    stroke w wide and centred on the outline shows w/2 outside the glyph, so
    the glyphs are stamped in the halo's colour at every whole-pixel offset
    within that reach: a dilation, which is what the stroke amounts to at
    these sizes. It never widens the caption's box. }
  if (AElement.Caption.StrokeWidthLogical > 0)
    and ((AElement.Caption.StrokeColour shr 24) <> 0) then
  begin
    halo := CaptionInk(AElement.Caption.StrokeColour, AElement.Style.Alpha);
    r := AElement.Caption.StrokeWidthLogical / 2 * P.PPI / 96;
    reach := Ceil(r);
    rr := r * r + r;
    for dy := -reach to reach do
      for dx := -reach to reach do
        if ((dx <> 0) or (dy <> 0)) and (dx * dx + dy * dy <= rr) then
          DrawCaptionAt(P, AElement, halo, dx, dy);
  end;
  DrawCaptionAt(P, AElement, ink, 0, 0);
end;

{ The caption's glyphs, in one ink, moved by (ADX, ADY) device px. }
procedure DrawCaptionAt(P: TTyPainter; const AElement: TTyChartElement;
  AInk: TTyColor; ADX, ADY: Integer);
var
  b: TTyRectF;
  ink: TTyColor;
  box: TRect;
begin
  ink := AInk;
  if AElement.Caption.RotationRad <> 0 then
  begin
    { NO RECT, so no clip and no ellipsis -- the rotated entry takes an anchor.
      A truncating caption that is also rotated therefore overflows, and the
      caption record says so where it is declared rather than here. }
    P.DrawTextRotated(TyInkText(AElement.Caption.Text), AElement.Caption.FontName,
      AElement.Caption.FontSizeLogical, AElement.Caption.FontWeight, ink,
      AElement.Caption.X + ADX, AElement.Caption.Y + ADY,
      AElement.Caption.RotationRad,
      TyAnchorToAlignment(AElement.Caption.AnchorH),
      TyAnchorToLayout(AElement.Caption.AnchorV));
    Exit;
  end;
  { THE SHAPE'S OWN RECT, not a box recomputed here. The label pass already put
    the caption's bounds in the companion's shape so that the hit test and the
    ink describe the same rectangle; recomputing would be a second answer to a
    question that already has one. }
  b := AElement.Shape.Bounds;
  if TyRectFIsValid(b) then
    P.DrawText(Rect(Round(b.Left) + ADX, Round(b.Top) + ADY,
      Round(b.Right) + ADX, Round(b.Bottom) + ADY),
      TyInkText(AElement.Caption.Text), AElement.Caption.FontName,
      AElement.Caption.FontSizeLogical, AElement.Caption.FontWeight, ink,
      TyAnchorToAlignment(AElement.Caption.AnchorH),
      TyAnchorToLayout(AElement.Caption.AnchorV),
      AElement.Caption.Truncate)
  else
  begin
    box := CaptionBox(AElement.Caption, 0, 0);
    OffsetRect(box, ADX, ADY);
    P.DrawText(box,
      TyInkText(AElement.Caption.Text), AElement.Caption.FontName,
      AElement.Caption.FontSizeLogical, AElement.Caption.FontWeight, ink,
      TyAnchorToAlignment(AElement.Caption.AnchorH),
      TyAnchorToLayout(AElement.Caption.AnchorV),
      AElement.Caption.Truncate);
  end;
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
        img := TyPatternImage(AElement.Style.FillPattern.Image);
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
            TyPatternMatrix(AElement.Style.FillPattern, pm);
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
  var tile: TBGRABitmap;
  begin
    if not (AElement.Style.Decal.Present and AElement.Style.HasFill) then Exit;
    tile := TyDecalTileImage(AElement.Style.Decal, P.PPI / 96);
    P.BeginPath;
    TyTraceShape(P, AElement.Shape);
    if tile <> nil then
    begin
      TyDecalMatrix(AElement.Style.Decal, P.PPI / 96, pm);
      P.FillPathPattern(tile, 'repeat', pm, rule);
    end;
    PaintPen;
  end;

  { the canvas draws in the bitmap's own pixels: no transform in force }
  function IdentityMatrix: Boolean;
  var m: TAffineMatrix;
  begin
    m := P.Bitmap.Canvas2D.matrix;
    Result := (m[1, 1] = 1) and (m[1, 2] = 0) and (m[1, 3] = 0)
      and (m[2, 1] = 0) and (m[2, 2] = 1) and (m[2, 3] = 0);
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

  { a lines row as layer points: its own, or its quadratic in 16 steps }
  function LinesRowPoints(const AG: TTyLargeGeom; ARow: Integer;
    AOX, AOY: Double): ArrayOfTPointF;
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
        Result[k] := PointF(u * u * AG.Pts[first] + 2 * u * t * cx + t * t * AG.Pts[first + 2] - AOX,
          u * u * AG.Pts[first + 1] + 2 * u * t * cy + t * t * AG.Pts[first + 3] - AOY);
      end;
      Exit;
    end;
    SetLength(Result, cnt);
    for k := 0 to cnt - 1 do
      Result[k] := PointF(AG.Pts[first + k * 2] - AOX, AG.Pts[first + k * 2 + 1] - AOY);
  end;

  procedure PaintLargeOnLayer(AStroke: Boolean);
  var
    g: TTyLargeGeom;
    spec: TTySymbolSpec;
    bmp, layer: TBGRABitmap;
    n, i, j, op: Integer;
    x0, y0, x1, y1, bx0, by0, bx1, by1, ox, oy, w, h, r, pen, reach: Double;
    any: Boolean;
    area: TRect;
    c: TBGRAPixel;
    sub: TTyChartShape;
    pts: ArrayOfTPointF;
  begin
    g := AElement.Shape.Large;
    spec := LargeSymbolSpec(g);
    bmp := P.Bitmap;
    n := LargeRowCount(g);
    if AStroke then pen := AElement.Style.StrokeWidthLogical * P.PPI / 96
    else pen := 0;
    reach := 2 + pen / 2;
    { the extent actually drawn, cut to the bitmap's clip and the element's }
    any := False;
    bx0 := 0; by0 := 0; bx1 := 0; by1 := 0;
    for i := 0 to n - 1 do
    begin
      if not LargeRowBox(g, i, x0, y0, x1, y1) then Continue;
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
      area := Rect(Max(area.Left, Floor(AElement.ClipRect.Left)),
        Max(area.Top, Floor(AElement.ClipRect.Top)),
        Min(area.Right, Ceil(AElement.ClipRect.Right)),
        Min(area.Bottom, Ceil(AElement.ClipRect.Bottom)));
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
        if (x1 < area.Left - reach) or (x0 > area.Right + reach)
          or (y1 < area.Top - reach) or (y0 > area.Bottom + reach) then Continue;
        if g.Kind = lgkCandle then
        begin
          if AStroke then
            layer.DrawLineAntialias(x0 - ox, g.Pts[i * 4 + 2] - oy, x0 - ox,
              g.Pts[i * 4 + 3] - oy, c, pen, False);
          Continue;
        end;
        { a lines row: its polyline, a curve sampled [Batch 121] }
        if g.Kind = lgkLines then
        begin
          if AStroke then
          begin
            pts := LinesRowPoints(g, i, ox, oy);
            if Length(pts) >= 2 then layer.DrawPolyLineAntialias(pts, c, pen);
          end;
          Continue;
        end;
        if (g.Kind = lgkBar) or g.Boost or (TTySymbolKind(g.SymKind) = tsyRect) then
        begin
          if AStroke then layer.RectangleAntialias(x0 - ox, y0 - oy, x1 - ox, y1 - oy, c, pen)
          else layer.FillRectAntialias(x0 - ox, y0 - oy, x1 - ox, y1 - oy, c);
          Continue;
        end;
        w := g.SymW;
        h := g.SymH;
        case TTySymbolKind(g.SymKind) of
          tsyNone: ;
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
            sub := TyBuildSymbolInBox(spec, TyRectF(x0, y0, x1, y1));
            if (sub.Kind in [cskPolygon, cskPolyline]) and (Length(sub.Points) >= 2) then
            begin
              SetLength(pts, Length(sub.Points));
              for j := 0 to High(sub.Points) do
                pts[j] := PointF(sub.Points[j].X - ox, sub.Points[j].Y - oy);
              if AStroke then
              begin
                if sub.Kind = cskPolyline then layer.DrawPolyLineAntialias(pts, c, pen)
                else layer.DrawPolygonAntialias(pts, c, pen);
              end
              else if sub.Kind = cskPolygon then
                layer.FillPolyAntialias(pts, c);
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
    x0, y0, x1, y1, margin: Double;
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
    g := AElement.Shape.Large;
    spec := LargeSymbolSpec(g);
    bmp := P.Bitmap;
    tile := TyLargeTilePx;
    n := LargeRowCount(g);
    if (n = 0) or (bmp.Width <= 0) or (bmp.Height <= 0) then Exit;
    nx := (bmp.Width + tile - 1) div tile;
    ny := (bmp.Height + tile - 1) div tile;
    { the antialiased edge and the pen reach past the shape }
    margin := 2 + Max(Double(0), AElement.Style.StrokeWidthLogical) * P.PPI / 96;
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
      P.ClipRect(Rect(Floor(AElement.ClipRect.Left), Floor(AElement.ClipRect.Top),
        Ceil(AElement.ClipRect.Right), Ceil(AElement.ClipRect.Bottom)));
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
    P.SetLineDash(AElement.Style.DashLogical);
    if (AElement.Shape.Kind = cskLarge) and (P.Bitmap <> nil) and IdentityMatrix
      and LayerFits then
    begin
      if AElement.Style.HasFill then PaintLargeOnLayer(False);
      if AElement.Style.StrokeWidthLogical > 0 then PaintLargeOnLayer(True);
    end
    else if (AElement.Shape.Kind = cskLarge) and (TyLargeTilePx > 0) and (P.Bitmap <> nil)
      and IdentityMatrix then
      PaintLargeInTiles
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
begin
  if (P = nil) or (AList = nil) then Exit;
  { Paint order, back to front. The hit test walks the same order in reverse, so
    what the eye sees on top is what the pointer gets. }
  for i := 0 to AList.Count - 1 do
    if not AList.Element(AList.PaintOrder(i)).Ignore
      and not AList.Element(AList.PaintOrder(i)).ProgHidden
      and not AList.Element(AList.PaintOrder(i)).GfxUnder then
      TyRenderElement(P, AList.Element(AList.PaintOrder(i)));
end;

finalization
  FreeAndNil(GPatternCache);
  FreeAndNil(GDecalCache);

end.
