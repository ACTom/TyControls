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
  TTyCustomPageControl = class(TTyCustomTabStrip)
  private
    FPages: array of TTyCustomTabSheet;
    FDestroying: Boolean;
    function GetPage(AIndex: Integer): TTyCustomTabSheet;
    function GetActivePage: TTyCustomTabSheet;
    procedure SetActivePage(AValue: TTyCustomTabSheet);
    procedure ShowOnlyPage(AIndex: Integer);
  protected
    function  GetTabCount: Integer; override;
    function  GetTabCaption(AIndex: Integer): string; override;
    { The page's own ImageIndex -- the per-item half of the icon rule, which OnGetImageIndex
      then has the last word over. Reading it off the PAGE rather than off a parallel array
      is what makes a reorder carry the icon with its tab. }
    function  GetTabImageIndex(AIndex: Integer): Integer; override;
    { The page's TabVisible -- except at design time, where every tab shows (the
      Delphi rule: you cannot click what is not there). }
    function  GetTabVisibleAt(AIndex: Integer): Boolean; override;
    procedure DoImagesChanged; override;
    function  GetStyleTypeKey: string; override;
    procedure DoSelectTab(AIndex: Integer); override;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
    procedure SetController(AValue: TTyCustomStyleController); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    { Designer tab clicks flip pages (see TTyCustomTabStrip.CMDesignHitTest). }
    function DesignTabClicksEnabled: Boolean; override;
    { The TCustomTabControl / Delphi contract: ShowControl walks up the parent chain
      (each hop passes its own child), and a tab container answers by activating the
      page that hosts the shown control -- Sheet.Show and Delphi-ported code rely on it. }
    procedure ShowControl(AControl: TControl); override;
  public
    { Hiding the ACTIVE page's tab moves the selection to the nearest visible tab
      (next first, then previous -- the Delphi behaviour); with no visible tab left
      the page keeps showing (the wizard pattern owns the band then). }
    procedure TabVisibilityChanged(AIndex: Integer); override;
    destructor Destroy; override;
    { Public so TTyTabSheet.SetParent (a different unit) can self-register. Idempotent. }
    procedure RegisterPage(APage: TTyCustomTabSheet);
    { The other half of RegisterPage, and public for the same reason: SetParent lives in
      tyControls.TabSheet and protected does not reach across units. It used to be reachable
      only from Notification (opRemove) and the close path, i.e. only when a page was being
      FREED -- so a page that merely MOVED to another pager registered with the new one and
      stayed registered with the old one too. The old pager went on counting it, drawing its
      tab and handing it out from Pages[], while the control itself lived somewhere else.
      AFree=False leaves the page alone; True frees it (the close-button path). }
    procedure UnregisterPage(APage: TTyCustomTabSheet; AFree: Boolean);
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
    { The pages, and the shown one, as TTyCustomTabSheet: a page control takes any
      TTyCustomTabSheet descendant (a page registers itself from SetParent), so the custom
      class is what it can truthfully hand out -- LCL's TCustomTabControl does the same with
      Page[] / ActivePageComponent: TCustomPage (comctrls.pp:457/500). TPageControl's
      ActivePage: TTabSheet is a true cast only because TPageControl admits nothing but
      TTabSheets; this one admits a third party's page. AddPage and its aliases build a
      TTyTabSheet and still return one. }
    property Pages[AIndex: Integer]: TTyCustomTabSheet read GetPage;
    property ActivePageIndex: Integer read FTabIndex write SetTabIndex default -1;
    { Published by TTyPageControl, as TPageControl does. It was public-only, so the designer
      and the .lfm could pick the shown page only by INDEX -- and an index silently points at
      a different page the moment someone reorders the tabs, while a page reference does
      not. ActivePageIndex stays for code that prefers it; both address one selection.
      Public here, the visibility of its LCL counterpart ActivePageComponent. }
    property ActivePage: TTyCustomTabSheet read GetActivePage write SetActivePage;
  end;

  { TTyPageControl publishes TTyCustomPageControl's properties; everything lives in TTyCustomPageControl. }
  TTyPageControl = class(TTyCustomPageControl)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Images;
    property ImagesWidth;
    property OnGetImageIndex;
    property TabHeight;
    property TabsClosable;
    property OnTabClose;
    property OnChange;
    property OnChanging;
    property OnReorder;
    property Align;
    property Anchors;
    property ActivePage;
    property ActivePageIndex;
    { Promoted from public on the header engine. Published HERE and on TTyTabSet rather
      than on the shared base, because TTyRibbon is the base's third subclass and its File
      tab, collapse chevron and KeyTip chips are all pinned to a top band -- publishing on
      the base would have offered the ribbon a designer property that moves the tabs and
      leaves that chrome where it was. }
    property TabPosition;
    { Promoted for the same reason and with the same boundary: a folded band is RowCount rows
      thick, and the ribbon's File tab / collapse chevron / KeyTip chips are all one row tall.
      RowCount itself stays PUBLIC -- it is read-only, and a published property with no setter
      is skipped by TWriter and reported unreadable by the Object Inspector. }
    property MultiLine;
    property RaggedRight;
    { Docking, republished exactly as TPageControl does. Same story as TTyPanel and
      TTyGroupBox: every member is TWinControl's or TControl's own, the dock manager is
      LCL code we do not touch, and a real drag docks a control into a ty page control with
      no source change -- measured, and written up in
      plans/2026-08-04-parity-remaining-programs.md. Four of the nine
      (OnGetSiteInfo/OnGetDockCaption/OnStartDock/OnEndDock) are PROTECTED upstream, so
      before this no route reached them at all. }
    property DockSite;
    property UseDockManager;
    property OnDockDrop;
    property OnDockOver;
    property OnUnDock;
    property OnGetSiteInfo;
    property OnGetDockCaption;
    property OnStartDock;
    property OnEndDock;
  end;

implementation

function TTyCustomPageControl.GetStyleTypeKey: string;
begin
  Result := 'TyPageControl';
end;

function TTyCustomPageControl.PageCount: Integer;
begin
  Result := Length(FPages);
end;

function TTyCustomPageControl.GetTabCount: Integer;
begin
  Result := Length(FPages);
end;

function TTyCustomPageControl.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex].Caption
  else
    Result := '';
