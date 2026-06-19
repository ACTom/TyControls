# 内置 curated 主题包 + 注册表 CSS 源 + demo 换肤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 TyControls 增加 12 套编译进二进制的内置主题(11 套 curated 双模设计师调色板 + system),并在 demo 提供「主题下拉 + 外观三态 + 随机 + 自定义」换肤 UI。

**Architecture:** 复用 DefaultTheme「CSS 编译成 Pascal 字符串」范式:`auto.tycss` 作双模基底、`system.tycss` 作 OS 主题,由 `gen-builtinthemes.ps1` 生成 `BuiltinThemeData.pas`(sync 测试守门)。每套 curated 主题 = `双模基底 + @mode light/dark 各覆盖 5 个颜色种子`,其余 resolve 时按新种子派生。注册表新增 name→CSS 字符串源;`Controller.ThemeName` 命中内置即从字符串加载(REPLACE)。明/暗/跟随仍是 controller 的 `Mode`/`Follow` 轴。

**Tech Stack:** Free Pascal / Lazarus LCL,fpcunit 测试,`.tycss` + 生成的 Pascal 字符串,PowerShell 生成脚本。

**Spec:** `docs/superpowers/specs/2026-06-19-tycontrols-builtin-theme-pack-design.md`

---

## 约定

- 统一测试命令:`lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`。单类:`./tests/tytests.exe --suite=<ClassName> --format=plain`。Windows 二进制 `tests/tytests.exe`;Git Bash 下 `./tests/tytests` 可直接跑。
- 基线:`main` 全量 **0 失败 / 11 error**(11 个 win32-1407 是本沙箱无法创建 ComboBox/ScrollBar/ListBox 真实窗口控件的既有限制,真机为 0,与本次无关)。每个 task 的验收=**0 失败、且 error ≤ 11(均为这些既有项)**。
- 已在分支 `feat/builtin-theme-pack`(spec 已提交于此)。

---

## 已核定的 curated 调色板(实施依据,取自各项目官方源)

种子顺序 = **accent / surface / on-surface / border / danger**(每模式 5 个颜色;`--radius` 沿用基底 6px;`--on-accent`/`--on-danger` 由 `on()` 自动)。

| 主题 | 浅色 (L) | 深色 (D) |
|---|---|---|
| one | `#4078F2 #FAFAFA #383A42 #D4D4D4 #E45649` | `#61AFEF #282C34 #ABB2BF #3E4451 #E06C75` |
| dracula | `#644AC9 #FFFBEB #1F1F1F #CFCFDE #CB3A2A` | `#BD93F9 #282A36 #F8F8F2 #44475A #FF5555` |
| nord | `#5E81AC #ECEFF4 #2E3440 #D8DEE9 #BF616A` | `#88C0D0 #2E3440 #ECEFF4 #4C566A #BF616A` |
| solarized | `#268BD2 #FDF6E3 #657B83 #EEE8D5 #DC322F` | `#268BD2 #002B36 #839496 #073642 #DC322F` |
| gruvbox | `#D65D0E #FBF1C7 #3C3836 #D5C4A1 #CC241D` | `#FE8019 #282828 #EBDBB2 #504945 #FB4934` |
| github | `#0969DA #FFFFFF #1F2328 #D1D9E0 #D1242F` | `#4493F8 #0D1117 #F0F6FC #3D444D #F85149` |
| catppuccin | `#1E66F5 #EFF1F5 #4C4F69 #CCD0DA #D20F39` | `#89B4FA #1E1E2E #CDD6F4 #313244 #F38BA8` |
| tokyonight | `#2959AA #E6E7ED #343B59 #C1C2C7 #BD4040` | `#7AA2F7 #1A1B26 #A9B1D6 #3B4261 #DB4B4B` |
| monokai | `#1C8CA8 #FAF4F2 #29242A #D3CDCC #E14775` | `#78DCE8 #2D2A2E #FCFCFA #403E41 #FF6188` |
| material | `#2196F3 #FAFAFA #212121 #E0E0E0 #F44336` | `#2196F3 #121212 #FFFFFF #2C2C2C #CF6679` |

`default` = 双模基底原样(无覆盖,= auto 的蓝色中性);`system` = OS 强调色(单独 CSS)。共 12。

---

## Phase A:注册表 CSS 字符串源

### Task 1：`TyRegisterThemeCss` / `TyResolveThemeCss` + 合并到 `TyThemeNames`

**Files:**
- Modify: `source/tyControls.ThemeRegistry.pas`
- Create: `tests/test.builtinthemes.pas`(本任务新建,后续任务续填)
- Modify: `tests/tytests.lpr`(加入新测试单元)

- [ ] **Step 1.1: 新建测试单元骨架** — 创建 `tests/test.builtinthemes.pas`:

