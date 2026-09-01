unit tyControls.SubPixel;
{$mode objfpc}{$H+}
{ Sub-pixel alignment for crisp thin strokes.

  THE PROBLEM. An antialiased 1 px line stroked at an integer coordinate is
  centred ON a pixel boundary, so it covers half of the row above and half of the
  row below: two rows at 50 % alpha, which reads as a soft grey smear rather than
  a line. Stroked at a half-integer it covers exactly one row at 100 %. Axis
  lines, grid lines, split lines, bar borders and table rules are all thin and
  all axis-aligned, so on a desktop chart this is the difference between crisp
  and fuzzy over most of the picture.

  THE RULE, which is zrender's (graphic/helper/subPixelOptimize.ts) and the
  standard canvas one: move the coordinate so that (coordinate + width/2) -- the
  stroke's OUTER EDGE -- lands on a whole pixel. An odd width therefore wants a
  half-integer centre and an even width wants an integer one.

  STANDALONE AND DEPENDENCY-FREE on purpose. It is arithmetic about how a
  rasteriser lands ink, not a chart concept and not an LCL concept, so it is
  usable both from the chart's pure geometry layer and from any control that
  draws a hairline.

  COORDINATES ARE DEVICE px. Snapping a logical coordinate would be meaningless:
  the pixel grid the ink lands on is the device one. }
interface
uses SysUtils, Math;

{ Snap one coordinate for a stroke of AWidthPx centred on it.

  ATowardsPositive picks which way to nudge when the coordinate has to move. Use
  True for a near edge (left/top) and False for a far edge (right/bottom): that
  biases both inward, so a snapped rect stays inside the rect it was asked for
  instead of creeping outward by half a pixel per side per frame.

  A width of 0 (or less) returns the coordinate untouched -- nothing is being
  stroked, so there is nothing to align. }
function TySubPixelSnap(APos, AWidthPx: Double;
  ATowardsPositive: Boolean = True): Double;

{ Snap a straight line. Only the axis the line is CONSTANT on is snapped: a
  vertical line's X, a horizontal line's Y. A diagonal is left alone, because
  moving either end of it would change its angle, and a diagonal is not the case
  that looks fuzzy anyway. }
procedure TySubPixelLine(var AX1, AY1, AX2, AY2: Double; AWidthPx: Double);

{ Snap all four edges of a rect, biasing inward. A rect that was not empty stays
  at least one device pixel wide and tall -- snapping a 0.4 px sliver to nothing
  would make it vanish, and a vanishing bar is worse than a slightly fat one. }
procedure TySubPixelRect(var ALeft, ATop, ARight, ABottom: Double; AWidthPx: Double);

implementation

function TySubPixelSnap(APos, AWidthPx: Double; ATowardsPositive: Boolean): Double;
var
  doubled, w: Int64;
begin
  if (AWidthPx <= 0) or IsNan(APos) or IsNan(AWidthPx) then
    Exit(APos);
  { Work in halves so the two cases -- odd width wants a half-integer, even width
    wants an integer -- collapse into one parity test. }
  doubled := Round(APos * 2);
  w := Round(AWidthPx);
  if ((doubled + w) mod 2) = 0 then
    Result := doubled / 2
  else if ATowardsPositive then
    Result := (doubled + 1) / 2
  else
    Result := (doubled - 1) / 2;
end;

procedure TySubPixelLine(var AX1, AY1, AX2, AY2: Double; AWidthPx: Double);
begin
  if AWidthPx <= 0 then Exit;
  { Compare in halves, matching the snap's own resolution: two coordinates that
    round to the same half-pixel are the same line as far as this is concerned. }
  if Round(AX1 * 2) = Round(AX2 * 2) then
  begin
    AX1 := TySubPixelSnap(AX1, AWidthPx, True);
    AX2 := AX1;
  end;
  if Round(AY1 * 2) = Round(AY2 * 2) then
  begin
    AY1 := TySubPixelSnap(AY1, AWidthPx, True);
    AY2 := AY1;
  end;
end;

procedure TySubPixelRect(var ALeft, ATop, ARight, ABottom: Double; AWidthPx: Double);
var
  w, h, l, t, r, b: Double;
begin
  if AWidthPx <= 0 then Exit;
  w := ARight - ALeft;
  h := ABottom - ATop;
  l := TySubPixelSnap(ALeft, AWidthPx, True);
  t := TySubPixelSnap(ATop, AWidthPx, True);
  r := TySubPixelSnap(ARight, AWidthPx, False);
  b := TySubPixelSnap(ABottom, AWidthPx, False);
  { Do not let a rect that had extent snap away to none... }
  if (w > 0) and (r - l < 1) then
    r := l + 1;
  if (h > 0) and (b - t < 1) then
    b := t + 1;
  { ...and do not let one that had NONE come back inverted. Snapping the two
    edges in opposite directions turns a zero-width rect into a -1 one, and an
    inverted rect survives a later Min/Max swap to reappear as a phantom band
    somewhere else -- the same trap TySolveBox and DataToLayout each collapse
    rather than invert for. Found by the test that asserted zero stays zero. }
  if w <= 0 then
    r := l;
  if h <= 0 then
    b := t;
  ALeft := l;
  ATop := t;
  ARight := r;
  ABottom := b;
end;

end.
