# TyControls 内置主题包(curated 设计师主题)+ 注册表 CSS 源 + demo 换肤 UI — 设计

- 日期：2026-06-19
- 状态：设计讨论中（待批准）
- 范围：编译进二进制的 12 套内置主题(11 套 curated 双模 + system)、注册表支持 CSS 字符串源、`Controller.ThemeName` 走内置 CSS、demo 换肤 UI(主题下拉 + 外观三态 + 随机 + 自定义)

---

## 1. 背景与目标

用户希望 TyControls 自带一组「开箱即用」的内置主题(无需随程序分发 `.tycss` 文件),用户也能加载自定义主题。经讨论确定两条关键架构决策:

1. **明/暗/跟随系统是 controller 的轴,不是主题身份。** `Controller.Mode`(`light`/`dark`)与 `Controller.Follow`(`tfManual`/`tfFollowSystem`)**已存在**。所谓「auto」=`Follow := tfFollowSystem`,不该是一个主题。因此每套内置主题都做成**双模**(`@mode light/dark`),明暗交给 controller。
2. **内置主题用 curated 设计师调色板,而非纯强调色色板。** 引擎是种子驱动(5 色 + 1 圆角,其余 resolve 时派生),一套完整调色板只是「覆盖 5-6 个种子」,与「只覆盖 1 个 accent」成本相同、效果远好。绝大多数知名主题本就有 light+dark 两版,正好契合双模架构。

**最终:12 套内置主题 = 11 套 curated 双模家族 + system(OS 强调色,双模)。** 全部编译进二进制。

硬性原则延续:视觉值由主题种子/令牌驱动,控件代码不写死颜色。

---

## 2. 现状锚点

- **种子→派生**:`auto.tycss` 的 `@mode light/dark` 各定义 6 个种子(`--accent --surface --on-surface --border --danger --radius`)+ 一张 MAP(`--surface-hover: darken(--surface,4%)` 等,**硬编码 darken/lighten 方向**,light 用 darken、dark 用 lighten;**不依赖 `--ty-mode`**)+ 语义别名(`--focus-ring`/`--selection`/`--on-accent: on(--accent)` 等)+ 标量。`system.tycss` 同形,但种子 `--accent: system-accent`、用 `elevate()`+`--ty-mode: system-mode` 跟随 OS。
- **@mode 合并**:`AddSheetInto`/`RebuildMergedVars` 把同名 `@mode` 块的 vars 后者覆盖前者;`RebuildMergedVars` 只把**当前激活 mode** 的 vars 叠在 user `:root` 上。MAP 是**表达式**,resolve 时按合并后的种子求值。⇒ 在一份 CSS 里 `auto 全文 + @mode light{:root{覆盖6种子}} + @mode dark{:root{覆盖6种子}}`,即可只改种子、其余整套派生重算。
- **注册表**(`tyControls.ThemeRegistry`):name→源(今为文件路径)。`TyRegisterThemeFile`/`TyResolveTheme`/`TyThemeNames`/`TyThemeRegistered`/`TyUnregisterTheme`。`Controller.ThemeName` 经 `TyResolveTheme`→`Model.LoadFromFile`(REPLACE+bump version)。
- **Controller**:`Mode`(GetMode/SetMode→Model.SetMode)、`Follow`(tfManual/tfFollowSystem;tfFollowSystem 时 `RefreshFromSystem` 把 OS scheme 灌进 Mode、重解析 system-accent)。`LoadFromCss`(REPLACE)已存在。
- **编译进二进制的范式**:`tyControls.DefaultTheme.TyBuiltinThemeCss`(由 `gen-defaulttheme.ps1` 从 `light.tycss` 生成,`test.defaulttheme` 字节同步守门)。
- **demo**(`examples/demo/`,.lfm 设计):自带 `Controller`,现有 6 个主题按钮(`BtnLight/Dark/Showcase/Green/Auto/System`)→`Controller.LoadTheme(ThemeDir+文件)`。`ApplyTheme` 设 `Follow:=tfManual`+`LoadTheme`+`Changed`+`ApplyChromeTheme`。已有 `TTyComboBox`(ComboKind,演示用)。**注意**:工作树里 `mainform.lfm`/`demo.lpi` 有 IDE 的 DPI 重存 churn(192↔96),非本次改动,动手前先 `git checkout --` 还原。
- 既有 `.tycss` 文件:`light`/`dark`(DefaultTheme 源 + golden + 示例)、`auto`(双模基底源)、`system`(OS 主题源)、`green`(照片+毛玻璃,**仅示例**)、`showcase`(渐变,**仅示例**)。后两者不进内置包。

