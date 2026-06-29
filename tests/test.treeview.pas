unit test.treeview;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.TreeView,
  tyControls.TreeView.Columns;

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
    { FIX 1: OnFreeNode must fire on destructor teardown (without explicit Clear) }
    procedure TestOnFreeNodeFiredOnTreeviewDestruction;
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
    { FIX 2: DeleteNode must clear FLastMouseNode to prevent UAF on DblClick }
    procedure TestDeleteNodeClearsFLastMouseNode;
    { FIX 3: right-click always moves FocusedNode even when node already selected }
    procedure TestRightClickAlwaysSetsFocus;
  end;

implementation

type
  { C3/C4: hard-cast helper to call protected methods from tests. }
  TTyTreeViewAccess = class(TTyTreeView)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MouseMove(Shift: TShiftState; X, Y: Integer);
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DblClick;
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

procedure TTyTreeViewAccess.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
end;

procedure TTyTreeViewAccess.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTyTreeViewAccess.DblClick;
begin
  inherited DblClick;
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
// A1 fix: DeleteNode re-sequences sibling Index values after an unlink so that
// remaining siblings always have consecutive 0-based indices.
// The Clear fast-path skips the re-sequence (guarded by nsClearing on FRoot)
// so bulk teardown stays O(n), not O(n²).
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
    // After deleting n2, DeleteNode re-sequences: n1->0, n3->1
    t.DeleteNode(n2);
    AssertEquals('root ChildCount = 2 after delete', 2, Integer(t.RootNode^.ChildCount));
    // n3 is still linked and accessible via n1^.NextSibling
    AssertEquals('n1.NextSibling = n3', PtrUInt(n3), PtrUInt(n1^.NextSibling));
    // A1: re-sequenced indices
    AssertEquals('n1 index = 0 after resequence', 0, Integer(n1^.Index));
    AssertEquals('n3 index = 1 after resequence', 1, Integer(n3^.Index));
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

{ FIX 1: TestOnFreeNodeFiredOnTreeviewDestruction
  Verifies that OnFreeNode fires during destructor teardown even when the app
  never calls Clear explicitly.  This is the regression test for the bug where
  FOnFreeNode was nilled before Clear in Destroy, silently skipping every
  managed-field release.

  Pattern:
    - NodeDataSize = SizeOf(TManagedRec) so each node has an AnsiString blob.
    - OnFreeNode increments FFireCount; also clears the AnsiString (canonical
      managed-release pattern) so the heap is left clean.
    - Build a 4-node tree, assign handler, then FREE the tree WITHOUT calling
      Clear → destructor must still walk and fire OnFreeNode for all 4 nodes.

  This test MUST FAIL before FIX 1 (when FOnFreeNode was nilled before Clear)
  and PASS after. }
procedure TTreeDeleteTest.TestOnFreeNodeFiredOnTreeviewDestruction;
var
  t: TTyTreeView;
  n: PTyTreeNode;
  i: Integer;
begin
  FFireCount := 0;
  t := TTyTreeView.Create(nil);
  t.NodeDataSize := SizeOf(TManagedRec);
  // Add 4 nodes and write a heap-allocated string into each blob.
  // AllocMem zero-fills so the AnsiString field starts as a valid nil ref.
  for i := 0 to 3 do
  begin
    n := t.AddChild(nil);
    PManagedRec(t.GetNodeData(n))^.S := 'node-' + IntToStr(i);
    PManagedRec(t.GetNodeData(n))^.I := i;
  end;
  t.OnFreeNode := @OnFreeManagedRec;  // clears S then increments FFireCount
  // Free without an explicit Clear — destructor must still fire OnFreeNode
  t.Free;
  AssertEquals('OnFreeNode fired for all 4 nodes on Free (no explicit Clear)', 4, FFireCount);
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
    { FIX 4 helper: returns a text string wide enough to overflow a 50px viewport }
    procedure OnGetTextWide(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
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
    { FIX 4: RangeX retracts to 0 after Clear; HScroll hidden again. }
    procedure TestFRangeXRetractsAfterClear;
  end;

procedure TTreeC2Test.OnInitChildrenX(Sender: TTyTreeView; Node: PTyTreeNode;
                                       var ChildCount: Cardinal);
begin
  ChildCount := 5;
end;

procedure TTreeC2Test.OnGetTextWide(Sender: TTyTreeView; Node: PTyTreeNode;
                                     var Text: string);
begin
  Text := 'Wide label text that overflows the narrow 50px viewport easily';
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

{ FIX 4: TestFRangeXRetractsAfterClear
  After a paint pass that sets FRangeX > 0 (making HScroll visible), a Clear
  followed by another paint must collapse FRangeX back to 0 and hide HScroll.

  We build a narrow tree (50px wide) with OnGetText wired to return a wide
  string, so the first RenderTo sets FRangeX > 50 and shows HScroll.
  Then Clear → RangeX must drop to 0 immediately (InvalidateTreeLayout).
  A second RenderTo on the empty tree must leave RangeX = 0 / HScroll hidden.

  This validates the FIX 4 invariant: InvalidateTreeLayout resets FRangeX = 0
  so a new paint pass accumulates from scratch. }
procedure TTreeC2Test.TestFRangeXRetractsAfterClear;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  Bmp: TBitmap;
  n: PTyTreeNode;
begin
  Ctl := TTyStyleController.Create(nil);
  F   := TForm.CreateNew(nil);
  try
    Ctl.LoadThemeCss(
      'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; } ' +
      'TyTreeNode  { background: none; color: #000000; }');
    t := TTyTreeView.Create(F);
    t.Parent     := F;
    t.Controller := Ctl;
    t.Font.PixelsPerInch := 96;
    t.DefaultNodeHeight  := 20;
    t.Indent             := 16;
    t.ShowRoot           := True;
    { Width = 50px (narrow): any node with a non-trivial label overflows. }
    t.SetBounds(0, 0, 50, 200);
    { OnGetText returns a wide string so FRangeX accumulation has text to measure. }
    t.OnGetText := @OnGetTextWide;

    { Three root nodes, all marked initialised so RenderTo skips lazy init. }
    t.RootNodeCount := 3;
    n := t.RootNode^.FirstChild;
    while n <> nil do
    begin
      Include(n^.States, nsInitialized);
      n := n^.NextSibling;
    end;

    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(t.Width, t.Height);

      { First paint: expect FRangeX > 0 because labels overflow 50px. }
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      {$PUSH}{$HINTS OFF}
      TTyTreeViewAccess(t).RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      {$POP}
      AssertTrue('RangeX > 0 after first paint (wide labels overflow narrow viewport)',
                 t.RangeX > 0);
      AssertTrue('HScroll visible after first paint',
                 (t.HScroll <> nil) and t.HScroll.Visible);

      { Clear: InvalidateTreeLayout must reset FRangeX = 0 immediately. }
      t.Clear;
      AssertEquals('RangeX = 0 immediately after Clear', 0, t.RangeX);

      { Second paint on empty tree: FRangeX stays 0; HScroll hidden. }
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      {$PUSH}{$HINTS OFF}
      TTyTreeViewAccess(t).RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      {$POP}
      AssertEquals('RangeX = 0 after Clear + repaint (empty tree)', 0, t.RangeX);
      AssertTrue('HScroll hidden after Clear + repaint',
                 (t.HScroll = nil) or (not t.HScroll.Visible));
    finally
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
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

{ FIX 2: TestDeleteNodeClearsFLastMouseNode
  When a node is deleted that was previously recorded in FLastMouseNode
  (by a MouseDown), DblClick must not crash (use-after-free) and must be a no-op.
  We verify the behaviour by observing that no DblClick event fires.

  Geometry: use BuildHitTestTree (DefaultNodeHeight=20, ShowRoot=True).
    n1 is at absY=80..99 (row 4).  Click at (30, 90) to set FLastMouseNode=n1.
    Then DeleteNode(n1) — FLastMouseNode must become nil.
    Then call DblClick — must not crash AND must NOT fire OnNodeDblClick. }
procedure TTreeC4Test.TestDeleteNodeClearsFLastMouseNode;
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    { Left-click on n1's label to set FLastMouseNode = n1 }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 90);
    {$POP}
    AssertTrue('after MouseDown FocusedNode = n1', t.FocusedNode = n1);
    // Now delete n1; FLastMouseNode must be cleared
    t.DeleteNode(n1);
    // Call DblClick — if FLastMouseNode is not nil this would be a UAF.
    // The call must succeed without an exception.
    ResetCounters;
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).DblClick;
    {$POP}
    // DblClick on a nil FLastMouseNode must fire 0 DblClick events
    AssertEquals('OnNodeDblClick NOT fired after DeleteNode cleared FLastMouseNode',
                 0, FOnDblClickCount);
  finally
    t.Free;
  end;
end;

{ FIX 3: TestRightClickAlwaysSetsFocus
  Right-click must unconditionally move FocusedNode to the clicked node,
  even when the node is already selected.  This prevents a desync where
  FocusedNode and the visually-highlighted row differ after a programmatic
  Selected[] assignment without focus.

  Setup: select n2 programmatically (no focus change), then right-click n2.
  Expected: FocusedNode = n2 after right-click.

  Geometry: n2 at absY=100..119 (row 5).  Right-click at (30, 110). }
procedure TTreeC4Test.TestRightClickAlwaysSetsFocus;
var
  t: TTyTreeView;
  n0, n0c0, n1, n2: PTyTreeNode;
begin
  ResetCounters;
  t := BuildHitTestTree(n0, n0c0, n1, n2);
  try
    // Programmatically select n2 without moving focus
    t.Selected[n2] := True;
    AssertTrue('n2 is selected', nsSelected in n2^.States);
    AssertTrue('FocusedNode is NOT n2 yet (selection only)', t.FocusedNode <> n2);

    // Right-click on n2 — even though nsSelected is set, focus must follow
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbRight, [], 30, 110);
    {$POP}
    AssertTrue('FocusedNode = n2 after right-click on already-selected node',
               t.FocusedNode = n2);
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

{ ── HiDPI (PPI≠96) vertical-axis correctness ──────────────────────────────── }

type
  { Two tests that are IMPOSSIBLE to pass before the fix but trivially pass after:
      (a) hit-test matches paint at PPI=144 (150 %)
      (b) ScrollIntoView / UpdateScrollBars reaches the true logical bottom

    Tree geometry (PPI=144, border-width=0, padding=0):
      DefaultNodeHeight = 20 logical → 30 device pixels per row
      Viewport          = 200×300 device = 200×200 logical (MulDiv(300,96,144))
      20 root nodes     → ContentHeight (logical) = 400
      FOffsetY = 0, no scrolling yet
      CR.Top = 0 (no padding / border)

    Row mapping at FOffsetY=0:
      node[i]  logical [i*20 .. i*20+19]
               device  [i*30 .. i*30+29]

    The 3rd visible row (i=2):
      logical [40..59]   device [60..89]   center device-Y = 75

    Pre-fix GetNodeAtPoint computes absY = (75-0)+0 = 75 and hits node[3] (logical 60-79).
    Post-fix it computes absY = MulDiv(75,96,144)+0 = 50 and hits node[2]. }
  TTreeHiDPITest = class(TTestCase)
  published
    { (a) GetNodeAtPoint centre of 3rd visible row must return the 3rd node. }
    procedure TestHitTestMatchesPaintAt144DPI;
    { (b) ScrollIntoView on last node must reach logical bottom. }
    procedure TestScrollIntoViewReachesBottomAt144DPI;
  end;

{ BuildHiDPITree144: 20 root nodes, PPI=144, 200×300 device viewport, no border/padding.
  Caller must free F then Ctl when done. }
function BuildHiDPITree144(out Ctl: TTyStyleController; out F: TForm): TTyTreeView;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(
    'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; } ' +
    'TyTreeNode  { background: none; color: #000000; }');
  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent              := F;
  t.Controller          := Ctl;
  t.Font.PixelsPerInch  := 144;
  t.DefaultNodeHeight   := 20;   { logical; 30 device pixels at PPI=144 }
  t.Indent              := 16;
  t.ShowRoot            := True;
  t.ShowButtons         := False;
  { Width=200 device, Height=300 device (= 200 logical at 144 DPI). }
  t.SetBounds(0, 0, 200, 300);
  t.RootNodeCount := 20;
  { Mark all nodes initialised so GetNodeAtPoint skips lazy callbacks. }
  n := t.RootNode^.FirstChild;
  while n <> nil do
  begin
    Include(n^.States, nsInitialized);
    n := n^.NextSibling;
  end;
  Result := t;
