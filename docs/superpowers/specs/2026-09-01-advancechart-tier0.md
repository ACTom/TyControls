# TTyAdvanceChart —— Tier 0 定稿

> 状态：已定稿（用户 2026-09-01 拍板）· 对标版本：**Apache ECharts 6.1.0** · 分支：`feat/advancechart`

调研依据：`docs/superpowers/research/2026-09-01-echarts/`（01–19，共 12645+ 行）。
本文只锁**范围与契约**，不锁实现步骤；实现步骤按项拆到 `docs/superpowers/plans/`。

---

## 1. 已定的前提（不再讨论）

| # | 决定 | 直接后果 |
|---|------|----------|
| 1 | **新控件 `TTyAdvanceChart`，不动 `TTyChart`** | **没有任何 `.lfm` 兼容包袱**。`tyControls.Chart.pas` 那 15 个导出纯函数、`tests/test.chart.pas` 那 67 个测试，全都不是契约。`'1,,3'` 直接按 `[1, NaN, 3]` 建模，解析不了的文本 → NaN |
| 2 | **窗口化基类 `TTyCustomControl`** | 解锁焦点、键盘、图内滚动条、dataZoom 滑块、toolbox、无障碍。代价是真机三平台复验，见 §6 |
| 3 | **API = option 树**（ECharts 形状），配设计期校验编辑器 | merge 语义从 Tier 3 提到 Tier 0，仍是 XL，**而且它就是 API**。~1950 条手写 published 属性彻底消失 |
| 4 | **地图 / GeoJSON 在范围内** | geo 引擎、map series、View+RoamController、lines、geo 热力全部保留。**但只做引擎、不发图集**（见 §7 未决项） |
| 5 | **深度优先** | 先把直角坐标做透，再上径向 / 关系族 |
| 6 | **对标 ECharts 6.1**，不是 6.0、不是 5 | v5 词汇是 v6 的严格子集，粘 v5 配置照样解析。抄公式必须从 **6.1** 源码抄——6.1 重写了轴的数学，且文档滞后于源码 |

**公开口径**：「覆盖 ECharts 6.1 的全部制图与交互能力，减去浏览器投递层、减去 WebGL、减去地图数据生态；matrix / chord / thumbnail / 断轴在路线图上。」

---

## 2. 两个不可事后补的契约

这两条是选 6.1 的**全部代价**，也是 Tier 0 存在的理由。都已按 ECharts 源码核实过形状。

### 契约 ① 坐标系接口必须同时给「点」和「矩形」

ECharts 的 `CoordinateSystem` 接口（`src/coord/CoordinateSystem.ts:148-166`）里，`dataToPoint` 是必需的，`dataToLayout` 是可选的——**但可选的那个才是嵌套的支点**：`heatmap` 靠它拿格子（`HeatmapView.ts:259,277`），`calendar` 和 `matrix` 各自实现它（`Calendar.ts:302`、`Matrix.ts:181`），`coordinateSystemUsage:'box'` 把一个被嵌套的坐标系**布局进宿主为某个 datum 返回的那个矩形**里。

我们**从第一天就把它做成必需的**：

```pascal
type
  { DataToLayout 的返回。两个矩形不是冗余：
      Rect        —— 这个 datum 占有的整格（含分隔线所在的那半格）
      ContentRect —— 按分隔线宽内缩后的可用区，**嵌套的东西布局进这个**
    ECharts 的 Calendar.dataToLayout（Calendar.ts:302-321）返回的正是这一对，
    heatmap 消费时也是 `layout.contentRect || layout.rect`（HeatmapView.ts:279）。 }
  TTyCoordLayout = record
    Rect: TTyRectF;
    ContentRect: TTyRectF;
  end;

  { 一个 datum 在坐标系里的两种落点。
    Point = 锚点（折线顶点、散点中心）。
    Layout = 这个 datum「占有」的格（柱的带宽 × 值域、matrix 的格、calendar 的一天）。
    嵌套坐标系与 boxed 组件被布局进 ContentRect——这是 box 用法唯一的支点。
    无效返回：Point 用 (NaN, NaN)，Layout 用全 NaN 的矩形，永远不返回「空」。 }
  ITyCoordSys = interface
    ['{...}']
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;                     // 本坐标系占的带，设备 px
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): ITyAxis;
  end;
```

> **我们比 ECharts 走得更远一步，是有意的。** 在 ECharts 里 `dataToLayout` 是**可选**方法，
> 只有 `Calendar` 和 `Matrix` 实现了；`Cartesian2D` **没有**，所以 heatmap 被迫分三条分支
> （`HeatmapView.ts:250-285`：直角自己算宽高、matrix 走 `.rect`、calendar 走 `.contentRect`）。
> 我们把它做成**必需**并且直角坐标系也实现（格 = 带宽 × 值域），三条分支收敛成一条——
> 这既是契约 ① 的落实，也顺手把 ECharts 自己留下的一处不一致抹平。

**同时**：盒布局求解器收的是**容器矩形提供者**，不是控件客户区。

```pascal
type
  { 布局的容器来源。顶层是控件客户区；嵌套时是宿主坐标系 DataToLayout 的返回。
    写成接口而不是 TRect 参数，是因为嵌套时容器要延迟到宿主布局完成后才知道。 }
  ITyBoxContainer = interface
    ['{...}']
    function ContainerRect: TRectF;
  end;
```

**成本对比**：现在做 = 接口上多一个方法 + 布局器多一层间接。事后补 = ECharts 自己这条缝碰 **19 个调用点**，加上每个坐标系的矩形推导、usage-kind 注入路径，而且 calendar 里放图表也一起没了。

### 契约 ② scale 内核按「value→coord 可能分段不连续」建

ECharts 的做法比我原先设想的更好，而且**更便宜**：它没有把断轴特判进每个 scale，而是抽出一个 **`ScaleMapper`**（`src/scale/scaleMapper.ts`，506 行），scale 的 `normalize`/`scale` 全部委托给它。mapper 的核心是一对：

```
transformIn(val)  —— 把值从「自己的空间」正向搬进内层空间
transformOut(val) —— 逆变换
```

链到最内层才做线性归一化。**log 轴和断轴是同一个机制**（`scaleMapper.ts:198-201` 的注释原话：轴刻度多在线性空间布局，某些特性——如 LogScale、axis breaks——把值从自己的空间变换到线性空间）。`initBreakOrLinearMapper`（:293）按有没有 break 决定装哪个 mapper。

我们照抄这个形状：

```pascal
type
  { 值空间变换器。每个 mapper 把值从「自己的空间」搬进内层空间，链到最内层做线性归一。
    Linear = 恒等；Log = ln；Break = 分段塌缩。三者同构，scale 子类一个都不需要知道 break。 }
  ITyScaleMapper = interface
    ['{...}']
    function NeedTransform: Boolean;          // 大数据遍历的快路径：恒等时可整段跳过
    function TransformIn(AValue: Double): Double;
    function TransformOut(AValue: Double): Double;
    function Normalize(AValue: Double): Double;   // 值 → [0,1]；span 为 0 时返回 0.5
    function Denormalize(ANorm: Double): Double;  // Normalize 的逆
    function Contain(AValue: Double): Boolean;
    function GetExtent(AKind: TTyScaleExtentKind): TTyDoubleRange;
    procedure SetExtent(AKind: TTyScaleExtentKind; AStart, AEnd: Double);
  end;
```

**两种 extent，不是一种。** 这是 ECharts 6.1 新引入的（`scaleMapper.ts:33-68`），而且是 `containShape` 与 `dataMin`/`dataMax` 的底座——复核报告 `19` 第 11 条把 `dataMin`/`dataMax` 从 NATURAL 改判为 HEAVY-lite，就是因为它动的是这个：

```pascal
  TTyScaleExtentKind = (
    sekEffective,   // 总是存在：刻度、标签、splitLine、命中都按它
    sekMapping      // 只在 setExtent2 指定时存在：从 Effective 两端外扩，
                    // 让边缘的柱 / K 线 / 箱线图形不溢出绘图区（containShape）。
                    // 只有 normalize/scale、仿射快路径、axisPointer 触发用它
  );
```

**成本对比**：现在做 = 一个接口 + 两个实现（Linear、Log）+ extent 分两种。事后补 = 重写 `Interval`/`Log`/`Time`/`minorTicks`/`scaleMapper`/`axisHelper`/`AxisBuilder`（ECharts 里各自 24/21/36/10/26/25/36 处 break 引用）。

---

## 3. 单元划分

照 Grid 的先例拆，前六个**纯的、无句柄、可 headless 测**。命名前缀 `tyControls.AdvChart.*`，控件本体 `tyControls.AdvanceChart`。

| 单元 | 职责 | 依赖 |
|------|------|------|
| `AdvChart.Types` | 共享值类型：`TTyDoubleArray`、`TRectF`/`TPointF` 约定、NaN 语义、枚举 | Types/Math 之外无 |
| `AdvChart.Scale` | `ITyScaleMapper` + Linear/Log/Break mapper；`TTyScale` 抽象 + Ordinal/Interval/Log/Time；nice 刻度、次刻度、两种 extent | Types |
| `AdvChart.Coord` | `ITyCoordSys` + `TTyCartesian2D`（N 轴 + master/sub）；`ITyAxis` | Types, Scale |
| `AdvChart.Layout` | `ITyBoxContainer` + 盒布局求解器（px/`'%'`/关键字）；两阶段轴构建（估文字 → 收缩 → 定尺寸），形状是 `outerBounds`/`outerBoundsContain`/`nameMoveOverlap` | Types, Coord, Painter（量文字） |
| `AdvChart.Data` | 列式存储：维度（float/int/ordinal/time）、NaN 哨兵、逐点覆盖侧表（Has 标志）、逐点 id/name、ordinal 驻留 + 倒排 | Types |
| `AdvChart.Option` | option 模型树；宽松 JSON 读取；merge 语义（normalMerge / replaceMerge / replaceAll、id/name 匹配、索引空洞） | Types, fcl-json |
| `AdvChart.Catalog` | **生成的** option 目录（去重 DAG，中英描述、类型、默认值、枚举、数值域、起始版本） | — |
| `AdvChart.Complete` | 目录之上的路径感知补全与校验 | Catalog, Option |
| `AdvChart.Handlers` | 具名句柄注册表 + 模板串求值 | Types |
| `AdvChart.Style` | 四态样式模型（normal/emphasis/blur/select）；itemStyle/lineStyle/areaStyle 全键集 → BGRA 画布状态 | Types, StyleModel |
| `AdvChart.Paint` | 元素 / 绘制列表，`z`/`z2` 排序，**唯一**的命中路径 | Types, Painter |
| `AdvChart.Series` | series 注册表：逐 series 的 `Type` + 逐 series 的轴绑定 | 全部 |
| `tyControls.AdvanceChart` | 控件本体（窗口化） | 全部 |
| `tyControls.Painter` | **扩展**：矢量 API（见 Tier 0 第 2 行） | — |

设计期编辑器进 `designtime/tyControls.Design.AdvChart.Editor.pas`，**运行时库永不引用 SynEdit**——照 `tyControls.Design.Css.Editor.pas` 的先例。

---

## 4. Tier 0 的 20 项（定稿）

规模口径：S ≈ 数天，M ≈ 1–2 周，L ≈ 3–6 周，XL ≈ 数月。

| # | 能力 | 规模 | 为什么是 Tier 0 |
|---|------|------|----------------|
| 1 | 单元拆分（§3 那张表），前六个纯 + headless 可测 | S | 必须最先做，否则 `AdvanceChart.pas` 会重演 `Chart.pas` 的历史 |
| 2 | **`TTyPainter` 矢量 API** —— 路径（move/line/bezier/quadratic/arc/close）、折线、winding + even-odd 填充、描边宽度/虚线/端点/连接、仿射变换、push/pop 裁剪、逐元素 alpha、渐变与图案作为一等填充、旋转文字、`path://` 绘制、`isPointInPath`；全部主题感知 + DPI 缩放 | L | 复核 `11` 第 2 条：`TTyPainter` public 面是外框形状，没有路径/弧/变换/裁剪/虚线。**压着约 40 条 Tier 1/2**。不做的话每个 series 渲染器都去抓 `Bitmap.Canvas2D`，各自重推 DPI 缩放、主题取色、bidi 文字、非 Win 超采样门控——正是本仓库付过学费的那类坑 |
| 3 | 窗口化基类 + Win32/GTK/Qt 真机复验 | M | 决定已定；复验那一半不免费。仓库记忆：阴影糊角、擦除到父 `Color`、窗口化兄弟裁剪（`RenderTo` 看不见）、吞掉 `CM_*` |
| 4 | **option 树**：宽松 JSON 读取 + 模型树 + merge 语义（normalMerge / replaceMerge / replaceAll、id/name 匹配、索引空洞） | XL | 它**就是** API。ECharts 在这上面花了约 3729 行。FPC 自带 `fcl-json` 开 `joUTF8, joComments, joIgnoreTrailingComma` 已经收不带引号的键、单引号、尾逗号、注释——**读取端不需要自写 JSON5 词法器** |
| 5 | **生成的 option 目录** —— 从 `D:\Projects\echarts-schema\{en,zh}\documents\option.json` 生成去重 DAG（约 1900 个结构节点，不是 58910 条路径），带类型、默认值、枚举、数值域、起始版本、中英描述 | M | 编译器不再替我们查 API 了，校验与补全成了我们的活。**生成，不手写**：79% 的节点带 `uiControl`，白拿 11248 个枚举点 / 67 张枚举表、21496 个数值下限。原型已编译通过（`research/.../spike/TyEChartsCatalog.pas`，683KB）。**去重是必须的**——不去重的 `.ppu` 会到 20MB |
| 6 | **校验式设计期编辑器** —— 路径感知的 DAG 补全、惰性参考树、能读出 `series[i]` 下 `type` 判别符的容错解析器、目录感知的错误提示 | L | 用户点名要的。先例：`Design.Css.Editor` 351 + `Css.Complete` 360 + `Css.Catalog` 411 = 1122 行已经在 `.tycss` 词汇上跑通了同一台机器 |
| 7 | **具名句柄注册表 + 模板串** —— 面向那 **1212 个**接受函数的节点 | S | option 树里闭包活不下来。形状照 v6 的 `registerCustomSeries` + `itemPayload`（一个 30 行的注册表）：`renderItem: 'bubble'`、`formatter: '@MyFormatter'`，外加一等的 `'{b}: {c}'` 模板串——**光模板串就覆盖 539/1212** |
| 8 | 列式类型化数据存储 —— 维度（float/int/ordinal/time）、**NaN 作无数据哨兵**、带 Has 标志的逐点覆盖侧表、逐点 id/name、ordinal 驻留 + 倒排索引 | XL | 23 种 series 里 20 种没有它就表达不了 |
| 9 | **可断的 scale 抽象** —— `ITyScaleMapper`（Linear/Log/Break 同构）+ Ordinal/Interval/Log；nice 1-2-5、次刻度、`min`/`max`/`scale`/`splitNumber`/`interval`/`minInterval`/`maxInterval`/`boundaryGap`/`inverse`、退化域、**`startValue` 独立于 `min`**、**两种 extent** | L | 契约 ②。见 §2 |
| 10 | **坐标系接口 `DataToPoint` + `DataToLayout`** + `TTyCartesian2D`（N 个 x/y 轴 + master/sub 拆分） | L | 契约 ①。见 §2 |
| 11 | **盒布局求解器收容器矩形提供者**（`left/top/right/bottom/width/height`；px、`'%'`、关键字），全组件共用 | M | 契约 ① 的另一半。写成「控件客户区」就等于把嵌套变成重写 |
| 12 | 两阶段轴构建（估文字 → 收缩矩形 → 定尺寸），形状用 `outerBounds`/`outerBoundsContain`/`nameMoveOverlap`，**不用已弃用的 `containLabel`** | L | 标签适配的底座。v6 形状比 v5 多约 150 行（ECharts 把 v5 版留成 `legacyContainLabel.ts` 共 120 行，v6 解算器约 276 行） |
| 13 | series 注册表 —— 逐 series 的 `Type` + 逐 series 的轴绑定 | M | 混合图表类型与副轴全靠它 |
| 14 | 元素 / 绘制列表，`z`/`z2` 排序，**唯一**的命中路径 | M | 今天绘制顺序 = 代码顺序。TTySegmented 那条「绘制与命中调同一批函数」的规矩，放大版 |
| 15 | 文字度量缓存（逐字体记录、ASCII 宽表、字符串 LRU）+ 折行/截断/省略号接到 `TyWrapTextCJK` | M | 每一趟布局都要先量文字才能定矩形；而仓库记忆 `cjk-wordwrap-space-only-trap` 说只认空格的折行在 CJK 上会静默失效 |
| 16 | 四态样式模型（normal/emphasis/blur/select 成栈）+ `focus: none\|self\|series` + `blurScope` | M | 把状态事后塞进按单态写的渲染器 = 全部重碰一遍 |
| 17 | 样式解析 —— `itemStyle`/`lineStyle`/`areaStyle` 全键集 → BGRA 画布状态 | M | 每一行 series 都消费它 |
| 18 | 图表主题 typeKey + **派生**色阶 + 那 8–12 个轴域令牌，落进 `themes/light.tycss` **和** `Css.Catalog.pas`，重新生成 `DefaultTheme.pas` / `BuiltinThemeData.pas`，**17 套皮肤全验**；顺手修两个孤儿 metric | M | 仓库记忆 `variant-dies-under-skin-base-rule`：皮肤只要为某 typeKey 写了任一条规则，就整体压掉内置层。12 个令牌能跨 17 套主题验，64 个不能。色阶用现成的 `darken()/lighten()/alpha()` **派生**，**别硬编码 `#b7b9be`** |
| 19 | `subPixelOptimize` —— 奇数线宽的像素中心对齐 | S | 一个 helper，决定桌面 DPI 下 1px 轴线 / 网格 / 柱边是脆的还是糊的 |
| 20 | **v6.1 语义写进契约** —— 回调参数记录带 `rawDataIndex`（不是 dataZoom 过滤后的 `dataIndex`）；extent 模型保持 `startValue` 独立于 `min` | S | 第一天免费；等用户代码里有句柄了再改，是最贵的那类迁移 |

**合计：2 XL + 5 L + 9 M + 4 S = 20 项。**

---

## 5. 排序（深度优先）

契约先行，然后按依赖走。**第 1 阶段就是 spike**：

```
阶段 0（spike，先验证经济账）  1 → 9 → 10 → 11
阶段 1（画得出东西）           2 → 15 → 12 → 14 → 19
阶段 2（API 成形）             4 → 5 → 6 → 7 → 20
阶段 3（数据与样式）           8 → 13 → 16 → 17 → 18
阶段 4（落到控件）             3
```

第 3 项（窗口化基类 + 真机复验）**故意排在最后**：前面全是纯单元，headless 可测；把真机那趟集中到一次，而不是每步都要开图形环境。

---

## 6. 明确不做（Tier X，与版本目标无关）

SVG 渲染器与 SVG 输出 · SSR/hydrate · tooltip 的 `renderMode:'html'` · echarts-gl 与全部 3D 坐标系 · bmap/amap/leaflet · **发布 GeoJSON 图集**（引擎做，图集不做）· SVG 底图 · 可插拔 JS 投影 · `dataView` 的 DOM textarea · `setPlatformAPI` · `'lighter'` 以外的 blendMode · 把浏览器调优旋钮作为公开 option · CSS 光标名 · `transform.print` · worker 线程 · `axisPointer.handle`

**永不实现的 v5 遗留拼写**：`grid.containLabel` · `series-line.triggerLineEvent` · `tooltip.appendToBody` · `legacyViewCoordSysCenterBase` · `richInheritPlainLabel: false` · `grid.outerBoundsMode: 'none'` · `axis.containShape: false` · 以及那约 64 个 v5 时代弃用名（`itemStyle.normal`、`hoverAnimation`、`focusNodeAdjacency`、`clipOverflow`、`mapType`、18 个 zrender `text*` 样式属性…）。

---

## 7. 仍未决（不阻塞 Tier 0，但阻塞后面）

| # | 问题 | 建议 |
|---|------|------|
| Q4b | 地图：引擎还是图集？ | **引擎做、图集不做**——ECharts 自己也不发。发图集等于要维护 `src/coord/geo/fix/` 那 118 行领土争议特判（`nanhai.ts` 73 + `diaoyuIsland.ts` 45）并随边界变化维护。缓解「编辑器预览不了地图」用一个 `registerMap` 等价物 + 一小块示例几何，**S** |
| Q5 | 依赖口径 | SVG 路径解析器已退场（BGRA 的 `addPath` 覆盖全语法含椭圆弧）。剩两条：filter DSL 的 `reg` 算子要 `RegExpr`；time 轴要一个靠谱的 ISO-8601 / 宽松日期解析器。**新增第三条**：目录生成器需要 node + npm 作**构建期**依赖（非运行期），要钉住 `echarts-doc` 的 commit 并加漂移测试 |
| Q6 | 回调约定的细节 | 形状已定（具名句柄 + 模板串 + 对字面 `function(...)` 给指名道姓的拒绝）。未定：注册表键的命名、参数记录的确切字段、要不要支持 `itemPayload` 式的数据记录 |
| Q7 | 动画与重绘模型 | **已定（2026-09-05），见 `2026-09-05-advancechart-q7-repaint-model.md`**：分层缓存做（这就是 critique #6 要的那一个归属），脏矩形放 Tier 3，3.1 只承诺进入动画与状态过渡；实测推翻了 14.9 ms 那条前提——像素不是瓶颈，逐元素描边才是，所以先把一帧画便宜 |
| Q10 | 测试策略 | golden 图仍需定容差、权威 widgetset、CI 预算。**新增**：目录需要一个漂移测试，形状照 `tests/test.css.catalog.pas`——从签入的指纹重算节点数 / 枚举数 / 逐根计数，生成单元与钉住的 `echarts-doc` commit 不一致就红 |
| 新 | 目录范围 | 生成全量 v6 树，还是只生成已实现的子集？`partial-version` 标记活到了生成的 JSON 里（1024 个节点标 `6.0.0`、89 个标 `6.1.0`），一个生成器两种都能出。**建议**：出全量并带 `ofUnimplemented` 标志——校验器据此给「这个选项还没实现」而不是「未知选项」 |
| 新 | 默认色板用 v6 那 9 色吗？ | 免费，而且是用户最认得的部分。两个注意：是 **9** 色不是现在的 8；第 3 槽 `#505372` 是深板岩色，**必须整条色阶一起采用**，单独放进旧色板里会像「有一条系列被灰掉了」 |

---

## 8. 完成判据

Tier 0 完成 = 以下全部为真：

1. `tests/tytests.lpr` 里新增的 `test.advchart.*` 全绿，且总数不低于基线 6331；
2. 前六个纯单元不引用 `Controls`、不引用句柄，能在无图形环境下跑；
3. `TTyCartesian2D` 的 `DataToPoint` / `PointToData` 往返在随机域上误差 < 0.5px；
4. `DataToLayout` 返回的矩形与 `DataToPoint` 的锚点一致（锚点落在矩形内），且**绘制与命中调同一批函数**；
5. 断轴 mapper 装上之后，Interval 与 Log 两个 scale 的既有测试**一条都不用改**——这是契约 ② 设计正确的判据；
6. 盒布局求解器在「容器 = 控件客户区」与「容器 = 另一个坐标系的 `DataToLayout`」两种来源下走同一条代码路径；
7. 17 套主题的 golden 全绿（第 18 项落地后）。

---

## 9. spike 结算（2026-09-01）

计划：`docs/superpowers/plans/2026-09-01-advancechart-contracts-spike.md`。分支 `feat/advancechart`。

### 量出来的

| 项 | 值 |
|---|---|
| 实现代码 | **1473 行**（Types 176 · Scale 703 · Coord 338 · Layout 256），含注释 |
| 测试代码 | **1008 行**，**59 个测试** |
| 全量套件 | **6390 个测试，0 错 0 败**（基线 6331 + 59） |
| 纯度 | 四个单元只 uses `SysUtils`、`Math` 和彼此。无 LCL、无 BGRA、无句柄 |
| 编译 | FPC 3.2.2 / x86_64-win64，零 error |

### 判据逐条

| spec §8 | 结果 |
|---|---|
| 1 全量绿且不低于基线 | ✅ 6390 ≥ 6331 |
| 2 前几个纯单元无句柄可 headless 跑 | ✅ 见上 |
| 3 `DataToPoint`/`PointToData` 往返 < 0.5px | ✅ `TestRoundTripWithinHalfPixel`，121 个点，容差按轴换算成半像素 |
| 4 `DataToLayout` 的矩形含 `DataToPoint` 的锚点 | ✅ `TestDataToLayoutContainsItsAnchor` |
| 5 **断轴装上后 Interval/Log 的既有测试一条不改** | ✅ `test.advchart.scale.pas` 在断轴落地后**零改动**；`TTyIntervalScale` 全文不出现 break |
| 6 两种容器来源走同一条路径 | ✅ `TestBothProvidersTakeTheSamePath`：解进坐标格与解进同一个字面矩形，四条边逐一相等 |
| 7 17 套主题 golden | ⏸ 不在本 spike 范围（Tier 0 第 18 项） |

### 变异测试（8 个，全部被杀）

首轮 59 个测试一次全绿，按 `assertsame-freed-pointer-trap` 的教训做了变异测试。

| # | 故意打坏什么 | 结果 |
|---|---|---|
| M1 | 断轴的 gap 恒为 0 | KILLED（4 条红） |
| M2 | Y 轴不翻转 | KILLED（2 条红） |
| M3 | `Normalize` 忽略 mapping extent，只看 effective | KILLED |
| M4 | 数据格的 contains 从半开改成闭合 | KILLED |
| M5 | 盒布局的约束优先级反过来 | KILLED |
| M6 | 容器交出 `Rect` 而不是 `ContentRect` | KILLED |
| M7 | nice 上界用 Floor 而不是 Ceil（会切掉数据） | KILLED |
| M8 | **`TTyScale` 自己算归一化，绕过 mapper** | KILLED |

M8 是最要紧的一条：它就是契约 ② 要防的那个失败模式，被 `TestScaleAcceptsBreakDecoratorWithoutKnowingIt` 抓住。

**过程中被变异测试救回来的两个真问题：**

1. **变异脚本自己是坏的。** 第一版跑出「8 个全部 SURVIVED」——原因是 `--sparse` 会把
   fpcunit 的汇总行一起吞掉，`errors:`/`failures:` 解析成空串被当成 0，于是永远报不出 KILLED。
   改成解析完整输出 + 先跑一个**必然会被杀的 canary** 验证脚本本身，才拿到可信结论。
   （另一半坑：文件当时还没被 git 跟踪，`git checkout --` 回滚失败，变异留在了磁盘上。）
2. **`ContentRect` 的选择原本没被任何断言钉住。** 布局测试的夹具 `DividerWidth` 是 0，
   `Rect` 与 `ContentRect` 恰好相等，M6 本来会存活。给夹具加了 `DividerWidth := 6` 并断言
   「带宽 40 − 分隔 6 = 34」之后 M6 才被杀。

### 结论：**≤ 一个 L，契约成立。**

两个契约都**没有**打架，而且比预估便宜：

- **契约 ②** 比预想的省。ECharts 把断轴做成 `ScaleMapper` 的 `transformIn`/`transformOut` 链，
  **log 轴和断轴因此是同一个机制**。照抄这个形状之后，`TTyBreakScaleMapper` 是一个**装饰器**，
  `TTyIntervalScale` 和两个基础 mapper 一个字都不用改，而且断轴**免费**地和 log 组合
  （`TestBreakOnLogInnerMapper`：一个 decade 塌缩成 5%）。整个断轴支持是 Scale 单元里约 180 行。
- **契约 ①** 就是接口上多一个方法加布局器多一层间接，代价确实是「一个参数」量级。
  `ITyBoxContainer` 两个实现共 40 行，其中坐标格那个 20 行。

**不改对标 6.1 的决定。** memo §5「什么会推翻这个建议」的那一条——第一个 spike 若超过一个 L
则经济账翻转——没有触发。

### 顺带确认的三件事

1. **我们比 ECharts 多做的那一步是对的。** 直角坐标系实现 `DataToLayout` 之后，
   heatmap 在 ECharts 里被迫分的三条分支（`HeatmapView.ts:250-285`）在我们这儿收敛成一条。
2. **非引用计数基类是必须的**（`TTyNonRefCountedObject`）。坐标系归图表所有，而持有
   `ITyCoordSys` 的盒容器是临时对象；若走引用计数，最后一个临时容器出作用域就会释放掉活着的坐标系。
3. **「点在图里」与「哪个格拥有这个像素」是两条不同的规则**，前者四边闭合、后者右下半开。
   写成同一条会让贴右边框的点掉出图表，或者让相邻两个柱抢同一列像素。

### 下一步

Tier 0 第 2 项（`TTyPainter` 矢量 API，L）——它压着约 40 条 Tier 1/2，且是 §5 阶段 1 的头一项。

---

## 10. Tier 0 第 2 项落地：`TTyPainter` 矢量 API（2026-09-01）

计划：`docs/superpowers/plans/2026-09-01-painter-vector-api.md`。commit `45c5ab4` + 后续修正。

**放在哪：直接扩展 `source/tyControls.Painter.pas`**（2327 → 2879 行）。不新开单元——`Grid.pas` 15724 行、
`TreeView.pas` 8159 行，本仓库的常规就是这样；而且长在 `TTyPainter` 上才能免费拿到 DPI 缩放、
主题取色、RTL、`Opacity`，以及 `test.painter.pas` 已经跑通的 headless 测试模式。

**交付**：路径构建 14 个方法（含 `SvgPath`/`SvgPathIn` 吃 `path://`）、两种填充规则、
描边（宽度/虚线/cap/join）、`FillPathWith` 吃 `TTyFill` 渐变、`PathContains`、
状态栈 + 仿射变换 + 两种裁剪 + 逐元素 alpha、`DrawTextRotated`。新增 `ScaleF`（**不取整**的 DPI 换算）。

**29 个测试**，全量 **6419 绿**。`tests/test.painter.pas` 那 27 个**零改动**且全绿——这是「没碰坏老路径」的判据。

### 两个单位约定（写进单元头注释了）

- **路径坐标 = 设备 px**。几何层已经换算过了，画家再缩放一次就是 bug。
- **线宽 / 虚线 / 半径 = 逻辑 px**，走 `ScaleF`，**不取整**：150% 下 1px 轴线必须是 1.5，不是 `Scale()` 给的 2。

### 变异测试逐个揪出来的三件事

11 个变异，最终全部被杀。过程中有价值的是那三个**没有**一次就被杀的：

1. **虚线单位错了，而且是测试先发现的。** 头一版把虚线段长按 `ScaleF` 缩放，测试报
   「96dpi 7 段 / 192dpi 2 段」——按像素算应该是 20 段。7 ≈ 20/3，正好是线宽。
   查证 `bgrapen.pas:1324` `DashPenStyle := BGRAPenStyle(3,1)`：**BGRA 的笔样式单位是线宽的倍数，
   不是像素**。所以原实现在双重缩放（200% 下虚线会长 4 倍）。改成：对外仍收逻辑像素，
   换算推迟到已知线宽的 `StrokePath` 里做除法；因为 `ctx.save/restore` 带不动这个字段，
   另配了一条并行的 dash 栈。
2. **零宽守卫真正承重的地方没被测。** `TestZeroWidthStrokeDrawsNothing` 把守卫放宽成 `w < 0` 也照样绿——
   因为 BGRA 在线宽 0 时本来就不画。守卫真正防的是**虚线换算里的除零**（`/ w`）。补测试后该变异抛异常被杀。
3. **一段假装是保险的死代码。** `RoundRectPath` 里的半径钳制拿掉后一个测试都不红——
   因为 `TBGRACanvas2D.roundRect` 自己就钳（`bgracanvas2d.pas:2685`）。删掉并注明；
   同时注明 `TyClampRadiusPx` 防的是 `FillRoundRectAntialias`，**不是同一个入口**。
   顺带补了真正没被钉住的那条：半径是逻辑 px（96dpi 与 192dpi 对比）。

### 下一步

