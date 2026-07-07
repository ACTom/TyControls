unit test.fontlistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.FontListBox;
type
  TFontListBoxTest = class(TTestCase)
  published
    procedure TestSelectedFontRoundTrip;
    procedure TestRefreshDoesNotCrash;
  end;
implementation

procedure TFontListBoxTest.TestSelectedFontRoundTrip;
var c: TTyFontListBox;
begin
  c := TTyFontListBox.Create(nil);
  try
    c.Items.Clear;
    c.Items.Add('Arial');
    c.Items.Add('Courier New');
    c.SelectedFont := 'Courier New';
    AssertEquals('selected', 'Courier New', c.SelectedFont);
    AssertEquals('index', 1, c.ItemIndex);
    c.SelectedFont := 'Nonexistent Font';   // not present -> unchanged
    AssertEquals('unchanged', 'Courier New', c.SelectedFont);
  finally c.Free; end;
end;

procedure TFontListBoxTest.TestRefreshDoesNotCrash;
var c: TTyFontListBox;
begin
  c := TTyFontListBox.Create(nil);
  try
    c.RefreshFonts;
    AssertTrue('items count is sane', c.Items.Count >= 0);
  finally c.Free; end;
end;

initialization
  RegisterTest(TFontListBoxTest);
end.
