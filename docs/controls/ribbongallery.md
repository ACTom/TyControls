# 画廊 (TTyRibbonGallery)

## 1. 概述

`TTyRibbonGallery` 是 Ribbon 的**标志性控件**：一行**内联缩略格**（每格一个标题，若有图标字体则再加一个字形），行右侧有一个**下拉箭头**，点击后弹出一个更高的**网格**列出**全部**条目。样式（如字体样式、边框、段落、颜色主题）、色板等就地可选。

它的实现思路直接对照 [[TTyListBox]]：一个自绘的窗口化表面，命中测试每一格、跟踪悬停格/选中格、把每一格当作一个带状态的**格子瓷砖**来绘制。但它画的东西列表框没有：一个下拉箭头、一片由 `--gallery-cell-width` 定宽的定尺瓷砖、每格标题左侧的图标字体缩略图。所以**内联行的表面已经有自己的 typeKey `TyRibbonGallery`**，不再借 `TyListBox`。

展开网格由共享的 `TTyDropdownPopup` 托管；弹窗内容是一个**内部**轻量控件 `TTyGalleryGrid`（**不注册到组件面板**），它把全部条目画成网格，并把格子点击回传给画廊（设 `ItemIndex`、触发 `OnSelect`、关闭弹窗）。该内部控件由画廊**按需创建、拥有并释放**。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.RibbonGallery` |
| 注册类 | `TTyRibbonGallery`（`TTyGalleryGrid` 是**内部**弹窗内容，不注册） |
| `GetStyleTypeKey` 返回值 | `'TyRibbonGallery'`（自己的键） |

绘制路径实际解析这几个键：

| typeKey | 画什么 |
|---|---|
| `TyRibbonGallery` | 内联行的外框：背景、边框、圆角、焦点环，以及下拉箭头的颜色（取其 `color`） |
| `TyListBox` | **弹窗网格**（内部的 `TTyGalleryGrid`）的表面——**仍然借用**，见下 |
| `TyListItem` | 每一格瓷砖的填充：`:active` = 选中、`:hover` = 悬停、`:normal` = 常态——**仍然借用**，见下 |

> **只拆了内联行的盒子键。** 弹窗网格表面与每一格瓷砖目前**仍解析列表框的键**，也就是说：改 `TyListItem`
> 会同时改到全库的列表行，改 `TyListBox` 会同时改到弹窗网格与全库列表框。这是"尚未拆分"，不是"设计如此"——
> `TyRibbonGalleryItem`(+`:hover`/`:active`) 与 `TyRibbonGalleryPopup` 是**有意推迟**的子部件键，
> 现在**并不存在**，写进皮肤不会被解析。清单见
> `docs/superpowers/plans/2026-07-23-typekey-explicit-borrowers.md`。

尺寸走 metric token,不是样式属性:`--gallery-cell-width`(格宽)、`--gallery-arrow-width`(右侧箭头区宽)、
`--gallery-glyph-pad`(字形四周留白)。

```pascal
uses tyControls.IconFont, tyControls.RibbonGallery;
```

---

## 3. 属性与事件

| 成员 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | 空 | 每一格的标题。`OnChange` → 重算 + 重绘；列表缩短到选中项之下时 `ItemIndex` 自动收敛到 `-1`。 |
| `GlyphNames` | `TStrings` | 空 | 可选，与 `Items` **平行**：每项一个字形名（对应 `IconFont.Glyphs` 映射）。缺省或越界的项不画字形。 |
| `IconFont` | `TTyIconFont` | `nil` | 可选字形来源。用 `FreeNotification`/`Notification` 挂钩：所指字体被释放时自动置 `nil`。 |
| `ItemIndex` | `Integer` | `-1` | 当前选中项（`-1` = 无）。越界值收敛为 `-1`。设置**只在真正改变时**触发一次 `OnSelect`。 |
| `VisibleColumns` | `Integer` | `3` | 内联行在下拉箭头之前显示多少格；也是弹出网格的列数。`< 1` 钳制为 `1`。 |
| `OnSelect` | `TNotifyEvent` | — | 选中项**改变**时触发（内联点击、弹窗网格点击、或代码设 `ItemIndex`）。无变化的重复设置**不触发**。 |
| `DropDown` / `CloseUp` / `IsDroppedDown` | 方法 | — | 打开 / 关闭 / 查询展开网格弹窗（GUI；无句柄或无条目时 `DropDown` 为空操作）。 |

另继承 [[TTyCustomControl]] 的通用成员：`Enabled`、`Font`、`Align`、`Anchors`、`StyleClass`、`Controller`、`TabStop` 及通用事件（`OnClick`、`OnMouseXxx` 等）。

---

## 4. 内联行 vs 下拉网格

- **内联行**：从左到右画最多 `VisibleColumns` 个 `TyListItem` 风格的格子（标题 + 可选字形），选中格用 `:selected` 状态、悬停格用 `:hover` 状态；行**右侧**画一个下拉箭头（`tgChevronDown`）作为展开提示。会溢入箭头区的格子被裁剪。
- **下拉网格**：点击箭头区 → 弹出 `TTyDropdownPopup`，其中的 `TTyGalleryGrid` 用 `VisibleColumns` 列把**全部** `Items` 画成网格（每格与内联格同一 `PaintCell` 逻辑，外观一致）。点击某格 → 回传：设 `ItemIndex`、触发 `OnSelect`、关闭弹窗。

内联格点击与弹窗格点击都汇入同一个选择接缝 `SelectAt`，因此**选中 + 事件在一处触发**。

---

## 5. 纯几何辅助（可无头单测）

三个模块级纯函数做布局数学，全部返回**设备像素**整数，headless 单测里可断言具体数值（控件在调用前把逻辑度量经 `TTyPainter.Scale` 缩放）：

```pascal
function TyGalleryInlineCellRect(AIndex, ACellW, AHeightPx, AArrowW: Integer): TRect;
function TyGalleryGridRect(AIndex, ACols, ACellW, ACellH: Integer): TRect;
function TyGalleryCellAt(AX, AY, ACols, ACellW, ACellH, ACount: Integer): Integer;
```

- `TyGalleryInlineCellRect` — 内联行中第 `AIndex` 格的矩形（格子从 `x=0` 起，`AArrowW` 是右侧为下拉箭头**保留**的宽度，供调用方裁剪；此定位函数本身不裁剪）。负索引按 `0` 处理。
- `TyGalleryGridRect` — `ACols` 列网格里第 `AIndex` 格的矩形，按行优先（先左到右、再上到下）平铺。`ACols < 1` 按单列处理。
- `TyGalleryCellAt` — `(AX,AY)` 点落在 `ACols` 列、共 `ACount` 项的网格里的哪一项索引；落在网格外、间隙或末项之后返回 `-1`。

例（3 列、56×44 格）：索引 `0 → (0,0)-(56,44)`；索引 `3 →` 换行到 `(0,44)-(56,88)`；点击 `(56,0) →` 索引 `1`；点击 `(0,44) →` 索引 `3`；6 项时点击 `(0,88)`（本会是索引 6）→ `-1`。

> **无头安全**：绘制与命中测试在 `0` 条目时也绝不崩溃；GUI 弹窗（`DropDown`）只在真实控件上由鼠标点击触发，因此 headless 测试永远不触及它——只测纯几何 + 选择逻辑（经 `protected SelectAt` 接缝）。字形绘制以窗口句柄为门控（无句柄即跳过），无头下退化为纯标题格。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Types,
  tyControls.IconFont, tyControls.RibbonGallery;

TyDefaultController.LoadTheme('themes/light.tycss');

// 可选的图标字体源（平行 GlyphNames 用）
var Icons: TTyIconFont;
Icons := TTyIconFont.Create(Self);
Icons.FontFile := 'assets/fontawesome.ttf';
Icons.FontFamily := 'Font Awesome 6 Free';
Icons.MapGlyph('square', $F0C8);
Icons.MapGlyph('circle', $F111);

var Gallery: TTyRibbonGallery;
Gallery := TTyRibbonGallery.Create(Self);
Gallery.Parent := Self;
Gallery.SetBounds(24, 24, 220, 44);
Gallery.Items.Add('无');
Gallery.Items.Add('细边');
Gallery.Items.Add('粗边');
Gallery.Items.Add('阴影');
Gallery.Items.Add('发光');
Gallery.GlyphNames.Add('square');   // 可选，与 Items 平行
Gallery.GlyphNames.Add('square');
Gallery.GlyphNames.Add('square');
Gallery.GlyphNames.Add('circle');
Gallery.IconFont := Icons;
Gallery.VisibleColumns := 3;        // 内联显示 3 格,箭头弹出全部
Gallery.ItemIndex := 1;
Gallery.OnSelect := @GalleryStyleSelected;
// 点内联格 → 直接选中;点右侧箭头 → 弹出 3 列网格列出全部 5 项。
```

