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
begin
  if P = nil then Exit;
  case AShape.Kind of
    cskRect:
      P.RectPath(AShape.Bounds.Left, AShape.Bounds.Top,
                 AShape.Bounds.Right, AShape.Bounds.Bottom);
    cskRoundRect:
      { The shape carries DEVICE px while RoundRectPath takes LOGICAL. Unscale
        rather than reach past the painter, so one place owns the conversion. }
      P.RoundRectPath(AShape.Bounds.Left, AShape.Bounds.Top,
                      AShape.Bounds.Right, AShape.Bounds.Bottom,
                      AShape.RadiusPx / Max(P.ScaleF(1), 1e-9));
    cskCircle:
      P.CirclePath(AShape.CX, AShape.CY, AShape.R1);
    cskEllipse:
      P.EllipsePath(AShape.CX, AShape.CY, AShape.R0, AShape.R1);
    cskSector:
      begin
        { Outer arc forward, inner arc back, closed -- one contour, so a ring
          fills correctly under either rule and the hit test's own annulus test
          describes the same area. }
        P.MoveTo(AShape.CX + AShape.R1 * Cos(AShape.StartRad),
                 AShape.CY + AShape.R1 * Sin(AShape.StartRad));
        P.ArcTo(AShape.CX, AShape.CY, AShape.R1, AShape.StartRad, AShape.EndRad, False);
        if AShape.R0 > 0 then
        begin
          P.LineTo(AShape.CX + AShape.R0 * Cos(AShape.EndRad),
                   AShape.CY + AShape.R0 * Sin(AShape.EndRad));
          P.ArcTo(AShape.CX, AShape.CY, AShape.R0, AShape.EndRad, AShape.StartRad, True);
        end
        else
          P.LineTo(AShape.CX, AShape.CY);
        P.ClosePath;
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
      if TyRectFIsValid(AShape.Bounds) then
        P.SvgPathIn(AShape.PathData,
                    Rect(Round(AShape.Bounds.Left), Round(AShape.Bounds.Top),
                         Round(AShape.Bounds.Right), Round(AShape.Bounds.Bottom)))
      else
        P.SvgPath(AShape.PathData);
  end;
end;

procedure TyRenderElement(P: TTyPainter; const AElement: TTyChartElement);
var
  rule: TTyFillRule;
begin
  if P = nil then Exit;
  { Nothing to draw is not an error -- a placeholder element with neither fill
    nor stroke is a legitimate way to register a hit area with no ink. }
  if (not AElement.Style.HasFill) and (AElement.Style.StrokeWidthLogical <= 0) then
    Exit;
  P.SaveState;
  try
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
      P.FillPath(TTyColor(AElement.Style.FillColor), rule);
    if AElement.Style.StrokeWidthLogical > 0 then
      P.StrokePath(TTyColor(AElement.Style.StrokeColor),
                   AElement.Style.StrokeWidthLogical);
  finally
    { Restore even if a trace raised: the canvas state is shared, and leaking a
      dash or an alpha onto the next element is the defect the state stack
      exists to prevent. }
    P.RestoreState;
  end;
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
