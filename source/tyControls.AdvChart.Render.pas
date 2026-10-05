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

{ THE BOX A LOCAL GRADIENT ON THIS ELEMENT NORMALISES AGAINST, device px at
  APPI: the builder's own when it set one, else the shape's bounds grown by
  the stroke -- upstream's getBoundingRect. [Batch 105] }
function TyElementGradientBox(const AElement: TTyChartElement;
  APPI: Integer): TTyXYWH;

{ A pattern's image: a `data:` URL with base64 content, decoded once and
  kept; nil for anything else or anything that does not decode. Owned by the
  cache. [Batch 105] }
function TyPatternImage(const ASource: string): TBGRABitmap;

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

uses base64;

var
  GPatternCache: TStringList = nil;

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

procedure TyTraceShape(P: TTyPainter; const AShape: TTyChartShape);
var
  i, n: Integer;
  pts: array of TTyVecPoint;
  ops: TTyPathOpArray;
begin
  if P = nil then Exit;
  case AShape.Kind of
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
  gi: Integer;
  stops: array of TTyGradStop;
  img: TBGRABitmap;
  pm: TTyDoubleArray;
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
    P.BeginPath;
    TyTraceShape(P, AElement.Shape);
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
          TyPatternMatrix(AElement.Style.FillPattern, pm);
          for gi := 0 to 5 do pm[gi] := pm[gi] * P.PPI / 96;
          P.FillPathPattern(img, AElement.Style.FillPattern.Repetition, pm, rule);
        end;
      end
      else
        P.FillPath(TTyColor(AElement.Style.FillColor), rule);
    end;
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
    if not AList.Element(AList.PaintOrder(i)).Ignore then
      TyRenderElement(P, AList.Element(AList.PaintOrder(i)));
end;

finalization
  FreeAndNil(GPatternCache);

end.
