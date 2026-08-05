unit tyControls.TabStrip;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LMessages, ExtCtrls,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.Animation, tyControls.Accel;

const
  { Assign to TabHeight to hand the band's height back to the theme, so it follows
    --control-height again (28 classic / 38 modern).

    Why a negative and not 0: LCL sizes its band from the font for EVERY value <= 0
    (C:/lazarus/lcl/include/tabcontrol.inc:404-406, `if NewHeight <= 0 then NewHeight :=
    GetMinimumTabHeight`), but OUR 0 already means "no band at all" -- a shipped,
    demoed capability that LCL only reaches through ShowTabs and that we would delete by
    re-pointing 0 at auto. So 0 keeps the meaning it has and auto takes the other half
    of LCL's `<= 0`, which makes a ported `TabHeight := -1` land on the SAME behaviour it
    had in Lazarus instead of silently hiding the band. It also gives the property the
    reverse gear it lacked: before this, a host that ever pinned a height could not get
    back to following the theme without hard-coding 28 (and thereby freezing the strip
    at classic size on a modern-density theme). }
  TyTabHeightAuto = -1;

type
  TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer;
    var AllowClose: Boolean) of object;

  { Pre-switch veto. Fired before the selection moves to ANewIndex (the clamped
    proposed index); clearing AllowChange aborts the switch (no page change, no
    OnChange, no fade). NOT fired during csLoading/streaming. }
  TTyTabChangingEvent = procedure(Sender: TObject; ANewIndex: Integer;
    var AllowChange: Boolean) of object;

  { Drag-reorder notification, fired after a committed reorder gesture has moved
    the dragged tab from AFromIndex to AToIndex. }
  TTyTabReorderEvent = procedure(Sender: TObject; AFromIndex, AToIndex: Integer)
    of object;

  { Page-agnostic tab-HEADER engine. Owns all header layout/render/hover/scroll/
    close-x/drag-reorder/cross-fade/mouse/keyboard logic but knows NOTHING about
    pages or any Tabs collection. Subclasses supply tab data via the abstract
    GetTabCount/GetTabCaption and react to user gestures via the virtual hooks
    (DoSelectTab/DoReorderTabs/RemoveTabData/GetTabClosableAt/TabsChanged). }
  TTyCustomTabStrip = class(TTyCustomControl)
  private
    FTabHeight: Integer;      // logical px, classic default 28 (fallback while not explicit)
    FTabHeightExplicit: Boolean;  // True once a host/.lfm sets TabHeight; False = follow
                                  // --control-height (density-aware: 28 classic / 38 modern)
    FHoverTab: Integer;       // -1 = none
    FHoverClose: Integer;     // tab index whose close (x) is hovered; -1 = none
    FOnChange: TNotifyEvent;
    FOnChanging: TTyTabChangingEvent;
    FOnReorder: TTyTabReorderEvent;
    FTabsClosable: Boolean;
    FOnTabClose: TTyTabCloseEvent;
    FHeaderRects: array of TRect;
    FCloseRects:  array of TRect;

    { Drag-reorder gesture state. FDragTab is the collection index of the tab a
      press armed as a drag candidate (-1 = none). FDragStartX is the device-px X
      of that press; FDragging flips True once the pointer travels past the drag
      threshold, switching the gesture from a click into a live reorder. }
    FDragTab:    Integer;
    FDragStartX: Integer;
    FDragging:   Boolean;
    { Collection index the dragged tab occupied when the press armed the gesture.
      FDragTab tracks the live (current) index as the tab is reseated during the
      drag; FDragOrigin is pinned so MouseUp can report the net from/to move and
      fire OnReorder exactly once for the whole gesture (-1 = no armed drag). }
    FDragOrigin: Integer;

    { Active-tab header cross-fade. FTabFade eases 0->1 when the selection moves
      to a new tab: the newly-active header blends from the inactive TyTab style
      to the active TyTab:active style. FAnimationsEnabled gates it (default True);
      with no window handle it snaps so headless pixel tests see the final style.
      FTimer is the lazy ~60fps driver. ONLY the header colour fades — the page
      child controls switch instantly (they are separate LCL controls). }
    FTabFade: TTyAnimator;
    FAnimationsEnabled: Boolean;
    FTimer: TTimer;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);

    function  GetTabHeight: Integer;
    procedure SetTabHeight(AValue: Integer);
    procedure SetTabsClosable(AValue: Boolean);
    procedure RebuildLayout(APPI: Integer);
    procedure DoCloseClick(AIndex: Integer);
    function  TabHPx(APPI: Integer): Integer;
    function  TabCaptionWidth(const ACaption: string;
                              const AStyle: TTyStyleSet; APPI: Integer): Integer;
  protected
    { Active selection index (-1 = none) and the TabIndex captured during
      csLoading (-1 = none). Protected so subclasses can read/write them while
      reconciling their own page/data backing. }
    FTabIndex: Integer;
    FPendingTabIndex: Integer;
    { Header overflow scroll. FHeaderScroll is the device-px amount the header
      strip is shifted left (>=0). FShowScrollAffordance and the two arrow rects
      are recomputed at the end of RebuildLayout. Kept protected so white-box
      tests can read them. }
    FHeaderScroll: Integer;
    FShowScrollAffordance: Boolean;
    FScrollLeftRect:  TRect;
    FScrollRightRect: TRect;
    { Device-px width of ONE overflow arrow band, 0 while the strip fits. Recomputed by
      RebuildLayout alongside the two arrow rects.

      HeaderShiftPx used to read this quantity off FScrollLeftRect.Right, which is only the
      same number while the back arrow is the one on the left. It is a CONTENT-SPACE
      reservation -- "how much of the band is not available to tab headers at each end" --
      and reading it off a rect whose side is a rendering decision is how the scroll origin
      and the arrow positions come apart. }
    FArrowBandPx: Integer;
    { Tab data is supplied by the subclass: GetTabCount/GetTabCaption are the
      only window the header engine has onto the tab model. The virtual hooks
      below let the subclass react to header gestures (select/reorder/close) and
      to data changes, defaulting to inert/simple behaviour here. }
    function GetTabCount: Integer; virtual; abstract;
    function GetTabCaption(AIndex: Integer): string; virtual; abstract;
    function GetTabClosableAt(AIndex: Integer): Boolean; virtual;
    { Protected so a subclass can publish the selection under its own name
      (TTyPageControl: ActivePageIndex). Clamps against GetTabCount, fires
      OnChanging/OnChange, calls DoSelectTab. }
    procedure SetTabIndex(AValue: Integer);
    procedure DoSelectTab(AIndex: Integer); virtual;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); virtual;
    procedure RemoveTabData(AIndex: Integer); virtual;
    procedure TabsChanged; virtual;
    { Device-px reserved at the LEFT of the header strip: the tab headers are shifted
      right by this much so a subclass can draw its own leftmost element there (e.g. a
      ribbon "File" tab). Default 0. }
    function HeaderLeftInset: Integer; virtual;
    { Which way this header band READS -- the ONE answer every x-axis consumer in this unit
      takes. RebuildLayout's arrow ends, ToScreenRect/ToReadingX, the RenderTo clip and
      caption slot, and the Left/Right arrow keys all call this and nothing else, so a
      subclass whose OWN chrome is still left-to-right can decline in one place instead of
      shipping a strip that is mirrored in three of its four consumers. TTyRibbon does
      exactly that, and tests/test.rtl.pas pins the decline.

      Default: TControl.IsRightToLeft (controls.pp:1833, = BiDiMode <> bdLeftToRight), which
      is public and works from code even though nothing publishes BiDiMode yet. }
    function HeaderRightToLeft: Boolean; virtual;
    { Does anything live BELOW the header band? A pager (TTyPageControl) hosts its
      pages there, so the area is framed as the page container. A caption-only strip
      (TTyTabSet) hosts nothing: framing it would draw an empty box under the tabs.
      Strip-only mode keeps the frame's TOP border as a baseline rail — the tabs must
      still sit on a line — and drops the rest of the box. }
    function HasPageBody: Boolean; virtual;
    procedure SetController(AValue: TTyStyleController); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    function DialogChar(var Message: TLMKey): Boolean; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
                        X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
                      X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
                         MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { Steppable animation seam (no wall clock): advance the active-tab header
      cross-fade by AMs and return True iff the eased progress changed. Tests
      drive this directly via an access subclass; the lazy TTimer drives it at
      runtime. }
    function AdvanceAnimation(AMs: Integer): Boolean;
    { Arm the header fade toward the active style WITHOUT snapping (Progress:=0;
      Target:=1) so AdvanceAnimation can interpolate it even handle-less. Test
      seam only — at runtime SetTabIndex arms it. }
    procedure ArmTabFade;
    { Eased 0..1 header-fade progress. Exposed for deterministic tests. }
    function GetTabFadeEased: Single;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function TabCount: Integer;
    function TabCaption(AIndex: Integer): string;
    { Public pure-ish geometry for tests: device px, (0,0)-local }
    function TyTabHeaderRect(AIndex: Integer): TRect;
    function TyTabCloseRect(AIndex: Integer): TRect;
    { Header overflow scroll geometry (device px, (0,0)-local).
      TyHeaderStripWidth: total unshifted width of all tab headers.
      TyMaxHeaderScroll:  largest valid FHeaderScroll (0 when content fits).
      TyTabScrollLeftRect/TyTabScrollRightRect: the prev/next arrow affordance
        rects, or (0,0,0,0) when the strip fits.
      HeaderRectShifted:  header rect translated by the current scroll offset.
      HeaderShiftPx:      device-px translation from content-space to screen — the
        scroll offset plus, when the overflow arrows show, a left inset equal to the
        left-arrow width so the first tab starts AFTER the left arrow instead of
        being clipped underneath it. }
    function TyHeaderStripWidth: Integer;
    function TyMaxHeaderScroll: Integer;
    function TyTabScrollLeftRect: TRect;
    function TyTabScrollRightRect: TRect;
    function HeaderRectShifted(AIndex: Integer): TRect;
    function HeaderShiftPx: Integer;

    { --- The ONE content-space <-> screen transform, and its exact inverse ------------

      A tab strip has FOUR consumers of the same x axis -- the paint, the click hit test,
      the drag-reorder midpoint rule and the overflow scroll offset -- and every one of them
      used to apply `OffsetRect(R, HeaderShiftPx, 0)` for itself, six copies of the same
      line. That was survivable while the transform was a translation, because a translation
      written six times is still the same translation. It stops being survivable the moment
      the transform acquires a direction: a drag whose midpoint rule did not follow the paint
      drops tabs on the wrong side of their neighbour, and no static render test can see it.

      So both directions are named here and nothing in this unit converts by hand.

      ToScreenRect: CONTENT space (what RebuildLayout builds -- reading order, tab 0 first,
        origin at the strip's start) -> control-local device px as drawn.
      ToReadingX:   the same reflection applied to a single x, i.e. ToScreenRect run
        backwards. A reflection is its own inverse, so `X in ToScreenRect(R)` and
        `ToReadingX(X) in shifted R` are the SAME predicate -- which is what lets the drag
        resolver keep one left-to-right comparison instead of growing a mirrored copy of it
        one character away from the original. }
    function ToScreenRect(const AContentRect: TRect): TRect;
    function ToReadingX(AX: Integer): Integer;
    procedure SetHeaderScroll(AValue: Integer);
    procedure ScrollTabIntoView(AIndex: Integer);

    { --- LCL-named geometry / hit-test / scroll -------------------------------------

      Three members that carry LCL's names, and therefore have to carry LCL's MEANINGS.
      The engine already had a near-twin of each under a Ty- name, and in all three cases
      the twin answers a DIFFERENT question -- which is exactly how a ported call site
      binds to the wrong member and gets a plausible wrong answer instead of a compile
      error. Each is spelled out below against the twin it is not. }

    { The tab header's rect AS DRAWN -- scroll offset and left inset applied. That is what
      TCustomTabControl.TabRect returns (comctrls.pp:476) and what any caller positioning a
      tooltip, a menu or an overlay over a tab needs. TyTabHeaderRect is the UNSHIFTED
      content-space rect: identical while the strip fits, and off by the scroll offset the
      moment it does not. Empty rect for an out-of-range index. }
    function TabRect(AIndex: Integer): TRect;
    { The rectangle the PAGE BODY occupies inside the control -- the area below the header
      band, in control-local device px. LCL's TCustomTabControl.DisplayRect (comctrls.pp:469).
      Nothing exposed this before: the inset existed only inside AdjustClientRect. }
    function DisplayRect: TRect;
    { Which tab is under a point, or -1 for NONE.

      TyDropIndexAt is not this and must not be mistaken for it: it is the drag-reorder
      target resolver, it answers with the nearest slot by shifted midpoints, it clamps into
      [0, Count-1], and so it can NEVER say "no tab here" -- ask it where a right-click
      landed on the empty strip past the last tab and it names the last tab. A context menu
      or a per-tab tooltip built on that opens on the wrong tab. This one hit-tests the real
      shifted header rects, requires the point to be inside the band, and returns -1
      everywhere else (including over the two overflow arrows, which are not tabs). }
    function IndexOfTabAt(X, Y: Integer): Integer; overload;
    function IndexOfTabAt(P: TPoint): Integer; overload;
    { Scroll the header band by Delta TABS -- LCL's unit (comctrls.pp:711/862), not ours.
      SetHeaderScroll takes DEVICE PIXELS, so a mechanical rename of a ported ScrollTabs(2)
      would scroll two pixels and look like nothing happened. Positive Delta moves the band
      toward later tabs. Clamped by SetHeaderScroll. }
    procedure ScrollTabs(Delta: Integer);

    { Drag-reorder helpers (pure, no mutation; device px).
      TyDragThresholdPx: how far (in device px at APPI) a press must move before
        a drag counts as a reorder rather than a click. Small + PPI-scaled.
      TyDropIndexAt: the collection index a drag at device-X should drop into,
        using shifted header midpoints. Returns the first index i whose shifted
        midpoint lies to the right of X; clamped to [0, Count-1] (default the
        last index when X is past every midpoint). }
    function TyDragThresholdPx(APPI: Integer): Integer;
    function TyDropIndexAt(X, APPI: Integer): Integer;

    { The tab index whose close (x) button the pointer currently hovers, or -1
      when none. Distinct from whole-tab hover (FHoverTab): the x lights up on
      its own so the buyer's user sees a precise close affordance. Read-only;
      driven by MouseMove/MouseLeave. }
    property TyTabHoverClose: Integer read FHoverClose;

    { On by default. When enabled and the control has a window handle, switching
      tabs cross-fades the newly-active header background from the inactive to the
      active style; with no handle (every render test) it snaps, preserving the
      existing exact-pixel header tests. Pages always switch instantly. }
    property AnimationsEnabled: Boolean read FAnimationsEnabled write FAnimationsEnabled default True;
    { The active selection. PUBLIC (not published) on the base: streaming and a
      published RTTI default belong to a concrete subclass that owns real tab
      data. Routes through SetTabIndex, which clamps against GetTabCount, fires
      the OnChanging veto + DoSelectTab + OnChange, and arms the header fade. }
    property TabIndex: Integer read FTabIndex write SetTabIndex;
  published
    { Header band height in logical px, DPI-scaled at paint time. Left unset it follows
      the theme's --control-height token, so the strip is 28 at classic density and 38 at
      modern density automatically. Set it explicitly and that value wins; assign
      TyTabHeightAuto (or any negative, as LCL does) to hand it back to the theme.

      0 means NO band -- the pages fill the whole control and the host drives paging
      itself. This is where we differ from LCL, ON PURPOSE: LCL's 0 means "size it from
      the font", which is what our UNSET state already does, and LCL spells "no band"
      ShowTabs := False. The only code this catches out is a port that assigns a literal
      0 expecting auto; TyTabHeightAuto is the value it wants, and a Lazarus .lfm can
      never carry the trap because LCL streams TabHeight only when > 0.

      Integer, not LCL's Smallint: narrowing would make an over-large assignment wrap
      silently under the default {$R-}, which is the same class of quiet corruption this
      property is being cleaned up for. Widening costs nothing.

      `stored FTabHeightExplicit`, not LCL's `TabHeight > 0`: a designed-in 0 is a real
      decision that must round-trip through the .lfm, and > 0 would drop it on every
      reload -- the band would silently come back. }
    property TabHeight: Integer read GetTabHeight write SetTabHeight stored FTabHeightExplicit;
    property TabsClosable: Boolean read FTabsClosable write SetTabsClosable default False;
    property OnTabClose: TTyTabCloseEvent read FOnTabClose write FOnTabClose;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnChanging: TTyTabChangingEvent read FOnChanging write FOnChanging;
    property OnReorder: TTyTabReorderEvent read FOnReorder write FOnReorder;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyCustomTabStrip }

