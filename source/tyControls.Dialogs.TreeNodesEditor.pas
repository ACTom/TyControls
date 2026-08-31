unit tyControls.Dialogs.TreeNodesEditor;
{$mode objfpc}{$H+}
{ TTyTreeView's node editor: ONE tree over the whole Items model, edited in place --
  Delphi's 'TreeView Items Editor', which the stock flat collection editor (rows plus
  a hand-typed Level number) never was. Any depth: Add Node inserts a sibling right
  below the selection, Add Child descends, Delete takes the subtree, Up/Down move the
  subtree BLOCK among its siblings (TTyTreeNodes.MoveSubTreeBefore/After).

  TTyStructureEditorForm carries the shape (modeless window, tree, button column, the
  OI events); this class is the TTyTreeNodes vocabulary. }
interface
uses
  Classes, SysUtils, Controls,
  tyControls.StrConsts, tyControls.TreeView, tyControls.Dialogs.StructureEditor;

type
  TTyTreeNodesEditorForm = class(TTyStructureEditorForm)
  private
    procedure AddNodeClick(Sender: TObject);
    procedure AddChildClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    function Model: TTyTreeNodes;
    function SelectedItem: TTyTreeNodeItem;
    { The same-level neighbour ADelta steps away (previous/next sibling), or nil at the
      end of the level -- the target MoveSelected hands to the block move. }
    function SiblingOf(AItem: TTyTreeNodeItem; ADelta: Integer): TTyTreeNodeItem;
  protected
    procedure BuildTree; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    procedure SetTree(ATree: TTyTreeView);

    { Action seams (the buttons call these; tests call them directly). }
    procedure AddNode;
    procedure AddChild;
    procedure DeleteSelected;
    procedure MoveSelected(ADelta: Integer);
  end;

