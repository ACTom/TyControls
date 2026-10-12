unit tyControls.AdvChart.HeatLayer;
{$mode objfpc}{$H+}
{ THE HEATMAP LAYER [Batch 152, D14 GE4] -- a heatmap on a geo, upstream's
  chart/heatmap/HeatmapLayer.ts and HeatmapView._renderOnGeo.

  UPSTREAM draws on a canvas: a circle of pointSize, shadow-blurred by
  blurSize into a brush image of (pointSize + blurSize) * 2 a side; the brush
  drawn at every point with the point's alpha (the visualMap's normalizer of
  its value); then every pixel's alpha coloured through a 256-step gradient
  of the visualMap's colours -- the in-range one where isInRange says so
  (asked with the PIXEL's alpha, a quirk kept), the out-of-range one
  elsewhere -- its alpha mapped into [minOpacity, maxOpacity].

  THE BRUSH IS NO CANVAS'S HERE. A canvas' shadowBlur is the browser's own
  approximation of a Gaussian; the port draws the SVG specification's: three
  box blurs of d = floor(sigma * 3 * sqrt(2 pi) / 4 + 0.5), sigma blurSize / 2
  (an even d: two of d, one either side of the pixel, and one of d + 1),
  along x then along y, in integers, each sum rounded to a byte. The point is
  drawn source-over at Math.round of its corner. tools/advchart-oracle/
  geo-series.js answers upstream's getImageData with the very same raster,
  so the colouring -- upstream's code on those bytes -- is compared byte for
  byte.

  PURE: no painter, no LCL. }
interface

uses
  SysUtils, Math, tyControls.AdvChart.VisualMap;

