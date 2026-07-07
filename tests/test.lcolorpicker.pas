unit test.lcolorpicker;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.ColorMath, tyControls.LColorPicker;
type
  TLColorPickerTest = class(TTestCase)
  published
    procedure TestDefaults;
    procedure TestPositionClampLow;
    procedure TestPositionClampHigh;
    procedure TestPositionMid;
    procedure TestHueSatSetGet;
    procedure TestSelectedColorWhite;
    procedure TestHueChangesSelectedColor;
    procedure TestOnChangeFires;
  private
    FChanges: Integer;
    procedure HandleChange(Sender: TObject);
  end;
implementation

procedure TLColorPickerTest.HandleChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TLColorPickerTest.TestDefaults;
var p: TTyLColorPicker;
begin
  p := TTyLColorPicker.Create(nil);
  try
    AssertEquals('default Hue', 0.0, p.Hue, 1e-6);
    AssertEquals('default Sat', 1.0, p.Sat, 1e-6);
    AssertEquals('default Position', 1.0, p.Position, 1e-6);
  finally p.Free; end;
end;

procedure TLColorPickerTest.TestPositionClampLow;
var p: TTyLColorPicker;
begin
  p := TTyLColorPicker.Create(nil);
  try
    p.Position := -0.5;
    AssertEquals('below range clamps to 0', 0.0, p.Position, 1e-6);
  finally p.Free; end;
end;

procedure TLColorPickerTest.TestPositionClampHigh;
var p: TTyLColorPicker;
begin
  p := TTyLColorPicker.Create(nil);
  try
    p.Position := 1.5;
    AssertEquals('above range clamps to 1', 1.0, p.Position, 1e-6);
  finally p.Free; end;
end;

procedure TLColorPickerTest.TestPositionMid;
var p: TTyLColorPicker;
begin
  p := TTyLColorPicker.Create(nil);
  try
    p.Position := 0.25;
    AssertEquals('in-range value kept', 0.25, p.Position, 1e-6);
  finally p.Free; end;
end;

procedure TLColorPickerTest.TestHueSatSetGet;
var p: TTyLColorPicker;
begin
  p := TTyLColorPicker.Create(nil);
  try
    p.Hue := 210;
    p.Sat := 0.4;
    AssertEquals('Hue set/get', 210.0, p.Hue, 1e-6);
    AssertEquals('Sat set/get', 0.4, p.Sat, 1e-6);
  finally p.Free; end;
end;

procedure TLColorPickerTest.TestSelectedColorWhite;
var p: TTyLColorPicker;
begin
  // Hue irrelevant when Sat=0 and V=1 -> pure white; assert equality to the direct call.
  p := TTyLColorPicker.Create(nil);
  try
    p.Hue := 0;
    p.Sat := 0;
    p.Position := 1;
    AssertTrue('SelectedColor = TyHSVToRGB(0,0,1,255)',
      p.SelectedColor = TyHSVToRGB(0, 0, 1, 255));
    AssertTrue('and that colour is white', p.SelectedColor = TyRGBA(255, 255, 255, 255));
  finally p.Free; end;
end;

procedure TLColorPickerTest.TestHueChangesSelectedColor;
var p: TTyLColorPicker; before: TTyColor;
begin
  // At full Sat + full V, changing the Hue must change the picked colour.
  p := TTyLColorPicker.Create(nil);
  try
    p.Sat := 1;
    p.Position := 1;
    p.Hue := 0;                 // red
    before := p.SelectedColor;
    p.Hue := 120;               // green
    AssertFalse('changing Hue changes SelectedColor', p.SelectedColor = before);
  finally p.Free; end;
end;

procedure TLColorPickerTest.TestOnChangeFires;
var p: TTyLColorPicker;
begin
  p := TTyLColorPicker.Create(nil);
  try
    FChanges := 0;
    p.OnChange := @HandleChange;
    p.Position := 0.5;
    AssertEquals('OnChange fired once on real change', 1, FChanges);
    p.Position := 0.5;          // same value -> no event
    AssertEquals('no event on same-value set', 1, FChanges);
  finally p.Free; end;
end;

initialization
  RegisterTest(TLColorPickerTest);
end.
