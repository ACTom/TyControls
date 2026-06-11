unit test.controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller;
type
  TControllerTest = class(TTestCase)
  published
    procedure TestLoadThemeCssResolves;
    procedure TestDefaultControllerIsSingleton;
  end;
implementation
procedure TControllerTest.TestLoadThemeCssResolves;
var
  c: TTyStyleController;
  s: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss('TyButton { color: #FF0000; border-width: 3px; }');
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertTrue('TextColor present', tpTextColor in s.Present);
    AssertEquals('TextColor value', Integer(TyRGB($FF, $00, $00)), Integer(s.TextColor));
    AssertEquals('BorderWidth value', 3, s.BorderWidth);
  finally
    c.Free;
  end;
end;
procedure TControllerTest.TestDefaultControllerIsSingleton;
begin
  AssertSame('same instance', TyDefaultController, TyDefaultController);
  AssertTrue('not nil', TyDefaultController <> nil);
end;
initialization
  RegisterTest(TControllerTest);
end.
