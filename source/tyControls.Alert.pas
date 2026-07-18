unit tyControls.Alert;
{$mode objfpc}{$H+}
{ TTyAlert — an INLINE alert banner: a themed bar that sits IN the page and says
  something, with a semantic status icon, an optional second line, and an optional
  close (x) glyph.

  The gap it fills: every other notice in this library is a MODAL dialog (TTyMessage
  and friends). "A bar in the form that says the connection dropped" had no semantic
  at all — it was a hand-tinted TTyPanel + TTyLabel per site, i.e. hard-coded colour.

  A GRAPHIC control (no handle), like TTyTag: an alert hosts no child controls, takes
  no focus and no keys (the x is a mouse affordance), so painting straight onto the
  parent gets the corner gaps outside its rounded frame — the parent surface, or an
  image theme's photo — for free, with none of the corner-gap repair a windowed control
  needs.

  typeKey 'TyAlert' for the bar; the x's chip + ink resolve from 'TyAlertClose' on the
  same contract as TyTagClose. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

const
  { Built-in logical-px defaults (96-PPI baseline) for the banner's five metrics. A skin
    retunes each through its named theme metric (the v3/C convention); these are only what
    a theme that sets none falls back to. Every call site scales them to device px.
    The close slot matches TyTagCloseSize (and through it TyTabCloseSize) so an alert's x,
    a tag's x and a tab's x read as the same glyph at the same weight. }
  TyAlertIconSize  = 16;   // status-icon slot, square
  TyAlertIconGap   = 8;    // gap between the icon slot and the text column
  TyAlertTextGap   = 2;    // vertical gap between the message line and the description line
  TyAlertCloseGap  = 8;    // gap between the text column and the close slot
  TyAlertCloseSize = 14;   // close (x) slot, square

  { The metric token each constant backs. Named constants rather than inline literals
    because three call sites (LayoutWith, CalculatePreferredSize, the tests) must agree
    on the spelling — a typo in one would silently fall back to the default and the
    geometry would drift from the measurement. }
  TyAlertIconSizeVar  = '--alert-icon-size';
  TyAlertIconGapVar   = '--alert-icon-gap';
  TyAlertTextGapVar   = '--alert-text-gap';
  TyAlertCloseGapVar  = '--alert-close-gap';
  TyAlertCloseSizeVar = '--alert-close-size';

type
  { The banner's semantic type. A published ENUM here, against the house rule that colour
    variants are plain StyleClass, because the type also chooses the ICON the control has
    to DRAW — so unlike a tag's colour, the control genuinely must know it. Precedent:
    TTyMessage.DlgType (a published TMsgDlgType that picks the glyph). TMsgDlgType itself
    is deliberately NOT reused: it has no 'success', which is half the point of an alert. }
  TTyAlertType = (atInfo, atSuccess, atWarning, atError);

  { The geometry of an alert banner, in DEVICE pixels relative to the control rect's
    top-left. Every rect is empty when the thing it holds is off or does not fit:
      IconRect        — the square status-glyph slot (empty when ShowIcon is off)
      MessageRect     — the headline's line band (the painter centres the text in it)
      DescriptionRect — the second line's band (empty when there is no description)
      CloseRect       — the square close-glyph slot (empty when not closable) }
  TTyAlertLayout = record
    IconRect: TRect;
    MessageRect: TRect;
    DescriptionRect: TRect;
    CloseRect: TRect;
  end;

{ The style VARIANT name an alert type resolves as — so a theme writes a `TyAlert.warning`
  rule, exactly the shape `TyTag.accent` already has, and the control needs no colour
  vocabulary of its own beyond the four names it must know anyway (it draws their icons). }
function TyAlertVariant(AType: TTyAlertType): string;

{ The status glyph an alert type draws. The four kinds are the painter's own semantic
  marks, each with a '--glyph-info/-success/-warning/-error' icon-font override token. }
function TyAlertGlyph(AType: TTyAlertType): TTyGlyphKind;

{ Pure geometry for an alert banner. All inputs/outputs are DEVICE px.
    AClientWidth/AClientHeight — the control size.
    AShowIcon                  — reserve the status-icon slot at the left of the band.
    AHasDescription            — lay out the taller two-line form.
    AClosable                  — reserve a close slot at the right of the band.
    APadLeft/Top/Right/Bottom  — themed padding (the content band's insets).
    AMessageHeight             — measured line height of the headline.
    ADescriptionHeight         — measured line height of the second line. Taken separately
                                 from AMessageHeight even though today's control feeds the
                                 same number twice (both lines share the one TyAlert font):
                                 the RULE is "each line gets its own measured height", and
                                 baking "they are equal" in here would have to be unpicked
                                 the day the description earns a typeKey of its own.
    AIconSize/AIconGap         — icon slot edge and the gap after it.
    ATextGap                   — vertical gap between the two lines.
    ACloseGap/ACloseSize       — the gap before the close slot and its edge.

  Vertical: the text block (message, + gap + description when present) is centred in the
  padded band, and BOTH slots centre on the MESSAGE line — one rule that gives the
  familiar centred look in the one-line form and puts the icon and the x beside the
  HEADLINE in the two-line form, rather than stranding them between the lines.

  Horizontal, when space runs out, in priority order: the close slot wins first (it is the
  banner's only affordance — TyTagLayout's rule), the icon next (it is what says WHAT kind
  of notice this is), and the text column takes the remainder, collapsing to empty rather
  than showing a sliver. Padding that eats the whole banner, or a zero size, leaves every
  rect empty rather than inverted.
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer): TTyAlertLayout;

{ The banner height that shows its content whole — the inverse of TyAlertLayout: feed the
  result back in as AClientHeight (same other arguments) and the text block lands exactly
  on the padding, with both slots unsquashed. Device px throughout; this is what AutoSize
  measures to.
  It takes no WIDTH because the banner's height does not depend on one: neither line
  wraps (both are single-line and ellipsised, like every other text in this library), so
  a narrower banner shows less text at the same height rather than reflowing to a taller
  block. }
function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize: Integer): Integer;

type
  { Fired before the banner acts on a click of its close (x) glyph. Clearing AllowClose
    vetoes the default action (hiding the banner) so a host that owns the alert's lifetime
    can free/relocate it itself. Identical in shape and meaning to TTyTagCloseEvent — the
    two are separate types only so neither unit has to use the other. }
  TTyAlertCloseEvent = procedure(Sender: TObject; var AllowClose: Boolean) of object;

  TTyAlert = class(TTyGraphicControl)
  private
    FAlertType: TTyAlertType;
    FMessage: string;
    FDescription: string;
    FShowIcon: Boolean;
    FClosable: Boolean;
    FHoverClose: Boolean;     // pointer is precisely over the x
    FClosePressed: Boolean;   // this press STARTED on the x (suppresses the banner's Click)
    FOnClose: TTyAlertCloseEvent;
    { StyleOverride overlay cache. A second copy of the base class's (whose fields are
      private) — see AlertStyle for why this control cannot use inherited CurrentStyle. }
    FOvrSet: TTyStyleSet;
    FOvrText: string;
    FOvrVer: Cardinal;
    FOvrValid: Boolean;
    procedure SetAlertType(AValue: TTyAlertType);
    procedure SetMessage(const AValue: string);
    procedure SetDescription(const AValue: string);
    procedure SetShowIcon(AValue: Boolean);
    procedure SetClosable(AValue: Boolean);
    { TTyGraphicControl has no ResolveFontSize helper (that lives on TTyCustomControl);
      mirror TTyLabel/TTyTag and resolve it locally. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { One text line's height in DEVICE px, from a stable reference glyph ('Ag') so an
      empty Message still sizes the banner to a line and the two lines cannot disagree.
      Measured with the PAINTER (not a TBitmap canvas): the banner's text is drawn with
      BGRA metrics, and only the same measurer reproduces the height those glyphs render
      at — the rects fed to the geometry are the rects the paint fills. }
    function LineHeightWith(APainter: TTyPainter; const AStyle: TTyStyleSet): Integer;
    function LineHeightAtPPI(APPI: Integer; const AStyle: TTyStyleSet): Integer;
    function LayoutWith(APainter: TTyPainter; const AStyle: TTyStyleSet;
      AWidth, AHeight: Integer): TTyAlertLayout;
    function PtOnClose(X, Y: Integer): Boolean;
    { AutoSize re-fit + repaint, for every change that can move the measured height. }
    procedure Refit;
  protected
    function GetStyleTypeKey: string; override;
    { The resolved TyAlert style for the CURRENT type, class and state. }
    function AlertStyle: TTyStyleSet;
    { TyAlertLayout fed from the resolved theme. AWidth/AHeight are device px (RenderTo
      passes its own rect; the hit-test passes the client size), so nothing here reads
      Width behind the caller's back. }
    function LayoutFor(AWidth, AHeight, APPI: Integer): TTyAlertLayout;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { TControl.WMLButtonUp runs Click BEFORE DoMouseUp, so FClosePressed is still set here
      for a press that started on the x: that gesture is a close, never a banner click.
      MouseUp (which has the release position) then decides whether it committed. }
    procedure Click; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Act on the close gesture: ask OnClose, and unless it vetoes, hide the banner. Public
      so a host can drive it from a shortcut / a timer, and callable on a disabled alert
      (only the MOUSE path is gated on Enabled). }
    procedure Close;
    { True when Description is set — i.e. the banner is in its two-line form. }
    function HasDescription: Boolean;
    { The variant tokens this banner resolves with: the type's own name, then the user's
      StyleClass. See the comment on the StyleClass property. }
    function StyleVariant: string;
    { The close-glyph slot in DEVICE px, (0,0)-local — the exact rect the paint fills and
      the hit-test measures against; empty when not Closable. Exposed for tests. }
    function TyAlertCloseRect: TRect;
    { The status-icon slot in DEVICE px, (0,0)-local; empty when ShowIcon is off. }
    function TyAlertIconRect: TRect;
  published
    { The banner's semantic type: it picks BOTH the style variant ('info' / 'success' /
      'warning' / 'error' — the theme writes a `TyAlert.warning` rule) and the status
      glyph. Changing it re-fits an auto-sized banner, because a theme may pad a variant
      differently. }
    property AlertType: TTyAlertType read FAlertType write SetAlertType default atInfo;
    { The headline. Drawn with the resolved TyAlert style (NOT the LCL Font.*), left
      aligned, ellipsised when it does not fit, and never wrapped. No mnemonic parsing —
      a banner activates nothing, so an '&' is literal text. }
    property Message: string read FMessage write SetMessage;
    { The optional second line. Setting it switches the banner to the taller two-line
      form; clearing it goes back to one line. Same drawing rules as Message. }
    property Description: string read FDescription write SetDescription;
    { Draw the type's status glyph in a slot at the left. On by default: the icon is what
      makes an alert readable at a glance, and it is the one thing AlertType exists for
      beyond colour. }
    property ShowIcon: Boolean read FShowIcon write SetShowIcon default True;
    { Shows the close (x) glyph and makes it live. Clicking it runs Close (OnClose, then
      hide unless vetoed); the banner's own OnClick never fires for that gesture. }
    property Closable: Boolean read FClosable write SetClosable default False;
    property OnClose: TTyAlertCloseEvent read FOnClose write FOnClose;
    { With AutoSize the banner's HEIGHT hugs its content (padding + one or two lines, at
      least as tall as its slots). The WIDTH is left alone — a banner spans its host via
      Align/Anchors, and re-fitting it to its text would fight that layout. }
    property AutoSize;
    property Align;
    property Anchors;
    property Enabled;
    property Font;
    { An EXTRA variant on top of the type's own. AlertType always contributes its variant
      token first and this one is appended, so the semantic look is always there and an
      explicit class layers over it per-property — the engine's ordinary multi-token
      cascade (later token wins). A theme rule `TyAlert.compact` setting only a tighter
      padding thus trims any type of banner without touching its colours. }
    property StyleClass;
    property StyleOverride;
    property Controller;
    property OnClick;
  end;

