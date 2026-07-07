unit test.colorlistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, fpcunit, testregistry, tyControls.ColorListBox;
type
  TColorListBoxTest = class(TTestCase)
  published
    procedure TestPaletteAndColorAt;
    procedure TestSelected;
    procedure TestSortedKeepsColors;
    procedure TestAddAndClear;
  end;
implementation

procedure TColorListBoxTest.TestPaletteAndColorAt;
var c: TTyColorListBox;
begin
  c := TTyColorListBox.Create(nil);
  try
    AssertEquals('16-colour palette', 16, c.Items.Count);
    AssertTrue('item 0 is black', c.ColorAt(0) = clBlack);
    AssertTrue('item 9 is red', c.ColorAt(9) = clRed);
    AssertTrue('out of range -> clNone', c.ColorAt(99) = clNone);
    AssertEquals('default selection', 0, c.ItemIndex);
  finally c.Free; end;
end;

procedure TColorListBoxTest.TestSelected;
var c: TTyColorListBox;
begin
  c := TTyColorListBox.Create(nil);
  try
    AssertTrue('initial selected black', c.Selected = clBlack);
    c.Selected := clRed;
    AssertEquals('picks red index', 9, c.ItemIndex);
    AssertTrue('selected red', c.Selected = clRed);
    c.Selected := TColor($00123456);
    AssertEquals('appended custom', 17, c.Items.Count);
    AssertTrue('selected custom', c.Selected = TColor($00123456));
  finally c.Free; end;
end;

procedure TColorListBoxTest.TestSortedKeepsColors;
var c: TTyColorListBox; idx: Integer;
begin
  c := TTyColorListBox.Create(nil);
  try
    c.Sorted := True;   // colours in Objects[] must ride along with the sorted names
    idx := c.Items.IndexOf('Red');
    AssertTrue('Red present', idx >= 0);
    AssertTrue('Red -> clRed after sort', c.ColorAt(idx) = clRed);
    idx := c.Items.IndexOf('White');
    AssertTrue('White -> clWhite after sort', c.ColorAt(idx) = clWhite);
  finally c.Free; end;
end;

procedure TColorListBoxTest.TestAddAndClear;
var c: TTyColorListBox;
begin
  c := TTyColorListBox.Create(nil);
  try
    c.ClearColors;
    AssertEquals('cleared', 0, c.Items.Count);
    c.AddColor('Sky', clSkyBlue);
    AssertTrue('color kept', c.ColorAt(0) = clSkyBlue);
    AssertEquals('name kept', 'Sky', c.Items[0]);
  finally c.Free; end;
end;

initialization
  RegisterTest(TColorListBoxTest);
end.
