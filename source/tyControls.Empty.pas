unit tyControls.Empty;
{$mode objfpc}{$H+}
{ TTyEmpty — the empty-state placeholder: a picture, a line of text, and an optional
  action, centred in the region that has nothing in it.

  Standard furniture for a list / tree / table with no rows: today the only way to say
  "no data" is to hand-assemble a TTyLabel and centre it yourself. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel, tyControls.StrConsts;

const
  { Built-in logical-px defaults (96-PPI baseline) for the placeholder's three metrics. A
    skin retunes each through the named token beside it (the v3/C convention); these are
    only what a theme that sets none falls back to. All three are scaled to device px at
    every call site. }
  TyEmptyImageSize    = 48;   // the picture's square edge: big enough to read as a box
  TyEmptyGap          = 8;    // vertical air between picture, message and action
  TyEmptyActionHeight = 32;   // the action band: clears a default-height TTyButton (30)

  { The tokens those fallbacks back. Named constants rather than literals so a typo cannot
    silently strand one call site on the default (the TyBadge*Var convention). }
  TyEmptyImageSizeVar    = '--empty-image-size';
  TyEmptyGapVar          = '--empty-gap';
  TyEmptyActionHeightVar = '--empty-action-height';
  { v3/C5 icon-font override for the built-in carton vector. NOT a TTyGlyphKind: the
    painter's kinds are control chrome and status marks, and an empty-state illustration
    is neither — so the vector lives here and hooks the override seam directly, the way
    TTyComboBox's drop chevron does with --glyph-dropdown. }
  TyEmptyGlyphVar        = '--glyph-empty';

type
  { The three stacked blocks of a placeholder, in DEVICE pixels, expressed in the SAME
    coordinate space as the rect handed in:
      ImageRect  — the picture, a centred square (empty when hidden / no room)
      TextRect   — the message band, spanning the full width (empty when hidden/no room)
      ActionRect — the action band, spanning the full width (empty when hidden/no room)
    Unlike a card's bands these do NOT tile their container: the stack is CENTRED in it
    and the space above/below is deliberately blank — that air is what makes an empty
    state read as empty rather than as a broken toolbar. }
  TTyEmptyLayout = record
    ImageRect: TRect;
    TextRect: TRect;
    ActionRect: TRect;
  end;

{ The height a placeholder stack occupies, DEVICE px: every PRESENT block (size > 0) plus
  one AGap between each adjacent pair — never a gap above the first or below the last, and
  never a gap for a block that is not shown. Pass 0 for a hidden block. This is what
  TyEmptyLayout centres, and what AutoSize measures to.
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyEmptyStackHeight(AImageSize, ATextHeight, AActionHeight, AGap: Integer): Integer;

{ Pure block geometry for a placeholder. All inputs/outputs are DEVICE px.
    AClient      — the rect to centre in (the caller has already applied padding).
    AImageSize   — the picture's square edge; 0 for "no picture".
    ATextHeight  — the message band's height; 0 for "no message".
    AActionHeight— the action band's height; 0 for "no action".
    AGap         — vertical air between adjacent blocks.
  Rules, in the order they bite:
    * A picture WIDER than the client shrinks to the client width, staying square (so it
      costs less height too) rather than bleeding out of the sides.
    * A stack taller than the client DROPS THE PICTURE first: it is decoration, while the
      message and the action are the whole reason the placeholder exists.
    * Still too tall: the stack starts at the client top rather than riding off it, and
      each block is squashed into the remaining room — a block with no room left at all
      comes out empty. Never an inverted rect.
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyEmptyLayout(const AClient: TRect; AImageSize, ATextHeight, AActionHeight,
  AGap: Integer): TTyEmptyLayout;

type
  { TTyEmpty — an empty-state placeholder: a themed picture, a line of text, and an
    optional action, stacked and centred in the control.

    WINDOWED (TTyCustomControl), for one reason: the action is a REAL control — the host
    drops a TTyButton ('Create the first one') into it, and child controls can only be
    parented to a TWinControl. A graphic control has no handle to parent them to; this is
    the same call TTyCard made, for the same reason (see docs/controls/card.md §2).
    The trade-off is real and accepted: one HWND per placeholder, and none of the free
    parent-surface show-through in the corner gaps that a graphic control (TTyTag) gets.
    Both are cheap HERE, because an empty state is a SINGLETON filling a list's client
    area — not a crowd like tags — and its themed background is normally transparent, so
    there are no rounded corners to leak in the first place.

    typeKey 'TyEmpty' is the surface AND the message (background/border/radius/padding +
    color/font-* for the text). The picture's ink resolves from 'TyEmptyImage': the
    illustration has to be able to sit far lighter than the message (AntD's is barely
    more than a hairline) and one rule cannot carry two inks. No TyEmptyImage colour =>
    the picture takes the message's own ink — never a hard-coded colour. }
  TTyEmpty = class(TTyCustomControl)
  private
    FDescription: string;
    FShowImage: Boolean;
    FShowDescription: Boolean;
    FShowAction: Boolean;
    procedure SetDescription(const AValue: string);
    procedure SetShowImage(AValue: Boolean);
    procedure SetShowDescription(AValue: Boolean);
    procedure SetShowAction(AValue: Boolean);
    { Block sizes in DEVICE px at APPI, from the theme metrics. }
    function ImageSizeAtPPI(APPI: Integer): Integer;
    function GapAtPPI(APPI: Integer): Integer;
    function ActionHeightAtPPI(APPI: Integer): Integer;
    { The message's extent in device px at APPI, measured in the THEME's font. }
    procedure MeasureDescription(APPI: Integer; out AWidthPx, AHeightPx: Integer);
    function TextHeightAtPPI(APPI: Integer): Integer;
    { AClient inset by the themed padding, never inverted. }
    function PaddedRect(const AClient: TRect; const AStyle: TTyStyleSet; APPI: Integer): TRect;
    { TyEmptyLayout fed from the resolved theme. RenderTo AND AdjustClientRect both route
      through here, so the painted stack and the carved child area cannot drift apart. }
    function LayoutAtPPI(const AClient: TRect; APPI: Integer): TTyEmptyLayout;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    { The message actually drawn. A blank Description means "the library's own translated
      default", NOT "no message" — hide the message with ShowDescription. }
    function DisplayDescription: string;
    { The painted picture square, in CLIENT coordinates; empty when hidden or squeezed out. }
    function ImageRect: TRect;
    { The painted message band, in CLIENT coordinates; empty when hidden or squeezed out. }
    function DescriptionRect: TRect;
    { The action band, in CLIENT coordinates — the CHILD AREA, not something the control
      paints. Empty (zero-height) when ShowAction is False. Position hand-placed (alNone)
      children against it: LCL's raw client coords would drop them on the picture. }
    function ActionRect: TRect;
  published
    { The message. '' = the library's translated "no data" (see DisplayDescription); any
      other text overrides it. Drawn literally (no mnemonic parsing — a placeholder
      activates nothing), centred, ellipsised when it does not fit. }
    property Description: string read FDescription write SetDescription;
    { Whether the picture is drawn AND takes room in the stack. }
    property ShowImage: Boolean read FShowImage write SetShowImage default True;
    { Whether the message is drawn AND takes room in the stack. The flag is authoritative,
      not the text: a blank Description falls back to the default message rather than
      collapsing the band, so clearing it never makes the stack jump. }
    property ShowDescription: Boolean read FShowDescription write SetShowDescription default True;
    { Whether the action band is reserved at the foot of the stack AND handed to child
      controls as the client area. Off (the default) there is NO child area at all — an
      empty state usually has no action, and reserving the band unasked would push the
      message off-centre. }
    property ShowAction: Boolean read FShowAction write SetShowAction default False;
    { With AutoSize the placeholder hugs its stack (plus the themed padding); off, it
      keeps its bounds and centres the stack in them — which is the normal use (alClient
      inside the empty list). }
    property AutoSize;
    property Align;
    property Anchors;
    property Enabled;
    property Font;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

uses
  BGRABitmap, BGRABitmapTypes;

{ ---- pure geometry ---- }

function TyEmptyStackHeight(AImageSize, ATextHeight, AActionHeight, AGap: Integer): Integer;
var
  n: Integer;
begin
  if AImageSize < 0 then AImageSize := 0;
  if ATextHeight < 0 then ATextHeight := 0;
  if AActionHeight < 0 then AActionHeight := 0;
  if AGap < 0 then AGap := 0;
  Result := 0;
  n := 0;
  if AImageSize > 0 then begin Inc(Result, AImageSize); Inc(n); end;
  if ATextHeight > 0 then begin Inc(Result, ATextHeight); Inc(n); end;
  if AActionHeight > 0 then begin Inc(Result, AActionHeight); Inc(n); end;
  // A gap only BETWEEN blocks — never above the first, below the last, or for a block
  // that is not shown (hiding the picture must not leave its air behind).
  if n > 1 then Inc(Result, AGap * (n - 1));
end;

function TyEmptyLayout(const AClient: TRect; AImageSize, ATextHeight, AActionHeight,
  AGap: Integer): TTyEmptyLayout;
var
  clientW, clientH, total, y, imgL: Integer;

  { Take AHeight off the top of the running Y cursor. The cursor advances by the FULL
    block even when the block did not fit, so the blocks below stay in the same order and
    simply run out of room — they never creep back up into the space above. }
  procedure Place(var ARect: TRect; AHeight, ALeft, ARight: Integer);
  begin
    ARect := Rect(0, 0, 0, 0);
    if AHeight <= 0 then Exit;   // hidden: no rect, and (see above) no gap either
    if y < AClient.Bottom then
    begin
      ARect := Rect(ALeft, y, ARight, y + AHeight);
      if ARect.Bottom > AClient.Bottom then
        ARect.Bottom := AClient.Bottom;   // squash into what is left, never overflow
    end;
    Inc(y, AHeight + AGap);
  end;

begin
  Result.ImageRect := Rect(0, 0, 0, 0);
  Result.TextRect := Rect(0, 0, 0, 0);
  Result.ActionRect := Rect(0, 0, 0, 0);

  clientW := AClient.Right - AClient.Left;
  clientH := AClient.Bottom - AClient.Top;
  if (clientW <= 0) or (clientH <= 0) then Exit;   // degenerate/inverted: nothing to lay out

  if AImageSize < 0 then AImageSize := 0;
  if ATextHeight < 0 then ATextHeight := 0;
  if AActionHeight < 0 then AActionHeight := 0;
  if AGap < 0 then AGap := 0;
  // A picture wider than the client shrinks to fit rather than bleeding out of the sides.
  // It stays SQUARE, so this costs height too — which the fit check below then sees.
  if AImageSize > clientW then AImageSize := clientW;

  total := TyEmptyStackHeight(AImageSize, ATextHeight, AActionHeight, AGap);
  // Too tall: the picture is decoration and loses first. The message and the action are
  // why the placeholder is on screen at all, so they keep the room.
  if (total > clientH) and (AImageSize > 0) then
  begin
    AImageSize := 0;
    total := TyEmptyStackHeight(0, ATextHeight, AActionHeight, AGap);
  end;

  y := AClient.Top + (clientH - total) div 2;
  if y < AClient.Top then y := AClient.Top;   // still too tall: start at the top, don't ride off it

  // The picture is centred horizontally and kept square; the message and the action span
  // the full width (the painter centres the text inside its band).
  imgL := AClient.Left + (clientW - AImageSize) div 2;
  Place(Result.ImageRect, AImageSize, imgL, imgL + AImageSize);
  Place(Result.TextRect, ATextHeight, AClient.Left, AClient.Right);
  Place(Result.ActionRect, AActionHeight, AClient.Left, AClient.Right);
end;

{ ---- the built-in picture ---- }

procedure TyDrawEmptyBox(APainter: TTyPainter; const ARect: TRect; AColor: TTyColor);
{ An open carton — the one shape that reads as "there is nothing in here" without colour
  or text. Drawn in ONE ink like every glyph in the painter: a two-tone illustration could
  not tint from a single theme colour, and this ink is a theme token.
  ARect is the square --empty-image-size sized, and the stroke scales WITH it — a fixed
  width would be a hairline at a 96px picture and a blob at a 24px one. }
var
  px: TBGRAPixel;
  th, l, t, r, b, w, h, bodyT: Single;
begin
  if (ARect.Right - ARect.Left < 4) or (ARect.Bottom - ARect.Top < 4) then
    Exit;   // below this the strokes merge into a smudge; draw nothing rather than a blob
  px := TyColorToBGRA(AColor);
  th := (ARect.Right - ARect.Left) / 24;
  if th < 1 then th := 1;
  // The stroke is centred on the path, so inset by its width to keep it inside the square.
  l := ARect.Left + th;
  t := ARect.Top + th;
  r := ARect.Right - 1 - th;
  b := ARect.Bottom - 1 - th;
  w := r - l;
  h := b - t;
  if (w <= 0) or (h <= 0) then Exit;
  bodyT := t + h * 0.42;
  // The carton body: the lower ~60%, narrower than the flaps span.
  APainter.Bitmap.RectangleAntialias(l + w * 0.14, bodyT, r - w * 0.14, b, px, th);
  // Its two lid flaps, splayed OPEN from the body's top corners. Open is the whole point:
  // a closed box is just a box.
  APainter.Bitmap.DrawLineAntialias(l + w * 0.14, bodyT, l, t, px, th, True);
  APainter.Bitmap.DrawLineAntialias(r - w * 0.14, bodyT, r, t, px, th, True);
end;

{ ---- TTyEmpty ---- }

constructor TTyEmpty.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Designer container: the IDE drops the action control INTO the placeholder, where it
  // lands in the band AdjustClientRect carves (which needs ShowAction — see the doc).
  ControlStyle := ControlStyle + [csAcceptsControls];
  FDescription := '';        // '' = the library's translated default (DisplayDescription)
  FShowImage := True;
  FShowDescription := True;
  FShowAction := False;
  Width := 220;
  Height := 140;
end;

function TTyEmpty.GetStyleTypeKey: string;
begin
  Result := 'TyEmpty';
end;

function TTyEmpty.DisplayDescription: string;
begin
  { A blank Description means "the library's own translated default", resolved HERE — at
    draw/measure time — so the placeholder follows a runtime language switch. Seeding
    FDescription with the resourcestring in the constructor would instead bake the English
    into the user's .lfm (a non-empty string property always streams) and freeze it there
    forever, which is exactly the trap this indirection exists to avoid. }
  if FDescription <> '' then
    Result := FDescription
  else
    Result := rsEmptyDescription;
end;

{ ---- property setters ---- }

procedure TTyEmpty.SetDescription(const AValue: string);
begin
  if FDescription = AValue then Exit;
  FDescription := AValue;
  // The band's HEIGHT is measured from a reference glyph, not from this text, so the
  // stack does not move and the children need no Realign — but an auto-sized placeholder
  // must re-fit its WIDTH to the new message.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyEmpty.SetShowImage(AValue: Boolean);
begin
  if FShowImage = AValue then Exit;
  FShowImage := AValue;
  // Every block below the picture just moved, and the action band is one of them — so the
  // children must be re-laid out, not merely repainted.
  Realign;
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyEmpty.SetShowDescription(AValue: Boolean);
begin
  if FShowDescription = AValue then Exit;
  FShowDescription := AValue;
  Realign;
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyEmpty.SetShowAction(AValue: Boolean);
begin
  if FShowAction = AValue then Exit;
  FShowAction := AValue;
  Realign;   // the child area just appeared/vanished
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

{ ---- theme-driven metrics ---- }

function TTyEmpty.ImageSizeAtPPI(APPI: Integer): Integer;
begin
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies,
  // so the rects the child area is carved from are the rects the paint drew.
  Result := MulDiv(ActiveController.Metric(TyEmptyImageSizeVar, TyEmptyImageSize), APPI, 96);
  if Result < 0 then Result := 0;
end;

function TTyEmpty.GapAtPPI(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(TyEmptyGapVar, TyEmptyGap), APPI, 96);
  if Result < 0 then Result := 0;
end;

function TTyEmpty.ActionHeightAtPPI(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(TyEmptyActionHeightVar, TyEmptyActionHeight), APPI, 96);
  if Result < 1 then Result := 1;   // a reserved band the user cannot see into is a bug
end;

procedure TTyEmpty.MeasureDescription(APPI: Integer; out AWidthPx, AHeightPx: Integer);
{ Measures with a CANVAS-LESS painter (the TTyBadge / tyControls.Form idiom): BeginPaint
  (nil, ...) builds only the painter's internal bitmap and EndPaint frees it WITHOUT
  blitting, so this is safe outside a paint cycle and leaks nothing. It has to be the
  painter and not a TBitmap canvas: the message is DRAWN with BGRA text metrics, and only
  the same measurer reproduces the extent those glyphs actually occupy. }
var
  P: TTyPainter;
  S: TTyStyleSet;
  fs: Integer;
begin
  S := CurrentStyle;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    fs := ResolveFontSize(S);
    AWidthPx := P.MeasureText(DisplayDescription, S.FontName, fs, S.FontWeight).cx;
    // Height from a stable reference glyph ('Ag'), not from the message: the band is ONE
    // line tall whatever it says, so a short message and a long one centre the stack alike.
    AHeightPx := P.MeasureText('Ag', S.FontName, fs, S.FontWeight).cy;
    P.EndPaint;   // nil canvas -> no blit, just frees the measure bitmap
  finally
    P.Free;
  end;
  if AWidthPx < 0 then AWidthPx := 0;
  if AHeightPx < 1 then AHeightPx := 1;
end;

function TTyEmpty.TextHeightAtPPI(APPI: Integer): Integer;
var
  w: Integer;
begin
  MeasureDescription(APPI, w, Result);
end;

function TTyEmpty.PaddedRect(const AClient: TRect; const AStyle: TTyStyleSet;
  APPI: Integer): TRect;
begin
  Result := AClient;
  Inc(Result.Left, MulDiv(AStyle.Padding.Left, APPI, 96));
  Inc(Result.Top, MulDiv(AStyle.Padding.Top, APPI, 96));
  Dec(Result.Right, MulDiv(AStyle.Padding.Right, APPI, 96));
  Dec(Result.Bottom, MulDiv(AStyle.Padding.Bottom, APPI, 96));
  if Result.Right < Result.Left then Result.Right := Result.Left;
  if Result.Bottom < Result.Top then Result.Bottom := Result.Top;
end;

function TTyEmpty.LayoutAtPPI(const AClient: TRect; APPI: Integer): TTyEmptyLayout;
var
  S: TTyStyleSet;
  img, txt, act: Integer;
begin
  if APPI <= 0 then APPI := 96;
  S := CurrentStyle;
  if FShowImage then img := ImageSizeAtPPI(APPI) else img := 0;
  if FShowDescription then txt := TextHeightAtPPI(APPI) else txt := 0;
  if FShowAction then act := ActionHeightAtPPI(APPI) else act := 0;
  // The stack centres in the client inset by the themed padding — that is what padding
  // means for a surface, and it is the ONE place it is applied.
  Result := TyEmptyLayout(PaddedRect(AClient, S, APPI), img, txt, act, GapAtPPI(APPI));
end;

{ ---- public geometry ---- }

function TTyEmpty.ImageRect: TRect;
begin
  Result := LayoutAtPPI(ClientRect, Font.PixelsPerInch).ImageRect;
end;

function TTyEmpty.DescriptionRect: TRect;
begin
  Result := LayoutAtPPI(ClientRect, Font.PixelsPerInch).TextRect;
end;

function TTyEmpty.ActionRect: TRect;
begin
  // Delegate to AdjustClientRect itself: the action band has exactly ONE definition, so a
  // hand-placed child and an aligned one land in the same band by construction.
  Result := ClientRect;
  AdjustClientRect(Result);
end;

procedure TTyEmpty.CMEnabledChanged(var Msg: TLMessage);
begin
  inherited CMEnabledChanged(Msg);   // base repaints for the faded/disabled look
  // The action band (the child area) is inset by CurrentStyle padding, which a theme may
  // vary per state (e.g. TyEmpty:disabled). The paint follows the new padding on the base's
  // Invalidate, but an aligned/hand-placed action child only moves on Realign — without this
  // it drifts out of the band the moment the placeholder is disabled.
  if FShowAction then Realign;
end;

procedure TTyEmpty.AdjustClientRect(var ARect: TRect);
var
  lay: TTyEmptyLayout;
begin
  inherited AdjustClientRect(ARect);
  lay := LayoutAtPPI(ARect, Font.PixelsPerInch);
  if lay.ActionRect.Bottom > lay.ActionRect.Top then
    ARect := lay.ActionRect   // children live in the action band only — never on the picture
  else
    // No action band => no child area. Collapse it INSIDE the client rather than to
    // (0,0,0,0), which would park a child on the control's own corner instead of nowhere.
    ARect := Rect(ARect.Left, ARect.Bottom, ARect.Left, ARect.Bottom);
end;

procedure TTyEmpty.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, img, txt, act, tw, th: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  if FShowImage then img := ImageSizeAtPPI(ppi) else img := 0;
  if FShowAction then act := ActionHeightAtPPI(ppi) else act := 0;
  tw := 0;
  txt := 0;
  if FShowDescription then
  begin
    MeasureDescription(ppi, tw, th);
    txt := th;
  end;
  PreferredHeight := TyEmptyStackHeight(img, txt, act, GapAtPPI(ppi))
    + MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);
  // Width: whichever of the picture and the message is wider. The action band spans
  // whatever width it is given, so it asks for nothing of its own — and neither do the
  // CHILDREN in it: the band is a themed height, not a fit to its contents (see the doc).
  PreferredWidth := img;
  if tw > PreferredWidth then PreferredWidth := tw;
  Inc(PreferredWidth, MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96));
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

{ ---- painting ---- }

procedure TTyEmpty.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, imgS: TTyStyleSet;
  R: TRect;
  lay: TTyEmptyLayout;
  ink: TTyColor;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at
    // ARect.Left/Top, so a non-zero ARect origin would shift the stack.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    if not (tpBackground in S.Present) then
    begin
      P.EndPaint;   // no TyEmpty rule -> draw nothing at all; a theme that omits the key
      Exit;         // must degrade to a blank region, not crash or invent a look
    end;
    // The surface: background + border + radius + shadow + opacity, all from the resolved
    // style. Normally transparent — the placeholder lies ON the empty list's own surface.
    DrawFrame(P, R, S);

    lay := LayoutAtPPI(R, APPI);

    if lay.ImageRect.Bottom > lay.ImageRect.Top then
    begin
      { The picture's ink is its own typeKey, resolved with the placeholder's StyleClass
        (so TyEmptyImage.danger can tint the box of a danger placeholder) and with the
        placeholder's states (a disabled empty state fades whole). No TyEmptyImage colour
        => the message's own ink; never a hard-coded colour. }
      imgS := ActiveController.Model.ResolveStyle('TyEmptyImage', StyleClass, CurrentStates);
      if tpTextColor in imgS.Present then
        ink := imgS.TextColor
      else
        ink := S.TextColor;
      // v3/C5: the illustration is theme-overridable with an icon-font codepoint; the
      // built-in carton is only what a theme that sets no --glyph-empty falls back to.
      if not TyTryDrawGlyphOverride(P, ActiveController, lay.ImageRect, TyEmptyGlyphVar, ink) then
        TyDrawEmptyBox(P, lay.ImageRect, ink);
    end;

    if lay.TextRect.Right > lay.TextRect.Left then
      // Centred + ellipsised: a placeholder narrower than its message shows 'No d…', not
      // a glyph sheared at the clip edge. No mnemonic parsing — an empty state activates
      // nothing, so an '&' in the text is literal.
      P.DrawText(lay.TextRect, DisplayDescription, S.FontName, ResolveFontSize(S),
        S.FontWeight, S.TextColor, taCenter, tlCenter, True);

    // The action band is deliberately NOT painted: it is the child area, and its contents
    // are the user's own controls.
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyEmpty.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