implementation

{ --- pure rules / geometry ---------------------------------------------------- }

function TyAlertVariant(AType: TTyAlertType): string;
begin
  case AType of
    atSuccess: Result := 'success';
    atWarning: Result := 'warning';
    atError:   Result := 'error';
  else
    // atInfo, and any value a future enum extension forgets: info is the neutral notice.
    Result := 'info';
  end;
end;

function TyAlertGlyph(AType: TTyAlertType): TTyGlyphKind;
begin
  case AType of
    atSuccess: Result := tgSuccess;
    atWarning: Result := tgWarning;
    atError:   Result := tgError;
  else
    Result := tgInfo;
  end;
end;

{ The vertical band an ASize-tall square slot occupies when centred on ACentreY in a
  banner AHeight tall: floored at the top edge and squashed at the bottom rather than
  overflowing (TyTagLayout's rule for its own close slot). False = no band left at all. }
function AlertSlotBand(ACentreY, ASize, AHeight: Integer; out ATop, ABottom: Integer): Boolean;
begin
  ATop := ACentreY - ASize div 2;
  if ATop < 0 then ATop := 0;
  if ATop > AHeight then ATop := AHeight;
  ABottom := ATop + ASize;
  if ABottom > AHeight then ABottom := AHeight;
  Result := ABottom > ATop;
end;

function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer): TTyAlertLayout;
var
  bandL, bandR, textL, textR: Integer;
  availH, blockH, blockT, centreY: Integer;
  closeL, iconR, slotT, slotB: Integer;
begin
  Result.IconRect := Rect(0, 0, 0, 0);
  Result.MessageRect := Rect(0, 0, 0, 0);
  Result.DescriptionRect := Rect(0, 0, 0, 0);
  Result.CloseRect := Rect(0, 0, 0, 0);
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  // Clamp every negative input once, here, so the arithmetic below can be read straight.
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;
  if AMessageHeight < 0 then AMessageHeight := 0;
  if ADescriptionHeight < 0 then ADescriptionHeight := 0;
  if AIconSize < 0 then AIconSize := 0;
  if AIconGap < 0 then AIconGap := 0;
  if ATextGap < 0 then ATextGap := 0;
  if ACloseGap < 0 then ACloseGap := 0;
  if ACloseSize < 0 then ACloseSize := 0;

  // The content band: the banner inset by its themed horizontal padding. Padding that
  // eats the whole banner leaves nothing to lay out (every rect stays empty).
  bandL := APadLeft;
  bandR := AClientWidth - APadRight;
  if bandR <= bandL then Exit;

  // --- vertical: the text block, centred in the padded band -------------------
  blockH := AMessageHeight;
  if AHasDescription then Inc(blockH, ATextGap + ADescriptionHeight);
  availH := AClientHeight - APadTop - APadBottom;
  if availH < 0 then availH := 0;
  blockT := APadTop + (availH - blockH) div 2;
  if blockT < 0 then blockT := 0;   // a block taller than its band starts at the top edge
  // Both slots centre on the MESSAGE line: in the one-line form that IS the banner's
  // optical centre, and in the two-line form it puts them beside the headline.
  centreY := blockT + AMessageHeight div 2;

  // --- horizontal: the close slot is served first ------------------------------
  textL := bandL;
  textR := bandR;
  if AClosable and (ACloseSize > 0) then
  begin
    // The x hugs the right of the content band.
    closeL := bandR - ACloseSize;
    if closeL < bandL then closeL := bandL;   // too narrow: the x takes what there is
    if AlertSlotBand(centreY, ACloseSize, AClientHeight, slotT, slotB) then
      Result.CloseRect := Rect(closeL, slotT, bandR, slotB);
    textR := closeL - ACloseGap;   // the text stops a gap short of the slot
  end;

  // --- then the icon, out of what the close slot left --------------------------
  if AShowIcon and (AIconSize > 0) and (textR > textL) then
  begin
    iconR := textL + AIconSize;
    if iconR > textR then iconR := textR;     // no room for a whole slot: take what there is
    if AlertSlotBand(centreY, AIconSize, AClientHeight, slotT, slotB) then
      Result.IconRect := Rect(textL, slotT, iconR, slotB);
    textL := iconR + AIconGap;
  end;

  // --- the text column takes the remainder -------------------------------------
  if textR <= textL then Exit;   // nothing left: the lines collapse rather than show a sliver
  if AMessageHeight > 0 then
    Result.MessageRect := Rect(textL, blockT, textR, blockT + AMessageHeight);
  if AHasDescription and (ADescriptionHeight > 0) then
    Result.DescriptionRect := Rect(textL, blockT + AMessageHeight + ATextGap,
      textR, blockT + blockH);
end;

function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize: Integer): Integer;
var
  blockH: Integer;
