# TTyAlert

## 1. 概述

`TTyAlert` 是 TyControls 库中的主题化「内联警告条」控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器）。它是一条**常驻在界面里**的横条：左侧一个语义状态图标，中间一行标题（可选再加一行描述），右侧可以放一排操作按钮（`Actions`），最右边是一个可选的关闭（`x`）字形。

**它补的是哪个缺口：** 本库此前所有的提示都是**模态对话框**（`TTyMessage` 一族）——「在窗体里放一条横幅说连接断了」这个语义**完全不存在**，只能每处手工拼一个染了色的 `TTyPanel` + `TTyLabel`，即硬编码颜色。典型用途：表单顶部的校验汇总、页面里的状态提示（「配置已过期」「同步中断」）、成功回执条、需要用户注意但**不该打断操作**的一切通知。

`AlertType` 决定**语义**：它同时选中样式变体（`TyAlert.warning` 等）和控件要画的**图标**。`Closable := True` 时右侧出现 `x`：点它触发 `OnClose`，未被否决则默认**隐藏**该横条；点横条其余部分是普通的 `OnClick`。两个手势互不串味——点 `x` **不会**触发 `OnClick`（详见第 8 节）。

横条上要放「重新载入」「保留我的」这类操作，就往 `Actions` 里加项：每一项是一个文字按钮，排在标题右边、`x` 左边，宽度跟着自己的文字走，剩下的宽度留给标题和描述。点其中一个触发 `OnAction`。隐藏某一项，它占的宽度就还给标题。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Alert` |
| `GetStyleTypeKey` 返回值 | `'TyAlert'`（横条本体：`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` / `shadow`） |
| 关闭字形 typeKey | `'TyAlertClose'`（`x` 的悬停底片取其 `background`，`x` 的笔色取其 `color`） |
| 操作按钮 typeKey | `'TyAlertAction'`（每个操作按自己的状态解析：`background` / `border-*` / `color` / `font-*` / `padding`） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`） |
| 默认尺寸 | 320 × 40（逻辑像素，构造时设置） |

```pascal
uses tyControls.Alert;
```

**为什么是图形控件（无句柄）？** 警告条不承载子控件、不取焦点、不吃按键（`x` 是纯鼠标可视对象）；直接画在父控件画布上，圆角**之外**的四角缺口天然显出父表面（图片主题下则是照片），省掉窗口化控件必须做的补角处理。与 `TTyTag` 同一套路。

**为什么操作是 `Actions` 集合，而不是让你往横条上放按钮？** 同一个原因：横条是图形控件，按钮当不了它的子控件，只能是叠在它上面的兄弟控件。那样的按钮圆角外侧和透明底取的是**页面**的背景，而不是横条的染色底，看上去像贴上去的；宿主还得自己量每个按钮的宽度、自己给标题让位。让横条自己画，这些就都由它排。

