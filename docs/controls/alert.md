# TTyAlert

## 1. 概述

`TTyAlert` 是 TyControls 库中的主题化「内联警告条」控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器）。它是一条**常驻在界面里**的横条：左侧一个语义状态图标，中间一行标题（可选再加一行描述），右侧一个可选的关闭（`x`）字形。

**它补的是哪个缺口：** 本库此前所有的提示都是**模态对话框**（`TTyMessage` 一族）——「在窗体里放一条横幅说连接断了」这个语义**完全不存在**，只能每处手工拼一个染了色的 `TTyPanel` + `TTyLabel`，即硬编码颜色。典型用途：表单顶部的校验汇总、页面里的状态提示（「配置已过期」「同步中断」）、成功回执条、需要用户注意但**不该打断操作**的一切通知。

`AlertType` 决定**语义**：它同时选中样式变体（`TyAlert.warning` 等）和控件要画的**图标**。`Closable := True` 时右侧出现 `x`：点它触发 `OnClose`，未被否决则默认**隐藏**该横条；点横条其余部分是普通的 `OnClick`。两个手势互不串味——点 `x` **不会**触发 `OnClick`（详见第 8 节）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Alert` |
| `GetStyleTypeKey` 返回值 | `'TyAlert'`（横条本体：`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` / `shadow`） |
| 关闭字形 typeKey | `'TyAlertClose'`（`x` 的悬停底片取其 `background`，`x` 的笔色取其 `color`） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`） |
| 默认尺寸 | 320 × 40（逻辑像素，构造时设置） |

```pascal
uses tyControls.Alert;
```

**为什么是图形控件（无句柄）？** 警告条不承载子控件、不取焦点、不吃按键（`x` 是纯鼠标可视对象）；直接画在父控件画布上，圆角**之外**的四角缺口天然显出父表面（图片主题下则是照片），省掉窗口化控件必须做的补角处理。与 `TTyTag` 同一套路。

**为什么 `AlertType` 是 published 枚举？** 本库的铁律是「颜色变体走 `StyleClass`，控件不认识任何变体名」。这里**故意破例**，理由是：类型不只决定颜色，还决定控件**必须自己画出来的图标**——所以控件是真的**必须知道**它。既有先例是 `TTyMessage.DlgType`（一个 published 的 `TMsgDlgType`，同样用来选字形）。**没有**复用 `TMsgDlgType`：它没有 `success`，而那正是警告条的半壁江山。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AlertType` | `TTyAlertType` | `atInfo` | `(atInfo, atSuccess, atWarning, atError)`。**同时**决定样式变体名（`'info'` / `'success'` / `'warning'` / `'error'`）和状态图标。改它会重新贴合自动尺寸的横条（主题可能给不同变体不同 `padding`）。 |
| `Message` | `string` | `''` | 标题行。用解析后的 `TyAlert` 样式绘制（**不**读取 LCL `Font.*`），**左对齐**，放不下时省略号截断，**不换行**。**不解析助记符**：警告条不激活任何东西，`&` 就是字面字符。 |
| `Description` | `string` | `''` | 可选的第二行。**一旦设置**，横条切换到更高的两行形态；清空则退回一行。绘制规则同 `Message`。 |
| `ShowIcon` | `Boolean` | `True` | 在左侧槽位画出该类型的状态图标。默认开：图标是让警告条「一眼可读」的关键，也是 `AlertType` 除颜色之外存在的理由。 |
| `Closable` | `Boolean` | `False` | 显示并启用关闭（`x`）字形。关掉时会一并清掉残留的悬停 / 按下状态。 |
| `OnClose` | `TTyAlertCloseEvent` | `nil` | 见第 4 节。 |
| `AutoSize` | `Boolean` | `False` | 开启后横条**高度**贴合内容（`padding` + 一或两行，且至少容得下槽位）。**宽度不动**——见第 8 节。 |

### 继承的通用成员

`TTyAlert` 继承自 `TTyGraphicControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | **附加变体**，叠在类型自带的变体之上——见下方「`StyleClass` 与 `AlertType` 怎么相处」。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

