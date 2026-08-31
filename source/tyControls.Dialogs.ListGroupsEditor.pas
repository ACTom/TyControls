unit tyControls.Dialogs.ListGroupsEditor;
{$mode objfpc}{$H+}
{ The sider's structure editor: ONE tree showing every group and every item, edited in
  place (real-machine feedback -- hopping between the stock collection editor's single
  layer per open made authoring a second group's items a chore).

  TTyStructureEditorForm carries the shape (modeless window, tree, button column, the
  OI events); this class is the ListGroupPanel vocabulary: Groups and their Items, the
  facade defaults, and where a new row lands. }
interface
uses
  Classes, SysUtils, Controls,
  tyControls.StrConsts, tyControls.TreeView, tyControls.Dialogs.StructureEditor,
  tyControls.ListGroupPanel;

type
  TTyListGroupsEditorForm = class(TTyStructureEditorForm)
  private
    procedure AddGroupClick(Sender: TObject);
    procedure AddItemClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
  protected
    procedure BuildTree; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    { The historical names for SetSubject/Subject, kept for the callers that use them. }
    procedure SetPanel(APanel: TTyListGroupPanel);
    function Panel: TTyListGroupPanel;

    { Action seams (the buttons call these; tests call them directly). }
    procedure AddGroup;
    { Into the selected group; after the selected item, when an item is selected. }
    procedure AddItem;
    procedure DeleteSelected;
    { Move the selected group / item within its own level; ends of the level are no-ops. }
    procedure MoveSelected(ADelta: Integer);
  end;

{ Construct-only builder (no Show), aimed at APanel; the test seam and the IDE's door. }
function TyBuildListGroupsEditor(APanel: TTyListGroupPanel): TTyListGroupsEditorForm;

implementation

function TyBuildListGroupsEditor(APanel: TTyListGroupPanel): TTyListGroupsEditorForm;
begin
  Result := TTyListGroupsEditorForm.CreateNew(nil);
  Result.SetPanel(APanel);
end;

constructor TTyListGroupsEditorForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  FBaseCaption := rsDlgLgeTitle;
  Caption := FBaseCaption;
  MakeActionButton(rsDlgLgeAddGroup, @AddGroupClick);
  MakeActionButton(rsDlgLgeAddItem, @AddItemClick);
  MakeActionButton(rsDlgLgeDelete, @DeleteClick);
  MakeActionButton(rsDlgLgeUp, @UpClick);
  MakeActionButton(rsDlgLgeDown, @DownClick);
  FinishCreation(430, 380);
end;

function TTyListGroupsEditorForm.Panel: TTyListGroupPanel;
begin
  Result := Subject as TTyListGroupPanel;
end;

procedure TTyListGroupsEditorForm.SetPanel(APanel: TTyListGroupPanel);
begin
  SetSubject(APanel);
end;

procedure TTyListGroupsEditorForm.BuildTree;
var
  g, i: Integer;
  grp: TTyListGroup;
  gNode: TTyTreeNodeItem;
begin
  for g := 0 to Panel.Groups.Count - 1 do
  begin
    grp := Panel.Groups[g];
    gNode := AddNode(nil, Format('%d - %s', [g, grp.DisplayName]), grp);
    for i := 0 to grp.Items.Count - 1 do
      AddNode(gNode, Format('%d - %s', [i, grp.Items[i].DisplayName]), grp.Items[i]);
  end;
end;

{ ---- actions ---- }

procedure TTyListGroupsEditorForm.AddGroup;
var
  g: TTyListGroup;
begin
  if Subject = nil then Exit;
  g := Panel.Groups.Add;
  g.Caption := Format('Group%d', [Panel.Groups.Count]);
  RefreshFromModel;
  SelectObject(g);
  NotifyEdited;
end;

procedure TTyListGroupsEditorForm.AddItem;
var
  sel: TPersistent;
  grp: TTyListGroup;
  after: Integer;
  it: TTyListGroupItem;
begin
  if Subject = nil then Exit;
  sel := SelectedObject;
  after := -1;                        // -1 = append at the group's end
  if sel is TTyListGroup then
    grp := TTyListGroup(sel)
  else if sel is TTyListGroupItem then
  begin
    grp := (TTyListGroupItem(sel).Collection as TTyListGroupItems).Group;
    after := TTyListGroupItem(sel).Index;
  end
  else
    Exit;                             // nothing aimed at: adding nowhere beats guessing
  it := grp.Items.Add;
  it.Caption := Format('Item%d', [grp.Items.Count]);
  if after >= 0 then
    it.Index := after + 1;            // right below the selected row, like every outliner
  RefreshFromModel;
  SelectObject(it);
  NotifyEdited;
end;

procedure TTyListGroupsEditorForm.DeleteSelected;
var
  sel: TPersistent;
  grp: TTyListGroup;
  idx: Integer;
  landOn: TPersistent;
begin
  sel := SelectedObject;
  if sel = nil then Exit;
  landOn := nil;
  if sel is TTyListGroupItem then
  begin
    grp := (TTyListGroupItem(sel).Collection as TTyListGroupItems).Group;
    idx := TTyListGroupItem(sel).Index;
    sel.Free;
    if idx >= grp.Items.Count then idx := grp.Items.Count - 1;
    if idx >= 0 then landOn := grp.Items[idx] else landOn := grp;
  end
  else if sel is TTyListGroup then
  begin
    idx := TTyListGroup(sel).Index;
    sel.Free;                         // takes its whole Items subtree with it
    if idx >= Panel.Groups.Count then idx := Panel.Groups.Count - 1;
    if idx >= 0 then landOn := Panel.Groups[idx];
  end;
  RefreshFromModel;
  SelectObject(landOn);
  NotifyEdited;
end;

procedure TTyListGroupsEditorForm.MoveSelected(ADelta: Integer);
var
  sel: TPersistent;
  cnt, dst: Integer;
begin
  sel := SelectedObject;
  if sel = nil then Exit;
  if sel is TTyListGroup then cnt := Panel.Groups.Count
  else if sel is TTyListGroupItem then
    cnt := (TTyListGroupItem(sel).Collection as TTyListGroupItems).Group.Items.Count
  else Exit;
  dst := TCollectionItem(sel).Index + ADelta;
  if (dst < 0) or (dst >= cnt) then Exit;
  TCollectionItem(sel).Index := dst;
  RefreshFromModel;
  SelectObject(sel);
  NotifyEdited;
end;

{ ---- button handlers (thin UI wrappers over the seams) ---- }

procedure TTyListGroupsEditorForm.AddGroupClick(Sender: TObject);
begin
  AddGroup;
end;

procedure TTyListGroupsEditorForm.AddItemClick(Sender: TObject);
begin
  AddItem;
end;

procedure TTyListGroupsEditorForm.DeleteClick(Sender: TObject);
begin
  DeleteSelected;
end;

procedure TTyListGroupsEditorForm.UpClick(Sender: TObject);
begin
  MoveSelected(-1);
end;

procedure TTyListGroupsEditorForm.DownClick(Sender: TObject);
begin
  MoveSelected(1);
end;

end.
