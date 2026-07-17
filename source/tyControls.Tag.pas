unit tyControls.Tag;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

const
  { Built-in logical-px defaults (96-PPI baseline) for the tag's own two metrics. A
    skin retunes them through the named theme metrics '--tag-close-size' / '--tag-gap'
    (the v3/C convention); these are only what a theme that sets neither falls back to.
    Both are scaled to device px at every call site. The slot matches TyTabCloseSize so
    a tag's x and a tab's x read as the same glyph at the same weight. }
  TyTagCloseSize = 14;   // close (x) slot, square
  TyTagGap       = 4;    // gap between the caption and the close slot

type
  { The geometry of a tag pill, in DEVICE pixels relative to the control rect's
    top-left. The caption is centred in CaptionRect (empty => nothing fits, so no text
    is drawn); CloseRect is the square close-glyph slot, vertically centred in the FULL
    height (empty when the tag is not closable). The slot is vertically centred in the
    whole height, not in the padded band, because a tag's vertical padding is typically
    0 and the slot is taller than its text. }
  TTyTagLayout = record
    CaptionRect: TRect;   // where the caption is drawn (empty => nothing drawn)
    CloseRect: TRect;     // the close-glyph slot (empty => no x)
  end;

{ Pure geometry for a tag pill. All inputs/outputs are DEVICE px.
    AClientWidth  — the control width, device px.
    AClientHeight — the control height, device px.
    AClosable     — reserve a close slot at the right of the content band.
    APadLeft      — themed left padding, device px (the content band's left edge).
    APadRight     — themed right padding, device px.
    AGap          — device-px gap between the caption and the close slot.
    ACloseSize    — close-slot edge length, device px.
  The close slot WINS the space: a pill too narrow for both keeps the x (it is the only
  affordance the tag has) and the caption collapses to empty. Padding that eats the
  whole pill leaves both rects empty rather than inverted.
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyTagLayout(AClientWidth, AClientHeight: Integer; AClosable: Boolean;
  APadLeft, APadRight, AGap, ACloseSize: Integer): TTyTagLayout;

{ The pill width that shows ATextWidth px of caption whole — the inverse of TyTagLayout:
  feed the result back in as AClientWidth (same other arguments) and CaptionRect comes
  out exactly ATextWidth wide. Device px throughout; this is what AutoSize measures to. }
function TyTagPreferredWidth(ATextWidth: Integer; AClosable: Boolean;
  APadLeft, APadRight, AGap, ACloseSize: Integer): Integer;

type
  { Fired before the tag acts on a click of its close (x) glyph. Clearing AllowClose
    vetoes the default action (hiding the tag) so a host that owns the tag's lifetime
    can free/relocate it itself. }
  TTyTagCloseEvent = procedure(Sender: TObject; var AllowClose: Boolean) of object;

  { A small pill: a caption on a themed rounded fill, with an optional close (x) glyph.
    Colour variants are plain StyleClass ('TyTag.success', 'TyTag.danger', …) — the
    control declares no variant enum of its own, so a theme may define as many as it
    likes without a code change.

    A GRAPHIC control (no handle) deliberately: tags come in crowds, they take no focus
    and no keys (the x is a mouse affordance), and painting straight onto the parent
    means the gaps outside the pill's rounded corners show the parent surface — or an
    image theme's photo — for free, with none of the corner-gap repair a windowed
    control needs.

    typeKey 'TyTag' for the pill; the x's chip + ink resolve from 'TyTagClose', whose
    :hover state is driven by the pointer being precisely over the GLYPH (not the pill),
    so the x lights up on its own. }
  TTyTag = class(TTyGraphicControl)
  private
    FClosable: Boolean;
    FHoverClose: Boolean;     // pointer is precisely over the x
    FClosePressed: Boolean;   // this press STARTED on the x (suppresses the tag's Click)
    FOnClose: TTyTagCloseEvent;
    procedure SetClosable(AValue: Boolean);
    { TTyGraphicControl has no ResolveFontSize helper (that lives on TTyCustomControl);
      mirror TTyLabel/TTyDivider and resolve it locally. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { TyTagLayout fed from the resolved theme: padding from the TyTag style, gap + slot
      size from the skin-tunable metrics. AWidth/AHeight are device px (RenderTo passes
      its own rect; the hit-test passes the client size), so nothing here reads Width
      behind the caller's back. }
    function LayoutFor(AWidth, AHeight, APPI: Integer): TTyTagLayout;
    function PtOnClose(X, Y: Integer): Boolean;
    { Caption extent in device px at APPI, measured in the theme's font. Height comes
      from a stable reference glyph ('Ag') so an empty caption still sizes to a line. }
    procedure MeasureCaption(APPI: Integer; out AWidthPx, AHeightPx: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { TControl.WMLButtonUp runs Click BEFORE DoMouseUp, so FClosePressed is still set
      here for a press that started on the x: that gesture is a close, never a tag
      click. MouseUp (which has the release position) then decides whether it committed. }
    procedure Click; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    { Caption changes at runtime route here (CM_TEXTCHANGED); with AutoSize the pill
      must re-measure to the new text (mirrors TTyLabel). }
    procedure TextChanged; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Act on the close gesture: ask OnClose, and unless it vetoes, hide the tag. Public
      so a host can drive it from a shortcut / context menu, and callable on a disabled
      tag (only the MOUSE path is gated on Enabled). }
    procedure Close;
    { The close-glyph slot in DEVICE px, (0,0)-local — the exact rect the paint fills and
      the hit-test measures against; empty when not Closable. Exposed for tests. }
    function TyTagCloseRect: TRect;
  published
    property Caption;
    { Shows the close (x) glyph and makes it live. Clicking it runs Close (OnClose, then
      hide unless vetoed); the pill's own OnClick never fires for that gesture. }
    property Closable: Boolean read FClosable write SetClosable default False;
    property OnClose: TTyTagCloseEvent read FOnClose write FOnClose;
    { With AutoSize the pill hugs its caption (plus padding, and the x slot when
      Closable); off, it keeps whatever bounds it was given and centres/ellipsises. }
    property AutoSize;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

implementation

function TyTagLayout(AClientWidth, AClientHeight: Integer; AClosable: Boolean;
  APadLeft, APadRight, AGap, ACloseSize: Integer): TTyTagLayout;
var
  contentL, contentR, closeL, closeT, closeB: Integer;
begin
  Result.CaptionRect := Rect(0, 0, 0, 0);
  Result.CloseRect := Rect(0, 0, 0, 0);
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  if APadLeft < 0 then APadLeft := 0;
  if APadRight < 0 then APadRight := 0;
  if AGap < 0 then AGap := 0;
  if ACloseSize < 0 then ACloseSize := 0;

  // The content band: the pill inset by its themed horizontal padding. Padding that
  // eats the whole pill leaves nothing to lay out (both rects stay empty).
  contentL := APadLeft;
  contentR := AClientWidth - APadRight;
  if contentR <= contentL then Exit;

  if AClosable and (ACloseSize > 0) then
  begin
    // The x hugs the right of the content band, vertically centred in the full height.
    closeL := contentR - ACloseSize;
    if closeL < contentL then closeL := contentL;   // too narrow: the x takes what there is
    closeT := (AClientHeight - ACloseSize) div 2;
    if closeT < 0 then closeT := 0;
    closeB := closeT + ACloseSize;
    if closeB > AClientHeight then closeB := AClientHeight;   // shorter than its slot: squash, don't overflow
    Result.CloseRect := Rect(closeL, closeT, contentR, closeB);
    contentR := closeL - AGap;   // the caption stops a gap short of the slot
  end;

  if contentR > contentL then
    Result.CaptionRect := Rect(contentL, 0, contentR, AClientHeight);
end;

function TyTagPreferredWidth(ATextWidth: Integer; AClosable: Boolean;
  APadLeft, APadRight, AGap, ACloseSize: Integer): Integer;
begin
  if ATextWidth < 0 then ATextWidth := 0;
  if APadLeft < 0 then APadLeft := 0;
  if APadRight < 0 then APadRight := 0;
  Result := APadLeft + ATextWidth + APadRight;
  if AClosable and (ACloseSize > 0) then
  begin
    if AGap < 0 then AGap := 0;
    Inc(Result, AGap + ACloseSize);
  end;
end;

{ TTyTag }

constructor TTyTag.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FClosable := False;
  FHoverClose := False;
  FClosePressed := False;
  Width := 72;
  Height := 22;
end;

function TTyTag.GetStyleTypeKey: string;
begin
  Result := 'TyTag';
end;

function TTyTag.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

procedure TTyTag.SetClosable(AValue: Boolean);
begin
  if FClosable = AValue then Exit;
  FClosable := AValue;
  if not FClosable then
  begin
    // Drop any live x state, or a tag that loses its glyph keeps a stale hover chip /
    // a press that would still close it on release.
    FHoverClose := False;
    FClosePressed := False;
  end;
  // The slot changes the width the caption needs, so an auto-sized pill must re-fit.
  if AutoSize then
    InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TTyTag.Close;
var
  allow: Boolean;
begin
  allow := True;
  if Assigned(FOnClose) then FOnClose(Self, allow);
  // Default action = hide, so the x is a live affordance even with no handler. A host
  // that owns the tag's lifetime clears AllowClose and frees/removes it itself.
  if allow then Visible := False;
end;

function TTyTag.LayoutFor(AWidth, AHeight, APPI: Integer): TTyTagLayout;
var
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := CurrentStyle;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies,
  // so the rects the hit-test measures are the rects the paint drew.
  Result := TyTagLayout(AWidth, AHeight, FClosable,
    MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Right, APPI, 96),
    MulDiv(ActiveController.Metric('--tag-gap', TyTagGap), APPI, 96),
    MulDiv(ActiveController.Metric('--tag-close-size', TyTagCloseSize), APPI, 96));
end;

function TTyTag.TyTagCloseRect: TRect;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch).CloseRect;
end;

function TTyTag.PtOnClose(X, Y: Integer): Boolean;
var
  R: TRect;
begin
  R := TyTagCloseRect;
  Result := (R.Right > R.Left) and (X >= R.Left) and (X < R.Right)
    and (Y >= R.Top) and (Y < R.Bottom);
end;

procedure TTyTag.MeasureCaption(APPI: Integer; out AWidthPx, AHeightPx: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
begin
  S := CurrentStyle;
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    if S.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    AWidthPx := Meas.Canvas.TextWidth(Caption);
    // A stable reference glyph: an empty caption still sizes the pill to one line.
    AHeightPx := Meas.Canvas.TextHeight('Ag');
    if AWidthPx < 0 then AWidthPx := 0;
    if AHeightPx < 1 then AHeightPx := 1;
  finally
    Meas.Free;
  end;
end;

procedure TTyTag.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, tw, th, closeSz: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  MeasureCaption(ppi, tw, th);
  closeSz := MulDiv(ActiveController.Metric('--tag-close-size', TyTagCloseSize), ppi, 96);
  PreferredWidth := TyTagPreferredWidth(tw, FClosable,
    MulDiv(S.Padding.Left, ppi, 96), MulDiv(S.Padding.Right, ppi, 96),
    MulDiv(ActiveController.Metric('--tag-gap', TyTagGap), ppi, 96), closeSz);
  PreferredHeight := th + MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);
  // A closable pill must clear its x slot or TyTagLayout squashes the glyph: tags are
  // typically padded 0px vertically, so the caption line alone is shorter than the slot.
  if FClosable and (PreferredHeight < closeSz) then
    PreferredHeight := closeSz;
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

procedure TTyTag.TextChanged;
begin
  inherited TextChanged;
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyTag.Click;
begin
  // See the declaration: Click runs BEFORE MouseUp, so a still-set FClosePressed means
  // this press started on the x — the close gesture owns it, the pill's OnClick does not
  // fire. The flag is consumed in MouseUp, which knows where the release landed.
  if FClosePressed then Exit;
  inherited Click;
end;

procedure TTyTag.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FClosePressed := FClosable and PtOnClose(X, Y);
  if FClosePressed then
  begin
    // The gesture belongs to the x, not the pill: undo the base's press state so the
    // whole tag doesn't flip to :active behind the glyph.
    FPressed := False;
    Invalidate;
  end;
end;

procedure TTyTag.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  wasClose: Boolean;
begin
  wasClose := FClosePressed;
  FClosePressed := False;
  inherited MouseUp(Button, Shift, X, Y);
  // Press AND release both on the x commit the close; dragging off it cancels the whole
  // gesture (no OnClose, and Click already swallowed the OnClick) like any push button.
  if (Button = mbLeft) and wasClose and PtOnClose(X, Y) then
    Close;
end;

procedure TTyTag.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  h: Boolean;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  h := FClosable and PtOnClose(X, Y);
  if FHoverClose <> h then
  begin
    FHoverClose := h;
    Invalidate;
  end;
end;

procedure TTyTag.MouseLeave;
begin
  inherited MouseLeave;   // clears the pill's own hover
  if FHoverClose then
  begin
    FHoverClose := False;
    Invalidate;
  end;
end;

procedure TTyTag.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, closeS: TTyStyleSet;
  R: TRect;
  Lay: TTyTagLayout;
  closeStates: TTyStateSet;
  glyphColor: TTyColor;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at
    // ARect.Left/Top, so a non-zero ARect origin would shift the pill.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The pill itself: background + border + shadow + opacity, all from the resolved
    // TyTag style. FillBackground clamps an oversized radius (var(--radius-round)) to
    // half the shorter side, so the pill shape is the theme's call, not this code's.
    DrawFrame(P, R, S);

    Lay := LayoutFor(R.Right - R.Left, R.Bottom - R.Top, APPI);

    // The x's chip and ink are their own typeKey, resolved with the TAG's StyleClass (so
    // TyTagClose.danger can tint the x of a danger tag) and with the state of the GLYPH,
    // not the pill — hovering precisely the x is what lights TyTagClose:hover.
    closeStates := [];
    if not Enabled then
      Include(closeStates, tysDisabled)
    else if FHoverClose then
      Include(closeStates, tysHover)
    else
      Include(closeStates, tysNormal);
    closeS := ActiveController.Model.ResolveStyle('TyTagClose', StyleClass, closeStates);
    // No TyTagClose colour -> the x is the pill's own ink; never a hard-coded colour.
    if tpTextColor in closeS.Present then
      glyphColor := closeS.TextColor
    else
      glyphColor := S.TextColor;

    if Lay.CaptionRect.Right > Lay.CaptionRect.Left then
      // Centred + ellipsised: a pill narrower than its caption shows 'Ta…', not a glyph
      // sheared at the clip edge. No mnemonic parsing — a tag activates nothing, so an
      // '&' in a caption is literal text.
      P.DrawText(Lay.CaptionRect, Caption, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, taCenter, tlCenter, True);

    if Lay.CloseRect.Right > Lay.CloseRect.Left then
    begin
      // An undefined TyTagClose key leaves no background -> no chip, and the glyph still
      // draws in the pill's ink. A theme that sets the fill only under :hover gets the
      // usual "chip appears under the pointer" for free.
      if tpBackground in closeS.Present then
        P.FillBackground(Lay.CloseRect, closeS.Background, TyEffectiveCorners(closeS));
      // v3/C5: the x is theme-overridable with an icon-font codepoint (--glyph-close).
      TyDrawGlyph(P, ActiveController, Lay.CloseRect, tgClose, glyphColor, 1);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTag.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
