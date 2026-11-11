unit tyControls.Alert;
{$mode objfpc}{$H+}
{ TTyAlert — an INLINE alert banner: a themed bar that sits IN the page and says
  something, with a semantic status icon, an optional second line, an optional row of
  actions (text buttons: "Reload", "Keep Mine") and an optional close (x) glyph.

  The gap it fills: every other notice in this library is a MODAL dialog (TTyMessage
  and friends). "A bar in the form that says the connection dropped" had no semantic
  at all — it was a hand-tinted TTyPanel + TTyLabel per site, i.e. hard-coded colour.

  A GRAPHIC control (no handle), like TTyTag: an alert hosts no child controls, takes
  no focus and no keys (the x and the actions are mouse affordances), so painting
  straight onto the parent gets the corner gaps outside its rounded frame — the parent
  surface, or an image theme's photo — for free, with none of the corner-gap repair a
  windowed control needs.

  That is also why the actions are an Actions collection the banner DRAWS, not a slot for
  child buttons: a button laid over a graphic control is its sibling, and resolves the
  page behind it for its corners and its ghost fill rather than the banner's tint; hosting
  real children would mean a windowed container.

  typeKey 'TyAlert' for the bar; the x's chip + ink resolve from 'TyAlertClose' on the
  same contract as TyTagClose, and each action resolves 'TyAlertAction' in its own state. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages,
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

  { The action row's one metric: the gap in FRONT of every action — after the text column
    for the first, after the previous action for the rest. (The row ends a close gap short
    of the x, like the text does without actions.) }
  TyAlertActionGap    = 8;
  TyAlertActionGapVar = '--alert-action-gap';

  { An action's padding is NOT a metric: it is the TyAlertAction style's ordinary CSS
    `padding` (the base theme feeds it from --pad-alert-action), as a pagination cell's is
    TyPaginationItem's. These two only stand in when the resolved style sets no padding at
    all — a theme that wrote a TyAlertAction rule of its own and left it out — so that such
    an action is still a button and not a bare word. Logical px; `padding: 0` is a value
    and is honoured. }
  TyAlertActionPadX = 8;   // left and right of the caption
  TyAlertActionPadY = 2;   // above and below it

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
      CloseRect       — the square close-glyph slot (empty when not closable)
      ActionRects     — one rect per action width handed in, in that order; an empty rect
                        for an action there was no room for. No entries without actions. }
  TTyAlertLayout = record
    IconRect: TRect;
    MessageRect: TRect;
    DescriptionRect: TRect;
    CloseRect: TRect;
    ActionRects: array of TRect;
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
    AActionWidths              — the width of each VISIBLE action in collection order (its
                                 caption plus its own padding); none = no action row. The
                                 overload without the last three arguments is that case.
    AActionHeight              — the height the actions share.
    AActionGap                 — the gap in front of every action.

  Vertical: the text block (message, + gap + description when present) is centred in the
  padded band, and the slots AND the action row centre on the MESSAGE line — one rule that
  gives the familiar centred look in the one-line form and puts the icon, the actions and
  the x beside the HEADLINE in the two-line form, rather than stranding them between the
  lines.

  Horizontal: the action row sits at the trailing end of the band, a close gap before the
  x when there is one, and the text column stops an action gap before the row. When space
  runs out, in priority order: the close slot wins first (it dismisses the banner —
  TyTagLayout's rule), the actions next (they are what the banner is there to offer), the
  icon after them (it is what says WHAT kind of notice this is), and the text column takes
  the remainder, collapsing to empty rather than showing a sliver. A row too wide for what
  the x left is laid from the band's leading edge in order: the action that reaches the end
  is cut there (its caption ellipsises) and the ones after it get no rect, so the first
  action is the last to go. Padding that eats the whole banner, or a zero size, leaves
  every rect empty rather than inverted.
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer): TTyAlertLayout; overload;
function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer;
  const AActionWidths: array of Integer;
  AActionHeight, AActionGap: Integer): TTyAlertLayout; overload;

{ The banner height that shows its content whole — the inverse of TyAlertLayout: feed the
  result back in as AClientHeight (same other arguments) and the text block lands exactly
  on the padding, with both slots unsquashed. Device px throughout; this is what AutoSize
  measures to.
  It takes no WIDTH because the banner's height does not depend on one: neither line
  wraps (both are single-line and ellipsised, like every other text in this library), so
  a narrower banner shows less text at the same height rather than reflowing to a taller
  block.
  AActionHeight is the height of the action row, 0 (or the overload without it) when no
  action is visible. An action that fits beside the message line changes nothing; a taller
  one grows the banner to the smallest height at which TyAlertLayout draws it whole. That
  is not simply "at least the action's height": the row centres on the MESSAGE line, which
  uneven padding or a second line moves off the banner's centre. }
function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize: Integer): Integer; overload;
function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize, AActionHeight: Integer): Integer; overload;

