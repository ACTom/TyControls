unit tyControls.AdvChart.Easing;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- zrender's easing functions, to the bit. [Batch 87, AN1]

  WHAT AN EASING IS. A clip hands its percent k in [0, 1] to one function and
  the answer is the weight every track of that clip interpolates with. There
  are 31 named functions (zrender/src/animation/easing.ts) and a
  `cubic-bezier(x1,y1,x2,y2)` form (animation/cubicEasing.ts over the root
  solver in core/curve.ts). Anything else -- an unknown name, a wrong case,
  an empty string, a bezier the pattern does not accept -- resolves to
  NOTHING, and the clip then uses the raw percent: linear, with no error.

  THE OPERATION ORDER IS UPSTREAM'S. `--k` and `k -= c` change k before the
  rest of the expression reads it, and `*` associates left to right, so
  `7.5625 * (k -= c) * k` is (7.5625 * m) * m and `0.5 * k * k * k` is
  ((0.5 * k) * k) * k. Every function below is the same sequence of double
  operations, and Math.pow, Math.sin, Math.cos and Math.acos are V8's
  (tyControls.AdvChart.JsMath) -- FPC's Power and Sin part from them in the
  last place. Math.sqrt is IEEE in both.

  THE CONSTANTS ARE DOUBLES FROM THEIR BITS where the decimal is not a binary
  fraction (1.70158, 1.525, 0.4, 1e-8): an untyped real literal can be read
  as a Single, and FPC's decimal reading is not always correctly rounded.

  THE ELASTIC CONSTANTS. Upstream declares a = 0.1, p = 0.4; `!a || a < 1` is
  always true, so a becomes 1 and s = p / 4, and the asin branch is dead.
  1 * x is x exactly, so the a factor is kept only where it changes nothing.

  THE DEGENERATE BEZIER. cubicRootAt writes a root but does not COUNT it when
  the cubic is flat (A, B and b all about zero): it returns 0, and upstream's
  `cubicRootAt(...) && cubicAt(...)` is then the number 0. A bezier whose x(t)
  is t itself -- cubic-bezier(1/3, 0, 2/3, 1) -- is therefore 0 on the whole
  open interval and 1 at the end. Kept, because the fixture has it.

  A NAMED HANDLER stands where upstream takes a JavaScript function:
  `animationEasing: '@Name'` resolves through the registry below.

  LCL-free: SysUtils, Math and the AdvChart units. }
interface
uses SysUtils, Math, tyControls.AdvChart.JsMath;

const
  TY_EASING_COUNT = 31;
  { The names in upstream's own order (easing.ts). Lookup is case-sensitive,
    as a JavaScript property is. }
  TyEasingNames: array[0..TY_EASING_COUNT - 1] of string = (
    'linear',
    'quadraticIn', 'quadraticOut', 'quadraticInOut',
    'cubicIn', 'cubicOut', 'cubicInOut',
    'quarticIn', 'quarticOut', 'quarticInOut',
    'quinticIn', 'quinticOut', 'quinticInOut',
    'sinusoidalIn', 'sinusoidalOut', 'sinusoidalInOut',
    'exponentialIn', 'exponentialOut', 'exponentialInOut',
    'circularIn', 'circularOut', 'circularInOut',
    'elasticIn', 'elasticOut', 'elasticInOut',
    'backIn', 'backOut', 'backInOut',
    'bounceIn', 'bounceOut', 'bounceInOut');

type
  { An easing a host registered by name, for `animationEasing: '@Name'`. }
  TTyEasingHandler = function(APercent: Double): Double of object;

  TTyEasingKind = (
    ekNone,     // unresolved: the clip uses the raw percent
    ekNamed,    // one of the 31, by Index
    ekBezier,   // cubic-bezier(A, B, C, D) = (x1, y1, x2, y2)
    ekHandler); // a registered handler

  TTyEasing = record
    Kind: TTyEasingKind;
    Index: Integer;
    A, B, C, D: Double;
    Handler: TTyEasingHandler;
    { the spec as written, for diagnostics }
    Spec: string;
  end;

