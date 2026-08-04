unit test.parity.treeview;
{ API-PARITY guards for TTyTreeView, written against the LCL declarations they mirror:

    C:/lazarus/lcl/comctrls.pp:41-43    THitTest / THitTests
    C:/lazarus/lcl/comctrls.pp:3179     TTreeNode.Visible (ours: NodeVisible[])
    C:/lazarus/lcl/comctrls.pp:3654     TCustomTreeView.AutoExpand
    C:/lazarus/lcl/comctrls.pp:3656     TCustomTreeView.HideSelection
    C:/lazarus/lcl/comctrls.pp:3662     TCustomTreeView.MultiSelect
    C:/lazarus/lcl/comctrls.pp:3669     TCustomTreeView.OnChanging
    C:/lazarus/lcl/comctrls.pp:3681     TCustomTreeView.OnEditingEnd
    C:/lazarus/lcl/comctrls.pp:3688     TCustomTreeView.OnHasChildren
    C:/lazarus/lcl/comctrls.pp:3694-97  ReadOnly / RightClickSelect / RowSelect
    C:/lazarus/lcl/comctrls.pp:3698-99  ScrolledLeft / ScrolledTop
    C:/lazarus/lcl/comctrls.pp:3701-05  ShowLines / ShowSeparators / SortType / ToolTips
    C:/lazarus/lcl/comctrls.pp:3709/12  AlphaSort / CustomSort
    C:/lazarus/lcl/comctrls.pp:3715-17  GetHitTestInfoAt / GetNodeAt / GetNodeWithExpandSignAt
    C:/lazarus/lcl/comctrls.pp:3761     DefaultItemHeight
    C:/lazarus/lcl/comctrls.pp:3768     Images: TCustomImageList
    C:/lazarus/lcl/comctrls.pp:3777     ScrollBars: TScrollStyle
    C:/lazarus/lcl/comctrls.pp:3778-87  Selected / SelectionCount / Selections / TopItem
    C:/lazarus/lcl/comctrls.pp:3878     TTreeView.OnDragOver (the inherited TControl one)

  Three of these were not "missing" but WRONG -- our member wore LCL's name and did
  something else, so ported code compiled (or half-compiled) and misbehaved:

    GetNodeAt   ours was GetNodeAt(Y; out ANodeTop). Same name, same arity, both
                Integer, so Tree.GetNodeAt(X, Y) bound to it, read X as a scroll
                offset and clobbered the caller's Y through the out parameter. Our
                own suite proved it: renaming the method turned twelve existing
                assertions red at once.
    Selected    ours was an indexed Boolean, LCL's is THE current node.
    OnDragOver  ours was an intra-tree node-drag veto with a completely different
                signature, published over the LCL drag hook the base class offers --
                which made the tree the one TTy control that could not be a drop
                target.

  Everything here is headless: Create(nil), never parented, painted only through the
  public RenderTo. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ImgList, StdCtrls, ComCtrls,
  LCLType, Forms, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.BuiltinThemes, tyControls.TreeView;

type
  { Reaches the protected mouse/key seams the way test.treeview does. }
  TTreeParityAccess = class(TTyTreeView)
  public
    procedure XMouseDown(ABtn: TMouseButton; AShift: TShiftState; X, Y: Integer);
  end;

  { ---------------------------------------------------------------------------
    The three name collisions, plus the renamed / retyped members
    --------------------------------------------------------------------------- }
  TTreeParityNameTest = class(TTestCase)
  private
    FT: TTreeParityAccess;
    FN: array[0..3] of PTyTreeNode;
    FDragOverSeen: Boolean;
    procedure HLclDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure HNodeDragOver(Sender: TTyTreeView; Src, Target: PTyTreeNode;
      Mode: TTyTreeDropMode; var Allowed: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { GetNodeAt(X, Y) is LCL's: the node under a CLIENT POINT }
    procedure TestGetNodeAtTakesAClientPoint;
    { ...and it is not the scroll-offset lookup, which kept its own name }
    procedure TestGetNodeAtOffsetStillAnswersRowTops;
    { GetNodeAt off the rows answers nil, it does not wrap to a row }
    procedure TestGetNodeAtBelowRowsIsNil;
    { Selected is THE current node, assignable and readable }
    procedure TestSelectedIsTheCurrentNode;
    { Selected := nil clears the selection (LCL semantics) }
    procedure TestSelectedNilClearsSelection;
    { the indexed Boolean survives under its own name }
    procedure TestNodeSelectedIsStillTheIndexedFlag;
    { assigning a plain LCL TDragOverEvent to OnDragOver compiles and sticks }
    procedure TestOnDragOverIsTheLclDragHook;
    { the intra-tree veto lives on OnNodeDragOver }
    procedure TestOnNodeDragOverCarriesTheNodeVeto;
    { Images takes a TCustomImageList-typed reference }
    procedure TestImagesAcceptsCustomImageList;
    { DefaultItemHeight is DefaultNodeHeight under LCL's name }
    procedure TestDefaultItemHeightAliasesDefaultNodeHeight;
    { RowSelect / MultiSelect / ReadOnly are the Options bits }
    procedure TestOptionBitsHaveLclNames;
    { ShowLines is ShowTreeLines }
    procedure TestShowLinesAliasesShowTreeLines;
    { SelectionCount + Selections[] give the standard multi-select loop }
    procedure TestSelectionsIndexedAccess;
    { Selections[] out of range is nil, not a crash }
    procedure TestSelectionsOutOfRangeIsNil;
  end;

  { ---------------------------------------------------------------------------
    Behaviour: the switches and events that were unreachable
    --------------------------------------------------------------------------- }
  TTreeParityBehaviourTest = class(TTestCase)
  private
    FT: TTreeParityAccess;
    FN: array[0..9] of PTyTreeNode;
    FChangingSeen: Integer;
    FVeto: Boolean;
    FEndSeen: Integer;
    FEndCancel: Boolean;
    FCaptions: array of string;
    procedure HChanging(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean);
    procedure HEditingEnd(Sender: TTyTreeView; Node: PTyTreeNode; Column: Integer;
      Cancel: Boolean);
    procedure HGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ScrollBars = ssNone leaves a tall tree with no bars and no offset }
    procedure TestScrollBarsNoneSuppressesBothBars;
    { ssHorizontal forbids the vertical bar even when the content overflows }
    procedure TestScrollBarsHorizontalForbidsVerticalBar;
    { ssBoth (the default) still shows the bar a tall tree needs }
    procedure TestScrollBarsDefaultStillScrolls;
    { AutoExpand opens the focused node and closes the one it left }
    procedure TestAutoExpandOpensNewAndClosesOld;
    { AutoExpand does not close a node the new focus lives inside }
    procedure TestAutoExpandKeepsAncestorOpen;
    { AutoExpand off (the default) changes nothing }
    procedure TestAutoExpandOffLeavesNodesAlone;
    { RightClickSelect False stops a right-click moving the caret }
    procedure TestRightClickSelectFalseKeepsFocus;
    { RightClickSelect True (our default) moves it }
    procedure TestRightClickSelectTrueMovesFocus;
    { OnChanging can veto a focus move }
    procedure TestOnChangingVetoBlocksFocusMove;
    { OnChanging can veto a programmatic selection }
    procedure TestOnChangingVetoBlocksSelection;
    { OnChanging is asked ONCE per gesture, not once per internal step }
    procedure TestOnChangingAskedOncePerGesture;
    { OnChanging is not asked about a no-op }
    procedure TestOnChangingSilentOnNoOp;
    { NodeVisible[N] := False takes the node out of the visible walk and the height }
    procedure TestVisibleFalseHidesNodeAndShrinksContent;
    { ...and putting it back restores both exactly }
    procedure TestVisibleTrueRestoresContentHeight;
    { hiding the focused node drops the caret rather than parking it off-screen }
    procedure TestVisibleFalseClearsFocusAndSelection;
    { the per-node switch must NOT be called Visible -- that name belongs to the
      control's own visibility, and an indexed property would hide it }
    procedure TestControlVisibleStillMeansTheControl;
    { HasChildren[N] := True gives a leaf an expander after the fact }
    procedure TestHasChildrenTrueAddsExpander;
    { HasChildren[N] := False collapses first, so no orphan rows are left }
    procedure TestHasChildrenFalseCollapsesFirst;
    { ScrolledTop is readable and writable; TopItem follows it }
    procedure TestScrolledTopRoundTripsAndMovesTopItem;
    { TopItem := N scrolls N to the top }
    procedure TestTopItemAssignmentScrolls;
    { ScrolledTop clamps instead of parking past the end }
    procedure TestScrolledTopClampsPastEnd;
    { OnEditingEnd fires once on commit, with Cancel = False }
    procedure TestEditingEndFiresOnCommit;
    { ...and once on cancel, with Cancel = True }
    procedure TestEditingEndFiresOnCancel;
    { AlphaSort sorts by node text with NO compare handler assigned }
    procedure TestAlphaSortNeedsNoHandler;
    { AlphaSort gives the app's OnCompareNodes back afterwards }
    procedure TestAlphaSortRestoresCompareHandler;
    { CustomSort sorts with a plain function }
    procedure TestCustomSortUsesThePlainFunction;
    { GetHitTestInfoAt reports the item AND the part, in one set }
    procedure TestHitTestInfoCombinesItemAndPart;
    { off the rows it reports htBelow / htNowhere, never htOnItem }
    procedure TestHitTestInfoOffRows;
    { DisplayRect spans the row; TextOnly starts past the indent }
    procedure TestDisplayRectAndTextLeft;
    { DisplayExpandSignRect only exists for a node that has an expander }
    procedure TestDisplayExpandSignRectOnlyWhenExpandable;
    { GetNodeWithExpandSignAt answers only over the expander }
    procedure TestGetNodeWithExpandSignAt;
  end;

  { ---------------------------------------------------------------------------
    Paint-visible parity: HideSelection, ShowSeparators, and the Ghosted flag
    that reached only half the control
    --------------------------------------------------------------------------- }
  TTreeParityPaintTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FT: TTyTreeView;
    FImgs: TImageList;
    FGhost: Boolean;
    procedure HGetImageIndex(Sender: TTyTreeView; Node: PTyTreeNode;
      Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean;
      var ImageIndex: Integer);
    procedure HGetSelectedImage(Sender: TTyTreeView; Node: PTyTreeNode;
      Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean;
      var ImageIndex: Integer);
    procedure HGetOverlayImage(Sender: TTyTreeView; Node: PTyTreeNode;
      Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean;
      var ImageIndex: Integer);
    function  RenderPixel(X, Y: Integer): TBGRAPixel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { unfocused + HideSelection (the default) => the accent fill is not drawn }
    procedure TestHideSelectionSuppressesFillWhenUnfocused;
    { HideSelection := False => the accent fill is drawn regardless of focus }
    procedure TestHideSelectionFalseKeepsFill;
    { ShowSeparators draws a rule under a top-level row }
    procedure TestShowSeparatorsDrawsRule;
    { and off (the default) it does not }
    procedure TestShowSeparatorsOffDrawsNothing;
    { Ghosted reaches the icon in a 0-COLUMN tree -- the default configuration,
      which the first Ghosted fix missed }
    procedure TestGhostedChangesTheIconInAZeroColumnTree;
    { ikSelected lets a selected row show a different icon }
    procedure TestSelectedImageKindIsAsked;
    { ikOverlay draws a badge on top of the normal icon }
    procedure TestOverlayImageKindIsDrawnOnTop;
  end;

implementation

{ A plain-function compare for CustomSort: reverse the original sibling order.
  Index is still the pre-sort ordinal while the merge runs (Sort re-stamps it
  afterwards), so this is a clean "reverse me". }
function CmpReverseByIndex(Node1, Node2: PTyTreeNode): Integer;
begin
  Result := Integer(Node2^.Index) - Integer(Node1^.Index);
end;

{ ── TTreeParityAccess ────────────────────────────────────────────────────── }

procedure TTreeParityAccess.XMouseDown(ABtn: TMouseButton; AShift: TShiftState;
  X, Y: Integer);
begin
  MouseDown(ABtn, AShift, X, Y);
end;

{ ── TTreeParityNameTest ──────────────────────────────────────────────────── }

procedure TTreeParityNameTest.HLclDragOver(Sender, Source: TObject;
  X, Y: Integer; State: TDragState; var Accept: Boolean);
begin
  FDragOverSeen := True;
  Accept := False;
end;

procedure TTreeParityNameTest.HNodeDragOver(Sender: TTyTreeView;
  Src, Target: PTyTreeNode; Mode: TTyTreeDropMode; var Allowed: Boolean);
begin
  FDragOverSeen := True;
  Allowed := False;
end;

procedure TTreeParityNameTest.SetUp;
var
  i: Integer;
begin
  FT := TTreeParityAccess.Create(nil);
  FT.Font.PixelsPerInch := 96;
  FT.DefaultNodeHeight  := 18;
  FT.SetBounds(0, 0, 200, 160);
  for i := 0 to High(FN) do
  begin
    FN[i] := FT.AddChild(nil);
    Include(FN[i]^.States, nsInitialized);
  end;
  { node 0 gets children so it has an expander }
  Include(FN[0]^.States, nsHasChildren);
  FDragOverSeen := False;
end;

procedure TTreeParityNameTest.TearDown;
begin
  FreeAndNil(FT);
end;

procedure TTreeParityNameTest.TestGetNodeAtTakesAClientPoint;
begin
  { Row 1 covers y = 18..35; x = 60 is well inside the caption zone. If GetNodeAt
    still meant "scroll offset", (60, 20) would answer the node at offset 60 --
    node 3 -- and would have overwritten the caller's second argument. }
  AssertTrue('GetNodeAt(60, 20) is row 1', FT.GetNodeAt(60, 20) = FN[1]);
  AssertTrue('GetNodeAt(60, 2)  is row 0', FT.GetNodeAt(60, 2)  = FN[0]);
  AssertTrue('GetNodeAt(60, 56) is row 3', FT.GetNodeAt(60, 56) = FN[3]);
end;

procedure TTreeParityNameTest.TestGetNodeAtOffsetStillAnswersRowTops;
var
  n: PTyTreeNode;
  nodeTop: Integer;
begin
  n := FT.GetNodeAtOffset(20, nodeTop);
  AssertTrue('GetNodeAtOffset(20) is row 1', n = FN[1]);
  AssertEquals('GetNodeAtOffset(20) reports the row top', 18, nodeTop);
end;

procedure TTreeParityNameTest.TestGetNodeAtBelowRowsIsNil;
begin
  AssertTrue('below every row', FT.GetNodeAt(60, 500) = nil);
  AssertTrue('above every row', FT.GetNodeAt(60, -5)  = nil);
end;

procedure TTreeParityNameTest.TestSelectedIsTheCurrentNode;
begin
  FT.Selected := FN[2];
  AssertTrue('Selected reads back the node',  FT.Selected = FN[2]);
  AssertTrue('and the node really is selected', FT.NodeSelected[FN[2]]);
  AssertTrue('and it took the caret with it', FT.FocusedNode = FN[2]);
  AssertEquals('exactly one node selected', 1, FT.SelectedCount);
end;

procedure TTreeParityNameTest.TestSelectedNilClearsSelection;
begin
  FT.Selected := FN[1];
  FT.Selected := nil;
  AssertTrue('Selected is nil after clearing', FT.Selected = nil);
  AssertEquals('nothing selected', 0, FT.SelectedCount);
end;

procedure TTreeParityNameTest.TestNodeSelectedIsStillTheIndexedFlag;
begin
  FT.NodeSelected[FN[1]] := True;
  AssertTrue('NodeSelected[n] set',   FT.NodeSelected[FN[1]]);
  AssertFalse('and only that one',    FT.NodeSelected[FN[2]]);
  FT.NodeSelected[FN[1]] := False;
  AssertFalse('NodeSelected[n] clear', FT.NodeSelected[FN[1]]);
end;

procedure TTreeParityNameTest.TestOnDragOverIsTheLclDragHook;
var
  accept: Boolean;
begin
  { The assignment itself is the guard: OnDragOver must take a TDragOverEvent.
    While TTyTreeDragOverEvent was published under this name it was a type error. }
  FT.OnDragOver := @HLclDragOver;
  AssertTrue('OnDragOver holds the LCL handler', Assigned(FT.OnDragOver));
  accept := True;
  FT.OnDragOver(FT, FT, 0, 0, dsDragEnter, accept);
  AssertTrue('and it is the one that ran', FDragOverSeen);
  AssertFalse('with its own Accept out-parameter', accept);
end;

procedure TTreeParityNameTest.TestOnNodeDragOverCarriesTheNodeVeto;
var
  allowed: Boolean;
begin
  FT.OnNodeDragOver := @HNodeDragOver;
  AssertTrue('OnNodeDragOver holds the node handler', Assigned(FT.OnNodeDragOver));
  allowed := True;
  FT.OnNodeDragOver(FT, FN[0], FN[1], dmOn, allowed);
  AssertTrue('the node veto ran', FDragOverSeen);
  AssertFalse('and vetoed', allowed);
end;

procedure TTreeParityNameTest.TestImagesAcceptsCustomImageList;
var
  il: TCustomImageList;
begin
  { The declared type of the variable is the guard: with Images: TImageList this
    assignment did not compile, which locked out TLCLGlyphs and every other
    TCustomImageList descendant. }
  il := TImageList.Create(nil);
  try
    FT.Images := il;
    AssertTrue('Images holds the TCustomImageList', FT.Images = il);
  finally
    FT.Images := nil;
    il.Free;
  end;
end;

procedure TTreeParityNameTest.TestDefaultItemHeightAliasesDefaultNodeHeight;
var
  c: TTyStyleController;
  t: TTyTreeView;
begin
  FT.DefaultItemHeight := 27;
  AssertEquals('DefaultItemHeight reads back', 27, FT.DefaultItemHeight);
  AssertEquals('and it IS DefaultNodeHeight',  27, FT.DefaultNodeHeight);
  FT.DefaultNodeHeight := 31;
  AssertEquals('both directions', 31, FT.DefaultItemHeight);

  { An alias that only forwards the STORED field would read identically here and
    still be wrong: unpinned, the height follows the density token, and reading the
    raw field would report the classic fallback on a modern tree. }
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  t := TTyTreeView.Create(nil);
  try
    c.ThemeName := 'default';
    t.Controller := c;
    c.Density := tdModern;
    AssertTrue('unpinned, DefaultNodeHeight rides the density token',
      t.DefaultNodeHeight > 30);
    AssertEquals('and DefaultItemHeight is the SAME reader, not the raw field',
      t.DefaultNodeHeight, t.DefaultItemHeight);
  finally
    t.Free;
    c.Free;
  end;
end;

procedure TTreeParityNameTest.TestOptionBitsHaveLclNames;
begin
  AssertFalse('RowSelect starts off',   FT.RowSelect);
  AssertFalse('MultiSelect starts off', FT.MultiSelect);
  AssertTrue('ReadOnly starts TRUE -- editing here is opt-in', FT.ReadOnly);

  { Each one must READ BACK what it wrote and must not answer for a different bit --
    four aliases over one set is exactly where a copy-paste getter goes unnoticed. }
  FT.RowSelect := True;
  AssertTrue('RowSelect is toFullRowSelect', toFullRowSelect in FT.Options);
  AssertTrue('and RowSelect reads back True', FT.RowSelect);
  AssertFalse('without dragging MultiSelect with it', FT.MultiSelect);
  AssertTrue('and ReadOnly is still True',    FT.ReadOnly);

  FT.MultiSelect := True;
  AssertTrue('MultiSelect is toMultiSelect', toMultiSelect in FT.Options);
  AssertTrue('and reads back True',          FT.MultiSelect);

  FT.ReadOnly := False;
  AssertTrue('ReadOnly := False is toEditable', toEditable in FT.Options);
  AssertFalse('and reads back False',           FT.ReadOnly);

  FT.RowSelect := False;
  AssertFalse('and back off again',          toFullRowSelect in FT.Options);
  AssertFalse('RowSelect reads back False',  FT.RowSelect);
  AssertTrue('while MultiSelect is untouched', FT.MultiSelect);

  FT.ReadOnly := True;
  AssertFalse('ReadOnly := True drops toEditable', toEditable in FT.Options);
  AssertTrue('and reads back True',                FT.ReadOnly);
end;

procedure TTreeParityNameTest.TestShowLinesAliasesShowTreeLines;
begin
  AssertTrue('ShowLines mirrors the default', FT.ShowLines);
  FT.ShowLines := False;
  AssertFalse('ShowTreeLines followed', FT.ShowTreeLines);
  FT.ShowTreeLines := True;
  AssertTrue('and the other way round', FT.ShowLines);
end;

procedure TTreeParityNameTest.TestSelectionsIndexedAccess;
begin
  FT.Options := [toMultiSelect];
  FT.InternalSetSelected(FN[0], True);
  FT.InternalSetSelected(FN[2], True);
  AssertEquals('SelectionCount', 2, FT.SelectionCount);
  AssertTrue('Selections[0] is the first in screen order', FT.Selections[0] = FN[0]);
  AssertTrue('Selections[1] is the second',                FT.Selections[1] = FN[2]);
  AssertTrue('GetLastSelected agrees with Selections[last]', FT.GetLastSelected = FN[2]);
end;

procedure TTreeParityNameTest.TestSelectionsOutOfRangeIsNil;
begin
  FT.InternalSetSelected(FN[0], True);
  AssertTrue('past the end',  FT.Selections[5]  = nil);
  AssertTrue('negative index', FT.Selections[-1] = nil);
end;

{ ── TTreeParityBehaviourTest ─────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.HChanging(Sender: TTyTreeView;
  Node: PTyTreeNode; var Allowed: Boolean);
begin
  Inc(FChangingSeen);
  if FVeto then Allowed := False;
end;

procedure TTreeParityBehaviourTest.HEditingEnd(Sender: TTyTreeView;
  Node: PTyTreeNode; Column: Integer; Cancel: Boolean);
begin
  Inc(FEndSeen);
  FEndCancel := Cancel;
end;

procedure TTreeParityBehaviourTest.HGetText(Sender: TTyTreeView;
  Node: PTyTreeNode; var Text: string);
var
  i: Integer;
begin
  Text := '';
  { The caption store is keyed by the node's ORIGINAL creation ordinal, which we
    stashed in the node data blob -- Index is re-stamped by a sort. }
  if Node = nil then Exit;
  i := PInteger(Sender.GetNodeData(Node))^;
  if (i >= 0) and (i <= High(FCaptions)) then Text := FCaptions[i];
end;

procedure TTreeParityBehaviourTest.SetUp;
var
  i: Integer;
begin
  FT := TTreeParityAccess.Create(nil);
  FT.Font.PixelsPerInch := 96;
  FT.NodeDataSize      := SizeOf(Integer);
  FT.DefaultNodeHeight := 18;
  FT.SetBounds(0, 0, 200, 160);
  for i := 0 to High(FN) do
  begin
    FN[i] := FT.AddChild(nil);
    Include(FN[i]^.States, nsInitialized);
    PInteger(FT.GetNodeData(FN[i]))^ := i;
  end;
  FChangingSeen := 0;
  FVeto  := False;
  FEndSeen   := 0;
  FEndCancel := False;
  FCaptions  := nil;
end;

procedure TTreeParityBehaviourTest.TearDown;
begin
  FreeAndNil(FT);
end;

{ ── ScrollBars ───────────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestScrollBarsDefaultStillScrolls;
begin
  FT.SetBounds(0, 0, 200, 40);   { 10 rows x 18 = 180 > 40 }
  AssertTrue('default ssBoth still shows the vertical bar', FT.VScroll.Visible);
end;

procedure TTreeParityBehaviourTest.TestScrollBarsNoneSuppressesBothBars;
begin
  FT.SetBounds(0, 0, 200, 40);
  FT.ScrollBars := ssNone;
  AssertFalse('ssNone: no vertical bar',   FT.VScroll.Visible);
  AssertFalse('ssNone: no horizontal bar', FT.HScroll.Visible);
  AssertEquals('and the viewport is pinned at the top', 0, FT.OffsetY);
end;

procedure TTreeParityBehaviourTest.TestScrollBarsHorizontalForbidsVerticalBar;
begin
  FT.SetBounds(0, 0, 200, 40);
  FT.ScrollBars := ssHorizontal;
  AssertFalse('ssHorizontal forbids the vertical bar', FT.VScroll.Visible);
end;

{ ── AutoExpand ───────────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestAutoExpandOpensNewAndClosesOld;
begin
  Include(FN[0]^.States, nsHasChildren);
  Include(FN[1]^.States, nsHasChildren);
  FT.AddChild(FN[0]);
  FT.AddChild(FN[1]);

  FT.AutoExpand := True;
  FT.FocusedNode := FN[0];
  AssertTrue('the focused node opened', FT.Expanded[FN[0]]);

  FT.FocusedNode := FN[1];
  AssertTrue('the new focus opened',    FT.Expanded[FN[1]]);
  AssertFalse('and the old one closed', FT.Expanded[FN[0]]);
end;

procedure TTreeParityBehaviourTest.TestAutoExpandKeepsAncestorOpen;
var
  child: PTyTreeNode;
begin
  Include(FN[0]^.States, nsHasChildren);
  child := FT.AddChild(FN[0]);
  Include(child^.States, nsInitialized);

  FT.AutoExpand := True;
  FT.FocusedNode := FN[0];
  AssertTrue('parent opened', FT.Expanded[FN[0]]);
  FT.FocusedNode := child;
  AssertTrue('walking INTO the subtree must not shut it', FT.Expanded[FN[0]]);
end;

procedure TTreeParityBehaviourTest.TestAutoExpandOffLeavesNodesAlone;
begin
  Include(FN[0]^.States, nsHasChildren);
  FT.AddChild(FN[0]);
  FT.FocusedNode := FN[0];
  AssertFalse('AutoExpand off is the default and does nothing', FT.Expanded[FN[0]]);
end;

{ ── RightClickSelect ─────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestRightClickSelectTrueMovesFocus;
begin
  FT.FocusedNode := FN[0];
  FT.XMouseDown(mbRight, [], 60, 20);   { row 1 }
  AssertTrue('our default moves the caret to the clicked row', FT.FocusedNode = FN[1]);
end;

procedure TTreeParityBehaviourTest.TestRightClickSelectFalseKeepsFocus;
begin
  FT.FocusedNode := FN[0];
  FT.RightClickSelect := False;
  FT.XMouseDown(mbRight, [], 60, 20);
  AssertTrue('a context menu can act on the existing selection', FT.FocusedNode = FN[0]);
end;

{ ── OnChanging ───────────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestOnChangingVetoBlocksFocusMove;
begin
  FT.FocusedNode := FN[0];
  FT.OnChanging := @HChanging;
  FVeto := True;
  FT.FocusedNode := FN[1];
  AssertTrue('the caret did not move',    FT.FocusedNode = FN[0]);
  AssertFalse('and nothing got selected', FT.NodeSelected[FN[1]]);
  AssertTrue('the handler was asked',     FChangingSeen > 0);
end;

procedure TTreeParityBehaviourTest.TestOnChangingVetoBlocksSelection;
begin
  FT.OnChanging := @HChanging;
  FVeto := True;
  FT.NodeSelected[FN[2]] := True;
  AssertFalse('a programmatic select is vetoable too', FT.NodeSelected[FN[2]]);
  AssertEquals('nothing selected', 0, FT.SelectedCount);
end;

procedure TTreeParityBehaviourTest.TestOnChangingAskedOncePerGesture;
begin
  FT.OnChanging := @HChanging;
  FT.FocusedNode := FN[1];
  AssertEquals('one question for one focus move', 1, FChangingSeen);
  AssertTrue('and it went through', FT.FocusedNode = FN[1]);
end;

procedure TTreeParityBehaviourTest.TestOnChangingSilentOnNoOp;
begin
  FT.FocusedNode := FN[1];
  FT.OnChanging := @HChanging;
  FT.FocusedNode := FN[1];        { same node }
  AssertEquals('no question about a change that is not happening', 0, FChangingSeen);
end;

{ ── Visible[] ────────────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestVisibleFalseHidesNodeAndShrinksContent;
var
  before: Integer;
  n: PTyTreeNode;
  seen: Boolean;
begin
  before := FT.ContentHeight;
  FT.NodeVisible[FN[3]] := False;
  AssertFalse('NodeVisible reads back False', FT.NodeVisible[FN[3]]);
  AssertEquals('one row of content gone', before - 18, FT.ContentHeight);

  seen := False;
  n := FT.GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if n = FN[3] then seen := True;
    n := FT.GetNextVisibleNoInit(n);
  end;
  AssertFalse('the hidden node is out of the visible walk', seen);
  AssertEquals('and the walk agrees with the bookkeeping',
    FT.ContentHeight, FT.SumVisibleHeights - Integer(FT.RootNode^.NodeHeight));
end;

procedure TTreeParityBehaviourTest.TestVisibleTrueRestoresContentHeight;
var
  before: Integer;
begin
  before := FT.ContentHeight;
  FT.NodeVisible[FN[2]] := False;
  FT.NodeVisible[FN[2]] := True;
  AssertTrue('NodeVisible reads back True', FT.NodeVisible[FN[2]]);
  AssertEquals('the height came back exactly', before, FT.ContentHeight);
  AssertEquals('and the walk still agrees',
    FT.ContentHeight, FT.SumVisibleHeights - Integer(FT.RootNode^.NodeHeight));
end;

procedure TTreeParityBehaviourTest.TestVisibleFalseClearsFocusAndSelection;
begin
  FT.FocusedNode := FN[4];
  AssertTrue('precondition: selected', FT.NodeSelected[FN[4]]);
  FT.NodeVisible[FN[4]] := False;
  AssertTrue('the caret does not stay on a row nothing draws', FT.FocusedNode = nil);
  AssertFalse('nor does the selection', FT.NodeSelected[FN[4]]);
  AssertEquals('count kept honest', 0, FT.SelectedCount);
end;

{ ── HasChildren[] ────────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestControlVisibleStillMeansTheControl;
begin
  { LCL hangs the per-node flag on TTreeNode, a class. Our nodes are records, so it
    has to live on the control -- and calling it Visible there would shadow
    TControl.Visible and turn this line into a compile error. It is NodeVisible for
    exactly that reason; this line is the guard. }
  FT.Visible := False;
  AssertFalse('Tree.Visible is still the CONTROL''s visibility', FT.Visible);
  FT.Visible := True;
  AssertTrue('and it round-trips', FT.Visible);
  AssertTrue('while the node flag is untouched', FT.NodeVisible[FN[0]]);
end;

procedure TTreeParityBehaviourTest.TestHasChildrenTrueAddsExpander;
var
  part: TTyTreeHitPart;
begin
  AssertFalse('a fresh leaf has none', FT.HasChildren[FN[1]]);
  AssertTrue('and no expander to hit',
    FT.GetNodeAtPoint(8, 20, part) <> nil);
  AssertTrue('...which is not the button', part <> hpButton);

  FT.HasChildren[FN[1]] := True;
  AssertTrue('HasChildren reads back', FT.HasChildren[FN[1]]);
  FT.GetNodeAtPoint(8, 20, part);
  AssertTrue('a directory that became non-empty now has an expander',
    part = hpButton);
end;

procedure TTreeParityBehaviourTest.TestHasChildrenFalseCollapsesFirst;
begin
  Include(FN[0]^.States, nsHasChildren);
  FT.AddChild(FN[0]);
  FT.Expanded[FN[0]] := True;
  AssertTrue('precondition: expanded', FT.Expanded[FN[0]]);

  FT.HasChildren[FN[0]] := False;
  AssertFalse('the flag is gone',   FT.HasChildren[FN[0]]);
  AssertFalse('and so is the open state -- no rows without a way to close them',
    FT.Expanded[FN[0]]);
  AssertEquals('the height bookkeeping followed the collapse',
    FT.ContentHeight, FT.SumVisibleHeights - Integer(FT.RootNode^.NodeHeight));
end;

{ ── scroll position ──────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestScrolledTopRoundTripsAndMovesTopItem;
begin
  FT.SetBounds(0, 0, 200, 40);
  AssertEquals('starts at the top', 0, FT.ScrolledTop);
  AssertTrue('TopItem is row 0', FT.TopItem = FN[0]);

  FT.ScrolledTop := 36;
  AssertEquals('ScrolledTop reads back what was written', 36, FT.ScrolledTop);
  AssertEquals('and OffsetY is its negation', -36, FT.OffsetY);
  AssertTrue('TopItem followed', FT.TopItem = FN[2]);
end;

procedure TTreeParityBehaviourTest.TestTopItemAssignmentScrolls;
begin
  FT.SetBounds(0, 0, 200, 40);
  FT.TopItem := FN[4];
  AssertEquals('row 4 starts at 4 * 18', 72, FT.ScrolledTop);
  AssertTrue('and it is the top row now', FT.TopItem = FN[4]);
end;

procedure TTreeParityBehaviourTest.TestScrolledTopClampsPastEnd;
begin
  FT.SetBounds(0, 0, 200, 40);
  FT.ScrolledTop := 100000;
  AssertTrue('a stale restore cannot park past the content',
    FT.ScrolledTop <= 180 - 40);
  AssertTrue('and something is still on screen', FT.TopItem <> nil);
end;

{ ── OnEditingEnd ─────────────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestEditingEndFiresOnCommit;
begin
  FT.Options := [toEditable];
  FT.OnEditingEnd := @HEditingEnd;
  AssertTrue('editor opened', FT.EditNode(FN[0], -1));
  FT.EndEditNode;
  AssertEquals('one end-of-edit notification', 1, FEndSeen);
  AssertFalse('committed, so Cancel is False', FEndCancel);
end;

procedure TTreeParityBehaviourTest.TestEditingEndFiresOnCancel;
begin
  FT.Options := [toEditable];
  FT.OnEditingEnd := @HEditingEnd;
  AssertTrue('editor opened', FT.EditNode(FN[0], -1));
  FT.CancelEdit;
  AssertEquals('one end-of-edit notification', 1, FEndSeen);
  AssertTrue('abandoned, so Cancel is True', FEndCancel);
end;

{ ── AlphaSort / CustomSort ───────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestAlphaSortNeedsNoHandler;
var
  n: PTyTreeNode;
  order: string;
  i: Integer;
begin
  SetLength(FCaptions, 10);
  for i := 0 to 9 do FCaptions[i] := '';
  FCaptions[0] := 'delta';
  FCaptions[1] := 'Alpha';
  FCaptions[2] := 'charlie';
  FCaptions[3] := 'Bravo';
  { keep the tree to those four }
  for i := 9 downto 4 do FT.DeleteNode(FN[i]);
  FT.OnGetText := @HGetText;

  AssertFalse('no compare handler assigned', Assigned(FT.OnCompareNodes));
  FT.AlphaSort;

  order := '';
  n := FT.RootNode^.FirstChild;
  while n <> nil do
  begin
    order := order + FCaptions[PInteger(FT.GetNodeData(n))^] + ' ';
    n := n^.NextSibling;
  end;
  AssertEquals('alphabetical, case-insensitive, with no handler at all',
    'Alpha Bravo charlie delta ', order);
end;

procedure TTreeParityBehaviourTest.TestAlphaSortRestoresCompareHandler;
begin
  SetLength(FCaptions, 10);
  FT.OnGetText := @HGetText;
  FT.OnCompareNodes := nil;
  FT.AlphaSort;
  AssertFalse('still nil afterwards', Assigned(FT.OnCompareNodes));
end;

procedure TTreeParityBehaviourTest.TestCustomSortUsesThePlainFunction;
var
  n: PTyTreeNode;
  order: string;
  i: Integer;
begin
  for i := 9 downto 4 do FT.DeleteNode(FN[i]);
  AssertTrue('CustomSort ran', FT.CustomSort(@CmpReverseByIndex));

  order := '';
  n := FT.RootNode^.FirstChild;
  while n <> nil do
  begin
    order := order + IntToStr(PInteger(FT.GetNodeData(n))^);
    n := n^.NextSibling;
  end;
  AssertEquals('a plain function drove the order', '3210', order);
end;

{ ── hit-test / geometry ──────────────────────────────────────────────────── }

procedure TTreeParityBehaviourTest.TestHitTestInfoCombinesItemAndPart;
var
  hits: THitTests;
begin
  Include(FN[1]^.States, nsHasChildren);
  hits := FT.GetHitTestInfoAt(8, 20);       { the expander slot of row 1 }
  AssertTrue('htOnItem',   htOnItem   in hits);
  AssertTrue('AND htOnButton -- the pair a single-valued enum cannot express',
    htOnButton in hits);

  hits := FT.GetHitTestInfoAt(60, 20);      { the caption }
  AssertTrue('htOnItem on the label too', htOnItem  in hits);
  AssertTrue('htOnLabel',                 htOnLabel in hits);
  AssertFalse('and not the button',       htOnButton in hits);
end;

procedure TTreeParityBehaviourTest.TestHitTestInfoOffRows;
var
  hits: THitTests;
begin
  hits := FT.GetHitTestInfoAt(60, 500);
  AssertFalse('nothing is on an item down there', htOnItem in hits);
  AssertTrue('below the rows', htBelow in hits);
end;

procedure TTreeParityBehaviourTest.TestDisplayRectAndTextLeft;
var
  row, txt, cr: TRect;
  left: Integer;
begin
  { Geometry is in ContentRect space, so every expectation is relative to CR --
    the themed padding is a real offset even with the default controller. }
  cr := FT.ContentRect;
  AssertTrue('row rect available', FT.DisplayRect(FN[1], False, row));
  AssertEquals('row 1 top',    cr.Top + 18, row.Top);
  AssertEquals('row 1 bottom', cr.Top + 36, row.Bottom);
  AssertTrue('and it spans the content width', row.Right > row.Left + 100);

  AssertTrue('text rect available', FT.DisplayRect(FN[1], True, txt));
  AssertTrue('the caption starts past the indent', txt.Left >= cr.Left + 16);
  AssertTrue('and inside the row', txt.Right <= row.Right);

  AssertTrue('DisplayTextLeft agrees', FT.DisplayTextLeft(FN[1], left));
  AssertEquals('with the text rect', txt.Left, left);
end;

procedure TTreeParityBehaviourTest.TestDisplayExpandSignRectOnlyWhenExpandable;
var
  r, cr: TRect;
begin
  cr := FT.ContentRect;
  AssertFalse('a leaf has no expander rect', FT.DisplayExpandSignRect(FN[1], r));

  Include(FN[1]^.States, nsHasChildren);
  AssertTrue('an expandable node does', FT.DisplayExpandSignRect(FN[1], r));
  AssertTrue('non-empty', (r.Right > r.Left) and (r.Bottom > r.Top));
  AssertTrue('and it sits left of the caption', r.Right <= cr.Left + 16);
  AssertTrue('inside row 1 vertically',
    (r.Top >= cr.Top + 18) and (r.Bottom <= cr.Top + 36));
end;

procedure TTreeParityBehaviourTest.TestGetNodeWithExpandSignAt;
begin
  Include(FN[1]^.States, nsHasChildren);
  AssertTrue('over the expander',  FT.GetNodeWithExpandSignAt(8, 20) = FN[1]);
  AssertTrue('over the caption is not the expander',
    FT.GetNodeWithExpandSignAt(60, 20) = nil);
  AssertTrue('a leaf never answers', FT.GetNodeWithExpandSignAt(8, 38) = nil);
end;

{ ── TTreeParityPaintTest ─────────────────────────────────────────────────── }

procedure TTreeParityPaintTest.HGetImageIndex(Sender: TTyTreeView;
  Node: PTyTreeNode; Kind: TTyVTImageKind; Column: Integer;
  var Ghosted: Boolean; var ImageIndex: Integer);
begin
  if Kind <> ikNormal then Exit;
  ImageIndex := 0;
  Ghosted    := FGhost;
end;

procedure TTreeParityPaintTest.HGetSelectedImage(Sender: TTyTreeView;
  Node: PTyTreeNode; Kind: TTyVTImageKind; Column: Integer;
  var Ghosted: Boolean; var ImageIndex: Integer);
begin
  case Kind of
    ikNormal:   ImageIndex := 0;   { blue }
    ikSelected: ImageIndex := 1;   { green }
  end;
end;

procedure TTreeParityPaintTest.HGetOverlayImage(Sender: TTyTreeView;
  Node: PTyTreeNode; Kind: TTyVTImageKind; Column: Integer;
  var Ghosted: Boolean; var ImageIndex: Integer);
begin
  case Kind of
    ikNormal:  ImageIndex := 0;   { blue }
    ikOverlay: ImageIndex := 1;   { green badge over it }
  end;
end;

function TTreeParityPaintTest.RenderPixel(X, Y: Integer): TBGRAPixel;
var
  bmp: TBitmap;
  wrap: TBGRABitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FT.Width, FT.Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    FT.RenderTo(bmp.Canvas, Rect(0, 0, bmp.Width, bmp.Height), 96);
    wrap := TBGRABitmap.Create(bmp, True);
    try
      Result := wrap.GetPixel(X, Y);
    finally
      wrap.Free;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TTreeParityPaintTest.SetUp;
var
  i: Integer;
  n: PTyTreeNode;
  glyph: TBitmap;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyTreeView { background: #FFFFFF; border-width: 0px; padding: 0px; border-color: #FF0000; } ' +
    'TyTreeNode { background: none; color: #000000; } ' +
    'TyTreeNode:selected { background: #3B82F6; color: #FFFFFF; }');

  FT := TTyTreeView.Create(nil);
  FT.Controller := FCtl;
  FT.Font.PixelsPerInch := 96;
  FT.DefaultNodeHeight  := 18;
  FT.ShowTreeLines      := False;   { keep the probe pixels free of chrome }
  FT.ShowButtons        := False;
  FT.SetBounds(0, 0, 200, 160);
  for i := 0 to 3 do
  begin
    n := FT.AddChild(nil);
    Include(n^.States, nsInitialized);
  end;

  { two 16x16 solid glyphs: 0 = blue, 1 = green }
  FImgs := TImageList.Create(nil);
  FImgs.Width  := 16;
  FImgs.Height := 16;
  glyph := TBitmap.Create;
  try
    glyph.PixelFormat := pf24bit;
    glyph.SetSize(16, 16);
    glyph.Canvas.Brush.Color := clBlue;
    glyph.Canvas.FillRect(0, 0, 16, 16);
    FImgs.Add(glyph, nil);
    glyph.Canvas.Brush.Color := clLime;
    glyph.Canvas.FillRect(0, 0, 16, 16);
    FImgs.Add(glyph, nil);
  finally
    glyph.Free;
  end;

  FGhost := False;
end;

procedure TTreeParityPaintTest.TearDown;
begin
  if FT <> nil then FT.Images := nil;
  FreeAndNil(FImgs);
  FreeAndNil(FT);
  FreeAndNil(FCtl);
end;

procedure TTreeParityPaintTest.TestHideSelectionSuppressesFillWhenUnfocused;
var
  px: TBGRAPixel;
begin
  FT.NodeSelected[FT.RootNode^.FirstChild] := True;
  AssertTrue('HideSelection defaults True, like LCL', FT.HideSelection);
  AssertFalse('and a headless control is not focused', FT.Focused);
  px := RenderPixel(120, 8);
  AssertTrue('an inactive selection must not paint the accent fill', px.blue < 150);
end;

procedure TTreeParityPaintTest.TestHideSelectionFalseKeepsFill;
var
  px: TBGRAPixel;
begin
  FT.HideSelection := False;
  FT.NodeSelected[FT.RootNode^.FirstChild] := True;
  px := RenderPixel(120, 8);
  AssertTrue('with HideSelection off the fill stays', px.blue > 150);
  AssertTrue('and it is the accent, not white',       px.red  < 120);
end;

procedure TTreeParityPaintTest.TestShowSeparatorsDrawsRule;
var
  px: TBGRAPixel;
begin
  FT.ShowSeparators := True;
  px := RenderPixel(120, 17);          { last scanline of row 0 }
  AssertTrue('a rule is drawn under the top-level row',
    (px.red > 150) and (px.green < 100) and (px.blue < 100));
end;

procedure TTreeParityPaintTest.TestShowSeparatorsOffDrawsNothing;
var
  px: TBGRAPixel;
begin
  AssertFalse('off by default, like LCL', FT.ShowSeparators);
  px := RenderPixel(120, 17);
  AssertFalse('nothing is drawn there',
    (px.red > 150) and (px.green < 100) and (px.blue < 100));
end;

procedure TTreeParityPaintTest.TestGhostedChangesTheIconInAZeroColumnTree;
var
  normal, ghosted: TBGRAPixel;
begin
  { NO columns -- this is the default tree, and the branch the first Ghosted fix
    did not reach: the flag was collected into a local and dropped, so an app
    setting Ghosted := True saw nothing change. }
  AssertEquals('precondition: a 0-column tree', 0, FT.Header.Columns.Count);
  FT.Images          := FImgs;
  FT.OnGetImageIndex := @HGetImageIndex;

  FGhost  := False;
  normal  := RenderPixel(20, 8);
  FGhost  := True;
  ghosted := RenderPixel(20, 8);

  AssertTrue('the un-ghosted icon is the blue glyph',
    (normal.blue > 150) and (normal.red < 120));
  AssertFalse('Ghosted := True must change what is drawn',
    (ghosted.blue = normal.blue) and (ghosted.red = normal.red) and
    (ghosted.green = normal.green));
end;

procedure TTreeParityPaintTest.TestSelectedImageKindIsAsked;
var
  plain, selected: TBGRAPixel;
begin
  FT.HideSelection   := False;   { we are probing the ICON, not the row fill }
  FT.Images          := FImgs;
  FT.OnGetImageIndex := @HGetSelectedImage;

  plain := RenderPixel(20, 8);
  AssertTrue('unselected row shows the ikNormal glyph (blue)',
    (plain.blue > 150) and (plain.green < 120));

  FT.NodeSelected[FT.RootNode^.FirstChild] := True;
  selected := RenderPixel(20, 8);
  AssertTrue('a selected row shows the ikSelected glyph (green)',
    (selected.green > 150) and (selected.blue < 120));
end;

procedure TTreeParityPaintTest.TestOverlayImageKindIsDrawnOnTop;
var
  px: TBGRAPixel;
begin
  FT.Images          := FImgs;
  FT.OnGetImageIndex := @HGetOverlayImage;
  px := RenderPixel(20, 8);
  AssertTrue('the overlay badge is painted over the normal icon',
    (px.green > 150) and (px.blue < 120));
end;

initialization
  RegisterTest(TTreeParityNameTest);
  RegisterTest(TTreeParityBehaviourTest);
  RegisterTest(TTreeParityPaintTest);

end.