```pascal
unit test.builtinthemes;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.ThemeRegistry, tyControls.BuiltinThemes, tyControls.BuiltinThemeData;
type
  TThemeRegistryCssTest = class(TTestCase)
  published
    procedure TestRegisterResolveCss;
    procedure TestNamesMergeFileAndCss;
    procedure TestUnregisterCss;
  end;
implementation

procedure TThemeRegistryCssTest.TestRegisterResolveCss;
var css: string;
begin
  TyUnregisterTheme('__t_css');
  AssertFalse('not registered yet', TyResolveThemeCss('__t_css', css));
  TyRegisterThemeCss('__t_css', 'TyButton { background:#010203; }');
  AssertTrue('resolves after register', TyResolveThemeCss('__T_CSS', css)); // 大小写不敏感
  AssertTrue('css round-trips', Pos('#010203', css) > 0);
  AssertTrue('registered flag', TyThemeRegistered('__t_css'));
  TyUnregisterTheme('__t_css');
end;

procedure TThemeRegistryCssTest.TestNamesMergeFileAndCss;
var names: TStringArray; i: Integer; sawFile, sawCss: Boolean;
begin
  TyRegisterThemeFile('__t_file', 'x.tycss');
  TyRegisterThemeCss('__t_css2', 'TyButton{background:#000000;}');
  names := TyThemeNames;
  sawFile := False; sawCss := False;
  for i := 0 to High(names) do
  begin
    if SameText(names[i], '__t_file') then sawFile := True;
    if SameText(names[i], '__t_css2') then sawCss := True;
  end;
  AssertTrue('file source name listed', sawFile);
  AssertTrue('css source name listed', sawCss);
  TyUnregisterTheme('__t_file'); TyUnregisterTheme('__t_css2');
end;

procedure TThemeRegistryCssTest.TestUnregisterCss;
var css: string;
begin
  TyRegisterThemeCss('__t_css3', 'TyButton{background:#000000;}');
  TyUnregisterTheme('__t_css3');
  AssertFalse('gone after unregister', TyResolveThemeCss('__t_css3', css));
  AssertFalse('not registered', TyThemeRegistered('__t_css3'));
end;

initialization
  RegisterTest(TThemeRegistryCssTest);
end.
```

- [ ] **Step 1.2: 加入测试运行器** — `tests/tytests.lpr` 的 `uses` 末尾(`test.menu;` 之前的列表里)加入 `test.builtinthemes`。例如把 `  test.menu;` 改为 `  test.menu, test.builtinthemes;`。

- [ ] **Step 1.3: 运行,确认编译失败(红)** — 运行测试套件。Expected:编译失败——`TyRegisterThemeCss`/`TyResolveThemeCss`/`tyControls.BuiltinThemes`/`tyControls.BuiltinThemeData` 未定义。(后续任务会建这些单元;本任务先实现注册表 API,BuiltinThemes/Data 单元在 Task 2/3 建——为让本任务可编译,见 Step 1.4 的临时占位说明。)

> **顺序说明**:为避免跨任务的编译死锁,本任务**同时**建立 Task 2/3 的空壳单元,使 `test.builtinthemes` 的 `uses` 可解析:
> - 创建 `source/tyControls.BuiltinThemeData.pas` 占位:`unit tyControls.BuiltinThemeData; {$mode objfpc}{$H+} interface function TyBuiltinDualBaseCss: string; function TyBuiltinSystemCss: string; implementation function TyBuiltinDualBaseCss: string; begin Result := ''; end; function TyBuiltinSystemCss: string; begin Result := ''; end; end.`
> - 创建 `source/tyControls.BuiltinThemes.pas` 占位:`unit tyControls.BuiltinThemes; {$mode objfpc}{$H+} interface uses Classes, SysUtils; function TyBuiltinThemeNames: TStringArray; function TyBuiltinThemeCss(const AName: string): string; procedure TyRegisterBuiltinThemes; implementation function TyBuiltinThemeNames: TStringArray; begin Result := nil; end; function TyBuiltinThemeCss(const AName: string): string; begin Result := ''; end; procedure TyRegisterBuiltinThemes; begin end; end.`(`TStringArray` 经 SysUtils/Types 可见,与真实单元一致)
> 这两个占位在 Task 2/3 被真实实现替换。

- [ ] **Step 1.4: 实现注册表 CSS 源** — `source/tyControls.ThemeRegistry.pas`:

interface 段加声明:

```pascal
{ Register a theme NAME bound to an inline CSS string (a compiled-in built-in theme).
  Case-insensitive; last registration wins. An empty name is ignored. }
procedure TyRegisterThemeCss(const AName, ACss: string);

{ Resolve a registered NAME to its inline CSS. Case-insensitive. False/'' if not a CSS theme. }
function TyResolveThemeCss(const AName: string; out ACss: string): Boolean;
```

implementation 段:加一个 holder 类型与并行存储,并扩展 names/registered/unregister。

```pascal
type
  TTyThemeCssHolder = class
    Css: string;
    constructor Create(const ACss: string);
  end;

constructor TTyThemeCssHolder.Create(const ACss: string);
begin
  inherited Create;
  Css := ACss;
end;

var
  GCssThemes: TStringList = nil;   // Name -> TTyThemeCssHolder; CaseSensitive=False, OwnsObjects

function CssRegistry: TStringList;
begin
  if GCssThemes = nil then
  begin
    GCssThemes := TStringList.Create;
    GCssThemes.CaseSensitive := False;
    GCssThemes.OwnsObjects := True;
  end;
  Result := GCssThemes;
end;

procedure TyRegisterThemeCss(const AName, ACss: string);
var idx: Integer; nm: string;
begin
  nm := Trim(AName);
  if nm = '' then Exit;
  idx := CssRegistry.IndexOf(nm);
  if idx >= 0 then
    TTyThemeCssHolder(CssRegistry.Objects[idx]).Css := ACss   // last wins
  else
    CssRegistry.AddObject(nm, TTyThemeCssHolder.Create(ACss));
end;

function TyResolveThemeCss(const AName: string; out ACss: string): Boolean;
var idx: Integer;
begin
  ACss := '';
  if (GCssThemes = nil) or (Trim(AName) = '') then Exit(False);
  idx := GCssThemes.IndexOf(Trim(AName));
  if idx < 0 then Exit(False);
  ACss := TTyThemeCssHolder(GCssThemes.Objects[idx]).Css;
  Result := True;
end;
```

