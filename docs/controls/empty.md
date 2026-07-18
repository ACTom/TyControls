# TTyEmpty

## 1. 概述

`TTyEmpty` 是 TyControls 库中的主题化「空状态占位符」控件，继承自 `TTyCustomControl`（**窗口化**，拥有自己的句柄，可作为父容器）。它把三块内容竖着叠起来、**整体居中**在控件里：

- **插画** —— 一个主题化的「敞口纸箱」矢量图（`ShowImage`）；
- **文案** —— 一行居中的说明文字（`Description` / `ShowDescription`）；
- **操作带** —— 可选的底部区域，**承载用户自己的控件**（通常是一个 `TTyButton`，`ShowAction`）。

典型用途：列表 / 树 / 表格里一行数据都没有时的占位；搜索无结果；筛选后为空。填补的缺口很实在——在此之前只能手拼一个 `TTyLabel` 再自己算居中。

**三块的上下留白是故意留的。** 卡片的横带是**铺满**容器的，空状态的栈**不是**：栈居中，上下留白，正是这份空旷让它读起来像「这里是空的」，而不是「这里的工具条坏了」。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Empty` |
| `GetStyleTypeKey` 返回值 | `'TyEmpty'`（表面 **兼** 文案：`background` / `border-*` / `padding` / `opacity` / `shadow` + `color` / `font-*`） |
| 插画 typeKey | `'TyEmptyImage'`（只取其 `color` 作纸箱的笔色） |
| 基类 | `TTyCustomControl`（→ `TCustomControl`） |
| 默认尺寸 | 220 × 140（逻辑像素，构造时设置） |

```pascal
uses tyControls.Empty;
```

**为什么是窗口化控件（有句柄）？** 因为**操作是一个真控件**——宿主要往里放一个 `TTyButton`（「新建第一个」），而子控件只能挂在 `TWinControl` 上，图形控件没有句柄可挂。这与 [TTyCard](card.md) 是同一个判断、同一个理由。

代价是实打实的，也认了：每个占位符一个 HWND；且拿不到 `TTyTag`（图形控件）那种「圆角之外天然透出父表面」的白送效果。但在**这里**这两笔都便宜——空状态是填满列表客户区的**独苗**（不像标签成群出现），而且它的主题背景一般就是透明的，压根没有圆角缺口要漏。

**为什么插画要单独一个 typeKey？** 插画必须能画得比文案**淡得多**（AntD 的默认空状态图几乎就是一根发丝），而一条规则表达不了两种墨色。`TyEmptyImage` **未定义 `color` 时优雅降级**：纸箱直接用文案自己的 `color`，**不会**回退到任何硬编码颜色。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Description` | `string` | `''` | 文案。**`''` = 库自带的已翻译默认文案**（「暂无数据」/「No data」），不是「没有文案」——详见第 5 节。用主题样式绘制（**不**读取 LCL `Font.*`），在文案带内**居中**，放不下时省略号截断。**不解析助记符**：空状态不激活任何东西，`&` 就是字面字符。 |
| `ShowImage` | `Boolean` | `True` | 插画是否绘制**并**在栈里占位。 |
| `ShowDescription` | `Boolean` | `True` | 文案是否绘制**并**在栈里占位。**标志是权威，不是文字**：`Description` 为空时回落到默认文案而**不是**塌掉文案带，所以清空文字不会让栈跳动。真要一行字都不显示，请关这个标志。 |
| `ShowAction` | `Boolean` | `False` | 是否在栈底预留操作带**并**把它作为客户区交给子控件。**关着时压根没有子控件区**——空状态通常没有操作，不问自取地预留只会把文案挤离中心。 |
| `AutoSize` | `Boolean` | `False` | 开启后占位符贴合自己的栈（+ 主题 `padding`）。关着时保持既有边界、把栈居中在里面——这才是常规用法（`alClient` 塞进空列表里）。 |

### 继承的通用成员

`TTyEmpty` 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | 变体入口：对应 `.tycss` 里 `TyEmpty.<classname>`（同时也作用于 `TyEmptyImage.<classname>`）。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

另暴露 `Align` / `Anchors` / `Enabled` / `Font` 及 `TTyCustomControl` 基线事件集，见 [../events.md](../events.md)。

### public 方法

| 方法 | 返回 | 说明 |
|------|------|------|
| `DisplayDescription` | `string` | **实际绘制的文案**：`Description` 非空则用它，否则用库的已翻译默认串。 |
| `ImageRect` | `TRect` | 已绘制的插画方块（**客户区坐标**）；隐藏或被挤掉时为空矩形。 |
| `DescriptionRect` | `TRect` | 已绘制的文案带（客户区坐标）；隐藏或被挤掉时为空矩形。 |
| `ActionRect` | `TRect` | 操作带（客户区坐标）= **子控件区**，控件自己**不画**它。`ShowAction = False` 时高度为 0。见第 8 节的坑。 |

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `TyEmptyImageSize` | `48` | 插画边长**兜底值**（主题未定义 `--empty-image-size` 时用）。 |
| `TyEmptyGap` | `8` | 块间留白兜底值。 |
| `TyEmptyActionHeight` | `32` | 操作带高度兜底值（够放下一个默认 30px 高的 `TTyButton`）。 |

