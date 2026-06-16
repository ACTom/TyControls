# TyControls `.tycss` 样式语言参考手册

本文档是 TyControls v1 样式语言(`.tycss`)的权威语法参考,面向主题作者与控件开发者。
文中每一条语法规则均与引擎实现(`source/tyControls.Css.Lexer.pas`、`Css.Parser.pas`、
`Css.Values.pas`、`StyleModel.pas`、`Painter.pas`)逐条核对,如与其他文档冲突,以本文为准。

加载入口:`TTyStyleModel.LoadFromFile(文件名)` / `LoadFromCss(源码字符串)`。
语法错误抛出 `ETyCssError`(含行/列号);属性值非法(如无法解析的颜色)在加载时抛出异常;
**未知的属性名被静默忽略**,不会报错。

## 内置默认皮肤与覆盖语义

库内置一套默认皮肤(等同 `themes/light.tycss`),作为始终存在的基础层。`ResolveStyle`
的实际行为是:**当且仅当**已加载主题对某 typeKey 没有任何规则时,该 typeKey 回退到内置
默认;一旦主题为该 typeKey 写了规则,内置层对它整体失效,完全由主题决定(包括"留空"
的属性也不会从内置层渗漏)。因此完整主题与未引入本特性前渲染一致,而部分主题不会导致
未覆盖控件不可见。

---

## 1. 概览与完整示例

`.tycss` 是一个刻意精简的 CSS 方言:

- 顶层只有两种结构:`:root` 变量块 和 样式规则;
- 选择器只有一种形态:`类型 [.变体] [:状态]`,可用逗号并列多个;
- **不支持**后代选择器、子选择器、通配符等任何组合选择器;
- 变量在使用处惰性求值,支持 `var(--x)` 与裸 `--x` 两种写法;
- 颜色支持 `rgb` / `rgba` 构造函数,以及 `lighten` / `darken` / `alpha` / `mix` 调整函数,可任意嵌套。

下面是一个可直接使用的最小完整主题:

```css
/* my-theme.tycss —— 最小可用主题 */
:root {
  --accent:     #3B82F6;
  --surface:    #FFFFFF;
  --on-surface: #1F2937;
  --border:     #D1D5DB;
  --danger:     #EF4444;
  --radius:     6px;
  --focus-ring: var(--accent);   /* 焦点环颜色;可独立覆盖 */
}

TyButton {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 6px;
  font-size: 10px;
  font-weight: 400;
}
TyButton:hover    { background: darken(--surface, 4%); }
TyButton:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyButton:active   { background: darken(--surface, 10%); }
TyButton:disabled { opacity: 0.5; }

TyButton.primary        { background: var(--accent); color: #FFFFFF; border-color: var(--accent); }
TyButton.primary:hover  { background: lighten(--accent, 8%); }
TyButton.primary:active { background: darken(--accent, 8%); }

TyLabel {
  background: alpha(#FFFFFF, 0);   /* 完全透明 */
  color: var(--on-surface);
  font-size: 10px;
}

TyEdit, TyComboBox {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 4px;
  font-size: 10px;
}
TyEdit:focus, TyComboBox:focus { border-color: var(--accent); outline: 2px var(--focus-ring); }

TyPanel {
  background: var(--surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 8px;
}
```

更完整的实例见仓库内置主题:`themes/light.tycss`、`themes/dark.tycss`、`themes/showcase.tycss`。

---

## 2. 文件结构与词法

### 2.1 顶层结构

一个 `.tycss` 文件是若干 `:root` 块与样式规则的序列,顺序任意、可交错:

```css
:root { --a: #fff; }
TyButton { background: var(--a); }
:root { --a: #000; }   /* 允许多个 :root 块;同名变量后定义者覆盖 */
```

### 2.2 注释

只支持块注释 `/* ... */`,可跨行。**不支持** `//` 行注释。

### 2.3 Token 一览

| Token | 形式 | 说明 |
|---|---|---|
| 颜色字面量 | `#rgb` `#rrggbb` `#rrggbbaa` | `#` 后只吃十六进制字符;长度必须为 3、6 或 8,否则求值时报错 |
| 数字 | `10` `0.45` `.5` | 无符号;可带小数。**词法上数字不带负号**(见下方"负数") |
| 标识符 | `bold` `--accent` `-2px` | 首字符 `[a-zA-Z_-]`,后续可含数字;`-` 可作首字符,故 `--accent`、`-2px` 都是单个标识符 |
| 函数名 | `var(` `lighten(` `url(` | 标识符**紧跟** `(`(中间不能有空格)即为函数调用开头 |
| 字符串 | `"Noto Sans"` `'a'` | 单/双引号;**无转义序列**;不能含同种引号 |
| 单位/符号 | `px` `%` `deg` | `px`、`deg` 是普通标识符,紧跟数字时被粘合为 `6px`、`90deg`;`%` 是独立符号,紧贴前一数字 |
| 标点 | `: ; { } . , ( )` | |