begin
  if APadTop < 0 then APadTop := 0;
  if APadBottom < 0 then APadBottom := 0;
  if AMessageHeight < 0 then AMessageHeight := 0;
  if ADescriptionHeight < 0 then ADescriptionHeight := 0;
  if ATextGap < 0 then ATextGap := 0;
  blockH := AMessageHeight;
  if AHasDescription then Inc(blockH, ATextGap + ADescriptionHeight);
  Result := APadTop + blockH + APadBottom;
  // Both slots are centred in the FULL height, not in the padded band, so a banner
  // shorter than a slot would have TyAlertLayout squash that glyph. Clear the tallest —
  // the bare slot, not slot+padding, exactly as TTyTag floors its own height.
  if AShowIcon and (AIconSize > Result) then Result := AIconSize;
  if AClosable and (ACloseSize > Result) then Result := ACloseSize;
  if Result < 1 then Result := 1;
end;

{ --- TTyAlert ----------------------------------------------------------------- }

constructor TTyAlert.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlertType := atInfo;
  FShowIcon := True;
  FClosable := False;
  FHoverClose := False;
  FClosePressed := False;
  // A drop size for the designer: wide enough to read as a banner, one line tall.
  Width := 320;
  Height := 40;
end;

function TTyAlert.GetStyleTypeKey: string;
begin
  Result := 'TyAlert';
