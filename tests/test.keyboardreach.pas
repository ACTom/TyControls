unit test.keyboardreach;

{$mode objfpc}{$H+}

{ #143: a control that takes the focus does something with the keyboard. The button group,
  the header control, the list group panel, the ribbon gallery and the draw grid took the
  focus and ignored every key; the menu bar took it on each click with no keys at all, and
  now takes none, opening its first menu on F10 instead. }

interface

uses
  Classes, SysUtils, Controls, Forms, Menus, LCLType, fpcunit, testregistry,
  tyControls.Edit, tyControls.ButtonGroup, tyControls.HeaderControl,
  tyControls.ListGroupPanel, tyControls.RibbonGallery, tyControls.Columns, tyControls.Grid,
  tyControls.Menu;

type
  TKeyboardReachTest = class(TTestCase)
  private
    FForm: TForm;
    FClicked, FClicks, FSelects: Integer;
    FItemGroup, FItemIndex: Integer;
    procedure SectionClicked(AHeader: TTyCustomHeaderControl; AIndex: Integer);
    procedure ItemClicked(Sender: TObject; AGroupIndex, AItemIndex: Integer);
    procedure Selected(Sender: TObject);
    function Press(C: TWinControl; AKey: Word; AShift: TShiftState = []): Word;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheArrowsPickAButtonGroupsSegment;
    procedure TestSpaceTogglesTheKeyboardsSegmentUnderMultiSelect;
    procedure TestTheArrowsWalkAHeadersShownSectionsAndSpaceClicks;
    procedure TestMirroredLeftIsTheNextSection;
    procedure TestTheArrowsWalkAListGroupPanel;
    procedure TestTheListGroupPanelScrollsToTheKeyboardsRow;
    procedure TestTheArrowsPickAGalleryItem;
    procedure TestTheKeysScrollADrawGrid;
    procedure TestADrawGridsArrowsFollowTheColumnsOnScreen;
    procedure TestAStringGridStillMovesItsCursor;
    procedure TestAMenuBarTakesNoFocusAndOpensOnF10;
  end;

implementation

type
  TCrack = class(TWinControl);
  TTyDrawGridClass = class of TTyCustomDrawGrid;
  TDrawAcc = class(TTyCustomDrawGrid);   // Header is published by the shells only

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TKeyboardReachTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FClicked := -1;
  FClicks := 0;
  FSelects := 0;
  FItemGroup := -1;
  FItemIndex := -1;
end;

procedure TKeyboardReachTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TKeyboardReachTest.SectionClicked(AHeader: TTyCustomHeaderControl; AIndex: Integer);
begin
  FClicked := AIndex;
  Inc(FClicks);
end;

procedure TKeyboardReachTest.ItemClicked(Sender: TObject; AGroupIndex, AItemIndex: Integer);
begin
  FItemGroup := AGroupIndex;
  FItemIndex := AItemIndex;
  Inc(FClicks);
end;

procedure TKeyboardReachTest.Selected(Sender: TObject);
begin
  Inc(FSelects);
end;

