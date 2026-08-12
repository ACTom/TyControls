unit tyControls.Types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics;

type
  TTyColor = type Cardinal;            // $AARRGGBB

  TTyRectArray = array of TRect;

  // Input-method (IME) callbacks shared by the Qt/GTK2 widgetset helpers (tyControls.QtWS/.Gtk2WS)
  // and the controls that opt in (Edit/Memo). Kept here in the common types unit so neither
  // widgetset helper has to depend on the other.
  TTyImeCommitEvent = procedure(const ACommitUtf8: string) of object;   // full committed UTF-8 text
  TTyImeCaretQuery = function: TRect of object;                         // caret rect, client device px

  { How a Wayland popup snaps to its anchor rect: drop directly BELOW it (dropdowns, bar cells,
    context menus) or fly out to one SIDE of it (a submenu cascade -- LTR opens right, mirrored
    opens left). In the shared types unit so the neutral PlatformWS facade + the GTK3 helper can
    both name it without either depending on the other. Only GTK3 acts on it. }
  TTyPopupAnchorMode = (pamBelow, pamRightOf, pamLeftOf);

  // tysSelected is APPENDED last so existing ordinals (and the golden baseline)
  // are unchanged; the cascade application order is set by cStateOrder in StyleModel,
  // not by this enum order. Driven by TTyButton.Down; matched by the ':selected'
  // (alias ':checked') pseudo-class.
  TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled, tysSelected);
  TTyStateSet = set of TTyState;

  TTyFillKind = (tfkNone, tfkSolid, tfkLinearGradient, tfkNineSlice, tfkImage);

  // How a plain background image (tfkImage) maps into the target rect.
  TTyImageMode = (timCover, timStretch, timCenter);

  TTyBorderStyle = (tbsSolid, tbsNone, tbsOutset, tbsInset);   // v3/B2: outset/inset = two-tone 3D bevel

  // v3/D: a control's render-style FAMILY. A one-word preset that bundles a look so a skin
  // need not spell out the individual border/radius tokens on every control.
  TTyRenderStyle = (trsFlat, trsBevel3D, trsInset3D);

  TTyCorners = record
    TL, TR, BR, BL: Integer;   // per-corner radii, logical px
  end;

  // v3/B1: one colour stop of a (multi-stop) linear gradient.
  TTyGradStop = record
    Color: TTyColor;
    Pos: Single;   // 0..1 along the gradient axis
  end;

  TTyFill = record
    Kind: TTyFillKind;
    Color: TTyColor;
    GradFrom, GradTo: TTyColor;    // 2-stop fast path (kept byte-identical; = stops[0]/[last])
    GradStops: array of TTyGradStop;  // v3/B1: >=2 stops; the painter uses a multi-stop scanner only when >2
    GradAngleDeg: Single;
    ImagePath: string;
    SliceInsets: TRect;
    SliceRepeat: Boolean;      // v3/B3: nine-slice edges/center TILE instead of stretch
    ImageMode: TTyImageMode;   // tfkImage only
    Blur: Integer;             // tfkImage Gaussian blur radius, logical px (0 = none)
    GlassBlur: Integer;        // frosted-glass: blur radius of the backdrop seen through
                               // this control, logical px (0 = opaque, no glass)
    GlassTint: TTyColor;       // translucent tint composited over the blurred slice
  end;

  TTyProp = (tpBackground, tpTextColor, tpBorderColor, tpBorderWidth, tpBorderRadius,
             tpPadding, tpFontName, tpFontSize, tpFontWeight, tpOpacity, tpShadow,
             tpBorderStyle, tpOutline, tpGlass, tpBgUnderTitle, tpWindowShadow, tpRenderStyle);
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
    RenderStyle: TTyRenderStyle;   // v3/D: family preset (flat/bevel3d/inset3d)
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

  // Library identity — surfaced by every component's read-only `Version` property and
  // the design-time About dialog. Bump TyVersion on each release (3-part: major.minor.patch).
  // 2.99.x is the 3.0 alpha line: it must sort ABOVE every 2.2.x so an installed 2.2
  // package is never preferred over it, and below the eventual 3.0.0.
  TyVersion     = '2.99.0';
  TyHomepageUrl = 'https://github.com/ACTom/TyControls';

  // Shared logical-px spacing/size constants (96-PPI baseline). Promoted from
  // duplicated hard-coded literals so they cannot silently drift; each call site
  // still scales them via MulDiv(..., APPI, 96) / TTyPainter.Scale().
  TyFieldButtonWidth = 18;   // SpinEdit up/down button width; ComboBox dropdown button width
  TyDropChevronSize  = 9;    // the drop-down chevron's WIDTH. It was a literal default on
                             // TTyPainter.DrawDropChevron that no caller ever overrode, i.e.
                             // the one visual value in the drop-field path a theme could not
                             // reach -- and the reason the chevron stays 9px while the button
                             // zone grows to 25 on the modern density axis
  TyTrackThickness   = 4;    // TrackBar GROOVE thickness -- the recessed band the thumb rides,
                             // not the control height (the bar used to fill its whole client
                             // rect, which is why it read as a slab and swallowed its ticks)
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
  TyTitleBarClassicHeight = 32;   // TitleBar height under classic density (modern: --titlebar-height)
  TyTitleButtonWidth = 46;   // TitleBar caption-button (min/max/close) width

  // Badge metrics, shared by TTyButton's built-in badge and the standalone TTyBadge so
  // the two cannot drift apart. They live HERE, below both, because tyControls.Badge
  // uses tyControls.Button (for TTyBadgePosition) and so cannot lend it a constant back.
  // Each is only the FALLBACK for the theme metric token named beside it: resolve via
  // ActiveController.Metric(TyBadgeInsetVar, TyBadgeInset), then scale.
  TyBadgeInset   = 2;   // inset from the host rect's corner
  TyBadgeMinSize = 8;   // degenerate-measure floor: stay visible
  TyBadgeDotSize = 8;   // TTyBadge dot diameter (no counterpart in TTyButton)

  // The metric tokens those fallbacks back. Named constants rather than literals so a
  // typo cannot silently strand one call site on the default.
  TyBadgeInsetVar   = '--badge-inset';
  TyBadgeMinSizeVar = '--badge-min-size';
  TyBadgeDotSizeVar = '--badge-dot-size';

  // The line box a MULTI-LINE caption is laid out on, logical px. There is deliberately no
  // fallback constant beside it: the default is the FONT's own line box, which only the
  // measuring canvas knows, so the resolver returns 0 for "unset" and each consumer asks the
  // font. Any extra leading over the font's own is a visual value and therefore the theme's
  // to give -- hard-coding one here would be exactly the kind of value a skin cannot reach.
  // Resolve it with TyLineHeight(ActiveController) (tyControls.Controller).
  TyLineHeightVar   = '--line-height';

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
{ True when a resolved style asks for a visible border: it needs a declared colour and a
  non-zero width, and `border-style: none` kills it outright — but only when the theme
  actually declared that property (an ABSENT border-style means "unspecified", not "none").
  Every control that strokes a border gates on this, so `border-width: 0` and
  `border-style: none` behave identically everywhere. }
function TyBorderVisible(const AStyle: TTyStyleSet): Boolean;
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

function TyBorderVisible(const AStyle: TTyStyleSet): Boolean;
begin
  Result := (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0)
    and not ((tpBorderStyle in AStyle.Present) and (AStyle.BorderStyle = tbsNone));
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