**为什么 `AlertType` 是 published 枚举？** 本库的铁律是「颜色变体走 `StyleClass`，控件不认识任何变体名」。这里**故意破例**，理由是：类型不只决定颜色，还决定控件**必须自己画出来的图标**——所以控件是真的**必须知道**它。既有先例是 `TTyMessage.DlgType`（一个 published 的 `TMsgDlgType`，同样用来选字形）。**没有**复用 `TMsgDlgType`：它没有 `success`，而那正是警告条的半壁江山。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AlertType` | `TTyAlertType` | `atInfo` | `(atInfo, atSuccess, atWarning, atError)`。**同时**决定样式变体名（`'info'` / `'success'` / `'warning'` / `'error'`）和状态图标。改它会重新贴合自动尺寸的横条（主题可能给不同变体不同 `padding`）。 |
| `Message` | `string` | `''` | 标题行。用解析后的 `TyAlert` 样式绘制（**不**读取 LCL `Font.*`），**左对齐**，放不下时省略号截断，**不换行**。**不解析助记符**：警告条不激活任何东西，`&` 就是字面字符。 |
| `Description` | `TCaption` | `''` | 可选的第二行。**一旦设置**，横条切换到更高的两行形态；清空则退回一行。绘制规则同 `Message`。 |
| `ShowIcon` | `Boolean` | `True` | 在左侧槽位画出该类型的状态图标。默认开：图标是让警告条「一眼可读」的关键，也是 `AlertType` 除颜色之外存在的理由。 |
| `Closable` | `Boolean` | `False` | 显示并启用关闭（`x`）字形。关掉时会一并清掉残留的悬停 / 按下状态。 |
| `Actions` | `TTyAlertActions` | 空 | 横条上的操作，一项一个文字按钮，按集合里的顺序从左到右排在 `x` 之前。设计期在对象查看器里点开就能增删，和状态栏的 `Panels` 一样。每一项的属性见下表。 |
| `OnClose` | `TTyAlertCloseEvent` | `nil` | 见第 4 节。 |
| `OnAction` | `TTyAlertActionEvent` | `nil` | 点了某个操作。见第 4 节。 |
| `AutoSize` | `Boolean` | `False` | 开启后横条**高度**贴合内容（`padding` + 一或两行，且至少容得下槽位）。操作按钮比文字行高出很多时，高度也会跟着长到放得下它。**宽度不动**——见第 8 节。 |

### `Actions` 里的每一项（`TTyAlertAction`）

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `TCaption` | `''` | 按钮上的文字。单行，横条太窄时用省略号截断。和横条的文字一样**不解析助记符**，`&` 就是字面字符。 |
| `Visible` | `Boolean` | `True` | 隐藏的操作不占位置：其余操作靠拢，标题拿回它的宽度。 |
| `Enabled` | `Boolean` | `True` | 禁用的操作位置不变，按 `:disabled` 的样子画，点了没有反应（也不会算成点了横条）。 |
| `Hint` | `TTranslateString` | `''` | 指针停在这个操作上时显示它，代替横条自己的 `Hint`。提示显不显示由横条的 `ShowHint` 决定。 |
| `Tag` | `PtrInt` | `0` | 留给应用用，通常用来在 `OnAction` 里区分是哪个操作。 |

### 继承的通用成员

`TTyAlert` 继承自 `TTyGraphicControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | **附加变体**，叠在类型自带的变体之上——见下方「`StyleClass` 与 `AlertType` 怎么相处」。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyCustomStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

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
| `OnAction` | 点了某个操作：左键在**同一个**启用的操作上按下并松开。`procedure(Sender: TObject; AAction: TTyAlertAction) of object`，`AAction` 就是被点的那一项。它不是 `OnClick`，也不会关掉横条；要让横条消失，在处理过程里把它隐藏或者调 `Close`。 |
| `OnClick` | 点击横条**除 `x` 和操作以外**的区域。点 `x` 或点操作的手势**不会**触发它。 |

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
    ActionRects: array of TRect;  // 每个可见操作一个矩形，顺序同传入的宽度；放不下的为空
  end;

function TyAlertVariant(AType: TTyAlertType): string;        // 'info' | 'success' | 'warning' | 'error'
function TyAlertGlyph(AType: TTyAlertType): TTyGlyphKind;    // tgInfo | tgSuccess | tgWarning | tgError

function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer): TTyAlertLayout;
// 带操作的版本：多三个参数——每个可见操作的宽度（文字 + 自己的 padding）、操作的高度、
// 每个操作前面的间隙。上面那个版本就是「没有操作」。
function TyAlertLayout(AClientWidth, AClientHeight: Integer;
  AShowIcon, AHasDescription, AClosable: Boolean;
  APadLeft, APadTop, APadRight, APadBottom: Integer;
  AMessageHeight, ADescriptionHeight: Integer;
  AIconSize, AIconGap, ATextGap, ACloseGap, ACloseSize: Integer;
  const AActionWidths: array of Integer;
  AActionHeight, AActionGap: Integer): TTyAlertLayout;

function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize: Integer): Integer;
// 带操作的版本：最后多一个操作的高度，0 表示没有可见的操作。
function TyAlertPreferredHeight(AShowIcon, AHasDescription, AClosable: Boolean;
  APadTop, APadBottom, AMessageHeight, ADescriptionHeight, ATextGap,
  AIconSize, ACloseSize, AActionHeight: Integer): Integer;