在 `TyThemeNames` 里追加 CSS 源的名字(去重,文件源在前):

```pascal
function TyThemeNames: TStringArray;
var i, n: Integer;
begin
  n := 0;
  if GThemes <> nil then n := GThemes.Count;
  if GCssThemes <> nil then Inc(n, GCssThemes.Count);
  SetLength(Result, n);
  n := 0;
  if GThemes <> nil then
    for i := 0 to GThemes.Count - 1 do begin Result[n] := GThemes.Names[i]; Inc(n); end;
  if GCssThemes <> nil then
    for i := 0 to GCssThemes.Count - 1 do begin Result[n] := GCssThemes[i]; Inc(n); end;
end;
```

在 `TyUnregisterTheme` 末尾追加删除 CSS 源:

```pascal
  if (GCssThemes <> nil) and (Trim(AName) <> '') then
  begin
    idx := GCssThemes.IndexOf(Trim(AName));
    if idx >= 0 then GCssThemes.Delete(idx);
  end;
```

在 `TyThemeRegistered` 里也认 CSS 源:

```pascal
function TyThemeRegistered(const AName: string): Boolean;
begin
  Result := ((GThemes <> nil) and (Trim(AName) <> '') and (GThemes.IndexOfName(Trim(AName)) >= 0))
         or ((GCssThemes <> nil) and (Trim(AName) <> '') and (GCssThemes.IndexOf(Trim(AName)) >= 0));
end;
```

finalization 段加 `FreeAndNil(GCssThemes);`(OwnsObjects 释放 holder)。

> `TyUnregisterTheme` 现有 `var idx: Integer;` 已存在,可复用;若作用域不够请在该过程 var 段确保有 `idx`。

- [ ] **Step 1.5: 运行,确认通过(绿)** — 运行测试套件。Expected:`TThemeRegistryCssTest` 3 项通过;无新增失败/error。

- [ ] **Step 1.6: 提交**

```bash
git add source/tyControls.ThemeRegistry.pas source/tyControls.BuiltinThemeData.pas source/tyControls.BuiltinThemes.pas tests/test.builtinthemes.pas tests/tytests.lpr
git commit -m "feat(tycontrols): theme registry — name->inline CSS source (TyRegisterThemeCss)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase B:生成双模基底 + system 数据

### Task 2：`gen-builtinthemes.ps1` 生成 `BuiltinThemeData.pas` + sync 测试

**Files:**
- Create: `gen-builtinthemes.ps1`(仓库根)
- Regenerate: `source/tyControls.BuiltinThemeData.pas`(替换 Task 1 的占位)
- Modify: `tests/test.builtinthemes.pas`(加 sync 测试类)

- [ ] **Step 2.1: 写 sync 失败测试** — `tests/test.builtinthemes.pas` 加类 + 注册:

声明(interface type 段加):

```pascal
  TBuiltinSyncTest = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
    function NormalizeCss(const S: string): string;
  published
    procedure TestDualBaseMatchesAuto;
    procedure TestSystemMatchesSystem;
  end;
```

实现(implementation 段加,initialization 里 `RegisterTest(TBuiltinSyncTest);`):

```pascal
function TBuiltinSyncTest.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
end;

function TBuiltinSyncTest.NormalizeCss(const S: string): string;
var sl: TStringList; i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Text := S;
    for i := 0 to sl.Count - 1 do sl[i] := TrimRight(sl[i]);
    Result := Trim(sl.Text);
  finally sl.Free; end;
end;

procedure TBuiltinSyncTest.TestDualBaseMatchesAuto;
var f: TStringList;
begin
  f := TStringList.Create;
  try
    f.LoadFromFile(ThemePath('auto.tycss'));
    AssertEquals('dual base == auto.tycss', NormalizeCss(f.Text), NormalizeCss(TyBuiltinDualBaseCss));
  finally f.Free; end;
end;

procedure TBuiltinSyncTest.TestSystemMatchesSystem;
var f: TStringList;
begin
  f := TStringList.Create;
  try
    f.LoadFromFile(ThemePath('system.tycss'));
    AssertEquals('system css == system.tycss', NormalizeCss(f.Text), NormalizeCss(TyBuiltinSystemCss));
  finally f.Free; end;
end;
```

- [ ] **Step 2.2: 运行,确认失败(红)** — 运行测试套件。Expected:两项失败(占位返回 `''`)。

- [ ] **Step 2.3: 写生成脚本** — 创建 `gen-builtinthemes.ps1`:

```powershell
# Regenerate source/tyControls.BuiltinThemeData.pas from themes/auto.tycss + themes/system.tycss.
# Sync-tested byte-identical (test.builtinthemes). Run from repo root:
#   powershell -File gen-builtinthemes.ps1
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)   # UTF-8 no BOM

function Emit-Func($name, $file) {
  $src = [IO.File]::ReadAllText($file, $enc)
  $lines = $src -split "`r`n|`n"
  if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("function $name: string;`r`nbegin`r`n  Result :=`r`n")
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $escd = $lines[$i] -replace "'", "''"
    if ($i -lt $lines.Count - 1) { $term = ' +' } else { $term = ';' }
    [void]$sb.Append("    '" + $escd + "' + LineEnding" + $term + "`r`n")
  }
  [void]$sb.Append("end;`r`n")
  return $sb.ToString()
}

