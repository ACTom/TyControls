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
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  tyControls.TreeView.Columns,
  tyControls.TreeView,
  tyControls.Controller;

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

  { F2: the mouse/keyboard drag state machine over the F1 engine. Headless: a real
    TForm + Controller + a RenderTo layout pass (so the hit-test resolves real
    device coordinates), driving the protected MouseDown/MouseMove/MouseUp/KeyDown
    through a hard-cast descendant. A 0-column tree (no header band) with three
    expandable/flat top-level nodes, ShowRoot + DefaultNodeHeight=22, so row r sits
    at y=[22*r .. 22*r+22). }
  TTreeDragF2Test = class(TTestCase)
  private
    FCtl:  TTyStyleController;
    FForm: TForm;
    FTree: TTyTreeView;
    FN0, FN1, FN2: PTyTreeNode;   // three top-level nodes (rows 0,1,2)
    { OnDragOver bookkeeping }
    FDragOverFired:   Integer;
    FDragOverAllow:   Boolean;    // what the handler forces Allowed to
    FDragOverVeto:    Boolean;    // when True the handler sets Allowed := False
    FDragOverSrc:     PTyTreeNode;
    FDragOverTarget:  PTyTreeNode;
    FDragOverMode:    TTyTreeDropMode;
    { OnNodeMoved bookkeeping }
    FMovedFired:      Integer;
    FMovedNode:       PTyTreeNode;
    procedure OnGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
    procedure OnDragOver(Sender: TTyTreeView; Src, Target: PTyTreeNode;
      Mode: TTyTreeDropMode; var Allowed: Boolean);
    procedure OnNodeMoved(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure BuildTree;
    procedure Layout;
    function  RowMidY(ARow: Integer): Integer;      // device-px Y at the middle of row ARow
    function  LabelX: Integer;                      // device-px X inside the label zone
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMouseDownArmsOnLabel;
    procedure TestMouseDownDoesNotArmOnButton;
    procedure TestMouseDownDoesNotArmWhenOptionOff;
    procedure TestMouseMoveBelowThresholdDoesNotStart;
    procedure TestMouseMovePastThresholdStarts;
    procedure TestDropModeFromYThirds;
    procedure TestDragOverVetoPerformsNoMove;
    procedure TestValidDropMovesAndFiresOnce;
    procedure TestEscapeCancelsMidDrag;
    procedure TestDeleteNodeMidDragClears;
    procedure TestClearMidDragClears;
    procedure TestOptionsEmptyNoDrag;
  end;

implementation

const
  NH = 18;  // == TTyTreeView.DefaultNodeHeight for a fresh control

  { minimal theme so RenderTo/GetCellRect lay out (mirrors the ③e edit fixture). }
  DRAG_THEME_CSS =
    'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; } ' +
    'TyTreeNode { background: none; color: #000000; } ' +
    'TyTreeNode:selected { background: #3B82F6; color: #FFFFFF; } ';

type
  { hard-cast helper: reach the protected RenderTo (to lay out) + the protected
    mouse/key handlers + the private DropModeFromY from the F2 tests. }
  TDragTreeAccess = class(TTyTreeView)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure MouseDownPub(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MouseMovePub(Shift: TShiftState; X, Y: Integer);
    procedure MouseUpPub(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure KeyDownPub(var Key: Word; Shift: TShiftState);
    function  DropModeFromYPub(Target: PTyTreeNode; AY: Integer): TTyTreeDropMode;
    function  DragNodePub: PTyTreeNode;
  end;

procedure TDragTreeAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TDragTreeAccess.MouseDownPub(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(Button, Shift, X, Y);
end;

procedure TDragTreeAccess.MouseMovePub(Shift: TShiftState; X, Y: Integer);
begin
  MouseMove(Shift, X, Y);
end;

procedure TDragTreeAccess.MouseUpPub(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  MouseUp(Button, Shift, X, Y);
end;

procedure TDragTreeAccess.KeyDownPub(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

function TDragTreeAccess.DropModeFromYPub(Target: PTyTreeNode; AY: Integer): TTyTreeDropMode;
begin
  Result := DropModeFromY(Target, AY);
end;

function TDragTreeAccess.DragNodePub: PTyTreeNode;
begin
  Result := DragNode;
end;

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

{ ============================================================================
  F2 — drag state machine (mouse + Esc) + option + events
  ============================================================================ }

procedure TTreeDragF2Test.OnGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var Text: string);
begin
  Text := 'row' + IntToStr(Node^.Index);
end;

procedure TTreeDragF2Test.OnDragOver(Sender: TTyTreeView; Src, Target: PTyTreeNode;
  Mode: TTyTreeDropMode; var Allowed: Boolean);
begin
  Inc(FDragOverFired);
  FDragOverSrc    := Src;
  FDragOverTarget := Target;
  FDragOverMode   := Mode;
  if FDragOverVeto then Allowed := False
  else                  Allowed := FDragOverAllow;
end;

procedure TTreeDragF2Test.OnNodeMoved(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FMovedFired);
  FMovedNode := Node;
end;

{ A 0-column tree (no header band) with three top-level nodes; the FIRST is given
  a child (so it shows an expand button at the left — exercises the hpButton gate),
  the other two are flat leaves. ShowRoot + DefaultNodeHeight=22 ⇒ row r at
  device-y [22*r .. 22*r+22); top-level indent = 16px so the button slot is [0..16)
  and the label zone is [16..). }
procedure TTreeDragF2Test.BuildTree;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(DRAG_THEME_CSS);

  FForm := TForm.CreateNew(nil);
  FTree := TTyTreeView.Create(FForm);
  FTree.Parent     := FForm;
  FTree.Controller := FCtl;
  FTree.Font.PixelsPerInch := 96;
  FTree.DefaultNodeHeight  := 22;
  FTree.Indent             := 16;
  FTree.ShowButtons        := True;
  FTree.ShowTreeLines      := False;
  FTree.ShowRoot           := True;
  FTree.SetBounds(0, 0, 300, 200);
  FTree.OnGetText          := @OnGetText;

  FTree.RootNodeCount := 3;
  FN0 := FTree.RootNode^.FirstChild;
  FN1 := FN0^.NextSibling;
  FN2 := FN1^.NextSibling;
  { give n0 a child so it shows an expand button; keep it collapsed }
  FTree.InitNode(FN0);
  FTree.AddChild(FN0);
end;

procedure TTreeDragF2Test.Layout;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(300, 200);
    TDragTreeAccess(FTree).RenderTo(Bmp.Canvas, Rect(0, 0, 300, 200), 96);
  finally
    Bmp.Free;
  end;
end;

function TTreeDragF2Test.RowMidY(ARow: Integer): Integer;
begin
  { DefaultNodeHeight=22 @96dpi, no header band ⇒ row ARow is [22*ARow .. +22). }
  Result := ARow * 22 + 11;
end;

function TTreeDragF2Test.LabelX: Integer;
begin
  { top-level indent = 16px ⇒ label zone starts at x=16; 50 is comfortably inside. }
  Result := 50;
end;

procedure TTreeDragF2Test.SetUp;
begin
  FDragOverFired  := 0;
  FDragOverAllow  := True;
  FDragOverVeto   := False;
  FDragOverSrc    := nil;
  FDragOverTarget := nil;
  FDragOverMode   := dmNone;
  FMovedFired     := 0;
  FMovedNode      := nil;
  BuildTree;
end;

procedure TTreeDragF2Test.TearDown;
begin
  FForm.Free;   // frees FTree (owned)
  FForm := nil;
  FCtl.Free;
  FCtl := nil;
end;

{ ---- MouseDown arms only on label/image + toNodeDrag ---- }

procedure TTreeDragF2Test.TestMouseDownArmsOnLabel;
begin
  FTree.Options := [toNodeDrag];
  Layout;
  { press on n1's label (row 1, x in label zone) → arms FDragNode but not active. }
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(1));
  AssertSame('MouseDown on a label arms FDragNode',
    FN1, TDragTreeAccess(FTree).DragNodePub);
  AssertFalse('arming does not start the drag yet', FTree.IsDraggingNode);
end;

procedure TTreeDragF2Test.TestMouseDownDoesNotArmOnButton;
begin
  FTree.Options := [toNodeDrag];
  Layout;
  { n0 has a child ⇒ the expand button occupies x=[0..16) on row 0. A press there
    is hpButton → must NOT arm a drag (the button toggles instead). }
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], 8, RowMidY(0));
  AssertTrue('press on the expand button arms nothing',
    TDragTreeAccess(FTree).DragNodePub = nil);
end;

procedure TTreeDragF2Test.TestMouseDownDoesNotArmWhenOptionOff;
begin
  FTree.Options := [];   // toNodeDrag OFF
  Layout;
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(1));
  AssertTrue('no toNodeDrag ⇒ MouseDown does not arm',
    TDragTreeAccess(FTree).DragNodePub = nil);
  AssertFalse('and no drag is active', FTree.IsDraggingNode);
end;

{ ---- MouseMove threshold ---- }

procedure TTreeDragF2Test.TestMouseMoveBelowThresholdDoesNotStart;
begin
  FTree.Options := [toNodeDrag];
  Layout;
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(1));
  { move 3px (< Scale(4)=4 @96dpi) with the button held ⇒ still armed, not active. }
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 3, RowMidY(1));
  AssertFalse('a move below the threshold does not start the drag',
    FTree.IsDraggingNode);
