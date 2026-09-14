# 滚动条自动隐藏 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 滚动条在没人用的时候淡出，滚动、悬停条本身、拖动时再出现；默认关闭，由主题 token 打开。

**Architecture:** 全部做进 `TTyScrollBar` 自身。一个惰性 `FHideTimer` 同时充当延时表和淡出动画驱动，**完全不碰已有的位置动画 `FTimer` / `HandleTimer` / `FPosAnim`**——那套逻辑有 `FDragging` 与 `LiveTracking` 的微妙分支，混进去是自找回归。可见度以一个 `FFadeLevel: Single` 表示，在 `RenderTo` 里乘进 `CurrentStyle` 的副本的 `Opacity`，走已有的 `TyApplyStyleOpacity` → `EndPaint` 铺父底色那条路。6 个宿主只转发属性，鼠标处理一行不动。

**Tech Stack:** FPC / Lazarus、`TTyAnimator`（`tyControls.Animation.pas`）、`TTyStyleController.Metric`、fpcunit。

**设计依据：** `docs/superpowers/specs/2026-09-14-scrollbar-auto-hide-design.md`

---

## 与 spec 的两处偏差（实现期查代码发现，spec 已在 Task 0 同步）

1. **「滚动条有焦点」这个活跃信号对内嵌条永远不成立。** 6 个宿主创建内嵌条时一律 `TabStop := False`（拖条不能把焦点从列表抢走）。信号保留，但它只对独立摆放的 `TTyScrollBar` 有意义。
2. **`Visible` 已经被宿主占用了。** Grid / ListView / ScrollBox / TreeView 建条时就 `Visible := False`，运行时按「内容装不装得下」开关。自动隐藏**只动 opacity，绝不碰 `Visible`**，两套机制必须正交：不需要这条 → 宿主 `Visible := False`；需要但暂时淡出 → `Visible := True` + `FFadeLevel = 0`。

---

## 文件清单

| 文件 | 职责 |
|---|---|
| `source/tyControls.ScrollBar.pas` | 主体：类型、常量、属性、状态机、动画、绘制接入 |
| `source/tyControls.Grid.pas` / `ListBox` / `ListView` / `Memo` / `ScrollBox` / `TreeView` | 各加一个 `ScrollBarAutoHide` published 属性并转发给内嵌条 |
| `themes/builtin/win11.tycss` / `macos` / `fluent` / `material3` | `:root` 里写 `--scrollbar-auto-hide: 1200` |
| `source/tyControls.BuiltinThemeData.pas` | 生成器产物，改皮肤后重跑 `scripts/gen-builtinthemes.ps1` |
| `tests/test.scrollbar.autohide.pas` | **新建**，本特性全部 headless 测试 |
| `tests/tytests.lpr` | uses 段注册上面这个新单元 |
| `docs/controls/scrollbar.md` | 纯主题菜谱 + 修 doc bug |

**不新建 `source/` 单元**，所以 `.lpk` 不用动。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **`Max` / `Min` 在 `TTyScrollBar` 的方法体内被控件自己的属性遮蔽。** 要用 Math 的就得写全 `Math.Max` / `Math.Min`。不写全的话报的是指着调用那行的裸语法错，看不出跟遮蔽有关系。任何钳位数值的地方都会撞上。
2. **`TTyAnimator` 没有 `Value` 成员**，缓动后的 0..1 视图叫 `Eased`；枚举成员是 `teEaseOutCubic` 不是 `teOutCubic`；停掉一个动画用 `SetTargetImmediate`，不是把 `DurationMs` 归零。
3. **别碰位置动画那一套**：`FTimer` / `HandleTimer` / `EnsureTimer` / `FPosAnim` / `FLastTickMs` / `AnimationsEnabled` / `TickElapsedMs` / `AdvanceAnimation` / `DisplayPos`。淡出是**另一套**机制，自己的字段、自己的 timer。在它们旁边加东西可以，改它们不行——每一条现存的滚动条测试都钉着它们的形状。
4. **`FDragging` 在 `protected`**，测试要碰它走 `tests/test.controls.scrollbar.pas:151` 那个 `TScrollAccess` 子类的路子，别另起炉灶。

---

## 跑测试的固定套路

改了 `source/` 之后**必须**：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi
```

跑（**exe 必须是唯一名**——另外两个会话也在跑 `tytests.exe`，按镜像名杀会互相掐掉；本 worktree 一律用 `tytests-31.exe`）：

```bash
cd /d/Projects/ty-3.1/tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyScrollBarAutoHideTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

**判据是 `Number of run tests` 那一行存在且 errors/failures 为 0，不是 exit code。** 输出为空 = 这次跑丢了，重跑，别读成通过。

全量：把 `--suite=...` 去掉。

---

### Task 0: 把两处偏差同步回 spec

**Files:**
- Modify: `docs/superpowers/specs/2026-09-14-scrollbar-auto-hide-design.md`

- [ ] **Step 1: 在 spec §4 的信号列表里给「有焦点」加限定**

把 `4. 滚动条有焦点` 改成：

```markdown
4. 滚动条有焦点——**只对独立摆放的条有效**：6 个宿主创建内嵌条时一律 `TabStop := False`（拖条不能把焦点从列表抢走），内嵌条永远拿不到焦点
```

- [ ] **Step 2: 在 spec §6 末尾追加一段，讲清与 `Visible` 的正交**

```markdown
### 与宿主的 `Visible` 正交

Grid / ListView / ScrollBox / TreeView 建条时就 `Visible := False`，运行时按「内容装不装得下」开关它。自动隐藏**只动 opacity，绝不碰 `Visible`**：

| 情形 | `Visible` | `FFadeLevel` |
|---|---|---|
| 内容装得下，不需要这条 | `False`（宿主管） | 不参与 |
| 需要，正在用 | `True` | `1` |
| 需要，已淡出 | `True`（**仍是 True**） | `0` |

把淡出做成 `Visible := False` 会让宿主重新布局把槽收掉，与前提 2 冲突。
```

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/superpowers/specs/2026-09-14-scrollbar-auto-hide-design.md && git commit -m "docs(scrollbar): an embedded bar never takes focus, and fading is not Visible

Two things the code says that the spec did not. Every host builds its
embedded bar with TabStop := False, so 'the bar has focus' can only ever
fire for a standalone bar. And four hosts already drive Visible from
whether the content overflows -- fading has to leave that alone and move
opacity only, or the slot the design promised to keep disappears.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 1: 类型、常量、有效延时

纯计算，先做，最容易钉死。

**Files:**
- Modify: `source/tyControls.ScrollBar.pas`（interface 段 type 区之前 / `TTyScrollBar` 类内）
- Create: `tests/test.scrollbar.autohide.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试**

新建 `tests/test.scrollbar.autohide.pas`：

```pascal
unit test.scrollbar.autohide;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ScrollBar;

