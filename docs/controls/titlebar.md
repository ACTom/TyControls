# TTyTitleBar — API 参考

## 1. 概述

`TTyTitleBar` 是 TyControls 自绘窗框方案的标题栏控件。它自绘背景并在**阅读起始侧**渲染窗口标题文本，另一侧自动放置三个 `TTyCaptionButton` 系统按钮（最小化、最大化/还原、关闭），按钮随控件宽度动态布局。左到右窗口下这就是「标题在左、按钮在右」；`BiDiMode = bdRightToLeft` 时整条栏镜像（见 §5「右到左」）。

`TTyTitleBar` 现在是 **`TTyForm` 的子组件**——由 `TTyForm` 构造函数代码创建并停靠在顶部（`alTop`，"条带 0"），通过窗体的只读 `TitleBar` 属性访问。它**不再单独出现在 Lazarus 调色板**上（不可单独拖放）。你仍可在代码里独立创建一个 `TTyTitleBar` 用作装饰性标题区域，但常规用法是继承 `TTyForm` 后用 `TitleBar` 访问它。新窗口模型详见 [ttyform.md](ttyform.md)。

### 可定制内容区（Q2）

标题栏现在有一个真正的内容区：它覆写了 `AdjustClientRect`，把客户区收缩为**中间条带**——阅读起始侧留出标题/图标内缩、另一侧留出**所有可见系统按钮之和**的内缩（`RightInset`，随 `ShowMinimize`/`ShowMaximize` 变化）。因此放在标题栏上的**对齐（aligned）子控件**会自动被约束在标题/图标与系统按钮之间的中间区域，便于放置 VS-Code 风格的按钮、下拉、菜单等。

这条内缩与按钮的摆放来自**同一个** `CaptionLayout`。它们曾经是两处各自独立的「按钮在右边」声明（`LayoutButtons` 从 `ClientWidth` 往左排，`RightInset` 又从右边减一遍），镜像时只改一处就会把标题和宿主子控件直接铺到按钮上、另一头留个洞——本库反复出过的「画在一边、答在另一边」。

