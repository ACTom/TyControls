unit test.form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.Form;

type
  TFormHelpersTest = class(TTestCase)
  published
    procedure TestCenterIsNone;
    procedure TestLeftEdge;
    procedure TestRightEdge;
    procedure TestTopEdge;
    procedure TestBottomEdge;
    procedure TestTopLeftCorner;
    procedure TestTopRightCorner;
    procedure TestBottomLeftCorner;
    procedure TestBottomRightCorner;
    procedure TestZeroZoneIsNone;
    procedure TestMaximizedBoundsEqualsWorkArea;
  end;

implementation

const
  CR: TRect = (Left: 0; Top: 0; Right: 200; Bottom: 100);
  ZONE = 6;

procedure TFormHelpersTest.TestCenterIsNone;
begin
  AssertTrue('center', TyHitTestBorder(CR, Point(100, 50), ZONE) = bhNone);
end;

procedure TFormHelpersTest.TestLeftEdge;
begin
  AssertTrue('left', TyHitTestBorder(CR, Point(2, 50), ZONE) = bhLeft);
end;

procedure TFormHelpersTest.TestRightEdge;
begin
  AssertTrue('right', TyHitTestBorder(CR, Point(198, 50), ZONE) = bhRight);
end;

procedure TFormHelpersTest.TestTopEdge;
begin
  AssertTrue('top', TyHitTestBorder(CR, Point(100, 2), ZONE) = bhTop);
end;

procedure TFormHelpersTest.TestBottomEdge;
begin
  AssertTrue('bottom', TyHitTestBorder(CR, Point(100, 98), ZONE) = bhBottom);
end;

procedure TFormHelpersTest.TestTopLeftCorner;
begin
  AssertTrue('topleft', TyHitTestBorder(CR, Point(2, 2), ZONE) = bhTopLeft);
end;

procedure TFormHelpersTest.TestTopRightCorner;
begin
  AssertTrue('topright', TyHitTestBorder(CR, Point(198, 2), ZONE) = bhTopRight);
end;

procedure TFormHelpersTest.TestBottomLeftCorner;
begin
  AssertTrue('bottomleft', TyHitTestBorder(CR, Point(2, 98), ZONE) = bhBottomLeft);
end;

procedure TFormHelpersTest.TestBottomRightCorner;
begin
  AssertTrue('bottomright', TyHitTestBorder(CR, Point(198, 98), ZONE) = bhBottomRight);
end;

procedure TFormHelpersTest.TestZeroZoneIsNone;
begin
  AssertTrue('zerozone', TyHitTestBorder(CR, Point(0, 0), 0) = bhNone);
end;

procedure TFormHelpersTest.TestMaximizedBoundsEqualsWorkArea;
var
  Wa, R: TRect;
begin
  Wa := Rect(0, 0, 1920, 1040);
  R := TyMaximizedBounds(Wa);
  AssertEquals('left', 0, R.Left);
  AssertEquals('top', 0, R.Top);
  AssertEquals('right', 1920, R.Right);
  AssertEquals('bottom', 1040, R.Bottom);
end;

initialization
  RegisterTest(TFormHelpersTest);

end.
