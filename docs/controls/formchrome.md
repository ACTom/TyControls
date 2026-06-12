# TTyFormChrome — API 参考

## 1. 概述

`TTyFormChrome` 是一个**非可视组件**（继承自 `TComponent`），用于将 Lazarus 标准窗体改造为自绘无边框窗口。激活后，它接管宿主 `TForm` 的边框样式与鼠标事件，注入一个 `TTyTitleBar` 标题栏，并提供：

- **标题栏拖动移动窗口**（非最大化状态下）
- **8 向边框缩放**（左/右/上/下/四个角，非最大化状态下）
- **双击标题栏切换最大化/还原**（避让工作区，不超出任务栏）
- **最小化、最大化/还原、关闭**（通过标题栏的三个 `TTyCaptionButton`）

`TTyFormChrome` 不继承任何 TyControls 样式基类，其 `TTyTitleBar` 子控件负责自身的样式渲染。

> **设计时行为：** 在 `csDesigning` 状态下（Lazarus IDE 中），设置 `Active` 不会修改窗体边框，也不会注入标题栏。所有自绘窗框效果只在运行时出现。

> **已知缺口：** 参见 [Known Gaps](../KNOWN_GAPS.md)。主要已知项：Windows Aero Snap 不支持；macOS traffic-light 按钮不仿真（可用 `ShowGlyphOnHoverOnly` + 自定义样式近似，见 [recipes-traffic-lights.md](../recipes-traffic-lights.md)）；Windows 原生阴影尚待实现。macOS 原生阴影与跨屏 DPI 重缩放已在 v1.1 解决。

## 2. 单元

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Form` |
| 基类 | `TComponent` |
| 可视 | 否（非控件） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Active` | `Boolean` | `False` | 核心开关。运行时设为 `True` 调用 `InstallChrome`；设为 `False` 调用 `UninstallChrome`。`csDesigning` 下写入无效果（见注意事项）。 |
| `TitleHeight` | `Integer` | `32` | 标题栏高度（逻辑像素）。运行时修改会立即调整已注入的 `TitleBar.SetBounds`。 |
| `BorderZone` | `Integer` | `6` | 边框拖动感应区宽度（像素）。鼠标进入距窗体边缘此距离范围内视为命中边框，触发 8 向缩放。 |
| `ShowMinimize` | `Boolean` | `True` | 控制最小化按钮的 `Visible`（在 `InstallChrome` 时生效）。 |
| `ShowMaximize` | `Boolean` | `True` | 控制最大化按钮的 `Visible`（在 `InstallChrome` 时生效）。 |

### public 只读属性（non-published）

| 属性 | 类型 | 说明 |
|------|------|------|
| `TitleBar` | `TTyTitleBar` | 注入的标题栏控件。在构造函数中创建（Owner 为 `TTyFormChrome` 自身）；`InstallChrome` 将其 Parent 设为宿主窗体。 |

## 4. 方法

### public 方法

#### `procedure ToggleMaximize`

切换最大化/还原状态：

- **还原 → 最大化：** 保存当前 `BoundsRect` 到 `FSavedBounds`；获取当前显示器的工作区（`Screen.MonitorFromWindow(FForm.Handle).WorkareaRect`，自动避让任务栏）；将窗体 `BoundsRect` 设为工作区矩形；切换 MaxButton 的 `Kind` 为 `cbkRestore`；设置 `FMaximized := True`。
- **最大化 → 还原：** 恢复 `FSavedBounds`；切换 MaxButton 的 `Kind` 为 `cbkMax`；设置 `FMaximized := False`。

若 `FForm = nil`（尚未 InstallChrome 或已 UninstallChrome）则无操作。

### private/internal 方法（行为说明）

#### `procedure InstallChrome`

在 `Active := True`（非设计时）时调用：

