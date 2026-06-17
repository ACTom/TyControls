# TyControls 主题系统 v2 · 分层令牌 + 三层级联 + 单文件双模式 + 跟随系统 设计文档（程序总纲）

- **日期:** 2026-06-17
- **定位:** 一个**新的多阶段程序**（与"控件完善程序"同级）。把 `.tycss` 主题系统从"扁平令牌 + 加载即烘焙 + 三套手抄"升级为"**分层令牌 + 三层属性级联 + 单文件双模式 + 跟随系统明暗/强调色**"。
- **来源:** 一次 19-agent 审计 workflow（`tycss-theme-audit`，每条结论已逐条源码核验，verify 阶段纠正过若干数字）+ 与用户的多轮设计讨论。
- **协同约束（关键）:** 另一 session 正在**同一 `main` 工作树**有**未提交**改动：`source/tyControls.Base.pas`、`Painter.pas`、`StyleModel.pas`、`Types.pas`（窗体背景图 + 控件毛玻璃）。本程序的引擎代码与之**物理重叠**，须待其**提交**后再动。**本文档仅文档，不触碰那四个文件。**
- **执行约定:** 沿用项目惯例 —— PPI=96；`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe -a --format=plain`；现有测试保持全绿、不改既有测试语义；`examples/demo/*` 是用户测试台，每个任务只 stage 自己的文件。
- **分解约定:** 本文是**程序总纲**。每个阶段（Phase 0–5）后续各出一份独立的详细 spec → plan → 实现，本文只定方向、范围、顺序与依赖。

---

## 1. 审计核心发现（均已源码核验）

现状是一个**扁平、即时烘焙、单层**的样式系统，只有约 **1.5 层**令牌：

- `:root` 仅 10 个 var，混了 SEED（`--accent --surface --on-surface --border --danger --radius`）与少量 ALIAS（`--focus-ring --selection --muted --overlay-hover`）；**无 MAP 层、无 component 层**。
- 派生色（`darken/lighten(种子)`）**内联重复 109 次**；强调底墨色（on-accent）**硬编码 26 次**；disabled 透明度**每套主题重复 14 次**。
- 三套主题 **59% 行字节级完全相同**，light/dark 高达 **80% 相同**——只差调色板 + 明暗方向（`darken`↔`lighten`，且幅度被手调，如 hover 4% vs 8%）。`dark.tycss` 是 `light.tycss` 的 265 行手工镜像，零复用。
- **真 bug:** `dark.tycss` 的 on-accent 墨色自相矛盾——按钮/关闭/列表选中用近黑 `#0B1120`（L32/35/132/133/158），checkbox/radio/开关却用白 `#FFFFFF`（L69/82/175），背景同为 `var(--accent)`。复制粘贴漂移，非设计。
- **四个硬约束（核验）:**
  1. 第二次 `LoadFromCss/LoadFromFile` **整体替换**不叠加（`StyleModel.LoadInto` 先 `ClearList + AVars.Clear` 再装）。
  2. **无 `@import` / 继承**（parser 无 `@` token，`docs/tycss-reference.md` §9 确认）。
  3. 内置回退按 typeKey **全有或全无**（`StyleModel.pas:618` `UserHasTypeKey`，注释明确"单条匹配即整块抑制，是故意的"），**非**属性级联。
  4. 颜色在加载时**即时烘焙**成具体色（`TyApplyDeclaration`→`TyEvalColor`），改 seed 不会重派生。
- `source/tyControls.DefaultTheme.pas` 是编译进控件的 Pascal 副本，要求与 `themes/light.tycss` **一字不差**——一个维护陷阱。

---

## 2. 已锁定的设计决策

| # | 决策 | 关键理由 |
|---|---|---|
| **D1** | **分层令牌**：SEED → MAP → ALIAS →（可选）COMPONENT | 根治 59% 重复 + 109 处内联派生 |
| **D2** | **求值模型改为"先合并所有令牌层，再统一求值一次"**（替换"加载即烘焙"） | 单种子派生 / 双模式 / 叠加覆盖的天花板都在这 |
| **D3** | **三层属性级联**：内置基础 → 载入主题 → 控件级 override，统一用 `TyMergeStyleSet` 按属性合并 | 薄主题 + 实例微调 |
| **D4** | **"省略=继承，删除=显式空值"** 语义；每个属性都要有可表达的"空值" | 级联的必然权衡；需补 `transparent`/`none` |
| **D5** | **`elevate()` / `on()` / `luminance()`** 三个 mode-aware 函数 | 消灭明暗手翻 + 自动对比墨色（顺带根治 on-accent bug） |
| **D6** | **bundle 抽象**：目录 / zip 同接口，`url()`/`@import` 相对**主题根**解析 | 顺带修掉 CWD 解析 + 路径空格两个旧 bug |
| **D7** | **单文件双模式**（`@mode light/dark { :root{…} }` 条件令牌块） | 作者写一份、明暗通吃，连"切主题"都不存在 |
| **D8** | **跟随系统**：明暗（`--ty-mode`）+ 强调色（`system-accent`），含一个内置 "system" 主题 | 几乎全用已规划的零件拼成 |

