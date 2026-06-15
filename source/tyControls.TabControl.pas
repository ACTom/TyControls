unit tyControls.TabControl;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.Panel;

type
  TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer;
    var AllowClose: Boolean) of object;

  TTyTabControl = class;

  { Streamable backing item for one tab page. Caption is published so it
    survives LFM streaming; the hosting TTyPanel is exposed read-only as Page. }
  TTyTabItem = class(TCollectionItem)
  private
    FCaption: string;
    FPage: TTyPanel;
    procedure SetCaption(const AValue: string);
  protected
    function GetDisplayName: string; override;
  public
    { Copy the streamable state (Caption). The hosting page is created by the
      destination collection's TabItemAdded, so it is intentionally NOT copied
      from the source item. Without this override, Collection.Assign raises
      "Cannot assign a TTyTabItem to a TTyTabItem". }
    procedure Assign(Source: TPersistent); override;
    property Page: TTyPanel read FPage;
  published
    property Caption: string read FCaption write SetCaption;
  end;

  { Owned collection of TTyTabItem. Routes add/delete/update notifications to
    the owning TTyTabControl so the parallel page/caption arrays stay in sync. }
  TTyTabCollection = class(TOwnedCollection)
  private
    FTabControl: TTyTabControl;
    function GetItem(AIndex: Integer): TTyTabItem;
    procedure SetItem(AIndex: Integer; const AValue: TTyTabItem);
  protected
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(ATabControl: TTyTabControl);
    function Add: TTyTabItem;
    property Items[AIndex: Integer]: TTyTabItem read GetItem write SetItem; default;
  end;

  TTyTabControl = class(TTyCustomControl)
  private
    FCaptions: TStringList;   // parallel arrays
    FPages:    array of TTyPanel;
    FTabs:     TTyTabCollection;
    FUpdatingTabs: Boolean;   // guards re-entrant collection<->array sync
    FTabIndex: Integer;       // -1 = none
    FPendingTabIndex: Integer; // TabIndex captured during csLoading (-1 = none)
    FTabHeight: Integer;      // logical px, default 28
    FHoverTab: Integer;       // -1 = none
    FHoverClose: Integer;     // tab index whose close (x) is hovered; -1 = none
    FOnChange: TNotifyEvent;
    FDestroying: Boolean;
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

    procedure SetTabs(AValue: TTyTabCollection);
    procedure TabItemAdded(AItem: TTyTabItem);
    procedure TabItemDeleting(AItem: TTyTabItem);
    procedure TabsChanged(AItem: TTyTabItem);
    function  IndexOfPage(APage: TTyPanel): Integer;
    procedure RemovePageInternal(AIndex: Integer; AFree: Boolean);
    procedure SetTabIndex(AValue: Integer);
    procedure SetTabHeight(AValue: Integer);
    procedure SetTabsClosable(AValue: Boolean);
    procedure RebuildLayout(APPI: Integer);
    procedure DoCloseTab(AIndex: Integer);
    function  TabHPx(APPI: Integer): Integer;
    function  GetPage(AIndex: Integer): TTyPanel;
    function  TabCaptionWidth(const ACaption: string;
                              const AStyle: TTyStyleSet; APPI: Integer): Integer;
    procedure ShowOnlyPage(AIndex: Integer);
  protected
    { Header overflow scroll. FHeaderScroll is the device-px amount the header
      strip is shifted left (>=0). FShowScrollAffordance and the two arrow rects
      are recomputed at the end of RebuildLayout. Kept protected so white-box
      tests can read them. }
    FHeaderScroll: Integer;
    FShowScrollAffordance: Boolean;
    FScrollLeftRect:  TRect;
    FScrollRightRect: TRect;
    function GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
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
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function AddTab(const ACaption: string): TTyPanel;
    procedure RemoveTab(AIndex: Integer);
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

    property Pages[AIndex: Integer]: TTyPanel read GetPage;
  published
    property Tabs: TTyTabCollection read FTabs write SetTabs;
    { Published so the active selection round-trips through LFM streaming. A
      value written during csLoading is captured (FPendingTabIndex) and applied
      in Loaded; default -1 lets the RTTI default suppress writing -1. }
    property TabIndex: Integer read FTabIndex write SetTabIndex default -1;
    property TabHeight: Integer read FTabHeight write SetTabHeight default 28;
    property TabsClosable: Boolean read FTabsClosable write SetTabsClosable default False;
    property OnTabClose: TTyTabCloseEvent read FOnTabClose write FOnTabClose;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyTabItem }

