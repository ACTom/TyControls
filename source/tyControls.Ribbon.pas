unit tyControls.Ribbon;
{$mode objfpc}{$H+}

{ Phase-3 R1 — the Ribbon skeleton: three tightly-coupled controls in one unit.

  TTyRibbon      — a top-docked command surface. Extends TTyCustomTabStrip (reusing
                   its whole tab-header engine: layout/render/click/hover/keyboard),
                   so the ribbon's tab strip is a tab strip. Below the strip it hosts
                   the ACTIVE page's group band. Pages are TTyRibbonPage children,
                   owned by the form and streamed via the default GetChildren (exactly
                   the TTyPageControl pattern). Ribbon tabs reuse the 'TyTab' token for
                   now; the surface below is 'TyRibbon'.
  TTyRibbonPage  — one tab: a themed band that hosts TTyRibbonGroups (which flow
                   left->right via Align=alLeft). Caption is the TAB label. Mirrors
                   TTyTabSheet's design-time flags + self-registration.
  TTyRibbonGroup — a labelled group box: a bottom caption band + a right separator,
                   hosting command controls (the Batch-C buttons) in the area above
                   the caption. Optional dialog-launcher arrow (bottom-right).

  Runtime tab-click switches the active page (the base's SetTabIndex -> DoSelectTab).
  Pure geometry (TyRibbonGroupContentRect) is unit-tested headlessly; rendering, the
  IDE designer, and interaction need a real machine. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.TabStrip, tyControls.RibbonBackstage, tyControls.PopupSurface,
  tyControls.Button, tyControls.KeyTips;

type
  TTyRibbonPage = class;
  TTyRibbonGroup = class;

  { The ribbon host. Extends the tab-header engine; adds page management (identical
    in shape to TTyPageControl). }
  TTyRibbon = class(TTyCustomTabStrip)
  private
    FPages: array of TTyRibbonPage;         // ALL pages, in child order
    FVisible: array of Integer;             // visible tab index -> FPages index
    FActiveContexts: TStringList;           // active context names (case-insensitive)
    FDestroying: Boolean;
    FMinimized: Boolean;
    FExpandedHeight: Integer;               // Height to restore when un-minimized
    FShowFileTab: Boolean;
    FFileTabCaption: string;
    FFileTabWidth: Integer;                 // logical px
    FBackstage: TTyRibbonBackstage;
    FShowCollapseBtn: Boolean;
    FFlyout: TTyPopupSurface;        // transient page band shown while Minimized
    FKeyTips: Boolean;
    FKeyTipsActive: Boolean;
    FKeyTipKeys: TKeyTipArray;       // one access key per VISIBLE tab (+ 'F' for the File tab)
    FHookedForm: TCustomForm;
    FSavedFormKeyDown: TKeyEvent;
    FSavedKeyPreview: Boolean;
    FOnFileTab: TNotifyEvent;
    procedure ShowFlyout;
    procedure FlyoutClosed(Sender: TObject);
    procedure SetKeyTips(AValue: Boolean);
    procedure HookForm;
    procedure UnhookForm;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RebuildKeyTipKeys;
    procedure DrawKeyTips;
    procedure SetMinimized(AValue: Boolean);
    procedure SetShowFileTab(AValue: Boolean);
    procedure SetFileTabCaption(const AValue: string);
    procedure SetFileTabWidth(AValue: Integer);
    procedure SetBackstage(AValue: TTyRibbonBackstage);
    procedure SetShowCollapseButton(AValue: Boolean);
    function FileTabWidthPx: Integer;
    function CollapseRectPx: TRect;
    procedure DrawFileTab;
    procedure DrawCollapseButton;
    function GetPage(AIndex: Integer): TTyRibbonPage;
    function GetActivePage: TTyRibbonPage;
    procedure SetActivePage(AValue: TTyRibbonPage);
    procedure ShowOnlyVisible(AVisIdx: Integer);
    procedure RebuildVisible;
    function  PageVisible(APageIdx: Integer): Boolean;
    { Re-derive the visible tab list + re-anchor the active tab on the SAME page object
      (AOldActive) it had before the change, clamping to the first visible tab when that
      page became hidden/removed. Callers capture AOldActive BEFORE mutating FPages. }
    procedure ReconcileVisibleFrom(AOldActive: TTyRibbonPage; AFireChange: Boolean);
  protected
    function  GetTabCount: Integer; override;
    function  GetTabCaption(AIndex: Integer): string; override;
    function  GetStyleTypeKey: string; override;
    procedure DoSelectTab(AIndex: Integer); override;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
    function  HeaderLeftInset: Integer; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    procedure CreateWnd; override;
    procedure UnregisterPage(APage: TTyRibbonPage; AFree: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Public so TTyRibbonPage.SetParent (same unit) can self-register. Idempotent. }
    { KeyTips: show/hide the Alt access-key badges over the tab strip. Pressing a tab's key
      switches to it. Also toggled by pressing Alt on the parent form. }
    procedure ShowKeyTips;
    procedure HideKeyTips;
    procedure ToggleKeyTips;
    procedure RegisterPage(APage: TTyRibbonPage);
    function AddPage(const ACaption: string): TTyRibbonPage;
    procedure RemovePage(AIndex: Integer);
    function PageCount: Integer;
    { Contextual tabs: a page whose Context is non-empty is only shown as a tab while
      that context is active. Activating/deactivating a context re-lays the strip and
      re-anchors the selection. Context names are case-insensitive. }
    procedure ShowContext(const AName: string);
    procedure HideContext(const AName: string);
    function  IsContextActive(const AName: string): Boolean;
    { Called by a page whose Context changed (same unit). }
    procedure PageContextChanged;
    property Pages[AIndex: Integer]: TTyRibbonPage read GetPage;
    property ActivePage: TTyRibbonPage read GetActivePage write SetActivePage;
  published
    property ActivePageIndex: Integer read FTabIndex write SetTabIndex default -1;
    { When True the group band collapses so only the tab strip shows (the ribbon's
      Height shrinks to the tab-header height); setting it back restores the previous
      Height. The transient show-page-on-tab-click overlay is a GUI follow-up. }
    property Minimized: Boolean read FMinimized write SetMinimized default False;
    { A modern-Office "File" tab at the LEFT of the tab strip (accent-styled). Clicking
      it opens Backstage (if assigned) and/or fires OnFileTab — it does NOT switch pages. }
    property FileTab: Boolean read FShowFileTab write SetShowFileTab default False;
    property FileTabCaption: string read FFileTabCaption write SetFileTabCaption;
    property FileTabWidth: Integer read FFileTabWidth write SetFileTabWidth default 52;
    property Backstage: TTyRibbonBackstage read FBackstage write SetBackstage;
    { A collapse/expand chevron at the RIGHT end of the tab strip that toggles Minimized
      (like Office). Double-clicking any tab also toggles Minimized. }
    property ShowCollapseButton: Boolean read FShowCollapseBtn write SetShowCollapseButton default True;
    { When True (default), pressing Alt on the parent form shows access-key badges over the
      tabs (Office KeyTips); typing a badge's letter switches to that tab, Escape hides them. }
    property KeyTips: Boolean read FKeyTips write SetKeyTips default True;
    property OnFileTab: TNotifyEvent read FOnFileTab write FOnFileTab;
    property Align default alTop;
  end;

  { One ribbon tab page — hosts groups. }
  TTyRibbonPage = class(TTyCustomControl)
  private
    FCaption: string;
    FContext: string;
    // Group-overflow (F3): the trailing groups that don't fit collapse into a "more" popup.
    FVisualGroups: array of TTyRibbonGroup;   // groups in stable left-to-right (visual) order
    FMoreBtn: TTyButton;                       // the "»" overflow button
    FPopup: TTyPopupSurface;                    // hosts the overflow groups while open
    FOverflowFrom: Integer;                     // FVisualGroups index where the overflow set begins
    FInLayout: Boolean;
    FCaptured: Boolean;
    procedure SetCaption(const AValue: string);
    procedure SetContext(const AValue: string);
    procedure CaptureGroups;
    procedure LayoutOverflow;
    procedure EnsureMoreButton;
    procedure MoreClick(Sender: TObject);
    procedure OverflowPopupClosed(Sender: TObject);
  protected
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
    { When non-empty, this page is a CONTEXTUAL tab: shown only while its host ribbon's
      context of this name is active (TTyRibbon.ShowContext/HideContext). Empty = a
      normal always-visible tab. }
    property Context: string read FContext write SetContext;
    property StyleClass;
    property Controller;
  end;

  TTyRibbonLauncherEvent = procedure(Sender: TTyRibbonGroup) of object;

  { A labelled group box inside a ribbon page. }
  TTyRibbonGroup = class(TTyCustomControl)
  private
    FCaption: string;
    FShowCaption: Boolean;
    FShowDialogLauncher: Boolean;
    FOnDialogLauncher: TTyRibbonLauncherEvent;
    procedure SetCaption(const AValue: string);
    procedure SetShowCaption(AValue: Boolean);
    procedure SetShowDialogLauncher(AValue: Boolean);
    { The launcher arrow's client rect (device px) — computed from the current size,
      NOT cached from the last Paint, so the hit-test works before the first paint. }
    function LauncherRectPx: TRect;
  protected
    function GetStyleTypeKey: string; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
    { Show the bottom caption band (the group name). False = the content fills the full
      height and no caption/launcher is drawn (a caption-less group). }
    property ShowCaption: Boolean read FShowCaption write SetShowCaption default True;
    { Show a small dialog-launcher arrow in the bottom-right of the caption band. }
    property ShowDialogLauncher: Boolean read FShowDialogLauncher write SetShowDialogLauncher default False;
    property OnDialogLauncher: TTyRibbonLauncherEvent read FOnDialogLauncher write FOnDialogLauncher;
    property Align default alLeft;
    property StyleClass;
    property Controller;
  end;

const
  TyRibbonCaptionBand = 18;   // logical px, the group's bottom title strip

{ Pure geometry: the content rect (device px, (0,0)-local) a group hosts controls in
  = the full client minus the bottom caption band (scaled from APadBottomPx). }
function TyRibbonGroupContentRect(AWidthPx, AHeightPx, ACaptionBandPx: Integer): TRect;

{ Pure overflow decision: given each group's natural width (device px) left->right and
  the available band width, return how many TRAILING groups (lowest priority = last)
  must collapse to a fixed ACollapsedPx button so the row fits. 0 = all fit; N (all) =
  even fully collapsed it doesn't fit. Headless-testable. }
function TyRibbonOverflowCount(const ANaturalWidths: array of Integer;
  AAvailPx, ACollapsedPx: Integer): Integer;

{ The collapse/expand button rect (device px, (0,0)-local): an ATabHpx square at the RIGHT
  end of the tab strip. Empty when the client is too narrow to hold it. Headless-testable. }
function TyRibbonCollapseRect(AClientWpx, ATabHpx: Integer): TRect;

{ How many LEADING groups (device-px widths, left-to-right) fit in AAvailPx before the row
  overflows — always at least 1 (the first group shows even if it alone overflows). The rest
  are the overflow set that collapses into the "more" popup. Headless-testable. }
function TyRibbonVisibleGroupCount(const AWidths: array of Integer; AAvailPx: Integer): Integer;

implementation

// ---------------------------------------------------------------------------
// Pure geometry
// ---------------------------------------------------------------------------
function TyRibbonGroupContentRect(AWidthPx, AHeightPx, ACaptionBandPx: Integer): TRect;
begin
  if ACaptionBandPx < 0 then ACaptionBandPx := 0;
  if ACaptionBandPx > AHeightPx then ACaptionBandPx := AHeightPx;
  Result := Rect(0, 0, AWidthPx, AHeightPx - ACaptionBandPx);
end;

function TyRibbonOverflowCount(const ANaturalWidths: array of Integer;
  AAvailPx, ACollapsedPx: Integer): Integer;
var
  N, I, Collapse, Total: Integer;
begin
  N := Length(ANaturalWidths);
  if ACollapsedPx < 0 then ACollapsedPx := 0;
  // Try collapsing the last 0, 1, 2 ... groups until the row fits.
  for Collapse := 0 to N do
  begin
    Total := 0;
    for I := 0 to N - 1 do
      if I < N - Collapse then
        Total := Total + ANaturalWidths[I]   // full width
      else
        Total := Total + ACollapsedPx;        // collapsed to a button
    if Total <= AAvailPx then
      Exit(Collapse);
  end;
  Result := N;   // even all-collapsed overflows
end;

function TyRibbonCollapseRect(AClientWpx, ATabHpx: Integer): TRect;
begin
  if (AClientWpx <= 0) or (ATabHpx <= 0) or (ATabHpx > AClientWpx) then
    Exit(Rect(0, 0, 0, 0));
  Result := Rect(AClientWpx - ATabHpx, 0, AClientWpx, ATabHpx);
end;

function TyRibbonVisibleGroupCount(const AWidths: array of Integer; AAvailPx: Integer): Integer;
var
  i, total: Integer;
begin
  Result := 0;
  total := 0;
  for i := 0 to High(AWidths) do
  begin
    // Stop once adding this group would overflow — but always keep at least one.
    if (Result > 0) and (total + AWidths[i] > AAvailPx) then Exit;
    Inc(total, AWidths[i]);
    Inc(Result);
  end;
end;

// ===========================================================================
// TTyRibbon
// ===========================================================================
constructor TTyRibbon.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActiveContexts := TStringList.Create;
  FActiveContexts.CaseSensitive := False;
  Align := alTop;
  // Tab strip (TabHeight) + a group band tall enough for a large button + caption.
  Width := 600;
  Height := 118;
  FExpandedHeight := 118;   // restored height if Minimized is set before any resize
  FShowFileTab := False;
  FFileTabCaption := '文件';
  FFileTabWidth := 52;
  FShowCollapseBtn := True;
  FKeyTips := True;
  TabStop := True;
end;

destructor TTyRibbon.Destroy;
begin
  FDestroying := True;
  UnhookForm;
  FActiveContexts.Free;
  inherited Destroy;   // pages owned by the form are freed normally
end;

function TTyRibbon.GetStyleTypeKey: string;
begin
  Result := 'TyRibbon';
end;

function TTyRibbon.PageCount: Integer;
begin
  Result := Length(FPages);
end;

// The tab strip enumerates only the VISIBLE pages (context-active or context-less).
function TTyRibbon.GetTabCount: Integer;
begin
  Result := Length(FVisible);
end;

function TTyRibbon.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(FVisible)) then
    Result := FPages[FVisible[AIndex]].Caption
  else
    Result := '';
end;

function TTyRibbon.GetPage(AIndex: Integer): TTyRibbonPage;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex]
  else
    Result := nil;
end;

// ActivePageIndex is the VISIBLE tab index (= the page index when no context hides a
// page); map it to the page object.
function TTyRibbon.GetActivePage: TTyRibbonPage;
begin
  if (FTabIndex >= 0) and (FTabIndex < Length(FVisible)) then
    Result := FPages[FVisible[FTabIndex]]
  else
    Result := nil;
end;

procedure TTyRibbon.SetActivePage(AValue: TTyRibbonPage);
var
  I: Integer;
begin
  for I := 0 to High(FVisible) do
    if FPages[FVisible[I]] = AValue then
    begin
      ActivePageIndex := I;   // the VISIBLE index
      Exit;
    end;
end;

function TTyRibbon.PageVisible(APageIdx: Integer): Boolean;
begin
  Result := (FPages[APageIdx].Context = '') or IsContextActive(FPages[APageIdx].Context);
end;

procedure TTyRibbon.RebuildVisible;
var
  I: Integer;
begin
  SetLength(FVisible, 0);
  for I := 0 to High(FPages) do
    if PageVisible(I) then
    begin
      SetLength(FVisible, Length(FVisible) + 1);
      FVisible[High(FVisible)] := I;
    end;
end;

// Show the page at VISIBLE index AVisIdx; hide every other page (context-hidden pages
// are hidden here too, since they are never the shown one).
procedure TTyRibbon.ShowOnlyVisible(AVisIdx: Integer);
var
  I, ActivePageIdx: Integer;
begin
  if (AVisIdx >= 0) and (AVisIdx < Length(FVisible)) then
    ActivePageIdx := FVisible[AVisIdx]
  else
    ActivePageIdx := -1;
  for I := 0 to High(FPages) do
  begin
    // csNoDesignVisible BEFORE Visible (the Visible change triggers the design-time
    // re-eval) — see [[designer-internal-subcontrol-leak]].
    if I = ActivePageIdx then
      FPages[I].ControlStyle := FPages[I].ControlStyle - [csNoDesignVisible]
    else
      FPages[I].ControlStyle := FPages[I].ControlStyle + [csNoDesignVisible];
    FPages[I].Visible := (I = ActivePageIdx);
  end;
  Invalidate;
end;

procedure TTyRibbon.ReconcileVisibleFrom(AOldActive: TTyRibbonPage; AFireChange: Boolean);
var
  I, NewIdx: Integer;
begin
  RebuildVisible;
  // Follow the SAME active page object where possible (comparison only — AOldActive may
  // be a just-freed pointer, which is safe to compare but never dereferenced).
  NewIdx := -1;
  if AOldActive <> nil then
    for I := 0 to High(FVisible) do
      if FPages[FVisible[I]] = AOldActive then begin NewIdx := I; Break; end;
  if NewIdx < 0 then
  begin
    // The active page became hidden/removed: keep the same tab POSITION, clamped to the
    // new visible range (matches TTyPageControl's clamp-to-last on active removal).
    NewIdx := FTabIndex;
    if NewIdx > High(FVisible) then NewIdx := High(FVisible);
    if (NewIdx < 0) and (Length(FVisible) > 0) then NewIdx := 0;
  end;
  if Length(FVisible) = 0 then NewIdx := -1;
  FTabIndex := NewIdx;
  ShowOnlyVisible(FTabIndex);
  TabsChanged;
  if AFireChange and (GetActivePage <> AOldActive) and Assigned(OnChange) then
    OnChange(Self);
end;

procedure TTyRibbon.DoSelectTab(AIndex: Integer);
begin
  ShowOnlyVisible(AIndex);
end;

procedure TTyRibbon.DoReorderTabs(AFromIndex, AToIndex: Integer);
var
  Moved: TTyRibbonPage;
  FromPage, ToPage, I: Integer;
begin
  // The header engine reorders by VISIBLE index; map both ends to page indices, move
  // within FPages, then rebuild the visible list.
  if (AFromIndex < 0) or (AFromIndex > High(FVisible)) then Exit;
  if (AToIndex < 0) or (AToIndex > High(FVisible)) then Exit;
  if AFromIndex = AToIndex then Exit;
  FromPage := FVisible[AFromIndex];
  ToPage := FVisible[AToIndex];
  Moved := FPages[FromPage];
  if FromPage < ToPage then
    for I := FromPage to ToPage - 1 do FPages[I] := FPages[I + 1]
  else
    for I := FromPage downto ToPage + 1 do FPages[I] := FPages[I - 1];
  FPages[ToPage] := Moved;
  RebuildVisible;
end;

procedure TTyRibbon.RegisterPage(APage: TTyRibbonPage);
var
  I: Integer;
  OldActive: TTyRibbonPage;
begin
  for I := 0 to High(FPages) do
    if FPages[I] = APage then Exit;   // idempotent
  OldActive := GetActivePage;         // BEFORE appending (append keeps old indices valid)
  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := APage;
  APage.Controller := Self.Controller;
  ReconcileVisibleFrom(OldActive, False);   // no OnChange on add
end;

procedure TTyRibbon.UnregisterPage(APage: TTyRibbonPage; AFree: Boolean);
var
  Idx, J: Integer;
  OldActive: TTyRibbonPage;
begin
  Idx := -1;
  for J := 0 to High(FPages) do
    if FPages[J] = APage then begin Idx := J; Break; end;
  if Idx < 0 then Exit;
  OldActive := GetActivePage;         // capture BEFORE mutating FPages
  for J := Idx to High(FPages) - 1 do FPages[J] := FPages[J + 1];
  SetLength(FPages, Length(FPages) - 1);
  if AFree and (APage <> nil) then
    APage.Free;
  ReconcileVisibleFrom(OldActive, True);    // fires OnChange when the active page moved
end;

procedure TTyRibbon.RemoveTabData(AIndex: Integer);
begin
  // AIndex is a VISIBLE tab index (the header engine's space).
  if (AIndex >= 0) and (AIndex < Length(FVisible)) then
    UnregisterPage(FPages[FVisible[AIndex]], True);
end;

procedure TTyRibbon.RemovePage(AIndex: Integer);
begin
  RemoveTabData(AIndex);
end;

function TTyRibbon.AddPage(const ACaption: string): TTyRibbonPage;
var
  PageOwner: TComponent;
begin
  if Owner <> nil then PageOwner := Owner else PageOwner := Self;
  Result := TTyRibbonPage.Create(PageOwner);
  Result.Caption := ACaption;
  Result.Parent := Self;     // SetParent -> RegisterPage
end;

function TTyRibbon.IsContextActive(const AName: string): Boolean;
begin
  Result := (AName <> '') and (FActiveContexts.IndexOf(AName) >= 0);
end;

procedure TTyRibbon.ShowContext(const AName: string);
var
  OldActive: TTyRibbonPage;
begin
  if (AName = '') or IsContextActive(AName) then Exit;
  OldActive := GetActivePage;
  FActiveContexts.Add(AName);
  ReconcileVisibleFrom(OldActive, True);
end;

procedure TTyRibbon.HideContext(const AName: string);
var
  Idx: Integer;
  OldActive: TTyRibbonPage;
begin
  Idx := FActiveContexts.IndexOf(AName);
  if Idx < 0 then Exit;
  OldActive := GetActivePage;
  FActiveContexts.Delete(Idx);
  ReconcileVisibleFrom(OldActive, True);
end;

procedure TTyRibbon.PageContextChanged;
begin
  ReconcileVisibleFrom(GetActivePage, True);
end;

procedure TTyRibbon.SetMinimized(AValue: Boolean);
begin
  if FMinimized = AValue then Exit;
  FMinimized := AValue;
  if FMinimized then
  begin
    FExpandedHeight := Height;                          // remember the full height
    Height := MulDiv(TabHeight, Font.PixelsPerInch, 96); // collapse to just the tab strip
  end
  else if FExpandedHeight > 0 then
    Height := FExpandedHeight;                 // restore the group band
  Invalidate;
end;

function TTyRibbon.FileTabWidthPx: Integer;
begin
  Result := MulDiv(FFileTabWidth, Font.PixelsPerInch, 96);
end;

function TTyRibbon.HeaderLeftInset: Integer;
begin
  if FShowFileTab then Result := FileTabWidthPx else Result := 0;
end;

procedure TTyRibbon.AdjustClientRect(var ARect: TRect);
var
  ppi: Integer;
begin
  inherited AdjustClientRect(ARect);   // reserves the tab-strip band on top
  // Reserve the ribbon's own frame (+ a small bottom gap) so the active page and its group
  // caption band don't paint OVER the ribbon's left/right/bottom border — the group names
  // and dialog-launcher were covering the bottom edge line.
  ppi := Font.PixelsPerInch;
  Inc(ARect.Left,  MulDiv(1, ppi, 96));
  Dec(ARect.Right, MulDiv(1, ppi, 96));
  // Reserve just the frame so the active page (windowed) can't paint over the bottom border,
  // but keep it MINIMAL (2px) so the border reads as a single line right under the group band
  // rather than a wide surface strip. (Runtime-verified: page bottom lands above the border.)
  Dec(ARect.Bottom, MulDiv(2, ppi, 96));
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

procedure TTyRibbon.SetShowFileTab(AValue: Boolean);
begin
  if FShowFileTab = AValue then Exit;
  FShowFileTab := AValue;
  Realign;      // the header shifts by the File-tab inset
  Invalidate;
end;

procedure TTyRibbon.SetFileTabCaption(const AValue: string);
begin
  if FFileTabCaption = AValue then Exit;
  FFileTabCaption := AValue;
  Invalidate;
end;

procedure TTyRibbon.SetFileTabWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FFileTabWidth = AValue then Exit;
  FFileTabWidth := AValue;
  Realign;
  Invalidate;
end;

procedure TTyRibbon.SetBackstage(AValue: TTyRibbonBackstage);
begin
  if FBackstage = AValue then Exit;
  if FBackstage <> nil then FBackstage.RemoveFreeNotification(Self);
  FBackstage := AValue;
  if FBackstage <> nil then FBackstage.FreeNotification(Self);
end;

procedure TTyRibbon.SetShowCollapseButton(AValue: Boolean);
begin
  if FShowCollapseBtn = AValue then Exit;
  FShowCollapseBtn := AValue;
  Invalidate;
end;

function TTyRibbon.CollapseRectPx: TRect;
begin
  if not FShowCollapseBtn then Exit(Rect(0, 0, 0, 0));
  Result := TyRibbonCollapseRect(ClientWidth, MulDiv(TabHeight, Font.PixelsPerInch, 96));
end;

{ Draw the collapse/expand chevron at the right of the tab strip: an up chevron when the
  ribbon is expanded (click to collapse), a down chevron when minimized (click to expand). }
procedure TTyRibbon.DrawCollapseButton;
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  g: TTyGlyphKind;
begin
  R := CollapseRectPx;
  if R.Right <= R.Left then Exit;
  S := ActiveController.Model.ResolveStyle('TyTab', '', []);
  if FMinimized then g := tgArrowDown else g := tgArrowUp;
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, R, Font.PixelsPerInch);
    P.DrawGlyph(Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top), g, S.TextColor, 1, 9);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

