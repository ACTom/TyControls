# 密度尺度:经典 / 现代 两档

日期:2026-07-21
状态:设计已确认;第一期实施计划见 `plans/2026-07-21-density-scale-p1.md`

## 一句话

给整套控件加一条**密度轴**:经典(现状,Win32 尺度)与现代(Web 尺度)。
它与配色、与皮肤风格**正交** —— win98 皮肤 + 现代密度是合法组合,含义是
"Windows 98 的观感,舒适的密度"。

## 为什么不是别的形状

### 不是"风格轴"

仓库里已经有 15 个内置皮肤,其中 `classic` / `xp` / `win10` / `win11` /
`antdesign` / `material3` 本身就在表达"经典 vs 现代"这条**风格**轴。
如果密度模式也管观感(圆角、立体边框、阴影),它会和皮肤打架 ——
"我选了 win98 皮肤又开了现代模式,到底该长什么样"没有好答案。

定成纯密度轴之后,答案是干净的:皮肤管长相,密度管疏密。

### 不是 `@mode` 的第二个值

`@mode` 已经被 light / dark 占满。密度挤进去会让每个主题写 4 个块
(light-classic / light-modern / dark-classic / dark-modern),而且这两条轴
语义完全不同 —— 一条管配色一条管几何。再加第三条轴就是指数爆炸。

### 不是全局缩放因子

Web 密度**不是等比放大**:字号 9→14 是 1.55×,内边距 6→12~16 是 2~2.6×,
圆角 3→8。比例本身是变的。

等比放大的结果是"一个放大的 Win32 程序"。这个项目已经栽过一次 ——
v3 皮肤那轮的反馈是"像放大了、不像原生",根因就是按钮内边距按比例撑大
而没有重新定比例(见 `skin-authenticity-pass`)。

## 现状:量出来的数字

| 事实 | 数字 |
|---|---|
| `font-size` 走 token | 45/45(100%) |
| `border-radius` 走 token | 57/60(95%) |
| `padding` 走 token | **0/41** —— 全是字面量 |
| `spacing` / `gap` / `margin` / `line-height` token | **不存在** |
| light.tycss 的 42 个 token 中,尺寸类 | **4 个**,其余全是颜色 |
| Pascal 里 `Scale(字面量)` | 约 330 处 |
| 其中值为 1/2/3/4 的 | **227 处** |
| 具名尺寸常量 | 66 个 |
| 7 个主题文件的基准字号 | 全是 `9px` |
| `--font-size-title` 的使用者 | **1 条规则**(TyTitleBar),值也是 9px |

两条推论:

1. **主题系统目前实质上是配色系统,不是设计系统。** 之前记下的
   "控件不用改,全走 token"是错的。
2. **要迁的比看上去少。** 227 处 1~4px 是结构性最小量(发丝线、抗锯齿内缩、
   图标与文字的缝),任何密度下都该保持原值。真正的密度值是约 100 处
   ≥6px 的调用 + 66 个具名常量。

## 机制

### Controller

```pascal
TTyDensity = (tdClassic, tdModern);

property Density: TTyDensity read FDensity write SetDensity;  // 默认 tdClassic
```

- `tdClassic` = **什么都不叠**。15 个皮肤的当前值原样生效,经典不是一个需要
  维护的包。这让"经典默认"自动成立。
- `tdModern` = 解析前叠一层 `density-modern.tycss`,里面**只有几何 token**,
  一个颜色都没有 —— 所以它对任何皮肤都成立。

密度**没有 OS 信号**可跟(明暗有),纯由程序控制,不进那个轮询。

**不做逐控件密度**,只有 Controller 级。一个窗口里一半经典一半现代不是
真实诉求。

### 按名字取尺寸令牌的 API:**已经存在**

> 更正(2026-07-21,写实施计划时发现):本节原先写的是"这是整件事真正缺的
> 基础设施",**那是错的**。

```pascal
{ TTyStyleModel }      function ResolveMetric(const AName: string; ADefault: Integer): Integer;
{ TTyStyleController } function Metric(const AName: string; ADefault: Integer): Integer;
```

两者都是 **public**,theme-v3 C 期就建好了,语义正是"从合并后的令牌里取一个
长度,取不到或解析不了就返回回退值"。全仓库只用过**一次**
(`--font-size-base` 取字体回退值)。所以第 3 期的迁移今天就没有前置:

