unit tyControls.Popover;
{$mode objfpc}{$H+}

{ TTyPopover — a themed popup that can HOST REAL CONTROLS.

  The gap it fills is functional, not cosmetic: TTyHint and TTyBalloonHint can only show
  TEXT. There is currently no way at all to pop a small panel with a couple of buttons in
  it beside a control — the "are you sure? [Yes] [No]" flyout, the little colour/format
  editor hanging off a toolbar button, the filter box. Popconfirm is that pattern, and it
  is built on this.

  It is a NON-VISUAL COMPONENT (the TTyBalloonHint / TTyNotification pattern): drop one on
  a form, point Content at the container you filled in the designer, point Target at the
  control it belongs to, and call Show. It cannot be an in-place control because it must
  float ABOVE everything — including windowed controls, which clip anything painted on the
  form's own canvas — so, exactly like TTyPopupSurface and TTyBalloonHint, it OWNS A WINDOW:
  a bare borderless fsStayOnTop form that paints the body + arrow with TTyPainter.

  Why Content is a control the app already owns, rather than a container this component
  creates: the whole point is that the app puts REAL controls inside, and the only place a
  developer can build those is the designer, on a form. So the popup ADOPTS an existing
  container into its window on Show and RELEASES it back to its original parent on Hide —
  TTyPopupSurface's battle-tested AdoptContent/ReleaseContent, which is how the ribbon
  already moves live control trees into a flyout.

  Everything that is a RULE — where the popup lands, which way it flips, what its frame
  holds — is a free function taking plain ints, so the whole geometry is exercisable with
  no window and no screen. Only putting the window up needs a real machine; verify the LOOK
  there (and note the arrow/border cosmetic in DrawArrow). }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.StyleModel;

const
  { Built-in logical-px defaults (96-PPI baseline) for the popover's own metrics. A skin
    retunes each through the named theme metric beside it (the v3/C convention); these are
    only what a theme that sets none of them falls back to. Every one is scaled to device px
    at its call site. }
  TyPopoverArrowSize = 8;   // the arrow's HALF-BASE and its strip thickness (TTyBalloonHint's
                            // pointer does both with one number, and the two must agree or
                            // the triangle stops being a right-angled 45 deg wedge)
  TyPopoverOffset    = 4;   // gap between the anchor's edge and the popup FRAME's near edge
  TyPopoverTitleGap  = 6;   // gap between the title line and the content

  { The metric token each constant backs. Named constants rather than inline literals because
    several call sites (the layout, the measurement, the tests) must agree on the spelling —
    a typo in one would silently fall back to the default and the geometry would drift from
    the measurement. }
  TyPopoverArrowSizeVar = '--popover-arrow-size';
  TyPopoverOffsetVar    = '--popover-offset';
  TyPopoverTitleGapVar  = '--popover-title-gap';

