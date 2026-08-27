unit tyControls.Dialogs.ListGroupsEditor;
{$mode objfpc}{$H+}
{ The sider's structure editor: ONE tree showing every group and every item, edited in
  place (real-machine feedback -- hopping between the stock collection editor's single
  layer per open made authoring a second group's items a chore).

  It edits the panel's Groups DIRECTLY, no working copy: the form is designed to run
  MODELESS next to the Object Inspector, which shows the live selected group/item --
  a copy would give the OI a different object than the panel streams. The IDE side
  (tyControls.Design) injects OnSelectObject (routing the tree's selection into the OI)
  and OnEdited (marking the designer modified); both stay nil in plain runtime use.

  Construct-only builder + public action seams, the house pattern, so every behaviour
  is assertable headlessly. }
interface
uses
  Classes, SysUtils, Types, Controls, Forms,
  tyControls.Types, tyControls.StrConsts, tyControls.Controller,
  tyControls.Dialogs, tyControls.Button, tyControls.TreeView,
  tyControls.ListGroupPanel;

type
  TTySelectObjectEvent = procedure(Sender: TObject; AObject: TPersistent) of object;

  TTyListGroupsEditorForm = class(TTyDialog)
  private
    FPanel: TTyListGroupPanel;
    FTree: TTyTreeView;
    FAddGroupBtn, FAddItemBtn, FDeleteBtn, FUpBtn, FDownBtn: TTyButton;
    FOnSelectObject: TTySelectObjectEvent;
    FOnEdited: TNotifyEvent;
    FRebuilding: Boolean;
    procedure TreeSelectionChanged(Sender: TObject);
    procedure TreeChange(Sender: TTyTreeView; ANode: PTyTreeNode);
    procedure AddGroupClick(Sender: TObject);
    procedure AddItemClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    function NodeItemOf(AObject: TPersistent): TTyTreeNodeItem;
    procedure NotifyEdited;
    procedure NotifySelection;
  protected
    procedure LayoutContent; override;
    procedure DoClose(var CloseAction: TCloseAction); override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    { Aim the editor at a panel (nil detaches). Rebuilds the tree, selects the first group. }
    procedure SetPanel(APanel: TTyListGroupPanel);
    { Rebuild the tree from the panel, keeping the selection when its object survived --
      the IDE side calls this when the model was edited elsewhere (e.g. in the OI). }
    procedure RefreshFromModel;

    { Action seams (the buttons call these; tests call them directly). }
    function SelectedObject: TPersistent;             // TTyListGroup / TTyListGroupItem / nil
    procedure SelectObject(AObject: TPersistent);
    procedure AddGroup;
    { Into the selected group; after the selected item, when an item is selected. }
    procedure AddItem;
    procedure DeleteSelected;
    { Move the selected group / item within its own level; ends of the level are no-ops. }
    procedure MoveSelected(ADelta: Integer);

    { The tree as data, for assertions: flat entry count, and each entry's payload/level. }
    function NodeCount: Integer;
    function NodeObject(AIndex: Integer): TPersistent;
    function NodeLevel(AIndex: Integer): Integer;
    function NodeCaption(AIndex: Integer): string;

    property Panel: TTyListGroupPanel read FPanel;
    property OnSelectObject: TTySelectObjectEvent read FOnSelectObject write FOnSelectObject;
    property OnEdited: TNotifyEvent read FOnEdited write FOnEdited;
  end;

{ Construct-only builder (no Show), aimed at APanel; the test seam and the IDE's door. }
function TyBuildListGroupsEditor(APanel: TTyListGroupPanel): TTyListGroupsEditorForm;

implementation

function TyBuildListGroupsEditor(APanel: TTyListGroupPanel): TTyListGroupsEditorForm;
begin
  Result := TTyListGroupsEditorForm.CreateNew(nil);
  Result.SetPanel(APanel);
end;

{ ---- construction / layout ---- }

constructor TTyListGroupsEditorForm.CreateNew(AOwner: TComponent; Num: Integer);

  function MakeButton(const ACaption: string; AHandler: TNotifyEvent): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
  end;

begin
  inherited CreateNew(AOwner, Num);
  Caption := rsDlgLgeTitle;
  Resizable := True;
  Constraints.MinWidth := 360;
  Constraints.MinHeight := 300;

  FTree := TTyTreeView.Create(Self);
  FTree.Parent := Self;

  FAddGroupBtn := MakeButton(rsDlgLgeAddGroup, @AddGroupClick);
  FAddItemBtn  := MakeButton(rsDlgLgeAddItem, @AddItemClick);
  FDeleteBtn   := MakeButton(rsDlgLgeDelete, @DeleteClick);
  FUpBtn       := MakeButton(rsDlgLgeUp, @UpClick);
  FDownBtn     := MakeButton(rsDlgLgeDown, @DownClick);

  { Handlers only after every child exists, so nothing fires into a half-built form.
    BOTH selection events: programmatic selects (Selected := N) fire OnChange, while
    the interactive paths (mouse, keyboard, select-all) fire OnSelectionChanged. }
  FTree.OnSelectionChanged := @TreeSelectionChanged;
  FTree.OnChange := @TreeChange;

  AutoSizeToContent(430, 380);
  LayoutContent;
end;

procedure TTyListGroupsEditorForm.LayoutContent;
const
  Gap = 8;
  BtnW = 120;
var
  r: TRect;
  x, y, treeW, btnH, i: Integer;
  btns: array[0..4] of TTyButton;
begin
  if FDownBtn = nil then Exit;    { Resize can fire before construction finishes }
  r := ContentRect;
  btnH := TyDensityHeight(nil, TyDlgEditH);
  treeW := (r.Right - r.Left) - 2 * TyDlgPad - BtnW - Gap;
  FTree.SetBounds(r.Left + TyDlgPad, r.Top + TyDlgPad,
    treeW, (r.Bottom - r.Top) - 2 * TyDlgPad);

  x := r.Left + TyDlgPad + treeW + Gap;
  y := r.Top + TyDlgPad;
  btns[0] := FAddGroupBtn; btns[1] := FAddItemBtn; btns[2] := FDeleteBtn;
  btns[3] := FUpBtn; btns[4] := FDownBtn;
  for i := 0 to High(btns) do
  begin
    btns[i].SetBounds(x, y, BtnW, btnH);
    Inc(y, btnH + Gap div 2);
  end;
end;

procedure TTyListGroupsEditorForm.DoClose(var CloseAction: TCloseAction);
begin
  inherited DoClose(CloseAction);
  { A modeless editor is a reusable window: closing hides it, its owner frees it. }
  CloseAction := caHide;
end;

{ ---- model <-> tree ---- }

procedure TTyListGroupsEditorForm.SetPanel(APanel: TTyListGroupPanel);
begin
  FPanel := APanel;
  if (FPanel <> nil) and (FPanel.Name <> '') then
    Caption := rsDlgLgeTitle + ' - ' + FPanel.Name
  else
    Caption := rsDlgLgeTitle;
  RefreshFromModel;
  { A fresh target starts on its first group, so Add Item has an aim from click one. }
  if (SelectedObject = nil) and (FPanel <> nil) and (FPanel.Groups.Count > 0) then
    SelectObject(FPanel.Groups[0]);
end;

procedure TTyListGroupsEditorForm.RefreshFromModel;
var
  keep: TPersistent;
  g, i: Integer;
  grp: TTyListGroup;
  gNode: TTyTreeNodeItem;
begin
  keep := SelectedObject;   { compared by pointer only below -- never dereferenced,
                              so a selection deleted elsewhere degrades to nil }
  FRebuilding := True;
  try
    FTree.Items.BeginUpdate;
    try
      FTree.Items.Clear;
      if FPanel <> nil then
        for g := 0 to FPanel.Groups.Count - 1 do
        begin
          grp := FPanel.Groups[g];
          gNode := FTree.Items.Add(nil, Format('%d - %s', [g, grp.DisplayName]));
          gNode.Data := grp;
          gNode.Expanded := True;
          for i := 0 to grp.Items.Count - 1 do
            FTree.Items.AddChild(gNode,
              Format('%d - %s', [i, grp.Items[i].DisplayName])).Data := grp.Items[i];
        end;
    finally
      FTree.Items.EndUpdate;
    end;
  finally
    FRebuilding := False;
  end;
  if keep <> nil then
    SelectObject(keep);
end;

function TTyListGroupsEditorForm.NodeItemOf(AObject: TPersistent): TTyTreeNodeItem;
var
  i: Integer;
begin
  Result := nil;
  if AObject = nil then Exit;
  for i := 0 to FTree.Items.Count - 1 do
    if FTree.Items[i].Data = Pointer(AObject) then
      Exit(FTree.Items[i]);
end;

function TTyListGroupsEditorForm.SelectedObject: TPersistent;
var
  i: Integer;
begin
  Result := nil;
  if FTree.Selected = nil then Exit;
  for i := 0 to FTree.Items.Count - 1 do
    if FTree.Items[i].Node = FTree.Selected then
      Exit(TPersistent(FTree.Items[i].Data));
end;

procedure TTyListGroupsEditorForm.SelectObject(AObject: TPersistent);
var
  it: TTyTreeNodeItem;
begin
  it := NodeItemOf(AObject);
  if (it <> nil) and (it.Node <> nil) then
    FTree.Selected := it.Node;
end;

procedure TTyListGroupsEditorForm.TreeSelectionChanged(Sender: TObject);
begin
  if not FRebuilding then
    NotifySelection;
end;

procedure TTyListGroupsEditorForm.TreeChange(Sender: TTyTreeView; ANode: PTyTreeNode);
begin
  if not FRebuilding then
    NotifySelection;
end;

procedure TTyListGroupsEditorForm.NotifySelection;
begin
  if Assigned(FOnSelectObject) then
    FOnSelectObject(Self, SelectedObject);
end;

procedure TTyListGroupsEditorForm.NotifyEdited;
begin
  if Assigned(FOnEdited) then
    FOnEdited(Self);
end;

{ ---- the tree as data ---- }

function TTyListGroupsEditorForm.NodeCount: Integer;
begin
  Result := FTree.Items.Count;
end;

function TTyListGroupsEditorForm.NodeObject(AIndex: Integer): TPersistent;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < FTree.Items.Count) then
    Result := TPersistent(FTree.Items[AIndex].Data);
end;

function TTyListGroupsEditorForm.NodeLevel(AIndex: Integer): Integer;
begin
  Result := -1;
  if (AIndex >= 0) and (AIndex < FTree.Items.Count) then
    Result := FTree.Items[AIndex].Level;
end;

function TTyListGroupsEditorForm.NodeCaption(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < FTree.Items.Count) then
    Result := FTree.Items[AIndex].Text;
end;

{ ---- actions ---- }

procedure TTyListGroupsEditorForm.AddGroup;
var
  g: TTyListGroup;
begin
  if FPanel = nil then Exit;
  g := FPanel.Groups.Add;
  g.Caption := Format('Group%d', [FPanel.Groups.Count]);
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
  if FPanel = nil then Exit;
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
    if idx >= FPanel.Groups.Count then idx := FPanel.Groups.Count - 1;
    if idx >= 0 then landOn := FPanel.Groups[idx];
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
  if sel is TTyListGroup then cnt := FPanel.Groups.Count
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