type
  { One action of a banner: a command it offers beside its message ("Reload", "Keep
    Mine"). The banner draws it as a text button and reports a click through its OnAction;
    the item carries no handler of its own, so a form file holds only the five values
    below. }
  TTyAlertAction = class(TCollectionItem)
  private
    FCaption: TCaption;
    FVisible: Boolean;
    FEnabled: Boolean;
    FHint: TTranslateString;
    FTag: PtrInt;
    procedure SetCaption(const AValue: TCaption);
    procedure SetVisible(AValue: Boolean);
    procedure SetEnabled(AValue: Boolean);
  protected
    { What the collection editor lists: the caption, once there is one. }
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(Source: TPersistent); override;
  published
    { The button's text: one line, ellipsised when the banner is too narrow for it. No
      mnemonic parsing, as in the banner's own text — an '&' is a literal character. }
    property Caption: TCaption read FCaption write SetCaption;
    { A hidden action takes no room: the others close up and the message gets its width. }
    property Visible: Boolean read FVisible write SetVisible default True;
    { A disabled action keeps its place, is drawn in the :disabled look and does nothing. }
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    { Shown while the pointer rests on this action, in place of the banner's own Hint.
      Whether hints show at all is the banner's ShowHint. }
    property Hint: TTranslateString read FHint write FHint;
    { The application's: the usual way to tell the actions apart in OnAction. }
    property Tag: PtrInt read FTag write FTag default 0;
  end;

  TTyAlertActions = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyAlertAction;
    procedure SetItem(AIndex: Integer; AValue: TTyAlertAction);
  protected
    procedure Update(Item: TCollectionItem); override;   // re-fit + repaint the banner
  public
    function Add: TTyAlertAction;
    property Items[AIndex: Integer]: TTyAlertAction read GetItem write SetItem; default;
  end;

  { Fired for a click on an action: the left button went down and came up on the same
    enabled action. AAction is that item. }
  TTyAlertActionEvent = procedure(Sender: TObject; AAction: TTyAlertAction) of object;

  { Fired before the banner acts on a click of its close (x) glyph. Clearing AllowClose
    vetoes the default action (hiding the banner) so a host that owns the alert's lifetime
    can free/relocate it itself. Identical in shape and meaning to TTyTagCloseEvent — the
    two are separate types only so neither unit has to use the other. }
  TTyAlertCloseEvent = procedure(Sender: TObject; var AllowClose: Boolean) of object;

  TTyCustomAlert = class(TTyGraphicControl)
  private
    FAlertType: TTyAlertType;
    FMessage: TCaption;
    FDescription: string;
    FShowIcon: Boolean;
    FClosable: Boolean;
    FHoverClose: Boolean;     // pointer is precisely over the x
    FClosePressed: Boolean;   // this press STARTED on the x (suppresses the banner's Click)
    FOnClose: TTyAlertCloseEvent;
    FActions: TTyAlertActions;
    FOnAction: TTyAlertActionEvent;
    { The action under the pointer and the one a press started on, by collection-item ID
      (-1 = none). An ID and not a pointer or an index: the host may delete or reorder the
      actions between two mouse events, and a stale ID simply matches nothing. }
    FHoverActionID: Integer;
    FPressedActionID: Integer;   // enabled or not: the press is that action's either way
                                 // (it suppresses the banner's Click)
    { StyleOverride overlay cache. A second copy of the base class's (whose fields are
      private) — see AlertStyle for why this control cannot use inherited CurrentStyle. }
    FOvrSet: TTyStyleSet;
    FOvrText: string;
    FOvrVer: Cardinal;
    FOvrValid: Boolean;
    procedure SetAlertType(AValue: TTyAlertType);
    procedure SetMessage(const AValue: TCaption);
    procedure SetDescription(const AValue: TCaption);
    procedure SetShowIcon(AValue: Boolean);
    procedure SetClosable(AValue: Boolean);
    procedure SetActions(AValue: TTyAlertActions);
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
    { The collection changed: an action was added, removed, moved or edited. }
    procedure ActionsChanged;
    function HasVisibleActions: Boolean;
    { The height the action row is laid out with, in device px at APainter's scale: one
      line of the action's font plus its padding. ARest is ActionStyle at rest. }
    function ActionHeightWith(APainter: TTyPainter; const ARest: TTyStyleSet): Integer;
    function ActionHeightAtPPI(APPI: Integer; const ARest: TTyStyleSet): Integer;
    { What is under (X, Y), from ONE layout pass: the visible action there (nil = none), and
      whether the point is on the close glyph instead. }
    function HitTest(X, Y: Integer; out AOnClose: Boolean): TTyAlertAction;
    { The banner's Hint is the control's; an action with a Hint of its own answers for the
      pointer resting on it. }
    procedure CMHintShow(var Message: TLMessage); message CM_HINTSHOW;
  protected
    function GetStyleTypeKey: string; override;
    { The resolved TyAlert style for the CURRENT type, class and state. }
    function AlertStyle: TTyStyleSet;
    { TyAlertLayout fed from the resolved theme. AWidth/AHeight are device px (RenderTo
      passes its own rect; the hit-test passes the client size), so nothing here reads
      Width behind the caller's back. }
    function LayoutFor(AWidth, AHeight, APPI: Integer): TTyAlertLayout;
    { The state one action is drawn in: disabled (its own Enabled, or the banner's), pressed
      while the press that started on it is still over it, hovered, or at rest. During a
      press nothing else lights: the gesture belongs to where it started. }
    function ActionStates(AAction: TTyAlertAction): TTyStateSet; virtual;
    { 'TyAlertAction' for AStates under the banner's variants (so TyAlertAction.warning can
      tint the actions of a warning), with the banner's Font and StyleOverride text
      declarations laid over it as on any part. What the key leaves unset comes from ABar,
      the bar's resolved style: its ink and its font — the house rule for a secondary key —
      and, for the padding, the built-in TyAlertActionPadX/Y. }
    function ActionStyle(const ABar: TTyStyleSet; const AStates: TTyStateSet): TTyStyleSet;
    { The width of what an action shows, in device px, WITHOUT its padding: the caption in
      AStyle's font (AStyle is the action's style at rest, so the row does not shift as the
      pointer crosses it). Override together with DrawAction to show something else. }
    function ActionContentWidth(APainter: TTyPainter; AAction: TTyAlertAction;
      const AStyle: TTyStyleSet): Integer; virtual;
    { Draws one action into ARect (device px, the rect ActionRect reports): the chip and
      border AStyle has, then the caption. AStyle is the action's style in its current
      state, with the padding it was measured with. }
    procedure DrawAction(APainter: TTyPainter; AAction: TTyAlertAction; const ARect: TRect;
      const AStyle: TTyStyleSet); virtual;
    { A click on an enabled action: fires OnAction. The last thing the mouse path does, so
      a handler may hide the banner or change its actions. }
    procedure DoAction(AAction: TTyAlertAction); virtual;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { TControl.WMLButtonUp runs Click BEFORE DoMouseUp, so FClosePressed / FPressedActionID
      is still set here for a press that started on the x or on an action: that gesture is
      a close or an action, never a banner click. MouseUp (which has the release position)
      then decides whether it committed. }
    procedure Click; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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
    { The visible action at (X, Y) — client coordinates, device px — or nil. A disabled
      action is still what is there; a hidden one is not. For a host that shows its own
      menu or tooltip over an action, and for tests. }
    function ActionAt(X, Y: Integer): TTyAlertAction;
    { Where Actions[AIndex] is drawn, in DEVICE px, (0,0)-local: the rect the paint fills
      and the hit test measures against. Empty for a hidden action, one the banner had no
      room for, and an index out of range. }
    function ActionRect(AIndex: Integer): TRect;
    { The commands the banner offers, drawn as a row of text buttons at its trailing end,
      before the close glyph, each as wide as its caption; the message and the description
      get what is left. The banner takes no focus, so the actions have no keyboard path of
      their own: give the same commands a shortcut or a menu item in the application. }
    property Actions: TTyAlertActions read FActions write SetActions;
    { A click on an action. It is not the banner's OnClick and it does not close the
      banner; a handler that wants it gone hides it (or calls Close). }
    property OnAction: TTyAlertActionEvent read FOnAction write FOnAction;
    { The banner's semantic type: it picks BOTH the style variant ('info' / 'success' /
      'warning' / 'error' — the theme writes a `TyAlert.warning` rule) and the status
      glyph. Changing it re-fits an auto-sized banner, because a theme may pad a variant
      differently. }
    property AlertType: TTyAlertType read FAlertType write SetAlertType default atInfo;
    { The headline. Drawn with the resolved TyAlert style (NOT the LCL Font.*), left
      aligned, ellipsised when it does not fit, and never wrapped. No mnemonic parsing —
      a banner activates nothing, so an '&' is literal text. }
    property Message: TCaption read FMessage write SetMessage;
    { The optional second line. Setting it switches the banner to the taller two-line
      form; clearing it goes back to one line. Same drawing rules as Message. }
    property Description: TCaption read FDescription write SetDescription;
    { Draw the type's status glyph in a slot at the left. On by default: the icon is what
      makes an alert readable at a glance, and it is the one thing AlertType exists for
      beyond colour. }
    property ShowIcon: Boolean read FShowIcon write SetShowIcon default True;
    { Shows the close (x) glyph and makes it live. Clicking it runs Close (OnClose, then
      hide unless vetoed); the banner's own OnClick never fires for that gesture. }
    property Closable: Boolean read FClosable write SetClosable default False;
    property OnClose: TTyAlertCloseEvent read FOnClose write FOnClose;
  end;

  { TTyAlert publishes TTyCustomAlert's properties; everything lives in TTyCustomAlert. }
  TTyAlert = class(TTyCustomAlert)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    { With AutoSize the banner's HEIGHT hugs its content (padding + one or two lines, at
      least as tall as its slots). The WIDTH is left alone — a banner spans its host via
      Align/Anchors, and re-fitting it to its text would fight that layout. }
    property AutoSize;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    { An EXTRA variant on top of the type's own. AlertType always contributes its variant
      token first and this one is appended, so the semantic look is always there and an
      explicit class layers over it per-property — the engine's ordinary multi-token
      cascade (later token wins). A theme rule `TyAlert.compact` setting only a tighter
      padding thus trims any type of banner without touching its colours. }
    property StyleClass;
    property StyleOverride;
    property Controller;
    property AlertType;
    property Message;
    property Description;
    property ShowIcon;
    property Closable;
    property Actions;
    property OnClose;
    property OnAction;
    property Align;
    property Anchors;
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

{ Where the text block starts when it is centred in the padded band of a banner
  AClientHeight tall: a block taller than its band starts at the top edge. One function
  because the layout and the preferred height must agree on it to the pixel. }
function AlertBlockTop(AClientHeight, APadTop, APadBottom, ABlockHeight: Integer): Integer;
var
  availH: Integer;
begin
  availH := AClientHeight - APadTop - APadBottom;
  if availH < 0 then availH := 0;
  Result := APadTop + (availH - ABlockHeight) div 2;
  if Result < 0 then Result := 0;
end;

{ The rect ALayout holds for the AOrdinal-th VISIBLE action; empty when it holds none. The
  layout is built from exactly the visible actions, so the ordinal is in range whenever
  both come from the same state of the collection — the check is for the day they do not. }
function AlertVisibleActionRect(const ALayout: TTyAlertLayout; AOrdinal: Integer): TRect;
begin
  if (AOrdinal >= 0) and (AOrdinal < Length(ALayout.ActionRects)) then
    Result := ALayout.ActionRects[AOrdinal]
  else
    Result := Rect(0, 0, 0, 0);
end;

function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer): TTyAlertLayout;
begin
  Result := TyAlertLayout(AClientWidth, AClientHeight, AShowIcon, AHasDescription, AClosable,
    APadLeft, APadTop, APadRight, APadBottom, AMessageHeight, ADescriptionHeight,
    AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize, [], 0, 0);
end;

function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer;
  const AActionWidths: array of Integer;
  AActionHeight, AActionGap: Integer): TTyAlertLayout;
var
  bandL, bandR, textL, textR: Integer;
  blockH, blockT, centreY: Integer;
  closeL, iconR, slotT, slotB: Integer;
  i, w, x, r, rowW, rowR: Integer;
  rowBand: Boolean;
begin
  Result.IconRect := Rect(0, 0, 0, 0);
  Result.MessageRect := Rect(0, 0, 0, 0);
  Result.DescriptionRect := Rect(0, 0, 0, 0);
  Result.CloseRect := Rect(0, 0, 0, 0);
  Result.ActionRects := nil;
  SetLength(Result.ActionRects, Length(AActionWidths));
  for i := 0 to High(Result.ActionRects) do
    Result.ActionRects[i] := Rect(0, 0, 0, 0);
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
  if AActionGap < 0 then AActionGap := 0;

  // The content band: the banner inset by its themed horizontal padding. Padding that
  // eats the whole banner leaves nothing to lay out (every rect stays empty).
  bandL := APadLeft;
  bandR := AClientWidth - APadRight;
  if bandR <= bandL then Exit;

  // --- vertical: the text block, centred in the padded band -------------------
  blockH := AMessageHeight;
  if AHasDescription then Inc(blockH, ATextGap + ADescriptionHeight);
  blockT := AlertBlockTop(AClientHeight, APadTop, APadBottom, blockH);
  // Both slots and the action row centre on the MESSAGE line: in the one-line form that IS
  // the banner's optical centre, and in the two-line form it puts them beside the headline.
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

  // --- then the action row, out of what the close slot left --------------------
  if Length(AActionWidths) > 0 then
  begin
    // The row ends where the text would have without it: at the band edge, or a close gap
    // short of the x.
    rowR := textR;
    rowW := 0;
    for i := 0 to High(AActionWidths) do
    begin
      if AActionWidths[i] > 0 then Inc(rowW, AActionWidths[i]);
      if i > 0 then Inc(rowW, AActionGap);
    end;
    x := rowR - rowW;
    if x < bandL then x := bandL;   // too wide: laid from the band edge, and the end is cut
    textR := x - AActionGap;        // the text stops a gap short of the row
    rowBand := AlertSlotBand(centreY, AActionHeight, AClientHeight, slotT, slotB);
    for i := 0 to High(AActionWidths) do
    begin
      w := AActionWidths[i];
      if w < 0 then w := 0;
      r := x + w;
      // The action that reaches the end is cut there; one that would start past it has
      // nothing left (r <= x) and gets no rect, like every action after it.
      if r > rowR then r := rowR;
      if rowBand and (r > x) then
        Result.ActionRects[i] := Rect(x, slotT, r, slotB);
      x := r + AActionGap;
    end;
  end;

  // --- then the icon, out of what the close slot and the actions left ----------
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
begin
  Result := TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable, APadTop, APadBottom,
    AMessageHeight, ADescriptionHeight, ATextGap, AIconSize, ACloseSize, 0);
end;

function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize, AActionHeight: Integer): Integer;
var
  blockH, rowT: Integer;
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
  if AActionHeight <= 0 then Exit;
  // The action row: grow, a pixel at a time, to the first height at which TyAlertLayout
  // has the whole row inside the banner. Asked of the layout's own arithmetic rather than
  // solved for: the row centres on the message line, the line on a block centred between
  // two paddings, and each step rounds. Every two pixels of height move the row one down,
  // so both edges clear within about twice the row's height.
  repeat
    rowT := AlertBlockTop(Result, APadTop, APadBottom, blockH) + AMessageHeight div 2
      - AActionHeight div 2;
    if (rowT >= 0) and (rowT + AActionHeight <= Result) then Break;
    Inc(Result);
  until False;
