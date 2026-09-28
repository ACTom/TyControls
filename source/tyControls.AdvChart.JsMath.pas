unit tyControls.AdvChart.JsMath;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- JavaScript's Math.sin, cos, atan and atan2, to the bit.

  WHY NOT FPC'S. The run-time library's Sin and Cos come out one unit in the
  last place away from V8's for ordinary arguments -- sin 2, cos 7 pi / 4 --
  and its ArcTan2 answers +pi for (-6.1e-17, -1), which is minus pi turned
  the wrong way round. A y axis is turned a quarter, and the name laid out on
  it goes through that turn and back: every one of those bits lands in where
  upstream puts it.

  WHAT V8 COMPUTES is fdlibm (src/base/ieee754.cc), and this is fdlibm
  transcribed operation for operation: the same argument reduction by pi/2
  in three pieces, the same kernel polynomials, the same special cases. It
  was first transcribed in JavaScript and matched node's Math on 2.4 million
  arguments bit for bit; tools/advchart-oracle/js-math.js holds the Pascal to
  the same answers.

  THE CONSTANTS ARE BITS. FPC's reading of a decimal literal is not always
  correctly rounded, so each is written as the pattern node gives for
  fdlibm's own decimal.

  PAST 2^19 pi/2 (about 823,550 radians) fdlibm reduces with a table of 2/pi
  to over a thousand bits; that path is not here and those arguments fall to
  the run-time library. No chart turns anything that far. }
interface