1. 保存宿主窗体的原始 `BorderStyle` 到 `FOldBorderStyle`。
2. 将 `FForm.BorderStyle := bsNone`（移除系统标题栏和边框）。
3. 将 `TitleBar.Parent := FForm`，`Align := alTop`，并调用 `SetBounds(0, 0, FForm.ClientWidth, FTitleHeight)`。
4. 根据 `ShowMinimize`/`ShowMaximize` 设置对应按钮 `Visible`。
5. 保存并替换窗体的 `OnMouseDown/OnMouseMove/OnMouseUp`（用于边框缩放逻辑）。
6. 绑定 `TitleBar` 的 `OnMouseDown/OnMouseMove/OnMouseUp/OnDblClick`（用于拖动和双击最大化）。
7. 绑定三个 `TTyCaptionButton` 的 `OnClick`（最小化/最大还原/关闭）。

#### `procedure UninstallChrome`

在 `Active := False` 时调用：

1. 恢复窗体的 `OnMouseDown/OnMouseMove/OnMouseUp`。
2. 恢复 `FForm.BorderStyle := FOldBorderStyle`。
3. 重置最大化状态，将 MaxButton 的 `Kind` 恢复为 `cbkMax`。
4. 将 `TitleBar.Parent := nil`（从窗体移除标题栏）。
5. 清除 `FForm := nil`。

> **注意：** 根据 [Known Gaps](../KNOWN_GAPS.md) 的说明，`Active` 实际应视为启动期的一次性开关。`UninstallChrome` 虽然恢复了 `BorderStyle` 和鼠标事件，但运行时将 `Active` 反复切换未经充分测试；建议在窗体的 `OnCreate`/`OnShow` 中设置一次 `Active := True` 后不再修改。

#### 鼠标事件处理（边框缩放）

- `FormMouseDown`：检测鼠标是否在 `BorderZone` 范围内（调用 `TyHitTestBorder`），记录缩放起始状态。不处理最大化状态（`FMaximized = True` 时跳过）。
- `FormMouseMove`：在 `FResizing = True` 时计算 `DX/DY`，按 `FResizeHit` 方向更新窗体 `BoundsRect`。最小窗体尺寸限制：宽 ≥ 80px，高 ≥ 60px。
- `FormMouseUp`：清除 `FResizing` 和 `FResizeHit`。

#### 鼠标事件处理（标题栏拖动）

- `TitleBarMouseDown`：非最大化状态下，记录 `FDragStart` 坐标，`FDragging := True`。
- `TitleBarMouseMove`：`FDragging = True` 时，将窗体位置偏移 `(X - FDragStart.X, Y - FDragStart.Y)`（注意：拖动时 `FDragStart` 不更新，这是相对于按下时光标在标题栏内的位置的偏移）。
- `TitleBarMouseUp`：`FDragging := False`。
- `TitleBarDblClick`：调用 `ToggleMaximize`。

## 5. 状态与主题

`TTyFormChrome` 本身不绘制任何内容，也没有 typeKey 或主题规则。

其内部的 `TTyTitleBar` 和 `TTyCaptionButton` 各有自己的主题规则，详见：
- [titlebar.md](titlebar.md)
- [captionbutton.md](captionbutton.md)

## 6. 代码示例

### 最基本用法

```pascal
// 在 Form1 的 .pas 文件 interface 区：
uses tyControls.Form;

// 在 Form1 的设计器或 OnCreate 中添加 TTyFormChrome 组件，
// 或纯代码方式：
var
  Chrome: TTyFormChrome;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Chrome := TTyFormChrome.Create(Self);   // Owner = 窗体，随窗体释放
  Chrome.TitleHeight := 32;
  Chrome.BorderZone := 6;
  Chrome.ShowMinimize := True;
  Chrome.ShowMaximize := True;
  Chrome.TitleBar.Caption := Caption;     // 同步窗体标题
  Chrome.Active := True;                  // 激活无边框窗框
end;
```