end;

{ --- TTyAlertAction / TTyAlertActions ----------------------------------------- }

constructor TTyAlertAction.Create(ACollection: TCollection);
begin
  // Before inherited: adding the item to the collection already reports a change, and the
  // banner must not lay out a half-built (hidden) action.
  FVisible := True;
  FEnabled := True;
  inherited Create(ACollection);
end;

procedure TTyAlertAction.Assign(Source: TPersistent);
var
  src: TTyAlertAction;
begin
  if Source is TTyAlertAction then
  begin
    src := TTyAlertAction(Source);
    FCaption := src.FCaption;
    FVisible := src.FVisible;
    FEnabled := src.FEnabled;
    FHint := src.FHint;
    FTag := src.FTag;
    Changed(False);
  end
  else
    inherited Assign(Source);
end;

function TTyAlertAction.GetDisplayName: string;
begin
  Result := FCaption;
  if Result = '' then Result := inherited GetDisplayName;
end;

procedure TTyAlertAction.SetCaption(const AValue: TCaption);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

procedure TTyAlertAction.SetVisible(AValue: Boolean);
begin
  if FVisible = AValue then Exit;
  FVisible := AValue;
  Changed(False);
end;

procedure TTyAlertAction.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then Exit;
  FEnabled := AValue;
  Changed(False);
