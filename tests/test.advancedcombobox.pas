unit test.advancedcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ComboBox, tyControls.AdvancedComboBox;
type
  TAdvancedComboBoxTest = class(TTestCase)
  published
    procedure TestAddItem;
    procedure TestSubtitleEmpty;
    procedure TestImageIndexOutOfRange;
    procedure TestPartsSurviveSort;
    procedure TestStyleLockedToDropDownList;
  end;
implementation

procedure TAdvancedComboBoxTest.TestAddItem;
var c: TTyAdvancedComboBox;
begin
  c := TTyAdvancedComboBox.Create(nil);
  try
    c.AddItem('Alice', 'Engineer', 3);
    c.AddItem('Bob', 'Designer', -1);
    AssertEquals('two items', 2, c.Items.Count);
    AssertEquals('title 0', 'Alice', c.TitleOf(0));
    AssertEquals('subtitle 0', 'Engineer', c.SubtitleOf(0));
    AssertEquals('image 0', 3, c.ImageIndexOf(0));
    AssertEquals('title 1', 'Bob', c.TitleOf(1));
    AssertEquals('subtitle 1', 'Designer', c.SubtitleOf(1));
    AssertEquals('image 1 -> none', -1, c.ImageIndexOf(1));
  finally c.Free; end;
end;

procedure TAdvancedComboBoxTest.TestSubtitleEmpty;
var c: TTyAdvancedComboBox;
begin
  c := TTyAdvancedComboBox.Create(nil);
  try
    c.AddItem('Solo', '', 0);
    AssertEquals('title kept', 'Solo', c.TitleOf(0));
    AssertEquals('empty subtitle', '', c.SubtitleOf(0));
    AssertEquals('image 0', 0, c.ImageIndexOf(0));
  finally c.Free; end;
end;

procedure TAdvancedComboBoxTest.TestImageIndexOutOfRange;
var c: TTyAdvancedComboBox;
begin
  c := TTyAdvancedComboBox.Create(nil);
  try
    c.AddItem('a', 'x', 2);
    AssertEquals('negative index -> -1', -1, c.ImageIndexOf(-1));
    AssertEquals('past end -> -1', -1, c.ImageIndexOf(99));
    AssertEquals('past-end title -> empty', '', c.TitleOf(99));
    AssertEquals('past-end subtitle -> empty', '', c.SubtitleOf(99));
  finally c.Free; end;
end;

procedure TAdvancedComboBoxTest.TestPartsSurviveSort;
var c: TTyAdvancedComboBox; idx: Integer;
begin
  c := TTyAdvancedComboBox.Create(nil);
  try
    c.AddItem('Zebra', 'stripes', 2);
    c.AddItem('Apple', 'fruit', 7);
    c.AddItem('Mango', 'sweet', 4);
    c.Sorted := True;   // reorders by joined string (title first); Objects[] must follow
    idx := c.Items.IndexOf('Apple' + LineEnding + 'fruit');
    AssertTrue('Apple present', idx >= 0);
    AssertEquals('Apple keeps title after sort', 'Apple', c.TitleOf(idx));
    AssertEquals('Apple keeps subtitle after sort', 'fruit', c.SubtitleOf(idx));
    AssertEquals('Apple keeps image 7 after sort', 7, c.ImageIndexOf(idx));
    idx := c.Items.IndexOf('Zebra' + LineEnding + 'stripes');
    AssertEquals('Zebra keeps image 2 after sort', 2, c.ImageIndexOf(idx));
    idx := c.Items.IndexOf('Mango' + LineEnding + 'sweet');
    AssertEquals('Mango keeps image 4 after sort', 4, c.ImageIndexOf(idx));
  finally c.Free; end;
end;

procedure TAdvancedComboBoxTest.TestStyleLockedToDropDownList;
var c: TTyAdvancedComboBox;
begin
  // Rich two-line items are pick-only: setting csDropDown must be ignored, else the
  // single-line editor / Text would leak the joined 'Title'+LineEnding+'Subtitle' string.
  c := TTyAdvancedComboBox.Create(nil);
  try
    AssertTrue('default is pick-only', c.Style = csDropDownList);
    c.Style := csDropDown;   // hostile: must be refused
    AssertTrue('stays csDropDownList', c.Style = csDropDownList);
  finally c.Free; end;
end;

initialization
  RegisterTest(TAdvancedComboBoxTest);
end.
