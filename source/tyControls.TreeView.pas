unit tyControls.TreeView;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ScrollBar;

type
  PTyTreeNode = ^TTyTreeNode;

  TTyNodeState = (nsInitialized, nsHasChildren, nsExpanded, nsVisible, nsSelected,
                  nsHeightMeasured, nsDeleting, nsClearing);
  TTyNodeStates = set of TTyNodeState;

  TTyNodeInitState = (ivsHasChildren, ivsExpanded, ivsSelected, ivsReInit);
  TTyNodeInitStates = set of TTyNodeInitState;

  TTyTreeNode = record
    Index, ChildCount: Cardinal;
    NodeHeight: Word;
    States: TTyNodeStates;
    TotalCount: Cardinal;       // self + all descendants
    TotalHeight: Cardinal;      // pixels of self + expanded/visible descendants
    Parent, PrevSibling, NextSibling, FirstChild, LastChild: PTyTreeNode;
    // user data blob (NodeDataSize bytes) follows at offset TreeNodeSize
  end;

  TTyTreeView = class;

  TTyTreeNodeEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode) of object;

const
  TreeNodeSize = (SizeOf(TTyTreeNode) + 7) and not 7;  // pointer-aligned struct stride

type
  TTyTreeView = class(TTyCustomControl)
  private
    FRoot: PTyTreeNode;
    FNodeDataSize: Integer;     // -1 until set
    FNodeAllocSize: Integer;    // TreeNodeSize + Max(0, FNodeDataSize)
    FDefaultNodeHeight: Integer;
    FOnFreeNode: TTyTreeNodeEvent;
    function  MakeNewNode: PTyTreeNode;
    procedure FreeNodeMem(Node: PTyTreeNode);
    procedure SetNodeDataSize(AValue: Integer);
    function  GetRootNodeCount: Cardinal;
    procedure SetRootNodeCount(AValue: Cardinal);
    procedure AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
    procedure AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
    procedure InvalidateTreeLayout;
  protected
    function GetStyleTypeKey: string; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    function  GetNodeData(Node: PTyTreeNode): Pointer;
    procedure SetChildCount(Node: PTyTreeNode; NewCount: Cardinal);
    function  AddChild(AParent: PTyTreeNode): PTyTreeNode;
    procedure DeleteNode(Node: PTyTreeNode);
    procedure Clear;
    property RootNode: PTyTreeNode read FRoot;
  published
    property NodeDataSize: Integer read FNodeDataSize write SetNodeDataSize default -1;
    property DefaultNodeHeight: Integer read FDefaultNodeHeight write FDefaultNodeHeight default 18;
    property RootNodeCount: Cardinal read GetRootNodeCount write SetRootNodeCount default 0;
    property OnFreeNode: TTyTreeNodeEvent read FOnFreeNode write FOnFreeNode;
  end;

implementation

{ TTyTreeView }

function TTyTreeView.GetStyleTypeKey: string;
begin
  Result := 'TyTreeView';
end;

constructor TTyTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNodeDataSize := -1;
  FNodeAllocSize := TreeNodeSize;
  FDefaultNodeHeight := 18;
  FRoot := MakeNewNode;                  // hidden root
  FRoot^.Parent := PTyTreeNode(Self);    // sentinel — root's Parent points back at the tree
  FRoot^.PrevSibling := FRoot;
  FRoot^.NextSibling := FRoot;
  // Root is always "expanded" so its children contribute height
  Include(FRoot^.States, nsExpanded);
  Width := 200; Height := 160;
end;

destructor TTyTreeView.Destroy;
begin
  // Free all child nodes first (without firing OnFreeNode in Destroy —
  // event handler may already be gone; clear it first)
  FOnFreeNode := nil;
  Clear;
  if FRoot <> nil then
  begin
    FreeNodeMem(FRoot);
    FRoot := nil;
  end;
  inherited Destroy;
end;

function TTyTreeView.MakeNewNode: PTyTreeNode;
begin
  Result := AllocMem(FNodeAllocSize);    // zero-filled by AllocMem
  Result^.States := [nsVisible];
  Result^.NodeHeight := FDefaultNodeHeight;
  // TotalCount and TotalHeight for a fresh leaf: count=1, height=NodeHeight
  Result^.TotalCount := 1;
  Result^.TotalHeight := FDefaultNodeHeight;
end;

procedure TTyTreeView.FreeNodeMem(Node: PTyTreeNode);
begin
  FreeMem(Node);
end;

procedure TTyTreeView.SetNodeDataSize(AValue: Integer);
begin
  if FNodeDataSize = AValue then Exit;
  // Must be set before any nodes exist (changes the allocation stride).
  FNodeDataSize := AValue;
  if AValue > 0 then FNodeAllocSize := TreeNodeSize + AValue
  else FNodeAllocSize := TreeNodeSize;
end;

function TTyTreeView.GetNodeData(Node: PTyTreeNode): Pointer;
begin
  if (FNodeDataSize <= 0) or (Node = nil) or (Node = FRoot) then
    Result := nil
  else
    Result := PByte(Node) + TreeNodeSize;
end;

procedure TTyTreeView.AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
var
  run: PTyTreeNode;