负数:`-2px` 在词法上是一个标识符 token,但长度/数值求值函数能正确解析它,
因此 `shadow: 0px -2px 4px #0000002E;` 这类负偏移是合法的。

### 2.4 声明的书写规则

- 每条声明形如 `属性名: 值;`,**分号必不可少**,包括块内最后一条;
- 值一直读到分号 / `}` 为止;括号内的逗号、冒号不会截断值;
- 类型名、变体名、伪类名、属性名、函数名的匹配均**不区分大小写**
  (习惯上请按本文与内置主题的写法书写);
- 同一规则块内重复写同一属性,**后写的覆盖先写的**。

---

## 3. `:root` 变量

### 3.1 定义

```css
:root {
  --accent: #3B82F6;
  --radius: 6px;
  --hover-bg: lighten(--accent, 8%);   /* 变量可以引用其他变量 */
}
```

- 变量名必须以 `--` 开头,否则解析报错;
- 值是**原始文本**,在使用处才求值(惰性求值)。因此变量可以前向/相互引用其他变量,
  也可以存放颜色函数、渐变参数片段等任何表达式;
- 同名变量重复定义时,后定义者覆盖(包括跨多个 `:root` 块);
- 引用未定义的变量在**使用该变量的规则被求值时**(即加载样式表时)抛出异常。

### 3.2 引用:`var(--x)` 与裸 `--x` 都支持

颜色、长度、数值三类表达式中,以下两种写法**完全等价**:

```css
TyButton {
  background: var(--accent);            /* CSS 标准写法 */
  border-color: --accent;               /* 裸变量写法,同样合法 */
  border-radius: var(--radius);
  padding: --radius;
}
```

在函数参数里同样两种都可用,内置主题大量使用裸写法以求简洁:

```css
TyButton:hover { background: lighten(--accent, 8%); }      /* 裸 --x */
TyButton:focus { border-color: darken(var(--border), 10%); } /* var(--x) */
```

注意:`var(...)` 形式只能整体作为一个值或一个函数参数使用,不存在字符串拼接。

### 3.3 内置语义令牌

除 `--focus-ring`(§5.14)外,内置主题在 `:root` 中还约定了若干**语义令牌**,供子部件
typeKey 与文本类控件引用。它们都是普通 `--变量`,可被主题作者整体覆盖:

| 令牌 | 内置取值(light) | 语义 / 用途 |
|---|---|---|
| `--selection` | `alpha(var(--accent), 0.30)` | 文本选区高亮带底色(accent 着色的半透明);由 `TyTextSelection` 引用,使 Edit/Memo 的选区与列表选中行视觉同源 |
| `--muted` | `alpha(var(--on-surface), 0.5)` | 弱化前景色(占位符 / 提示文字);由 `TyTextHint` 引用 |
| `--overlay-hover` | `alpha(var(--on-surface), 0.12)` | 半透明悬停叠加层(如页签关闭 × 的圆角底片);由 `TyTabClose` 引用 |

```css
:root {
  --selection:     alpha(var(--accent), 0.30);
  --muted:         alpha(var(--on-surface), 0.5);
  --overlay-hover: alpha(var(--on-surface), 0.12);
}
```

> 改这三个令牌即可全局调整选区/占位符/悬停叠加的外观,无需逐个控件改写;它们与上面的
> `--accent`、`--on-surface` 一样在使用处惰性求值,可引用其他变量。

---

## 4. 选择器与样式解析

### 4.1 选择器文法

```
选择器     ::= 类型名 [ "." 变体名 ] [ ":" 状态名 ]
选择器列表 ::= 选择器 { "," 选择器 }
```

- **类型名**:控件的 typeKey(见第 8 节),如 `TyButton`;
- **变体名**(可选):任意标识符,对应控件 `StyleClass` 属性中的某个 token,如 `.primary`;
  每个选择器**最多一个**变体;
- **状态名**(可选):只能是 `hover`、`active`、`focus`、`disabled` 四个之一,
  其他伪类名直接解析报错。每个选择器最多一个状态。

```css
TyButton { ... }                 /* 类型基础样式 */
TyButton.primary { ... }         /* 变体 */
TyButton:hover { ... }           /* 状态 */
TyButton.primary:hover { ... }   /* 变体 + 状态 */
TyEdit:focus, TyComboBox:focus { ... }   /* 逗号列表:同一组声明注册到多个选择器 */
```

### 4.2 明确不支持的选择器

以下写法都会导致解析错误或不被识别,引擎**没有**任何组合选择器:

- 后代 / 子选择器:`TyPanel TyButton`、`TyPanel > TyButton`
- 通配符:`*`
- 多变体:`TyButton.primary.large`(一个选择器只允许一个 `.变体`)
- 纯类 / 纯状态选择器:`.primary`、`:hover`(必须以类型名开头)
- 属性选择器、`!important`、`@media`、`@import` 等一概不支持

### 4.3 控件状态从哪里来

控件每次重绘时计算当前状态集:

- `disabled`(控件 `Enabled = False`)是**排他的**:禁用时只有 disabled 一个状态,
  hover / focus / active 均被忽略;
