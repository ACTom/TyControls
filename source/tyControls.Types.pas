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
             tpBorderStyle);
  TTyPropSet = set of TTyProp;

  TTyStyleSet = record
    Present: TTyPropSet;
    Background: TTyFill;
    TextColor: TTyColor;
    BorderColor: TTyColor;
    BorderWidth: Integer;
    BorderStyle: TTyBorderStyle;
    BorderRadius: Integer;
    Padding: TRect;
    FontName: string;
    FontSize: Integer;
    FontWeight: Integer;
    Opacity: Single;
    ShadowColor: TTyColor;
    ShadowBlur: Integer;
    ShadowOffset: TPoint;
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

function EmptyStyleSet: TTyStyleSet;
begin
  // Default() zero-initializes safely (including the managed FontName string),
  // unlike FillChar which bypasses managed-type handling. Present=[], all colors
  // and metrics 0, Background.Kind=tfkNone (first enum value); only Opacity differs.
  Result := Default(TTyStyleSet);
  Result.Opacity := 1.0;
end;

end.
