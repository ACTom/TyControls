unit test.colorcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, fpcunit, testregistry, tyControls.ColorComboBox;
type
  TColorComboBoxTest = class(TTestCase)
  published
    procedure TestMoreItem;
    procedure TestMoreCaptionRebuild;
  end;
implementation

procedure TColorComboBoxTest.TestMoreItem;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    // 16 palette colours + one trailing "more…" sentinel (clNone).
    AssertEquals('16 + more', 17, c.Items.Count);
    AssertTrue('real colour 0 intact', c.ColorAt(0) = clBlack);
    AssertTrue('last is the clNone sentinel', c.ColorAt(c.Items.Count - 1) = clNone);
    AssertEquals('more caption', 'More…', c.Items[c.Items.Count - 1]);
  finally c.Free; end;
end;

procedure TColorComboBoxTest.TestMoreCaptionRebuild;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    c.MoreCaption := 'Custom…';
    AssertEquals('still 17 (old more dropped)', 17, c.Items.Count);
    AssertEquals('rebuilt caption last', 'Custom…', c.Items[c.Items.Count - 1]);
    AssertTrue('still clNone sentinel', c.ColorAt(c.Items.Count - 1) = clNone);
  finally c.Free; end;
end;

initialization
  RegisterTest(TColorComboBoxTest);
end.
