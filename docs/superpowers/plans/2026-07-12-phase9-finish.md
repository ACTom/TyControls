# Phase 9 收尾 —— TTyChart + TTyHtmlLabel + Transitions(三项并行)

> 路线图 Phase 9 剩余三项,用户批准 v1 范围后一次做完。三个**互不相干的新单元**,并行三个 workflow;
> 共享集成文件(lpk/Design/icons/tytests/docs)由控制者事后统一改。**零新增主题 token**;跨平台;无原生控件。
> 每项唯一可无头测的是**纯函数**(几何/解析/插值);绘制/鼠标/窗口靠真机。

---

## ① TTyChart（`source/tyControls.Chart.pas`）

`TTyChart = class(TTyGraphicControl)` —— 折线/柱/饼图。`GetStyleTypeKey := 'TyPanel'`(背景/文字/网格走主题
surface/text/border;系列色用固定雅致调色板)。

**类型**:`TTyChartType = (ctLine, ctBar, ctPie)`;`property ChartType`。

**数据**:`Series: TTyChartSeries`(TCollection,设计期可编辑),每项 `Name: string; Color: TColor;
Values: string`(逗号分隔的数值,便于流式;或一个 TDoubleArray + AddValue)。`Categories: TStrings`(X 轴分类)。
折线/柱=多系列;饼=第一个系列的各值为扇区。

**装饰**:`Title: string`、`ShowLegend: Boolean`、`ShowGrid: Boolean`、`ShowValues: Boolean`(柱/饼标数值)。

**渲染**(RenderTo,BGRA `Canvas2D`,抗锯齿):折线=各系列 moveTo/lineTo + 点;柱=分组填充矩形;
饼=`arc` 扇区。Y 轴自动量程 + nice 刻度 + 网格;X 轴 Categories;图例(色块+名)。

**纯函数(接口导出,无头测)**:
```pascal
{ 漂亮量程:把 [min,max] 扩到 nice 边界,返回 niceMin/niceMax/step 使刻度数≈ATarget }
procedure TyChartNiceRange(AMin, AMax: Double; ATarget: Integer;
  out ANiceMin, ANiceMax, AStep: Double);
{ 值 -> 像素 Y(top=niceMax,bottom=niceMin,线性)}
function TyChartValueToY(AValue, ANiceMin, ANiceMax: Double; ATop, ABottom: Integer): Integer;
{ 第 AIndex 个柱(共 ACount,在 [ALeft,ARight] 均分,含组间距)的 X 矩形 }
procedure TyChartBarXRange(AIndex, ACount, ALeft, ARight: Integer; out AX0, AX1: Integer);
{ 饼扇角度:各值 -> (起始角, 扫过角) 度;和=360;负值/全零安全 }
function TyChartPieSweeps(const AValues: array of Double): TDoubleArray;   { 交错 start,sweep 或返回 record 数组 }
```
测试:nice-range(如 [0,97]→0..100 step 20 之类,断言 step 是 1/2/5×10^k、niceMin≤min、niceMax≥max、刻度数合理);
value→Y 端点与中点;柱 X 分区不重叠且在界内;饼扇 sweep 和=360、比例正确、全零不崩。

**v1 不含**:tooltip/交互/缩放/混合类型/次坐标轴。

---

## ② TTyHtmlLabel（`source/tyControls.HtmlLabel.pas`）

`TTyHtmlLabel = class(TTyCustomControl)` —— 迷你 HTML 标签(**行内子集**,不是浏览器)。窗口化(链接要鼠标)。
`GetStyleTypeKey := 'TyLabel'`(复用标签样式;文字色取主题,链接色取 accent)。

**支持子集**:纯文本 + `<b> </b>`、`<i>`、`<u>`、`<s>`(删除线)、`<font color=#rrggbb size=N>`、
`<a href="...">`、`<br>`。实体:`&lt; &gt; &amp; &quot; &nbsp;`。大小写不敏感标签。畸形/未知标签**容错跳过**不崩。
**不做**:表格/图片/CSS/列表/块级嵌套/`<div><p>`。

**状态/API**:
```pascal
published
  property Html: string read FHtml write SetHtml;   { 设值重解析 + 换行 + 重绘 }
  property WordWrap: Boolean default True;
  property OnLinkClick: TTyHtmlLinkEvent;   { procedure(Sender; const AHref: string) }
  property AutoSize; Align; Anchors; StyleClass; Controller; ...
```
渲染:解析成 runs -> 按控件宽度换行成 lines -> BGRA 逐 run 画(粗/斜/下划线/删除线/色/字号);链接 run 命中测试
(MouseMove 改手型 + MouseUp 触发 OnLinkClick)。

