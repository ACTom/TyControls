unit test.splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, fpcunit, testregistry, tyControls.Splitter;
type
  TSplitterGeomTest = class(TTestCase)
  published
    procedure TestNewSizeGrowShrink;
    procedure TestNewSizeClamps;
  end;
implementation

procedure TSplitterGeomTest.TestNewSizeGrowShrink;
begin
  // alLeft/alTop: sibling precedes the splitter -> +delta grows it
  AssertEquals('alLeft +20', 120, TySplitterNewSize(alLeft, 100, 20, 30, 1000));
  AssertEquals('alTop  +20', 120, TySplitterNewSize(alTop,  100, 20, 30, 1000));
  // alRight/alBottom: sibling follows the splitter -> +delta shrinks it
  AssertEquals('alRight +20', 80, TySplitterNewSize(alRight,  100, 20, 30, 1000));
  AssertEquals('alBottom +20', 80, TySplitterNewSize(alBottom, 100, 20, 30, 1000));
end;

procedure TSplitterGeomTest.TestNewSizeClamps;
begin
  AssertEquals('floor at MinSize', 30, TySplitterNewSize(alLeft, 100, -500, 30, 1000));
  AssertEquals('ceil at MaxSize',  200, TySplitterNewSize(alLeft, 100, 500, 30, 200));
  // MaxSize < MinSize means "no max" (unknown) -> only the floor applies
  AssertEquals('no max when max<min', 600, TySplitterNewSize(alLeft, 100, 500, 30, -1));
end;

initialization
  RegisterTest(TSplitterGeomTest);
end.
