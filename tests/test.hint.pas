unit test.hint;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Hint;

type
  THintTest = class(TTestCase)
  published
    procedure ContentRectAddsPaddingAllSides;
    procedure ContentRectZeroPadding;
  end;

implementation

procedure THintTest.ContentRectAddsPaddingAllSides;
var
  R: TRect;
begin
  // text 40x12, padding L=3 T=2 R=5 B=4  ->  48 x 18
  R := TyHintContentRect(40, 12, 3, 2, 5, 4);
  AssertEquals('left', 0, R.Left);
  AssertEquals('top', 0, R.Top);
  AssertEquals('width', 40 + 3 + 5, R.Right);
  AssertEquals('height', 12 + 2 + 4, R.Bottom);
end;

procedure THintTest.ContentRectZeroPadding;
var
  R: TRect;
begin
  R := TyHintContentRect(30, 10, 0, 0, 0, 0);
  AssertEquals('width', 30, R.Right);
  AssertEquals('height', 10, R.Bottom);
end;

initialization
  RegisterTest(THintTest);
end.