end;

function TTyCustomPageControl.GetTabImageIndex(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) and (FPages[AIndex] <> nil) then
    Result := FPages[AIndex].ImageIndex
  else
    Result := -1;
end;

function TTyCustomPageControl.GetTabVisibleAt(AIndex: Integer): Boolean;
begin
  if csDesigning in ComponentState then Exit(True);
  if (AIndex >= 0) and (AIndex < Length(FPages)) and (FPages[AIndex] <> nil) then
    Result := FPages[AIndex].TabVisible
  else
    Result := True;
end;

procedure TTyCustomPageControl.TabVisibilityChanged(AIndex: Integer);
var
  NewIdx: Integer;
begin
  { Runtime only, and only when the ACTIVE tab was hidden: next visible first, then
    previous. NearestVisibleTab returns its start unchanged when the walk finds
    nothing, so "every tab hidden" falls through and the page keeps showing. }
  if not (csDesigning in ComponentState)
    and (AIndex = TabIndex) and not GetTabVisibleAt(AIndex) then
  begin
    NewIdx := NearestVisibleTab(AIndex, 1, False);
    if NewIdx = AIndex then NewIdx := NearestVisibleTab(AIndex, -1, False);
    if NewIdx <> AIndex then TabIndex := NewIdx;
  end;
  inherited TabVisibilityChanged(AIndex);
end;

procedure TTyCustomPageControl.DoImagesChanged;
var i: Integer;
begin
  { The list just changed: give every page the chance to turn a pending ImageIndex into its
    durable name against the new list. Idempotent for pages with nothing pending. }
  for i := 0 to High(FPages) do
    if FPages[i] <> nil then
      FPages[i].ResolveImageIndex;
end;

function TTyCustomPageControl.GetPage(AIndex: Integer): TTyCustomTabSheet;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex]
  else
    Result := nil;
end;

function TTyCustomPageControl.GetActivePage: TTyCustomTabSheet;
begin
  Result := GetPage(ActivePageIndex);
end;

procedure TTyCustomPageControl.SetActivePage(AValue: TTyCustomTabSheet);
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

procedure TTyCustomPageControl.ShowOnlyPage(AIndex: Integer);
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

procedure TTyCustomPageControl.DoSelectTab(AIndex: Integer);
begin
  ShowOnlyPage(AIndex);
end;

procedure TTyCustomPageControl.DoReorderTabs(AFromIndex, AToIndex: Integer);
var
  Moved: TTyCustomTabSheet;
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