{ Draw the accent File tab in the reserved left inset (its own small paint pass, sized
  to the tab rect so it does not blit over the base's tab-strip drawing). }
procedure TTyRibbon.DrawFileTab;
var
  P: TTyPainter;
  S: TTyStyleSet;
  ppi, w, h, fs: Integer;
begin
  if not FShowFileTab then Exit;
  ppi := Font.PixelsPerInch;
  w := FileTabWidthPx;
  h := MulDiv(TabHeight, ppi, 96);
  if (w <= 0) or (h <= 0) then Exit;
  S := ActiveController.Model.ResolveStyle('TyButton', 'primary', []);
  fs := S.FontSize; if fs <= 0 then fs := 9;
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, Rect(0, 0, w, h), ppi);
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, w, h), S.Background, 0);
    P.DrawText(Rect(0, 0, w, h), FFileTabCaption, S.FontName, fs, S.FontWeight,
      S.TextColor, taCenter, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

{ Show the active page's group band in a transient flyout just below the tab strip
  (used while Minimized). The real page control is temporarily re-parented into the
  popup so its live command buttons keep working; closing restores it to the ribbon. }
procedure TTyRibbon.ShowFlyout;
var
  pg: TTyRibbonPage;
  stripH, bandHpx: Integer;
  tl: TPoint;
begin
  pg := GetActivePage;
  if (pg = nil) or not FMinimized then Exit;
  if FFlyout = nil then
  begin
    FFlyout := TTyPopupSurface.CreateNew(Self);
    FFlyout.StyleKey := 'TyRibbon';
    FFlyout.OnPopupClose := @FlyoutClosed;
  end;
  stripH := MulDiv(TabHeight, Font.PixelsPerInch, 96);
  bandHpx := FExpandedHeight - stripH;             // the expanded group-band height
  if bandHpx < stripH then bandHpx := MulDiv(90, Font.PixelsPerInch, 96);
  tl := ClientToScreen(Point(0, stripH));          // just below the tab strip
  FFlyout.AdoptContent(pg);
  FFlyout.ShowAt(Rect(tl.x, tl.y, tl.x + Width, tl.y + bandHpx));
end;

procedure TTyRibbon.FlyoutClosed(Sender: TObject);
begin
  // The popup already released the page back to the ribbon; re-lay the (minimized) band.
  if not (csDestroying in ComponentState) then
    Realign;
end;

// ---------------------------------------------------------------------------
// KeyTips (Alt access-key overlay)
// ---------------------------------------------------------------------------
procedure TTyRibbon.SetKeyTips(AValue: Boolean);
begin
  if FKeyTips = AValue then Exit;
  FKeyTips := AValue;
  if not FKeyTips then HideKeyTips;
end;

procedure TTyRibbon.RebuildKeyTipKeys;
var
  caps: array of string;
  i: Integer;
begin
  SetLength(caps, GetTabCount);
  for i := 0 to GetTabCount - 1 do
    caps[i] := GetTabCaption(i);
  FKeyTipKeys := TyAssignKeyTips(caps);
end;

procedure TTyRibbon.ShowKeyTips;
begin
  if not FKeyTips then Exit;
  RebuildKeyTipKeys;
  FKeyTipsActive := True;
  Invalidate;
end;

procedure TTyRibbon.HideKeyTips;
begin
  if not FKeyTipsActive then Exit;
  FKeyTipsActive := False;
  Invalidate;
end;

procedure TTyRibbon.ToggleKeyTips;
begin
  if FKeyTipsActive then HideKeyTips else ShowKeyTips;
end;

procedure TTyRibbon.HookForm;
var
  frm: TCustomForm;
begin
  if csDesigning in ComponentState then Exit;
  frm := GetParentForm(Self);
  if (frm = nil) or (frm = FHookedForm) then Exit;
  UnhookForm;
  FHookedForm := frm;
  FSavedFormKeyDown := frm.OnKeyDown;
  FSavedKeyPreview := frm.KeyPreview;
  frm.KeyPreview := True;
  frm.OnKeyDown := @FormKeyDown;
end;

procedure TTyRibbon.UnhookForm;
begin
  if FHookedForm = nil then Exit;
  // Only restore if OUR handler is still installed (don't clobber a later hook).
  if TMethod(FHookedForm.OnKeyDown).Data = Pointer(Self) then
  begin
    FHookedForm.OnKeyDown := FSavedFormKeyDown;
    FHookedForm.KeyPreview := FSavedKeyPreview;
  end;
  FHookedForm := nil;
end;

procedure TTyRibbon.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  i: Integer;
  ch: Char;
begin
  // Bare Alt toggles the KeyTip badges.
  if FKeyTips and (Key = VK_MENU) and (Shift * [ssShift, ssCtrl] = []) then
  begin
    ToggleKeyTips;
    Key := 0;
    Exit;
  end;
  if FKeyTipsActive then
  begin
    if Key = VK_ESCAPE then begin HideKeyTips; Key := 0; Exit; end;
    if (Key >= Ord('0')) and (Key <= Ord('Z')) then
    begin
      ch := UpCase(Chr(Key));
      for i := 0 to High(FKeyTipKeys) do
        if (FKeyTipKeys[i] <> '') and (UpCase(FKeyTipKeys[i][1]) = ch) then
        begin
          ActivePageIndex := i;
          HideKeyTips;
          Key := 0;
          Exit;
        end;
    end;
  end;
  if Assigned(FSavedFormKeyDown) then FSavedFormKeyDown(Sender, Key, Shift);
end;

procedure TTyRibbon.DrawKeyTips;
var
  P: TTyPainter;
  chipS: TTyStyleSet;
  i, cw, bx, by: Integer;
  hr: TRect;
  key: string;
begin
  if not FKeyTipsActive then Exit;
  if Length(FKeyTipKeys) <> GetTabCount then RebuildKeyTipKeys;
  chipS := ActiveController.Model.ResolveStyle('TyButton', 'primary', []);
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
    cw := P.Scale(15);
    for i := 0 to GetTabCount - 1 do
    begin
      if i > High(FKeyTipKeys) then Break;
      key := FKeyTipKeys[i];
      if key = '' then Continue;
      hr := HeaderRectShifted(i);                 // tab rect (device px)
      bx := (hr.Left + hr.Right) div 2 - cw div 2;
      by := hr.Bottom - P.Scale(2) - cw;          // a small chip near the tab's bottom
      if tpBackground in chipS.Present then
        P.FillBackground(Rect(bx, by, bx + cw, by + cw), chipS.Background, P.Scale(3));
      P.DrawText(Rect(bx, by, bx + cw, by + cw), key, chipS.FontName, 8,
        chipS.FontWeight, chipS.TextColor, taCenter, tlCenter, False);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbon.Paint;
begin
  inherited Paint;   // base draws the tab strip (shifted right by HeaderLeftInset) + frame
  DrawFileTab;
  DrawCollapseButton;
  DrawKeyTips;
end;

procedure TTyRibbon.CreateWnd;
begin
  inherited CreateWnd;
  HookForm;   // the parent form exists by now -> install the Alt key hook
end;

procedure TTyRibbon.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  w, h: Integer;
  Frm: TCustomForm;
  R: TRect;
begin
  if FKeyTipsActive then HideKeyTips;   // any click dismisses the KeyTip overlay
  if FShowFileTab and (Button = mbLeft) then
  begin
    w := FileTabWidthPx;
    h := MulDiv(TabHeight, Font.PixelsPerInch, 96);
    if (X >= 0) and (X < w) and (Y >= 0) and (Y < h) then
    begin
      // The File tab opens the backstage and/or fires OnFileTab — it does NOT switch
      // pages, so swallow the click (don't call the base tab hit-test).
      if FBackstage <> nil then
      begin
        Frm := GetParentForm(Self);
        if Frm <> nil then
          FBackstage.ShowOver(Frm, Top);   // cover everything below the title bar
      end;
      if Assigned(FOnFileTab) then FOnFileTab(Self);
      Exit;
    end;
  end;
  // Collapse/expand chevron at the right of the strip toggles Minimized.
  if (Button = mbLeft) and FShowCollapseBtn then
  begin
    R := CollapseRectPx;
    if (R.Right > R.Left) and (X >= R.Left) and (X < R.Right) and
       (Y >= R.Top) and (Y < R.Bottom) then
    begin
      Minimized := not Minimized;
      Exit;
    end;
  end;
  // Double-clicking a tab (anywhere in the header band, past the File tab) toggles Minimized.
  if (Button = mbLeft) and (ssDouble in Shift) then
  begin
    h := MulDiv(TabHeight, Font.PixelsPerInch, 96);
    if (Y >= 0) and (Y < h) and (X >= HeaderLeftInset) then
    begin
      Minimized := not Minimized;
      Exit;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);   // base does the tab hit-test + selection
  // While Minimized, a single click on a tab flies the active page's band out below the strip.
  if FMinimized and (Button = mbLeft) and not (ssDouble in Shift) then
  begin
    h := MulDiv(TabHeight, Font.PixelsPerInch, 96);
    R := CollapseRectPx;
    if (Y >= 0) and (Y < h) and (X >= HeaderLeftInset) and
       ((R.Right <= R.Left) or (X < R.Left)) then
      ShowFlyout;
  end;
