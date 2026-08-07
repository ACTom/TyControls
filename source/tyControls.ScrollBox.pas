unit tyControls.ScrollBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Panel, tyControls.ScrollBar, tyControls.ScrollContent;

type
  { TTyScrollBox — a scrolling viewport for oversized child content.

    Subclasses TTyPanel for the frame + container plumbing, but carries its OWN
    'TyScrollBox' typeKey (see GetStyleTypeKey). It hosts
    arbitrary child controls whose bounding box may exceed the viewport; a vertical
    and a horizontal TTyScrollBar (both csNoDesignVisible, owned by Self) appear ONLY
    when the content overflows on that axis.

    A scroll offset (FScrollX/FScrollY, both >= 0) tracks how far the content has been
    scrolled, and it is the SINGLE SOURCE OF TRUTH: on a scrollbar change we commit the
    new offset first, then call inherited ScrollBy(-dx,-dy) to move the child controls,
    then put the two scrollbars back on their gutters (ScrollBy moved them too) — back to
    the rect MeasureAndDock decided on, never to a second copy of that arithmetic; see
    FVBarRect. The whole move runs inside one DisableAutoSizing/EnableAutoSizing pair so
    it costs a single layout pass. The content RANGE is the bounding box of the
    NON-scrollbar children in LOGICAL (un-scrolled) coordinates — each child's current
    position plus the current offset.

    Being a CONTAINER is the other half of the job, and it is all in AdjustClientRect
    (see there): the LCL alignment engine has to know that a visible bar owns a gutter,
    and that the layout origin is the SCROLLED origin. Without the first, an aligned
    child is sized over the bar; without the second, every realign undoes the scroll for
    aligned children. Re-measuring is likewise automatic — Resize, Loaded (the .lfm's
    children arrive after the last Resize) and ControlsAligned (any child added, removed,
    moved or resized) all funnel into UpdateScrollRange. }
  TTyScrollBox = class(TTyPanel)
  private
    FContent: TTyScrollContent;
    FVScrollBar: TTyScrollBar;   // nil until first needed
    FHScrollBar: TTyScrollBar;   // nil until first needed
    FScrollX: Integer;           // >= 0 : logical px the content is scrolled left
    FScrollY: Integer;           // >= 0 : logical px the content is scrolled up
    FContentW: Integer;          // logical content extent (bounding box of children)
    FContentH: Integer;
    FSyncing: Boolean;           // reentrancy guard while we drive the bars
    FInScrollBy: Boolean;        // guard so re-docking the bars is ignored by range calc
    FInUpdate: Boolean;          // reentrancy guard for UpdateScrollRange (see there)
    { WHERE THE BARS BELONG — computed once, by MeasureAndDock, and read back by the
      re-dock in ScrollContentTo.

      There used to be two copies of this arithmetic and they DISAGREED: MeasureAndDock
      docked the vertical bar at (Width-thick-bw, bw) while ScrollContentTo put it back at
      (Width-thick, 0). Every single scroll step therefore yanked both bars one frame-width
      off their gutter and the next measure pass shoved them back — a 1px twitch at drag
      rate, which is what "flicker while dragging the thumb" looks like, and each of those
      SetBounds calls costs a full child-realign pass of the whole box. Measured on the
      forum's own scenario (tests/scrollcluster): 12 thumb-drag steps produced 120
      ControlsAligned passes, i.e. ten layout passes per mouse move.

      Storing the rect instead of recomputing it means the re-dock cannot drift from the
      dock: it restores exactly what the dock decided, so once the bars are where they
      belong the restore is a no-op and LCL's SetBounds early-returns. }
    FVBarRect: TRect;
    FHBarRect: TRect;
    procedure RedockBars;
    procedure EnsureBars;
    procedure VScrollBarChange(Sender: TObject);
    procedure HScrollBarChange(Sender: TObject);
    procedure ScrollContentTo(ANewX, ANewY: Integer);
    function ScrollbarThick: Integer;
    function MeasureAndDock: Boolean;
  protected
    { HOW FAR THE CONTENT AREA IS PUSHED OFF THE LEFT EDGE, and the single number the whole
      mirror consists of.

      Zero left-to-right. Right-to-left it is the vertical bar's width, because the bar moves
      to the LEFT edge -- which is the loudest thing a mirrored window does, and the reason
      this control is in phase 3 at all. Every place that has to know (the layout origin in
      AdjustClientRect, the viewport's bounds, the horizontal bar's left end, both re-docks,
      ScrollInView's viewport test) adds exactly this, so there is one definition of "which
      side the gutter is on" rather than six agreeing copies.

      What it deliberately does NOT change is the SIZE anything gives up -- see GetClientRect.
      Protected rather than private because TTyScrollPanel's auto-pan viewport needs the same
      number: a pan band placed on the unmirrored side pans toward the scrollbar. }
    function LeadingInset: Integer;
    procedure Resize; override;
    procedure Loaded; override;
    procedure InsertControl(AControl: TControl; Index: Integer); override;
    { Called by the LCL at the end of every child-layout pass — i.e. after a child was
      inserted, removed, moved or resized. That is exactly when the content extent can
      have changed, so this is where the box re-measures itself. Before this hook the
      only automatic trigger was Resize, which a child change does NOT fire: a box whose
      children came from a .lfm (or from runtime code) depended on some later, incidental
      resize to ever notice its own content, and the docs had to tell hosts to call
      UpdateScrollRange by hand — something no other LCL container asks for. }
    procedure ControlsAligned; override;
    { The viewport: the box minus whatever gutters the visible bars own.

      This HAS to be on ClientRect and not just on the layout rect below. LCL records a
      child's anchor baseline from Parent.ClientWidth/ClientHeight (TControl.UpdateBaseBounds)
      but lays it out against GetLogicalClientRect/AdjustClientRect. If the two disagree by
      the scrollbar thickness, every ScrollBy — which writes bounds to each child — banks that
      difference again, and an akRight-anchored child loses a scrollbar's width on every
      single scroll until it vanishes. }
    { The themed border width in device px -- the frame the viewport must stay inside. }
    function FrameInset: Integer;
    function GetClientRect: TRect; override;
    { The themed frame still covers the WHOLE control: ClientRect now stops at the gutters,
      but the box's background/border must run under the bars and fill the corner square
      where the two of them meet. }
    procedure Paint; override;
    { HOW BIG the child layout area is. Two jobs:

      1) Take the visible bars' gutters off. Without this an alClient / alRight / alBottom /
         alTop child is sized against the full width and simply covers the scrollbar — the
         bar is there, drawn on top, but the content runs under it.
      2) Grow to the CONTENT when the content is bigger than the viewport. This is the whole
         point of a scroll box and it is not optional: DoAlign(alTop) clamps its running
         offset to this rect's Bottom, so a column of alTop rows taller than the viewport
         would pile every row past the fold on top of the last visible one. (LCL's own
         TScrollingWinControl does exactly this, growing to the scrollbar Range.) }
    function GetLogicalClientRect: TRect; override;
    { WHERE the child layout area starts. Children live in SCROLLED coordinates (ScrollBy
      moves their Left/Top), so the align engine has to agree: otherwise every realign snaps
      the aligned children straight back to the unscrolled spot and undoes the scroll — the
      thumb travels, the bar Position changes, and the content never moves. }
    procedure AdjustClientRect(var ARect: TRect); override;
    { Nudge the scroll offset by (ADx, ADy), clamped to the current scrollable range (0 on an
      axis with no bar), and keep the bar thumbs in sync. For subclasses (e.g. TTyScrollPanel's
      edge auto-pan). Safe to call after the layout has settled (bars configured). }

    { A scrollbar is an internal child; keep it out of the range measurement and out of
      the streamed/designer child list. }
    { Where the content actually lives. A box that has been given a TTyScrollContent scrolls
      INSIDE it, so the viewport's window clips the content and it can never reach the frame.
      A box without one keeps scrolling its own children exactly as before -- an existing form
      does not change behaviour by being recompiled; it gains the clipping by being given a
      viewport. }
    function ContentHost: TWinControl;
    function IsContentChild(AControl: TControl): Boolean;
    { Does this child count toward the content extent on this axis?

      Only if its size on that axis is its OWN — a child whose size comes FROM the layout
      area must not feed back INTO it. An alTop row is as wide as the layout area, so
      counting it horizontally makes: wide row -> wide content -> horizontal bar -> which
      steals height, not width, so the row stays wide -> the bar never goes away, and the
      rows sit under the vertical bar forever. Same story for alLeft/alRight vertically,
      and alClient on both. (LCL sidesteps this by deriving its Range from GetPreferredSize
      — the children's INTRINSIC sizes — rather than from their stretched bounds.)

      An alTop row still counts VERTICALLY: the stack height is exactly the content height. }
    function CountsInWidth(AControl: TControl): Boolean;
    function CountsInHeight(AControl: TControl): Boolean;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Its own key, NOT the base panel's. A scroll box is a content WELL, not a
      decorative panel: every classic look recesses it (Win32 TScrollBox carries
      WS_EX_CLIENTEDGE where TPanel is flat) and modern skins give a scroll region a
      background distinct from the surrounding surface. Pinned to 'TyPanel' a theme
      could not recess, tint or de-border the well without dragging every panel in the
      app with it. The two embedded bars are real TTyScrollBar children, so they keep
      resolving TyScrollBar/TyScrollThumb — no sub-part key is needed here. }
    function GetStyleTypeKey: string; override;
    { Recompute the logical content extent from the current children + offset, then
      show/hide/position the two scrollbars and clamp the offset. Call on Resize and
      whenever the child set changes (add/remove/move). }
    procedure UpdateScrollRange;
    { Scroll the VIEW by a delta / to an absolute offset.

      Both already existed and were protected, so the one thing a caller most wants from a
      scrolling container -- "show me a bit further down" -- was reachable only by writing
      the scrollbar's Position and hoping. }
    procedure ScrollByDelta(ADx, ADy: Integer);
    procedure ScrollTo(AX, AY: Integer);
    { ScrollBy, with the meaning it has on every OTHER scrolling container.

      This is a name that already existed and already compiled, and that is the whole
      problem: on a TScrollBox, ScrollBy is the documented "scroll the view" call, because
      TScrollingWinControl OVERRIDES TWinControl's child-mover with a real view scroll
      (C:/lazarus/lcl/include/scrollingwincontrol.inc:276-279). Ours did not override it, so
      a ported `Box.ScrollBy(0, -50)` reached TWinControl's version
      (include/wincontrol.inc:6255-6268) and re-bounded EVERY child -- including the two
      scrollbars, which walked off their docked edges -- while FScrollX/FScrollY, documented
      at the top of this unit as the single source of truth, stayed where they were. The
      next UpdateScrollRange then measured the moved children as a SMALLER content extent
      (MeasureAndDock adds the offset back in), so the range and the thumb were both wrong
      and the following drag made the content jump. Same name, same arity, same parameter
      types, different meaning, no compile error.

      Sign convention is LCL's: the arguments are how far the CONTENT moves, so a negative
      DeltaY pushes the content up, i.e. scrolls DOWN -- hence the negation into the offset.
      The child-moving original is still what does the work; it is reached as `inherited`
      from ScrollContentTo, which is the only caller that wants it. }
    procedure ScrollBy(DeltaX, DeltaY: Integer); override;
    { Scroll the minimum amount that brings AControl fully into the viewport.

      Nothing here could do this, and a host could not hand-roll it either while the only
      mutator was protected. It is what makes keyboard navigation follow the content: tab to
      a child below the fold and it is still off screen otherwise. Clamped like LCL's
      (include/scrollingwincontrol.inc:281-312): a child TALLER than the viewport aligns its
      top edge rather than chasing its bottom one off the other end. }
    procedure ScrollInView(AControl: TControl);
    { LCL's name for UpdateScrollRange (forms.pp:202, TScrollingWinControl.UpdateScrollbars).
      Same job, and it stays a one-line forward rather than a rename so the existing name --
      which every call site and doc page in this repo uses -- keeps working. }
    procedure UpdateScrollbars;
    { The logical content extent (bounding box of the non-scrollbar children), valid
      after UpdateScrollRange. Exposed for tests. }
    property ContentWidth: Integer read FContentW;
    property ContentHeight: Integer read FContentH;
    property ScrollX: Integer read FScrollX;
    property ScrollY: Integer read FScrollY;
  published
    { Republished as TScrollBox does (forms.pp:257). It is declared in TControl's PROTECTED
      "optional properties" block (controls.pp:1580), so unlike most of the events this
      library republishes it was unreachable from CODE too, not merely absent from the
      Object Inspector -- the static Constraints values were the only size limits a host
      could express, and a limit that depends on the form ("never wider than half of it")
      had no expression at all. }
    property OnConstrainedResize;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ --- Pure, headless-tested scroll math ------------------------------------------- }

