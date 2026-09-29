unit tyControls.AdvChart.LinePath;
{$mode objfpc}{$H+}
{ A line series' path as upstream builds it: ECPolyline's and ECPolygon's
  buildPath over the series' points, through poly.ts's drawSegment -- the
  smoothed curve (smooth, smoothMonotone), a run broken or bridged at a null
  (connectNulls), the points it drops (a segment under 0.7 px from the last
  one drawn), and the area's base walked backwards under the line. And
  turnPointsIntoStep, which feeds it the stepped points. [Batch 63.]

  THE POINTS ARE FLOAT32 AND THE CONTROL POINTS ARE NOT: upstream stores the
  layout in a Float32Array and works the curve out in doubles from those
  values, never rounding what it computes. A step's corners are doubles too
  (the middle one's x is a fresh average).

  AN INDEX PAST EITHER END IS AN ILLEGAL POINT, as upstream's read of
  `undefined` is -- drawSegment finds a run's last point by the NEXT one
  being illegal as often as by its count.

  PURE: points in, commands out. }
interface
uses SysUtils, Math, fpjson, tyControls.AdvChart.Types,
     tyControls.AdvChart.Shape;

type
  TTyStepTurn = (sttNone, sttStart, sttMiddle, sttEnd);
  TTyPathCmdArray2 = array of TTyPathCmdArray;

{ getSmooth: a number as it is (no clamp: 1.5 stays 1.5), anything else by
  its truth -- 0.5 or 0, the string '0' included among the true }
function TyLineSmoothOf(AData: TJSONData): Double;

{ drawSegment: from AStart, ASegLen indices at most, ADir +1 or -1, into
  ACmds; answers how many indices it consumed. }
function TyDrawSegment(var ACmds: TTyPathCmdArray; const P: TTyPointFArray;
  AStart, ASegLen, AAllLen, ADir: Integer; ASmooth: Double;
  const AMonotone: string; AConnectNulls: Boolean): Integer;

{ ECPolyline.buildPath }
function TyPolylinePath(const P: TTyPointFArray; ASmooth: Double;
  const AMonotone: string; AConnectNulls: Boolean): TTyPathCmdArray;
{ ECPolygon.buildPath: each run's top forward from a move, its base (B,
  index for index) backwards from a line, and a close }
function TyPolygonPath(const P, B: TTyPointFArray; ASmooth, ABaseSmooth: Double;
  const AMonotone: string; AConnectNulls: Boolean): TTyPathCmdArray;

