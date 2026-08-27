unit test.listgrouppanel.editor;
{$mode objfpc}{$H+}
{ The sider's structure editor (real-machine feedback): ONE tree over the whole nested
  model, edited in place -- because the stock collection editor is a single reused
  window showing a single layer, so authoring a second group's items meant reopening
  editors over and over. Modeless-by-design: the IDE routes the selection into the
  Object Inspector through OnSelectObject, and marks the designer dirty via OnEdited. }
interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.ListGroupPanel, tyControls.Dialogs.ListGroupsEditor;

type
  TListGroupEditorTest = class(TTestCase)
  private
    FPanel: TTyListGroupPanel;
    FForm: TTyListGroupsEditorForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TreeMirrorsTheModel;
    procedure OpeningSelectsTheFirstGroup;
    procedure AddGroupAppendsSelectsAndNotifies;
    procedure AddItemLandsInTheSelectedGroup;
    procedure DeleteTakesTheSubtreeAndLandsNearby;
    procedure MoveStaysWithinItsLevel;
    procedure RefreshKeepsTheSelectionAcrossEdits;
  end;

implementation

type
  { Records what the editor pushes out through its two IDE-facing events. }
  TEditorProbe = class
  public
    Selected: TPersistent;
    SelectCount: Integer;
    EditCount: Integer;
    procedure HandleSelect(Sender: TObject; AObject: TPersistent);
    procedure HandleEdited(Sender: TObject);
  end;

procedure TEditorProbe.HandleSelect(Sender: TObject; AObject: TPersistent);
begin
  Selected := AObject;
  Inc(SelectCount);
end;

procedure TEditorProbe.HandleEdited(Sender: TObject);
begin
  Inc(EditCount);
end;

procedure TListGroupEditorTest.SetUp;
var
  g: TTyListGroup;
begin
  FPanel := TTyListGroupPanel.Create(nil);
  FPanel.Font.PixelsPerInch := 96;
  g := FPanel.Groups.Add;
  g.Caption := 'Alpha';
  g.Items.Add.Caption := 'a1';
  g.Items.Add.Caption := 'a2';
  g := FPanel.Groups.Add;
  g.Caption := 'Beta';
  g.Items.Add.Caption := 'b1';
  FForm := TyBuildListGroupsEditor(FPanel);
end;

procedure TListGroupEditorTest.TearDown;
begin
  FForm.Free;
  FPanel.Free;
end;

procedure TListGroupEditorTest.TreeMirrorsTheModel;
begin
  AssertEquals('every group and item is one tree entry', 5, FForm.NodeCount);
  AssertEquals('groups sit at the top level', 0, FForm.NodeLevel(0));
  AssertEquals('their items one level in', 1, FForm.NodeLevel(1));
  AssertEquals('order is the panel order', 1, FForm.NodeLevel(2));
  AssertEquals('second group back at the top', 0, FForm.NodeLevel(3));
  AssertTrue('a group entry carries its group', FForm.NodeObject(0) = FPanel.Groups[0]);
  AssertTrue('an item entry carries its item', FForm.NodeObject(2) = FPanel.Groups[0].Items[1]);
  AssertTrue('captions show the display name',
    Pos('Alpha', FForm.NodeCaption(0)) > 0);
end;

procedure TListGroupEditorTest.OpeningSelectsTheFirstGroup;
begin
  { Add Item must have an aim from the very first click. }
  AssertTrue('the first group starts selected', FForm.SelectedObject = FPanel.Groups[0]);
end;

procedure TListGroupEditorTest.AddGroupAppendsSelectsAndNotifies;
var
  probe: TEditorProbe;
begin
  probe := TEditorProbe.Create;
  try
    FForm.OnSelectObject := @probe.HandleSelect;
    FForm.OnEdited := @probe.HandleEdited;
    FForm.AddGroup;
    AssertEquals('a third group exists', 3, FPanel.Groups.Count);
    AssertTrue('and is the selection', FForm.SelectedObject = FPanel.Groups[2]);
    AssertTrue('the IDE was told to show it', probe.Selected = FPanel.Groups[2]);
    AssertEquals('one designer-dirty ping', 1, probe.EditCount);
  finally
    FForm.OnSelectObject := nil;
    FForm.OnEdited := nil;
    probe.Free;
  end;
