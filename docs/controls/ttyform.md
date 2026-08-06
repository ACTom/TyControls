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

`TTyForm` 自出生即为无边框窗口（`BorderStyle = bsNone`）。窗体上有两样东西：

- **`Surface: TTyFormSurface`**——铺满窗体（`alClient`）的内容承载容器，**每个窗体有且只有一个**，
  固定名为 `Surface`。它**不是构造时创建的**，而是从 `.lfm` 流式化出来的：File > New 的
  *TyControls Form / Application* 模板已经带好它，设计器里拖控件本来就落进它。
- **`TitleBar: TTyTitleBar`**——可关联的标题栏，走的是 `Form.Menu` 那种「属性指向一个组件」的模式，
  不是硬塞的子组件。它本身也放在 `Surface` 里。

**你的应用控件都放在 `Surface` 里。** 尤其是 `TTyLabel`、`TTyShape` 这类**无窗口的图形控件**——
它们画在父控件身上，直接放在窗体上会被 `Surface` 挡住、**根本看不见**（设计器会提示）。
非可视组件（样式控制器、定时器、对话框组件、图像列表、菜单）不受影响，仍留在窗体上。

> **为什么需要 `Surface`：** 无边框可缩放窗口画不到自己最外圈的像素——合成器给的后备表面比窗口小，
> 右边和下边会留一条没画上的细边。而**子窗口**能画到真正的边缘，所以窗体的主题背景改由 `Surface` 画。
> 在设计器里选中它，`Purpose` 属性里有完整说明。
>
> **`TTyDialog` 没有 `Surface`**：它不可缩放，不需要；控件照常直接放在对话框上。

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
  └─ Surface : TTyFormSurface (alClient)     // 内容承载容器，从 .lfm 流式化
        ├─ TitleBar : TTyTitleBar  (alTop)   // 条带 0：标题栏（由 Form.TitleBar 关联）
        │     ├─ 系统按钮（最小化/最大化/关闭）—— 代码持有，位于右侧空槽
        │     └─ 可定制内容区（左侧标题/图标 + AdjustClientRect 中间条）
        ├─ （其他条带：菜单 / ribbon / 工具栏 —— alTop，按自上而下顺序创建）
        └─ 你的控件放这里

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
| `BorderIcons` | `TBorderIcons` | `[biSystemMenu, biMinimize, biMaximize]` | 决定标题栏按钮：`biSystemMenu`→关闭、`biMinimize`→最小化、`biMaximize`→最大化（仅当 `Resizable`）。变更时即时同步到关联的标题栏。 |
| `Resizable` | `Boolean` | `True` | 是否允许边缘拖拽缩放；同时门控最大化按钮（`False` 时即使含 `biMaximize` 也隐藏最大化）。 |
| `BorderStyle` | `TFormBorderStyle` | `bsNone` | **锁定** `bsNone`（无边框自绘窗）：对象查看器中隐藏，赋任何值都归正为 `bsNone`。 |

> 缩放边框宽度（旧 `TTyFormChrome.BorderZone`）在 `TTyForm` 上**不再是 published 属性**；它是固定的 6px 内部环。

### public 只读属性（non-published）

| 属性 | 类型 | 说明 |
|------|------|------|
| `TitleBar` | `TTyTitleBar` | **可关联**的标题栏——指向窗体上某个 `TTyTitleBar` 实例（`Form.Menu` 模式），不是构造时硬创建的子组件。流式化的 `.lfm` **必须显式写 `TitleBar = <名字>`**，否则窗口拖不动。 |
| `Surface` | `TTyFormSurface` | 内容承载容器（`alClient`，固定名 `Surface`）。由 `.lfm` 流式化，不在构造函数里创建。 |

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

> **流式化（streaming）说明：** `Surface` 与标题栏都来自 `.lfm`，不是构造函数创建的。这一点很要紧：
> **`.lfm` 必须显式写 `TitleBar = <标题栏名字>`**——那是一个关联属性，不写则窗体没有标题栏可拖，
> 窗口拖不动。新建窗体用 File > New 的模板即可，模板已经把两者写好。
>
> **迁移既有窗体：** 把原本直接放在窗体上的控件移进 `Surface`（非可视组件不动）。
> 参考 [examples/button/umain.lfm](../../examples/button/umain.lfm)。

## 7. 状态与主题

`TTyForm` 自身的窗体背景来自 `TyForm` 主题令牌（经 `ApplyChromeTheme` 应用）。其两个子组件各有自己的 typeKey 与主题规则：