- `hover`:鼠标位于控件上;
- `active`:鼠标左键按下未释放(对 CheckBox 等也是"按住"而非"选中");
- `focus`:控件拥有键盘焦点。`TyLabel` 基于 GraphicControl,**没有** focus 状态,
  其余 9 个 typeKey 均支持 focus。

多个状态可同时成立(如鼠标悬停在已聚焦的按钮上 = hover + focus)。

### 4.4 样式解析与合并顺序(ResolveStyle)

控件最终样式由多层 `TTyStyleSet` 按**固定顺序**合并,后层只覆盖其**显式声明过**的属性:

1. **类型基础层**:`Type { }`;
2. **变体层**:控件 `StyleClass` 中的每个空格分隔 token,按其在 `StyleClass`
   字符串中的文本顺序依次应用 `Type.变体 { }`(`StyleClass` 可含多个变体,如 `"primary large"`);
3. **状态层**:对当前成立的每个状态,按固定顺序 **hover → focus → active → disabled**
   依次处理;每个状态内先应用 `Type:状态 { }`,再按变体顺序应用 `Type.变体:状态 { }`。

由此可见:**带状态的规则永远晚于(强于)不带状态的规则,带变体的状态规则永远晚于
同状态的纯类型规则**。

#### 为什么 `.primary` 的悬停必须写成 `TyButton.primary:hover`

```css
TyButton          { background: #FFFFFF; }
TyButton:hover    { background: #F0F0F0; }              /* 状态层 */
TyButton.primary  { background: var(--accent); }        /* 变体层 */
```

鼠标悬停在一个 `StyleClass = primary` 的按钮上时,合并顺序为:
`TyButton` → `TyButton.primary` → `TyButton:hover`。
状态层在变体层**之后**,所以 `TyButton:hover` 的 `#F0F0F0` 会盖掉 `.primary`
的强调色——primary 按钮一悬停就"褪色"。正确做法是为变体补一条同状态规则,
它在 `TyButton:hover` 之后应用:

```css
TyButton.primary:hover { background: lighten(--accent, 8%); }
```

#### 重复选择器:先写者胜

引擎为每个 `(类型, 变体, 状态)` 组合查找规则时返回**文件中第一条**匹配的规则,
与浏览器 CSS"后写覆盖"相反:

```css
TyButton { background: #FF0000; }   /* 生效 */
TyButton { background: #00FF00; }   /* 被忽略 */
```

请勿重复定义同一选择器;需要并列声明时把它们写进同一个规则块
(块内同名属性才是后写覆盖)。

---

## 5. 属性参考

引擎可识别的属性共 16 个(另有 `background-color` 作为 `background` 的别名),其余属性名一律被静默忽略。
所有长度均为**逻辑像素**(96 DPI 基准),绘制时按控件实际 DPI 缩放。
长度值可写 `6px` 或裸 `6`(`px` 后缀可省略),也可用 `var(--x)` / 裸 `--x`。

### 5.1 `background` — 背景填充

```
background: <颜色表达式> ;
background: linear-gradient(<角度>deg, <起始色>, <终止色>) ;
```

- 纯色:任何颜色表达式(`#hex`、`var()`、裸 `--x`、颜色函数,见第 6 节);
- 渐变:见第 7 节;**角度必须是第一个参数**,值以 `linear-gradient(` 开头才按渐变解析。

```css
TyPanel  { background: var(--surface); }
TyButton { background: linear-gradient(90deg, lighten(--accent, 10%), var(--accent)); }
```

`background-color` 是 `background` 的**别名**(仅纯色语义,不接受渐变),二者效果相同:

```css
TyEdit { background-color: rgb(255, 255, 255); }   /* 等价于 background: rgb(255, 255, 255); */
```

### 5.2 `background-image` — 九宫格贴图

```
background-image: url(<路径>) slice(<上> <右> <下> <左>) ;
```

- `url()` 与 `slice()` **都必须出现**,缺一报错;
- `slice` 的四个值为整数像素,顺序固定:**上 右 下 左**(同 CSS 四值顺序),
  表示源图四边不拉伸的边框宽度;
- 路径可加引号也可不加,但**路径中绝对不能含空格**:词法器会在未加引号的路径中插入
  空格(如 `panel.png` 变为 `panel. png`),引擎通过"无条件删除所有空格"来复原,
  因此真实空格也会被一并删除而悄悄读错。目录名、文件名都请保持无空格;
- 相对路径相对于**进程当前工作目录**解析(没有"相对主题文件"的解析);文件不存在时
  该填充被静默跳过(不报错、不绘制);
- 不支持 `var()`。

```css
TyPanel { background-image: url(assets/panel.png) slice(8 8 8 8); }
```

### 5.3 `color` — 前景/文字颜色

```
color: <颜色表达式> ;
```

用于文字以及 tier-b 单色字形(CheckBox 勾选符、ComboBox 下拉箭头、SpinEdit/ScrollBar 箭头、
Tab 关闭 × 等,见 §8.3)。