```

全部整数 / 枚举入参、无控件状态、无句柄依赖，测试直接调用（`tests/test.alert.pas`）。要点：

- **垂直**：文字块（标题，有描述时再加 `ATextGap` + 描述）在 `padding` 带内**垂直居中**；两个槽位（图标与 `x`）和那一排操作都**以标题行为准**居中。**一条规则两种形态**——一行时那就是横条的视觉中心，两行时则把图标、操作和 `x` 放在**标题**旁边，而不是晾在两行中间。
- **水平**：操作排在内容带的尾端，有 `x` 时停在 `x` 前面一个 `ACloseGap` 处；文字列停在这一排前面一个 `AActionGap` 处。空间不够时的**优先级**：`x` 最先（它负责关掉横条——沿用 `TyTagLayout` 的规矩），操作次之（横条就是为了给出它们），图标再次（它说明「这是哪一类通知」），文字列拿剩下的；剩不下就整列塌缩为空，而不是露出一条几像素的残片。
- 操作这一排比 `x` 让出来的地方还宽时，从内容带的起始边按顺序排：排到尽头的那个被截短（文字变省略号），它后面的没有矩形。所以**排在前面的操作最后才消失**——把最要紧的那个放在第一项。
- 槽位比横条高 → 压进高度内，不越界；`padding` 吃掉整个横条 / 宽高 ≤ 0 → 所有矩形都为空，绝不出现反向矩形。
- 操作放得进标题行旁边时，首选高度和没有操作时一样。放不进（主题给了操作很大的上下 `padding`，或者很大的字）才长高，长到 `TyAlertLayout` 能把它完整画出来的**最小**高度。这个高度不一定等于操作自己的高度：操作以标题行为准居中，上下 `padding` 不对称、或者有第二行时，标题行并不在横条正中。
- `TyAlertPreferredHeight` 是 `TyAlertLayout` 的**逆**：把它的结果当 `AClientHeight` 回喂，文字块正好落在 `padding` 上，两个槽位都不被压扁（已有往返测试守护）。它**不吃宽度**参数——横条的高度不依赖宽度：两行都是**单行不换行**（省略号截断，与本库其余文字一致），所以窄一点只是少显几个字，不会回流成更高的块。
- `ADescriptionHeight` 与 `AMessageHeight` **分开传**，尽管今天的控件把同一个数喂了两遍（两行共用同一份 `TyAlert` 字体）：**规则**是「每行用自己量出来的高度」，把「两者相等」焊死在几何里，等描述将来有了自己的 typeKey 就得再拆一遍。

### 公开成员

```pascal
procedure Close;                // 走 OnClose，未否决则隐藏；可对 disabled 横条调用（只有鼠标路径受 Enabled 门控）
function HasDescription: Boolean; // Description <> ''，即是否处于两行形态
function StyleVariant: string;    // 实际参与解析的 variant 串（'warning' / 'success compact' …）
function TyAlertCloseRect: TRect; // x 槽位（设备像素，(0,0)-local）；非 Closable 时为空。绘制与命中检测同源
function TyAlertIconRect: TRect;  // 图标槽位（同上）；ShowIcon 关闭时为空
function ActionAt(X, Y: Integer): TTyAlertAction;  // (X, Y) 处那个可见的操作，没有则 nil；禁用的也算，隐藏的不算
function ActionRect(AIndex: Integer): TRect;       // Actions[AIndex] 画在哪（设备像素，(0,0)-local）；隐藏、放不下、下标越界时为空
```

`ActionAt` / `ActionRect` 和绘制、命中检测用的是同一份几何，宿主想在某个操作上弹自己的菜单或提示时用得上。

### 给子类的钩子（protected virtual）

```pascal
procedure DoAction(AAction: TTyAlertAction); virtual;        // 点中一个启用的操作；默认触发 OnAction
function ActionStates(AAction: TTyAlertAction): TTyStateSet; virtual;  // 这个操作此刻按哪个状态画
function ActionContentWidth(APainter: TTyPainter; AAction: TTyAlertAction;
  const AStyle: TTyStyleSet): Integer; virtual;              // 操作里内容的宽度（不含 padding）；默认量 Caption
