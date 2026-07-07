unit test.fontcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.FontComboBox;
type
  TFontComboBoxTest = class(TTestCase)
  published
    procedure TestSelectedFontRoundTrip;
    procedure TestRefreshDoesNotCrash;
  end;
implementation

procedure TFontComboBoxTest.TestSelectedFontRoundTrip;
var c: TTyFontComboBox;
begin
  c := TTyFontComboBox.Create(nil);
  try
    // Replace the Screen.Fonts population with a deterministic set.
    c.Items.Clear;
    c.Items.Add('Arial');
    c.Items.Add('Courier New');
    c.Items.Add('Times New Roman');
    c.SelectedFont := 'Courier New';
    AssertEquals('selected', 'Courier New', c.SelectedFont);
    AssertEquals('index', 1, c.ItemIndex);
    c.SelectedFont := 'Nonexistent Font';   // not present -> selection unchanged
    AssertEquals('unchanged', 'Courier New', c.SelectedFont);
  finally c.Free; end;
end;

procedure TFontComboBoxTest.TestRefreshDoesNotCrash;
var c: TTyFontComboBox;
begin
  // Construction reads Screen.Fonts; RefreshFonts re-reads. Neither may crash headless.
  c := TTyFontComboBox.Create(nil);
  try
    c.RefreshFonts;
    AssertTrue('items count is sane', c.Items.Count >= 0);
  finally c.Free; end;
end;

initialization
  RegisterTest(TFontComboBoxTest);
end.
