unit tyControls.AdvChart.Morph;
{$mode objfpc}{$H+}
{ zrender's PATH MORPHING, transcribed: tool/convertPath.ts (pathToBezierCurves,
  pathToPolygons), tool/morphPath.ts (alignSubpath, alignBezierCurves, centroid,
  findBestRingOffset, reverse, findBestMorphingRotation, applyTransformOnBeziers,
  prepareMorphPath and the buildPath it puts in the target's place, hilbert) and
  tool/dividePath.ts (getDividingGrids, the rect / sector / polygon dividers,
  split's polygon fallback), and echarts' animation/morphTransitionHelper.ts
  prepareMorphBatches. [Batch 136, D5 UT1]
  What combining and separating read besides [Batch 137, D5 UT2]:
  core/PathProxy.ts getBoundingRect with core/bbox.ts (fromLine, fromCubic,
  fromQuadratic, fromArc), Path.getBoundingRect's stroke, Transformable's
  setLocalTransform and the transform an element with no parent then
  computes, and sortPaths' order (its hilbert keys, a stable sort).

  THE DATA IS PATHPROXY'S. Every path here is the flat array a PathProxy holds
  -- a command code (M 1, L 2, C 3, Q 4, A 5, Z 6, R 7) and its arguments --
  as LabelGuide.TyGuidePathData lays a TTyZrPath out; the morph's frame comes
  back in the same form (moves, lines and cubics only).

  WHAT A MORPH IS. Both paths become rings of cubic beziers (a line is a cubic
  whose control points sit on its ends), one ring per subpath; the shorter of
  each pair of rings is subdivided until both have the same number of curves,
  and a missing ring is made of the other side's last point repeated. Each
  ring is then centred on its centroid, the source ring is reversed when the
  two wind the other way round (the first pair decides for all of them), the
  source is rotated by whole curves to the start that lies nearest the
  target's, and the target is turned by the angle in [-pi/2, pi/2], in steps
  of pi/10, that brings it nearest. A frame at t lerps the points and the
  centres and turns back by t times that angle; a curve whose control points
  sit on its ends is drawn as a line.

  WHAT READS LIKE A BUG AND IS TRANSCRIBED AS ONE:
    - alignSubpath cuts the k-th piece of a curve at k / n of the REMAINING
      curve, not of the whole one;
    - prepareMorphBatches overwrites batch 0's list with half of another
      batch's when it wraps round (`off = 0` after `moveFrom` was taken);
    - divideSector adds |sweep| to the start angle whatever the direction;
    - cubicExtrema finds a double root and does not count it (the bounding
      rect of such a curve is its end points').

  DEVIATIONS (where upstream throws or never returns): a polygon count below
  one (an empty polygon in the area split) divides into nothing; the adaptive
  bezier of pathToPolygons stops at a depth of 64 (upstream recurses until
  the stack goes when a point is not a number).

  PURE: numbers in, numbers out. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Shape;

type
  { cubicSubdivide's out: the first half's four points, then the second's }
  TTyCubicSplit = array[0..7] of Double;
  { one ring of beziers: its start point, then six numbers a curve }
  TTyBezierCurves = array of TTyDoubleArray;

  { one subpath of findBestMorphingRotation's answer: the two rings centred,
    their centroids ([x, y] or [x, y, signed area]) and the angle }
  TTyMorphSub = record
    From, Dest: TTyDoubleArray;
    FromCp, DestCp: TTyDoubleArray;
    Rotation: Double;
  end;
  TTyMorphData = array of TTyMorphSub;

  { split's pieces: a rect, a sector or a polygon (flat x, y) }
  TTyDivideKind = (dkRect, dkSector, dkPolygon);
  TTyDividePiece = record
    Kind: TTyDivideKind;
    X, Y, W, H: Double;
    CX, CY, R0, R, StartAngle, EndAngle: Double;
    { a sector's `clockwise` as the source held it; HasClockwise False for
      undefined (a circle's pieces) }
    HasClockwise, Clockwise: Boolean;
    Points: TTyDoubleArray;
  end;
  TTyDividePieceArray = array of TTyDividePiece;

  { prepareMorphBatches over ids: `one` and the `many` it takes }
  TTyMorphBatch = record
    One: Integer;
    Many: TTyIntegerArray;
  end;
  TTyMorphBatchArray = array of TTyMorphBatch;

const
  TyZrCodeM = 1;
  TyZrCodeL = 2;
  TyZrCodeC = 3;
  TyZrCodeQ = 4;
  TyZrCodeA = 5;
  TyZrCodeZ = 6;
  TyZrCodeR = 7;

{ ---- curve.ts / convertPath.ts ---- }
procedure TyCubicSubdivide(P0, P1, P2, P3, T: Double; out AOut: TTyCubicSplit);
function TyPathToBezierCurves(const AData: array of Double): TTyBezierCurves;
{ pathToPolygons: AScale as given (upstream's `scale || 1` is the caller's) }
function TyPathToPolygons(const AData: array of Double; AScale: Double): TTyBezierCurves;

{ ---- morphPath.ts ---- }
procedure TyAlignSubpath(const A1, A2: TTyDoubleArray; out O1, O2: TTyDoubleArray);
procedure TyAlignBezierCurves(const A1, A2: TTyBezierCurves; out O1, O2: TTyBezierCurves);
{ [cx, cy, signed area], or [x0 || 0, y0 || 0] for no area }
function TyMorphCentroid(const A: TTyDoubleArray): TTyDoubleArray;
function TyFindBestRingOffset(const AFrom, ATo, AFromCp, AToCp: TTyDoubleArray): Integer;
function TyMorphReverse(const A: TTyDoubleArray): TTyDoubleArray;
function TyFindBestMorphingRotation(const AFrom, ATo: TTyBezierCurves;
  AIterations: Integer; ARange: Double): TTyMorphData;
procedure TyApplyTransformOnBeziers(var ACurves: TTyBezierCurves; const M: TTyMat2D);
{ prepareMorphPath: the two paths' data, each with its computed transform
  (AHas False: none) }
function TyPrepareMorph(const AFrom: array of Double; AFromHasM: Boolean;
  const AFromM: TTyMat2D; const ATo: array of Double; AToHasM: Boolean;
  const AToM: TTyMat2D): TTyMorphData;
{ the replaced buildPath at __morphT = AT: PathProxy data }
function TyMorphPathData(const AData: TTyMorphData; AT: Double): TTyDoubleArray;
{ PathProxy data (moves, lines, cubics, closes) as path commands to draw }
function TyMorphDataCmds(const AData: TTyDoubleArray): TTyPathCmdArray;
{ sortPaths' key }
function TyMorphHilbert(AX, AY, AMinX, AMinY, AMaxX, AMaxY: Double): Double;

{ ---- what combining and separating read [Batch 137, D5 UT2] ---- }
{ PathProxy.getBoundingRect over PathProxy data (bbox.ts' fromLine /
  fromCubic / fromQuadratic / fromArc, the double root of cubicExtrema not
  counted, as upstream) }
function TyPathDataRect(const AData: array of Double): TTyXYWH;
{ Path.getBoundingRect's stroke: grown by the line width -- at least the
  hover threshold 5 where nothing fills -- over getLineScale under
  strokeNoScale }
function TyPathStrokeRect(const ARect: TTyXYWH; AHasStroke, AHasFill: Boolean;
  ALineWidth: Double; ANoScale, AHasM: Boolean; const AM: TTyMat2D): TTyXYWH;
{ setLocalTransform(AM) and the transform an element with no parent then
  computes (updateTransform): AOutHas False for none }
procedure TyMorphRecompose(const AM: TTyMat2D; out AOutHas: Boolean; out AOut: TTyMat2D);
{ sortPaths: the paths' order by their centres on the hilbert curve (the
  sort is stable) }
function TyMorphSortOrder(const ACX, ACY: array of Double): TTyIntegerArray;

{ ---- dividePath.ts ---- }
{ getDividingGrids: the column count of each row }
function TyDividingGrids(ADim0, ADim1: Double; ARowDim, ACount: Integer): TTyDoubleArray;
function TyDivideRect(AX, AY, AW, AH: Double; ACount: Integer): TTyDividePieceArray;
function TyDivideSector(ACX, ACY, AR0, AR, AStart, AEnd: Double; AHasClockwise,
  AClockwise: Boolean; ACount: Integer): TTyDividePieceArray;
{ split's fallback: the path's polygons (pathToPolygons at the scale) divided
  into ACount pieces }
function TyDividePolygons(const APolygons: TTyBezierCurves; ACount: Integer): TTyDividePieceArray;
{ the clone divider's opacity: 1 - (1 - opacity) ^ (1 / count) }
function TyCloneOpacity(AOpacity: Double; ACount: Integer): Double;

{ ---- morphTransitionHelper.ts ---- }
function TyPrepareMorphBatches(const AOne: array of Integer;
  const AMany: array of TTyIntegerArray): TTyMorphBatchArray;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
  tyControls.AdvChart.DataTransform;

const
  cTwoThirds: Double = 2 / 3;
  cAroundEqual: Double = 1e-5;
  cTiny: Double = 1e-6;

type
  { a growable flat array }
  TDList = record
    A: TTyDoubleArray;
    N: Integer;
  end;

procedure DPush(var L: TDList; V: Double);
begin
  if L.N >= Length(L.A) then SetLength(L.A, L.N * 2 + 16);
  L.A[L.N] := V;
  Inc(L.N);
end;

function DDone(var L: TDList): TTyDoubleArray;
begin
  SetLength(L.A, L.N);
  Result := L.A;
  L.A := nil;
  L.N := 0;
end;

{ THE TRAPS OFF for upstream's own arithmetic: nought over nought, an
  infinite count and the like are JavaScript's numbers here. The pending flags
  are cleared -- the SSE ones too -- before the old mask goes back (as
  AdvChart.LabelGuide's pair). }
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

{ ==================== JavaScript's numbers ==================== }

function JsEq(A, B: Double): Boolean; inline;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A = B);
end;

function JsLess(A, B: Double): Boolean; inline;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A < B);
end;

function JsLessEq(A, B: Double): Boolean; inline;
begin
  Result := (not IsNan(A)) and (not IsNan(B)) and (A <= B);
end;

function SignBit(A: Double): Boolean; inline;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := (q shr 63) <> 0;
end;

{ Math.min / Math.max: a not-a-number wins, -0 below +0 }
function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if (A = 0) and (B = 0) then
  begin
    if SignBit(A) then Exit(A);
    Exit(B);
  end;
  if A < B then Result := A else Result := B;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if (A = 0) and (B = 0) then
  begin
    if SignBit(A) then Exit(B);
    Exit(A);
  end;
  if A > B then Result := A else Result := B;
end;

{ `v || 0` }
function OrZero(A: Double): Double; inline;
begin
  if IsNan(A) or (A = 0) then Result := 0 else Result := A;
end;

{ ToInt32 }
function ToInt32(A: Double): LongInt;
var q: Int64;
begin
  if IsNan(A) or IsInfinite(A) then Exit(0);
  A := Int(A);
  A := A - JsFloor(A / 4294967296.0) * 4294967296.0;
  q := Trunc(A);
  Result := LongInt(LongWord(q));
end;

{ array[i] -- undefined (not a number) outside it }
function At(const A: array of Double; I: Integer): Double;
begin
  if (I >= 0) and (I <= High(A)) then Result := A[I] else Result := NaN;
end;

function AtD(const A: TTyDoubleArray; I: Integer): Double;
begin
  if (I >= 0) and (I <= High(A)) then Result := A[I] else Result := NaN;
end;

{ ==================== curve.ts / convertPath.ts ==================== }

procedure TyCubicSubdivide(P0, P1, P2, P3, T: Double; out AOut: TTyCubicSplit);
var p01, p12, p23, p012, p123, p0123: Double;
begin
  p01 := (P1 - P0) * T + P0;
  p12 := (P2 - P1) * T + P1;
  p23 := (P3 - P2) * T + P2;
  p012 := (p12 - p01) * T + p01;
  p123 := (p23 - p12) * T + p12;
  p0123 := (p123 - p012) * T + p012;
  AOut[0] := P0;
  AOut[1] := p01;
  AOut[2] := p012;
  AOut[3] := p0123;
  AOut[4] := p0123;
  AOut[5] := p123;
  AOut[6] := p23;
  AOut[7] := P3;
end;

function AroundEqual(A, B: Double): Boolean; inline;
begin
  Result := JsLess(Abs(A - B), cAroundEqual);
end;

function TyPathToBezierCurves(const AData: array of Double): TTyBezierCurves;
var
  groups: TTyBezierCurves;
  cur: TDList;
  hasCur: Boolean;
  xi, yi, x0, y0, x1, y1, x2, y2, cx, cy, rx, ry, startAngle, endAngle,
    step, angle, nextAngle: Double;
  i, len, cmd: Integer;
  isFirst, anticlockwise: Boolean;

  procedure CreateNewSubpath(AX, AY: Double);
  begin
    { more than one M command }
    if hasCur and (cur.N > 2) then
    begin
      SetLength(groups, Length(groups) + 1);
      groups[High(groups)] := DDone(cur);
    end;
    cur.A := nil;
    cur.N := 0;
    DPush(cur, AX);
    DPush(cur, AY);
    hasCur := True;
  end;

  procedure AddLine(AX0, AY0, AX1, AY1: Double);
  begin
    if not hasCur then Exit;
    if not (AroundEqual(AX0, AX1) and AroundEqual(AY0, AY1)) then
    begin
      DPush(cur, AX0);
      DPush(cur, AY0);
      DPush(cur, AX1);
      DPush(cur, AY1);
      DPush(cur, AX1);
      DPush(cur, AY1);
    end;
  end;

  procedure AddArc(AStart, AEnd, ACX, ACY, ARX, ARY: Double);
  var
    delta, alen, dir, c1, s1, c2, s2, ax1, ay1, ax4, ay4, hx, hy: Double;
  begin
    if not hasCur then Exit;
    delta := Abs(AEnd - AStart);
    alen := TyJsTan(delta / 4) * 4 / 3;
    if JsLess(AEnd, AStart) then dir := -1 else dir := 1;
    c1 := TyJsCos(AStart);
    s1 := TyJsSin(AStart);
    c2 := TyJsCos(AEnd);
    s2 := TyJsSin(AEnd);
    ax1 := c1 * ARX + ACX;
    ay1 := s1 * ARY + ACY;
    ax4 := c2 * ARX + ACX;
    ay4 := s2 * ARY + ACY;
    hx := ARX * alen * dir;
    hy := ARY * alen * dir;
    DPush(cur, ax1 - hx * s1);
    DPush(cur, ay1 + hy * c1);
    DPush(cur, ax4 + hx * s2);
    DPush(cur, ay4 - hy * c2);
    DPush(cur, ax4);
    DPush(cur, ay4);
  end;

var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    groups := nil;
    cur.A := nil;
    cur.N := 0;
    hasCur := False;
    xi := 0;
    yi := 0;
    x0 := 0;
    y0 := 0;
    len := Length(AData);
    i := 0;
    while i < len do
    begin
      cmd := ToInt32(AData[i]);
      Inc(i);
      isFirst := i = 1;
      if isFirst then
      begin
        { the previous point of a first L, C or Q is its own first point; a
          first arc is handled below }
        xi := At(AData, i);
        yi := At(AData, i + 1);
        x0 := xi;
        y0 := yi;
        if (cmd = TyZrCodeL) or (cmd = TyZrCodeC) or (cmd = TyZrCodeQ) then
        begin
          cur.A := nil;
          cur.N := 0;
          DPush(cur, x0);
          DPush(cur, y0);
          hasCur := True;
        end;
      end;
      case cmd of
        TyZrCodeM:
          begin
            x0 := At(AData, i);
            xi := x0;
            y0 := At(AData, i + 1);
            yi := y0;
            Inc(i, 2);
            CreateNewSubpath(x0, y0);
          end;
        TyZrCodeL:
          begin
            x1 := At(AData, i);
            y1 := At(AData, i + 1);
            Inc(i, 2);
            AddLine(xi, yi, x1, y1);
            xi := x1;
            yi := y1;
          end;
        TyZrCodeC:
          begin
            if hasCur then
            begin
              DPush(cur, At(AData, i));
              DPush(cur, At(AData, i + 1));
              DPush(cur, At(AData, i + 2));
              DPush(cur, At(AData, i + 3));
              DPush(cur, At(AData, i + 4));
              DPush(cur, At(AData, i + 5));
            end;
            xi := At(AData, i + 4);
            yi := At(AData, i + 5);
            Inc(i, 6);
          end;
        TyZrCodeQ:
          begin
            x1 := At(AData, i);
            y1 := At(AData, i + 1);
            x2 := At(AData, i + 2);
            y2 := At(AData, i + 3);
            Inc(i, 4);
            if hasCur then
            begin
              { the quadratic as a cubic }
              DPush(cur, xi + cTwoThirds * (x1 - xi));
              DPush(cur, yi + cTwoThirds * (y1 - yi));
              DPush(cur, x2 + cTwoThirds * (x1 - x2));
              DPush(cur, y2 + cTwoThirds * (y1 - y2));
              DPush(cur, x2);
              DPush(cur, y2);
            end;
            xi := x2;
            yi := y2;
          end;
        TyZrCodeA:
          begin
            cx := At(AData, i);
            cy := At(AData, i + 1);
            rx := At(AData, i + 2);
            ry := At(AData, i + 3);
            startAngle := At(AData, i + 4);
            endAngle := At(AData, i + 5) + startAngle;
            { the rotation is ignored upstream too }
            Inc(i, 7);
            anticlockwise := IsNan(At(AData, i)) or (At(AData, i) = 0);
            Inc(i);
            x1 := TyJsCos(startAngle) * rx + cx;
            y1 := TyJsSin(startAngle) * ry + cy;
            if isFirst then
            begin
              { the arc itself starts the path }
              x0 := x1;
              y0 := y1;
              CreateNewSubpath(x0, y0);
            end
            else
              { a line from the current point to the arc's start }
              AddLine(xi, yi, x1, y1);
            xi := TyJsCos(endAngle) * rx + cx;
            yi := TyJsSin(endAngle) * ry + cy;
            if anticlockwise then step := -Pi / 2 else step := Pi / 2;
            angle := startAngle;
            while (anticlockwise and JsLess(endAngle, angle))
              or ((not anticlockwise) and JsLess(angle, endAngle)) do
            begin
              if anticlockwise then nextAngle := JsMax(angle + step, endAngle)
              else nextAngle := JsMin(angle + step, endAngle);
              AddArc(angle, nextAngle, cx, cy, rx, ry);
              angle := angle + step;
            end;
          end;
        TyZrCodeR:
          begin
            x0 := At(AData, i);
            xi := x0;
            y0 := At(AData, i + 1);
            yi := y0;
            x1 := x0 + At(AData, i + 2);
            y1 := y0 + At(AData, i + 3);
            Inc(i, 4);
            { a rect is a subpath of its own }
            CreateNewSubpath(x1, y0);
            AddLine(x1, y0, x1, y1);
            AddLine(x1, y1, x0, y1);
            AddLine(x0, y1, x0, y0);
            AddLine(x0, y0, x1, y0);
          end;
        TyZrCodeZ:
          begin
            if hasCur then AddLine(xi, yi, x0, y0);
            xi := x0;
            yi := y0;
          end;
      end;
    end;
    if hasCur and (cur.N > 2) then
    begin
      SetLength(groups, Length(groups) + 1);
      groups[High(groups)] := DDone(cur);
    end;
    Result := groups;
  finally
    UnmaskFP(mask);
  end;
end;

{ adpativeBezier: a curve as points within two px over the scale }
procedure AdaptiveBezier(X0, Y0, X1, Y1, X2, Y2, X3, Y3: Double;
  var AOut: TDList; AScale: Double; ADepth: Integer);
var
  pixelDistance, pixelDistanceSqr, dx, dy, d, dx1, dy1, dx2, dy2, cp1LenSqr,
    cp2LenSqr, projLen1, projLen2, d1Sqr, d2Sqr: Double;
  sx, sy: TTyCubicSplit;
begin
  { a bezier that simulates a line }
  if AroundEqual(X0, X1) and AroundEqual(Y0, Y1) and AroundEqual(X2, X3)
    and AroundEqual(Y2, Y3) then
  begin
    DPush(AOut, X3);
    DPush(AOut, Y3);
    Exit;
  end;
  pixelDistance := 2 / AScale;
  pixelDistanceSqr := pixelDistance * pixelDistance;
  dx := X3 - X0;
  dy := Y3 - Y0;
  d := Sqrt(dx * dx + dy * dy);
  dx := dx / d;
  dy := dy / d;
  dx1 := X1 - X0;
  dy1 := Y1 - Y0;
  dx2 := X2 - X3;
  dy2 := Y2 - Y3;
  cp1LenSqr := dx1 * dx1 + dy1 * dy1;
  cp2LenSqr := dx2 * dx2 + dy2 * dy2;
  if JsLess(cp1LenSqr, pixelDistanceSqr) and JsLess(cp2LenSqr, pixelDistanceSqr) then
  begin
    DPush(AOut, X3);
    DPush(AOut, Y3);
    Exit;
  end;
  projLen1 := dx * dx1 + dy * dy1;
  projLen2 := -dx * dx2 - dy * dy2;
  d1Sqr := cp1LenSqr - projLen1 * projLen1;
  d2Sqr := cp2LenSqr - projLen2 * projLen2;
  if JsLess(d1Sqr, pixelDistanceSqr) and JsLessEq(0, projLen1)
    and JsLess(d2Sqr, pixelDistanceSqr) and JsLessEq(0, projLen2) then
  begin
    DPush(AOut, X3);
    DPush(AOut, Y3);
    Exit;
  end;
  { [deviation] a depth past which upstream would only find its stack's end }
  if ADepth >= 64 then
  begin
    DPush(AOut, X3);
    DPush(AOut, Y3);
    Exit;
  end;
  TyCubicSubdivide(X0, X1, X2, X3, 0.5, sx);
  TyCubicSubdivide(Y0, Y1, Y2, Y3, 0.5, sy);
  AdaptiveBezier(sx[0], sy[0], sx[1], sy[1], sx[2], sy[2], sx[3], sy[3], AOut, AScale, ADepth + 1);
  AdaptiveBezier(sx[4], sy[4], sx[5], sy[5], sx[6], sy[6], sx[7], sy[7], AOut, AScale, ADepth + 1);
end;

function TyPathToPolygons(const AData: array of Double; AScale: Double): TTyBezierCurves;
var
  groups: TTyBezierCurves;
  i, k: Integer;
  b: TTyDoubleArray;
  poly: TDList;
  x0, y0, x1, y1, x2, y2, x3, y3: Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    groups := TyPathToBezierCurves(AData);
    if IsNan(AScale) or (AScale = 0) then AScale := 1;
    SetLength(Result, Length(groups));
    for i := 0 to High(groups) do
    begin
      b := groups[i];
      poly.A := nil;
      poly.N := 0;
      x0 := AtD(b, 0);
      y0 := AtD(b, 1);
      DPush(poly, x0);
      DPush(poly, y0);
      k := 2;
      while k < Length(b) do
      begin
        x1 := AtD(b, k);
        y1 := AtD(b, k + 1);
        x2 := AtD(b, k + 2);
        y2 := AtD(b, k + 3);
        x3 := AtD(b, k + 4);
        y3 := AtD(b, k + 5);
        Inc(k, 6);
        AdaptiveBezier(x0, y0, x1, y1, x2, y2, x3, y3, poly, AScale, 0);
        x0 := x3;
        y0 := y3;
      end;
      Result[i] := DDone(poly);
    end;
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== morphPath.ts ==================== }

procedure TyAlignSubpath(const A1, A2: TTyDoubleArray; out O1, O2: TTyDoubleArray);
var
  len1, len2, shorterLen, i, k: Integer;
  shorter: TTyDoubleArray;
  diff, shorterBezierCount, eachCurveSubDivCount, remained, actual, kk, p,
    x0, y0, x1, y1, x2, y2, x3, y3: Double;
  sx, sy: TTyCubicSplit;
  sub: TDList;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    len1 := Length(A1);
    len2 := Length(A2);
    if len1 = len2 then
    begin
      O1 := A1;
      O2 := A2;
      Exit;
    end;
    if len1 < len2 then shorter := A1 else shorter := A2;
    shorterLen := Min(len1, len2);
    { should divide exactly }
    diff := Abs(len2 - len1) / 6;
    shorterBezierCount := (shorterLen - 2) / 6;
    { add `diff` beziers }
    eachCurveSubDivCount := JsCeil(diff / shorterBezierCount) + 1;
    sub.A := nil;
    sub.N := 0;
    DPush(sub, AtD(shorter, 0));
    DPush(sub, AtD(shorter, 1));
    remained := diff;
    i := 2;
    while i < shorterLen do
    begin
      x0 := AtD(shorter, i - 2);
      y0 := AtD(shorter, i - 1);
      x1 := AtD(shorter, i);
      y1 := AtD(shorter, i + 1);
      x2 := AtD(shorter, i + 2);
      y2 := AtD(shorter, i + 3);
      x3 := AtD(shorter, i + 4);
      y3 := AtD(shorter, i + 5);
      Inc(i, 6);
      if not (remained > 0) then
      begin
        DPush(sub, x1);
        DPush(sub, y1);
        DPush(sub, x2);
        DPush(sub, y2);
        DPush(sub, x3);
        DPush(sub, y3);
        Continue;
      end;
      actual := JsMin(remained, eachCurveSubDivCount - 1) + 1;
      k := 1;
      kk := 1;
      while JsLessEq(kk, actual) do
      begin
        p := kk / actual;
        TyCubicSubdivide(x0, x1, x2, x3, p, sx);
        TyCubicSubdivide(y0, y1, y2, y3, p, sy);
        { sx[3] = sx[4] }
        x0 := sx[3];
        y0 := sy[3];
        DPush(sub, sx[1]);
        DPush(sub, sy[1]);
        DPush(sub, sx[2]);
        DPush(sub, sy[2]);
        DPush(sub, x0);
        DPush(sub, y0);
        x1 := sx[5];
        y1 := sy[5];
        x2 := sx[6];
        y2 := sy[6];
        { the last point (x3, y3) is still the same }
        Inc(k);
        kk := k;
      end;
      remained := remained - (actual - 1);
    end;
    if len1 < len2 then
    begin
      O1 := DDone(sub);
      O2 := A2;
    end
    else
    begin
      O1 := A1;
      O2 := DDone(sub);
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function CreateSubpath(const ALast, AOther: TTyDoubleArray): TTyDoubleArray;
var
  len, i: Integer;
  lastX, lastY: Double;
begin
  len := Length(ALast);
  lastX := AtD(ALast, len - 2);
  lastY := AtD(ALast, len - 1);
  SetLength(Result, Length(AOther) + (Length(AOther) and 1));
  i := 0;
  while i < Length(AOther) do
  begin
    Result[i] := lastX;
    Inc(i);
    Result[i] := lastY;
    Inc(i);
  end;
end;

procedure TyAlignBezierCurves(const A1, A2: TTyBezierCurves; out O1, O2: TTyBezierCurves);
var
  i, n: Integer;
  last1, last2, s1, s2, n1, n2: TTyDoubleArray;
  hasLast1, hasLast2: Boolean;
begin
  n := Max(Length(A1), Length(A2));
  SetLength(O1, n);
  SetLength(O2, n);
  hasLast1 := False;
  hasLast2 := False;
  last1 := nil;
  last2 := nil;
  for i := 0 to n - 1 do
  begin
    if i <= High(A1) then s1 := A1[i] else s1 := nil;
    if i <= High(A2) then s2 := A2[i] else s2 := nil;
    if i > High(A1) then
    begin
      if hasLast1 then n1 := CreateSubpath(last1, s2) else n1 := CreateSubpath(s2, s2);
      n2 := s2;
    end
    else if i > High(A2) then
    begin
      if hasLast2 then n2 := CreateSubpath(last2, s1) else n2 := CreateSubpath(s1, s1);
      n1 := s1;
    end
    else
    begin
      TyAlignSubpath(s1, s2, n1, n2);
      last1 := n1;
      last2 := n2;
      hasLast1 := True;
      hasLast2 := True;
    end;
    O1[i] := n1;
    O2[i] := n2;
  end;
end;

function TyMorphCentroid(const A: TTyDoubleArray): TTyDoubleArray;
var
  signedArea, cx, cy, x0, y0, x1, y1, aa: Double;
  i, j, len: Integer;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    signedArea := 0;
    cx := 0;
    cy := 0;
    len := Length(A);
    { the polygon closed }
    i := 0;
    j := len - 2;
    while i < len do
    begin
      x0 := AtD(A, j);
      y0 := AtD(A, j + 1);
      x1 := AtD(A, i);
      y1 := AtD(A, i + 1);
      aa := x0 * y1 - x1 * y0;
      signedArea := signedArea + aa;
      cx := cx + (x0 + x1) * aa;
      cy := cy + (y0 + y1) * aa;
      j := i;
      Inc(i, 2);
    end;
    if JsEq(signedArea, 0) then
    begin
      SetLength(Result, 2);
      Result[0] := OrZero(AtD(A, 0));
      Result[1] := OrZero(AtD(A, 1));
      Exit;
    end;
    SetLength(Result, 3);
    Result[0] := cx / signedArea / 3;
    Result[1] := cy / signedArea / 3;
    Result[2] := signedArea;
  finally
    UnmaskFP(mask);
  end;
end;

function TyFindBestRingOffset(const AFrom, ATo, AFromCp, AToCp: TTyDoubleArray): Integer;
var
  bezierCount, bestScore, score, x0, y0, x1, y1, dx, dy: Double;
  offset, cursorOffset, k, idx, len, len2: Integer;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    bezierCount := (Length(AFrom) - 2) / 6;
    bestScore := Infinity;
    Result := 0;
    len := Length(AFrom);
    len2 := len - 2;
    offset := 0;
    while offset < bezierCount do
    begin
      cursorOffset := offset * 6;
      score := 0;
      k := 0;
      while k < len do
      begin
        if k = 0 then idx := cursorOffset
        else if len2 > 0 then idx := (cursorOffset + k - 2) mod len2 + 2
        else idx := -1;
        x0 := AtD(AFrom, idx) - AtD(AFromCp, 0);
        y0 := AtD(AFrom, idx + 1) - AtD(AFromCp, 1);
        x1 := AtD(ATo, k) - AtD(AToCp, 0);
        y1 := AtD(ATo, k + 1) - AtD(AToCp, 1);
        dx := x1 - x0;
        dy := y1 - y0;
        score := score + (dx * dx + dy * dy);
        Inc(k, 2);
      end;
      if JsLess(score, bestScore) then
      begin
        bestScore := score;
        Result := offset;
      end;
      Inc(offset);
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyMorphReverse(const A: TTyDoubleArray): TTyDoubleArray;
var len, i: Integer;
begin
  len := Length(A);
  SetLength(Result, len + (len and 1));
  i := 0;
  while i < len do
  begin
    Result[i] := AtD(A, len - i - 2);
    Result[i + 1] := AtD(A, len - i - 1);
    Inc(i, 2);
  end;
end;

{ the third of a centroid, `cp[2] < 0`: false for one that has none }
function CpNegative(const ACp: TTyDoubleArray): Boolean;
begin
  Result := (Length(ACp) > 2) and JsLess(ACp[2], 0);
end;

function TyFindBestMorphingRotation(const AFrom, ATo: TTyBezierCurves;
  AIterations: Integer; ARange: Double): TTyMorphData;
var
  i, k, m, len, len2, offset, idx: Integer;
  fromSub, toSub, fromCp, toCp, newFrom, newTo, tmp: TTyDoubleArray;
  decided, needsReverse: Boolean;
  bestAngle, bestScore, step, angle, sa, ca, score, x0, y0, x1, y1, nx1, ny1,
    dx, dy, half: Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    SetLength(Result, Length(AFrom));
    decided := False;
    needsReverse := False;
    for i := 0 to High(AFrom) do
    begin
      fromSub := AFrom[i];
      if i <= High(ATo) then toSub := ATo[i] else toSub := nil;
      fromCp := TyMorphCentroid(fromSub);
      toCp := TyMorphCentroid(toSub);
      if not decided then
      begin
        { reverse the source when the two run different ways round: the first
          pair decides for every subpath, so the winding rule holds }
        needsReverse := CpNegative(fromCp) <> CpNegative(toCp);
        decided := True;
      end;
      bestAngle := 0;
      bestScore := Infinity;
      len := Length(fromSub);
      if needsReverse then fromSub := TyMorphReverse(fromSub);
      offset := TyFindBestRingOffset(fromSub, toSub, fromCp, toCp) * 6;
      len2 := len - 2;
      SetLength(newFrom, Max(len, 2));
      k := 0;
      while k < len2 do
      begin
        { the start point not included }
        idx := (offset + k) mod len2 + 2;
        newFrom[k + 2] := AtD(fromSub, idx) - AtD(fromCp, 0);
        newFrom[k + 3] := AtD(fromSub, idx + 1) - AtD(fromCp, 1);
        Inc(k, 2);
      end;
      newFrom[0] := AtD(fromSub, offset) - AtD(fromCp, 0);
      newFrom[1] := AtD(fromSub, offset + 1) - AtD(fromCp, 1);
      if len < 2 then SetLength(newFrom, len);
      { the target never improved on: undefined everywhere }
      SetLength(newTo, Length(fromSub));
      for k := 0 to High(newTo) do newTo[k] := NaN;
      SetLength(tmp, Length(fromSub));
      if AIterations > 0 then
      begin
        step := ARange / AIterations;
        half := ARange / 2;
        angle := -ARange / 2;
        while JsLessEq(angle, half) do
        begin
          sa := TyJsSin(angle);
          ca := TyJsCos(angle);
          score := 0;
          k := 0;
          while k < Length(fromSub) do
          begin
            x0 := AtD(newFrom, k);
            y0 := AtD(newFrom, k + 1);
            x1 := AtD(toSub, k) - AtD(toCp, 0);
            y1 := AtD(toSub, k + 1) - AtD(toCp, 1);
            { the turn on the target point }
            nx1 := x1 * ca - y1 * sa;
            ny1 := x1 * sa + y1 * ca;
            tmp[k] := nx1;
            if k + 1 <= High(tmp) then tmp[k + 1] := ny1;
            dx := nx1 - x0;
            dy := ny1 - y0;
            score := score + (dx * dx + dy * dy);
            Inc(k, 2);
          end;
          if JsLess(score, bestScore) then
          begin
            bestScore := score;
            bestAngle := angle;
            for m := 0 to High(tmp) do newTo[m] := tmp[m];
          end;
          angle := angle + step;
        end;
      end
      else
      begin
        k := 0;
        while k < len do
        begin
          newTo[k] := AtD(toSub, k) - AtD(toCp, 0);
          if k + 1 <= High(newTo) then newTo[k + 1] := AtD(toSub, k + 1) - AtD(toCp, 1);
          Inc(k, 2);
        end;
      end;
      Result[i].From := Copy(newFrom, 0, Length(newFrom));
      Result[i].Dest := Copy(newTo, 0, Length(newTo));
      Result[i].FromCp := fromCp;
      Result[i].DestCp := toCp;
      Result[i].Rotation := -bestAngle;
      newFrom := nil;
      newTo := nil;
      tmp := nil;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyApplyTransformOnBeziers(var ACurves: TTyBezierCurves; const M: TTyMat2D);
var
  i, k: Integer;
  x, y: Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    for i := 0 to High(ACurves) do
    begin
      k := 0;
      while k < Length(ACurves[i]) do
      begin
        x := ACurves[i][k];
        y := AtD(ACurves[i], k + 1);
        ACurves[i][k] := M[0] * x + M[2] * y + M[4];
        Inc(k);
        if k <= High(ACurves[i]) then ACurves[i][k] := M[1] * x + M[3] * y + M[5];
        Inc(k);
      end;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyPrepareMorph(const AFrom: array of Double; AFromHasM: Boolean;
  const AFromM: TTyMat2D; const ATo: array of Double; AToHasM: Boolean;
  const AToM: TTyMat2D): TTyMorphData;
var
  fb, tb, af, at_: TTyBezierCurves;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    fb := TyPathToBezierCurves(AFrom);
    tb := TyPathToBezierCurves(ATo);
    TyAlignBezierCurves(fb, tb, af, at_);
    if AFromHasM then TyApplyTransformOnBeziers(af, AFromM);
    if AToHasM then TyApplyTransformOnBeziers(at_, AToM);
    Result := TyFindBestMorphingRotation(af, at_, 10, Pi);
  finally
    UnmaskFP(mask);
  end;
end;

function TyMorphPathData(const AData: TTyMorphData; AT: Double): TTyDoubleArray;
var
  out_: TDList;
  tmp: TTyDoubleArray;
  i, m, n: Integer;
  onet, angle, sa, ca, ncx, ncy, x0, y0, x1, y1, x2, y2, x3, y3, x, y: Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    out_.A := nil;
    out_.N := 0;
    onet := 1 - AT;
    tmp := nil;
    for i := 0 to High(AData) do
    begin
      angle := AData[i].Rotation * AT;
      sa := TyJsSin(angle);
      ca := TyJsCos(angle);
      { lerp(newCp, fromCp, toCp, t) }
      ncx := AtD(AData[i].FromCp, 0) + AT * (AtD(AData[i].DestCp, 0) - AtD(AData[i].FromCp, 0));
      ncy := AtD(AData[i].FromCp, 1) + AT * (AtD(AData[i].DestCp, 1) - AtD(AData[i].FromCp, 1));
      n := Length(AData[i].From);
      if Length(tmp) < n + 1 then SetLength(tmp, n + 1);
      m := 0;
      while m < n do
      begin
        x0 := AData[i].From[m];
        y0 := AtD(AData[i].From, m + 1);
        x1 := AtD(AData[i].Dest, m);
        y1 := AtD(AData[i].Dest, m + 1);
        x := x0 * onet + x1 * AT;
        y := y0 * onet + y1 * AT;
        tmp[m] := (x * ca - y * sa) + ncx;
        tmp[m + 1] := (x * sa + y * ca) + ncy;
        Inc(m, 2);
      end;
      x0 := tmp[0];
      y0 := tmp[1];
      DPush(out_, TyZrCodeM);
      DPush(out_, x0);
      DPush(out_, y0);
      m := 2;
      while m < n do
      begin
        x1 := AtD(tmp, m);
        y1 := AtD(tmp, m + 1);
        x2 := AtD(tmp, m + 2);
        y2 := AtD(tmp, m + 3);
        x3 := AtD(tmp, m + 4);
        y3 := AtD(tmp, m + 5);
        Inc(m, 6);
        { a curve on its own ends is a line }
        if JsEq(x0, x1) and JsEq(y0, y1) and JsEq(x2, x3) and JsEq(y2, y3) then
        begin
          DPush(out_, TyZrCodeL);
          DPush(out_, x3);
          DPush(out_, y3);
        end
        else
        begin
          DPush(out_, TyZrCodeC);
          DPush(out_, x1);
          DPush(out_, y1);
          DPush(out_, x2);
          DPush(out_, y2);
          DPush(out_, x3);
          DPush(out_, y3);
        end;
        x0 := x3;
        y0 := y3;
      end;
    end;
    Result := DDone(out_);
  finally
    UnmaskFP(mask);
  end;
end;

function TyMorphDataCmds(const AData: TTyDoubleArray): TTyPathCmdArray;
var
  i, n, code: Integer;

  procedure Add(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double);
  begin
    if n >= Length(Result) then SetLength(Result, n * 2 + 8);
    Result[n].Kind := AKind;
    Result[n].X1 := AX1;
    Result[n].Y1 := AY1;
    Result[n].X2 := AX2;
    Result[n].Y2 := AY2;
    Result[n].X := AX;
    Result[n].Y := AY;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  i := 0;
  while i < Length(AData) do
  begin
    code := ToInt32(AData[i]);
    Inc(i);
    case code of
      TyZrCodeM:
        begin
          Add(pckMove, 0, 0, 0, 0, AtD(AData, i), AtD(AData, i + 1));
          Inc(i, 2);
        end;
      TyZrCodeL:
        begin
          Add(pckLine, 0, 0, 0, 0, AtD(AData, i), AtD(AData, i + 1));
          Inc(i, 2);
        end;
      TyZrCodeC:
        begin
          Add(pckCurve, AtD(AData, i), AtD(AData, i + 1), AtD(AData, i + 2),
            AtD(AData, i + 3), AtD(AData, i + 4), AtD(AData, i + 5));
          Inc(i, 6);
        end;
      TyZrCodeZ:
        Add(pckClose, 0, 0, 0, 0, 0, 0);
    else
      Break;
    end;
  end;
  SetLength(Result, n);
end;

function TyMorphHilbert(AX, AY, AMinX, AMinY, AMaxX, AMaxY: Double): Double;
var
  x, y, s, rx, ry, tmp: LongInt;
  d: Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    if JsEq(AMaxX, AMinX) then x := 0
    else x := ToInt32(TyJsRound(32767 * (AX - AMinX) / (AMaxX - AMinX)));
    if JsEq(AMaxY, AMinY) then y := 0
    else y := ToInt32(TyJsRound(32767 * (AY - AMinY) / (AMaxY - AMinY)));
    d := 0;
    { s runs on below one upstream, where `x & s` is nought and only x and y
      trade places: d is done at one }
    s := (1 shl 16) div 2;
    while s > 0 do
    begin
      rx := 0;
      ry := 0;
      if (x and s) > 0 then rx := 1;
      if (y and s) > 0 then ry := 1;
      d := d + Double(s) * s * ((3 * rx) xor ry);
      if ry = 0 then
      begin
        if rx = 1 then
        begin
          x := s - 1 - x;
          y := s - 1 - y;
        end;
        tmp := x;
        x := y;
        y := tmp;
      end;
      s := s div 2;
    end;
    Result := d;
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== dividePath.ts ==================== }

function TyDividingGrids(ADim0, ADim1: Double; ARowDim, ACount: Integer): TTyDoubleArray;
var
  rowSize, columnSize, ratio, rowCount, columnCount, currentCount, remained: Double;
  i, n, rc: Integer;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    Result := nil;
    if ARowDim = 0 then
    begin
      rowSize := ADim0;
      columnSize := ADim1;
    end
    else
    begin
      rowSize := ADim1;
      columnSize := ADim0;
    end;
    ratio := Abs(rowSize / columnSize);
    rowCount := JsCeil(Sqrt(ratio * ACount));
    columnCount := JsFloor(ACount / rowCount);
    if JsEq(columnCount, 0) then
    begin
      columnCount := 1;
      rowCount := ACount;
    end;
    if IsNan(rowCount) or not (rowCount > 0) then Exit;
    { rowCount <= count here: a larger one leaves no column }
    rc := Trunc(rowCount);
    SetLength(Result, rc);
    for i := 0 to rc - 1 do Result[i] := columnCount;
    currentCount := rowCount * columnCount;
    remained := ACount - currentCount;
    if remained > 0 then
    begin
      n := Trunc(remained);
      for i := 0 to n - 1 do
        Result[i mod rc] := Result[i mod rc] + 1;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyDivideRect(AX, AY, AW, AH: Double; ACount: Integer): TTyDividePieceArray;
var
  grids: TTyDoubleArray;
  horiz: Boolean;
  rowSize, columnSize, rowLen, colLen: Double;
  row, column, n: Integer;
  pc: TTyDividePiece;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    Result := nil;
    horiz := JsLess(AH, AW);
    grids := TyDividingGrids(AW, AH, Ord(not horiz), ACount);
    if horiz then
    begin
      rowLen := AW;
      colLen := AH;
    end
    else
    begin
      rowLen := AH;
      colLen := AW;
    end;
    rowSize := rowLen / Length(grids);
    n := 0;
    for row := 0 to High(grids) do
    begin
      columnSize := colLen / grids[row];
      column := 0;
      while column < grids[row] do
      begin
        pc := Default(TTyDividePiece);
        pc.Kind := dkRect;
        if horiz then
        begin
          pc.X := row * rowSize;
          pc.Y := column * columnSize;
          pc.W := rowSize;
          pc.H := columnSize;
        end
        else
        begin
          pc.Y := row * rowSize;
          pc.X := column * columnSize;
          pc.H := rowSize;
          pc.W := columnSize;
        end;
        pc.X := pc.X + AX;
        pc.Y := pc.Y + AY;
        SetLength(Result, n + 1);
        Result[n] := pc;
        Inc(n);
        Inc(column);
      end;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyDivideSector(ACX, ACY, AR0, AR, AStart, AEnd: Double; AHasClockwise,
  AClockwise: Boolean; ACount: Integer): TTyDividePieceArray;
var
  angle, arcLen, deltaR, rowSize, columnSize: Double;
  isAngleRow: Boolean;
  grids: TTyDoubleArray;
  row, column, n: Integer;
  pc: TTyDividePiece;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    Result := nil;
    angle := Abs(AEnd - AStart);
    arcLen := angle * AR;
    deltaR := AR - AR0;
    isAngleRow := JsLess(Abs(deltaR), arcLen);
    grids := TyDividingGrids(arcLen, deltaR, Ord(not isAngleRow), ACount);
    if isAngleRow then rowSize := angle / Length(grids)
    else rowSize := deltaR / Length(grids);
    n := 0;
    for row := 0 to High(grids) do
    begin
      if isAngleRow then columnSize := deltaR / grids[row]
      else columnSize := angle / grids[row];
      column := 0;
      while column < grids[row] do
      begin
        pc := Default(TTyDividePiece);
        pc.Kind := dkSector;
        if isAngleRow then
        begin
          pc.StartAngle := AStart + rowSize * row;
          pc.EndAngle := AStart + rowSize * (row + 1);
          pc.R0 := AR0 + columnSize * column;
          pc.R := AR0 + columnSize * (column + 1);
        end
        else
        begin
          pc.StartAngle := AStart + columnSize * column;
          pc.EndAngle := AStart + columnSize * (column + 1);
          pc.R0 := AR0 + rowSize * row;
          pc.R := AR0 + rowSize * (row + 1);
        end;
        pc.HasClockwise := AHasClockwise;
        pc.Clockwise := AClockwise;
        pc.CX := ACX;
        pc.CY := ACY;
        SetLength(Result, n + 1);
        Result[n] := pc;
        Inc(n);
        Inc(column);
      end;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

type
  { the polygon dividers' state: the pieces, and the sort's comparator }
  TPolyDivider = class
  public
    Pieces: TTyDividePieceArray;
    Keys: TTyDoubleArray;
    Descending: Boolean;
    function Compare(A, B: Integer): Integer;
    procedure Emit(const APoints: TTyDoubleArray);
    procedure Recurse(const APoints: TTyDoubleArray; ACount: Integer);
  end;

function TPolyDivider.Compare(A, B: Integer): Integer;
var d: Double;
begin
  if Descending then d := Keys[B] - Keys[A] else d := Keys[A] - Keys[B];
  if IsNan(d) or (d = 0) then Result := 0
  else if d < 0 then Result := -1
  else Result := 1;
end;

procedure TPolyDivider.Emit(const APoints: TTyDoubleArray);
var n: Integer;
begin
  n := Length(Pieces);
  SetLength(Pieces, n + 1);
  Pieces[n] := Default(TTyDividePiece);
  Pieces[n].Kind := dkPolygon;
  Pieces[n].Points := APoints;
end;

{ lineLineIntersect: AOk False for parallel, or p outside [0, 1] }
function LineLineIntersect(A1X, A1Y, A2X, A2Y, B1X, B1Y, B2X, B2Y: Double;
  out AX, AY: Double): Boolean;
var mx, my, nx, ny, nm, b1a1x, b1a1y, p: Double;
begin
  mx := A2X - A1X;
  my := A2Y - A1Y;
  nx := B2X - B1X;
  ny := B2Y - B1Y;
  { crossProduct2d(nx, ny, mx, my) }
  nm := nx * my - mx * ny;
  AX := NaN;
  AY := NaN;
  if JsLess(Abs(nm), cTiny) then Exit(False);
  b1a1x := A1X - B1X;
  b1a1y := A1Y - B1Y;
  p := (b1a1x * ny - nx * b1a1y) / nm;
  if JsLess(p, 0) or JsLess(1, p) then Exit(False);
  { p2 is an infinite line }
  AX := p * mx + A1X;
  AY := p * my + A1Y;
  Result := True;
end;

{ projPtOnLine: the point's run along the line's unit direction }
function ProjPtOnLine(PX, PY, AX, AY, BX, BY: Double): Double;
var dx, dy, l, ex, ey: Double;
begin
  dx := BX - AX;
  dy := BY - AY;
  l := Sqrt(dx * dx + dy * dy);
  dx := dx / l;
  dy := dy / l;
  ex := PX - AX;
  ey := PY - AY;
  Result := ex * dx + ey * dy;
end;

procedure AddToPoly(var APoly: TDList; AX, AY: Double);
begin
  if (APoly.N >= 2) and JsEq(APoly.A[APoly.N - 2], AX) and JsEq(APoly.A[APoly.N - 1], AY) then
    Exit;
  DPush(APoly, AX);
  DPush(APoly, AY);
end;

{ splitPolygonByLine: two polygons, or the same points twice for fewer than
  two crossings }
procedure SplitPolygonByLine(const APoints: TTyDoubleArray; AX, AY, BX, BY: Double;
  out P1, P2: TTyDoubleArray);
var
  len, i, n, idx0, idx1, cnt: Integer;
  ix, iy: Double;
  xs, ys, projs: TTyDoubleArray;
  idxs, order: TTyIntegerArray;
  srt: TPolyDivider;
  pa, pb: TDList;
  s0x, s0y, s1x, s1y: Double;
  k: Integer;
begin
  len := Length(APoints) div 2;
  n := 0;
  xs := nil; ys := nil; projs := nil; idxs := nil;
  for i := 0 to len - 1 do
  begin
    if LineLineIntersect(APoints[i * 2], APoints[i * 2 + 1],
      APoints[((i + 1) mod len) * 2], APoints[((i + 1) mod len) * 2 + 1],
      AX, AY, BX, BY, ix, iy) then
    begin
      SetLength(xs, n + 1); SetLength(ys, n + 1); SetLength(projs, n + 1); SetLength(idxs, n + 1);
      xs[n] := ix;
      ys[n] := iy;
      projs[n] := ProjPtOnLine(ix, iy, AX, AY, BX, BY);
      idxs[n] := i;
      Inc(n);
    end;
  end;
  if n < 2 then
  begin
    { clone }
    P1 := APoints;
    P2 := APoints;
    Exit;
  end;
  { the two farthest crossings }
  SetLength(order, n);
  for i := 0 to n - 1 do order[i] := i;
  srt := TPolyDivider.Create;
  try
    srt.Keys := projs;
    srt.Descending := False;
    TyJsArraySort(order, @srt.Compare);
  finally
    srt.Free;
  end;
  idx0 := order[0];
  idx1 := order[n - 1];
  if idxs[idx1] < idxs[idx0] then
  begin
    k := idx0;
    idx0 := idx1;
    idx1 := k;
  end;
  s0x := xs[idx0]; s0y := ys[idx0];
  s1x := xs[idx1]; s1y := ys[idx1];
  pa.A := nil; pa.N := 0;
  pb.A := nil; pb.N := 0;
  DPush(pa, s0x); DPush(pa, s0y);
  DPush(pb, s1x); DPush(pb, s1y);
  for i := idxs[idx0] + 1 to idxs[idx1] do
    AddToPoly(pa, APoints[i * 2], APoints[i * 2 + 1]);
  AddToPoly(pa, s1x, s1y);
  { close the path }
  AddToPoly(pa, s0x, s0y);
  cnt := idxs[idx0] + len;
  for i := idxs[idx1] + 1 to cnt do
    AddToPoly(pb, APoints[(i mod len) * 2], APoints[(i mod len) * 2 + 1]);
  AddToPoly(pb, s0x, s0y);
  AddToPoly(pb, s1x, s1y);
  P1 := DDone(pa);
  P2 := DDone(pb);
end;

procedure BinaryDividePolygon(const APoints: TTyDoubleArray; out P1, P2: TTyDoubleArray);
var
  i, n: Integer;
  left, right, top, bottom, x, y, w, h, ax, ay, bx, by: Double;
begin
  n := Length(APoints) div 2;
  { fromPoints over none leaves min / max undefined }
  left := NaN; right := NaN; top := NaN; bottom := NaN;
  if n > 0 then
  begin
    left := APoints[0]; right := APoints[0];
    top := APoints[1]; bottom := APoints[1];
    for i := 1 to n - 1 do
    begin
      left := JsMin(left, APoints[i * 2]);
      right := JsMax(right, APoints[i * 2]);
      top := JsMin(top, APoints[i * 2 + 1]);
      bottom := JsMax(bottom, APoints[i * 2 + 1]);
    end;
  end;
  x := left;
  y := top;
  w := right - left;
  h := bottom - top;
  if JsLess(h, w) then
  begin
    ax := x + w / 2;
    bx := ax;
    ay := y;
    by := y + h;
  end
  else
  begin
    ay := y + h / 2;
    by := ay;
    ax := x;
    bx := x + w;
  end;
  SplitPolygonByLine(APoints, ax, ay, bx, by, P1, P2);
end;

procedure TPolyDivider.Recurse(const APoints: TTyDoubleArray; ACount: Integer);
var
  mid: Integer;
  a, b: TTyDoubleArray;
begin
  if ACount = 1 then
  begin
    Emit(APoints);
    Exit;
  end;
  { [deviation] nought (an empty polygon's share) divides into nothing;
    upstream recurses until its stack goes }
  if ACount < 1 then Exit;
  mid := ACount div 2;
  BinaryDividePolygon(APoints, a, b);
  Recurse(a, mid);
  Recurse(b, ACount - mid);
end;

function TyDividePolygons(const APolygons: TTyBezierCurves; ACount: Integer): TTyDividePieceArray;
var
  dv: TPolyDivider;
  i, k, n, left, selfCount: Integer;
  areas: TTyDoubleArray;
  order: TTyIntegerArray;
  totalArea, l, r, t, b, sc: Double;
  p: TTyDoubleArray;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    dv := TPolyDivider.Create;
    try
      n := Length(APolygons);
      if n = 0 then
      begin
        { [deviation] upstream divides `undefined`: one empty polygon for one,
          a TypeError for more }
        if ACount = 1 then dv.Emit(nil);
      end
      else if n = ACount then
      begin
        { batched paths split into non-batched ones: no division }
        for i := 0 to n - 1 do dv.Emit(APolygons[i]);
      end
      else
      begin
        { several subpaths: each takes a share by the area of its rect }
        totalArea := 0;
        SetLength(areas, n);
        for i := 0 to n - 1 do
        begin
          p := APolygons[i];
          l := NaN; r := NaN; t := NaN; b := NaN;
          if Length(p) >= 2 then
          begin
            l := p[0]; r := p[0]; t := p[1]; b := p[1];
            k := 1;
            while k * 2 + 1 <= High(p) do
            begin
              l := JsMin(l, p[k * 2]);
              r := JsMax(r, p[k * 2]);
              t := JsMin(t, p[k * 2 + 1]);
              b := JsMax(b, p[k * 2 + 1]);
              Inc(k);
            end;
          end;
          areas[i] := (b - t) * (r - l);
          totalArea := totalArea + areas[i];
        end;
        SetLength(order, n);
        for i := 0 to n - 1 do order[i] := i;
        dv.Keys := areas;
        dv.Descending := True;
        TyJsArraySort(order, @dv.Compare);
        left := ACount;
        for i := 0 to n - 1 do
        begin
          if left <= 0 then Break;
          if i = n - 1 then selfCount := left
          else
          begin
            sc := JsCeil(areas[order[i]] / totalArea * ACount);
            if IsNan(sc) or IsInfinite(sc) then selfCount := 0
            else selfCount := Trunc(sc);
          end;
          if selfCount < 0 then Continue;
          dv.Recurse(APolygons[order[i]], selfCount);
          left := left - selfCount;
        end;
      end;
      Result := dv.Pieces;
    finally
      dv.Free;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyCloneOpacity(AOpacity: Double; ACount: Integer): Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    Result := 1 - TyJsPow(1 - AOpacity, 1 / ACount);
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== morphTransitionHelper.ts ==================== }

function TyPrepareMorphBatches(const AOne: array of Integer;
  const AMany: array of TTyIntegerArray): TTyMorphBatchArray;
var
  batchCount, i, k, len, mid, off, n: Integer;
  moveFrom: TTyIntegerArray;
begin
  batchCount := Length(AOne);
  SetLength(Result, batchCount);
  for i := 0 to batchCount - 1 do
  begin
    Result[i].One := AOne[i];
    Result[i].Many := nil;
  end;
  if batchCount = 0 then Exit;
  for i := 0 to High(AMany) do
    for k := 0 to High(AMany[i]) do
    begin
      n := Length(Result[k mod batchCount].Many);
      SetLength(Result[k mod batchCount].Many, n + 1);
      Result[k mod batchCount].Many[n] := AMany[i][k];
    end;
  off := 0;
  { one has more paths than each of many: average them }
  for i := batchCount - 1 downto 0 do
  begin
    if Length(Result[i].Many) = 0 then
    begin
      moveFrom := Copy(Result[off].Many, 0, Length(Result[off].Many));
      if Length(moveFrom) <= 1 then
      begin
        { not enough: start from the first one }
        if off <> 0 then off := 0
        else Exit;
      end;
      len := Length(moveFrom);
      mid := Trunc(JsCeil(len / 2));
      Result[i].Many := Copy(moveFrom, mid, len - mid);
      Result[off].Many := Copy(moveFrom, 0, mid);
      Inc(off);
    end;
  end;
end;

{ ==================== bbox.ts, PathProxy.ts, Path.ts, Transformable.ts [Batch 137, D5 UT2] ==================== }

const
  cBoxEps: Double = 1e-8;
  cArcEps: Double = 1e-4;
  cTfEps: Double = 5e-5;
  cScaleEps: Double = 1e-10;
  cHalfPi: Double = Pi / 2;
  cTwoPi: Double = Pi * 2;

{ Math.min / Math.max of three, left to right }
function JsMin3(A, B, C: Double): Double;
begin
  Result := JsMin(JsMin(A, B), C);
end;

function JsMax3(A, B, C: Double): Double;
begin
  Result := JsMax(JsMax(A, B), C);
end;

function CubicAtB(P0, P1, P2, P3, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * onet * (onet * P0 + 3 * T * P1) + T * T * (T * P3 + 3 * onet * P2);
end;

{ cubicExtrema -- a double root is found and NOT counted, as upstream }
function CubicExtremaB(P0, P1, P2, P3: Double; out E0, E1: Double): Integer;
var a, b, c, disc, ds, t1, t2: Double;
begin
  Result := 0;
  E0 := NaN;
  E1 := NaN;
  b := 6 * P2 - 12 * P1 + 6 * P0;
  a := 9 * P1 + 3 * P3 - 3 * P0 - 9 * P2;
  c := 3 * P1 - 3 * P0;
  if (a > -cBoxEps) and (a < cBoxEps) then
  begin
    if (b > cBoxEps) or (b < -cBoxEps) then
    begin
      t1 := -c / b;
      if (t1 >= 0) and (t1 <= 1) then
      begin
        E0 := t1;
        Result := 1;
      end;
    end;
  end
  else
  begin
    disc := b * b - 4 * a * c;
    if (disc > -cBoxEps) and (disc < cBoxEps) then
      E0 := -b / (2 * a)
    else if disc > 0 then
    begin
      ds := Sqrt(disc);
      t1 := (-b + ds) / (2 * a);
      t2 := (-b - ds) / (2 * a);
      if (t1 >= 0) and (t1 <= 1) then
      begin
        E0 := t1;
        Result := 1;
      end;
      if (t2 >= 0) and (t2 <= 1) then
      begin
        if Result = 0 then E0 := t2 else E1 := t2;
        Inc(Result);
      end;
    end;
  end;
end;

procedure FromCubicB(X0, Y0, X1, Y1, X2, Y2, X3, Y3: Double; out MinX, MinY, MaxX, MaxY: Double);
var
  n, i: Integer;
  e: array[0..1] of Double;
  v: Double;
begin
  n := CubicExtremaB(X0, X1, X2, X3, e[0], e[1]);
  MinX := Infinity;
  MinY := Infinity;
  MaxX := NegInfinity;
  MaxY := NegInfinity;
  for i := 0 to n - 1 do
  begin
    v := CubicAtB(X0, X1, X2, X3, e[i]);
    MinX := JsMin(v, MinX);
    MaxX := JsMax(v, MaxX);
  end;
  n := CubicExtremaB(Y0, Y1, Y2, Y3, e[0], e[1]);
  for i := 0 to n - 1 do
  begin
    v := CubicAtB(Y0, Y1, Y2, Y3, e[i]);
    MinY := JsMin(v, MinY);
    MaxY := JsMax(v, MaxY);
  end;
  MinX := JsMin(X0, MinX);
  MaxX := JsMax(X0, MaxX);
  MinX := JsMin(X3, MinX);
  MaxX := JsMax(X3, MaxX);
  MinY := JsMin(Y0, MinY);
  MaxY := JsMax(Y0, MaxY);
  MinY := JsMin(Y3, MinY);
  MaxY := JsMax(Y3, MaxY);
end;

function QuadExtremumB(P0, P1, P2: Double): Double;
var d: Double;
begin
  d := P0 + P2 - 2 * P1;
  if JsEq(d, 0) then Result := 0.5 else Result := (P0 - P1) / d;
end;

function QuadAtB(P0, P1, P2, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * (onet * P0 + 2 * T * P1) + T * T * P2;
end;

procedure FromQuadB(X0, Y0, X1, Y1, X2, Y2: Double; out MinX, MinY, MaxX, MaxY: Double);
var tx, ty, x, y: Double;
begin
  tx := JsMax(JsMin(QuadExtremumB(X0, X1, X2), 1), 0);
  ty := JsMax(JsMin(QuadExtremumB(Y0, Y1, Y2), 1), 0);
  x := QuadAtB(X0, X1, X2, tx);
  y := QuadAtB(Y0, Y1, Y2, ty);
  MinX := JsMin3(X0, X2, x);
  MinY := JsMin3(Y0, Y2, y);
  MaxX := JsMax3(X0, X2, x);
  MaxY := JsMax3(Y0, Y2, y);
end;

procedure FromArcB(X, Y, RX, RY, AStart, AEnd: Double; AAnti: Boolean;
  out MinX, MinY, MaxX, MaxY: Double);
var diff, sx, sy, ex, ey, angle, t: Double;
begin
  diff := Abs(AStart - AEnd);
  if JsLess(TyJsFMod(diff, cTwoPi), cArcEps) and JsLess(cArcEps, diff) then
  begin
    { a circle }
    MinX := X - RX;
    MinY := Y - RY;
    MaxX := X + RX;
    MaxY := Y + RY;
    Exit;
  end;
  sx := TyJsCos(AStart) * RX + X;
  sy := TyJsSin(AStart) * RY + Y;
  ex := TyJsCos(AEnd) * RX + X;
  ey := TyJsSin(AEnd) * RY + Y;
  MinX := JsMin(sx, ex);
  MinY := JsMin(sy, ey);
  MaxX := JsMax(sx, ex);
  MaxY := JsMax(sy, ey);
  { to [0, 2 pi] }
  AStart := TyJsFMod(AStart, cTwoPi);
  if AStart < 0 then AStart := AStart + cTwoPi;
  AEnd := TyJsFMod(AEnd, cTwoPi);
  if AEnd < 0 then AEnd := AEnd + cTwoPi;
  if (AStart > AEnd) and not AAnti then AEnd := AEnd + cTwoPi
  else if (AStart < AEnd) and AAnti then AStart := AStart + cTwoPi;
  if AAnti then
  begin
    t := AEnd;
    AEnd := AStart;
    AStart := t;
  end;
  angle := 0;
  while angle < AEnd do
  begin
    if angle > AStart then
    begin
      sx := TyJsCos(angle) * RX + X;
      sy := TyJsSin(angle) * RY + Y;
      MinX := JsMin(MinX, sx);
      MinY := JsMin(MinY, sy);
      MaxX := JsMax(MaxX, sx);
      MaxY := JsMax(MaxY, sy);
    end;
    angle := angle + cHalfPi;
  end;
end;

function TyPathDataRect(const AData: array of Double): TTyXYWH;
var
  mnX, mnY, mxX, mxY, m2x, m2y, x2x, x2y, xi, yi, x0, y0: Double;
  cx, cy, rx, ry, sa, ea, w, h: Double;
  i, cmd, n: Integer;
  isFirst, anti: Boolean;
  mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    mnX := MaxDouble; mnY := MaxDouble; m2x := MaxDouble; m2y := MaxDouble;
    mxX := -MaxDouble; mxY := -MaxDouble; x2x := -MaxDouble; x2y := -MaxDouble;
    xi := 0; yi := 0; x0 := 0; y0 := 0;
    n := Length(AData);
    i := 0;
    while i < n do
    begin
      cmd := Round(AData[i]);
      Inc(i);
      isFirst := i = 1;
      if isFirst then
      begin
        xi := At(AData, i);
        yi := At(AData, i + 1);
        x0 := xi;
        y0 := yi;
      end;
      case cmd of
        TyZrCodeM:
          begin
            xi := At(AData, i); x0 := xi;
            yi := At(AData, i + 1); y0 := yi;
            Inc(i, 2);
            m2x := x0; m2y := y0;
            x2x := x0; x2y := y0;
          end;
        TyZrCodeL:
          begin
            { fromLine }
            m2x := JsMin(xi, At(AData, i));
            m2y := JsMin(yi, At(AData, i + 1));
            x2x := JsMax(xi, At(AData, i));
            x2y := JsMax(yi, At(AData, i + 1));
            xi := At(AData, i);
            yi := At(AData, i + 1);
            Inc(i, 2);
          end;
        TyZrCodeC:
          begin
            FromCubicB(xi, yi, At(AData, i), At(AData, i + 1), At(AData, i + 2), At(AData, i + 3),
              At(AData, i + 4), At(AData, i + 5), m2x, m2y, x2x, x2y);
            xi := At(AData, i + 4);
            yi := At(AData, i + 5);
            Inc(i, 6);
          end;
        TyZrCodeQ:
          begin
            FromQuadB(xi, yi, At(AData, i), At(AData, i + 1), At(AData, i + 2), At(AData, i + 3),
              m2x, m2y, x2x, x2y);
            xi := At(AData, i + 2);
            yi := At(AData, i + 3);
            Inc(i, 4);
          end;
        TyZrCodeA:
          begin
            cx := At(AData, i);
            cy := At(AData, i + 1);
            rx := At(AData, i + 2);
            ry := At(AData, i + 3);
            sa := At(AData, i + 4);
            ea := At(AData, i + 5) + sa;
            { the rotation, then !anticlockwise as stored }
            anti := not ((not IsNan(At(AData, i + 7))) and (At(AData, i + 7) <> 0));
            Inc(i, 8);
            if isFirst then
            begin
              x0 := TyJsCos(sa) * rx + cx;
              y0 := TyJsSin(sa) * ry + cy;
            end;
            FromArcB(cx, cy, rx, ry, sa, ea, anti, m2x, m2y, x2x, x2y);
            xi := TyJsCos(ea) * rx + cx;
            yi := TyJsSin(ea) * ry + cy;
          end;
        TyZrCodeR:
          begin
            xi := At(AData, i); x0 := xi;
            yi := At(AData, i + 1); y0 := yi;
            w := At(AData, i + 2);
            h := At(AData, i + 3);
            Inc(i, 4);
            m2x := JsMin(x0, x0 + w);
            m2y := JsMin(y0, y0 + h);
            x2x := JsMax(x0, x0 + w);
            x2y := JsMax(y0, y0 + h);
          end;
        TyZrCodeZ:
          begin
            xi := x0;
            yi := y0;
          end;
      end;
      { the union (vec2.min / vec2.max) }
      mnX := JsMin(mnX, m2x);
      mnY := JsMin(mnY, m2y);
      mxX := JsMax(mxX, x2x);
      mxY := JsMax(mxY, x2y);
    end;
    { no data }
    if i = 0 then
    begin
      mnX := 0; mnY := 0; mxX := 0; mxY := 0;
    end;
    Result.X := mnX;
    Result.Y := mnY;
    Result.W := mxX - mnX;
    Result.H := mxY - mnY;
    { new BoundingRect: a negative size turned over }
    if Result.W < 0 then
    begin
      Result.X := Result.X + Result.W;
      Result.W := -Result.W;
    end;
    if Result.H < 0 then
    begin
      Result.Y := Result.Y + Result.H;
      Result.H := -Result.H;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyPathStrokeRect(const ARect: TTyXYWH; AHasStroke, AHasFill: Boolean;
  ALineWidth: Double; ANoScale, AHasM: Boolean; const AM: TTyMat2D): TTyXYWH;
var
  lineScale, w: Double;
  mask: TFPUExceptionMask;
begin
  Result := ARect;
  if not AHasStroke then Exit;
  mask := MaskFP;
  try
    lineScale := 1;
    { getLineScale: the transform's, unless its diagonal is one }
    if ANoScale and AHasM and (Abs(AM[0] - 1) > cScaleEps) and (Abs(AM[3] - 1) > cScaleEps) then
      lineScale := Sqrt(Abs(AM[0] * AM[3] - AM[2] * AM[1]));
    w := ALineWidth;
    { the hover threshold where nothing fills (strokeContainThreshold 5) }
    if not AHasFill then w := JsMax(w, 5);
    if lineScale > cScaleEps then
    begin
      Result.W := Result.W + w / lineScale;
      Result.H := Result.H + w / lineScale;
      Result.X := Result.X - w / lineScale / 2;
      Result.Y := Result.Y - w / lineScale / 2;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyMorphRecompose(const AM: TTyMat2D; out AOutHas: Boolean; out AOut: TTyMat2D);
var
  sx, sy, rot, shearX, rotF, x, y, skX, skY, st, ct: Double;
  aa, ac, atx, ab, ad, aty: Double;
  k: Integer;
  mask: TFPUExceptionMask;

  function NotAround0(V: Double): Boolean;
  begin
    Result := (V > cTfEps) or (V < -cTfEps);
  end;

begin
  for k := 0 to 5 do AOut[k] := 0;
  mask := MaskFP;
  try
    { setLocalTransform }
    sx := AM[0] * AM[0] + AM[1] * AM[1];
    sy := AM[2] * AM[2] + AM[3] * AM[3];
    rot := TyJsAtan2(AM[1], AM[0]);
    shearX := cHalfPi + rot - TyJsAtan2(AM[3], AM[2]);
    sy := Sqrt(sy) * TyJsCos(shearX);
    sx := Sqrt(sx);
    rotF := -rot;
    x := AM[4];
    y := AM[5];
    { updateTransform with no parent: getLocalTransform, or nothing }
    AOutHas := NotAround0(rotF) or NotAround0(x) or NotAround0(y) or NotAround0(sx - 1)
      or NotAround0(sy - 1) or NotAround0(shearX);
    if not AOutHas then Exit;
    if (not IsNan(shearX)) and (shearX <> 0) then skX := TyJsTan(shearX) else skX := 0;
    skY := 0;
    AOut[4] := 0;
    AOut[5] := 0;
    AOut[0] := sx;
    AOut[3] := sy;
    AOut[1] := skY * sx;
    AOut[2] := skX * sy;
    if (not IsNan(rotF)) and (rotF <> 0) then
    begin
      { matrix.rotate about [0, 0] }
      aa := AOut[0]; ac := AOut[2]; atx := AOut[4];
      ab := AOut[1]; ad := AOut[3]; aty := AOut[5];
      st := TyJsSin(rotF);
      ct := TyJsCos(rotF);
      AOut[0] := aa * ct + ab * st;
      AOut[1] := -aa * st + ab * ct;
      AOut[2] := ac * ct + ad * st;
      AOut[3] := -ac * st + ct * ad;
      AOut[4] := ct * (atx - 0) + st * (aty - 0) + 0;
      AOut[5] := ct * (aty - 0) - st * (atx - 0) + 0;
    end;
    AOut[4] := AOut[4] + (0 + x);
    AOut[5] := AOut[5] + (0 + y);
  finally
    UnmaskFP(mask);
  end;
end;

function TyMorphSortOrder(const ACX, ACY: array of Double): TTyIntegerArray;
var
  n, i, j, t: Integer;
  xMin, yMin, xMax, yMax: Double;
  z: TTyDoubleArray;
  mask: TFPUExceptionMask;
begin
  n := Length(ACX);
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := i;
  mask := MaskFP;
  try
    xMin := Infinity; yMin := Infinity; xMax := NegInfinity; yMax := NegInfinity;
    for i := 0 to n - 1 do
    begin
      xMin := JsMin(ACX[i], xMin);
      yMin := JsMin(ACY[i], yMin);
      xMax := JsMax(ACX[i], xMax);
      yMax := JsMax(ACY[i], yMax);
    end;
    SetLength(z, n);
    for i := 0 to n - 1 do z[i] := TyMorphHilbert(ACX[i], ACY[i], xMin, yMin, xMax, yMax);
    { sort((a, b) => a.z - b.z): stable }
    for i := 1 to n - 1 do
    begin
      t := Result[i];
      j := i - 1;
      while (j >= 0) and (z[Result[j]] - z[t] > 0) do
      begin
        Result[j + 1] := Result[j];
        Dec(j);
      end;
      Result[j + 1] := t;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

end.