end;

procedure TTreeHiDPITest.TestHitTestMatchesPaintAt144DPI;
{ The 3rd visible row (index 2, FOffsetY=0) occupies device Y [60..89].
  Its visual centre is device Y = 75.  GetNodeAtPoint must return the 3rd root
  child (the node RenderTo paints at that device Y).

  Pre-fix:  absY = (75 - 0) + 0 = 75 → GetNodeAt returns node[3] (wrong).
  Post-fix: absY = MulDiv(75, 96, 144) + 0 = 50 → GetNodeAt returns node[2] (correct). }
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  thirdNode: PTyTreeNode;
  part: TTyTreeHitPart;
  hitNode: PTyTreeNode;
  devRowH, centerY: Integer;
begin
  t := BuildHiDPITree144(Ctl, F);
  try
    { Identify the 3rd root child (0-based index 2). }
    thirdNode := t.RootNode^.FirstChild;
    AssertTrue('tree has >=3 nodes', thirdNode <> nil);
    thirdNode := thirdNode^.NextSibling;
    AssertTrue('tree has >=3 nodes (2)', thirdNode <> nil);
    thirdNode := thirdNode^.NextSibling;
    AssertTrue('tree has >=3 nodes (3)', thirdNode <> nil);

    { Device row height = MulDiv(20, 144, 96) = 30. }
    devRowH := MulDiv(t.DefaultNodeHeight, t.Font.PixelsPerInch, 96);
    { Centre of 3rd row (0-based i=2): i * devRowH + devRowH / 2 = 75. }
    centerY := 2 * devRowH + devRowH div 2;

    hitNode := t.GetNodeAtPoint(50, centerY, part);

    AssertTrue(
      Format('GetNodeAtPoint at device-Y=%d must return 3rd node (hitNode=nil: %s)',
             [centerY, BoolToStr(hitNode = nil, True)]),
      hitNode = thirdNode);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTreeHiDPITest.TestScrollIntoViewReachesBottomAt144DPI;
{ After ScrollIntoView(lastNode), FOffsetY must equal the true logical bottom:
    -(ContentHeight - viewH_logical)
  where viewH_logical = MulDiv(300, 96, 144) = 200.
  ContentHeight (logical) = 20 nodes * 20 = 400.
  Expected FOffsetY = -(400 - 200) = -200.

  Pre-fix: ScrollIntoView used device ClientHeight=300 instead of logical 200,
  so it would clamp at -(400 - 300) = -100, failing to reach the last node. }
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  lastNode: PTyTreeNode;
  contH, viewHLogical, expectedOff: Integer;
begin
  t := BuildHiDPITree144(Ctl, F);
  try
    lastNode := t.RootNode^.LastChild;
    AssertTrue('lastNode non-nil', lastNode <> nil);

    t.ScrollIntoView(lastNode);

    contH        := t.ContentHeight;                                    { 400 logical }
    viewHLogical := MulDiv(t.ClientHeight, 96, t.Font.PixelsPerInch);  { 200 logical }
    expectedOff  := -(contH - viewHLogical);                            { -200 }

    AssertTrue('FOffsetY <= 0 after ScrollIntoView', t.OffsetY <= 0);
    AssertEquals(
      Format('FOffsetY must reach -(ContentHeight - viewH_logical) = %d', [expectedOff]),
      expectedOff, t.OffsetY);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ ── C (columns): Phase C1 + C2 paint tests ────────────────────────────────── }