procedure DrawAction(APainter: TTyPainter; AAction: TTyAlertAction; const ARect: TRect;
  const AStyle: TTyStyleSet); virtual;                       // 画一个操作；默认画底片、边框和 Caption
```

想让操作带图标、或者画成别的样子，就一起覆盖 `ActionContentWidth` 和 `DrawAction`：前者决定给它留多宽，后者在那个矩形里画。

---

## 6. 状态与主题

### 支持的伪类状态

- **横条**（`TyAlert`）：`:hover` / `:active` / `:disabled` 由基类状态机计算。
- **`x`**（`TyAlertClose`）：状态取的是**字形自己的**——指针精确落在 `x` 上才是 `:hover`，所以 `x` 独立于横条亮起（与 `TTyTag` / TabStrip 的关闭按钮同一套路）。解析时带上**横条完整的 variant 串**，因此 `TyAlertClose.error` 可以给错误横条的 `x` 单独换色。
- **操作**（`TyAlertAction`）：每个操作有自己的状态。指针落在哪个操作上，哪个才是 `:hover`；在它上面按住是 `:active`，按住拖出去就回到常态，拖回来又是 `:active`；`Enabled = False` 的操作（或者整个横条禁用时的所有操作）是 `:disabled`。同样带着横条完整的 variant 串解析，所以 `TyAlertAction.warning` 可以单独给警告横条的操作换样子。

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

操作按钮的内置样式：

```css
/* 安静的文字按钮。常态故意不写 color —— 没写就用横条自己的墨色，所以四种染色各自给
   自己的操作上色，标题读得清的地方操作也读得清；加粗是为了和标题区分开。 */
TyAlertAction          { border-radius: var(--radius-sm); font-weight: var(--font-weight-bold);
                         padding: var(--pad-alert-action); }      /* 默认 2px 8px */
TyAlertAction:hover    { background: var(--overlay-hover); }
TyAlertAction:active   { background: alpha(var(--on-surface), 0.20); }
TyAlertAction:disabled { color: var(--muted); }
```

想要描边按钮或实心按钮，给 `TyAlertAction` 加 `border-*` 或常态的 `background` 即可，控件会照着画。

`TyAlertAction` **没写的东西怎么办**：没有 `color`、没有字体 → 用横条自己的；没有 `background` → 那个状态下不画底片；没有 `padding` → 用内置的 `2px 8px`（`padding: 0` 算写了，照 0 来）。操作的宽高是按**常态**的样式量的，指针划过、按下时这一排不会跳动：`:hover` / `:active` 里写的 `padding` 不起作用；在那里改字号或字重会照着画，但宽度不重新量，文字放不下就被截断。

`TyAlertClose` **未定义时优雅降级**：无 `background` → 不画底片；无 `color` → `x` 用横条自己的 `color`。**不会**回退到任何硬编码颜色。
`TyAlert` **本身没有 `background`** 时（主题压根没定义、或定义了却没给底色）→ **整条什么都不画**，而不是画一条硬编码的横幅。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--alert-icon-size` | `16`（= `TyAlertIconSize`） | 状态图标方形槽位边长 |
| `--alert-icon-gap` | `8`（= `TyAlertIconGap`） | 图标槽位与文字列之间的间隙 |
| `--alert-text-gap` | `2`（= `TyAlertTextGap`） | 标题行与描述行之间的垂直间隙 |
| `--alert-close-gap` | `8`（= `TyAlertCloseGap`） | `x` 槽位前面的间隙：没有操作时隔开文字列，有操作时隔开最后一个操作 |
| `--alert-action-gap` | `8`（= `TyAlertActionGap`） | 每个操作前面的间隙：第一个操作与文字列之间，以及相邻两个操作之间 |
| `--alert-close-size` | `14`（= `TyAlertCloseSize`，与 `TyTagCloseSize` / `TyTabCloseSize` 一致，三处 `x` 观感统一） | `x` 方形槽位边长 |