### 通过 IDE 设计器放置

1. 在 Lazarus 包管理器中安装 `tycontrols.lpk`。
2. 在窗体上拖放 `TTyFormChrome` 组件（非可视，出现在下方组件栏）。
3. 在 Object Inspector 中设置 `TitleHeight`、`BorderZone`、`ShowMinimize`、`ShowMaximize`。
4. 在 `FormCreate` 中赋值 `Chrome.TitleBar.Caption` 并设 `Chrome.Active := True`。

设计时窗体保持原始外观；运行时自动切换为无边框。

### 手动触发最大化

```pascal
// 在代码中直接切换（等同于双击标题栏）
Chrome.ToggleMaximize;
```

### 使用自定义样式控制器

```pascal
Chrome.TitleBar.Controller := MyStyleController;
// TTyCaptionButton 子控件的 Controller 不会自动更新，
// 需逐一设置：
Chrome.TitleBar.MinButton.Controller := MyStyleController;
Chrome.TitleBar.MaxButton.Controller := MyStyleController;
Chrome.TitleBar.CloseButton.Controller := MyStyleController;
```

## 7. 注意事项

1. **Active 建议一次性设置：** `UninstallChrome` 会恢复 `BorderStyle`、鼠标事件处理器和 `OnChangeBounds` 链。但反复切换 `Active` 未经充分测试；推荐在窗体 `OnCreate` / `OnShow` 中置一次 `True` 后不再修改。
2. **仅支持 TForm Owner：** `HostForm` 在 `InstallChrome` 时检查 `Owner is TCustomForm`；若将 `TTyFormChrome` 放置在非 `TForm` 的容器上，`FForm` 将为 nil，所有操作静默无效。
3. **设计时不生效：** `SetActive` 中明确检查 `csDesigning in ComponentState`，设计时赋值 `Active` 直接返回，不调用 `InstallChrome`。
4. **最大化避让任务栏：** `ToggleMaximize` 使用 `Screen.MonitorFromWindow(FForm.Handle).WorkareaRect`（工作区，不含任务栏），而非 `Screen.DesktopRect`，因此最大化窗口会自然避让任务栏。
5. **鼠标事件链：** `InstallChrome` 保存并替换窗体原有的 `OnMouseDown/Move/Up`，`UninstallChrome` 恢复它们；若宿主窗体在 `InstallChrome` 之后又手动设置了这三个事件，`UninstallChrome` 恢复的将是安装前的旧值，动态设置的新处理器会丢失。
6. **最小窗体尺寸：** 边框缩放逻辑硬编码最小宽度 80px、最小高度 60px，不可通过属性配置。
7. **macOS 原生阴影（v1.1 已解决）：** `InstallChrome` 在 `{$IFDEF LCLCOCOA}` 下通过 `NSView(Form.Handle).window.setHasShadow(True)` 恢复 `BorderStyle := bsNone` 后丢失的系统阴影。非 Cocoa 构建不受影响。
8. **跨屏 DPI 重缩放（v1.1 已解决）：** `InstallChrome` 在安装时记录当前显示器 PPI（`FInstalledPPI`），并通过链接宿主窗体的 `OnChangeBounds` 事件监听窗体移动。当 PPI 变化时，`TitleHeight` 和按钮宽度经 `TyRescaleChromeMetric`（MulDiv 半入）按比例重缩放，原有的 `OnChangeBounds` 处理器得到保存并在卸载时恢复。
9. **`Active := False` 恢复行为：** `UninstallChrome` 会恢复原始 `BorderStyle` 和宿主窗体的鼠标事件（包括 `OnChangeBounds`）。但反复切换 `Active` 未经充分测试；建议在窗体生命周期内仅在启动时置一次 `True`。
10. **Windows 原生阴影：** `bsNone` 状态下 Windows DWM 阴影尚待实现（无跨编译验证环境），详见 Known Gaps。