```css
TyButton.primary { color: #FFFFFF; }
```

注:滑块/旋钮等 tier-a **着色面**不再借用本控件的 `color`,而由各自的子部件 typeKey
(`TyScrollThumb`、`TyToggleKnob` 等)的 `background` 决定——详见第 8.2 / 8.3 节。轨道/轨条背景仍来自父控件 `background`。

### 5.4 `border-color` / `border-width` / `border-style` — 边框

```
border-color: <颜色表达式> ;
border-width: <长度> ;
border-style: none | solid ;
```

三者配合:`border-width` 为 0(或未声明 `border-color`)时不描边。
边框沿圆角矩形内侧描绘。

`border-style` 取 `none` 或 `solid`,**默认 `solid`**;`none` 会**强制不描边**,
即便 `border-width > 0` 也不绘制边框。仅此两种取值,**不支持** `dashed`、`dotted` 等。

```css
TyEdit       { border-color: var(--border); border-width: 1px; }
TyEdit:focus { border-color: var(--accent); }
TyPanel      { border-style: none; }   /* 显式去掉边框,即便有 border-width */
```

### 5.5 `border` — 边框简写

```
border: <宽度> [<样式>] <颜色> ;
```

一次性设置 `border-width`、`border-style`、`border-color` 三者,**完全等价**于分别书写它们。
顺序为宽度在前、颜色在后,中间可选写 `solid` / `none` 样式(省略时为 `solid`)。
颜色可用任意颜色表达式(`#hex`、`var(--x)`、`rgb(...)` / `rgba(...)`,见第 6 节):

```css
TyButton { border: 2px solid var(--accent); }   /* width=2px, style=solid, color=accent */
TyEdit   { border: 1px var(--border); }          /* 省略样式,等价于 solid */
TyPanel  { border: 0px none var(--border); }     /* style=none → 强制不描边 */
```

### 5.6 `border-radius` — 圆角半径

```
border-radius: <长度> ;
border-radius: <TL> <TR> <BR> <BL> ;
```

同时作用于背景填充、边框与焦点环形状。`0px` 为直角。

- **1 个值**:四角使用相同半径(向后兼容原有行为);
- **4 个值**:按 CSS 标准顺序依次为 **左上、右上、右下、左下**(`TL TR BR BL`),
  空格分隔。值可为长度或 `var(--x)` / 裸 `--x`,支持 `0` 表示直角。

```css
TyButton    { border-radius: var(--radius); }           /* 四角相同 */
TyTitleBar  { border-radius: 6px 6px 0 0; }            /* 上圆下方(标题栏 / 页签) */
TyTabControl { border-radius: var(--radius) var(--radius) 0 0; }
```

内置主题对标题栏(`TyTitleBar`)与页签(`TyTab`)使用 `var(--radius) var(--radius) 0 0`
实现顶部圆角、底部直角效果。

**不支持**:每角长手写法(`border-top-left-radius` 等)、百分比半径、
椭圆双半径写法(`<a> / <b>`)。

### 5.7 `padding` — 内边距

```
padding: <全部> ;
padding: <上下> <左右> ;
padding: <上> <右> <下> <左> ;
```

空格分隔,只接受 1、2、4 个值(3 个值报错)。语义与 CSS 一致。

```css
TyButton { padding: 6px; }
TyPanel  { padding: 8px 12px; }
TyEdit   { padding: 4px 8px 4px 8px; }
```

### 5.8 `font-family` — 字体名

```
font-family: <字体名> ;
```

值按原始文本直接作为字体名。**不要加引号**:带引号书写时引号字符会被保留进字体名,
导致找不到字体。多词字体名直接裸写即可(空格会被规范为单个空格):

```css
TyLabel { font-family: Noto Sans CJK SC; }   /* 正确 */
/* font-family: "Noto Sans CJK SC";  错误:引号会成为名字的一部分 */
```

### 5.9 `font-size` — 字号(注意:数值是 pt)

```
font-size: <数值>[px] ;
```

**数值按"磅"(pt)解释**:绘制时换算为像素 `round(n × 96 / 72)` 再做 DPI 缩放。
允许写 `px` 后缀,但后缀只是被剥掉,数值仍按 pt 处理——`font-size: 10px` 实际是 10pt
(96 DPI 下约 13 像素)。内置主题沿用了这一写法。

```css
TyButton { font-size: 10px; }   /* = 10pt */
```

### 5.10 `font-weight` — 字重

```
font-weight: bold | normal | <数值> ;
```

- `bold` = 700,`normal` = 400,也可直接写数字(如 `600`);
- 渲染时只有粗体/常规两档:**数值 ≥ 600 绘制为粗体,否则常规**,没有中间字重。

```css
TyTitleBar { font-weight: 700; }
```

### 5.11 `opacity` — 整体不透明度

```
opacity: <0..1 小数> ;
```

对**整个控件的绘制结果**(含文字)统一施加不透明度,常用于 disabled 态:

```css
TyButton:disabled { opacity: 0.5; }
```