阶段 1 余下：第 15 项文字度量缓存（M）→ 第 12 项两阶段轴构建（L）→ 第 14 项绘制列表 + 单一命中路径（M）
→ 第 19 项 `subPixelOptimize`（S）。

---

## 11. Tier 0 第 14 项落地：绘制列表 + 唯一命中路径（2026-09-01）

commit `bab5446` + 后续修正。三个单元：**Shape**（纯）、**Paint**（纯）、**Render**（桥接）。

**核心改变：形状是「数据」，不是「一对函数」。** 老 `TTyChart` 靠「绘制与命中调同一批纯函数」来守
TTySegmented 那条规矩——三种几何、一个人记得住的时候管用；二十种 series 就不行了。现在渲染器和命中
检测拿到的是**同一个 `TTyChartShape` 记录**，没有第二份描述可以漂移。`Render` 单独成一个单元正是
为此：**在渲染时现算的几何，是命中检测看不见的几何。**

排序 = `(Z, Z2, 插入下标)`；元素**默认 Silent**（没想过命中的装饰最多是惰性的，而不是悄悄从数据
手里抢走 hover）。

**承重测试是 `TestInkAndHitTestAgree`**：画一个圆环，然后逐像素扫 40000 个点，对每个点同时问
「这儿有墨吗」和「命中检测认这个 datum 吗」，要求分歧只是抗锯齿的一条细边、不是一片区域。

52 个新测试，全量 **6500**，五个纯单元仍不引用 LCL 任何东西。

### 变异测试（11 个）与它揪出的三件事

1. **`P.SaveState` 删掉后全绿**——虚线不泄漏是因为每个元素都显式 `SetLineDash`；真正靠
   save/restore 的是 **alpha**（只在 `<1` 时才设）。补了测试。
2. **比较器里的 `A < B` 是冗余的**——归并排序本身稳定，两种实现输出完全一致，**没有任何测试能
   区分**。保留（它防的是以后换成不稳定排序），但把注释里那句「没有它顺序就由排序决定」改成实话。
3. **一个「假的偶发失败」，真凶是变异脚本**：脚本 `git checkout` 恢复了源码却**没重建**，
   之后每次全量都在跑那个被打了洞的 exe。已给脚本加上恢复后重建。

### 我在实现中途改掉的一个测试预期

`TestPolylineNaNVertexBreaksTheRun` 原本断言「有 NaN 断点时真实顶点仍可命中」——**是测试错了**。
polyline 描述的是**描边**；两段都带 NaN 端点，什么都没画，让它认领没有墨的地方正违反这一层的核心
不变量。孤立数据点由**符号元素**（另一个形状）负责。顺带把「单点 polyline 可命中」的特例也去掉了
——单点同样什么都不描。

### 下一步

阶段 1 只剩第 19 项 `subPixelOptimize`（S）。之后进阶段 2（API 成形：option 树 → 目录 → 编辑器）。

---

## 12. Tier 0 第 19 项落地：`subPixelOptimize`（2026-09-01）

新单元 `source/tyControls.SubPixel.pas`，**独立、零依赖**——它是「光栅器如何落墨」的算术，
既不是图表概念也不是 LCL 概念，所以任何画细线的控件和图表的纯层都能用。
规则照 zrender（`graphic/helper/subPixelOptimize.ts`）：把坐标挪到让**描边外缘落在整像素上**，
于是奇数线宽要半整数中心、偶数线宽要整数中心。

**关键设计决定：在构造形状时 snap，不在渲染时 snap。** 渲染器和命中检测读的是同一个形状记录；
在渲染器里 snap 会让命中检测面对**没 snap 的几何**，每条边上平白多出半像素的分歧——正是这一层
竭力避免的漂移。`TySnapShape` 只动矩形和轴对齐的两点折线：在数据折线中间 snap 一个顶点等于
**挪动一个数据点**，那比一条软边严重得多。

**证明用的是像素而不是算术**：未 snap 的 1px 线糊在两行上（各半透明），snap 后正好铺满一行、
且是实心的。

**测试逮到的一个真 bug**：零宽矩形 snap 之后**倒置**了（-1 宽）——因为两条边朝相反方向 snap。
倒置矩形会活过后面的 Min/Max 交换、在别处冒出一条幽灵带，这正是 `TySolveBox` 和 `DataToLayout`
都选择「宁可塌缩不可倒置」的原因；现在这里也一样。

19 个新测试，全量 **6519**。5 个变异全部被杀。

**阶段 1 到此收口。** 第 2、12、14、15、19 项全部完成（15 项是「本来就有」）。
下一步进**阶段 2**：option 树（XL）→ 生成目录（M）→ 校验编辑器（L）→ 具名句柄注册表（S）
→ v6.1 语义写进契约（S）。

---

## 13. Tier 0 第 4 项落地：option 树（2026-09-01）

`source/tyControls.AdvChart.Option.pas`。**这就是 API。**

### 先实测，再动手：不需要自写 JSON5 词法器

上一轮我转述过「fcl-json 宽松模式够用」，这次**写了探针实测**（scratchpad/probe/jsonprobe.lpr）：

| 写法 | 结果 |
|---|---|
| 不带引号的键 `{a:1}` | OK |
| 单引号字符串 / 单引号键 | OK |
| 尾逗号 | OK |
| `//` 与 `/* */` 注释 | OK |
| 真实的 ECharts 配置 | OK |
| JS 函数值 | **FAIL**，带行列位置 |

最后一行正是想要的：**指名道姓地报错，而不是静默忽略**。我们再把它改善一层——裸的
"unexpected token" 对用户毫无帮助，所以当文本里含 `function`/`=>` 时，消息里补上他**能**写的两种
东西：`'{b}: {c}'` 模板串，或 `'@已注册句柄'`。

### 范围决定：不做增量 merge

ECharts 的 `normalMerge` / `replaceMerge` / `replaceAll` 带 id 匹配和刻意的索引空洞，
在它自己源码里约 3700 行，本身就是一个 XL。`SetOptionText` **整体替换**（等价 notMerge）。
第一版没人真需要增量 merge，而且以后补上不会改动任何「只做过整体替换」的调用点。
**这把第 4 项从 XL 压到 L 左右。**

### 一条行为决定

**解析失败时保留上一份好的 option。** 设计期编辑器里每敲一个字符都可能暂时不合法；
因此报错但不清空——图表继续画它最后看懂的东西。

> **2026-09-03 推翻（用户拍板）。** 这条的前提是「编辑器每敲一字就把文本推给控件」。
> 而实际做出来的编辑器是**模态对话框、按确定才写回**，Object Inspector 也是一次提交——
> 半成品文本根本不会到达控件。前提没了，剩下的只是**一个会说谎的控件**：属性里是 A、
> 画面上是 B，屏幕上没有任何东西说明这件事；设计期尤其糟，读起来像「我的改动没生效」
> 而不是「我写错了」。现在的规则是 **解析失败就没有图**，见 §25。

22 个测试，全量 **6541**。

### 变异测试逮到的：泄漏这一类全库都没人看

去掉替换前的 `FreeAndNil(FRoot)`（每次调用泄漏一整棵解析树）**所有测试照样绿**——
因为这个套件里没有任何东西看内存，也没开 heaptrc。而**替换 option 正是热路径**
（图表每次重新配置都走它，设计期编辑器还会在打字时按定时器走）。
所以补了一个专盯这一类的测试：200 次替换一个 200 点的配置，看堆增长，
阈值放宽以便它只对 bug 变红、不对分配器噪声变红。

### 阶段 2 余下

第 5 项生成目录（M）→ 第 6 项校验编辑器（L）→ 第 7 项具名句柄注册表（S）
→ 第 20 项 v6.1 语义写进契约（S）。

---

## 14. Tier 0 第 5 项落地：生成的 option 目录（2026-09-02）

`tools/advchart/` 两段流水线 + `AdvChart.Catalog`（生成）+ `AdvChart.Complete`（手写）。

**为什么两段**：输入是仓外 278MB 的 echarts-doc 构建产物，重新生成还要联网 + npm。
而全新 checkout 必须仍能重建单元并**证明它同步**，所以钉住的输入必须是仓库里真有的东西。
`extract-catalog.js`（29MB 中英 schema → `catalog.json` 0.55MB，**入库**，只在对标版本移动时跑）
+ `gen-catalog.js`（`catalog.json` → Pascal，任何机器可重现）。

**57785 次节点出现折叠成 2455 条记录（23.5×）**——schema 把 itemStyle/label/textStyle 在每个父节点下
物理复制一遍，平铺成每条路径一行会是几十 MB 字面量，编不动。

### 修掉而不是继承 spike 的两个 bug

1. spike 按**下标**配对中英的 `anyOf` 变体，而 `graphic.elements` 的变体顺序在两个文件里不同，
   于是两个子树被配上了错的语言。现在按**判别符标签**配对，不匹配就大声失败（今天是 0 个）。
2. spike 取摘要时没先剥掉版本 div，291 个选项的整条描述变成了 "Since v6.0.0"。

### 生成单元不含描述

仓库里**没有任何单元有非 ASCII 字符串字面量**、没有 codepage 指令、没有 BOM，可译文本走 `.po`。
摘要留在 `catalog.json` 里、**按同一个节点索引**寻址，设计期编辑器从那儿读。
schema 里唯一一个非 ASCII 默认值（U+25B6）按 UTF-8 **字节转义**发射，源文件保持纯 ASCII 字节。

### 漂移守卫：三个，而不是 Lucide 的两个

照 `tyControls.Icons.Lucide`（SHA-1 钉输入 + 钉生成器），**不照 `Css.Catalog`**
（它只检查目录没有凭空发明，所以上游**新增**的东西照样全绿）。

但变异测试发现 **Lucide 那一对本身有洞**：改**结构**会被抓（DAG 重展开 + 自洽性检查），
改**一个数据值**不会——两个摘要常量就住在被改的那个文件里。
所以加了第三个：数据段放在一个标记行之下，单独摘要。
（Lucide 的注释声称能抓手改；就这一点而言不准确。）

### 顺带修的两个既有问题

- **`NoCoreUnitReferencesTheBundledFont` 误报**：它对整个文件做子串扫描，我在**注释**里提到
  `tyControls.Icons.Lucide` 就触发了。注释不可能造成依赖。改成扫描前先抹掉注释——更精确而非更弱，
  并用变异验证真的 `uses` 仍被抓住。
- **那条一直没定位的偶发失败查明了**：`TestCtrlXGestureCutsAndReadOnlyDegradesToCopy`。
  Windows 上写剪贴板要打开它，别的进程短暂持有就会失败，而 LCL 的 `TClipboard` 吞掉这个失败，
  于是哨兵没写进去、断言拿旧值去比。四处哨兵写入改走带检查的 setter。

21 个新测试，全量 **6562**。

### 阶段 2 余下

第 6 项校验编辑器（L）→ 第 7 项具名句柄注册表（S）→ 第 20 项 v6.1 语义（S）。

---

## 15. Tier 0 第 6 项（部分）：补全内核（2026-09-02）

**顺序问题先说清楚**：第 6 项是设计期编辑器，要挂在 `TTyAdvanceChart.Option` 这个属性上——
而控件本体是第 3 项，spec §5 把它排在**最后**（真机复验集中做一次）。所以现在没有属性可挂。

这一轮做的是它**可测的内核**，放进 `AdvChart.Complete`；SynEdit 那层壳等控件出来再套。
这也正是仓库自己的分法：`Css.Complete` 是逻辑、`Design.Css.Editor` 是壳。

### 扫描必须容错，且不能用 JSON 读取器

打字过程中「大括号没闭合」是**常态**。用 `TTyChartOption` 去解析意味着补全只在文档合法时
才出现——也就是几乎不出现。所以是一个小状态机，从光标**往前**扫文本，维护一个容器栈。

它顺带记住每个对象自己的 `type` 值，于是**判别联合不需要解析树就能定**：
`series[0].itemStyle` 是二十三种形状之一，而等光标进到那里时 `type` 通常已经写在上面一行了。
写了才定得下来——没写就报 `NeedsVariantType`，让编辑器说「先写个 type」，
而不是弹一个空列表（看起来像功能坏了）。

值位置只提供**枚举**值；5776 个字符串选项的取值只存在于文档散文里，
凭空编一个列表比给空列表更糟。

19 个测试，**每一条的输入都是没闭合的片段**。全量 **6581**。

### 两个坑

1. **FPC 的 `{ }` 注释会嵌套。** 我在注释里写了 `'{' or ','`，那个 `{` 开出第二层，
   收尾的 `}` 只关掉第二层，**后面整个文件被吞进注释**，报的却是文件末尾的
   "unexpected end of file"。真正的线索是 `Warning: (2005) Comment level 2 found`——
   而我第一次用 grep 只捞 error，正好把它滤掉了。已写进记忆。
2. **变异测试逮到字符串转义没被测**：去掉 `\` 跳过，所有测试照样绿。它是承重的——
   `formatter: 'it\'s {c}'` 会在 `\'` 处提前结束字符串，模板里剩下的大括号被当成结构，
   光标落进一个不存在的容器。补测试后杀掉。

### 阶段 2 余下

第 6 项的 SynEdit 壳（等第 3 项）→ 第 7 项具名句柄注册表（S）→ 第 20 项 v6.1 语义（S）。

---

## 16. Tier 0 第 7 + 20 项：具名句柄与模板串（2026-09-02）

`source/tyControls.AdvChart.Handlers.pas`。两项合在一起做，因为 **v6.1 的语义就住在这个参数记录里**。

约 1212 个 schema 节点接受函数，光 `formatter` 就 539 个。闭包活不进序列化的 option 文本，
所以要有别的答案，按「多数情况下哪个对」排序：

| 形式 | 何时用 |
|---|---|
| `'{b}: {c} ({d}%)'` | ECharts 自己的模板语法，**不用注册、不用编译**，覆盖 539 个 formatter 的绝大多数 |
| `'@SalesFormatter'` | 走注册表到一个 Pascal 方法。可流式化、设计期可见，正是 ECharts 6 给 `registerCustomSeries` 选的形状——**一个名字加一份载荷**，而不是内联闭包 |
| 真事件 | 少数本该长在控件上的 |

模板按**查到的官方语法**实现，不凭记忆：`a b c d e` 加可选的系列下标后缀（`a0`/`b1`——
axis 触发的 tooltip 就是这么点名多条系列中的一条），外加 dataset 的 `@name` 与 `@[n]`。
**认不出的占位符原样保留**：删掉会让笔误隐形。

数字格式**与区域设置无关**，永远用 `.`（照 ECharts），这样同一份 option 文本在任何机器上
画出同一张图。

### 第 20 项随之落地

ECharts 6.1 把 `tooltip.valueFormatter` 的第二个参数从 **dataZoom 过滤后的下标**改成了
**原始输入数据的下标**（changelog 原文："changed from `dataIndex` ... to `rawDataIndex`"）。
参数记录**两个都带**。现在做免费；等用户代码里有句柄了再补这个区分，是最贵的那类迁移。
（第 20 项的另一半「`startValue` 独立于 `min`」在契约 spike 时就进 `TTyScale` 了。）

19 个测试，全量 **6600**。

### 变异测试：两条存活，一条修了一条如实记录

- **修了**：区域设置那条。断言 `'1234.5'` 在本来就用 `.` 的机器上**什么都没证明**——
  去掉代码里的锁定它照样绿。改成测试期间真的把小数分隔符换成逗号再断言。
  这是 `skin-variance-breaks-fixed-widths` 那一类：因本地巧合而通过。
- **如实记录**：系列下标越界的守卫。去掉它不会给出另一个答案，而是**读数组界外**——
  未定义行为，这次恰好长得一样。要让它可观测得开范围检查（全仓库没有一个单元开），
  或者把正确行为换成好测的行为。两个都不划算，所以在测试里写明这个界限。

### 阶段 2 余下

只剩第 6 项的 SynEdit 壳，**等第 3 项控件本体**。

---

## 17. Tier 0 第 8 项：列式数据存储（2026-09-02）

`source/tyControls.AdvChart.Data.pas`。23 种 series 里 20 种没有它就表达不了：
一条 candlestick 数据是五个数，boxplot 六个，radar 每个 indicator 一个，heatmap 三个。
比「N 维一点」窄的任何形状事后都要加宽，而加宽意味着回头改每一个照窄形状写的渲染器。
所以**从第一行起就是 N 维的**。

### 一种列类型，四种维度类型

每一列都是 `array of Double`，不管维度声明成什么。ECharts 用 `Int32Array` 存 `int` 和
`ordinal` 省内存，代价是一个 wart：**Int32Array 装不下 NaN**，所以 `int` 维度上缺失的值
悄悄变成 0 而不是空档。Double 能精确表示每一个 Int32 和每一个 ordinal 下标，多花的只是
每值四个字节——换来的是 **NaN 作为四种类型统一的、唯一的「无数据」写法**，这一层的契约
就建在它上面。维度类型因此只管**解析和解释，不管存储**。

四种不是 ECharts 的五种：它的 `number` 与 `float` 的区别只是「普通 JS 数组 vs 类型化数组」，
在这里没有意义。

### 两个下标空间

raw 下标指向原始输入行，永不变；data 下标指向当前过滤后的视图。dataZoom 动后者、前者不动——
**正是第 20 项的回调记录已经许诺的那一对**。过滤从不搬值，只建一个下标向量。

**故意偏离 ECharts**：ECharts 每次过滤都克隆 store、列按引用共享，因为 JS 里多条 series 读同一张
解析好的表。FPC 的动态数组虽然有引用计数，但**写元素不触发写时复制**，同样的把戏会让两个 store
别名到同一个缓冲区、一起写坏。所以这里是**原地过滤**：一个 store、一个下标向量、`RestoreAll` 撤销。
跨 series 共享解析结果是后面的问题，要单独的答案。

### 三条抄来的规则和三条故意不抄的

抄：
- **过滤保留 NaN**。ECharts 明写这不是疏忽——折线图在缺值处断开，丢掉那行会把口子合上、直接连过去。
- **ordinal 的文本原样收下**：`'-'` 和空串在类目轴上是**正经的类目名**，不是无数据
  （ECharts 对 ordinal 提前 return，在它的无数据规则之前）。
- **固定类目表上的数字是下标**（`xAxis.data` 给了表时），收集式类目表上的数字是**标签**
  （`[[2001, 12], [2002, 15]]` 里的年份是类目，不是下标）。

不抄：
- **越界的类目下标 → NaN**。ECharts 原样返回，点会画到轴外。空档诚实。
- **不合法的日期分量直接拒**（13 月、2 月 30 日）。JavaScript 会绕成下一年一月；空档能看出笔误，
  悄悄挪走一年不能。
- **`SetCategories` 必须在第一行数据之前调**，否则抛异常。ECharts 先填后原地重写整列，
  是因为它的 Model 层解析顺序它自己控制不了；我们控制得了（轴在 series 之前读），
  所以把重写换成一条规则——**没有强制的规则只是注释**。

### 逐点覆盖侧表

ECharts 的 `getItemModel` 把一条数据包进 `Model`，靠原型链回落到 series。这里没有原型链，
所以「设过」和「没设过」必须**显式**分开：`symbolSize: 0` 是一条真指令，不能用「不存在」表示，
而 NaN 也代替不了缺席的字符串或布尔。

实现是**天然稀疏**的：没有覆盖的行只占一个 Integer，什么都没覆盖的 store 一分不占。
键是全局驻留的整数（内层循环里比整数，设计期编辑器还能枚举可覆盖项）。

### 时间

epoch 毫秒，不是 `TDateTime`——因为 `TDateTime` 的 0 是一个合法日期，用它当哨兵就等于第二套机制。
解析实现 ECharts `TIME_REG` 的子集，**无时区标记按本地时间**（ECharts 的明确选择，故意不同于
JavaScript 自己的 Date 解析器）。

**如实写进单元头的一条限制**：本地换算用机器**当前**的 UTC 偏移，因为 FPC 3.2.2 不提供
「某个日期上的偏移」。跨夏令时切换的时间戳会差一小时。在意的数据应该自带时区标记。

### FPC 的一个坑（已进记忆）

`Round(x) * 1.0` 看着是「转成浮点」，实际不是：FPC 把无类型实常量 `1.0` 定为 **Single**，
整个乘法在 Single 里算，Int64 被砍成 24 位尾数。epoch 毫秒（约 2^40）每次最多丢 65536 ms。
测试报 `expected 1700000000000 but was 1700000038912` 才发现。已扫全仓库：现有的
`* 0.5` 之类左边都是浮点或小整数（像素、角度），不受影响——**这条只在量级超过 2^24 时咬人**。

### 变异测试

23 个变异，**22 个被杀，1 个存活且是等价变异**。

存活的是 `IndexOfRawIndex` 的恒等快路径（先猜 `indices[i] == i` 再二分）。去掉它答案完全一样，
只是慢一点——**纯优化，没有可断言的行为**。如实记下，不为它编一个测试。

**三条被逮到的真缺口，都是「测试写了但走的不是那条路」：**

1. **extent 的无穷守卫**。`TestExtentIgnoresInfinity` 早就在，但**没过滤的 store 根本走不到扫描循环**——
   增量维护的 raw extent 有它自己的守卫，变异没碰。改成在**第二个维度**上过滤，
   把 500 那行踢掉、两个无穷留在窗口里，才真的扫。
2. **extent 缓存的失效**。每个测试都是「过滤一次、读一次 extent」，这**分辨不出缓存是活是死**。
   补两个：换窗口后再读（读到新窗口而不是记住的那个），以及 log 的 `defPositive` 与普通 extent
   **各自的缓存槽互不串**（两种顺序都验）。
3. **短行补 NaN**。`AppendRow` 有两个重载，测试只用了数值那个。给另一个重载也加了变异——
   两个现在都被杀。

**顺带：变异脚本自己第一轮全废。** 22 个变异整整齐齐报 "NO-OP"，因为新文件还没 `git add`，
`git diff --quiet` 对未跟踪文件恒答「无变化」。看起来像脚本很严谨，实际一个都没跑。
改成**写完读回来跟原文比**，已补进 `crlf-mutation-phantom-survivor` 记忆。

63 个测试，全量 **6663**。

### 一件挂起的接线

`AdvChart.*` 十三个单元和 `tyControls.SubPixel` **都还不在 `tycontrols.lpk` 里**——
目前只有测试工程按单元路径直接编它们。这是有意的（包里还没有东西用得上它们），
但**第 3 项落控件本体时必须一起接上**，否则就是 `capability-built-but-not-wired` 那一类。

---

## 18. 第 13 项的调研结论：它单独交付不了；先补地基（2026-09-02）

三轮工作流（27 个 agent，约 450 万 token）读 ECharts 源码 + 攻我们自己的设计。**结论是把第 13 项
往后挪**，先补它依赖的地基。

### 三份独立设计收敛到同一条论点

「一条 series = 类型名 + 已解析的轴绑定 + 自己的数据存储」，而且**轴→series 的反向索引必须跟
正向绑定同批交付**——没有它，副轴画出来了、有刻度，**显示的却是主轴的数**。这正是第 13 项的
立项理由，三份设计各自独立得出。

### 但三份设计全被攻破，攻的过程钉死了真约束

| 约束 | 证据 |
|---|---|
| `TTyAxis` **没有身份** | `xAxisIndex` 是跨 grid 的**全局 option 下标**（`Grid.ts:441-455, 505, 591-592`），而 `ITyCoordSys.GetAxis(i)` 是系统内部的扁平下标。今天没有任何东西连接两者 |
| `DataToPoint`/`DataToLayout` **只认 master 对** | `Coord.pas:219-235, 264-273, 275-316`。绑到 `yAxisIndex:1` 的 series **根本映射不到像素** |
| 绑定**不是**「每个坐标维一个 `<组件>Index`」 | 只有 cartesian2d 与 singleAxis 直接点名轴；polar 只有一个 `polarIndex`，然后**反问系统要**它的 radius/angle 轴（`referHelper.ts:163-165`），parallel/matrix 同理。resolver 必须**两步** |
| ref 解析**必须按 `coordinateSystem` 设门** | `CoordinateSystem.ts:320-322`。不设门，一条 cartesian line 会解析出 `polarIndex:0`（目录里它的默认值就是 `0`）并**悄悄撑大 polar 轴范围** |
| 反向索引**必须带 key** | `axisStatistics.ts:407-417` 扁平 / `:428-444` keyed，桶 key 是 **(seriesType, coordSysType)**（`isBaseAxis` 只是**插入过滤器**，不在桶 key 里）。柱宽算法读 keyed 那张（`barGrid.ts:170-177`）；只有扁平表时，一条 line + 一条 bar 共用 x 轴会让**每根柱子宽度减半** |
| 目录的 per-type `coordinateSystem` **有 6 处与源码不符** | radar 无此节点（源码 `'radar'`）、graph 目录 `'none'`（源码 `'view'`）、tree/treemap/sankey 的 usage。**目录是文档真相，渲染器真相要手抄** |
| `xAxisId` 默认值是字面量 `undefined`、类型写成 `number` | **上游文档自己的 bug**（`coord-sys.md:199`），目录忠实转录。加漂移守卫时别去「修」目录 |

从源码逐行核出了 **23 种 series 的权威表**（默认坐标系、usage、渲染器**真正分支**的系统、维度、
是否需要 Graph/Tree 伴生结构）。两条值得单记：**scatter/effectScatter 的渲染器一个坐标系分支都
没有**（只要 `dimensions` + `dataToPoint`）；**bar 按选项字符串门控**，不认识就静默什么都不画。

### 第 13 项立不住的四件事

1. **没有任何东西从 option 读 `xAxis`/`yAxis`/`grid`**——全库 `TTyAxis.Create` 五处**全在测试里**
2. **没有类目 scale**，而带 `data` 的轴就是类目轴（见 §19 的更正：**`type` 没有 `'category'` 默认**，目录那条是上游文档 bug）；`BandWidth` 也只有测试写过
3. **类目表归属错了**：store 拥有它，而 ECharts 挂在轴上共享
4. **没有东西把 `series[i].data` 灌进 store**，且顺序被锁死：绑定 → 维度 → 类目 → 填充

### 已落地的地基（两个 commit）

**组件槽归一化**（`6d9988b8`）。`series: {...}` 写成裸对象会**静默产生 0 条 series、0 条诊断**——
`CountAt` 对非数组返回 0，而 ECharts 归一化成数组（`Global.ts:369`）。加的是 `ComponentCount`/
`ComponentAt` 一对**新**访问器而不是改 `CountAt`：已有测试钉着「对象不是数组」，而且归一化是
**组件槽**的规矩，不是树里每个数组的（`data: 5` 不该变成单元素数组）。

**类目 scale 与 band 几何**（`8314858a`）。`TTyOrdinalScale`；extent 是**闭区间**不是计数；三个
数字空间从第一行分开；**band 宽度改成派生**（像素范围一次布局写两遍，构造时缓存的第二次就馊）；
**半 band 内缩带符号不用 `Abs`**（竖轴 margin 为负，两端才都朝内收；写成 `Abs` 在所有横轴测试上
都对、所有竖轴上都错）；**类目表归轴所有、store 借用**。

顺带修了一个既有 bug：**有序比较遇 NaN 会抛 `EInvalidOp` 而不是答 False**（x86_64 的 `COMISD` 对
静默 NaN 发信号），于是对 `TyInvalidPointF` ——本库自己的「无答案」写法——做命中检测是**崩溃**
而不是未命中。

34 个新测试，全量 **6703**。变异 26 个杀 24，两个存活**都是死守卫**（`Count` 对空 scale 本来就答
0，`SetLength(x,0)` 本来就是空数组），已删。

### 阶段 3 余下

地基还差**轴/坐标系构建器**（从 option 读 `grid`/`xAxis`/`yAxis`，含 `gridIndex` 与多 grid）和
**option→store 的填充**（含「类目轴上的标量补全」：`data:[555,666,777]` 变成 `[[0,555],...]`，
这是网上几乎每个例子的形状）。之后才轮到第 13 项本体。

---

## 19. 轴/坐标系构建器（2026-09-02）

`source/tyControls.AdvChart.Builder.pas`。在它之前，**全仓库每一个 `TTyAxis` 都是测试构造的**——
scale 层、坐标层、盒求解器全都建好且正确，就是没有东西把它们和 option 树连起来。

### 三相，不是一相

像素范围**必须写两次**，这不是缺陷：

| 相 | 做什么 | 为什么在这个位置 |
|---|---|---|
| A 结构 | 读 grid/xAxis/yAxis，建 scale、轴、N×M 坐标系，按**原始** grid 矩形给一个近似像素范围 | dataZoom 滑块和柱布局都需要在任何数据范围存在**之前**就有像素范围 |
| B 范围 | 把绑定 series 的数据范围并进 value 轴 | 需要 series store，**跟 series 绑定一起交付** |
| C 像素 | 格式化刻度、量文字、按轴占用收缩 grid 矩形、写**最终**像素范围 | 标签占多少地方，量过才知道 |

B 相**故意缺席**：今天没有东西把 option 填进 store，并起来也是空的。A + C 已经可用——类目轴的
范围整个来自它的类目，A 相就知道。

### 目录在轴类型上是错的（本条最容易搞错的一点）

目录记 `xAxis.type` 默认 `'category'`。**运行时没有这个默认**：两个轴族跑同一条规则——

```
显式 type 优先（不校验）；否则带 `data` 键的是 category；其余都是 value
```

**裸 `xAxis: {}` 是 value 轴。** 类目轴常见是因为 `data` 常见，不是因为轴叫 x。目录忠实转录了
**上游文档的 bug**（`x-axis.md:53` 的 `axisTypeDefault`），同一个 bug 让它对 `angleAxis` 也错。
所以这条规则**手写，不查目录**。

**`data: []` 仍然是类目轴**——空数组在 JS 里为真。判 `Length(data) > 0` 会把「固定的空类目表」
静默变成 value 轴，而这两件事不一样。

**未知 type 上游直接抛异常**（组件类查不到）。抛异常对我们是错的：设计期编辑器每敲一键都渲染，
打到一半的 `cat` 会把图清空。我们**回落 value 并报诊断**——静默丢弃是三者里最差的。

### 其余从源码取的规则（文档都是过期的）

- grid 默认 **left 15% / top 65 / right 10% / bottom 80**（文档还写 60）。600×400 → `(90, 65, 540, 320)`
- **两个轴族都在**才合成默认 grid；只有一个就一个 grid 都不建
- 轴引用：**index 压过 id**；index 指不到任何 grid 就**落空**，不回退 id、也不回退 grid 0
- 侧边分配**只看 bottom / left 一个标志**，所以**第三根 x 轴也在上边**（靠 offset 叠）；标志**逐 grid 重置**；
  显式 position 也占用槽位
- 一个 grid 少了任一方向的轴，**整个 grid 一个坐标系都不建**——半个 cartesian 放不了点

`TTyCartesian2D` 加了 `OwnsAxes`：一个 grid 用 N+M 根轴撑起 N×M 个坐标系，同一根轴在好几个里面，
默认所有权会释放好几次。

### 变异测试

23 个**全部被杀**，其中三个存活项暴露的是真缺口：**没有任何测试写过百分比字符串**（默认值是直接
构造成百分比的，`'20%'` 那条解析路径无人走过）；**没有测过匹配不上的 `gridId`**（会静默落到 grid 0，
图照画且屏幕上分辨不出）；**显式 position 只测了 `'top'`**，而那走的是另一个分支。

32 个测试，全量 **6742**。

### 地基还差最后一件

**option → store 的填充**，含「类目轴上的标量补全」（`data:[555,666,777]` → `[[0,555],...]`，
网上几乎每个例子都是这个形状）。做完它，第 13 项才有立足点。

---

## 20. series.data 读进列式存储（2026-09-02）

地基的最后一件。**option 现在能一路走到轴、坐标系和填好的数据存储**，中间没有任何一步靠测试手工构造。

### 两个「看第一项」的决定，看的不是同一项

- **列数**从 `data[0]` **字面**读：前导 null 算标量，得 1
- **索引模式**从**第一个非 null 项**判断

在 `[null, [1,55], [2,66]]` 上两者**真的不一致**——列数说 1，索引模式说否。合并成一个会更整齐，
也会把行下标盖到真正的 x 值上。

### 行下标

`data: [120, 200, 150]` 配三个类目名能画出来，全靠它：**类目列填 0/1/2，数字进值列**。没有它，
这些数字会被当**类目名**去查，全部落空，图是空的——而这是网上最常见的一种写法。

