# TTyTreeView ③a — Virtual Engine + Single-Column Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use `- [ ]` checkboxes.

**Goal:** A faithful VirtualTreeView-style virtual tree (`TTyTreeView`): a node-record store with 3-stage lazy init + inlined per-node data, an incremental-height + position-cache virtual scroll engine, and a single-column custom-drawn tree (expand/collapse, single-select, keyboard, images, tree lines, embedded scrollbars).

**Architecture:** One unit `source/tyControls.TreeView.pas`, `TTyTreeView = class(TTyCustomControl)`, painting via `TTyPainter`. The engine (node store + scroll) lives on the control but is exercised headlessly (no window handle). Pure helpers are factored out and unit-tested.

**Tech Stack:** FPC/Lazarus LCL, BGRABitmap, the `.tycss` theme engine, fpcunit. Reference: `…\VirtualTreeViewV5\Source\VirtualTrees.pas`.

**Spec:** `docs/superpowers/specs/2026-06-27-tycontrols-treeview-engine-design.md`. **Branch:** `feat/treeview-engine`.

---

## Conventions

- Build runtime pkg `lazbuild tycontrols.lpk`; tests `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → `Number of failures: 0`. **Baseline at branch start: 1115 run / 0 failures / 11 pre-existing env-errors.**
- New test unit: `RegisterTest(...)` in `initialization` + add the unit name to `tests/tytests.lpr` `uses`. New control unit → `<Item>` in `tycontrols.lpk`.
- `AssertEquals(expected, actual)` expected-first. PPI 96 in pixel tests.
- Mirror the windowed-control idiom from `source/tyControls.ListBox.pas` (embedded scrollbar + scrollable content) and `tyControls.Splitter.pas`/`GroupBox.pas` (RenderTo/CurrentStyle/DrawFrame/P.Scale).
- **Engine is testable WITHOUT a window:** a test creates the control, parents it to a `TForm` only if it needs paint; the node store / scroll math work on a control with no handle. Attach `OnInitChildren`/`OnInitNode`/`OnGetText` in the test, set `RootNodeCount`, drive expansion, assert.
- Commit per task, English, ending `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

# PHASE A — node store + lazy lifecycle

## Task A1: types + node allocation + GetNodeData

**Files:** Create `source/tyControls.TreeView.pas`; Create `tests/test.treeview.pas`; wire into `tycontrols.lpk` + `tests/tytests.lpr`.

The node record + the inline-data addressing. Data lives at a FIXED offset `TreeNodeSize` after the node pointer (avoids the empty-placeholder-offset subtlety).