另暴露 `Enabled` / `Font` / `Align` / `Anchors` / `OnClick` 及 `TTyGraphicControl` 基线事件集，见 [../events.md](../events.md)。

### `StyleClass` 与 `AlertType` 怎么相处

**规则：类型永远先出，`StyleClass` 追加在后。** 解析时传给引擎的 variant 串是 `'<类型名> <用户的 StyleClass>'`，而引擎**按文本顺序**逐个套用 variant 规则（后者按属性覆盖前者）。于是：

- 语义外观**永远在**，不会被悄悄丢掉——`TyAlert.warning` 一定会被套用；
- `StyleClass` 仍然是**活的**，不是摆设——主题写一条只调 `padding` 的 `TyAlert.compact`，就能把**任意类型**的横条压扁而**丝毫不碰它的颜色**；
- 用户若真想改颜色，写 `TyAlert.mine { background: ... }` 也覆盖得掉（后者胜）——这是引擎既有的级联规则，不是本控件的特例。

```pascal
A.AlertType := atSuccess;
A.StyleClass := 'compact';
// A.StyleVariant = 'success compact'  ->  TyAlert.success 先，TyAlert.compact 后
```

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnClose` | 在横条**响应 `x` 点击**之前触发。`procedure(Sender: TObject; var AllowClose: Boolean) of object`。默认 `AllowClose = True` → 控件执行默认动作 **`Visible := False`**（隐藏）；置 `AllowClose := False` 则否决默认动作，由宿主自己决定（`Free` 它、从队列里摘掉、做退场动画等）。 |
| `OnClick` | 点击横条**除 `x` 以外**的区域。点 `x` 的手势**不会**触发它。 |

> **为什么默认动作是「隐藏」而不是「什么都不做」：** 未挂 `OnClose` 时 `x` 仍然是活的可视对象（点了就消失），符合用户对通知条的直觉；真正拥有横条生命周期的宿主用 `AllowClose := False` 接管。与 `TTyTag` 完全同一套语义。

---

## 5. 关键成员

### 纯规则 / 几何函数（单元级，可无句柄直接调用）

```pascal
type
  TTyAlertType = (atInfo, atSuccess, atWarning, atError);

  TTyAlertLayout = record
    IconRect: TRect;          // 状态图标槽位（空 => 无图标）
    MessageRect: TRect;       // 标题行的行带（空 => 不画）
    DescriptionRect: TRect;   // 第二行的行带（空 => 无描述）
    CloseRect: TRect;         // 关闭字形槽位（空 => 无 x）
  end;

function TyAlertVariant(AType: TTyAlertType): string;        // 'info' | 'success' | 'warning' | 'error'
function TyAlertGlyph(AType: TTyAlertType): TTyGlyphKind;    // tgInfo | tgSuccess | tgWarning | tgError

function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer): TTyAlertLayout;