function TKeyboardReachTest.Press(C: TWinControl; AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  TCrack(C).KeyDown(Result, AShift);
end;

procedure TKeyboardReachTest.TestTheArrowsPickAButtonGroupsSegment;
var
  b: TTyButtonGroup;
begin
  b := TTyButtonGroup.Create(FForm);
  b.Parent := FForm;
  b.Items.Text := 'a' + LineEnding + 'b' + LineEnding + 'c';
  AssertEquals('Right from none: consumed', 0, Integer(Press(b, VK_RIGHT)));
  AssertEquals('the first segment', 0, b.ItemIndex);
  Press(b, VK_RIGHT);
  AssertEquals('the next', 1, b.ItemIndex);
  Press(b, VK_END);
  AssertEquals('End: the last', 2, b.ItemIndex);
  Press(b, VK_DOWN);
  AssertEquals('Down at the end stays', 2, b.ItemIndex);
  Press(b, VK_UP);
  AssertEquals('Up: the previous', 1, b.ItemIndex);
  Press(b, VK_HOME);
  AssertEquals('Home: the first', 0, b.ItemIndex);
  Press(b, VK_LEFT);
  AssertEquals('Left at the start stays', 0, b.ItemIndex);
  AssertEquals('Space with one choice: not used', VK_SPACE, Integer(Press(b, VK_SPACE)));
  AssertEquals('Ctrl+Right: not used', VK_RIGHT, Integer(Press(b, VK_RIGHT, [ssCtrl])));
  b.ItemIndex := -1;
  Press(b, VK_LEFT);
  AssertEquals('Left from none: the last', 2, b.ItemIndex);
end;

procedure TKeyboardReachTest.TestSpaceTogglesTheKeyboardsSegmentUnderMultiSelect;
var
  b: TTyButtonGroup;
begin
  b := TTyButtonGroup.Create(FForm);
  b.Parent := FForm;
  b.Items.Text := 'a' + LineEnding + 'b' + LineEnding + 'c';
  b.MultiSelect := True;
  Press(b, VK_RIGHT);
  AssertFalse('an arrow selects nothing under MultiSelect', b.IsSelected(0));
  AssertEquals('Space: consumed', 0, Integer(Press(b, VK_SPACE)));
  AssertTrue('Space toggles the keyboard''s segment on', b.IsSelected(0));
  Press(b, VK_RIGHT);
  Press(b, VK_RIGHT);
  Press(b, VK_SPACE);
  AssertTrue('two on, the third', b.IsSelected(2));
  AssertFalse('the one passed over is left alone', b.IsSelected(1));
  Press(b, VK_SPACE);
  AssertFalse('and Space again toggles it off', b.IsSelected(2));
  Press(b, VK_HOME);
  Press(b, VK_SPACE);
  AssertFalse('Home went to the first, toggled off', b.IsSelected(0));
end;

procedure TKeyboardReachTest.TestTheArrowsWalkAHeadersShownSectionsAndSpaceClicks;
var
  h: TTyHeaderControl;
begin
  h := TTyHeaderControl.Create(FForm);
  h.Parent := FForm;
  h.AddSection('a');
  h.AddSection('b');
  h.AddSection('c');
  h.SectionVisible[1] := False;
  h.OnSectionClick := @SectionClicked;
  AssertEquals('Right: consumed', 0, Integer(Press(h, VK_RIGHT)));
  AssertEquals('nothing clicked by moving', 0, FClicks);
  Press(h, VK_SPACE);
  AssertEquals('Space clicks the first section', 0, FClicked);
  AssertTrue('and turns its sort, as a click does', hsdAscending = h.Sort[0]);
  Press(h, VK_RIGHT);
  Press(h, VK_SPACE);
  AssertEquals('Right passes over the hidden one', 2, FClicked);
  Press(h, VK_RIGHT);
  Press(h, VK_SPACE);
  AssertEquals('Right at the end stays', 2, FClicked);
  Press(h, VK_HOME);
  Press(h, VK_SPACE);
  AssertEquals('Home: the first', 0, FClicked);
  Press(h, VK_END);
  Press(h, VK_LEFT);
  Press(h, VK_SPACE);
  AssertEquals('End, then Left over the hidden one', 0, FClicked);
  AssertEquals('Enter is not the header''s', VK_RETURN, Integer(Press(h, VK_RETURN)));
end;

procedure TKeyboardReachTest.TestMirroredLeftIsTheNextSection;
var
  h: TTyHeaderControl;
begin
  h := TTyHeaderControl.Create(FForm);
  h.Parent := FForm;
  h.BiDiMode := bdRightToLeft;
  h.AddSection('a');
  h.AddSection('b');
  h.OnSectionClick := @SectionClicked;
  Press(h, VK_LEFT);
  Press(h, VK_SPACE);
  AssertEquals('mirrored, Left from none starts at the first (the right end)', 0, FClicked);
  Press(h, VK_LEFT);
  Press(h, VK_SPACE);
  AssertEquals('and Left goes on to the next', 1, FClicked);
  Press(h, VK_RIGHT);
  Press(h, VK_SPACE);
  AssertEquals('Right comes back', 0, FClicked);
end;

procedure TKeyboardReachTest.TestTheArrowsWalkAListGroupPanel;
var
  p: TTyListGroupPanel;
begin
  p := TTyListGroupPanel.Create(FForm);
  p.Parent := FForm;
  p.SetBounds(0, 0, 200, 260);
  p.AddGroup('one');
  p.AddItem(0, 'a');
  p.AddItem(0, 'b');
  p.AddGroup('two');
  p.AddItem(1, 'c');
  p.Expanded[0] := True;
  p.Expanded[1] := False;
  p.OnItemClick := @ItemClicked;
  AssertEquals('Down: consumed', 0, Integer(Press(p, VK_DOWN)));
  AssertEquals('the first row is a header: nothing selected', -1, p.SelectedGroup);
  Press(p, VK_DOWN);
  AssertEquals('an item reached is selected', 0, p.SelectedItem);
  AssertEquals('and reported as a click is', 0, FItemIndex);
  Press(p, VK_DOWN);
  AssertEquals('the next item', 1, p.SelectedItem);
  Press(p, VK_DOWN);
  Press(p, VK_DOWN);
  AssertEquals('the closed group''s header is the last row', 1, p.SelectedItem);
  Press(p, VK_RIGHT);
  AssertTrue('Right opens it', p.Expanded[1]);
  Press(p, VK_RIGHT);
  AssertEquals('Right again: its first item', 1, p.SelectedGroup);
  AssertEquals('item c', 0, p.SelectedItem);
  Press(p, VK_LEFT);
  AssertTrue('Left: to its header, still open', p.Expanded[1]);
  Press(p, VK_LEFT);
  AssertFalse('Left on an open header closes it', p.Expanded[1]);
  Press(p, VK_UP);
  AssertEquals('Up: the last item of the open group', 0, p.SelectedGroup);
  AssertEquals('item b', 1, p.SelectedItem);
  Press(p, VK_HOME);
  AssertEquals('Space on the first header', 0, Integer(Press(p, VK_SPACE)));
  AssertFalse('closes it', p.Expanded[0]);
  Press(p, VK_SPACE);
  AssertTrue('and opens it again', p.Expanded[0]);
  Press(p, VK_END);
  AssertEquals('End: the last row, a header -- the selection stays', 1, p.SelectedItem);
end;

procedure TKeyboardReachTest.TestTheListGroupPanelScrollsToTheKeyboardsRow;
var
  p: TTyListGroupPanel;
  i: Integer;
begin
  p := TTyListGroupPanel.Create(FForm);
  p.Parent := FForm;
  p.Font.PixelsPerInch := 96;
  p.SetBounds(0, 0, 200, 80);
  p.AddGroup('one');
  for i := 0 to 19 do p.AddItem(0, 'item ' + IntToStr(i));
  p.Expanded[0] := True;
  AssertEquals('setup: at the top', 0, p.ScrollOffset);
  Press(p, VK_END);
  AssertTrue('End scrolls the last row into view', p.ScrollOffset > 0);
  Press(p, VK_HOME);
  AssertEquals('Home scrolls back to the top', 0, p.ScrollOffset);
end;

procedure TKeyboardReachTest.TestTheArrowsPickAGalleryItem;
var
  g: TTyRibbonGallery;
begin
  g := TTyRibbonGallery.Create(FForm);
  g.Parent := FForm;
  g.Items.Text := 'a' + LineEnding + 'b' + LineEnding + 'c' + LineEnding + 'd';
  g.OnSelect := @Selected;
  g.HandleNeeded;   // the gallery opens from a handle
  AssertEquals('Right: consumed', 0, Integer(Press(g, VK_RIGHT)));
  AssertEquals('the first item', 0, g.ItemIndex);
  Press(g, VK_DOWN);
  AssertEquals('Down: the next', 1, g.ItemIndex);
  Press(g, VK_END);
  AssertEquals('End: the last, past the inline row too', 3, g.ItemIndex);
  Press(g, VK_LEFT);
  AssertEquals('Left: the previous', 2, g.ItemIndex);
  Press(g, VK_HOME);
  AssertEquals('Home: the first', 0, g.ItemIndex);
  AssertEquals('each a selection', 5, FSelects);
  AssertEquals('F4: consumed', 0, Integer(Press(g, VK_F4)));
  AssertTrue('F4 opens the gallery', g.IsDroppedDown);
  Press(g, VK_F4);
  AssertFalse('and closes it', g.IsDroppedDown);
  Press(g, VK_DOWN, [ssAlt]);
  AssertTrue('Alt+Down opens it', g.IsDroppedDown);
  AssertEquals('without moving the selection', 0, g.ItemIndex);
  g.CloseUp;
end;

function NewGrid(AForm: TForm; AClass: TTyDrawGridClass): TTyCustomDrawGrid;
var
  i: Integer;
begin
  Result := AClass.Create(AForm);
  Result.Parent := AForm;
  Result.SetBounds(0, 0, 200, 150);
  for i := 0 to 9 do
    (TDrawAcc(Result).Header.Columns.Add as TTyColumn).Width := 80;
  Result.RowCount := 100;
end;

procedure TKeyboardReachTest.TestTheKeysScrollADrawGrid;
var
  g: TTyCustomDrawGrid;
  top, page: Integer;
begin
  g := NewGrid(FForm, TTyDrawGrid);
  top := g.TopRow;
  AssertEquals('Down: consumed', 0, Integer(Press(g, VK_DOWN)));
  AssertEquals('Down scrolls a row', top + 1, g.TopRow);
  Press(g, VK_UP);
  AssertEquals('Up scrolls back', top, g.TopRow);
  Press(g, VK_NEXT);
  page := g.TopRow - top;
  AssertTrue('Page Down scrolls more than a row', page > 1);
  Press(g, VK_PRIOR);
  AssertEquals('Page Up comes back', top, g.TopRow);
  Press(g, VK_END, [ssCtrl]);
  AssertTrue('Ctrl+End: near the last row', g.TopRow > 90);
  Press(g, VK_HOME, [ssCtrl]);
  AssertEquals('Ctrl+Home: the first row', top, g.TopRow);
  Press(g, VK_RIGHT);
  AssertEquals('Right scrolls a column', 1, g.LeftCol);
  Press(g, VK_LEFT);
  AssertEquals('Left scrolls back', 0, g.LeftCol);
  Press(g, VK_END);
  AssertTrue('End: toward the last column', g.LeftCol > 5);
  Press(g, VK_HOME);
  AssertEquals('Home: the first column', 0, g.LeftCol);
end;

procedure TKeyboardReachTest.TestADrawGridsArrowsFollowTheColumnsOnScreen;
var
  g: TTyCustomDrawGrid;
begin
  g := NewGrid(FForm, TTyDrawGrid);
  (TDrawAcc(g).Header.Columns.Items[1] as TTyColumn).Position := 3;   // on screen: 0, 2, 3, 1, 4 ...
  Press(g, VK_RIGHT);
  AssertEquals('Right: the column next on screen', 2, g.LeftCol);
  Press(g, VK_LEFT);
  AssertEquals('Left: back', 0, g.LeftCol);
  g.BiDiMode := bdRightToLeft;
  Press(g, VK_LEFT);
  AssertEquals('mirrored, Left goes on', 2, g.LeftCol);
  Press(g, VK_RIGHT);
  AssertEquals('and Right comes back', 0, g.LeftCol);
end;

procedure TKeyboardReachTest.TestAStringGridStillMovesItsCursor;
var
  g: TTyStringGrid;
begin
  g := TTyStringGrid(NewGrid(FForm, TTyStringGrid));
  g.Row := 1;
  Press(g, VK_DOWN);
  AssertEquals('Down moves the cursor', 2, g.Row);
  AssertEquals('which is in view: no scroll', 0, g.TopRow);
end;

procedure TKeyboardReachTest.TestAMenuBarTakesNoFocusAndOpensOnF10;
var
  bar: TTyMenuBar;
  mm: TMainMenu;
  e: TTyEdit;
  other: TForm;
  key: Word;

  function Item(AParent: TMenuItem; const ACaption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(mm);
    Result.Caption := ACaption;
    AParent.Add(Result);
  end;

begin
  { shown, off screen: the bar opens only when it is on a form the user sees }
  FForm.SetBounds(-4000, -4000, 400, 300);
  FForm.Visible := True;
  mm := TMainMenu.Create(FForm);
  Item(mm.Items, 'Do');                        // a top command: F10 does not click it
  Item(Item(mm.Items, 'File'), 'Open').Enabled := False;
  mm.Items[1].Enabled := False;                // a disabled menu: passed over
  Item(Item(mm.Items, 'Edit'), 'Copy');
  bar := TTyMenuBar.Create(FForm);
  bar.Parent := FForm;
  bar.Align := alTop;
  bar.Menu := mm;
  e := TTyEdit.Create(FForm);
  e.Parent := FForm;
  e.SetBounds(8, 40, 160, 26);
  AssertFalse('the bar is not a tab stop', bar.TabStop);

  other := TForm.CreateNew(nil);
  try
    key := VK_F10;
    Forms.Application.NotifyKeyDownHandler(other, key, []);
    AssertEquals('F10 in another form: not the bar''s', -1, bar.OpenIndexForTest);
  finally
    other.Free;
  end;
  key := VK_F10;
  Forms.Application.NotifyKeyDownHandler(e, key, [ssShift]);
  AssertEquals('Shift+F10 is the context menu''s', -1, bar.OpenIndexForTest);
  key := VK_F10;
  Forms.Application.NotifyKeyDownHandler(e, key, []);
  AssertEquals('F10 opens the first menu that can open', 2, bar.OpenIndexForTest);
  AssertEquals('and takes the key', 0, Integer(key));
end;

initialization
  RegisterTest(TKeyboardReachTest);
end.
