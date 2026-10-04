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

**不在本计划**：CHANGELOG（发版时写）；~~`designtime/` 里 StyleOverride 编辑器的参考面板（直接读 `TyCatalogTypeKeys`，见 §5）~~（主控裁决后补做，见 §9）；主题编辑器（theme builder，未立项、仓库里没有）；合 `main`。

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

> **已被主控裁决推翻（2026-10-05），现行语义见 §9 D2′「按阶段交错」。** 下文保留原样，作为当时的设计记录。

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
| `TestNoChainIsByteIdentical` | 登记 20 个无关子键前后，目录里每个键在 4 组 (class, states) 下的转储相同 | —（回归；单键路径的逐字节等价由 golden 守，见 M13） |
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

- ~~【主控执行】裁决 D2 的顺序（先父后子 vs 按阶段交错）。~~ 已裁决：按阶段交错（§9）。
- 【主控执行】编 `tycontrols.lpk` / `tycontrols_dt.lpk`。
- ~~【主控执行】合 `main` 前按 pre-merge checklist 查 i18n（`examples/*/languages` 里各有一份库字符串目录副本，本任务只改了 `languages/` 下的两份）。~~ 已查：不需要同步，理由见 §9。
- ~~设计期 StyleOverride 编辑器的参考面板（`designtime/tyControls.Design.Css.Editor.pas:166`）仍只列目录键；补全已经列登记键。要不要让面板也列，主控定。~~ 主控定为要列，已做（§9）。

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
| M13 | 底层从不让位：`if FPropertyCascade or not UserHasTypeKey(chain[ci])` 换成 `if True`（单键路径与今天不再等价） | PlainChildRuleYieldsOnlyChildBase、`TTestThemeGolden.TestShowcaseGolden` |
| M9 | 补全不追加登记键 | CompletionOffersRegisteredKeys |
| M10 | 登记表大小写敏感 | CaseInsensitiveChain |
| M11 | 撤销不动戳记 | CacheFollowsRegistration |
| M12 | 不校验键名 | InvalidNamesRaise |

## 7. 性能

探针：scratchpad 里一个只链 StyleModel 的小程序（`fpc -O2`），改前用 `140496e6` 的 `source/` 快照编，改后用本分支编；两者交替各跑 3 次，每次 5 轮，表里是 15 个样本的中位数，单位为每次 `ResolveStyle` 的微秒。「冷」= 每轮先 `RefreshSystemTokens` 让缓存失效，再对目录全部 253 个键各解析两次（`primary`+hover、无类+normal）；「热」= 同样的请求缓存已满。机器上同时有别的会话在编译跑测试，单次波动约 ±10%。

| 场景 | 改前冷 | 改后冷 | 改前热 | 改后热 |
|---|---|---|---|---|
| 只有内置层 | 296.8 | 294.1 | 3.99 | 4.28 |
| 内置层 + dark 主题 | 275.5 | 290.2 | 4.11 | 4.19 |
| 同上 + 登记 20 个无关子键 | — | 294.0 | — | 4.36 |
| 只解析 `TyButton` | 862.2 | 847.8 | 6.64 | 6.55 |
| 只解析一条两级链的子键 | — | 901.2 | — | 6.59 |

结论：没有可测的变慢。未命中路径多一次登记表查询（空表时直接返回）和一次动态数组分配；命中路径多一次整数比较。子键冷解析比 `TyButton` 本身贵约 6%（多扫一遍两层规则找子键）。

## 8. 签收

**提交**：`52ec197e` 计划；`9ba746f8` 登记表与沿链解析；`5c87b9b4` 补全；`ab590436` 文档；`83f3228f` 修一处注释里的花括号（FPC 的 `{ }` 注释会嵌套，编译出 Comment level 2 警告）和一条写错的成环测试；本提交签收。

**编译**：`lazbuild -B tests/tytests.lpi` 通过；StyleModel 只剩改前就有的两条警告。

**测试**：`TTypeKeyChainTest` 21/21、`TThemeLintTest` 20/20、`TTestThemeGolden` 8/8、`TTestThemes` 19/19、`TCssCatalogTest` 14/14、`TButtonTest` 25/25、`TTestStyle{Resolve,PropertyCascade,Load,Override,Mode}` 全绿。全量（`tests/tytests-tk14.exe --all`）8786 条，0 错误，1 失败：`TTyTerminalPerfTests.TestTheLongestSliceStaysNearTheBudget`（计时，25.7 ms 超预算）；单独重跑第一次 298.9 ms、第二次 13.1 ms 通过——机器负载导致的偶发，与本改动无关（终端写队列不经样式解析的未命中路径）。基线（`140496e6`）全量 8764 条全绿；差值 22 = 新增 21 + lint 1。