- [ ] **Step 1 — unit skeleton + types + alloc.** Create `source/tyControls.TreeView.pas`:
```pascal
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

const
  TreeNodeSize = (SizeOf(TTyTreeNode) + 7) and not 7;   // pointer-aligned struct stride

type
  TTyTreeView = class(TTyCustomControl)
  private
    FRoot: PTyTreeNode;
    FNodeDataSize: Integer;     // -1 until set
    FNodeAllocSize: Integer;    // TreeNodeSize + Max(0, FNodeDataSize)
    FDefaultNodeHeight: Integer;
    function  MakeNewNode: PTyTreeNode;
    procedure FreeNodeMem(Node: PTyTreeNode);
    procedure SetNodeDataSize(AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    function GetNodeData(Node: PTyTreeNode): Pointer;
    property RootNode: PTyTreeNode read FRoot;
  published
    property NodeDataSize: Integer read FNodeDataSize write SetNodeDataSize default -1;
    property DefaultNodeHeight: Integer read FDefaultNodeHeight write FDefaultNodeHeight default 18;
  end;

implementation

constructor TTyTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNodeDataSize := -1;
  FNodeAllocSize := TreeNodeSize;
  FDefaultNodeHeight := 18;
  FRoot := MakeNewNode;                 // hidden root
  FRoot^.Parent := PTyTreeNode(Self);   // root's Parent points back at the tree (sentinel)
  FRoot^.PrevSibling := FRoot;
  FRoot^.NextSibling := FRoot;
  Width := 200; Height := 160;
end;

destructor TTyTreeView.Destroy;
begin
  // Clear (Task A4) frees all child nodes + fires OnFreeNode; here just free the root block.
  if FRoot <> nil then FreeNodeMem(FRoot);
  inherited Destroy;
end;

function TTyTreeView.MakeNewNode: PTyTreeNode;
begin
  Result := AllocMem(FNodeAllocSize);   // zero-filled
  Result^.States := [nsVisible];
  Result^.NodeHeight := FDefaultNodeHeight;
end;

procedure TTyTreeView.FreeNodeMem(Node: PTyTreeNode);
begin
  FreeMem(Node);
end;

procedure TTyTreeView.SetNodeDataSize(AValue: Integer);
begin
  if FNodeDataSize = AValue then Exit;
  // Must be set before any nodes exist (it changes the allocation stride).
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

end.
```
- [ ] **Step 2 — test** `tests/test.treeview.pas`:
```pascal
unit test.treeview;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.TreeView;
type
  TTreeStoreTest = class(TTestCase)
  published
    procedure TestRootExistsNoData;
    procedure TestNodeDataRoundTrips;
  end;
implementation
type PMyRec = ^TMyRec; TMyRec = record N: Integer; S: string[7]; end;

procedure TTreeStoreTest.TestRootExistsNoData;
var t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    AssertTrue('root allocated', t.RootNode <> nil);
    AssertNull('GetNodeData(root) is nil', t.GetNodeData(t.RootNode));
  finally t.Free; end;
end;

procedure TTreeStoreTest.TestNodeDataRoundTrips;
var t: TTyTreeView; n: PTyTreeNode; p: PMyRec;
begin
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize := SizeOf(TMyRec);
    n := t.AddChild(nil);                 // AddChild lands in Task A3 — see note
    p := PMyRec(t.GetNodeData(n));
    AssertTrue('data ptr non-nil', p <> nil);
    p^.N := 42; p^.S := 'hello';
    AssertEquals('blob persists', 42, PMyRec(t.GetNodeData(n))^.N);
  finally t.Free; end;
end;
initialization
  RegisterTest(TTreeStoreTest);
end.
```
> Note: `TestNodeDataRoundTrips` uses `AddChild` (Task A3). For A1, write only `TestRootExistsNoData` and a smaller test that allocates via a temporary public `MakeNewNode` exposure, OR fold A1+A2+A3 ordering so `AddChild` exists. Simplest: implement A1+A2+A3 together (they're one cohesive store) and commit once — see Task A3.
- [ ] **Step 3** — Wire the unit into `tycontrols.lpk` (new `<Item>`); `test.treeview` into `tests/tytests.lpr`. Build runtime pkg + run `TestRootExistsNoData` → green.
- [ ] **Step 4** — Commit `feat(treeview): node record + allocation + GetNodeData (inlined data blob)`.

## Task A2: TotalCount/TotalHeight aggregates + structural linking helpers

**Files:** Modify `source/tyControls.TreeView.pas`.

Incremental subtree aggregates — the spine of scrolling. `AdjustTotalCount`/`AdjustTotalHeight` walk node→root applying a delta; linking helpers append a child.

- [ ] **Step 1** — Add to the private section + implement:
```pascal
    procedure AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
    procedure AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
    function  NodeIsEffectivelyVisible(Node: PTyTreeNode): Boolean;  // nsVisible up the chain
```
```pascal
procedure TTyTreeView.AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
var run: PTyTreeNode;
begin
  run := Node;
  while run <> nil do begin Inc(run^.TotalCount, Delta); run := run^.Parent; if run = PTyTreeNode(Self) then Break; end;
end;

procedure TTyTreeView.AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
// Propagates a pixel delta up the chain, but STOPS climbing past a collapsed ancestor
// (a collapsed node's TotalHeight does not include hidden descendants).
var run: PTyTreeNode;
begin
  run := Node;
  while run <> nil do
  begin
    Inc(run^.TotalHeight, Delta);
    if not (nsExpanded in run^.States) then Break;   // collapsed: ancestors don't see the delta
    run := run^.Parent;
    if run = PTyTreeNode(Self) then Break;
  end;
end;
```
- [ ] **Step 2** — Tests (a `TTreeAggTest`): after manually building 1 parent + 3 children (via the Task A3 `SetChildCount`), assert `RootNode^.TotalCount` and `TotalHeight` reflect expanded vs collapsed states. (Depends on A3; commit A2+A3 together.)
- [ ] **Step 3** — Commit (folded into A3).

## Task A3: RootNodeCount / SetChildCount / AddChild (skeleton, no app events)

**Files:** Modify `source/tyControls.TreeView.pas`.

Skeleton creation. Growing a node's children allocates blank blocks and links them; NO `OnInitNode`. Setting `RootNodeCount` is `SetChildCount(FRoot, n)`.

- [ ] **Step 1** — Add + implement:
```pascal
    function  GetRootNodeCount: Cardinal;
    procedure SetRootNodeCount(AValue: Cardinal);
    procedure SetChildCount(Node: PTyTreeNode; NewCount: Cardinal);
  public
    function AddChild(Parent: PTyTreeNode): PTyTreeNode;   // append one child, return it
  published
    property RootNodeCount: Cardinal read GetRootNodeCount write SetRootNodeCount default 0;
```
```pascal
function TTyTreeView.GetRootNodeCount: Cardinal;
begin Result := FRoot^.ChildCount; end;

procedure TTyTreeView.SetRootNodeCount(AValue: Cardinal);
begin SetChildCount(FRoot, AValue); end;

procedure TTyTreeView.SetChildCount(Node: PTyTreeNode; NewCount: Cardinal);
var i: Cardinal; child, prev: PTyTreeNode; addedH, addedC: Integer;
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
      if prev <> nil then prev^.NextSibling := child else Node^.FirstChild := child;
      Node^.LastChild := child;
      prev := child;
      Inc(addedC); Inc(addedH, child^.NodeHeight);
    end;
    Node^.ChildCount := NewCount;
    AdjustTotalCount(Node, addedC);
    // children contribute height only if Node is expanded (or is the root, which is always "open")
    if (nsExpanded in Node^.States) or (Node = FRoot) then
      AdjustTotalHeight(Node, addedH);
  end
  else
  begin
    // shrink: delete the tail children (Task A4 DeleteNode handles the recursion + OnFreeNode)
    while Node^.ChildCount > NewCount do
      DeleteNode(Node^.LastChild);
  end;
  InvalidateTreeLayout;   // marks the position cache dirty + Invalidate (Task B)
end;

function TTyTreeView.AddChild(Parent: PTyTreeNode): PTyTreeNode;
var p: PTyTreeNode;
begin
  if Parent = nil then p := FRoot else p := Parent;
  SetChildCount(p, p^.ChildCount + 1);
  Result := p^.LastChild;
  // a node that gains children is implicitly expandable; if the app didn't InitNode it, mark it
  if (p <> FRoot) and not (nsHasChildren in p^.States) then Include(p^.States, nsHasChildren);
end;
```
(`DeleteNode` is Task A4; `InvalidateTreeLayout` is Task B1 — for now stub `InvalidateTreeLayout` as `Invalidate;` and refine in B1.)
- [ ] **Step 2 — tests** (incl. the A1 `TestNodeDataRoundTrips` + A2 aggregates now compile): `RootNodeCount := 5` → `RootNode^.ChildCount = 5`, `TotalCount = 5`; the 5 children are linked (`FirstChild`/`NextSibling` chain length 5, `Index` 0..4); setting `RootNodeCount := 1_000_000` is fast and fires NO `OnInitNode` (attach a counter handler, assert 0). `AddChild(nil)` appends + returns the node.
- [ ] **Step 3** — Build + run → green. Commit `feat(treeview): RootNodeCount/SetChildCount/AddChild skeleton (+ TotalCount/Height aggregates)`.

## Task A4: DeleteNode / Clear + OnFreeNode

**Files:** Modify `source/tyControls.TreeView.pas`.

- [ ] **Step 1** — Add `OnFreeNode: TTyTreeNodeEvent` (define `TTyTreeNodeEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode) of object;`), `DeleteNode(Node)`, `Clear`. `DeleteNode` recursively frees the subtree (depth-first), firing `OnFreeNode` per node (so the app can `Finalize` managed fields), unlinks from siblings/parent, and adjusts `ChildCount`/`TotalCount`/`TotalHeight`. `Clear` = `DeleteNode` all root children. Code:
```pascal
procedure TTyTreeView.DeleteNode(Node: PTyTreeNode);
var parent: PTyTreeNode; dh, dc: Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  // free children first (recursively)
  while Node^.FirstChild <> nil do DeleteNode(Node^.FirstChild);
  parent := Node^.Parent;
  dc := Node^.TotalCount;                              // self + (now zero) descendants = 1
  if (nsExpanded in parent^.States) or (parent = FRoot) then dh := Node^.TotalHeight else dh := 0;
  if Assigned(FOnFreeNode) and (FNodeDataSize > 0) then FOnFreeNode(Self, Node);
  // unlink
  if Node^.PrevSibling <> nil then Node^.PrevSibling^.NextSibling := Node^.NextSibling
  else parent^.FirstChild := Node^.NextSibling;
  if Node^.NextSibling <> nil then Node^.NextSibling^.PrevSibling := Node^.PrevSibling
  else parent^.LastChild := Node^.PrevSibling;
  Dec(parent^.ChildCount);
  AdjustTotalCount(parent, -dc);
  if dh <> 0 then AdjustTotalHeight(parent, -dh);
  if parent^.ChildCount = 0 then Exclude(parent^.States, nsHasChildren);
  FreeNodeMem(Node);
  InvalidateTreeLayout;
end;

procedure TTyTreeView.Clear;
begin
  while FRoot^.FirstChild <> nil do DeleteNode(FRoot^.FirstChild);
end;
```
- [ ] **Step 2 — tests:** build a tree, set `OnFreeNode` to count, `Clear` → counter equals node count, `RootNodeCount = 0`, `TotalCount = 0`. `DeleteNode` a middle child → siblings re-link, counts drop. A leak check: `NodeDataSize` record with a string field, `OnFreeNode` sets it `''` (no crash).
- [ ] **Step 3** — Commit `feat(treeview): DeleteNode/Clear + OnFreeNode (managed-field release)`.

## Task A5: lazy init — OnInitNode / OnInitChildren / Expanded + iterators

**Files:** Modify `source/tyControls.TreeView.pas`.

The lazy gates + navigation. This is where the data-on-demand contract lives.

- [ ] **Step 1** — Events + types: `TTyTreeInitNodeEvent = procedure(Sender; ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates) of object;` `TTyTreeInitChildrenEvent = procedure(Sender; Node: PTyTreeNode; var ChildCount: Cardinal) of object;` plus `OnInitNode`, `OnInitChildren`. Implement:
```pascal
procedure TTyTreeView.InitNode(Node: PTyTreeNode);
var initStates: TTyNodeInitStates;
begin
  if (Node = nil) or (Node = FRoot) or (nsInitialized in Node^.States) then Exit;
  Include(Node^.States, nsInitialized);
  initStates := [];
  if Assigned(FOnInitNode) then FOnInitNode(Self, Node^.Parent, Node, initStates);
  if ivsHasChildren in initStates then Include(Node^.States, nsHasChildren);
  if ivsSelected in initStates then SetSelected(Node, True);     // SetSelected = Task C
  if ivsExpanded in initStates then ToggleNode(Node, True);      // expand (materializes children)
end;

procedure TTyTreeView.InitChildren(Node: PTyTreeNode);
var c: Cardinal;
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if (Node^.ChildCount > 0) then Exit;          // already materialized
  if not (nsHasChildren in Node^.States) then Exit;
  c := 0;
  if Assigned(FOnInitChildren) then FOnInitChildren(Self, Node, c);
  if c > 0 then SetChildCount(Node, c)
  else Exclude(Node^.States, nsHasChildren);    // app said "actually none"
end;
```
- [ ] **Step 2** — `ToggleNode(Node; Expand: Boolean)` / `Expanded[Node]` property + the expand/collapse events. Expanding: fire `OnExpanding` (vetoable), `InitChildren`, set `nsExpanded`, add the subtree's child heights to ancestors via `AdjustTotalHeight`, fire `OnExpanded`. Collapsing: fire `OnCollapsing`, subtract child heights, clear `nsExpanded`, fire `OnCollapsed`. Code (the height bookkeeping is the subtle part):
```pascal
procedure TTyTreeView.SetExpanded(Node: PTyTreeNode; AValue: Boolean);
var allowed: Boolean; childrenH: Integer;
begin
  if (Node = nil) or (Node = FRoot) or not (nsHasChildren in Node^.States) then Exit;
  if AValue = (nsExpanded in Node^.States) then Exit;
  if AValue then
  begin
    allowed := True; if Assigned(FOnExpanding) then FOnExpanding(Self, Node, allowed);
    if not allowed then Exit;
    InitChildren(Node);
    Include(Node^.States, nsExpanded);
    // While collapsed, Node.TotalHeight == NodeHeight (descendants excluded). On expand, ADD the
    // newly-visible descendant height = ComputeExpandedSubtreeHeight(Node) - current TotalHeight.
    childrenH := ComputeExpandedSubtreeHeight(Node) - Integer(Node^.TotalHeight);
    if childrenH <> 0 then AdjustTotalHeight(Node, childrenH);
    if Assigned(FOnExpanded) then FOnExpanded(Self, Node);
  end
  else
  begin
    allowed := True; if Assigned(FOnCollapsing) then FOnCollapsing(Self, Node, allowed);
    if not allowed then Exit;
    // Removing descendants: TotalHeight drops back to just this node's own NodeHeight.
    childrenH := Integer(Node^.NodeHeight) - Integer(Node^.TotalHeight);   // negative delta
    Exclude(Node^.States, nsExpanded);
    if childrenH <> 0 then AdjustTotalHeight(Node, childrenH);
    if Assigned(FOnCollapsed) then FOnCollapsed(Self, Node);
  end;
  InvalidateTreeLayout;
end;
```
> **Critical height-bookkeeping rule (document + test it):** a node's `TotalHeight` includes its descendants' heights ONLY while it is expanded. Define the invariant precisely and implement `ComputeExpandedSubtreeHeight(Node)` = `NodeHeight + (if nsExpanded: sum over children of ComputeExpandedSubtreeHeight(child) else 0)`. On expand, the delta added to ancestors = (newly-visible descendant height). The implementer MUST get this exactly right (it's the #1 source of scroll desync) — Task B tests assert `RootNode^.TotalHeight` equals the sum of all visible nodes' heights after arbitrary expand/collapse sequences.
- [ ] **Step 3** — Iterators: `GetFirstChild`, `GetNextSibling`, `GetParent`, `GetNodeLevel`, `GetFirst`/`GetNext` (depth-first, init-on-touch), and the screen-order `GetFirstVisibleNoInit`/`GetNextVisibleNoInit` (descend into children only when `nsExpanded`; skip collapsed subtrees; require `NodeIsEffectivelyVisible`). Provide complete code (these are pure pointer-walks). Example for the workhorse:
```pascal
function TTyTreeView.GetNextVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
begin
  Result := Node;
  repeat
    if (nsExpanded in Result^.States) and (Result^.FirstChild <> nil) then
      Result := Result^.FirstChild
    else
      while Result <> nil do
      begin
        if Result^.NextSibling <> nil then begin Result := Result^.NextSibling; Break; end;
        Result := Result^.Parent;
        if Result = FRoot then begin Result := nil; Break; end;
      end;
  until (Result = nil) or (nsVisible in Result^.States);
end;
```
- [ ] **Step 4 — tests:** attach `OnInitNode` (sets `ivsHasChildren` for level<3) + `OnInitChildren` (sets ChildCount=4) + a fire-counter. Assert: setting `RootNodeCount` fires no init; touching a node via `GetNext` fires `OnInitNode` once; expanding fires `OnInitChildren` once + allocates 4 children; `nsHasChildren` set without children (collapsed node has `ChildCount=0` but is expandable); `GetNextVisibleNoInit` over an expanded tree yields the correct screen order; collapsing a node makes `GetNextVisibleNoInit` skip its subtree; `GetNodeLevel` correct; `OnExpanding := Allowed:=False` vetoes.
- [ ] **Step 5** — Commit `feat(treeview): lazy InitNode/InitChildren + Expand/Collapse + visible-order iterators`.

---

# PHASE B — scroll engine

## Task B1: TotalHeight ↔ visible-height invariant + InvalidateTreeLayout/range

**Files:** Modify `source/tyControls.TreeView.pas`.

- [ ] **Step 1** — Implement `InvalidateTreeLayout` (marks the position cache dirty via `FCacheValid := False`, recomputes `FRangeY := FRoot^.TotalHeight`, updates the scrollbar range (Task C), `Invalidate`). Add `function SumVisibleHeights: Integer` (a TEST/debug walk: `GetFirstVisibleNoInit`→`GetNextVisibleNoInit` summing `NodeHeight`) used only to ASSERT the invariant.
- [ ] **Step 2 — the invariant test** (`TTreeHeightTest`): after a randomized but reproducible sequence of expand/collapse/AddChild/DeleteNode (seed the sequence with fixed values — `Date.Now`/`Random` are unavailable in tests; use a hardcoded operation list), assert `RootNode^.TotalHeight = SumVisibleHeights` at every step. This is THE correctness gate for the scroll engine. Also assert `RootNode^.TotalCount = ` (count of all nodes).
- [ ] **Step 3** — Commit `feat(treeview): TotalHeight==visible-height invariant + layout invalidation`.

## Task B2: GetNodeAt(Y) via TotalHeight subtree-skip

**Files:** Modify `source/tyControls.TreeView.pas`.

Map a pixel offset to (node, nodeTop) by skipping collapsed subtrees by `TotalHeight` — O(depth + sibling scan), not O(total).

- [ ] **Step 1** — Implement:
```pascal
// Returns the visible node covering absolute Y (>=0 from the top of the virtual image),
// and its absolute top in ANodeTop. nil if Y is past the end.
function TTyTreeView.GetNodeAt(Y: Integer; out ANodeTop: Integer): PTyTreeNode;
var node: PTyTreeNode; top, h: Integer;
begin
  Result := nil; ANodeTop := 0;
  if Y < 0 then Exit;
  node := FRoot^.FirstChild; top := 0;
  while node <> nil do
  begin
    if not (nsVisible in node^.States) then begin node := node^.NextSibling; Continue; end;
    h := node^.NodeHeight;
    if Y < top + h then begin Result := node; ANodeTop := top; Exit; end;     // hit this node's own row
    if (nsExpanded in node^.States) and (node^.FirstChild <> nil) then
    begin
      // does Y fall inside this node's expanded subtree?
      if Y < top + Integer(node^.TotalHeight) then
      begin
        top := top + h;                     // descend past the node's own row
        node := node^.FirstChild;
        Continue;
      end
      else
        Inc(top, Integer(node^.TotalHeight));   // skip the whole subtree in O(1)
    end
    else
      Inc(top, h);
    node := node^.NextSibling;
    // climb if we ran off the sibling list inside a subtree
    while (node = nil) and (... ) do ... ;   // implementer: handle climbing back to parent's sibling
  end;
end;
```
> The implementer completes the climb-back logic (when `node` reaches the end of a child list mid-descent, climb to `Parent^.NextSibling`, like `GetNextVisibleNoInit`). Equivalent correctness target: `GetNodeAt(Y)` must agree with a linear `GetNextVisibleNoInit` walk summing heights — assert that in tests across many Y values.
- [ ] **Step 2 — tests:** build a multi-level expanded tree; for every visible node, `GetNodeAt(node.absoluteTop)` returns that node with the right top; `GetNodeAt(top + height - 1)` still returns it; `GetNodeAt(top + height)` returns the next; `GetNodeAt(hugeY)` returns nil. Cross-check against a linear walk for 100s of Y values.
- [ ] **Step 3** — Commit `feat(treeview): GetNodeAt(Y) with TotalHeight subtree-skip`.

## Task B3: position cache (binary-search marks) + the performance invariant

**Files:** Modify `source/tyControls.TreeView.pas`.

The every-~2000-nodes binary-searchable cache so a flat huge level is O(log + step), not O(n).

- [ ] **Step 1** — Add `FPositionCache: array of record Node: PTyTreeNode; Top: Integer; end;` + `FCacheValid: Boolean`; `const CACHE_STEP = 2000;`. `ValidateCache`: one `GetFirstVisibleNoInit`→`GetNextVisibleNoInit` pass summing heights, pushing a `(node, top)` mark every `CACHE_STEP` visible nodes. `FindInCache(Y): index` binary-searches the marks for the nearest at/below `Y`. Modify `GetNodeAt` to, when the cache is valid, start the linear scan from the nearest mark (≤ CACHE_STEP nodes) instead of the root. `InvalidateTreeLayout` sets `FCacheValid := False`.
- [ ] **Step 2 — the performance invariant test** (`TTreePerfTest`): build a FLAT tree of 200_000 root nodes (lazy, NodeDataSize=0, OnInitNode no-op) all visible; instrument `GetNodeAt` with a module-level visited-node counter; assert `GetNodeAt(Y)` near the END of the list visits **≤ CACHE_STEP + a small constant** nodes (NOT ~200_000) — proving the cache bounds the scan. Also a DEEP lazy tree (e.g. 12 levels × 6 = ~2 billion virtual, but only a path expanded) and assert `GetNodeAt` is bounded. Keep the test runtime reasonable (200k flat is fine headlessly).
- [ ] **Step 3** — Commit `feat(treeview): position cache (binary-search marks) + perf invariant test`.

---

# PHASE C — the control (paint + interaction + scrollbars)

## Task C1: selection/focus state + ToggleNode wiring + basic API

**Files:** Modify `source/tyControls.TreeView.pas`.

- [ ] Add `FFocusedNode`, single-selection (`Selected[Node]`/`SetSelected` using `nsSelected`), `FocusedNode` property, `OnChange`/`OnFocusChanged` events, `ToggleNode(Node; ForceExpand)` (used by InitNode's `ivsExpanded`). Add `Indent: Integer` (default 16), `Images: TImageList`, `EmptyListMessage: string`, the slim `TreeOptions` booleans (`ShowButtons`/`ShowTreeLines`/`ShowRoot`/`ToggleOnDblClick`/`HotTrack` — as published Boolean properties for v1, e.g. `property ShowButtons: Boolean ... default True`). `FullExpand`/`FullCollapse` (walk + expand/collapse), `ScrollIntoView(Node)` (compute the node's absolute top via a walk, adjust `FOffsetY`). Test: select fires `OnChange` once; FocusedNode tracks; FullExpand materializes all lazy children (counter). Commit `feat(treeview): selection/focus + tree options + FullExpand/ScrollIntoView`.

## Task C2: embedded scrollbars + offsets

**Files:** Modify `source/tyControls.TreeView.pas`. Pattern: read `source/tyControls.ListBox.pas` for the embedded-`TTyScrollBar` + content-rect-insets approach.

- [ ] Add `FVScroll`/`FHScroll: TTyScrollBar` (created in Create, `AnimationsEnabled := False`), `FOffsetY`/`FOffsetX`, the content rect calc (insets for visible bars), `UpdateScrollBars` (vertical: Max=`FRangeY`, Page=contentH, Position=`-FOffsetY`; horizontal over `FRangeX`), wheel → scroll, OnChange handlers → set offsets + Invalidate. Show a bar only when its range exceeds the content extent. Mirror ListBox exactly for the show/hide + inset logic. Test (headless, no real window needed for the math): set a tall virtual height, assert the vertical bar range == FRangeY and that scrolling sets FOffsetY. Commit `feat(treeview): embedded vertical/horizontal TTyScrollBars + offsets`.

## Task C3: RenderTo — visible-window paint

**Files:** Modify `source/tyControls.TreeView.pas`.

- [ ] `Paint` → `RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`. `RenderTo`: `DrawFrame` (TyTreeView), compute the content rect (minus scrollbars), find the first row via `GetNodeAt(-FOffsetY)` positioned by the sub-row remainder, then loop `GetNextVisibleNoInit` until past the content bottom. Per row, x-accumulate: indent (`level*Indent` via `GetNodeLevel`, +1 slot if `ShowRoot`), the expand button (`ShowButtons` + `nsHasChildren`; a themed `tgChevronDown`/right glyph rotated for collapsed — use `tgArrowRight`/`tgArrowDown` or a triangle), the image (`Images`+`OnGetImageIndex`), the caption (`OnGetText` + ellipsis via DrawText), the row background from `TyTreeNode` state (`:selected` accent, `:hover` when HotTrack, else none). Tree lines (`ShowTreeLines`) computed per indent slot from sibling presence. All metrics `P.Scale`. `EmptyListMessage` when no nodes. Pixel tests: a selected row paints accent; the expand button appears for an expandable node; indentation increases with level. Commit `feat(treeview): RenderTo visible-window paint (indent/buttons/lines/image/text/selection)`.

## Task C4: hit-testing + mouse + keyboard

**Files:** Modify `source/tyControls.TreeView.pas`.

- [ ] `GetNodeAtPoint(X,Y; out Part)` (Part = `hpButton`/`hpImage`/`hpLabel`/`hpIndent`/`hpNowhere`), reproducing C3's x-accumulation. MouseDown: button/indent-button → toggle expand; label → select+focus (`OnNodeClick`); `ToggleOnDblClick` → dbl-click toggles. Wheel scrolls. HotTrack updates the hovered node on MouseMove. KeyDown: ↑/↓ move focus (visible-order via GetNextVisible/GetPrevVisible), ←(collapse or go to parent)/→(expand or go to first child), Home/End, PageUp/Dn (by content height in rows), `+`/`-`/`*`(FullExpand of focused), Enter (`OnNodeDblClick`-like activate). After focus moves, `ScrollIntoView`. Behavior tests (headless, synthetic keys/mouse via a probe): click toggles expand; arrow-down moves focus to the next visible node + fires OnFocusChanged; right-arrow expands a collapsed focused node. Commit `feat(treeview): hit-test + mouse + keyboard navigation`.

---

# PHASE D — theme, events, design-time, demo, finish

## Task D1: theme typeKeys + goldens

- [ ] Add to every `themes/*.tycss` (green concrete-value per the ① learnings):
```css
TyTreeView { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: 2px; font-size: var(--font-size-base); }
TyTreeNode { background: none; color: var(--on-surface); }
TyTreeNode:hover { background: var(--surface-hover); }
TyTreeNode:selected { background: var(--accent); color: var(--on-accent); }
TyTreeNode:disabled { color: var(--muted); }
```
Regenerate both mirrors (`gen-defaulttheme.ps1` + `gen-builtinthemes.ps1`); extend `GGRID` by `'TyTreeView|','TyTreeNode|'` (+2 bound); re-bootstrap `tests/golden/{light,dark,showcase}.golden.txt` (delete + run twice; confirm purely additive); add `AssertBg('TyTreeView', [])` to `TestBuiltinCoversAllTypeKeys`. Tree-line + button-glyph colors: resolve from `TyTreeNode`/`--border`/`--muted` in the control (no hard-coded). Full suite green. Commit `feat(theme): TyTreeView + TyTreeNode typeKeys across all themes + goldens`.

## Task D2: events RTTI guard

- [ ] `tests/test.treeview.events.pas`: RTTI-assert `TTyTreeView` publishes the inherited standard set + `OnInitNode`/`OnInitChildren`/`OnFreeNode`/`OnGetText`/`OnGetImageIndex`/`OnExpanding`/`OnExpanded`/`OnCollapsing`/`OnCollapsed`/`OnChange`/`OnFocusChanged`/`OnNodeClick`/`OnNodeDblClick`/`OnPaintText`. Wire into `tytests.lpr`. Commit `test(treeview): RTTI guard for published events`.

## Task D3: design-time + icon

- [ ] Register `TTyTreeView` (Design.pas `uses` + `RegisterComponents`); `GTTyTreeView` glyph (a small tree: a root + two indented child rows with a `[+]`) in `genicons.lpr` `Glyphs[]` (+bound), `gen-icons.ps1 $classes`, `test.paletteicons.pas CClasses` (+bound); `pwsh -File scripts/gen-icons.ps1` (drift-guard pass); `lazbuild tycontrols_dt.lpk` exit 0; suite green. Commit `feat(designtime): register TTyTreeView on the palette + icon`.

## Task D4: demo + finish

- [ ] Demo: a `TTyTreeView` in the demo `.lfm` + `OnInitChildren`/`OnInitNode`/`OnGetText` handlers in `mainform.pas` producing a lazy 4-level tree (the canonical example: `OnInitNode` sets `ivsHasChildren` for level<3 + a caption in the node data; `OnInitChildren` sets `ChildCount := 5`). `NodeDataSize := SizeOf(a record with a string)`, `OnFreeNode` clears it. `lazbuild examples/demo/demo.lpi` exit 0. Commit `example(demo): showcase TTyTreeView (lazy virtual tree)`.
- [ ] Final: full verify (all packages + tests + demo), then **superpowers:finishing-a-development-branch** → merge to main. Update `new-controls-program` memory (③a done; ③b/③c next).

---

## Notes for the implementer (read once)

- **The #1 risk is the `TotalHeight` ↔ visible-height invariant** (Task B1's test is the gate). Every structural mutation (SetChildCount/DeleteNode/expand/collapse) must keep `RootNode^.TotalHeight == sum of visible node heights`. When in doubt, recompute a subtree's expanded height (`ComputeExpandedSubtreeHeight`) and apply the delta rather than guessing.
- **The #2 risk is `GetNodeAt`'s climb-back logic** — it must exactly mirror `GetNextVisibleNoInit`. The cross-check-against-linear-walk test (B2) catches divergence.
- **Headless-testability:** none of Phase A/B needs a window. Phase C's paint/scrollbars need a parented control for pixel tests; the scroll MATH does not.
- **Fixed default node height in ③a** (no variable/measured height — that's deferred), so `NodeHeight = DefaultNodeHeight` for every node; `TotalHeight` math is exact integer sums.

## Deferred (③b/③c/later — confirm none dropped)

Multi-column + header + sort (③b); checkboxes + tri-state + multi-select + full-row (③c); editing, drag-drop/OLE, animation, incremental search, variable node height, owner-draw-only tree, stream persistence (later/never). See spec §8.