end;

function TTyAlertActions.GetItem(AIndex: Integer): TTyAlertAction;
begin
  Result := TTyAlertAction(inherited Items[AIndex]);
end;

procedure TTyAlertActions.SetItem(AIndex: Integer; AValue: TTyAlertAction);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyAlertActions.Add: TTyAlertAction;
begin
  Result := TTyAlertAction(inherited Add);
end;

procedure TTyAlertActions.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if GetOwner is TTyCustomAlert then TTyCustomAlert(GetOwner).ActionsChanged;
end;

{ --- TTyCustomAlert ----------------------------------------------------------- }

constructor TTyCustomAlert.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlertType := atInfo;
  FShowIcon := True;
  FClosable := False;
  FHoverClose := False;
  FClosePressed := False;
  FHoverActionID := -1;
  FPressedActionID := -1;
  FActions := TTyAlertActions.Create(Self, TTyAlertAction);
  // A drop size for the designer: wide enough to read as a banner, one line tall.
  Width := 320;
  Height := 40;
end;

destructor TTyCustomAlert.Destroy;
begin
  // Nil first: freeing the collection clears it, which reports a change, and ActionsChanged
  // must find a banner that is no longer there to re-fit.
  FreeAndNil(FActions);
  inherited Destroy;
end;

function TTyCustomAlert.GetStyleTypeKey: string;
begin
  Result := 'TyAlert';
