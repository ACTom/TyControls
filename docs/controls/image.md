# TTyImage

## 1. 概述

TTyImage 是 TyControls 库中的**主题化位图图像控件**，继承自 `TTyGraphicControl`（叶子图形控件，无窗口句柄、不可聚焦）。它显示一个 `TPicture`（任意 LCL 图形——PNG / BMP / JPG，支持 alpha 透明），**或者共享图像列表 `TTyVirtualImageList` 中的某一项**，并通过 `TTyPainter` 自绘，从而与主题化界面无缝融合。功能对标 LCL `TImage`，提供**拉伸 / 等比 / 居中**三种摆放模式。

> 主题：`GetStyleTypeKey` 返回 `'TyImage'`（本控件**自有**的键）。`Transparent = True` 时**不绘制背景**；为 `False`（默认，与 `TImage` 一致）时先用 `DrawFrame` 画出 `TyImage` 表面（填充 + 边框）再叠加图像。

> ### ⚠ 3.0 破坏性变更：`Center` 与 `Transparent` 的默认值
>
> 这两个属性用的是 LCL 的**名字**，从前却是 LCL **相反**的默认值（都为 `True`，`TImage` 都为 `False`）。
> LCL 不会把等于默认值的属性写进 `.lfm`，所以一份从 `TImage` 转过来的窗体里**根本没有** `Center=` 这一行——
> 落到旧版 TTyImage 上，每一张未拉伸的图都会悄悄跑到控件正中，`.lfm` 里没有任何东西能解释它。
>
> 现在两者都默认 `False`。**迁移**：原先依赖默认居中 / 默认透明的窗体，在 `.lfm` 或代码里显式写上
> `Center = True` / `Transparent = True` 即可（写出来的窗体反过来也能移植回 `TImage`）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Image` |
| `GetStyleTypeKey` 返回值 | `'TyImage'`（**自有 typeKey**） |

它从前返回 `'TyPanel'`。这里借用面板键的代价最直观：本控件在默认透明模式下唯一读取的样式属性就是 `opacity`（源码注释承诺"禁用的图片会变淡"），而 `light.tycss` 给 `TyPanel` **没有**定义任何状态规则，所以那句承诺当时并不成立——而唯一的补法 `TyPanel:disabled { opacity }` 会让全应用的容器一起变淡。现在写 `TyImage:disabled { opacity: 0.5 }` 就只作用于图片。`TyImage` 已作为附加选择器并入主题里 `TyPanel` 的规则块，解析值与从前逐字节相同，**开钩子而不动像素**；第三方主题若只覆盖了 `TyPanel`，需要补上 `TyImage`（主题层按 typeKey 全有全无地回落）。

### 子部件 typeKey

**没有。** 控件只解析这一个盒子样式：`Transparent = False` 时它是图片的衬底（填充 + 边框 + 圆角），`Transparent = True` 时只取其中的 `opacity`。

```pascal
uses tyControls.Image;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Picture` | `TPicture` | 空图 | 要显示的图像（控件拥有；其 `OnChange` 触发重绘，`AutoSize=True` 时同时重新适配尺寸）。 |
| `Stretch` | `Boolean` | `False` | `True` 时图像**填满**客户区（不保持宽高比）；与 `Proportional` 同时为 `True` 时不再填满，而是允许等比**放大**（见下表）。 |
| `Proportional` | `Boolean` | `False` | `True` 时**等比缩放**以完整装入客户区（letterbox 留边），保持宽高比。**单独打开时只缩不放**：小于客户区的图保持原始尺寸；要让它等比放大，请**同时**打开 `Stretch`（与 LCL 一致）。 |
| `Center` | `Boolean` | `False` | 图像未填满时是否居中（`False` 则左上角对齐）。**3.0 起默认 `False`**，见上方破坏性变更。 |
| `Transparent` | `Boolean` | `False` | `True` 时不画背景，透出下层；`False`（默认）先画 `TyImage` 表面。赋值同时会写入 `Picture.Graphic.Transparent`，因此带掩码 / 透明色的位图（BMP 等）也会真正透明——换图后自动重新应用。**3.0 起默认 `False`**。 |
| `StretchOutEnabled` | `Boolean` | `True` | **放大**开关（把图"撑出去"填满更大的控件）。为 `False` 时比控件小的图永不放大，`Stretch` / `Proportional` 也拉不动它。 |
| `StretchInEnabled` | `Boolean` | `True` | **缩小**开关（把大图"收进来"装进控件）。为 `False` 时超出的图按 1:1 绘制并裁剪。与上一条组合即可表达"大图缩小、小图不放大"。 |
| `KeepOriginXWhenClipped` | `Boolean` | `False` | `Center` 打开且图**大于**控件时，居中会把原点推成负数，切掉左边。置 `True` 则把该轴钉在 0，保住地图 / 截图 / 扫描件的左上角。图装得下时无效（仍居中）。 |
| `KeepOriginYWhenClipped` | `Boolean` | `False` | 同上，纵轴。 |
| `AntialiasingMode` | `TAntialiasingMode` | `amDontCare` | 缩放质量。`amOff` **保证**硬边（像素画 / 二维码 / 精灵图，任何缩放比例下都不混色）；`amOn` **保证**插值平滑；`amDontCare` 走原有路径，不改变任何既有窗体。 |
| `Images` | `TTyVirtualImageList` | `nil` | 共享图像源。`Picture` 非空时**优先用 `Picture`**（与 `customimage.inc` 一致）。列表被释放时引用自动置 `nil`。 |
| `ImageIndex` | `Integer` | `-1` | 显示 `Images` 的第几项。`-1` = 不显示（LCL 默认是 `0`；这里用 `-1`，因为本库的列表按**名字**索引、设计期 `Names` 可以是空的，而 `-1` 也是全库统一的"无图标"哨兵）。 |
| `ImageWidth` | `Integer` | `0` | 渲染列表项时的像素**边长**；`0` = 用列表自己的 `DefaultSize`。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态（通常降低不透明度，图像一并变淡）。 |
| `AutoSize` | `Boolean` | `False` | `True` 时控件尺寸跟随图像原始尺寸；无 `Picture` 时退回到图像列表的尺寸（`ImageSize` 见下）。 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点。 |

### 只读查询（public，非 published）

| 成员 | 类型 | 说明 |
|------|------|------|
| `HasGraphic` | `Boolean` | 有没有东西可画：有 `Picture`，**或**有 `Images` 且 `ImageIndex` 落在范围内。宿主用它决定要不要显示占位内容，不必自己去 `Picture.Graphic` 上做 nil / `Empty` 判断。 |
| `ImageSize` | `Integer` | 列表项实际渲染的像素边长：`ImageWidth` 非 0 就用它，否则用 `Images.DefaultSize`；没有列表时为 `0`。 |

### 继承的通用成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器。 |

**构造时默认尺寸：** `Width = 90`，`Height = 90`（可在创建后自由调整；`AutoSize=True` 时随图像尺寸变化）。

> **注意：** TTyImage 继承自 `TTyGraphicControl`（`TGraphicControl` 的子类），**没有窗口句柄**，因此不可获得键盘焦点，也就**没有** `:focus` 伪类状态。

---

## 4. 三种摆放模式

摆放几何由纯函数 `TyImageFitRect` 计算（模块级、已单元测试），返回图像在客户区内的目标矩形（客户区坐标）：

```pascal
{ 简写形式：等同于下面那个用 LCL 默认值（缩放两向都开、KeepOrigin 都关）调用。 }
function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean): TRect; overload;

