unit tyControls.Dialogs.StructureEditor;
{$mode objfpc}{$H+}
{ The SHARED SHAPE of every structure editor: one modeless window, one tree over a
  component's whole hierarchical model, an action-button column, and the two IDE-facing
  events (OnSelectObject routes the tree's selection into the Object Inspector,
  OnEdited marks the designer modified). TTyListGroupsEditorForm, the TreeView node
  editor and the Cascader editor are this class plus their model verbs -- one shape,
  N vocabularies, instead of N copies of the window.

  Edits go to the subject DIRECTLY, no working copy: the form runs modeless next to
  the OI, which shows the live selected object -- a copy would hand the OI a different
  object than the one that streams. Both events stay nil in plain runtime use.

  Subclass contract: build the buttons in CreateNew with MakeActionButton, then call
  FinishCreation; fill the tree in BuildTree with AddNode (it wires Data and expands). }
interface
uses
  Classes, SysUtils, Types, Controls, Forms,
  tyControls.Types, tyControls.StrConsts, tyControls.Controller,
  tyControls.Dialogs, tyControls.Button, tyControls.TreeView;

type
  TTySelectObjectEvent = procedure(Sender: TObject; AObject: TPersistent) of object;

  TTyStructureEditorForm = class(TTyDialog)
  private
    FSubject: TComponent;
    FTree: TTyTreeView;
    FButtons: array of TTyButton;
    FOnSelectObject: TTySelectObjectEvent;
    FOnEdited: TNotifyEvent;
    FRebuilding: Boolean;
    procedure TreeSelectionChanged(Sender: TObject);
    procedure TreeChange(Sender: TTyTreeView; ANode: PTyTreeNode);
    function NodeItemOf(AObject: TPersistent): TTyTreeNodeItem;
  protected
    { The window title's fixed half; SetSubject appends ' - <SubjectTitle>' to it.
      The subclass constructor sets it (and the initial Caption). }
    FBaseCaption: string;
    procedure LayoutContent; override;
    procedure DoClose(var CloseAction: TCloseAction); override;
    { Build one action button (right column, in call order). CreateNew-time only. }
    function MakeActionButton(const ACaption: string; AHandler: TNotifyEvent): TTyButton;
    { Size the dialog once every button exists -- the subclass constructor's last call. }
    procedure FinishCreation(AWidth, AHeight: Integer);
    { Rebuild the tree's rows from FSubject. Called inside a guarded rebuild: selection
      events are muted, and the previous selection is re-applied afterwards when its
      object survived. Use AddNode for every row. }
    procedure BuildTree; virtual; abstract;
    { The caption suffix for a live subject; default is its Name. }
    function SubjectTitle: string; virtual;
    { What to select when the editor aims at a subject and nothing is selected yet --
      so the actions have a target from click one. Default: the first root row. }
    procedure SelectDefault; virtual;
    procedure NotifyEdited;
    procedure NotifySelection;
    { The one way rows enter the tree: caption + the model object it stands for. }
    function AddNode(AParent: TTyTreeNodeItem; const ACaption: string;
      AObject: TPersistent): TTyTreeNodeItem;
    property Tree: TTyTreeView read FTree;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    { Aim the editor at a component (nil detaches). Rebuilds, then SelectDefault. }
    procedure SetSubject(ASubject: TComponent);
    { Rebuild the tree, keeping the selection when its object survived -- the IDE side
      calls this when the model was edited elsewhere (e.g. in the OI). }
    procedure RefreshFromModel;

    function SelectedObject: TPersistent;
    procedure SelectObject(AObject: TPersistent);

    { The tree as data, for assertions: flat row count, and each row's payload/level. }
    function NodeCount: Integer;
    function NodeObject(AIndex: Integer): TPersistent;
    function NodeLevel(AIndex: Integer): Integer;
    function NodeCaption(AIndex: Integer): string;

    property Subject: TComponent read FSubject;
    property OnSelectObject: TTySelectObjectEvent read FOnSelectObject write FOnSelectObject;
    property OnEdited: TNotifyEvent read FOnEdited write FOnEdited;
  end;

implementation

{ ---- construction / layout ---- }

constructor TTyStructureEditorForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  Constraints.MinWidth := 360;
  Constraints.MinHeight := 300;

  FTree := TTyTreeView.Create(Self);
  FTree.Parent := Self;
  { BOTH selection events: programmatic selects (Selected := N) fire OnChange, while
    the interactive paths (mouse, keyboard, select-all) fire OnSelectionChanged. }
  FTree.OnSelectionChanged := @TreeSelectionChanged;
  FTree.OnChange := @TreeChange;
end;

function TTyStructureEditorForm.MakeActionButton(const ACaption: string;
  AHandler: TNotifyEvent): TTyButton;
begin
  Result := TTyButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  SetLength(FButtons, Length(FButtons) + 1);
  FButtons[High(FButtons)] := Result;
end;

procedure TTyStructureEditorForm.FinishCreation(AWidth, AHeight: Integer);
begin
  AutoSizeToContent(AWidth, AHeight);
  LayoutContent;
end;

procedure TTyStructureEditorForm.LayoutContent;
const
  Gap = 8;
  BtnW = 120;
var
  r: TRect;
  x, y, treeW, btnH, i: Integer;
begin
  if (FTree = nil) or (Length(FButtons) = 0) then Exit;  { resize during construction }
  r := ContentRect;
  btnH := TyDensityHeight(nil, TyDlgEditH);
  treeW := (r.Right - r.Left) - 2 * TyDlgPad - BtnW - Gap;
  FTree.SetBounds(r.Left + TyDlgPad, r.Top + TyDlgPad,
    treeW, (r.Bottom - r.Top) - 2 * TyDlgPad);

  x := r.Left + TyDlgPad + treeW + Gap;
  y := r.Top + TyDlgPad;
  for i := 0 to High(FButtons) do
  begin
    FButtons[i].SetBounds(x, y, BtnW, btnH);
    Inc(y, btnH + Gap div 2);
  end;
end;

procedure TTyStructureEditorForm.DoClose(var CloseAction: TCloseAction);
begin
  inherited DoClose(CloseAction);
  { A modeless editor is a reusable window: closing hides it, its owner frees it. }
  CloseAction := caHide;
end;

{ ---- model <-> tree ---- }

function TTyStructureEditorForm.SubjectTitle: string;
begin
  if FSubject <> nil then Result := FSubject.Name else Result := '';
end;

procedure TTyStructureEditorForm.SetSubject(ASubject: TComponent);
begin
  FSubject := ASubject;
  if (FSubject <> nil) and (SubjectTitle <> '') then
    Caption := FBaseCaption + ' - ' + SubjectTitle
  else
    Caption := FBaseCaption;
  RefreshFromModel;
  if SelectedObject = nil then
    SelectDefault;
end;

procedure TTyStructureEditorForm.SelectDefault;
begin
  if FTree.Items.Count > 0 then
    SelectObject(TPersistent(FTree.Items[0].Data));
end;

procedure TTyStructureEditorForm.RefreshFromModel;
var
  keep: TPersistent;
begin
  keep := SelectedObject;   { compared by pointer only below -- never dereferenced,
                              so a selection deleted elsewhere degrades to nil }
  FRebuilding := True;
  try
    FTree.Items.BeginUpdate;
    try
      FTree.Items.Clear;
      if FSubject <> nil then
        BuildTree;
    finally
      FTree.Items.EndUpdate;
    end;
  finally
    FRebuilding := False;
  end;
  if keep <> nil then
    SelectObject(keep);
end;

function TTyStructureEditorForm.AddNode(AParent: TTyTreeNodeItem; const ACaption: string;
  AObject: TPersistent): TTyTreeNodeItem;
begin
  if AParent = nil then
    Result := FTree.Items.Add(nil, ACaption)
  else
    Result := FTree.Items.AddChild(AParent, ACaption);
  Result.Data := AObject;
  Result.Expanded := True;
end;

function TTyStructureEditorForm.NodeItemOf(AObject: TPersistent): TTyTreeNodeItem;
var
  i: Integer;
begin
  Result := nil;
  if AObject = nil then Exit;
  for i := 0 to FTree.Items.Count - 1 do
    if FTree.Items[i].Data = Pointer(AObject) then
      Exit(FTree.Items[i]);
end;

function TTyStructureEditorForm.SelectedObject: TPersistent;
var
  i: Integer;
begin
  Result := nil;
  if FTree.Selected = nil then Exit;
  for i := 0 to FTree.Items.Count - 1 do
    if FTree.Items[i].Node = FTree.Selected then
      Exit(TPersistent(FTree.Items[i].Data));
end;

procedure TTyStructureEditorForm.SelectObject(AObject: TPersistent);
var
  it: TTyTreeNodeItem;
begin
  it := NodeItemOf(AObject);
  if (it <> nil) and (it.Node <> nil) then
    FTree.Selected := it.Node;
end;

procedure TTyStructureEditorForm.TreeSelectionChanged(Sender: TObject);
begin
  if not FRebuilding then
    NotifySelection;
end;

procedure TTyStructureEditorForm.TreeChange(Sender: TTyTreeView; ANode: PTyTreeNode);
begin
  if not FRebuilding then
    NotifySelection;
end;

procedure TTyStructureEditorForm.NotifySelection;
begin
  if Assigned(FOnSelectObject) then
    FOnSelectObject(Self, SelectedObject);
end;

procedure TTyStructureEditorForm.NotifyEdited;
begin
  if Assigned(FOnEdited) then
    FOnEdited(Self);
end;

{ ---- the tree as data ---- }

function TTyStructureEditorForm.NodeCount: Integer;
begin
  Result := FTree.Items.Count;
end;

function TTyStructureEditorForm.NodeObject(AIndex: Integer): TPersistent;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < FTree.Items.Count) then
    Result := TPersistent(FTree.Items[AIndex].Data);
end;

function TTyStructureEditorForm.NodeLevel(AIndex: Integer): Integer;
begin
  Result := -1;
  if (AIndex >= 0) and (AIndex < FTree.Items.Count) then
    Result := FTree.Items[AIndex].Level;
end;

function TTyStructureEditorForm.NodeCaption(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < FTree.Items.Count) then
    Result := FTree.Items[AIndex].Text;
end;

end.
