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
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.TabStrip;

type
  TTyRibbonPage = class;

  { The ribbon host. Extends the tab-header engine; adds page management (identical
    in shape to TTyPageControl). }
  TTyRibbon = class(TTyCustomTabStrip)
  private
    FPages: array of TTyRibbonPage;         // ALL pages, in child order
    FVisible: array of Integer;             // visible tab index -> FPages index
    FActiveContexts: TStringList;           // active context names (case-insensitive)
    FDestroying: Boolean;
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
    procedure SetController(AValue: TTyStyleController); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    procedure UnregisterPage(APage: TTyRibbonPage; AFree: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Public so TTyRibbonPage.SetParent (same unit) can self-register. Idempotent. }
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
    property Align default alTop;
  end;

  { One ribbon tab page — hosts groups. }
  TTyRibbonPage = class(TTyCustomControl)
  private
    FCaption: string;
    FContext: string;
    procedure SetCaption(const AValue: string);
    procedure SetContext(const AValue: string);
  protected
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
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

  TTyRibbonGroup = class;
  TTyRibbonLauncherEvent = procedure(Sender: TTyRibbonGroup) of object;

  { A labelled group box inside a ribbon page. }
  TTyRibbonGroup = class(TTyCustomControl)
  private
    FCaption: string;
    FShowDialogLauncher: Boolean;
    FOnDialogLauncher: TTyRibbonLauncherEvent;
    procedure SetCaption(const AValue: string);
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
  TabStop := True;
end;

destructor TTyRibbon.Destroy;
begin
  FDestroying := True;
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
    DrawFrame(P, Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top), S);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbonPage.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
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

procedure TTyRibbonGroup.SetShowDialogLauncher(AValue: Boolean);
begin
  if FShowDialogLauncher = AValue then Exit;
  FShowDialogLauncher := AValue;
  Invalidate;
end;

procedure TTyRibbonGroup.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
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

    // Caption centered in the bottom band.
    if FCaption <> '' then
    begin
      capRect := Rect(P.Scale(2), H - bandPx, W - P.Scale(2), H);
      P.DrawText(capRect, FCaption, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taCenter, tlCenter, True);
    end;

    // Dialog-launcher arrow in the bottom-right of the caption band (same geometry
    // as LauncherRectPx, which the hit-test uses).
    if FShowDialogLauncher then
      P.DrawGlyph(Rect(W - bandPx, H - bandPx, W, H), tgArrowDown, S.TextColor, 1);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbonGroup.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

function TTyRibbonGroup.LauncherRectPx: TRect;
var
  bandPx: Integer;
begin
  if not FShowDialogLauncher then Exit(Rect(0, 0, 0, 0));
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