type
  TTyScrollBarAutoHideTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyScrollBar;
    procedure UseThemeCss(const ACss: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ThemeOffByDefault;
    procedure ThemeDelayIsRead;
    procedure NegativeOneParsesAsOff;
    procedure NeverBeatsAnAutoHidingTheme;
    procedure AutoBeatsAnOffTheme;
  end;

implementation

procedure TTyScrollBarAutoHideTests.SetUp;
begin
  { 控件必须有父控件，并且自带 controller——否则它读的是进程级主题，
    单跑绿、全量红。 }
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(FForm);
  FBar := TTyScrollBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
end;

procedure TTyScrollBarAutoHideTests.TearDown;
begin
  FreeAndNil(FForm);   // 拥有 controller 与 bar
end;

procedure TTyScrollBarAutoHideTests.UseThemeCss(const ACss: string);
begin
  FCtl.LoadThemeCss(ACss);
end;

procedure TTyScrollBarAutoHideTests.ThemeOffByDefault;
begin
  { 主题什么都不说 -> Metric 回退到 TyScrollBarAutoHideDef = -1 = 关 }
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.ThemeDelayIsRead;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1200; }');
  AssertEquals(1200, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.NegativeOneParsesAsOff;
begin
  { 整条链路压在 TyEvalLength 那句「头两个字符都是 '-' 才算变量引用」上。
    谁把那个判断收紧成「以 '-' 开头」，-1 就会静默变成默认值。 }
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.NeverBeatsAnAutoHidingTheme;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1200; }');
  FBar.AutoHide := sbahNever;
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.AutoBeatsAnOffTheme;
begin
  { 主题说关，属性说要自动隐藏 -> 用回退延时，而不是「关」 }
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  FBar.AutoHide := sbahAuto;
  AssertEquals(TyScrollBarAutoHideFallbackMs, FBar.EffectiveAutoHideMs);
end;

initialization
  RegisterTest(TTyScrollBarAutoHideTests);
end.
```

- [ ] **Step 2: 把新单元注册进测试程序**

`tests/tytests.lpr` 的 uses 段里，紧跟 `test.controls.scrollbar,` 之后加一项：

```pascal
  test.scrollbar.autohide,
```

- [ ] **Step 3: 跑，确认编译就失败**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi 2>&1 | tail -20
```

预期：`Error: identifier idents no member "EffectiveAutoHideMs"`（以及 `TyScrollBarAutoHideFallbackMs`、`sbahNever` 未定义）。**编不过就是这一步的「红」。**

- [ ] **Step 4: 加类型与常量**

`source/tyControls.ScrollBar.pas`，`type` 关键字之前插入 const 段（现在文件里 `interface`→`uses`→`type` 是连着的，要新开一个 `const`）：

```pascal
const
  { 自动隐藏延时的主题令牌。一条轴，没有歧义的零：
      -1 = 关（滚动条一直显示，**内置主题就是这个值**）
       0 = 开，停手立即淡出
       N = 开，停手 N 毫秒后淡出
    走已有的 Metric 机制，tycss 不需要新的值类型。负号能活着走完
    ResolveMetric -> TyEvalLength -> ParsePctOrNum -> StrToFloat，理由见
    docs/superpowers/specs/2026-09-14-scrollbar-auto-hide-design.md §2。 }
  TyScrollBarAutoHideVar = '--scrollbar-auto-hide';
  TyScrollBarAutoHideDef = -1;
  { 属性明说要自动隐藏、而主题没给延时时的回退。macOS 量级。 }
  TyScrollBarAutoHideFallbackMs = 1200;
  { 出现要快——用户正在找它；消失要柔——别打扰。 }
  TyScrollBarFadeInMs  = 120;
  TyScrollBarFadeOutMs = 200;

type
  TTyScrollBarKind = (sbHorizontal, sbVertical);

  { 自动隐藏的三态。**不能是 Boolean**：Boolean 一旦被碰过就永远脱离主题
    控制，换主题不跟着变——在一个主打换肤的库里这是硬伤。 }
  TTyScrollBarAutoHide = (sbahDefault, sbahNever, sbahAuto);
```

（原来的 `type` 行与 `TTyScrollBarKind` 保留，别写重。）

- [ ] **Step 5: 加字段、属性与 `EffectiveAutoHideMs`**

`TTyScrollBar` 的 `private` 段加字段：

```pascal
    FAutoHide: TTyScrollBarAutoHide;
```

`public` 段加：

```pascal
    { 本条现在实际的自动隐藏延时，毫秒；-1 表示关（一直显示）。
      属性压过主题：sbahNever 恒为 -1；sbahAuto 在主题说关时用回退值。 }
    function EffectiveAutoHideMs: Integer;
```

`published` 段加（**`default sbahDefault` 必须与构造函数里赋的值一致**，否则 `.lfm` 写的值被当默认省略、加载后丢失）：

```pascal
    { 这条滚动条要不要在没人用的时候淡出。

      sbahDefault —— 跟主题走（令牌 --scrollbar-auto-hide）。
      sbahNever   —— 永远显示，压过主题。
      sbahAuto    —— 自动隐藏，压过主题；延时仍读主题，主题没给就用
                     TyScrollBarAutoHideFallbackMs。

      延时**故意不给属性**：单控件要不同延时是臆想需求。整体调快调慢改主题。 }
    property AutoHide: TTyScrollBarAutoHide read FAutoHide write FAutoHide default sbahDefault;
```

实现（放在 `EnsureTimer` 附近）：

```pascal
function TTyScrollBar.EffectiveAutoHideMs: Integer;
var
  themeMs: Integer;
begin
  if FAutoHide = sbahNever then
    Exit(-1);
  { ActiveController，不是裸 Controller——后者在没挂 controller 时会 AV。 }
  themeMs := ActiveController.Metric(TyScrollBarAutoHideVar, TyScrollBarAutoHideDef);
  if FAutoHide = sbahAuto then
  begin
    { 属性明说要隐藏。主题关着（或没说）时不能跟着关，否则这个属性是个谎。 }
    if themeMs < 0 then
      Exit(TyScrollBarAutoHideFallbackMs);
    Exit(themeMs);
  end;
  Result := themeMs;   // sbahDefault
end;
```

构造函数（`TTyScrollBar.Create`）里加：

```pascal
  FAutoHide := sbahDefault;
```

- [ ] **Step 6: 跑，确认绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyScrollBarAutoHideTests --format=plain > /tmp/t1.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t1.txt
```

预期：新套件全绿（errors 0 / failures 0）。**别对着绝对数字较劲**——补一条测试就让写死的数字全部作废。判据是 `Number of run tests` 那行存在、errors/failures 为 0、且条数比上一步**多了这一步新写的那几条**。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ScrollBar.pas tests/test.scrollbar.autohide.pas tests/tytests.lpr && git commit -m "feat(scrollbar): the auto-hide token and the three-state property

One token carries both the switch and the delay: -1 off, 0 immediate,
N milliseconds. The zero is not overloaded, which is why it is one axis
and not two tokens.

The property is a three-state enum rather than a Boolean so that touching
it does not permanently divorce the bar from the theme -- sbahDefault
follows the token, and only Never/Auto override it. Auto against a theme
that says off falls back to a delay instead of obeying the theme, because
a property that asks to hide and then does not is a lying property.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: published default 的 RTTI 守卫

**Files:**
- Modify: `tests/test.scrollbar.autohide.pas`

- [ ] **Step 1: 写测试**

`published` 段加一条，实现加：

```pascal
procedure TTyScrollBarAutoHideTests.DeclaredDefaultMatchesConstructed;
var
  pi: PPropInfo;
begin
  { 声明的 default 与构造值不一致 -> .lfm 里写的值被当默认省略 -> 加载后丢失。
    这个坑本库踩过，见 memory/tabstop-declared-default-must-match。 }
  pi := GetPropInfo(FBar, 'AutoHide');
  AssertTrue('AutoHide 必须是 published', pi <> nil);
  AssertEquals('声明的 default 必须等于构造函数赋的值',
    Ord(FBar.AutoHide), pi^.Default);
end;
```

uses 段补 `TypInfo`。

- [ ] **Step 2: 跑，确认绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyScrollBarAutoHideTests --format=plain > /tmp/t2.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t2.txt
```

