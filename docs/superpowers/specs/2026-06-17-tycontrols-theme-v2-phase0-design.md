# TyControls 主题系统 v2 · 阶段0「引擎地基」设计文档

- **日期:** 2026-06-17
- **定位:** 总纲（`2026-06-17-tycontrols-theme-system-v2-design.md`）阶段0 的**详细 spec**。只做引擎地基；不动令牌分层（P1）、属性级联（P2·A7）、`@mode`（P3）、`@import`/bundle/override/注册表（P2）、系统集成（P4）。
- **依赖（已满足）:** 并行线「窗体背景图 + 控件毛玻璃」已提交并通过收尾对抗评审（`3d9d640` 起，含评审修复 `9ad87ff`、资源 `4f50870`；工作树仅余用户测试台 `demo.lpi`）。握手完成：新增 background/glass 属性全部经 `TyApplyDeclaration` 的 `TyEvalColor/TyEvalLength(…, Vars)` 求值，是令牌驱动的，可随 D2 自然延迟求值——本程序只消费、不重造（`TTyFill` 的 cover/stretch/center 归并行线）。
- **执行约定:** PPI=96；`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe --all --format=plain`；现有测试全绿、不改既有测试语义；`examples/demo/*` 是用户测试台；每任务只 stage 自己的文件。

---

## 1. 目标

把 `StyleModel` 的求值模型从**「加载即烘焙」**改为**「先合并所有令牌层、解析时统一求值一次」**（D2，总纲 §3.3），并新增 mode-aware 函数 `luminance/elevate/on` + `--ty-mode` + `transparent/none` 关键字（D5/D4）。**现有 light/dark/showcase 主题渲染像素零变化**——这是回归门。

不解锁 D2，双模式 / 单种子派生 / 叠加覆盖 / 跟随系统全做不了。

---

## 2. 范围

**做（阶段0）：**
1. merge-then-resolve 求值模型重构（规则条目改持原始声明；合并 vars；ResolveStyle 解析时按级联顺序逐条求值）。
2. `TyLuminance / TyElevate / TyOn` 函数 + `--ty-mode` 读取（`Css.Values`）。
3. `transparent`（颜色关键字）/ `none`（background 空值）关键字。
4. 握手：`MaxGlassBlur` 适配新条目结构。
5. 测试：像素基线 + 头号解锁测试 + 函数单测 + 关键字。

**不做（后续阶段，明确划界）：**
- 属性级联 / 改 `UserHasTypeKey` 全抑制（P2·A7，总纲风险1）——本阶段**保留**全有或全无语义不动。
- `@mode` 条件块（P3）、`@import`/bundle/控件级 override/注册表（P2）。
- 令牌分层 + 重构内置主题（P1）——现有主题继续用 `darken/lighten`，故像素不动；`elevate/on/--ty-mode` 本阶段**加而未用**（P1 才接入主题）。
- **解析结果缓存（P2）**——已与用户确认：本阶段不缓存，每次 resolve 求值一次、永远新鲜，零「残留上一个主题」风险（总纲 §3.8/§6 风险6 的失败面在切换出现，本阶段尚无运行期切换）。

---

## 3. 现状（源码逐条核验）

- **烘焙点是单一函数：** `TyApplyDeclaration`（`StyleModel.pas:436`）在 `LoadInto`（`:663`）内对每条声明即时求值——`TyEvalColor/TyEvalLength/TyEvalFloat`（`Css.Values.pas:195/262/277`）把 `var()`+`darken/lighten/alpha/mix/rgb` 折叠成具体值，写进 `TTyStyleRuleEntry.Style`（`TTyStyleSet`，已烘焙）。
- **求值机已是 `Vars` 参数化、调用时递归解析**（含 `var`-on-`var`：`ResolveVarRef` 返回原始串，`TyEvalColor` 再递归）。**唯一问题是调用时机在加载**，对的是该层的 `:root`。
- `ResolveStyle`（`:811`）只合并**已烘焙**的 `Style`（`TyMergeStyleSet`），按 `UserHasTypeKey`（`:618`）**全有或全无**叠 base/user 两层。`ResolveLayer`（`:761`）按 type→variants→states 固定序合并。
- **数据模型已具空值：** `TTyFillKind.tfkNone` 与 `tyTransparent ($00000000)`（`Types.pas:16/71`）已存在——`transparent/none` 只缺**解析**，不缺表示。
- 条目结构：`TTyStyleRuleEntry = class { TypeName, Variant, HasState, State, Style: TTyStyleSet }`；声明记录 `TTyCssDeclaration = record Prop, RawValue: string end`（`Css.Parser.pas`），`TTyCssRule.Declarations: array of TTyCssDeclaration`。