**一个 series 一次决定**，所以混合数组里的元组行也拿行下标。

### 标量广播到每一列

`data: [5]` 在两根 value 轴上，x 和 y **都是 5**。看着像缺了个守卫，其实是上游行为——而唯一会
看出问题的场合（类目轴）正好被行下标接管了。

### 逐点覆盖按点分隔的叶子路径驻留

`emphasis.itemStyle.color` 而不是 `emphasis`，因为下游每个读取点都是**叶子读取**。这样不需要
「支持哪些键」的清单，嵌套的样式覆盖也只占一个槽。非标量叶子（渐变对象、虚线数组）**跳过而不是
存成无数据**——「不存在」和「存在但空」必须分得开，那正是这张表存在的理由。

### 变异测试逮到我自己的一条假绿测试

15 个变异杀 14。三个存活项里最值钱的是:`TestALeadingNullDoesNotTurnTuplesIntoIndexMode` 用的
fixture 是 `[null, [1,55], [2,66]]`——元组的 x 是 1、2,而**行下标恰好也是 1、2**。两个答案完全
重合,所以把索引模式打开它照样绿,**什么都没断言**。改成 x = 2 和 0(仍是合法类目下标、但与行下标
不同)才真的分得开。

另外两条:`time` 轴的列映射**没有任何测试**(去掉全绿,而一旦错了日期字符串会被当数字读、整条
series 全是空档);以及一个**等价变异**(null value 与无 value 的对象在本单元的单元格映射里都到
「无数据」),注释已改成不再声称那个分支承重。

顺带记了一条:**fpcunit 的 `AssertEquals` 拿到 NaN 是抛 `EInvalidOp`**,报「Invalid floating point
operation」而不是「expected X but was NaN」。在这种「NaN 就是无数据」的层里,这条报错完全不提
NaN,排查方向很容易跑偏。

14 个测试，全量 **6765**。

### 地基齐了

`option → 轴/坐标系 → 数据存储` 整条链路通了，第 13 项（series 注册表 + 轴绑定）现在有立足点：
它要的 `TTyAxis` 身份、`ITyCoordSys` 的实例、类目表共享、以及带 raw/data 两个下标空间的 store，
全部就位。

---

## 21. Tier 0 第 13 项：series 注册表与轴绑定（2026-09-03）

`source/tyControls.AdvChart.Series.pas`。立项理由「混合图表类型与副轴」现在**能演示**了。

### 构建器已经把头号难题解决了

早期审稿指出「`DataToPoint` 只认 master 对，所以副轴 series 映射不到像素」，并建议给绑定加一层
`ITyCoordSys` 视图。**结果不需要**：构建器的 N×M 交叉积里每个 `TTyCartesian2D` 恰好装一对轴，
所以绑到 `yAxisIndex:1` 的 series 拿到的坐标系，master 对**就是** (x0, y1)。绘制和命中走同一个
对象，天然不会分叉。绑定只是**查**，不是**建**。

### series 类型是数据，不是继承体系

类型**是什么**（默认坐标系、按轴布局还是塞进盒子、列叫什么）是表里的一条记录；只有**画**的那个
是类。两条理由都不是风格问题：**FPC 对 nil 类引用做虚类方法派发会 AV**，而 23 种类型里有 21 种
在有人写渲染器之前正是这个状态；而记录表是校验器和设计期编辑器**读得懂**的东西，一组被覆盖的
方法不是。

表**从源码手抄**——目录是文档真相，这 23 行里有 6 行它是错的。

### 反向索引的两套 population，而且互相不是你以为的那个子集

- **扁平**：每一对 (轴, series)，是**轴的范围**并集的来源。它**必须**看见挂在「bar 不以之为基准的
  那根轴」上的 line，否则那根轴根本没有范围
- **带 key**：按 (series 类型, 坐标系) 分桶，且**只收轴是该 series 基准轴的那些对**，是柱子**分带**的依据

只发扁平那张：一条 line 和一条 bar 共用 x 轴时 line 被当成 bar，**每根柱子宽度减半**，而图看着正常。
只发带 key 那张：value 轴拿不到范围。

### 基准轴按 `AxisType` 判，不按 scale 的类

**time 轴在这里也是 `TTyIntervalScale`**，所以按类判断会**静默跳过两条时间规则**，每张时间图都回落
到 x 轴——当时间恰好在 x 上时它是对的，一旦不在就错，而且看不出来。

### index/id 优先级抽成一个共享 helper

不在 series 绑定里再抄一份。两份必须一致的规则，正是这个仓库栽过的形状。

### 变异测试

19 个活变异**全部被杀**；第 20 个是一条**只是复述 `Associate` 自己 nil 检查**的守卫，已删（本会话
第三次删这类东西）。五个存活项里四个是真缺口，其中三个是同一个原因:**整个套件都走构建器，而它
恰好先加 x 再加 y**——于是按槽位取轴的写法全绿，直到有一条测试**先加 y 再加 x** 才照出来。

28 个测试，全量 **6793**。

### 阶段 3 余下

第 16 项四态样式、第 17 项样式解析、第 18 项主题令牌（要跨 17 套皮肤验）。之后是阶段 4 的第 3 项
控件本体 + 真机复验，再回头补第 6 项的 SynEdit 壳。

---

## 22. Tier 0 第 16 / 17 / 18 项：状态、样式解析、主题令牌（2026-09-03）

**阶段 3 到此全部完成。**

### 第 16 + 17 项合做（`AdvChart.Style.pas`）

状态模型没有值可解析就没法测，解析器没有状态可解析就没事可做。

**四态不是一个四值枚举，是两个正交的槽**——spec 原来的写法有误导。emphasis 与 blur 共用一个槽、
互斥；**select 是独立的一个**，能和另外两个同时成立（一根既被选中又被悬停的柱子同时处于两态）。
normal 不是谁「进入」的状态，是两个槽都空。

**「进入」无守卫、「离开」有守卫。** 离开 emphasis 只在槽里确实是 emphasis 时才清。这是
「先把整条 series 压暗、再高亮悬停项」能对的**全部机制**——没有它，一次悬停离开会把同一趟压暗的
每个元素都点亮。

**emphasis 是引用计数的**，一个 source 一位：图例悬停和轴指示器联动可以同时持有同一个元素。
**鼠标不占位**，且只在掩码为空时生效——所以 API 高亮压过指针，指针也释放不掉它。

**而「有覆盖用覆盖、没有用 series 的」这条规则只对 normal 正确。** 对另外三态错，且每一处都看得见：
- **没写样式的 emphasis 不是「没样式」,是把正常色提亮**——库里每根柱子、每块饼、每个散点的默认悬停外观
- **blur 的透明度是算出来的**(正常值 × 0.1),不是查出来的,否则绝大多数没声明透明度的元素根本不会变暗
- **z 提升来自任何 option 路径之外**——等着在 option 树里找它的移植永远找不到
- **fill 优先于 stroke 提亮,且绝不同时**——形体和轮廓一起变亮读起来是「换了个颜色」而不是「高亮」

反直觉的一点:那个函数叫 `lift`、参数是**负**的 −0.1、效果是**变亮**。名字和符号都指向反方向,
所以有一条测试专门钉方向。

31 个测试,变异 **25/25 全杀**。两个存活项是我的测试因为错误的理由通过:元素已在 emphasis 时
「按鼠标进入」与「不进入」结果分不开(守卫只在被持有期间又被压暗时才显形);以及只断言越界 source
「能通过 bit 0 释放」——它**压根没注册任何位**时这条也成立。

### 第 18 项（`themes/light.tycss` + 三个生成器）

八个 typeKey 加四个度量,**数量本身是设计的一部分**:十二样东西能跨十七套主题用眼睛过一遍,
六十四样不能。

颜色**全部从主题已有的语义令牌派生**。分隔线和次刻度是 `alpha(var(--border), ...)`——
**绝不是 `alpha(--surface, ...)`**:图片主题上半透明的表面会读成亮白光晕而不是淡线,这个 bug
本库已经发过一次。

**跨皮肤测试一开始是假绿的,变异证明了。** 它断言「轴线跟表面区分得开」——真的,但不是要紧的那件事:
硬编码 spec 点名警告的那个灰 `#b7b9be` **通不过**这条断言,因为中灰跟浅底、深底**都**区分得开。
改成断言**派生关系**:轴线、次刻度、分隔线同出于 `--border`,**色相必须相同、只有 alpha 不同**。
拿同一个变异再跑,第一套主题就红。

`Css.Catalog` 188→192 个令牌、197→205 个 typeKey;`BuiltinThemeData` **零变化**——皮肤是基座之上的
增量,新键全部被继承。

全量 **6825**。

### Tier 0 余下

只剩**阶段 4 的第 3 项**:窗口化控件本体 + Win32/GTK/Qt 真机复验,然后回头补第 6 项的 SynEdit 壳。
前面十九项全部完成。

## 23. Tier 0 第 3 项：窗口化控件本体（2026-09-03）

### 控件在绘制路径上没有自己的行为，这就是这一项的答案

规格给这一项点了四个仓库老坑：阴影糊角、擦除到父 `Color`、窗口化兄弟裁剪、吞掉 `CM_*`。
四个的答案是同一句：**控件不自己做这件事**。

- 一次 `DrawFrame` 把父背景、不透明度、阴影、背景、边框、以及一个不许投阴影的窗口化控件自己补的角，
  一起画掉。**但补角是有条件的**：`TyFillParentBg` 打底、`FillCornerGaps` 还要求「有阴影」加
  「`TyResolveParentBg` 拿得到父背景色」。**孤儿控件两条都不满足**——这正是下面那条假绿暴露出来的。
- 文字全部走 `APainter.MeasureText` / `DrawText`。空字体名由 `TyEffectiveFontName` 兜底、小号字的
  超采样由 painter 按平台开——控件一行都不用写，也就一行都不会写错。
- **一个 `CM_` / `WM_` 重写都没有。** 所以「重写了不调 `inherited`、把 LCL 那层吞掉」这个坑不可能发生，
  而且它是**靠没有代码证明的**，比靠一条测试证明硬。

### 护栏替我做了分类，而且推翻了我的第一次分类

加一句 `RegisterComponents` 就有三条测试变红，每条问的都是我没主动想过的问题——而修好之后又有两条变红。

- **面板图标**不是「画没画」而是「`.lrs` 里有没有」。glyph 加在 `genicons.lpr`、类名清单在
  `gen-icons.ps1`，**两处**；而且 `Glyphs` 是定长数组，加一项不改上界，报的是
  「`)` expected but `,` found」并且指在错误的行上。
- **`test.version` 的 `Reg()`**：注册了但这条测试够不着，等于版本表里查无此人。
- **tab-stop 表**：一个窗口化 `TTy` 类必须落在两张表之一，好让 `TabStop` 的默认值是有人写下来的决定。
  顺带把 `TTyChart` **两张表都不在也是对的**记在了注释里——它是图形控件，这两张表只收窗口化类。

**而填这张表的第一次尝试是错的，另外两条测试当场证明了。** 我把 `TTyAdvanceChart` 归进「容器与
外壳」，但构造函数里写着 `TabStop := True`——**分类和代码互相矛盾**，我按它今天画什么分的类，
没按它构造成什么。两条断言从两个方向指出来：一条说这个实例不该是 tab stop，另一条说
RTTI 的 `default`（0）跟构造出来的值（1）对不上。

后面这条才是要害：**流式化会省略等于声明默认值的属性**，所以声明和构造不一致时，`.lfm` 里写的
`TabStop=False` 会被当成「就是默认值」而不写出去，加载后仍是 True——**这个文件存在的全部理由**。

最后按那张表**自己的判据**定：「用户操作的控件：点击落焦点、Tab 够得到，且自己处理按键或点击
直接改值」。这个控件今天两条都不满足，而**一个不处理键盘却在点击时抢走焦点的控件**，正是外壳表
注释里描述的那种伤害。所以 `TabStop := False` + `property TabStop default False`，留在外壳表。
**窗口化让焦点将来成为可能，不等于现在就该拿。** dataZoom / brush / 键盘 tooltip 落地那天它翻成
True 并换表，而这两张表会逼着人**明确决定**而不是漂移过去。

### 只有真机渲染看得见的那个 bug

headless 断言「轴画出来了」的方式是数非背景像素。y 轴有 5 条刻度加 4 条分隔线，几百个像素，
**标签一个字不画照样绿**。

真机渲染一眼就看见：y 轴有刻度、没有数字。`PaintAxis` 只给 `TTyOrdinalScale` 画标签——
category 轴标自己的类目、value 轴标自己的刻度值，我只写了前一半。

改这行时还栽了一跤：替换模式漏掉中间一行 `lblH := ...`，断言失败、整个脚本回滚，我却当成已改，
于是连着两次「全量重编」编的都是同一份源码。**PNG 字节数一模一样不是「没生效」，是「根本没改」**——
前者会让人去查链接顺序，后者只要 `grep` 一下新符号在不在文件里。

### 顺手改对的一件事：分隔线不该画在标签上

`TickCoords` 的 `AAlignWithLabel` 参数存在的唯一理由就是区分这两者，而分隔线那次调用传的是 `True`。

量出来的：两根轴在 x=102 和 x=437，分隔线落在 135.5 / 202.5 / 269.5 / 336.5 / 403.5，是 band **中心**。
改成默认之后是 102 / 169 / 236 / 303 / 370 / 437，正好 5 个 band 的**边界**，两端与轴线重合。

（ECharts 里 category 轴的 `splitLine.show` 默认 `false`、value 轴才 `true`。这条属于后面的轴渲染项，
不在本项范围内，先记在这里。）

### 我自己破掉的一条约定

运行期字符串在本库只有 `tyControls.StrConsts` 一个家——`grep -l '^resourcestring' source/*.pas`
一行就能证明。AdvChart 的两个单元各自开了 `resourcestring`，于是多出两个 `.pot`。
挪回 `StrConsts`、`implementation` 段 `uses`，跟 `TTyCalendar` 一样。
example 的两份 `.po` 也按其他 example 的样子补齐了（97 份全过 lint）。

### 两件小的，但都是同一类

**我写的 `TyChartTickText` 跟 `AdvChart.Handlers` 里的 `TyChartNumToStr` 一字不差。**
删掉用现成的——同一件事有两个写法，第二个迟早跟第一个不一样。

**三个新文件的行尾是混的**，`test.advancechart.pas` 一度是 58 个 CRLF 加 266 个 LF。
它的直接后果是变异脚本的模式**有的命中有的不命中**——跟
[[crlf-mutation-phantom-survivor]] 记的是同一个陷阱，只是这回反过来：不是 LF 串搜 CRLF 文件，
是同一个文件里两种行尾都有。全部归一成 CRLF（仓库里 `.pas` 一律 CRLF，`.gitattributes`
只对 `*.sh` 和 `*.ps1` 有规定）。

### 没做的那一半：GTK / Qt 真机

这一项的名字里就写着 Win32/GTK/Qt，我手上只有 Windows。Win32 那半的证据是上面那张渲染。
**Linux 那半没做**，清单如下，每条都对应一个本库真栽过的坑：

1. `gtk2` / `qt5` / `qt6` 三个 widgetset 各编一遍 `examples/advchart`。
2. **图表客户区不是黑块。** 非合成 blit 的离屏 32 位缓存在 GTK2 上 alpha 平面会整片是 0。
3. **轴标签的小字不糊。** 小号字在 Linux/macOS 上发虚是修过的老问题，走 painter 的超采样路径。
4. 换肤 + 明暗切换后，轴的八个 typeKey 全跟着变。**Win32 上有像素证据**：example 的 `--shot`
   收了主题名和明暗参数，`win11/dark` 出深底浅轴线、`xp/light` 出米色底暖网格。留在清单上是因为
   主题解析和绘制是两件事，Linux 上文字和线宽走的是另一条路径。
   （顺带：`material` 这个名字根本不存在，真名是 `material3`。错名**不报错**，而且这是有意的——
   `SetThemeName` 允许名字尚未注册，`ThemeRegistryChanged` 会在它出现时重试。代价是打错字
   没有任何反馈：我是靠那张 PNG 跟默认主题那张**字节数一模一样**才发现的。）
5. 150% / 200% 缩放下刻度线仍是 1px——`ScaleF` 而不是 `Scale`，就是为了不让它变成 2px。
6. 把图表和另一个**窗口化**控件摆成重叠：句柄咬平的那块 `RenderTo` 看不见。
7. `SaveToPng` 存出来的 PNG 不是全透明。**这是控件唯一一段不走共享绘制路径的代码**
   （`TBGRABitmap.Canvas` → `TBitmapTracker.Changed` → `NotifyBitmapChange`，Win32 上验过是自动的）。
8. 设计期：Lazarus 里从面板拖一个下来，图标在、且不报 Cannot read property。

### 金丝雀存活，而它揪出的是真洞不是坏脚手架

变异跑出来「整个 frame 不画」**存活**，我第一反应是脚手架坏了（为省时间去掉了 `-B`）。
错了——同一轮里另一个变异体**被杀了**，证明构建是生效的。

真因是这套测试的**画布本身**：`Draw` 把位图预填成 `BGRAWhite`，而

1. **light 主题的图表表面就是纯白**，跟底色分不开；
2. **BGRABitmap 在用完 `.Canvas` 之后会对整张位图做 alpha 校正**，把所有 alpha=0 的像素设成 255。

于是 `p.alpha = 255` 这个断言**永远成立**，跟控件画没画毫无关系。
`TestAnEmptyChartStillPaintsItsSurface` 和 `TestEveryCornerIsPainted` **两条都是彻底空转的**——
一个什么都不画的控件照样全绿。而它俩的注释里还写着「在白底上看不见，所以要查 alpha」,
**注释把理由写对了、代码把结论写反了**。

改成画在**哨兵色**（品红，本库任何主题都不产生）上，断言「这里不是哨兵色」。改完立刻红：
**角 0 从来没被画过。**

而这一条又暴露第二件事：`DrawFrame` 第一步是 `TyFillParentBg`，补角还额外要求
`TyResolveParentBg` 成功——**没有父控件就没有父背景色可填**。测试里的控件是
`Create(nil)` 的孤儿，而 `.lfm` 造不出这种控件（真机渲染四个角都是父背景色：浅色 245、深色 32）。
按仓库既有做法（`test.base.drawframe.pas`）给它一个真窗体做父控件后全绿——
**这次的绿是有内容的绿。**

教训不是「金丝雀救了脚手架」，是**金丝雀必须必然致命**。「frame 不画」在这套测试下并不致命，
所以它没法替脚手架作证。换成「控件报错误的 typeKey」——这个不可能漏。

### 变异证明：我为这次改动新写的测试，没有一条抓得住它要抓的东西

九个变异体，第一轮只杀掉三个。**存活的里面有三个是我专门写测试去钉的**——分隔线位置、
值轴标签、resize 重排。三条的假绿机制**各不相同**，而且都不是「写得不够细」：

**① 扫描窗口把被测对象之外的东西算了进去。** 值轴标签那条数「y 轴左侧空槽里的墨」，
但窗口从 x=0 开始——**控件自己的边框和圆角就是 926 个墨点，标签只有 184 个**。
阈值 `ink > 20` 由边框独自满足。改成从 `x0 = 空槽 - 45` 起扫、并按 y 分成「墨带」计数
（一条刻度一带、每带中心要对上刻度的 y）之后，又冒出第二个同类问题：
**竖直扫描条穿过了控件的上下边框**，四个刻度数出六条带，多的两条在 y=0 和 y=298。
把 y 也收进绘图区才干净。

**② 参考色的取样点，正好是变异体要画的地方。** 分隔线那条在 `left + band div 2` 取底色——
**而半个 band 正是「对齐标签」那种画法的落点**。变异体一上去，取样点就落在线上，
于是「与底色不同」的判断整个反过来：绘图区底色全成了墨，扫描每 3 px 记一列，
`want` 附近永远找得到列，断言照过。改成取四分之一 band（两种画法都不落在那儿），
并**断言线的条数**——四个 band 的正确答案是 5 条（两端与轴线重合），
画在中心则是 4 条中心线加 2 条轴线共 6 条，光数数就能分开。

**③ 被变异的那行，在测试走的路径上根本到不了。** `RenderTo` 里那句
`FDirty or (矩形变了)`，测试是靠 `Draw` 改尺寸触发的，而 `SetBounds → Resize` 已经把
`FDirty` 置位了——矩形比较那半句**从来没被用到**。它守的是另一条路：
**不改控件边界、直接用不同矩形调 `RenderTo`**。补了一条那样的断言。

另外两个存活（「刻度线从不绘制」「最后一个刻度不标」）说明整套测试里**没有一条看得见刻度线本身**——
轴线、分隔线、标签加起来就把每个像素计数喂饱了。新增一条只看「轴线外侧那条窄带」的测试——
**而它第一版还是同一个错误**：带子从 `left-6` 起、只要「超过 8 个墨点」，
而**轴线自己的抗锯齿沿整个绘图高度铺开**，足够喂饱它，刻度全删掉照样绿。
收到 `left-5 … left-3` 并改成数**墨带条数 = 刻度条数**才真的钉住。

**这一段的教训不是「要多写测试」，是：断言之前先问「除了我要测的东西，这个窗口里还有什么」。**
四次假绿，四次都是这个问题——控件边框、控件上下边框、取样点落在被测物上、轴线的抗锯齿。

**顺带**：我的补丁脚本在这个测试文件里造了 32 处 `
`（`
→
` 转了两次，
调用方转一遍、`sub` 又转一遍）。FPC 照编照跑，`cat -A` 也几乎看不出，但后续任何模式匹配
都会在那一行断掉——症状是「这段文字明明一模一样，`count` 却是 0」。见
[[crlf-mutation-phantom-survivor]]。

改完之后 **9 个变异全部被杀**（第一轮 3/9）。

**然后全量又红了一条：单跑绿、全量红。** 刻度线那条数出 0 而不是 4——
测试在读**进程级的 `TyDefaultController`**，于是「跑在它前面的是哪个用例」变成了隐含输入：
某套皮肤下轴刻度解析不出边框色，就什么都不画。这一组每一条断言都是关于像素的，
**主题就是输入，得归测试所有**。按仓库既有做法（`test.badge.pas`）给控件挂了自建的
`TTyStyleController`，钉死 `default` + `light`。

另外两条新测试（标签、分隔线）本来吃同一个亏，只是这次的执行顺序没撞上。

### 全量 6837，零失败。

## 24. Tier 0 收尾审计：三个 bug 在「已完成」的代码里（2026-09-03）

第 3 项提交之后做了一次并行审计（四个独立审计员按 spec 逐项核代码，外加一个专找漏judgment
的批评者）。**三个真 bug 在被标成「完成」的代码里**，没有任何一条测试看得见它们。

### ① 布局用一套字体量，绘制用另一套画

`Builder.FillSpec` 写死 `FontSizeLogical := 12`、`FontWeight := 400`，`FontName` **根本没赋值**；
同一段里 `8 / 5 / 15` 三个数字正是主题的 `--advchart-label-margin` / `--advchart-tick-length` /
`--advchart-name-gap`，被抄成了字面量。

而绘制端用的是主题解析出来的 `TyAdvChartAxisLabel`。**绘图矩形是按量出来的标签尺寸收缩的**，
所以换一套标签字号更大的皮肤，矩形按 12pt 算、字按皮肤画 —— 标签会溢出它自己挣来的空间。

这**直接违反仓库硬规则**「视觉值必须走主题 token，绝不硬编码在控件代码里」
（[[theme-customizability-principle]]），而且它躲过了所有测试，因为测试用的是假度量器，
量什么字体都一样。

修法：`Layout.pas` 新增 `TTyAxisTextStyle`，由**控件**解析主题后传进 `TyLayoutGrids`。
**纯布局层里不提供默认值** —— 一个默认值就是把同样的硬编码往下挪一层；测试自己声明它拿什么量。

### ② 同一个刻度值，两端用不同的数字格式化器

布局 `FloatToStr(ticks[q].Value)`（**跟随机器区域设置**），绘制 `TyChartNumToStr`（强制 `.`）。
逗号小数点的机器上，量出来的宽度和画出来的字不是同一个字符串。
Builder 里本来就有一个 `NumText` 跟绘制端一字不差，改一行就完。

### ③ `show: false` 只让轴变薄，照样画

全库 `'show'` 只有一处被读（`Builder.pas`），喂给 `ASpec.ShowLabels`，而它只影响
`TyAxisThickness` 预留的厚度。于是关掉一根轴，**绘图区确实变宽了**（看起来生效了），
**线、刻度、标签、分隔线一个不少**。

修法：`TTyAxis.Visible`（默认 True，跟上游一致），`PaintAxis` 早退。
**轴仍然参与构建** —— 绑在它上面的 series 照样有范围和坐标，只是不画。
新增测试断言两根轴都隐藏后，绘图区里**零个非背景像素**。

### ④ 十一条诊断是硬编码英文

`Builder.pas` 5 处 + `Series.pas` 6 处 `Note(...)` 全是英文字面量，而这些文字**会直接显示给用户**
（控件的诊断列表，以及将来设计期编辑器的警告栏）。上一轮刚把两条串挪进 `StrConsts`，
**却漏了这十一条** —— 因为它们不长得像「界面文字」。挪进 `StrConsts`、`implementation` 段 `uses`、
补齐 zh_CN。

顺带一个操作上的坑：**`.pot` 是 package 构建生成的，不是测试项目构建生成的**。
只编 `tests/tytests.lpi` 就跑全量，会被 `TestEveryStrConstsResourcestringIsInThePot` 拦下——
加了 resourcestring 必须先 `lazbuild tycontrols.lpk` 一次。

### 教训

**「测试全绿」和「按 spec 做完了」是两件事。** 这三个 bug 全都在有测试覆盖的代码里，
而且第 ① 个恰恰**因为**测试用假度量器才躲过去 —— 假度量器让布局断言能写成精确数值（这是当初
正确的设计决定），代价是它对「量的是哪套字体」完全无感。

按 spec 逐项核代码，是测试替代不了的一道关。

## 25. 「解析失败保留上一份」被推翻（2026-09-03，用户拍板）

写第 6 项的第一步时我照着 §13 记的行为决定做，用户当场质疑：
「确定就提示解析失败，可能白屏啊，为啥要存上一份正确的，白屏就白屏呗」。

**他是对的，而且我是照着一个已经不成立的前提在做。**

§13 那条的理由原话是「设计期编辑器里每敲一个字符都可能暂时不合法」。
可几个小时前刚定稿的编辑器设计是**照 CSS 编辑器的模态对话框**：文本活在 SynEdit 里，
**按确定才写回属性**。Object Inspector 同理，回车提交一次。
**半成品文本根本不会到达控件** —— 闪烁这个代价从来不会发生。

剩下的就只有代价了：**控件在说谎**。属性里存着 A，画面上画着 B，屏幕上没有任何东西说明这件事。
设计期反而更糟 —— 你改完看图没变，第一反应是「我的改动没生效」，而不是「我写错了」。
一张空图配一条错误信息，是**更强**的信号，不是更弱的。

现在的规则：

- `TTyChartOption.SetOptionText` 失败 → **释放树**（`FreeAndNil(FRoot)`），`Error` 说明原因。
  下游访问器本来就全部 nil 安全（`Find` / `ComponentCount` / `ComponentAt` 都先判 `FRoot = nil`）。
- 控件仍然**读回你写进去的文本**（第 24 节那个 round-trip 修复照旧）——
  这两件事方向相反是对的：**文本归宿主，树归解析器**，`OptionError` 是它们之间的桥。
- 「确定」按钮**不拦**（也是用户拍板）：编辑器是编辑器，不是关卡。粘一段带 `function` 的
  ECharts 配置能先存下来慢慢改。

### 这条教训

**一条被写进文档的决定，它的理由可能比它本身先过期。** §13 那条当时是对的；
让它变错的不是它自己，是三个月后**另一个决定**（编辑器做成模态的）抽掉了它的地基。
文档记了「决定是什么」和「为什么」，但没有任何机制在「为什么」失效时提醒我们回头看。

实际做法上：**照着自己写的 spec 实现时，先验一遍它给的理由今天还成不成立**，
而不是只把结论抄进代码。

## 26. 第 6 项第 3 步：`AdvChart.Locate`，以及「夹具比断言重要」的第三次（2026-09-03）

正向扫描器：把 `series[0].itemStyle.color` 这样的路径变成文本里的行列，
好让只知道路径的诊断能变成一个可以跳过去的光标位置。是隔壁 `TyOptContextAt` 的对偶。

**为什么不复用同一个扫描器。** 方向不同只是表面。真正的分歧是**数组下标**：
反向扫描器**故意不数元素**（它的注释说得对——`series[3]` 里哪些 option 合法，
跟 `series[0]` 里是同一个问题），而运行期路径里**下标就是答案本身**。
两者必须一致的只有词法（引号、转义、注释），那部分是**有意复制**的：
19 条测试钉着反向扫描器，为统一而重开它不划算。

### 写完之后并行核查，在草稿里挖出四个真 bug

写之前起了一个事实核查工作流（四个独立读者按主题读源码 + 一个批评者）。
它读到了我已经写好的草稿，于是变成了一次评审。**四个真 bug，一个设计缝。**

**① 我那条转义测试根本没钉住转义。** 夹具是 `text: 'a ' b: c'`——
把转义规则从扫描器里删掉，**输出一个字不变**。因为字符串被提前闭合后，
残余落在一个 `ExpectKey` 早已被前面冒号清掉的帧里，两种情况都不发射。
**一条存在理由就是「防止复制来的规则腐烂」的测试，自己是假绿的。**
真正致命的夹具要在字符串里放一个**逗号**，把帧推回键位置：
`{ a: 'x ' , b: 2', c: 3 }` 开着转义得 `a c`、关掉得 `a b`。

**② 转义吃掉换行时不计行。** 之后每个键行号偏低，而且列号还从错的行首量起——
编辑器会**自信地跳到错的地方**，比找不到更糟。三种换行拼法里只有 CRLF 侥幸正确。

**③ `'.'` 被当成名字字符。** `{ a.b: 1 }` 产出单个路径 `a.b`，
与嵌套的拼法直接冲突，而且 fcl-json 根本解析不了它。
**名字字符集的权威是 fcl-json，不是隔壁那个更宽松的扫描器**——
只有它能解析的键才可能出现在一条诊断里。

**④ 不以名字字符开头的 token 被从中间切入。** `5x` 报出键 `x`、`-foo` 报出 `foo`，
位置差几列：**一个没人写过的键，指着差不多的地方。**

**⑤ 设计缝：同一段文本，两个生产者拼法不同。** `xAxis: { type: ... }` 是裸对象，
构建器按 `ComponentCount`（对裸对象返回 1）循环，诊断说 `xAxis[0].type`；
`TyOptValidate` 按树走，说 `xAxis.type`；**文本里两个下标都没有**。
最近前缀回退原本会一路退过真正存在的那个键、落到容器上——正好错过消息说的那个东西。
现在回退会额外试一次去掉 `[0]` 的拼法（只去 `[0]`：`[3]` 说的是真数组）。

### 顺带钉住的一件反直觉的事

**数组元素不是键。** `series[0]` 是个位置，没人给它敲过名字，所以扫描器不为它产出条目，
最近前缀回退**直接跨过它**落到 `series`。十一条诊断里有八条正是这个形状，
所以对多数真实输入而言，**干活的其实是回退而不是精确匹配**。

### 第三次撞上同一条

**断言之前先问：这个夹具里，除了我要测的东西，还有什么在起作用。**
前两次是像素窗口里混进了控件边框和轴线抗锯齿；这次是字符串闭合后残余落在一个
早已不接受键的帧里——**所以删掉规则也看不出差别**。
见 [[headless-render-needs-sentinel-ground]]。

### 变异 16/16，而两个存活者都是夹具问题

第一轮 14/16。两个存活的**都不是代码 bug**，都是**夹具让被测的差异消失了**：

**「带引号的键的列号」在第 1 行上不可见。** `lineStart = 1` 时，
「从文档头算」和「从行首算」**数值相同**——夹具放在第一行，等于把被测的那个减法恰好消掉。
跟前面「参考色取样点落在被测物上」是同一族。