{ True when the content is taller/wider than the viewport on this axis, i.e. a
  scrollbar is needed. Both arguments in the SAME (logical) px units. }
function TyScrollNeeded(AContentExtent, AViewport: Integer): Boolean;

{ Clamp a scroll offset to [0, max], where max = content - viewport (never < 0). A
  content that fits the viewport pins the offset at 0. }
function TyClampScroll(APos, ARange, AViewport: Integer): Integer;

{ The scrollbar PageSize for this axis: the viewport length (proportional-thumb sizing
  keys off Max-Min plus PageSize). Never below 1 so the thumb math stays well-defined. }
function TyScrollThumbPage(AViewport, ARange: Integer): Integer;

{ The scroll RANGE (max offset) for this axis = content - viewport, floored at 0. The
  scrollbar Max is set to this. }
function TyScrollMax(AContentExtent, AViewport: Integer): Integer;

implementation

{ --- Pure functions -------------------------------------------------------------- }

function TyScrollNeeded(AContentExtent, AViewport: Integer): Boolean;
begin
  Result := AContentExtent > AViewport;
end;

function TyScrollMax(AContentExtent, AViewport: Integer): Integer;
begin
  Result := AContentExtent - AViewport;
  if Result < 0 then Result := 0;
end;

function TyClampScroll(APos, ARange, AViewport: Integer): Integer;
var
  MaxPos: Integer;