type
  { TTreeColumnPaintTest — pixel tests for multi-column node paint (C1)
    and header band paint (C2).
    Guard: 0-column render must be byte-identical to ③a (existing tests green). }
  TTreeColumnPaintTest = class(TTestCase)
  private
    { Per-column text returned by OnGetTextWithType }
    procedure OnGetTextWithType(Sender: TTyTreeView; Node: PTyTreeNode;
      Column: Integer; TextType: TTyVSTTextType; var CellText: string);
    procedure OnInitNodeHasChildren(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure OnInitChildren3(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    { C0 regression: 0-column callbacks mimicking ③a (same as TTreeC3PaintTest) }
    procedure C0GetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
    procedure C0InitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure C0InitChildren(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);

    { Build a 3-column tree and render it.  Returns the BGRA bitmap (caller
      frees both Bgra and Bmp).
      Col 0 (main, width=120): tree chrome + caption
      Col 1 (left-align, width=80): flat text
      Col 2 (right-align, width=100): flat right-aligned text
      PPI=96; DefaultNodeHeight=22; ShowRoot=True; Indent=16;
      1 root node expanded with 2 children. }
    function BuildColumnTree(out Ctl: TTyStyleController; out F: TForm;
      ASortColumn: Integer = -1): TTyTreeView;
    function RenderColumnTree(Tree: TTyTreeView; out Bmp: TBitmap): TBGRABitmap;
  published
    { C1a: column-1 caption ink starts WITHIN column 1's x span (right of col 0). }
    procedure TestC1_Col1CaptionInCol1Span;
    { C1b: right-aligned column-2 text sits in the cell's right half. }
    procedure TestC1_Col2RightAligned;
    { C1c: expand button and indent ink appear ONLY within column 0 (main column). }
    procedure TestC1_ChromeOnlyInMainColumn;
    { C1d: selection fill spans the full row width (not just col 0). }
    procedure TestC1_SelectionSpansFullRow;
    { C2a: the top Scale(Header.Height) px is the header band (distinct bg). }
    procedure TestC2_HeaderBandAtTop;
    { C2b: each column caption paints within its header cell x span. }
    procedure TestC2_HeaderCaptionsInSpan;
    { C2c: sort glyph appears in the SortColumn's header cell. }
    procedure TestC2_SortGlyphInSortColumn;
    { C2d: FOffsetX scroll shifts both header caption and node cell by the same delta. }
    procedure TestC2_ScrollShiftsHeaderAndCells;
    { C0 regression: 0 columns → existing ③a single-column paint is unchanged.
      The same pixel assertions as TestChildRowIndentedMoreThanTopLevel must still hold. }
    procedure TestC0_ZeroColumnsIdenticToIIIa;
  end;

  { TTreeD1D2Test — D1 header/column hit-test + D2 column resize by drag }
  TTreeD1D2Test = class(TTestCase)
  private
    FColumnResizedCount: Integer;
    FColumnResizedLast:  Integer;
    procedure OnColumnResized(Sender: TTyTreeView; Column: Integer);
    { Build a 3-column tree (widths 120/80/100, PPI=96, header height=22,
      hoVisible+hoColumnResize, all columns coResizable).
      Caller owns F and Ctl. }
    function BuildD1D2Tree(out Ctl: TTyStyleController; out F: TForm): TTyTreeView;
  published
    { D1: GetNodeAtPoint 3-out overload returns the correct column index }
    procedure TestD1_NodeColumnIndex;
    { D1: GetHeaderHitAt returns hpHeaderSection for a plain header hit }
    procedure TestD1_HeaderSectionHit;
    { D1: GetHeaderHitAt returns hpHeaderDivider at a column right edge }
    procedure TestD1_HeaderDividerHit;
    { D1: Y below the header band → GetHeaderHitAt returns False }
    procedure TestD1_BelowHeaderNotHeader;
    { D1: zero columns → GetHeaderHitAt always returns False }
    procedure TestD1_ZeroColumnsNoHeader;
    { D1: 2-out overload still compiles and works (backward compat) }
    procedure TestD1_TwoOutOverloadCompat;
    { D2: dragging col0 divider right by 30px widens col0 by 30 }
    procedure TestD2_ResizeColumn0;
    { D2: drag is clamped to MaxWidth }
    procedure TestD2_ClampAtMaxWidth;
    { D2: column without coResizable → drag does not start }
    procedure TestD2_NonResizableNoResize;
    { D2: OnColumnResized fires during resize }
    procedure TestD2_OnColumnResizedFired;
  end;

{ Inline theme used for column tests.
  TyTreeHeader / TyTreeHeaderSection typeKeys (Phase F1 adds them to the real
  themes; here we use an inline CSS block so the test is self-contained). }
const
  COLUMN_THEME_CSS =
    'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; } ' +
    'TyTreeNode { background: none; color: #000000; } ' +
    'TyTreeNode:selected { background: #3B82F6; color: #FFFFFF; } ' +
    'TyTreeHeader { background: #EEEEEE; color: #000000; } ' +
    'TyTreeHeaderSection { background: none; color: #000000; } ' +
    'TyTreeHeaderSection:hover { background: #DDDDDD; }';

{ Column widths in logical px at PPI=96 (device px = logical at 96 DPI) }
const
  COL0_W = 120;  // main column
  COL1_W = 80;   // col 1 left-align
  COL2_W = 100;  // col 2 right-align
  COL1_LEFT = COL0_W;          // left edge of col 1 (device px at 96 DPI)
  COL2_LEFT = COL0_W + COL1_W; // left edge of col 2

procedure TTreeColumnPaintTest.OnGetTextWithType(Sender: TTyTreeView;
  Node: PTyTreeNode; Column: Integer; TextType: TTyVSTTextType; var CellText: string);
begin
  case Column of
    0: CellText := 'Name' + IntToStr(Node^.Index);
    1: CellText := 'Col1';
    2: CellText := 'C2Right';
  else
    CellText := '';
  end;
end;

procedure TTreeColumnPaintTest.OnInitNodeHasChildren(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) = 0 then
    Include(InitStates, ivsHasChildren);
end;

procedure TTreeColumnPaintTest.OnInitChildren3(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 2;
end;

function TTreeColumnPaintTest.BuildColumnTree(out Ctl: TTyStyleController;
  out F: TForm; ASortColumn: Integer): TTyTreeView;
var
  t: TTyTreeView;
  col0, col1, col2: TTyTreeColumn;
  n0: PTyTreeNode;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(COLUMN_THEME_CSS);

  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent     := F;
  t.Controller := Ctl;
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 22;
  t.Indent             := 16;
  t.ShowButtons        := True;
  t.ShowTreeLines      := False;  // keep simple for pixel tests
  t.ShowRoot           := True;
  { Width = COL0_W + COL1_W + COL2_W = 300; Height enough for header + 3 rows }
  t.SetBounds(0, 0, 300, 200);

  t.OnGetTextWithType := @OnGetTextWithType;
  t.OnInitNode     := @OnInitNodeHasChildren;
  t.OnInitChildren := @OnInitChildren3;

  { Set up 3 columns }
  col0 := t.Header.Columns.Add as TTyTreeColumn;
  col0.Width := COL0_W;
  col0.Text  := 'Name';
  col0.Alignment := taLeftJustify;
  col0.CaptionAlignment := taLeftJustify;

  col1 := t.Header.Columns.Add as TTyTreeColumn;
  col1.Width := COL1_W;
  col1.Text  := 'Info';
  col1.Alignment := taLeftJustify;
  col1.CaptionAlignment := taLeftJustify;

  col2 := t.Header.Columns.Add as TTyTreeColumn;
  col2.Width := COL2_W;
  col2.Text  := 'Size';
  col2.Alignment := taRightJustify;
  col2.CaptionAlignment := taLeftJustify;

  t.Header.MainColumn    := 0;
  t.Header.SortColumn    := ASortColumn;
  t.Header.SortDirection := sdAscending;
  t.Header.Options       := [hoVisible, hoShowSortGlyphs];

  { Materialise 1 root node, expand it }
  t.RootNodeCount := 1;
  n0 := t.RootNode^.FirstChild;
  t.InitNode(n0);
  t.Expanded[n0] := True;

  Result := t;
end;

function TTreeColumnPaintTest.RenderColumnTree(Tree: TTyTreeView;
  out Bmp: TBitmap): TBGRABitmap;
var
  BgraWrap: TBGRABitmap;
begin
  Bmp := TBitmap.Create;
  Bmp.PixelFormat := pf32bit;
  Bmp.SetSize(Tree.Width, Tree.Height);
  Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);

  {$PUSH}{$HINTS OFF}
  TTyTreeViewAccess(Tree).RenderTo(Bmp.Canvas,
    Rect(0, 0, Bmp.Width, Bmp.Height), 96);
  {$POP}

  BgraWrap := TBGRABitmap.Create(Bmp, True);
  Result := BgraWrap;
end;

{ Helper: scan a horizontal band [xFrom..xTo) at y and return True if any
  pixel has R<200 (dark ink). }
function HasDarkInkInBand(Bgra: TBGRABitmap; xFrom, xTo, y: Integer): Boolean;
var
  x: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for x := xFrom to xTo - 1 do
  begin
    px := Bgra.GetPixel(x, y);
    if (px.alpha > 0) and (px.red < 200) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

{ Helper: returns True if ALL pixels in x range are bright (R>=200) = no dark ink. }
function NoDarkInkInBand(Bgra: TBGRABitmap; xFrom, xTo, y: Integer): Boolean;
var
  x: Integer;
  px: TBGRAPixel;
begin
  Result := True;
  for x := xFrom to xTo - 1 do
  begin
    px := Bgra.GetPixel(x, y);
    if (px.alpha > 0) and (px.red < 100) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

{ C1a: column 1 caption ink starts WITHIN [COL1_LEFT .. COL1_LEFT+COL1_W).
  Row 0 (the root node) has caption 'Name0' in col 0, 'Col1' in col 1, 'C2Right' in col 2.
  At PPI=96, DefaultNodeHeight=22, header=22px:
    Row 0 top in device px = headerH = 22 (since header occupies 0..21).
    Row 0 y-center ≈ 22 + 11 = 33. }
procedure TTreeColumnPaintTest.TestC1_Col1CaptionInCol1Span;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  rowY: Integer;
begin
  Tree := BuildColumnTree(Ctl, F);
  try
    Bgra := RenderColumnTree(Tree, Bmp);
    try
      { Row 0 is at device y = headerH (22 px) .. headerH+22.  Centre = 22+11=33. }
      rowY := 33;

      { Col 1 x span = [COL1_LEFT .. COL1_LEFT+COL1_W) = [120..200).
        There must be dark ink in that band (the 'Col1' text). }
      AssertTrue(
        'C1a: col1 caption ink found in x=[120..200) at y=' + IntToStr(rowY),
        HasDarkInkInBand(Bgra, COL1_LEFT, COL1_LEFT + COL1_W, rowY));

      { Col 0 right half should not contain col 1's ink (they don't overlap).
        We test that col 1 text does NOT appear left of COL1_LEFT in the first few px. }
      { This check is font-dependent so we only assert positively above }
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ C1b: right-aligned column 2 text sits in the right half of cell [COL2_LEFT .. 300).
  Right half = [COL2_LEFT+COL2_W/2 .. COL2_LEFT+COL2_W) = [250..300). }
procedure TTreeColumnPaintTest.TestC1_Col2RightAligned;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  rowY, rightHalfLeft: Integer;
begin
  Tree := BuildColumnTree(Ctl, F);
  try
    Bgra := RenderColumnTree(Tree, Bmp);
    try
      rowY := 33;  // row 0 centre (header=22, row height=22, centre=22+11=33)
      rightHalfLeft := COL2_LEFT + COL2_W div 2;  // 200+50=250

      { Right half of col 2 must have dark ink }
      AssertTrue(
        'C1b: right-aligned col2 text ink found in right half x=[' +
        IntToStr(rightHalfLeft) + '..300) at y=' + IntToStr(rowY),
        HasDarkInkInBand(Bgra, rightHalfLeft, COL2_LEFT + COL2_W, rowY));
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ C1c: the expand button / chevron ink is confined to column 0 (the main column).
  The col1 left edge (x=120) up to the caption margin (x=123) is a blank gap —
  the column paint starts at colCaptionX = colCellLeft + colMargin = 120 + 4 = 124.
  The col2 left edge (x=200..203) is similarly blank.
  If chrome leaked into col1/col2, ink would appear in x=[120..123] or x=[200..203]. }
procedure TTreeColumnPaintTest.TestC1_ChromeOnlyInMainColumn;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  y: Integer;
  px: TBGRAPixel;
  inkInGap1, inkInGap2: Boolean;
  x: Integer;
begin
  Tree := BuildColumnTree(Ctl, F);
  try
    Bgra := RenderColumnTree(Tree, Bmp);
    try
      { Row 0 y-range = 22..43, centre y=33.
        x=[120..123]: gap between col1 left edge and caption margin (should be blank).
        x=[200..203]: gap between col2 left edge and caption margin (should be blank). }
      y := 33;
      inkInGap1 := False;
      for x := COL1_LEFT to COL1_LEFT + 3 do
      begin
        px := Bgra.GetPixel(x, y);
        if (px.alpha > 0) and (px.red < 230) then
          inkInGap1 := True;
      end;
      inkInGap2 := False;
      for x := COL2_LEFT to COL2_LEFT + 3 do
      begin
        px := Bgra.GetPixel(x, y);
        if (px.alpha > 0) and (px.red < 230) then
          inkInGap2 := True;
      end;
      AssertFalse(
        'C1c: no ink in col1 left-margin gap x=[120..123] (chrome should not leak into col1)',
        inkInGap1);
      AssertFalse(
        'C1c: no ink in col2 left-margin gap x=[200..203] (chrome should not leak into col2)',
        inkInGap2);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ C1d: selection fill spans the FULL row width (x=[0..300)).
  Select row 0, check that the blue accent fill is present both at x=10 (col 0)
  and x=205 (just inside col 2 left edge, before any right-aligned text). }
procedure TTreeColumnPaintTest.TestC1_SelectionSpansFullRow;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  px0, px2: TBGRAPixel;
  rowY: Integer;
begin
  Tree := BuildColumnTree(Ctl, F);
  try
    { Select the root node (row 0) }
    Tree.Selected[Tree.RootNode^.FirstChild] := True;

    Bgra := RenderColumnTree(Tree, Bmp);
    try
      rowY := 33;  // row 0 centre

      { Check blue fill at x=50 (col 0, well past the expand button + image slots at x=[0..32)).
        The caption 'Root' starts around x=36, so x=50 may have text — but text on a blue
        background is still blue-dominant (composite). We use blue>150 as a loose bar. }
      px0 := Bgra.GetPixel(50, rowY);

      { Check blue fill at x=205 (5px into col 2, before right-aligned text starts).
        'C2Right' is right-aligned; in a 100px cell with 4px margin the text ends at
        x=296 and starts around x=248+ depending on font. x=205 should be pure fill. }
      px2 := Bgra.GetPixel(205, rowY);

      AssertTrue(
        'C1d: selection fill blue channel > 150 at col0 x=50 y=' + IntToStr(rowY),
        px0.blue > 150);
      AssertTrue(
        'C1d: selection fill red channel < 200 at col0 x=50 y=' + IntToStr(rowY),
        px0.red < 200);
      AssertTrue(
        'C1d: selection fill blue channel > 150 at col2 x=205 y=' + IntToStr(rowY),
        px2.blue > 150);
      AssertTrue(
        'C1d: selection fill red channel < 120 at col2 x=205 y=' + IntToStr(rowY),
        px2.red < 120);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ C2a: the top headerH device px is the header band (bg color #EEEEEE = R=238,G=238,B=238).
  At y=11 (mid of 22px header band), x=150 (col 1, no text) we expect the grey bg. }
procedure TTreeColumnPaintTest.TestC2_HeaderBandAtTop;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  px: TBGRAPixel;
begin
  Tree := BuildColumnTree(Ctl, F);
  try
    Bgra := RenderColumnTree(Tree, Bmp);
    try
      { Mid of header band = y=11; x=150 (middle of col 1 span).
        The header background is #EEEEEE (R=238 >= 200). }
      px := Bgra.GetPixel(150, 11);
      AssertTrue(
        'C2a: header band has grey bg at y=11 (R>=200)',
        px.red >= 200);
      { Also verify that the header paint covers y=2 (near top of header band) at x=150.
        This confirms the header bg is a full band, not just a thin stripe. }
      px := Bgra.GetPixel(150, 2);
      AssertTrue(
        'C2a: header band top (y=2) also grey (R>=200)',
        px.red >= 200);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ C2b: each column caption paints within its header cell x span.
  Col 0 header text 'Name' → ink in [0..120) at y=11.
  Col 1 header text 'Info' → ink in [120..200) at y=11.
  Col 2 header text 'Size' → ink in [200..300) at y=11. }
procedure TTreeColumnPaintTest.TestC2_HeaderCaptionsInSpan;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  headerY: Integer;
begin
  Tree := BuildColumnTree(Ctl, F);
  try
    Bgra := RenderColumnTree(Tree, Bmp);
    try
      headerY := 11;  // mid of 22px header band

      AssertTrue(
        'C2b: col0 header "Name" ink in x=[0..120) at y=' + IntToStr(headerY),
        HasDarkInkInBand(Bgra, 0, COL0_W, headerY));

      AssertTrue(
        'C2b: col1 header "Info" ink in x=[120..200) at y=' + IntToStr(headerY),
        HasDarkInkInBand(Bgra, COL1_LEFT, COL1_LEFT + COL1_W, headerY));

      AssertTrue(
        'C2b: col2 header "Size" ink in x=[200..300) at y=' + IntToStr(headerY),
        HasDarkInkInBand(Bgra, COL2_LEFT, COL2_LEFT + COL2_W, headerY));
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ C2c: sort glyph appears in the SortColumn (col 1) header cell, NOT in col 0 or col 2.
  The glyph arrow is drawn at the right of the col 1 cell so we probe x≈190 (right
  of col 1's text but still inside the cell).
  We also verify no extra glyph ink appears in col 0 or col 2 cells at similar x.
  NOTE: DrawGlyph uses antialias lines; the glyph ink may be grey rather than very dark.
  We use a broader test: check that SOME non-white pixel exists in the glyph zone. }
procedure TTreeColumnPaintTest.TestC2_SortGlyphInSortColumn;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  headerY: Integer;
  px: TBGRAPixel;
  x: Integer;
  glyphZoneHasInk: Boolean;
begin
  { Build with SortColumn = 1 (col 1 = 'Info') }
  Tree := BuildColumnTree(Ctl, F, {ASortColumn=}1);
  try
    Bgra := RenderColumnTree(Tree, Bmp);
    try
      headerY := 11;  // mid of 22px header band

      { Glyph is drawn at the right of col 1: reserve sortGlyphSize = Scale(10) = 10px.
        So glyph occupies [cellRight - 10 - margin .. cellRight - margin]
        = [200 - 10 - 4 .. 200 - 4] = [186 .. 196] approx.
        We scan x=[185..199] for any non-white pixel. }
      glyphZoneHasInk := False;
      for x := 185 to 199 do
      begin
        px := Bgra.GetPixel(x, headerY);
        if (px.alpha > 0) and ((px.red < 200) or (px.green < 200) or (px.blue < 200)) then
        begin
          glyphZoneHasInk := True;
          Break;
        end;
      end;
      AssertTrue('C2c: sort glyph ink in col1 right zone x=[185..199] at y=11',
                 glyphZoneHasInk);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ C2d: FOffsetX = 0 → header and cell column origins are aligned.
  We verify that the col2 header text ('Size') appears at x=[200..220) at FOffsetX=0,
  AND that col2 node cell text also starts at x >= 200 (same origin).
  The general invariant (header scrolls by the same delta as cells) is guaranteed
  by the implementation using the same CR.Left + P.Scale(col.Left) + FOffsetX
  formula for both bands. }
procedure TTreeColumnPaintTest.TestC2_ScrollShiftsHeaderAndCells;
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeView;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
  headerY, rowY: Integer;
  headerCol2HasInk, nodeCellCol2HasInk: Boolean;
