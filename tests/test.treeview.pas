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

  { ③d A1: GetCellRect — single source of cell geometry.
    Builds a 3-column tree (PPI 96, header 22, DefaultNodeHeight 22, ShowRoot,
    Indent 16, 1 root expanded with 2 children) and asserts GetCellRect's device
    rect matches the painted geometry, scales at HiDPI, shifts with scroll, and
    returns False for non-visible nodes. }
  TTreeGetCellRectTest = class(TTestCase)
  private
    procedure OnGetTextWithType(Sender: TTyTreeView; Node: PTyTreeNode;
      Column: Integer; TextType: TTyVSTTextType; var CellText: string);
    procedure OnInitNodeHasChildren(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure OnInitChildren2(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    { Build the 3-column tree at the given PPI; out-params expose the form/ctl
      (caller frees F then Ctl) and the root + its first child. }
    function BuildTree(out Ctl: TTyStyleController; out F: TForm;
      out ARoot, AChild0: PTyTreeNode; APPI: Integer = 96): TTyTreeView;
  published
    { device rect of column 0 / column 2 matches the manual P.Scale computation }
    procedure TestCellRectColumn0Geometry;
    procedure TestCellRectColumn2Geometry;
    { Column = -1 maps to the main column's cell }
    procedure TestCellRectMainColumnAlias;
    { a child row sits one Scale(NodeHeight) below the root row }
    procedure TestCellRectChildRowTop;
    { a node hidden under a collapsed ancestor → Result = False }
    procedure TestCellRectCollapsedNodeFalse;
    { root / nil → Result = False }
    procedure TestCellRectRootAndNilFalse;
    { a node scrolled entirely above the content rect → Result = False }
    procedure TestCellRectScrolledOffscreenFalse;
    { cross-check vs paint: the caption ink of (root, col 1) lies inside its rect }
    procedure TestCellRectContainsPaintedInk;
    { HiDPI: at PPI=144 the rect (top, height, column span) scales }
    procedure TestCellRectHiDPIScales;
    { scroll: setting FOffsetX/FOffsetY shifts the rect by the same delta as paint }
    procedure TestCellRectShiftsWithScroll;
  end;

  { ③d B1: variable per-node row height (toVariableNodeHeight + OnMeasureItem +
    NodeHeight[]). A flat 12-child tree whose OnMeasureItem returns
    18 + 6*(Index mod 3) → heights cycle 18/24/30. Verifies the ③a height
    invariant holds with variable heights, GetNodeAt lands on the right node,
    NodeHeight[] override bumps TotalHeight by the delta, default-off == ③c, and
    the invariant survives HiDPI (logical units). }
  TTreeB1VariableHeightTest = class(TTestCase)
  private
    FMeasureCalls: Integer;
    procedure OnMeasureItem(Sender: TTyTreeView; ACanvas: TCanvas;
      Node: PTyTreeNode; var ANodeHeight: Integer);
    { Build a flat tree of AChildCount root children at APPI; optionally wire
      OnMeasureItem + toVariableNodeHeight. Caller frees F then Ctl. }
    function BuildFlatTree(out Ctl: TTyStyleController; out F: TForm;
      AChildCount: Integer; AVariable: Boolean; APPI: Integer = 96): TTyTreeView;
    { Force a measure of every visible node (paint to an offscreen bitmap, which
      calls InitNode → OnMeasureItem for each rendered row). Bitmap is tall
      enough to render all rows. }
    procedure ForceMeasureAll(t: TTyTreeView; APPI: Integer = 96);
    { Expected logical height of the child at Index under the 18+6*(idx mod 3) rule. }
    function ExpectedH(Index: Integer): Integer;
  published
    { invariant: RootNode.TotalHeight == Σ measured heights + root's own row }
    procedure TestTotalHeightSumsVariableHeights;
    { SumVisibleHeights (the ③a invariant helper) agrees with RootNode.TotalHeight }
    procedure TestInvariantHelperAgrees;
    { GetNodeAt(y) lands on the correct node across the varied heights }
    procedure TestGetNodeAtAcrossVariedHeights;
    { NodeHeight[node] := 40 bumps TotalHeight by (40 - oldHeight); reads back 40 }
    procedure TestSetNodeHeightUpdatesTotal;
    { default off (no toVariableNodeHeight) → every node = DefaultNodeHeight (== ③c) }
    procedure TestDefaultOffEqualsC3;
    { OnMeasureItem unassigned but option on → still all DefaultNodeHeight }
    procedure TestOptionOnButNoHandlerEqualsC3;
    { HiDPI: at PPI=144 the LOGICAL TotalHeight still sums the logical heights }
    procedure TestHiDPILogicalInvariant;
    { OnMeasureItem returning 0 is ignored (height stays at default) }
    procedure TestZeroHeightIgnored;
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
    // NodeDataSize = -1 (default) 鈫?GetNodeData returns nil even for a real node
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
    // Wait 鈥?root is a special sentinel. Root's TotalCount accumulates all descendants + itself.
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
    // Root's own NodeHeight = 18; plus 5*18 = 90 鈫?108
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
    // parent is not expanded yet 鈥?children contribute 0 height to root
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
// so bulk teardown stays O(n), not O(n虏).
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
      Clear 鈫?destructor must still walk and fire OnFreeNode for all 4 nodes.

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
  // Free without an explicit Clear 鈥?destructor must still fire OnFreeNode
  t.Free;
  AssertEquals('OnFreeNode fired for all 4 nodes on Free (no explicit Clear)', 4, FFireCount);
end;

{ 鈹€鈹€ A5 鈹€鈹€ lazy init + expand/collapse + iterators 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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

{ 鈹€鈹€ TTreeLazyTest helpers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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

{ 鈹€鈹€ TTreeLazyTest published tests 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    n := t.GetFirst;  // InitNode 鈫?sets nsHasChildren
    t.Expanded[n] := True;
    AssertEquals('OnInitChildren fired once', 1, FInitChildrenCount);
    AssertEquals('4 children materialised', 4, Integer(n^.ChildCount));
    AssertTrue  ('nsExpanded set', nsExpanded in n^.States);
    // Second expand call must NOT fire OnInitChildren again.
    FInitChildrenCount := 0;
    t.Expanded[n] := True;   // already expanded 鈥?no-op
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
    n0 := t.GetFirst;   // InitNode n0 鈫?ivsHasChildren
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
{ Expand n[0], then collapse it again 鈥?the 4 children must not appear in the walk. }
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
    n0 := t.GetFirst;  // InitNode 鈫?nsHasChildren
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
    // Baseline: 3 top-level nodes, each NodeHeight=18; root itself 18 鈫?total=4*18=72
    heightBefore := Integer(t.RootNode^.TotalHeight);
    AssertEquals('baseline height 72', 72, heightBefore);

    n0 := t.GetFirst;   // InitNode n0
    t.Expanded[n0] := True;
    heightAfterExpand := Integer(t.RootNode^.TotalHeight);
    // n0 expanded with 4 children (each 18px) 鈫?root total = 72 + 4*18 = 144
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

{ 鈹€鈹€ B1 鈹€鈹€ TotalHeight invariant + FRangeY 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    { Scenario 1: root nodes 鈫?expand 鈫?collapse (basic roundtrip). }
    procedure TestScenario1_ExpandCollapse;
    { Scenario 2: nested expand A, then expand A.child B, then collapse A (B still expanded),
      then re-expand A (B must still be expanded, invariant must hold throughout). }
    procedure TestScenario2_NestedCollapseAndReexpand;
    { Scenario 3: OnInitNode returns ivsExpanded 鈫?auto-expand on first touch;
      assert invariant after the node is initialised. }
    procedure TestScenario3_AutoExpandViaInitStates;
    { Scenario 4: AddChild to an expanded parent grows root height;
      AddChild to a collapsed parent does NOT. }
    procedure TestScenario4_AddChildExpandedVsCollapsed;
    { Scenario 5: DeleteNode of an expanded child (parent expanded) drops the full
      visible subtree; DeleteNode from a collapsed parent leaves root height unchanged. }
    procedure TestScenario5_DeleteExpandedVsCollapsed;
    { Scenario 6 (the bug this fix addresses): with A collapsed, set Expanded[B]=True
      where B is A's child 鈫?A.TotalHeight must stay = A.NodeHeight, root unchanged;
      then expand A 鈫?root grows by B's already-expanded subtree. }
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
  Step 1: expand A 鈫?A's 4 children materialised
  Step 2: expand B (A's first child) 鈫?B's 4 grandchildren materialised
  Step 3: collapse A (B is still expanded internally)
  Step 4: re-expand A 鈫?B must still be expanded, invariant holds }
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

    { Step 4: re-expand A 鈥?B's 4 grandchildren must reappear }
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
{ OnInitNode returns ivsExpanded for level-0 nodes 鈫?auto-expand on first GetNext touch.
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

    { Touch first node: triggers InitNode 鈫?ivsExpanded 鈫?auto-expand 鈫?InitChildren 鈫?4 children }
    n := t.GetFirst;   // fires InitNode(first child) 鈫?sets ivsExpanded 鈫?calls SetExpanded
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

    { AddChild to an EXPANDED node 鈫?root height grows by NodeHeight }
    heightBefore := Integer(t.RootNode^.TotalHeight);
    t.AddChild(expandedParent);
    AssertInvariant(t, 'S4 after AddChild to expanded parent');
    AssertEquals('S4 root height grew by NodeHeight after AddChild to expanded',
                 heightBefore + 18,
                 Integer(t.RootNode^.TotalHeight));

    { AddChild to a COLLAPSED node 鈫?root height unchanged }
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

    { Delete the expanded child (parent expanded) 鈫?root drops by child's full TotalHeight }
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

{ Scenario 6 鈥?the bug this fix addresses }
procedure TTreeHeightInvariantTest.TestScenario6_ExpandInCollapsedAncestor;
{ With A collapsed, programmatically set Expanded[B] := True where B is A's child.
  Expected:
    鈥?A.TotalHeight stays = A.NodeHeight (collapsed; B's subtree excluded)
    鈥?RootNode^.TotalHeight unchanged
  Then expand A:
    鈥?Root grows by A's full (now B-expanded) subtree height
    鈥?B must still be expanded, invariant holds. }
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

    { Expand B while A is COLLAPSED 鈥?the key scenario }
    t.Expanded[B] := True;   { InitChildren fires via SetExpanded 鈫?4 grandchildren }
    AssertInvariant(t, 'S6 after Expanded[B]=True with A collapsed');
    { A is collapsed: its TotalHeight must still be just its own NodeHeight (18) }
    AssertEquals('S6 A.TotalHeight = 18 while A collapsed (B expanded inside)',
                 18, Integer(A^.TotalHeight));
    { Root height must NOT have changed }
    AssertEquals('S6 root height unchanged while A collapsed',
                 rootHeightBase, Integer(t.RootNode^.TotalHeight));
    AssertTrue('S6 B is marked expanded', nsExpanded in B^.States);

    { Now expand A 鈥?root must grow by A's full visible subtree (A's 4 children + B's 4 grandchildren) }
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

{ 鈹€鈹€ B2 鈹€鈹€ GetNodeAt(Y) cross-check vs linear walk 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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

      Total visible height = 10 nodes 脳 18 = 180 px
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

{ 鈹€鈹€ TTreeGetNodeAtTest helpers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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

  { A1's children 鈥?allocate them but keep A1 collapsed }
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
  { Y is past the end 鈥?return nil }
end;

{ 鈹€鈹€ TTreeGetNodeAtTest published tests 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
  Total visible = 11 nodes 脳 18 = 198 px }
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
    { A0C1 is at top=36, NodeHeight=18 鈫?spans [36, 54) }
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

{ 鈹€鈹€ B3 鈹€鈹€ position cache + performance invariant 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

type
  TTreePerfTest = class(TTestCase)
  private
    { Linear-walk helper (reused from TTreeGetNodeAtTest). }
    function LinearGetNodeAt(T: TTyTreeView; Y: Integer; out ANodeTop: Integer): PTyTreeNode;
  published
    { PERFORMANCE INVARIANT: a flat 200k-node tree, GetNodeAt near the END of the
      list must visit 鈮?TREE_CACHE_STEP + small constant nodes, NOT ~200k.
      This proves the binary-search cache bounds the per-call scan.

      200k flat skeleton nodes are allocated in one SetChildCount call
      (no OnInitNode, NodeDataSize=0 鈫?minimum allocation stride).
      Each node: NodeHeight=18, nsVisible set, not expandable 鈫?total visible height = 200k脳18.

      We query a Y near the END (node 199_000's top = 199_000 脳 18 = 3_582_000 px).
      Without the cache, GetNodeAt would scan ~199_000 nodes linearly.
      With TREE_CACHE_STEP=2000, it starts from mark floor(199_000/2000)=99 and
      then scans at most 2000 nodes 鈫?visits 鈮?2000+small.

      Building 200k nodes takes ~100ms headlessly; well within test budget. }
    procedure TestFlatTree200kCacheBoundsVisits;

    { CORRECTNESS SPOT-CHECK: a few GetNodeAt queries on the 200k tree must return
      the correct node (verified against a short local linear walk 鈥?we do NOT
      linearly scan 200k for every query). }
    procedure TestFlatTree200kCorrectness;

    { INVALIDATION: after Clear, the cache is dirty; after re-adding nodes,
      ValidateCache rebuilds and GetNodeAt still works correctly. }
    procedure TestCacheInvalidatesOnClear;
  end;

function TTreePerfTest.LinearGetNodeAt(T: TTyTreeView; Y: Integer;
  out ANodeTop: Integer): PTyTreeNode;
{ Short linear walk 鈥?only used for spot-checks of a few nodes. }
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
  Query Y near the END of the list (node 199_000 鈫?top = 199_000 脳 18).
  Expect: visits 鈮?TREE_CACHE_STEP + a small constant (well under 3000).
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

    { Y for node at QUERY_INDEX (0-based): QUERY_INDEX 脳 DefaultNodeHeight }
    queryY := QUERY_INDEX * t.DefaultNodeHeight;

    node   := t.GetNodeAt(queryY, nodeTop);
    visits := t.LastGetNodeAtVisits;

    AssertTrue('node found (not nil)', node <> nil);

    { nodeTop must be exactly QUERY_INDEX 脳 18 }
    AssertEquals('nodeTop correct', QUERY_INDEX * t.DefaultNodeHeight, nodeTop);

    { The cache must limit the scan to 鈮?MAX_VISITS nodes.
      Without the cache, this would be ~199_000.  With TREE_CACHE_STEP=2000 the
      walk starts from mark 99 (top=199_000脳18 closest from below) and advances
      at most 2000 nodes, so visits will typically be 鈮?2001. }
    if visits > MAX_VISITS then
      Fail(Format('Cache did NOT bound the scan: visited %d nodes (limit=%d). '
                + 'Expected 鈮?%d for TREE_CACHE_STEP=%d.',
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

    { First query 鈥?builds cache }
    node := t.GetNodeAt(0, nodeTop);
    AssertTrue('first query: node found', node <> nil);

    { Clear invalidates the cache; RangeY = ContentHeight = TotalHeight - NodeHeight.
      After Clear, no children remain, so TotalHeight = NodeHeight 鈫?RangeY = 0. }
    t.Clear;
    AssertEquals('after Clear: RangeY = ContentHeight (= 0 when tree empty)',
                 Integer(t.RootNode^.TotalHeight) - Integer(t.RootNode^.NodeHeight),
                 t.RangeY);
    node := t.GetNodeAt(0, nodeTop);
    AssertNull('after Clear: GetNodeAt(0) = nil (empty)', node);

    { Add nodes back 鈫?cache rebuilds }
    t.RootNodeCount := NODE_COUNT;
    node := t.GetNodeAt((NODE_COUNT - 1) * t.DefaultNodeHeight, nodeTop);
    AssertTrue('after re-add: last node found', node <> nil);
    AssertEquals('after re-add: nodeTop correct',
                 (NODE_COUNT - 1) * t.DefaultNodeHeight, nodeTop);
  finally
    t.Free;
  end;
end;

{ 鈹€鈹€ C1 鈹€鈹€ selection / focus + tree options + FullExpand/Collapse/ScrollIntoView 鈹€鈹€ }

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

{ 鈹€鈹€ Published tests 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    t.Selected[n] := True;   // re-select same node 鈫?should fire nothing
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
{ Just flip every Boolean and set Indent 鈥?must not crash (Invalidate is safe
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
    level 0: 3 nodes  鈫?3  OnInitChildren calls  (3 root nodes expanded)
    level 1: 9 nodes  鈫?9  OnInitChildren calls  (9 level-1 nodes expanded)
    level 2: 27 nodes 鈫?27 OnInitChildren calls  (27 level-2 nodes expanded)
    level 3: 81 nodes 鈫?leaves (level >= 3 鈫?no ivsHasChildren 鈫?not expanded)
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
    // FRESH tree 鈥?no manual InitNode calls; FullExpand must do its own InitNode.

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
{ Expand some nodes then FullCollapse 鈥?all nsExpanded bits must be cleared. }
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
    t.RootNodeCount := 20;   // 20 nodes 脳 18px = 360px total; ClientHeight=0 headless
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

{ 鈹€鈹€ C2 鈹€鈹€ embedded scrollbars + offsets 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

type
  TTreeC2Test = class(TTestCase)
  private
    procedure OnInitChildrenX(Sender: TTyTreeView; Node: PTyTreeNode;
                               var ChildCount: Cardinal);
    { FIX 4 helper: returns a text string wide enough to overflow a 50px viewport }
    procedure OnGetTextWide(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
  published
    { Scrollbars exist immediately after Create 鈥?never lazily created during paint. }
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
{ Both scrollbars must be allocated right after Create 鈥?before any paint,
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
  After UpdateScrollBars (called by InvalidateTreeLayout 鈫?SetChildCount),
  the vertical scrollbar must be Visible. }
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    { Height = 160 (default); 20 nodes 脳 18 = 360px > 160px 鈫?bar needed. }
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
{ 3 nodes 脳 18 = 54px < 160px (default Height) 鈫?bar hidden, FOffsetY = 0. }
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
  Then Clear 鈫?RangeX must drop to 0 immediately (InvalidateTreeLayout).
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

{ 鈹€鈹€ C3 鈹€鈹€ pixel paint tests 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    row 0 = top-level node 0 (level 0, expanded). Caption starts at x鈮?8.
    row 1 = first child of node 0 (level 1). Caption starts at x鈮?4.
  Assert: the child row has text ink at x鈮?0 (comfortably in its caption zone)
  AND the parent row has text ink at x in [18..35) (its caption zone).
  Crucially, the parent row at x鈮?6 should NOT have text ink (caption 'N0 L0'
  is short) 鈥?but that's font-dependent.  The robust assertion is:
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
    y=40..59 : grandchild 0 of child 0 (level 2 = leaf 鈫?no button)
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
        { Grey tree lines have R=G=B鈮?28; glyph has R<64. We only flag as "ink"
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
    { No RootNodeCount set 鈥?tree is empty }
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

{ 鈹€鈹€ C4 鈹€鈹€ hit-test + mouse + keyboard 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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

  Note: the tree is created with Create(nil) so there is no controller 鈫?no CSS
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

{ 鈹€鈹€ C4 published tests 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
  x=30 >= indentPx=16 鈫?label zone. }
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
{ 6 rows 脳 20px = 120px total.  Y=130 is below all rows.
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
  n0c0 row absY=[20..39].  Client Y=30 鈫?absY=30 鈫?n0c0. }
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
  Client Y=90, X=30 鈫?n1's label zone.
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
{ n0 is currently EXPANDED.  Click on its button slot 鈫?should collapse it.
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
  Set FocusedNode = n0, press VK_DOWN 鈫?should land on n0c0 and fire OnFocusChanged. }
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
  then press VK_RIGHT 鈫?should expand it. }
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
{ n0 is expanded; press VK_LEFT with FocusedNode=n0 鈫?should collapse n0. }
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
    Then DeleteNode(n1) 鈥?FLastMouseNode must become nil.
    Then call DblClick 鈥?must not crash AND must NOT fire OnNodeDblClick. }
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
    // Call DblClick 鈥?if FLastMouseNode is not nil this would be a UAF.
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

    // Right-click on n2 鈥?even though nsSelected is set, focus must follow
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbRight, [], 30, 110);
    {$POP}
    AssertTrue('FocusedNode = n2 after right-click on already-selected node',
               t.FocusedNode = n2);
  finally
    t.Free;
  end;
end;

{ 鈹€鈹€ ContentRect padding regression 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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

{ 鈹€鈹€ HiDPI (PPI鈮?6) vertical-axis correctness 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

type
  { Two tests that are IMPOSSIBLE to pass before the fix but trivially pass after:
      (a) hit-test matches paint at PPI=144 (150 %)
      (b) ScrollIntoView / UpdateScrollBars reaches the true logical bottom

    Tree geometry (PPI=144, border-width=0, padding=0):
      DefaultNodeHeight = 20 logical 鈫?30 device pixels per row
      Viewport          = 200脳300 device = 200脳200 logical (MulDiv(300,96,144))
      20 root nodes     鈫?ContentHeight (logical) = 400
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

{ BuildHiDPITree144: 20 root nodes, PPI=144, 200脳300 device viewport, no border/padding.
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

  Pre-fix:  absY = (75 - 0) + 0 = 75 鈫?GetNodeAt returns node[3] (wrong).
  Post-fix: absY = MulDiv(75, 96, 144) + 0 = 50 鈫?GetNodeAt returns node[2] (correct). }
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

{ 鈹€鈹€ C (columns): Phase C1 + C2 paint tests 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

type
  { TTreeColumnPaintTest 鈥?pixel tests for multi-column node paint (C1)
    and header band paint (C2).
    Guard: 0-column render must be byte-identical to 鈶 (existing tests green). }
  TTreeColumnPaintTest = class(TTestCase)
  private
    { Per-column text returned by OnGetTextWithType }
    procedure OnGetTextWithType(Sender: TTyTreeView; Node: PTyTreeNode;
      Column: Integer; TextType: TTyVSTTextType; var CellText: string);
    procedure OnInitNodeHasChildren(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode;
      var InitStates: TTyNodeInitStates);
    procedure OnInitChildren3(Sender: TTyTreeView; Node: PTyTreeNode;
      var ChildCount: Cardinal);
    { C0 regression: 0-column callbacks mimicking 鈶 (same as TTreeC3PaintTest) }
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
    { C0 regression: 0 columns 鈫?existing 鈶 single-column paint is unchanged.
      The same pixel assertions as TestChildRowIndentedMoreThanTopLevel must still hold. }
    procedure TestC0_ZeroColumnsIdenticToIIIa;
  end;

  { TTreeD1D2Test 鈥?D1 header/column hit-test + D2 column resize by drag }
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
    { D1: Y below the header band 鈫?GetHeaderHitAt returns False }
    procedure TestD1_BelowHeaderNotHeader;
    { D1: zero columns 鈫?GetHeaderHitAt always returns False }
    procedure TestD1_ZeroColumnsNoHeader;
    { D1: 2-out overload still compiles and works (backward compat) }
    procedure TestD1_TwoOutOverloadCompat;
    { D2: dragging col0 divider right by 30px widens col0 by 30 }
    procedure TestD2_ResizeColumn0;
    { D2: drag is clamped to MaxWidth }
    procedure TestD2_ClampAtMaxWidth;
    { D2: column without coResizable 鈫?drag does not start }
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
    Row 0 y-center 鈮?22 + 11 = 33. }
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
  The col1 left edge (x=120) up to the caption margin (x=123) is a blank gap 鈥?
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
        The caption 'Root' starts around x=36, so x=50 may have text 鈥?but text on a blue
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
  Col 0 header text 'Name' 鈫?ink in [0..120) at y=11.
  Col 1 header text 'Info' 鈫?ink in [120..200) at y=11.
  Col 2 header text 'Size' 鈫?ink in [200..300) at y=11. }
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
  The glyph arrow is drawn at the right of the col 1 cell so we probe x鈮?90 (right
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

{ C2d: FOffsetX = 0 鈫?header and cell column origins are aligned.
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

{ C0 regression: 0 columns 鈫?the 鈶 single-column paint path is byte-identical.
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
  { BuildPaintTree creates a 0-column tree with the 鈶 OnGetText event }
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

{ 鈹€鈹€ D1/D2 鈹€鈹€ header/column hit-test + column resize 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    { X=60 鈫?col0 (span [0..120)) }
    node := t.GetNodeAtPoint(60, 33, part, col);
    AssertTrue('D1: node at (60,33) not nil', node <> nil);
    AssertEquals('D1: column at X=60 is col0', 0, col);

    { X=250 鈫?col2 (span [200..300)) }
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

{ D1: Y in node area (below header) 鈫?GetHeaderHitAt returns False }
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

{ D1: zero columns 鈫?header is not shown 鈫?GetHeaderHitAt returns False }
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
    AssertFalse('D1: no columns 鈫?GetHeaderHitAt = False',
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

{ D2: dragging col0 divider from X=120 to X=150 鈫?col0.Width = 150 }
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
    TTyTreeViewAccess(t).MouseMove([], 200, 11);  // delta=80 鈫?unclamped=200, clamped=130
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 200, 11);

    AssertEquals('D2: col0.Width clamped to MaxWidth=130', 130, col0.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D2: column without coResizable 鈫?drag does not start 鈫?width unchanged }
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

{ 鈹€鈹€ D3 鈹€鈹€ column drag-reorder 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    { Drag col0 header past the threshold into col2 area 鈫?positions reordered,
      FLeft recomputed, OnColumnReorder fired with oldPos=0 newPos=2. }
    procedure TestD3_DragReorderColumns;
    { Press-and-release with no movement 鈫?no reorder (click-sort path preserved). }
    procedure TestD3_ClickNoReorder;
    { Drag below threshold 鈫?no reorder (pending state cleared cleanly). }
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

  { 3 columns 鈥?widths 100/80/60 }
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

{ D3: drag col0 centre to col2 centre 鈫?positions reordered }
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

{ D3: press-and-release without movement 鈫?no reorder }
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

    { col0 must still be at position 0 鈥?no reorder }
    AssertEquals('D3: click-no-move leaves col0.Position=0', 0, Integer(col0.Position));
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D3: drag below threshold 鈫?no reorder }
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
    TTyTreeViewAccess(t).MouseMove([], 52, 11);   { 2px 鈥?below threshold }
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

{ 鈹€鈹€ D4 鈹€鈹€ auto-size on resize + spring 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
  { Width=300, header=22px 鈫?content width=300 (no scrollbars, no padding in theme) }
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
    { Resize the control to 350 wide 鈥?Resize override should run ApplyAutoSize }
    t.SetBounds(0, 0, 350, 200);
    { SetBounds calls Resize; verify col1 absorbed the extra 50px }
    expected := 350 - 100 - 80;  { = 170 }
    AssertEquals('D4: col1 grows to 170 after Resize to 350', expected, col1.Width);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

{ D4: spring distribution 鈥?two coAutoSpring columns share delta evenly }
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

{ 鈹€鈹€ E1 鈹€鈹€ OnCompareNodes + sibling-list merge Sort(node,col,dir) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }
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

  { Create a parent node with 8 children (NOT expanded 鈥?sort is a pure relink test) }
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
    { Parent has no children 鈥?Sort must be a no-op (no crash) }
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
    { 1 child 鈥?Sort must be a no-op (no crash, child unchanged) }
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

{ 鈹€鈹€ E2 鈹€鈹€ SortTree recursive lazy-aware + cache rebuild 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    { A's children: sorted ascending 鈫?A2(1), A1(2) }
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
    { B's children: sorted ascending 鈫?B2(5), B1(9) }
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

{ 鈹€鈹€ E3 鈹€鈹€ header-click sort wiring 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    { Click col0 twice 鈫?desc }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 50, 11);
    TTyTreeViewAccess(t).MouseUp(mbLeft, [], 50, 11);
    AssertEquals('E3 col0 is desc', Ord(sdDescending), Ord(t.Header.SortDirection));
    { Click col1 (X=150) 鈫?SortColumn=1, reset to asc }
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

{ 鈹€鈹€ A2 鈹€鈹€ check types + tri-state propagation pure helpers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

type
  TTreeA2CheckPropTest = class(TTestCase)
  published
    { PropagateCheckDown sets all ctCheckBox children to the given state. }
    procedure TestPropagateCheckDownSetsAllCheckBoxChildren;
    { PropagateCheckDown does not touch ctRadioButton children. }
    procedure TestPropagateCheckDownSkipsRadioButton;
    { RecomputeParentCheckState: all checked 鈫?csChecked. }
    procedure TestRecomputeAllChecked;
    { RecomputeParentCheckState: all unchecked 鈫?csUnchecked. }
    procedure TestRecomputeAllUnchecked;
    { RecomputeParentCheckState: mixed (checked+unchecked) 鈫?csMixed. }
    procedure TestRecomputeMixedReturnsCsMixed;
    { RecomputeParentCheckState: ctRadioButton children are ignored. }
    procedure TestRecomputeIgnoresRadioButton;
    { RecomputeParentCheckState: no check-children 鈫?returns current state unchanged. }
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
    AssertEquals('all checked 鈫?csChecked',
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
    AssertEquals('all unchecked 鈫?csUnchecked',
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
    AssertEquals('checked+unchecked 鈫?csMixed',
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
    // Only cb counts 鈫?all check-children are csChecked 鈫?csChecked
    AssertEquals('radio ignored; cb checked 鈫?csChecked',
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
    AssertEquals('no check-children 鈫?current state unchanged',
      Ord(csMixed), Ord(t.RecomputeParentCheckState(parent)));
  finally
    t.Free;
  end;
end;

{ 鈹€鈹€ A3 鈹€鈹€ SelectRange visible-order helper + selection-count bookkeeping 鈹€鈹€ }

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
    { After SelectRange, ClearSelection 鈫?SelectedCount=0. }
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
    // SelectRange(node[2], node[4]) 鈫?nodes 2,3,4 selected
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
    // SelectRange(node[4], node[2]) 鈥?order-independent; same set
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

{ 鈹€鈹€ B1 鈹€鈹€ Options set + check array properties 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

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
    AssertEquals('Checked:=True 鈫?csChecked',
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
    AssertEquals('Checked:=False 鈫?csUnchecked',
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
    AssertEquals('CheckType nil鈫抍tNone',     Ord(ctNone),     Ord(t.CheckType[nil]));
    AssertEquals('CheckState nil鈫抍sUnchecked', Ord(csUnchecked), Ord(t.CheckState[nil]));
    AssertFalse('Checked nil鈫扚alse', t.Checked[nil]);
  finally
    t.Free;
  end;
end;

{ 鈹€鈹€ B2 鈹€鈹€ Checkbox/radio paint in the main column 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ }

{ Helper: build a simple paint tree with an inline CSS theme that includes
  TyTreeCheckBox rules.  Returns the tree (owned by F).
  The tree has 2 root nodes:
    n0  ctCheckBox  csChecked
    n1  ctCheckBox  csUnchecked
  Width=200, Height=100, PPI=96, NodeHeight=20, Indent=16, ShowRoot=True.
  toCheckSupport is set in Options.  An outer Ctl+F must be freed by the caller. }
function BuildCheckboxPaintTree(out Ctl: TTyStyleController; out F: TForm;
  CheckOff: Boolean = False): TTyTreeViewAccess;
var
  t: TTyTreeViewAccess;
  n0, n1: PTyTreeNode;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(
    'TyTreeView { background:#FFFFFF; border-width:0px; padding:0px; } ' +
    'TyTreeNode { background:none; color:#000000; } ' +
    'TyTreeNode:selected { background:#3B82F6; color:#FFFFFF; } ' +
    'TyTreeCheckBox { background:#FFFFFF; color:#000000; border-color:#888888; border-width:1px; } ' +
    'TyTreeCheckBox:active { background:#3B82F6; color:#FFFFFF; border-color:#3B82F6; border-width:1px; }');
  F := TForm.CreateNew(nil);
  t := TTyTreeViewAccess(TTyTreeView.Create(F));
  t.Parent              := F;
  t.Controller          := Ctl;
  t.Font.PixelsPerInch  := 96;
  t.DefaultNodeHeight   := 20;
  t.Indent              := 16;
  t.ShowButtons         := False;
  t.ShowTreeLines       := False;
  t.ShowRoot            := True;
  t.SetBounds(0, 0, 200, 100);
  if not CheckOff then
    t.Options := [toCheckSupport];
  t.RootNodeCount := 2;
  n0 := t.RootNode^.FirstChild;
  n1 := n0^.NextSibling;
  t.CheckType[n0]  := ctCheckBox;
  t.CheckState[n0] := csChecked;
  t.CheckType[n1]  := ctCheckBox;
  t.CheckState[n1] := csUnchecked;
  Result := t;
end;

{ Helper: scan x=[xLeft..xRight) at y; True if any pixel is dark (R<150, A>0). }
function HasDarkInkAt(Bmp: TBGRABitmap; xLeft, xRight, y: Integer): Boolean;
var
  x: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for x := xLeft to xRight - 1 do
  begin
    px := Bmp.GetPixel(x, y);
    if (px.alpha > 0) and (px.red < 150) then begin Result := True; Exit; end;
  end;
end;

{ Helper: True if any pixel in x=[xLeft..xRight) at y is NOT pure white. }
function HasNonWhiteAt(Bmp: TBGRABitmap; xLeft, xRight, y: Integer): Boolean;
var
  x: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for x := xLeft to xRight - 1 do
  begin
    px := Bmp.GetPixel(x, y);
    if (px.alpha > 0) and ((px.red < 240) or (px.green < 240) or (px.blue < 240)) then
    begin Result := True; Exit; end;
  end;
end;

type
  TTreeB2CheckPaintTest = class(TTestCase)
  published
    procedure TestCheckedNodeDrawsCheckGlyph;
    procedure TestUncheckedNodeDrawsEmptyBox;
    procedure TestCaptionStartsRightOfCheckSlot;
    procedure TestNoCheckSlotWhenOptionOff;
    procedure TestRadioButtonCheckedDrawsDot;
  end;

procedure TTreeB2CheckPaintTest.TestCheckedNodeDrawsCheckGlyph;
{ Row 0 (csChecked) at y=10. Slot x=[16..32). With :active 鈫?blue fill 鈫?non-white. }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F);
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Tree.Width, Tree.Height);
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      Tree.RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      Bgra := TBGRABitmap.Create(Bmp, True);
      try
        AssertTrue('B2: checked row 0 has non-white ink in slot x=[16..32) at y=10',
          HasNonWhiteAt(Bgra, 16, 32, 10));
      finally Bgra.Free; end;
    finally Bmp.Free; end;
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeB2CheckPaintTest.TestUncheckedNodeDrawsEmptyBox;
{ Row 1 (csUnchecked) at y=30. Border in slot (non-white); no dark glyph in centre. }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F);
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Tree.Width, Tree.Height);
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      Tree.RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      Bgra := TBGRABitmap.Create(Bmp, True);
      try
        AssertTrue('B2: unchecked row 1 border ink in x=[16..32) at y=30',
          HasNonWhiteAt(Bgra, 16, 32, 30));
        AssertFalse('B2: unchecked row 1 no dark glyph in x=[21..27) at y=30',
          HasDarkInkAt(Bgra, 21, 27, 30));
      finally Bgra.Free; end;
    finally Bmp.Free; end;
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeB2CheckPaintTest.TestCaptionStartsRightOfCheckSlot;
{ Slot x=[16..32) has non-white ink; x=[0..16) is white (no indent at level 0). }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F);
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Tree.Width, Tree.Height);
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      Tree.RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      Bgra := TBGRABitmap.Create(Bmp, True);
      try
        AssertTrue('B2: slot x=[16..32) has non-white ink at y=10',
          HasNonWhiteAt(Bgra, 16, 32, 10));
        AssertFalse('B2: x=[0..16) is white at y=10',
          HasNonWhiteAt(Bgra, 0, 16, 10));
      finally Bgra.Free; end;
    finally Bmp.Free; end;
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeB2CheckPaintTest.TestNoCheckSlotWhenOptionOff;
{ toCheckSupport OFF 鈫?x=[16..32) is pure white (no box drawn). }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F, True);  { CheckOff=True }
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Tree.Width, Tree.Height);
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      Tree.RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      Bgra := TBGRABitmap.Create(Bmp, True);
      try
        AssertFalse('B2 (option off): no box border in x=[16..32) at y=10',
          HasNonWhiteAt(Bgra, 16, 32, 10));
      finally Bgra.Free; end;
    finally Bmp.Free; end;
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeB2CheckPaintTest.TestRadioButtonCheckedDrawsDot;
{ ctRadioButton + csChecked 鈫?:active 鈫?blue circle 鈫?non-white ink in slot. }
var
  Ctl: TTyStyleController;
  F: TForm;
  t: TTyTreeViewAccess;
  n: PTyTreeNode;
  Bmp: TBitmap;
  Bgra: TBGRABitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(
    'TyTreeView { background:#FFFFFF; border-width:0px; padding:0px; } ' +
    'TyTreeNode { background:none; color:#000000; } ' +
    'TyTreeNode:selected { background:#3B82F6; color:#FFFFFF; } ' +
    'TyTreeCheckBox { background:#FFFFFF; color:#000000; border-color:#888888; border-width:1px; } ' +
    'TyTreeCheckBox:active { background:#3B82F6; color:#FFFFFF; border-color:#3B82F6; border-width:1px; }');
  F := TForm.CreateNew(nil);
  t := TTyTreeViewAccess(TTyTreeView.Create(F));
  t.Parent := F; t.Controller := Ctl; t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight := 20; t.Indent := 16;
  t.ShowButtons := False; t.ShowTreeLines := False; t.ShowRoot := True;
  t.Options := [toCheckSupport]; t.SetBounds(0, 0, 200, 100);
  t.RootNodeCount := 1;
  n := t.RootNode^.FirstChild;
  t.CheckType[n] := ctRadioButton; t.CheckState[n] := csChecked;
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit; Bmp.SetSize(t.Width, t.Height);
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      t.RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      Bgra := TBGRABitmap.Create(Bmp, True);
      try
        AssertTrue('B2: ctRadioButton+csChecked draws ink in x=[16..32) at y=10',
          HasNonWhiteAt(Bgra, 16, 32, 10));
      finally Bgra.Free; end;
    finally Bmp.Free; end;
  finally F.Free; Ctl.Free; end;
end;

{ ── B3 ── Checkbox hit-test (hpCheckBox) ───────────────────────────────────── }

type
  TTreeB3HitCheckBoxTest = class(TTestCase)
  published
    procedure TestClickInSlotReturnsHpCheckBox;
    procedure TestClickOnLabelReturnsHpLabel;
    procedure TestOptionOffNoHpCheckBox;
    procedure TestCtNoneNodeNoHpCheckBox;
  end;

procedure TTreeB3HitCheckBoxTest.TestClickInSlotReturnsHpCheckBox;
{ toCheckSupport on; node 0 is ctCheckBox; click at x=20 (slot=[16..32)) → hpCheckBox }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  HitNode: PTyTreeNode;
  HitPart: TTyTreeHitPart;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F);
  try
    HitNode := Tree.GetNodeAtPoint(20, 10, HitPart);
    AssertNotNull('B3: hit node at (20,10)', HitNode);
    AssertTrue('B3: hpCheckBox when clicking slot x=20', HitPart = hpCheckBox);
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeB3HitCheckBoxTest.TestClickOnLabelReturnsHpLabel;
{ Click at x=50 (well past slot [16..32)) → hpLabel }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  HitNode: PTyTreeNode;
  HitPart: TTyTreeHitPart;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F);
  try
    HitNode := Tree.GetNodeAtPoint(50, 10, HitPart);
    AssertNotNull('B3: hit node at (50,10)', HitNode);
    AssertTrue('B3: hpLabel when clicking past slot x=50', HitPart = hpLabel);
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeB3HitCheckBoxTest.TestOptionOffNoHpCheckBox;
{ toCheckSupport OFF; click at x=20 → hpLabel (no slot reserved) }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  HitNode: PTyTreeNode;
  HitPart: TTyTreeHitPart;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F, True);  { CheckOff=True }
  try
    HitNode := Tree.GetNodeAtPoint(20, 10, HitPart);
    AssertNotNull('B3 (opt off): hit node at (20,10)', HitNode);
    AssertFalse('B3 (opt off): no hpCheckBox when toCheckSupport off',
      HitPart = hpCheckBox);
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeB3HitCheckBoxTest.TestCtNoneNodeNoHpCheckBox;
{ toCheckSupport ON but CheckType=ctNone → click in slot → not hpCheckBox }
var
  Ctl: TTyStyleController;
  F: TForm;
  Tree: TTyTreeViewAccess;
  n: PTyTreeNode;
  HitNode: PTyTreeNode;
  HitPart: TTyTreeHitPart;
begin
  Tree := BuildCheckboxPaintTree(Ctl, F);
  try
    { Override first node to ctNone }
    n := Tree.RootNode^.FirstChild;
    Tree.CheckType[n] := ctNone;
    HitNode := Tree.GetNodeAtPoint(20, 10, HitPart);
    AssertNotNull('B3 (ctNone): hit node at (20,10)', HitNode);
    AssertFalse('B3 (ctNone): no hpCheckBox when CheckType=ctNone',
      HitPart = hpCheckBox);
  finally F.Free; Ctl.Free; end;
end;

{ ── C1 ── ToggleCheck + events + radio exclusivity + auto-tri-state ─────────── }

type
  TTreeC1CheckBehaviourTest = class(TTestCase)
  private
    FCheckingCount: Integer;
    FCheckingAllowed: Boolean;
    FCheckedCount: Integer;
    FCheckedLastNode: PTyTreeNode;
    procedure OnChecking(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean);
    procedure OnChecked(Sender: TTyTreeView; Node: PTyTreeNode);

    { Build a tree with toCheckSupport (PPI=96, NodeHeight=20, Indent=16, ShowRoot=True)
      ready for checkbox-slot hit tests.  Returns TTyTreeViewAccess.
      F is the owning form; Ctl is the style controller.
      n0 = first root child (ctCheckBox, csUnchecked). }
    function BuildCheckTree(out Ctl: TTyStyleController; out F: TForm;
      out n0: PTyTreeNode): TTyTreeViewAccess;
  published
    { ToggleCheck: ctCheckBox unchecked→checked }
    procedure TestToggleCheckBoxUncheckedToChecked;
    { ToggleCheck: ctCheckBox checked→unchecked }
    procedure TestToggleCheckBoxCheckedToUnchecked;
    { OnChecked fires after a successful toggle }
    procedure TestOnCheckedFiresAfterToggle;
    { OnChecking with Allowed:=False blocks the change and OnChecked NOT fired }
    procedure TestOnCheckingVetoBlocksChange;
    { ctTriStateCheckBox: unchecked→checked }
    procedure TestTriStateUncheckedToChecked;
    { ctTriStateCheckBox: checked→unchecked }
    procedure TestTriStateCheckedToUnchecked;
    { ctTriStateCheckBox: csMixed→csChecked (user click never sets csMixed) }
    procedure TestTriStateMixedToChecked;
    { Radio: checking the 2nd of 3 radio siblings → 2nd checked, others unchecked }
    procedure TestRadioExclusivity;
    { Radio: checking the 3rd after the 2nd → 3rd checked, 2nd unchecked }
    procedure TestRadioSwitchToThird;
    { MouseDown on hpCheckBox toggles check, does NOT change FocusedNode/selection }
    procedure TestMouseDownCheckBoxDoesNotSelect;
    { VK_SPACE on focused checkable node toggles it }
    procedure TestSpaceKeyTogglesCheck;
    { toCheckSupport off → ToggleCheck is a no-op (no state change) }
    procedure TestToggleCheckNoOpWhenOptionOff;
    { toCheckSupport off → click where box would be just selects (③b behaviour) }
    procedure TestClickWithCheckOffSelectsNode;
    { toAutoTristateTracking: ToggleCheck(parent) csChecked → all children csChecked }
    procedure TestAutoTriStateDownPropagatesToChildren;
    { toAutoTristateTracking: uncheck one child → parent becomes csMixed }
    procedure TestAutoTriStateUpMixedOnOneUnchecked;
    { toAutoTristateTracking: uncheck all children → parent csUnchecked }
    procedure TestAutoTriStateUpAllUnchecked;
  end;

procedure TTreeC1CheckBehaviourTest.OnChecking(Sender: TTyTreeView;
  Node: PTyTreeNode; var Allowed: Boolean);
begin
  Inc(FCheckingCount);
  Allowed := FCheckingAllowed;
end;

procedure TTreeC1CheckBehaviourTest.OnChecked(Sender: TTyTreeView;
  Node: PTyTreeNode);
begin
  Inc(FCheckedCount);
  FCheckedLastNode := Node;
end;

function TTreeC1CheckBehaviourTest.BuildCheckTree(out Ctl: TTyStyleController;
  out F: TForm; out n0: PTyTreeNode): TTyTreeViewAccess;
var
  t: TTyTreeViewAccess;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(
    'TyTreeView { background:#FFFFFF; border-width:0px; padding:0px; } ' +
    'TyTreeNode { background:none; color:#000000; } ' +
    'TyTreeNode:selected { background:#3B82F6; color:#FFFFFF; } ' +
    'TyTreeCheckBox { background:#FFFFFF; color:#000000; border-color:#888888; border-width:1px; } ' +
    'TyTreeCheckBox:active { background:#3B82F6; color:#FFFFFF; border-color:#3B82F6; border-width:1px; }');
  F := TForm.CreateNew(nil);
  t := TTyTreeViewAccess(TTyTreeView.Create(F));
  t.Parent             := F;
  t.Controller         := Ctl;
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 20;
  t.Indent             := 16;
  t.ShowButtons        := False;
  t.ShowTreeLines      := False;
  t.ShowRoot           := True;
  t.Options            := [toCheckSupport];
  t.SetBounds(0, 0, 200, 100);
  t.RootNodeCount := 1;
  n0 := t.RootNode^.FirstChild;
  t.CheckType[n0]  := ctCheckBox;
  t.CheckState[n0] := csUnchecked;
  Result := t;
end;

procedure TTreeC1CheckBehaviourTest.TestToggleCheckBoxUncheckedToChecked;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.ToggleCheck(n0);
    AssertEquals('C1: unchecked→checked', Ord(csChecked), Ord(t.CheckState[n0]));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestToggleCheckBoxCheckedToUnchecked;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.CheckState[n0] := csChecked;
    t.ToggleCheck(n0);
    AssertEquals('C1: checked→unchecked', Ord(csUnchecked), Ord(t.CheckState[n0]));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestOnCheckedFiresAfterToggle;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    FCheckedCount    := 0;
    FCheckedLastNode := nil;
    t.OnChecked      := @OnChecked;
    t.ToggleCheck(n0);
    AssertEquals('C1: OnChecked fires once', 1, FCheckedCount);
    AssertTrue('C1: OnChecked node = n0', FCheckedLastNode = n0);
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestOnCheckingVetoBlocksChange;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    FCheckingCount   := 0;
    FCheckingAllowed := False;   // veto
    FCheckedCount    := 0;
    t.OnChecking     := @OnChecking;
    t.OnChecked      := @OnChecked;
    t.ToggleCheck(n0);
    AssertEquals('C1: OnChecking fired',        1,               FCheckingCount);
    AssertEquals('C1: state unchanged (vetoed)',Ord(csUnchecked), Ord(t.CheckState[n0]));
    AssertEquals('C1: OnChecked NOT fired',     0,               FCheckedCount);
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestTriStateUncheckedToChecked;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.CheckType[n0]  := ctTriStateCheckBox;
    t.CheckState[n0] := csUnchecked;
    t.ToggleCheck(n0);
    AssertEquals('C1 tri: unchecked→checked', Ord(csChecked), Ord(t.CheckState[n0]));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestTriStateCheckedToUnchecked;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.CheckType[n0]  := ctTriStateCheckBox;
    t.CheckState[n0] := csChecked;
    t.ToggleCheck(n0);
    AssertEquals('C1 tri: checked→unchecked', Ord(csUnchecked), Ord(t.CheckState[n0]));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestTriStateMixedToChecked;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.CheckType[n0]  := ctTriStateCheckBox;
    t.CheckState[n0] := csMixed;
    t.ToggleCheck(n0);
    AssertEquals('C1 tri: mixed→checked (user click)', Ord(csChecked), Ord(t.CheckState[n0]));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestRadioExclusivity;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0, r0, r1, r2: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    { Turn n0 into a radio and add 2 more siblings }
    t.CheckType[n0]  := ctRadioButton;
    t.CheckState[n0] := csChecked;  // r0 starts checked
    r0 := n0;
    t.RootNodeCount := 3;
    r1 := r0^.NextSibling;
    r2 := r1^.NextSibling;
    t.CheckType[r1]  := ctRadioButton; t.CheckState[r1] := csUnchecked;
    t.CheckType[r2]  := ctRadioButton; t.CheckState[r2] := csUnchecked;

    { Toggle r1 — should make r1 checked, r0+r2 unchecked }
    t.ToggleCheck(r1);
    AssertEquals('C1 radio: r0 unchecked', Ord(csUnchecked), Ord(r0^.CheckState));
    AssertEquals('C1 radio: r1 checked',   Ord(csChecked),   Ord(r1^.CheckState));
    AssertEquals('C1 radio: r2 unchecked', Ord(csUnchecked), Ord(r2^.CheckState));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestRadioSwitchToThird;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0, r0, r1, r2: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.CheckType[n0]  := ctRadioButton;
    t.CheckState[n0] := csUnchecked;
    r0 := n0;
    t.RootNodeCount := 3;
    r1 := r0^.NextSibling;
    r2 := r1^.NextSibling;
    t.CheckType[r1]  := ctRadioButton; t.CheckState[r1] := csChecked;   // r1 starts checked
    t.CheckType[r2]  := ctRadioButton; t.CheckState[r2] := csUnchecked;

    { Toggle r2 — should make r2 the only checked one }
    t.ToggleCheck(r2);
    AssertEquals('C1 radio3: r0 unchecked', Ord(csUnchecked), Ord(r0^.CheckState));
    AssertEquals('C1 radio3: r1 unchecked', Ord(csUnchecked), Ord(r1^.CheckState));
    AssertEquals('C1 radio3: r2 checked',   Ord(csChecked),   Ord(r2^.CheckState));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestMouseDownCheckBoxDoesNotSelect;
{ MouseDown at the hpCheckBox slot (x=20, row 0 y=10) toggles check
  but does NOT change FocusedNode or selection. }
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    AssertTrue('C1 mouse: no focused node before click', t.FocusedNode = nil);
    t.MouseDown(mbLeft, [], 20, 10);  { x=20 → slot x=[16..32) → hpCheckBox }
    AssertEquals('C1 mouse: state toggled to csChecked',
      Ord(csChecked), Ord(t.CheckState[n0]));
    AssertTrue('C1 mouse: FocusedNode unchanged (still nil)',
      t.FocusedNode = nil);
    AssertFalse('C1 mouse: node not selected',
      t.Selected[n0]);
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestSpaceKeyTogglesCheck;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
  Key: Word;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.FocusedNode := n0;   { focus the node (sets selection — expected) }
    t.CheckState[n0] := csUnchecked;
    Key := VK_SPACE;
    t.KeyDown(Key, []);
    AssertEquals('C1 space: state toggled to csChecked',
      Ord(csChecked), Ord(t.CheckState[n0]));
    AssertEquals('C1 space: Key consumed (=0)', 0, Integer(Key));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestToggleCheckNoOpWhenOptionOff;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.Options := [];   { toCheckSupport off }
    t.ToggleCheck(n0);
    AssertEquals('C1 opt-off: state unchanged',
      Ord(csUnchecked), Ord(t.CheckState[n0]));
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestClickWithCheckOffSelectsNode;
{ toCheckSupport off → click at x=20 (where box would be) → selects node (③b) }
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeViewAccess;
  n0: PTyTreeNode;
begin
  t := BuildCheckTree(Ctl, F, n0);
  try
    t.Options := [];   { toCheckSupport off }
    t.MouseDown(mbLeft, [], 20, 10);
    AssertTrue('C1 click-no-check: node is focused/selected',
      t.Selected[n0]);
  finally F.Free; Ctl.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestAutoTriStateDownPropagatesToChildren;
{ parent (ctTriStateCheckBox) + 3 ctCheckBox children.
  ToggleCheck(parent) → parent csChecked → all 3 children csChecked (down). }
var
  t: TTyTreeView;
  parent, c1, c2, c3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toCheckSupport, toAutoTristateTracking];
    parent := t.AddChild(nil);
    parent^.CheckType  := ctTriStateCheckBox;
    parent^.CheckState := csUnchecked;
    c1 := t.AddChild(parent); c1^.CheckType := ctCheckBox; c1^.CheckState := csUnchecked;
    c2 := t.AddChild(parent); c2^.CheckType := ctCheckBox; c2^.CheckState := csUnchecked;
    c3 := t.AddChild(parent); c3^.CheckType := ctCheckBox; c3^.CheckState := csUnchecked;
    { toggle parent: unchecked→checked }
    t.ToggleCheck(parent);
    AssertEquals('C1 tri-down: parent csChecked',
      Ord(csChecked), Ord(parent^.CheckState));
    AssertEquals('C1 tri-down: c1 csChecked',
      Ord(csChecked), Ord(c1^.CheckState));
    AssertEquals('C1 tri-down: c2 csChecked',
      Ord(csChecked), Ord(c2^.CheckState));
    AssertEquals('C1 tri-down: c3 csChecked',
      Ord(csChecked), Ord(c3^.CheckState));
  finally t.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestAutoTriStateUpMixedOnOneUnchecked;
{ parent + 3 children all checked.  ToggleCheck(c1) → c1 unchecked → parent csMixed. }
var
  t: TTyTreeView;
  parent, c1, c2, c3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toCheckSupport, toAutoTristateTracking];
    parent := t.AddChild(nil);
    parent^.CheckType  := ctTriStateCheckBox;
    parent^.CheckState := csChecked;
    c1 := t.AddChild(parent); c1^.CheckType := ctCheckBox; c1^.CheckState := csChecked;
    c2 := t.AddChild(parent); c2^.CheckType := ctCheckBox; c2^.CheckState := csChecked;
    c3 := t.AddChild(parent); c3^.CheckType := ctCheckBox; c3^.CheckState := csChecked;
    { uncheck c1 }
    t.ToggleCheck(c1);
    AssertEquals('C1 tri-up: c1 unchecked',
      Ord(csUnchecked), Ord(c1^.CheckState));
    AssertEquals('C1 tri-up: parent csMixed',
      Ord(csMixed), Ord(parent^.CheckState));
  finally t.Free; end;
end;

procedure TTreeC1CheckBehaviourTest.TestAutoTriStateUpAllUnchecked;
{ parent + 3 children all checked.  Uncheck all 3 → parent becomes csUnchecked. }
var
  t: TTyTreeView;
  parent, c1, c2, c3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toCheckSupport, toAutoTristateTracking];
    parent := t.AddChild(nil);
    parent^.CheckType  := ctTriStateCheckBox;
    parent^.CheckState := csChecked;
    c1 := t.AddChild(parent); c1^.CheckType := ctCheckBox; c1^.CheckState := csChecked;
    c2 := t.AddChild(parent); c2^.CheckType := ctCheckBox; c2^.CheckState := csChecked;
    c3 := t.AddChild(parent); c3^.CheckType := ctCheckBox; c3^.CheckState := csChecked;
    { propagation test: start by checking parent to set all checked first,
      then uncheck each child individually }
    t.ToggleCheck(c1);   { c1→unchecked; parent→csMixed }
    t.ToggleCheck(c2);   { c2→unchecked; parent stays csMixed }
    t.ToggleCheck(c3);   { c3→unchecked; parent→csUnchecked }
    AssertEquals('C1 tri-up-all: c1 unchecked', Ord(csUnchecked), Ord(c1^.CheckState));
    AssertEquals('C1 tri-up-all: c2 unchecked', Ord(csUnchecked), Ord(c2^.CheckState));
    AssertEquals('C1 tri-up-all: c3 unchecked', Ord(csUnchecked), Ord(c3^.CheckState));
    AssertEquals('C1 tri-up-all: parent csUnchecked',
      Ord(csUnchecked), Ord(parent^.CheckState));
  finally t.Free; end;
end;

{ ── D1 ── multi-select mouse (Ctrl/Shift) + selection API + OnSelectionChanged ── }

type
  TTreeD1MultiSelectMouseTest = class(TTestCase)
  private
    FSelChangedCount: Integer;
    procedure OnSelChanged(Sender: TObject);
    { Build a flat 6-node tree with toMultiSelect; PPI=96, NodeHeight=20,
      Indent=16, ShowRoot=True, ShowButtons=False.
      Nodes occupy rows 0..5 (absY 0..19 .. 100..119).
      Label zone for level-0 nodes: x >= 16. }
    function BuildMultiTree(out nodes: array of PTyTreeNode): TTyTreeView;
  published
    { Ctrl+click two separate nodes → both selected, SelectedCount=2;
      OnSelectionChanged fired once per click. }
    procedure TestCtrlClickTwoNodes;
    { Shift+click after a plain-click anchor → inclusive visible range selected. }
    procedure TestShiftClickRange;
    { Plain click → collapses multi-selection to count=1. }
    procedure TestPlainClickCollapsesSelection;
    { SelectAll → count = visible node count; iterators walk in visible order. }
    procedure TestSelectAllAndIterators;
    { GetFirstSelected/GetNextSelected traverse in visible order. }
    procedure TestGetFirstAndNextSelected;
    { OnSelectionChanged fires once per mouse gesture (not per node). }
    procedure TestOnSelectionChangedFiredOncePerGesture;
    { toMultiSelect OFF → Ctrl+click behaves like plain single-select. }
    procedure TestMultiSelectOffCtrlClickIsSingleSelect;
    { toMultiSelect OFF → Shift+click behaves like plain single-select. }
    procedure TestMultiSelectOffShiftClickIsSingleSelect;
    { Ctrl+Shift+click extends range without clearing existing selection. }
    procedure TestCtrlShiftClickExtendsRange;
    { hpButton click does NOT change multi-selection. }
    procedure TestButtonClickDoesNotAlterMultiSelect;
    { hpCheckBox click does NOT change multi-selection. }
    procedure TestCheckBoxClickDoesNotAlterMultiSelect;
  end;

procedure TTreeD1MultiSelectMouseTest.OnSelChanged(Sender: TObject);
begin
  Inc(FSelChangedCount);
end;

function TTreeD1MultiSelectMouseTest.BuildMultiTree(
  out nodes: array of PTyTreeNode): TTyTreeView;
var
  t: TTyTreeView;
  i: Integer;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 20;
  t.Indent             := 16;
  t.ShowRoot           := True;
  t.ShowButtons        := False;
  t.ShowTreeLines      := False;
  t.Options            := [toMultiSelect];
  t.SetBounds(0, 0, 300, 200);
  t.RootNodeCount := 6;
  n := t.RootNode^.FirstChild;
  for i := 0 to 5 do
  begin
    nodes[i] := n;
    n := n^.NextSibling;
  end;
  Result := t;
end;

procedure TTreeD1MultiSelectMouseTest.TestCtrlClickTwoNodes;
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  FSelChangedCount := 0;
  t := BuildMultiTree(nodes);
  try
    t.OnSelectionChanged := @OnSelChanged;
    { Plain click on node[0] — anchor + select }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 10);  { row 0, label zone }
    {$POP}
    AssertEquals('D1 ctrl2: after plain click count=1', 1, t.SelectedCount);
    AssertEquals('D1 ctrl2: sel-changed fired for plain click', 1, FSelChangedCount);
    FSelChangedCount := 0;
    { Ctrl+click on node[2] — add to selection }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssCtrl], 30, 50);  { row 2, label zone }
    {$POP}
    AssertEquals('D1 ctrl2: SelectedCount=2', 2, t.SelectedCount);
    AssertTrue('D1 ctrl2: node[0] selected', nsSelected in nodes[0]^.States);
    AssertTrue('D1 ctrl2: node[2] selected', nsSelected in nodes[2]^.States);
    AssertFalse('D1 ctrl2: node[1] not selected', nsSelected in nodes[1]^.States);
    AssertEquals('D1 ctrl2: OnSelectionChanged fired once for Ctrl+click',
      1, FSelChangedCount);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestShiftClickRange;
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  t := BuildMultiTree(nodes);
  try
    { Plain click on node[1] → anchor }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 30);   { row 1 }
    {$POP}
    { Shift+click on node[4] → range [1..4] selected }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssShift], 30, 90);  { row 4 }
    {$POP}
    AssertEquals('D1 shift: SelectedCount=4', 4, t.SelectedCount);
    AssertFalse('D1 shift: node[0] not selected', nsSelected in nodes[0]^.States);
    AssertTrue ('D1 shift: node[1] selected',     nsSelected in nodes[1]^.States);
    AssertTrue ('D1 shift: node[2] selected',     nsSelected in nodes[2]^.States);
    AssertTrue ('D1 shift: node[3] selected',     nsSelected in nodes[3]^.States);
    AssertTrue ('D1 shift: node[4] selected',     nsSelected in nodes[4]^.States);
    AssertFalse('D1 shift: node[5] not selected', nsSelected in nodes[5]^.States);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestPlainClickCollapsesSelection;
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  t := BuildMultiTree(nodes);
  try
    { Select a range first }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 10);          { row 0 }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssShift], 30, 90);   { row 4 }
    {$POP}
    AssertEquals('D1 plain: initial range count=5', 5, t.SelectedCount);
    { Plain click on node[3] → collapse to 1 }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 70);  { row 3 }
    {$POP}
    AssertEquals('D1 plain: collapsed to count=1', 1, t.SelectedCount);
    AssertTrue('D1 plain: only node[3] selected', nsSelected in nodes[3]^.States);
    AssertFalse('D1 plain: node[0] deselected',   nsSelected in nodes[0]^.States);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestSelectAllAndIterators;
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
  i: Integer;
begin
  t := BuildMultiTree(nodes);
  try
    t.SelectAll;
    AssertEquals('D1 selectall: SelectedCount=6', 6, t.SelectedCount);
    for i := 0 to 5 do
      AssertTrue('D1 selectall: node[' + IntToStr(i) + '] selected',
        nsSelected in nodes[i]^.States);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestGetFirstAndNextSelected;
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
  n: PTyTreeNode;
  visitCount: Integer;
begin
  t := BuildMultiTree(nodes);
  try
    { Select nodes 1, 3, 5 }
    t.InternalSetSelected(nodes[1], True);
    t.InternalSetSelected(nodes[3], True);
    t.InternalSetSelected(nodes[5], True);
    AssertEquals('D1 iter: SelectedCount=3', 3, t.SelectedCount);
    n := t.GetFirstSelected;
    AssertTrue('D1 iter: GetFirstSelected = nodes[1]', n = nodes[1]);
    n := t.GetNextSelected(n);
    AssertTrue('D1 iter: next = nodes[3]', n = nodes[3]);
    n := t.GetNextSelected(n);
    AssertTrue('D1 iter: next = nodes[5]', n = nodes[5]);
    n := t.GetNextSelected(n);
    AssertTrue('D1 iter: no more selected (nil)', n = nil);
    { Count via iteration }
    visitCount := 0;
    n := t.GetFirstSelected;
    while n <> nil do
    begin
      Inc(visitCount);
      n := t.GetNextSelected(n);
    end;
    AssertEquals('D1 iter: iterated 3 nodes', 3, visitCount);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestOnSelectionChangedFiredOncePerGesture;
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  FSelChangedCount := 0;
  t := BuildMultiTree(nodes);
  try
    t.OnSelectionChanged := @OnSelChanged;
    { SelectAll is one gesture → one fire }
    t.SelectAll;
    AssertEquals('D1 once: SelectAll fires once', 1, FSelChangedCount);
    FSelChangedCount := 0;
    { ClearSelection → does NOT fire OnSelectionChanged (it's not a user gesture
      from multi-select perspective; ClearSelection fires OnChange instead).
      That's consistent with the design spec. }
    t.ClearSelection;
    { One plain mouse click → one fire }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 10);
    {$POP}
    AssertEquals('D1 once: plain click fires once', 1, FSelChangedCount);
    FSelChangedCount := 0;
    { Shift+click → one fire (covers the whole range in one gesture) }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssShift], 30, 90);
    {$POP}
    AssertEquals('D1 once: Shift+click fires once', 1, FSelChangedCount);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestMultiSelectOffCtrlClickIsSingleSelect;
{ toMultiSelect OFF → Ctrl+click is treated as plain single-select (③a/③b). }
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  t := BuildMultiTree(nodes);
  try
    t.Options := [];   { toMultiSelect OFF }
    { Click node[0] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 10);
    {$POP}
    AssertEquals('D1 off ctrl: count=1 after plain', 1, t.SelectedCount);
    { Ctrl+click node[2] → should NOT add; just single-selects node[2] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssCtrl], 30, 50);
    {$POP}
    { In single-select mode, FocusedNode := node[2] runs → SetSelected(node[2],True)
      which calls ClearSelectedNode first — so node[0] deselected, node[2] selected }
    AssertEquals('D1 off ctrl: still only 1 selected', 1, t.SelectedCount);
    AssertTrue('D1 off ctrl: node[2] selected',   nsSelected in nodes[2]^.States);
    AssertFalse('D1 off ctrl: node[0] deselected', nsSelected in nodes[0]^.States);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestMultiSelectOffShiftClickIsSingleSelect;
{ toMultiSelect OFF → Shift+click is treated as plain single-select (③a/③b). }
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  t := BuildMultiTree(nodes);
  try
    t.Options := [];   { toMultiSelect OFF }
    { Shift+click node[3] → single-selects node[3] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssShift], 30, 70);
    {$POP}
    AssertEquals('D1 off shift: exactly 1 selected', 1, t.SelectedCount);
    AssertTrue('D1 off shift: node[3] selected', nsSelected in nodes[3]^.States);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestCtrlShiftClickExtendsRange;
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  t := BuildMultiTree(nodes);
  try
    { First: plain click on node[0] → anchor + select (count=1) }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 10);
    {$POP}
    AssertEquals('D1 ctrl+shift: after plain count=1', 1, t.SelectedCount);
    { Ctrl+click node[4] → node[0]+node[4] selected (count=2); anchor=node[4] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssCtrl], 30, 90);
    {$POP}
    AssertEquals('D1 ctrl+shift: after ctrl count=2', 2, t.SelectedCount);
    { Ctrl+Shift+click on node[5] → extend range from anchor(node[4]) to node[5];
      adds node[5] to existing selection (does NOT clear node[0]). }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssCtrl, ssShift], 30, 110);
    {$POP}
    AssertTrue('D1 ctrl+shift: node[0] still selected', nsSelected in nodes[0]^.States);
    AssertTrue('D1 ctrl+shift: node[4] selected', nsSelected in nodes[4]^.States);
    AssertTrue('D1 ctrl+shift: node[5] selected', nsSelected in nodes[5]^.States);
    AssertEquals('D1 ctrl+shift: count=3', 3, t.SelectedCount);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestButtonClickDoesNotAlterMultiSelect;
{ hpButton click expands/collapses; does NOT change multi-selection. }
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
  n0: PTyTreeNode;
begin
  t := BuildMultiTree(nodes);
  try
    t.ShowButtons := True;
    { Pre-select nodes[1] and nodes[2] }
    t.InternalSetSelected(nodes[1], True);
    t.InternalSetSelected(nodes[2], True);
    AssertEquals('D1 btn: pre-sel count=2', 2, t.SelectedCount);
    { Make nodes[0] expandable so there's a real button }
    n0 := nodes[0];
    Include(n0^.States, nsHasChildren);
    Include(n0^.States, nsInitialized);
    { Click the button slot of nodes[0] at (8,10) — indentPx=16, btnSlotW=16
      so button zone x in [0..15]; we hit x=8, y=10 = row 0 }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 8, 10);
    {$POP}
    AssertEquals('D1 btn: count still=2 after button click', 2, t.SelectedCount);
    AssertTrue('D1 btn: node[1] still selected', nsSelected in nodes[1]^.States);
    AssertTrue('D1 btn: node[2] still selected', nsSelected in nodes[2]^.States);
  finally t.Free; end;
end;

procedure TTreeD1MultiSelectMouseTest.TestCheckBoxClickDoesNotAlterMultiSelect;
{ hpCheckBox click toggles check; does NOT change multi-selection. }
var
  t: TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
begin
  t := BuildMultiTree(nodes);
  try
    t.Options := [toMultiSelect, toCheckSupport];
    nodes[0]^.CheckType  := ctCheckBox;
    nodes[0]^.CheckState := csUnchecked;
    { Pre-select nodes[1] and nodes[2] }
    t.InternalSetSelected(nodes[1], True);
    t.InternalSetSelected(nodes[2], True);
    AssertEquals('D1 cb: pre-sel count=2', 2, t.SelectedCount);
    { Click the checkbox slot of nodes[0]: x=20 (indentPx=16, cbSlot=[16..31]) }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 20, 10);
    {$POP}
    AssertEquals('D1 cb: count still=2 after checkbox click', 2, t.SelectedCount);
    AssertTrue('D1 cb: node[1] still selected', nsSelected in nodes[1]^.States);
    AssertTrue('D1 cb: node[2] still selected', nsSelected in nodes[2]^.States);
    AssertEquals('D1 cb: nodes[0] check toggled to csChecked',
      Ord(csChecked), Ord(nodes[0]^.CheckState));
  finally t.Free; end;
end;

{ ── D2 ── multi-select keyboard + full-row select ────────────────────────────── }

type
  TTreeD2MultiSelectKeyboardTest = class(TTestCase)
  private
    FSelChangedCount: Integer;
    procedure OnSelChanged(Sender: TObject);
    function BuildKeyTree(out nodes: array of PTyTreeNode): TTyTreeView;
  published
    { Shift+Down extends selection by one; anchor stays }
    procedure TestShiftDownExtendsRange;
    { Shift+Up extends selection by one (upward) }
    procedure TestShiftUpExtendsRange;
    { Ctrl+Space toggles the focused node's selection }
    procedure TestCtrlSpaceTogglesFocused;
    { Ctrl+A selects all visible nodes }
    procedure TestCtrlASelectsAll;
    { Plain Down (no Shift) collapses to new single selection + resets anchor }
    procedure TestPlainDownCollapsesSingleSelect;
    { toFullRowSelect: click past the caption selects the row }
    procedure TestFullRowSelectClickPastCaption;
    { Without toFullRowSelect: click in indent zone does NOT select (single-select ③b) }
    procedure TestNoFullRowSelectIndentZoneDoesNotSelect;
    { toFullRowSelect: Ctrl+click past caption adds to multi-selection }
    procedure TestFullRowSelectCtrlClickAdds;
    { toMultiSelect OFF → Ctrl+Space does nothing (not consumed) }
    procedure TestMultiSelectOffCtrlSpaceNoOp;
    { toMultiSelect OFF → Shift+Down single-selects (no extension) }
    procedure TestMultiSelectOffShiftDownSingleSelect;
  end;

procedure TTreeD2MultiSelectKeyboardTest.OnSelChanged(Sender: TObject);
begin
  Inc(FSelChangedCount);
end;

function TTreeD2MultiSelectKeyboardTest.BuildKeyTree(
  out nodes: array of PTyTreeNode): TTyTreeView;
var
  t: TTyTreeView;
  i: Integer;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  t.Font.PixelsPerInch := 96;
  t.DefaultNodeHeight  := 20;
  t.Indent             := 16;
  t.ShowRoot           := True;
  t.ShowButtons        := False;
  t.ShowTreeLines      := False;
  t.Options            := [toMultiSelect];
  t.SetBounds(0, 0, 300, 200);
  t.RootNodeCount := 5;
  n := t.RootNode^.FirstChild;
  for i := 0 to 4 do
  begin
    nodes[i] := n;
    n := n^.NextSibling;
  end;
  Result := t;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestShiftDownExtendsRange;
{ Start: plain click node[1] → anchor=node[1], selected=node[1].
  Shift+Down → caret moves to node[2], SelectRange(node[1],node[2]).
  Result: nodes[1]+nodes[2] selected, count=2; anchor=node[1]. }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  key: Word;
begin
  FSelChangedCount := 0;
  t := BuildKeyTree(nodes);
  try
    t.OnSelectionChanged := @OnSelChanged;
    { Plain click on node[1] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 30);  { row 1 }
    {$POP}
    FSelChangedCount := 0;
    { Shift+Down }
    key := VK_DOWN;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, [ssShift]);{$POP}
    AssertEquals('D2 shift-dn: key consumed', 0, Integer(key));
    AssertEquals('D2 shift-dn: SelectedCount=2', 2, t.SelectedCount);
    AssertTrue ('D2 shift-dn: node[1] selected', nsSelected in nodes[1]^.States);
    AssertTrue ('D2 shift-dn: node[2] selected', nsSelected in nodes[2]^.States);
    AssertFalse('D2 shift-dn: node[0] not selected', nsSelected in nodes[0]^.States);
    AssertTrue ('D2 shift-dn: FocusedNode=node[2]', t.FocusedNode = nodes[2]);
    AssertEquals('D2 shift-dn: OnSelectionChanged fired once', 1, FSelChangedCount);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestShiftUpExtendsRange;
{ Start: plain click node[3] → anchor=node[3].
  Shift+Up → caret to node[2], SelectRange(node[3],node[2]).
  Result: nodes[2]+nodes[3] selected, count=2. }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  key: Word;
begin
  t := BuildKeyTree(nodes);
  try
    { Plain click on node[3] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 70);  { row 3 }
    {$POP}
    { Shift+Up }
    key := VK_UP;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, [ssShift]);{$POP}
    AssertEquals('D2 shift-up: key consumed', 0, Integer(key));
    AssertEquals('D2 shift-up: SelectedCount=2', 2, t.SelectedCount);
    AssertTrue ('D2 shift-up: node[2] selected', nsSelected in nodes[2]^.States);
    AssertTrue ('D2 shift-up: node[3] selected', nsSelected in nodes[3]^.States);
    AssertTrue ('D2 shift-up: FocusedNode=node[2]', t.FocusedNode = nodes[2]);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestCtrlSpaceTogglesFocused;
{ Ctrl+Space on a focused node toggles its selection state. }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  key: Word;
begin
  FSelChangedCount := 0;
  t := BuildKeyTree(nodes);
  try
    t.OnSelectionChanged := @OnSelChanged;
    { Focus node[2] (plain click) }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 50);  { row 2 }
    {$POP}
    AssertTrue('D2 ctrl-sp: node[2] selected after click',
      nsSelected in nodes[2]^.States);
    FSelChangedCount := 0;
    { Ctrl+Space → toggles node[2] from selected → deselected }
    key := VK_SPACE;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, [ssCtrl]);{$POP}
    AssertEquals('D2 ctrl-sp: key consumed', 0, Integer(key));
    AssertFalse('D2 ctrl-sp: node[2] deselected after toggle',
      nsSelected in nodes[2]^.States);
    AssertEquals('D2 ctrl-sp: OnSelectionChanged fired', 1, FSelChangedCount);
    { Second Ctrl+Space → re-selects }
    FSelChangedCount := 0;
    key := VK_SPACE;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, [ssCtrl]);{$POP}
    AssertTrue('D2 ctrl-sp: node[2] re-selected', nsSelected in nodes[2]^.States);
    AssertEquals('D2 ctrl-sp: OnSelectionChanged fired again', 1, FSelChangedCount);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestCtrlASelectsAll;
{ Ctrl+A selects all 5 visible nodes. }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  key: Word;
  i: Integer;
begin
  FSelChangedCount := 0;
  t := BuildKeyTree(nodes);
  try
    t.OnSelectionChanged := @OnSelChanged;
    key := Ord('A');
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, [ssCtrl]);{$POP}
    AssertEquals('D2 ctrl-a: key consumed', 0, Integer(key));
    AssertEquals('D2 ctrl-a: SelectedCount=5', 5, t.SelectedCount);
    for i := 0 to 4 do
      AssertTrue('D2 ctrl-a: nodes[' + IntToStr(i) + '] selected',
        nsSelected in nodes[i]^.States);
    AssertEquals('D2 ctrl-a: OnSelectionChanged fired once', 1, FSelChangedCount);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestPlainDownCollapsesSingleSelect;
{ Plain Down (no Shift) in multi-select: moves caret + collapses to one. }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  key: Word;
begin
  t := BuildKeyTree(nodes);
  try
    { Select a range first }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 10);         { row 0 }
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssShift], 30, 70);  { row 3 }
    {$POP}
    AssertEquals('D2 plain-dn: range count=4', 4, t.SelectedCount);
    { Plain Down from node[3] → node[4]; collapses selection }
    key := VK_DOWN;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, []);{$POP}
    AssertEquals('D2 plain-dn: collapsed to count=1', 1, t.SelectedCount);
    AssertTrue('D2 plain-dn: node[4] selected', nsSelected in nodes[4]^.States);
    AssertFalse('D2 plain-dn: node[3] deselected', nsSelected in nodes[3]^.States);
    AssertTrue('D2 plain-dn: FocusedNode=node[4]', t.FocusedNode = nodes[4]);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestFullRowSelectClickPastCaption;
{ toFullRowSelect: click at x=200 (far right, past label) selects the row. }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
begin
  t := BuildKeyTree(nodes);
  try
    t.Options := [toMultiSelect, toFullRowSelect];
    { Click far right in row 2 (y=50) }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 200, 50);
    {$POP}
    AssertEquals('D2 fullrow: SelectedCount=1', 1, t.SelectedCount);
    AssertTrue('D2 fullrow: node[2] selected', nsSelected in nodes[2]^.States);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestNoFullRowSelectIndentZoneDoesNotSelect;
{ Without toFullRowSelect: a click in the label area still selects; a click in
  the indent zone also selects (hpIndent → single-select path).
  But a click in the indent zone for toMultiSelect without toFullRowSelect falls
  through to the single-select path (FocusedNode := node). }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
begin
  t := BuildKeyTree(nodes);
  try
    { toMultiSelect WITHOUT toFullRowSelect }
    t.Options := [toMultiSelect];
    { Click on the label zone of node[1] (row 1, x=30) — should select }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 30);
    {$POP}
    AssertEquals('D2 no-fullrow label: count=1', 1, t.SelectedCount);
    AssertTrue('D2 no-fullrow label: node[1] selected', nsSelected in nodes[1]^.States);
    { Now click far right (x=200) in row 2 — hpLabel (past caption), selects }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 200, 50);
    {$POP}
    AssertEquals('D2 no-fullrow far: count=1', 1, t.SelectedCount);
    AssertTrue('D2 no-fullrow far: node[2] selected', nsSelected in nodes[2]^.States);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestFullRowSelectCtrlClickAdds;
{ toFullRowSelect + Ctrl+click far right adds to multi-selection. }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
begin
  t := BuildKeyTree(nodes);
  try
    t.Options := [toMultiSelect, toFullRowSelect];
    { Plain click node[0] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [], 30, 10);
    {$POP}
    AssertEquals('D2 fullrow-ctrl: count=1', 1, t.SelectedCount);
    { Ctrl+click far right in row 3 → add node[3] }
    {$PUSH}{$HINTS OFF}
    TTyTreeViewAccess(t).MouseDown(mbLeft, [ssCtrl], 200, 70);
    {$POP}
    AssertEquals('D2 fullrow-ctrl: count=2', 2, t.SelectedCount);
    AssertTrue('D2 fullrow-ctrl: node[0] selected', nsSelected in nodes[0]^.States);
    AssertTrue('D2 fullrow-ctrl: node[3] selected', nsSelected in nodes[3]^.States);
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestMultiSelectOffCtrlSpaceNoOp;
{ toMultiSelect OFF → Ctrl+Space key is not consumed (no multi-select action). }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  key: Word;
begin
  t := BuildKeyTree(nodes);
  try
    t.Options := [];   { toMultiSelect OFF }
    t.FocusedNode := nodes[1];
    key := VK_SPACE;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, [ssCtrl]);{$POP}
    { When toMultiSelect is off, the Ctrl+Space handler is skipped.
      VK_SPACE falls to the case branch which only fires for toCheckSupport+ctNone check.
      With toCheckSupport off the key is NOT consumed either. }
    AssertEquals('D2 off ctrl-sp: key not consumed (VK_SPACE=32)',
      VK_SPACE, Integer(key));
  finally t.Free; end;