**纯函数(接口导出,无头测)** —— 解析是核心可测面:
```pascal
type
  TTyHtmlRun = record
    Text: string; Bold, Italic, Underline, Strike, LineBreak: Boolean;
    Color: TColor; HasColor: Boolean; SizePt: Integer;  { 0=默认 }
    Href: string;   { ''=非链接 }
  end;
  TTyHtmlRunArray = array of TTyHtmlRun;
{ 把 HTML 子集解析成富文本 run 序列(标签改样式栈,<br> -> LineBreak run,实体解码,畸形容错)}
function TyHtmlParse(const AHtml: string): TTyHtmlRunArray;
```
测试:`'a<b>b</b>c'` -> 3 run,中间 Bold;`<a href="x">t</a>` -> run.Href='x';`<br>` -> 一个 LineBreak run;
`&lt;&amp;` -> 解码成 `<&`;`<font color=#ff0000>` -> HasColor + Color=红;嵌套 `<b><i>x` -> Bold+Italic;
未知/未闭合标签不崩;`<font size=14>` -> SizePt=14。**换行**依赖文本测量(BGRA),用一个小位图无头测或留真机。

**v1 不含**:块级布局/对齐/图片/`<p>`边距。

---

## ③ Transitions（`source/tyControls.Transitions.pas`）—— 跨平台过渡工具

**不改 TTyForm**(避免动窗口 chrome 那套微妙代码)。一个自成一体的工具单元:全局过程 + 一个惰性 timer 驱动
`TTyAnimator`,给控件/表单播放出现动画。

```pascal
type TTyTransitionKind = (ttNone, ttFade, ttSlideUp, ttSlideDown, ttSlideLeft, ttSlideRight);
{ 播放:滑入=动 AControl 的位置(跨平台);淡入=表单 AlphaBlendValue(仅 Windows,其它平台降级为直接显示)。
  ADurationMs 默认 200。用惰性 TTimer + TTyAnimator + TyLerpF/I 驱动,结束自清理。 }
procedure TyPlayTransition(AControl: TControl; AKind: TTyTransitionKind; ADurationMs: Integer = 200);
{ 便捷 }
procedure TyFadeIn(AControl: TControl; ADurationMs: Integer = 200);
procedure TySlideIn(AControl: TControl; AKind: TTyTransitionKind; ADurationMs: Integer = 200);
```
- **slide**:记录目标 Bounds,从某边外偏移开始,`TyLerpI` 动回目标(SetBounds 每帧)。跨平台。
- **fade**:`{$IFDEF MSWINDOWS}` 用 `TForm(AControl).AlphaBlend := True; AlphaBlendValue := lerp(0..255)`,结束设 255 关 AlphaBlend;非 Windows 直接显示(降级),**给出注释说明**。
- 内部一个隐藏的 driver(TComponent 持 TTimer + 状态,自释放),或一个单例管理器。**无泄漏**、控件析构中安全。

**纯函数(接口导出,无头测)**:
```pascal
{ 某边滑入的起始偏移(相对目标),供动画 lerp:t=0 在偏移处,t=1 在 0 }
procedure TyTransitionStartOffset(AKind: TTyTransitionKind; AW, AH: Integer;
  out ADX, ADY: Integer);
```
测试:各方向的起始偏移方向/量正确(ttSlideUp -> 从下方 +AH 之类,依约定钉死);`TTyAnimator` 插值:半程在
(from,to) 之间、到时长后 Running=False 且值=to(用 TyLerpI/F)。窗口/timer 行为真机。

**注册**:纯工具函数,**无调色板组件**(不进 Design.pas/图标);只 lpk + tytests + docs。

---

## 集成(控制者事后统一,每项落地时)

- `tycontrols.lpk` 各加 Item;`tests/tytests.lpr` 各加 uses。
- **Chart + HtmlLabel** 是控件 -> 注册进 Design.pas(Chart 新开 **TyControls Charts** 组;HtmlLabel 进
  **TyControls**(标签类)或 Containers)+ 调色板图标(genicons/gen-icons.ps1/test.paletteicons,142→144)。
- **Transitions** 无组件 -> 不注册、无图标。
- 各 `docs/controls/*.md` + README 索引;examples(chart 三图 / htmllabel 富文本 / transitions 演示)。

## 验收(每项)

- 全量测试 0 失败(基线 2834 + 新增纯函数测试)。
- 零新 token;受保护文件零改(尤其 **Transitions 不改 tyControls.Form.pas**);调色板漂移守卫过。
- examples 双击可跑,真机验渲染/交互/动画。
- 过 [[pre-merge-checklist]](合并回 main 时统一 i18n / README 中英)。
