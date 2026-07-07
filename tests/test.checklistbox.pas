unit test.checklistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.CheckListBox;
type
  TCheckListBoxTest = class(TTestCase)
  published
    procedure TestCheckedState;
    procedure TestCheckedCount;
    procedure TestSortedKeepsChecks;
    procedure TestOutOfRange;
  end;
implementation

procedure TCheckListBoxTest.TestCheckedState;
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a'); c.Items.Add('b'); c.Items.Add('c');
    AssertFalse('default unchecked', c.Checked[0]);
    c.Checked[1] := True;
    AssertTrue('now checked', c.Checked[1]);
    c.Checked[1] := False;
    AssertFalse('unchecked again', c.Checked[1]);
  finally c.Free; end;
end;

procedure TCheckListBoxTest.TestCheckedCount;
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a'); c.Items.Add('b'); c.Items.Add('c');
    AssertEquals('none', 0, c.CheckedCount);
    c.Checked[0] := True;
    c.Checked[2] := True;
    AssertEquals('two', 2, c.CheckedCount);
  finally c.Free; end;
end;

procedure TCheckListBoxTest.TestSortedKeepsChecks;
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('Zebra'); c.Items.Add('Apple'); c.Items.Add('Mango');
    c.Checked[c.Items.IndexOf('Apple')] := True;   // check state in Objects[]
    c.Sorted := True;                              // reorders the names
    AssertTrue('Apple still checked after sort', c.Checked[c.Items.IndexOf('Apple')]);
    AssertFalse('Zebra still unchecked', c.Checked[c.Items.IndexOf('Zebra')]);
    AssertEquals('still one checked', 1, c.CheckedCount);
  finally c.Free; end;
end;

procedure TCheckListBoxTest.TestOutOfRange;
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a');
    AssertFalse('out of range is False', c.Checked[99]);
    c.Checked[99] := True;   // must be a safe no-op
    AssertEquals('no phantom item', 1, c.Items.Count);
  finally c.Free; end;
end;

initialization
  RegisterTest(TCheckListBoxTest);
end.
