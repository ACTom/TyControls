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

  TTyTreeNodeEvent    = procedure(Sender: TTyTreeView; Node: PTyTreeNode) of object;
  TTyTreeChangingEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean) of object;
  TTyTreeInitNodeEvent     = procedure(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates) of object;
  TTyTreeInitChildrenEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var ChildCount: Cardinal) of object;

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
    { B1 scroll engine cache fields }
    FCacheValid: Boolean;
    FRangeY:    Integer;
    { A5 events }
    FOnInitNode:     TTyTreeInitNodeEvent;
    FOnInitChildren: TTyTreeInitChildrenEvent;
    FOnExpanding:    TTyTreeChangingEvent;
    FOnExpanded:     TTyTreeNodeEvent;
    FOnCollapsing:   TTyTreeChangingEvent;
    FOnCollapsed:    TTyTreeNodeEvent;
    function  MakeNewNode: PTyTreeNode;
    procedure FreeNodeMem(Node: PTyTreeNode);
    procedure SetNodeDataSize(AValue: Integer);
    function  GetRootNodeCount: Cardinal;
    procedure SetRootNodeCount(AValue: Cardinal);
    procedure AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
    procedure AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
    procedure InvalidateTreeLayout;
    { A5 helpers }
    function  ComputeExpandedSubtreeHeight(Node: PTyTreeNode): Integer;
    function  GetExpanded(Node: PTyTreeNode): Boolean;
    procedure SetExpanded(Node: PTyTreeNode; AValue: Boolean);
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
    { A5 lifecycle }
    procedure InitNode(Node: PTyTreeNode);
    procedure InitChildren(Node: PTyTreeNode);
    procedure ToggleNode(Node: PTyTreeNode; AExpand: Boolean);
    { A5 iterators }
    function GetFirstChild(Node: PTyTreeNode): PTyTreeNode;
    function GetLastChild(Node: PTyTreeNode): PTyTreeNode;
    function GetNextSibling(Node: PTyTreeNode): PTyTreeNode;
    function GetPrevSibling(Node: PTyTreeNode): PTyTreeNode;
    function GetParent(Node: PTyTreeNode): PTyTreeNode;
    function GetNodeLevel(Node: PTyTreeNode): Integer;
    function GetFirst: PTyTreeNode;
    function GetNext(Node: PTyTreeNode): PTyTreeNode;
    function GetFirstVisibleNoInit: PTyTreeNode;
    function GetNextVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
    function GetPreviousVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
    { B1 helpers — used by tests + scroll engine }
    function  SumVisibleHeights: Integer;
    property Expanded[Node: PTyTreeNode]: Boolean read GetExpanded write SetExpanded;
    property RootNode: PTyTreeNode read FRoot;
    property RangeY: Integer read FRangeY;
  published
    property NodeDataSize: Integer read FNodeDataSize write SetNodeDataSize default -1;
    property DefaultNodeHeight: Integer read FDefaultNodeHeight write FDefaultNodeHeight default 18;
    property RootNodeCount: Cardinal read GetRootNodeCount write SetRootNodeCount default 0;
    property OnFreeNode:      TTyTreeNodeEvent         read FOnFreeNode      write FOnFreeNode;
    property OnInitNode:      TTyTreeInitNodeEvent     read FOnInitNode      write FOnInitNode;
    property OnInitChildren:  TTyTreeInitChildrenEvent read FOnInitChildren  write FOnInitChildren;
    property OnExpanding:     TTyTreeChangingEvent     read FOnExpanding     write FOnExpanding;
    property OnExpanded:      TTyTreeNodeEvent         read FOnExpanded      write FOnExpanded;
    property OnCollapsing:    TTyTreeChangingEvent     read FOnCollapsing    write FOnCollapsing;
    property OnCollapsed:     TTyTreeNodeEvent         read FOnCollapsed     write FOnCollapsed;
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
{ Propagates a pixel delta up the ancestor chain.
  INVARIANT: a parent's TotalHeight includes a child's contribution ONLY when the
  PARENT is expanded.  Therefore, before adding Delta to a parent, we check whether
  the PARENT is expanded — not whether the child (run) is expanded.
  This is ordering-independent: the caller may set/clear nsExpanded on Node before
  or after calling AdjustTotalHeight and the result is still correct.
  (The old code checked run^.States BEFORE climbing, which wrongly inflated a
  collapsed ancestor when a deeply-nested node was expanded programmatically.) }
