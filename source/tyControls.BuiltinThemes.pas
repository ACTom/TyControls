unit tyControls.BuiltinThemes;
{$mode objfpc}{$H+}
{ PLACEHOLDER — real implementation lands in Task 3. }
interface
uses Classes, SysUtils;
function TyBuiltinThemeNames: TStringArray;
function TyBuiltinThemeCss(const AName: string): string;
procedure TyRegisterBuiltinThemes;
implementation
function TyBuiltinThemeNames: TStringArray;
begin
  Result := nil;
end;
function TyBuiltinThemeCss(const AName: string): string;
begin
  Result := '';
end;
procedure TyRegisterBuiltinThemes;
begin
end;
end.