begin
  run := Node;
  while run <> nil do
  begin
    Inc(run^.TotalCount, Delta);
    run := run^.Parent;
    if run = PTyTreeNode(Self) then Break;  // reached the sentinel above root
  end;
end;

procedure TTyTreeView.AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
// Propagates a pixel delta up the chain, but STOPS climbing past a collapsed ancestor
// (a collapsed node's TotalHeight does not include hidden descendants).
var
  run: PTyTreeNode;
begin
  run := Node;
  while run <> nil do
  begin
    Inc(run^.TotalHeight, Delta);
    // Stop climbing if this node is not expanded: its ancestors don't see the delta
    // (its collapsed TotalHeight is just its own row, not the subtree)
    if not (nsExpanded in run^.States) then Break;
    run := run^.Parent;
    if run = PTyTreeNode(Self) then Break;  // sentinel
  end;
end;

procedure TTyTreeView.InvalidateTreeLayout;
begin
  // Phase B will implement the position cache + range update.
  // For A1-A4, just repaint.
  Invalidate;
end;

function TTyTreeView.GetRootNodeCount: Cardinal;
begin
  Result := FRoot^.ChildCount;
end;

procedure TTyTreeView.SetRootNodeCount(AValue: Cardinal);
begin
  SetChildCount(FRoot, AValue);
end;

procedure TTyTreeView.SetChildCount(Node: PTyTreeNode; NewCount: Cardinal);
var
  i: Cardinal;
  child, prev: PTyTreeNode;
  addedH, addedC: Integer;
begin
  if NewCount = Node^.ChildCount then Exit;
  if NewCount > Node^.ChildCount then
  begin
    addedH := 0; addedC := 0;
    prev := Node^.LastChild;
    for i := Node^.ChildCount to NewCount - 1 do
    begin
      child := MakeNewNode;
      child^.Parent := Node;
      child^.Index := i;
      child^.PrevSibling := prev;
      if prev <> nil then prev^.NextSibling := child
      else Node^.FirstChild := child;
      Node^.LastChild := child;
      prev := child;
      Inc(addedC);
      Inc(addedH, child^.NodeHeight);
    end;
    Node^.ChildCount := NewCount;
    // Each new node has TotalCount=1; increment ancestors by addedC
    AdjustTotalCount(Node, addedC);
    // Children contribute height only when parent is expanded (root is always expanded)
    if (nsExpanded in Node^.States) or (Node = FRoot) then
      AdjustTotalHeight(Node, addedH);
  end
  else
  begin
    // Shrink: delete tail children one by one (DeleteNode handles recursion + OnFreeNode)
    while Node^.ChildCount > NewCount do
      DeleteNode(Node^.LastChild);
  end;
  InvalidateTreeLayout;
end;

function TTyTreeView.AddChild(AParent: PTyTreeNode): PTyTreeNode;
var
  p: PTyTreeNode;
begin
  if AParent = nil then p := FRoot else p := AParent;
  SetChildCount(p, p^.ChildCount + 1);
  Result := p^.LastChild;
  // Mark the parent as having children if it isn't the root and wasn't already marked
  if (p <> FRoot) and not (nsHasChildren in p^.States) then
    Include(p^.States, nsHasChildren);
end;

procedure TTyTreeView.DeleteNode(Node: PTyTreeNode);
var
  nodeParent: PTyTreeNode;
  dh, dc: Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;

  // Recursively free all children first (depth-first)
  while Node^.FirstChild <> nil do DeleteNode(Node^.FirstChild);

  nodeParent := Node^.Parent;
  // dc = how many nodes we're removing from ancestor counts
  // After the recursive child deletions above, this node is a leaf, so TotalCount=1
  dc := 1;  // Node^.TotalCount is now 1 (all children already gone)

  // Height delta: only subtract from ancestors when nodeParent contributes visible heights
  if (nsExpanded in nodeParent^.States) or (nodeParent = FRoot) then
    dh := Node^.NodeHeight   // node is a leaf now, its TotalHeight = NodeHeight
  else
    dh := 0;

  // Fire OnFreeNode so app can release managed fields in the data blob
  if Assigned(FOnFreeNode) then
    FOnFreeNode(Self, Node);

  // Unlink from siblings
  if Node^.PrevSibling <> nil then
    Node^.PrevSibling^.NextSibling := Node^.NextSibling
  else
    nodeParent^.FirstChild := Node^.NextSibling;

  if Node^.NextSibling <> nil then
    Node^.NextSibling^.PrevSibling := Node^.PrevSibling
  else
    nodeParent^.LastChild := Node^.PrevSibling;

  Dec(nodeParent^.ChildCount);

  // Adjust aggregate counts on the nodeParent chain
  AdjustTotalCount(nodeParent, -dc);
  if dh <> 0 then AdjustTotalHeight(nodeParent, -dh);

  // Clear nsHasChildren when the last child is removed
  if nodeParent^.ChildCount = 0 then
    Exclude(nodeParent^.States, nsHasChildren);

  FreeNodeMem(Node);
  InvalidateTreeLayout;
end;

procedure TTyTreeView.Clear;
begin
  while FRoot^.FirstChild <> nil do DeleteNode(FRoot^.FirstChild);
end;

end.
