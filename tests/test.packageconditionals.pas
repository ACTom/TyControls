unit test.packageconditionals;
{$mode objfpc}{$H+}

{ #81: the macOS IME types moved in Lazarus 4.0 (CocoaPrivate -> CocoaFullControlEdit), and a
  uses clause cannot ask which Lazarus it is compiled with -- FPC does not see a constant from an
  earlier unit of the same clause. So tycontrols.lpk asks, in its Conditionals, and passes the
  answer down as a define that tyControls.CocoaWS picks its unit by.

  Nothing in this suite compiles for macOS, so a rename on one side of that hand-off, or an IDE
  that drops the Conditionals when it re-saves the package, would only show on a Mac with
  Lazarus 3.x. This pins the two sides to each other; the macOS cross-build is the real proof. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, test.designregistry;

type
  TPackageConditionalsTest = class(TTestCase)
  published
    procedure TestTheCocoaImeUnitFollowsTheLazarusVersion;
  end;

implementation

function FileText(const ARel: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(RepoRoot + ARel);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

procedure TPackageConditionalsTest.TestTheCocoaImeUnitFollowsTheLazarusVersion;
var lpk, unitText: string;
begin
  lpk := FileText('tycontrols.lpk');
  unitText := FileText('source' + PathDelim + 'tyControls.CocoaWS.pas');
  AssertTrue('the package asks for the Lazarus version (only 4.0+ answers)',
    Pos('GetIDEValue(&apos;LAZ_FULLVERSION&apos;) &gt;= 4000000', lpk) > 0);
  AssertTrue('and defines TY_LCL_BEFORE_4 when it gets no 4.0+ answer',
    Pos('-dTY_LCL_BEFORE_4', lpk) > 0);
  AssertTrue('the unit takes the IME types from CocoaPrivate under that define, else from CocoaFullControlEdit',
    Pos('{$IFDEF TY_LCL_BEFORE_4}CocoaPrivate,{$ELSE}CocoaFullControlEdit,{$ENDIF}', unitText) > 0);
end;

initialization
  RegisterTest(TPackageConditionalsTest);

end.