end;

function TTyAlert.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

function TTyAlert.HasDescription: Boolean;
begin
  Result := FDescription <> '';
end;

function TTyAlert.StyleVariant: string;
begin
  // The TYPE contributes its variant token FIRST and the user's StyleClass follows it.
  // ResolveLayer applies variant tokens in textual order, so the semantic look is always
  // applied and an explicit class layers over it per-property — the same cascade any
  // multi-token StyleClass already gets. The type therefore always wins the SEMANTICS
  // (it can never be silently dropped) without making StyleClass a dead property.
  Result := TyAlertVariant(FAlertType);
  if Trim(StyleClass) <> '' then
    Result := Result + ' ' + Trim(StyleClass);
end;

function TTyAlert.AlertStyle: TTyStyleSet;
var
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  // NOT inherited CurrentStyle: that resolves with StyleClass ALONE, and it cannot know
  // about AlertType — the whole point here is that the type contributes a variant token.
  Result := model.ResolveStyle(GetStyleTypeKey, StyleVariant, CurrentStates);
  // Resolving for ourselves means re-applying the StyleOverride layer the base would
  // otherwise have added, with the same staleness rule (the text changed, or the theme
  // version bumped so var(--...) must re-bind). The base's cache fields are private,
  // hence this second copy rather than a call into it.
  if StyleOverride <> '' then
  begin
    if (not FOvrValid) or (FOvrText <> StyleOverride) or (FOvrVer <> model.ThemeVersion) then
    begin
      FOvrSet := model.ResolveOverride(StyleOverride);
      FOvrText := StyleOverride;
      FOvrVer := model.ThemeVersion;
      FOvrValid := True;
    end;
    TyMergeStyleSet(Result, FOvrSet);   // the override wins per Present flag
  end;