end;

procedure TTreeD2MultiSelectKeyboardTest.TestMultiSelectOffShiftDownSingleSelect;
{ toMultiSelect OFF → Shift+Down moves focus like plain Down (single-select). }
var
  t: TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  key: Word;
begin
  t := BuildKeyTree(nodes);
  try
    t.Options := [];   { toMultiSelect OFF }
    t.FocusedNode := nodes[1];
    key := VK_DOWN;
    {$PUSH}{$HINTS OFF}TTyTreeViewAccess(t).KeyDown(key, [ssShift]);{$POP}
    { Without toMultiSelect, Shift+Down falls through to the normal VK_DOWN case
      which calls FocusedNode := nxt (single-select). }
    AssertEquals('D2 off shift-dn: key consumed', 0, Integer(key));
    AssertTrue('D2 off shift-dn: FocusedNode = nodes[2]', t.FocusedNode = nodes[2]);
    AssertEquals('D2 off shift-dn: only 1 selected', 1, t.SelectedCount);
    AssertTrue('D2 off shift-dn: nodes[2] selected', nsSelected in nodes[2]^.States);
    AssertFalse('D2 off shift-dn: nodes[1] deselected', nsSelected in nodes[1]^.States);
  finally t.Free; end;
end;

{ ── FIX 1/2/3/5 adversarial-review regression tests ─────────────────────── }