end;

procedure TListGroupEditorTest.AddItemLandsInTheSelectedGroup;
begin
  FForm.SelectObject(FPanel.Groups[1]);
  FForm.AddItem;
  AssertEquals('appended to the aimed group', 2, FPanel.Groups[1].Items.Count);
  AssertTrue('the new item is the selection',
    FForm.SelectedObject = FPanel.Groups[1].Items[1]);
  AssertEquals('the neighbour group is untouched', 2, FPanel.Groups[0].Items.Count);

  { Aimed at an ITEM: the new row lands right below it, like every outliner. }
  FForm.SelectObject(FPanel.Groups[0].Items[0]);
  FForm.AddItem;
  AssertEquals('inserted, not appended', 3, FPanel.Groups[0].Items.Count);
  AssertTrue('right below the selected row',
    FForm.SelectedObject = FPanel.Groups[0].Items[1]);
  AssertEquals('the old second row slid down', 'a2', FPanel.Groups[0].Items[2].Caption);
end;

procedure TListGroupEditorTest.DeleteTakesTheSubtreeAndLandsNearby;
begin
  FForm.SelectObject(FPanel.Groups[0]);
  FForm.DeleteSelected;
  AssertEquals('the group went with both its items', 1, FPanel.Groups.Count);
  AssertEquals('the tree shrank to the survivor', 2, FForm.NodeCount);
  AssertTrue('the selection landed on the next group',
    FForm.SelectedObject = FPanel.Groups[0]);

  FForm.SelectObject(FPanel.Groups[0].Items[0]);
  FForm.DeleteSelected;
  AssertEquals('the item is gone', 0, FPanel.Groups[0].Items.Count);
  AssertTrue('an emptied group keeps the selection',
    FForm.SelectedObject = FPanel.Groups[0]);
end;

procedure TListGroupEditorTest.MoveStaysWithinItsLevel;
var
  probe: TEditorProbe;
begin
  FForm.SelectObject(FPanel.Groups[0]);
  FForm.MoveSelected(1);
  AssertEquals('the group moved down', 'Alpha', FPanel.Groups[1].Caption);
  AssertTrue('and stays selected', FForm.SelectedObject = FPanel.Groups[1]);
  AssertEquals('its items travelled with it', 2, FPanel.Groups[1].Items.Count);

  probe := TEditorProbe.Create;
  try
    FForm.OnEdited := @probe.HandleEdited;
    { The first item of its group has nowhere up to go: a no-op, not a dirty designer. }
    FForm.SelectObject(FPanel.Groups[1].Items[0]);
    FForm.MoveSelected(-1);
    AssertEquals('an end-of-level move changes nothing', 'a1', FPanel.Groups[1].Items[0].Caption);
    AssertEquals('and pings nobody', 0, probe.EditCount);

    FForm.MoveSelected(1);
    AssertEquals('an in-level move reorders', 'a1', FPanel.Groups[1].Items[1].Caption);
    AssertEquals('and pings once', 1, probe.EditCount);
  finally
    FForm.OnEdited := nil;
    probe.Free;
  end;
end;

procedure TListGroupEditorTest.RefreshKeepsTheSelectionAcrossEdits;
begin
  { The OI edits the model behind the editor's back; the IDE then calls RefreshFromModel. }
  FForm.SelectObject(FPanel.Groups[1].Items[0]);
  FPanel.Groups[1].Caption := 'Renamed';
  FForm.RefreshFromModel;
  AssertTrue('the selected object survived the rebuild',
    FForm.SelectedObject = FPanel.Groups[1].Items[0]);
  AssertTrue('and the tree shows the new name',
    Pos('Renamed', FForm.NodeCaption(3)) > 0);
end;

initialization
  RegisterTest(TListGroupEditorTest);

end.
