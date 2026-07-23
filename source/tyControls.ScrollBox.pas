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
    scrolled. On a scrollbar change we compute the delta from the current offset and
    call inherited ScrollBy(-dx,-dy) to move the child controls, then re-dock the two
    scrollbars back to the right/bottom edge (ScrollBy moved them too) and commit the
    new offset. The content RANGE is the bounding box of the NON-scrollbar children in
    LOGICAL (un-scrolled) coordinates — each child's current position plus the current
    offset. }
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
    procedure EnsureBars;
    procedure VScrollBarChange(Sender: TObject);
    procedure HScrollBarChange(Sender: TObject);
    procedure ScrollContentTo(ANewX, ANewY: Integer);
    function ScrollbarThick: Integer;
  protected
    procedure Resize; override;
    { Nudge the scroll offset by (ADx, ADy), clamped to the current scrollable range (0 on an
      axis with no bar), and keep the bar thumbs in sync. For subclasses (e.g. TTyScrollPanel's
      edge auto-pan). Safe to call after the layout has settled (bars configured). }
    procedure ScrollByDelta(ADx, ADy: Integer);
    { A scrollbar is an internal child; keep it out of the range measurement and out of
      the streamed/designer child list. }
    function IsContentChild(AControl: TControl): Boolean;
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

procedure TTyScrollBox.EnsureBars;
begin
  if FVScrollBar = nil then
  begin
    FVScrollBar := TTyScrollBar.Create(Self);
    FVScrollBar.Parent := Self;
    FVScrollBar.Kind := sbVertical;
    FVScrollBar.Align := alNone;   // manual dock: ScrollBy moves it, we re-place it
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
    FHScrollBar.OnChange := @HScrollBarChange;
    FHScrollBar.AnimationsEnabled := False;
    FHScrollBar.ControlStyle := FHScrollBar.ControlStyle + [csNoDesignVisible];
    FHScrollBar.Visible := False;
  end;
end;

procedure TTyScrollBox.UpdateScrollRange;
var
  i: Integer;
  child: TControl;
  minL, minT, maxR, maxB: Integer;
  haveChild: Boolean;
  viewW, viewH, thick: Integer;
  wantV, wantH: Boolean;
  vMax, hMax: Integer;
begin
  if FInScrollBy then Exit;   // re-docking the bars must not re-trigger a measure
  EnsureBars;
  thick := ScrollbarThick;

  // 1) Content bounding box in LOGICAL (un-scrolled) coordinates. A child's current
  //    (scrolled) Left/Top plus the current offset gives its logical position; the
  //    box spans from the logical origin (0,0) out to the far edge of the children.
  haveChild := False;
  minL := 0; minT := 0; maxR := 0; maxB := 0;
  for i := 0 to ControlCount - 1 do
  begin
    child := Controls[i];
    if not IsContentChild(child) then Continue;
    if not haveChild then
    begin
      minL := child.Left + FScrollX;
      minT := child.Top + FScrollY;
      maxR := child.Left + FScrollX + child.Width;
      maxB := child.Top + FScrollY + child.Height;
      haveChild := True;
    end
    else
    begin
      if child.Left + FScrollX < minL then minL := child.Left + FScrollX;
      if child.Top + FScrollY < minT then minT := child.Top + FScrollY;
      if child.Left + FScrollX + child.Width > maxR then maxR := child.Left + FScrollX + child.Width;
      if child.Top + FScrollY + child.Height > maxB then maxB := child.Top + FScrollY + child.Height;
    end;
  end;
  // Extent measured from the viewport origin (0,0); a child straddling negative
  // logical space still contributes its far edge. Never negative.
  if not haveChild then
  begin
    FContentW := 0;
    FContentH := 0;
  end
  else
  begin
    FContentW := maxR;
    FContentH := maxB;
    if FContentW < 0 then FContentW := 0;
    if FContentH < 0 then FContentH := 0;
  end;

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
  // Move the child controls. ScrollBy moves EVERY child (incl. our two scrollbars),
  // so guard the range recompute and re-dock the bars right after.
  FInScrollBy := True;
  try
    ScrollBy(-dx, -dy);
  finally
    FInScrollBy := False;
  end;
  FScrollX := ANewX;
  FScrollY := ANewY;
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
  if (FVScrollBar <> nil) and FVScrollBar.Visible then
  begin
    if WheelDelta > 0 then
      ScrollContentTo(FScrollX, FScrollY - step)
    else
      ScrollContentTo(FScrollX, FScrollY + step);
    UpdateScrollRange;   // resync the bar position to the new offset
    Result := True;
  end
  else if (FHScrollBar <> nil) and FHScrollBar.Visible then
  begin
    if WheelDelta > 0 then
      ScrollContentTo(FScrollX - step, FScrollY)
    else
      ScrollContentTo(FScrollX + step, FScrollY);
    UpdateScrollRange;
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