var
  run, up: PTyTreeNode;
begin
  if Delta = 0 then Exit;
  Inc(Node^.TotalHeight, Delta);          // the changed node's own total always reflects the delta
  run := Node;
  while True do
  begin
    up := run^.Parent;
    if (up = nil) or (up = PTyTreeNode(Self)) then Break;  // reached the root sentinel
    if not (nsExpanded in up^.States) then Break;  // parent collapsed: its total excludes run's subtree
    Inc(up^.TotalHeight, Delta);
    run := up;
  end;
end;

procedure TTyTreeView.InvalidateTreeLayout;
begin
  // B1: mark the position cache dirty and recompute FRangeY.
  // The cache itself is built lazily in Task B3; here we just invalidate the flag.
  FCacheValid := False;
  FRangeY     := Integer(FRoot^.TotalHeight);
  Invalidate;
end;

function TTyTreeView.SumVisibleHeights: Integer;
{ Walk all screen-order visible nodes and sum their NodeHeight values.
  Used ONLY by the B1 invariant test and debug assertions — not in the hot path. }
var
  n: PTyTreeNode;
begin
  Result := 0;
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    Inc(Result, n^.NodeHeight);
    n := GetNextVisibleNoInit(n);
  end;
  // Add the root's own NodeHeight (the root sentinel always counts itself)
  Inc(Result, FRoot^.NodeHeight);
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
    // Shrink: delete tail children one by one (DeleteNode handles recursion + OnFreeNode).
    // Each DeleteNode call already fires InvalidateTreeLayout; no extra call needed here.
    while Node^.ChildCount > NewCount do
      DeleteNode(Node^.LastChild);
    Exit;  // skip the grow-path InvalidateTreeLayout below
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
  // dc = how many nodes we're removing from ancestor counts.
  // All children have already been freed above, so TotalCount is authoritatively 1 here.
  dc := Node^.TotalCount;  // = 1 after recursive child frees; avoids magic literal

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

{ ── A5 ── lazy lifecycle ─────────────────────────────────────────────────── }

{ ComputeExpandedSubtreeHeight
  Returns the total pixel height that Node and ALL its currently-expanded
  descendants would occupy if Node itself were visible.
  This is a pure recursive walk — called only when we NEED the exact value
  (on expand/collapse) and not in the hot paint path. }
function TTyTreeView.ComputeExpandedSubtreeHeight(Node: PTyTreeNode): Integer;
var
  child: PTyTreeNode;
begin
  if Node = nil then begin Result := 0; Exit; end;
  Result := Node^.NodeHeight;
  if (nsExpanded in Node^.States) and (Node^.FirstChild <> nil) then
  begin
    child := Node^.FirstChild;
    while child <> nil do
    begin
      Inc(Result, ComputeExpandedSubtreeHeight(child));
      child := child^.NextSibling;
    end;
  end;
end;

function TTyTreeView.GetExpanded(Node: PTyTreeNode): Boolean;
begin
  Result := (Node <> nil) and (nsExpanded in Node^.States);
end;

procedure TTyTreeView.InitNode(Node: PTyTreeNode);
var
  initStates: TTyNodeInitStates;
begin
  if (Node = nil) or (Node = FRoot) or (nsInitialized in Node^.States) then Exit;
  Include(Node^.States, nsInitialized);
  initStates := [];
  if Assigned(FOnInitNode) then
    FOnInitNode(Self, Node^.Parent, Node, initStates);
  if ivsHasChildren in initStates then
    Include(Node^.States, nsHasChildren);
  if ivsSelected in initStates then
    Include(Node^.States, nsSelected);   // SetSelected is Task C1; just set the bit here
  if ivsExpanded in initStates then
    SetExpanded(Node, True);             // materialise children if the app requests auto-expand