end;

procedure TTyRibbon.SetController(AValue: TTyStyleController);
var
  I: Integer;
begin
  inherited SetController(AValue);
  for I := 0 to High(FPages) do
    if FPages[I] <> nil then
      FPages[I].Controller := AValue;
end;

procedure TTyRibbon.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FBackstage) then
    FBackstage := nil;
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyRibbonPage) then
    UnregisterPage(TTyRibbonPage(AComponent), False);
end;

procedure TTyRibbon.Loaded;
begin
  inherited Loaded;
  // Build the visible-tab list from the streamed pages (each self-registered during
  // streaming), anchoring the active tab on the first visible page.
  ReconcileVisibleFrom(nil, False);
  if FPendingTabIndex <> -1 then
  begin
    SetTabIndex(FPendingTabIndex);
    FPendingTabIndex := -1;
  end;
  Invalidate;
end;

// ===========================================================================
// TTyRibbonPage
// ===========================================================================
constructor TTyRibbonPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds,
    csNoDesignVisible, csNoFocus];
  Align := alClient;
  Visible := False;
  FCaption := '';
end;

function TTyRibbonPage.GetStyleTypeKey: string;
begin
  Result := 'TyRibbon';   // the page body is the ribbon surface below the tabs
end;

procedure TTyRibbonPage.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  if Parent <> nil then
    Parent.Invalidate;   // the tab label changed — re-lay the host strip
