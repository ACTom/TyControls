unit test.valueformat;
{$mode objfpc}{$H+}

{ #138: ValueFormat on the instruments. They formatted the value as a float, so a format with
  an integer specifier -- '%d%%' is how a percentage is usually written -- raised in Paint, on
  every repaint, and the control never drew. }

interface

uses
  Classes, SysUtils, TypInfo, Controls, Graphics, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Gauge, tyControls.Meter, tyControls.LevelMeter,
  tyControls.CircularProgress, tyControls.Dial, tyControls.GearDial, test.dpi.support;

type
  TValueFormatTest = class(TTestCase)
  published
    procedure TestAnIntegerSpecifierGetsTheValueRounded;
    procedure TestAFloatSpecifierGetsTheValue;
    procedure TestAFormatWithNoNumberDoesNotRaise;
    procedure TestEveryInstrumentPaintsAnIntegerFormat;
  end;

implementation

procedure TValueFormatTest.TestAnIntegerSpecifierGetsTheValueRounded;
begin
  AssertEquals('%d', '42%', TyFormatValue('%d%%', 42.4));
  AssertEquals('%d rounds', '43', TyFormatValue('%d', 42.6));
  AssertEquals('%x', 'FF', TyFormatValue('%x', 255));
  AssertEquals('with a width', '  7', TyFormatValue('%3d', 7));
  AssertEquals('after a literal percent', '100% of 5', TyFormatValue('100%% of %d', 5));
end;

procedure TValueFormatTest.TestAFloatSpecifierGetsTheValue;
begin
  AssertEquals('%.1f', '2.5', TyFormatValue('%.1f', 2.5));
  AssertEquals('%.0f%%', '50%', TyFormatValue('%.0f%%', 50));
end;

procedure TValueFormatTest.TestAFormatWithNoNumberDoesNotRaise;
begin
  AssertEquals('no specifier: the text as it is', 'Level', TyFormatValue('Level', 3));
  AssertEquals('a string specifier: the value as text', FloatToStr(3), TyFormatValue('%s', 3));
end;

procedure TValueFormatTest.TestEveryInstrumentPaintsAnIntegerFormat;
const
  Classes_: array[0..5] of TControlClass = (TTyGauge, TTyMeter, TTyLevelMeter,
    TTyCircularProgress, TTyDial, TTyGearDial);
var
  form: TForm;
  c: TControl;
  bmp: TBitmap;
  log: TStringList;
  i: Integer;
begin
  form := TForm.CreateNew(nil);
  bmp := TBitmap.Create;
  log := TStringList.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(200, 200);
    for i := Low(Classes_) to High(Classes_) do
    begin
      c := Classes_[i].Create(form);
      c.Name := Copy(Classes_[i].ClassName, 2, MaxInt);
      c.Parent := form;
      c.SetBounds(0, 0, 200, 200);
      SetOrdProp(c, 'ShowValue', Ord(True));
      SetStrProp(c, 'ValueFormat', '%d%%');
      TyTestPaintTree(c, bmp, log);
    end;
    AssertEquals('every instrument paints with ''%d%%'': ' + log.Text, 0, log.Count);
  finally
    log.Free;
    bmp.Free;
    form.Free;
  end;
end;

initialization
  RegisterTest(TValueFormatTest);
end.
