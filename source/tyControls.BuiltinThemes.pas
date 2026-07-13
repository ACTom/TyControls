unit tyControls.BuiltinThemes;
{$mode objfpc}{$H+}
{ Compiled-in built-in themes: just 'default' (dual-mode neutral base) + 'system' (OS accent).
  Everything else — the curated palettes (one/dracula/nord/…) and the structural skins
  (classic/xp/aero/…) — now lives as .tycss FILES in themes/, loaded via the theme registry
  (TyRegisterThemeDir). Keeping the pack tiny means adding a theme is just dropping in a file. }
interface
uses
  Classes, SysUtils, tyControls.ThemeRegistry, tyControls.BuiltinThemeData;

function TyBuiltinThemeNames: TStringArray;             // 'default', 'system'
function TyBuiltinThemeCss(const AName: string): string;
procedure TyRegisterBuiltinThemes;                      // register the compiled-in pair as CSS sources

implementation

uses tyControls.BuiltinSkins;   // the compiled-in structural skins (classic/xp/office/…)

const
  cDefault = 'default';
  cSystem  = 'system';

function TyBuiltinThemeNames: TStringArray;
begin
  SetLength(Result, 2);
  Result[0] := cDefault;
  Result[1] := cSystem;
end;

function TyBuiltinThemeCss(const AName: string): string;
begin
  if SameText(AName, cSystem)  then Exit(TyBuiltinSystemCss);
  if SameText(AName, cDefault) then Exit(TyBuiltinDualBaseCss);
  Result := '';
end;

procedure TyRegisterBuiltinThemes;
var n: TStringArray; i: Integer;
begin
  n := TyBuiltinThemeNames;
  for i := 0 to High(n) do
    TyRegisterThemeCss(n[i], TyBuiltinThemeCss(n[i]));
  TyRegisterBuiltinSkins;   // + the structural skins, compiled in from themes/builtin/
end;

end.