type
  { Which side OF THE ANCHOR the popup body sits on. psvTop means the body is ABOVE the
    anchor (and its arrow therefore hangs off its own BOTTOM edge). }
  TTyPopoverSide = (psvTop, psvBottom, psvLeft, psvRight);

  { Where the popup sits along the edge it shares with the anchor. palStart/palEnd line the
    popup's near/far edge up with the anchor's; palCenter centres it. }
  TTyPopoverAlign = (palStart, palCenter, palEnd);

  { The twelve placements, named as Ant Design names them: the side first, then the
    alignment along it. Deliberately a flat enum rather than a (side, align) pair of
    properties: this is the ONE thing a designer sets, and one drop-down of twelve reads
    better than two that can be combined into the same twelve. TyPopoverSide/TyPopoverAlign
    split it back apart for the rules. }
  TTyPopoverPlacement = (
    ppTop, ppTopLeft, ppTopRight,
    ppBottom, ppBottomLeft, ppBottomRight,
    ppLeft, ppLeftTop, ppLeftBottom,
    ppRight, ppRightTop, ppRightBottom);

  { Where the popup window goes and where its arrow points. Frame/TipX/TipY are in the SAME
    coordinate space as the work area handed to TyPopoverPlace (screen px at runtime; the
    tests pass a synthetic rect, which is exactly why it is a parameter).
      Frame   — the whole popup window: the body PLUS the arrow strip on the anchor side.
      Side    — the side actually used, AFTER any flip. Never assume it is the requested one.
      Flipped — True when the requested side had no room and the opposite one did.
      TipX/Y  — the arrow's apex, ON the frame's near edge, aimed at the anchor's centre. }
  TTyPopoverGeometry = record
    Frame: TRect;
    Side: TTyPopoverSide;
    Flipped: Boolean;
    TipX, TipY: Integer;
  end;

  { The insides of the popup frame, in DEVICE px relative to the frame's top-left. Every rect
    may be EMPTY, and empty always means "there is nothing here" — never "it moved".
      BodyRect    — the rounded body (the frame minus the arrow strip). Empty => the strip
                    ate the whole frame, so there is no popup to draw at all.
      ArrowRect   — the triangle's bounding box (empty => no arrow).
      ArrowTip    — the triangle's apex, on the frame's near edge.
      TitleRect   — the title's line band (empty => no title, or nothing fits).
      ContentRect — where the hosted control is put (empty => nothing fits). }
  TTyPopoverLayout = record
    BodyRect: TRect;
    ArrowRect: TRect;
    ArrowTip: TPoint;
    TitleRect: TRect;
    ContentRect: TRect;
  end;

{ --- Pure rules / geometry (headless-testable; no component, no window, no theme) ------- }

{ The side of the anchor a placement puts the body on. }
function TyPopoverSide(APlacement: TTyPopoverPlacement): TTyPopoverSide;

{ The alignment a placement asks for along the shared edge. }
function TyPopoverAlign(APlacement: TTyPopoverPlacement): TTyPopoverAlign;

{ Re-compose a placement from its two halves — the inverse of the two functions above, and
  what a flip needs: flipping changes only the SIDE, and the user's alignment must survive
  it (a ppBottomLeft that flips is a ppTopLeft, never a ppTop). }
function TyPopoverPlacementOf(ASide: TTyPopoverSide; AAlign: TTyPopoverAlign): TTyPopoverPlacement;

{ The side a flip lands on. }
function TyPopoverOppositeSide(ASide: TTyPopoverSide): TTyPopoverSide;

{ True when the popup stacks along the Y axis (above/below the anchor), so its arrow strip
  eats HEIGHT and its alignment slides along X. A flip never changes this — that is the
  whole reason the frame can be measured before the flip is known. }
function TyPopoverSideIsVertical(ASide: TTyPopoverSide): Boolean;

{ Where an AFrameW x AFrameH popup goes, and which way its arrow points.
    AAnchor    — the control's rect, in the same space as AWorkArea.
    AFrameW/H  — the whole window, arrow strip included (TyPopoverFrameSize computes it).
    APlacement — what the user asked for.
    AOffset    — gap between the anchor's edge and the frame's near edge.
    AArrowSize — the arrow's half-base; needed here only to keep the tip far enough from the
                 frame's corners that the triangle's base still lands ON the frame.

  Main axis (the side): the requested side is honoured when the frame fits between the anchor
  and the work-area edge. When it does not and the OPPOSITE side does, the popup FLIPS — that
  is the entire overflow strategy on this axis, and it is why a popover never covers the thing
  it belongs to. When NEITHER side fits, the requested side is kept: there is no right answer
  left, so the caller's own request wins rather than a second wrong one.
  The frame is deliberately NOT clamped along this axis: a popup that slides away from its
  anchor stops reading as belonging to it, and its arrow would be pointing at nothing.

  Cross axis (the alignment): aligned as asked, then CLAMPED into the work area — here sliding
  is exactly right, because the popup stays beside its anchor either way. The tip is aimed at
  the anchor's centre and then clamped into the frame, so a popup that had to slide keeps a
  well-formed arrow (it just no longer points at the middle).

  Headless-safe: no control state, no handle, no screen — the tests call it directly. }
function TyPopoverPlace(const AAnchor: TRect; AFrameW, AFrameH: Integer;
  const AWorkArea: TRect; APlacement: TTyPopoverPlacement;
  AOffset, AArrowSize: Integer): TTyPopoverGeometry;

{ The tip's frame-local cross-axis coordinate — the one number TyPopoverLayout needs out of a
  geometry, and the only place the two coordinate spaces meet. }
function TyPopoverTipLocal(const AGeometry: TTyPopoverGeometry): Integer;

{ Pure geometry for the frame's insides. All inputs/outputs are DEVICE px.
    AFrameW/H  — the whole window.
    ASide      — the side the popup ACTUALLY landed on (post-flip); it decides which edge the
                 arrow strip is carved out of.
    ATipLocal  — the tip's cross-axis coordinate, frame-local (TyPopoverTipLocal).
    AShowArrow — carve the strip at all. Off => the body IS the frame.
    AHasTitle  — reserve the title's line at the top of the content band.
    APadL..B   — the themed padding (the content band's insets INSIDE the body).
    ATitleH    — the measured title line height.
    ATitleGap  — the gap between the title and the content; spent only when BOTH are there.
    AArrowSize — the arrow's half-base and the strip's thickness.

  The frame is carved in one order: strip, then body, then padding, then title, then content.
  The content is the only elastic part, and it collapses to empty rather than showing a sliver
  — a frame too small for its content is a mis-measured popover, not a layout to defend.
  A degenerate frame (zero/negative size, padding that eats the body, a strip thicker than the
  frame) leaves every rect empty rather than inverted. }
function TyPopoverLayout(AFrameW, AFrameH: Integer; ASide: TTyPopoverSide; ATipLocal: Integer;
  AShowArrow, AHasTitle: Boolean;
  APadL, APadT, APadR, APadB, ATitleH, ATitleGap, AArrowSize: Integer): TTyPopoverLayout;

{ The frame that holds AContentW x AContentH of content whole — the INVERSE of TyPopoverLayout:
  feed the result back in as AFrameW/AFrameH (same other arguments) and ContentRect comes out
  exactly AContentW x AContentH. Device px throughout; this is what Show measures to.
  Note the width is not a function of the title: the title is single-line and ellipsised (like
  every other text in this library), so a long one shows 'Confirm dele…' rather than stretching
  the popup out from under its content. }
function TyPopoverFrameSize(AContentW, AContentH: Integer; ASide: TTyPopoverSide;
  AShowArrow, AHasTitle: Boolean;
  APadL, APadT, APadR, APadB, ATitleH, ATitleGap, AArrowSize: Integer): TSize;

{ The arrow triangle's three points, frame-local: the apex plus its two base corners, derived
  from a layout's ArrowRect + ArrowTip. False (and untouched outs) when there is no arrow.
  Split out of the paint so the triangle the window fills is a rule the tests can read. }
function TyPopoverArrowPoints(const ALayout: TTyPopoverLayout; ASide: TTyPopoverSide;
  out ATip, ABase1, ABase2: TPoint): Boolean;

type
  TTyPopover = class;

  { The popover's window. A plain borderless TForm (TTyBalloonHint's shell) rather than a
    TTyPopupSurface, because a popover needs three things that surface does not offer: an
    arrow, a title, and a dismiss rule the app can turn OFF (CloseOnClickOutside). What it
    DOES borrow from TTyPopupSurface is the hard-won Color lesson — see TTyPopover.Show.

    It holds no state of its own: it paints by calling back into the component, so the card
    is fully renderable with no window at all. }
  TTyPopoverWindow = class(TForm)
  private
    FOwnerPop: TTyPopover;
    FSide: TTyPopoverSide;
    FTipLocal: Integer;
    { Cut the window to the body's rounded silhouette OR-ed with the arrow triangle, so the
      pixels outside it are not the form's Color in a square block. No-op on Wayland (no
      XShape — the popup simply keeps square corners and a square arrow strip), which is
      TTyBalloonHint's rule verbatim. }
    procedure ApplyShape;
    procedure DoDeactivate(Sender: TObject);
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); reintroduce;
  end;

  TTyPopover = class(TComponent)
  private
    FTarget: TControl;
    FContent: TWinControl;
    FPlacement: TTyPopoverPlacement;
    FTitle: string;
    FShowArrow: Boolean;
    FCloseOnClickOutside: Boolean;
    FCloseOnEscape: Boolean;
    FStyleClass: string;
    FController: TTyStyleController;
    FOnShow: TNotifyEvent;
    FOnHide: TNotifyEvent;
    FWin: TTyPopoverWindow;
    FShowing: Boolean;
    { The content's own life before we borrowed it, restored verbatim on Hide. FAdopted is
      the guard rather than "FContent <> nil": Content is a published property that outlives
      the popup, so its being set says nothing about whether we currently hold it. }
    FAdopted: Boolean;
    FOrigParent: TWinControl;
    FOrigAlign: TAlign;
    FOrigBounds: TRect;
    FOrigVisible: Boolean;
    procedure SetTarget(AValue: TControl);
    procedure SetContent(AValue: TWinControl);
    procedure SetPlacement(AValue: TTyPopoverPlacement);
    procedure SetTitle(const AValue: string);
    procedure SetShowArrow(AValue: Boolean);
    procedure SetStyleClass(const AValue: string);
    procedure SetController(AValue: TTyStyleController);
    { The theme metrics in LOGICAL px (each call site scales). Named helpers rather than
      inline Metric() calls so a typo cannot strand one call site on the default. }
    function ArrowSizeLogical: Integer;
    function OffsetLogical: Integer;
    function TitleGapLogical: Integer;
    { Adopt / release the Content control. The TTyPopupSurface contract: its original parent,
      align, bounds and visibility are remembered and restored, so a container the designer
      shows on the form (or, more usually, one left Visible=False there) comes back exactly
      as it was. }
    procedure AdoptContent;
    procedure ReleaseContent;
    { Create the window (if this is the first Show) and paint it with the body's own surface
      colour. Split out of ShowAt so BeginShowing has somewhere to adopt the content INTO. }
    procedure EnsureWindow;
  protected
    { Everything a Show does EXCEPT putting the window on screen: place by rule, point the
      window's arrow, adopt the content and bound it to the frame's content rect. ShowAt does
      this and then shows. Split so the whole placement / adoption / lifetime rule set is
      drivable headlessly, which is exactly how the tests reach it — a real Show needs a
      handle the headless runner has not got. AWorkArea is a parameter for the same reason.
      Returns the geometry it placed to. }
    function BeginShowing(const AAnchorScreen, AWorkArea: TRect;
      APPI: Integer): TTyPopoverGeometry;
    { The two typeKeys, resolved with the user's StyleClass. }
    function PopoverStyle: TTyStyleSet;
    function TitleStyle: TTyStyleSet;
    { A non-visual component has no Font of its own, so the theme is the ONLY source: pass
      ParentFont=True / size 0 and let TyResolveFontSize fall through to --font-size-base. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { The title's three text values, each falling back to the BODY's when TyPopoverTitle does
      not declare it — the graceful-degradation rule: an undefined title key inherits the
      popup's own ink/font, and never a hard-coded one. }
    procedure TitleFont(out AName: string; out ASize, AWeight: Integer);
    function TitleInk: TTyColor;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; ASide: TTyPopoverSide;
      ATipLocal, APPI: Integer);
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The controller whose theme this popover resolves against — never FController directly:
      a popover themed by the global default has Controller = nil. }
    function ActiveController: TTyStyleController;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The typeKeys this component resolves. Not an ITyStyleable: the controller's styleable
      registry holds TControls, and a non-visual component is not one — so the keys are plain
      class functions, for the tests and for the theme docs. }
    class function StyleTypeKey: string;
    class function TitleStyleTypeKey: string;
    { Pop up beside Target. Inert with no Target (and at design time — a popover is a runtime
      gesture, not a preview). }
    procedure Show;
    { Pop up beside an arbitrary control. Does NOT change Target. }
    procedure ShowFor(AControl: TControl);
    { Pop up beside an arbitrary screen rect — the seam the two above funnel through, for a
      host that anchors to something that is not a control (a grid cell, a glyph). }
    procedure ShowAt(const AAnchorScreen: TRect);
    { Put it away: release the content back to its own form, hide the window, fire OnHide.
      Idempotent — OnHide fires once per dismissal, never for a Hide on a hidden popover. }
    procedure Hide;
    { One line's height in device px at APPI in the TITLE's resolved font, from the stable
      reference glyph 'Ag' (so an empty title still measures a whole line). }
    function TitleHeightAt(APPI: Integer): Integer;
    { The frame's natural size in device px at APPI: the Content control's own size, wrapped
      in the themed padding, title and arrow strip. Content = nil measures to just the chrome
      — a titled, contentless popover is legal (if pointless), never a crash. }
    function MeasureFrameAtPPI(APPI: Integer): TSize;
    { Where this popover's window belongs beside AAnchorScreen. The work area is a PARAMETER
      (not Screen.WorkAreaRect) so the placement rules are testable without a screen; ShowAt
      passes the real one. }
    function GeometryIn(const AAnchorScreen, AWorkArea: TRect; APPI: Integer): TTyPopoverGeometry;
    { The frame's insides for a window of AFrameW x AFrameH landed on ASide — the exact rects
      the paint fills and the content is placed into. }
    function LayoutIn(AFrameW, AFrameH: Integer; ASide: TTyPopoverSide;
      ATipLocal, APPI: Integer): TTyPopoverLayout;
    { Whether the popup is currently up. }
    property Showing: Boolean read FShowing;
  published
    { The control the popover belongs to and points at. Show uses it; ShowFor/ShowAt override
      it for one call without disturbing it. }
    property Target: TControl read FTarget write SetTarget;
    { The container whose controls the popup shows. Fill it in the designer (a TTyPanel with
      your buttons in it, typically left Visible=False on the form) and point this at it: on
      Show it is re-parented INTO the popup window at the frame's content rect, and on Hide it
      goes back to its own form exactly as it was. Its DESIGNED SIZE is what the popup measures
      to, so size the container, not the popover. }
    property Content: TWinControl read FContent write SetContent;
    { Which side of Target the popup prefers, and how it lines up along that side. Only a
      PREFERENCE: a popup with no room on that side flips to the opposite one. }
    property Placement: TTyPopoverPlacement read FPlacement write SetPlacement default ppBottom;
    { An optional headline above the content, drawn with the resolved TyPopoverTitle style.
      Empty = no title, and the content takes the whole body. Single-line and ellipsised; no
      mnemonic parsing — a title activates nothing, so an '&' is literal text. }
    property Title: string read FTitle write SetTitle;
    { Draw the arrow pointing at Target. Off = a plain floating card that still places and
      flips by the same rules, just without the strip (and without its thickness). }
    property ShowArrow: Boolean read FShowArrow write SetShowArrow default True;
    { Dismiss when the user clicks away (the popup's window deactivating). On by default: that
      is what a flyout does. Turn it OFF for a popover whose content the user must answer —
      it then stays until Hide, or Escape. }
    property CloseOnClickOutside: Boolean read FCloseOnClickOutside
      write FCloseOnClickOutside default True;
    { Dismiss on Escape. Kept separate from CloseOnClickOutside so a "must answer" popover can
      still have the keyboard way out that every user expects, without the accidental one. }
    property CloseOnEscape: Boolean read FCloseOnEscape write FCloseOnEscape default True;
    { The variant entry: a `TyPopover.danger` rule in the theme. Resolved for BOTH typeKeys,
      so TyPopoverTitle.danger tints a danger popover's headline. }
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
    { Fired after the popup is on screen (and after the content has been adopted into it, so a
      handler may focus a control inside). }
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    { Fired once per dismissal, whatever caused it: a click away, Escape, or Hide. NOT fired
      when the component is destroyed — a component going away is not a popover the user
      dismissed. }
    property OnHide: TNotifyEvent read FOnHide write FOnHide;
  end;

implementation

uses
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.QtWS;   // TyQtIsWayland — the shape gate; TyQtMaskWindowDeep — Qt's child masks

// ---------------------------------------------------------------------------
// Pure rules / geometry
// ---------------------------------------------------------------------------

function TyPopoverSide(APlacement: TTyPopoverPlacement): TTyPopoverSide;
begin
  case APlacement of
    ppTop, ppTopLeft, ppTopRight:          Result := psvTop;
    ppLeft, ppLeftTop, ppLeftBottom:       Result := psvLeft;
    ppRight, ppRightTop, ppRightBottom:    Result := psvRight;
  else
    // ppBottom* — and anything a future enum extension forgets: below is the neutral default.
    Result := psvBottom;
  end;
end;

function TyPopoverAlign(APlacement: TTyPopoverPlacement): TTyPopoverAlign;
begin
  case APlacement of
    ppTopLeft, ppBottomLeft, ppLeftTop, ppRightTop:       Result := palStart;
    ppTopRight, ppBottomRight, ppLeftBottom, ppRightBottom: Result := palEnd;
  else
    Result := palCenter;
  end;
end;

function TyPopoverPlacementOf(ASide: TTyPopoverSide; AAlign: TTyPopoverAlign): TTyPopoverPlacement;
begin
  case ASide of
    psvTop:
      case AAlign of
        palStart: Result := ppTopLeft;
        palEnd:   Result := ppTopRight;
      else        Result := ppTop;
      end;
    psvLeft:
      case AAlign of
        palStart: Result := ppLeftTop;
        palEnd:   Result := ppLeftBottom;
      else        Result := ppLeft;
      end;
    psvRight:
      case AAlign of
        palStart: Result := ppRightTop;
        palEnd:   Result := ppRightBottom;
      else        Result := ppRight;
      end;
  else
    case AAlign of
      palStart: Result := ppBottomLeft;
      palEnd:   Result := ppBottomRight;
    else        Result := ppBottom;
    end;
  end;
end;

function TyPopoverOppositeSide(ASide: TTyPopoverSide): TTyPopoverSide;
begin
  case ASide of
    psvTop:   Result := psvBottom;
    psvLeft:  Result := psvRight;
    psvRight: Result := psvLeft;
  else
    Result := psvTop;
  end;
end;

function TyPopoverSideIsVertical(ASide: TTyPopoverSide): Boolean;
begin
  Result := ASide in [psvTop, psvBottom];
end;

{ The room a side has for a frame ANeed thick, between the anchor's edge and the work area's.
  Negative rooms are meaningless (an anchor already off screen), so they read as none. }
function PopoverRoomOn(const AAnchor, AWorkArea: TRect; ASide: TTyPopoverSide): Integer;
begin
  case ASide of
    psvTop:    Result := AAnchor.Top - AWorkArea.Top;
    psvBottom: Result := AWorkArea.Bottom - AAnchor.Bottom;
    psvLeft:   Result := AAnchor.Left - AWorkArea.Left;
  else
    Result := AWorkArea.Right - AAnchor.Right;
  end;
  if Result < 0 then Result := 0;
end;

function TyPopoverPlace(const AAnchor: TRect; AFrameW, AFrameH: Integer;
  const AWorkArea: TRect; APlacement: TTyPopoverPlacement;
  AOffset, AArrowSize: Integer): TTyPopoverGeometry;
var
  chosen, other: TTyPopoverSide;
  algn: TTyPopoverAlign;
  need, x, y, lo, hi: Integer;
begin
  if AFrameW < 0 then AFrameW := 0;
  if AFrameH < 0 then AFrameH := 0;
  if AOffset < 0 then AOffset := 0;
  if AArrowSize < 0 then AArrowSize := 0;

  chosen := TyPopoverSide(APlacement);
  algn := TyPopoverAlign(APlacement);
  other := TyPopoverOppositeSide(chosen);

  // --- main axis: honour, flip, or give up -----------------------------------
  if TyPopoverSideIsVertical(chosen) then need := AFrameH + AOffset
  else need := AFrameW + AOffset;
  Result.Flipped := (PopoverRoomOn(AAnchor, AWorkArea, chosen) < need)
    and (PopoverRoomOn(AAnchor, AWorkArea, other) >= need);
  if Result.Flipped then chosen := other;
  Result.Side := chosen;

  case chosen of
    psvTop:    y := AAnchor.Top - AOffset - AFrameH;
    psvBottom: y := AAnchor.Bottom + AOffset;
    psvLeft:   x := AAnchor.Left - AOffset - AFrameW;
  else
    x := AAnchor.Right + AOffset;
  end;

  // --- cross axis: align as asked, then slide into the work area --------------
  if TyPopoverSideIsVertical(chosen) then
  begin
    case algn of
      palStart: x := AAnchor.Left;
      palEnd:   x := AAnchor.Right - AFrameW;
    else
      x := (AAnchor.Left + AAnchor.Right) div 2 - AFrameW div 2;
    end;
    // Right edge first, then left: a frame wider than the work area hugs its LEFT edge (the
    // reading edge) rather than its right — TTyBalloonHint's clamp order, for that reason.
    if x + AFrameW > AWorkArea.Right then x := AWorkArea.Right - AFrameW;
    if x < AWorkArea.Left then x := AWorkArea.Left;
  end
  else
  begin
    case algn of
      palStart: y := AAnchor.Top;
      palEnd:   y := AAnchor.Bottom - AFrameH;
    else
      y := (AAnchor.Top + AAnchor.Bottom) div 2 - AFrameH div 2;
    end;
    if y + AFrameH > AWorkArea.Bottom then y := AWorkArea.Bottom - AFrameH;
    if y < AWorkArea.Top then y := AWorkArea.Top;
  end;

  Result.Frame := Rect(x, y, x + AFrameW, y + AFrameH);

  // --- the tip: the anchor's centre, clamped so its base still lands on the frame ---
  if TyPopoverSideIsVertical(chosen) then
  begin
    Result.TipX := (AAnchor.Left + AAnchor.Right) div 2;
    lo := Result.Frame.Left + AArrowSize;
    hi := Result.Frame.Right - AArrowSize;
    if Result.TipX < lo then Result.TipX := lo;
    if Result.TipX > hi then Result.TipX := hi;
    if chosen = psvBottom then Result.TipY := Result.Frame.Top
    else Result.TipY := Result.Frame.Bottom;
  end
  else
  begin
    Result.TipY := (AAnchor.Top + AAnchor.Bottom) div 2;
    lo := Result.Frame.Top + AArrowSize;
    hi := Result.Frame.Bottom - AArrowSize;
    if Result.TipY < lo then Result.TipY := lo;
    if Result.TipY > hi then Result.TipY := hi;
    if chosen = psvRight then Result.TipX := Result.Frame.Left
    else Result.TipX := Result.Frame.Right;
  end;
end;

function TyPopoverTipLocal(const AGeometry: TTyPopoverGeometry): Integer;
begin
  if TyPopoverSideIsVertical(AGeometry.Side) then
    Result := AGeometry.TipX - AGeometry.Frame.Left
  else
    Result := AGeometry.TipY - AGeometry.Frame.Top;
end;

function TyPopoverLayout(AFrameW, AFrameH: Integer; ASide: TTyPopoverSide; ATipLocal: Integer;
  AShowArrow, AHasTitle: Boolean;
  APadL, APadT, APadR, APadB, ATitleH, ATitleGap, AArrowSize: Integer): TTyPopoverLayout;
var
  strip, bandL, bandT, bandR, bandB, extent, aL, aR, y: Integer;
begin
  Result.BodyRect := Rect(0, 0, 0, 0);
  Result.ArrowRect := Rect(0, 0, 0, 0);
  Result.ArrowTip := Point(0, 0);
  Result.TitleRect := Rect(0, 0, 0, 0);
  Result.ContentRect := Rect(0, 0, 0, 0);
  if (AFrameW <= 0) or (AFrameH <= 0) then Exit;
  // Clamp every negative input once, here, so the arithmetic below can be read straight.
  if APadL < 0 then APadL := 0;
  if APadT < 0 then APadT := 0;
  if APadR < 0 then APadR := 0;
  if APadB < 0 then APadB := 0;
  if ATitleH < 0 then ATitleH := 0;
  if ATitleGap < 0 then ATitleGap := 0;
  if AArrowSize < 0 then AArrowSize := 0;

  strip := 0;
  if AShowArrow then strip := AArrowSize;

  // --- the strip, carved out of the anchor-facing edge --------------------------
  case ASide of
    psvTop:    Result.BodyRect := Rect(0, 0, AFrameW, AFrameH - strip);   // arrow hangs below
    psvBottom: Result.BodyRect := Rect(0, strip, AFrameW, AFrameH);       // arrow sits above
    psvLeft:   Result.BodyRect := Rect(0, 0, AFrameW - strip, AFrameH);   // arrow on the right
  else
    Result.BodyRect := Rect(strip, 0, AFrameW, AFrameH);                  // arrow on the left
  end;
  if (Result.BodyRect.Right <= Result.BodyRect.Left)
    or (Result.BodyRect.Bottom <= Result.BodyRect.Top) then
  begin
    // The strip ate the whole frame: there is no popup here at all.
    Result.BodyRect := Rect(0, 0, 0, 0);
    Exit;
  end;

  // --- the arrow ---------------------------------------------------------------
  if AShowArrow and (AArrowSize > 0) then
  begin
    if TyPopoverSideIsVertical(ASide) then extent := AFrameW else extent := AFrameH;
    // The tip's base must land ON the frame; a frame narrower than the whole base simply
    // clamps the box into it (the triangle degenerates rather than spilling out).
    if ATipLocal < AArrowSize then ATipLocal := AArrowSize;
    if ATipLocal > extent - AArrowSize then ATipLocal := extent - AArrowSize;
    aL := ATipLocal - AArrowSize;
    aR := ATipLocal + AArrowSize;
    if aL < 0 then aL := 0;
    if aR > extent then aR := extent;
    case ASide of
      psvTop:
        begin
          Result.ArrowRect := Rect(aL, AFrameH - strip, aR, AFrameH);
          Result.ArrowTip := Point(ATipLocal, AFrameH);
        end;
      psvBottom:
        begin
          Result.ArrowRect := Rect(aL, 0, aR, strip);
          Result.ArrowTip := Point(ATipLocal, 0);
        end;
      psvLeft:
        begin
          Result.ArrowRect := Rect(AFrameW - strip, aL, AFrameW, aR);
          Result.ArrowTip := Point(AFrameW, ATipLocal);
        end;
    else
      Result.ArrowRect := Rect(0, aL, strip, aR);
      Result.ArrowTip := Point(0, ATipLocal);
    end;
  end;

  // --- the content band: the body inset by its themed padding -------------------
  bandL := Result.BodyRect.Left + APadL;
  bandT := Result.BodyRect.Top + APadT;
  bandR := Result.BodyRect.Right - APadR;
  bandB := Result.BodyRect.Bottom - APadB;
  // Padding that eats the whole body leaves nothing to lay out; the body itself still draws.
  if (bandR <= bandL) or (bandB <= bandT) then Exit;

  y := bandT;
  if AHasTitle and (ATitleH > 0) then
  begin
    if y + ATitleH > bandB then
      // No room for a whole line: the title takes what there is and the content collapses.
      Result.TitleRect := Rect(bandL, y, bandR, bandB)
    else
      Result.TitleRect := Rect(bandL, y, bandR, y + ATitleH);
    y := Result.TitleRect.Bottom + ATitleGap;   // the gap exists only BETWEEN the two
  end;

  if y < bandB then
    Result.ContentRect := Rect(bandL, y, bandR, bandB);
end;

function TyPopoverFrameSize(AContentW, AContentH: Integer; ASide: TTyPopoverSide;
  AShowArrow, AHasTitle: Boolean;
  APadL, APadT, APadR, APadB, ATitleH, ATitleGap, AArrowSize: Integer): TSize;
var
  strip, bandH: Integer;
begin
  if AContentW < 0 then AContentW := 0;
  if AContentH < 0 then AContentH := 0;
  if APadL < 0 then APadL := 0;
  if APadT < 0 then APadT := 0;
  if APadR < 0 then APadR := 0;
  if APadB < 0 then APadB := 0;
  if ATitleH < 0 then ATitleH := 0;
  if ATitleGap < 0 then ATitleGap := 0;
  if AArrowSize < 0 then AArrowSize := 0;

  strip := 0;
  if AShowArrow then strip := AArrowSize;

  bandH := AContentH;
  if AHasTitle and (ATitleH > 0) then
  begin
    Inc(bandH, ATitleH);
    // Mirrors TyPopoverLayout: the gap is spent only when there IS content under the title.
    if AContentH > 0 then Inc(bandH, ATitleGap);
  end;

  Result.cx := APadL + AContentW + APadR;
  Result.cy := APadT + bandH + APadB;
  if TyPopoverSideIsVertical(ASide) then Inc(Result.cy, strip)
  else Inc(Result.cx, strip);
  if Result.cx < 1 then Result.cx := 1;
  if Result.cy < 1 then Result.cy := 1;
end;

function TyPopoverArrowPoints(const ALayout: TTyPopoverLayout; ASide: TTyPopoverSide;
  out ATip, ABase1, ABase2: TPoint): Boolean;
begin
  Result := (ALayout.ArrowRect.Right > ALayout.ArrowRect.Left)
    and (ALayout.ArrowRect.Bottom > ALayout.ArrowRect.Top);
  if not Result then Exit;
  ATip := ALayout.ArrowTip;
  // The base is the strip's INNER edge — the one that meets the body — so the two slanted
  // sides run from there out to the apex on the frame's outer edge.
  case ASide of
    psvTop:
      begin
        ABase1 := Point(ALayout.ArrowRect.Left, ALayout.ArrowRect.Top);
        ABase2 := Point(ALayout.ArrowRect.Right, ALayout.ArrowRect.Top);
      end;
    psvBottom:
      begin
        ABase1 := Point(ALayout.ArrowRect.Left, ALayout.ArrowRect.Bottom);
        ABase2 := Point(ALayout.ArrowRect.Right, ALayout.ArrowRect.Bottom);
      end;
    psvLeft:
      begin
        ABase1 := Point(ALayout.ArrowRect.Left, ALayout.ArrowRect.Top);
        ABase2 := Point(ALayout.ArrowRect.Left, ALayout.ArrowRect.Bottom);
      end;
  else
    ABase1 := Point(ALayout.ArrowRect.Right, ALayout.ArrowRect.Top);
    ABase2 := Point(ALayout.ArrowRect.Right, ALayout.ArrowRect.Bottom);
  end;
end;

// ---------------------------------------------------------------------------
// TTyPopoverWindow
// ---------------------------------------------------------------------------
constructor TTyPopoverWindow.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  BorderStyle := bsNone;      // the body IS the chrome
  FormStyle := fsStayOnTop;   // it floats above the form it belongs to
  ShowInTaskBar := stNever;   // a popover is not a window the user manages
  Position := poDesigned;     // Show must not re-centre a window we placed by rule
  KeyPreview := True;         // Escape must reach us past whatever the content focused
  OnDeactivate := @DoDeactivate;
  Visible := False;
end;

procedure TTyPopoverWindow.DoDeactivate(Sender: TObject);
begin
  // Lost focus (a click outside) -> dismiss, like any flyout — unless the app said not to.
  if (FOwnerPop <> nil) and FOwnerPop.CloseOnClickOutside then
    FOwnerPop.Hide;
end;

procedure TTyPopoverWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and (FOwnerPop <> nil) and FOwnerPop.CloseOnEscape then
  begin
    Key := 0;
    FOwnerPop.Hide;
  end;
end;

procedure TTyPopoverWindow.Paint;
begin
  if FOwnerPop = nil then Exit;
  FOwnerPop.RenderTo(Canvas, ClientRect, FSide, FTipLocal, Font.PixelsPerInch);
  ApplyShape;
end;

procedure TTyPopoverWindow.ApplyShape;
var
  Lay: TTyPopoverLayout;
  S: TTyStyleSet;
  d: Integer;
  bodyRgn, triRgn: HRGN;
  tip, b1, b2: TPoint;
  pts: array[0..2] of TPoint;
begin
  if (FOwnerPop = nil) or not HandleAllocated then Exit;
  if TyQtIsWayland then Exit;   // no XShape: square corners, as TTyBalloonHint degrades
  Lay := FOwnerPop.LayoutIn(ClientWidth, ClientHeight, FSide, FTipLocal, Font.PixelsPerInch);
  if Lay.BodyRect.Right <= Lay.BodyRect.Left then Exit;
  S := FOwnerPop.PopoverStyle;
  d := MulDiv(TyEffectiveCorners(S).TL, Font.PixelsPerInch, 96) * 2;

  // +1 on the extents: CreateRoundRectRgn's right/bottom are exclusive.
  if d > 0 then
    bodyRgn := CreateRoundRectRgn(Lay.BodyRect.Left, Lay.BodyRect.Top,
      Lay.BodyRect.Right + 1, Lay.BodyRect.Bottom + 1, d, d)
  else
    bodyRgn := CreateRectRgn(Lay.BodyRect.Left, Lay.BodyRect.Top,
      Lay.BodyRect.Right + 1, Lay.BodyRect.Bottom + 1);

  if TyPopoverArrowPoints(Lay, FSide, tip, b1, b2) then
  begin
    pts[0] := tip;
    pts[1] := b1;
    pts[2] := b2;
    triRgn := CreatePolygonRgn(pts, 3, LCLType.WINDING);
    CombineRgn(bodyRgn, bodyRgn, triRgn, RGN_OR);
    DeleteObject(triRgn);
  end;

  // Qt6/X11 (QTSCROLLABLEFORMS): the top-level mask never reaches the scroll-area viewport
  // or the adopted content's own native widget — TTyDropdownPopup's deep mask does. No-op
  // off Qt, and it does NOT take the region (SetWindowRgn below does).
  TyQtMaskWindowDeep(Self, FOwnerPop.Content, bodyRgn);
  SetWindowRgn(Handle, bodyRgn, True);   // takes ownership of bodyRgn
end;

// ---------------------------------------------------------------------------
// TTyPopover — construction / theming
// ---------------------------------------------------------------------------
constructor TTyPopover.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPlacement := ppBottom;
  FShowArrow := True;
  FCloseOnClickOutside := True;
  FCloseOnEscape := True;
end;

destructor TTyPopover.Destroy;
begin
  // Dismiss WITHOUT firing OnHide: a component being destroyed is not a popover the user
  // dismissed, and the handler's form may already be half torn down. The content still has
  // to go home — it belongs to that form, not to us.
  FOnHide := nil;
  Hide;
  FreeAndNil(FWin);   // CreateNew(nil): owned by us, not by a form
  inherited Destroy;
end;

class function TTyPopover.StyleTypeKey: string;
begin
  Result := 'TyPopover';
end;

class function TTyPopover.TitleStyleTypeKey: string;
begin
  Result := 'TyPopoverTitle';
end;

function TTyPopover.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyPopover.PopoverStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(StyleTypeKey, FStyleClass, []);
end;

function TTyPopover.TitleStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(TitleStyleTypeKey, FStyleClass, []);
end;

function TTyPopover.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, True, 0, ActiveController);
end;

procedure TTyPopover.TitleFont(out AName: string; out ASize, AWeight: Integer);
var
  bodyS, tS: TTyStyleSet;
begin
  bodyS := PopoverStyle;
  tS := TitleStyle;
  // Each value INDIVIDUALLY falls back to the body's, so a theme that gives TyPopoverTitle
  // only a font-weight still gets the body's family and size — the ordinary per-property
  // degradation, never a hard-coded font.
  if tpFontName in tS.Present then AName := tS.FontName else AName := bodyS.FontName;
  if tpFontSize in tS.Present then ASize := ResolveFontSize(tS) else ASize := ResolveFontSize(bodyS);
  if tpFontWeight in tS.Present then AWeight := tS.FontWeight else AWeight := bodyS.FontWeight;
end;

function TTyPopover.TitleInk: TTyColor;
var
  tS: TTyStyleSet;
begin
  tS := TitleStyle;
  if tpTextColor in tS.Present then Result := tS.TextColor
  else Result := PopoverStyle.TextColor;   // no title colour -> the popup's own ink
end;

// ---------------------------------------------------------------------------
// Theme metrics
// ---------------------------------------------------------------------------
function TTyPopover.ArrowSizeLogical: Integer;
begin
  Result := ActiveController.Metric(TyPopoverArrowSizeVar, TyPopoverArrowSize);
  if Result < 0 then Result := 0;
end;

function TTyPopover.OffsetLogical: Integer;
begin
  Result := ActiveController.Metric(TyPopoverOffsetVar, TyPopoverOffset);
  if Result < 0 then Result := 0;
end;

function TTyPopover.TitleGapLogical: Integer;
begin
  Result := ActiveController.Metric(TyPopoverTitleGapVar, TyPopoverTitleGap);
  if Result < 0 then Result := 0;
end;

// ---------------------------------------------------------------------------
// Measurement + geometry
// ---------------------------------------------------------------------------
function TTyPopover.TitleHeightAt(APPI: Integer): Integer;
{ Measured with a CANVAS-LESS painter — the TTyBadge / TTyNotification idiom: BeginPaint(nil,
  ...) builds only the painter's internal bitmap and EndPaint frees it WITHOUT blitting, so
  this is safe outside a paint cycle and leaks nothing. It has to be the painter and not a
  TBitmap canvas: the title is drawn with BGRA text metrics, and only the same measurer
  reproduces the height those glyphs actually render at. }
var
  P: TTyPainter;
  nm: string;
  sz, wt: Integer;
begin
  if APPI <= 0 then APPI := 96;
  TitleFont(nm, sz, wt);
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    // A stable reference glyph: an empty Title still measures a whole line.
    Result := P.MeasureText('Ag', nm, sz, wt).cy;
    P.EndPaint;                                  // nil canvas -> no blit, just frees the bitmap
  finally
    P.Free;
  end;
  if Result < 1 then Result := 1;
end;

function TTyPopover.MeasureFrameAtPPI(APPI: Integer): TSize;
var
  S: TTyStyleSet;
  cw, ch: Integer;
begin
  if APPI <= 0 then APPI := 96;
  S := PopoverStyle;
  cw := 0;
  ch := 0;
  if FContent <> nil then
  begin
    // The container's DESIGNED size, taken as it stands: it is a real control on a real form,
    // already in that form's pixels. Nothing here re-scales it — the popup wraps what the
    // designer built, it does not second-guess it.
    cw := FContent.Width;
    ch := FContent.Height;
  end;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the frame measured here is the frame the paint carves up.
  Result := TyPopoverFrameSize(cw, ch, TyPopoverSide(FPlacement), FShowArrow, FTitle <> '',
    MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Top, APPI, 96),
    MulDiv(S.Padding.Right, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96),
    TitleHeightAt(APPI), MulDiv(TitleGapLogical, APPI, 96),
    MulDiv(ArrowSizeLogical, APPI, 96));
