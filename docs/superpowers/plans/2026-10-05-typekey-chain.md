# typeKey 链（#14）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：任务连续写完，每个任务单独提交；任务之间不编译。Task 1 写测试与实现，Task 2 lint / 补全，Task 3 文档；Task 4 **一次编译**、跑相关 suite 与全量、集中修红、集中变异、性能对比、签收。中途不汇报、不问要不要提交。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent 不做：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编 `examples/`、GUI 冒烟、改 CHANGELOG、合 `main`。

**Goal:** 控件子类报自己的 typeKey（如 `TagButton`）时，能声明它的父 typeKey（`TyButton`），引擎先按父 typeKey 完整解析，再用子 typeKey 自己的规则逐属性覆盖；主题没写子 typeKey 时它和父一模一样。没声明链的 typeKey 行为逐字节不变。

**Architecture:** `StyleModel.pas` 里加一张**进程级 typeKey 父链登记表**（`TyRegisterTypeKeyParent('TagButton', 'TyButton')`，第三方在自己单元的 `initialization` 里登记）。`ResolveStyle` 在缓存未命中时从登记表取出整条链 `[TagButton, TyButton]`，从根到叶依次做「现在对单个 typeKey 做的那两步」（底层 + 用户层，各含变体、状态）。缓存的有效性多看一个登记表戳记。`GetVariantsForType` 与 StyleOverride 编辑器的补全跟着链走。`Base.pas` 不改。

**Tech Stack:** FPC 3.2.2 / Lazarus（最低 3.0）、fpcunit（`tests/tytests.lpi`）。

**设计依据：** GitHub issue #14 正文；主控 brief（2026-10-05，含「用户已同意改 `StyleModel.pas`」）。

**工作树：** `D:/Projects/ty-typekey`，分支 `feat/typekey-chain`，起点 `main` @ `140496e6`。

**不在本计划**：CHANGELOG（发版时写）；`designtime/` 里 StyleOverride 编辑器的参考面板（直接读 `TyCatalogTypeKeys`，见 §5）；主题编辑器（theme builder，未立项、仓库里没有）；合 `main`。

---

## 1. 核实记录

对照 brief 里的假设逐条查了代码（行号是 `140496e6`）：

| # | 假设 / 问题 | 实际 | 影响 |
|---|---|---|---|
| V1 | 控件只经 `CurrentStyle` 解析自己 | **不是**。`Base.pas:794/1942` 的 `CurrentStyle` 之外，有 30 处直接 `Model.ResolveStyle(GetStyleTypeKey, …)`（如 `Button.pas:702-703` 的悬停渐变两端、`ButtonGroup`、`Steps`、`Terminal`、`ToolWindows`），另有 16 处 `GetStyleTypeKey + 'Fill'` / `'Pointer'` 等子部件键，还有父容器经 `ITyStyleable` 取子控件 / 自己的键去解析背景 | 「控件实例报链、调用点把链传给模型」要改 30+ 个调用点，漏一处就是一块没样式的像素（本项目最常见的故障：建好没接线）。见 D1 |
| V2 | lint（brief 里叫 `TyLintCssEx`）会对第三方 typeKey 报「未知 typeKey」 | **没有这个检查**，也没有 `TyLintCssEx`。`ThemeLint.pas` 只报四类：未知属性、未定义变量、缺资源、低对比度。第三方 typeKey 今天就不报任何东西 | 不需要「降级为提示」。也**不新加**未知 typeKey 检查：见 D6 |
| V3 | 有一份「所有合法 typeKey」可供 lint 对照 | `Css.Catalog.TyCatalogTypeKeys` 是 `light.tycss` **写过规则的**键（253 个），不是「代码会解析的键」。仓库里别的主题用到 9 个它没有的键（`TyGridPanelCell`、`TyListViewLine`、`TyValueListEditorKey` 等，§8.4 里的刻意不定义键） | 用目录判「未知 typeKey」会对现有主题误报 |
| V4 | 「主题编辑器的覆盖检查、Ctrl+点击」 | 仓库里**没有**主题编辑器（记忆：待立项），也没有 Ctrl+点击。现有的相近物是 StyleOverride 编辑器：补全逻辑在 `source/tyControls.Css.Complete.pas`（运行时单元，可测），参考面板在 `designtime/tyControls.Design.Css.Editor.pas:166` | 补全跟链走（Task 2）；登记表提供查询函数给以后的主题编辑器用；设计期参考面板不动（本任务不编 dt 包） |
| V5 | 解析是纯函数、有缓存 | `ResolveStyle` 以 `typeKey|styleClass|states` 为键、以 `FVersion` 为锚记忆；`ResolveMetric` 共用同一个锚 | 登记表是进程级的，改登记表碰不到各个模型的 `FVersion`，所以锚里加一个全局戳记（D4） |
| V6 | `UserHasTypeKey` 让位规则 | 用户层有该键「无变体、无状态」的规则 → 该键的底层**整个**跳过（`PropertyCascade` 关时）；只按键名判 | 链上每个键各判各的（D3） |
| V7 | 像素 golden | `tests/golden/{light,dark,showcase}.golden.txt` 是逐键解析结果的文本快照（`test.themes`）；不登记链时它们必须一字不变 | 回归判据 |
| V8 | `GetStyleTypeKey` 的可见性 | 两个基类上 `protected virtual abstract`；Custom 类覆写 | 第三方覆写它报新键，不需要任何新接口 |

