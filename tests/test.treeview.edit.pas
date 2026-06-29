unit test.treeview.edit;
{ ③e — inline cell editing tests.
  E1: scaffolding only (toEditable option + editor field + edit-state +
  read-only props + stub methods). Headless: Create(nil), no windowing. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.TreeView;

type
  { E1: the opt-in option + edit state default to "off" }
  TTreeEditE1Test = class(TTestCase)
  published
    procedure TestEditableOptionDefaultsOff;
  end;

implementation

{ A fresh tree must NOT enable editing: toEditable is not in the default
  Options, it is not editing, and EditNode on a nil node is refused. }
procedure TTreeEditE1Test.TestEditableOptionDefaultsOff;
var
  Tree: TTyTreeView;
begin
  Tree := TTyTreeView.Create(nil);
  try
    AssertFalse('toEditable must default OFF', toEditable in Tree.Options);
    AssertFalse('IsEditing must default False', Tree.IsEditing);
    AssertFalse('EditNode(nil,0) must return False', Tree.EditNode(nil, 0));
  finally
    Tree.Free;
  end;
end;

initialization
  RegisterTest(TTreeEditE1Test);
end.