操作按钮的内边距不在这张表里：它就是 `TyAlertAction` 的 `padding`，内置主题用令牌 `--pad-alert-action`（默认 `2px 8px`）给它赋值。

`--alert-action-gap` 可以只对一条横条设：写在它自己的 `StyleOverride` 里，例如 `--alert-action-gap: 12px;`。其余几个目前只跟主题走。

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

带操作的横条（编辑器上方「文件在磁盘上被改过」那种）：

```pascal
A := TTyAlert.Create(Self);
A.Parent := Surface;
A.Align := alTop;
A.AutoSize := True;
A.AlertType := atWarning;
A.Message := '文件已在磁盘上被修改。';
with A.Actions.Add do begin Caption := '重新载入'; Tag := 1; end;
with A.Actions.Add do begin Caption := '合并';     Tag := 2; end;
with A.Actions.Add do begin Caption := '保留我的'; Tag := 3; end;
A.OnAction := @HandleAlertAction;

procedure TForm1.HandleAlertAction(Sender: TObject; AAction: TTyAlertAction);
begin
  case AAction.Tag of
    1: ReloadFromDisk;
    2: MergeWithDisk;
    3: KeepMine;
  end;
  (Sender as TTyAlert).Visible := False;      // 点操作不会自动关掉横条
end;

// 没有冲突时不给「合并」：隐藏它，标题就多出它的宽度
A.Actions[1].Visible := HasConflict;
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
- **操作的点击规矩和 `x` 一样：** 在一个操作上按下、在**同一个**操作上松开才算点了它。在一个上按下、在另一个上松开，或者拖到别处再松开，什么都不触发；在禁用的操作上点也什么都不触发，包括 `OnClick`。只认左键。点操作既不是 `OnClick`，也不会关掉横条。
- **操作没有键盘入口：** 横条不取焦点（`x` 也一样），Tab 走不到这些操作，它们也没有助记符。同样的命令要能用键盘触发，得由应用自己提供——给它配一个快捷键、一个菜单项，或者工具栏上的按钮，在里面调和 `OnAction` 相同的代码。
- **操作的提示：** 指针停在带 `Hint` 的操作上显示那一项的提示，停在别处显示横条自己的。前提是横条的 `ShowHint` 为真。
- **横条太窄时：** `x` 先保住，其次是操作，再次是图标，最后才是文字。操作也放不全时，排在后面的先被截短、再消失——所以集合里的顺序就是重要程度的顺序。
- **从右到左（`BiDiMode = bdRightToLeft`）：** 整条镜像，操作这一排到了左边，第一项仍然紧挨着文字。
- **`AutoSize` 只管高度：** `CalculatePreferredSize` 返回宽度 `0`，即 LCL 的「无首选宽度，保持现有边界」。横条是用 `Align`/`Anchors` 横跨宿主的，把宽度回缩到文字宽会**和布局打架**。
- **图标与文字同色：** 状态图标没有自己的 typeKey（本控件的 typeKey 是 `TyAlert` / `TyAlertClose` / `TyAlertAction`），取的是**横条自己的 `color`**。所以 `TyAlert.warning { color: var(--warning); }` 会**同时**染上图标和文字——这正是上面 CSS 摘要选择 Bootstrap 式「淡底 + 深语义色文字」而非 AntD 式「彩色图标 + 中性深色文字」的原因。若主题层日后想让图标单独着色，需要再加一个 typeKey（`TyAlertIcon`）。
- **两行共用一份字体：** 同理，`Message` 与 `Description` 用的是同一条 `TyAlert` 规则解析出的字体，**无法**让标题加粗而描述常规（AntD 是那样做的）。要做需要给描述一个自己的 typeKey。
- **不换行：** 两行都是单行 + 省略号截断，与本库其余文字一致。`Description` 是**第二行**，不是段落。
- **图形控件，非容器：** 无窗口句柄，子控件不能以它为 `Parent`。
- **文字用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