## 2. 设计

### D1 链怎么报：按 typeKey 登记，而不是按控件实例报

```pascal
{ StyleModel.pas interface }
procedure TyRegisterTypeKeyParent(const ATypeKey, AParentKey: string);
procedure TyUnregisterTypeKeyParent(const ATypeKey: string);
function TyTypeKeyParent(const ATypeKey: string): string;          // '' = 没登记
function TyTypeKeyChain(const ATypeKey: string): TStringArray;     // [自己, 父, 祖父, …]
procedure TyGetRegisteredTypeKeys(AList: TStrings);                // 登记过的子键
const
  TyMaxTypeKeyChain = 8;   // 一条链最多 8 个键（含自己）
```

第三方：

```pascal
initialization
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
finalization
  TyUnregisterTypeKeyParent('TagButton');
```

**与 brief 建议做法的差别和理由**（brief 建议「可选接口 `ITyStyleableChain` 或基类默认返回空的虚方法」）：

1. **调用点**（V1）。按实例报链，30+ 处 `ResolveStyle(GetStyleTypeKey, …)`、子部件键、父容器取键都得改成传链；漏一处，比如按钮悬停渐变的两端，子类一悬停背景就渐变到空。按 typeKey 登记，**所有**走 `ResolveStyle` 的路径自动跟链，一处不用改，`Base.pas` 也不用改。
2. **没有控件实例的地方也要知道链**：lint、补全、以后的主题编辑器只有 tycss 文本，没有控件。登记表是它们唯一能问的地方。
3. **链是 typeKey 的属性，不是类的属性**：两个类报同一个 typeKey 却声明不同的父键，主题就有歧义；登记表把它挡在登记时（重复登记不同父键抛异常）。
4. **多级链**：实例上一个「父键」虚方法表达不了「孙 → 子 → 父」（孙覆写后，子那一级的父键就丢了，除非返回整条数组）；登记表天然逐级。

不报链的控件（= 没登记的 typeKey）走的仍是原来那两步，结果逐字节一致。`ITyStyleable` 不变，第三方实现者不受影响，**没有不兼容**。

**子部件键**（`GetStyleTypeKey + 'Fill'`）：要继承也得登记（`TyRegisterTypeKeyParent('TagMeterFill', 'TyMeterFill')`），文档写明。

### D2 解析语义（照 brief）

链 `[C, P, G]`（叶在前）。缓存未命中时：

```
for k in [G, P, C]（从根到叶）:
    if PropertyCascade or not UserHasTypeKey(k): ResolveLayer(底层, k)   // 含变体、状态
    ResolveLayer(用户层, k)                                             // 含变体、状态
```

即「先按父 typeKey 完整解析，再用子 typeKey 自己的规则逐属性覆盖」。链长 1 时就是今天的两行。主题里没有 `C` 的规则时，`C` 那一轮什么都不写，结果和 `P` 完全相同。

