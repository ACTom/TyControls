unit test.fontsizecombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.FontSizeComboBox;
type
  TFontSizeComboBoxTest = class(TTestCase)
  published
    procedure TestPresetsAndDefault;
    procedure TestSetGetSize;
  end;
implementation

procedure TFontSizeComboBoxTest.TestPresetsAndDefault;
var c: TTyFontSizeComboBox;
begin
  c := TTyFontSizeComboBox.Create(nil);
  try
    AssertTrue('has preset sizes', c.Items.Count >= 10);
    AssertEquals('default size', 12, c.FontSize);
  finally c.Free; end;
end;

procedure TFontSizeComboBoxTest.TestSetGetSize;
var c: TTyFontSizeComboBox;
begin
  c := TTyFontSizeComboBox.Create(nil);
  try
    c.FontSize := 24;   // a preset
    AssertEquals('preset 24', 24, c.FontSize);
    c.FontSize := 13;   // custom (not a preset) -> editable text
    AssertEquals('custom 13', 13, c.FontSize);
  finally c.Free; end;
end;

initialization
  RegisterTest(TFontSizeComboBoxTest);
end.