end;

procedure TTyRibbonPage.SetContext(const AValue: string);
begin
  if FContext = AValue then Exit;
  FContext := AValue;
  // A changed Context may show/hide this page as a tab — ask the host to re-lay.
  if (Parent <> nil) and (Parent is TTyRibbon) then
    TTyRibbon(Parent).PageContextChanged;
end;

procedure TTyRibbonPage.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if (AParent <> nil) and (AParent is TTyRibbon) then
    TTyRibbon(AParent).RegisterPage(Self);
end;

procedure TTyRibbonPage.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // Show the form photo (image theme) / opaque parent (solid) so a transparent ribbon
    // surface reveals the backdrop instead of a white hole.
    if not FillSharpBackdrop(P, Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top)) then
      TyFillParentBg(Self, P, Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top), S);
    // Fill the surface only — NO border. The ribbon's own frame already draws the outer
    // border; a page border here would DOUBLE the edge in the empty area (where no group
    // covers it), making it look thicker than where groups sit. (Reported.)
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top),
        S.Background, 0);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbonPage.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyRibbonPage.AlignControls(AControl: TControl; var ARect: TRect);
begin
  inherited AlignControls(AControl, ARect);   // first pass lays the alLeft groups
  LayoutOverflow;                             // then apply overflow collapse (page owns layout)
