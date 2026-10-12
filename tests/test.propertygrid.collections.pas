unit test.propertygrid.collections;
{$mode objfpc}{$H+}

{ The property grid (#65), phase 2 Task 2: adding, deleting and moving collection items (plan D2),
  and the ways an application reaches the same (plan D6 (b)).

  Every action goes in the way the user takes it -- Insert, Ctrl+Delete, Ctrl+Up / Ctrl+Down on
  the row, or a right click and an item of the menu -- and every verdict is read off the
  collection itself (and, for a string grid's columns, off the grid the columns belong to). }

interface

uses
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms, Menus, fpcunit, testregistry,
  tyControls.ValueListEditor, tyControls.PropertyGrid, tyControls.Grid, tyControls.Columns,
  tyControls.StrConsts, test.propertygrid.fixtures;

type
  TPropertyGridCollectionsTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FHolder: TPGHolder;
    FAllow: Boolean;
    FLog: TStringList;          // 'changing add 2 2', 'changed delete 0 -1', ...
    FMade: TCollectionItem;
    procedure Changing(Sender: TObject; ACollection: TCollection; AAction: TTyCollectionAction;
      AIndex, ANewIndex: Integer; var AAllow: Boolean);
    procedure Changed(Sender: TObject; ACollection: TCollection; AAction: TTyCollectionAction;
      AIndex, ANewIndex: Integer);
    procedure Make(Sender: TObject; ACollection: TCollection; var AItem: TCollectionItem);
    function Captions: string;
    function Logged: string;
    function Item(AIndex: Integer): TPGItem;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the keys }
    procedure TestInsertOnTheCollectionRowAppends;
    procedure TestInsertOnAnItemAddsRightAfterIt;
    procedure TestCtrlDeleteMovesToTheNextItem;
    procedure TestDeletingTheLastItemLandsOnTheOneBefore;
    procedure TestCtrlUpAndDownMoveTheItem;
    procedure TestCtrlUpOnTheFirstItemDoesNothing;
    procedure TestTheKeysDoNothingOnOtherRowsOrWhenReadOnly;
    { the menu }
    procedure TestTheMenuOnAnItemRow;
    procedure TestTheMenuOnTheCollectionRow;
    procedure TestNoMenuOnOtherRows;
    procedure TestEachMenuItemDoesItsAction;
    { the events, the rows }
    procedure TestOnCollectionChangingRefusesEveryWay;
    procedure TestOnCollectionChangedFollows;
    procedure TestTheExpandedItemsGoWithTheirItems;
    procedure TestOnCreateCollectionItemMakesTheItem;
    { the application's own way in }
    procedure TestTheApplicationsMenuWinsAndThePublicMethodsDoTheSame;
    procedure TestAPathThatIsNoCollectionRaises;
    { a real host }
    procedure TestAStringGridsColumnsFollow;
  end;

implementation

procedure TPropertyGridCollectionsTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FHolder := TPGHolder.Create;
  FLog := TStringList.Create;
  FAllow := True;
  FMade := nil;
  FForm.Show;
  FGrid.SelectedObject := FHolder;
end;

procedure TPropertyGridCollectionsTest.TearDown;
begin
  FForm.Free;
  FHolder.Free;
  FLog.Free;
end;

function ActionName(AAction: TTyCollectionAction): string;
begin
  case AAction of
    caAdd: Result := 'add';
    caDelete: Result := 'delete';
  else
    Result := 'move';
  end;
end;

procedure TPropertyGridCollectionsTest.Changing(Sender: TObject; ACollection: TCollection;
  AAction: TTyCollectionAction; AIndex, ANewIndex: Integer; var AAllow: Boolean);
begin
  AssertSame('the collection itself', FHolder.Items, ACollection);
  FLog.Add(Format('changing %s %d %d', [ActionName(AAction), AIndex, ANewIndex]));
  AAllow := FAllow;
end;

procedure TPropertyGridCollectionsTest.Changed(Sender: TObject; ACollection: TCollection;
  AAction: TTyCollectionAction; AIndex, ANewIndex: Integer);
begin
  FLog.Add(Format('changed %s %d %d (%d items)', [ActionName(AAction), AIndex, ANewIndex,
    ACollection.Count]));
end;

procedure TPropertyGridCollectionsTest.Make(Sender: TObject; ACollection: TCollection;
  var AItem: TCollectionItem);
begin
  FMade := ACollection.Add;
  TPGItem(FMade).Caption := 'made';
  TPGItem(FMade).Size := 5;
  AItem := FMade;
end;

function TPropertyGridCollectionsTest.Captions: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FHolder.Items.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + TPGItem(FHolder.Items.Items[i]).Caption;
  end;
end;

function TPropertyGridCollectionsTest.Logged: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FLog.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + FLog[i];
  end;
end;

function TPropertyGridCollectionsTest.Item(AIndex: Integer): TPGItem;
begin
  Result := TPGItem(FHolder.Items.Items[AIndex]);
end;

{ ================================================================ the keys }

procedure TPropertyGridCollectionsTest.TestInsertOnTheCollectionRowAppends;
begin
  AssertFalse('collapsed to begin with', FGrid.RowAt('Items').Expanded);
  FGrid.Select(FGrid.RowAt('Items'));
  FGrid.Press(VK_INSERT);
  AssertEquals('a third item', 3, FHolder.Items.Count);
  AssertEquals('at the end', 'first,second,', Captions);
  AssertEquals('the row counts it', Format(rsTyPropGridItems, [3]), FGrid.RowAt('Items').Value);
  AssertTrue('the collection opened to show it', FGrid.RowAt('Items').Expanded);
  AssertSame('and the new item''s row is current', FGrid.RowAt('Items.[2]'), FGrid.CurrentRow);
end;

procedure TPropertyGridCollectionsTest.TestInsertOnAnItemAddsRightAfterIt;
begin
  FGrid.Select(FGrid.RowAt('Items.[0]'));
  FGrid.Press(VK_INSERT);
  AssertEquals('after the first', 'first,,second', Captions);
  AssertSame('the new row is current', FGrid.RowAt('Items.[1]'), FGrid.CurrentRow);
  FGrid.TypeInto(FGrid.RowAt('Items.[1].Caption'), 'between');
  AssertEquals('and it is the new item that the rows edit', 'first,between,second', Captions);
end;

procedure TPropertyGridCollectionsTest.TestCtrlDeleteMovesToTheNextItem;
begin
  FGrid.Select(FGrid.RowAt('Items.[0]'));
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('the first is gone', 'second', Captions);
  AssertSame('the next item -- now [0] -- is current', FGrid.RowAt('Items.[0]'), FGrid.CurrentRow);
  AssertEquals('which is second', 'second', FGrid.CurrentRow.Value);
  AssertEquals('one row left under Items', 1, FGrid.RowAt('Items').ChildCount);
end;

procedure TPropertyGridCollectionsTest.TestDeletingTheLastItemLandsOnTheOneBefore;
begin
  FGrid.Select(FGrid.RowAt('Items.[1]'));
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('second is gone', 'first', Captions);
  AssertNotNull('a row is current', FGrid.CurrentRow);
  AssertSame('no next one: the one before', FGrid.RowAt('Items.[0]'), FGrid.CurrentRow);
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('empty', 0, FHolder.Items.Count);
  AssertSame('none at all: the collection''s row', FGrid.RowAt('Items'), FGrid.CurrentRow);
end;

procedure TPropertyGridCollectionsTest.TestCtrlUpAndDownMoveTheItem;
var it: TPGItem;
begin
  it := TPGItem(FHolder.Items.Add);
  it.Caption := 'third';
  FGrid.Refresh;
  FGrid.Select(FGrid.RowAt('Items.[2]'));
  FGrid.Press(VK_UP, [ssModifier]);
  AssertEquals('third moved up one', 'first,third,second', Captions);
  AssertSame('the same item object', it, FHolder.Items.Items[1]);
  AssertSame('the current row follows it', FGrid.RowAt('Items.[1]'), FGrid.CurrentRow);
  FGrid.Press(VK_UP, [ssModifier]);
  AssertEquals('and up again', 'third,first,second', Captions);
  FGrid.Press(VK_DOWN, [ssModifier]);
  FGrid.Press(VK_DOWN, [ssModifier]);
  AssertEquals('down twice: last again', 'first,second,third', Captions);
  AssertSame('still on it', FGrid.RowAt('Items.[2]'), FGrid.CurrentRow);
end;

procedure TPropertyGridCollectionsTest.TestCtrlUpOnTheFirstItemDoesNothing;
begin
  FGrid.OnCollectionChanging := @Changing;
  FGrid.Select(FGrid.RowAt('Items.[0]'));
  FGrid.Press(VK_UP, [ssModifier]);
  AssertEquals('nothing moved', 'first,second', Captions);
  AssertEquals('nobody was asked about a move to nowhere', 0, FLog.Count);
  AssertSame('and the selection did not walk up to Items either', FGrid.RowAt('Items.[0]'),
    FGrid.CurrentRow);
  FGrid.Select(FGrid.RowAt('Items.[1]'));
  FGrid.Press(VK_DOWN, [ssModifier]);
  AssertEquals('nor past the end', 'first,second', Captions);
  AssertEquals('still nobody asked', 0, FLog.Count);
end;

procedure TPropertyGridCollectionsTest.TestTheKeysDoNothingOnOtherRowsOrWhenReadOnly;
begin
  FGrid.Select(FGrid.RowAt('Flags'));
  FGrid.Press(VK_INSERT);
  AssertEquals('Insert on another row: nothing', 2, FHolder.Items.Count);
  FGrid.Select(FGrid.RowAt('Items'));
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('Ctrl+Delete on the collection row itself: nothing', 2, FHolder.Items.Count);
  FGrid.ReadOnly := True;
  FGrid.Press(VK_INSERT);
  AssertEquals('ReadOnly: Insert does nothing', 2, FHolder.Items.Count);
  FGrid.Select(FGrid.RowAt('Items.[0]'));
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('nor Ctrl+Delete', 2, FHolder.Items.Count);
  AssertFalse('nor is there a menu', FGrid.RightClick(FGrid.RowAt('Items.[0]')));
end;

{ ================================================================ the menu }

procedure TPropertyGridCollectionsTest.TestTheMenuOnAnItemRow;
begin
  FGrid.Select(FGrid.RowAt('Flags'));
  AssertTrue('the grid takes a right click on an item', FGrid.RightClick(FGrid.RowAt('Items.[0]')));
  AssertEquals('and shows its menu once', 1, FGrid.MenusShown);
  AssertSame('the row clicked became current', FGrid.RowAt('Items.[0]'), FGrid.CurrentRow);
  AssertTrue('Add', FGrid.MenuItem(rsTyPropGridAddItem).Enabled);
  AssertTrue('Delete', FGrid.MenuItem(rsTyPropGridDeleteItem).Enabled);
  AssertFalse('Move Up: already the first', FGrid.MenuItem(rsTyPropGridMoveUp).Enabled);
  AssertTrue('Move Down', FGrid.MenuItem(rsTyPropGridMoveDown).Enabled);
  AssertEquals('the keys shown beside them', ShortCut(VK_DELETE, [ssModifier]),
    FGrid.MenuItem(rsTyPropGridDeleteItem).ShortCut);
  FGrid.RightClick(FGrid.RowAt('Items.[1]'));
  AssertTrue('Move Up on the last', FGrid.MenuItem(rsTyPropGridMoveUp).Enabled);
  AssertFalse('Move Down: already the last', FGrid.MenuItem(rsTyPropGridMoveDown).Enabled);
end;

procedure TPropertyGridCollectionsTest.TestTheMenuOnTheCollectionRow;
begin
  AssertTrue('taken', FGrid.RightClick(FGrid.RowAt('Items')));
  AssertTrue('Add', FGrid.MenuItem(rsTyPropGridAddItem).Enabled);
  AssertFalse('no item to delete', FGrid.MenuItem(rsTyPropGridDeleteItem).Enabled);
  AssertFalse('nor to move', FGrid.MenuItem(rsTyPropGridMoveUp).Enabled);
  AssertFalse('either way', FGrid.MenuItem(rsTyPropGridMoveDown).Enabled);
  FGrid.PickMenu(rsTyPropGridDeleteItem);
  AssertEquals('a disabled item does nothing', 2, FHolder.Items.Count);
end;

procedure TPropertyGridCollectionsTest.TestNoMenuOnOtherRows;
begin
  AssertFalse('a set row is left alone', FGrid.RightClick(FGrid.RowAt('Flags')));
  AssertFalse('so is an item''s property', FGrid.RightClick(FGrid.RowAt('Items.[0].Size')));
  AssertEquals('no menu shown', 0, FGrid.MenusShown);
end;

procedure TPropertyGridCollectionsTest.TestEachMenuItemDoesItsAction;
begin
  FGrid.RightClick(FGrid.RowAt('Items.[1]'));
  FGrid.PickMenu(rsTyPropGridMoveUp);
  AssertEquals('Move Up', 'second,first', Captions);
  FGrid.RightClick(FGrid.RowAt('Items.[0]'));
  FGrid.PickMenu(rsTyPropGridMoveDown);
  AssertEquals('Move Down', 'first,second', Captions);
  FGrid.RightClick(FGrid.RowAt('Items.[0]'));
  FGrid.PickMenu(rsTyPropGridAddItem);
  AssertEquals('Add Item: after the item clicked', 'first,,second', Captions);
  AssertSame('current: the new one', FGrid.RowAt('Items.[1]'), FGrid.CurrentRow);
  FGrid.RightClick(FGrid.RowAt('Items.[2]'));
  FGrid.PickMenu(rsTyPropGridDeleteItem);
  AssertEquals('Delete Item', 'first,', Captions);
  FGrid.RightClick(FGrid.RowAt('Items'));
  FGrid.PickMenu(rsTyPropGridAddItem);
  AssertEquals('Add Item on the collection: at the end', 3, FHolder.Items.Count);
end;

{ ================================================================ the events, the rows }

procedure TPropertyGridCollectionsTest.TestOnCollectionChangingRefusesEveryWay;
begin
  FGrid.OnCollectionChanging := @Changing;
  FGrid.OnCollectionChanged := @Changed;
  FAllow := False;
  FGrid.Select(FGrid.RowAt('Items'));
  FGrid.Press(VK_INSERT);
  FGrid.Select(FGrid.RowAt('Items.[0]'));
  FGrid.Press(VK_INSERT);
  FGrid.Press(VK_DELETE, [ssModifier]);
  FGrid.Press(VK_DOWN, [ssModifier]);
  FGrid.RightClick(FGrid.RowAt('Items.[1]'));
  FGrid.PickMenu(rsTyPropGridDeleteItem);
  FGrid.RightClick(FGrid.RowAt('Items.[1]'));
  FGrid.PickMenu(rsTyPropGridMoveUp);
  FGrid.RightClick(FGrid.RowAt('Items'));
  FGrid.PickMenu(rsTyPropGridAddItem);
  AssertNull('the method returns nil', FGrid.AddCollectionItem('Items'));
  FGrid.DeleteCollectionItem('Items[0]');
  FGrid.MoveCollectionItem('Items[0]', 1);
  AssertEquals('refused: the collection is as it was', 'first,second', Captions);
  AssertEquals('asked each time, never announced',
    'changing add 2 2,changing add 1 1,changing delete 0 -1,changing move 0 1,'
    + 'changing delete 1 -1,changing move 1 0,changing add 2 2,'
    + 'changing add 2 2,changing delete 0 -1,changing move 0 1',
    Logged);
end;

procedure TPropertyGridCollectionsTest.TestOnCollectionChangedFollows;
begin
  FGrid.OnCollectionChanging := @Changing;
  FGrid.OnCollectionChanged := @Changed;
  FGrid.Select(FGrid.RowAt('Items.[1]'));
  FGrid.Press(VK_UP, [ssModifier]);
  FGrid.Press(VK_INSERT);
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('asked, then told, with the indexes',
    'changing move 1 0,changed move 1 0 (2 items),'
    + 'changing add 1 1,changed add 1 1 (3 items),'
    + 'changing delete 1 -1,changed delete 1 -1 (2 items)',
    Logged);
end;

procedure TPropertyGridCollectionsTest.TestTheExpandedItemsGoWithTheirItems;
var it: TPGItem;
begin
  it := TPGItem(FHolder.Items.Add);
  it.Caption := 'third';
  FGrid.Refresh;
  FGrid.ExpandedProperties.Add('Inner');
  FGrid.ExpandedProperties.Add('Items');
  FGrid.ExpandedProperties.Add('Items[2]');
  AssertTrue('third is open', FGrid.RowAt('Items.[2]').Expanded);
  FGrid.Select(FGrid.RowAt('Items.[2]'));
  FGrid.Press(VK_UP, [ssModifier]);
  AssertTrue('it is still open where it went', FGrid.RowAt('Items.[1]').Expanded);
  AssertEquals('which is third', 'third', FGrid.RowAt('Items.[1]').Value);
  AssertFalse('second, now last, stays shut', FGrid.RowAt('Items.[2]').Expanded);
  AssertTrue('the paths say so', FGrid.ExpandedProperties.IndexOf('Items[1]') >= 0);
  AssertTrue('and only so', FGrid.ExpandedProperties.IndexOf('Items[2]') < 0);
  AssertTrue('the rest keep theirs', FGrid.RowAt('Inner').Expanded);
  FGrid.Select(FGrid.RowAt('Items.[0]'));
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertTrue('a delete before it shifts it down', FGrid.RowAt('Items.[0]').Expanded);
  AssertEquals('third', 'third', FGrid.RowAt('Items.[0]').Value);
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertTrue('and deleting it takes its path away', FGrid.ExpandedProperties.IndexOf('Items[0]') < 0);
end;

procedure TPropertyGridCollectionsTest.TestOnCreateCollectionItemMakesTheItem;
var got: TCollectionItem;
begin
  FGrid.OnCreateCollectionItem := @Make;
  got := FGrid.AddCollectionItem('Items[0]');
  AssertNotNull('the handler made one', FMade);
  AssertSame('and that is the item added', FMade, got);
  AssertEquals('put where it was asked for: after the first', 'first,made,second', Captions);
  AssertEquals('with the handler''s values', 5, Item(1).Size);
  FGrid.Select(FGrid.RowAt('Items'));
  FGrid.Press(VK_INSERT);
  AssertSame('the key goes through it too', FMade, FHolder.Items.Items[3]);
  FGrid.OnCreateCollectionItem := nil;
  FGrid.Press(VK_INSERT);
  AssertEquals('without it, the collection''s own Add', 5, FHolder.Items.Count);
end;

{ ================================================================ the application's own way in }

procedure TPropertyGridCollectionsTest.TestTheApplicationsMenuWinsAndThePublicMethodsDoTheSame;
var inst: TPersistent; nm, path: string;
begin
  FGrid.PopupMenu := TPopupMenu.Create(FForm);
  AssertFalse('the application''s PopupMenu: the grid leaves the click to it',
    FGrid.RightClick(FGrid.RowAt('Items.[0]')));
  AssertEquals('its own menu is not shown', 0, FGrid.MenusShown);
  { What the application's menu does with the row it was opened on. }
  FGrid.Select(FGrid.RowAt('Items.[0]'));
  AssertFalse('an item''s row is no property', FGrid.PropertyAt(FGrid.SelectedRow, inst, nm));
  path := FGrid.RowPath(FGrid.SelectedRow);
  AssertEquals('but it has a path', 'Items[0]', path);
  FGrid.MoveCollectionItem(path, 1);
  AssertEquals('moved', 'second,first', Captions);
  AssertEquals('the selection followed it', 'Items[1]', FGrid.RowPath(FGrid.SelectedRow));
  FGrid.DeleteCollectionItem(FGrid.RowPath(FGrid.SelectedRow));
  AssertEquals('deleted', 'second', Captions);
  AssertNotNull('added', FGrid.AddCollectionItem('Items'));
  AssertEquals('added at the end', 2, FHolder.Items.Count);
  AssertTrue('a property row''s path too', FGrid.PropertyAt(FGrid.RowAt('Items.[0].Size'), inst, nm));
  AssertEquals('Size', 'Size', nm);
  AssertEquals('Items[0].Size', FGrid.RowPath(FGrid.RowAt('Items.[0].Size')));
end;

procedure TPropertyGridCollectionsTest.TestAPathThatIsNoCollectionRaises;
var raised: Boolean;
begin
  raised := False;
  try
    FGrid.AddCollectionItem('Flags');
  except
    on E: EPropertyError do raised := True;
  end;
  AssertTrue('a set is no collection', raised);
  raised := False;
  try
    FGrid.DeleteCollectionItem('Items');
  except
    on E: EPropertyError do raised := True;
  end;
  AssertTrue('the collection is no item', raised);
  raised := False;
  try
    FGrid.MoveCollectionItem('Items[7]', 1);
  except
    on E: EPropertyError do raised := True;
  end;
  AssertTrue('nor is an item that is not there', raised);
  AssertEquals('nothing changed', 'first,second', Captions);
end;

{ ================================================================ a real host }

{ The string grid's columns are Header.Columns. Added, deleted and moved from the property grid,
  the grid itself must follow: its column count, and its cell geometry -- a column of 70 moved
  in front of a column of 50 makes the cell at that index 70 wide. }
procedure TPropertyGridCollectionsTest.TestAStringGridsColumnsFollow;
var sg: TTyStringGrid; c: TTyColumn;

  procedure AddColumn(const AText: string; AWidth: Integer);
  begin
    c := sg.Header.Columns.Add as TTyColumn;
    c.Text := AText;
    c.Width := AWidth;
  end;

  function W(ACol: Integer): Integer;
  begin
    Result := sg.CellRect(ACol, 0).Right - sg.CellRect(ACol, 0).Left;
  end;

  function Texts: string;
  var i: Integer;
  begin
    Result := '';
    for i := 0 to sg.Header.Columns.Count - 1 do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + sg.Header.Columns[i].Text;
    end;
  end;

begin
  sg := TTyStringGrid.Create(FForm);
  sg.Parent := FForm;
  sg.SetBounds(0, 0, 300, 200);
  sg.RowCount := 2;
  AddColumn('A', 40);
  AddColumn('B', 50);
  AddColumn('C', 70);
  FGrid.SelectedObject := sg;
  FGrid.ExpandedProperties.Add('Header');
  FGrid.ExpandedProperties.Add('Header.Columns');
  AssertTrue('B narrower than C to begin with', W(1) < W(2));
  FGrid.Select(FGrid.RowAt('Header.Columns.[2]'));
  FGrid.Press(VK_UP, [ssModifier]);
  AssertEquals('C moved in front of B', 'A,C,B', Texts);
  AssertTrue('and the grid''s cells follow: index 1 is now the wide one', W(1) > W(2));
  AssertSame('the row follows the column', FGrid.RowAt('Header.Columns.[1]'), FGrid.CurrentRow);
  FGrid.Press(VK_INSERT);
  AssertEquals('a fourth column, after C', 4, sg.Header.Columns.Count);
  AssertTrue('and the grid has a cell for it', W(3) > 0);
  FGrid.Select(FGrid.RowAt('Header.Columns.[0]'));
  FGrid.Press(VK_DELETE, [ssModifier]);
  AssertEquals('A deleted: three left', 3, sg.Header.Columns.Count);
  AssertEquals('C first now', 'C', sg.Header.Columns[0].Text);
  AssertTrue('and the grid knows: no cell past the last column', W(3) = 0);
  FGrid.SelectedObject := nil;
end;

initialization
  RegisterTest(TPropertyGridCollectionsTest);
end.
