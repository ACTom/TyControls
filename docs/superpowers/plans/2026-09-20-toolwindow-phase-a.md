# IDE 工作台 A 期：主题 + 几何 + 工具窗口 + 侧栏 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出能用的左右侧栏：图标条切换工具窗口、收起、拉宽、栏内调顺序；工具窗口自带标题行和可选操作区。不含底栏、manager、跨侧拖动、布局保存。

**Architecture:** 一个新单元 `source/tyControls.ToolWindows.pas` 放四个类（A 期只实现三个：`TTyToolWindow`、`TTyToolWindowActions`、`TTyToolWindowBar`；`TTyToolWindowManager` 只建空壳好让 `Manager` 属性在 B/C 期接上）。标题行几何是**纯函数**，控件只负责量文字、取 token、把结果画出来和命中；侧栏和底栏两种模式在纯函数里一次定完，底栏的接线留到 B 期。工具窗口照 `TTyTabSheet`（窗体拥有的设计期容器 + 绘制缓存），栏照 `TTyPageControl`（注册 / 注销 / 当前页回落）。

**Tech Stack:** FPC / Lazarus LCL、BGRABitmap、`TTyPainter`、`TTyStyleController.Metric`、fpcunit。

**设计依据：** `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`（下称 spec）。本计划覆盖 spec §16 的第 1–3 步。

---

## 文件清单

| 文件 | 职责 |
|---|---|
| `source/tyControls.ToolWindows.pas` | **新建**。四个类 + 纯几何函数 + token 常量 |
| `tycontrols.lpk` | 加一个 `<Item>` 登记新单元（`tests/test.release.pas` 走磁盘比对，漏登记会红） |
| `themes/light.tycss` | 16 个新 typeKey 的基础规则 + 14 个长度 token + 12 个颜色 token |
| `source/tyControls.DensityPack.pas` | 14 个长度 token 的现代取值 |
| `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas` | 生成物，改完 light.tycss 各跑一次生成器 |
| `tests/test.themes.pas` | GGRID 加 16 个键、GMETRICS 加 14 个 token、golden 重铺 |
| `tests/test.toolwindow.geometry.pas` | **新建**。纯几何函数（无控件、无句柄、无主题） |
| `tests/test.toolwindow.window.pas` | **新建**。工具窗口 + 操作区：排布、流式、缓存 |
| `tests/test.toolwindow.bar.pas` | **新建**。栏：尺寸推导、当前页、收起、图标条手势、拉宽、调顺序 |
| `tests/test.toolwindow.theme.pas` | **新建**。token 与 typeKey 走真皮肤的链路守卫 |
| `tests/tytests.lpr` | uses 段加上面四个新测试单元 |

**A 期不碰**：`designtime/`（组件编辑器和属性编辑器是 D 期）、`examples/`、`docs/controls/`、`languages/`。
所以 A 期**不需要**编 `tycontrols_dt.lpk`，也不用跑 `scripts/gen-icons.ps1`。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **`ClientRect` 不含 `AdjustClientRect` 的内缩。** 手工摆放子控件、量正文区，都要先自己调一次 `AdjustClientRect`（`TTyEmpty.ActionRect`，`Empty.pas:471-486` 是范本：查询就调自己的 `AdjustClientRect`，保证「一个定义只写一遍」）。
2. **改了客户区内缩量必须 `Realign; Invalidate;` 两句。** 只 `Invalidate`，alClient 子控件会停在旧 bounds 上、盖住新腾出来的标题行（`TabStrip.pas:1917-1932` 踩过这个）。
3. **`RenderTo` 里一切坐标是 (0,0)-local。** painter 建的是 W×H 位图、blit 到 `ARect.Left/Top`；用 `ARect` 当坐标系会整体平移。每条提前 `Exit` 的路径都要先 `P.EndPaint`。
4. **绘制缓存位图必须 `pf24bit`。** `TTyPaintCache` 已经是对的，自己另建位图时别顺手写 `pf32bit`（GTK2 整块变黑，Win32 测不出来）。
5. **FPC 3.2 不认 `SetLength` 初始化 managed result。** 纯函数里先 `Result := nil;` 再 `SetLength`。
6. **`csNoDesignVisible` 必须在写 `Visible` 之前设。** 顺序反了，设计器里切走的那一页 HWND 还杵着（`PageControl.pas:244-262`）。无头测不出来，只能用探针钉顺序（Task 5 Step 6）。
7. **published `default` 必须等于构造里赋的值**，否则 .lfm 省略该值、加载后丢失。`ExpandedSize` 构造值和 default 都是 240，侧栏底栏共用（Pascal 的 default 只能是常量）。
8. **token 名一律写成单元级具名常量**（`TyToolWindowHeaderHeightVar = '--toolwindow-header-height'`），调用点不写字符串字面量。读值一律 `ActiveController.Metric(...)`，不是裸 `Controller`（nil 会 AV）。
9. **`Metric` 返回逻辑像素**，用之前 `APainter.Scale(v)` 或 `MulDiv(v, Font.PixelsPerInch, 96)`。布局和绘制必须用同一套，否则出现「量的是逻辑、画的是设备」两套真相。
10. **新单元不加进 `tycontrols.lpk` 编译照样过**，但会从安装包里消失；`tests/test.release.pas` 是唯一守卫。另：仓库里**没有** `tycontrols.pas`（.gitignore 掉了，装包时生成），别去改它。
11. **别用 `sed -i` 改 `tycontrols.lpk` / `tests/tytests.lpr`。** 本机 MSYS 的 `sed` 读 CRLF 文件会吞掉 `\r`，整文件被转成 LF、炸出巨大 diff。要脚本化就用 Python 二进制读写，或者直接用编辑工具。
12. **换主题只广播一次裸 `Invalidate`**（`Controller.pas:665-687`），没有 StyleChanged 钩子。凡是缓存了主题值又影响布局的，都要在 `Invalidate` 重写里查缓存键（`ScrollBar.pas:616-657, 992-1028` 是范本）。

---

## 跑测试的固定套路

改了 `source/` 之后**必须**：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi
```

跑（**exe 必须是唯一名**——另外两个会话也在跑 `tytests.exe`，按镜像名杀会互相掐掉；本 worktree 一律用 `tytests-31.exe`）：

```bash
cd /d/Projects/ty-3.1/tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowGeometryTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

**判据是 `Number of run tests` 那一行存在且 errors/failures 为 0，不是 exit code。** 输出为空 = 这次跑丢了，重跑，别读成通过。

全量要写 `--all`（**不能**只是把 `--suite=...` 去掉——不带参数的 runner 只打印 usage 然后 exit 0，正好伪装成「跑丢了」）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

## 关于「有的测试给的是判据不是代码」

纯计算的（几何、token、尺寸推导）本计划直接写死测试代码。**涉及时序、手势、焦点、像素的，写的是判据加「哪个变异必须让它变红」**——实现还不存在时隔空写出来的时序测试，本库有过 7 条里 3 条是假守卫的记录（断在「武装」那一刻等于没断言）。这类测试按判据现写，写完先跑变异确认它真的在守。

**探针属性**（`TickForTest`、`IsDraggingForTest`、`DropSlotForTest`、`NoDesignVisibleAtLastShow`）只能是**真实状态的只读视图**，绝不能另开一条测试专用的计算路径——否则把接线变异掉，测试照样绿。加一个探针前先问：「没人调用真实路径的话，这条测试会红吗？」

**变异验证**（仓库里没有变异脚本，就是手工三拍）：改一行 → `lazbuild -B` 重编 → 重跑该 suite **必须红** → 改回来 → 重编重跑确认绿。收割源码不还原 exe，所以**每次都要重编**，否则「全量红 + 单跑绿」是二进制陈旧不是抖动。CRLF 文件上用 LF 搜索串替换会静默 no-op，改完先 `git diff` 确认真的改到了。

---

### Task 0: 空单元 + 包登记 + 第一个测试单元

**Files:**
- Create: `source/tyControls.ToolWindows.pas`
- Modify: `tycontrols.lpk`
- Create: `tests/test.toolwindow.geometry.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 建单元骨架（只有类型、常量和四个空类）**

```pascal
unit tyControls.ToolWindows;
{$mode objfpc}{$H+}

{ IDE 工作台的侧栏 / 底栏。设计定稿见
  docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md。
  四个类同在一个单元:窗口与栏互相引用,拆单元只会多一圈前向声明。 }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Base, tyControls.Component;

const
  { 长度 token。经典值必须等于这里的 Def —— light.tycss 的 :root 里写同一个数,
    不然加 token 这一步会悄悄给控件换一套尺寸。 }
  TyToolWindowHeaderHeightVar = '--toolwindow-header-height';
  TyToolWindowHeaderHeightDef = 26;
  TyToolWindowHeaderPadVar    = '--toolwindow-header-pad';
  TyToolWindowHeaderPadDef    = 6;
  TyToolWindowHeaderGapVar    = '--toolwindow-header-gap';
  TyToolWindowHeaderGapDef    = 4;
  TyToolWindowTabPadVar       = '--toolwindow-tab-pad';
  TyToolWindowTabPadDef       = 10;
  TyToolWindowTabAreaMinVar   = '--toolwindow-tab-area-min';
  TyToolWindowTabAreaMinDef   = 50;
  TyToolWindowIndicatorSizeVar = '--toolwindow-indicator-size';
  TyToolWindowIndicatorSizeDef = 2;
  TyToolWindowStripIndicatorSizeVar = '--toolwindow-strip-indicator-size';
  TyToolWindowStripIndicatorSizeDef = 2;
  TyToolWindowButtonSizeVar   = '--toolwindow-button-size';
  TyToolWindowButtonSizeDef   = 22;
  TyToolWindowGlyphSizeVar    = '--toolwindow-glyph-size';
  TyToolWindowGlyphSizeDef    = 16;
  TyToolWindowContentMinVar   = '--toolwindow-content-min';
  TyToolWindowContentMinDef   = 120;
  TyToolWindowStripSizeVar    = '--toolwindow-strip-size';
  TyToolWindowStripSizeDef    = 36;
  TyToolWindowStripItemSizeVar = '--toolwindow-strip-item-size';
  TyToolWindowStripItemSizeDef = 36;
  TyToolWindowEdgeSizeVar     = '--toolwindow-edge-size';
  TyToolWindowEdgeSizeDef     = 4;
  TyToolWindowDropSizeVar     = '--toolwindow-drop-size';
  TyToolWindowDropSizeDef     = 2;

  { 展开尺寸的出厂值。侧栏与底栏共用一个数:Pascal 的 published default 只能是常量,
    按 Placement 分两个数会让 .lfm 省略掉其中一侧的值、加载后变成另一侧的默认。
    名字不叫 ...Def —— 本库的 ...Var / ...Def 成对只用于「主题 token 与它的回落值」。 }
  TyToolWindowDefaultExpandedSize = 240;

  { 拖动阈值(逻辑像素)与点击防抖(毫秒)。 }
  TyToolWindowDragThresholdPx = 6;
  TyToolWindowClickGuardMs     = 300;

type
  TTyToolWindowPlacement = (twpLeft, twpRight, twpBottom);
  TTyToolWindowHeaderMode = (twhNone, twhSide, twhBottom);

  TTyToolWindowBar = class;
  TTyToolWindowActions = class;
  TTyToolWindowManager = class;

  { GetStyleTypeKey 在 TTyCustomControl 上是 abstract,不覆写就等于注册了一个
    「一解析样式就抛 EAbstractError」的类 —— 而 RegisterClass 已经把它交给流式化了。
    类型键是契约不是实现,A 期就钉死。 }
  TTyToolWindow = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  TTyToolWindowActions = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  TTyToolWindowBar = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  { A 期只建壳:栏的 Manager 属性要到 C 期才接线,但类名先占住,
    免得 B 期的测试和 .lfm 里写出两个名字。
    继承 TTyComponent(不是 TComponent):全库非可视组件都从它来,它带着
    对象查看器里那个只读 Version。 }
  TTyToolWindowManager = class(TTyComponent)
  end;

implementation

initialization
  { 运行时 .lfm 按类名实例化流里的子对象,四个都要注册。 }
  RegisterClass(TTyToolWindow);
  RegisterClass(TTyToolWindowActions);
  RegisterClass(TTyToolWindowBar);
  RegisterClass(TTyToolWindowManager);
end.
```

- [ ] **Step 2: 登记进 `tycontrols.lpk`**

在 `<Item>` 列表里 `tyControls.ListGroupPanel` 那条后面插入（**本仓库的 `<Files>` 没有 Count 属性，不要去改计数**）：

```xml
      <Item>
        <Filename Value="source/tyControls.ToolWindows.pas"/>
        <UnitName Value="tyControls.ToolWindows"/>
      </Item>
```

- [ ] **Step 3: 建第一个测试单元，先只钉「单元能编、类能实例化」**

`tests/test.toolwindow.geometry.pas`：

```pascal
unit test.toolwindow.geometry;
{$mode objfpc}{$H+}
interface
uses
  Classes, fpcunit, testregistry,
  tyControls.ToolWindows;

type
  TTyToolWindowGeometryTests = class(TTestCase)
  published
    procedure TestEveryClassIsRegisteredForStreaming;
  end;

implementation