$u = New-Object System.Text.StringBuilder
[void]$u.Append("unit tyControls.BuiltinThemeData;`r`n`r`n")
[void]$u.Append("{ GENERATED from themes/auto.tycss + themes/system.tycss by gen-builtinthemes.ps1 - do NOT`r`n")
[void]$u.Append("  edit by hand; edit the .tycss files and re-run the generator. Sync-tested byte-identical`r`n")
[void]$u.Append("  to those files (test.builtinthemes). }`r`n`r`n")
[void]$u.Append("{`$mode objfpc}{`$H+}`r`n`r`ninterface`r`n`r`n")
[void]$u.Append("function TyBuiltinDualBaseCss: string;`r`nfunction TyBuiltinSystemCss: string;`r`n`r`nimplementation`r`n`r`n")
[void]$u.Append((Emit-Func 'TyBuiltinDualBaseCss' 'themes\auto.tycss'))
[void]$u.Append("`r`n")
[void]$u.Append((Emit-Func 'TyBuiltinSystemCss' 'themes\system.tycss'))
[void]$u.Append("`r`nend.`r`n")
[IO.File]::WriteAllText('source\tyControls.BuiltinThemeData.pas', $u.ToString(), $enc)
Write-Output "Regenerated BuiltinThemeData.pas from auto.tycss + system.tycss"
```

- [ ] **Step 2.4: 生成** — 仓库根运行:`powershell -File gen-builtinthemes.ps1`。Expected:输出 `Regenerated BuiltinThemeData.pas ...`;`source/tyControls.BuiltinThemeData.pas` 被真实内容替换。

- [ ] **Step 2.5: 运行,确认通过(绿)** — 运行测试套件。Expected:`TBuiltinSyncTest` 两项通过;无回归。

- [ ] **Step 2.6: 提交**

```bash
git add gen-builtinthemes.ps1 source/tyControls.BuiltinThemeData.pas tests/test.builtinthemes.pas
git commit -m "feat(tycontrols): compile-in dual-mode base + system CSS (gen-builtinthemes.ps1)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase C:`BuiltinThemes` 单元(12 套)

### Task 3：种子表 + CSS 生成 + 注册

**Files:**
- Modify: `source/tyControls.BuiltinThemes.pas`(替换 Task 1 占位)
- Modify: `tests/test.builtinthemes.pas`(加 TBuiltinThemesTest)

- [ ] **Step 3.1: 写失败测试** — `tests/test.builtinthemes.pas` 加类 + 注册:

声明:

```pascal
  TBuiltinThemesTest = class(TTestCase)
  published
    procedure TestNamesCountAndContents;
    procedure TestAllBuiltinsLoad;
    procedure TestDraculaPalette;
    procedure TestNordPalette;
  end;
```

实现(`RegisterTest(TBuiltinThemesTest);`):

```pascal
procedure TBuiltinThemesTest.TestNamesCountAndContents;
var n: TStringArray; i: Integer; sawDefault, sawSystem, sawDracula: Boolean;
begin
  n := TyBuiltinThemeNames;
  AssertEquals('12 built-in themes', 12, Length(n));
  sawDefault := False; sawSystem := False; sawDracula := False;
  for i := 0 to High(n) do
  begin
    if n[i] = 'default'  then sawDefault := True;
    if n[i] = 'system'   then sawSystem := True;
    if n[i] = 'dracula'  then sawDracula := True;
  end;
  AssertTrue('has default', sawDefault);
  AssertTrue('has system', sawSystem);
  AssertTrue('has dracula', sawDracula);
end;

procedure TBuiltinThemesTest.TestAllBuiltinsLoad;
var n: TStringArray; i: Integer; m: TTyStyleModel; s: TTyStyleSet;
begin
  // 每套内置 CSS 都要能加载且在两个模式下解析出 TyButton 背景(不抛、不空)。
  n := TyBuiltinThemeNames;
  for i := 0 to High(n) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss(TyBuiltinThemeCss(n[i]));
      m.SetMode('light');
      s := m.ResolveStyle('TyButton', '', []);
      AssertTrue(n[i] + ' light has bg', tpBackground in s.Present);
      m.SetMode('dark');
      s := m.ResolveStyle('TyButton', '', []);
      AssertTrue(n[i] + ' dark has bg', tpBackground in s.Present);
    finally m.Free; end;
  end;
end;

procedure TBuiltinThemesTest.TestDraculaPalette;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  // TyButton.primary 背景 = var(--accent)。dracula light accent #644AC9 / dark #BD93F9。
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss('dracula'));
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', 'primary', []);
    AssertEquals('dracula light accent R', $64, TyRedOf(s.Background.Color));
    AssertEquals('dracula light accent G', $4A, TyGreenOf(s.Background.Color));
    AssertEquals('dracula light accent B', $C9, TyBlueOf(s.Background.Color));
    m.SetMode('dark');
    s := m.ResolveStyle('TyButton', 'primary', []);
    AssertEquals('dracula dark accent R', $BD, TyRedOf(s.Background.Color));
    AssertEquals('dracula dark surface R', $28, TyRedOf(m.ResolveStyle('TyButton','',[]).Background.Color));
  finally m.Free; end;
end;

procedure TBuiltinThemesTest.TestNordPalette;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  // nord dark surface #2E3440; light surface #ECEFF4。
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss('nord'));
    m.SetMode('dark');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('nord dark surface R', $2E, TyRedOf(s.Background.Color));
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('nord light surface R', $EC, TyRedOf(s.Background.Color));
  finally m.Free; end;
end;
```