**golden**：`git diff --quiet tests/golden` 通过，三份一字不变。

**文档示例**：`docs/subclassing.md` 与 `.en.md` 里的 `MyTagButton` 单元抽出来逐字节相同，用 fpc 编进一个小程序：编译通过，运行时 `TyTypeKeyParent('MyTagButton') = 'TyButton'`，且 `ResolveStyle('MyTagButton')` 有背景。

**变异**（§6，写回原字节还原并逐字节核对，每个变异后增量重编，结束后 `-B` 全量重编再跑全量）：M1–M13 全部被杀，每个都红在表中预期的测试上（M3 另外还红了 ChildRuleOverrides、ThreeLevel、TagButtonRule…，因为它们的用户层也有子键普通规则）。

**与计划的偏差**：完成补全的测试随 Task 1 一起提交（Task 2 才实现），中间那个提交上它是红的。原计划 M8b 构造不出能区分的变异，换成 M13。

**未做 / 交主控**：见 §5。

## 9. 主控裁决后的修订（2026-10-05）

主控裁决三条：① 解析顺序改为按阶段交错；② 设计期参考面板也列登记键；③ 查 `examples/*/languages` 是否要同步。

### D2′ 按阶段交错（取代 D2）

阶段（tier）就是 §4.4 在一层里的顺序：0 = 普通规则，1 = 变体（按 StyleClass 顺序），2–6 = selected、hover、focus、active、disabled 各一档（每档先 `Key:state` 再 `Key.variant:state`）。

- 链根照旧：`if PropertyCascade or not UserHasTypeKey(root) then ResolveLayer(底层, root); ResolveLayer(用户层, root)`。**不登记链的键只走这两行，逐字节不变。**
- 链根下面的键（`LayerChainChildren`）：先按链根自己的解析顺序（底层全部阶段、再用户层全部阶段）重放一遍，只记下**每个属性最后是哪一档写的**（`lastTier`）；然后从根往叶，每个键逐档应用（该档内先底层、后用户层，底层照 D3 按该键自己让位）。某档写过的属性里，凡 `lastTier` 比这一档**更晚**的，从该档应用前的快照写回（祖先更晚阶段的值胜）；其余属性记为这一档（子键胜同档和更早档）。
- 结果：子键普通规则盖不过父键 `:hover` / `:disabled`；子键 `:hover` 盖过父键 `:hover`；子键 `.primary` 盖过父键 `.primary`，但盖不过父键的 `:hover`；同档先父后子，多级同理。
- 「父键最后写的档」取父键**自己的**结果：用户层一条普通规则在父键自己的结果里已经盖掉了内置 `:hover`（`PropertyCascade` 开时），对子键也只算普通档。这是为满足「主题没写子键时与父键完全相同」必须的——父键自己的顺序是按层的，不是按档的。
- 只写子字段、不立 Present 标志的三个声明（`background-size`、`background-blur`、`outline-offset`）算作写了所属属性（`tpBackground` / `tpOutline`），随它一起让位。
- 每条规则写哪些属性（`EntryProps`）只看属性名和值的形状、不看变量取值，缓存在规则条目上（`f1663d64`），否则链键冷解析要贵一倍。

让位规则（D3）不变。

### 测试（`TTypeKeyChainTest`，21 → 28）

`TestChildBaseRuleBeatsParentState` 改写为 `TestChildBaseRuleYieldsToParentState`（新语义）；新增 `TestChildBaseRuleYieldsToBuiltinHover`（主题只写子键普通背景，悬停时等于按钮悬停，最常见的情形）、`TestChildStateBeatsParentSameState`、`TestParentDisabledBeatsChildHover`、`TestChildVariantBeatsParentVariantNotParentState`、`TestParentVariantBeatsChildBase`、`TestThreeLevelInterleave`、`TestSubFieldDeclarationYieldsWithItsField`；`TestCompletionOffersRegisteredKeys` 加了参考面板列表（`TyCssSelectorTypeKeys`）的断言。

### 设计期参考面板

`Css.Complete.pas` 新增 `TyCssSelectorTypeKeys`（目录键 + 目录里没有的登记键），补全和 `designtime/tyControls.Design.Css.Editor.pas` 的参考面板都读它，两边不会不一致。设计期单元用 fpc 对着测试构建产出的运行时单元、IDEIntf / SynEdit 的已编单元单独编过：0 错误、0 警告，输出只写 scratchpad。dt 包由主控编。