begin
  MaxPos := TyScrollMax(ARange, AViewport);
  Result := APos;
  if Result < 0 then Result := 0;
  if Result > MaxPos then Result := MaxPos;
end;

function TyScrollThumbPage(AViewport, ARange: Integer): Integer;
begin
  // The thumb should size proportionally to the visible fraction; PageSize = viewport.
  Result := AViewport;
  if Result < 1 then Result := 1;
end;

{ TTyScrollBox }

constructor TTyScrollBox.Create(AOwner: TComponent);
begin
  // NB: inherited Create (TTyPanel) sets Width/Height, which fires Resize ->
  // UpdateScrollRange -> EnsureBars. Fields are zero-initialized by the RTL before
  // that runs, so EnsureBars lazily creates the ONE bar pair and stores it; do NOT
  // re-nil the field references here (that would orphan those bars and let a later
  // Resize create a duplicate pair).
  inherited Create(AOwner);
  Width := 200;
  Height := 150;
end;

destructor TTyScrollBox.Destroy;
begin
  // FVScrollBar / FHScrollBar are owned by Self (Create(Self)) -> freed by TComponent.
  inherited Destroy;
end;

function TTyScrollBox.GetStyleTypeKey: string;
begin
  Result := 'TyScrollBox';
end;

function TTyScrollBox.ScrollbarThick: Integer;
begin
  Result := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyScrollBox.ContentHost: TWinControl;
