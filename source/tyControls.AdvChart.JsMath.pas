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

implementation

uses Math;

var
  invpio2, pio2_1, pio2_1t, pio2_2, pio2_2t, pio2_3, pio2_3t: Double;
  S1, S2, S3, S4, S5, S6: Double;
  C1, C2, C3, C4, C5, C6: Double;
  atanhi, atanlo: array[0..3] of Double;
  aT: array[0..10] of Double;
  pi_o_4, pi_o_2, pi_, pi_lo, tiny: Double;
  { a literal -0.0 may be folded to +0.0 }
  negZero: Double;

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
end.
