unit tyControls.Notification;
{$mode objfpc}{$H+}

{ TTyNotification — a corner toast: a themed card that floats in over everything, says its
  piece, and dismisses itself after Duration ms.

  This is the gap TTyMessage does NOT fill: TTyMessage is a MODAL dialog — it stops the user
  and demands an answer. A toast interrupts nothing, needs no answer, and disappears on its
  own. The two are different things, not two sizes of the same thing.

  It is a NON-VISUAL COMPONENT (the TTyHint / TTyBalloonHint pattern): drop one on a form,
  set Title / Message / NotificationType, call Show. It is not an in-place control because it
  must float ABOVE everything — including windowed controls, which would clip anything painted
  on the form's own canvas — so, exactly like TTyPopupSurface and TTyBalloonHint, it OWNS A
  WINDOW: a bare borderless fsStayOnTop form that paints the card with TTyPainter and hands
  its mouse gestures straight back to this component.

  Everything that is a RULE — which corner, how toasts stack, the card's geometry, the
  auto-dismiss countdown — lives either in a free function (plain ints in, values out) or in a
  windowless method here, so the whole behaviour is exercisable headlessly. Only putting the
  window on screen needs a real machine; verify the LOOK there. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LCLIntf, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.StyleModel,
  tyControls.Alert;   // TTyAlertType + its type->variant/glyph mapping — the SAME semantics

const
  { Built-in logical-px defaults (96-PPI baseline) for the toast's own metrics. A skin
    retunes each through the named theme metric beside it (the v3/C convention); these are
    only what a theme that sets none of them falls back to. Every one is scaled to device px
    at its call site. }
  TyNotificationWidth     = 340;  // the card's fixed width — the message wraps at line breaks, not by measure
  TyNotificationIconSize  = 24;   // the semantic mark's square slot (TyDrawGlyph pads it, so the mark reads ~16px)
  TyNotificationCloseSize = 14;   // the close (x) slot; matches TyTagCloseSize / TyTabCloseSize so every x reads alike
  TyNotificationGap       = 8;    // mark<->text column, and title<->message
  TyNotificationMargin    = 16;   // inset from the work-area corner
  TyNotificationStackGap  = 8;    // gap between two stacked cards

  { The title's weight. It is a METRIC and not a style property because ONE typeKey has to
    carry two text roles: the TyNotification rule's own font-weight is the MESSAGE's, so the
    title needs a second number and the theme must still own it. }
  TyNotificationTitleWeight = 700;

  TyNotificationWidthVar       = '--notification-width';
  TyNotificationIconSizeVar    = '--notification-icon-size';
  TyNotificationCloseSizeVar   = '--notification-close-size';
  TyNotificationGapVar         = '--notification-gap';
  TyNotificationMarginVar      = '--notification-margin';
  TyNotificationStackGapVar    = '--notification-stack-gap';
  TyNotificationTitleWeightVar = '--notification-title-weight';

  { Behaviour, not appearance — hence a plain property default, not a theme token. 4500ms is
    long enough to read two lines and short enough not to nag. }
  TyNotificationDuration = 4500;
  { Countdown granularity. A toast measured in seconds needs nothing finer, and a lazy 100ms
    timer costs nothing next to TTyButton's 16ms animation tick. }
  TyNotificationTickMs = 100;

type
  { The semantic kind of a notification, which picks its mark (and, through the matching
    StyleClass, that mark's ink).

    DECLARED HERE rather than shared with TTyAlert: the natural home for a type both controls
    could see is tyControls.Types (below every control), and putting it there is a change to a
    shared unit outside this control's remit; aliasing tyControls.Alert instead — the trick
    TTyBadge plays on tyControls.Button — would make a floating toast window depend on an
    inline banner control, which is backwards. If a shared semantic type ever lands in
    tyControls.Types, this becomes a one-line alias and no call site changes. }
  { Re-exported so `uses tyControls.Notification` is enough to declare one. Deliberately an
    ALIAS of TTyAlert's type rather than a copy: a toast and a banner mean exactly the same
    thing by info/success/warning/error — they pick the same glyph and, more importantly, the
    same theme VARIANT NAME, which is a hard contract with every .tycss. Two copies could
    drift that string and silently unstyle one of them; an alias cannot. (Same reasoning, and
    the same shape, as TTyBadge aliasing TTyButton's TTyBadgePosition.) The VALUES still live
    in tyControls.Alert — code naming atInfo also uses that unit. }
  TTyNotificationType = tyControls.Alert.TTyAlertType;

  { Which corner of the screen work area the toast floats in. Screen corners, not form
    corners: a toast outlives the click that raised it and may report on something the user
    has already navigated away from. }
  TTyNotificationPosition = (npTopLeft, npTopRight, npBottomLeft, npBottomRight);

  { The heights (device px) of the cards already stacked in one corner. }
  TTyNotificationHeights = array of Integer;

  { The insides of a toast card, in DEVICE pixels relative to the card's top-left. Every rect
    may be EMPTY, and empty always means "draw nothing here" — never "draw it somewhere else".
      IconRect    — the semantic mark's slot (empty => no mark)
      CloseRect   — the close (x) slot (empty => not closable / no room)
      TitleRect   — the title line (empty => no title, or nothing fits)
      MessageRect — the message block, below the title (empty => nothing fits) }
  TTyNotificationLayout = record
    IconRect: TRect;
    CloseRect: TRect;
    TitleRect: TRect;
    MessageRect: TRect;
  end;

{ --- Pure rules / geometry (headless-testable; no component, no window) ---------------- }

{ The vector mark a type shows. The four kinds are the painter's own semantic glyphs, so a
  theme can swap any of them for an icon-font codepoint (--glyph-info/-success/-warning/-error)
  without this unit knowing. }
function TyNotificationTypeGlyph(AType: TTyNotificationType): TTyGlyphKind;

{ The StyleClass a type resolves under: 'TyNotification.success', 'TyNotificationClose.error'
  and so on. The type is a CLASS and not a code branch precisely so a theme decides what each
  kind looks like; this unit only knows the four names. }
function TyNotificationTypeClass(AType: TTyNotificationType): string;

{ True when a corner's stack grows DOWNWARD. The stack always grows away from the edge the
  first card is anchored to: down from the top corners, up from the bottom ones — so the
  OLDEST toast keeps the corner and the newest never shoves the others off screen. }
function TyNotificationStacksDown(APosition: TTyNotificationPosition): Boolean;

{ How far along the stacking direction a card sits, given the heights of the cards already in
  its corner. A degenerate (<= 0 high) card occupies nothing, so it contributes no gap either
  — it must not push the stack for a card nobody can see. }
function TyNotificationStackOffset(const APriorHeights: array of Integer; AGap: Integer): Integer;

{ Where an AW x AH card goes, in the SAME coordinate space as AWorkArea (screen px at runtime;
  the tests hand in a synthetic rect, which is the whole point of taking it as a parameter).
  AMargin insets it from the corner; AStackOffset pushes it along the stacking direction.
  A stack taller than the work area PILES at the far edge rather than marching off screen: the
  card is clamped, so a newcomer overlaps its elders instead of vanishing. }
function TyNotificationRect(APosition: TTyNotificationPosition; const AWorkArea: TRect;
  AW, AH, AMargin, AStackOffset: Integer): TRect;

{ The card's natural height in DEVICE px, from already-measured text metrics:
    ATitleH     — the title line height (ignored when AHasTitle is False);
    ALineH      — one message line's height;
    ALineCount  — how many message lines (0 = no message);
    APadT/APadB — the theme's vertical padding;
    AGap        — the themed gap, spent between the title and the message;
    AIconSize   — the mark's slot, a FLOOR on the content: the mark sits BESIDE the text, so a
                  one-line toast must still be tall enough to hold it.
  Width is not measured at all — the card is a fixed themed width (--notification-width). }
function TyNotificationHeight(ATitleH, ALineH, ALineCount, APadT, APadB, AGap, AIconSize: Integer;
  AHasIcon, AHasTitle: Boolean): Integer;

{ Pure geometry for a toast card. All inputs/outputs are DEVICE px.
  The content band is the card inset by its themed padding. Inside it the space is claimed in
  a fixed order of precedence — close, then mark, then text:
    - the x hugs the band's TOP-RIGHT corner and is reserved FIRST, because on a Duration=0
      toast it is the only way out (TTyTag's x wins the same way, for the same reason);
    - the mark hugs the band's left and is reserved second, when it still fits;
    - the text column is whatever is left, and is therefore the only elastic part: a width
      that leaves it nothing is a mis-tuned --notification-width, not a layout to defend.
  The title takes the top of the column; the message takes the rest, a gap below it. Padding
  that eats the whole card, or a zero/negative size, leaves every rect empty — never inverted. }
function TyNotificationLayout(AClientWidth, AClientHeight: Integer;
  AHasIcon, AHasTitle, AClosable: Boolean;
  APadL, APadT, APadR, APadB, AIconSize, AGap, ACloseSize, ATitleH: Integer): TTyNotificationLayout;

{ Advance a countdown by AMs. A PAUSED countdown does not move at all (it is frozen, not
  slowed), and a negative/zero tick never rewinds it. }
function TyNotificationAdvance(AElapsedMs, AMs: Integer; APaused: Boolean): Integer;

{ Whether a countdown is up. Duration 0 means "stay until closed", so it NEVER expires — that
  is the whole contract of a toast the user must acknowledge. }
function TyNotificationExpired(AElapsedMs, ADurationMs: Integer): Boolean;

type
  TTyNotification = class;

  { The toast's window. Deliberately a plain borderless TForm (TTyBalloonHint's shell), NOT a
    TTyPopupSurface: a popup surface dismisses itself the moment it loses focus, which is the
    correct rule for a flyout and the exact opposite of a toast — a toast appears BECAUSE the
    user is busy elsewhere, and must sit still while they finish. What it does borrow from
    TTyPopupSurface is the hard-won Color lesson; see TTyNotification.Show.

    It holds no state of its own: it paints by calling back into the component and forwards
    every gesture there, so the card is fully renderable and clickable with no window at all. }
  TTyNotificationWindow = class(TForm)
  private
    FOwnerNote: TTyNotification;
    { Cut the window to the card's themed rounded silhouette. Without it the pixels outside
      the radius show the form's Color as square corners. No-op on Wayland (no XShape — the
      card simply keeps square corners), which is TTyBalloonHint's rule verbatim. }
    procedure ApplyShape;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); reintroduce;
  end;

  TTyNotification = class(TComponent)
  private
    FTitle: string;
    FMessage: string;
    FNotificationType: TTyNotificationType;
    FDuration: Integer;
    FPosition: TTyNotificationPosition;
    FClosable: Boolean;
    FShowIcon: Boolean;
    FPauseOnHover: Boolean;
    FController: TTyStyleController;
    FOnClose: TNotifyEvent;
    FOnClick: TNotifyEvent;
    FWin: TTyNotificationWindow;
    FTimer: TTimer;
    FShowing: Boolean;
    FElapsedMs: Integer;
    FHoverClose: Boolean;      // pointer is precisely over the x
    FClosePressed: Boolean;    // this press STARTED on the x (so it is a close, not a card click)
    FPointerInside: Boolean;   // pointer is over the card (drives :hover and the pause)
    procedure SetTitle(const AValue: string);
    procedure SetMessage(const AValue: string);
    procedure SetNotificationType(AValue: TTyNotificationType);
    procedure SetDuration(AValue: Integer);
    procedure SetPosition(AValue: TTyNotificationPosition);
    procedure SetClosable(AValue: Boolean);
    procedure SetShowIcon(AValue: Boolean);
    procedure SetController(AValue: TTyStyleController);
    { The theme metrics, in LOGICAL px (each call site scales). Named helpers rather than
      inline Metric() calls so a typo cannot strand one call site on the default. }
    function WidthLogical: Integer;
    function IconSizeLogical: Integer;
    function CloseSizeLogical: Integer;
    function GapLogical: Integer;
    function MarginLogical: Integer;
    function StackGapLogical: Integer;
    function TitleWeight: Integer;
    { Split the message the way TTyBalloonHint splits its description: on line breaks only.
      There is no auto-wrap — the card is a fixed themed width and the author decides where
      the lines end. }
    procedure SplitMessage(ALines: TStrings);
    { One line's height in device px at APPI, from the stable reference glyph 'Ag' (so an
      empty line still measures a full line) in the theme's card font at AWeight. }
    function LineHeightAt(APPI, AWeight: Integer): Integer;
    function TitleHeightAt(APPI: Integer): Integer;
    function PtOnClose(X, Y, AClientW, AClientH, APPI: Integer): Boolean;
    { The heights of the showing toasts that entered MY corner before me. The stack list is in
      show order, so everything after Self in it is stacked below Self. }
    function PriorHeights(APPI: Integer): TTyNotificationHeights;
    procedure EnterStack;
    procedure LeaveStack;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure InvalidateWindow;
    { Re-place a live toast and re-stack its corner. Every one of Title/Message/Type/Closable
      changes the card's measured SIZE, so a bare repaint would leave it at the old one. }
    procedure Restyle;
  protected
    { The showing STATE, with no window: reset the countdown and enter the corner's stack.
      Show does this and THEN puts a window on screen — split so the whole lifetime / stacking
      / countdown rule set is drivable headlessly, which is exactly how the tests reach it (a
      real Show needs a handle the headless runner has not got). }
    procedure BeginShowing;
    { A toast has no enabled / focus / press state of its own; the pointer being over the CARD
      is the one thing a theme might react to (a hover lift), so mirror the base classes' rule
      and give it :hover / :normal. }
    function CurrentStates: TTyStateSet;
    { The card: 'TyNotification' resolved under the TYPE's class. Everything about the card
      comes from here — surface, border, radius, padding, font — AND the mark's ink. }
    function CardStyle: TTyStyleSet;
    { The card WITHOUT the type class. Read for one thing only: the title/message ink. }
    function BaseStyle: TTyStyleSet;
    { The two inks, split because ONE typeKey must carry two text roles:
        'TyNotification'          -> its color is the TITLE + MESSAGE ink;
        'TyNotification.<type>'   -> its color is the MARK's ink.
      With no variant rule the variant cascade resolves to the base rule, so the mark simply
      takes the card's own ink — the degradation is automatic, and never a hard-coded colour. }
    function MarkInk: TTyColor;
    function TextInk: TTyColor;
    { A non-visual component has no Font of its own, so the theme is the ONLY source: pass
      ParentFont=True / size 0 and let TyResolveFontSize fall through to --font-size-base. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { TyNotificationLayout fed from the resolved theme. AWidth/AHeight are device px handed in
      by the caller (the paint passes its own rect, the hit-test the window's client size), so
      nothing here reads a size behind the caller's back. }
    function LayoutFor(AWidth, AHeight, APPI: Integer): TTyNotificationLayout;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The gesture path, driven by the toast window (which supplies its own client size + PPI).
      The STATE lives here on the component, so the whole hover / press / close rule set runs
      with no window at all. }
    procedure DoMouseMove(X, Y, AClientW, AClientH, APPI: Integer);
    procedure DoMouseDown(X, Y, AClientW, AClientH, APPI: Integer);
    procedure DoMouseUp(X, Y, AClientW, AClientH, APPI: Integer);
    procedure DoMouseLeave;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The controller whose theme this toast resolves against — never FController directly: a
      toast themed by the global default has Controller = nil. }
    function ActiveController: TTyStyleController;
    { Move the live window onto the slot the rules give it. No-op with no window. }
    procedure PlaceWindow;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The typeKeys this component resolves. Not an ITyStyleable: the controller's styleable
      registry holds TControls, and a non-visual component is not one — so the keys are plain
      functions, for the tests and for the theme docs. }
    class function StyleTypeKey: string;
    class function CloseStyleTypeKey: string;
    { Float the card into its corner and start the countdown. Re-showing a live toast simply
      restarts the countdown (it does not stack a second copy of itself). Inert at design time. }
    procedure Show;
    { Dismiss now: stops the countdown, leaves the stack (the toasts below close the gap) and
      fires OnClose. Idempotent — OnClose fires once per dismissal, never for a Hide on an
      already-hidden toast. }
    procedure Hide;
    { Advance the auto-dismiss countdown by AMs; True iff THIS tick dismissed the toast. The
      lazy TTimer calls it every tick at runtime; tests call it directly, so no test ever
      sleeps (TTyButton.AdvanceAnimation is the same seam for the same reason). }
    function AdvanceTime(AMs: Integer): Boolean;
    { The card's natural size in device px at APPI: the themed width, and the height its title
      + message + mark need. }
    function MeasureAtPPI(APPI: Integer): TSize;
    { Where this toast's card belongs inside AWorkArea, accounting for the toasts already
      stacked in its corner. The work area is a PARAMETER (not Screen.WorkAreaRect) so the
      placement rules are testable without a screen — Show passes the real one. }
    function SlotRectIn(const AWorkArea: TRect; APPI: Integer): TRect;
    { The close-glyph slot in device px, (0,0)-local, for a card of AClientW x AClientH — the
      exact rect the paint fills and the hit-test measures against. Empty when not Closable. }
    function CloseRectIn(AClientW, AClientH, APPI: Integer): TRect;
    { Whether the card is currently up. }
    property Showing: Boolean read FShowing;
  published
    { The headline, drawn in the card font at --notification-title-weight. Empty = no title:
      the message then takes the whole text column. }
    property Title: string read FTitle write SetTitle;
    { The body. Split on line breaks only — the card is a fixed themed width and does NOT
      auto-wrap, so the author owns the line ends. }
    property Message: string read FMessage write SetMessage;
    { The semantic kind: picks the mark and, through 'TyNotification.<type>', its ink. }
    property NotificationType: TTyNotificationType read FNotificationType
      write SetNotificationType default atInfo;
    { Auto-dismiss delay in ms. 0 = stay until Hide / the x — which is why a Duration=0 toast
      really ought to keep Closable True. }
    property Duration: Integer read FDuration write SetDuration default TyNotificationDuration;
    { Which screen corner it floats in. Toasts sharing a corner stack in show order. }
    property Position: TTyNotificationPosition read FPosition write SetPosition default npTopRight;
    { Show the close (x). On by default: a toast the user cannot dismiss early is a toast that
      is in the way. }
    property Closable: Boolean read FClosable write SetClosable default True;
    { Show the type's mark. Off = a text-only card (the type then only reaches the theme). }
    property ShowIcon: Boolean read FShowIcon write SetShowIcon default True;
    { Freeze the countdown while the pointer is over the card, so a toast cannot expire out
      from under someone who is reading it (or reaching for its x). }
    property PauseOnHover: Boolean read FPauseOnHover write FPauseOnHover default True;
    property Controller: TTyStyleController read FController write SetController;
    { Fired once per dismissal, whatever caused it: the countdown, the x, or Hide. NOT fired
      when the component is destroyed — a component going away is not a toast the user closed.
      Do NOT Free the toast from this handler: a timed-out dismissal reaches it from inside the
      countdown timer's own tick, and the timer belongs to the component you would be freeing.
      For a toast nobody wants to own, use TyNotify — it reaps its own. }
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    { Fired when the CARD is clicked — never for a click on the x (that gesture is a close and
      nothing else). Does not dismiss: what a click means is the host's business. }
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

{ Fire-and-forget toast: build one, show it, and let this unit own it. The house's global-
  function convenience (tyControls.Dialogs' TyShowMessage / TyMessageDlg), for the very common
  "report this and get out of the way" call that does not want a component on a form. }
procedure TyNotify(const ATitle, AMessage: string; AType: TTyNotificationType = atInfo;
  APosition: TTyNotificationPosition = npTopRight;
  ADurationMs: Integer = TyNotificationDuration);

implementation

uses
  tyControls.QtWS;   // TyQtIsWayland — the shape gate

// ---------------------------------------------------------------------------
// Pure rules / geometry
// ---------------------------------------------------------------------------

function TyNotificationTypeGlyph(AType: TTyNotificationType): TTyGlyphKind;
begin
  Result := TyAlertGlyph(AType);   // one mapping, shared with the banner
end;

function TyNotificationTypeClass(AType: TTyNotificationType): string;
begin
  Result := TyAlertVariant(AType);   // one mapping: the variant name is a theme contract
end;

function TyNotificationStacksDown(APosition: TTyNotificationPosition): Boolean;
begin
  Result := APosition in [npTopLeft, npTopRight];
end;

function TyNotificationStackOffset(const APriorHeights: array of Integer; AGap: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  if AGap < 0 then AGap := 0;
  for i := 0 to High(APriorHeights) do
    // A card with no height occupies nothing, so it earns no gap either.
    if APriorHeights[i] > 0 then
      Inc(Result, APriorHeights[i] + AGap);
end;

function TyNotificationRect(APosition: TTyNotificationPosition; const AWorkArea: TRect;
  AW, AH, AMargin, AStackOffset: Integer): TRect;
var
  x, y: Integer;
begin
  if AW < 0 then AW := 0;
  if AH < 0 then AH := 0;
  if AMargin < 0 then AMargin := 0;
  if AStackOffset < 0 then AStackOffset := 0;

  if APosition in [npTopLeft, npBottomLeft] then
    x := AWorkArea.Left + AMargin
  else
    x := AWorkArea.Right - AMargin - AW;

  // The stack grows AWAY from the anchored edge, so the first (oldest) card keeps the corner.
  if TyNotificationStacksDown(APosition) then
    y := AWorkArea.Top + AMargin + AStackOffset
  else
    y := AWorkArea.Bottom - AMargin - AH - AStackOffset;

  // A stack taller (or a card wider) than the work area piles at the far edge instead of
  // marching off screen: an overlapped toast is still readable, an off-screen one is not.
  if y + AH > AWorkArea.Bottom then y := AWorkArea.Bottom - AH;
  if y < AWorkArea.Top then y := AWorkArea.Top;
  if x + AW > AWorkArea.Right then x := AWorkArea.Right - AW;
  if x < AWorkArea.Left then x := AWorkArea.Left;

  Result := Rect(x, y, x + AW, y + AH);
end;

function TyNotificationHeight(ATitleH, ALineH, ALineCount, APadT, APadB, AGap, AIconSize: Integer;
  AHasIcon, AHasTitle: Boolean): Integer;
var
  contentH: Integer;
begin
  if ATitleH < 0 then ATitleH := 0;
  if ALineH < 0 then ALineH := 0;
  if ALineCount < 0 then ALineCount := 0;
  if APadT < 0 then APadT := 0;
  if APadB < 0 then APadB := 0;
  if AGap < 0 then AGap := 0;
  if AIconSize < 0 then AIconSize := 0;

  contentH := 0;
  if AHasTitle then Inc(contentH, ATitleH);
  if ALineCount > 0 then
  begin
    if AHasTitle then Inc(contentH, AGap);   // the gap only exists BETWEEN the two
    Inc(contentH, ALineCount * ALineH);
  end;
  // The mark sits BESIDE the text, so a one-line toast must still clear it.
  if AHasIcon and (contentH < AIconSize) then contentH := AIconSize;

  Result := APadT + contentH + APadB;
  if Result < 1 then Result := 1;
end;

function TyNotificationLayout(AClientWidth, AClientHeight: Integer;
  AHasIcon, AHasTitle, AClosable: Boolean;
  APadL, APadT, APadR, APadB, AIconSize, AGap, ACloseSize, ATitleH: Integer): TTyNotificationLayout;
var
  bandL, bandT, bandR, bandB, colL, colR: Integer;
  closeL, closeB, iconT, iconB, titleB, y: Integer;
begin
  Result.IconRect := Rect(0, 0, 0, 0);
  Result.CloseRect := Rect(0, 0, 0, 0);
  Result.TitleRect := Rect(0, 0, 0, 0);
  Result.MessageRect := Rect(0, 0, 0, 0);
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  if APadL < 0 then APadL := 0;
  if APadT < 0 then APadT := 0;
  if APadR < 0 then APadR := 0;
  if APadB < 0 then APadB := 0;
  if AIconSize < 0 then AIconSize := 0;
  if AGap < 0 then AGap := 0;
  if ACloseSize < 0 then ACloseSize := 0;
  if ATitleH < 0 then ATitleH := 0;

  // The content band: the card inset by its themed padding. Padding that eats the whole card
  // leaves nothing to lay out (every rect stays empty).
  bandL := APadL;
  bandT := APadT;
  bandR := AClientWidth - APadR;
  bandB := AClientHeight - APadB;
  if (bandR <= bandL) or (bandB <= bandT) then Exit;

  colL := bandL;
  colR := bandR;

  // 1. The x, hugging the band's top-right. Reserved FIRST: on a Duration=0 toast it is the
  //    only way out, so it never gives up its space to the text.
  if AClosable and (ACloseSize > 0) then
  begin
    closeL := bandR - ACloseSize;
    if closeL < bandL then closeL := bandL;      // too narrow: the x takes what there is
    closeB := bandT + ACloseSize;
    if closeB > bandB then closeB := bandB;      // shorter than its slot: squash, don't overflow
    Result.CloseRect := Rect(closeL, bandT, bandR, closeB);
    colR := closeL - AGap;                       // the text stops a gap short of the slot
  end;

  // 2. The mark, hugging the band's left — but only if it still fits beside the x.
  if AHasIcon and (AIconSize > 0) and (colL + AIconSize <= colR) then
  begin
    // Centred on the TITLE line when there is one (the mark belongs beside the headline, and
    // a mark taller than that line simply top-aligns), else centred in the whole band.
    if AHasTitle and (ATitleH > 0) then
      iconT := bandT + (ATitleH - AIconSize) div 2
    else
      iconT := bandT + ((bandB - bandT) - AIconSize) div 2;
    if iconT < bandT then iconT := bandT;
    iconB := iconT + AIconSize;
    if iconB > bandB then iconB := bandB;
    Result.IconRect := Rect(colL, iconT, colL + AIconSize, iconB);
    colL := colL + AIconSize + AGap;
  end;

  // 3. The text column: whatever is left. The title takes its top, the message the rest.
  if colR <= colL then Exit;
  y := bandT;
  if AHasTitle and (ATitleH > 0) then
  begin
    titleB := y + ATitleH;
    if titleB > bandB then titleB := bandB;
    Result.TitleRect := Rect(colL, y, colR, titleB);
    y := titleB + AGap;
  end;
  if y < bandB then
    Result.MessageRect := Rect(colL, y, colR, bandB);
end;

function TyNotificationAdvance(AElapsedMs, AMs: Integer; APaused: Boolean): Integer;
begin
  Result := AElapsedMs;
  if APaused then Exit;      // frozen, not slowed
  if AMs <= 0 then Exit;     // a tick never rewinds the countdown
  Inc(Result, AMs);
end;

function TyNotificationExpired(AElapsedMs, ADurationMs: Integer): Boolean;
begin
  Result := (ADurationMs > 0) and (AElapsedMs >= ADurationMs);
end;

// ---------------------------------------------------------------------------
// The live stack: every showing toast, in show order (which IS the stacking order).
// A plain unit-level list, because a corner is a screen-wide resource that no single
// component owns.
// ---------------------------------------------------------------------------
var
  UStack: TFPList = nil;   // showing toasts (does NOT own them)
  UAuto: TFPList = nil;    // toasts TyNotify created and must therefore free

{ Re-place every showing toast in APosition: one closing out of the middle of a stack must not
  leave a hole. Only toasts with a live window move — a never-shown one has nothing to place. }
procedure ReflowStack(APosition: TTyNotificationPosition);
var
  i: Integer;
  n: TTyNotification;
begin
  if UStack = nil then Exit;
  for i := 0 to UStack.Count - 1 do
  begin
    n := TTyNotification(UStack[i]);
    if n.FShowing and (n.FPosition = APosition) then
      n.PlaceWindow;
  end;
end;

// ---------------------------------------------------------------------------
// TTyNotificationWindow
// ---------------------------------------------------------------------------
constructor TTyNotificationWindow.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  BorderStyle := bsNone;      // the card IS the chrome
  FormStyle := fsStayOnTop;   // it floats above the app it reports on
  ShowInTaskBar := stNever;   // a toast is not a window the user manages
  Position := poDesigned;     // Show must not re-centre a card we placed by rule
  Visible := False;
end;

procedure TTyNotificationWindow.Paint;
begin
  if FOwnerNote = nil then Exit;
  FOwnerNote.RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
  ApplyShape;
end;

procedure TTyNotificationWindow.ApplyShape;
var
  S: TTyStyleSet;
  d: Integer;
  rgn: HRGN;
begin
  if (FOwnerNote = nil) or not HandleAllocated then Exit;
  if TyQtIsWayland then Exit;   // no XShape: square corners, as TTyBalloonHint degrades
  S := FOwnerNote.CardStyle;
  d := MulDiv(TyEffectiveCorners(S).TL, Font.PixelsPerInch, 96) * 2;
  if d > 0 then
    rgn := CreateRoundRectRgn(0, 0, ClientWidth + 1, ClientHeight + 1, d, d)
  else
    rgn := CreateRectRgn(0, 0, ClientWidth + 1, ClientHeight + 1);
  SetWindowRgn(Handle, rgn, True);   // takes ownership of rgn
end;

procedure TTyNotificationWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and (FOwnerNote <> nil) then
    FOwnerNote.DoMouseDown(X, Y, ClientWidth, ClientHeight, Font.PixelsPerInch);
end;

procedure TTyNotificationWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and (FOwnerNote <> nil) then
    FOwnerNote.DoMouseUp(X, Y, ClientWidth, ClientHeight, Font.PixelsPerInch);
end;

procedure TTyNotificationWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FOwnerNote <> nil then
    FOwnerNote.DoMouseMove(X, Y, ClientWidth, ClientHeight, Font.PixelsPerInch);
end;

procedure TTyNotificationWindow.MouseLeave;
begin
  inherited MouseLeave;
  if FOwnerNote <> nil then FOwnerNote.DoMouseLeave;
end;

// ---------------------------------------------------------------------------
// TTyNotification — construction / theming
// ---------------------------------------------------------------------------
constructor TTyNotification.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNotificationType := atInfo;
  FDuration := TyNotificationDuration;
  FPosition := npTopRight;
  FClosable := True;
  FShowIcon := True;
  FPauseOnHover := True;
end;

destructor TTyNotification.Destroy;
begin
  // Dismiss WITHOUT firing OnClose: a component being destroyed is not a notification the user
  // closed, and the handler's form may already be half torn down.
  FOnClose := nil;
  Hide;
  if FTimer <> nil then
    FTimer.OnTimer := nil;   // detach before free so no queued tick re-enters us
  FreeAndNil(FTimer);
  FreeAndNil(FWin);          // CreateNew(nil): owned by us, not by a form
  inherited Destroy;
end;

class function TTyNotification.StyleTypeKey: string;
begin
  Result := 'TyNotification';
end;

class function TTyNotification.CloseStyleTypeKey: string;
begin
  Result := 'TyNotificationClose';
end;

function TTyNotification.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyNotification.CurrentStates: TTyStateSet;
begin
  Result := [];
  if FPointerInside then Include(Result, tysHover);
  if Result = [] then Include(Result, tysNormal);
end;

function TTyNotification.CardStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(StyleTypeKey,
    TyNotificationTypeClass(FNotificationType), CurrentStates);
end;

function TTyNotification.BaseStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(StyleTypeKey, '', CurrentStates);
end;

function TTyNotification.MarkInk: TTyColor;
begin
  Result := CardStyle.TextColor;
end;

function TTyNotification.TextInk: TTyColor;
begin
  Result := BaseStyle.TextColor;
end;

function TTyNotification.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, True, 0, ActiveController);
end;

// ---------------------------------------------------------------------------
// Theme metrics
// ---------------------------------------------------------------------------
function TTyNotification.WidthLogical: Integer;
begin
  Result := ActiveController.Metric(TyNotificationWidthVar, TyNotificationWidth);
  if Result < 1 then Result := 1;
end;

function TTyNotification.IconSizeLogical: Integer;
begin
  Result := ActiveController.Metric(TyNotificationIconSizeVar, TyNotificationIconSize);
  if Result < 0 then Result := 0;
end;

function TTyNotification.CloseSizeLogical: Integer;
begin
  Result := ActiveController.Metric(TyNotificationCloseSizeVar, TyNotificationCloseSize);
  if Result < 0 then Result := 0;
end;

function TTyNotification.GapLogical: Integer;
begin
  Result := ActiveController.Metric(TyNotificationGapVar, TyNotificationGap);
  if Result < 0 then Result := 0;
end;

function TTyNotification.MarginLogical: Integer;
begin
  Result := ActiveController.Metric(TyNotificationMarginVar, TyNotificationMargin);
  if Result < 0 then Result := 0;
end;

function TTyNotification.StackGapLogical: Integer;
begin
  Result := ActiveController.Metric(TyNotificationStackGapVar, TyNotificationStackGap);
  if Result < 0 then Result := 0;
end;

function TTyNotification.TitleWeight: Integer;
begin
  // NOT scaled at any call site: this metric is a font WEIGHT, not a length. Metric() is
  // simply the theme's integer-token resolver, and a weight is the one number the single
  // shared TyNotification rule cannot carry (its font-weight is the message's).
  Result := ActiveController.Metric(TyNotificationTitleWeightVar, TyNotificationTitleWeight);
  if Result < 1 then Result := TyNotificationTitleWeight;
end;

// ---------------------------------------------------------------------------
// Measurement + geometry
// ---------------------------------------------------------------------------
procedure TTyNotification.SplitMessage(ALines: TStrings);
begin
  ALines.Text := FMessage;   // splits on CR/LF; '' -> no lines at all
end;

function TTyNotification.LineHeightAt(APPI, AWeight: Integer): Integer;
{ Measured with a CANVAS-LESS painter — the TTyBadge idiom: BeginPaint(nil, ...) builds only
  the painter's internal bitmap and EndPaint frees it WITHOUT blitting, so this is safe outside
  a paint cycle and leaks nothing. It has to be the painter and not a TBitmap canvas: the card
  is drawn with BGRA text metrics, and only the same measurer reproduces the size those glyphs
  actually render at. }
var
  P: TTyPainter;
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := CardStyle;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    Result := P.MeasureText('Ag', S.FontName, ResolveFontSize(S), AWeight).cy;
    P.EndPaint;                                  // nil canvas -> no blit, just frees the bitmap
  finally
    P.Free;
  end;
  if Result < 1 then Result := 1;
end;

function TTyNotification.TitleHeightAt(APPI: Integer): Integer;
begin
  Result := LineHeightAt(APPI, TitleWeight);
end;

function TTyNotification.MeasureAtPPI(APPI: Integer): TSize;
var
  Lines: TStringList;
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := CardStyle;
  Lines := TStringList.Create;
  try
    SplitMessage(Lines);
    // Width is the theme's, flat: the card does not measure its text (it does not wrap it
    // either), so a row of toasts is a column of identical cards, as a stack must be.
    Result.cx := MulDiv(WidthLogical, APPI, 96);
    Result.cy := TyNotificationHeight(TitleHeightAt(APPI),
      LineHeightAt(APPI, S.FontWeight), Lines.Count,
      MulDiv(S.Padding.Top, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96),
      MulDiv(GapLogical, APPI, 96), MulDiv(IconSizeLogical, APPI, 96),
      FShowIcon, FTitle <> '');
  finally
    Lines.Free;
  end;
end;

function TTyNotification.LayoutFor(AWidth, AHeight, APPI: Integer): TTyNotificationLayout;
var
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := CardStyle;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the rects the hit-test measures are the rects the paint drew.
  Result := TyNotificationLayout(AWidth, AHeight, FShowIcon, FTitle <> '', FClosable,
    MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Top, APPI, 96),
    MulDiv(S.Padding.Right, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96),
    MulDiv(IconSizeLogical, APPI, 96), MulDiv(GapLogical, APPI, 96),
    MulDiv(CloseSizeLogical, APPI, 96), TitleHeightAt(APPI));
end;

function TTyNotification.CloseRectIn(AClientW, AClientH, APPI: Integer): TRect;
begin
  Result := LayoutFor(AClientW, AClientH, APPI).CloseRect;
end;

function TTyNotification.PtOnClose(X, Y, AClientW, AClientH, APPI: Integer): Boolean;
var
  R: TRect;
begin
  R := CloseRectIn(AClientW, AClientH, APPI);
  Result := (R.Right > R.Left) and (X >= R.Left) and (X < R.Right)
    and (Y >= R.Top) and (Y < R.Bottom);
end;

// ---------------------------------------------------------------------------
// Stacking + placement
// ---------------------------------------------------------------------------
procedure TTyNotification.EnterStack;
begin
  if UStack = nil then UStack := TFPList.Create;
  if UStack.IndexOf(Self) < 0 then UStack.Add(Self);
end;

procedure TTyNotification.LeaveStack;
begin
  if UStack <> nil then UStack.Remove(Self);
end;

function TTyNotification.PriorHeights(APPI: Integer): TTyNotificationHeights;
var
  i, n: Integer;
  other: TTyNotification;
begin
  SetLength(Result, 0);
  if UStack = nil then Exit;
  n := 0;
  for i := 0 to UStack.Count - 1 do
  begin
    other := TTyNotification(UStack[i]);
    if other = Self then Break;   // show order = stack order: everything past me is below me
    if other.FShowing and (other.FPosition = FPosition) then
    begin
      SetLength(Result, n + 1);
      Result[n] := other.MeasureAtPPI(APPI).cy;
      Inc(n);
    end;
  end;
end;

function TTyNotification.SlotRectIn(const AWorkArea: TRect; APPI: Integer): TRect;
var
  sz: TSize;
begin
  if APPI <= 0 then APPI := 96;
  sz := MeasureAtPPI(APPI);
  Result := TyNotificationRect(FPosition, AWorkArea, sz.cx, sz.cy,
    MulDiv(MarginLogical, APPI, 96),
    TyNotificationStackOffset(PriorHeights(APPI), MulDiv(StackGapLogical, APPI, 96)));
end;

procedure TTyNotification.PlaceWindow;
var
  R: TRect;
  ppi: Integer;
begin
  if FWin = nil then Exit;
  ppi := Screen.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  R := SlotRectIn(Screen.WorkAreaRect, ppi);
  FWin.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
end;

procedure TTyNotification.InvalidateWindow;
begin
  if (FWin <> nil) and FWin.Visible then FWin.Invalidate;
end;

procedure TTyNotification.Restyle;
begin
  if not FShowing then Exit;
  PlaceWindow;
  ReflowStack(FPosition);   // my new height moves everything stacked below me
  InvalidateWindow;
end;

// ---------------------------------------------------------------------------
// Lifetime
// ---------------------------------------------------------------------------
procedure TTyNotification.BeginShowing;
begin
  FElapsedMs := 0;          // a re-Show restarts the countdown...
  if FShowing then Exit;    // ...but never stacks a second copy of the same toast
  FHoverClose := False;
  FClosePressed := False;
  FPointerInside := False;
  FShowing := True;
  EnterStack;
end;

procedure TTyNotification.Show;
var
  S: TTyStyleSet;
begin
  if csDesigning in ComponentState then Exit;   // a toast is a runtime event, not a preview
  BeginShowing;
  if FWin = nil then
  begin
    FWin := TTyNotificationWindow.CreateNew(nil);
    FWin.FOwnerNote := Self;
  end;
  { The TTyPopupSurface lesson: a bare borderless form never sets Color, so it keeps the OS
    default clBtnFace — which is near-BLACK on a dark-mode OS. Every pixel the card does not
    cover erases to it: the corners outside the themed radius, and (on Wayland, where the shape
    region is silently ignored) the whole silhouette. Paint the window with the card's own
    surface colour so those pixels read as the card instead of a black notch. }
  S := CardStyle;
  if (tpBackground in S.Present) and (S.Background.Kind = tfkSolid) then
    FWin.Color := TyColorToLCL(S.Background.Color);
  PlaceWindow;
  FWin.Show;
  FWin.BringToFront;
  PlaceWindow;   // a bsNone form can be re-placed by the WM on show (TTyBalloonHint re-sets too)
  FWin.Invalidate;
  EnsureTimer;
  FTimer.Enabled := FDuration > 0;
end;

procedure TTyNotification.Hide;
var
  pos: TTyNotificationPosition;
begin
  if not FShowing then Exit;   // idempotent: OnClose fires once per dismissal
  FShowing := False;
  pos := FPosition;            // a handler may move us; the corner we LEAVE is this one
  if FTimer <> nil then FTimer.Enabled := False;
  LeaveStack;
  FHoverClose := False;
  FClosePressed := False;
  FPointerInside := False;
  if (FWin <> nil) and FWin.Visible then FWin.Hide;
  ReflowStack(pos);            // the toasts below close the gap
  if Assigned(FOnClose) then FOnClose(Self);
end;

procedure TTyNotification.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := TyNotificationTickMs;
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyNotification.HandleTimer(Sender: TObject);
begin
  // Ticks land ~Interval apart and a toast is measured in seconds: close enough, and it keeps
  // the countdown on the one steppable seam the tests drive. Nothing may follow this call:
  // AdvanceTime can dismiss the toast, and a dismissal runs the user's OnClose.
  AdvanceTime(Integer(FTimer.Interval));
end;

function TTyNotification.AdvanceTime(AMs: Integer): Boolean;
begin
  Result := False;
  if not FShowing then Exit;
  FElapsedMs := TyNotificationAdvance(FElapsedMs, AMs, FPauseOnHover and FPointerInside);
  if TyNotificationExpired(FElapsedMs, FDuration) then
  begin
    Result := True;
    Hide;
  end;
end;

// ---------------------------------------------------------------------------
// Gestures (driven by the window; the state lives here)
// ---------------------------------------------------------------------------
procedure TTyNotification.DoMouseMove(X, Y, AClientW, AClientH, APPI: Integer);
var
  onCard, overClose: Boolean;   // NOT 'onClose': Pascal is case-insensitive, so it would
begin                           // collide with this component's own OnClose property.
  onCard := (X >= 0) and (Y >= 0) and (X < AClientW) and (Y < AClientH);
  overClose := FClosable and PtOnClose(X, Y, AClientW, AClientH, APPI);
  if (FPointerInside <> onCard) or (FHoverClose <> overClose) then
  begin
    FPointerInside := onCard;   // freezes the countdown (PauseOnHover) and drives :hover
    FHoverClose := overClose;
    InvalidateWindow;
  end;
end;

procedure TTyNotification.DoMouseDown(X, Y, AClientW, AClientH, APPI: Integer);
begin
  FClosePressed := FClosable and PtOnClose(X, Y, AClientW, AClientH, APPI);
  if FClosePressed then InvalidateWindow;   // TyNotificationClose:active
end;

procedure TTyNotification.DoMouseUp(X, Y, AClientW, AClientH, APPI: Integer);
var
  wasClose: Boolean;
begin
  wasClose := FClosePressed;
  FClosePressed := False;
  if wasClose then
  begin
    // Press AND release both on the x commit the close; dragging off it cancels the whole
    // gesture, like any push button — and never leaks out as a card click, because the press
    // was never the card's. (TTyTag splits the same two gestures for the same reason: "get rid
    // of this" must not also read as "the user chose this".)
    if PtOnClose(X, Y, AClientW, AClientH, APPI) then Hide
    else InvalidateWindow;
    Exit;
  end;
  if (X >= 0) and (Y >= 0) and (X < AClientW) and (Y < AClientH) and Assigned(FOnClick) then
    FOnClick(Self);
end;

procedure TTyNotification.DoMouseLeave;
begin
  if not (FPointerInside or FHoverClose) then Exit;
  FPointerInside := False;   // the countdown resumes
  FHoverClose := False;
  InvalidateWindow;
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------
procedure TTyNotification.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, closeS: TTyStyleSet;
  R: TRect;
  Lay: TTyNotificationLayout;
  Lines: TStringList;
  closeStates: TTyStateSet;
  ink, closeInk: TTyColor;
  fs, lh, i, y, lb: Integer;
begin
  if APPI <= 0 then APPI := 96;
  S := CardStyle;
  P := TTyPainter.Create;
  Lines := TStringList.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at ARect's origin,
    // so a non-zero ARect origin would shift the card.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    if not (tpBackground in S.Present) then
    begin
      // A theme that does not define TyNotification gets NO card — not a hard-coded one.
      P.EndPaint;
      Exit;
    end;
    if tpOpacity in S.Present then P.Opacity := S.Opacity;
    // No shadow: the window is cut to the card's silhouette, so a drop shadow would be cut off
    // with everything else outside it. Elevation is the OS's business for a top-level window.
    P.FillBackground(R, S.Background, TyEffectiveCorners(S));
    if TyBorderVisible(S) then
      P.StrokeBorder(R, TyEffectiveCorners(S), S.BorderWidth, S.BorderColor);

    Lay := LayoutFor(R.Right - R.Left, R.Bottom - R.Top, APPI);
    ink := TextInk;
    fs := ResolveFontSize(S);

    // The mark, in the TYPE variant's ink (see MarkInk). v3/C5: theme-overridable with an
    // icon-font codepoint (--glyph-info / -success / -warning / -error).
    if Lay.IconRect.Right > Lay.IconRect.Left then
      TyDrawGlyph(P, ActiveController, Lay.IconRect,
        TyNotificationTypeGlyph(FNotificationType), MarkInk, 2);

    if Lay.TitleRect.Right > Lay.TitleRect.Left then
      // Ellipsised, never sheared at the clip edge. No mnemonic parsing — a toast activates
      // nothing, so an '&' in a title is literal text.
      P.DrawText(Lay.TitleRect, FTitle, S.FontName, fs, TitleWeight, ink,
        taLeftJustify, tlCenter, True);

    if Lay.MessageRect.Right > Lay.MessageRect.Left then
    begin
      SplitMessage(Lines);
      lh := LineHeightAt(APPI, S.FontWeight);
      y := Lay.MessageRect.Top;
      for i := 0 to Lines.Count - 1 do
      begin
        if y >= Lay.MessageRect.Bottom then Break;   // out of card: stop, never overflow it
        lb := y + lh;
        if lb > Lay.MessageRect.Bottom then lb := Lay.MessageRect.Bottom;
        P.DrawText(Rect(Lay.MessageRect.Left, y, Lay.MessageRect.Right, lb),
          Lines[i], S.FontName, fs, S.FontWeight, ink, taLeftJustify, tlCenter, True);
        y := y + lh;
      end;
    end;

    if Lay.CloseRect.Right > Lay.CloseRect.Left then
    begin
      // The x's chip and ink are their OWN typeKey, resolved with the toast's type class (so
      // TyNotificationClose.error can tint the x of an error toast) and with the state of the
      // GLYPH, not the card — hovering precisely the x is what lights :hover.
      closeStates := [];
      if FClosePressed then Include(closeStates, tysActive)
      else if FHoverClose then Include(closeStates, tysHover)
      else Include(closeStates, tysNormal);
      closeS := ActiveController.Model.ResolveStyle(CloseStyleTypeKey,
        TyNotificationTypeClass(FNotificationType), closeStates);
      // An undefined TyNotificationClose leaves no background -> no chip, and the x still draws
      // in the card's own ink. A theme that fills only under :hover gets "the chip appears
      // under the pointer" for free.
      if tpBackground in closeS.Present then
        P.FillBackground(Lay.CloseRect, closeS.Background, TyEffectiveCorners(closeS));
      if tpTextColor in closeS.Present then closeInk := closeS.TextColor
      else closeInk := ink;
      TyDrawGlyph(P, ActiveController, Lay.CloseRect, tgClose, closeInk, 1);
    end;

    P.EndPaint;
  finally
    Lines.Free;
    P.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Property setters
// ---------------------------------------------------------------------------
procedure TTyNotification.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  Restyle;
end;

procedure TTyNotification.SetMessage(const AValue: string);
begin
  if FMessage = AValue then Exit;
  FMessage := AValue;
  Restyle;
end;

procedure TTyNotification.SetNotificationType(AValue: TTyNotificationType);
begin
  if FNotificationType = AValue then Exit;
  FNotificationType := AValue;
  Restyle;   // the type is a StyleClass: padding/font (hence the height) may change with it
end;

procedure TTyNotification.SetDuration(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;   // "no duration" is 0; a negative one is a typo, not a rule
  if FDuration = AValue then Exit;
  FDuration := AValue;
  // Retuning a live toast's duration restarts its countdown from now, which is what a caller
  // extending "keep this up longer" means; the timer follows the new 0/non-0 answer.
  FElapsedMs := 0;
  if FShowing and (FTimer <> nil) then FTimer.Enabled := FDuration > 0;
end;

procedure TTyNotification.SetPosition(AValue: TTyNotificationPosition);
var
  old: TTyNotificationPosition;
begin
  if FPosition = AValue then Exit;
  old := FPosition;
  FPosition := AValue;
  if not FShowing then Exit;
  Restyle;             // re-place in the new corner (and re-stack it)
  ReflowStack(old);    // and let the corner it left close the gap
end;

procedure TTyNotification.SetClosable(AValue: Boolean);
begin
  if FClosable = AValue then Exit;
  FClosable := AValue;
  if not FClosable then
  begin
    // Drop any live x state, or a card that loses its glyph keeps a stale hover chip / a press
    // that would still close it on release.
    FHoverClose := False;
    FClosePressed := False;
  end;
  Restyle;
end;

procedure TTyNotification.SetShowIcon(AValue: Boolean);
begin
  if FShowIcon = AValue then Exit;
  FShowIcon := AValue;
  Restyle;   // the mark is a height floor, so dropping it can shrink the card
end;

procedure TTyNotification.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then FController.RemoveFreeNotification(Self);
  FController := AValue;
  if FController <> nil then FController.FreeNotification(Self);
  Restyle;
end;

procedure TTyNotification.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FController) then
    FController := nil;   // fall back to TyDefaultController rather than dangle
end;

// ---------------------------------------------------------------------------
// TyNotify — the fire-and-forget convenience
// ---------------------------------------------------------------------------
procedure ReapAutoToasts;
{ Free the auto toasts that have since closed. Deliberately driven from the NEXT TyNotify (and
  from finalization) rather than from a toast's own close path: that path runs inside the timer
  tick / mouse handler OF the very component that would be freed. }
var
  i: Integer;
  n: TTyNotification;
begin
  if UAuto = nil then Exit;
  for i := UAuto.Count - 1 downto 0 do
  begin
    n := TTyNotification(UAuto[i]);
    if not n.Showing then
    begin
      UAuto.Delete(i);
      n.Free;
    end;
  end;
end;

procedure TyNotify(const ATitle, AMessage: string; AType: TTyNotificationType;
  APosition: TTyNotificationPosition; ADurationMs: Integer);
var
  n: TTyNotification;
begin
  ReapAutoToasts;
  if UAuto = nil then UAuto := TFPList.Create;
  n := TTyNotification.Create(nil);
  n.Title := ATitle;
  n.Message := AMessage;
  n.NotificationType := AType;
  n.Position := APosition;
  n.Duration := ADurationMs;
  UAuto.Add(n);
  n.Show;
end;

procedure ShutdownToasts;
var
  i: Integer;
begin
  // The auto toasts first: freeing one runs Hide, which touches UStack.
  if UAuto <> nil then
  begin
    for i := UAuto.Count - 1 downto 0 do
      TTyNotification(UAuto[i]).Free;
    FreeAndNil(UAuto);
  end;
  // UStack does not own its entries — a form-owned toast outlives this and finds it nil
  // (EnterStack/LeaveStack/ReflowStack all guard for exactly that).
  FreeAndNil(UStack);
end;

finalization
  ShutdownToasts;
end.
