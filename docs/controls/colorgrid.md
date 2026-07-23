# TTyColorGrid

## 1. 概述

TTyColorGrid 是一个**颜色色块网格**:把一组颜色平铺成 `Columns` 列的方格,**点击某个方格即可选中该颜色**。颜色保存在内部的定长数组里(不是 `Items` / `Objects`——这是一份固定调色板,不排序、也没有每格文字,数组是最自然的存法)。构造时自动填入经典 16 色 VGA 调色板,可用 `AddColor` 追加。

网格底色、每格 1px 描边、以及选中格的高亮框全部来自主题(typeKey `'TyColorGrid'`,本控件自有的键)。点击选中会触发 `OnChange`;用代码写 `Selected` 只重绘、不触发事件。色块本身的 RGB 是**数据**,按字面值绘制。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ColorGrid` |
| 基类 | `TTyCustomControl`(窗口化自绘控件)|
| typeKey | `'TyColorGrid'`(**自有 typeKey** → 背景 / 边框 / 文字色)|

它从前返回 `'TyPanel'`:色板矩阵、每格描边、选中环都不是面板会画的东西,而借用面板键让主题层根本够不着它——想让色板的网格线变淡,就得改动全应用的面板边框。现在 `TyColorGrid` 已作为附加选择器并入主题里 `TyPanel` 的规则块,解析值与从前逐字节相同,**开钩子而不动像素**;第三方主题若只覆盖了 `TyPanel`,需要补上 `TyColorGrid`(主题层按 typeKey 全有全无地回落)。

### 子部件 typeKey

**没有。** 单个色格不是可寻址的子部件:描边宽度写死为 1px、圆角写死为 0(所以主题目前无法把色块变圆)、选中环宽度是 `max(2, Scale(2))`,颜色都从盒子样式派生。子部件键 `TyColorGridCell`(连同它的 `:selected` 状态)的扩展已被**刻意推迟**,该键当前**并不存在**,写进 `.tycss` 解析不到任何东西。

```pascal
uses tyControls.ColorGrid;
```

---

## 3. 属性 / 方法 / 事件

| 成员 | 说明 |
|------|------|
| `Columns: Integer` | 列数,默认 `8`,写入时下限夹到 `1`。 |
| `Selected: TColor` | 当前选中的颜色。**读**返回选中色;**写**仅存值 + 重绘(不触发 `OnChange`)。 |
| `AddColor(AColor: TColor)` | 追加一个颜色格并重绘。 |
| `ColorCount: Integer` | 当前颜色格数量。 |
| `CellAt(AX, AY): Integer` | 设备坐标点 `(AX, AY)` 处的格子索引;点在任何格子之外(空网格、或最后一行右侧空位)返回 `-1`。 |
| `OnChange: TNotifyEvent` | **点击某格选中**时触发(代码写 `Selected` 不触发)。 |

另继承 `TTyCustomControl` 的 `Align` / `Anchors` / `StyleClass` / `Controller` / `Font` 等。

---

## 4. 交互

- **左键点击某个色块** → 选中该格颜色,画出高亮框,并触发 `OnChange`。
- 空网格、或点在最后一行未填满的空位上 → 不选中(`CellAt` 返回 `-1`)。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.ColorGrid;

var CG: TTyColorGrid;
CG := TTyColorGrid.Create(Self);
CG.Parent := Self;
CG.SetBounds(20, 20, 200, 120);
CG.Columns := 8;               // 8 列
CG.AddColor(clSkyBlue);        // 追加一格
CG.Selected := clRed;          // 代码选中(不触发 OnChange)
CG.OnChange := @ColorPicked;   // 用户点击选中时回调
```

---

## 6. 注意事项

- **主题驱动的描边:** 格子描边 / 高亮框取 `CurrentStyle.BorderColor`(即 `TyColorGrid` 的 `border-color`);当主题把边框设成透明时回退到 `TextColor`,保证浅色块和高亮框始终可见(仍是主题 token,不是硬编码颜色)。调网格线请写 `TyColorGrid` 规则,别去动 `TyPanel`。
- **色块 RGB 是数据:** 每格的实际颜色是调色板数据,按字面值绘制(不走主题),这与 [colorbox.md](colorbox.md) 的色块一致。
- **交互是真机验证项:** 纯数据 / 状态逻辑(`ColorCount` / `Columns` 夹取 / `Selected` 读写)已 headless 单测;鼠标点击选中(`CellAt` + `OnChange`)需真机验证。