end;

{ --- property setters --------------------------------------------------------- }

procedure TTyAlert.Refit;
begin
  // Every visual value here is theme-derived, so a change that can move the measured
  // height (a variant with different padding, a second line, a slot appearing) must
  // re-fit an auto-sized banner, not merely repaint it.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyAlert.SetAlertType(AValue: TTyAlertType);
begin
  if FAlertType = AValue then Exit;
  FAlertType := AValue;
  // More than a repaint: the variant is a different theme rule, which may pad or size
  // its text differently.
  Refit;
end;

procedure TTyAlert.SetMessage(const AValue: string);
begin
  if FMessage = AValue then Exit;
  FMessage := AValue;
  // Height comes from a reference glyph, not from this text, and the width is never
  // measured — so new headline text is a pure repaint.
  Invalidate;
end;

procedure TTyAlert.SetDescription(const AValue: string);
begin
  if FDescription = AValue then Exit;
  // '' <-> text is the one-line/two-line switch: a height change, not a repaint.
  FDescription := AValue;
  Refit;
end;

procedure TTyAlert.SetShowIcon(AValue: Boolean);
begin
  if FShowIcon = AValue then Exit;
  FShowIcon := AValue;
  Refit;   // the icon slot is a height floor as well as a left inset
end;

procedure TTyAlert.SetClosable(AValue: Boolean);
begin
  if FClosable = AValue then Exit;
  FClosable := AValue;
  if not FClosable then
  begin
    // Drop any live x state, or a banner that loses its glyph keeps a stale hover chip /
    // a press that would still close it on release.
    FHoverClose := False;
    FClosePressed := False;
  end;
  Refit;