end;

procedure TTyRibbonPage.CaptureGroups;
var
  i, j, n, maxLeft: Integer;
  tmp: TTyRibbonGroup;
begin
  n := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyRibbonGroup then Inc(n);
  if n = 0 then Exit;
  // Capture only once the groups have actually been laid out (distinct Lefts). Before the
  // first layout every Left is 0 and CHILD order is the REVERSE of the visual order, so a
  // premature capture would scramble the group order.
  maxLeft := 0;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyRibbonGroup) and (Controls[i].Left > maxLeft) then
      maxLeft := Controls[i].Left;
  if (n > 1) and (maxLeft = 0) then Exit;
  SetLength(FVisualGroups, n);
  j := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyRibbonGroup then
    begin FVisualGroups[j] := TTyRibbonGroup(Controls[i]); Inc(j); end;
  // Insertion sort by current Left -> stable left-to-right (visual) order.
  for i := 1 to n - 1 do
  begin
    tmp := FVisualGroups[i];
    j := i - 1;
    while (j >= 0) and (FVisualGroups[j].Left > tmp.Left) do
    begin FVisualGroups[j + 1] := FVisualGroups[j]; Dec(j); end;
    FVisualGroups[j + 1] := tmp;
  end;
  FCaptured := True;
end;

procedure TTyRibbonPage.EnsureMoreButton;
begin
  if FMoreBtn <> nil then Exit;
  FMoreBtn := TTyButton.Create(Self);
  FMoreBtn.Parent := Self;
  FMoreBtn.Caption := '»';
  FMoreBtn.Hint := '更多分组';
  FMoreBtn.ShowHint := True;
  FMoreBtn.OnClick := @MoreClick;
