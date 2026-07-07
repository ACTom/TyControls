unit test.mrucombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ComboBox, tyControls.MRUComboBox;
type
  TMRUComboBoxTest = class(TTestCase)
  published
    procedure TestEditableByDefault;
    procedure TestOrderAndCap;
    procedure TestDedupeBubbles;
    procedure TestEmptyIgnored;
    procedure TestLoweringMaxItemsTrims;
    procedure TestMaxItemsClampedToOne;
    procedure TestSortedNeverCrashesKeepsMRUOrder;
  end;
implementation

procedure TMRUComboBoxTest.TestEditableByDefault;
var c: TTyMRUComboBox;
begin
  c := TTyMRUComboBox.Create(nil);
  try
    AssertTrue('constructed editable (csDropDown)', c.Style = csDropDown);
    AssertEquals('default MaxItems', 10, c.MaxItems);
  finally c.Free; end;
end;

procedure TMRUComboBoxTest.TestOrderAndCap;
var c: TTyMRUComboBox;
begin
  c := TTyMRUComboBox.Create(nil);
  try
    c.MaxItems := 3;
    c.AddToHistory('a');
    c.AddToHistory('b');
    c.AddToHistory('c');
    c.AddToHistory('d');
    AssertEquals('capped at MaxItems', 3, c.Items.Count);
    AssertEquals('newest on top', 'd', c.Items[0]);
    AssertEquals('second newest', 'c', c.Items[1]);
    AssertEquals('third newest', 'b', c.Items[2]);   // 'a' fell off the tail
    AssertEquals('newest selected', 0, c.ItemIndex);
  finally c.Free; end;
end;

procedure TMRUComboBoxTest.TestDedupeBubbles;
var c: TTyMRUComboBox;
begin
  c := TTyMRUComboBox.Create(nil);
  try
    c.MaxItems := 3;
    c.AddToHistory('a');
    c.AddToHistory('b');
    c.AddToHistory('c');
    c.AddToHistory('d');   // list is now d, c, b
    c.AddToHistory('b');   // existing -> bubbles to top, no duplicate
    AssertEquals('bubbled to top', 'b', c.Items[0]);
    AssertEquals('no duplicate / same count', 3, c.Items.Count);
    AssertEquals('bubbled item selected', 0, c.ItemIndex);
  finally c.Free; end;
end;

procedure TMRUComboBoxTest.TestEmptyIgnored;
var c: TTyMRUComboBox;
begin
  c := TTyMRUComboBox.Create(nil);
  try
    c.AddToHistory('x');
    c.AddToHistory('');       // ignored
    c.AddToHistory('   ');    // whitespace-only -> ignored
    AssertEquals('only the real entry remembered', 1, c.Items.Count);
    AssertEquals('trimmed dedupe still works', 'x', c.Items[0]);
  finally c.Free; end;
end;

procedure TMRUComboBoxTest.TestLoweringMaxItemsTrims;
var c: TTyMRUComboBox;
begin
  c := TTyMRUComboBox.Create(nil);
  try
    c.AddToHistory('a');
    c.AddToHistory('b');
    c.AddToHistory('c');
    c.AddToHistory('d');   // list is d, c, b, a
    AssertEquals('four remembered', 4, c.Items.Count);
    c.MaxItems := 2;       // lowering trims the tail
    AssertEquals('trimmed to new cap', 2, c.Items.Count);
    AssertEquals('newest kept', 'd', c.Items[0]);
    AssertEquals('second kept', 'c', c.Items[1]);
  finally c.Free; end;
end;

procedure TMRUComboBoxTest.TestMaxItemsClampedToOne;
var c: TTyMRUComboBox;
begin
  c := TTyMRUComboBox.Create(nil);
  try
    c.MaxItems := 0;          // clamped up to 1
    AssertEquals('clamped to 1', 1, c.MaxItems);
    c.AddToHistory('a');
    c.AddToHistory('b');
    AssertEquals('only one remembered', 1, c.Items.Count);
    AssertEquals('newest wins', 'b', c.Items[0]);
  finally c.Free; end;
end;

procedure TMRUComboBoxTest.TestSortedNeverCrashesKeepsMRUOrder;
var c: TTyMRUComboBox;
begin
  // Regression: a designer-set Sorted:=True must NOT make AddToHistory's Insert(0,…) raise
  // SSortedListError, and MRU order (recency) must win over alphabetical.
  c := TTyMRUComboBox.Create(nil);
  try
    c.Sorted := True;          // hostile setting
    c.AddToHistory('mango');   // would crash on a sorted TStringList before the fix
    c.AddToHistory('apple');
    c.AddToHistory('cherry');
    AssertEquals('newest on top (recency, not alphabetical)', 'cherry', c.Items[0]);
    AssertEquals('then apple', 'apple', c.Items[1]);
    AssertEquals('then mango', 'mango', c.Items[2]);
  finally c.Free; end;
end;

initialization
  RegisterTest(TMRUComboBoxTest);
end.
