# 图标命令按钮 (TTyGlyphButton / TTyGlyphContainerButton / TTySpeedButton)

## 1. 概述

这三个控件把 [[TTyIconFont]] 的**图标字体字形**和按钮标题配对，全部继承自 [[TTyButton]]，共享同一套框架、悬停背景淡入、状态、焦点环与数字角标——**不新增任何 `.tycss` 规则**：

| 控件 | 布局 | 典型用途 | 默认尺寸 |
|------|------|----------|----------|
| `TTyGlyphButton` | 图标在**左**、标题在右 | 紧凑的命令按钮（图标 + 文字并排） | ~96 × 30 |
| `TTyGlyphContainerButton` | 大图标在**上**、标题在下 | Ribbon 风格的大按钮 | ~72 × 64（默认字形更大） |
| `TTySpeedButton` | 图标在左（扁平/工具栏） | 可分组的工具栏切换按钮 | ~32 × 32 |

它们共用一个基类 **`TTyGlyphButtonBase`**（本身不注册到组件面板），基类只做三件事：加上图标字体接线、按 `GlyphLayout` 放置字形、然后把标题交给继承的 `DrawContent` 画在剩余矩形里。字形的光栅化完全委托给 `TTyIconFont.RenderGlyph`（与 [[TTyCharImage]] 完全一致，返回调用方拥有的透明 BGRA 位图，用完释放）。

> **复用 TyButton 主题**：`GetStyleTypeKey` 保持返回 `'TyButton'`（继承而来）。因此框架、`:hover`/`:active`/`:focus`/`:disabled`/`:selected` 状态、悬停背景渐变和角标都**免费**获得；字形默认与标题同色（取解析后的 `TextColor`）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GlyphButtons` |
| `GetStyleTypeKey` 返回值 | `'TyButton'`（**三者均复用**，见 [button.md](button.md)） |

```pascal
uses tyControls.IconFont, tyControls.GlyphButtons;
```

---

## 3. 属性表

### 3.1 共有（`TTyGlyphButtonBase` 新增，三者都有）

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `IconFont` | `TTyIconFont` | `nil` | 字形来源。用 `FreeNotification`/`Notification` 挂钩：所指字体被释放时自动置 `nil`，不留悬垂引用。 |
| `GlyphName` | `string` | `''` | 要绘制的字形名（对应 IconFont 的 `Glyphs` 映射，如 `save`）。为空或未映射 → 不画字形，标题占满内容区（退化为普通按钮）。 |
| `GlyphSize` | `Integer` | `0` | 字形边长（**逻辑像素**，随 PPI 经 `TTyPainter.Scale` 缩放）。`0` = 自动：glyph-top 取内容区短边，glyph-left 取内容区高度。 |
| `GlyphColor` | `TTyColor` | `TyGlyphButtonColorDefault` | 字形填充色。默认哨兵值 `TyGlyphButtonColorDefault`（即全透明 `$00000000`，表示“**用主题**”）→ 取 `TextColor`，与标题同色；设为其他值则覆盖。 |

### 3.2 `TTySpeedButton` 额外新增

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `GroupIndex` | `Integer` | `0` | `0` = 普通按钮（`Click` 仅触发 `OnClick`）。`>0` 时点击表现为**单选**：按下自己（`Down := True`）并抬起**同 Parent、同 GroupIndex** 的其它 `TTySpeedButton`。 |
| `AllowAllUp` | `Boolean` | `False` | `True` 时，点击**已按下**的按钮会把它切回抬起（整组可全部抬起）；`False`（默认）时已按下的按钮再点保持按下（严格单选）。 |

### 3.3 继承自 [[TTyButton]] 的常用成员

`Caption`、`Down`（`:selected` 常驻选中态）、`Default`、`Cancel`、`ModalResult`、`ShowBadge`/`BadgeValue`/`BadgePosition`/`OnBadgeDisplay`（数字角标）、`AnimationsEnabled`（悬停背景渐变）、`Enabled`、`Font`、`Align`、`Anchors`、`StyleClass`、`Controller`、`OnClick` 等——细节见 [button.md](button.md)。

---

## 4. 绘制机制（DrawContent + 字形）

三者都**只重写** `DrawContent`（`TTySpeedButton` 另重写 `Click`，各自重写 `Create` 设默认值），不触碰框架/状态/角标绘制路径：

1. 基类 `RenderTo`（继承自 TTyButton）先画框架、算内边距，再把已内缩的内容矩形交给 `DrawContent`。
2. `TTyGlyphButtonBase.DrawContent`：
   - 若 `IconFont = nil`、`GlyphName` 为空或内容区退化 → 直接 `inherited DrawContent`（居中标题，即普通按钮）。
   - 否则算出字形像素大小（显式 `GlyphSize` 优先，否则按布局自动适配），用纯函数 **`TyGlyphButtonSplit`** 把内容矩形切成 **字形矩形 + 标题矩形**（中间隔 `TyGlyphButtonGap` 逻辑像素）。
   - `IconFont.RenderGlyph(GlyphName, px, color)` 光栅化字形，居中合成进字形矩形，释放位图。
   - 最后 `inherited DrawContent(APainter, 标题矩形, AStyle)` 在剩余矩形里画标题（空标题时跳过）。

### 纯函数 `TyGlyphButtonSplit`（可无头单测）

```pascal
procedure TyGlyphButtonSplit(const AContentRect: TRect; AGlyphPx, AGapPx: Integer;
  ALayout: TTyGlyphLayout; out AGlyphRect, ACaptionRect: TRect);
