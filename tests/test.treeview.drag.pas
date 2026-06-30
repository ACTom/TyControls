unit test.treeview.drag;
{ ③f — intra-tree node drag-drop.
  F1: the PURE structural-move engine — MoveNode / CanMoveNode / IsDescendant.
  No mouse, no paint (those are F2/F3). Headless: a bare TTyTreeView (no Form /
  Controller / RenderTo needed) — the count/height bookkeeping is maintained by
  AddChild / AdjustTotal* / the Index re-sequence, all of which run without a
  window handle (mirrors the ③a aggregate tests in test.treeview.pas). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils,
  fpcunit, testregistry,
  tyControls.TreeView;

type
  { F1: the pure move engine. The fixture is a small known tree built with
    AddChild; every test reads the link fields / TotalCount / TotalHeight /
    Index directly off the public RootNode pointer. }
  TTreeDragF1Test = class(TTestCase)
  private
    FTree: TTyTreeView;
    { fixture nodes (built by BuildTree):
        rootA  (3 children: a0, a1, a2)
        rootB  (2 children: b0, b1)
      all top-level: rootA, rootB }
    FRootA, FRootB:     PTyTreeNode;
    FA0, FA1, FA2:      PTyTreeNode;
    FB0, FB1:           PTyTreeNode;
    procedure BuildTree;
    function  SiblingIndexList(AParent: PTyTreeNode): string;  // "child0Index,child1Index,..."
    function  ChildAt(AParent: PTyTreeNode; AIdx: Integer): PTyTreeNode;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { reorder within one parent }
    procedure TestMoveAboveReordersSiblings;
    procedure TestMoveBelowReordersSiblings;
    procedure TestReorderRestampsIndex;
    { reparent }
    procedure TestMoveOnReparents;
    procedure TestMoveOnMarksHasChildren;
    { conservation across a cross-parent move }
    procedure TestCrossParentConservesRootCount;
    procedure TestCrossParentAdjustsChildCounts;
    procedure TestCrossParentConservesExpandedHeight;
    { rejections }
    procedure TestCircularRejected;
    procedure TestCircularLeavesTreeUnchanged;
    procedure TestSelfRejected;
    procedure TestDmNoneRejected;
    procedure TestNoOpReorderRejected;
    procedure TestNoOpReparentRejected;
    { auto-expand }
    procedure TestMoveOnCollapsedTargetAutoExpands;
    { IsDescendant + CanMoveNode predicate matrix }
    procedure TestIsDescendant;
    procedure TestCanMoveNodePredicateMatrix;
  end;

implementation

const
  NH = 18;  // == TTyTreeView.DefaultNodeHeight for a fresh control

procedure TTreeDragF1Test.SetUp;
begin
  FTree := TTyTreeView.Create(nil);
  BuildTree;
end;

procedure TTreeDragF1Test.TearDown;
begin
  FTree.Free;
  FTree := nil;
end;

procedure TTreeDragF1Test.BuildTree;
begin
  { two top-level subtrees: rootA[a0,a1,a2]  rootB[b0,b1] }
  FRootA := FTree.AddChild(nil);
  FA0    := FTree.AddChild(FRootA);
  FA1    := FTree.AddChild(FRootA);
  FA2    := FTree.AddChild(FRootA);

  FRootB := FTree.AddChild(nil);
  FB0    := FTree.AddChild(FRootB);
  FB1    := FTree.AddChild(FRootB);

  { expand both subtrees so heights are "visible" and conservation is meaningful }
  FTree.Expanded[FRootA] := True;
  FTree.Expanded[FRootB] := True;
end;

function TTreeDragF1Test.SiblingIndexList(AParent: PTyTreeNode): string;
var
  n: PTyTreeNode;
begin
  Result := '';
  n := AParent^.FirstChild;
  while n <> nil do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + IntToStr(n^.Index);
    n := n^.NextSibling;
  end;
end;

function TTreeDragF1Test.ChildAt(AParent: PTyTreeNode; AIdx: Integer): PTyTreeNode;
var
  i: Integer;
begin
  Result := AParent^.FirstChild;
  i := 0;
  while (Result <> nil) and (i < AIdx) do
  begin
    Result := Result^.NextSibling;
    Inc(i);
  end;
end;

{ ---- reorder within one parent ---- }

procedure TTreeDragF1Test.TestMoveAboveReordersSiblings;
begin
  { move a2 ABOVE a0 → order becomes a2, a0, a1 }
  AssertTrue('MoveNode(a2, a0, dmAbove)', FTree.MoveNode(FA2, FA0, dmAbove));
  AssertSame('child[0] = a2', FA2, ChildAt(FRootA, 0));
  AssertSame('child[1] = a0', FA0, ChildAt(FRootA, 1));
  AssertSame('child[2] = a1', FA1, ChildAt(FRootA, 2));
  AssertSame('a2.Parent unchanged', FRootA, FA2^.Parent);
  AssertEquals('rootA.ChildCount still 3', 3, Integer(FRootA^.ChildCount));
end;

procedure TTreeDragF1Test.TestMoveBelowReordersSiblings;
begin
  { move a0 BELOW a2 → order becomes a1, a2, a0 }
  AssertTrue('MoveNode(a0, a2, dmBelow)', FTree.MoveNode(FA0, FA2, dmBelow));
  AssertSame('child[0] = a1', FA1, ChildAt(FRootA, 0));
  AssertSame('child[1] = a2', FA2, ChildAt(FRootA, 1));
  AssertSame('child[2] = a0', FA0, ChildAt(FRootA, 2));
end;

procedure TTreeDragF1Test.TestReorderRestampsIndex;
begin
  AssertTrue(FTree.MoveNode(FA2, FA0, dmAbove));
  { after a2,a0,a1 the Index field must be 0,1,2 in sibling order }
  AssertEquals('Index re-stamped 0..n-1', '0,1,2', SiblingIndexList(FRootA));
  AssertEquals('a2.Index = 0', 0, Integer(FA2^.Index));
  AssertEquals('a0.Index = 1', 1, Integer(FA0^.Index));
  AssertEquals('a1.Index = 2', 2, Integer(FA1^.Index));
end;

{ ---- reparent (dmOn) ---- }

procedure TTreeDragF1Test.TestMoveOnReparents;
begin
  { move a0 ONTO rootB → a0 becomes rootB's last child }
  AssertTrue('MoveNode(a0, rootB, dmOn)', FTree.MoveNode(FA0, FRootB, dmOn));
  AssertSame('a0.Parent = rootB', FRootB, FA0^.Parent);
  AssertEquals('rootB.ChildCount = 3', 3, Integer(FRootB^.ChildCount));
  AssertEquals('rootA.ChildCount = 2', 2, Integer(FRootA^.ChildCount));
  AssertSame('rootB.LastChild = a0', FA0, FRootB^.LastChild);
  AssertSame('a0 unlinked from rootA: rootA.FirstChild = a1', FA1, FRootA^.FirstChild);
end;

procedure TTreeDragF1Test.TestMoveOnMarksHasChildren;
var
  leaf: PTyTreeNode;
begin
  { b0 is a leaf (no children). Move a0 ONTO b0 → b0 gains nsHasChildren. }
  leaf := FB0;
  AssertFalse('b0 starts without nsHasChildren', nsHasChildren in leaf^.States);
  AssertTrue(FTree.MoveNode(FA0, leaf, dmOn));
  AssertTrue('b0 gains nsHasChildren', nsHasChildren in leaf^.States);
  AssertSame('a0.Parent = b0', leaf, FA0^.Parent);
  AssertEquals('b0.ChildCount = 1', 1, Integer(leaf^.ChildCount));
end;

{ ---- conservation across a cross-parent move ---- }

procedure TTreeDragF1Test.TestCrossParentConservesRootCount;
var
  before: Cardinal;
begin
  before := FTree.RootNode^.TotalCount;
  AssertTrue(FTree.MoveNode(FA0, FRootB, dmOn));
  AssertEquals('root TotalCount conserved across a cross-parent move',
    Integer(before), Integer(FTree.RootNode^.TotalCount));
end;

procedure TTreeDragF1Test.TestCrossParentAdjustsChildCounts;
begin
  AssertEquals('rootA.ChildCount before = 3', 3, Integer(FRootA^.ChildCount));
  AssertEquals('rootB.ChildCount before = 2', 2, Integer(FRootB^.ChildCount));
  AssertTrue(FTree.MoveNode(FA0, FRootB, dmOn));
  AssertEquals('rootA.ChildCount after = 2', 2, Integer(FRootA^.ChildCount));
  AssertEquals('rootB.ChildCount after = 3', 3, Integer(FRootB^.ChildCount));
  { aggregate TotalCount of each subtree root is consistent }
  AssertEquals('rootA TotalCount = 3 (self + 2 children)', 3, Integer(FRootA^.TotalCount));
  AssertEquals('rootB TotalCount = 4 (self + 3 children)', 4, Integer(FRootB^.TotalCount));
end;

procedure TTreeDragF1Test.TestCrossParentConservesExpandedHeight;
var
  before: Cardinal;
begin
  { both subtrees expanded; the whole tree's visible height must be conserved
    when a node moves between two expanded parents (it stays visible). }
  before := FTree.RootNode^.TotalHeight;
  AssertTrue(FTree.MoveNode(FA0, FRootB, dmOn));
  AssertEquals('root TotalHeight conserved (both parents expanded, node stays visible)',
    Integer(before), Integer(FTree.RootNode^.TotalHeight));
  { sanity: rootA loses one row, rootB gains one }
  AssertEquals('rootA TotalHeight = 3*NH', 3 * NH, Integer(FRootA^.TotalHeight));
  AssertEquals('rootB TotalHeight = 4*NH', 4 * NH, Integer(FRootB^.TotalHeight));
end;

{ ---- rejections ---- }

procedure TTreeDragF1Test.TestCircularRejected;
begin
  { can't drop a parent into its own descendant }
  AssertFalse('MoveNode(rootA, a0, dmOn) rejected (a0 is rootA descendant)',
    FTree.MoveNode(FRootA, FA0, dmOn));
  AssertFalse('CanMoveNode mirrors it', FTree.CanMoveNode(FRootA, FA0, dmOn));
end;

procedure TTreeDragF1Test.TestCircularLeavesTreeUnchanged;
begin
  FTree.MoveNode(FRootA, FA0, dmOn);  // rejected
  { rootA still has its 3 children, a0 still leaf, rootA still top-level }
  AssertEquals('rootA.ChildCount unchanged = 3', 3, Integer(FRootA^.ChildCount));
  AssertSame('rootA.Parent still hidden root', FTree.RootNode, FRootA^.Parent);
  AssertEquals('a0.ChildCount still 0', 0, Integer(FA0^.ChildCount));
  AssertSame('a0.Parent still rootA', FRootA, FA0^.Parent);
end;

procedure TTreeDragF1Test.TestSelfRejected;
begin
  AssertFalse('move onto self rejected', FTree.MoveNode(FA1, FA1, dmOn));
  AssertFalse('above self rejected', FTree.MoveNode(FA1, FA1, dmAbove));
  AssertFalse('CanMoveNode self = False', FTree.CanMoveNode(FA1, FA1, dmOn));
end;

procedure TTreeDragF1Test.TestDmNoneRejected;
begin
  AssertFalse('dmNone rejected', FTree.MoveNode(FA0, FRootB, dmNone));
  AssertFalse('CanMoveNode dmNone = False', FTree.CanMoveNode(FA0, FRootB, dmNone));
  AssertFalse('nil node rejected', FTree.MoveNode(nil, FRootB, dmOn));
  AssertFalse('nil target rejected', FTree.MoveNode(FA0, nil, dmOn));
  AssertFalse('moving the hidden root rejected',
    FTree.MoveNode(FTree.RootNode, FRootA, dmOn));
end;

procedure TTreeDragF1Test.TestNoOpReorderRejected;
begin
  { a1 is already between a0 and a2. dmBelow a0 would put it right back where it
    is (a1 directly follows a0) → no-op → False. dmAbove a2 is likewise a no-op. }
  AssertFalse('dmBelow a0 is a no-op for a1', FTree.CanMoveNode(FA1, FA0, dmBelow));
  AssertFalse('dmAbove a2 is a no-op for a1', FTree.CanMoveNode(FA1, FA2, dmAbove));
  AssertFalse('MoveNode no-op returns False', FTree.MoveNode(FA1, FA0, dmBelow));
  { order untouched }
  AssertEquals('order untouched', '0,1,2', SiblingIndexList(FRootA));
  AssertSame('a1 still 2nd', FA1, ChildAt(FRootA, 1));
end;

procedure TTreeDragF1Test.TestNoOpReparentRejected;
begin
  { dmAbove a0 (the first child of rootA) for a node that is ALREADY rootA's first
    child is a no-op. a0 is already rootA's first child; dmAbove a1 keeps a0 first. }
  AssertFalse('dmAbove a1 is a no-op for a0 (already directly before a1)',
    FTree.CanMoveNode(FA0, FA1, dmAbove));
  { dmOn rootA for a0 (already a child of rootA, and last? no — a0 is first).
    dmOn appends as LAST child; a0 is NOT last, so dmOn rootA is NOT a no-op. }
  AssertTrue('dmOn rootA for a0 is a real move (a0 not last child)',
    FTree.CanMoveNode(FA0, FRootA, dmOn));
  { but dmOn rootA for a2 (already the last child) IS a no-op }
  AssertFalse('dmOn rootA for a2 is a no-op (a2 already last child)',
    FTree.CanMoveNode(FA2, FRootA, dmOn));
end;

{ ---- auto-expand ---- }

procedure TTreeDragF1Test.TestMoveOnCollapsedTargetAutoExpands;
var
  before: Cardinal;
begin
  { collapse rootB, then drop a0 ONTO rootB → rootB must auto-expand so the drop
    is visible, and the whole-tree visible height must still be conserved. }
  FTree.Expanded[FRootB] := False;
  AssertFalse('rootB collapsed', FTree.Expanded[FRootB]);
  before := FTree.RootNode^.TotalHeight;   // rootB's children NOT counted now

  AssertTrue(FTree.MoveNode(FA0, FRootB, dmOn));
  AssertTrue('rootB auto-expanded by dmOn', FTree.Expanded[FRootB]);
  AssertSame('a0.Parent = rootB', FRootB, FA0^.Parent);

  { conservation: a0 was visible under expanded rootA (counted once). After the
    move rootB is expanded, so a0 + the now-revealed b0,b1 are all counted.
    Net root height = before - a0(was visible) + (b0+b1+a0 now visible). }
  AssertEquals('root TotalHeight = before + 2 newly-revealed rows',
    Integer(before) + 2 * NH, Integer(FTree.RootNode^.TotalHeight));
  { rootB now expanded with 3 children: rootB row + 3 child rows }
  AssertEquals('rootB TotalHeight = 4*NH', 4 * NH, Integer(FRootB^.TotalHeight));
end;

{ ---- IsDescendant + predicate matrix ---- }

procedure TTreeDragF1Test.TestIsDescendant;
var
  deep: PTyTreeNode;
begin
  { add a grandchild under a0 to test multi-level descent }
  deep := FTree.AddChild(FA0);
  AssertTrue('a0 is descendant of rootA', FTree.IsDescendant(FA0, FRootA));
  AssertTrue('grandchild is descendant of rootA', FTree.IsDescendant(deep, FRootA));
  AssertTrue('grandchild is descendant of a0', FTree.IsDescendant(deep, FA0));
  AssertFalse('a0 is NOT descendant of rootB', FTree.IsDescendant(FA0, FRootB));
  AssertFalse('rootA is NOT descendant of a0', FTree.IsDescendant(FRootA, FA0));
  AssertFalse('a node is not its own descendant', FTree.IsDescendant(FA0, FA0));
end;

procedure TTreeDragF1Test.TestCanMoveNodePredicateMatrix;
begin
  { valid moves }
  AssertTrue('a0 above a2 valid', FTree.CanMoveNode(FA0, FA2, dmAbove));
  AssertTrue('a2 below a0 valid', FTree.CanMoveNode(FA2, FA0, dmBelow));
  AssertTrue('a0 onto rootB valid', FTree.CanMoveNode(FA0, FRootB, dmOn));
  AssertTrue('b0 onto rootA valid (cross-parent)', FTree.CanMoveNode(FB0, FRootA, dmOn));
  { invalid moves }
  AssertFalse('nil src invalid', FTree.CanMoveNode(nil, FRootB, dmOn));
  AssertFalse('nil target invalid', FTree.CanMoveNode(FA0, nil, dmOn));
  AssertFalse('dmNone invalid', FTree.CanMoveNode(FA0, FRootB, dmNone));
  AssertFalse('self invalid', FTree.CanMoveNode(FA0, FA0, dmOn));
  AssertFalse('hidden root as src invalid', FTree.CanMoveNode(FTree.RootNode, FRootA, dmOn));
  AssertFalse('circular (target is src descendant) invalid', FTree.CanMoveNode(FRootA, FA1, dmOn));
end;

initialization
  RegisterTest(TTreeDragF1Test);

end.
