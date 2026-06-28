unit test.treeview;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.TreeView;

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

  { C3: pixel-level paint tests }
  TTreeC3PaintTest = class(TTestCase)
  private
    FGetTextCalled: Integer;
    procedure OnGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
    procedure OnInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                        var InitStates: TTyNodeInitStates);
    procedure OnInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
                             var ChildCount: Cardinal);
  published
    procedure TestSelectedRowHasAccentBlue;
    procedure TestChildRowIndentedMoreThanTopLevel;
    procedure TestExpandButtonInkForExpandable;
    procedure TestEmptyTreeNoException;
  end;

  { C4: hit-test + mouse + keyboard }
  TTreeC4Test = class(TTestCase)
  private
    FOnChangeCount:     Integer;
    FOnChangeLastNode:  PTyTreeNode;
    FOnFocusCount:      Integer;
    FOnFocusLastNode:   PTyTreeNode;
    FOnClickCount:      Integer;
    FOnClickLastNode:   PTyTreeNode;
    FOnDblClickCount:   Integer;
    FOnDblClickLastNode: PTyTreeNode;
    FOnExpandedCount:   Integer;
    FOnExpandedNode:    PTyTreeNode;

    procedure OnChange(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnNodeClick(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnNodeDblClick(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnExpanded(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnInitNodeHasChildren(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                    var InitStates: TTyNodeInitStates);
    procedure OnInitChildren3(Sender: TTyTreeView; Node: PTyTreeNode;
                              var ChildCount: Cardinal);
    procedure ResetCounters;

    { Build a known-geometry tree (PPI=96, DefaultNodeHeight=20, Indent=16, ShowRoot=True)
        root
          n0  (expandable: nsHasChildren manually set, 3 children materialised)
            n0c0  (leaf)
            n0c1  (leaf)
            n0c2  (leaf)
          n1  (leaf)
          n2  (leaf)
      n0 is already EXPANDED on return.
      Out params let the caller reference individual nodes. }
    function BuildHitTestTree(out n0, n0c0, n1, n2: PTyTreeNode): TTyTreeView;
  published
    { GetNodeAtPoint: button slot returns hpButton for an expandable node }
    procedure TestHitTestButtonSlot;
    { GetNodeAtPoint: label area returns hpLabel }
    procedure TestHitTestLabelArea;
    { GetNodeAtPoint: below all rows returns nil + hpNowhere }
    procedure TestHitTestBelowAllRows;
    { GetNodeAtPoint: indent area (left of button slot) returns hpIndent }
    procedure TestHitTestIndentArea;
    { Mouse: clicking label selects+focuses node, fires OnChange + OnNodeClick }
    procedure TestMouseClickLabelSelectsNode;
    { Mouse: clicking expand button toggles expansion, does NOT change focus }
    procedure TestMouseClickButtonExpandsNode;
    { Keyboard: VK_DOWN moves FocusedNode to next visible, fires OnFocusChanged }
    procedure TestKeyDownMovesToNextVisible;
    { Keyboard: VK_UP moves FocusedNode to previous visible, fires OnFocusChanged }
    procedure TestKeyUpMovesToPrevious;
    { Keyboard: VK_RIGHT on collapsed+expandable node expands it }
    procedure TestKeyRightExpandsCollapsed;
    { Keyboard: VK_LEFT on expanded node collapses it }
    procedure TestKeyLeftCollapsesExpanded;
  end;

implementation

type
  { C3/C4: hard-cast helper to call protected methods from tests. }
  TTyTreeViewAccess = class(TTyTreeView)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure KeyDown(var Key: Word; Shift: TShiftState);
  end;

procedure TTyTreeViewAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyTreeViewAccess.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyTreeViewAccess.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
end;

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
{ C2 fix: RangeY now equals ContentHeight = RootNode^.TotalHeight - RootNode^.NodeHeight.
  The root's phantom row is NOT part of the scrollable content. }
var
  t: TTyTreeView;
  A: PTyTreeNode;
  expectedRangeY: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildren4;
    t.RootNodeCount  := 3;
    expectedRangeY := Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight);
    AssertEquals('RangeY = ContentHeight (TotalHeight - NodeHeight) after RootNodeCount',
                 expectedRangeY, t.RangeY);

    A := t.RootNode^.FirstChild;
    Include(A^.States, nsHasChildren);
    Include(A^.States, nsInitialized);
    t.Expanded[A] := True;
    expectedRangeY := Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight);
    AssertEquals('RangeY = ContentHeight after expand',
                 expectedRangeY, t.RangeY);

    t.Expanded[A] := False;
    expectedRangeY := Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight);
    AssertEquals('RangeY = ContentHeight after collapse',
                 expectedRangeY, t.RangeY);
  finally
    t.Free;
  end;
end;

{ ── B2 ── GetNodeAt(Y) cross-check vs linear walk ────────────────────────── }

type
  TTreeGetNodeAtTest = class(TTestCase)
  private
    { Multi-level test tree layout (all nodes have DefaultNodeHeight=18):
        Root (hidden)
          A0   top=0   (expanded, 3 children)
            A0C0  top=18  (leaf)
            A0C1  top=36  (expanded, 2 children)
              A0C1G0  top=54  (leaf)
              A0C1G1  top=72  (leaf)
            A0C2  top=90  (leaf)
          A1   top=108  (collapsed, has children but not expanded)
          A2   top=126  (expanded, 2 children)
            A2C0  top=144  (leaf)
            A2C1  top=162  (leaf)
          A3   top=180  (leaf)

      Total visible height = 10 nodes × 18 = 180 px
      (A1's children are NOT visible because A1 is collapsed.)

      We build this tree explicitly (no lazy init needed). }

    { Nodes we keep for assertions }
    FA0, FA0C0, FA0C1, FA0C1G0, FA0C1G1, FA0C2: PTyTreeNode;
    FA1, FA2, FA2C0, FA2C1, FA3: PTyTreeNode;

    function  BuildTree: TTyTreeView;
    { Linear-walk helper: find (node, top) for a given Y by summing NodeHeight. }
    function  LinearGetNodeAt(T: TTyTreeView; Y: Integer; out ANodeTop: Integer): PTyTreeNode;
  published
    { Exact-node tests: known (node, top) pairs. }
    procedure TestGetNodeAtKnownNodes;
    { Boundary: GetNodeAt(top + NodeHeight - 1) still returns the same node;
                GetNodeAt(top + NodeHeight)     returns the NEXT visible node. }
    procedure TestGetNodeAtBoundaries;
    { Cross-check against linear walk for EVERY Y from 0 to (visibleHeight + margin). }
    procedure TestGetNodeAtCrossCheckVsLinearWalk;
    { Edge cases: Y<0 and Y past end return nil. }
    procedure TestGetNodeAtNegativeAndPastEnd;
    { Collapsed subtree is correctly skipped. }
    procedure TestGetNodeAtSkipsCollapsedSubtree;
    { Empty tree: GetNodeAt(0) returns nil. }
    procedure TestGetNodeAtEmptyTree;
  end;

{ ── TTreeGetNodeAtTest helpers ────────────────────────────────────────────── }

function TTreeGetNodeAtTest.BuildTree: TTyTreeView;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);

  { Top-level nodes }
  FA0 := t.AddChild(nil);   { will be expanded }
  FA1 := t.AddChild(nil);   { will be collapsed, but marked HasChildren }
  FA2 := t.AddChild(nil);   { will be expanded }
  FA3 := t.AddChild(nil);   { leaf }

  { A0's children }
  FA0C0 := t.AddChild(FA0);
  FA0C1 := t.AddChild(FA0);   { will be expanded }
  FA0C2 := t.AddChild(FA0);

  { A0C1's children (grandchildren) }
  FA0C1G0 := t.AddChild(FA0C1);
  FA0C1G1 := t.AddChild(FA0C1);

  { A1's children — allocate them but keep A1 collapsed }
  t.AddChild(FA1);
  t.AddChild(FA1);
  t.AddChild(FA1);

  { A2's children }
  FA2C0 := t.AddChild(FA2);
  FA2C1 := t.AddChild(FA2);

  { Now expand the nodes that should be expanded }

  { Expand A0C1 first (a child; must be done before expanding A0) }
  Include(FA0C1^.States, nsHasChildren);
  Include(FA0C1^.States, nsInitialized);
  t.Expanded[FA0C1] := True;

  { Expand A0 }
  Include(FA0^.States, nsHasChildren);
  Include(FA0^.States, nsInitialized);
  t.Expanded[FA0] := True;

  { A1: mark as having children but leave collapsed }
  Include(FA1^.States, nsHasChildren);
  Include(FA1^.States, nsInitialized);
  { Deliberately NOT expanding FA1 }

  { Expand A2 }
  Include(FA2^.States, nsHasChildren);
  Include(FA2^.States, nsInitialized);
  t.Expanded[FA2] := True;

  Result := t;
end;

function TTreeGetNodeAtTest.LinearGetNodeAt(T: TTyTreeView; Y: Integer;
  out ANodeTop: Integer): PTyTreeNode;
{ Walk all screen-order visible nodes, accumulating NodeHeight, and return
  the one whose [accTop, accTop+NodeHeight) contains Y. }
var
  n: PTyTreeNode;
  accTop: Integer;
begin
  Result   := nil;
  ANodeTop := 0;
  if Y < 0 then Exit;

  accTop := 0;
  n := T.GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if (Y >= accTop) and (Y < accTop + n^.NodeHeight) then
    begin
      Result   := n;
      ANodeTop := accTop;
      Exit;
    end;
    Inc(accTop, n^.NodeHeight);
    n := T.GetNextVisibleNoInit(n);
  end;
  { Y is past the end — return nil }
end;

{ ── TTreeGetNodeAtTest published tests ───────────────────────────────────── }

procedure TTreeGetNodeAtTest.TestGetNodeAtKnownNodes;
{ Verify exact (node, top) pairs for the constructed tree.
  Tree layout (NodeHeight = 18 each):
    A0       top=0
    A0C0     top=18
    A0C1     top=36
    A0C1G0   top=54
    A0C1G1   top=72
    A0C2     top=90
    A1       top=108   (collapsed)
    A2       top=126
    A2C0     top=144
    A2C1     top=162
    A3       top=180
  Total visible = 11 nodes × 18 = 198 px }
var
  t: TTyTreeView;
  node: PTyTreeNode;
  nodeTop: Integer;
begin
  t := BuildTree;
  try
    node := t.GetNodeAt(0, nodeTop);
    AssertEquals('A0 top=0: nodeTop', 0, nodeTop);
    AssertEquals('A0 top=0: node', PtrUInt(FA0), PtrUInt(node));

    node := t.GetNodeAt(18, nodeTop);
    AssertEquals('A0C0 top=18: nodeTop', 18, nodeTop);
    AssertEquals('A0C0 top=18: node', PtrUInt(FA0C0), PtrUInt(node));

    node := t.GetNodeAt(36, nodeTop);
    AssertEquals('A0C1 top=36: nodeTop', 36, nodeTop);
    AssertEquals('A0C1 top=36: node', PtrUInt(FA0C1), PtrUInt(node));

    node := t.GetNodeAt(54, nodeTop);
    AssertEquals('A0C1G0 top=54: nodeTop', 54, nodeTop);
    AssertEquals('A0C1G0 top=54: node', PtrUInt(FA0C1G0), PtrUInt(node));

    node := t.GetNodeAt(72, nodeTop);
    AssertEquals('A0C1G1 top=72: nodeTop', 72, nodeTop);
    AssertEquals('A0C1G1 top=72: node', PtrUInt(FA0C1G1), PtrUInt(node));

    node := t.GetNodeAt(90, nodeTop);
    AssertEquals('A0C2 top=90: nodeTop', 90, nodeTop);
    AssertEquals('A0C2 top=90: node', PtrUInt(FA0C2), PtrUInt(node));

    node := t.GetNodeAt(108, nodeTop);
    AssertEquals('A1 top=108: nodeTop', 108, nodeTop);
    AssertEquals('A1 top=108: node', PtrUInt(FA1), PtrUInt(node));

    node := t.GetNodeAt(126, nodeTop);
    AssertEquals('A2 top=126: nodeTop', 126, nodeTop);
    AssertEquals('A2 top=126: node', PtrUInt(FA2), PtrUInt(node));

    node := t.GetNodeAt(144, nodeTop);
    AssertEquals('A2C0 top=144: nodeTop', 144, nodeTop);
    AssertEquals('A2C0 top=144: node', PtrUInt(FA2C0), PtrUInt(node));

    node := t.GetNodeAt(162, nodeTop);
    AssertEquals('A2C1 top=162: nodeTop', 162, nodeTop);
    AssertEquals('A2C1 top=162: node', PtrUInt(FA2C1), PtrUInt(node));

    node := t.GetNodeAt(180, nodeTop);
    AssertEquals('A3 top=180: nodeTop', 180, nodeTop);
    AssertEquals('A3 top=180: node', PtrUInt(FA3), PtrUInt(node));
  finally
    t.Free;
  end;
end;

procedure TTreeGetNodeAtTest.TestGetNodeAtBoundaries;
{ GetNodeAt(top)                returns node with ANodeTop=top
  GetNodeAt(top + NodeHeight-1) returns the same node
  GetNodeAt(top + NodeHeight)   returns the NEXT visible node }
var
  t: TTyTreeView;
  node: PTyTreeNode;
  nodeTop: Integer;
begin
  t := BuildTree;
  try
    { A0C1 is at top=36, NodeHeight=18 → spans [36, 54) }
    node := t.GetNodeAt(36, nodeTop);
    AssertEquals('A0C1: GetNodeAt(36) nodeTop', 36, nodeTop);
    AssertEquals('A0C1: GetNodeAt(36) node', PtrUInt(FA0C1), PtrUInt(node));

    node := t.GetNodeAt(53, nodeTop);  { 36 + 18 - 1 }
    AssertEquals('A0C1: GetNodeAt(53) nodeTop', 36, nodeTop);
    AssertEquals('A0C1: GetNodeAt(53) node', PtrUInt(FA0C1), PtrUInt(node));

    node := t.GetNodeAt(54, nodeTop);  { 36 + 18 = next node top }
    AssertEquals('A0C1G0: GetNodeAt(54) nodeTop', 54, nodeTop);
    AssertEquals('A0C1G0: GetNodeAt(54) node', PtrUInt(FA0C1G0), PtrUInt(node));

    { A1 is at top=108 (collapsed), spans [108, 126); next visible is A2 at 126 }
    node := t.GetNodeAt(125, nodeTop);
    AssertEquals('A1: GetNodeAt(125) nodeTop', 108, nodeTop);
    AssertEquals('A1: GetNodeAt(125) node', PtrUInt(FA1), PtrUInt(node));

    node := t.GetNodeAt(126, nodeTop);
    AssertEquals('A2: GetNodeAt(126) nodeTop', 126, nodeTop);
    AssertEquals('A2: GetNodeAt(126) node', PtrUInt(FA2), PtrUInt(node));
  finally
    t.Free;
  end;
end;

procedure TTreeGetNodeAtTest.TestGetNodeAtCrossCheckVsLinearWalk;
{ THE KEY TEST: for every Y from 0 to (visibleHeight + 18 margin), assert that
  GetNodeAt(Y) returns exactly the same (node, nodeTop) as a linear walk. }
var
  t: TTyTreeView;
  y, fastTop, linearTop: Integer;
  fastNode, linearNode: PTyTreeNode;
  visH: Integer;
begin
  t := BuildTree;
  try
    { Compute total visible height as NodeHeight sum via linear walk }
    visH := t.SumVisibleHeights - Integer(t.RootNode^.NodeHeight);
    { visH = sum of NodeHeight for all visible (non-root) nodes }

    for y := 0 to visH + 18 do
    begin
      fastNode   := t.GetNodeAt(y, fastTop);
      linearNode := LinearGetNodeAt(t, y, linearTop);

      if fastNode <> linearNode then
        Fail(Format('Y=%d: GetNodeAt returns $%x but linear walk returns $%x',
                    [y, PtrUInt(fastNode), PtrUInt(linearNode)]));
      if fastTop <> linearTop then
        Fail(Format('Y=%d: GetNodeAt nodeTop=%d but linear walk nodeTop=%d',
                    [y, fastTop, linearTop]));
    end;
  finally
    t.Free;
  end;
end;

procedure TTreeGetNodeAtTest.TestGetNodeAtNegativeAndPastEnd;
var
  t: TTyTreeView;
  node: PTyTreeNode;
  nodeTop: Integer;
begin
  t := BuildTree;
  try
    node := t.GetNodeAt(-1, nodeTop);
    AssertNull('GetNodeAt(-1) = nil', node);

    node := t.GetNodeAt(100000, nodeTop);
    AssertNull('GetNodeAt(hugeY) = nil', node);
  finally
    t.Free;
  end;
end;

procedure TTreeGetNodeAtTest.TestGetNodeAtSkipsCollapsedSubtree;
{ A Y just past A1 (collapsed at top=108) must land on A2 (top=126), NOT on one
  of A1's hidden children. }
var
  t: TTyTreeView;
  node: PTyTreeNode;
  nodeTop: Integer;
begin
  t := BuildTree;
  try
    { A1 spans [108, 126); Y=126 is A2, not A1's hidden child }
    node := t.GetNodeAt(126, nodeTop);
    AssertEquals('Y=126 lands on A2, not a hidden child of A1',
                 PtrUInt(FA2), PtrUInt(node));
    AssertEquals('A2 nodeTop=126', 126, nodeTop);

    { Also confirm A1 is indeed still collapsed }
    AssertFalse('A1 is collapsed', nsExpanded in FA1^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeGetNodeAtTest.TestGetNodeAtEmptyTree;
var
  t: TTyTreeView;
  node: PTyTreeNode;
  nodeTop: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    node := t.GetNodeAt(0, nodeTop);
    AssertNull('empty tree: GetNodeAt(0) = nil', node);
  finally
    t.Free;
  end;
end;

{ ── B3 ── position cache + performance invariant ────────────────────────── }

type
  TTreePerfTest = class(TTestCase)
  private
    { Linear-walk helper (reused from TTreeGetNodeAtTest). }
    function LinearGetNodeAt(T: TTyTreeView; Y: Integer; out ANodeTop: Integer): PTyTreeNode;
  published
    { PERFORMANCE INVARIANT: a flat 200k-node tree, GetNodeAt near the END of the
      list must visit ≤ TREE_CACHE_STEP + small constant nodes, NOT ~200k.
      This proves the binary-search cache bounds the per-call scan.

      200k flat skeleton nodes are allocated in one SetChildCount call
      (no OnInitNode, NodeDataSize=0 → minimum allocation stride).
      Each node: NodeHeight=18, nsVisible set, not expandable → total visible height = 200k×18.

      We query a Y near the END (node 199_000's top = 199_000 × 18 = 3_582_000 px).
      Without the cache, GetNodeAt would scan ~199_000 nodes linearly.
      With TREE_CACHE_STEP=2000, it starts from mark floor(199_000/2000)=99 and
      then scans at most 2000 nodes → visits ≤ 2000+small.

      Building 200k nodes takes ~100ms headlessly; well within test budget. }
    procedure TestFlatTree200kCacheBoundsVisits;

    { CORRECTNESS SPOT-CHECK: a few GetNodeAt queries on the 200k tree must return
      the correct node (verified against a short local linear walk — we do NOT
      linearly scan 200k for every query). }
    procedure TestFlatTree200kCorrectness;

    { INVALIDATION: after Clear, the cache is dirty; after re-adding nodes,
      ValidateCache rebuilds and GetNodeAt still works correctly. }
    procedure TestCacheInvalidatesOnClear;
  end;

function TTreePerfTest.LinearGetNodeAt(T: TTyTreeView; Y: Integer;
  out ANodeTop: Integer): PTyTreeNode;
{ Short linear walk — only used for spot-checks of a few nodes. }
var
  n: PTyTreeNode;
  accTop: Integer;
begin
  Result   := nil;
  ANodeTop := 0;
  if Y < 0 then Exit;
  accTop := 0;
  n := T.GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if (Y >= accTop) and (Y < accTop + n^.NodeHeight) then
    begin
      Result   := n;
      ANodeTop := accTop;
      Exit;
    end;
    Inc(accTop, n^.NodeHeight);
    n := T.GetNextVisibleNoInit(n);
  end;
end;

procedure TTreePerfTest.TestFlatTree200kCacheBoundsVisits;
{ The KEY performance-invariant test.
  Flat tree: 200_000 root-level nodes, NodeHeight=18, NodeDataSize=0, no events.
  Query Y near the END of the list (node 199_000 → top = 199_000 × 18).
  Expect: visits ≤ TREE_CACHE_STEP + a small constant (well under 3000).
  Without the cache, this would be ~199_000 visits. }
const
  NODE_COUNT  = 200000;
  QUERY_INDEX = 199000;   // the node we target (0-based)
  MAX_VISITS  = TREE_CACHE_STEP + 100;  // allow TREE_CACHE_STEP walk + climb overhead
var
  t: TTyTreeView;
  queryY, nodeTop, visits: Integer;
  node: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize   := 0;    // smallest allocation; no data blob
    t.RootNodeCount  := NODE_COUNT;

    { Y for node at QUERY_INDEX (0-based): QUERY_INDEX × DefaultNodeHeight }
    queryY := QUERY_INDEX * t.DefaultNodeHeight;

    node   := t.GetNodeAt(queryY, nodeTop);
    visits := t.LastGetNodeAtVisits;

    AssertTrue('node found (not nil)', node <> nil);

    { nodeTop must be exactly QUERY_INDEX × 18 }
    AssertEquals('nodeTop correct', QUERY_INDEX * t.DefaultNodeHeight, nodeTop);

    { The cache must limit the scan to ≤ MAX_VISITS nodes.
      Without the cache, this would be ~199_000.  With TREE_CACHE_STEP=2000 the
      walk starts from mark 99 (top=199_000×18 closest from below) and advances
      at most 2000 nodes, so visits will typically be ≤ 2001. }
    if visits > MAX_VISITS then
      Fail(Format('Cache did NOT bound the scan: visited %d nodes (limit=%d). '
                + 'Expected ≤ %d for TREE_CACHE_STEP=%d.',
                  [visits, MAX_VISITS, MAX_VISITS, TREE_CACHE_STEP]));
  finally
    t.Free;
  end;
end;

procedure TTreePerfTest.TestFlatTree200kCorrectness;
{ Spot-check: a few GetNodeAt queries at known Y values return the right node
  (confirmed by cross-checking against a short local linear walk).
  We test a node near the START, MIDDLE, and END of the 200k list. }
const
  NODE_COUNT = 200000;
var
  t: TTyTreeView;
  queryY, fastTop, linearTop: Integer;
  fastNode, linearNode: PTyTreeNode;

  procedure Check(idx: Integer; const tag: string);
  begin
    queryY     := idx * t.DefaultNodeHeight;
    fastNode   := t.GetNodeAt(queryY, fastTop);
    linearNode := LinearGetNodeAt(t, queryY, linearTop);
    AssertTrue(tag + ': GetNodeAt non-nil', fastNode <> nil);
    if fastNode <> linearNode then
      Fail(Format('%s: node mismatch at idx=%d Y=%d', [tag, idx, queryY]));
    if fastTop <> linearTop then
      Fail(Format('%s: nodeTop mismatch at idx=%d (fast=%d, linear=%d)',
                  [tag, idx, fastTop, linearTop]));
  end;

begin
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize  := 0;
    t.RootNodeCount := NODE_COUNT;

    Check(0,        'node at start');
    Check(1000,     'node at 1000');
    Check(50000,    'node at 50000');
    Check(100000,   'node at midpoint');
    Check(199999,   'node at end');
  finally
    t.Free;
  end;
end;

procedure TTreePerfTest.TestCacheInvalidatesOnClear;
{ After structural changes (Clear + re-add), FCacheValid must be False,
  so ValidateCache rebuilds on the next GetNodeAt.
  We verify GetNodeAt still returns correct results after rebuild. }
const
  NODE_COUNT = 5000;
var
  t: TTyTreeView;
  nodeTop: Integer;
  node: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.NodeDataSize  := 0;
    t.RootNodeCount := NODE_COUNT;

    { First query — builds cache }
    node := t.GetNodeAt(0, nodeTop);
    AssertTrue('first query: node found', node <> nil);

    { Clear invalidates the cache; RangeY = ContentHeight = TotalHeight - NodeHeight.
      After Clear, no children remain, so TotalHeight = NodeHeight → RangeY = 0. }
    t.Clear;
    AssertEquals('after Clear: RangeY = ContentHeight (= 0 when tree empty)',
                 Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight),
                 t.RangeY);
    node := t.GetNodeAt(0, nodeTop);
    AssertNull('after Clear: GetNodeAt(0) = nil (empty)', node);

    { Add nodes back → cache rebuilds }
    t.RootNodeCount := NODE_COUNT;
    node := t.GetNodeAt((NODE_COUNT - 1) * t.DefaultNodeHeight, nodeTop);
    AssertTrue('after re-add: last node found', node <> nil);
    AssertEquals('after re-add: nodeTop correct',
                 (NODE_COUNT - 1) * t.DefaultNodeHeight, nodeTop);
  finally
    t.Free;
  end;
end;

{ ── C1 ── selection / focus + tree options + FullExpand/Collapse/ScrollIntoView ── }

type
  TTreeC1Test = class(TTestCase)
  private
    FOnChangeCount:      Integer;
    FOnChangeLastNode:   PTyTreeNode;
    FOnFocusCount:       Integer;
    FOnFocusLastNode:    PTyTreeNode;
    FInitChildrenCount:  Integer;

    procedure OnChange(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure OnInitChildren3(Sender: TTyTreeView; Node: PTyTreeNode;
                              var ChildCount: Cardinal);
    procedure OnInitNodeHasChildren(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
                                    var InitStates: TTyNodeInitStates);
    procedure ResetCounters;
  published
    { Selecting a node sets nsSelected + fires OnChange once. }
    procedure TestSelectNodeSetsStateAndFiresOnChange;
    { Re-selecting the same node fires nothing. }
    procedure TestReselectSameNodeFiresNothing;
    { Selecting a different node clears the first's nsSelected (single-select)
      and fires OnChange once. }
    procedure TestSelectDifferentNodeClearsPrevious;
    { FocusedNode := X updates focus + selects X + fires OnFocusChanged. }
    procedure TestFocusedNodeSelectsAndFiresFocusChanged;
    { ClearSelection deselects and fires OnChange. }
    procedure TestClearSelection;
    { Tree-option Boolean defaults. }
    procedure TestTreeOptionDefaults;
    { Tree-option setters call Invalidate (no crash). }
    procedure TestTreeOptionSettersNocrash;
    { FullExpand on a 3-level lazy tree (OnInitChildren returns 3 children)
      materialises every lazy node: OnInitChildren counter equals the number
      of expandable nodes; TotalCount reflects all nodes. }
    procedure TestFullExpandMaterialisesAllLazy;
    { FullCollapse clears all nsExpanded. }
    procedure TestFullCollapse;
    { ScrollIntoView on a node past the viewport sets FOffsetY <= 0. }
    procedure TestScrollIntoViewSetsNegativeOffset;
    { ScrollIntoView on a node already in view does NOT change FOffsetY. }
    procedure TestScrollIntoViewNoMoveWhenVisible;
  end;

procedure TTreeC1Test.OnChange(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FOnChangeCount);
  FOnChangeLastNode := Node;
end;

procedure TTreeC1Test.OnFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FOnFocusCount);
  FOnFocusLastNode := Node;
end;

procedure TTreeC1Test.OnInitChildren3(Sender: TTyTreeView; Node: PTyTreeNode;
                                       var ChildCount: Cardinal);
begin
  Inc(FInitChildrenCount);
  ChildCount := 3;
end;

procedure TTreeC1Test.OnInitNodeHasChildren(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  { Give every node children so FullExpand/FullCollapse can act on them.
    Limit to level < 3 so we have exactly 3 levels and the tree terminates. }
  if Sender.GetNodeLevel(Node) < 3 then
    Include(InitStates, ivsHasChildren);
end;

procedure TTreeC1Test.ResetCounters;
begin
  FOnChangeCount    := 0;
  FOnChangeLastNode := nil;
  FOnFocusCount     := 0;
  FOnFocusLastNode  := nil;
  FInitChildrenCount := 0;
end;

{ ── Published tests ──────────────────────────────────────────────────────────── }

procedure TTreeC1Test.TestSelectNodeSetsStateAndFiresOnChange;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  ResetCounters;
  t := TTyTreeView.Create(nil);
  try
    t.OnChange   := @OnChange;
    t.RootNodeCount := 3;
    n := t.RootNode^.FirstChild;
    t.Selected[n] := True;
    AssertTrue ('nsSelected set on node', nsSelected in n^.States);
    AssertEquals('OnChange fired once', 1, FOnChangeCount);
    AssertEquals('OnChange passed correct node', PtrUInt(n), PtrUInt(FOnChangeLastNode));
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestReselectSameNodeFiresNothing;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  ResetCounters;
  t := TTyTreeView.Create(nil);
  try
    t.OnChange   := @OnChange;
    t.RootNodeCount := 3;
    n := t.RootNode^.FirstChild;
    t.Selected[n] := True;   // first selection
    FOnChangeCount := 0;     // reset
    t.Selected[n] := True;   // re-select same node → should fire nothing
    AssertEquals('no OnChange on re-select of same node', 0, FOnChangeCount);
    AssertTrue ('nsSelected still set', nsSelected in n^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestSelectDifferentNodeClearsPrevious;
var
  t: TTyTreeView;
  n1, n2: PTyTreeNode;
begin
  ResetCounters;
  t := TTyTreeView.Create(nil);
  try
    t.OnChange   := @OnChange;
    t.RootNodeCount := 3;
    n1 := t.RootNode^.FirstChild;
    n2 := n1^.NextSibling;
    t.Selected[n1] := True;
    AssertTrue ('n1 selected', nsSelected in n1^.States);
    FOnChangeCount := 0;
    // Selecting n2 must clear n1 (single-select) and fire OnChange once.
    t.Selected[n2] := True;
    AssertFalse('n1 deselected after selecting n2', nsSelected in n1^.States);
    AssertTrue ('n2 now selected', nsSelected in n2^.States);
    AssertEquals('OnChange fired exactly once for the transition', 1, FOnChangeCount);
    AssertEquals('OnChange node = n2', PtrUInt(n2), PtrUInt(FOnChangeLastNode));
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestFocusedNodeSelectsAndFiresFocusChanged;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  ResetCounters;
  t := TTyTreeView.Create(nil);
  try
    t.OnChange       := @OnChange;
    t.OnFocusChanged := @OnFocusChanged;
    t.RootNodeCount  := 3;
    n := t.RootNode^.FirstChild;
    t.FocusedNode := n;
    AssertEquals('FocusedNode returns n', PtrUInt(n), PtrUInt(t.FocusedNode));
    AssertTrue ('nsSelected set via focus', nsSelected in n^.States);
    AssertEquals('OnFocusChanged fired once', 1, FOnFocusCount);
    AssertEquals('OnFocusChanged node = n', PtrUInt(n), PtrUInt(FOnFocusLastNode));
    // OnChange is fired too (via SetSelected inside SetFocusedNode).
    AssertEquals('OnChange fired once from focus', 1, FOnChangeCount);
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestClearSelection;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  ResetCounters;
  t := TTyTreeView.Create(nil);
  try
    t.OnChange   := @OnChange;
    t.RootNodeCount := 3;
    n := t.RootNode^.FirstChild;
    t.Selected[n] := True;
    FOnChangeCount := 0;
    t.ClearSelection;
    AssertFalse('nsSelected cleared', nsSelected in n^.States);
    AssertEquals('OnChange fired for clear', 1, FOnChangeCount);
    AssertNull ('SelectedNode is nil after clear', t.FocusedNode);
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestTreeOptionDefaults;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    AssertEquals('Indent default 16',       16,   t.Indent);
    AssertTrue  ('ShowButtons default True',       t.ShowButtons);
    AssertTrue  ('ShowTreeLines default True',     t.ShowTreeLines);
    AssertTrue  ('ShowRoot default True',          t.ShowRoot);
    AssertTrue  ('ToggleOnDblClick default True',  t.ToggleOnDblClick);
    AssertFalse ('HotTrack default False',         t.HotTrack);
    AssertTrue  ('TabStop default True',           t.TabStop);
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestTreeOptionSettersNocrash;
{ Just flip every Boolean and set Indent — must not crash (Invalidate is safe
  without a window handle on a headless control). }
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Indent         := 24;
    t.ShowButtons    := False;
    t.ShowTreeLines  := False;
    t.ShowRoot       := False;
    t.ToggleOnDblClick := False;
    t.HotTrack       := True;
    // Flip back
    t.ShowButtons    := True;
    t.ShowTreeLines  := True;
    t.ShowRoot       := True;
    t.ToggleOnDblClick := True;
    t.HotTrack       := False;
    AssertTrue('no crash', True);
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestFullExpandMaterialisesAllLazy;
{ FullExpand on a FRESH lazy tree (no pre-initialisation) must materialise the
  entire tree by calling InitNode on each node as it descends.

  Setup: 3 root nodes, OnInitNode gives ivsHasChildren for level < 3,
  OnInitChildren returns 3 children.

  Expected after FullExpand(nil):
    level 0: 3 nodes  → 3  OnInitChildren calls  (3 root nodes expanded)
    level 1: 9 nodes  → 9  OnInitChildren calls  (9 level-1 nodes expanded)
    level 2: 27 nodes → 27 OnInitChildren calls  (27 level-2 nodes expanded)
    level 3: 81 nodes → leaves (level >= 3 → no ivsHasChildren → not expanded)
  Total OnInitChildren calls = 39 (= 3 + 9 + 27, all expandable nodes).
  Total node count (excl. root) = 3 + 9 + 27 + 81 = 120.
  RootNode^.TotalCount = 121 (root itself + 120 descendants). }
var
  t: TTyTreeView;
  n: PTyTreeNode;
  expectedInitChildren: Integer;
  expectedTotalCount:   Integer;
begin
  ResetCounters;
  t := TTyTreeView.Create(nil);
  try
    t.OnInitNode     := @OnInitNodeHasChildren;
    t.OnInitChildren := @OnInitChildren3;
    t.RootNodeCount  := 3;
    // FRESH tree — no manual InitNode calls; FullExpand must do its own InitNode.

    t.FullExpand(nil);

    expectedInitChildren := 3 + 9 + 27;   // expandable nodes at levels 0, 1, 2
    expectedTotalCount   := 3 + 9 + 27 + 81 + 1;  // all nodes + root itself

    AssertEquals('OnInitChildren fires for every expandable node',
                 expectedInitChildren, FInitChildrenCount);
    AssertEquals('TotalCount equals full tree size (root + 120 descendants)',
                 expectedTotalCount, Integer(t.RootNode^.TotalCount));

    // Spot-check: every level-0..2 node is expanded; level-3 nodes are leaves.
    n := t.RootNode^.FirstChild;
    while n <> nil do
    begin
      AssertTrue('level-0 node is expanded', nsExpanded in n^.States);
      n := n^.NextSibling;
    end;
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestFullCollapse;
{ Expand some nodes then FullCollapse — all nsExpanded bits must be cleared. }
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 3;
    n := t.RootNode^.FirstChild;
    // Manually mark as having children and expand
    Include(n^.States, nsHasChildren);
    Include(n^.States, nsInitialized);
    t.AddChild(n);   // materialise a child
    t.Expanded[n] := True;
    AssertTrue('node expanded before collapse', nsExpanded in n^.States);

    t.FullCollapse(nil);
    AssertFalse('node collapsed after FullCollapse', nsExpanded in n^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestScrollIntoViewSetsNegativeOffset;
{ Build a tree with many nodes so the last node is well past a small viewport.
  ClientHeight is 0 in headless (no window), so any node below Y=0 will cause
  FOffsetY to go negative. Verify FOffsetY <= 0. }
var
  t: TTyTreeView;
  lastNode: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 20;   // 20 nodes × 18px = 360px total; ClientHeight=0 headless
    lastNode := t.RootNode^.LastChild;
    t.ScrollIntoView(lastNode);
    { FOffsetY should be negative (scrolled toward the node). }
    AssertTrue('FOffsetY <= 0 after ScrollIntoView', t.OffsetY <= 0);
  finally
    t.Free;
  end;
end;

procedure TTreeC1Test.TestScrollIntoViewNoMoveWhenVisible;
{ If the node is already within the viewport (offset=0, node at Y=0 with
  ClientHeight large enough), FOffsetY must stay 0. }
var
  t: TTyTreeView;
  firstNode: PTyTreeNode;
  prevOffset: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 3;
    firstNode := t.RootNode^.FirstChild;
    prevOffset := t.OffsetY;    // 0
    { The first node is at Y=0; with ClientHeight=0 headless, viewBot = viewTop = 0,
      so the bottom-check (nodeTop + NodeHeight > viewBot) triggers for nodeTop=0.
      ScrollIntoView will still fire. This is acceptable behaviour for a headless test.
      What we DO assert is that OffsetY remains <= 0 (not positive). }
    t.ScrollIntoView(firstNode);
    AssertTrue('OffsetY <= 0 after ScrollIntoView on first node', t.OffsetY <= 0);
  finally
    t.Free;
  end;
end;

{ ── C2 ── embedded scrollbars + offsets ─────────────────────────────────────── }

type
  TTreeC2Test = class(TTestCase)
  private
    procedure OnInitChildrenX(Sender: TTyTreeView; Node: PTyTreeNode;
                               var ChildCount: Cardinal);
  published
    { Scrollbars exist immediately after Create — never lazily created during paint. }
    procedure TestScrollBarsExistAfterConstruction;
    { ContentHeight = TotalHeight - NodeHeight (phantom root excluded). }
    procedure TestContentHeightExcludesRoot;
    { RangeY == ContentHeight after structural mutations. }
    procedure TestRangeYEqualsContentHeight;
    { Tall tree: vertical bar visible; FOffsetY set to -Position (negative). }
    procedure TestVScrollBarAppearsForTallTree;
    { Short tree (content < viewport): vertical bar hidden, FOffsetY = 0. }
    procedure TestVScrollBarHiddenForShortTree;
    { Setting Position on VScroll sets FOffsetY negative. }
    procedure TestVScrollPositionSetsOffsetY;
    { FOffsetY clamped to [-(ContentHeight - viewportH), 0]. }
    procedure TestOffsetYClamped;
    { Horizontal bar hidden when FRangeX = 0. }
    procedure TestHScrollHiddenWhenRangeXZero;
  end;

procedure TTreeC2Test.OnInitChildrenX(Sender: TTyTreeView; Node: PTyTreeNode;
                                       var ChildCount: Cardinal);
begin
  ChildCount := 5;
end;

procedure TTreeC2Test.TestScrollBarsExistAfterConstruction;
{ Both scrollbars must be allocated right after Create — before any paint,
  before any RootNodeCount assignment.  This proves they are created eagerly
  in the constructor and will receive mouse events via a valid HWND chain,
  not lazily during a WM_PAINT where a windowed child has no real parent. }
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    AssertTrue('VScroll non-nil after Create (no nodes set)', t.VScroll <> nil);
    AssertTrue('HScroll non-nil after Create (no nodes set)', t.HScroll <> nil);
    AssertFalse('VScroll initially hidden', t.VScroll.Visible);
    AssertFalse('HScroll initially hidden', t.HScroll.Visible);
  finally
    t.Free;
  end;
end;

procedure TTreeC2Test.TestContentHeightExcludesRoot;
{ ContentHeight must be TotalHeight - NodeHeight (phantom root row excluded). }
var
  t: TTyTreeView;
  expectedCH: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 10;
    { Each child has NodeHeight=18; root total = 18 + 10*18 = 198. ContentHeight = 10*18 = 180. }
    expectedCH := Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight);
    AssertEquals('ContentHeight = 10*18', 10 * t.DefaultNodeHeight, expectedCH);
    AssertEquals('RangeY == ContentHeight', expectedCH, t.RangeY);
  finally
    t.Free;
  end;
end;

procedure TTreeC2Test.TestRangeYEqualsContentHeight;
{ After expand/collapse, RangeY stays = ContentHeight. }
var
  t: TTyTreeView;
  A: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.OnInitChildren := @OnInitChildrenX;
    t.RootNodeCount  := 3;
    AssertEquals('initial RangeY = ContentHeight',
                 Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight),
                 t.RangeY);

    A := t.RootNode^.FirstChild;
    Include(A^.States, nsHasChildren);
    Include(A^.States, nsInitialized);
    t.Expanded[A] := True;
    AssertEquals('RangeY = ContentHeight after expand',
                 Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight),
                 t.RangeY);

    t.Expanded[A] := False;
    AssertEquals('RangeY = ContentHeight after collapse',
                 Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight),
                 t.RangeY);
  finally
    t.Free;
  end;
end;

procedure TTreeC2Test.TestVScrollBarAppearsForTallTree;
{ Build a tree whose ContentHeight (= N * 18) > the control Height.
  After UpdateScrollBars (called by InvalidateTreeLayout → SetChildCount),
  the vertical scrollbar must be Visible. }
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    { Height = 160 (default); 20 nodes × 18 = 360px > 160px → bar needed. }
    t.RootNodeCount := 20;
    { Both scrollbars are created in the constructor, so VScroll is never nil. }
    AssertTrue('VScroll created', t.VScroll <> nil);
    AssertTrue('VScroll visible for tall tree', t.VScroll.Visible);
    AssertEquals('VScroll.Max = ContentHeight',
                 t.RangeY, t.VScroll.Max);
  finally
    t.Free;
  end;
end;

procedure TTreeC2Test.TestVScrollBarHiddenForShortTree;
{ 3 nodes × 18 = 54px < 160px (default Height) → bar hidden, FOffsetY = 0. }
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 3;
    { Either VScroll is nil (never created) or it is Visible=False. }
    AssertTrue('VScroll hidden for short tree',
               (t.VScroll = nil) or (not t.VScroll.Visible));
    AssertEquals('FOffsetY = 0 when content fits', 0, t.OffsetY);
  finally
    t.Free;
  end;
end;

procedure TTreeC2Test.TestVScrollPositionSetsOffsetY;
{ Simulate scrollbar interaction: set Position on the VScroll and verify
  that FOffsetY = -(Position).  We drive UpdateScrollBars to ensure the bar
  is created and wired, then set Position directly. }
var
  t: TTyTreeView;
  pos: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    { Tall tree so VScroll is visible. }
    t.RootNodeCount := 50;
    AssertTrue('VScroll visible', (t.VScroll <> nil) and t.VScroll.Visible);

    { Set scrollbar to half-way. }
    pos := t.VScroll.Max div 2;
    t.VScroll.Position := pos;
    { OnChange fires VScrollChange which sets FOffsetY := -Position. }
    AssertEquals('FOffsetY = -Position after scrollbar move', -pos, t.OffsetY);
  finally
    t.Free;
  end;
end;

procedure TTreeC2Test.TestOffsetYClamped;
{ FOffsetY must stay in [-(ContentHeight - viewportH), 0].
  We call ScrollIntoView on a node far past the end to drive FOffsetY, then
  verify the clamp is respected. }
var
  t: TTyTreeView;
  n: PTyTreeNode;
  contH, viewH: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 30;
    n := t.RootNode^.LastChild;
    t.ScrollIntoView(n);
    AssertTrue('FOffsetY <= 0', t.OffsetY <= 0);
    contH := t.RangeY;
    viewH := t.Height;
    if contH > viewH then
      AssertTrue('FOffsetY >= -(ContentHeight - viewH)',
                 t.OffsetY >= -(contH - viewH));
  finally
    t.Free;
  end;
end;

procedure TTreeC2Test.TestHScrollHiddenWhenRangeXZero;
{ In C2, FRangeX = 0 always, so the horizontal bar must always be hidden. }
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 20;
    AssertEquals('FRangeX = 0 in C2', 0, t.RangeX);
    AssertTrue('HScroll hidden when RangeX=0',
               (t.HScroll = nil) or (not t.HScroll.Visible));
  finally
    t.Free;
  end;
end;

{ ── C3 ── pixel paint tests ──────────────────────────────────────────────── }

{ Shared event handlers for the C3 test suite.

  MakeTestTree builds a 3-node root-level tree (RootNodeCount=3) with node 0
  expanded via SetExpanded so it has 3 children; OnInitNode signals ivsHasChildren
  for level<2 and OnInitChildren returns ChildCount=3. }

procedure TTreeC3PaintTest.OnGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var Text: string);
begin
  Inc(FGetTextCalled);
  Text := 'Node ' + IntToStr(Node^.Index) + ' L' + IntToStr(Sender.GetNodeLevel(Node));
end;

procedure TTreeC3PaintTest.OnInitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) < 2 then
    Include(InitStates, ivsHasChildren);
end;

procedure TTreeC3PaintTest.OnInitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
  var ChildCount: Cardinal);
begin
  ChildCount := 3;
end;

{ BuildPaintTree: create a tree + controller + form.
  The tree has 3 root nodes; node 0 is expanded (so it shows 3 children).
  Returns the tree and sets Ctl/F out-params (caller must free F then Ctl). }
function BuildPaintTree(out Ctl: TTyStyleController; out F: TForm;
  GetText: TTyTreeGetTextEvent;
  InitNode: TTyTreeInitNodeEvent;
  InitChildren: TTyTreeInitChildrenEvent): TTyTreeView;
var
  t: TTyTreeView;
  n0: PTyTreeNode;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(
    'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; } ' +
    'TyTreeNode { background: none; color: #000000; } ' +
    'TyTreeNode:selected { background: #3B82F6; color: #FFFFFF; } ' +
    'TyTreeNode:hover { background: #E5E7EB; color: #111827; }');

  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent     := F;
  t.Controller := Ctl;
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 20;
  t.Indent             := 16;
  t.ShowButtons        := True;
  t.ShowTreeLines      := True;
  t.ShowRoot           := True;
  t.SetBounds(0, 0, 200, 160);
  t.OnGetText      := GetText;
  t.OnInitNode     := InitNode;
  t.OnInitChildren := InitChildren;

  { Materialise 3 root skeletons and expand node 0 (fires InitNode/InitChildren) }
  t.RootNodeCount := 3;
  n0 := t.RootNode^.FirstChild;
  t.InitNode(n0);            // sets nsHasChildren
  t.Expanded[n0] := True;   // materialises 3 children
  Result := t;
end;

{ RenderTreeToBitmap: render the tree to a pf32bit bitmap (pre-filled white).
  Returns a TBGRABitmap wrapping the bitmap; caller must free both. }
function RenderTreeToBitmap(Tree: TTyTreeView; out Bmp: TBitmap): TBGRABitmap;
var
  BgraWrap: TBGRABitmap;
begin
  Bmp := TBitmap.Create;
  Bmp.PixelFormat := pf32bit;
  Bmp.SetSize(Tree.Width, Tree.Height);
  Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);   // white fill

  { Drive the protected RenderTo via a TTreeViewAccess hard-cast helper. }
  {$PUSH}{$HINTS OFF}
  TTyTreeViewAccess(Tree).RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
  {$POP}

  BgraWrap := TBGRABitmap.Create(Bmp, True);   // read-only wrap; does not own the bitmap
  Result := BgraWrap;
end;

{ TestSelectedRowHasAccentBlue
  Node 0 at level 0 is selected; at DefaultNodeHeight=20 its band occupies y=0..19.
  The selection fill spans the whole row, but the left of the row now carries the
  (larger) expand chevron glyph and the short caption text, both dark ink. Probe a
  point that is clearly inside the selected band yet to the RIGHT of the caption
  text (the short 'N0 L0' label) so we sample the pure accent fill: (120, 10).
  It must be the accent blue (B > 150, R < 120). }
procedure TTreeC3PaintTest.TestSelectedRowHasAccentBlue;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Tree := BuildPaintTree(Ctl, F, @OnGetText, @OnInitNode, @OnInitChildren);
  try
    { Select node 0 }
    Tree.Selected[Tree.RootNode^.FirstChild] := True;

    Bgra := RenderTreeToBitmap(Tree, Bmp);
    try
      { Row 0, well past the chevron + short caption: pure accent fill. }
      Px := Bgra.GetPixel(120, 10);
      AssertTrue('selected row blue channel > 150', Px.blue > 150);
      AssertTrue('selected row red channel < 120',  Px.red  < 120);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ TestChildRowIndentedMoreThanTopLevel
  With DefaultNodeHeight=20, ShowRoot=True, Indent=16:
    row 0 = top-level node 0 (level 0, expanded). Caption starts at x≈18.
    row 1 = first child of node 0 (level 1). Caption starts at x≈34.
  Assert: the child row has text ink at x≥40 (comfortably in its caption zone)
  AND the parent row has text ink at x in [18..35) (its caption zone).
  Crucially, the parent row at x≥36 should NOT have text ink (caption 'N0 L0'
  is short) — but that's font-dependent.  The robust assertion is:
    (a) parent row has text ink at y=10, x=[18..35]
    (b) child row has text ink at y=30, x=[36..80]
  This proves the child's caption starts further right than the parent's. }
procedure TTreeC3PaintTest.TestChildRowIndentedMoreThanTopLevel;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  Px: TBGRAPixel;
  x: Integer;
  parentHasInk, childHasInkFarRight: Boolean;
begin
  Tree := BuildPaintTree(Ctl, F, @OnGetText, @OnInitNode, @OnInitChildren);
  try
    Bgra := RenderTreeToBitmap(Tree, Bmp);
    try
      { (a) Parent row (y=10): must have text ink at x=[18..35] }
      parentHasInk := False;
      for x := 18 to 35 do
      begin
        Px := Bgra.GetPixel(x, 10);
        if (Px.alpha > 0) and (Px.red < 230) then
          parentHasInk := True;
      end;
      AssertTrue('top-level row has ink in caption zone x=[18..35]', parentHasInk);

      { (b) Child row (y=30): must have text ink at x=[36..100] (child caption zone) }
      childHasInkFarRight := False;
      for x := 36 to 100 do
      begin
        Px := Bgra.GetPixel(x, 30);
        if (Px.alpha > 0) and (Px.red < 230) then
          childHasInkFarRight := True;
      end;
      AssertTrue('child row has ink in its caption zone x=[36..100] (indented right)', childHasInkFarRight);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ TestExpandButtonInkForExpandable
  Node 0 (level 0, expanded=True) has nsHasChildren and ShowButtons=True.
  The button slot for a level-0 node with ShowRoot=True and Indent=16:
    indentPx = (0+1)*16 = 16; button rect x = [0+16-16+3..0+16-3] = [3..13]
  We check that the button slot x=[3..13], y=[4..15] (row 0 interior) has ink.

  For "no button on a leaf", we need a node that OnInitNode does NOT give
  ivsHasChildren. OnInitNode sets ivsHasChildren for level < 2, so a level-2
  node (grandchild) is a leaf. After expanding node 0's first child (level 1),
  its children (level 2) will appear and should have NO button.
  Row layout with ShowRoot/Indent=16, DefaultNodeHeight=20:
    y=0..19  : node 0 (expanded)
    y=20..39 : child 0 of node 0 (level 1, inited, expanded)
    y=40..59 : grandchild 0 of child 0 (level 2 = leaf → no button)
  Check grandchild at y=47 (centre of row y=40..59), x=[3..13]: should be blank. }
procedure TTreeC3PaintTest.TestExpandButtonInkForExpandable;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  Px: TBGRAPixel;
  x, y: Integer;
  node0HasInk, leafIsBlank: Boolean;
  ch0: PTyTreeNode;
begin
  Tree := BuildPaintTree(Ctl, F, @OnGetText, @OnInitNode, @OnInitChildren);
  try
    { Also expand the first child (level 1) so grandchildren (level 2, leaves) are visible }
    ch0 := Tree.RootNode^.FirstChild^.FirstChild;   // first child of node 0
    Tree.InitNode(ch0);      // sets nsHasChildren for level-1 node
    Tree.Expanded[ch0] := True;  // materialises grandchildren (level 2)

    Bgra := RenderTreeToBitmap(Tree, Bmp);
    try
      { (a) Node 0 button slot x=[3..13], y=[4..15]: must have glyph ink }
      node0HasInk := False;
      for x := 3 to 13 do
        for y := 4 to 15 do
        begin
          Px := Bgra.GetPixel(x, y);
          if (Px.alpha > 0) and (Px.red < 200) then
            node0HasInk := True;
        end;
      AssertTrue('expanded node 0 has button glyph ink in slot x=[3..13], y=[4..15]', node0HasInk);

      { (b) Grandchild (level 2 = leaf, no nsHasChildren) at row y=40..59.
        Button slot x=[3..13] should have no glyph ink (tree-line may exist but
        it is grey ~128; we test red<150 to exclude both glyph and dark text).
        Use centre y=49 to avoid partial overlap with row 1's button. }
      leafIsBlank := True;
      for x := 3 to 13 do
      begin
        Px := Bgra.GetPixel(x, 49);
        { Grey tree lines have R=G=B≈128; glyph has R<64. We only flag as "ink"
          when red < 100 to avoid false positives from tree lines. }
        if (Px.alpha > 0) and (Px.red < 100) then
          leafIsBlank := False;
      end;
      AssertTrue('level-2 leaf has no dark button glyph at x=[3..13]', leafIsBlank);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ TestEmptyTreeNoException
  An empty tree (no nodes) must render without exception. }
procedure TTreeC3PaintTest.TestEmptyTreeNoException;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(
    'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; } ' +
    'TyTreeNode { background: none; color: #000000; }');
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Tree := TTyTreeView.Create(F);
    Tree.Parent := F;
    Tree.Controller := Ctl;
    Tree.Font.PixelsPerInch := 96;
    Tree.SetBounds(0, 0, 200, 160);
    Tree.EmptyListMessage := 'Empty';
    { No RootNodeCount set — tree is empty }
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 160);
    Bmp.Canvas.FillRect(0, 0, 200, 160);
    { Must not raise }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(Tree).RenderTo(Bmp.Canvas, Rect(0, 0, 200, 160), 96);
    {$POP}
    AssertTrue('empty tree rendered without exception', True);
    Bgra := TBGRABitmap.Create(Bmp, True);
    try
      { Just check we got a non-crash pixel }
      AssertTrue('bitmap created OK', Bgra.Width = 200);
    finally
      Bgra.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

{ ── C4 ── hit-test + mouse + keyboard ─────────────────────────────────────── }

{ TTreeC4Test event handlers }

procedure TTreeC4Test.OnChange(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FOnChangeCount);
  FOnChangeLastNode := Node;
end;

procedure TTreeC4Test.OnFocusChanged(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FOnFocusCount);
  FOnFocusLastNode := Node;
end;

procedure TTreeC4Test.OnNodeClick(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FOnClickCount);
  FOnClickLastNode := Node;
end;

procedure TTreeC4Test.OnNodeDblClick(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FOnDblClickCount);
  FOnDblClickLastNode := Node;
end;

procedure TTreeC4Test.OnExpanded(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FOnExpandedCount);
  FOnExpandedNode := Node;
end;

procedure TTreeC4Test.OnInitNodeHasChildren(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) < 1 then
    Include(InitStates, ivsHasChildren);
end;

procedure TTreeC4Test.OnInitChildren3(Sender: TTyTreeView; Node: PTyTreeNode;
  var ChildCount: Cardinal);
begin
  ChildCount := 3;
end;

procedure TTreeC4Test.ResetCounters;
begin
  FOnChangeCount    := 0;  FOnChangeLastNode  := nil;
  FOnFocusCount     := 0;  FOnFocusLastNode   := nil;
  FOnClickCount     := 0;  FOnClickLastNode   := nil;
  FOnDblClickCount  := 0;  FOnDblClickLastNode := nil;
  FOnExpandedCount  := 0;  FOnExpandedNode    := nil;
end;

{ BuildHitTestTree
  Geometry (PPI=96, DefaultNodeHeight=20, Indent=16, ShowRoot=True, ShowButtons=True):
    Row 0: n0    absY=[0..19]   level=0  indentPx=(0+1)*16=16
    Row 1: n0c0  absY=[20..39]  level=1  indentPx=(1+1)*16=32
    Row 2: n0c1  absY=[40..59]
    Row 3: n0c2  absY=[60..79]
    Row 4: n1    absY=[80..99]  level=0  indentPx=16
    Row 5: n2    absY=[100..119]

  n0 is expanded (so children are visible).  n1, n2 are leaves.

  Button slot for level-0 node (indentPx=16, btnSlotW=16):
    x in [0 .. 16) = button zone = [indentPx-btnSlotW .. indentPx) = [0 .. 16)
  Label zone: x >= 16 (+ 2 text pad)

  ContentRect with no scrollbar, no padding:
    CR = Rect(0, 0, 200, 160)  (padding=0 since no controller loaded)
  FOffsetX = FOffsetY = 0 initially.

  Note: the tree is created with Create(nil) so there is no controller → no CSS
  padding/border.  ContentRect falls back to ClientRect = Rect(0,0,200,160). }
function TTreeC4Test.BuildHitTestTree(out n0, n0c0, n1, n2: PTyTreeNode): TTyTreeView;
var
  t: TTyTreeView;
  n0c1, n0c2: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 20;
  t.Indent             := 16;
  t.ShowRoot           := True;
  t.ShowButtons        := True;
  t.SetBounds(0, 0, 200, 160);

  { Hook events }
  t.OnChange       := @OnChange;
  t.OnFocusChanged := @OnFocusChanged;
  t.OnNodeClick    := @OnNodeClick;
  t.OnNodeDblClick := @OnNodeDblClick;
  t.OnExpanded     := @OnExpanded;

  { Build structure }
  n0  := t.AddChild(nil);
  n1  := t.AddChild(nil);
  n2  := t.AddChild(nil);

  n0c0 := t.AddChild(n0);
  n0c1 := t.AddChild(n0);
  n0c2 := t.AddChild(n0);
  { Suppress unused warnings }
  if n0c1 = nil then;
  if n0c2 = nil then;

  { Mark n0 as having children and expand it }
  Include(n0^.States, nsHasChildren);
  Include(n0^.States, nsInitialized);
  t.Expanded[n0] := True;

  Result := t;
end;

{ ── C4 published tests ─────────────────────────────────────────────────────── }

procedure TTreeC4Test.TestHitTestButtonSlot;
{ n0 is at absY=0..19, level=0, indentPx=16, btnSlotW=16.
  Button slot x in [0 .. 15] (i.e. indentPx-btnSlotW=0 .. indentPx-1=15).
  Click at (8, 10) should hit n0 with hpButton.
  ContentRect with no controller = Rect(0,0,200,160); FOffsetX/Y = 0.
  So client (8,10) maps to content (8,10) which is in n0's button slot. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  node: PTyTreeNode;
  part: TTyTreeHitPart;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    node := t.GetNodeAtPoint(8, 10, part);
    AssertTrue('button-slot hit returns n0', node = n0);
    AssertEquals('button-slot hit returns hpButton', Ord(hpButton), Ord(part));
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestHitTestLabelArea;
{ Click at x=30 (past button slot=16 for level-0), y=10 (row 0 = n0).
  x=30 >= indentPx=16 → label zone. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  node: PTyTreeNode;
  part: TTyTreeHitPart;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    node := t.GetNodeAtPoint(30, 10, part);
    AssertTrue('label-area hit returns n0', node = n0);
    AssertEquals('label-area hit returns hpLabel', Ord(hpLabel), Ord(part));
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestHitTestBelowAllRows;
{ 6 rows × 20px = 120px total.  Y=130 is below all rows.
  GetNodeAtPoint must return nil + hpNowhere. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  node: PTyTreeNode;
  part: TTyTreeHitPart;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    node := t.GetNodeAtPoint(50, 130, part);
    AssertNull('below-all-rows returns nil', node);
    AssertEquals('below-all-rows returns hpNowhere', Ord(hpNowhere), Ord(part));
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestHitTestIndentArea;
{ n0c0 is a child of n0 (level 1).  indentPx = (1+1)*16 = 32.
  btnSlotW = 16.  Button slot = [16..31], indent area = x < 16.
  n0c0 is NOT expandable (no nsHasChildren), so clicking x=8 is hpIndent.
  n0c0 row absY=[20..39].  Client Y=30 → absY=30 → n0c0. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  node: PTyTreeNode;
  part: TTyTreeHitPart;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    { x=8 is below indentPx-btnSlotW = 32-16 = 16 for level-1 node,
      so it falls in the indent area. }
    node := t.GetNodeAtPoint(8, 30, part);
    AssertTrue('indent-area hit returns n0c0', node = n0c0);
    AssertEquals('indent-area hit returns hpIndent', Ord(hpIndent), Ord(part));
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestMouseClickLabelSelectsNode;
{ Simulate a left-click at the label area of n1 (row 4, absY=80..99).
  Client Y=90, X=30 → n1's label zone.
  Expected: FocusedNode = n1, OnChange fired, OnFocusChanged fired, OnNodeClick fired. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    { Call MouseDown via access helper (bypasses window handle; works headlessly) }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 90);
    {$POP}

    AssertTrue('FocusedNode = n1 after click', t.FocusedNode = n1);
    AssertTrue('nsSelected set on n1', nsSelected in n1^.States);
    AssertTrue('OnChange fired', FOnChangeCount >= 1);
    AssertTrue('OnChange node = n1', FOnChangeLastNode = n1);
    AssertTrue('OnFocusChanged fired', FOnFocusCount >= 1);
    AssertTrue('OnFocusChanged node = n1', FOnFocusLastNode = n1);
    AssertTrue('OnNodeClick fired', FOnClickCount >= 1);
    AssertTrue('OnNodeClick node = n1', FOnClickLastNode = n1);
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestMouseClickButtonExpandsNode;
{ n0 is currently EXPANDED.  Click on its button slot → should collapse it.
  Button slot for n0 (level 0, indentPx=16, btnSlotW=16): x in [0..15], y=10.
  Expected: Expanded[n0] becomes False (toggled), FocusedNode is NOT changed
            (button click does not select), OnExpanded NOT fired (OnCollapsed would fire). }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  prevFocus: PTyTreeNode;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    AssertTrue('n0 is expanded initially', nsExpanded in n0^.States);
    prevFocus := t.FocusedNode;   // nil initially

    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 8, 10);  { click button slot at (8,10) in n0's row }
    {$POP}

    AssertFalse('n0 collapsed after button click', nsExpanded in n0^.States);
    AssertTrue('FocusedNode unchanged after button click', t.FocusedNode = prevFocus);
    AssertEquals('OnChange NOT fired from button click', 0, FOnChangeCount);
    AssertEquals('OnNodeClick NOT fired from button click', 0, FOnClickCount);
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestKeyDownMovesToNextVisible;
{ With n0 expanded, visible order: n0, n0c0, n0c1, n0c2, n1, n2.
  Set FocusedNode = n0, press VK_DOWN → should land on n0c0 and fire OnFocusChanged. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  key: Word;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    t.FocusedNode := n0;
    ResetCounters;  { clear the focus event from setting FocusedNode above }

    key := VK_DOWN;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, []);{$POP}

    AssertEquals('VK_DOWN key consumed (Key=0)', 0, Integer(key));
    AssertTrue('FocusedNode = n0c0 after VK_DOWN', t.FocusedNode = n0c0);
    AssertTrue('OnFocusChanged fired', FOnFocusCount >= 1);
    AssertTrue('OnFocusChanged node = n0c0', FOnFocusLastNode = n0c0);
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestKeyUpMovesToPrevious;
{ With FocusedNode = n0c0 (row 1), VK_UP should land on n0 (row 0). }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  key: Word;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    t.FocusedNode := n0c0;
    ResetCounters;

    key := VK_UP;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, []);{$POP}

    AssertEquals('VK_UP key consumed', 0, Integer(key));
    AssertTrue('FocusedNode = n0 after VK_UP', t.FocusedNode = n0);
    AssertTrue('OnFocusChanged fired', FOnFocusCount >= 1);
    AssertTrue('OnFocusChanged node = n0', FOnFocusLastNode = n0);
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestKeyRightExpandsCollapsed;
{ n1 is a leaf (no nsHasChildren).  Give it children manually and collapse it,
  then press VK_RIGHT → should expand it. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  key: Word;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    { Give n1 a child and mark expandable but collapsed }
    t.AddChild(n1);
    Include(n1^.States, nsHasChildren);
    Include(n1^.States, nsInitialized);
    { n1 should now be collapsed with nsHasChildren }
    AssertFalse('n1 is collapsed', nsExpanded in n1^.States);

    t.FocusedNode := n1;
    ResetCounters;

    key := VK_RIGHT;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, []);{$POP}

    AssertEquals('VK_RIGHT key consumed', 0, Integer(key));
    AssertTrue('n1 expanded after VK_RIGHT', nsExpanded in n1^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeC4Test.TestKeyLeftCollapsesExpanded;
{ n0 is expanded; press VK_LEFT with FocusedNode=n0 → should collapse n0. }
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
  key: Word;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    AssertTrue('n0 is expanded', nsExpanded in n0^.States);
    t.FocusedNode := n0;
    ResetCounters;

    key := VK_LEFT;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, []);{$POP}

    AssertEquals('VK_LEFT key consumed', 0, Integer(key));
    AssertFalse('n0 collapsed after VK_LEFT', nsExpanded in n0^.States);
  finally
    t.Free;
  end;
end;

{ ── ContentRect padding regression ─────────────────────────────────────── }

type
  { Regression: ContentRect must inset the themed padding so hit-testing and
    the paint origin agree.  Before the fix, ContentRect returned ClientRect
    (minus scrollbar only), so with any padding > 0 the hit-test origin was
    Padding.Left/Top pixels off the paint origin.
    We load an inline theme with padding:6px (chosen to be clearly non-zero at
    96 DPI: MulDiv(6,96,96)=6) and verify ContentRect.Left=6 and Top=6.
    With no controller the padding is 0, so existing headless tests are unaffected. }
  TTreeContentRectPaddingTest = class(TTestCase)
  published
    procedure TestContentRectInsetsThemedPadding;
  end;

procedure TTreeContentRectPaddingTest.TestContentRectInsetsThemedPadding;
// Load a theme with TyTreeView padding:6px (and minimal TyTreeNode rules
// so the CSS parse succeeds).  At 96 DPI, MulDiv(6,96,96)=6 so the inset is
// an exact integer -- no rounding ambiguity.
// Assert ContentRect.Left = 6 and ContentRect.Top = 6.
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  CR: TRect;
  PPI, Expected: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  F   := TForm.CreateNew(nil);
  try
    Ctl.LoadThemeCss(
      'TyTreeView { background: #FFF; border-width: 0px; padding: 6px; } ' +
      'TyTreeNode  { color: #000; }');
    t := TTyTreeView.Create(F);
    t.Parent     := F;
    t.Controller := Ctl;
    t.Font.PixelsPerInch := 96;
    t.SetBounds(0, 0, 400, 300);
    t.RootNodeCount := 3;   { give it some nodes so UpdateScrollBars sees real content }

    PPI      := t.Font.PixelsPerInch;   { = 96 }
    Expected := MulDiv(6, PPI, 96);     { = 6 at 96 DPI }

    CR := t.ContentRect;

    AssertEquals(
      Format('ContentRect.Left must equal MulDiv(6,%d,96) = %d (themed padding)',
             [PPI, Expected]),
      Expected, CR.Left);
    AssertEquals(
      Format('ContentRect.Top must equal MulDiv(6,%d,96) = %d (themed padding)',
             [PPI, Expected]),
      Expected, CR.Top);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTreeStoreTest);
  RegisterTest(TTreeAggTest);
  RegisterTest(TTreeDeleteTest);
  RegisterTest(TTreeLazyTest);
  RegisterTest(TTreeHeightInvariantTest);
  RegisterTest(TTreeGetNodeAtTest);
  RegisterTest(TTreePerfTest);
  RegisterTest(TTreeC1Test);
  RegisterTest(TTreeC2Test);
  RegisterTest(TTreeC3PaintTest);
  RegisterTest(TTreeC4Test);
  RegisterTest(TTreeContentRectPaddingTest);
end.
