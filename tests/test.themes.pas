unit test.themes;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel;
type
  TTestThemes = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
    procedure CheckTheme(const AName: string);
  published
    procedure TestLightLoadsAndResolvesButton;
    procedure TestDarkLoadsAndResolvesButton;
    procedure TestShowcaseLoadsAndResolvesButton;
  end;
implementation

function TTestThemes.ThemePath(const AName: string): string;
begin
  // Resolve relative to the test executable (in /tests) so the path does not
  // depend on the current working directory.
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
    + 'themes' + PathDelim + AName;
end;

procedure TTestThemes.CheckTheme(const AName: string);
var
  model: TTyStyleModel;
  base, prim: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));
    base := model.ResolveStyle('TyButton', '', []);
    AssertTrue('TyButton base must set Background: ' + AName,
      tpBackground in base.Present);
    AssertTrue('TyButton base must set TextColor: ' + AName,
      tpTextColor in base.Present);
    prim := model.ResolveStyle('TyButton', 'primary', [tysHover]);
    AssertTrue('TyButton.primary:hover must set Background: ' + AName,
      tpBackground in prim.Present);
  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightLoadsAndResolvesButton;
begin
  CheckTheme('light.tycss');
end;

procedure TTestThemes.TestDarkLoadsAndResolvesButton;
begin
  CheckTheme('dark.tycss');
end;

procedure TTestThemes.TestShowcaseLoadsAndResolvesButton;
begin
  CheckTheme('showcase.tycss');
end;

initialization
  RegisterTest(TTestThemes);
end.