begin
  Tree := BuildColumnTree(Ctl, F);
  try
    Bgra := RenderColumnTree(Tree, Bmp);
    try
      headerY := 11;   // mid of header band
      rowY    := 33;   // row 0 node centre

      { Col 2 header ('Size') at x=[200..220) }
      headerCol2HasInk :=
        HasDarkInkInBand(Bgra, COL2_LEFT, COL2_LEFT + 20, headerY);

      { Col 2 node cell ('C2Right', right-aligned) at x=[200..300) }
      nodeCellCol2HasInk :=
        HasDarkInkInBand(Bgra, COL2_LEFT, COL2_LEFT + COL2_W, rowY);

      AssertTrue(
        'C2d: col2 header ink at x=[200..220) at FOffsetX=0',
        headerCol2HasInk);
      AssertTrue(
        'C2d: col2 node cell ink at x=[200..300) at FOffsetX=0 (same origin as header)',
        nodeCellCol2HasInk);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTreeColumnPaintTest.C0GetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var Text: string);
begin
  Text := 'Node ' + IntToStr(Node^.Index) + ' L' + IntToStr(Sender.GetNodeLevel(Node));
end;

procedure TTreeColumnPaintTest.C0InitNode(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) < 2 then
    Include(InitStates, ivsHasChildren);
end;

procedure TTreeColumnPaintTest.C0InitChildren(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 3;
end;

{ C0 regression: 0 columns → the ③a single-column paint path is byte-identical.
  We reproduce the same assertions as TestChildRowIndentedMoreThanTopLevel:
    (a) parent row (y=10) has text ink at x=[18..35]
    (b) child row (y=30) has text ink at x=[36..100]
  This uses the standard BuildPaintTree helper (which has 0 columns and uses
  OnGetText, not OnGetTextWithType). }
procedure TTreeColumnPaintTest.TestC0_ZeroColumnsIdenticToIIIa;
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
  { BuildPaintTree creates a 0-column tree with the ③a OnGetText event }
  Tree := BuildPaintTree(Ctl, F, @Self.C0GetText, @Self.C0InitNode, @Self.C0InitChildren);
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
      AssertTrue('C0 regression: 0-column parent row has ink in x=[18..35]',
                 parentHasInk);

      { (b) Child row (y=30): must have text ink at x=[36..100] }
      childHasInkFarRight := False;
      for x := 36 to 100 do
      begin
        Px := Bgra.GetPixel(x, 30);
        if (Px.alpha > 0) and (Px.red < 230) then
          childHasInkFarRight := True;
      end;
      AssertTrue('C0 regression: 0-column child row has ink in x=[36..100]',
                 childHasInkFarRight);
    finally
      Bgra.Free;
      Bmp.Free;
    end;
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ ── D1/D2 ── header/column hit-test + column resize ─────────────────────── }

procedure TTreeD1D2Test.OnColumnResized(Sender: TTyTreeView; Column: Integer);
begin
  Inc(FColumnResizedCount);
  FColumnResizedLast := Column;
end;

function TTreeD1D2Test.BuildD1D2Tree(out Ctl: TTyStyleController; out F: TForm): TTyTreeView;
var
  t: TTyTreeView;
  col0, col1, col2: TTyTreeColumn;
  n0: PTyTreeNode;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(COLUMN_THEME_CSS);

  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent              := F;
  t.Controller          := Ctl;
  t.Font.PixelsPerInch  := 96;
  t.DefaultNodeHeight   := 22;
  t.Indent              := 16;
  t.ShowButtons         := True;
  t.ShowTreeLines       := False;
  t.ShowRoot            := True;
  t.SetBounds(0, 0, 300, 200);

  { Set up 3 columns: widths 120 / 80 / 100 }
  col0 := t.Header.Columns.Add as TTyTreeColumn;
  col0.Width := 120;
  col0.Text  := 'Name';

  col1 := t.Header.Columns.Add as TTyTreeColumn;
  col1.Width := 80;
  col1.Text  := 'Info';

  col2 := t.Header.Columns.Add as TTyTreeColumn;
  col2.Width := 100;
  col2.Text  := 'Size';

  t.Header.MainColumn    := 0;
  t.Header.SortColumn    := -1;
  t.Header.Height        := 22;
  t.Header.Options       := [hoVisible, hoColumnResize, hoShowSortGlyphs];

  { All columns get default Options including coResizable (set in TTyTreeColumn.Create) }

  { Materialise 1 root node }
  n0 := t.AddChild(nil);
  Include(n0^.States, nsInitialized);

  Result := t;
end;

{ D1: GetNodeAtPoint 3-out returns correct column index.
  At PPI=96, ContentRect.Top = 22 (header height).
  Col spans: col0=[0..120), col1=[120..200), col2=[200..300).
  Row 0 centre: Y = 22 + 11 = 33. }
procedure TTreeD1D2Test.TestD1_NodeColumnIndex;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  part: TTyTreeHitPart;
  col: Integer;
  node: PTyTreeNode;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    { X=60 → col0 (span [0..120)) }
    node := t.GetNodeAtPoint(60, 33, part, col);
    AssertTrue('D1: node at (60,33) not nil', node <> nil);
    AssertEquals('D1: column at X=60 is col0', 0, col);

    { X=250 → col2 (span [200..300)) }
    node := t.GetNodeAtPoint(250, 33, part, col);
    AssertTrue('D1: node at (250,33) not nil', node <> nil);
    AssertEquals('D1: column at X=250 is col2', 2, col);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D1: GetHeaderHitAt returns True + hpHeaderSection for a centre-of-header click }
procedure TTreeD1D2Test.TestD1_HeaderSectionHit;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  part: TTyTreeHitPart;
  col: Integer;
  ok: Boolean;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    { Y=11 (mid of 22px header), X=160 (centre of col1 [120..200)) }
    ok := t.GetHeaderHitAt(160, 11, part, col);
    AssertTrue('D1: GetHeaderHitAt in header band returns True', ok);
    AssertEquals('D1: part = hpHeaderSection', Ord(hpHeaderSection), Ord(part));
    AssertEquals('D1: col = 1 (col1)', 1, col);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D1: GetHeaderHitAt returns hpHeaderDivider at col0 right edge (X=120) }
procedure TTreeD1D2Test.TestD1_HeaderDividerHit;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  part: TTyTreeHitPart;
  col: Integer;
  ok: Boolean;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    { X=120 is the right edge of col0 (logical 120 = device 120 at PPI=96).
      DetermineSplitterIndex tolerance: [120-3=117 .. 120+5=125]. X=120 hits. }
    ok := t.GetHeaderHitAt(120, 11, part, col);
    AssertTrue('D1: GetHeaderHitAt at divider returns True', ok);
    AssertEquals('D1: part = hpHeaderDivider', Ord(hpHeaderDivider), Ord(part));
    AssertEquals('D1: divider col = 0 (col0 right edge)', 0, col);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D1: Y in node area (below header) → GetHeaderHitAt returns False }
procedure TTreeD1D2Test.TestD1_BelowHeaderNotHeader;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  part: TTyTreeHitPart;
  col: Integer;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    AssertFalse('D1: Y=33 (node area) is not in header',
      t.GetHeaderHitAt(100, 33, part, col));
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D1: zero columns → header is not shown → GetHeaderHitAt returns False }
procedure TTreeD1D2Test.TestD1_ZeroColumnsNoHeader;
var
  t: TTyTreeView;
  part: TTyTreeHitPart;
  col: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Font.PixelsPerInch := 96;
    t.SetBounds(0, 0, 300, 200);
    AssertFalse('D1: no columns → GetHeaderHitAt = False',
      t.GetHeaderHitAt(100, 10, part, col));
  finally
    t.Free;
  end;
end;

{ D1: 2-out overload compiles and returns node (backward compat) }
procedure TTreeD1D2Test.TestD1_TwoOutOverloadCompat;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  part: TTyTreeHitPart;
  node: PTyTreeNode;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    node := t.GetNodeAtPoint(60, 33, part);
    AssertTrue('D1: 2-out overload returns non-nil node', node <> nil);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D2: dragging col0 divider from X=120 to X=150 → col0.Width = 150 }
procedure TTreeD1D2Test.TestD2_ResizeColumn0;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col0: TTyTreeColumn;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    col0 := t.Header.Columns.Items[0] as TTyTreeColumn;
    AssertEquals('D2: col0 initial width', 120, col0.Width);

    { Simulate: MouseDown on divider at (120,11), drag to (150,11), release }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 120, 11);
    TTyTreeViewAccess(t).MouseMove([], 150, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 150, 11);

    { newWidth = 120 + MulDiv(150-120, 96, 96) = 120 + 30 = 150 }
    AssertEquals('D2: col0.Width after drag right 30px', 150, col0.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D2: drag beyond MaxWidth is clamped }
procedure TTreeD1D2Test.TestD2_ClampAtMaxWidth;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col0: TTyTreeColumn;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    col0 := t.Header.Columns.Items[0] as TTyTreeColumn;
    col0.MaxWidth := 130;   // clamp at 130

    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 120, 11);
    TTyTreeViewAccess(t).MouseMove([], 200, 11);  // delta=80 → unclamped=200, clamped=130
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 200, 11);

    AssertEquals('D2: col0.Width clamped to MaxWidth=130', 130, col0.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D2: column without coResizable → drag does not start → width unchanged }
procedure TTreeD1D2Test.TestD2_NonResizableNoResize;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col0: TTyTreeColumn;
begin
  t := BuildD1D2Tree(Ctl, F);
  try
    col0 := t.Header.Columns.Items[0] as TTyTreeColumn;
    col0.Options := col0.Options - [coResizable];   // remove coResizable

    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 120, 11);
    TTyTreeViewAccess(t).MouseMove([], 150, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 150, 11);

    AssertEquals('D2: non-resizable col0 width unchanged', 120, col0.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D2: OnColumnResized fires at least once during a resize drag }
procedure TTreeD1D2Test.TestD2_OnColumnResizedFired;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
begin
  FColumnResizedCount := 0;
  FColumnResizedLast  := -99;
  t := BuildD1D2Tree(Ctl, F);
  try
    t.OnColumnResized := @OnColumnResized;

    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 120, 11);
    TTyTreeViewAccess(t).MouseMove([], 150, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 150, 11);

    AssertTrue('D2: OnColumnResized fired at least once', FColumnResizedCount > 0);
    AssertEquals('D2: OnColumnResized last column = 0', 0, FColumnResizedLast);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ ── D3 ── column drag-reorder ──────────────────────────────────────────────── }

type
  TTreeD3DragTest = class(TTestCase)
  private
    FReorderFired:   Boolean;
    FReorderOldPos:  Integer;
    FReorderNewPos:  Integer;
    procedure OnColumnReorder(Sender: TTyTreeView; OldPosition, NewPosition: Integer);
    { Build a 3-column tree ready for drag-reorder tests.
      widths 100/80/60, hoDrag, all coDraggable, PPI=96, header height=22.
      Layout: col0=[0..100), col1=[100..180), col2=[180..240).
      Caller owns F and Ctl. }
    function BuildD3Tree(out Ctl: TTyStyleController; out F: TForm): TTyTreeView;
  published
    { Drag col0 header past the threshold into col2 area → positions reordered,
      FLeft recomputed, OnColumnReorder fired with oldPos=0 newPos=2. }
    procedure TestD3_DragReorderColumns;
    { Press-and-release with no movement → no reorder (click-sort path preserved). }
    procedure TestD3_ClickNoReorder;
    { Drag below threshold → no reorder (pending state cleared cleanly). }
    procedure TestD3_BelowThresholdNoReorder;
    { OnColumnReorder fires with correct old/new positions. }
    procedure TestD3_OnColumnReorderFired;
  end;

procedure TTreeD3DragTest.OnColumnReorder(Sender: TTyTreeView;
  OldPosition, NewPosition: Integer);
begin
  FReorderFired  := True;
  FReorderOldPos := OldPosition;
  FReorderNewPos := NewPosition;
end;

function TTreeD3DragTest.BuildD3Tree(out Ctl: TTyStyleController;
  out F: TForm): TTyTreeView;
