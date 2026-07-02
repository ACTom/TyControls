unit tyControls.ColorMath;
{$mode objfpc}{$H+}
interface
uses SysUtils, Types, Graphics, tyControls.Types;

procedure TyRGBToHSV(AColor: TTyColor; out H, S, V: Single);
function  TyHSVToRGB(H, S, V: Single; AAlpha: Byte = 255): TTyColor;
procedure TyRGBToCMYK(AColor: TTyColor; out C, M, Y, K: Single);
function  TyCMYKToRGB(C, M, Y, K: Single; AAlpha: Byte = 255): TTyColor;
function  TyColorToHex(AColor: TTyColor; AIncludeAlpha: Boolean = True): string;
function  TyColorFromLCL(AColor: TColor; AAlpha: Byte = 255): TTyColor;
function  TyHSVAreaToSV(const APoint: TPoint; const ARect: TRect): TPointF;
function  TyHueBarToH(AY: Integer; const ARect: TRect): Single;

implementation
uses Math;

function ClampF(X, Lo, Hi: Single): Single;
begin
  if X < Lo then Result := Lo
  else if X > Hi then Result := Hi
  else Result := X;
end;

procedure TyRGBToHSV(AColor: TTyColor; out H, S, V: Single);
var
  r, g, b, mx, mn, d: Single;
begin
  r := TyRedOf(AColor) / 255;
  g := TyGreenOf(AColor) / 255;
  b := TyBlueOf(AColor) / 255;
  mx := Max(r, Max(g, b));
  mn := Min(r, Min(g, b));
  d := mx - mn;
  V := mx;
  if mx = 0 then
    S := 0
  else
    S := d / mx;
  if d = 0 then
    H := 0
  else begin
    if mx = r then
      H := 60 * ((g - b) / d)
    else if mx = g then
      H := 60 * (((b - r) / d) + 2)
    else
      H := 60 * (((r - g) / d) + 4);
    if H < 0 then
      H := H + 360;
  end;
end;

function TyHSVToRGB(H, S, V: Single; AAlpha: Byte): TTyColor;
var
  c, x, m, r1, g1, b1, hp: Single;
  seg: Integer;
begin
  H := H - Floor(H / 360) * 360;          // normalize to [0,360)
  S := ClampF(S, 0, 1);
  V := ClampF(V, 0, 1);
  c := V * S;
  hp := H / 60;
  hp := hp - 2 * Floor(hp / 2);           // hp = (H/60) mod 2, in [0,2)
  x := c * (1 - Abs(hp - 1));
  m := V - c;
  seg := Trunc(H / 60) mod 6;
  case seg of
    0: begin r1 := c; g1 := x; b1 := 0; end;
    1: begin r1 := x; g1 := c; b1 := 0; end;
    2: begin r1 := 0; g1 := c; b1 := x; end;
    3: begin r1 := 0; g1 := x; b1 := c; end;
    4: begin r1 := x; g1 := 0; b1 := c; end;
  else
    begin r1 := c; g1 := 0; b1 := x; end;
  end;
  Result := TyRGBA(Round((r1 + m) * 255), Round((g1 + m) * 255), Round((b1 + m) * 255), AAlpha);
end;

procedure TyRGBToCMYK(AColor: TTyColor; out C, M, Y, K: Single);
var
  r, g, b: Single;
begin
  r := TyRedOf(AColor) / 255;
  g := TyGreenOf(AColor) / 255;
  b := TyBlueOf(AColor) / 255;
  K := 1 - Max(r, Max(g, b));
  if K >= 1 then begin
    C := 0; M := 0; Y := 0;
  end else begin
    C := (1 - r - K) / (1 - K);
    M := (1 - g - K) / (1 - K);
    Y := (1 - b - K) / (1 - K);
  end;
end;

function TyCMYKToRGB(C, M, Y, K: Single; AAlpha: Byte): TTyColor;
var
  kk: Single;
begin
  kk := ClampF(K, 0, 1);
  Result := TyRGBA(
    Round(255 * (1 - ClampF(C, 0, 1)) * (1 - kk)),
    Round(255 * (1 - ClampF(M, 0, 1)) * (1 - kk)),
    Round(255 * (1 - ClampF(Y, 0, 1)) * (1 - kk)),
    AAlpha);
end;

function TyColorToHex(AColor: TTyColor; AIncludeAlpha: Boolean): string;
begin
  // RGBA order (alpha LAST) to match TyParseColor
  if AIncludeAlpha then
    Result := Format('#%.2x%.2x%.2x%.2x',
      [TyRedOf(AColor), TyGreenOf(AColor), TyBlueOf(AColor), TyAlphaOf(AColor)])
  else
    Result := Format('#%.2x%.2x%.2x',
      [TyRedOf(AColor), TyGreenOf(AColor), TyBlueOf(AColor)]);
end;

function TyColorFromLCL(AColor: TColor; AAlpha: Byte): TTyColor;
var
  r, g, b: Byte;
begin
  RedGreenBlue(ColorToRGB(AColor), r, g, b);   // ColorToRGB resolves system colors
  Result := TyRGBA(r, g, b, AAlpha);
end;

function TyHSVAreaToSV(const APoint: TPoint; const ARect: TRect): TPointF;
var
  w, h: Integer;
begin
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if w <= 0 then Result.X := 0
  else Result.X := ClampF((APoint.X - ARect.Left) / w, 0, 1);
  if h <= 0 then Result.Y := 0
  else Result.Y := ClampF(1 - (APoint.Y - ARect.Top) / h, 0, 1);
end;

function TyHueBarToH(AY: Integer; const ARect: TRect): Single;
var
  h: Integer;
begin
  h := ARect.Bottom - ARect.Top;
  if h <= 0 then Result := 0
  else Result := ClampF((AY - ARect.Top) / h, 0, 1) * 360;
end;

end.