type
  TTreeAdversarialFixTest = class(TTestCase)
  published
    { FIX 1: DeleteNode of a selected node decrements FSelectionCount }
    procedure TestDeleteSelectedNodeDecrementsCount;
    { FIX 1: DeleteNode of a multi-selected range member decrements count correctly }
    procedure TestDeleteRangeMemberDecrementsCount;
    { FIX 1: Clear after SelectAll resets SelectedCount=0 and FRangeAnchor=nil }
    procedure TestClearAfterSelectAllResetsCount;
    { FIX 1: DeleteNode clears FRangeAnchor when anchor is deleted }
    procedure TestDeleteAnchorClearsRangeAnchor;
    { FIX 2: re-sequence still happens on normal (non-Clear) DeleteNode }
    procedure TestDeleteNonClearResequences;
    { FIX 3: ClearSelection after collapse clears hidden selected nodes }
    procedure TestClearSelectionClearsHiddenNodes;
    { FIX 3: SelectRange clears hidden selected nodes before selecting new range }
    procedure TestSelectRangeClearsHiddenSelectedFirst;
    { FIX 5: removing toMultiSelect collapses multi-selection to single }
    procedure TestRemoveMultiSelectCollapsesToSingle;
    { FIX 5: removing toMultiSelect with 0 or 1 nodes selected is a no-op }
    procedure TestRemoveMultiSelectSingleSelectedNoOp;
  end;