```pascal
// 迁移前
h := Scale(TyCardHeaderHeight);
// 迁移后 —— 主题没给这个令牌时原样返回 36
h := Scale(ActiveController.Metric('--card-header-height', TyCardHeaderHeight));
```

**回退参数是迁移安全的关键**:密度包出现之前,每一处都返回原来那个常量,
逐像素相同。与本轮 `HeaderHeightPx` 收口同一条纪律 —— 先建等价收口点、
验证全绿、再往里加行为。

这条更正本身是个信号:这个仓库反复出现**能力建好了但没接线** ——
`--font-size-title` 只被引用一次、`TTyGridHeaderGroup.Level` published 却被
渲染循环整个跳过、`HasFontStyle` 有存储槽却没有属性、`Metric` 建好之后用了一次。
排查"缺什么"之前先查"是不是已经有了、只是没接",能省掉一次重复实现。

## token 词汇表

### 内边距:语义 token,不是数字尺度

**经典必须逐字节保持现状**,而现状里有 `5px 9px`、`4px 10px`、`0px 14px`
这些历史随手值。如果强推一个 4 的倍数尺度,经典会有少数控件移动 1px。

所以内边距按**角色**命名,不按尺度命名:

```css
/* 经典:原样,包括那些不规整的值 */
--pad-button: 5px 9px;
--pad-input:  4px 6px;
--pad-card:   12px 14px;

/* 现代:从一个自洽的 4px 尺度里取 */
--space-1: 4px;  --space-2: 8px;  --space-3: 12px;
--space-4: 16px; --space-5: 24px; --space-6: 32px;

--pad-button: var(--space-3) var(--space-5);
--pad-input:  var(--space-2) var(--space-3);
--pad-card:   var(--space-4) var(--space-4);
```

尺度只在现代侧存在,经典侧不引用它。这样两边都拿到想要的:
经典逐字节不变,现代内部自洽。

### 字号:层级是"现代"的一部分

今天所有控件都是 9px,`--font-size-title` 是个只被用过一次、值也是 9px 的
残留 token。**这种扁平本身就是 Win32 时代的特征。**

| token | 经典 | 现代 |
|---|---|---|
| `--font-size-sm` | 9px | 12px |
| `--font-size-base` | 9px | 14px |
| `--font-size-title` | 9px | 20px |

经典三个全等于 9px —— 忠实于那个时代,也保证 golden 不变。

需要配套 CSS 工作:约 12 个"标题性"控件(TyTitleBar / TyCardHeader /
TyPopoverTitle / TyCalendarTitle / TyGridHeader / TyTreeHeader /
TyListGroupHeader / TyTransferTitle …)目前**根本没声明 font-size**,
要让它们引用 `--font-size-title` 才有层级可言。

### 其余

| 组 | token | 经典 | 现代 |
|---|---|---|---|
| 圆角 | `--radius-sm` / `--radius` / `--radius-pill` / `--radius-round` | 3 / 6 / 8 / 12(**已存在**) | 4 / 8 / 12 / 16 |
| 控件高 | `--control-height` / `--row-height` / `--header-height` / `--item-height` | 22~30 | 32~40 |
| 图标槽 | `--icon-size` | 16 | 20 |

**行高不单独开 token**:`TTyStyleSet` 没有 LineHeight 字段,而这些控件本来
就是算高度、不排行盒。Web 的宽松行高由 `--row-height` / `--control-height`
表达,不新造概念。

## 哪些常量不迁

三类,只有第一类该动:

**① 密度值 —— 迁**
`TyCardHeaderHeight=36`、`TyCardActionsHeight=44`、`TyCascaderRowHeight=24`、
`TyCascaderColumnWidth=120`、`TyBackstageRowH=42`、`TyBackstageSidebarW=190`、
`TyDlgPad=16`、`TyCheckBoxGap=6`、`TyEmptyGap=8` …… 这些是**设计决定**,
写死在 Pascal 里等于把设计决定藏进代码。

**② 形状比例 —— 不迁**
`TyArrowDefHeadRatio=0.45`、`TyChartDonutHolePercent=55`、`TyArrowMinRatio=0.1`。
定义的是"箭头/环形图**是什么形状**",不是"多大"。甜甜圈的洞在任何密度下
都是 55%。