---

## 3. 12 套内置主题

每套**双模**(`@mode light` + `@mode dark`),种子级别覆盖,其余派生。`default` = 双模基底原样;`system` = OS 强调色(单独 CSS);其余 10 套 = 基底 + 每模 6 种子覆盖。

注册名(小写单 token):`default one dracula nord solarized gruvbox github catppuccin tokyonight monokai material system`。

> **配色来源**:取自各开源项目官方调色板(One/Atom、Dracula+Alucard、Nord、Solarized、Gruvbox、GitHub、Catppuccin Latte/Mocha、Tokyo Night Day/Night、Monokai Pro、Material;多为 MIT)。下表为**拟定种子**(accent/surface/on-surface/border/danger;radius 默认 6px),**实施时以各项目官方色值逐一核对/定稿**(计划阶段做一次取色核对)。`--on-accent`/`--on-danger` 由 `on()` 自动选黑/白字,无需手填。

### 浅色种子(@mode light)
| 主题 | accent | surface | on-surface | border | danger |
|---|---|---|---|---|---|
| default | #3B82F6 | #FFFFFF | #1F2937 | #D1D5DB | #EF4444 |
| one | #4078F2 | #FAFAFA | #383A42 | #D4D4D4 | #E45649 |
| dracula(Alucard) | #644AC9 | #FFFBEB | #1F1F1F | #CFCFDE | #CB3A2A |
| nord(Snow Storm) | #5E81AC | #ECEFF4 | #2E3440 | #D8DEE9 | #BF616A |
| solarized | #268BD2 | #FDF6E3 | #586E75 | #EEE8D5 | #DC322F |
| gruvbox | #D65D0E | #FBF1C7 | #3C3836 | #EBDBB2 | #CC241D |
| github | #0969DA | #FFFFFF | #1F2328 | #D0D7DE | #CF222E |
| catppuccin(Latte) | #1E66F5 | #EFF1F5 | #4C4F69 | #CCD0DA | #D20F39 |
| tokyonight(Day) | #2E7DE9 | #E1E2E7 | #3760BF | #C4C8DA | #F52A65 |
| monokai | #1E92D6 | #FAFAFA | #2D2A2E | #E0E0E0 | #E14775 |
| material | #2196F3 | #FAFAFA | #212121 | #E0E0E0 | #F44336 |

### 深色种子(@mode dark)
| 主题 | accent | surface | on-surface | border | danger |
|---|---|---|---|---|---|
| default | #60A5FA | #1E1E1E | #E5E7EB | #3F3F46 | #F87171 |
| one | #61AFEF | #282C34 | #ABB2BF | #3E4451 | #E06C75 |
| dracula | #BD93F9 | #282A36 | #F8F8F2 | #44475A | #FF5555 |
| nord(Polar Night) | #88C0D0 | #2E3440 | #D8DEE9 | #3B4252 | #BF616A |
| solarized | #268BD2 | #002B36 | #839496 | #073642 | #DC322F |
| gruvbox | #FE8019 | #282828 | #EBDBB2 | #3C3836 | #FB4934 |
| github | #2F81F7 | #0D1117 | #C9D1D9 | #30363D | #F85149 |
| catppuccin(Mocha) | #89B4FA | #1E1E2E | #CDD6F4 | #313244 | #F38BA8 |
| tokyonight(Night) | #7AA2F7 | #1A1B26 | #C0CAF5 | #292E42 | #F7768E |
| monokai(Pro) | #78DCE8 | #2D2A2E | #FCFCFA | #5B595C | #FF6188 |
| material | #82B1FF | #212121 | #EEEEEE | #373737 | #F44336 |