opacity 经由通用框架绘制路径（DrawFrame）生效。v1.1 中 `TyCheckBox` 与
`TyRadioButton` 已通过修改渲染路径使 `opacity` 与 `shadow` 正常生效；
所有 typeKey（含 `TyLabel`）均已支持。

### 5.12 `shadow` — 投影

```
shadow: <X偏移> <Y偏移> <模糊半径> <颜色> ;
```

- 四段以空格分隔,顺序固定:X 偏移、Y 偏移、模糊半径(均为逻辑像素,偏移可为负)、颜色;
- **颜色必须是单个 token**:`#hex`(推荐带 alpha 的 `#rrggbbaa`)、`var(--x)` 或裸 `--x`。
  因为值按空格切分,**不能使用含逗号的颜色函数**(`alpha(...)`、`mix(...)` 等);
  需要半透明请直接写 hex-alpha;
- 颜色 alpha 为 0 时不绘制阴影;
- 阴影同样走 DrawFrame 路径,**对 `TyCheckBox` / `TyRadioButton` 无效**。

```css
TyButton { shadow: 0px 2px 4px #0000002E; }
TyPanel  { shadow: 0px 1px 3px var(--shadow-color); }
```

### 5.13 `outline` / `outline-offset` — 焦点环

```
outline: <宽度> <颜色> ;
outline-offset: <长度> ;
```

在控件内部绘制一圈焦点指示边框。因为 TyControls 控件完全自绘、绘制结果被裁剪到控件矩形内,
焦点环总是**向内**偏移而非向外扩张。

- `outline: <宽度> <颜色>`:宽度在前(开头为数字)、颜色在后(颜色表达式)。
  与 `border` 独立,不影响布局与 `padding`。设置此属性会将 `tpOutline` 加入 `Present` 集;
- `outline-offset: <长度>`:焦点环距控件外边缘的内缩距离,默认 `0`(贴着控件边缘)。
  `outline-offset` **单独不设置** `tpOutline`——必须同时有 `outline` 规则焦点环才会绘制;
- `outline: 0` 可在特定规则里禁用焦点环(引擎只处理 `outline` 简写与 `outline-offset`,`outline-width` 属性不被识别、静默忽略);
- 焦点环的圆角跟随 `border-radius` 的四角设置(各角减去 `outline-offset` 后箍合,最小为 0)。

通常写在 `:focus` 规则内,且引用 `--focus-ring` 语义令牌:

```css
TyButton:focus { outline: 2px var(--focus-ring); }
TyEdit:focus   { border-color: var(--accent); outline: 2px var(--focus-ring); outline-offset: 2px; }
```

### 5.14 `--focus-ring` — 焦点环颜色语义令牌

这不是一个属性名,而是内置主题在 `:root` 中定义的**语义变量**:

```css
:root {
  --focus-ring: var(--accent);
}
```

所有内置主题(`light.tycss`、`dark.tycss` 等)均在 `:root` 中定义 `--focus-ring`,
并在所有可聚焦控件的 `:focus` 规则中用 `outline: 2px var(--focus-ring)` 绘制焦点环。

主题作者可按以下方式定制:

| 目的 | 写法 |
|---|---|
| 改变焦点环颜色 | `:root { --focus-ring: #FF8800; }` |
| 全局禁用焦点环 | 各 `:focus` 规则中写 `outline: 0;` 或省略 `outline` |
| 单控件禁用焦点环 | `TyEdit:focus { outline: 0; }` |
| 回归直角焦点环 | 对应控件写 `border-radius: 0;` |

---

## 6. 颜色函数参考

颜色表达式 = `#hex` | `var(--x)` | 裸 `--x` | `rgb(...)` / `rgba(...)` | 以下函数(参数本身又是颜色表达式,
**可任意嵌套**)。函数名不区分大小写。百分比参数的 `%` 后缀可写可不写
(`8%` 与 `8` 等价)——**唯一例外是 `alpha`,见下**。

任何接受颜色的位置(`color`、`background` / `background-color`、`border-color`、`border:` 简写、
颜色函数的参数等)都可使用上述全部形式。

### 6.1 `lighten(<颜色>, <百分比 0..100>)`

向白色方向提亮:每通道 `ch + (255 − ch) × p/100`;**alpha 保持不变**。

```css
TyButton.primary:hover { background: lighten(--accent, 8%); }
```

### 6.2 `darken(<颜色>, <百分比 0..100>)`

向黑色方向压暗:每通道 `ch × (1 − p/100)`;**alpha 保持不变**。

```css
TyButton:active { background: darken(--surface, 10%); }
```

### 6.3 `alpha(<颜色>, <不透明度 0..1>)`

把颜色的 alpha **替换**为给定值(RGB 不变),`0` 全透明、`1` 不透明。

> **陷阱**:第二个参数是 0..1 的小数,**不是百分比**。引擎会剥掉 `%` 后缀但
> **不会除以 100**——`alpha(#fff, 50%)` 等价于 `alpha(#fff, 50)`,结果被钳为完全不透明。
> 永远写小数:`alpha(#FFFFFF, 0.18)`。

