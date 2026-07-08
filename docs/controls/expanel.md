# TTyExPanel — API 参考

## 1. 概述

`TTyExPanel` 是 TyControls 库中的**可折叠/展开面板容器**，继承自 `TTyPanel`（后者继承自 `TTyCustomControl`）。它在控件顶部绘制一段**标题栏（header band）**：内含一个展开/折叠的三角形箭头（chevron）和 `Caption` 文字；点击标题栏即切换 `Collapsed` 状态。标题栏下方是**主体区（body）**，用于放置用户的子控件。

- **折叠时**：控件的 `Height` 收缩到只剩标题栏高度；`ExpandedHeight` 记住折叠前的完整高度。
- **展开时**：`Height` 恢复到 `ExpandedHeight`。

折叠/展开使用库内的缓动动画内核（`TTyAnimator` / `TyEase` / `TyLerpI`）：**运行时**由一个 `TTimer` 逐帧驱动高度平滑过渡；**无窗口句柄（headless / 测试环境）或动画时长为 0** 时，高度**直接跳到最终值**（不启动定时器）。

`TTyExPanel` 是一个**真容器**（保留 `csAcceptsControls`）：主体区的子控件由用户放置，LCL 的 `AdjustClientRect` 机制会把客户区顶边下移一个标题栏高度，使子控件落在标题栏下方。**只有标题栏由面板自绘**（不是一个独立的子控件）。

典型用途：属性检查器 / 选项分区 / 侧边栏中可展开收起的分段。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ExPanel` |
| typeKey | `TyPanel`（**复用**基类 `TTyPanel` 的 typeKey，不新增 `.tycss`） |
| 基类 | `TTyPanel`（继承自 `TTyCustomControl` → `TCustomControl`） |
| 默认尺寸 | 200 × 140（逻辑像素） |
| 默认标题栏高度 | 26 逻辑像素（常量 `TyExPanelDefaultHeaderHeight`） |
| 客户区顶边内缩 | 一个标题栏高度（`AdjustClientRect` 实现，随 DPI 缩放） |

```pascal
uses tyControls.ExPanel;
```

因为复用 `TyPanel` typeKey，`TTyExPanel` 直接沿用主题中 `TyPanel` 规则的背景、边框、圆角、字体与文字颜色——标题栏文字与三角形箭头均使用 `TyPanel` 解析出的 `TextColor`，全部主题驱动，无硬编码颜色。

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Collapsed` | `Boolean` | `False` | 是否折叠。写入 `True` 时记住当前 `Height` 到 `ExpandedHeight` 并将高度收缩到标题栏高度（触发 `OnCollapse`）；写入 `False` 时恢复到 `ExpandedHeight`（触发 `OnExpand`）。值未变化时为 no-op（不触发事件）。 |
| `HeaderHeight` | `Integer` | `26` | 标题栏高度（逻辑像素，最小 1）。改变后会重新计算主体区内缩并重绘；若当前处于折叠态（且无动画进行中），控件高度同步跟随。 |
| `AnimationDuration` | `Integer` | `160` | 折叠/展开动画时长（毫秒）。`0` = 瞬间跳变（不启动定时器）。运行时由 `TTimer` 逐帧驱动，headless 环境下始终跳变。 |
| `OnExpand` | `TNotifyEvent` | `nil` | 从折叠切换到展开时触发。 |
| `OnCollapse` | `TNotifyEvent` | `nil` | 从展开切换到折叠时触发。 |
| `Caption` | `string` | `''` | **继承自 `TTyPanel`**。绘制在标题栏内、箭头右侧，垂直居中。 |
| `Align` / `Anchors` / `StyleClass` / `Controller` | — | — | 继承自基类的通用容器成员。 |

### public 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `ExpandedHeight` | `Integer` | 完整（展开）高度。折叠时它是展开将要恢复到的高度；构造时以初始 `Height` 播种，折叠瞬间以当前 `Height` 更新。可读写。 |

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `TyExPanelDefaultHeaderHeight` | `26` | 默认标题栏逻辑高度。 |

---

## 4. 纯几何函数（可独立单元测试）

以下三个单元级函数为纯计算（**设备像素**，无副作用），是折叠面板逻辑的**受测核心**——测试直接调用它们，无需真实窗口。渲染路径与命中测试均复用这些函数，保证「画在哪里」与「点哪里生效」一致。

```pascal
{ 顶部标题栏矩形：整宽、AHeaderHeight 高，超过客户区高度时钳制到客户区高度。 }
function TyExPanelHeaderRect(const AClient: TRect; AHeaderHeight: Integer): TRect;

{ 展开/折叠箭头三角形的三个顶点，位于标题栏左侧的一个小方形区域内。
  AExpanded=True → 向下（主体展开）；False → 向右（主体隐藏）。 }
function TyExPanelChevronPoints(const AHeaderRect: TRect; AExpanded: Boolean): TTyTriangle;

{ 缓动参数 t（0..1）下的插值高度：t=0 → ACollapsedH，t=1 → AExpandedH。
  在 t 上线性（调用方传入已缓动的 t）。 }
function TyExPanelHeightAt(ACollapsedH, AExpandedH: Integer; t: Single): Integer;
```