- [ ] **Step 3.2: 运行,确认失败(红)** — 运行测试套件。Expected:失败(占位 `TyBuiltinThemeNames` 返回 nil、`TyBuiltinThemeCss` 返回 '')。

- [ ] **Step 3.3: 实现 BuiltinThemes** — 用以下完整内容替换 `source/tyControls.BuiltinThemes.pas`:

```pascal
unit tyControls.BuiltinThemes;
{$mode objfpc}{$H+}
{ 12 套内置主题(编译进二进制):default(双模中性基底)+ 10 套 curated 双模设计师调色板
  + system(OS 强调色)。curated 主题 = 双模基底 + @mode light/dark 各覆盖 5 个颜色种子,
  其余令牌 resolve 时按新种子派生(on()/darken/lighten)。明暗由 Controller.Mode/Follow 控制。 }
interface
uses
  Classes, SysUtils, tyControls.ThemeRegistry, tyControls.BuiltinThemeData;

function TyBuiltinThemeNames: TStringArray;            // 12 个名字(default..material, system)
function TyBuiltinThemeCss(const AName: string): string;
procedure TyRegisterBuiltinThemes;                     // 全部注册为 CSS 源(显式调用)

implementation

type
  TSeed = record Accent, Surface, OnSurface, Border, Danger: string; end;
  TDef  = record Name: string; L, D: TSeed; end;

const
  cDefault = 'default';
  cSystem  = 'system';

  // 5 颜色种子(accent/surface/on-surface/border/danger);官方源见 plan。
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
```

- [ ] **Step 3.4: 运行,确认通过(绿)** — 运行测试套件。Expected:`TBuiltinThemesTest` 4 项通过(含每套双模加载 + dracula/nord 取色);无回归。

- [ ] **Step 3.5: 提交**

```bash
git add source/tyControls.BuiltinThemes.pas tests/test.builtinthemes.pas
git commit -m "feat(tycontrols): BuiltinThemes — 12 compile-in themes (10 curated dual-mode + default + system)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase D:Controller 支持内置 CSS 主题

### Task 4：`SetThemeName` 命中内置 CSS 即从字符串加载

**Files:**
- Modify: `source/tyControls.Controller.pas`
- Modify: `tests/test.builtinthemes.pas`(加 TControllerThemeNameTest)

- [ ] **Step 4.1: 写失败测试** — `tests/test.builtinthemes.pas` 加类 + 注册:

声明:

```pascal
  TControllerThemeNameTest = class(TTestCase)
  published
    procedure TestThemeNameLoadsBuiltinCss;
    procedure TestModePersistsAcrossThemeSwitch;
  end;
```

实现(`RegisterTest(TControllerThemeNameTest);`):

```pascal
procedure TControllerThemeNameTest.TestThemeNameLoadsBuiltinCss;
var c: TTyStyleController; s: TTyStyleSet;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'gruvbox';
    c.Mode := 'dark';
    s := c.Model.ResolveStyle('TyButton', 'primary', []);
    // gruvbox dark accent #FE8019
    AssertEquals('gruvbox dark accent R', $FE, TyRedOf(s.Background.Color));
    AssertEquals('gruvbox dark accent G', $80, TyGreenOf(s.Background.Color));
  finally c.Free; end;
end;

procedure TControllerThemeNameTest.TestModePersistsAcrossThemeSwitch;
var c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    c.Mode := 'dark';
    c.ThemeName := 'nord';
    AssertEquals('mode persists after theme switch', 'dark', c.Mode);
    AssertEquals('nord dark surface R', $2E,
      TyRedOf(c.Model.ResolveStyle('TyButton', '', []).Background.Color));
  finally c.Free; end;
end;
```

- [ ] **Step 4.2: 运行,确认失败(红)** — 运行测试套件。Expected:失败——`ThemeName:='gruvbox'` 现走文件分支(注册的是 CSS 源,`TyResolveTheme` 文件查找失败),model 仍是内置 light 兜底,gruvbox 取色不成立。

- [ ] **Step 4.3: 实现 CSS 分支** — `source/tyControls.Controller.pas`,`uses` 加 `tyControls.ThemeRegistry`(若未引入)。把 `SetThemeName` 改为先查 CSS 源:

```pascal
procedure TTyStyleController.SetThemeName(const AValue: string);
var
  src, css: string;
begin
  if FThemeName = AValue then Exit;
  FThemeName := AValue;
  FThemeFile := '';   // ThemeFile/ThemeName 互斥
  UpdateWatch;        // 无文件可监视
  if AValue = '' then Exit;
  if TyResolveThemeCss(AValue, css) then
  begin
    // 内置(编译进二进制)主题:从字符串 REPLACE 加载 + bump ThemeVersion。
    FModel.LoadFromCss(css);
    Changed;
  end
  else if TyResolveTheme(AValue, src) and (src <> '') and FileExists(src) then
  begin
    FModel.LoadFromFile(src);
    Changed;
  end;
