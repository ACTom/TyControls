# TTyForm — API 参考

## 1. 概述

`TTyForm` 是 TyControls 自绘窗口（自定义窗框）的**唯一**入口：要让窗口拥有自绘标题栏、保留的内容区以及未来的 ribbon/菜单/工具栏条带，**让你的窗体类从 `TTyForm` 继承**即可：

```pascal
type
  TMainForm = class(TTyForm)   // 自绘窗框窗口
    // ... 你的控件（拖到内容区中）
  end;
```

需要**原生**（系统标题栏、系统边框、无自绘）的窗口时，仍然继承普通的 `TForm`——这是原生路径，不需要 TyControls 做任何处理。一句话：

> **要原生 → 用 `TForm`；要自绘窗框 → 继承 `TTyForm`。**

`TTyForm` 自出生即为无边框窗口（`BorderStyle = bsNone`），并在构造时**代码创建**两个子组件：

- `TitleBar: TTyTitleBar`——停靠在顶部（`alTop`）的标题栏（"band 0"，条带 0）。
- `ContentPanel: TTyContentPanel`——填充其余区域（`alClient`）的保留内容区。

**你的应用控件放在内容区里**（在设计器中直接拖到内容面板上）。由于内容面板的原点已经落在标题栏条带**下方**，控件永远不会被标题栏覆盖——无论设计期还是运行期。这从**构造上**消除了旧 `TTyFormChrome` 把标题栏画到既有控件之上的"覆盖 bug"。

> **历史变更：** 旧的窗框控制器 `TTyFormChrome`（挂在普通 `TForm` 上的非可视 `TComponent`）已被**移除**，由 `TTyForm` 取代。若你在迁移旧代码，请参见 [formchrome.md](formchrome.md)。

## 2. 单元

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Form` |
| 基类 | `TForm` |
| 出生边框样式 | `bsNone`（无边框） |
| 设计期可用 | 是（作为窗体祖类，从它继承；它不是放在调色板上的组件） |

## 3. 架构

```
TTyForm = class(TForm)                      // 构造时即 bsNone
  ├─ TitleBar : TTyTitleBar  (alTop)        // 条带 0：标题栏
  │     ├─ 系统按钮（最小化/最大化/关闭）—— 代码持有，位于右侧空槽
  │     └─ 可定制内容区（左侧标题/图标 + AdjustClientRect 中间条）
  ├─ （未来条带：菜单 / ribbon / 工具栏 —— alTop，在 ContentPanel 之前创建）
  └─ ContentPanel : TTyContentPanel (alClient)   // 保留的客户区
        └─ 你的控件放这里（它们的 (0,0) 已在标题栏下方）

TTyChromeEngine（由 TTyForm 拥有/释放）     // 与窗体无关的窗口行为
  拖动移动 · 边缘缩放 + 悬停光标 · 自绘无边框最大化/还原 · 跨屏 DPI 重缩放