预期：新套件全绿（errors 0 / failures 0）。**别对着绝对数字较劲**——补一条测试就让写死的数字全部作废。判据是 `Number of run tests` 那行存在、errors/failures 为 0、且条数比上一步**多了这一步新写的那几条**。

- [ ] **Step 3: 变异确认这条守卫真的在守**

把 `property AutoHide ... default sbahDefault;` 临时改成 `default sbahNever;`，重编重跑，**必须变红**。红了再改回来、重编、重跑确认绿。

> 光看绿不算数：跟着修复写的测试绿着错，本库有过一轮 5 条全绿全错。抓手就是把被测的东西变异掉看红不红。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tests/test.scrollbar.autohide.pas && git commit -m "test(scrollbar): pin AutoHide's declared default to its constructed value

Mutating the declaration to sbahNever turns this red, which is the only
evidence that it guards anything.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: 活跃信号与状态机（先做瞬时，不含动画）

> **已完成（`c44fb81e` / `fbd2ffa6` / `c3fa505e`）。下面的代码是原始计划，实现时改动不小——以代码为准，别照抄这一段。** 记在这里是为了留下痕迹：
>
> 1. **三条测试是假守卫**，全栽在同一个坑上：`StartFade` 只「武装」淡出、不动 `FadeLevel`，而断言落在武装那一 tick 上，于是守卫删没删读到的都是 1.0。`IdleFadesOutAfterTheDelay`、`PointerOnBarHoldsItOpen`、`DraggingHoldsItOpen` 都要在断言前**多推一个完整的 `TyScrollBarFadeOutMs`**。
> 2. **`NoteActivity` 只看 `FFadeLevel < 1.0` 是个真 bug**：淡出被武装、还没推进的那一帧里 level 仍是 1.0，活动信号落在那儿就取消不掉它——条照样藏掉，而且因为动画期间闲置时钟不走，会一直藏到下次活动。要同时问「有没有一个反向的淡出在跑」，`StartFade` 的早退也要跟着放宽。
> 3. **`FPointerOnBar` 是多余的**：基类 `TTyCustomControl` 已有 `FHover`（`Base.pas:1893/1900` 两处写，就是 `inherited MouseEnter/MouseLeave`），而且滑块绘制早就在读它。实现里已删掉这个字段，连带删掉了只剩一行不可观测代码的 `MouseLeave` override。
> 4. `MouseEnter`/`MouseLeave` 在 `TControl` 里是 **protected**，测试够不到——走 `TBarAccess` 那道门，和 `SetDraggingState` 一样。

**Files:**
- Modify: `source/tyControls.ScrollBar.pas`
- Modify: `tests/test.scrollbar.autohide.pas`

- [ ] **Step 1: 写失败的测试**

```pascal
procedure TTyScrollBarAutoHideTests.OffThemeAlwaysFullyVisible;
begin
  AssertEquals('主题关着时必须恒为完全可见', 1.0, FBar.FadeLevel, 0.001);
  FBar.NoteActivity;
  FBar.AutoHideTick(99999);
  AssertEquals('关着的时候多久都不该淡出', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.IdleFadesOutAfterTheDelay;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  AssertEquals('刚用过 -> 完全可见', 1.0, FBar.FadeLevel, 0.001);
  FBar.AutoHideTick(999);
  AssertEquals('延时没到 -> 还在', 1.0, FBar.FadeLevel, 0.001);
  FBar.AutoHideTick(1);            // 累计 1000，到点
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('淡出跑完 -> 不见了', 0.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.ActivityBringsItBack;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  FBar.NoteActivity;
  FBar.AutoHideTick(TyScrollBarFadeInMs);
  AssertEquals('用一下就该回来', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.PositionChangeCountsAsActivity;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  FBar.Position := 42;             // 程序化赋值也算「在用」
  FBar.AutoHideTick(TyScrollBarFadeInMs);
  AssertEquals(1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.PointerOnBarHoldsItOpen;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.MouseEnter;
  FBar.AutoHideTick(99999);        // 鼠标在条上，多久都不该淡
  AssertEquals(1.0, FBar.FadeLevel, 0.001);
  FBar.MouseLeave;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('鼠标离开后才开始计时', 0.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.DraggingHoldsItOpen;
begin
  { 条在手底下消失是不可接受的。用最激进的 delay=0 逼它。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  TBarAccess(FBar).SetDraggingState(True);
  FBar.AutoHideTick(99999);
  AssertEquals('拖着的时候不能淡出', 1.0, FBar.FadeLevel, 0.001);
  TBarAccess(FBar).SetDraggingState(False);
  FBar.AutoHideTick(0);                       // delay=0 -> 立刻该淡
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('松手之后才轮到它淡', 0.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.FadingIgnoresAnimationsEnabled;
begin
  { 内嵌条构造时一律 AnimationsEnabled := False——那管的是**滑块位置**缓动，
    有意为之（滚动要跟手，缓动会让滑块和内容错位）。淡入淡出要是共用了那个
    标志，内嵌条就永远是跳变——而内嵌条正是这个特性的主场。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.AnimationsEnabled := False;
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs div 2);
  AssertTrue('淡出必须真的经过中间态，不是一步跳到 0',
    (FBar.FadeLevel > 0.0) and (FBar.FadeLevel < 1.0));
end;
```

这两条要用一个 access 子类拿到 protected 的 `FDragging`——**照 `tests/test.controls.scrollbar.pas:151` 的 `TScrollAccess` 写**，别自己发明别的办法。加在测试单元的 `implementation` 段顶部：

```pascal
type
  { protected 成员的访问缝，照 test.controls.scrollbar.pas 的 TScrollAccess。 }
  TBarAccess = class(TTyScrollBar)
  public
    procedure SetDraggingState(AValue: Boolean);
  end;

procedure TBarAccess.SetDraggingState(AValue: Boolean);
begin
  FDragging := AValue;
end;
```

把这 7 个方法名加进 `published` 段。

- [ ] **Step 2: 跑，确认编不过**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi 2>&1 | tail -10
```

预期：`FadeLevel` / `NoteActivity` / `AutoHideTick` 未定义。

- [ ] **Step 3: 实现状态机**

`private` 段加字段：

```pascal
    FFadeLevel: Single;         // 1 = 完全显示，0 = 完全隐藏
    FFadeAnim: TTyAnimator;     // 0..1 traversal，驱动 FFadeFrom -> FFadeTo
    FFadeFrom, FFadeTo: Single;
    FIdleMs: Integer;           // 距上次「在用」过去了多久
    FPointerOnBar: Boolean;
    { 惰性；延时表与淡出共用它，靠 Interval 区分阶段。
      **和位置动画的 FTimer 无关**——那套有 FDragging/LiveTracking 的分支，
      掺进来只会把两件事一起弄坏。 }
    FHideTimer: TTimer;
    procedure EnsureHideTimer;
    procedure HandleHideTimer(Sender: TObject);
    function AutoHideHeldOpen: Boolean;
    procedure StartFade(ATo: Single; ADurationMs: Integer);
```

`public` 段加：

```pascal
    { 0..1 的当前可见度。1 = 完全显示。绘制时乘进样式的 opacity。 }
    property FadeLevel: Single read FFadeLevel;
    { 「有人在用」。滚动、悬停、拖动、聚焦都调它。 }
    procedure NoteActivity;
    { 测试缝：推进 AMs 毫秒。真机由 FHideTimer 驱动，headless 由测试驱动
      ——和位置动画的 HandleTimerTick 是同一个路子。 }
    procedure AutoHideTick(AMs: Integer);