{ The named function AIndex (0..30) at AK. }
function TyEasingByIndex(AIndex: Integer; AK: Double): Double;
{ The index of a name, or -1. Case-sensitive. }
function TyEasingIndexOf(const AName: string): Integer;

{ core/curve.ts cubicAt: onet*onet*(onet*p0 + 3*t*p1) + t*t*(t*p3 + 3*onet*p2). }
function TyCubicAt(AP0, AP1, AP2, AP3, AT: Double): Double;
{ core/curve.ts cubicRootAt: the roots in [0, 1] of the cubic through
  AP0..AP3 at AVal, by Shengjin's formula, in upstream's push order; the
  answer is how many were COUNTED (see the header: the flat case writes
  ARoots[0] and answers 0). ARoots needs room for three. }
function TyCubicRootAt(AP0, AP1, AP2, AP3, AVal: Double;
  var ARoots: array of Double): Integer;
{ animation/cubicEasing.ts: the regexp /cubic-bezier\(([0-9,\.e ]+)\)/ -- no
  sign, so a negative control point does not match -- anywhere in AText, the
  capture split at commas, each piece trimmed and taken by Number(); a piece
  that is not there is +null, which is 0. False when there is no match or the
  sum of the four is not-a-number. }
function TyCubicBezierParse(const AText: string; out AX1, AY1, AX2, AY2: Double): Boolean;
{ The bezier easing at AP: 0 at or below 0, 1 at or above 1, else the y at
  the first root of x(t) = AP -- or 0 when no root was counted. }
function TyCubicBezierAt(AX1, AY1, AX2, AY2, AP: Double): Double;

{ Clip.setEasing: a name first, then a bezier, then (the port's addition) a
  '@Name' handler; anything else is ekNone. }
function TyEasingResolve(const ASpec: string): TTyEasing;
{ The schedule a clip hands its tracks: the easing at AP, or AP itself when
  the easing is ekNone. }
function TyEasingApply(const AEasing: TTyEasing; AP: Double): Double;
{ ekNone }
function TyEasingNone: TTyEasing;

{ ---- the registry for '@Name' easings ----
  Registering a name twice replaces it. Names are case-sensitive (unlike the
  formatter registry) because the named easings they sit beside are. }
procedure TyChartRegisterEasing(const AName: string; AHandler: TTyEasingHandler);
procedure TyChartUnregisterEasing(const AName: string);
function TyChartFindEasing(const AName: string; out AHandler: TTyEasingHandler): Boolean;
procedure TyChartClearEasings;

implementation

uses tyControls.AdvChart.Data;

var
  { the constants, from their bits (see the header) }
  cPi, cBackS, cBack1525, cElasticP, cEps, cOneThird, cThreeSqrt: Double;
  { binary fractions: exact in any reading, typed here so no expression
    folds them into a Single }
  cHalf, cBounce, cB275, cB15, cB225, cB2625, cB25, c075, c09375, c0984375: Double;

type
  TEasingEntry = record
    Name: string;
    Handler: TTyEasingHandler;
  end;

var
  GEasings: array of TEasingEntry;

function FromBits(AQ: QWord): Double;
begin
  Move(AQ, Result, SizeOf(Result));
end;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  { the SSE sticky flags too: ClearExceptions only clears the x87 word here }
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ ==================== the 31 ==================== }

function BounceOut(k: Double): Double;
var m: Double;
begin
  if k < (1 / cB275) then
    Result := cBounce * k * k
  else if k < (2 / cB275) then
  begin
    m := k - (cB15 / cB275);
    Result := cBounce * m * m + c075;
  end
  else if k < (cB25 / cB275) then
  begin
    m := k - (cB225 / cB275);
    Result := cBounce * m * m + c09375;
  end
  else
  begin
    m := k - (cB2625 / cB275);
    Result := cBounce * m * m + c0984375;
  end;