```

窗口行为本身（标题栏拖动移动、8 向边缘缩放、自绘无边框最大化/还原、跨显示器 DPI 重缩放）被抽取到一个**与窗体无关**的辅助对象 `TTyChromeEngine` 中，`TTyForm` 拥有它并把事件委托给它。这让 `TTyForm` 保持轻薄，也保留了无头（headless）测试能力。

> **保留缩放边框环（resize ring）：** 由于内容面板覆盖了窗口内部，`TTyForm` 在左/右/下保留了一圈 **6px** 的缩放感应边框（私有字段，默认 6，引擎的 `BorderZone`），让窗体仍能命中边缘缩放。这圈边框不是可发布属性。

## 4. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `TitleHeight` | `Integer` | `32` | 标题栏高度（逻辑像素）。写入时重新布局顶部条带（`TitleBar.Height`）。 |
| `ShowMinimize` | `Boolean` | `True` | 控制最小化按钮的 `Visible`，并即时重排标题栏按钮与内容区右侧内缩。 |
| `ShowMaximize` | `Boolean` | `True` | 控制最大化按钮的 `Visible`，并即时重排标题栏按钮与内容区右侧内缩。 |

> 缩放边框宽度（旧 `TTyFormChrome.BorderZone`）在 `TTyForm` 上**不再是 published 属性**；它是固定的 6px 内部环。

### public 只读属性（non-published）

| 属性 | 类型 | 说明 |
|------|------|------|
| `TitleBar` | `TTyTitleBar` | 自绘标题栏子组件（构造时创建，`SetSubComponent(True)`，名为 `TyTitleBar`）。 |
| `ContentPanel` | `TTyContentPanel` | 保留的内容区子组件（构造时创建，`SetSubComponent(True)`，名为 `TyContent`，`Align = alClient`）。 |

### 继承的标准 TForm 生命周期事件

`TTyForm` **就是**一个 `TForm`，因此 `OnCloseQuery`、`OnClose`、`OnShow`、`OnActivate`、`WindowState` 等都是标准的、已 published 的窗体事件，可在对象查看器里直接挂接。旧 `TTyFormChrome` 的自定义 `OnMinimize/OnMaximize/OnRestore` 事件**已废弃**——标准窗体生命周期已经覆盖这些需求（最大化由引擎处理，最小化即 `WindowState := wsMinimized`）。

## 5. 方法

### public 方法

#### `procedure ApplyChromeTheme(AController: TTyStyleController)`

从 `TyForm` 主题令牌解析窗体背景：调用 `AController.Model.ResolveStyle('TyForm', '', [])`，若解析出 `tpBackground` 且为纯色（`tfkSolid`），将该颜色赋给窗体 `Color`/背景。用于让无边框窗体的背景与主题保持一致（遵守"视觉由主题令牌驱动"的硬性原则——背景不在控件代码里写死）。

通常在窗体的 `OnCreate`/`OnShow` 中、加载主题后调用一次：

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
begin
  StyleCtrl := TTyStyleController.Create(Self);
  StyleCtrl.LoadThemeCss(GetThemesDir + 'light.tycss');
  ApplyChromeTheme(StyleCtrl);     // 背景取自 TyForm 主题令牌
  TitleBar.Caption := Caption;     // 同步窗体标题到标题栏
end;
```

### 标题栏系统按钮的行为接线

标题栏右侧三个系统按钮的 `OnClick` 由框架接线，行为如下：

| 按钮 | 行为 |
|------|------|
| 最小化（Min） | `WindowState := wsMinimized` |
| 最大化/还原（Max） | 引擎 `ToggleMaximize`（自绘无边框最大化/还原，避让任务栏工作区） |
| 关闭（Close） | `Close`（走标准 `OnCloseQuery` → `OnClose` 流程） |

## 6. 设计期行为（重要）

`TTyForm` 在 Lazarus 设计器中是**布局级 WYSIWYG**：

- **几何/布局是真实的**——标题栏占据顶部条带，内容面板填充其下方区域；你拖到内容面板上的控件在设计期就位于条带**下方**，与运行期一致。这正是用 `TTyForm` 取代控制器方案的核心收益。
- **标题栏皮肤在设计期是未换肤（unthemed）的**——和**所有**其它 tyControl 一样，设计器没有运行期主题上下文，因此标题栏的自绘**皮肤**在设计期以内置默认外观呈现，而非你运行时加载的 `.tycss` 主题。**这不是 bug**，请勿把设计期未换肤的标题栏当成缺陷。

> **流式化（streaming）说明：** `TitleBar` 与 `ContentPanel` 用 `SetSubComponent(True)` + 固定 `Name`（`TyTitleBar` / `TyContent`）创建。你的窗体继承自 `TTyForm`，其 `.lfm` 是**继承式（inherited）**流，读取器按名字把这两个子控件匹配到活动实例上，**不会**重复创建它们。
>
> **防御式 `Loaded`：** `TTyForm` 覆写了 `Loaded`，把任何错误地以**窗体**为父（而非内容面板）的用户控件重新归位（reparent）到 `ContentPanel`（跳过 `TitleBar`/`ContentPanel` 自身；幂等、运行期无害）。这中和了唯一无法从 LCL 源码证明的一点——IDE 设计器在放置控件时究竟选了哪个父容器。

