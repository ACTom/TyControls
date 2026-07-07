unit test.hscolorpicker;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.ColorMath, tyControls.HSColorPicker;
type
  THSColorPickerTest = class(TTestCase)
  published
    procedure TestDefaults;
    procedure TestHueClampLow;
    procedure TestHueClampHigh;
    procedure TestSatClampLow;
    procedure TestSatClampHigh;
    procedure TestValueClamp;
    procedure TestSelectedColorMatchesHSV;
    procedure TestHueChangesSelectedColor;
    procedure TestOnChangeFiresOnHue;
    procedure TestValueDoesNotFireOnChange;
  private
    FChanges: Integer;
    procedure HandleChange(Sender: TObject);
  end;
implementation

procedure THSColorPickerTest.HandleChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure THSColorPickerTest.TestDefaults;
var p: TTyHSColorPicker;
begin
  p := TTyHSColorPicker.Create(nil);
  try
    AssertEquals('default Hue', 0.0, p.Hue, 1e-6);
    AssertEquals('default Sat', 1.0, p.Sat, 1e-6);
    AssertEquals('default Value', 1.0, p.Value, 1e-6);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestHueClampLow;
var p: TTyHSColorPicker;
begin
  p := TTyHSColorPicker.Create(nil);
  try
    p.Hue := -10;
    AssertEquals('below range clamps to 0', 0.0, p.Hue, 1e-6);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestHueClampHigh;
var p: TTyHSColorPicker;
begin
  p := TTyHSColorPicker.Create(nil);
  try
    p.Hue := 400;
    AssertEquals('above range clamps to 360', 360.0, p.Hue, 1e-6);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestSatClampLow;
var p: TTyHSColorPicker;
begin
  p := TTyHSColorPicker.Create(nil);
  try
    p.Sat := -0.5;
    AssertEquals('below range clamps to 0', 0.0, p.Sat, 1e-6);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestSatClampHigh;
var p: TTyHSColorPicker;
begin
  p := TTyHSColorPicker.Create(nil);
  try
    p.Sat := 1.5;
    AssertEquals('above range clamps to 1', 1.0, p.Sat, 1e-6);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestValueClamp;
var p: TTyHSColorPicker;
begin
  p := TTyHSColorPicker.Create(nil);
  try
    p.Value := 2.0;
    AssertEquals('Value above range clamps to 1', 1.0, p.Value, 1e-6);
    p.Value := -1.0;
    AssertEquals('Value below range clamps to 0', 0.0, p.Value, 1e-6);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestSelectedColorMatchesHSV;
var p: TTyHSColorPicker;
begin
  // SelectedColor must equal the direct HSV->RGB call at the current H/S/V.
  p := TTyHSColorPicker.Create(nil);
  try
    p.Hue := 210;
    p.Sat := 0.6;
    p.Value := 0.8;
    AssertTrue('SelectedColor = TyHSVToRGB(210,0.6,0.8,255)',
      p.SelectedColor = TyHSVToRGB(210, 0.6, 0.8, 255));
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestHueChangesSelectedColor;
var p: TTyHSColorPicker; before: TTyColor;
begin
  // At full Sat + full Value, changing the Hue must change the picked colour.
  p := TTyHSColorPicker.Create(nil);
  try
    p.Sat := 1;
    p.Value := 1;
    p.Hue := 0;                 // red
    before := p.SelectedColor;
    p.Hue := 120;               // green
    AssertFalse('changing Hue changes SelectedColor', p.SelectedColor = before);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestOnChangeFiresOnHue;
var p: TTyHSColorPicker;
begin
  p := TTyHSColorPicker.Create(nil);
  try
    FChanges := 0;
    p.OnChange := @HandleChange;
    p.Hue := 90;
    AssertEquals('OnChange fired once on real Hue change', 1, FChanges);
    p.Hue := 90;                // same value -> no event
    AssertEquals('no event on same-value set', 1, FChanges);
  finally p.Free; end;
end;

procedure THSColorPickerTest.TestValueDoesNotFireOnChange;
var p: TTyHSColorPicker;
begin
  // Value is the fixed brightness; changing it repaints but must NOT fire OnChange.
  p := TTyHSColorPicker.Create(nil);
  try
    FChanges := 0;
    p.OnChange := @HandleChange;
    p.Value := 0.5;
    AssertEquals('Value change does not fire OnChange', 0, FChanges);
  finally p.Free; end;
end;

initialization
  RegisterTest(THSColorPickerTest);
end.