---

## 7. 注意事项

- **改画廊外观写 `TyRibbonGallery` 规则**，不要去改 `TyListBox`——那会顺手重绘全库的列表框。但**格子瓷砖仍是 `TyListItem`**，改它同样会波及所有列表行；在瓷砖键拆出来之前，只能靠 `StyleClass` 在外框这一层做区分（各部件是按空类名解析的，`StyleClass` 到不了格子）。
- **`GlyphNames` 与 `Items` 平行、可短可缺**：某项无对应字形名（或未映射/无 `IconFont`）时该格只画标题，不报错。
- **`ItemIndex` 语义**：越界收敛为 `-1`；仅在**真正改变**时触发一次 `OnSelect`，重复设同值不触发。列表缩短到选中项之下会自动收敛并触发一次。
- **字形像素需真机 + 真实字体**：`RenderGlyph` 依赖已加载/安装的图标字体；无头/单测环境返回空透明位图（逻辑正确但无可见字形），且绘制以窗口句柄为门控——此时格子仍正常显示标题。
- **内部网格不注册面板**：`TTyGalleryGrid` 仅作弹窗内容，由画廊拥有/释放，带 `csNoDesignVisible`，不出现在组件面板。

---

## 相关

- [[TTyRibbon]] —— 命令带宿主；画廊是放进 Ribbon 分组的标志性命令控件。
- [[TTyListBox]] —— 命中测试 + 逐格绘制范式的来源；弹窗网格表面与格子瓷砖目前仍解析它的 `TyListBox` / `TyListItem`。
- [[TTyIconFont]] —— 可选字形来源，`RenderGlyph` 光栅化每格的缩略字形。
- [[TTyDropdownPopup]] —— 托管展开网格的共享弹窗宿主。
```