- 深色 accent 可与浅色不同色阶(类 Tailwind 深色用更亮 accent),已在上表分别取值。
- 数量可调(加 Ayu/Rosé Pine/Everforest 或砍几套);`default` 与 `system` 固定保留。

---

## 4. 注册表加 CSS 字符串源(`tyControls.ThemeRegistry`)

现注册表只存 name→路径。新增 name→CSS 文本(多行,不能用 Name=Value 存,用一个 holder 对象):

```pascal
type
  TTyThemeCssHolder = class            // 私有实现细节,持有一段 CSS
    Css: string;
    constructor Create(const ACss: string);
  end;

procedure TyRegisterThemeCss(const AName, ACss: string);          // 注册内置 CSS 主题
function  TyResolveThemeCss(const AName: string; out ACss: string): Boolean;
```

- 用一个独立 `GCssThemes: TStringList`(CaseSensitive=False, OwnsObjects=True),`AddObject(name, TTyThemeCssHolder.Create(css))`;重复名 last-wins。
- `TyThemeNames` 合并文件源 + CSS 源(去重,文件源在前或注册序);`TyThemeRegistered`/`TyUnregisterTheme` 同时查/删两边。
- finalization 释放(OwnsObjects)。
- 现有文件源 API 与 `test.themeregistry` 行为不变(CSS 源是新增并行通道)。

---

## 5. 新单元 `tyControls.BuiltinThemes`

提供 12 套内置主题并注册进注册表。依赖编译进二进制的两段基底 CSS(由 gen 脚本从 `.tycss` 生成,见 §6):`TyBuiltinDualBaseCss`(= auto.tycss)、`TyBuiltinSystemCss`(= system.tycss)。

```pascal
type
  TTyBuiltinSeed = record
    Accent, Surface, OnSurface, Border, Danger: string;   // '#RRGGBB'
  end;
  TTyBuiltinThemeDef = record
    Name: string;
    HasOverride: Boolean;          // False = 用基底原样(default);True = 覆盖种子
    Light, Dark: TTyBuiltinSeed;
  end;

const
  TyBuiltinThemeDefs: array[...] of TTyBuiltinThemeDef = ( ... );  // §3 的 11 套(default 无覆盖)

function TyBuiltinThemeNames: TStringArray;       // 12 个名字(含 system)
function TyBuiltinThemeCss(const AName: string): string;  // 见下
procedure TyRegisterBuiltinThemes;                // 把 12 套全部 TyRegisterThemeCss
```

- `TyBuiltinThemeCss(name)`:
  - `system` → `TyBuiltinSystemCss`。
  - `default` → `TyBuiltinDualBaseCss`。
  - 其余 → `TyBuiltinDualBaseCss + LineEnding +`
    `'@mode light { :root { --accent:<L.Accent>; --surface:<L.Surface>; --on-surface:<L.OnSurface>; --border:<L.Border>; --danger:<L.Danger>; } }' + LineEnding +`
    `'@mode dark  { :root { --accent:<D.Accent>; ... } }'`。
    只覆盖 5 个颜色种子(radius 沿用基底 6px);MAP/别名/on() 在 resolve 时按新种子重算。
- `TyRegisterBuiltinThemes`:遍历 `TyBuiltinThemeNames`,`TyRegisterThemeCss(name, TyBuiltinThemeCss(name))`。**显式调用**(不在 initialization 自动注册,避免污染未使用它的 app/测试)。
- 单元加入 `tyControls.lpk` 与 `tytests.lpr`。