> **范围说明：** 本周期支持运行期放置的、且**对齐**的标题栏子控件。自由放置（`alNone`）的标题栏子控件在设计期的完整 WYSIWYG 与窗体内容区有相同的 `alNone` 注意事项，**已推迟**（未来可能引入一个对称于内容面板的标题栏内层内容子面板）。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Form` |
| typeKey | `TyTitleBar` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 200 × 32（逻辑像素） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 标题栏显示的文本。赋值时若值变化则触发 `Invalidate`。 |
| `Align` | `TAlign` | `alNone` | 对齐方式（继承自 LCL，现 published）。作为 `TTyForm` 子组件时由窗体设为 `alTop`。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 锚定（继承自 LCL，现 published）。 |
| `ButtonWidth` | `Integer` | `46` | 每个系统按钮的宽度（逻辑像素）。写入时重排按钮并刷新右侧内缩（`RightInset`）。 |

### public 只读属性 / 方法（non-published）

| 成员 | 类型 | 说明 |
|------|------|------|
| `MinButton` | `TTyCaptionButton` | 最小化按钮（`Kind = cbkMin`），由构造函数创建。 |
| `MaxButton` | `TTyCaptionButton` | 最大化/还原按钮（`Kind = cbkMax`，最大化后切换为 `cbkRestore`）。 |
| `CloseButton` | `TTyCaptionButton` | 关闭按钮（`Kind = cbkClose`）。 |
| `CaptionLayout` | `function: TTyCaptionLayout` | 系统按钮簇与内容区当前的几何（`MinBtn`/`MaxBtn`/`CloseBtn`/`Band`/`Content`，均为客户区设备像素）。**这是按钮 x 的唯一权威**：`LayoutButtons`、`AdjustClientRect`、`CaptionSpan` 全部读它。宿主要在标题栏上放东西时，问它按钮在哪一侧，别自己算。 |
| `RightInset` | `function: Integer` | 系统按钮簇占用的总**宽度**（= `CaptionLayout.Band` 的宽度）。宽度没有方向，所以镜像不改变它的值——但镜像后它量的那条带在**左**边，名字会骗人。保留原名是因为改公开成员名属破坏性变更，收益不抵成本（见 `plans/2026-08-04-rtl-mirroring-scope.md` §6.3 第 6 条）。 |

这三个按钮的 `Parent` 设为 `TTyTitleBar` 自身（**代码持有**），由 `LayoutButtons` 在构造和 `Resize` 时自动排布。它们是**窗口化子控件**，所以 `LayoutButtons` 写下的 `SetBounds` 同时就是它们的命中区、悬停区和按下区——LCL 按这份 bounds 路由——这也是按钮几何只需要在一个地方正确的原因。

### 继承的通用成员（来自 TTyCustomControl / TTyGraphicControl）

| 成员 | 说明 |
|------|------|
| `StyleClass` | CSS 变体类名 |
| `Controller` | 关联的样式控制器 |
| `Enabled` | 启用/禁用（影响状态渲染） |
| `Align` / `Anchors` | 布局属性 |

## 4. 事件与方法

### public 方法

#### `function GetStyleTypeKey: string`（override）

返回 `'TyTitleBar'`，用于主题样式查找。

### protected 方法（内部使用）

| 方法 | 说明 |
|------|------|
| `procedure LayoutButtons` | 按 `CaptionLayout` 放置可见的 CloseButton、MaxButton、MinButton，每个宽度为 `ButtonWidth`（默认 46px），高度等于 `ClientHeight` 减上下 margin。隐藏的按钮（`ShowMinimize`/`ShowMaximize`/`ShowClose` = False）不占位——按钮簇是**紧凑排布**不是固定槽位，藏掉中间那个，外面两个会靠拢。关联到 `TTyForm` 后，这三个开关由窗体的 `BorderIcons` + `Resizable` 驱动。 |
| `procedure Resize` | 重写 `TCustomControl.Resize`，在控件尺寸变化时调用 `LayoutButtons`。 |
| `procedure CMBiDiModeChanged` | 运行期改 `BiDiMode` 后重排按钮。LCL 自己那层只 `Invalidate` + `AdjustSize`；按钮是用 `SetBounds` 摆的、不是画出来的，少了这一步按钮簇会停在旧的一侧直到下一次重绘。 |
| `procedure AdjustClientRect(var ARect)` | 覆写：按 `CaptionLayout.Content` 收缩客户区——阅读起始侧留标题内缩、另一侧让出整个按钮簇——返回中间内容条带，使对齐子控件自动约束于此。 |
| `procedure RenderTo(...)` | 绘制背景框架和标题文本。文本区间来自 `CaptionSpan`（即 `CaptionLayout.Content` 再避开宿主子控件），并以 `IsRightToLeft` 调用 `BeginPaint`，因此 `TitleAlignment` 是**阅读序**对齐。 |

### 事件

`TTyTitleBar` 本身没有额外的 published 事件，但其 published 的 `OnMouseDown/OnMouseMove/OnMouseUp/OnDblClick` 事件槽位**对用户开放**。

标题栏的窗口交互（拖动移动窗口、双击最大化）不再占用这些事件槽位——`TTyTitleBar` 改为**方法覆写**（`MouseDown/MouseMove/MouseUp/DblClick` 各方法先调 `inherited`，再委托给 `TTyForm` 拥有的 `TTyChromeEngine`）。因此你可以自由挂接 `TitleBar.OnMouseDown/...`，不会破坏拖动 / 最大化逻辑。

三个系统按钮的 `OnClick` 由 `TTyForm` 接线：最小化 → `WindowState := wsMinimized`；最大化/还原 → 引擎 `ToggleMaximize`；关闭 → `Close`。

## 5. 状态与主题

### 状态

TTyTitleBar 继承 `TTyCustomControl` 的状态机制，但实际使用中通常处于 `tysNormal` 状态（不需要 hover/focus 效果）：

| 状态常量 | 触发条件 |
|----------|----------|
| `tysNormal` | 正常 |
| `tysHover` | 鼠标悬停 |
| `tysActive` | 鼠标左键按下 |
| `tysFocused` | 键盘焦点（罕见） |
| `tysDisabled` | `Enabled = False` |

### light.tycss 内置规则

```css
TyTitleBar {
  background: darken(--surface, 6%);  /* 略深于窗体背景 */
  color: var(--on-surface);           /* #1F2937 */
  border-color: var(--border);        /* #D1D5DB */
  border-width: 1px;
  font-size: 10px;
  font-weight: 700;                   /* 标题加粗 */
}
```

内置主题没有定义 `:hover`、`:active`、`:focus` 或命名变体规则（标题栏通常不需要交互状态样式）。

### 按钮布局

可见的按钮从右到左排列，右边对齐控件右边缘（每个宽度 `ButtonWidth`，默认 46px）：

```
[  标题文本  ...  ] [ Min ] [ Max ] [ Close ]
```

文本区域：`Left + 8px` 到 `Right - RightInset`，其中 `RightInset = VisibleButtonCount × ButtonWidth`（三个全可见时为 138px = 3 × 46；隐藏最小化/最大化按钮会相应缩小内缩）。

### 右到左（`BiDiMode = bdRightToLeft`）

整条标题栏跟着窗口的阅读方向走：

```
[ Close ] [ Max ] [ Min ] [  ...  标题文本  ]
```

按钮簇移到**前导边**（左），并且**内部顺序一起翻**——关闭按钮占住窗口角，然后最大化，然后最小化。按阅读方向读，序列仍然是「最小化 → 最大化 → 关闭」，和左到右时一模一样；这正是 Windows 对 RTL 窗口做的事（`WS_EX_LAYOUTRTL` 整体镜像非客户区）。只平移不翻序会把最小化按钮丢进窗口角、关闭按钮丢到中间，那个顺序在任何平台上都不存在。

实现上这是**一次反射**：`TyCaptionLayoutFor` 先按左到右算完，再用 LCL 的 `BidiFlipRect` 把记录里的每个矩形（三个按钮 + `Band` + `Content`）一起翻过去。侧别、顺序、margin、gap 全都是这一步的推论，所以不可能只翻一半。

`TitleAlignment` 是**阅读序**对齐，不是物理对齐：镜像后 `taLeftJustify` 落在内容区的**右**边缘，`taRightJustify` 落在左边缘，`taCenter` 不动。这与全库的规则一致——作者显式写下的 `Alignment` 是被**覆盖**而非被默认（见 `docs/rtl.md`）。

**不跟着翻的两件事**（都是有意的）：

- **窗口边角码。** `HTBOTTOMLEFT` / `HTBOTTOMRIGHT` 命名的是真实窗口角，一个窗口的左下角在哪个阅读方向下都是左下角。`TyNcHitTest` 因此根本没有方向参数。这与 `TTyStatusBar` 的 size grip 早先做的决定一致。
- **`cbkRestore` 的字形。** 还原图标（两个叠起来的方框，后面那个在右上）目前没有镜像伙伴——`tyControls.Painter.pas` 里没有 `tgRestoreLeft`。它是纯字形，绘制与命中不会因此分叉。

标题栏上**宿主自己放的子控件**不会被镜像（`Align`/`Anchors` 由 LCL 的对齐引擎管，而 LCL 不认 BiDi）。标题文本仍然取这些子控件让出的**最宽空隙**，所以不会被压在它们下面。

## 6. 代码示例

### 配合 TTyForm（推荐方式）

```pascal
// 窗体继承自 TTyForm，标题栏通过只读 TitleBar 属性访问，由窗体负责创建与管理。
type
  TMainForm = class(TTyForm)
  end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  TitleBar.Caption := Application.Title;     // 同步标题
  TitleBar.ButtonWidth := 40;                // 可选：调整系统按钮宽度
  // 隐藏最大化按钮（即时重排按钮与内容区右侧内缩）：
  ShowMaximize := False;
