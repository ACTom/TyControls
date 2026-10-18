unit tyControls.AdvChart.ZrPath;
{$mode objfpc}{$H+}
{ zrender's PathProxy as a component's static picture reads it: the command
  list a path element holds, built the way Rect.buildPath, the symbol makers
  and createPathProxyFromString build it, and the bounding rect
  PathProxy.getBoundingRect and Path.getBoundingRect take from it.

  THE DATA IS WHAT THE PROXY HOLDS, not a picture of it: an SVG icon longer
  than eleven numbers is stored in a Float32Array (toStatic), so every value
  is rounded to a single at the parse and again at each store of the fit
  (transformPath: a point once, an arc's centre twice). A curve's rect is
  exact -- the cubic's and the quadratic's extrema, the arc's quarter
  points -- where a control-point box would overshoot. [Batch 61: the slider
  dataZoom's handles and move icon.]

  PURE: numbers in, numbers out. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Shape;

type
  TTyZrCmd = (zrM, zrL, zrC, zrQ, zrA, zrZ, zrR);
  { One command and its arguments. An arc's are cx, cy, rx, ry, the start
    angle, the SWEEP, psi and 1 for clockwise (0 anticlockwise). }
  TTyZrSeg = record
    Cmd: TTyZrCmd;
    V: array[0..7] of Double;
  end;
  TTyZrPath = array of TTyZrSeg;

const
  TyZrCmdName: array[TTyZrCmd] of Char = ('M', 'L', 'C', 'Q', 'A', 'Z', 'R');

function TyZrArgCount(ACmd: TTyZrCmd): Integer;
{ How many numbers the proxy's data array holds: each command's code and its
  arguments. }
function TyZrDataLength(const APath: TTyZrPath): Integer;

{ ---- building, as the proxy's own methods do ---- }
procedure TyZrMoveTo(var APath: TTyZrPath; AX, AY: Double);
procedure TyZrLineTo(var APath: TTyZrPath; AX, AY: Double);
{ bezierCurveTo }
procedure TyZrCubic(var APath: TTyZrPath; AX1, AY1, AX2, AY2, AX, AY: Double);
{ PathProxy.arc: the angles normalised first (normalizeArcAngles) }
procedure TyZrArc(var APath: TTyZrPath; ACX, ACY, AR, AStart, AEnd: Double;
  AAnti: Boolean);
procedure TyZrRect(var APath: TTyZrPath; AX, AY, AW, AH: Double);
procedure TyZrClose(var APath: TTyZrPath);
{ roundRect.ts: four radii (top-left, top-right, bottom-right, bottom-left),
  shrunk to fit, a quarter arc for each that is not nought }
procedure TyZrRoundRect(var APath: TTyZrPath; AX, AY, AW, AH, R1, R2, R3,
  R4: Double);
{ RectShape.r as roundRect.ts reads it: a number is every corner; an array
  of one is every corner, two the diagonals, three the middle one shared }
procedure TyZrRadii(const AValues: array of Double; out R1, R2, R3, R4: Double);
{ a polygon's or a polyline's path: nothing below two points }
function TyZrPolyPath(const APoints: TTyPointFArray; AClose: Boolean): TTyZrPath;

{ subPixelOptimize.ts }
function TyZrSubPixelOptimize(APosition, ALineWidth: Double;
  APositive: Boolean): Double;
function TyZrSubPixelOptimizeRect(const ARect: TTyXYWH;
  ALineWidth: Double): TTyXYWH;

{ createPathProxyFromString with processArc, then toStatic: AFloat32 says
  whether the data went to a Float32Array (more than eleven numbers). }
function TyZrParseSvg(const S: string; out AFloat32: Boolean): TTyZrPath;
{ PathProxy.getBoundingRect }
function TyZrBBox(const APath: TTyZrPath): TTyXYWH;
{ transformPath, each store a single when AFloat32 }
procedure TyZrTransform(var APath: TTyZrPath; const M: TTyMat2D;
  AFloat32: Boolean);
{ graphic.makePath(str, no options, ABox, 'center'): the path fitted into the box
  keeping its aspect, the fit baked into the data }
function TyZrMakePathCenter(const S: string; const ABox: TTyXYWH): TTyZrPath;
{ the same with the layout 'cover' (resizePath): the path stretched over the
  whole box -- a symbol's path:// icon when symbolKeepAspect is not set
  [Batch 112] }
function TyZrMakePathCover(const S: string; const ABox: TTyXYWH): TTyZrPath;

{ symbol.ts's built-in names this port builds as zrender does }
function TyZrIsBuiltinSymbol(const AType: string): Boolean;
{ createSymbol(type, x, y, w, h, color, keepAspect = true): a `path://` icon
  fitted, a built-in symbol's maker, 'empty' taken off first; any other name
  a rect. }
function TyZrSymbol(const AType: string; AX, AY, AW, AH: Double): TTyZrPath;

{ Path.getBoundingRect: the path's rect grown by the stroke when there is
  one and the path is not empty -- by the line width over a fill, by at least
  five (strokeContainThreshold) without one -- divided by the line scale. }
function TyZrStrokeRect(const APathRect: TTyXYWH; ADataLen: Integer;
  AHasStroke, AHasFill: Boolean; ALineWidth, ALineScale: Double): TTyXYWH;

{ ---- zrender's bounding-rect arithmetic ---- }
{ Group.getBoundingRect's accumulation: the first child's rect unioned with
  itself, every later one with the running rect. }
procedure TyZrAccumulate(var ARect: TTyXYWH; var AHave: Boolean;
  const AChild: TTyXYWH; const M: TTyMat2D);
{ Transformable.getLocalTransform: scale, then the turn, then the move }
function TyZrLocal(AScaleX, AScaleY, ARotation, AX, AY: Double): TTyMat2D;
procedure TyZrApply(const M: TTyMat2D; AX, AY: Double; out OX, OY: Double);

{ ---- contain/path.ts [F6b] ----
  Path.contain's two tests over the proxy's data, in the element's own
  coordinates: the nonzero winding of every command (cubic, quadratic, arc,
  rect, line; a sub-path closed back to its start at the next moveTo and at
  the end) and the stroke within half the line width of a segment.
  Upstream's own arithmetic, quirks and all: a cubic whose y is only a
  quadratic (a = 0) finds no root (Shengjin's formula divides by nought), the
  root and extremum arrays are module-wide and an unwritten slot keeps what
  the last call left there, an arc is tested on a circle of radius ry with x
  scaled by ry / rx. }
function TyZrContain(const APath: TTyZrPath; AX, AY: Double): Boolean;
function TyZrContainStroke(const APath: TTyZrPath; ALineWidth, AX, AY: Double): Boolean;
{ [F6b] the traps a masked stretch saved put back, the flags it left set
  cleared first -- the x87 ones and SSE's in MXCSR, which ClearExceptions
  leaves on x86_64: a sticky one would report the host's next trap wrong }
procedure TyZrRestoreFpu(const AOld: TFPUExceptionMask);

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Data, tyControls.AdvChart.Layout;

const
  PI2 = 2 * Pi;

function XYWH(AX, AY, AW, AH: Double): TTyXYWH;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

{ JavaScript's % }
function JsRem(A, B: Double): Double;
begin
  Result := A - B * Int(A / B);
end;

{ Math.min / Math.max of two: a not-a-number wins }
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

function TyZrArgCount(ACmd: TTyZrCmd): Integer;
begin
  case ACmd of
    zrM, zrL: Result := 2;
    zrC: Result := 6;
    zrQ: Result := 4;
    zrA: Result := 8;
    zrR: Result := 4;
  else
    Result := 0;
  end;
end;

function TyZrDataLength(const APath: TTyZrPath): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(APath) do Inc(Result, 1 + TyZrArgCount(APath[i].Cmd));
end;

procedure Add(var APath: TTyZrPath; ACmd: TTyZrCmd; const AV: array of Double);
var n, i: Integer;
begin
  n := Length(APath);
  SetLength(APath, n + 1);
  APath[n].Cmd := ACmd;
  for i := 0 to 7 do APath[n].V[i] := 0;
  for i := 0 to High(AV) do APath[n].V[i] := AV[i];
end;

procedure TyZrMoveTo(var APath: TTyZrPath; AX, AY: Double);
begin
  Add(APath, zrM, [AX, AY]);
end;

procedure TyZrLineTo(var APath: TTyZrPath; AX, AY: Double);
begin
  Add(APath, zrL, [AX, AY]);
end;

procedure TyZrCubic(var APath: TTyZrPath; AX1, AY1, AX2, AY2, AX, AY: Double);
begin
  Add(APath, zrC, [AX1, AY1, AX2, AY2, AX, AY]);
end;

{ PathProxy's modPI2: the angle's multiple of pi, rounded to 1e-8 }
function ModPI2(ARadian: Double): Double;
var n: Double;
begin
  n := TyJsRound(ARadian / Pi * 1e8) / 1e8;
  Result := JsRem(n, 2) * Pi;
end;

procedure TyZrArc(var APath: TTyZrPath; ACX, ACY, AR, AStart, AEnd: Double;
  AAnti: Boolean);
var s, e, delta: Double;
begin
  { normalizeArcAngles }
  s := ModPI2(AStart);
  if s < 0 then s := s + PI2;
  delta := s - AStart;
  e := AEnd;
  e := e + delta;
  if (not AAnti) and (e - s >= PI2) then e := s + PI2
  else if AAnti and (s - e >= PI2) then e := s - PI2
  else if (not AAnti) and (s > e) then e := s + (PI2 - ModPI2(s - e))
  else if AAnti and (s < e) then e := s - (PI2 - ModPI2(e - s));
  if AAnti then
    Add(APath, zrA, [ACX, ACY, AR, AR, s, e - s, 0, 0])
  else
    Add(APath, zrA, [ACX, ACY, AR, AR, s, e - s, 0, 1]);
end;

procedure TyZrRect(var APath: TTyZrPath; AX, AY, AW, AH: Double);
begin
  Add(APath, zrR, [AX, AY, AW, AH]);
end;

procedure TyZrClose(var APath: TTyZrPath);
begin
  Add(APath, zrZ, []);
end;

procedure TyZrRoundRect(var APath: TTyZrPath; AX, AY, AW, AH, R1, R2, R3,
  R4: Double);
var total: Double;
begin
  if AW < 0 then
  begin
    AX := AX + AW;
    AW := -AW;
  end;
  if AH < 0 then
  begin
    AY := AY + AH;
    AH := -AH;
  end;
  if R1 + R2 > AW then
  begin
    total := R1 + R2;
    R1 := R1 * (AW / total);
    R2 := R2 * (AW / total);
  end;
  if R3 + R4 > AW then
  begin
    total := R3 + R4;
    R3 := R3 * (AW / total);
    R4 := R4 * (AW / total);
  end;
  if R2 + R3 > AH then
  begin
    total := R2 + R3;
    R2 := R2 * (AH / total);
    R3 := R3 * (AH / total);
  end;
  if R1 + R4 > AH then
  begin
    total := R1 + R4;
    R1 := R1 * (AH / total);
    R4 := R4 * (AH / total);
  end;
  TyZrMoveTo(APath, AX + R1, AY);
  TyZrLineTo(APath, AX + AW - R2, AY);
  if R2 <> 0 then TyZrArc(APath, AX + AW - R2, AY + R2, R2, -Pi / 2, 0, False);
  TyZrLineTo(APath, AX + AW, AY + AH - R3);
  if R3 <> 0 then TyZrArc(APath, AX + AW - R3, AY + AH - R3, R3, 0, Pi / 2, False);
  TyZrLineTo(APath, AX + R4, AY + AH);
  if R4 <> 0 then TyZrArc(APath, AX + R4, AY + AH - R4, R4, Pi / 2, Pi, False);
  TyZrLineTo(APath, AX, AY + R1);
  if R1 <> 0 then TyZrArc(APath, AX + R1, AY + R1, R1, Pi, Pi * 1.5, False);
  TyZrClose(APath);
end;

procedure TyZrRadii(const AValues: array of Double; out R1, R2, R3, R4: Double);
begin
  R1 := 0; R2 := 0; R3 := 0; R4 := 0;
  case Length(AValues) of
    0: ;
    1: begin R1 := AValues[0]; R2 := R1; R3 := R1; R4 := R1; end;
    2: begin R1 := AValues[0]; R3 := R1; R2 := AValues[1]; R4 := R2; end;
    3: begin R1 := AValues[0]; R2 := AValues[1]; R4 := R2; R3 := AValues[2]; end;
  else
    R1 := AValues[0]; R2 := AValues[1]; R3 := AValues[2]; R4 := AValues[3];
  end;
end;

function TyZrPolyPath(const APoints: TTyPointFArray; AClose: Boolean): TTyZrPath;
var i: Integer;
begin
  Result := nil;
  if Length(APoints) < 2 then Exit;
  TyZrMoveTo(Result, APoints[0].X, APoints[0].Y);
  for i := 1 to High(APoints) do TyZrLineTo(Result, APoints[i].X, APoints[i].Y);
  if AClose then TyZrClose(Result);
end;

function TyZrSubPixelOptimize(APosition, ALineWidth: Double;
  APositive: Boolean): Double;
var d: Double;
begin
  if IsNan(ALineWidth) or (ALineWidth = 0) then Exit(APosition);
  d := TyJsRound(APosition * 2);
  if JsRem(d + TyJsRound(ALineWidth), 2) = 0 then Result := d / 2
  else if APositive then Result := (d + 1) / 2
  else Result := (d - 1) / 2;
end;

function TyZrSubPixelOptimizeRect(const ARect: TTyXYWH;
  ALineWidth: Double): TTyXYWH;
var floorW, floorH: Double;
begin
  Result := ARect;
  if IsNan(ALineWidth) or (ALineWidth = 0) then Exit;
  Result.X := TyZrSubPixelOptimize(ARect.X, ALineWidth, True);
  Result.Y := TyZrSubPixelOptimize(ARect.Y, ALineWidth, True);
  if ARect.W = 0 then floorW := 0 else floorW := 1;
  if ARect.H = 0 then floorH := 0 else floorH := 1;
  Result.W := JMax(TyZrSubPixelOptimize(ARect.X + ARect.W, ALineWidth, False)
    - Result.X, floorW);
  Result.H := JMax(TyZrSubPixelOptimize(ARect.Y + ARect.H, ALineWidth, False)
    - Result.Y, floorH);
end;

{ ==================== the SVG parser ==================== }

function VMag(AX, AY: Double): Double;
begin
  Result := Sqrt(AX * AX + AY * AY);
end;

function VRatio(UX, UY, VX, VY: Double): Double;
begin
  Result := (UX * VX + UY * VY) / (VMag(UX, UY) * VMag(VX, VY));
end;

function VAngle(UX, UY, VX, VY: Double): Double;
var s: Double;
begin
  if UX * VY < UY * VX then s := -1 else s := 1;
  Result := s * TyJsAcos(VRatio(UX, UY, VX, VY));
end;

{ path.ts processArc }
procedure ProcessArc(var APath: TTyZrPath; X1, Y1, X2, Y2, FA, FS, RX, RY,
  PsiDeg: Double);
var
  psi, xp, yp, lambda, f, num, cxp, cyp, cx, cy, theta, dTheta, ux, uy, vx,
    vy, n: Double;
begin
  psi := PsiDeg * (Pi / 180.0);
  xp := TyJsCos(psi) * (X1 - X2) / 2.0 + TyJsSin(psi) * (Y1 - Y2) / 2.0;
  yp := -1 * TyJsSin(psi) * (X1 - X2) / 2.0 + TyJsCos(psi) * (Y1 - Y2) / 2.0;
  lambda := (xp * xp) / (RX * RX) + (yp * yp) / (RY * RY);
  if lambda > 1 then
  begin
    RX := RX * Sqrt(lambda);
    RY := RY * Sqrt(lambda);
  end;
  num := (((RX * RX) * (RY * RY)) - ((RX * RX) * (yp * yp))
    - ((RY * RY) * (xp * xp))) / ((RX * RX) * (yp * yp) + (RY * RY) * (xp * xp));
  { `(fa === fs ? -1 : 1) * Math.sqrt(...) || 0`: a not-a-number and a zero
    of either sign are nought }
  if IsNan(num) or (num < 0) then f := NaN else f := Sqrt(num);
  if FA = FS then f := -f;
  if IsNan(f) or (f = 0) then f := 0;
  cxp := f * RX * yp / RY;
  cyp := f * -RY * xp / RX;
  cx := (X1 + X2) / 2.0 + TyJsCos(psi) * cxp - TyJsSin(psi) * cyp;
  cy := (Y1 + Y2) / 2.0 + TyJsSin(psi) * cxp + TyJsCos(psi) * cyp;
  theta := VAngle(1, 0, (xp - cxp) / RX, (yp - cyp) / RY);
  ux := (xp - cxp) / RX;
  uy := (yp - cyp) / RY;
  vx := (-1 * xp - cxp) / RX;
  vy := (-1 * yp - cyp) / RY;
  dTheta := VAngle(ux, uy, vx, vy);
  if VRatio(ux, uy, vx, vy) <= -1 then dTheta := Pi;
  if VRatio(ux, uy, vx, vy) >= 1 then dTheta := 0;
  if dTheta < 0 then
  begin
    n := TyJsRound(dTheta / Pi * 1e6) / 1e6;
    dTheta := Pi * 2 + JsRem(n, 2) * Pi;
  end;
  Add(APath, zrA, [cx, cy, RX, RY, theta, dTheta, psi, FS]);
end;

function TyZrParseSvg(const S: string; out AFloat32: Boolean): TTyZrPath;
var
  i, k, off, n: Integer;
  ch, cmdStr: Char;
  body: string;
  p: array of Double;
  cpx, cpy, subX, subY, x1, y1, ctlX, ctlY, rx, ry, psi, fa, fs, a, b, c,
    d, e, f: Double;
  prev, cmd: TTyZrCmd;
  havePrev, haveCmd: Boolean;

  function IsCmd(C: Char): Boolean;
  begin
    Result := Pos(LowerCase(C), 'mlvhzcqtsa') > 0;
  end;

  { numberReg: -?([0-9]*\.)?[0-9]+([eE]-?[0-9]+)? }
  procedure Numbers(const B: string);
  var j, st, m: Integer; t: string;
  begin
    p := nil;
    j := 1;
    while j <= Length(B) do
    begin
      st := j;
      if B[j] = '-' then Inc(j);
      m := j;
      while (j <= Length(B)) and (B[j] in ['0'..'9']) do Inc(j);
      if (j <= Length(B)) and (B[j] = '.') and (j + 1 <= Length(B))
        and (B[j + 1] in ['0'..'9']) then
      begin
        Inc(j);
        m := j;
        while (j <= Length(B)) and (B[j] in ['0'..'9']) do Inc(j);
      end;
      if j = m then
      begin
        j := st + 1;
        Continue;
      end;
      if (j <= Length(B)) and (B[j] in ['e', 'E']) then
      begin
        m := j + 1;
        if (m <= Length(B)) and (B[m] = '-') then Inc(m);
        if (m <= Length(B)) and (B[m] in ['0'..'9']) then
        begin
          j := m;
          while (j <= Length(B)) and (B[j] in ['0'..'9']) do Inc(j);
        end;
      end;
      t := Copy(B, st, j - st);
      SetLength(p, Length(p) + 1);
      p[High(p)] := TyJsParseFloat(t);
    end;
  end;

  function PV: Double;
  begin
    if off <= High(p) then Result := p[off] else Result := NaN;
    Inc(off);
  end;

  { pathData[len - 4] / [len - 3]: a C's second control point, a Q's
    only one }
  function LastV(const APath: TTyZrPath; AIdx: Integer): Double;
  begin
    if Length(APath) = 0 then Exit(NaN);
    Result := APath[High(APath)].V[AIdx];
  end;

begin
  Result := nil;
  AFloat32 := False;
  cpx := 0; cpy := 0; subX := 0; subY := 0;
  havePrev := False;
  haveCmd := False;
  prev := zrM;
  cmd := zrM;
  i := 1;
  while i <= Length(S) do
  begin
    ch := S[i];
    if not IsCmd(ch) then
    begin
      Inc(i);
      Continue;
    end;
    k := i + 1;
    while (k <= Length(S)) and not IsCmd(S[k]) do Inc(k);
    body := Copy(S, i + 1, k - i - 1);
    i := k;
    cmdStr := ch;
    Numbers(body);
    off := 0;
    haveCmd := False;
    while off < Length(p) do
    begin
      x1 := cpx;
      y1 := cpy;
      haveCmd := True;
      case cmdStr of
        'l': begin cpx := cpx + PV; cpy := cpy + PV; cmd := zrL; Add(Result, zrL, [cpx, cpy]); end;
        'L': begin cpx := PV; cpy := PV; cmd := zrL; Add(Result, zrL, [cpx, cpy]); end;
        'm': begin cpx := cpx + PV; cpy := cpy + PV; cmd := zrM; Add(Result, zrM, [cpx, cpy]);
               subX := cpx; subY := cpy; cmdStr := 'l'; end;
        'M': begin cpx := PV; cpy := PV; cmd := zrM; Add(Result, zrM, [cpx, cpy]);
               subX := cpx; subY := cpy; cmdStr := 'L'; end;
        'h': begin cpx := cpx + PV; cmd := zrL; Add(Result, zrL, [cpx, cpy]); end;
        'H': begin cpx := PV; cmd := zrL; Add(Result, zrL, [cpx, cpy]); end;
        'v': begin cpy := cpy + PV; cmd := zrL; Add(Result, zrL, [cpx, cpy]); end;
        'V': begin cpy := PV; cmd := zrL; Add(Result, zrL, [cpx, cpy]); end;
        'C':
          begin
            cmd := zrC;
            a := PV; b := PV; c := PV; d := PV; e := PV; f := PV;
            Add(Result, zrC, [a, b, c, d, e, f]);
            cpx := e;
            cpy := f;
          end;
        'c':
          begin
            cmd := zrC;
            a := PV + cpx; b := PV + cpy; c := PV + cpx; d := PV + cpy;
            e := PV; f := PV;
            Add(Result, zrC, [a, b, c, d, e + cpx, f + cpy]);
            cpx := cpx + e;
            cpy := cpy + f;
          end;
        'S', 's':
          begin
            ctlX := cpx;
            ctlY := cpy;
            if havePrev and (prev = zrC) then
            begin
              ctlX := ctlX + cpx - LastV(Result, 2);
              ctlY := ctlY + cpy - LastV(Result, 3);
            end;
            cmd := zrC;
            if cmdStr = 'S' then
            begin
              x1 := PV; y1 := PV; cpx := PV; cpy := PV;
            end
            else
            begin
              x1 := cpx + PV; y1 := cpy + PV;
              rx := PV; ry := PV;
              cpx := cpx + rx; cpy := cpy + ry;
            end;
            Add(Result, zrC, [ctlX, ctlY, x1, y1, cpx, cpy]);
          end;
        'Q':
          begin
            x1 := PV; y1 := PV; cpx := PV; cpy := PV;
            cmd := zrQ;
            Add(Result, zrQ, [x1, y1, cpx, cpy]);
          end;
        'q':
          begin
            x1 := PV + cpx; y1 := PV + cpy;
            rx := PV; ry := PV;
            cpx := cpx + rx; cpy := cpy + ry;
            cmd := zrQ;
            Add(Result, zrQ, [x1, y1, cpx, cpy]);
          end;
        'T', 't':
          begin
            ctlX := cpx;
            ctlY := cpy;
            if havePrev and (prev = zrQ) then
            begin
              ctlX := ctlX + cpx - LastV(Result, 0);
              ctlY := ctlY + cpy - LastV(Result, 1);
            end;
            if cmdStr = 'T' then begin cpx := PV; cpy := PV; end
            else begin rx := PV; ry := PV; cpx := cpx + rx; cpy := cpy + ry; end;
            cmd := zrQ;
            Add(Result, zrQ, [ctlX, ctlY, cpx, cpy]);
          end;
        'A', 'a':
          begin
            rx := PV; ry := PV; psi := PV; fa := PV; fs := PV;
            x1 := cpx; y1 := cpy;
            if cmdStr = 'A' then begin cpx := PV; cpy := PV; end
            else begin cpx := cpx + PV; cpy := cpy + PV; end;
            cmd := zrA;
            ProcessArc(Result, x1, y1, cpx, cpy, fa, fs, rx, ry, psi);
          end;
      else
        off := Length(p);
      end;
    end;
    if cmdStr in ['z', 'Z'] then
    begin
      cmd := zrZ;
      haveCmd := True;
      Add(Result, zrZ, []);
      cpx := subX;
      cpy := subY;
    end;
    { `prevCmd = cmd`: undefined after a command with no numbers }
    havePrev := haveCmd;
    prev := cmd;
  end;
  { toStatic }
  if TyZrDataLength(Result) > 11 then
  begin
    AFloat32 := True;
    for n := 0 to High(Result) do
      for k := 0 to TyZrArgCount(Result[n].Cmd) - 1 do
        Result[n].V[k] := TyJsFround(Result[n].V[k]);
  end;
end;

{ ==================== bounding rects ==================== }

const
  EPS = 1e-8;

function IsAroundZero(V: Double): Boolean;
begin
  Result := (V > -EPS) and (V < EPS);
end;

function IsNotAroundZero(V: Double): Boolean;
begin
  Result := (V > EPS) or (V < -EPS);
end;

function CubicAt(P0, P1, P2, P3, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * onet * (onet * P0 + 3 * T * P1) + T * T * (T * P3 + 3 * onet * P2);
end;

function CubicExtrema(P0, P1, P2, P3: Double; out E0, E1: Double): Integer;
var a, b, c, disc, ds, t1, t2: Double;
begin
  Result := 0;
  E0 := NaN;
  E1 := NaN;
  b := 6 * P2 - 12 * P1 + 6 * P0;
  a := 9 * P1 + 3 * P3 - 3 * P0 - 9 * P2;
  c := 3 * P1 - 3 * P0;
  if IsAroundZero(a) then
  begin
    if IsNotAroundZero(b) then
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
    if IsAroundZero(disc) then
      { `extrema[0] = -b / (2 * a)` and the count left at nought }
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

procedure FromLine(X0, Y0, X1, Y1: Double; var MinX, MinY, MaxX, MaxY: Double);
begin
  MinX := JMin(X0, X1);
  MinY := JMin(Y0, Y1);
  MaxX := JMax(X0, X1);
  MaxY := JMax(Y0, Y1);
end;

procedure FromCubic(X0, Y0, X1, Y1, X2, Y2, X3, Y3: Double;
  var MinX, MinY, MaxX, MaxY: Double);
var
  n, i: Integer;
  e: array[0..1] of Double;
  v: Double;
begin
  n := CubicExtrema(X0, X1, X2, X3, e[0], e[1]);
  MinX := Infinity; MinY := Infinity; MaxX := NegInfinity; MaxY := NegInfinity;
  for i := 0 to n - 1 do
  begin
    v := CubicAt(X0, X1, X2, X3, e[i]);
    MinX := JMin(v, MinX);
    MaxX := JMax(v, MaxX);
  end;
  n := CubicExtrema(Y0, Y1, Y2, Y3, e[0], e[1]);
  for i := 0 to n - 1 do
  begin
    v := CubicAt(Y0, Y1, Y2, Y3, e[i]);
    MinY := JMin(v, MinY);
    MaxY := JMax(v, MaxY);
  end;
  MinX := JMin(X0, MinX); MaxX := JMax(X0, MaxX);
  MinX := JMin(X3, MinX); MaxX := JMax(X3, MaxX);
  MinY := JMin(Y0, MinY); MaxY := JMax(Y0, MaxY);
  MinY := JMin(Y3, MinY); MaxY := JMax(Y3, MaxY);
end;

function QuadraticAt(P0, P1, P2, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * (onet * P0 + 2 * T * P1) + T * T * P2;
end;

function QuadraticExtremum(P0, P1, P2: Double): Double;
var divider: Double;
begin
  divider := P0 + P2 - 2 * P1;
  if divider = 0 then Result := 0.5 else Result := (P0 - P1) / divider;
end;

procedure FromQuadratic(X0, Y0, X1, Y1, X2, Y2: Double;
  var MinX, MinY, MaxX, MaxY: Double);
var tx, ty, x, y: Double;
begin
  tx := JMax(JMin(QuadraticExtremum(X0, X1, X2), 1), 0);
  ty := JMax(JMin(QuadraticExtremum(Y0, Y1, Y2), 1), 0);
  x := QuadraticAt(X0, X1, X2, tx);
  y := QuadraticAt(Y0, Y1, Y2, ty);
  MinX := JMin(JMin(X0, X2), x);
  MinY := JMin(JMin(Y0, Y2), y);
  MaxX := JMax(JMax(X0, X2), x);
  MaxY := JMax(JMax(Y0, Y2), y);
end;

procedure FromArc(X, Y, RX, RY, AStart, AEnd: Double; AAnti: Boolean;
  var MinX, MinY, MaxX, MaxY: Double);
var
  diff, sx, sy, ex, ey, angle, t: Double;
begin
  diff := Abs(AStart - AEnd);
  if (JsRem(diff, PI2) < 1e-4) and (diff > 1e-4) then
  begin
    MinX := X - RX; MinY := Y - RY; MaxX := X + RX; MaxY := Y + RY;
    Exit;
  end;
  sx := TyJsCos(AStart) * RX + X;
  sy := TyJsSin(AStart) * RY + Y;
  ex := TyJsCos(AEnd) * RX + X;
  ey := TyJsSin(AEnd) * RY + Y;
  MinX := JMin(sx, ex); MinY := JMin(sy, ey);
  MaxX := JMax(sx, ex); MaxY := JMax(sy, ey);
  AStart := JsRem(AStart, PI2);
  if AStart < 0 then AStart := AStart + PI2;
  AEnd := JsRem(AEnd, PI2);
  if AEnd < 0 then AEnd := AEnd + PI2;
  if (AStart > AEnd) and not AAnti then AEnd := AEnd + PI2
  else if (AStart < AEnd) and AAnti then AStart := AStart + PI2;
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
      MinX := JMin(sx, MinX); MinY := JMin(sy, MinY);
      MaxX := JMax(sx, MaxX); MaxY := JMax(sy, MaxY);
    end;
    angle := angle + Pi / 2;
  end;
end;

function TyZrBBox(const APath: TTyZrPath): TTyXYWH;
var
  i: Integer;
  mnX, mnY, mxX, mxY, m2x, m2y, x2x, x2y, xi, yi, x0, y0, ea: Double;
  s: TTyZrSeg;
begin
  if Length(APath) = 0 then Exit(XYWH(0, 0, 0, 0));
  mnX := MaxDouble; mnY := MaxDouble; mxX := -MaxDouble; mxY := -MaxDouble;
  m2x := MaxDouble; m2y := MaxDouble; x2x := -MaxDouble; x2y := -MaxDouble;
  xi := 0; yi := 0; x0 := 0; y0 := 0;
  for i := 0 to High(APath) do
  begin
    s := APath[i];
    if i = 0 then
    begin
      { `data[i]`, `data[i + 1]`: whatever the first command's first two
        numbers are }
      xi := s.V[0];
      yi := s.V[1];
      x0 := xi;
      y0 := yi;
    end;
    case s.Cmd of
      zrM:
        begin
          xi := s.V[0]; x0 := xi;
          yi := s.V[1]; y0 := yi;
          m2x := x0; m2y := y0; x2x := x0; x2y := y0;
        end;
      zrL:
        begin
          FromLine(xi, yi, s.V[0], s.V[1], m2x, m2y, x2x, x2y);
          xi := s.V[0]; yi := s.V[1];
        end;
      zrC:
        begin
          FromCubic(xi, yi, s.V[0], s.V[1], s.V[2], s.V[3], s.V[4], s.V[5],
            m2x, m2y, x2x, x2y);
          xi := s.V[4]; yi := s.V[5];
        end;
      zrQ:
        begin
          FromQuadratic(xi, yi, s.V[0], s.V[1], s.V[2], s.V[3], m2x, m2y, x2x, x2y);
          xi := s.V[2]; yi := s.V[3];
        end;
      zrA:
        begin
          ea := s.V[5] + s.V[4];
          if i = 0 then
          begin
            x0 := TyJsCos(s.V[4]) * s.V[2] + s.V[0];
            y0 := TyJsSin(s.V[4]) * s.V[3] + s.V[1];
          end;
          FromArc(s.V[0], s.V[1], s.V[2], s.V[3], s.V[4], ea, s.V[7] = 0,
            m2x, m2y, x2x, x2y);
          xi := TyJsCos(ea) * s.V[2] + s.V[0];
          yi := TyJsSin(ea) * s.V[3] + s.V[1];
        end;
      zrR:
        begin
          x0 := s.V[0]; xi := x0;
          y0 := s.V[1]; yi := y0;
          FromLine(x0, y0, x0 + s.V[2], y0 + s.V[3], m2x, m2y, x2x, x2y);
        end;
      zrZ:
        begin
          xi := x0;
          yi := y0;
        end;
    end;
    mnX := JMin(mnX, m2x); mnY := JMin(mnY, m2y);
    mxX := JMax(mxX, x2x); mxY := JMax(mxY, x2y);
  end;
  Result := XYWH(mnX, mnY, mxX - mnX, mxY - mnY);
end;

procedure TyZrTransform(var APath: TTyZrPath; const M: TTyMat2D;
  AFloat32: Boolean);
var
  i, k, n: Integer;
  sx, sy, angle, x, y: Double;

  function St(A: Double): Double;
  begin
    if AFloat32 then Result := TyJsFround(A) else Result := A;
  end;

begin
  for i := 0 to High(APath) do
    case APath[i].Cmd of
      zrM, zrL, zrC, zrQ:
        begin
          case APath[i].Cmd of
            zrC: n := 3;
            zrQ: n := 2;
          else
            n := 1;
          end;
          for k := 0 to n - 1 do
          begin
            x := APath[i].V[2 * k];
            y := APath[i].V[2 * k + 1];
            APath[i].V[2 * k] := St(M[0] * x + M[2] * y + M[4]);
            APath[i].V[2 * k + 1] := St(M[1] * x + M[3] * y + M[5]);
          end;
        end;
      zrA:
        begin
          sx := Sqrt(M[0] * M[0] + M[1] * M[1]);
          sy := Sqrt(M[2] * M[2] + M[3] * M[3]);
          angle := TyJsAtan2(-M[1] / sy, M[0] / sx);
          { `data[i] *= sx; data[i] += x`: two stores }
          APath[i].V[0] := St(St(APath[i].V[0] * sx) + M[4]);
          APath[i].V[1] := St(St(APath[i].V[1] * sy) + M[5]);
          APath[i].V[2] := St(APath[i].V[2] * sx);
          APath[i].V[3] := St(APath[i].V[3] * sy);
          APath[i].V[4] := St(APath[i].V[4] + angle);
          APath[i].V[5] := St(APath[i].V[5] + angle);
        end;
    end;
end;

function TyZrMakePathCenter(const S: string; const ABox: TTyXYWH): TTyZrPath;
var
  f32: Boolean;
  r, fit: TTyXYWH;
  aspect, w, h, cx, cy, sx, sy: Double;
  m: TTyMat2D;
begin
  Result := TyZrParseSvg(S, f32);
  r := TyZrBBox(Result);
  { centerGraphic: the box, keeping the path's own proportions }
  aspect := r.W / r.H;
  w := ABox.H * aspect;
  if w <= ABox.W then
    h := ABox.H
  else
  begin
    w := ABox.W;
    h := w / aspect;
  end;
  cx := ABox.X + ABox.W / 2;
  cy := ABox.Y + ABox.H / 2;
  fit := XYWH(cx - w / 2, cy - h / 2, w, h);
  { BoundingRect.calculateTransform: translate, scale, translate }
  sx := fit.W / r.W;
  sy := fit.H / r.H;
  m[0] := 1; m[1] := 0; m[2] := 0; m[3] := 1;
  m[4] := 0 + -r.X;
  m[5] := 0 + -r.Y;
  m[0] := m[0] * sx; m[1] := m[1] * sy;
  m[2] := m[2] * sx; m[3] := m[3] * sy;
  m[4] := m[4] * sx; m[5] := m[5] * sy;
  m[4] := m[4] + fit.X;
  m[5] := m[5] + fit.Y;
  TyZrTransform(Result, m, f32);
end;

function TyZrMakePathCover(const S: string; const ABox: TTyXYWH): TTyZrPath;
var
  f32: Boolean;
  r: TTyXYWH;
  sx, sy: Double;
  m: TTyMat2D;
begin
  Result := TyZrParseSvg(S, f32);
  r := TyZrBBox(Result);
  { BoundingRect.calculateTransform onto the box itself }
  sx := ABox.W / r.W;
  sy := ABox.H / r.H;
  m[0] := 1; m[1] := 0; m[2] := 0; m[3] := 1;
  m[4] := 0 + -r.X;
  m[5] := 0 + -r.Y;
  m[0] := m[0] * sx; m[1] := m[1] * sy;
  m[2] := m[2] * sx; m[3] := m[3] * sy;
  m[4] := m[4] * sx; m[5] := m[5] * sy;
  m[4] := m[4] + ABox.X;
  m[5] := m[5] + ABox.Y;
  TyZrTransform(Result, m, f32);
end;

function TyZrIsBuiltinSymbol(const AType: string): Boolean;
begin
  Result := (AType = 'line') or (AType = 'rect') or (AType = 'roundRect')
    or (AType = 'square') or (AType = 'circle') or (AType = 'diamond')
    or (AType = 'pin') or (AType = 'arrow') or (AType = 'triangle');
end;

function TyZrSymbol(const AType: string; AX, AY, AW, AH: Double): TTyZrPath;
var
  t: string;
  cx, cy, r, hw, hh, size: Double;
  px, py, pw, ph, dy, pcy, ang, dx, tanX, tanY, cpLen, cpLen2: Double;
begin
  Result := nil;
  t := AType;
  if Copy(t, 1, 5) = 'empty' then
    t := LowerCase(Copy(t, 6, 1)) + Copy(t, 7, MaxInt);
  if Copy(t, 1, 7) = 'path://' then
    Exit(TyZrMakePathCenter(Copy(t, 8, MaxInt), XYWH(AX, AY, AW, AH)));
  if t = 'circle' then
  begin
    cx := AX + AW / 2;
    cy := AY + AH / 2;
    r := JMin(AW, AH) / 2;
    TyZrMoveTo(Result, cx + r, cy);
    TyZrArc(Result, cx, cy, r, 0, Pi * 2, False);
  end
  else if t = 'roundRect' then
  begin
    { Rect.buildPath: a radius of nought is a plain rect command }
    r := JMin(AW, AH) / 4;
    if (r = 0) or IsNan(r) then TyZrRect(Result, AX, AY, AW, AH)
    else TyZrRoundRect(Result, AX, AY, AW, AH, r, r, r, r);
  end
  else if t = 'line' then
  begin
    { a zrender Line across the box's middle, no sub-pixel step on a proxy }
    TyZrMoveTo(Result, AX, AY + AH / 2);
    TyZrLineTo(Result, AX + AW, AY + AH / 2);
  end
  else if t = 'pin' then
  begin
    { the maker puts (x, y) at the box CENTRE: the cusp, with the head above
      it. [Batch 65] }
    px := AX + AW / 2;
    py := AY + AH / 2;
    pw := AW / 5 * 3;
    ph := JMax(pw, AH);
    r := pw / 2;
    dy := r * r / (ph - r);
    pcy := py - ph + r + dy;
    ang := TyJsAsin(dy / r);
    dx := TyJsCos(ang) * r;
    tanX := TyJsSin(ang);
    tanY := TyJsCos(ang);
    cpLen := r * 0.6;
    cpLen2 := r * 0.7;
    TyZrMoveTo(Result, px - dx, pcy + dy);
    TyZrArc(Result, px, pcy, r, Pi - ang, Pi * 2 + ang, False);
    TyZrCubic(Result, px + dx - tanX * cpLen, pcy + dy + tanY * cpLen, px, py - cpLen2,
      px, py);
    TyZrCubic(Result, px, py - cpLen2, px - dx + tanX * cpLen, pcy + dy + tanY * cpLen,
      px - dx, pcy + dy);
    TyZrClose(Result);
  end
  else if t = 'arrow' then
  begin
    { the TIP at the box centre, the body a whole height below it }
    px := AX + AW / 2;
    py := AY + AH / 2;
    dx := AW / 3 * 2;
    TyZrMoveTo(Result, px, py);
    TyZrLineTo(Result, px + dx, py + AH);
    TyZrLineTo(Result, px, py + AH / 4 * 3);
    TyZrLineTo(Result, px - dx, py + AH);
    TyZrLineTo(Result, px, py);
    TyZrClose(Result);
  end
  else if t = 'square' then
  begin
    size := JMin(AW, AH);
    TyZrRect(Result, AX, AY, size, size);
  end
  else if t = 'diamond' then
  begin
    cx := AX + AW / 2; cy := AY + AH / 2; hw := AW / 2; hh := AH / 2;
    TyZrMoveTo(Result, cx, cy - hh);
    TyZrLineTo(Result, cx + hw, cy);
    TyZrLineTo(Result, cx, cy + hh);
    TyZrLineTo(Result, cx - hw, cy);
    TyZrClose(Result);
  end
  else if t = 'triangle' then
  begin
    cx := AX + AW / 2; cy := AY + AH / 2; hw := AW / 2; hh := AH / 2;
    TyZrMoveTo(Result, cx, cy - hh);
    TyZrLineTo(Result, cx + hw, cy + hh);
    TyZrLineTo(Result, cx - hw, cy + hh);
    TyZrClose(Result);
  end
  else
    { rect, and any name symbol.ts does not know: SymbolClz.buildPath draws
      a rect for it }
    TyZrRect(Result, AX, AY, AW, AH);
end;

function TyZrStrokeRect(const APathRect: TTyXYWH; ADataLen: Integer;
  AHasStroke, AHasFill: Boolean; ALineWidth, ALineScale: Double): TTyXYWH;
var w: Double;
begin
  Result := APathRect;
  if not (AHasStroke and (ALineWidth > 0) and (ADataLen > 0)) then Exit;
  w := ALineWidth;
  if not AHasFill then w := JMax(w, 5);
  if ALineScale > 1e-10 then
  begin
    Result.W := Result.W + w / ALineScale;
    Result.H := Result.H + w / ALineScale;
    Result.X := Result.X - w / ALineScale / 2;
    Result.Y := Result.Y - w / ALineScale / 2;
  end;
end;

procedure TyZrAccumulate(var ARect: TTyXYWH; var AHave: Boolean;
  const AChild: TTyXYWH; const M: TTyMat2D);
var t: TTyXYWH;
begin
  t := TyRectApplyMat(AChild, M);
  if not AHave then
  begin
    ARect := t;
    AHave := True;
  end;
  ARect := TyRectUnion(ARect, t);
end;

function TyZrLocal(AScaleX, AScaleY, ARotation, AX, AY: Double): TTyMat2D;
var aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  Result[4] := 0;
  Result[5] := 0;
  Result[0] := AScaleX;
  Result[3] := AScaleY;
  Result[1] := 0 * AScaleX;
  Result[2] := 0 * AScaleY;
  if ARotation <> 0 then
  begin
    aa := Result[0]; ac := Result[2]; atx := Result[4];
    ab := Result[1]; ad := Result[3]; aty := Result[5];
    st := TyJsSin(ARotation);
    ct := TyJsCos(ARotation);
    Result[0] := aa * ct + ab * st;
    Result[1] := -aa * st + ab * ct;
    Result[2] := ac * ct + ad * st;
    Result[3] := -ac * st + ct * ad;
    Result[4] := ct * (atx - 0) + st * (aty - 0) + 0;
    Result[5] := ct * (aty - 0) - st * (atx - 0) + 0;
  end;
  Result[4] := Result[4] + (0 + AX);
  Result[5] := Result[5] + (0 + AY);
end;

procedure TyZrApply(const M: TTyMat2D; AX, AY: Double; out OX, OY: Double);
begin
  OX := M[0] * AX + M[2] * AY + M[4];
  OY := M[1] * AX + M[3] * AY + M[5];
end;

{ ==================== contain/path.ts [F6b] ==================== }

const
  cCurveEps = 1e-8;
  cCurveNumeric = 1e-4;
  cWindEps = 1e-4;

var
  { the module-wide scratch arrays of contain/path.ts: a slot a call does not
    write keeps the last call's value }
  GZrRoots: array[0..2] of Double = (-1, -1, -1);
  GZrExtrema: array[0..1] of Double = (-1, -1);

function CvAroundZero(V: Double): Boolean;
begin
  Result := (V > -cCurveEps) and (V < cCurveEps);
end;

function CvNotAroundZero(V: Double): Boolean;
begin
  Result := (V > cCurveEps) or (V < -cCurveEps);
end;

function CvCubicAt(P0, P1, P2, P3, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * onet * (onet * P0 + 3 * T * P1) + T * T * (T * P3 + 3 * onet * P2);
end;

function CvQuadraticAt(P0, P1, P2, T: Double): Double;
var onet: Double;
begin
  onet := 1 - T;
  Result := onet * (onet * P0 + 2 * T * P1) + T * T * P2;
end;

{ Math.pow(x, ONE_THIRD) }
function CvCbrt(X: Double): Double;
const cThird: Double = 1 / 3;
begin
  Result := TyJsPow(X, cThird);
end;

function CvCubicRootAt(P0, P1, P2, P3, AVal: Double): Integer;
var
  a, b, c, d, aa, bb, cc, disc, k, t1, t2, t3, ds, y1, y2, tt, theta, asq, tmp,
    threeSqrt: Double;
  n: Integer;
begin
  threeSqrt := Sqrt(3);
  a := P3 + 3 * (P1 - P2) - P0;
  b := 3 * (P2 - P1 * 2 + P0);
  c := 3 * (P1 - P0);
  d := P0 - AVal;
  aa := b * b - 3 * a * c;
  bb := b * c - 9 * a * d;
  cc := c * c - 3 * b * d;
  n := 0;
  if CvAroundZero(aa) and CvAroundZero(bb) then
  begin
    if CvAroundZero(b) then
      GZrRoots[0] := 0
    else
    begin
      t1 := -c / b;
      if (t1 >= 0) and (t1 <= 1) then
      begin
        GZrRoots[n] := t1;
        Inc(n);
      end;
    end;
  end
  else
  begin
    disc := bb * bb - 4 * aa * cc;
    if CvAroundZero(disc) then
    begin
      k := bb / aa;
      t1 := -b / a + k;
      t2 := -k / 2;
      if (t1 >= 0) and (t1 <= 1) then begin GZrRoots[n] := t1; Inc(n); end;
      if (t2 >= 0) and (t2 <= 1) then begin GZrRoots[n] := t2; Inc(n); end;
    end
    else if disc > 0 then
    begin
      ds := Sqrt(disc);
      y1 := aa * b + 1.5 * a * (-bb + ds);
      y2 := aa * b + 1.5 * a * (-bb - ds);
      if y1 < 0 then y1 := -CvCbrt(-y1) else y1 := CvCbrt(y1);
      if y2 < 0 then y2 := -CvCbrt(-y2) else y2 := CvCbrt(y2);
      t1 := (-b - (y1 + y2)) / (3 * a);
      if (t1 >= 0) and (t1 <= 1) then begin GZrRoots[n] := t1; Inc(n); end;
    end
    else
    begin
      tt := (2 * aa * b - 3 * a * bb) / (2 * Sqrt(aa * aa * aa));
      theta := TyJsAcos(tt) / 3;
      asq := Sqrt(aa);
      tmp := TyJsCos(theta);
      t1 := (-b - 2 * asq * tmp) / (3 * a);
      t2 := (-b + asq * (tmp + threeSqrt * TyJsSin(theta))) / (3 * a);
      t3 := (-b + asq * (tmp - threeSqrt * TyJsSin(theta))) / (3 * a);
      if (t1 >= 0) and (t1 <= 1) then begin GZrRoots[n] := t1; Inc(n); end;
      if (t2 >= 0) and (t2 <= 1) then begin GZrRoots[n] := t2; Inc(n); end;
      if (t3 >= 0) and (t3 <= 1) then begin GZrRoots[n] := t3; Inc(n); end;
    end;
  end;
  Result := n;
end;

function CvCubicExtrema(P0, P1, P2, P3: Double): Integer;
var a, b, c, disc, ds, t1, t2: Double; n: Integer;
begin
  b := 6 * P2 - 12 * P1 + 6 * P0;
  a := 9 * P1 + 3 * P3 - 3 * P0 - 9 * P2;
  c := 3 * P1 - 3 * P0;
  n := 0;
  if CvAroundZero(a) then
  begin
    if CvNotAroundZero(b) then
    begin
      t1 := -c / b;
      if (t1 >= 0) and (t1 <= 1) then begin GZrExtrema[n] := t1; Inc(n); end;
    end;
  end
  else
  begin
    disc := b * b - 4 * a * c;
    if CvAroundZero(disc) then
      GZrExtrema[0] := -b / (2 * a)
    else if disc > 0 then
    begin
      ds := Sqrt(disc);
      t1 := (-b + ds) / (2 * a);
      t2 := (-b - ds) / (2 * a);
      if (t1 >= 0) and (t1 <= 1) then begin GZrExtrema[n] := t1; Inc(n); end;
      if (t2 >= 0) and (t2 <= 1) then begin GZrExtrema[n] := t2; Inc(n); end;
    end;
  end;
  Result := n;
end;

function CvQuadraticRootAt(P0, P1, P2, AVal: Double): Integer;
var a, b, c, disc, ds, t1, t2: Double; n: Integer;
begin
  a := P0 - 2 * P1 + P2;
  b := 2 * (P1 - P0);
  c := P0 - AVal;
  n := 0;
  if CvAroundZero(a) then
  begin
    if CvNotAroundZero(b) then
    begin
      t1 := -c / b;
      if (t1 >= 0) and (t1 <= 1) then begin GZrRoots[n] := t1; Inc(n); end;
    end;
  end
  else
  begin
    disc := b * b - 4 * a * c;
    if CvAroundZero(disc) then
    begin
      t1 := -b / (2 * a);
      if (t1 >= 0) and (t1 <= 1) then begin GZrRoots[n] := t1; Inc(n); end;
    end
    else if disc > 0 then
    begin
      ds := Sqrt(disc);
      t1 := (-b + ds) / (2 * a);
      t2 := (-b - ds) / (2 * a);
      if (t1 >= 0) and (t1 <= 1) then begin GZrRoots[n] := t1; Inc(n); end;
      if (t2 >= 0) and (t2 <= 1) then begin GZrRoots[n] := t2; Inc(n); end;
    end;
  end;
  Result := n;
end;

function CvQuadraticExtremum(P0, P1, P2: Double): Double;
var divider: Double;
begin
  divider := P0 + P2 - 2 * P1;
  if divider = 0 then Result := 0.5
  else Result := (P0 - P1) / divider;
end;

{ windingLine.ts }
function ZrWindingLine(X0, Y0, X1, Y1, X, Y: Double): Double;
var t, dir, xx: Double;
begin
  if ((Y > Y0) and (Y > Y1)) or ((Y < Y0) and (Y < Y1)) then Exit(0);
  if Y1 = Y0 then Exit(0);
  t := (Y - Y0) / (Y1 - Y0);
  if Y1 < Y0 then dir := 1 else dir := -1;
  if (t = 1) or (t = 0) then
  begin
    if Y1 < Y0 then dir := 0.5 else dir := -0.5;
  end;
  xx := t * (X1 - X0) + X0;
  if xx = X then Result := Infinity
  else if xx > X then Result := dir
  else Result := 0;
end;

{ `w += f(...) || 0`: a not-a-number adds nothing }
function OrNought(V: Double): Double;
begin
  if IsNan(V) then Result := 0 else Result := V;
end;

function ZrWindingCubic(X0, Y0, X1, Y1, X2, Y2, X3, Y3, X, Y: Double): Double;
var
  nRoots, nExtrema, i: Integer;
  w, t, unitW, xx, y0_, y1_, tmp: Double;
begin
  if ((Y > Y0) and (Y > Y1) and (Y > Y2) and (Y > Y3))
    or ((Y < Y0) and (Y < Y1) and (Y < Y2) and (Y < Y3)) then Exit(0);
  nRoots := CvCubicRootAt(Y0, Y1, Y2, Y3, Y);
  if nRoots = 0 then Exit(0);
  w := 0;
  nExtrema := -1;
  y0_ := NaN;
  y1_ := NaN;
  for i := 0 to nRoots - 1 do
  begin
    t := GZrRoots[i];
    if (t = 0) or (t = 1) then unitW := 0.5 else unitW := 1;
    xx := CvCubicAt(X0, X1, X2, X3, t);
    if xx < X then Continue;
    if nExtrema < 0 then
    begin
      nExtrema := CvCubicExtrema(Y0, Y1, Y2, Y3);
      if (GZrExtrema[1] < GZrExtrema[0]) and (nExtrema > 1) then
      begin
        tmp := GZrExtrema[0];
        GZrExtrema[0] := GZrExtrema[1];
        GZrExtrema[1] := tmp;
      end;
      y0_ := CvCubicAt(Y0, Y1, Y2, Y3, GZrExtrema[0]);
      if nExtrema > 1 then y1_ := CvCubicAt(Y0, Y1, Y2, Y3, GZrExtrema[1]);
    end;
    if nExtrema = 2 then
    begin
      if t < GZrExtrema[0] then
      begin
        if y0_ < Y0 then w := w + unitW else w := w - unitW;
      end
      else if t < GZrExtrema[1] then
      begin
        if y1_ < y0_ then w := w + unitW else w := w - unitW;
      end
      else
      begin
        if Y3 < y1_ then w := w + unitW else w := w - unitW;
      end;
    end
    else
    begin
      if t < GZrExtrema[0] then
      begin
        if y0_ < Y0 then w := w + unitW else w := w - unitW;
      end
      else
      begin
        if Y3 < y0_ then w := w + unitW else w := w - unitW;
      end;
    end;
  end;
  Result := w;
end;

function ZrWindingQuadratic(X0, Y0, X1, Y1, X2, Y2, X, Y: Double): Double;
var nRoots, i: Integer; t, w, yy, unitW, xx: Double;
begin
  if ((Y > Y0) and (Y > Y1) and (Y > Y2)) or ((Y < Y0) and (Y < Y1) and (Y < Y2)) then Exit(0);
  nRoots := CvQuadraticRootAt(Y0, Y1, Y2, Y);
  if nRoots = 0 then Exit(0);
  t := CvQuadraticExtremum(Y0, Y1, Y2);
  if (t >= 0) and (t <= 1) then
  begin
    w := 0;
    yy := CvQuadraticAt(Y0, Y1, Y2, t);
    for i := 0 to nRoots - 1 do
    begin
      if (GZrRoots[i] = 0) or (GZrRoots[i] = 1) then unitW := 0.5 else unitW := 1;
      xx := CvQuadraticAt(X0, X1, X2, GZrRoots[i]);
      if xx < X then Continue;
      if GZrRoots[i] < t then
      begin
        if yy < Y0 then w := w + unitW else w := w - unitW;
      end
      else
      begin
        if Y2 < yy then w := w + unitW else w := w - unitW;
      end;
    end;
    Result := w;
  end
  else
  begin
    if (GZrRoots[0] = 0) or (GZrRoots[0] = 1) then unitW := 0.5 else unitW := 1;
    xx := CvQuadraticAt(X0, X1, X2, GZrRoots[0]);
    if xx < X then Exit(0);
    if Y2 < Y0 then Result := unitW else Result := -unitW;
  end;
end;

function ZrWindingArc(CX, CY, R, AStart, AEnd: Double; AAnti: Boolean; X, Y: Double): Double;
var tmp, dTheta, w, angle, dir, pi2: Double; i: Integer;
begin
  pi2 := Pi * 2;
  Y := Y - CY;
  if (Y > R) or (Y < -R) then Exit(0);
  tmp := Sqrt(R * R - Y * Y);
  GZrRoots[0] := -tmp;
  GZrRoots[1] := tmp;
  dTheta := Abs(AStart - AEnd);
  if dTheta < 1e-4 then Exit(0);
  if dTheta >= pi2 - 1e-4 then
  begin
    if AAnti then dir := 1 else dir := -1;
    if (X >= GZrRoots[0] + CX) and (X <= GZrRoots[1] + CX) then Exit(dir);
    Exit(0);
  end;
  if AStart > AEnd then
  begin
    tmp := AStart;
    AStart := AEnd;
    AEnd := tmp;
  end;
  if AStart < 0 then
  begin
    AStart := AStart + pi2;
    AEnd := AEnd + pi2;
  end;
  w := 0;
  for i := 0 to 1 do
  begin
    if GZrRoots[i] + CX > X then
    begin
      angle := TyJsAtan2(Y, GZrRoots[i]);
      if AAnti then dir := 1 else dir := -1;
      if angle < 0 then angle := pi2 + angle;
      if ((angle >= AStart) and (angle <= AEnd))
        or ((angle + pi2 >= AStart) and (angle + pi2 <= AEnd)) then
      begin
        if (angle > Pi / 2) and (angle < Pi * 1.5) then dir := -dir;
        w := w + dir;
      end;
    end;
  end;
  Result := w;
end;

{ contain/line.ts }
function ZrLineStroke(X0, Y0, X1, Y1, ALineWidth, X, Y: Double): Boolean;
var l, a, b, tmp, s: Double;
begin
  if ALineWidth = 0 then Exit(False);
  l := ALineWidth;
  if ((Y > Y0 + l) and (Y > Y1 + l)) or ((Y < Y0 - l) and (Y < Y1 - l))
    or ((X > X0 + l) and (X > X1 + l)) or ((X < X0 - l) and (X < X1 - l)) then Exit(False);
  if X0 <> X1 then
  begin
    a := (Y0 - Y1) / (X0 - X1);
    b := (X0 * Y1 - X1 * Y0) / (X0 - X1);
  end
  else
    Exit(Abs(X - X0) <= l / 2);
  tmp := a * X - Y + b;
  s := tmp * tmp / (a * a + 1);
  Result := s <= l / 2 * l / 2;
end;

function DistSq(AX, AY, BX, BY: Double): Double;
begin
  Result := (AX - BX) * (AX - BX) + (AY - BY) * (AY - BY);
end;

{ curve.ts cubicProjectPoint / quadraticProjectPoint: the distance }
function ZrProjectPoint(AQuad: Boolean; X0, Y0, X1, Y1, X2, Y2, X3, Y3, X, Y: Double): Double;
var
  t, interval, d, prev, next, d1, d2, tt: Double;
  i: Integer;

  function AtX(AT: Double): Double;
  begin
    if AQuad then Result := CvQuadraticAt(X0, X1, X2, AT)
    else Result := CvCubicAt(X0, X1, X2, X3, AT);
  end;

  function AtY(AT: Double): Double;
  begin
    if AQuad then Result := CvQuadraticAt(Y0, Y1, Y2, AT)
    else Result := CvCubicAt(Y0, Y1, Y2, Y3, AT);
  end;

begin
  t := NaN;
  interval := 0.005;
  d := Infinity;
  tt := 0;
  while tt < 1 do
  begin
    d1 := DistSq(X, Y, AtX(tt), AtY(tt));
    if d1 < d then
    begin
      t := tt;
      d := d1;
    end;
    tt := tt + 0.05;
  end;
  d := Infinity;
  for i := 0 to 31 do
  begin
    if interval < cCurveNumeric then Break;
    prev := t - interval;
    next := t + interval;
    d1 := DistSq(AtX(prev), AtY(prev), X, Y);
    if (prev >= 0) and (d1 < d) then
    begin
      t := prev;
      d := d1;
    end
    else
    begin
      d2 := DistSq(AtX(next), AtY(next), X, Y);
      if (next <= 1) and (d2 < d) then
      begin
        t := next;
        d := d2;
      end
      else
        interval := interval * 0.5;
    end;
  end;
  Result := Sqrt(d);
end;

function ZrCubicStroke(X0, Y0, X1, Y1, X2, Y2, X3, Y3, ALineWidth, X, Y: Double): Boolean;
var l: Double;
begin
  if ALineWidth = 0 then Exit(False);
  l := ALineWidth;
  if ((Y > Y0 + l) and (Y > Y1 + l) and (Y > Y2 + l) and (Y > Y3 + l))
    or ((Y < Y0 - l) and (Y < Y1 - l) and (Y < Y2 - l) and (Y < Y3 - l))
    or ((X > X0 + l) and (X > X1 + l) and (X > X2 + l) and (X > X3 + l))
    or ((X < X0 - l) and (X < X1 - l) and (X < X2 - l) and (X < X3 - l)) then Exit(False);
  Result := ZrProjectPoint(False, X0, Y0, X1, Y1, X2, Y2, X3, Y3, X, Y) <= l / 2;
end;

function ZrQuadraticStroke(X0, Y0, X1, Y1, X2, Y2, ALineWidth, X, Y: Double): Boolean;
var l: Double;
begin
  if ALineWidth = 0 then Exit(False);
  l := ALineWidth;
  if ((Y > Y0 + l) and (Y > Y1 + l) and (Y > Y2 + l))
    or ((Y < Y0 - l) and (Y < Y1 - l) and (Y < Y2 - l))
    or ((X > X0 + l) and (X > X1 + l) and (X > X2 + l))
    or ((X < X0 - l) and (X < X1 - l) and (X < X2 - l)) then Exit(False);
  Result := ZrProjectPoint(True, X0, Y0, X1, Y1, X2, Y2, 0, 0, X, Y) <= l / 2;
end;

function ZrNormalizeRadian(A: Double): Double;
var pi2: Double;
begin
  pi2 := Pi * 2;
  Result := TyJsFMod(A, pi2);
  if Result < 0 then Result := Result + pi2;
end;

{ contain/arc.ts }
function ZrArcStroke(CX, CY, R, AStart, AEnd: Double; AAnti: Boolean;
  ALineWidth, X, Y: Double): Boolean;
var l, d, tmp, angle, pi2: Double;
begin
  if ALineWidth = 0 then Exit(False);
  pi2 := Pi * 2;
  l := ALineWidth;
  X := X - CX;
  Y := Y - CY;
  d := Sqrt(X * X + Y * Y);
  if (d - l > R) or (d + l < R) then Exit(False);
  if TyJsFMod(Abs(AStart - AEnd), pi2) < 1e-4 then Exit(True);
  if AAnti then
  begin
    tmp := AStart;
    AStart := ZrNormalizeRadian(AEnd);
    AEnd := ZrNormalizeRadian(tmp);
  end
  else
  begin
    AStart := ZrNormalizeRadian(AStart);
    AEnd := ZrNormalizeRadian(AEnd);
  end;
  if AStart > AEnd then AEnd := AEnd + pi2;
  angle := TyJsAtan2(Y, X);
  if angle < 0 then angle := angle + pi2;
  Result := ((angle >= AStart) and (angle <= AEnd))
    or ((angle + pi2 >= AStart) and (angle + pi2 <= AEnd));
end;

{ containPath }
function ZrContainPath(const APath: TTyZrPath; ALineWidth: Double; AIsStroke: Boolean;
  X, Y: Double): Boolean;
var
  i: Integer;
  w, xi, yi, x0, y0, x1, y1, cx, cy, rx, ry, theta, dTheta, xs, wd, ht: Double;
  isFirst, anti: Boolean;
  s: TTyZrSeg;
begin
  w := 0;
  xi := 0; yi := 0; x0 := 0; y0 := 0;
  for i := 0 to High(APath) do
  begin
    s := APath[i];
    isFirst := i = 0;
    if (s.Cmd = zrM) and (i > 0) then
      if not AIsStroke then w := w + ZrWindingLine(xi, yi, x0, y0, X, Y);
    if isFirst then
    begin
      xi := s.V[0];
      yi := s.V[1];
      x0 := xi;
      y0 := yi;
    end;
    case s.Cmd of
      zrM:
        begin
          x0 := s.V[0];
          y0 := s.V[1];
          xi := x0;
          yi := y0;
        end;
      zrL:
        begin
          if AIsStroke then
          begin
            if ZrLineStroke(xi, yi, s.V[0], s.V[1], ALineWidth, X, Y) then Exit(True);
          end
          else
            w := w + OrNought(ZrWindingLine(xi, yi, s.V[0], s.V[1], X, Y));
          xi := s.V[0];
          yi := s.V[1];
        end;
      zrC:
        begin
          if AIsStroke then
          begin
            if ZrCubicStroke(xi, yi, s.V[0], s.V[1], s.V[2], s.V[3], s.V[4], s.V[5],
              ALineWidth, X, Y) then Exit(True);
          end
          else
            w := w + OrNought(ZrWindingCubic(xi, yi, s.V[0], s.V[1], s.V[2], s.V[3],
              s.V[4], s.V[5], X, Y));
          xi := s.V[4];
          yi := s.V[5];
        end;
      zrQ:
        begin
          if AIsStroke then
          begin
            if ZrQuadraticStroke(xi, yi, s.V[0], s.V[1], s.V[2], s.V[3],
              ALineWidth, X, Y) then Exit(True);
          end
          else
            w := w + OrNought(ZrWindingQuadratic(xi, yi, s.V[0], s.V[1], s.V[2], s.V[3], X, Y));
          xi := s.V[2];
          yi := s.V[3];
        end;
      zrA:
        begin
          cx := s.V[0];
          cy := s.V[1];
          rx := s.V[2];
          ry := s.V[3];
          theta := s.V[4];
          dTheta := s.V[5];
          anti := (1 - s.V[7]) <> 0;
          x1 := TyJsCos(theta) * rx + cx;
          y1 := TyJsSin(theta) * ry + cy;
          if not isFirst then
            w := w + ZrWindingLine(xi, yi, x1, y1, X, Y)
          else
          begin
            x0 := x1;
            y0 := y1;
          end;
          xs := (X - cx) * ry / rx + cx;
          if AIsStroke then
          begin
            if ZrArcStroke(cx, cy, ry, theta, theta + dTheta, anti, ALineWidth, xs, Y) then
              Exit(True);
          end
          else
            w := w + ZrWindingArc(cx, cy, ry, theta, theta + dTheta, anti, xs, Y);
          xi := TyJsCos(theta + dTheta) * rx + cx;
          yi := TyJsSin(theta + dTheta) * ry + cy;
        end;
      zrR:
        begin
          x0 := s.V[0];
          xi := x0;
          y0 := s.V[1];
          yi := y0;
          wd := s.V[2];
          ht := s.V[3];
          x1 := x0 + wd;
          y1 := y0 + ht;
          if AIsStroke then
          begin
            if ZrLineStroke(x0, y0, x1, y0, ALineWidth, X, Y)
              or ZrLineStroke(x1, y0, x1, y1, ALineWidth, X, Y)
              or ZrLineStroke(x1, y1, x0, y1, ALineWidth, X, Y)
              or ZrLineStroke(x0, y1, x0, y0, ALineWidth, X, Y) then Exit(True);
          end
          else
          begin
            w := w + ZrWindingLine(x1, y0, x1, y1, X, Y);
            w := w + ZrWindingLine(x0, y1, x0, y0, X, Y);
          end;
        end;
      zrZ:
        begin
          if AIsStroke then
          begin
            if ZrLineStroke(xi, yi, x0, y0, ALineWidth, X, Y) then Exit(True);
          end
          else
            w := w + ZrWindingLine(xi, yi, x0, y0, X, Y);
          xi := x0;
          yi := y0;
        end;
    end;
  end;
  if (not AIsStroke) and not (Abs(yi - y0) < cWindEps) then
    w := w + OrNought(ZrWindingLine(xi, yi, x0, y0, X, Y));
  Result := w <> 0;
end;

procedure TyZrRestoreFpu(const AOld: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AOld);
end;

{ upstream's arithmetic divides by nought and meets not-a-numbers (a
  degenerate cubic's roots): JavaScript's quiet values, not traps }
function TyZrContain(const APath: TTyZrPath; AX, AY: Double): Boolean;
var old: TFPUExceptionMask;
begin
  old := GetExceptionMask;
  SetExceptionMask(old + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    Result := ZrContainPath(APath, 0, False, AX, AY);
  finally
    TyZrRestoreFpu(old);
  end;
end;

function TyZrContainStroke(const APath: TTyZrPath; ALineWidth, AX, AY: Double): Boolean;
var old: TFPUExceptionMask;
begin
  old := GetExceptionMask;
  SetExceptionMask(old + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    Result := ZrContainPath(APath, ALineWidth, True, AX, AY);
  finally
    TyZrRestoreFpu(old);
  end;
end;

end.
