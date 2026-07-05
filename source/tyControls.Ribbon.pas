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
    FPages: array of TTyRibbonPage;
    FDestroying: Boolean;
    function GetPage(AIndex: Integer): TTyRibbonPage;
    function GetActivePage: TTyRibbonPage;
    procedure SetActivePage(AValue: TTyRibbonPage);
    procedure ShowOnlyPage(AIndex: Integer);
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
    procedure SetCaption(const AValue: string);
  protected
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
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
    FLauncherRect: TRect;    // device px, hit-test for the launcher arrow
    procedure SetCaption(const AValue: string);
    procedure SetShowDialogLauncher(AValue: Boolean);
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
  Align := alTop;
  // Tab strip (TabHeight) + a group band tall enough for a large button + caption.
  Width := 600;
  Height := 118;
  TabStop := True;
end;

destructor TTyRibbon.Destroy;
begin
  FDestroying := True;
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

function TTyRibbon.GetTabCount: Integer;
begin
  Result := Length(FPages);
end;

function TTyRibbon.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex].Caption
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

function TTyRibbon.GetActivePage: TTyRibbonPage;
begin
  Result := GetPage(ActivePageIndex);
end;

procedure TTyRibbon.SetActivePage(AValue: TTyRibbonPage);
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I] = AValue then
    begin
      ActivePageIndex := I;
      Exit;
    end;
end;

procedure TTyRibbon.ShowOnlyPage(AIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
  begin
    // csNoDesignVisible BEFORE Visible (the Visible change triggers the design-time
    // re-eval) — see [[designer-internal-subcontrol-leak]].
    if I = AIndex then
      FPages[I].ControlStyle := FPages[I].ControlStyle - [csNoDesignVisible]
    else
      FPages[I].ControlStyle := FPages[I].ControlStyle + [csNoDesignVisible];
    FPages[I].Visible := (I = AIndex);
  end;
  Invalidate;
end;

procedure TTyRibbon.DoSelectTab(AIndex: Integer);
begin
  ShowOnlyPage(AIndex);
end;

procedure TTyRibbon.DoReorderTabs(AFromIndex, AToIndex: Integer);
var
  Moved: TTyRibbonPage;
  I: Integer;
begin
  if (AFromIndex < 0) or (AFromIndex > High(FPages)) then Exit;
  if (AToIndex < 0) or (AToIndex > High(FPages)) then Exit;
  if AFromIndex = AToIndex then Exit;
  Moved := FPages[AFromIndex];
  if AFromIndex < AToIndex then
    for I := AFromIndex to AToIndex - 1 do FPages[I] := FPages[I + 1]
  else
    for I := AFromIndex downto AToIndex + 1 do FPages[I] := FPages[I - 1];
  FPages[AToIndex] := Moved;
end;

procedure TTyRibbon.RegisterPage(APage: TTyRibbonPage);
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I] = APage then Exit;   // idempotent
  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := APage;
  APage.Controller := Self.Controller;
  if Length(FPages) = 1 then
  begin
    FTabIndex := 0;
    ShowOnlyPage(0);
  end
  else
    APage.Visible := (High(FPages) = FTabIndex);
  TabsChanged;
end;

procedure TTyRibbon.UnregisterPage(APage: TTyRibbonPage; AFree: Boolean);
var
  Idx, J: Integer;
begin
  Idx := -1;
  for J := 0 to High(FPages) do
    if FPages[J] = APage then begin Idx := J; Break; end;
  if Idx < 0 then Exit;
  for J := Idx to High(FPages) - 1 do FPages[J] := FPages[J + 1];
  SetLength(FPages, Length(FPages) - 1);
  if Length(FPages) = 0 then
    FTabIndex := -1
  else if Idx < FTabIndex then
    Dec(FTabIndex)
  else if (Idx = FTabIndex) and (FTabIndex > High(FPages)) then
    FTabIndex := High(FPages);
  if AFree and (APage <> nil) then
    APage.Free;
  ShowOnlyPage(FTabIndex);
  TabsChanged;
end;

procedure TTyRibbon.RemoveTabData(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    UnregisterPage(FPages[AIndex], True);
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

    // Dialog-launcher arrow in the bottom-right of the caption band.
    if FShowDialogLauncher then
    begin
      FLauncherRect := Rect(W - bandPx, H - bandPx, W, H);
      P.DrawGlyph(FLauncherRect, tgArrowDown, S.TextColor, 1);
    end
    else
      FLauncherRect := Rect(0, 0, 0, 0);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbonGroup.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyRibbonGroup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and FShowDialogLauncher and Assigned(FOnDialogLauncher) and
     (X >= FLauncherRect.Left) and (X < FLauncherRect.Right) and
     (Y >= FLauncherRect.Top) and (Y < FLauncherRect.Bottom) then
    FOnDialogLauncher(Self);
end;

initialization
  RegisterClass(TTyRibbon);
  RegisterClass(TTyRibbonPage);
  RegisterClass(TTyRibbonGroup);
end.
