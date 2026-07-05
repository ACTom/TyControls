unit tyControls.RibbonAppMenu;
{$mode objfpc}{$H+}
{ The ribbon's top-left application ("File") button (unit tyControls.RibbonAppMenu).

  TTyRibbonAppMenu — a prominent accent button (StyleClass 'primary') that drops a
  menu composed of the app's top COMMANDS plus an optional RECENT-ITEMS section.

  It SUBCLASSES TTyMenuButton (unit tyControls.DropButtons): the whole button is the
  drop trigger, it inherits the caption + trailing arrow drawing, and its Click fires
  OnDropDown then pops the inherited DropDownMenu when a window handle exists. It reuses
  the 'TyButton' style token (GetStyleTypeKey unchanged) — NO new .tycss is introduced;
  the accent look comes entirely from StyleClass := 'primary'.

  Composition without mutating anything the user owns:
    - The user sets Commands (a TTyPopupMenu — their File menu tree) and RecentItems (a
      TStrings of recent-file captions). Neither is ever mutated by this control.
    - This control owns an INTERNAL TTyPopupMenu (FMenu, created in Create / freed in
      Destroy) that the button actually drops. On every drop (DoDropDown override) it
      REBUILDS FMenu: it copies the top-level Commands items (Caption + a forwarding
      OnClick that re-fires the source item's OnClick), then — if RecentItems is
      non-empty — appends a separator and one item per recent entry (each routing to
      OnRecentItemClick with its index). Finally it points the inherited DropDownMenu at
      FMenu and calls inherited DoDropDown.

  Headless-safe: the rebuild + wiring never need a window handle (the inherited
  DoDropDown gates the actual GUI PopUp on HandleAllocated), and Commands=nil /
  RecentItems empty are all handled. }

interface

uses
  Classes, SysUtils, Menus,
  tyControls.DropButtons, tyControls.Menu;

const
  { Default logical-px size of the app-menu button (96-PPI baseline). Wide + short like
    Office's File tab; scaled to device px by the LCL layout at paint time. }
  TyRibbonAppMenuDefaultWidth  = 64;
  TyRibbonAppMenuDefaultHeight = 26;

type
  { Fired when the user chooses one of the RecentItems rows in the dropped menu. AIndex
    is the 0-based index into RecentItems of the chosen entry. }
  TTyRecentItemEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { The ribbon application ("File") button: an accent TTyMenuButton that composes the
    user's Commands menu with an optional recent-items list into an internal dropdown. }
  TTyRibbonAppMenu = class(TTyMenuButton)
  private
    { The internal menu the button actually drops. Owned by Self (created in Create,
      freed in Destroy); rebuilt from Commands + RecentItems on every drop. Never
      exposed for the user to mutate. }
    FMenu: TTyPopupMenu;
    { The user's command menu (their File items). Referenced, never mutated or owned;
      FreeNotification-tracked so freeing it nils this. }
    FCommands: TTyPopupMenu;
    FRecentItems: TStrings;
    FOnRecentItemClick: TTyRecentItemEvent;
    procedure SetCommands(AValue: TTyPopupMenu);
    procedure SetRecentItems(AValue: TStrings);
    { OnClick target on each RECENT item: map the clicked item back to its RecentItems
      index (carried in the item's Tag) and fire OnRecentItemClick. }
    procedure HandleRecentClick(Sender: TObject);
    procedure RecentItemsChanged(Sender: TObject);
  protected
    { Rebuild FMenu from the current Commands + RecentItems WITHOUT popping anything (no
      GUI). Copies the top-level command items (Caption + forwarding OnClick), then — if
      RecentItems is non-empty — appends a separator + one item per recent entry. Exposed
      (protected) so a headless test can assert the composed item count/wiring without a
      live PopUp. }
    procedure RebuildMenu; virtual;
    { Test seams over the composed internal menu (which a headless test can't reach — FMenu
      is private): the count of, and AIndex-th item of, FMenu.Items after RebuildMenu. Let
      a test verify the composition (command count + separator + recent count) and click a
      row (via TMenuItem.Click) without a live PopUp. }
    function DroppedMenuItemCount: Integer;
    function DroppedMenuItem(AIndex: Integer): TMenuItem;
    { Compose FMenu (RebuildMenu), point the inherited DropDownMenu at it, then run the
      inherited drop (fires OnDropDown + pops FMenu when a handle exists). }
    procedure DoDropDown; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    { The user's command menu (their "File" items). Copied into the internal dropdown on
      each drop; never mutated. FreeNotification-tracked: freeing it nils this. }
    property Commands: TTyPopupMenu read FCommands write SetCommands;
    { Recent-file captions. When non-empty a separator + one row per entry is appended
      below the commands; choosing a row fires OnRecentItemClick with its index. }
    property RecentItems: TStrings read FRecentItems write SetRecentItems;
    { Fired when a recent-items row is chosen (AIndex = index into RecentItems). }
    property OnRecentItemClick: TTyRecentItemEvent read FOnRecentItemClick write FOnRecentItemClick;
  end;

implementation

{ TTyRibbonAppMenu }

constructor TTyRibbonAppMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // The internal dropped menu (owned by Self, freed in Destroy). Rebuilt on each drop;
  // routed through DropDownMenu in DoDropDown, so it's never streamed/edited by the user.
  FMenu := TTyPopupMenu.Create(Self);
  FRecentItems := TStringList.Create;
  TStringList(FRecentItems).OnChange := @RecentItemsChanged;
  // Accent "File" look purely via StyleClass (no new typeKey); TTyButton draws 'primary'.
  StyleClass := 'primary';
  Caption := 'File';
  // Wide + short like Office's File tab (logical px; LCL scales at paint time).
  Width := TyRibbonAppMenuDefaultWidth;
  Height := TyRibbonAppMenuDefaultHeight;
end;

destructor TTyRibbonAppMenu.Destroy;
begin
  FreeAndNil(FRecentItems);
  // FMenu is owned by Self (would be freed by DestroyComponents), but free it explicitly
  // first so nothing dangling references it during teardown.
  FreeAndNil(FMenu);
  inherited Destroy;
end;

procedure TTyRibbonAppMenu.SetCommands(AValue: TTyPopupMenu);
begin
  if FCommands = AValue then Exit;
  if FCommands <> nil then
    FCommands.RemoveFreeNotification(Self);
  FCommands := AValue;
  if FCommands <> nil then
    FCommands.FreeNotification(Self);
  Invalidate;
end;

procedure TTyRibbonAppMenu.SetRecentItems(AValue: TStrings);
begin
  // Own the storage; assign copies the caller's lines in (we keep our TStringList so the
  // OnChange -> Invalidate hook stays wired and we never alias a list the user may free).
  // Guard nil (TStrings.Assign(nil) raises EConvertError) so `RecentItems := nil` clears.
  if AValue = nil then
    FRecentItems.Clear
  else
    FRecentItems.Assign(AValue);
end;

procedure TTyRibbonAppMenu.RecentItemsChanged(Sender: TObject);
begin
  Invalidate;
end;

procedure TTyRibbonAppMenu.HandleRecentClick(Sender: TObject);
begin
  // The recent clone carries its RecentItems index in Tag; fire the public event with it.
  if not (Sender is TMenuItem) then Exit;
  if Assigned(FOnRecentItemClick) then
    FOnRecentItemClick(Self, Integer(TMenuItem(Sender).Tag));
end;

procedure TTyRibbonAppMenu.RebuildMenu;
var
  i: Integer;
  SrcRoot, Src, Clone, Sep: TMenuItem;
begin
  if FMenu = nil then Exit;
  FMenu.Items.Clear;

  // 1) Copy the top-level command items. Each clone is a fresh TMenuItem owned by FMenu
  //    that carries the source's ACTIVATION HANDLES (OnClick / Action), NOT a raw pointer
  //    back to the source item: so clicking a command still runs the user's handler (or
  //    executes its Action), with no dangling-pointer window if Commands is freed while the
  //    menu is open. A '-' caption stays a separator (IsLine keys off the caption).
  if FCommands <> nil then
  begin
    SrcRoot := FCommands.Items;
    for i := 0 to SrcRoot.Count - 1 do
    begin
      Src := SrcRoot.Items[i];
      Clone := TMenuItem.Create(FMenu);
      Clone.Caption := Src.Caption;
      Clone.Enabled := Src.Enabled;
      Clone.ImageIndex := Src.ImageIndex;
      if not Src.IsLine then
      begin
        if Src.Action <> nil then
          Clone.Action := Src.Action          // the Action drives execute/caption/state
        else
        begin
          Clone.OnClick   := Src.OnClick;      // fires the user's handler directly
          Clone.AutoCheck := Src.AutoCheck;
          Clone.Checked   := Src.Checked;
          Clone.RadioItem := Src.RadioItem;
          Clone.GroupIndex := Src.GroupIndex;
        end;
      end;
      FMenu.Items.Add(Clone);
    end;
  end;

  // 2) Recent-items section: a separator (only when commands precede it) + one item per
  //    entry, each routing to OnRecentItemClick with its 0-based index. Skipped when empty.
  if (FRecentItems <> nil) and (FRecentItems.Count > 0) then
  begin
    if FMenu.Items.Count > 0 then
    begin
      Sep := TMenuItem.Create(FMenu);
      Sep.Caption := '-';
      FMenu.Items.Add(Sep);
    end;
    for i := 0 to FRecentItems.Count - 1 do
    begin
      Clone := TMenuItem.Create(FMenu);
      Clone.Caption := FRecentItems[i];
      Clone.Tag := i;
      Clone.OnClick := @HandleRecentClick;
      FMenu.Items.Add(Clone);
    end;
  end;
end;

function TTyRibbonAppMenu.DroppedMenuItemCount: Integer;
begin
  if FMenu = nil then Result := 0 else Result := FMenu.Items.Count;
end;

function TTyRibbonAppMenu.DroppedMenuItem(AIndex: Integer): TMenuItem;
begin
  if (FMenu = nil) or (AIndex < 0) or (AIndex >= FMenu.Items.Count) then
    Result := nil
  else
    Result := FMenu.Items[AIndex];
end;

procedure TTyRibbonAppMenu.DoDropDown;
begin
  // Compose the internal menu, then let the base drop it: inherited DoDropDown fires
  // OnDropDown and — only with a live window handle — pops DropDownMenu. Route the button
  // at FMenu so the base pops the composed menu, not a user menu we'd otherwise mutate.
  RebuildMenu;
  // Carry the app-menu's controller onto the internal menu so it themes with our theme.
  FMenu.Controller := ActiveController;
  DropDownMenu := FMenu;
  inherited DoDropDown;
end;

procedure TTyRibbonAppMenu.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FCommands) then
    FCommands := nil;
end;

end.
