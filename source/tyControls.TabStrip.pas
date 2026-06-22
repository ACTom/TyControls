unit tyControls.TabStrip;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages, ExtCtrls,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.Animation, tyControls.Accel;

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
    FTabHeight: Integer;      // logical px, default 28
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
      HeaderRectShifted:  header rect translated by the current scroll offset. }
    function TyHeaderStripWidth: Integer;
    function TyMaxHeaderScroll: Integer;
    function TyTabScrollLeftRect: TRect;
    function TyTabScrollRightRect: TRect;
    function HeaderRectShifted(AIndex: Integer): TRect;
    procedure SetHeaderScroll(AValue: Integer);
    procedure ScrollTabIntoView(AIndex: Integer);

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
    property TabHeight: Integer read FTabHeight write SetTabHeight default 28;
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
  FTabHeight := 28;
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

{ Shared tab-header-band height: TabHeight logical px → device px at APPI. }
function TTyCustomTabStrip.TabHPx(APPI: Integer): Integer;
begin
  Result := MulDiv(FTabHeight, APPI, 96);
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
  Pad       := MulDiv(TyTabPad, APPI, 96);
  MinW      := MulDiv(TyTabMinWidth, APPI, 96);
  CloseSize := MulDiv(TyTabCloseSize, APPI, 96);
  Gap       := MulDiv(TyTabGap,  APPI, 96);
  Margin    := MulDiv(TyTabMargin,  APPI, 96);
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
  AffordanceW  := MulDiv(TyTabArrowBand, APPI, 96) * 2;
  FShowScrollAffordance := X > VisibleWidth;
  if FShowScrollAffordance then
  begin
    ArrowW := MulDiv(TyTabArrowBand, APPI, 96);
    FScrollLeftRect  := Rect(0, 0, ArrowW, TabH);
    FScrollRightRect := Rect(VisibleWidth - ArrowW, 0, VisibleWidth, TabH);
  end
  else
  begin
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
  AffordanceW  := MulDiv(TyTabArrowBand, Font.PixelsPerInch, 96) * 2;
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