```

- `glLeft`：字形是靠左、垂直居中的 `AGlyphPx` 见方正方形；标题取其右侧（跨过 `AGapPx`）到内容区右边。
- `glTop`：字形是靠上、水平居中的正方形；标题取其下方（跨过 `AGapPx`）到内容区底边。
- `AGlyphPx <= 0`（无字形）→ 字形矩形为空，标题保留整个内容矩形。
- 字形被**钳制**在内容盒内，超大字形绝不会把标题挤成负宽/负高矩形。

例（内容区 100×40、字形 20px、间隔 6px、glyph-left）：字形 `(0,10)-(20,30)`，标题 `(26,0)-(100,40)`。

---

## 5. 状态与主题

伪类状态与 [[TTyButton]] 完全一致：`:hover` / `:focus` / `:active` / `:disabled` / `:selected`（由 `Down` 驱动，`TTySpeedButton` 分组用它做单选高亮）。

由于复用 `TyButton` 选择器，**默认外观就是一个普通按钮**。要让 `TTySpeedButton` 呈现扁平/工具栏观感，给它一个自定义 `StyleClass`（如 `'ghost'`，见 button.md 的 ghost 变体），无需新增 typeKey：

```css
/* 复用内置的 ghost 变体即可得到扁平、仅 hover/选中显底的工具栏按钮 */
TyButton.ghost           { background: alpha(--surface, 0); border-color: alpha(--border, 0); }
TyButton.ghost:hover     { background: var(--surface-hover); }
TyButton.ghost:selected  { background: var(--surface-active); }
```

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Types,
  tyControls.IconFont, tyControls.GlyphButtons;

TyDefaultController.LoadTheme('themes/light.tycss');

// 1) 一个共享的图标字体源
var Icons: TTyIconFont;
Icons := TTyIconFont.Create(Self);
Icons.FontFile := 'assets/fontawesome.ttf';   // Windows 进程私有加载
Icons.FontFamily := 'Font Awesome 6 Free';
Icons.MapGlyph('save', $F0C7);
Icons.MapGlyph('open', $F07C);

// 2) 紧凑命令按钮:图标 + 文字并排
var Cmd: TTyGlyphButton;
Cmd := TTyGlyphButton.Create(Self);
Cmd.Parent := Self;
Cmd.SetBounds(24, 24, 96, 30);
Cmd.IconFont := Icons;
Cmd.GlyphName := 'save';
Cmd.Caption := '保存';
// Cmd.GlyphColor := TyRGB(40, 120, 220);   // 可选:覆盖字形色(默认与标题同色)

// 3) Ribbon 风格大按钮:大图标在上,文字在下
var Ribbon: TTyGlyphContainerButton;
Ribbon := TTyGlyphContainerButton.Create(Self);
Ribbon.Parent := Self;
Ribbon.SetBounds(140, 24, 72, 64);
Ribbon.IconFont := Icons;
Ribbon.GlyphName := 'open';
Ribbon.Caption := '打开';
Ribbon.GlyphSize := 28;   // 更大的字形(默认 24)

// 4) 工具栏分组切换(单选,像 TSpeedButton)
var i: Integer; Names: array[0..2] of string = ('save', 'open', 'save');
for i := 0 to 2 do
begin
  var Sp: TTySpeedButton;
  Sp := TTySpeedButton.Create(Self);
  Sp.Parent := Self;
  Sp.SetBounds(24 + i * 36, 108, 32, 32);
  Sp.IconFont := Icons;
  Sp.GlyphName := Names[i];
  Sp.StyleClass := 'ghost';   // 扁平观感
  Sp.GroupIndex := 1;         // 同组单选
end;
// 点击其中一个 -> 它 Down、同组其它抬起。设 AllowAllUp := True 可再点抬起。
```

---

## 7. 注意事项

- **字形像素需要真实的图标字体（真机）：** 渲染出的字形依赖已加载/安装的图标字体。请通过 [[TTyIconFont]] 的 `FontFile`（Windows 进程私有加载）或在系统安装对应字体族，并把 `FontFamily` 设为该族名。**无头/单元测试环境下没有字体，`RenderGlyph` 返回空透明位图——逻辑正确但画不出可见字形**，属预期；此时按钮仍正常显示标题与框架。
- **无字形即普通按钮：** `IconFont = nil` 或 `GlyphName` 未映射时，`DrawContent` 干净退化为居中标题的普通 [[TTyButton]]，绝不崩溃。
- **`GlyphColor` 哨兵：** 默认 `TyGlyphButtonColorDefault`（全透明 `$00000000`）表示“用主题 `TextColor`”，与标题同色；设为任意其它 `TTyColor`（`$AARRGGBB`）即覆盖。
- **尺寸随 PPI 缩放：** `GlyphSize` 与字形-标题间隔 `TyGlyphButtonGap` 都是逻辑像素，渲染时经 `TTyPainter.Scale` 按目标 DPI 缩放。
- **`TTySpeedButton` 分组：** 单选/互斥完全在 `Click` 里实现（同 Parent 扫描同 `GroupIndex` 的兄弟），因此**直接调用 `Click` 或用户点击**都会触发分组逻辑；`Enabled = False` 时 `Click` 为空操作（不按下、不影响兄弟）。选中高亮复用 `Down` 的 `:selected` 状态。
- **基类不注册面板：** `TTyGlyphButtonBase` 仅作共享父类，不出现在组件面板;面板上注册的是三个具体类。

---

## 相关

- [[TTyButton]] —— 基类，提供框架、状态、悬停渐变、角标、Default/Cancel/ModalResult。
- [[TTyIconFont]] —— 图标字体源，`RenderGlyph` 光栅化字形。
- [[TTyCharImage]] —— 只显示单个字形的叶子图形控件（同样的字形合成机制）。