begin
  if FContent <> nil then Result := FContent else Result := Self;
end;

function TTyScrollBox.LeadingInset: Integer;
begin
  if IsRightToLeft and (FVScrollBar <> nil) and FVScrollBar.Visible then
    Result := FVScrollBar.Width
  else
    Result := 0;
end;

procedure TTyScrollBox.InsertControl(AControl: TControl; Index: Integer);
begin
  inherited InsertControl(AControl, Index);
  { Claim the viewport here rather than in the viewport's SetParent: every path -- created in
    code, dropped in the designer, streamed from a .lfm -- goes through InsertControl, and this
    way the viewport unit needs no reference back to this one. }
  if AControl is TTyScrollContent then
  begin
    FContent := TTyScrollContent(AControl);
    UpdateScrollRange;
  end;
end;

function TTyScrollBox.IsContentChild(AControl: TControl): Boolean;
begin
  { Not a scrollbar, and not the viewport -- the viewport is CHROME from the box's point of
    view: its size comes from the box, so counting it as content would feed the layout back
    into itself. }
  Result := (AControl <> nil) and (AControl <> FVScrollBar) and (AControl <> FHScrollBar)
        and (AControl <> FContent);
end;

function TTyScrollBox.CountsInWidth(AControl: TControl): Boolean;
begin
  Result := IsContentChild(AControl)
        and not (AControl.Align in [alTop, alBottom, alClient]);
end;

function TTyScrollBox.CountsInHeight(AControl: TControl): Boolean;
begin
  Result := IsContentChild(AControl)
        and not (AControl.Align in [alLeft, alRight, alClient]);
end;

procedure TTyScrollBox.EnsureBars;
begin
  if FVScrollBar = nil then
  begin
    FVScrollBar := TTyScrollBar.Create(Self);
    FVScrollBar.Parent := Self;
    FVScrollBar.Kind := sbVertical;
    FVScrollBar.Align := alNone;   // manual dock: ScrollBy moves it, we re-place it
    // A standalone TTyScrollBar is focusable; the two bars a scroll box owns must not be —
    // they are chrome around the CONTENT, and a Tab that stopped on them would land the
    // user on a scrollbar instead of on the next control inside the box.
    FVScrollBar.TabStop := False;
    FVScrollBar.OnChange := @VScrollBarChange;
    // Embedded bar drives content scrolling: keep it instant (no thumb glide) so
    // scrolling never lags behind the wheel/keyboard.
    FVScrollBar.AnimationsEnabled := False;
    FVScrollBar.ControlStyle := FVScrollBar.ControlStyle + [csNoDesignVisible];
    FVScrollBar.Visible := False;
  end;
  if FHScrollBar = nil then
  begin
    FHScrollBar := TTyScrollBar.Create(Self);
    FHScrollBar.Parent := Self;
    FHScrollBar.Kind := sbHorizontal;
    FHScrollBar.Align := alNone;
    FHScrollBar.TabStop := False;   // embedded chrome, not a stop — see the vertical bar
    FHScrollBar.OnChange := @HScrollBarChange;
    FHScrollBar.AnimationsEnabled := False;
    FHScrollBar.ControlStyle := FHScrollBar.ControlStyle + [csNoDesignVisible];
    FHScrollBar.Visible := False;
  end;
end;

{ See the declaration for why this override exists at all. }
procedure TTyScrollBox.ScrollBy(DeltaX, DeltaY: Integer);
begin
  ScrollByDelta(-DeltaX, -DeltaY);
end;

procedure TTyScrollBox.UpdateScrollbars;
begin
  UpdateScrollRange;
end;

procedure TTyScrollBox.ScrollInView(AControl: TControl);
var
  R: TRect;
  P: TPoint;
  viewW, viewH, dx, dy: Integer;
begin
  if (AControl = nil) or (AControl.Parent = nil) then Exit;
  if not ContentHost.IsParentOf(AControl) then Exit;
  UpdateScrollRange;
  { The child's rect in the CONTENT HOST's coordinates -- the same space the offset is
    expressed in, so a plain delta is all that is needed. }
  P := AControl.ClientToParent(Point(0, 0), ContentHost);
  R := Rect(P.x, P.y, P.x + AControl.Width, P.y + AControl.Height);
  { The tests below are against the VIEWPORT, whose origin is 0 only when the content host is
    the viewport control (it carries the leading gutter in its own bounds). Without one, the
    children sit directly in the box and a mirrored box has pushed them past the bar, so take
    that back off first -- otherwise "is this child off the right edge" is asked a scrollbar's
    width too late and the last column never quite scrolls into view. }
  if FContent = nil then
    Types.OffsetRect(R, -LeadingInset, 0);

  viewW := ClientWidth;
  viewH := ClientHeight;
  dx := 0;
  dy := 0;
  { Past the far edge: pull it back by the overshoot. Before the near edge: push by the
    shortfall. The near-edge test runs SECOND so an oversized child ends up top/left-aligned
    rather than chasing its far edge out of view -- LCL resolves the same conflict the same
    way. }
  if R.Right > viewW then dx := R.Right - viewW;
  if R.Left - dx < 0 then dx := R.Left;
  if R.Bottom > viewH then dy := R.Bottom - viewH;
  if R.Top - dy < 0 then dy := R.Top;
  if (dx <> 0) or (dy <> 0) then
    ScrollByDelta(dx, dy);
