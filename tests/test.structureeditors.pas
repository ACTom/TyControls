unit test.structureeditors;
{$mode objfpc}{$H+}
{ The two new structure editors on the shared TTyStructureEditorForm shape: the
  TreeView node editor (any-depth Level model, subtree block moves) and the Cascader
  option editor (nested collections). The shape itself -- selection events, refresh
  keeping the selection, OI plumbing -- is pinned by test.listgrouppanel.editor;
  these pin each editor's own vocabulary. }
interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.TreeView, tyControls.Cascader,
  tyControls.Dialogs.StructureEditor,
  tyControls.Dialogs.TreeNodesEditor, tyControls.Dialogs.CascaderEditor;

type
  TTreeNodesEditorTest = class(TTestCase)
  private
    FTree: TTyTreeView;
    FForm: TTyTreeNodesEditorForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TreeMirrorsAnyDepth;
    procedure AddNodeLandsRightBelowTheSelection;
    procedure AddChildDescends;
    procedure DeleteTakesTheSubtree;
    procedure MoveCarriesTheBlockPastAWholeSibling;
  end;

  TCascaderEditorTest = class(TTestCase)
  private
    FCasc: TTyCascader;
    FForm: TTyCascaderEditorForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TreeMirrorsTheNesting;
    procedure AddNodeLandsRightBelowTheSelection;
    procedure AddChildDescends;
    procedure DeleteLandsOnTheParentWhenTheBranchEmpties;
    procedure MoveStaysWithinItsLevel;
  end;

implementation

{ ==== TreeView nodes ==== }

procedure TTreeNodesEditorTest.SetUp;
var
  a: TTyTreeNodeItem;
begin
  FTree := TTyTreeView.Create(nil);
  a := FTree.Items.AddChild(nil, 'A');
  FTree.Items.AddChild(a, 'a1');
  FTree.Items.AddChild(FTree.Items.AddChild(a, 'a2'), 'a2x');   // depth 3
  FTree.Items.AddChild(nil, 'B');
  FForm := TyBuildTreeNodesEditor(FTree);
end;

procedure TTreeNodesEditorTest.TearDown;
begin
  FForm.Free;
  FTree.Free;
end;

procedure TTreeNodesEditorTest.TreeMirrorsAnyDepth;
begin
  AssertEquals('every model row is one editor row', 5, FForm.NodeCount);
  AssertEquals('root', 0, FForm.NodeLevel(0));
  AssertEquals('child', 1, FForm.NodeLevel(1));
  AssertEquals('grandchild rides at depth 3', 2, FForm.NodeLevel(3));
  AssertTrue('rows carry their model items', FForm.NodeObject(3) = TPersistent(FTree.Items[3]));
  AssertEquals('captions are the node text', 'a2x', FForm.NodeCaption(3));
end;

procedure TTreeNodesEditorTest.AddNodeLandsRightBelowTheSelection;
begin
  FForm.SelectObject(FTree.Items[0]);        // A
  FForm.AddNode;
  { flat was A a1 a2 a2x B; the new sibling must sit right after A's whole subtree. }
  AssertEquals('one more row', 6, FTree.Items.Count);
  AssertEquals('right below A''s block', 4, TTyTreeNodeItem(FForm.SelectedObject).Index);
  AssertEquals('at A''s level', 0, TTyTreeNodeItem(FForm.SelectedObject).Level);
  AssertEquals('B slid down', 'B', FTree.Items[5].Text);
end;

procedure TTreeNodesEditorTest.AddChildDescends;
begin
  FForm.SelectObject(FTree.Items[4]);        // B
  FForm.AddChild;
  AssertEquals('the child is one deeper', 1, TTyTreeNodeItem(FForm.SelectedObject).Level);
  AssertEquals('and lives inside B', 5, TTyTreeNodeItem(FForm.SelectedObject).Index);
end;

procedure TTreeNodesEditorTest.DeleteTakesTheSubtree;
begin
  FForm.SelectObject(FTree.Items[0]);        // A with 3 descendants
  FForm.DeleteSelected;
  AssertEquals('the block went as one', 1, FTree.Items.Count);
  AssertEquals('B is what remains', 'B', FTree.Items[0].Text);
  AssertTrue('and inherits the selection', FForm.SelectedObject = TPersistent(FTree.Items[0]));
end;

procedure TTreeNodesEditorTest.MoveCarriesTheBlockPastAWholeSibling;
begin
  FForm.SelectObject(FTree.Items[4]);        // B, after A's 4-row block
  FForm.MoveSelected(-1);
  AssertEquals('B jumped the whole block', 'B', FTree.Items[0].Text);
  AssertEquals('A follows intact', 'A', FTree.Items[1].Text);
  AssertEquals('with its depth-3 tail', 'a2x', FTree.Items[4].Text);
  { And the top has nowhere further up: a no-op. }
  FForm.MoveSelected(-1);
  AssertEquals('the top stays the top', 'B', FTree.Items[0].Text);
end;

{ ==== Cascader options ==== }

procedure TCascaderEditorTest.SetUp;
var
  prov: TTyCascaderNode;
begin
  FCasc := TTyCascader.Create(nil);
  prov := FCasc.Nodes.AddNode('Zhejiang');
  prov.Children.AddNode('Hangzhou').Children.AddNode('Xihu');
  prov.Children.AddNode('Ningbo');
  FCasc.Nodes.AddNode('Jiangsu');
  FForm := TyBuildCascaderEditor(FCasc);
end;

procedure TCascaderEditorTest.TearDown;
begin
  FForm.Free;
  FCasc.Free;
end;

procedure TCascaderEditorTest.TreeMirrorsTheNesting;
begin
  AssertEquals('every option is one row', 5, FForm.NodeCount);
  AssertEquals('province', 0, FForm.NodeLevel(0));
  AssertEquals('city', 1, FForm.NodeLevel(1));
  AssertEquals('district', 2, FForm.NodeLevel(2));
  AssertEquals('captions are the option captions', 'Xihu', FForm.NodeCaption(2));
  AssertTrue('rows carry their options',
    FForm.NodeObject(2) = TPersistent(FCasc.Nodes[0].Children[0].Children[0]));
end;

procedure TCascaderEditorTest.AddNodeLandsRightBelowTheSelection;
begin
  FForm.SelectObject(FCasc.Nodes[0].Children[0]);    // Hangzhou
  FForm.AddNode;
  AssertEquals('a third city', 3, FCasc.Nodes[0].Children.Count);
  AssertEquals('right below Hangzhou', 1, TTyCascaderNode(FForm.SelectedObject).Index);
  AssertEquals('Ningbo slid down', 'Ningbo', FCasc.Nodes[0].Children[2].Caption);
end;

procedure TCascaderEditorTest.AddChildDescends;
begin
  FForm.SelectObject(FCasc.Nodes[1]);                // Jiangsu, a leaf
  FForm.AddChild;
  AssertEquals('the leaf grew a child', 1, FCasc.Nodes[1].Children.Count);
  AssertTrue('which is the selection',
    FForm.SelectedObject = TPersistent(FCasc.Nodes[1].Children[0]));
end;

procedure TCascaderEditorTest.DeleteLandsOnTheParentWhenTheBranchEmpties;
begin
  FForm.SelectObject(FCasc.Nodes[0].Children[0].Children[0]);   // Xihu, only district
  FForm.DeleteSelected;
  AssertEquals('the district is gone', 0, FCasc.Nodes[0].Children[0].Children.Count);
  AssertTrue('the emptied branch keeps the selection on its parent city',
    FForm.SelectedObject = TPersistent(FCasc.Nodes[0].Children[0]));
end;

procedure TCascaderEditorTest.MoveStaysWithinItsLevel;
begin
  FForm.SelectObject(FCasc.Nodes[0].Children[1]);    // Ningbo
  FForm.MoveSelected(-1);
  AssertEquals('the cities swapped', 'Ningbo', FCasc.Nodes[0].Children[0].Caption);
  AssertEquals('Hangzhou kept its district', 1, FCasc.Nodes[0].Children[1].Children.Count);
  FForm.MoveSelected(-1);
  AssertEquals('the top of the level stays', 'Ningbo', FCasc.Nodes[0].Children[0].Caption);
end;

initialization
  RegisterTest(TTreeNodesEditorTest);
  RegisterTest(TCascaderEditorTest);

end.