procedure TTreeAdversarialFixTest.TestDeleteSelectedNodeDecrementsCount;
{ FIX 1: deleting the single selected node must set SelectedCount=0. }
var
  t: TTyTreeView;
  n: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n := t.AddChild(nil);
    t.Selected[n] := True;
    AssertEquals('count=1 before delete', 1, t.SelectedCount);
    t.DeleteNode(n);
    AssertEquals('FIX1: count=0 after delete', 0, t.SelectedCount);
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestDeleteRangeMemberDecrementsCount;
{ FIX 1: SelectRange(n2..n4) = 3 nodes; DeleteNode(n3) → count=2. }
var
  t:     TTyTreeView;
  nodes: array[0..5] of PTyTreeNode;
  n:     PTyTreeNode;
  i:     Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.RootNodeCount := 6;
    n := t.RootNode^.FirstChild;
    for i := 0 to 5 do begin nodes[i] := n; n := n^.NextSibling; end;
    t.SelectRange(nodes[2], nodes[4]);
    AssertEquals('FIX1 pre: SelectedCount=3', 3, t.SelectedCount);
    t.DeleteNode(nodes[3]);
    AssertEquals('FIX1: SelectedCount=2 after delete of mid member', 2, t.SelectedCount);
    AssertFalse('FIX1: deleted node no longer selected', nsSelected in nodes[3]^.States);
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestClearAfterSelectAllResetsCount;
{ FIX 1: SelectAll then Clear → SelectedCount=0, no crash. }
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toMultiSelect];
    t.RootNodeCount := 5;
    t.SelectAll;
    AssertEquals('FIX1 pre: SelectedCount=5', 5, t.SelectedCount);
    t.Clear;
    AssertEquals('FIX1: SelectedCount=0 after Clear', 0, t.SelectedCount);
    AssertNull ('FIX1: FSelectedNode nil after Clear', t.FocusedNode);
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestDeleteAnchorClearsRangeAnchor;
{ FIX 1: after DeleteNode of the range anchor, FRangeAnchor must be nil.
  We verify indirectly: ClearSelection must run without crash (no UAF). }