constructor TTyCustomTabStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  FTabIndex  := -1;
  FPendingTabIndex := -1;
  FTabHeight := 28;             { fallback; unused while FTabHeightExplicit=False }
  FTabHeightExplicit := False;  { follow --control-height (density-aware) until set }
  FHoverTab  := -1;
  FHoverClose := -1;
  FHeaderScroll := 0;
  FDragTab   := -1;
  FDragging  := False;
  FDragOrigin := -1;
  FTabsClosable := False;
  FAnimationsEnabled := True;
  { Active-tab header cross-fade: rests at 1 (settled = active style), ~120ms full
    traversal, decelerating. Mirrors the Button hover-fade timing. }
  FTabFade.Progress := 1;
  FTabFade.Target := 1;
  FTabFade.DurationMs := 120;
  FTabFade.Easing := teEaseOutCubic;
  TabStop    := True;
  Width      := 300;
  Height     := 200;
end;

destructor TTyCustomTabStrip.Destroy;
begin
  { FTimer is owned by Self (would be freed by DestroyComponents), but free it
    explicitly first so the OnTimer callback can never fire mid-teardown. }
  FreeAndNil(FTimer);
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyCustomTabStrip.DialogChar(var Message: TLMKey): Boolean;
var I: Integer;
begin
  if Enabled then   // match the Enabled gate on MouseDown/KeyDown + the sibling controls
    for I := 0 to GetTabCount - 1 do
      if TyIsAccelKey(Message, GetTabCaption(I)) then
      begin
        SetTabIndex(I);
        Exit(True);
      end;
  Result := inherited DialogChar(Message);