function TyJsSin(AX: Double): Double;
function TyJsCos(AX: Double): Double;
function TyJsAtan(AX: Double): Double;
function TyJsAtan2(AY, AX: Double): Double;
{ Math.acos: fdlibm's e_acos.c, as V8's ieee754::acos. zrender's arc
  parser measures the angle between two radii with it, so an SVG icon's
  arcs start where upstream's do only through this. }
function TyJsAcos(AX: Double): Double;
{ Math.tan: fdlibm's s_tan.c and V8's __kernel_tan. zrender recomposes a
  turned label's matrix from its decomposed skew, and a skew of 2 pi --
  which a label turned past a quarter comes to -- is where FPC's Tan and
  V8's part: `BCB1A60000000000` against `BCB1A62633145C07`. }
function TyJsTan(AX: Double): Double;
{ Math.fround: the nearest single, ties to even, and past the largest single
  -- by half a unit of its last place -- an infinity. Upstream keeps a line's
  vertices in a Float32Array, so a vertex is this of the coordinate. }
function TyJsFround(AX: Double): Double;
{ Math.log and Math.pow as V8 answers them: fdlibm's e_log.c, and e_pow.c
  with V8's one change. FPC's Power is exp(y ln x) and parts from V8 by up
  to a dozen units in the last place at a fractional exponent -- every log
  axis' mapping end, every pixel taken back to a value on one. }
function TyJsLog(AX: Double): Double;
function TyJsPow(AX, AY: Double): Double;

implementation

uses Math;

var
  invpio2, pio2_1, pio2_1t, pio2_2, pio2_2t, pio2_3, pio2_3t: Double;
  S1, S2, S3, S4, S5, S6: Double;
  C1, C2, C3, C4, C5, C6: Double;
  { k_tan.c }
  TT: array[0..12] of Double;
  atanhi, atanlo: array[0..3] of Double;
  aT: array[0..10] of Double;
  pi_o_4, pi_o_2, pi_, pi_lo, tiny: Double;
  { a literal -0.0 may be folded to +0.0 }
  negZero: Double;
  { e_log.c }
  lg_ln2_hi, lg_ln2_lo, lg_two54, lg_third: Double;
  Lg1, Lg2, Lg3, Lg4, Lg5, Lg6, Lg7: Double;
  { e_pow.c }
  pw_dp_h1, pw_dp_l1, pw_two53, pw_twom54: Double;
  pw_L1, pw_L2, pw_L3, pw_L4, pw_L5, pw_L6: Double;
  pw_P1, pw_P2, pw_P3, pw_P4, pw_P5: Double;
  pw_lg2, pw_lg2_h, pw_lg2_l, pw_ovt: Double;
  pw_cp, pw_cp_h, pw_cp_l, pw_ivln2, pw_ivln2_h, pw_ivln2_l, pw_thrd: Double;

const
  npio2_hw: array[0..31] of LongInt = (
    $3FF921FB, $400921FB, $4012D97C, $401921FB, $401F6A7A, $4022D97C,
    $4025FDBB, $402921FB, $402C463A, $402F6A7A, $4031475C, $4032D97C,
    $40346B9C, $4035FDBB, $40378FDB, $403921FB, $403AB41B, $403C463A,
    $403DD85A, $403F6A7A, $40407E4C, $4041475C, $4042106C, $4042D97C,
    $4043A28C, $40446B9C, $404534AC, $4045FDBB, $4046C6CB, $40478FDB,
    $404858EB, $404921FB);

function FromBits(AQ: QWord): Double;
begin
  Move(AQ, Result, SizeOf(Result));
end;

{ GET_HIGH_WORD / GET_LOW_WORD / INSERT_WORDS }
function HighWord(AX: Double): LongInt;
var q: QWord;
begin
  Move(AX, q, SizeOf(q));
  Result := LongInt(LongWord(q shr 32));
end;

function LowWord(AX: Double): LongWord;
var q: QWord;
begin
  Move(AX, q, SizeOf(q));
  Result := LongWord(q and $FFFFFFFF);
end;

function FromWords(AHigh: LongInt; ALow: LongWord): Double;
var q: QWord;
begin
  q := (QWord(LongWord(AHigh)) shl 32) or ALow;
  Move(q, Result, SizeOf(Result));
end;

{ __ieee754_rem_pio2, the small and medium ranges: n, and the remainder in
  two pieces. False past the medium range. }
function RemPio2(AX: Double; out AN: Integer; out Y0, Y1: Double): Boolean;
var
  hx, ix, j, i, n: LongInt;
  z, t, r, w, fn: Double;
begin
  Result := True;
  hx := HighWord(AX);
  ix := hx and $7FFFFFFF;
  if ix <= $3FE921FB then
  begin
    AN := 0;
    Y0 := AX;
    Y1 := 0;
    Exit;
  end;
  if ix < $4002D97C then
  begin
    { |x| < 3pi/4: n is one either way }
    if hx > 0 then
    begin
      z := AX - pio2_1;
      if ix <> $3FF921FB then
      begin
        Y0 := z - pio2_1t;
        Y1 := (z - Y0) - pio2_1t;
      end
      else
      begin
        z := z - pio2_2;
        Y0 := z - pio2_2t;
        Y1 := (z - Y0) - pio2_2t;
      end;
      AN := 1;
    end
    else
    begin
      z := AX + pio2_1;
      if ix <> $3FF921FB then
      begin
        Y0 := z + pio2_1t;
        Y1 := (z - Y0) + pio2_1t;
      end
      else
      begin
        z := z + pio2_2;
        Y0 := z + pio2_2t;
        Y1 := (z - Y0) + pio2_2t;
      end;
      AN := -1;
    end;
    Exit;
  end;
  if ix <= $413921FB then
  begin
    t := Abs(AX);
    n := Trunc(t * invpio2 + 0.5);
    fn := n;
    r := t - fn * pio2_1;
    w := fn * pio2_1t;
    if (n < 32) and (ix <> npio2_hw[n - 1]) then
      Y0 := r - w
    else
    begin
      j := ix shr 20;
      Y0 := r - w;
      i := j - LongInt((LongWord(HighWord(Y0)) shr 20) and $7FF);
      if i > 16 then
      begin
        t := r;
        w := fn * pio2_2;
        r := t - w;
        w := fn * pio2_2t - ((t - r) - w);
        Y0 := r - w;
        i := j - LongInt((LongWord(HighWord(Y0)) shr 20) and $7FF);
        if i > 49 then
        begin
          t := r;
          w := fn * pio2_3;
          r := t - w;
          w := fn * pio2_3t - ((t - r) - w);
          Y0 := r - w;
        end;
      end;
    end;
    Y1 := (r - Y0) - w;
    if hx < 0 then
    begin
      Y0 := -Y0;
      Y1 := -Y1;
      AN := -n;
    end
    else
      AN := n;
    Exit;
  end;
  Result := False;
end;

{ __kernel_sin }
function KSin(AX, AY: Double; AIY: Integer): Double;
var ix: LongInt;
  z, v, r: Double;
begin
  ix := HighWord(AX) and $7FFFFFFF;
  if ix < $3E400000 then Exit(AX);
  z := AX * AX;
  v := z * AX;
  r := S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
  if AIY = 0 then
    Result := AX + v * (S1 + z * r)
  else
    Result := AX - ((z * (0.5 * AY - v * r) - AY) - v * S1);
end;

{ __kernel_cos }
function KCos(AX, AY: Double): Double;
var ix: LongInt;
  z, r, qx, hz, a: Double;
begin
  ix := HighWord(AX) and $7FFFFFFF;
  if ix < $3E400000 then Exit(1);
  z := AX * AX;
  r := z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
  if ix < $3FD33333 then
    Exit(1 - (0.5 * z - (z * r - AX * AY)));
  if ix > $3FE90000 then qx := 0.28125
  else qx := FromWords(ix - $00200000, 0);
  hz := 0.5 * z - qx;
  a := 1 - qx;
  Result := a - (hz - (z * r - AX * AY));
end;

{ V8's __kernel_tan: tan of x + y on [-pi/4, pi/4]; AIY 1 for tan, -1 for
  -1/tan. Line for line, the two careful -1/w reconstructions included. }
function KTan(AX, AY: Double; AIY: Integer): Double;
var
  z, r, v, w, s, a, t: Double;
  ix, hx: LongInt;
  low: LongWord;
begin
  hx := HighWord(AX);
  ix := hx and $7FFFFFFF;
  if ix < $3E300000 then
  begin
    { x < 2^-28 }
    low := LowWord(AX);
    if ((LongWord(ix) or low) or LongWord(AIY + 1)) = 0 then
      Exit(1 / Abs(AX));
    if AIY = 1 then Exit(AX);
    z := AX + AY;
    w := z;
    z := FromWords(HighWord(z), 0);
    v := AY - (z - AX);
    a := -1 / w;
    t := FromWords(HighWord(a), 0);
    s := 1 + t * z;
    Exit(t + a * (s + t * v));
  end;
  if ix >= $3FE59428 then
  begin
    { |x| >= 0.6744 }
    if hx < 0 then
    begin
      AX := -AX;
      AY := -AY;
    end;
    z := pi_o_4 - AX;
    w := atanlo[1] - AY;
    AX := z + w;
    AY := 0.0;
  end;
  z := AX * AX;
  w := z * z;
  r := TT[1] + w * (TT[3] + w * (TT[5] + w * (TT[7] + w * (TT[9] + w * TT[11]))));
  v := z * (TT[2] + w * (TT[4] + w * (TT[6] + w * (TT[8] + w * (TT[10] + w * TT[12])))));
  s := z * AX;
  r := AY + z * (s * (r + v) + AY);
  r := r + TT[0] * s;
  w := AX + r;
  if ix >= $3FE59428 then
  begin
    v := AIY;
    Exit((1 - (SarLongint(hx, 30) and 2)) * (v - 2.0 * (AX - (w * w / (w + v) - r))));
  end;
  if AIY = 1 then Exit(w);
  { -1/(x + r), accurately }
  z := FromWords(HighWord(w), 0);
  v := r - (z - AX);
  a := -1 / w;
  t := FromWords(HighWord(a), 0);
  s := 1 + t * z;
  Result := t + a * (s + t * v);
end;

function TyJsTan(AX: Double): Double;
var
  ix: LongInt;
  n: Integer;
  y0, y1: Double;
begin
  ix := HighWord(AX) and $7FFFFFFF;
  if ix <= $3FE921FB then Exit(KTan(AX, 0, 1));
  if ix >= $7FF00000 then Exit(NaN);
  if not RemPio2(AX, n, y0, y1) then Exit(Tan(AX));
  { 1 when n is even, -1 when it is odd }
  Result := KTan(y0, y1, 1 - ((n and 1) shl 1));
end;

function TyJsSin(AX: Double): Double;
var ix: LongInt;
  n: Integer;
  y0, y1: Double;
begin
  ix := HighWord(AX) and $7FFFFFFF;
  if ix <= $3FE921FB then Exit(KSin(AX, 0, 0));
  if ix >= $7FF00000 then Exit(NaN);
  if not RemPio2(AX, n, y0, y1) then Exit(Sin(AX));
  case n and 3 of
    0: Result := KSin(y0, y1, 1);
    1: Result := KCos(y0, y1);
    2: Result := -KSin(y0, y1, 1);
  else
    Result := -KCos(y0, y1);
  end;
end;

function TyJsCos(AX: Double): Double;
var ix: LongInt;
  n: Integer;
  y0, y1: Double;
begin
  ix := HighWord(AX) and $7FFFFFFF;
  if ix <= $3FE921FB then Exit(KCos(AX, 0));
  if ix >= $7FF00000 then Exit(NaN);
  if not RemPio2(AX, n, y0, y1) then Exit(Cos(AX));
  case n and 3 of
    0: Result := KCos(y0, y1);
    1: Result := -KSin(y0, y1, 1);
    2: Result := -KCos(y0, y1);
  else
    Result := KSin(y0, y1, 1);
  end;
end;

function TyJsAtan(AX: Double): Double;
var
  hx, ix: LongInt;
  id: Integer;
  z, w, s1_, s2_: Double;
begin
  hx := HighWord(AX);
  ix := hx and $7FFFFFFF;
  if ix >= $44100000 then
  begin
    { |x| >= 2^66, or not a number }
    if (ix > $7FF00000) or ((ix = $7FF00000) and (LowWord(AX) <> 0)) then
      Exit(NaN);
    if hx > 0 then Exit(atanhi[3] + atanlo[3]);
    Exit(-atanhi[3] - atanlo[3]);
  end;
  if ix < $3FDC0000 then
  begin
    { |x| < 0.4375 }
    if ix < $3E400000 then Exit(AX);
    id := -1;
  end
  else
  begin
    AX := Abs(AX);
    if ix < $3FF30000 then
    begin
      if ix < $3FE60000 then
      begin
        id := 0;
        AX := (2.0 * AX - 1) / (2.0 + AX);
      end
      else
      begin
        id := 1;
        AX := (AX - 1) / (AX + 1);
      end;
    end
    else if ix < $40038000 then
    begin
      id := 2;
      AX := (AX - 1.5) / (1 + 1.5 * AX);
    end
    else
    begin
      id := 3;
      AX := -1.0 / AX;
    end;
  end;
  z := AX * AX;
  w := z * z;
  s1_ := z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
  s2_ := w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
  if id < 0 then Exit(AX - AX * (s1_ + s2_));
  z := atanhi[id] - ((AX * (s1_ + s2_) - atanlo[id]) - AX);
  if hx < 0 then Result := -z else Result := z;
end;

function TyJsAcos(AX: Double): Double;
var
  hx, ix: LongInt;
  z, p, q, r, w, s, c, df, pi_, pio2Hi, pio2Lo: Double;

  function PQ(AZ: Double): Double;
  begin
    p := AZ * (FromBits(QWord($3FC5555555555555)) + AZ * (FromBits(QWord($BFD4D61203EB6F7D))
      + AZ * (FromBits(QWord($3FC9C1550E884455)) + AZ * (FromBits(QWord($BFA48228B5688F3B))
      + AZ * (FromBits(QWord($3F49EFE07501B288)) + AZ * FromBits(QWord($3F023DE10DFDF709)))))));
    q := 1.0 + AZ * (FromBits(QWord($C0033A271C8A2D4B)) + AZ * (FromBits(QWord($40002AE59C598AC8))
      + AZ * (FromBits(QWord($BFE6066C1B8D0159)) + AZ * FromBits(QWord($3FB3B8C5B12E9282)))));
    Result := p / q;
  end;

begin
  pi_ := FromBits(QWord($400921FB54442D18));
  pio2Hi := FromBits(QWord($3FF921FB54442D18));
  pio2Lo := FromBits(QWord($3C91A62633145C07));
  hx := HighWord(AX);
  ix := hx and $7FFFFFFF;
  if ix >= $3FF00000 then
  begin
    { |x| = 1 exactly, or past it: not a number }
    if ((ix - $3FF00000) or LongInt(LowWord(AX))) = 0 then
    begin
      if hx > 0 then Exit(0.0);
      Exit(pi_ + 2.0 * pio2Lo);
    end;
    Exit(NaN);
  end;
  if ix < $3FE00000 then
  begin
    { |x| < 0.5 }
    if ix <= $3C600000 then Exit(pio2Hi + pio2Lo);
    z := AX * AX;
    r := PQ(z);
    Exit(pio2Hi - (AX - (pio2Lo - AX * r)));
  end;
  if hx < 0 then
  begin
    z := (1.0 + AX) * 0.5;
    r := PQ(z);
    s := Sqrt(z);
    w := r * s - pio2Lo;
    Exit(pi_ - 2.0 * (s + w));
  end;
  z := (1.0 - AX) * 0.5;
  s := Sqrt(z);
  df := FromWords(HighWord(s), 0);
  c := (z - df * df) / (s + df);
  r := PQ(z);
  w := r * s + c;
  Result := 2.0 * (df + w);
end;

function TyJsAtan2(AY, AX: Double): Double;
var
  hx, ix, hy, iy, k: LongInt;
  lx, ly: LongWord;
  m: Integer;
  z: Double;
begin
  if IsNan(AX) or IsNan(AY) then Exit(NaN);
  hx := HighWord(AX);
  lx := LowWord(AX);
  ix := hx and $7FFFFFFF;
  hy := HighWord(AY);
  ly := LowWord(AY);
  iy := hy and $7FFFFFFF;
  { x = 1.0 }
  if (hx = $3FF00000) and (lx = 0) then Exit(TyJsAtan(AY));
  { 2 * sign(x) + sign(y) }
  m := 0;
  if hy < 0 then m := m or 1;
  if hx < 0 then m := m or 2;
  { y = 0 }
  if (iy = 0) and (ly = 0) then
    case m of
      0, 1: Exit(AY);
      2: Exit(pi_ + tiny);
    else
      Exit(-pi_ - tiny);
    end;
  { x = 0 }
  if (ix = 0) and (lx = 0) then
  begin
    if hy < 0 then Exit(-pi_o_2 - tiny) else Exit(pi_o_2 + tiny);
  end;
  { x infinite }
  if (ix = $7FF00000) and (lx = 0) then
  begin
    if (iy = $7FF00000) and (ly = 0) then
      case m of
        0: Exit(pi_o_4 + tiny);
        1: Exit(-pi_o_4 - tiny);
        2: Exit(3.0 * pi_o_4 + tiny);
      else
        Exit(-3.0 * pi_o_4 - tiny);
      end
    else
      case m of
        0: Exit(0.0);
        1: Exit(negZero);
        2: Exit(pi_ + tiny);
      else
        Exit(-pi_ - tiny);
      end;
  end;
  { y infinite }
  if (iy = $7FF00000) and (ly = 0) then
  begin
    if hy < 0 then Exit(-pi_o_2 - tiny) else Exit(pi_o_2 + tiny);
  end;
  k := SarLongint(iy - ix, 20);
  if k > 60 then
  begin
    { |y/x| > 2^60 }
    z := pi_o_2 + 0.5 * pi_lo;
    m := m and 1;
  end
  else if (hx < 0) and (k < -60) then
    { 0 > |y|/x > -2^-60 }
    z := 0.0
  else
    z := TyJsAtan(Abs(AY / AX));
  case m of
    0: Result := z;
    1: Result := -z;
    2: Result := pi_ - (z - pi_lo);
  else
    Result := (z - pi_lo) - pi_;
  end;
end;

function TyJsFround(AX: Double): Double;
const
  { the largest single, 2^128 - 2^104, plus half a unit of its last place:
    2^128 - 2^103, where the tie goes to the infinity }
  cOverflow: Double = 3.4028235677973366e38;
var s: Single;
begin
  if IsNan(AX) or IsInfinite(AX) then Exit(AX);
  { STATED, NOT LEFT TO THE CONVERSION, which raises on an overflow the
    run-time library has not masked }
  if AX >= cOverflow then Exit(Infinity);
  if AX <= -cOverflow then Exit(NegInfinity);
  s := AX;
  Result := s;
end;

{ ==================== __ieee754_log and __ieee754_pow ====================

  V8's Math.log is fdlibm's e_log.c as it stands; its Math.pow is e_pow.c
  with one line changed (ieee754.cc:2894), the correction taken inside the
  divisor. Transcribed from tools/advchart-oracle/fdlibm-powlog.js, which
  matched node on millions of arguments; tools/advchart-oracle/js-pow-log.js
  holds this to the same answers.

  WHERE C LETS THE HARDWARE MAKE AN INFINITY, A ZERO OR A NAN -- huge*huge,
  tiny*tiny, x/0, (x-x)/(x-x) -- the answer is written out: FPC raises on an
  overflow, a division by nought and an invalid operation that C's defaults
  let through. The results are the same values.

  SIGNED SHIFTS are SarLongint where the operand can be negative; everything
  else is a non-negative word and shr is the same. Integer arithmetic wraps
  as C's does, with range and overflow checks off. }

{$PUSH}{$R-}{$Q-}

function WithHigh(AX: Double; AHigh: LongInt): Double;
begin
  Result := FromWords(AHigh, LowWord(AX));
end;

function WithLow(AX: Double; ALow: LongWord): Double;
begin
  Result := FromWords(HighWord(AX), ALow);
end;

{ A PRODUCT OR QUOTIENT THAT MAY OVERFLOW, as C computes it: to the
  infinity, not to an exception. Only the two special cases that can --
  x * x for y = 2 and 1 / x for y = -1 -- come here. }
function MulOrDivQuiet(A, B: Double; ADivide: Boolean): Double;
var mask: TFPUExceptionMask;
begin
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exOverflow, exUnderflow, exPrecision]);
  try
    if ADivide then Result := A / B else Result := A * B;
  finally
    ClearExceptions(False);
    {$IFDEF CPUX86_64}
    SetMXCSR(GetMXCSR and not LongWord($3F));
    {$ENDIF}
    SetExceptionMask(mask);
  end;
end;

function SignedInf(ANeg: Boolean): Double;
begin
  if ANeg then Result := NegInfinity else Result := Infinity;
end;

function SignedZero(ANeg: Boolean): Double;
begin
  if ANeg then Result := negZero else Result := 0;
end;

function TyJsLog(AX: Double): Double;
var
  hfsq, f, s, z, R, w, t1, t2, dk, x: Double;
  k, hx, i, j: LongInt;
  lx: LongWord;
begin
  x := AX;
  hx := HighWord(x);
  lx := LowWord(x);
  k := 0;
  if hx < $00100000 then                         { x < 2**-1022 }
  begin
    if ((hx and $7FFFFFFF) or LongInt(lx)) = 0 then
      Exit(NegInfinity);                         { log(+-0) = -inf }
    if hx < 0 then Exit(NaN);                    { log(-#) = NaN }
    k := k - 54;
    x := x * lg_two54;                           { subnormal, scale up }
    hx := HighWord(x);
  end;
  if hx >= $7FF00000 then Exit(x + x);
  k := k + (hx shr 20) - 1023;
  hx := hx and $000FFFFF;
  i := (hx + $95F64) and $100000;
  x := WithHigh(x, hx or (i xor $3FF00000));    { normalize x or x/2 }
  k := k + (i shr 20);
  f := x - 1.0;
  if (($000FFFFF and (2 + hx)) < 3) then         { -2**-20 <= f < 2**-20 }
  begin
    if f = 0.0 then
    begin
      if k = 0 then Exit(0.0);
      dk := k;
      Exit(dk * lg_ln2_hi + dk * lg_ln2_lo);
    end;
    R := f * f * (0.5 - lg_third * f);
    if k = 0 then Exit(f - R);
    dk := k;
    Exit(dk * lg_ln2_hi - ((R - dk * lg_ln2_lo) - f));
  end;
  s := f / (2.0 + f);
  dk := k;
  z := s * s;
  i := hx - $6147A;
  w := z * z;
  j := $6B851 - hx;
  t1 := w * (Lg2 + w * (Lg4 + w * Lg6));
  t2 := z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)));
  i := i or j;
  R := t2 + t1;
  if i > 0 then
  begin
    hfsq := 0.5 * f * f;
    if k = 0 then Exit(f - (hfsq - s * (hfsq + R)));
    Exit(dk * lg_ln2_hi - ((hfsq - (s * (hfsq + R) + dk * lg_ln2_lo)) - f));
  end;
  if k = 0 then Exit(f - s * (f - R));
  Result := dk * lg_ln2_hi - ((s * (f - R) - dk * lg_ln2_lo) - f);
end;

{ s_scalbn.c, reached only for a result below the normal range }
function ScalbN(AX: Double; AN: LongInt): Double;
var
  k, hx: LongInt;
  lx: LongWord;
  x: Double;
begin
  x := AX;
  hx := HighWord(x);
  lx := LowWord(x);
  k := (hx and $7FF00000) shr 20;
  if k = 0 then
  begin
    if (LongInt(lx) or (hx and $7FFFFFFF)) = 0 then Exit(x);
    x := x * lg_two54;
    hx := HighWord(x);
    k := ((hx and $7FF00000) shr 20) - 54;
    if AN < -50000 then Exit(SignedZero(x < 0));
  end;
  if k = $7FF then Exit(x + x);
  k := k + AN;
  if k > $7FE then Exit(SignedInf(x < 0));
  if k > 0 then Exit(WithHigh(x, (hx and LongInt($800FFFFF)) or (k shl 20)));
  if k <= -54 then
  begin
    if AN > 50000 then Exit(SignedInf(x < 0));
    Exit(SignedZero(x < 0));
  end;
  k := k + 54;
  x := WithHigh(x, (hx and LongInt($800FFFFF)) or (k shl 20));
  Result := x * pw_twom54;
end;

function TyJsPow(AX, AY: Double): Double;
var
  z, absx, z_h, z_l, p_h, p_l, y1, t1, t2, r, s, t, u, v, w: Double;
  ss, s2, s_h, s_l, t_h, t_l: Double;
  i, j, k, yisint, n, hx, hy, ix, iy: LongInt;
  lx, ly, uj: LongWord;
  bpk, dphk, dplk: Double;
begin
  hx := HighWord(AX);
  lx := LowWord(AX);
  hy := HighWord(AY);
  ly := LowWord(AY);
  ix := hx and $7FFFFFFF;
  iy := hy and $7FFFFFFF;

  { y == zero: x**0 = 1 }
  if (iy or LongInt(ly)) = 0 then Exit(1.0);
  { +-NaN return x + y }
  if (ix > $7FF00000) or ((ix = $7FF00000) and (lx <> 0))
    or (iy > $7FF00000) or ((iy = $7FF00000) and (ly <> 0)) then
    Exit(AX + AY);

  { is y an odd integer when x < 0: 0 not an integer, 1 odd, 2 even }
  yisint := 0;
  if hx < 0 then
  begin
    if iy >= $43400000 then yisint := 2
    else if iy >= $3FF00000 then
    begin
      k := (iy shr 20) - $3FF;
      if k > 20 then
      begin
        uj := ly shr (52 - k);
        if LongWord(uj shl (52 - k)) = ly then yisint := 2 - LongInt(uj and 1);
      end
      else if ly = 0 then
      begin
        j := iy shr (20 - k);
        if (j shl (20 - k)) = iy then yisint := 2 - (j and 1);
      end;
    end;
  end;

  { special values of y }
  if ly = 0 then
  begin
    if iy = $7FF00000 then                       { y is +-inf }
    begin
      if ((ix - $3FF00000) or LongInt(lx)) = 0 then
        Exit(NaN)                                { (+-1)**+-inf is NaN }
      else if ix >= $3FF00000 then               { (|x|>1)**+-inf = inf, 0 }
      begin
        if hy >= 0 then Exit(AY) else Exit(0.0);
      end
      else                                       { (|x|<1)**-,+inf = inf, 0 }
      begin
        if hy < 0 then Exit(-AY) else Exit(0.0);
      end;
    end;
    if iy = $3FF00000 then                       { y is +-1 }
    begin
      if hy < 0 then
      begin
        if AX = 0 then Exit(SignedInf(hx < 0));
        Exit(MulOrDivQuiet(1.0, AX, True));
      end;
      Exit(AX);
    end;
    if hy = $40000000 then Exit(MulOrDivQuiet(AX, AX, False));   { y is 2 }
    if (hy = $3FE00000) and (hx >= 0) then       { y is 0.5, x >= +0 }
      Exit(Sqrt(AX));
  end;

  absx := Abs(AX);
  { special values of x }
  if lx = 0 then
    if (ix = $7FF00000) or (ix = 0) or (ix = $3FF00000) then
    begin
      z := absx;                                   { x is +-0, +-inf, +-1 }
      if hy < 0 then
      begin
        if z = 0 then z := Infinity else z := 1.0 / z;
      end;
      if hx < 0 then
      begin
        if ((ix - $3FF00000) or yisint) = 0 then
          z := NaN                               { (-1)**non-int is NaN }
        else if yisint = 1 then
          z := -z;                               { (x<0)**odd = -(|x|**odd) }
      end;
      Exit(z);
    end;

  n := LongInt(LongWord(hx) shr 31) - 1;        { 0 when x < 0, -1 otherwise }
  { (x<0)**(non-int) is NaN }
  if (n or yisint) = 0 then Exit(NaN);
  s := 1.0;
  if (n or (yisint - 1)) = 0 then s := -1.0;    { (-ve)**(odd int) }

  if iy > $41E00000 then                         { |y| > 2**31 }
  begin
    if iy > $43F00000 then                       { |y| > 2**64: must o/uflow }
    begin
      if ix <= $3FEFFFFF then
      begin
        if hy < 0 then Exit(Infinity) else Exit(0.0);
      end;
      if ix >= $3FF00000 then
      begin
        if hy > 0 then Exit(Infinity) else Exit(0.0);
      end;
    end;
    { over/underflow if x is not close to one }
    if ix < $3FEFFFFF then
    begin
      if hy < 0 then Exit(SignedInf(s < 0)) else Exit(SignedZero(s < 0));
    end;
    if ix > $3FF00000 then
    begin
      if hy > 0 then Exit(SignedInf(s < 0)) else Exit(SignedZero(s < 0));
    end;
    { |1 - x| is tiny <= 2**-20: log(x) by x - x^2/2 + x^3/3 - x^4/4 }
    t := absx - 1.0;
    w := (t * t) * (0.5 - t * (pw_thrd - t * 0.25));
    u := pw_ivln2_h * t;
    v := t * pw_ivln2_l - w * pw_ivln2;
    t1 := u + v;
    t1 := WithLow(t1, 0);
    t2 := v - (t1 - u);
  end
  else
  begin
    n := 0;
    { take care of a subnormal }
    if ix < $00100000 then
    begin
      absx := absx * pw_two53;
      n := n - 53;
      ix := HighWord(absx);
    end;
    n := n + (ix shr 20) - $3FF;
    j := ix and $000FFFFF;
    { determine the interval }
    ix := j or $3FF00000;
    if j <= $3988E then k := 0                   { |x| < sqrt(3/2) }
    else if j < $BB67A then k := 1               { |x| < sqrt(3) }
    else
    begin
      k := 0;
      n := n + 1;
      ix := ix - $00100000;
    end;
    absx := WithHigh(absx, ix);
    if k = 0 then
    begin
      bpk := 1.0;
      dphk := 0.0;
      dplk := 0.0;
    end
    else
    begin
      bpk := 1.5;
      dphk := pw_dp_h1;
      dplk := pw_dp_l1;
    end;

    { ss = s_h + s_l = (x-1)/(x+1) or (x-1.5)/(x+1.5) }
    u := absx - bpk;
    v := 1.0 / (absx + bpk);
    ss := u * v;
    s_h := ss;
    s_h := WithLow(s_h, 0);
    { t_h = absx + bp[k], high }
    t_h := 0.0;
    t_h := WithHigh(t_h, ((ix shr 1) or $20000000) + $00080000 + (k shl 18));
    t_l := absx - (t_h - bpk);
    s_l := v * ((u - s_h * t_h) - s_h * t_l);
    { log(absx) }
    s2 := ss * ss;
    r := s2 * s2 * (pw_L1 + s2 * (pw_L2 + s2 * (pw_L3 + s2 * (pw_L4
      + s2 * (pw_L5 + s2 * pw_L6)))));
    r := r + s_l * (s_h + ss);
    s2 := s_h * s_h;
    t_h := 3.0 + s2 + r;
    t_h := WithLow(t_h, 0);
    t_l := r - ((t_h - 3.0) - s2);
    { u + v = ss * (1 + ...) }
    u := s_h * t_h;
    v := s_l * t_h + t_l * ss;
    { 2/(3 log2) * (ss + ...) }
    p_h := u + v;
    p_h := WithLow(p_h, 0);
    p_l := v - (p_h - u);
    z_h := pw_cp_h * p_h;
    z_l := pw_cp_l * p_h + p_l * pw_cp + dplk;
    { log2(absx) = (ss + ..) * 2/(3 log2) = n + dp_h + z_h + z_l }
    t := n;
    t1 := ((z_h + z_l) + dphk) + t;
    t1 := WithLow(t1, 0);
    t2 := z_l - (((t1 - t) - dphk) - z_h);
  end;

  { split y into y1 + y2 and compute (y1 + y2) * (t1 + t2) }
  y1 := AY;
  y1 := WithLow(y1, 0);
  p_l := (AY - y1) * t1 + AY * t2;
  p_h := y1 * t1;
  z := p_l + p_h;
  j := HighWord(z);
  i := LongInt(LowWord(z));
  if j >= $40900000 then                         { z >= 1024 }
  begin
    if ((j - $40900000) or i) <> 0 then
      Exit(SignedInf(s < 0))                     { overflow }
    else if p_l + pw_ovt > z - p_h then
      Exit(SignedInf(s < 0));
  end
  else if (j and $7FFFFFFF) >= $4090CC00 then    { z <= -1075 }
  begin
    if ((j - LongInt($C090CC00)) or i) <> 0 then
      Exit(SignedZero(s < 0))                    { underflow }
    else if p_l <= z - p_h then
      Exit(SignedZero(s < 0));
  end;
  { 2**(p_h + p_l) }
  i := j and $7FFFFFFF;
  k := (i shr 20) - $3FF;
  n := 0;
  if i > $3FE00000 then                          { |z| > 0.5: n = [z + 0.5] }
  begin
    n := j + ($00100000 shr (k + 1));
    k := ((n and $7FFFFFFF) shr 20) - $3FF;
    t := 0.0;
    t := WithHigh(t, n and not ($000FFFFF shr k));
    n := ((n and $000FFFFF) or $00100000) shr (20 - k);
    if j < 0 then n := -n;
    p_h := p_h - t;
  end;
  t := p_l + p_h;
  t := WithLow(t, 0);
  u := t * pw_lg2_h;
  v := (p_l - (t - p_h)) * pw_lg2 + t * pw_lg2_l;
  z := u + v;
  w := v - (z - u);
  t := z * z;
  t1 := z - t * (pw_P1 + t * (pw_P2 + t * (pw_P3 + t * (pw_P4 + t * pw_P5))));
  { V8's line, not fdlibm's: the correction inside the divisor }
  r := (z * t1) / ((t1 - 2.0) - (w + z * w));
  z := 1.0 - (r - z);
  j := HighWord(z);
  j := j + (n shl 20);
  if SarLongint(j, 20) <= 0 then
    z := ScalbN(z, n)                            { subnormal output }
  else
    z := WithHigh(z, j);
  Result := s * z;
end;

{$POP}

initialization
  invpio2 := FromBits(QWord($3FE45F306DC9C883));
  pio2_1 := FromBits(QWord($3FF921FB54400000));
  pio2_1t := FromBits(QWord($3DD0B4611A626331));
  pio2_2 := FromBits(QWord($3DD0B4611A600000));
  pio2_2t := FromBits(QWord($3BA3198A2E037073));
  pio2_3 := FromBits(QWord($3BA3198A2E000000));
  pio2_3t := FromBits(QWord($397B839A252049C1));
  S1 := FromBits(QWord($BFC5555555555549));
  S2 := FromBits(QWord($3F8111111110F8A6));
  S3 := FromBits(QWord($BF2A01A019C161D5));
  S4 := FromBits(QWord($3EC71DE357B1FE7D));
  S5 := FromBits(QWord($BE5AE5E68A2B9CEB));
  S6 := FromBits(QWord($3DE5D93A5ACFD57C));
  C1 := FromBits(QWord($3FA555555555554C));
  C2 := FromBits(QWord($BF56C16C16C15177));
  C3 := FromBits(QWord($3EFA01A019CB1590));
  C4 := FromBits(QWord($BE927E4F809C52AD));
  C5 := FromBits(QWord($3E21EE9EBDB4B1C4));
  C6 := FromBits(QWord($BDA8FAE9BE8838D4));
  TT[0] := FromBits(QWord($3FD5555555555563));
  TT[1] := FromBits(QWord($3FC111111110FE7A));
  TT[2] := FromBits(QWord($3FABA1BA1BB341FE));
  TT[3] := FromBits(QWord($3F9664F48406D637));
  TT[4] := FromBits(QWord($3F8226E3E96E8493));
  TT[5] := FromBits(QWord($3F6D6D22C9560328));
  TT[6] := FromBits(QWord($3F57DBC8FEE08315));
  TT[7] := FromBits(QWord($3F4344D8F2F26501));
  TT[8] := FromBits(QWord($3F3026F71A8D1068));
  TT[9] := FromBits(QWord($3F147E88A03792A6));
  TT[10] := FromBits(QWord($3F12B80F32F0A7E9));
  TT[11] := FromBits(QWord($BEF375CBDB605373));
  TT[12] := FromBits(QWord($3EFB2A7074BF7AD4));
  atanhi[0] := FromBits(QWord($3FDDAC670561BB4F));
  atanhi[1] := FromBits(QWord($3FE921FB54442D18));
  atanhi[2] := FromBits(QWord($3FEF730BD281F69B));
  atanhi[3] := FromBits(QWord($3FF921FB54442D18));
  atanlo[0] := FromBits(QWord($3C7A2B7F222F65E2));
  atanlo[1] := FromBits(QWord($3C81A62633145C07));
  atanlo[2] := FromBits(QWord($3C7007887AF0CBBD));
  atanlo[3] := FromBits(QWord($3C91A62633145C07));
  aT[0] := FromBits(QWord($3FD555555555550D));
  aT[1] := FromBits(QWord($BFC999999998EBC4));
  aT[2] := FromBits(QWord($3FC24924920083FF));
  aT[3] := FromBits(QWord($BFBC71C6FE231671));
  aT[4] := FromBits(QWord($3FB745CDC54C206E));
  aT[5] := FromBits(QWord($BFB3B0F2AF749A6D));
  aT[6] := FromBits(QWord($3FB10D66A0D03D51));
  aT[7] := FromBits(QWord($BFADDE2D52DEFD9A));
  aT[8] := FromBits(QWord($3FA97B4B24760DEB));
  aT[9] := FromBits(QWord($BFA2B4442C6A6C2F));
  aT[10] := FromBits(QWord($3F90AD3AE322DA11));
  pi_o_4 := FromBits(QWord($3FE921FB54442D18));
  pi_o_2 := FromBits(QWord($3FF921FB54442D18));
  pi_ := FromBits(QWord($400921FB54442D18));
  pi_lo := FromBits(QWord($3CA1A62633145C07));
  tiny := FromBits(QWord($01A56E1FC2F8F359));
  negZero := FromBits(QWord($8000000000000000));
  lg_ln2_hi := FromBits(QWord($3FE62E42FEE00000));
  lg_ln2_lo := FromBits(QWord($3DEA39EF35793C76));
  lg_two54 := FromBits(QWord($4350000000000000));
  lg_third := FromBits(QWord($3FD5555555555555));
  Lg1 := FromBits(QWord($3FE5555555555593));
  Lg2 := FromBits(QWord($3FD999999997FA04));
  Lg3 := FromBits(QWord($3FD2492494229359));
  Lg4 := FromBits(QWord($3FCC71C51D8E78AF));
  Lg5 := FromBits(QWord($3FC7466496CB03DE));
  Lg6 := FromBits(QWord($3FC39A09D078C69F));
  Lg7 := FromBits(QWord($3FC2F112DF3E5244));
  pw_dp_h1 := FromBits(QWord($3FE2B80340000000));
  pw_dp_l1 := FromBits(QWord($3E4CFDEB43CFD006));
  pw_two53 := FromBits(QWord($4340000000000000));
  pw_twom54 := FromBits(QWord($3C90000000000000));
  pw_L1 := FromBits(QWord($3FE3333333333303));
  pw_L2 := FromBits(QWord($3FDB6DB6DB6FABFF));
  pw_L3 := FromBits(QWord($3FD55555518F264D));
  pw_L4 := FromBits(QWord($3FD17460A91D4101));
  pw_L5 := FromBits(QWord($3FCD864A93C9DB65));
  pw_L6 := FromBits(QWord($3FCA7E284A454EEF));
  pw_P1 := FromBits(QWord($3FC555555555553E));
  pw_P2 := FromBits(QWord($BF66C16C16BEBD93));
  pw_P3 := FromBits(QWord($3F11566AAF25DE2C));
  pw_P4 := FromBits(QWord($BEBBBD41C5D26BF1));
  pw_P5 := FromBits(QWord($3E66376972BEA4D0));
  pw_lg2 := FromBits(QWord($3FE62E42FEFA39EF));
  pw_lg2_h := FromBits(QWord($3FE62E4300000000));
  pw_lg2_l := FromBits(QWord($BE205C610CA86C39));
  pw_ovt := FromBits(QWord($3C971547652B82FE));
  pw_cp := FromBits(QWord($3FEEC709DC3A03FD));
  pw_cp_h := FromBits(QWord($3FEEC709E0000000));
  pw_cp_l := FromBits(QWord($BE3E2FE0145B01F5));
  pw_ivln2 := FromBits(QWord($3FF71547652B82FE));
  pw_ivln2_h := FromBits(QWord($3FF7154760000000));
  pw_ivln2_l := FromBits(QWord($3E54AE0BF85DDF44));
  pw_thrd := FromBits(QWord($3FD5555555555555));
end.