**一个要主控看的后果**：子键的**普通**规则排在父键的**状态**规则之后，所以

```css
TyButton:hover { background: #E5E7EB; }
TagButton      { background: #DCFCE7; }
```

悬停的 `TagButton` 是绿的（子键胜），父键的 `:hover` 背景被盖掉；`:disabled` 同理。写了子键某属性，就要把需要的状态也为子键写上。浏览器 CSS 在这里的结果相反（`.btn:hover` 的特异度高于 `.tag`）。备选是「按阶段交错」（父基础、子基础、父变体、子变体、父各状态、子各状态），它让父的 `:hover` / `:disabled` 继续生效，但与 brief 和 issue 正文「先父后子」的表述不同。本计划按 brief 实现，文档写明，并在 `TestChildBaseRuleBeatsParentState` 里钉住；改成交错只动 `ResolveStyle` 里一个循环，主控裁决后再改。

### D3 `UserHasTypeKey` 让位

链上每个键**各判各的**：用户层有 `TagButton {…}`（无变体无状态）只让 `TagButton` 自己的底层规则让位，`TyButton` 的底层照常；用户层有 `TyButton {…}` 只让 `TyButton` 的底层让位。第三方键在内置底层里本来没有规则，所以对它们实际没有区别；区别只在把内置键登记成子键时（测试就用这个场景钉住）。

### D4 缓存

键仍是 `typeKey|styleClass|states`；有效条件从 `FCacheVer = FVersion` 变成 `FCacheVer = FVersion` **且** `FCacheChainStamp = GTypeKeyChainStamp`。每次登记 / 撤销都 `Inc(GTypeKeyChainStamp)`，所有模型下一次查缓存时整体失效重建。效果等同于「缓存键含整条链」（brief 的要求），但热路径只多一次整数比较，不用每次拼链。`ResolveMetric` 共用这个锚（度量不依赖链，多失效一次无害）。

登记应在 `initialization` 里完成（控件创建之前）；运行中登记不会通知已画好的控件重画——文档写明。

### D5 限深与成环

- 键名必须是标识符（字母或 `_` 开头，后跟字母、数字、`_`、`-`），否则 `ETyCssError`。
- 父键等于自己、或从父键往上走能走回自己 → `ETyCssError`（成环），登记表不变。
- 登记后任何一个已登记键的链超过 `TyMaxTypeKeyChain`（8）个键 → 撤回这次登记，`ETyCssError`（过深）。
- 同一子键再登记**同一个**父键：无操作（不抛、不动戳记）；登记**不同**父键：`ETyCssError`（冲突）。要改先撤销。
- 键名不分大小写（与规则匹配的 `SameText` 一致）。
- `TyTypeKeyChain` 自己也最多走 8 步，登记表万一被绕过也不会死循环。

### D6 lint

不改 `ThemeLint.pas`。V2：它本来就不查 typeKey，第三方键（登记与否）都不报。不新加「未知 typeKey」检查（V3：没有一份可靠的合法键全集，加了会对现有主题误报；它也不是 #14 的范围）。加一条测试钉住「链上的子键不产生任何 lint 警告」，以后谁给 lint 加 typeKey 检查，这条会提醒他认登记表。

### D7 补全

`TyCssCompletionItems` 的选择器模式在目录键之后追加登记过的子键（去掉与目录重名的）。

### D8 `GetVariantsForType`

沿链从根到叶收集变体：`TagButton` 的 StyleClass 下拉列出 `primary` / `danger` / `ghost`（它们经父键真的生效）。未登记的键结果不变。

## 3. 文件

| 文件 | 改什么 |
|---|---|
| `source/tyControls.StyleModel.pas` | 登记表与五个函数；`ResolveStyle` 沿链；缓存锚加戳记；`GetVariantsForType` 沿链 |
| `source/tyControls.StrConsts.pas` | 4 条 `rsSmTypeKey*` 错误文字 |
| `languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po` | 同步 4 条 |
| `source/tyControls.Css.Complete.pas` | 补全追加登记键 |
| `tests/test.typekeychain.pas`（新） | 全部新测试 |
| `tests/test.themelint.pas` | 1 条 lint 测试 |
| `tests/tytests.lpr` | uses 加 `test.typekeychain` |
| `docs/tycss-reference.md` / `.en.md` | 新增 §4.5 typeKey 链；开头「覆盖语义」一段加一句指路 |
| `docs/subclassing.md` / `.en.md` | 第 2 节改写 |