```css
TyCaptionButton:hover { background: alpha(#FFFFFF, 0.18); }
TyLabel { background: alpha(#FFFFFF, 0); }   /* 透明背景 */
```

### 6.4 `mix(<颜色1>, <颜色2>, <百分比 0..100>)`

线性混合,百分比是**第二个颜色的占比**:`结果 = 颜色1 × (1−p/100) + 颜色2 × p/100`。
RGB 与 alpha 四个通道都参与混合。

```css
:root { --tint: mix(--surface, --accent, 20%); }   /* 80% surface + 20% accent */
```

### 6.5 `rgb(<r>, <g>, <b>)` / `rgba(<r>, <g>, <b>, <a>)`

按 RGB 分量构造颜色。`r` / `g` / `b` 为 0..255 的整数;`rgba` 的第四个参数 `a` 是
不透明度,既可写 0..1 的小数,也可写带 `%` 的百分比(`0.6` 与 `60%` 等价)。
`rgb(...)` 等价于 alpha 为 1 的 `rgba(...)`。可用在任何接受颜色的位置(含 `border:` 与 `background`)。

```css
TyEdit  { background-color: rgb(255, 255, 255); }
TyLabel { color: rgba(0, 0, 0, 0.6); }          /* 60% 不透明的黑 */
TyButton { border: 2px solid rgb(59, 130, 246); }
```

### 6.6 嵌套与变量

```css
TyButton:hover {
  background: lighten(mix(--surface, var(--accent), 15%), 4%);
}
```

---

## 7. 线性渐变

```
background: linear-gradient(<角度>deg, <起始色>, <终止色>) ;
```

- **角度必须是第一个参数**(angle-first),恰好三个参数;`deg` 后缀可省略;
  角度可带小数;
- 两个颜色参数是完整的颜色表达式(可用函数、变量,内部逗号不会引起误切分);
- 不支持多于两个色标,不支持 `to right` 等关键字方向。

### 7.1 角度方向(与 CSS 不同!)

渐变轴穿过控件中心,方向按**屏幕坐标系**(x 向右、y 向下)的数学角度计算
(`dx = cos θ, dy = sin θ`),起始色在角度反方向端点:

| 角度 | 方向(起始色 → 终止色) |
|---|---|
| `0deg` | 左 → 右 |
| `90deg` | **上 → 下** |
| `180deg` | 右 → 左 |
| `270deg` | 下 → 上 |

注意这与浏览器 CSS 约定(`0deg` 朝上、`90deg` 朝右)**不一致**。
内置 showcase 主题中常见的 `linear-gradient(90deg, …)` 是**自上而下**的渐变:

```css
TyButton.primary {
  background: linear-gradient(90deg, lighten(--accent, 10%), var(--accent));
  /* 顶部较亮,底部为强调色 */
}
```

渐变端点取在渐变轴与控件包围盒的交点上,渐变铺满整个控件矩形。

---

## 8. typeKey 与内置变体清单

选择器中的类型名即控件 `GetStyleTypeKey` 返回的 typeKey（含子部件 typeKey）:

> **保留（未来 ribbon）：** typeKey `TyRibbon`、`TyRibbonTab`、`TyRibbonGroup` 已为未来的 ribbon 条带**预留命名**——目前不对应任何控件，也不应把这三个名字用于其它用途。未来的 `TTyRibbon`（基于 `TTyTabControl`、与窗框无关、docked `alTop`）落地时会启用它们。详见 [controls/ttyform.md](controls/ttyform.md) 第 8 节。

### 8.1 控件 typeKey