---

## 4. 设计

### 4.1 规则条目改持原始声明

`TTyStyleRuleEntry.Style: TTyStyleSet` → **`Decls: array of TTyCssDeclaration`**（直接复用 parser 的 `(Prop, RawValue)` 记录）。

- `AddEntryTo` 签名 `const AStyle: TTyStyleSet` → `const ADecls: array of TTyCssDeclaration`。
- `LoadInto` **不再调 `TyApplyDeclaration`**；直接把 `rule.Declarations` 存进条目（`tmpVars` 仍收集 `:root`，但不再在 load 求值规则值）。
- `FindStyleIn` 返回命中条目（供其 `Decls` 被应用），而非已烘焙 `Style`。

### 4.2 合并令牌层（加载期一次，非每帧）

新增 `FMergedVars: TStringList := FBaseVars ⊕ FVars`（user 同名覆盖 base），在 `Create`（载内置后）与每次 `LoadInto`/`Clear` 后**重建一次**。

- `var`-on-`var` 派生（如 `--surface-1: darken(var(--surface), 4%)`）由 `TyEvalColor` 在 resolve 时递归解析 → **改一个 seed，全族重派生**（这正是 D2 解锁的天花板）。
- 说明：这**不是**用户否决的「解析结果缓存」。`FMergedVars` 是**令牌层的加载期准备**，随加载失效；缓存的是 `TTyStyleSet` 解析结果，那个本阶段不做。

### 4.3 `ResolveStyle` 解析时按级联顺序逐条求值

**级联顺序完全不变**（`!UserHasTypeKey(typeKey)` ? 走 base 层 : 跳过 → 再走 user 层；层内：type 基规则 → 各 variant → 各 state 固定序）。把所有命中条目的 `Decls` **按该序收集**，逐条 `TyApplyDeclaration(result, prop, raw, FMergedVars)` 应用到一个 `result: TTyStyleSet`。

- `ResolveLayer` 由「合并烘焙 `Style`」改为「把命中条目的 `Decls` **按序应用**到传入的 `result`」（签名加 `var AResult: TTyStyleSet; AVars: TStrings`）。
- **等价性证明（保证像素零变化）：** 「烘焙每条规则 → 再 `TyMergeStyleSet` 按序合并」 ≡ 「把全部命中声明**按同序**逐条应用到一个 styleset」。因为 `TyApplyDeclaration` 是**按字段覆盖**、且 shorthand 两路展开一致：`border:1px solid blue` 后 `border-color:red`，烘焙-合并得 `{w=1,st=solid,c=red}`，按序应用同样得 `{w=1,st=solid,c=red}`。命中集合与顺序不变 ⇒ 结果逐字段相同。
- **D2 解锁 + 头号测试：** 载 thin `:root{--accent:#FF0000}`（无 `TyButton` 规则）→ `!UserHasTypeKey('TyButton')` → base `TyButton.primary` 的 `background: var(--accent)` 对 **merged accent** 求值 = **红**。烘焙模型里 base 规则用内置 accent → 给内置色。**两模型由此测试区分。**

### 4.4 新函数（均落在 `Css.Values`，对 `TyEvalColor` 分发是叠加）