**「值不当键」的守卫已经大部分冗余了。** 改成按冒号发射之后，一个值即使被 held 住，
后面没有冒号就不会发射，所以在**良构**文档里守卫无事可做。它还剩下的用处只有畸形输入
（`a: b: 1` 里只有 `a` 是键）。这里变异测试给的不是「发现 bug」，
而是**「这段代码现在还买到了什么」**——答案写进了测试注释，并补了那个用例，
**而不是删掉守卫**：容错扫描器天天见畸形输入。

## 27. 第 6 项第 4 步：`AdvChart.Diagnose`，与一次 40 个 agent 的对抗性评审（2026-09-04）

`TyOptDiagnose(text)` 把整个编辑器的分析压成一次调用：什么算问题、按什么顺序、用什么措辞、指向哪里。
**对话框只负责把列表放进框。** 理由还是那条——`designtime/` 不在测试构建里，
在那里做的判断天生没人看着。

### 评审确认 33 条（3 条被反驳），其中三条 high 全在已提交的代码里

**① `StrIn` / `StrOf` 读到数组或对象会抛异常。** 它的两个兄弟 `BoolIn`、`IntIn` 都检查类型并回退，
只有它没有；`Option.pas` 里早有正确写法。`{ xAxis: { name: [1] } }` 是合法 JSON、
是编辑到一半的正常状态，而它让 `TyOptDiagnose` 直接抛出。

**而这个 bug 的代价比"值算错了"大得多**：异常发生在 `TyBuildGrids` **返回之前**，
所以调用方的 `build` 局部**从没被赋值**，那句 `try..finally build.Free` 根本没进去——
**整个 build 泄漏**，外加一个正在构造的 `TTyAxis`。正是那段注释声称在防的东西。

顺带一个讽刺：`Builder.pas` 里有一条注释在论证「ECharts 在这里抛异常……抛异常对我们是错的，
设计期编辑器每敲一个字都要渲染」——**就写在那个会抛异常的调用上方**。

**② 裸对象形式的联合体，每个键都被报成未知选项**，包括 `type` 自己。
而 `series: { type: 'bar', ... }` 这种裸对象正是 ECharts 文档里到处在写的形式。
`TTyChartOption.ComponentAt` 早就把两种形式归一了，`TyOptValidate` 没有。

**③ 数组形式 `xAxis: [{...}]` 整个子树不校验。** 没有 `[]` 边不等于没东西可查——
多组件选项（xAxis/yAxis/grid）把属性直接挂在自己身上，schema 描述一根轴、允许你写一个列表。
于是里面写错字，编辑器报**「一切正常」**。

### 我这个新单元的四类

- **契约写着「永不抛异常」，却没有一个 `except`。** 承诺得靠强制而不是靠声明。
- **「一切正常」那句对饼图撒谎**（说「画出坐标轴」，而饼图没有轴），
  而且**对没有 series 的合法配置完全沉默**——正是这一行被发明出来要防的那种沉默。
- **同一个问题被两个生产者各报一次**（未定型 series）。两行说同一件事，是诊断列表开始没人读的方式。
- **行数无上界**（一个数据点一行），**列表不按文本顺序**（三趟拼接、从没排序）。

### 五条假绿测试，五种不同的"分不开"

| 原断言 | 为什么分不开 |
|---|---|
| 拼错指向第 3 行 | `axisLabel` 和 `colour` **都在第 3 行**，落到容器上一样满足 |
| `d.Line > 0` | 回退到容器一样满足——而 `[0]` 剥离的全部意义就是**不要**回退 |
| 消息里有 `middle` 和 `bottom` | 把「写了什么」和「允许什么」**对调**，两个词照样都在 |
| 解析错误 `d.Line > 0` | 错误在第 1 行，「传上来的位置」和「凭空编的 1」**数值相同** |
| 消息里有 `series` | 十一条构建消息里**五条**都含这个词 |

最后一条尤其典型：它的名字是「构建问题被报告**并定位**」，而它**关于定位一个字都没断言**。

### 顺带被红出来的一条真相

新写的「解析错误位置」测试要求一个列号，红了——去查才发现**列号是从 fpjson 的消息文本里刮出来的**，
而那条消息对这类失败只给行、不给 `Pos`。我原来的断言是在要求解析器承诺它并没承诺的东西。
改成只钉行号（编辑器跳转真正需要的那个），并把这个限制写进注释。

### 这类评审能找到什么，是我自己找不到的

两类，都不是"再读一遍代码"能补上的：

**跨文件的因果链。** `StrIn` 少一个类型检查 → 抛异常 → 异常在函数返回**之前** →
调用方局部从没赋值 → `try..finally` 没进去 → 泄漏。串起这条链要同时读懂三个单元加 fpjson 的实现。

**"这句话是不是真的"。** `rsTyOptDiagNothingPaintsYet` 承诺"画出坐标轴"，而饼图没有轴。
这不是代码 bug，是**一句会被印在对话框里的谎话**——没有任何测试形状能覆盖它，
只能有人去读那句话本身、再去查它对每一种输入成不成立。

## 28. 第 6 项第 7–9 步：守卫、壳，以及一条自己抓住自己的规则（2026-09-04）

### 第 7 步：守住那个「本机永远看不见」的方向

新加的 `source/` 或 `designtime/` 单元**不进 `.lpk` 也照样编得过**——Lazarus 靠目录搜索路径
找到它。没有编译错误、没有测试变红、没有警告，它只是**从安装出来的包和每一个发布归档里消失**。

仓库原有的 `EveryFileThePackagesNameIsShipped` 是**走清单问磁盘**（「这个条目对应的文件在吗」），
抓的是删文件忘删条目。真正会发生的是反方向，而**没有任何东西检查它**。
新增 `EveryUnitOnDiskIsListedInItsPackage` 走磁盘问清单，两个方向才齐。

这一层一个下午手工加了三个 `<Item>`。三次全对是运气。见
[[new-unit-missing-from-lpk]]。

### 第 8 步：壳的形状就是前七步的论点

约 630 行，通篇**找不到一个判断**：

| 事件 | 委托给 |
|---|---|
| 该补全什么 | `TyOptCompletionsAt` / `TyOptVariantHelpAt` |
| 补全插入什么、光标退几格 | `TyOptCompletionInsert` |
| 状态栏显示什么 | `TyOptStatusAt` |
| 有什么问题、指哪儿 | `TyOptDiagnose` |
| 树里双击插入什么 | `TyOptTreeInsert` |
| 光标前是哪一段文本 | `TyOptSliceBefore` |

三处直接照仓库记忆写、没有重新论证：底部控件**反着创建**
（[[lcl-code-created-align-order]]）、读 `LogicalCaretXY` **不读 `CaretXY`**
（屏幕列 vs 字节偏移，而切片按字节——在一个 demo 里到处写中文标签的库里，这是「什么时候」
而不是「会不会」）、`.lrs` 只能包含在过程体里（[[lrs-is-statements-not-declarations]]）。

编译错误全是「我以为它在那个单元里」：`TUTF8Char` 在 `LCLType` 不在 `LazUTF8`；
`OnCodeCompletion` 的 `Value` 是 `var` 参数；局部变量 `name` 撞了 `TComponent.Name`。

### 第 9 步：规则值多少，取决于什么在强制它

「对话框只把列表放进框」是 `source/` 里那四个单元存在的**全部理由**，
而在这一步之前**没有任何东西检查它**——`designtime/` 在测试构建之外，
在那儿悄悄加一个判断，直到它在用户面前出错都不会有人发现。

`TheChartOptionEditorStaysAShell` 读那个**文件**（tests/ 对那个目录只能做这件事），
在里面找五个低层原语的名字：`TyOptContextAt`、`TyOptValidate`、`TyOptFindFor`、
`TyOptKeyPositions`、`TyOptFindNearestKey`。它是钝器，而且是故意的：
**编辑器一旦需要其中之一，正确答案是在 `source/` 里加一个组合函数，不是在这里绕过那一层。**

**它第一次跑就抓到了两处，抓的是我自己刚写的代码。** 我没有放宽守卫去迁就已有代码，
而是照它的建议改：新增 `TyOptPartialAt` 和 `TyOptCompletionDetail`，壳改成走它们，
两个新函数各自配测试。差别很实在——`TyOptCompletionDetail` 里「解析光标容器、再去目录查子节点」
那段逻辑原本待在 `designtime/`，**任何测试都碰不到**。

### 第 10 步：真机 IDE（作者做不了，只有 Windows 上装了这个包的人能跑）

设计期包编译通过只证明它**能编**。下面每一条都只有在真 IDE 里才会现形：

1. **Install 之后重启 Lazarus**，从组件面板拖一个 `TTyAdvanceChart` 到窗体上。图标在不在？
2. Object Inspector 里 `Option` 那一行有没有 `...` 按钮。点开，对话框起不起得来。
3. **补全**：在 `{ ` 后按 Ctrl+Space，列表出不出来、右侧详情有没有跟着。
   打几个字母看它有没有过滤。
4. **插入的标点**：选 `xAxis` 应该插入 `xAxis: {}` 且光标停在花括号**里面**；
   选一个字符串属性应插入 `''` 并停在引号里。
5. **枚举值必须带引号**：在 `series: [{ type: ` 后补全 `bar`，插进去的应该是 `'bar'`——
   插成裸 `bar` 的文档解析不了。
6. **CJK**：把 `title: { text: '中文标题' }` 写在前面几行，然后在**它下面**触发补全。
   光标位置算错的话，补全会出现在错的地方——这是 `LogicalCaretXY` 那条的真机验证，
   而它在纯 ASCII 文本上永远不会现形。
7. **参考树**：展开 `series`，应看到 23 个 `type = xxx` 行；双击插入；
   下方文档区应显示中英说明之一（跟 IDE 语言走）。
8. **诊断**：故意写错一个键，看下方列表出不出来、**双击能不能跳到那一行**。
9. **确定按钮**：写一段解析不了的文本按确定——应该**存得下来**，
   回到 Object Inspector 里能看到你写的原文（不是上一份）。
10. **Format**：文本里有 `//` 注释时点 Format，应先弹一句确认。
11. **双击图表本身**：应打开同一个对话框（组件编辑器那条路径）。
12. 布局：底部从上到下应是 **问题列表 / 红色警告 / 路径**，再是按钮条。
    顺序反了就是 [[lcl-code-created-align-order]] 那条没生效。

GTK/Qt 上再跑一遍第 3 项的 8 条清单（spec §23），加上这里的 3、6、12——
弹出定位、CJK 光标、对齐顺序在三个 widgetset 上是三套代码。

## 29. Tier 0 收口（2026-09-04）

审计（§24）查出的六个真缺口，五个已补完，第六个只有装了这个包的 Windows/Linux 机器能做。

| 项 | 缺的是什么 | 结果 |
|---|---|---|
| 12 | phase 3 是死代码，标签**完全不抽稀** | 接线；刻度线跟着同一个 step 抽稀 |
| 9 | `min`/`max`/`interval`/`splitNumber` **一处都没读过**；`Level` 永远是 0 | 四个 option 生效（`FixMin`/`FixMax` 保证经过 `Niceify` 仍生效）；次刻度按 `minorTick` 开启 |
| 17 | 键名映射表有，**读取端不存在** | `TyChartReadStyle` + `TyChartParseColor` |
| 18 | 只有旧图表的 8 个硬编码色 | 从 `--accent` 派生的八色阶，206→214 typeKey |
| 6 | 设计期编辑器 | §28，9/10 步；第 10 步是真机 |
| 3 | GTK/Qt 真机 | **未做**，只有你能跑 |

### 一天之内同一个形状出现四次

**「能力建好了但没接线」**，而且每一次都**看起来像做过了**：

- `TyLayoutAxisLabels` / `TyAxisLabelStep`：只有测试调用它们。
- `FixMin` / `FixMax` / `Interval`：从写下来就在，**从没有人赋过值**。
- `TTyScaleTick.Level`：注释从第一天写着「1 = minor」，两个主题键从 item 18 起就躺着，
  绘制端解析代码也在——**唯独没有任何生成器会写 1**。三处等一个永远不来的值，
  而缺了那一环之后，其余每一环单看都是完好的。
- `TyChartStyleOptionKey`：三种形状的键名全映射好了，**没有任何东西拿着 JSON 调用过它**。

### 顺带修掉的两个真 bug（都在已发布代码里）

**measurer 泄漏。** `TTyPainterTextMeasurer` 是 `TInterfacedObject`，参数是
`const ITyTextMeasurer`——**`const` 接口参数不生成引用计数的临时变量**，直接传 `.Create`
的结果，引用计数停在 0，永不释放。既有的 `Relayout` 一直如此，每次重排漏一个，
三十次绘制的堆测试看不出来；我加的每轴两次让它当场显形。

**标签画进了刻度线里。** 布局层说「这个**点**，文字这样挂着」，画笔要「在这个**矩形**里对齐」。
把锚点映射成 LCL 对齐方式却留着旧的对称矩形，右锚点标签的右边缘就跑到锚点**右侧整整一个宽度**。
修法不是改映射，是**按锚点算出精确的文本框**——框和文本一样大时对齐参数就不再有影响，
两个概念合成一个。

抓住它的是刻度线那条测试，而它能抓住，是因为**早先的变异测试逼我把它从「数墨点总数」
改成「数墨带条数、且避开轴线抗锯齿」**。

### 两次「绿得没有意义」

一次是变异脚本还原源码却不重编，留下的 exe 是最后一个变异体的——表现为**莫名其妙的红**。
一次是重定向目标文件被占用，`lazbuild` 根本没跑，两个套件报 0 失败——
表现为**莫名其妙的绿**，而后者危险得多。

同一条判据：**跑测试前，确认 exe 是从当前这份源码编出来的。**

### 还有一条：一条测试依赖某个功能时，先确认那个功能存在

写标签抽稀测试时，夹具用了 `min/max/interval` 来造一个「要 150 个刻度」的尺度。
测试当场就绿了。而那三个 option 当时**一处都没被读过**，
所以两个对比夹具其实是同一个尺度——**它是因为错误的理由绿的**。
接受之前 grep 一遍，代价是一分钟。

### Tier 0 之后

Tier 1：23 个 series 渲染器、dataZoom、brush、legend、tooltip、动画时间线、地图/GeoJSON。
本项打的底——列式存储、坐标系、scale、绘制列表、四态样式、样式读取端、色阶——
在那时才有消费者。**那是排期，不是遗漏**，区别在于 Tier 1 按 spec 就还不存在。

---

## 30. 逐项复审：20 项对着代码过一遍（2026-09-05）

§29 说收口了。这次把 20 项每一项单独交给一个 agent 对着代码核，
再把每条结论交给两个独立的 agent 去**反驳**——一个查代码是不是真这样，
一个查 spec 后面有没有把这条范围收窄过。61 条原始结论，24 条挺过了反驳。

反驳这一层不是形式。37 条被否掉的里面，有把 §13 已经明文记过的
「不做增量 merge」当成缺口报上来的，也有把 Tier 1 的东西算进 Tier 0 的。
但反驳器被我要求「拿不准就判驳回」，所以它也**漏杀**——
「轴名占了位置却没人画」这条被驳回了，而我自己 grep 一遍就确认了：
`AdvanceChart.pas` 里根本没有出现过 `Name`。**它是高精度、低召回的筛子，
不是清单。**

### 24 条里最贵的那几条

| 项 | 症状 |
|---|---|
| 19 | **发丝线一根都没对齐过**。`tyControls.SubPixel` 就是第 19 项本身，唯一的调用方在 `AdvChart.Shape`——而控件的绘制路径不走 `AdvChart.Shape`。每条轴线、刻度、网格线都跨在两行像素上各占一半 |
| 3 | 六个 style 解出来只读 `BorderColor`，线宽写死 `1`。主题里五个 typeKey 全都声明了 `border-width`，改它没有任何效果 |
| 12 | **轴名从来没画过**，而 `TyAxisThickness` 从第 12 项起就一直为它扣着 `NameGap` + 转过向的文字宽度。设了 `xAxis.name`，图就窄一截，窄掉的地方什么都没有 |
| 9/13 | **log 轴整个塌到画面正中**。它是 `TTyIntervalScale` 挂 log mapper，而 `Niceify` 在原始值空间里做——步长比下界大，`Floor` 把下界推到 0，`TransformIn(0)` 是 NaN，之后 `Normalize` 对所有值返回 0.5 |
| 10 | `DataToLayout` 写死「带宽来自 x、值域来自 y」。横向柱状图的格子宽度是 0，热力图的格子从第一个类目的中心一直拉到当前这个 |
| 14 | **反向扇形画出来的是命中区的补集**。`SectorContains` 一直把负 sweep 读成两角之间的短楔形，而渲染把两个角原样交给 `ArcTo`，它的扫过量是按环绕算的 |
| 8 | 从 series 数据里收上来的类目**到不了轴**。存储那半边接好了，消费那半边没有：范围在轴构造时定死，那时列表还是空的 |
| 2 | **图案填充根本不存在**，而注释说图片类会「退化成底色」——图片类的 `Color` 是 `tyTransparent`，退化的结果是一个像素都不画，还不报错 |

### 同一个形状，第五次到第八次

§29 说「能力建好了但没接线」一天之内出现四次。这一轮又是四次：
`--advchart-minor-tick-length`（token、常量、默认值三处齐全，没有读的人）、
`TyOptDescZh`（唯一的调用分支进不去）、
`TyOptValueCandidates`（调用方只有测试）、
`minInterval`/`maxInterval`（scale 上连属性都没有）。

**判据现在很清楚了**：一个能力横跨主题、常量、类型、绘制四层的时候，
每一层单看都是完好的，缺的那一环只有把四层连起来数才看得见。
`grep` 调用点，调用点只在 `tests/` 就是红旗。

### 测试比修复更容易写错

这一轮我为修复写的测试里，**有五条第一版是错的**，而且全都是绿的：

- 数轴线附近的墨点——把刻度线也数进去了，改宽度前后都是 269
- 按「离背景多远」分「实心/半亮」——主题给分隔线的 alpha 是 0.6，
  对齐得再好也算「半亮」，这条测试**无论代码怎么写都不可能通过**
- 有名轴 vs 无名轴的总墨量——取名会**挪动 plot 矩形**，两次的差跟名字无关；
  把绘制变异掉它照样绿
- 2×2 的棋盘纹理——pattern scanner 做插值，每个像素都是紫的，
  找红色一个都找不到，而画布上有 1224 个像素证明填充是好的
- 只数覆盖像素——平铺和拉伸都盖满路径，两个变异体都活着

抓住这五条的是同一件事：**改完之后把修复变异掉，看测试红不红**。
没有这一步，五条里有五条会当成通过发出去。

### 顺带的两件事

**i18n**：AdvChart 编辑器有 6 条字符串没翻译，`tyControls.Design` 有 36 条，
后者比这个分支还早。既有的 i18n 测试只查 `.pot` 全不全，
从来不查有没有人翻——所以补了一条**走磁盘问清单**的守卫，又查出 8 条。
守卫自己的第一版用子串匹配，`rstyOptDiagNoSeries` 在
`rstyOptDiagNoSeriesXX` 里面——被金丝雀当场杀掉。

**`\uXXXX` 相邻就丢字节**。FPC 3.2.2 的 json scanner 在两个转义挨着时
会用第二个覆盖掉第一个的尾巴：`"\u4e2d\u6587"` 解出来 4 个字节而不是 6 个。
中间隔一个字符就正常——而两个转义挨着，正是中文字符串写成 \u 形式的样子。
现在在交给 parser 之前自己解。

### 还是没做的

- 第 3 项的 **GTK / Qt 真机**：用户明确押后，先把 Windows 做完。
- 第 6 项第 10 步的**真机 IDE**：注册的三处（面板、组件编辑器、属性编辑器）
  代码上都在，对话框本身由 `tools/advchart-probe` 在真桌面上驱动（25 项检查），
  但「在 IDE 里装上这个包、从 Object Inspector 点开」仍然只有装了包的人能做。

---

## 31. 第 15 项:筛子漏掉的那一整项(2026-09-05)

§30 的反驳器把第 15 项的三条结论**全部驳回**,所以它没进那 24 条。
我复查的时候只查了被误杀的高危条,没查「整项全清」的那几项——这是漏检。
手工核完:**三条都是真的**。

- `TyWrapTextCJK` 在整个 chart 里一次都没被调用
- `Measure.pas` 一共 103 行,行 15 点名的三种缓存机制**一个都没有**
- 标签带换行的话,measure 按 N 行算、draw 按一行画,后面几行直接丢

### 缓存那一半:早就有了,在下面一层

两个测量函数**本来就是 memo 化的**,键里含每一个输入——包括主题每次 apply 都会重写的
两个全局——换主题时整个丢掉,而且陈旧性论证在 Painter 里写了整整一页。
**在 chart 里再建一份缓存,等于把那页论证复制一遍,还多一个能跟它对不上的东西。**

真正缺的是另一件事:`PaintAxis` 用 `APainter.MeasureText` 量标签,
而布局用的是另一条路径——**两个不同的光栅器**,差约 1px,
`Measure.pas` 的头注释自己写着「尺寸下限喂给裁剪的控件必须取两者中较大的」。
布局取了较大的,绘制取了其中一个,然后拿它去搭标签的框。
现在绘制走它本来就收到的那个 measurer。

### 折行那一半:件件都在,一件也够不着

`TyWrapTextCJK`、`TyEllipsisPrefix`(按字符切、不会把三字节汉字劈一半)、
`DrawText` 自己的 `AEllipsis` 和 `AMultiLine`——全都在,而 chart 传的是
`AEllipsis := False`、从不设 `AMultiLine`、也没有地方说一条标签最宽能多宽。

现在:`axisLabel.width` + `overflow: truncate | break | none`(`none` 是 ECharts 的默认,
也是原来的行为)。**断好的文本只产生一次**,在 builder 里,写进 spec——
布局量的和绘制画的是同一个字符串。折行走 measurer,因为 builder 是纯的、
而认得中文的折行在 painter 里;按空格断的折行会把一整段中文当成一个不可断的词。

### 一个变异体活着,如实记下

「绘制退回用 painter 自己的测量」这条**杀不掉**:差别是亚像素的,
我没能造出一个不会「因为错误的理由通过」的无头判别器。
所以不硬凑,改成钉住它所依赖的不变式——**measurer 永远不是两者中较窄的那个**。

### Tier 0 到此为止

20 项里 19 项完成,第 3 项的 GTK/Qt 真机由用户押后,
第 6 项第 10 步的「在 IDE 里装包点开」只有装了包的人能跑。

---

## 32. Q7 定案：动画与重绘模型（2026-09-05）

单独成文：`2026-09-05-advancechart-q7-repaint-model.md`。这里只记结论和它靠的数字。

**决定**：分层缓存做，脏矩形不做（Tier 3），3.1 只承诺进入动画与状态过渡；
在这之前先做一件研究里没有的事——把一帧本身画便宜。

**依据**（`tools/advchart-bench`，900×700，无头 `RenderTo`）：60 点一帧 53 ms，600 点 110 ms，
**两根轴隐藏 13 ms**，300×200 仍要 32 ms，5000 点 **10 秒**。
研究给 Q7 的三个选项全建在「一整页光栅 14.9 ms」上，而那是老图表经父控件重绘量的；
新控件的一整页光栅确实是 13 ms，**其余全是轴上逐条描边和逐个文字光栅**，缩像素不省时间。
脏矩形省的是像素，所以它打的是错的账单。

**前置**：同样式发丝线合成一条路径一次描边；分隔线跟标签一起抽稀；600 点一帧 ≤ 16 ms 作为验收，
数字记在 bench 不写进测试。

**帧模型**：照库里 8 个控件的既有做法（懒建 16 ms `TTimer` + `TTyAnimator.Advance`），
新加 `InvalidateFrame` 只重绘动态层；层标记挂在第 14 项的绘制列表上，**不暴露成 option**。

---

## 33. 图元:Tier 0 那堆底座第一次有人用(2026-09-06)

到 §32 为止,控件画的是坐标轴,数据一根没画。它自己的诊断行也这么说——
「series 图元尚未实现」。同时 §30 复审记下过一条:**第 14 项的绘制列表在 tests/ 之外没有任何调用者**。
这两件其实是同一件。

`AdvChart.Marks.pas`:一个绑定好的 series 加它的 store,变成绘制列表里的元素。
纯单元,不碰 painter、不碰 LCL——颜色是个数字传进来的,因为解析主题是控件的事。
今天只有 bar 和 line,别的类型画不出来就是画不出来,不画近似。

### 柱子的矩形不是自己算的

`DataToLayout` 是坐标系合同的第(1)条,一根柱子正是它设计出来要返回的形状:
一个 band 宽,从数值轴基线到数据点。自己算一遍就是同一个数字的第二个生产者,
而且横向柱状图会算错——那正是 `DataToLayout` 一直带着、直到被逼着问「哪根轴是脊柱」才修掉的缺陷。

不做的部分写在单元头里:ECharts 的柱宽求解器(`barWidth` / `barMaxWidth` / `barGap` /
`barCategoryGap`,以及让多个 series 共用一个 band 的偏移)是 Tier 1 自己的一行。
现在实现的是**单 series 默认值**——上游自己的 `barCategoryGap: '20%'`,所以 `BarBandFraction` 是 0.8。

### 五条老测试当场变红,原因全一样

它们都从图区正中取背景参考色(`PixelAt(200, 150)`)。那里以前是空的表面色,
现在是一根柱子。参考色变成柱子的颜色,于是其余每个像素都「和背景不同」,
四个标签数出来是一整条。**数像素前先问窗口里除了被测对象还有什么**——同一个坑。

修法不是换个取样点(那只是把问题挪个地方),是 `series: []`。这些是**坐标轴测试**,
没有 series 的坐标轴是控件真实存在的状态。其中一条的含义因此变了:
`show: false` 藏的是**轴**,绑在被藏坐标轴上的 series 照样映射照样画——
沿用老断言等于把一个 bug 钉死。加了一条断言把新的真相钉住。

### 顺手挖出一个已发布代码里的真 bug

给「图元用的是主题颜色」写测试时,`StyleOverride := ''` 清不掉。追下去:
`ReloadThemeLayer` 的**每一条分支都必须加载点什么**,因为附加层没法卸载,
layer-1 是整个重建的——而一条什么都不加载的分支,会把旧补丁原封不动留在 `FRules` 里。

两条源分支都可能什么都不加载:被删掉的 ThemeFile,和**没注册的 ThemeName**。
后者一点都不罕见——`SetThemeName` 明文允许失败并在主题出现时重试,
所以一个控件可以长期挂着一个它还没有的主题名。症状是:
**凡是指定了主题名的控件,StyleOverride 永远清不掉,换一个则是叠加而不是替换**。
原来那条清除测试之所以绿,是因为它的控制器没有主题名,走的是第三条分支——那条一直有加载。

回落到 base 不是猜用户想要什么:名字既然从来没解析成功,layer-1 里本来就是 base,
所以这一步恢复的正是原来那个画面,减掉它本来就该丢掉的补丁。

### 诊断行自己变成了那句谎话

那条 all-clear 行对**每一个**合法配置都说「series 图元尚未实现,所以只画得出坐标轴」。
柱子开始画的那一刻,这句话就反了过来:作者的图明明在屏幕上,面板告诉他什么都没画——
这正是这行当初被发明出来要防的那件事,只是掉了个头。

现在它按类型分三种答法:全都画得出就只说读懂了;一个都画不出还是老那两句;
**混着的时候点名那些画不出来的**——不然「option 没有问题」会让作者去找一根不存在的柱子。
「哪些类型有渲染器」这个答案从渲染器本身拿,不在编辑器里另立一张表:
另立的那张,会在下一个渲染器落地的那天开始说谎。枚举名 `odkNothingPaintsYet` 一并改成 `odkAllClear`。

### 变异测试的五条回执

三轮 25 个变异体,活下来 2 个,其中一个直接导致了一次重构。

- **`v.Z2 := i` 是死代码**。把它改成 0 的变异体活着,因为绘制列表**写明了**
  平局用插入序,而这些本来就是按 series 序插入的。同一件事说了两遍,其中一遍不做事——删掉。
  等 series 的 `z` / `zlevel` 落地,Z 会变,Z2 才有活干。
- **「谓词守住派发」也是死代码,而且它自称的职责就是防死代码**。
  我原本让 `TyBuildSeriesMarks` 先问一遍 `TySeriesTypeHasRenderer` 再走
  `if t = 'bar' ... else if t = 'line'`,理由写的是「这样两边不会各答各的」。
  把那道门删掉的变异体活着——**因为两边一致的时候删哪边都没区别**,
  而它唯一有用的时刻是两边已经不一致了。那不是守卫,是第二份拷贝。
  改成一张表:`cRenderers` 一行一个渲染器,谓词是查表,派发是查表后调用。
  加一个渲染器是加一行,没有第二个地方可忘。
- **调色板根本没被证明会轮转**。所有 series 都解析 `TyAdvChartSeries1` 的版本通过了当时全部测试——
  单 series 的图分辨不出来,而这个文件里当时全是单 series 的图。补了一条两 series 两颜色的。
- **被删掉的 ThemeFile 那条分支没人测**。补了。
- **NaN 预检查杀不掉,如实记下**:NaN 数据点算出来的矩形两行之后过不了 `TyRectFIsValid`,
  两道关都拦得住。这行留着,因为它在规则适用的地方把规则说出来了——但今天执行规则的不是它。

### 读自己的 diff 读出来的两个洞

- **去重按裸子串比,`map` 被 `treemap` 吃掉**。两个都是真类型、都还画不出来,
  同时出现只会点名一个。改成带分隔符整词比。
- 类型名**大小写敏感**,跟 `TySeriesFindType` 一致:ECharts 的类型名区分大小写,
  写成 `'Bar'` 的 series 根本 resolve 不了、也就永远画不出来,谓词答「能画」就是承诺一张画不出的图。

去重那条的测试**我写错了,而且是变异测试才告诉我的**。

我以为 `treemap` + `tree` 就够了,写了注释说它钉住了子串修复。跑变异体——**活着**。
回头看:被吞掉的是**后缀**不是前缀。`Pos('tree,', 'treemap,')` 找不到(逗号不对),
`Pos('map,', 'treemap,')` 找得到。二十三个类型里唯一的后缀对就是 `map` 跟在 `treemap` / `heatmap` 后面,
而 `map` **永远走不到这一行**——它要 geo 坐标系,builder 先报
`coordinateSystem "geo" is not built yet`,有 build 诊断就没有 all-clear 行。

所以这个修复是**对的,但今天够不着**,那个变异体是故意留活的。
测试留下了(它钉的是「几个不同类型都要点名」,这是真的),
注释改成说它到底钉住了什么、没钉住什么——
**一条声称覆盖了它没覆盖的东西的测试,比没有那条测试更糟**。

---

## 34. Tier 1 第一批:柱子的宽度求解器(2026-09-06)

§33 让柱子画出来了,但**同一根轴上的多个 bar series 画在完全相同的位置**——第二个盖住第一个,
两个 series 的图看起来像一个 series 的图。宽度不是某个 series 的属性,
是**共用一根基准轴的所有 bar series 共同的属性**,一个 series 算不出来。

`AdvChart.BarLayout.pas`:照 ECharts 6.1.0 的 `calcBarWidthAndOffset` 抄的。
输入早就备好了——`TTyAxisSeriesIndex` 的 keyed 桶只收「这根轴是该 series 的**基准**轴」的条目,
它自己的注释就写着这是给柱子分带用的,然后一直没人调。

### 抄文档抄错了,而且错了两处

`Marks.pas` 里写着「上游的 barCategoryGap 是 '20%',所以 0.8」。**两个数都不对。**

源码里根本没有固定的 barCategoryGap 默认值:没人设的时候是 `max(35 - 列数*4, 15) + '%'`,
一列 31%、两列 27%、三列 23%、四列 19%,五列起钉死 15%。
`barGap` 的真实默认是 **10%**,来自 `BaseBarSeries.defaultOption` 上一个私有的 `defaultBarGap: '10%'`;
公开的 option 文档写 20%,本仓库那份**生成的** catalog 也写 20%——因为它是从文档转录的。

所以一根孤零零的柱子占的是 **0.69** 个带,不是 0.8。

这正是仓库里早就记下的那条:**目录是文档真相,不是运行时真相,渲染语义必须从源码手抄**。
这回连「上游的默认值是多少」都得从源码手抄。