---

## 4. 纯几何函数（单元级，可无句柄直接调用）

```pascal
type
  TTyEmptyLayout = record
    ImageRect: TRect;    // 插画方块（空 => 不画）
    TextRect: TRect;     // 文案带（空 => 不画）
    ActionRect: TRect;   // 操作带（空 => 无子控件区）
  end;

function TyEmptyStackHeight(AImageSize, ATextHeight, AActionHeight, AGap: Integer): Integer;

function TyEmptyLayout(const AClient: TRect; AImageSize, ATextHeight, AActionHeight,
  AGap: Integer): TTyEmptyLayout;
```

全部整数入参、无控件状态、无句柄依赖，测试直接调用（`tests/test.empty.pas`）。要点：

- `TyEmptyStackHeight` = 所有**在场**块（尺寸 > 0）之和 + **相邻两块之间**各一个 `AGap`。首块之上、末块之下、以及**不在场的块**都**不产生**留白——隐藏插画会把它的空气一起带走，否则栈会被前导留白顶得偏离中心。
- `TyEmptyLayout` 把这个栈**居中**在 `AClient` 里（输出与传入**同一坐标空间**，控件传的就是已按 `padding` 内缩的矩形）。
- 插画**水平居中且保持正方**；文案带与操作带**横跨整个宽度**（文字由绘制器在带内居中 + 截断）。

降级规则，按生效顺序：

1. **插画比客户区宽** → 缩到客户区宽度，**仍保持正方**（所以也少占高度，下一条随即看得到）。
2. **栈比客户区高** → **先丢插画**：它是装饰，而文案和操作才是这个占位符存在的全部理由。
3. **还是不够高** → 栈从客户区**顶部**开始（不骑出去），各块被压进剩余空间；实在没地方的块**塌缩为空矩形**。宽 / 高 ≤ 0 或矩形上下反转 → 三个矩形全为空。**绝不出现反向矩形。**
- `TyEmptyStackHeight` 与 `TyEmptyLayout` 互为**契约**：客户区正好 `TyEmptyStackHeight` 高时，首块贴顶、末块贴底、中间恰好是声明的留白（已有往返测试守护）。`AutoSize` 依赖的就是这条。

---

## 5. i18n：默认文案（**运行期控件里的罕见特例**）

**运行期控件几乎不画自己的文字**——它们画的是 app 喂给它们的文字。`rsEmptyDescription`（「暂无数据」）和 `rsBadgeOverflow`（`99+`）是仅有的两个例外，理由很直白：空状态**按定义**就没有 app 文字可显示，而这一行是**说给用户听的一句话**，必须跟着语言走。

所以它是 `source/tyControls.StrConsts.pas` 里的一条 `resourcestring`（库的中央串表），译文在 `languages/tycontrols.strconsts.<lang>.po`。

**为什么是「`Description = ''` 时回落」，而不是在构造函数里塞默认值？**

```pascal
function TTyEmpty.DisplayDescription: string;
begin
  if FDescription <> '' then Result := FDescription else Result := rsEmptyDescription;
end;
```

两个都是真问题：

- 构造函数里 `FDescription := rsEmptyDescription` 会让**英文被烤进用户的 `.lfm`**（非空字符串属性总是被流式化），从此冻死在那儿——之后再切语言也救不回来。
- 而现在这样，`resourcestring` 是在**绘制 / 测量时**才解析的，所以运行期切语言（`SetDefaultLang`）能直接reach到它。

代价：`''` 被占用为「用默认文案」的语义，因此「一行字都不要」得用 `ShowDescription := False` 表达。

---

## 6. 状态与主题

### 支持的伪类状态

`TyEmpty` 的 `:hover` / `:active` / `:disabled` / `:focus` 由基类状态机计算。插画的 `TyEmptyImage` 解析时**带上占位符自己的 `StyleClass` 与状态集**——所以 `TyEmpty:disabled { opacity: … }` 会让整个占位符一起淡下去，`TyEmptyImage.danger` 也能给危险变体的纸箱单独换色。

### 主题令牌摘要

```css
TyEmpty {
  background: alpha(var(--surface), 0);   /* 透明：占位符躺在空列表自己的表面上 */
  color: var(--muted);                    /* 文案是次要信息，不与正文争 */
  font-size: var(--font-size-base);
  padding: 16px;
}
TyEmpty:disabled { opacity: var(--disabled-opacity); }

/* 插画的墨色单独一把：它要比文案淡得多，一条规则表达不了两种墨 */
TyEmptyImage { color: var(--border); }
```

> **双模式主题**里透明填充写 `background: var(--transparent-fill);`（`@mode` 里按模式给出 `alpha(#FFFFFF, 0)` / `alpha(#000000, 0)`），这是既有约定，不是本控件的特殊要求。