{ Header rect translated left by the current scroll offset. }
function TTyCustomTabStrip.HeaderRectShifted(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then
    Exit(Rect(0, 0, 0, 0));
  Result := FHeaderRects[AIndex];
  OffsetRect(Result, -FHeaderScroll, 0);
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
    ArrowW   := MulDiv(TyTabArrowBand, Font.PixelsPerInch, 96);
    { The left arrow overlays the start of the strip, so the leftmost tab can
      legitimately sit at x=0 (scroll 0). Align "into view from the left" to the
      true left edge; reserve only the right arrow on the trailing side. }
    VisLeft  := 0;
    VisRight := Width - ArrowW;
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

{ Device-px drag threshold at APPI: 6 logical px scaled. At 96 PPI this is 6. }
function TTyCustomTabStrip.TyDragThresholdPx(APPI: Integer): Integer;
begin
  Result := MulDiv(6, APPI, 96);
  if Result < 1 then Result := 1;
end;

{ Resolve which collection index a drag at device-X should drop into, scanning
  the shifted header midpoints left-to-right. Returns the first index whose
  shifted midpoint lies strictly to the right of X; if X is past every midpoint
  it defaults to the last index. Result is clamped to [0, Count-1]. Pure: it
  rebuilds the (cached) layout for measurement but mutates no selection state. }
function TTyCustomTabStrip.TyDropIndexAt(X, APPI: Integer): Integer;
var
  I, Mid: Integer;
  HR: TRect;
begin
  if GetTabCount = 0 then Exit(0);
  RebuildLayout(APPI);
  Result := GetTabCount - 1; // default: past every midpoint -> last
  for I := 0 to GetTabCount - 1 do
  begin
    HR := FHeaderRects[I];
    OffsetRect(HR, -FHeaderScroll, 0); // shifted midpoint
    Mid := (HR.Left + HR.Right) div 2;
    if X < Mid then
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

procedure TTyCustomTabStrip.SetTabHeight(AValue: Integer);
begin
  if FTabHeight = AValue then Exit;
  FTabHeight := AValue;
  if FTabHeight < 1 then FTabHeight := 1;
  Invalidate;
end;

procedure TTyCustomTabStrip.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, TabStyle, ArrowStyle, CloseS, InactiveS, ActiveS: TTyStyleSet;
  R: TRect;
  W, H, TabH, I: Integer;
  HdrRect, CloseRect, TextRect, BandRect, SavedClip: TRect;
  TabStates: TTyStateSet;
  CloseHi: TTyFill;
  FadeEased: Single;
  disp: string;
  mp: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    W := R.Right;
    H := R.Bottom;
    P.BeginPaint(ACanvas, ARect, APPI);

    BoxStyle := CurrentStyle;
    TabH := TabHPx(APPI);

    { The header strip is only painted where tab headers land; the empty area to the
      right of the last tab would otherwise be a stale gap. On an image theme fill
      the whole strip with the form's photo first so that gap reads as the form's
      background (no-op off-image: the strip composites the parent as before). }
    FillSharpBackdrop(P, Rect(0, 0, W, TabH));

    { Draw content area frame below header strip.
      Overlap by 1px so the active tab can visually merge with the content panel. }
    DrawFrame(P, Rect(0, TabH - MulDiv(1, APPI, 96), W, H), BoxStyle);

    { Draw each tab header }
    RebuildLayout(APPI);

    { When overflowing, clip the header strip to the band between the two arrow
      affordances so shifted headers do not paint over the arrows or past the
      control. When it fits, clip to the full header band (offset is 0 anyway). }
    SavedClip := P.Bitmap.ClipRect;
    if FShowScrollAffordance then
      BandRect := Rect(FScrollLeftRect.Right, 0, FScrollRightRect.Left, TabH)
    else
      BandRect := Rect(0, 0, W, TabH);
    P.Bitmap.ClipRect := BandRect;

    for I := 0 to GetTabCount - 1 do
    begin
      HdrRect   := HeaderRectShifted(I);
      CloseRect := FCloseRects[I];
      if GetTabClosableAt(I) then
        OffsetRect(CloseRect, -FHeaderScroll, 0);

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

      { Draw caption centered in header (clipped to left of close glyph) }
      TextRect := HdrRect;
      if GetTabClosableAt(I) then
        TextRect.Right := CloseRect.Left;
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
      P.DrawGlyph(FScrollLeftRect,  tgArrowLeft,  ArrowStyle.TextColor, 2);
      P.DrawGlyph(FScrollRightRect, tgArrowRight, ArrowStyle.TextColor, 2);
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
          CloseRect := FCloseRects[I];
          OffsetRect(CloseRect, -FHeaderScroll, 0);
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
            CloseRect := FCloseRects[I];
            OffsetRect(CloseRect, -FHeaderScroll, 0);
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
  VK_LEFT/VK_RIGHT step prev/next clamped (legacy). Every handled key is
  consumed (Key := 0). TabIndex := routes through SetTabIndex, which clamps,
  shows the page, scrolls it into view, and fires OnChange. }
procedure TTyCustomTabStrip.KeyDown(var Key: Word; Shift: TShiftState);
var NewIndex, Cnt: Integer;
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
  case Key of
    VK_HOME:  begin TabIndex := 0; Key := 0; end;
    VK_END:   begin TabIndex := Cnt - 1; Key := 0; end;
    VK_RIGHT:
      begin
        NewIndex := FTabIndex + 1;
        if NewIndex > Cnt - 1 then NewIndex := Cnt - 1;
        TabIndex := NewIndex; Key := 0;
      end;
    VK_LEFT:
      begin
        NewIndex := FTabIndex - 1;
        if NewIndex < 0 then NewIndex := 0;
        TabIndex := NewIndex; Key := 0;
      end;
  end;
end;

end.