end;

function TTyPopover.GeometryIn(const AAnchorScreen, AWorkArea: TRect;
  APPI: Integer): TTyPopoverGeometry;
var
  sz: TSize;
begin
  if APPI <= 0 then APPI := 96;
  sz := MeasureFrameAtPPI(APPI);
  Result := TyPopoverPlace(AAnchorScreen, sz.cx, sz.cy, AWorkArea, FPlacement,
    MulDiv(OffsetLogical, APPI, 96), MulDiv(ArrowSizeLogical, APPI, 96));
end;

function TTyPopover.LayoutIn(AFrameW, AFrameH: Integer; ASide: TTyPopoverSide;
  ATipLocal, APPI: Integer): TTyPopoverLayout;
var
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := PopoverStyle;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the rects the content is placed into are the rects the paint drew.
  Result := TyPopoverLayout(AFrameW, AFrameH, ASide, ATipLocal, FShowArrow, FTitle <> '',
    MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Top, APPI, 96),
    MulDiv(S.Padding.Right, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96),
    TitleHeightAt(APPI), MulDiv(TitleGapLogical, APPI, 96),
    MulDiv(ArrowSizeLogical, APPI, 96));
end;

// ---------------------------------------------------------------------------
// Content adoption
// ---------------------------------------------------------------------------
procedure TTyPopover.AdoptContent;
begin
  if (FContent = nil) or FAdopted or (FWin = nil) then Exit;
  // Remember its whole life before we borrow it — TTyPopupSurface's contract.
  FOrigParent := FContent.Parent;
  FOrigAlign := FContent.Align;
  FOrigBounds := FContent.BoundsRect;
  FOrigVisible := FContent.Visible;
  FAdopted := True;
  FContent.Align := alNone;   // the frame's content rect places it, not an align rule
  FContent.Parent := FWin;
  FContent.Visible := True;