end;

{ --- actions ------------------------------------------------------------------ }

procedure TTyAlert.Close;
var
  allow: Boolean;
begin
  allow := True;
  if Assigned(FOnClose) then FOnClose(Self, allow);
  // Default action = hide, so the x is a live affordance even with no handler (TTyTag's
  // rule). A host that owns the banner's lifetime clears AllowClose and frees/removes it.
  if allow then Visible := False;
end;

{ --- measurement + geometry --------------------------------------------------- }

function TTyAlert.LineHeightWith(APainter: TTyPainter; const AStyle: TTyStyleSet): Integer;
begin
  // A stable reference glyph: an empty Message still sizes the banner to a line.
  Result := APainter.MeasureText('Ag', AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight).cy;
  if Result < 1 then Result := 1;
end;

function TTyAlert.LineHeightAtPPI(APPI: Integer; const AStyle: TTyStyleSet): Integer;
{ A CANVAS-LESS painter — the tyControls.Form / TTyBadge idiom: BeginPaint(nil, ...) builds
  only the painter's internal bitmap and EndPaint frees it WITHOUT blitting, so this is safe
  outside a paint cycle and leaks nothing. }
var
  P: TTyPainter;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    Result := LineHeightWith(P, AStyle);
    P.EndPaint;   // nil canvas -> no blit, just frees the measure bitmap
  finally
    P.Free;
  end;
end;

function TTyAlert.LayoutWith(APainter: TTyPainter; const AStyle: TTyStyleSet;
  AWidth, AHeight: Integer): TTyAlertLayout;
var
  lineH: Integer;