| typeKey | 控件类 | focus 状态 | 内置主题用到的变体 | 备注 |
|---|---|---|---|---|
| `TyButton` | `TTyButton` | ✓ | `primary`、`danger` | |
| `TyLabel` | `TTyLabel` | ✗（GraphicControl，无焦点） | — | |
| `TyEdit` | `TTyEdit` | ✓ | — | 选区底色用 `:focus` 的 `border-color` 加 35% alpha |
| `TyCheckBox` | `TTyCheckBox` | ✓ | — | `background`/`border` 作用于小方块；控件整体透明；`opacity`/`shadow` v1.1 起生效 |
| `TyRadioButton` | `TTyRadioButton` | ✓ | — | 同上，`background`/`border` 作用于圆圈 |
| `TyPanel` | `TTyPanel` | ✓ | — | 容器，`padding` 决定内容区内缩 |
| `TyComboBox` | `TTyComboBox` | ✓ | — | 下拉箭头用 `color` 绘制 |
| `TyScrollBar` | `TTyScrollBar` | ✓ | — | 滑块样式由子部件 typeKey `TyScrollThumb` 决定(tier-a)；轨道背景来自 `background`；端部箭头墨色用 `color`(tier-b) |
| `TyListBox` | `TTyListBox` | ✓ | — | 行条目样式由子部件 typeKey `TyListItem` 决定 |
| `TyProgressBar` | `TTyProgressBar` | ✗（GraphicControl，无交互） | — | 填充段样式由子部件 typeKey `TyProgressFill` 决定 |
| `TyToggleSwitch` | `TTyToggleSwitch` | ✓ | — | `Checked=True` 时追加 `:active` 状态；旋钮样式由子部件 typeKey `TyToggleKnob` 决定(tier-a) |
| `TyTrackBar` | `TTyTrackBar` | ✓ | — | 滑块样式由子部件 typeKey `TyTrackThumb` 决定 |
| `TyGroupBox` | `TTyGroupBox` | ✓ | — | **必须声明 `background`**（用于遮盖标题处边框线） |
| `TyForm` | `TTyForm` | — | — | 自绘窗框窗体背景；经 `ApplyChromeTheme` 应用到窗体 `Color`；内置 `background: darken(--surface, 4%)` |
| `TyContentPanel` | `TTyContentPanel` | ✓ | — | `TTyForm` 的保留内容区背景；内置 `background: var(--surface)`（内容区表面色，比窗体背景 `darken(--surface, 4%)` 略浅） |
| `TyTitleBar` | `TTyTitleBar` | ✓ | — | 自绘窗体标题栏（`TTyForm` 子组件，"条带 0"） |
| `TyCaptionButton` | `TTyCaptionButton` | ✓ | `close`、`min`、`max` | 标题栏关闭/最小化/最大化系统按钮（`TTyTitleBar` 代码持有） |
| `TyTabControl` | `TTyTabControl` | ✓ | — | 标签页控件外框；页签子部件样式由 `TyTab` 决定 |

### 8.2 子部件 typeKey（不对应独立控件，由父控件内部解析）

| typeKey | 父控件 | 支持的状态 | 说明 / 内置默认 |
|---|---|---|---|
| `TyListItem` | `TTyListBox` | `:hover`（悬停行）、`:active`（选中行）、无伪类（普通行） | 每行条目的独立样式，`background` 决定行背景，`color` 决定文字颜色；内置 `border-radius:var(--radius)` + `padding:4px`，使行呈圆角并内缩 |
| `TyProgressFill` | `TTyProgressBar` | 无状态（始终正常） | 进度条填充段，`background` 决定填充色（默认 `var(--accent)`）；部分填充时只圆**起始(左)角**、保留前缘直角（详见 [controls/progressbar.md](controls/progressbar.md)） |
| `TyTrackThumb` | `TTyTrackBar` | `:hover`（鼠标在滑块上）、`:active`（拖动中）、无伪类（正常） | 滑块的独立样式，`background` 决定滑块颜色（默认 `var(--accent)`） |
| `TyTab` | `TTyTabControl` | `:hover`（鼠标悬停在该页签上）、`:active`（该页签当前被选中）、无伪类（普通未选中） | 单个页签头的独立样式；注意 `:active` 在此表示"选中态"而非"鼠标按下" |
| `TyScrollThumb` | `TTyScrollBar` | `:hover`（鼠标悬停滚动条上）、`:active`（按下）、无伪类（正常） | 滚动条滑块(thumb)的独立填充与圆角；`background` 决定滑块色、`border-radius` 决定滑块圆角。内置默认 `background:var(--border)`（hover→`darken(--border,15%)`、active→`var(--accent)`）、`border-radius:4px`——与旧版借用 `TyScrollBar` 的 `color` 渲染结果**逐字一致** |
| `TyToggleKnob` | `TTyToggleSwitch` | 无状态（始终正常） | 开关旋钮的独立填充与圆角；`background` 决定旋钮色（默认 `#FFFFFF`）、`border-radius` 决定旋钮圆角(默认 `12px`，绘制时按 `TyClampRadius` 钳到旋钮半径,圆形不变) |
| `TyTextSelection` | `TTyEdit` / `TTyMemo` | 无状态（始终正常） | 文本选区高亮带底色；只取 `background`(默认 `var(--selection)`，accent 着色的半透明)。与 `TyListItem:active` 视觉同源 |
| `TyTextHint` | `TTyEdit` | 无状态（始终正常） | 占位符 / 提示文字颜色；只取 `color`（默认 `var(--muted)`，弱化前景） |
| `TyTabClose` | `TTyTabControl` | 无状态（始终正常） | 页签关闭 × 悬停时其后的圆角底片；`background` 决定底片色(默认 `var(--overlay-hover)`)、`border-radius` 决定底片圆角(默认 `var(--radius)`)。× 字形本身仍用 `TyTab` 的 `color` 绘制(tier-b，见 §8.3) |

- 所有控件 typeKey 都支持 `hover`、`active`、`disabled` 三个状态；除 `TyLabel`、`TyProgressBar` 外都支持 `focus`；
- **变体不是封闭集合**：任何标识符都可以作为变体，只要控件的 `StyleClass` 属性包含对应 token（空格分隔，可多个）即可匹配；
- 表中"内置变体"只是三个内置主题实际定义过的：`TyButton` 的 `primary` / `danger`，`TyCaptionButton` 的 `close` / `min` / `max`（由窗体镶边自动赋给三个标题栏按钮）。