### 保留了一个上游的怪癖

显式给了 `barWidth` 的列,它的宽度会**从余量里被减掉两次**——第一遍收集时一次,
第二遍定稿时又一次。这是上游从 5.x 起就有的行为。
把它「修好」的移植会画出和被抄的那张图不一样的柱子,所以照抄。

同理照抄的还有那套不一致的取值规则:`defaultBarGap` 只听**第一个** series 的,
`barGap` / `barCategoryGap` 听**最后一个**说了的,`barWidth` 在一列里听**第一个**说了的。
这些选项写起来是 per-series、作用起来是 per-axis,复制它的 tie-break 是两张图能一致的唯一办法。

### 一个「像 bug 其实不是」的地方,变异测试之外靠对抗审查捞回来

`barMinWidth` 上游读的是 `get('barMinWidth') || 1`——**永远不是 null**,
所以每个 series 都会覆写所在列的 minWidth。后果是:
**同一个 stack 里后面那个什么都没设的 series,会把前面那个显式写的 barMinWidth 覆盖成默认的 1。**
把「没设」读成「保持原值」是最自然的移植,也是错的,画出来的柱子比被抄的那张宽。

我第一版就是错的那种。是并行审查里一个 refuter 对着源码指出来的。

### FPC:`Max(0, <Double>)` 走的是 Single 重载

整数字面量让 Single 成为更便宜的转换,于是**每一个解出来的宽度都被悄悄截成 24 位尾数**。
症状隐蔽到了危险的地步:柱子位置全对、图也没问题,只有拿公式比的测试在第 8 位有效数字上差一点,
**看起来像容差没调好,而不是精度出了问题**——我差一点就去放宽容差把它盖掉。
钳制全部写开成 `AtLeast`,一个重载都没得选。

另一个会话对着同一个编译器说**不复现**,建议我去查「整数 × 无类型实常量」那条老坑。
写了探针实测,结论跟他相反,而且判据不靠比较:

```
  TRUNCATED Max(0, d)      got=78.214286804199219 want=78.214285714285694
  exact     Max(1.0, d)                { 无类型实常量 → Double 重载 }
  exact     Max(cTenth, d)             { 0.10 也一样 }
  TRUNCATED i * 1.0        got=16777216 want=16777217
sizes: SizeOf(Max(cOne,d))=8  SizeOf(Max(0,d))=4  SizeOf(d)=8
```

**`SizeOf(Max(0, d)) = 4`**——编译器直接说了返回类型是 Single,不需要靠运行期比较去推,
也不会被常量折叠骗到。三件事同时成立:整数字面量那条是真的、
无类型实常量那条**恰恰相反**(我原先猜错了元凶)、他说的 `i * 1.0` 那条也是真的但是另一个坑。
变异测试从第二个方向确认了同一件事:把调用点改回 `Max(0, ...)`,测试红。

### 变异测试:三轮 32 个,活下来 1 个

活下来的那个是**等价变异体**:`Max(35 - AAutoCount*4, 15)` 和 `Max(35 - Length(ACols)*4, 15)`
在调用点上恒等——`autoCount` 每遇到一个新列加一、在 `SolveColumns` 里才开始减,
所以进函数时它就等于列数。等价的不去凑测试,记下来。

第一轮 26 个里活了 6 个,其中 4 个是真缺口,变异测试逐个点了名:

- **15% 的地板没测到**。`max(35 - n*4, 15)` 要到**六列**才开始钳(五列两边都是 15),
  而我的测试停在四列。补了六列的用例。
- **`barWidth` 在一列内是 first-wins 没测到**。它跟 `barGap` / `barCategoryGap` 的 last-wins 相反,
  而且只有两个 series 共用一个 `stack` 时才看得出来。
- **1px 带宽下限没测到**。数据比轴还密时(间隔 1、跨度 100000)带宽不到一个像素,
  下游全都要除以它——没有下限的话图是空的,而里面每个数都有限且看着合理。
- **零宽列会画出整条带**。`PlaceInBand` 在宽度 ≤ 0 时「原样返回」,
  而原样返回的是**整个格子**——于是 `barCategoryGap: '100%'`(把每一列都解成 0)
  画出的是**最宽的柱子**。下游那道零宽守卫永远够不着,因为零宽的矩形根本没送到它手上。
  **这是变异测试直接挖出来的真 bug,不是测试缺口。**

还有一个是**变异体自己设计错了**:我把 `AtLeast` 的函数体换成 `Max(AFloor, AValue)`,
两个都是 Double 形参,选的是 Double 重载,什么都没变。要复现那个坑,
整数字面量必须在**调用点**上——重新瞄准之后一枪毙命。

最后一件,记在这里因为它差点让整轮结果失效:第二轮我往变异体列表里追加两条,
用的是不带命中数断言的 `str.replace`——**没匹配上,静默 no-op**,
于是跑了 4 个却报告「六个变异体,SURVIVORS: none」。
这正是仓库里那条「CRLF 上的变异替换=假存活」的同一个形状:
**替换失败会报告成功,然后收割机给出一张它根本没测过的满分成绩单**。
补跑那两条,都杀掉了。

### 顺手补掉的两件事

- **值轴上的柱子以前画不出来还挡着**。基准轴不是类目轴时 `BandWidth` 返回 0,
  于是 `DataToLayout` 给出一个零宽矩形——不可见,但 `TyRectFIsValid` 认它、命中测试也认它。
  现在按上游的启发式从数据里推带宽:所有 bar series 的基准维值汇到一起排序,取**严格为正的最小间隔**
  (重复值是常态——两个 series 报同一个 x——零间隔会把柱子压没);
  全部相同或只有一个时回落到跨度的 80%;最后有 1px 下限。
- **`barMinHeight` 和 `itemStyle.borderRadius`**(标量形式)。
  minHeight 锚在基线上而不是格子上——格子是哪一头是基线,恰恰被建它的那个 Min/Max 丢掉了。
  零值柱子朝正方向伸,两种朝向的符号规则是从相反方向得到的同一个答案。

### 已知的偏差,写在这里而不是留着

`DataToLayout` 的基线取的是**值轴 extent 的起点**,上游取的是 `dataToCoord(0)`(对数轴是 1)
或作者写的 `startValue`。`min: 0` 时两者重合,`min: 20` 时不重合。
这是 `DataToLayout` 既有的行为,不是这批引入的;
`ApplyMinHeight` 跟着同一条基线走,因为让 minHeight 和矩形用两条不同的基线只会更糟。

### 一条不是这批引起的红

全量 6985 个测试 0 failures,一个 error:`TestReadOnlyCutCopiesButDoesNotClear` 的剪贴板写入被拒。
它今天在这个分支上跑绿过两次、红过两次,所以第一反应是那条已知的环境抖动。
但**在 main 的二进制上它现在是绿的,在这个分支上连红三次**——「环境」解释不了这个差别,
所以去查了:把未提交的改动 stash 掉、在 HEAD 上重编重跑,**照样红**。

不是这批引起的——这一半是对的,stash 掉重跑照样红。

**但我给出的原因是错的,后来被推翻了。** 我当时写:差别在于 main 上有两个这个分支还没有的 grid 提交。
另一个会话指出真凶是 Snipaste / rdpclip 在抢剪贴板,并说他那边连跑三次是「绿红绿」。
我在同一个分支二进制上连跑四次:**红、红、绿、红**。所以它就是抖动,只是恰好连红了三次。

**教训不是「跑绿过所以是抖动」,而是我把它反过来用错了。**
我当时的推理是「分支和 main 表现不同,那就不是抖动,是两份不同的代码」——
这句话本身没问题,错在我只跑了一次 main、三次分支就当成了「表现不同」。
三次连红在一个真抖动上一点都不稀奇,而我拿它当了因果证据。
**要区分抖动和代码差异,得两边都多跑几次,不能一边一次。**

### 明确没做

值堆叠(几个 series 共用一个 `stack` 沿值轴累加)是 Tier 1 自己的一行。
求解器**已经**把它们归成一列——这是堆叠的布局那一半,所以它们共用宽度和偏移、
然后画在一起:**对的列,错的值**。四角形式的 `borderRadius`、`showBackground`、
以及 line 那一族(`areaStyle` / `smooth` / `step` / symbol)都是各自的行。

---

## 35. Tier 1 第二批:值堆叠(2026-09-06)

§34 留了个半成品,而且是我自己造的:求解器已经按 `stack` 把柱子归成一列,
但值不累加——**对的列,错的值**。两个同 stack 的 series 共用宽度和偏移,然后画在一起。
代码里三处注释白纸黑字写着这件事没做,留着不动比什么都不做更糟。

`AdvChart.Stack.pas`:照 `src/processor/dataStack.ts` 抄的。
`stack` / `stackStrategy`(四个值)/ `stackOrder` / `addSafe`。

### 底座早就搭好了,只差一块

`AddDimension` 的注释原文写着「一次堆叠计算会追加两个」,
`BuildInvertedIndex` 的注释写着「给按类目堆叠用」——两个都建好了,两个都没有调用者。
缺的只有**写入**:填充之后加的列全是 NaN,而没有任何办法往里放数。
补了 `SetCalculated`。

### 三件照抄才对的事

- **搜索在最近的合格成员处 break,不是把下面全加起来**。
  每个成员只加它下面第一个策略认可的那个的**累计值**,然后停。
  连带的后果是:`samesign` 判断里的 `sum` **永远是这个 series 自己的原始值**,不是运行总和。
- **值堆叠只按 `stack` 字符串分组,全图范围**,不看坐标系、不看基准轴、不看类型。
  这跟柱子**列**的分组不是一回事——那个是按基准轴分的。同一个词,两个问题,
  搞混是最顺手的错误。两个不同 grid 里同名的 series 真的会累加。
- **`stackOrder` 只读第一个成员的**。写在后面任何一个 series 上都完全不起作用。

### 两个 bug,一个是审查抓的,一个是读自己的 diff 读出来的

**`SetCalculated` 只清了缓存,不够。** `DataExtent` 有一条快路径——未过滤、未筛值,
正是值轴要问的那一条——它在查缓存**之前**就从 `RawMin`/`RawMax` 返回了。
而那两个只在 append 时维护,`AddDimension` 留下的是空区间。
于是**一整列堆叠总和会报告「没有数据」**,轴按原始值定尺寸,堆叠图直接画到图区外面,
什么都不抛。修法是给维度打标记而不是在写入时顺手撑宽 RawMin/RawMax:
撑宽只在「每格只写一次」时成立,而公开的 setter 承诺不了这个,
一次写入更小的值就会让单调的 RawMin 永远偏宽。

**横向柱子会静默地不堆叠。** 我把累计值无条件塞进 `y`——竖着的柱子对,
横着的柱子值在 X 上,于是堆叠算完了又扔掉。读自己的 patch 时发现的。

### 变异测试:两轮 26 个,全杀

这一批的变异测试比平时更要紧,因为审查报告点明了一件事:
**accumulation 落地时,套件里没有任何一条既有断言会变红**——
柱布局的测试读的是列几何(从 bar* 键和带宽算的,从不碰值),其余是词汇表。
所以套件从头到尾都是绿的,**做对了是绿的,做错了也是绿的**。新写的测试是唯一的守卫,
那么这一轮变异测试就是这些守卫到底守不守得住的唯一证据。

第一轮 22 个跑掉 2 个真缺口,都补了:

- **一堆的最底下那个也被算了地板**。它累加在虚空上,地板就是轴自己的基线;
  给它算一个 `(累计 - 自身) = 0` 会在**轴不从零开始时**把它挪走。
  之前每条测试的轴都从 0 开始,于是两个答案是同一个数,变异体活得好好的。
- **堆叠的 line 没有测**。只有柱子测了画累计值,而堆叠面积图底下就是一条堆叠折线——
  最常用堆叠的那个类型,恰好是没被钉住的那个。

还有一条**针打偏了**:「累计值塞错轴」这个针在 BuildBars 和 BuildLine 里各有一份
(两处代码一模一样),命中 2 次,脚本如实报了 NEEDLE MISSED 而不是假装跑过。
分开瞄准之后两个都杀掉了。

### 明确没做

`areaStyle`(堆叠折线底下那条带子,`stackedOver` 列就是给它准备的)、
symbol、`smooth` / `step`,以及 `showBackground` 和四角 `borderRadius`,都是各自的行。
图例过滤会改变堆叠成员(上游正因为这个才把结果写进计算列而从不碰原始数据)——
还没有图例。极坐标的柱子用的是第三套机制(像素累加器,不是这两列)——也还没有极坐标。

---

## 36. Tier 1 第三批:line 那一族(2026-09-06)

`areaStyle`(含 `origin`)、`step` 三种、`connectNulls`。全部照 ECharts 6.1.0 源码抄,
不是照描述抄——`poly.ts` 的 `ECPolygon.buildPath`、`helper.ts` 的 `getStackedOnPoint` / `getValueStart`、
`LineView.ts` 的 `turnPointsIntoStep`。

`cskPolygon`(「闭合的填充区域」)**是这一片第四个「建好了没接线」的东西**:
渲染有、命中测试有、`tests/` 之外零个调用者。前三个是 `TTyAxisSeriesIndex` 的 keyed 桶、
`AddDimension` 注释里那句「堆叠计算会追加两个」、`BuildInvertedIndex` 的「给按类目堆叠用」。
底座总是先到,调用者后到。

### 面积的下边缘就是上一批那列

`getStackedOnPoint`:堆着就取 `stackedOver`,是 NaN 就落到 origin。
所以上一批建的那一列在这里有了消费者——**堆叠面积图**就是这么来的。

`origin: 'auto'` **不是简单的零**:整根轴都在零以上时,面积从**量程底部**起;
整根轴都在零以下时从顶部起。否则填充会伸向一个不在轴上的零。

### 一个循环里三条互相矛盾的 gap 规则

审查员在我自己刚写的代码里挑出来的:数据是 NaN 就断开运行——对;
但**点映射失败**和**面积基线映射失败**是**静默丢弃**的。
丢弃会让折线直接跨过那个洞闭合,**正是 `connectNulls: false` 要防的那件事被它自己撤销了**。
统一成一条。

### 变异测试:18 个跑掉 6 个,其中三个是同一个洞

**`TyLineSpecOf`——读 option 的那个函数——在整个套件里一个调用者都没有。**
所有几何测试都是手工塞 `TTyLineSpec` 再验画得对不对。
手工塞记录测的是绘制,**它对「option 有没有被读懂」一个字都没说**。
于是三个变异体活着:`step: true` 不当成 'start'、空的 `areaStyle: {}` 不开面积、默认值。

另外三个也都是真洞:

- **我的绘制顺序测试测错了东西**。它断言 `Element(0)` 是多边形——那是**插入**序。
  绘制列表按 (Z, Z2, 插入序) 排,把面积的 Z2 抬高的变异体让阴影盖住了线,测试照样绿。
  改成问 `PaintOrder`,那才是「先画谁」。
- **没有任何东西比较过面积的上下两条边**,所以「下边不跟着 step」的变异体活着:
  上面是台阶下面是直线,填充从自己的轮廓底下漏出来。
- **Infinity 没被当成洞测过**。

### 一个活着的变异体,如实记下

`Illegal` 里的 `IsInfinite` 那一半**今天够不着**。上游需要它是因为**它的**对数轴对非正值答 -Infinity;
**我们的答 NaN**(`TTyLogScaleMapper.TransformIn` 对 `AValue <= 0` 直接 `Exit(NaN)`),
所以 NaN 那一半已经把唯一能到这儿的情况拦掉了。
留着是因为「洞 = 任何非有限坐标」这条规则本身是对的,下一个除以零跨度的 mapper 就会造出一个。
**不为了杀一个变异体去编一个够不着的状态**——跟 §33 里 NaN 预检查那条同一个处理。

### 顺带:官方示例语料

`tools/advchart-gallery/harvest.js` 把 Apache ECharts 官方示例转成静态 option JSON,
**273 个里转出来 244 个**。转法是**跑**而不是**解析**:那些文件是 TypeScript,
不引号的键、单引号、尾逗号、模板串、箭头函数、生成的数据——正则转换会安静地转错。
先 `ts.transpileModule` 再在 vm 沙箱里执行,`JSON.stringify` 顺手把回调丢掉(那正是对的:
这个端口读的 option 树就是 JSON,诊断行早就为粘贴进来的回调准备好说辞了)。

三个坑记一下:
- `module: 'None'` 传**字符串**会被静默忽略、回落成 CommonJS,于是 273 个里 247 个死在
  `exports is not defined`——看起来像沙箱问题,其实是编译选项问题。要传 `ts.ModuleKind.None`。
- 每个示例结尾都有一句 `export {};`。就是这个标记让 TypeScript 把文件当**模块**,
  于是不管 ModuleKind 是什么都会吐 `__esModule` 前言。它对我们没有意义,去掉。
- TypeScript **7.0.2 是 Go 重写版**,npm 包的入口只有一个版本号存根,没有 `transpileModule`。要装 5.x。

剩下 29 个转不出来的各自记了原因(ecStat、echarts-gl、zrender 内部),
另有 10 个转出来但太大(`scatter-large` 单个 64MB,十个加起来 120MB,
全是 large 模式的压力用例、恰好也是这个端口画不了的),按 1MB 上限排除,原因同样写在索引里。

---

## 37. Tier 1 第四批:符号库与 scatter(2026-09-06)

示例记分牌说得很清楚:scatter 挡着 33 个官方示例,而且它的**整条流水线早就通了**——
解析、绑定、列式存储、轴范围、布局、画轴全对,轴上的数字都是从真实数据推出来的,
**只差最后一步画点**。

`AdvChart.Symbol.pas`:照 `src/util/symbol.ts` 抄的符号库。
circle / rect / roundRect / square / triangle / diamond / pin / arrow / line / none,
加 `empty*` 前缀和 `path://`。`image://` 明确拒绝——纯单元里没有图片的容身之处,
而画个替代形状等于给作者一张他没要的图。

### 没有复用 tyControls.Shape

那个单元确实有 triangle 和 diamond,但**不是这两个**:它服务 TTyShape 控件,
词汇是它自己的(star、squared diamond、四个方向的三角),顶点也按那个控件算。
**两族只是重叠,不等于是一族**;共用之后,以后每加一个 ECharts 符号,
都得在一个控件的词汇里争论它该叫什么。

### 除了圆、圆角矩形和 path,一切都建成多边形

不是偷懒:绘制列表的 shape 记录**没有旋转**,而多边形可以直接按旋转后的顶点建。
一条永远对的路,好过一条快、但对一半形状悄悄忽略 `symbolRotate` 的路。
圆角矩形一旦旋转就退化成方角多边形——角度是作者要的,圆角不是。

### 我的心智模型错了,而且错得很像对的

我以为符号是**在它的 symbolSize 盒子里**建的,于是照着 shape-maker 抄:
`circle` 取 `Math.min(w, h) / 2`、`square` 取短边并贴盒子左上角、`keepAspect` 把盒子取方。

**都不对。** `Symbol.ts` 调 `createSymbol(type, -1, -1, 2, 2, ...)`——**单位盒**——
然后给元素 `scaleX = symbolSize[0]/2, scaleY = symbolSize[1]/2`,**非等比缩放**。所以:

- `symbolSize: [20, 8]` 的 circle 是**一个 20×8 的椭圆**,不是内切的半径 4 的圆
- `square` 对 series 符号而言**和 rect 一模一样**:单位盒里 `min(2,2)` 是空操作,
  左上角锚定也就永远不显形。差别只在 createSymbol 拿到真实盒子的地方——图例图标和 markPoint
- **`symbolKeepAspect` 根本到不了内置符号**:`createSymbol` 只把它交给 `makePath` / `makeImage`
  当作包围盒的贴合模式,内置那条分支一个字都没读

直边形状不受影响——在单位盒里建再缩放,和直接在盒子里建是同一个线性映射。

**这三条是并行审查里的第二个审计员抓到的,而且它跟第一个审计员的结论相反。**
两份报告对着干的时候只有一个办法:自己去读源码。读完是第二个对的。
`scaleX: symbolSize[0] / 2` 那行就在 `Symbol.ts:87`。

### 变异测试:24 个跑掉 3 个

- **旋转方向没被钉住**。我的测试转 180°——**半圈是它自己的镜像**,分不出顺时针逆时针。
  改成 90° 就杀掉了。
- **零尺寸那条断言错了对象**。它断言 `Bounds` 无效,而圆**根本不用 Bounds**,
  所以守卫开不开它都绿。改成断言 Kind:「什么都不画」是一个 bounds 无效的 rect,
  变异体给出的是 circle。
- **`tsyNone` 的提前返回是等价变异体**,如实记下:删掉它也没区别,
  因为 case 里没有 tsyNone 分支,点列表保持为空,两屏之后返回同一个无效矩形。
  它留着是为了把规则说出声——'none' 是一条指令,不是一次失败的绘制。

### 两条测试因此变红,而且红得正确

`TestAnUnknownSeriesTypeDrawsNothing` 和 `TestThePublishedAnswerMatchesWhatIsActuallyDrawn`
钉的是「scatter 还没有渲染器」。这正是这类测试的用途——**断言说的是规则,类型只是当下的例子**——
所以例子换成了 `pie`。诊断那条同理。

### 气泡图的尺寸

上游用回调按 datum 算 symbolSize,而回调过不了 JSON 这一关。
静态 option 能带的是**点上的第三个数**,所以读它:
store 里除去两根轴用的那两列之外的第一个浮点列。
不这么做的话,画廊里每张气泡图都画成一个尺寸,看着就是普通散点图。

---

## 38. Tier 1 第五批:折线的标记(2026-09-07)

`showSymbol` / `showAllSymbol`。`LineSeries.defaultOption` 写着
`symbol: 'emptyCircle'`、`symbolSize: 6`、`showSymbol: true`、`showAllSymbol: 'auto'`,
所以 ECharts 的折线**每个点上都有一个环**,而我们一个都没画。

### 只有对着原图才看得出来的错

line 的默认符号是 **`emptyCircle`** 不是 `circle`。两个都是圆,代码看着没毛病;
差别是**环还是实心点**。这种错能活很久,因为单看自己的图完全正常。

### 一个我先写错又推翻的设计

加上标记之后 6 条折线几何测试变红——它们数元素个数,现在把标记也数进去了。
最省事的做法:让手工构造的 visual 默认不画标记,一行测试都不用改。**我先这么写了,然后推翻。**

**同一个字段两个默认值,正是这个项目反复栽进去的「悄悄不对的默认值」。**
改成上游的 `True`,让 10 条几何测试各自显式关掉并写明「这条测的是线」。
多改十行,但每条测试从此说得清自己在测什么,而且万一有惊喜是**看得见的**(多出元素)
而不是**沉默的**(少画东西)。

### 密度规则复用了 Tier 0 的成果

`showAllSymbol: 'auto'` 在标记会挤到一起时,上游「跟随类目轴的标签间隔策略」。
那个间隔布局阶段早算好了(第 15 项的 `LabelStep`),所以是**取来用**,不是再猜一遍。
判据也照抄:`|轴像素跨度| / 类目数`,符号尺寸 × 1.5 超过它就算挤。
连它读 `symbolSize[1]`(横向类目轴读**高度**)这个看着像 bug 的选择也照抄了,并在注释里标出来。

### 变异测试:11 + 3

第一轮 11 个跑掉 3 个:

- **`showSymbol` / `showAllSymbol` 从来没被从 option 里读出来测过**——
  所有标记测试都是手工塞字段。**同一个读取器、同一个洞、第二次**。
- **没有任何断言说折线的标记是「描边」的**。默认是 emptyCircle,
  「改成填充」的变异体把每个环变成实心点,整个套件没反应。
- 第三个是**我的变异体设计错了**:它调了一次 `AList.Element` 然后把结果扔掉,
  等于什么都没改。重新瞄准成把标记的 Z2 压到线下面,一枪毙命。

### 变异测试之后必须重编,再跑全量

跑完变异测试直接跑全量,红了一条 `TestALineWearsAMarkerOnEveryPoint`——
而同一条测试单跑是绿的。**原因是收割机把源码还原了,可执行文件却还是最后一个变异体编出来的。**
那个变异体正是「把标记压到线下面」,所以断言「先画线」当然红。

看起来完全像一次真实回归:全量红、单跑绿,最容易得出「偶发」的结论。
重编之后 7030 个测试 0 失败。**收割机内部有 BUILD-STALE 检查,但那只保护它自己的循环;
它跑完之后手动跑全量的人不在保护范围内。规矩:变异测试之后先 lazbuild,再跑全量。**

### 过程中的一个教训

我用文本模式批量替换调用点,**打中了两个柱状测试**(同样的调用形状)。
没有在坏改动上打补丁,而是 `git checkout` 回滚重做,改成**按过程名定位**——
先找到过程的起止,再在那个区间里替换,这样一次编辑不可能溢出到邻居。

---

## 39. Tier 1 第六批:饼图,第一个不在坐标系上的系列(2026-09-10)

前五批的每一条数据都是**轴把它映射成了一个点**。饼图没有轴:
它的几何来自**自己那个盒子里的圆心和半径**,角度来自值占总和的比例。
所以它不能走 `TyBuildSeriesMarks`——那个入口第一行就要求一个直角坐标系和两根轴——
而是新开一遍 `AdvChart.Pie`,和柱线散点并排进同一个绘制清单。

### 五个照文档做就会错的地方

**一、两个百分比的基数不是同一个数。** `center` 的两个分量分别按视图矩形的
**宽**和**高**算,再加上矩形原点;`radius` 按 `min(宽,高) / 2` 算——**短边的一半**。
方形图上这两套算术给出同一个数,只有长方形图能把它们分开,测试就是这么写的。

**二、默认半径,源码是 `[0, '50%']`,文档是 `[0, '75%']`。**
`PieSeries.ts:229` 和 `echarts-doc/en/option/series/pie.md:329` 直接矛盾,
而我们的 option 目录抄的是文档。差 1.5 倍的饼画在图上看着完全合理,
不对着源码根本发现不了。这是目录第 9 处与源码不符。

**三、角度是取反的。** option 里的 `startAngle` 是数学约定(从三点钟逆时针),
布局把它取反成画布弧度(y 向下、递增即顺时针)。默认 90 于是成了 `-Pi/2`,十二点钟。
少一个负号,整张饼镜像翻转,而**单色饼看不出来**。

**四、重分配那一遍不是边界情况。** `restAngle` 从整个扫掠角起算,只在扇区被
`minAngle` 顶住时才减。所以「有扇区受限」这个判断 `restAngle < 2*Pi`,
对**任何不走满一圈的饼**都成立——半圆环也算。第一遍是按整圈分的角度,
第二遍才把它们压进那半圈。把它当边界情况跳过,半圆环就画成整圆压在自己的标签上。

**五、负值是被删掉的,不是被钳到零。** `negativeDataFilter` 是布局之前跑的
processor,那一行数据整个消失:不占角度、不进总和、连位置都不占。
NaN 不一样——它**留在原位**,所以等角分支会在它那里留一个缺口。

### 一个在真实代码里必须加护栏的地方

第二遍里 `unitRadian = restAngle / valueSumLargerThanMinAngle`。
当所有扇区都被 `minAngle` 顶住时分母是 0——JavaScript 给 Infinity,
而紧接着的三目运算把每个扇区都判进「被顶住」分支,那个 Infinity 从来没被读过。
Free Pascal 会直接抛异常。**加的是除法的护栏,不是行为的改动**,注释里写清楚了。

### 变异测试:32 个,跑掉 2 个

- **`showEmptyCircle` 从来没被从 option 里关掉过**——测试是直接改记录字段的。
  **同一个读取器、同一个洞、第三次**(前两次是 §38 的 `showSymbol`、更早的 symbol)。
  补的测试把 `minShowLabelAngle` / `percentPrecision` / `roseType: true` / `center: "center"`
  一起从 option 里读出来断言。
- **modPI2 的那个四舍五入是等价变异体。** zrender 的注释说「按 N 取模比按 PI 稳」,
  我照抄了,还差点在注释里把它写成「这样整圈就精确了」。
  **量了一下**:360 个整度起始角里,带舍入 273 个落在精确整圈上,不带舍入 215 个——
  更好,但不是保证,而默认的 90 两种都精确。落不到的那些差 7×10^15 分之一,
  会走进第二遍,而第二遍算出来的角度也只差同一个量级。**记下来,不追。**

### `TySeriesTypeHasRenderer` 现在要覆盖两条画法

编辑器的「全清」那一行只问一个问题:**这个系列会不会出现在屏幕上**。
饼图不经过 `Marks`,所以那个函数得加第二张表。
第二张表就是第二个会漂移的东西——而且 `Marks` 里那条
「公开答案和实际绘制一致」的循环**管不了这一半**,它驱动的正是饼图不走的那个入口。
真正守住它的是控件层数像素的那条测试,注释里指名写了。

顺带:`test.advchart.diagnose` 里那条「某类型还没有渲染器」的测试第二次搬家
(scatter → pie → funnel)。它钉的是**规则**,类型只是当下的例子;
它变红就是又有一种类型能画了的提醒。

---

## 40. Tier 1 第七批:四角圆角、背景条、裁剪(2026-09-10)

三条都是柱状图的,而且互相牵扯,所以一批做完。

### 圆角从一个数变成四个

`borderRadius: [8, 8, 0, 0]`——只在离开轴的那一头圆——是画廊里最常见的写法,
而我们的读取器只认标量,数组形式**被接受然后被忽略**。

短形式不是「补零」,这是最容易想当然的地方(roundRect.ts:30-55):
`[a]` 是四个角,`[a,b]` 是**对角线**,`[a,b,c]` 让右上和左下**共用中间那个**。
按「剩下的补零」读,圆的是错的角,柱子看着像倒过来了。

钳位也是**按共边的一对、成比例缩**(roundRect.ts:57-76),不是各自钳到短边一半:
40 宽的框上 30 和 10 的两个角保持 3:1,出来是 30 和 10,不是 20 和 10。

**钳位放在构造函数里**,和扇区角度归一化同一个理由:命中测试也读这条记录,
一个形状对两个读者意思不同,就是指针替不存在的墨水应答的由来。
于是渲染器改成自己描四段弧——`RoundRectPath` 只收一个半径,画不出只圆上面的柱子。

### 背景条

`showBackground` 画的是柱子自己的那条带,**沿值轴铺满整个绘图区**。
silent,而且**先于**柱子入清单——上游给它和柱子同一个 z2,靠插入顺序决定前后,
我们这个清单的并列规则一样。

颜色**不抄上游写死的 rgba(180,180,180,0.2)**:那在深色皮肤上是一条灰白带。
给它自己的主题键。

**和上游不一致的一处,写在注释里**:数据有洞的那一格没有背景条。
带是从这条数据自己的格子里读的,NaN 没有格子;上游是从布局阶段读的,那里还留着。

### 裁剪

`clip` 默认 true。上游的做法是**相交矩形**(clip.cartesian2d),不是设裁剪路径——
所以柱子仍然是一个真矩形,命中测试和墨水仍然对得上。照抄这个做法,理由相同。
放在 `barMinHeight` **之后**,否则最小高度会把刚裁掉的又推回去。

### 变异测试:30 个,活了 9 个,其中 8 个是真窟窿

- **圆角矩形的渲染侧一条测试都没有**。三个变异体活着:整个描成直角矩形、
  某一段弧反向、少画一个角。7000 条测试里没有一条问过「圆角矩形画出来长什么样」。
  补的是一条四个角**各不相同**的墨水/命中扫描——任意两个角相同,
  张冠李戴的变异体照样画对。
- **钳位测试分不清宽和高**:框是 40×200 且只设了上面两个角,第三个 Fit 从来没触发。
- **右到左的矩形从来没有被构造过**,归一化没测。
- **直角的角从来没有被问过容差**:半径为 0 时,那个 `r > 0` 守卫正是让对角方向
  也享受容差的东西。
- **裁剪只测了近边**:竖着的夹具只可能从上面溢出。转成横的,同样的溢出就走远边。
- 还有一个是我自己刚写下的死代码:`TySeriesVisual` 里的 `Result.Bar.Clip := True`。
  `ColumnFor` 对未求解的列**整个不看**,转手去问求解器,所以那行看着像护栏、
  一次都没被读过。**删掉,并在原处写明为什么**。

