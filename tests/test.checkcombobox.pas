unit test.checkcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ComboBox, tyControls.CheckComboBox;
type
  TCheckComboBoxTest = class(TTestCase)
  private
    function MakeABC: TTyCheckComboBox;
  published
    procedure TestCheckedRoundTrip;
    procedure TestCheckedTextJoinsCheckedItems;
    procedure TestEmptyTextWhenNoneChecked;
    procedure TestSeparatorApplied;
    procedure TestOutOfRangeSafe;
    procedure TestCheckStateSurvivesSort;
    procedure TestStyleLockedToDropDownList;
  end;
implementation

function TCheckComboBoxTest.MakeABC: TTyCheckComboBox;
begin
  Result := TTyCheckComboBox.Create(nil);
  Result.Items.Add('Apple');
  Result.Items.Add('Banana');
  Result.Items.Add('Cherry');
end;

procedure TCheckComboBoxTest.TestCheckedRoundTrip;
var c: TTyCheckComboBox;
begin
  c := MakeABC;
  try
    c.Checked[0] := True;
    c.Checked[2] := True;
    AssertTrue('0 checked', c.Checked[0]);
    AssertFalse('1 unchecked', c.Checked[1]);
    AssertTrue('2 checked', c.Checked[2]);
    AssertEquals('count', 2, c.CheckedCount);
    c.Checked[0] := False;
    AssertFalse('0 now unchecked', c.Checked[0]);
    AssertEquals('count after uncheck', 1, c.CheckedCount);
  finally c.Free; end;
end;

procedure TCheckComboBoxTest.TestCheckedTextJoinsCheckedItems;
var c: TTyCheckComboBox;
begin
  c := MakeABC;
  try
    c.Checked[0] := True;
    c.Checked[2] := True;   // Apple + Cherry, in item order
    AssertEquals('joined summary', 'Apple, Cherry', c.CheckedText);
  finally c.Free; end;
end;

procedure TCheckComboBoxTest.TestEmptyTextWhenNoneChecked;
var c: TTyCheckComboBox;
begin
  c := MakeABC;
  try
    AssertEquals('empty default', '', c.CheckedText);
    c.EmptyText := '(未选)';
    AssertEquals('empty text shown', '(未选)', c.CheckedText);
    c.Checked[1] := True;
    AssertEquals('summary once checked', 'Banana', c.CheckedText);
  finally c.Free; end;
end;

procedure TCheckComboBoxTest.TestSeparatorApplied;
var c: TTyCheckComboBox;
begin
  c := MakeABC;
  try
    c.Separator := ' | ';
    c.Checked[0] := True;
    c.Checked[1] := True;
    AssertEquals('custom separator', 'Apple | Banana', c.CheckedText);
  finally c.Free; end;
end;

procedure TCheckComboBoxTest.TestOutOfRangeSafe;
var c: TTyCheckComboBox;
begin
  c := MakeABC;
  try
    c.Checked[-1] := True;   // no crash, ignored
    c.Checked[99] := True;   // no crash, ignored
    AssertFalse('negative reads false', c.Checked[-1]);
    AssertFalse('past-end reads false', c.Checked[99]);
    AssertEquals('nothing checked', 0, c.CheckedCount);
  finally c.Free; end;
end;

procedure TCheckComboBoxTest.TestCheckStateSurvivesSort;
var c: TTyCheckComboBox;
begin
  // Check state lives in Items.Objects[] so it follows the string through a sort.
  c := TTyCheckComboBox.Create(nil);
  try
    c.Items.Add('Zebra');
    c.Items.Add('Apple');
    c.Checked[0] := True;   // Zebra checked
    c.Sorted := True;       // Apple now first, Zebra last
    AssertTrue('Zebra still checked after sort', c.Checked[c.Items.IndexOf('Zebra')]);
    AssertFalse('Apple still unchecked', c.Checked[c.Items.IndexOf('Apple')]);
  finally c.Free; end;
end;

procedure TCheckComboBoxTest.TestStyleLockedToDropDownList;
var c: TTyCheckComboBox;
begin
  c := MakeABC;
  try
    AssertTrue('default pick-only', c.Style = csDropDownList);
    c.Style := csDropDown;   // must be refused
    AssertTrue('stays csDropDownList', c.Style = csDropDownList);
  finally c.Free; end;
end;

initialization
  RegisterTest(TCheckComboBoxTest);
end.
