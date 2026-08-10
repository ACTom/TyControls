unit tyControls.TabStrip;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, ImgList, Types, Math, Controls, Graphics, LCLType, LMessages, ExtCtrls,
  ComCtrls,                          // TTabPosition -- LCL's type, so a port streams
  BGRABitmap, BGRABitmapTypes,       // the borrowed bitmap CachedIndex hands back
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.Animation, tyControls.Accel, tyControls.ImageCollection, tyControls.ImageDraw;

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

  { Fallbacks for the two icon metrics, in logical px. They are Metric() DEFAULTS, not
    hard-coded values: a skin that defines --tab-icon-size / --tab-icon-gap overrides both,
    exactly as --tab-padding and --tab-gap already work. They live here rather than in
    tyControls.Types because they are this unit's own tokens and nothing else reads them. }
  TyTabIconSize = 16;
  TyTabIconGap  = 6;

type
  TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer;
    var AllowClose: Boolean) of object;

  { Last-word override of a tab's icon. Fired AFTER the per-tab ImageIndex has been read,
    with AImageIndex seeded from it, so a handler sees what it is replacing and a control
    with no handler keeps the per-tab value. Same shape and same precedence rule as
    TTyTreeView.OnGetImageIndex; -1 means "no icon". }
  TTyTabGetImageIndexEvent = procedure(Sender: TObject; AIndex: Integer;
    var AImageIndex: Integer) of object;

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
    FIconRects:   array of TRect;

    { Which edge the band sits on. The layout is built in the SAME content space for all
      four (see ToScreenRect); this only chooses how that 1-D run is embedded in the
      control's box. }
    FTabPosition: TTabPosition;
    { Device-px thickness of the band across its minor axis, recomputed by RebuildLayout.
      ONE ROW is TabHPx on a horizontal band and the widest caption box on a vertical one
      (the captions are NOT rotated -- see RebuildLayout); the band is FRowCount of those. }
    FBandThickness: Integer;

    { Wrapping. FMultiLine lets the run FOLD instead of overflowing: it fills the band's main
      extent, then starts another row. FRaggedRight = False (LCL's default, and LCL's polarity
      -- the STYLE bit is set when the property is True) stretches each row's tabs to fill it.
      FRowCount is the RESULT of that fold and is therefore read-only, exactly as LCL has it:
      a setter would create "I asked for 3 rows and only 2 fit", a state with no answer. }
    FMultiLine: Boolean;
    FRaggedRight: Boolean;
    FRowCount: Integer;

    { Tab icons: one list on the control, an index per tab, an event with the last word. }
    FImages: TCustomImageList;
    FImagesWidth: Integer;
    FOnGetImageIndex: TTyTabGetImageIndexEvent;

    { Drag-reorder gesture state. FDragTab is the collection index of the tab a
      press armed as a drag candidate (-1 = none). FDragStartMain is the device-px
      MAIN-AXIS coordinate of that press (x on a top/bottom band, y on a left/right
      one); FDragging flips True once the pointer travels past the drag threshold,
      switching the gesture from a click into a live reorder. }
    FDragTab:    Integer;
    FDragStartMain: Integer;
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
    procedure SetTabPosition(AValue: TTabPosition);
    procedure SetMultiLine(AValue: Boolean);
    procedure SetRaggedRight(AValue: Boolean);
    function  GetRowCount: Integer;
    procedure SetImages(AValue: TCustomImageList);
    procedure SetImagesWidth(AValue: Integer);
    procedure RebuildLayout(APPI: Integer);
    procedure DoCloseClick(AIndex: Integer);
    function  TabHPx(APPI: Integer): Integer;
    function  IconPx(APPI: Integer): Integer;
    function  TabCaptionWidth(const ACaption: string;
                              const AStyle: TTyStyleSet; APPI: Integer): Integer;
    { Half-open point-in-rect, spelled out rather than borrowed from Types.PtInRect so the
      [Left,Right) x [Top,Bottom) convention every hit test in this unit already uses is
      visible at the one place it is now shared from. }
    function  HitRect(const R: TRect; AX, AY: Integer): Boolean;
    { The screen coordinate along the band's MAIN axis. Every scan in this unit used to
      hard-code X for it; a left/right band turns the main axis vertical and this is the
      only place that has to know. }
    function  MainOf(AX, AY: Integer): Integer;
    function  HitBandMinor(AX, AY: Integer): Boolean;
    { The band's physical rect BEFORE the mirror, and the control's extent along the
      band's main axis. See the implementations. }
    function  BandBoxPx(AW, AH, AThickness: Integer): TRect;
    function  MainVisiblePx: Integer;
    { Which edge the band is DRAWN on, mirror applied, and the three edge-picking rules
      that take that one answer. See the implementations. }
    function  EffectiveBandSide: TTabPosition;
    procedure InsetForBand(var ARect: TRect);
    procedure GrowTowardBand(var ARect: TRect; AAmount: Integer);
    function  BandEdgeOf(const ARect: TRect; AThick: Integer): TRect;
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
    { The per-tab half of the icon rule: the index into Images this tab carries, or -1.
      The base has no tab data, so it has no index either; TTyPageControl overrides it to
      return the page's ImageIndex. This is the value TabImageIndex seeds OnGetImageIndex
      with -- the event is the override, this is what it overrides. }
    function GetTabImageIndex(AIndex: Integer): Integer; virtual;
    { Fired after the Images list is (re)assigned, before the relayout. The base does nothing;
      TTyPageControl overrides it to re-resolve every page's pending ImageIndex against the new
      list, so a name-keyed page icon survives a list that arrives after the pages. }
    procedure DoImagesChanged; virtual;
    { Which edge the band sits on, as the LAYOUT sees it -- the ONE answer the band box,
      AdjustClientRect, DisplayRect and the arrow ends all take, exactly as
      HeaderRightToLeft is the one answer for direction. A subclass whose own chrome is
      pinned to the top (TTyRibbon: a File tab, a collapse chevron and KeyTip chips, all
      of which assume a top band) declines here in one place instead of shipping a strip
      whose band moved and whose chrome did not. }
    function HeaderTabPosition: TTabPosition; virtual;
    { Does the run FOLD, as the LAYOUT sees it -- the same shape as HeaderTabPosition and for
      the same reason. A subclass whose own chrome is sized to ONE row declines here, in one
      place, instead of growing a band its chrome does not follow. TTyRibbon is that subclass:
      its File tab, its collapse chevron, its KeyTip chips and two of its MouseDown gates are
      all computed as `MulDiv(TabHeight, PPI, 96)` -- one row -- so a two-row ribbon band would
      be drawn two rows tall and answer clicks over one. It needs
        function TTyRibbon.HeaderMultiLine: Boolean; begin Result := False; end;
      which is outside this change's edit scope and is reported rather than made. }
    function HeaderMultiLine: Boolean; virtual;
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
    { Drops the Images reference when the list is freed. The setter also registers a
      FreeNotification, because opRemove only reaches us for a component we asked about:
      a list owned by another form (or created with Owner = nil) would be freed without a
      word and leave FImages dangling. }
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
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

      A tab strip has FOUR consumers of the same axis -- the paint, the click hit test,
      the drag-reorder midpoint rule and the overflow scroll offset -- and every one of them
      used to apply `OffsetRect(R, HeaderShiftPx, 0)` for itself, six copies of the same
      line. That was survivable while the transform was a translation, because a translation
      written six times is still the same translation. It stops being survivable the moment
      the transform acquires a direction: a drag whose midpoint rule did not follow the paint
      drops tabs on the wrong side of their neighbour, and no static render test can see it.

      So both directions are named here and nothing in this unit converts by hand.

      CONTENT SPACE is what RebuildLayout builds and is the SAME for all four TabPositions:
      a 1-D run of tabs along a MAIN axis (reading order, tab 0 first, origin 0), each tab
      spanning the band's thickness on the CROSS axis. x carries main, y carries cross. The
      layout problem genuinely is 1-D -- tabs of varying length, one uniform thickness -- so
      the four positions differ ONLY in how that run is embedded in the control's box, which
      is what a transform is for and not what a second builder would be for.

      ToScreenRect runs three steps, in this order:
        1. slide along MAIN by HeaderShiftPx (scroll offset + arrow band + subclass inset);
        2. embed: (main, cross) -> (x, y) at the band box for the current TabPosition. At
           tpTop the band box starts at (0,0) and the map is the identity, so every step is
           a no-op and the result is byte-identical to what this did before TabPosition
           existed;
        3. reflect the SCREEN x about the control's Width when the strip reads
           right-to-left. Reflecting last rather than first is what makes one line cover
           two different meanings of "mirrored": on a top/bottom band the reflected axis IS
           the main one (tab order reverses, as it always did), and on a left/right band it
           is the CROSS one, so the band moves to the opposite edge and the close slot moves
           to the other end of its row -- with no second branch anywhere.

      ToReadingMain: a screen POINT -> the main-axis coordinate in SHIFTED content space,
        i.e. steps 3 and 2 run backwards. `MainOf(pt) in ToScreenRect(R)` and
        `ToReadingMain(pt) in shifted R` are then the same predicate for every point, which
        is the property TyDropIndexAt relies on to keep a single forward comparison instead
        of growing a mirrored copy of it one character away from the original. }
    function ToScreenRect(const AContentRect: TRect): TRect;
    function ToReadingMain(const APt: TPoint): Integer;
    { The CROSS-axis half of the same inverse, and written here rather than anywhere else so
      the two cannot drift: they undo the same two steps of ToScreenRect in the same order,
      and each reads off the axis the other does not.

      They differ in exactly one argument, and it is load-bearing. ToReadingMain may pass a
      thickness of 0 to BandBoxPx because it reads the MAJOR axis, which the thickness does
      not place. This reads the MINOR axis, which is the only thing the thickness DOES place
      (`tpBottom` puts the band at `AH - AThickness`, `tpRight` at `AW - AThickness`), so it
      has to pay for the real one. Passing 0 here would answer as if every band were at the
      top-left, which is right at tpTop and off by the control's whole extent elsewhere. }
    function ToReadingCross(const APt: TPoint): Integer;
    { The horizontal-band form of ToReadingMain, kept because it is public API and because
      a top/bottom band is the only shape whose main axis is x. On a LEFT/RIGHT band the
      main axis is y and an x alone cannot answer: ask ToReadingMain. }
    function ToReadingX(AX: Integer): Integer;

    { --- Where the band is ------------------------------------------------------------

      BandIsVertical:  does the tab run go down the side rather than across the top?
      BandThicknessPx: the band's device-px extent across its MINOR axis -- TabHPx on a
        top/bottom band; on a left/right band the widest caption box, because captions are
        never rotated (see RebuildLayout) and a 28px-wide rail could not hold one.
      BandRect:        the band's physical rect in the control, mirror applied. The arrow
        ends, the paint's backdrop fill and the clip all come off this one rect. }
    function BandIsVertical: Boolean;
    function BandThicknessPx: Integer;
    function BandRect: TRect;

    { The icon a tab draws, or -1 for none: the per-tab index (GetTabImageIndex) with
      OnGetImageIndex given the last word over it. }
    function TabImageIndex(AIndex: Integer): Integer;
    { The icon's slot inside the tab, as drawn (device px, mirror applied), or an empty
      rect when this tab draws no icon. }
    function TabImageRect(AIndex: Integer): TRect;

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
      TyDropIndexAtPoint: the collection index a drag at a device-px POINT should drop
        into, using shifted header midpoints along the band's main axis. Returns the first
        index i whose shifted midpoint lies past the pointer; clamped to [0, Count-1]
        (default the last index when the pointer is past every midpoint).
      TyDropIndexAt: the same for a top/bottom band, where the main axis is x. Kept
        because it is public API; on a left/right band ask TyDropIndexAtPoint. }
    function TyDragThresholdPx(APPI: Integer): Integer;
    function TyDropIndexAt(X, APPI: Integer): Integer;
    function TyDropIndexAtPoint(const APt: TPoint; APPI: Integer): Integer;

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

    { Which edge the tab band sits on. LCL's type and LCL's four values, so a ported
      `TabPosition := tpBottom` compiles and a ported .lfm streams.

      PUBLIC here and PUBLISHED on the concrete subclasses (TTyPageControl, TTyTabSet)
      rather than published here, because TTyRibbon is the third subclass of this engine
      and its own chrome -- the File tab, the collapse chevron, the KeyTip chips -- is
      pinned to a top band. Publishing on the base would have put a property in the
      ribbon's Object Inspector that moves the tabs and leaves that chrome behind.
      A subclass that wants to refuse outright overrides HeaderTabPosition.

      One respect in which this is NOT LCL's tpLeft/tpRight, deliberately: LCL delegates to
      comctl32's TCS_VERTICAL, which ROTATES the caption 90 degrees. We do not rotate --
      the band becomes a stack of full-width rows with upright captions, sized to the widest
      one, which is what every modern themed tab rail does and what this painter can draw
      crisply at any DPI. docs/controls/pagecontrol.md records the divergence. }
    property TabPosition: TTabPosition read FTabPosition write SetTabPosition default tpTop;

    { Let the run FOLD rather than overflow. LCL's name, LCL's default, and LCL's mutual
      exclusion with the scroll affordance: with MultiLine on there is nothing off-screen to
      scroll to, so the two arrow bands are dropped and the offset is pinned at 0. Half of
      this feature would be worse than none -- a strip that both wrapped AND kept the arrows
      would eat 16px at each end of every row to reach content that is already visible.

      It generalises to the side bands with no code of its own, because the layout is 1-D:
      a tpLeft band that folds grows a second COLUMN, which is the same statement about the
      cross axis that a second row is on a top band. comctl32's TCS_MULTILINE + TCS_VERTICAL
      does the same, so this is one of the places we and LCL agree.

      What it does NOT do, deliberately, is move the rows about when the selection changes.
      Delphi/comctl32 re-seat the selected row next to the page body (and TCS_SCROLLOPPOSITE
      picks which way the others go). We do not, and therefore do not offer ScrollOpposite
      either: that rearrangement is what turns selection from a RENDER state into a LAYOUT
      input, and this control has a drag-reorder gesture comctl32 has never had -- during a
      drag the selection is pinned to the POSITION, so a reorder across a row boundary would
      re-fold the band underneath the pointer mid-gesture. docs/controls/pagecontrol.md
      records the divergence.

      PUBLIC here and PUBLISHED on TTyPageControl / TTyTabSet, for the reason TabPosition is:
      TTyRibbon's chrome is one row tall. See HeaderMultiLine. }
    property MultiLine: Boolean read FMultiLine write SetMultiLine default False;
    { With MultiLine on, should a row keep its tabs' natural extents and leave the tail of the
      row empty? LCL's polarity, which reads backwards until you look at the style bit:
      TCS_RAGGEDRIGHT is set when the property is TRUE, and WITHOUT it comctl32 stretches each
      row to fill the band. So False -- the default -- is the JUSTIFIED one. Inert while
      MultiLine is off, where there is only ever one row and nothing to justify against. }
    property RaggedRight: Boolean read FRaggedRight write SetRaggedRight default False;
    { How many rows the run folded into: 0 with no tabs, 1 whenever MultiLine is off.

      READ-ONLY, as LCL has it, and public rather than published for the same reason it is
      read-only: it is the RESULT of the fold, so it has no setter, and a published property
      without a setter is one TWriter.WriteProperty skips and the Object Inspector reports as
      unreadable. }
    property RowCount: Integer read GetRowCount;
  published
    { The icon source for the tab headers, indexed by the per-tab image index.

      Typed TTyVirtualImageList, not LCL's TCustomImageList, and that is not a preference:
      TTyVirtualImageList renders on demand rather than holding a fixed-resolution set, so
      it is not a TCustomImageList descendant -- which means a TCustomImageList-typed
      property would accept only the lists no TTyPainter can draw. TTyHeader.Images was
      retyped for exactly this reason (Columns.pas), and this follows it rather than
      inventing a third rule. }
    property Images: TCustomImageList read FImages write SetImages;
    { Logical-px edge to render tab icons at. 0 (the default) follows the --tab-icon-size
      theme token, which is what keeps icons in step with a density change; a non-zero
      value pins them. LCL's ImagesWidth picks a RESOLUTION out of a multi-resolution list;
      ours is a size request, because a virtual list renders at whatever size it is asked. }
    property ImagesWidth: Integer read FImagesWidth write SetImagesWidth default 0;
    { Last word on a tab's icon -- fired after the per-tab index has been read, with
      AImageIndex seeded from it. -1 draws no icon. }
    property OnGetImageIndex: TTyTabGetImageIndexEvent read FOnGetImageIndex write FOnGetImageIndex;
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
  FTabPosition := tpTop;
  FBandThickness := 0;
  FMultiLine := False;
  FRaggedRight := False;
  FRowCount := 0;
  FImagesWidth := 0;
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

function TTyCustomTabStrip.HeaderTabPosition: TTabPosition;
begin
  Result := FTabPosition;
end;

function TTyCustomTabStrip.HeaderMultiLine: Boolean;
begin
  Result := FMultiLine;
end;

function TTyCustomTabStrip.GetTabImageIndex(AIndex: Integer): Integer;
begin
  { The base owns no tab data, so it owns no per-tab index either. }
  Result := -1;
end;

procedure TTyCustomTabStrip.DoImagesChanged;
begin
  { The base owns no tabs, so there is nothing to re-resolve. TTyPageControl overrides this. }
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

{ Moving the band moves the client rect's inset from one edge to another, so the pages
  must be RE-ALIGNED and not merely repainted -- the same reason SetTabHeight calls
  Realign. Invalidate alone would leave every alClient page covering the new band. }
procedure TTyCustomTabStrip.SetTabPosition(AValue: TTabPosition);
begin
  if FTabPosition = AValue then Exit;
  FTabPosition := AValue;
  { The scroll offset is measured along the main axis, and the main axis just changed
    length (Width <-> Height): an offset valid for the old axis is meaningless on the new
    one. Reset rather than clamp -- clamping would silently keep a fraction of it. }
  FHeaderScroll := 0;
  Realign;
  Invalidate;
end;

{ Folding changes the band's THICKNESS (one row becomes RowCount rows), which is the client
  rect's inset -- so this is the same Realign-not-just-Invalidate rule SetTabHeight and
  SetTabPosition already carry, and for the same reason: Invalidate alone would leave every
  alClient page at its old bounds, covering the rows that just appeared.

  The scroll offset is dropped rather than clamped. Turning MultiLine ON removes overflow
  entirely, so any surviving offset would be a shift with nothing left to shift towards;
  turning it OFF re-measures the run from scratch and RebuildLayout re-clamps anyway. }
procedure TTyCustomTabStrip.SetMultiLine(AValue: Boolean);
begin
  if FMultiLine = AValue then Exit;
  FMultiLine := AValue;
  FHeaderScroll := 0;
  Realign;
  Invalidate;
end;

{ Justification only moves tabs ALONG their row, so unlike MultiLine this cannot change the
  band's thickness and an Invalidate would do. Realign anyway: it is one layout pass, and the
  alternative is a pair of near-identical setters where one re-lays and the other does not,
  which is the kind of difference that survives a review and then has to be found. }
procedure TTyCustomTabStrip.SetRaggedRight(AValue: Boolean);
begin
  if FRaggedRight = AValue then Exit;
  FRaggedRight := AValue;
  Realign;
  Invalidate;
end;

function TTyCustomTabStrip.GetRowCount: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  Result := FRowCount;
end;

procedure TTyCustomTabStrip.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  { A list arriving is when each page's streamed-but-pending ImageIndex can finally become a name
    (TTyPageControl overrides this; the base does nothing). }
  DoImagesChanged;
  { Icons take room inside every header, so this is a LAYOUT change, not a repaint:
    gaining or losing the list re-measures each tab. Realign because the band's thickness
    on a left/right band is the widest caption box and the icon slot is inside it. }
  Realign;
  Invalidate;
end;

procedure TTyCustomTabStrip.SetImagesWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;   // 0 = follow the theme token; negative is not a size
  if FImagesWidth = AValue then Exit;
  FImagesWidth := AValue;
  Realign;
  Invalidate;
end;

procedure TTyCustomTabStrip.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then FImages := nil;
end;

{ Device-px edge of a tab icon at APPI. 0 -- meaning "no icon slot at all", which is what
  the layout keys on -- when there is no list to draw from, so a strip without Images
  measures and paints exactly as it did before icons existed. }
function TTyCustomTabStrip.IconPx(APPI: Integer): Integer;
var
  Logical: Integer;
begin
  if FImages = nil then Exit(0);
  if FImagesWidth > 0 then
    Logical := FImagesWidth
  else
    Logical := ActiveController.Metric('--tab-icon-size', TyTabIconSize);
  if Logical <= 0 then Exit(0);
  Result := MulDiv(Logical, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyCustomTabStrip.HitRect(const R: TRect; AX, AY: Integer): Boolean;
begin
  Result := (AX >= R.Left) and (AX < R.Right) and (AY >= R.Top) and (AY < R.Bottom);
end;

function TTyCustomTabStrip.MainOf(AX, AY: Integer): Integer;
begin
  if BandIsVertical then Result := AY else Result := AX;
end;

{ Is the point on the band, measured across the band's MINOR axis ONLY?

  Only the minor one, and that is not laziness: an overflowing run reaches PAST the control
  along the major axis (the paint clips it, the layout does not), so gating on the major
  axis too would make every hit test disagree with what is drawn -- and the strip's own
  overflow tests press at shifted midpoints that lie beyond Width. At tpTop the band is
  Rect(0, 0, Width, TabH) and this is the `Y < TabH` each caller used to spell for itself. }
function TTyCustomTabStrip.HitBandMinor(AX, AY: Integer): Boolean;
var
  Band: TRect;
begin
  if TabHPx(Font.PixelsPerInch) <= 0 then Exit(False);   // TabHeight = 0: no band to hit
  Band := BandRect;
  if BandIsVertical then
    Result := (AX >= Band.Left) and (AX < Band.Right)
  else
    Result := (AY >= Band.Top) and (AY < Band.Bottom);
end;

{ --- Where the band is. See the declarations. ------------------------------------- }

function TTyCustomTabStrip.BandIsVertical: Boolean;
begin
  Result := HeaderTabPosition in [tpLeft, tpRight];
end;

{ Thickness across the band's MINOR axis. A single-row top/bottom band is one tab-height
  thick and costs nothing to answer. Everything else -- a left/right band, whose thickness is
  its widest caption box, and ANY folded band, whose thickness is RowCount rows -- is a
  number only RebuildLayout knows, so the measuring pass runs for exactly the shapes that
  need it and a default strip pays what it always paid.

  MultiLine had to join BandIsVertical in that test. It is the one line of the band-geometry
  chain that folding does change: InsetForBand, BandBoxPx and BandRect all already speak in
  terms of this answer, which is the whole reason the row count is folded into the THICKNESS
  and not carried separately. }
function TTyCustomTabStrip.BandThicknessPx: Integer;
begin
  if TabHPx(Font.PixelsPerInch) <= 0 then Exit(0);   // TabHeight = 0 still means NO band
  if not (BandIsVertical or HeaderMultiLine) then Exit(TabHPx(Font.PixelsPerInch));
  RebuildLayout(Font.PixelsPerInch);
  Result := FBandThickness;
end;

{ The band's physical rect, mirror applied -- so on a right-to-left strip a tpLeft band
  really is drawn at the right edge, and everything derived from this rect (the arrow ends,
  the backdrop fill, the paint clip) follows without a branch of its own. }
function TTyCustomTabStrip.BandRect: TRect;
begin
  Result := BandBoxPx(Width, Height, BandThicknessPx);
  if HeaderRightToLeft then
    Result := BidiFlipRect(Result, Rect(0, 0, Width, 0), True);
end;

{ The band's physical rect BEFORE the mirror, for an AW x AH box. Split out from BandRect
  because ToScreenRect needs the unmirrored origin: it embeds first and reflects last, and
  reflecting a rect that was already placed at the mirrored edge would mirror it twice. }
function TTyCustomTabStrip.BandBoxPx(AW, AH, AThickness: Integer): TRect;
begin
  case HeaderTabPosition of
    tpBottom: Result := Rect(0, AH - AThickness, AW, AH);
    tpLeft:   Result := Rect(0, 0, AThickness, AH);
    tpRight:  Result := Rect(AW - AThickness, 0, AW, AH);
  else
    { tpTop -- origin (0,0), which is what makes ToScreenRect's embed step the identity
      and the whole transform byte-identical to the pre-TabPosition one. }
    Result := Rect(0, 0, AW, AThickness);
  end;
end;

{ The control extent along the band's MAIN axis: what the strip has to fit into before it
  overflows, and what the scroll arithmetic measures against. }
function TTyCustomTabStrip.MainVisiblePx: Integer;
begin
  if BandIsVertical then Result := Height else Result := Width;
end;

{ Single-pass cached layout, and the ONLY layout builder in this unit. Builds
  FHeaderRects/FCloseRects/FIconRects for all tabs in CONTENT space (device px, origin 0,
  reading order, x carries the MAIN axis and y the CROSS axis -- see ToScreenRect).

  Every TabPosition goes through this one builder because they share the whole of the
  problem: the CAPTION BOX of a tab -- padding + optional icon slot + caption + optional
  close slot, floored at --tab-min-width -- is measured identically whichever edge the band
  is on. The four positions differ only in which of the two measured numbers becomes the
  tab's extent along the run:

    top/bottom  main extent = the caption box; band thickness = one tab height
    left/right  main extent = one tab height;  band thickness = the WIDEST caption box

  because we do not rotate captions (see the TabPosition declaration), so a side band is a
  stack of uniform-height rows whose common width has to hold the longest label. That is
  one `if` inside one loop, which is the whole cost of being axis-generic; a second builder
  would have had to duplicate the measuring, the min-width floor, the close-slot reserve,
  the overflow test and the scroll clamp to buy nothing. }
procedure TTyCustomTabStrip.RebuildLayout(APPI: Integer);
var
  TabH, Pad, MinW, CloseSize, Gap, CloseSlot, Margin: Integer;
  IconSize, IconGap, IconSlot: Integer;
  TabStyle: TTyStyleSet;
  I, J, K, X, TW, MainExt, RowThick, Cy, Lead: Integer;
  Row, CrossLo, CrossHi, RowLen, Extra, Share, Rem, N: Integer;
  MainVisible, WrapLimit, StripLen, AffordanceW, ArrowW, MaxScroll: Integer;
  Vert, Multi: Boolean;
  Boxes: array of Integer;   // pass 1: each tab's measured caption box
  Mains: array of Integer;   // pass 2: each tab's FINAL main-axis extent (post-justification)
  Rows:  array of Integer;   // pass 2: which row each tab folded into
  Band: TRect;
  dispCap: string;
  mpm: Integer;
begin
  SetLength(FHeaderRects, GetTabCount);
  SetLength(FCloseRects, GetTabCount);
  SetLength(FIconRects, GetTabCount);

  Vert      := BandIsVertical;
  Multi     := HeaderMultiLine;
  TabH      := TabHPx(APPI);
  Pad       := MulDiv(ActiveController.Metric('--tab-padding', TyTabPad), APPI, 96);
  MinW      := MulDiv(ActiveController.Metric('--tab-min-width', TyTabMinWidth), APPI, 96);
  CloseSize := MulDiv(ActiveController.Metric('--tab-close-size', TyTabCloseSize), APPI, 96);
  Gap       := MulDiv(ActiveController.Metric('--tab-gap', TyTabGap),  APPI, 96);
  Margin    := MulDiv(ActiveController.Metric('--tab-margin', TyTabMargin),  APPI, 96);
  CloseSlot := CloseSize + Gap;
  IconSize  := IconPx(APPI);                    // 0 when there is no image list
  if IconSize > 0 then
    IconGap := MulDiv(ActiveController.Metric('--tab-icon-gap', TyTabIconGap), APPI, 96)
  else
    IconGap := 0;
  IconSlot  := IconSize + IconGap;              // 0 without a list -> pre-icon arithmetic

  TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);

  { Pass 1 -- measure each tab's CAPTION BOX. This is the number the old single-position
    builder called TW and used directly as the header width; it still is, and on a
    top/bottom band nothing below changes it. }
  SetLength(Boxes, GetTabCount);
  RowThick := TabH;
  for I := 0 to GetTabCount - 1 do
  begin
    TyParseMnemonic(GetTabCaption(I), dispCap, mpm);
    TW := TabCaptionWidth(dispCap, TabStyle, APPI) + 2 * Pad;
    if (IconSize > 0) and (TabImageIndex(I) >= 0) then Inc(TW, IconSlot);
    if GetTabClosableAt(I) then
    begin
      Inc(TW, CloseSlot);
      if TW < (MinW + CloseSlot) then TW := MinW + CloseSlot;
    end
    else
      if TW < MinW then TW := MinW;
    Boxes[I] := TW;
    { A side band is only as wide as it has to be, and never narrower than one row. }
    if Vert and (TW > RowThick) then RowThick := TW;
  end;

  { Pass 2a -- FOLD. RowThick is ONE row's extent across the cross axis, and it comes from
    the same two places it always did (TabHPx off --control-height on a top/bottom band, the
    widest measured caption box on a side one); nothing here introduces a metric of its own.

    The wrap limit is the main extent MINUS the subclass's leading inset, because the run is
    drawn shifted by that inset (HeaderShiftPx) and a row measured against the full extent
    would fold one tab too late and hang it off the end.

    `(X > 0)` is not optional, and not for the reason it looks like. This is a FOR loop over
    a fixed tab count, so omitting it cannot spin -- what it does is fold a tab that is wider
    than the whole band at the START of its row, pushing it onto the next one and leaving the
    row it came from EMPTY. An over-wide tab has to be allowed to overhang a row of its own;
    there is nowhere narrower to put it. }
  MainVisible := MainVisiblePx;
  WrapLimit   := MainVisible - HeaderLeftInset;
  if WrapLimit < 1 then WrapLimit := 1;

  SetLength(Rows,  GetTabCount);
  SetLength(Mains, GetTabCount);
  Row := 0;
  X   := 0;
  for I := 0 to GetTabCount - 1 do
  begin
    if Vert then MainExt := TabH else MainExt := Boxes[I];
    if Multi and (X > 0) and (X + MainExt > WrapLimit) then
    begin
      Inc(Row);
      X := 0;
    end;
    Rows[I]  := Row;
    Mains[I] := MainExt;
    Inc(X, MainExt);
  end;

  if GetTabCount = 0 then
  begin
    { No tabs folded into no rows -- but the BAND is still there, exactly as it was before
      folding existed (an empty strip has always shown one row of backdrop). Deriving the
      thickness from FRowCount here would delete it. }
    FRowCount      := 0;
    FBandThickness := RowThick;
  end
  else
  begin
    FRowCount      := Row + 1;
    FBandThickness := FRowCount * RowThick;
  end;

  { Pass 2b -- JUSTIFY. Not folded into 2a: how many tabs share a row is only known once the
    fold is finished, so the stretch has to be a separate sweep over completed rows. It
    re-measures nothing; it only widens numbers pass 1 already produced.

    The remainder is handed out one pixel at a time rather than dropped. `Extra div N` alone
    leaves the row up to N-1 px short of the band edge, which on a skin with a visible tab
    border is a ragged notch at the end of every row -- the exact thing RaggedRight = False
    exists to remove. }
  if Multi and (not FRaggedRight) then
  begin
    I := 0;
    while I < GetTabCount do
    begin
      J      := I;
      RowLen := 0;
      while (J < GetTabCount) and (Rows[J] = Rows[I]) do
      begin
        Inc(RowLen, Mains[J]);
        Inc(J);
      end;
      N     := J - I;
      Extra := WrapLimit - RowLen;
      if Extra > 0 then            // an over-wide lone tab OVERHANGS; it is never shrunk
      begin
        Share := Extra div N;
        Rem   := Extra mod N;
        for K := I to J - 1 do
        begin
          Inc(Mains[K], Share);
          if (K - I) < Rem then Inc(Mains[K]);
        end;
      end;
      I := J;
    end;
  end;

  { Pass 2c -- PLACE. The close slot sits at the trailing edge of the caption box and the
    icon at its leading edge; the caption box runs along the MAIN axis on a top/bottom band
    and along the CROSS axis on a left/right one, because the text itself is upright in all
    four. Every cross coordinate is measured from CrossLo -- the row's own leading edge --
    rather than from the band's, which is what carries the close glyph and the icon down onto
    row 1 with their tab instead of stranding them all on row 0. At RowCount = 1 CrossLo is 0
    and CrossHi is the band thickness, so this is byte-identical to the unfolded arithmetic. }
  X   := 0;
  Row := -1;
  for I := 0 to GetTabCount - 1 do
  begin
    if Rows[I] <> Row then
    begin
      Row := Rows[I];
      X   := 0;
    end;
    MainExt := Mains[I];
    CrossLo := Row * RowThick;
    CrossHi := CrossLo + RowThick;
    FHeaderRects[I] := Rect(X, CrossLo, X + MainExt, CrossHi);

    if GetTabClosableAt(I) then
    begin
      if Vert then
      begin
        { Centred down the row, measured against the tab's OWN extent so a justified row
          (whose rows are taller than TabH) keeps the glyph in the middle of its tab. }
        Cy := X + (MainExt - CloseSize) div 2;
        FCloseRects[I] := Rect(Cy, CrossHi - Margin - CloseSize,
                               Cy + CloseSize, CrossHi - Margin);
      end
      else
      begin
        Cy := CrossLo + (RowThick - CloseSize) div 2;
        FCloseRects[I] := Rect(X + MainExt - Margin - CloseSize, Cy,
                               X + MainExt - Margin, Cy + CloseSize);
      end;
    end
    else
      FCloseRects[I] := Rect(0, 0, 0, 0);

    if (IconSize > 0) and (TabImageIndex(I) >= 0) then
    begin
      if Vert then
      begin
        Lead := X + (MainExt - IconSize) div 2;     // centred down the row
        FIconRects[I] := Rect(Lead, CrossLo + Pad, Lead + IconSize, CrossLo + Pad + IconSize);
      end
      else
      begin
        Cy := CrossLo + (RowThick - IconSize) div 2;
        FIconRects[I] := Rect(X + Pad, Cy, X + Pad + IconSize, Cy + IconSize);
      end;
    end
    else
      FIconRects[I] := Rect(0, 0, 0, 0);

    Inc(X, MainExt);
  end;

  { The run's main extent is the LONGEST row -- which is the last header's Right while there
    is only one row, and is not once there are several (X now holds the last row's length,
    which on a folded strip is usually the shortest). Decide whether that overflows the
    control along the MAIN axis and, if so, reserve an arrow affordance band (two Scale(16)
    arrows) at the run's two ends.

    MULTILINE FORCES THE AFFORDANCE OFF, and that is the feature's one hard interlock rather
    than a tidy-up: folding exists precisely so that nothing is off-screen, so arrows would
    reserve 16px at each end of every row to reach content already in view -- and the first
    tab of every row would be drawn under one of them. FHeaderScroll follows automatically:
    with no affordance MaxScroll is 0 and the clamp at the bottom of this function pins it. }
  StripLen := 0;
  for I := 0 to GetTabCount - 1 do
    if FHeaderRects[I].Right > StripLen then StripLen := FHeaderRects[I].Right;

  AffordanceW  := MulDiv(ActiveController.Metric('--tab-arrow-band', TyTabArrowBand), APPI, 96) * 2;
  FShowScrollAffordance := (not Multi) and (StripLen > MainVisible);
  if FShowScrollAffordance then
  begin
    ArrowW := MulDiv(ActiveController.Metric('--tab-arrow-band', TyTabArrowBand), APPI, 96);
    FArrowBandPx     := ArrowW;
    { The two arrows change ENDS when the strip reads right-to-left, and their names do not:
      FScrollLeftRect is the BACK arrow (a click on it decreases the scroll) and belongs at
      the reading START, which is the right edge there. Renaming the fields would be a
      breaking change for no behavioural gain, so the plan rules it out (§6.3.6) and the
      documentation carries the warning instead -- which is also why every test for this
      asserts the SCROLL DIRECTION a click produces and not the field name.

      Cut from BandRect rather than from Rect(0,0,Width,TabH), so the two arrows land on
      whichever edge the band is on and mirror with it; and written as explicit branches
      rather than a BidiFlipRect over the pair, because these two rects are the only
      geometry in the unit that is NOT in content space -- they are already physical, so
      putting them through the content transform would mirror them twice.

      A VERTICAL band's reading start is the TOP, mirrored or not: reflecting the screen's
      x axis cannot reorder a run that goes down the page (the plan's logical-vs-visual
      rule, §6.3.3), so only the horizontal case has ends to trade.

      Built from the LOCAL FBandThickness rather than from BandRect, which is the same rect:
      BandRect asks BandThicknessPx, and on a vertical (or folded) band BandThicknessPx asks
      RebuildLayout -- i.e. this function. FBandThickness is that answer, set just above.
      Only reached with Multi = False, so the band is one row here either way. }
    Band := BandBoxPx(Width, Height, FBandThickness);
    if HeaderRightToLeft then
      Band := BidiFlipRect(Band, Rect(0, 0, Width, 0), True);
    if Vert then
    begin
      FScrollLeftRect  := Rect(Band.Left, Band.Top, Band.Right, Band.Top + ArrowW);
      FScrollRightRect := Rect(Band.Left, Band.Bottom - ArrowW, Band.Right, Band.Bottom);
    end
    else if HeaderRightToLeft then
    begin
      FScrollLeftRect  := Rect(Band.Right - ArrowW, Band.Top, Band.Right, Band.Bottom);
      FScrollRightRect := Rect(Band.Left, Band.Top, Band.Left + ArrowW, Band.Bottom);
    end
    else
    begin
      FScrollLeftRect  := Rect(Band.Left, Band.Top, Band.Left + ArrowW, Band.Bottom);
      FScrollRightRect := Rect(Band.Right - ArrowW, Band.Top, Band.Right, Band.Bottom);
    end;
  end
  else
  begin
    FArrowBandPx     := 0;
    FScrollLeftRect  := Rect(0, 0, 0, 0);
    FScrollRightRect := Rect(0, 0, 0, 0);
    AffordanceW := 0; // no band reserved when content fits
  end;

  { Clamp the current scroll to the new maximum. Max scroll is the overshoot of the run past
    the visible extent minus the affordance band. Measured off StripLen and not off X: X now
    holds the LAST ROW's length, which is the same number only while there is one row -- and
    a folded strip never gets here anyway, because folding cleared the affordance above. }
  if FShowScrollAffordance then
    MaxScroll := StripLen - (MainVisible - AffordanceW)
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

{ Unshifted main extent of the header strip: the LONGEST row (rebuilt at the control's
  current PPI). While the run is one row that is the last header's right edge, which is what
  this used to read directly; once the run folds, the last header is at the end of the last
  row -- normally the SHORTEST one -- and reading it would report a strip narrower than the
  one on screen. }
function TTyCustomTabStrip.TyHeaderStripWidth: Integer;
var
  I: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  Result := 0;
  for I := 0 to High(FHeaderRects) do
    if FHeaderRects[I].Right > Result then Result := FHeaderRects[I].Right;
end;

{ Largest valid scroll: the overshoot of the run past the visible MAIN extent minus
  the reserved arrow band. 0 when the strip fits. Mirrors RebuildLayout's clamp. }
function TTyCustomTabStrip.TyMaxHeaderScroll: Integer;
var
  I, StripW, MainVisible, AffordanceW: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  { A folded strip has no affordance (RebuildLayout clears it), so this is the ONE place
    MultiLine's "no scrolling" promise is observable from outside, and it answers 0. }
  if not FShowScrollAffordance then Exit(0);
  StripW := 0;
  for I := 0 to High(FHeaderRects) do
    if FHeaderRects[I].Right > StripW then StripW := FHeaderRects[I].Right;
  MainVisible  := MainVisiblePx;
  AffordanceW  := MulDiv(ActiveController.Metric('--tab-arrow-band', TyTabArrowBand), Font.PixelsPerInch, 96) * 2;
  Result := StripW - (MainVisible - AffordanceW);
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

{ Slide along MAIN, embed at the band, then -- when the strip reads right-to-left --
  reflect the SCREEN x about the control's width. See the declaration for why that order.

  A REFLECTION of the finished layout, not a reversed accumulation loop: a reflection of a
  gapless tiling is gapless by construction, so the mirrored strip cannot grow a 1px seam of
  page body between two headers, and every derived rect (the close slot and the icon slot,
  which live INSIDE a header) lands in the right place without a second formula. LCL's
  BidiFlipRect (controls.pp:2966) is that five-line arithmetic, used here rather than
  rewritten so nobody has to check a `-1` twice.

  The reflection uses the control's own Width -- the same quantity RebuildLayout pins the
  arrow ends to -- so the band between the two arrows maps onto itself and the scroll
  arithmetic, which is all in content space, needs no mirror of its own. }
function TTyCustomTabStrip.ToScreenRect(const AContentRect: TRect): TRect;
var
  R, Band: TRect;
begin
  R := AContentRect;
  OffsetRect(R, HeaderShiftPx, 0);
  Band := BandBoxPx(Width, Height, BandThicknessPx);
  if BandIsVertical then
    { main -> y, cross -> x }
    Result := Rect(Band.Left + R.Top,    Band.Top + R.Left,
                   Band.Left + R.Bottom, Band.Top + R.Right)
  else
    { main -> x, cross -> y. At tpTop the band origin is (0,0), so this is R unchanged. }
    Result := Rect(Band.Left + R.Left,  Band.Top + R.Top,
                   Band.Left + R.Right, Band.Top + R.Bottom);
  if HeaderRightToLeft then
    Result := BidiFlipRect(Result, Rect(0, 0, Width, 0), True);
end;

{ ToScreenRect run backwards as far as the shift -- un-reflect, then un-embed -- which is
  what makes this its EXACT inverse rather than a hand-written `Width - 1 - X` that could
  drift from it by one pixel. `MainOf(pt) in ToScreenRect(R)` and `ToReadingMain(pt) in
  shifted R` are then the same predicate for every point, which is the property
  TyDropIndexAtPoint relies on to keep a single forward comparison.

  The reflection is undone on a 1px-wide rect for the same reason it is applied on one. }
function TTyCustomTabStrip.ToReadingMain(const APt: TPoint): Integer;
var
  MX: Integer;
  Band: TRect;
begin
  MX := APt.X;
  if HeaderRightToLeft then
    MX := BidiFlipRect(Rect(MX, 0, MX + 1, 0), Rect(0, 0, Width, 0), True).Left;
  { The thickness is passed as 0 deliberately. BandBoxPx uses it only to place the band
    across its MINOR axis, and the two lines below read the MAJOR one -- so the answer is
    the same for every thickness, while asking for the real one would mean measuring the
    entire strip (on a side band BandThicknessPx rebuilds the layout) to learn a number
    this cannot use. Still routed through BandBoxPx rather than a hand-written 0, so that
    if the band ever grows a leading gap this inverse picks it up out of the same function
    ToScreenRect placed it with. }
  Band := BandBoxPx(Width, Height, 0);
  if BandIsVertical then
    Result := APt.Y - Band.Top     // main runs down the side; x carried the cross axis
  else
    Result := MX - Band.Left;      // at tpTop Band.Left is 0, so this is the un-reflected x
end;

{ The same inverse read off the OTHER axis, deliberately written next to ToReadingMain and
  built out of the same two undone steps in the same order, so that a change to one is in the
  reviewer's eye when the other is edited. Two inverses of one transform that live apart is
  how a fold ends up drawn on row 1 and answered on row 0.

  The one asymmetry is the thickness handed to BandBoxPx, and it is not an oversight in
  either direction. ToReadingMain reads the axis the band RUNS along, which BandBoxPx places
  at 0 for every thickness, so it passes 0 and skips measuring the strip. This reads the axis
  the band is THICK along, which is the only thing that argument moves, so it has to pay for
  the real number -- and on a folded or vertical band paying for it means a layout pass. }
function TTyCustomTabStrip.ToReadingCross(const APt: TPoint): Integer;
var
  CX: Integer;
  Band: TRect;
begin
  CX := APt.X;
  if HeaderRightToLeft then
    CX := BidiFlipRect(Rect(CX, 0, CX + 1, 0), Rect(0, 0, Width, 0), True).Left;
  Band := BandBoxPx(Width, Height, BandThicknessPx);
  if BandIsVertical then
    Result := CX - Band.Left     // cross runs across the side band; x carried it
  else
    Result := APt.Y - Band.Top;  // at tpTop Band.Top is 0, so this is the plain y
end;

function TTyCustomTabStrip.ToReadingX(AX: Integer): Integer;
begin
  Result := ToReadingMain(Point(AX, 0));
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
    { Tabs render inset by ArrowW (HeaderShiftPx), so content-main 0 maps to the band's
      starting edge. Measure "into view" in content-minus-scroll space, where the visible
      run is [0, MainVisiblePx - 2*ArrowW] with BOTH arrow bands reserved. }
    VisLeft  := 0;
    VisRight := MainVisiblePx - 2 * ArrowW;
  end
  else
  begin
    VisLeft  := 0;
    VisRight := MainVisiblePx;
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
begin
  Result := Rect(0, 0, Width, Height);
  InsetForBand(Result);           // the same inset AdjustClientRect applies
end;

{ The edge the band is DRAWN on, mirror applied -- the one answer every edge-picking rule
  below takes. On a right-to-left strip tpLeft and tpRight trade places, because
  ToScreenRect's reflection moves the band to the other side and the client-rect inset, the
  frame overlap and the baseline rail all have to move with it. Top and bottom do not trade:
  reflecting the x axis cannot swap them. }
function TTyCustomTabStrip.EffectiveBandSide: TTabPosition;
begin
  Result := HeaderTabPosition;
  if HeaderRightToLeft then
    case Result of
      tpLeft:  Result := tpRight;
      tpRight: Result := tpLeft;
    end;
end;

{ Take the band's edge out of ARect. The ONE place that turns "which edge is the band on"
  into a client-rect inset, shared by AdjustClientRect (which the align engine uses to lay
  the pages out) and DisplayRect (which reports the body to callers), so the two cannot
  disagree about where the body starts. }
procedure TTyCustomTabStrip.InsetForBand(var ARect: TRect);
var
  T: Integer;
begin
  T := BandThicknessPx;
  if T <= 0 then Exit;            // TabHeight = 0: no band, the body fills the control
  case EffectiveBandSide of
    tpBottom: Dec(ARect.Bottom, T);
    tpLeft:   Inc(ARect.Left,   T);
    tpRight:  Dec(ARect.Right,  T);
  else
    Inc(ARect.Top, T);
  end;
  if ARect.Top  > ARect.Bottom then ARect.Top  := ARect.Bottom;
  if ARect.Left > ARect.Right  then ARect.Left := ARect.Right;
end;

{ Push ARect's band-facing edge BACK into the band by AAmount px, so the page frame and the
  active tab merge into one another. At tpTop this is the old `ContentTop := TabH - 1px`. }
procedure TTyCustomTabStrip.GrowTowardBand(var ARect: TRect; AAmount: Integer);
begin
  if AAmount <= 0 then Exit;
  case EffectiveBandSide of
    tpBottom: Inc(ARect.Bottom, AAmount);
    tpLeft:   Dec(ARect.Left,   AAmount);
    tpRight:  Inc(ARect.Right,  AAmount);
  else
    Dec(ARect.Top, AAmount);
  end;
end;

{ The AThick-px sliver of ARect that lies ALONG the band -- the baseline rail a caption-only
  strip keeps when it drops the rest of the page box. At tpTop this is
  `Rect(0, Top, W, Top + AThick)`, the row the frame's top border occupied. }
function TTyCustomTabStrip.BandEdgeOf(const ARect: TRect; AThick: Integer): TRect;
begin
  case EffectiveBandSide of
    tpBottom: Result := Rect(ARect.Left, ARect.Bottom - AThick, ARect.Right, ARect.Bottom);
    tpLeft:   Result := Rect(ARect.Left, ARect.Top, ARect.Left + AThick, ARect.Bottom);
    tpRight:  Result := Rect(ARect.Right - AThick, ARect.Top, ARect.Right, ARect.Bottom);
  else
    Result := Rect(ARect.Left, ARect.Top, ARect.Right, ARect.Top + AThick);
  end;
end;

function TTyCustomTabStrip.IndexOfTabAt(X, Y: Integer): Integer;
var
  PPI, I: Integer;
  HR: TRect;
begin
  Result := -1;
  PPI  := Font.PixelsPerInch;
  if not HitBandMinor(X, Y) then Exit;   // no band, or the point is off it
  RebuildLayout(PPI);
  { The overflow arrows sit ON the band but are not tabs; a click there scrolls, so a
    hit-test that named a tab would put a context menu on a tab the user never aimed at. }
  if FShowScrollAffordance then
  begin
    if HitRect(FScrollLeftRect, X, Y) then Exit;
    if HitRect(FScrollRightRect, X, Y) then Exit;
  end;
  { BOTH axes, on every band and whether it folded or not.

    It used to be the MAIN axis alone, because a single-row tab spans the whole band across
    the cross axis and the HitBandMinor gate above had already tested that -- the two are the
    same predicate there, which is why nothing below changes for an unfolded strip. They stop
    being the same the moment the run folds: two tabs one above the other cover the same main
    span, a main-only scan finds the row-0 one first, and every tab on row 1 becomes
    unclickable while still being drawn. Written as the unconditional two-axis test rather
    than as `if MultiLine then` so there is one rule to check against the paint, not two. }
  for I := 0 to GetTabCount - 1 do
  begin
    HR := ToScreenRect(FHeaderRects[I]);
    if HitRect(HR, X, Y) then Exit(I);
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
begin
  Result := TyDropIndexAtPoint(Point(X, 0), APPI);
end;

function TTyCustomTabStrip.TyDropIndexAtPoint(const APt: TPoint; APPI: Integer): Integer;
var
  I, Mid, RM, RC: Integer;
  HR: TRect;
  Folded, Past: Boolean;
begin
  if GetTabCount = 0 then Exit(0);
  RebuildLayout(APPI);
  RM := ToReadingMain(APt);

  { Is there any row STRUCTURE to compare? Asked of the finished layout (FRowCount) and not
    of the MultiLine property, because that is the condition the comparison below actually
    needs -- MultiLine with everything on one row has no rows to tell apart either.

    The one-row branch is SPELLED OUT rather than derived. The tempting version is to let the
    folded comparison degenerate, and it does not: TabHeight = 0 is a shipped capability (no
    band at all), it makes RowThick and therefore every row's cross extent ZERO, and a
    half-open `RC < HR.Bottom` can never be satisfied against a zero-height row -- the scan
    would fall through every tab and answer with its default for every point on the strip.
    That is a live regression in TyDropIndexAt, which is pure public API and does not go
    through the HitBandMinor gate that hides the rest of a zero-height band. }
  Folded := FRowCount > 1;

  { The pointer's row, CLAMPED into the band. A drag leaves the band constantly, and
    unclamped the comparison would answer with the row above the first or below the last --
    different SLOTS, not nearby ones. Only meaningful while folded, and only computed then:
    a zero-thickness band has no range to clamp into. }
  RC := ToReadingCross(APt);
  if Folded then
  begin
    if RC < 0 then RC := 0;
    if RC > FBandThickness - 1 then RC := FBandThickness - 1;
  end;

  Result := GetTabCount - 1; // default: past every midpoint on the last row -> last
  for I := 0 to GetTabCount - 1 do
  begin
    HR := FHeaderRects[I];
    OffsetRect(HR, HeaderShiftPx, 0); // shifted midpoint (incl. arrow-band inset)
    { Content space always carries MAIN in x and CROSS in y, whichever edge the band ended up
      on -- so this stays the one forward comparison, and it is the paint's own midpoint
      because ToReadingMain/ToReadingCross are exactly the transform that placed the paint,
      run backwards.

      LEXICOGRAPHIC (row, main): tab I is past the pointer if its row is past the pointer's,
      or they share a row and its midpoint is. A main-only rule answers "the nearest midpoint
      anywhere", so dragging up from row 1 into row 0 would drop at whichever row-1 tab
      happened to have a midpoint past the pointer -- a whole slot wrong, silently, and only
      in the gesture nobody re-tests. }
    Mid := (HR.Left + HR.Right) div 2;
    if Folded then
      Past := (RC < HR.Top) or ((RC < HR.Bottom) and (RM < Mid))
    else
      Past := RM < Mid;          // byte-for-byte the rule this shipped with
    if Past then
    begin
      Result := I;
      Break;
    end;
  end;
  if Result < 0 then Result := 0;
  if Result > GetTabCount - 1 then Result := GetTabCount - 1;
end;

{ --- Tab icons ------------------------------------------------------------------- }

{ The per-tab index first, the event last -- the order TTyListView and TTyTreeView already
  use, so a handler sees the value it is replacing and a control with no handler keeps the
  per-tab one. }
function TTyCustomTabStrip.TabImageIndex(AIndex: Integer): Integer;
begin
  Result := -1;
  if (AIndex < 0) or (AIndex >= GetTabCount) then Exit;
  Result := GetTabImageIndex(AIndex);
  if Assigned(FOnGetImageIndex) then
    FOnGetImageIndex(Self, AIndex, Result);
end;

function TTyCustomTabStrip.TabImageRect(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FIconRects)) then Exit(Rect(0, 0, 0, 0));
  if FIconRects[AIndex].Right <= FIconRects[AIndex].Left then Exit(Rect(0, 0, 0, 0));
  Result := ToScreenRect(FIconRects[AIndex]);
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
  InsetForBand(ARect);
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
  W, H, TabH, I, Overlap: Integer;
  HdrRect, CloseRect, TextRect, IconRect, SavedClip: TRect;
  Band, Body, ClipBand: TRect;
  TabStates: TTyStateSet;
  CloseHi, BaseFill: TTyFill;
  BaseW, IconIdx: Integer;
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
    TabH := BandThicknessPx;
    Band := BandRect;

    { The header strip is only painted where tab headers land; the empty area past
      the last tab would otherwise be a stale gap. On an image theme fill
      the whole strip with the form's photo; off-image fill it with the OPAQUE
      resolved parent background (the tabs sit on the form backdrop) so the gap is
      not a transparent hole the Win10 DWM glass shows as the system color. }
    if not FillSharpBackdrop(P, Band) then
      TyFillParentBg(Self, P, Band, BoxStyle);

    { Fill the content area with the form's photo (image theme) or the opaque parent bg
      (solid) FIRST, so a transparent content surface (e.g. green's ribbon body) shows the
      photo instead of a white hole; DrawFrame's own (possibly transparent) fill goes on top. }
    { The content frame overlaps the strip by 1px so the active tab merges into it — but with
      NO strip (TabHeight = 0) that would pull the frame's border off the control. Which
      EDGE it overlaps follows the band, so a bottom band's frame reaches down and a side
      band's reaches sideways; at tpTop this is the old `ContentTop := TabH - 1px`. }
    Body := Rect(0, 0, W, H);
    InsetForBand(Body);
    Overlap := MulDiv(1, APPI, 96);
    if TabH > 0 then
      GrowTowardBand(Body, Min(Overlap, TabH));
    if not FillSharpBackdrop(P, Body) then
      TyFillParentBg(Self, P, Body, BoxStyle);
    if HasPageBody then
      DrawFrame(P, Body, BoxStyle)
    else
    begin
      { Caption-only strip: no page container, so no box. Keep just the frame's border
        along the band as a baseline the tabs sit on — same pixel row, same themed colour
        and width, so the rail stays and only the empty body goes. Laid down as a crisp
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
        P.FillBackground(BandEdgeOf(Body, BaseW), BaseFill, 0);
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

    { When overflowing, clip the header strip to the stretch of band between the two arrow
      affordances so shifted headers do not paint over the arrows or past the
      control. When it fits, clip to the whole band (offset is 0 anyway). }
    SavedClip := P.Bitmap.ClipRect;
    if FShowScrollAffordance then
      { The band BETWEEN the arrows, whichever end each of them is on. The old expression
        named FScrollLeftRect.Right and FScrollRightRect.Left directly, which is the same
        band only while the back arrow is the left one -- mirrored, it names an INVERTED
        (empty) clip and every header disappears. Min/Max is the same two numbers in
        left-to-right, so this is byte-identical there; and taken along the MAIN axis only,
        so a side band clips top-and-bottom instead. }
      if BandIsVertical then
        ClipBand := Rect(Band.Left,
                         Min(FScrollLeftRect.Bottom, FScrollRightRect.Bottom),
                         Band.Right,
                         Max(FScrollLeftRect.Top,    FScrollRightRect.Top))
      else
        ClipBand := Rect(Min(FScrollLeftRect.Right, FScrollRightRect.Right), Band.Top,
                         Max(FScrollLeftRect.Left,  FScrollRightRect.Left),  Band.Bottom)
    else
      ClipBand := Band;
    P.Bitmap.ClipRect := ClipBand;

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

      { Draw caption centered in header, clipped off the close glyph and the icon. The
        close slot is at the header's TRAILING edge -- the right one normally, the left one
        when the strip reads right-to-left (the reflection put it there) -- so it is the
        opposite edge of the caption box that has to give way. Both rects are already
        SCREEN rects and the caption is upright in every TabPosition, so this rule needs no
        branch for a side band: the reflection has already decided which end is which. }
      TextRect := HdrRect;
      if GetTabClosableAt(I) then
      begin
        if Rtl then
          TextRect.Left := CloseRect.Right
        else
          TextRect.Right := CloseRect.Left;
      end;

      { The icon sits at the caption box's LEADING edge, and the caption steps aside by
        exactly the slot RebuildLayout reserved for it. Blitted through CachedIndex, which
        hands back a borrowed bitmap and allocates nothing -- the path every other icon
        consumer in this library uses (TTyListView.DrawImage). }
      IconIdx := TabImageIndex(I);
      if (FImages <> nil) and (IconIdx >= 0) and (IconIdx < TyImageCount(FImages)) and
         (FIconRects[I].Right > FIconRects[I].Left) then
      begin
        IconRect := ToScreenRect(FIconRects[I]);
        TyBlitImage(P.Bitmap, FImages, IconIdx, IconRect.Left, IconRect.Top,
          IconRect.Right - IconRect.Left, P.Scale(96), False);
        if Rtl then
        begin
          if IconRect.Left < TextRect.Right then TextRect.Right := IconRect.Left;
        end
        else
          if IconRect.Right > TextRect.Left then TextRect.Left := IconRect.Right;
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
        mirrored strip the back arrow is at the right and points right, and on a side band
        the run goes down the page so they point up and down instead. Two arrows both
        pointing the old way over swapped rects would be the "size grip drawn on one side,
        grabbed on the other" defect (§5.5) in miniature. }
      if BandIsVertical then
      begin
        { Triangles: the native tab control scrolls with an UPDOWN, i.e. the spin part. }
        P.DrawGlyph(TySquareGlyphBox(FScrollLeftRect),  tgTriangleUp,   ArrowStyle.TextColor, 2, 1);
        P.DrawGlyph(TySquareGlyphBox(FScrollRightRect), tgTriangleDown, ArrowStyle.TextColor, 2, 1);
      end
      else if Rtl then
      begin
        P.DrawGlyph(TySquareGlyphBox(FScrollLeftRect),  tgTriangleRight, ArrowStyle.TextColor, 2, 1);
        P.DrawGlyph(TySquareGlyphBox(FScrollRightRect), tgTriangleLeft,  ArrowStyle.TextColor, 2, 1);
      end
      else
      begin
        P.DrawGlyph(TySquareGlyphBox(FScrollLeftRect),  tgTriangleLeft,  ArrowStyle.TextColor, 2, 1);
        P.DrawGlyph(TySquareGlyphBox(FScrollRightRect), tgTriangleRight, ArrowStyle.TextColor, 2, 1);
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
  PPI, Step, I: Integer;
  HdrRect, CloseRect: TRect;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    PPI  := Font.PixelsPerInch;
    if HitBandMinor(X, Y) then
    begin
      RebuildLayout(PPI);

      { Affordance arrows take priority over the header scan. Each click nudges
        the scroll by ~40 logical px (clamped inside SetHeaderScroll). }
      if FShowScrollAffordance then
      begin
        Step := MulDiv(40, PPI, 96);
        if HitRect(FScrollLeftRect, X, Y) then
        begin
          SetHeaderScroll(FHeaderScroll - Step);
          Exit;
        end;
        if HitRect(FScrollRightRect, X, Y) then
        begin
          SetHeaderScroll(FHeaderScroll + Step);
          Exit;
        end;
      end;

      for I := 0 to GetTabCount - 1 do
      begin
        HdrRect := HeaderRectShifted(I);
        if HitRect(HdrRect, X, Y) then     // both axes -- see IndexOfTabAt
        begin
          CloseRect := ToScreenRect(FCloseRects[I]);
          if GetTabClosableAt(I) and HitRect(CloseRect, X, Y) then
            DoCloseClick(I)
          else
          begin
            TabIndex := I;
            { Arm a drag-reorder candidate. A plain press+release stays a click
              (FDragging never flips); only a move past the threshold reorders.
              FDragOrigin pins the start index so MouseUp can report the net move. }
            FDragTab    := I;
            FDragOrigin := I;
            FDragStartMain := MainOf(X, Y);
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
  PPI, NewHover, NewHoverClose, I, Target: Integer;
  HdrRect, CloseRect: TRect;
  OverArrow: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  PPI  := Font.PixelsPerInch;

  { Drag-reorder gesture. While a candidate is armed and the left button is held,
    a move past the threshold flips into live reorder mode. Each subsequent move
    drops the dragged tab at the index its current X resolves to (shifted-midpoint
    rule). The subclass owns the tab data, so the live move is delegated via
    DoReorderTabs(from, to); FDragTab tracks the dragged tab's new live index.
    Skip the hover scan while dragging. }
  if (FDragTab >= 0) and (ssLeft in Shift) then
  begin
    { Travel is measured along the band's MAIN axis -- the axis the tabs are strung out on
      and therefore the only one a reorder can happen along. On a top/bottom band MainOf is
      X and this is the old `Abs(X - FDragStartX)`. }
    if (not FDragging) and
       (Abs(MainOf(X, Y) - FDragStartMain) >= TyDragThresholdPx(PPI)) then
      FDragging := True;
    if FDragging then
    begin
      { The POINT form, not TyDropIndexAt(X, ...): the midpoint rule has to follow the
        paint onto whichever axis the band runs along, and handing it an x on a side band
        would leave the drag resolving against a coordinate the paint never used. That is
        the one desync this control is most prone to -- the header and the body have come
        apart here before -- so the drag takes the same transform the paint does. }
      Target := TyDropIndexAtPoint(Point(X, Y), PPI);
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
  if HitBandMinor(X, Y) then
  begin
    RebuildLayout(PPI);
    { Over an affordance arrow counts as no tab hover. }
    OverArrow := FShowScrollAffordance and
      (HitRect(FScrollLeftRect, X, Y) or HitRect(FScrollRightRect, X, Y));
    if not OverArrow then
      for I := 0 to GetTabCount - 1 do
      begin
        HdrRect := HeaderRectShifted(I);
        if HitRect(HdrRect, X, Y) then     // both axes -- see IndexOfTabAt
        begin
          NewHover := I;
          { Independent close (x) hover: only when closable and the pointer is
            inside this tab's shifted close rect. Mirrors the MouseDown hit-test
            so the highlight and the actual close target stay in lockstep. }
          if GetTabClosableAt(I) then
          begin
            CloseRect := ToScreenRect(FCloseRects[I]);
            if HitRect(CloseRect, X, Y) then NewHoverClose := I;
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
  PPI, Step: Integer;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then
    Exit(True);

  PPI  := Font.PixelsPerInch;
  RebuildLayout(PPI);

  Result := False;
  if HitBandMinor(MousePos.X, MousePos.Y) and FShowScrollAffordance then
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
  { Reflecting the screen's x axis cannot reverse a run that goes DOWN the page, so a
    left/right band's order never turns -- the same logical-vs-visual line §6.3.3 draws for
    Home/End. Only a top/bottom band trades its two arrows. }
  if HeaderRightToLeft and not BandIsVertical then Step := -1 else Step := 1;
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
    { Up/Down step the selection only on a band whose run IS vertical. Handling them on a
      top/bottom band would swallow two keys the strip has never consumed -- a host that
      routes Up/Down to the active page's content would stop receiving them. }
    VK_UP:
      if BandIsVertical then
      begin
        NewIndex := FTabIndex - 1;
        if NewIndex < 0 then NewIndex := 0;
        TabIndex := NewIndex; Key := 0;
      end;
    VK_DOWN:
      if BandIsVertical then
      begin
        NewIndex := FTabIndex + 1;
        if NewIndex > Cnt - 1 then NewIndex := Cnt - 1;
        TabIndex := NewIndex; Key := 0;
      end;
  end;
end;

end.
