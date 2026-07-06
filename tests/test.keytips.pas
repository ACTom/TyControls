unit test.keytips;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.KeyTips;

type
  TKeyTipsTest = class(TTestCase)
  published
    procedure FirstLettersWhenFree;
    procedure ConflictFallsBackToPool;
    procedure CjkCaptionsUsePool;
    procedure UniqueAcrossAll;
  end;

implementation

procedure TKeyTipsTest.FirstLettersWhenFree;
var k: TKeyTipArray;
begin
  k := TyAssignKeyTips(['Home', 'Insert', 'View']);
  AssertEquals('H', 'H', k[0]);
  AssertEquals('I', 'I', k[1]);
  AssertEquals('V', 'V', k[2]);
end;

procedure TKeyTipsTest.ConflictFallsBackToPool;
var k: TKeyTipArray;
begin
  // Both start with H; the second takes a free pool key instead.
  k := TyAssignKeyTips(['Home', 'Help']);
  AssertEquals('first H', 'H', k[0]);
  AssertTrue('second not H', k[1] <> 'H');
  AssertTrue('second assigned', k[1] <> '');
end;

procedure TKeyTipsTest.CjkCaptionsUsePool;
var k: TKeyTipArray;
begin
  // No ASCII alnum -> pool keys, in order 1,2,3.
  k := TyAssignKeyTips(['开始', '插入', '视图']);
  AssertEquals('1', '1', k[0]);
  AssertEquals('2', '2', k[1]);
  AssertEquals('3', '3', k[2]);
end;

procedure TKeyTipsTest.UniqueAcrossAll;
var
  k: TKeyTipArray;
  i, j: Integer;
begin
  k := TyAssignKeyTips(['File', 'Formulas', 'Format', '开始', 'Data', 'Data']);
  for i := 0 to High(k) do
  begin
    AssertTrue('assigned ' + IntToStr(i), k[i] <> '');
    for j := i + 1 to High(k) do
      AssertTrue('unique ' + IntToStr(i) + '/' + IntToStr(j), k[i] <> k[j]);
  end;
end;

initialization
  RegisterTest(TKeyTipsTest);
end.