end;

{ Default virtual hooks. Subclasses override these to wire real tab data:
  GetTabClosableAt reports per-tab closability; DoSelectTab/DoReorderTabs/
  RemoveTabData react to selection/reorder/close gestures; TabsChanged repaints
  when the header model changed (suppressed during streaming). }
function TTyCustomTabStrip.GetTabClosableAt(AIndex: Integer): Boolean;
begin
  Result := FTabsClosable;
end;

procedure TTyCustomTabStrip.DoSelectTab(AIndex: Integer);
begin
end;

procedure TTyCustomTabStrip.DoReorderTabs(AFromIndex, AToIndex: Integer);
begin
end;

procedure TTyCustomTabStrip.RemoveTabData(AIndex: Integer);
begin
end;

procedure TTyCustomTabStrip.TabsChanged;
begin
  if not (csLoading in ComponentState) then Invalidate;
end;

function TTyCustomTabStrip.HeaderLeftInset: Integer;
begin
  Result := 0;
end;

function TTyCustomTabStrip.HeaderRightToLeft: Boolean;
begin
  Result := IsRightToLeft;
end;

function TTyCustomTabStrip.HasPageBody: Boolean;
begin
  Result := True;
end;

procedure TTyCustomTabStrip.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyCustomTabStrip.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then
    Invalidate;
  if not FTabFade.Running then
    FTimer.Enabled := False;
end;

function TTyCustomTabStrip.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FTabFade.Advance(AMs);
end;

procedure TTyCustomTabStrip.ArmTabFade;
begin
  FTabFade.Progress := 0;
  FTabFade.Target := 1;
end;

function TTyCustomTabStrip.GetTabFadeEased: Single;
begin
  Result := FTabFade.Eased;
end;

{ The header engine only needs the inherited controller wiring; a page-owning
  subclass overrides this to propagate the controller down to its child pages. }
procedure TTyCustomTabStrip.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
end;

{ Shared tab-header-band height: TabHeight logical px → device px at APPI.
  TabHeight = 0 means NO strip and must survive the scale: the old `if Result < 1 then 1`
  floor made "hidden" impossible — it turned 0 into a 1px band that still painted a 1px
  slice of every tab caption. A NON-zero TabHeight still floors at 1px, so a tiny-but-
  present strip cannot round away to nothing at a low DPI. }
function TTyCustomTabStrip.TabHPx(APPI: Integer): Integer;
var
  H: Integer;
begin
  H := GetTabHeight;
  if H <= 0 then Exit(0);
  Result := MulDiv(H, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyCustomTabStrip.TabCount: Integer;
begin
  Result := GetTabCount;
end;

function TTyCustomTabStrip.TabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < GetTabCount) then
    Result := GetTabCaption(AIndex)
  else
    Result := '';
end;

{ Measure the rendered caption width using a scratch TBitmap canvas so CJK and
  variable-width fonts are handled correctly (same pattern as TTyGroupBox). }
function TTyCustomTabStrip.TabCaptionWidth(const ACaption: string;
  const AStyle: TTyStyleSet; APPI: Integer): Integer;
var
  MeasBmp: TBitmap;
begin
  MeasBmp := TBitmap.Create;
  try
    MeasBmp.SetSize(1, 1);
    MeasBmp.Canvas.Font.Name := TyEffectiveFontName(AStyle.FontName);
    MeasBmp.Canvas.Font.Size := MulDiv(ResolveFontSize(AStyle), APPI, 96);
    Result := MeasBmp.Canvas.TextWidth(ACaption);
  finally
    MeasBmp.Free;
  end;
  if Result < 1 then Result := 1;
end;

procedure TTyCustomTabStrip.SetTabsClosable(AValue: Boolean);
begin
  if FTabsClosable = AValue then Exit;
  FTabsClosable := AValue;
  Invalidate;
end;

{ Single-pass cached layout. Builds FHeaderRects/FCloseRects for all tabs.
  Geometry: device px, (0,0)-local. Headers laid left-to-right;
  width = text width + 2×Scale(12), minimum Scale(48). When closable, a
  close-glyph slot is reserved on the right of each header. }
procedure TTyCustomTabStrip.RebuildLayout(APPI: Integer);
var
  TabH, Pad, MinW, CloseSize, Gap, CloseSlot, Margin: Integer;
  TabStyle: TTyStyleSet;
  I, X, TW, HW, Cy: Integer;
  VisibleWidth, AffordanceW, ArrowW, MaxScroll: Integer;
  dispCap: string;
  mpm: Integer;
