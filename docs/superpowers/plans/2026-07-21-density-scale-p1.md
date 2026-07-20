# 密度尺度 · 第一期(基础设施与 CSS 令牌化)实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把主题系统从"配色系统"变成能表达几何的"设计系统",且经典密度逐字节不变。

**Architecture:** 两步。① 修好 `padding` 的 `var()` 展开顺序(今天多值令牌会静默算错)。② 把 41 条 padding 字面量换成 19 个角色令牌,值保持不变,并让标题控件真的去引用标题字号。全程由 3 份逐字节 golden 守着。

**按名字取尺寸令牌的 API 不用建 —— 它已经存在。** `TTyStyleController.Metric(AName, ADefault)`
(底下是 `TTyStyleModel.ResolveMetric`)是 theme-v3 C 期加的,public,语义正是
"从合并后的令牌里取一个长度,取不到就用回退值"。全仓库只用了它**一次**
(`--font-size-base` 取字体回退值)。第 3 期的迁移今天就无前置。

**Tech Stack:** Free Pascal / Lazarus,FPCUnit,`.tycss` 自有样式引擎。

---

## 范围说明(为什么这里只有 0~2 期)

设计文档 `docs/superpowers/specs/2026-07-21-density-scale-design.md` 分了 6 期。
本计划只覆盖 **0~2 期**,理由:

- 0~2 期**自身即可独立交付并验证**:经典逐字节不变、令牌词汇表就位、多值令牌可用。
- 第 3 期是约 100 处调用 + 66 个常量、跨 40 多个控件的机械迁移,它的逐条步骤
  **取决于第 1 期最终定下的令牌名**,现在写只能靠编。
- 第 4 期(现代取值)的不确定性全在"比例调没调对",要真机看了才谈得上计划。
- 第 5 期是 45 个示例各加一行。

3~5 期在 0~2 期落地后各自单开计划。

## 文件结构

| 文件 | 职责 | 动作 |
|---|---|---|
| `source/tyControls.Css.Values.pas` | CSS 值求值(长度、颜色、`var()`) | 新增 `TyExpandVars` |
| `source/tyControls.StyleModel.pas` | 样式模型:解析、合并、解析出 `TTyStyleSet` | `ParsePadding` 改用 `TyExpandVars` |
| `themes/light.tycss` | 基准主题(base 层,垫在每个皮肤下) | 新增令牌;41 条 padding 改走令牌 |
| `tests/test.StyleModel.pas` | 样式模型测试 | 新增 `TTestDensityTokens` |
| `source/tyControls.DefaultTheme.pas` | 由 light.tycss 生成 | **只能由 `./gen-defaulttheme.ps1` 重生成** |
| `source/tyControls.BuiltinThemeData.pas` | 由 themes/ 生成 | **只能由 `./gen-builtinthemes.ps1` 重生成** |

**注意**:改 `themes/light.tycss` 之后必须跑两个生成器,否则 golden 与 built-in 一致性测试会挂。

## 全程守卫

每个 Task 的最后一步都是这条。它是整期的核心保证:

```bash
lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --all --format=plain | grep -E "Number of (run|err|fail)"
git diff --stat tests/golden/
```

预期:`Number of failures: 0`,且 **`git diff --stat tests/golden/` 无输出**(3 份 golden 逐字节不变)。
golden 的每一行都含 `pad=左,上,右,下`,所以 padding 迁移只要有一处算错,它立刻红。

---

## Task 1:padding 里的多值令牌(第 0 期)

**背景**:`ParsePadding` 先按空格切分、再逐段 `TyEvalLength`。于是
`padding: var(--pad-tooltip)`(`--pad-tooltip: 5px 9px`)会被当成**单个**长度求值:
`var(...)` 展开成 `5px 9px` → 末尾 `px` 被剥掉变成 `5px 9` → `ParsePctOrNum` 给出错数。
**不报错,只是错。** 第 2 期的 19 个角色令牌里有 12 个是多值的,所以这是硬前置。

**Files:**
- Modify: `source/tyControls.Css.Values.pas`(新增 `TyExpandVars`)
- Modify: `source/tyControls.StyleModel.pas` — `ParsePadding` 内的 `parts.DelimitedText := ...` 一行
- Test: `tests/test.StyleModel.pas`

