unit tyControls.Css.Values;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.Types;

function TyParseColor(const S: string): TTyColor;        // #rgb #rrggbb #rrggbbaa
function TyLighten(c: TTyColor; Pct: Single): TTyColor;  // Pct 0..100
function TyDarken(c: TTyColor; Pct: Single): TTyColor;   // Pct 0..100
function TyAlpha(c: TTyColor; A: Single): TTyColor;       // A 0..1
function TyMix(c1, c2: TTyColor; Pct: Single): TTyColor;  // Pct 0..100 of c2

implementation

// Clamp a real channel value into the 0..255 Byte range.
function ClampByte(V: Single): Byte;
var I: Integer;
begin
  I := Round(V);
  if I < 0 then I := 0;
  if I > 255 then I := 255;
  Result := Byte(I);
end;

// Parse one hex digit; raises ETyCssError-equivalent by returning via Valid flag.
function HexDigit(Ch: Char; out OK: Boolean): Integer;
begin
  OK := True;
  case Ch of
    '0'..'9': Result := Ord(Ch) - Ord('0');
    'a'..'f': Result := Ord(Ch) - Ord('a') + 10;
    'A'..'F': Result := Ord(Ch) - Ord('A') + 10;
  else
    Result := 0; OK := False;
  end;
end;

function HexByte(Hi, Lo: Char; out OK: Boolean): Integer;
var ho, lo2: Boolean;
begin
  Result := HexDigit(Hi, ho) * 16 + HexDigit(Lo, lo2);
  OK := ho and lo2;
end;

function TyParseColor(const S: string): TTyColor;
var
  T: string;
  R, G, B, A, n: Integer;
  ok1, ok2, ok3, ok4: Boolean;
begin
  T := Trim(S);
  if (T = '') or (T[1] <> '#') then
    raise Exception.CreateFmt('Invalid color literal: %s', [S]);
  T := Copy(T, 2, Length(T) - 1);
  n := Length(T);
  ok4 := True;
  A := 255;
  case n of
    3:
      begin
        // #rgb -> each digit doubled
        R := HexDigit(T[1], ok1) * 17;
        G := HexDigit(T[2], ok2) * 17;
        B := HexDigit(T[3], ok3) * 17;
      end;
    6:
      begin
        R := HexByte(T[1], T[2], ok1);
        G := HexByte(T[3], T[4], ok2);
        B := HexByte(T[5], T[6], ok3);
      end;
    8:
      begin
        R := HexByte(T[1], T[2], ok1);
        G := HexByte(T[3], T[4], ok2);
        B := HexByte(T[5], T[6], ok3);
        A := HexByte(T[7], T[8], ok4);
      end;
  else
    raise Exception.CreateFmt('Invalid color length: %s', [S]);
  end;
  if not (ok1 and ok2 and ok3 and ok4) then
    raise Exception.CreateFmt('Invalid hex in color: %s', [S]);
  Result := TyRGBA(Byte(R), Byte(G), Byte(B), Byte(A));
end;

function TyLighten(c: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // each channel = ch + (255 - ch) * (Pct/100); alpha preserved
  f := Pct / 100;
  Result := TyRGBA(
    ClampByte(TyRedOf(c)   + (255 - TyRedOf(c))   * f),
    ClampByte(TyGreenOf(c) + (255 - TyGreenOf(c)) * f),
    ClampByte(TyBlueOf(c)  + (255 - TyBlueOf(c))  * f),
    TyAlphaOf(c));
end;

function TyDarken(c: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // each channel = ch * (1 - Pct/100); alpha preserved
  f := 1 - (Pct / 100);
  Result := TyRGBA(
    ClampByte(TyRedOf(c)   * f),
    ClampByte(TyGreenOf(c) * f),
    ClampByte(TyBlueOf(c)  * f),
    TyAlphaOf(c));
end;

function TyAlpha(c: TTyColor; A: Single): TTyColor;
begin
  // replace alpha with A (0..1 -> 0..255); rgb preserved
  Result := TyRGBA(TyRedOf(c), TyGreenOf(c), TyBlueOf(c), ClampByte(A * 255));
end;

function TyMix(c1, c2: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // result = c1*(1-f) + c2*f where f = Pct/100 (Pct is amount of c2)
  f := Pct / 100;
  Result := TyRGBA(
    ClampByte(TyRedOf(c1)   * (1 - f) + TyRedOf(c2)   * f),
    ClampByte(TyGreenOf(c1) * (1 - f) + TyGreenOf(c2) * f),
    ClampByte(TyBlueOf(c1)  * (1 - f) + TyBlueOf(c2)  * f),
    ClampByte(TyAlphaOf(c1) * (1 - f) + TyAlphaOf(c2) * f));
end;

end.
