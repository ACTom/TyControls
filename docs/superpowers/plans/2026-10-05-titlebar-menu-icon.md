# 标题栏默认右键菜单与可选图标 实现计划（#9）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能默认做法）**：测试先行，每个任务改代码 + 写测试并单独提交；任务之间**不编译**；Task 7 一次编译、跑相关 suite 与全量、集中变异、签收。中途不汇报、不问要不要提交。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent 不做：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编 `examples/`、GUI 冒烟与手点。实现 agent 只编 `tests/tytests.lpi`。
>
> **不改的文件**：`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`Base.pas`、`Menu.pas`（本计划不需要）。`CHANGELOG.md` 不改（发版时写）。

**Goal:** GitHub #9——`TTyTitleBar` 右键弹出库内主题化的窗口菜单（还原 / 最小化 / 最大化 / 关闭），用户设了 `PopupMenu` 就用用户的；加 `ShowIcon`（默认关）与 `Icon`，打开后标题栏最左画图标，单击图标弹同一个菜单、双击图标关窗。

**Architecture:** 全部实现放 `TTyCustomTitleBar`（public），`TTyTitleBar` 在发布段末尾追加两行。布局走既有的唯一权威 `TTyCaptionLayout`：记录多一个 `Icon` 矩形，`Content` 的阅读起始边在有图标时让出「图标 + 间距」，镜像仍是那一次 `BidiFlipRect`。菜单是一个无 Owner 的 `TTyPopupMenu`，每次弹出前按纯函数 `TyWindowMenuStateFor` 刷新可见 / 可用；菜单项执行的是三个标题按钮的 `Click`，和按钮走同一条路。弹出只有一个出口 `PopupWindowMenu`（virtual，测试替身改它记录请求，不开真窗口）。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL（最低 Lazarus 3.0）、BGRABitmap、fpcunit（`tests/tytests.lpi`）。

**工作树：** `D:/Projects/ty-titlebar`，分支 `feat/titlebar-menu`，起点 `main` @ `140496e6`（已含 TTyCustomXxx 拆分）。

---

## 核实记录（动手前查过的事实）

| # | 事实 | 出处 | 对设计的影响 |
|---|---|---|---|
| V1 | `TControl.PopupMenu` 的读方法是 **virtual `GetPopupMenu`**（`property PopupMenu: TPopupmenu read GetPopupmenu`，controls.pp:1815） | LCL 4.4 | **不能**覆写 `GetPopupMenu` 返回默认菜单：那样 `TitleBar.PopupMenu` 读出来非 nil，`.lfm` 会把一个无名、无 Owner 的菜单写进窗体，对象查看器也会显示它，用户代码 `if TitleBar.PopupMenu = nil` 全错。改在 `DoContextPopup` 里弹（见 D2）。`ToolWindows.pas` 覆写 `GetPopupMenu` 只返回 nil，不受此限。 |
| V2 | `TControl.WMContextMenu` 先 `DoContextPopup(P, Handled)`，Handled 就结束；否则才 `GetPopupMenu` → `Popup`。键盘菜单键时 P = (-1,-1) 原样传入 | control.inc:2472-2502 | `DoContextPopup` 覆写：先 inherited（用户的 `OnContextPopup` 先说话），没 Handled 且 `PopupMenu = nil` 才弹默认菜单并置 Handled。 |
| V3 | `TWinControl.WMContextMenu` 先把消息交给鼠标下的**图形**子控件（`ControlAtPos(..., [])`，不找窗口化子控件），子控件不处理才走自己的 | wincontrol.inc:8446-8471 | 标题栏上的 `TTyLabel` 之类图形子控件右键 → 落回标题栏 → 默认菜单（它们画在标题栏身上，属于标题栏表面）。窗口化子控件自己收消息，不处理时 Win32 的 DefWindowProc 把 `WM_CONTEXTMENU` 冒泡给父窗口（`ToolWindows.pas` 1198 行注释记的同一事实）——这时标题栏不弹，让它继续冒泡到窗体（D3）。 |
| V4 | 快捷键分发用的是 `PopupMenu` 属性（`DoKeyDownBeforeInterface.IsShortCut`，wincontrol.inc:5815） | LCL 4.4 | 默认菜单不挂在 `PopupMenu` 上，所以它的 `Alt+F4` 项只是显示文字，不会被分发成第二次关闭。 |
| V5 | `CNSysKeyDown` → `DoKeyDownBeforeInterface` → 沿父链调各窗体的 `IsShortcut`（wincontrol.inc:7260、5815-5830） | LCL 4.4 | Alt+Space 在 `TTyForm.IsShortcut` 里截（已覆写过，给菜单栏分发用），返回 True 即 Handled。 |
| V6 | `MsgKeyDataToShiftState`：Win32 上 `ssAlt` 取自 `KeyData and MK_ALT`，Ctrl/Shift/Meta 取实时键盘 | lclintf.pas:198-205；`test.form.pas` 的 `TestIsShortCut` 已用这条 | 无头测试用 `KeyData` 带 `MK_ALT` 驱动 Alt+Space。 |
| V7 | `TGraphicPropertyEditor` 注册在 `ClassTypeInfo(TGraphic)` 上，属性名 / 宿主类不限 | components/ideintf/graphpropedits.pas:840 | `Icon: TIcon` 在对象查看器里自动用 LCL 现成的图像编辑器（和 `TForm.Icon` 同一个），设计期包不用注册任何东西。该编辑器 `AGraphic.Assign(...)` **直接改对象**、不走 setter → 控件必须挂 `FIcon.OnChange` 才能重画。 |
| V8 | `TGraphic.DefineProperties` 只在非空时写 `Data` | LCL | 空 `Icon` 本来就不写；再加 `stored IsIconStored`（照 `TCustomForm.Icon`），`.lfm` 里连空的 `Icon` 都不出现。 |
| V9 | `TCustomIcon.Assign(TRasterImage)` 把位图收成单张图标；`GetBestIndexForSize(TSize)`、`Current`、`Count` 都是 public | icon.inc:368、966；graphics.pp:1671-1675 | 绘制时**复制**一份再改 `Current`（源可能是 `Application.Icon`，改它的 `Current` 会触发应用图标重设）。测试用位图造图标。`GetBestIndexForSize` 在 Lazarus 1.8 的 HiDPI 图标选择里就有，3.0 可用。 |
| V10 | `TTyPainter.DrawGlyphBitmap(ARect, ABmp)` 居中 `PutImage(..., dmDrawWithTransparency)` | Painter.pas:2123 | 画图标不用改 Painter。 |
| V11 | `TTyMenuPopup.DoActivateRow` 先 `CloseAll` 再 `Item.Click`，根级之后不再碰 Self | Menu.pas:1955-1977 | 「关闭」项里走 `Close`（`caFree` 时是 `Release`，异步），菜单对象不会在自己的激活里被释放。 |
| V12 | `TTyPopupMenu.PopUp` 先 `DoPopup`、再快照 Items；RTL 读 `PopupComponent` | Menu.pas:2750、2830 | 弹出前设 `PopupComponent := Self`，菜单随标题栏的阅读方向镜像。 |
| V13 | `TTyForm.BorderStyle` 锁死 `bsNone`；窗口提供哪些按钮由 `BorderIcons + Resizable` 经 `TyResolveCaptionButtons` 推到 `OfferedButtons` | Form.pas:2435、2453 | 主控设计里「按 BorderStyle」在本库没有信息量：`bsDialog` / `bsToolWindow` 的含义（无最小化 / 最大化）在 `TTyForm` 上由 `BorderIcons` 表达。判据统一取「按钮在不在」= 开关 AND 窗口提供（`TTyDialog` 只提供关闭 → 菜单只有「关闭」，同 Windows 对话框的系统菜单）。 |
| V14 | 最大化有两条路：引擎自己的工作区最大化（`WindowState` 保持 `wsNormal`）和系统最大化（Aero Snap，`SyncNativeMaximized`）；两条都经 `ApplyMaximizedState` 把最大化按钮的 `Kind` 换成 `cbkRestore` | Form.pas:1905-1950、2938-2963 | 「已最大化」以 `MaxButton.Kind = cbkRestore` 为准（独立标题栏也成立），再并上宿主窗体 `WindowState = wsMaximized`。只看 `WindowState` 会把引擎最大化当成正常态。 |
| V15 | 标题栏的对齐子控件被 `AdjustClientRect` 收进 `Content`；自由放置（`alNone`）的不受影响——titlebar.md §1「范围说明」早已写明只支持对齐子控件 | Form.pas:1374-1388；docs/controls/titlebar.md | 「菜单栏随图标右移」对**对齐的**菜单栏成立；`alNone` 的保持作者写的坐标（LCL 语义，不替作者挪）。示例把内嵌菜单栏改成 `alLeft` 演示（Task 6）。 |
| V16 | 主题令牌约定：长度令牌写 `themes/light.tycss` `:root` 几何段（字母序），现代密度写 `DensityPack.pas`（手写），`gen-defaulttheme.ps1` 与 `gen-tycss-catalog.ps1` 重新生成 `DefaultTheme.pas` / `Css.Catalog.pas`；`test.themes` 的 `GMETRICS` 与三个 golden 的 `metric` 行同步加 | 2026-09-20-toolwindow-phase-a.md Task 1；test.themes.pas | 本计划不动 `auto` / `system` / `builtin/*`，不跑 `gen-builtinthemes.ps1`。 |
| V17 | 可翻译字符串：`StrConsts.pas` 的 `resourcestring` + `languages/tyControls.StrConsts.pot`（按标识符字母序）+ `tycontrols.strconsts.zh_CN.po` + `.en.po`（追加在末尾）；`test.i18n` 守 pot 覆盖 | test.i18n.pas:180-230 | 四个菜单项各一条。 |
| V18 | 发布段追加：`gen-mimic.py` 照抄最终类发布段；`TY_WRITE_FRESH_STREAMS=1` 重写新实例快照 | CONTRIBUTING.md；docs/subclassing.md | mimic 的 diff 只该是 `TGenTitleBar` 段末多两行；fresh-streams 预期**无 diff**（两个新属性的默认值都不写出），有 diff 就是默认值写出了，要查。 |

## 设计（主控已定 + 本计划落地的细节）

**D1 默认菜单的内容与规则**（照 Windows 系统菜单，`TyWindowMenuStateFor`，纯函数）：

| 项 | 可见 | 可用 |
|---|---|---|
| 还原 `&Restore` | 能最小化或能最大化或已最大化 | 已最大化 |
| 最小化 `Mi&nimize` | 同上 | 能最小化 |
| 最大化 `Ma&ximize` | 同上 | 能最大化且未最大化 |
| 分隔线 | 关闭可见且上面三项可见 | — |
| 关闭 `&Close`（显示 `Alt+F4`） | 能关闭 | 总是 |

「能最小化 / 最大化 / 关闭」= 对应按钮的开关 AND 窗口提供（`ShowXxx and (cbfXxx in OfferedButtons)`），与按钮在不在逐字同一个判断。「上面三项全藏」照 Windows：窗口既没有最小化框也没有最大化框时系统菜单删掉这三项。**比 Windows 多一条**：已最大化时三项不藏——本库到处守着「最大化的窗口总能还原」（`ToggleMaximize`、`CanMaximize` 的注释），菜单不该是例外。`Alt+F4` 只在非 macOS 显示（mac 没有这个键，关窗是 Cmd+W；Linux 主流 WM 认 Alt+F4）——对主控设计的小偏离，见 D9。

菜单项执行 `MinButton` / `MaxButton` / `CloseButton` 的 `Click`：挂在 `TTyForm` 上时走窗体接好的 `DoMinimizeClick` / `DoMaxRestoreClick` / `DoCloseClick`；独立标题栏走用户自己给按钮挂的 `OnClick`。还原 = 已最大化时点最大化按钮（它此刻就是还原按钮）。

**D2 弹在哪**：`DoContextPopup` 覆写（V1、V2）。用户的 `OnContextPopup` 先跑；置了 Handled 就不弹。`PopupMenu <> nil` 时不插手，LCL 接着弹用户的。键盘菜单键 (-1,-1) 弹在 D5 的锚点。

**D3 冒泡上来的不弹**：点在宿主放的**窗口化**子控件上（不是三个标题按钮）——那是子控件自己的请求冒泡上来，标题栏不认，让它继续冒泡到窗体。标题按钮上的右键照 Windows 弹窗口菜单。图形子控件见 V3。

**D4 一个入口三条路**：`WindowMenu` = `PopupMenu`（用户设了）否则默认菜单（没有可见项时 nil）；右键、单击图标、Alt+Space 都开 `WindowMenu`。理由：用户换掉了窗口菜单，Alt+Space 再弹库里那份就是同一件事两个菜单。主控原话「用户设了 PopupMenu 就用用户的」「Alt+Space 也打开这个菜单」「单击图标打开同一个菜单」按这个读。

**D5 锚点**：图标打开时，菜单挂在图标阅读起始边的下沿（`Icon.Left` / RTL 时 `Icon.Right`，y = `ClientHeight`）；否则挂在标题栏阅读起始角的下沿（0 或 `ClientWidth`）。右键弹在指针处。

**D6 图标**：`ShowIcon: Boolean default False`、`Icon: TIcon stored IsIconStored`。取图：`Icon`（非空）→ 宿主窗体 `Icon`（非空）→ `Application.Icon`（非空）→ 不画（槽位照留，布局不随「有没有图」跳）。尺寸 `--titlebar-icon-size`（16，现代 20）、与标题的间距 `--titlebar-icon-gap`（6，现代 8），逻辑像素，按 `Font.PixelsPerInch` 缩放；起始边距沿用 `--titlebar-padding`。边长不超过标题栏高度，垂直居中。`ShowIcon = False` 时 `TyTitleBarLayoutFor` 收到 0/0，走的算式与改动前逐项相同。

**D7 图标的鼠标**：左键按在图标上——不进引擎（不拖、不顶边缩放之外的任何事；Win32 顶边缩放热区仍优先，它在 y < 6px），单击开 `WindowMenu`，`ssDouble` 的那一下关窗（能关闭时，等于点关闭按钮）；紧随的 `DblClick` 不再走引擎的最大化 / 卷起。用户的 `OnMouseDown` / `OnDblClick` 照常触发。

**D8 Alt+Space**：`TTyForm.IsShortcut` 里，按键是 Space、修饰键恰好是 Alt、有可见的关联标题栏、`ShowWindowMenu` 返回 True → 吃掉。Windows、Linux 启用；**macOS 不启用**（Option+Space 在 mac 上是输入不换行空格，截了会让编辑框打不出这个字符；mac 窗口也没有窗口菜单这个惯例）——偏离主控「其它平台也启用」，理由如上，写进文档。Linux 上不少 WM 自己绑了 Alt+Space（GNOME / KDE 的窗口菜单），它们先抢到时我们收不到，文档写明。

**D9 偏离汇总**：① BorderStyle 不参与判断（V13）；② 已最大化时还原 / 最小化 / 最大化三项不藏（D1）；③ macOS 不显示 `Alt+F4`、不截 Option+Space（D1、D8）；④ 自由放置的内嵌菜单栏不随图标移动（V15，沿用既有范围说明）；⑤ 用户的 `PopupMenu` 也用于图标单击与 Alt+Space（D4）；⑥（期末修复补记）取图顺序比主控设计多了一级窗体 `Icon`：`Icon` → 宿主窗体 `Icon` → `Application.Icon`（D6），窗体图标是这扇窗自己的图标，比程序图标更贴切；⑦（期末修复补记）标题栏右键不再冒泡到窗体的 `PopupMenu`（3.0 会），要旧行为把 `TitleBar.PopupMenu` 设成窗体的菜单——写进 `titlebar.md`、`ttyform.md` 的「从 3.0 升级」。

**D10 公开面**（全部在 `TTyCustomTitleBar`；最终类只追加 `property ShowIcon; property Icon;`）：

```pascal
// 单元级
const
  TyTitleBarIconSizeVar = '--titlebar-icon-size';  TyTitleBarIconSizeDef = 16;
  TyTitleBarIconGapVar  = '--titlebar-icon-gap';   TyTitleBarIconGapDef  = 6;
  TyWindowMenuRestoreIndex = 0; TyWindowMenuMinimizeIndex = 1; TyWindowMenuMaximizeIndex = 2;
  TyWindowMenuSeparatorIndex = 3; TyWindowMenuCloseIndex = 4;
type
  TTyWindowMenuState = record
    RestoreVisible, RestoreEnabled, MinimizeVisible, MinimizeEnabled,
    MaximizeVisible, MaximizeEnabled, CloseVisible: Boolean;
  end;
function TyWindowMenuStateFor(ACanMinimize, ACanMaximize, ACanClose, AMaximized: Boolean): TTyWindowMenuState;
function TyIsWindowMenuKey(AKey: Word; AShift: TShiftState): Boolean;
function TyTitleBarLayoutFor(AShowMin, AShowMax, AShowClose: Boolean;
  ABarWidth, ABarHeight, AButtonWidthPx, AMarginXPx, AMarginYPx, AGapPx,
  ALeadPadPx, AIconPx, AIconGapPx: Integer; ARightToLeft: Boolean): TTyCaptionLayout;
// TTyCaptionLayout 多一个字段 Icon: TRect（不显示图标时为空矩形）
// TyCaptionLayoutFor 签名不变，改为调 TyTitleBarLayoutFor(..., 0, 0, ...)

// TTyCustomTitleBar
protected
  procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
  procedure PopupWindowMenu(AMenu: TPopupMenu; const AScreenPt: TPoint); virtual;
public
  destructor Destroy; override;
  function DefaultWindowMenu: TPopupMenu;
  function WindowMenu: TPopupMenu;
  function ShowWindowMenu: Boolean;
  function WindowMenuAnchor: TPoint;
  function EffectiveIcon: TIcon;
  property ShowIcon: Boolean read FShowIcon write SetShowIcon default False;
  property Icon: TIcon read FIcon write SetIcon stored IsIconStored;
```

`TyCaptionLayoutFor` 不改签名而是另起 `TyTitleBarLayoutFor`：公开函数加参数即使带默认值也是签名变化（CONTRIBUTING「公开 API 不删、不改签名」）。

## 文件

- 改 `source/tyControls.Form.pas`：常量、记录字段、两个纯函数、`TTyCustomTitleBar` 的图标 / 菜单、`TTyTitleBar` 发布段末尾两行、`TTyForm.IsShortcut`。
- 改 `source/tyControls.StrConsts.pas`、`languages/tyControls.StrConsts.pot`、`languages/tycontrols.strconsts.zh_CN.po`、`languages/tycontrols.strconsts.en.po`。
- 改 `themes/light.tycss`、`source/tyControls.DensityPack.pas`；生成 `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`。
- 改 `tests/test.themes.pas`（GMETRICS）、`tests/golden/{light,dark,showcase}.golden.txt`。
- 新建 `tests/test.titlebar.menuicon.pas`；改 `tests/tytests.lpr`（uses 加一项）。
- 生成 `tests/test.customclasses.mimic.pas`；核对 `tests/fixtures/customclasses/fresh-streams.txt`。
- 改 `examples/toolwindows/umain.lfm`（`ShowIcon = True`，内嵌菜单栏 `alLeft`）。
- 改 `docs/controls/titlebar.md`、`docs/controls/ttyform.md`（无英文版）。

---

### Task 1: 主题令牌

**Files:** `themes/light.tycss`、`source/tyControls.DensityPack.pas`、生成两单元、`tests/test.themes.pas`、三个 golden。

- [ ] **Step 1**：`light.tycss` `:root` 几何段，`--titlebar-padding: 8px;` 之前插入（字母序）：

```css
  --titlebar-icon-gap: 6px;
  --titlebar-icon-size: 16px;
```

- [ ] **Step 2**：`DensityPack.pas`，`'  --titlebar-height: 48px;'` 行之后插入：

```pascal
    '  --titlebar-icon-gap: 8px;' + LineEnding +
    '  --titlebar-icon-size: 20px;' + LineEnding +
```

（图标槽 ×1.25 = 20，间距走 4px 尺度 = 8，与单元头注释的规律一致。）

- [ ] **Step 3**：`test.themes.pas` 的 `GMETRICS` 在 `'--titlebar-padding',` 前加 `'--titlebar-icon-gap', '--titlebar-icon-size',`；三个 golden 在 `metric --titlebar-padding => 8` 前加两行 `metric --titlebar-icon-gap => 6`、`metric --titlebar-icon-size => 16`（Task 7 编译后以 `.actual` 核对只多这两行）。
- [ ] **Step 4**：`powershell -File scripts/gen-defaulttheme.ps1; powershell -File scripts/gen-tycss-catalog.ps1`，`git diff --stat` 只该动 `DefaultTheme.pas`（两行令牌）与 `Css.Catalog.pas`（两个令牌名，数组上界 +2）。生成前先确认 `git checkout` 之前的 `DefaultTheme.pas` 与 light.tycss 同步（重跑一次、`git diff --quiet` 为真），否则停下。
- [ ] **Step 5**：提交 `feat(titlebar): icon size and gap tokens`，正文 `Refs #9`。

判据：`TTitleBarIconTest.TestIconTokensMatchTheControlDefaults` —— light.tycss 解析出 16 / 6 且等于 `TyTitleBarIconSizeDef` / `TyTitleBarIconGapDef`；现代密度控制器解析出 20 / 8。变异 M18（light.tycss 的 16 改 18）必须红。

### Task 2: 可翻译字符串

**Files:** `source/tyControls.StrConsts.pas`、三份语言文件。

- [ ] **Step 1**：`StrConsts.pas` 的 `rsTyToolWindowRestore` 附近加：

```pascal
  // --- Title bar: the window menu (right-click, the icon, Alt+Space) ---
  // Same items, order and mnemonics as the Windows system menu.
  rsTyWindowMenuRestore  = '&Restore';
  rsTyWindowMenuMinimize = 'Mi&nimize';
  rsTyWindowMenuMaximize = 'Ma&ximize';
  rsTyWindowMenuClose    = '&Close';
```

- [ ] **Step 2**：`.pot` 末尾（`rstywindowmenu*` 在 `rstyupdownalreadyassociated` 之后，字母序）按 close / maximize / minimize / restore 追加四条 `msgstr ""`；`zh_CN.po` 末尾追加 `还原(&R)`、`最小化(&N)`、`最大化(&X)`、`关闭(&C)`（Windows 中文系统菜单的写法）；`en.po` 末尾追加 msgstr = msgid。保持 CRLF（Write 落文件后 `file` 核对）。
- [ ] **Step 3**：提交 `feat(titlebar): window menu strings`，`Refs #9`。

判据：`test.i18n` 的 pot 覆盖测试（已有）；变异 M22（删掉 pot 里 `rstywindowmenuclose` 那条）必须红。

### Task 3: 布局——图标槽（测试先行）

**Files:** `tests/test.titlebar.menuicon.pas`（新建，本任务写图标布局部分）、`tests/tytests.lpr`、`source/tyControls.Form.pas`。

- [ ] **Step 1：测试**（`TTitleBarIconTest`）

```pascal
procedure TTitleBarIconTest.TestLayoutUnchangedWhenIconOff;
{ ShowIcon = False must be the old layout to the pixel: TyCaptionLayoutFor (the unchanged
  public entry) and TyTitleBarLayoutFor with a zero icon agree on every rect, over widths,
  margins and both reading directions. }
var w, m: Integer; rtl: Boolean; a, b: TTyCaptionLayout;
begin
  for rtl := False to True do
    for w := 0 to 400 do
      for m := 0 to 3 do
      begin
        a := TyCaptionLayoutFor(True, w mod 2 = 0, True, w, 32, 46, m, m, m, 8, rtl);
        b := TyTitleBarLayoutFor(True, w mod 2 = 0, True, w, 32, 46, m, m, m, 8, 0, 0, rtl);
        AssertTrue(Format('w=%d m=%d rtl=%s', [w, m, BoolToStr(rtl, True)]),
          SameLayout(a, b));
        AssertTrue('no icon rect when the icon is off', IsRectEmpty(b.Icon));
      end;
end;
```

另：`TestBarLayoutUnchangedWhenIconOff`（标题栏实例 `Icon` 设了图、`ShowIcon=False`：`CaptionLayout.Content.Left = TTitleBarProbe.LeadPad`、`Icon` 空）；`TestShowIconReservesSlotAndShiftsContent`（`ShowIcon=True`：`Icon = Rect(pad, (H-s) div 2, pad+s, ...)`、`Content.Left = pad+s+gap`，`s`/`gap` 按 `Font.PixelsPerInch` 由 16/6 算出）；`TestIconMirrorsInRtl`（`BiDiMode := bdRightToLeft`：`Icon.Right = W - pad`、`Content.Right = W - pad - s - gap`）；`TestAdjustClientRectGivesTheIconItsRoom`（`AdjustClientRect` 左边比关图标时多 `s+gap`）；`TestIconNeverTallerThanTheBar`（高 10 的条：图标边长 10）；`TestIconTokensScaleWithPPI`（`Font.PixelsPerInch := 192` → 边长 32、间距 12）。

`tytests.lpr` 的 uses 在 `test.form,` 那行加 `test.titlebar.menuicon,`。

- [ ] **Step 2：实现**

```pascal
function TyTitleBarLayoutFor(AShowMin, AShowMax, AShowClose: Boolean;
  ABarWidth, ABarHeight, AButtonWidthPx, AMarginXPx, AMarginYPx, AGapPx,
  ALeadPadPx, AIconPx, AIconGapPx: Integer; ARightToLeft: Boolean): TTyCaptionLayout;
{ 原 TyCaptionLayoutFor 的函数体整体搬来，只改两处：
  1) 算 Content 之前：
       lead := ALeadPadPx;
       if AIconPx > 0 then
       begin
         s := AIconPx; if s > ABarHeight then s := ABarHeight;
         Result.Icon := Rect(ALeadPadPx, (ABarHeight - s) div 2, ALeadPadPx + s, (ABarHeight - s) div 2 + s);
         lead := ALeadPadPx + s + AIconGapPx;
       end;
       Result.Content := Rect(lead, 0, ABarWidth - span, ABarHeight);
  2) 镜像段加一行 Result.Icon := BidiFlipRect(Result.Icon, bar, True);（仅当非空）}

function TyCaptionLayoutFor(...同原签名...): TTyCaptionLayout;
begin
  Result := TyTitleBarLayoutFor(AShowMin, AShowMax, AShowClose, ABarWidth, ABarHeight,
    AButtonWidthPx, AMarginXPx, AMarginYPx, AGapPx, ALeadPadPx, 0, 0, ARightToLeft);
end;
```

`TTyCustomTitleBar.CaptionLayoutAt` 按 `FShowIcon` 传 `IconSizePx` / `IconGapPx`（关时 0 / 0）。`SetShowIcon`：变化时 `ReAlign; Invalidate;`（对齐子控件进新的内容区）。构造里 `FIcon := TIcon.Create; FIcon.OnChange := @IconChanged;`；析构释放。

- [ ] **Step 3**：提交 `feat(titlebar): ShowIcon reserves an icon slot at the reading start`，`Refs #9`。

判据 / 变异：M9（`CaptionLayoutAt` 不看 `FShowIcon`、总传图标尺寸）→ `TestBarLayoutUnchangedWhenIconOff` 红；M10（`lead` 漏加 `AIconGapPx`）→ `TestShowIconReservesSlotAndShiftsContent` 红；M11（镜像段漏掉 `Icon`）→ `TestIconMirrorsInRtl` 红；M17（`IconSizePx` 不乘 PPI）→ `TestIconTokensScaleWithPPI` 红。`SetShowIcon` 里的 `ReAlign`：无头跑不到 LCL 对齐引擎（仓库记忆），不做变异，由示例冒烟看（主控）。

### Task 4: 画图标与取图

**Files:** 测试文件、`Form.pas`。

- [ ] **Step 1：测试**
  - `TestIconOffRendersSameWithOrWithoutIcon`：两个条，同主题（`TyTitleBar { background: #FFFFFF; color: #000000; border-width: 0px; }`）、同尺寸、同标题；一个设了红色图标且 `ShowIcon=False`，一个没设——`RenderTo` 到哨兵底色的 32 位位图，逐像素相同。
  - `TestIconPaintsInItsSlot`：`ShowIcon=True` + 纯红 16×16 图标 → 图标矩形中心像素为红；`ShowIcon=False` 时全图无红像素。
  - `TestCaptionStartsAfterTheIcon`：标题 `'WWWW'`，开图标时最左的深色像素 x ≥ `Icon.Right`；关图标时 < `Icon.Right`（证明这个量真的动了）。
  - `TestIconSourcePriority`：自己的 `Icon` → 宿主窗体 `Icon` → `Application.Icon` → nil（`Application.Icon` 先存一份、测完原样还回）。
  - `TestIconStoredOnlyWhenSet`：`IsStoredProp(bar, 'Icon')` 空时 False、设了 True；`TestShowIconAndIconRoundTrip`：`WriteComponent` / `ReadComponent` 往返后 `ShowIcon=True`、`Icon` 非空且宽 16。
  - `TestShowIconDefaultsFalse`：新实例 `ShowIcon=False`、`Icon.Empty`。

- [ ] **Step 2：实现**

```pascal
function TTyCustomTitleBar.EffectiveIcon: TIcon;
var f: TCustomForm;
begin
  if not FIcon.Empty then Exit(FIcon);
  f := GetParentForm(Self);
  if (f <> nil) and (f.Icon <> nil) and not f.Icon.Empty then Exit(f.Icon);
  if (Application <> nil) and (Application.Icon <> nil) and not Application.Icon.Empty then
    Exit(Application.Icon);
  Result := nil;
end;

procedure TTyCustomTitleBar.DrawIcon(P: TTyPainter; const ARect: TRect);
{ 复制一份再挑尺寸（V9）；TBitmap 作桥（同 TTyImage）；尺寸不符时 rmFineResample。 }
var src, ico: TIcon; tmp: TBitmap; bmp, sized: TBGRABitmap; side: Integer; want: TSize;
begin
  side := ARect.Right - ARect.Left;
  if side <= 0 then Exit;
  src := EffectiveIcon;
  if src = nil then Exit;
  ico := TIcon.Create; tmp := TBitmap.Create; bmp := nil; sized := nil;
  try
    ico.Assign(src);
    if ico.Count > 1 then
    begin
      want.cx := side; want.cy := side;
      ico.Current := ico.GetBestIndexForSize(want);
    end;
    tmp.Assign(ico);
    if (tmp.Width <= 0) or (tmp.Height <= 0) then Exit;
    bmp := TBGRABitmap.Create(tmp);
    if (bmp.Width <> side) or (bmp.Height <> side) then
    begin
      sized := bmp.Resample(side, side, rmFineResample) as TBGRABitmap;
      P.DrawGlyphBitmap(ARect, sized);
    end
    else
      P.DrawGlyphBitmap(ARect, bmp);
  finally
    sized.Free; bmp.Free; tmp.Free; ico.Free;
  end;
end;
```

`RenderTo` 在 `DrawFrame` 之后：`if FShowIcon then DrawIcon(P, CaptionLayoutAt(W, H).Icon);`。`IconChanged`：`if FShowIcon then Invalidate`。`SetIcon`：`nil` → `FIcon.Clear`，否则 `FIcon.Assign`。`IsIconStored := not FIcon.Empty`。

- [ ] **Step 3**：提交 `feat(titlebar): draw the icon, falling back to the form's and the application's`，`Refs #9`。

判据 / 变异：M8（`RenderTo` 去掉 `FShowIcon` 门）→ `TestIconOffRendersSameWithOrWithoutIcon` 红；M14（`EffectiveIcon` 先看窗体再看自己）→ `TestIconSourcePriority` 红；M16（`IsIconStored` 恒 True）→ `TestIconStoredOnlyWhenSet` 红。

### Task 5: 默认窗口菜单、右键、图标的鼠标

**Files:** 测试文件、`Form.pas`。

- [ ] **Step 1：测试**（`TTitleBarWindowMenuTest`；测试替身 `TMenuProbeBar = class(TTyTitleBar)` 覆写 `PopupWindowMenu` 记下菜单与屏幕点、不真弹；`CallContextPopup` / `InjectMouseDown` / `InjectDblClick` 暴露 protected 入口）
  - 纯函数四条：`TestStateNormalWindow`（三项可见；还原灰、最小化 / 最大化可用；关闭可见）、`TestStateMaximized`（还原可用、最大化灰）、`TestStateWithoutMinAndMaxHidesSizingItems`、`TestStateMaximizedWithoutButtonsStillRestores`。
  - `TestDefaultMenuFollowsBorderIcons`：`TTyForm` + 探针条；`BorderIcons := [biSystemMenu, biMinimize]` → 最大化可见但灰；`[biSystemMenu]` → 前三项与分隔线不可见、关闭可见；`Resizable := False` → 最大化灰。
  - `TestDefaultMenuFollowsTheMaximizedChrome`：引擎 `ToggleMaximize` 之后还原可用、最大化灰；再 `ToggleMaximize` 回来反过来。
  - `TestCloseItemShowsAltF4`：非 Darwin `ShortCut = ShortCut(VK_F4, [ssAlt])`，Darwin 为 0。
  - `TestMenuItemsClickTheCaptionButtons`：独立条，三个按钮挂记录器；点「最小化」只触发最小化按钮，「最大化」只触发最大化按钮，「关闭」只触发关闭按钮，最大化后点「还原」触发最大化按钮。
  - `TestRightClickPopsTheDefaultMenu`：`CallContextPopup(Point(50, 10))` → 记下的是 `DefaultWindowMenu`、点 = `ClientToScreen(Point(50, 10))`、Handled = True、`PopupComponent = bar`。
  - `TestUserPopupMenuWins`：设 `PopupMenu` → 不记录、Handled = False；`WindowMenu = 用户的`。
  - `TestRightClickOnAHostChildBubbles`：条上放一个窗口化的 `TTyButton`（`SetBounds(100, 2, 40, 20)`），在 (110, 10) 右键 → 不记录；在 (50, 10) → 记录。
  - `TestOnContextPopupHandledSuppresses`：`OnContextPopup` 置 Handled → 不记录。
  - `TestMenuKeyUsesTheAnchor`：(-1, -1) → 记下的点 = `WindowMenuAnchor` = `ClientToScreen(Point(0, ClientHeight))`；开图标后 = `ClientToScreen(Point(Icon.Left, ClientHeight))`。
  - `TestDefaultMenuNeverBecomesThePopupMenuProperty`：调过 `DefaultWindowMenu` / 右键之后 `PopupMenu = nil`（V1 的陷阱）。
  - `TestDefaultMenuThemedByTheBarsController`：`(DefaultWindowMenu as TTyPopupMenu).Controller = bar.ActiveController`。
  - `TestIconClickOpensTheMenuWithoutDragging`：`TTyForm` + 探针条、开图标；在图标中心 `InjectMouseDown(mbLeft, [])` → 记录、锚点为图标左下、引擎 `Dragging = False`；`ShowIcon=False` 时同一点按下 → 不记录、`Dragging = True`。
  - `TestIconDoubleClickClosesAndDoesNotMaximize`：窗体 `OnCloseQuery` 记录并 `CanClose := False`；图标上 `InjectMouseDown(mbLeft, [ssDouble])` + `InjectDblClick` → 关窗请求一次、引擎未最大化。

- [ ] **Step 2：实现**（要点，完整代码见提交）
  - `TyWindowMenuStateFor` 按 D1 表。
  - `BuildWindowMenu`：`FWindowMenu := TTyPopupMenu.Create(nil)`（不给 Owner：给标题栏的话进它的 `Components`，还得操心流式化；析构里释放），五项按 `TyWindowMenu*Index` 顺序，关闭项 `{$IFNDEF DARWIN} ShortCut := Menus.ShortCut(VK_F4, [ssAlt]) {$ENDIF}`。
  - `DefaultWindowMenu`：建好后每次刷新标题（resourcestring 可能已被翻译）、可见、可用、`Controller := ActiveController`。
  - `IsWindowMaximized := ((FMaxButton <> nil) and (FMaxButton.Kind = cbkRestore)) or (宿主窗体 WindowState = wsMaximized)`（V14）。
  - `WindowMenu`、`ShowWindowMenu`（设计期 False）、`WindowMenuAnchor`、`PopupWindowMenu`（`PopupComponent := Self; PopUp(X, Y)`）。
  - `DoContextPopup` 按 D2 / D3；`HostChildAt` 只认可见的 `TWinControl`、排除三个标题按钮。
  - `MouseDown`：Win32 顶边热区之后，`FIconPressed := (Button = mbLeft) and FShowIcon and not csDesigning and PtInRect(CaptionLayout.Icon, Point(X, Y))`；inherited；是图标就 `ssDouble` → `CloseFromIcon`，否则 `ShowWindowMenu`，`Exit`（不进引擎）。`DblClick`：inherited 之后 `if FIconPressed then Exit`。
- [ ] **Step 3**：提交 `feat(titlebar): themed default window menu on right-click and on the icon`，`Refs #9`。

判据 / 变异：M1（还原可用 = 可见）→ `TestStateNormalWindow` 红；M2（可见去掉「已最大化」）→ `TestStateMaximizedWithoutButtonsStillRestores` 红；M3（最大化可用不看已最大化）→ `TestStateMaximized` 红；M4（能最大化只看开关、不看 `FOffered`）→ `TestDefaultMenuFollowsBorderIcons` 红；M5（`DoContextPopup` 不看 `PopupMenu`）→ `TestUserPopupMenuWins` 红；M6（去掉 `HostChildAt`）→ `TestRightClickOnAHostChildBubbles` 红；M7（不看 inherited 之后的 Handled）→ `TestOnContextPopupHandledSuppresses` 红；M12（图标分支不 `Exit`）→ `TestIconClickOpensTheMenuWithoutDragging` 红；M13（`DblClick` 不看 `FIconPressed`）→ `TestIconDoubleClickClosesAndDoesNotMaximize` 红；M19（不设 Controller）→ `TestDefaultMenuThemedByTheBarsController` 红；M20（删掉 Alt+F4）→ `TestCloseItemShowsAltF4` 红；M21（「最大化」项接到最小化按钮）→ `TestMenuItemsClickTheCaptionButtons` 红。

### Task 6: Alt+Space、发布、示例、文档

**Files:** `Form.pas`（`TTyForm.IsShortcut`、`TTyTitleBar` 发布段）、测试文件、mimic、`examples/toolwindows/umain.lfm`、两份文档。

- [ ] **Step 1：测试**
  - `TestAltSpaceOpensTheWindowMenu`：`TTyForm` + 探针条，`KeyData` 带 `MK_ALT`、`CharCode = VK_SPACE` → `IsShortcut` True 且记录、锚点 = `WindowMenuAnchor`；非 Darwin。Darwin 编译下断言 False。
  - `TestOnlyAltSpaceIsTheWindowMenuKey`：`TyIsWindowMenuKey`：Alt+Space True；Space、Alt+X、Shift+Alt+Space、Ctrl+Alt+Space False；窗体上 Alt+X → `IsShortcut` False、不记录。
  - `TestAltSpaceWithoutATitleBarIsNotEaten`：没有标题栏的 `TTyForm` → False。
- [ ] **Step 2：实现**

```pascal
function TyIsWindowMenuKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (AKey = VK_SPACE) and (AShift * [ssShift, ssCtrl, ssAlt, ssMeta] = [ssAlt]);
end;

function TTyForm.IsShortcut(var Message: TLMKey): Boolean;
begin
  {$IFNDEF DARWIN}
  { Alt+Space opens the window menu, as it opens the system menu of a native window. Not on
    macOS: Option+Space types a no-break space there, and a mac window has no window menu. }
  if TyIsWindowMenuKey(Message.CharCode, KeyDataToShiftState(Message.KeyData))
     and (FTitleBar <> nil) and FTitleBar.Visible
     and not (csDesigning in ComponentState) and FTitleBar.ShowWindowMenu then
    Exit(True);
  ...原有菜单栏分发...
```

`TTyTitleBar` 发布段 `property ShowClose;` 之后追加 `property ShowIcon;`、`property Icon;`。

- [ ] **Step 3**：`python scripts/gen-mimic.py`，`git diff tests/test.customclasses.mimic.pas` 只该是 `TGenTitleBar` 段末多两行。fresh-streams 在 Task 7 编译后用 `TY_WRITE_FRESH_STREAMS=1` 重写，预期无 diff。
- [ ] **Step 4：示例** `examples/toolwindows/umain.lfm`：`Bar` 加 `ShowIcon = True`；`MainMenuBar` 加 `Align = alLeft`、`BorderSpacing.Top = 4`、`BorderSpacing.Bottom = 4`，`Left` 改为开图标后的内容区起点 30（8 + 16 + 6）。程序图标来自工程自带的 `toolwindows_example.ico`（`Application.Icon`）。示例已有真标题栏与运行时换肤。
- [ ] **Step 5：文档** titlebar.md：属性表加 `ShowIcon` / `Icon`，新增「窗口菜单」「图标」两节（规则表、取图顺序、令牌、鼠标、`PopupMenu` 优先、冒泡、平台差异、自由放置子控件不跟着挪）；ttyform.md：系统按钮行为一节后加窗口菜单与 Alt+Space。
- [ ] **Step 6**：提交（代码 `feat(titlebar): Alt+Space opens the window menu; publish ShowIcon and Icon`；示例与文档 `docs(titlebar): window menu and icon`，最后一个提交正文 `Fixes #9`）。

判据 / 变异：M15（`TyIsWindowMenuKey` 不看 `VK_SPACE`）→ `TestOnlyAltSpaceIsTheWindowMenuKey` 红；M23（`IsShortcut` 不看 `FTitleBar <> nil`）→ `TestAltSpaceWithoutATitleBarIsNotEaten` AV / 红；发布段：G9 mimic 守卫（已有）——变异 M24（删掉 `TTyTitleBar` 的 `property Icon;`、不重生 mimic）必须红。

### Task 7: 编译、全量、变异、签收

- [ ] `lazbuild -B tests/tytests.lpi`（只编测试），exe 复制成 `tests/tytests-tb9.exe` 再跑，输出重定向到 scratchpad。
- [ ] 先跑 `--suite=TTitleBarIconTest`、`TTitleBarWindowMenuTest`、`TTestThemeGolden`、`TTyCustomClassesGuardTest`、`TI18NTest`、`test.form` 里的标题栏几组、`test.rtl.chrome`；再全量。
- [ ] fresh-streams：`$env:TY_WRITE_FRESH_STREAMS='1'` 跑 `TTyCustomClassesGuardTest.TestFreshFormFileTextUnchanged`，`git diff` 应为空。
- [ ] 变异 M1–M24：改一行 → 读回比对命中 → `lazbuild -B` → 跑对应 suite 必须红 → 写回原字节 → 重编 → 绿。
- [ ] 签收写在本文末。
- [ ] **【主控执行】** 编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编 `examples/toolwindows`、冒烟；手点见文末。

---

## 签收

**2026-10-05，实现 agent。**

**提交**（`main` @ `140496e6` 之后）：`70a93b1a` 计划；`9af9e01f` 令牌（Task 1）；`e796fc02` 字符串（Task 2）；`1746f10b` 功能与测试（Task 3–6 的代码部分合成一个提交：几处改动落在同一个类声明里，按任务拆反而要中间态能编过，不值）；`dd5d30cc` 示例与文档；本签收提交。

**编译与测试**：`lazbuild -B tests/tytests.lpi` 通过，exe 复制成 `tests/tytests-tb9.exe` 跑。
- 新增两组：`TTitleBarWindowMenuTest` 20 条、`TTitleBarIconTest` 15 条，全绿。
- 相关：`TI18NTest` 7、`TTyCustomClassesGuardTest` 11、`TTestThemeGolden` 8，全绿。
- **全量 8799 条，0 失败 0 错误**，没有计时类偶发红。
- fresh-streams：`TY_WRITE_FRESH_STREAMS=1` 重写后内容**无 diff**（只是写出时换成了 LF，已转回 CRLF）——两个新属性的默认值都不写进窗体文件，符合 V18 的预期。
- mimic：`gen-mimic.py` 的 diff 只有 `TGenTitleBar` 段末多出 `property ShowIcon;`、`property Icon;` 两行。
- 生成器：改动前先重跑两个生成器确认与源同步（`git diff --quiet` 为真），改动后 `DefaultTheme.pas` 只多两行令牌、`Css.Catalog.pas` 只多两个令牌名与数组上界。

**变异**（`mut.py`：读原字节 → 断言命中一次 → 写入并读回比对 → `lazbuild -B` → 跑对应 suite → 写回原字节并读回比对；全部做完后再 `-B` 一次，上面那几组重跑全绿）：

| 变异 | 改了什么 | 结果 |
|---|---|---|
| M1 | 还原可用 = 三项可见 | 红（2） |
| M2 | 三项可见去掉「已最大化」 | 红（1） |
| M3 | 最大化可用不看已最大化 | 红（2） |
| M4 | 能最大化只看开关、不看 `FOffered` | 红（1） |
| M5 | `DoContextPopup` 不让 `PopupMenu` | 红（1） |
| M6 | 去掉宿主子控件冒泡判断 | 红（1） |
| M7 | 不看 inherited 之后的 Handled | 红（1） |
| M8 | `RenderTo` 去掉 `FShowIcon` 门 | **不做**：等价变异——关图标时 `CaptionLayoutAt` 给的 `Icon` 是空矩形，`DrawIcon` 首行就退出，去掉门画面不变。「关图标却画出图标」只能经 M9 发生，M9 红 |
| M9 | `CaptionLayoutAt` 总传图标尺寸 | 红（4） |
| M10 | 内容区漏加图标间距 | 红（5） |
| M11 | 镜像漏掉 `Icon` | 红（1） |
| M12 | 图标分支不 `Exit`（落进拖动） | 红（1） |
| M13 | `DblClick` 不看 `FIconPressed` | 红（1） |
| M14 | 取图先窗体后自己 | 红（1） |
| M15 | `TyIsWindowMenuKey` 不看 Space | 红（2） |
| M16 | `IsIconStored` 恒 True | 红（1） |
| M17 | 图标尺寸不乘 PPI | 红（1） |
| M18 | light.tycss 图标 16 → 18 | 红（1） |
| M19 | 默认菜单不设 Controller | 红（1） |
| M20 | 关闭项去掉 Alt+F4 | 红（1） |
| M21 | 「最大化」接到最小化按钮 | 红（1） |
| M22 | pot 删掉 `rstywindowmenuclose` | 红（`TI18NTest` 1） |
| M23 | `IsShortcut` 不看 `FTitleBar <> nil` | 红（错误 1，nil 访问） |
| M24 | 最终类删掉 `property Icon;`（不重生 mimic） | 红（`TTyCustomClassesGuardTest` 1） |
| M26 | `IsWindowMaximized` 恒 False | 红（2） |
| M27 | 分隔线不看前三项 | 红（1） |
| M28 | 锚点不跟图标走 | 红（1） |

27 个跑了的变异全红，没有存活。

**与计划的出入**：Task 3–6 的代码合并为一个提交（见上）；变异表比计划多了 M26–M28（计划写了判据、没编号的三处）；M8 判为等价变异。

**没有自动化覆盖、要人看的**：
- `SetShowIcon` 里的 `ReAlign`（无头跑不到 LCL 对齐引擎）：示例里切换 / 启动时内嵌菜单栏是否落在图标之后。
- 真弹窗：`PopupWindowMenu` 的真实路径（`TTyPopupMenu.PopUp`）测试里被替身截住。
- Win32 上 Alt+Space：`WM_SYSKEYDOWN` 被吃掉后，后续 `WM_SYSCHAR` 是否还会让 `DefWindowProc` 弹出原生系统菜单（预期 LCL 在 KeyDown 已处理时丢掉随后的字符消息）。
- 图标双击：第一下弹出菜单、菜单窗口抢走激活后，第二下是否仍以双击（`ssDouble`）到达标题栏。

**【主控执行】**
1. 编 `tycontrols.lpk`、`tycontrols_dt.lpk`。
2. 编 `examples/toolwindows`，冒烟：标题栏左侧出现程序图标，菜单栏在图标之后、不与图标重叠；换主题（含现代密度）后图标与菜单栏位置跟着变。
3. 手点：右键标题栏空白处 → 菜单四项，状态随最大化 / 还原变化；右键菜单栏、主题下拉框 → 不弹窗口菜单；单击图标 → 菜单挂在图标正下方；双击图标 → 关窗；Alt+Space → 菜单；最大化后菜单里「还原」可用、「最大化」灰；菜单项「关闭」走 `OnCloseQuery`。
4. 设计器：选中标题栏，对象查看器里 `ShowIcon`、`Icon` 出现在 `ShowClose` 之后；`Icon` 的「...」打开 LCL 的图像编辑器，载入 `.ico` 后设计面板上（`ShowIcon=True` 时）立即重画；未设图时保存的 `.lfm` 里没有 `Icon`。