### i18n：`examples/*/languages` 不同步

- `scripts/check-example-po.py` 只检查已有条目（空 msgid+msgstr、占位符不一致、多余的格式标记、重复），**不**拿示例目录和库的 `.pot` 比完整性；跑了一遍：101 个文件 0 问题。
- 示例里的库字符串副本不是库目录的完整镜像（库 267 条，示例 92–96 条）。最近给库加报错文字的提交（`97572817` 终端配色方案的报错、`639a773b`）只改了 `languages/` 两份；只有示例界面上看得见的字符串才同步进示例副本（`fe1429b8` 的「基本颜色」）。
- 本任务的 4 条是 `TyRegisterTypeKeyParent` 用错时抛的异常文字，没有示例调用它。按惯例不同步。

### 变异（重做）

| 编号 | 变异 | 结果 |
|---|---|---|
| M1 | 不叠链根下面的键 | 杀 |
| M2 | **退回「先父后子」**（永不写回祖先更晚档的值） | 杀：YieldsToParentState、YieldsToBuiltinHover、ParentDisabledBeatsChildHover、ChildVariantBeats…NotParentState、ParentVariantBeatsChildBase、ThreeLevelInterleave、SubFieldDeclaration… |
| M2b | 叶先于中间键 | 杀：ThreeLevelInterleave、ThreeLevelChain |
| M2c | 同档归祖先（`>` 改 `>=`） | 杀：ChildRuleOverrides、ChildStateBeatsParentSameState 等 7 条 |
| M2d | 子键写的档不记下 | 杀：ThreeLevelInterleave |
| M2e | 重放链根时跳过底层 | 杀：YieldsToBuiltinHover 等 5 条 |
| M2f | 子字段声明不算所属属性 | 杀：SubFieldDeclaration… |
| M3 | 链根让位看叶键 | 杀：PlainChildRuleYieldsOnlyChildBase 等 7 条 |
| M3b | 子键底层从不让位 | 杀：PlainChildRuleYieldsOnlyChildBase |
| M4–M12 | 同 §6 | 全杀，各红在 §6 所列测试上 |
| M13 | 链根底层从不让位 | 杀：`TTestThemeGolden.TestShowcaseGolden` |

全部写回原字节并逐字节核对；加了条目缓存之后重跑了 M2、M2d、M2f，仍被杀。

### 性能（重测）

同 §7 的探针，改前快照对改后交替各 3 次，15 个样本中位数，微秒 / 次。

| 场景 | 改前冷 | 改后冷 | 改前热 | 改后热 |
|---|---|---|---|---|
| 只有内置层 | 286.8 | 300.0 | 3.96 | 4.22 |
| 内置层 + dark 主题 | 268.3 | 276.0 | 4.00 | 4.28 |
| 同上 + 登记 20 个无关子键 | — | 293.7 | — | 4.25 |
| 只解析 `TyButton` | 826.6 | 833.9 | 6.54 | 6.62 |
| 两级链的子键 | — | 907.3 | — | 6.59 |

未登记的键走的代码和交错之前完全一样，差别在噪声（±10%）以内。链键冷解析比 `TyButton` 本身贵约 9%（没有条目缓存时是 2 倍：1700 µs）；热路径不变。

### 签收（修订）

**提交**：`3f4f6f6f` 按阶段交错；`b303dd97` 设计期参考面板；`756be3e8` 文档（`tycss-reference` §4.5 中英、`subclassing` 第 2 节中英）；`f1663d64` 条目属性缓存；本提交签收。

**测试**：`lazbuild -B tests/tytests.lpi` 通过，`tests/tytests-tk14.exe --all`：**8793 条，0 错误，0 失败**（基线 8764 + 本任务 28 + lint 1）。`tests/golden` 三份一字不变（`git diff --quiet`）；M13 变异留下的 `showcase.golden.txt.actual` 已删。

## 集成与期末修复（2026-10-05，`feat/4.0-batch`）

三个分支（#9 标题栏、#14 typeKey 链、#27/#28 对话框选项）合进 `feat/4.0-batch`（`d509261d`）后整批审查，下面是按审查意见做的修复，每项一个提交（正文按 issue 写 `Refs`）：

