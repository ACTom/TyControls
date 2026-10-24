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

  { What the platform's own window frame does for a TTyForm (macOS frame spec 2026-10-14). The
    chrome engine and the title bar ask tyControls.PlatformWS.TyFrameTraits rather than testing
    for a widgetset. }
  TTyFrameTrait = (
    { The system window move is a loop that runs until the button comes up (Win32's caption
      move, Cocoa's performWindowDrag). It is started past a drag threshold, never on the press,
      and it carries a window the system maximized along by itself. }
    ftrModalMove,
    { The system resizes the window from its edges, so the engine's own edge resize stays off. }
    ftrNativeResize,
    { Maximize is the system's zoom (Cocoa), not the engine's work-area fill. }
    ftrNativeZoom,
    { The system draws its own caption buttons (the macOS traffic lights); a title bar leaves
      them a slot instead of showing its own. }
    ftrSystemButtons);
  TTyFrameTraits = set of TTyFrameTrait;

  { The frame TTyForm asks the platform for (tyControls.PlatformWS.TyApplyWindowFrame). }
  TTyWindowFrame = record
    Resizable: Boolean;      // the edges resize the window
    CanClose: Boolean;       // each system button's ENABLED state: one the window does not
    CanMinimize: Boolean;    // offer is greyed, not hidden, as macOS shows it
    CanMaximize: Boolean;
    SystemButtons: Boolean;  // whether the system's caption buttons show at all
    { The window is in the system's full screen, where the system slides its own title bar in
      over the content: that bar gets its own look back (opaque, titled). }
    FullScreen: Boolean;
    { The smallest the user may drag the window to, px; 0 = no minimum. }
    MinSize: TSize;
  end;

  { The system's caption buttons taken as one group, device px. }
  TTySystemButtonGroup = record
    Size: TSize;      // the three buttons with the system's own spacing between them; 0 x 0 = none
    Inset: Integer;   // how far the system's own title bar keeps the group from the window edge
  end;

  { What a double-click on the title bar does, where the platform has a setting for it. }
  TTyTitleDoubleClick = (tdcMaximize, tdcMinimize, tdcNone);

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
  // the design-time About dialog. Bump TyVersion on each release. The stable line is
  // 3-part (major.minor.patch); a pre-release appends a `-Beta`/`-RC` suffix, which is
  // DISPLAY ONLY — the .lpk <Version> stays numeric (3.0.0). 2.99.x was the 3.0 alpha
  // line (kept above every 2.2.x, below 3.0.0); 3.0.0 is now the first official release,
  // shipping first as 3.0.0-Beta; main is the 4.0 feature line, numbered 3.99 until 4.0 ships (3.0 fixes live on branch 3.0-fixes).
  TyVersion     = '3.99.0';
  TyHomepageUrl = 'https://github.com/ACTom/TyControls';

  // Shared logical-px spacing/size constants (96-PPI baseline). Promoted from
  // duplicated hard-coded literals so they cannot silently drift; each call site
  // still scales them via MulDiv(..., APPI, 96) / TTyPainter.Scale().
  TyFieldButtonWidth = 18;   // SpinEdit up/down button width; ComboBox dropdown button width
  TyDropChevronSize  = 7;    // the LONG side of a disclosure chevron's centre line -- a drop
                             // field's V and a tree's > alike (--glyph-chevron-size). 7 puts
                             // the ink at ~0.9x the cap height of the 9pt body text, where
                             // Windows 11, macOS and GNOME all sit (0.6-0.93x); the old 9 was
                             // 1.22x, and the tree's slot-filling > was 1.33x
  TyChevronAlpha     = 200;  // a chevron's ink over its text colour's own alpha, 0..255
                             // (--glyph-chevron-alpha). Windows 11 draws drop and submenu
                             // marks in its secondary text colour (62%), GNOME dims trees and
                             // expanders to 70%, macOS greys its outline marks -- but they
                             // blend in sRGB and BGRA blends in linear light, which pales a
                             // partial alpha: black at 180 here peaks at 126, at 200 at 106,
                             // where the Windows 11 chevron's darkest pixel is (about 111)
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

const
  { A STYLE'S FontWeight CARRIES THE FONT'S STYLE (#92). Every text call in the library passes
    a style's FontWeight on as it is -- a hundred and fifty of them -- and a control's own
    Font can be italic, underlined or struck out, which a CSS weight cannot say. So those three
    ride above the weight's range (1..1000) and only the two font set-ups in tyControls.Painter
    read them. Anything that wants the weight as a number takes TyFontWeightOf first; a bare
    `FontWeight >= 600` would call an italic regular font bold (test.controlfont guards it). }
  TyFontItalic     = $10000;
  TyFontUnderline  = $20000;
  TyFontStrikeOut  = $40000;
  TyFontWeightMask = $FFFF;

{ The CSS weight of a style's FontWeight, without the style flags. }
function TyFontWeightOf(AWeight: Integer): Integer;
{ The font style a style's FontWeight draws: bold from a weight of 600 and up, and the flags. }
function TyFontStylesOf(AWeight: Integer): TFontStyles;
{ AWeight with a font's style laid over it: bold makes the weight 700, no bold keeps AWeight's
  own; italic, underline and strikeout set their flags. }
function TyFontWeightWithStyle(AWeight: Integer; AStyle: TFontStyles): Integer;
function TyAlphaOf(c: TTyColor): Byte;
function TyRedOf(c: TTyColor): Byte;
function TyGreenOf(c: TTyColor): Byte;
function TyBlueOf(c: TTyColor): Byte;
function TyColorToLCL(c: TTyColor): TColor;
function TyCorners(ATL, ATR, ABR, ABL: Integer): TTyCorners;
function TyUniformCorners(R: Integer): TTyCorners;
function TyEffectiveCorners(const AStyle: TTyStyleSet): TTyCorners;
{ True when a linear gradient has to be drawn stop by stop: three or more stops, or two that do
  not sit at 0 and 1. The two-colour scanner (first colour to last over the whole sweep) is
  exact only for two stops at 0 and 1, and is kept for exactly those, so the two-colour
  gradients every theme ships render as they always did. Used by every place that builds a
  gradient scanner, so the painter and the parent-background samplers cannot disagree. }
function TyGradientNeedsStops(const AFill: TTyFill): Boolean;
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

var
  { IDE bridge, the OwnerFormDesignerModifiedProc pattern: the designtime package points
    this at GlobalDesignHook.RefreshPropertyValues (ideintf, unreachable from here), so a
    control whose DESIGN-TIME gesture changed a published value can make the Object
    Inspector re-read what it shows. It must, because the IDE splits the concerns:
    OwnerFormDesignerModified only marks the unit dirty (TMainIDE.DesignerModified never
    touches the OI), and the OI re-reads only on the RefreshPropertyValues hook.
    nil outside the IDE. Callers gate on csDesigning themselves. }
  TyDesignerRefreshValuesProc: procedure = nil;

implementation

function TyRGB(R, G, B: Byte): TTyColor;
begin
  Result := TTyColor((Cardinal($FF) shl 24) or (Cardinal(R) shl 16) or
                     (Cardinal(G) shl 8) or Cardinal(B));
end;

function TyFontWeightOf(AWeight: Integer): Integer;
begin
  Result := AWeight and TyFontWeightMask;
end;

function TyFontStylesOf(AWeight: Integer): TFontStyles;
var
  css: Integer;
begin
  css := AWeight and TyFontWeightMask;
  Result := [];
  if css >= 600 then Include(Result, fsBold);
  if (AWeight and TyFontItalic) <> 0 then Include(Result, fsItalic);
  if (AWeight and TyFontUnderline) <> 0 then Include(Result, fsUnderline);
  if (AWeight and TyFontStrikeOut) <> 0 then Include(Result, fsStrikeOut);
end;

function TyFontWeightWithStyle(AWeight: Integer; AStyle: TFontStyles): Integer;
begin
  if fsBold in AStyle then
    Result := 700
  else
    Result := AWeight and TyFontWeightMask;
  if fsItalic in AStyle then Result := Result or TyFontItalic;
  if fsUnderline in AStyle then Result := Result or TyFontUnderline;
  if fsStrikeOut in AStyle then Result := Result or TyFontStrikeOut;
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

function TyGradientNeedsStops(const AFill: TTyFill): Boolean;
var
  n: Integer;
begin
  n := Length(AFill.GradStops);
  Result := (n > 2) or
    ((n = 2) and ((AFill.GradStops[0].Pos <> 0) or (AFill.GradStops[1].Pos <> 1)));
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