- `function TyLuminance(c: TTyColor): Single`（0..1）。**Rec.601 感知亮度** `0.299·R + 0.587·G + 0.114·B`（**非** WCAG 线性）。选感知亮度是为匹配「饱和色上用白字」的设计惯例：`on(#3B82F6)`/`on(accent)` 给白墨（WCAG 最大对比反而给黑墨、与现有主题/惯例相悖）。
- `function TyElevate(c: TTyColor; Pct: Single; const Mode: string): TTyColor`：`Mode='light'`→`TyDarken`；`'dark'`→`TyLighten`；`''`（缺省）→ 按 `TyLuminance(c)`（亮色 darken / 暗色 lighten）。**方向匹配现有约定**（light 用 darken、dark 用 lighten 做抬升/下沉面）→ 落总纲风险3 的「保真路线」：方向由 mode 翻、幅度由显式步长给，零像素漂移；感知均匀（OkLab）留 P1/P3 可选打磨。
- `function TyOn(bg: TTyColor): TTyColor` + 重载 `TyOn(bg, inkOnLight, inkOnDark: TTyColor)`：按 `TyLuminance(bg)` 阈 **0.5** 挑 `#000`（亮底）/`#FFF`（暗底）；带参时 bg 偏亮取 `inkOnLight`、偏暗取 `inkOnDark`。**根治 on-accent bug**（`on(var(--accent))` 一致可读），并使「换强调色」永远安全。
- `TyEvalColor` 分发新增 `elevate`(2 参) / `on`(1 或 3 参)。**只有 `elevate` 读 `--ty-mode`**（经 `Vars.Values['ty-mode']`，空→按 `luminance(c)` 兜底定方向）；**`on` 不读 mode**，纯按 `luminance(bg)` 自挑墨。`transparent` 关键字（颜色处任意位置）→ `tyTransparent`。
- `background: none` → `tfkNone`：在 `TyApplyDeclaration` 的 `background` 分支识别（`Default(TTyFill)` + `Kind:=tfkNone`，置 `tpBackground`）。

### 4.5 `--ty-mode`

SEED 令牌 `--ty-mode`（`light`/`dark`），由 `elevate` 经 `FMergedVars` 读取定方向（`on` 不依赖 mode，按 `luminance(bg)` 挑墨）。**本阶段仅引擎能读**；内置/现有主题**暂不设** `--ty-mode`、暂不改用 `elevate/on`（保持像素基线）；P1 接入主题、P3 接 `@mode` 翻转。

### 4.6 握手：`MaxGlassBlur` 适配（消费并行线）

`MaxGlassBlur`（`:716`）原读烘焙 `e.Style.Background.GlassBlur`。改为：遍历条目 `Decls`，对 `prop='glass-blur'` 的声明 `TyEvalLength(raw, FMergedVars)` 取最大（base 层仍按 `UserHasTypeKey` 跳过用户已定义 typeKey，语义不变）。

### 4.7 错误时机（重要）

求值从 load 移到 resolve ⇒ 坏值（未定义 `var`、坏表达式）原本在 `LoadFromCss` 抛、现在会在**绘制路径**抛。处理：

- **保留 load 期校验**：`LoadInto` 存完原始声明后，对每条做**一次**校验性求值（对 `FMergedVars`，捕获并带上下文 re-raise）——**坏 CSS 仍在加载期 fail-fast**，保住现有「载入坏主题即抛」的行为与相关测试。
- 本阶段 vars 加载后静态（无运行期 override，那是 P2）⇒ load 校验通过即 resolve 必通过，resolve 路径无需 try/except。
- P2 引入运行期 override（可注入运行期坏 vars）时，再加 resolve 容错（跳过坏属性 + log，不崩绘制）。

---

## 5. 数据 / API 变更清单（全部叠加，向后兼容）

| 变更 | 文件 | 兼容性 |
|---|---|---|
| `TTyStyleRuleEntry.Style` → `Decls: array of TTyCssDeclaration` | StyleModel | 内部类型，无外部引用 |
| `AddEntryTo` 形参 | StyleModel | 私有方法 |
| `LoadInto` 不再烘焙 + load 校验 | StyleModel | 行为等价（+ 解锁 merged-vars） |
| 新增 `FMergedVars` + 重建逻辑 | StyleModel | 新增私有字段 |
| `ResolveLayer/ResolveStyle` 改按声明求值 | StyleModel | **签名对外不变**：`ResolveStyle(typeKey,class,states): TTyStyleSet` 不变 |
| `MaxGlassBlur` 适配 | StyleModel | 返回值语义不变 |
| 新增 `TyLuminance/TyElevate/TyOn`（exported） | Css.Values | 纯新增 |
| `TyEvalColor` 识别 `transparent/elevate/on` | Css.Values | 纯新增分支 |
| `TyApplyDeclaration` 识别 `background:none` | StyleModel | 纯新增分支 |

