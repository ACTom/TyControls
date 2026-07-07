unit test.advancedlistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.ListBox, tyControls.AdvancedListBox;
type
  TAdvancedListBoxTest = class(TTestCase)
  published
    procedure TestAddItem;
    procedure TestSubtitleEmpty;
    procedure TestImageIndexOutOfRange;
    procedure TestPartsSurviveSort;
  end;
implementation

procedure TAdvancedListBoxTest.TestAddItem;
var lb: TTyAdvancedListBox;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('Alice', 'Engineer', 3);
    lb.AddItem('Bob', 'Designer', -1);
    AssertEquals('two items', 2, lb.Items.Count);
    AssertEquals('title 0', 'Alice', lb.TitleOf(0));
    AssertEquals('subtitle 0', 'Engineer', lb.SubtitleOf(0));
    AssertEquals('image 0', 3, lb.ImageIndexOf(0));
    AssertEquals('title 1', 'Bob', lb.TitleOf(1));
    AssertEquals('subtitle 1', 'Designer', lb.SubtitleOf(1));
    AssertEquals('image 1 -> none', -1, lb.ImageIndexOf(1));
  finally lb.Free; end;
end;

procedure TAdvancedListBoxTest.TestSubtitleEmpty;
var lb: TTyAdvancedListBox;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('Solo', '', 0);
    AssertEquals('title kept', 'Solo', lb.TitleOf(0));
    AssertEquals('empty subtitle', '', lb.SubtitleOf(0));
    AssertEquals('image 0', 0, lb.ImageIndexOf(0));
  finally lb.Free; end;
end;

procedure TAdvancedListBoxTest.TestImageIndexOutOfRange;
var lb: TTyAdvancedListBox;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('a', 'x', 2);
    AssertEquals('negative index -> -1', -1, lb.ImageIndexOf(-1));
    AssertEquals('past end -> -1', -1, lb.ImageIndexOf(99));
    AssertEquals('past-end title -> empty', '', lb.TitleOf(99));
    AssertEquals('past-end subtitle -> empty', '', lb.SubtitleOf(99));
  finally lb.Free; end;
end;

procedure TAdvancedListBoxTest.TestPartsSurviveSort;
var lb: TTyAdvancedListBox; idx: Integer;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('Zebra', 'stripes', 2);
    lb.AddItem('Apple', 'fruit', 7);
    lb.AddItem('Mango', 'sweet', 4);
    lb.Sorted := True;   // reorders by joined string (title first); Objects[] must follow
    idx := lb.Items.IndexOf('Apple' + LineEnding + 'fruit');
    AssertTrue('Apple present', idx >= 0);
    AssertEquals('Apple keeps title after sort', 'Apple', lb.TitleOf(idx));
    AssertEquals('Apple keeps subtitle after sort', 'fruit', lb.SubtitleOf(idx));
    AssertEquals('Apple keeps image 7 after sort', 7, lb.ImageIndexOf(idx));
    idx := lb.Items.IndexOf('Zebra' + LineEnding + 'stripes');
    AssertEquals('Zebra keeps image 2 after sort', 2, lb.ImageIndexOf(idx));
    idx := lb.Items.IndexOf('Mango' + LineEnding + 'sweet');
    AssertEquals('Mango keeps image 4 after sort', 4, lb.ImageIndexOf(idx));
  finally lb.Free; end;
end;

initialization
  RegisterTest(TAdvancedListBoxTest);
end.
