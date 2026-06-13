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
    procedure CheckThemeNewTypeKeys(const AName: string);
    procedure CheckThemeTabControlTypeKeys(const AName: string);
    procedure CheckThemeFormTypeKey(const AName: string);
  published
    procedure TestLightLoadsAndResolvesButton;
    procedure TestDarkLoadsAndResolvesButton;
    procedure TestShowcaseLoadsAndResolvesButton;
    { v1.1 typeKey assertions — one method per theme }
    procedure TestLightStylesNewTypeKeys;
    procedure TestDarkStylesNewTypeKeys;
    procedure TestShowcaseStylesNewTypeKeys;
    { v1.2 typeKey assertions — TabControl }
    procedure TestLightStylesTabControlTypeKeys;
    procedure TestDarkStylesTabControlTypeKeys;
    procedure TestShowcaseStylesTabControlTypeKeys;
    { v1.5.1 typeKey assertions — TyForm window background }
    procedure TestLightStylesFormTypeKey;
    procedure TestDarkStylesFormTypeKey;
    procedure TestShowcaseStylesFormTypeKey;
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

{ v1.1: assert all 8 new typeKeys are styled correctly in the given theme }
procedure TTestThemes.CheckThemeNewTypeKeys(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyListBox base: must have Background }
    s := model.ResolveStyle('TyListBox', '', []);
    AssertTrue('TyListBox base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyListItem:active: must have Background (accent selection highlight) }
    s := model.ResolveStyle('TyListItem', '', [tysActive]);
    AssertTrue('TyListItem:active must set Background: ' + AName,
      tpBackground in s.Present);

    { TyProgressFill base: must have Background (the fill colour) }
    s := model.ResolveStyle('TyProgressFill', '', []);
    AssertTrue('TyProgressFill base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyToggleSwitch:active: must have Background (ON-state track colour) }
    s := model.ResolveStyle('TyToggleSwitch', '', [tysActive]);
    AssertTrue('TyToggleSwitch:active must set Background: ' + AName,
      tpBackground in s.Present);

    { TyTrackThumb base: must have Background (thumb fill) }
    s := model.ResolveStyle('TyTrackThumb', '', []);
    AssertTrue('TyTrackThumb base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyGroupBox base: must have BorderColor (the group border line) }
    s := model.ResolveStyle('TyGroupBox', '', []);
    AssertTrue('TyGroupBox base must set BorderColor: ' + AName,
      tpBorderColor in s.Present);

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

procedure TTestThemes.TestLightStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('light.tycss');
end;

procedure TTestThemes.TestDarkStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('showcase.tycss');
end;

{ v1.2: assert TyTabControl base and TyTab:active are styled in the given theme }
procedure TTestThemes.CheckThemeTabControlTypeKeys(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyTabControl base: must have Background (content area surface) }
    s := model.ResolveStyle('TyTabControl', '', []);
    AssertTrue('TyTabControl base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyTab:active: must have Background (selected tab highlight) }
    s := model.ResolveStyle('TyTab', '', [tysActive]);
    AssertTrue('TyTab:active must set Background: ' + AName,
      tpBackground in s.Present);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('light.tycss');
end;

procedure TTestThemes.TestDarkStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('showcase.tycss');
end;

{ v1.5.1: assert TyForm defines a solid window background in the given theme }
procedure TTestThemes.CheckThemeFormTypeKey(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyForm base: must have Background (the window/form backdrop) }
    s := model.ResolveStyle('TyForm', '', []);
    AssertTrue('TyForm base must set Background: ' + AName,
      tpBackground in s.Present);
    AssertTrue('TyForm background must be solid: ' + AName,
      s.Background.Kind = tfkSolid);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('light.tycss');
end;

procedure TTestThemes.TestDarkStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('showcase.tycss');
end;

initialization
  RegisterTest(TTestThemes);
end.