其中 `TTyTriangle = array[0..2] of TPoint`（在 `tyControls.ExPanel` 中声明）。

---

## 5. 方法与事件

### AdjustClientRect（protected override）

在继承实现基础上将 `ARect.Top` 增加 `ScaledHeaderHeight`（即 `HeaderHeight` 按当前 DPI 缩放后的物理像素）。放在面板内的子控件 `Top = 0` 即等价于标题栏下方，无需手动偏移。

### MouseDown / MouseMove / MouseLeave（protected override）

- `MouseDown`：左键点击且落在标题栏矩形内时切换 `Collapsed`（`Enabled = False` 时忽略）。
- `MouseMove` / `MouseLeave`：跟踪鼠标是否悬停在标题栏上（用于将来的悬停高亮，当前仅置标志并重绘）。

### 事件

- `OnCollapse`：`Collapsed` 由 `False` 变为 `True` 时触发。
- `OnExpand`：`Collapsed` 由 `True` 变为 `False` 时触发。

---

## 6. 折叠动画与 headless 语义（重要）

`SetCollapsed` 决定目标高度后调用内部的 `StartHeightAnimation`：

- **有窗口句柄且 `AnimationDuration > 0`**：从当前 `Height` 起，用 `teEaseOutCubic` 缓动，由 16ms（约 60fps）的 `TTimer` 逐帧把 `Height` 推向目标；每帧 `Height` 变化会触发 LCL 重新布局子控件并重绘。
- **无句柄（headless / 测试）或 `AnimationDuration = 0`**：`Height` **立即设为最终值**（`SetTargetImmediate`，不启动定时器）。

> **契约**：在无句柄环境中切换 `Collapsed`，`Height` 会**同步**变为最终高度（折叠 = `ScaledHeaderHeight`，展开 = `ExpandedHeight`）。测试据此直接断言 `Height`，无需等待定时器。真实逐帧动画属于真机行为。

---

## 7. 状态与主题

因复用 `TyPanel` typeKey，`TTyExPanel` 直接使用主题中的 `TyPanel` 规则：

```css
TyPanel {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  font-size: 10px;
}
```

### 渲染细节

绘制顺序（`RenderTo`）：

1. **整体框架**：`DrawFrame` 以 `TyPanel` 样式绘制整个控件的背景 + 边框（标题栏与主体共用同一主题化表面，标题栏即其顶部一段）；
2. **箭头三角形**：用 `TyPanel` 的 `TextColor` 填充，展开时向下、折叠时向右（顶点由纯函数 `TyExPanelChevronPoints` 计算，与命中测试同源）；
3. **标题文字**：`Caption` 非空时以 `TextColor` 绘制在箭头右侧、标题栏内垂直居中。

---

## 8. 代码示例

### 基础可折叠面板

```pascal
uses
  tyControls.Controller, tyControls.ExPanel, tyControls.CheckBox;

TyDefaultController.LoadTheme('themes/light.tycss');

var Panel: TTyExPanel;
Panel := TTyExPanel.Create(Self);
Panel.Parent := Self;
Panel.SetBounds(16, 16, 240, 160);
Panel.Caption := '高级选项';
Panel.HeaderHeight := 28;
Panel.AnimationDuration := 180;

// 主体区放置子控件——Top=0 已自动位于标题栏下方
var Chk: TTyCheckBox;
Chk := TTyCheckBox.Create(Panel);
Chk.Parent := Panel;
Chk.SetBounds(12, 12, 180, 24);
Chk.Caption := '启用日志';

// 初始折叠
Panel.Collapsed := True;
```

### 监听展开/折叠

```pascal
procedure TForm1.PanelExpand(Sender: TObject);
begin
  StatusBar.Caption := '面板已展开';
end;

procedure TForm1.PanelCollapse(Sender: TObject);
begin
  StatusBar.Caption := '面板已折叠';
end;

// ...
Panel.OnExpand := @PanelExpand;
Panel.OnCollapse := @PanelCollapse;
```

完整可运行示例参见 `examples/containers/`。

---

## 9. 注意事项

1. **复用 `TyPanel` typeKey**：不需要、也不应为 `TTyExPanel` 新增 `.tycss` 规则；调整外观请修改主题中的 `TyPanel` 规则或用 `StyleClass` / `StyleOverride`。
2. **`ExpandedHeight` 在折叠瞬间捕获**：展开恢复的是**折叠时**的高度，而非构造时的尺寸。若在折叠态直接改 `Height` 无意义（下次展开仍恢复 `ExpandedHeight`）；需要改变展开高度请在展开态设 `Height`，或直接写 `ExpandedHeight`。
3. **headless 高度即时到位**：测试 / 无句柄环境中 `Collapsed` 切换后 `Height` 立即是最终值；真机上是逐帧缓动。
4. **只有标题栏自绘**：标题栏是面板绘制出来的一段区域，不是子控件；`AdjustClientRect` 已把主体客户区下移一个标题栏高度，子控件不会遮住标题。
5. **`HeaderHeight` 随 DPI 缩放**：内部一律用 `MulDiv(HeaderHeight, PixelsPerInch, 96)`，绘制、命中测试、客户区内缩三者一致。