end;
```

> 现有 `SetThemeName` 已 `uses tyControls.ThemeRegistry`?Controller 单元已 `uses ... tyControls.ThemeRegistry`(`TyResolveTheme` 来自此),故无需新增。

- [ ] **Step 4.4: 运行,确认通过(绿)** — 运行测试套件。Expected:`TControllerThemeNameTest` 两项通过;现有 `test.controller`/`test.themeregistry` 不破。

- [ ] **Step 4.5: 提交**

```bash
git add source/tyControls.Controller.pas tests/test.builtinthemes.pas
git commit -m "feat(tycontrols): Controller.ThemeName resolves compile-in CSS themes first

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase E:打包接入

### Task 5：把新单元加入运行期包

**Files:**
- Modify: `tyControls.lpk`

- [ ] **Step 5.1: 读 .lpk 结构** — 打开 `tyControls.lpk`,找到 `<Files Count="N">` 与某个现有单元条目(如 `tyControls.ThemeRegistry.pas` 的 `<Item><Filename .../><UnitName .../></Item>`)作模板。

- [ ] **Step 5.2: 加入两个新单元** — 在 `<Files>` 列表加两条(镜像现有条目格式,Filename 用 `source\tyControls.BuiltinThemeData.pas` / `source\tyControls.BuiltinThemes.pas`,UnitName 对应),并把 `<Files Count="N">` 的 N 增加 2。

- [ ] **Step 5.3: 构建包,确认通过** — 运行:`lazbuild tyControls.lpk`。Expected:`Success`,无错误。

- [ ] **Step 5.4: 提交**

```bash
git add tyControls.lpk
git commit -m "build(tycontrols): add BuiltinThemes + BuiltinThemeData to runtime package

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase F:demo 换肤 UI

### Task 6：还原 demo 的 DPI churn

**Files:**
- Restore: `examples/demo/mainform.lfm`, `examples/demo/demo.lpi`

- [ ] **Step 6.1: 还原** — 运行:`git checkout -- examples/demo/mainform.lfm examples/demo/demo.lpi`。然后 `git status --short` 应不再显示这两个文件(除非本任务后续再改)。Expected:工作树这两个文件回到已提交版本。

- [ ] **Step 6.2: 基线编译 demo** — 运行:`lazbuild examples/demo/demo.lpi`。Expected:`Success`(还原后的 demo 能编)。

---

### Task 7：移除 6 个主题按钮

**Files:**
- Modify: `examples/demo/mainform.lfm`, `examples/demo/mainform.pas`

- [ ] **Step 7.1: 删 .lfm 按钮对象** — 在 `examples/demo/mainform.lfm` 中删除这 6 个对象块(每个形如 `object BtnLight: TTyButton ... end`):`BtnLight`、`BtnDark`、`BtnShowcase`、`BtnGreen`、`BtnAuto`、`BtnSystem`。仅删这 6 块,勿动其它控件。

- [ ] **Step 7.2: 删 .pas 字段与 handler** — 在 `examples/demo/mainform.pas`:
  - 删字段声明 `BtnLight: TTyButton;` … `BtnSystem: TTyButton;`(6 行,第 22-27 行附近)。
  - 删方法声明 `procedure BtnLightClick(Sender: TObject);` … `procedure BtnSystemClick(Sender: TObject);`(6 行)。
  - 删这 6 个方法的实现体(`BtnLightClick`/`BtnDarkClick`/`BtnShowcaseClick`/`BtnGreenClick`/`BtnAutoClick`/`BtnSystemClick` 整段)。
  - 保留 `ApplyTheme`、`ThemeDir`(后者自定义文件加载仍可能用到;若最终未用到则一并删,见 Task 8)。

- [ ] **Step 7.2b: 编译确认无悬空引用** — 运行:`lazbuild examples/demo/demo.lpi`。Expected:`Success`(删除干净,无对未定义按钮/handler 的引用)。若报错,补删遗留引用。

> 本任务不单独提交,与 Task 8 一起提交(中间态 demo 没有换肤入口)。

---

### Task 8：代码内换肤 UI(下拉 + 外观三态 + 随机 + 自定义)

**Files:**
- Modify: `examples/demo/mainform.pas`

- [ ] **Step 8.1: uses + 字段 + 方法声明** — `examples/demo/mainform.pas`:
  - `uses` 确保含 `tyControls.BuiltinThemes`、`Dialogs`(TOpenDialog,现有 uses 已有 Dialogs)。加 `tyControls.BuiltinThemes`。
  - 在 `TDemoMainForm` 私有区加字段与方法:

```pascal
  private
    ThemeCombo: TTyComboBox;
    BtnApLight, BtnApDark, BtnApAuto, BtnRandom: TTyButton;
    procedure BuildSwitcher;
    procedure ThemeComboChange(Sender: TObject);
    procedure SetAppearance(AFollow: TTyThemeFollow; const AMode: string;
      ASelected: TTyButton);
    procedure ApLightClick(Sender: TObject);
    procedure ApDarkClick(Sender: TObject);
    procedure ApAutoClick(Sender: TObject);
    procedure RandomClick(Sender: TObject);
    procedure ApplyBuiltin(const AName: string);
```

  - `TTyComboBox` 在 `tyControls.ComboBox`(uses 已有);`TTyThemeFollow` 在 `tyControls.Controller`(uses 已有)。

- [ ] **Step 8.2: 实现** — 在 implementation 段加(并在 `FormCreate` 末尾调用 `BuildSwitcher`):

```pascal
procedure TDemoMainForm.BuildSwitcher;
var
  names: TStringArray;
  i: Integer;
