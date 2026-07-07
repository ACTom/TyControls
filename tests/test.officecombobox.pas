unit test.officecombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.OfficeComboBox;
type
  TOfficeComboBoxTest = class(TTestCase)
  published
    procedure TestAddHeaderAndItem;
    procedure TestIsHeader;
    procedure TestOutOfRange;
    procedure TestHeaderNotSelectable;
  end;
implementation

procedure TOfficeComboBoxTest.TestAddHeaderAndItem;
var c: TTyOfficeComboBox;
begin
  c := TTyOfficeComboBox.Create(nil);
  try
    c.AddHeader('Fruit');
    c.AddItem('Apple');
    c.AddItem('Mango');
    AssertEquals('three rows', 3, c.Items.Count);
    AssertEquals('header text', 'Fruit', c.Items[0]);
    AssertEquals('item text', 'Apple', c.Items[1]);
  finally c.Free; end;
end;

procedure TOfficeComboBoxTest.TestIsHeader;
var c: TTyOfficeComboBox;
begin
  c := TTyOfficeComboBox.Create(nil);
  try
    c.AddHeader('Fruit');
    c.AddItem('Apple');
    AssertTrue('row 0 is header', c.IsHeader(0));
    AssertFalse('row 1 is not header', c.IsHeader(1));
  finally c.Free; end;
end;

procedure TOfficeComboBoxTest.TestOutOfRange;
var c: TTyOfficeComboBox;
begin
  c := TTyOfficeComboBox.Create(nil);
  try
    c.AddItem('Apple');
    AssertFalse('negative index', c.IsHeader(-1));
    AssertFalse('past end', c.IsHeader(99));
  finally c.Free; end;
end;

procedure TOfficeComboBoxTest.TestHeaderNotSelectable;
var c: TTyOfficeComboBox;
begin
  // Selection (keyboard, ItemIndex setter, popup click) funnels through the overridden
  // SelectItem, which redirects a header target to the nearest real item; a real item selects
  // normally. (Replaces the old too-late DoSelect reset-to-(-1).)
  c := TTyOfficeComboBox.Create(nil);
  try
    c.AddHeader('Fruit');   // 0
    c.AddItem('Apple');     // 1
    c.AddItem('Mango');     // 2
    c.AddHeader('Veg');     // 3
    c.AddItem('Carrot');    // 4
    c.ItemIndex := 1;
    AssertEquals('real item stays selected', 1, c.ItemIndex);
    c.ItemIndex := 0;       // header -> redirect forward to first item
    AssertEquals('header 0 redirected to item 1', 1, c.ItemIndex);
    c.ItemIndex := 3;       // header below current -> redirect forward to item 4
    AssertEquals('header 3 redirected to item 4', 4, c.ItemIndex);
  finally c.Free; end;
end;

initialization
  RegisterTest(TOfficeComboBoxTest);
end.