end;

procedure TTyTreeView.InitChildren(Node: PTyTreeNode);
var
  c: Cardinal;
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if Node^.ChildCount > 0 then Exit;           // already materialised
  if not (nsHasChildren in Node^.States) then Exit;
  c := 0;
  if Assigned(FOnInitChildren) then
    FOnInitChildren(Self, Node, c);
  if c > 0 then
    SetChildCount(Node, c)
  else
    Exclude(Node^.States, nsHasChildren);       // app says "actually no children"
end;

procedure TTyTreeView.SetExpanded(Node: PTyTreeNode; AValue: Boolean);
{ Height-bookkeeping invariant (asserted by B1):
    RootNode^.TotalHeight = sum of NodeHeight for every visible (nsVisible + reachable via
    nsExpanded ancestors) node.
  When a node is EXPANDED:
    • Its children are just-materialised collapsed skeletons; each child's TotalHeight = NodeHeight.
    • We add the delta = ComputeExpandedSubtreeHeight(Node) − current TotalHeight.
      (current TotalHeight equals NodeHeight while collapsed.)
  When a node is COLLAPSED:
    • All descendant heights are subtracted.
    • The delta = NodeHeight − current TotalHeight  (a negative number). }
var
  allowed: Boolean;
  childrenH: Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if not (nsHasChildren in Node^.States) then Exit;
  if AValue = (nsExpanded in Node^.States) then Exit;

  if AValue then
  begin
    // ── Expanding ──
    allowed := True;
    if Assigned(FOnExpanding) then FOnExpanding(Self, Node, allowed);
    if not allowed then Exit;

    InitChildren(Node);
    Include(Node^.States, nsExpanded);

    // Add the newly-visible descendant heights.
    // While collapsed, TotalHeight == NodeHeight.
    // ComputeExpandedSubtreeHeight(Node) = NodeHeight + sum(child heights).
    childrenH := ComputeExpandedSubtreeHeight(Node) - Integer(Node^.TotalHeight);
    if childrenH <> 0 then AdjustTotalHeight(Node, childrenH);

    if Assigned(FOnExpanded) then FOnExpanded(Self, Node);
  end
  else
  begin
    // ── Collapsing ──
    allowed := True;
    if Assigned(FOnCollapsing) then FOnCollapsing(Self, Node, allowed);
    if not allowed then Exit;

    // childrenH is negative: NodeHeight − TotalHeight (TotalHeight ≥ NodeHeight while expanded).
    // IMPORTANT: call AdjustTotalHeight BEFORE Exclude(nsExpanded), so that
    // AdjustTotalHeight can still climb past this node to its ancestors.
    // (AdjustTotalHeight stops climbing at the first non-expanded node; if we
    // cleared nsExpanded first, it would stop right here and leave root stale.)
    childrenH := Integer(Node^.NodeHeight) - Integer(Node^.TotalHeight);
    if childrenH <> 0 then AdjustTotalHeight(Node, childrenH);
    Exclude(Node^.States, nsExpanded);

    if Assigned(FOnCollapsed) then FOnCollapsed(Self, Node);
  end;
  InvalidateTreeLayout;
end;

procedure TTyTreeView.ToggleNode(Node: PTyTreeNode; AExpand: Boolean);
begin
  SetExpanded(Node, AExpand);
end;

{ ── A5 ── iterators ──────────────────────────────────────────────────────── }

