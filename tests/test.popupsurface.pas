unit test.popupsurface;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.PopupSurface;

type
  TPopupSurfaceTest = class(TTestCase)
  published
    procedure PlacesBelowWhenItFits;
    procedure FlipsAboveWhenOffBottom;
    procedure ClampsXIntoScreen;
  end;

implementation

procedure TPopupSurfaceTest.PlacesBelowWhenItFits;
var R: TRect;
begin
  // anchor bottom = 40; 200x100 popup fits within an 800-tall screen -> sits at y=40.
  R := TyPopupPlaceBelow(Rect(100, 20, 150, 40), 200, 100, Rect(0, 0, 1000, 800));
  AssertEquals('left', 100, R.Left);
  AssertEquals('top just below anchor', 40, R.Top);
  AssertEquals('right', 300, R.Right);
  AssertEquals('bottom', 140, R.Bottom);
end;

procedure TPopupSurfaceTest.FlipsAboveWhenOffBottom;
var R: TRect;
begin
  // anchor near the bottom; below would overflow -> flip above (top = anchorTop - height).
  R := TyPopupPlaceBelow(Rect(100, 700, 150, 720), 200, 100, Rect(0, 0, 1000, 768));
  AssertEquals('flipped top', 600, R.Top);
  AssertEquals('flipped bottom == anchor top', 700, R.Bottom);
end;

procedure TPopupSurfaceTest.ClampsXIntoScreen;
var R: TRect;
begin
  // would run off the right edge -> clamp so right == screen right.
  R := TyPopupPlaceBelow(Rect(900, 20, 950, 40), 200, 100, Rect(0, 0, 1000, 800));
  AssertEquals('clamped right', 1000, R.Right);
  AssertEquals('clamped left', 800, R.Left);
  // would run off the left edge -> clamp to 0.
  R := TyPopupPlaceBelow(Rect(-50, 20, 0, 40), 200, 100, Rect(0, 0, 1000, 800));
  AssertEquals('clamped to left 0', 0, R.Left);
end;

initialization
  RegisterTest(TPopupSurfaceTest);
end.