end;

function BounceIn(k: Double): Double;
begin
  Result := 1 - BounceOut(1 - k);
end;

function TyEasingByIndex(AIndex: Integer; AK: Double): Double;
var
  k, k2, m, s, p: Double;
begin
  k := AK;
  case AIndex of
    0: Result := k;
    { quadratic }
    1: Result := k * k;
    2: Result := k * (2 - k);
    3: begin
         k2 := k * 2;
         if k2 < 1 then Result := cHalf * k2 * k2
         else
         begin
           m := k2 - 1;
           Result := -cHalf * (m * (m - 2) - 1);
         end;
       end;
    { cubic }
    4: Result := k * k * k;
    5: begin
         m := k - 1;
         Result := m * m * m + 1;
       end;
    6: begin
         k2 := k * 2;
         if k2 < 1 then Result := cHalf * k2 * k2 * k2
         else
         begin
           m := k2 - 2;
           Result := cHalf * (m * m * m + 2);
         end;
       end;
    { quartic }
    7: Result := k * k * k * k;
    8: begin
         m := k - 1;
         Result := 1 - (m * m * m * m);
       end;
    9: begin
         k2 := k * 2;
         if k2 < 1 then Result := cHalf * k2 * k2 * k2 * k2
         else
         begin
           m := k2 - 2;
           Result := -cHalf * (m * m * m * m - 2);
         end;
       end;
    { quintic }
    10: Result := k * k * k * k * k;
    11: begin
          m := k - 1;
          Result := m * m * m * m * m + 1;
        end;
    12: begin
          k2 := k * 2;
          if k2 < 1 then Result := cHalf * k2 * k2 * k2 * k2 * k2
          else
          begin
            m := k2 - 2;
            Result := cHalf * (m * m * m * m * m + 2);
          end;
        end;
    { sinusoidal: k * Math.PI / 2 is (k * PI) / 2 }
    13: Result := 1 - TyJsCos(k * cPi / 2);
    14: Result := TyJsSin(k * cPi / 2);
    15: Result := cHalf * (1 - TyJsCos(cPi * k));
    { exponential }
    16: if k = 0 then Result := 0
        else Result := TyJsPow(1024, k - 1);
    17: if k = 1 then Result := 1
        else Result := 1 - TyJsPow(2, -10 * k);
    18: if k = 0 then Result := 0
        else if k = 1 then Result := 1
        else
        begin
          k2 := k * 2;
          if k2 < 1 then Result := cHalf * TyJsPow(1024, k2 - 1)
          else Result := cHalf * (-TyJsPow(2, -10 * (k2 - 1)) + 2);
        end;
    { circular }
    19: Result := 1 - Sqrt(1 - k * k);
    20: begin
          m := k - 1;
          Result := Sqrt(1 - (m * m));
        end;
    21: begin
          k2 := k * 2;
          if k2 < 1 then Result := -cHalf * (Sqrt(1 - k2 * k2) - 1)
          else
          begin
            m := k2 - 2;
            Result := cHalf * (Sqrt(1 - m * m) + 1);
          end;
        end;
    { elastic: a = 1, s = p / 4; (m - s) * (2 * PI) / p }
    22: if k = 0 then Result := 0
        else if k = 1 then Result := 1
        else
        begin
          p := cElasticP;
          s := p / 4;
          m := k - 1;
          Result := -(TyJsPow(2, 10 * m) * TyJsSin((m - s) * (2 * cPi) / p));
        end;
    23: if k = 0 then Result := 0
        else if k = 1 then Result := 1
        else
        begin
          p := cElasticP;
          s := p / 4;
          Result := TyJsPow(2, -10 * k) * TyJsSin((k - s) * (2 * cPi) / p) + 1;
        end;
    24: if k = 0 then Result := 0
        else if k = 1 then Result := 1
        else
        begin
          p := cElasticP;
          s := p / 4;
          k2 := k * 2;
          m := k2 - 1;
          if k2 < 1 then
            Result := -cHalf * (TyJsPow(2, 10 * m) * TyJsSin((m - s) * (2 * cPi) / p))
          else
            Result := TyJsPow(2, -10 * m) * TyJsSin((m - s) * (2 * cPi) / p) * cHalf + 1;
        end;
    { back }
    25: begin
          s := cBackS;
          Result := k * k * ((s + 1) * k - s);
        end;
    26: begin
          s := cBackS;
          m := k - 1;
          Result := m * m * ((s + 1) * m + s) + 1;
        end;
    27: begin
          s := cBackS * cBack1525;
          k2 := k * 2;
          if k2 < 1 then
            Result := cHalf * (k2 * k2 * ((s + 1) * k2 - s))
          else
          begin
            m := k2 - 2;
            Result := cHalf * (m * m * ((s + 1) * m + s) + 2);
          end;
        end;
    { bounce }
    28: Result := BounceIn(k);
    29: Result := BounceOut(k);
    30: if k < cHalf then Result := BounceIn(k * 2) * cHalf
        else Result := BounceOut(k * 2 - 1) * cHalf + cHalf;
  else
    Result := k;
  end;