end;

function TTyCustomAlert.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

function TTyCustomAlert.HasDescription: Boolean;
begin
  Result := FDescription <> '';
end;

function TTyCustomAlert.StyleVariant: string;
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

function TTyCustomAlert.AlertStyle: TTyStyleSet;
var
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  // NOT inherited CurrentStyle: that resolves with StyleClass ALONE, and it cannot know
  // about AlertType — the whole point here is that the type contributes a variant token.
  Result := model.ResolveStyle(GetStyleTypeKey, StyleVariant, CurrentStates);
  TyApplyControlFont(Result, Self, CurrentStates);   // the alert's own font, as CurrentStyle lays it (#113)
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

procedure TTyCustomAlert.Refit;
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

procedure TTyCustomAlert.SetAlertType(AValue: TTyAlertType);
begin
  if FAlertType = AValue then Exit;
  FAlertType := AValue;
  // More than a repaint: the variant is a different theme rule, which may pad or size
  // its text differently.
  Refit;
end;

procedure TTyCustomAlert.SetMessage(const AValue: TCaption);
begin
  if FMessage = AValue then Exit;
  FMessage := AValue;
  // Height comes from a reference glyph, not from this text, and the width is never
  // measured — so new headline text is a pure repaint.
  Invalidate;
end;

procedure TTyCustomAlert.SetDescription(const AValue: TCaption);
begin
  if FDescription = AValue then Exit;
  // '' <-> text is the one-line/two-line switch: a height change, not a repaint.
  FDescription := AValue;
  Refit;
end;

procedure TTyCustomAlert.SetShowIcon(AValue: Boolean);
begin
  if FShowIcon = AValue then Exit;
  FShowIcon := AValue;
  Refit;   // the icon slot is a height floor as well as a left inset
end;

procedure TTyCustomAlert.SetClosable(AValue: Boolean);
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

procedure TTyCustomAlert.SetActions(AValue: TTyAlertActions);
begin
  FActions.Assign(AValue);
end;

procedure TTyCustomAlert.ActionsChanged;
begin
  if FActions = nil then Exit;   // being destroyed
  // An action appearing, going or changing can move the height an auto-sized banner fits
  // (the row may be taller than the line) as well as what is drawn.
  Refit;
end;

function TTyCustomAlert.HasVisibleActions: Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to FActions.Count - 1 do
    if FActions[i].Visible then Exit(True);
end;

{ --- the close gesture -------------------------------------------------------- }

procedure TTyCustomAlert.Close;
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

function TTyCustomAlert.LineHeightWith(APainter: TTyPainter; const AStyle: TTyStyleSet): Integer;
begin
  // A stable reference glyph: an empty Message still sizes the banner to a line.
  Result := APainter.MeasureText('Ag', AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight).cy;
  if Result < 1 then Result := 1;
end;

function TTyCustomAlert.LineHeightAtPPI(APPI: Integer; const AStyle: TTyStyleSet): Integer;
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

function TTyCustomAlert.LayoutWith(APainter: TTyPainter; const AStyle: TTyStyleSet;
  AWidth, AHeight: Integer): TTyAlertLayout;
var
  lineH, actionH, i, n: Integer;
  rest: TTyStyleSet;
  widths: array of Integer;
begin
  lineH := LineHeightWith(APainter, AStyle);
  widths := nil;
  actionH := 0;
  if HasVisibleActions then
  begin
    // Measured at REST, whatever state each action is in: the row must not shift as the
    // pointer crosses it or a button goes down.
    rest := ActionStyle(AStyle, [tysNormal]);
    actionH := ActionHeightWith(APainter, rest);
    SetLength(widths, FActions.Count);
    n := 0;
    for i := 0 to FActions.Count - 1 do
      if FActions[i].Visible then
      begin
        widths[n] := ActionContentWidth(APainter, FActions[i], rest)
          + APainter.Scale(rest.Padding.Left) + APainter.Scale(rest.Padding.Right);
        Inc(n);
      end;
    SetLength(widths, n);
  end;
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
    APainter.Scale(ActiveController.Metric(TyAlertCloseSizeVar, TyAlertCloseSize)),
    widths, actionH,
    // StyleMetric: a banner can set the gap for itself in its StyleOverride.
    APainter.Scale(StyleMetric(TyAlertActionGapVar, TyAlertActionGap)));
  { #153: mirrored, the glyph, the text, the actions and the close button change sides; the
    painter is armed in RenderTo, so the text's alignment follows }
  if IsRightToLeft then
  begin
    for i := 0 to High(Result.ActionRects) do
      Result.ActionRects[i] := TyMirrorRectX(Result.ActionRects[i], AWidth);
    Result.IconRect := TyMirrorRectX(Result.IconRect, AWidth);
    Result.MessageRect := TyMirrorRectX(Result.MessageRect, AWidth);
    Result.DescriptionRect := TyMirrorRectX(Result.DescriptionRect, AWidth);
    Result.CloseRect := TyMirrorRectX(Result.CloseRect, AWidth);
  end;
end;

function TTyCustomAlert.LayoutFor(AWidth, AHeight, APPI: Integer): TTyAlertLayout;
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

function TTyCustomAlert.TyAlertCloseRect: TRect;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch).CloseRect;
end;