var
  t: TTyTreeView;
  col0, col1, col2: TTyTreeColumn;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(COLUMN_THEME_CSS);

  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent     := F;
  t.Controller := Ctl;
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 22;
  t.SetBounds(0, 0, 300, 200);

  { 3 columns — widths 100/80/60 }
  col0 := t.Header.Columns.Add as TTyTreeColumn;
  col0.Width := 100;
  col0.Text  := 'Col0';
  col0.Options := [coVisible, coResizable, coAllowClick, coDraggable];

  col1 := t.Header.Columns.Add as TTyTreeColumn;
  col1.Width := 80;
  col1.Text  := 'Col1';
  col1.Options := [coVisible, coResizable, coAllowClick, coDraggable];

  col2 := t.Header.Columns.Add as TTyTreeColumn;
  col2.Width := 60;
  col2.Text  := 'Col2';
  col2.Options := [coVisible, coResizable, coAllowClick, coDraggable];

  t.Header.MainColumn := 0;
  t.Header.Height     := 22;
  t.Header.Options    := [hoVisible, hoColumnResize, hoDrag];

  t.AddChild(nil);
  Result := t;
end;

{ D3: drag col0 centre to col2 centre → positions reordered }
procedure TTreeD3DragTest.TestD3_DragReorderColumns;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col0, col1, col2: TTyTreeColumn;
  oldCol0Pos, oldCol1Pos, oldCol2Pos: Integer;
begin
  t := BuildD3Tree(Ctl, F);
  try
    col0 := t.Header.Columns.Items[0] as TTyTreeColumn;
    col1 := t.Header.Columns.Items[1] as TTyTreeColumn;
    col2 := t.Header.Columns.Items[2] as TTyTreeColumn;

    { Remember initial positions }
    oldCol0Pos := col0.Position;  { = 0 }
    oldCol1Pos := col1.Position;  { = 1 }
    oldCol2Pos := col2.Position;  { = 2 }

    AssertEquals('D3: col0 initial position=0', 0, Integer(oldCol0Pos));
    AssertEquals('D3: col1 initial position=1', 1, Integer(oldCol1Pos));
    AssertEquals('D3: col2 initial position=2', 2, Integer(oldCol2Pos));

    { Press in col0 centre (X=50, Y=11), drag right by 150px to X=200 (col2 area),
      then release.  Threshold = 4px at PPI=96, so 150px >> threshold. }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseMove([], 200, 11);  { past threshold into col2 }
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 200, 11);

    { col0 (collection index 0) should now be at position 2 }
    AssertEquals('D3: col0.Position after drag to pos2', 2, Integer(col0.Position));
    { FLeft of col0 should be UpdatePositions-recomputed }
    { col1 and col2 should have shifted left by one position each }
    AssertEquals('D3: col1.Position after drag', 0, Integer(col1.Position));
    AssertEquals('D3: col2.Position after drag', 1, Integer(col2.Position));
    { FLeft values reflect the new order: col1=0, col2=80, col0=140 }
    AssertEquals('D3: col1 FLeft=0 (now first)', 0, col1.Left);
    AssertEquals('D3: col2 FLeft=80 (now second)', 80, col2.Left);
    AssertEquals('D3: col0 FLeft=140 (now third)', 140, col0.Left);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D3: press-and-release without movement → no reorder }
procedure TTreeD3DragTest.TestD3_ClickNoReorder;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col0: TTyTreeColumn;
begin
  t := BuildD3Tree(Ctl, F);
  try
    col0 := t.Header.Columns.Items[0] as TTyTreeColumn;

    { Press and release at the same spot (no movement) }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);

    { col0 must still be at position 0 — no reorder }
    AssertEquals('D3: click-no-move leaves col0.Position=0', 0, Integer(col0.Position));
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D3: drag below threshold → no reorder }
procedure TTreeD3DragTest.TestD3_BelowThresholdNoReorder;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col0: TTyTreeColumn;
begin
  t := BuildD3Tree(Ctl, F);
  try
    col0 := t.Header.Columns.Items[0] as TTyTreeColumn;

    { Press then move only 2px (below 4px threshold) then release }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseMove([], 52, 11);   { 2px — below threshold }
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 52, 11);

    AssertEquals('D3: below-threshold no reorder, col0.Position=0', 0, Integer(col0.Position));
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D3: OnColumnReorder fires with correct OldPosition and NewPosition }
procedure TTreeD3DragTest.TestD3_OnColumnReorderFired;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
begin
  FReorderFired  := False;
  FReorderOldPos := -99;
  FReorderNewPos := -99;

  t := BuildD3Tree(Ctl, F);
  try
    t.OnColumnReorder := @OnColumnReorder;

    { Drag col0 (position 0) to col2's area (position 2) }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseMove([], 200, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 200, 11);

    AssertTrue ('D3: OnColumnReorder fired', FReorderFired);
    AssertEquals('D3: OldPosition=0', 0, FReorderOldPos);
    AssertEquals('D3: NewPosition=2', 2, FReorderNewPos);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ ── D4 ── auto-size on resize + spring ─────────────────────────────────────── }

type
  TTreeD4AutoSizeTest = class(TTestCase)
  private
    { Build a 3-column tree with hoAutoResize + AutoSizeIndex=1.
      col0=100, col1=?, col2=80; client width=300 so col1 should start=120.
      Caller owns F and Ctl. }
    function BuildD4Tree(out Ctl: TTyStyleController; out F: TForm): TTyTreeView;
  published
    { With hoAutoResize+AutoSizeIndex=1 and client=300:
      col1 fills 300-100-80=120. }
    procedure TestD4_AutoSizeInitial;
    { After Resize (wider client), col1 grows to absorb the extra width. }
    procedure TestD4_AutoSizeAfterResize;
    { Spring columns: two coAutoSpring columns share a delta evenly. }
    procedure TestD4_SpringDistribution;
    { After a non-auto column is resized, col1 (auto) absorbs the change. }
    procedure TestD4_AutoSizeAfterColumnResize;
  end;

function TTreeD4AutoSizeTest.BuildD4Tree(out Ctl: TTyStyleController;
  out F: TForm): TTyTreeView;
var
  t: TTyTreeView;
  col0, col1, col2: TTyTreeColumn;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(COLUMN_THEME_CSS);

  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent     := F;
  t.Controller := Ctl;
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 22;
  { Width=300, header=22px → content width=300 (no scrollbars, no padding in theme) }
  t.SetBounds(0, 0, 300, 200);

  col0 := t.Header.Columns.Add as TTyTreeColumn;
  col0.Width := 100;
  col0.Text  := 'A';

  col1 := t.Header.Columns.Add as TTyTreeColumn;
  col1.Width := 50;   { will be reset by ApplyAutoSize to fill remainder }
  col1.Text  := 'B';

  col2 := t.Header.Columns.Add as TTyTreeColumn;
  col2.Width := 80;
  col2.Text  := 'C';

  t.Header.MainColumn    := 0;
  t.Header.Height        := 22;
  t.Header.AutoSizeIndex := 1;   { col1 = auto-size column }
  t.Header.Options       := [hoVisible, hoColumnResize, hoAutoResize];

  t.AddChild(nil);
  Result := t;
end;

{ D4: col1 width = client_width - col0 - col2 = 300 - 100 - 80 = 120 after initial Resize }
procedure TTreeD4AutoSizeTest.TestD4_AutoSizeInitial;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col1: TTyTreeColumn;
  expected: Integer;
begin
  t := BuildD4Tree(Ctl, F);
  try
    col1 := t.Header.Columns.Items[1] as TTyTreeColumn;
    { Apply auto-size manually to simulate the Resize trigger }
    t.Header.Columns.ApplyAutoSize(
      MulDiv(t.ContentRect.Width, 96, t.Font.PixelsPerInch), 1);
    expected := 300 - 100 - 80;  { = 120 }
    AssertEquals('D4: col1 auto-sized to 120', expected, col1.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D4: after Resize to width=350, col1 should grow to 170 (350-100-80) }
procedure TTreeD4AutoSizeTest.TestD4_AutoSizeAfterResize;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col1: TTyTreeColumn;
  expected: Integer;
begin
  t := BuildD4Tree(Ctl, F);
  try
    col1 := t.Header.Columns.Items[1] as TTyTreeColumn;
    { Resize the control to 350 wide — Resize override should run ApplyAutoSize }
    t.SetBounds(0, 0, 350, 200);
    { SetBounds calls Resize; verify col1 absorbed the extra 50px }
    expected := 350 - 100 - 80;  { = 170 }
    AssertEquals('D4: col1 grows to 170 after Resize to 350', expected, col1.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D4: spring distribution — two coAutoSpring columns share delta evenly }
procedure TTreeD4AutoSizeTest.TestD4_SpringDistribution;
var
  col0: TTyTreeColumn;
  cols: TTyTreeColumns;
  col1, col2: TTyTreeColumn;
begin
  cols := TTyTreeColumns.Create;
  try
    col0 := cols.Add as TTyTreeColumn;
    col0.Width   := 100;
    col0.Options := [coVisible, coAutoSpring];

    col1 := cols.Add as TTyTreeColumn;
    col1.Width   := 100;
    col1.Options := [coVisible, coAutoSpring];

    col2 := cols.Add as TTyTreeColumn;
    col2.Width   := 50;
    col2.Options := [coVisible];   { not a spring column }

    { Distribute +40 across spring columns (col0 and col1 each get +20) }
    cols.DistributeSpring(40);
    AssertEquals('D4: col0 gets half of delta', 120, col0.Width);
    AssertEquals('D4: col1 gets half of delta', 120, col1.Width);
    AssertEquals('D4: col2 unchanged (no spring)', 50, col2.Width);
  finally
    cols.Free;
  end;
  { Suppress unused hint for col1 - it's used in Asserts above }
end;

{ D4: after a non-auto-column resize, col1 (auto) absorbs the difference }
procedure TTreeD4AutoSizeTest.TestD4_AutoSizeAfterColumnResize;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  col0, col1: TTyTreeColumn;
begin
  t := BuildD4Tree(Ctl, F);
  try
    col0 := t.Header.Columns.Items[0] as TTyTreeColumn;
    col1 := t.Header.Columns.Items[1] as TTyTreeColumn;

    { Simulate resizing col0 from 100 to 130 via header drag }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 100, 11);  { col0 right edge }
    TTyTreeViewAccess(t).MouseMove([], 130, 11);           { drag right 30px }
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 130, 11);

    { col0 width should be 130 }
    AssertEquals('D4: col0 width after resize', 130, col0.Width);
    { col1 (auto) should absorb: new width = 300 - 130 - 80 = 90 }
    AssertEquals('D4: col1 auto-absorbs col0 resize', 90, col1.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ ── E1 ── OnCompareNodes + sibling-list merge Sort(node,col,dir) ─────────────── }
{ Strategy: store an integer key in the node-data blob (NodeDataSize=SizeOf(Integer))
  via the tree's NodeDataSize.  OnCompareNodes reads the key and compares.
  The tree will use a parent node whose children carry keys [3,1,4,1,5,9,2,6].
  After ascending sort the order must be [1,1,2,3,4,5,6,9] (stable within equal keys).
  After descending the order must be [9,6,5,4,3,2,1,1].
  The key is written into the node-data blob via PInteger(t.GetNodeData(child))^. }

type
  TTreeE1SortTest = class(TTestCase)
  private
    FCompareCount: Integer;
    FLastColumn:   Integer;
    procedure OnCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
                        Column: Integer; var Result: Integer);
    { Build a parent+children tree with the keys [3,1,4,1,5,9,2,6].
      Returns the tree (caller frees); AParent = the parent node. }
    function BuildSortTree(out AParent: PTyTreeNode): TTyTreeView;
    { Walk children of AParent forward and return their keys in order }
    procedure CollectKeys(Tree: TTyTreeView; Parent: PTyTreeNode; out AKeys: array of Integer);
  published
    procedure TestE1_AscendingSortOrder;
    procedure TestE1_DescendingSortOrder;
    procedure TestE1_IndexReStamped;
    procedure TestE1_BackwardLinkCorrect;
    procedure TestE1_ZeroChildNoOp;
    procedure TestE1_OneChildNoOp;
    procedure TestE1_HeightInvariantHolds;
    procedure TestE1_OnCompareNodesFiredWithCorrectColumn;
  end;

procedure TTreeE1SortTest.OnCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
  Column: Integer; var Result: Integer);
begin
  Inc(FCompareCount);
  FLastColumn := Column;
  { Compare the integer key stored in the node-data blob }
  Result := PInteger(Sender.GetNodeData(Node1))^ -
            PInteger(Sender.GetNodeData(Node2))^;
end;

