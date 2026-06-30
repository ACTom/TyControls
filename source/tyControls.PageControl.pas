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
    function  GetStyleTypeKey: string; override;
    procedure DoSelectTab(AIndex: Integer); override;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    procedure UnregisterPage(APage: TTyTabSheet; AFree: Boolean);
  public
    destructor Destroy; override;
    { Public so TTyTabSheet.SetParent (a different unit) can self-register. Idempotent. }
    procedure RegisterPage(APage: TTyTabSheet);
    function AddPage(const ACaption: string): TTyTabSheet;
    function AddTab(const ACaption: string): TTyTabSheet;   // API-parity alias
    procedure RemovePage(AIndex: Integer);
    function PageCount: Integer;
    property Pages[AIndex: Integer]: TTyTabSheet read GetPage;
    property ActivePage: TTyTabSheet read GetActivePage write SetActivePage;
  published
    property ActivePageIndex: Integer read FTabIndex write SetTabIndex default -1;
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