function TTyCustomAlert.TyAlertIconRect: TRect;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch).IconRect;
end;

function TTyCustomAlert.PtOnClose(X, Y: Integer): Boolean;
var
  R: TRect;
begin
  // Asked only on the release of a press that started on the x.
  R := TyAlertCloseRect;
  Result := (R.Right > R.Left) and (X >= R.Left) and (X < R.Right)
    and (Y >= R.Top) and (Y < R.Bottom);
end;

procedure TTyCustomAlert.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, lineH, actionH: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := AlertStyle;
  lineH := LineHeightAtPPI(ppi, S);
  // The action row as LayoutWith measures it; no visible action, no row.
  actionH := 0;
  if HasVisibleActions then
    actionH := ActionHeightAtPPI(ppi, ActionStyle(S, [tysNormal]));
  // 0 = "no preferred width" (the LCL convention: keep the bounds you were given).
  // AutoSize hugs the HEIGHT only — a banner spans its host via Align/Anchors.
  PreferredWidth := 0;
  PreferredHeight := TyAlertPreferredHeight(FShowIcon, HasDescription, FClosable,
    MulDiv(S.Padding.Top, ppi, 96), MulDiv(S.Padding.Bottom, ppi, 96),
    lineH, lineH,
    MulDiv(ActiveController.Metric(TyAlertTextGapVar, TyAlertTextGap), ppi, 96),
    MulDiv(ActiveController.Metric(TyAlertIconSizeVar, TyAlertIconSize), ppi, 96),
    MulDiv(ActiveController.Metric(TyAlertCloseSizeVar, TyAlertCloseSize), ppi, 96),
    actionH);
end;

{ --- the action row ----------------------------------------------------------- }

function TTyCustomAlert.ActionStates(AAction: TTyAlertAction): TTyStateSet;
begin
  if (not IsEnabled) or (not AAction.Enabled) then Exit([tysDisabled]);
  Result := [];
  if FPressedActionID >= 0 then
  begin
    // A press that started on an action: that action alone answers, pressed while the
    // pointer is still on it and at rest once it is dragged off, like any push button.
    if (AAction.ID = FPressedActionID) and (AAction.ID = FHoverActionID) then
      Result := [tysHover, tysActive];
  end
  else if (AAction.ID = FHoverActionID) and not (FPressed or FClosePressed) then
    // No press anywhere: the action under the pointer lights. A press on the bar or on the
    // x that wanders over an action does not light it.
    Result := [tysHover];
  if Result = [] then Include(Result, tysNormal);
end;

function TTyCustomAlert.ActionStyle(const ABar: TTyStyleSet;
  const AStates: TTyStateSet): TTyStyleSet;
begin
  // The disabled look keeps the theme's ink: the banner's Font.Color or StyleOverride
  // colour is its live ink, and laid over :disabled it would make the action look live.
  Result := PartStyle('TyAlertAction', StyleVariant, AStates, not (tysDisabled in AStates));
  // The house degradation rule for a secondary key (TyAlertClose, TyPaginationItem): what
  // it does not set is the bar's -- never a hard-coded colour or font.
  if not (tpTextColor in Result.Present) then
  begin
    Result.TextColor := ABar.TextColor;
    if tpTextColor in ABar.Present then Include(Result.Present, tpTextColor);
  end;
  if not (tpFontName in Result.Present) then
  begin
    Result.FontName := ABar.FontName;
    if tpFontName in ABar.Present then Include(Result.Present, tpFontName);
  end;
  if not (tpFontSize in Result.Present) then
  begin
    Result.FontSize := ABar.FontSize;
    if tpFontSize in ABar.Present then Include(Result.Present, tpFontSize);
  end;
  if not (tpFontWeight in Result.Present) then
  begin
    Result.FontWeight := ABar.FontWeight;
    if tpFontWeight in ABar.Present then Include(Result.Present, tpFontWeight);
  end;
  if not (tpPadding in Result.Present) then
  begin
    Result.Padding := Rect(TyAlertActionPadX, TyAlertActionPadY,
      TyAlertActionPadX, TyAlertActionPadY);
    Include(Result.Present, tpPadding);
  end;
end;

function TTyCustomAlert.ActionContentWidth(APainter: TTyPainter; AAction: TTyAlertAction;
  const AStyle: TTyStyleSet): Integer;
begin
  Result := APainter.MeasureText(AAction.Caption, AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight).cx;
end;

function TTyCustomAlert.ActionHeightWith(APainter: TTyPainter;
  const ARest: TTyStyleSet): Integer;
begin
  Result := LineHeightWith(APainter, ARest) + APainter.Scale(ARest.Padding.Top)
    + APainter.Scale(ARest.Padding.Bottom);
