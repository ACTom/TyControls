unit test.officelistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.OfficeListBox;
type
  TOfficeListBoxTest = class(TTestCase)
  published
    procedure TestAddHeaderAndItem;
    procedure TestIsHeader;
    procedure TestOutOfRange;
    procedure TestHeaderFlagSurvivesSort;
    procedure TestHeaderNotSelectableViaIndex;
  end;
implementation

procedure TOfficeListBoxTest.TestAddHeaderAndItem;
var c: TTyOfficeListBox;
begin
  c := TTyOfficeListBox.Create(nil);
  try
    c.AddHeader('Fruit');
    c.AddItem('Apple');
    c.AddItem('Mango');
    AssertEquals('three rows', 3, c.Items.Count);
    AssertEquals('header text', 'Fruit', c.Items[0]);
    AssertEquals('item text', 'Apple', c.Items[1]);
  finally c.Free; end;
end;

procedure TOfficeListBoxTest.TestIsHeader;
var c: TTyOfficeListBox;
begin
  c := TTyOfficeListBox.Create(nil);
  try
    c.AddHeader('Fruit');
    c.AddItem('Apple');
    AssertTrue('row 0 is header', c.IsHeader(0));
    AssertFalse('row 1 is not header', c.IsHeader(1));
  finally c.Free; end;
end;

procedure TOfficeListBoxTest.TestOutOfRange;
var c: TTyOfficeListBox;
begin
  c := TTyOfficeListBox.Create(nil);
  try
    c.AddItem('Apple');
    AssertFalse('negative index', c.IsHeader(-1));
    AssertFalse('past end', c.IsHeader(99));
  finally c.Free; end;
end;

procedure TOfficeListBoxTest.TestHeaderFlagSurvivesSort;
var c: TTyOfficeListBox;
begin
  c := TTyOfficeListBox.Create(nil);
  try
    // The header flag lives in Objects[] so it follows the string through a sort.
    c.AddHeader('Zebra');           // header, sorts last
    c.AddItem('Apple');
    c.AddItem('Mango');
    c.Sorted := True;               // reorders the names; flags in Objects[] follow
    AssertTrue('Zebra still a header after sort', c.IsHeader(c.Items.IndexOf('Zebra')));
    AssertFalse('Apple still an item', c.IsHeader(c.Items.IndexOf('Apple')));
  finally c.Free; end;
end;

procedure TOfficeListBoxTest.TestHeaderNotSelectableViaIndex;
var c: TTyOfficeListBox;
begin
  // Regression: headers must be non-selectable on the programmatic path too (not only clicks).
  // Selection funnels through the overridden SelectItem, which redirects a header to the nearest
  // real item in the direction of travel.
  c := TTyOfficeListBox.Create(nil);
  try
    c.AddHeader('Fruit');   // 0
    c.AddItem('Apple');     // 1
    c.AddItem('Mango');     // 2
    c.AddHeader('Veg');     // 3
    c.AddItem('Carrot');    // 4
    c.ItemIndex := 0;       // header -> redirect forward to first item
    AssertEquals('header 0 redirected to item 1', 1, c.ItemIndex);
    c.ItemIndex := 3;       // header below the current -> redirect forward to item 4
    AssertEquals('header 3 redirected to item 4', 4, c.ItemIndex);
    c.ItemIndex := 2;       // a real item selects normally
    AssertEquals('real item selects', 2, c.ItemIndex);
  finally c.Free; end;
end;

initialization
  RegisterTest(TOfficeListBoxTest);
end.