```

实现：

```pascal
function TTyScrollBar.AutoHideHeldOpen: Boolean;
begin
  { 任一成立就「按住不放」，延时表根本不起。
    注意 Focused 只对独立摆放的条有意义：6 个宿主的内嵌条一律 TabStop=False。 }
  Result := FPointerOnBar or FDragging or (csDesigning in ComponentState)
            or (HandleAllocated and Focused);
end;

procedure TTyScrollBar.NoteActivity;
begin
  FIdleMs := 0;
  if FFadeLevel < 1.0 then
    StartFade(1.0, TyScrollBarFadeInMs);
  if EffectiveAutoHideMs >= 0 then
  begin
    EnsureHideTimer;
    if FHideTimer <> nil then FHideTimer.Enabled := True;
  end;
end;

procedure TTyScrollBar.StartFade(ATo: Single; ADurationMs: Integer);
begin
  if SameValue(FFadeLevel, ATo, 0.001) then Exit;
  FFadeFrom := FFadeLevel;
  FFadeTo := ATo;
  { TyAnimatorInit 给的是 Progress=0 -> Target=1 的归一化行程；真实的
    FFadeFrom -> FFadeTo 由 TyLerpF 按 Eased 插出来。
    枚举成员是 teEaseOutCubic，不是 teOutCubic。 }
  FFadeAnim := TyAnimatorInit(ADurationMs, teEaseOutCubic);
end;

procedure TTyScrollBar.AutoHideTick(AMs: Integer);
var
  delay: Integer;
begin
  delay := EffectiveAutoHideMs;
  if delay < 0 then
  begin
    { 关着。任何残留的淡出都要收回来，否则改主题/改属性之后条会停在半透明。 }
    if not SameValue(FFadeLevel, 1.0, 0.001) then
    begin
      FFadeLevel := 1.0;
      FFadeAnim.SetTargetImmediate(1.0);   { 让 Running 变 False，别留个跑着的动画 }
      Invalidate;
    end;
    Exit;
  end;

  if FFadeAnim.Running then
  begin
    if FFadeAnim.Advance(AMs) then
    begin
      { Eased 是缓动后的 0..1 视图（Value 这个成员不存在）。 }
      FFadeLevel := TyLerpF(FFadeFrom, FFadeTo, FFadeAnim.Eased);
      Invalidate;
    end;
    if not FFadeAnim.Running then FFadeLevel := FFadeTo;
    Exit;   { 动画期间不计闲置——否则淡入刚跑一半就被判定该淡出 }
  end;

  if AutoHideHeldOpen then
  begin
    FIdleMs := 0;
    Exit;
  end;

  Inc(FIdleMs, AMs);
  if (FIdleMs >= delay) and (FFadeLevel > 0.0) then
    StartFade(0.0, TyScrollBarFadeOutMs);
end;
```

`Position` 的 setter（`TTyScrollBar.SetPosition`）末尾加一句 `NoteActivity;`——**程序化赋值也算在用**。

`MouseEnter` / `MouseLeave` override（类里加声明，`protected` 段）：

```pascal
procedure TTyScrollBar.MouseEnter;
begin
  inherited MouseEnter;    { 不调 inherited 会吞掉 LCL 那层的 hover 状态 }
  FPointerOnBar := True;
  NoteActivity;
end;

procedure TTyScrollBar.MouseLeave;
begin
  inherited MouseLeave;
  FPointerOnBar := False;
  FIdleMs := 0;            { 从「离开」这一刻开始计时，不是从上次滚动 }
end;
```

构造函数加 `FFadeLevel := 1.0;`。

- [ ] **Step 4: 跑，确认绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyScrollBarAutoHideTests --format=plain > /tmp/t3.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t3.txt
```

预期：新套件全绿（errors 0 / failures 0）。**别对着绝对数字较劲**——补一条测试就让写死的数字全部作废。判据是 `Number of run tests` 那行存在、errors/failures 为 0、且条数比上一步**多了这一步新写的那几条**。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ScrollBar.pas tests/test.scrollbar.autohide.pas && git commit -m "feat(scrollbar): the idle clock, and what counts as still using it

Scrolling, the pointer on the bar itself, a drag, focus. Pointer movement
over the host content deliberately does not -- the pointer sits there most
of the time, so counting it would mean the bar never idles and auto-hide
would do nothing at all.

The clock does not advance while a fade is running, or a fade-in would be
judged idle halfway through and turn around.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: 真机的 timer 驱动

> **Step 1 已经在 Task 3 顺带做掉了**：那一步声明了 `EnsureHideTimer` / `HandleHideTimer`，而 FPC 不接受只有声明没有实现体的方法，所以 Task 3 必须把它们写出来——写出来的东西几乎就是下面这段。
>
> **Task 4 实际剩下三件事**，都是审查揪出来的：
>
> 1. **按真实经过时间步进**，不按 timer 的标称间隔（详见下方注释块）。需要自己的 `FFadeLastTickMs` 和一个 `TickElapsedMs` 的孪生体——原件在「别碰」清单上，不能共用。
>    **「孪生」= 连可见性和测试缝一起孪生**，`protected virtual`，不是只抄个函数体。原件的注释自己写着为什么：抽成可覆写的是为了让测试喂一个受控时钟，「**而这正是当初写成名义间隔也没人发现的原因**」。缝是活的——`tests/test.controls.scrollbar.pas:160` 的 `TFakeClockScroll` 就在 override 它。丢掉 `virtual`，「按真实时间推进」这条就只能靠 `Sleep` 和时钟运气去测。
> 2. **被按住不放的时候把 timer 停掉**，离开时再启起来。**这让 `MouseLeave` 重新有了存在的理由**（Task 3 因为它只剩一行不可观测代码而删了它）；`DoExit` 与拖动结束同理，但**逐个 trace 再决定加不加**，别反射性地全加上。
>
>    **两个方向的危险不对称，别按同一条标准判：**
>    - **重启路径漏一条**（按住 → 指针离开 → 没人重启时钟）→ 条多留一会儿。难看，但良性。
>    - **判定顺序写反**（先问「被按住吗」再问「动画还在跑吗」）→ **Task 3 那个搁浅 bug 的完整复刻**。条已淡到 0、表已停，指针移到那根看不见的条上 → `MouseEnter` → 武装淡入 + 起表 → 第一拍就被「被按住」判定停掉 → **指针停在那儿多久，条就多久不出现**。一定要让「有动画在跑」赢在最前面。
> 3. **`EffectiveAutoHideMs` 按 `(Model 身份, ThemeVersion)` 缓存**——**不是只按版本号**。`ThemeVersion` 是**每个 model 各自计数**的，两个各加载过一次的 controller 版本号相同；而 `Controller` 是 published 可重新赋值的，只按版本号会把 A 的延时端给 B。库里的先例（`Base.pas:1670`、`Menu.pas:924`）只按版本号，这里要比它们严。
>    只缓存**主题那一半**，把 `sbahNever`/`sbahAuto` 的属性判断留在缓存外（几个整数比较而已）——这样 `SetAutoHide` 根本不需要记得去作废缓存。
>
> **可测性（实测结论，比原来的预判乐观）**：三条都拿到了真覆盖。第 3 条直接可测。第 1 条经由 `HandleHideTimerTick` 端到端可测——这是 `HandleTimerTick` 的孪生缝，**那个先例确实存在**（`test.controls.scrollbar.pas:179` 在用），不是手工塞 timer。第 2 条**只有判定函数可测**：`FHideTimer.Enabled := False` 本身 headless 够不着（无句柄就没 timer），把 `AutoHideTimerNeeded` 抽出来直接测，真正的停表效果留给真机。**测不到就直说**——造一个手工塞 timer 的假测试，钉的是实现不是行为。