## 4. 任务

### Task 1：登记表、沿链解析（测试先行）

**Files:** `tests/test.typekeychain.pas`（新）、`tests/tytests.lpr`、`source/tyControls.StyleModel.pas`、`source/tyControls.StrConsts.pas`、两个语言文件。

- [ ] **Step 1：写测试**（`TTypeKeyChainTest`，`SetUp` / `TearDown` 撤销本测试登记过的全部键，保证不污染别的 suite）。下表每条都写明「在哪个变异下必须红」（§6 的编号）。

| 测试 | 断言 | 必须红于 |
|---|---|---|
| `TestUnregisteredKeyGetsNothing` | 没登记的 `TagButton`，`Present = []` | —（钉现状） |
| `TestChainWithoutChildRulesEqualsParent` | 登记后，`TagButton` 在 `''`/`primary`/`ghost` × `[tysNormal]`/`[tysHover]`/`[tysDisabled]`/`[tysSelected,tysHover]` 下与 `TyButton` 的逐字段转储相同 | M1 |
| `TestChildRuleOverridesOnlyItsProperties` | 用户层 `TagButton { border-color: #FF0000 }`：`TagButton` 的边框色是红，其余字段与 `TyButton` 相同；`TyButton` 自己不变 | M1、M2 |
| `TestChildVariantAndStateRules` | `TagButton.primary:hover { color: #00FF00 }` 只在 primary+hover 生效 | M1 |
| `TestChildBaseRuleBeatsParentState` | `TyButton:hover{background:#0000FF} TagButton{background:#00FF00}`：悬停的 `TagButton` 背景绿（D2 钉住） | M2 |
| `TestPlainChildRuleYieldsOnlyChildBase` | 把内置键 `TyTag` 登记为 `TyButton` 的子键；用户层 `TyTag { color: #123456 }`：背景等于 `TyButton` 的底层背景（父底层没让位），不是 `TyTag` 的底层背景（子底层让位了）；颜色 `#123456` | M3 |
| `TestThreeLevelChain` | `FancyTag → TagButton → TyButton`，三层规则逐级覆盖；`TyTypeKeyChain('FancyTag')` = 三个键 | M1、M2 |
| `TestCycleRaisesAndLeavesRegistryIntact` | `A→B` 后登记 `B→A` 抛 `ETyCssError`，消息含 `cycle`；`B` 没登记上；`ResolveStyle('A')` 正常返回 | M5 |
| `TestSelfParentRaises` | `A→A` 抛 | M5 |
| `TestTooDeepRaises` | 8 个键的链能登记；第 9 个抛，消息含 `deep`；在中间接一段使已有后代超深也抛，并撤回 | M6 |
| `TestConflictingParentRaises` | 同父重复登记无操作；换父抛，原父键还在 | M7 |
| `TestInvalidNamesRaise` | `''`、`'1x'`、`'a b'` 抛 | M12 |
| `TestCacheFollowsRegistration` | 先解析 `TagButton`（空，进缓存）→ 登记 → 再解析等于 `TyButton` → 撤销 → 再解析为空 | M4、M11 |
| `TestCaseInsensitiveChain` | 登记 `TagButton`，解析 `tagbutton` 也跟链 | M10 |
| `TestNoChainIsByteIdentical` | 登记 20 个无关子键前后，目录里每个键在 4 组 (class, states) 下的转储相同 | M8b |
| `TestPropertyCascadeFollowsChain` | `PropertyCascade := True` 时，用户层 `TagButton { color }` 之外的属性仍来自 `TyButton` 底层 | M1 |
| `TestVariantsFollowChain` | `GetVariantsForType('TagButton')` 含 `primary`、`danger`、`ghost`；没登记时为空 | M8 |
| `TestTagButtonRendersLikeButton`（端到端） | 第三方子类 `TTestTagButton = class(TTyCustomButton)` 报 `TagButton`，登记到 `TyButton`；独立控制器、内置主题，`RenderTo` 到黑底位图，与 `TTyButton` 逐像素相同 | M1 |
| `TestUnregisteredTagButtonRendersBare` | 不登记：与按钮像素不同（证明上一条有区分力） | — |
| `TestTagButtonRuleChangesOnlyThatProperty`（端到端） | 主题 `TagButton { border-color: #FF0000; }`：`TagButton` 的像素 = 带 `StyleOverride := 'border-color: #FF0000;'` 的 `TTyButton`，且 ≠ 普通按钮 | M1、M2 |

