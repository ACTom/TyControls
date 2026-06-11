program tytests;

{$mode objfpc}{$H+}

uses
  consoletestrunner, test.Types, test.Css.Tokens;

type
  TTyTestRunner = class(TTestRunner)
  protected
  end;

var
  Application: TTyTestRunner;

begin
  Application := TTyTestRunner.Create(nil);
  Application.Initialize;
  Application.Title := 'TyControls Test Runner';
  Application.Run;
  Application.Free;
end.