---

## 3. 目标架构

### 3.1 三层属性级联（D3）
```
第0层  内置基础主题   （编译进控件，永远在，从不被整块抑制）         —— 完整默认外观
第1层  载入的主题     （文件/字符串，可 @import 另一主题 + 资源包）   —— 按属性盖第0层
第2层  控件级 override（控件自带的一小段 css，可含 var()）           —— 按属性盖该实例
```
三层统一走 `TyMergeStyleSet`（已是按属性合并）。第2层风险最低（最终层、单实例，不碰全局逻辑）；第0→1 层从"全有或全无"改成属性级联是**唯一动到既有刻意契约**的地方（见 §7 风险）。

### 3.2 令牌四层（D1）
- **SEED**（约 6–8 个旋钮）：`--accent --surface --on-surface --border --danger --radius --ty-mode`。recolor 应当只动这一层。
- **MAP**（命名派生阶梯，当前缺失）：`--surface-1/-2/-sunk`、`--border-hover`、`--accent-hover/-active`、`--danger-hover/-active`，由 `elevate()/lighten()/darken()` 在 `:root` 定义**一次**；明暗差异只活在这一层。
- **ALIAS**（语义意图）：`--disabled-opacity`、状态色 `--success/--warning/--info`、`--focus-ring/--selection/--muted/--overlay-hover`；`--on-accent` 多由 `on()` 取代。
- **COMPONENT**（可选）：`--input-bg`、`--control-padding`、`--radius-sm/md/lg`、字号/间距 scale。对接 memory 里挂着的**批⑤（spacing tokens）/ 批⑥**。

### 3.3 求值模型（D2，**地基**）
规则保留**原始表达式**，在"所有令牌层（base + @import + @mode 块 + override）合并完"后**统一求值一次**，替换 `StyleModel` 现在加载即烘焙的路径。这是单种子派生、双模式、叠加覆盖三者共同的前提——"加载即烘焙再叠加"做不到"改一个 seed、全族重派生"。

### 3.4 新函数 / 关键字（D5、D4）
- `luminance(色) → 0..1`（内部 helper，可不暴露）。
- `elevate(色, 步%)`：按 `--ty-mode`（缺省按 `luminance(色)`）选 `darken`(亮) / `lighten`(暗)。
- `on(背景) → 黑/白墨`：按背景亮度自动挑可读前景；**根治 on-accent bug、并使"换强调色"永远安全**。
- `transparent` / `none` 关键字：补齐 `background` 的"空值"缺口（其余属性 `border-width:0`、`border-style:none`、`outline:0`、`shadow` alpha 0、`opacity:1` 已可表达"空值"）。

### 3.5 单文件双模式（D7）
文件结构：共享 `:root{…}` + `@mode light{ :root{覆盖} }` + `@mode dark{ :root{覆盖} }`。加载时按当前 mode 合并对应块 → 再统一求值（复用 §3.3）。系统 mode 翻转时换另一块、重求值、重绘。需：lexer 加 `@` token、parser 加 at-rule、`LoadInto` 加 mode-aware 合并。

### 3.6 bundle / 打包 / 注册（D6）
- `ITyThemeSource`（目录实现 / zip 实现，FPC `zipper`），`url()`/`@import`/资源相对**主题根**解析。
- `theme.json` 清单：名/作者/版本/extends/双模式声明。
- 命名注册表：按名（+ 家族 + mode）注册，`Controller.ThemeName := 'ocean'` 切换。