begin
  SetLength(FHeaderRects, GetTabCount);
  SetLength(FCloseRects, GetTabCount);

  TabH      := TabHPx(APPI);
  Pad       := MulDiv(ActiveController.Metric('--tab-padding', TyTabPad), APPI, 96);
  MinW      := MulDiv(ActiveController.Metric('--tab-min-width', TyTabMinWidth), APPI, 96);
  CloseSize := MulDiv(ActiveController.Metric('--tab-close-size', TyTabCloseSize), APPI, 96);
  Gap       := MulDiv(ActiveController.Metric('--tab-gap', TyTabGap),  APPI, 96);
  Margin    := MulDiv(ActiveController.Metric('--tab-margin', TyTabMargin),  APPI, 96);
  CloseSlot := CloseSize + Gap;

  TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);

  X := 0;
  for I := 0 to GetTabCount - 1 do
  begin
    TyParseMnemonic(GetTabCaption(I), dispCap, mpm);
    TW := TabCaptionWidth(dispCap, TabStyle, APPI) + 2 * Pad;
    if GetTabClosableAt(I) then
    begin
      Inc(TW, CloseSlot);
      if TW < (MinW + CloseSlot) then TW := MinW + CloseSlot;
    end
    else
      if TW < MinW then TW := MinW;

    HW := TW;
    FHeaderRects[I] := Rect(X, 0, X + HW, TabH);

    if GetTabClosableAt(I) then
    begin
      Cy := (TabH - CloseSize) div 2;
      FCloseRects[I] := Rect(X + HW - Margin - CloseSize, Cy,
                             X + HW - Margin, Cy + CloseSize);
    end
    else
      FCloseRects[I] := Rect(0, 0, 0, 0);

    Inc(X, HW);
  end;

  { X is now the total (unshifted) header strip width. Decide whether the strip
    overflows the visible control width and, if so, reserve a left/right arrow
    affordance band (two Scale(16) arrows) at the far ends of the header band. }
  VisibleWidth := Width;
  AffordanceW  := MulDiv(ActiveController.Metric('--tab-arrow-band', TyTabArrowBand), APPI, 96) * 2;
  FShowScrollAffordance := X > VisibleWidth;
  if FShowScrollAffordance then
  begin
    ArrowW := MulDiv(ActiveController.Metric('--tab-arrow-band', TyTabArrowBand), APPI, 96);
    FArrowBandPx     := ArrowW;
    { The two arrows change ENDS when the strip reads right-to-left, and their names do not:
      FScrollLeftRect is the BACK arrow (a click on it decreases the scroll) and belongs at
      the reading START, which is the right edge here. Renaming the fields would be a
      breaking change for no behavioural gain, so the plan rules it out (§6.3.6) and the
      documentation carries the warning instead -- which is also why every test for this
      asserts the SCROLL DIRECTION a click produces and not the field name.

      Written as two explicit branches rather than a BidiFlipRect over the pair, because
      these two rects are the only geometry in the unit that is NOT in content space: they
      are already physical, so putting them through the content transform would mirror them
      twice. }
    if HeaderRightToLeft then
    begin
      FScrollLeftRect  := Rect(VisibleWidth - ArrowW, 0, VisibleWidth, TabH);
      FScrollRightRect := Rect(0, 0, ArrowW, TabH);
    end
    else
    begin
      FScrollLeftRect  := Rect(0, 0, ArrowW, TabH);
      FScrollRightRect := Rect(VisibleWidth - ArrowW, 0, VisibleWidth, TabH);
    end;
  end
  else
  begin
    FArrowBandPx     := 0;
    FScrollLeftRect  := Rect(0, 0, 0, 0);
    FScrollRightRect := Rect(0, 0, 0, 0);
    AffordanceW := 0; // no band reserved when content fits
  end;

  { Clamp the current scroll to the new maximum. Max scroll is the overshoot of
    the strip past the visible width minus the affordance band. }
  if FShowScrollAffordance then
    MaxScroll := X - (VisibleWidth - AffordanceW)
  else
    MaxScroll := 0;
  if MaxScroll < 0 then MaxScroll := 0;
  if FHeaderScroll > MaxScroll then FHeaderScroll := MaxScroll;
  if FHeaderScroll < 0 then FHeaderScroll := 0;
end;

function TTyCustomTabStrip.TyTabHeaderRect(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then
    Result := Rect(0, 0, 0, 0)
  else
    Result := FHeaderRects[AIndex];
end;

function TTyCustomTabStrip.TyTabCloseRect(AIndex: Integer): TRect;
begin
  if not FTabsClosable then
    Exit(Rect(0, 0, 0, 0));
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FCloseRects)) then
    Result := Rect(0, 0, 0, 0)
  else
    Result := FCloseRects[AIndex];
end;

