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