> **调色板边界：** 本控件只用现成的 `--surface` / `--muted` / `--border` / `--radius` / `--disabled-opacity`，**不需要**本批新加的 `--success` / `--warning` 语义 seed——空状态是中性的。要做语义变体（比如 `TyEmpty.danger` 的红纸箱）纯写 `.tycss` 即可，控件代码不动。

**「主题没定义 `TyEmpty` 就什么都不画」**：`background` 未设 → `RenderTo` 直接返回，整块区域留白。一个不认识这个 typeKey 的皮肤必须**降级**，而不是崩溃、也不是自己发明一套观感。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--empty-image-size` | `48`（= `TyEmptyImageSize`） | 插画方形边长 |
| `--empty-gap` | `8`（= `TyEmptyGap`） | 插画 / 文案 / 操作带**之间**的竖向留白 |
| `--empty-action-height` | `32`（= `TyEmptyActionHeight`） | 操作带高度 = **子控件区**高度 |

三者随 DPI 缩放。**刻意不做成 published 属性**：占位符的比例本身就是皮肤的一部分（同 `TTyCard` 的 `--card-header-height`）；单个实例要破例用 `StyleOverride`。

**插画还支持图标字体覆盖**（`--glyph-empty`，v3/C5）：主题设了它就渲染那个码位的字形，内置纸箱矢量只是**没设时的兜底**。纸箱**不是**一个 `TTyGlyphKind`——绘制器里的字形是控件铬件与状态标记，空状态插画两者都不是，所以矢量留在本控件里、直接挂覆盖接缝（与 `TTyComboBox` 的下拉箭头用 `--glyph-dropdown` 是同一套路）。它用**单一墨色**绘制（和绘制器里每个字形一样）：双色插画没法从一个主题颜色着色。笔画粗细**按插画尺寸成比例**——固定粗细在 96px 的插画上是发丝、在 24px 上是墨团。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Empty, tyControls.Button;

TyDefaultController.LoadTheme('themes/light.tycss');

var Empty: TTyEmpty; Btn: TTyButton;

// 最简：一图 + 一句已翻译的默认文案，铺满空列表
Empty := TTyEmpty.Create(Self);
Empty.Parent := ListHost;
Empty.Align := alClient;

// 自定义文案
Empty.Description := '没有符合条件的订单';

// 带操作：先开操作带（否则没有子控件区），再把按钮放进去
Empty.ShowAction := True;
Btn := TTyButton.Create(Self);
Btn.Parent := Empty;          // 落进操作带
Btn.Align := alClient;
Btn.Caption := '新建订单';
Btn.OnClick := @HandleCreate;
```

手工摆放（`alNone`）的操作控件必须自己对着 `ActionRect` 定位——见第 8 节：

```pascal
Btn.Align := alNone;
Btn.SetBounds(Empty.ActionRect.Left + (Empty.ActionRect.Right - Empty.ActionRect.Left - 96) div 2,
              Empty.ActionRect.Top, 96, 30);
```

按数据量切换占位符与列表：

```pascal
procedure TForm1.RefreshOrders;
begin
  OrderList.Visible := FOrders.Count > 0;
  EmptyState.Visible := FOrders.Count = 0;
end;
```

---

## 8. 注意事项

- **⚠ 不开 `ShowAction` 就没有子控件区。** `AdjustClientRect` 只把**操作带**交给子控件；`ShowAction = False` 时它塌缩成客户区**底边**上的零高矩形（**不是** `(0,0,0,0)`——零矩形在原点会把误放的子控件停在插画上）。设计器里想往里拖按钮，请先把 `ShowAction` 打开。
- **⚠ 手工摆放的子控件不会自动落进操作带。** LCL 的 `GetClientRect` 返回**原始** `(0,0,W,H)` 矩形，`AdjustClientRect` **只作用于对齐的子控件**（`alClient` / `alTop` / …）与锚定。`Align = alNone` + `SetBounds` 的子控件用的是原始客户区坐标，`Top = 0` 会**压在插画上**。请对着 public 的 `ActionRect` 定位——它直接委托给 `AdjustClientRect`，所以两条路径**在构造上不可能漂移**。
- **操作带是主题定的高度，不是「贴合内容」。** 它就是 `--empty-action-height`（同 `TTyCard` 的横带）。比它高的操作控件会溢出——改 `--empty-action-height`，别指望带自己长高。这一点也传导到 `AutoSize`：占位符的首选高度是**栈**的高度，**不含**子控件的实际高度。
- **切主题后子控件可能暂时没跟上。** 栈的几何是主题驱动的（字号、三个 metric），而主题切换只以一个裸 `Invalidate` 到达控件——它会重画，但不会 `Realign`。子控件会在下一次 `Realign` / 尺寸变化时归位。（这是容器类控件的既有行为，`TTyCard` 同款；改 `ShowImage` / `ShowDescription` / `ShowAction` **会**主动 `Realign`。）
- **`Description = ''` ≠ 没有文案。** 见第 5 节：空串是「用库的已翻译默认文案」。要真的不显示，用 `ShowDescription := False`。
- **文案用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **栈居中，不铺满：** 这是与 `TTyCard` 横带最大的语义差异，别拿卡片的直觉套它。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