begin
  lineH := LineHeightWith(APainter, AStyle);
  // APainter.Scale is the same logical->device conversion the painter applies to every
  // themed value it draws, so the rects the hit-test measures are the rects the paint drew.
  Result := TyAlertLayout(AWidth, AHeight, FShowIcon, HasDescription, FClosable,
    APainter.Scale(AStyle.Padding.Left), APainter.Scale(AStyle.Padding.Top),
    APainter.Scale(AStyle.Padding.Right), APainter.Scale(AStyle.Padding.Bottom),
    lineH, lineH,
    APainter.Scale(ActiveController.Metric(TyAlertIconSizeVar, TyAlertIconSize)),
    APainter.Scale(ActiveController.Metric(TyAlertIconGapVar, TyAlertIconGap)),
    APainter.Scale(ActiveController.Metric(TyAlertTextGapVar, TyAlertTextGap)),
    APainter.Scale(ActiveController.Metric(TyAlertCloseGapVar, TyAlertCloseGap)),
    APainter.Scale(ActiveController.Metric(TyAlertCloseSizeVar, TyAlertCloseSize)));
end;

function TTyAlert.LayoutFor(AWidth, AHeight, APPI: Integer): TTyAlertLayout;
var
  P: TTyPainter;
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := AlertStyle;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);
    Result := LayoutWith(P, S, AWidth, AHeight);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

function TTyAlert.TyAlertCloseRect: TRect;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch).CloseRect;
end;

function TTyAlert.TyAlertIconRect: TRect;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch).IconRect;
end;

function TTyAlert.PtOnClose(X, Y: Integer): Boolean;
var
  R: TRect;
begin
  // Guarded by the caller's `FClosable and ...` short-circuit, so a non-closable banner
  // never pays for the layout's text measure on a mouse move.
  R := TyAlertCloseRect;
  Result := (R.Right > R.Left) and (X >= R.Left) and (X < R.Right)
    and (Y >= R.Top) and (Y < R.Bottom);
end;

procedure TTyAlert.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, lineH: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := AlertStyle;
  lineH := LineHeightAtPPI(ppi, S);
  // 0 = "no preferred width" (the LCL convention: keep the bounds you were given).
  // AutoSize hugs the HEIGHT only — a banner spans its host via Align/Anchors.
  PreferredWidth := 0;
  PreferredHeight := TyAlertPreferredHeight(FShowIcon, HasDescription, FClosable,
    MulDiv(S.Padding.Top, ppi, 96), MulDiv(S.Padding.Bottom, ppi, 96),
    lineH, lineH,
    MulDiv(ActiveController.Metric(TyAlertTextGapVar, TyAlertTextGap), ppi, 96),
    MulDiv(ActiveController.Metric(TyAlertIconSizeVar, TyAlertIconSize), ppi, 96),
    MulDiv(ActiveController.Metric(TyAlertCloseSizeVar, TyAlertCloseSize), ppi, 96));
end;

{ --- input -------------------------------------------------------------------- }

procedure TTyAlert.Click;
begin
  // A banner that drew nothing (no themed background) must not fire OnClick either: the input
  // has to honour the paint's "no banner at all" decision, or a click on apparent blank space
  // fires OnClick for a control the user cannot see.
  if not (tpBackground in AlertStyle.Present) then Exit;
  // See the declaration: Click runs BEFORE MouseUp, so a still-set FClosePressed means
  // this press started on the x — the close gesture owns it, the banner's OnClick does
  // not fire. The flag is consumed in MouseUp, which knows where the release landed.
  if FClosePressed then Exit;
  inherited Click;
end;