## 7. 状态与主题

`TTyForm` 自身的窗体背景来自 `TyForm` 主题令牌（经 `ApplyChromeTheme` 应用）。其两个子组件各有自己的 typeKey 与主题规则：

| typeKey | 子组件 | 内置默认 |
|---------|--------|----------|
| `TyTitleBar` | `TitleBar`（`TTyTitleBar`） | 略深于窗体背景的标题条 —— 详见 [titlebar.md](titlebar.md) |
| `TyContentPanel` | `ContentPanel`（`TTyContentPanel`） | `background: var(--surface)`（内容区表面色，与 `TyPanel` 一致；比窗体背景 `darken(--surface, 4%)` 略浅） |
| `TyCaptionButton` | 标题栏系统按钮 | 透明背景，hover/active 着色；`close` 变体 hover 变红 —— 详见 [captionbutton.md](captionbutton.md) |

`TyForm` 令牌在内置主题中为 `background: darken(--surface, 4%)`（窗体背景）。

## 8. 窗口圆角与原生投影阴影

无边框的 `TTyForm` 在支持的平台上**默认**拥有抗锯齿圆角与原生投影阴影——**无需任何主题令牌**。视觉由两个 `TyForm` 令牌驱动，可在 `.tycss` 中覆盖或关闭：

```css
TyForm {
  border-radius: 12px;     /* 圆角半径（默认 8）；逻辑像素 */
  border-radius: 0;        /* 关闭圆角（方角窗口）       */
  window-shadow: false;    /* 关闭原生窗口阴影           */
}
```

> **默认开启：** 内置主题的 `TyForm` 规则未设置这两个令牌，因此走代码默认值（半径 8 + 阴影开）。要关闭就显式写 `border-radius: 0` / `window-shadow: false`。默认半径常量 `TyDefaultWindowRadiusPx` 是代码里唯一的视觉默认值，且完全可被 css 覆盖——仍符合"视觉由主题令牌驱动"的原则。

### 平台支持矩阵

| 平台 | 圆角 | 阴影 |
|------|------|------|
| Windows 11 | 抗锯齿（DWM 圆角偏好） | 随圆角自带的原生阴影 |
| Windows Vista–10 | 方角（不上锯齿 region） | 原生矩形阴影（`DwmExtendFrameIntoClientArea`） |
| Windows XP | 方角 | 无（无 DWM 合成器） |
| macOS | 抗锯齿（`CALayer.cornerRadius`） | 原生（`NSWindow.hasShadow`） |
| Linux（GTK / Qt） | 由桌面环境决定 | 由桌面环境决定 |

### 实现要点

- **抗锯齿优先：** 只在能做出**平滑**圆角的平台圆角（Win11、macOS）；老版 Windows 保持方角，但仍可加原生阴影。这是经过权衡的取舍——锯齿圆角比方角更难看。
- **不限定 Win10+：** Windows 路径通过运行期 `GetProcAddress` 动态加载 `dwmapi.dll`（绝不静态 `external`），因此可执行文件在 Win7/XP 上**照常启动**，查不到 DWM 函数时优雅降级。
- **半径映射：** Win11 的 DWM 只接受枚举（round≈8px / small≈4px / none），无法精确到任意像素，`border-radius` 据此映射到 round/small；macOS 使用精确逻辑像素。
- **最大化变方角：** 最大化时圆角自动关闭（否则四角会露出桌面），还原时恢复——由 chrome 引擎的 `ToggleMaximize` 触发重新应用。
- **应用时机：** 首次显示（`DoShow`）、`Loaded`、主题切换（`ApplyChromeTheme`）、最大化/还原时各应用一次。半径为逻辑像素，故 DPI 变化无需重新应用。
- **架构隔离：** 所有平台/widgetset 代码集中在 `tyControls.WindowEffects` 单元，对外只暴露 `TyApplyWindowEffects` 一个入口；Linux 各 widgetset 留有 widgetset-aware 扩展口（Qt 透明窗 + 自绘抗锯齿圆角 + 自定义阴影是未来最有希望的路径）。