{ Construct-only builder (no Show), aimed at ATree; the test seam and the IDE's door. }
function TyBuildTreeNodesEditor(ATree: TTyTreeView): TTyTreeNodesEditorForm;

implementation

function TyBuildTreeNodesEditor(ATree: TTyTreeView): TTyTreeNodesEditorForm;
begin
  Result := TTyTreeNodesEditorForm.CreateNew(nil);
  Result.SetTree(ATree);
end;

constructor TTyTreeNodesEditorForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  FBaseCaption := rsDlgNodesTitle;
  Caption := FBaseCaption;
  MakeActionButton(rsDlgNodesAddNode, @AddNodeClick);
  MakeActionButton(rsDlgNodesAddChild, @AddChildClick);
  MakeActionButton(rsDlgNodesDelete, @DeleteClick);
  MakeActionButton(rsDlgNodesUp, @UpClick);
  MakeActionButton(rsDlgNodesDown, @DownClick);
  FinishCreation(430, 380);
end;

procedure TTyTreeNodesEditorForm.SetTree(ATree: TTyTreeView);
begin
  SetSubject(ATree);
end;

function TTyTreeNodesEditorForm.Model: TTyTreeNodes;
begin
  Result := (Subject as TTyTreeView).Items;
end;

function TTyTreeNodesEditorForm.SelectedItem: TTyTreeNodeItem;
var
  o: TPersistent;
begin
  o := SelectedObject;
  if o is TTyTreeNodeItem then Result := TTyTreeNodeItem(o) else Result := nil;
end;

procedure TTyTreeNodesEditorForm.BuildTree;
var
  i: Integer;
  it: TTyTreeNodeItem;
  stack: array of TTyTreeNodeItem;   // editor-tree node per depth, index = level
begin
  { The model is pre-order + Level, so the parent at depth d-1 is simply the last
    editor node placed at that depth -- one stack, no lookups. }
  SetLength(stack, 0);
  for i := 0 to Model.Count - 1 do
  begin
    it := Model[i];
    if Length(stack) < it.Level + 1 then SetLength(stack, it.Level + 1);
    if it.Level = 0 then
      stack[0] := inherited AddNode(nil, it.Text, it)
    else
      stack[it.Level] := inherited AddNode(stack[it.Level - 1], it.Text, it);
  end;
end;

function TTyTreeNodesEditorForm.SiblingOf(AItem: TTyTreeNodeItem; ADelta: Integer): TTyTreeNodeItem;
var
  i: Integer;
begin
  Result := nil;
  if ADelta < 0 then
  begin
    { Scan backwards: the previous SAME-level item before crossing a shallower one
      (a shallower item is the parent boundary -- past it lives another family). }
    i := AItem.Index - 1;
    while i >= 0 do
    begin
      if Model[i].Level < AItem.Level then Exit;
      if Model[i].Level = AItem.Level then Exit(Model[i]);
      Dec(i);
    end;
  end
  else
  begin
    { Forwards, the block structure answers directly: the item right after our
      subtree is the next sibling -- or a shallower item, which ends the level. }
    i := AItem.Index + AItem.SubTreeCount;
    if (i < Model.Count) and (Model[i].Level = AItem.Level) then
      Result := Model[i];
  end;
end;

{ ---- actions ---- }

procedure TTyTreeNodesEditorForm.AddNode;
var
  sel, it: TTyTreeNodeItem;
begin
  if Subject = nil then Exit;
  sel := SelectedItem;
  if sel = nil then
    it := Model.AddChild(nil, Format('Node%d', [Model.Count + 1]))
  else
  begin
    { Add appends at the LEVEL'S end (the LCL contract); the editor wants the new row
      right below the selection, so the block move walks it back up. }
    it := Model.Add(sel, Format('Node%d', [Model.Count + 1]));
    Model.MoveSubTreeAfter(it, sel);
  end;
  RefreshFromModel;
  SelectObject(it);
  NotifyEdited;
end;

procedure TTyTreeNodesEditorForm.AddChild;
var
  sel, it: TTyTreeNodeItem;
begin
  if Subject = nil then Exit;
  sel := SelectedItem;
  it := Model.AddChild(sel, Format('Node%d', [Model.Count + 1]));
  RefreshFromModel;
  SelectObject(it);
  NotifyEdited;
end;

procedure TTyTreeNodesEditorForm.DeleteSelected;
var
  sel: TTyTreeNodeItem;
  idx: Integer;
begin
  sel := SelectedItem;
  if sel = nil then Exit;
  idx := sel.Index;
  Model.DeleteItem(sel);              // the whole subtree goes with it
  RefreshFromModel;
  { Land on the row that slid into the hole (visually the next line), clamped. }
  if idx >= Model.Count then idx := Model.Count - 1;
  if idx >= 0 then SelectObject(Model[idx]);
  NotifyEdited;
end;

procedure TTyTreeNodesEditorForm.MoveSelected(ADelta: Integer);
var
  sel, sib: TTyTreeNodeItem;
begin
  sel := SelectedItem;
  if sel = nil then Exit;
  sib := SiblingOf(sel, ADelta);
  if sib = nil then Exit;             // the end of its level: a no-op, not a dirty designer
  if ADelta < 0 then
    Model.MoveSubTreeBefore(sel, sib)
  else
    Model.MoveSubTreeAfter(sel, sib);
  RefreshFromModel;
  SelectObject(sel);
  NotifyEdited;
end;

{ ---- button handlers (thin UI wrappers over the seams) ---- }

procedure TTyTreeNodesEditorForm.AddNodeClick(Sender: TObject);
begin
  AddNode;
end;

procedure TTyTreeNodesEditorForm.AddChildClick(Sender: TObject);
begin
  AddChild;
end;

procedure TTyTreeNodesEditorForm.DeleteClick(Sender: TObject);
begin
  DeleteSelected;
end;

procedure TTyTreeNodesEditorForm.UpClick(Sender: TObject);
begin
  MoveSelected(-1);
end;

procedure TTyTreeNodesEditorForm.DownClick(Sender: TObject);
begin
  MoveSelected(1);
end;

end.
