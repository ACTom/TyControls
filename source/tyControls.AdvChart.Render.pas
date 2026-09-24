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
  SysUtils, Math, Types,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
  tyControls.Types,     // TTyColor: the render side speaks the library's colour type
  tyControls.AdvChart.Measure,  // the anchor-to-LCL-alignment converters
  tyControls.Painter;

{ Trace one shape into the painter's current path. Does NOT begin the path: a
  caller composing a ring from two contours needs to add both before filling. }
procedure TyTraceShape(P: TTyPainter; const AShape: TTyChartShape);

{ Draw one element: its shape, filled and/or stroked per its style. }
procedure TyRenderElement(P: TTyPainter; const AElement: TTyChartElement);

{ Draw the whole list in paint order. }
procedure TyRenderPaintList(P: TTyPainter; AList: TTyPaintList);

implementation

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

procedure TyRenderCaption(P: TTyPainter; const AElement: TTyChartElement);
var
  ink, halo: TTyColor;
  r, rr: Double;
  dx, dy, reach: Integer;
begin
  if (P = nil) or (AElement.Caption.Text = '') then Exit;
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

procedure TyRenderElement(P: TTyPainter; const AElement: TTyChartElement);
var
  rule: TTyFillRule;
  gx1, gy1, gx2, gy2, gr: Double;
  gi: Integer;
  stops: array of TTyGradStop;
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
        TyResolveGradient(AElement.Style.FillGradient,
          TyShapeBounds(AElement.Shape), gx1, gy1, gx2, gy2, gr);
        SetLength(stops, Length(AElement.Style.FillGradient.Stops));
        for gi := 0 to High(stops) do
        begin
          stops[gi].Color :=
            TTyColor(AElement.Style.FillGradient.Stops[gi].Color);
          stops[gi].Pos := AElement.Style.FillGradient.Stops[gi].Offset;
        end;
        P.FillPathGradient(stops, gx1, gy1, gx2, gy2, gr, rule);
      end
      else
        P.FillPath(TTyColor(AElement.Style.FillColor), rule);
    end;
    if AElement.Style.StrokeWidthLogical > 0 then
    begin
      if AElement.Style.StrokeGradient.Kind <> cgkNone then
      begin
        TyResolveGradient(AElement.Style.StrokeGradient,
          TyShapeBounds(AElement.Shape), gx1, gy1, gx2, gy2, gr);
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
    TyRenderElement(P, AList.Element(AList.PaintOrder(i)));
end;

end.
