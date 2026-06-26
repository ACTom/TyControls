unit tyControls.Types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics;

type
  TTyColor = type Cardinal;            // $AARRGGBB

  TTyRectArray = array of TRect;

  // Input-method (IME) callbacks shared by the Qt/GTK widgetset helpers (tyControls.QtWS/.GtkWS)
  // and the controls that opt in (Edit/Memo). Kept here in the common types unit so neither
  // widgetset helper has to depend on the other.
  TTyImeCommitEvent = procedure(const ACommitUtf8: string) of object;   // full committed UTF-8 text
  TTyImeCaretQuery = function: TRect of object;                         // caret rect, client device px

  // tysSelected is APPENDED last so existing ordinals (and the golden baseline)
  // are unchanged; the cascade application order is set by cStateOrder in StyleModel,
  // not by this enum order. Driven by TTyButton.Down; matched by the ':selected'
  // (alias ':checked') pseudo-class.
  TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled, tysSelected);
  TTyStateSet = set of TTyState;

  TTyFillKind = (tfkNone, tfkSolid, tfkLinearGradient, tfkNineSlice, tfkImage);

  // How a plain background image (tfkImage) maps into the target rect.
  TTyImageMode = (timCover, timStretch, timCenter);

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
    ImageMode: TTyImageMode;   // tfkImage only
    Blur: Integer;             // tfkImage Gaussian blur radius, logical px (0 = none)
    GlassBlur: Integer;        // frosted-glass: blur radius of the backdrop seen through
                               // this control, logical px (0 = opaque, no glass)
    GlassTint: TTyColor;       // translucent tint composited over the blurred slice
  end;

  TTyProp = (tpBackground, tpTextColor, tpBorderColor, tpBorderWidth, tpBorderRadius,
             tpPadding, tpFontName, tpFontSize, tpFontWeight, tpOpacity, tpShadow,
             tpBorderStyle, tpOutline, tpGlass, tpBgUnderTitle, tpWindowShadow);
  TTyPropSet = set of TTyProp;

  TTyStyleSet = record
    Present: TTyPropSet;
    Background: TTyFill;
    BackgroundUnderTitlebar: Boolean;   // TyForm only: image extends under the title bar
    WindowShadow: Boolean;              // TyForm only: toggle the OS-native window drop shadow
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

  // Library identity — surfaced by every component's read-only `About` property and
  // the design-time About dialog. Bump TyVersion on each release.
  TyVersion     = '2.0.0.0';
  TyHomepageUrl = 'https://github.com/ACTom/TyControls';

  // Shared logical-px spacing/size constants (96-PPI baseline). Promoted from
  // duplicated hard-coded literals so they cannot silently drift; each call site
  // still scales them via MulDiv(..., APPI, 96) / TTyPainter.Scale().
  TyFieldButtonWidth = 18;   // SpinEdit up/down button width; ComboBox dropdown button width
  TyScrollbarSize    = 12;   // embedded vertical scrollbar width (Memo, ListBox)
  TyCheckBoxBox      = 16;   // CheckBox/RadioButton box (indicator) size
  TyCheckBoxGap      = 6;    // gap between the box and the caption
  TyTabPad           = 12;   // TabControl header horizontal padding (each side)
  TyTabMinWidth      = 48;   // TabControl header minimum width
  TyTabCloseSize     = 14;   // TabControl close-glyph slot size
  TyTabGap           = 6;    // TabControl gap between caption/close slot
  TyTabMargin        = 6;    // TabControl close-glyph right margin
  TyTabArrowBand     = 16;   // TabControl overflow scroll-arrow width
  TyTitleBarPad      = 8;    // TitleBar caption + content-zone left margin
  TyTitleButtonWidth = 46;   // TitleBar caption-button (min/max/close) width

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