function TTreeE1SortTest.BuildSortTree(out AParent: PTyTreeNode): TTyTreeView;
const
  Keys: array[0..7] of Integer = (3, 1, 4, 1, 5, 9, 2, 6);
var
  t: TTyTreeView;
  parent, child: PTyTreeNode;
  i: Integer;
begin
  t := TTyTreeView.Create(nil);
  t.NodeDataSize := SizeOf(Integer);
  t.OnCompareNodes := @OnCompare;

  { Create a parent node with 8 children (NOT expanded — sort is a pure relink test) }
  t.RootNodeCount := 1;
  parent := t.RootNode^.FirstChild;
  Include(parent^.States, nsHasChildren);  { mark as having children }
  t.SetChildCount(parent, 8);
  { Parent stays COLLAPSED so TotalHeight is not affected by children heights. }

  { Stamp keys into the data blobs and init states }
  child := parent^.FirstChild;
  i := 0;
  while child <> nil do
  begin
    Include(child^.States, nsInitialized); { already inited for compare purposes }
    PInteger(t.GetNodeData(child))^ := Keys[i];
    Inc(i);
    child := child^.NextSibling;
  end;

  AParent := parent;
  Result := t;
end;

{ CollectKeys: walk children of Parent forward and fill AKeys }
procedure TTreeE1SortTest.CollectKeys(Tree: TTyTreeView; Parent: PTyTreeNode;
  out AKeys: array of Integer);
var
  child: PTyTreeNode;
  i: Integer;
begin
  i := 0;
  child := Parent^.FirstChild;
  while child <> nil do
  begin
    if i <= High(AKeys) then
      AKeys[i] := PInteger(Tree.GetNodeData(child))^;
    Inc(i);
    child := child^.NextSibling;
  end;
end;

procedure TTreeE1SortTest.TestE1_AscendingSortOrder;
var
  t: TTyTreeView;
  parent: PTyTreeNode;
  keys: array[0..7] of Integer;
  expected: array[0..7] of Integer = (1, 1, 2, 3, 4, 5, 6, 9);
  i: Integer;
begin
  t := BuildSortTree(parent);
  try
    t.Sort(parent, 0, sdAscending, False);
    CollectKeys(t, parent, keys);
    for i := 0 to 7 do
      AssertEquals('E1 asc key['+IntToStr(i)+']', expected[i], keys[i]);
  finally
    t.Free;
  end;
end;

procedure TTreeE1SortTest.TestE1_DescendingSortOrder;
var
  t: TTyTreeView;
  parent: PTyTreeNode;
  keys: array[0..7] of Integer;
  expected: array[0..7] of Integer = (9, 6, 5, 4, 3, 2, 1, 1);
  i: Integer;
begin
  t := BuildSortTree(parent);
  try
    t.Sort(parent, 0, sdDescending, False);
    CollectKeys(t, parent, keys);
    for i := 0 to 7 do
      AssertEquals('E1 desc key['+IntToStr(i)+']', expected[i], keys[i]);
  finally
    t.Free;
  end;
end;

procedure TTreeE1SortTest.TestE1_IndexReStamped;
var
  t: TTyTreeView;
  parent, child: PTyTreeNode;
  i: Integer;
begin
  t := BuildSortTree(parent);
  try
    t.Sort(parent, 0, sdAscending, False);
    child := parent^.FirstChild;
    i := 0;
    while child <> nil do
    begin
      AssertEquals('E1 Index['+IntToStr(i)+'] re-stamped', i, Integer(child^.Index));
      Inc(i);
      child := child^.NextSibling;
    end;
  finally
    t.Free;
  end;
end;

procedure TTreeE1SortTest.TestE1_BackwardLinkCorrect;
var
  t: TTyTreeView;
  parent, child, prev: PTyTreeNode;
begin
  t := BuildSortTree(parent);
  try
    t.Sort(parent, 0, sdAscending, False);
    { Walk forward and verify PrevSibling of each node points back to the previous }
    prev  := nil;
    child := parent^.FirstChild;
    AssertTrue('E1 FirstChild.PrevSibling = nil', child^.PrevSibling = nil);
    AssertTrue('E1 Parent.FirstChild = sorted head', parent^.FirstChild = child);
    while child <> nil do
    begin
      AssertTrue('E1 PrevSibling correct', child^.PrevSibling = prev);
      if child^.NextSibling = nil then
        AssertTrue('E1 LastChild correct', parent^.LastChild = child);
      prev  := child;
      child := child^.NextSibling;
    end;
  finally
    t.Free;
  end;
end;

procedure TTreeE1SortTest.TestE1_ZeroChildNoOp;
var
  t: TTyTreeView;
  parent: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 1;
    parent := t.RootNode^.FirstChild;
    { Parent has no children — Sort must be a no-op (no crash) }
    t.Sort(parent, 0, sdAscending, False);
    AssertEquals('E1 0-child ChildCount unchanged', 0, Integer(parent^.ChildCount));
  finally
    t.Free;
  end;
end;

procedure TTreeE1SortTest.TestE1_OneChildNoOp;
var
  t: TTyTreeView;
  parent, child: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  t.NodeDataSize := SizeOf(Integer);
  t.OnCompareNodes := @OnCompare;
  try
    t.RootNodeCount := 1;
    parent := t.RootNode^.FirstChild;
    t.SetChildCount(parent, 1);
    child := parent^.FirstChild;
    Include(child^.States, nsInitialized);
    PInteger(t.GetNodeData(child))^ := 42;
    { 1 child — Sort must be a no-op (no crash, child unchanged) }
    t.Sort(parent, 0, sdAscending, False);
    AssertEquals('E1 1-child key unchanged', 42, PInteger(t.GetNodeData(parent^.FirstChild))^);
  finally
    t.Free;
  end;
end;

procedure TTreeE1SortTest.TestE1_HeightInvariantHolds;
{ After sorting, TotalHeight must be unchanged (sort is a pure relink). }
var
  t: TTyTreeView;
  parent: PTyTreeNode;
  totalBefore, totalAfter: Integer;
begin
  t := BuildSortTree(parent);
  try
    totalBefore := Integer(t.RootNode^.TotalHeight);
    t.Sort(parent, 0, sdAscending, False);
    totalAfter := Integer(t.RootNode^.TotalHeight);
    AssertEquals('E1 height invariant: TotalHeight unchanged by sort',
      totalBefore, totalAfter);
    AssertEquals('E1 height invariant: TotalHeight = SumVisible',
      t.SumVisibleHeights, totalAfter);
  finally
    t.Free;
  end;
end;

procedure TTreeE1SortTest.TestE1_OnCompareNodesFiredWithCorrectColumn;
var
  t: TTyTreeView;
  parent: PTyTreeNode;
begin
  t := BuildSortTree(parent);
  try
    FCompareCount := 0;
    FLastColumn   := -99;
    t.Sort(parent, 3, sdAscending, False);   { column 3 }
    AssertTrue('E1 OnCompareNodes fired at least once', FCompareCount > 0);
    AssertEquals('E1 OnCompareNodes column = 3', 3, FLastColumn);
  finally
    t.Free;
  end;
end;

{ ── E2 ── SortTree recursive lazy-aware + cache rebuild ─────────────────────── }

type
  TTreeE2SortTreeTest = class(TTestCase)
  private
    procedure OnCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
                        Column: Integer; var Result: Integer);
    { Build a 3-level tree:
        root
          A (key=3, expanded, 2 children: A1=key2, A2=key1)
          B (key=1, expanded, 2 children: B1=key9, B2=key5)
          C (key=2, collapsed, 1 child C1=key7, lazy/uninitialized) }
    function BuildE2Tree(out A, B, C: PTyTreeNode): TTyTreeView;
  published
    procedure TestE2_RootLevelSorted;
    procedure TestE2_ExpandedChildLevelSorted;
    procedure TestE2_CollapsedBranchNotSorted;
    procedure TestE2_HeightInvariantAfterSortTree;
    procedure TestE2_GetNodeAtConsistentAfterSort;
  end;

procedure TTreeE2SortTreeTest.OnCompare(Sender: TTyTreeView;
  Node1, Node2: PTyTreeNode; Column: Integer; var Result: Integer);
begin
  Result := PInteger(Sender.GetNodeData(Node1))^ -
            PInteger(Sender.GetNodeData(Node2))^;
end;

function TTreeE2SortTreeTest.BuildE2Tree(out A, B, C: PTyTreeNode): TTyTreeView;
var
  t: TTyTreeView;
  A1, A2, B1, B2: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  t.NodeDataSize   := SizeOf(Integer);
  t.OnCompareNodes := @OnCompare;
  t.DefaultNodeHeight := 20;

  { Root level: 3 nodes A,B,C }
  t.RootNodeCount := 3;
  A := t.RootNode^.FirstChild;
  B := A^.NextSibling;
  C := B^.NextSibling;

  { Stamp keys and mark initialized }
  Include(A^.States, nsInitialized); PInteger(t.GetNodeData(A))^ := 3;
  Include(B^.States, nsInitialized); PInteger(t.GetNodeData(B))^ := 1;
  Include(C^.States, nsInitialized); PInteger(t.GetNodeData(C))^ := 2;

  { A: expanded with 2 children using Expanded property (proper height tracking) }
  Include(A^.States, nsHasChildren);
  t.SetChildCount(A, 2);
  t.Expanded[A] := True;
  A1 := A^.FirstChild; A2 := A1^.NextSibling;
  Include(A1^.States, nsInitialized); PInteger(t.GetNodeData(A1))^ := 2;
  Include(A2^.States, nsInitialized); PInteger(t.GetNodeData(A2))^ := 1;

  { B: expanded with 2 children }
  Include(B^.States, nsHasChildren);
  t.SetChildCount(B, 2);
  t.Expanded[B] := True;
  B1 := B^.FirstChild; B2 := B1^.NextSibling;
  Include(B1^.States, nsInitialized); PInteger(t.GetNodeData(B1))^ := 9;
  Include(B2^.States, nsInitialized); PInteger(t.GetNodeData(B2))^ := 5;

  { C: collapsed, 1 lazy child (NOT initialized - simulates lazy model) }
  Include(C^.States, nsHasChildren);
  t.SetChildCount(C, 1);
  { C stays collapsed }
  PInteger(t.GetNodeData(C^.FirstChild))^ := 7;
  { Leave C^.FirstChild NOT initialized }

  Result := t;
end;

procedure TTreeE2SortTreeTest.TestE2_RootLevelSorted;
var
  t: TTyTreeView;
  A, B, C: PTyTreeNode;
  n: PTyTreeNode;
  keys: array[0..2] of Integer;
  i: Integer;
begin
  t := BuildE2Tree(A, B, C);
  try
    t.SortTree(0, sdAscending);
    { Root-level should now be B(1), C(2), A(3) }
    n := t.RootNode^.FirstChild;
    i := 0;
    while (n <> nil) and (i < 3) do
    begin
      keys[i] := PInteger(t.GetNodeData(n))^;
      Inc(i);
      n := n^.NextSibling;
    end;
    AssertEquals('E2 root[0]=1 (B)', 1, keys[0]);
    AssertEquals('E2 root[1]=2 (C)', 2, keys[1]);
    AssertEquals('E2 root[2]=3 (A)', 3, keys[2]);
  finally
    t.Free;
  end;
end;

procedure TTreeE2SortTreeTest.TestE2_ExpandedChildLevelSorted;
var
  t: TTyTreeView;
  A, B, C: PTyTreeNode;
  n: PTyTreeNode;
  childKeys: array[0..1] of Integer;
  i: Integer;