**Files:**
- Modify: `source/tyControls.ScrollBar.pas`

- [ ] **Step 1: 实现 timer**

```pascal
procedure TTyScrollBar.EnsureHideTimer;
begin
  { headless 与设计期不建 timer：没有句柄的时候动画没有意义，而设计器里
    这条永远不隐藏。 }
  if (csDesigning in ComponentState) or not HandleAllocated then Exit;
  if FHideTimer = nil then
  begin
    FHideTimer := TTimer.Create(Self);
    FHideTimer.Enabled := False;
    FHideTimer.Interval := 16;   // ~60fps；延时阶段也用它，靠 FIdleMs 累计
    FHideTimer.OnTimer := @HandleHideTimer;
  end;
end;

procedure TTyScrollBar.HandleHideTimer(Sender: TObject);
begin
  AutoHideTick(FHideTimer.Interval);
  { 到了终态就把 timer 停掉，别让它空转到天荒地老。下次 NoteActivity 会
    再打开。 }
  if (not FFadeAnim.Running) and
     (SameValue(FFadeLevel, 0.0, 0.001) or (EffectiveAutoHideMs < 0)) then
    FHideTimer.Enabled := False;
end;
```

> 16ms 的 tick 在延时阶段确实是空转，但它同时是淡出动画的驱动，多一个低频 timer 换来两套状态反而更难对齐。一条条最多空转「延时」那么久，之后就自己停了。

> **`AutoHideTick(0)` 会让正在跑的淡出瞬间跑完。** `TTyAnimator.Advance` 把 `AMs <= 0` 当成「直接吸附到 Target」。Task 3 里这不成问题（唯一的 0ms 调用走的是「关着」那条分支），但真 timer 一旦可能投递一个 0ms 的步长，淡出就会跳变而不是渐变。两相 `Interval` 切换的那一刻尤其危险——**切 `Interval` 时别顺手用 0 去「立即触发一次」**。

> **别在每个 tick 里调 `EffectiveAutoHideMs`。** 它每次都走 `ResolveMetric`，而那里**即使缓存命中也要**先拼一个 `AName + '|' + IntToStr(ADefault)` 的 key 字符串再做 `IndexOf`——每次调用一个堆字符串。现在常见路径上**每 tick 调两次**（`AutoHideTick` 里一次、`HandleHideTimer` 的停止判断里一次）。按 60fps × 最多 12 条内嵌条算，一条静止不动的条能烧掉每秒上千次字符串分配。本库已经在 `TTyMemo` 上被逐帧开销咬过一次（0.5 秒一键的延迟）。
>
> **缓存要按 `ActiveController.Model.ThemeVersion` 键控**，别想着「在主题变更时作废」——**没有主题变更通知这回事**：`TTyStyleController.Changed` 只广播一个裸 `Invalidate`，全 `source/` 里没有 `StyleChanged` 钩子。库里现成的做法是拿 `ThemeVersion` 当锚，见 `tyControls.Base.pas:767` 和 `:1670`。照「主题变更时作废」的字面意思写，会做出一个**永远供应旧主题延时**的缓存。

> **淡出要按真实经过时间步进，不能按 timer 的标称间隔。** 现在 `HandleHideTimer` 传的是 `FHideTimer.Interval`（16），而同一个文件里 200 行开外的 `HandleTimer` 做的正好相反，还写了长注释解释为什么：界面忙的时候（大网格重绘一帧上百毫秒）定时器会被饿死，按标称累加会把 120 ms 的缓动拉成将近一秒。**而网格滚动中正是这段代码在跑的时候。** 需要一个自己的 `FFadeLastTickMs` 加一个 `TickElapsedMs` 的孪生体（`FLastTickMs` 在「别碰」清单上，不能共用）。保留 `if Result < 1 then Result := 1` 那道钳位——它同时也是挡住 0 ms 步长掉进 `Advance` 吸附路径的东西。

> **「按住不放」的时候要把 timer 停掉。** 现在的停止条件只认「没有动画在跑 且（关着 或 已经淡到 0）」，于是鼠标停在滚动条上——一个极其常见的鼠标停靠位置——timer 就永远以 16 ms 转下去，什么也没推进。被按住的时候本来就无事可做：停掉它，让 `MouseLeave` / `DoExit` 再启起来。**这也正好给 `MouseLeave` 一个重新存在的理由**（Task 3 因为它只剩一行不可观测的代码而把它删了）。

- [ ] **Step 2: 全量跑，确认没碰坏位置动画**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --format=plain > /tmp/full1.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/full1.txt
```

预期：新套件全绿（errors 0 / failures 0）。**别对着绝对数字较劲**——补一条测试就让写死的数字全部作废。判据是 `Number of run tests` 那行存在、errors/failures 为 0、且条数比上一步**多了这一步新写的那几条**。

**若 `test.controls.scrollbar` 里有红**：说明动了位置动画那条路，回头看是不是把 `NoteActivity` 加进了 `SetPosition` 的错误分支。

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ScrollBar.pas && git commit -m "feat(scrollbar): drive the fade from a timer of its own

Not the position animator's timer. That one carries FDragging and
LiveTracking branches whose shape is load-bearing, and HandleTimer stops
it the moment the position eases home -- which would cut a fade off
mid-way. A separate lazy timer costs one handle per bar that actually
hides, and keeps both state machines legible.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: 把 fade 接进绘制

**Files:**
- Modify: `source/tyControls.ScrollBar.pas`（`RenderTo`）
- Modify: `tests/test.scrollbar.autohide.pas`

- [ ] **Step 1: 写测试**

```pascal
procedure TTyScrollBarAutoHideTests.FadeMultipliesIntoStyleOpacity;
var
  s: TTyStyleSet;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }' +
              'TyScrollBar { background: #808080; color: #404040; opacity: 0.5; }');
  FBar.NoteActivity;
  s := FBar.PaintStyleForTest;
  AssertEquals('完全可见时就是主题自己的 opacity', 0.5, s.Opacity, 0.001);

  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  s := FBar.PaintStyleForTest;
  AssertEquals('淡出到底 -> 0，而不是主题的 0.5', 0.0, s.Opacity, 0.001);
  AssertTrue('必须把 tpOpacity 标成 present，否则画笔根本不看这个值',
    tpOpacity in s.Present);
end;
```

- [ ] **Step 2: 跑，确认编不过**（`PaintStyleForTest` 未定义）

- [ ] **Step 3: 抽出「绘制用的样式」并接上 fade**

`public` 段加：

```pascal
    { RenderTo 真正用的那份样式：主题样式叠上自动隐藏的淡出系数。
      抽成函数是为了让测试能问「这一帧的 opacity 是多少」，而不用去数像素。 }
    function PaintStyleForTest: TTyStyleSet;
```

实现：

```pascal
function TTyScrollBar.PaintStyle: TTyStyleSet;
var
  base: Single;
begin
  Result := CurrentStyle;
  if SameValue(FFadeLevel, 1.0, 0.001) then Exit;
  { record 是非托管的：Present 里没有 tpOpacity 时 Result.Opacity 的值不可信，
    必须自己给基准，不能直接乘。 }
  if tpOpacity in Result.Present then base := Result.Opacity else base := 1.0;
  Result.Opacity := base * FFadeLevel;
  Include(Result.Present, tpOpacity);
end;

function TTyScrollBar.PaintStyleForTest: TTyStyleSet;
begin
  Result := PaintStyle;
end;
```

（`PaintStyle` 放 `private`，`PaintStyleForTest` 是 `public` 的测试缝。）

`RenderTo` 里把 `S := CurrentStyle;` 改成：

```pascal
    S := PaintStyle;
