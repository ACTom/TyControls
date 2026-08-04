# TTyPaintPanel

## 1. 概述

`TTyPaintPanel` 是一个**自绘表面（owner-draw surface）容器**，继承自 [`TTyPanel`](panel.md)。它在绘制完主题化的边框/背景并按主题 `padding` 内缩内容区后，触发一个新的 `OnPaintSurface` 事件，把库的绘制器 `TTyPainter` 与内容矩形交给应用，让应用**在同一遍绘制（same paint pass）中**用库绘制器直接画到面板表面上——绘制结果随面板自身的 `EndPaint` 一起合成到画布。

典型用途：需要在一个主题化容器里画自定义图形（图表、迷你可视化、装饰、标注）但又想复用库的绘制能力（圆角填充、描边、文本、字形、`Canvas2D`）而不必自己搭建绘制管线时。未接管 `OnPaintSurface` 时，它与普通 `TTyPanel` **逐字节兼容**（仍可显示可选的 `Caption`）。它本身就是面板，是真正的 LCL 容器（`csAcceptsControls`），可承载子控件。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.PaintPanel` |
| `GetStyleTypeKey` 返回值 | `'TyPanel'`（**复用** `TTyPanel` 的 typeKey，不引入新主题 token） |
| 默认尺寸 | 105 × 105（逻辑像素） |

在 `.tycss` 文件中，该控件与 `TTyPanel` 共用 `TyPanel` 选择器的全部主题规则（背景、边框、圆角、`padding`、文本颜色）。

```pascal
uses tyControls.PaintPanel;
```

---

## 3. 关键成员

### 事件类型

```pascal
TTyPaintSurfaceEvent = procedure(Sender: TObject; APainter: TTyPainter;
  const AContent: TRect) of object;
```

| 参数 | 说明 |
|------|------|
| `APainter` | 当前正在使用的**活动**绘制器。**不要**释放它，**不要**对它调用 `BeginPaint`/`EndPaint`；直接使用其绘制 API（`FillBackground` / `StrokeBorder` / `DrawText` / `DrawGlyph` / `Bitmap.Canvas2D`）即可 |
| `AContent` | 内容矩形（**设备像素**），已按主题 `padding` 内缩，可直接作为绘制目标区 |

### 自有 published 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `OnPaintSurface` | `TTyPaintSurfaceEvent` | 自绘表面回调：在主题边框绘制 + `padding` 内缩之后、绘制器合成到画布之前触发一次。未赋值时面板与普通 `TTyPanel` 行为一致 |
| `Caption` | `string` | 继承自 `TTyPanel`：可选标题文字，在自绘回调**之前**绘制（因此应用可覆盖其上） |
| `Alignment` | `TAlignment` | 继承自 `TTyPanel`：标题的水平对齐 |

### 纯几何单元级函数（供无句柄的 headless 测试直接调用）

```pascal
function TyPaintPanelContentRect(const ARect: TRect; const APadding: TRect;
  APPI: Integer): TRect;
```

返回主题边框绘制后交给 `OnPaintSurface` 的内容矩形——即 `ARect`（设备像素）按 `APadding`（逻辑像素，各边分别经 `MulDiv(..., APPI, 96)` 缩放）内缩的结果。与 `RenderTo` 内部的计算一致，但无需窗口句柄或绘制器。

---

## 4. 代码示例

```pascal
uses
  Types, Graphics,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.PaintPanel;

TyDefaultController.LoadTheme('themes/light.tycss');

var Surface: TTyPaintPanel;
Surface := TTyPaintPanel.Create(Self);
Surface.Parent := Self;
Surface.SetBounds(16, 16, 320, 180);
Surface.OnPaintSurface := @DrawMyChart;

// 在同一遍绘制中用库绘制器画自定义内容
procedure TForm1.DrawMyChart(Sender: TObject; APainter: TTyPainter;
  const AContent: TRect);
var
  Fill: TTyFill;
  BarRect: TRect;
begin
  // 用库绘制器填一根强调色柱条（圆角 4 逻辑像素）
  Fill := Default(TTyFill);
  Fill.Kind := tfkSolid;
  Fill.Color := TyRGB($3B, $82, $F6);
  BarRect := Rect(AContent.Left + 8, AContent.Top + 8,
                  AContent.Left + 48, AContent.Bottom - 8);
  APainter.FillBackground(BarRect, Fill, 4);
  // 也可用 APainter.Bitmap.Canvas2D 画线/形状，或 APainter.DrawText 画文本
end;
```

---

## 5. 注意事项

- **同一遍绘制，不是叠加控件：** `OnPaintSurface` 在面板自身的 `TTyPainter` 绘制过程内触发，绘制内容与面板背景一起合成——不存在额外的子控件或第二次绘制开销。
- **绘制器生命周期由面板管理：** 回调里拿到的 `APainter` 归面板所有，**切勿**释放它或调用它的 `BeginPaint`/`EndPaint`；只使用其绘制方法。回调返回后面板会自行 `EndPaint`。
- **内容区已内缩 padding：** `AContent` 已按主题 `TyPanel { padding }` 内缩（设备像素）。若要画到边框边缘，请自行从 `AContent` 反推或改用主题去掉 padding；库的 `FillBackground` 等方法会把绘制裁剪在你给定的矩形内。
- **未接管即等价 TTyPanel：** 不赋值 `OnPaintSurface` 时逐字节兼容普通 `TTyPanel`（仍绘制 `Caption`），可安全地作为普通容器使用。
- **默认落点尺寸 105 × 105（不再继承 `TTyPanel` 的 185 × 41）：** `TTyPanel` 是一条标题带，而绘图面没有天然的长宽比；185 × 41 这种信箱条里画什么都被裁，用户拖出来第一件事就是改尺寸。105 × 105 与 LCL `TPaintBox` 出于同样理由选的值一致（`include/paintbox.inc:50-54`）。
- **仍是真容器：** 继承 `TTyPanel` 的 `csAcceptsControls`，子控件可将其设为 `Parent`；自绘表面与子控件可并存（自绘在下，windowed 子控件叠加在上）。LCL 的 `TPaintBox` 是 `TGraphicControl`，没有句柄、也**根本不能**接子控件；把本控件改基类去换那份透明性，等于删掉一个它已经在提供的能力，所以基类保持不变。
- **复用 TyPanel 主题：** 不引入新的 `.tycss` token；所有视觉值来自 `TyPanel` 选择器，符合"视觉值必须由主题驱动"的约定。
