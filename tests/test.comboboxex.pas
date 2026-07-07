unit test.comboboxex;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ComboBox, tyControls.ComboBoxEx;
type
  TComboBoxExTest = class(TTestCase)
  published
    procedure TestAddItem;
    procedure TestImageIndexOutOfRange;
    procedure TestImageIndexSurvivesSort;
  end;
implementation

procedure TComboBoxExTest.TestAddItem;
var c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    c.AddItem('a', 5);
    c.AddItem('b', -1);
    AssertEquals('two items', 2, c.Items.Count);
    AssertEquals('a keeps image 5', 5, c.ImageIndexOf(0));
    AssertEquals('b has no image', -1, c.ImageIndexOf(1));
    AssertEquals('name a kept', 'a', c.Items[0]);
    AssertEquals('name b kept', 'b', c.Items[1]);
  finally c.Free; end;
end;

procedure TComboBoxExTest.TestImageIndexOutOfRange;
var c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    c.AddItem('a', 0);
    AssertEquals('index 0 image 0', 0, c.ImageIndexOf(0));
    AssertEquals('negative index -> -1', -1, c.ImageIndexOf(-1));
    AssertEquals('past end -> -1', -1, c.ImageIndexOf(99));
  finally c.Free; end;
end;

procedure TComboBoxExTest.TestImageIndexSurvivesSort;
var c: TTyComboBoxEx; idx: Integer;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    c.AddItem('Zebra', 2);
    c.AddItem('Apple', 7);
    c.AddItem('Mango', 4);
    c.Sorted := True;   // reorders the NAMES; image indices (in Objects[]) must follow
    idx := c.Items.IndexOf('Apple');
    AssertTrue('Apple present', idx >= 0);
    AssertEquals('Apple keeps image 7 after sort', 7, c.ImageIndexOf(idx));
    idx := c.Items.IndexOf('Zebra');
    AssertEquals('Zebra keeps image 2 after sort', 2, c.ImageIndexOf(idx));
    idx := c.Items.IndexOf('Mango');
    AssertEquals('Mango keeps image 4 after sort', 4, c.ImageIndexOf(idx));
  finally c.Free; end;
end;

initialization
  RegisterTest(TComboBoxExTest);
end.