type
  { one point: its place on the layer's canvas (the view rect's corner its
    origin) and its alpha, the normalizer's answer }
  TTyHeatPoint = record
    X, Y, Alpha: Double;
  end;
  TTyHeatPointArray = array of TTyHeatPoint;

  { _getGradient: 256 colours, four bytes each (the alpha byte the colour's
    0..1 alpha through a Uint8ClampedArray: 0 or 1) }
  TTyHeatGradient = array[0..1023] of Byte;

  { isInRange: a continuous visualMap's range over its extent, or a
    piecewise one's pieces (each piece's interval over the extent, whether
    it is selected), asked with a pixel's alpha -- the piecewise one keeps
    the piece it last found, as upstream's closure does }
  TTyHeatRange = record
    Piecewise: Boolean;
    R0, R1: Double;
    Lo, Hi: array of Double;
    Selected: array of Boolean;
    LastIndex: Integer;
  end;

  TTyHeatLayer = record
    Valid: Boolean;
    { the image's rect, chart px }
    X, Y, W, H: Double;
    { the canvas, whole pixels (the canvas width attribute's truncation) }
    PixW, PixH: Integer;
    { the coloured RGBA bytes, PixW * PixH * 4, not premultiplied }
    Bytes: TBytes;
    { the brush's corner of every drawImage, and its alpha (as upstream
      hands them: x - r, y - r, the normalizer's answer) }
    DrawX, DrawY, DrawAlpha: array of Double;
  end;

{ the gradient of a colour list (fastLerp at i / 255, fastMode); an empty
  list leaves every colour [0, 0, 0, 0] }
function TyHeatGradientOf(const AColors: TTyVisualColorArray): TTyHeatGradient;
{ getIsInContinuousRange / getIsInPiecewiseRange }
function TyHeatContinuousRange(AE0, AE1, AR0, AR1: Double): TTyHeatRange;
function TyHeatPiecewiseRange(AE0, AE1: Double; const ALo, AHi: array of Double;
  const ASelected: array of Boolean): TTyHeatRange;
function TyHeatInRange(var ARange: TTyHeatRange; AValue: Double): Boolean;
{ the reference brush: (pointSize + blurSize) * 2 a side, each pixel's alpha
  a byte over 255 }
function TyHeatBrush(APointSize, ABlurSize: Double; out ASide: Integer): TBytes;
{ HeatmapLayer.update: the brush at every point, then the colouring }
function TyHeatRender(const APoints: TTyHeatPointArray; AW, AH: Integer;
  APointSize, ABlurSize, AMinOpacity, AMaxOpacity: Double;
  const AGradIn, AGradOut: TTyHeatGradient; var ARange: TTyHeatRange): TBytes;
{ Uint8ClampedArray's ToUint8Clamp: NaN 0, the ends clamped, a tie to even }
function TyHeatClampByte(AValue: Double): Byte;

implementation

uses tyControls.AdvChart.Scale;

const
  cHeatPi: Double = 3.141592653589793;

function TyHeatClampByte(AValue: Double): Byte;
var f: Double;
begin
  if IsNan(AValue) or (AValue <= 0) then Exit(0);
  if AValue >= 255 then Exit(255);
  f := Floor(AValue);
  if f + 0.5 < AValue then Exit(Byte(Trunc(f) + 1));
  if AValue < f + 0.5 then Exit(Byte(Trunc(f)));
  { a tie: the even one }
  if Odd(Trunc(f)) then Result := Byte(Trunc(f) + 1) else Result := Byte(Trunc(f));
end;

function TyHeatGradientOf(const AColors: TTyVisualColorArray): TTyHeatGradient;
var
  i, off: Integer;
  c: TTyVisualColor;
  r, g, b, a: Double;
begin
  r := 0;
  g := 0;
  b := 0;
  a := 0;
  off := 0;
  for i := 0 to 255 do
  begin
    { fastLerp writes the colour reused from call to call; an empty list
      leaves it as it was }
    if Length(AColors) > 0 then
    begin
      c := TyVisualFastLerp(i / 255, AColors);
      if c.Defined then
      begin
        r := c.R;
        g := c.G;
        b := c.B;
        a := c.A;
      end;
    end;
    Result[off] := TyHeatClampByte(r);
    Result[off + 1] := TyHeatClampByte(g);
    Result[off + 2] := TyHeatClampByte(b);
    Result[off + 3] := TyHeatClampByte(a);
    Inc(off, 4);
  end;
end;

function TyHeatContinuousRange(AE0, AE1, AR0, AR1: Double): TTyHeatRange;
var span: Double;
begin
  Result := Default(TTyHeatRange);
  span := AE1 - AE0;
  Result.R0 := (AR0 - AE0) / span;
  Result.R1 := (AR1 - AE0) / span;
end;

function TyHeatPiecewiseRange(AE0, AE1: Double; const ALo, AHi: array of Double;
  const ASelected: array of Boolean): TTyHeatRange;
var span: Double; i: Integer;
begin
  Result := Default(TTyHeatRange);
  Result.Piecewise := True;
  span := AE1 - AE0;
  SetLength(Result.Lo, Length(ALo));
  SetLength(Result.Hi, Length(ALo));
  SetLength(Result.Selected, Length(ALo));
  for i := 0 to High(ALo) do
  begin
    Result.Lo[i] := (ALo[i] - AE0) / span;
    Result.Hi[i] := (AHi[i] - AE0) / span;
    Result.Selected[i] := (i <= High(ASelected)) and ASelected[i];
  end;
  Result.LastIndex := 0;
end;

function TyHeatInRange(var ARange: TTyHeatRange; AValue: Double): Boolean;
var i, n: Integer;
begin
  if not ARange.Piecewise then
    Exit((AValue >= ARange.R0) and (AValue <= ARange.R1));
  n := Length(ARange.Lo);
  { from the piece last found, then back }
  i := ARange.LastIndex;
  while i < n do
  begin
    if (ARange.Lo[i] <= AValue) and (AValue <= ARange.Hi[i]) then
    begin
      ARange.LastIndex := i;
      Break;
    end;
    Inc(i);
  end;
  if i = n then
  begin
    i := ARange.LastIndex - 1;
    while i >= 0 do
    begin
      if (ARange.Lo[i] <= AValue) and (AValue <= ARange.Hi[i]) then
      begin
        ARange.LastIndex := i;
        Break;
      end;
      Dec(i);
    end;
  end;
  Result := (i >= 0) and (i < n) and ARange.Selected[i];
end;

procedure BoxPass(const ASrc: array of Integer; var ADst: array of Integer;
  AW, AH, ASize, AOff: Integer; AVertical: Boolean);
var i, j, k, ii, sum, half: Integer;
begin
  half := ASize div 2;
  for j := 0 to AH - 1 do
    for i := 0 to AW - 1 do
    begin
      sum := 0;
      for k := 0 to ASize - 1 do
        if AVertical then
        begin
          ii := j - AOff + k;
          if (ii >= 0) and (ii < AH) then Inc(sum, ASrc[ii * AW + i]);
        end
        else
        begin
          ii := i - AOff + k;
          if (ii >= 0) and (ii < AW) then Inc(sum, ASrc[j * AW + ii]);
        end;
      ADst[j * AW + i] := (sum + half) div ASize;
    end;
end;

function TyHeatBrush(APointSize, ABlurSize: Double; out ASide: Integer): TBytes;
var
  r, sigma, dx, dy: Double;
  i, j, d, p: Integer;
  a, b: array of Integer;
  sizes, offs: array[0..2] of Integer;
begin
  Result := nil;
  r := APointSize + ABlurSize;
  ASide := Trunc(r * 2);
  if ASide <= 0 then Exit;
  SetLength(a, ASide * ASide);
  SetLength(b, ASide * ASide);
  { the disc, its centre where the shadow falls: (r, r) }
  for j := 0 to ASide - 1 do
    for i := 0 to ASide - 1 do
    begin
      dx := i + 0.5 - r;
      dy := j + 0.5 - r;
      if dx * dx + dy * dy <= APointSize * APointSize then a[j * ASide + i] := 255
      else a[j * ASide + i] := 0;
    end;
  sigma := ABlurSize / 2;
  d := 0;
  if sigma > 0 then d := Floor(sigma * 3 * Sqrt(2 * cHeatPi) / 4 + 0.5);
  if d >= 1 then
  begin
    if Odd(d) then
      for p := 0 to 2 do
      begin
        sizes[p] := d;
        offs[p] := (d - 1) div 2;
      end
    else
    begin
      sizes[0] := d;
      offs[0] := d div 2;
      sizes[1] := d;
      offs[1] := d div 2 - 1;
      sizes[2] := d + 1;
      offs[2] := d div 2;
    end;
    for p := 0 to 2 do
    begin
      BoxPass(a, b, ASide, ASide, sizes[p], offs[p], False);
      a := Copy(b);
    end;
    for p := 0 to 2 do
    begin
      BoxPass(a, b, ASide, ASide, sizes[p], offs[p], True);
      a := Copy(b);
    end;
  end;
  SetLength(Result, ASide * ASide);
  for i := 0 to High(Result) do Result[i] := Byte(a[i]);
end;

function TyHeatRender(const APoints: TTyHeatPointArray; AW, AH: Integer;
  APointSize, ABlurSize, AMinOpacity, AMaxOpacity: Double;
  const AGradIn, AGradOut: TTyHeatGradient; var ARange: TTyHeatRange): TBytes;
var
  brush: TBytes;
  side, k, i, j, tx, ty, ox, oy, off, g: Integer;
  acc: array of Double;
  r, s, ga, alpha, diff: Double;
  mask: TFPUExceptionMask;
begin
  Result := nil;
  if (AW <= 0) or (AH <= 0) then Exit;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    brush := TyHeatBrush(APointSize, ABlurSize, side);
    r := APointSize + ABlurSize;
    SetLength(acc, AW * AH);
    for k := 0 to High(acc) do acc[k] := 0;
    { the brush at every point, source-over, its alpha the point's }
    for k := 0 to High(APoints) do
    begin
      if IsNan(APoints[k].X) or IsNan(APoints[k].Y) then Continue;
      ga := APoints[k].Alpha;
      ox := Trunc(TyJsRound(APoints[k].X - r));
      oy := Trunc(TyJsRound(APoints[k].Y - r));
      for j := 0 to side - 1 do
      begin
        ty := oy + j;
        if (ty < 0) or (ty >= AH) then Continue;
        for i := 0 to side - 1 do
        begin
          tx := ox + i;
          if (tx < 0) or (tx >= AW) then Continue;
          s := (brush[j * side + i] / 255) * ga;
          acc[ty * AW + tx] := s + acc[ty * AW + tx] * (1 - s);
        end;
      end;
    end;
    { getImageData, then the colouring }
    SetLength(Result, AW * AH * 4);
    diff := AMaxOpacity - AMinOpacity;
    off := 0;
    for k := 0 to AW * AH - 1 do
    begin
      Result[off + 3] := Floor(acc[k] * 255 + 0.5);
      alpha := Result[off + 3] / 256;
      g := Floor(alpha * (256 - 1)) * 4;
      if alpha > 0 then
      begin
        alpha := alpha * diff + AMinOpacity;
        if TyHeatInRange(ARange, Result[off + 3] / 256) then
        begin
          Result[off] := AGradIn[g];
          Result[off + 1] := AGradIn[g + 1];
          Result[off + 2] := AGradIn[g + 2];
          Result[off + 3] := TyHeatClampByte(AGradIn[g + 3] * alpha * 256);
        end
        else
        begin
          Result[off] := AGradOut[g];
          Result[off + 1] := AGradOut[g + 1];
          Result[off + 2] := AGradOut[g + 2];
          Result[off + 3] := TyHeatClampByte(AGradOut[g + 3] * alpha * 256);
        end;
      end;
      Inc(off, 4);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

end.