end;

procedure TTyScrollBox.ScrollTo(AX, AY: Integer);
begin
  { Through ScrollByDelta, not ScrollContentTo: the delta path re-measures and clamps to
    the real scrollable range, and ScrollContentTo does not. Two entry points with two
    clamping rules is how a public ScrollTo ends up able to scroll past the content end. }
  ScrollByDelta(AX - FScrollX, AY - FScrollY);
end;

procedure TTyScrollBox.UpdateScrollRange;
var
  pass: Integer;
begin
  // Re-docking the bars from inside ScrollBy must not re-trigger a measure.
  if FInScrollBy or FInUpdate then Exit;
  if csDestroying in ComponentState then Exit;
  // Mid-stream the child set and the bounds are both half-read; Loaded re-runs this
  // once the .lfm is fully in.
  if csLoading in ComponentState then Exit;
  FInUpdate := True;
  try
    EnsureBars;
    // Showing/hiding a bar changes AdjustClientRect, so the align engine reflows every
    // ALIGNED child right there — which can change the content extent we just measured.
    // Re-measure until it settles (bounded: a pathological layout must not spin).
    pass := 0;
    repeat
      Inc(pass);
    until (not MeasureAndDock) or (pass >= 3);
  finally
    FInUpdate := False;
  end;
end;

{ One measure + dock pass. Returns True when it changed something the NEXT pass would
  measure differently (content extent or bar visibility), so the caller can settle. }
function TTyScrollBox.MeasureAndDock: Boolean;
var
  host: TWinControl;
  bw: Integer;
  i: Integer;
  child: TControl;
  minL, minT, maxR, maxB: Integer;
  haveChild: Boolean;
  viewW, viewH, thick: Integer;
  wantV, wantH: Boolean;
  vMax, hMax: Integer;
  oldW, oldH: Integer;
  oldV, oldH2: Boolean;
  lead: Integer;