end;

procedure TTyPopover.ReleaseContent;
var
  c: TWinControl;
begin
  if not FAdopted then Exit;
  FAdopted := False;   // clear FIRST: SetParent can re-enter through alignment
  c := FContent;
  if c = nil then Exit;
  c.Align := alNone;
  c.Parent := FOrigParent;
  c.BoundsRect := FOrigBounds;
  c.Align := FOrigAlign;
  c.Visible := FOrigVisible;
end;

// ---------------------------------------------------------------------------
// Lifetime
// ---------------------------------------------------------------------------
procedure TTyPopover.EnsureWindow;
var
  S: TTyStyleSet;
begin
  if FWin = nil then
  begin
    FWin := TTyPopoverWindow.CreateNew(nil);
    FWin.FOwnerPop := Self;
  end;
  { The TTyPopupSurface lesson: a bare borderless form never sets Color, so it keeps the OS
    default clBtnFace — which is near-BLACK on a dark-mode OS. Every pixel the body does not
    cover erases to it (the corners outside the radius, the strip beside the arrow, and on
    Wayland — where the shape region is silently ignored — the whole silhouette), AND so does
    every transparent/ghost child control the app parented into us, which is the entire point
    of this component. Paint the window with the body's own surface colour first. }
  S := PopoverStyle;
  if (tpBackground in S.Present) and (S.Background.Kind = tfkSolid) then
    FWin.Color := TyColorToLCL(S.Background.Color);
end;

function TTyPopover.BeginShowing(const AAnchorScreen, AWorkArea: TRect;
  APPI: Integer): TTyPopoverGeometry;
var
  Lay: TTyPopoverLayout;
begin
  if APPI <= 0 then APPI := 96;
  EnsureWindow;
  Result := GeometryIn(AAnchorScreen, AWorkArea, APPI);
  FWin.FSide := Result.Side;
  FWin.FTipLocal := TyPopoverTipLocal(Result);
  FWin.SetBounds(Result.Frame.Left, Result.Frame.Top,
    Result.Frame.Right - Result.Frame.Left, Result.Frame.Bottom - Result.Frame.Top);

  AdoptContent;
  if FAdopted then
  begin
    // The frame was measured FROM this control, so the content rect is exactly its own size:
    // the round-trip between TyPopoverFrameSize and TyPopoverLayout is what stops a popover
    // from resizing its own content a little more on every Show.
    Lay := LayoutIn(Result.Frame.Right - Result.Frame.Left,
      Result.Frame.Bottom - Result.Frame.Top, Result.Side, FWin.FTipLocal, APPI);
    FContent.SetBounds(Lay.ContentRect.Left, Lay.ContentRect.Top,
      Lay.ContentRect.Right - Lay.ContentRect.Left,
      Lay.ContentRect.Bottom - Lay.ContentRect.Top);
  end;
  FShowing := True;
end;

procedure TTyPopover.Show;
begin
  if FTarget = nil then Exit;   // nothing to point at: a popover is always ABOUT something
  ShowFor(FTarget);
end;

procedure TTyPopover.ShowFor(AControl: TControl);
var
  tl: TPoint;
begin
  if AControl = nil then Exit;
  tl := AControl.ClientToScreen(Point(0, 0));
  ShowAt(Rect(tl.X, tl.Y, tl.X + AControl.Width, tl.Y + AControl.Height));
end;

procedure TTyPopover.ShowAt(const AAnchorScreen: TRect);
var
  geo: TTyPopoverGeometry;
  ppi: Integer;
begin
  if csDesigning in ComponentState then Exit;   // a popover is a runtime gesture, not a preview
  ppi := Screen.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  geo := BeginShowing(AAnchorScreen, Screen.WorkAreaRect, ppi);
  FWin.Show;
  FWin.BringToFront;
  // A bsNone form can be re-placed by the WM on show (TTyBalloonHint / TTyNotification re-set
  // for the same reason), so assert the rect again once it is up.
  FWin.SetBounds(geo.Frame.Left, geo.Frame.Top,
    geo.Frame.Right - geo.Frame.Left, geo.Frame.Bottom - geo.Frame.Top);
  FWin.Invalidate;
  if Assigned(FOnShow) then FOnShow(Self);
end;

procedure TTyPopover.Hide;
begin
  if not FShowing then
  begin
    // Not up, but the content may still be adopted if a Show never finished — put it back
    // regardless, then get out. A Hide on a hidden popover fires nothing (idempotent).
    ReleaseContent;
    Exit;
  end;
  FShowing := False;   // set FIRST: hiding the window can fire OnDeactivate straight back here
  ReleaseContent;
  if (FWin <> nil) and FWin.Visible then FWin.Hide;
  if Assigned(FOnHide) then FOnHide(Self);
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------
procedure TTyPopover.RenderTo(ACanvas: TCanvas; const ARect: TRect; ASide: TTyPopoverSide;
  ATipLocal, APPI: Integer);
var
  P: TTyPainter;
  S, tS: TTyStyleSet;
  R: TRect;
  Lay: TTyPopoverLayout;
  ctx: TBGRACanvas2D;
  tip, b1, b2: TPoint;
  nm: string;
  sz, wt: Integer;
begin
  if APPI <= 0 then APPI := 96;
  S := PopoverStyle;
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at ARect's origin,
    // so a non-zero ARect origin would shift the popup.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    if not (tpBackground in S.Present) then
    begin
      // A theme that does not define TyPopover (or this variant of it) gets NO popup body at
      // all rather than a hard-coded one. Degrade, never crash, never invent a colour.
      P.EndPaint;
      Exit;
    end;
    if tpOpacity in S.Present then P.Opacity := S.Opacity;

    Lay := LayoutIn(R.Right - R.Left, R.Bottom - R.Top, ASide, ATipLocal, APPI);
    if Lay.BodyRect.Right <= Lay.BodyRect.Left then
    begin
      P.EndPaint;
      Exit;
    end;

    // No shadow: the window is cut to the body's silhouette, so a drop shadow would be cut
    // off with everything else outside it. Elevation is the OS's business for a top-level.
    P.FillBackground(Lay.BodyRect, S.Background, TyEffectiveCorners(S));

    { The arrow is the body carried out past its own edge, so it takes the body's SOLID fill.
      A gradient / image / nine-slice body gets NO arrow: there is no one colour to carry out
      there, and inventing one is exactly what this library does not do. (The strip is still
      reserved, so nothing shifts — such a theme simply reads as a floating card. A theme that
      wants an arrow on a gradient popup should set ShowArrow off, or a solid TyPopover.)
      Known cosmetic, shared with TTyBalloonHint: on a bordered theme the body's own border
      line still runs across the arrow's base. Verify the look on a real machine. }
    if (S.Background.Kind = tfkSolid) and TyPopoverArrowPoints(Lay, ASide, tip, b1, b2) then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.beginPath;
      ctx.moveTo(tip.X, tip.Y);
      ctx.lineTo(b1.X, b1.Y);
      ctx.lineTo(b2.X, b2.Y);
      ctx.closePath;
      ctx.fillStyle(TyColorToBGRA(S.Background.Color));
      ctx.fill;
      if TyBorderVisible(S) then
      begin
        // Only the two SLANTED sides: the base belongs to the body, whose own border draws it.
        ctx.beginPath;
        ctx.moveTo(b1.X, b1.Y);
        ctx.lineTo(tip.X, tip.Y);
        ctx.lineTo(b2.X, b2.Y);
        ctx.strokeStyle(TyColorToBGRA(S.BorderColor));
        ctx.lineWidth := P.Scale(S.BorderWidth);
        ctx.stroke;
      end;
    end;

    if TyBorderVisible(S) then
      P.StrokeBorder(Lay.BodyRect, TyEffectiveCorners(S), S.BorderWidth, S.BorderColor);

    if Lay.TitleRect.Right > Lay.TitleRect.Left then
    begin
      tS := TitleStyle;
      // An undefined TyPopoverTitle leaves no background -> no band, and the headline still
      // draws in the popup's own ink. A theme that fills it gets a header strip for free.
      if tpBackground in tS.Present then
        P.FillBackground(Lay.TitleRect, tS.Background, TyEffectiveCorners(tS));
      TitleFont(nm, sz, wt);
      // Left-aligned + ellipsised: a popup narrower than its headline shows 'Confirm dele…',
      // not a glyph sheared at the clip edge. No mnemonic parsing (see the property).
      P.DrawText(Lay.TitleRect, FTitle, nm, sz, wt, TitleInk, taLeftJustify, tlCenter, True);
    end;

    // ContentRect is not painted: a real control lives there, and it paints itself.
    P.EndPaint;
  finally
    P.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Property setters
// ---------------------------------------------------------------------------
procedure TTyPopover.SetTarget(AValue: TControl);
begin
  if FTarget = AValue then Exit;
  if FTarget <> nil then FTarget.RemoveFreeNotification(Self);
  FTarget := AValue;
  if FTarget <> nil then FTarget.FreeNotification(Self);
end;

procedure TTyPopover.SetContent(AValue: TWinControl);
begin
  if FContent = AValue then Exit;
  // Swapping the content out from under a live popup would strand the old one in our window:
  // put it home first, and let the caller re-Show with the new one.
  if FAdopted then Hide;
  if FContent <> nil then FContent.RemoveFreeNotification(Self);
  FContent := AValue;
  if FContent <> nil then FContent.FreeNotification(Self);
end;

procedure TTyPopover.SetPlacement(AValue: TTyPopoverPlacement);
begin
  if FPlacement = AValue then Exit;
  FPlacement := AValue;
  // A live popup does not jump: the placement is read when it goes up. Moving it under the
  // pointer mid-gesture is how a user loses the button they were reaching for.
end;

procedure TTyPopover.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  // '' <-> text is a SIZE change (the title's whole band), so a live popup would have to be
  // re-measured, re-placed and its content re-bounded. Repaint only: the new size lands on
  // the next Show, which is when a popover's geometry is decided.
  if (FWin <> nil) and FWin.Visible then FWin.Invalidate;
end;

procedure TTyPopover.SetShowArrow(AValue: Boolean);
begin
  if FShowArrow = AValue then Exit;
  FShowArrow := AValue;
  if (FWin <> nil) and FWin.Visible then FWin.Invalidate;
end;

procedure TTyPopover.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  if (FWin <> nil) and FWin.Visible then FWin.Invalidate;
end;

procedure TTyPopover.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then FController.RemoveFreeNotification(Self);
  FController := AValue;
  if FController <> nil then FController.FreeNotification(Self);
  if (FWin <> nil) and FWin.Visible then FWin.Invalidate;
end;

procedure TTyPopover.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  if AComponent = FController then
    FController := nil          // fall back to TyDefaultController rather than dangle
  else if AComponent = FTarget then
    FTarget := nil
  else if AComponent = FContent then
  begin
    // The container is being freed out from under a live popup. Drop the adoption WITHOUT
    // releasing (there is nothing left to hand back), then take the popup down: a popover
    // whose content just died has nothing left to show.
    FAdopted := False;
    FContent := nil;
    Hide;
  end;
end;

end.