end;

procedure TTreeDragF2Test.TestMouseMovePastThresholdStarts;
begin
  FTree.Options := [toNodeDrag];
  Layout;
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(1));
  { move 6px (> 4) with the button held ⇒ the drag goes active. }
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 6, RowMidY(1));
  AssertTrue('a move past Scale(4) starts the drag', FTree.IsDraggingNode);
end;

{ ---- DropModeFromY thirds ---- }

procedure TTreeDragF2Test.TestDropModeFromYThirds;
begin
  FTree.Options := [toNodeDrag];
  Layout;
  { row 1 spans device-y [22..44): top third [22..29.33) → dmAbove, middle → dmOn,
    bottom third [36.67..44) → dmBelow. Probe 24 / 33 / 42. }
  AssertEquals('top third → dmAbove', Ord(dmAbove),
    Ord(TDragTreeAccess(FTree).DropModeFromYPub(FN1, 24)));
  AssertEquals('middle third → dmOn', Ord(dmOn),
    Ord(TDragTreeAccess(FTree).DropModeFromYPub(FN1, 33)));
  AssertEquals('bottom third → dmBelow', Ord(dmBelow),
    Ord(TDragTreeAccess(FTree).DropModeFromYPub(FN1, 42)));
  AssertEquals('nil target → dmNone', Ord(dmNone),
    Ord(TDragTreeAccess(FTree).DropModeFromYPub(nil, 33)));