### 8.3 子部件着色的两层约定（tier-a / tier-b）

控件内部那些不属于"控件本体框"的小部件，按其是不是一块**独立的着色面**分两类处理颜色,
这是**官方约定**而非遗留缺口:

- **tier-a — 着色面（colored surfaces）：** thumb / knob / fill / progress 等本身就是一块需要
  独立配色的实心面。它们各有**专属子部件 typeKey**(`TyScrollThumb`、`TyToggleKnob`、
  `TyTrackThumb`、`TyProgressFill`),颜色取该 typeKey 的 `background`、圆角取其 `border-radius`,
  与父控件本体的 `background`/`color` 互不干扰。主题作者可单独为它们(及其 `:hover`/`:active`)配色。

- **tier-b — 单色字形（monochrome glyphs）：** 复选框勾号 / 单选圆点、ComboBox 下拉箭头、
  SpinEdit 上下箭头、ScrollBar 端部箭头、Tab 关闭 × 等只是一笔**单色墨迹**,没有独立的面。
  它们**借用所属控件(或子部件)样式的 `color`(`TextColor`)作为墨色**——这是官方约定,
  不是"应当各给一个 typeKey 却漏了"。为这类字形配色,直接改对应控件 typeKey 的 `color` 即可
  (例如 `TyScrollBar { color: … }` 改端部箭头墨色、`TyTab { color: … }` 改关闭 × 墨色)。

> 个别 tier-a 部件会同时叠加一个 tier-b 字形:页签关闭 × 的**底片**是 tier-a(`TyTabClose`
> 的 `background`),其上的 **× 笔画**是 tier-b(`TyTab` 的 `color`)。

---

## 9. 限制汇总(v1)

引擎层限制(均已在上文相应小节展开,另见 [KNOWN_GAPS.md](KNOWN_GAPS.md)):

1. **无组合选择器**:不支持后代/子/通配/多变体/纯类/纯状态选择器(§4.2)。
2. **重复选择器先写者胜**,与浏览器相反(§4.4)。
3. **`url()` 路径不能含空格**:重建文件名时空格被无条件删除(§5.2);
   路径相对进程工作目录解析,缺失文件静默跳过。
4. **`shadow` 颜色必须单 token**:`#hex` / `var(--x)` / 裸 `--x`,不能用带逗号的
   颜色函数;需要半透明用 `#rrggbbaa`(§5.12)。
5. **`opacity` 与 `shadow` 全控件生效（v1.1）**：v1.1 修复了 `TyCheckBox` 与
   `TyRadioButton` 的渲染路径，使其也支持 `opacity` 和 `shadow`；所有 typeKey 均已生效。
6. **`alpha()` 第二参数是 0..1 小数**,写百分号不会按百分比换算(§6.3)。
7. **渐变角度方向与 CSS 不同**:`0deg` 左→右,`90deg` 上→下(§7.1);
   只支持双色标线性渐变。
8. **`font-size` 数值按 pt 解释**,`px` 后缀只是装饰(§5.9);`font-weight`
   渲染只分 ≥600 粗体 / 其余常规两档(§5.10)。
9. **`font-family` 不要加引号**,引号会保留进字体名(§5.8)。
10. **子部件着色分 tier-a / tier-b（Batch ④）**：thumb / knob / fill 等着色面由专属子部件 typeKey（`TyScrollThumb`、`TyToggleKnob`、`TyTrackThumb`、`TyProgressFill`）的 `background` 着色；勾号 / 箭头 / 关闭 × 等单色字形借用所属控件的 `color`(`TextColor`)作墨色。二者均为官方约定（§8.3）。`TyScrollThumb` / `TyToggleKnob` 的默认值与早前借用 `color` 渲染时**逐字一致**。
11. **`TyTabControl` 页签溢出可横向滚动（v1.10）**：所有页签头宽度之和超过控件宽度时，页签头条带进入溢出模式可横向滚动——条带左右两端渲染 `tgArrowLeft` / `tgArrowRight` 箭头按钮，鼠标在条带上滚轮也能滚动，且切换选中页时会自动把目标页签滚入可见区。绘制时页签头被裁剪到两个箭头之间的可见带（箭头始终绘制在最上层）。详见 [controls/tabcontrol.md](controls/tabcontrol.md) 第 13 节。
12. 不支持 `@media`、`@import`、`!important`、转义字符串、`//` 行注释。
13. **边框/盒模型的取舍(v1.6)**:`border-style` 仅支持 `none` / `solid`,**无** `dashed`、
    `dotted` 等;**不存在 `margin` 属性**(外边距请用容器布局实现)。`border` 简写只是
    `border-width` / `border-style` / `border-color` 三者的合写,并不引入额外能力。
14. **`border-radius` 不支持的形式**:每角长手写法(`border-top-left-radius` 等)、
    百分比半径、椭圆双半径语法(`<a> / <b>`)均不支持(§5.6)。`outline-offset`
    单独声明时不激活焦点环——必须同时声明 `outline`(§5.13)。