function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize: Integer): Integer;
```

全部整数 / 枚举入参、无控件状态、无句柄依赖，测试直接调用（`tests/test.alert.pas`）。要点：

- **垂直**：文字块（标题，有描述时再加 `ATextGap` + 描述）在 `padding` 带内**垂直居中**；两个槽位（图标与 `x`）都**以标题行为准**居中。**一条规则两种形态**——一行时那就是横条的视觉中心，两行时则把图标和 `x` 放在**标题**旁边，而不是晾在两行中间。
- **水平**，空间不够时的**优先级**：`x` 最先（它是横条唯一的可视对象——沿用 `TyTagLayout` 的规矩），图标次之（它说明「这是哪一类通知」），文字列拿剩下的；剩不下就整列塌缩为空，而不是露出一条几像素的残片。
- 槽位比横条高 → 压进高度内，不越界；`padding` 吃掉整个横条 / 宽高 ≤ 0 → 所有矩形都为空，绝不出现反向矩形。
- `TyAlertPreferredHeight` 是 `TyAlertLayout` 的**逆**：把它的结果当 `AClientHeight` 回喂，文字块正好落在 `padding` 上，两个槽位都不被压扁（已有往返测试守护）。它**不吃宽度**参数——横条的高度不依赖宽度：两行都是**单行不换行**（省略号截断，与本库其余文字一致），所以窄一点只是少显几个字，不会回流成更高的块。
- `ADescriptionHeight` 与 `AMessageHeight` **分开传**，尽管今天的控件把同一个数喂了两遍（两行共用同一份 `TyAlert` 字体）：**规则**是「每行用自己量出来的高度」，把「两者相等」焊死在几何里，等描述将来有了自己的 typeKey 就得再拆一遍。

### 公开成员

```pascal
procedure Close;                // 走 OnClose，未否决则隐藏；可对 disabled 横条调用（只有鼠标路径受 Enabled 门控）
function HasDescription: Boolean; // Description <> ''，即是否处于两行形态
function StyleVariant: string;    // 实际参与解析的 variant 串（'warning' / 'success compact' …）
function TyAlertCloseRect: TRect; // x 槽位（设备像素，(0,0)-local）；非 Closable 时为空。绘制与命中检测同源
function TyAlertIconRect: TRect;  // 图标槽位（同上）；ShowIcon 关闭时为空
```

---

## 6. 状态与主题

### 支持的伪类状态

- **横条**（`TyAlert`）：`:hover` / `:active` / `:disabled` 由基类状态机计算。
- **`x`**（`TyAlertClose`）：状态取的是**字形自己的**——指针精确落在 `x` 上才是 `:hover`，所以 `x` 独立于横条亮起（与 `TTyTag` / TabStrip 的关闭按钮同一套路）。解析时带上**横条完整的 variant 串**，因此 `TyAlertClose.error` 可以给错误横条的 `x` 单独换色。

### 主题令牌摘要

```css
TyAlert {
  background: var(--surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  color: var(--on-surface);
  font-size: var(--font-size-base);
  padding: 8px 12px;                 /* 上下决定行块留白，左右决定内容带 */
}

/* 四个语义变体 —— 变体名由 AlertType 映射而来，是控件与主题之间的硬契约。
   淡底 + 中调边框 + 深语义色文字（Bootstrap 式染色条）：文字与图标同色，见下方注意事项。 */
TyAlert.info    { background: alpha(var(--accent), 0.10);  border-color: alpha(var(--accent), 0.35);  color: var(--accent); }
TyAlert.success { background: alpha(var(--success), 0.10); border-color: alpha(var(--success), 0.35); color: var(--success); }
TyAlert.warning { background: alpha(var(--warning), 0.10); border-color: alpha(var(--warning), 0.35); color: var(--warning); }
TyAlert.error   { background: alpha(var(--danger), 0.10);  border-color: alpha(var(--danger), 0.35);  color: var(--danger); }

TyAlertClose       { color: var(--muted); }
TyAlertClose:hover { background: var(--overlay-hover); color: var(--on-surface);
                     border-radius: var(--radius); }
```

> **变体调色板的落点（本批调色板扩容后）：** `success` / `warning` 直接落在**本批新增的两个 seed** `--success` / `--warning` 上（各自带 `on(var(--...))` 配对）。`error` 用**既有的** `--danger`（没有、也不需要 `--error` seed）。`info` 用 `--accent`——**Ant Design 的 info 就是品牌蓝**，所以**不新增** `--info` seed。控件对这些**颜色**一无所知，它只认那四个**变体名**（因为它得画它们的图标）。

`TyAlertClose` **未定义时优雅降级**：无 `background` → 不画底片；无 `color` → `x` 用横条自己的 `color`。**不会**回退到任何硬编码颜色。
`TyAlert` **本身没有 `background`** 时（主题压根没定义、或定义了却没给底色）→ **整条什么都不画**，而不是画一条硬编码的横幅。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--alert-icon-size` | `16`（= `TyAlertIconSize`） | 状态图标方形槽位边长 |
| `--alert-icon-gap` | `8`（= `TyAlertIconGap`） | 图标槽位与文字列之间的间隙 |
| `--alert-text-gap` | `2`（= `TyAlertTextGap`） | 标题行与描述行之间的垂直间隙 |
| `--alert-close-gap` | `8`（= `TyAlertCloseGap`） | 文字列与 `x` 槽位之间的间隙 |
| `--alert-close-size` | `14`（= `TyAlertCloseSize`，与 `TyTagCloseSize` / `TyTabCloseSize` 一致，三处 `x` 观感统一） | `x` 方形槽位边长 |

五个字形本身还都支持图标字体覆盖（v3/C5）：状态图标是 `--glyph-info` / `--glyph-success` / `--glyph-warning` / `--glyph-error`，`x` 是 `--glyph-close`。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Alert;

TyDefaultController.LoadTheme('themes/light.tycss');

var A: TTyAlert;

// 一行的警告条：贴着表单顶部
A := TTyAlert.Create(Self);
A.Parent := Surface;
A.Align := alTop;
A.AutoSize := True;              // 高度贴合；宽度交给 alTop
A.AlertType := atWarning;
A.Message := '证书将在 7 天后过期。';

// 两行 + 可关闭的错误条
A := TTyAlert.Create(Self);
A.Parent := Surface;
A.Align := alTop;
A.AutoSize := True;
A.AlertType := atError;
A.Message := '同步失败';
A.Description := '无法连接到服务器 sync.example.com（超时 30s）。';
A.Closable := True;
A.OnClose := @HandleAlertClose;  // procedure(Sender: TObject; var AllowClose: Boolean)
```

宿主接管生命周期（不要默认的「隐藏」）：

```pascal
procedure TForm1.HandleAlertClose(Sender: TObject; var AllowClose: Boolean);
begin
  AllowClose := False;                        // 否决默认的 Visible := False
  FNotices.Remove(Sender);
  (Sender as TTyAlert).Free;                  // 自己销毁并重排
end;
```

---

## 8. 注意事项

- **两个手势互不串味：** 点 `x` **只**触发 `OnClose`，绝不触发 `OnClick`（否则一条「点正文看详情」的横条会「既看详情又消失」）。实现依赖 LCL 的既定次序——`TControl.WMLButtonUp` **先 `Click` 后 `MouseUp`**：`Click` 看到「本次按下起始于 `x`」就吞掉；`MouseUp`（知道抬起位置）才决定是否真的关闭。
- **按下 `x` 拖开再抬起 = 取消：** 和任何按钮一致——不关闭，也不产生 `OnClick`（这次按下从来就不属于横条）。
- **`AutoSize` 只管高度：** `CalculatePreferredSize` 返回宽度 `0`，即 LCL 的「无首选宽度，保持现有边界」。横条是用 `Align`/`Anchors` 横跨宿主的，把宽度回缩到文字宽会**和布局打架**。
- **图标与文字同色（两个 typeKey 的代价）：** 本控件只有 `TyAlert` / `TyAlertClose` 两个 typeKey，状态图标取的是**横条自己的 `color`**。所以 `TyAlert.warning { color: var(--warning); }` 会**同时**染上图标和文字——这正是上面 CSS 摘要选择 Bootstrap 式「淡底 + 深语义色文字」而非 AntD 式「彩色图标 + 中性深色文字」的原因。若主题层日后想让图标单独着色，需要新增第三个 typeKey（`TyAlertIcon`）。
- **两行共用一份字体：** 同理，`Message` 与 `Description` 用的是同一条 `TyAlert` 规则解析出的字体，**无法**让标题加粗而描述常规（AntD 是那样做的）。要做需要给描述一个自己的 typeKey。
- **不换行：** 两行都是单行 + 省略号截断，与本库其余文字一致。`Description` 是**第二行**，不是段落。
- **图形控件，非容器：** 无窗口句柄，子控件不能以它为 `Parent`。
- **文字用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