**③ 物理与交互下限 —— 不迁**
`TyChartHitRadius=12`(鼠标不会因为选了现代密度就变精准)、
`TyBadgeMinSize=8`(注释原文:degenerate-measure floor: stay visible)、
`TyAutoPanEdgeMargin=24`、以及 227 处 1~4px 的发丝线与内缩。

把第三类交给主题,等于允许某个皮肤把命中半径配成 2px —— 那不叫可定制,
叫可以配坏。图标槽位上已经栽过一次:12px 的槽被 DrawGlyph 每边吃掉 4px,
只剩 3px 一坨糊点,当时报的是"箭头方向反了",其实是读不出方向
(见 `glyph-slot-floor`)。

## published 属性的流式化约束

```pascal
property DefaultRowHeight: Integer read ... write ... default 22;
```

Pascal 的流式化靠"与 `default` 不同才写进 .lfm",所以 `default` **必须是
编译期常量**,不能是"从主题取"。

仓库已有对应惯例:

```pascal
property FilterRowHeight: Integer ... default 0;   { 0 = 跟列头同高 }
property DropDownWidth:   Integer ... default 0;   { 0 = 跟列宽走 }
```

改造路径:`default 22` → `default 0`,0 表示"问主题要"。

**副作用要认**:已有 .lfm 里存着 `DefaultRowHeight = 22` 的窗体,升级后会
继续是 22、不跟密度走。这行为是对的(用户显式设的值该赢),但意味着
示例和 IDE 模板要把这些显式值删掉才能吃到密度。

## 测试策略

- goldens 是 **3 个文本文件**(不是 PNG),重铺成本可控
- **经典默认 ⇒ 现有 3 份必须逐字节不变**。这就是迁移忠实性的守卫,
  贯穿第 1~3 期每一批
- 现代新增 **1 份** golden,不是 3 份 ×2
- 给标题性控件补 `font-size` 声明时,若某控件此前的字体回退不是 9px,
  经典会漂移 —— 逐字节 golden 正是为了抓这个

## 示例策略

45 个示例、23,254 行,其中 **44 个已经带主题切换器**。

对应再做一套 = 再来 23k 行,以及**永久的双边同步负担**。这个仓库在同类问题上
栽过两次(生成器覆写手写代码、内置皮肤两边同步),都不是设计错误,
是"同一件事有两份实现"的必然结果。

做法:

- 每个示例在皮肤切换器旁边加一个**密度开关**(45 × 一行),
  于是每个示例都成为自己的经典/现代对照,而且能在同一个窗口里来回切
- 另做**一个** `density` 示例(与现有 `theming` 示例同定位):并排两份、
  展示整套尺度 token、给出 9px→14px 时各项的对照表

## 分期

| 期 | 内容 | 可验证的产出 |
|---|---|---|
| 0 | 修 `padding` 的 `var()` 展开顺序(多值令牌今天静默算错) | 一个测试红→绿 |
| 1 | token 词汇表(经典值)。API 不用建,`Metric` 已存在 | 3 份 golden 逐字节不变 |
| 2 | CSS 侧:41 条 padding 改走语义 token | 同上 |
| 3 | Pascal 侧:约 100 处 + 66 个常量,分批迁 | 每批 golden 不变 |
| 4 | `density-modern.tycss` + `Controller.Density` | 现代 golden;**真机看** |
| 5 | 45 个示例加开关 + `density` 示例 | 真机看 |

**第 0 期是地基,而且已经查实是坏的**:`ParsePadding` 先按空格切分、再逐段
求值,于是 `padding: var(--pad-tooltip)`(值为 `5px 9px`)会被当成单个长度 ——
展开成 `5px 9px`、末尾 `px` 被剥掉变成 `5px 9`、`ParsePctOrNum` 给出错数。
**不报错,只是错。** 19 个角色令牌里有 12 个是多值的,所以这是硬前置。

不确定性全部集中在**第 4 期** —— 现代那套比例到底调没调对,只有真机上
看了才知道。第 1~3 期是纯机械的、有逐字节 golden 守着的铺路。

## 明确不做

- 逐控件密度覆盖
- 密度跟随 OS(没有这个信号)
- 第三档密度(紧凑)。Controller 上是枚举,以后要加是加一个值的事,
  但现在不做
- 经典侧的间距尺度归并(会让经典漂移 1px,与"经典逐字节不变"冲突)
- 翻转默认值。现代成为默认要单独用一次 major 版本,不和基础设施同批发