{ turnPointsIntoStep. AReference: the array whose illegal points are
  dropped under connectNulls (the line's own for the base), nil for P
  itself. ABaseIsX: the base axis is x (or radius). }
function TyTurnPointsIntoStep(const P, AReference: TTyPointFArray;
  AHasReference, ABaseIsX: Boolean; ATurn: TTyStepTurn;
  AConnectNulls: Boolean): TTyPointFArray;

{ the commands cut at each move: one run each }
function TySplitRuns(const ACmds: TTyPathCmdArray): TTyPathCmdArray2;

{ PathProxy.getBoundingRect of the commands }
function TyPathCmdsRect(const ACmds: TTyPathCmdArray): TTyXYWH;

implementation

uses tyControls.AdvChart.ZrPath;

function TyLineSmoothOf(AData: TJSONData): Double;
begin
  Result := 0;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtBoolean: if AData.AsBoolean then Result := 0.5;
    jtString: if AData.AsString <> '' then Result := 0.5;
    jtNull: Result := 0;
  else
    Result := 0.5;
  end;
end;

{ isPointIllegal, with a read off either end illegal too }
function At(const P: TTyPointFArray; AIdx: Integer; out AX, AY: Double): Boolean;
begin
  if (AIdx < 0) or (AIdx > High(P)) then
  begin
    AX := NaN;
    AY := NaN;
    Exit(False);
  end;
  AX := P[AIdx].X;
  AY := P[AIdx].Y;
  Result := not (IsNan(AX) or IsNan(AY) or IsInfinite(AX) or IsInfinite(AY));
end;

procedure Add(var ACmds: TTyPathCmdArray; AKind: TTyPathCmdKind;
  AX1, AY1, AX2, AY2, AX, AY: Double);
var n: Integer;
begin
  n := Length(ACmds);
  SetLength(ACmds, n + 1);
  ACmds[n].Kind := AKind;
  ACmds[n].X1 := AX1;
  ACmds[n].Y1 := AY1;
  ACmds[n].X2 := AX2;
  ACmds[n].Y2 := AY2;
  ACmds[n].X := AX;
  ACmds[n].Y := AY;
end;

{ Math.min / Math.max: a not-a-number wins }
function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function TyDrawSegment(var ACmds: TTyPathCmdArray; const P: TTyPointFArray;
  AStart, ASegLen, AAllLen, ADir: Integer; ASmooth: Double;
  const AMonotone: string; AConnectNulls: Boolean): Integer;
var
  idx, k, nextIdx, tmpK: Integer;
  x, y, prevX, prevY, cpx0, cpy0, cpx1, cpy1, nextCpx0, nextCpy0, dx, dy,
    nx, ny, vx, vy, dx0, dx1, dy0, dy1, lenPrev, lenNext, ratio, d: Double;
  legal, nextLegal: Boolean;
begin
  prevX := NaN;
  prevY := NaN;
  cpx0 := NaN;
  cpy0 := NaN;
  nextCpx0 := NaN;
  nextCpy0 := NaN;
  idx := AStart;
  k := 0;
  while k < ASegLen do
  begin
    { read before the range check, as upstream does }
    legal := At(P, idx, x, y);
    if (idx >= AAllLen) or (idx < 0) then Break;
    if not legal then
    begin
      if AConnectNulls then
      begin
        idx := idx + ADir;
        Inc(k);
        Continue;
      end;
      Break;
    end;
    if idx = AStart then
    begin
      if ADir > 0 then Add(ACmds, pckMove, 0, 0, 0, 0, x, y)
      else Add(ACmds, pckLine, 0, 0, 0, 0, x, y);
      cpx0 := x;
      cpy0 := y;
    end
    else
    begin
      dx := x - prevX;
      dy := y - prevY;
      { (A) a segment under 0.7 px from the last DRAWN point: dropped, and
        prev not moved }
      if dx * dx + dy * dy < 0.5 then
      begin
        idx := idx + ADir;
        Inc(k);
        Continue;
      end;
      if ASmooth > 0 then
      begin
        nextIdx := idx + ADir;
        nextLegal := At(P, nextIdx, nx, ny);
        { (B) the next point on top of this one: step past the duplicates }
        { NaN === x is false in JavaScript; FPC's = on a NaN raises }
        while (not IsNan(nx)) and (not IsNan(ny)) and (nx = x) and (ny = y)
          and (k < ASegLen) do
        begin
          Inc(k);
          nextIdx := nextIdx + ADir;
          idx := idx + ADir;
          nextLegal := At(P, nextIdx, nx, ny);
          At(P, idx, x, y);
          dx := x - prevX;
          dy := y - prevY;
        end;
        tmpK := k + 1;
        { (C) across a gap, when the gaps are bridged }
        if AConnectNulls then
          while (not nextLegal) and (tmpK < ASegLen) do
          begin
            Inc(tmpK);
            nextIdx := nextIdx + ADir;
            nextLegal := At(P, nextIdx, nx, ny);
          end;
        if (tmpK >= ASegLen) or not nextLegal then
        begin
          { (D) the last point: its own second control point }
          cpx1 := x;
          cpy1 := y;
        end
        else
        begin
          vx := nx - prevX;
          vy := ny - prevY;
          dx0 := x - prevX;
          dx1 := nx - x;
          dy0 := y - prevY;
          dy1 := ny - y;
          if AMonotone = 'x' then
          begin
            lenPrev := Abs(dx0);
            lenNext := Abs(dx1);
            if vx > 0 then d := 1 else d := -1;
            cpx1 := x - d * lenPrev * ASmooth;
            cpy1 := y;
            nextCpx0 := x + d * lenNext * ASmooth;
            nextCpy0 := y;
          end
          else if AMonotone = 'y' then
          begin
            lenPrev := Abs(dy0);
            lenNext := Abs(dy1);
            if vy > 0 then d := 1 else d := -1;
            cpx1 := x;
            cpy1 := y - d * lenPrev * ASmooth;
            nextCpx0 := x;
            nextCpy0 := y + d * lenNext * ASmooth;
          end
          else
          begin
            lenPrev := Sqrt(dx0 * dx0 + dy0 * dy0);
            lenNext := Sqrt(dx1 * dx1 + dy1 * dy1);
            ratio := lenNext / (lenNext + lenPrev);
            cpx1 := x - vx * ASmooth * (1 - ratio);
            cpy1 := y - vy * ASmooth * (1 - ratio);
            nextCpx0 := x + vx * ASmooth * ratio;
            nextCpy0 := y + vy * ASmooth * ratio;
            { the next control point into the box of [x, next] }
            nextCpx0 := JMin(nextCpx0, JMax(nx, x));
            nextCpy0 := JMin(nextCpy0, JMax(ny, y));
            nextCpx0 := JMax(nextCpx0, JMin(nx, x));
            nextCpy0 := JMax(nextCpy0, JMin(ny, y));
            { this one re-derived from it, into the box of [prev, x] }
            vx := nextCpx0 - x;
            vy := nextCpy0 - y;
            cpx1 := x - vx * lenPrev / lenNext;
            cpy1 := y - vy * lenPrev / lenNext;
            cpx1 := JMin(cpx1, JMax(prevX, x));
            cpy1 := JMin(cpy1, JMax(prevY, y));
            cpx1 := JMax(cpx1, JMin(prevX, x));
            cpy1 := JMax(cpy1, JMin(prevY, y));
            { and the next one again from it, not clamped this time }
            vx := x - cpx1;
            vy := y - cpy1;
            nextCpx0 := x + vx * lenNext / lenPrev;
            nextCpy0 := y + vy * lenNext / lenPrev;
          end;
        end;
        Add(ACmds, pckCurve, cpx0, cpy0, cpx1, cpy1, x, y);
        cpx0 := nextCpx0;
        cpy0 := nextCpy0;
      end
      else
        Add(ACmds, pckLine, 0, 0, 0, 0, x, y);
    end;
    prevX := x;
    prevY := y;
    idx := idx + ADir;
    Inc(k);
  end;
  Result := k;
end;

{ connectNulls: the illegal points trimmed off both ends }
procedure Trim(const P: TTyPointFArray; out AI, ALen: Integer);
var x, y: Double;
begin
  AI := 0;
  ALen := Length(P);
  while (ALen > 0) and not At(P, ALen - 1, x, y) do Dec(ALen);
  while (AI < ALen) and not At(P, AI, x, y) do Inc(AI);
end;

function TyPolylinePath(const P: TTyPointFArray; ASmooth: Double;
  const AMonotone: string; AConnectNulls: Boolean): TTyPathCmdArray;
var i, len: Integer;
begin
  Result := nil;
  i := 0;
  len := Length(P);
  if AConnectNulls then Trim(P, i, len);
  while i < len do
    i := i + TyDrawSegment(Result, P, i, len, len, 1, ASmooth, AMonotone,
      AConnectNulls) + 1;
end;

function TyPolygonPath(const P, B: TTyPointFArray; ASmooth, ABaseSmooth: Double;
  const AMonotone: string; AConnectNulls: Boolean): TTyPathCmdArray;
var i, len, k: Integer;
begin
  Result := nil;
  i := 0;
  len := Length(P);
  if AConnectNulls then Trim(P, i, len);
  while i < len do
  begin
    k := TyDrawSegment(Result, P, i, len, len, 1, ASmooth, AMonotone, AConnectNulls);
    TyDrawSegment(Result, B, i + k - 1, k, len, -1, ABaseSmooth, AMonotone,
      AConnectNulls);
    i := i + k + 1;
    Add(Result, pckClose, 0, 0, 0, 0, 0, 0);
  end;
end;

function TyTurnPointsIntoStep(const P, AReference: TTyPointFArray;
  AHasReference, ABaseIsX: Boolean; ATurn: TTyStepTurn;
  AConnectNulls: Boolean): TTyPointFArray;
var
  pts: TTyPointFArray;
  i, n, bi: Integer;
  pt, nx, a, b: array[0..1] of Double;
  middle, rx, ry: Double;

  procedure Push(AX, AY: Double);
  begin
    if n > High(Result) then SetLength(Result, Max(8, n * 2));
    Result[n] := TyPointF(AX, AY);
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  pts := P;
  if AConnectNulls then
  begin
    pts := nil;
    for i := 0 to High(P) do
    begin
      if AHasReference then At(AReference, i, rx, ry) else At(P, i, rx, ry);
      if not (IsNan(rx) or IsNan(ry) or IsInfinite(rx) or IsInfinite(ry)) then
      begin
        SetLength(pts, Length(pts) + 1);
        pts[High(pts)] := P[i];
      end;
    end;
  end;
  if ABaseIsX then bi := 0 else bi := 1;
  SetLength(Result, Length(pts) * 3 + 1);
  i := 0;
  while i < Length(pts) - 1 do
  begin
    nx[0] := pts[i + 1].X;
    nx[1] := pts[i + 1].Y;
    pt[0] := pts[i].X;
    pt[1] := pts[i].Y;
    Push(pt[0], pt[1]);
    case ATurn of
      sttEnd:
        begin
          a[bi] := nx[bi];
          a[1 - bi] := pt[1 - bi];
          Push(a[0], a[1]);
        end;
      sttMiddle:
        begin
          middle := (pt[bi] + nx[bi]) / 2;
          a[bi] := middle;
          b[bi] := middle;
          a[1 - bi] := pt[1 - bi];
          b[1 - bi] := nx[1 - bi];
          Push(a[0], a[1]);
          Push(b[0], b[1]);
        end;
    else
      a[bi] := pt[bi];
      a[1 - bi] := nx[1 - bi];
      Push(a[0], a[1]);
    end;
    Inc(i);
  end;
  { the last point: `points[i++]`, undefined for an empty array }
  if i <= High(pts) then Push(pts[i].X, pts[i].Y)
  else Push(NaN, NaN);
  SetLength(Result, n);
end;

function TySplitRuns(const ACmds: TTyPathCmdArray): TTyPathCmdArray2;
var i, n: Integer;
begin
  Result := nil;
  for i := 0 to High(ACmds) do
  begin
    if (ACmds[i].Kind = pckMove) or (Length(Result) = 0) then
      SetLength(Result, Length(Result) + 1);
    n := Length(Result[High(Result)]);
    SetLength(Result[High(Result)], n + 1);
    Result[High(Result)][n] := ACmds[i];
  end;
end;

function TyPathCmdsRect(const ACmds: TTyPathCmdArray): TTyXYWH;
var
  path: TTyZrPath;
  i: Integer;
begin
  path := nil;
  SetLength(path, Length(ACmds));
  for i := 0 to High(ACmds) do
  begin
    path[i] := Default(TTyZrSeg);
    case ACmds[i].Kind of
      pckMove:
        begin
          path[i].Cmd := zrM;
          path[i].V[0] := ACmds[i].X;
          path[i].V[1] := ACmds[i].Y;
        end;
      pckLine:
        begin
          path[i].Cmd := zrL;
          path[i].V[0] := ACmds[i].X;
          path[i].V[1] := ACmds[i].Y;
        end;
      pckCurve:
        begin
          path[i].Cmd := zrC;
          path[i].V[0] := ACmds[i].X1;
          path[i].V[1] := ACmds[i].Y1;
          path[i].V[2] := ACmds[i].X2;
          path[i].V[3] := ACmds[i].Y2;
          path[i].V[4] := ACmds[i].X;
          path[i].V[5] := ACmds[i].Y;
        end;
    else
      path[i].Cmd := zrZ;
    end;
  end;
  Result := TyZrBBox(path);
end;

end.
