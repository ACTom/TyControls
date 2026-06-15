unit tyControls.Types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics;

type
  TTyColor = type Cardinal;            // $AARRGGBB

  TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled);
  TTyStateSet = set of TTyState;

  TTyFillKind = (tfkNone, tfkSolid, tfkLinearGradient, tfkNineSlice);

  TTyBorderStyle = (tbsSolid, tbsNone);

  TTyCorners = record
    TL, TR, BR, BL: Integer;   // per-corner radii, logical px
  end;

  TTyFill = record
    Kind: TTyFillKind;
    Color: TTyColor;
    GradFrom, GradTo: TTyColor;
    GradAngleDeg: Single;
    ImagePath: string;
    SliceInsets: TRect;
  end;

  TTyProp = (tpBackground, tpTextColor, tpBorderColor, tpBorderWidth, tpBorderRadius,
             tpPadding, tpFontName, tpFontSize, tpFontWeight, tpOpacity, tpShadow,
             tpBorderStyle, tpOutline);
  TTyPropSet = set of TTyProp;

  TTyStyleSet = record
    Present: TTyPropSet;
    Background: TTyFill;
    TextColor: TTyColor;
    BorderColor: TTyColor;
    BorderWidth: Integer;
    BorderStyle: TTyBorderStyle;
    BorderRadius: Integer;
    Radius: TTyCorners;          // per-corner radii; falls back to BorderRadius when all 0.
                                 // Carried under tpBorderRadius (not a separate Present flag).
    Padding: TRect;
    FontName: string;
    FontSize: Integer;
    FontWeight: Integer;
    Opacity: Single;
    ShadowColor: TTyColor;
    ShadowBlur: Integer;
    ShadowOffset: TPoint;
    OutlineColor: TTyColor;
    OutlineWidth: Integer;
    OutlineOffset: Integer;
  end;

const
  tyTransparent = TTyColor($00000000);

function TyRGB(R, G, B: Byte): TTyColor;
function TyRGBA(R, G, B, A: Byte): TTyColor;
function TyAlphaOf(c: TTyColor): Byte;
function TyRedOf(c: TTyColor): Byte;
function TyGreenOf(c: TTyColor): Byte;
function TyBlueOf(c: TTyColor): Byte;
function TyColorToLCL(c: TTyColor): TColor;
function TyCorners(ATL, ATR, ABR, ABL: Integer): TTyCorners;
function TyUniformCorners(R: Integer): TTyCorners;
function TyEffectiveCorners(const AStyle: TTyStyleSet): TTyCorners;
{ Caps a (theme-token) corner radius at a sub-element's half-side so a smaller
  theme radius is honored but the geometry can never exceed a perfect circle.
  ARadius and AHalf MUST be in the SAME unit (both logical or both device). }
function TyClampRadius(ARadius, AHalf: Integer): Integer;
function EmptyStyleSet: TTyStyleSet;

implementation

function TyRGB(R, G, B: Byte): TTyColor;
begin
  Result := TTyColor((Cardinal($FF) shl 24) or (Cardinal(R) shl 16) or
                     (Cardinal(G) shl 8) or Cardinal(B));
end;

function TyRGBA(R, G, B, A: Byte): TTyColor;
begin
  Result := TTyColor((Cardinal(A) shl 24) or (Cardinal(R) shl 16) or
                     (Cardinal(G) shl 8) or Cardinal(B));
end;

function TyAlphaOf(c: TTyColor): Byte;
begin
  Result := Byte((Cardinal(c) shr 24) and $FF);
end;

function TyRedOf(c: TTyColor): Byte;
begin
  Result := Byte((Cardinal(c) shr 16) and $FF);
end;

function TyGreenOf(c: TTyColor): Byte;
begin
  Result := Byte((Cardinal(c) shr 8) and $FF);
end;

function TyBlueOf(c: TTyColor): Byte;
begin
  Result := Byte(Cardinal(c) and $FF);
end;

function TyColorToLCL(c: TTyColor): TColor;
begin
  // LCL TColor is $00BBGGRR (alpha-less); drop the TTyColor alpha channel.
  Result := RGBToColor(TyRedOf(c), TyGreenOf(c), TyBlueOf(c));
end;

function TyCorners(ATL, ATR, ABR, ABL: Integer): TTyCorners;
begin
  Result.TL := ATL; Result.TR := ATR; Result.BR := ABR; Result.BL := ABL;
end;

function TyUniformCorners(R: Integer): TTyCorners;
begin
  Result.TL := R; Result.TR := R; Result.BR := R; Result.BL := R;
end;

function TyClampRadius(ARadius, AHalf: Integer): Integer;
begin
  if ARadius < AHalf then Result := ARadius else Result := AHalf;
  if Result < 0 then Result := 0;
end;

function TyEffectiveCorners(const AStyle: TTyStyleSet): TTyCorners;
begin
  // Per-corner Radius wins; if it was never set (all zero) but a uniform
  // BorderRadius was (e.g. a code-built style), derive uniform corners from it.
  if (AStyle.Radius.TL = 0) and (AStyle.Radius.TR = 0) and
     (AStyle.Radius.BR = 0) and (AStyle.Radius.BL = 0) and (AStyle.BorderRadius > 0) then
    Result := TyUniformCorners(AStyle.BorderRadius)
  else
    Result := AStyle.Radius;
end;

function EmptyStyleSet: TTyStyleSet;
begin
  // Default() zero-initializes safely (including the managed FontName string),
  // unlike FillChar which bypasses managed-type handling. Present=[], all colors
  // and metrics 0, Background.Kind=tfkNone (first enum value); only Opacity differs.
  Result := Default(TTyStyleSet);
  Result.Opacity := 1.0;
end;

end.