- [ ] **Step 2：StrConsts + 语言文件**

```pascal
  rsSmTypeKeyInvalidName = 'Invalid type key name: "%s"';
  rsSmTypeKeyCycle       = 'Type key chain cycle: "%s" -> "%s"';
  rsSmTypeKeyTooDeep     = 'Type key chain too deep (> %d keys) at "%s"';
  rsSmTypeKeyConflict    = 'Type key "%s" already has parent "%s" (not "%s")';
```

`.pot` 加四条空 msgstr；`zh_CN.po` 译为「无效的 typeKey 名：\"%s\"」「typeKey 链成环：\"%s\" -> \"%s\"」「typeKey 链过深（超过 %d 个键），位于 \"%s\"」「typeKey \"%s\" 已登记父键 \"%s\"（不是 \"%s\"）」。

- [ ] **Step 3：实现**（`StyleModel.pas`）

接口段加 D1 的五个函数与常量。实现段：

```pascal
var
  GTypeKeyParents: TStringList = nil;   // 'child=parent'; names compared case-insensitively
  GTypeKeyChainStamp: Cardinal = 0;     // bumped on every (un)registration; part of the memo anchor

function IsTypeKeyName(const S: string): Boolean;   // letter/_ then letters, digits, _ and -
function TyTypeKeyParent(const ATypeKey: string): string;      // IndexOfName on the list
function TyTypeKeyChain(const ATypeKey: string): TStringArray; // walks parents, <= TyMaxTypeKeyChain keys
procedure TyRegisterTypeKeyParent(const ATypeKey, AParentKey: string);
  // validate names; same link -> Exit; other parent -> rsSmTypeKeyConflict;
  // walk up from AParentKey, meeting ATypeKey -> rsSmTypeKeyCycle;
  // Add; any registered key whose chain exceeds TyMaxTypeKeyChain -> Delete + rsSmTypeKeyTooDeep;
  // Inc(GTypeKeyChainStamp)
procedure TyUnregisterTypeKeyParent(const ATypeKey: string);   // Delete + Inc stamp (no-op if absent)
```

`TTyStyleModel`：新字段 `FCacheChainStamp: Cardinal`；新私有方法 `CacheCurrent: Boolean`（三条件）、`ReanchorCache`（失效 + 记下 `FVersion` 与戳记）、`ResolveTypeKeyInto(const AKey, AStyleClass; AStates; var AResult)`（原来的两行）。`ResolveStyle` / `ResolveMetric` 改用 `CacheCurrent` / `ReanchorCache`；`ResolveStyle` 主体：

```pascal
    chain := TyTypeKeyChain(ATypeKey);          // [ATypeKey] when nothing is registered
    for ci := High(chain) downto 0 do           // root first, the leaf's own rules last
      ResolveTypeKeyInto(chain[ci], AStyleClass, AStates, Result);
```

`GetVariantsForType` 同样沿链从根到叶扫两层。`finalization` 释放登记表。

- [ ] **Step 4：提交** `feat(style): type key chain — a subclass key inherits its parent's rules`，正文 `Refs #14`。

### Task 2：补全、lint 测试

- [ ] `Css.Complete.pas` 选择器模式：`AddAll(TyCatalogTypeKeys)` 之后调 `TyGetRegisteredTypeKeys` 追加不在目录里的键。
- [ ] `test.typekeychain`：`TestCompletionOffersRegisteredKeys`（登记后有 `TagButton`，撤销后没有）——M9 下必须红。
- [ ] `test.themelint`：`TestChainKeyLintsClean`（`TagButton { … }` 与 `TagButton.primary:hover { … }`，登记与否都 0 条警告）。
- [ ] 提交 `feat(css): completion offers registered type keys`，`Refs #14`。

