unit test.StyleModel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Types, tyControls.StyleModel;
type
  TTestStyleMerge = class(TTestCase)
  published
    procedure TestMergeUnionPresent;
    procedure TestMergeOverlaysOnlyPresent;
  end;
implementation

procedure TTestStyleMerge.TestMergeUnionPresent;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  base.Present := [tpTextColor];
  base.TextColor := TyRGB($FF, $FF, $FF);
  over := EmptyStyleSet;
  over.Present := [tpBorderWidth];
  over.BorderWidth := 2;
  TyMergeStyleSet(base, over);
  AssertTrue('textcolor still present', tpTextColor in base.Present);
  AssertTrue('borderwidth now present', tpBorderWidth in base.Present);
  AssertEquals('borderwidth value', 2, base.BorderWidth);
  AssertEquals('textcolor preserved', Integer(TyRGB($FF, $FF, $FF)), Integer(base.TextColor));
end;

procedure TTestStyleMerge.TestMergeOverlaysOnlyPresent;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  base.Present := [tpBorderWidth];
  base.BorderWidth := 1;
  over := EmptyStyleSet;
  over.Present := [];          // nothing present -> base unchanged
  over.BorderWidth := 99;
  TyMergeStyleSet(base, over);
  AssertEquals('borderwidth unchanged', 1, base.BorderWidth);
end;

initialization
  RegisterTest(TTestStyleMerge);
end.