---

## 6. 生成脚本 + sync 测试

- 新 `gen-builtinthemes.ps1`:从 `themes/auto.tycss`、`themes/system.tycss` 生成 `source/tyControls.BuiltinThemeData.pas`,内含 `TyBuiltinDualBaseCss`/`TyBuiltinSystemCss`(纯生成的字符串常量,与 DefaultTheme 同套路)。**勿手改该文件**;改 auto/system 后重跑脚本。
- `tests/test.builtinthemes.pas` 含 sync 子测试:`TyBuiltinDualBaseCss` 规范化后 == `auto.tycss`、`TyBuiltinSystemCss` == `system.tycss`(规范化忽略行尾/尾空白,同 `test.defaulttheme`)。

---

## 7. `Controller.ThemeName` 支持内置 CSS

`SetThemeName` 先查 CSS 源,命中则从字符串加载(REPLACE),否则走现有文件分支:

```pascal
procedure TTyStyleController.SetThemeName(const AValue: string);
var src, css: string;
begin
  if FThemeName = AValue then Exit;
  FThemeName := AValue;
  FThemeFile := '';
  UpdateWatch;                                  // 无文件可监视
  if AValue = '' then Exit;
  if TyResolveThemeCss(AValue, css) then        // 内置(编译进二进制)
  begin
    FModel.LoadFromCss(css);                    // REPLACE + bump ThemeVersion
    Changed;
  end
  else if TyResolveTheme(AValue, src) and (src <> '') and FileExists(src) then
  begin
    FModel.LoadFromFile(src);
    Changed;
  end;
end;
```

- 切主题(REPLACE)不重置 `Model.FMode`(`Clear` 保留 FMode),故当前明/暗在换主题后保持。
- auto/system 的「跟随系统」仍由调用方设 `Follow := tfFollowSystem`(见 demo)。`system` 主题被 `LoadFromCss` 后,`system-accent`/`system-mode` 哨兵照常在 `RebuildMergedVars` 解析为 OS 值。

---

## 8. demo 换肤 UI

先 `git checkout -- examples/demo/mainform.lfm examples/demo/demo.lpi` 还原 churn。

- **移除**现有 6 个主题按钮(.lfm 删对象 + .pas 删 6 个 handler)。
- **代码内**(`FormCreate`)创建换肤控件(不进 .lfm,避免 DPI 重存噪声;父挂到表单/某个 panel,逻辑坐标):
  - **主题下拉**(`TTyComboBox`):`TyRegisterBuiltinThemes` 后用 `TyBuiltinThemeNames` 填 12 项 + 末尾「自定义…」。主题选择**只决定哪套主题**,不碰 Follow/Mode(明暗由外观三态独占,正交)。`OnChange`:
    - 选「自定义…」→`TOpenDialog`(`*.tycss`)→`Controller.ThemeFile:=选中文件`;`ApplyChromeTheme`。
    - 选内置 name → `ApplyBuiltin(name)`:`Controller.ThemeName:=name; ApplyChromeTheme(Controller)`。**不**改 Follow/Mode(`system` 主题在 manual light/dark 下其 `system-accent` 仍由 `RebuildMergedVars` 解析为 OS 强调色,故无需特判)。
  - **外观三态**(浅色 / 深色 / 跟随系统)——**外观轴的唯一控制处**。用三个 **ghost 按钮 + `Down` 选中态**(顺带 dogfood 上一特性;应用层互斥:点中的 `Down:=True`,另两个 `Down:=False`):
    - 浅色 → `Controller.Follow:=tfManual; Controller.Mode:='light'`
    - 深色 → `Controller.Follow:=tfManual; Controller.Mode:='dark'`
    - 跟随系统 → `Controller.Follow:=tfFollowSystem`(把 OS scheme 灌进 Mode)
    - 之后 `ApplyChromeTheme`。
  - **随机换肤按钮**:从 `TyBuiltinThemeNames` 随机取一个(≠当前)→设下拉选中 + `ApplyBuiltin`(只换主题,外观不变)。
  - **初始**:`FormCreate` 中 `TyRegisterBuiltinThemes`;主题 `default`、外观「跟随系统」(`Follow:=tfFollowSystem`)。
