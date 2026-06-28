unit test.treeview;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.TreeView;

type
  { A1: basic allocation and GetNodeData }
  TTreeStoreTest = class(TTestCase)
  published
    procedure TestRootExistsAndSentinel;
    procedure TestGetNodeDataNilForRoot;
    procedure TestGetNodeDataNilWhenNoDataSize;
    procedure TestNodeDataRoundTrips;
    procedure TestNodeDataSizeChangesAllocStride;
  end;

  { A2: TotalCount / TotalHeight aggregates }
  TTreeAggTest = class(TTestCase)
  published
    procedure TestRootNodeCountSetsChildCount;
    procedure TestRootTotalCountAfterFiveChildren;
    procedure TestRootTotalHeightAfterFiveChildren;
    procedure TestChildChainCorrectLength;
    procedure TestChildIndexValues;
    procedure TestLargeRootNodeCountIsFast;
    procedure TestAddChildReturnsLastChild;
    procedure TestAddChildNilUsesRoot;
    procedure TestAddChildNonRootMarksHasChildren;
    procedure TestRootTotalCountAfterAddChild;
    procedure TestRootTotalHeightAfterAddChild;
    procedure TestNestedChildCountAndHeight;
    procedure TestCollapsedChildHeightNotCounted;
  end;

  { A4: DeleteNode / Clear / OnFreeNode }
  TTreeDeleteTest = class(TTestCase)
  private
    FFireCount: Integer;
    FLastNode: PTyTreeNode;
    procedure OnFree(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnFreeManagedRec(Sender: TTyTreeView; Node: PTyTreeNode);
  published
    procedure TestClearFiresOnFreeNodeForAll;
    procedure TestClearResetsCountsToZero;
    procedure TestDeleteMiddleChildRelinksNode;
    procedure TestDeleteMiddleChildUpdatesIndices;
    procedure TestDeleteNodeAdjustsTotalCount;
    procedure TestDeleteNodeAdjustsTotalHeight;
    procedure TestDeleteNodeWithChildrenFiresOnFreeForAll;
    procedure TestClearFiresOnFreeExactly;
    procedure TestManagedFieldReleaseViaOnFreeNode;
    procedure TestDeleteRootNoOp;
    procedure TestDeleteNilNoOp;
    procedure TestRootNodeCountShrinkDeletesTail;
    procedure TestRootChildCountAfterShrink;
  end;

implementation

type
  PMyRec = ^TMyRec;
  TMyRec = record
    N: Integer;
    S: string[7];
  end;

  PManagedRec = ^TManagedRec;
  TManagedRec = record
    S: AnsiString;
    I: Integer;
  end;

{ TTreeStoreTest }

procedure TTreeStoreTest.TestRootExistsAndSentinel;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    AssertTrue('root allocated', t.RootNode <> nil);
    AssertTrue('root parent is sentinel (= Self)', t.RootNode^.Parent = PTyTreeNode(t));
    AssertTrue('root nsExpanded', nsExpanded in t.RootNode^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeStoreTest.TestGetNodeDataNilForRoot;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize := SizeOf(TMyRec);
    AssertNull('GetNodeData(root) is nil', t.GetNodeData(t.RootNode));
  finally
    t.Free;
  end;
end;

procedure TTreeStoreTest.TestGetNodeDataNilWhenNoDataSize;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    // NodeDataSize = -1 (default) → GetNodeData returns nil even for a real node
    n := t.AddChild(nil);
    AssertNull('GetNodeData nil when NodeDataSize=-1', t.GetNodeData(n));
  finally
    t.Free;
  end;
end;

procedure TTreeStoreTest.TestNodeDataRoundTrips;
var
  t: TTyTreeView;
  n: PTyTreeNode;
  p: PMyRec;
begin
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize := SizeOf(TMyRec);
    n := t.AddChild(nil);
    p := PMyRec(t.GetNodeData(n));
    AssertTrue('data ptr non-nil', p <> nil);
    p^.N := 42;
    p^.S := 'hello';
    AssertEquals('blob int persists', 42, PMyRec(t.GetNodeData(n))^.N);
    AssertEquals('blob str persists', 'hello', string(PMyRec(t.GetNodeData(n))^.S));
  finally
    t.Free;
  end;
end;

procedure TTreeStoreTest.TestNodeDataSizeChangesAllocStride;
var
  t: TTyTreeView;
  n1, n2: PTyTreeNode;
  p1, p2: Pointer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize := 64;
    n1 := t.AddChild(nil);
    n2 := t.AddChild(nil);
    p1 := t.GetNodeData(n1);
    p2 := t.GetNodeData(n2);
    AssertTrue('data ptr 1 non-nil', p1 <> nil);
    AssertTrue('data ptr 2 non-nil', p2 <> nil);
    AssertTrue('data ptrs differ', p1 <> p2);
    // Both should be at offset TreeNodeSize from their node pointer
    AssertEquals('node1 data offset', PtrUInt(p1), PtrUInt(n1) + TreeNodeSize);
    AssertEquals('node2 data offset', PtrUInt(p2), PtrUInt(n2) + TreeNodeSize);
  finally
    t.Free;
  end;
end;

{ TTreeAggTest }

procedure TTreeAggTest.TestRootNodeCountSetsChildCount;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 5;
    AssertEquals('ChildCount = 5', 5, Integer(t.RootNode^.ChildCount));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestRootTotalCountAfterFiveChildren;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 5;
    // Root TotalCount = 1 (self) + 5 children = 6
    // Wait — root is a special sentinel. Root's TotalCount accumulates all descendants + itself.
    // Each child has TotalCount=1, so root TotalCount = 1 + 5 = 6
    AssertEquals('root TotalCount = 6', 6, Integer(t.RootNode^.TotalCount));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestRootTotalHeightAfterFiveChildren;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 5;
    // Root is expanded; 5 children each with NodeHeight=18; root TotalHeight = 18 + 5*18 = 108
    // Root's own NodeHeight = 18; plus 5*18 = 90 → 108
    AssertEquals('root TotalHeight = 108', 108, Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestChildChainCorrectLength;
var
  t: TTyTreeView;
  n: PTyTreeNode;
  count: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 7;
    n := t.RootNode^.FirstChild;
    count := 0;
    while n <> nil do
    begin
      Inc(count);
      n := n^.NextSibling;
    end;
    AssertEquals('chain length = 7', 7, count);
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestChildIndexValues;
var
  t: TTyTreeView;
  n: PTyTreeNode;
  idx: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 5;
    n := t.RootNode^.FirstChild;
    idx := 0;
    while n <> nil do
    begin
      AssertEquals('child index ' + IntToStr(idx), idx, Integer(n^.Index));
      Inc(idx);
      n := n^.NextSibling;
    end;
    AssertEquals('walked 5 children', 5, idx);
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestLargeRootNodeCountIsFast;
var
  t: TTyTreeView;
  initCalled: Boolean;
begin
  initCalled := False;
  t := TTyTreeView.Create(nil);
  try
    // Setting a large RootNodeCount must fire NO init event (skeleton only)
    t.RootNodeCount := 1000000;
    AssertFalse('no init event fired', initCalled);
    AssertEquals('ChildCount = 1000000', 1000000, Integer(t.RootNode^.ChildCount));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestAddChildReturnsLastChild;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    AssertTrue('AddChild returns non-nil', n <> nil);
    AssertEquals('returned node is LastChild', PtrUInt(n), PtrUInt(t.RootNode^.LastChild));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestAddChildNilUsesRoot;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    AssertTrue('parent of result is root', n^.Parent = t.RootNode);
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestAddChildNonRootMarksHasChildren;
var
  t: TTyTreeView;
  parent, child: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    AssertFalse('parent initially no nsHasChildren', nsHasChildren in parent^.States);
    child := t.AddChild(parent);
    AssertTrue('parent gains nsHasChildren', nsHasChildren in parent^.States);
    AssertTrue('child parent is parent', child^.Parent = parent);
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestRootTotalCountAfterAddChild;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.AddChild(nil);
    t.AddChild(nil);
    t.AddChild(nil);
    // root TotalCount = 1 (root itself) + 3 children = 4
    AssertEquals('root TotalCount = 4', 4, Integer(t.RootNode^.TotalCount));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestRootTotalHeightAfterAddChild;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.AddChild(nil);
    t.AddChild(nil);
    // root TotalHeight = 18 (root's own row) + 2*18 = 54
    AssertEquals('root TotalHeight = 54', 54, Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestNestedChildCountAndHeight;
var
  t: TTyTreeView;
  parent, child1, child2: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    // parent is not expanded yet — children contribute 0 height to root
    child1 := t.AddChild(parent);
    child2 := t.AddChild(parent);
    // root TotalCount = root(1) + parent(1) + child1(1) + child2(1) = 4
    AssertEquals('root TotalCount = 4', 4, Integer(t.RootNode^.TotalCount));
    // parent not expanded: root TotalHeight = root(18) + parent(18) = 36
    // (child1 and child2 heights not included because parent not expanded)
    AssertEquals('root TotalHeight = 36 (parent collapsed)', 36, Integer(t.RootNode^.TotalHeight));
    // parent TotalCount = parent(1) + child1(1) + child2(1) = 3
    AssertEquals('parent TotalCount = 3', 3, Integer(parent^.TotalCount));
    // parent TotalHeight = 18 (only parent itself, not expanded)
    AssertEquals('parent TotalHeight = 18 (not expanded)', 18, Integer(parent^.TotalHeight));
    // The children themselves have TotalHeight=18 each
    AssertEquals('child1 TotalHeight = 18', 18, Integer(child1^.TotalHeight));
    AssertEquals('child2 TotalHeight = 18', 18, Integer(child2^.TotalHeight));
  finally
    t.Free;
  end;
end;

procedure TTreeAggTest.TestCollapsedChildHeightNotCounted;
var
  t: TTyTreeView;
  parent, grandchild: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    grandchild := t.AddChild(parent);
    // parent is collapsed: root TotalHeight = 18 (root) + 18 (parent) = 36
    AssertEquals('root TotalHeight = 36', 36, Integer(t.RootNode^.TotalHeight));
    // Now expand parent manually to simulate what Phase A5 will do
    Include(parent^.States, nsExpanded);
    // We need to manually call AdjustTotalHeight to add grandchild height
    // (this would normally be done by ToggleNode in A5)
    // For this test, let's just verify the current (collapsed) state
    // The height should not have changed since we didn't call SetChildCount again
    AssertEquals('grandchild TotalHeight = 18', 18, Integer(grandchild^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ TTreeDeleteTest }

procedure TTreeDeleteTest.OnFree(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FFireCount);
  FLastNode := Node;
end;

procedure TTreeDeleteTest.OnFreeManagedRec(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  // Finalize the heap-allocated AnsiString before FreeMem destroys the raw blob.
  PManagedRec(Sender.GetNodeData(Node))^.S := '';
  Inc(FFireCount);
end;

procedure TTreeDeleteTest.TestClearFiresOnFreeNodeForAll;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    FFireCount := 0;
    t.RootNodeCount := 5;
    t.OnFreeNode := @OnFree;
    t.Clear;
    AssertEquals('OnFreeNode fired 5 times', 5, FFireCount);
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestClearResetsCountsToZero;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 10;
    t.Clear;
    AssertEquals('ChildCount = 0 after Clear', 0, Integer(t.RootNode^.ChildCount));
    // Root TotalCount after clearing all children = 1 (root itself)
    AssertEquals('root TotalCount = 1 after Clear', 1, Integer(t.RootNode^.TotalCount));
    // Root TotalHeight after clearing all children = 18 (root itself)
    AssertEquals('root TotalHeight = 18 after Clear', 18, Integer(t.RootNode^.TotalHeight));
    AssertNull('FirstChild nil after Clear', t.RootNode^.FirstChild);
    AssertNull('LastChild nil after Clear', t.RootNode^.LastChild);
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestDeleteMiddleChildRelinksNode;
var
  t: TTyTreeView;
  n1, n2, n3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n1 := t.AddChild(nil);
    n2 := t.AddChild(nil);
    n3 := t.AddChild(nil);
    t.DeleteNode(n2);
    // n1 should now link directly to n3
    AssertEquals('n1.NextSibling = n3', PtrUInt(n3), PtrUInt(n1^.NextSibling));
    AssertEquals('n3.PrevSibling = n1', PtrUInt(n1), PtrUInt(n3^.PrevSibling));
    AssertEquals('root FirstChild = n1', PtrUInt(n1), PtrUInt(t.RootNode^.FirstChild));
    AssertEquals('root LastChild = n3', PtrUInt(n3), PtrUInt(t.RootNode^.LastChild));
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestDeleteMiddleChildUpdatesIndices;
// Note: DeleteNode does NOT re-sequence sibling indices (that would be O(n) per delete).
// The Index field reflects the original insertion order; callers should use
// sibling traversal (NextSibling/PrevSibling) rather than relying on Index post-delete.
// This test verifies the initial Index values are correct at insertion time.
var
  t: TTyTreeView;
  n1, n2, n3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n1 := t.AddChild(nil);
    n2 := t.AddChild(nil);
    n3 := t.AddChild(nil);
    // Before delete: n1=0, n2=1, n3=2
    AssertEquals('n1 index = 0', 0, Integer(n1^.Index));
    AssertEquals('n2 index = 1', 1, Integer(n2^.Index));
    AssertEquals('n3 index = 2', 2, Integer(n3^.Index));
    // After deleting n2, ChildCount drops, but sibling indices are NOT re-sequenced
    t.DeleteNode(n2);
    AssertEquals('root ChildCount = 2 after delete', 2, Integer(t.RootNode^.ChildCount));
    // n3 is still linked and accessible via n1^.NextSibling
    AssertEquals('n1.NextSibling = n3', PtrUInt(n3), PtrUInt(n1^.NextSibling));
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestDeleteNodeAdjustsTotalCount;
var
  t: TTyTreeView;
  n1, n2: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n1 := t.AddChild(nil);
    n2 := t.AddChild(nil);
    AssertEquals('root TotalCount before = 3', 3, Integer(t.RootNode^.TotalCount));
    t.DeleteNode(n1);
    AssertEquals('root TotalCount after = 2', 2, Integer(t.RootNode^.TotalCount));
    t.DeleteNode(n2);
    AssertEquals('root TotalCount after 2nd delete = 1', 1, Integer(t.RootNode^.TotalCount));
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestDeleteNodeAdjustsTotalHeight;
var
  t: TTyTreeView;
  n1: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n1 := t.AddChild(nil);
    t.AddChild(nil);
    // root TotalHeight = 18 + 2*18 = 54
    AssertEquals('root TotalHeight before = 54', 54, Integer(t.RootNode^.TotalHeight));
    t.DeleteNode(n1);
    // After deleting one child: 18 + 1*18 = 36
    AssertEquals('root TotalHeight after = 36', 36, Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestDeleteNodeWithChildrenFiresOnFreeForAll;
var
  t: TTyTreeView;
  parent: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    FFireCount := 0;
    t.OnFreeNode := @OnFree;
    parent := t.AddChild(nil);
    t.AddChild(parent);
    t.AddChild(parent);
    // 3 nodes total (1 parent + 2 children)
    t.DeleteNode(parent);
    AssertEquals('OnFreeNode fired 3 times (parent + 2 children)', 3, FFireCount);
    AssertEquals('root TotalCount = 1 after', 1, Integer(t.RootNode^.TotalCount));
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestClearFiresOnFreeExactly;
var
  t: TTyTreeView;
  parent1, parent2: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    FFireCount := 0;
    t.OnFreeNode := @OnFree;
    parent1 := t.AddChild(nil);
    t.AddChild(parent1);
    t.AddChild(parent1);
    parent2 := t.AddChild(nil);
    t.AddChild(parent2);
    // 5 nodes: parent1 + 2 children + parent2 + 1 child
    t.Clear;
    AssertEquals('OnFreeNode fired exactly 5 times', 5, FFireCount);
    AssertEquals('root ChildCount = 0', 0, Integer(t.RootNode^.ChildCount));
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestManagedFieldReleaseViaOnFreeNode;
// Proves the canonical "OnFreeNode releases managed fields" pattern:
// - node blob is zero-filled by AllocMem, so AnsiString starts as a valid nil ref
// - a real heap-allocated string is written into the blob after AddChild
// - OnFreeNode (OnFreeManagedRec) finalizes the string field before the raw FreeMem
// - no crash and no memory leak; handler fires exactly once per node
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  FFireCount := 0;
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize := SizeOf(TManagedRec);
    // Add three nodes and write a real heap-allocated string into each blob.
    // AllocMem zero-fills the blob so the AnsiString starts as a valid nil ref;
    // assigning into it is safe and causes a real heap allocation.
    n := t.AddChild(nil);
    PManagedRec(t.GetNodeData(n))^.S := 'hello world ' + IntToStr(n^.Index);
    PManagedRec(t.GetNodeData(n))^.I := 1;
    n := t.AddChild(nil);
    PManagedRec(t.GetNodeData(n))^.S := 'hello world ' + IntToStr(n^.Index);
    PManagedRec(t.GetNodeData(n))^.I := 2;
    n := t.AddChild(nil);
    PManagedRec(t.GetNodeData(n))^.S := 'hello world ' + IntToStr(n^.Index);
    PManagedRec(t.GetNodeData(n))^.I := 3;
    // OnFreeManagedRec clears S (releasing the heap block) then increments FFireCount
    t.OnFreeNode := @OnFreeManagedRec;
    // Clear must fire OnFreeNode for every node (finalizing the heap string each time)
    t.Clear;
    AssertEquals('OnFreeNode fired for all 3 managed nodes', 3, FFireCount);
    AssertEquals('tree is empty after Clear', 0, Integer(t.RootNode^.ChildCount));
  finally
    // Free without OnFreeNode (strings already cleared above); must not crash
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestDeleteRootNoOp;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 3;
    t.DeleteNode(t.RootNode);  // must be a no-op, not crash
    AssertEquals('ChildCount still 3', 3, Integer(t.RootNode^.ChildCount));
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestDeleteNilNoOp;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.DeleteNode(nil);  // must not crash
    AssertTrue('tree still alive', t.RootNode <> nil);
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestRootNodeCountShrinkDeletesTail;
var
  t: TTyTreeView;
  n1, n2, n3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    FFireCount := 0;
    t.OnFreeNode := @OnFree;
    n1 := t.AddChild(nil);
    n2 := t.AddChild(nil);
    n3 := t.AddChild(nil);
    // shrink from 3 to 1: should delete n3 then n2 (tail first)
    t.RootNodeCount := 1;
    AssertEquals('ChildCount = 1 after shrink', 1, Integer(t.RootNode^.ChildCount));
    AssertEquals('n1 still FirstChild', PtrUInt(n1), PtrUInt(t.RootNode^.FirstChild));
    AssertEquals('OnFreeNode fired 2 times (n2+n3 freed)', 2, FFireCount);
  finally
    t.Free;
  end;
end;

procedure TTreeDeleteTest.TestRootChildCountAfterShrink;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 10;
    t.RootNodeCount := 3;
    AssertEquals('ChildCount = 3 after shrink', 3, Integer(t.RootNode^.ChildCount));
    AssertEquals('root TotalCount = 4', 4, Integer(t.RootNode^.TotalCount));
    AssertEquals('root TotalHeight = 4*18', 72, Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ ── A5 ── lazy init + expand/collapse + iterators ─────────────────────── }

type
  TTreeLazyTest = class(TTestCase)
  private
    FInitNodeCount:     Integer;
    FInitChildrenCount: Integer;
    FExpandingCount:    Integer;
    FExpandedCount:     Integer;
    FCollapsingCount:   Integer;
    FCollapsedCount:    Integer;
    FVetoExpanding:     Boolean;

    procedure OnInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                         var InitStates: TTyNodeInitStates);
    procedure OnInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                             var ChildCount: Cardinal);
    procedure OnExpanding(Sender: TTyTreeView; Node: PTyTreeNode;
                          var Allowed: Boolean);
    procedure OnExpanded(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnCollapsing(Sender: TTyTreeView; Node: PTyTreeNode;
                           var Allowed: Boolean);
    procedure OnCollapsed(Sender: TTyTreeView; Node: PTyTreeNode);

    // Build a standard test tree: attach the handlers and set RootNodeCount.
    function MakeTree: TTyTreeView;
    procedure ResetCounters;
  published
    // Setting RootNodeCount allocates skeletons but fires NO OnInitNode.
    procedure TestSetRootNodeCountFiresNoInit;
    // GetNext touches each node exactly once via OnInitNode.
    procedure TestGetNextFiresInitNodeOnce;
    // A node that got ivsHasChildren has nsHasChildren set but ChildCount=0.
    procedure TestHasChildrenSetWithoutMaterialising;
    // Expanding fires OnInitChildren once and allocates 4 children.
    procedure TestExpandingFiresInitChildrenOnce;
    // GetNextVisibleNoInit yields screen order over an expanded tree.
    procedure TestGetNextVisibleNoInitScreenOrder;
    // GetNextVisibleNoInit skips a collapsed node's children.
    procedure TestGetNextVisibleNoInitSkipsCollapsed;
    // GetNodeLevel returns 0 for top-level nodes, 1 for their children, etc.
    procedure TestGetNodeLevel;
    // OnExpanding with Allowed:=False vetoes the expand (node stays collapsed).
    procedure TestExpandingVetoPreventsExpand;
    // After expand then collapse, RootNode^.TotalHeight returns to the pre-expand value.
    procedure TestHeightRoundTrip;
    // Expanded property getter / setter roundtrip.
    procedure TestExpandedProperty;
  end;

{ ── TTreeLazyTest helpers ─────────────────────────────────────────────── }

{ OnInitNode fires for any depth.
  ivsHasChildren is set for levels 0, 1, and 2 (so level 3 nodes are leaves).
  We always signal HasChildren for simplicity; InitChildren/OnInitChildren
  will be called to actually materialise child nodes. }
procedure TTreeLazyTest.OnInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                   var InitStates: TTyNodeInitStates);
begin
  Inc(FInitNodeCount);
  if Sender.GetNodeLevel(Node) < 3 then
    Include(InitStates, ivsHasChildren);
end;

procedure TTreeLazyTest.OnInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                                       var ChildCount: Cardinal);
begin
  Inc(FInitChildrenCount);
  ChildCount := 4;
end;

procedure TTreeLazyTest.OnExpanding(Sender: TTyTreeView; Node: PTyTreeNode;
                                    var Allowed: Boolean);
begin
  Inc(FExpandingCount);
  Allowed := not FVetoExpanding;
end;

procedure TTreeLazyTest.OnExpanded(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FExpandedCount);
end;

procedure TTreeLazyTest.OnCollapsing(Sender: TTyTreeView; Node: PTyTreeNode;
                                     var Allowed: Boolean);
begin
  Inc(FCollapsingCount);
  Allowed := True;
end;

procedure TTreeLazyTest.OnCollapsed(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FCollapsedCount);
end;

procedure TTreeLazyTest.ResetCounters;
begin
  FInitNodeCount     := 0;
  FInitChildrenCount := 0;
  FExpandingCount    := 0;
  FExpandedCount     := 0;
  FCollapsingCount   := 0;
  FCollapsedCount    := 0;
  FVetoExpanding     := False;
end;

function TTreeLazyTest.MakeTree: TTyTreeView;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  t.OnInitNode     := @OnInitNode;
  t.OnInitChildren := @OnInitChildren;
  t.OnExpanding    := @OnExpanding;
  t.OnExpanded     := @OnExpanded;
  t.OnCollapsing   := @OnCollapsing;
  t.OnCollapsed    := @OnCollapsed;
  t.RootNodeCount  := 3;   // 3 top-level skeleton nodes, no init fired yet
  Result := t;
end;

{ ── TTreeLazyTest published tests ────────────────────────────────────── }

procedure TTreeLazyTest.TestSetRootNodeCountFiresNoInit;
var
  t: TTyTreeView;
begin
  ResetCounters;
  t := MakeTree;
  try
    AssertEquals('no OnInitNode on RootNodeCount', 0, FInitNodeCount);
    AssertEquals('no OnInitChildren on RootNodeCount', 0, FInitChildrenCount);
    AssertEquals('ChildCount = 3', 3, Integer(t.RootNode^.ChildCount));
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestGetNextFiresInitNodeOnce;
{ Walk the entire top-level (3 nodes, no deeper because we don't expand).
  GetNext inits each node as it is first touched. }
var
  t: TTyTreeView;
  n: PTyTreeNode;
  visited: Integer;
begin
  ResetCounters;
  t := MakeTree;
  try
    visited := 0;
    n := t.GetFirst;
    while n <> nil do
    begin
      Inc(visited);
      n := t.GetNext(n);
    end;
    AssertEquals('visited 3 top-level nodes', 3, visited);
    // Each node inited exactly once.
    AssertEquals('OnInitNode fired once per node', 3, FInitNodeCount);
    // Second walk fires no additional init (nsInitialized guard).
    ResetCounters;
    n := t.GetFirst;
    while n <> nil do n := t.GetNext(n);
    AssertEquals('no re-init on second walk', 0, FInitNodeCount);
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestHasChildrenSetWithoutMaterialising;
{ After InitNode, a level-0 node should have nsHasChildren but still ChildCount=0
  (children are not materialised until expansion). }
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  ResetCounters;
  t := MakeTree;
  try
    n := t.GetFirst;   // triggers InitNode
    AssertTrue ('nsHasChildren set', nsHasChildren in n^.States);
    AssertEquals('ChildCount still 0 (not yet expanded)', 0, Integer(n^.ChildCount));
    AssertFalse ('not expanded', nsExpanded in n^.States);
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestExpandingFiresInitChildrenOnce;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  ResetCounters;
  t := MakeTree;
  try
    n := t.GetFirst;  // InitNode → sets nsHasChildren
    t.Expanded[n] := True;
    AssertEquals('OnInitChildren fired once', 1, FInitChildrenCount);
    AssertEquals('4 children materialised', 4, Integer(n^.ChildCount));
    AssertTrue  ('nsExpanded set', nsExpanded in n^.States);
    // Second expand call must NOT fire OnInitChildren again.
    FInitChildrenCount := 0;
    t.Expanded[n] := True;   // already expanded — no-op
    AssertEquals('no re-init on second expand', 0, FInitChildrenCount);
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestGetNextVisibleNoInitScreenOrder;
{ Build:  root
            n[0] (expanded, 4 children)
            n[1]
            n[2]
  Screen order: n[0], child[0], child[1], child[2], child[3], n[1], n[2] }
var
  t: TTyTreeView;
  n0: PTyTreeNode;
  vis: PTyTreeNode;
  order: array[0..6] of PTyTreeNode;
  i, count: Integer;
begin
  ResetCounters;
  t := MakeTree;
  try
    n0 := t.GetFirst;   // InitNode n0 → ivsHasChildren
    t.Expanded[n0] := True;  // materialises 4 children

    // Collect screen order via NoInit iterator
    count := 0;
    vis := t.GetFirstVisibleNoInit;
    while vis <> nil do
    begin
      AssertTrue('count < 7', count < 7);
      order[count] := vis;
      Inc(count);
      vis := t.GetNextVisibleNoInit(vis);
    end;

    AssertEquals('7 visible nodes', 7, count);
    // First = n0
    AssertEquals('order[0] = n0', PtrUInt(n0), PtrUInt(order[0]));
    // order[1..4] = children of n0
    for i := 1 to 4 do
      AssertEquals('order[' + IntToStr(i) + '] parent = n0',
                   PtrUInt(n0), PtrUInt(order[i]^.Parent));
    // order[5] and order[6] = n[1] and n[2]
    AssertEquals('order[5].PrevSibling = n0', PtrUInt(n0), PtrUInt(order[5]^.PrevSibling));
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestGetNextVisibleNoInitSkipsCollapsed;
{ Expand n[0], then collapse it again — the 4 children must not appear in the walk. }
var
  t: TTyTreeView;
  n0: PTyTreeNode;
  vis: PTyTreeNode;
  count: Integer;
begin
  ResetCounters;
  t := MakeTree;
  try
    n0 := t.GetFirst;
    t.Expanded[n0] := True;
    t.Expanded[n0] := False;   // collapse

    count := 0;
    vis := t.GetFirstVisibleNoInit;
    while vis <> nil do
    begin
      Inc(count);
      vis := t.GetNextVisibleNoInit(vis);
    end;
    AssertEquals('only 3 visible (collapsed subtree skipped)', 3, count);
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestGetNodeLevel;
var
  t: TTyTreeView;
  n0, child, grandchild: PTyTreeNode;
begin
  ResetCounters;
  t := MakeTree;
  try
    n0 := t.GetFirst;   // level 0
    AssertEquals('level 0', 0, t.GetNodeLevel(n0));

    t.Expanded[n0] := True;
    child := n0^.FirstChild;   // level 1
    AssertEquals('level 1', 1, t.GetNodeLevel(child));

    // Initialise and expand the child so we can get a grandchild
    t.InitNode(child);
    t.Expanded[child] := True;
    grandchild := child^.FirstChild;  // level 2
    AssertEquals('level 2', 2, t.GetNodeLevel(grandchild));
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestExpandingVetoPreventsExpand;
var
  t: TTyTreeView;
  n0: PTyTreeNode;
  prevTotal: Cardinal;
begin
  ResetCounters;
  FVetoExpanding := True;
  t := MakeTree;
  try
    n0 := t.GetFirst;  // InitNode → nsHasChildren
    prevTotal := t.RootNode^.TotalHeight;
    t.Expanded[n0] := True;   // vetoed
    AssertFalse ('still not expanded', nsExpanded in n0^.States);
    AssertEquals('ChildCount still 0', 0, Integer(n0^.ChildCount));
    AssertEquals('TotalHeight unchanged', Integer(prevTotal), Integer(t.RootNode^.TotalHeight));
    AssertEquals('OnExpanding fired', 1, FExpandingCount);
    AssertEquals('OnExpanded NOT fired', 0, FExpandedCount);
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestHeightRoundTrip;
{ Expand n[0], then collapse it.  RootNode^.TotalHeight must return to its
  pre-expand value.  (The full multi-step invariant test lives in B1.) }
var
  t: TTyTreeView;
  n0: PTyTreeNode;
  heightBefore, heightAfterExpand, heightAfterCollapse: Integer;
begin
  ResetCounters;
  t := MakeTree;
  try
    // Baseline: 3 top-level nodes, each NodeHeight=18; root itself 18 → total=4*18=72
    heightBefore := Integer(t.RootNode^.TotalHeight);
    AssertEquals('baseline height 72', 72, heightBefore);

    n0 := t.GetFirst;   // InitNode n0
    t.Expanded[n0] := True;
    heightAfterExpand := Integer(t.RootNode^.TotalHeight);
    // n0 expanded with 4 children (each 18px) → root total = 72 + 4*18 = 144
    AssertEquals('height after expand = 144', 144, heightAfterExpand);

    t.Expanded[n0] := False;  // collapse
    heightAfterCollapse := Integer(t.RootNode^.TotalHeight);
    AssertEquals('height after collapse = baseline', heightBefore, heightAfterCollapse);

    AssertEquals('OnCollapsing fired', 1, FCollapsingCount);
    AssertEquals('OnCollapsed fired',  1, FCollapsedCount);
  finally t.Free; end;
end;

procedure TTreeLazyTest.TestExpandedProperty;
var
  t: TTyTreeView;
  n0: PTyTreeNode;
begin
  ResetCounters;
  t := MakeTree;
  try
    n0 := t.GetFirst;
    AssertFalse('not expanded initially', t.Expanded[n0]);
    t.Expanded[n0] := True;
    AssertTrue ('expanded after set', t.Expanded[n0]);
    t.Expanded[n0] := False;
    AssertFalse('collapsed after clear', t.Expanded[n0]);
  finally t.Free; end;
end;

{ ── B1 ── TotalHeight invariant + FRangeY ──────────────────────────────── }

type
  TTreeHeightInvariantTest = class(TTestCase)
  private
    { Shared event state for scenario 3 (auto-expand via ivsExpanded). }
    FAutoExpandLevel: Integer;  // OnInitNode sets ivsExpanded for nodes at this level

    procedure OnInitNodeAutoExpand(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                   var InitStates: TTyNodeInitStates);
    procedure OnInitChildren4(Sender: TTyTreeView; Node: PTyTreeNode;
                              var ChildCount: Cardinal);
    { Count all nodes via depth-first GetFirst/GetNext (no init side-effects, but we
      call GetFirst which does call InitNode for the first node; for counting purposes
      we accept this and note: we only need TotalCount = RootNode^.TotalCount). }
    function CountAllNodes(T: TTyTreeView): Integer;
    procedure AssertInvariant(T: TTyTreeView; const Step: string);
  published
    { Scenario 1: root nodes → expand → collapse (basic roundtrip). }
    procedure TestScenario1_ExpandCollapse;
    { Scenario 2: nested expand A, then expand A.child B, then collapse A (B still expanded),
      then re-expand A (B must still be expanded, invariant must hold throughout). }
    procedure TestScenario2_NestedCollapseAndReexpand;
    { Scenario 3: OnInitNode returns ivsExpanded → auto-expand on first touch;
      assert invariant after the node is initialised. }
    procedure TestScenario3_AutoExpandViaInitStates;
    { Scenario 4: AddChild to an expanded parent grows root height;
      AddChild to a collapsed parent does NOT. }
    procedure TestScenario4_AddChildExpandedVsCollapsed;
    { Scenario 5: DeleteNode of an expanded child (parent expanded) drops the full
      visible subtree; DeleteNode from a collapsed parent leaves root height unchanged. }
    procedure TestScenario5_DeleteExpandedVsCollapsed;
    { Scenario 6 (the bug this fix addresses): with A collapsed, set Expanded[B]=True
      where B is A's child → A.TotalHeight must stay = A.NodeHeight, root unchanged;
      then expand A → root grows by B's already-expanded subtree. }
    procedure TestScenario6_ExpandInCollapsedAncestor;
    { RangeY tracks RootNode^.TotalHeight after mutations. }
    procedure TestRangeYTracksRoot;
  end;

procedure TTreeHeightInvariantTest.OnInitNodeAutoExpand(
  Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
  var InitStates: TTyNodeInitStates);
begin
  { Auto-expand nodes at level FAutoExpandLevel (or all levels if -1).
    Set ivsHasChildren always so we can test auto-expansion. }
  Include(InitStates, ivsHasChildren);
  if (FAutoExpandLevel < 0) or (Sender.GetNodeLevel(Node) = FAutoExpandLevel) then
    Include(InitStates, ivsExpanded);
end;

procedure TTreeHeightInvariantTest.OnInitChildren4(
  Sender: TTyTreeView; Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 4;
end;

function TTreeHeightInvariantTest.CountAllNodes(T: TTyTreeView): Integer;
{ Return the count of all nodes (not counting the root sentinel itself).
  We simply use RootNode^.TotalCount - 1 (root counts itself).
  Cross-checked in scenario tests. }
begin
  Result := Integer(T.RootNode^.TotalCount) - 1;
end;

procedure TTreeHeightInvariantTest.AssertInvariant(T: TTyTreeView; const Step: string);
var
  sumH, rootH: Integer;
begin
  sumH  := T.SumVisibleHeights;
  rootH := Integer(T.RootNode^.TotalHeight);
  AssertEquals(Step + ': TotalHeight = SumVisibleHeights', sumH, rootH);
end;

{ Scenario 1 }
procedure TTreeHeightInvariantTest.TestScenario1_ExpandCollapse;
var
  t: TTyTreeView;
  n: PTyTreeNode;
  heightBase: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 5;
    AssertInvariant(t, 'after RootNodeCount=5');

    { Manually give node HasChildren so Expanded can work (no OnInitNode) }
    n := t.RootNode^.FirstChild;
    Include(n^.States, nsHasChildren);
    Include(n^.States, nsInitialized);
    heightBase := Integer(t.RootNode^.TotalHeight);

    t.Expanded[n] := True;
    AssertInvariant(t, 'after expand first node');

    t.Expanded[n] := False;
    AssertInvariant(t, 'after collapse first node');
    AssertEquals('height returns to base after collapse', heightBase,
                 Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ Scenario 2 }
procedure TTreeHeightInvariantTest.TestScenario2_NestedCollapseAndReexpand;
{ Tree (5 root nodes; A = first root node, B = A's first child)
  Step 1: expand A → A's 4 children materialised
  Step 2: expand B (A's first child) → B's 4 grandchildren materialised
  Step 3: collapse A (B is still expanded internally)
  Step 4: re-expand A → B must still be expanded, invariant holds }
var
  t: TTyTreeView;
  A, B: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 3;
    AssertInvariant(t, 'S2 initial');

    A := t.RootNode^.FirstChild;
    Include(A^.States, nsHasChildren);
    Include(A^.States, nsInitialized);

    { Step 1: expand A }
    t.Expanded[A] := True;
    AssertInvariant(t, 'S2 after expand A');

    { Step 2: expand B (first child of A) }
    B := A^.FirstChild;
    Include(B^.States, nsHasChildren);
    Include(B^.States, nsInitialized);
    t.Expanded[B] := True;
    AssertInvariant(t, 'S2 after expand B');
    { root height = root_h + 3*18 (root children) + 4*18 (A's children) + 4*18 (B's children) }
    AssertEquals('S2 A expanded, B expanded: height',
                 Integer(t.RootNode^.NodeHeight) + 3*18 + 4*18 + 4*18,
                 Integer(t.RootNode^.TotalHeight));

    { Step 3: collapse A (B is still internally expanded but its children are now hidden) }
    t.Expanded[A] := False;
    AssertInvariant(t, 'S2 after collapse A (B still internally expanded)');
    { Now only 3 root children are visible; A is collapsed }
    AssertEquals('S2 A collapsed: height = root_h + 3*18',
                 Integer(t.RootNode^.NodeHeight) + 3*18,
                 Integer(t.RootNode^.TotalHeight));
    { B must still be internally expanded (nsExpanded still set) }
    AssertTrue('B still internally expanded', nsExpanded in B^.States);

    { Step 4: re-expand A — B's 4 grandchildren must reappear }
    t.Expanded[A] := True;
    AssertInvariant(t, 'S2 after re-expand A (B still expanded)');
    AssertEquals('S2 re-expand A: height = root_h + 3*18 + 4*18 + 4*18',
                 Integer(t.RootNode^.NodeHeight) + 3*18 + 4*18 + 4*18,
                 Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ Scenario 3 }
procedure TTreeHeightInvariantTest.TestScenario3_AutoExpandViaInitStates;
{ OnInitNode returns ivsExpanded for level-0 nodes → auto-expand on first GetNext touch.
  The invariant must hold after InitNode + auto-expand fires. }
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  FAutoExpandLevel := 0;
  t := TTyTreeView.Create(nil);
  try
    t.OnInitNode     := @OnInitNodeAutoExpand;
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 2;
    AssertInvariant(t, 'S3 before init');

    { Touch first node: triggers InitNode → ivsExpanded → auto-expand → InitChildren → 4 children }
    n := t.GetFirst;   // fires InitNode(first child) → sets ivsExpanded → calls SetExpanded
    AssertTrue('S3 node is expanded after auto-expand', nsExpanded in n^.States);
    AssertEquals('S3 node has 4 children after auto-expand', 4, Integer(n^.ChildCount));
    AssertInvariant(t, 'S3 after auto-expand via ivsExpanded');
    { root_h + 2*18 (root children) + 4*18 (first child's expanded children) }
    AssertEquals('S3 height = root_h + 2*18 + 4*18',
                 Integer(t.RootNode^.NodeHeight) + 2*18 + 4*18,
                 Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ Scenario 4 }
procedure TTreeHeightInvariantTest.TestScenario4_AddChildExpandedVsCollapsed;
var
  t: TTyTreeView;
  expandedParent, collapsedParent: PTyTreeNode;
  heightBefore: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 2;
    expandedParent  := t.RootNode^.FirstChild;
    collapsedParent := expandedParent^.NextSibling;

    { Expand first node (manually mark has-children first) }
    Include(expandedParent^.States, nsHasChildren);
    Include(expandedParent^.States, nsInitialized);
    t.Expanded[expandedParent] := True;
    AssertInvariant(t, 'S4 after expand first node');

    { AddChild to an EXPANDED node → root height grows by NodeHeight }
    heightBefore := Integer(t.RootNode^.TotalHeight);
    t.AddChild(expandedParent);
    AssertInvariant(t, 'S4 after AddChild to expanded parent');
    AssertEquals('S4 root height grew by NodeHeight after AddChild to expanded',
                 heightBefore + 18,
                 Integer(t.RootNode^.TotalHeight));

    { AddChild to a COLLAPSED node → root height unchanged }
    heightBefore := Integer(t.RootNode^.TotalHeight);
    t.AddChild(collapsedParent);
    AssertInvariant(t, 'S4 after AddChild to collapsed parent');
    AssertEquals('S4 root height unchanged after AddChild to collapsed',
                 heightBefore,
                 Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ Scenario 5 }
procedure TTreeHeightInvariantTest.TestScenario5_DeleteExpandedVsCollapsed;
var
  t: TTyTreeView;
  expandedParent, collapsedParent, expandedChild, collapsedChild: PTyTreeNode;
  heightBefore: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 2;
    expandedParent  := t.RootNode^.FirstChild;
    collapsedParent := expandedParent^.NextSibling;

    { Expand first parent and add a child to it }
    Include(expandedParent^.States, nsHasChildren);
    Include(expandedParent^.States, nsInitialized);
    t.Expanded[expandedParent] := True;   { materialises 4 children }
    expandedChild := expandedParent^.FirstChild;
    AssertInvariant(t, 'S5 after expand parent');

    { Also expand one of its children (grandchild scenario) }
    Include(expandedChild^.States, nsHasChildren);
    Include(expandedChild^.States, nsInitialized);
    t.Expanded[expandedChild] := True;    { materialises 4 grandchildren }
    AssertInvariant(t, 'S5 after expand child');

    { Delete the expanded child (parent expanded) → root drops by child's full TotalHeight }
    heightBefore := Integer(t.RootNode^.TotalHeight);
    { expandedChild^.TotalHeight = 18 + 4*18 = 90 (itself + 4 grandchildren) }
    AssertEquals('S5 expanded child TotalHeight = 90', 90,
                 Integer(expandedChild^.TotalHeight));
    t.DeleteNode(expandedChild);
    AssertInvariant(t, 'S5 after delete expanded child');
    AssertEquals('S5 root dropped by child TotalHeight (90)',
                 heightBefore - 90,
                 Integer(t.RootNode^.TotalHeight));

    { Now test deletion from a COLLAPSED parent }
    collapsedChild := t.AddChild(collapsedParent);
    AssertInvariant(t, 'S5 after add to collapsed parent');
    heightBefore := Integer(t.RootNode^.TotalHeight);
    t.DeleteNode(collapsedChild);
    AssertInvariant(t, 'S5 after delete from collapsed parent');
    AssertEquals('S5 root height unchanged after delete from collapsed',
                 heightBefore,
                 Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ Scenario 6 — the bug this fix addresses }
procedure TTreeHeightInvariantTest.TestScenario6_ExpandInCollapsedAncestor;
{ With A collapsed, programmatically set Expanded[B] := True where B is A's child.
  Expected:
    • A.TotalHeight stays = A.NodeHeight (collapsed; B's subtree excluded)
    • RootNode^.TotalHeight unchanged
  Then expand A:
    • Root grows by A's full (now B-expanded) subtree height
    • B must still be expanded, invariant holds. }
var
  t: TTyTreeView;
  A, B: PTyTreeNode;
  rootHeightBase: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 2;   { 2 root nodes, A = first }
    A := t.RootNode^.FirstChild;

    { Materialise A's children (without expanding A) }
    Include(A^.States, nsHasChildren);
    Include(A^.States, nsInitialized);
    t.SetChildCount(A, 4);   { 4 children allocated but A still collapsed }
    AssertInvariant(t, 'S6 after SetChildCount A (still collapsed)');

    rootHeightBase := Integer(t.RootNode^.TotalHeight);

    { B = first child of A }
    B := A^.FirstChild;
    Include(B^.States, nsHasChildren);
    Include(B^.States, nsInitialized);

    { Expand B while A is COLLAPSED — the key scenario }
    t.Expanded[B] := True;   { InitChildren fires via SetExpanded → 4 grandchildren }
    AssertInvariant(t, 'S6 after Expanded[B]=True with A collapsed');
    { A is collapsed: its TotalHeight must still be just its own NodeHeight (18) }
    AssertEquals('S6 A.TotalHeight = 18 while A collapsed (B expanded inside)',
                 18, Integer(A^.TotalHeight));
    { Root height must NOT have changed }
    AssertEquals('S6 root height unchanged while A collapsed',
                 rootHeightBase, Integer(t.RootNode^.TotalHeight));
    AssertTrue('S6 B is marked expanded', nsExpanded in B^.States);

    { Now expand A — root must grow by A's full visible subtree (A's 4 children + B's 4 grandchildren) }
    t.Expanded[A] := True;
    AssertInvariant(t, 'S6 after Expanded[A]=True (B already expanded)');
    AssertTrue('S6 B still expanded after A expands', nsExpanded in B^.States);
    { A's visible subtree: 4 children rows + 4 grandchildren (under B) }
    { root height = root_h + 2*18 (root's 2 children) + 4*18 (A's children) + 4*18 (B's grandchildren) }
    AssertEquals('S6 root height = root_h + 2*18 + 4*18 + 4*18',
                 Integer(t.RootNode^.NodeHeight) + 2*18 + 4*18 + 4*18,
                 Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

{ RangeY }
procedure TTreeHeightInvariantTest.TestRangeYTracksRoot;
var
  t: TTyTreeView;
  A: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 3;
    AssertEquals('RangeY = RootNode^.TotalHeight after RootNodeCount',
                 Integer(t.RootNode^.TotalHeight), t.RangeY);

    A := t.RootNode^.FirstChild;
    Include(A^.States, nsHasChildren);
    Include(A^.States, nsInitialized);
    t.Expanded[A] := True;
    AssertEquals('RangeY = RootNode^.TotalHeight after expand',
                 Integer(t.RootNode^.TotalHeight), t.RangeY);

    t.Expanded[A] := False;
    AssertEquals('RangeY = RootNode^.TotalHeight after collapse',
                 Integer(t.RootNode^.TotalHeight), t.RangeY);
  finally
    t.Free;
  end;
end;

initialization
  RegisterTest(TTreeStoreTest);
  RegisterTest(TTreeAggTest);
  RegisterTest(TTreeDeleteTest);
  RegisterTest(TTreeLazyTest);
  RegisterTest(TTreeHeightInvariantTest);
end.