begin
  thick := ScrollbarThick;
  oldW := FContentW;
  oldH := FContentH;
  oldV := FVScrollBar.Visible;
  oldH2 := FHScrollBar.Visible;

  // 1) Content extent in LOGICAL (un-scrolled) coordinates, measured from the viewport
  //    origin (0,0) out to the far edge of the children. A child's current (scrolled)
  //    Left/Top plus the current offset gives its logical position. Each axis only counts
  //    the children whose size on that axis is their own — see CountsInWidth/Height.
  maxR := 0; maxB := 0;
  host := ContentHost;
  for i := 0 to host.ControlCount - 1 do
  begin
    child := host.Controls[i];
    if not IsContentChild(child) then Continue;
    if CountsInWidth(child) and (child.Left + FScrollX + child.Width > maxR) then
      maxR := child.Left + FScrollX + child.Width;
    if CountsInHeight(child) and (child.Top + FScrollY + child.Height > maxB) then
      maxB := child.Top + FScrollY + child.Height;
  end;
  FContentW := maxR;   // never negative: maxR/maxB start at 0
  FContentH := maxB;

  // 2) Decide which bars are needed. Each bar, when shown, steals viewport from the
  //    OTHER axis, which can in turn force the other bar (classic mutual dependency).
  { The viewport is what is left INSIDE the frame, not the whole control. Measuring the scroll
    range against Width/Height put the maximum offset one border-width too far, so scrolling to
    the end laid the last row exactly on the bottom border line. }
  bw := FrameInset;
  viewW := Width - 2 * bw;
  viewH := Height - 2 * bw;
  if viewW < 0 then viewW := 0;
  if viewH < 0 then viewH := 0;
  wantV := TyScrollNeeded(FContentH, viewH);
  wantH := TyScrollNeeded(FContentW, viewW - Ord(wantV) * thick);
  wantV := TyScrollNeeded(FContentH, viewH - Ord(wantH) * thick);

  viewW := Width - 2 * bw - Ord(wantV) * thick;
  viewH := Height - 2 * bw - Ord(wantH) * thick;
  if viewW < 0 then viewW := 0;
  if viewH < 0 then viewH := 0;
  { LeadingInset cannot be used yet -- it reads FVScrollBar.Visible, and this pass is what
    DECIDES that. Same number, from the decision instead of from the outcome. }
  if IsRightToLeft and wantV then lead := thick else lead := 0;

  // 3) Clamp the offset to the (possibly reduced) viewport, moving content if needed.
  ScrollContentTo(TyClampScroll(FScrollX, FContentW, viewW),
                  TyClampScroll(FScrollY, FContentH, viewH));

  // 4) Dock + configure the vertical bar.
  if wantV then
  begin
    FVScrollBar.Controller := Self.Controller;
    { Keep the bars ABOVE the content. Both are created in the constructor, so they sit at the
      bottom of the child z-order and every control the app adds afterwards paints over them --
      a content child wider than the viewport buried the bar, leaving it visible only in the
      gaps between rows. Raising them here rather than at construction is deliberate: children
      stream in and get added after the fact, and this runs whenever the content changes. }
    FVScrollBar.BringToFront;
    { THE SIGNAL. A vertical bar on the left edge is what makes a window read as right-to-left
      before a single word is legible, which is why this one placement is the phase's headline
      even though the arithmetic around it is larger than phase 2's. }
    if lead > 0 then
      FVBarRect := Bounds(bw, bw, thick, viewH)
    else
      FVBarRect := Bounds(Width - thick - bw, bw, thick, viewH);
    FVScrollBar.BoundsRect := FVBarRect;
    vMax := TyScrollMax(FContentH, viewH);
    FSyncing := True;
    try
      FVScrollBar.Min := 0;
      FVScrollBar.Max := vMax;
      FVScrollBar.PageSize := TyScrollThumbPage(viewH, FContentH);
      FVScrollBar.Position := FScrollY;
    finally
      FSyncing := False;
    end;
    FVScrollBar.Visible := True;
  end
  else if FVScrollBar <> nil then
    FVScrollBar.Visible := False;

  // 5) Dock + configure the horizontal bar (stops short of the vbar corner).
  if wantH then
  begin
    FHScrollBar.Controller := Self.Controller;
    FHScrollBar.BringToFront;
    { Starts where the content starts, so it still stops short of the vertical bar's corner --
      the corner has simply changed ends. Its own MirrorHorizontal stays OFF: the children it
      scrolls are laid out left-to-right (see AdjustClientRect), so the content's origin IS
      the left edge, and a bar that put Position=Min on the right would point at the wrong end
      of its own document. The bar mirrors when the thing it scrolls does. }
    FHBarRect := Bounds(bw + lead, Height - thick - bw, viewW, thick);
    FHScrollBar.BoundsRect := FHBarRect;
    hMax := TyScrollMax(FContentW, viewW);
    FSyncing := True;
    try
      FHScrollBar.Min := 0;
      FHScrollBar.Max := hMax;
      FHScrollBar.PageSize := TyScrollThumbPage(viewW, FContentW);
      FHScrollBar.Position := FScrollX;
    finally
      FSyncing := False;
    end;
    FHScrollBar.Visible := True;
  end
  else if FHScrollBar <> nil then
    FHScrollBar.Visible := False;

  { The viewport IS the visible content area: inside the frame, minus whichever bars showed.
    Sizing it here rather than by Align keeps it in step with the very numbers the scroll range
    was computed from. }
  if FContent <> nil then
  begin
    FContent.SetBounds(bw + lead, bw, viewW, viewH);
    { The extent can change without the offset moving (a child grew, a row was added), and
      the viewport's layout area is derived from it -- so push here too, not only from
      ScrollContentTo. }
    FContent.SetScrollOrigin(Point(FScrollX, FScrollY), FContentW, FContentH);
  end;

  Result := (FContentW <> oldW) or (FContentH <> oldH)
         or (FVScrollBar.Visible <> oldV) or (FHScrollBar.Visible <> oldH2);
  // A bar that just appeared/vanished changed ClientRect, and LCL caches that. Drop the
  // cache so the next anchor/align pass reads the new viewport instead of the stale one.
  if (FVScrollBar.Visible <> oldV) or (FHScrollBar.Visible <> oldH2) then
    InvalidateClientRectCache(True);
end;

function TTyScrollBox.FrameInset: Integer;
var
  S: TTyStyleSet;
begin
  { The themed border, in device px. DrawFrame strokes it INSIDE the control's rect (Paint uses
    Rect(0,0,Width,Height)), so without reserving it the viewport reaches the border line and
    scrolled content is drawn straight over it -- the reported "content eats the container's
    bottom border". Only the border: the theme's 8px container padding is TTyPanel's client-rect
    semantics, and insetting by that too would silently re-lay-out every existing scroll box.
    Same call and same reasoning as TTyExPanel.AdjustClientRect, the one container in the
    library that already did this. }
  S := CurrentStyle;
  if TyBorderVisible(S) then
    Result := MulDiv(S.BorderWidth, Font.PixelsPerInch, 96)
  else
    Result := 0;
  if Result < 0 then Result := 0;
end;

function TTyScrollBox.GetClientRect: TRect;
begin
  { THIS DOES NOT MIRROR, and it is the one hook of the three that must not.

    The scoping document reads `Dec(Result.Right, ...)` as "vertical bar on the right,
    hard-coded" and asks for it to become `Inc(Result.Left, ...)` when mirrored. Doing that
    breaks the control outright: TControl.GetClientWidth is literally `ClientRect.Right`
    (lcl/include/control.inc:1910) -- a client rect that starts at Left=12 reports its width
    as the FULL width, so the anchor baseline LCL banks from ClientWidth (the thing the
    declaration comment above warns about) would exceed the layout rect by a scrollbar, and
    every ScrollBy would re-bank the difference. That is the recorded "each scroll costs an
    akRight child 12 px until it vanishes" failure, reintroduced by the change meant to
    mirror the box.

    So the split is: this hook and GetLogicalClientRect own the SIZE the gutters cost, which
    is side-independent, and AdjustClientRect owns WHERE the remaining area starts, which is
    the only thing mirroring actually moves. LeadingInset is that move. }
  Result := inherited GetClientRect;
  if (FVScrollBar <> nil) and FVScrollBar.Visible then
    Dec(Result.Right, FVScrollBar.Width);
  if (FHScrollBar <> nil) and FHScrollBar.Visible then
    Dec(Result.Bottom, FHScrollBar.Height);
  if Result.Right < Result.Left then Result.Right := Result.Left;
  if Result.Bottom < Result.Top then Result.Bottom := Result.Top;