end;

{ ---- OnDragOver veto → no move ---- }

procedure TTreeDragF2Test.TestDragOverVetoPerformsNoMove;
begin
  FTree.Options    := [toNodeDrag];
  FTree.OnDragOver := @OnDragOver;
  FDragOverVeto    := True;        // handler forces Allowed := False
  Layout;
  { press n2's label, drag onto n0 (dmOn), release. The veto must block the move. }
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(2));   // n2
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 6, RowMidY(2)); // start
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX, RowMidY(0));     // over n0
  AssertTrue('OnDragOver fired during the drag', FDragOverFired > 0);
  AssertEquals('veto collapses the drop mode to dmNone', Ord(dmNone), Ord(FTree.DropMode));
  TDragTreeAccess(FTree).MouseUpPub(mbLeft, [], LabelX, RowMidY(0));
  { n2 must be untouched: still a top-level leaf, n0 still has just its 1 child. }
  AssertSame('vetoed: n2.Parent unchanged', FTree.RootNode, FN2^.Parent);
  AssertEquals('vetoed: n0.ChildCount unchanged (1)', 1, Integer(FN0^.ChildCount));
  AssertEquals('vetoed: OnNodeMoved never fired', 0, FMovedFired);
  AssertFalse('drag ended', FTree.IsDraggingNode);
end;

{ ---- valid drop → MoveNode ran + OnNodeMoved once ---- }