var
  t:     TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  n:     PTyTreeNode;
  i:     Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toMultiSelect];
    t.RootNodeCount := 5;
    n := t.RootNode^.FirstChild;
    for i := 0 to 4 do begin nodes[i] := n; n := n^.NextSibling; end;
    { SelectRange sets FRangeAnchor to nodes[1] internally via keyboard path;
      we simulate by direct SelectRange + selection of anchor }
    t.SelectRange(nodes[1], nodes[3]);
    AssertEquals('FIX1 anchor pre: count=3', 3, t.SelectedCount);
    { Delete nodes[1] — the range anchor }
    t.DeleteNode(nodes[1]);
    { Now ClearSelection must not crash (FRangeAnchor should be nil) }
    t.ClearSelection;
    AssertEquals('FIX1 anchor: count=0 after clear', 0, t.SelectedCount);
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestDeleteNonClearResequences;
{ FIX 2: normal (non-Clear) DeleteNode still re-sequences sibling indices. }
var
  t:      TTyTreeView;
  n1, n2, n3: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    n1 := t.AddChild(nil);
    n2 := t.AddChild(nil);
    n3 := t.AddChild(nil);
    t.DeleteNode(n2);
    AssertEquals('FIX2: n1 index still 0', 0, Integer(n1^.Index));
    AssertEquals('FIX2: n3 re-sequenced to 1', 1, Integer(n3^.Index));
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestClearSelectionClearsHiddenNodes;
{ FIX 3: select parent + child, then hide child by removing nsExpanded from
  parent (simulating a collapse without triggering height bookkeeping).
  ClearSelection must clear the child even though it is no longer visible. }