end;

procedure TTyRibbonPage.LayoutOverflow;
var
  i, n, x, moreW, visCount, bandH, total: Integer;
  widths: array of Integer;
begin
  if FInLayout then Exit;
  if (FPopup <> nil) and FPopup.Visible then Exit;   // groups are in the popup; don't touch
  if not FCaptured then CaptureGroups;
  n := Length(FVisualGroups);
  if n = 0 then Exit;
  FInLayout := True;
  try
    bandH := ClientHeight;
    moreW := MulDiv(30, Font.PixelsPerInch, 96);
    SetLength(widths, n);
    total := 0;
    for i := 0 to n - 1 do
    begin widths[i] := FVisualGroups[i].Width; Inc(total, widths[i]); end;
    if total <= ClientWidth then
    begin
      visCount := n;
      if FMoreBtn <> nil then FMoreBtn.Visible := False;
    end
    else
    begin
      visCount := TyRibbonVisibleGroupCount(widths, ClientWidth - moreW);
      EnsureMoreButton;
    end;
    x := 0;
    for i := 0 to n - 1 do
    begin
      FVisualGroups[i].Align := alNone;   // page owns the layout from here
      if i < visCount then
      begin
        FVisualGroups[i].SetBounds(x, 0, widths[i], bandH);
        FVisualGroups[i].Visible := True;
        Inc(x, widths[i]);
      end
      else
        FVisualGroups[i].Visible := False;
    end;
    FOverflowFrom := visCount;
    if visCount < n then
    begin
      FMoreBtn.SetBounds(x, 0, moreW, bandH);
      FMoreBtn.Visible := True;
      FMoreBtn.BringToFront;
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TTyRibbonPage.MoreClick(Sender: TObject);
var
  i, x, bandH: Integer;
  tl: TPoint;