```

- [ ] **Step 4: 跑，确认绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyScrollBarAutoHideTests --format=plain > /tmp/t5.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t5.txt
```

预期：新套件全绿（errors 0 / failures 0）。**别对着绝对数字较劲**——补一条测试就让写死的数字全部作废。判据是 `Number of run tests` 那行存在、errors/failures 为 0、且条数比上一步**多了这一步新写的那几条**。

- [ ] **Step 5: 变异确认**

把 `S := PaintStyle;` 改回 `S := CurrentStyle;`，重编重跑——`FadeMultipliesIntoStyleOpacity` **必须红**。红了改回来。

> 「建好了没接线」是本库的默认故障，已经八次。这条变异就是专门验接线的。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ScrollBar.pas tests/test.scrollbar.autohide.pas && git commit -m "feat(scrollbar): the fade rides the style's opacity, not a second channel

Going through TTyStyleSet means EndPaint's existing dim-toward-the-parent
path handles it, so a faded bar lands on the host's background instead of
going see-through over whatever is behind the window.

The style is an unmanaged record: without tpOpacity in Present its Opacity
field holds nothing trustworthy, so the multiply starts from an explicit
1.0 rather than from whatever was in the slot.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: 设计期永不隐藏

**Files:**
- Modify: `tests/test.scrollbar.autohide.pas`

`AutoHideHeldOpen` 里已经写了 `csDesigning`，`EnsureHideTimer` 也早退了。这一步只是把它钉住。

- [ ] **Step 1: 写测试**

```pascal
procedure TTyScrollBarAutoHideTests.DesignTimeNeverHides;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');   // 最激进：立即隐藏
  FBar.SetDesigning(True, False);
  FBar.AutoHideTick(99999);
  { **第二个 tick 不能省。** 第一个 tick 只是「武装」淡出——StartFade 不动
    FadeLevel，所以门控删没删，这一刻都读 1.0。真正把两种实现分开的是
    下面这一下：门控还在就什么都不会发生，门控没了就会跑完 200ms 淡出。 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('设计器里看不见滚动条是不可接受的', 1.0, FBar.FadeLevel, 0.001);
end;
```

> **原来这里只有一个 tick，是假守卫**（2026-09-14 修）。Step 3 让你删掉 `csDesigning` 那一项「必须变红」——按原来的写法它**不会红**，于是你会去找一个根本不存在的问题。这是本计划里第四条栽在同一个坑上的测试，前三条已经在 Task 3 实现时被逐条揪出来了。

- [ ] **Step 2: 跑，确认绿**（实现已在 Task 3，这条应当直接通过）

- [ ] **Step 3: 变异确认**

把 `AutoHideHeldOpen` 里的 `or (csDesigning in ComponentState)` 删掉，重编重跑——**必须红**。红了加回来。

> 直接就绿的测试最可疑：它可能根本没在测它声称的东西。变异一下才知道。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tests/test.scrollbar.autohide.pas && git commit -m "test(scrollbar): the designer never loses its scrollbars

Passed on the first run, which is exactly when a test deserves to be
mutated: dropping the csDesigning arm turns it red, so it is testing
what it claims.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: 6 个宿主转发

6 个宿主改法完全一样。**逐个做，逐个提交**，不要攒成一个。

**Files（每个宿主一轮）:**

| 宿主 | 单元 | 内嵌条字段 |
|---|---|---|
| Grid | `source/tyControls.Grid.pas` | `FVScroll`、`FHScroll` |
| ListBox | `source/tyControls.ListBox.pas` | `FScrollBar`、`FHScrollBar` |
| ListView | `source/tyControls.ListView.pas` | `FVScroll`、`FHScroll` |
| Memo | `source/tyControls.Memo.pas` | `FScrollBar`、`FHScrollBar` |
| ScrollBox | `source/tyControls.ScrollBox.pas` | `FVScrollBar`、`FHScrollBar` |
| TreeView | `source/tyControls.TreeView.pas` | `FVScroll`、`FHScroll` |

- [ ] **Step 1: 先写测试，六个宿主一次写全**

**怎么拿到内嵌条 —— 已经查过了（2026-09-14）：六个宿主一个现成的缝都没有。**

```bash
grep -n "ForTest\|function.*ScrollBar: TTyScrollBar" source/tyControls.{ListBox,Grid,Memo,TreeView,ListView,ScrollBox}.pas
```
只命中 `Grid.pas:2817 EditorCanCancelForTest`，跟滚动条无关。

**不要给六个宿主各加一个 `VertScrollBarForTest`。** 内嵌条都是 `Parent := Self` 的真子控件，测试遍历 `Controls` 就能拿到，不必为测试往公开 API 上加六个函数：

```pascal
function FindEmbeddedBar(AHost: TWinControl; AKind: TTyScrollBarKind): TTyScrollBar;
var
  i: Integer;
begin
  { 内嵌条是宿主的真子控件（建的时候 Parent := Self），所以遍历得到。
    这样就不用为了测试给六个宿主各开一个 public 函数——那种测试专用 API
    一旦进了公开面就再也删不掉。 }
  Result := nil;
  for i := 0 to AHost.ControlCount - 1 do
    if (AHost.Controls[i] is TTyScrollBar)
       and (TTyScrollBar(AHost.Controls[i]).Kind = AKind) then
      Exit(TTyScrollBar(AHost.Controls[i]));
end;

procedure TTyScrollBarAutoHideTests.ListBoxForwardsToItsEmbeddedBars;
var
  lb: TTyListBox;
  f: TForm;
  bar: TTyScrollBar;
  i: Integer;
begin
  { 「建好了没接线」是本库的默认故障，已经八次。转发这种四平八稳的代码最容易
    只写一半——属性加了，创建处没传。 }
  f := TForm.CreateNew(nil);
  try
    lb := TTyListBox.Create(f);
    lb.Parent := f;
    lb.SetBounds(0, 0, 120, 60);
    { ListBox 的条是**惰性创建**的：不塞够条目它根本不存在，
      于是「找不到条」会被误读成「转发没生效」。 }
    for i := 1 to 100 do lb.Items.Add('item ' + IntToStr(i));
    lb.ScrollBarAutoHide := sbahNever;
    bar := FindEmbeddedBar(lb, sbVertical);
    AssertTrue('内嵌竖条应当已经存在', bar <> nil);
    AssertEquals('属性必须传到内嵌条上', Ord(sbahNever), Ord(bar.AutoHide));
  finally
    f.Free;
  end;
end;
```

> **惰性 vs 急切**：ListBox 与 Memo 的条是惰性建的（要先有内容撑出滚动），Grid / ListView / ScrollBox / TreeView 在构造函数里就建好（只是 `Visible := False`）。所以后四个不用塞内容，前两个必须塞。写测试时按这个分别处理，别套同一个模板。

对其余五个宿主重复这条测试（`TTyStringGrid`、`TTyListView`、`TTyMemo`、`TTyScrollBox`、`TTyTreeView`），**不要写成循环**——每个宿主的构造路径不同，一个挂了要能立刻看出是哪个。

- [ ] **Step 2: 跑，确认六条全红**

- [ ] **Step 3: 逐个宿主实现**

每个宿主 `private` 加字段、`published` 加属性、setter 转发。以 ListBox 为例：

```pascal
  private
    FScrollBarAutoHide: TTyScrollBarAutoHide;
    procedure SetScrollBarAutoHide(const AValue: TTyScrollBarAutoHide);
```

```pascal
  published
    { 这个列表的两条滚动条要不要在没人用的时候淡出。转发给内嵌条，
      语义见 TTyScrollBar.AutoHide。 }
    property ScrollBarAutoHide: TTyScrollBarAutoHide
      read FScrollBarAutoHide write SetScrollBarAutoHide default sbahDefault;
```