- [x] **Step 1:写失败测试**

在 `tests/test.StyleModel.pas` 的 `type` 段末尾(`TTestStylePhase0` 之后)加:

```pascal
  { 密度尺度第一期:多值令牌必须能用在 padding 上。
    这条守的是**展开与切分的顺序** —— 先切分再展开的话,
    `padding: var(--pad-tooltip)` 会静默算出一个错数(不报错,只是错)。 }
  TTestDensityTokens = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMultiValuePaddingToken;
    procedure TestSingleValuePaddingTokenStillWorks;
    procedure TestLiteralPaddingUnchanged;
  end;
```

在 `implementation` 段末尾(`initialization` 之前)加:

```pascal
const
  CSS_DENSITY =
    ':root { --pad-tooltip: 5px 9px; --pad-control: 4px; }' + LineEnding +
    'TyHint   { padding: var(--pad-tooltip); }' + LineEnding +
    'TyEdit   { padding: var(--pad-control); }' + LineEnding +
    'TyButton { padding: 6px; }';

procedure TTestDensityTokens.SetUp;
begin
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss(CSS_DENSITY);
end;

procedure TTestDensityTokens.TearDown;
begin
  FModel.Free;
end;

{ '5px 9px' = 上下 5、左右 9(CSS 的「纵向 横向」约定)。 }
procedure TTestDensityTokens.TestMultiValuePaddingToken;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyHint', '', []);
  AssertTrue('padding 存在', tpPadding in s.Present);
  AssertEquals('上', 5, s.Padding.Top);
  AssertEquals('下', 5, s.Padding.Bottom);
  AssertEquals('左', 9, s.Padding.Left);
  AssertEquals('右', 9, s.Padding.Right);
end;

procedure TTestDensityTokens.TestSingleValuePaddingTokenStillWorks;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyEdit', '', []);
  AssertEquals('上', 4, s.Padding.Top);
  AssertEquals('左', 4, s.Padding.Left);
end;

{ 现存的 41 条规则全是字面量。这条守的是「修了展开顺序之后它们一点没变」——
  也就是第 2 期迁移之前,经典 golden 不会因为这个修改而漂移。 }
procedure TTestDensityTokens.TestLiteralPaddingUnchanged;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertEquals('上', 6, s.Padding.Top);
  AssertEquals('左', 6, s.Padding.Left);
end;
```

在 `initialization` 段加:

```pascal
  RegisterTest(TTestDensityTokens);
```

- [x] **Step 2:跑,确认它红**

```bash
lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --suite=TTestDensityTokens --format=plain
```

预期:`TestMultiValuePaddingToken` 失败,报 `"上" expected: <5> but was: <某个错数>`。
另外两条应当已经绿(它们守的是不许回归)。

- [x] **Step 3:加 `TyExpandVars`**

在 `source/tyControls.Css.Values.pas` 的 `interface` 段,`TyEvalLength` 声明旁加:

```pascal
{ 把 Expr 里所有 var(...) 就地展开成它们的值,返回展开后的字符串。
  多值属性(padding)必须**先展开再切分** —— 反过来的话
  `padding: var(--pad-tooltip)` 会把 '5px 9px' 当成一个长度求值,
  静默算出一个错数。 }
function TyExpandVars(const Expr: string; Vars: TStrings): string;
```

在 `implementation` 段,`TyEvalLength` 之前加:

```pascal
function TyExpandVars(const Expr: string; Vars: TStrings): string;
var
  lo, ref, val: string;
  i, j, depth, guard: Integer;
begin
  Result := Expr;
  { 护栏:令牌互相引用成环时不至于转死。32 层远超任何真实主题的嵌套。 }
  guard := 0;
  while guard < 32 do
  begin
    Inc(guard);
    lo := LowerCase(Result);
    i := Pos('var(', lo);
    if i = 0 then Exit;
    { 从 'var(' 的左括号起按深度找配对的右括号 —— var() 可以嵌套
      (var(--a, var(--b))),只找第一个 ')' 会截断。 }
    depth := 0;
    j := i + 3;
    while j <= Length(Result) do
    begin
      if Result[j] = '(' then Inc(depth)
      else if Result[j] = ')' then
      begin
        Dec(depth);
        if depth = 0 then Break;
      end;
      Inc(j);
    end;
    if j > Length(Result) then Exit;   { 括号不配对:原样返回,别把输入吃掉 }
    ref := Copy(Result, i, j - i + 1);
    val := Trim(ResolveVarRef(ref, Vars));
    Result := Copy(Result, 1, i - 1) + val + Copy(Result, j + 1, MaxInt);
  end;
end;
```

