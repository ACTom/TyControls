unit tyControls.BuiltinThemes;
{$mode objfpc}{$H+}
{ 12 套内置主题(编译进二进制):default(双模中性基底)+ 10 套 curated 双模设计师调色板
  + system(OS 强调色)。curated 主题 = 双模基底 + @mode light/dark 各覆盖 5 个颜色种子,
  其余令牌 resolve 时按新种子派生(on()/darken/lighten)。明暗由 Controller.Mode/Follow 控制。
  调色板取自各开源项目官方色值(One/Dracula+Alucard/Nord/Solarized/Gruvbox/GitHub/Catppuccin/
  Tokyo Night/Monokai Pro/Material),仅借用色值并致谢。 }
interface
uses
  Classes, SysUtils, tyControls.ThemeRegistry, tyControls.BuiltinThemeData;

function TyBuiltinThemeNames: TStringArray;             // 12 个名字(default..material, system)
function TyBuiltinThemeCss(const AName: string): string;
procedure TyRegisterBuiltinThemes;                      // 全部注册为 CSS 源(显式调用)

implementation

type
  TSeed = record Accent, Surface, OnSurface, Border, Danger: string; end;
  TDef  = record Name: string; L, D: TSeed; end;

const
  cDefault = 'default';
  cSystem  = 'system';

  Curated: array[0..9] of TDef = (
    (Name:'one';        L:(Accent:'#4078F2';Surface:'#FAFAFA';OnSurface:'#383A42';Border:'#D4D4D4';Danger:'#E45649');
                        D:(Accent:'#61AFEF';Surface:'#282C34';OnSurface:'#ABB2BF';Border:'#3E4451';Danger:'#E06C75')),
    (Name:'dracula';    L:(Accent:'#644AC9';Surface:'#FFFBEB';OnSurface:'#1F1F1F';Border:'#CFCFDE';Danger:'#CB3A2A');
                        D:(Accent:'#BD93F9';Surface:'#282A36';OnSurface:'#F8F8F2';Border:'#44475A';Danger:'#FF5555')),
    (Name:'nord';       L:(Accent:'#5E81AC';Surface:'#ECEFF4';OnSurface:'#2E3440';Border:'#D8DEE9';Danger:'#BF616A');
                        D:(Accent:'#88C0D0';Surface:'#2E3440';OnSurface:'#ECEFF4';Border:'#4C566A';Danger:'#BF616A')),
    (Name:'solarized';  L:(Accent:'#268BD2';Surface:'#FDF6E3';OnSurface:'#657B83';Border:'#EEE8D5';Danger:'#DC322F');
                        D:(Accent:'#268BD2';Surface:'#002B36';OnSurface:'#839496';Border:'#073642';Danger:'#DC322F')),
    (Name:'gruvbox';    L:(Accent:'#D65D0E';Surface:'#FBF1C7';OnSurface:'#3C3836';Border:'#D5C4A1';Danger:'#CC241D');
                        D:(Accent:'#FE8019';Surface:'#282828';OnSurface:'#EBDBB2';Border:'#504945';Danger:'#FB4934')),
    (Name:'github';     L:(Accent:'#0969DA';Surface:'#FFFFFF';OnSurface:'#1F2328';Border:'#D1D9E0';Danger:'#D1242F');
                        D:(Accent:'#4493F8';Surface:'#0D1117';OnSurface:'#F0F6FC';Border:'#3D444D';Danger:'#F85149')),
    (Name:'catppuccin'; L:(Accent:'#1E66F5';Surface:'#EFF1F5';OnSurface:'#4C4F69';Border:'#CCD0DA';Danger:'#D20F39');
                        D:(Accent:'#89B4FA';Surface:'#1E1E2E';OnSurface:'#CDD6F4';Border:'#313244';Danger:'#F38BA8')),
    (Name:'tokyonight'; L:(Accent:'#2959AA';Surface:'#E6E7ED';OnSurface:'#343B59';Border:'#C1C2C7';Danger:'#BD4040');
                        D:(Accent:'#7AA2F7';Surface:'#1A1B26';OnSurface:'#A9B1D6';Border:'#3B4261';Danger:'#DB4B4B')),
    (Name:'monokai';    L:(Accent:'#1C8CA8';Surface:'#FAF4F2';OnSurface:'#29242A';Border:'#D3CDCC';Danger:'#E14775');
                        D:(Accent:'#78DCE8';Surface:'#2D2A2E';OnSurface:'#FCFCFA';Border:'#403E41';Danger:'#FF6188')),
    (Name:'material';   L:(Accent:'#2196F3';Surface:'#FAFAFA';OnSurface:'#212121';Border:'#E0E0E0';Danger:'#F44336');
                        D:(Accent:'#2196F3';Surface:'#121212';OnSurface:'#FFFFFF';Border:'#2C2C2C';Danger:'#CF6679'))
  );

function SeedBlock(const AMode: string; const S: TSeed): string;
begin
  Result := '@mode ' + AMode + ' { :root { '
    + '--accent: '     + S.Accent    + '; '
    + '--surface: '    + S.Surface   + '; '
    + '--on-surface: ' + S.OnSurface + '; '
    + '--border: '     + S.Border    + '; '
    + '--danger: '     + S.Danger    + '; } }';
end;

function TyBuiltinThemeNames: TStringArray;
var i: Integer;
begin
  SetLength(Result, Length(Curated) + 2);   // default + curated + system
  Result[0] := cDefault;
  for i := 0 to High(Curated) do Result[i + 1] := Curated[i].Name;
  Result[High(Result)] := cSystem;
end;

function TyBuiltinThemeCss(const AName: string): string;
var i: Integer;
begin
  Result := '';
  if SameText(AName, cSystem)  then Exit(TyBuiltinSystemCss);
  if SameText(AName, cDefault) then Exit(TyBuiltinDualBaseCss);
  for i := 0 to High(Curated) do
    if SameText(Curated[i].Name, AName) then
      Exit(TyBuiltinDualBaseCss + LineEnding
        + SeedBlock('light', Curated[i].L) + LineEnding
        + SeedBlock('dark',  Curated[i].D));
end;

procedure TyRegisterBuiltinThemes;
var n: TStringArray; i: Integer;
begin
  n := TyBuiltinThemeNames;
  for i := 0 to High(n) do
    TyRegisterThemeCss(n[i], TyBuiltinThemeCss(n[i]));
end;

end.