### 3.7 跟随系统（D8）
- `tyControls.SystemTheme`（新单元）：探测明暗 `SystemColorScheme`、强调色 `SystemAccentColor`；Windows 优先（注册表 `AppsUseLightTheme` + DWM 强调色），macOS/Cocoa 次之，Linux 尽力，失败回 `tcsUnknown`。
- 实时跟随：捕获 `WM_SETTINGCHANGE`("ImmersiveColorSet") / `WM_DWMCOLORIZATIONCOLORCHANGED`，**复用 FormChrome/TTyForm 的 WndProc 钩子**；策略 `Light/Dark/FollowSystem`（手动覆盖永远优先）；变化时重求值 + 重绘。
- 内置 "system" 主题：双模式 + `--accent: system-accent` + 单种子派生 + `on()` 墨色 → 跟随系统明暗与强调色实时变化。
- 边角：无对应 mode 兄弟时 **原地不动**或回退内置；**不做亮→暗自动反相**（朴素反相必丑）。

### 3.8 主题切换语义：合成 vs 切换（防"残留上一个主题"）
两个长得像、必须分开的操作：
- **合成主题**（构建期）：`@import "base"` + 覆盖几条 → **叠加/合并**（`LoadInto AReplace=False`）。故意继承，是薄主题的根本。
- **切换当前主题**（运行期换肤 / 家族切换 / OS 跟随）：**整体替换第1层**（`LoadInto AReplace=True`，默认）。**绝不能用"在上一个主题之上叠加"实现切换**——那正是"残留上一个主题"的唯一来源。

**活动栈恒为：** `base(恒定垫底) → 当前主题(已合成，切换时整块替换) → 实例 override(用户数据，跨切换持久)`。切换只换中间层。

**由此的保证：** 主题没写的属性**回落到 base**（确定、作者可知），**永不回落到上一个主题**；`@import` 在合成时即解析，不是跨主题活引用。实例 override 跨切换持久，其 `var(--…)` 切换后自动按新主题重解析（是特性）。

**实现红线：** 切换 = 替换第1层 **＋ bump 主题版本 ＋ 失效解析缓存**（含 §4-A9 的 override 缓存键）。否则缓存里的旧样式才是真正的残留；`Controller.Changed` 已重刷控件，缓存按"主题版本"key 即可。

**作者注意：** 主题最终长相 = `base ⊕ 主题`；想"零 base 继承、全权自定" → 写 standalone/完整主题（重述全部，或用 `none/0/transparent` 显式删 base 项，见 D4）。

---

## 4. 范围清单（按子系统）

**A. 引擎 / 语言**（Lexer · Parser · Values · StyleModel · Controller）
1. 求值模型重构（D2，§3.3）。
2. 新函数 `luminance/elevate/on` + `transparent/none` 关键字（Values）。
3. `--ty-mode` 令牌驱动 elevate/on。
4. `@mode light/dark{ :root{} }` 条件块（lexer+parser+加载合并，D7 核心）。
5. `system-accent` / `system-mode` 动态值（令牌绑定 OS 状态）。
6. 叠加加载 `LoadInto(…; AReplace)` + 控制器 `LoadThemeCssAdditive`（默认 `AReplace=True`=替换=**换肤路径**；`False`=叠加=**仅用于合成**，见 §3.8）。
7. 属性级级联（改 `StyleModel.pas:618` `UserHasTypeKey` 的全抑制 → 按属性合并）。⚠️ 见 §7。
8. `@import "file"`（叠加 + bundle 资源解析之上的语法糖）。
9. 控件级 override：基控件加 `StyleOverride` 属性，按控制器变量表解析、作最终层合并，按（override + 主题版本）缓存。

**B. 令牌架构 / 主题内容**
10. 建 MAP 层。11. 建/补 ALIAS 层（含状态色）。12. 度量 scale 令牌（对接批⑤/批⑥）。
13. 抽出共享 `components.tycss`；内置基础从同一份源**嵌入生成**，干掉 `DefaultTheme.pas` 手抄副本。
14. light/dark 合并成单文件双模式。

**C. 打包 / 分发**
15. `ITyThemeSource`（目录/zip）。16. `theme.json` 清单。17. 命名注册表。

**D. 系统集成**
18. `tyControls.SystemTheme`（探测明暗 + 强调色）。19. 实时跟随（复用 WndProc 钩子）。20. 内置 "system" 主题。

**E. 关联项（背景图 / 修正 / DX）**
21. ~~`TTyFill` 增加图片填充模式 `cover/stretch/tile/center` + 控件透明~~ → **划归并行 session（窗体背景图 + 毛玻璃），本程序消费其成果，不重复造。**
22. 修正：on-accent bug（`on()` 白送修掉）、`--overlay-hover` 漂移、transparent 噪音、魔法数字度量（令牌化修掉）。
23. DX（高价值可选）：实时热重载（文件监视→重载→重绘）、严格/lint 模式（未知属性 / 未定义变量 / 缺资源 / 对比度告警）。

