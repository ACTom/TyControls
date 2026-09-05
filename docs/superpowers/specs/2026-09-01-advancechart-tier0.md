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
| Q7 | 动画与重绘模型 | 窗口化让选项 (a)(c) 都变便宜——`Invalidate` 不再损毁父控件整个客户区（那个 ~14.9ms 就是这么来的）。复核 `11` 第 6 条仍成立：脏矩形绘制被填在三个互相矛盾的层里，需要**一个**归属 |
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

