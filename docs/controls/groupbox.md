# TTyGroupBox — API 参考

## 1. 概述

`TTyGroupBox` 是 TyControls 库中的主题化分组容器控件，继承自 `TTyCustomControl`。外观为一个带圆角边框的矩形区域，顶部有一段文字标题嵌入边框线中（标题处用背景色遮挡边框线，形成视觉断口）。它是一个**真容器**：子控件放置在内部客户区，LCL 的 `AdjustClientRect` 机制会自动将客户区顶边向下移动 16 逻辑像素（标题栏高度），以免子控件遮盖标题文字。

典型用途：配合 `TTyRadioButton` 实现单选组的视觉分区（由于 `TTyRadioButton` 按 `Parent` 分组，将不同组的单选按钮分别放在两个 `TTyGroupBox` 内即可实现两组独立互斥）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GroupBox` |
| typeKey | `TyGroupBox` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 185 × 105（逻辑像素） |
| 客户区顶边内缩 | 16 逻辑像素（`AdjustClientRect` 实现） |

```pascal
uses tyControls.GroupBox;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 分组框顶部嵌入边框线的标题文字。写入时触发重绘。若为空字符串，则不绘制标题文字和背景遮盖带。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |

### 继承的通用成员

TTyGroupBox 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制与样式解析。

---

## 4. 方法与事件

### AdjustClientRect（protected override）

`AdjustClientRect` 已重写，在继承实现的基础上将 `ARect.Top` 增加 `CapHAtPPI(Font.PixelsPerInch)`（即 16 逻辑像素按当前 DPI 缩放后的物理像素值）。LCL 在布局子控件时自动调用此方法，因此放置在 `TTyGroupBox` 内的子控件不需要手动偏移——它们的 `Top = 0` 等价于标题栏下方 16 逻辑像素处。

`TTyGroupBox` 没有公开的自定义方法或事件。

---

## 5. 状态与主题

### 状态

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 获得键盘焦点（分组框通常不设 `TabStop`） |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

### 渲染细节

绘制顺序：

1. **边框矩形：** 顶边从标题栏高度的一半（`CapH div 2`）开始，以 `TyGroupBox` 样式的背景与边框绘制；
2. **标题文字背景带：** 在顶边中央绘制一段与控件背景同色的矩形，遮住边框线（宽度 = 8px 边距 + 文字宽度 + 8px 边距）；若主题未声明 `background`，使用黑色作为后备填充（不美观，请在主题中声明 `background`）；
3. **标题文字：** 以 `TextColor` 在标题带内居中绘制。

### light.tycss 示例规则

```css
TyGroupBox {
  background: var(--surface);     /* 必须声明，用于遮盖标题处的边框线 */
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  font-size: 10px;
}
```

---

## 6. 代码示例

### 基础分组框

```pascal
uses
  tyControls.Controller, tyControls.GroupBox;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var GB: TTyGroupBox;
GB := TTyGroupBox.Create(Self);
GB.Parent := Self;
GB.SetBounds(16, 16, 200, 120);
GB.Caption := '分组标题';
```

### 配合 RadioButton 实现互斥分组

```pascal
uses
  tyControls.Controller, tyControls.GroupBox, tyControls.CheckBox;

// 第一组（水果）
var GBFruit: TTyGroupBox;
GBFruit := TTyGroupBox.Create(Self);
GBFruit.Parent := Self;
GBFruit.SetBounds(16, 16, 185, 120);
GBFruit.Caption := '水果';

var R1, R2: TTyRadioButton;
R1 := TTyRadioButton.Create(GBFruit);
R1.Parent := GBFruit;
R1.SetBounds(8, 8, 160, 28);   // 相对于分组框内的客户区（已自动下移标题高度）
R1.Caption := '苹果';
R1.Checked := True;

R2 := TTyRadioButton.Create(GBFruit);
R2.Parent := GBFruit;
R2.SetBounds(8, 44, 160, 28);
R2.Caption := '香蕉';

// 第二组（颜色）——与第一组完全独立
var GBColor: TTyGroupBox;
GBColor := TTyGroupBox.Create(Self);
GBColor.Parent := Self;
GBColor.SetBounds(220, 16, 185, 120);
GBColor.Caption := '颜色';

var R3, R4: TTyRadioButton;
R3 := TTyRadioButton.Create(GBColor);
R3.Parent := GBColor;
R3.SetBounds(8, 8, 160, 28);
R3.Caption := '红色';
R3.Checked := True;

R4 := TTyRadioButton.Create(GBColor);
R4.Parent := GBColor;
R4.SetBounds(8, 44, 160, 28);
R4.Caption := '蓝色';
```

完整可运行示例参见 `examples/groupbox/umain.pas`。

---

## 7. 注意事项

1. **主题必须声明 `background`：** 标题处的边框遮盖带使用控件样式的 `background` 填充。若主题未声明 `background`，代码会用纯黑色作为后备，这在浅色主题下视觉效果不佳。务必在主题 CSS 中为 `TyGroupBox` 声明 `background`。
2. **客户区自动下移 16 逻辑像素：** `AdjustClientRect` 已重写，子控件的 `Top = 0` 位置实际显示在标题栏下方。无需手动为子控件添加顶部偏移。
3. **边框从标题中线开始：** 边框矩形的顶边位于 `CapH div 2`（约 8 逻辑像素处），而非控件顶边，以便标题文字的中心线与边框线对齐。
4. **RadioButton 分组由 Parent 决定：** `TTyRadioButton.UncheckSiblings` 只遍历同一 `Parent` 下的兄弟控件。将两组单选按钮分别放在两个 `TTyGroupBox` 内即可实现独立互斥，无需额外的 GroupName 属性。
5. **标题文字宽度用 Canvas 精确测量：** 渲染器使用临时 `TBitmap.Canvas` 测量文字宽度（正确处理 CJK 等可变宽字体），而非简单估算。