end;

function TTyCustomAlert.ActionHeightAtPPI(APPI: Integer; const ARest: TTyStyleSet): Integer;
var
  P: TTyPainter;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // canvas-less: measures, draws nothing
    Result := ActionHeightWith(P, ARest);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomAlert.DrawAction(APainter: TTyPainter; AAction: TTyAlertAction;
  const ARect: TRect; const AStyle: TTyStyleSet);
var
  padL, padR, t: Integer;
  txtR: TRect;
begin
  // No background in this state -> no chip, and the caption still draws: that is the quiet
  // text button, and how a theme that lights the chip only under :hover gets it.
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, TyEffectiveCorners(AStyle),
      TyBorderVisible(AStyle));
  if TyBorderVisible(AStyle) then
    APainter.StrokeBorder(ARect, TyEffectiveCorners(AStyle), AStyle.BorderWidth,
      AStyle.BorderColor);
  padL := APainter.Scale(AStyle.Padding.Left);
  padR := APainter.Scale(AStyle.Padding.Right);
  if IsRightToLeft then
  begin
    // The rect was mirrored by the layout; its leading padding is on the right now.
    t := padL;
    padL := padR;
    padR := t;
  end;
  // The caption keeps clear of the horizontal padding and centres in the rect's whole
  // height: a rect squashed by a short banner has nothing left to inset. An action the
  // banner had to cut ellipsises here.
  txtR := Rect(ARect.Left + padL, ARect.Top, ARect.Right - padR, ARect.Bottom);
  if txtR.Right > txtR.Left then
    APainter.DrawText(txtR, AAction.Caption, AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, AStyle.TextColor, taCenter, tlCenter, True);
end;

procedure TTyCustomAlert.DoAction(AAction: TTyAlertAction);
begin
  if Assigned(FOnAction) then FOnAction(Self, AAction);
end;

function TTyCustomAlert.ActionRect(AIndex: Integer): TRect;
var
  lay: TTyAlertLayout;
  i, n: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (AIndex < 0) or (AIndex >= FActions.Count) or not FActions[AIndex].Visible then Exit;
  // The layout knows only the visible actions: this one's place among them.
  n := 0;
  for i := 0 to AIndex - 1 do
    if FActions[i].Visible then Inc(n);
  lay := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch);
  Result := AlertVisibleActionRect(lay, n);
end;

function TTyCustomAlert.HitTest(X, Y: Integer; out AOnClose: Boolean): TTyAlertAction;
var
  lay: TTyAlertLayout;
  i, n: Integer;
  p: TPoint;
begin
  AOnClose := False;
  Result := nil;
  // A banner with neither has nothing to hit, and pays for no layout on a mouse move.
  if not (FClosable or HasVisibleActions) then Exit;
  lay := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch);
  p := Point(X, Y);
  if FClosable and PtInRect(lay.CloseRect, p) then
  begin
    AOnClose := True;
    Exit;
  end;
  n := 0;
  for i := 0 to FActions.Count - 1 do
    if FActions[i].Visible then
    begin
      if PtInRect(AlertVisibleActionRect(lay, n), p) then Exit(FActions[i]);
      Inc(n);
    end;
end;

function TTyCustomAlert.ActionAt(X, Y: Integer): TTyAlertAction;
var
  overClose: Boolean;
begin
  Result := HitTest(X, Y, overClose);
end;

procedure TTyCustomAlert.CMHintShow(var Message: TLMessage);
var
  info: PHintInfo;
  lay: TTyAlertLayout;
  i, n, lo, hi: Integer;
  r: TRect;
  p: TPoint;
  any: Boolean;
begin
  info := PHintInfo(Message.LParam);
  any := False;
  for i := 0 to FActions.Count - 1 do
    if FActions[i].Visible and (FActions[i].Hint <> '') then
    begin
      any := True;
      Break;
    end;
  if (info = nil) or not any then
  begin
    inherited;
    Exit;
  end;
  lay := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch);
  p := info^.CursorPos;
  lo := 0;
  hi := ClientWidth;
  n := 0;
  for i := 0 to FActions.Count - 1 do
  begin
    if not FActions[i].Visible then Continue;
    r := AlertVisibleActionRect(lay, n);
    Inc(n);
    if r.Right <= r.Left then Continue;
    if PtInRect(r, p) then
    begin
      // On an action: its hint when it has one, the banner's otherwise. Leaving the action
      // asks again either way.
      if FActions[i].Hint <> '' then info^.HintStr := FActions[i].Hint;
      info^.CursorRect := r;
      inherited;
      Exit;
    end;
    if (p.X >= r.Left) and (p.X < r.Right) then
    begin
      // Above or below an action: that strip, so moving onto the action asks again.
      if p.Y < r.Top then
        info^.CursorRect := Rect(r.Left, 0, r.Right, r.Top)
      else
        info^.CursorRect := Rect(r.Left, r.Bottom, r.Right, ClientHeight);
      inherited;
      Exit;
    end;
    if (r.Right <= p.X) and (r.Right > lo) then lo := r.Right;
    if (r.Left > p.X) and (r.Left < hi) then hi := r.Left;
  end;
  // Beside the row: the stretch up to the nearest action on either side, so reaching one
  // asks again.
  info^.CursorRect := Rect(lo, 0, hi, ClientHeight);
  inherited;
end;

{ --- input -------------------------------------------------------------------- }

