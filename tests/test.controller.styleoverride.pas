unit test.controller.styleoverride;
{$mode objfpc}{$H+}

{ TTyStyleController.StyleOverride -- a tycss patch composed on top of the active theme, the
  "tweak the system theme a little without authoring a whole theme" door. These tests pin the two
  things that make it more than a one-shot additive load: it PERSISTS across theme switches and
  density changes (re-applied whenever layer-1 reloads), and doing so does NOT drop the runtime
  accent (a REPLACE load clears the accent override -- SetDensity used to lose it; the reload path
  now saves and restores it). }

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TControllerStyleOverrideTest = class(TTestCase)
  published
    procedure OverridePatchesTheResolvedStyle;
    procedure OverrideWinsOverAnExplicitlyLoadedTheme;
    procedure OverrideSurvivesADensityChange;
    procedure ClearingTheOverrideRestoresTheBase;
    procedure ClearingTheOverrideRestoresTheBaseOnANamedTheme;
    procedure ClearingItWorksEvenIfTheThemeFileWentAway;
    procedure AccentSurvivesADensityChange;
    procedure AccentSurvivesAnOverrideChange;
    procedure TheDefaultControllerTakesItInCode;
  end;

implementation

uses
  tyControls.Types, tyControls.StyleModel, tyControls.Controller;

{ The resolved border-width of TyButton -- a clean integer to watch an override land on. 7px is a
  distinctive value the base theme does not use. }
function ButtonBorderWidth(AController: TTyStyleController): Integer;
begin
  Result := AController.Model.ResolveStyle('TyButton', '', []).BorderWidth;
end;

procedure TControllerStyleOverrideTest.OverridePatchesTheResolvedStyle;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    AssertTrue('base TyButton is not already 7px (would void the test)', ButtonBorderWidth(c) <> 7);
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('the override patched the resolved style', 7, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.OverrideWinsOverAnExplicitlyLoadedTheme;
var c: TTyStyleController;
begin
  { A REPLACE theme load clears the user layer; the override must re-compose on top and win. }
  c := TTyStyleController.Create(nil);
  try
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    c.LoadThemeCss('TyButton { border-width: 3px; }');   // a "theme" that disagrees
    AssertEquals('the override still wins after a theme load', 7, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.OverrideSurvivesADensityChange;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    c.Density := tdModern;   // reloads layer-1 + density pack; the override must re-apply on top
    AssertEquals('the override survived a density change', 7, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.ClearingTheOverrideRestoresTheBase;
var c: TTyStyleController; base: Integer;
begin
  c := TTyStyleController.Create(nil);
  try
    base := ButtonBorderWidth(c);
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('override applied', 7, ButtonBorderWidth(c));
    c.StyleOverride := '';   // an additive layer cannot be unloaded -> the chain is rebuilt clean
    AssertEquals('clearing the override restored the base', base, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.ClearingItWorksEvenIfTheThemeFileWentAway;
var
  c: TTyStyleController;
  base: Integer;
  path: string;
begin
  { THE OTHER BRANCH THAT COULD LOAD NOTHING. A ThemeFile that has been moved,
    renamed or deleted while the program runs is the file-shaped version of a
    theme name that does not resolve, and it used to fail the same way: nothing
    was loaded, so nothing was cleared, so the override was stuck.

    A deleted theme file is not an exotic state -- it is what an author gets
    the moment they rename the .tycss they are working on. }
  path := GetTempFileName('', 'tycss');
  c := TTyStyleController.Create(nil);
  try
    with TStringList.Create do
    try
      Text := 'TyButton { border-width: 2px; }';
      SaveToFile(path);
    finally
      Free;
    end;
    c.ThemeFile := path;
    base := ButtonBorderWidth(c);
    AssertEquals('the file was loaded to begin with', 2, base);

    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('override applied', 7, ButtonBorderWidth(c));

    DeleteFile(path);
    c.StyleOverride := '';
    { The file is gone, so the base it falls back to is the built-in one rather
      than the 2px the file used to say. What matters is that the 7px patch is
      GONE: a stuck override is unrecoverable, a fallback is not. }
    AssertTrue('the patch did not survive the file going away',
      ButtonBorderWidth(c) <> 7);
  finally
    c.Free;
    DeleteFile(path);
  end;
end;

procedure TControllerStyleOverrideTest.AccentSurvivesADensityChange;
var c: TTyStyleController;
begin
  { The bug this feature exposed: SetDensity -> ReloadThemeLayer -> REPLACE load cleared the
    accent override. The reload now saves/restores it. }
  c := TTyStyleController.Create(nil);
  try
    c.SetAccent('#123456');
    AssertEquals('accent is set', '#123456', c.AccentOverride);
    c.Density := tdModern;
    AssertEquals('accent survived the density change', '#123456', c.AccentOverride);
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.AccentSurvivesAnOverrideChange;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.SetAccent('#123456');
    c.StyleOverride := 'TyButton { border-width: 7px; }';   // rebuilds the chain
    AssertEquals('accent survived setting an override', '#123456', c.AccentOverride);
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.TheDefaultControllerTakesItInCode;
var saved: string;
begin
  { The default controller has no editor popup -- it is set in code. Same effect. }
  saved := TyDefaultController.StyleOverride;
  try
    TyDefaultController.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('default controller applied the override', 7,
      ButtonBorderWidth(TyDefaultController));
  finally
    TyDefaultController.StyleOverride := saved;   { leave the shared singleton as we found it }
  end;
end;

procedure TControllerStyleOverrideTest.ClearingTheOverrideRestoresTheBaseOnANamedTheme;
var c: TTyStyleController; base: Integer;
begin
  { THE SAME THING ON A CONTROLLER THAT NAMES ITS THEME, which is what every
    real one does -- and what ClearingTheOverrideRestoresTheBase above does
    NOT: it leaves ThemeName empty, so ReloadThemeLayer takes the `else` branch
    and clears layer-1 with an explicit LoadFromCss(''). A named theme takes a
    different branch, and if the name does not resolve, that branch loads
    nothing at all and the additive patch survives -- patches then accumulate
    and the override can never be cleared or changed. }
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'default';
    base := ButtonBorderWidth(c);
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('override applied', 7, ButtonBorderWidth(c));
    c.StyleOverride := '';
    AssertEquals('clearing it restored the base', base, ButtonBorderWidth(c));

    { AND A REPLACEMENT REPLACES rather than stacking on the old one, which is
      the other half of the same defect: the patch was never dropped, so a
      second override was appended to the first. }
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    c.StyleOverride := 'TyButton { border-width: 3px; }';
    AssertEquals('the second override replaced the first', 3,
      ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TControllerStyleOverrideTest);

end.