### Task 3：文档

- [ ] `docs/tycss-reference.md` / `.en.md` 新增 §4.5「typeKey 链」：登记方法、解析顺序（含 D2 的悬停 / 禁用后果与写法）、让位规则（D3）、子部件键、限制（8 级、成环、冲突、运行中登记不触发重画）、lint 与补全。
- [ ] `docs/subclassing.md` / `.en.md` 第 2 节：删掉「拿不到任何样式、记在 #14」那段，改成「覆写 `GetStyleTypeKey` + 在 `initialization` 登记父键」的完整单元，示例代码在 Task 4 用 fpc 实编。
- [ ] 提交 `docs(theming): type key chains`，`Refs #14`。

### Task 4：编译、全量、变异、性能、签收

- [ ] `lazbuild -B tests/tytests.lpi`，exe 复制为 `tests/tytests-tk14.exe`，输出重定向到 scratchpad。
- [ ] 跑 `TTypeKeyChainTest`、`TThemeLintTest`、`TTestThemeGolden`、`TTestThemes`、`TStyleModel*`、`TCssCatalogTest`、`TButtonTest`，再跑全量。与基线（Task 0 前跑的 `140496e6` 全量）比条数与红名单。
- [ ] golden 三个文件 `git diff --quiet tests/golden`。
- [ ] 文档示例单元用 fpc 实编（scratchpad 里一个 `uses TagButton` 的小程序）。
- [ ] 集中变异（§6），写回原字节还原，变异后重编再跑 `TTypeKeyChainTest`。
- [ ] 性能：scratchpad 探针（只链 StyleModel，`-O2`）对改前快照与改后各跑 5 轮，冷 / 热 `ResolveStyle` 每次调用耗时，填表（§7）。
- [ ] 签收（§8），提交 `test(style): sign off the type key chain`，正文 `Fixes #14`。

## 5. 主控 / 用户要做的事

- 【主控执行】裁决 D2 的顺序（先父后子 vs 按阶段交错）。
- 【主控执行】编 `tycontrols.lpk` / `tycontrols_dt.lpk`。
- 【主控执行】合 `main` 前按 pre-merge checklist 查 i18n（`examples/*/languages` 里各有一份库字符串目录副本，本任务只改了 `languages/` 下的两份）。
- 设计期 StyleOverride 编辑器的参考面板（`designtime/tyControls.Design.Css.Editor.pas:166`）仍只列目录键；补全已经列登记键。要不要让面板也列，主控定。

## 6. 变异清单

| 编号 | 变异 | 必须红的测试 |
|---|---|---|
| M1 | 只解析叶：循环改成 `for ci := 0 downto 0` | ChainWithoutChildRules、ChildRuleOverrides、ThreeLevel、PropertyCascade、TagButtonRendersLikeButton、TagButtonRule… |
| M2 | 顺序反了：`for ci := 0 to High(chain)` | ChildRuleOverrides、ChildBaseRuleBeatsParentState、ThreeLevel、TagButtonRule… |
| M3 | 让位看叶：`UserHasTypeKey(AKey)` 换成判整条链的叶键 | PlainChildRuleYieldsOnlyChildBase |
| M4 | `CacheCurrent` 不看戳记 | CacheFollowsRegistration |
| M5 | 去掉成环检查 | CycleRaises…、SelfParentRaises |
| M6 | 去掉过深检查 | TooDeepRaises |
| M7 | 冲突时覆盖而不是抛 | ConflictingParentRaises |
| M8 | `GetVariantsForType` 只扫叶 | VariantsFollowChain |
| M8b | 链取法把未登记键也接到某个父上（`TyTypeKeyChain` 对空父也追加） | NoChainIsByteIdentical、UnregisteredKeyGetsNothing |
| M9 | 补全不追加登记键 | CompletionOffersRegisteredKeys |
| M10 | 登记表大小写敏感 | CaseInsensitiveChain |
| M11 | 撤销不动戳记 | CacheFollowsRegistration |
| M12 | 不校验键名 | InvalidNamesRaise |

## 7. 性能

（Task 4 填）

## 8. 签收

（Task 4 填）
