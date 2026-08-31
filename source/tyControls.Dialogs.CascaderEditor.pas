unit tyControls.Dialogs.CascaderEditor;
{$mode objfpc}{$H+}
{ TTyCascader's option editor: ONE tree over the whole nested Nodes model, edited in
  place -- the stock collection editor shows one nesting level per open, so authoring
  a province/city/district tree meant a window per branch. Any depth: Add Option
  inserts a sibling right below the selection, Add Child descends, Up/Down reorder
  within the level (nested collections make that a plain Index write).

  TTyStructureEditorForm carries the shape (modeless window, tree, button column, the
  OI events); this class is the TTyCascaderNodes vocabulary. }
interface
uses
  Classes, SysUtils, Controls,
  tyControls.StrConsts, tyControls.TreeView, tyControls.Dialogs.StructureEditor,
  tyControls.Cascader;

type
  TTyCascaderEditorForm = class(TTyStructureEditorForm)
  private
    procedure AddNodeClick(Sender: TObject);
    procedure AddChildClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    function Model: TTyCascaderNodes;
    function SelectedNode: TTyCascaderNode;
    procedure BuildBranch(AParent: TTyTreeNodeItem; ANodes: TTyCascaderNodes);
  protected
    procedure BuildTree; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    procedure SetCascader(ACascader: TTyCascader);

    { Action seams (the buttons call these; tests call them directly). }
    procedure AddNode;
    procedure AddChild;
    procedure DeleteSelected;
    procedure MoveSelected(ADelta: Integer);
  end;

{ Construct-only builder (no Show), aimed at ACascader; the test seam and the IDE's door. }
function TyBuildCascaderEditor(ACascader: TTyCascader): TTyCascaderEditorForm;

implementation

type
  { GetOwner is protected on TPersistent; the parent node of an emptied branch is
    reached through it (a sub-list's owner is its TTyCascaderNode). }
  TNodesAccess = class(TTyCascaderNodes);

function TyBuildCascaderEditor(ACascader: TTyCascader): TTyCascaderEditorForm;
begin
  Result := TTyCascaderEditorForm.CreateNew(nil);
  Result.SetCascader(ACascader);
end;

constructor TTyCascaderEditorForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  FBaseCaption := rsDlgCascTitle;
  Caption := FBaseCaption;
  MakeActionButton(rsDlgNodesAddNode, @AddNodeClick);
  MakeActionButton(rsDlgNodesAddChild, @AddChildClick);
  MakeActionButton(rsDlgNodesDelete, @DeleteClick);
  MakeActionButton(rsDlgNodesUp, @UpClick);
  MakeActionButton(rsDlgNodesDown, @DownClick);
  FinishCreation(430, 380);
end;

procedure TTyCascaderEditorForm.SetCascader(ACascader: TTyCascader);
begin
  SetSubject(ACascader);
end;

function TTyCascaderEditorForm.Model: TTyCascaderNodes;
begin
  Result := (Subject as TTyCascader).Nodes;
end;

function TTyCascaderEditorForm.SelectedNode: TTyCascaderNode;
var
  o: TPersistent;
begin
  o := SelectedObject;
  if o is TTyCascaderNode then Result := TTyCascaderNode(o) else Result := nil;
end;

procedure TTyCascaderEditorForm.BuildBranch(AParent: TTyTreeNodeItem; ANodes: TTyCascaderNodes);
var
  i: Integer;
  n: TTyCascaderNode;
begin
  for i := 0 to ANodes.Count - 1 do
  begin
    n := ANodes[i];
    BuildBranch(inherited AddNode(AParent, n.Caption, n), n.Children);
  end;
end;

procedure TTyCascaderEditorForm.BuildTree;
begin
  BuildBranch(nil, Model);
end;

{ ---- actions ---- }

procedure TTyCascaderEditorForm.AddNode;
var
  sel, n: TTyCascaderNode;
  coll: TTyCascaderNodes;
begin
  if Subject = nil then Exit;
  sel := SelectedNode;
  if sel = nil then coll := Model else coll := sel.Collection as TTyCascaderNodes;
  n := coll.Add;
  n.Caption := Format('Option%d', [coll.Count]);
  if sel <> nil then
    n.Index := sel.Index + 1;         // right below the selected row, like every outliner
  RefreshFromModel;
  SelectObject(n);
  NotifyEdited;
end;

procedure TTyCascaderEditorForm.AddChild;
var
  sel, n: TTyCascaderNode;
  coll: TTyCascaderNodes;
begin
  if Subject = nil then Exit;
  sel := SelectedNode;
  if sel = nil then coll := Model else coll := sel.Children;
  n := coll.Add;
  n.Caption := Format('Option%d', [coll.Count]);
  RefreshFromModel;
  SelectObject(n);
  NotifyEdited;
end;

procedure TTyCascaderEditorForm.DeleteSelected;
var
  sel: TTyCascaderNode;
  coll: TTyCascaderNodes;
  ownerP: TPersistent;
  idx: Integer;
  landOn: TPersistent;
begin
  sel := SelectedNode;
  if sel = nil then Exit;
  coll := sel.Collection as TTyCascaderNodes;
  ownerP := TNodesAccess(coll).GetOwner;
  idx := sel.Index;
  sel.Free;                           // takes its whole Children subtree with it
  if idx >= coll.Count then idx := coll.Count - 1;
  if idx >= 0 then
    landOn := coll[idx]
  else if ownerP is TTyCascaderNode then
    landOn := TTyCascaderNode(ownerP) // the emptied branch keeps the selection on its parent
  else
    landOn := nil;
  RefreshFromModel;
  SelectObject(landOn);
  NotifyEdited;
end;

procedure TTyCascaderEditorForm.MoveSelected(ADelta: Integer);
var
  sel: TTyCascaderNode;
  coll: TTyCascaderNodes;
  dst: Integer;
begin
  sel := SelectedNode;
  if sel = nil then Exit;
  coll := sel.Collection as TTyCascaderNodes;
  dst := sel.Index + ADelta;
  if (dst < 0) or (dst >= coll.Count) then Exit;   // the end of its level: a no-op
  sel.Index := dst;
  RefreshFromModel;
  SelectObject(sel);
  NotifyEdited;
end;

{ ---- button handlers (thin UI wrappers over the seams) ---- }

procedure TTyCascaderEditorForm.AddNodeClick(Sender: TObject);
begin
  AddNode;
end;

procedure TTyCascaderEditorForm.AddChildClick(Sender: TObject);
begin
  AddChild;
end;

procedure TTyCascaderEditorForm.DeleteClick(Sender: TObject);
begin
  DeleteSelected;
end;

procedure TTyCascaderEditorForm.UpClick(Sender: TObject);
begin
  MoveSelected(-1);
end;

procedure TTyCascaderEditorForm.DownClick(Sender: TObject);
begin
  MoveSelected(1);
end;

end.