| typeKey | 子组件 | 内置默认 |
|---------|--------|----------|
| `TyTitleBar` | `TitleBar`（`TTyTitleBar`） | 略深于窗体背景的标题条 —— 详见 [titlebar.md](titlebar.md) |
| `TyFormSurface` | `Surface`（`TTyFormSurface`） | **随库主题刻意不定义**——`Surface` 画的就是窗体自己的主题背景（`TyForm` 令牌），它自身不该再叠一层表面色。见 [tycss-reference §8.4](../tycss-reference.md) |
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

1. **内容承载容器已存在**——`Surface`（由 `.lfm` 提供）。
2. **条带就是 `Surface` 里停靠在顶部的 `alTop` 普通控件**，按自上而下的顺序创建，每个条带先占据自己的条带区，剩余区域留给内容。**标题栏是条带 0**；ribbon 只是其下方"又一条条带"。条带的创建/对齐顺序是**承重（load-bearing）**的。
3. **预留主题 typeKey** `TyRibbon`、`TyRibbonTab`、`TyRibbonGroup`——**这是命名决策，请勿把这三个名字用于其它任何用途**。

未来的 `TTyRibbon` 将是一个与窗框无关（chrome-agnostic）的、基于 `TTyCustomTabStrip` 的 `alTop` 控件，通过 `AdjustClientRect` 预留自身的主体区，docked 在内容面板之上、标题栏之下——**不**焊死在标题栏里。它在原生有边框的 `TForm` 上也能工作。

> **增量保证：** 添加条带是未来的纯增量步骤——届时会扩展 `TTyForm` 以**注册条带**，使其堆叠在内容面板之上，并被排除在内容区 reparent 之外。本节记录这一意图，使后续 ribbon 工作保持纯增量、不需返工。

## 10. 注意事项

1. **唯一自绘窗框路径：** 自绘窗框只通过继承 `TTyForm` 获得；普通 `TForm` 是原生（无窗框）路径。不存在"把窗框挂到既有 `TForm` 上"的控制器（旧 `TTyFormChrome` 已移除）。
2. **控件放 `Surface` 里：** 设计器里拖控件本来就落进它。图形控件（`TTyLabel` / `TTyShape` 等）**必须**放进去——放在窗体上会被 `Surface` 挡住、看不见。
3. **标题文本独立：** `TitleBar.Caption` 与窗体 `Caption` 是独立属性；修改窗体 `Caption` 不会自动更新标题栏，需手动 `TitleBar.Caption := Caption`。
4. **背景来自主题：** 用 `ApplyChromeTheme` 让窗体背景取自 `TyForm` 令牌，不要在代码里写死颜色。
5. **缩放最小尺寸：** 边缘缩放硬编码最小宽度 80px、高度 60px（在引擎中），不可经属性配置。
6. **设计期标题栏皮肤未换肤：** 见第 6 节——这是 tyControls 全库一致的设计期行为，不是缺陷。
7. **最大化避让任务栏：** 引擎 `ToggleMaximize` 使用当前显示器工作区（`Screen.MonitorFromWindow(...).WorkareaRect`），最大化窗口自然避让任务栏。
8. **原生窗口行为：** Windows Aero Snap（贴边平铺 + 拖到顶端最大化）**已实现**——标题栏拖拽交给系统的原生标题栏移动循环，窗口样式也换成 shell 认可的普通顶层窗口样式；系统自己发起的最大化（Aero Snap / Win+↑ / 任务栏菜单）会被窗框采纳，最大化后仍可拖动（拖动即还原并继续跟随鼠标）。Vista/Win7 与固定尺寸（`Resizable := False`）窗口不参与。Windows DWM 原生投影阴影与圆角**已实现**（见第 8 节「窗口圆角与原生投影阴影」）。

## 11. 相关文档

- [titlebar.md](titlebar.md) —— `TTyTitleBar` 标题栏子组件（可定制内容区、`AdjustClientRect`、`ButtonWidth`）。
- [captionbutton.md](captionbutton.md) —— `TTyCaptionButton` 标题栏系统按钮。
- [formchrome.md](formchrome.md) —— 旧 `TTyFormChrome` → `TTyForm` 迁移说明。
- [../events.md](../events.md) —— 全库事件契约；`TTyForm` 使用标准 `TForm` 生命周期事件。
- [../recipes-traffic-lights.md](../recipes-traffic-lights.md) —— traffic-light 风格标题栏按钮配方。