- `ApplyChromeTheme` 调用与现状一致(窗体背景/标题栏跟随 TyForm 令牌)。
- demo 不再从 `themes/` 加载内置主题(改用 ThemeName 内置 CSS);自定义/示例(green 照片、showcase)经「自定义…」文件对话框加载。

---

## 9. 涉及文件

- 新增：`source/tyControls.BuiltinThemes.pas`、`source/tyControls.BuiltinThemeData.pas`(生成)、`gen-builtinthemes.ps1`、`tests/test.builtinthemes.pas`。
- 改：`source/tyControls.ThemeRegistry.pas`、`source/tyControls.Controller.pas`、`tyControls.lpk`(加新单元)、`tests/tytests.lpr`(加测试单元)、`examples/demo/{mainform.pas,mainform.lfm,demo.lpi}`、文档(`docs/tycss-reference.md` 或新 `docs/themes.md` 列内置主题与用法)。
- 还原(非本次)：`examples/demo/{mainform.lfm,demo.lpi}` 的 DPI churn。

---

## 10. 测试

- 注册表：`TyRegisterThemeCss`/`TyResolveThemeCss` 往返;`TyThemeNames` 合并文件+CSS 源;`TyUnregisterTheme` 两边都删。
- BuiltinThemes：`TyBuiltinThemeNames` 返回 12 个含 system;`TyRegisterBuiltinThemes` 后 `TyThemeRegistered('dracula')` 等为真;每套主题 `LoadFromCss(TyBuiltinThemeCss(name))` 后,`@mode light`/`@mode dark` 下 `ResolveStyle('TyButton','primary',[])` 的背景 == 该模式拟定 accent;`on-accent` 派生为可读黑/白。
- gen sync：`TyBuiltinDualBaseCss`==auto.tycss、`TyBuiltinSystemCss`==system.tycss(规范化)。
- Controller：`ThemeName:='nord'` 后控件解析为 nord 调色板;`Mode:='dark'` 切深色;`ThemeName` 切换保持当前 Mode。
- 回归：现有 golden(`tests/golden`)不受影响(新主题不在 golden 网格;auto/system/light/dark 文件未改)。
- 真机手测(headless 不能点 OI/对话框)：demo 主题下拉、外观三态、随机、自定义换肤;一套 curated 在浅/深下观感正确。

---

## 11. 非目标 / 未来

- 不内置纯强调色 16 色色板(curated 取而代之;品牌色定制可由用户自定义主题或 StyleOverride 实现)。
- 不内置照片/毛玻璃主题(green/showcase 仅示例文件)。
- zip 主题包资源、`@import`/`extends` 组合主题:沿用现有 Bundle 能力,不在本次。
- 主题缩略图预览、主题热切换动画:未来可选。

## 12. 风险

- **配色保真**:curated 调色板需以官方色值定稿(计划阶段取色核对),否则「不像 Dracula」。深色 accent 对比度个别需微调(on() 兜底)。
- **demo .lfm**:DPI 重存反复;换肤控件放代码里规避,.lfm 仅删按钮。
- 部分主题官方无 light/dark 双版(Dracula→Alucard、Monokai→自拟浅色):用项目官方对应版,无则按种子派生一份得体的同族浅/深。
- `TyThemeNames` 合并顺序变化可能影响依赖顺序的测试:内置仅在显式 `TyRegisterBuiltinThemes` 后出现,现有测试不调用,不受影响。