补完之后重跑:30 个全灭。

### 一个下批要用的上游 bug

`getSectorCornerRadius` 里 `Math.abs(shape.r || 0 - shape.r0 || 0)`——
JS 的优先级让它读成 `r || (0 - r0) || 0`,r 非零时结果就是 **r**,不是环的厚度。
我用 node 跑过确认:r=80、r0=30 得 80,不是 50。
所以百分比形式的 `borderRadius` 在扇区上是**外半径的百分比**。照抄,并标注。

---

## 41. Tier 1 第八批:扇区的圆角(2026-09-10)

`pie-borderRadius` 和 `pie-padAngle` 都要它,后面极坐标柱状也要。
这是 zrender 的 `roundSector`(其实是 d3 的 arc),一百来行三角。

### 路径改成「一串图元」而不是一串画笔调用

圆角扇区的算术在像素里根本没法查是哪一步错了。
所以 `TySectorPath` 返回 moveTo/lineTo/arc/close 的列表,测试直接读它,
渲染器只负责回放。**顺带把所有扇区统一到这一条路径上**——圆角与否都走它,
两条路径就是两个必须保持一致的东西。

### 扇区的圆角规则和矩形的不是同一套

这是这一批最容易栽的地方,两套规则长得一模一样:

| 写法 | 矩形 | 扇区 |
|---|---|---|
| `5` | 四个角 | 四个角 |
| `[5]` | 四个角 | **只有内侧两个** |
| `[5,10]` | 对角线 | **内侧一对、外侧一对** |
| `[5,10,15]` | 右上左下共用中间 | **最后一个覆盖外侧两个** |

顺序也不同:扇区是 **内起、内止、外起、外止**,从里往外。
拿矩形的规则读扇区,一个普通圆环会**圆了洞、方了边**,正好反过来。
两套规则各自的测试里都点名了另一套。

另外 ECharts 在交给 zrender 之前会把**标量**展开成 `[cr,cr,cr,cr]`,
所以 `borderRadius: 8` 和 `borderRadius: [8]` 在饼图上是**两回事**。

### 两个互相独立的上限

一是**不超过环厚的一半**,否则同一条径向边上的两个角在中间碰头、扇区翻过来。
二是**窄扇区还有第二个上限**:不到半圈时两条径向边会收拢,
能塞进环厚的角未必塞得进夹角。饼图里的细条是常态不是特例。
第二个上限被 `arc < Pi` 门控,这个门是有用的——去掉它会把本来放得下的角削掉。

### 一个照抄的上游 bug

`sectorHelper.ts:37` 的 `Math.abs(shape.r || 0 - shape.r0 || 0)`:
`-` 比 `||` 紧,读成 `r || (0 - r0) || 0`,r 非零就直接是 r。
我用 node 跑过:r=80、r0=30 得 **80**,不是名字 `dr` 暗示的 50。
所以百分比的 `borderRadius` 在扇区上是**外半径的百分比**。
照抄——「做个合理的事情」会让每一个圆环都和被对比的那张图不一样。

### 变异测试:19 个,第一轮活了 6 个,而且全是同一个盲点

**测试只数弧的条数、只读它的半径,从来没问过角画在哪。**
把内外顺序对调、挑错切圆、丢掉偏移的符号、外环用内环的公式——
这四个**画出来的弧条数和半径全都对**。

- 定位的判据:半径 cr 的角**内切**于外沿,所以圆心离扇区中心正好 `radius - cr`;
  内侧的角朝洞里鼓,圆心在 `innerRadius + cr`。
- 但**光靠距离还不够**:切圆有两个,**两个都内切**——这正是要挑一个的原因。
  它们的区别是**在环上的角位置**:该留的那个在扫掠范围内(0.143 rad),
  另一个在 2.998 rad,差不多在饼的对面。加上角度断言才杀掉。
- 窄扇区上限也从「比原来小」改成了确切的数:`radius/(a+1)` = 3.022137。
  「比原来小」对用错公式的版本(3.269)同样成立。

### 又一个我自己写下的死参数

`CornerTangents` 的 `clockwise` 参数,唯一作用是垂直偏移的符号;
而唯一的调用者 `TySectorPath` 拿到的形状角度**已经归一化成正向**,
所以每个调用点传的都是 True,那个分支一次都没走过。
**去掉参数、内联**——角往哪边鼓仍然表达得出来,用上游自己的办法:内侧传负半径。
去掉之后那个变异体才真的会动东西。

### 命中测试没跟上,写在原处

`SectorContains` 仍然测的是完整圆环,所以指针在被削掉的角外面一点会被答「是」。
误差被角半径限住,而角半径又被环厚的一半限住,而且**错在宽容的一侧**——
一个命中区域该错的方向。要精确就得把整条路径也搬进命中测试,
为了让 hover 更难命中一点,不值。

---

## 42. Tier 1 第九批:标题,以及盒子求解器长出 margin(2026-09-10)

按语料排的:244 个能转换的官方示例里,`label` 114、`title` 114、`legend` 109。
标题是这三个里最小的一个,而且它是**第一个既不是坐标系也不是系列的组件**。

### 它不占地方

标题浮在容器上,**不挤任何东西**。这是上游的安排不是简化:两个组件互相挤,
就得吵一个顺序出来;ECharts 的办法是每个组件都拿整个容器,再给合适的默认值。
grid 默认的 top 间隙本来就是给它留的。

### 盒子求解器长出 margin

组件的 `padding` 是**盒子外面**的空——getLayoutRect 就叫它 margin——
title 和 legend 都靠它定位。加进**唯一那个求解器**,而不是在旁边再写一个。
每个分支在 margin 为 0 时都退化成原来的样子,这也是它能加进去而不是加旁边的原因。

**居中那一支不加 margin 项**:上游写 `extent/2 - size/2 - marginStart`,
出来的时候再把 marginStart 加回去,两者抵消——居中的盒子是相对**容器**居中,
不是相对剩下的空间。这个抵消很容易在"整理代码"时弄丢。

### 四个边的关键字不是 parsePercent 解的

`left: 'right'` **不是**「左边缘在 100% 处」——那是 parsePercent 单独给的答案,
会把整块推到容器外面。它的意思是「靠右」:**钉住的是右边缘**,左边是自由的。
上游在 getLayoutRect 的 switch 里处理,和百分比是两条路。

顺带两个后果:`left: 'right'` 才是把标题放右边的惯用写法;
而 `right: 10` 单独写**不会移动它**——默认的 `left: 'center'` 还在,而 switch 先看 left。

### 一个照抄的怪处

`textAlign` 只在**没给**的时候才从 `left`/`right` 推,而这个推导**同时会移动盒子**:
右对齐移一整个宽度,居中移一半。显式写了 textAlign 就不移。
所以 `left: 'center'` 和 `left: 'center', textAlign: 'center'` 是**两张不同的图**。
照抄了,因为第二种正是别人觉得第一种不对时会去写的东西,silently 让它们一样会让人惊讶两次。

### 一处有意不照抄:字号

上游是写死的 18px 粗体 + 12px。这里走**本库自己的字号刻度**
(`--font-size-title` + 粗体 / `--font-size-base` + muted)。
理由是密度体系归 density-scale 那条线管,18px 的标题压在 9px 的轴标签上像贴上去的。
皮肤想要上游的比例,直接改 `TyAdvChartTitle` 这个键就是了。

### 变异测试:24 个,活了 7 个,6 个是同一种盲点

**断言从来没让被测的东西变化过**:

- **对称的 margin** 分不出「相对容器居中」和「相对剩下的空间居中」——都是 175。
  换成 `[7, 3, 7, 11]` 才分得开。
- **一个值的 padding** 分不出 CSS 简写形式。要 `[7, 3]`。
- **left 和 right 的关键字一致**时,先读哪个都一样。要让它们不一致。
- **整块的高度**没有任何断言读到:副标题的偏移是从标题高度直接算的,
  所以「算整块高度时忘了第二行」两行还是画在对的地方,只有边框短了一截。
- **`left: null`** 在我修关键字的时候从测试里掉出去了,清默认值这条没测。

第 7 个是我自己瞄错了变异体:改的是副标题的**字体名**不是颜色,同一套字体下看不见。

### 最后一个变异体是我自己写的重复

`TyTitleSpecDefault` 既钉了 `Box.Left := TyBoxCentre` 又设了 `LeftWord := 'center'`,
而读取器末尾的关键字 switch 会**从词再推一遍并覆盖掉它**。
所以破坏前者在任何会画出来的路径上都没有影响。
**抽成 `ApplyEdgeWords`,默认值和读取器都调它**——一处权威,调两次。

### 「单跑绿、全量红」又来了一次,这次不是二进制陈旧

副标题颜色那条断言我先写成「第 30 行以下没有红色」。**单跑绿,全量红。**
真因是标题自己的下伸部就落在那附近,具体落在哪取决于进程最后拿到的是哪套字体。
改成**「红色的像素数没有变多」**——标题在两次渲染里位置相同,所以它的红是同一个数——
就不需要对字形结束在哪有任何意见了。

**判据仍然是那条:先重编。重编之后还红,才去看断言本身。**

---

## 43. Tier 1 第十批:标签引擎(2026-09-11)

244 个已转换的官方示例里 111 个带 `label`,是剩下的最大视觉缺口。

### 座位设计:三个角度独立论证,结论一致

跑了一个三方评审:「新增一种 shape kind」「另开一条列表」「挂在 element 上」。
**三个都收敛到同一处**——连主张新增 shape kind 的那个都说**载荷应该放在 element 上**:

`AdvChart.Shape` 是纯命中测试层,**故意不引入 measurer**,`TyShapeBounds` 必须只靠记录本身作答。
一个装着字符串和字号的 shape kind 会让它回答一个它算不出来的问题。

所以:**标记声明自己的文字,一个纯函数把每条展开成第二个绘制条目,带同一个 datum**。
一条清单、一套顺序、一个答案;而伴生条目的形状是一个**普通矩形**,
shape 层完全理解它——墨水和命中测试描述的是同一个矩形。

另外两条路各自输在哪,也记下来了:
- **另开一条列表**:datum 会活在两个结构里、按两套规则排序,悬停柱子和悬停它的数字可能报出不同的行。
- **一个条目同时装形状和文字**:外置标签会把 bounds 撑大一百像素,
  `TyShapeContains` 会在扇区和标签之间那片空白里答「是」——正是 shape 层的头注释要防的那件事。

### 四个照文档做就会错的地方

- **未知的 position 不是 `inside`**。zrender 的 switch **没有 default 分支**,
  所以不认识的名字落在宿主的**左上角**。悄悄替换成默认值,会把上游会显示出来的拼写错误藏起来。
- **`distance` 在默认位置下什么都不做**。`inside` 是唯一没有 distance 项的位置,而它是默认值。
  第一次碰到像 bug,手最容易伸过去「修」。
- **数组形式钉的是标签的左上角**。`['50%','50%']` 落点和 `inside` 一样,
  然后文字往右下挂,而不是居中——上游在这里把两个对齐都设成 null,而 null 解析成 left/top。
- **内部标签的墨色是三段亮度表,中间那段最亮**。
  中等深的底要最大对比,接近全黑的底上最亮的墨反而晃眼、柔一点的更好读。
  压成明/暗两段,深色那头就是错的。

另外两条:**`label.offset` 是在定位之后加的**(只抄 switch 会静默丢掉它);
**默认文字柱是「值」、饼是「名字」**——两者用同一个默认值,
每个没写 formatter 的饼图标签都会渲染成一个数字。

### 语料决定了范围

244 棵选项树里**总共只出现五种 token**:`{c}` 48、`{b}` 41、`{a}` 6、`{d}` 2、`{@2012}` 1,
**没有任何带下标的形式**。所以上游先做的那一遍「裸 token 改写成 0 号下标」这里没抄——
那会是一张没人读的表。

### 变异测试:38 个,活了 6 个,5 个是真窟窿

- **亮度边界 `>` vs `>=`**:我原来用灰度试,而**灰 128 是 0.5020、灰 127 是 0.4980**,
  两个都分不开。**alpha 提供了缺的精度**:暴力搜了一遍,有 21 个颜色算出来正好是 0.5,
  `alpha 150, rgb(131,253,255)` 是其中一个。**不是不可达的边界,是我的测试够不着。**
- **`offset` 读进了字段,但没有任何断言说它到达了锚点**——本仓库最常犯的那一类。
- **三个盖章点**(柱、散点、折线的标记)**各自独立**,
  从其中一个删掉,只画另一种的测试完全看不见。
- **每个 series 自己的 spec 要两个 series 才说得清**:只有一个的时候,
  把所有 spec 都归到 0 号槽的 bug 读回来是同一个答案。按「都没有 / 一个 / 两个」排成阶梯,
  中间那档必须严格落在两端之间。

### 第 6 个是等价变异体,但理由和我写的不一样

「边遍历边往清单里追加」——我原来的注释说安全是因为伴生条目自己没有 caption。
**这是错的**:伴生条目是整份拷贝宿主的 caption。
真正挡住它的是**语言**:Pascal 的 `for` 只求值一次上界,
所以 `to AList.Count - 1` 和缓存的局部变量行为完全一样。
那个局部变量防的是**将来有人把它改写成 `while i < AList.Count`**,仅此而已。
**改注释,不改代码**——错的是注释。

### 不在这一批里,而且是有理由的

- **饼图的标签**。`PieView` 把 textConfig 的几何整个丢掉,
  `labelLayout.ts` 自己算 x/y/rotation——所以 `distance` 和 `offset` 在饼上是**真的无效**,
  上面那十三个位置也不适用。**它是另一套算法,单独一批。**
- **九个扇区位置**。它们服务极坐标柱状,而这个移植还没有极坐标渲染器;
  现在建就是一张没人读的表。
- **去重叠**。上游能把压住别人的标签整个隐藏,这里不能,会画成叠在一起。头注释里写明了。

---

## 44. Tier 1 第十一批:饼图的标签(2026-09-11)

上一批把十三个通用位置做完了,而饼图**一个都用不上**:
`pie/labelLayout.ts` 自己算 x/y/rotation。单独一套算法,所以单独一批。

### 审计推翻了我写的一句话,连带上一批的头注释

我写的是「饼图上 `label.distance` 和 `label.offset` 都无效」。**只有 distance 无效。**

两个选项**死法不同,而且只死了一个**:
`PieView` 只重置 `position` 和 `rotation`,而且 `setTextConfig` 是**合并不是替换**——
所以通用读取器早先写进去的 distance 和 offset **都活着进了 zrender**。
`distance` 只在「有 position」那道门**里面**被读,null 的 position 把门关上了;
`offset` 在门**外面**无条件生效。

改了代码,也改了上一批的头注释,并注明是审计发现的。

### 四个照文档做就会错的地方

- **只有 `inside` 和 `inner` 算 inside**。其它任何值——包括 `top` 这种通用锚点,
  包括打错的字——统统落到**外侧**那条路。上游这里没有表,只有两个等值判断和一个 else。
- **`center` 不是内部标签**。它拿的是**外侧的墨色**:
  环形图的中心标签坐在洞上而不是环上,所以对比色规则不适用。
- **引导线只给字面量 `outer` 和 `outside`**。`PieView` 对其它值把线删掉,
  而 `labelLayout` 照样算外侧锚点——所以 `position: 'top'` 会把标签放到环外面、**没有线指着它**。
- **拐点落在半径 `seriesR + length` 的圆上,不是 `sliceR + length`**。
  那个 `+ r - sector.r` 是**南丁格尔玫瑰的补偿**:让每条线都结束在离**系列**外沿同样远的地方,
  标签才排成一列而不是跟着尖刺发散。

另外还有**一个没有任何选项控制、上游也没解释的固定 3 像素法向推移**,
以及切向旋转那个**运算符优先级 bug**——照抄了,并且专门放了一个
「把它改成本意」的变异体,免得以后被人「顺手修正」。

### 不在这一批里

**去重叠求解器**。上游能把外侧标签沿一侧上下挪、在椭圆上重解 x、向邻居借空间、
按视图矩形截断。这些**一个都不需要**就能把**一个**标签放对,
而它们**全都**是为了让**几个**标签不打架。头注释里写明:
在它落地之前,密集的饼图外侧标签会叠在一起,而 ECharts 会把它们分开。

### 变异测试:35 个,活了 10 个

**6 个在 `TyBuildPieLabels` 里,而那个函数一条测试都没有**——
我测了摆放(`TyPlacePieLabel`)和选项读取,**从来没测过把摆放变成绘制元素的那一步**。

另外 4 个是同一种盲点,而且这一轮已经见过两次:
**夹具里每一片扇区都指向右边**。右半边所有水平项都是**加**,
所以「把符号整个丢掉」画出来一模一样——`length2` 永远往右、`distanceToLabelLine` 永远加,
两个都看不见。新夹具左右各一片。

还有一个:**无效扇区那道门根本没被走到**。
我传的那个无效 sector 扫掠角是 0,`minShowLabelAngle` 先把它拦下了。
这个区别是要紧的:普通饼图上 NaN 数据**保留环自己的半径**,只有 roseType 下才是 NaN——
所以判据必须是 `Valid`,不能是「半径是不是数」。

补完之后 35 个全灭。

---

## 45. Tier 1 第十二批:图例,画出来的那一半(2026-09-11)

244 个转换过来的例子里有 103 个带 `legend`,比任何别的可选组件都多。
其中 **21 个只写了一个 `legend: {}`**——所以这一批里最要紧的东西是**默认值**,
而生成的目录对其中四个都是错的。

### 目录错的那四个,每一个都能让图例跑到别的地方去

| | 目录 | 源码 |
|---|---|---|
| `left` | `auto` | `'center'` |
| `bottom` | `auto` | `tokens.size.m` = 15 |
| `itemGap` | 10 | **8** |
| `borderWidth` | 1 | **0** |

前两个合起来的效果是:**一个裸的 `legend: {}` 居中贴在底边上方 15 像素处**,
照目录做就会跑到左上角去。`itemGap` 这条连上游自己都矛盾——
`LegendModel` 的 JSDoc 在 defaultOption 上面两行写着 `@default 10`,
下面写的是 `itemGap: 8`。以源码为准。

### 盒子要解两遍,而 `legend.width` 不是宽度

第一遍拿的是「有多少地方」,**只用它的尺寸**,当折行上限;
第二遍才用量出来的尺寸去定位。`zrUtil.defaults` 只填空缺,
而量出来的宽高从来不空缺——所以 **`legend.width` 会被覆盖掉,它只是折行上限**。
上游自己在 `LegendModel.ts:251-254` 写了注释说这件事。

顺带修了 `TySolveBox` 里一个只有图例才会踩到的分支:
**居中但没有尺寸**时,上游不是居中,而是掉进 `left = left || 0` 去填满——
填的是**扣掉 margin 之后**的容器。原来这里返回整个容器,
于是每一行都能比上游多长出一个 padding 才折行。标题永远带着量好的尺寸,踩不到。

### 图标:同一个 createSymbol,两种画法

`TyBuildSymbol` 实现的是**数据点**的语义:上游在单位盒里建形状,
再按 `(symbolSize[0]/2, symbolSize[1]/2)` 非均匀缩放。图例图标不缩放,
**真盒子直接进形状构造器**,于是那些 `Math.min(w, h)` 终于起作用了:

- `circle` 在 25x14 里是**半径 7 的正圆**,不是椭圆;
- `square` 取 `min(w,h)` 而且**保留盒子左上角**,于是是一个贴着左边的 14x14;
- `roundRect` 两边一样。

所以新加了 `TyBuildSymbolInBox`。同一个源码,两张图,两个函数。

### 顺手改掉了一条本来就错的规则

**认不出来的符号名画的是 rect,不是什么都不画。**
`SymbolClz.buildPath` 查不到代理就把 `symbolType` 换成 `'rect'` 再画。
这个端口原来答 `tsyNone`,一条老测试还把它钉死了("an unknown name draws nothing")。
图例是让它露出来的地方:**`legend.icon: 'inherit'` 放在柱状图上走的正是这条路**,
ECharts 在那里画一个直角方块。

### 一行图例的行高不是 itemHeight

`boxLayout` 的换行推进量是**正在收尾那一行里最高的那一项的包围盒高度**,
加一个 itemGap。包围盒是图标和文字的并集,**还要算上笔画外扩**——
zrender 给描边路径的包围盒每边加半个笔宽。
(它还有一条「没有填充时至少加半个 `strokeContainThreshold`=5」的规则,
但**图例图标永远够不到它**:zrender 路径的默认 style 自带 `fill: '#000'`,
`setStyle` 只会往上盖不会删,所以图例图标一律有填充。头注释里写明了,省得以后被当成漏抄。)

于是一行折线图例比一行柱状图例**矮那么一点点**:
折线的「一横加一个圈」高 13.2,柱状的圆角矩形正好 14。这一批照抄了。

还有那个 `(-next.x + this.x)` 修正项:`x` 是一项的**原点**落在哪,不是墨迹从哪开始。
修正项把两者换算过来,于是**相邻两个包围盒之间永远正好差一个 itemGap**,
不管哪一项往自己原点外面挂多远。右对齐的图例每一项都往左挂 `5 + 文字宽`,
是这条规则唯一看得见的地方——夹具里专门放了一条。

### 选中状态是**第一帧**的事,不是点击的事

`selectedMode: 'single'` 由 `optionUpdated` 在**加载时**强制只留一个选中。
所以一个只会画的图例,在**没人点任何东西之前**就已经画错了——
语料里有 4 个例子是这样。同理 `legend.selected`:

- 判据是 `!(has(name) && !selected[name])`,是 JavaScript——
  **null、0、空字符串全都算关**,不只是 `false`;
- 还有第二个没人写进文档的条件:名字得是图表**拿得出来**的。
  `legend.data` 里写一个不存在的系列名,ECharts 照画,画成灰的。

### 不在这一批里(头注释里逐条写明了)

- **点击**。它要一条鼠标路径、一个命中测试、以及每次切换后的整轮重排,
  那是交互那一行的事。这里做的是点击之前就已经定下来的全部状态。
- **过滤**。这里灰掉的项只是灰掉,它的系列照画。让它消失要在取轴范围之前过滤数据,
  是下一个提交。
- **selector 按钮**和 **`type: 'scroll'`**。两个都是控件,**不能按的控件比没有更糟**,
  跟点击一起落地。语料里有 2 个例子要 scroll,现在给它们一个会溢出的普通图例。
- **选项里的颜色**。`textStyle.color`、`inactiveColor` 这些一个都没读,
  因为这个端口到今天为止**没有任何地方从选项里读颜色**——`color` 没有,
  `series.itemStyle.color` 也没有。颜色解析器跟调色板那一行一起来,一次服务所有人。
  先读一个块,就会出现「图例听 `legend.textStyle.color`、旁边的系列不听
  `series.itemStyle.color`」这种事。

### 变异测试:三轮 95 个,等价的 1 个

第一轮 65 个,活了 19 个。**存活的一多半是同一种形状**,还是上一批那条教训:
**夹具里被测的那个量没变化过**。

- 两个同名的图例项——**去重把它吃掉了**,于是「三项换行」的夹具只有两项。
  夹具自己的一个特性,把夹具本身废了。
- `right: 10` 是**数字不是关键字**,所以「left 先还是 right 先」两种读法答案一样。
  要 `{left: 'left', right: 'right'}` 两边都写关键字才看得见。
- 边界比较 `>` 和 `>=`:两项 100、上限 100 的夹具**两种读法画出来一模一样**——
  第一项一旦挤爆,后面每一项都换行。要把上限放宽到 208,**让第二项正好落在线上**。
- 折行修正项 `(-next.x + this.x)`:所有项 rect.x 都是 0 就分不出。要右对齐、
  而且两个名字**长度不同**。
- 竖排图例从来没测过会不会换列。

另外**三个是「建好没接线」**:`TyLegendDefaultIcon` / `TyLegendDrawsOwnIcon`
单元测试测得好好的,**控件怎么用它们没有任何测试**——控件那一层从来没有一条
折线系列的图例。补了一条真渲染的:量图例带的墨迹包围盒有多宽(有没有那一横)、
再数中间那一列断了几段(标记是环还是实心点)。

第一轮里还顺出两处**代码本身该改的**:

- **80% 那个数写了两遍**(量的时候一次、画的时候一次),变异掉量的那一份根本看不出来。
  变成一个常量。
- **图标上色的二十行写了两遍**(折线自己那个标记一份、通用图标一份,只差一个盒子),
  折成一个内嵌函数。

第二轮 23 个活了 3 个,第三轮 7 个**全灭**。

最后**留下一个等价变异体**并在原处注明:单选模式里那个 `Break`。
`SelectOnly` 已经把所有项关掉了,后面每一次 `IsSel` 都答假,循环本来就走不动。
`Break` 是上游的,留着是因为它**把「第一个选中的赢」这条规则说出了口**,
而不是让人从两行上面的副作用里推。

### 一个自己踩的坑:探针量错了东西

给折线图例写的第一版探针量「最长的一段连续红像素」,以为那一横有 25 长。
跑出来是 10。**不是代码错了,是那一横中间被挖掉了**:
环画在横线之上,而 `empty` 图标是**拿图表底色填**的,
所以那一横活下来的是左右两截。上游画出来也是这样,原因一模一样。

真正分得开三张图的是**墨迹包围盒的宽度**(有没有横线)
和**正中那一列断成几段**(标记是不是环)。

---

## 46. Tier 1 第十二批(下):关掉的那一项真的消失(2026-09-11)

上一半把图例画出来了,关掉的项只是变灰——**系列照画**。这一半让它真的不见,
而且让**剩下的东西重新排**:轴重新取范围、柱子变宽、饼重新分角度。

### 一个标记,不是一次压缩

给 `TTySeriesBinding` 加了一个 `Hidden`。**不压缩数组**,理由有三条,
其中第三条是这个仓库自己早就写下的:

1. 图例本身要看得见被关掉的项——灰着的项还得有自己的图标形状和自己的颜色。
   压缩掉就等于要维护两份,而图例读的是没压缩的那一份。
2. 下游每个单元本来就是「守卫形」的(未解析的 binding、越界的槽、缺列),
   加一个标记只是给已有的守卫多一个从句。
3. **上游也是标记**:`filterSeries` 改写的是 `_seriesIndices`,
   series 数组一根手指都不碰;`eachRawSeries` 走的是没动过的那份,图例故意用它。
   而这个端口的 `TyBindSeries` 早就为**同一个理由**决定过一次:
   一个解析失败的系列**保留槽位**,注释写着「留洞会让后面每个系列重新编号,
   把回调或者命中测试指着的东西悄悄挪走」。

### 三处跳过,不是一处

映射的第一版说「改索引一处就够了」,审计把它推翻了:

- **索引**(`TyIndexSeries`)跳过 → 轴范围和柱宽**自动**跟着变,
  因为这两个的population都只从索引里取,别处没有;
- **堆叠**(`TySolveStacks`)**不吃索引**,得单独加一个从句;
- **饼**根本不在索引里(它 `HasAxes=False`,`Associate` 拒绝 nil 轴),
  而且饼的语义根本不是按槽位。

### 饼是按行过滤的,而且颜色必须钉在原始行上

饼的图例名的是**切片**不是系列,所以过滤走
`TTyDataStore.FilterSelf`——**这个能力早就建好了,`source/` 里零个调用者**
(5 个调用全在 tests/,「建好没接线」第 10 次)。
它跟饼布局里那个负值过滤**天然复合**,而且顺序正好是上游的:
`dataFilter` 先注册、`negativeDataFilter` 后注册。

**真正要紧的是颜色。** 原来 `PieVisual` 是拿**扇区序号**去取色的,
而扇区序号跟数据行号**早就不等**了——负值过滤已经压缩过一次。
再叠一层图例过滤,**每关掉一片、剩下的每一片都会换颜色**,
这是这个提交最扎眼的失败方式。改成按 `Sectors[k].RawIndex` 取色。
上游为**同一个理由**写了同一句注释:
「Iterate on data before filtered. To make sure color from palette can be
consistent when toggling legend.」

顺带修了图例那边的对称问题:切片色卡也改成按原始行取。

### 一个会让整张图变白的陷阱

**不能写 `hidden := not IsSelected(name)`。**
`TyLegendSelected` 答 False 有**两个**不同的原因——被关掉了,
或者**这个名字图表根本拿不出来**(这是没写 `name` 的系列会走到的那条)。
只有第一个是「别画了」的指令。照着写,**一张没有任何 `series.name` 的图
在出现图例的那一刻整个变白**。

上游不中招纯属命名的巧合:每个系列都有自动生成的唯一名字,
而且**无条件**进 `_availableNames`,于是 `isSelected` 找得到它、
`selected` 里又没有它的键。这个端口没有那种名字,所以规则得**明写**:
`TyLegendHides` ——「这个图例**列了**这个名字,而且把它关掉了」。

### 还补了一条上游有、端口漏了的

`LegendNames` 走到饼时推完切片名就 `Continue` 了,
于是**饼自己的系列名两个列表都没进**。上游是**每个 raw series 的名字
无条件先进 available**,然后才看 provider。差别在作者把饼的系列名
写进 `legend.data` 的时候露出来:名字不在 available 里,那一项就会灰掉,
理由跟选项没有任何关系。补上 `PushA`(只进 available,不进 potential)。

### 变异测试:两轮 26 个,等价的 1 个

第一轮 19 个活了 7 个,**七个里有六个是「这条规则压根没测过」**:

- **没名字的系列**和**换行标记**——两个守卫**互相遮住了对方**:
  换行项的名字就是空串,而空串又被第一个守卫先挡掉,
  所以单独去掉任何一个都看不出来。要**手搓一个 `Newline=False` 的空名字条目**
  才能钉住第一个;要造一个**名字本身就是换行符**的条目(`legend.data` 里写一个
  转义的换行)才能钉住第二个。
  `TyLegendHides` 是公开函数,测的是它的**契约**,不是当前调用图。
- **堆叠里被藏掉的那一项**:轴范围和柱宽都从索引里取,索引跳过就够了;
  **堆叠不吃索引**,是唯一需要单独一条的。夹具是两根各 5 的堆叠柱,
  藏掉下面那根,上面那根必须**落到底**——它的颜色出现在它从没去过的地方。
- **饼自己的系列名**两条(要在 available 里、不能进 potential)。
  后面那条第一次没杀掉是因为**我的阈值给松了**:正确是 49 像素宽,
  变异体 206,而我写的是 `< 260`。量一次两边再定界。
- **按原始行取名字的 getter**:只有 store 被过滤过才分得出来,
  所以测试得**先过滤再问**。

### 一个藏在「看不见的症状」后面的真缺陷

「饼的图例色卡按 view 还是按 raw 取」这条活下来的时候我去查了,
结果发现**代码本来就是错的**:`LegendSources` 跑在 Relayout 里,
也就是**过滤之后**——它遍历的那个 view 里已经没有被关掉的切片了,
于是它**恰恰找不到它要描述的那些项**。

没人发现是因为**症状不可见**:灰掉的项用的是 inactive 墨色,
饼的图标又一律落到 roundRect,所以 `Found` 是真是假画出来一模一样。
改成走原始行之后,这条变异体就**真的等价**了——已在原处注明,
并写清它什么时候会不再等价(灰掉的项一旦保留任何自己的东西)。

---

## 47. Tier 1 第十三批:一张表,和哪一列喂哪个坐标(2026-09-11)

`series.data` 说的是「值是什么」,而且**按位置**说明每个值是哪个坐标。
`dataset` 只说值是什么——一张所有系列共用的表;`encode` 说哪一列喂哪个坐标。
这正是数据在被人塞进图表库之前的样子,也就是这个特性存在的理由。

244 个例子里 14 个用 `dataset`、21 个用 `encode`;其中 7 个 dataset 例子
这一批做完就够了。

### 默认 encode 是一个**会走的计数器**,不是「系列序号→列号」

这是移植最容易做错的一条。上游给每个 `(dataset, seriesLayoutBy)` 存一个游标,
**每个要默认值的系列都会把它往前推**——所以一张表上的三根柱子拿到的是
第 1、2、3 列,而不是都拿第 1 列。

两种走法,由「这个系列**有没有**序数坐标」决定,而不是由哪根轴决定:

- **value way**(一个序数坐标都没有):每个系列连取 `coordDim` 个列。
  六列表上三个散点拿 (0,1)、(2,3)、(4,5)。