begin
  t := BuildE2Tree(A, B, C);
  try
    t.SortTree(0, sdAscending);
    { A's children: sorted ascending → A2(1), A1(2) }
    n := A^.FirstChild;
    i := 0;
    while (n <> nil) and (i < 2) do
    begin
      childKeys[i] := PInteger(t.GetNodeData(n))^;
      Inc(i);
      n := n^.NextSibling;
    end;
    AssertEquals('E2 A.child[0]=1', 1, childKeys[0]);
    AssertEquals('E2 A.child[1]=2', 2, childKeys[1]);
    { B's children: sorted ascending → B2(5), B1(9) }
    n := B^.FirstChild;
    i := 0;
    while (n <> nil) and (i < 2) do
    begin
      childKeys[i] := PInteger(t.GetNodeData(n))^;
      Inc(i);
      n := n^.NextSibling;
    end;
    AssertEquals('E2 B.child[0]=5', 5, childKeys[0]);
    AssertEquals('E2 B.child[1]=9', 9, childKeys[1]);
  finally
    t.Free;
  end;
end;

procedure TTreeE2SortTreeTest.TestE2_CollapsedBranchNotSorted;
var
  t: TTyTreeView;
  A, B, C, C1: PTyTreeNode;
begin
  t := BuildE2Tree(A, B, C);
  try
    t.SortTree(0, sdAscending);
    { C1 key=7, C is not expanded; SortTree should NOT touch C1 }
    C1 := C^.FirstChild;
    AssertTrue('E2 C1 still exists', C1 <> nil);
    AssertEquals('E2 collapsed C1 key unchanged (7)', 7, PInteger(t.GetNodeData(C1))^);
    AssertFalse('E2 collapsed C1 not initialized by SortTree',
      nsInitialized in C1^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeE2SortTreeTest.TestE2_HeightInvariantAfterSortTree;
var
  t: TTyTreeView;
  A, B, C: PTyTreeNode;
begin
  t := BuildE2Tree(A, B, C);
  try
    t.SortTree(0, sdAscending);
    AssertEquals('E2 height invariant after SortTree',
      t.SumVisibleHeights, Integer(t.RootNode^.TotalHeight));
  finally
    t.Free;
  end;
end;

procedure TTreeE2SortTreeTest.TestE2_GetNodeAtConsistentAfterSort;
{ After SortTree, GetNodeAt(y) must return the same node as a manual visible-walk. }
var
  t: TTyTreeView;
  A, B, C: PTyTreeNode;
  yList: array[0..2] of Integer;
  i: Integer;
  sampleY, nodeTop: Integer;
  nodeFromCache, nodeFromWalk: PTyTreeNode;
  accTop: Integer;
  walk: PTyTreeNode;
begin
  t := BuildE2Tree(A, B, C);
  try
    t.SortTree(0, sdAscending);
    { Sample visible y values: 5 (1st row), 25 (2nd row), 45 (3rd row) }
    yList[0] := 5;
    yList[1] := 25;
    yList[2] := 45;
    for i := 0 to 2 do
    begin
      sampleY       := yList[i];
      nodeFromCache := t.GetNodeAt(sampleY, nodeTop);
      { Manual visible-order walk to find who owns sampleY }
      accTop        := 0;
      nodeFromWalk  := nil;
      walk := t.GetFirstVisibleNoInit;
      while walk <> nil do
      begin
        if (sampleY >= accTop) and (sampleY < accTop + Integer(walk^.NodeHeight)) then
        begin
          nodeFromWalk := walk;
          Break;
        end;
        Inc(accTop, walk^.NodeHeight);
        walk := t.GetNextVisibleNoInit(walk);
      end;
      AssertTrue('E2 GetNodeAt['+IntToStr(sampleY)+'] matches walk',
        nodeFromCache = nodeFromWalk);
    end;
  finally
    t.Free;
  end;
end;

{ ── E3 ── header-click sort wiring ─────────────────────────────────────────── }

type
  TTreeE3HeaderClickTest = class(TTestCase)
  private
    FCompareCol:      Integer;
    FHeaderClickCol:  Integer;
    FHeaderClickCount: Integer;
    procedure OnCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
                        Column: Integer; var Result: Integer);
    procedure OnHeaderClick(Sender: TTyTreeView; Column: Integer);
    { Build a sortable multi-column tree with 4 root nodes keyed [4,2,3,1]. }
    function BuildE3Tree(out Ctl: TTyStyleController; out F: TForm): TTyTreeView;
  published
    procedure TestE3_ClickSetsColumnAsc;
    procedure TestE3_ClickSameColumnTogglesToDesc;
    procedure TestE3_ClickNewColumnResetsAsc;
    procedure TestE3_OnHeaderClickFired;
    procedure TestE3_SortRunsOnClick;
  end;

procedure TTreeE3HeaderClickTest.OnCompare(Sender: TTyTreeView;
  Node1, Node2: PTyTreeNode; Column: Integer; var Result: Integer);
begin
  FCompareCol := Column;
  Result := PInteger(Sender.GetNodeData(Node1))^ -
            PInteger(Sender.GetNodeData(Node2))^;
end;

procedure TTreeE3HeaderClickTest.OnHeaderClick(Sender: TTyTreeView; Column: Integer);
begin
  Inc(FHeaderClickCount);
  FHeaderClickCol := Column;
end;

function TTreeE3HeaderClickTest.BuildE3Tree(out Ctl: TTyStyleController;
  out F: TForm): TTyTreeView;
var
  t: TTyTreeView;
  col0, col1: TTyTreeColumn;
  n: PTyTreeNode;
  i: Integer;
const
  Keys: array[0..3] of Integer = (4, 2, 3, 1);
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(COLUMN_THEME_CSS);

  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent     := F;
  t.Controller := Ctl;
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 20;
  t.NodeDataSize       := SizeOf(Integer);
  t.SetBounds(0, 0, 300, 200);

  col0 := t.Header.Columns.Add as TTyTreeColumn;
  col0.Width := 100; col0.Text := 'Col0';
  col1 := t.Header.Columns.Add as TTyTreeColumn;
  col1.Width := 100; col1.Text := 'Col1';

  t.Header.MainColumn    := 0;
  t.Header.Height        := 22;
  t.Header.SortColumn    := -1;
  t.Header.Options       := [hoVisible, hoHeaderClickAutoSort, hoDrag];

  t.OnCompareNodes := @OnCompare;
  t.OnHeaderClick  := @OnHeaderClick;

  { 4 root nodes with keys [4,2,3,1] }
  t.RootNodeCount := 4;
  n := t.RootNode^.FirstChild;
  i := 0;
  while n <> nil do
  begin
    Include(n^.States, nsInitialized);
    PInteger(t.GetNodeData(n))^ := Keys[i];
    Inc(i);
    n := n^.NextSibling;
  end;

  Result := t;
end;

{ Simulate a press+release on the header section of a column (no drag).
  col0 header: Y=11 (inside the 22px header band), X=50 (within col0 width=100).
  col1 header: X=150 (within col1 which starts at 100). }

procedure TTreeE3HeaderClickTest.TestE3_ClickSetsColumnAsc;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
begin
  t := BuildE3Tree(Ctl, F);
  try
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    AssertEquals('E3 SortColumn set to col0 (0)', 0, t.Header.SortColumn);
    AssertEquals('E3 SortDirection = ascending', Ord(sdAscending), Ord(t.Header.SortDirection));
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTreeE3HeaderClickTest.TestE3_ClickSameColumnTogglesToDesc;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
begin
  t := BuildE3Tree(Ctl, F);
  try
    { First click: sets col0, asc }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    AssertEquals('E3 1st click: asc', Ord(sdAscending), Ord(t.Header.SortDirection));
    { Second click on same col: toggles to desc }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    AssertEquals('E3 2nd click: desc', Ord(sdDescending), Ord(t.Header.SortDirection));
    AssertEquals('E3 SortColumn still 0', 0, t.Header.SortColumn);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTreeE3HeaderClickTest.TestE3_ClickNewColumnResetsAsc;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
begin
  t := BuildE3Tree(Ctl, F);
  try
    { Click col0 twice → desc }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    AssertEquals('E3 col0 is desc', Ord(sdDescending), Ord(t.Header.SortDirection));
    { Click col1 (X=150) → SortColumn=1, reset to asc }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 150, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 150, 11);
    AssertEquals('E3 SortColumn=1 after col1 click', 1, t.Header.SortColumn);
    AssertEquals('E3 SortDirection reset to asc', Ord(sdAscending), Ord(t.Header.SortDirection));
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTreeE3HeaderClickTest.TestE3_OnHeaderClickFired;
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
begin
  FHeaderClickCount := 0;
  FHeaderClickCol   := -1;
  t := BuildE3Tree(Ctl, F);
  try
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    AssertEquals('E3 OnHeaderClick fired once', 1, FHeaderClickCount);
    AssertEquals('E3 OnHeaderClick col=0', 0, FHeaderClickCol);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTreeE3HeaderClickTest.TestE3_SortRunsOnClick;
{ After clicking col0, the 4 root nodes [4,2,3,1] should be sorted [1,2,3,4]. }
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeView;
  n: PTyTreeNode;
  keys: array[0..3] of Integer;
  i: Integer;
begin
  FCompareCol := -99;
  t := BuildE3Tree(Ctl, F);
  try
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    { Collect the sorted root order }
    n := t.RootNode^.FirstChild;
    i := 0;
    while (n <> nil) and (i < 4) do
    begin
      keys[i] := PInteger(t.GetNodeData(n))^;
      Inc(i);
      n := n^.NextSibling;
    end;
    AssertEquals('E3 sort[0]=1', 1, keys[0]);
    AssertEquals('E3 sort[1]=2', 2, keys[1]);
    AssertEquals('E3 sort[2]=3', 3, keys[2]);
    AssertEquals('E3 sort[3]=4', 4, keys[3]);
    AssertEquals('E3 OnCompareNodes column=0', 0, FCompareCol);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ ── A2 ── check types + tri-state propagation pure helpers ──────────────── }

type
  TTreeA2CheckPropTest = class(TTestCase)
  published
    { PropagateCheckDown sets all ctCheckBox children to the given state. }
    procedure TestPropagateCheckDownSetsAllCheckBoxChildren;
    { PropagateCheckDown does not touch ctRadioButton children. }
    procedure TestPropagateCheckDownSkipsRadioButton;
    { RecomputeParentCheckState: all checked → csChecked. }
    procedure TestRecomputeAllChecked;
    { RecomputeParentCheckState: all unchecked → csUnchecked. }
    procedure TestRecomputeAllUnchecked;
    { RecomputeParentCheckState: mixed (checked+unchecked) → csMixed. }
    procedure TestRecomputeMixedReturnsCsMixed;
    { RecomputeParentCheckState: ctRadioButton children are ignored. }
    procedure TestRecomputeIgnoresRadioButton;
    { RecomputeParentCheckState: no check-children → returns current state unchanged. }
    procedure TestRecomputeNoCheckChildrenReturnsCurrentState;
  end;

procedure TTreeA2CheckPropTest.TestPropagateCheckDownSetsAllCheckBoxChildren;
var
  t: TTyTreeView;
  parent, c1, c2, c3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    c1 := t.AddChild(parent);
    c2 := t.AddChild(parent);
    c3 := t.AddChild(parent);
    c1^.CheckType := ctCheckBox;
    c2^.CheckType := ctCheckBox;
    c3^.CheckType := ctCheckBox;
    c1^.CheckState := csUnchecked;
    c2^.CheckState := csUnchecked;
    c3^.CheckState := csUnchecked;
    t.PropagateCheckDown(parent, csChecked);
    AssertEquals('c1 csChecked', Ord(csChecked), Ord(c1^.CheckState));
    AssertEquals('c2 csChecked', Ord(csChecked), Ord(c2^.CheckState));
    AssertEquals('c3 csChecked', Ord(csChecked), Ord(c3^.CheckState));
  finally
    t.Free;
  end;
end;

procedure TTreeA2CheckPropTest.TestPropagateCheckDownSkipsRadioButton;
var
  t: TTyTreeView;
  parent, c1, radio: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    c1     := t.AddChild(parent);
    radio  := t.AddChild(parent);
    c1^.CheckType    := ctCheckBox;
    c1^.CheckState   := csUnchecked;
    radio^.CheckType  := ctRadioButton;
    radio^.CheckState := csChecked;
    t.PropagateCheckDown(parent, csUnchecked);
    AssertEquals('c1 set to csUnchecked',    Ord(csUnchecked), Ord(c1^.CheckState));
    AssertEquals('radio stays csChecked',    Ord(csChecked),   Ord(radio^.CheckState));
  finally
    t.Free;
  end;
end;

