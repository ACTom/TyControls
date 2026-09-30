unit test.newproject;

{$mode objfpc}{$H+}

{ The program File -> New -> Project -> TyControls Application writes
  (TTyApplicationDescriptor.InitProject in designtime/tyControls.Design.NewItems.pas).

  The built-in themes are registered by the APPLICATION. The IDE registers them for itself, so a
  ThemeName picked in the Object Inspector shows in the designer; a program that never calls
  TyRegisterBuiltinThemes then opens with the default look. Every project made from this template
  did that until 3.0 -- the README's quick start led straight into it.

  The template cannot run here (the design-time units pull in IDEIntf), so the program is rebuilt
  from the string literals of its source, the way test.designeditors reads the registrations,
  and read as a program: the unit is in its uses clause, and the call comes after
  Application.Initialize and before Application.Run, in front of which the IDE puts every
  Application.CreateForm -- so the first form is created with the themes already there. }

interface

uses
  Classes, SysUtils, StrUtils, fpcunit, testregistry, test.designregistry;

type
  TNewProjectTemplateTest = class(TTestCase)
  private
    function ProgramText: string;
  published
    procedure TestTheProgramUsesTheBuiltinThemesUnit;
    procedure TestTheBuiltinThemesAreRegisteredBeforeTheFormsAreCreated;
  end;

implementation

function TNewProjectTemplateTest.ProgramText: string;
var
  code, expr, lit: string;
  p, q, i: Integer;
begin
  code := DesignSourceCode(True);
  p := Pos('''program Project1;''', code);
  AssertTrue('the template''s program is found in the design-time source', p > 0);
  q := PosEx('SetSourceText', code, p);
  AssertTrue('and where it ends', q > p);
  expr := Copy(code, p, q - p);
  { Every string literal, in order: one line of the program each. }
  Result := '';
  i := 1;
  while i <= Length(expr) do
  begin
    if expr[i] = '''' then
    begin
      lit := '';
      Inc(i);
      while i <= Length(expr) do
      begin
        if expr[i] = '''' then
        begin
          if (i < Length(expr)) and (expr[i + 1] = '''') then
          begin
            lit := lit + '''';
            Inc(i, 2);
            Continue;
          end;
          Break;
        end;
        lit := lit + expr[i];
        Inc(i);
      end;
      Result := Result + lit + LineEnding;
    end;
    Inc(i);
  end;
end;

procedure TNewProjectTemplateTest.TestTheProgramUsesTheBuiltinThemesUnit;
var
  t, usesClause: string;
  a, b: Integer;
begin
  t := ProgramText;
  a := Pos('uses', t);
  b := PosEx(';', t, a);
  AssertTrue('the program has a uses clause:' + LineEnding + t, (a > 0) and (b > a));
  usesClause := Copy(t, a, b - a);
  AssertTrue('the uses clause names tyControls.BuiltinThemes:' + LineEnding + usesClause,
    Pos('tyControls.BuiltinThemes', usesClause) > 0);
end;

procedure TNewProjectTemplateTest.TestTheBuiltinThemesAreRegisteredBeforeTheFormsAreCreated;
var
  t: string;
  pInit, pReg, pRun: Integer;
begin
  t := ProgramText;
  pInit := Pos('Application.Initialize;', t);
  pReg := Pos('TyRegisterBuiltinThemes;', t);
  pRun := Pos('Application.Run;', t);
  AssertTrue('precondition: Application.Initialize and Application.Run are there:' + LineEnding + t,
    (pInit > 0) and (pRun > pInit));
  AssertTrue('the program calls TyRegisterBuiltinThemes:' + LineEnding + t, pReg > 0);
  AssertTrue('after Application.Initialize and before Application.Run, where the IDE puts ' +
    'the forms:' + LineEnding + t, (pReg > pInit) and (pReg < pRun));
end;

initialization
  RegisterTest(TNewProjectTemplateTest);

end.