```pascal
procedure TTyListBox.SetScrollBarAutoHide(const AValue: TTyScrollBarAutoHide);
begin
  if FScrollBarAutoHide = AValue then Exit;
  FScrollBarAutoHide := AValue;
  { 两条都是惰性创建的，建的时候也要带上——所以创建处同样要写一遍。 }
  if FScrollBar <> nil then FScrollBar.AutoHide := AValue;
  if FHScrollBar <> nil then FHScrollBar.AutoHide := AValue;
end;
```

**并且**在每个内嵌条的创建处（紧挨着已有的 `AnimationsEnabled := False`）加一行：

```pascal
      FScrollBar.AutoHide := FScrollBarAutoHide;
```

构造函数加 `FScrollBarAutoHide := sbahDefault;`。

> **惰性创建的宿主（ListBox / Memo）两处都要写**：setter 管「已经建好的」，创建处管「之后才建的」。只写 setter 的话，先设属性后滚动的用法会丢值。

- [ ] **Step 4: 每个宿主做完就跑、就提交**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyScrollBarAutoHideTests --format=plain > /tmp/t7.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t7.txt
```

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ListBox.pas tests/test.scrollbar.autohide.pas && git commit -m "feat(listbox): forward ScrollBarAutoHide to the embedded bars

Both the setter and the lazy creation site set it. The setter alone loses
the value for anyone who sets the property before the list ever scrolls.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 六个都做完后，全量跑**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --format=plain > /tmp/full2.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/full2.txt
```

预期：全量绿。**用增量判据**：条数 = 上一次全量数 + 这一步新增的条数，errors/failures 为 0。基线是本 worktree 开工时的 7035。

---

### Task 8: 现代主题打开它，并让编辑器认识这个令牌

**Files:**
- Modify: `themes/light.tycss`（显式写出默认值，见 Step 1）
- Modify: `source/tyControls.Css.Catalog.pas`（`TyCatalogTokens`）
- Modify: `themes/builtin/win11.tycss`、`macos.tycss`、`fluent.tycss`、`material3.tycss`
- Modify: `source/tyControls.BuiltinThemeData.pas`（生成器产物）

- [ ] **Step 1: 在 `light.tycss` 的 `:root` 里显式写出默认值**

```css
  --scrollbar-auto-hide: -1;
```

**为什么要写**：这个令牌的默认值本来活在代码里（`TyScrollBarAutoHideDef`），主题不写也能跑。但 StyleOverride 编辑器的补全与校验走的是 `TyCatalogTokens`（`source/tyControls.Css.Catalog.pas`），而 `tests/test.css.catalog.pas` 有一条守卫要求**catalog 里的每个令牌都在 `light.tycss` 里有定义**。想让用户在编辑器里能补全它（spec §11 验收 4 正是让用户写这行），就得两边都有。代码里的 `Def` 仍是兜底——主题被换成一个没定义它的皮肤时照样回落。

- [ ] **Step 2: 登记进 `TyCatalogTokens`**

照该数组现有条目的写法加一条，描述写清三个值的含义（`-1` 关 / `0` 立即 / `N` 毫秒）。加完跑一次 catalog 守卫：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyCssCatalogTests --format=plain > /tmp/cat.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/cat.txt
```

> 顺序很重要：**先写 `light.tycss` 再登记 catalog**。反过来那条守卫会红，而红的原因看起来像是 catalog 写错了，其实是主题还没写。

- [ ] **Step 3: 四个皮肤的 `:root` 各加一行**

```css
  --scrollbar-auto-hide: 1200;
```

**先确认每个文件确实有 `:root` 块**：

```bash
cd /d/Projects/ty-3.1 && for t in win11 macos fluent material3; do echo "=== $t ==="; grep -n ":root" themes/builtin/$t.tycss | head -3; done
```

- [ ] **Step 4: 重跑生成器**

```bash
cd /d/Projects/ty-3.1 && powershell -ExecutionPolicy Bypass -File scripts/gen-builtinthemes.ps1
```

> 15 个皮肤是**编译进** `BuiltinThemeData` 的，`themes/builtin/` 只是参考源。不重跑生成器，改的就只是磁盘上的文本，程序里的主题一点没变。

- [ ] **Step 5: 写一条测试，钉住「现代开、经典关」**

```pascal
procedure TTyScrollBarAutoHideTests.ModernThemesHideClassicThemesDoNot;
begin
  FCtl.ThemeName := 'win11';
  AssertTrue('win11 应当自动隐藏', FBar.EffectiveAutoHideMs >= 0);
  FCtl.ThemeName := 'classic';
  AssertEquals('经典主题必须一直显示', -1, FBar.EffectiveAutoHideMs);
end;
```

- [ ] **Step 6: 全量跑**

改主题会波及 golden 像素守卫。**若 golden 变红**：先确认变的是不是只有滚动条那几张；是就更新 golden，不是就回头查。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --format=plain > /tmp/full3.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/full3.txt
```

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add themes/ source/tyControls.Css.Catalog.pas themes/builtin source/tyControls.BuiltinThemeData.pas tests/test.scrollbar.autohide.pas && git commit -m "feat(themes): the modern skins hide their scrollbars, the classic ones do not

win11, macos, fluent and material3 opt in at 1200ms. classic, xp and aero
say nothing and inherit -1, which is the whole point of the split -- this
library supports two generations of look, and a Win7-era skin whose
scrollbars vanish is not one of them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: 图片主题的色块判定（spec §6 的二选一）

这一步产出的是**一个决定**，不是代码。

> **范围已缩小(2026-09-15)**：Task 5 给 `RenderTo` 加了早退——`opacity = 0` 时只铺父背景、不进合成分支。所以**常驻的完全隐藏态已经没有平板色风险了**，背景是像素级正确的。
>
> **这里要量的只剩淡入淡出途中那约 200 ms。** 暴露面从「用户盯着看的常驻状态」缩成「一闪而过的过渡」，判据也该跟着松：过渡期一瞬的色块，和常驻一块平板，完全不是一个量级的问题。量之前先想清楚这一点，别照着原来的标准去要求它。

**Files:**
- Create: `tests/test.scrollbar.autohide.pas` 里一条诊断测试（可能保留，也可能只是量完就删）

- [ ] **Step 1: 先确认 headless 到底测不测得了**

`green` 是图片主题，而 `url()` 是在 **resolve 时**求值的，`ResolveStyle` 期间必须处在主题目录下，否则图片路径直接断。headless 测试里这一条不一定成立。**先花两分钟确认，别在测不准的路上写半小时测试**：

```bash
cd /d/Projects/ty-3.1 && grep -rn "GlassSharpBackdrop\|GlassBackdrop" source/tyControls.Base.pas | head -5
```

写一条一次性探针，看 green 主题下宿主到底有没有拿到 backdrop：

```pascal
procedure TTyScrollBarAutoHideTests.ProbeGreenThemeHasBackdrop;
var
  host: ITyGlassHost;
  off: TPoint;
begin
  FCtl.ThemeName := 'green';
  { TyResolveGlassHost 返回 False 就说明 headless 下根本没有图片背景，
    这一整套 headless 测量就是在量一张纯色图，结论不作数。 }
  AssertTrue('headless 下 green 主题没有 backdrop，本任务改走真机',
    TyResolveGlassHost(FBar, host, off));
end;
```

- **这条通过** → 走 Step 2a（headless 量）
- **这条失败** → 走 Step 2b（真机量）。**把这条探针删掉，不要留一条永远红的测试在套件里。**