## 9. 未来条带（bands）与 ribbon —— 仅锁定命名/设计

`TTyForm` 的条带模型为**纯增量式（additive）**地添加菜单栏 / ribbon / 工具栏预留了清晰的接缝：

1. **保留的客户区已存在**——`ContentPanel`（由本架构提供）。
2. **条带就是停靠在内容面板之上的 `alTop` 普通控件**，按从上到下的顺序创建，使每个条带先占据自己的条带区、再由 `ContentPanel` 填充剩余区域。**标题栏是条带 0**；ribbon 只是其下方"又一条条带"。条带的创建/对齐顺序是**承重（load-bearing）**的——必须自上而下，每个条带先占据其条带区，再由内容面板填充。
3. **预留主题 typeKey** `TyRibbon`、`TyRibbonTab`、`TyRibbonGroup`——**这是命名决策，请勿把这三个名字用于其它任何用途**。

未来的 `TTyRibbon` 将是一个与窗框无关（chrome-agnostic）的、基于 `TTyCustomTabStrip` 的 `alTop` 控件，通过 `AdjustClientRect` 预留自身的主体区，docked 在内容面板之上、标题栏之下——**不**焊死在标题栏里。它在原生有边框的 `TForm` 上也能工作。

> **增量保证：** 添加条带是未来的纯增量步骤——届时会扩展 `TTyForm` 以**注册条带**，使其堆叠在内容面板之上，并被排除在内容区 reparent 之外。本节记录这一意图，使后续 ribbon 工作保持纯增量、不需返工。

## 10. 注意事项

1. **唯一自绘窗框路径：** 自绘窗框只通过继承 `TTyForm` 获得；普通 `TForm` 是原生（无窗框）路径。不存在"把窗框挂到既有 `TForm` 上"的控制器（旧 `TTyFormChrome` 已移除）。
2. **控件放内容区：** 应用控件应放在 `ContentPanel` 上（设计期直接拖到内容面板）。防御式 `Loaded` 会把误放在窗体根上的控件归位到内容面板，但仍建议直接拖入内容面板以获得正确的设计期 WYSIWYG。
3. **标题文本独立：** `TitleBar.Caption` 与窗体 `Caption` 是独立属性；修改窗体 `Caption` 不会自动更新标题栏，需手动 `TitleBar.Caption := Caption`。
4. **背景来自主题：** 用 `ApplyChromeTheme` 让窗体背景取自 `TyForm` 令牌，不要在代码里写死颜色。
5. **缩放最小尺寸：** 边缘缩放硬编码最小宽度 80px、高度 60px（在引擎中），不可经属性配置。
6. **设计期标题栏皮肤未换肤：** 见第 6 节——这是 tyControls 全库一致的设计期行为，不是缺陷。
7. **最大化避让任务栏：** 引擎 `ToggleMaximize` 使用当前显示器工作区（`Screen.MonitorFromWindow(...).WorkareaRect`），最大化窗口自然避让任务栏。
8. **原生窗口行为缺口：** Windows Aero Snap 仍未实现；Windows DWM 原生投影阴影与圆角**已实现**（见第 8 节「窗口圆角与原生投影阴影」）。详见 [KNOWN_GAPS.md](../KNOWN_GAPS.md)。

## 11. 相关文档

- [titlebar.md](titlebar.md) —— `TTyTitleBar` 标题栏子组件（可定制内容区、`AdjustClientRect`、`ButtonWidth`）。
- [captionbutton.md](captionbutton.md) —— `TTyCaptionButton` 标题栏系统按钮。
- [formchrome.md](formchrome.md) —— 旧 `TTyFormChrome` → `TTyForm` 迁移说明。
- [../events.md](../events.md) —— 全库事件契约；`TTyForm` 使用标准 `TForm` 生命周期事件。
- [../recipes-traffic-lights.md](../recipes-traffic-lights.md) —— traffic-light 风格标题栏按钮配方。