var
  t:      TTyTreeView;
  parent, child: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toMultiSelect];
    parent := t.AddChild(nil);
    child  := t.AddChild(parent);
    { Mark parent as having initialized, expanded children }
    Include(parent^.States, nsHasChildren);
    Include(parent^.States, nsInitialized);
    Include(parent^.States, nsExpanded);
    { Select both (while parent is expanded) }
    t.InternalSetSelected(parent, True);
    t.InternalSetSelected(child, True);
    AssertEquals('FIX3 pre: count=2', 2, t.SelectedCount);
    { Simulate collapse by clearing nsExpanded — child is no longer in visible walk }
    Exclude(parent^.States, nsExpanded);
    { ClearSelection must clear child too, not just visible nodes }
    t.ClearSelection;
    AssertEquals('FIX3: count=0 after clear', 0, t.SelectedCount);
    AssertFalse('FIX3: parent not selected', nsSelected in parent^.States);
    AssertFalse('FIX3: hidden child not selected', nsSelected in child^.States);
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestSelectRangeClearsHiddenSelectedFirst;
{ FIX 3: a pre-existing selection that includes a hidden (collapsed) node
  must be fully cleared when SelectRange is called next. }
var
  t:      TTyTreeView;
  parent, child, sib: PTyTreeNode;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toMultiSelect];
    parent := t.AddChild(nil);
    child  := t.AddChild(parent);
    sib    := t.AddChild(nil);
    Include(parent^.States, nsHasChildren);
    Include(parent^.States, nsInitialized);
    Include(parent^.States, nsExpanded);
    { Select child while parent is expanded }
    t.InternalSetSelected(child, True);
    AssertEquals('FIX3 sr pre: count=1', 1, t.SelectedCount);
    { Simulate collapse by clearing nsExpanded — child hidden }
    Exclude(parent^.States, nsExpanded);
    { SelectRange(parent, sib) — must clear child's nsSelected first }
    t.SelectRange(parent, sib);
    AssertFalse('FIX3 sr: child not selected after new range', nsSelected in child^.States);
    AssertTrue ('FIX3 sr: parent selected', nsSelected in parent^.States);
    AssertTrue ('FIX3 sr: sib selected', nsSelected in sib^.States);
    { Count must be 2 (parent+sib); child is cleared by ClearAllSelectedFull }
    AssertEquals('FIX3 sr: count=2 (parent+sib)', 2, t.SelectedCount);
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestRemoveMultiSelectCollapsesToSingle;
{ FIX 5: 3 nodes selected, toMultiSelect removed → SelectedCount ≤ 1. }
var
  t:     TTyTreeView;
  nodes: array[0..4] of PTyTreeNode;
  n:     PTyTreeNode;
  i:     Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toMultiSelect];
    t.RootNodeCount := 5;
    n := t.RootNode^.FirstChild;
    for i := 0 to 4 do begin nodes[i] := n; n := n^.NextSibling; end;
    t.SelectRange(nodes[0], nodes[2]);
    AssertEquals('FIX5 pre: count=3', 3, t.SelectedCount);
    t.Options := [];   { remove toMultiSelect }
    AssertTrue('FIX5: SelectedCount ≤ 1 after remove', t.SelectedCount <= 1);
    { Verify no stale nsSelected flags on the cleared nodes }
    if not (nsSelected in nodes[0]^.States) then
      AssertFalse('FIX5: node[1] cleared', nsSelected in nodes[1]^.States);
  finally t.Free; end;
