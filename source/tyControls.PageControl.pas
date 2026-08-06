unit tyControls.PageControl;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.TabStrip, tyControls.TabSheet;
type
  { A TPageControl-faithful designer container: TTyTabSheet pages owned by the form,
    parented to the control, streamed via the default GetChildren (Owner=Root). The
    tab strip (header) comes from TTyCustomTabStrip; tab captions are read from the
    pages. Active-page switching toggles Visible + csNoDesignVisible per page. }
  TTyPageControl = class(TTyCustomTabStrip)
  private
    FPages: array of TTyTabSheet;
    FDestroying: Boolean;
    function GetPage(AIndex: Integer): TTyTabSheet;
    function GetActivePage: TTyTabSheet;
    procedure SetActivePage(AValue: TTyTabSheet);
    procedure ShowOnlyPage(AIndex: Integer);
  protected
    function  GetTabCount: Integer; override;
    function  GetTabCaption(AIndex: Integer): string; override;
    { The page's own ImageIndex -- the per-item half of the icon rule, which OnGetImageIndex
      then has the last word over. Reading it off the PAGE rather than off a parallel array
      is what makes a reorder carry the icon with its tab. }
    function  GetTabImageIndex(AIndex: Integer): Integer; override;
    function  GetStyleTypeKey: string; override;
    procedure DoSelectTab(AIndex: Integer); override;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    destructor Destroy; override;
    { Public so TTyTabSheet.SetParent (a different unit) can self-register. Idempotent. }
    procedure RegisterPage(APage: TTyTabSheet);
    { The other half of RegisterPage, and public for the same reason: SetParent lives in
      tyControls.TabSheet and protected does not reach across units. It used to be reachable
      only from Notification (opRemove) and the close path, i.e. only when a page was being
      FREED -- so a page that merely MOVED to another pager registered with the new one and
      stayed registered with the old one too. The old pager went on counting it, drawing its
      tab and handing it out from Pages[], while the control itself lived somewhere else.
      AFree=False leaves the page alone; True frees it (the close-button path). }
    procedure UnregisterPage(APage: TTyTabSheet; AFree: Boolean);
    function AddPage(const ACaption: string): TTyTabSheet;
    function AddTab(const ACaption: string): TTyTabSheet;   // API-parity alias
    { LCL's spelling (comctrls.pp:606) and LCL's signature: no caption argument, returns the
      page. It is the single most common way pages get created in existing Delphi/Lazarus
      code, and it is the one spelling this class did not answer to. }
    function AddTabSheet: TTyTabSheet;
    { Which PAGE is under a point, or -1 for none. LCL's IndexOfPageAt (comctrls.pp:452,
      overridden on TPageControl :604) asks about the page BODY, where IndexOfTabAt asks
      about the header -- so a point on the tab band is not a page hit, and vice versa.
      Only the active page occupies the body, so at most one index can ever answer. }
    function IndexOfPageAt(X, Y: Integer): Integer; overload;
    function IndexOfPageAt(P: TPoint): Integer; overload;
    procedure RemovePage(AIndex: Integer);
    { Move a page (and its tab) from one position to another. The reorder primitive existed
      but only as a PROTECTED hook driven by the header drag, so application code had no way
      to order pages at all. Public entry point for TTyTabSheet.PageIndex; both ends are
      clamped and out-of-range or no-op moves are ignored. }
    procedure MovePage(AFromIndex, AToIndex: Integer);
    function PageCount: Integer;
    property Pages[AIndex: Integer]: TTyTabSheet read GetPage;
  published
    { PUBLISHED, as TPageControl does. It was public-only, so the designer and the .lfm
      could pick the shown page only by INDEX -- and an index silently points at a
      different page the moment someone reorders the tabs, while a page reference does
      not. ActivePageIndex stays for code that prefers it; both address one selection. }
    property ActivePage: TTyTabSheet read GetActivePage write SetActivePage;
    property ActivePageIndex: Integer read FTabIndex write SetTabIndex default -1;
    { Promoted from public on the header engine. Published HERE and on TTyTabSet rather
      than on the shared base, because TTyRibbon is the base's third subclass and its File
      tab, collapse chevron and KeyTip chips are all pinned to a top band -- publishing on
      the base would have offered the ribbon a designer property that moves the tabs and
      leaves that chrome where it was. }
    property TabPosition;
  end;

implementation

function TTyPageControl.GetStyleTypeKey: string;
begin
  Result := 'TyPageControl';
end;

function TTyPageControl.PageCount: Integer;
begin
  Result := Length(FPages);
end;

function TTyPageControl.GetTabCount: Integer;
begin
  Result := Length(FPages);
end;

function TTyPageControl.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex].Caption
  else
    Result := '';
end;

function TTyPageControl.GetTabImageIndex(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) and (FPages[AIndex] <> nil) then
    Result := FPages[AIndex].ImageIndex
  else
    Result := -1;
end;

function TTyPageControl.GetPage(AIndex: Integer): TTyTabSheet;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex]
  else
    Result := nil;
end;

function TTyPageControl.GetActivePage: TTyTabSheet;
begin
  Result := GetPage(ActivePageIndex);
end;

procedure TTyPageControl.SetActivePage(AValue: TTyTabSheet);
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