- [ ] **Step 2a: headless 量（探针通过时）**

判据不需要基准图：淡出后条那一竖条**如果是一块纯色、而紧邻它左侧的同高度区域有明显变化**，就说明 opacity 把渐变/照片铺平了。

```pascal
procedure TTyScrollBarAutoHideTests.MeasureFadeFlatteningOnImageTheme;
var
  bmp: TBitmap;
  y, barMin, barMax, sideMin, sideMax, v: Integer;
  W, H, barX, sideX: Integer;

  function Lum(c: TColor): Integer;
  begin
    Result := (Red(c) * 299 + Green(c) * 587 + Blue(c) * 114) div 1000;
  end;

begin
  FCtl.ThemeName := 'green';
  W := 200; H := 120;
  FBar.SetBounds(W - 14, 0, 14, H);
  FBar.Max := 100; FBar.Position := 50;

  bmp := TBitmap.Create;
  try
    { 非合成 blit 的离屏位图用 pf24bit：pf32bit 在 GTK2 上 alpha 平面全 0，
      整块黑，而 Win32 GDI 忽略 alpha 所以本机测不出来。 }
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(W, H);
    { 洋红哨兵底：白底会和 light 主题的表面色混淆，量出来的差没法归因。 }
    bmp.Canvas.Brush.Color := clFuchsia;
    bmp.Canvas.FillRect(0, 0, W, H);

    FBar.NoteActivity;
    FBar.AutoHideTick(99999);          { 主题若没开自动隐藏，这里仍是 1.0 }
    TBarAccess(FBar).SetFadeLevelForProbe(0.0);   { 直接按到全隐藏 }
    TBarAccess(FBar).RenderTo(bmp.Canvas, Rect(W - 14, 0, W, H), 96);

    barX := W - 7;      { 条的中线 }
    sideX := W - 30;    { 条左边 16px 处的宿主背景 }
    barMin := 255; barMax := 0; sideMin := 255; sideMax := 0;
    for y := 4 to H - 5 do
    begin
      v := Lum(bmp.Canvas.Pixels[barX, y]);
      if v < barMin then barMin := v;
      if v > barMax then barMax := v;
      v := Lum(bmp.Canvas.Pixels[sideX, y]);
      if v < sideMin then sideMin := v;
      if v > sideMax then sideMax := v;
    end;

    { 报出来，让人读数据再做决定——这一步的产出是一个决定，不是一条断言。 }
    Status(Format('bar spread=%d  side spread=%d', [barMax - barMin, sideMax - sideMin]));
    AssertTrue('哨兵底还在 = 条那一竖根本没画上去，测量无效',
      barMax > 0);
  finally
    bmp.Free;
  end;
end;
```

这需要给 access 类加两个缝：

```pascal
  TBarAccess = class(TTyScrollBar)
  public
    procedure SetDraggingState(AValue: Boolean);
    procedure SetFadeLevelForProbe(v: Single);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TBarAccess.SetFadeLevelForProbe(v: Single);
begin
  FFadeLevel := v;
end;

procedure TBarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;
```

**读数：** `side spread` 明显 > 0（背景确实在变）而 `bar spread` ≈ 0（条那一竖是平的）→ 铺平了，走 Step 3 的第二条。两个都 ≈ 0 → 这张背景本来就平，换一张对比强的图再量。

- [ ] **Step 2b: 真机量（探针失败时）**

1. `lazbuild -B tycontrols.lpk`（**先夺回机器级包注册权**，否则编的可能是另外两个会话的树）
2. `lazbuild -B examples/listbox/listbox.lpi` 并运行
3. 切到 `green` 主题，让列表长到出滚动条
4. 截两张图：滚动条完全显示时、淡出后
5. 放大看条所在的那一竖条与周围背景是否接得上

- [ ] **Step 3: 按数据二选一**

- **条那一竖与周围接得上**（`bar spread` 与 `side spread` 同量级 / 真机看不出边界）：照用。在 `docs/controls/scrollbar.md` 记一句已知限制，本任务结束。
- **明显是一块平色**：改 `TyApplyStyleOpacity`（`source/tyControls.Base.pas:1313`）用带 rect 的 `TyResolveParentBgFill` 取渐变切片，而不是 `TyResolveParentBg` 的单色中心。**这会顺带修好 `:disabled` 半透明在图片主题下的同一个毛病**——它一直在，只是没人报。

  动的是 `Base.pas` 共享文件，另外两个会话也可能在改——**动之前先说一声**，别自己合。

- [ ] **Step 4: 把结论写回 spec 并提交**

不论走哪条，都要把 spec §6 里那段「已知风险，用数据定」改写成**量到的结论 + 日期 + 走了哪条**。决定的理由比决定本身先过期，下一个人照着实现时得能看出这个判断是什么时候、基于什么数据做的。

```bash
cd /d/Projects/ty-3.1 && git add docs/ source/ tests/ && git commit -m "docs(scrollbar): settle how the fade lands on an image theme

Measured rather than argued. The spec carried this as an open risk; it now
carries the number and the date.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: 文档

**Files:**
- Modify: `docs/controls/scrollbar.md`

- [ ] **Step 1: 修 doc bug**

`§6`（以及 `:290`、`:372` 两处）现在只说 `TTyListBox` 与 `TTyMemo` 的内嵌条是静态的。实际 Grid / ListView / ScrollBox / TreeView 也都设了。改成六个宿主全列。

- [ ] **Step 2: 加自动隐藏一节**

写清：token 三个值、三态属性、宿主转发属性名、**哪些事算「在用」**（并点明鼠标在内容区上移动**不**算，以及为什么）、设计期不隐藏。

- [ ] **Step 3: 加纯主题菜谱**

```css
TyScrollBar { background: var(--chrome-bar-bg); color: var(--scroll-handle);
  border-radius: var(--radius-scroll); opacity: 0.3; }
TyScrollBar:hover  { color: var(--scroll-handle-hover); opacity: 1; }
TyScrollBar:active { color: var(--accent); opacity: 1; }
TyScrollBar:focus  { outline: 2px var(--focus-ring); }
TyScrollBar:disabled { opacity: var(--disabled-opacity); }
```

**必须写明两条**：①整块要抄全——用户层写了 `TyScrollBar` 任一条，内置那块就整体作废；②Task 9 量到的图片主题限定。

- [ ] **Step 4: 英文文档 —— 查过了，不用做**

`docs/controls/` 下只有中文，`scrollbar.en.md` 不存在（成对的是 `getting-started` / `themes` / `known-issues` / `tycss-reference` 那几篇顶层文档）。**这一步是 no-op，写在这里是为了让人不用再查一遍。**

合回 main 前仍要照 pre-merge checklist 看 README 中英双份要不要提这个能力——那是另一回事。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/controls/ && git commit -m "docs(scrollbar): auto-hide, and the four hosts the note forgot

The static-embedded-bar note named ListBox and Memo. Grid, ListView,
ScrollBox and TreeView do the same thing and always have.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## 收尾

- [ ] 全量测试绿，且 `Number of run tests` 那行在
- [ ] 按 spec §11 的六条验收逐条对
- [ ] **真机验**（headless 测不到）：淡入淡出观感、`green` 主题色块、隐藏态下鼠标移过去能否唤回并点中
- [ ] 合回 main 前照 pre-merge checklist 走：i18n（本特性无可译串，确认一下）、README 中英双份是否需要提这个能力
- [ ] example：`examples/scrollbar/` 是否值得加一个自动隐藏的开关演示——按「教用法 / 覆盖测试够不到的」判，不追求成员覆盖率