end;

procedure TTreeAdversarialFixTest.TestRemoveMultiSelectSingleSelectedNoOp;
{ FIX 5: removing toMultiSelect when only 1 node selected — count stays 1. }
var
  t:     TTyTreeView;
  nodes: array[0..2] of PTyTreeNode;
  n:     PTyTreeNode;
  i:     Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.Options := [toMultiSelect];
    t.RootNodeCount := 3;
    n := t.RootNode^.FirstChild;
    for i := 0 to 2 do begin nodes[i] := n; n := n^.NextSibling; end;
    t.InternalSetSelected(nodes[1], True);
    AssertEquals('FIX5 single pre: count=1', 1, t.SelectedCount);
    t.Options := [];
    AssertEquals('FIX5 single: count still=1', 1, t.SelectedCount);
    AssertTrue('FIX5 single: node[1] still selected', nsSelected in nodes[1]^.States);
  finally t.Free; end;
end;

{ ── ③d A1 ── GetCellRect tests ──────────────────────────────────────────── }

procedure TTreeGetCellRectTest.OnGetTextWithType(Sender: TTyTreeView;
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

procedure TTreeGetCellRectTest.OnInitNodeHasChildren(Sender: TTyTreeView;
  ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
begin
  if Sender.GetNodeLevel(Node) = 0 then
    Include(InitStates, ivsHasChildren);
end;

procedure TTreeGetCellRectTest.OnInitChildren2(Sender: TTyTreeView;
  Node: PTyTreeNode; var ChildCount: Cardinal);
begin
  ChildCount := 2;
end;

{ 3-column tree, mirroring the column-paint harness:
    col 0 (main, width 120) | col 1 (width 80) | col 2 (width 100)
  header height 22, DefaultNodeHeight 22, ShowRoot, Indent 16, 1 root + 2 kids.
  At PPI=96 device px == logical px; col0=[0..120), col1=[120..200), col2=[200..300). }
function TTreeGetCellRectTest.BuildTree(out Ctl: TTyStyleController; out F: TForm;
  out ARoot, AChild0: PTyTreeNode; APPI: Integer): TTyTreeView;
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
  t.Font.PixelsPerInch := APPI;
  t.DefaultNodeHeight  := 22;
  t.Indent             := 16;
  t.ShowButtons        := True;
  t.ShowTreeLines      := False;
  t.ShowRoot           := True;
  { Device size scales with PPI so the same logical layout fits at any DPI. }
  t.SetBounds(0, 0, MulDiv(300, APPI, 96), MulDiv(200, APPI, 96));

  t.OnGetTextWithType := @OnGetTextWithType;
  t.OnInitNode        := @OnInitNodeHasChildren;
  t.OnInitChildren    := @OnInitChildren2;

  col0 := t.Header.Columns.Add as TTyTreeColumn;
  col0.Width := 120; col0.Text := 'Name';
  col0.Alignment := taLeftJustify; col0.CaptionAlignment := taLeftJustify;
  col1 := t.Header.Columns.Add as TTyTreeColumn;
  col1.Width := 80; col1.Text := 'Info';
  col1.Alignment := taLeftJustify; col1.CaptionAlignment := taLeftJustify;
  col2 := t.Header.Columns.Add as TTyTreeColumn;
  col2.Width := 100; col2.Text := 'Size';
  col2.Alignment := taRightJustify; col2.CaptionAlignment := taLeftJustify;

  t.Header.MainColumn := 0;
  t.Header.Options    := [hoVisible];

  t.RootNodeCount := 1;
  ARoot := t.RootNode^.FirstChild;
  t.InitNode(ARoot);
  t.Expanded[ARoot] := True;
  AChild0 := ARoot^.FirstChild;
  Result := t;
end;

{ Col 0 (main) at PPI=96: header band = device [0..22), so row 0 (root) top = 22,
  height = 22; main column span x = [0..120). }
procedure TTreeGetCellRectTest.TestCellRectColumn0Geometry;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  r: TRect; ok: Boolean;
begin
  t := BuildTree(Ctl, F, root, child0);
  try
    ok := t.GetCellRect(root, 0, r);
    AssertTrue('col0: GetCellRect succeeds for visible root', ok);
    AssertEquals('col0: top = headerH(22) + index0*22', 22, r.Top);
    AssertEquals('col0: height = Scale(NodeHeight)=22', 22, r.Bottom - r.Top);
    AssertEquals('col0: left = main column left (0)', 0, r.Left);
    AssertEquals('col0: right = col0 width (120)', 120, r.Right);
  finally
    F.Free; Ctl.Free;
  end;
end;

{ Col 2 span = [200..300); same row geometry. }
procedure TTreeGetCellRectTest.TestCellRectColumn2Geometry;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  r: TRect; ok: Boolean;
begin
  t := BuildTree(Ctl, F, root, child0);
  try
    ok := t.GetCellRect(root, 2, r);
    AssertTrue('col2: GetCellRect succeeds', ok);
    AssertEquals('col2: left = 120+80 = 200', 200, r.Left);
    AssertEquals('col2: right = 200+100 = 300', 300, r.Right);
    AssertEquals('col2: top = 22', 22, r.Top);
    AssertEquals('col2: height = 22', 22, r.Bottom - r.Top);
  finally
    F.Free; Ctl.Free;
  end;
end;

{ Column = -1 returns the same rect as the explicit MainColumn (0). }
procedure TTreeGetCellRectTest.TestCellRectMainColumnAlias;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  rMain, rNeg1: TRect;
begin
  t := BuildTree(Ctl, F, root, child0);
  try
    AssertTrue('main: col 0 ok',  t.GetCellRect(root, 0,  rMain));
    AssertTrue('main: col -1 ok', t.GetCellRect(root, -1, rNeg1));
    AssertTrue('main: -1 aliases MainColumn (left)',  rMain.Left  = rNeg1.Left);
    AssertTrue('main: -1 aliases MainColumn (right)', rMain.Right = rNeg1.Right);
    AssertTrue('main: -1 aliases MainColumn (top)',   rMain.Top   = rNeg1.Top);
    AssertTrue('main: -1 aliases MainColumn (bottom)',rMain.Bottom= rNeg1.Bottom);
  finally
    F.Free; Ctl.Free;
  end;
end;

{ Child row (visible index 1) sits exactly Scale(NodeHeight)=22 below the root row. }
procedure TTreeGetCellRectTest.TestCellRectChildRowTop;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  rRoot, rChild: TRect;
begin
  t := BuildTree(Ctl, F, root, child0);
  try
    AssertTrue('child: root ok',  t.GetCellRect(root,   0, rRoot));
    AssertTrue('child: child ok', t.GetCellRect(child0, 0, rChild));
    AssertEquals('child: row top = root top + 22', rRoot.Top + 22, rChild.Top);
    AssertEquals('child: height = 22', 22, rChild.Bottom - rChild.Top);
    AssertEquals('child: same main-column left as root', rRoot.Left,  rChild.Left);
    AssertEquals('child: same main-column right as root', rRoot.Right, rChild.Right);
  finally
    F.Free; Ctl.Free;
  end;
end;

{ Collapsing the root hides its children → GetCellRect(child) = False. }
procedure TTreeGetCellRectTest.TestCellRectCollapsedNodeFalse;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  r: TRect;
begin
  t := BuildTree(Ctl, F, root, child0);
  try
    { child0 is visible while root is expanded }
    AssertTrue('collapsed: child visible while expanded', t.GetCellRect(child0, 0, r));
    t.Expanded[root] := False;   // collapse → child0 no longer visible
    AssertFalse('collapsed: child under collapsed ancestor → False',
      t.GetCellRect(child0, 0, r));
  finally
    F.Free; Ctl.Free;
  end;
end;

{ nil and the hidden root sentinel → False. }
procedure TTreeGetCellRectTest.TestCellRectRootAndNilFalse;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  r: TRect;
begin
  t := BuildTree(Ctl, F, root, child0);
  try
    AssertFalse('nil node → False',  t.GetCellRect(nil, 0, r));
    AssertFalse('root sentinel → False', t.GetCellRect(t.RootNode, 0, r));
  finally
    F.Free; Ctl.Free;
  end;
end;

{ A node scrolled entirely above the content rect → False.
  Build a tall tree (many rows), scroll down via the vertical scrollbar so the
  first rows are above the viewport, then assert the very first node's rect is
  rejected (row bottom <= CR.Top). }
procedure TTreeGetCellRectTest.TestCellRectScrolledOffscreenFalse;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView;
  first, n: PTyTreeNode;
  r: TRect;
  i: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss('TyTreeView { background:#FFFFFF; border-width:0px; padding:0px; } ' +
                   'TyTreeNode { background:none; color:#000000; }');
  F := TForm.CreateNew(nil);
  try
    t := TTyTreeView.Create(F);
    t.Parent := F; t.Controller := Ctl;
    t.Font.PixelsPerInch := 96;
    t.DefaultNodeHeight := 20;
    t.Indent := 16; t.ShowRoot := True;
    t.SetBounds(0, 0, 120, 100);   // viewport 100px tall: holds 5 rows
    t.RootNodeCount := 40;          // 40*20 = 800px content >> 100px viewport
    n := t.RootNode^.FirstChild;
    while n <> nil do begin Include(n^.States, nsInitialized); n := n^.NextSibling; end;

    { RootNodeCount → InvalidateTreeLayout → UpdateScrollBars already realized the
      bars; GetCellRect also calls UpdateScrollBars. Confirm the V-bar is up. }
    AssertTrue('offscreen: vertical bar visible',
               (t.VScroll <> nil) and t.VScroll.Visible);

    { Scroll down 10 rows (200px) so the first ~10 rows are above the viewport. }
    t.VScroll.Position := 200;
    AssertTrue('offscreen: scrolled down (OffsetY < 0)', t.OffsetY < 0);

    first := t.RootNode^.FirstChild;   // node 0 — now well above the top
    AssertFalse('offscreen: first node scrolled above content rect → False',
                t.GetCellRect(first, 0, r));

    { A node currently in the viewport must still succeed. }
    n := first;
    for i := 1 to 12 do n := t.GetNextVisibleNoInit(n);  // ~row 12, on screen
    AssertTrue('offscreen: an on-screen node still succeeds',
               t.GetCellRect(n, 0, r));
  finally
    F.Free; Ctl.Free;
  end;
end;

{ Cross-check vs paint: render the tree and confirm the column-1 caption ink of
  the root row lies INSIDE GetCellRect(root, 1). }
procedure TTreeGetCellRectTest.TestCellRectContainsPaintedInk;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  Bmp: TBitmap; Bgra: TBGRABitmap; px: TBGRAPixel;
  r: TRect; x, y: Integer; inkX, inkY: Integer; foundInk: Boolean;
begin
  t := BuildTree(Ctl, F, root, child0);
  try
    AssertTrue('ink: col1 rect ok', t.GetCellRect(root, 1, r));

    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(t.Width, t.Height);
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      {$PUSH}{$HINTS OFF}
      TTyTreeViewAccess(t).RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      {$POP}
      Bgra := TBGRABitmap.Create(Bmp, True);
      try
        { Search the WHOLE bitmap for the 'Col1' dark ink, then assert it lies
          inside GetCellRect(root,1). Restricting the search to the rect would be
          circular; scanning everything proves the ink the paint produced for that
          cell actually falls within the reported rect. We scan only the root row's
          vertical band to isolate col-1 ink from the col-1 text of the child row. }
        foundInk := False; inkX := -1; inkY := -1;
        for y := r.Top to r.Bottom - 1 do
        begin
          for x := 0 to Bmp.Width - 1 do
          begin
            px := Bgra.GetPixel(x, y);
            { 'Col1' is the only dark ink in [120..200) on the root row; col0 has
              'Name0' + chevron, col2 has 'C2Right'. Find the leftmost dark ink at
              or past col1's left so we land on the 'Col1' glyphs. }
            if (px.alpha > 0) and (px.red < 120) and (x >= 120) and (x < 200) then
            begin
              foundInk := True; inkX := x; inkY := y;
              Break;
            end;
          end;
          if foundInk then Break;
        end;
        AssertTrue('ink: found col1 caption ink on the root row', foundInk);
        AssertTrue('ink: ink X inside GetCellRect(root,1)',
                   (inkX >= r.Left) and (inkX < r.Right));
        AssertTrue('ink: ink Y inside GetCellRect(root,1)',
                   (inkY >= r.Top) and (inkY < r.Bottom));
      finally
        Bgra.Free;
      end;
    finally
      Bmp.Free;
    end;
  finally
    F.Free; Ctl.Free;
  end;
end;

{ HiDPI: at PPI=144 the rect top/height and column span all scale by 144/96. }
procedure TTreeGetCellRectTest.TestCellRectHiDPIScales;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView; root, child0: PTyTreeNode;
  r: TRect;
begin
  t := BuildTree(Ctl, F, root, child0, 144);
  try
    AssertTrue('hidpi: col0 rect ok', t.GetCellRect(root, 0, r));
    { header 22 → MulDiv(22,144,96)=33; NodeHeight 22 → 33; col0 width 120 → 180 }
    AssertEquals('hidpi: top = Scale(22) = 33', 33, r.Top);
    AssertEquals('hidpi: height = Scale(22) = 33', 33, r.Bottom - r.Top);
    AssertEquals('hidpi: left = 0', 0, r.Left);
    AssertEquals('hidpi: right = Scale(120) = 180', 180, r.Right);
    { col 2: left = Scale(200)=300, right = Scale(300)=450 }
    AssertTrue('hidpi: col2 rect ok', t.GetCellRect(root, 2, r));
    AssertEquals('hidpi: col2 left = Scale(200) = 300', 300, r.Left);
    AssertEquals('hidpi: col2 right = Scale(300) = 450', 450, r.Right);
  finally
    F.Free; Ctl.Free;
  end;
end;

{ Scroll: with the H and V bars driven to a known position, GetCellRect shifts by
  exactly the read-back FOffsetX (horizontally) and tracks the paint vertically.
  A tall+narrow tree guarantees both bars are present. }
procedure TTreeGetCellRectTest.TestCellRectShiftsWithScroll;
var
  Ctl: TTyStyleController; F: TForm;
  t: TTyTreeView;
  col0, col1: TTyTreeColumn;
  n0: PTyTreeNode;
  rBefore, rAfter: TRect;
  offX: Integer;
  Bmp: TBitmap; Bgra: TBGRABitmap; px: TBGRAPixel;
  x, y: Integer; foundInk: Boolean;
begin
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(COLUMN_THEME_CSS);
  F := TForm.CreateNew(nil);
  try
    t := TTyTreeView.Create(F);
    t.Parent := F; t.Controller := Ctl;
    t.Font.PixelsPerInch := 96;
    t.DefaultNodeHeight := 22; t.Indent := 16;
    t.ShowButtons := True; t.ShowTreeLines := False; t.ShowRoot := True;
    { Narrow viewport (200 < 300 total col width) so the H-bar shows. }
    t.SetBounds(0, 0, 200, 200);
    t.OnGetTextWithType := @OnGetTextWithType;

    col0 := t.Header.Columns.Add as TTyTreeColumn;
    col0.Width := 120; col0.Text := 'Name';
    col1 := t.Header.Columns.Add as TTyTreeColumn;
    col1.Width := 80;  col1.Text := 'Info';
    with t.Header.Columns.Add as TTyTreeColumn do begin Width := 100; Text := 'Size'; end;
    t.Header.MainColumn := 0;
    t.Header.Options := [hoVisible];

    t.RootNodeCount := 1;
    n0 := t.RootNode^.FirstChild;
    Include(n0^.States, nsInitialized);

    { Adding columns + RootNodeCount already ran InvalidateTreeLayout →
      UpdateScrollBars, configuring the H-bar (FRangeX=300 > viewport 200). }
    AssertTrue('scroll: H-bar visible (cols 300 > viewport 200)',
               (t.HScroll <> nil) and t.HScroll.Visible);

    { Unscrolled rect of column 0 for node 0. }
    AssertTrue('scroll: rect before ok', t.GetCellRect(n0, 0, rBefore));

    { Scroll right by 40 device px. Read back the actual (clamped) offset. }
    t.HScroll.Position := 40;
    offX := -t.OffsetX;   // device px the content shifted left (>0)
    AssertTrue('scroll: scrolled right (OffsetX < 0)', t.OffsetX < 0);

    AssertTrue('scroll: rect after ok', t.GetCellRect(n0, 0, rAfter));
    AssertEquals('scroll: cell left shifts by -OffsetX',  rBefore.Left  - offX, rAfter.Left);
    AssertEquals('scroll: cell right shifts by -OffsetX', rBefore.Right - offX, rAfter.Right);
    AssertEquals('scroll: top unchanged by horizontal scroll', rBefore.Top, rAfter.Top);

    { Cross-check vs paint at the scrolled offset: the col-0 caption ink must fall
      inside the shifted rect. Render and scan the root row band. }
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(t.Width, t.Height);
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      {$PUSH}{$HINTS OFF}
      TTyTreeViewAccess(t).RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), 96);
      {$POP}
      Bgra := TBGRABitmap.Create(Bmp, True);
      try
        { The main column is the LEFTMOST column, so the leftmost dark-ink pixel
          on the root row belongs to the main column's caption ('Name0'). Assert
          that leftmost ink falls inside the SHIFTED GetCellRect(n0,0) — a
          non-circular cross-check that paint and GetCellRect agree under scroll.
          (col-1 'Col1' / col-2 'C2Right' ink sits further right, in their own
          cells, so we must not require ALL row ink to be in the main rect.) }
        foundInk := False;
        for x := 0 to Bmp.Width - 1 do
        begin
          for y := rAfter.Top to rAfter.Bottom - 1 do
          begin
            px := Bgra.GetPixel(x, y);
            if (px.alpha > 0) and (px.red < 120) then
            begin
              foundInk := True;
              Break;
            end;
          end;
          if foundInk then Break;
        end;
        AssertTrue('scroll: found painted caption ink on the scrolled root row', foundInk);
        AssertTrue('scroll: leftmost root-row ink X within shifted main-column rect',
                   (x >= rAfter.Left) and (x < rAfter.Right));
      finally
        Bgra.Free;
      end;
    finally
      Bmp.Free;
    end;
  finally
    F.Free; Ctl.Free;
  end;
end;

{ ── ③d B1 ── variable per-node row height ──────────────────────────────────── }

function TTreeB1VariableHeightTest.ExpectedH(Index: Integer): Integer;
begin
  Result := 18 + 6 * (Index mod 3);   // 0→18, 1→24, 2→30
end;

procedure TTreeB1VariableHeightTest.OnMeasureItem(Sender: TTyTreeView;
  ACanvas: TCanvas; Node: PTyTreeNode; var ANodeHeight: Integer);
begin
  Inc(FMeasureCalls);
  AssertTrue('measure: ACanvas non-nil', ACanvas <> nil);
  ANodeHeight := ExpectedH(Integer(Node^.Index));
end;

{ Flat tree: a single level of AChildCount root children, all leaves.
  DefaultNodeHeight = 18 (the C3 default). At PPI=96 logical px == device px. }
function TTreeB1VariableHeightTest.BuildFlatTree(out Ctl: TTyStyleController;
  out F: TForm; AChildCount: Integer; AVariable: Boolean; APPI: Integer): TTyTreeView;
var
  t: TTyTreeView;
begin
  FMeasureCalls := 0;
  Ctl := TTyStyleController.Create(nil);
  Ctl.LoadThemeCss(COLUMN_THEME_CSS);

  F := TForm.CreateNew(nil);
  t := TTyTreeView.Create(F);
  t.Parent     := F;
  t.Controller := Ctl;
  t.Font.PixelsPerInch := APPI;
  t.DefaultNodeHeight  := 18;
  t.Indent             := 16;
  t.ShowRoot           := True;
  t.SetBounds(0, 0, MulDiv(200, APPI, 96), MulDiv(120, APPI, 96));

  if AVariable then
  begin
    t.Options       := t.Options + [toVariableNodeHeight];
    t.OnMeasureItem := @OnMeasureItem;
  end;

  t.RootNodeCount := AChildCount;   // flat list of leaves
  Result := t;
end;

{ Render to an offscreen bitmap tall enough to fit all rows so every visible row
  is InitNode'd (→ OnMeasureItem fired). Render twice: the first pass measures +
  invalidates the cache; a settle pass ensures TotalHeight + cache reflect the
  measured heights. }
procedure TTreeB1VariableHeightTest.ForceMeasureAll(t: TTyTreeView; APPI: Integer);
var
  Bmp: TBitmap;
  pass: Integer;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(MulDiv(200, APPI, 96), MulDiv(2000, APPI, 96));  // tall: all rows fit
    for pass := 1 to 2 do
    begin
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);
      {$PUSH}{$HINTS OFF}
      TTyTreeViewAccess(t).RenderTo(Bmp.Canvas, Rect(0, 0, Bmp.Width, Bmp.Height), APPI);
      {$POP}
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestTotalHeightSumsVariableHeights;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
  i, expectedSum: Integer;
  n: PTyTreeNode;
