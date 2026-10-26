unit test.comboprops;
{ #120: combo box properties that did nothing, or did it only halfway -- ItemHeight set back
  to 0 hands the rows back to the theme (or to the list's own factory height); Text that
  names an item selects it; a renamed selected row stays selected, a rebuilt list does not;
  the MRU combo's Sorted reads back what its list does; ItemIndex set in code moves a filter
  combo's FilterIndex and Mask; a ComboBoxEx row's Indent stays out of the closed field; and
  Separator / Options repaint. Each as LCL's own combo does. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  tyControls.ListBox, tyControls.ComboBox, tyControls.MRUComboBox,
  tyControls.FilterComboBox, tyControls.ComboBoxEx, tyControls.CheckComboBox,
  tyControls.DateTimePicker;

type
  TComboPropsTest = class(TTestCase)
  published
    procedure TestItemHeightBackToZeroFollowsTheTheme;
    procedure TestItemHeightBackToZeroRestoresTheFactoryHeight;
    procedure TestTextThatNamesAnItemSelectsIt;
    procedure TestARenamedSelectedRowStaysSelected;
    procedure TestARebuiltListDropsTheSelection;
    procedure TestMRUSortedReadsWhatTheListDoes;
    procedure TestFilterItemIndexMovesTheFilter;
    procedure TestComboBoxExFieldTakesNoIndent;
    procedure TestCheckComboSeparatorRepaints;
    procedure TestDateTimePickerOptionsRepaint;
  end;

implementation

type
  { A list factory that pins its own row height, as TTyAdvancedComboBox's does. }
  TPinnedFactoryCombo = class(TTyComboBox)
  protected
    function CreatePopupList: TTyCustomListBox; override;
  end;

  TComboRenderAccess = class(TTyCustomComboBox);

  TCheckComboProbe = class(TTyCheckComboBox)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
  end;

  TPickerProbe = class(TTyDateTimePicker)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
  end;

function TPinnedFactoryCombo.CreatePopupList: TTyCustomListBox;
begin
  Result := inherited CreatePopupList;
  Result.ItemHeight := 40;
end;

procedure TCheckComboProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

procedure TPickerProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

function RenderField(C: TTyCustomComboBox): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(200, 26);
  TComboRenderAccess(C).RenderTo(Result.Canvas, Rect(0, 0, 200, 26), 96);
end;

function SamePixels(A, B: TBitmap): Boolean;
var
  x, y: Integer;
begin
  Result := False;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if ColorToRGB(A.Canvas.Pixels[x, y]) <> ColorToRGB(B.Canvas.Pixels[x, y]) then Exit;
  Result := True;
end;

procedure TComboPropsTest.TestItemHeightBackToZeroFollowsTheTheme;
var
  c: TTyComboBox;
  themed: Integer;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csSimple;   // the docked list exists without a drop-down
    themed := c.PopupList.ItemHeight;
    c.ItemHeight := themed + 17;
    AssertEquals('pinned', themed + 17, c.PopupList.ItemHeight);
    c.ItemHeight := 0;
    AssertEquals('0 gives the rows back to the theme', themed, c.PopupList.ItemHeight);
    AssertFalse('and the list follows it again', c.PopupList.ItemHeightIsExplicit);
  finally
    c.Free;
  end;
end;

procedure TComboPropsTest.TestItemHeightBackToZeroRestoresTheFactoryHeight;
var
  c: TPinnedFactoryCombo;
begin
  c := TPinnedFactoryCombo.Create(nil);
  try
    c.Style := csSimple;
    AssertEquals('the factory''s rows', 40, c.PopupList.ItemHeight);
    c.ItemHeight := 55;
    AssertEquals('pinned', 55, c.PopupList.ItemHeight);
    c.ItemHeight := 0;
    AssertEquals('0 gives them back to the factory, not the theme', 40, c.PopupList.ItemHeight);
  finally
    c.Free;
  end;
end;

procedure TComboPropsTest.TestTextThatNamesAnItemSelectsIt;
var
  c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Items.Add('Apple');
    c.Items.Add('Banana');
    c.Text := 'Banana';
    AssertEquals('the named item is selected', 1, c.ItemIndex);
    c.Text := 'apple';
    AssertEquals('case-insensitively, as LCL''s default match', 0, c.ItemIndex);
    AssertEquals('the text stays as written', 'apple', c.Text);
    c.Text := 'Cherry';
    AssertEquals('text that names none selects nothing', -1, c.ItemIndex);
  finally
    c.Free;
  end;
end;

procedure TComboPropsTest.TestARenamedSelectedRowStaysSelected;
var
  c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDownList;
    c.Items.Add('Apple');
    c.Items.Add('Banana');
    c.ItemIndex := 1;
    c.Items[1] := 'Blueberry';
    AssertEquals('still selected', 1, c.ItemIndex);
    AssertEquals('showing its new text', 'Blueberry', c.Text);
  finally
    c.Free;
  end;
end;

procedure TComboPropsTest.TestARebuiltListDropsTheSelection;
var
  c: TTyComboBox;
  other: TStringList;
begin
  c := TTyComboBox.Create(nil);
  other := TStringList.Create;
  try
    c.Style := csDropDownList;
    c.Items.Add('Apple');
    c.Items.Add('Banana');
    c.ItemIndex := 1;
    other.Add('Cherry');
    other.Add('Damson');   // as many rows, none of them the selected one
    c.Items.Assign(other);
    AssertEquals('a new list is not a rename', -1, c.ItemIndex);
  finally
    other.Free;
    c.Free;
  end;
end;

procedure TComboPropsTest.TestMRUSortedReadsWhatTheListDoes;
var
  c: TTyMRUComboBox;
begin
  c := TTyMRUComboBox.Create(nil);
  try
    c.Sorted := True;
    c.AddToHistory('zebra');
    c.AddToHistory('apple');
    AssertEquals('history is recency', 'apple', c.Items[0]);
    AssertFalse('and Sorted says so', c.Sorted);
  finally
    c.Free;
  end;
end;

procedure TComboPropsTest.TestFilterItemIndexMovesTheFilter;
var
  c: TTyFilterComboBox;
begin
  c := TTyFilterComboBox.Create(nil);
  try
    c.Filter := 'Text (*.txt)|*.txt|All (*.*)|*.*';
    AssertEquals('starts on the first', 1, c.FilterIndex);
    c.ItemIndex := 1;
    AssertEquals('FilterIndex follows', 2, c.FilterIndex);
    AssertEquals('and the mask', '*.*', c.Mask);
  finally
    c.Free;
  end;
end;

procedure TComboPropsTest.TestComboBoxExFieldTakesNoIndent;
var
  flat, indented: TTyComboBoxEx;
  a, b: TBitmap;
begin
  flat := TTyComboBoxEx.Create(nil);
  indented := TTyComboBoxEx.Create(nil);
  a := nil;
  b := nil;
  try
    flat.ItemsEx.AddItem('Indented row', -1, -1, -1, 0, nil);
    indented.ItemsEx.AddItem('Indented row', -1, -1, -1, 30, nil);
    flat.ItemIndex := 0;
    indented.ItemIndex := 0;
    a := RenderField(flat);
    b := RenderField(indented);
    AssertTrue('the closed field shows the row flush, as LCL''s', SamePixels(a, b));
  finally
    a.Free;
    b.Free;
    flat.Free;
    indented.Free;
  end;
end;

procedure TComboPropsTest.TestCheckComboSeparatorRepaints;
var
  c: TCheckComboProbe;
begin
  c := TCheckComboProbe.Create(nil);
  try
    c.Invalidations := 0;
    c.Separator := ' / ';
    AssertTrue('the summary is redrawn', c.Invalidations > 0);
  finally
    c.Free;
  end;
end;

procedure TComboPropsTest.TestDateTimePickerOptionsRepaint;
var
  c: TPickerProbe;
begin
  c := TPickerProbe.Create(nil);
  try
    c.Invalidations := 0;
    c.Options := [dtpoEnabledIfUnchecked];
    AssertTrue('the field is redrawn', c.Invalidations > 0);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TComboPropsTest);
end.
