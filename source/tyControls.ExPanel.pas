unit tyControls.ExPanel;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages, ExtCtrls,
  BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Panel,
  tyControls.Controller, tyControls.StyleModel, tyControls.Animation;

const
  // Logical (96ppi) default header-band height. Chosen to match the compact
  // caption bands used elsewhere (GroupBox 16 + a little breathing room).
  TyExPanelDefaultHeaderHeight = 26;
  { The header's action area, logical px: the inset at each end of its row of children, and
    the gap between two of them. }
  TyExPanelActionsPadVar = '--expander-actions-pad';
  TyExPanelActionsPadDef = 4;
  TyExPanelActionsGapVar = '--expander-actions-gap';
  TyExPanelActionsGapDef = 2;
  TyExPanelActionsKey    = 'TyExPanelActions';

type
  { The three corners of the expand/collapse chevron (device pixels). }
  TTyTriangle = array[0..2] of TPoint;

  TTyCustomExPanel = class;

  { When the header's action area shows. }
  TTyExPanelActionsVisibility = (
    eavAlways,          { all the time }
    eavHoverOrFocus);   { while the pointer is over the header or the focus is in the panel }

  { What a point of the panel is on. }
  TTyExPanelHit = (ephNone, ephHeader, ephActions, ephBody);

  { The header's parts, device px, in the panel's client coordinates. Actions is empty (no
    width, at the trailing end) while there is no action area or it does not show. }
  TTyExPanelHeaderGeom = record
    Chevron, Caption, Actions: TRect;
  end;

  { The action area's row of children: each one's box in the area (in the order given) and
    the size the whole row asks for. }
  TTyExPanelFlow = record
    Rects: array of TRect;
    Size: TSize;
  end;

  { The action area's visible children, in Controls[] order: one for one with a flow's Rects. }
  TTyExPanelKids = array of TControl;

  { What a container that stacks panels as sections, and so owns their heights, is to a
    panel in it (TTyAccordion is one). A panel asks its Parent for this; one whose Parent
    does not answer sizes itself, as a panel on a form always has. The panel's events stay
    the application's: the container hears from the panel here. }
  ITyExPanelHost = interface
    ['{3F8A5C12-9E47-4B6D-A1C0-5D2E7F90B364}']
    { ASection.Collapsed changed (it reads the new value already). The host gives the
      sections their new heights, over ASection.AnimationDuration. }
    procedure SectionToggled(ASection: TTyCustomExPanel);
    { ASection's weight (ExpandedHeight) or its header height changed. }
    procedure SectionChanged(ASection: TTyCustomExPanel);
    { A key pressed on ASection's focused header that the header has no use for itself. The
      host takes it by setting Key to 0. }
    procedure SectionKeyDown(ASection: TTyCustomExPanel; var Key: Word; Shift: TShiftState);
  end;

  { The action area of a panel's header: a container the panel keeps at the trailing end of
    its header band, for the small buttons that act on the section. Its children sit in one
    row, in creation order, centred on the band and cut at its height; their Align and
    Anchors are not used. A panel uses the first one among its children; a second one, and
    one that is not in a TTyExPanel at all, shows only in the designer, where it can be
    deleted.

    'TyExPanelActions' is its own style key. With no background of its own it carries on
    the header band under its children -- the band's tint, its hover, its focus ring. }
  TTyCustomExPanelActions = class(TTyCustomControl)
  private
    FInLayout: Boolean;
    function OwnPPI: Integer;
    function HasVisibleChild: Boolean;
    function MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
    { The row of the visible children (Controls[] order) at APPI, in a room of AAvailW by
      AAvailH: the one answer the area lays its children out by and is measured by. }
    function RowAt(APPI, AAvailW, AAvailH: Integer; out AKids: TTyExPanelKids): TTyExPanelFlow;
  protected
    function GetStyleTypeKey: string; override;
    procedure SetAlign(Value: TAlign); override;
    function ChildClassAllowed(ChildClass: TClass): Boolean; override;
    procedure AlignControls(AControl: TControl; var RemainingClientRect: TRect); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { A container for the buttons, never the focus itself: an arrow key LCL turns into
      "the next control" must not land on it. Its children are reached as usual. }
    function CanFocus: Boolean; override;
    { The panel whose header this area is in, or nil: its Parent, when that is a
      TTyCustomExPanel and this is the first action area in it. }
    function Panel: TTyCustomExPanel;
    { Out of a header it has nowhere to be: hidden at run time, shown in the designer.
      Derived, not written to Visible, which would go into the form file. }
    function IsControlVisible: Boolean; override;
    { A child came, went, showed, hid or changed size: the header makes room again. }
    procedure AdjustSize; override;
    { The width its row of visible children asks for at APPI, device px; 0 with none.
      In the designer an empty area asks for ASlot, so that there is something to drop on. }
    function PreferredWidthAt(APPI, ASlot: Integer): Integer;
    { Pushed by the panel, so not stored. }
    property Controller stored False;
  end;

  { TTyExPanelActions publishes TTyCustomExPanelActions's properties; everything lives in
    TTyCustomExPanelActions. Align and Anchors are not here: the header places it. }
  TTyExPanelActions = class(TTyCustomExPanelActions)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property ParentShowHint;
    property PopupMenu;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnContextPopup;
    property OnResize;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

  { TTyExPanel — a collapsible/expandable panel.

    A HEADER band across the top draws the Caption + an expand/collapse chevron;
    clicking it toggles Collapsed. The BODY below the header hosts the user's child
    controls (a real container: csAcceptsControls). When Collapsed the control's
    Height animates down to just the header height; ExpandedHeight remembers the
    full height so expanding restores it.

    Only the header is painted by the panel (it is NOT a child control). The body
    children are the user's — AdjustClientRect insets the client below the header
    so dropped controls sit in the body.

    As a SECTION of a side bar the header does three more things. It can hold an action
    area (TTyExPanelActions, a child the panel keeps at the header's trailing end instead
    of in the body; ActionsVisibility says when it shows). It can take the keyboard focus --
    the panel itself focused, not a child -- and then Space and Enter toggle, Left
    collapses and Right expands (the other way round right to left), with the header's
    ':focus' style as the indication; TabStop stays False until a form asks for it. And in a
    container that stacks sections (ITyExPanelHost) the panel leaves its height to that
    container, and ExpandedHeight is its weight there.

    Theming: 'TyExPanel' is the surface (background/border/radius/padding — everything
    TTyPanel's frame draws). 'TyExPanelHeader' is the header BAND: its background is an
    opt-in tint (no background => the panel's own surface shows through, unfilled) and
    its color/font drive BOTH the caption and the chevron, so a caret and its caption
    always tint together. The band is also the hit zone, so it takes ':hover' while the
    pointer is over it — that is what makes the header-hover repaint visible. Every
    value is theme-driven. }

  TTyCustomExPanel = class(TTyCustomPanel)
  private
    FCollapsed: Boolean;
    FHeaderHeight: Integer;
    FHeaderHeightExplicit: Boolean;   { True once set; False = follow --expander-header-height (density) }
    FExpandedHeight: Integer;      // remembered full height while collapsed
    FAnimationDuration: Integer;   // ms; a real timer drives frames at runtime
    FAnimator: TTyAnimator;        // 0..1 traversal driving FAnimFromH -> FAnimToH
    FAnimFromH, FAnimToH: Integer; // height endpoints for the collapse ease
    FTimer: TTimer;                // lazy; only while actually animating
    FOnExpand: TNotifyEvent;
    FOnCollapse: TNotifyEvent;
    { Pointer is over the header BAND (not merely over the control). Drives the
      ':hover' state of the 'TyExPanelHeader' key — which is what makes the repaint
      MouseMove/MouseLeave already ask for actually change something. }
    FHeaderHover: Boolean;
    FActionsVisibility: TTyExPanelActionsVisibility;
    FFocusInside: Boolean;         // the focus is on the panel or on a control in it
    FPlacingActions: Boolean;
    procedure SetCollapsed(AValue: Boolean);
    procedure SetExpandedHeight(AValue: Integer);
    procedure SetActionsVisibility(AValue: TTyExPanelActionsVisibility);
    function GetHeaderHeight: Integer;
    procedure SetHeaderHeight(AValue: Integer);
    function ScaledHeaderHeight: Integer;
    { The header's parts in AClient at APPI: what RenderTo draws by, what a click is tested
      against and where the action area is put. }
    function HeaderGeomAt(const AClient: TRect; APPI: Integer): TTyExPanelHeaderGeom;
    procedure SetHeaderHover(AValue: Boolean);
    { A child's enter and leave come up to the parent (TControl.CMMouseEnter): the pointer
      on the action area is on the header. }
    procedure CMMouseEnter(var Message: TLMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TLMessage); message CM_MOUSELEAVE;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    { Drive the control's Height to the animation's current eased endpoint. At
      runtime the timer calls this per frame; headless it is never called (the
      Collapsed setter snaps Height directly). }
    procedure ApplyAnimatedHeight;
    { Start (or restart) the collapse/expand ease toward ATargetH from the current
      Height. With a window handle a timer eases; headless it snaps immediately. }
    procedure StartHeightAnimation(ATargetH: Integer);
    procedure ReadExpandedHeight(Reader: TReader);
    procedure WriteExpandedHeight(Writer: TWriter);
  protected
    procedure DefineProperties(Filer: TFiler); override;
    { The resolved 'TyExPanelHeader' style — ONLY what that key itself declared, so the
      caller can tell "the theme tinted the band" from "the band inherits the surface".
      Its states are the panel's, except that ':hover' follows the BAND (FHeaderHover):
      the band is the click target, so hovering the body must not light it up. }
    function HeaderStyle: TTyStyleSet;
    { The band's own paint -- its tint and the line along its top edge, when
      'TyExPanelHeader' declares a background or a border, and its focus ring -- with the
      panel's rect at ARect on P. The panel draws it at its origin; the
      action area draws it again, moved back by its own position, so the band carries on
      under the buttons. }
    procedure DrawHeaderBand(P: TTyPainter; const ARect: TRect; APPI: Integer);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    { After OnKeyDown, which can take the key, the header's keys (HeaderKeyDown). }
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { The keys of a focused header: Space and Enter toggle, Left collapses, Right expands
      (mirrored right to left) -- taken even when there is nothing to do, so an arrow never
      moves the focus to a sibling instead. Any other key without Ctrl, Alt or Meta is
      offered to the container that stacks this panel. Override to add keys. }
    procedure HeaderKeyDown(var Key: Word; Shift: TShiftState); virtual;
    { What a click on the header and the toggle keys do: Collapsed := not Collapsed. }
    procedure UserToggle; virtual;
    procedure DoEnter; override;
    procedure DoExit; override;
    { Where the pointer is, in client coordinates: asked when the pointer leaves the panel
      or its action area, to tell "onto the buttons" from "away". }
    function PointerPos: TPoint; virtual;
    { The container that owns this panel's height, or nil. }
    function SectionHost: ITyExPanelHost;
    { The action area is placed by the header, wherever it was dropped. }
    procedure CustomAlignPosition(AControl: TControl; var ANewLeft, ANewTop, ANewWidth,
      ANewHeight: Integer; var AlignRect: TRect; AlignInfo: TAlignInfo); override;
    procedure SetController(AValue: TTyCustomStyleController); override;
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: Double); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure InsertControl(AControl: TControl; Index: Integer); override;
    procedure Invalidate; override;
    { #174: collapsed, the body's children are out of the tab order. The header's actions
      stay in it, and come before the body's controls. }
    procedure GetTabOrderList(List: TFPList); override;
    { Its own key, NOT the base panel's. This control paints two things a plain panel
      never paints — an interactive header band and a chevron — and pinned to 'TyPanel'
      a theme had no name to reach them by: it could not tint the band, weight its
      caption or accent the caret without restyling every panel in the app. }
    function GetStyleTypeKey: string; override;
    { The header's action area: the first TTyCustomExPanelActions among the children, or
      nil. Not cached, so nothing has to remember to drop it. }
    function HeaderActions: TTyCustomExPanelActions;
    { The header's action area, made when there is none: owned by the panel's owner, so
      that it goes into the form file. Put the buttons in it. }
    function EnsureHeaderActions: TTyCustomExPanelActions;
    { Whether the action area takes room in the header now: there is one with something to
      show, and ActionsVisibility lets it (the designer always does). }
    function ActionsShowing: Boolean;
    { The pointer is on the header band, its action area included. }
    function HeaderHot: Boolean;
    { Geometry, device px, client coordinates. }
    function HeaderHeightPx: Integer;
    function HeaderRect: TRect;
    function HeaderGeom: TTyExPanelHeaderGeom;
    function ActionsRect: TRect;
    function BodyRect: TRect;
    function HitTest(X, Y: Integer): TTyExPanelHit;
    { The action area asks for this when its row changed: the header makes room again. }
    procedure HeaderActionsChanged;
    { The full (expanded) height: the height a collapsed panel returns to when expanded,
      taken from Height as the panel collapses. In a container that stacks sections it is
      the section's weight -- the expanded sections share the room in proportion to it --
      and is not taken from Height: set it to say how much of the stack the section gets. }
    property ExpandedHeight: Integer read FExpandedHeight write SetExpandedHeight;
    property ActionsVisibility: TTyExPanelActionsVisibility read FActionsVisibility
      write SetActionsVisibility default eavAlways;
    property Alignment default taLeftJustify;   // the header's side (#116)
    property Collapsed: Boolean read FCollapsed write SetCollapsed default False;
    { Left unset it follows --expander-header-height (26 classic / 36 modern), so the
      header band grows with density; set it and that value wins and is streamed. }
    property HeaderHeight: Integer read GetHeaderHeight write SetHeaderHeight
      stored FHeaderHeightExplicit;
    { Collapse/expand animation duration in milliseconds (0 = snap instantly). A
      real timer drives the frames at runtime; headless the height snaps. }
    property AnimationDuration: Integer read FAnimationDuration write FAnimationDuration
      default 160;
    property OnExpand: TNotifyEvent read FOnExpand write FOnExpand;
    property OnCollapse: TNotifyEvent read FOnCollapse write FOnCollapse;
  end;

  { TTyExPanel publishes TTyCustomExPanel's properties; everything lives in TTyCustomExPanel. }
  TTyExPanel = class(TTyCustomExPanel)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
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
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
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
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    { Caption is TControl's; the custom class draws it in the header band. }
    property Caption;
    property Alignment;
    property VerticalAlignment;
    property WordWrap;
    property ShowAccelChar;
    property DockSite;
    property UseDockManager;
    property OnDockDrop;
    property OnDockOver;
    property OnUnDock;
    property OnGetSiteInfo;
    property OnGetDockCaption;
    property OnStartDock;
    property OnEndDock;
    property Align;
    property Anchors;
    property Collapsed;
    property HeaderHeight;
    property AnimationDuration;
    property OnExpand;
    property OnCollapse;
    property ActionsVisibility;
  end;

{ PURE, headless-tested geometry. All in DEVICE pixels (caller scales HeaderHeight). }

{ The header's parts. AHeader is the band; AInner the part of it inside the frame's border,
  which the action area is cut from the trailing end of. AInset (BorderWidth) keeps the
  chevron and the actions off the two ends; the chevron's box is as wide as the band is
  high; ATrailingPad is where the caption ends when there are no actions. AActionsWidth is
  what the actions ask for (0: none): they keep it until the caption has nothing left, and
  then give way themselves, so the chevron always stays whole. ARightToLeft mirrors all
  three in the band. }
function TyExPanelHeaderLayout(const AHeader, AInner: TRect; AInset, ATrailingPad,
  AActionsWidth: Integer; ARightToLeft: Boolean): TTyExPanelHeaderGeom;

{ The action area's row: the children in order from the leading end, APad before the first
  and after the last, AGap between two, each centred on AAvailH at its own height (a taller
  one runs past both edges and is cut by the area). A row wider than AAvailW keeps its
  trailing end in view. ARightToLeft mirrors the row in AAvailW. Size does not depend on
  the room; with no children it is (0, 0). }
function TyExPanelActionsFlow(const AWidths, AHeights: array of Integer;
  AAvailW, AAvailH, APad, AGap: Integer; ARightToLeft: Boolean): TTyExPanelFlow;

{ The header band across the top of the client rect: full width, AHeaderHeight tall,
  clamped so it never exceeds the client height. }
function TyExPanelHeaderRect(const AClient: TRect; AHeaderHeight: Integer): TRect;

{ The three points of the expand/collapse chevron triangle, centered in a small square
  zone at the LEFT of AHeaderRect. When AExpanded the triangle points DOWN (body shown);
  when collapsed it points RIGHT (body hidden). Device pixels. The panel no longer paints
  this filled triangle (it draws TyExPanelChevronKind's chevron in the same gutter); the
  function stays for callers that used it. }
function TyExPanelChevronPoints(const AHeaderRect: TRect; AExpanded: Boolean): TTyTriangle;

{ The chevron the header draws: down while the body shows, right while it is hidden. }
function TyExPanelChevronKind(AExpanded: Boolean): TTyGlyphKind;

{ Interpolated height at ease parameter t in 0..1, from ACollapsedH toward AExpandedH.
  t=0 -> ACollapsedH, t=1 -> AExpandedH (linear in t; the CALLER passes an eased t). }
function TyExPanelHeightAt(ACollapsedH, AExpandedH: Integer; t: Single): Integer;

implementation

uses
  Forms;

{ ---- pure geometry ---- }

function TyExPanelHeaderRect(const AClient: TRect; AHeaderHeight: Integer): TRect;
var
  h, clientH: Integer;
begin
  clientH := AClient.Bottom - AClient.Top;
  h := AHeaderHeight;
  if h < 0 then h := 0;
  if h > clientH then h := clientH;   // never taller than the client
  Result := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + h);
end;

function TyExPanelChevronPoints(const AHeaderRect: TRect; AExpanded: Boolean): TTyTriangle;
var
  bandH, zone, cx, cy, half: Integer;
begin
  // A small square zone at the header's left, vertically centered. The chevron
  // is ~40% of the band height so it stays a clean caret regardless of band size.
  bandH := AHeaderRect.Bottom - AHeaderRect.Top;
  if bandH < 1 then bandH := 1;
  zone := (bandH * 40) div 100;
  if zone < 5 then zone := 5;
  if Odd(zone) then Dec(zone);        // keep it even so the apex sits on a pixel
  half := zone div 2;
  // Center of the zone: one band-height in from the left edge (a comfortable gutter),
  // vertically centered in the band.
  cx := AHeaderRect.Left + bandH div 2;
  cy := (AHeaderRect.Top + AHeaderRect.Bottom) div 2;
  if AExpanded then
  begin
    // Down-pointing: apex at bottom-center, base across the top.
    Result[0] := Point(cx - half, cy - half);
    Result[1] := Point(cx + half, cy - half);
    Result[2] := Point(cx,        cy + half);
  end
  else
  begin
    // Right-pointing: apex at right-center, base down the left.
    Result[0] := Point(cx - half, cy - half);
    Result[1] := Point(cx - half, cy + half);
    Result[2] := Point(cx + half, cy);
  end;
end;

function TyExPanelChevronKind(AExpanded: Boolean): TTyGlyphKind;
begin
  if AExpanded then Result := tgChevronDown else Result := tgChevronRight;
end;

function TyExPanelHeightAt(ACollapsedH, AExpandedH: Integer; t: Single): Integer;
begin
  Result := TyLerpI(ACollapsedH, AExpandedH, t);
end;

function TyExPanelHeaderLayout(const AHeader, AInner: TRect; AInset, ATrailingPad,
  AActionsWidth: Integer; ARightToLeft: Boolean): TTyExPanelHeaderGeom;
var
  bandH, trail, w: Integer;

  function Mirrored(const R: TRect): TRect;
  begin
    Result := Rect(AHeader.Left + AHeader.Right - R.Right, R.Top,
      AHeader.Left + AHeader.Right - R.Left, R.Bottom);
  end;

begin
  bandH := AHeader.Bottom - AHeader.Top;
  if bandH < 0 then bandH := 0;
  if AInset < 0 then AInset := 0;
  // The chevron's gutter is as wide as the band is high, so the mark sits in a square.
  Result.Chevron := Rect(AHeader.Left + AInset, AHeader.Top,
    AHeader.Left + AInset + bandH, AHeader.Bottom);
  // The actions end where the frame and the inset let them, and reach back from there --
  // over the caption's room first, never over the chevron.
  trail := AInner.Right - AInset;
  w := AActionsWidth;
  if w > trail - Result.Chevron.Right then w := trail - Result.Chevron.Right;
  if w < 0 then w := 0;
  Result.Actions := Rect(trail - w, AInner.Top, trail, AInner.Bottom);
  if Result.Actions.Bottom < Result.Actions.Top then
    Result.Actions.Bottom := Result.Actions.Top;
  if AActionsWidth > 0 then
    Result.Caption := Rect(Result.Chevron.Right, AHeader.Top, Result.Actions.Left,
      AHeader.Bottom)
  else
    Result.Caption := Rect(Result.Chevron.Right, AHeader.Top,
      AHeader.Right - ATrailingPad, AHeader.Bottom);
  if Result.Caption.Right < Result.Caption.Left then
    Result.Caption.Right := Result.Caption.Left;
  if ARightToLeft then   // #153: the whole header the other way round
  begin
    Result.Chevron := Mirrored(Result.Chevron);
    Result.Caption := Mirrored(Result.Caption);
    Result.Actions := Mirrored(Result.Actions);
  end;
end;

function TyExPanelActionsFlow(const AWidths, AHeights: array of Integer;
  AAvailW, AAvailH, APad, AGap: Integer; ARightToLeft: Boolean): TTyExPanelFlow;
var
  n, i, x, w, h, left: Integer;
begin
  Result := Default(TTyExPanelFlow);
  n := Length(AWidths);
  if Length(AHeights) < n then n := Length(AHeights);
  if n = 0 then Exit;
  if APad < 0 then APad := 0;
  if AGap < 0 then AGap := 0;
  Result.Size.cx := 2 * APad + (n - 1) * AGap;
  for i := 0 to n - 1 do
  begin
    if AWidths[i] > 0 then Inc(Result.Size.cx, AWidths[i]);
    if AHeights[i] > Result.Size.cy then Result.Size.cy := AHeights[i];
  end;
  // A row that fits starts after the leading pad; one that does not ends a pad before the
  // trailing end, and it is its start that runs out of the area.
  if Result.Size.cx <= AAvailW then x := APad
  else x := AAvailW - Result.Size.cx + APad;
  SetLength(Result.Rects, n);
  for i := 0 to n - 1 do
  begin
    w := AWidths[i];
    if w < 0 then w := 0;
    h := AHeights[i];
    if h < 0 then h := 0;
    if ARightToLeft then left := AAvailW - x - w
    else left := x;
    Result.Rects[i] := Bounds(left, (AAvailH - h) div 2, w, h);
    Inc(x, w + AGap);
  end;
end;

{ ---- TTyCustomExPanelActions ---- }

constructor TTyCustomExPanelActions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { csDesignFixedBounds: the header places it, the designer's grips would only fight that.
    The two KeepChild flags: AutoSize, turned on in code, would otherwise have
    TWinControl.DoAutoSize move the children to the top left, against the row laid out here. }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus,
    csAutoSizeKeepChildLeft, csAutoSizeKeepChildTop];
  inherited SetAlign(alCustom);
end;

function TTyCustomExPanelActions.GetStyleTypeKey: string;
begin
  Result := TyExPanelActionsKey;
end;

procedure TTyCustomExPanelActions.SetAlign(Value: TAlign);
begin
  { The panel's CustomAlignPosition says where it goes; no other value is taken. }
  inherited SetAlign(alCustom);
end;

function TTyCustomExPanelActions.CanFocus: Boolean;
begin
  Result := False;
end;

function TTyCustomExPanelActions.ChildClassAllowed(ChildClass: TClass): Boolean;
begin
  Result := inherited ChildClassAllowed(ChildClass)
    and not ChildClass.InheritsFrom(TTyCustomExPanel)
    and not ChildClass.InheritsFrom(TTyCustomExPanelActions);
end;

function TTyCustomExPanelActions.Panel: TTyCustomExPanel;
begin
  if (Parent is TTyCustomExPanel) and (TTyCustomExPanel(Parent).HeaderActions = Self) then
    Result := TTyCustomExPanel(Parent)
  else
    Result := nil;
end;

function TTyCustomExPanelActions.IsControlVisible: Boolean;
begin
  Result := inherited IsControlVisible;
  { Nobody has to announce the change when the first area is deleted or this one is moved
    into a panel: both go through the form's layout pass, which asks here again. }
  if Result and not (csDesigning in ComponentState) and (Panel = nil) then
    Result := False;
end;

function TTyCustomExPanelActions.OwnPPI: Integer;
begin
  Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyCustomExPanelActions.HasVisibleChild: Boolean;
var
  i: Integer;
begin
  for i := 0 to ControlCount - 1 do
    if Controls[i].IsControlVisible then Exit(True);
  Result := False;
end;

function TTyCustomExPanelActions.MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
begin
  Result := MulDiv(StyleMetric(AName, ADefault), APPI, 96);
  if Result < 0 then Result := 0;
end;

function TTyCustomExPanelActions.RowAt(APPI, AAvailW, AAvailH: Integer;
  out AKids: TTyExPanelKids): TTyExPanelFlow;
var
  ws, hs: array of Integer;
  i, n, own, w, h: Integer;
  c: TControl;
begin
  { The children's sizes are device px at this control's density; asked for another, they
    are scaled over, so that one row is in one scale. A child counts at its minimum size
    when that is larger: a button sets MinWidth from its caption, and SetBounds then makes
    it wider than the Width it was given. }
  own := OwnPPI;
  AKids := nil;
  ws := nil;
  hs := nil;
  SetLength(AKids, ControlCount);
  SetLength(ws, ControlCount);
  SetLength(hs, ControlCount);
  n := 0;
  for i := 0 to ControlCount - 1 do
  begin
    c := Controls[i];
    if not c.IsControlVisible then Continue;
    w := c.Width;
    if c.Constraints.MinWidth > w then w := c.Constraints.MinWidth;
    h := c.Height;
    if c.Constraints.MinHeight > h then h := c.Constraints.MinHeight;
    AKids[n] := c;
    ws[n] := MulDiv(w, APPI, own);
    hs[n] := MulDiv(h, APPI, own);
    Inc(n);
  end;
  SetLength(AKids, n);
  SetLength(ws, n);
  SetLength(hs, n);
  Result := TyExPanelActionsFlow(ws, hs, AAvailW, AAvailH,
    MetricPx(TyExPanelActionsPadVar, TyExPanelActionsPadDef, APPI),
    MetricPx(TyExPanelActionsGapVar, TyExPanelActionsGapDef, APPI), IsRightToLeft);
end;

function TTyCustomExPanelActions.PreferredWidthAt(APPI, ASlot: Integer): Integer;
var
  kids: TTyExPanelKids;
begin
  Result := RowAt(APPI, 0, 0, kids).Size.cx;
  if Length(kids) = 0 then
    { Empty, it takes no room from the caption at run time; the designer gets a slot to
      drop the first button on. }
    if csDesigning in ComponentState then Result := ASlot
    else Result := 0;
end;

procedure TTyCustomExPanelActions.AdjustSize;
begin
  inherited AdjustSize;
  { A child added, removed, shown, hidden or resized ends here (TControl.AdjustSize goes up
    to the parent): the header gives the area its new width and the caption what is left. }
  if (Parent is TTyCustomExPanel)
     and ([csDestroying, csLoading] * Parent.ComponentState = []) then
    TTyCustomExPanel(Parent).HeaderActionsChanged;
end;

procedure TTyCustomExPanelActions.AlignControls(AControl: TControl;
  var RemainingClientRect: TRect);
var
  kids: TTyExPanelKids;
  fl: TTyExPanelFlow;
  cr, r: TRect;
  i: Integer;
begin
  { Not inherited: the children's Align and Anchors do not count here, the row does.
    Placing a child comes back here, hence the guard. }
  if FInLayout then Exit;
  FInLayout := True;
  try
    // As LCL's own AlignControls starts: the rect comes in whole.
    cr := RemainingClientRect;
    AdjustClientRect(cr);
    fl := RowAt(OwnPPI, cr.Right - cr.Left, cr.Bottom - cr.Top, kids);
    for i := 0 to High(kids) do
    begin
      r := fl.Rects[i];
      kids[i].SetBounds(cr.Left + r.Left, cr.Top + r.Top, r.Right - r.Left, r.Bottom - r.Top);
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TTyCustomExPanelActions.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, slot: TTyStyleSet;
  R, pr: TRect;
  pn: TTyCustomExPanel;
  own: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    { With no background of its own the area is a piece of the header: the panel draws its
      band here too, from where the panel's own corner is on this painter. }
    pn := Panel;
    if (pn <> nil) and not (tpBackground in S.Present) then
    begin
      own := OwnPPI;
      pr := Bounds(-MulDiv(Left, APPI, own), -MulDiv(Top, APPI, own),
        MulDiv(pn.ClientWidth, APPI, own), MulDiv(pn.ClientHeight, APPI, own));
      pn.DrawHeaderBand(P, pr, APPI);
    end;
    { In the designer an empty area shows its slot: seen, it can be dropped on. }
    if (csDesigning in ComponentState) and not HasVisibleChild then
    begin
      slot := ActiveController.Model.ResolveOverride('border-color: var(--border);');
      if tpBorderColor in slot.Present then
        P.StrokeBorder(R, 0, 1, slot.BorderColor);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomExPanelActions.Paint;
begin
  // No paint cache: it is small, and its children cover most of it.
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ ---- TTyCustomExPanel ---- }

constructor TTyCustomExPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // TTyPanel already adds csAcceptsControls (real container) and sets a default size.
  { The header caption has always sat at the left; now that it honours Alignment (#116),
    the left is what it starts at -- and the default says so, so a form that never set it
    reads the header exactly as before. }
  Alignment := taLeftJustify;
  FCollapsed := False;
  FHeaderHeight := TyExPanelDefaultHeaderHeight;   { fallback; unused while not explicit }
  FHeaderHeightExplicit := False;                  { follow --expander-header-height (density) }
  FAnimationDuration := 160;
  FActionsVisibility := eavAlways;
  // A taller default than the base panel so there is a visible body under the header.
  Width := 200;
  Height := 140;
  FExpandedHeight := Height;
  FAnimator := TyAnimatorInit(FAnimationDuration, teEaseOutCubic);
  FAnimator.SetTargetImmediate(1);   // settled (not mid-animation)
  FAnimFromH := Height;
  FAnimToH := Height;
end;

destructor TTyCustomExPanel.Destroy;
begin
  // Free the timer first so its callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyCustomExPanel.GetStyleTypeKey: string;
begin
  Result := 'TyExPanel';
end;

function TTyCustomExPanel.HeaderStyle: TTyStyleSet;
var
  states: TTyStateSet;
begin
  // Swap the control-wide hover for the BAND hover: TTyCustomControl sets FHover for the
  // whole client area, but only the band is clickable, so only the band may read as hot.
  states := CurrentStates;
  Exclude(states, tysHover);
  if FHeaderHover and IsEnabled then Include(states, tysHover);
  Result := PartStyle('TyExPanelHeader', StyleClass, states);
end;

{ Effective header height: an explicit set wins; otherwise follow the theme's
  --expander-header-height (density pack raises it for modern). Resolved live so a
  density toggle re-heights the header on the next layout. }
function TTyCustomExPanel.GetHeaderHeight: Integer;
var
  fh: Integer;
begin
  if FHeaderHeightExplicit then
    Result := FHeaderHeight
  else
  begin
    Result := ActiveController.Metric('--expander-header-height', TyExPanelDefaultHeaderHeight);
    { #146: and tall enough for the caption's font, which a fixed header clipped }
    fh := TyFontHeightPx(ResolveFontSize(PartStyle('TyExPanelHeader', StyleClass, [])), 96) + 2;
    if fh > Result then Result := fh;
  end;
end;

function TTyCustomExPanel.ScaledHeaderHeight: Integer;
begin
  Result := MulDiv(GetHeaderHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

procedure TTyCustomExPanel.AdjustClientRect(var ARect: TRect);
var
  S: TTyStyleSet;
  bw: Integer;
begin
  inherited AdjustClientRect(ARect);
  // The body (where child controls live) starts below the header band.
  Inc(ARect.Top, ScaledHeaderHeight);
  // ...and clears the BORDER on the other three sides. DrawFrame strokes the border INSIDE
  // the control's rect, so without this an alClient child starts at x=0 — directly on top of
  // the border line, which reads as the content spilling out of the panel. (The header band
  // already covers the top edge.) Only the border, deliberately not the themed padding: this
  // is TTyPanel's client rect, and insetting it further would silently re-lay-out every
  // existing ExPanel's children.
  S := CurrentStyle;
  if TyBorderVisible(S) then bw := MulDiv(S.BorderWidth, Font.PixelsPerInch, 96) else bw := 0;
  if bw > 0 then
  begin
    Inc(ARect.Left, bw);
    Dec(ARect.Right, bw);
    Dec(ARect.Bottom, bw);
  end;
  if ARect.Top > ARect.Bottom then ARect.Top := ARect.Bottom;
  if ARect.Left > ARect.Right then ARect.Left := ARect.Right;
end;

procedure TTyCustomExPanel.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;   // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyCustomExPanel.HandleTimer(Sender: TObject);
begin
  if FAnimator.Advance(FTimer.Interval) then
    ApplyAnimatedHeight;
  if not FAnimator.Running then
    FTimer.Enabled := False;
end;

procedure TTyCustomExPanel.ApplyAnimatedHeight;
begin
  // Drive Height along the eased curve between the two endpoints. Setting Height
  // re-lays-out the children and repaints via the LCL.
  Height := TyExPanelHeightAt(FAnimFromH, FAnimToH, FAnimator.Eased);
end;

procedure TTyCustomExPanel.StartHeightAnimation(ATargetH: Integer);
begin
  FAnimFromH := Height;
  FAnimToH := ATargetH;
  FAnimator.DurationMs := FAnimationDuration;
  if HandleAllocated and (FAnimationDuration > 0) then
  begin
    // Real window: ease the height over time.
    FAnimator.Progress := 0;
    FAnimator.Target := 1;
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless (no handle) or zero duration: SNAP to the final height so the
    // geometry is settled immediately (documented contract for tests).
    FAnimator.SetTargetImmediate(1);
    Height := ATargetH;
  end;
end;

procedure TTyCustomExPanel.SetCollapsed(AValue: Boolean);
var
  targetH: Integer;
  frm: TCustomForm;
  host: ITyExPanelHost;
begin
  if FCollapsed = AValue then Exit;
  FCollapsed := AValue;
  { #152: while a form is read, Height is the height the panel was saved at, which for a
    collapsed panel is its header's: taken for the expanded height, it left nothing to expand
    to. The expanded height comes from its own stored value (DefineProperties). }
  if csLoading in ComponentState then Exit;
  { In a container that stacks sections the heights are the container's: it is told, and
    gives every section its new height (over this panel's AnimationDuration). The panel
    does not size itself there, and ExpandedHeight is not taken from Height: it is the
    section's weight, and the height the stack gave it is not what it weighs. }
  host := SectionHost;
  if FCollapsed then
  begin
    if host <> nil then
      host.SectionToggled(Self)
    else
    begin
      // Remember the full height so expanding restores it. But if a height animation is still in
      // flight (e.g. collapsing mid-EXPAND), the live Height is an interim eased value — keep the
      // already-captured FExpandedHeight (the settled full height from before the animation) so the
      // panel still restores to its true size.
      if (FTimer = nil) or not FTimer.Enabled then
        FExpandedHeight := Height;
      targetH := ScaledHeaderHeight;
      StartHeightAnimation(targetH);
    end;
    { #174: the focus on a control of the body goes on to the next control after the panel --
      left there, the keys went into a control nobody could see. }
    frm := GetParentForm(Self);
    if (frm <> nil) and (frm.ActiveControl <> nil) and (frm.ActiveControl <> Self)
       and ContainsControl(frm.ActiveControl) then
    begin
      frm.SelectNext(Self, True, True);
      if ContainsControl(frm.ActiveControl) then frm.ActiveControl := nil;
    end;
    if Assigned(FOnCollapse) then FOnCollapse(Self);
  end
  else
  begin
    if host <> nil then
      host.SectionToggled(Self)
    else
    begin
      targetH := FExpandedHeight;
      if targetH < ScaledHeaderHeight then targetH := ScaledHeaderHeight;
      StartHeightAnimation(targetH);
    end;
    if Assigned(FOnExpand) then FOnExpand(Self);
  end;
  Invalidate;
end;

procedure TTyCustomExPanel.SetExpandedHeight(AValue: Integer);
var
  host: ITyExPanelHost;
begin
  if FExpandedHeight = AValue then Exit;
  FExpandedHeight := AValue;
  // In a stack this is the section's weight: the stack shares its room out again.
  host := SectionHost;
  if host <> nil then host.SectionChanged(Self);
end;

function TTyCustomExPanel.SectionHost: ITyExPanelHost;
begin
  if (Parent = nil) or not Supports(Parent, ITyExPanelHost, Result) then
    Result := nil;
end;

procedure TTyCustomExPanel.DefineProperties(Filer: TFiler);
begin
  inherited DefineProperties(Filer);
  { #152: saved collapsed, a panel is saved at its header's height, so the height it opens to
    is saved beside it. Not a published property: a 3.0 form only gains a value. }
  { In a container that stacks sections it is the section's weight, and is saved for an
    open section as well: nothing else in the form file holds it. }
  Filer.DefineProperty('ExpandedHeight', @ReadExpandedHeight, @WriteExpandedHeight,
    FCollapsed or (SectionHost <> nil));
end;

procedure TTyCustomExPanel.ReadExpandedHeight(Reader: TReader);
begin
  FExpandedHeight := Reader.ReadInteger;
end;

procedure TTyCustomExPanel.WriteExpandedHeight(Writer: TWriter);
begin
  Writer.WriteInteger(FExpandedHeight);
end;

procedure TTyCustomExPanel.SetHeaderHeight(AValue: Integer);
var
  was: Integer;
  host: ITyExPanelHost;
begin
  if AValue < 1 then AValue := 1;
  { #146: compared with the height the header HAD -- the theme's, until it is pinned -- not
    with the field: 26 already in it, under a theme of 32, was a pin that changed nothing. }
  was := GetHeaderHeight;
  FHeaderHeightExplicit := True;   { host pinned it, even at the fallback value }
  FHeaderHeight := AValue;
  if was = AValue then Exit;
  host := SectionHost;
  if host <> nil then
    host.SectionChanged(Self)   // the stack gives a collapsed section its header's height
  // Collapsed height equals the header height, so keep it in step while collapsed
  // (unless an animation is currently in flight driving the height itself).
  else if FCollapsed and ((FTimer = nil) or not FTimer.Enabled) then
    Height := ScaledHeaderHeight;
  Realign;   // body inset changed
  Invalidate;
end;

procedure TTyCustomExPanel.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  { inherited focuses the panel when it is a tab stop: a click on the header is where the
    keyboard goes next. }
  inherited MouseDown(Button, Shift, X, Y);
  // The header toggles; its action area never does, whatever is or is not under the click.
  if (Button = mbLeft) and IsEnabled and (HitTest(X, Y) = ephHeader) then
    UserToggle;
end;

procedure TTyCustomExPanel.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHeaderHover(HitTest(X, Y) in [ephHeader, ephActions]);
end;

procedure TTyCustomExPanel.MouseLeave;
var
  p: TPoint;
begin
  inherited MouseLeave;
  { Onto a button of the action area is still on the header: the area is a child window, so
    the panel is told the pointer left, and only where the pointer is now tells the two
    apart. Hidden at once, the buttons would be gone from under the pointer that came for
    them. }
  p := PointerPos;
  SetHeaderHover(HitTest(p.X, p.Y) in [ephHeader, ephActions]);
end;

procedure TTyCustomExPanel.CMMouseEnter(var Message: TLMessage);
begin
  inherited;
  // Straight onto the action area (a child's enter, passed up): the header is hot.
  if (Message.LParam <> 0) and (TObject(Message.LParam) = HeaderActions) then
    SetHeaderHover(True);
end;

procedure TTyCustomExPanel.CMMouseLeave(var Message: TLMessage);
var
  p: TPoint;
begin
  inherited;
  // Off a child: still on the band, or gone.
  if Message.LParam <> 0 then
  begin
    p := PointerPos;
    SetHeaderHover(HitTest(p.X, p.Y) in [ephHeader, ephActions]);
  end;
end;

function TTyCustomExPanel.PointerPos: TPoint;
begin
  if HandleAllocated then
    Result := ScreenToClient(Mouse.CursorPos)
  else
    Result := Point(-1, -1);   // no window, no pointer over it
end;

procedure TTyCustomExPanel.SetHeaderHover(AValue: Boolean);
begin
  if FHeaderHover = AValue then Exit;
  FHeaderHover := AValue;
  // Hover-only actions come and go with it, and the band's ':hover' repaints.
  HeaderActionsChanged;
end;

function TTyCustomExPanel.HeaderHot: Boolean;
begin
  Result := FHeaderHover;
end;

procedure TTyCustomExPanel.DoEnter;
begin
  FFocusInside := True;
  inherited DoEnter;
  HeaderActionsChanged;
end;

procedure TTyCustomExPanel.DoExit;
begin
  FFocusInside := False;
  inherited DoExit;
  HeaderActionsChanged;
end;

procedure TTyCustomExPanel.UserToggle;
begin
  SetCollapsed(not FCollapsed);
end;

procedure TTyCustomExPanel.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);   // OnKeyDown first: it can take the key
  if (Key <> 0) and IsEnabled then
    HeaderKeyDown(Key, Shift);
end;

procedure TTyCustomExPanel.HeaderKeyDown(var Key: Word; Shift: TShiftState);
var
  k: Word;
  host: ITyExPanelHost;
begin
  // With a modifier the key is somebody's shortcut, not the header's.
  if Shift * [ssShift, ssCtrl, ssAlt, ssMeta] <> [] then Exit;
  k := Key;
  if IsRightToLeft then   // the arrow that points at the body's side opens
    case k of
      VK_LEFT:  k := VK_RIGHT;
      VK_RIGHT: k := VK_LEFT;
    end;
  case k of
    VK_SPACE, VK_RETURN:
      begin
        UserToggle;
        Key := 0;
      end;
    { Taken even when there is nothing to do: an arrow nobody used is LCL's "next control"
      (TApplication.DoArrowKey), and the focus would leave the header for a sibling. }
    VK_LEFT:
      begin
        if not FCollapsed then UserToggle;
        Key := 0;
      end;
    VK_RIGHT:
      begin
        if FCollapsed then UserToggle;
        Key := 0;
      end;
  else
    // Up and Down between the headers of a stack are the stack's.
    host := SectionHost;
    if host <> nil then host.SectionKeyDown(Self, Key, Shift);
  end;
end;

{ ---- the header's action area ---- }

function TTyCustomExPanel.HeaderActions: TTyCustomExPanelActions;
var
  i: Integer;
begin
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomExPanelActions then
      Exit(TTyCustomExPanelActions(Controls[i]));
  Result := nil;
end;

function TTyCustomExPanel.EnsureHeaderActions: TTyCustomExPanelActions;
var
  own: TComponent;
begin
  Result := HeaderActions;
  if Result <> nil then Exit;
  { Owned by the panel's owner -- the form -- so that it is written into the form file and
    can be picked in the designer. A panel made with Create(nil) has none, and LCL does not
    free a child without an owner (TWinControl.Destroy only takes it off), so the panel
    owns it then. }
  if Owner <> nil then own := Owner else own := Self;
  Result := TTyExPanelActions.Create(own);
  Result.Parent := Self;   // InsertControl hands it the panel's controller
end;

procedure TTyCustomExPanel.InsertControl(AControl: TControl; Index: Integer);
begin
  inherited InsertControl(AControl, Index);
  if AControl is TTyCustomExPanelActions then
  begin
    { The header leaves it room by the panel's theme; measured by another controller's, the
      room and the row would not agree. }
    TTyCustomExPanelActions(AControl).Controller := Controller;
    HeaderActionsChanged;
  end;
end;

procedure TTyCustomExPanel.SetController(AValue: TTyCustomStyleController);
var
  i: Integer;
begin
  inherited SetController(AValue);
  // inherited returns early on an unchanged value; an area put in later may carry another.
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomExPanelActions then
      TTyCustomExPanelActions(Controls[i]).Controller := AValue;
end;

function TTyCustomExPanel.ActionsShowing: Boolean;
var
  act: TTyCustomExPanelActions;
begin
  act := HeaderActions;
  if (act = nil) or not act.IsControlVisible then Exit(False);
  // The designer always shows it, empty or not: it is what the buttons are dropped on.
  if csDesigning in act.ComponentState then Exit(True);
  if not act.HasVisibleChild then Exit(False);
  Result := (FActionsVisibility = eavAlways) or FHeaderHover or FFocusInside;
end;

procedure TTyCustomExPanel.SetActionsVisibility(AValue: TTyExPanelActionsVisibility);
begin
  if FActionsVisibility = AValue then Exit;
  FActionsVisibility := AValue;
  HeaderActionsChanged;
end;

procedure TTyCustomExPanel.HeaderActionsChanged;
var
  act: TTyCustomExPanelActions;
  r: TRect;
begin
  if [csDestroying, csLoading] * ComponentState <> [] then Exit;
  { Placed here and now, not left to the next layout pass: hover-only actions follow the
    pointer, and nothing else asks for a layout when it moves. A hidden area keeps its
    place at no width, so the focus can still be tabbed into it -- which shows it. The
    same box comes back from CustomAlignPosition whenever LCL aligns the panel. }
  act := HeaderActions;
  if (act <> nil) and not FPlacingActions then
  begin
    FPlacingActions := True;
    try
      r := HeaderGeom.Actions;
      act.SetBounds(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
    finally
      FPlacingActions := False;
    end;
  end;
  Invalidate;   // the caption ends where the actions start
end;

procedure TTyCustomExPanel.CustomAlignPosition(AControl: TControl; var ANewLeft, ANewTop,
  ANewWidth, ANewHeight: Integer; var AlignRect: TRect; AlignInfo: TAlignInfo);
var
  r: TRect;
  side: Integer;
begin
  if not (AControl is TTyCustomExPanelActions) then
  begin
    inherited CustomAlignPosition(AControl, ANewLeft, ANewTop, ANewWidth, ANewHeight,
      AlignRect, AlignInfo);
    Exit;
  end;
  if AControl = HeaderActions then
    r := HeaderGeom.Actions
  else
  begin
    { A second area (pasted in; it shows only in the designer): at the start of the body,
      where it can be seen, picked and deleted. }
    side := ScaledHeaderHeight;
    r := BodyRect;
    r := Bounds(r.Left, r.Top,
      TTyCustomExPanelActions(AControl).PreferredWidthAt(Font.PixelsPerInch, side), side);
  end;
  ANewLeft := r.Left;
  ANewTop := r.Top;
  ANewWidth := r.Right - r.Left;
  ANewHeight := r.Bottom - r.Top;
end;

procedure TTyCustomExPanel.Invalidate;
var
  act: TTyCustomExPanelActions;
begin
  inherited Invalidate;
  { The action area draws its stretch of the header band (tint, hover, focus ring), and a
    child window does not repaint with its parent. Every change of the band ends in an
    Invalidate, so this is the one place that misses none of them. }
  if csDestroying in ComponentState then Exit;
  act := HeaderActions;
  if (act <> nil) and act.HandleAllocated then act.Invalidate;
end;

{ ---- geometry ---- }

function TTyCustomExPanel.HeaderHeightPx: Integer;
begin
  Result := ScaledHeaderHeight;
end;

function TTyCustomExPanel.HeaderRect: TRect;
begin
  Result := TyExPanelHeaderRect(ClientRect, ScaledHeaderHeight);
end;

function TTyCustomExPanel.HeaderGeomAt(const AClient: TRect; APPI: Integer): TTyExPanelHeaderGeom;
var
  S: TTyStyleSet;
  hdr, inner: TRect;
  hdrH, edge, aw: Integer;
begin
  S := CurrentStyle;
  hdrH := MulDiv(GetHeaderHeight, APPI, 96);
  if hdrH < 1 then hdrH := 1;
  hdr := TyExPanelHeaderRect(AClient, hdrH);
  { The actions live inside the frame's border, which DrawFrame strokes inside the
    control: at the top, at the trailing end, and -- collapsed, when the band is the whole
    panel -- at the bottom. }
  if TyBorderVisible(S) then edge := MulDiv(S.BorderWidth, APPI, 96) else edge := 0;
  inner := Rect(hdr.Left + edge, hdr.Top + edge, hdr.Right - edge, hdr.Bottom);
  if inner.Bottom > AClient.Bottom - edge then inner.Bottom := AClient.Bottom - edge;
  if inner.Bottom < inner.Top then inner.Bottom := inner.Top;
  if ActionsShowing then
    aw := HeaderActions.PreferredWidthAt(APPI, inner.Bottom - inner.Top)
  else
    aw := 0;
  // BorderWidth moves the header's chevron, caption and actions in from the sides (#115);
  // the caption's far inset stays the PANEL's padding: the band's box is the panel's box.
  Result := TyExPanelHeaderLayout(hdr, inner, MulDiv(BorderWidth, APPI, 96),
    MulDiv(S.Padding.Right + BorderWidth, APPI, 96), aw, IsRightToLeft);
end;

function TTyCustomExPanel.HeaderGeom: TTyExPanelHeaderGeom;
begin
  Result := HeaderGeomAt(ClientRect, Font.PixelsPerInch);
end;

function TTyCustomExPanel.ActionsRect: TRect;
begin
  Result := HeaderGeom.Actions;
end;

function TTyCustomExPanel.BodyRect: TRect;
begin
  Result := ClientRect;
  AdjustClientRect(Result);
end;

function TTyCustomExPanel.HitTest(X, Y: Integer): TTyExPanelHit;
var
  p: TPoint;
  g: TTyExPanelHeaderGeom;
begin
  p := Point(X, Y);
  if not PtInRect(ClientRect, p) then Exit(ephNone);
  if not PtInRect(HeaderRect, p) then Exit(ephBody);
  g := HeaderGeom;
  if (g.Actions.Right > g.Actions.Left) and PtInRect(g.Actions, p) then
    Result := ephActions
  else
    Result := ephHeader;
end;

procedure TTyCustomExPanel.DrawHeaderBand(P: TTyPainter; const ARect: TRect; APPI: Integer);
var
  S, HD: TTyStyleSet;
  hdr, bandRect, lineRect, ringRect: TRect;
  hdrH, bw, bwLogical, off: Integer;
  corners, bandCorners, ringCorners: TTyCorners;
  line: TTyFill;
begin
  S := CurrentStyle;
  HD := HeaderStyle;
  hdrH := MulDiv(GetHeaderHeight, APPI, 96);
  if hdrH < 1 then hdrH := 1;
  hdr := TyExPanelHeaderRect(ARect, hdrH);
  if TyBorderVisible(S) then
  begin
    bw := P.Scale(S.BorderWidth);   // device px: the fill inset
    bwLogical := S.BorderWidth;     // logical px: FillBackground scales corners itself
  end
  else
  begin
    bw := 0;
    bwLogical := 0;                 // border present-but-not-drawn keeps the full radius
  end;
  corners := TyEffectiveCorners(S);

  // Band tint is OPT-IN: only a header key that declares a background paints one. Say
  // nothing and the panel's single surface is left exactly as DrawFrame laid it down —
  // a second fill would re-blend the frame's antialiased corner arcs. When it IS
  // painted, the band is pulled off the border stroke and its OUTER corners follow the
  // panel's, so a tint can never spill into the corner arcs or over the frame.
  if tpBackground in HD.Present then
  begin
    bandCorners := Default(TTyCorners);
    bandCorners.TL := corners.TL - bwLogical;
    bandCorners.TR := corners.TR - bwLogical;
    if bandCorners.TL < 0 then bandCorners.TL := 0;
    if bandCorners.TR < 0 then bandCorners.TR := 0;
    bandRect := Rect(hdr.Left + bw, hdr.Top + bw, hdr.Right - bw, hdr.Bottom);
    if (bandRect.Right > bandRect.Left) and (bandRect.Bottom > bandRect.Top) then
      P.FillBackground(bandRect, HD.Background, bandCorners);
  end;

  { A line along the band's top edge, when 'TyExPanelHeader' declares a border: its colour
    and its width, read the way TyStatusBar's top line is. It is what divides frameless
    sections stacked on one surface, where a tint alone is too close to the surface in a
    dark theme to be seen. }
  if TyBorderVisible(HD) then
  begin
    line := Default(TTyFill);
    line.Kind := tfkSolid;
    line.Color := HD.BorderColor;
    lineRect := Rect(hdr.Left + bw, hdr.Top + bw, hdr.Right - bw,
      hdr.Top + bw + P.Scale(HD.BorderWidth));
    if lineRect.Bottom > hdr.Bottom then lineRect.Bottom := hdr.Bottom;
    if (lineRect.Right > lineRect.Left) and (lineRect.Bottom > lineRect.Top) then
      P.FillBackground(lineRect, line, 0);
  end;

  { The focus indication is the header's, since it is the header that takes the keys: a
    ring round the band, inside the frame, when 'TyExPanelHeader:focus' resolves an outline.
    Its outer corners follow the panel's -- the bottom two only when the band reaches the
    bottom of the frame, which is the collapsed panel. }
  if (tpOutline in HD.Present) and (HD.OutlineWidth > 0) then
  begin
    ringRect := Rect(hdr.Left + bw, hdr.Top + bw, hdr.Right - bw, hdr.Bottom);
    ringCorners := Default(TTyCorners);
    ringCorners.TL := corners.TL - bwLogical - HD.OutlineOffset;
    ringCorners.TR := corners.TR - bwLogical - HD.OutlineOffset;
    if hdr.Bottom >= ARect.Bottom - bw then
    begin
      ringRect.Bottom := ARect.Bottom - bw;
      ringCorners.BL := corners.BL - bwLogical - HD.OutlineOffset;
      ringCorners.BR := corners.BR - bwLogical - HD.OutlineOffset;
    end;
    if ringCorners.TL < 0 then ringCorners.TL := 0;
    if ringCorners.TR < 0 then ringCorners.TR := 0;
    if ringCorners.BL < 0 then ringCorners.BL := 0;
    if ringCorners.BR < 0 then ringCorners.BR := 0;
    off := P.Scale(HD.OutlineOffset);
    InflateRect(ringRect, -off, -off);
    if (ringRect.Right > ringRect.Left) and (ringRect.Bottom > ringRect.Top) then
      P.StrokeBorder(ringRect, ringCorners, HD.OutlineWidth, HD.OutlineColor);
  end;
end;

procedure TTyCustomExPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, HD, HS: TTyStyleSet;
  R: TRect;
  geom: TTyExPanelHeaderGeom;
  kind: TTyGlyphKind;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The frame (background + border) spans the WHOLE control — header and body share
    // the one themed surface, so the header is just the top band of it.
    DrawFrame(P, R, S);

    // The header band is its own themable part. HD holds ONLY what 'TyExPanelHeader'
    // declared (so the tint can stay opt-in); HS is the panel surface with those
    // declarations laid over it — what the chevron and caption actually draw with, so a
    // theme that names neither still gets exactly the panel's ink.
    HD := HeaderStyle;
    HS := S;
    TyMergeStyleSet(HS, HD);

    DrawHeaderBand(P, R, APPI);

    // Chevron in the HEADER's color (caret and caption tint together — that is how a real
    // collapse header behaves), pointing down when expanded and right when collapsed, in the
    // band-high gutter the caption starts after. The library's disclosure chevron, not the
    // filled triangle this used to paint: a solid triangle is the shape the library keeps for
    // STEPPING a value (spin, scroll), and every desktop now draws an expander as an open
    // mark. Through TyDrawChevron, so --glyph-chevron-down / -right replace it as well.
    // Where the parts are -- the chevron's gutter, the caption after it, the action area at
    // the far end, all of it the other way round right to left (#153) -- is HeaderGeomAt's
    // answer, the same one a click is tested against.
    geom := HeaderGeomAt(R, APPI);
    kind := TyExPanelChevronKind(not FCollapsed);
    if IsRightToLeft and (kind = tgChevronRight) then   // a closed one points the reading way
      kind := tgChevronLeft;
    TyDrawChevron(P, ActiveController, geom.Chevron, kind, HS.TextColor);

    // Caption text after the chevron gutter, vertically centered in the band; it stops
    // where the action area starts, and DrawCaption's ellipsis does the rest.
    if Caption <> '' then
      DrawCaption(P, geom.Caption, HS, APPI);   // Alignment & co., as the panel's (#116)

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomExPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ #174: collapsed, the body's children leave the tab order -- Tab reached them, and the keys went
  into controls nobody could see. The designer keeps them reachable. }
procedure TTyCustomExPanel.GetTabOrderList(List: TFPList);
var
  all: TFPList;
  act: TTyCustomExPanelActions;
  c: TWinControl;
  i, pass: Integer;
  bodyToo, inActions: Boolean;
begin
  bodyToo := not FCollapsed or (csDesigning in ComponentState);
  act := HeaderActions;
  if act = nil then
  begin
    if bodyToo then inherited GetTabOrderList(List);
    Exit;
  end;
  { The header's actions are seen in a collapsed panel too, so they stay; and they come
    before the body's controls whatever TabOrder the area was given, as they do on screen. }
  all := TFPList.Create;
  try
    inherited GetTabOrderList(all);
    for pass := 0 to 1 do
      for i := 0 to all.Count - 1 do
      begin
        c := TWinControl(all[i]);
        inActions := (c = act) or act.ContainsControl(c);
        if inActions <> (pass = 0) then Continue;
        if inActions or bodyToo then List.Add(c);
      end;
  finally
    all.Free;
  end;
end;

{ #174: ExpandedHeight is device px, as Height is: a DPI change scales it with the rest of the
  bounds -- left alone, the panel opened to its height at the old DPI. }
procedure TTyCustomExPanel.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: Double);
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode in [lapAutoAdjustWithoutHorizontalScrolling, lapAutoAdjustForDPI] then
    FExpandedHeight := Round(FExpandedHeight * AYProportion);
end;

end.
