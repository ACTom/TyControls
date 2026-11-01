unit test.propertygrid.objects;
{$mode objfpc}{$H+}

{ The property grid (#65), part 2: the properties that are more than one value -- sets, sub-objects
  and csSubComponent parts, collections and their items, a TFont written back whole, references to
  other components, TStrings through a dialog -- on hand-written fixtures and on a real TTyButton
  sitting on a form with an Owner.

  As in part 1, every edit goes in the way the user makes it and every verdict is read off the
  inspected object. }

interface

uses
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms, Menus, fpcunit, testregistry,
  tyControls.ListBox, tyControls.ValueListEditor, tyControls.PropertyGrid, tyControls.Button,
  tyControls.Edit, tyControls.StrConsts, test.propertygrid.fixtures;

type
  TPropertyGridObjectsTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FHolder: TPGHolder;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestASetShowsItsElements;
    procedure TestSpaceOnAnElementWritesTheSet;
    procedure TestPickingAnElementWritesTheSet;
    procedure TestASetWithoutASetterHasReadOnlyElements;
    procedure TestASetOfAnIntegerRangeNamesItsNumbers;
    procedure TestASubObjectWithoutASetterStillExpandsAndWrites;
    procedure TestACollectionListsItsItems;
    procedure TestAnItemPropertyIsWrittenToThatItem;
    procedure TestTheStringsDialogWritesThroughTheSetter;
    procedure TestTheStringsDialogAssignsWhenThereIsNoSetter;
    procedure TestACancelledStringsDialogWritesNothing;
    procedure TestACycleStopsAtTheDepthLimit;
    procedure TestASubComponentIsExpandedNotReferenced;
  end;

  { A real control on a real form: Font, Constraints, Anchors, PopupMenu. }
  TPropertyGridButtonTest = class(TTestCase)
  private
    FForm: TForm;
    FButton: TTyButton;
    FPop1, FPop2, FPop3: TPopupMenu;
    FElsewhere: TComponent;
    FGrid: TPGGrid;
    FAnswer: TFont;
    procedure AddForeignMenu(Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo;
      AList: TStrings);
    function Lines(const AText: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPopupMenuOffersTheOwnersMenusOnly;
    procedure TestPickingAMenuSetsTheReference;
    procedure TestOnGetComponentNamesCanOfferAForeignMenu;
    procedure TestAForeignCurrentValueIsListed;
    procedure TestWithoutAnOwnerOnlyNoneAndTheCurrentValue;
    procedure TestAnchorsElementWritesTheSet;
    procedure TestFontSizeRowWritesTheFont;
    procedure TestFontStyleElementWritesTheFont;
    procedure TestTheFontDialogWritesTheWholeFont;
    procedure TestACancelledFontDialogWritesNothing;
    procedure TestTheFontDialogStartsFromTheButtonsFont;
    procedure TestConstraintsExpandAndWrite;
  end;

implementation

{ ================================================================ fixtures }

procedure TPropertyGridObjectsTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FHolder := TPGHolder.Create;
  FForm.Show;
  FGrid.SelectedObject := FHolder;
end;

procedure TPropertyGridObjectsTest.TearDown;
begin
  FForm.Free;
  FHolder.Free;
end;

procedure TPropertyGridObjectsTest.TestASetShowsItsElements;
var r: TTyValueRow;
begin
  r := FGrid.RowAt('Flags');
  AssertEquals('the set in brackets', '[pfA,pfC]', r.Value);
  AssertTrue('the set row itself is not typed into', r.ReadOnly);
  AssertEquals('one child per element', 4, r.ChildCount);
  AssertEquals('pfA', 'True', FGrid.RowAt('Flags.pfA').Value);
  AssertEquals('pfB', 'False', FGrid.RowAt('Flags.pfB').Value);
  AssertEquals('pfC', 'True', FGrid.RowAt('Flags.pfC').Value);
  AssertEquals('pfD', 'False', FGrid.RowAt('Flags.pfD').Value);
  AssertTrue('an element is a boolean', FGrid.RowAt('Flags.pfB').EditorKind = vekBoolean);
  AssertFalse('and editable', FGrid.RowAt('Flags.pfB').ReadOnly);
end;

procedure TPropertyGridObjectsTest.TestSpaceOnAnElementWritesTheSet;
begin
  FGrid.Select(FGrid.RowAt('Flags.pfB'));
  FGrid.Press(VK_SPACE);
  AssertTrue('the object''s set gained pfB', FHolder.Flags = [pfA, pfB, pfC]);
  AssertEquals('the element row', 'True', FGrid.RowAt('Flags.pfB').Value);
  AssertEquals('and the set row was recomputed', '[pfA,pfB,pfC]', FGrid.RowAt('Flags').Value);
end;

procedure TPropertyGridObjectsTest.TestPickingAnElementWritesTheSet;
begin
  FGrid.PickFromDropdown(FGrid.RowAt('Flags.pfA'), 'False');
  AssertTrue('pfA is gone from the object''s set', FHolder.Flags = [pfC]);
  AssertEquals('set row', '[pfC]', FGrid.RowAt('Flags').Value);
end;

procedure TPropertyGridObjectsTest.TestASetWithoutASetterHasReadOnlyElements;
begin
  AssertEquals('shown', '[pfB]', FGrid.RowAt('FixedFlags').Value);
  AssertTrue('its elements are read-only', FGrid.RowAt('FixedFlags.pfA').ReadOnly);
  FGrid.Select(FGrid.RowAt('FixedFlags.pfA'));
  FGrid.Press(VK_SPACE);
  AssertTrue('Space changes nothing', FHolder.FixedFlags = [pfB]);
end;

procedure TPropertyGridObjectsTest.TestASetOfAnIntegerRangeNamesItsNumbers;
begin
  AssertEquals('numbers, not enum names', '[1,3]', FGrid.RowAt('Nums').Value);
  AssertEquals('eight elements', 8, FGrid.RowAt('Nums').ChildCount);
  FGrid.Select(FGrid.RowAt('Nums.7'));
  FGrid.Press(VK_SPACE);
  AssertTrue('7 joined', FHolder.Nums = [1, 3, 7]);
  AssertEquals('row', '[1,3,7]', FGrid.RowAt('Nums').Value);
end;

procedure TPropertyGridObjectsTest.TestASubObjectWithoutASetterStillExpandsAndWrites;
var r: TTyValueRow;
begin
  r := FGrid.RowAt('Inner');
  AssertEquals('the class name', '(TPGInner)', r.Value);
  AssertTrue('the object row is read-only', r.ReadOnly);
  AssertFalse('collapsed until asked', r.Expanded);
  AssertEquals('its properties are its children', '5', FGrid.RowAt('Inner.Level').Value);
  FGrid.TypeInto(FGrid.RowAt('Inner.Level'), '8');
  AssertEquals('written into the sub-object', 8, FHolder.Inner.Level);
end;

procedure TPropertyGridObjectsTest.TestACollectionListsItsItems;
var r: TTyValueRow;
begin
  r := FGrid.RowAt('Items');
  AssertEquals('the count', Format(rsTyPropGridItems, [2]), r.Value);
  AssertTrue('read-only', r.ReadOnly);
  AssertEquals('one child per item', 2, r.ChildCount);
  AssertEquals('an item shows its DisplayName', 'first', FGrid.RowAt('Items.[0]').Value);
  AssertEquals('second', 'second', FGrid.RowAt('Items.[1]').Value);
  AssertEquals('and expands into its properties', '20', FGrid.RowAt('Items.[1].Size').Value);
end;

procedure TPropertyGridObjectsTest.TestAnItemPropertyIsWrittenToThatItem;
begin
  FGrid.TypeInto(FGrid.RowAt('Items.[1].Size'), '77');
  AssertEquals('item 1 took it', 77, TPGItem(FHolder.Items.Items[1]).Size);
  AssertEquals('item 0 did not', 10, TPGItem(FHolder.Items.Items[0]).Size);
  FGrid.TypeInto(FGrid.RowAt('Items.[1].Caption'), 'renamed');
  AssertEquals('item 1''s caption', 'renamed', TPGItem(FHolder.Items.Items[1]).Caption);
  AssertEquals('item 0''s caption untouched', 'first', TPGItem(FHolder.Items.Items[0]).Caption);
  AssertEquals('the item row re-read its DisplayName', 'renamed', FGrid.RowAt('Items.[1]').Value);
end;

procedure TPropertyGridObjectsTest.TestTheStringsDialogWritesThroughTheSetter;
begin
  FGrid.StringsAccept := True;
  FGrid.StringsAnswer := 'alpha' + LineEnding + 'beta' + LineEnding + 'gamma';
  AssertTrue('a TStrings row is a dialog row', FGrid.RowAt('Lines').EditorKind = vekDialog);
  FGrid.ClickValue(FGrid.RowAt('Lines'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('the dialog opened once', 1, FGrid.StringsDialogs);
  AssertEquals('titled after the property', Format(rsTyPropGridStringsTitle, ['Lines']),
    FGrid.StringsTitle);
  AssertEquals('handed the current lines', 'one' + LineEnding + 'two' + LineEnding, FGrid.StringsSeen);
  AssertEquals('through the setter', 1, FHolder.LinesSets);
  AssertEquals('three lines now', 3, FHolder.Lines.Count);
  AssertEquals('gamma last', 'gamma', FHolder.Lines[2]);
end;

procedure TPropertyGridObjectsTest.TestTheStringsDialogAssignsWhenThereIsNoSetter;
begin
  FGrid.StringsAccept := True;
  FGrid.StringsAnswer := 'x' + LineEnding + 'y';
  AssertFalse('no setter, still editable: the list is written in place', FGrid.RowAt('Notes').ReadOnly);
  FGrid.ClickValue(FGrid.RowAt('Notes'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('two lines', 2, FHolder.Notes.Count);
  AssertEquals('y', 'y', FHolder.Notes[1]);
end;

procedure TPropertyGridObjectsTest.TestACancelledStringsDialogWritesNothing;
begin
  FGrid.StringsAccept := False;
  FGrid.StringsAnswer := 'nope';
  FGrid.ClickValue(FGrid.RowAt('Lines'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('asked', 1, FGrid.StringsDialogs);
  AssertEquals('setter not called', 0, FHolder.LinesSets);
  AssertEquals('lines untouched', 'two', FHolder.Lines[1]);
end;

procedure TPropertyGridObjectsTest.TestACycleStopsAtTheDepthLimit;
var a, b: TPGLink; r: TTyValueRow; chain: Integer;

  function OtherChild(ARow: TTyValueRow): TTyValueRow;
  var i: Integer;
  begin
    Result := nil;
    for i := 0 to ARow.ChildCount - 1 do
      if ARow.Child[i].Key = 'Other' then Exit(ARow.Child[i]);
  end;

begin
  a := TPGLink.Create;
  b := TPGLink.Create;
  try
    a.Link(b);
    b.Link(a);
    LinkReads := 0;
    FGrid.SelectedObject := a;
    r := FGrid.RowAt('Other');
    chain := 1;
    while OtherChild(r) <> nil do
    begin
      r := OtherChild(r);
      Inc(chain);
    end;
    { 'Other' rows at object depths 0 .. MaxDepth: the last one is listed but not expanded. }
    AssertEquals('the chain stops at the depth limit', TyPropertyGridDefaultMaxDepth + 1, chain);
    AssertEquals('the last link has no children', 0, r.ChildCount);
    AssertTrue('and the getter was never driven to its runaway guard', LinkReads < LinkReadLimit);

    FGrid.PropertyRows.MaxDepth := 2;
    FGrid.Rebuild;
    r := FGrid.RowAt('Other');
    chain := 1;
    while OtherChild(r) <> nil do
    begin
      r := OtherChild(r);
      Inc(chain);
    end;
    AssertEquals('a smaller limit, a shorter chain', 3, chain);
    FGrid.SelectedObject := nil;
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TPropertyGridObjectsTest.TestASubComponentIsExpandedNotReferenced;
var host: TPGHostComp; r: TTyValueRow;
begin
  host := TPGHostComp.Create(nil);
  try
    FGrid.SelectedObject := host;
    r := FGrid.RowAt('Sub');
    AssertFalse('a csSubComponent is not a reference picked from a list', r.EditorKind = vekEnum);
    AssertEquals('it is a part, shown by class', '(TPGSub)', r.Value);
    AssertTrue('and expanded into its own properties', FGrid.HasRow('Sub.Level'));
    FGrid.TypeInto(FGrid.RowAt('Sub.Level'), '4');
    AssertEquals('written into the part', 4, host.Sub.Level);
    AssertTrue('a plain TComponent property IS a reference', FGrid.RowAt('Ref').EditorKind = vekEnum);
    FGrid.SelectedObject := nil;
  finally
    host.Free;
  end;
end;

{ ================================================================ a real TTyButton }

procedure TPropertyGridButtonTest.SetUp;
var ed: TTyEdit;
begin
  FForm := NewHostForm;
  FForm.Name := 'HostForm';
  FButton := TTyButton.Create(FForm);
  FButton.Name := 'Button1';
  FButton.Parent := FForm;
  FButton.SetBounds(10, 730, 80, 24);
  FButton.Anchors := [akLeft, akTop];
  FButton.Font.Name := 'Arial';
  FButton.Font.Size := 9;
  FPop1 := TPopupMenu.Create(FForm);
  FPop1.Name := 'PopupMenu1';
  FPop2 := TPopupMenu.Create(FForm);
  FPop2.Name := 'PopupMenu2';
  ed := TTyEdit.Create(FForm);         // owned by the same form, but not a TPopupMenu
  ed.Name := 'Edit1';
  FElsewhere := TForm.CreateNew(nil);   // another form: what "a different Owner" means in an app
  FPop3 := TPopupMenu.Create(FElsewhere);
  FPop3.Name := 'PopupMenu3';
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FAnswer := TFont.Create;
  FForm.Show;
  FGrid.SelectedObject := FButton;
end;

procedure TPropertyGridButtonTest.TearDown;
begin
  FForm.Free;
  FElsewhere.Free;
  FAnswer.Free;
end;

procedure TPropertyGridButtonTest.AddForeignMenu(Sender: TObject; AInstance: TPersistent;
  APropInfo: PPropInfo; AList: TStrings);
begin
  if APropInfo^.Name = 'PopupMenu' then AList.AddObject('PopupMenu3', FPop3);
end;

function TPropertyGridButtonTest.Lines(const AText: string): string;
begin
  Result := StringReplace(Trim(AText), LineEnding, ',', [rfReplaceAll]);
end;

procedure TPropertyGridButtonTest.TestPopupMenuOffersTheOwnersMenusOnly;
var r: TTyValueRow;
begin
  r := FGrid.RowAt('PopupMenu');
  AssertTrue('a reference is a pick list', r.EditorKind = vekEnum);
  AssertEquals('(none), then the form''s menus by name -- not Edit1, not another owner''s menu',
    rsTyPropGridNone + ',PopupMenu1,PopupMenu2', Lines(r.EnumValues));
  AssertEquals('nothing assigned yet', rsTyPropGridNone, r.Value);
end;

procedure TPropertyGridButtonTest.TestPickingAMenuSetsTheReference;
begin
  FGrid.PickFromDropdown(FGrid.RowAt('PopupMenu'), 'PopupMenu2');
  AssertSame('the button got the menu', FPop2, FButton.PopupMenu);
  AssertEquals('row', 'PopupMenu2', FGrid.RowAt('PopupMenu').Value);
  FGrid.PickFromDropdown(FGrid.RowAt('PopupMenu'), rsTyPropGridNone);
  AssertNull('(none) clears it', FButton.PopupMenu);
end;

procedure TPropertyGridButtonTest.TestOnGetComponentNamesCanOfferAForeignMenu;
begin
  FGrid.PropertyRows.OnGetComponentNames := @AddForeignMenu;
  FGrid.Rebuild;
  AssertEquals('the handler''s entry is on the list',
    rsTyPropGridNone + ',PopupMenu1,PopupMenu2,PopupMenu3', Lines(FGrid.RowAt('PopupMenu').EnumValues));
  FGrid.PickFromDropdown(FGrid.RowAt('PopupMenu'), 'PopupMenu3');
  AssertSame('and picking it resolves to that menu', FPop3, FButton.PopupMenu);
end;

procedure TPropertyGridButtonTest.TestAForeignCurrentValueIsListed;
begin
  FButton.PopupMenu := FPop3;
  FGrid.Rebuild;
  AssertEquals('shown by name', 'PopupMenu3', FGrid.RowAt('PopupMenu').Value);
  AssertEquals('and listed, though another owner owns it',
    rsTyPropGridNone + ',PopupMenu1,PopupMenu2,PopupMenu3', Lines(FGrid.RowAt('PopupMenu').EnumValues));
end;

procedure TPropertyGridButtonTest.TestWithoutAnOwnerOnlyNoneAndTheCurrentValue;
var orphan: TTyButton;
begin
  orphan := TTyButton.Create(nil);
  try
    orphan.PopupMenu := FPop1;
    FGrid.SelectedObject := orphan;
    AssertEquals('(none) and what it holds',
      rsTyPropGridNone + ',PopupMenu1', Lines(FGrid.RowAt('PopupMenu').EnumValues));
    FGrid.SelectedObject := nil;
    orphan.PopupMenu := nil;
  finally
    orphan.Free;
  end;
end;

procedure TPropertyGridButtonTest.TestAnchorsElementWritesTheSet;
begin
  AssertEquals('shown, in TAnchorKind order', '[akTop,akLeft]', FGrid.RowAt('Anchors').Value);
  FGrid.Select(FGrid.RowAt('Anchors.akRight'));
  FGrid.Press(VK_SPACE);
  AssertTrue('the button''s anchors gained akRight', FButton.Anchors = [akLeft, akTop, akRight]);
  AssertEquals('set row', '[akTop,akLeft,akRight]', FGrid.RowAt('Anchors').Value);
end;

procedure TPropertyGridButtonTest.TestFontSizeRowWritesTheFont;
begin
  AssertTrue('the font row is the font editor', FGrid.RowAt('Font').EditorKind = vekFont);
  AssertEquals('summarised', 'Arial, 9', FGrid.RowAt('Font').Value);
  FGrid.TypeInto(FGrid.RowAt('Font.Size'), '14');
  AssertEquals('the button''s font size', 14, FButton.Font.Size);
  AssertEquals('and its face kept', 'Arial', FButton.Font.Name);
  AssertEquals('the font row followed', 'Arial, 14', FGrid.RowAt('Font').Value);
end;

procedure TPropertyGridButtonTest.TestFontStyleElementWritesTheFont;
begin
  FGrid.Select(FGrid.RowAt('Font.Style.fsBold'));
  FGrid.Press(VK_SPACE);
  AssertTrue('bold on the button', fsBold in FButton.Font.Style);
  AssertEquals('style row', '[fsBold]', FGrid.RowAt('Font.Style').Value);
end;

procedure TPropertyGridButtonTest.TestTheFontDialogWritesTheWholeFont;
begin
  FAnswer.Name := 'Courier New';
  FAnswer.Size := 15;
  FAnswer.Style := [fsBold, fsItalic];
  FAnswer.Color := clBlue;
  FGrid.FontAnswer := FAnswer;
  FGrid.ClickValue(FGrid.RowAt('Font'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('the dialog opened', 1, FGrid.FontDialogs);
  AssertEquals('face', 'Courier New', FButton.Font.Name);
  AssertEquals('size', 15, FButton.Font.Size);
  AssertTrue('style', FButton.Font.Style = [fsBold, fsItalic]);
  AssertEquals('colour', clBlue, FButton.Font.Color);
  AssertEquals('the font row', 'Courier New, 15', FGrid.RowAt('Font').Value);
  AssertEquals('the size row', '15', FGrid.RowAt('Font.Size').Value);
  AssertEquals('the style row', '[fsBold,fsItalic]', FGrid.RowAt('Font.Style').Value);
end;

{ #183: OK after changing only the size keeps the rest of the font. The dialog opened on a font
  put together from the rows -- regular whatever the button's style, with the default CharSet,
  Pitch, Quality and Orientation -- and OK wrote all of that back. }
procedure TPropertyGridButtonTest.TestTheFontDialogStartsFromTheButtonsFont;
begin
  FButton.Font.Style := [fsBold, fsUnderline];
  FButton.Font.CharSet := RUSSIAN_CHARSET;
  FButton.Font.Pitch := fpFixed;
  FButton.Font.Quality := fqNonAntialiased;
  FButton.Font.Orientation := 900;
  FGrid.Refresh;
  FGrid.FontSizeAnswer := 15;
  FGrid.ClickValue(FGrid.RowAt('Font'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('the dialog opened', 1, FGrid.FontDialogs);
  AssertTrue('on the button''s style', FGrid.FontSeen.Style = [fsBold, fsUnderline]);
  AssertEquals('and its character set', RUSSIAN_CHARSET, FGrid.FontSeen.CharSet);
  AssertEquals('the new size', 15, FButton.Font.Size);
  AssertEquals('face kept', 'Arial', FButton.Font.Name);
  AssertTrue('bold and underline kept', FButton.Font.Style = [fsBold, fsUnderline]);
  AssertEquals('character set kept', RUSSIAN_CHARSET, FButton.Font.CharSet);
  AssertTrue('pitch kept', FButton.Font.Pitch = fpFixed);
  AssertTrue('quality kept', FButton.Font.Quality = fqNonAntialiased);
  AssertEquals('orientation kept', 900, FButton.Font.Orientation);
end;

procedure TPropertyGridButtonTest.TestACancelledFontDialogWritesNothing;
begin
  FGrid.FontAnswer := nil;
  FGrid.ClickValue(FGrid.RowAt('Font'));
  FGrid.Editor.ClickEllipsis;
  AssertEquals('the dialog opened', 1, FGrid.FontDialogs);
  AssertEquals('face kept', 'Arial', FButton.Font.Name);
  AssertEquals('size kept', 9, FButton.Font.Size);
end;

{ MaxWidth, not MinWidth: TTyButton keeps MinWidth at its measured content width itself
  (DoUpdateSizeConstraints), so a written MinWidth is overruled by the control, not lost by the grid. }
procedure TPropertyGridButtonTest.TestConstraintsExpandAndWrite;
begin
  AssertEquals('a sub-object', '(TSizeConstraints)', FGrid.RowAt('Constraints').Value);
  AssertEquals('wider than the limit to come', 80, FButton.Width);
  FGrid.TypeInto(FGrid.RowAt('Constraints.MaxWidth'), '70');
  AssertEquals('written into the button''s constraints', 70, FButton.Constraints.MaxWidth);
  AssertEquals('and the constraint took effect', 70, FButton.Width);
  AssertEquals('so the Width row was re-read', '70', FGrid.RowAt('Width').Value);
end;

initialization
  RegisterTest(TPropertyGridObjectsTest);
  RegisterTest(TPropertyGridButtonTest);
end.