begin
  if (FOverflowFrom < 0) or (FOverflowFrom >= Length(FVisualGroups)) then Exit;
  if FPopup = nil then
  begin
    FPopup := TTyPopupSurface.CreateNew(Self);
    FPopup.StyleKey := 'TyRibbon';
    FPopup.OnPopupClose := @OverflowPopupClosed;
  end;
  bandH := ClientHeight;
  x := 0;
  for i := FOverflowFrom to High(FVisualGroups) do
  begin
    FVisualGroups[i].Parent := FPopup;   // move the overflow groups into the flyout
    FVisualGroups[i].Align := alNone;
    FVisualGroups[i].SetBounds(x, 0, FVisualGroups[i].Width, bandH);
    FVisualGroups[i].Visible := True;
    Inc(x, FVisualGroups[i].Width);
  end;
  if x <= 0 then Exit;
  tl := FMoreBtn.ClientToScreen(Point(0, FMoreBtn.Height));
  FPopup.ShowAt(Rect(tl.x, tl.y, tl.x + x, tl.y + bandH));
end;

procedure TTyRibbonPage.OverflowPopupClosed(Sender: TObject);
var
  i: Integer;
begin
  for i := FOverflowFrom to High(FVisualGroups) do
    if FVisualGroups[i] <> nil then
    begin
      FVisualGroups[i].Parent := Self;      // restore to the page (still overflowing -> hidden)
      FVisualGroups[i].Visible := False;
    end;
  LayoutOverflow;