procedure TTyToolWindowGeometryTests.TestEveryClassIsRegisteredForStreaming;
begin
  { 这一条守的正是本任务交付的东西:漏掉任何一句 RegisterClass,读 .lfm 时按类名
    就找不到类。断言常量等于它自己写的字面量是同义反复,不要那么写。 }
  AssertNotNull('TTyToolWindow 必须注册', GetClass('TTyToolWindow'));
  AssertNotNull('TTyToolWindowActions 必须注册', GetClass('TTyToolWindowActions'));
  AssertNotNull('TTyToolWindowBar 必须注册', GetClass('TTyToolWindowBar'));
  AssertNotNull('TTyToolWindowManager 必须注册', GetClass('TTyToolWindowManager'));
end;

initialization
  RegisterTest(TTyToolWindowGeometryTests);
end.
```

- [ ] **Step 4: 挂进 `tests/tytests.lpr` 的 uses**

在 `test.treeselect, test.cascader, test.popover,` 这一行后面加一行（**`tests/tytests.lpi` 不用动**，它的 `<Units>` 里只有 .lpr 本身）：

```pascal
  test.toolwindow.geometry,
```

- [ ] **Step 5: 编译并跑这一条**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowGeometryTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

Expected：`Number of run tests: 1`，errors/failures 都是 0。**变异确认**：注释掉任何一句 `RegisterClass`，重编重跑必须红。

- [ ] **Step 6: 跑一次 release 守卫，确认 .lpk 登记生效**

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-31.exe --suite=TReleaseManifestTest --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

（suite 名写错的后果是 `No tests selected.` + exit 0 + grep 无输出——看着像「跑丢了」，其实是跑错了。名字以 `tests/` 里 `RegisterTest(...)` 注册的类名为准。）

Expected：0 errors / 0 failures。**把 Step 2 的那个 `<Item>` 临时删掉重跑，这条必须红**（这是新单元漏进包的唯一守卫），红了再加回来。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tycontrols.lpk tests/test.toolwindow.geometry.pas tests/tytests.lpr && git commit -m "feat(toolwindows): unit skeleton, token constants and package entry

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 1: 主题——16 个类型键、14 个长度 token、12 个颜色 token

**Files:**
- Modify: `themes/light.tycss`
- Modify: `source/tyControls.DensityPack.pas`
- Modify: `tests/test.themes.pas`
- Create: `tests/test.toolwindow.theme.pas`
- Modify: `tests/tytests.lpr`
- Regenerate: `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`

- [ ] **Step 1: 先验生成器忠实度（在动 light.tycss 之前）**

```bash
cd /d/Projects/ty-3.1 && git checkout HEAD -- themes/light.tycss && powershell -File scripts/gen-defaulttheme.ps1 && git diff --quiet -- source/tyControls.DefaultTheme.pas && echo FAITHFUL
```

Expected：打印 `FAITHFUL`。**不是 FAITHFUL 就停下来**——生成器会整体覆写那个单元，曾经吃掉过手写代码，先查清楚再继续。

- [ ] **Step 2: 颜色 token 写进 light.tycss 的 MAP / ALIAS 段（第 14-60 行那一片）**

```css
  /* 工具窗口(IDE 侧栏/底栏)。底色只引用皮肤已经定义好的 surface / chrome 令牌,
     绝不在这里自己写 darken(--surface, ...) —— 那会绕过白底皮肤自定义的 chrome 值。 */
  --toolwindow-bg:                  var(--surface);
  --toolwindow-header-bg:           var(--toolwindow-bg);
  --toolwindow-caption-ink:         var(--on-surface);
  --toolwindow-tab-ink:             var(--muted);
  --toolwindow-tab-ink-active:      var(--on-surface);
  --toolwindow-indicator-color:     var(--accent);
  --toolwindow-strip-bg:            var(--chrome-bar-bg);
  --toolwindow-strip-ink:           var(--muted);
  --toolwindow-strip-ink-active:    var(--on-surface);
  --toolwindow-strip-indicator-color: var(--accent);
  --toolwindow-edge-color:          var(--border);
  --toolwindow-drop-color:          var(--accent);
```

- [ ] **Step 3: 长度 token 写进 :root 的几何段（按字母序，落在 `--titlebar-padding` 和 `--transfer-arrow-margin` 之间）**

```css
  --toolwindow-button-size: 22px;
  --toolwindow-content-min: 120px;
  --toolwindow-drop-size: 2px;
  --toolwindow-edge-size: 4px;
  --toolwindow-glyph-size: 16px;
  --toolwindow-header-gap: 4px;
  --toolwindow-header-height: 26px;
  --toolwindow-header-pad: 6px;
  --toolwindow-indicator-size: 2px;
  --toolwindow-strip-indicator-size: 2px;
  --toolwindow-strip-item-size: 36px;
  --toolwindow-strip-size: 36px;
  --toolwindow-tab-area-min: 50px;
  --toolwindow-tab-pad: 10px;
```

每个数都必须等于 Task 0 里的 `...Def` 常量。

- [ ] **Step 4: 16 个类型键的基础规则，写在 light.tycss 末尾（「Keys the CODE resolves that this file deliberately does NOT define」那段注释之前）**

```css
/* 工具窗口(IDE 侧栏/底栏)。容器键写全整套属性 —— 皮肤只要给某个 typeKey 写了任何一条
   规则,基础层这一整个键(含 variant)就被压掉,所以容器不能只写半套;只带墨色的子部件
   故意不写 background,好让它继承容器的表面。 */
TyToolWindowBar    { background: var(--toolwindow-bg); color: var(--on-surface);
                     font-size: var(--font-size-base); }
TyToolWindow       { background: var(--toolwindow-bg); color: var(--on-surface);
                     font-size: var(--font-size-base); }
TyToolWindowStrip  { background: var(--toolwindow-strip-bg); color: var(--toolwindow-strip-ink); }
TyToolWindowStripItem          { color: var(--toolwindow-strip-ink); }
TyToolWindowStripItem:hover    { background: var(--overlay-hover); color: var(--toolwindow-strip-ink-active); }
TyToolWindowStripItem:selected { color: var(--toolwindow-strip-ink-active); }
TyToolWindowStripItem:active   { background: var(--overlay-hover); }
TyToolWindowStripIndicator     { background: var(--toolwindow-strip-indicator-color); }
TyToolWindowEdge        { background: var(--toolwindow-edge-color); }
TyToolWindowEdge:hover  { background: var(--accent); }
TyToolWindowEdge:active { background: var(--accent); }
TyToolWindowHeader      { background: var(--toolwindow-header-bg); color: var(--toolwindow-caption-ink);
                          font-size: var(--font-size-base); padding: var(--toolwindow-header-pad); }
TyToolWindowActions     { background: var(--toolwindow-header-bg); }
TyToolWindowTabRow      { background: var(--toolwindow-header-bg); }
TyToolWindowTab          { color: var(--toolwindow-tab-ink); padding: var(--toolwindow-tab-pad); }
TyToolWindowTab:hover    { color: var(--toolwindow-tab-ink-active); }
TyToolWindowTab:selected { color: var(--toolwindow-tab-ink-active); }
TyToolWindowTabIndicator { background: var(--toolwindow-indicator-color); }
TyToolWindowOverflow        { color: var(--toolwindow-tab-ink); }
TyToolWindowOverflow:hover  { background: var(--overlay-hover); color: var(--toolwindow-tab-ink-active); }
TyToolWindowOverflow:active { background: var(--overlay-hover); }
TyToolWindowButton        { color: var(--toolwindow-tab-ink); }
TyToolWindowButton:hover  { background: var(--overlay-hover); color: var(--toolwindow-tab-ink-active); }
TyToolWindowButton:active { background: var(--overlay-hover); }
TyToolWindowSeparator     { background: var(--border); }
TyToolWindowDropIndicator { background: var(--toolwindow-drop-color); }
TyToolWindowNote          { color: var(--muted); font-size: var(--font-size-base); }
```

- [ ] **Step 5: 现代密度取值写进 `source/tyControls.DensityPack.pas`（按字母序插进那串字符串里）**

```pascal
    '  --toolwindow-button-size: 28px;' + LineEnding +
    '  --toolwindow-content-min: 160px;' + LineEnding +
    '  --toolwindow-drop-size: 2px;' + LineEnding +
    '  --toolwindow-edge-size: 4px;' + LineEnding +
    '  --toolwindow-glyph-size: 20px;' + LineEnding +
    '  --toolwindow-header-gap: 8px;' + LineEnding +
    '  --toolwindow-header-height: 36px;' + LineEnding +
    '  --toolwindow-header-pad: 8px;' + LineEnding +
    '  --toolwindow-indicator-size: 2px;' + LineEnding +
    '  --toolwindow-strip-indicator-size: 3px;' + LineEnding +
    '  --toolwindow-strip-item-size: 44px;' + LineEnding +
    '  --toolwindow-strip-size: 48px;' + LineEnding +
    '  --toolwindow-tab-area-min: 60px;' + LineEnding +
    '  --toolwindow-tab-pad: 12px;' + LineEnding +