end;
```

### 独立使用（装饰性标题区域）

```pascal
uses tyControls.Form;

var
  TBar: TTyTitleBar;
begin
  TBar := TTyTitleBar.Create(Self);
  TBar.Parent := Self;
  TBar.Align := alTop;
  TBar.Caption := '我的窗口';
  // 独立使用时需自行绑定系统按钮的 OnClick：
  TBar.CloseButton.OnClick := @CloseButtonClick;
end;

procedure TForm1.CloseButtonClick(Sender: TObject);
begin
  Close;
end;
```

## 7. 注意事项

1. **由 TTyForm 管理：** 作为 `TTyForm` 子组件时，`TitleBar` 的 `Parent` 是窗体、`Align = alTop`；不要手动重设其 `Parent`。通过窗体只读 `TitleBar` 属性访问它。
2. **按钮宽度可配：** `ButtonWidth` 现为 published 属性（默认 46）；写入后自动重排按钮并刷新右侧内缩，无需子类化。
3. **Caption 与窗体 Caption 不同步：** `TTyTitleBar.Caption` 与窗体 `Caption` 是独立属性，修改窗体 `Caption` 不会自动更新标题栏，需手动赋值 `TitleBar.Caption := Caption`。
4. **子按钮 StyleClass 自动设置：** 三个 `TTyCaptionButton` 子控件的 `StyleClass` 由其 `Kind` 属性自动设置（`'min'`、`'max'`/`'restore'`、`'close'`），无需手动干预。
5. **设计期皮肤未换肤：** 与全库一致，标题栏自绘**皮肤**在 Lazarus 设计器中以内置默认外观呈现（设计器无运行期主题），布局/几何则是 WYSIWYG 的。详见 [ttyform.md](ttyform.md) 第 6 节。
