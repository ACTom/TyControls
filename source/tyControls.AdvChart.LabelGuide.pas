unit tyControls.AdvChart.LabelGuide;
{$mode objfpc}{$H+}
{ LABEL-LINE ROUTING -- upstream's label/labelGuideHelper.ts, the part that
  decides where a label line goes once the labels are laid out.
  [Batch 112, roadmap B14]

  WHAT UPSTREAM DOES (ECharts 6.1.0, zrender 6.1):

  1. ROUTE (updateLabelLinePoints). LabelManager._updateLabelLine runs it on
     every element with a label and a data index -- every series but a pie's
     and a funnel's, which route their own lines, and a pie's too when its
     labelLayout gives an x or a y. The label's rect goes through the label's
     transform; each of four candidate anchors on it -- top, right, bottom,
     left, in that order -- is pushed out by labelLine.length2, carried into
     the HOST's own frame by the inverse of the host's transform, and
     measured against the host: the nearest point of the host's PATH
     (nearestPointOnPath), or of its rect, or -- for a pie -- the distance to
     the anchor the pie left (the line's first point). The nearest candidate
     wins (strictly: a tie keeps the earlier one), and the line is
     [the point on the host, the pushed-out anchor, the anchor] carried back.
  2. LIMIT. limitTurnAngle bends the middle point so the two segments turn by
     no less than labelLine.minTurnAngle degrees (out of (0, 180]: none);
     a pie's own last pass also runs limitSurfaceAngle, which keeps the first
     segment within maxSurfaceAngle of the slice's normal.
  3. DRAW. smooth (true is 0.3; anything else max(+smooth, 0), 0 for not a
     number) turns the corner into two cubics through points moved
     min(len1, len2) * smooth back along each segment (buildLabelLinePath).

  WHAT READS LIKE A BUG AND IS TRANSCRIBED AS ONE:
    - projectPointToArc answers d - r on the arc, which is NEGATIVE for a
      point inside a circle: the candidate deepest inside a symbol wins;
    - off the arc, it measures the arc's two ends against the point's UNIT
      DIRECTION (x and y were divided by d a few lines up), and answers that
      distance;
    - an elliptical arc is measured with x scaled by ry / rx and the point it
      finds is not scaled back;
    - the distances are compared in the HOST'S frame, so a symbol scaled
      unevenly weighs its candidates in a squashed space.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.ZrPath, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Symbol;

type
  TTyGuidePoints = array[0..2] of TTyPointF;

  { THE HOST as updateLabelLinePoints measures it. A path host's commands are
    in its own frame (Data: the PathProxy's data array, command codes
    included -- M 1, L 2, C 3, Q 4, A 5, Z 6, R 7); anything else answers its
    rect. HasM: the host's computed transform. HasAnchor: a pie's anchor,
    which replaces the measuring altogether. }
  TTyGuideHost = record
    IsPath: Boolean;
    Data: TTyDoubleArray;
    Rect: TTyXYWH;
    HasM: Boolean;
    M: TTyMat2D;
    HasAnchor: Boolean;
    AnchorX, AnchorY: Double;
  end;

const
  { TTyElementCaption.LgKind: what a host is to a label line }
  cTyGuideHostNone = 0;
  cTyGuideHostSymbol = 1;
  cTyGuideHostRect = 2;

{ ---- the projections (labelGuideHelper.ts), each answering the distance
  and the point it found ---- }
function TyGuideProjectToLine(AX1, AY1, AX2, AY2, AX, AY: Double;
  ALimitToEnds: Boolean; out AOX, AOY: Double): Double;
function TyGuideProjectToRect(AX1, AY1, AW, AH, AX, AY: Double;
  out AOX, AOY: Double): Double;
function TyGuideProjectToArc(ACX, ACY, AR, AStart, AEnd: Double;
  AAnti: Boolean; AX, AY: Double; out AOX, AOY: Double): Double;
{ zrender's curve.ts: twenty samples, then a bisection of up to 32 steps }
function TyCubicProjectPoint(AX0, AY0, AX1, AY1, AX2, AY2, AX3, AY3, AX,
  AY: Double; out AOX, AOY: Double): Double;
function TyQuadraticProjectPoint(AX0, AY0, AX1, AY1, AX2, AY2, AX,
  AY: Double; out AOX, AOY: Double): Double;
{ nearestPointOnPath over a PathProxy's data array: AOX / AOY are written
  only where a segment comes nearer than the last (a path of moves alone
  leaves them as they were) }
function TyNearestPointOnPath(const AData: array of Double; AX, AY: Double;
  var AOX, AOY: Double): Double;
function TyNearestPointOnRect(const ARect: TTyXYWH; AX, AY: Double;
  out AOX, AOY: Double): Double;

{ a ZrPath's commands as the PathProxy holds them, codes included }
function TyGuidePathData(const APath: TTyZrPath): TTyDoubleArray;

{ ---- the matrix arithmetic zrender's matrix.ts does ---- }
{ invert: False (upstream's null) for a determinant of nought or not a number }
function TyGuideMatInvert(const M: TTyMat2D; out AInv: TTyMat2D): Boolean;
{ mul(out, A, B) }
function TyGuideMatMul(const A, B: TTyMat2D): TTyMat2D;

{ ---- the route ---- }
{ updateLabelLinePoints up to (not including) its limitTurnAngle: ARaw is the
  label's own rect as read (getBoundingRect), ALabelM its transform; ALen
  labelLine.length2 as a number (device px). APoints: [on the host, the
  pushed-out anchor, the anchor on the label]. }
procedure TyLabelLineRoute(const ARaw: TTyXYWH; AHasLabelM: Boolean;
  const ALabelM: TTyMat2D; const AHost: TTyGuideHost; ALen: Double;
  out APoints: TTyGuidePoints);

{ limitTurnAngle (degrees; out of (0, 180] -- not-a-number included --
  nothing happens) }
procedure TyLimitTurnAngle(var APoints: TTyGuidePoints; AMinTurnAngle: Double);
{ limitSurfaceAngle, ANX / ANY the surface's normal }
procedure TyLimitSurfaceAngle(var APoints: TTyGuidePoints; ANX, ANY,
  AMaxSurfaceAngle: Double);

{ ---- reading and drawing ---- }
{ setLabelLineState's smooth: true 0.3, else max(+value, 0), 0 for not a
  number; absent (nil) is nought }
function TyLabelLineSmoothOf(D: TJSONData): Double;
{ an option value as JavaScript's ToNumber reads it (a product or a
  comparison coerces it): a number, a numeric string, a boolean, null as
  nought; nil (absent) answers AAbsent }
function TyGuideJsNumber(D: TJSONData; AAbsent: Double): Double;
{ `labelLineModel.get('length2') || 0` as Point.scaleAndAdd multiplies it:
  nought, false, '' and not-a-number are nought; any other string is its
  ToNumber (not a number for '10%'); nil (absent) answers AAbsent }
function TyGuideLength2(D: TJSONData; AAbsent: Double): Double;
{ buildLabelLinePath: the two cubics a smooth line draws, or nothing where it
  draws its points joined (not smooth, fewer than three points, a segment of
  no length) }
function TyLabelLineCmds(const APoints: array of TTyPointF;
  ASmooth: Double): TTyPathCmdArray;

{ ---- the hosts ---- }
{ the zrender symbol type a spec draws ('circle', 'path://...') }
function TyGuideSymbolName(const ASpec: TTySymbolSpec): string;
{ a symbol as SymbolDraw builds it: createSymbol(type, -1, -1, 2, 2) scaled to
  half its size, turned by symbolRotate (degrees), moved by its offset, in a
  group at the point }
function TyGuideSymbolHost(const AType: string; AKeepAspect: Boolean; AW, AH,
  ARotateDeg, AOffX, AOffY, APX, APY: Double): TTyGuideHost;
{ a Rect's path (a bar's layout, signed), its corners rounded when any of the
  four radii is }
function TyGuideRectHost(AX, AY, AW, AH: Double;
  const ARadii: array of Double): TTyGuideHost;
{ the host a caption describes (its Lg* fields); False for none }
function TyGuideHostOf(const ACaption: TTyElementCaption;
  out AHost: TTyGuideHost): Boolean;

implementation

uses
  tyControls.AdvChart.JsMath, tyControls.AdvChart.Data,
  tyControls.AdvChart.Layout, tyControls.AdvChart.LabelLayout;

const
  PI2 = 2 * Pi;
  cCurveStep: Double = 0.05;
  cCurveInterval: Double = 0.005;
  cEpsilonNumeric: Double = 1e-4;
  cArcCircle: Double = 1e-4;
  cHalf: Double = 0.5;
  cSmoothTrue: Double = 0.3;
  cTinySegment: Double = 1e-3;

{ ==================== JavaScript's comparisons and Math ==================== }

{ THE TRAPS OFF for the arithmetic upstream's own: a point at an arc's centre
  divides nought by nought there, and the answer is JavaScript's (not a number,
  comparisons false). The pending flags are cleared -- the SSE ones too, which
  ClearExceptions leaves -- before the old mask goes back (AdvChart.Graph's
  pair). }
function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ a < b, false where either is not a number (as JavaScript; FPC's own
  comparison need not be) }
function JLess(A, B: Double): Boolean; inline;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A < B);
end;

function JLessEq(A, B: Double): Boolean; inline;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A <= B);
end;

{ minus nought: nought with the sign bit set }
function IsNegZero(A: Double): Boolean; inline;
begin
  Result := (A = 0) and (PQWord(@A)^ <> 0);
end;

{ Math.max / Math.min of two: a not-a-number wins, +0 is above -0 }
function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Exit(A);
  if B > A then Exit(B);
  if IsNegZero(A) then Result := B else Result := A;
end;

function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Exit(A);
  if B < A then Exit(B);
  if IsNegZero(A) then Result := A else Result := B;
end;

{ normalizeRadian (contain/util.ts) }
function NormRad(A: Double): Double;
begin
  Result := TyJsFMod(A, PI2);
  if JLess(Result, 0) then Result := Result + PI2;
end;

{ ==================== the projections ==================== }

function PrjLine(AX1, AY1, AX2, AY2, AX, AY: Double;
  ALimitToEnds: Boolean; out AOX, AOY: Double): Double;
var dx, dy, dx1, dy1, lineLen, projectedLen, t: Double;
begin
  dx := AX - AX1;
  dy := AY - AY1;
  dx1 := AX2 - AX1;
  dy1 := AY2 - AY1;
  lineLen := Sqrt(dx1 * dx1 + dy1 * dy1);
  dx1 := dx1 / lineLen;
  dy1 := dy1 / lineLen;
  projectedLen := dx * dx1 + dy * dy1;
  t := projectedLen / lineLen;
  if ALimitToEnds then t := JsMin(JsMax(t, 0), 1);
  t := t * lineLen;
  AOX := AX1 + t * dx1;
  AOY := AY1 + t * dy1;
  Result := Sqrt((AOX - AX) * (AOX - AX) + (AOY - AY) * (AOY - AY));
end;

function TyGuideProjectToLine(AX1, AY1, AX2, AY2, AX, AY: Double;
  ALimitToEnds: Boolean; out AOX, AOY: Double): Double;
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    Result := PrjLine(AX1, AY1, AX2, AY2, AX, AY, ALimitToEnds, AOX, AOY);
  finally
    UnmaskFP(fm);
  end;
end;

function PrjRect(AX1, AY1, AW, AH, AX, AY: Double;
  out AOX, AOY: Double): Double;
var x2, y2: Double;
begin
  if JLess(AW, 0) then
  begin
    AX1 := AX1 + AW;
    AW := -AW;
  end;
  if JLess(AH, 0) then
  begin
    AY1 := AY1 + AH;
    AH := -AH;
  end;
  x2 := AX1 + AW;
  y2 := AY1 + AH;
  AOX := JsMin(JsMax(AX, AX1), x2);
  AOY := JsMin(JsMax(AY, AY1), y2);
  Result := Sqrt((AOX - AX) * (AOX - AX) + (AOY - AY) * (AOY - AY));
end;

function TyGuideProjectToRect(AX1, AY1, AW, AH, AX, AY: Double;
  out AOX, AOY: Double): Double;
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    Result := PrjRect(AX1, AY1, AW, AH, AX, AY, AOX, AOY);
  finally
    UnmaskFP(fm);
  end;
end;

function PrjArc(ACX, ACY, AR, AStart, AEnd: Double;
  AAnti: Boolean; AX, AY: Double; out AOX, AOY: Double): Double;
var d, ox, oy, tmp, angle, x1, y1, x2, y2, d1, d2: Double;
begin
  AX := AX - ACX;
  AY := AY - ACY;
  d := Sqrt(AX * AX + AY * AY);
  AX := AX / d;
  AY := AY / d;
  { the point on the circle }
  ox := AX * AR + ACX;
  oy := AY * AR + ACY;
  if JLess(TyJsFMod(Abs(AStart - AEnd), PI2), cArcCircle) then
  begin
    { a whole circle }
    AOX := ox;
    AOY := oy;
    Exit(d - AR);
  end;
  if AAnti then
  begin
    tmp := AStart;
    AStart := NormRad(AEnd);
    AEnd := NormRad(tmp);
  end
  else
  begin
    AStart := NormRad(AStart);
    AEnd := NormRad(AEnd);
  end;
  if JLess(AEnd, AStart) then AEnd := AEnd + PI2;
  angle := TyJsAtan2(AY, AX);
  if JLess(angle, 0) then angle := angle + PI2;
  if (JLessEq(AStart, angle) and JLessEq(angle, AEnd))
    or (JLessEq(AStart, angle + PI2) and JLessEq(angle + PI2, AEnd)) then
  begin
    { the point projects onto the arc }
    AOX := ox;
    AOY := oy;
    Exit(d - AR);
  end;
  x1 := AR * TyJsCos(AStart) + ACX;
  y1 := AR * TyJsSin(AStart) + ACY;
  x2 := AR * TyJsCos(AEnd) + ACX;
  y2 := AR * TyJsSin(AEnd) + ACY;
  { AGAINST THE UNIT DIRECTION: AX / AY were divided by d above }
  d1 := (x1 - AX) * (x1 - AX) + (y1 - AY) * (y1 - AY);
  d2 := (x2 - AX) * (x2 - AX) + (y2 - AY) * (y2 - AY);
  if JLess(d1, d2) then
  begin
    AOX := x1;
    AOY := y1;
    Result := Sqrt(d1);
  end
  else
  begin
    AOX := x2;
    AOY := y2;
    Result := Sqrt(d2);
  end;
end;

function TyGuideProjectToArc(ACX, ACY, AR, AStart, AEnd: Double;
  AAnti: Boolean; AX, AY: Double; out AOX, AOY: Double): Double;
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    Result := PrjArc(ACX, ACY, AR, AStart, AEnd, AAnti, AX, AY, AOX, AOY);
  finally
    UnmaskFP(fm);
  end;
end;

function CubicAt(P0, P1, P2, P3, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * onet * (onet * P0 + 3 * T * P1) + T * T * (T * P3 + 3 * onet * P2);
end;

function QuadraticAt(P0, P1, P2, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * (onet * P0 + 2 * T * P1) + T * T * P2;
end;

{ curve.ts' cubicProjectPoint / quadraticProjectPoint, AQuad picking which }
function CurveProject(AQuad: Boolean; const XS, YS: array of Double; AX, AY: Double;
  out AOX, AOY: Double): Double;
var
  t, tt, interval, d, d1, d2, prev, next, vx, vy: Double;
  i: Integer;

  procedure At(AT: Double; out OX, OY: Double);
  begin
    if AQuad then
    begin
      OX := QuadraticAt(XS[0], XS[1], XS[2], AT);
      OY := QuadraticAt(YS[0], YS[1], YS[2], AT);
    end
    else
    begin
      OX := CubicAt(XS[0], XS[1], XS[2], XS[3], AT);
      OY := CubicAt(YS[0], YS[1], YS[2], YS[3], AT);
    end;
  end;

begin
  { an undefined t, should every distance be not a number }
  t := NaN;
  interval := cCurveInterval;
  d := Infinity;
  tt := 0;
  while tt < 1 do
  begin
    At(tt, vx, vy);
    d1 := (AX - vx) * (AX - vx) + (AY - vy) * (AY - vy);
    if JLess(d1, d) then
    begin
      t := tt;
      d := d1;
    end;
    tt := tt + cCurveStep;
  end;
  d := Infinity;
  for i := 0 to 31 do
  begin
    if JLess(interval, cEpsilonNumeric) then Break;
    prev := t - interval;
    next := t + interval;
    At(prev, vx, vy);
    d1 := (vx - AX) * (vx - AX) + (vy - AY) * (vy - AY);
    if JLessEq(0, prev) and JLess(d1, d) then
    begin
      t := prev;
      d := d1;
    end
    else
    begin
      At(next, vx, vy);
      d2 := (vx - AX) * (vx - AX) + (vy - AY) * (vy - AY);
      if JLessEq(next, 1) and JLess(d2, d) then
      begin
        t := next;
        d := d2;
      end
      else
        interval := interval * cHalf;
    end;
  end;
  At(t, AOX, AOY);
  Result := Sqrt(d);
end;

function TyCubicProjectPoint(AX0, AY0, AX1, AY1, AX2, AY2, AX3, AY3, AX,
  AY: Double; out AOX, AOY: Double): Double;
begin
  Result := CurveProject(False, [AX0, AX1, AX2, AX3], [AY0, AY1, AY2, AY3], AX, AY, AOX, AOY);
end;

function TyQuadraticProjectPoint(AX0, AY0, AX1, AY1, AX2, AY2, AX,
  AY: Double; out AOX, AOY: Double): Double;
begin
  Result := CurveProject(True, [AX0, AX1, AX2], [AY0, AY1, AY2], AX, AY, AOX, AOY);
end;

{ the data array at AI, 0 past its end (an undefined there is a NaN in any
  arithmetic; nothing upstream builds reads past it) }
function DataAt(const AData: array of Double; AI: Integer): Double;
begin
  if (AI >= 0) and (AI <= High(AData)) then Result := AData[AI] else Result := NaN;
end;

function NearestOnPath(const AData: array of Double; AX, AY: Double;
  var AOX, AOY: Double): Double;
var
  i, cmd: Integer;
  xi, yi, x0, y0, minDist, d, tx, ty, cx, cy, rx, ry, theta, dTheta, sx,
    w, h: Double;
  anti: Boolean;
begin
  xi := 0;
  yi := 0;
  x0 := 0;
  y0 := 0;
  minDist := Infinity;
  tx := 0;
  ty := 0;
  i := 0;
  while i < Length(AData) do
  begin
    cmd := Round(AData[i]);
    Inc(i);
    { THE FIRST COMMAND seeds the current point from the two numbers after
      its code, whatever the command is }
    if i = 1 then
    begin
      xi := DataAt(AData, i);
      yi := DataAt(AData, i + 1);
      x0 := xi;
      y0 := yi;
    end;
    d := minDist;
    case cmd of
      1:
        begin
          x0 := DataAt(AData, i);
          y0 := DataAt(AData, i + 1);
          Inc(i, 2);
          xi := x0;
          yi := y0;
        end;
      2:
        begin
          d := PrjLine(xi, yi, DataAt(AData, i), DataAt(AData, i + 1),
            AX, AY, True, tx, ty);
          xi := DataAt(AData, i);
          yi := DataAt(AData, i + 1);
          Inc(i, 2);
        end;
      3:
        begin
          d := TyCubicProjectPoint(xi, yi, DataAt(AData, i), DataAt(AData, i + 1),
            DataAt(AData, i + 2), DataAt(AData, i + 3), DataAt(AData, i + 4),
            DataAt(AData, i + 5), AX, AY, tx, ty);
          xi := DataAt(AData, i + 4);
          yi := DataAt(AData, i + 5);
          Inc(i, 6);
        end;
      4:
        begin
          d := TyQuadraticProjectPoint(xi, yi, DataAt(AData, i), DataAt(AData, i + 1),
            DataAt(AData, i + 2), DataAt(AData, i + 3), AX, AY, tx, ty);
          xi := DataAt(AData, i + 2);
          yi := DataAt(AData, i + 3);
          Inc(i, 4);
        end;
      5:
        begin
          cx := DataAt(AData, i);
          cy := DataAt(AData, i + 1);
          rx := DataAt(AData, i + 2);
          ry := DataAt(AData, i + 3);
          theta := DataAt(AData, i + 4);
          dTheta := DataAt(AData, i + 5);
          { psi is skipped }
          anti := (1 - DataAt(AData, i + 7)) <> 0;
          Inc(i, 8);
          { zrender draws an ellipse as a scaled circle: x is scaled the same
            way, and the point found is not scaled back }
          sx := (AX - cx) * ry / rx + cx;
          d := PrjArc(cx, cy, ry, theta, theta + dTheta, anti, sx, AY, tx, ty);
          xi := TyJsCos(theta + dTheta) * rx + cx;
          yi := TyJsSin(theta + dTheta) * ry + cy;
        end;
      7:
        begin
          xi := DataAt(AData, i);
          yi := DataAt(AData, i + 1);
          x0 := xi;
          y0 := yi;
          w := DataAt(AData, i + 2);
          h := DataAt(AData, i + 3);
          Inc(i, 4);
          d := PrjRect(x0, y0, w, h, AX, AY, tx, ty);
        end;
      6:
        begin
          d := PrjLine(xi, yi, x0, y0, AX, AY, True, tx, ty);
          xi := x0;
          yi := y0;
        end;
    end;
    if JLess(d, minDist) then
    begin
      minDist := d;
      AOX := tx;
      AOY := ty;
    end;
  end;
  Result := minDist;
end;

function TyNearestPointOnPath(const AData: array of Double; AX, AY: Double;
  var AOX, AOY: Double): Double;
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    Result := NearestOnPath(AData, AX, AY, AOX, AOY);
  finally
    UnmaskFP(fm);
  end;
end;

function TyNearestPointOnRect(const ARect: TTyXYWH; AX, AY: Double;
  out AOX, AOY: Double): Double;
begin
  Result := TyGuideProjectToRect(ARect.X, ARect.Y, ARect.W, ARect.H, AX, AY, AOX, AOY);
end;

function TyGuidePathData(const APath: TTyZrPath): TTyDoubleArray;
const
  cCode: array[TTyZrCmd] of Integer = (1, 2, 3, 4, 5, 6, 7);
var i, k, n, c: Integer;
begin
  SetLength(Result, TyZrDataLength(APath));
  n := 0;
  for i := 0 to High(APath) do
  begin
    Result[n] := cCode[APath[i].Cmd];
    Inc(n);
    c := TyZrArgCount(APath[i].Cmd);
    for k := 0 to c - 1 do
    begin
      Result[n] := APath[i].V[k];
      Inc(n);
    end;
  end;
end;

{ ==================== matrices ==================== }

function TyGuideMatInvert(const M: TTyMat2D; out AInv: TTyMat2D): Boolean;
var aa, ac, atx, ab, ad, aty, det: Double;
begin
  aa := M[0]; ac := M[2]; atx := M[4];
  ab := M[1]; ad := M[3]; aty := M[5];
  det := aa * ad - ab * ac;
  { `if (!det) return null` }
  if IsNan(det) or (det = 0) then
  begin
    AInv := M;
    Exit(False);
  end;
  det := 1.0 / det;
  AInv[0] := ad * det;
  AInv[1] := -ab * det;
  AInv[2] := -ac * det;
  AInv[3] := aa * det;
  AInv[4] := (ac * aty - ad * atx) * det;
  AInv[5] := (ab * atx - aa * aty) * det;
  Result := True;
end;

function TyGuideMatMul(const A, B: TTyMat2D): TTyMat2D;
begin
  Result[0] := A[0] * B[0] + A[2] * B[1];
  Result[1] := A[1] * B[0] + A[3] * B[1];
  Result[2] := A[0] * B[2] + A[2] * B[3];
  Result[3] := A[1] * B[2] + A[3] * B[3];
  Result[4] := A[0] * B[4] + A[2] * B[5] + A[4];
  Result[5] := A[1] * B[4] + A[3] * B[5] + A[5];
end;

{ Point.transform }
procedure PtApply(const M: TTyMat2D; var P: TTyPointF); inline;
var x, y: Double;
begin
  x := P.X;
  y := P.Y;
  P.X := M[0] * x + M[2] * y + M[4];
  P.Y := M[1] * x + M[3] * y + M[5];
end;

{ ==================== the route ==================== }

procedure Route(const ARaw: TTyXYWH; AHasLabelM: Boolean;
  const ALabelM: TTyMat2D; const AHost: TTyGuideHost; ALen: Double;
  out APoints: TTyGuidePoints);
var
  r: TTyXYWH;
  inv: TTyMat2D;
  hasInv: Boolean;
  minDist, dist, dx, dy, ox, oy: Double;
  pt0, pt1, pt2, dir: TTyPointF;
  c: Integer;
begin
  APoints[0] := TyPointF(0, 0);
  APoints[1] := TyPointF(0, 0);
  APoints[2] := TyPointF(0, 0);
  { the label's rect through the label's transform }
  if AHasLabelM then r := TyRectApplyMat(ARaw, ALabelM) else r := ARaw;
  hasInv := AHost.HasM and TyGuideMatInvert(AHost.M, inv);
  minDist := Infinity;
  { THE POINT ON THE HOST persists across the candidates: the anchor copied
    once (and carried by the host's transform each time a candidate wins), or
    the last point nearestPointOnPath wrote }
  pt2 := TyPointF(0, 0);
  if AHost.HasAnchor then pt2 := TyPointF(AHost.AnchorX, AHost.AnchorY);
  for c := 0 to 3 do
  begin
    { getCandidateAnchor, distance 0: top, right, bottom, left }
    case c of
      0:
        begin
          pt0 := TyPointF(r.X + r.W / 2, r.Y - 0);
          dir := TyPointF(0, -1);
        end;
      1:
        begin
          pt0 := TyPointF(r.X + r.W + 0, r.Y + r.H / 2);
          dir := TyPointF(1, 0);
        end;
      2:
        begin
          pt0 := TyPointF(r.X + r.W / 2, r.Y + r.H + 0);
          dir := TyPointF(0, 1);
        end;
    else
      pt0 := TyPointF(r.X - 0, r.Y + r.H / 2);
      dir := TyPointF(-1, 0);
    end;
    { Point.scaleAndAdd(pt1, pt0, dir, len) }
    pt1.X := pt0.X + dir.X * ALen;
    pt1.Y := pt0.Y + dir.Y * ALen;
    { into the host's frame }
    if hasInv then PtApply(inv, pt1);
    if AHost.HasAnchor then
    begin
      dx := AHost.AnchorX - pt1.X;
      dy := AHost.AnchorY - pt1.Y;
      dist := Sqrt(dx * dx + dy * dy);
    end
    else if AHost.IsPath then
    begin
      ox := pt2.X;
      oy := pt2.Y;
      dist := NearestOnPath(AHost.Data, pt1.X, pt1.Y, ox, oy);
      pt2 := TyPointF(ox, oy);
    end
    else
    begin
      dist := TyNearestPointOnRect(AHost.Rect, pt1.X, pt1.Y, ox, oy);
      pt2 := TyPointF(ox, oy);
    end;
    if JLess(dist, minDist) then
    begin
      minDist := dist;
      { back to the global frame }
      if AHost.HasM then
      begin
        PtApply(AHost.M, pt1);
        PtApply(AHost.M, pt2);
      end;
      APoints[0] := pt2;
      APoints[1] := pt1;
      APoints[2] := pt0;
    end;
  end;
end;

procedure TyLabelLineRoute(const ARaw: TTyXYWH; AHasLabelM: Boolean;
  const ALabelM: TTyMat2D; const AHost: TTyGuideHost; ALen: Double;
  out APoints: TTyGuidePoints);
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    Route(ARaw, AHasLabelM, ALabelM, AHost, ALen, APoints);
  finally
    UnmaskFP(fm);
  end;
end;

{ the limits' shared tail: the new middle point clamped to the segment
  pt1-pt2 by its parameter; False where the parameter is not a number }
function ClampOnSegment(var Q: TTyPointF; const P1, P2: TTyPointF): Boolean;
var t: Double;
begin
  { `pt2.x !== pt1.x`, true where either is not a number }
  if IsNan(P2.X) or IsNan(P1.X) or (P2.X <> P1.X) then t := (Q.X - P1.X) / (P2.X - P1.X)
  else t := (Q.Y - P1.Y) / (P2.Y - P1.Y);
  if IsNan(t) then Exit(False);
  if t < 0 then Q := P1
  else if t > 1 then Q := P2;
  Result := True;
end;

procedure LimitTurn(var APoints: TTyGuidePoints; AMinTurnAngle: Double);
var
  pt0, pt1, pt2, dir, dir2, q: TTyPointF;
  len1, len2, angleCos, minCos, d, ox, oy, k: Double;
begin
  if not (JLessEq(AMinTurnAngle, 180) and JLess(0, AMinTurnAngle)) then Exit;
  AMinTurnAngle := AMinTurnAngle / 180 * Pi;
  pt0 := APoints[0];
  pt1 := APoints[1];
  pt2 := APoints[2];
  dir := TyPointF(pt0.X - pt1.X, pt0.Y - pt1.Y);
  dir2 := TyPointF(pt2.X - pt1.X, pt2.Y - pt1.Y);
  len1 := Sqrt(dir.X * dir.X + dir.Y * dir.Y);
  len2 := Sqrt(dir2.X * dir2.X + dir2.Y * dir2.Y);
  if JLess(len1, cTinySegment) or JLess(len2, cTinySegment) then Exit;
  dir.X := dir.X * (1 / len1);
  dir.Y := dir.Y * (1 / len1);
  dir2.X := dir2.X * (1 / len2);
  dir2.Y := dir2.Y * (1 / len2);
  angleCos := dir.X * dir2.X + dir.Y * dir2.Y;
  minCos := TyJsCos(AMinTurnAngle);
  if JLess(minCos, angleCos) then
  begin
    { pt0 projected onto the line pt1-pt2, then moved along it so the turn is
      the minimum }
    d := PrjLine(pt1.X, pt1.Y, pt2.X, pt2.Y, pt0.X, pt0.Y, False, ox, oy);
    k := d / TyJsTan(Pi - AMinTurnAngle);
    q.X := ox + dir2.X * k;
    q.Y := oy + dir2.Y * k;
    if not ClampOnSegment(q, pt1, pt2) then Exit;
    APoints[1] := q;
  end;
end;

procedure TyLimitTurnAngle(var APoints: TTyGuidePoints; AMinTurnAngle: Double);
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    LimitTurn(APoints, AMinTurnAngle);
  finally
    UnmaskFP(fm);
  end;
end;

procedure LimitSurface(var APoints: TTyGuidePoints; ANX, ANY,
  AMaxSurfaceAngle: Double);
var
  pt0, pt1, pt2, dir, dir2, q: TTyPointF;
  len1, len2, angleCos, maxCos, d, ox, oy, angle2, newAngle, k, halfPi: Double;
begin
  if not (JLessEq(AMaxSurfaceAngle, 180) and JLess(0, AMaxSurfaceAngle)) then Exit;
  AMaxSurfaceAngle := AMaxSurfaceAngle / 180 * Pi;
  pt0 := APoints[0];
  pt1 := APoints[1];
  pt2 := APoints[2];
  dir := TyPointF(pt1.X - pt0.X, pt1.Y - pt0.Y);
  dir2 := TyPointF(pt2.X - pt1.X, pt2.Y - pt1.Y);
  len1 := Sqrt(dir.X * dir.X + dir.Y * dir.Y);
  len2 := Sqrt(dir2.X * dir2.X + dir2.Y * dir2.Y);
  if JLess(len1, cTinySegment) or JLess(len2, cTinySegment) then Exit;
  dir.X := dir.X * (1 / len1);
  dir.Y := dir.Y * (1 / len1);
  dir2.X := dir2.X * (1 / len2);
  dir2.Y := dir2.Y * (1 / len2);
  angleCos := dir.X * ANX + dir.Y * ANY;
  maxCos := TyJsCos(AMaxSurfaceAngle);
  if JLess(angleCos, maxCos) then
  begin
    d := PrjLine(pt1.X, pt1.Y, pt2.X, pt2.Y, pt0.X, pt0.Y, False, ox, oy);
    q := TyPointF(ox, oy);
    halfPi := Pi / 2;
    angle2 := TyJsAcos(dir2.X * ANX + dir2.Y * ANY);
    newAngle := halfPi + angle2 - AMaxSurfaceAngle;
    if JLessEq(halfPi, newAngle) then
      { parallel }
      q := pt2
    else
    begin
      k := d / TyJsTan(Pi / 2 - newAngle);
      q.X := q.X + dir2.X * k;
      q.Y := q.Y + dir2.Y * k;
      if not ClampOnSegment(q, pt1, pt2) then Exit;
    end;
    APoints[1] := q;
  end;
end;

procedure TyLimitSurfaceAngle(var APoints: TTyGuidePoints; ANX, ANY,
  AMaxSurfaceAngle: Double);
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    LimitSurface(APoints, ANX, ANY, AMaxSurfaceAngle);
  finally
    UnmaskFP(fm);
  end;
end;

{ ==================== reading and drawing ==================== }

function TyGuideJsNumber(D: TJSONData; AAbsent: Double): Double;
begin
  if D = nil then Exit(AAbsent);
  case D.JSONType of
    jtNull: Result := 0;
    jtNumber: Result := D.AsFloat;
    jtBoolean: if D.AsBoolean then Result := 1 else Result := 0;
    jtString: Result := TyJsToNumber(D.AsString);
  else
    Result := NaN;
  end;
end;

function TyGuideLength2(D: TJSONData; AAbsent: Double): Double;
begin
  if D = nil then Exit(AAbsent);
  case D.JSONType of
    jtNumber:
      begin
        Result := D.AsFloat;
        if IsNan(Result) then Result := 0;
      end;
    jtString:
      if D.AsString = '' then Result := 0
      else Result := TyJsToNumber(D.AsString);
    jtBoolean: if D.AsBoolean then Result := 1 else Result := 0;
    jtNull: Result := 0;
  else
    Result := NaN;
  end;
end;

function TyLabelLineSmoothOf(D: TJSONData): Double;
begin
  if (D <> nil) and (D.JSONType = jtBoolean) and D.AsBoolean then Exit(cSmoothTrue);
  { Math.max(+smooth, 0) || 0 }
  Result := JsMax(TyGuideJsNumber(D, NaN), 0);
  if IsNan(Result) then Result := 0;
end;

function SmoothCmds(const APoints: array of TTyPointF;
  ASmooth: Double): TTyPathCmdArray;
var
  len1, len2, moveLen, t: Double;
  m0, m1, m2, p0, p1, p2: TTyPointF;

  function Dist(const A, B: TTyPointF): Double;
  begin
    Result := Sqrt((A.X - B.X) * (A.X - B.X) + (A.Y - B.Y) * (A.Y - B.Y));
  end;

  function Lerp(const A, B: TTyPointF; AT: Double): TTyPointF;
  begin
    Result.X := A.X + AT * (B.X - A.X);
    Result.Y := A.Y + AT * (B.Y - A.Y);
  end;

begin
  Result := nil;
  if not (JLess(0, ASmooth) and (Length(APoints) >= 3)) then Exit;
  p0 := APoints[0];
  p1 := APoints[1];
  p2 := APoints[2];
  len1 := Dist(p0, p1);
  len2 := Dist(p1, p2);
  { `!len1 || !len2`: straight }
  if (len1 = 0) or IsNan(len1) or (len2 = 0) or IsNan(len2) then Exit;
  moveLen := JsMin(len1, len2) * ASmooth;
  t := moveLen / len1;
  m0 := Lerp(p1, p0, t);
  t := moveLen / len2;
  m2 := Lerp(p1, p2, t);
  m1 := Lerp(m0, m2, cHalf);
  SetLength(Result, 3);
  Result[0].Kind := pckMove;
  Result[0].X := p0.X;
  Result[0].Y := p0.Y;
  Result[1].Kind := pckCurve;
  Result[1].X1 := m0.X;
  Result[1].Y1 := m0.Y;
  Result[1].X2 := m0.X;
  Result[1].Y2 := m0.Y;
  Result[1].X := m1.X;
  Result[1].Y := m1.Y;
  Result[2].Kind := pckCurve;
  Result[2].X1 := m2.X;
  Result[2].Y1 := m2.Y;
  Result[2].X2 := m2.X;
  Result[2].Y2 := m2.Y;
  Result[2].X := p2.X;
  Result[2].Y := p2.Y;
end;

function TyLabelLineCmds(const APoints: array of TTyPointF;
  ASmooth: Double): TTyPathCmdArray;
var fm: TFPUExceptionMask;
begin
  fm := MaskFP;
  try
    Result := SmoothCmds(APoints, ASmooth);
  finally
    UnmaskFP(fm);
  end;
end;

{ ==================== the hosts ==================== }

function TyGuideSymbolName(const ASpec: TTySymbolSpec): string;
begin
  case ASpec.Kind of
    tsyCircle: Result := 'circle';
    tsyRect: Result := 'rect';
    tsyRoundRect: Result := 'roundRect';
    tsySquare: Result := 'square';
    tsyTriangle: Result := 'triangle';
    tsyDiamond: Result := 'diamond';
    tsyPin: Result := 'pin';
    tsyArrow: Result := 'arrow';
    tsyLine: Result := 'line';
    tsyPath: Result := 'path://' + ASpec.PathData;
  else
    Result := '';
  end;
end;

function TyGuideSymbolHost(const AType: string; AKeepAspect: Boolean; AW, AH,
  ARotateDeg, AOffX, AOffY, APX, APY: Double): TTyGuideHost;
var
  path: TTyZrPath;
  rot: Double;
  local, parent: TTyMat2D;
  hasLocal, hasParent: Boolean;
begin
  Result := Default(TTyGuideHost);
  { createSymbol(type, -1, -1, 2, 2): a path:// icon fitted keeping its
    aspect, or stretched over the box (keepAspect false: 'cover') }
  if (Copy(AType, 1, 7) = 'path://') and not AKeepAspect then
    path := TyZrMakePathCover(Copy(AType, 8, MaxInt), TyXYWH(-1, -1, 2, 2))
  else
    path := TyZrSymbol(AType, -1, -1, 2, 2);
  Result.IsPath := True;
  Result.Data := TyGuidePathData(path);
  { symbolPath: scaled to half its size, turned by
    (symbolRotate || 0) * Math.PI / 180 || 0, moved by its offset }
  rot := ARotateDeg * Pi / 180;
  if IsNan(rot) then rot := 0;
  hasLocal := TyLabelLocalTransform(AOffX, AOffY, 0, 0, rot, AW / 2, AH / 2, local);
  { its group, at the point }
  hasParent := TyLabelLocalTransform(APX, APY, 0, 0, 0, 1, 1, parent);
  Result.HasM := hasLocal or hasParent;
  if hasLocal and hasParent then Result.M := TyGuideMatMul(parent, local)
  else if hasLocal then Result.M := local
  else Result.M := parent;
end;

function TyGuideRectHost(AX, AY, AW, AH: Double;
  const ARadii: array of Double): TTyGuideHost;
var
  path: TTyZrPath;
  r1, r2, r3, r4: Double;
begin
  Result := Default(TTyGuideHost);
  path := nil;
  TyZrRadii(ARadii, r1, r2, r3, r4);
  if (r1 <> 0) or (r2 <> 0) or (r3 <> 0) or (r4 <> 0) then
    TyZrRoundRect(path, AX, AY, AW, AH, r1, r2, r3, r4)
  else
    TyZrRect(path, AX, AY, AW, AH);
  Result.IsPath := True;
  Result.Data := TyGuidePathData(path);
end;

function TyGuideHostOf(const ACaption: TTyElementCaption;
  out AHost: TTyGuideHost): Boolean;
begin
  AHost := Default(TTyGuideHost);
  case ACaption.LgKind of
    cTyGuideHostSymbol:
      AHost := TyGuideSymbolHost(ACaption.LgSymbol, ACaption.LgKeepAspect,
        ACaption.LgG[0], ACaption.LgG[1], ACaption.LgG[2], ACaption.LgG[3],
        ACaption.LgG[4], ACaption.LgG[5], ACaption.LgG[6]);
    cTyGuideHostRect:
      AHost := TyGuideRectHost(ACaption.LgG[0], ACaption.LgG[1], ACaption.LgG[2],
        ACaption.LgG[3], [ACaption.LgG[4], ACaption.LgG[5], ACaption.LgG[6],
        ACaption.LgG[7]]);
  else
    Exit(False);
  end;
  Result := True;
end;

end.