begin
  TyRegisterBuiltinThemes;

  ThemeCombo := TTyComboBox.Create(Self);
  ThemeCombo.Parent := Self;
  ThemeCombo.SetBounds(16, 8, 160, 28);
  ThemeCombo.Controller := Controller;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do ThemeCombo.Items.Add(names[i]);
  ThemeCombo.Items.Add('自定义…');
  ThemeCombo.ItemIndex := 0;                 // default
  ThemeCombo.OnChange := @ThemeComboChange;

  BtnApLight := TTyButton.Create(Self);
  BtnApLight.Parent := Self; BtnApLight.SetBounds(188, 8, 56, 28);
  BtnApLight.Caption := '浅色'; BtnApLight.StyleClass := 'ghost';
  BtnApLight.Controller := Controller; BtnApLight.OnClick := @ApLightClick;

  BtnApDark := TTyButton.Create(Self);
  BtnApDark.Parent := Self; BtnApDark.SetBounds(248, 8, 56, 28);
  BtnApDark.Caption := '深色'; BtnApDark.StyleClass := 'ghost';
  BtnApDark.Controller := Controller; BtnApDark.OnClick := @ApDarkClick;

  BtnApAuto := TTyButton.Create(Self);
  BtnApAuto.Parent := Self; BtnApAuto.SetBounds(308, 8, 84, 28);
  BtnApAuto.Caption := '跟随系统'; BtnApAuto.StyleClass := 'ghost';
  BtnApAuto.Controller := Controller; BtnApAuto.OnClick := @ApAutoClick;

  BtnRandom := TTyButton.Create(Self);
  BtnRandom.Parent := Self; BtnRandom.SetBounds(400, 8, 84, 28);
  BtnRandom.Caption := '随机换肤'; BtnRandom.StyleClass := 'primary';
  BtnRandom.Controller := Controller; BtnRandom.OnClick := @RandomClick;

  // 初始:default 主题 + 跟随系统外观
  ApplyBuiltin('default');
  SetAppearance(tfFollowSystem, '', BtnApAuto);
end;

procedure TDemoMainForm.ApplyBuiltin(const AName: string);
begin
  // 只换主题,不动 Follow/Mode(外观轴由三态独占)。
  Controller.ThemeName := AName;
  ApplyChromeTheme(Controller);
  if TitleBar <> nil then TitleBar.Caption := 'TyControls Demo';
end;

procedure TDemoMainForm.ThemeComboChange(Sender: TObject);
var idx: Integer; dlg: TOpenDialog;
begin
  idx := ThemeCombo.ItemIndex;
  if idx < 0 then Exit;
  if ThemeCombo.Items[idx] = '自定义…' then
  begin
    dlg := TOpenDialog.Create(Self);
    try
      dlg.Filter := 'TyControls 主题 (*.tycss)|*.tycss';
      if dlg.Execute then
      begin
        Controller.ThemeFile := dlg.FileName;   // 自定义文件(REPLACE)
        ApplyChromeTheme(Controller);
      end;
    finally dlg.Free; end;
  end
  else
    ApplyBuiltin(ThemeCombo.Items[idx]);
end;

procedure TDemoMainForm.SetAppearance(AFollow: TTyThemeFollow; const AMode: string;
  ASelected: TTyButton);
begin
  Controller.Follow := AFollow;
  if AFollow = tfManual then Controller.Mode := AMode;   // 跟随系统时 Mode 由 OS 决定
  // 三态互斥:用 ghost 的 Down 选中态高亮当前外观。
  BtnApLight.Down := (ASelected = BtnApLight);
  BtnApDark.Down  := (ASelected = BtnApDark);
  BtnApAuto.Down  := (ASelected = BtnApAuto);
  ApplyChromeTheme(Controller);
end;

procedure TDemoMainForm.ApLightClick(Sender: TObject);
begin SetAppearance(tfManual, 'light', BtnApLight); end;

procedure TDemoMainForm.ApDarkClick(Sender: TObject);
begin SetAppearance(tfManual, 'dark', BtnApDark); end;

procedure TDemoMainForm.ApAutoClick(Sender: TObject);
begin SetAppearance(tfFollowSystem, '', BtnApAuto); end;

procedure TDemoMainForm.RandomClick(Sender: TObject);
var names: TStringArray; i, pick: Integer;
begin
  names := TyBuiltinThemeNames;
  if Length(names) = 0 then Exit;
  pick := ThemeCombo.ItemIndex;
  // 随机取一个不同的内置主题(names 索引 0..High;下拉里 0..High 与之对应,末尾是「自定义…」)。
  for i := 0 to 7 do
  begin
    pick := Random(Length(names));
    if pick <> ThemeCombo.ItemIndex then Break;
  end;
  ThemeCombo.ItemIndex := pick;     // 同步下拉
  ApplyBuiltin(names[pick]);
end;
```

  - 在 `FormCreate` 末尾(`ApplyTheme('light.tycss');` 那行**替换为**)调用 `BuildSwitcher;`(BuildSwitcher 内部已设初始主题与外观,故移除原 `ApplyTheme('light.tycss')`)。`Randomize;` 也加到 `FormCreate` 开头一次(让 `Random` 有种子)。

- [ ] **Step 8.3: 编译 demo** — 运行:`lazbuild examples/demo/demo.lpi`。Expected:`Success`,无错误。

- [ ] **Step 8.4: 提交**

```bash
git add examples/demo/mainform.pas examples/demo/mainform.lfm
git commit -m "docs(tycontrols): demo theme switcher — built-in dropdown + appearance tri-state + random + custom

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 8.5: 手测(记录,不阻塞)** — 真机跑 demo:下拉切 dracula/nord/gruvbox 等即时换肤;浅/深/跟随系统三态;随机换肤;「自定义…」选一个 `.tycss`(如 `themes/green.tycss`)。记录结果到提交/PR。