- **category way**(有):**第一个**序数坐标固定取第 0 列并被所有系列共享,
  其余的从「刚好越过它」的位置开始走。

而且**类目列永远是第 0 列,不管它在哪根轴上**。类目在 y 轴时,
仍然是 y 取第 0 列、x 去走——规则说的是坐标列表的顺序,不是屏幕。

### 写了一半的 `encode` 会把默认器整个关掉

默认器只在**完全没有** `encode` 时才跑。所以 `encode: { x: 0 }` 不是
「x 我自己定、y 你来」——它让 y **没人填**。是替换,不是合并。

### `sourceHeader: 'auto'` 的真实判据,和它上面那句注释不一样

代码要求**每一个被看到的单元都是字符串**才算表头:字符串只在「还没人表态」时
投一票,数字则**无条件**把答案压成「没有表头」。而它正上方的注释写的是
「第一行大部分是字符串就是表头」,还专门讨论了「5 个字符串 1 个数字」的情形——
**注释和它注释的代码不一致**,以代码为准。

另外:`null` 和字符串 `'-'` 会被跳过,而且**最多只看 10 个单元**——
所以第 12 列上的那个数字是看不见的,还会被转成字符串当成维度名。

### 一张表不是只读一遍

`seriesLayoutBy`、`sourceHeader`、`dimensions` **三个都可以写在系列上**,
而且**系列优先**。于是两个系列可以把同一张表**朝两个方向读**,
用两套表头规则、拿到两套维度名。语料里 `dataset-series-layout-by` 就是
七根柱子共用一张表、其中三根自己转置,而 dataset 对此一个字没说。

所以 source 是**按系列**解析的,不是按 dataset 解析一次就完事。
(我第一版就是按 dataset 解析的,写测试挑例子的时候才发现。)

### 一批小规则,每一条都在某处是承重的

- encode 里**数字是下标、字符串是名字**,包括**看起来像数字的字符串**——
  `encode: { y: '2016' }` 配一张列名是年份的表,走的是按名查找;
- 列表只取**第一项**;`-1` 让那个坐标**彻底没人填**;
- 系列**自己有 `data` 就不看表**,而且 `data: []` **也算自己有**;
- `datasetIndex` 指向不存在的表**解析成「没有表」**,不回落到第一张——
  回落就等于把别人的数字画在这个系列的名下;
- **没写 `name` 的系列用它读的那一列的列名当自己的名字**。
  这是 dataset 图上 `legend: {}` 唯一有东西可列的原因。

### 不在这一批里

**`dataset.transform`**。它是一门语言而不是一个设置:一套过滤表达式文法、
一个排序、一个 boxplot 归约器,外加数据集互相串联。14 个里有 6 个用到它。
**上游自己就发布了「有 dataset、没有 transform」的构建**,所以这条线是它先划的。

还有 typed array(过不了 JSON)和列式对象(语料零使用)——两个都能正确识别,
然后答「没有行」。

### 变异测试:三轮 62 个,等价的 1 个

第一轮 50 个活了 6 个,**六个里有五个是「夹具够不到那条规则」**,
而且这一批的形状跟前几批不太一样——**不是对称,是两个答案碰巧一致**:

- **「破折号算不算一票」**:我的夹具里同一行还有别的字符串,已经先表态了。
  能看见这条规则的夹具只有**整行都是破折号**:跳过它 → 没人表态 → 无表头;
  不跳过 → 破折号是字符串 → 有表头。
- **「第一个序数坐标说了算」**:夹具里只有一个序数坐标,
  「第一个」和「最后一个」是同一个。要**两个坐标都是类目**才分得开。
- **「没人认领的坐标」**:我把 y 退出了,而回落目标第 0 列是**文字列**——
  回落过去照样解析成非数、照样画不出来,**两个答案碰巧一致**。
  改成退出 x,回落就落在一个好端端的类目列上,画得出来了。
- **「系列压过 dataset」**:我的夹具只在**系列**上写了那个选项,
  于是把优先级反过来也没区别——**dataset 手里没牌**。
  要两边都写、而且写的不一样。
- **饼的按名默认器**和**按列给行命名**两条:控件层压根没有「饼读表」的用例。

### 这一批自己找出来的一个漏

写「按系列覆盖」的测试时才发现:`seriesLayoutBy`、`sourceHeader`、`dimensions`
**三个都能写在系列上,而且系列优先**。我第一版是**按 dataset 解析一次**的,
语料里 `dataset-series-layout-by` 正好是七根柱子共用一张表、三根自己转置——
按 dataset 解析根本表达不了。改成**按系列**解析。

### 留下的那一个等价体

`TyDetectSourceFormat` 里跳过 null 的那个守卫。fpjson 的 null 是 `TJSONNull`,
直接继承 `TJSONData`,**既不是数组也不是对象**——所以循环里那两个 `is` 判断
本来就会放它过去。守卫留着是因为它**把规则说出了口**:
上游是**故意**跳过 null 的,读代码的人不该为了看懂这一点先去查另一个库的类继承。

## 48. Tier 1 第十四批:一根轴到底画了什么(2026-09-11)

一根 `xAxis: { data: [...] }`、一根 `yAxis: {}`,一句轴配置都没写。
上游对这张图回答了六个问题,三个是、三个否:

| | 轴线 | 刻度 | 分隔线 |
|---|---|---|---|
| 类目 x | **画** | 不画 | 不画 |
| 数值 y | 不画 | 不画 | **画** |

端口六个全画。**一句配置没写就错四个**,而且错在最常见的那张图上——
柱状图看起来是「关在盒子里的柱子」,不是「网格上的柱子」。

这一批之前所有的断言都是绿的,因为它们问的是「轴画出来了吗」。

### `'auto'` 是第三种值,不是 true 的别名

上游只在两个地方写 `'auto'`:轴线和刻度。规则在
`cartesianAxisHelper.ts`:

```
axisLineAutoShow = axisTickAutoShow = false
遍历本 grid 的每个 cartesian:
    若「另一维那根轴」的 scale 是 interval 或 log:
        两个都置 true
        若本轴是 category 且 onBand:axisTickAutoShow = false
```

两处容易错:

**一,遍历的是 cartesian,不是「我这一对」。** 它问的是本 grid 里
*任意一个* cartesian 的对侧轴,不管本轴在不在那个 cartesian 里。

**二,time 不算数轴。** `isIntervalOrLogScale` 就是
`type = 'interval' or type = 'log'` 两句,而 time scale 的 type 是
`'time'`。上游规则上面那行注释写得很直白:"not show axisTick or axisLine
if other axis is category / time"。所以时间轴对面那根数值轴 **不画轴线、
不画刻度**——同一张图上两根轴的答案是反的。

刻度那条 `onBand` 追加子句,就是柱状图类目下面没有刻度的原因:两个 band
中间的一道刻度什么也没指。写 `boundaryGap: false` 刻度就回来了。

### 各类型的默认值(从 `axisDefault.ts` 抄的)

共享块:`axisLine.show true`、`axisTick.show true`、`splitLine.show true`、
`splitArea.show false`。然后:

- **category**:`splitLine.show` 改 false、`axisTick.show` 改 `'auto'`、
  `alignWithLabel false`
- **value**:`axisLine.show` 和 `axisTick.show` 都改 `'auto'`、
  `minorTick.show false`、`minorSplitLine.show false`
- **time**:继承 value,再把 `splitLine.show` 改回 false
- **log**:`defaults({logBase: 10}, valueAxis)` —— 和 value 一模一样,
  所以它 **保留** 分隔线,而且对面那根轴看它算数轴

### 布局和绘制是两半,而它们本来对不上

`TyAxisThickness` 说「图区让出多少」,`TyLayoutAxisLabels` 说「文字放在
让出来的那块里的哪儿」。两个函数写在不同时候。这一批让 thickness 不再为
「没画的刻度」收费之后,placement 还在把标签往外推一个刻度长——**推到了
为它留的那条带子外面**,越过控件边缘。

现在两边用同一句算式,而且都遵守同一条规则:**只为挡在路上的东西收费**。
向内的刻度、向内的标签,外面一律不占。`axisLabel.inside` 配 `axisTick`
向外时,刻度在轴线另一侧、根本不在两者之间,所以也不算。

顺带:`axisLabel.inside` 原来只把地方还了,标签没动——等于「关掉标签,
但字还画在页边距上」。锚点也得跟着翻,不然它从一个在里面的点往外读,
正好骑在刚挪开的那条轴线上。

### 四个照文档做就会错的地方

**一,`-1` 不能当哨兵。** `axisTick.length: -5` 在上游是合法的,负号就是
方向(`tickEndCoord = tickDirection * length`)。用 -1 表示「主题说了算」
会把作者写的每一个负数吞掉,而且没有别的写法。改用 `NaN`。

**二,`GetTicks` 一个数组里装了主次两种刻度。** `Level` 字段区分。
`TickCoords` 整个数组照单全收——于是 `minorTick: { show: true }` 会把
**主** 分隔线也画到每个细分位置上,一道变五道,而且是主样式。
次刻度的画法自己去问 `GetTicks` 并反过来测 `Level`,所以这一处从来没暴露。

**三,`minorTick` 没有 `inside`。** 上游翻的是一个 `tickDirection`,
轴上所有刻度跟着翻。「主刻度朝内、次刻度朝外」不是上游能到达的状态——
而布局已经不给外面留地方了,次刻度会画到别人身上。

**四,`show: false` 的轴必须把地方还回来。** 上游对隐藏的轴 **什么都不建**,
折算收缩时再跳过一次。端口只在 **绘制** 时藏:`yAxis: { show: false }`
不画数字,照样给数字留位置——左边一条空白页边距,而且没法关掉。

### 测试抓出来的那个:画的那一半在读未初始化内存

`PaintAxis` 里 `tickLen` 那段在 `spec` 和 `furn` 赋值 **之前**。两个都是
普通局部变量(record 里只有 Boolean 和 Double,指针是裸指针),FPC 谁也不清零。
于是:

- `axisTick.length: 20` 对画出来的刻度毫无影响(还是主题的 5),
  而 `TyAxisThickness` 已经按 20 留好了地方——留的带子和画的marks对不上
- `axisTick.inside` 的正负号取决于栈上残留的字节
- `spec^.TickLengthLogical` 每画一根轴就解一次未初始化的指针

布局那一半是对的,绘制那一半在读垃圾。**任何关于 plot rect 的断言都看不见
这个差别**——`TestAnInsideTickPointsIntoThePlot` 数像素才数出来。

### 不在这一批里

`onZero`、`offset`、`nameLocation`/`nameGap`/`nameRotate`、
`axisLabel.formatter`、`axisLabel.interval`、`showMinLabel`/`showMaxLabel`、
`lineStyle` 的颜色(等配色那一行)、多根轴。

还有一个 **故意留的偏差**:`splitArea.areaStyle.color` 上游是一个颜色
**列表**,每条带子轮流取,默认两个几乎一样的半透明灰。端口按主题一个
`TyAdvChartSplitArea` 令牌隔一条画一条——在默认值下肉眼等价(等于其中一色
全透明),而「作者自己写颜色列表」属于配色那一行。

### 变异测试:三轮 63 个,最后 0 个存活

第一轮 52 个,活了 4 个,**每一个都指着一样真东西**:

**一,`yIsValue` 那半边从来没承重。** 时间轴只出现在 x 上,所以「另一族里
有没有数轴」的 y 那一次遍历怎么写都一样——补了一条日期在纵轴上的图。

**二,一个真正的等价变异体**,而且是我自己挑错了目标:我变的是
`FurnitureFor` 里那句 **越界检查** `XAxisCount + i <= High(FFurniture)`,
不是真正取值的下标。换成变下标本身,一下子挂了 17 条。

**三和四,两个 minor 门控双双存活**,而原因正是记忆里写过的那句:
「存活的变异体值得查,因为它看不见,可能是因为代码本来就已经悄悄错了。」

`minorTick.show` 同时管着两件事:**要不要算出细分刻度**,和 **要不要画那些
marks**。于是细分刻度不可能在「没人要画它」的时候存在,两个门控怎么变都
不改一个像素。上游 `getMinorTicksCoords` 只读 `minorTick.splitNumber`,
根本不看 `show`——两个 show 是后面分开问的。

拆开之后带出一个本来就有的洞:**`minorSplitLine: { show: true }` 单独写
什么也画不出来**,因为没有细分刻度给它落。

第二轮 9 个(4 个重跑 + 2 个 minor 门控 + 3 个新拆出来的 Series 决策),
活了 2 个:

- minor tick 门控还活着——**我新写的探针看不见它要断言的东西**:次刻度被
  我覆写成绿色,而 `RedRunsDown` 判的是 `red > green + 40`,绿色永远不成立。
  「没画 marks」这条断言是空的,画没画都是 0。改成同一个颜色、靠几何分开:
  次分隔线横跨图区,次刻度挂在图区左边外面。
- `minorTick.splitNumber` 读了但没人断言。

第三轮 2 个,全挂。

### 一个我一度当成 bug 的东西:离屏截图会掉末字

用无头渲染截图验收的时候,每个标签都少最后一个字(`Mon` 成了 `Mo`、
`200` 成了 `20`)。我一开始判成「本来就有的老毛病,下一批修」,**判错了**。

真因是 [[empty-fontname-gotcha]] 的另一面:主题里 **一条 `font-family` 都没有**
(`grep -c` = 0),整库的文字都靠 `TyFallbackFontName`;而它是 GUI 里第一个
Controller 从 `Screen.SystemFont.Name` 填的,**测试夹具故意把
`TyAutoSystemFontFallback` 关掉**以保证无头渲染可复现。所以空字体名只在
截图里出现,example 跑起来是好的。

排查顺序也记一笔:我先后试了「把文字盒子加宽 6」「加高 6」「两边各加 20」——
**全都没变化**,这才说明不是裁剪。真正定性的一步是
`StyleOverride` 里写死一个真字体名,一次就全好了。
**盒子大小改了没反应,就别再往盒子上想。**

## 49. Tier 1 第十五批:作者写的那个颜色(2026-09-11)

在这一批之前,图里每一个颜色都来自 `.tycss` 主题,option 里写的颜色**没有任何
代码读过**——`color: ['#c23531', ...]`,大概是所有人写 ECharts 时最常写的那一行,
在这个端口里什么也不做。

这一批定的规矩:**作者写了的,作者说了算;作者没写的,还是主题说了算。**
轴线、网格、标签这些 chrome 继续归主题;数据的颜色归作者。

### 上游的「颜色语法」不是浏览器那一套

第一个反直觉的发现,而且是审计推翻我的地图才拿到的:
**zrender 的 `parse()` 根本不在绘制路径上。** option 里的颜色字符串是**原样**
交给 `ctx.fillStyle` 的(`canvas/graphic.ts:454`,唯一的门是
`typeof x === 'string' && x !== 'none'`),所以真正解释它的是**浏览器的 CSS 解析器**;
`parse()` 只管派生运算——hover 提亮、插值、图例色卡。

**而端口自己就是光栅器**,后面没有浏览器。所以 `parse()` 的语法就是全部语法:

- 148 个关键字(147 个 CSS Level 3 名字 + `transparent`);`rebeccapurple` **不在里面**
- `#rgb` `#rgba` `#rrggbb` `#rrggbbaa`;半字节加倍就是 ×17,而且 alpha 那位
  `n/15` 和 `(n*17)/255` **逐位相等**,所以 `#abcd` 和 `#aabbccdd` 是同一个数
- `rgb() rgba() hsl() hsla()`,**只认逗号**;`rgb(255 0 0 / 50%)`、`hwb()`、`lab()`、
  `oklch()`、`color-mix()` 上游一概不认,端口认了反而画得出 ECharts 画不出的图

一个**必须**支持的怪形状:`rgba(160,197,232)` **三个参数**。它就写在 ECharts 自己的
parallel 默认值里,坚持四个参数的解析器会在一张原装图上失败。

### 一处故意的偏差:十六进制严格

上游的十六进制走 `parseInt`,**遇到第一个非十六进制字符就停**,而且只校验结果的
**数值范围**。于是 `#12g` 会静悄悄变成 `#001122`,**还进缓存**。
两行上面都挂着上游自己的 `TODO(deanm): Stricter parsing`。

端口这里严格:一个笔误落回主题色——**能看见但讲得通**,而不是一个自信的错答案。

### 色板是一个「按名字记账」的游标,不是下标

第二个照文档做就会错的地方。上游那个函数(`palette.ts:93-127`)的顺序是:

```
名字已经在备忘录里 → 返回它的颜色,一格都不消耗
色板是空的         → 返回「没有」,一格都不消耗
否则取 Idx 那一格,按 NON-EMPTY 的名字记进备忘录,
                    然后 Idx 前进,MODULO 色板长度 —— 这一步不受名字保护
```

四条推论,每一条都能单独看见:

- **两个同名 series 共用一个颜色,而且一共只花一格**
- **`name: ''` 不被记住,但照样花一格**——和上面那条正好相反
- **写了颜色的 series 一格都不花**。上游注释写了为什么:有人把某条 series
  画成透明或当背景,不代表他想让**别的**series 全部换色。
  `series: [{}, {color}, {}]` 是 palette[0]、那个颜色、**palette[1]**
- **`'auto'` 照样花一格**——它的意思就是「色板那个颜色」,得有一个才行

还有一条最容易漏的:**一个不写 `name` 的 series 不是叫 `''`**,
上游给它 `'series' + NUL + 下标`,注释里直说是为了「避免不同 series 同名,
因为 name 会被用在色板上」。留空的话每个匿名 series 都拿第一个颜色。

**被图例关掉的 series 照样占着它那一格。** 这就是「点一下图例、颜色不动」的
全部机制;跳过隐藏的,后面每一条的颜色都会平移。

### 一根折线的颜色来自 `itemStyle`,不是 `lineStyle`

`visualStyleAccessPath` 的原型默认值是 `itemStyle` / `fill`,**只有两个类型覆盖它**
(`lines` 和 `parallel`),**折线不在其中**。所以:

- 写 `lineStyle.color` **不能**阻止一根折线去拿色板的一格
- 它拿到的那个色板颜色**仍然**给了它的符号和它的面积
- `lineStyle.color` 只赢下折线本身那几个像素

另外 boxplot 保留 `itemStyle` 但**用描边画**,所以挡住它色板的是
`itemStyle.borderColor` 而不是 `itemStyle.color`。

### `areaStyle: {}` 是七成的水,不是一块实色

`LineView` 放面积时写的是 `defaults(getAreaStyle(), {fill: visualColor, opacity: 0.7})`,
radar 一样。端口原来默认 1,而且注释还专门写着「上游没有默认值,不透明」——
**注释和上游都是反的**。不透明的面积会盖住它后面堆叠的东西,这是这条错的可见那一半。

顺带:`areaStyle` 一共**六个键、一个描边都没有**,`areaStyle.borderColor`
上游没有任何地方读。

### 不在这一批里

渐变和图案(自己一行)、`decal`、`visualMap`、`brush`、颜色回调、`colorLayer`、
`colorBy: 'data'` 的**独立**游标(饼现在按原始行取同一条色板,顺序对、作用域还没分家)。

一条**明确拒绝**的:**逐数据项的颜色回调**。上游 `dataStyleTask` 里没有 `isFunction`
判断,那个 Function 被原样写进 `style.fill`,过了 `styleHasFill`、没过
`isValidStrokeFillStyle`,于是那个形状用**上一个元素残留的** fillStyle 画出来——
浏览器的事故,不是行为,没有可移植的语义。

### 一个 `'auto'` 的坑,是测试抓出来的

上游对 `'auto'` 的处理有两层,我第一版只做了一层:

```
hasAutoColor = globalStyle.fill === 'auto' || globalStyle.stroke === 'auto'
if (没写颜色 || 回调 || hasAutoColor) { 问色板 }
globalStyle.fill   = (fill   === 'auto') ? 色板那个 : fill
globalStyle.stroke = (stroke === 'auto') ? 色板那个 : stroke
```

两条推论我都漏了:

- **`'auto'` 解析成「色板挑的那个」,不是「这条 series 解析出来的填充色」。**
  `{ color: '#fff', borderColor: 'auto' }` 是**白底 + 色板色的边**,两个数同时存在,
  所以端口得同时留住两个。
- **这一对里任意一半写了 `'auto'`,整条 series 就得去问色板,因而也就花掉一格**——
  哪怕另一半明明白白写了颜色。

抓到它的那条测试本身也是被变异测试逼出来的:在**填充**上,「认识 auto」和
「不认识 auto、当成读不懂的字符串」**结果一样**(都落到色板),所以任何建在填充上的
夹具都分不出来。换到**边框**上两者就分家了:`auto` 画一条色板色的边,读不懂的字符串
等于没写、一条边都没有。

### 一个我自己制造的缺陷,也是变异测试逼出来的

`PieVisual` 一直问 `SeriesColor(原始行号)`。在 `SeriesColor` 还只是主题色阶的时候
这是无害的——色阶是下标的函数,不在乎下标**是什么意思**。等这个函数开始回答
「按 series 解析出来的颜色」之后,**饼的第 0 片拿走了第 0 条 series 的颜色,后面每一片
落回皮肤**:半张饼是作者的色板、半张是主题的。

修法就是把上游的 `colorBy:'data'` 作用域真做出来:饼按**原始行**、**按行序**、
**按切片名字**跑自己那一份游标,被过滤掉的行照样占格。

### 变异测试:三轮 76 个,等价的 4 个

第一轮 52 个活了 17 个——**这一批新面比前一批大得多,测试一开始差得远**。
第二轮补完夹具后 15 个里活 7 个,其中 4 个是真等价:

- **游标那个 `mod` 是多余的**:前进那一步已经取模,下标永远到不了长度
- **`jtNull` 那道门是多余的**:紧跟着的 `jtString` 判断本来就会把 null 挡掉,
  而 `Written := True` 在它之后
- **匿名 series 那个假名字在本端口不承重**:空名字本来就不进备忘录、还照样前进,
  所以 `''` 和 `series+NUL+i` 算出来的颜色一样(上游那里也是同一回事,它那个假名字
  同样是双保险)
- **`dvkText` 那道门是多余的**:非文本的覆盖值 `Text` 是空串,解析本来就会失败

第三轮 6 个全挂。

## 50. Tier 1 第十六批:一个颜色可以不是一个颜色(2026-09-13)

`itemStyle: { color: { type: 'linear', colorStops: [...] } }`——ECharts 里
颜色那一格可以写一个**对象**。最常见的那一张图就是靠它画的:一条折线,
下面一片从实色淡出到透明的面积。

### 判别是**结构性**的,不看 `type`

上游 `canvas/graphic.ts:121-122` 判的是 `!!fill.colorStops`,`isGradientObject`
也只测 `colorStops != null`。`type` **只在之后决定形状**,而且
`helper.ts:72-74` 写的是 `obj.type === 'radial' ? 径向 : 线性`——
**任何不是正好 `'radial'` 的东西,包括 `type` 根本没写,都画线性。**

按 `type` 判的端口在「没写 type」的合法渐变上什么都画不出来。

### 线性的默认方向是**从左到右**

`x=0, y=0, x2=1, y2=0`。而画廊里几乎每个例子都把 `x2: 0, y2: 1` 写出来,
所以**这个默认值是没人见过的那个**,也正是端口会想当然认成竖直的那个。

径向:`x=0.5, y=0.5, r=0.5`,**内半径永远是 0**,而且永远是正圆——
半径按 `min(宽, 高)` 缩放,不是按宽、也不是按对角线。

### `global: false` 归一化的是**元素自己的盒子**

不是绘图区,不是整条 series:上游取 `el.getBoundingRect()`。所以

- 每根柱子各自从自己的左边开始渐变,两根柱子离多远都一样
- 堆叠的每一段是自己的 `Rect`,渐变**逐段重来**
- 折线的面积是一个多边形,盒子就是那条路径的包围盒

而且**两个轴各自缩放**(x 乘宽、y 乘高)——这个各向异性是有意的,
Sankey 就是靠它用 `0,0,+(横),+(竖)` 一句话切换方向的。

另外那个字段叫 **`global`**;文档里的 `globalCoord` 是构造函数的参数名,
写在 option 字面量里**什么也不做**。

### 两处端口必须和上游不一样

**一,gamma。** Canvas 2D 在**预乘 sRGB、不做 gamma** 下插值;
BGRA 的 gamma 通道用的指数是 **1.7**。开着 gamma,每一条渐变的中点都会落在
上游不会放的位置——所以这条路必须 `gammaCorrection := False`。

**二,零 alpha 的那个停靠点会掉色。** BGRA 插值 alpha 是**直通**的,
于是「红 → `transparent`」这条上游真的会写的渐变,在这里会往**黑**里衰减:
`transparent` 是 `rgba(0,0,0,0)`,它那三个零通道照样被平均进去。
Canvas 2D 预乘所以没这个问题。修法是**把一个看不见的停靠点的颜色换成邻居的**——
它本来就画不出来,换了不影响它自己,却让整条渐变和上游一致。

### 降级成一个颜色:取**第一个**停靠点

图例色卡、tooltip 的小圆点只能要一个颜色。上游自己的规矩
(`util/format.ts:302-313`)是 **`colorStops[0].color`**——第一个,
不是平均值也不是中点,拿不到就 `'transparent'`。
所以端口里渐变和它降级出来的那个实色**同时存在**:
`TTyOptColor.Color` 仍然是一个数,图例那一路一个字都不用改。

### 不在这一批里

`type: 'pattern'`(要一条图片管线,而且上游那个字段收的是
`HTMLImageElement`/canvas,不是路径——照搬不过来,补一条路径形式就是发明而不是移植)、
`decal`、文字上的渐变(上游把带 `colorStops` 的文字填充**换成字面量 `'#000'`**,
这在深色皮肤上是个上游缺陷,不抄)。

### 变异测试:两轮 30 个,0 存活

第一轮 24 个活了 6 个,**六个里有三个是同一个病**:这一批之前每个夹具都是
**又高又窄的一根柱子**,而在那种盒子上「y 按高缩放」和「y 按宽缩放」画出来
差不多——`AY *= h` → `AY *= w`、径向半径 `Min(w,h)` → `w`、
以及 `global` 的径向那一半,三个变异体全靠这一点活下来。

补了一个 **330 宽 25 高** 的夹具,三个一起死。
**夹具的形状本身就是一个自由度**,这一轮之前它从来没变过。

另外三个:
- 折线用 `itemStyle` 里的渐变描边——这条回退路没测
- **gamma**:任何「渐变往哪个方向走」的断言都看不见它,得直接量
  黑到白的**中点是 128 还是 170**
- **零 alpha 那个停靠点借邻居颜色**:两端看起来都一样(那一端本来就看不见),
  只有**中间**看得出来——不借的话半程就已经暗了一半

## 51. Tier 1 第十七批:一根轴不在边上的时候(2026-09-13)

多根轴的骨架早就有了:`xAxis`/`yAxis` 写成数组、`gridIndex`、`position`、
N×M 的 cartesian 交叉积、`series.xAxisIndex`/`yAxisIndex` 绑到对的那一对。
缺的是**一根轴不在图区边上时它在哪儿**——两个选项,而且它们不是二选一。

### `offset`:把轴推离图区

- 默认值 **是写出来的**,不是靠 `|| 0` 兜出来的:上游在
  `component/grid/installSimple.ts` 里把 `offset: 0` 合进了**八个**轴模型类。
- **正数永远表示「离开图区」**,按**边**定符号而不是按屏幕方向:
  `top - offset`、`bottom + offset`、`left - offset`、`right + offset`。
- 只有**垂直于轴**的那一个坐标动;沿轴那一头仍然是图区的边。
- 刻度和标签的**方向**取自 `rawAxisPosition`,`offset` 不改它。
- **它是要占地方的。** 上游是绕一圈到的:标签是在 offset 之后的位置上建的,
  然后按「标签超出画布多少」收缩图区。端口直接把 offset 加进这根轴的带子里——
  一根轴一边的时候两条路结果一样。

**这就是两根同侧轴唯一的分开办法。** 上游对两根都写 `left` 的轴就是原地重叠,
指望作者用 `offset` 挪开。

### `axisLine.onZero`:线跑到对面那根轴的零点上

**默认是开的**(`'auto'` 是真值),所以**带负值的柱状图,类目轴本来就在中间**——
这一条谁也没写,但它是这一批里唯一一处改了"一句配置都没写的图"的长相。

谁能当提供者,规则比想象的严:

- **类目轴和时间轴永远不能**,不管它的区间多明显地跨过零——上游管这叫历史原因
- 零必须**不在它有效区间之外**(压在端点上算);所以**对数轴永远当不了提供者**
- **已经被别人占用的不算**。两根 y 轴都要求 onZero 的话,若都给同一根 x,
  两条线会叠在一起——上游在同一处留了这句注释
- `onZeroAxisIndex` 点名一根。**点名失败不会退回自动扫描**——
  上游那个 `else` 属于 `if (onZeroAxisIndex != null)`,点了一根答不了的就是关掉

而位置是 `clamp(对面轴的零点坐标, posBound[0], posBound[1])`——
**而 `offset` 只是把这个 clamp 的范围撑宽**,所以 onZero 之下 offset 不挪线。

### 线走了,字不走

`labelOffset = posBound[原始位置] - posBound[onZero]`——标签被拉回**原来那条边**。
这就是"带负值的柱状图,轴线从中间穿过、类目名还在底下"的全部机制。
线动、刻度跟着线动、**只有标签留在边上**。

### 顺手挖出来的一个真缺陷:网格盖住了轴线

写 onZero 的测试时发现:**两根 y 轴的图上,x 轴线画不出来。**

原因不在 onZero,在**绘制顺序**:`PaintAxis` 原来是一根轴画完自己的**全部**——
网格和轴线——再轮到下一根。一根 x 一根 y 时这和正确顺序看不出区别;
两根 y 轴时,**第二根 y 轴的分隔线正好落在第一根 y 轴的零点上**,
而那正是 onZero 刚把 x 轴线放的地方,于是把它擦掉了。

上游靠 z 分层:分隔线和分隔区在下,轴线带着 `z2 = 1` 在上。
端口改成**两遍**:所有轴的网格,然后所有轴的线。

一个中间状态值得记:**只在第二遍前面加一句 `if ABelow then Exit` 是不够的**,
那样第二遍会把网格**再画一遍**,照样盖在第一遍刚画好的线上。
三个网格块也得各自判 ABelow。

### 变异测试:两轮 21 个,等价的 2 个

第一轮 18 个活了 3 个。一个是真洞——**所有 offset 的测试都在 y 轴上**,
一个「不管哪一族都去拿图区左右边」的端口会全部通过,而 x 轴根本不会动。
补一条横轴的。

剩下两个是真等价,按惯例在原处记了理由:

- **那个 clamp 够不着**:`CanProvideZero` 已经把「区间不含零」的提供者挡掉了,
  所以 `DataToCoord(0)` 天生就在图区里,没有东西给 clamp 抓。
  保留是因为上游也是这一对,而且断轴/映射区间落地那天它就是那张网。
- **`if ABelow then Exit` 单独看不见**:删掉它,第一遍也会画线,第二遍再画一次——
  **一样的像素,两倍的工**。顺序是那三个网格块的 `ABelow` 守的,这一句守的只是开销。

## 52. Tier 1 第十八批:日历不是数字(2026-09-13)

时间轴一直是「画对了但读不出来」:epoch 毫秒本来就是数,线性映射没有错,
错的是刻度落在哪儿和标签写什么——线性 nice 器每 200,000,000 ms 放一根,
标签写 `1709251200000`。

这一批把三件事补齐:**日历步进**、**层级**、**默认标签**。

### 月不是一个毫秒数

一个月是 744、720、696 还是 743 小时,取决于是哪个月、站在哪儿。所以一根刻度
是**把解码后日期的某个字段加一再编码回去**,不是加一个常数。跨夏令时的一天是
23 或 25 小时,同理。

上游靠 JS 的 `setMonth`/`setDate` 拿到这个:**字段溢出会进位**。1 月 31 日加
一个月是 3 月 2 日(或 3 日),不是 2 月 28 日。FPC 的 `IncMonth` 反过来——它
**钳位**——而钳位的步进永远走不出它出发的那个月,十六天的梯子会一直转到安全阀。
所以端口自己做进位:年月先折成一个连续月号,日再当成天数加上去。