- [x] **Step 4:让 `ParsePadding` 先展开再切分**

在 `source/tyControls.StyleModel.pas` 的 `ParsePadding` 里,把:

```pascal
    parts.DelimitedText := Trim(ARaw);
```

改成:

```pascal
    { **先展开 var() 再按空格切分。** 顺序反了的话,值含空格的令牌
      (--pad-tooltip: 5px 9px)会被当成单个长度求值,静默算错。 }
    parts.DelimitedText := Trim(TyExpandVars(ARaw, Vars));
```

- [x] **Step 5:跑,确认全绿**

```bash
lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --all --format=plain | grep -E "Number of (run|err|fail)"
git diff --stat tests/golden/
```

预期:`Number of failures: 0`;`git diff --stat tests/golden/` **无输出**。

- [x] **Step 6:变异验证**

把 Step 4 改回 `parts.DelimitedText := Trim(ARaw);`,重跑:

```bash
lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --suite=TTestDensityTokens --format=plain
```

预期:`TestMultiValuePaddingToken` 红。**确认红之后把改动改回来**,重新跑一遍确认绿。

- [x] **Step 7:提交**

```bash
git add source/tyControls.Css.Values.pas source/tyControls.StyleModel.pas tests/test.StyleModel.pas
git commit -m "fix(css): expand var() before splitting padding

A padding token whose value contains spaces (--pad-tooltip: 5px 9px) was
split before expansion, so var(--pad-tooltip) was evaluated as a single
length: it expanded to '5px 9px', the trailing 'px' was stripped, and
ParsePctOrNum returned a wrong number. It did not raise -- it was just
wrong, which is the worst failure mode for a value that ends up in a
pixel offset.

TyExpandVars expands every var() in the raw value first, counting paren
depth so nested var(--a, var(--b)) is not truncated at the first ')'.

This unblocks the semantic padding tokens: 12 of the 19 planned roles
carry two values.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2:经典令牌词汇表(第 1 期)

**背景**:补齐尺寸类令牌,**全部取今天的实际值**。这一步不改任何观感,
只是把散在规则里的数字变成有名字的东西。

**Files:**
- Modify: `themes/light.tycss`(`:root` 段)
- Regenerate: `source/tyControls.DefaultTheme.pas`、`source/tyControls.BuiltinThemeData.pas`

- [x] **Step 1:加令牌**

在 `themes/light.tycss` 的 `:root` 段里,`--font-size-base` 那一行之后加:

```css
  /* ── 尺寸令牌(密度尺度第一期)────────────────────────────────
     经典密度 = 今天的实际值,一个都不动。现代密度由 density-modern.tycss
     覆盖这些名字,不碰任何规则、也不碰任何颜色 —— 所以它对 15 个皮肤
     一视同仁。
     注意:这里**没有** --space-* 数字尺度。经典侧有 5px/9px/10px/14px
     这些历史随手值,强推 4 的倍数会让经典漂移 1px,与「经典逐字节不变」
     冲突。尺度只在现代侧存在。 */

  /* 字号:经典三档全是 9px —— 这种扁平本身就是 Win32 时代的特征,
     字号层级是 Web 时代才有的东西。 */
  --font-size-sm: 9px;

  /* 内边距:按**角色**命名,不按尺度命名(见上)。41 条规则归并成 19 个角色。 */
  --pad-none:            0px;
  --pad-tight:           2px;
  --pad-control:         4px;
  --pad-tooltip:         5px 9px;
  --pad-button:          6px;
  --pad-container:       8px;
  --pad-card:            12px;
  --pad-empty:           16px;
  --pad-cell:            0px 6px;
  --pad-chip:            0px 8px;
  --pad-badge:           0px 4px;
  --pad-breadcrumb:      2px 4px;
  --pad-breadcrumb-item: 0px 4px;
  --pad-groupbox:        4px 12px;
  --pad-datetime:        4px 6px;
  --pad-segmented:       4px 10px;
  --pad-alert:           8px 12px;
  --pad-notification:    12px 14px;
  --pad-group-header:    0px 14px;

  /* 控件高与图标槽:第 3 期把 Pascal 侧的常量迁到这里时会用上。 */
  --control-height: 30px;
  --row-height:     22px;
  --header-height:  22px;
  --item-height:    24px;
  --icon-size:      16px;