---

## Phase G:文档

### Task 9：内置主题文档

**Files:**
- Create: `docs/themes.md`

- [ ] **Step 9.1: 写文档** — 创建 `docs/themes.md`,内容涵盖:
  - 12 套内置主题清单(default + 10 curated + system)及来源致谢(One/Dracula/Nord/Solarized/Gruvbox/GitHub/Catppuccin/Tokyo Night/Monokai/Material,均开源调色板)。
  - 用法:`uses tyControls.BuiltinThemes; ... TyRegisterBuiltinThemes; Controller.ThemeName := 'dracula';`。
  - 明/暗/跟随:`Controller.Mode := 'light'/'dark'`;`Controller.Follow := tfFollowSystem`(= auto)。说明明暗是 controller 轴、与主题正交;每套内置主题都双模。
  - 自定义主题:`Controller.ThemeFile := 'my.tycss'`(或 `TyRegisterThemeFile` + `ThemeName`)。
  - 列每套的浅/深代表色(可引用本 plan 的表)。

具体可粘贴的骨架:

```markdown
# 内置主题

TyControls 自带 12 套编译进二进制的主题(无需随程序分发 .tycss):11 套 curated 双模设计师调色板 + `system`(跟随 OS 强调色)。

## 用法

​```pascal
uses tyControls.Controller, tyControls.BuiltinThemes;
TyRegisterBuiltinThemes;              // 注册 12 套到全局注册表(启动时调用一次)
Controller.ThemeName := 'dracula';   // 切换内置主题
Controller.Mode := 'dark';           // 明/暗:'light' | 'dark'
// 或跟随系统(= auto):
Controller.Follow := tfFollowSystem;
​```

明/暗/跟随系统是 **controller 的轴**(`Mode`/`Follow`),与「选哪套主题」正交;每套内置主题都含 light+dark 两版。

## 主题清单
default · one · dracula · nord · solarized · gruvbox · github · catppuccin · tokyonight · monokai · material · system

调色板取自各开源项目官方色值(MIT 等),仅借用色值并致谢。

## 自定义主题
​```pascal
Controller.ThemeFile := 'themes/my.tycss';   // 直接加载文件
// 或先注册名字再按名切换:
TyRegisterThemeFile('mine', 'themes/my.tycss');
Controller.ThemeName := 'mine';
​```
```

> 落盘时把全角反引号改回三反引号代码块。

- [ ] **Step 9.2: 提交**

```bash
git add docs/themes.md
git commit -m "docs(tycontrols): document the built-in theme pack + Mode/Follow appearance axis

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase H:收尾

### Task 10：全量回归 + 包/示例构建

- [ ] **Step 10.1: 全量测试** — `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`。Expected:`Number of failures: 0`;`Number of errors: 11`(均为既有 win32-1407)。
- [ ] **Step 10.2: 包** — `lazbuild tyControls.lpk && lazbuild tycontrols_dt.lpk`。Expected:均成功。
- [ ] **Step 10.3: 示例** — `lazbuild examples/demo/demo.lpi && lazbuild examples/button/button_example.lpi`。Expected:均成功。
- [ ] **Step 10.4:(可选)PR** — `gh pr create`,正文链接 spec/plan、列 12 套主题、附 Task 8.5 手测结果。

---

## 自检对照(spec 覆盖)

- §3 12 套主题(11 curated 双模 + system) → Task 2(基底/system 数据)、Task 3(种子表+生成) ✓
- §4 注册表 CSS 源 → Task 1 ✓
- §5 BuiltinThemes 单元(names/css/register) → Task 3 ✓
- §6 gen 脚本 + sync 测试 → Task 2 ✓
- §7 Controller.ThemeName 内置 CSS + Mode 保持 → Task 4 ✓
- §8 demo(下拉+外观三态+随机+自定义、代码内建、先还原 churn) → Task 6/7/8 ✓
- §9 文件清单(.lpk/runner/docs) → Task 5/1/9 ✓
- §10 测试(注册表/builtin/controller/sync/回归) → Task 1/3/4/2/10 ✓

## 风险备忘

- **种子覆盖机制**:依赖「同名 @mode 后块覆盖前块的同名 var」+「派生令牌 resolve 时按合并种子重算」。Task 3 的 dracula/nord 取色 + Task 3 的「每套双模都解析出背景」覆盖此点。
- **gen sync**:改 auto/system 后必须重跑 `gen-builtinthemes.ps1`,否则 `TBuiltinSyncTest` 失败(守门)。
- **demo .lfm**:先还原 churn(Task 6);换肤控件代码内建,.lfm 仅删 6 按钮,降低 DPI 噪声面。
- **TyThemeNames 顺序**:现改为「文件源在前 + CSS 源在后」。若有测试依赖旧顺序需同步(现有 `test.themeregistry` 只注册文件源,不受影响)。
- **`one` 调色板**:研究时该项 API 529 超时,采用业界公认的 Atom One Light/Dark 值(One Dark #282C34/#61AFEF;One Light #FAFAFA/#4078F2),实施时如有官方源可二次核对。
- **Random**:`FormCreate` 需 `Randomize`(本沙箱无关;真机生效)。
```