end;

procedure TTyScrollBox.Paint;
begin
  RenderTo(Canvas, Rect(0, 0, Width, Height), Font.PixelsPerInch);
end;

function TTyScrollBox.GetLogicalClientRect: TRect;
var
  viewW, viewH, bw: Integer;
begin
  Result := inherited GetLogicalClientRect;   // = ClientRect, already minus the gutters
  viewW := Result.Right - Result.Left;
  viewH := Result.Bottom - Result.Top;
  // Grow to the content so overflowing aligned rows have somewhere to stack — but ONLY on
  // an axis that actually scrolls. The condition is not a nicety: an aligned child's size
  // comes FROM this rect and then feeds BACK into the content extent, so growing an axis
  // unconditionally latches it — a column of alTop rows would keep the full box width, sit
  // under the vertical bar forever, and never fall back to the viewport. (LCL's own
  // TScrollingWinControl.GetLogicalClientRect guards on ScrollBar.Visible for the same reason.)
  { Grow by the content PLUS everything AdjustClientRect is about to take back off both edges,
    so what the children actually get laid out in is exactly the content. Growing to the bare
    content would leave them a frame short of it and clip the last row by a border width.
    BorderWidth is in that sum because TTyPanel.AdjustClientRect now honours it -- leave it
    out and an 8px gutter would cost the last row 16px instead of moving it. }
  bw := 2 * (FrameInset + BorderWidth);
  if (FHScrollBar <> nil) and FHScrollBar.Visible and (FContentW > viewW) then
    Result.Right := Result.Left + FContentW + bw;
  if (FVScrollBar <> nil) and FVScrollBar.Visible and (FContentH > viewH) then
    Result.Bottom := Result.Top + FContentH + bw;
end;

procedure TTyScrollBox.AdjustClientRect(var ARect: TRect);
var
  bw: Integer;
begin
  inherited AdjustClientRect(ARect);
  // Keep the layout area inside the frame the control paints for itself.
  bw := FrameInset;
  if bw > 0 then
  begin
    Inc(ARect.Left, bw);
    Inc(ARect.Top, bw);
    Dec(ARect.Right, bw);
    Dec(ARect.Bottom, bw);
    if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
    if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
  end;
  { Size is GetLogicalClientRect's job; this only moves the ORIGIN -- twice, for two unrelated
    reasons that both land here.

    LeadingInset is the mirror: right-to-left the vertical bar sits on the LEFT, so the first
    column of content starts a bar-width in. It is added to both edges (a slide, not a
    stretch) precisely because the size was already settled by the other two hooks; adding it
    to Left alone would shrink the layout area a second time and hand every child a viewport
    a scrollbar too narrow.

    The scroll offset is the other, and it does NOT change sign when mirrored: the children
    inside the box are still laid out left-to-right (§6.3 item 1 -- LCL's align engine has no
    BiDi outside the ChildSizing table path, and diverging from it would misplace every
    ported .lfm), so the content still begins at the layout origin and still runs rightwards.
    Flipping the sign here would scroll away from the content on the first drag. }
  Inc(ARect.Left,  LeadingInset);
  Inc(ARect.Right, LeadingInset);
  Types.OffsetRect(ARect, -FScrollX, -FScrollY);
end;

procedure TTyScrollBox.Loaded;
begin
  inherited Loaded;
  // The .lfm streams the content children in AFTER the Width/Height writes that fired the
  // last Resize, so this is the first moment the real child set is measurable. Without it
  // the box relies on some later, incidental resize to ever notice its own content.
  UpdateScrollRange;
end;

procedure TTyScrollBox.ControlsAligned;
begin
  inherited ControlsAligned;
  // Re-entrant by nature: docking the bars below moves children, which asks the align
  // engine for another pass. UpdateScrollRange's own FInUpdate guard swallows those, and
  // its settle loop picks up whatever the reflow changed.
  UpdateScrollRange;
end;

procedure TTyScrollBox.ScrollByDelta(ADx, ADy: Integer);
var
  nx, ny: Integer;
begin
  // Re-measure first so the clamp below uses a FRESH range: an auto-pan tick may fire while the
  // content is reflowing (a live drag) without the caller having re-run UpdateScrollRange, and a
  // stale (too-large) bar Max would otherwise let us scroll past the real content end.
  UpdateScrollRange;
  // Target offset, clamped to the current per-axis scrollable range (the bar Max; 0 when that axis
  // has no visible bar).
  nx := FScrollX + ADx;
  ny := FScrollY + ADy;
  if (FHScrollBar = nil) or not FHScrollBar.Visible then nx := 0
  else if nx > FHScrollBar.Max then nx := FHScrollBar.Max;
  if (FVScrollBar = nil) or not FVScrollBar.Visible then ny := 0
  else if ny > FVScrollBar.Max then ny := FVScrollBar.Max;
  if nx < 0 then nx := 0;
  if ny < 0 then ny := 0;
  ScrollContentTo(nx, ny);
  // Keep the thumbs in sync without re-entering our own OnChange handlers.
  FSyncing := True;
  try
    if (FVScrollBar <> nil) and FVScrollBar.Visible then FVScrollBar.Position := FScrollY;
    if (FHScrollBar <> nil) and FHScrollBar.Visible then FHScrollBar.Position := FScrollX;
  finally
    FSyncing := False;
  end;