---

## 5. 阶段路线与依赖

```
阶段0  引擎地基：D2 合并后求值 + luminance/elevate/on/transparent + --ty-mode
         └─ 不解锁它，双模式/单种子/叠加/跟随 全都做不了；【依赖并行 session 先提交】
阶段1  令牌分层 + 重构内置三主题（纯 DRY/修正，渲染基本不变，每步可发）         依赖 0
阶段2  分层 & 授权：叠加加载 + @import + bundle(目录/zip) + 控件 override
        + 属性级联 + 注册表  →  交付"基于现有主题薄改 / 控件级覆盖 / zip 打包"   依赖 0,1
阶段3  单文件双模式（@mode 块）                                                依赖 0,1
阶段4  系统集成：SystemTheme + 实时跟随 + system 内置主题                       依赖 3 + FormChrome 的 WndProc 钩子
阶段5  收尾：（背景图模式由并行 session 提供后）热重载 + lint + 统一背景对接      依赖 2,4 + 并行 session
```

---

## 6. 与并行 session（背景图 + 毛玻璃）的协同

- 该 session 在**同一工作树**未提交改动 `Base/Painter/StyleModel/Types.pas`——正是本程序**阶段0（求值重构）**与**E21（TTyFill 图片模式）**的同一批文件。
- **顺序：让窄功能（背景图 + 毛玻璃）先提交，本程序的引擎代码 rebase 其上。** 大重构走第二，永远比反过来省事。
- **E21 划归对方**，本程序只消费（统一背景需要的 `--surface-*` 抬升令牌与 `transparent` 由本程序提供，反向利好对方）。
- **落地握手**：其提交后 diff `Types/Painter/StyleModel/Base`，确认新增 background 属性走通"先合并后求值"路径，再开阶段0。

---

## 7. 风险

1. **属性级联（A7）动到既有刻意契约**：`UserHasTypeKey` 全抑制是故意设计（如 `TyGroupBox` 需自控 background 遮标题处边框线）。改成"省略=继承"前，须排查哪些控件依赖"省略=删除"，避免内置属性意外漏出。建议带开关 / 后置。
2. **求值模型重构是宽改动**，且与并行 session 同区——靠 §6 的顺序与握手降风险。
3. **`elevate()` 感知不均匀**：现有 `TyDarken`(ch·(1−f)) 与 `TyLighten`(ch+(255−ch)·f) 不对称，naive 同步长翻方向**不能复现现有像素**。阶段3 采"保真路线"：方向由 `--ty-mode` 翻、**幅度由每模式 step 令牌**给，零像素变化；感知均匀（OkLab/HSL-L）留作可选打磨。
4. **Linux 明暗/强调色探测不可靠**（因桌面环境而异）：Windows 优先，`tcsUnknown` 兜底，探测失败绝不能让主题崩。
5. **加载即烘焙的遗留语义**：单种子派生要求"种子可见 → 再求值规则"，加载顺序错了会拿到旧值（§3.3 的重构正是解决它，但要测"载 light + 覆盖 --accent → TyButton.primary 取到新色"）。
6. **误用叠加做切换 / 缓存不按主题版本失效 → 残留上一个主题**：切换必须替换第1层 + bump 主题版本 + 失效缓存，叠加加载仅用于合成（见 §3.8）。要测"A→B 切换后，B 未声明的属性取 base 值而非 A 值"。

---

## 8. 待定 / 明确延后（YAGNI）

- CSS 式 `unset`/`revert`（让上层"假装没写"、透出下层）：显式空值已覆盖现实场景，**先不做**。
- 感知均匀 `elevate`（见风险3）：方向后置打磨。
- Linux 实时跟随：先做 Windows + macOS，Linux 仅一次性探测。
- `ListBox.Columns` 类大件：与本程序无关，归控件完善程序。

---

## 9. 验收原则

- **向后兼容**：新增 published/令牌/函数/加载 API 是叠加；现有主题与渲染在阶段0/1 保持**像素回归基线**（阶段3 双模式按"保真路线"亦不改像素）。
- **token 驱动硬规则**（用户既有铁律）：视觉值必须主题令牌驱动，绝不硬编码进控件代码；控件级 override 是**实例数据**且可写 `var(--…)`，不违反该规则。
- 现有测试全绿；新行为（如 `on()` 修复 on-accent bug）单独提交便于二分，并补测。