procedure TTyPageControl.ShowOnlyPage(AIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
  begin
    { Set csNoDesignVisible BEFORE Visible. The control's design-time shown-state is
      `Visible or (csDesigning and not csNoDesignVisible)`, and it is the VISIBLE change that
      triggers the re-evaluation (UpdateControlState). If csNoDesignVisible were set AFTER, the
      re-eval would have run against its stale value, leaving a switched-away page's HWND shown
      until a full designer re-render (the "flip to the code tab and back" workaround). }
    if I = AIndex then
      FPages[I].ControlStyle := FPages[I].ControlStyle - [csNoDesignVisible]
    else
      FPages[I].ControlStyle := FPages[I].ControlStyle + [csNoDesignVisible];
    FPages[I].Visible := (I = AIndex);
  end;
  Invalidate;
end;

procedure TTyPageControl.DoSelectTab(AIndex: Integer);
begin
  ShowOnlyPage(AIndex);
end;

procedure TTyPageControl.DoReorderTabs(AFromIndex, AToIndex: Integer);
var
  Moved: TTyTabSheet;
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
  { Re-show whatever page NOW sits at the selected index.

    The selection is pinned to the POSITION, not to the moved tab (the same rule
    TTyTabSet.DoReorderTabs documents) -- but only the header was following that rule.
    Visible is a property of the page OBJECT, and nothing re-assigned it after the array was
    permuted, so dragging a tab past the selected one left the highlighted tab and the shown
    page disagreeing: the header said "B" and the body still showed A, until the next tab
    click resynced them. }
  ShowOnlyPage(FTabIndex);
end;

procedure TTyPageControl.MovePage(AFromIndex, AToIndex: Integer);
begin
  if (AFromIndex < 0) or (AFromIndex > High(FPages)) then Exit;
  if AToIndex < 0 then AToIndex := 0;
  if AToIndex > High(FPages) then AToIndex := High(FPages);
  if AFromIndex = AToIndex then Exit;
  DoReorderTabs(AFromIndex, AToIndex);
  TabsChanged;
end;

procedure TTyPageControl.RegisterPage(APage: TTyTabSheet);
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I] = APage then Exit;   // already registered (idempotent)
  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := APage;
  APage.Controller := Self.Controller;
  if Length(FPages) = 1 then
  begin
    FTabIndex := 0;          // auto-select the first page
    ShowOnlyPage(0);
  end
  else
    APage.Visible := (High(FPages) = FTabIndex);
  TabsChanged;
end;

procedure TTyPageControl.UnregisterPage(APage: TTyTabSheet; AFree: Boolean);
var
  Idx, J: Integer;
  OldActive: TTyTabSheet;
begin
  Idx := -1;
  for J := 0 to High(FPages) do
    if FPages[J] = APage then begin Idx := J; Break; end;
  if Idx < 0 then Exit;
  OldActive := GetActivePage;
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
  if (GetActivePage <> OldActive) and Assigned(OnChange) then
    OnChange(Self);
end;

procedure TTyPageControl.RemoveTabData(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    UnregisterPage(FPages[AIndex], True);
end;

procedure TTyPageControl.RemovePage(AIndex: Integer);
begin
  RemoveTabData(AIndex);
end;

function TTyPageControl.AddPage(const ACaption: string): TTyTabSheet;
var
  PageOwner: TComponent;
begin
  if Owner <> nil then PageOwner := Owner else PageOwner := Self;
  Result := TTyTabSheet.Create(PageOwner);
  Result.Caption := ACaption;
  Result.Parent := Self;     // SetParent -> RegisterPage
end;

function TTyPageControl.AddTab(const ACaption: string): TTyTabSheet;
begin
  Result := AddPage(ACaption);
end;

function TTyPageControl.AddTabSheet: TTyTabSheet;
begin
  { '' and not a generated name: LCL's AddTabSheet leaves the caption empty too, and a
    made-up 'TabSheet1' would then be a label the host has to notice and clear. }
  Result := AddPage('');
end;

function TTyPageControl.IndexOfPageAt(X, Y: Integer): Integer;
var
  Body: TRect;
begin
  Result := -1;
  Body := DisplayRect;
  if (X < Body.Left) or (X >= Body.Right) then Exit;
  if (Y < Body.Top) or (Y >= Body.Bottom) then Exit;
  { The shown page is the only one with any pixels; every other page is Visible := False. }
  if (FTabIndex >= 0) and (FTabIndex <= High(FPages)) then
    Result := FTabIndex;
end;

function TTyPageControl.IndexOfPageAt(P: TPoint): Integer;
begin
  Result := IndexOfPageAt(P.x, P.y);
end;

procedure TTyPageControl.SetController(AValue: TTyStyleController);
var
  I: Integer;
begin
  inherited SetController(AValue);
  for I := 0 to High(FPages) do
    if FPages[I] <> nil then
      FPages[I].Controller := AValue;
end;

procedure TTyPageControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyTabSheet) then
    UnregisterPage(TTyTabSheet(AComponent), False);   // LCL already freeing it
end;

procedure TTyPageControl.Loaded;
begin
  inherited Loaded;
  { Pages self-registered via SetParent during streaming, so FPages is already
    populated in child order. Apply a streamed ActivePageIndex (captured by the
    base SetTabIndex into FPendingTabIndex while csLoading was set). }
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

destructor TTyPageControl.Destroy;
begin
  FDestroying := True;
  inherited Destroy;   // pages are owned by the form (or Self) and freed normally
end;

initialization
  RegisterClass(TTyPageControl);
end.
