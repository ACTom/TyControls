# TTyRibbonQuickAccess (Ribbon 快速访问栏 / QAT)

## 1. 概述

`TTyRibbonQuickAccess`（快速访问栏，Quick Access Toolbar，简称 **QAT**）是一条**紧凑的水平命令带**，用来托管少量小尺寸命令控件（Batch-C 的按钮家族：[[TTyGlyphButton]] / `TTySpeedButton`）。它继承自 `TTyCustomControl`，是一个 `csAcceptsControls` 容器：在它身后绘制一层紧凑的主题化条带背景，子命令控件在其上**自左向右**排布。

它专为 **Ribbon 的标题栏行**设计——通常摆在应用按钮之右、窗口标题之左，与其下方的 [[TTyRibbon]] 配对（应用图标 → QAT → 标题 → 窗口按钮）。结构上直接模仿 `TTyToolBar`（另见 [toolbar.md](toolbar.md)）：同为托管子控件、绘制主题条带的窗口化容器。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.RibbonQuickAccess` |
| `GetStyleTypeKey` 返回值 | `'TyRibbon'`（**刻意复用** Ribbon 命令带的表面令牌） |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 120 × 26（逻辑像素） |
| 默认 `Align` | `alNone`（标题栏条带由应用定位，不停靠） |

> **复用 TyRibbon 令牌，不新增 .tycss 规则**：QAT 坐落在 Ribbon / 标题命令带上，理应读作同一表面，因此其 `GetStyleTypeKey` 复用现有的 `'TyRibbon'` 令牌（与 `TTyRibbon` 命令带同色），**不引入任何新的 tycss 选择器**。若你的主题只在 `TyToolBar` 上定义了合适的条带样式，也可自行改用该令牌——但请只复用一个**已存在**的令牌。

```pascal
uses tyControls.RibbonQuickAccess, tyControls.GlyphButtons;
```

---

## 3. 子控件如何排布（Align=alLeft）

QAT 让每个子按钮携带 **`Align := alLeft`**，由 LCL 的对齐引擎按子控件顺序把它们**依次贴向左边缘**，形成自左向右的流式排布。这是最简单、最健壮的做法——无需自定义 `AlignControls`，添加顺序即视觉顺序。

- 用 **`AddButton`** 便捷方法添加（见下），会自动设好 `Align=alLeft`；
- 或自行把任意小尺寸 TTy 控件 `Parent := QAT` 并设 `Align := alLeft`。

`Indent` / `Spacing` 属性是**给宿主测量条带宽度用的建议值**（配合下方纯函数 `TyQatContentWidth`），本身并不移动按钮——`alLeft` 子控件始终紧贴客户区边缘。

---

## 4. AddButton 便捷方法

```pascal
function AddButton(const ACaption: string): TTyGlyphButton;
```

创建一个紧凑的 [[TTyGlyphButton]]，把它 `Parent := Self`、设好 `Align := alLeft`、赋上 `Caption` 并返回。每调用一次，`ControlCount` 增长 1；返回的按钮由 QAT 拥有（随 QAT 一同释放）。这样在代码里填充 QAT 就是一行的事：

```pascal
Qat.AddButton('保存').OnClick := @DoSave;
Qat.AddButton('撤销').OnClick := @DoUndo;
Qat.AddButton('重做').OnClick := @DoRedo;
```

---

## 5. 纯几何

```pascal
function TyQatContentWidth(const AItemWidths: array of Integer;
  AIndent, ASpacing: Integer): Integer;
```

计算一组左对齐项打包后的总宽度：**前导 `AIndent` 内缩 + 各项宽度 + 相邻项之间的 `ASpacing`**（第一项前、最后一项后都不加间距）。零个项 → 仅 `AIndent`；负数输入一律取 0。宿主可据此为标题栏中的 QAT 计算所需宽度。已 headless 单测（如 `TyQatContentWidth([22,22,22], 3, 2) = 73`）。

---

## 6. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Indent` | `Integer` | `3` | 首项前的前导内缩（逻辑像素）。供 `TyQatContentWidth` 测量宽度用，改值 `Invalidate`。 |
| `Spacing` | `Integer` | `2` | 相邻项之间的建议间距（逻辑像素）。供 `TyQatContentWidth` 测量宽度用，改值 `Invalidate`。 |
| `Align` | `TAlign` | `alNone` | 停靠方式（继承）。 |
| `Anchors` | `TAnchors` | — | 锚点布局（继承）。 |
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定样式控制器。 |

QAT 还暴露 `TTyCustomControl` 的基线事件集（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件）；命令响应通常挂在**子按钮**的 `OnClick` 上，而非 QAT 自身。

---

## 7. 渲染

`Paint` → `RenderTo(Canvas, ClientRect, PPI)`：先铺 `FillSharpBackdrop`（图片主题下透出照片，纯色主题为 no-op），再经共享的 `DrawFrame` 用解析后的 `'TyRibbon'` 样式绘制主题条带（背景 + 任意边框 / 圆角）。**0 子控件时也安全，不会抛异常**（headless 单测覆盖）。

---

## 8. 用法

```pascal
uses
  tyControls.Controller, tyControls.RibbonQuickAccess, tyControls.GlyphButtons;

var
  Qat: TTyRibbonQuickAccess;
begin
  Qat := TTyRibbonQuickAccess.Create(Self);
  Qat.Parent := TitleBar;          // 放进 Ribbon 的标题栏行
  Qat.SetBounds(48, 3, 120, 20);   // 由应用定位（Align=alNone）

  // 自左向右填充命令按钮（AddButton 已设好 Align=alLeft）
  Qat.AddButton('保存').OnClick := @DoSave;
  Qat.AddButton('撤销').OnClick := @DoUndo;
  Qat.AddButton('重做').OnClick := @DoRedo;
end;
```

---

## 9. 注意事项

- **子控件即命令项，且需 `Align=alLeft`**：`AddButton` 已自动设好；若自行添加子控件，务必设 `Align := alLeft` 才能参与自左向右的流式排布。
- **专为标题栏行设计**：默认 `Align=alNone`，位置由应用给定；它与下方的 [[TTyRibbon]] 命令带配对使用。
- **复用 TyRibbon 令牌**：`GetStyleTypeKey` 返回 `'TyRibbon'`，没有独立的 tycss 选择器；条带外观跟随 Ribbon 命令带的主题。**不新增任何令牌**。
- **命令响应走子按钮**：QAT 自身无 `OnClick` 语义的专有事件；请挂接各 [[TTyGlyphButton]] 的 `OnClick`。
- **`Indent` / `Spacing` 仅供测量**：它们喂给 `TyQatContentWidth` 帮宿主算条带宽度，本身不移动 `alLeft` 子控件。
- **DFM 序列化**：`Indent`（`3`）/ `Spacing`（`2`）声明了默认值，等于默认值时不写入 `.lfm` / `.dfm`。