### 层级不是主/次刻度

上游不是挑一个单位步进,而是**从年往下每个单位都收一遍**,够了就停,并给每根
刻度标上「有多粗」。这就是一根轴能读成

    12   13   14   Feb   2   3   4

而不是十四个一模一样的日期的原因。`Feb` 和 `13` 是同一种东西,只是粗一级、
加粗显示。**每一根都是有标签的主刻度。**

编号是**反的**:最粗的那层拿最大号,最细的拿 0。而且数的是**活下来的层**不是
单位——七十年的图只有年这一层,它的刻度就是 0,不是「年是第六个单位所以 6」。

端口这里踩了个必须记的点:`TTyScaleTick.Level` 在整个端口里的含义是**主刻度还是
次刻度**,渲染器就是这么读的。时间刻度的「粗细」写进 `Level` 会把每个年份标记
变成次刻度——画得短、没有标签、走另一套样式。所以它有自己的字段。

### 两端是数据自己的

时间轴的区间**永远不外扩取整**。数据从 07:13 到 19:48,轴就是 07:13 到 19:48,
所以两端各补一根「没有任何间隔落在这儿」的刻度,否则网格到不了数据。
上游给它们打 `notNice`,**刻度留着、标签藏起来**——一个紧贴第一个整点的
`07:13` 是粗糙移植最显眼的标志。

### 反直觉但是上游的三处

- **底层单位比 bisect 找到的那行细一格**(`scaleIntervals[max(idx-1,0)]`)。
  落在那行本身,要六根刻度会给四根。
- **复合名字停不住走查**。`half-week`、`quarter-day`、`half-year` 这些行只是为了
  让**尺寸表**更细,它们不对应真单位;上游比较的是名字,所以选中它们时循环不会在
  日或时停下,而是一直走到刻度数够。看着像 bug,不是——它们的尺寸夹在两个真单位
  之间,哪个都不是该停的地方。(变异测试后记:在默认刻度数下这条**看不出来**,
  因为刻度数那道守卫总是先触发;照抄是因为它是上游的,不是因为它可观测。)
- **12 小时制的午夜是 0 不是 12**。上游写的是 `(H - 1) % 12 + 1`,JS 的取余保号,
  所以 0 点出来是 0。把它「修好」的端口会在每天恰好一个小时上和全世界的 ECharts
  图不一致。

### 接线上四个「不做就是错」

1. **归零规则要放过它**。每根值轴都会被拉到含 0(柱状图的基线就是这么来的);
   时间轴的 0 是 1970 年第一毫秒,上周的七个点会被画在最后一个像素里。
2. **不能 Niceify**。取整会把 2024 年 3 月的一周开到 1973 年附近。
3. **splitNumber 默认 6 不是 5**,`splitLine` 默认**关**——上游在按类型的默认值里
   写死的两条,日期比数字宽。
4. **min/max 通常是日期串**。`min: '2024-01-01'` 是所有人写的形式,只认数字等于
   这两个最常用的轴选项在最需要它们的轴上什么都不做。

`useUTC` 是**根**选项不是轴选项,默认 false:服务器上存 UTC,人读自己的钟。

### 月份名字早就有了

写了 38 条 `rsTyTimeMonAbbr*` 之后才发现——库里早有
`rsTyLongMonth1..12`/`rsTyShortMonth1..12`/`rsTyLongDay1..7`,而且外面包着一条
三级规则 `TyDateTimeNames`:app 显式选择 > 已加载的翻译 > 机器 locale。
日历和日期选择器都走它。

**一个日历说八月、旁边的图说 Aug,比两边都说 Aug 更糟。**所以 38 条删掉,
`TyDateTimeNames` 连同它的三级规则从 `tyControls.Calendar` **搬到了
`tyControls.StrConsts`**——名字一直在那儿,现在挑名字的规则也在那儿。搬的理由是
分层:图表单元是不带 LCL 的,留在原处要么把 Controls 和 BGRABitmap 拖进一个纯
scale 单元,要么长出第二张表。

代价一处,记在这儿:**已经建好的图不会因为 app 换语言自己重排标签**,要重建。

### FPC:差了 31,744 毫秒

`days * cOneDay` 里 `cOneDay` 是无类型实常量,**整个表达式在 Single 里算**,
不管结果放进多宽的变量。24 位尾数装不下 1,709,251,200,000。第一版的标签读作
`00:00:-31 -744`,而且每个「这两个在不在同一个月」的判断都在说谎。
整条挂钟改成整数常量 + Int64 乘法。

同一段还有一处:`cMinDay` 写成 `1 - 25569`,那是 1899-12-31 而不是公元 1 年。
TDateTime 从 1899-12-30 起算、之前是负数,**钳在 0 看着像地板,其实是范围中间的
一堵墙**,999 年出来是 1899。

### 变异测试

66 个变异体,第一轮活了 11 个。**其中 4 个是真洞,1 个是死代码,6 个真等价。**

四个洞都是「夹具从没试过那一侧」:

- **所有夹具都是 1 月 1 日起**,于是年那一层「回snap到年初」这件事没东西可挪;
  补一条 6 月到 6 月的,忘了清月份的实现会把每根都标成 `Jun`。
- **分钟/秒的梯子一级都没踩到**——只有一条 3 秒的测试,走的是最底一级。
- **整整一年的跨度一条都没有**,于是月那一级除以 30 天还是 31 天看不出区别。
- **「按自己的字重去量」在图表里量不出来**:横轴留的是标签高度,粗体不改高度;
  而时间轴上最宽的标签通常是没加粗的那些。补了一条直接问布局单元的测试:
  一根纵轴,最宽的标签恰好是那个加粗的年份标记。

死代码一处:`MsOf` 里给负月份借位的分支。`div` 向零截断确实会让月份落到 0 或以下,
但那要求年份 ≤ 0,而下面的钳位本来就把那些全变成公元 1 年 1 月 1 日——
**借位改不了一个钳位已经决定的答案**。删掉。

六个等价的,都是同一件事的不同面,按惯例在原处记了理由:
**尺寸表挑的单位,正好就是刻度数达标的那一级**。于是
`tickCount > target`、丢弃规则、底层单位这三道停止条件互相覆盖:
把表的搜索条件改宽、把 `bottomStops` 恒真、把 day 那行从 1.2 天改成 1 天、
去掉 `tickCount > target`、去掉空层过滤、去掉不相交跨度的剪枝——每一条都不改任何读数。

**但底层单位那一半不是冗余的,而且被钉住了**:在细的那一端,层是被**跳过**而不是被数的
(三秒的跨度根本没有分钟那一层),所以没有任何计数累积起来,
只有它能让走查在毫秒之前停下。把它去掉,变异体当场就死。

补完之后重跑这四条:**全部命中**。

### 这一批没做的

- `axisLabel.formatter`(字符串 / 回调 / 按单位的字典)——默认模板已经全套,
  用户自定义模板接口留给「标签格式化」那一行。
- 上游的 `{primary|...}` 富文本。端口用一个独立 typeKey
  `TyAdvChartAxisLabelPrimary` 代替:效果一样,而且皮肤能改。
- ECharts 自己的 locale registry。月名走的是本库的三级规则(见上),
  和日历共用——这是有意的偏离。
- 断轴上的 `upperTimeUnit`(断轴本身还没做)、`axisPointer`/`tooltip` 上的时间
  格式(那两行还没到)。
- `hideOverlap`。**上游默认也不开**,所以「Feb 和 2 挤在一起」是忠实的;
  真要按测量去碰撞归到「标签去碰撞」那一行。

## 53. Tier 1 第十九批:轴标签画哪些、怎么挂(2026-09-14)

这一批两件事,一件是修 bug,一件是补选项。它们在同一条管线上,而且第二件是
第一件被发现的原因——测 `interval` 的时候顺手渲染了一张 `rotate: 45` 的图。

### 先说 bug:旋转的标签挂反了方向

`axisLabel: { rotate: 45 }` 的柱状图,八个类目标签有五个掉尾巴,
`Category 1` 显示成 `Category`。

**不是文字渲染坏了。**同一份 option 把 `series` 清空,八个全是完整的——
所以是被盖掉的,不是没画出来。

端口给旋转标签用的还是**没旋转时那套锚点**(下轴=居中/顶对齐),再绕这个锚点
转 45°。结果标签**骑**在锚点上,一半翻过轴线进了图区,柱子从上面盖过去。
`RotationRad` 一路传到画笔,却从来没传到锚点。

上游的规则是 `AxisBuilder.innerTextLayout`:

```
diff = rem(文字角度 − 轴自身角度)      x 轴 0,y 轴 π/2;rem 归一到 [0, 2π)
dir  = top -1 / bottom +1 / left -1 / right +1   (axisLabel.inside 取反)

diff ≈ 0   → 垂直 = dir>0 ? 顶 : 底,  水平 = 居中
diff ≈ π   → 垂直 = dir>0 ? 底 : 顶,  水平 = 居中
其余       → 垂直 = 居中
             水平 = (0<diff<π) ? (dir>0 ? 右 : 左) : (dir>0 ? 左 : 右)
```

**整条照抄的理由:喂 `rotate 0` 进去,它精确复现端口现有的四边表。**
所以它不是表旁边多一个分支,它替换那张表,旋转不再是特例。
一条老测试都没红,这既是好消息也是坏消息——说明旋转锚点原本零覆盖。

`rem` 归一到 **[0, 2π)** 而不是 [−π, π),这一点会咬人:顺时针四分之一圈
回来是逆时针四分之三圈,落在 π 的另一边,于是进的是另一条分支。

### 能咬住它的断言只有一条

批次 17 发 `rotate` 时测了**锚点位置**和**让出的边距变大**。
这两条对一个朝图区伸的标签同样成立,所以全绿。

写第一版守卫时我也没写对:数了**轴线下方**那条带子的墨迹——
而被擦掉的恰恰是翻到轴线**上方**的那一半。框在了伤害不发生的一侧。

第二版改成差分:「没有 series 时是灰字、有 series 时不是了」的像素数。
但 y 轴没钉住(无 series 时跨 0..1、有 series 时跨 0..60),
每个 y 标签都算「被毁」,**对着正确实现也是红的**。

第三版:钉住 y 轴 + 把容差从 40 收到 8。
**容差必须小于缺陷本身,而这个只能靠对着修复版和 bug 版各跑一次才知道**——
修复后 0 像素,发布版 32 像素,我最初的 40 正好把它放过去。

### 再说选项:`interval` 数的是它跳过的

| 写法 | 含义 |
|---|---|
| `interval: 0` | 全画(最常写的值,而端口之前完全无效) |
| `interval: 1` | 每隔一个 |
| `interval: 2` | 每三个一个 |

**步长是 N+1。**把它读成「每 N 个」,0 就成了「一个不画」、1 成了「全画」,
恰好在最常用的两个值上完全反过来。

三条反直觉但是上游的:

- **`axisTick.interval: 'auto'` 自己不算任何东西。**它重跑**标签**那条管线
  (故意绕过 `axisLabel.show` 门),再把 `.tick` 摘出来。
  所以标签的步长单向驱动 axisTick / splitLine / splitArea——
  这是为了多个 grid 共享 x 轴、只有一个画标签时,网格仍然一致。
- **只在类目轴上读。**值轴和时间轴是**刻度先行、标签由刻度生成**,
  没有东西供标签步长去稀释;时间轴上照做还会把月份标记一起丢掉。
- **`showMinLabel` / `showMaxLabel` 是三态,默认是第三态。**
  上游默认 `null`:步长落在那一端就显示、没落就隐藏——这是两个布尔值都问不出
  的问题。默认成 `true` 会让每根抽稀过的轴都露出参差的末标签;
  默认成 `false` 会让没抽稀的轴丢掉两端。

末标签比首标签重要得多:步长锚在 0,**永远**落在第一个标签上,
落在最后一个只是碰巧;而最后一个才是读者要找的——它说数据在哪儿停。

### 一处有意偏离

`interval: 2.7` 端口取整数部分。上游拿它造出 3.7 的步长去走序数轴,
发出的刻度值不对应任何类目——那是不自洽,不是特性。

### `'auto'` 保留端口自己的规则

上游 `calculateCategoryInterval` 是 `floor(min(最大标签宽/单类目宽, 最大标签高/单类目高))`,
其中标签尺寸乘 1.3、每维取 7px 下限,再加一层防抖缓存。
端口用的是**逐对测量碰撞找第一个不碰撞的均匀步长**。

两者产出同一种东西——一个均匀步长——而端口这套是逐对测量的,比
「最大标签 × 1.3 除以单类目跨度」这个估算更准。**没有为了对齐数字换成更粗的公式。**
上游公式的全部细节(那个 1.3、那个 7、`min` 而不是 `max`、onBand 内缩、
防抖缓存只抑制「减一」)都在简报里,真要对齐随时可以换。


## 54. Tier 1 第二十批:指针指着谁(2026-09-14)

Tooltip 的第一笔不是 tooltip。图表在这之前对鼠标一无所知,
而"一无所知"里有三样东西各自坏掉,写了 tooltip 也不会被画出来。

### paint list 活不过那一帧

`PaintSeries` 里 paint list 是**局部变量**:那一帧建、那一帧释放。
形状记录、z 序、命中测试、`Silent` 标记,Tier 0 全都造好了,
`HitTestElement` 完整得可以直接用——可是等指针来问"我指着什么",
答案已经被 `list.Free` 了。所以它唯一的调用方是它自己的测试。

现在它是字段,生命周期跟静态缓存绑在一起:两者由同一趟渲染产出,
`DropStatic` 一起作废。代价是每个 mark 一条元素记录,
买到的是图表被问到的唯一一个交互问题。

**坐标是本地设备像素、原点 (0,0)**——`MouseMove` 的 X,Y 就在这个空间。
`RenderTo` 到一个非零原点的矩形上时,list 仍然填本地坐标,
那条路上的调用方得自己减掉原点。

### 指针一进来就砸缓存

`TTyAdvanceChart` 一个鼠标方法都没重写,但基类重写了六个:
`MouseEnter`/`MouseLeave`/`MouseDown`/`MouseUp`/`DoEnter`/`DoExit`,
每个末尾一句 `Invalidate`。而图表的 `Invalidate` 覆写里是
`FDirty := True` 加 `DropStatic`——**指针跨过边界就是一次全量
Rebuild + Relayout + 静态层重画**。

而且是纯浪费:这个类从不读 `FHover`/`FPressed`,
`CurrentStyle`/`CurrentStates` 在整个 `AdvanceChart.pas` 里零调用点。
五次重画,画的是同一张图。

修法是给基类开一道接缝:`PointerStateChanged`,默认实现就是今天的
`Invalidate`,所以别的控件一个字节都没变。图表把它重写成 `InvalidateFrame`。
`InvalidateFrame` 从此有了第一个生产调用点。

### 命中层是惰性的:`HitSlopLogical` 处处为零

字段自己的注释写着意图——"6px 的散点标记需要宽容的目标,
线系列需要一整条带子"——`TyChartElement` 设 `0`,
**没有任何构建器改过它**,全仓库唯一的非零赋值在测试里。
于是 `PolylineNear` 要求距离**恰好为 0**:一条线只有数学中心线可点。

现在:有面积的东西一律不给公差(柱子、扇区、填充带本来就是它所指之物那么大,
给了会越过类目间隙咬到邻居——上游也不给);
标记给 4 逻辑像素(一个 4px 的 emptyCircle 代表一整行数据,
那么小的目标指针总是点不中);
线给**半支笔加一条带子**(`PolylineNear` 量的是数学线段,
形状记录里没有线宽,不把半支笔算进公差,3px 的线就只有中心线可点)。

公差不敢再大:命中测试答的是**最上面那个**包含点的元素,不是最近的,
所以互相重叠的公差会把每一次并列都悄悄判给后面那一行。

### 一个元素代表一整条系列的时候

线的描边是**一个**元素代表整条系列,所以它没有行可报——
`Marks.pas` 给它 `(series, -1)`,而 `TyChartDatumValid` 要求两者都 ≥ 0。
更糟的是它不是 `Silent`,而命中测试答的是最上面那个、不会往下落,
所以点在线上等于点了个寂寞;它底下的面积填充还是**故意** `Silent` 的
("指针落在阴影上该找到线,不是阴影")。

`HitTestAt` 补的就是这一处、也只有这一处:拿到一个没有行的 datum 时,
**反过来问基准轴**——`CoordToData` 把像素变回数据,再在 store 里找最近的一行。
不是第二条命中路径:走的还是 paint list 那一趟,
只是把它答不出来的那个数补上。

**问哪个坐标不是"线就问 x"**:横向柱状图的脊柱是竖着的,
拿 y 轴去问 x 像素,答出来的数形状对、量的东西不对。
binding 自己知道它两根轴里哪根是基准轴。

### `DataIndex` 一个名字扛了两个答案

笛卡尔的 mark 存的是 store 的**视图**行,饼图的扇区存的是**原始**行。
今天两者只在饼图上分岔——控件里唯一按行过滤的就是饼图的图例——
所以没人发现:同一个 `DataIndex`,拿去读 store 在一种系列上对、
在另一种上错了被丢掉的行数那么多。

`TTyChartCallbackParams` 从写出来那天就同时声明了 `DataIndex` 和 `RawDataIndex`。
现在 datum 也是。两参数的 `TyChartDatum` 断言两者相同——
对每一个走未过滤视图的构建器都是实话;三参数的那个留给知道它们不同的人。

饼图的视图行不能从下标推:负值的行是被**整个移出布局**的
(不是画成零角度的扇区),所以扇区下标只数扇区。
`TTyPieSector` 现在同时带 `RawIndex` 和 `Index`,由唯一手里同时有这两个数的那一趟填。

### 一处仍然欠着的账

系列的 mark 画在**静态层**里。Q7 的层规划说它该在动态层;
git 记录显示这是无意飘移的——落地静态层的那次提交里 `PaintStatic` 没有
`PaintSeries`,同一天的下一次提交把它插了进去,只字未提分层,
而 `PaintDynamic` 里那段预言了这件事的警告注释原封不动还在。

浮动的 tooltip **框**不受影响,可以纯活在动态层。
被悬停那个 mark 的**高亮**不行:它已经烤进静态位图了。
这笔账等高亮要做的时候再还。

## 55. Tier 1 第二十一批:指针停在那儿的时候(2026-09-14)

### 画在控件里,不是弹窗

库里每一个浮层都是真窗口。tooltip 不能是——**GTK3/Wayland 上已经映射的
xdg_popup 不能移动**,跟随指针就意味着每一次鼠标移动都要 Hide → 重定位 → Show;
Wayland 没有 XShape,圆角会退化成"方窗口里画个圆角"。

上游正好有一个反过来的同款问题:它的 `richText` 渲染模式就是为**没有 DOM 的宿主**
准备的,答案是把 tooltip 画在画布上。这里也这么做。

**代价说一次**:画在控件里的 tooltip 出不了控件。这就是 `confine: true`,永远。
而上游那个 `confine` 比的是**原始的 `renderMode` 选项字符串**,默认值是 `'auto'`,
`'auto' <> 'richText'` 所以它在任何环境里都解析成 false——跟它自己声明上方那条注释
正好相反。端口无条件钳住,选项读下来但不遵守,**这是有意分歧**。

### 抄 richText,不抄 html

两个渲染器不是一套版式的两张皮:同一个圆点,html 写 `border-radius: 10px`(CSS 自己
钳成圆),richText 写 `borderRadius: 5`(**真半径**)——照 CSS 的数字抄半径翻倍。
右对齐的机制也不同(CSS float 对 padding + align)、认的选项也不同(richText 忽略
`borderWidth` 和 `textStyle.lineHeight`)、能做的事更不同(没有箭头、没有过渡)。
**分歧处一律跟 richText**,因为它才是为画布写的那个。

### 默认内容不是模板字符串

`'{a}<br/>{b}: {c}'` **不是 6.1 里任何东西的默认值**。默认内容是一棵
`section` / `nameValue` 的树,而**竖直间距是从树的形状算出来的**——
从模板字符串起步的端口只能自己编间距,而且一定会把双轴那种情况编错。

间距等级是**自底向上按结构**算的,叶子是 0、根最大,跟"深度"正好相反。
而且 richText 的 gap 表是 **0/1/2/3 个换行 = 0/0/1/2 个空行**——
把那张表读成"空行数",每个 tooltip 都会多出一行。

上游那张表没有钳位:越界给 `undefined`,JS 渲染成字面量 `undefinedpx`;
**FPC 里那是越界错误,从 paint 里抛出去会带走宿主窗口**。这里钳到 3,记在原处。

### `DataIndex` 之外,还有两处"一个名字两个答案"

- **千分位**:默认内容里的值走 `addCommas`,`1048` 显示成 `1,048`;
  模板里的 `{c}` **不走**。所以是两个函数,不是一个带开关的——
  而且轴刻度标签用的那个是**故意**不加千分位的。
- **`textStyle` 整体替换,不逐键合并**。上游 `Model.get` 只有在整条路径解析为 null
  时才往父级走,所以 series 级写一个 `{fontWeight:'bold'}` 会把全局那个对象**整个换掉**,
  它没写的键落到渲染器自己的常量、**不是**落到上一级的值。
  这件事在有人只写一个键、另一个键跟着变之前完全看不见。

### 边框颜色是数据点的颜色

灰色那个 token 是**轴触发**时的回退;item 触发时边框取被悬停那个数据点自己的颜色——
这就是 ECharts 6 那个"贴在它所描述的东西上"的观感,而静态灰边框在最常见的那次交互上
就是错的。颜色是**问画出它的那个元素**要的,不是问 series 要的:
这样逐点 `itemStyle` 白拿,而且圆点和它指的那个 mark 不可能不一致。

### 两个守卫互相遮挡

`show: false` 和 `trigger: 'none'` 各有两道检查:`MouseMove` 问**全局**选项要不要
跟踪指针(那时还没有数据点,它问不了别的),绘制时问**级联**后的选项。
两边都说"不"的测试会让第二道守卫被第一道遮住——变异测试里两个变异体都活了下来。
真正只有第二道能拦的形状是:**全局开、series 自己关**。

### 一个像素测试绿着错

`CirclePath` 是往**当前路径**上追加的,不是开一条新路径。漏了 `BeginPath`,
圆点的填充就把静态层遗留的半成品路径一起填了——在图表另一端的图例标签上
画了一个实心蓝方块。

而"数两帧之间变了多少像素"的测试**全程是绿的**:画错地方的像素也是像素。
现在它还要求所有变化落在**一个**包围盒里,且包围盒基本被填满。

### 这一批没做的

`trigger: 'axis'` 和整个 axisPointer(线/阴影/十字/吸附/指示标签)是下一批。
`position` 的四种形式、`order` 排序(上游只在轴触发和雷达图上置 `sortBlocks`,
所以 item tooltip 上它本来就是空操作)、`valueFormatter`(是函数,JSON 里写不出来)、
`enterable`(画在控件里没有"进入"这回事)、`showDelay`/`hideDelay` 的定时器,
都还欠着。

### 一处按主题规则的有意分歧

行高。上游 richText 硬编码 22,不管字体多大;html 是 `round(fontSize * 3 / 2)`。
这个库的主题会改整套字号,常量在这里活不下去:紧凑皮肤 11px 会得到双倍行距,
展示皮肤 20px 会重叠。所以取 html 那条规则。

## 56. Tier 1 第二十二批:一整列的那个 tooltip(2026-09-14)

### 三处写 axisPointer,优先级跟名字给的印象相反

    <轴>.axisPointer.*   >   tooltip.axisPointer.*   >   axisPointer(根组件)

"tooltip 赢"**只对根成立,对轴从来不成立**。上游解析一根 tooltip 驱动的轴是
`axis.model.getModel('axisPointer', <volatile>)`——轴自己的块是 model,
tooltip 那层只是它的**父级**。所以 `xAxis.axisPointer.type: 'shadow'`
照样压过 `tooltip.axisPointer.type: 'line'`。

而且回退是**逐叶、只在 null 时**发生的,所以 tooltip 层带的任何值都会**遮住根**——
即使用户显式设了根。上游自己在 `TooltipModel.ts:180` 处理这件事的办法是
**故意不给 lineStyle 和 shadowStyle 写默认值**,好让这两个键还能够到根层。

### 只有九个字段过河,其中三个过河后又被改写

`type`、`snap`、`lineStyle`、`shadowStyle`、`label`、`animation` 加三个动画细节。
写在 `tooltip.axisPointer` 下的 `show`、`triggerTooltip`、`handle`、`link`、`zlevel`
**静默无效**。第十个 `crossStyle` 只在 cross 那条路上过。

然后:
- **`snap` 被无条件按轴的**种类**重算**——所以 `tooltip.axisPointer.snap` 是死代码,
  根的那个对 tooltip 轴也够不着。轴自己的 snap 仍然赢,因为它是 model 本身。
  规则(用上游自己的话):类目轴不自动吸附,否则没有值的刻度就没法悬停;
  value/time/log 轴在 tooltip 要求时吸附。
- **`type: 'cross'` 逐轴改写成 `'line'`**。上游的形状表里只有 `line` 和 `shadow`
  两个键,**根本没有 cross 这个形状**——cross 是"两根轴各画一条线"。
  根上写 `axisPointer: {type:'cross'}` 打到没改写的表上是上游的一个真崩溃。
- **`label.show` 被按倒**:普通 tooltip 轴强制 false,cross 下强制 true。
  显式写的值两种情况下都活着。

### 一个键名表,两套词汇

`show` 既是 axisPointer 块的键,也是它 label 的键。一份扁平的"已认领键名"表
会让前者把后者吞掉——写好的 `label.show` 被两行之上仅仅提到过 `show` 的那一层挡住了。
测试里这条只有**两个都写**的夹具才问得出来;只写一个的夹具在分不清它们的读取器上照样绿。

### 一整列不是"这一列里的每条序列"

上游在出现更近的序列时**清空**已收集的批次,活下来的是**离悬停值最近的**那些序列。
而且"更近"的比较在**原始数据空间**,不是像素;
per-series 那个 `0.5` 才是像素——**半个像素**,不是半个类目。
(ECharts 5.x 在数据空间比,6.x 挪了方法并换了空间。)

半个像素的用处正是:**比轴短的序列在它够不到的类目上什么都不贡献**,
而不是贡献它最后一行。

这两条各自都难以观测,而且**夹具的顺序决定了能不能观测**:
把近的序列写在前面,远的那条只是从没被加进来,清空那个分支根本走不到——
一个删掉了清空的端口照样全绿。

### 阴影带被钳,不是居中溢出

两端**各自独立**钳位,所以第一个/最后一个类目上的带子是**半宽且不对称**的——
不是被推进去保持宽度。先居中再裁剪的端口会把带子挪离它自己的类目。

**value 轴上端口不画带子。** 上游是从悬停序列的最小正间隔统计出来的;
没有那趟统计,诚实的答案是不画,而不是那个缺失的数会产出的一像素细条。
**记录在案的限制**,不是近似。

### `type: 'dashed'` 在端口里一直画成实线

`TTyOptDash` 读出来、存下来,然后全仓库**没有一个消费者**。
两个词是**线宽的倍数**、数字不是(zrender 在一个函数里定这件事,
`dashed` → `[4w, 2w]`、`dotted` → `[w]`),
所以这一批把它补成一个函数,顺手让全局的 `lineStyle.type` 开始生效。

### `precision: 'auto'` 不是"有几位算几位"

是**刻度间隔的精度**。缺了它,指针在 value 轴上拖出来的标签读作 `37.246964`——
一个为真且无用的数。

### `order` 排的是一个 section 内部的行

上游只在**轴 section** 和雷达图上置 `sortBlocks`,从不在根上——
排根的端口会把**轴**重排而每一行原地不动。
`'seriesAsc'` 是个**两个分支都不处理**的枚举值,行为上等同于没写(上游自己在旁边留了 FIXME);
排序必须**稳定**,并列要保持序列顺序。

### 两个夹具跟它们的 bug 同形

`seriesAsc` 那条我第一版的夹具本身就是降序的,而漏掉早退正好让它按降序排——
**一个起始顺序就等于它的 bug 会产出的顺序的夹具,什么都没证明**。
"比轴短的序列"那条同理:旁边站着一条更长的序列时,
横向过滤会因为**另一个原因**把它丢掉,窗口从头到尾没被测到。

### 还欠着的

`position` 的四种形式、`valueFormatter`(是函数,option 文本写不出来)、
`link`/`handle`/`triggerEmphasis`、`showDelay`/`hideDelay` 的定时器、
指针移动动画,以及那笔分层的账——**系列的 mark 在静态层**,
所以阴影带只能画在柱子**上面**(10% alpha 下读得过去,但它本该在下面)。
高亮要做的时候这笔账必须还。

## 57. Tier 1 第二十三批:指针底下那个变了样(2026-09-14)

### 机制早就在,少的是那个接头

`tyControls.AdvChart.Style` 是六百行的四态解析——两个槽而不是一个枚举、
引用计数的 emphasis 掩码、以及一套跟 normal 态在**五个地方**不同的回退规则——
而在这之前,单元之外的每一处引用都是它自己的测试。这一批只做那个接头。

### 画在哪一层,以及那为什么是一个真实约束

静态层里已经有了静止状态的 mark,所以**强调态的那一份画在动态层、盖在它上面**:
一个元素、不掉缓存、不重建。

**这成立是因为强调要么变大要么变亮,因此盖得住它替换的东西**。
这不是巧合而是约束,也正是 blur 不在这一批里的原因:
把**其他** mark 调暗,意味着要改已经烤进静态位图的墨。

顺带,这也修掉了上一批留下的观感债:阴影带画在柱子**上面**,
而被悬停那一列的 mark 重新画一遍,正好把带子盖回去。

### 什么都不写的时候,强调是"原色提亮一成"

这是 ECharts 里每一根柱子、每一片扇区、每一个符号的**默认**悬停外观。
把"没写 emphasis 样式"读成"没有变化"的端口,会画出一个什么都不做的悬停——
而且没有任何东西会发现。

反过来读也是错的:**写了的填充色不提亮**。提亮是它缺席时发生的事。

### `scale` 一个键四种意思

上游自己的注释点了名:null 或 true 是默认策略,有限正数是字面比例,
**0 / false / 负数 / NaN / Infinity 全都表示不缩放**。
默认策略是 `max(1.1, 3 / 半高)`——大标记涨一成,四像素的标记涨一半,
因为四像素的一成不是任何人看得见的悬停。

**扇区不按比例缩放**,它的**外半径涨若干像素**(默认 5)。
绕圆心按比例放大会把它的内边也一起抬离圆孔——那是两个不同的操作。

**柱子不涨**。上游缩放的是符号和扇区,柱子的矩形不动:
一根在指针下跳大一成的柱子看起来像是数据变了。

### tooltip 关掉了,高亮不该跟着关

原来的 `MouseMove` 开头就是 `if not spec.Show then Exit;`——
于是 `tooltip: {show:false}` 把悬停跟踪整个关掉,高亮也就没了。

**指针底下是什么,是几何事实;要不要为它画一个框,是绘制时的问题。**
上游的高亮来自 zrender 自己的 hover,tooltip 是另一个监听器。
`triggerOn` 留在 MouseMove 里——它问的确实是指针:
移动**能不能**驱动 tooltip;但它只管框,不管高亮。

### 五条测试钉的是"没有墨",它们想说的是"没有框"

高亮一开始工作,这五条就红了——它们把两件事量成了一件。
这一类测试只有在被测的第二件事还不存在时才是绿的,
**而它们的绿正是"还不存在"的证据**,不是正确性的证据。

修法不是放宽阈值,是在夹具里显式 `emphasis: {disabled: true}`,
让每一条只量一件事。

### 两个变异体活下来的原因也是同一类

- "扇区不再长大"活着,因为断言数的是"变了多少像素"——
  而提亮本身就改了整片扇区几千个像素。
  只有**长大**能做到的事是:**把颜色放到本来没有颜色的地方**。
- "triggerOn 不再管框"活着,因为没有一条测试用非默认的 `triggerOn`。

### 还欠着的

blur(要改静态层里的墨)、select 槽、`emphasis` 的逐数据项级联、
`emphasis.label`,以及 focus/blurScope 虽然读进来了但还没有消费者。