{ Total unshifted width of the header strip = right edge of the last header
  (rebuilt at the control's current PPI). }
function TTyCustomTabStrip.TyHeaderStripWidth: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  if Length(FHeaderRects) = 0 then
    Result := 0
  else
    Result := FHeaderRects[High(FHeaderRects)].Right;
end;

{ Largest valid scroll: the overshoot of the strip past the visible width minus
  the reserved arrow band. 0 when the strip fits. Mirrors RebuildLayout's clamp. }
function TTyCustomTabStrip.TyMaxHeaderScroll: Integer;
var
  StripW, VisibleWidth, AffordanceW: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  if not FShowScrollAffordance then Exit(0);
  if Length(FHeaderRects) = 0 then
    StripW := 0
  else
    StripW := FHeaderRects[High(FHeaderRects)].Right;
  VisibleWidth := Width;
  AffordanceW  := MulDiv(ActiveController.Metric('--tab-arrow-band', TyTabArrowBand), Font.PixelsPerInch, 96) * 2;
  Result := StripW - (VisibleWidth - AffordanceW);
  if Result < 0 then Result := 0;
end;

function TTyCustomTabStrip.TyTabScrollLeftRect: TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  Result := FScrollLeftRect;
end;

function TTyCustomTabStrip.TyTabScrollRightRect: TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  Result := FScrollRightRect;
end;

{ Header rect as drawn: the cached content rect put through the one transform. }
function TTyCustomTabStrip.HeaderRectShifted(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then
    Exit(Rect(0, 0, 0, 0));
  Result := ToScreenRect(FHeaderRects[AIndex]);
end;

{ Content-space → screen TRANSLATION (the transform's first half; ToScreenRect adds the
  second). FArrowBandPx is one arrow's width when the overflow arrows show, 0 otherwise, so
  this is a plain scroll offset when the strip fits. Insetting by it keeps tab headers inside
  the band between the two arrows that the RenderTo clip reserves, so the first/last tab is
  never drawn under an arrow. Callers must have run RebuildLayout so FArrowBandPx and
  FHeaderScroll are current. }
function TTyCustomTabStrip.HeaderShiftPx: Integer;
begin
  // Reserve the subclass's leading inset (e.g. a ribbon File tab) plus the overflow
  // arrow band, minus the current scroll offset.
  Result := FArrowBandPx - FHeaderScroll + HeaderLeftInset;
end;

{ Shift, then -- when the strip reads right-to-left -- reflect about the control's width.

  A REFLECTION of the finished layout, not a reversed accumulation loop: a reflection of a
  gapless tiling is gapless by construction, so the mirrored strip cannot grow a 1px seam of
  page body between two headers, and every derived rect (the close slot, which lives INSIDE
  a header) lands in the right place without a second formula. LCL's BidiFlipRect
  (controls.pp:2966) is that five-line arithmetic, used here rather than rewritten so nobody
  has to check a `-1` twice.

  The reflection uses the control's own Width -- the same quantity RebuildLayout measures the
  overflow against and pins the arrow ends to -- so the band between the two arrows maps onto
  itself and the scroll arithmetic, which is all in content space, needs no mirror of its own. }
function TTyCustomTabStrip.ToScreenRect(const AContentRect: TRect): TRect;
begin
  Result := AContentRect;
  OffsetRect(Result, HeaderShiftPx, 0);
  if HeaderRightToLeft then
    Result := BidiFlipRect(Result, Rect(0, 0, Width, 0), True);
end;

{ The same reflection on a 1px-wide rect, which is what makes this the EXACT inverse of
  ToScreenRect rather than a hand-written `Width - 1 - X` that could drift from it by one
  pixel. `X in ToScreenRect(R)` and `ToReadingX(X) in shifted R` are then the same predicate
  for every integer X, which is the property TyDropIndexAt relies on to keep a single
  left-to-right comparison. }
function TTyCustomTabStrip.ToReadingX(AX: Integer): Integer;
begin
  Result := AX;
  if HeaderRightToLeft then
    Result := BidiFlipRect(Rect(AX, 0, AX + 1, 0), Rect(0, 0, Width, 0), True).Left;
end;

{ Clamp the requested scroll into [0, TyMaxHeaderScroll] and repaint. }
procedure TTyCustomTabStrip.SetHeaderScroll(AValue: Integer);
var
  MaxScroll: Integer;
begin
  MaxScroll := TyMaxHeaderScroll;
  if AValue < 0 then AValue := 0;
  if AValue > MaxScroll then AValue := MaxScroll;
  if AValue = FHeaderScroll then Exit;
  FHeaderScroll := AValue;
  Invalidate;
end;

{ Adjust FHeaderScroll (clamped) so the header at AIndex is fully inside the
  visible band. Pure integer math on the unshifted rect vs the visible band:
  the band is [VisLeft, VisRight], where the arrow affordance (when shown) eats
  ArrowW off each side. Scroll right just enough if the tab's right edge is past
  the band; scroll left just enough if its left edge is before the band. }
procedure TTyCustomTabStrip.ScrollTabIntoView(AIndex: Integer);
var
  ArrowW, VisLeft, VisRight, L, R, Want: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then Exit;

  if FShowScrollAffordance then
  begin
    ArrowW   := MulDiv(ActiveController.Metric('--tab-arrow-band', TyTabArrowBand), Font.PixelsPerInch, 96);
    { Tabs render inset by ArrowW (HeaderShiftPx), so content-x 0 maps to the band's
      left edge. Measure "into view" in content-minus-scroll space, where the visible
      band is [0, Width - 2*ArrowW] with BOTH arrow bands reserved. }
    VisLeft  := 0;
    VisRight := Width - 2 * ArrowW;
  end
  else
  begin
    VisLeft  := 0;
    VisRight := Width;
  end;

  Want := FHeaderScroll;
  L := FHeaderRects[AIndex].Left;
  R := FHeaderRects[AIndex].Right;

  { If the tab's right edge falls past the visible right, scroll so it aligns. }
  if (R - Want) > VisRight then
    Want := R - VisRight;
  { If the tab's left edge falls before the visible left, scroll so it aligns. }
  if (L - Want) < VisLeft then
    Want := L - VisLeft;

  SetHeaderScroll(Want);
end;

{ --- LCL-named geometry / hit-test / scroll. See the declarations. --------------- }

function TTyCustomTabStrip.TabRect(AIndex: Integer): TRect;
begin
  { HeaderRectShifted, not FHeaderRects[]: the SHIFTED rect is the one on screen, and on
    screen is what LCL's TabRect means. }
  Result := HeaderRectShifted(AIndex);
end;

function TTyCustomTabStrip.DisplayRect: TRect;
var
  TabH: Integer;
begin
  Result := Rect(0, 0, Width, Height);
  TabH := TabHPx(Font.PixelsPerInch);
  Inc(Result.Top, TabH);          // the same inset AdjustClientRect applies
  if Result.Top > Result.Bottom then Result.Top := Result.Bottom;
end;

function TTyCustomTabStrip.IndexOfTabAt(X, Y: Integer): Integer;
var
  PPI, TabH, I: Integer;
  HR: TRect;
begin
  Result := -1;
  PPI  := Font.PixelsPerInch;
  TabH := TabHPx(PPI);
  if TabH <= 0 then Exit;         // no band: nothing to hit
  if (Y < 0) or (Y >= TabH) then Exit;
  RebuildLayout(PPI);
  { The overflow arrows sit ON the band but are not tabs; a click there scrolls, so a
    hit-test that named a tab would put a context menu on a tab the user never aimed at. }
  if FShowScrollAffordance then
  begin
    if (X >= FScrollLeftRect.Left) and (X < FScrollLeftRect.Right) then Exit;
    if (X >= FScrollRightRect.Left) and (X < FScrollRightRect.Right) then Exit;
  end;
  for I := 0 to GetTabCount - 1 do
  begin
    HR := ToScreenRect(FHeaderRects[I]);
    if (X >= HR.Left) and (X < HR.Right) then Exit(I);
  end;
end;

function TTyCustomTabStrip.IndexOfTabAt(P: TPoint): Integer;
begin
  Result := IndexOfTabAt(P.x, P.y);
end;

procedure TTyCustomTabStrip.ScrollTabs(Delta: Integer);
var
  Target, Cnt: Integer;
begin
  Cnt := GetTabCount;
  if (Cnt = 0) or (Delta = 0) then Exit;
  RebuildLayout(Font.PixelsPerInch);
  { "By N tabs" is expressed as: find the tab whose left edge the band currently starts at,
    step N along the collection, and scroll to THAT tab's left edge. Doing it in tab space
    rather than by an averaged pixel width keeps the band aligned to a tab boundary even
    when the tabs have wildly different caption widths -- which they normally do. }
  Target := 0;
  while (Target < Cnt - 1) and (FHeaderRects[Target].Right <= FHeaderScroll) do
    Inc(Target);
  Inc(Target, Delta);
  if Target < 0 then Target := 0;
  if Target > Cnt - 1 then Target := Cnt - 1;
  SetHeaderScroll(FHeaderRects[Target].Left);
end;

{ Device-px drag threshold at APPI: 6 logical px scaled. At 96 PPI this is 6. }
function TTyCustomTabStrip.TyDragThresholdPx(APPI: Integer): Integer;
begin
  Result := MulDiv(6, APPI, 96);
  if Result < 1 then Result := 1;
end;

{ Resolve which collection index a drag at device-X should drop into, scanning
  the shifted header midpoints in READING order. Returns the first index whose
  shifted midpoint lies strictly past X; if X is past every midpoint it defaults
  to the last index. Result is clamped to [0, Count-1]. Pure: it rebuilds the
  (cached) layout for measurement but mutates no selection state.

  The pointer is reflected ONCE, at the door, and the scan below is then the plain
  left-to-right one. The alternative -- keeping X physical and writing a second,
  mirrored `X > Mid` branch beside the first -- puts the direction rule in two places one
  character apart, which is the shape §5 of the mirroring plan lists as the hardest kind
  of half-mirroring to spot. ToReadingX is exactly ToScreenRect run backwards, so the slot
  a drag drops into is by construction the slot the paint drew and the hit test names. }
function TTyCustomTabStrip.TyDropIndexAt(X, APPI: Integer): Integer;
var
  I, Mid, RX: Integer;
  HR: TRect;
begin
  if GetTabCount = 0 then Exit(0);
  RebuildLayout(APPI);
  RX := ToReadingX(X);
  Result := GetTabCount - 1; // default: past every midpoint -> last
  for I := 0 to GetTabCount - 1 do
  begin
    HR := FHeaderRects[I];
    OffsetRect(HR, HeaderShiftPx, 0); // shifted midpoint (incl. arrow-band inset)
    Mid := (HR.Left + HR.Right) div 2;
    if RX < Mid then
    begin
      Result := I;
      Break;
    end;
  end;
  if Result < 0 then Result := 0;
  if Result > GetTabCount - 1 then Result := GetTabCount - 1;
end;

procedure TTyCustomTabStrip.DoCloseClick(AIndex: Integer);
var
  AllowClose: Boolean;
begin
  if (AIndex < 0) or (AIndex >= GetTabCount) then Exit;
  AllowClose := True;
  if Assigned(FOnTabClose) then
    FOnTabClose(Self, AIndex, AllowClose);
  if AllowClose then
    RemoveTabData(AIndex);
end;

procedure TTyCustomTabStrip.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Top, TabHPx(Font.PixelsPerInch));
end;

procedure TTyCustomTabStrip.SetTabIndex(AValue: Integer);
var
  Clamped: Integer;
  Allow: Boolean;
begin
  { During csLoading the tab data may not exist yet, so clamping against an
    empty count would lose a streamed selection. Capture it and apply later.
    OnChanging is deliberately NOT consulted here: a streamed/loading selection
    is not a user/programmatic runtime switch and must not be vetoable (mirrors
    LCL, which does not fire OnChanging during loading). }
  if csLoading in ComponentState then
  begin
    FPendingTabIndex := AValue;
    Exit;
  end;
  if AValue < -1 then
    Clamped := -1
  else if AValue >= GetTabCount then
    Clamped := GetTabCount - 1
  else
    Clamped := AValue;
  if Clamped = FTabIndex then Exit;
  { Pre-switch veto: a handler may abort the switch by clearing AllowChange. When
    vetoed we keep the old index and commit nothing (no DoSelectTab, no fade, no
    OnChange). }
  Allow := True;
  if Assigned(FOnChanging) then
    FOnChanging(Self, Clamped, Allow);
  if not Allow then Exit;
  FTabIndex := Clamped;
  { Let the subclass react to the new selection (e.g. show its page). Only the
    header colour fades — any page switch is the subclass's instant concern. }
  DoSelectTab(FTabIndex);
  { Arm the active-tab header cross-fade when moving to a real tab. Animate when
    enabled and a window handle exists; otherwise snap so headless paint (every
    pixel test) shows the final active style immediately and existing tab tests
    stay green. The -1 (none) case skips: nothing to fade in. }
  if FTabIndex >= 0 then
  begin
    FTabFade.Progress := 0;
    FTabFade.Target := 1;
    if FAnimationsEnabled and HandleAllocated then
    begin
      EnsureTimer;
      FTimer.Enabled := True;
    end
    else
      FTabFade.SetTargetImmediate(1);
    ScrollTabIntoView(FTabIndex);
  end;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

{ Density-aware header height. Explicit host/.lfm value wins and is streamed; otherwise
  follow --control-height (TyDensityHeight: 28 classic byte-identical / 38 modern). }
function TTyCustomTabStrip.GetTabHeight: Integer;
begin
  if FTabHeightExplicit then
    Result := FTabHeight
  else
    Result := TyDensityHeight(ActiveController, 28);
end;

procedure TTyCustomTabStrip.SetTabHeight(AValue: Integer);
var
  OldEffective: Integer;
begin
  OldEffective := GetTabHeight;
  if AValue < 0 then
    // TyTabHeightAuto, and every other negative the way LCL reads them: UN-pin, so the
    // band goes back to following --control-height. It used to floor at 0 instead, which
    // silently turned "let the theme size it" into "remove the band" — the two furthest
    // apart outcomes the property has.
    FTabHeightExplicit := False
  else
  begin
    // 0 is legal and means NO header strip: the pages fill the whole control and the host
    // drives paging itself (a sider, a segmented control). It used to clamp to 1, which is
    // not "hidden" — a 1px strip still paints a 1px slice of every tab caption, which reads
    // as a smear of text above the content.
    FTabHeightExplicit := True;   { even if the value equals the fallback, the host meant to pin it }
    FTabHeight := AValue;
  end;
  { Compare the EFFECTIVE height, not the raw field. FTabHeight keeps the classic 28 as a
    fallback it is not using while unpinned, so on a modern-density theme (band = 38)
    `TabHeight := 28` hit the old `if FTabHeight = AValue then Exit` and returned before
    Realign: the getter reported the new 28, the band and the pages stayed at 38, and no
    repaint was ever asked for. Pinning a value must be judged by what it CHANGES, and
    what it changes is GetTabHeight. }
  if GetTabHeight = OldEffective then Exit;
  // The strip's height IS the client rect's top inset (see AdjustClientRect), so the pages
  // must be RE-ALIGNED, not merely repainted: Invalidate alone left every alClient page at
  // its old bounds, covering the new strip (set TabHeight := 30 and no tab was visible).
  Realign;
  Invalidate;
end;

procedure TTyCustomTabStrip.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, TabStyle, ArrowStyle, CloseS, InactiveS, ActiveS: TTyStyleSet;
  R: TRect;
  W, H, TabH, I, ContentTop: Integer;
  HdrRect, CloseRect, TextRect, BandRect, SavedClip: TRect;
  TabStates: TTyStateSet;
  CloseHi, BaseFill: TTyFill;
  BaseW: Integer;
  FadeEased: Single;
  disp: string;
  mp: Integer;
  Rtl: Boolean;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    W := R.Right;
    H := R.Bottom;
    Rtl := HeaderRightToLeft;
    { Armed because this control's GEOMETRY mirrors -- that is the rule BeginPaint's comment
      lays down for opting in. Every string this frame draws is taCenter, which
      BidiFlipAlignment leaves alone, so arming changes no pixel today; it is here so that a
      caption alignment which ever stops being centred cannot end up hugging the wrong side
      of a header that already moved. }
    P.BeginPaint(ACanvas, ARect, APPI, Rtl);

    BoxStyle := CurrentStyle;
    TabH := TabHPx(APPI);

    { The header strip is only painted where tab headers land; the empty area to the
      right of the last tab would otherwise be a stale gap. On an image theme fill
      the whole strip with the form's photo; off-image fill it with the OPAQUE
      resolved parent background (the tabs sit on the form backdrop) so the gap is
      not a transparent hole the Win10 DWM glass shows as the system color. }
    if not FillSharpBackdrop(P, Rect(0, 0, W, TabH)) then
      TyFillParentBg(Self, P, Rect(0, 0, W, TabH), BoxStyle);

    { Fill the content area with the form's photo (image theme) or the opaque parent bg
      (solid) FIRST, so a transparent content surface (e.g. green's ribbon body) shows the
      photo instead of a white hole; DrawFrame's own (possibly transparent) fill goes on top. }
    { The content frame overlaps the strip by 1px so the active tab merges into it — but with
      NO strip (TabHeight = 0) that would pull the frame's top border off the control. }
    ContentTop := TabH - MulDiv(1, APPI, 96);
    if ContentTop < 0 then ContentTop := 0;
    if not FillSharpBackdrop(P, Rect(0, ContentTop, W, H)) then
      TyFillParentBg(Self, P, Rect(0, ContentTop, W, H), BoxStyle);
    if HasPageBody then
      DrawFrame(P, Rect(0, ContentTop, W, H), BoxStyle)
    else
    begin
      { Caption-only strip: no page container, so no box. Keep just the frame's top
        border as a baseline the tabs sit on — same pixel row, same themed colour and
        width, so the rail stays and only the empty body goes. Laid down as a crisp
        fill rather than StrokeBorder's antialiased edge (a hairline rail reads
        sharper that way, and there is no rounded box left for it to follow). Drawn
        BEFORE the headers, as the frame was, so an active tab still merges into it. }
      if (TabH > 0) and TyBorderVisible(BoxStyle) then
      begin
        BaseW := MulDiv(BoxStyle.BorderWidth, APPI, 96);
        if BaseW < 1 then BaseW := 1;
        BaseFill := Default(TTyFill);
        BaseFill.Kind  := tfkSolid;
        BaseFill.Color := BoxStyle.BorderColor;
        P.FillBackground(Rect(0, ContentTop, W, ContentTop + BaseW), BaseFill, 0);
      end;
    end;

    { TabHeight = 0: no strip at all — skip every header. The pages already fill the control
      (AdjustClientRect adds nothing), so there is nothing to draw and nothing to clip. }
    if TabH <= 0 then
    begin
      P.EndPaint;
      Exit;
    end;

    { Draw each tab header }
    RebuildLayout(APPI);

    { When overflowing, clip the header strip to the band between the two arrow
      affordances so shifted headers do not paint over the arrows or past the
      control. When it fits, clip to the full header band (offset is 0 anyway). }
    SavedClip := P.Bitmap.ClipRect;
    if FShowScrollAffordance then
      { The band BETWEEN the arrows, whichever end each of them is on. The old expression
        named FScrollLeftRect.Right and FScrollRightRect.Left directly, which is the same
        band only while the back arrow is the left one -- mirrored, it names an INVERTED
        (empty) clip and every header disappears. Min/Max is the same two numbers in
        left-to-right, so this is byte-identical there. }
      BandRect := Rect(Min(FScrollLeftRect.Right, FScrollRightRect.Right), 0,
                       Max(FScrollLeftRect.Left,  FScrollRightRect.Left),  TabH)
    else
      BandRect := Rect(0, 0, W, TabH);
    P.Bitmap.ClipRect := BandRect;

    for I := 0 to GetTabCount - 1 do
    begin
      HdrRect   := HeaderRectShifted(I);
      CloseRect := FCloseRects[I];
      if GetTabClosableAt(I) then
        CloseRect := ToScreenRect(CloseRect);

      { Determine state }
      TabStates := [];
      if I = FTabIndex then
        Include(TabStates, tysActive)
      else if I = FHoverTab then
        Include(TabStates, tysHover)
      else
        Include(TabStates, tysNormal);

      TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', TabStates);

      { Active-tab header cross-fade. For the newly-active tab only, while the
        fade is mid-flight, blend the inactive TyTab background into the active
        TyTab:active background. Resolving both states explicitly keeps the maths
        independent of the live style and lets the eased animator drive the
        visible colour. At Eased=1 (settled / headless-snapped) it is exactly the
        active background, so existing tab pixel tests are unchanged. Only the
        background fill is touched — text/close glyph/geometry are unaffected. }
      if (I = FTabIndex) then
      begin
        FadeEased := FTabFade.Eased;
        if (FadeEased > 0) and (FadeEased < 1) and (TabStyle.Background.Kind = tfkSolid) then
        begin
          InactiveS := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);
          ActiveS   := ActiveController.Model.ResolveStyle('TyTab', '', [tysActive]);
          if (InactiveS.Background.Kind = tfkSolid) and (ActiveS.Background.Kind = tfkSolid) then
            TabStyle.Background.Color :=
              TyLerpColor(InactiveS.Background.Color, ActiveS.Background.Color, FadeEased);
        end;
      end;

      { Fill header background }
      if tpBackground in TabStyle.Present then
        P.FillBackground(HdrRect, TabStyle.Background, TyEffectiveCorners(TabStyle));

      { Draw caption centered in header, clipped off the close glyph. The close slot is at
        the header's TRAILING edge -- the right one normally, the left one when the strip
        reads right-to-left (the reflection put it there) -- so it is the opposite edge of
        the caption box that has to give way. }
      TextRect := HdrRect;
      if GetTabClosableAt(I) then
      begin
        if Rtl then
          TextRect.Left := CloseRect.Right
        else
          TextRect.Right := CloseRect.Left;
      end;
      TyParseMnemonic(GetTabCaption(I), disp, mp);
      P.DrawText(TextRect,
        disp,
        TabStyle.FontName, ResolveFontSize(TabStyle), TabStyle.FontWeight,
        TabStyle.TextColor,
        taCenter, tlCenter, True, TyAccelGatePos(mp));

      if GetTabClosableAt(I) then
      begin
        { Independent close (x) hover highlight: a token-driven chip behind the
          glyph (TyTabClose = var(--overlay-hover) fill + var(--radius)) plus the
          glyph at full opacity, so the x lights up on its own when the pointer
          is precisely over it. The glyph itself correctly stays TextColor (the
          tier-b "ink" of the convention). }
        if I = FHoverClose then
        begin
          CloseS := ActiveController.Model.ResolveStyle('TyTabClose', '', []);
          CloseHi := Default(TTyFill);
          CloseHi.Kind  := tfkSolid;
          CloseHi.Color := CloseS.Background.Color;
          P.FillBackground(CloseRect, CloseHi, CloseS.BorderRadius);
        end;
        P.DrawGlyph(CloseRect, tgClose, TabStyle.TextColor, 1);
      end;
    end;

    { Restore the clip and draw the prev/next arrow affordances on top so they
      are never overlapped by a shifted header. }
    P.Bitmap.ClipRect := SavedClip;
    if FShowScrollAffordance then
    begin
      ArrowStyle := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);
      if tpBackground in ArrowStyle.Present then
      begin
        P.FillBackground(FScrollLeftRect,  ArrowStyle.Background, 0);
        P.FillBackground(FScrollRightRect, ArrowStyle.Background, 0);
      end;
      { The chevrons point the way the strip MOVES, so they turn round with the ends: on a
        mirrored strip the back arrow is at the right and points right. Two arrows both
        pointing the old way over swapped rects would be the "size grip drawn on one side,
        grabbed on the other" defect (§5.5) in miniature. }
      if Rtl then
      begin
        P.DrawGlyph(FScrollLeftRect,  tgArrowRight, ArrowStyle.TextColor, 2);
        P.DrawGlyph(FScrollRightRect, tgArrowLeft,  ArrowStyle.TextColor, 2);
      end
      else
      begin
        P.DrawGlyph(FScrollLeftRect,  tgArrowLeft,  ArrowStyle.TextColor, 2);
        P.DrawGlyph(FScrollRightRect, tgArrowRight, ArrowStyle.TextColor, 2);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomTabStrip.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ Mouse: hit-test headers on left-click }
procedure TTyCustomTabStrip.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  PPI, TabH, Step, I: Integer;
  HdrRect, CloseRect: TRect;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    PPI  := Font.PixelsPerInch;
    TabH := TabHPx(PPI);
    if Y < TabH then
    begin
      RebuildLayout(PPI);

      { Affordance arrows take priority over the header scan. Each click nudges
        the scroll by ~40 logical px (clamped inside SetHeaderScroll). }
      if FShowScrollAffordance then
      begin
        Step := MulDiv(40, PPI, 96);
        if (X >= FScrollLeftRect.Left) and (X < FScrollLeftRect.Right) and
           (Y >= FScrollLeftRect.Top) and (Y < FScrollLeftRect.Bottom) then
        begin
          SetHeaderScroll(FHeaderScroll - Step);
          Exit;
        end;
        if (X >= FScrollRightRect.Left) and (X < FScrollRightRect.Right) and
           (Y >= FScrollRightRect.Top) and (Y < FScrollRightRect.Bottom) then
        begin
          SetHeaderScroll(FHeaderScroll + Step);
          Exit;
        end;
      end;

      for I := 0 to GetTabCount - 1 do
      begin
        HdrRect := HeaderRectShifted(I);
        if (X >= HdrRect.Left) and (X < HdrRect.Right) then
        begin
          CloseRect := ToScreenRect(FCloseRects[I]);
          if GetTabClosableAt(I) and
             (X >= CloseRect.Left) and (X < CloseRect.Right) and
             (Y >= CloseRect.Top) and (Y < CloseRect.Bottom) then
            DoCloseClick(I)
          else
          begin
            TabIndex := I;
            { Arm a drag-reorder candidate. A plain press+release stays a click
              (FDragging never flips); only a move past the threshold reorders.
              FDragOrigin pins the start index so MouseUp can report the net move. }
            FDragTab    := I;
            FDragOrigin := I;
            FDragStartX := X;
            FDragging   := False;
          end;
          Break;
        end;
      end;
    end;
    try
      if CanFocus then SetFocus;
    except
      { Ignore focus errors in headless/test environments }
    end;
  end;
end;

procedure TTyCustomTabStrip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  PPI, TabH, NewHover, NewHoverClose, I, Target: Integer;
  HdrRect, CloseRect: TRect;
  OverArrow: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  PPI  := Font.PixelsPerInch;
  TabH := TabHPx(PPI);

  { Drag-reorder gesture. While a candidate is armed and the left button is held,
    a move past the threshold flips into live reorder mode. Each subsequent move
    drops the dragged tab at the index its current X resolves to (shifted-midpoint
    rule). The subclass owns the tab data, so the live move is delegated via
    DoReorderTabs(from, to); FDragTab tracks the dragged tab's new live index.
    Skip the hover scan while dragging. }
  if (FDragTab >= 0) and (ssLeft in Shift) then
  begin
    if (not FDragging) and (Abs(X - FDragStartX) >= TyDragThresholdPx(PPI)) then
      FDragging := True;
    if FDragging then
    begin
      Target := TyDropIndexAt(X, PPI);
      if (Target >= 0) and (Target <> FDragTab) then
      begin
        DoReorderTabs(FDragTab, Target); // subclass reseats its own tab data
        FDragTab := Target;
      end;
      { A live reorder drag is not a close-button hover; drop any stale highlight. }
      if FHoverClose <> -1 then
      begin
        FHoverClose := -1;
        Invalidate;
      end;
      Exit; // skip hover scan while a drag is in progress
    end;
  end;

  NewHover := -1;
  NewHoverClose := -1;
  if Y < TabH then
  begin
    RebuildLayout(PPI);
    { Over an affordance arrow counts as no tab hover. }
    OverArrow := FShowScrollAffordance and
      (((X >= FScrollLeftRect.Left)  and (X < FScrollLeftRect.Right)) or
       ((X >= FScrollRightRect.Left) and (X < FScrollRightRect.Right)));
    if not OverArrow then
      for I := 0 to GetTabCount - 1 do
      begin
        HdrRect := HeaderRectShifted(I);
        if (X >= HdrRect.Left) and (X < HdrRect.Right) then
        begin
          NewHover := I;
          { Independent close (x) hover: only when closable and the pointer is
            inside this tab's shifted close rect. Mirrors the MouseDown hit-test
            so the highlight and the actual close target stay in lockstep. }
          if GetTabClosableAt(I) then
          begin
            CloseRect := ToScreenRect(FCloseRects[I]);
            if (X >= CloseRect.Left) and (X < CloseRect.Right) and
               (Y >= CloseRect.Top)  and (Y < CloseRect.Bottom) then
              NewHoverClose := I;
          end;
          Break;
        end;
      end;
  end;
  if NewHoverClose <> FHoverClose then
  begin
    FHoverClose := NewHoverClose;
    Invalidate;
  end;
  if NewHover <> FHoverTab then
  begin
    FHoverTab := NewHover;
    Invalidate;
  end;
end;

{ End any drag-reorder gesture. The reorder itself already happened live during
  MouseMove (each crossed midpoint reseated the item), so MouseUp only disarms
  the candidate so a later move without a fresh press cannot reorder. }
procedure TTyCustomTabStrip.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  FromIdx, ToIdx: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  { A committed reorder fires OnReorder exactly once for the whole gesture, with
    the net from (press) -> to (final) move. FDragging only flips True once the
    pointer crossed the threshold and reseated the tab, so a plain click never
    fires it; the move is real only when the final index differs from the start. }
  if FDragging and (FDragOrigin >= 0) and (FDragTab >= 0) and
     (FDragTab <> FDragOrigin) and Assigned(FOnReorder) then
  begin
    FromIdx := FDragOrigin;
    ToIdx   := FDragTab;
    FOnReorder(Self, FromIdx, ToIdx);
  end;
  FDragTab    := -1;
  FDragOrigin := -1;
  FDragging   := False;
end;

procedure TTyCustomTabStrip.MouseLeave;
begin
  inherited MouseLeave;
  { Disarm any in-flight drag so a re-entry move without a fresh press is inert.
    No OnReorder here: a reorder is only committed/announced on a clean MouseUp. }
  FDragTab    := -1;
  FDragOrigin := -1;
  FDragging   := False;
  if (FHoverTab <> -1) or (FHoverClose <> -1) then
  begin
    FHoverTab   := -1;
    FHoverClose := -1;
    Invalidate;
  end;
end;

{ Mouse wheel over the header band scrolls the overflowing strip. Mirrors
  ListBox.DoMouseWheel: bail when disabled, let a user handler consume first,
  then act only when the pointer is in the header band and the strip overflows.
  WheelDelta>0 (scroll up/back) decreases the offset; WheelDelta<0 increases it.
  SetHeaderScroll clamps to [0, TyMaxHeaderScroll]. }
function TTyCustomTabStrip.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  PPI, TabH, Step: Integer;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then
    Exit(True);

  PPI  := Font.PixelsPerInch;
  TabH := TabHPx(PPI);
  RebuildLayout(PPI);

  Result := False;
  if (MousePos.Y < TabH) and FShowScrollAffordance then
  begin
    Step := MulDiv(40, PPI, 96);
    if WheelDelta > 0 then
      SetHeaderScroll(FHeaderScroll - Step)
    else
      SetHeaderScroll(FHeaderScroll + Step);
    Result := True;
  end;
end;

{ Keyboard: standard tab navigation.
  Ctrl+Tab / Ctrl+Shift+Tab cycle the selection WITH wrap; Ctrl+PageDown /
  Ctrl+PageUp step next/prev clamped at the ends; Home/End jump to first/last;
  the arrow key pointing at the next tab steps next, the other steps prev, both
  clamped (which arrow is which follows HeaderRightToLeft). Every handled key is
  consumed (Key := 0). TabIndex := routes through SetTabIndex, which clamps,
  shows the page, scrolls it into view, and fires OnChange. }
procedure TTyCustomTabStrip.KeyDown(var Key: Word; Shift: TShiftState);
var NewIndex, Cnt, Step: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  Cnt := GetTabCount;
  if Cnt = 0 then Exit;
  // Ctrl+Tab / Ctrl+Shift+Tab: cycle with wrap.
  if (Key = VK_TAB) and (ssCtrl in Shift) then
  begin
    if ssShift in Shift then NewIndex := FTabIndex - 1 else NewIndex := FTabIndex + 1;
    if NewIndex < 0 then NewIndex := Cnt - 1;
    if NewIndex > Cnt - 1 then NewIndex := 0;
    TabIndex := NewIndex; Key := 0; Exit;
  end;
  // Ctrl+PageDown / Ctrl+PageUp: next/prev, clamp.
  if (Key = VK_NEXT) and (ssCtrl in Shift) then
  begin
    if FTabIndex < Cnt - 1 then TabIndex := FTabIndex + 1; Key := 0; Exit;
  end;
  if (Key = VK_PRIOR) and (ssCtrl in Shift) then
  begin
    if FTabIndex > 0 then TabIndex := FTabIndex - 1; Key := 0; Exit;
  end;
  { Step := +1 for the key that points at the NEXT tab. On a mirrored strip the next tab is
    the one to the LEFT, so the two arrows trade jobs -- this is LAYOUT direction, which the
    plan separates from text direction precisely here (§6.3.4): a text caret's Left/Right
    belong to the bidi layer and must not be flipped, a tab strip's follow the eye. Home/End
    are logical ends and Ctrl+Tab a logical cycle, so neither turns (§6.3.3); they are handled
    above and below this and deliberately not touched.

    One `Step` rather than two mirrored branches: the branches differ only by a sign, which
    §5.3 lists as the flip reviewers cannot see. }
  if HeaderRightToLeft then Step := -1 else Step := 1;
  case Key of
    VK_HOME:  begin TabIndex := 0; Key := 0; end;
    VK_END:   begin TabIndex := Cnt - 1; Key := 0; end;
    VK_RIGHT:
      begin
        NewIndex := FTabIndex + Step;
        if NewIndex > Cnt - 1 then NewIndex := Cnt - 1;
        if NewIndex < 0 then NewIndex := 0;
        TabIndex := NewIndex; Key := 0;
      end;
    VK_LEFT:
      begin
        NewIndex := FTabIndex - Step;
        if NewIndex > Cnt - 1 then NewIndex := Cnt - 1;
        if NewIndex < 0 then NewIndex := 0;
        TabIndex := NewIndex; Key := 0;
      end;
  end;
end;

end.