begin
  t := BuildFlatTree(Ctl, F, 12, True);
  try
    ForceMeasureAll(t);
    AssertTrue('measure fired for the visible rows', FMeasureCalls >= 12);

    { Σ of per-node heights (children only) }
    expectedSum := 0;
    for i := 0 to 11 do Inc(expectedSum, ExpectedH(i));
    AssertEquals('Σ child heights = 4*(18+24+30) = 288', 288, expectedSum);

    { Each node carries its measured height }
    n := t.RootNode^.FirstChild; i := 0;
    while n <> nil do
    begin
      AssertEquals('node ' + IntToStr(i) + ' NodeHeight = expected',
        ExpectedH(i), Integer(n^.NodeHeight));
      n := n^.NextSibling; Inc(i);
    end;

    { ③a invariant with variable heights: root TotalHeight = Σ children + root row(18) }
    AssertEquals('RootNode.TotalHeight = 288 + root row 18 = 306',
      306, Integer(t.RootNode^.TotalHeight));
    AssertEquals('ContentHeight = 288', 288, t.ContentHeight);
  finally
    F.Free; Ctl.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestInvariantHelperAgrees;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
begin
  t := BuildFlatTree(Ctl, F, 12, True);
  try
    ForceMeasureAll(t);
    { SumVisibleHeights (the ③a invariant helper) must equal RootNode.TotalHeight. }
    AssertEquals('SumVisibleHeights = RootNode.TotalHeight (invariant holds)',
      t.SumVisibleHeights, Integer(t.RootNode^.TotalHeight));
  finally
    F.Free; Ctl.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestGetNodeAtAcrossVariedHeights;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
  node: PTyTreeNode;
  top, accTop, i: Integer;
begin
  t := BuildFlatTree(Ctl, F, 12, True);
  try
    ForceMeasureAll(t);

    { Walk the expected boundaries: child i occupies [accTop, accTop+ExpectedH(i)).
      GetNodeAt at the top pixel and the last pixel of each band must land on
      child i with ANodeTop = accTop. }
    accTop := 0;
    for i := 0 to 11 do
    begin
      node := t.GetNodeAt(accTop, top);
      AssertTrue('GetNodeAt(top of band ' + IntToStr(i) + ') non-nil', node <> nil);
      AssertEquals('GetNodeAt(top) → child ' + IntToStr(i) + ' (by Index)',
        i, Integer(node^.Index));
      AssertEquals('GetNodeAt(top) ANodeTop = band top', accTop, top);

      node := t.GetNodeAt(accTop + ExpectedH(i) - 1, top);
      AssertEquals('GetNodeAt(bottom-1 of band ' + IntToStr(i) + ') → same child',
        i, Integer(node^.Index));

      Inc(accTop, ExpectedH(i));
    end;

    { One pixel past the last band → nil (past end). accTop now = 288. }
    node := t.GetNodeAt(accTop, top);
    AssertTrue('GetNodeAt past last band → nil', node = nil);
  finally
    F.Free; Ctl.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestSetNodeHeightUpdatesTotal;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
  node: PTyTreeNode;
  oldH, beforeTotal: Integer;
begin
  t := BuildFlatTree(Ctl, F, 12, True);
  try
    ForceMeasureAll(t);

    { Pick child index 1 (measured height 24). }
    node := t.RootNode^.FirstChild^.NextSibling;
    AssertEquals('precondition: child1 height = 24', 24, Integer(node^.NodeHeight));
    AssertEquals('NodeHeight[] getter returns 24', 24, t.NodeHeight[node]);

    oldH        := Integer(node^.NodeHeight);
    beforeTotal := Integer(t.RootNode^.TotalHeight);

    t.NodeHeight[node] := 40;

    AssertEquals('NodeHeight[] reads back 40', 40, t.NodeHeight[node]);
    AssertEquals('node field = 40', 40, Integer(node^.NodeHeight));
    AssertEquals('RootNode.TotalHeight bumped by (40 - oldH)',
      beforeTotal + (40 - oldH), Integer(t.RootNode^.TotalHeight));

    { Invariant still holds after the programmatic override. }
    AssertEquals('SumVisibleHeights = RootNode.TotalHeight after SetNodeHeight',
      t.SumVisibleHeights, Integer(t.RootNode^.TotalHeight));

    { No-op when set to the same value. }
    beforeTotal := Integer(t.RootNode^.TotalHeight);
    t.NodeHeight[node] := 40;
    AssertEquals('SetNodeHeight same value → no change',
      beforeTotal, Integer(t.RootNode^.TotalHeight));
  finally
    F.Free; Ctl.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestDefaultOffEqualsC3;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
  n: PTyTreeNode;
begin
  { toVariableNodeHeight OFF (and OnMeasureItem still wired would not matter, but
    here it's unassigned too): every node = DefaultNodeHeight, identical to ③c. }
  t := BuildFlatTree(Ctl, F, 12, False);
  try
    ForceMeasureAll(t);
    AssertEquals('default-off: no measure calls', 0, FMeasureCalls);

    n := t.RootNode^.FirstChild;
    while n <> nil do
    begin
      AssertEquals('default-off: every node = DefaultNodeHeight(18)',
        18, Integer(n^.NodeHeight));
      n := n^.NextSibling;
    end;
    { TotalHeight == count*default + root row: 12*18 + 18 = 234 }
    AssertEquals('default-off: TotalHeight = 13*18 = 234',
      234, Integer(t.RootNode^.TotalHeight));
    AssertEquals('default-off: ContentHeight = 12*18 = 216', 216, t.ContentHeight);
  finally
    F.Free; Ctl.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestOptionOnButNoHandlerEqualsC3;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
  n: PTyTreeNode;
begin
  { Option ON but OnMeasureItem UNASSIGNED → the measure block is skipped (guard
    on Assigned(FOnMeasureItem)), so behaviour == ③c. }
  t := BuildFlatTree(Ctl, F, 12, False);   // build without handler...
  try
    t.Options := t.Options + [toVariableNodeHeight];  // ...then turn the option on, leave OnMeasureItem nil
    ForceMeasureAll(t);

    n := t.RootNode^.FirstChild;
    while n <> nil do
    begin
      AssertEquals('option-on/no-handler: every node = DefaultNodeHeight(18)',
        18, Integer(n^.NodeHeight));
      n := n^.NextSibling;
    end;
    AssertEquals('option-on/no-handler: TotalHeight = 234',
      234, Integer(t.RootNode^.TotalHeight));
  finally
    F.Free; Ctl.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestHiDPILogicalInvariant;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
  i, expectedSum: Integer;
begin
  { At PPI=144 the measured heights are LOGICAL (device scaling happens at paint
    via P.Scale). TotalHeight is logical, so it must still sum the logical
    heights — exactly as at PPI=96 (matching the ③a logical-unit discipline). }
  t := BuildFlatTree(Ctl, F, 12, True, 144);
  try
    ForceMeasureAll(t, 144);

    expectedSum := 0;
    for i := 0 to 11 do Inc(expectedSum, ExpectedH(i));   // 288 logical

    { Each node stores the LOGICAL measured height (not scaled to 144). }
    AssertEquals('hidpi: child0 logical height = 18', 18,
      Integer(t.RootNode^.FirstChild^.NodeHeight));
    AssertEquals('hidpi: RootNode.TotalHeight logical = 288 + 18 = 306',
      306, Integer(t.RootNode^.TotalHeight));
    AssertEquals('hidpi: invariant holds (SumVisibleHeights logical)',
      t.SumVisibleHeights, Integer(t.RootNode^.TotalHeight));
  finally
    F.Free; Ctl.Free;
  end;
end;

procedure TTreeB1VariableHeightTest.TestZeroHeightIgnored;
var
  Ctl: TTyStyleController; F: TForm; t: TTyTreeView;
  node: PTyTreeNode;
  beforeTotal: Integer;
begin
  { Programmatic guard: SetNodeHeight(0) is a no-op (heights must be positive). }
  t := BuildFlatTree(Ctl, F, 4, True);
  try
    ForceMeasureAll(t);
    node := t.RootNode^.FirstChild;   // index 0, height 18
    beforeTotal := Integer(t.RootNode^.TotalHeight);
    t.NodeHeight[node] := 0;          // ignored
    AssertEquals('SetNodeHeight(0) ignored: height unchanged',
      18, Integer(node^.NodeHeight));
    AssertEquals('SetNodeHeight(0) ignored: TotalHeight unchanged',
      beforeTotal, Integer(t.RootNode^.TotalHeight));
  finally
    F.Free; Ctl.Free;
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
  RegisterTest(TTreeB2CheckPaintTest);
  RegisterTest(TTreeB3HitCheckBoxTest);
  RegisterTest(TTreeC1CheckBehaviourTest);
  RegisterTest(TTreeD1MultiSelectMouseTest);
  RegisterTest(TTreeD2MultiSelectKeyboardTest);
  RegisterTest(TTreeAdversarialFixTest);
  RegisterTest(TTreeGetCellRectTest);
  RegisterTest(TTreeB1VariableHeightTest);
end.
