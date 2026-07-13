unit tyControls.BuiltinThemes;
{$mode objfpc}{$H+}
{ Compiled-in built-in themes: the 'default' dual-mode base, the OS-accent 'system' theme, AND
  every structural skin (classic/xp/office/win11/…). All of them ship inside the binary — an app
  needs no themes/ folder to pick any of them by name (Controller.ThemeName := 'office').

  The CSS data lives in the GENERATED tyControls.BuiltinThemeData (built from themes/auto.tycss,
  themes/system.tycss and themes/builtin/*.tycss). Those .tycss files are a REFERENCE copy for
  users to base their own themes on; they are NOT scanned or dynamically loaded at runtime.

  The curated palettes (one/dracula/nord/…) stay as .tycss FILES in themes/palettes/, loaded via
  the theme registry (TyRegisterThemeDir) when an app wants them. }
interface
uses
  Classes, SysUtils, tyControls.ThemeRegistry, tyControls.BuiltinThemeData;

function TyBuiltinThemeNames: TStringArray;             // 'default', 'system', + every structural skin
function TyBuiltinThemeCss(const AName: string): string;
procedure TyRegisterBuiltinThemes;                      // register the whole compiled-in pack as CSS sources

implementation

const
  cDefault = 'default';
  cSystem  = 'system';

function TyBuiltinThemeNames: TStringArray;
var skins: TStringArray; i: Integer;
begin
  skins := TyBuiltinSkinNames;                 // the structural skins (compiled in, sorted)
  SetLength(Result, 2 + Length(skins));
  Result[0] := cDefault;
  Result[1] := cSystem;
  for i := 0 to High(skins) do
    Result[2 + i] := skins[i];
end;

function TyBuiltinThemeCss(const AName: string): string;
begin
  if SameText(AName, cSystem)  then Exit(TyBuiltinSystemCss);
  if SameText(AName, cDefault) then Exit(TyBuiltinDualBaseCss);
  Result := TyBuiltinSkinCss(AName);           // a structural skin, or '' if not a built-in name
end;

procedure TyRegisterBuiltinThemes;
var n: TStringArray; i: Integer;
begin
  n := TyBuiltinThemeNames;
  for i := 0 to High(n) do
    TyRegisterThemeCss(n[i], TyBuiltinThemeCss(n[i]));
end;

end.
