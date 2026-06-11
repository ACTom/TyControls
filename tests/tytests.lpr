program tytests;

{$mode objfpc}{$H+}

uses
  Interfaces, consoletestrunner, test.Types, test.Css.Tokens, test.Css.Lexer, test.Css.Parser,
  test.Css.Values, test.StyleModel, test.painter, test.controller, test.base,
  test.base.drawframe, test.button, test.tylabel, test.edit, test.checkbox,
  test.radiobutton, test.controls.panel;

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