procedure TTyCustomAlert.Click;
begin
  // A banner that drew nothing (no themed background) must not fire OnClick either: the input
  // has to honour the paint's "no banner at all" decision, or a click on apparent blank space
  // fires OnClick for a control the user cannot see.
  if not (tpBackground in AlertStyle.Present) then Exit;
  // See the declaration: Click runs BEFORE MouseUp, so a still-set FClosePressed means
  // this press started on the x — the close gesture owns it, the banner's OnClick does
  // not fire. The flag is consumed in MouseUp, which knows where the release landed.
  // A press that started on an action is the action's in the same way, whether or not the
  // action is enabled: a dead button is not a way to click the banner behind it.
  if FClosePressed or (FPressedActionID >= 0) then Exit;
  inherited Click;
end;

procedure TTyCustomAlert.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  closeHit: Boolean;
  act: TTyAlertAction;
  actID: Integer;
begin
  if not IsEnabled then Exit;
  // A background-less (theme-degraded) alert paints NOTHING — the input must agree it is not
  // there, or it swallows clicks and (over the invisible x's slot) can even hide itself.
  if not (tpBackground in AlertStyle.Present) then Exit;
  // Hit-test the close x and the actions on the RESTING geometry, BEFORE inherited
  // MouseDown sets FPressed: FPressed makes AlertStyle resolve the :active variant, whose
  // padding can move the close rect and the action row off what is painted (at rest), so a
  // press squarely on the visible x or action reads as a body press.
  actID := -1;
  act := HitTest(X, Y, closeHit);
  // Read now: inherited runs OnMouseDown, and a handler may change the collection.
  if act <> nil then actID := act.ID;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FClosePressed := closeHit;
  FPressedActionID := actID;
  // A press is also where the pointer is: a press with no move before it (a touch) still
  // shows the pressed look.
  if actID >= 0 then FHoverActionID := actID;
  if FClosePressed or (FPressedActionID >= 0) then
  begin
    // The gesture belongs to the x or the action, not the banner: undo the base's press
    // state so the whole bar doesn't flip to :active behind it.
    FPressed := False;
    Invalidate;
  end;
end;

procedure TTyCustomAlert.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  wasClose, overClose: Boolean;
  pressedID: Integer;
  act: TTyAlertAction;
begin
  wasClose := FClosePressed;
  FClosePressed := False;
  // Only the left button ends a press on an action: another button going up while the left
  // one is held neither fires the action nor hands the click to the banner.
  pressedID := -1;
  if Button = mbLeft then
  begin
    pressedID := FPressedActionID;
    FPressedActionID := -1;
  end;
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  // Press AND release both on the x commit the close; dragging off it cancels the whole
  // gesture (no OnClose, and Click already swallowed the OnClick) like any push button.
  if wasClose then
  begin
    if PtOnClose(X, Y) then Close;
  end
  else if pressedID >= 0 then
  begin
    // The same rule for an action: down and up on the SAME one, and it must still be there
    // and still enabled -- the host may have changed the collection in between.
    act := HitTest(X, Y, overClose);
    if (act <> nil) and (act.ID = pressedID) and act.Enabled and IsEnabled then
      DoAction(act);   // last: the handler may hide the banner or change its actions
  end;
end;

procedure TTyCustomAlert.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  overClose: Boolean;
  act: TTyAlertAction;
  id: Integer;
begin
  if not IsEnabled then Exit;
  inherited MouseMove(Shift, X, Y);
  act := HitTest(X, Y, overClose);
  id := -1;
  if act <> nil then id := act.ID;
  if (FHoverClose <> overClose) or (FHoverActionID <> id) then
  begin
    FHoverClose := overClose;
    FHoverActionID := id;
    Invalidate;
  end;
end;

procedure TTyCustomAlert.MouseLeave;
begin
  inherited MouseLeave;   // clears the bar's own hover
  if FHoverClose or (FHoverActionID >= 0) then
  begin
    FHoverClose := False;
    FHoverActionID := -1;
    Invalidate;
  end;
end;

{ --- painting ----------------------------------------------------------------- }

procedure TTyCustomAlert.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, closeS, restS, actS: TTyStyleSet;
  R, actR: TRect;
  Lay: TTyAlertLayout;
  fs, i, n: Integer;
  closeStates: TTyStateSet;
  glyphColor: TTyColor;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at
    // ARect.Left/Top, so a non-zero ARect origin would shift the banner.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    { #153: mirrored, the glyph, the text and the close button change sides; the layout is
      written for reading order and the painter turns it }
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
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

    if Length(Lay.ActionRects) > 0 then
    begin
      // Each action resolves TyAlertAction in its OWN state -- hovering precisely that
      // action lights TyAlertAction:hover -- but is drawn with the padding the layout
      // measured it with, the resting one.
      restS := ActionStyle(S, [tysNormal]);
      n := 0;
      for i := 0 to FActions.Count - 1 do
      begin
        if not FActions[i].Visible then Continue;
        actR := AlertVisibleActionRect(Lay, n);
        Inc(n);
        if actR.Right <= actR.Left then Continue;   // the banner had no room for this one
        actS := ActionStyle(S, ActionStates(FActions[i]));
        actS.Padding := restS.Padding;
        DrawAction(P, FActions[i], actR, actS);
      end;
    end;

    if Lay.CloseRect.Right > Lay.CloseRect.Left then
    begin
      // The x's chip and ink are their own typeKey, resolved with the BANNER's variants
      // (so TyAlertClose.error can tint the x of an error alert) and with the state of the
      // GLYPH, not the bar — hovering precisely the x is what lights TyAlertClose:hover.
      closeStates := [];
      if not IsEnabled then
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

procedure TTyCustomAlert.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