| 提交 | 处理 |
|---|---|
| `0d0a2758` | 字体对话框 `fdLimitSize` + 原字号 0：显示的 9 被范围夹过时写回夹过的值，未被夹才保留 0（#28） |
| `2e5f883e` | 字体框 / 字体列表切换 `FixedPitchOnly`：原地重填、按名字找回选中，不再选第一行；没选中的仍不选；选中的字体族不变不发 `OnChange`、变了只发一次（#27） |
| `072528cb` | `TyGetFontFamilies` 所有列表（过滤与不过滤）都不列 `@` 竖排字体；字体对话框的不过滤列表也走它；写进升级说明（#27） |
| `4e7ce551` | `dialogs.md` §10 写成「从 3.0 升级须知」：所有 3.0 窗体里的查找 / 替换对话框都多出复选框，给 `.lfm` 与代码两种恢复写法；demo 的替换对话框补 `frHidePromptOnReplace`（#28） |
| `396e5c67` | 示例里的库翻译副本补这批界面上看得见的字符串：50 份都补窗口菜单 4 项（每个示例都有标题栏），demo / dialogs / ribbon 补「整个范围」「替换前提示」，filedialog 补文件对话框 3 条新消息（#9、#28） |
| `1e37ab32` | 选文件夹组件在 Linux / macOS 上把 `Directory` 的符号链接换成实际路径，写进 §8.5「从 3.0 升级」（#28） |
| `0f81e711` | 选文件夹路径框里的相对路径按树上选中的文件夹展开（不再按进程当前目录）；没选中时带三个存在性选项之一就报错；报错 / 询问走虚方法，OK 路径可无头测（#28） |
| `c2b3ceca` | 标题栏：Win32 顶边缩放热区清掉图标按下标记；图标跟随窗体 / 程序图标变化重画（`TTyForm` 经 `CM_ICONCHANGED` 转告 `HostIconChanged`），缩放好的图标按「图源 + 边长 + 版本号」缓存；菜单开着时单击图标只关菜单；焦点在 bar 上宿主放的窗口化控件里时菜单键不弹窗口菜单；文档写明右键不再冒泡到窗体的 `PopupMenu`（#9） |
| `7a80d1f4` | 新增 `TyTryRegisterTypeKeyParent`；`tycss-reference` §4.5 中英补「按属性组交错」「链根以下同一阶段先内置层后用户层」「`initialization` 里抛异常会让程序起不来」；补四角圆角还原测试（#14） |
| `f6dcc412` | 文件对话框「询问创建 / 询问覆盖」走虚方法 `ConfirmChoice`，补测试（#28） |
| `22fcad6a` | `FontFamilies` 单元头、`BuildForm`、`RefreshFonts` 文档改成实话：LCL 只填一次 `Screen.Fonts`，运行中新装的字体要重启程序（#27、#28） |
| `8ec8d708` | `rsTyWindowMenu*` 挪出 `rsTyToolWindow*` 那组；`.pot` 末尾补回生成器写的空行（提交的那份在 `e796fc02` 里丢了它，每次编包都把工作树弄脏）（#9） |
| `68b8bf33` | `tycontrols.strconsts.en.po` 删掉追加的 4 条与英文相同的翻译（文件头写明故意最小化）（#9） |
| `539736ce` | `dialogs.md` §10 中英混排改成全中文（#28） |

**编译**：`lazbuild -B tests/tytests.lpi` 通过，本批改过的单元没有新警告（StyleModel、Form 里的三条是原有的）；设计期 7 个单元用 fpc 对着测试构建的运行时单元、IDEIntf / SynEdit / LazControls 的已编单元单独编过，0 错误（4 条警告在 AdvChart 编辑器里，原有），输出只进 scratchpad。

**全量**（`tests/tytests-batchfix.exe --all`，即合并后的整批）：**8931 条，0 错 0 败**，没有计时类偶发红。合并前三份签收分别是 8836 / 8799 / 8793（各自分支）；本轮新增 22 条。`main` 上那 4 个 3.0 移植提交（`34d58e8a` 按钮栏不给隐藏按钮留空、`1f69a555` 隐藏按钮不定按钮栏高度、`bf26ce09` 文件对话框 `ofPathMustExist` / `ofFileMustExist`、`92076c03` 查找对话框的隐藏 / 禁用 / 帮助）带来的测试在 4.0 路径下全部跑到且全绿：`TestAHiddenButtonLeavesNoGap`、`TestAHiddenButtonDoesNotSetTheBarHeight`、`TFileDialogValidationTest` 的 5 条、`TFindOptionsTest` 的 7 条。`TTyCustomClassesGuardTest` 连跑 3 次，11/11 全绿。