procedure TTyTabItem.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

function TTyTabItem.GetDisplayName: string;
begin
  if FCaption <> '' then
    Result := FCaption
  else
    Result := inherited GetDisplayName;
end;

procedure TTyTabItem.Assign(Source: TPersistent);
begin
  if Source is TTyTabItem then
    Caption := TTyTabItem(Source).Caption  // setter -> Update -> TabsChanged sync
  else
    inherited Assign(Source);
end;

{ TTyTabCollection }

constructor TTyTabCollection.Create(ATabControl: TTyTabControl);
begin
  inherited Create(ATabControl, TTyTabItem);
  FTabControl := ATabControl;
end;

function TTyTabCollection.GetItem(AIndex: Integer): TTyTabItem;
begin
  Result := TTyTabItem(inherited Items[AIndex]);
end;

procedure TTyTabCollection.SetItem(AIndex: Integer; const AValue: TTyTabItem);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyTabCollection.Add: TTyTabItem;
begin
  Result := TTyTabItem(inherited Add);
end;

procedure TTyTabCollection.Notify(Item: TCollectionItem;
  Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  if FTabControl = nil then Exit;
  case Action of
    cnAdded:
      FTabControl.TabItemAdded(TTyTabItem(Item));
    cnDeleting, cnExtracting:
      FTabControl.TabItemDeleting(TTyTabItem(Item));
  end;
end;

procedure TTyTabCollection.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if FTabControl <> nil then
    FTabControl.TabsChanged(TTyTabItem(Item));
end;

{ TTyTabControl }

constructor TTyTabControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaptions := TStringList.Create;
  FTabs     := TTyTabCollection.Create(Self);
  FTabIndex  := -1;
  FPendingTabIndex := -1;
  FTabHeight := 28;
  FHoverTab  := -1;
  FHoverClose := -1;
  FHeaderScroll := 0;
  FDragTab   := -1;
  FDragging  := False;
  FTabsClosable := False;
  TabStop    := True;
  Width      := 300;
  Height     := 200;
end;

destructor TTyTabControl.Destroy;
begin
  FDestroying := True;
  { FDestroying is set so the collection's Notify is inert while it tears down. }
  FTabs.Free;
  FCaptions.Free;
  { Pages are owned components (Owner=Self) so freed by TComponent.Destroy }
  inherited Destroy;
end;

function TTyTabControl.GetStyleTypeKey: string;
begin
  Result := 'TyTabControl';
end;

{ When the TabControl's Controller changes, propagate it to all existing pages
  so they render with the same style controller rather than the default one. }
procedure TTyTabControl.SetController(AValue: TTyStyleController);
var
  I: Integer;
begin
  inherited SetController(AValue);
  for I := 0 to High(FPages) do
    if FPages[I] <> nil then
      FPages[I].Controller := AValue;
end;

{ Shared tab-header-band height: TabHeight logical px → device px at APPI. }
function TTyTabControl.TabHPx(APPI: Integer): Integer;
begin
  Result := MulDiv(FTabHeight, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyTabControl.GetPage(AIndex: Integer): TTyPanel;
begin
  if (AIndex < 0) or (AIndex >= Length(FPages)) then
    Result := nil
  else
    Result := FPages[AIndex];
end;

function TTyTabControl.TabCount: Integer;
begin
  Result := FCaptions.Count;
end;

function TTyTabControl.TabCaption(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= FCaptions.Count) then
    Result := ''
  else
    Result := FCaptions[AIndex];
end;

{ Measure the rendered caption width using a scratch TBitmap canvas so CJK and
  variable-width fonts are handled correctly (same pattern as TTyGroupBox). }
function TTyTabControl.TabCaptionWidth(const ACaption: string;
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

procedure TTyTabControl.SetTabsClosable(AValue: Boolean);
begin
  if FTabsClosable = AValue then Exit;
  FTabsClosable := AValue;
  Invalidate;
end;

{ Single-pass cached layout. Builds FHeaderRects/FCloseRects for all tabs.
  Geometry: device px, (0,0)-local. Headers laid left-to-right;
  width = text width + 2×Scale(12), minimum Scale(48). When closable, a
  close-glyph slot is reserved on the right of each header. }
procedure TTyTabControl.RebuildLayout(APPI: Integer);
var
  TabH, Pad, MinW, CloseSize, Gap, CloseSlot, Margin: Integer;
  TabStyle: TTyStyleSet;
  I, X, TW, HW, Cy: Integer;
  VisibleWidth, AffordanceW, ArrowW, MaxScroll: Integer;
begin
  SetLength(FHeaderRects, FCaptions.Count);
  SetLength(FCloseRects, FCaptions.Count);

  TabH      := TabHPx(APPI);
  Pad       := MulDiv(12, APPI, 96);
  MinW      := MulDiv(48, APPI, 96);
  CloseSize := MulDiv(14, APPI, 96);
  Gap       := MulDiv(6,  APPI, 96);
  Margin    := MulDiv(6,  APPI, 96);
  CloseSlot := CloseSize + Gap;

  TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);

  X := 0;
  for I := 0 to FCaptions.Count - 1 do
  begin
    TW := TabCaptionWidth(FCaptions[I], TabStyle, APPI) + 2 * Pad;
    if FTabsClosable then
    begin
      Inc(TW, CloseSlot);
      if TW < (MinW + CloseSlot) then TW := MinW + CloseSlot;
    end
    else
      if TW < MinW then TW := MinW;

    HW := TW;
    FHeaderRects[I] := Rect(X, 0, X + HW, TabH);

    if FTabsClosable then
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
  AffordanceW  := MulDiv(16, APPI, 96) * 2;
  FShowScrollAffordance := X > VisibleWidth;
  if FShowScrollAffordance then
  begin
    ArrowW := MulDiv(16, APPI, 96);
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

function TTyTabControl.TyTabHeaderRect(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then
    Result := Rect(0, 0, 0, 0)
  else
    Result := FHeaderRects[AIndex];
end;

function TTyTabControl.TyTabCloseRect(AIndex: Integer): TRect;
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
function TTyTabControl.TyHeaderStripWidth: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  if Length(FHeaderRects) = 0 then
    Result := 0
  else
    Result := FHeaderRects[High(FHeaderRects)].Right;
end;

{ Largest valid scroll: the overshoot of the strip past the visible width minus
  the reserved arrow band. 0 when the strip fits. Mirrors RebuildLayout's clamp. }
function TTyTabControl.TyMaxHeaderScroll: Integer;
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
  AffordanceW  := MulDiv(16, Font.PixelsPerInch, 96) * 2;
  Result := StripW - (VisibleWidth - AffordanceW);
  if Result < 0 then Result := 0;
end;

function TTyTabControl.TyTabScrollLeftRect: TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  Result := FScrollLeftRect;
end;

function TTyTabControl.TyTabScrollRightRect: TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  Result := FScrollRightRect;
end;

{ Header rect translated left by the current scroll offset. }
function TTyTabControl.HeaderRectShifted(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then
    Exit(Rect(0, 0, 0, 0));
  Result := FHeaderRects[AIndex];
  OffsetRect(Result, -FHeaderScroll, 0);
end;

{ Clamp the requested scroll into [0, TyMaxHeaderScroll] and repaint. }
procedure TTyTabControl.SetHeaderScroll(AValue: Integer);
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
procedure TTyTabControl.ScrollTabIntoView(AIndex: Integer);
var
  ArrowW, VisLeft, VisRight, L, R, Want: Integer;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then Exit;

  if FShowScrollAffordance then
  begin
    ArrowW   := MulDiv(16, Font.PixelsPerInch, 96);
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
function TTyTabControl.TyDragThresholdPx(APPI: Integer): Integer;
begin
  Result := MulDiv(6, APPI, 96);
  if Result < 1 then Result := 1;
end;

{ Resolve which collection index a drag at device-X should drop into, scanning
  the shifted header midpoints left-to-right. Returns the first index whose
  shifted midpoint lies strictly to the right of X; if X is past every midpoint
  it defaults to the last index. Result is clamped to [0, Count-1]. Pure: it
  rebuilds the (cached) layout for measurement but mutates no selection state. }
function TTyTabControl.TyDropIndexAt(X, APPI: Integer): Integer;
var
  I, Mid: Integer;
  HR: TRect;
begin
  if FCaptions.Count = 0 then Exit(0);
  RebuildLayout(APPI);
  Result := FCaptions.Count - 1; // default: past every midpoint -> last
  for I := 0 to FCaptions.Count - 1 do
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
  if Result > FCaptions.Count - 1 then Result := FCaptions.Count - 1;
end;

procedure TTyTabControl.DoCloseTab(AIndex: Integer);
var
  AllowClose: Boolean;
begin
  if (AIndex < 0) or (AIndex >= FCaptions.Count) then Exit;
  AllowClose := True;
  if Assigned(FOnTabClose) then
    FOnTabClose(Self, AIndex, AllowClose);
  if AllowClose then
    RemoveTab(AIndex);
end;

procedure TTyTabControl.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Top, TabHPx(Font.PixelsPerInch));
end;

{ Show only the page at AIndex (or none when AIndex=-1). }
procedure TTyTabControl.ShowOnlyPage(AIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to Length(FPages) - 1 do
    FPages[I].Visible := (I = AIndex);
end;

procedure TTyTabControl.SetTabIndex(AValue: Integer);
var
  Clamped: Integer;
begin
  { During csLoading the pages do not exist yet, so clamping against the empty
    page list would lose a streamed selection. Capture it and apply in Loaded. }
  if csLoading in ComponentState then
  begin
    FPendingTabIndex := AValue;
    Exit;
  end;
  if AValue < -1 then
    Clamped := -1
  else if AValue >= FCaptions.Count then
    Clamped := FCaptions.Count - 1
  else
    Clamped := AValue;
  if Clamped = FTabIndex then Exit;
  FTabIndex := Clamped;
  ShowOnlyPage(FTabIndex);
  if FTabIndex >= 0 then
    ScrollTabIntoView(FTabIndex);
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTabControl.SetTabHeight(AValue: Integer);
begin
  if FTabHeight = AValue then Exit;
  FTabHeight := AValue;
  if FTabHeight < 1 then FTabHeight := 1;
  Invalidate;
end;

{ Public convenience: add a tab through the collection (so the page/caption
  arrays stay in sync) and return its hosting page. The collection's Add fires
  TabItemAdded which creates the page; setting Caption then syncs FCaptions. }
function TTyTabControl.AddTab(const ACaption: string): TTyPanel;
var
  Item: TTyTabItem;
begin
  FUpdatingTabs := True;
  try
    Item := FTabs.Add;          // -> TabItemAdded creates page + caption slot
    Item.Caption := ACaption;   // -> TabsChanged re-syncs FCaptions
  finally
    FUpdatingTabs := False;
  end;
  Result := Item.Page;
end;

procedure TTyTabControl.SetTabs(AValue: TTyTabCollection);
begin
  FTabs.Assign(AValue);
end;

{ Create the hosting page for a freshly-added collection item and wire it into
  the parallel arrays. During csLoading we must NOT create the page: the pages
  are owned child components and are streamed in their own right as nested
  `object TTyPanel` blocks, so creating one here would double them. Instead we
  defer all page wiring (and FCaptions/FTabIndex reconciliation) to Loaded,
  which pairs the streamed child panels back to the loaded items. }
procedure TTyTabControl.TabItemAdded(AItem: TTyTabItem);
var
  Page: TTyPanel;
  IsFirst: Boolean;
begin
  if AItem.FPage <> nil then Exit; // already wired (defensive)
  if csLoading in ComponentState then Exit; // page+sync deferred to Loaded

  IsFirst := (FCaptions.Count = 0);
  FCaptions.Add(AItem.Caption);

  Page := TTyPanel.Create(Self);
  Page.Parent := Self;
  Page.Align  := alClient;
  Page.Visible := False;
  { Propagate controller so the page renders with the same style as the tab. }
  Page.Controller := Self.Controller;
  AItem.FPage := Page;

  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := Page;

  if IsFirst then
  begin
    { Auto-select: bypass setter's clamping by setting FTabIndex directly,
      then manually show the first page and fire nothing (first add, no real
      "change" from a previous selection). }
    FTabIndex := 0;
    Page.Visible := True;
    Invalidate;
  end;
end;

{ A collection item is being deleted/extracted: remove its page (find it via
  the page object so we are robust to reordering). FUpdatingTabs marks that the
  removal originates from the collection so RemovePageInternal does not try to
  delete the item again. }
procedure TTyTabControl.TabItemDeleting(AItem: TTyTabItem);
var
  Idx: Integer;
  SavedUpdating: Boolean;
begin
  if FDestroying then Exit;
  if AItem.FPage = nil then Exit;
  Idx := IndexOfPage(AItem.FPage);
  if Idx < 0 then Exit;
  AItem.FPage := nil;
  SavedUpdating := FUpdatingTabs;
  FUpdatingTabs := True;
  try
    RemovePageInternal(Idx, True);
  finally
    FUpdatingTabs := SavedUpdating;
  end;
end;

{ An item changed: re-sync the parallel arrays to the current item order. A
  plain Caption edit (Changed(False) -> Update(Self)) leaves the order intact,
  but a reorder (TCollectionItem.SetIndex -> Changed(True) -> Update(nil)) moves
  the item within the collection without touching FPages/FCaptions, so we rebuild
  both arrays from the collection in its current order, reading each item's
  hosting page (FPage) and Caption.

  The active selection follows the page OBJECT, not the index: we snapshot the
  active page before the rebuild and recompute FTabIndex to point at wherever
  that same page now lives. OnChange is fired only if the active page object
  actually changed (mirroring RemovePageInternal). }
procedure TTyTabControl.TabsChanged(AItem: TTyTabItem);
var
  I: Integer;
  OldActive, NewActive: TTyPanel;
  CanRebuild: Boolean;
begin
  if FDestroying then Exit;
  if csLoading in ComponentState then Exit;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    OldActive := FPages[FTabIndex]
  else
    OldActive := nil;

  { Only rebuild the page array when the collection is fully wired to pages
    (every item has a live FPage and the counts line up). This holds for normal
    caption edits and reorders; it skips any transient mid-mutation state. }
  CanRebuild := (FTabs.Count = Length(FPages));
  if CanRebuild then
    for I := 0 to FTabs.Count - 1 do
      if FTabs.Items[I].FPage = nil then
      begin
        CanRebuild := False;
        Break;
      end;

  if CanRebuild then
  begin
    for I := 0 to FTabs.Count - 1 do
    begin
      FPages[I] := FTabs.Items[I].FPage;
      FCaptions[I] := FTabs.Items[I].Caption;
    end;
    { Recompute FTabIndex so it still points at the same active page object. }
    if OldActive <> nil then
    begin
      FTabIndex := IndexOfPage(OldActive);
      if FTabIndex < 0 then
        FTabIndex := -1;
    end;
    ShowOnlyPage(FTabIndex);
  end
  else
    { Fallback: only the overlapping caption slots are safe to touch. }
    for I := 0 to FTabs.Count - 1 do
      if I < FCaptions.Count then
        FCaptions[I] := FTabs.Items[I].Caption;

  Invalidate;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    NewActive := FPages[FTabIndex]
  else
    NewActive := nil;

  if (NewActive <> OldActive) and Assigned(FOnChange) then
    FOnChange(Self);
end;

function TTyTabControl.IndexOfPage(APage: TTyPanel): Integer;
var I: Integer;
begin
  Result := -1;
  for I := 0 to High(FPages) do
    if FPages[I] = APage then
      Exit(I);
end;

procedure TTyTabControl.RemovePageInternal(AIndex: Integer; AFree: Boolean);
var
  OldActive, NewActive, Page: TTyPanel;
  J, ItemIdx: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FPages)) then Exit;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    OldActive := FPages[FTabIndex]
  else
    OldActive := nil;

  Page := FPages[AIndex];

  { Keep the backing collection in sync when the removal originated outside it
    (RemoveTab/close-glyph/external page free). FUpdatingTabs is set when the
    removal already came from the collection, so we skip to avoid recursion. }
  if (not FUpdatingTabs) and (FTabs <> nil) and (not FDestroying) then
  begin
    ItemIdx := -1;
    for J := 0 to FTabs.Count - 1 do
      if FTabs.Items[J].FPage = Page then
      begin
        ItemIdx := J;
        Break;
      end;
    if ItemIdx >= 0 then
    begin
      FUpdatingTabs := True;
      try
        FTabs.Items[ItemIdx].FPage := nil; // make TabItemDeleting a no-op
        FTabs.Delete(ItemIdx);
      finally
        FUpdatingTabs := False;
      end;
    end;
  end;

  FCaptions.Delete(AIndex);
  for J := AIndex to High(FPages) - 1 do
    FPages[J] := FPages[J + 1];
  SetLength(FPages, Length(FPages) - 1);

  if Length(FPages) = 0 then
    FTabIndex := -1
  else if AIndex < FTabIndex then
    Dec(FTabIndex)
  else if AIndex = FTabIndex then
  begin
    if FTabIndex > High(FPages) then
      FTabIndex := High(FPages);
  end;

  if AFree and (Page <> nil) then
    Page.Free;

  ShowOnlyPage(FTabIndex);
  Invalidate;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    NewActive := FPages[FTabIndex]
  else
    NewActive := nil;

  if (NewActive <> OldActive) and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTabControl.RemoveTab(AIndex: Integer);
begin
  RemovePageInternal(AIndex, True);
end;

procedure TTyTabControl.Notification(AComponent: TComponent; Operation: TOperation);
var
  Idx: Integer;
begin
  inherited Notification(AComponent, Operation);
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyPanel) then
  begin
    Idx := IndexOfPage(TTyPanel(AComponent));
    if Idx >= 0 then
      { External free of a hosting page: LCL is already freeing the panel, so we
        MUST pass AFree=False (re-freeing it would be a double-free). We also do
        NOT pre-set FUpdatingTabs here: leaving it False lets RemovePageInternal
        locate and delete the owning TTyTabItem in lockstep (it nils the item's
        FPage first so the resulting TabItemDeleting is an inert no-op rather than
        a second RemovePageInternal/Page.Free). Net effect: caption + item + page
        all compact exactly once and the page is never re-freed. }
      RemovePageInternal(Idx, False);
  end;
end;

{ Reconcile streaming results. TabItemAdded was suppressed during csLoading, so
  the loaded Tabs collection has captions but no pages, FPages/FCaptions are
  empty, and the pages exist only as the streamed child TTyPanel controls. Here
  we pair each loaded item with one streamed page (in child-control order),
  rebuild the parallel arrays, and re-establish the selection so the displayed
  captions match the items. Any item without a streamed page (e.g. a hand-authored
  LFM with captions only) gets a fresh page; any surplus streamed panel that has
  no item is left untouched (it is still an owned child, but not part of a tab). }
procedure TTyTabControl.Loaded;
var
  StreamedPages: array of TTyPanel;
  I, PageCursor: Integer;
  Ctrl: TControl;
  Page: TTyPanel;
  Item: TTyTabItem;
begin
  inherited Loaded;

  { Collect already-existing child panels (the streamed pages), in control order. }
  SetLength(StreamedPages, 0);
  for I := 0 to ControlCount - 1 do
  begin
    Ctrl := Controls[I];
    if Ctrl is TTyPanel then
    begin
      SetLength(StreamedPages, Length(StreamedPages) + 1);
      StreamedPages[High(StreamedPages)] := TTyPanel(Ctrl);
    end;
  end;

  { Rebuild the parallel arrays purely from the loaded collection. }
  FCaptions.Clear;
  SetLength(FPages, 0);
  PageCursor := 0;
  for I := 0 to FTabs.Count - 1 do
  begin
    Item := FTabs.Items[I];
    if Item.FPage <> nil then
      Page := Item.FPage                 // defensive: already wired
    else if PageCursor <= High(StreamedPages) then
    begin
      Page := StreamedPages[PageCursor]; // reuse a streamed page
      Inc(PageCursor);
    end
    else
    begin
      { No streamed page for this item (e.g. captions-only LFM): create one. }
      Page := TTyPanel.Create(Self);
      Page.Parent := Self;
    end;

    Page.Align := alClient;
    Page.Visible := False;
    Page.Controller := Self.Controller;
    Item.FPage := Page;

    FCaptions.Add(Item.Caption);
    SetLength(FPages, Length(FPages) + 1);
    FPages[High(FPages)] := Page;
  end;

  { Re-establish selection. inherited Loaded has already cleared csLoading, so
    SetTabIndex now clamps and shows the page normally. A TabIndex written
    during loading is captured in FPendingTabIndex; apply it. Otherwise, when
    nothing was streamed and there are pages, default to the first tab to
    preserve the legacy in-memory auto-select. }
  if FPendingTabIndex <> -1 then
  begin
    SetTabIndex(FPendingTabIndex);
    FPendingTabIndex := -1;
  end
  else if (FTabIndex = -1) and (Length(FPages) > 0) then
    FTabIndex := 0;

  if Length(FPages) = 0 then
    FTabIndex := -1;

  ShowOnlyPage(FTabIndex);
  Invalidate;
end;

procedure TTyTabControl.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, TabStyle, ArrowStyle, CloseS: TTyStyleSet;
  R: TRect;
  W, H, TabH, I: Integer;
  HdrRect, CloseRect, TextRect, BandRect, SavedClip: TRect;
  TabStates: TTyStateSet;
  CloseHi: TTyFill;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    W := R.Right;
    H := R.Bottom;
    P.BeginPaint(ACanvas, ARect, APPI);

    BoxStyle := CurrentStyle;
    TabH := TabHPx(APPI);

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

    for I := 0 to FCaptions.Count - 1 do
    begin
      HdrRect   := HeaderRectShifted(I);
      CloseRect := FCloseRects[I];
      if FTabsClosable then
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

      { Fill header background }
      if tpBackground in TabStyle.Present then
        P.FillBackground(HdrRect, TabStyle.Background, TyEffectiveCorners(TabStyle));

      { Draw caption centered in header (clipped to left of close glyph) }
      TextRect := HdrRect;
      if FTabsClosable then
        TextRect.Right := CloseRect.Left;
      P.DrawText(TextRect,
        FCaptions[I],
        TabStyle.FontName, ResolveFontSize(TabStyle), TabStyle.FontWeight,
        TabStyle.TextColor,
        taCenter, tlCenter, True);

      if FTabsClosable then
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

procedure TTyTabControl.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ Mouse: hit-test headers on left-click }
procedure TTyTabControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
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

      for I := 0 to FCaptions.Count - 1 do
      begin
        HdrRect := HeaderRectShifted(I);
        if (X >= HdrRect.Left) and (X < HdrRect.Right) then
        begin
          CloseRect := FCloseRects[I];
          OffsetRect(CloseRect, -FHeaderScroll, 0);
          if FTabsClosable and
             (X >= CloseRect.Left) and (X < CloseRect.Right) and
             (Y >= CloseRect.Top) and (Y < CloseRect.Bottom) then
            DoCloseTab(I)
          else
          begin
            TabIndex := I;
            { Arm a drag-reorder candidate. A plain press+release stays a click
              (FDragging never flips); only a move past the threshold reorders. }
            FDragTab    := I;
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

procedure TTyTabControl.MouseMove(Shift: TShiftState; X, Y: Integer);
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
    rule) by reseating the backing collection item, which re-syncs the parallel
    arrays via TabsChanged. Skip the hover scan while dragging. }
  if (FDragTab >= 0) and (ssLeft in Shift) then
  begin
    if (not FDragging) and (Abs(X - FDragStartX) >= TyDragThresholdPx(PPI)) then
      FDragging := True;
    if FDragging then
    begin
      Target := TyDropIndexAt(X, PPI);
      if (Target >= 0) and (Target <> FDragTab) then
      begin
        FTabs.Items[FDragTab].Index := Target; // -> TabsChanged re-syncs arrays
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
      for I := 0 to FCaptions.Count - 1 do
      begin
        HdrRect := HeaderRectShifted(I);
        if (X >= HdrRect.Left) and (X < HdrRect.Right) then
        begin
          NewHover := I;
          { Independent close (x) hover: only when closable and the pointer is
            inside this tab's shifted close rect. Mirrors the MouseDown hit-test
            so the highlight and the actual close target stay in lockstep. }
          if FTabsClosable then
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
procedure TTyTabControl.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragTab  := -1;
  FDragging := False;
end;

procedure TTyTabControl.MouseLeave;
begin
  inherited MouseLeave;
  { Disarm any in-flight drag so a re-entry move without a fresh press is inert. }
  FDragTab  := -1;
  FDragging := False;
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
function TTyTabControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
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
procedure TTyTabControl.KeyDown(var Key: Word; Shift: TShiftState);
var NewIndex, Cnt: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  Cnt := FCaptions.Count;
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
