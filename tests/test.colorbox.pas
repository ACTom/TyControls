unit test.colorbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.ComboBox, tyControls.ColorBox;
type
  TColorBoxTest = class(TTestCase)
  published
    procedure TestTColorConversion;
    procedure TestPaletteAndColorAt;
    procedure TestSelected;
    procedure TestAddAndClear;
    procedure TestSortedKeepsColors;
    procedure TestComboModeStaysLocked;
    procedure TestFormFileKeepsAnExtendedSelection;
  end;
implementation

procedure TColorBoxTest.TestTColorConversion;
begin
  AssertEquals('red',   'FFFF0000', IntToHex(TyTColorToTy(clRed), 8));
  AssertEquals('lime',  'FF00FF00', IntToHex(TyTColorToTy(clLime), 8));
  AssertEquals('blue',  'FF0000FF', IntToHex(TyTColorToTy(clBlue), 8));
  AssertEquals('black', 'FF000000', IntToHex(TyTColorToTy(clBlack), 8));
  AssertEquals('white', 'FFFFFFFF', IntToHex(TyTColorToTy(clWhite), 8));
end;

procedure TColorBoxTest.TestPaletteAndColorAt;
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    AssertEquals('16-colour palette', 16, c.Items.Count);
    AssertTrue('item 0 is black', c.ColorAt(0) = clBlack);
    AssertTrue('item 9 is red', c.ColorAt(9) = clRed);
    AssertTrue('out of range -> clNone', c.ColorAt(99) = clNone);
    AssertEquals('default selection', 0, c.ItemIndex);
  finally c.Free; end;
end;

procedure TColorBoxTest.TestSelected;
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    AssertTrue('initial selected black', c.Selected = clBlack);
    c.Selected := clRed;
    AssertEquals('picks red index', 9, c.ItemIndex);
    AssertTrue('selected red', c.Selected = clRed);
    // A colour not in the palette reports "not one of mine" and leaves the list alone.
    c.Selected := TColor($00123456);
    AssertEquals('palette untouched', 16, c.Items.Count);
    AssertEquals('nothing selected', -1, c.ItemIndex);
  finally c.Free; end;
end;

procedure TColorBoxTest.TestAddAndClear;
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    c.ClearColors;
    AssertEquals('cleared', 0, c.Items.Count);
    c.AddColor('Sky', clSkyBlue);
    AssertEquals('one item', 1, c.Items.Count);
    AssertTrue('color kept', c.ColorAt(0) = clSkyBlue);
    AssertEquals('name kept', 'Sky', c.Items[0]);
  finally c.Free; end;
end;

procedure TColorBoxTest.TestSortedKeepsColors;
var c: TTyColorBox; idx: Integer;
begin
  c := TTyColorBox.Create(nil);
  try
    c.Sorted := True;   // reorders the NAMES; colours (in Objects[]) must follow
    idx := c.Items.IndexOf('Red');
    AssertTrue('Red present', idx >= 0);
    AssertTrue('Red -> clRed after sort', c.ColorAt(idx) = clRed);
    idx := c.Items.IndexOf('White');
    AssertTrue('White present', idx >= 0);
    AssertTrue('White -> clWhite after sort', c.ColorAt(idx) = clWhite);
    idx := c.Items.IndexOf('Black');
    AssertTrue('Black -> clBlack after sort', c.ColorAt(idx) = clBlack);
  finally c.Free; end;
end;

{ Was TestStyleLocked, and its name asserted what Style MEANT on this class: the combo's
  dropdown mode, which the control silently discarded on every write. Style now composes the
  palette (as it does on LCL's TColorBox), so the combo mode is reached through the ancestor
  -- and is still locked, for the same reason as before: a filtered editable popup would map
  row indices to the wrong swatches. }
procedure TColorBoxTest.TestComboModeStaysLocked;
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    { The combo mode, reached through the combo ancestor: on a colour box `Style` is the
      palette. TTyCustomComboBox, not TTyComboBox -- a colour box is not a TTyComboBox. }
    AssertTrue('starts list-only', TTyCustomComboBox(c).Style = csDropDownList);
    TTyCustomComboBox(c).Style := csDropDown;   // must still be ignored
    AssertTrue('stays list-only', TTyCustomComboBox(c).Style = csDropDownList);
  finally c.Free; end;
end;

{ Selected is read from a form file before the Style that composes the palette holding it --
  TTyColorBox publishes Style first, but the palette is only rebuilt in Loaded. The colour has
  to survive until then: it used to be looked up in the default 16, missed, and come back as
  nothing selected. }
procedure TColorBoxTest.TestFormFileKeepsAnExtendedSelection;
var
  src, dst: TForm;
  c: TTyColorBox;
  ms: TMemoryStream;
begin
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    c := TTyColorBox.Create(src);
    c.Name := 'CB';
    c.Parent := src;
    c.Style := [cbStandardColors, cbExtendedColors, cbPrettyNames];
    c.Selected := clMoneyGreen;
    AssertTrue('setup: the extended palette holds clMoneyGreen', c.Selected = clMoneyGreen);
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    c := dst.FindComponent('CB') as TTyColorBox;
    AssertTrue('the palette came back', cbExtendedColors in c.Style);
    AssertEquals('and so did the selected colour', clMoneyGreen, c.Selected);
  finally
    ms.Free;
    src.Free;
    dst.Free;
  end;
end;

initialization
  RegisterTest(TColorBoxTest);
end.
