unit test.Css.Values;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Types, tyControls.Css.Values;
type
  TTestCssValuesColors = class(TTestCase)
  published
    procedure TestParse3Digit;
    procedure TestParse6Digit;
    procedure TestParse8Digit;
    procedure TestLighten;
    procedure TestDarken;
    procedure TestAlpha;
    procedure TestMix;
  end;

  TTestCssValuesEval = class(TTestCase)
  private
    FVars: TStringList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEvalDirectColor;
    procedure TestEvalVarColor;
    procedure TestEvalNestedLightenVar;
    procedure TestEvalMixVars;
    procedure TestEvalLengthPx;
    procedure TestEvalLengthVar;
    procedure TestEvalFloat;
  end;
implementation

procedure TTestCssValuesColors.TestParse3Digit;
var c: TTyColor;
begin
  c := TyParseColor('#f00');
  AssertEquals('alpha', 255, TyAlphaOf(c));
  AssertEquals('red', 255, TyRedOf(c));
  AssertEquals('green', 0, TyGreenOf(c));
  AssertEquals('blue', 0, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestParse6Digit;
var c: TTyColor;
begin
  c := TyParseColor('#3B82F6');
  AssertEquals('alpha', 255, TyAlphaOf(c));
  AssertEquals('red', $3B, TyRedOf(c));
  AssertEquals('green', $82, TyGreenOf(c));
  AssertEquals('blue', $F6, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestParse8Digit;
var c: TTyColor;
begin
  c := TyParseColor('#3B82F680');
  AssertEquals('alpha', $80, TyAlphaOf(c));
  AssertEquals('red', $3B, TyRedOf(c));
  AssertEquals('green', $82, TyGreenOf(c));
  AssertEquals('blue', $F6, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestLighten;
var c: TTyColor;
begin
  // base #404040 = 64; lighten 50%: 64 + (255-64)*0.5 = 64 + 95.5 -> round 160 -> 159? see formula
  c := TyLighten(TyRGB($40, $40, $40), 50);
  AssertEquals('red', 160, TyRedOf(c));
  AssertEquals('green', 160, TyGreenOf(c));
  AssertEquals('blue', 160, TyBlueOf(c));
  AssertEquals('alpha preserved', 255, TyAlphaOf(c));
end;

procedure TTestCssValuesColors.TestDarken;
var c: TTyColor;
begin
  // base #808080 = 128; darken 50%: 128*(1-0.5)=64
  c := TyDarken(TyRGB($80, $80, $80), 50);
  AssertEquals('red', 64, TyRedOf(c));
  AssertEquals('green', 64, TyGreenOf(c));
  AssertEquals('blue', 64, TyBlueOf(c));
  AssertEquals('alpha preserved', 255, TyAlphaOf(c));
end;

procedure TTestCssValuesColors.TestAlpha;
var c: TTyColor;
begin
  // A=0.5 -> alpha 128
  c := TyAlpha(TyRGB($10, $20, $30), 0.5);
  AssertEquals('alpha', 128, TyAlphaOf(c));
  AssertEquals('red preserved', $10, TyRedOf(c));
  AssertEquals('green preserved', $20, TyGreenOf(c));
  AssertEquals('blue preserved', $30, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestMix;
var c: TTyColor;
begin
  // mix(#000000, #FFFFFF, 50%) -> 50% of c2 -> 128 each
  c := TyMix(TyRGB(0, 0, 0), TyRGB($FF, $FF, $FF), 50);
  AssertEquals('red', 128, TyRedOf(c));
  AssertEquals('green', 128, TyGreenOf(c));
  AssertEquals('blue', 128, TyBlueOf(c));
end;

procedure TTestCssValuesEval.SetUp;
begin
  FVars := TStringList.Create;
  FVars.Values['accent'] := '#3B82F6';
  FVars.Values['surface'] := '#404040';
  FVars.Values['radius'] := '6px';
end;

procedure TTestCssValuesEval.TearDown;
begin
  FVars.Free;
end;

procedure TTestCssValuesEval.TestEvalDirectColor;
var c: TTyColor;
begin
  c := TyEvalColor('#FF8800', FVars);
  AssertEquals('red', $FF, TyRedOf(c));
  AssertEquals('green', $88, TyGreenOf(c));
  AssertEquals('blue', $00, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalVarColor;
var c: TTyColor;
begin
  c := TyEvalColor('var(--accent)', FVars);
  AssertEquals('red', $3B, TyRedOf(c));
  AssertEquals('green', $82, TyGreenOf(c));
  AssertEquals('blue', $F6, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalNestedLightenVar;
var c: TTyColor;
begin
  // surface=#404040=64; lighten 50% -> 64 + (255-64)*0.5 = 159.5 -> 160
  c := TyEvalColor('lighten(var(--surface), 50%)', FVars);
  AssertEquals('red', 160, TyRedOf(c));
  AssertEquals('green', 160, TyGreenOf(c));
  AssertEquals('blue', 160, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalMixVars;
var c: TTyColor;
begin
  // mix(#404040, #3B82F6, 0%) -> 0% of c2 -> equals c1
  c := TyEvalColor('mix(var(--surface), var(--accent), 0%)', FVars);
  AssertEquals('red', $40, TyRedOf(c));
  AssertEquals('green', $40, TyGreenOf(c));
  AssertEquals('blue', $40, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalLengthPx;
begin
  AssertEquals('length', 12, TyEvalLength('12px', FVars));
end;

procedure TTestCssValuesEval.TestEvalLengthVar;
begin
  AssertEquals('var length', 6, TyEvalLength('var(--radius)', FVars));
end;

procedure TTestCssValuesEval.TestEvalFloat;
begin
  AssertTrue('float 0.5', Abs(TyEvalFloat('0.5', FVars) - 0.5) < 0.0001);
end;

initialization
  RegisterTest(TTestCssValuesColors);
  RegisterTest(TTestCssValuesEval);
end.