**无 published 属性 / 外部加载 API 破坏。** 控件侧零改动（仍 `CurrentStyle`→`ResolveStyle`→`TTyStyleSet`）。

---

## 6. 测试计划

1. **像素基线（回归门）：** 现有 `test.defaulttheme` 与各控件 pixel 测试**保持全绿、零语义改动**——这是 merge-then-resolve 等价性的证据。
2. **头号解锁测试（新）：** `LoadFromCss(':root{ --accent:#FF0000; }')` → `ResolveStyle('TyButton','primary',[]).Background.Color` = 红（base 规则吃 merged seed；烘焙模型会失败，正是要测的区分点）。
3. **merge-then-resolve 正确性（新）：** 载 light → 抽样若干 typeKey/state 的解析色与烘焙基线逐一相等。
4. **函数单测（新）：** `TyLuminance` 黑/白/中灰边界；`TyElevate` light→darken、dark→lighten、缺省按 luminance 方向；`TyOn` 双模式可读 + 自定义墨 + **on-accent bug 回归**（`on` 在亮/暗 accent 上都给可读墨）。
5. **关键字（新）：** `background: transparent`→alpha0 / `background: none`→`tfkNone`；`border-color: transparent`。
6. **握手：** green 主题 `MaxGlassBlur` 仍 = 16；green 渲染（headless 下玻璃路径 inert）不回归。
7. **load 校验：** 坏 CSS（未定义 var）仍在 `LoadFromCss` 抛（保住现有语义）。

---

## 7. 风险与缓解

1. **级联顺序复现** —— §4.3 等价性证明 + 像素基线门（测试1）双重保。
2. **`MaxGlassBlur` 适配** —— 小、被测（测试6）。
3. **全主题无行为变化** —— 现有 light/dark/showcase 是**完整主题**（`DefaultTheme.pas` 即 light 的 Pascal 副本，typeKey 集合一致），每个 typeKey 都 user-defined → base 永不漏出 → 「base 规则吃 merged vars」只影响 **partial 主题**（= 本阶段要解锁的新能力），故完整主题零变化。**子风险:** 若某既有测试恰好测了「base 忽略 user seed」这一旧量子（载 partial CSS + 覆盖某 seed + 断言一个**未被覆盖的** typeKey 的 base 色），merge-then-resolve 会**合理地**改变其结果——届时**上报用户、按新能力更新该测试**，而非静默改语义或退回旧模型。实现时逐一排查这类测试。
4. **每帧求值成本（无缓存）** —— 与今日「每帧重跑 `ResolveStyle` 级联」同阶（今日也无缓存）；新增的是每色属性一次 `TyEvalColor` 字符串求值。若 profile 显示绘制抖动，P2 随 override 缓存一并加（已与用户确认延后）。
5. **错误时机迁移** —— §4.7：load 校验保 fail-fast；本阶段 vars 静态 ⇒ resolve 不会新抛。

---

## 8. 验收标准

- `lazbuild tyControls.lpk`、`tests/tytests.lpi`、`examples/demo/demo.lpi` 全过；`tytests.exe` 现有测试全绿（已知 11 环境错误不变），新测试通过。
- 现有三主题**像素基线不变**（测试1）。
- 头号解锁测试通过（测试2）——证明已离开「加载即烘焙」。
- demo 仍正常显示（Green 玻璃不回归）。
- 每个逻辑改动单独可二分提交（求值重构 / 函数 / 关键字 / MaxGlassBlur 分开），新行为附测。

---

## 9. 明确延后（YAGNI / 后续阶段）

- 解析结果缓存 + 切换失效纪律 → **P2**（随控件级 override）。
- 属性级联（改 `UserHasTypeKey`）→ **P2·A7**。
- `elevate/on/--ty-mode` 接入内置/现有主题、令牌分层 → **P1**。
- `@mode` 双模式、`@import`、bundle、注册表 → **P2/P3**。
- 感知均匀 elevate（OkLab）、resolve 期容错 → 后置打磨。