**G9 / G10**：`gen-mimic.py` 重生成无 diff（没有新 published 属性）；`TY_WRITE_FRESH_STREAMS=1` 重写 `fresh-streams.txt` 内容无变化（只有写出时的 LF，已转回 CRLF）。`check-lfm-props` 通过，`check-example-po` 101 个文件 0 问题。

**变异**（按字节替换、断言命中 1 次、写回原字节并核对、每个变异后重编再跑相关 suite）：

| 变异 | 改了什么 | 结果 |
|---|---|---|
| M28f | 原字号 ≤0 一律保留 0（审查时存活的那个） | 红 |
| M28f2 | 原字号 ≤0 一律不保留 | 红 |
| M27c / M27cL | 切换 `FixedPitchOnly` 退回选第一行（字体框 / 列表） | 红（4 / 1） |
| M27d / M27dL | 不管变没变都发 `OnChange` | 红（2 / 2） |
| M27e / M27eL | 变了也不发 | 红（1 / 1） |
| M27f | `TyGetFontFamilies` 不滤 `@` | 红（字体族 2、字体框 3、列表 4、对话框 1） |
| M27g | 字体对话框不过滤时退回 `Screen.Fonts` | 红 |
| M28g | 相对路径不展开 | 红 |
| M28h | 没选中时相对路径不拒绝 | 红（2） |
| M9c | `IconChanged` 不 `Invalidate`（审查时存活的那个） | 红 |
| M9d | `IconChanged` 不升版本号（缓存不失效） | 红 |
| M9e | `TTyForm` 不改接 `Icon.OnChange` | 红 |
| M9f | `CMIconChanged` 不转告标题栏 | 红 |
| M9g | 图标单击不看菜单开着 / 刚关 | 红 |
| M9h | 菜单键不看焦点在宿主子控件上 | 红 |
| M9i | 顶边热区不清图标按下标记 | 红 |
| M9j | 默认菜单关闭不记时 | 红 |
| M14b | `RestoreProps` 不还原四角 `Radius`（审查时存活的那个） | 红 |
| M14c | `TyTryRegisterTypeKeyParent` 出错仍返回 True | 红 |
| M14d | `outline-offset` 不算进 outline 组 | 红 |
| M28a | 选中集里的输入名再查一次（审查时存活的那个） | 红 |
| M28i / M28j | 询问创建 / 覆盖不问直接放行 | 红（2 / 1） |

**选择与理由**：
- `@` 竖排字体：普通列表也过滤。LCL `TFontDialog` 在 Windows 上就是 `ChooseFont`，它不列这些；GTK / Qt / Cocoa 本来不报；它们在横排控件里字是躺着的。3.0 列出它们，写进 `fontcombobox.md` / `fontlistbox.md` / `dialogs.md` 的升级说明。
- 选文件夹相对路径：展开而不拒绝。路径框平时显示选中文件夹的完整路径，在上面输一个名字的意思就是「在这里面」，Windows 选文件夹对话框也这样；没选中时无从展开，才拒绝。输入过程中只跟随完整路径，免得选中的文件夹在手底下变动。
- `outline-offset`：不拆成单独属性位，只写文档。组的划分和 StyleOverride 合并是同一套；拆开要给样式集加新的 `Present` 标志，所有读它的地方都得认，而只有父子键在不同阶段分写同一个焦点环的两半时才碰得到。

**未覆盖 / 要人看的**：
- 图标单击「只关菜单」在真机上依赖弹出菜单自己的失活关闭（点击主窗口 → 延迟关闭），测试只模拟了「菜单开着」「刚关」两种顺序。
- 标题栏放在非 `TTyForm` 的窗体上时，窗体 / 程序图标的变化要宿主自己调 `HostIconChanged`（文档已写）。
- `ofNoResolveLinks`、选文件夹的不可写文件夹：同前，Windows 上测不出。

**主控待做**：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编示例冒烟（toolwindows 的图标与窗口菜单、demo 的替换对话框）；合 `main` 时注意 `main` 在本分支起点之后又有 `672c16c9`、`12ca184f`（3.0 的 `@` 字体修复，`TyFontPickerFamilies` 与「只有过滤单元读 `Screen.Fonts`」的源码守卫）、`0fb45bbc`（文件对话框 OnCanClose 只问通过校验的名字），与本批在 `FontComboBox` / `FontListBox` / `Dialogs.Font` / `Dialogs.FileDialog` / `.pot` 及对应测试上会冲突——4.0 一侧以 `TyGetFontFamilies` 为准（`TyFontPickerFamilies` 可改成调它），守卫要放行 `tyControls.FontFamilies`；合完再跑一次全量。
