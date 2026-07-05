unit test.ribbonappmenu;
{$mode objfpc}{$H+}
{ Headless fpcunit tests for tyControls.RibbonAppMenu (TTyRibbonAppMenu — the ribbon's
  accent "File" application-menu button). The live PopUp needs a GUI, so the tests drive
  the pure/headless seams only:
    - typeKey stays 'TyButton' (inherited, no new .tycss); default Caption/StyleClass.
    - RecentItems round-trip; Commands FreeNotification nils it.
    - RebuildMenu (a protected seam, invoked directly WITHOUT a GUI pop) composes the
      internal menu: FMenu.Items.Count = command count + (1 separator + recent count) when
      RecentItems is non-empty, = command count when empty, and 0 when Commands is nil.
    - Choosing a recent row (invoking its clone's OnClick) fires OnRecentItemClick with the
      right index; choosing a command row re-fires the source command's OnClick. }
interface
uses
  Classes, SysUtils, TypInfo, Menus, fpcunit, testregistry,
  tyControls.Base, tyControls.Menu, tyControls.DropButtons, tyControls.RibbonAppMenu;

type
  { Probe subclass surfacing the protected RebuildMenu + the composed-menu inspection seams
    (inherited protected) as public wrappers, so the test can compose the dropdown and walk
    its item tree without a live PopUp. }
  TAppMenuAccess = class(TTyRibbonAppMenu)
  public
    procedure DoRebuild;
    function ItemCount: Integer;
    function ItemAt(AIndex: Integer): TMenuItem;
  end;

  TRibbonAppMenuTest = class(TTestCase)
  private
    FRecentIndex: Integer;   // last AIndex reported by OnRecentItemClick, or -1
    FRecentCount: Integer;   // number of OnRecentItemClick fires
    FCmdFired: Integer;      // number of source-command OnClick re-fires
    procedure HandleRecent(Sender: TObject; AIndex: Integer);
    procedure HandleCommand(Sender: TObject);
    { Build a TTyPopupMenu with ACount top-level command items (captions Cmd0..CmdN-1),
      each wired to HandleCommand. Owned by AOwner. }
    function MakeCommands(AOwner: TComponent; ACount: Integer): TTyPopupMenu;
  published
    procedure TestTypeKeyReusesButton;
    procedure TestDefaultCaptionAndStyleClass;
    procedure TestRecentItemsRoundTrip;
    procedure TestRecentItemsNilAssignIsSafe;
    procedure TestCommandsFreeNotificationNilsIt;
    procedure TestRebuildComposesCommandsPlusRecent;
    procedure TestRebuildCommandsOnlyWhenRecentEmpty;
    procedure TestRebuildNilCommandsIsSafe;
    procedure TestRecentClickFiresEventWithIndex;
    procedure TestCommandClickReFiresSourceOnClick;
  end;

implementation

{ TAppMenuAccess }

procedure TAppMenuAccess.DoRebuild;
begin
  RebuildMenu;
end;

function TAppMenuAccess.ItemCount: Integer;
begin
  Result := DroppedMenuItemCount;   // inherited protected, reachable from a descendant method
end;

function TAppMenuAccess.ItemAt(AIndex: Integer): TMenuItem;
begin
  Result := DroppedMenuItem(AIndex);
end;

{ TRibbonAppMenuTest }

procedure TRibbonAppMenuTest.HandleRecent(Sender: TObject; AIndex: Integer);
begin
  FRecentIndex := AIndex;
  Inc(FRecentCount);
end;

procedure TRibbonAppMenuTest.HandleCommand(Sender: TObject);
begin
  Inc(FCmdFired);
end;

function TRibbonAppMenuTest.MakeCommands(AOwner: TComponent; ACount: Integer): TTyPopupMenu;
var
  i: Integer;
  Mi: TMenuItem;
begin
  Result := TTyPopupMenu.Create(AOwner);
  for i := 0 to ACount - 1 do
  begin
    Mi := TMenuItem.Create(Result);
    Mi.Caption := 'Cmd' + IntToStr(i);
    Mi.OnClick := @HandleCommand;
    Result.Items.Add(Mi);
  end;
end;

procedure TRibbonAppMenuTest.TestTypeKeyReusesButton;
var B: TTyRibbonAppMenu;
begin
  B := TTyRibbonAppMenu.Create(nil);
  try
    // Reuses the TyButton token (accent look comes from StyleClass, not a new typeKey).
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestDefaultCaptionAndStyleClass;
var B: TTyRibbonAppMenu;
begin
  B := TTyRibbonAppMenu.Create(nil);
  try
    AssertEquals('default caption', 'File', B.Caption);
    AssertEquals('default StyleClass is primary (accent)', 'primary', B.StyleClass);
    AssertTrue('Commands published', IsPublishedProp(B, 'Commands'));
    AssertTrue('RecentItems published', IsPublishedProp(B, 'RecentItems'));
    AssertTrue('OnRecentItemClick published', IsPublishedProp(B, 'OnRecentItemClick'));
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestRecentItemsRoundTrip;
var B: TTyRibbonAppMenu;
begin
  B := TTyRibbonAppMenu.Create(nil);
  try
    B.RecentItems.Add('a.txt');
    B.RecentItems.Add('b.txt');
    AssertEquals('recent count round-trips', 2, B.RecentItems.Count);
    AssertEquals('recent[0]', 'a.txt', B.RecentItems[0]);
    AssertEquals('recent[1]', 'b.txt', B.RecentItems[1]);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestCommandsFreeNotificationNilsIt;
var
  B: TTyRibbonAppMenu;
  M: TTyPopupMenu;
begin
  B := TTyRibbonAppMenu.Create(nil);
  try
    M := TTyPopupMenu.Create(nil);
    B.Commands := M;
    AssertSame('commands wired', M, B.Commands);
    M.Free;   // FreeNotification must nil the reference
    AssertTrue('freeing the commands menu nils Commands', B.Commands = nil);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestRebuildComposesCommandsPlusRecent;
var
  B: TAppMenuAccess;
  M: TTyPopupMenu;
begin
  // 3 commands + 2 recent => 3 + (1 separator + 2) = 6 rows, WITHOUT a GUI pop.
  B := TAppMenuAccess.Create(nil);
  try
    M := MakeCommands(B, 3);
    B.Commands := M;
    B.RecentItems.Add('r0');
    B.RecentItems.Add('r1');
    B.DoRebuild;
    AssertEquals('commands + separator + recent', 6, B.ItemCount);
    // The separator sits between the last command and the first recent row.
    AssertTrue('row 3 is the separator', B.ItemAt(3).IsLine);
    AssertEquals('first recent caption', 'r0', B.ItemAt(4).Caption);
    AssertEquals('second recent caption', 'r1', B.ItemAt(5).Caption);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestRebuildCommandsOnlyWhenRecentEmpty;
var
  B: TAppMenuAccess;
  M: TTyPopupMenu;
begin
  // 3 commands + 0 recent => exactly 3 rows (no separator, no recent section).
  B := TAppMenuAccess.Create(nil);
  try
    M := MakeCommands(B, 3);
    B.Commands := M;
    B.DoRebuild;
    AssertEquals('no recent -> only the commands', 3, B.ItemCount);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestRecentItemsNilAssignIsSafe;
var B: TAppMenuAccess;
begin
  // Regression: `RecentItems := nil` must clear (not raise EConvertError from Assign(nil)).
  B := TAppMenuAccess.Create(nil);
  try
    B.RecentItems.Add('a');
    B.RecentItems.Add('b');
    B.RecentItems := nil;   // must not raise
    AssertEquals('nil assign cleared the list', 0, B.RecentItems.Count);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestRebuildNilCommandsIsSafe;
var B: TAppMenuAccess;
begin
  // Commands=nil, no recent -> empty menu, no crash.
  B := TAppMenuAccess.Create(nil);
  try
    B.DoRebuild;
    AssertEquals('nil commands + empty recent -> 0 rows', 0, B.ItemCount);
    // Now nil commands but WITH recent -> just the recent rows, NO leading separator
    // (the separator only appears when commands precede it).
    B.RecentItems.Add('only-recent');
    B.DoRebuild;
    AssertEquals('nil commands + 1 recent -> just the 1 recent row', 1, B.ItemCount);
    AssertEquals('recent caption', 'only-recent', B.ItemAt(0).Caption);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestRecentClickFiresEventWithIndex;
var
  B: TAppMenuAccess;
  Row: TMenuItem;
begin
  // Choosing a recent row (invoking its clone's OnClick) fires OnRecentItemClick with the
  // matching RecentItems index.
  FRecentIndex := -1;
  FRecentCount := 0;
  B := TAppMenuAccess.Create(nil);
  try
    B.OnRecentItemClick := @HandleRecent;
    B.RecentItems.Add('r0');
    B.RecentItems.Add('r1');
    B.RecentItems.Add('r2');
    B.DoRebuild;
    // No commands: rows are [r0, r1, r2] (no leading separator). r1 is at index 1.
    Row := B.ItemAt(1);
    AssertEquals('picked the r1 row', 'r1', Row.Caption);
    Row.Click;   // fires the clone's OnClick -> HandleRecentClick -> OnRecentItemClick
    AssertEquals('OnRecentItemClick fired once', 1, FRecentCount);
    AssertEquals('reported the r1 index (1)', 1, FRecentIndex);
  finally
    B.Free;
  end;
end;

procedure TRibbonAppMenuTest.TestCommandClickReFiresSourceOnClick;
var
  B: TAppMenuAccess;
  M: TTyPopupMenu;
begin
  // Choosing a copied command row re-fires the SOURCE command's OnClick (the user's
  // handler still runs) — nothing the user owns was mutated.
  FCmdFired := 0;
  B := TAppMenuAccess.Create(nil);
  try
    M := MakeCommands(B, 2);
    B.Commands := M;
    B.DoRebuild;
    B.ItemAt(0).Click;   // clone of Cmd0 -> HandleCommandClick -> source OnClick
    AssertEquals('source command OnClick re-fired once', 1, FCmdFired);
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TRibbonAppMenuTest);
end.