procedure TTreeDragF2Test.TestValidDropMovesAndFiresOnce;
begin
  FTree.Options     := [toNodeDrag];
  FTree.OnDragOver  := @OnDragOver;
  FTree.OnNodeMoved := @OnNodeMoved;
  Layout;
  AssertEquals('precondition: 3 top-level nodes', 3, Integer(FTree.RootNode^.ChildCount));
  { press n2's label, drag, drop ONTO n0 (middle third) → n2 reparents under n0. }
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(2));   // n2
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 6, RowMidY(2)); // start
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX, RowMidY(0) + 0); // over n0 middle
  AssertEquals('tracking resolved dmOn over n0', Ord(dmOn), Ord(FTree.DropMode));
  AssertSame('drop target is n0', FN0, FTree.DropTargetNode);
  TDragTreeAccess(FTree).MouseUpPub(mbLeft, [], LabelX, RowMidY(0));
  { structure changed: n2 now a child of n0; top-level count dropped to 2. }
  AssertSame('n2.Parent = n0 after the drop', FN0, FN2^.Parent);
  AssertEquals('top-level count now 2', 2, Integer(FTree.RootNode^.ChildCount));
  AssertEquals('OnNodeMoved fired exactly once', 1, FMovedFired);
  AssertSame('OnNodeMoved carried the moved node', FN2, FMovedNode);
  AssertFalse('drag ended after the commit', FTree.IsDraggingNode);
end;

{ ---- Esc cancels mid-drag ---- }

procedure TTreeDragF2Test.TestEscapeCancelsMidDrag;
var
  Key: Word;
begin
  FTree.Options     := [toNodeDrag];
  FTree.OnNodeMoved := @OnNodeMoved;
  Layout;
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(2));   // n2
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 6, RowMidY(2)); // start
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX, RowMidY(0));     // over n0
  AssertTrue('precondition: dragging', FTree.IsDraggingNode);
  Key := VK_ESCAPE;
  TDragTreeAccess(FTree).KeyDownPub(Key, []);
  AssertFalse('Esc cancels the drag', FTree.IsDraggingNode);
  AssertEquals('Esc consumed the key', 0, Integer(Key));
  { a follow-up MouseUp must NOT commit a move. }
  TDragTreeAccess(FTree).MouseUpPub(mbLeft, [], LabelX, RowMidY(0));
  AssertSame('Esc: n2.Parent unchanged', FTree.RootNode, FN2^.Parent);
  AssertEquals('Esc: no move fired', 0, FMovedFired);
end;

{ ---- DeleteNode / Clear during a drag clears state (no UAF on next layout) ---- }

procedure TTreeDragF2Test.TestDeleteNodeMidDragClears;
begin
  FTree.Options := [toNodeDrag];
  Layout;
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(2));   // arm n2
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 6, RowMidY(2)); // active
  AssertTrue('precondition: dragging n2', FTree.IsDraggingNode);
  { delete the very node being dragged ⇒ drag must end + FDragNode null. }
  FTree.DeleteNode(FN2);
  AssertFalse('DeleteNode of the drag source clears the drag', FTree.IsDraggingNode);
  AssertTrue('FDragNode nulled', TDragTreeAccess(FTree).DragNodePub = nil);
  AssertTrue('DropTargetNode nulled', FTree.DropTargetNode = nil);
  Layout;   // must not dereference a freed pointer
end;

procedure TTreeDragF2Test.TestClearMidDragClears;
begin
  FTree.Options := [toNodeDrag];
  Layout;
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(1));   // arm n1
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 6, RowMidY(1)); // active
  AssertTrue('precondition: dragging', FTree.IsDraggingNode);
  FTree.Clear;
  AssertFalse('Clear during a drag clears the drag', FTree.IsDraggingNode);
  AssertTrue('FDragNode nulled by Clear', TDragTreeAccess(FTree).DragNodePub = nil);
  AssertTrue('DropTargetNode nulled by Clear', FTree.DropTargetNode = nil);
  Layout;   // must not dereference a freed pointer
end;

{ ---- Options=[] ⇒ no drag at all ---- }

procedure TTreeDragF2Test.TestOptionsEmptyNoDrag;
begin
  FTree.Options := [];
  Layout;
  TDragTreeAccess(FTree).MouseDownPub(mbLeft, [], LabelX, RowMidY(1));
  TDragTreeAccess(FTree).MouseMovePub([ssLeft], LabelX + 20, RowMidY(1));  // way past threshold
  AssertFalse('Options=[] never starts a drag', FTree.IsDraggingNode);
  AssertTrue('Options=[] never arms a drag node',
    TDragTreeAccess(FTree).DragNodePub = nil);
end;

initialization
  RegisterTest(TTreeDragF1Test);
  RegisterTest(TTreeDragF2Test);

end.
