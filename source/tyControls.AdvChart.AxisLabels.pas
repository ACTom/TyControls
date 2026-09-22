unit tyControls.AdvChart.AxisLabels;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- WHICH of an axis' labels are drawn.

  UPSTREAM'S RULES, transcribed operation for operation:

  - A CATEGORY AXIS builds every interval-th label and its two ends. The
    interval is the author's, or measured: the widest sampled label, grown by
    1.3 and never under 7 px, over the band width turned into the label's
    frame -- the floor of the smaller of the two ratios (calculateCategory-
    Interval). The stride is aligned from category nought, so a window that
    starts part-way keeps the labels it had.
  - A VALUE, LOG OR TIME AXIS builds a label per tick and never drops one for
    its index.
  - THE ENDS (fixMinMaxLabelShow): an end off the interval, or a time axis'
    ragged end, is dropped; an end that crowds its neighbour gives way --
    unless showMinLabel / showMaxLabel says to keep it, when the neighbour
    does. Not asked at all on a category axis written `interval: 0`.
  - hideOverlap, when asked for: every label that crowds one already kept is
    dropped, the coarser time ticks and the ones kept last time first.

  CROWDING IS zrender's: two boxes each shrunk by a threshold on every side
  overlap, and when either is turned off the axes the two oriented boxes are
  then held to the separating-axis test, quirks and all.

  PURE: the caller measures and places; this unit only decides. }
interface
uses Math, tyControls.AdvChart.Types, tyControls.AdvChart.Layout;

type
  { One label's box as zrender holds it: in its own frame, the matrix that
    places it, the axis-aligned rect round the result. }
  TTyLabelBox = record
    LocalRect: TTyXYWH;
    M: TTyMat2D;
    Rect: TTyXYWH;
    AxisAligned: Boolean;
  end;

  { One BUILT label, as the end rules and hideOverlap weigh it. }
  TTyLabelCandidate = record
    { which of the spec's labels }
    Index: Integer;
    { with axisLabel.textMargin round it, and without }
    Margin, Bare: TTyLabelBox;
    { a box was made: the end rules only ever need the outer two }
    HasBox: Boolean;
    OffInterval, NotNice, SuggestIgnore: Boolean;
    Priority: Integer;
    { the answer }
    Ignore: Boolean;
  end;
  TTyLabelCandidateArray = array of TTyLabelCandidate;

{ Axis.dataToCoord(e0 + 1) - dataToCoord(e0) on a pixel extent [0, ALen]
  (turned round when inverse), band-inset when AOnBand, through upstream's
  own fixExtentWithBands and linearMap. }
function TyCategoryUnitSpan(ALen: Double; ACount: Integer;
  AOnBand, AInverse: Boolean): Double;

{ Every how many labels the auto interval measures: all of them up to forty. }
function TyCategorySampleStep(ACount: Integer): Integer;

{ calculateCategoryInterval from the sampled labels' text sizes -- width of
  the widest line, height of one line -- the band width, the axis' turn (0
  for x, 90 for y) and the label's (axisLabel.rotate as written), and the
  7 px floor in device px. +Infinity when the band has no length. }
function TyCategoryAutoInterval(const AWidths, AHeights: array of Double;
  AUnitSpan, AAxisRotateDeg, ALabelRotateDeg, AMinSize: Double): Double;

{ ordinalScaleCreateTicks: the categories a label is built for, from the
  axis' first category AStart over ACount of them, and which of them are the
  two ends the interval did not land on. }
procedure TyCategoryBuiltList(AStart, ACount: Integer; AInterval: Double;
  out AValues: TTyIntegerArray; out AOffInterval: TTyBoolArray);

