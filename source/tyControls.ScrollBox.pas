unit tyControls.ScrollBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Panel, tyControls.ScrollBar;

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
    then re-dock the two scrollbars back to the right/bottom edge (ScrollBy moved them
    too). The content RANGE is the bounding box of the NON-scrollbar children in LOGICAL
    (un-scrolled) coordinates — each child's current position plus the current offset.

    Being a CONTAINER is the other half of the job, and it is all in AdjustClientRect
    (see there): the LCL alignment engine has to know that a visible bar owns a gutter,
    and that the layout origin is the SCROLLED origin. Without the first, an aligned
    child is sized over the bar; without the second, every realign undoes the scroll for
    aligned children. Re-measuring is likewise automatic — Resize, Loaded (the .lfm's
    children arrive after the last Resize) and ControlsAligned (any child added, removed,
    moved or resized) all funnel into UpdateScrollRange. }
  TTyScrollBox = class(TTyPanel)
  private
    FVScrollBar: TTyScrollBar;   // nil until first needed
    FHScrollBar: TTyScrollBar;   // nil until first needed
    FScrollX: Integer;           // >= 0 : logical px the content is scrolled left
    FScrollY: Integer;           // >= 0 : logical px the content is scrolled up
    FContentW: Integer;          // logical content extent (bounding box of children)
    FContentH: Integer;
    FSyncing: Boolean;           // reentrancy guard while we drive the bars
    FInScrollBy: Boolean;        // guard so re-docking the bars is ignored by range calc
    FInUpdate: Boolean;          // reentrancy guard for UpdateScrollRange (see there)
    procedure EnsureBars;
    procedure VScrollBarChange(Sender: TObject);
    procedure HScrollBarChange(Sender: TObject);
    procedure ScrollContentTo(ANewX, ANewY: Integer);
    function ScrollbarThick: Integer;
    function MeasureAndDock: Boolean;
  protected
    procedure Resize; override;
    procedure Loaded; override;
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
    procedure ScrollByDelta(ADx, ADy: Integer);
    { A scrollbar is an internal child; keep it out of the range measurement and out of
      the streamed/designer child list. }
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
    { The logical content extent (bounding box of the non-scrollbar children), valid
      after UpdateScrollRange. Exposed for tests. }
    property ContentWidth: Integer read FContentW;
    property ContentHeight: Integer read FContentH;
    property ScrollX: Integer read FScrollX;
    property ScrollY: Integer read FScrollY;
  published
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

function TTyScrollBox.IsContentChild(AControl: TControl): Boolean;
begin
  // Everything that is NOT one of our two embedded scrollbars is content.
  Result := (AControl <> nil) and (AControl <> FVScrollBar) and (AControl <> FHScrollBar);
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
  i: Integer;
  child: TControl;
  minL, minT, maxR, maxB: Integer;
  haveChild: Boolean;
  viewW, viewH, thick: Integer;
  wantV, wantH: Boolean;
  vMax, hMax: Integer;
  oldW, oldH: Integer;
  oldV, oldH2: Boolean;
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
  for i := 0 to ControlCount - 1 do
  begin
    child := Controls[i];
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
  viewW := Width;
  viewH := Height;
  wantV := TyScrollNeeded(FContentH, viewH);
  wantH := TyScrollNeeded(FContentW, viewW - Ord(wantV) * thick);
  wantV := TyScrollNeeded(FContentH, viewH - Ord(wantH) * thick);

  viewW := Width - Ord(wantV) * thick;
  viewH := Height - Ord(wantH) * thick;

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
    FVScrollBar.SetBounds(Width - thick, 0, thick, viewH);
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
    FHScrollBar.SetBounds(0, Height - thick, viewW, thick);
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

  Result := (FContentW <> oldW) or (FContentH <> oldH)
         or (FVScrollBar.Visible <> oldV) or (FHScrollBar.Visible <> oldH2);
  // A bar that just appeared/vanished changed ClientRect, and LCL caches that. Drop the
  // cache so the next anchor/align pass reads the new viewport instead of the stale one.
  if (FVScrollBar.Visible <> oldV) or (FHScrollBar.Visible <> oldH2) then
    InvalidateClientRectCache(True);
end;

function TTyScrollBox.GetClientRect: TRect;
begin
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
  viewW, viewH: Integer;
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
  if (FHScrollBar <> nil) and FHScrollBar.Visible and (FContentW > viewW) then
    Result.Right := Result.Left + FContentW;
  if (FVScrollBar <> nil) and FVScrollBar.Visible and (FContentH > viewH) then
    Result.Bottom := Result.Top + FContentH;
end;

procedure TTyScrollBox.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  // Size is GetLogicalClientRect's job; this only moves the origin to the scrolled origin.
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
  // Move the child controls. ScrollBy moves EVERY child (incl. our two scrollbars),
  // so guard the range recompute and re-dock the bars right after.
  FInScrollBy := True;
  try
    ScrollBy(-dx, -dy);
  finally
    FInScrollBy := False;
  end;
  // Re-dock the bars to the edges (ScrollBy shifted them off): vbar on the right,
  // hbar on the bottom. Bounds/PageSize/Max stay as UpdateScrollRange set them.
  if (FVScrollBar <> nil) and FVScrollBar.Visible then
    FVScrollBar.SetBounds(Width - FVScrollBar.Width, 0,
      FVScrollBar.Width, FVScrollBar.Height);
  if (FHScrollBar <> nil) and FHScrollBar.Visible then
    FHScrollBar.SetBounds(0, Height - FHScrollBar.Height,
      FHScrollBar.Width, FHScrollBar.Height);
  Invalidate;
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