```

- [x] **Step 2:重跑两个生成器**

```powershell
.\gen-defaulttheme.ps1
.\gen-builtinthemes.ps1
```

预期:两条 `Regenerated ...` 输出。

- [x] **Step 3:跑,确认全绿且 golden 不变**

```bash
lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --all --format=plain | grep -E "Number of (run|err|fail)"
git diff --stat tests/golden/
```

预期:`Number of failures: 0`;golden **无输出**(只加了令牌,没人引用)。

- [x] **Step 4:提交**

```bash
git add themes/light.tycss source/tyControls.DefaultTheme.pas source/tyControls.BuiltinThemeData.pas
git commit -m "feat(theme): size token vocabulary, classic values

Adds the size half of the token vocabulary the theme system never had:
41 padding declarations condensed into 19 role tokens, plus control
heights, an icon slot and a small font size. Every value is what the
theme resolves to today, so nothing renders differently.

Padding tokens are named by role (--pad-button) rather than by a numeric
scale (--space-3). Classic carries irregular historical values -- 5px 9px,
4px 10px, 0px 14px -- and forcing them onto a 4px scale would drift
classic by a pixel in a handful of controls, which is exactly what the
byte-identical golden exists to prevent. The numeric scale will live only
on the modern side, where it can be internally consistent.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3:41 条 padding 改走令牌(第 2 期)

**背景**:纯替换,值不变。golden 是唯一也是充分的守卫。
**依赖 Task 1** —— 19 个角色里有 12 个是多值的。

**Files:**
- Modify: `themes/light.tycss`(41 条规则)
- Regenerate: 两个生成器产物

- [x] **Step 1:按下表逐条替换**

每条规则里的 `padding: <字面量>` 换成 `padding: var(<令牌>)`:

| 规则 | 原值 | 令牌 |
|---|---|---|
| `TyTrackBar` `TyTransfer` | `0px` | `--pad-none` |
| `TyListBox` `TyMenuBar` `TyTreeView` | `2px` | `--pad-tight` |
| `TyEdit` `TyCheckBox` `TyRadioButton` `TyComboBox` `TyListItem` `TyTab` `TySpinEdit` `TyMemo` `TyMenuView` `TyMenuPopup` `TyMenuItem` `TyCascader` | `4px` | `--pad-control` |
| `TyHint` `TyChartTooltip` | `5px 9px` | `--pad-tooltip` |
| `TyButton` `TyButton.ghost` `TyCalendar` | `6px` | `--pad-button` |
| `TyPanel` `TyPopover` | `8px` | `--pad-container` |
| `TyCard` | `12px` | `--pad-card` |
| `TyEmpty` | `16px` | `--pad-empty` |
| `TyGridCell` `TyPaginationItem` | `0px 6px` | `--pad-cell` |
| `TyTag` `TyTransferTitle` `TyCascaderItem` | `0px 8px` | `--pad-chip` |
| `TyBadge` | `0px 4px` | `--pad-badge` |
| `TyBreadcrumb` | `2px 4px` | `--pad-breadcrumb` |
| `TyBreadcrumbItem` | `0px 4px` | `--pad-breadcrumb-item` |
| `TyGroupBox` | `4px 12px` | `--pad-groupbox` |
| `TyDateTimePicker` | `4px 6px` | `--pad-datetime` |
| `TySegmentedItem` | `4px 10px` | `--pad-segmented` |
| `TyAlert` | `8px 12px` | `--pad-alert` |
| `TyNotification` | `12px 14px` | `--pad-notification` |
| `TyListGroupHeader` `TyListGroupItem` | `0px 14px` | `--pad-group-header` |