{ zrender's oriented-box test, boolean, with a touch threshold. }
function TyObbIntersect(const A, B: TTyLabelBox; AThreshold: Double): Boolean;

{ labelIntersect without the ignore check: the rects, then the oriented
  boxes when either is turned off the axes. }
function TyLabelBoxesIntersect(const A, B: TTyLabelBox;
  AThreshold: Double): Boolean;

{ fixMinMaxLabelShow over the built list, in value order. AShowAll is a
  category axis' `interval: 0`. }
procedure TyFixMinMaxLabelShow(var ACands: TTyLabelCandidateArray;
  AKind: TTyLabelAxisKind; AShowAll: Boolean; AShowMin, AShowMax: TTyAxisEndLabel;
  AHideOverlap: Boolean);

{ hideOverlap over the built labels still shown. }
procedure TyHideOverlap(var ACands: TTyLabelCandidateArray);

{ fixOnBandTicksCoords, on marks whose Coord is in the axis' OWN frame --
  from its start, the way its extent runs: every mark back half a band onto
  the leading edge, the last dropped if it is off the interval, and the edge
  past the last category added -- the last mark's, one band on. The marks are
  flagged OnBand. Nothing happens off a band, aligned with the labels, with
  no marks, or with no band width. }
procedure TyFixOnBandMarks(var AMarks: TTyAxisMarkArray; AOnBand,
  AAlignWithLabel: Boolean; ABandWidth: Double; ALastCategory: Integer);

implementation

uses tyControls.AdvChart.JsMath;

function FromBits(AQ: QWord): Double;
begin
  Move(AQ, Result, SizeOf(Result));
end;

var
  { 1.3, the magic number, as a bit pattern }
  cMagic: Double;

function TyCategoryUnitSpan(ALen: Double; ACount: Integer;
  AOnBand, AInverse: Boolean): Double;
var
  r0, r1, size, margin, v, subRange, c0, c1: Double;
begin
  if AInverse then
  begin
    r0 := ALen;
    r1 := 0;
  end
  else
  begin
    r0 := 0;
    r1 := ALen;
  end;
  if AOnBand then
  begin
    { fixExtentWithBands }
    size := r1 - r0;
    margin := size / ACount / 2;
    r0 := r0 + margin;
    r1 := r1 - margin;
  end;
  { normalize(e0 + 1) on [e0, e1], and linearMap over [0, 1] }
  if ACount - 1 = 0 then v := 0.5
  else v := 1 / (ACount - 1);
  subRange := r1 - r0;
  if v = 0 then c1 := r0
  else if v = 1 then c1 := r1
  else c1 := (v - 0) / 1 * subRange + r0;
  c0 := r0;
  Result := c1 - c0;
end;

function TyCategorySampleStep(ACount: Integer): Integer;
begin
  Result := 1;
  if ACount > 40 then Result := Max(1, ACount div 40);
end;

function TyCategoryAutoInterval(const AWidths, AHeights: array of Double;
  AUnitSpan, AAxisRotateDeg, ALabelRotateDeg, AMinSize: Double): Double;
var
  rotation, unitW, unitH, maxW, maxH, dw, dh, m: Double;
  i: Integer;
begin
  rotation := (AAxisRotateDeg - ALabelRotateDeg) / 180 * Pi;
  unitW := Abs(AUnitSpan * TyJsCos(rotation));
  unitH := Abs(AUnitSpan * TyJsSin(rotation));
  maxW := 0;
  maxH := 0;
  for i := 0 to High(AWidths) do
  begin
    { Math.max(maxW, width, 7) }
    maxW := Max(Max(maxW, AWidths[i] * cMagic), AMinSize);
    maxH := Max(Max(maxH, AHeights[i] * cMagic), AMinSize);
  end;
  { 0/0 is NaN and 1/0 Infinity, both Infinity here; the sizes are never
    nought, so only the second can happen }
  if unitW = 0 then dw := Infinity else dw := maxW / unitW;
  if unitH = 0 then dh := Infinity else dh := maxH / unitH;
  if IsNan(dw) then dw := Infinity;
  if IsNan(dh) then dh := Infinity;
  m := Min(dw, dh);
  if IsInfinite(m) then Exit(Infinity);
  { Math.floor; never negative here }
  Result := Max(Double(0), Int(m));
end;

procedure TyCategoryBuiltList(AStart, ACount: Integer; AInterval: Double;
  out AValues: TTyIntegerArray; out AOffInterval: TTyBoolArray);
var
  e0, e1, step, start, t: Double;
  n: Integer;

  procedure Add(AValue: Double; AOff: Boolean);
  begin
    SetLength(AValues, n + 1);
    SetLength(AOffInterval, n + 1);
    AValues[n] := Round(AValue);
    AOffInterval[n] := AOff;
    Inc(n);
  end;

begin
  AValues := nil;
  AOffInterval := nil;
  n := 0;
  if ACount <= 0 then Exit;
  e0 := AStart;
  e1 := AStart + ACount - 1;
  { Math.max((interval || 0) + 1, 1) }
  if IsNan(AInterval) then AInterval := 0;
  step := Max(AInterval + 1, Double(1));
  start := e0;
  { FROM NOUGHT, so that a window that starts part-way keeps its labels }
  if (start <> 0) and (step > 1) and (ACount / step > 2) then
    start := Floor(Ceil(start / step) * step + 0.5);
  if start <> e0 then Add(e0, True);
  t := start;
  while t <= e1 do
  begin
    Add(t, False);
    t := t + step;
  end;
  { `tickValue - step !== extent[1]`: Infinity less Infinity is NaN, never
    the end }
  if IsInfinite(step) or (t - step <> e1) then Add(e1, True);
end;

{ ==================== oriented boxes ==================== }

type
  TObb = record
    CX, CY: array[0..3] of Double;
    AX, AY: array[0..1] of Double;
    Origin: array[0..1] of Double;
  end;

function MakeObb(const ABox: TTyLabelBox): TObb;
var
  x, y, x2, y2, px, py, len: Double;
  i: Integer;
  m: TTyMat2D;
begin
  m := ABox.M;
  x := ABox.LocalRect.X;
  y := ABox.LocalRect.Y;
  x2 := x + ABox.LocalRect.W;
  y2 := y + ABox.LocalRect.H;
  Result.CX[0] := x;  Result.CY[0] := y;
  Result.CX[1] := x2; Result.CY[1] := y;
  Result.CX[2] := x2; Result.CY[2] := y2;
  Result.CX[3] := x;  Result.CY[3] := y2;
  for i := 0 to 3 do
  begin
    { Point.transform }
    px := Result.CX[i];
    py := Result.CY[i];
    Result.CX[i] := m[0] * px + m[2] * py + m[4];
    Result.CY[i] := m[1] * px + m[3] * py + m[5];
  end;
  { the two edge directions, normalised }
  Result.AX[0] := Result.CX[1] - Result.CX[0];
  Result.AY[0] := Result.CY[1] - Result.CY[0];
  Result.AX[1] := Result.CX[3] - Result.CX[0];
  Result.AY[1] := Result.CY[3] - Result.CY[0];
  for i := 0 to 1 do
  begin
    len := Sqrt(Result.AX[i] * Result.AX[i] + Result.AY[i] * Result.AY[i]);
    Result.AX[i] := Result.AX[i] / len;
    Result.AY[i] := Result.AY[i] / len;
  end;
  for i := 0 to 1 do
    Result.Origin[i] := Result.AX[i] * Result.CX[0] + Result.AY[i] * Result.CY[0];
end;

{ _getProjMinMaxOnAxis: the corners onto the SELF box' axis ADim, shifted by
  its origin, pulled in by the threshold; and whether that left nothing }
procedure Project(const ASelf, ACorners: TObb; ADim: Integer;
  AThreshold: Double; out ALo, AHi: Double; out ANegative: Boolean);
var
  proj, mn, mx: Double;
  k: Integer;
begin
  proj := ACorners.CX[0] * ASelf.AX[ADim] + ACorners.CY[0] * ASelf.AY[ADim]
    + ASelf.Origin[ADim];
  mn := proj;
  mx := proj;
  for k := 1 to 3 do
  begin
    proj := ACorners.CX[k] * ASelf.AX[ADim] + ACorners.CY[k] * ASelf.AY[ADim]
      + ASelf.Origin[ADim];
    mn := Min(proj, mn);
    mx := Max(proj, mx);
  end;
  ALo := mn + AThreshold;
  AHi := mx - AThreshold;
  ANegative := AHi < ALo;
end;

{ _intersectCheckOneSide, without a translation. THE EMPTINESS TESTED IS THE
  OTHER BOX' -- the flag is left by the second projection -- which is
  zrender's, and copied. }
function CheckOneSide(const ASelf, AOther: TObb; AThreshold: Double): Boolean;
var
  i: Integer;
  lo1, hi1, lo2, hi2: Double;
  neg: Boolean;
begin
  for i := 0 to 1 do
  begin
    Project(ASelf, ASelf, i, AThreshold, lo1, hi1, neg);
    Project(ASelf, AOther, i, AThreshold, lo2, hi2, neg);
    if neg or (hi1 < lo2) or (lo1 > hi2) then Exit(False);
  end;
  Result := True;
end;

function TyObbIntersect(const A, B: TTyLabelBox; AThreshold: Double): Boolean;
var oa, ob: TObb;
begin
  oa := MakeObb(A);
  ob := MakeObb(B);
  Result := CheckOneSide(oa, ob, AThreshold) and CheckOneSide(ob, oa, AThreshold);
end;

function TyLabelBoxesIntersect(const A, B: TTyLabelBox;
  AThreshold: Double): Boolean;
var
  t, ax0, ax1, ay0, ay1, bx0, bx1, by0, by1: Double;
begin
  { BoundingRect.intersect with no translation }
  t := Max(Double(0), AThreshold);
  ax0 := A.Rect.X + t;
  ax1 := A.Rect.X + A.Rect.W - t;
  ay0 := A.Rect.Y + t;
  ay1 := A.Rect.Y + A.Rect.H - t;
  bx0 := B.Rect.X + t;
  bx1 := B.Rect.X + B.Rect.W - t;
  by0 := B.Rect.Y + t;
  by1 := B.Rect.Y + B.Rect.H - t;
  if (ax0 > ax1) or (ay0 > ay1) or (bx0 > bx1) or (by0 > by1) then Exit(False);
  if (ax1 < bx0) or (bx1 < ax0) or (ay1 < by0) or (by1 < ay0) then Exit(False);
  if A.AxisAligned and B.AxisAligned then Exit(True);
  Result := TyObbIntersect(A, B, t);
end;

{ ==================== the ends ==================== }

procedure TyFixMinMaxLabelShow(var ACands: TTyLabelCandidateArray;
  AKind: TTyLabelAxisKind; AShowAll: Boolean; AShowMin, AShowMax: TTyAxisEndLabel;
  AHideOverlap: Boolean);
const
  cTouch = 0.1;

  procedure Deal(AOpt: TTyAxisEndLabel; AOut, AIn: Integer);
  var hit: Boolean;
  begin
    if (AOut < 0) or (AIn < 0) or (AOut > High(ACands)) or (AIn > High(ACands)) then
      Exit;
    if AOpt = aelAuto then
    begin
      { a time axis' ragged end, or a category axis' end off the interval }
      if ((AKind = lakTime) and ACands[AOut].NotNice)
        or ((AKind = lakCategory) and ACands[AOut].OffInterval) then
      begin
        ACands[AOut].Ignore := True;
        Exit;
      end;
    end;
    if (AOpt = aelHide) or ACands[AOut].SuggestIgnore then
    begin
      ACands[AOut].Ignore := True;
      Exit;
    end;
    if ACands[AIn].SuggestIgnore then
    begin
      ACands[AIn].Ignore := True;
      Exit;
    end;
    { an ignored label meets nothing }
    if ACands[AOut].Ignore or ACands[AIn].Ignore then Exit;
    { WITHOUT hideOverlap THE MARGINS ARE LEFT OFF: an author who did not ask
      for overlaps to be resolved has accepted labels that touch }
    if AHideOverlap then
      hit := TyLabelBoxesIntersect(ACands[AOut].Margin, ACands[AIn].Margin, cTouch)
    else
      hit := TyLabelBoxesIntersect(ACands[AOut].Bare, ACands[AIn].Bare, cTouch);
    if hit then
    begin
      if AOpt = aelShow then ACands[AIn].Ignore := True
      else ACands[AOut].Ignore := True;
    end;
  end;

var n: Integer;
begin
  if AShowAll then Exit;
  n := Length(ACands);
  Deal(AShowMin, 0, 1);
  Deal(AShowMax, n - 1, n - 2);
end;

procedure TyHideOverlap(var ACands: TTyLabelCandidateArray);
const
  cTouch = 0.05;
var
  order, kept: array of Integer;
  i, j, k, n, nk: Integer;
  overlapped: Boolean;

  { the sort: ones kept last time first, then the higher priority }
  function Before(A, B: Integer): Boolean;
  begin
    if ACands[A].SuggestIgnore <> ACands[B].SuggestIgnore then
      Exit(ACands[A].SuggestIgnore);
    Result := ACands[A].Priority > ACands[B].Priority;
  end;

begin
  { the ones still shown, in value order }
  n := 0;
  SetLength(order, Length(ACands));
  for i := 0 to High(ACands) do
    if not ACands[i].Ignore then
    begin
      order[n] := i;
      Inc(n);
    end;
  SetLength(order, n);
  { stable, as V8's sort is }
  for i := 1 to n - 1 do
  begin
    k := order[i];
    j := i - 1;
    while (j >= 0) and Before(k, order[j]) do
    begin
      order[j + 1] := order[j];
      Dec(j);
    end;
    order[j + 1] := k;
  end;
  SetLength(kept, n);
  nk := 0;
  for i := 0 to n - 1 do
  begin
    k := order[i];
    if ACands[k].Ignore then Continue;
    overlapped := False;
    for j := 0 to nk - 1 do
      if TyLabelBoxesIntersect(ACands[k].Margin, ACands[kept[j]].Margin, cTouch) then
      begin
        overlapped := True;
        Break;
      end;
    if overlapped then ACands[k].Ignore := True
    else
    begin
      kept[nk] := k;
      Inc(nk);
    end;
  end;
end;

procedure TyFixOnBandMarks(var AMarks: TTyAxisMarkArray; AOnBand,
  AAlignWithLabel: Boolean; ABandWidth: Double; ALastCategory: Integer);
var
  i, n: Integer;
  oldLast: TTyAxisMark;
begin
  n := Length(AMarks);
  if (not AOnBand) or AAlignWithLabel or (n = 0) then Exit;
  if (ABandWidth = 0) or IsNan(ABandWidth) then Exit;
  for i := 0 to n - 1 do
    AMarks[i].Coord := AMarks[i].Coord - ABandWidth / 2;
  oldLast := AMarks[n - 1];
  if oldLast.OffInterval then
  begin
    SetLength(AMarks, n - 1);
    Dec(n);
  end;
  SetLength(AMarks, n + 1);
  AMarks[n] := Default(TTyAxisMark);
  AMarks[n].Value := ALastCategory + 1;
  AMarks[n].Coord := oldLast.Coord + ABandWidth;
  for i := 0 to n do
    AMarks[i].OnBand := True;
end;

initialization
  cMagic := FromBits(QWord($3FF4CCCCCCCCCCCD));
end.