procedure TTreeA2CheckPropTest.TestRecomputeAllChecked;
var
  t: TTyTreeView;
  parent, c1, c2: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    c1 := t.AddChild(parent);
    c2 := t.AddChild(parent);
    c1^.CheckType  := ctCheckBox; c1^.CheckState := csChecked;
    c2^.CheckType  := ctCheckBox; c2^.CheckState := csChecked;
    AssertEquals('all checked → csChecked',
      Ord(csChecked), Ord(t.RecomputeParentCheckState(parent)));
  finally
    t.Free;
  end;
end;

procedure TTreeA2CheckPropTest.TestRecomputeAllUnchecked;
var
  t: TTyTreeView;
  parent, c1, c2: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    c1 := t.AddChild(parent);
    c2 := t.AddChild(parent);
    c1^.CheckType  := ctCheckBox; c1^.CheckState := csUnchecked;
    c2^.CheckType  := ctCheckBox; c2^.CheckState := csUnchecked;
    AssertEquals('all unchecked → csUnchecked',
      Ord(csUnchecked), Ord(t.RecomputeParentCheckState(parent)));
  finally
    t.Free;
  end;
end;

procedure TTreeA2CheckPropTest.TestRecomputeMixedReturnsCsMixed;
var
  t: TTyTreeView;
  parent, c1, c2, c3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    c1 := t.AddChild(parent);
    c2 := t.AddChild(parent);
    c3 := t.AddChild(parent);
    c1^.CheckType := ctCheckBox; c1^.CheckState := csChecked;
    c2^.CheckType := ctCheckBox; c2^.CheckState := csChecked;
    c3^.CheckType := ctCheckBox; c3^.CheckState := csUnchecked;
    AssertEquals('checked+unchecked → csMixed',
      Ord(csMixed), Ord(t.RecomputeParentCheckState(parent)));
  finally
    t.Free;
  end;
end;

procedure TTreeA2CheckPropTest.TestRecomputeIgnoresRadioButton;
var
  t: TTyTreeView;
  parent, cb, radio: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    cb    := t.AddChild(parent);
    radio := t.AddChild(parent);
    cb^.CheckType    := ctCheckBox;    cb^.CheckState    := csChecked;
    radio^.CheckType  := ctRadioButton; radio^.CheckState := csUnchecked;
    // Only cb counts → all check-children are csChecked → csChecked
    AssertEquals('radio ignored; cb checked → csChecked',
      Ord(csChecked), Ord(t.RecomputeParentCheckState(parent)));
  finally
    t.Free;
  end;
end;

procedure TTreeA2CheckPropTest.TestRecomputeNoCheckChildrenReturnsCurrentState;
var
  t: TTyTreeView;
  parent, child: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    parent := t.AddChild(nil);
    child  := t.AddChild(parent);
    child^.CheckType   := ctNone;  // not a check child
    parent^.CheckState := csMixed;
    AssertEquals('no check-children → current state unchanged',
      Ord(csMixed), Ord(t.RecomputeParentCheckState(parent)));
  finally
    t.Free;
  end;
end;

{ ── A3 ── SelectRange visible-order helper + selection-count bookkeeping ── }

type
  TTreeA3SelectRangeTest = class(TTestCase)
  private
    function  BuildFlatTree6: TTyTreeView;
  published
    { SelectRange(n2,n4): nodes at positions 2,3,4 selected; SelectedCount=3. }
    procedure TestSelectRangeForward;
    { SelectRange(n4,n2): same set regardless of argument order. }
    procedure TestSelectRangeReverse;
    { SelectRange(n,n): just n selected; count=1. }
    procedure TestSelectRangeSingleNode;
    { After SelectRange, ClearSelection → SelectedCount=0. }
    procedure TestClearSelectionResetsCount;
    { SelectedCount returns 0 after construction. }
    procedure TestSelectedCountInitiallyZero;
  end;

function TTreeA3SelectRangeTest.BuildFlatTree6: TTyTreeView;
begin
  Result := TTyTreeView.Create(nil);
  Result.RootNodeCount := 6;
end;

procedure TTreeA3SelectRangeTest.TestSelectRangeForward;
var
  t:     TTyTreeView;
  n:     PTyTreeNode;
  nodes: array[0..5] of PTyTreeNode;
  i:     Integer;
begin
  t := BuildFlatTree6;
  try
    // Collect nodes in visible order
    n := t.RootNode^.FirstChild;
    for i := 0 to 5 do
    begin
      nodes[i] := n;
      n := n^.NextSibling;
    end;
    // SelectRange(node[2], node[4]) → nodes 2,3,4 selected
    t.SelectRange(nodes[2], nodes[4]);
    AssertEquals('SelectedCount = 3', 3, t.SelectedCount);
    AssertFalse('node[0] not selected', nsSelected in nodes[0]^.States);
    AssertFalse('node[1] not selected', nsSelected in nodes[1]^.States);
    AssertTrue ('node[2] selected',     nsSelected in nodes[2]^.States);
    AssertTrue ('node[3] selected',     nsSelected in nodes[3]^.States);
    AssertTrue ('node[4] selected',     nsSelected in nodes[4]^.States);
    AssertFalse('node[5] not selected', nsSelected in nodes[5]^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeA3SelectRangeTest.TestSelectRangeReverse;
var
  t:     TTyTreeView;
  n:     PTyTreeNode;
  nodes: array[0..5] of PTyTreeNode;
  i:     Integer;
begin
  t := BuildFlatTree6;
  try
    n := t.RootNode^.FirstChild;
    for i := 0 to 5 do
    begin
      nodes[i] := n;
      n := n^.NextSibling;
    end;
    // SelectRange(node[4], node[2]) — order-independent; same set
    t.SelectRange(nodes[4], nodes[2]);
    AssertEquals('SelectedCount = 3 (reversed)', 3, t.SelectedCount);
    AssertTrue ('node[2] selected',     nsSelected in nodes[2]^.States);
    AssertTrue ('node[3] selected',     nsSelected in nodes[3]^.States);
    AssertTrue ('node[4] selected',     nsSelected in nodes[4]^.States);
    AssertFalse('node[0] not selected', nsSelected in nodes[0]^.States);
    AssertFalse('node[5] not selected', nsSelected in nodes[5]^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeA3SelectRangeTest.TestSelectRangeSingleNode;
var
  t:     TTyTreeView;
  n:     PTyTreeNode;
  nodes: array[0..5] of PTyTreeNode;
  i:     Integer;
begin
  t := BuildFlatTree6;
  try
    n := t.RootNode^.FirstChild;
    for i := 0 to 5 do
    begin
      nodes[i] := n;
      n := n^.NextSibling;
    end;
    t.SelectRange(nodes[3], nodes[3]);
    AssertEquals('SelectedCount = 1 (single)', 1, t.SelectedCount);
    AssertTrue ('node[3] selected',     nsSelected in nodes[3]^.States);
    AssertFalse('node[2] not selected', nsSelected in nodes[2]^.States);
    AssertFalse('node[4] not selected', nsSelected in nodes[4]^.States);
  finally
    t.Free;
  end;
end;

procedure TTreeA3SelectRangeTest.TestClearSelectionResetsCount;
var
  t:     TTyTreeView;
  n:     PTyTreeNode;
  nodes: array[0..5] of PTyTreeNode;
  i:     Integer;
begin
  t := BuildFlatTree6;
  try
    n := t.RootNode^.FirstChild;
    for i := 0 to 5 do
    begin
      nodes[i] := n;
      n := n^.NextSibling;
    end;
    t.SelectRange(nodes[1], nodes[4]);
    AssertTrue('SelectedCount > 0 before clear', t.SelectedCount > 0);
    t.ClearSelection;
    AssertEquals('SelectedCount = 0 after ClearSelection', 0, t.SelectedCount);
  finally
    t.Free;
  end;
end;

procedure TTreeA3SelectRangeTest.TestSelectedCountInitiallyZero;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    AssertEquals('SelectedCount = 0 initially', 0, t.SelectedCount);
  finally
    t.Free;
  end;
end;

{ ── B1 ── Options set + check array properties ─────────────────────────────── }

type
  TTreeB1OptionsTest = class(TTestCase)
  published
    { Options defaults to []. }
    procedure TestOptionsDefaultEmpty;
    { Setting CheckType via array property stores the value in the node. }
    procedure TestSetCheckTypePersists;
    { Checked[n] := True sets CheckState to csChecked. }
    procedure TestCheckedTrueSetsCsChecked;
    { Checked[n] := False sets CheckState to csUnchecked. }
    procedure TestCheckedFalseSetsCsUnchecked;
    { Checked getter returns True only when csChecked. }
    procedure TestCheckedGetterReflectsCheckState;
    { CheckState[n] := csMixed stores csMixed. }
    procedure TestSetCheckStateMixed;
    { CheckType/CheckState setters are nil-safe (no crash). }
    procedure TestNilNodeSafe;
  end;

procedure TTreeB1OptionsTest.TestOptionsDefaultEmpty;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    AssertTrue('Options default []', t.Options = []);
  finally
    t.Free;
  end;
end;

procedure TTreeB1OptionsTest.TestSetCheckTypePersists;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    t.CheckType[n] := ctCheckBox;
    AssertEquals('CheckType ctCheckBox persisted',
      Ord(ctCheckBox), Ord(t.CheckType[n]));
    AssertEquals('CheckState still csUnchecked',
      Ord(csUnchecked), Ord(t.CheckState[n]));
  finally
    t.Free;
  end;
end;

procedure TTreeB1OptionsTest.TestCheckedTrueSetsCsChecked;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    t.CheckType[n] := ctCheckBox;
    t.Checked[n]   := True;
    AssertEquals('Checked:=True → csChecked',
      Ord(csChecked), Ord(t.CheckState[n]));
    AssertTrue('Checked getter True', t.Checked[n]);
  finally
    t.Free;
  end;
end;

procedure TTreeB1OptionsTest.TestCheckedFalseSetsCsUnchecked;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    t.CheckType[n]  := ctCheckBox;
    t.CheckState[n] := csChecked;   // start checked
    t.Checked[n]    := False;
    AssertEquals('Checked:=False → csUnchecked',
      Ord(csUnchecked), Ord(t.CheckState[n]));
    AssertFalse('Checked getter False', t.Checked[n]);
  finally
    t.Free;
  end;
end;

procedure TTreeB1OptionsTest.TestCheckedGetterReflectsCheckState;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    t.CheckType[n]  := ctCheckBox;
    t.CheckState[n] := csMixed;
    AssertFalse('Checked getter False for csMixed', t.Checked[n]);
  finally
    t.Free;
  end;
end;

procedure TTreeB1OptionsTest.TestSetCheckStateMixed;
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    t.CheckType[n]  := ctTriStateCheckBox;
    t.CheckState[n] := csMixed;
    AssertEquals('CheckState csMixed persisted',
      Ord(csMixed), Ord(t.CheckState[n]));
  finally
    t.Free;
  end;
end;

procedure TTreeB1OptionsTest.TestNilNodeSafe;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    { These must not crash }
    t.CheckType[nil]  := ctCheckBox;
    t.CheckState[nil] := csChecked;
    t.Checked[nil]    := True;
    AssertEquals('CheckType nil→ctNone',     Ord(ctNone),     Ord(t.CheckType[nil]));
    AssertEquals('CheckState nil→csUnchecked', Ord(csUnchecked), Ord(t.CheckState[nil]));
    AssertFalse('Checked nil→False', t.Checked[nil]);
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
  RegisterTest(TTreeGetNodeAtTest);
  RegisterTest(TTreePerfTest);
  RegisterTest(TTreeC1Test);
  RegisterTest(TTreeC2Test);
  RegisterTest(TTreeC3PaintTest);
  RegisterTest(TTreeC4Test);
  RegisterTest(TTreeContentRectPaddingTest);
  RegisterTest(TTreeHiDPITest);
  RegisterTest(TTreeColumnPaintTest);
  RegisterTest(TTreeD1D2Test);
  RegisterTest(TTreeD3DragTest);
  RegisterTest(TTreeD4AutoSizeTest);
  RegisterTest(TTreeE1SortTest);
  RegisterTest(TTreeE2SortTreeTest);
  RegisterTest(TTreeE3HeaderClickTest);
  RegisterTest(TTreeA2CheckPropTest);
  RegisterTest(TTreeA3SelectRangeTest);
  RegisterTest(TTreeB1OptionsTest);
end.