注意 `TyBadge` 与 `TyBreadcrumbItem` 原值同为 `0px 4px`,但**给了两个令牌** ——
它们是两个角色,现代密度下很可能取不同的值。合并成一个会把这个自由度提前丢掉。

**分三批做,每批之后跑一次 Step 2。** 批次:① 单值的 22 条;② 双值里的
`--pad-cell` / `--pad-chip` / `--pad-badge` / `--pad-breadcrumb*`;③ 其余。
一次全改再发现 golden 红,定位成本高得多。

- [x] **Step 2:每批之后重生成 + 验证**

```powershell
.\gen-defaulttheme.ps1
.\gen-builtinthemes.ps1
```

```bash
lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --all --format=plain | grep -E "Number of (run|err|fail)"
git diff --stat tests/golden/
```

预期:`Number of failures: 0`;golden **无输出**。
若 golden 有输出:说明某条令牌的值抄错了。`tests/golden/*.actual` 会写在旁边,
`diff tests/golden/light.golden.txt tests/golden/light.golden.actual` 直接指出是哪个 typeKey 的 `pad=`。

- [x] **Step 3:确认没有漏网**

```bash
grep -cE "padding: *[0-9]" themes/light.tycss
```

预期:`0`(所有 padding 都走令牌了)。

- [x] **Step 4:提交**

```bash
git add themes/light.tycss source/tyControls.DefaultTheme.pas source/tyControls.BuiltinThemeData.pas
git commit -m "refactor(theme): route all padding through role tokens

All 41 padding declarations now read a token instead of a literal. Values
are unchanged, which the byte-identical golden asserts -- every line of it
carries pad=l,t,r,b, so a single mistyped token turns it red.

TyBadge and TyBreadcrumbItem both resolve to 0px 4px today but get
separate tokens: they are different roles and will likely want different
values at modern density. Merging them would spend that freedom early.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4:标题字号层级(第 2 期)

**背景**:今天 `--font-size-title` 只被 `TyTitleBar` 一条规则引用,值也是 9px ——
**字号层级实际上不存在**。要让现代密度能有层级,得先让标题性控件真的去引用它。

**风险**:这些控件目前**根本没声明 font-size**。加上声明后,若某控件此前的
字体回退不是 9px,经典会漂移 —— 逐字节 golden 正是为抓这个而在。

**Files:**
- Modify: `themes/light.tycss`
- Regenerate: 两个生成器产物

- [x] **Step 1:给标题性控件加 font-size 声明**

给下列规则各加一条 `font-size: var(--font-size-title);`:

```
TyCardHeader  TyPopoverTitle  TyCalendarTitle  TyTransferTitle
```

`TyTitleBar` 已经有了,不动。
`TyGridHeader` / `TyTreeHeader` / `TyListGroupHeader` 已显式声明 `--font-size-base`,
**保持不动** —— 表格列头是密集数据的一部分,不是标题层级。

- [x] **Step 2:重生成并验证**

```powershell
.\gen-defaulttheme.ps1
.\gen-builtinthemes.ps1
```

```bash
lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --all --format=plain | grep -E "Number of (run|err|fail)"
git diff tests/golden/
```

**这一步 golden 可能真的会变**,而且变了不一定是错:如果某控件此前拿到的
不是 9px,现在被显式钉成 9px,那是修正了一处隐式回退。

- 若 golden **无变化**:直接进 Step 3。
- 若 golden **有变化**:逐条看 `git diff tests/golden/` 里 `fnt=/<字号>/<字重>` 那一段。
  只允许出现"某控件字号从别的值变成 9"。出现任何**其它**字段变化就是改错了,
  回退重来。确认无误后把新 golden 一起提交,并在提交信息里写明哪几个 typeKey 变了、
  从多少变成 9。

- [x] **Step 3:提交**

```bash
git add themes/light.tycss source/tyControls.DefaultTheme.pas source/tyControls.BuiltinThemeData.pas tests/golden/
git commit -m "feat(theme): let title surfaces reference the title font size

--font-size-title existed but was read by exactly one rule (TyTitleBar),
and its value equalled the body size, so the library had no type
hierarchy at all. That flatness is faithful to the Win32 era; hierarchy
is what the modern density needs to express.