procedure TTyCustomPageControl.MovePage(AFromIndex, AToIndex: Integer);
begin
  if (AFromIndex < 0) or (AFromIndex > High(FPages)) then Exit;
  if AToIndex < 0 then AToIndex := 0;
  if AToIndex > High(FPages) then AToIndex := High(FPages);
  if AFromIndex = AToIndex then Exit;
  DoReorderTabs(AFromIndex, AToIndex);
  TabsChanged;
end;

procedure TTyCustomPageControl.RegisterPage(APage: TTyCustomTabSheet);
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I] = APage then Exit;   // already registered (idempotent)
  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := APage;
  { Hear about the page's destruction ourselves: Notification(opRemove) reaches us on its own
    only when we share its owner, so a page owned by anything else (or by nothing) would be
    freed while still in FPages -- counted, tabbed and read through on the next caption. }
  APage.FreeNotification(Self);
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

procedure TTyCustomPageControl.UnregisterPage(APage: TTyCustomTabSheet; AFree: Boolean);
var
  Idx, J: Integer;
  OldActive: TTyCustomTabSheet;
begin
  Idx := -1;
  for J := 0 to High(FPages) do
    if FPages[J] = APage then begin Idx := J; Break; end;
  if Idx < 0 then Exit;
  OldActive := GetActivePage;
  for J := Idx to High(FPages) - 1 do FPages[J] := FPages[J + 1];
  SetLength(FPages, Length(FPages) - 1);
  APage.RemoveFreeNotification(Self);   // the other half of RegisterPage's
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

procedure TTyCustomPageControl.RemoveTabData(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    UnregisterPage(FPages[AIndex], True);
end;

procedure TTyCustomPageControl.RemovePage(AIndex: Integer);
begin
  RemoveTabData(AIndex);
end;

function TTyCustomPageControl.AddPage(const ACaption: string): TTyTabSheet;
var
  PageOwner: TComponent;
begin
  if Owner <> nil then PageOwner := Owner else PageOwner := Self;
  Result := TTyTabSheet.Create(PageOwner);
  Result.Caption := ACaption;
  Result.Parent := Self;     // SetParent -> RegisterPage
end;

function TTyCustomPageControl.AddTab(const ACaption: string): TTyTabSheet;
begin
  Result := AddPage(ACaption);
end;

function TTyCustomPageControl.AddTabSheet: TTyTabSheet;
begin
  { '' and not a generated name: LCL's AddTabSheet leaves the caption empty too, and a
    made-up 'TabSheet1' would then be a label the host has to notice and clear. }
  Result := AddPage('');
end;

function TTyCustomPageControl.IndexOfPageAt(X, Y: Integer): Integer;
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

function TTyCustomPageControl.IndexOfPageAt(P: TPoint): Integer;
begin
  Result := IndexOfPageAt(P.x, P.y);
end;

procedure TTyCustomPageControl.SetController(AValue: TTyCustomStyleController);
var
  I: Integer;
begin
  inherited SetController(AValue);
  for I := 0 to High(FPages) do
    if FPages[I] <> nil then
      FPages[I].Controller := AValue;
end;

procedure TTyCustomPageControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyCustomTabSheet) then
    UnregisterPage(TTyCustomTabSheet(AComponent), False);   // LCL already freeing it
end;

procedure TTyCustomPageControl.Loaded;
begin
  { Pages self-registered via SetParent during streaming, so FPages is already
    populated in child order; inherited applies a streamed ActivePageIndex (the
    base Loaded consumes SetTabIndex's csLoading capture -- for every strip). }
  inherited Loaded;
  if (FTabIndex = -1) and (Length(FPages) > 0) then
    FTabIndex := 0;
  if Length(FPages) = 0 then
    FTabIndex := -1;
  ShowOnlyPage(FTabIndex);
  Invalidate;
end;

function TTyCustomPageControl.DesignTabClicksEnabled: Boolean;
begin
  Result := True;
end;

procedure TTyCustomPageControl.ShowControl(AControl: TControl);
var
  i: Integer;
begin
  { Mirror TCustomTabControl.ShowControl: a direct page match activates that page.
    A control nested ON a page arrives here as the page itself, because the default
    TWinControl.ShowControl passes each caller's own child up the parent chain. }
  for i := 0 to PageCount - 1 do
    if GetPage(i) = AControl then
    begin
      ActivePageIndex := i;
      Exit;
    end;
  inherited ShowControl(AControl);
end;

destructor TTyCustomPageControl.Destroy;
begin
  FDestroying := True;
  inherited Destroy;   // pages are owned by the form (or Self) and freed normally
end;

initialization
  RegisterClass(TTyPageControl);
end.