end;

procedure TTyScrollBox.ScrollContentTo(ANewX, ANewY: Integer);
var
  dx, dy: Integer;
begin
  if ANewX < 0 then ANewX := 0;
  if ANewY < 0 then ANewY := 0;
  dx := ANewX - FScrollX;
  dy := ANewY - FScrollY;
  if (dx = 0) and (dy = 0) then Exit;
  // Commit the offset BEFORE moving anything. ScrollBy ends in EnableAutoSizing, which can
  // realign the children on the spot; that realign reads AdjustClientRect, and if the offset
  // were still the old one it would place every ALIGNED child back where it was and quietly
  // eat the scroll. The offset is the single source of truth — ScrollBy just applies it.
  FScrollX := ANewX;
  FScrollY := ANewY;
  { Hand the viewport the new origin BEFORE anything moves. Its own layout hooks read it,
    and the ScrollBy below ends in an EnableAutoSizing that can realign its children on the
    spot -- with the old origin still in place that realign puts every ALIGNED child back
    where it was and eats the scroll. Same ordering rule as the offset commit above, one
    container down. }
  if FContent <> nil then
    FContent.SetScrollOrigin(Point(FScrollX, FScrollY), FContentW, FContentH);

  { ONE layout pass for the whole move. Without the outer Disable/EnableAutoSizing each of
    the three steps below (the child move, and the two bar re-docks) ends its own autosize
    cycle, so a single thumb-drag tick paid for several full realigns of every child -- and
    each realign re-entered UpdateScrollRange, which re-docked the bars, which asked for
    another realign. Nesting the lock collapses that to the single pass the move actually
    needs. }
  DisableAutoSizing{$IFDEF DebugDisableAutoSizing}('TTyScrollBox.ScrollContentTo'){$ENDIF};
  try
    // Move the child controls. ScrollBy moves EVERY child (incl. our two scrollbars),
    // so guard the range recompute and re-dock the bars right after.
    FInScrollBy := True;
    try
      { Scroll INSIDE the viewport when there is one: moving its children is what the viewport's
        window then clips. Scrolling the box itself would move the viewport, and the frame with
        it. }
      if FContent <> nil then
        FContent.ScrollBy(-dx, -dy)
      else
        { INHERITED: the child-mover, not our own view-scroll override -- which would call
          straight back into here. }
        inherited ScrollBy(-dx, -dy);
      { Put the bars back on their gutters -- ScrollBy shifted them off with everything else.
        Inside the FInScrollBy guard on purpose: the SetBounds is bookkeeping for a move we
        are still in the middle of, not a new fact about the content, so it must not kick off
        a fresh measure. }
      RedockBars;
    finally
      FInScrollBy := False;
    end;
  finally
    EnableAutoSizing{$IFDEF DebugDisableAutoSizing}('TTyScrollBox.ScrollContentTo'){$ENDIF};
  end;
  Invalidate;
end;

{ Restore both bars to the rect MeasureAndDock last decided on.

  Deliberately NOT a second copy of that arithmetic: see the FVBarRect declaration for what
  the second copy cost. When the bars are already there (the viewport case -- FContent.ScrollBy
  never touches them) every call here is a no-op that LCL's SetBounds drops on the floor. }
procedure TTyScrollBox.RedockBars;
begin
  if (FVScrollBar <> nil) and FVScrollBar.Visible and not IsRectEmpty(FVBarRect) then
    FVScrollBar.BoundsRect := FVBarRect;
  if (FHScrollBar <> nil) and FHScrollBar.Visible and not IsRectEmpty(FHBarRect) then
    FHScrollBar.BoundsRect := FHBarRect;
end;

procedure TTyScrollBox.VScrollBarChange(Sender: TObject);
begin
  if FSyncing then Exit;
  FSyncing := True;
  try
    ScrollContentTo(FScrollX, FVScrollBar.Position);
  finally
    FSyncing := False;
  end;
end;

procedure TTyScrollBox.HScrollBarChange(Sender: TObject);
begin
  if FSyncing then Exit;
  FSyncing := True;
  try
    ScrollContentTo(FHScrollBar.Position, FScrollY);
  finally
    FSyncing := False;
  end;
end;

function TTyScrollBox.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  step: Integer;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  // Wheel scrolls the vertical axis when it overflows, else the horizontal one.
  step := ScrollbarThick;   // one "line" ~ a scrollbar thickness of content
  if WheelDelta > 0 then step := -step;
  // ScrollByDelta re-measures, clamps to the live range and syncs the thumbs, so the wheel
  // can never park the content past its own end.
  if (FVScrollBar <> nil) and FVScrollBar.Visible then
  begin
    ScrollByDelta(0, step);
    Result := True;
  end
  else if (FHScrollBar <> nil) and FHScrollBar.Visible then
  begin
    ScrollByDelta(step, 0);
    Result := True;
  end
  else
    Result := False;
end;

procedure TTyScrollBox.Resize;
begin
  inherited Resize;
  UpdateScrollRange;
end;

end.