```

（高度 ×1.4、图标槽 ×1.25、大布局宽 ×1.2、内距走 4px 尺度——和这个单元头注释里写的规律一致。）

- [ ] **Step 6: 跑两个生成器**

```bash
cd /d/Projects/ty-3.1 && powershell -File scripts/gen-defaulttheme.ps1 && powershell -File scripts/gen-tycss-catalog.ps1 && git status --short
```

Expected：`source/tyControls.DefaultTheme.pas` 和 `source/tyControls.Css.Catalog.pas` 两个都被改动。
**不用跑 `gen-builtinthemes.ps1`**——这次没动 `themes/auto.tycss` / `system.tycss` / `themes/builtin/*`。

- [ ] **Step 7: 写 token 链路守卫（新测试单元）**

`tests/test.toolwindow.theme.pas`：

```pascal
unit test.toolwindow.theme;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.ToolWindows;

type
  TTyToolWindowThemeTests = class(TTestCase)
  published
    procedure TestEveryLengthTokenIsDeclaredAndEqualsTheControlDefault;
    procedure TestSurfaceKeysReachEveryBuiltinTheme;
    procedure TestStripItemSelectedDiffersFromRest;
  end;

implementation

type
  TTokenCase = record Name: string; Def: Integer; end;

const
  CTokens: array[0..13] of TTokenCase = (
    (Name: TyToolWindowButtonSizeVar;         Def: TyToolWindowButtonSizeDef),
    (Name: TyToolWindowContentMinVar;         Def: TyToolWindowContentMinDef),
    (Name: TyToolWindowDropSizeVar;           Def: TyToolWindowDropSizeDef),
    (Name: TyToolWindowEdgeSizeVar;           Def: TyToolWindowEdgeSizeDef),
    (Name: TyToolWindowGlyphSizeVar;          Def: TyToolWindowGlyphSizeDef),
    (Name: TyToolWindowHeaderGapVar;          Def: TyToolWindowHeaderGapDef),
    (Name: TyToolWindowHeaderHeightVar;       Def: TyToolWindowHeaderHeightDef),
    (Name: TyToolWindowHeaderPadVar;          Def: TyToolWindowHeaderPadDef),
    (Name: TyToolWindowIndicatorSizeVar;      Def: TyToolWindowIndicatorSizeDef),
    (Name: TyToolWindowStripIndicatorSizeVar; Def: TyToolWindowStripIndicatorSizeDef),
    (Name: TyToolWindowStripItemSizeVar;      Def: TyToolWindowStripItemSizeDef),
    (Name: TyToolWindowStripSizeVar;          Def: TyToolWindowStripSizeDef),
    (Name: TyToolWindowTabAreaMinVar;         Def: TyToolWindowTabAreaMinDef),
    (Name: TyToolWindowTabPadVar;             Def: TyToolWindowTabPadDef));

  CSurfaceKeys: array[0..3] of string = (
    'TyToolWindowBar', 'TyToolWindow', 'TyToolWindowStrip', 'TyToolWindowHeader');

function ThemePath(const AFile: string): string;
begin
  { 不能写死相对路径:测试跑起来时的当前目录不一定是 tests/。照 test.themes.pas 的写法,
    从 exe 位置往上一级找 themes/。 }
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AFile;
end;

procedure TTyToolWindowThemeTests.TestEveryLengthTokenIsDeclaredAndEqualsTheControlDefault;
const
  cSentinel = -12345;
var
  m: TTyStyleModel;
  i, got: Integer;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    for i := 0 to High(CTokens) do
    begin
      got := m.ResolveMetric(CTokens[i].Name, cSentinel);
      AssertTrue(CTokens[i].Name + ' 必须在 light.tycss 的 :root 里声明 —— 拿回哨兵值'
        + '说明它压根没定义,或者解析不成长度', got <> cSentinel);
      AssertEquals(CTokens[i].Name + ' 的经典值必须等于控件常量', CTokens[i].Def, got);
    end;
  finally
    m.Free;
  end;
end;

procedure TTyToolWindowThemeTests.TestSurfaceKeysReachEveryBuiltinTheme;
var
  c: TTyStyleController;
  names: TStringArray;
  i, k, md: Integer;
  mode: string;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('有内置主题可查', Length(names) > 0);
    for i := 0 to High(names) do
      for md := 0 to 1 do
      begin
        if md = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        for k := 0 to High(CSurfaceKeys) do
          AssertTrue(Format('%s/%s: %s 必须经基础层拿到底色', [names[i], mode, CSurfaceKeys[k]]),
            tpBackground in c.Model.ResolveStyle(CSurfaceKeys[k], '', []).Present);
      end;
  finally
    c.Free;
  end;
end;

procedure TTyToolWindowThemeTests.TestStripItemSelectedDiffersFromRest;
var
  m: TTyStyleModel;
  rest, sel: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    rest := m.ResolveStyle('TyToolWindowStripItem', '', []);
    sel := m.ResolveStyle('TyToolWindowStripItem', '', [tysSelected]);
    AssertTrue('当前图标的墨色必须和静止态不同,否则图标条上看不出选中',
      sel.TextColor <> rest.TextColor);
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TTyToolWindowThemeTests);
end.
```

挂进 `tests/tytests.lpr` 的 uses：`test.toolwindow.theme,`。

- [ ] **Step 8: 跑这条，确认三条都绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowThemeTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

- [ ] **Step 9: 变异确认第一条真的在守**

把 light.tycss 里 `--toolwindow-strip-size: 36px;` 临时改成 `38px`，重编重跑——`TestEveryLengthTokenIsDeclaredAndEqualsTheControlDefault` **必须红**。改回来、重编、确认绿。

- [ ] **Step 10: GGRID / GMETRICS 登记 + golden 重铺**

`tests/test.themes.pas`：GGRID 的数组上界加 16（`array[0..204]` → `array[0..220]`），末尾加一段：

```pascal
    { TyToolWindow* —— IDE 工作台侧栏 / 底栏 }
    'TyToolWindowBar|', 'TyToolWindow|', 'TyToolWindowStrip|', 'TyToolWindowStripItem|',
    'TyToolWindowStripIndicator|', 'TyToolWindowEdge|', 'TyToolWindowHeader|',
    'TyToolWindowActions|', 'TyToolWindowTabRow|', 'TyToolWindowTab|',
    'TyToolWindowTabIndicator|', 'TyToolWindowOverflow|', 'TyToolWindowButton|',
    'TyToolWindowSeparator|', 'TyToolWindowDropIndicator|', 'TyToolWindowNote|');
```

GMETRICS 上界加 14（`array[0..110]` → `array[0..124]`），按字母序把 14 个 `--toolwindow-*` 插进去。

然后重铺三张 golden：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTestThemeGolden --format=plain > /tmp/t.txt 2>&1; ls golden/*.actual
```

Expected：三个 `.actual` 文件。**逐个 diff 确认是纯增量**（只多出 TyToolWindow* 和 metric 行，一条既有行都没变），确认后覆盖：

```bash
cd /d/Projects/ty-3.1/tests/golden && for f in *.actual; do mv "$f" "${f%.actual}"; done
```

再跑一次 `TTestThemeGolden`，必须全绿。

- [ ] **Step 11: 给内置主题覆盖测试补三行**

`tests/test.defaulttheme.pas` 的 `TestBuiltinCoversAllTypeKeys` 里加（**不在 test.themes.pas**）：

```pascal
  AssertBg('TyToolWindow', []);
  AssertBg('TyToolWindowBar', []);
  AssertBg('TyToolWindowStrip', []);
```

- [ ] **Step 12: 跑全量，确认没有连累别人**

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

- [ ] **Step 13: 提交**

```bash
cd /d/Projects/ty-3.1 && git add themes/light.tycss source/tyControls.DensityPack.pas source/tyControls.DefaultTheme.pas source/tyControls.Css.Catalog.pas tests/ && git commit -m "feat(toolwindows): theme keys, length and colour tokens

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: 标题行几何纯函数

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.geometry.pas`

纯函数层不认 DPI、不认主题、不认控件：调用方先把 token 缩放成设备像素再传进来（`Breadcrumb.pas` 同一套分工）。

- [ ] **Step 1: 先写失败的测试——侧栏标题行：操作区保宽、标题让位**

加进 `tests/test.toolwindow.geometry.pas`：

```pascal
procedure TTyToolWindowGeometryTests.TestSideHeaderGivesActionsItsWidthAndClipsTheCaption;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  inp := Default(TTyToolWindowHeaderInput);
  inp.Mode := twhSide;
  inp.RowWidth := 200;
  inp.RowHeight := 26;
  inp.Pad := 6;
  inp.Gap := 4;
  inp.ActionsWidth := 80;
  inp.CaptionWidth := 150;          { 想要 150,只剩 200-6-80-4-6 = 104 }
  g := TyToolWindowHeaderLayout(inp);
  AssertEquals('操作区贴右端', 200 - 6 - 80, g.Actions.Left);
  AssertEquals('操作区保住自己的宽', 80, g.Actions.Right - g.Actions.Left);
  AssertEquals('标题从左内距开始', 6, g.Caption.Left);
  AssertEquals('标题被挤到操作区左边', 200 - 6 - 80 - 4, g.Caption.Right);
end;

procedure TTyToolWindowGeometryTests.TestSideHeaderWithoutActionsPadsTheTrailingEdge;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  inp := Default(TTyToolWindowHeaderInput);
  inp.Mode := twhSide;
  inp.RowWidth := 200;
  inp.RowHeight := 26;
  inp.Pad := 6;
  inp.Gap := 4;
  inp.ActionsWidth := 0;
  inp.CaptionWidth := 40;
  g := TyToolWindowHeaderLayout(inp);
  AssertEquals('没有操作区时标题止于右内距', 200 - 6, g.Caption.Right);
  AssertTrue('没有操作区就是空矩形', g.Actions.Right <= g.Actions.Left);
end;
```

- [ ] **Step 2: 跑，确认因为「类型不存在」而编译失败**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi 2>&1 | tail -5
```

Expected：`Error: Identifier not found "TTyToolWindowHeaderInput"`。

- [ ] **Step 3: 在 interface 里声明纯几何层**

```pascal
type
  { 标题行的一个可点部件。 }
  TTyToolWindowZone = (twzNone, twzTab, twzOverflow, twzSeparator, twzMaximize, twzCollapse);

  { 一个标签 / 一个图标的槽位。ItemIndex 是**窗口序号**,不是排布序号 ——
    当前页被强制留在条上时,已排布的项不再是窗口列表的前缀。 }
  TTyToolWindowSlot = record
    ItemIndex: Integer;
    ItemRect: TRect;
  end;
  TTyToolWindowSlots = array of TTyToolWindowSlot;

  { 排布的全部输入。尺寸一律是**设备像素**,调用方缩放好再传。 }
  TTyToolWindowHeaderInput = record
    Mode: TTyToolWindowHeaderMode;
    RowWidth, RowHeight: Integer;
    Pad, Gap: Integer;
    ActionsWidth: Integer;      { 操作区 raw 首选宽;0 = 没有操作区 }
    CaptionWidth: Integer;      { 侧栏:标题想要的宽 }
    TabWidths: array of Integer;{ 底栏:每个窗口的标签想要的宽 }
    ActiveIndex: Integer;
    TabAreaMin: Integer;
    ButtonSize: Integer;        { 底栏:最大化 / 收起 }
    SeparatorWidth: Integer;
    OverflowWidth: Integer;
    RightToLeft: Boolean;
  end;

  TTyToolWindowHeaderGeom = record
    Caption: TRect;             { 侧栏 }
    Actions: TRect;
    TabArea: TRect;             { 底栏:标签可用区 }
    Tabs: TTyToolWindowSlots;   { 底栏:真正排上去的标签 }
    Overflow: TRect;
    Separator: TRect;
    Maximize: TRect;
    Collapse: TRect;
    Hidden: array of Integer;   { 底栏:收进溢出菜单的窗口序号 }
  end;

{ --- 纯规则 / 几何(无控件、无句柄、无主题,可无头测) ------------------------ }

{ 按顺序放,遇到第一个放不下的就停;当前页不在里面就追加到末尾,再从它前面一个
  开始往前挤,直到放得下。返回的是**窗口序号**的可见计划。 }
function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer; out AAnyHidden: Boolean): TTyToolWindowPlan;

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;

{ 排布的精确逆运算:只扫 Layout 自己产出的矩形。 }
function TyToolWindowZoneAt(const AGeom: TTyToolWindowHeaderGeom; X, Y: Integer;
  out AIndex: Integer; out ARect: TRect): TTyToolWindowZone;

{ 图标条 / 标签行的插入槽:按已排布项的中点分。返回 0..N 的**窗口序号**位置。 }
function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;

{ 图标条排布(竖直)。 }
function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer; out AAnyHidden: Boolean): TTyToolWindowSlots;

function TyToolWindowDragThreshold(APPI: Integer): Integer;
```

`TTyToolWindowPlan = array of Integer;` 也加进 type 段。

- [ ] **Step 4: 实现侧栏那一支（够让 Step 1 的两条变绿）**

```pascal
function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;
var
  pad, gap, aw, x: Integer;
begin
  Result := Default(TTyToolWindowHeaderGeom);
  Result.Tabs := nil;                { FPC 3.2 不认 SetLength 初始化 managed result }
  Result.Hidden := nil;
  if (AInput.RowWidth <= 0) or (AInput.RowHeight <= 0) then Exit;
  pad := AInput.Pad; if pad < 0 then pad := 0;
  gap := AInput.Gap; if gap < 0 then gap := 0;
  aw := AInput.ActionsWidth; if aw < 0 then aw := 0;
  if aw > AInput.RowWidth - pad then aw := AInput.RowWidth - pad;

  if aw > 0 then
    Result.Actions := Rect(AInput.RowWidth - pad - aw, 0, AInput.RowWidth - pad, AInput.RowHeight);

  if AInput.Mode = twhSide then
  begin
    if aw > 0 then x := Result.Actions.Left - gap
    else x := AInput.RowWidth - pad;      { 没有操作区,尾端补一个内距 }
    if x > pad then
      Result.Caption := Rect(pad, 0, x, AInput.RowHeight);
    { 标题想要的宽小于可用宽时不拉伸:DrawText 左对齐、必要时自己出省略号。 }
    if (AInput.CaptionWidth > 0)
       and (Result.Caption.Left + AInput.CaptionWidth < Result.Caption.Right) then
      Result.Caption.Right := Result.Caption.Left + AInput.CaptionWidth;
  end;
  { twhBottom 那一支在 B 期实现;twhNone 什么都不排。 }
end;
```

- [ ] **Step 5: 跑，两条必须绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowGeometryTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

- [ ] **Step 6: 写图标条排布 + 槽位的失败测试**

```pascal
procedure TTyToolWindowGeometryTests.TestStripKeepsTheActiveIconWhenItOverflows;
var
  slots: TTyToolWindowSlots;
  hidden: Boolean;
  i, seen: Integer;
begin
  { 高度 150、每项 36、溢出按钮 36 —— 放得下 3 项 + 溢出按钮。当前页是第 8 个。 }
  slots := TyToolWindowStripLayout(36, 150, 36, 36, 10, 8, hidden);
  AssertTrue('十个图标放不下,必须报溢出', hidden);
  seen := -1;
  for i := 0 to High(slots) do
    if slots[i].ItemIndex = 8 then seen := i;
  AssertTrue('当前页的图标必须留在条上', seen >= 0);
  AssertEquals('当前页被追加到末尾', High(slots), seen);
end;

procedure TTyToolWindowGeometryTests.TestSlotAtMapsGapsToWindowIndexes;
var
  slots: TTyToolWindowSlots;
  hidden: Boolean;
begin
  slots := TyToolWindowStripLayout(36, 200, 36, 36, 4, 0, hidden);
  AssertFalse('四个图标放得下', hidden);
  AssertEquals('第一个图标的上半 → 插到它前面', 0,
    TyToolWindowSlotAt(slots, 18, slots[0].ItemRect.Top + 4, True, 4));
  AssertEquals('第一个图标的下半 → 插到它后面', 1,
    TyToolWindowSlotAt(slots, 18, slots[0].ItemRect.Bottom - 4, True, 4));
  AssertEquals('最后一个图标之后 → 末尾', 4,
    TyToolWindowSlotAt(slots, 18, slots[3].ItemRect.Bottom + 2, True, 4));
end;
```

- [ ] **Step 7: 实现 `TyToolWindowVisiblePlan` / `TyToolWindowStripLayout` / `TyToolWindowSlotAt`**

```pascal
function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer; out AAnyHidden: Boolean): TTyToolWindowPlan;

  function Fill(ABudget: Integer): TTyToolWindowPlan;
  var
    i, used: Integer;
  begin
    Result := nil;
    used := 0;
    for i := 0 to High(AWidths) do
    begin
      if used + AWidths[i] > ABudget then Break;   { 遇到第一个放不下的就停 }
      Inc(used, AWidths[i]);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := i;
    end;
  end;

  function Has(const APlan: TTyToolWindowPlan; AIdx: Integer): Boolean;
  var i: Integer;
  begin
    Result := False;
    for i := 0 to High(APlan) do
      if APlan[i] = AIdx then Exit(True);
  end;

  function Width(const APlan: TTyToolWindowPlan): Integer;
  var i: Integer;
  begin
    Result := 0;
    for i := 0 to High(APlan) do Inc(Result, AWidths[APlan[i]]);
  end;

var
  plan: TTyToolWindowPlan;
  budget, i: Integer;
begin
  Result := nil;
  AAnyHidden := False;
  if Length(AWidths) = 0 then Exit;
  if AAvail <= 0 then
  begin
    AAnyHidden := True;
    Exit;
  end;
  plan := Fill(AAvail);
  AAnyHidden := Length(plan) < Length(AWidths);
  if AAnyHidden then
  begin
    { 确实有东西被收起来了,才给溢出按钮留位置,然后重排一次。 }
    budget := AAvail - AOverflowWidth;
    if budget < 0 then budget := 0;
    plan := Fill(budget);
    { 当前页强制留在行上:追加到末尾,再从它前面一个开始往前挤。 }
    if (AActiveIndex >= 0) and (AActiveIndex <= High(AWidths)) and not Has(plan, AActiveIndex) then
    begin
      SetLength(plan, Length(plan) + 1);
      plan[High(plan)] := AActiveIndex;
      i := Length(plan) - 2;
      while (i >= 0) and (Width(plan) > budget) do
      begin
        Delete(plan, i, 1);
        Dec(i);
      end;
    end;
    AAnyHidden := Length(plan) < Length(AWidths);
  end;
  Result := plan;
end;

function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer; out AAnyHidden: Boolean): TTyToolWindowSlots;
var
  widths: array of Integer;
  plan: TTyToolWindowPlan;
  i, y: Integer;
begin
  Result := nil;
  AAnyHidden := False;
  if (ACount <= 0) or (AItemSize <= 0) or (AStripHeight <= 0) then Exit;
  SetLength(widths, ACount);
  for i := 0 to ACount - 1 do widths[i] := AItemSize;   { 图标是方的,等宽 }
  plan := TyToolWindowVisiblePlan(AStripHeight, widths, AActiveIndex, AOverflowSize, AAnyHidden);
  SetLength(Result, Length(plan));
  y := 0;
  for i := 0 to High(plan) do
  begin
    Result[i].ItemIndex := plan[i];
    Result[i].ItemRect := Rect(0, y, AStripWidth, y + AItemSize);
    Inc(y, AItemSize);
  end;
end;

function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;
var
  i, mid, pos: Integer;
begin
  { 已排布项不一定是窗口列表的前缀(当前页被强制留下),所以空隙映射到**它对应窗口的序号**,
    不是排布序号。 }
  Result := ACount;
  if Length(ASlots) = 0 then Exit;
  for i := 0 to High(ASlots) do
  begin
    if AVertical then
    begin
      mid := (ASlots[i].ItemRect.Top + ASlots[i].ItemRect.Bottom) div 2;
      pos := Y;
    end
    else
    begin
      mid := (ASlots[i].ItemRect.Left + ASlots[i].ItemRect.Right) div 2;
      pos := X;
    end;
    if pos < mid then Exit(ASlots[i].ItemIndex);
  end;
  Result := ASlots[High(ASlots)].ItemIndex + 1;
end;

function TyToolWindowDragThreshold(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := MulDiv(TyToolWindowDragThresholdPx, APPI, 96);
  if Result < 1 then Result := 1;
end;
```

`Delete` 用于动态数组要 uses `SysUtils`（已在）；FPC 3.2 支持 `Delete(dynarray, idx, cnt)`。

- [ ] **Step 8: 跑，四条全绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowGeometryTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

- [ ] **Step 9: 变异确认「当前页强制留下」这条真的在守**

把 `TyToolWindowVisiblePlan` 里那段 `if (AActiveIndex >= 0) and ... not Has(plan, AActiveIndex)` 整块注释掉，重编重跑——`TestStripKeepsTheActiveIconWhenItOverflows` **必须红**。改回来、重编、确认绿。

- [ ] **Step 10: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.geometry.pas && git commit -m "feat(toolwindows): pure header and strip geometry

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `TTyToolWindow` 本体（标题行 + 正文 + 绘制缓存）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.window.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试——正文在标题行下面**

`tests/test.toolwindow.window.pas`：

```pascal
unit test.toolwindow.window;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Panel, tyControls.ToolWindows;

type
  TWinAccess = class(TWinControl);

  TTyToolWindowTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyToolWindowBar;
    FWin: TTyToolWindow;
    procedure ForceAlign(AHost: TWinControl);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBodyStartsBelowTheHeaderRow;
  end;

implementation

procedure TTyToolWindowTests.SetUp;
begin
  { 控件必须有父控件并自带 controller,否则读的是进程级主题:单跑绿、全量红。 }
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(FForm);
  FBar := TTyToolWindowBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.SetBounds(0, 0, 240, 400);
  FWin := TTyToolWindow.Create(FForm);
  FWin.Parent := FBar;
end;

procedure TTyToolWindowTests.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TTyToolWindowTests.ForceAlign(AHost: TWinControl);
var
  r: TRect;
begin
  { 没 Show 的窗体上 LCL 跳过 AutoSize/Realign,但对齐引擎本身照样能跑。 }
  r := Rect(0, 0, AHost.Width, AHost.Height);
  TWinAccess(AHost).AdjustClientRect(r);
  TWinAccess(AHost).AlignControls(nil, r);
end;

procedure TTyToolWindowTests.TestBodyStartsBelowTheHeaderRow;
var
  body: TRect;
  hdr: Integer;
begin
  FWin.SetBounds(0, 0, 200, 300);
  hdr := FWin.HeaderHeightPx;
  AssertTrue('标题行要有高度', hdr > 0);
  body := FWin.ClientRect;
  TWinAccess(FWin).AdjustClientRect(body);
  AssertEquals('正文从标题行下面开始', hdr, body.Top);
  AssertEquals('标题行矩形就是上面那一条', hdr, FWin.HeaderRowRect.Bottom);
end;

initialization
  RegisterClasses([TTyToolWindowBar, TTyToolWindow, TTyToolWindowActions]);
  RegisterTest(TTyToolWindowTests);
end.
```

挂进 `tests/tytests.lpr`：`test.toolwindow.window,`。

- [ ] **Step 2: 跑，确认编译失败在 `HeaderHeightPx`**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi 2>&1 | tail -5
```

- [ ] **Step 3: 实现工具窗口的类声明**

```pascal
  TTyToolWindow = class(TTyCustomControl)
  private
    FImageName: string;
    FImageIndex: Integer;
    FStripHint: string;
    FPaintCacheDummy: Boolean;
    FHeaderPxCache: Integer;
    FHeaderPxPPI: Integer;
    FHeaderPxVer: Cardinal;
    FHeaderPxAnchor: TObject;
    FHeaderPxRTL: Boolean;
    FHeaderPxMode: TTyToolWindowHeaderMode;
    FRelayouting: Boolean;
    function ImageIndexIsStored: Boolean;
    function GetBar: TTyToolWindowBar;
    function GetActions: TTyToolWindowActions;
  protected
    FPaintCache: TTyPaintCache;      { protected:测试要能问「重渲染了没有」 }
    function GetStyleTypeKey: string; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure SetParent(AParent: TWinControl); override;
    procedure CustomAlignPosition(AControl: TControl;
      var ANewLeft, ANewTop, ANewWidth, ANewHeight: Integer;
      var AAlignRect: TRect; AAlignInfo: TAlignInfo); override;
    procedure AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
      const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer); override;
    procedure CMBiDiModeChanged(var Msg: TLMessage); message CM_BIDIMODECHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    procedure Paint; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure RelayoutHeader;
    function HeaderMode: TTyToolWindowHeaderMode;
    function HeaderHeightPx: Integer;
    function HeaderRowRect: TRect;
    function BodyRect: TRect;
    property Bar: TTyToolWindowBar read GetBar;
    property Actions: TTyToolWindowActions read GetActions;
  published
    property Caption;
    property ImageName: string read FImageName write FImageName;
    property ImageIndex: Integer read FImageIndex write FImageIndex
      stored ImageIndexIsStored default -1;
    property StripHint: string read FStripHint write FStripHint;
    property StyleClass;
    { 栏推给窗口、窗口再推给操作区;不进 .lfm(读进来的时机在注册之后,两边会漂开)。 }
    property Controller stored False;
    property Left stored False;
    property Top stored False;
    property Width stored False;
    property Height stored False;
    property TabOrder stored False;
    property Visible stored False;
    property OnShow;
    property OnHide;
  end;
```

`OnShow` / `OnHide` 在 `TTyCustomControl` 上没有现成的，要在 private 段加 `FOnShow, FOnHide: TNotifyEvent;` 并 published 出去，由栏在切换时调用（Task 5 Step 7）。

- [ ] **Step 4: 实现构造、样式键、标题行高与缓存键**

```pascal
constructor TTyToolWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 多击两个标志:底栏标题行的按下落在窗口的句柄上,LCL 数点击次数看的是收到消息的
    那个窗口化控件;不加的话第三次按下会被还原成普通按下,又生效一次。 }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds,
    csNoDesignVisible, csNoFocus, csTripleClicks, csQuadClicks];
  FImageIndex := -1;
  FHeaderPxCache := -1;
  Align := alClient;
  Visible := False;
  { 构造里一个子对象都不建 —— 建了会在流式加载时翻倍。 }
end;

destructor TTyToolWindow.Destroy;
begin
  FPaintCache.Free;
  inherited Destroy;
end;

function TTyToolWindow.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindow';
end;

function TTyToolWindow.ImageIndexIsStored: Boolean;
begin
  { 名字是持久键,序号只在名字给不出答案时才进流。 }
  Result := (FImageName = '') and (FImageIndex >= 0);
end;

function TTyToolWindow.HeaderMode: TTyToolWindowHeaderMode;
begin
  { 只看所在栏的 Placement —— 不看哪页是当前页,否则切页时正文会跳。 }
  if not (Parent is TTyToolWindowBar) then Exit(twhNone);
  if TTyToolWindowBar(Parent).Placement = twpBottom then Result := twhBottom
  else Result := twhSide;
end;

function TTyToolWindow.HeaderHeightPx: Integer;
var
  mdl: TTyStyleModel;
  ver: Cardinal;
  mode: TTyToolWindowHeaderMode;
  tokenPx, actionsPx: Integer;
begin
  mode := HeaderMode;
  if mode = twhNone then Exit(0);
  mdl := ActiveController.Model;
  ver := mdl.ThemeVersion;
  { 键里既要版本号也要 model 身份:版本号是每个 model 各自算的,只按版本号键控
    会把 A 的值端给 B —— Controller 是 published,中途换得掉。 }
  if (FHeaderPxAnchor <> TObject(mdl)) or (FHeaderPxVer <> ver)
     or (FHeaderPxPPI <> Font.PixelsPerInch) or (FHeaderPxRTL <> UseRightToLeftAlignment)
     or (FHeaderPxMode <> mode) or (FHeaderPxCache < 0) then
  begin
    FHeaderPxCache := MulDiv(ActiveController.Metric(TyToolWindowHeaderHeightVar,
      TyToolWindowHeaderHeightDef), Font.PixelsPerInch, 96);
    FHeaderPxAnchor := TObject(mdl);
    FHeaderPxVer := ver;
    FHeaderPxPPI := Font.PixelsPerInch;
    FHeaderPxRTL := UseRightToLeftAlignment;
    FHeaderPxMode := mode;
  end;
  tokenPx := FHeaderPxCache;
  { 操作区那一项**不缓存**:子控件增删 / 显隐 / 改尺寸都会触发整窗体自顶向下重排,
    现取就能跟上。底栏模式下由栏统一算(B 期),A 期两种模式都按本窗口算。 }
  actionsPx := 0;
  if Actions <> nil then actionsPx := Actions.RawPreferredHeight;
  if actionsPx > tokenPx then Result := actionsPx else Result := tokenPx;
  if Result < 1 then Result := 1;
end;

function TTyToolWindow.HeaderRowRect: TRect;
begin
  Result := Rect(0, 0, ClientWidth, HeaderHeightPx);
end;

function TTyToolWindow.BodyRect: TRect;
begin
  { 查询就调自己的 AdjustClientRect —— 正文区只有一个定义,手摆和对齐摆落在同一处。 }
  Result := ClientRect;
  AdjustClientRect(Result);
end;

procedure TTyToolWindow.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Top, HeaderHeightPx);
  if ARect.Top > ARect.Bottom then ARect.Top := ARect.Bottom;
end;
```

- [ ] **Step 5: 跑第一条，必须绿**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
```

- [ ] **Step 6: 写「换主题要重排、不只是重画」的失败测试**

```pascal
procedure TTyToolWindowTests.TestThemeChangeRelayoutsTheBody;
var
  before, after: Integer;
  body: TRect;
begin
  FWin.SetBounds(0, 0, 200, 300);
  before := FWin.HeaderHeightPx;
  FCtl.StyleOverride := ':root { --toolwindow-header-height: 48px; }';
  after := FWin.HeaderHeightPx;
  AssertTrue('换主题后标题行必须变高', after > before);
  body := FWin.ClientRect;
  TWinAccess(FWin).AdjustClientRect(body);
  AssertEquals('正文顶跟着走', after, body.Top);
end;
```

- [ ] **Step 7: 实现 `Invalidate` / `RelayoutHeader` / DPI / RTL 三个入口**

```pascal
procedure TTyToolWindow.RelayoutHeader;
begin
  if FRelayouting then Exit;
  FRelayouting := True;
  try
    Realign;      { 客户区内缩量变了就必须重排,只 Invalidate 会让 alClient 子控件盖住标题行 }
    inherited Invalidate;
  finally
    FRelayouting := False;
  end;
end;

procedure TTyToolWindow.Invalidate;
var
  old: Integer;
begin
  { 自己的样子变了 —— 丢缓存。子控件打脏到不了这里,缓存正是靠这一点活着。 }
  if FPaintCache <> nil then FPaintCache.Drop;
  { 换主题是这个类唯一听不见的事件:广播过来的只有一个裸 Invalidate。 }
  old := FHeaderPxCache;
  FHeaderPxCache := -1;
  if (not FRelayouting) and (HeaderHeightPx <> old) and (old >= 0) then
    RelayoutHeader;
  inherited Invalidate;
end;

procedure TTyToolWindow.AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
  const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer);
begin
  inherited AutoAdjustLayout(AMode, AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth);
  FHeaderPxCache := -1;
  RelayoutHeader;
end;

procedure TTyToolWindow.CMBiDiModeChanged(var Msg: TLMessage);
begin
  inherited;
  FHeaderPxCache := -1;
  RelayoutHeader;
end;
```

- [ ] **Step 8: 跑，两条都绿；变异确认**

把 `Invalidate` 里的 `RelayoutHeader` 那一句注释掉，重编重跑——`TestThemeChangeRelayoutsTheBody` **必须红**（会停在旧的 body.Top）。改回来确认绿。

- [ ] **Step 9: 写绘制与缓存的测试（哨兵底色）**

```pascal
procedure TTyToolWindowTests.TestHeaderPaintsItsOwnSurfaceNotTheGround;
const
  Ground = TColor($FF00FF);   { 品红。绝不能用白 —— 白就是 light 主题的表面色 }
  Wipe   = TColor($00FF00);
var
  bmp: TBitmap;
  notGround, wipeLeft: Integer;
begin
  FForm.Color := Ground;
  FWin.SetBounds(0, 0, 120, 80);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(120, 80);
    bmp.Canvas.Brush.Color := Wipe;
    bmp.Canvas.FillRect(0, 0, 120, 80);
    FWin.RenderTo(bmp.Canvas, Rect(0, 0, 120, 80), 96);
    TallyPixels(bmp, Ground, Wipe, notGround, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('整块都要画到,不许留底漆', 0, wipeLeft);
  AssertTrue('画出来的不是父背景色', notGround > 0);
end;
```

`TallyPixels` 是本单元里的一个辅助过程，照 `tests/test.scrollbar.autohide.pas:266-313` 的 `RenderAndTally` 抄（只比 RGB，绝不断言 alpha）。

- [ ] **Step 10: 实现 `RenderTo` / `Paint`**

```pascal
procedure TTyToolWindow.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, hdrS: TTyStyleSet;
  R, hdr: TRect;
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  P := TTyPainter.Create;
  try
    { painter 的位图是 W×H 并 blit 到 ARect 左上,所以内部一切坐标都用 (0,0)-local。 }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    hdr := Rect(0, 0, R.Right, HeaderHeightPx);
    if (HeaderMode = twhSide) and (hdr.Bottom > hdr.Top) then
    begin
      hdrS := ActiveController.Model.ResolveStyle('TyToolWindowHeader',
        TyStyleClassFor(Self, StyleClass), [tysNormal]);
      if tpBackground in hdrS.Present then
        P.FillBackground(hdr, hdrS.Background, 0);
      inp := Default(TTyToolWindowHeaderInput);
      inp.Mode := twhSide;
      inp.RowWidth := hdr.Right;
      inp.RowHeight := hdr.Bottom;
      inp.Pad := P.Scale(ActiveController.Metric(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef));
      inp.Gap := P.Scale(ActiveController.Metric(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef));
      if Actions <> nil then inp.ActionsWidth := Actions.RawPreferredWidth;
      inp.CaptionWidth := 0;   { 0 = 用满可用宽,DrawText 自己出省略号 }
      g := TyToolWindowHeaderLayout(inp);
      if (Caption <> '') and (g.Caption.Right > g.Caption.Left) then
        P.DrawText(g.Caption, Caption, hdrS.FontName, ResolveFontSize(hdrS),
          hdrS.FontWeight, hdrS.TextColor, taLeftJustify, tlCenter, True);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyToolWindow.Paint;
var
  w, h: Integer;
begin
  { 设计器重绘少、而且边重绘边流式化,所以只在运行时用缓存。 }
  if csDesigning in ComponentState then
  begin
    RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  w := ClientWidth; h := ClientHeight;
  if (w <= 0) or (h <= 0) then Exit;
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  if FPaintCache.NeedsRender(w, h) then
    RenderTo(FPaintCache.Canvas, Rect(0, 0, w, h), Font.PixelsPerInch);
  FPaintCache.Blit(Canvas);
end;
```

- [ ] **Step 11: 跑这一条，然后提交**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): tool window body, header row and paint cache

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `TTyToolWindowActions`（操作区）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.window.pas`

- [ ] **Step 1: 写失败的测试——空操作区宽 0、有控件按内容算**

```pascal
procedure TTyToolWindowTests.TestActionsWidthIsContentNotDefault;
var
  act: TTyToolWindowActions;
  b1, b2: TTyPanel;
begin
  act := TTyToolWindowActions.Create(FForm);
  act.Parent := FWin;
  AssertEquals('运行时没有可见子控件 → 宽 0(不是 LCL 的 75px 默认宽)',
    0, act.RawPreferredWidth);
  b1 := TTyPanel.Create(FForm); b1.Parent := act; b1.SetBounds(0, 0, 20, 18);
  b2 := TTyPanel.Create(FForm); b2.Parent := act; b2.SetBounds(0, 0, 30, 18);
  { 2×pad + 20 + 30 + 1×gap，pad/gap 取 light.tycss 的经典值 6/4 }
  AssertEquals('宽 = 2×内距 + 子控件宽之和 + (n-1)×间距',
    2 * TyToolWindowHeaderPadDef + 50 + TyToolWindowHeaderGapDef, act.RawPreferredWidth);
  b2.Visible := False;
  AssertEquals('隐藏的子控件不算',
    2 * TyToolWindowHeaderPadDef + 20, act.RawPreferredWidth);
end;

procedure TTyToolWindowTests.TestActionsSitsInTheHeaderRowAndIgnoresAlign;
var
  act: TTyToolWindowActions;
  b1: TTyPanel;
begin
  FWin.SetBounds(0, 0, 200, 300);
  act := TTyToolWindowActions.Create(FForm);
  act.Parent := FWin;
  b1 := TTyPanel.Create(FForm); b1.Parent := act; b1.SetBounds(0, 0, 40, 18);
  act.Align := alClient;        { 用户乱设也没用 }
  ForceAlign(FWin);
  AssertEquals('操作区贴标题行右端', 200 - TyToolWindowHeaderPadDef, act.Left + act.Width);
  AssertEquals('操作区在标题行里', 0, act.Top);
  AssertEquals('高度就是标题行高', FWin.HeaderHeightPx, act.Height);
end;
```

- [ ] **Step 2: 跑，确认红在 `RawPreferredWidth` 不存在**

- [ ] **Step 3: 实现操作区**

```pascal
  TTyToolWindowActions = class(TTyCustomControl)
  private
    FInLayout: Boolean;
    function PadPx: Integer;
    function GapPx: Integer;
  protected
    function GetStyleTypeKey: string; override;
    procedure SetAlign(AValue: TAlign); override;     { 钉死 alCustom }
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    function ChildClassAllowed(ChildClass: TClass): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    function RawPreferredWidth: Integer;
    function RawPreferredHeight: Integer;
  published
    property StyleClass;
    property Controller stored False;
  end;

constructor TTyToolWindowActions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 两个 KeepChild 标志:用户在对象查看器里开 AutoSize 时,LCL 的 DoAutoSize 会把
    子控件往左上挪,和这里的自排互相覆盖。 }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus,
    csAutoSizeKeepChildLeft, csAutoSizeKeepChildTop];
  inherited SetAlign(alCustom);
end;

procedure TTyToolWindowActions.SetAlign(AValue: TAlign);
begin
  { 位置由所在窗口的 CustomAlignPosition 定,Align 不接受任何值。 }
  inherited SetAlign(alCustom);
end;

function TTyToolWindowActions.PadPx: Integer;
begin
  Result := MulDiv(ActiveController.Metric(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef),
    Font.PixelsPerInch, 96);
end;

function TTyToolWindowActions.GapPx: Integer;
begin
  Result := MulDiv(ActiveController.Metric(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef),
    Font.PixelsPerInch, 96);
end;

function TTyToolWindowActions.RawPreferredWidth: Integer;
var
  i, n, w: Integer;
begin
  n := 0; w := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i].Visible or (csDesigning in ComponentState) then
    begin
      Inc(n);
      Inc(w, Controls[i].Width);
    end;
  if n = 0 then Exit(0);     { raw:0 就是 0,不要让 LCL 换成 75px 默认宽 }
  Result := 2 * PadPx + w + (n - 1) * GapPx;
end;

function TTyToolWindowActions.RawPreferredHeight: Integer;
var
  i, h, ch: Integer;
begin
  h := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i].Visible or (csDesigning in ComponentState) then
    begin
      ch := Controls[i].Height;
      if Controls[i].Constraints.MinHeight > ch then ch := Controls[i].Constraints.MinHeight;
      if ch > h then h := ch;
    end;
  if h = 0 then Exit(0);
  Result := h + 2 * PadPx;
end;

procedure TTyToolWindowActions.AlignControls(AControl: TControl; var ARect: TRect);
var
  i, x, n, contentW, ch, top: Integer;
  kids: array of TControl;
begin
  if FInLayout then Exit;           { 尾部改子控件尺寸会再次触发本方法 }
  FInLayout := True;
  try
    SetLength(kids, ControlCount); n := 0;
    for i := 0 to ControlCount - 1 do
      if Controls[i].Visible or (csDesigning in ComponentState) then
      begin
        kids[n] := Controls[i]; Inc(n);
      end;
    SetLength(kids, n);
    if n = 0 then Exit;
    contentW := RawPreferredWidth;
    if contentW <= Width then x := PadPx
    else x := Width - contentW + PadPx;   { 放不下就贴尾端,裁掉开头的 }
    for i := 0 to n - 1 do
    begin
      ch := kids[i].Height;
      if kids[i].Constraints.MinHeight > ch then ch := kids[i].Constraints.MinHeight;
      top := (Height - ch) div 2;
      if top < 0 then top := 0;
      kids[i].SetBounds(x, top, kids[i].Width, ch);
      Inc(x, kids[i].Width + GapPx);
    end;
  finally
    FInLayout := False;
  end;
end;
```

工具窗口一侧补上 `CustomAlignPosition`：

```pascal
procedure TTyToolWindow.CustomAlignPosition(AControl: TControl;
  var ANewLeft, ANewTop, ANewWidth, ANewHeight: Integer;
  var AAlignRect: TRect; AAlignInfo: TAlignInfo);
var
  g: TTyToolWindowHeaderGeom;
  inp: TTyToolWindowHeaderInput;
begin
  if (AControl is TTyToolWindowActions) and (AControl = Actions) and (HeaderMode <> twhNone) then
  begin
    inp := Default(TTyToolWindowHeaderInput);
    inp.Mode := HeaderMode;
    inp.RowWidth := ClientWidth;
    inp.RowHeight := HeaderHeightPx;
    inp.Pad := MulDiv(ActiveController.Metric(TyToolWindowHeaderPadVar,
      TyToolWindowHeaderPadDef), Font.PixelsPerInch, 96);
    inp.Gap := MulDiv(ActiveController.Metric(TyToolWindowHeaderGapVar,
      TyToolWindowHeaderGapDef), Font.PixelsPerInch, 96);
    inp.ActionsWidth := TTyToolWindowActions(AControl).RawPreferredWidth;
    g := TyToolWindowHeaderLayout(inp);
    ANewLeft := g.Actions.Left;
    ANewTop := g.Actions.Top;
    ANewWidth := g.Actions.Right - g.Actions.Left;
    ANewHeight := g.Actions.Bottom - g.Actions.Top;
    Exit;
  end;
  if (AControl is TTyToolWindowActions) then
  begin
    { 多出来的操作区(粘贴等途径):放到正文区左上角,不参与标题行。 }
    ANewLeft := BodyRect.Left;
    ANewTop := BodyRect.Top;
    ANewWidth := TTyToolWindowActions(AControl).RawPreferredWidth;
    ANewHeight := TTyToolWindowActions(AControl).RawPreferredHeight;
    Exit;
  end;
  inherited CustomAlignPosition(AControl, ANewLeft, ANewTop, ANewWidth, ANewHeight,
    AAlignRect, AAlignInfo);
end;
```

`GetActions` 扫 `Controls[]` 取第一个 `TTyToolWindowActions`，不缓存。

- [ ] **Step 4: 跑两条，必须绿**

- [ ] **Step 5: 变异确认「raw 宽」那条在守**

把 `RawPreferredWidth` 里的 `if n = 0 then Exit(0);` 改成 `if n = 0 then Exit(75);`，重编重跑——`TestActionsWidthIsContentNotDefault` **必须红**。改回来确认绿。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.window.pas && git commit -m "feat(toolwindows): actions area with its own flow and raw preferred size

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `TTyToolWindowBar` 状态模型（Placement、尺寸、注册、当前页、收起）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.bar.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 写失败的测试——侧栏宽度由 token 和 ExpandedSize 推出来**

`tests/test.toolwindow.bar.pas`（夹具三件套同 Task 3，`TBarAccess = class(TTyToolWindowBar)` 把 protected 的 `MouseDown/MouseMove/MouseUp/SetDesigning/RenderTo` 开成 public）：

```pascal
procedure TTyToolWindowBarTests.TestSideWidthIsStripPlusEdgePlusContent;
var
  w: TTyToolWindow;
begin
  FBar.Placement := twpLeft;
  FBar.ExpandedSize := 200;
  w := TTyToolWindow.Create(FForm);
  w.Parent := FBar;                 { 有窗口才按展开算 }
  AssertEquals('宽 = 图标条 + 2×chrome + 边缘区 + 内容',
    TyToolWindowStripSizeDef + FBar.ChromeInsetPx * 2 + TyToolWindowEdgeSizeDef + 200,
    FBar.Width);
  FBar.Collapsed := True;
  AssertEquals('收起 = 图标条 + 2×chrome',
    TyToolWindowStripSizeDef + FBar.ChromeInsetPx * 2, FBar.Width);
  AssertEquals('收起不动展开尺寸', 200, FBar.ExpandedSize);
end;

procedure TTyToolWindowBarTests.TestEmptyBarKeepsTheStripAtRunTimeAndExpandsAtDesignTime;
begin
  FBar.Placement := twpLeft;
  FBar.ExpandedSize := 200;
  AssertEquals('运行时没有窗口 = 只剩图标条',
    TyToolWindowStripSizeDef + FBar.ChromeInsetPx * 2, FBar.Width);
  TBarAccess(FBar).MarkDesigning(True);
  AssertTrue('设计期没有窗口也按展开算,否则设计器里点不中',
    FBar.Width > TyToolWindowStripSizeDef + FBar.ChromeInsetPx * 2);
end;
```

- [ ] **Step 2: 跑，确认红**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi 2>&1 | tail -5
```

- [ ] **Step 3: 实现栏的声明与尺寸推导**

```pascal
  TTyToolWindowBar = class(TTyCustomControl)
  private
    FWindows: array of TTyToolWindow;
    FPlacement: TTyToolWindowPlacement;
    FExpandedSize: Integer;
    FCollapsed: Boolean;
    FActiveIndex: Integer;
    FActive: TTyToolWindow;
    FBarSwitching: Boolean;
    FDeriving: Boolean;
    FDpiAdjusting: Boolean;
    FImages: TCustomImageList;
    FSubscribedList: TCustomImageList;    { 真正注册过 ChangeLink 的那个,可能不是 FImages }
    FTickOffset: QWord;                   { 无头测试把时钟往前推的偏移量 }
    FDragging: Boolean;                   { 图标拖动中(Task 9) }
    FDropSlot: Integer;                   { 当前插入槽,-1 = 没有(Task 9) }
    FLastClickTick: QWord;
    FLastClickWindow: TTyToolWindow;
    FOnChange, FOnCollapse, FOnExpand: TNotifyEvent;
    procedure SetPlacement(AValue: TTyToolWindowPlacement);
    procedure SetExpandedSize(AValue: Integer);
    procedure SetCollapsed(AValue: Boolean);
    procedure SetActiveIndex(AValue: Integer);
    function GetWindow(AIndex: Integer): TTyToolWindow;
    function GetWindowCount: Integer;
    procedure DeriveSize;
  protected
    function GetStyleTypeKey: string; override;
    function ChildClassAllowed(ChildClass: TClass): Boolean; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure ConstrainedResize(var MinWidth, MinHeight, MaxWidth,
      MaxHeight: TConstraintSize); override;
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RegisterWindow(AWindow: TTyToolWindow);
    procedure UnregisterWindow(AWindow: TTyToolWindow);
    procedure ActivateWindow(AWindow: TTyToolWindow);
    function ChromeInsetPx: Integer;
    function StripSizePx: Integer;
    function EdgeSizePx: Integer;
    function ContentMinLogical: Integer;   { 逻辑像素,和 ExpandedSize 同一套单位 }
    function ContentMinPx: Integer;        { = MulDiv(ContentMinLogical, PPI, 96) }
    function StripItemRect(AIndex: Integer): TRect;
    function EdgeRect: TRect;
    function IndexOfWindow(AWindow: TTyToolWindow): Integer;
    function WindowAtPos(X, Y: Integer): TTyToolWindow;
    property Windows[AIndex: Integer]: TTyToolWindow read GetWindow;
    property WindowCount: Integer read GetWindowCount;
    property ActiveWindow: TTyToolWindow read FActive write ActivateWindow;
    { 探针:全部是真实状态的只读视图(TickForTest 例外,它是把时钟往前推的偏移量),
      不许另开计算路径。 }
    property TickForTest: QWord read FTickOffset write FTickOffset;
    property IsDraggingForTest: Boolean read FDragging;
    property DropSlotForTest: Integer read FDropSlot;
  published
    property Placement: TTyToolWindowPlacement read FPlacement write SetPlacement default twpLeft;
    property ExpandedSize: Integer read FExpandedSize write SetExpandedSize
      default TyToolWindowDefaultExpandedSize;
    property Collapsed: Boolean read FCollapsed write SetCollapsed default False;
    property ActiveIndex: Integer read FActiveIndex write SetActiveIndex default -1;
    property Images: TCustomImageList read FImages write SetImages;   { Task 6 }
    property Align;
    property StyleClass;
    property Controller;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnCollapse: TNotifyEvent read FOnCollapse write FOnCollapse;
    property OnExpand: TNotifyEvent read FOnExpand write FOnExpand;
  end;
```

尺寸推导：

```pascal
function TTyToolWindowBar.ChromeInsetPx: Integer;
var
  S: TTyStyleSet;
begin
  { 用**静止态**样式:TyChromeInsetLogical 含焦点环宽度,拿 CurrentStyle 会让客户区
    随鼠标悬停抖动 —— 而悬停只 Invalidate、不 Realign。 }
  S := ActiveController.Model.ResolveStyle(GetStyleTypeKey,
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
  Result := MulDiv(TyChromeInsetLogical(S), Font.PixelsPerInch, 96);
end;

function TTyToolWindowBar.StripSizePx: Integer;
begin
  if FPlacement = twpBottom then Exit(0);
  Result := MulDiv(ActiveController.Metric(TyToolWindowStripSizeVar, TyToolWindowStripSizeDef),
    Font.PixelsPerInch, 96);
end;

procedure TTyToolWindowBar.DeriveSize;
var
  collapsedNow: Boolean;
  content, total: Integer;
begin
  if FDeriving or FDpiAdjusting or (csLoading in ComponentState) then Exit;
  FDeriving := True;
  try
    { 设计期不算收起,没有窗口也按展开算 —— 否则设计器里既看不见提示也点不中。 }
    collapsedNow := not (csDesigning in ComponentState)
      and (FCollapsed or (Length(FWindows) = 0));
    content := MulDiv(FExpandedSize, Font.PixelsPerInch, 96);
    if FPlacement = twpBottom then
    begin
      if collapsedNow then total := 0
      else total := 2 * ChromeInsetPx + EdgeSizePx + content;
      Height := total;
    end
    else
    begin
      total := StripSizePx + 2 * ChromeInsetPx;
      if not collapsedNow then Inc(total, EdgeSizePx + content);
      Width := total;
    end;
  finally
    FDeriving := False;
  end;
end;

procedure TTyToolWindowBar.ConstrainedResize(var MinWidth, MinHeight, MaxWidth,
  MaxHeight: TConstraintSize);
var
  collapsedNow: Boolean;
  minAxis: Integer;
begin
  inherited ConstrainedResize(MinWidth, MinHeight, MaxWidth, MaxHeight);
  collapsedNow := not (csDesigning in ComponentState)
    and (FCollapsed or (Length(FWindows) = 0));
  if FPlacement = twpBottom then
  begin
    if collapsedNow then minAxis := 0
    else minAxis := 2 * ChromeInsetPx + EdgeSizePx + ContentMinPx;
    if MinHeight < minAxis then MinHeight := minAxis;
  end
  else
  begin
    minAxis := StripSizePx + 2 * ChromeInsetPx;
    if not collapsedNow then Inc(minAxis, EdgeSizePx + ContentMinPx);
    if MinWidth < minAxis then MinWidth := minAxis;
  end;
end;
```

`SetExpandedSize` 钳 `0..99999`（和布局串的 1-5 位纯数字对齐），然后 `DeriveSize; Realign; Invalidate;`。
`AdjustClientRect`：`inherited` 之后按 Placement 扣掉图标条、边缘区和 `2×ChromeInsetPx`。
`Width` / `Height` 按 Placement 重声明为 `stored False`（用 stored 函数 `WidthIsStored` / `HeightIsStored`）。

- [ ] **Step 4: 跑两条，必须绿**

- [ ] **Step 5: 写「注册 / 注销 / 当前页回落」的失败测试**

```pascal
procedure TTyToolWindowBarTests.TestFirstWindowBecomesActiveAndRemovalFallsBack;
var
  a, b, c: TTyToolWindow;
begin
  a := TTyToolWindow.Create(FForm); a.Parent := FBar;
  AssertSame('第一个注册进来的成为当前页', a, FBar.ActiveWindow);
  b := TTyToolWindow.Create(FForm); b.Parent := FBar;
  c := TTyToolWindow.Create(FForm); c.Parent := FBar;
  FBar.ActivateWindow(b);
  b.Free;
  AssertSame('当前页离开 → 原位置的下一个接班', c, FBar.ActiveWindow);
  c.Free;
  AssertSame('没有下一个就上一个', a, FBar.ActiveWindow);
  a.Free;
  AssertNull('都没了就是 nil', FBar.ActiveWindow);
  AssertEquals('空栏的 ActiveIndex 是 -1', -1, FBar.ActiveIndex);
end;

procedure TTyToolWindowBarTests.TestBarRejectsNonWindowChildren;
begin
  AssertFalse('栏只收工具窗口', FBar.ChildClassAllowed(TTyPanel));
  AssertTrue('工具窗口当然收', FBar.ChildClassAllowed(TTyToolWindow));
end;
```

- [ ] **Step 6: 实现注册 / 注销 / 激活**

- `RegisterWindow` 照 `PageControl.pas:272-296`：幂等、推 Controller、第一个自动成为当前页；栏**不在 csLoading** 时注册进来的（组件编辑器新建、粘贴、代码添加）也成为当前页。
- `UnregisterWindow` 照 `PageControl.pas:298-313` 的回落边界（`Idx < FActiveIndex → Dec`、`Idx = FActiveIndex 且越界 → 钳到 High`），但**先把 `FActive` 置 nil 再回落**——回落用的 `ActivateWindow` 不该去藏一个已经离开的窗口。
- `Notification(opRemove)` 也走 `UnregisterWindow`，并清掉属于该窗口的悬停、按下部件和手势记录。
- `ActivateWindow` 按 spec §5.1 的六步；第 2、3 步必须是：

```pascal
  { csNoDesignVisible 必须在写 Visible 之前设:设计期的显示状态是
    `Visible or (csDesigning and not csNoDesignVisible)`,触发重算的是写 Visible 那一次。
    顺序反了,切走的那一页 HWND 会一直杵到设计器整体重绘。 }
  FBarSwitching := True;
  try
    AWindow.ControlStyle := AWindow.ControlStyle - [csNoDesignVisible];
    AWindow.Visible := True;
    if (old <> nil) and (old <> AWindow) then
    begin
      old.ControlStyle := old.ControlStyle + [csNoDesignVisible];
      old.Visible := False;
    end;
  finally
    FBarSwitching := False;
  end;
```

工具窗口里加一个探针，好让顺序可测（无头没别的办法看出顺序）：

```pascal
    { 测试用:记下「写 Visible 那一刻 csNoDesignVisible 是什么」。顺序变异掉之后这个值翻转。 }
    property NoDesignVisibleAtLastShow: Boolean read FNoDesignVisibleAtShow;
```

在 `TTyToolWindow.SetVisible` 里赋值：`FNoDesignVisibleAtShow := csNoDesignVisible in ControlStyle;`。

- [ ] **Step 7: 顺序测试 + 变异**

```pascal
procedure TTyToolWindowBarTests.TestDesignVisibleFlagIsSetBeforeVisible;
var
  a, b: TTyToolWindow;
begin
  a := TTyToolWindow.Create(FForm); a.Parent := FBar;
  b := TTyToolWindow.Create(FForm); b.Parent := FBar;
  FBar.ActivateWindow(b);
  AssertFalse('新当前页写 Visible 时,csNoDesignVisible 必须已经摘掉',
    b.NoDesignVisibleAtLastShow);
  AssertTrue('旧页写 Visible 时,csNoDesignVisible 必须已经加上',
    a.NoDesignVisibleAtLastShow);
end;
```

变异：把 `ActivateWindow` 里那两行对调（先写 `Visible` 再改 `ControlStyle`），重编重跑——这条**必须红**。改回来确认绿。

- [ ] **Step 8: 写流式往返测试**

加进 `tests/test.toolwindow.window.pas`，载体是 `THostForm = class(TForm) published Bar: TTyToolWindowBar; end;`：

```pascal
procedure TTyToolWindowStreamingTests.TestRoundTripKeepsWindowsOrderActiveAndSizes;
begin
  { Src：栏 + 三个窗口(W1/W2/W3) + W2 里一个操作区 + 一个正文控件；
    ExpandedSize := 200；ActiveIndex := 1；Collapsed := True。 }
  MS.WriteComponent(Src);
  MS.Position := 0;
  MS.ReadComponent(Dst);
  AssertEquals('窗口数', 3, DstBar.WindowCount);
  AssertEquals('顺序', 'W1', DstBar.Windows[0].Name);
  AssertEquals('当前页序号', 1, DstBar.ActiveIndex);
  AssertEquals('展开尺寸', 200, DstBar.ExpandedSize);
  AssertTrue('收起标志', DstBar.Collapsed);
  AssertNotNull('操作区跟着窗口一起流', DstBar.Windows[1].Actions);
  AssertNull('Controller 不进 .lfm', DstBar.Windows[1].Controller);
end;

procedure TTyToolWindowStreamingTests.TestExpandedSizeStreamsOnBothSidesOfTheDefault;
begin
  { 一条 240(默认值,省略不写)、一条 260(写出来)各往返一次,值都必须不变。
    published default 与构造值不一致时,第一条会在加载后变成另一个数。 }
end;
```

`initialization` 里 `RegisterClasses([TTyToolWindowBar, TTyToolWindow, TTyToolWindowActions]);`——漏一个，读回来时按类名找不到类。

- [ ] **Step 9: 跑 bar 与 window 两个 suite，绿了提交**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowBarTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): bar state model, registration and active window

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: 图片列表与图标解析（spec §8）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bar.pas`

- [ ] **Step 1: 写失败的测试**

```pascal
procedure TTyToolWindowBarTests.TestImageNameResolvesAgainstTheBarsList;
var
  w: TTyToolWindow;
begin
  FBar.Images := FList;              { 夹具里建的 TTyLucideImageList,含 'house' 这个名字 }
  w := TTyToolWindow.Create(FForm); w.Parent := FBar;
  w.ImageName := 'house';
  AssertTrue('按名字解析得到有效序号', FBar.ResolvedImageIndex(w) >= 0);
  w.ImageName := 'no-such-glyph';
  AssertEquals('名字找不到 → -1,不许乱画一个', -1, FBar.ResolvedImageIndex(w));
end;

procedure TTyToolWindowBarTests.TestPendingImageIndexResolvesInLoadedNotWhileLoading;
begin
  { 模拟流式:栏进 csLoading、窗口设 ImageIndex、栏 Loaded。
    判据:csLoading 期间 ResolvedImageIndex 不去碰列表(列表这时可能还没 fixup 上),
    Loaded 之后才给出最终值。变异:把解析挪进 SetImageIndex → 这条必须红。 }
end;

procedure TTyToolWindowBarTests.TestSwappingTheListUnsubscribesTheOldOneFirst;
begin
  { FBar.Images := A; FBar.Images := B; 然后 A.Free。
    判据:A 析构不许卡住(同一个 ChangeLink 不注销就重复注册,旧列表析构时会死循环)。
    变异:把 UnRegisterChanges 那一句删掉 → 这条必须挂住/超时。 }
end;
```

- [ ] **Step 2: 实现**

- 栏上 published `Images: TCustomImageList`，setter 里：先对 `FSubscribedList` `UnRegisterChanges`，再对新列表 `RegisterChanges` + `FreeNotification`，记进 `FSubscribedList`。
  只有被移除的**正是** `FSubscribedList` 时才跳过注销（`imglist.inc:1692-1698`：同一个 link 不注销就重复注册，旧列表析构时死循环）。
- `EffectiveImages`：`Images` 为空时读取时回落到 `Manager.Images`（A 期 manager 是空壳，所以恒为 `Images`；C 期接上）。
- `ResolvedImageIndex(AWindow)`：`ImageName` 非空就按名字在 `EffectiveImages` 里找（找不到返回 -1），否则用 `ImageIndex`。
- 挂起的 `ImageIndex` 在**栏的 `Loaded`** 里解析，csLoading 期间不碰列表（否则解析到先 fixup 的那个列表）。
- `Notification(opRemove)`：被移除的是 `FSubscribedList` 就清引用。

- [ ] **Step 3: 跑三条，绿了提交**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --suite=TTyToolWindowBarTests --format=plain > /tmp/t.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/t.txt
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bar.pas && git commit -m "feat(toolwindows): image list plumbing and icon resolution

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6b: 栏的绘制（图标条、图标着色、指示条、边缘区、设计期提示）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bar.pas`

夹具里加一个 `TallyStripCell(AIndex; AGround, AWipe: TColor; out ANotGround, AWipeLeft: Integer)`：
按 `FBar.StripItemRect(AIndex)` 的范围，用 Task 3 Step 9 的 `TallyPixels` 数那一格（底色铺 `AWipe`、`FForm.Color := AGround`、`TBarAccess(FBar).RenderInto(...)`）。

- [ ] **Step 1: 写失败的像素测试**

```pascal
procedure TTyToolWindowBarTests.TestStripPaintsAndTheActiveItemDiffers;
const
  Ground = TColor($FF00FF);   { 品红:绝不能用白,白就是 light 主题的表面色 }
  Wipe   = TColor($00FF00);
var
  restPix, activePix, wipeLeft: Integer;
begin
  { 两个窗口,当前页是第一个。分别数图标条第 1 格和第 2 格里的非底色像素。 }
  TallyStripCell(0, Ground, Wipe, activePix, wipeLeft);
  AssertEquals('整块都画到,不许留底漆', 0, wipeLeft);
  TallyStripCell(1, Ground, Wipe, restPix, wipeLeft);
  AssertTrue('图标条画了东西', restPix > 0);
  AssertTrue('当前页那一格和静止格不一样', activePix <> restPix);
end;

procedure TTyToolWindowBarTests.TestDesignTimeEmptyBarPaintsANote;
begin
  TBarAccess(FBar).MarkDesigning(True);
  { 没有窗口时设计期必须画出提示文字(非底色像素 > 0);运行时同样位置必须是 0。 }
end;
```

- [ ] **Step 2: 实现 `RenderTo`（结构照 `Breadcrumb.pas:895-973`）**

1. `P.BeginPaint(ACanvas, ARect, APPI)`；`R` 用 (0,0)-local。
2. `DrawFrame(P, R, S)` 画栏自己的底色。
3. 侧栏：`stripS := ActiveController.Model.ResolveStyle('TyToolWindowStrip', TyStyleClassFor(Self, StyleClass), [tysNormal])`，`P.FillBackground(StripRect, stripS.Background, 0)`。
4. `slots := TyToolWindowStripLayout(stripPx, R.Bottom, itemPx, itemPx, WindowCount, FActiveIndex, hidden)`。
5. 逐格：`itemS := ActiveController.Model.ResolveStyle('TyToolWindowStripItem', StyleClass, ItemStates(i))`（`ItemStates` 照 `Segmented.pas:395-410`：disabled / hover / selected / active / normal）；有底色就 `FillBackground`；图标：

```pascal
        bmp := TyRenderImage(EffectiveImages, idx, glyphPx, APPI, False);
        if bmp <> nil then
        try
          { GetBitmap / RenderIndex 返回的是调用方持有的拷贝,可以就地染色;
            GetCachedBitmap 是借来的,染它会污染缓存。 }
          TyTintBitmapAlpha(bmp, itemS.TextColor);
          P.Bitmap.PutImage(x, y, bmp, dmDrawWithTransparency);
        finally
          bmp.Free;
        end;
```

6. 当前格画指示条：`TyToolWindowStripIndicator` 的底色，粗细 `--toolwindow-strip-indicator-size`（0 就不画），贴在图标条靠内容区那一侧。
7. 有溢出时条末尾画 `TyToolWindowOverflow`：`TyDrawGlyph(P, ActiveController, r, tgChevronDown, S.TextColor, 1)`。
8. 边缘区：`TyToolWindowEdge` 的底色填 `EdgeRect`。
9. `csDesigning` 且没有窗口：用 `TyToolWindowNote` 的墨色 `P.DrawText` 画一行 resourcestring 提示。
10. `P.EndPaint`——**每条提前 `Exit` 的路径都要先 `EndPaint`**，否则整块不 blit。

`Paint` 一行：`RenderTo(Canvas, ClientRect, Font.PixelsPerInch);`。栏**不做**绘制缓存：它的悬停变化频繁，而且没有会不停打脏它的子控件（工具窗口有，所以工具窗口做）。

- [ ] **Step 3: 跑，两条绿**

- [ ] **Step 4: 变异确认着色那条在守**

把 `TyTintBitmapAlpha(bmp, itemS.TextColor)` 改成 `TyTintBitmapAlpha(bmp, S.TextColor)`（永远用栏的静止态墨色），重编重跑——`TestStripPaintsAndTheActiveItemDiffers` **必须红**。改回来确认绿。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bar.pas && git commit -m "feat(toolwindows): strip, icons, indicator and edge painting

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: 图标条手势（松开切换、收起、防抖、多击、设计期）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bar.pas`

- [ ] **Step 1: 写失败的测试**

```pascal
procedure TTyToolWindowBarTests.TestIconSwitchesOnReleaseNotOnPress;
var
  p: TPoint;
begin
  { 两个窗口,当前页是第一个;点第二个图标。 }
  p := FBar.StripItemRect(1).CenterPoint;
  TBarAccess(FBar).CallMouseDown(p.X, p.Y);
  AssertSame('按下不切', FBar.Windows[0], FBar.ActiveWindow);
  TBarAccess(FBar).CallMouseUp(p.X, p.Y);
  AssertSame('松开才切', FBar.Windows[1], FBar.ActiveWindow);
end;

procedure TTyToolWindowBarTests.TestClickingTheActiveIconTogglesCollapse;
var
  p: TPoint;
begin
  p := FBar.StripItemRect(0).CenterPoint;
  TBarAccess(FBar).CallMouseDown(p.X, p.Y);
  TBarAccess(FBar).CallMouseUp(p.X, p.Y);
  AssertTrue('点当前页的图标 → 收起', FBar.Collapsed);
  FBar.TickForTest := FBar.TickForTest + TyToolWindowClickGuardMs + 1;
  TBarAccess(FBar).CallMouseDown(p.X, p.Y);
  TBarAccess(FBar).CallMouseUp(p.X, p.Y);
  AssertFalse('再点一次 → 展开', FBar.Collapsed);
end;

procedure TTyToolWindowBarTests.TestASecondClickWithin300msIsIgnored;
begin
  { 同上但不推时钟:第二次点击什么都不做。慢速双击(默认 500ms)不许收起又展开。 }
end;

procedure TTyToolWindowBarTests.TestDoubleClickPressNeverCounts;
begin
  { MouseDown 的 Shift 集写成 [ssLeft, ssDouble],松开后当前页不变、Collapsed 不变;
    但这次按下**可以**武装拖动 —— 点一下图标再马上按住拖,必须拖得起来。 }
end;

procedure TTyToolWindowBarTests.TestDesignerHitTestArmsOnPressAndHandsBackOnRelease;
begin
  TBarAccess(FBar).MarkDesigning(True);
  { ① 图标上按位置问 → 1;② 带 MK_LBUTTON 问(手势中) → 1;
    ③ wParam=0 那一拍(松开) → 0,并且当前页在这一拍切过去;④ 再按位置问 → 按位置回答。 }
end;
```

- [ ] **Step 2: 实现手势引擎的点击那一半（拖动在 Task 9 接上）**

- `MouseDown`：右键 / 中键走继承；落在图标上 → 新建手势记录（窗口引用、源序号、屏幕原点、是否多击、栏原来是否收起），**什么都不激活**。
- `MouseUp`：阈值以内 + 落在同一个图标上 + 没有多击标记 → 执行点击；否则什么都不做。
- 点击语义：不是当前页 → 激活（收起着就展开）；是当前页 → 切换 `Collapsed`。**按窗口**记 300ms 防抖，时钟走可重写的 `TickNow`。
- 覆盖 `Click` / `DblClick`：手势起自图标区时吞掉（栏 published 了 `OnClick`，LCL 在 MouseUp 之前调 `Click`）。
- 覆盖 `BeginAutoDrag`：图标区内直接 `Exit`。
- `CM_DESIGNHITTEST`：`csDesigning` 下图标上或武装中回答 1；wParam 不带 `MK_LBUTTON` 那一拍先切换、再回答 0 交还设计器。收起、调顺序、拉宽在 `csDesigning` 下一律 no-op。

时钟做成可推：

```pascal
    { 无头测试要能把时钟往前推,否则 300ms 防抖只能靠 Sleep(套件会变慢又不稳)。 }
    function TickNow: QWord; virtual;     { GetTickCount64 + FTickOffset }
    property TickForTest: QWord read FTickOffset write FTickOffset;
```

- [ ] **Step 3: 跑五条，全绿**

- [ ] **Step 4: 三处变异**

1. 把切换挪回 `MouseDown` → `TestIconSwitchesOnReleaseNotOnPress` 必须红。
2. 把防抖的 300ms 改成 0 → `TestASecondClickWithin300msIsIgnored` 必须红。
3. 把 `CM_DESIGNHITTEST` 松开分支的 `Result := 0` 改成 `1` → 设计期那条必须红。

每次都是：改 → `lazbuild -B` → 跑 → 红 → 改回 → 重编 → 绿。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bar.pas && git commit -m "feat(toolwindows): strip clicks switch on release, with a 300 ms guard

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: 拉宽边（实时写 ExpandedSize、吸附收起、中途取消）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bar.pas`

- [ ] **Step 1: 写失败的测试**

```pascal
procedure TTyToolWindowBarTests.TestEdgeDragWritesExpandedSizeLive;
var
  e: TPoint;
begin
  FBar.Placement := twpLeft;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  TBarAccess(FBar).CallMouseDown(e.X, e.Y);
  TBarAccess(FBar).CallMouseMove(e.X + 30, e.Y);
  AssertEquals('拖动过程中就写', 230, FBar.ExpandedSize);
  TBarAccess(FBar).CallMouseUp(e.X + 30, e.Y);
  AssertEquals('松开保持', 230, FBar.ExpandedSize);
  AssertFalse('没收起', FBar.Collapsed);
end;

procedure TTyToolWindowBarTests.TestEdgeDragSnapsClosedBelowHalfTheMinimum;
begin
  { 从 200 往回拖到 content-min 的一半以下:拖动中按收起排布(Width 只剩图标条 + chrome),
    ExpandedSize 保持 200;松开后 Collapsed = True、ExpandedSize 仍是 200。 }
end;

procedure TTyToolWindowBarTests.TestEdgeDragCancelRestoresTheStartValue;
begin
  { 拖到 260,然后 FBar.Perform(LM_CANCELMODE, 0, 0):ExpandedSize 回到 200,手势结束。 }
end;

procedure TTyToolWindowBarTests.TestRightBarGrowsLeftwards;
begin
  { Placement := twpRight 时,向**左**的位移让 ExpandedSize 变大(位移按增长方向取符号)。 }
end;
```

- [ ] **Step 2: 实现**

- `EdgeRect`：侧栏在内容区靠编辑区那一侧（左栏在右边、右栏在左边），底栏在顶边，宽 `EdgeSizePx`。
- 按下落在 `EdgeRect`：记 `FEdgeStartSize := FExpandedSize`、`FEdgeStartPos`，置 `FEdgeDragging`。
- `MouseMove`：`delta := UnscaleI(位移)`，按增长方向取符号（左栏向右、右栏向左、底栏向上为正，同 `TySplitterNewSize` 对 alRight / alBottom 取反）；`want := FEdgeStartSize + delta`：
  - `want < ContentMinLogical div 2` → `FEdgeSnapped := True`，实时按收起排布，`ExpandedSize` **不动**；
  - 否则 `FEdgeSnapped := False`，`ExpandedSize := Math.Max(want, ContentMinLogical)`。
- `MouseUp`：`FEdgeSnapped` 为真 → `Collapsed := True`；清状态。
- `LM_CANCELMODE` / Application 失活 / `Collapsed`、`Placement` 被别处改 → `ExpandedSize := FEdgeStartSize`，清状态。
- 栏里没有窗口、`csDesigning`：边缘区不起作用。
- **不复用 `TySplitterNewSize`**：它默认吸附到 0，关掉吸附又钳在最小值上，两种都和上面的规则冲突（`Splitter.pas:103-111`）。

- [ ] **Step 3: 跑四条，全绿**

- [ ] **Step 4: 变异**

把 `want < ContentMinLogical div 2` 改成 `want < 0`（等于取消吸附），重编重跑——`TestEdgeDragSnapsClosedBelowHalfTheMinimum` 必须红。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bar.pas && git commit -m "feat(toolwindows): resize edge writes live and snaps closed

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: 栏内拖动调顺序（阈值、插入线、松开提交、Esc 取消）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Modify: `tests/test.toolwindow.bar.pas`

- [ ] **Step 1: 写失败的测试**

```pascal
procedure TTyToolWindowBarTests.TestDragReordersOnReleaseNotLive;
var
  a, b, c: TTyToolWindow;
  p: TPoint;
begin
  { 三个窗口 a b c;把 a 拖到 c 后面。 }
  p := FBar.StripItemRect(0).CenterPoint;
  TBarAccess(FBar).CallMouseDown(p.X, p.Y);
  TBarAccess(FBar).CallMouseMove(p.X, p.Y + 80);
  AssertSame('拖动过程中不实时挪', a, FBar.Windows[0]);
  AssertEquals('插入线落在末尾', 3, FBar.DropSlotForTest);
  TBarAccess(FBar).CallMouseUp(p.X, p.Y + 80);
  AssertSame('松开才提交', b, FBar.Windows[0]);
  AssertSame('a 到了最后', a, FBar.Windows[2]);
end;

procedure TTyToolWindowBarTests.TestSidewaysDragStarts;
begin
  { 竖直图标条上**横向**移动超过阈值也要进入拖动 —— TabStrip 只算主轴,照抄永远拖不起来。 }
  TBarAccess(FBar).CallMouseDown(p.X, p.Y);
  TBarAccess(FBar).CallMouseMove(p.X + TyToolWindowDragThreshold(96) + 1, p.Y);
  AssertTrue('横拖也算拖', FBar.IsDraggingForTest);
end;

procedure TTyToolWindowBarTests.TestEscCancelsAndTheReleaseIsNotAClick;
begin
  { 拖起来之后 FBar.Perform(CN_KEYDOWN, VK_ESCAPE, 0):
    IsDraggingForTest = False、顺序不变;随后的 MouseUp 不许被当成点击(当前页不变)。 }
end;

procedure TTyToolWindowBarTests.TestNoOpSlotsDoNotReorder;
begin
  { 拖 b 放回它自己前后两个空隙(slot = src 与 src+1):顺序一点不变,也不发 OnChange。 }
end;

procedure TTyToolWindowBarTests.TestDropIndicatorPixelsLandInTheStrip;
begin
  { 哨兵底色 RenderTo:拖动中插入线那一行的非底色像素 > 0,没拖动时同一行 = 0。
    插入线颜色挑一个红绿蓝不相等的色,别的元素混不出来。 }
end;
```

- [ ] **Step 2: 实现**

- 阈值：`Max(|dx|, |dy|) >= TyToolWindowDragThreshold(Font.PixelsPerInch)`，按**屏幕坐标**比（`ClientToScreen` 之后）。
- 进入拖动：置吞点击标志、`Application.CancelHint`、`Screen.BeginTempCursor(crDrag)`；装 `Application.AddOnKeyDownBeforeHandler`、`AddOnDeactivateHandler`、`Screen.AddHandlerActiveFormChanged`，并建一个**只在拖动期间存在**的 `TTimer`（约 100ms）比对 `GetCaptureControl`。
  **不用 `AddOnIdleHandler`**：`Application.OnIdle` 或处理器链上任一个把 `Done` 置 False，后面的就不跑（`application.inc:471-477, 743-751`）。
- 移动：`slot := TyToolWindowSlotAt(slots, X, Y, True, WindowCount)`；`(栏, 槽位)` 变了才 `Invalidate`。
- 松开：`FinalIndex := slot - Ord(slot > src)`；`slot` 是 `src` 或 `src+1` → 什么都不做；否则 `SetControlIndex`（**按 §2 的索引换算**：窗口序号 → `Controls` 下标）；当前页没换就不发 `OnChange`。
- `EndGesture` 幂等：弹**唯一一次** `EndTempCursor`（不配对会抛）、摘全部处理器、释放计时器、清反馈。取消入口：Esc（`KeyDownBefore` 里 `Key := 0`）、没有 `ssLeft` 的移动、`LM_CANCELMODE`、Application 失活、`ActiveFormChanged`、计时器发现捕获没了、`opRemove`、析构（同时 `RemoveAllHandlersOfObject` + `Application.RemoveAsyncCalls`）。
- **`CaptureChanged` 从不取消**：Win32 上每次正常松手都会先到，在里面取消会让所有放下都失败。
- 插入线：在自己的 `RenderTo` 里、`EndPaint` **之前**画进 BGRA 层，颜色取 `TyToolWindowDropIndicator` 的底色，粗细 `--toolwindow-drop-size` 按 PPI 缩放。
- `csDesigning` 下不武装拖动。

- [ ] **Step 3: 跑五条，全绿**

- [ ] **Step 4: 两处变异**

1. 阈值改成只算主轴（`Abs(dy)`）→ `TestSidewaysDragStarts` 必须红。
2. 把提交从 `MouseUp` 挪到 `MouseMove`（实时挪位）→ `TestDragReordersOnReleaseNotLive` 必须红。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/test.toolwindow.bar.pas && git commit -m "feat(toolwindows): in-strip reorder commits on release with a drop line

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: 可见性与焦点（`SetVisible` 收口、收起时焦点搬家）

**Files:**
- Modify: `source/tyControls.ToolWindows.pas`
- Create: `tests/test.toolwindow.focus.pas`
- Modify: `tests/tytests.lpr`

这一组要**真句柄**（`CanFocus` 要求整条父链 Visible），夹具照 `tests/test.focus.tabstop.pas:585-647`：**本单元自带**一个 `ToolWindowWidgetSetReady` 开关（别共用别人的，共用会让单跑和全量给出不同结果）、窗体摆到 `(-4000, -4000)` 再 `Visible := True` + `HandleNeeded`、装一个 `Application.OnException` 陷阱（消息里抛异常没有帧可退，不接住会弹模态框把 console runner 永久卡住）。

- [ ] **Step 1: 写失败的测试**

```pascal
procedure TTyToolWindowFocusTests.TestCollapsingMovesFocusOutOfTheWindow;
var
  ed: TTyEdit;
begin
  ed.SetFocus;
  AssertSame('先确认焦点真的在里面', ed, FForm.ActiveControl);
  FBar.Collapsed := True;
  AssertTrue('焦点不许掉到窗体本身,那样快捷键全失灵',
    (FForm.ActiveControl <> nil) and (FForm.ActiveControl <> FForm));
  AssertFalse('焦点不许留在被藏起来的窗口里', FWin.ContainsControl(FForm.ActiveControl));
end;

procedure TTyToolWindowFocusTests.TestSwitchingMovesFocusOnlyIfItWasInside;
begin
  { 焦点在旧页里 → 切页后落到新页第一个可聚焦控件;
    焦点在栏外的控件上 → 切页后一动不动。 }
end;

procedure TTyToolWindowFocusTests.TestExternalVisibleTrueActivatesThroughTheBar;
begin
  FBar.Windows[1].Visible := True;
  AssertSame('外部把非当前页设成可见 = 激活它', FBar.Windows[1], FBar.ActiveWindow);
  AssertFalse('并且展开栏', FBar.Collapsed);
  FBar.ActiveWindow.Visible := False;
  AssertTrue('把当前页设成不可见 = 收起栏', FBar.Collapsed);
end;
```

- [ ] **Step 2: 实现**

- `TTyToolWindow.SetVisible` 覆写：`FBarSwitching` 下直接放行；csLoading 忽略；运行时外部 `True` → `Bar.ActivateWindow(Self)` 并展开；外部 `False` 且自己是当前页 → `Bar.Collapsed := True`；**设计期**外部 `True` 只激活不写 `Collapsed`，外部 `False` 忽略。
- `SetCollapsed(True)`（只在运行时）：先记 `Form.ActiveControl` 在不在当前页里 → 当前页在 `FBarSwitching` 下 `Visible := False`（发 `OnHide`）→ 原来在里面就 `GetParentForm(Self).SelectNext(Self, True, True)`。
- `SetCollapsed(False)`：在 `FBarSwitching` 下把 `FActive` 显示出来（发 `OnShow`）。
- 切页焦点按 spec §5.1 第 5 步：**只有**焦点原来在旧页里、且 `W.CanFocus` 才 `W.FocusFirst`（`FocusFirst` 是 protected `SelectFirst` 的 public 包装）。

- [ ] **Step 3: 跑三条，全绿**

- [ ] **Step 4: 变异**

把收起里的 `SelectNext` 删掉，重编重跑——`TestCollapsingMovesFocusOutOfTheWindow` 必须红（`ActiveControl` 会变成窗体本身）。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.ToolWindows.pas tests/ && git commit -m "feat(toolwindows): visibility routes through the bar, collapse moves focus out

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: 收尾——按 spec 逐条核、跑全量、抽查变异

**Files:**
- Modify: `docs/superpowers/plans/2026-09-20-toolwindow-phase-a.md`
- Modify: `docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md`

- [ ] **Step 1: 按 spec 逐条核代码，不看测试**

对着 spec §3、§4、§5、§6、§9.1–9.3、§12 一条条查实现。**全绿不等于按 spec 做完**：重点查测试碰不到的那些——`csNoFocus`、六个 `stored False`、`ChildClassAllowed`、`TabStop` 的 published default、改 `Placement` 时同步 `Align` 与 `Left`/`Top`、`--toolwindow-*` 每个 token 是不是真的有人读。**只在 tests/ 里出现的常量就是红旗**（建好没接线是本库的默认故障）。

- [ ] **Step 2: 跑全量**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi && cd tests && cp tytests.exe tytests-31.exe && ./tytests-31.exe --all --format=plain > /tmp/all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/all.txt
```

Expected：`Number of run tests` 那一行存在，errors / failures 都是 0，总条数比 A 期开工前多出本计划新增的条数。

- [ ] **Step 3: 抽查四条变异**

按任务里写死的四处（Task 2 Step 9、Task 5 Step 7、Task 7 Step 4 第一条、Task 10 Step 4）各做一次「改 → `lazbuild -B` → 必须红 → 改回 → 重编 → 绿」。

- [ ] **Step 4: 把实现期发现的偏差写回 spec**

实现期一定会撞上 spec 没写准的地方。发现一条就在 spec **原处**改，并注明「实现期修正」——B/C/D 期读的是 spec，不是这份计划。

- [ ] **Step 5: 提交收尾**

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(toolwindows): phase A sign-off notes and spec corrections

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## A 期做完能看到什么

在一个 `.lfm` 里放一条 `TTyToolWindowBar`（`Placement := twpLeft`、`Align := alLeft`），用代码往里加两三个 `TTyToolWindow`，运行起来应当是：

- 左边一条图标条，每个工具窗口一个图标，当前页那个带指示条；
- 点别的图标（松手时）切过去；点当前图标收起，再点展开；
- 拖图标能在条内调顺序，拖动时有插入线，Esc 取消；
- 拖内容区靠编辑区那条边能调宽度，拖过头吸附收起；
- 工具窗口上面有标题行，标题在左、操作区在右；
- 换主题 / 换密度 / 换 DPI，标题行和图标条都跟着变。

**还做不到的**（B / C / D 期）：底栏、跨侧拖动、布局保存、设计器里加窗口、示例和文档。