function TTyTreeView.GetFirstChild(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := FRoot^.FirstChild
  else Result := Node^.FirstChild;
end;

function TTyTreeView.GetLastChild(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := FRoot^.LastChild
  else Result := Node^.LastChild;
end;

function TTyTreeView.GetNextSibling(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := nil
  else Result := Node^.NextSibling;
end;

function TTyTreeView.GetPrevSibling(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := nil
  else Result := Node^.PrevSibling;
end;

{ GetParent: returns nil when Node is a top-level node (its Parent is the hidden root).
  Mirrors VTV semantics: GetNodeParent returns nil for root-level nodes. }
function TTyTreeView.GetParent(Node: PTyTreeNode): PTyTreeNode;
begin
  if (Node = nil) or (Node = FRoot) then
    Result := nil
  else if Node^.Parent = FRoot then
    Result := nil     // top-level node — parent is the hidden root sentinel
  else if Node^.Parent = PTyTreeNode(Self) then
    Result := nil     // Node IS the root (shouldn't happen but be safe)
  else
    Result := Node^.Parent;
end;

{ GetNodeLevel: returns 0 for top-level nodes (direct children of the hidden root).
  Counts parent hops until we hit the hidden root or the sentinel. }
function TTyTreeView.GetNodeLevel(Node: PTyTreeNode): Integer;
var
  run: PTyTreeNode;
begin
  Result := 0;
  if (Node = nil) or (Node = FRoot) then Exit;
  run := Node^.Parent;
  while (run <> nil) and (run <> FRoot) and (run <> PTyTreeNode(Self)) do
  begin
    Inc(Result);
    run := run^.Parent;
  end;
end;

{ GetFirst: depth-first pre-order first node, inits it. }
function TTyTreeView.GetFirst: PTyTreeNode;
begin
  Result := FRoot^.FirstChild;
  if Result <> nil then InitNode(Result);
end;

{ GetNext: depth-first pre-order successor, inits any node we land on. }
function TTyTreeView.GetNext(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then begin Result := nil; Exit; end;

  // Descend into children first
  if Node^.FirstChild <> nil then
  begin
    Result := Node^.FirstChild;
    InitNode(Result);
    Exit;
  end;

  // No children — try next sibling, then climb
  Result := Node;
  repeat
    if Result^.NextSibling <> nil then
    begin
      Result := Result^.NextSibling;
      InitNode(Result);
      Exit;
    end;
    Result := Result^.Parent;
    if (Result = FRoot) or (Result = PTyTreeNode(Self)) then
    begin
      Result := nil;
      Exit;
    end;
  until False;
end;

{ GetFirstVisibleNoInit: first screen-order visible node (no init side-effects). }
function TTyTreeView.GetFirstVisibleNoInit: PTyTreeNode;
begin
  Result := FRoot^.FirstChild;
  // Advance past any non-visible top-level nodes
  while (Result <> nil) and not (nsVisible in Result^.States) do
    Result := Result^.NextSibling;
end;

{ GetNextVisibleNoInit: screen-order successor, skipping collapsed subtrees.
  Never inits nodes — safe to call from paint / scroll. }
function TTyTreeView.GetNextVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
begin
  Result := Node;
  repeat
    if (nsExpanded in Result^.States) and (Result^.FirstChild <> nil) then
      Result := Result^.FirstChild
    else
      while Result <> nil do
      begin
        if Result^.NextSibling <> nil then
        begin
          Result := Result^.NextSibling;
          Break;
        end;
        Result := Result^.Parent;
        if Result = FRoot then
        begin
          Result := nil;
          Break;
        end;
      end;
  until (Result = nil) or (nsVisible in Result^.States);
end;

{ GetPreviousVisibleNoInit: reverse screen-order predecessor (no init).
  Walk to the previous sibling's last expanded descendant, or to the parent. }
function TTyTreeView.GetPreviousVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
var
  prev: PTyTreeNode;
begin
  if Node = nil then begin Result := nil; Exit; end;

  // Try the previous sibling (then go down into its last expanded descendant)
  if Node^.PrevSibling <> nil then
  begin
    Result := Node^.PrevSibling;
    // Descend into the last expanded child chain
    while (nsExpanded in Result^.States) and (Result^.LastChild <> nil) do
      Result := Result^.LastChild;
    // skip invisible (shouldn't happen in normal trees, but be safe)
    while (Result <> nil) and not (nsVisible in Result^.States) do
    begin
      prev := Result^.PrevSibling;
      if prev <> nil then Result := prev
      else begin Result := nil; Break; end;
    end;
    Exit;
  end;

  // No previous sibling — go to parent (unless parent is root)
  Result := Node^.Parent;
  if (Result = nil) or (Result = FRoot) or (Result = PTyTreeNode(Self)) then
    Result := nil;
end;

end.