end;

// ===========================================================================
// TTyRibbonGroup
// ===========================================================================
constructor TTyRibbonGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csNoFocus];
  Align := alLeft;
  Width := 96;
  FCaption := '';
  FShowCaption := True;
  FShowDialogLauncher := False;
end;

function TTyRibbonGroup.GetStyleTypeKey: string;
begin
  Result := 'TyRibbonGroup';
end;

procedure TTyRibbonGroup.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Invalidate;
end;

procedure TTyRibbonGroup.SetShowCaption(AValue: Boolean);
begin
  if FShowCaption = AValue then Exit;
  FShowCaption := AValue;
  Realign;      // the reserved caption band changed -> re-lay hosted controls
  Invalidate;
end;

procedure TTyRibbonGroup.SetShowDialogLauncher(AValue: Boolean);
begin
  if FShowDialogLauncher = AValue then Exit;
  FShowDialogLauncher := AValue;
  Invalidate;
end;

procedure TTyRibbonGroup.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  if not FShowCaption then Exit;   // caption-less group: content fills the full height
  // Reserve the bottom caption band so hosted command controls sit above the title.
  Dec(ARect.Bottom, MulDiv(TyRibbonCaptionBand, Font.PixelsPerInch, 96));
  // Guard a group shorter than the caption band: never invert the rect.
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

procedure TTyRibbonGroup.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, bandPx, sepW: Integer;
  capRect: TRect;
  sepFill: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    bandPx := MulDiv(TyRibbonCaptionBand, APPI, 96);

    // Fill the OPAQUE parent (ribbon page) surface first, so the group's transparent bg
    // shows the page — not the Win10 DWM glass (which blurs the caption + washes it white
    // on deactivate). This is why group names looked faint and vanished when unfocused.
    TyFillParentBg(Self, P, Rect(0, 0, W, H), S);
    // Group background (usually transparent/surface) via the resolved style.
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, W, H), S.Background, S.BorderRadius);

    // Right separator line (the between-groups divider), drawn in the border color.
    if (tpBorderColor in S.Present) and (S.BorderWidth > 0) then
    begin
      sepW := P.Scale(S.BorderWidth);
      if sepW < 1 then sepW := 1;
      sepFill := Default(TTyFill);
      sepFill.Kind := tfkSolid;
      sepFill.Color := S.BorderColor;
      P.FillBackground(Rect(W - sepW, P.Scale(4), W, H - P.Scale(4)), sepFill, 0);
    end;

    // Caption band (name + optional dialog launcher) — only when ShowCaption.
    if FShowCaption then
    begin
      if FCaption <> '' then
      begin
        capRect := Rect(P.Scale(2), H - bandPx, W - P.Scale(2), H);
        P.DrawText(capRect, FCaption, S.FontName, ResolveFontSize(S), S.FontWeight,
          S.TextColor, taCenter, tlCenter, True);
      end;
      // Small Office-style dialog launcher (diagonal arrow) in the bottom-right corner.
      if FShowDialogLauncher then
        P.DrawGlyph(Rect(W - P.Scale(13), H - P.Scale(13), W - P.Scale(3), H - P.Scale(3)),
          tgDialogLauncher, S.TextColor, 1, 0);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbonGroup.Paint;
begin
  // Paint the FULL bounds (ClientRect would exclude the reserved caption band, misplacing
  // the caption band Y on any widgetset where GetClientRect honors AdjustClientRect).
  RenderTo(Canvas, Rect(0, 0, Width, Height), Font.PixelsPerInch);
end;

function TTyRibbonGroup.LauncherRectPx: TRect;
var
  bandPx: Integer;
begin
  if (not FShowDialogLauncher) or (not FShowCaption) then Exit(Rect(0, 0, 0, 0));
  bandPx := MulDiv(TyRibbonCaptionBand, Font.PixelsPerInch, 96);
  Result := Rect(ClientWidth - bandPx, ClientHeight - bandPx, ClientWidth, ClientHeight);
end;

procedure TTyRibbonGroup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  R: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  R := LauncherRectPx;
  if (Button = mbLeft) and FShowDialogLauncher and Assigned(FOnDialogLauncher) and
     (R.Right > R.Left) and
     (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom) then
    FOnDialogLauncher(Self);
end;

initialization
  RegisterClass(TTyRibbon);
  RegisterClass(TTyRibbonPage);
  RegisterClass(TTyRibbonGroup);
end.