{ 完整形式，逐行对照 LCL 的 TCustomImage.DestRect。 }
function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean;
  AStretchInEnabled, AStretchOutEnabled,
  AKeepOriginX, AKeepOriginY: Boolean): TRect; overload;
```

> **`In` / `Out` 的方向容易记反**，这里以 LCL 源码为准（`customimage.inc` 的门是
> `(StretchOutEnabled or PicOutsidePartial) and (StretchInEnabled or PicInside)`）：
> 图**比控件小**时该式化简为 `StretchOutEnabled`，图**比控件大**时化简为 `StretchInEnabled`。
> 也就是说 **Out = 放大、In = 缩小**——名字是站在**图片**的角度说的，不是控件。

| 模式 | `Stretch` | `Proportional` | 行为 |
|------|-----------|----------------|------|
| **原始尺寸** | `False` | `False` | 按图像原始像素尺寸绘制，**不缩放**；`Center=True` 时居中，否则贴左上角。图像大于客户区时会溢出（被裁剪）。 |
| **拉伸填充** | `True` | `False` | 图像**精确填满**客户区 `Rect(0,0,W,H)`，不保持宽高比（可能变形）。 |
| **等比缩小** | `False` | `True` | 图像大于客户区时**等比缩小**以完整装入（留 letterbox 边）；**小于客户区时保持原始尺寸，不放大**。`Center=True` 时居中。 |
| **等比缩放** | `True` | `True` | 同上，但**允许等比放大**填满客户区的短边。 |

上表四行都还要再过 `StretchInEnabled` / `StretchOutEnabled` 这两道闸：任一方向被关掉，该方向就退回原始尺寸。

举例：源 `100×50` 装入 `200×200`——

- 原始尺寸 + 居中：`Rect(50, 75, 150, 125)`
- 拉伸填充：`Rect(0, 0, 200, 200)`
- 等比缩小 + 居中（仅 `Proportional`）：图比客户区小，**不放大**，保持 `100×50` 居中 → `Rect(50, 75, 150, 125)`
- 等比缩放 + 居中（`Proportional` + `Stretch`）：放大 2 倍成 `200×100`，垂直居中 → `Rect(0, 50, 200, 150)`

`Proportional` 单独打开只缩不放，是为了让"一个 16×16 的图标丢进 200×200 的图片控件"保持 16×16：
从前它会被拉成 200×200，看上去像图标坏了，而不像某个属性在照它字面的意思办事。LCL 划的是同一条线，
放大是靠**同时**打开 `Stretch` 显式选进来的。

---

## 5. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击时（`TGraphicControl` 内置支持）。 |
| `OnPictureChanged` | `TNotifyEvent` | `Picture` 发生任何变化时（赋值、就地编辑、清空）。用来刷新尺寸标签、置脏标志、重建缩略图。`TPicture.OnChange` 被控件自己占用（AutoSize 依赖它），所以这是唯一可用的接口。控件先完成自身反应（重算尺寸 + `Invalidate`）**再**回调。 |
| `OnPaint` | `TNotifyEvent` | 控件画完之后（继承自 `TTyGraphicControl`），用来在图上叠加裁剪框、热点标记、水印。 |

> **基线事件集：** 仅暴露 **Tier A** 基线事件（鼠标 / 通用），**无** Tier B 键盘 / 焦点事件（不可聚焦）。完整清单见 [../events.md](../events.md)。

---

## 6. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

> `:focus` **不支持**（`TTyGraphicControl` 无窗口句柄，不可聚焦）。

### 主题来源

走 `TyImage` 选择器（默认取值与 [panel.md](panel.md) 相同，但名字独立）。默认 `Transparent = True` 时背景完全不绘制，图像浮在下层内容之上；仅当 `Transparent = False` 时才画出 `TyImage` 的填充 + 圆角边框作为图像衬底。无论透明与否，`:disabled` 的 `opacity` 都会作用到最终像素上（图像随之变淡）——**但内置主题并未声明这条状态规则**，要让禁用的图片真的变淡，需要主题自己写：

```css
/* 盒子样式（内置主题中与 TyPanel 同值同块），仅在 Transparent=False 时可见 */
TyImage {
  background: var(--surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 8px;
}
/* 想要"禁用即变淡"就加这一条——只影响图片，不影响任何容器 */
TyImage:disabled { opacity: 0.5; }
```

---

## 7. 代码示例

```pascal
uses
  Graphics, tyControls.Controller, tyControls.Image;

TyDefaultController.LoadTheme('themes/light.tycss');

var Img: TTyImage;
Img := TTyImage.Create(Self);
Img.Parent := Self;
Img.SetBounds(16, 16, 240, 160);
Img.Picture.LoadFromFile('assets/photo.png');

// 等比缩小：大图完整装入控件、保持宽高比、居中留边；小图保持原尺寸
Img.Proportional := True;
Img.Center := True;

// 想让小图也等比放大填满，再加上 Stretch：
// Img.Stretch := True;

// 或：只开 Stretch —— 拉伸填满（可能变形）
// Img.Proportional := False;  Img.Stretch := True;

// 不要衬底：跳过 TyImage 表面，直接浮在下层内容上
Img.Transparent := True;

// 「大图缩小、小图绝不放大」——LCL 的经典配方，从前无法表达
Img.Stretch := True;
Img.StretchOutEnabled := False;   // Out = 放大

// 超大扫描件：保住左上角而不是居中裁掉
Img.Center := True;
Img.KeepOriginXWhenClipped := True;
Img.KeepOriginYWhenClipped := True;

// 像素画 / 二维码：任何缩放比例下都保证硬边
Img.AntialiasingMode := amOff;

// 用共享图标集而不是私有 Picture
Img.Images := AppIcons;      // TTyVirtualImageList
Img.ImageIndex := 3;
Img.ImageWidth := 32;        // 0 = 用列表的 DefaultSize
```

---

## 8. 注意事项

- **透明：** `Transparent = False`（默认，与 `TImage` 一致）时先画 `TyImage` 表面作衬底；置 `True` 让图像直接浮在下层内容上。该属性同时管两件事：**跳过控件表面**（一直如此）与**启用图形自身的掩码 / 透明色**（写进 `Picture.Graphic.Transparent`）。后者从前没接，于是一张带真实掩码的位图无论怎么设都画成不透明的。
- **模式组合：** `Proportional = True` 时 `Stretch` **不再被忽略**——它决定等比缩放是否允许**放大**（只缩 vs 可放）。两者都为 `True` 时不会变形填满，仍保持宽高比。`StretchIn/OutEnabled` 是更细的两道闸，压在这两个开关之上。
- **`Picture` 优先于 `Images`：** 两者都设时画 `Picture`（与 LCL 的 `Paint` 一致）。要显示列表项就别给 `Picture` 赋值。
- **空图安全：** 没有任何可画内容（`HasGraphic = False`）时绘制阶段直接跳过，不解引用、不崩溃，适用于无头 / 单元测试环境。**仅在设计期**会描一圈半透明灰色轮廓，否则一个空图片控件在设计器里就是看不见、点不到、拖不动的；运行期保持完全不可见（发布的程序里出现占位框是缺陷）。
- **AutoSize 跟随原始尺寸：** `AutoSize = True` 时控件尺寸取 `Picture.Width/Height`；无图时退回到 `ImageSize` 的正方形；两者都没有则保持当前尺寸。
- **`Canvas` 不是 `TImage` 的 `Canvas`：** LCL 的 `TCustomImage` 把 `Canvas` **重定向**到图片自己的位图画布，所以 `Image1.Canvas.LineTo(...)` 是画**进图里**并且留得住的。本控件继承的是 `TGraphicControl.Canvas`——**绘制期的临时控件画布**，每次重绘都会被 `Picture` 整个盖掉。名字相同、含义不同，且能编译通过，移植时要留意。（详见 [../../CHANGELOG.md]，此项尚未收敛。）
- **alpha 支持：** 通过 `TBGRABitmap.Create(Picture.Graphic)` 载入并以 `dmDrawWithTransparency` 合成，PNG 等带 alpha 的图像会正确透明叠加。
- **不可聚焦：** 基类是 `TGraphicControl`，没有 HWND，`:focus` 伪类永不生效。
- **多图管理：** 若需按名字 / 索引管理一批图像（喂给工具栏、树视图等），见 [[TTyImageCollection]]。