procedure TTyAlert.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  closeHit: Boolean;
begin
  if not Enabled then Exit;
  // A background-less (theme-degraded) alert paints NOTHING — the input must agree it is not
  // there, or it swallows clicks and (over the invisible x's slot) can even hide itself.
  if not (tpBackground in AlertStyle.Present) then Exit;
  // Hit-test the close x on the RESTING geometry, BEFORE inherited MouseDown sets FPressed:
  // FPressed makes AlertStyle resolve the :active variant, whose padding can move the close
  // rect off the painted (resting) x, so a press squarely on the visible x reads as a body
  // press — the opposite of closing.
  closeHit := (Button = mbLeft) and FClosable and PtOnClose(X, Y);
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FClosePressed := closeHit;
  if FClosePressed then
  begin
    // The gesture belongs to the x, not the banner: undo the base's press state so the
    // whole bar doesn't flip to :active behind the glyph.
    FPressed := False;
    Invalidate;
  end;
end;

procedure TTyAlert.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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

procedure TTyAlert.MouseMove(Shift: TShiftState; X, Y: Integer);
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

procedure TTyAlert.MouseLeave;
begin
  inherited MouseLeave;   // clears the bar's own hover
  if FHoverClose then
  begin
    FHoverClose := False;
    Invalidate;
  end;
end;

{ --- painting ----------------------------------------------------------------- }

procedure TTyAlert.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, closeS: TTyStyleSet;
  R: TRect;
  Lay: TTyAlertLayout;
  fs: Integer;
  closeStates: TTyStateSet;
  glyphColor: TTyColor;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at
    // ARect.Left/Top, so a non-zero ARect origin would shift the banner.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := AlertStyle;
    if not (tpBackground in S.Present) then
    begin
      // A theme that does not define TyAlert (or this variant of it) gets no banner at
      // all rather than a hard-coded one. Degrade, never crash, never invent a colour.
      P.EndPaint;
      Exit;
    end;
    // The bar itself: background + border + shadow + opacity, all from the resolved style.
    DrawFrame(P, R, S);

    Lay := LayoutWith(P, S, R.Right - R.Left, R.Bottom - R.Top);
    fs := ResolveFontSize(S);

    // The status glyph takes the BAR's ink: with only two typeKeys the icon is part of
    // the banner's text colour, so `TyAlert.warning { color: var(--warning); }` tints the
    // mark and the words together (the Bootstrap-style tinted banner). A theme that sets
    // no `color` therefore draws no icon and no text — the same degradation, one rule.
    if Lay.IconRect.Right > Lay.IconRect.Left then
      TyDrawGlyph(P, ActiveController, Lay.IconRect, TyAlertGlyph(FAlertType), S.TextColor, 1);

    // Left-aligned + ellipsised: a banner narrower than its headline shows 'Connect…',
    // not a glyph sheared at the clip edge. No mnemonic parsing (see the property).
    if Lay.MessageRect.Right > Lay.MessageRect.Left then
      P.DrawText(Lay.MessageRect, FMessage, S.FontName, fs, S.FontWeight, S.TextColor,
        taLeftJustify, tlCenter, True);
    if Lay.DescriptionRect.Right > Lay.DescriptionRect.Left then
      P.DrawText(Lay.DescriptionRect, FDescription, S.FontName, fs, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);

    if Lay.CloseRect.Right > Lay.CloseRect.Left then
    begin
      // The x's chip and ink are their own typeKey, resolved with the BANNER's variants
      // (so TyAlertClose.error can tint the x of an error alert) and with the state of the
      // GLYPH, not the bar — hovering precisely the x is what lights TyAlertClose:hover.
      closeStates := [];
      if not Enabled then
        Include(closeStates, tysDisabled)
      else if FHoverClose then
        Include(closeStates, tysHover)
      else
        Include(closeStates, tysNormal);
      closeS := ActiveController.Model.ResolveStyle('TyAlertClose', StyleVariant, closeStates);
      // No TyAlertClose colour -> the x is the bar's own ink; never a hard-coded colour.
      if tpTextColor in closeS.Present then
        glyphColor := closeS.TextColor
      else
        glyphColor := S.TextColor;
      // An undefined TyAlertClose key leaves no background -> no chip, and the glyph still
      // draws. A theme that sets the fill only under :hover gets the usual "chip appears
      // under the pointer" for free.
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

procedure TTyAlert.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