end;

function TyEasingIndexOf(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to TY_EASING_COUNT - 1 do
    if TyEasingNames[i] = AName then Exit(i);
  Result := -1;
end;

{ ==================== the bezier ==================== }

function TyCubicAt(AP0, AP1, AP2, AP3, AT: Double): Double;
var onet: Double;
begin
  onet := 1 - AT;
  Result := onet * onet * (onet * AP0 + 3 * AT * AP1)
    + AT * AT * (AT * AP3 + 3 * onet * AP2);
end;

function AroundZero(AV: Double): Boolean; inline;
begin
  Result := (AV > -cEps) and (AV < cEps);
end;

function TyCubicRootAt(AP0, AP1, AP2, AP3, AVal: Double;
  var ARoots: array of Double): Integer;
var
  a, b, c, d, bigA, bigB, bigC, disc, K, t1, t2, t3, ds, Y1, Y2, T, theta,
    aSqrt, tmp: Double;
  n: Integer;
begin
  a := AP3 + 3 * (AP1 - AP2) - AP0;
  b := 3 * (AP2 - AP1 * 2 + AP0);
  c := 3 * (AP1 - AP0);
  d := AP0 - AVal;

  bigA := b * b - 3 * a * c;
  bigB := b * c - 9 * a * d;
  bigC := c * c - 3 * b * d;

  n := 0;
  if AroundZero(bigA) and AroundZero(bigB) then
  begin
    if AroundZero(b) then
      { written, not counted: upstream returns 0 here }
      ARoots[0] := 0
    else
    begin
      t1 := -c / b;
      if (t1 >= 0) and (t1 <= 1) then
      begin
        ARoots[n] := t1;
        Inc(n);
      end;
    end;
  end
  else
  begin
    disc := bigB * bigB - 4 * bigA * bigC;
    if AroundZero(disc) then
    begin
      K := bigB / bigA;
      t1 := -b / a + K;
      t2 := -K / 2;
      if (t1 >= 0) and (t1 <= 1) then
      begin
        ARoots[n] := t1;
        Inc(n);
      end;
      if (t2 >= 0) and (t2 <= 1) then
      begin
        ARoots[n] := t2;
        Inc(n);
      end;
    end
    else if disc > 0 then
    begin
      ds := Sqrt(disc);
      Y1 := bigA * b + 1.5 * a * (-bigB + ds);
      Y2 := bigA * b + 1.5 * a * (-bigB - ds);
      if Y1 < 0 then Y1 := -TyJsPow(-Y1, cOneThird)
      else Y1 := TyJsPow(Y1, cOneThird);
      if Y2 < 0 then Y2 := -TyJsPow(-Y2, cOneThird)
      else Y2 := TyJsPow(Y2, cOneThird);
      t1 := (-b - (Y1 + Y2)) / (3 * a);
      if (t1 >= 0) and (t1 <= 1) then
      begin
        ARoots[n] := t1;
        Inc(n);
      end;
    end
    else
    begin
      T := (2 * bigA * b - 3 * a * bigB) / (2 * Sqrt(bigA * bigA * bigA));
      theta := TyJsAcos(T) / 3;
      aSqrt := Sqrt(bigA);
      tmp := TyJsCos(theta);
      t1 := (-b - 2 * aSqrt * tmp) / (3 * a);
      t2 := (-b + aSqrt * (tmp + cThreeSqrt * TyJsSin(theta))) / (3 * a);
      t3 := (-b + aSqrt * (tmp - cThreeSqrt * TyJsSin(theta))) / (3 * a);
      if (t1 >= 0) and (t1 <= 1) then
      begin
        ARoots[n] := t1;
        Inc(n);
      end;
      if (t2 >= 0) and (t2 <= 1) then
      begin
        ARoots[n] := t2;
        Inc(n);
      end;
      if (t3 >= 0) and (t3 <= 1) then
      begin
        ARoots[n] := t3;
        Inc(n);
      end;
    end;
  end;
  Result := n;
end;

function InBezierClass(ACh: Char): Boolean; inline;
begin
  Result := ACh in ['0'..'9', ',', '.', 'e', ' '];
end;

function TyCubicBezierParse(const AText: string; out AX1, AY1, AX2, AY2: Double): Boolean;
const
  cHead = 'cubic-bezier(';
var
  from, p, q, i, start, cnt: Integer;
  cap, piece: string;
  vals: array[0..3] of Double;
  mask: TFPUExceptionMask;
begin
  AX1 := 0; AY1 := 0; AX2 := 0; AY2 := 0;
  Result := False;
  if AText = '' then Exit;
  cap := '';
  from := 1;
  { exec: the first place the whole pattern matches. The class holds neither
    parenthesis, so at one place the run of class characters is maximal and
    must be followed by ')'. }
  repeat
    p := Pos(cHead, Copy(AText, from, MaxInt));
    if p = 0 then Exit;
    p := p + from - 1;
    q := p + Length(cHead);
    start := q;
    while (q <= Length(AText)) and InBezierClass(AText[q]) do Inc(q);
    if (q > start) and (q <= Length(AText)) and (AText[q] = ')') then
    begin
      cap := Copy(AText, start, q - start);
      Break;
    end;
    from := p + 1;
  until False;
  { split(','), then +trim(points[i]); a missing piece is +null = 0 }
  for i := 0 to 3 do vals[i] := 0;
  cnt := 0;
  piece := '';
  mask := MaskFP;
  try
    for i := 1 to Length(cap) + 1 do
    begin
      if (i > Length(cap)) or (cap[i] = ',') then
      begin
        if cnt <= 3 then vals[cnt] := TyJsToNumber(piece);
        Inc(cnt);
        piece := '';
      end
      else
        piece := piece + cap[i];
    end;
    AX1 := vals[0]; AY1 := vals[1]; AX2 := vals[2]; AY2 := vals[3];
    Result := not IsNan(AX1 + AY1 + AX2 + AY2);
  finally
    UnmaskFP(mask);
  end;
end;

function BezierAt(AX1, AY1, AX2, AY2, AP: Double): Double;
var
  roots: array[0..2] of Double;
begin
  if AP <= 0 then Exit(0);
  if AP >= 1 then Exit(1);
  roots[0] := 0; roots[1] := 0; roots[2] := 0;
  if TyCubicRootAt(0, AX1, AX2, 1, AP, roots) = 0 then
    Result := 0
  else
    Result := TyCubicAt(0, AY1, AY2, 1, roots[0]);
end;

function TyCubicBezierAt(AX1, AY1, AX2, AY2, AP: Double): Double;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    Result := BezierAt(AX1, AY1, AX2, AY2, AP);
  finally
    UnmaskFP(mask);
  end;
end;

{ ==================== resolution ==================== }

function TyEasingNone: TTyEasing;
begin
  Result := Default(TTyEasing);
  Result.Kind := ekNone;
  Result.Index := -1;
end;

function TyEasingResolve(const ASpec: string): TTyEasing;
var
  i: Integer;
  h: TTyEasingHandler;
begin
  Result := TyEasingNone;
  Result.Spec := ASpec;
  if ASpec = '' then Exit;
  i := TyEasingIndexOf(ASpec);
  if i >= 0 then
  begin
    Result.Kind := ekNamed;
    Result.Index := i;
    Exit;
  end;
  if TyCubicBezierParse(ASpec, Result.A, Result.B, Result.C, Result.D) then
  begin
    Result.Kind := ekBezier;
    Exit;
  end;
  if (Length(ASpec) > 1) and (ASpec[1] = '@')
    and TyChartFindEasing(Copy(ASpec, 2, MaxInt), h) and Assigned(h) then
  begin
    Result.Kind := ekHandler;
    Result.Handler := h;
  end;
end;

function TyEasingApply(const AEasing: TTyEasing; AP: Double): Double;
var mask: TFPUExceptionMask;
begin
  case AEasing.Kind of
    ekNone: Result := AP;
    ekHandler: Result := AEasing.Handler(AP);
  else
    mask := MaskFP;
    try
      if AEasing.Kind = ekNamed then
        Result := TyEasingByIndex(AEasing.Index, AP)
      else
        Result := BezierAt(AEasing.A, AEasing.B, AEasing.C, AEasing.D, AP);
    finally
      UnmaskFP(mask);
    end;
  end;
end;

{ ==================== the registry ==================== }

function IndexOfEasing(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GEasings) do
    if GEasings[i].Name = AName then Exit(i);
  Result := -1;
end;

procedure TyChartRegisterEasing(const AName: string; AHandler: TTyEasingHandler);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfEasing(AName);
  if i < 0 then
  begin
    i := Length(GEasings);
    SetLength(GEasings, i + 1);
    GEasings[i].Name := AName;
  end;
  GEasings[i].Handler := AHandler;
end;

procedure TyChartUnregisterEasing(const AName: string);
var i, j: Integer;
begin
  i := IndexOfEasing(AName);
  if i < 0 then Exit;
  for j := i to High(GEasings) - 1 do
    GEasings[j] := GEasings[j + 1];
  SetLength(GEasings, Length(GEasings) - 1);
end;

function TyChartFindEasing(const AName: string; out AHandler: TTyEasingHandler): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfEasing(AName);
  Result := i >= 0;
  if Result then AHandler := GEasings[i].Handler;
end;

procedure TyChartClearEasings;
begin
  GEasings := nil;
end;

initialization
  cPi := FromBits($400921FB54442D18);
  cBackS := FromBits($3FFB39ABF3387161);      // 1.70158
  cBack1525 := FromBits($3FF8666666666666);   // 1.525
  cElasticP := FromBits($3FD999999999999A);   // 0.4
  cEps := FromBits($3E45798EE2308C3A);        // 1e-8
  cOneThird := 1 / Double(3);
  cThreeSqrt := Sqrt(Double(3));
  cHalf := 0.5;
  cBounce := 7.5625;
  cB275 := 2.75;
  cB15 := 1.5;
  cB225 := 2.25;
  cB2625 := 2.625;
  cB25 := 2.5;
  c075 := 0.75;
  c09375 := 0.9375;
  c0984375 := 0.984375;
end.