Card, popover, calendar and transfer titles now reference the token.
Grid, tree and list-group headers deliberately keep the body size -- a
column header is part of dense data, not a title.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 之后(各自单开计划)

| 期 | 内容 | 前置 |
|---|---|---|
| 3 | Pascal 侧约 100 处 `Scale(≥6)` + 66 个具名常量迁到 `ActiveController.Metric(...)`;`default 22` → `default 0` 哨兵改造 | 本计划 Task 2 |
| 4 | 写 `density-modern.tycss` + `Controller.Density`;**真机看比例** | 第 3 期 |
| 5 | 45 个示例各加一个密度开关 + 一个 `density` 专门示例 | 第 4 期 |

第 3 期的迁移**不碰**两类常量,理由见设计文档:形状比例(`TyArrowDefHeadRatio`、
`TyChartDonutHolePercent`)与物理/交互下限(`TyChartHitRadius`、`TyBadgeMinSize`、
227 处 1~4px 的发丝线与内缩)。

## 执行记录(2026-07-21 完成,分支 `feat/density-scale`)

三处与计划不同,都是执行中发现的:

1. **Task 1 修的是 3 处不是 1 处。** `padding` 之外,`ApplyShadow` 与
   `ApplyBorderRadius` 是同一份"先切分再求值"的代码形状。按"碰到一个就
   grep 全部"的纪律一起修,三处各自独立变异验证有效。
   另外失败方式比计划写的更糟也更好查:不是"静默算错",是 `EConvertError`
   抛出 `LoadFromCss`,**整份样式表加载失败**。

2. **中途插入了一次 golden 扩容(提交 `0e747ac`)。** 做到 Task 3 时发现
   `GGRID` 停在 `TyTreeCheckBox` —— 107 个 typeKey 里 **54 个从来没有像素守卫**
   (整个 Grid、整批 AntD 控件)。"golden 没变"当时对其中 19 条迁移毫无证明力。
   按正确顺序处理:先把迁移 stash 起来、在未迁移的树上扩 golden 并提升基线
   (纯增量,0 行旧值被改),再放回迁移验证。

3. **Task 4 是三边同步,不是单边。** `auto.tycss` 必须在 light 模式下与
   `light.tycss`、dark 模式下与 `dark.tycss` 逐字节相同。改了 light 之后
   `TestAutoLightEqualsLight` 红,同步 auto 之后 `TestAutoDarkEqualsDark` 红,
   两次都是这个不变量抓住的。三份文件都要改。

**结果**:3923 测试 / 0 失败(12 个错误是既有的无头环境 win32 限制);
41 条 padding 全部走令牌;golden 覆盖从 53 涨到 107 个 typeKey。

## 自审

- **规格覆盖**:设计文档的「机制」→ 第 4 期(Controller);
  「token 词汇表」→ Task 2、4;「内边距语义令牌」→ Task 2、3;
  「流式化约束」→ 第 3 期;「测试策略」→ 每个 Task 的 golden 步骤;
  「示例策略」→ 第 5 期。**缺口**:`Controller.Density` 本身不在本计划内,
  这是有意的 —— 没有现代取值时它无处可切。
- **写计划过程中推翻的一条**:设计文档原说"缺一个按名字取尺寸令牌的 API"。
  **错的** —— `TTyStyleController.Metric` / `TTyStyleModel.ResolveMetric`
  是 theme-v3 C 期就建好的 public API,语义一字不差,全仓库只用过一次。
  原计划里的 Task 2(新建 `TokenPx`)已删除;再建一个就是同一件事两份实现,
  这个仓库在这上面栽过两次。设计文档已同步更正。
- **占位符**:无。每个改动步骤都给了可粘贴的完整代码或逐条替换表。
- **类型一致**:`TyExpandVars(const Expr: string; Vars: TStrings): string` 在
  Task 1 定义并在同一 Task 内使用。第 3 期要用的
  `TTyStyleController.Metric(const AName: string; ADefault: Integer): Integer`
  是既有 public API,已核对签名。
- **已知的不确定处**:无。原先 Task 2 那处「到时候 grep 确认字段名」的软处,
  随该 Task 一并删除。
