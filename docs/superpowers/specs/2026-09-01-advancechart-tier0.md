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
| 9 | **可断的 scale 抽象** —— `ITyScaleMapper`（Linear/Log/Break 同构）+ Ordinal/Interval/Log；nice 1-2-5、次刻度、`min`/`max`/`scale`/`splitNumber`/`interval`/`minInterval`/`maxInterval`/`boundaryGap`/`inverse`、退化域、**`startValue` 独立于 `min`**、**两种 extent** | L | 契约 ②。见 §2。**[第三十二批标注：实现用的是不取整的 1/2/2.5/5 阶梯；上游 `intervalScaleNiceTicks` 是 `nice(span/splitNumber, round)`，1/2/3/5/10、阈值 1.5/2.5/4/7。span 为 7 时上游间隔 1、这里 2。待单独一批按 oracle 修，见 §66。]** **[第三十三批已修：步长、范围、主次刻度与上游逐位一致，见 §67。]** |
| 10 | **坐标系接口 `DataToPoint` + `DataToLayout`** + `TTyCartesian2D`（N 个 x/y 轴 + master/sub 拆分） | L | 契约 ①。见 §2 |
| 11 | **盒布局求解器收容器矩形提供者**（`left/top/right/bottom/width/height`；px、`'%'`、关键字），全组件共用 | M | 契约 ① 的另一半。写成「控件客户区」就等于把嵌套变成重写 |
| 12 | 两阶段轴构建（估文字 → 收缩矩形 → 定尺寸），形状用 `outerBounds`/`outerBoundsContain`/`nameMoveOverlap`，**不用已弃用的 `containLabel`** | L | 标签适配的底座。v6 形状比 v5 多约 150 行（ECharts 把 v5 版留成 `legacyContainLabel.ts` 共 120 行，v6 解算器约 276 行）。**[第三十二批标注：`outerBoundsMode:'auto'` 的外边界默认是**整个画布**（`OUTER_BOUNDS_DEFAULT` 边距 0），只有标签越出画布才收缩 grid；实现把 grid 矩形当外边界、按标签厚度收缩，等于 `containLabel:true`，plot 普遍偏小。待单独一批按 oracle 修，见 §66。]** |
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

**永不实现的 v5 遗留拼写**：`grid.containLabel` · `series-line.triggerLineEvent` · `tooltip.appendToBody` · `legacyViewCoordSysCenterBase` · `richInheritPlainLabel: false` · `grid.outerBoundsMode: 'none'` · `axis.containShape: false`(**[第四十一批更正:6.1 里它不是遗留拼写,上游照读,port 也照读,见 §75。]**)· 以及那约 64 个 v5 时代弃用名（`itemStyle.normal`、`hoverAnimation`、`focusNodeAdjacency`、`clipOverflow`、`mapType`、18 个 zrender `text*` 样式属性…）。

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
  **[第四十六批更正:声明了 `blur.*.opacity` 就用声明的值,不再乘 0.1,见 §80。]**
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
**[第五十二批:错。上游用 mergeLayoutParam 的 ignoreSize 规则把选项并进默认值,选项自己写了 `right` 就把默认的 `left` 置成 null,`right: 10` 单独写照样把标题挪到右边。见 §86。]**

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
  **[第五十二批:合并之后 left、right 至多一个有值,这个读序对 title/legend 已不可观察。见 §86。]**
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

> **第三十一批修正**:「没列出的名字不归图例管」只对 `selected` 也没提到的名字成立。
> 上游先读 `selected` 再读列表,`selected: { L: false }` 不管 `legend.data` 列没列都关掉系列 L。
> 控件现在问的是带 option 的那个重载;空名字永远不隐藏这一条保留。见 §65。

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

渐变和图案(自己一行)、`decal`、`visualMap`(**[编码见 §88]**)、`brush`、颜色回调、`colorLayer`、
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
**[第四十六批更正:对半透明的 mark(画两遍会变深)和压在别的 mark 下面的 mark(副本会盖住上面的)不成立,graph 的边两样都占。graph 的悬停因此改在静态层里原地画,blur 也在那里,见 §80。其他系列仍用叠加。]**

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
**[第四十六批:graph 系列的 blur、逐数据项级联、focus/blurScope 已做,见 §80;其他系列仍欠。]**

## 58. Tier 1 第二十四批:一根轴上四列(2026-09-14)

### 先补一个诚实性缺口

绑定认识 ECharts 那二十三个类型名,但对"这个控件能画哪几个"一无所知。
于是一个 `funnel` 干干净净地绑上、干干净净地布好局,画出来一片空白,
**而且一句诊断都没有**——这正是这个控件不被允许做的那一件事。

`rsTyChartSeriesNoRenderer`。说在控件里而不是绑定器里:
绑定器看不见渲染器表(拥有那张表的单元反过来用绑定器),
在那边再抄一份列表就是第二个会飘的东西。

### candlestick 撞上的不是渲染器,是底层

store 是**一个坐标一列**建的——`x` 和 `y`。而 candlestick 是
**一根轴上四个数**,类目还完全不在行里。结果:

- item 的四个值丢掉三个;
- 值轴按收盘价定范围(影线跑出图外,什么都不抛);
- 渲染器 `DimIndexOf('y')` 得到 -1,在自己的入口之前就退出去了——
  **画不出、不出声,看起来跟"这个类型没有渲染器"一模一样**。

上游把坐标建模成**一串**数据维度(`mapDimensionsAll`),
store 这一批学会的就是这件事:`DimsOfCoord` 答一个列表,没映射过的 store
答那个同名的单列——**每一个在此之前建的 store 都是后一种**。

### 两个默认值的极性

新加的字段会被 `SetLength` 和 `Default()` 清零,所以

- `SourceSlot` 是**一基**的:0 表示"这一列自己的位置"。
  零基的话,每一个 store 的每一列都会悄悄声称自己读元素 0。
  **别扭的编号正是让默认值安全的那个东西。**
- `FromRowIndex` 是布尔:False 是对的默认。

而 store 那个全局的 `useIndex`(「item 不是数组时用行号」)表达不了 candlestick:
它的 item 永远是数组。所以行号成了**逐列**的性质。

### 涨跌不是"正负"

两边比的都是**这个数据点跟它自己**:收盘高于开盘,还是开盘高于收盘。
涨的市场里两种都会出现。

**第三种情况是十字星**——开盘恰好等于收盘,这是真实且常见的读数,不是舍入误差。
上游拿**前一行的收盘**来定方向,所以一根平线跟着走进它的那一段走势;
只有写了 `borderColorDoji` 才给它自己的颜色。第一行没有前一行,算涨。

### 影线是两段,不是一条

看起来一样——在不透明的实体下面。在**空心**实体下面完全不一样,
而世界上有一半的人就是这么画上涨柱的。

### 主题:红涨绿跌是一种约定,不是一个事实

上游写死 `#eb5454` / `#47b262`,那是东亚约定,跟北美的正好相反。
这个库已经有 `--success` 和 `--danger`,在两种约定下含义都对——
想换一边的主题改这里两行,而不是重新给图表配色。

### 夹具扫得太宽

"实体是半个 band 宽"那条第一版扫了 ±一个 band,
把**邻居**的实体也数进去了(它的中心在一个 band 外,自己的半宽又折回来四分之一)。
量出来大了一半。

## 59. Tier 1 第二十五批:漏斗,以及一行门控饿死的两个系列(2026-09-14)

### 一行

没有坐标系的那条建表分支,判的是**字面类型名** `= 'pie'`。
而注册表从写下的那天起就说 funnel 和 gauge 是 `scuBox`、维度 `['value']`。
于是两者走到这里、一个都不匹配、带着**零列零行的 store** 离开。

什么都没抛。它们的布局找不到值维度,画不出东西——
**跟"这个类型没有渲染器"长得一模一样**。

判据改成 usage,列名取注册表自己声明的那个。

### 漏斗不是直边的饼图

饼图把每个值变成**角度**,整个圆盘是总和;
漏斗把每个值变成**宽度**,量在一把共享的尺子上,
而这摞东西的**高度跟数据毫无关系**——是视图除以行数。

所以一个巨值加四个小值,是五条等高的带子,其中四条几乎看不见。
这是上游画的,也是读惯饼图的人不会预期的。

### 最后一条没有"下一行"

上游走到那里的办法是**越过数组末尾取下标**:得到 undefined,
再从 store 得到 NaN,再被 `|| 0` 变成零。
所以尖端是**值为零**的宽度——默认 `minSize: '0%'` 下就是一个点。

端口必须**显式造出这条幻影边**:这里越界是范围错误,
而夹到最后一行会把三角形画成矩形。

### 定义域没有宽度的时候,答案是量程的**中点**

不是起点,不是零。而且这不是边界情况:**每个值都相等**正是"等步漏斗"的样子。
写成"分母为零就返回零"的端口,恰好在上游画半宽带子的时候画出一张空图。

### `ascending` 是四件事一起翻

步长翻号、间隔翻号、游标跳到**远端**、顺序反转。
做了三件就把漏斗画到自己的盒子外面去。

### 一个选项,两套互不相交的词汇

`funnelAlign` 竖直时收 left/center/right、水平时收 top/center/bottom,
而**每个 switch 只处理自己那三个**,另外三个落到一个**未初始化的局部**上——
那边是 NaN 几何,这边会是栈垃圾。

端口把两套并到一根轴上(start/centre/end)。**有意分歧**,而且是更好的答案:
竖直漏斗上的 `funnelAlign: 'top'` 明摆着就是 `left` 的意思,为它画个空白帮不了谁。

### 只有 `none` 这个词能关掉排序

上游的守卫是 `sort !== 'none'`,不是白名单——所以拼错的词**按降序排**。
照抄而不是收紧:收紧会让同一段 option 文本画出跟 ECharts 不同的图。

### `labelLine.show` 与 `label.show` 的与,发生在**选项期**

上游在 init 时就把 `labelLine.show := labelLine.show and label.show`
烤进解析后的 series option。放到绘制时再与,两者就能各说各话——
藏起来的标签会留下它的引导线。

### 三个夹具看不见自己要测的东西

变异测试里活下来三个,原因同一类:

- **没有一条测试写过 `min`**。而且它的回退是 `Min(最小值, 0)`,
  对全正数据**就是 0**,所以只有写一个不同的值才观测得到。
  而负的 min 让带子**变宽**——读起来是反的:定义域的**地板下移**,
  同一个正值就坐得更靠上。
- **视口是正方形的**,于是"横轴基准"和"纵轴基准"是同一个数。
- **没有一条测试问过颜色跟的是行还是位置**。漏斗是**排过序的**,
  两者对不上是常态;而夹具里行本来就是有序的,两个答案碰巧一致。

### 顺手搬了一处

"一个 box 值除以一个基数"这条规则原来住在 `Pie.pas` 里叫 `TyPieResolve`。
第二个系列去问**饼图**怎么读百分比,是"借用类型键"那个错误换了身衣服。
规则搬到类型所在的 Layout 单元,饼图那个名字留着、只是个转发。

### 三条老测试变红,是它们的本职

`funnel` 当过三条测试里的"还画不出来的那个类型"——
诊断面板点名的例子、控件"说不出口就是失职"的例子,
以及"发布的答案跟实际画出来的一致"那条循环里的一个下标。

它们红了不是回归:第一条注释里写着"发现这条变红,就是又一个类型会画了的提醒"。
例子往后挪到 `sankey`;循环那条把漏斗并进饼图那一支——
两者都没有坐标系,都不经过 `TyBuildSeriesMarks`,像素在控件那边数。

那一支的名单是**手写的**,不去问库。
问库就等于两边抄同一份表,而这条测试存在的全部意义,
就是第三个类型落到这里的那天会红一次。

## 60. Tier 1 第二十六批:表盘,以及一个不肯转的形状(2026-09-15)

### 唯一一个不按盒子布局的系列

饼图和漏斗都收 left/top/right/bottom,把画布缩一圈;
仪表盘收的是**圆心加半径**——`center` 的两个百分比分别对宽和高,
`radius` 对的是**较短边的一半**。三个百分比,两个基数。

正方形视口里这三者是同一个数,所以第一版规则测试全用矩形。

上游的类型里给它开了日历和矩阵定位,代码里一个都不读。这里没有盒子要尊重。

### 角度是两步,不是一步

选项里的度数是数学约定:0 在三点钟,逆时针为正。
第一步取负进入 y 向下的绘制系,第二步**把这一对**拿去归一化,
而且顺时针标志在传进去的时候是**反的**。

只做第一步的端口,画 `startAngle: 0, endAngle: 360` 会得到**负**的一整圈——
空表盘,或者反着画。而默认的 225/-45 归一化后就是它自己,
所以这个错在默认值上完全看不出来。

**方向不能用弧度断言**。少取一次负和多取一次负,
算出来的数都一样合理,而跟着写的测试会同意任何一种。
所以钉的是**设备像素的正负号**:默认表盘的起点在**左下**。

### 一个故意的分歧

上游把量程末端那个变量,当成色带循环的循环变量用了。
循环跑完,它里面装的是**最后一个色标**的角度——
而刻度、标签、指针的值→角度映射,拿到的都是它。

于是 `color: [[0.7, ...]]` 让整个刻度缩到七成,标签还老老实实写 min..max:
表盘悄悄读错,什么都不说。
更说明问题的是:把 `axisLine.show` 关掉,循环整个跳过,刻度又对了。
没有人会把"关掉一个装饰会修好读数"设计出来。

这里拆成两个字段:`EndRad` 是表盘,`BandEndRad` 是颜色停在哪。
默认的单个 1.0 色标下两者相等,画廊里所有上色的表盘也一样。

### 一个不肯转的形状

本库的形状**不带旋转**,只有文字带。这是绘制层的立身之本:
多边形直接按转好的点建就行了,不需要变换。

`path://` 不行。它的几何是**作者自己坐标系里的一串字符串**,
画的时候才由画笔装进一个盒子——没有"点"可以先转好。

而画廊里 22 条仪表序列中,**10 条的指针是 `path://`**。不转,就全部指向正上方。

所以路径这一种形状拿到了 `RotationRad` 加一个绕点,
在**描线时**压一次栈:平移、旋转、平移回来、描、弹栈。
填充和描边在这之后发生,对它一无所知。命中测试也一样——
路径本来就只按盒子命中,转过的路径不比正的更不准。

**绕的是轴心,不是盒子。** `offsetCenter` 活在跟着转的那个坐标系里,
所以偏移必须被同一次旋转带着走;绕盒子自己的脚转,
一个本该在三分之二半径处的指针会缩回圆心,还歪着。

### 圆头不是线帽

绘制元素的样式里没有 line cap,所以第一反应是"做不了"。
但上游的 `Sausage` 本来就**不是**线帽——
它是在带子两端各加一个**半径为带宽一半**的半圆,圆心落在带子的中线上。

半圆本库没有,整圆有。内侧那一半被带子自己盖住,颜色还一样,像素完全相同。

### 四条规则搬了家,一条搬回来

- `linearMap` 这一批是**第三份**了(饼图一份不夹,漏斗一份夹)。
  搬进 Layout,两个旧名字留成转发。审计还找出第四、第五份:
  Scale 单元的 `Normalize` 和**老 TTyGauge 控件**的 `TyGaugeFraction`——
  而后者的退化分支答的是 **0**,不是中点。名字里带 Gauge 的那个是唯一答错的。
- 弧角归一化从**饼图**搬到形状层。仪表盘去问饼图自己该怎么转,
  是"借用类型键"那个错误的第三次变装。
- `{value}` 替换是**第四份**:`ReplaceFirst` 原来是 LabelOpt 的私有函数,
  另一处直接写在控件里。导出。
- "把一个 w×h 的盒子挂在一个点上"这条,审计数出**七处**手写。第八处没写,导出了。

搬回来的是漏斗:上一批它自己抄了一份三段亮度表,
而且守卫跟原版**不一样**——它测 `fill = 0`,原版问宿主有没有填充。
不透明的黑是 `$FF000000`,不等于零。改回调共享的那个。

### 主题只加了一个键

刻度用 `TyAdvChartAxisTick`,小刻度用 `TyAdvChartMinorTick`,
刻度标签用 `TyAdvChartAxisLabel`,名字用 `TyAdvChartLabel`,
轨道用饼图"没数据时那圈"的 `TyAdvChartEmptyCircle`——
它们本来就**是**这些东西,不管选项管它们叫什么。

只有中央那个大读数没有现成的施主:图表自己的标题键是粗的,
但字号走标题尺度,而仪表的读数是**这张图本身**,不是压在它上面的抬头。
加了 `TyAdvChartGaugeDetail` 一个键,里面写了字面的 30px——
字面值就该待在主题文件里。

加新键是**两边的事**:改完 light.tycss 要重跑三个生成器,
否则运行时读的是编译进去的旧主题,`ResolveStyle` 答一个空样式,
字号 0,测量出来宽高为零,那行字**一个像素都不画**,还不报错。
这一批就是这么发现的。

### 夹具看不见的八次

前两次是画出来才发现的:

- 刻度标签**先量后改字号**:量的时候用主题的 9px,画的时候用选项的 12px,
  而渲染器是把字画进形状的矩形里的——`100` 出来是 `00`。
  单看"标签画出来了"的测试永远绿。
- 指针的第一版测试在**轴心上方**那几行找最饱和的像素。
  满量程时指针朝右下,那几行里只有**尾巴**,尾巴朝的正好是反方向。
  改成"离轴心最远的那个饱和像素",也就是针尖。

另外六次是第一轮变异测试报的存活体,原因各不相同,但没有一条是"断言太弱":

- **色标越界钳位**断在了 `BandEndRad` 上,而那个字段**自己另有一道钳位**。
  要断在色带**本身**的扇形上。一条规则有两处实现的时候,
  测其中一处等于没测另一处。
- **每条色带从上一条的终点开始**——这条在不透明色下**根本不可观测**:
  色带是倒序插入的,多画出来的那一截总是被前一条盖住。
  改成断几何:第 i 条的起点必须等于第 i−1 条的终点。
- **轨道不该吃命中**:轨道元素身上没有 datum,所以它就算不再 silent,
  命中测试照样答"没有数据点"。要问的是**哪个元素**回答了,不是哪个数据点。
- **富文本里的杂散花括号**:`{other}` 单独一个,前后都没有竖线,
  "往后找竖线"和"往后找竖线但不能跨过花括号"给的是同一个答案。
  要让那个杂散 token **后面还跟一个真的富文本段**。
- **`path://` 指针往哪边转**:默认偏移是 0,反着转的针尖跟正着转的
  **在同一个高度上**,只是左右相反。y 断言看不出来,要断 x。
- **`path://` 指针绕什么转**:偏移是 0 的时候,盒子的脚**就是**轴心,
  绕盒子转和绕轴心转是同一件事。要一个带 `offsetCenter` 的夹具。

## 61. Tier 1 第二十七批:雷达,第二个坐标系(2026-09-15)

### 网格层问那个问题,辐条答不上来

网格求解器、轴厚度求解器、轴绘制器,开头问的都是同一件事:
**这根轴贴在矩形的哪一边**。辐条没有边。

所以雷达自己算自己的几何,自己把网格画进绘制列表——跟饼图和漏斗一样。
共用停在**轴对象和它背后的刻度**上:那两层不含几何,
值→位置那套映射整个在里面,拿来就能用。

### 它的角度**不**取负,而饼图的取

饼图把选项度数取负进 y 向下的绘制系;雷达不取。
它保持数学约定,在**造点**的时候减掉正弦:

    x = cx + coord * cos(angle)
    y = cy - coord * sin(angle)

两条路,同一个结果:`startAngle: 90` 在两边都是正上方。
所以**第一根辐条落在哪里证明不了任何事**——照饼图那条规则写,
第一根依然朝上,而整张图是镜像的。要看**第二根**。

而且默认 `clockwise: false`:指标 1、2、3 是**逆时针**排的。

### 每一圈都是等距的,不管刻度说什么

上游把每根辐条强行对齐到**同一个** splitNumber 段的 dummy 刻度,
所以第 k 圈永远在 `r0 + (r - r0) * k / splitNumber`。

按 nice 刻度画圈的端口,会给一个指标六圈、给它邻居五圈——
而多边形的圈是**跨辐条连起来的**,数目不一样就闭不上。

### min/max 那条链有四段,每段都容易漏

1. **写了 `max` 且大于零,就把 `min` 钉成 0**(反过来同理)。
   判断是**falsy**不是 null 检查:显式写 `min: 0` 算没写。
   而且它**不看 `scale`**——`scale: true` 加一个 `max` 照样把底钉在零。
2. `scale: false`(默认)= **包含零**,而且只动**作者没写的那一端**。
3. 两端反了就对调。`max: 0` 配正数据就是这条:
   写下的零落在数据下面,对调之后**它成了底**。
4. 宽度为零要撑开,而且**怎么撑取决于零在不在里面**——
   包含零的那条已经把 [0,v] 造出来了,所以到这一步只剩下平的零,变成 0..1。

### 一个标量半径是**外**半径

`radius: '60%'` 归一成 `[0, '60%']`,不是 `['60%', '60%']`。
把标量复制到两端的端口,会在正中间画一圈"什么都不是"的环,还丢掉全部色带。

### 图例不再问"你是不是饼图"

`LegendNames`、`LegendSources`、`ApplyLegendFilter` 三处都在跟 `'pie'` 比字面量。
雷达的图例项是**行**不是系列,漏斗也是——后者上一批落地时就已经漏了。

换成一张表:`TySeriesLegendByDatum`。不是从 `colorBy: 'data'` 推出来的——
一个系列可以按数据着色而仍然只占一个图例项,那天一推就错。

顺带修了一处早就存在的偏差:图例色块直接按行号读色带,
而标记走的是共享的逐数据点规则,所以作者写的 `color` 列表
或者某一行自己的 `itemStyle` 会挪动扇形、把色块留在原地。

### 上游三处真崩

- `indicator: []` 是**默认值**,而 `radarLayout` 在零根辐条时
  `points[idx].push(...)` —— `points[idx]` 根本没被建出来。
- `pointToData` 在正中心除以半径 0,拿到 NaN,
  跟每根辐条比都是 false,带着 **-1** 这个下标返回给调用者。
- 多边形色带的守卫写的是 `if (showSplitArea && prevPoints)`,
  而 `prevPoints` 那时是 `[]` —— 空数组是真值,
  于是第一圈就进去了,用 **-1** 去取颜色桶,
  在 JS 里落到一个名叫 `'-1'` 的属性上,`forEach` 永远看不见它。
  每帧白造一个对象,而那个守卫什么都没守住。

## 62. Tier 1 第二十八批:一根柱子,四个矩形(2026-09-15)

象形柱图就是一根**不画自己那个矩形**的柱子。
带宽、列宽、偏移、堆叠全都照搬柱状图,画的时候把矩形换成一个图元,
或者换成一列图元。

### 四个矩形,合并任意两个都会错

| | 是什么 | 画不画 |
|---|---|---|
| 值矩形 | 柱状布局算出来的那个 | 不画 |
| 包围长度 | 一个**带符号**的像素标量,替代值矩形去**定图元大小和落点** | 不画 |
| 柱矩形 | 值矩形和图元跑到的最远端的并集 | 透明,但**只有它能被指针打中** |
| 裁剪矩形 | 从基线到真实值 | 不画,只裁 |

平铺一张图上这四个是重合的,所以随便合并两个都测不出来。
只要写了 `symbolBoundingData`、`symbolRepeat`、`symbolClip` 里的任何一个,
它们立刻分开。

柱矩形留着是有两个用处的:**外侧标签得让开图标**,
以及**读者指的是柱子,不是被裁剩下的那半个图元**。
所以图元全部 silent,一个数据点只有一个命中目标。

### pxSign 永远不是零,源码旁边写了理由

`boundingLength >= 0 ? 1 : -1`——注意是两条不同的分界:
像素随值增大时零判正,像素随值减小时零判负。
两条合起来是同一句话:**零长度的柱子,图元仍然朝正值那一侧**。

不能取零,因为零号会让图元的缩放变成零,
而零缩放会让"不随缩放变化"的描边宽度变成 NaN。

### 百分号量的是哪一边,两根轴不一样——而且重复会再改一次

- **横过柱子**:永远是那一列的宽度。
- **顺着柱子**:包围长度;
- **但只要重复打开**:顺着柱子那一边也变成列宽。

第三条是重复图元看起来大致是方的、而不是被拉长成一整根柱子的全部原因。
写成"两边都按列宽"或者"两边都按包围长度"的端口,
平铺时看不出差别,一打开 `symbolRepeat` 就整列变形。

### 重复是两遍加一遍,第二遍推翻第一遍的答案

1. 按包围长度数一遍,得到个数;
2. **把 margin 重新解一遍**,让这个个数正好铺满包围长度——
   解出来可以是负的,**图元互相压着就是想要的结果**,
   因为向上取整之后它们没有别的办法挤进去;
3. 只有 `true` 走第三遍:按**数据自己那段长度**再数一次。
   `'fixed'` 和写死的个数都保留整列,让裁剪去露出数据挣到的那一段。

写死个数会**连 margin 的数值一起作废**(第一遍整个跳过,第二遍重解),
但是**末尾感叹号还活着**——它改的是第二遍的除数。

### toIntTimes 两条分支都得抄

`|times - round(times)| < 1e-4 ? round : ceil`。
换成单独一个 round 或者单独一个 ceil,
在**每一根铺不整齐的柱子**上都会差一个图元——也就是所有人真会画的那些柱子。

而且喂给它的是一个除法结果,除数是作者能控制的长度。
JS 的 `Math.round` 没有定义域,这里的有:它奔着 Int64 去,出界就抛。
无穷和 NaN 在这儿是**常态**不是异常,所以四条守卫都在函数开头。

### symbolPosition 有两种"没写"

读法是 `get('symbolPosition') || 'start'`,
接着那个三元只判 `'start'` 和 `'end'`。于是:

- **没写** → `start`;
- **写错** → 掉到最后一条,`center`。

把两种没写合并成一个 `start` 兜底——这是最顺手的整理——
会把每一个拼错的图元挪到基线上去。

### 零值必须是"不裁"

`TTyChartElement` 多了一个裁剪矩形,这是这一层第一个真裁剪:
重复列要在**图元中间**切开,靠矩形求交做不到。

一开始"没有裁剪"是用一个非法矩形表示的,和 bounds 那套约定一致。
**全零矩形是一个合法的空矩形**——它把元素整个抹掉。
而库里有几处元素是 `Default(TTyChartElement)` 直接造的,图例就是其中一处。
于是图例一个像素都不画——症状是一张缺了一块的图,
从头到尾没有一句话提到裁剪。

**这个记录的零值必须落在安全的那一侧,而任何矩形都说不出这句话。**
所以现在是一个 Boolean 加一个矩形。

横过柱子那一边上游裁的是**整张画布**,不是绘图区:
比自己那列宽的图元本来就该探出去。这里给的是一个比任何画布都大的数,
不去假装知道一个拿不到的尺寸。

**两个裁剪,最后合成一个矩形。** `symbolClip` 只沿值轴切;
`clip` 切的是绘图区,是另一个问题、另一个默认值(这个类型是 false)。
柱状图回答 `clip` 的办法是**把自己的矩形缩小**——图元没有这条路,
半个图元不是一个小图元,所以它必须走元素的裁剪。
变异测试才发现这条:`clip` 为这个类型解出来了,然后**没人读**。

### 图元是**镜像**,不是转半圈

上游把图元沿值轴的缩放乘上 `(isHorizontal ? -1 : 1) * pxSign`,
负缩放就是一次反射:朝上的箭头在负柱子上朝下。
取绝对值的端口,两根柱子的图标都朝上。

镜像和旋转**不可交换**,所以角度先取负、反射后做——
这不是近似,沿坐标轴反射会把一次旋转变成它的反向,两条路完全等价。

只有点集形状能翻。圆、椭圆、正立矩形是自己的镜像,原样返回是对的不是漏的;
`path://` 不行——它的几何是一个字符串,画的时候才被塞进一个框,
而没有负的框。这一条写在函数旁边,因为修它属于路径填充那一层。

### symbolRotate 的方向反了,而且一直是绿的

zrender 的局部变换用 `matrix.rotate` 造,第一行是 `(cos, -sin)`,
在 y 向下的坐标系里,`(1, 0)` 转 +90° 落到**正上方**——**逆时针**。
画布自己的 `rotate` 是顺时针。这个端口取了画布那条。

后果是每一个转过的图元都沿着作者指的那根轴被镜像了。
守卫测试里写着"屏幕 y 向下,所以正角度把顶点甩到**右边**"——
测试钉死了这个 bug,而且它是**故意**加上去的:
在它之前只测了转半圈,而半圈是自己的镜像,测不出方向。

### parseFloat 读前缀,TryStrToFloat 读整串

`parsePositionSizeOption` 结尾是 `parseFloat`,而 `parseFloat` 读到第一个
用不上的字符就停。`TryStrToFloat` 回答的是**整串**是不是数字。

于是 `'20px'`、`'8pt'`、`'10 '` 这些按样式表习惯写的盒子值,
在端口里全部落回默认值,而不是二十、八、十。
`symbolMargin` 把这条摆到了台面上,因为上游对它**先字符串化再解析**,
连纯数字也要走这条路。

百分号是在**整串**上判的(`/%$/`),所以 `'50%x'` 是五十**像素**。
`'30%!!'` 去掉一个感叹号剩 `'30%!'`,不以百分号结尾——三十像素。

### 每一个选项都是逐数据点的

视图是通过 item model 读这一整组选项的,所以
`data: [{ value: 123, symbol: 'path://...' }]` 是画廊里象形柱图的**主流写法**。
只读系列层的端口会把同一个圆画九遍,看起来像丢了选项而不是丢了行。

数据仓把数据项的标量叶子按点号路径存下来,数组跳过——
所以一行上的 `symbolSize: [10, 20]` 读不到,保留系列的。
这条写在函数旁边:行上的成对形式是**真的不支持**,不是没测。

### pictorialBar 不跟 bar 共用一条带

ECharts 6 的列布局按**系列类型**建桶(`makeAxisStatKey2(seriesType, 'cartesian2d')`),
所以同一根轴上的象形柱图和柱状图各占一整条带,不是各分一半。

跟着类型走的还有两个默认值,选项树里永远读不到它们:
`barGap: '-100%'`(象形柱图本来就是要叠在一起的——
写两个系列的常见理由就是前景图标压在背景图标上)
和 `clip: false`(源码旁边说了:这类图通常把轴藏起来,
比值高的图元该探出绘图区,不该在边上被切掉)。

### 一处真崩:带末端间隙的除零

`symbolMarginNumeric = mDiff / 2 / (hasEndGap ? repeatTimes : max(repeatTimes - 1, 1))`——
那个 `max(..., 1)` 只保护了**没有**末端间隙的那条路。
写了末尾感叹号、而且柱子长度是零,除数就是字面意义上的 0:
JS 得到 ±Infinity,接着 pathLen 是 NaN,接着 `Math.max(..., NaN)` 返回 NaN;
FPC 在除法那一步就抛,躲过去了在 `Max` 那一步也抛——
**对一个静默的 NaN 做有序比较是会抛的**。

顺带说一句,"柱子比一个图元短"不是这条:那个个数向上取整成 1,
除数是 1,margin 只是解成负的。要够到这条,柱子长度得是零。

### 变异测试留下的两条等价体

都记在原处,不追:

- `if IsNan(x) or IsNan(y) then Continue` —— NaN 那一行的矩形在四行之后
  过不了 `TyRectFIsValid`,缺口两条路都会被丢掉。BuildBars 在同一句旁边
  早就记过同一条。
- `TyLeadingNumber` 里的 `if not seenDigit then Exit` —— 能走到这儿而没有数字的
  前缀(`''`、`'+'`、`'-'`、`'.'`),两行之后 `TryStrToFloat` 自己也会拒。

两条都是**第二道守卫遮住了第一道**:那一句把规则说在了它该在的地方,
但今天执行规则的不是它。

### 落地

- `source/tyControls.AdvChart.Pictorial.pas`(新):选项读取 + 重复算术 + 逐行覆盖。
  纯单元,不认识绘制列表,可以脱离图表断言。
- `BuildPictorialBar` 在 `AdvChart.Marks`,`cRenderers` 从四行变五行。
- `TTyChartElement.HasClip` / `ClipRect`,`TyRenderElement` 在自己那层 SaveState 里发裁剪。
- `TyMirrorShape` 在 `AdvChart.Shape`。
- `TyLeadingNumber` 在 `AdvChart.Layout`,`TyBoxStrOf` 改用它。
- `TySolveBarLayout` 跑两遍,一遍一个类型。

**已知偏差,都记在原处**:
上游把图元自己的描边宽度算进单元长度,这里没算——
描边宽度在渲染器按 PPI 缩放之前是**逻辑像素**,而这个构造器工作在设备像素里,
把一个逻辑数折进去只会在 96 dpi 上对;
`image://` 画不出来(纯单元里没有图片)——
画廊八条象形柱图里,`forest`、`hill`、`spirit` 三条因此是空的,
而 `vehicle`、`velocity`、`body-fill`、`bar-transition` 四条
正因为逐数据点的 `path://` 现在读得到了才画对;
`path://` 的镜像做不到;
行上的 `symbolSize` 成对形式读不到。

还有一条不在上面那张表里,因为它属于**高亮**那一层:
指针打中的是柱矩形,而柱矩形没有墨。高亮那段代码抬的是**被打中的那一个元素**,
所以象形柱图悬停时 tooltip 出来了、图元一点没亮。
上游抬的是这一根柱子的**那一组**图元——
要做得把"一个数据点对应一组元素"这件事告诉高亮那一层,
不是这一批该动的地方。

## 63. Tier 1 第二十九批:图,以及一个通常不存在的矩形(2026-09-15)

`graph` 是这个端口里**第一个自带坐标系的系列**。雷达的坐标系是个组件,
几个系列可以共用一个;图的不是——`view` 归画它的那个系列所有,
所以绑定器里认出这个名字就等于解析完了,剩下的几何它自己算。

这一批做的是:view、数据模型、`none` 和 `circular` 两个布局、
节点、边、曲度、箭头、标签。force、roam、`focus: 'adjacency'`、
以及跑在笛卡尔上的 graph 各自一批。

### 数据矩形通常不存在,而那才是常态

`view` 是一个**数据矩形**贴到一个**像素矩形**上。数据矩形是各节点自己写的
x/y 的包围盒——而 `circular` 和 `force` 的图**一个节点都不写**,
于是包围盒根本算不出来,上游就把数据矩形**换成**像素矩形,贴合变成恒等映射。

把"贴合"当成有意思的那一半是反的:**有意思的是通常没什么可贴**,
所以布局直接工作在像素里。

**一个没摆位置的节点毒化全部四条边界**,这不是要绕开的缺陷:
上游用 `Math.min`/`Math.max` 折叠,一个 NaN 让四条边界全成 NaN——
而这正是把整张图送进"没什么可贴"那条分支的东西。
跳过没摆位置的节点的端口,会把唯一摆了位置的那个节点贴满整块画布。

### `center` 在同一个函数里干两件事

`left: 'center'` 先被当成**位置**解析——`parsePercent` 在解析前把方位词
改写成百分比,所以它是**容器的一半,不是 NaN**——
然后又被当成**对齐**读一遍,把前面那个值覆盖掉。

映射说它解析成 NaN,审计把这条推翻了。差别在作者写了第四条边的时候露出来:
`top: 'center', bottom: 20` 会算出一个真实的高度,**根本走不到那条长宽比分支**;
按"NaN"写的端口在那儿算出 NaN,于是去走 0.8。

那 80% 又是从哪来的:两个尺寸都没写、并且有长宽比的时候,
**其中一根轴**取容器的五分之四(取哪根由长宽比决定),另一根跟着长宽比走。
它不是一个默认宽度,所以不能写成常数。

### 环上每个节点按自己符号的宽度分走一段角

`circular` 两遍扫:第一遍把每个节点的符号折算成半角 `asin(size / 2 / r)` 累加,
第二遍按 `(2π - 总和) / 个数 / 2 + 自己的半角` 往前推。
角度在**放置之前**先走半格、放完再走半格——所以节点落在自己那段的**中间**。

**所有节点一样大的时候这些全约掉了**:半角恒等于 π/个数,
于是均匀排列,和半径与符号大小都无关。
也就是说**默认那张图,算错了也长得对**——要靠不等大的节点才分得出来。

两行防御性代码的**顺序**也得照抄:先把 NaN 换成 2(上游说这是个随便取的值),
再把负数压成 0。反过来写,第二行就得去和一个 NaN 做有序比较,而那在这个编译器上是抛。

### `fixed` 是拖拽的词,不是选项的词

> **§64 修正**:这条只对**环**成立。force 读的是**选项里**的 `fixed`
> (`getItemModel(idx).get('fixed')`),沿节点 → 类别 → 系列 → option 根一路往上找。

上游在拖拽结束时把 `fixed` 写到**布局**上,布局器之后就不动这个节点。
"作者写了 x/y" 是另一回事:它决定 `layout: 'none'` 下节点在哪、
并且喂给数据矩形,但它**不阻止 `circular` 摆放这个节点**。

当成钉住的后果:画廊那张《悲惨世界》带着全套坐标,于是一个节点都没摆,
看起来像根本没请求过布局。

### 边按 id 认端点,而 id 不在覆盖表里

数据仓故意把 `value`、`name`、`id` 排除在覆盖表之外——那是数据点的**身份**,
不是写在它上面的选项。所以节点的 id 得单独问仓库要。

画廊那张图的 254 条边写的是 `{"source": "1", "target": "0"}`,
是 **id**,而每个节点的 name 是个人名。按覆盖表去读,254 条边一条都解析不出来。

### 曲度:一张表、一个键、两个方向

> **§64 修正**:"先出现的那一对是正向"不是上游的规则。上游的正向标记是三态的,
> 只在**某个键已有成员**时才被设;单独一条边、以及一来一回的两条,都是**未设**,
> 走反向分支。另外 `none` 和 `force` 要对查表结果**取负**并带 `needReverse`,
> 本节只写了环的那一种。

表的每一项是 `(i % 2 ? i + 1 : i) / 10 * (i % 2 ? -1 : 1)`——
**两个分支的分子不一样**,于是表是 0, -0.2, 0.2, -0.4, 0.4 …,
而下标 0 是唯一一项恰好为零的。

表长那行注释写着"确保长度是偶数",而 `length % 2 ? length + 2 : length + 3`
对任何整数输入都是**奇数**:文档里那张二十项的表,实际是二十三项。

**键上游是字符串拼的**:uid + 源 + 目标,用 `-->` 连起来,
反向键靠对这个字符串做切分拿到。于是**一个 id 里含 `-->` 的节点永远配不上对**,
不报错。这里按两个整数下标建键,这是**有意的偏离**——两个整数做不出这种事。

自环在上游是它自己的反向(键和反向键是同一个字符串);
按整数下标,它只会落进正向那一支,答案相同而没有别名。

### 环的控制点和别人完全不是一回事

`none` 和 `force` 把中点沿**垂线**推开:

    cp.x = 中点.x - (p1.y - p2.y) * curveness
    cp.y = 中点.y - (p2.x - p1.x) * curveness

**两根轴减的不是同一个差**,把一行抄成另一行会把每条曲线镜像掉——
而**水平边和垂直边都看不出来**,因为其中一项总是零。

`circular` 不是这样:它把曲度**乘三**,然后把中点朝**环心**插值过去。
所以三分之一正好把控制点放在圆心上,再大就冲过去。
每条边都向内弯——这就是弦图之所以是弦图。

### 箭头落在节点边界上,而切线是导数不是弦

`adjustEdge` 只在那一端**有符号**的时候才把边往回拉,拉的距离是节点的**半径**
(上游在函数开头把 scale 除以二一次,两端两条分支共用)。
不拉的话,50 像素的圆盘底下压着一个箭头,谁也看不见。

曲线那条分支要照抄三件事:
**点的顺序不一样**(布局存的是 起点、终点、控制点;贝塞尔要 起点、控制点、终点,
进出各换一次);
**近端先裁,远端拿已经裁过的曲线去量、但圆心还是原始端点**;
以及 `intersectCurveCircle` 那个"九个粗采样 + 三十二次二分"的求参数方式——
它不是解析解,旁边的注释说了原因:假设这一段到圆心的距离是单调的。

切线取的是**导数**,不是弦。两端的导数正好是控制多边形的两条腿,
所以弯得厉害的边上,箭头是顺着曲线出去的,不是指着对面那个节点。

### 上游真崩的地方

- `circularLayout` 在 `coordSys` 为空时,`if` 短路成 false,**下一行照样解引用它**。
  `simpleLayout` 是同样的守卫形状但不解引用,所以它无害地退化。
- `autoCurveness: Infinity` 会让浏览器**挂死**:`Infinity % 2` 是 NaN(假),
  于是 `len = Infinity`,循环永不终止。这里在循环前先钳。
- `autoCurveness: 1e7` 分配一千万项的数组,没有任何东西拦它。
- 第一次建表时 `appendLength` 是 `undefined`,`undefined > 20` 在 JS 里是 false——
  **这是正常路径上的一次 NaN 有序比较**。这里用负数表示"没有要追加的",不用 NaN。

### 落地

- `source/tyControls.AdvChart.Graph.pas`(新):`TTyGraphView`、三个集合、
  两个布局、曲度表、以及 marks 构造器。
- 绑定器多了第四条分支:`view` —— 唯一一个**没有组件可查**的坐标系。
- `TySeriesTypeHasRenderer` 的"在别处画"名单里多了 graph。

**这一批踩到的三个坑,都是"建好没接线"那一族的:**

1. **graph 的仓库有零列零行。** 非笛卡尔那段只认 radar 和 `scuBox`,
   而 graph 是 `scuData`,两边都不匹配。源码里那段注释**已经记过一次**了——
   漏斗和仪表当年就是这么死的。**这是第三次。**
2. `fixed` 当成了选项(上面那节)。
3. 边的 id 去覆盖表里找(上面那节)。

三个都不报错、不画错,只是**不画**。

### 变异测试说的话

六十个变异体,第一轮只杀掉二十四个。**三十六个存活里没有一个是断言写弱了**,
全是夹具看不见差别——而且这一批的夹具毛病比前几批更集中:

- **环的夹具是正方形的**,于是"取短边"和"取长边"是同一个数;
- **弦的中点正好就是环心**,于是"曲度乘三"在插值里被约掉;
- **对角线那条边断言的是包围盒**,而两个互为镜像的控制点给出**同一个包围盒**——
  盒子看不见的东西,曲线上的一个点看得见;
- **箭头的切线取的是 (1,0)**,于是 `atan2` 是零,减不减都一样;
- **平行边的条数是奇数**,而奇偶修正对奇数恰好是零;
- **裁边的测试直接调裁边函数**,于是"半径"和"长短轴取平均"这两条规则
  ——它们住在**构造器**里——一次都没跑到。

还有两条是**代码问题不是测试问题**:

- `TyGraphDataRect` 原本把"有没有没摆位置的节点"这条规则**说了四遍**
  (四个 min/max 各带一个守卫),于是破坏任何一个都观察不到——另外三个替它挡着。
  改成**先问一遍**再折叠。
- `left` 在 graph 上**永远不可能是 NaN**:它自己的默认值就是 `'center'`,
  而写不出来的值会落回默认而不是落回"没有"。所以上游那句
  `left = left || 0`、以及"从对边推出缺失那边"的那一步,
  在这个系列上都**够不着**。
  **(§64 推翻:够得着,而且是常态。**没摆位置的图长宽比是 NaN,
  居中那一步算出 `W/2 - NaN/2`,正是这句洗白把它变回 0。)守卫留着(规则该写在那一步),
  推导不写(不可达的代码不是移植,是负担),两条都记在原处。

**另外两条等价体**,也记在原处:裁边函数开头那句"两端都没有符号就直接返回"
——不返回也不会动任何东西;以及上面那条 `left` 的洗白。

**已知偏差,都记在原处**:曲线边是**采样成折线**的(形状记录里没有贝塞尔,
饼图的弧和 pin 符号早就是这么做的),但标签和箭头仍然用真正的 t 点和切线;
`nodeScaleRatio` 与 roam 的补偿缩放没做(没有 roam),所以裁边的 scale 恒为 1。
**[第四十五批已做:补偿缩放、数据空间裁边,见 §79。]**

## 64. Tier 1 第三十批:力导向,以及上游亲自给的答案(2026-09-21)

`layout: 'force'`。`initLayout`(`none` / `circular` / 其他)、`repulsion` 与 `edgeLength`
两个区间、`gravity`、`friction`、节点的 `fixed`、边的 `ignoreForceLayout`,
以及上游的 `preservedPoints`——缩放窗口时接着上次的位置继续退火,而不是重新撒点。

这一批最重要的不是力导向本身,是**测试第一次拿上游的运行结果当标准答案**。

### 基准:让上游用我们的随机数

`tools/advchart-oracle/graph-force.js` 在 node 里以服务端模式跑**真的** ECharts 6.1
(`dist/echarts.js`),把 `Math.random` 换成移植端用的同一个 xorshift32、同一个种子,
然后把每个节点在数据空间和像素里的位置、每条边的控制点写进
`tests/fixtures/advchart-graph-force.json`。每一次取随机数都检查调用栈,
只允许来自力导向求解器——别处取一次,整张表就不作数。

`TAdvChartGraphOracleTest` 逐项比对:**167 个用例、约 2200 个数全部一致**。
容差设为零再跑一遍,差异**只出现在两处**:

- **像素**:上游用矩阵把点带过去,这里用缩放加平移,末位不同;
- **环形初值**:`cos`/`sin` 在两个运行时里都不是正确舍入的。

除此之外**数据空间逐位相同**——包括《悲惨世界》那张图完整的 510 步。
所以测试就这么要求:夹具给每个用例标 `exact`(没有环的 105 个),
这些用例的数据空间按**精确相等**比,环形用例容差十亿分之一,像素一律百万分之一。

精确不是洁癖。第一轮变异里 `/ d / d` 改成 `/ (d * d)` 活了下来——
差异在末位,十亿分之一的容差看不见;改成精确比较之后当场就死。

这套做法以后每一批都该用:手推的期望值只能证明**推的人**和写代码的人想法一致。

### 力导向本身

- **斥力是 `pp` 上的"吸引"**。第二遍把对方的**上一位置**拉向自己,
  积分那一步沿 `(当前 - 上一)` 走——结果是推开。把符号"改对"会把布局翻成里朝外。
- **弹簧是就地更新的**(下一条边读到的是上一条边刚挪过的位置),斥力不是(只读 `p`、只写 `pp`)。
  所以边的顺序会改变结果,节点对的顺序不会。
- **`edgeLength` 区间要掉头**,`repulsion` 不掉头:值大的边更短。
  两个区间都是**原样**读的——`[30]` 的第二端是 `undefined`,不是第一端的副本,
  于是所有边长都成了 NaN,图空了。
- **`linearMap` 两端精确返回**:`[0.1, 0.7] → [0.3, 0.9]` 上直接套公式得
  `0.9000000000000001`,上游返回 `0.9`。定义域退化时取值域**中点**——
  默认斥力 `[0, 50]` 在所有节点同值时是 25,哪端都不是。
- **步数**:摩擦每步乘 0.992,降到 0.01 以下为止,默认 510 步;
  **至少两步**——布局阶段先走一步,视图再走,然后才看结果。
  上游没有上限;这里封顶 2000 步(覆盖九万以下的摩擦),NaN 或无穷的摩擦只走两步——
  上游那个循环永远出不来,而它画出来的永远是"所有自由节点都成了 NaN"。
- **没摆位置的节点在数据矩形里均匀撒点**,x 再 y,一个接一个。
  钉住但没有位置的节点也取一次随机数然后丢掉——**这一次取不取看不出来**:
  它被钉在 NaN 上,第一步就把所有自由节点带成 NaN,后面的随机数没人看得见。
  变异体存活,理由记在原处。
- **`initLayout`**:假值和 `'none'` 从作者写的位置出发,`'circular'` 从一个
  **按值**分角度的环出发(不是 `layout: 'circular'` 那个按符号宽度分的环,
  也不管 `fixed`),**其他任何字符串连作者写的位置都不用**,全部随机。

### `fixed` 有两个,住在两个地方

§63 说 `fixed` 是拖拽写的词。那只对**环**成立。force 读的是**选项里**的,
而且沿 item model 的父链一路往上:节点自己的 → 它的**类别** → 系列 → **option 根**。
写成 `false` 也会截住这条链。

类别只在节点用**下标**指它时才是父模型——上游拿作者写的值去索引一个数组,
按名字索引找不到东西;但 `'0'` 这样的规范数字串找得到(`'01'`、`'1.0'` 找不到)。
颜色按名字能找到类别,`fixed` 按名字找不到——**同一个节点对两件事给出两种答案**,这是上游的样子。

### 状态:什么时候接着算,什么时候重来

上游把 `preservedPoints` 放在系列模型上。这里按**系列下标**存在控件上,
**活过每一次重新布局**(每次 Relayout 都整个重建,这是唯一必须活下来的东西),
**只在 option 改变时清掉**——这个端口的 option 是整体替换的,等于上游的新系列模型。

- **矩形没变**:直接用上次的答案,一步不算。主题切换、焦点变化都会触发重新布局,
  上游根本不会为这些重新布局;跑五百步只会让每个节点无缘无故挪一点。
- **矩形变了**(缩放窗口):从上次的位置出发、摩擦重置,完整再退火一遍——上游的行为。
- **option 变了**:从头撒点。哪怕文本只差一个空格。

### 浮点陷阱关掉,出口洗干净

力导向的每个乘数都是作者给的,算到无穷大是**合法结果**,不是缺陷。
上游一声不吭地算完、画剩下的。这里:

- **`= 0` 在默认异常掩码下也会抛**——不只是有序比较。§63 那份映射说相等比较安全,
  实测推翻:`NaN = 0` 抛 `EInvalidOp`。
- 于是整个 graph 的布局阶段(`TyGraphSolve`)在**屏蔽全部浮点陷阱**的情况下跑。
  屏蔽之后比较、0/0、溢出、Inf−Inf 的行为和 JS 一致,这正是要移植的东西。
- **恢复掩码前要清 SSE 标志**。FPC 的 `ClearExceptions` 在 x86_64 上只清 x87,
  MXCSR 里留着的"无效操作"粘滞位会让**宿主之后的下一次陷阱**被报成 `EInvalidOp`
  ——哪怕那是一次普通的除以零,发生在跟图表毫无关系的代码里。审计抓到的,
  现在 `UnmaskFP` 自己清 MXCSR 低六位,有测试钉住。
- **出口洗干净**:像素位置不是有限数或超过一千屏(`cTyGraphFarPx = 1e6`)的节点当作不存在;
  控制点同理——画不出来的控制点**把边一起带走**(上游把它交给 canvas,canvas 拒绝那一段),
  不退化成直线。绘制路径是开着陷阱跑的,它拿到的一切都已经是有限的。
  **[第三十一批修正:只对「是数但画不出」的点成立。有一半是 NaN 的控制点上游画直线,
  端点带符号时整条不画。见 §65。]**
- **符号尺寸同样封顶**:节点和箭头超过一千屏按一千屏算。画面上没有区别
  (都盖满整个画布),但构造器会把半径加、平均、平方。

### 边的几何挪回布局阶段

上游的控制点是**布局**在**数据空间**里算的,视图只负责缩短。原来的构造器在绘制时、
在像素里自己算——两个后果:

- **环的弦弯向了左上角**。环的控制点朝**数据矩形**的中心插值,
  而构造器拿数据空间的中心去和**像素**中点插值。只要作者写了坐标
  (画廊那张环形《悲惨世界》就写了),数据矩形和像素框就不是一回事。
- **作者的曲度在开着陷阱的绘制路径里做乘法**,`curveness: 1e308` 直接溢出。

现在 `TyGraphEdgeGeometry` 在布局阶段、数据空间里算,经视图带到像素,洗过再存到边上;
构造器只读。

### 基准顺带抓到的,上一批已经"完成"的代码里的四个错

1. **没有位置的图,框是整个容器**——错。长宽比是 NaN 时那段分支**照样跑**:
   `NaN > x` 为假,于是**高度**取五分之四,宽度留成 NaN,最后从容器补满。
   所有不写坐标的 circular 和 force 图都在这个框里。**原来的测试把错的答案钉住了**。
2. **对齐词丢了**。上游在算完框之后把 `left || right` 的**原始值**再当对齐词读一遍;
   这里的共用解析器把 `'center'` 早早变成 50%,词没了——
   写出来的 `left: 'center'` 让框右移半个宽度,`left: 'right'` 让它整个出界。
3. **自动曲度**:正向标记是三态的、`none` 和 `force` 要取负带 `needReverse`、
   表长按**两个方向的总边数**算、作者数组里的非数字要**占位**而不是挤掉。
   一来一回的两条边原来在 `none` 下**重叠**,而原来的测试断言"两个数不相等"——
   钉住的正是重叠的那组数。
4. **环的控制点**(上一节)。

### 审计:四个维度,八个 agent

对照上游源码逐行审,每条发现再交给一个只负责驳倒它的核查员。23 条里 19 条成立,
其中这一批自己引入的只有 MXCSR 那一条;其余是上一批和更早的:

- **边的 `value` 只认 JSON 数字**。上游的数据层把 `'4'` 读成 4、`[9]` 读成 9、`true` 读成 1;
  force 是第一个读边值的布局,于是第一次看得出来。
- **端点只认一个键**:`retrieve(id, name, 下标)`。有 id 的节点**不能**按名字连;
  既没 id 也没名字的节点按 `'0'`、`'1'` 连。原来的实现先找名字再找 id,
  连出上游不存在的边、漏掉上游存在的边。**又一条测试钉住了错的答案**。
- **`edges || links`**:`edges` 先读,空数组也赢。原来的注释把顺序写反了。
- **`nodes` 是 `data` 的别名**,原来根本不读——写 `nodes` 的图一个点都不画。
  现在控件和测试都经 `TyGraphFillStore` 建仓库。
- **盒子的位置按上游 `parsePositionOption` 读**:四个词**精确**匹配
  (`'Center'`、`'centre'` 不是词),以 `%` 结尾(去掉首尾空白之后)才是百分比,
  其余走 `parseFloat`;`null`、`''`、`'auto'` 是 NaN,`false` 是 0。
  共用的解析器会转小写、会接受 `centre`——对别的组件无害,对 graph 的框会挪位置,
  **[第五十二批:对 title / legend 也不是无害的——`left: 'centre'` 上游是 x 5,不居中;两者已改用照抄的解析,见 §86。]**
  所以 graph 单独照抄一份。**`right/bottom/width/height` 在系列上没写时一路找到 option 根**
  (`getShallow` 不忽略父模型)——根上一个无关的 `width` 会改 graph 的框,上游就是这样。
- **`preserveAspect`**(`contain`/`cover` 与两个对齐)补上了:框在自己里面再排一次。

**核查员驳回的四条**:把裸字符串当类别名、字符串坐标、`zoom`/`center`
(属于 roam)、非数字的曲度——全在上游声明的选项类型之外,上游碰巧的行为不必照抄。
**[第四十五批:`zoom` / `center` 随 roam 一起读了,见 §79。]**

### 已知偏差

- **不动画**。`layoutAnimation: true`(默认)在上游是 510 帧、约八秒;这里一次算完,
  等于上游 `layoutAnimation: false`。Q7 只承诺了进入动画和状态过渡。
- 随机数有种子;步数封顶;无穷摩擦只走两步;同一矩形复用上次答案;
  超过一千屏的点、控制点、符号尺寸按上面的规则处理。
- **非等比视图下**(作者同时写了宽和高、节点又都写了坐标),上游的符号会被压扁、
  裁边在数据空间里做;这里符号是圆的、裁边在像素里做。归 roam 那一批(补偿缩放一起做)。
  **[第四十五批已做:符号按两个轴分别缩放、裁边在数据空间,见 §79。]**
- `force: null`、字符串写的区间和重力摩擦按"不是数"处理(上游会做字符串拼接)。

### 代价

`graph-webkit-dep`(492 个节点、806 条边)一次布局约 **1.4 秒**。瓶颈是每对节点
一次开方加两次除法——`/ d / d` 不能改成乘倒数,那样就不再逐位等于上游。
这就是算术下限:内层循环已经把外层节点的量提成局部变量,只快了百分之五。
上游默认把这些步分摊到 510 帧上;这里每次改 option 或缩放窗口都要付一整遍。
将来的出路是**用 Q7 的帧驱动把退火分摊到帧上**(和上游默认一致),
或者一个显式开启的 Barnes–Hut(画面不再等于上游,所以必须是开关)。

### 落地

- `source/tyControls.AdvChart.Graph.pas`:力导向求解器、`TyGraphSolve`(整条布局通道)、
  `TyGraphEdgeGeometry`、重写的曲度求解与视图框、`TyGraphFillStore`。
- `source/tyControls.AdvanceChart.pas`:`FGraphForce` 按系列存状态,`SetOptionText` 清掉。
- `source/tyControls.AdvChart.Builder.pas`:`TyFillSeriesStore` 多一个可选的数据键。
- `tools/advchart-oracle/graph-force.js` 与 `tests/fixtures/advchart-graph-force.json`。
- `tests/test.advchart.graphforce.pas`(新):基准、规则、控件接线三组。

### 变异测试

七十八个变异体。第一轮 69 个死、7 个活、2 个是**假死**
(删掉 `else if` 的那两行漏了分号,编译不过被记成"杀死"——脚本分得开,但得有人去看)。

七个存活里四个是**夹具没问到**,补了用例就死:

- `/ d / d` 与 `/ (d * d)`:容差放过了末位差异 → 改成精确比较(上面那节);
- 作者数组里的非数字**挤掉**还是**占位**:空洞本来就画直线,0 和 NaN 分不出来——
  但**第一个**元素是非数字时,"以零开头"那条判断会翻转;补了 `['x', 0.2, ...]`;
- 百分号判断**去不去首尾空白**:补了 `'25% '`;
- `false` 是不是位置:对 `left` 来说 `false` 和 NaN 最后都被 `|| 0` 洗成 0,
  看不出来;`left: true` 看得出来(上游是 1 像素)。

剩下三个是**等价体**,都在原处写了为什么:

- 钉住却没有位置的节点**取不取**那一次随机数(它把所有自由节点带成 NaN,后面的数没人看得见);
- NaN 摩擦**只走两步**(两千步落在同样的 NaN 上,只是慢);
- 两个长宽比已经相等时**不再重排**(重排只移动舍入误差,远小于百万分之一像素)。

另外,`width: false` 这个用例**上游自己崩了**:零宽的框,视图矩阵求不出逆,`copy(null)` 抛异常。
没有答案可比,用例删掉;这里零宽的框不崩,节点塌成一条竖线。

### 还在队列里

roam(连同补偿缩放和非等比视图)、`focus: 'adjacency'`、笛卡尔上的 graph、
**graph 的类别进图例**(现在图例里的色块是灰的)。

## 65. Tier 1 第三十一批:graph 的类别进图例(2026-09-21)

graph 写了 `categories`,图例列的就是类别,不再是系列名。关掉一个类别,它的节点和连着这些节点的边一起消失。
色块、节点、`lineStyle.color: 'source'`/`'target'` 的边,颜色出自同一张表。

### 过滤分两层,规则不一样

- 先按**系列名**整个过滤(legendFilter),留下来的再按**类别**逐个节点过滤(categoryFilter)。
- 类别这一层问的是 `isSelected`:`selected` 里关掉的名字算关,不管 `legend.data` 列没列;
  图表**给不出**的名字也算关——下标越界、没人声明的名字、布尔值。
  所以**只要有图例**,指向不存在类别的节点就不画;没有图例什么都不过滤;`show: false` 的图例照样过滤。
- 被滤掉的节点**还算**在数据矩形里。视图按全部节点拟合,远处那个点被关掉,画面不会重新放大。
  边的端点也按全部节点解析。
- 曲度表建在全部边上。力导向按**过滤后**的边下标查,初始布局按**原始**下标查,
  两次查询可能一真一假,于是留下初始布局写的旧控制点(§64 的 stale point)。

### 一个调色板游标,跨所有 graph

上游的 categoryVisual 给所有**画出来的** graph 共用一个调色板作用域:

- 先走 `itemStyle.color` 的父链:类别的 → 系列的 → option 根的,取第一个不是 null 的。
  它是假值才去调色板;是真值就**不占槽位**,渐变、`'none'`、画不出来的词都一样。
- 调色板先用系列自己的 `color`,取不到再用全图的,游标是同一个。
  取色**不取模**,游标按上一次推进它的那张调色板回绕——长调色板后面跟一张短的,就会落到短的末尾之外,取不到颜色。
- **取失败也会被记住**。同名的类别在后面的 graph 里照样没有颜色。只有无名类别不记,它会接着去问全图调色板。
- 被系列名关掉的 graph 不参与这一轮,后面的 graph 从它本来的起点开始取色。
  关掉第一个 graph,后面所有 graph 都会换颜色。

画不出来的词(`'auto'`、拼错的颜色、`true`),上游直接交给 canvas,canvas 不认,沿用上一次的填充色,结果看绘制顺序。
这里节点保留系列色,图例色块也用系列色。`'none'` 两边都是不填充。

### 图例色块

- 类别色块是 roundRect,颜色取类别色。完全透明的颜色按上游规则抬到 0.2,免得找不到。
- 图例列类别名,系列名只进 available。
- graph 被系列名关掉、它的类别又还在图例上时,上游会崩(对被过滤的系列取视觉)。这里把这些色块画成灰的。

### 系列上的 `category`

节点的 `category` 是用 getShallow 读的,会沿父链找到系列、再找到 option 根。
系列上写 `category: 1`,所有没写的节点都算第 1 类,图例也按它过滤。节点写 `null` 等于没写。

### 审计推翻的旧说法

- **§46 的"只有列出来的名字才能被关掉"**:不对。上游先读 `selected` 再读列表,每个系列名都在 available 里,
  所以 `selected: { L: false }` 不管 `legend.data` 列没列都会关掉系列 L,饼的切片也一样。
  带类别的 graph 上最明显:它的图例列的是类别,从来不列系列名。
  控件现在问完整的规则:列出的名字看标志(带着 single 模式的改写),没列出的看 `selected`。
  只有"可用性"那一半没照抄,空名字仍然永远不隐藏——§46 要防的"没名字的系列一出图例就整个变白"还在。
- **§64 的"画不出来的控制点把边一起带走"**:只对"是数但画不出"的点成立。
  控制点有一半是 NaN 的时候——水平的边乘上无穷曲度得到 `0 × ∞`,或者没摆位置的节点留下的旧控制点——
  上游的 `isStraightLine` 画成**直线**。可一旦端点带符号(箭头),adjustEdge 会在节点边缘去切这条"曲线",
  两端都算成 NaN,整条边就不画了。
- 环按符号尺寸分角度,量的是 `[w, h]` 的**平均值**,不是宽。`[w]` 平均出来是 NaN,按 2 算。
- `category: ''` 找的是**最后一个**无名类别(无名类别都登记在空串下)。布尔值既不是下标也不是名字。
- `1e999` 解析出来是无穷。原来先判小数部分再判范围,`Frac(∞)` 直接抛异常。

### 基准

`tools/advchart-oracle/graph-legend.js`,70 个用例,和上一批一样拿上游的运行结果当答案。
每个用例都经过**控件**走一遍——过滤、可用名、共享调色板、色块都在控件里,只有这条路能一起看到。比对:

- 留下哪些节点(按原始行)、位置、填充、符号;
- 留下哪些边、四种弯法(没有第三点 / 有 NaN 半边的画直线 / 不是有限数的不画 / 真曲线)、端点还在不在、
  作者写了线色时的描边;
- 图例的名字、选中状态、色块颜色和形状;
- 上游滤掉的 graph,这里也不布局。

第一遍会按原尺寸再画一次。第二次复用力导向的答案,必须和第一次完全一样,旧控制点也算。
总共 2363 项,全部一致。

两个细节:

- 带箭头时上游的 adjustEdge 会**就地改写**控制点,夹具记的是 `__original` 里布局给出的那个。
- 默认线色这里是主题色,上游是固定的灰,所以只在作者写了 `lineStyle.color` 时才比描边。

### 已知偏差

- 画不出来的颜色词,节点和色块用系列色(见上)。
- 颜色的 alpha 只有 8 位。alpha 小于 1/510 的颜色在这里就是 0,图例会把它抬到 0.2,上游不会。
- 数字写的类别名走端口自己的数字格式化,不是 JS 的 `String(n)`(`1e21` 这种写法不同)。
- `legend.data` 里写数字、写没有名字的对象,还是按原来的规则。上游前者永远匹配不上,后者是一个 single 模式能选中的换行。
- 系列名写成数字仍然不认。
- 边上单独写的 `lineStyle.color`、节点上单独写的数组 `symbolSize` 不读(老问题)。

### 落地

- `source/tyControls.AdvChart.Graph.pas`:按父链解析的类别颜色、共享作用域的取色(失败也记住)、
  `TTyGraphCatColours.Base`、环的平均尺寸(`RingSizeNaN`)、系列和根上的 `category`、
  `NaNCurve`、力导向状态里的 `Stale`、导出的 `TyGraphEdgeStroke`。
- `source/tyControls.AdvChart.Legend.pas`:带 option 的 `TyLegendHides` 重载、`TyLegendNameSelected`、`Greyed`。
- `source/tyControls.AdvanceChart.pas`:类别过滤、`LegendNames` 给 graph 的分支、共享的类别色表、
  色块、`GraphInkOf`,`LegendLayout` 交出去的是副本。
- `tools/advchart-oracle/graph-legend.js` 与 `tests/fixtures/advchart-graph-legend.json`。
- `tests/test.advchart.graphlegend.pas`(新);`test.advchart.graphforce.pas` 改了一条(无穷曲度的水平边画直线),
  `test.advchart.tooltip.pas` 多一条(图节点的色点)。

### 变异测试

五十一个变异体。第一轮 49 个:44 个死,4 个活,1 个假死(删掉一个 `else if` 分支时把语句结构删坏了,
编译不过被记成"杀死",重写成 `else if False` 再测)。

- **三个活在力导向的重放上**。同尺寸再画一次**根本不会重新布局**,第二遍比的是第一遍的边和它自己。
  第二遍之前先 `Invalidate`,三个当场都死。
- **图节点的 tooltip 色点**:`DatumColour` 里 graph 那个分支从来没被问过。补了一条:
  图例滤掉第一个节点之后,按视图行问到的必须是类别色,节点自己写了颜色的就是它自己的。

第二轮 7 个——4 个存活、重写的那个假死、两个新用例(无名类别越过自己调色板的末尾去问全图的;
节点自己的颜色按原始行读)对应的——全死。全量 **7686** 绿。

### 还在队列里

笛卡尔上的 graph(graph-life-expectancy 有 19 个系列)、roam(连同补偿缩放和非等比视图)、`focus: 'adjacency'`。

## 66. Tier 1 第三十二批:直角坐标系上的 graph(2026-09-21)

`coordinateSystem: 'cartesian2d'` 的 graph 以前能解析、画不出来。现在节点按两根轴落位,连线、箭头、标签、tooltip 都有。
目标示例是画廊里的 `graph-grid` 和 `graph-life-expectancy`。

### 上游在轴上只做一件事

不是 view 的坐标系,上游只有一种布局:每个节点放在 `dataToPoint(x, y)`,这就是全部。

- `layout: 'force'` 和 `'circular'` 都在开头判断坐标系类型,直接返回。写了也没用,节点位置和 `none` 一模一样。
- 盒子、`zoom`、`center`、`preserveAspect`、`nodeScaleRatio` 一概不读。节点按自己的 `symbolSize` 像素画,箭头也是。
- 数据项上写的 `x`、`y` 不算位置。位置来自数据的两个维度:类目轴上一个裸数字就是"行号 + 值"(`graph-grid` 的 842 落在 Mon),值数组取前两列。
- 数据和别的直角坐标系列一样参与轴的范围。图例把节点滤掉以后,范围按剩下的算。
- 连线的控制点在**像素**里算,曲度取 `none` 那一族(取负、按原始边号查)。两根轴比例不同,在数据空间里算再映射,曲线会往另一边弯。
- 什么都不裁剪。轴外的值画在 grid 外面。

### 仓库和求解

- 轴上的 graph 用轴自己的 x、y 两列,没有 `value` 列。还是读 `data || nodes`,还是把系列和根上的 `category` 填进没写的节点,**从不读 dataset**:上游 graph 只认自己的节点。
- `TyGraphSolveOnCoordSys`:在节点的**视图行**上读两列(图例过滤是个视图),`dataToPoint`,然后算曲度和控制点。
  有一个坐标是 NaN 的节点没有位置,连线跟着不画。上游会保留另外半个坐标,但半个点两边都画不出来。
- 两个求解器共用同一段"收集节点、边、存活者"的代码和同一段曲度查询。`TyGraphEdgeGeometry` 不传 view 时就用像素位置,也不走环形公式(环形要 view 的中心)。
- 控件里 `FGraphLaidOut` 取代了"`FGraphs[i]` 非空"这个判断:轴上的 graph 没有 view,也是布局好的。`TyBuildGraphMarks` 去掉了 view 参数,它从来只拿它判断是不是 nil。

### 名字:getName 会回落到类目

上游 `createSeriesData` 把"条目名"交给**第一个类目维**。条目自己没名字时,`getName` 回答类目文字。
所以 `graph-grid` 的标签是 Mon…Sun,不是空的。

- 新增 `TTyDataStore.GetItemName`:先看自己的名字,没有就取第一个 ordinal 维的类目文字。
- 标签的 b 占位符(`TyLabelText`)和 tooltip 的名字都改走它。**这是全库的**:类目轴上的柱子、折线写 `{b}` 以前是空的,现在显示类目。
- 节点的**键**不变,还是作者写的 id、名字或位置。上游也是:裸数字节点按 '0'、'1' 连,连 'Mon' 找不到。

### 连线不再冒充节点

连线的行号和节点的行号在同一个数字空间里。以前鼠标移到第一条连线上,tooltip 说的是第一个节点。

- `TTyChartDatumRef.IsEdge`,连线用 `TyChartEdgeDatum`。零值是 False,其他所有数据不受影响。
- 按行找元素(`IndexOfDatum` / `IndexOfDatumInk`)跳过连线。
- 连线的 tooltip 照上游 `formatTooltip`:一行 `源 > 目标`(两头都用 getName),没有标记,没有系列标题,有 `value` 才显示值。
  用系列级的 tooltip 设置,不读同行节点的。颜色是连线的描边。
- 回调参数多了 `DataType`:graph 的节点是 `'node'`,连线是 `'edge'`,其他为空。

### 基准

`tools/advchart-oracle/graph-cartesian.js`,22 个用例,直接读上游的 `getItemLayout`(轴上已经是像素,不能再映射一次)。
比对 plot 矩形、每个节点的原始行和像素位置、名字、每条连线的弯法、控制点、两端在不在、tooltip 名字和值、作者写了线色时的描边,
以及上游滤掉的 graph 这里也不布局。380 多项,全部一致。

用例覆盖类目 x / 类目 y / 两根值轴、值数组带多余列和数字名、缺值、像素曲度、自动曲度(含过滤后按原始边号查)、
force 和 circular 被忽略、条目的 x/y 不算、图例按类别过滤、系列级 `category`、`nodes` 旁边有 dataset、轴外的值、第二根 y 轴、
single 模式的图例、没有 data 的类目轴、有名字的节点、带值的连线、按端点着色的连线。

### 顺带挖出的两个全库问题(单独成批)

为了让比对只看 graph,夹具把所有轴的标签和刻度藏了起来,还避开了两种取整规则会分歧的轴范围。原因是这两件事 port 都和上游不一样:

1. **刻度间隔**。上游(v5 和 v6 都是)`intervalScaleNiceTicks` 用 `nice(span/splitNumber, round)`,档位 1/2/3/5/10,阈值 1.5/2.5/4/7。
   port 是不取整的 1/2/2.5/5。span 为 7 时上游间隔 1、这里 2;`graph-grid` 的 y 轴上游是 0 到 6000 七格,这里四格。
   **[第三十三批已修,见 §67。]**
2. **grid 收缩**。v6 的 `outerBoundsMode: 'auto'` 外边界默认是**整个画布**,标签不越出画布就不收缩。
   port 把 grid 矩形当外边界、按标签厚度收缩,等于 `containLabel: true`,plot 比上游普遍小三十像素左右。

两处都在 Tier 0 的原话旁边加了标注。两批都会动很多旧测试,要先写 oracle。

### 已知偏差

- `graph-life-expectancy` 的节点颜色来自 visualMap(还没有),这里是系列色。
  **[visualMap 的编码第五十四批已有(§88);graph 节点色还没接,排在 B3。]**
- 节点的 `itemStyle.borderColor/borderWidth` 不画,每个数据项自己的 `label`(那三个年份标签)不读,图例色块没有 2px 边框。view 上的 graph 也一样。
- 内部标签的自动描边没有:上游给 inside 文字加一圈 2px 宿主色描边,溢出节点的白字靠它看得见。这里 "Very Loooong Thu" 溢出的部分白底白字。全库的问题。
- `{c}` 在轴上读值轴那一列;上游是原始值,值数组会整个拼出来。两个目标示例都不用。
- 没有 `tooltip` 组件的图(life-expectancy)这里照样弹 tooltip。全库的问题。
- 轴上的 graph 不能拖节点(拖动还没做)。

### 落地

- `source/tyControls.AdvChart.Graph.pas`:`TyGraphSolveOnCoordSys`、共用的收集和曲度查询、`TyGraphFillNodes`、
  `TyGraphEdgeGeometry` 的无 view 分支、`TyBuildGraphMarks` 去掉 view 参数、连线用边数据引用。
- `source/tyControls.AdvanceChart.pas`:轴上 graph 的仓库分支和求解分支、`FGraphLaidOut`、`{c}` 列、tooltip 和颜色的连线分支、`GraphNodeName`。
- `source/tyControls.AdvChart.Paint.pas`:`IsEdge` 和 `TyChartEdgeDatum`,按行查找跳过连线。
- `source/tyControls.AdvChart.Data.pas`:`GetItemName`。`source/tyControls.AdvChart.LabelOpt.pas`:b 占位符走它。
- `source/tyControls.AdvChart.Handlers.pas`:`DataType`。
- `tools/advchart-oracle/graph-cartesian.js`、`tests/fixtures/advchart-graph-cartesian.json`、`tests/test.advchart.graphcartesian.pas`(新)。

### 变异测试

三十二个变异体。一个是等价的:半个坐标是 NaN 的节点在前面跳过,还是交给后面的清洗,结果一样——清洗本来就把半个点清成 NaN。
它从清单里拿掉,理由记在这里。

剩下 31 个,第一轮活了一个:**轴上不做清洗**。半个点早就跳过了,夹具里又没有远得离谱的值,清洗只剩"一千屏"那一条管得着。
规则测试里补了一个 1e12 的节点,当场就死。全量 **7692** 绿。

### 还在队列里

刻度间隔的取整规则 → grid 的外边界收缩 → roam(连同补偿缩放和非等比视图)→ `focus: 'adjacency'`。

## 67. Tier 1 第三十三批:数值轴的取整刻度和原始范围(2026-09-21)

数值轴和 log 轴的范围、步长、每一个主刻度和次刻度,现在和上游逐位相同。这是 §66 挖出的第一个全库问题。
`graph-grid` 的 y 轴现在和上游一样是 0 到 6000 七格。

### 步长:nice 的阶梯

- 步长是 `nice(span / splitNumber, round)`:1、2、3、5、10 乘 10 的幂,阈值 1.5 / 2.5 / 4 / 7,
  再用 toFixed 按指数截回小数(3 × 0.1 是 0.30000000000000004,截完是 0.3)。
- 10 的幂查 V8 自己 `Math.pow` 的表,-323 到 308 全覆盖。V8 的 10^-4 不是离它最近的 Double
  (是 0.00009999999999999999),FPC 的 `Power` 碰到负指数差得更远,1e-10 差 8 个 ulp。
  尾数差一个 ulp 就可能落到 1.5 这种阈值的另一边,换一档步长。
- 精度是 `getPrecision(步长) + 2`,toFixed 钳在 0 到 20 位。1e21 以上照 JS 原样返回——这一条不能省:
  FPC 的 `Str(x:0:p)` 结果超过 255 个字符就改写成科学计数,只留两位有效数字,7.015e301 会变成 7.0E+301。
- toFixed 按**二进制值**取整,和规范一样:(1.005).toFixed(2) 是 1.00,因为 1.005 实际比它小一丝。
  最初用 Str/Val 实现,Str 按自己的十七位十进制取整,给出 1.01。现在用大整数精确算 m·10^p 再移位得到 n。
  n 小于 2^53 时,n 和 10^p 都是精确的 Double,一次 IEEE 除法就是正确舍入;更长的做长除法,
  商取到 64 位以上、记住余数是否非零,再就近偶数舍入到 53 位。**不走 FPC 的 Val**:它不是正确舍入,
  把答案写成文本再读回来,276712 个向量里错 22 个,都差一个 ulp。现在和 node 比 276712 个一般向量、
  再加两百万个长答案向量,零差异。
- splitNumber 是 `round(max(写的值 || 默认, 1))`:0 和 NaN 用默认值,2.5 取 3,小于 1 取 1。
- minInterval、maxInterval 在 nice 之后夹。

### 范围:向外取整,刻度在范围里面

- 先照 `intervalScaleEnsureValidExtent` 校验:平的范围按自身一半张开(max 被钉住时只往下张),
  0 张成 [0, 1],端点不是有限数就整个换成 [0, 1]。
- nice 刻度范围是 `ceil(lo/步长)·步长` 到 `floor(hi/步长)·步长`,在范围取整**之前**算。
  钉住的一端如果不是步长的倍数,自己成为首刻度或末刻度。
- 没钉住的一端按步长向外取整。
- 写了 `interval` 只换刻度的步长。范围还是按自动步长取整(上游注释自己说这是历史行为),刻度走满整个范围。
- 数据小到 1e-20 左右时,toFixed 会把步长截成 0,取整结果是 NaN。上游的 `setExtent` 跳过 NaN 端点,
  范围停在校验后的样子,一个刻度都没有。这里照做,整段按 JS 的算术走,不抛异常。
- 刻度两头补范围的端点;超过 3000 个就一个都不给;加一个步长加不动(`tick + 步长 = tick`)就停。

### 次刻度

- 切的是"展开到 nice 范围"的主刻度列表:钉住的端点往外推到步长的倍数,切完只留严格落在范围里的。
  min 钉在 3、步长 20 时,第一个主刻度 20 前面照样有 4、8、12、16。
- 每一段的精度是 `getPrecision(段长) + 2`。三等分是满精度的循环小数,也逐位相同。
- log 轴也是在**值空间**里线性切:1 到 10 之间是 2.8、4.6、6.4、8.2。

### log 轴

- 不走 nice。步长是 `max(10^quantity(span), 1)` 个十年;`err = splitNumber / span × 步长` 不超过 0.5 时再乘 10,
  这只有 splitNumber 不超过 4 时才可能。minInterval、maxInterval 不读。
- 刻度和范围回到值空间走 V8 的 `Math.pow` 表。取整没动的一端保留它进来时的值——上游的 lookup,
  不只管钉住的端点:10^log10(3) 在这里是 2.9999999999999996;数据从 10.000000000000002 起,首刻度就是它,不是整 10。
- 只有 log 轴在 log 空间里 nice。断轴的装饰器也做变换,以前被当成 log 轴,步长在压缩后的空间里走,
  刻度出了范围、顺序也乱(0、20、97.89、117.89、137.89、100)。上游在值空间里 nice 断轴(跨度扣掉断开的部分,这个还没做)。
  断轴还没接到任何 option 上,图表碰不到,但单元测试碰得到。
- 范围里没有小于等于 0 的端点:上游的 `sanitize` 把它挪到数据的最小值(`min: 0` 变成数据最小值)。
  数据里的 0 和负数本来就不进范围。
- 挪完如果反了(`min: 0, max: 2`,数据从 3 起):上游本想用 `ensureExtentAscSimply` 合上,可它先问
  `isValidBoundsForExtent`,那个函数要求 start ≤ end,所以永远不动手。log scale 整对拒收,留着初始的
  `[Infinity, -Infinity]`,校验成 [0, 1],也就是 1 到 10。这里照这个结果做,不照注释的意图做。

### 空轴

没有数据、也没有可用的 min 和 max 时,上游的 `isBlank` 为真:轴线和轴名照画,标签、刻度、次刻度、分隔线、分隔区一概不画。
nice 照样给出 [0, 1] 和上面的刻度,oracle 比的也是它们。以前这里在空图上标 0、0.2 … 1。

- 原始范围第 4 步算出的 Blank 交给 scale(`MarkedBlank`)。只有 max 也还是空轴,min 和 max 都有才不是。
- 画轴部件的五处(标签规格、`TickCoords`、次分隔线、次刻度、画出来的标签)改走 `TyDrawnTicks`:空轴给空列表。
  `GetTicks` 本身不变,和上游一样照样回答。
- 时间轴没数据时范围是今天,同样是空轴。

### 时间轴顺带修的两处

两处都早于这一批,这批把时间轴也接到了 `TyAxisRawExtent` 上,oracle 顺手比了它们:

- **平的范围在 scale 上左右各开一天**(上游 `calcNiceForTimeScale`)。以前只在生成刻度时开,scale 的范围还是平的,
  每个刻度都归一到轴的正中间。
- **minInterval / maxInterval 夹住近似间隔**,目标刻度数跟着变成 `跨度 / 近似间隔`。DoAxis 早就把两个值写进了时间 scale,
  `GetTicks` 从来没读过。

### 原始范围,照 scaleRawExtentInfo 的顺序

`TyAxisRawExtent` 一步一步照抄:

1. 数据范围,`dataMin` / `dataMax` 只扩不缩。
2. `min` / `max` 钉住端点。`'dataMin'` / `'dataMax'` 取数据;其余走 `Number()`。NaN 也钉住——那是作者写的坏边界,轴变空。
3. `boundaryGap` 只作用在没钉住的一端,单位是**数据跨度的比例**:数字就是比例,`'10%'` 是 0.1,
   不带 % 的字符串按 parseFloat 读(`'1'` 就是一整个跨度)。只有一个值时拿它的绝对值当跨度。
4. 不是有限数的端点算没有。
5. 零:只在普通数值轴上、`scale` 为假、两端同号、那一端没钉住时。
6. 反了就翻过来,轴跟着反向(`legacyMinMaxDontInverseAxis` 例外)。
7. `startValue` 并进范围,钉住它挪动的那一端。柱子的值轴不写也要一个起点:log 轴是 1,其余是 0(`scale: true` 的柱子不并)。
8. log 轴的 sanitize。

被推翻的两句旧话:

- `TestAValueAxisBoundaryGapPadsTheExtent` 说不带 % 的数字字符串一律不认,理由是"上游两种读法都没写"。
  上游代码其实选了一种:parseFloat 之后当比例。测试已改,原处有标注。
- `StepMantissaIsNice` 认 2.5、不认 3。那是 port 自己的阶梯。

两处和下一节那条测试的改动都在原处写了标注。

### 顺带暴露的一个测试缺陷

`TestTheGridNeverPaintsOverAnAxisLine` 单跑绿、全量红。二分前面 549 个 suite,找到的是 `TComboSimpleModeTest`。
它调 `Application.Initialize`,之后整个进程的字体走真实度量,plot 的底边从 198 挪到 195。
扫描列取的是 plot 正中,新阶梯下 x 轴正好在 1.5 有一个刻度;onZero 的 x 轴刻度从轴线那一行往下画,把交点盖住了。
上游在同一个 group 里也是先画轴线再画刻度,画法没错,错在扫描列选得太巧。改成取两个刻度的中点。

### 基准

`tools/advchart-oracle/value-axis.js`:134 个结构化用例加 400 个随机用例。scatter(或 bar)放在被测的轴上,
默认是 yAxis[0],`axis: 'x'` 时是 xAxis[0](横向柱、x 数值轴)。读上游的 `getExtent()`、`getConfig().interval`、
`getTicks()`、`getMinorTicks()`、`isBlank()` 和 `axis.inverse`。覆盖堆叠(总和、正负混合、横向)、8 条时间轴、6 条空轴。
39188 项比较(17039 个主刻度、18868 个次刻度)全部逐位相同,log 轴和时间轴也是。

上游的开发版在一条用例上自己断言失败(1e-25 量级的数据,nice 刻度范围越出了范围)。
这条改用生产版跑,也就是网页上实际加载的那个,fixture 里标了 `productionBuild`。

### 已知偏差

- 刻度**标签**的格式(getPrecision / toFixed / addCommas)还是旧的,下一小批。axisPointer 的标签精度一起:
  上游 `precision: 'auto'` 用步长的小数位加 2(37.25),这里用步长自己的(37),log 轴上显示成 4 而不是 3.72。
  **[第三十四批已修,见 §68。]**
- **非整数次幂**走 FPC 的 `Power`,和 V8 的 `Math.pow` 末位不同:log 轴写了小数 `interval`(0.5 → 3.1622776601683795)、
  底数不是 10 或 2。标签看不出来。
- **containShape 没做**:柱子放在数值或时间**基轴**上时,上游把平的 0 张成 [-1, 1],还把 mapping 范围放宽半个带宽,
  两头的柱子不被截。这里都没有。刻度一致,柱子的像素位置不同。
  **[第四十一批已做,见 §75。时间轴不走张成 [-1, 1] 那条,平的时间范围仍是前后各一天。]**
- `logBase` 小于等于 1 这里一律当 10;上游是 `logBase || 10`,0.5 这种底数照用。
- 雷达指示器和 `alignTicks` 都要 `scaleCalcAlign`(NICE_MODE_MIN 加 increaseInterval),不在这批。
- getPrecision 走字符串的那条路(负数、小于 1e-14)28572 个里差 7 个,步长不走那条路。

### 落地

- `source/tyControls.AdvChart.Scale.pas`:`TyJsRound`(用 Int 实现,过二十亿不溢出)、`TyJsPow10`(V8 的表)、
  `TyJsToFixed`、`TyQuantityExponent`、`TyNice`、`TyGetPrecision`、`TyIntervalPrecision`、`TyValidSplitNumber`;
  `TTyIntervalScale` 的 `Niceify(splitNumber, interval)`(外面一层屏蔽 FP 陷阱)、刻度和次刻度;
  log mapper 的反变换查 V8 的表。
- `source/tyControls.AdvChart.Series.pas`:`TyAxisRawExtent` 和它的几个解析函数,`DoAxis` 按上游顺序重排。
- `source/tyControls.AdvChart.Builder.pas`:log 轴打开 `LogRule`;标签规格走 `TyDrawnTicks`。
- `source/tyControls.AdvChart.Coord.pas`、`source/tyControls.AdvanceChart.pas`:刻度坐标、次分隔线、次刻度、画出来的标签走 `TyDrawnTicks`。
- `source/tyControls.AdvChart.Time.pas`:`TyTimeTicks` 多一个带 minInterval / maxInterval 的重载。
- `tools/advchart-oracle/value-axis.js`、`tests/fixtures/advchart-value-axis.json`、`tests/test.advchart.valueaxis.pas`(新)。

### 变异测试

三轮。

**第一轮 87 个,活 7 个。** 用一个工作流逐个分析,每个结论再交给一个专门反驳的复核者:

- **量级修正**:log(1000)/LN10 是 2.9999999999999996,上游和这里都会把指数往上补一。圆整阶梯对 1000 看不出来,
  对 1e26 以上看得出来(10 × 1e26 比 1e27 小一个 ulp,toFixed 在 1e21 以上原样返回)。补了 0 到 5e27 的用例和单元断言。
- **用户步长按自己的精度取整**:原来的用例步长都是一位小数,两种精度取整结果一样。补了 0.125 和"步长 1 配钉住的 0.001"。
- **log 轴钉住的 min 读回原值、首刻度走查表**:唯一钉住 min 的用例是 5,而 10^log10(5) 在这里恰好是 5。换成 3 就不是。
- **StillNiced**:没有任何图表路径在 Niceify 之后再设范围,只有单元测试钉得住。复核者指出线性那一半的"变异体"其实就是上游生产版的行为
  (留着旧的 nice 范围),所以测试写成 port 自己的契约,log 那一半是必须的:变异后的刻度是 1、10、100、1000、100。
- **log 轴上端 ≤ 0 的 sanitize**:`max: 0` 先被第 6 步翻到了下端,碰不到这一行。补了 `min: -5, max: 0`。
- **NiceifyJs 里的反序交换:等价**。唯一调用方交进来的范围都经过会排序的 `TyRange`,log 变换单调;上游那一行同样是死代码。代码照抄保留。

同一个工作流还审了 oracle 够不到的调用方,本节"空轴""时间轴顺带修的两处"、log 查表不限钉住、断轴不当 log、x 轴和堆叠的用例都来自这次审计。
审计另外发现的 containShape、雷达、alignTicks、axisPointer 精度写在已知偏差里。

**第二轮 27 个**(第一轮的 6 个加新代码),活 1 个:toFixed 的除法捷径。它引出了 Val 不正确舍入这件事,长答案改成长除法。

**第三轮 110 个**:前两轮所有被杀的变异体按最终代码重跑,加上长除法的新变异体。活 1 个:toFixed 里"1e21 以上原样返回"。
新实现里凡是 ≥ 2^53 的 Double 都是整数,早从"整数原样返回"那一支出去了,这一行是死代码,删掉,理由写在注释里。

**记为等价、不进清单的**(都有证据):

- 长除法的平局取偶、余数 sticky、商的低位检查。对 toFixed 的输入观测不到:长答案满足 x·10^p ≥ 2^53,n/10^p 离 x 至多半个 ulp 左右,
  贴着一个 Double 而不是两个 Double 的中点。三个变体在两百万个长答案向量上和 node 零差异。一般意义上的正确舍入需要它们,代码保留。
  (平局还能证明完全不可能:p 位小数要么够精确表示 x,要么不够表示任何中点。)
- 短答案也走长除法:两条路径在 276712 个向量上都和 node 零差异,捷径只为快。
- mant 进位到 2^53 后的重新规格化:2^53·2^k 和 2^52·2^(k+1) 是同一个 Double,那段已删。

全量 **7702** 绿。

### 还在队列里

刻度标签的格式(连同 axisPointer 的精度)→ grid 的外边界收缩 → containShape → roam(连同补偿缩放和非等比视图)→
`focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign`(雷达指示器和 `alignTicks`)。

## 68. Tier 1 第三十四批:数值轴上的文字(2026-09-22)

上一批让刻度的**值**和上游逐位相同,这一批让它们的**文字**也相同:刻度标签、`axisLabel.formatter` 模板、axisPointer 标签、axis tooltip 的表头。

### 上游只有一个函数

数值轴和 log 轴上凡是数字变成字,都走 `IntervalScale.getLabel(tick, opt)`:

1. 精度:没给就是这个值自己的 `getPrecision`;`'auto'` 是 scale 的 intervalPrecision(步长的小数位加 2);给了数就用它。
2. `round(value, 精度, true)`:精度钳在 0 到 20,再 toFixed,拿到的是**字符串**。精度不是数时,直接是值的 ToString。
3. `addCommas`:只给第一个小数点前面的数字串分组。

刻度标签不带 opt,每个刻度用自己的精度;pointer 标签和表头带 `label.precision`,默认 `'auto'`,所以步长为 1 的轴上 pointer 读 "3.00"。
log 轴的 `getLabel` 转给它的 intervalStub:数值是幂,`'auto'` 是十年步长的精度,也就是 2。

port 以前两处刻度文字都是 `FormatFloat('0.######')`:不分组、最多六位小数(1e-7 印成 0)、大约十五位有效数字、1e18 以上印成 `1E18`。
上一批 fixture 里 16933 个刻度有 12229 个文字和上游不同。pointer 用的是"步长自己的小数位、不补零",37.246964 显示 37,上游是 37.25。

### 三个精确的 JS 数字转文字

全部在 `tyControls.AdvChart.Scale`,不经过 FPC 的 `Str`、`Val` 或 `FormatFloat`:

- `TyJsNumberToString`:ECMAScript 的 `Number::toString`。对 k = 1..17,取夹住 x 的两个 k 位十进制,
  用整数判断能不能读回 x——x 两边各半个间距,binade 底部下侧是四分之一,边界上只有尾数为偶时读回;
  最短的 k 胜出,同一个 k 两个都读得回时取更近的,平局取偶。排版按规范:1e-7 到 1e21 之间是位置记法,外面是 `1.5e-7`、`1e+21`。
  变长大整数实现。
  **只看更近的那一个是错的**:binade 底部读回区间不对称,更近的候选可能落在窄的下半边读不回,稍远的上侧候选却读得回。
  2^-1015 上游是 `7.120236347223045e-307`,只看更近者会得到 17 位。第一版就这么写,20 万个随机向量没抓到,
  是变异体活下来之后专门拿全部 2 的幂去探才暴露的,一共 46 个。
- `TyJsToFixedStr`:toFixed 的字符串。数字取自上一批的精确 n;负号取自 x < 0,所以 -0.001 保留两位是 "-0.00",-0 是 "0.00";
  1e21 以上交给 ToString。
- `TyJsAddCommas`:照上游正则的效果,只处理第一个 '.' 之前、只处理连续数字,所以 '1e+21'、'NaN' 原样通过。

`getPrecision` 的字符串分支(负数、1e-14 以下)改用 `TyJsNumberToString`。它以前用 Str/Val,60011 个随机 Double 里有 28 个和上游不同。

四个函数和 node 比了 200104 个向量(随机位模式、各种量级、专挑的半数、边界值),ToString 另外比了全部 2 的幂和它们的邻居(6280 个),零差异。

### 刻度标签和模板

- `TyAxisTickLabel`:类目轴取类目文字,数值和 log 轴取 `getLabel`(不带 opt);`axisLabel.formatter` 是字符串时,把**第一个** `{value}` 换成它。
  这和上游 `makeLabelFormatter` 的字符串分支一样,不分轴的类型;时间轴另有自己的一套。`''` 也是字符串,所有标签变空。
- 布局量的和画出来的是同一个字符串:只有 Builder 生成标签规格时调用它。绘制那边原来还有一条"没有 placements 时自己排版"的兜底路径,
  带着自己的一份数字格式。它其实走不到——每根 grid 轴都有规格,placements 和标签一一对应——变异测试里改它什么都不会红。删了,
  Layout 里说"没有 plot rect 时 placements 为空"的那句注释与代码不符,一并改正。
- 分组让标签变宽,四位数以上的轴 gutter 会跟着变。

### axisPointer 标签和表头

- `label.precision` 进了级联:数、`'auto'`、Number() 读得懂的字符串('3'、'' 是 0)、true/false 是 1/0,读不懂的('abc'、对象)印 ToString。
  **没写**就是 `'auto'`——这由 `HasPrecision` 表示,记录的零值就是默认值。
- 级联里的 null 不再认领这个键。上游只在某层的值是 null 或没写时才落到下一层;以前轴上写 `formatter: null` 会挡住 tooltip 那层的 formatter。
- 表头和 pointer 标签是同一个函数(上游的 `getValueLabel`),formatter 和精度都作用在表头上;被 formatter 弄成空白的表头就是没有表头。
- pointer 自己的值:开 snap 时是吸附到的那一行,关了就是光标处。以前线画在光标处、标签却写吸附行的值。
  值先按上游的 `fixValue` 夹进 scale 的范围,线和标签都用夹过的值:写了 max 100 时,一行 150 的数据让 pointer 停在 100。表头不夹,它总是描述吸附行。
- 数值超过约 9.2e18 时,原来的 `RoundTo` 会在绘制里抛 EInvalidOp。现在没有这条路了。

### 基准

`tools/advchart-oracle/axis-labels.js`,四节,数值用 IEEE 位模式传(JSON 读取端会把超过 2^63 的整数字面量读错):

- ticks 37 条:`getViewLabels()` 的 formattedLabel,正负、小数、钉住的端点、1e-7 步长、1e20 到 1e27、log(含底数 2、1e-7..1)、x 数值轴、六种模板。
- getLabel 88 条:在真实 scale 上按各种精度调用。
- pointer 22 条:画出来的 pointer 标签(同一个 option 有没有 pointer 两次渲染,取文字元素的差集)。
- header 11 条:node 下 tooltip 不渲染,oracle 临时改掉 `env.node` 和 `getDom`,从 formatter 参数的 `axisValueLabel` 拿表头,再用 showtip 事件核对值。

比对一共 470 多项,全部相同;把机器的小数点改成逗号、千分位改成句点再跑一遍,也全部相同。表头走真实的悬停路径,不是抄一遍公式。

另有单元测试:`TyJsNumberToString(1e23)` 是 '1e+23'(最接近 1e23 的 Double 比它小,一位数进位成十,是下一位的一,不是两位的 '10');
精度 1e300 和 -1e300 必须先夹再截断,否则 `Trunc` 溢出;NaN 和 Infinity 的标签;类目轴也吃模板。

### 被推翻的旧话

- `TestThePointerLabelRoundsToTheScalesPrecision` 钉的是 '37' 和 '1,234'。上游是 '37.25' 和 '1,234.40'。已改,原处有标注。
- `AdvanceChart.pas` 和 `Tooltip.pas` 的注释说上游刻度标签不分组,和 pointer 标签是两条路。不对:两者都是 `getLabel`,都分组。注释已改。

### 已知偏差

- 函数形式的 formatter(`axisLabel.formatter`、`axisPointer.label.formatter`)不做:option 文本里写不出函数,port 这边要走 `@Name` 事件,参数另设计。
- `axisLabel.customValues` 不做:它决定标在哪些值上,文字照样走这里。
- 系列标签的 `{c}`、tooltip 里系列那几行的值:上游是 `addCommas(ToString(值))`,这里还是 `TyChartNumToStr`/`TyTooltipValueText`。下一小批。
  **[第三十五批已修,见 §69。标签的 `{c}` 其实不分组,只有 tooltip 的默认行分组。]**
- 雷达环上的标签:上游分组,但环上的值要先按上游方式取整(scaleCalcAlign),不然全精度标签会印出浮点噪声。和雷达对齐一起做。
- 值的偏差照样会反映到文字上:log 轴的分数次幂(FPC Power 末位不同)。

### 落地

- `source/tyControls.AdvChart.Scale.pas`:`TyJsNumberToString`、`TyJsToFixedStr`、`TyJsAddCommas`、`TTyLabelPrecision`、`TyScaleValueLabel`;
  `getPrecision` 的字符串分支;`FixedDigits` 由两个 toFixed 共用。
- `source/tyControls.AdvChart.Builder.pas`:`TyAxisTickLabel`,`TTyAxisFurniture.LabelFormatter`。
- `source/tyControls.AdvChart.AxisPointer.pas`:`label.precision`、`TyLabelPrecisionOf`,`Claim` 不认 null。
- `source/tyControls.AdvanceChart.pas`:`AxisValueText`(规格驱动)、`PointerAt`、`PointerValue`,表头,兜底路径。
- `tools/advchart-oracle/axis-labels.js`、`tests/fixtures/advchart-axis-labels.json`、`tests/test.advchart.labeltext.pas`(新)。

### 变异测试

两轮。

**第一轮 47 个,活 7 个:**

- **ToString 的三条边界规则**(下界相等时读回、binade 底收窄、平局取偶)。追查它们时发现上面那个真 bug:只看更近的候选。
  改成两侧都问之后,这三条连同"只问下侧""只问上侧""两个都行时取下侧"在 2 的幂和 20 万向量上各自错几十到几万个,挑代表写成单元断言。
- **精度是个词('abc')时照样取整**:在位置记法范围里,`toFixed(x, getPrecision(x))` 和 ToString 恰好一样;只有指数形式分得开。补了 1e-7 的断言。
- **无穷大的刻度自己算精度**:`getPrecision(Infinity)` 不抛异常,toFixed 又把 Infinity 交给 ToString,那道保护多余,删了。
- **绘制兜底路径的两个**:整条路径走不到,删了(见上)。

**第二轮 46 个**:第一轮被杀的按新代码重跑,加上两侧候选的新变异,全部杀死。全量 **7714** 绿。

### 还在队列里

系列标签与 tooltip 值的文字 → grid 的外边界收缩 → containShape → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign`(雷达与 `alignTicks`)。

## 69. Tier 1 第三十五批:系列自己的文字(2026-09-22)

上一批管轴上的字,这一批管系列上的字:数据标签、tooltip 的默认行、tooltip 的 formatter 模板,以及仪表盘的标题、数值和刻度。

### 上游的规则

- **标签的默认文字和模板里的 `{c}`**:`String(值)`,也就是 ToString,不分组。1e-7 是 `1e-7`,0.1+0.2 是 `0.30000000000000004`。
- **tooltip 默认行的值**:`makeValueReadable`。有限数是 `addCommas(ToString)`;NaN 和 Infinity 是 `-`,从不留空。
- **模板是 `formatTpl`**,标签和 tooltip 共用:
  - 先把每个裸字母的**第一处** `{a}` 改写成 `{a0}`,再按系列逐个替换**第一处** `{a0}`、`{b0}`……
  - 字母只有 a、b、c;d 只在有百分比的系列(pie、funnel)才算字母。
  - 替换用的是 `String.prototype.replace`,替换串里的 `$$`、`$&`、`` $` ``、`$'` 按 JS 规则解释。
  - 其余一律原样留下:第二个 `{c}`、`{e}`、只有一个系列时的 `{c1}`、`{a5}`、没有百分比时的 `{d}`。
  - `{@维度}` 只在**标签**里展开(`getFormattedLabel`),tooltip 模板里原样留下。
  - tooltip 模板会对替换进去的值做 HTML 转义;浏览器默认的 html 模式再解码回来,所以比对用解码后的文字。
- **`formatter: ''` 是空标签**,不是"没写"。`null` 才是没写,会退回默认文字——还会去掉系列类型自带的默认值:graph 的默认 formatter 是 `'{b}'`,写 `null` 以后显示的是值。
- **pie 的 `{d}`**:`getPercentSeats`,最大余数法。`digits = Math.pow(10, precision)`,不钳位,负精度也照算(-1 就是按十个百分点分)。算的是图例过滤后的那些扇区;取值是 `seats[i] || 0`。
- **funnel 的 `{d}`**:`+(值 / 总和 * 100).toFixed(2)`,不走最大余数,三等分就是三个 33.33。总和跳过缺失值;总和为 0 时全是 0;缺失值自己的是 NaN。
- **仪表盘**:数值是 `value + ''`,缺失值显示 `NaN`;刻度值先 `round(x, 14)`,所以 0..1 三等分是 0.33333333333333。
- **K 线**:`label.show` 接受但什么都不画。
- **系列名是数字**时按 `'' + name` 当名字用;名字是空格时,tooltip 表头是 `-`。
- **缺失值**:节点、柱子的 tooltip 行显示 `-`;graph 的边没有值时整格不出。

### port 以前

- 所有这些地方都用 `TyChartNumToStr`(`FormatFloat`,最多六位小数):1e21 印成 `1E21`,1e-7 印成 `0.000000`,0.1+0.2 印成 `0.3`。
- 模板只认 `{a}{b}{c}{d}` 各替换一次:`{a0}` 不认;没有百分比时 `{d}` 变成空;`{a5}` 变成空;tooltip 里也展开 `{@}`;多个值用 `, ` 连。
- `formatter: ''` 当成没写。
- pie 标签:按原始行号取数据,图例关掉一块以后,后面的扇区读的是下一块的名字;`{a}` 是类型名 `pie`;`{c}` 是空;`{d}` 从来没算过——`TyPiePercentSeats` 写好了,没有调用方。
- funnel 标签:formatter 原样画出来,花括号也在。
- tooltip 里的缺失值是空白。仪表盘六位小数。K 线画了数据标签。

### 顺带发现的三个问题

- **堆叠求和把整张图弄没了。** `TyAddSafe` 用 `Round(和 * 10^p) / 10^p` 取整,1.23456789 叠在 1e17 上,乘积超出 Int64,EInvalidOp 一路抛出渲染。
  它还自带一份 getPrecision,探测不出来的部分读 `FloatToStr` 的十五位:0.30000000000000004 的精度算成 1。
  现在精度用轴那边的 `TyGetPrecision`,取整用 `TyJsToFixed`,精度超过 20 时原样返回和(上游 `TO_FIXED_SUPPORTED_PRECISION_MAX`)。
- **`percentPrecision: 1e19` 让渲染失败。** 敌意选项测试抓到的:精度钳到 MaxInt,`Math.pow` 是 Infinity,空扇区投票 0 × Infinity,FPC 抛异常。
  上游算出 NaN,再被 `|| 0` 变成 0。现在在屏蔽浮点异常的外壳里照算,NaN 取 0。
  另外,上游这个循环在精度大约 14 以上会死循环:和过了 2^53 以后加 1 不变,`while (currentSum < targetSeats)` 永远成立。
  精度取 14 到 300 之间的 11 个值,每个随机 3000 组数据,卡住的有 53 到 1521 组。port 在这里停下,用已经分好的席位。
- **graph 的 `formatter: null`**:以前 graph 的默认文字硬写成名字,`null` 改不回来。现在默认 formatter 是模板 `'{b}'`,`null` 去掉它,显示值。

### 基准

`tools/advchart-oracle/series-text.js`,跑真实的 ECharts 6.1,读 zrender 拿到的文字,不信任 API 自称的结果:

- 标签:每个数据项的图形元素及其子元素上的每个 label(`getTextContent`);没有元素就是没画。
- tooltip:真的 TooltipView,richText 模式,node 下临时改 `env.node` 和 `getDom`;逐行解析出 marker、名字、值。
  样式名的编号取自 `Math.random`,加载库之前换成常数,fixture 才能复现。
- 仪表盘:`_titleEls`、`_detailEls`,以及刻度的静默 Text。

标签 44 个用例(209 项,175 项有字),tooltip 53 个,仪表盘 14 个,逐字比较;把小数点改成逗号再跑一遍。全部相同。

另有 34 个用例标成 deferred,上游答案一并记着,以后只需去掉标记:原始值通道、数组的 `{c}`、tooltip 子行、encode、未命名系列的自动名,还有下面说的柱子几何。
**[第四十九批:原始值通道和数组的 `{c}` 已做,那 20 条已解除 deferred,见 §83。]**

### 被推翻的旧断言

- `test.advchart.handlers.pas`:
  - `{d}` 没有百分比时是空:改为原样 `{d}`。
  - 多值 `{c}` 是 `10, 20.5`:改为 `10,20.5`。
  - `{a5}` 是空:改为原样。
  - tooltip 模板展开 `{@price}`、`{@[2]}`:改为原样。
  - 原处都有标注。
- `test.advchart.tooltip.pas`:`TyTooltipValueText(NaN)` 是 `''`,改为 `-`。

### 已知偏差

- **原始值通道**:**[第四十九批已做,见 §83。]** store 只存解析后的 Double。原始字符串(`'12.50'`)、布尔、`null` 和 `undefined` 的文字、数组和 dataset 行的 `{c}`、objectRows,都要能回头查原始 JSON。
  `{@维度}` 对标量数据项的回退也在这里:上游一个标量项对任何维度名、任何 `[n]` 都答它自己的值,这要知道原始项是不是数组。
- **tooltip 子行**:K 线的 open/close/lowest/highest、雷达每个指标一行、`displayName`、`encode.tooltip`。
  **[第五十批已做,见 §84。]**
- 雷达的数据标签没有实现;雷达环上的标签还是 `TyChartNumToStr`,要和 scaleCalcAlign 一起做。
  **[第四十八批:环上的标签改成刻度标签(千分位),见 §82。]**
- `encode.label` 和 defaultedLabel 维度规则(类目-类目、时间-类目的散点没有默认标签)。
  **[第五十批已做,见 §84。]**
- 未命名系列的自动名 `series\0N`:要先决定怎么画一个 NUL。
  **[第五十批:文字里保留 NUL,度量和绘制时去掉,和浏览器一样什么也不画,见 §84。]**
- 仪表盘 `splitNumber: 0`:上游印 NaN,port 有意画最小值(gauge 测试钉着)。
- **柱子几何,下一批**:fixture 里的堆叠用例暴露了两个问题。
  - 柱子从坐标轴的 min 画起,不是从 0(上游 `getValueAxisStart`)。数据全为正时两者重合,有负值就画错。
  - 长度为 0 的柱子整个被丢掉,标签也一起没了;上游画一个扁的矩形,标签照常。1/3 叠在 1e17 上就是这样。
  **[第三十六批已修,见 §70;那条用例已去掉 deferred。]**
- 函数形式的 formatter、`valueFormatter`、`@Name` 事件用在标签上。

### 落地

- `source/tyControls.AdvChart.Handlers.pas`:`TyJsReplaceFirst`、`TyJsFormatTpl`、`TyChartValueText`,`TyChartFormatTemplate` 改用 formatTpl。
- `source/tyControls.AdvChart.LabelOpt.pas`、`Labels.pas`:`HasFormatter`,`TyLabelText` 用 formatTpl。
- `source/tyControls.AdvChart.Pie.pas`、`PieLabel.pas`:精确的 `TyPiePercentSeats`、`TyPieSectorPercents`;标签用视图行号、系列名、值列和百分比。
- `source/tyControls.AdvChart.Funnel.pas`:`TyFunnelPercents`,标签走 `TyLabelText`。
- `source/tyControls.AdvChart.Tooltip.pas`、`Gauge.pas`、`Stack.pas`、`Marks.pas`、`Data.pas`、`Builder.pas`、`Graph.pas`。
- `source/tyControls.AdvanceChart.pas`:pie/funnel 的 `{d}` 参数、数字系列名、空白表头、边的缺值、graph 的默认 formatter。
- `tools/advchart-oracle/series-text.js`、`tests/fixtures/advchart-series-text.json`、`tests/test.advchart.seriestext.pas`(新)。

### 变异测试

51 个,第一轮活 9 个,另有 1 个是没编译过的假杀(删掉 `else if` 分支后前一个 `end` 缺分号),改写法重跑。

- **fixture 没覆盖到的输入**,补成 oracle 用例:K 线带 formatter(不带时默认文字本来就空,放回标题也画不出字);
  关掉中间一块的饼图 tooltip 模板(视图行号和原始行号相同时分不出来);数据里收集的数值类目;数字形式的数据项名字。
- **fixture 只比文字**,补单元断言:`formatter: ''` 的饼图标签引导线还在;漏斗总和为 0 时占比是 0;
  `` $` `` 以及其余几种 `$` 写法逐个按 node 的答案检查;零个系列时 formatTpl 返回空串(绘制路径走不到,函数是导出的)。
- **等价的一个**:没有值的 graph 边不出值格子,我专门加了一行判断。其实 `TooltipParams` 只在边有值时才给它值,那一行多余,删了,留一句注释说明原因。

补完后 9 个全部杀死。全量 **7721** 绿。

### 还在队列里

柱子的基线和零长度柱子 → grid 的外边界收缩 → containShape → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign`(雷达与 `alignTicks`)→ 原始值通道 → tooltip 子行。

## 70. Tier 1 第三十六批:柱子站在哪里(2026-09-22)

上一批的 fixture 里,一根 1/3 叠在 1e17 上的柱子连标签一起不见了。顺着查下去是两个老问题:柱子从坐标轴的 min 画起,长度为 0 的柱子被丢掉。
这一批把柱子沿数值轴方向的几何对齐上游。

### 上游的规则

- **起点是 startValue**(`getValueAxisStart`):写了 `startValue` 就用它;没写时 log 轴是 1,其他是 0。不是轴的 min。
  - 只有柱状图(含 pictorialBar)的数值轴要起点;基轴不要。
  - 起点什么时候并进轴的范围,第 33 批已经按 scaleRawExtentInfo 做了。`scale: true` 又没写 startValue 时它不进范围,但仍然是柱子的起点,于是柱子从画布外开始、被 clip 裁到边上。
  - 起点按原样保存,不跟范围一起清理:log 轴写 `startValue: 0`,起点落不到像素上,一根柱子也不画。
- **堆叠**:最底层没有 stackedOn 系列,和不堆叠的柱子一样站在起点上;上面各层从 `累计 - 自己` 画到 `累计`。下面没有同号层的,站在 0 上,不是起点(上游自己在注释里承认这里有问题)。
- **barMinHeight** 从每根柱子自己的底量起,所以不会沿着堆叠往上传,两段短柱会重叠。竖柱长度 ≤ 0 时向上,横柱 < 0 时向左。
- **长度为 0 的柱子照画**:一个扁矩形,不出颜色,标签照挂。clip 只在矩形被裁到"反过来"(整个在图外)时才隐藏它;正好贴边的不隐藏。
- **`label.position: 'outside'`** 不是一个位置,是按柱子方向求的:竖柱向下长的放下方、否则上方;横柱向左长的放左边、否则右边。
  判断用的是裁剪后的矩形;长度为 0(包括被裁成 0)时看数值轴是否 inverse。只有 `outside` 会翻,写死的 `top` 不翻。

### port 以前

- `DataToLayout` 和 `BuildBars` 都拿 `Scale.GetExtent.Start` 当柱子的底。有负值时 -3 那根从图底往上长,5 那根高出一倍多;全负的数据柱子倒过来,最小值那根长度为 0 被丢掉。
- `startValue` 在第 33 批的原始范围第 (7) 步里算出来、并进了范围,然后就扔了:`TTyScale.StartValue` 这个属性早就有,没有任何生产代码写它。它的注释还说它"从不改变范围",和第 33 批的实现矛盾。
- 堆叠最底层的注释专门论证它要站在"轴自己的基线"上;对应的测试只因为 clip 默认开、把两种答案都裁到了图边,才一直是绿的。
- 长度 ≤ 0 的柱子连同标签被丢弃。数值为 0、等于钉住的 min、`scale: true` 的最小值,都没有标签。
- barMinHeight 对堆叠的上层也从轴量起:叠在 5 上的 0.001 已经"够长",画成 0.04 像素的一条缝。
- `outside` 在解析时就变成了 `top`。
- log 轴上"下面没有同号层"的上层柱:底是 0,映射成 NaN,`Min(NaN, …)` 在 FPC 的默认陷阱下把整张图的渲染抛掉。

### 做法

- 原始范围记录加了 `HasStartValue`/`StartValue`(零值是"没有",因为 log 轴的默认是 1 而不是 0),构建时写进 `Scale.StartValue`,每次构建都写,没有就写 NaN。
- `TyValueAxisStart(axis)`:有 startValue 用它,否则 log 轴 1、其他 0。`DataToLayout`、`BuildBars`、`BuildPictorialBar` 三处都用它;起点落不到像素上就没有格子。
- `BuildBars` 求每根柱子的底(起点,或下一层的顶)和带符号的长度,barMinHeight 和 outside 的方向都用它。
  outside 用的是加最小高度之前的长度:最小高度只会把 0 撑成向上(竖)或向右(横),而长度为 0 本来就是这个答案。
- 沿数值轴只在"反过来"时丢弃;沿基轴仍然是宽度 ≤ 0 就丢(上游有 `barMinWidth || 1`,零宽柱子造不出来)。
- 元素标题加了 `Outside`(`TTyCaptionOutside`,零值 `coNone` 表示没有自己的外侧,即上方);标签规格加了 `Outside` 标记,标签排版对 `outside` 按元素求位置。
- `grid.outerBoundsMode: 'none'` 现在会读:grid 的矩形就是绘图区。别的模式照旧,留给外边界那一批。

### 基准

`tools/advchart-oracle/bar-geometry.js`,73 个用例(另有 5 个 deferred),每个数据项记录:drawn / hidden(整个被裁掉)/ none(缺值或起点落不到像素上)、裁剪后画出来的矩形、标签画没画、锚点和对齐方式。
用例覆盖起点(正负、全负、`scale: true`、各种 startValue、log、inverse)、堆叠(混号、NaN、带 startValue、log)、barMinHeight(横竖、inverse、堆叠、被裁回 0)、clip(min、max、远端、多出的数据)、outside 和 pictorial 的底。

所有用例都写 `grid: { outerBoundsMode: 'none' }`:两边默认 grid 的收缩规则不同(下一批),先把绘图区钉成一样,只比柱子。

243 个画出的柱子(其中 42 个长度为 0)、9 个隐藏、11 个不画,239 个标签,共 1150 项比较,每个用例渲染两遍(第二遍之前 Invalidate)。
坐标按 ulp 比:线性轴上最多差 1 ulp,log 轴上最多 4 ulp。像素是同一个值走不同的算式得到的(上游 `(v - d0) / span * range + r0`,这里 `r0 + n * range`),
log 轴的对数还来自不同的库。数值本身第 33 批已经逐位对齐。

第 35 批那条"太短看不见的柱子也保留标签"的用例去掉了 deferred,现在也相同。

### 被推翻的旧话

- `TestTheBottomOfAStackKeepsTheAxisOwnBaseline` 钉的是"最底层站在轴的 min 上"。改名为 `TestTheBottomOfAStackStandsOnTheStartValue`,关掉 clip,期望站在 0 上、写了 startValue 时站在它上面。原处有标注。
- `Scale.pas` 里 `StartValue` 的注释("只是视口提示,从不改变范围")、`Marks.pas` 里堆叠最底层和 barMinHeight 的注释,都已改正并标注。

### 已知偏差

- **数值型基轴上的柱子**:上游按数据的最小间隔求柱宽,并把基轴范围放宽半个柱宽(containShape);port 还没有。起点这部分已经一致,那条用例标 deferred。
  **[第四十一批已做,见 §75;那条用例已解除 deferred,盒子与上游一致。]**
- **边框内缩**(`itemStyle.borderWidth` 让矩形向里缩半个线宽)、**缺值行的背景条**、`barMinWidth: 0`:各自 deferred,上游答案已记在 fixture 里。
- **长度为 0 的柱子的悬停**:上游竖直的零高柱子本身悬停不到(有边框或 inside 标签时才能),port 的矩形在那条线上能命中。标签照样代表这个数据。fixture 没有收悬停。
- pictorialBar 的 `outside`:上游用自己的规则(`boundingLength` 的符号),port 仍然放上方。

### 落地

- `source/tyControls.AdvChart.Series.pas`:`TTyAxisRawExtent.HasStartValue/StartValue`,写 `Scale.StartValue`。
- `source/tyControls.AdvChart.Coord.pas`:`TyValueAxisStart`,`DataToLayout` 用它。
- `source/tyControls.AdvChart.Marks.pas`:`BarLength`、`BarOutside`,`ApplyMinHeight` 以底为锚,零长度柱子保留,log 堆叠守卫,pictorial 的起点。
- `source/tyControls.AdvChart.Paint.pas`:`TTyCaptionOutside`、`TTyElementCaption.Outside`。
- `source/tyControls.AdvChart.Labels.pas`、`LabelOpt.pas`:`TTyLabelSpec.Outside`,标签排版按元素求 outside。
- `source/tyControls.AdvChart.Builder.pas`:`outerBoundsMode: 'none'`。
- `source/tyControls.AdvChart.Scale.pas`:注释。
- `tools/advchart-oracle/bar-geometry.js`、`tests/fixtures/advchart-bar-geometry.json`、`tests/test.advchart.bargeometry.pas`(新);
  `test.advchart.marks.pas`、`test.advchart.labels.pas`、`test.advchart.coord.pas` 补测试。

### 变异测试

33 个,第一轮活 5 个:

- **等价的两个**:
  - 没写 startValue 时存不存默认值:存下来的(log 1、否则 0)和 `TyValueAxisStart` 的回退值一样。默认值算了两处,一处给范围、一处给手工搭的坐标系,答案相同。
  - `BarLength` 里"够长就不改"的判断:barMinHeight 不改变长度的符号,所以对 outside 没有影响。顺着这个把 `BuildBars` 简化了:
    outside 直接用原始长度,`BarLength` 并回 `ApplyMinHeight`。"方向在最小高度之前决定"那个变异体随之消失。
- **补 oracle 用例的三个**:横向堆叠的上层柱在 `startValue: 20` 下的 outside(底和起点方向不同才分得开)、横向堆叠的 barMinHeight、
  横向 barMinHeight 撑开的 0 的 outside(简化后 `>= 0` 在这里才起作用)。

重新锚定的两个"零长度朝向"变异体和上面三个全部杀死。另外试了一个"按画出来的矩形中点定方向"的写法,和原写法等价,活下来是预期的。
全量 **7727** 绿。

另:第 35 批写进本文档的 `series\0N` 经 heredoc 变成了一个 NUL 字节,`grep` 把整个文件当成二进制。已改回字面的反斜杠 0。

### 还在队列里

grid 的外边界收缩 → containShape(数值型基轴上的柱子)→ roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign`(雷达与 `alignTicks`)→ 原始值通道 → tooltip 子行。

## 71. Tier 1 第三十七批:grid 的外边界(2026-09-22)

上游 v6 的默认是 `outerBoundsMode: 'auto'`:grid 按写的矩形放,标签只要没越出画布就不收缩。port 一直把 grid 的矩形当外边界,在里面给每根轴的标签、刻度、间隔、名称预留地方,相当于 `containLabel: true`,绘图区普遍比上游小三十像素左右。这一批按上游的 `layOutGridByOuterBounds` 重写。

### 上游的做法

- **模式**:`containLabel` 为真时走旧版规则,`outerBounds*` 全部忽略。否则看 `outerBoundsMode`:
  - 没写、null、`'auto'`:外边界是 `outerBounds` 在画布上解出来的矩形,默认 `{left: 0, right: 0, top: 0, bottom: 0}`,即整个画布。
  - `'same'`:外边界就是 grid 自己的矩形。
  - `'none'` 和任何不认识的值:不收缩。
- **估算**:在 grid 原始矩形上把标签照画的样子排一遍:锚点在绘图区边缘加 offset 加 `axisLabel.margin`,**不算刻度**;按 `rotate` 转;文字框沿行方向两端各加 `textMargin` 的 3(默认 `[0, 3]`);只算稀疏后显示的那些。
- **溢出**:每个标签框相对外边界的溢出量。沿自己那根轴的方向,溢出量除以标签在轴上的比例 p(`scale.normalize(tick)`,不做 band 调整,也不按 inverse 翻转;y 轴取 1 − p),只在溢出量为正、p 大于 1e-4 时才除;垂直方向原样计入。grid 矩形本身也算一项。**每边取最大,不是求和。**
- **收缩**:`expandOrShrinkRect`。负的边距当 0;每个方向最小不小于钳位值(`outerBoundsClampWidth/Height`,默认原始矩形的 25%)。碰到钳位时,只有一侧要收的那一侧不动,另一侧的位置有一条特别的规则:只从左边收时矩形会移到原来的右端(上游代码如此,照搬)。
- **不迭代**:估算一次、收缩一次、在最终矩形上定一次标签。收缩后标签可能又越出画布,上游也不管。
- **旧版 `containLabel`**:每根轴取所有标签(超过 40 个时抽样)未旋转尺寸按 |cos|、|sin| 转过后的最大宽高,加 margin,从那一侧扣掉;同侧多根轴累加;不管 offset、名称和 `axis.show`,内侧标签不算,也没有 textMargin。
- **node 里怎么量字**:zrender 没有 canvas 时查一张表,可打印 ASCII 每个字符是字号的固定比例(数字 0.56、逗号 0.28……),其他字符算一个字号,行高等于字号。字体、粗细都不看。

### port 以前

- `TySolveGrid` 在 grid 矩形里给每根轴留"offset + 刻度 + margin + 最宽标签 (+ 名称)",同侧求和;一个标签也没越出画布,绘图区照样缩。
- 标签离轴线的距离多算了一个刻度长度(5 像素);有 offset 的轴线移出去了,标签却还贴在绘图区边上。
- 没有 textMargin,没有钳位(太长的标签把绘图区压到宽度 0),`'same'`、`outerBounds`、`outerBoundsContain`、钳位选项、`containLabel` 都不读。
- **类目标签站错了地方**:`NormalizedCoord` 给的是相对"扣掉半个 band 的范围"的比例,标签布局却乘以整个绘图区宽度。七个类目时第一个标签在绘图区左边缘,不在第一根柱子下面,最后一个在右边缘,只有中间那个对齐。有一个测试专门钉着这个错法(按内缩范围换算回像素)。

### 做法

- `tyControls.AdvChart.Layout`:
  - `TTyXYWH`、`TTyBoundsItem`、`TTyMargin4`;
  - `TyAxisLabelBoundsItems`(估算标签框)、`TyOuterBoundsMargin`(溢出)、`TyShrinkRect`(收缩)、`TySolveGridBounds`(三步合一)、`TyLegacyContainLabel`;
  - 收缩用 x/y/宽/高做,和上游的运算顺序一致,可以逐位相同;
  - 删掉 `TySolveGrid`;标签定位改为"margin + offset",不含刻度。
- 规格记录加 `Proportions`、`TextMarginV/HLogical`、`LegacyLabels`(隐藏的轴旧版规则照样量它的标签)。
- Builder 读 `containLabel`、`outerBoundsMode`、`outerBounds`(按上游"每个方向最多保留两个键"合并)、`outerBoundsContain`、`outerBoundsClampWidth/Height`、`axisLabel.textMargin`;构建记录保存画布矩形。
- `NormalizedCoord` 改为相对整个像素范围。
- 坐标轴名称(`'all'` 时):暂时按 port 画出来的位置计入,比例取 0.5。上游名称默认在轴的末端、有自己的 gap 和层级规则,那是单独一批;这里先保证名称仍然占地方。
  **[第三十八批已改,见 §72:名称按上游的布局计入,末端名称的比例是 NaN,只有居中名称取 0.5。]**

### 基准

`tools/advchart-oracle/grid-bounds.js`,三层:

1. **测宽**:zrender 那张表的 95 个比例从 dist 解码、以位模式写进 fixture;60 条字符串 × 字号的宽高,port 的 `TZrSsrMeasurer` 必须逐位相同。
2. **收缩**:把上游自己的估算标签框和比例喂给 `TyOuterBoundsMargin` + `TyShrinkRect`,边距和最终矩形逐位相同(60 条)。
3. **整条流水线**:读选项、格式化、稀疏、定位、旋转、加 textMargin、收缩,最终矩形在每条用例自己的容差内(约 4.5e-13;标签框经过 zrender 的变换矩阵,1.72 会变成 1.720000000000013)。64 条。
   **[第五十一批:现在逐位。原因有二,都不是"矩阵舍入不同"那么笼统:标签矩阵要按 zrender 分解再重组;测试把 `Right - Left` 当宽度,118.16 + 421.84 − 118.16 = 421.84000000000003。见 §85。]**

另有 23 条 deferred:坐标轴名称(5,**第三十八批已解除,见 §72**)、hideOverlap、类目自动间隔、fontSize、truncate/break、grid 盒子合并(10)、值轴稀疏(2)、containShape(1,**第四十一批已解除,见 §75**)。

生成器自带两道自检:转写的收缩在 60 条上复现上游矩形,转写的旧版规则在 15 条上复现。

### 被推翻的旧测试

- `test.advchart.axis.pas`:`TySolveGrid` 的五个测试改写为新语义(不越界不收、只收越出的那一侧、同侧取最大、沿轴除以比例、钳位);三处标签定位 87→92、163→158(不再加刻度),另加 offset 的断言。
- `test.advchart.furniture.pas`:刻度三个测试合并为"刻度从不移动绘图区";标签内外、margin、旋转、隐藏轴四个测试改为 grid 贴画布边(`left: 0` / `bottom: 0`),在标签真正越界时比较。
- `test.advchart.multiaxis.pas` 的 offset、`test.advchart.builder.pas` 的像素范围:同样改为贴边,另加"默认 grid 不收缩"。
- `test.advchart.scale.ordinal.pas`:`NormalizedCoord` 的比例按整个范围换算。
- 原处都有标注。

### 已知偏差

- **坐标轴名称**的完整布局(nameLocation、nameGap、nameRotate、margin 层级、nameMoveOverlap):单独一批。现在名称还画在居中位置。
  **[第三十八批已做,见 §72。]**
- **稀疏**:上游值轴从不按序号稀疏标签,port 会;类目自动间隔、`fixMinMaxLabelShow`、`hideOverlap` 与上游不同。估算用的标签集因此可能不一样。单独一批。
  **[第三十九批已做,见 §73。]**
- **containShape**:柱子让无 band 的类目范围加宽半个 band,影响比例 p。
  **[第四十一批已做,见 §75。]**
- **grid 盒子本身**:`left: 'right'`、`top: 'bottom'`、居中无尺寸、键的合并规则(D12),和 title/legend 共用 `TySolveBox`,单独一批。
- `axisLabel.fontSize`(字体由主题决定)、`minMargin`、`width` + `overflow` 的估算:未做。

### 落地

- `source/tyControls.AdvChart.Layout.pas`、`Builder.pas`、`Coord.pas`。
- `tools/advchart-oracle/grid-bounds.js`、`tests/fixtures/advchart-grid-bounds.json`、`tests/test.advchart.gridbounds.pas`(新)。
- 上面列出的测试。

### 变异测试

40 个,第一轮活 11 个:

- **等价的两个**:
  - 收缩模式下近侧边距为 0 时"加上负的近侧边距"那一支:加的就是 0。
  - `outerBounds` 只写一个键时保留哪个默认值:无论保留哪个,解出来的矩形一样。那段合并代码因此简化为"写了两个键时去掉默认值"。
- **oracle 够不到、补单元测试的九个**:
  - 比例为 0 或小于 1e-4 时不做除法;
  - y 方向近侧用 1 − p;
  - 负边距不会撑大矩形;
  - 钳位值大于原尺寸时取原尺寸;
  - y 轴项的比例从顶部量;
  - 被稀疏掉的标签不计入;
  - 名称沿轴越界时按 0.5 放大;
  - 旧版规则跳过内侧标签;
  - `'axisLabel'` 时不计名称(builder 测试)。
  这些能区分的上游用例大都因为稀疏或名称被延后了,所以直接对纯函数断言。
- 简化后补的"写了两个键时去掉默认值"变异体,用 `outerBounds: { right: 10, width: 300 }` 的 builder 测试杀死。

补完后除等价的一个外全部杀死。全量 **7735** 绿。

### 还在队列里

坐标轴名称的布局 → 标签稀疏(值轴不稀疏、类目自动间隔、fixMinMaxLabelShow、hideOverlap)→ containShape → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。

## 72. Tier 1 第三十八批:坐标轴名称(2026-09-22)

port 一直把名称居中画在标签外侧,y 轴的转 90°,位置由画的时候临时算。上游默认把名称放在轴的**末端**、水平书写,再把它从标签上挪开。这一批按上游 `AxisBuilder` 的 axisName 部分重写:布局给出名称的位置、对齐、旋转和框,grid 收缩和绘制都读这一份结果。

### 上游的做法

- **读选项**:
  - `name` 按 JS 真值判断有没有名称:`0`、`false`、`''`、`null` 都算没有;`true` 是 `'true'`,`1.5` 是 `'1.5'`,`' '` 算有。
  - `nameLocation`:默认 `'end'`;`'center'` 等于 `'middle'`。
  - `nameGap` 是 `get('nameGap') || 0`:没写取主题的 15,`null` 和 `false` 是 0,负数照用。
  - `nameRotate`:度数乘 π/180;没写时居中名称随轴转,两端名称保持水平。
  - `nameTextStyle.align` / `verticalAlign` 覆盖布局算出的对齐;`textMargin`(数或 css 数组)和 `minMargin` 取代层级边距,两者都写时 `minMargin` 优先。
  - `nameMoveOverlap`:`null` 和 `'auto'` 取 grid 的默认——旧版 `containLabel` 为真时不挪,否则挪;其他值按 JS 真值。
- **坐标系**:轴线位置(x 轴在绘图区上/下边加减 offset,y 轴在左/右边;有 onZero 时换成对方的零线)、旋转(x 轴 0,y 轴 π/2)、范围 `[0, len]`(inverse 时反过来)、`labelOffset`(onZero 时标签仍在原边,离轴线的距离)、`nameDirection`(上/左为 −1)。
- **锚点**,在轴自己的坐标系里,`s` 为 inverse 时的 −1:
  - start:`(ext0 − s·gap, 0)`,往 `−s` 方向挪;
  - end:`(ext1 + s·gap, 0)`,往 `s` 方向挪;
  - middle:`((ext0 + ext1)/2, labelOffset + nameDirection·gap)`,往 `nameDirection` 方向挪。
  - 挪动方向再按轴的旋转转过去。
- **对齐和旋转**:两端名称用 `endTextLayout`(传入 `nameRotate || 0`),居中名称用 `innerTextLayout`;"接近"指差值在 1e-4 以内,`remRadian` 用 JS 的 `%`,是精确取余。
- **矩阵**:轴的组变换 G 乘上文字自己的变换 L(文字在组原点且不转时直接用 G)。画在 (M4, M5),旋转 −atan2(M1, M0)。
- **框**:文字框按对齐放好,再加边距得到 `localRect`,经矩阵得到屏幕上的 `rect`。
  - 层级按**这一遍**的 grid 矩形和画布比:x 轴高度不超过画布一半为 0,否则 1;y 轴宽度不超过一半为 0,否则 2。
  - 居中名称的边距表 `[1,2,1,2] [5,3,5,3] [8,3,8,3]`,两端名称 `[0,1,0,1] [0,3,0,3] [0,3,0,3]`(上右下左)。
  - `minMargin` 不加本地边距,而是把屏幕上的 `rect` 每边扩 `minMargin/2`。
- **挪开**:
  - 居中名称只躲一块:所有显示的标签在轴坐标系里的并集(按标签原本的顺序求并,不是排序后的顺序),再拉到轴线。平行的其他轴不管。
  - 两端名称先躲自己的标签,再躲每根垂直轴的标签;标签按离轴原点的距离排序,和挪动方向同向时从近到远,反向时从远到近。
  - 碰撞用 zrender 的 `BoundingRect.intersect`:两框各缩 0.05,重叠时取挪动方向上最短的平移(只许朝一个方向)。结果是名称的近边落在障碍物远边往里 0.1 的地方。
  - 两个框里有一个不和坐标轴平行、并且外接框确实相交时,上游改用有向包围盒判断——**这条没做**,名称不挪。
- **两遍**:
  - **估算**:只在 auto/same 模式且 `outerBoundsContain` 为 `'all'` 时做,在原始矩形上排,名称框作为一项参与收缩;居中名称的比例是 0.5,两端名称是 NaN(溢出多少算多少)。
  - **确定**:在最终矩形上重排一遍,用它自己的层级和零线位置。画出来的是这一遍。

### port 以前

- 名称总居中在标签外侧,y 轴的转 90°;不读 `nameLocation`、`nameGap`、`nameRotate`、`nameTextStyle`、`nameMoveOverlap`;不管 inverse。
- 没有层级边距,没有挪开;比例一律 0.5。
- offset 在布局里算了两次;有 onZero 时绘制和布局差一个 offset。
- 布局用标签字体测名称,绘制用名称字体。
- `name: 0` 画成 `0`,`false` 画成 `False`,`1.5` 画成科学计数法。

### 做法

- 新单元 `tyControls.AdvChart.AxisName`:
  - `TyLayoutAxisName`:一个名称、一遍布局。输入是规格、坐标系、层级、自己的标签和垂直轴的标签几何。它是纯函数,测试可以直接喂上游的标签几何。
  - `TyLayoutGridNames`:一个 grid 的所有名称。先把每根轴的标签排好,再排名称。
  - 另有 `TyRectIntersectDir`(zrender 的相交)、`TySortLabelGeoms`、`TyAxisNameLevel`、`TyRemRadian`。
- `tyControls.AdvChart.Layout`:
  - zrender 的矩阵运算:`TyMatLocal`、`TyMatMul`、`TyMatInvert`、`TyRectApplyMat`、`TyRectUnion`、`TyRectExpand`。
  - 标签几何 `TyAxisLabelGeoms`,估算标签项也改由它生成。
  - 规格加上名称的输入、坐标系和最终摆放 `NamePlacement`;`TySolveGridBounds` 先排完所有标签再排名称,并多一个画布参数(层级要用)。
- Builder:
  - 读上面那些选项。
  - `NameFrameFor` 按当前矩形和零线给出坐标系,在收缩前(原始矩形)和写入最终矩形后各算一次。确定那一遍的结果存进规格。
  - 名称字体从主题的 `TyAdvChartAxisName` 解出来交给布局。
- 绘制只读 `NamePlacement`:水平的走普通文字路径(能画多行),转过的走 `DrawTextRotated`。
- **新单元 `tyControls.AdvChart.JsMath`**:V8 的 `Math.sin/cos/atan/atan2` 是 fdlibm,FPC 的不是。
  - FPC 的 `Sin(2)`、`Cos(7π/4)` 和 V8 差最后一位。
  - FPC 的 `ArcTan2(-6.1e-17, -1)` 给出 +π,V8 给出 −π。y 轴名称的挪动方向正好是这个数。
  - 于是逐条转写 fdlibm。先用 JS 转写一遍,和 node 比 240 万个参数全部一致,再照同样的运算顺序写成 Pascal。
  - 常数按位写,因为 FPC 读十进制浮点字面量不保证正确舍入。
  - 超过 2^19·π/2(约 82 万弧度)的参数交给运行库,图表转不到那么远。
  - 矩阵旋转和名称布局全部改用它。

### 基准

- `tools/advchart-oracle/axis-names.js`:
  - 65 条用例,54 条比较,11 条延后。
  - 每条记录每根轴每一遍的坐标系、层级、按上游顺序的标签几何(含原始顺序)、名称的对齐、框、矩阵、挪动前后的框、每次平移、最终位置。
  - 估算那一遍直接在真实运行里挂钩 `AxisBuilder.build` 取得。
  - 生成器自检:它自己的转写在 198 次名称排布、72 次平移、62 个 stOccupiedRect 上与上游逐位一致;收缩自检 52/52。
- 测试 `test.advchart.axisnames`,三层:
  1. 测宽逐位一致,四分之一圈的三角函数值与 V8 逐位一致。
  2. 纯函数:上游的坐标系、层级、标签几何喂给 `TyLayoutAxisName`,198 次名称排布的对齐、局部旋转、`localRect`、锚点、矩阵、挪动前后的框、stOccupiedRect、每次平移和最终旋转**逐位**一致。
  3. 整条流水线:名称位置和框、grid 最终矩形,都在各用例的容差内。
- 另有三条单元测试补夹具够不到的地方:斜名称碰到标签时不挪;名称用自己的字体测量;Builder 对各种选项形态的读取。
- `tools/advchart-oracle/js-math.js` → `test.advchart.jsmath`:
  - 3182 个参数的 sin/cos/atan、3225 对 atan2,逐位一致;NaN 对 NaN。
  - 另有一条钉住"运行库确实不一致",哪天 FPC 追上了会变红提醒。
- grid-bounds 的 I、I2、I3、Z4、Z6 解除延后,收缩测试只在 `'all'` 时计入名称。

### 被推翻的旧测试

- `test.advchart.axis.pas` 的"名称在 `'all'` 下计入":以前按居中临时规则断言 90.5 和 100/200。
  - 改成上游规则下手算的值:居中名称被标签推开后外缘 93.9;40 个字符沿轴溢出 53,除以 0.5 得 106/194。
  - 另加末端名称:顶部 35,左边仍由标签决定为 58。
- `test.advancechart.pas` 的名称绘制测试:以前数"绘图区下方的红色像素"。末端名称在轴线右侧,一半在绘图区下方,那种数法不再说明问题。
  - 改为:每一个红色像素都落在布局给的名称框里(留 1 像素抗锯齿),居中名称也一样。
- `test.advchart.gridbounds.pas` 的收缩测试:只有 `'all'` 时才计入名称。以前不分,I2 解除延后就会红。
- 原处都有标注。

### 已知偏差

- **有向包围盒**:名称或障碍物不和坐标轴平行、外接框又相交时,上游用有向包围盒算平移,port 不挪。只有 `nameRotate` 不是 90° 的倍数、或者两端名称碰上转过的标签时才会出现。
- **`nameTruncate`**:没有和 zrender 一致的截断,等标签截断一起做。
- **`nameTextStyle` 的字号、颜色、padding、lineHeight 等**:字体和颜色来自主题,和 `axisLabel` 的做法一致。
- **不认识的 `nameLocation`**:上游用居中的锚点配两端的排布,port 当成 `'end'`。
- **颜色**:上游名称和轴线、标签同色;port 用主题的 `TyAdvChartAxisName`,这是主题的决定。
- 主题没给名称文字色时,绘制不画,但布局照样给它留地方(以前就是这样)。
- 转过的多行名称:`DrawTextRotated` 只画一行。
- `TyAxisThickness` 已没有产品代码调用,只剩测试用它量标签带;它里面的名称项是旧的临时规则。
- 名称 tooltip、`triggerEvent`、极坐标/平行/单轴的名称、grid 不以画布为容器的布局:未做。

### 变异测试

89 个,第一轮活 16 个:

- **等价的一个**:`atan2` 里"|y/x| 小于 2^-60 时 z 取 0"那一支。去掉后 z 是一个不到 2^-60 的数,π − (z − pi_lo) 照样舍入回 π。
- **夹具和流水线够不到、补单元测试的十五个**:
  - 文字排布:"接近"的 1e-4 阈值、转 180° 的居中名称、斜转的居中名称的对齐、居中名称读不读 `nameRotate`。夹具里的居中名称只有水平和四分之一圈两种,斜的都走有向包围盒,被延后了。
  - 层级在正好一半时取小的那档(`<=`)。
  - stOccupiedRect 按标签排布的原始顺序求并:三个标签框按原序并出 27.049999999999997,按排序后的顺序并出 27.05。
  - 逆着轴挪时从远到近检查标签:构造两个标签,从近到远会推两次,从远到近只推一次。
  - 斜方向上取最短的允许平移(名称只沿轴挪,这条只能直接测相交函数)。
  - 标签排序:沿轴、按离原点的距离、同距离保持原序。
  - 零线上的轴:居中名称跟着标签走(标签隐藏时没有东西推它,只剩坐标系的 labelOffset);顶部轴的坐标系在上边。
  - 估算那一遍也要用零线:y 轴在 x 轴零点上时,末端名称在绘图区中间,`grid.left: 0` 不收。
  - 层级按画布算:半个画布以内的 grid 在估算时也用 0 档边距,右边正好让出 15 + 宽度 + 1。
  - 绘制用挪动后的位置:控件测试的居中名称改成 `nameGap: 0`,确认它确实被挪了十像素以上,再要求每个红色像素都在框里。

补完后除等价的一个外全部杀死。全量 **7756** 绿(新增 `test.advchart.axisnames` 17 条、`test.advchart.jsmath` 4 条)。

单独跑 `TAdvanceChartTest` 时 `TestASeriesLabelIsDrawnAndTakesItsInkFromItsMark` 会红(10 像素,断言要大于 10),上一个提交也一样,全量下是绿的;和本批无关,另立任务查。

### 还在队列里

标签稀疏(值轴不稀疏、类目自动间隔、fixMinMaxLabelShow、hideOverlap)→ containShape → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。
**[第三十九批做了标签稀疏,见 §73。]**

## 73. Tier 1 第三十九批:哪些轴标签画出来(2026-09-22)

port 以前对除时间轴外的每根轴都用同一条规则:找最小的等步长,让相邻标签之间留 4 像素。上游只按序号稀疏类目轴,数值、对数、时间轴一个标签也不因序号丢;两端和挤在一起的标签另有规则。这一批按上游重写"哪些标签画出来"。刻度、分割线、分割区域怎么跟着标签走留给下一批。

### 上游的做法

- **类目轴建哪些标签**(`ordinalScaleCreateTicks`):
  - 步长是 `max(interval + 1, 1)`。起点在类目 0 以外、步长大于 1、类目数除以步长大于 2 时,起点对齐到从 0 数的步长倍数。
  - 两端**总是**建:不在步长上的端点标为"间隔外"。
- **自动间隔**(`calculateCategoryInterval`):
  - 超过 40 个类目时每 `floor(n/40)` 个取一个样。
  - 每个样本的宽度取最宽一行,高度只取一行;都乘 1.3,且不小于 7。
  - 带宽是 `dataToCoord(e0+1) − dataToCoord(e0)`,按 `makeExtentWithBands` 和 `linearMap` 的运算顺序算。
  - 按轴的转角减标签转角,把带宽投影到标签的坐标系里:宽的比值用 cos,高的比值用 sin。
  - 取两个比值中较小的那个向下取整。带宽为 0 时结果是无穷大,这时只建首尾两个。
- **数值、对数、时间轴**:每个刻度建一个标签,从不按序号丢。
- **两端**(`fixMinMaxLabelShow`,所有轴类型):
  - `showMinLabel` / `showMaxLabel` 没写时:间隔外的端点、时间轴不整的端点直接隐藏;否则和邻居挤在一起就隐藏端点。
  - 写 `false`:隐藏端点。写 `true`:保留端点,挤在一起时隐藏邻居。
  - 类目轴写了 `interval: 0` 时整条规则都不跑;负的间隔不算。
  - "挤在一起"用 zrender 的相交判断,阈值 0.1。没开 hideOverlap 时不算文字边距,开了才算。
- **hideOverlap**(没有默认值):
  - 还显示着的标签先按"上一遍被隐藏的在前、优先级高的在前"稳定排序。优先级是 10 加时间轴的层级。
  - 然后依次检查,和已保留的任何一个相交(阈值 0.05,带文字边距)就隐藏。
- **相交**:两个框各缩一个阈值,外接矩形先相交。任一个不和坐标轴平行时,再用有向包围盒做分离轴测试,包括 zrender 只看**对方**投影是否为空的那个怪癖。
- **两遍之间**:
  - 估算那一遍什么都没越界(`noPxChange`)时,确定那一遍原样沿用估算的结果。
  - 否则类目轴在最终矩形上从头重建。数值、对数、时间轴沿用同一批标签,把估算时隐藏的标为"建议隐藏":端点规则里它们直接隐藏,hideOverlap 里它们排在最前面。

### port 以前

- 除时间轴外一律按"最小等步长 + 4 像素"稀疏,数值轴和对数轴也被按序号丢标签。
- 两端只认显式的 `true` / `false`;`true` 时保留端点的同时也保留邻居,两个叠在一起。没有默认的重叠规则。
- 时间轴不整的端点永远隐藏,`showMinLabel: true` 也叫不回来。
- 不读 `hideOverlap`;挤得放不下时强行保留第一个标签(上游可以一个都不显示)。
- 确定那一遍不知道估算那一遍隐藏了什么。

### 做法

- 新单元 `tyControls.AdvChart.AxisLabels`,都是纯函数:
  - `TyCategoryUnitSpan`、`TyCategorySampleStep`、`TyCategoryAutoInterval`、`TyCategoryBuiltList`;
  - `TyObbIntersect`、`TyLabelBoxesIntersect`;
  - `TyFixMinMaxLabelShow`、`TyHideOverlap`。
- 常数 1.3 按位写,三角函数用 `TyJsCos` / `TyJsSin`。
- `tyControls.AdvChart.Layout`:
  - 规格加上标签规则所属的轴类别(零值是数值轴,也就是从不按序号丢的那一侧)、`ShowAllLabels`(`interval: 0`)、原始的 `LabelRotateDeg`、`OnBand`、`OrdinalStart`、`HideOverlap`、时间轴的 `LabelLevel`、从估算带过来的 `LabelSuggestIgnore`。
  - `LabelHidden` 改名为 `LabelNotNice`,意思也改了:它是不整的端点,不再是"永远不画"。去掉 `KeepEveryLabel`。
  - `TyLayoutAxisLabels` 先放好所有标签,再建列表、跑端点规则和 hideOverlap。只有开了 hideOverlap 才给每个标签算框,否则只算两端各两个。
  - `TyAxisLabelStep` 只对类目轴返回步长(给刻度和线图符号用);标签关掉时也照样测量,因为刻度跟着它走。
  - `TySolveGridBounds` 多一个重载,告诉调用方有没有越界。
- Builder:
  - 读 `axisLabel.interval` 是否恰好为 0,以及 `axisLabel.hideOverlap`(按 JS 真值)。
  - 填上述规格字段。
  - 估算跑过且有越界时,数值、对数、时间轴在原始矩形上重排一次,把没显示的标成"建议隐藏"。名称那一遍重算标签时读同一个字段,所以和画出来的标签一致。

### 基准

- `tools/advchart-oracle/label-thinning.js`:
  - 126 条用例,112 条比较,14 条延后。
  - 每根轴每一遍记下类目轴的间隔及其全部输入,以及建出来的每个标签:间隔外、不整、层级、优先级、建议隐藏、是否显示、带边距和不带边距的局部框、矩阵。
  - 确定那一遍另记刻度、分割线、分割区域,留给下一批。
  - 生成器自检全部通过:间隔 130/130、带宽 130/130、标签列表 200/200、去留 286/286、两遍 233/233、收缩 112/112。
  - 临界守卫:离阈值最近的重叠量和离整数最近的比值,都远离判定边界。
- 测试 `test.advchart.labelthinning`,四层:
  1. 测宽逐位一致(872 个字符串)。
  2. 用上游采样到的尺寸和带宽,自动间隔和带宽**逐位**一致,标签列表一致。
  3. 用上游的框和标记,端点规则加 hideOverlap 留下的标签和上游完全一样,包括转过的标签走有向包围盒的那些。
  4. 整条流水线:每根轴画出的标签文字、类目轴的步长和上游一致,grid 矩形在容差内。
- grid-bounds 的 W2、inverse value x、AC、B 解除延后;PM4 的说明改正:最后一个标签是因为在间隔外被丢,不是因为重叠。

### 被推翻的旧测试

- `test.advchart.axis.pas`:
  - 四条稀疏测试加上"类目轴"(以前规格里不分类别)。
  - "永不全部隐藏"改成"太短的轴一个也不显示",这是上游的行为。
  - "被稀疏的标签不计入"改成只剩首个,尾端在间隔外被丢。
- `test.advchart.axislabel.pas`:
  - 步长 2 时首个标签和邻居挤在一起,被隐藏。
  - `interval: 0` 全部保留;负间隔会隐藏挤着的两端。
  - `showMaxLabel: true` 两处改成 0,5,11:保留端点,隐藏邻居。
- `test.advchart.time.pas`:月份哨兵从 `'LocaleProbeMar'` 改成三个字符的 `'MaR'`。太长的首个标签会和邻居挤在一起而被隐藏,上游也是这样。
- `test.advancechart.pas`:
  - "拥挤的轴要稀疏"改成数值轴 151 个标签画 149 个,只丢挤着的两端。
  - "主刻度稀疏后次刻度消失"改成数值轴不稀疏、次刻度照画(上游画 1200 个)。
- 原处都有标注。

### 已知偏差

- **刻度、分割线、分割区域**还按 `i mod 步长` 画:没有和隐藏标签同步的刻度隐藏,没有补收尾那条边,`splitLine.interval` / `splitArea.interval` 不读,分割区域不跟间隔。下一批做,基准已经记好。
  **[第四十批已做,见 §74。]**
- **类目轴的 `min` / `max`**:port 不截取类目范围,相关三条用例延后。
- **grid 盒子**:上下边距之和超过容器高度时和上游不同(time.pas:861 的场景),归 grid 盒子那一批。
- **按模型缓存的间隔**(跨 `setOption` 和缩放保持间隔稳定):port 每次从头算,只有单次渲染一致。
- `customValues`、函数间隔和格式化器、轴断裂、`minMargin`、标签的 `fontSize` / `width` / `overflow` 进入间隔测量:未做。
- 小数间隔仍按整数部分处理,这是有意的偏差(axislabel.pas:506)。
- 线图符号的稀疏仍按 `k mod 步长`,不按"类目在间隔上"。

### 变异测试

60 个,第一轮活 10 个,都是夹具分不出、补单元测试的:

- **有向包围盒的三处**:只查一个框的轴、投影不按阈值内缩、不问对方投影是否为空。夹具里真正由有向包围盒定去留的标签太少。构造了三组几何:
  - 斜长条只在自己的短边方向和方框分开;
  - 同转角的两个方块互相嵌入 0.05 时分开,嵌入 0.15 时相交;
  - 内缩后没有内部的细条什么都不相交。
- **两个阈值**:端点规则 0.1、hideOverlap 0.05。两个水平标签互相嵌入 0.15:端点规则认为分开,hideOverlap 认为相交。
- **端点规则两处**:
  - 邻居在估算里被隐藏时直接隐藏邻居;
  - 已隐藏的标签不再和谁相交:两个完全叠在一起的标签,min 规则隐藏第一个,max 规则就不再动第二个。
- **7 像素下限**(高度这一侧):空标签在 2 像素的带宽上,间隔是 3。
- **无穷间隔的步长**:长度为 0 的轴,步长跳过除第一个以外的所有标签。
- **`hideOverlap` 的真值**:`1`、字符串、对象为真,`0`、空串为假。

补完后全部杀死。全量 **7770** 绿(新增 `test.advchart.labelthinning` 14 条)。

### 还在队列里

轴部件跟随标签(刻度与隐藏标签同步、收尾边、`splitLine` / `splitArea` 的间隔、次刻度)→ containShape → 类目轴 `min` / `max` → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。

## 74. Tier 1 第四十批:刻度、分割线、分割区域跟着标签走(2026-09-22)

上一批定下了哪些标签画出来,这一批让轴上的其余部件按上游的方式跟上。上游的规则在 §73 的审计里已经跑过验证,基准就是上一批夹具里确定那一遍的记录。

### 上游的做法

- **类目轴**:刻度、分割线、分割区域各读自己的 `interval`。
  - 没写(`auto`)时取标签列表的那些刻度,包括间隔外的两端。标签关掉时照样按标签的间隔算。
  - 写了数字时用同样的办法按这个数字建列表。
- **在带子上**(`boundaryGap` 为真,且这个部件的 `alignWithLabel` 没开):
  - 所有坐标在轴自己的坐标系里退半个带宽;
  - 最后一个如果在间隔外就去掉;
  - **总是**补一条边:原来最后一个的坐标加一个带宽,对应第 n 个类目。
  - 反向轴上这条收尾边会落在奇怪的位置(三十个类目时在 105 而不是轴端的 90),上游如此,照搬。
- **数值、对数、时间轴**:每个主刻度一个。
- **刻度跟标签同步**:标签建了但被隐藏时,对应的刻度也隐藏。不在带子上的才同步;显示次刻度(`minorTick.show`,类目轴上也读)时不同步。
- **分割线**:首尾两条可以分别用 `showMinLine` / `showMaxLine` 关掉,不跟标签同步。
- **分割区域**:相邻两个坐标之间一块。
- **次刻度、次分割线**:和标签无关,总是画。

### port 以前

- 三样都按 `i mod 步长` 画,步长是标签步长,或者 `axisTick.interval` 给的步长。
- 分割线也跟着 `axisTick.interval` 走;`splitLine.interval` / `splitArea.interval` 不读。
- 收尾那条边只有类目数正好整除步长时才画。
- 分割区域完全不管间隔,每隔一个带子涂一块。
- 标签被隐藏的刻度照画。
- 主刻度一稀疏,次刻度和次分割线就全部不画。

### 做法

- `tyControls.AdvChart.Layout`:
  - 新类型 `TTyAxisMark`,记录刻度值、坐标、是否间隔外、是否在带子上、是否画。
  - 规格加 `TickMarks`、`SplitLineMarks`、`SplitAreaMarks`。
  - 导出 `TyCategoryLabelInterval`。
- `tyControls.AdvChart.AxisLabels`:`TyFixOnBandMarks`,逐条转写 `fixOnBandTicksCoords`。
- Builder:
  - 读 `axisTick` / `splitLine` / `splitArea` 各自的 `interval` 和 `alignWithLabel`,以及原样的 `minorTick.show`。
  - 在写入最终矩形之后算三组标记:类目轴在上游的轴坐标系里做半带宽平移和收尾,再换回画布坐标;数值轴一个主刻度一个。
  - 定下哪些画。
- 绘制只读这三组标记;次刻度、次分割线去掉"步长为 1 才画"的条件。PaintAxis 里不再有步长。

### 基准

- `test.advchart.labelthinning` 新增一条:112 条用例里每根轴确定那一遍的刻度和分割线,对应的刻度值和是否画必须完全一致,坐标在用例容差内;分割区域比块数和边界。
- 一次通过,包括反向类目轴那条奇怪的收尾边。

### 被推翻的旧测试

- `test.advchart.axislabel.pas`:`axisTick.interval: 4` 下 12 个类目的刻度从 3 个改成 4 个,即 0、5、10,加上收尾的 12。
- `test.advchart.time.pas`:注释更正。上游不整的端点标签被隐藏时,刻度也一起隐藏,不是"保留刻度"。
- 原处都有标注。

### 已知偏差

- 分割区域的颜色:上游两种颜色交替,并且跨渲染保持连续;port 用主题的一种颜色,隔一块涂一块,只管首次渲染。
- 线图符号的稀疏仍按 `k mod 步长`,不是"类目在间隔上"。
  **[第四十四批已做,见 §78。]**
- `customValues`、函数间隔、轴断裂:未做。

### 变异测试

31 个,第一轮活 1 个:绘制时不看"画不画"、把所有刻度都画上。像素测试里被同步隐藏的刻度只有流水线数据里有。补了一条像素测试:12 个类目、`boundaryGap: false`、`interval: 4`,第十一个标签在间隔外被隐藏,屏幕上只画 3 个刻度;在带子上时则是 4 个边,含收尾的一个。

补完后全部杀死。全量 **7772** 绿。

### 还在队列里

containShape → 类目轴 `min` / `max` → 线图符号跟着标签间隔 → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。

## 75. Tier 1 第四十一批:containShape(2026-09-23)

柱子站在数值轴、对数轴、时间轴,或者 `boundaryGap: false` 的类目轴上时,两头的柱子原来有一半画在绘图区外面,被截掉。上游给这种轴另算一个 **mapping 范围**:在刻度范围两边各加半个柱宽。值按 mapping 范围落位,刻度仍按原来的范围取。port 的刻度层早就有两种范围(§2),只是从来没人写 mapping。

### 上游的做法

- **谁要放宽(ctnShp)**:
  - 轴的 `containShape` 按 JS 真假读;没写时,类目轴 `boundaryGap` 为真就不放宽,其余都放宽。
  - 而且这根轴得是某个 `bar` 或 `pictorialBar`(cartesian2d)的**基轴**。柱子的数值轴从不放宽。
  - 被图例关掉的系列、一行数据都没有的系列也算。
- **平的零点**:要放宽的轴上,数据全是 0 时范围张成 [-1, 1],不是 [0, 1]。`min: 0, max: 0` 也一样。对数轴在指数空间里做,单个 1 得到 [0.1, 10]。时间轴不管这条。
- **半个柱宽(数据空间)**,每种系列类型各算一次:
  - 先算最小间隔:没被图例关掉的系列,所有行的基轴值,只取有限值;对数轴只取正值,换成以底数为底的对数。排序后取最小的正差。
    所有值都相同时得到 SINGLE,没有值时得到 NONE。
  - 类目轴:`px / span * span / px`,通常是 1,末位由这趟像素往返决定(12 个类目、400 px 时是 1.0000000000000002)。
  - 数值轴:有间隔就用间隔;SINGLE 时用 `px * 0.8 * span / px`,直接写 `0.8 * span` 有三分之一的情况末位不同;NONE 时不放宽。
  - 这里的 `px` 是布局选项给出的像素长度,也就是标签收缩绘图区**之前**的那个。上游做 nice 时,坐标系是新建的,还没收缩。
- **mapping 范围**:各类型的半宽取并集,加到刻度范围两端。
  - 类目轴总是写。
  - 其余轴只有真的变宽才写。对数轴在指数空间里加,再换回原值。
  - `min` / `max` 挡不住这一步。
- **谁读哪个范围**:
  - 刻度、标签、分割线、`clampData`、onZero 的"零在范围内"判断:读刻度范围。
  - 落位、带宽、`contain`:读 mapping 范围。
- **柱子的带宽**:最终像素长度 ÷ mapping 范围的线性跨度 × 最小间隔;SINGLE 时是像素长度的 0.8;下限 1 px。
- **onZero**:一根轴只要加了半宽,就记为"零点不宜"。对面轴的 `axisLine.onZero` 没写或写 `'auto'` 时,不再站到它的零点上;写 `true` 仍然站上去。

### port 以前

- 没有 ctnShp,平的零点总是 [0, 1]。
- 从来不写 mapping 范围,两头的柱子被截掉一半。
- 带宽按刻度范围算。对数轴按原值算间隔,也不滤掉非正值。
- `Contain` 读刻度范围,和上游相反。
- onZero 只有真假两态。

### 做法

- `Scale`:
  - `TTyIntervalScale.ContainShape` 标志,平的零点在它为真时张成 [-1, 1]。
  - `Contain` 改读 mapping 范围。
- `Series`:
  - `TyMinGapOf`、`TyLiPosMinGap`:最小间隔统计,两个特殊答案是 `cTyMinGapSingle` 和 `cTyMinGapNone`。
  - `TyApplyAxisExtents` 先算每根轴的 ctnShp。它直接查绑定,因为索引跳过了隐藏系列。
  - nice 之后写 mapping 范围;类目轴在按类目数定范围之后写。
  - 半宽用的像素长度就是阶段 A 写好的那个,正好是上游的初始长度。
- `Coord`:`TTyAxis.ZeroDiscouraged`。
- `BarLayout`:
  - 带宽按 mapping 范围的线性跨度算,间隔用同一个统计。
  - `TyBandFromMinGap` 按上游的判断顺序:先看"有间隔、跨度为正",再看 SINGLE,都不是就不放宽。
- `Builder`:
  - 家具记录加 `OnZeroAuto`:键没写、写 `null` 或写 `'auto'` 时为真。
  - `CanProvideZero` 在 `auto` 下拒绝零点不宜的轴。
- `TTyAdvanceChart.BarColumnOf`(受保护):测试读柱子求解结果用。

### 基准

- `tools/advchart-oracle/contain-shape.js` → `tests/fixtures/advchart-contain-shape.json`,82 条,4 条 deferred。
- 生成器自带 6 项自检:
  - 转写的 R2–R5 逐位复现 mapping;
  - 带宽等于 R7;
  - 变换矩阵等于仿射公式;
  - 刻度落在刻度范围上;
  - onZero 与 ctnShp 都符合规则。
- `test.advchart.containshape`,两遍(第二遍先 Invalidate),共 1008 项比较:
  - 刻度范围、mapping 范围、ctnShp、零点不宜、onZero、带宽 / 偏移 / 柱宽:逐位;
  - 对数轴 8 ulp;
  - 盒子 8 ulp;
  - 刻度坐标 1 ulp,G9 为 8 ulp。
  - 一次通过。
- 解除 deferred:
  - bar-geometry 的 `value base axis [[1,5],[2,-3],[4,2]]`,盒子在该测试的 1 ulp 容差内一致;
  - grid-bounds 的 `boundaryGap false category, long labels, interval 1, grid left/right 0`,最终矩形一致。
- G8 的 4 条是文档性的:只比范围,最终矩形归 grid-bounds 管。真正能分辨"初始像素长度"和"最终像素长度"的只有 PX3。

### 被推翻的旧测试

- `test.advchart.barlayout.pas`:`min: 0, max: 10` 上 x = 1, 2, 3 的带宽从绘图区的 1/10 改为 1/11。上游的 mapping 是 [-0.5, 10.5],`min` / `max` 挡不住。
- `test.advchart.scale.pas`:`TestEffectiveExtentStillDrivesContain` 改为 `TestMappingExtentDrivesContain`。原测试钉的是上游的反面。
- `Scale` 单元头的注释同样更正。
- 原处都有标注。

### 已知偏差

- **仿射快路径**:
  - 上游在 value/time × value/time 上用坐标系的仿射矩阵落位,port 逐轴算,盒子最多差 8 ulp。
  - y 轴端点的刻度坐标差 2 ulp:上游是 `(r0 + r1) - map(n) + y`,port 是 `a + n * (b - a)`。
  - G9 的 8 条只比轴、不比盒子。下一批做。
  **[第四十二批已做,见 §76。containshape 的盒子、刻度、G9 现在全部逐位比较。]**
- **对数轴的 pow**:mapping 端点是 10 的小数次幂,FPC 的 `Power` 和 V8 的 `Math.pow` 差 6–7 ulp(10^2.5、log 2/3/50 的上端)。审计估计的 4 ulp 不够,容差放到 8。要逐位一致,得移植 fdlibm 的 `pow` / `log`。
- **candlestick 和 boxplot** 也会让 ctnShp 为真,上游值轴上的 candlestick 也会放宽(mapping [-0.5, 4.5]);port 的 K 线在非类目轴上是固定的 8 px,这批不管。用例 deferred。
- alignTicks、dataZoom(`zoomFixMM`)、axisPointer 的钳位与阴影宽:port 还没有这些功能,用例 deferred。
- 时间轴平的范围仍是前后各一天,和上游一样,不走 [-1, 1]。

### 变异测试

42 个变异体,杀掉 36 个,活下来 6 个,都是等价的:

- 两个是多余的守卫,已删:
  - 每次构建都把"零点不宜"清零。轴每次构建都是新建的,不用清。
  - 对数统计里先滤掉非正值。`TransformIn` 对非正值本来就返回 NaN,随后会被滤掉。
- 四个照上游原样保留,改掉也看不出差别:
  - 没写 `containShape` 时类目轴 `boundaryGap` 为真就不放宽:在带子上的类目轴本来就不加半宽。
  - 有间隔时还要求跨度为正:nice 之后跨度总是正的。
  - 数值轴"真的变宽才写 mapping":半宽总是正的,所以总会变宽。
  - 类目轴 mapping 的写法:同理。退一步说,就算写了一个和刻度范围相同的 mapping,落位结果也完全一样。

两处删改之后重编,全量 **7773** 绿。

### 还在队列里

仿射快路径(value/time × value/time)→ 类目轴 `min` / `max` → 线图符号跟着标签间隔 → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。V8 兼容的 `pow` / `log` 视需要插进来。

## 76. Tier 1 第四十二批:坐标落位逐位对齐上游(仿射矩阵与逐轴公式)(2026-09-23)

§75 留下的尾巴是仿射快路径。审计发现问题不止这一处:port 的逐轴公式本身和上游不同(类目轴上也不同),网格矩形丢了宽高,柱子的盒子和裁剪另有写法,折线顶点上游存成 float32,时间数据在读入时被取整。这一批把一个值从数据落到画布的整条路都换成上游的算法。

### 上游的做法

- **网格矩形**:上游始终按 `(x, y, width, height)` 保存。给了宽度就用那个宽度,右边缘是 `x + width`。`(x + w) - x` 不一定等于 `w`。
- **网格选项的合并(mergeLayoutParam)**:用户在一个方向上写了两个键(比如 `right` 和 `width`),就只用这两个,默认的 `left` 丢掉;只写了一个,就从默认值里按 left、right、width 的顺序补第一个没写的;写成 `null` 或 `'auto'` 的键算写了但没有值。
- **逐轴落位**:
  - 轴有自己的局部范围 `[0, w]`,反向时是 `[w, 0]`(交换两端,不是 `1 - n`);
  - 类目轴在局部范围上各收半个带;
  - `linearMap(n, [0,1], [r0,r1])`:n 为 0 或 1 时原样返回端点,其余 `n * (r1 - r0) + r0`;clamp 时越界返回端点;
  - 再转到画布:x 是 `c + x`,y 是 `(e0 + e1) - c + y`;
  - 时间轴先按 `Math.round` 取整到毫秒(scale.parse);
  - 值是 NaN 且轴的范围是平的(一个类目),落在中点(normalize 先答 0.5)。
- **仿射矩阵**:
  - 两根主轴都是 value 或 time(不是 log、不是类目)才有;两根轴的 mapping 跨度都不能为 0 或 NaN。
  - 用逐轴落位算 mapping 两端的点,`sx = (end - start) / span`,`tx = start - m0 * sx`;时间轴的两端因此先被取整。
  - 只在最终矩形写定之后算一次(Grid.resize 末尾);还有逆矩阵(zrender 的 invert,行列式为 0 时没有)。
  - `dataToPoint`:两个值都有限才走矩阵,否则两维都走逐轴;矩阵不 clamp。`pointToData` 有逆矩阵就用逆矩阵。
- **柱子**:`coord = dataToPoint([base, value])`,`x = coord.x + offset`、`width = size`、`y = 底`、`height = coord.y - 底`(横向对称);底是数值轴起点(逐轴),堆叠时是 `dataToPoint` 算的下一层。barMinHeight 之后按 `clip.cartesian2d` 在 x/width 形式下裁剪到 `getArea()`,远端总是 `x + width`。
- **pictorialBar**:布局同柱子,图形沿 `layout.xy + layout.wh / 2` 居中;**不堆叠**(getInitialData 把 `stack` 置空)。
- **折线**:顶点、面积下沿、符号位置都来自 `Float32Array`。
- **时间数据**:数据存储里数值原样保留,只在落位时取整。
- **对数轴**:nice 之后用存下的指数空间范围(比如 -1 到 3)归一化,不是端点的对数(-0.9999999999999998)。

### port 以前

- 网格只存四条边,宽度靠 `Right - Left` 反推。
- grid 只写 `right` + `width` 时,默认的 `left: 15%` 还在,落进"起点 + 尺寸"分支,整个网格放错位置。
- 逐轴公式是全局两端之间的 `a + n * (b - a)`,反向用 `1 - n`,带宽内缩也在全局坐标上做。
- 没有仿射矩阵。
- 柱子盒子用 `Min/Max` 拼,在带子中心 `(L + R) / 2` 上加偏移,裁剪直接夹四条边。
- pictorialBar 会堆叠。
- 折线顶点是 double。
- 时间数据读入时按银行家舍入取整。
- 对数轴归一化用端点的对数。

### 做法

- `Types`:`TTyXYWH`、`TTyMat2D` 及转换函数从 Layout 挪过来。
- `Layout`:`SolveAxis` 多给出上游的长度(给了尺寸就是尺寸);`TySolveBoxXYWH`;`TySolveGridBoundsXYWH`、`TyLegacyContainLabelXYWH` 以 XYWH 进出。
- `Builder`:
  - 网格保存 `OuterXYWH` / `PlotXYWH`,四条边由它导出;
  - grid 的 box 选项按 mergeLayoutParam 合并(`MergedBoxDim`);
  - 最终写矩形后调用 `CalcAffineTransform`。
- `Coord`:
  - 轴存局部长度和基点(`SetLayoutExtent`),`LocalExtent`、`BandExtent`、`ToGlobal`、`ToLocal`、`DataToLocal`;`DataToCoord` 可 clamp;`PxLength` 是宽度本身,带宽和 containShape 的像素长度都用它;
  - 雷达等仍用 `SetPxExtent`(恒等映射);
  - 笛卡尔系存 XYWH,`CalcAffineTransform`、`Transform`、`InvTransform`、`GetArea`、`DataToPointClamped`,`PointToData` 走逆矩阵。
- `Marks`:柱子按上游布局 + `ClipBarLayout`;pictorialBar 的列和堆叠底同上;折线顶点和面积下沿经 `TyJsFround`。
- `JsMath`:`TyJsFround`(Math.fround,溢出按半个末位判定为无穷,不交给会抛异常的转换)。
- `Scale`:`TTyIntervalScale.Normalize/Denormalize` 在对数轴、nice 未被改写、没有 mapping 时用存下的指数范围。
- `Stack`:pictorialBar 不堆叠。
- `Data`:时间维的数值原样保存。

### 基准

- `tools/advchart-oracle/coord-affine.js` → `tests/fixtures/advchart-coord-affine.json`,53 条(51 比较、2 文档性)。生成器有 8 项自检,包括逐位复现矩阵与逆矩阵、每条用例都能区分仿射与逐轴、port 旧公式与上游、D4(毫秒级时间柱子,两条路差 9.16 px)。
- `test.advchart.coordaffine`,两遍,一万多项:矩形、矩阵与逆矩阵、裁剪区、局部范围、刻度坐标、onZero 线、数值轴起点、每个点、柱列的 offset 和 size、柱子盒子、pictorial 底、折线顶点与面积下沿、各种探针(非有限值、clamp、pointToData 与轴的 pointToData、axisPointer 的 clamp 像素)。全部逐位,只有对数轴上从像素换回数值(pow 的小数次幂)放宽到 16 ulp。
  **[第四十三批:16 ulp 已归零,见 §77。]**
- 收紧的旧测试:
  - `test.advchart.containshape`:盒子、刻度 8 ulp → 逐位,G9 的盒子打开,绘图区直接比 XYWH;对数轴仍 8 ulp(mapping 端点是 pow)。
  - `test.advchart.bargeometry`:1 ulp(对数 4)→ 全部逐位,对数也是;绘图区比 XYWH。

### 被推翻的旧测试

- `test.advchart.data.pas`:时间维的数值不再取整;超过 Int64 的数也是数。原处有标注。
- `test.advchart.bargeometry.pas`、`test.advchart.containshape.pas` 的容差说明同样更正。

### 已知偏差

- **对数轴的 pow**:从像素换回数值、以及 containShape 的 mapping 端点,都要算小数次幂,FPC 的 `Power` 和 V8 的 `Math.pow` 差到 12 ulp。要逐位得移植 fdlibm 的 `pow`(可能还有 `log`)。
  **[第四十三批已做,见 §77。]**
- **坐标轴标签锚点**:上游经 AxisBuilder 的组矩阵(y 轴是旋转矩阵,含 `cos(π/2)` 的 6e-17),port 仍是 `L + p * len`,且 p 取自初始矩形。差 ≤ 2 ulp;类目轴带边刻度也还是全局 → 局部 → 全局的往返。
  **[第四十三批已做,见 §77。]**
- **axisPointer**:值的钳位仍按有效范围;clamp 的像素已经有了(`DataToCoord(v, True)`),指针还没改用。
  **[第四十三批:指针像素已改用 clamp。]**
- **K 线**:仍逐轴,没有 subPixelOptimize。
- **轴断裂**:port 不建断裂,矩阵门控没查断裂。
- title / legend 的 box 选项还没按 mergeLayoutParam 合并,只做了 grid。**[第五十二批已做,见 §86。]**

### 变异测试

55 个变异体。第一轮存活 15 个,其中 10 个是夹具里没有能区分它们的用例。给生成器补了 12 条用例:

- 反向的带轴画到最后一个类目(那里 `(r1 - r0) + r0` 不等于 `r1`);
- `(x + w) - x ≠ w` 的网格上放类目柱、数值基轴柱、单值 containShape,以及一个不收缩的 outerBounds;
- grid 只写 `width`,或写 `left: 'auto'`;
- 小数网格上 `((c - h) + (c + h)) / 2 ≠ c` 的横竖两种类目柱;
- 横向柱子在左侧被裁剪。

Pascal 测试另外加比柱列的 offset 和 size。这 10 个随后全部被杀。

仍然存活的 5 个:

- 4 个等价:
  - mapping 跨度为 0 的判断:nice 之后跨度不会是 0;
  - 换矩形后清掉旧矩阵:每次构建都新建坐标系;
  - CoordToData 两端原样返回:在数值轴上算式本来就精确到端点,在类目轴上结果还要再取整;
  - 裁剪之后的宽度写 `x2 - x` 还是 `x2 - AX`:AX 在这之前已经被赋成 x。
- 1 个被容差遮住:对数轴的 Denormalize 走不走存下的指数范围,差别淹没在 pow 的 16 ulp 里。等 fdlibm 的 `pow` 移植进来就能分辨。

重编后全量 **7775** 绿。

### 还在队列里

坐标轴标签锚点的组矩阵(连同类目轴带边刻度)与 fdlibm 的 `pow` / `log` → 类目轴 `min` / `max` → 线图符号跟着标签间隔 → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。

## 77. Tier 1 第四十三批:坐标轴标签锚点、带边刻度与 V8 的 pow / log(2026-09-23)

§76 之后,数据落位已经逐位对齐,轴上的东西还没有:标签锚点用初始矩形上取的比例铺到最终矩形上;带边刻度要先转到画布再转回来;对数轴的小数次幂走 FPC 的 `Power`。审计另外找出一处肉眼可见的错误:onZero 的顶部轴,标签旋转方向反了。

### 上游的做法

- **轴框(cartesianAxisHelper)**:
  - 位置 `(X, Y)`:x 轴在 `(x, 上或下边界)`,y 轴在 `(左或右边界, y + h)`;边界是矩形边 ± `offset`;
  - 坐在另一根轴的零点上时,X 或 Y 就是那个零点,`labelOffset` 是原位置与零点之差;
  - 位置是 `'top'` 才把 `rotate` 取反;坐在零点上的轴位置是 `'onZero'`,不取反。
- **标签锚点(AxisBuilder)**:
  - 局部点 `(c, t)`:c 是轴自己的坐标(`dataToCoord`);`t = labelOffset + 方向 × margin`,`inside` 时方向反过来;offset 已在 `(X, Y)` 里,不进 t。
  - 用轴组矩阵变换:x 轴 `[1,0,0,1,X,Y]`,y 轴 `[ct,-1,1,ct,X,Y]`,`ct = cos(π/2) = 6.123e-17`。所以 y 轴标签横向是 `(ct·c + t) + X`、纵向是 `(-c + ct·t) + Y`——不是 `toGlobalCoord`。
  - 估算那遍在初始矩形上、最终那遍在最终矩形上各算一次;最终那遍在写入最终矩形之后。
- **带边刻度与分割线**:在轴自己的坐标里取 `dataToCoord`、平移半个带、补收尾那条,再 `toGlobalCoord`。反向带轴上会重复一条、缺远端那条,上游如此,照搬。
- **长度**:offset、margin 等按写的值用;`v * 96 / 96` 对六分之一的 double 不等于 v。
- **轴名称**:沿轴的范围是 `[0, w]`,不是右边减左边。
- **Math.log**:V8 用的就是 fdlibm 的 `e_log.c`。**Math.pow**:fdlibm 的 `e_pow.c`,只改了一行:修正项放进了除数里(ieee754.cc:2894)。
- **对数轴的线性范围**:span、半宽、带宽用的是 intervalStub 存下的指数范围(比如平零张开的 `[-1, 1]`),不是 pow 端点的对数。

### port 以前

- 标签锚点是 `L + p·len`(y 轴 `B − p·len`),p 取自初始矩形,而且是在写入最终矩形之前算的;横向用 `边 ± (margin + offset)`,没有 `ct` 项。y 轴横向差到 36 ulp,纵向差到 8 ulp。
- 顶部轴一律取反旋转角。onZero 的顶部类目轴因此斜向反了,对齐也反了。
- 带边刻度:全局 → 局部 → 全局,差 2 ulp。
- 长度按 `v * 96 / 96` 换算。
- 轴名称沿轴的范围是 `Right - Left`。
- 对数轴:`Ln` / `Power`;span 取 pow 端点的对数。
- axisPointer 的像素不 clamp。

### 做法

- `Layout`:规格加 `TickValues`、`LocalCoords`;有了它们,`TyLayoutAxisLabels` 用名称框(没有就用默认框)按轴组矩阵算锚点,没有就退回旧的比例路径(手工构造的规格用)。`AxisScaleF` 改成 `v * (PPI / 96)`,96 时就是 v 本身。
- `Builder`:
  - 先算出全部轴的 furniture,再逐轴建规格——判断"坐在谁的零点上"要读所有轴的 onZero;
  - 顶部轴只在不坐在零点上时取反旋转;
  - 最终矩形写入(连同仿射矩阵)提前到最终标签之前,随后重算名称框和各标签的局部坐标;
  - 带边刻度直接用 `DataToLocal` / `ToGlobal`;
  - 名称框的范围取轴自己的局部范围;AxisLineCoord 的 offset 也经 `AxisScaleF`。
- `JsMath`:`TyJsLog`、`TyJsPow`,逐行转写 fdlibm(V8 版);C 里靠溢出、除零、无效运算得到的 ±Inf、0、NaN 直接写出,两个可能溢出的特殊分支(`x*x`、`1/x`)临时屏蔽溢出。
- `Scale`:对数映射用 `TyJsLog` / `TyJsPow`;`LinearExtent2`:nice 过、没有被改写时返回存下的指数范围;containShape 的 span 和柱子的带宽都用它。
- `AdvanceChart`:指针像素 `DataToCoord(v, True)`。

### 基准

- `coord-affine` 扩到 63 条:新增顶部轴在零点上与不在零点上、offset 2.7 与 margin 12.3、inside、alignWithLabel 只对刻度、分割线间隔让最后一个类目出列、`(x + w) - x ≠ w` 的反向带轴等;每个标签记锚点、变换矩阵和局部框,每根轴记旋转、对齐、分割线坐标。
- `test.advchart.coordaffine` 新增比较:每个建出的标签的锚点与是否隐藏、旋转角与对齐、刻度标记与分割线坐标(空白轴除外),全部逐位;两万多项。
- `js-pow-log.js` → `advchart-js-powlog.json`:3,348 条 pow、2,824 条 log,包括教科书 fdlibm 与 V8 不同的 450 条和能区分 log 两个分支的 13 条;`test.advchart.jsmath` 逐位比较,另钉 `10^-4`、`10^-307`、`1.5^1025` 三个只有 V8 版才对的值。
- `axis-names` 加一条 `(x + w) - x ≠ w` 的中间名称用例。
- 收紧:
  - coordaffine 的对数反算 16 ulp → 0;
  - containshape 的对数 8 ulp → 0,现在全部逐位;
  - label-thinning 的刻度与分割线,在绘图区逐位一致的用例上逐位比较(至少 80 条);
  - axis-names 的名称:绘图区逐位一致时,挪动前的锚点逐位比较,没挪动的连最终锚点一起(至少 60 个)。挪动量量的是上游分解后的标签矩阵,属于上面的已知偏差。

### 被推翻的旧测试

- `test.advchart.furniture.pas` `TestATopAxisTurnsItsLabelsTheOtherWay`:onZero 的顶部轴保持 `+π/4`、左对齐;加 `onZero: false` 才是 `−π/4`、右对齐。
- `test.advchart.valueaxis.pas`:小数次幂不再钉 FPC 的 `Power`,而是 V8 的 `3.1622776601683795`。
- 原处都有标注。

### 已知偏差

- **旋转标签的矩形**:上游把组矩阵乘标签自身的变换,再分解、重组,旋转角因此差 1–6 ulp,±90° 时还要 V8 的 `tan`;port 直接用请求的旋转角。矩形差 ≤ 1.14e-13,在各用例容差内。`remRadian` 的写法也不同(差到 64 ulp,只影响这个矩阵)。
  **[第五十一批已做,见 §85。几处事实更正:分解后的旋转角差 ≤ 1.1e-15 rad;需要 V8 `tan` 的是请求角在 (−180°, −90°] ∪ [181°, 270°](顶部离零点的轴镜像),不是 ±90°;`remRadian` 两种写法最多差 1 ulp(2π),不是 64 ulp;不转的 y 轴标签也受影响——轴名称"占用区"经过同一矩阵,中间名称差 7.1e-15。]**
- 刻度线、轴线像素的 `subPixelOptimizeLine`,以及 y 轴刻度两端的 `ct·c` 项:是绘制几何,亚像素。
- 上游的 title / legend 选项合并(mergeLayoutParam)仍只做了 grid。**[第五十二批已做,见 §86。]**

### 变异测试

31 个变异体,第一轮存活 9 个。补了三样之后,其中 3 个被杀:

- log 的两个分支(|f| < 2^-20 的捷径、i > 0 的另一个核):搜出 13 个能区分它们的参数,作为 `kernel discriminators` 加进 js-pow-log 夹具;
- 轴名称的范围:axis-names 在绘图区逐位一致的用例上,改为逐位比较挪动前的锚点,没挪动过的名称连最终锚点一起逐位比较(至少 60 个名称)。

仍然存活的 6 个都是等价的:

- AxisLineCoord 的 offset 按 `*96/96` 换算:它只进一个到不了的钳位;
- 指针像素不 clamp:值在前面已经钳进有效范围了;
- pow 的 `y = 2` 特殊分支:走通用路径,得到的位也一样;
- 对数刻度的 `Ln`、底数的 `Ln`、数量级的 `Ln` 换成 FPC 的:win64 上 FPC 的通用 `Ln` 本身就是 fdlibm,和 V8 逐位相同。在有 x87 扩展精度的平台上(比如 x86_64 Linux),`Ln` 走 x87,就不一样了,所以 `TyJsLog` 保留。

重编后全量 **7777** 绿。

### 还在队列里

类目轴 `min` / `max` → 线图符号跟着标签间隔 → roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。旋转标签矩形的分解重组(连同 V8 的 `tan`)视需要插进来。

## 78. Tier 1 第四十四批:类目轴的 min / max,线图符号跟着标签,线的裁剪(2026-09-24)

类目轴的 `min`、`max`、`startValue` 以前一概不读:一进 TyApplyAxisExtents,类目轴就被设成"全部类目"然后返回。这一批让类目轴也走原始范围那条路,顺带把依赖它的几处补齐——线图符号的稀疏(原在队列第二位)、线和散点的裁剪、指针只落在真实类目上。

### 上游的做法

- **解析**:
  - 数字按 `Math.round` 取整,当作类目序号(`2.5` → 3,`-2.5` → -2)。
  - 字符串是类目**名称**,原样查找——不去空格,也不当数字读:`'3'`、`''`、`' c'` 都查不到,整根轴变空白。
  - `true` / `false` 是 1 / 0;数组按 JS 的 `Number()`:`[3]` → 3,`[]` → 0,`['c']` → NaN。
  - `'dataMin'` / `'dataMax'` 取系列数据在类目维上的范围(图例隐藏的系列除外)。
- **范围**:
  - 没写的一端是第一个 / 最后一个类目;没有类目就是 NaN。
  - `dataMin` / `dataMax` 这两个**选项键**对类目轴不起作用。
  - 越过类目列表两端也允许,多出来的位置标签为空。
  - 写反了就交换并翻转轴;`startValue` 能放宽没被钉住的一端。
  - 任何一端无效,或者一个类目都没有,轴就是空白的:不画标签、刻度、柱子。
- **数据**:固定类目列表上的数字按序号原样保存,越界也保留,落位时再 `Math.round`,最后由裁剪处理。
- **自动间隔**:unitSpan 是 `dataToCoord(e0 + 1) − dataToCoord(e0)`,在 mapping 范围上。
- **线图符号**:`showAllSymbol` 为 false,或为 'auto' 且挤不下时,只在"有标签的类目"(建出来、且不在间隔外的)上画符号,按数据在类目维上的**值**判断,不按点的顺序。
- **线的裁剪**:`getArea` 外扩半个线宽,宽度向上取整,x 不是整数时向下取整并把宽度加 1,y 不动;`clip: false` 只沿数值方向放宽"宽、高中较大者"的两倍。符号在区域 ±0.1 之外的不创建;散点用 `getArea(0.1)`。
- **指针**:落在范围内、并且是真实存在的类目上(`0 ≤ v < 类目数`)才出现;绘图区的四条边都算在内。

### port 以前

- 类目轴的 min / max / startValue / 反向规则全不读。
- 固定类目列表上越界或带小数的数字当作缺口。
- 线图符号按"第几个点"每隔几个画一个;`showAllSymbol: false` 也先判断拥挤。
- 线和散点完全不裁剪,出了绘图区照画。
- 指针:只看有效范围,空位置也会停;绘图区右、下两条边不算在内。

### 做法

- `Series`:`ParseOrdinalBound`;`TyAxisRawExtent` 加类目模式(不读 dataMin / dataMax 键、空端取首末类目,没有类目时为 NaN);类目轴走完整的数据循环和原始范围,再由 `ApplyCategoryExtent` 写入(窗口超过 2^20 个类目视为空白,是记录在案的偏差)。
- `Scale`:类目刻度的 `Blank` 继承 MarkedBlank 与 NaN 范围;范围为 NaN 时 `Normalize` 返回 NaN;`JsFloor` / `JsCeil` 导出。
- `Data`:固定类目列表上的数字原样保存。
- `Coord`:落位前类目值按 `Math.round` 取整;`ContainPoint` 按轴的局部坐标闭区间判断;`GetAreaTol`。
- `Layout`:自动间隔的 unitSpan 取规格里前两个标签的局部坐标之差。
- `Marks`:线图符号按类目值与标签列表稀疏;`TTyLineSpec.Clip`;线和面积带上游的裁剪矩形,符号和散点按区域剔除。
- `BarLayout`:空白轴(跨度为 NaN)不再在比较里抛异常。
- `AdvanceChart`:指针检查"是真实类目"和空白轴,绘图区用 `ContainPoint`;`NewTextMeasurer` 受保护的虚函数,测试可换成 zrender 的宽度表。

### 基准

- `tools/advchart-oracle/category-minmax.js` → `advchart-category-minmax.json`:96 条,3 条按声明延期(`data: []` 配纯数值的两条、`min 1e300`)。
- `test.advchart.categoryminmax`:用 zrender 的宽度表量字(主题字号是点,换成像素),逐位比较:翻转、空白、有效与 mapping 范围、类目数、带宽、17 个值的包含与坐标、建出的标签(文字、间隔外、是否画)、自动间隔、刻度与分割线、柱列与每个柱子的盒子、线的顶点(float32)与裁剪矩形与带符号的数据项、散点的符号与位置、36 个指针探针(类目值与数据项)。一万多项。
- label-thinning 里原先延期的三条(C M1、C M2、F)解除,整条流水线逐位比较。

### 被推翻的旧测试

- `test.advchart.data.pas`:固定类目列表上的 7 和 1.5 不再是缺口,原样保存。
- `test.advchart.labelthinning.pas`:去掉已失效的延期豁免。
- 原处都有标注。

### 已知偏差

- `data: []` 配纯数值:上游用数据求范围并画出柱子,port 什么都不画(延期)。
- 超过 2^20 个类目的窗口视为空白;上游照样画两个标签。
- 渲染时裁剪矩形取整:上游的 y 不取整,port 的整数裁剪会向下取整,差半个像素。
- title / legend 的布局合并、旋转标签矩阵,仍在之前的已知偏差里。

### 变异测试

37 个变异体,第一轮存活 8 个:

- 3 个是多余的写法,已删:原始范围里的「无类目即空白」(类目刻度的 Blank 已经管了)、空白时把范围置 NaN(现在只在超过窗口上限时这么做)、类目轴上的 StartValue。
- 其余 5 个补了用例或测试:
  - 窗口上限:单元测试 `TestAHugeWindowIsRefusedNotWalked`;
  - 值轴空白时不给指针:单元测试 `TestABlankAxisTakesNoPointer`;
  - 裁剪宽度的向上取整:对照新增一条小数宽度网格上的面积线;
  - 面积多边形的裁剪:测试也比较面积的裁剪矩形;
  - unitSpan 取法:对照新增一条"两种算法间隔不同"的用例(W 507,区间 10 对 9)。
- 另有一个变异体的替换写法编译不过,修正后第二轮存活,于是补了单元测试 `TestAFractionalIndexLandsOnItsRoundedCategory`(1.5 落在第三个类目上)。

第二轮 34 个全部杀死。重编后全量 **7781** 绿。

### 还在队列里

roam → `focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。

## 79. Tier 1 第四十五批:graph 的 roam(平移、缩放、补偿缩放)(2026-09-24)

view 上的 graph 以前只有一个"数据矩形贴进框"的缩放加平移,`center`、`zoom`、`scaleLimit`、`nodeScaleRatio`、`roam` 一概不读,也没有任何交互。这一批把上游 View 的三层变换搬过来,接上 `graphRoam` 动作和两种手势,补偿缩放和数据空间裁边一起做。

### 上游的做法

- **三层变换**:raw 把数据矩形贴进框(`sx = vw/dw`,`rx = (-dx)*sx + vx`);roam 以框心为中心缩放 `z`,把 `center` 挪到框心;overall = roam × raw。点走 overall 矩阵(`px = osx*x + ox`),回到数据走 overall 的逆矩阵,都是 zrender 的矩阵运算,运算顺序决定末位。
- **矩阵的零项不全是零**:`m[2]*y` 在 y 不是有限数时是 NaN,所以中心有一半读不出数,两个方向都变 NaN,整张图不画。
- **选项**:
  - `center` 和 `scaleLimit` 在系列没写时向根上找;`zoom`(默认 1)和 `nodeScaleRatio`(默认 0.6)不找。
  - `center` 的百分比按**数据矩形**的宽高,再加它的左上角;`'center'` 等关键字按百分比算。
  - `zoom` 是 `clamp(zoom || 1) || 1`;`scaleLimit` 是 `min || 0`、`max || Infinity`。
  - `roam`:`true` 和 `null`(根上也没有)是平移加缩放,`'move'` / `'pan'` 只平移,`'scale'` / `'zoom'` 只缩放,其他都关。`roamTrigger: 'global'` 在哪儿都接手势。
- **动作**:由 overall 反推 roam(`toRoam`),平移加在平移量上,缩放按"旧缩放 = overall 的 sx 乘 raw 逆矩阵"算、clamp 后绕原点缩放,再反推出新的中心和缩放写回选项。写回的缩放**不 clamp**;上次写成百分比字符串的那一维仍写回百分比,其余(包括关键字和数字字符串)都写成数。动作不受 `roam` 限制。没指定系列时,所有 view 上的 graph 一起动。
- **手势**就是一串动作:
  - 左键按下(不在可拖动节点上、在区域内)武装;每次移动发 `{dx, dy}`,相对上一次位置,指针出了画布也照样平移;左键抬起解除,中键和右键的按下、抬起都不算。
  - 滚轮 `d = delta/120`,`|d| > 3` 取 1.4、`> 1` 取 1.2、否则 1.1,反方向取倒数;绕指针缩放;没有 graph 接的滚轮不消费。
  - 多个 graph 重叠时,zlevel 高的先,再 z 高的,再系列序号小的。
- **手势区域**是数据矩形经 overall 变换后的矩形,闭区间;缩小以后区域跟着缩小。
- **补偿缩放** `ns = ((z-1)*(ratio || 1) + 1) / osx`:符号的半宽是 `fl(osx*ns) * (w/2)`,两个轴分别算;裁边在数据空间里按 `symbolSize * ns/2` 做;环形布局的份额也乘 `ns`。**只在渲染和带缩放的动作时重算**,平移后保持旧值(差一个 ulp,上游如此)。
- **什么留得下**:resize 和 merge 保留中心和缩放(环形在下一次布局时用新的 `ns` 重排);notMerge 清掉;一次 roam 不重新布局、不重跑力导向。

### port 以前

- 数据到像素是 `(d - left) * scale + viewLeft`,约三分之一的坐标差一个 ulp(力导向的基准因此放了 1e-6 的像素容差)。
- 回到数据用除法;区域就是框本身。
- roam 相关的选项一个不读;没有 MouseDown / MouseUp / 滚轮。
- 符号是圆的、按像素大小画;裁边在像素里按原始半径做;环形按像素大小分份额。
- 超过一千屏的节点按缩放后的像素判,放大一百多倍就会把节点和它的边一起扔掉。

### 做法

- `Graph`:
  - `TTyGraphView` 持 raw / roam / overall 三层和两个逆矩阵,矩形按 x/y/w/h 保存(框由 `TyGraphViewXYWH` 直接给出,不从右减左还原);`SetRoam`、`ApplyRoam`、`NodeScale`、`TriggerRect`、`RawToPoint`。
  - `TyGraphSpecOf` 读 `center`(`TTyGraphCentre`,记住哪一维写的是百分比字符串)、`zoom`、`scaleLimit`、`nodeScaleRatio`、`roam`、`roamTrigger`、`zlevel`、`draggable`(节点、类别、系列一路找下来)。
  - `TyGraphSolve` 多一个 roam 状态参数:roam 过就用 roam 写回的中心和缩放;先算 `ns` 再布局。
  - 边多存数据空间的控制点和裁好的两端(`TyGraphTrimInView`),再经视图映射(`TyGraphMapEdges`);构建器画这两端,不再自己在像素里裁。
  - `TyGraphRoamStep`、`TyGraphRemap`(不布局,只重新映射;带缩放才重算 `ns` 并重新裁边)、`TyGraphWheelScale`。
  - 远近按 raw 像素判(`TyGraphSanitiseView`、控制点同理)。
- `AdvanceChart`:
  - roam 状态按系列序号存在构建之外(和力导向的答案一样),`SetOptionText` 清掉;`ns` 按槽位存。
  - API:`GraphRoam`、`GraphZoom`、`GraphDispatchRoam`、`GraphRoamState`、`GraphView`、`GraphNodeScale`;事件 `OnGraphRoam`(每个动作每个系列一次);发布 `OnMouseWheel`。
  - `MouseDown` / `MouseMove` / `MouseUp` / `DoMouseWheel`(宿主的 `OnMouseWheel` 先处理)/ `CaptureChanged`(丢了捕获就结束拖动);`MouseLeave` 不结束拖动。
  - 一步 roam 只丢静态层重画,不置 FDirty,构建和力导向答案都保留。
  - 零、负数、NaN、无穷的缩放一律拒绝(上游会把负缩放分解成旋转 π,下一步又翻回来)。

### 基准

- `tools/advchart-oracle/roam.js` → `advchart-graph-roam.json`:83 条,346 个状态。79 条逐位比较,2 条只记录(非等比视图下的线宽和箭头压扁、子像素对齐),2 条按声明延期(负缩放)。生成器自检:内嵌配方逐位复现每个数、手势按事件回放逐位一致、各项区分计数都 ≥ 1、两次生成逐字节相同、非有限数都已分类。
- `test.advchart.graphroam`:用控件自己的 API 和鼠标重写方法驱动(resize 用 SetBounds,merge 用 Invalidate,notMerge 用换选项),每一步之后逐位比较:三层变换和两个逆矩阵、区域和每个探针点(连同区域边上的前后一个 ulp)、探针点回到数据、选项里的中心(种类和值)和缩放、实际用的缩放、`ns`(连同重算值)、每个节点的数据位置、像素和实际画出的半宽、每条边裁好的两端(数据和像素)、实际画出的折线端点和曲线中点、手势发出的每个 payload。约六万七千项。
- 环形的布局按十亿分之一比较;系列级节点标签也按十亿分之一(上游经符号自己的变换得到 `(px - half) + 2 half`,这里是 `px + half`,偶尔差一个 ulp)。
- 另有五个单元测试:缩放十万倍后远处节点和曲边照画;没有 graph 接的滚轮返回 False;宿主接了的滚轮不缩放;非正、非有限的缩放被拒;丢了捕获结束拖动。
- 力导向基准的像素容差从 1e-6 收紧到和数据空间一样(精确用例精确比较)。

### 被推翻的旧测试

- `test.advchart.graphforce.pas`:像素容差 1e-6 的理由("port 走缩放加平移")不成立了,原处有标注。

### 已知偏差

- 非等比视图下,箭头和线宽仍是固定像素;上游箭头按 x 缩放被压扁,线宽随方向变化(只记录)。
- 上游按线宽在数据单位里做子像素对齐,这里没有(只记录,另立任务)。
- 上游放标签前把宿主的包围盒按描边加宽,这里的标签不算描边,带边框的符号标签差半个边框。所有系列都如此,与 roam 无关(另立任务)。
- 只读系列级 `label`;节点自己的 `label` 不读。
- 给 `Option` 赋和现在一样的文本什么也不做,不等于上游的 notMerge 重置。（第 95 批修正：属性是声明，同一文本不算变化是对的；上游的 notMerge 是 `SetOption(text, True)`，同一文本也重来；合并是 `MergeOption`。见 §130。）
- 双指缩放、光标样式、拖动节点、roam 动画、拖动后抑制点击:不做。拖动期间悬停命中要等下一次重画才恢复。

### 变异测试

58 个,57 个被杀。

- 第一轮存活 4 个,补了用例和断言后杀掉 3 个:
  - "百分比中心不加数据矩形的左上角":原有用例的数据矩形都从原点开始,补了一个数据平移过的百分比中心用例;
  - "zoom 0 在 clamp 之前不当作 1":补了 `zoom: 0` 配 `scaleLimit.min` 的用例;
  - "曲线经未裁剪的控制点绘制":测试原来只比折线两端,加上比较折线中点。
- **等价的一个**:"数据到像素时丢掉矩阵的零项"。任一半不是有限数的节点本来就不画,边的两端也来自两半都有限的节点,这条路径观察不到。按上游保留。

### 还在队列里

`focus: 'adjacency'` → 内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。旋转标签矩形的分解重组(连同 V8 的 `tan`)、title / legend 的布局合并视需要插进来。

## 80. Tier 1 第四十六批:graph 的 `focus: 'adjacency'`,以及 graph 的 blur(2026-09-24)

以前 port 的悬停只有 emphasis:在动态层里把被悬停的元素复制一份、提亮后叠在上面;blur 一概没有,`focus` 读进来了但没人用,`'adjacency'` 连读都读不到(当成 none)。这一批给 graph 系列补上完整的悬停:四种 focus、blurScope、逐数据项的级联、声明的 blur 透明度,并把 graph 的悬停改成在静态层里原地画。

### 上游的做法

- **focus 的取值**:假值和 `'none'` 是不开;`'series'`、`'adjacency'` 是它们自己;**其他任何真值**(`true`、`1`、`'foo'`、数组)都当 `'self'`。
- **级联**:节点依次读数据项、类别、系列;边读 link、系列。`emphasis.focus / blurScope / disabled / scale` 和 `blur.*.opacity` 都走这条链。旧写法 `focusNodeAdjacency` 只在 `emphasis.focus` 没写时起作用,写成 `false` 也算开。
- **悬停节点,adjacency**:这个节点 emphasis;它的边(自环算一次)和这些边两端的节点保持 normal——**不提亮、不放大**;系列里其余全部 blur。没有边的节点集合是空的,连它自己都不在里面,于是其余全部 blur。
- **悬停边,adjacency**:这条边 emphasis,两端节点 normal,其余全 blur,**共用端点的边也 blur**。
- **self**:除了被悬停的元素全部 blur;**series**:本系列不动,范围内的其他系列全 blur;**none**:只有被悬停的元素 emphasis。
- **blurScope**:默认按坐标系(view 上的 graph 各有各的 view),`'series'` 只管本系列,`'global'` 管所有系列——另一个 graph 用**同一组下标**去解除 blur(上游的下标泄漏)。
- **emphasis.disabled**:这个元素被悬停时什么都不发生;被别人的悬停 blur 时状态是 B,**外观不变**,只有声明了的 `blur.*.opacity` 才生效。
- **外观**:
  - blur:透明度 = 声明的 `blur.itemStyle / lineStyle / label.opacity`,没声明就是正常值 × 0.1(边默认 0.5 → 0.05);颜色、大小、层级不变。
  - 节点 emphasis:只读 `emphasis.itemStyle`,填充色提亮(每个通道 ×1.1 取整,封顶 255),边框按声明;符号按 `max(1.1, 3/半高)` 放大;z2 +10。
  - 边 emphasis:只读 `emphasis.lineStyle`,描边提亮,宽度和透明度只按声明,**不加宽**;z2 从 0 到 10,仍在所有节点(100)下面;箭头的填充跟着边的描边走。
  - 标签跟着自己的节点 blur,悬停时在节点上面。
- **悬停标签就是悬停它的节点**,哪怕标签在符号外面。

### port 以前

- `'adjacency'` 读成 none,`'foo'` 之类读成 none;只读系列层的 emphasis。
- 没有 blur;声明的 blur 透明度会被 × 0.1 覆盖。
- emphasis 是动态层里的叠加副本:半透明的边被画两遍,颜色比应有的深;提亮的边盖在它两端的节点上面。
- 节点比边只高 1 层,z2 +10 的边会越过所有节点;箭头的 datum 是 (系列, -1),不跟着边变。

### 做法

- `Style`:`cfAdjacency`;focus 按真值规则解析;`TTyChartEmphasisSpec` 记下每个键是否写了(给级联用),并读同级的 `blur` 块;`TyChartMergeEmphasis` 做级联;`TyChartResolveStyle` 遇到声明的 blur 透明度就照用。
- `Paint`:`TTyPaintList.SetElement`,原地替换元素。
- `Graph`:节点 z2 改成边 +100(`cTyGraphNodeZ2`,与上游一致);箭头带边的 datum,仍然 silent;`TyGraphFocusSets`(上游的 ecFocus 集合)和 `TyGraphBlurStates`(先全 blur、再按下标解除)。
- `AdvanceChart`:
  - `GraphEmphasisOf` 走级联并认 `focusNodeAdjacency`。
  - `ApplyGraphHover` 在标签展开之后、对整张列表按 hover 改样式:范围内的 graph 按集合算出 N/B/E,blur 只改透明度,emphasis 原地提亮、放大、抬层;disabled 的元素只吃声明的 blur。
  - `PaintEmphasis` 跳过 graph 的元素。
  - `MouseMove` / `MouseLeave`:悬停的 graph 元素变了就只丢静态缓存重画(`RestyleStatic`),构建和列表都保留,命中测试不中断。

### 基准

- `tools/advchart-oracle/focus-adjacency.js` → `advchart-graph-focus.json`:51 条,45 条比较,6 条只记录(笛卡尔 graph 连带柱子、`label.show: false`、悬停边标签、highlight / downplay、悬停图例、global 下悬空 link 的泄漏)。生成器自检:每个悬停点命中预期的元素且在 port 的命中规则下不会误中、离开等于静止、数值与状态一致、状态从选项独立重算一致、键是双射、两次生成逐字节相同;二十多个错误模型各自至少被一条记录区分开。
- `test.advchart.graphfocus`:
  - oracle 测试经控件自己的 `MouseMove` / `MouseLeave` 驱动,先比命中的元素,再从实际绘制的列表里逐项比较:每个节点的透明度、填充、边框、半宽,标签的透明度和它在节点之上,每条边的透明度、描边、宽度,每个箭头的透明度和填充;z2 按顺序比较(节点之间、边之间、每条边对每个节点)。
  - 十二个单元测试,其中三个读像素,另有走缓存路径的离开、两次移动之间不重画仍命中、解析器保留声明的 blur 透明度:blur 的节点中心是填充色按 0.1 合成**一次**;高亮的边不盖住端点节点;半透明的高亮边只合成一次。期望值用 BGRA 自己的混合算(port 的画笔做 gamma 混合,和上游 canvas 不同,这是全局的既有差异)。

### 被推翻的旧说法和旧测试

- `test.advchart.emphasis.pas` 的文件头说"强调一定盖住它替换的东西",对 graph 的边不成立,原处有标注。
- 本 spec 里三处(blur 透明度一律算出来、blur 不在那一批的理由、欠账清单)原处有标注。
- `focus` 的未知字符串以前读成 none,现在按上游当 self。

### 已知偏差

- 其他系列的 blur 和 focus 仍没有做:它们照旧用叠加的 emphasis,`self` / `series` 也不会让别的柱子、扇区变暗。graph 和非 graph 系列之间的互相 blur(笛卡尔上 graph 连带柱子)不做。
- highlight / downplay 动作、悬停图例联动高亮、`emphasis.label`(`label.show: false` 时悬停显示标签)、边标签、状态动画:不做。
- 节点的 `itemStyle.opacity`、逐边的 `lineStyle`(除曲度外)仍不读,属于 normal 状态的欠账。
- 边的命中容差是 4 个逻辑像素,不是 zrender 的描边阈值。
- 坐标轴触发(`trigger: 'axis'`)时 graph 元素不再做叠加高亮。

### 变异测试

39 个,全部被杀。

- 第一轮存活 4 个,都是测试缺口,补测试后杀掉:
  - "声明的 blur 透明度又乘 0.1"在通用解析器里:graph 的路径不经过它,补了解析器的直接测试;
  - "节点读到连线的 emphasis":节点本来没有边框时测试什么都不比,补了"上游没边框、这里也不能长出边框";
  - "离开时不丢静态缓存":无头的 RenderTo 每次都重画,补了走 RenderCached 的测试;
  - "重画时连列表一起丢掉":补了"两次移动之间不重画,第二次仍然命中"的测试。

### 还在队列里

内部标签的自动描边 → `scaleCalcAlign` → 原始值通道 → tooltip 子行。旋转标签矩形的分解重组(连同 V8 的 `tan`)、title / legend 的布局合并视需要插进来。

## 81. Tier 1 第四十七批:标签的自动墨色与描边(halo)(2026-09-24)

以前标签只有一个颜色:内部按宿主亮度三档取墨,外部取主题的墨,没有任何描边;字面量 `label.color`、`textBorderColor`、`textBorderWidth` 一概不读。这一批按 zrender 的规则补上描边,把判定"内部"的条件、悬停时的重新配墨和几处相关的既有偏差一起修掉。

### 上游的做法

- **是否算内部**:位置含 `inside` **并且宿主有填充**(`fill` 不是 null 也不是 `'none'`;`'transparent'` 和渐变都算有填充)。没有填充的宿主上的标签走外部分支。饼图只有 `inside` / `inner` 算内部(`center` 不算),漏斗是 `inner` / `inside` / `center` / `insideLeft` / `insideRight`。折线的默认位置是 `top`。
- **内部墨色**:亮度 `(0.299r + 0.587g + 0.114b)·a/255`,大于 0.5 取 `#333`,大于 0.2 取 `#eee`,否则取 `#ccc`;渐变取 `#ccc`。与明暗模式无关。
- **内部描边**:宿主填充色本身(含 alpha),只有在"底色是深色"与"墨色是第 0 档"一致时才有——浅底上给第 1、2 档描边,深底上给第 0 档描边;渐变没有;透明的描边等于没有。
- **外部**:墨色按模式取主题的,描边是底色(不透明化)。
- **宽度**:`textBorderWidth || 2`,写 0 也是 2。
- **覆盖**:字面量 `label.color` 没有自动描边;`inherit` 取宿主色,也没有(漏斗例外:内部保留档位墨色并强制用宿主色描边,外部取宿主色、保留底色描边);`textBorderColor` 配上宽度就按它画,不管墨色;只写颜色不写宽度等于宽度 0,不画;`none` / `transparent` 去掉描边;标签有 `backgroundColor` 时没有自动描边。
- **悬停**:宿主填充变成 `emphasis.itemStyle.color` 或提亮后的颜色,整套规则在新填充上重算,档位可能翻转;`emphasis.label.color` 在悬停时去掉描边。
- **描边不加宽标签的包围盒**。先画描边后画字(`paint-order: stroke`)。

### port 以前

- 没有描边。
- 无填充的宿主当作浅色背景取第 0 档墨色;pictorialBar 的目标矩形被当成无填充;渐变按第一个色标算亮度。
- 三个内部墨色 token 是 `var(--on-surface)` / `var(--surface)`,深色皮肤里会翻过来,把浅色字放在浅色柱上。
- 字面量 `label.color`、`textBorderColor`、`textBorderWidth` 不读;饼图和漏斗连 `inherit` 都不读。
- 悬停的叠加层把宿主提亮后重画在上面,并丢掉了标签,内部标签被自己的柱子盖住。
- 折线标签没有默认位置,落在符号内部。

### 做法

- `Labels`:`TyLabelInkBand`、`TyLabelInk`(墨色 + 描边颜色 + 宽度,一处决定)、`TyLabelInkEmphasis`、`TyLabelStampEmphasis`;`TyLabelAutoColour` 把无填充改走外部分支;展开标签时按最终位置(柱子的 `outside` 按每根柱子的朝向)判定内部,并把悬停时的墨色和描边预先算好放在 caption 上。`TTyLabelSpec` 加了底色、是否深色、`textBorder*`、背景、漏斗 `inherit`、悬停覆盖等字段。
- `Paint`:caption 加 `StrokeColour` / `StrokeWidthLogical`(零值即无描边,图例、仪表盘等从不要描边的 caption 不受影响)、`HostTransparent`、`HasEmph` 与悬停时的三项。
- `LabelOpt`:`TyLabelReadInk`,所有系列共用,读字面量颜色、`inherit`、`textBorderColor`、`textBorderWidth`、背景、`emphasis.label.color` / `textBorderWidth`、`emphasis.itemStyle.color`;饼图和漏斗的规格各带一份。
- `Render`:描边在字形下面画——按描边半径(宽度的一半,按 PPI 换成设备像素)把文字用描边色在每个整数偏移处盖印一次,再画正文。
- `AdvanceChart`:底色与是否深色(`LabelGround`,亮度按背景 1 计,小于 0.4 为深)交给所有标签规格;折线默认 `top`;悬停叠加层把宿主的标签用悬停墨色重画在提亮的宿主上面;graph 原地改。
- 主题:三个内部墨色 token 改成不随模式变的 `#333333` / `#EEEEEE` / `#CCCCCC`,重跑了主题生成器(只动这三行)。
- 顺带修的既有偏差:
  - 柱子系列级 `itemStyle.color: 'none'` 以前落回主题颜色,现在是无填充。
  - 饼图和漏斗读系列级 `itemStyle.color`(以前每一块都按色板取色)。
  - 散点默认 `opacity: 0.8`(上游 ScatterSeries 的默认值,以前是不透明)。
  - 只有一个点的折线段(包括被空值隔开的孤点)以前连符号和标签都不画,现在照画符号。

### 基准

- `tools/advchart-oracle/inside-label.js` → `advchart-inside-label.json`:72 条,67 条比较,2 条只记录(标签背景、全局 `textStyle`),3 条延期(`darkMode` 选项、rich 标签、alpha 恰好在 .5 上的取整)。包含亮度恰好是 0.5 和 0.2 的两个颜色(`#04c26d`、`#033992`),钉住严格大于和双精度的计算顺序。
- `test.advchart.insidelabel`:
  - 选择器层:每条记录都用控件同一个读取器读选项,逐字节比较墨色、描边颜色和宽度,深底也比。
  - 集成层:浅底用例真实渲染,在控件实际生成的 caption 上比较墨色、描边、透明度和悬停时的墨色与描边(外部墨色是主题自己的,不比)。
  - 像素:外部标签配红色描边时字形周围出现红色像素、不配时一个都没有,且包围盒不变。

### 被推翻的旧测试

- `test.advchart.labels.pas`:"无填充,所以取深色墨"改为取外部墨,原处有标注。

### 已知偏差

- 描边用整数偏移盖印模拟,不是真正的轮廓描边;半透明的描边在盖印重叠处会略深。
- `darkMode`、图表级 `backgroundColor` 不读,底色和明暗来自皮肤。
- rich 文本、标签背景框、全局 `textStyle`、`textBorderType` / `textShadow*`、显式描边加宽包围盒:不做。
- 悬停时 `emphasis.label.position` 挪动标签:不做,标签留在原处。
- alpha 按字节取整,`rgba(…, 0.5)` 落到另一档(保留)。

### 变异测试

44 个。40 个被杀,4 个等价。

- 第一轮存活 7 个。补了三个测试后杀掉 3 个:
  - `textBorderColor` 配宽度与标签背景去掉描边(选择器单元测试);
  - 悬停后内部标签重画在提亮的柱子上(像素测试);
  - 字形画在描边之上(逐像素比较有无描边时字形墨色不变;原来那个变异本身写错了,末尾的字形照样最后画,改写后被杀)。
- "悬停不提亮"第一轮是因为编译不过才算被杀,改成能编译的写法后被测试杀掉。
- **等价的 4 个**:
  - 底色描边保留 alpha:皮肤底色总是不透明;
  - 透明描边也画:透明的盖印什么都不画;
  - 柱子 `outside` 标签按 spec 位置判内部:`outside` 映射到的位置本身就在外部;
  - `textBorderColor: 'none'` 不提前返回:没解析出颜色时描边颜色是 0,透明,等于不画。

### 还在队列里

`scaleCalcAlign`(雷达指示器与 `alignTicks`)→ 原始值通道 → tooltip 子行。旋转标签矩形的分解重组(连同 V8 的 `tan`)、title / legend 的布局合并视需要插进来。

## 82. Tier 1 第四十八批:`scaleCalcAlign`——雷达指示器与 `alignTicks`(2026-09-24)

上游有两处不自己 nice、而是把一根轴的刻度"对齐"到另一根轴上:雷达的每条指标轴对齐到一个 `[0, splitNumber]` 的哑刻度,笛卡尔上写了 `alignTicks: true` 的数值轴对齐到同方向的参考轴。port 两处都没有:雷达直接用原始范围、环按半径等分、标签用 `FormatFloat` 不带千分位;`alignTicks` 根本不读。

### 上游的做法(axisAlignTicks.ts)

- **参考轴的形状**:刻度数 `n`。一段时 `seg = 1`;两段且不等长时 `seg = 1`,短的那段按比例算成端部的分数段;三段以上 `t0 = (1 − (T0 − X0)/iv) % 1`、`t1` 对称,`seg = n − (t0?1:0) − (t1?1:0)`(X 是扩展到 nice 范围的刻度)。
- **目标的范围**先过 `ensureValidExtent`(平值:固定了 max 只向下开,否则两边各开一半;零 → `[0, 1]`;非有限 → `[0, 1]`)。对数目标在自己的指数空间里算。
- **两端都固定**:`iv = (max − min)/(seg + t0 + t1)`,精度 `getAcceptableTickPrecision([max, min], px, 0.5/seg)`(px 为 0 时是 0 而不是 NaN;跨度为 0 或非有限时是 NaN);nice 两端用**未取整**的 iv 算,之后才把 iv 按精度取整。
- **否则搜索**:起点 `niceMin(span/seg)`(10 的整数幂,`NICE_MODE_MIN`),对数轴是 `max(10^qE(span), 1)`;最多 50 轮,每轮不满足就 `increaseInterval`(首位数 1→2→3→5→10,0 当 1),对数轴乘 `max(base, 2)`;**第 50 轮失败后还会再加一次**,所以存下的步长比决定范围的那一步大一格。
  - min 固定:从 min 往上铺 `seg` 段,直到 max 够到数据;max 固定对称。
  - 都不固定:取数据里的整倍数,段数不够时把多出的段补在两边——含零(或对数轴)且一端是 0 时全补在另一端;否则奇数段按**上一轮**的 `min + max` 与数据中点比较决定多给哪边(第一轮是 NaN,比较为假)。
- **写回**:范围、步长、精度(不钳制,可以是 28)、`intervalCount = seg`、nice 范围。刻度严格走 `intervalCount` 段,最后一个刻度就是 nice 终点;步长为 0 时没有刻度。标签是 `getLabel`:按值自己的小数位,加千分位。
- **雷达**:哑刻度 `[0, n]`、步长 1,所以 `t0 = t1 = 0`、`seg = n`;`n = Math.round(max(splitNumber || 5, 1))`;范围来自原始规则(max>0 且 min 为假 → min=0 等),固定标志按下标保留(min > max 时只交换值);px 是 CSS 像素的半径差。环画在每条轴自己取整后的刻度坐标上:多边形取各条轴刻度数的最小值,圆形用第一条轴。
- **笛卡尔**:每个网格、每个方向,按下标**倒序**找参考轴——最后一个没要求对齐的数值轴(值轴或对数轴),都要求时取第一个要求的;写了 `interval` 的不对齐。先 nice 其余轴,再对齐。px 是**只按网格选项**算出的矩形宽高(在 outerBounds / containLabel 收缩之前)。

### port 以前

- 雷达:范围就是原始范围(40..90 画成 `[0, 90]`,上游 `[0, 100]`);平值在原始规则里两边各开一半,不看固定标志;环按半径等分、环上的值线性插值;标签 `FormatFloat('0.######')`,没有千分位;splitNumber 用 banker's 取整(2.5 → 2);半径差按设备像素。
- 笛卡尔:`alignTicks` 不读,每根轴自己 nice。
- 刻度:没有 `intervalCount` 分支;没有 `NICE_MODE_MIN`、`increaseInterval`、`getAcceptableTickPrecision`。

### 做法

- `Scale`:`TyRoundP`(精度可为 NaN 或大于 20)、`TyNiceMin`、`TyIncreaseInterval`、`TyAcceptableTickPrecision`、纯函数 `TyScaleCalcAlign`(输入输出记录,逐行照搬,在屏蔽浮点异常的外壳里算);`TTyIntervalScale.SetAligned`(范围、步长、精度、段数、nice 范围,段数用单独的"有"标志,NaN 精度也单独记)、`AlignTo`(读参考轴的步进空间刻度和扩展刻度,对数目标在指数空间里算、固定且没动的一端保留原值)、`StepTicks`;`StubTicks` 加 `intervalCount` 分支;`Niceify` 清掉对齐状态。
- `Radar`:原始范围函数多输出固定标志和是否含零,不再展开平值;`AlignAxis` 对齐到哑刻度,px 换算成逻辑像素;`RingCount`、`RingRadiusOf`(每条轴自己的刻度坐标)、`RingValue` 读对齐后的刻度;绘制逐条轴取环坐标;标签用 `TyScaleValueLabel`;splitNumber 用 `TyValidSplitNumber`(保留 1000 的上限)。
- `Series`:原始范围记录导出 `Incl0`;每个网格每个方向按上游规则选参考轴,先 nice 其余轴,再 `AlignTo`;px 取构建阶段已算好的选项矩形,按 PPI 换成逻辑像素。
- `AdvanceChart`:雷达走 `AlignAxis`;记下 `FLastPPI`;`RadarLayout` 供测试读取。

### 基准

- `tools/advchart-oracle/scale-align.js` → `advchart-scale-align.json`:111 例、258 条对齐轴(雷达 53 例,笛卡尔 57 例,1 例 dataZoom 只作单元层;其中 3 例是变异测试后补的判别用例)。生成器内嵌一份逐位验证过的配方,逐字段对拍;14 个判别守卫(新鲜居中、`log10`、banker's 取整、无 `intervalCount`、1-2-5 阶梯、`NICE_MODE_ROUND`、取整后的步长做 nice 端、交换固定标志、平值两边开、px 0 → NaN、存储时钳制精度、50 轮后不多加一次、最终 px、设备 px)各自至少改变一个具名用例。
- `test.advchart.scalealign`:
  - 单元层:全部 258 条对齐轴,把 input 喂给 `TyScaleCalcAlign`,逐位比较 t0、t1、段数、有效范围、范围、步长、精度、nice 范围、轮数与是否耗尽,再经 `SetAligned` 比较刻度和标签。约六千项。
  - 雷达端到端:真实渲染后逐条轴比较范围、步长、nice 范围、每个环的值和半径、环数。
  - 笛卡尔端到端:真实渲染后比较对齐轴的范围(对数轴比值域)、步长、nice 范围、步进空间的刻度。
  - 144 PPI、画布放大 1.5 倍的雷达,步长和范围与 96 PPI 相同;辅助函数的边界(`round(x, NaN)`、`increaseInterval(0)`)。
- 一个 FPC 陷阱在这里咬到:`0.5 / seg` 里实常量除以整数按 Single 算,0.1 的 Single 让 LOG10-BOUNDARY 的精度差一位,改成 `Double(0.5)`。

### 被推翻的旧测试

- `test.advchart.radar.pas`:平值 `[25, 75]` 是对齐之前的原始值,上游从不显示;改为原始规则原样返回平值,对齐后 scale:true 的 50/50 是 `[0, 100]`、两端都钉在 50 是 `[25, 50]`。原处有标注。

### 已知偏差

- dataZoom 驱动的对齐(两端都算固定)、轴断裂的回退、对齐轴上的 containShape 采用、`inverse` 的交互:不做(dataZoom 那例只在单元层比较)。
- 雷达半径为 0 时不画(上游算出精度 0 但什么也看不见)。
- splitNumber 上限 1000(上游无上限)。
- 雷达轴标签的首尾隐藏(`fixMinMaxLabelShow` / `hideOverlap`):不做。

### 变异测试

42 个。38 个被杀,4 个等价。

- 第一轮存活 11 个。补测试后杀掉 7 个,加上新写的"对齐后没有刻度的辐条按 splitNumber 算环数",共 8 个:
  - `TyRoundP` 精度为 NaN 时原样返回、`increaseInterval(0)` 是 1:辅助函数的边界单元测试;
  - 雷达按设备像素算半径:同一雷达在 144 PPI、画布放大 1.5 倍时,步长和范围与 96 PPI 一样;
  - 对齐后没有刻度时的环数:TINY 例原先因为上游环数是 −1 被跳过,改为照样比较(并据此改了 `RingCount`:对齐过的辐条没有刻度就是没有环);
  - `scale: true` 不含零(雷达、笛卡尔各一):补了数据恰好碰到 0 的基准用例,含零会把多出的一段全补在上面;
  - 对数目标固定端保留原值:补了对数轴固定在 3 的基准用例。
- **等价的 4 个**:
  - 存储时把精度钳到 20:取整时本来就钳制,可见结果不变;
  - 参考轴不足两个刻度照样对齐:上游保证参考轴至少两个刻度,这个分支到不了;
  - 用最终绘图矩形代替选项矩形算 px:对齐时绘图矩形还没收缩,两者相同(变异本身不成立;OB-74 例钉的是选项矩形算出的精度);
  - 圆形雷达取所有辐条里最少的环数:所有辐条的刻度数都等于 splitNumber+1(或都为空),两种取法相同。

### 还在队列里

原始值通道 → tooltip 子行。旋转标签矩形的分解重组(连同 V8 的 `tan`)、title / legend 的布局合并视需要插进来。

## 83. Tier 1 第四十九批:原始值通道(2026-09-24)

标签和 tooltip 打印的是数据**写成的样子**,不是解析后的数。`'12.50'` 的标签是 `12.50`,`true` 是 `true`,`{c}` 是整个原始值(数组用逗号连,`null`、`undefined`、`[object Object]` 照印)。port 的 store 只存 Double,所以这些全都印成了解析后的数:`12.5`、`1`,`{c}` 只取一列。

### 上游的做法

- **原始项**(`getRawValue` / `getDataItemValue`):对象取 `value`,`{value: null}` 是 null,没有 `value` 的对象和 JSON `null` 是 undefined;标量回答任何维度;数组、数据集的行按位置回答。K 线和箱线图在类目轴上会把行号插到每项前面(`whiskerBoxCommon` 的 `unshift`)。
- **数据集**:列布局的一行是整行;行布局按所有行重建一条记录;objectRows 是对象,只有源维度能取到;keyedColumns 是各列的第 i 格。
- **`{@key}`**(`getDimensionIndex`):`[n]` 按 `Number` 读成位置,声明过的维度名取它的位置,看起来像数字的 key 也是位置;名字表是上游自己的——系列写了 `dimensions` 就用它,否则坐标名放在各自 encode 的位置上,其余位置依次叫 `value`、`value0`、`value1`……;数据集用表头。
- **tooltip 单元格**(`makeValueReadable`):ordinal 原样印文字(空白是 `-`)、有限数不加千分位;其余先 `numericToNumber`——`parseFloat` 与 `Number` 一致才算数,且不是从第二个字符之后带 `x` 的串读出的 0——有限就 `addCommas`,否则印文字、布尔词或 `-`。
- **tooltip 模板的 `{c}`**:`String(raw)`,null 和 undefined 是空串。

### port 以前

- 默认标签、`{c}`、`{@}`、tooltip 单元格和模板的 `{c}` 全部从 Double 来。
- `{@}` 按 store 的坐标名找列:数据集表头名找不到,`[n]` 和数字 key 不认,标量不回答别的维度。
- 原始数据上的 `encode` 不读(`encode: {x: 1, y: 0}` 的散点画在错的位置)。
- 全是 null 的系列在类目轴上没有行号,轴 tooltip 里整行消失。
- keyedColumns 数据集不读,整张图是空的。

### 做法

- `Data`:
  - 原始项旁表 `TTyRawItem`(`rshNone` 表示没存,消费者回到 Double 路径;`rshAbsent` / `rshNull` / `rshScalar` / `rshArray` / `rshObject`),和名字表、维度位置表、`RawPosOf`、`RawCell`。
  - JS 数值:`TyJsTrim`(JS 的空白比 `Trim` 宽:NBSP、U+FEFF、Zs 各字符、行分隔符)、`TyJsToNumber`、`TyJsParseFloat`、`TyJsNumericToNumber`、`TyJsValueText`、`TyRawItemText`、`TyReadableCell`。
- `Scale`:`TyJsDecimalToDouble`,大整数实现的正确舍入(含次正规数)。**FPC 的 `TryStrToFloat` 不是正确舍入的**:`2.4703282292062328e-324` 刚过最小次正规数的一半,应入到 `5e-324`,它给 0。短数字(≤15 位、10 的指数在 ±22 内)走一次 IEEE 运算。
- `Builder`:原始数据按 `getDataItemValue` 填原始项(不用 `UnwrapItem`),K 线/箱线图的行号前插;名字表和位置表;数据集按格式填;全 null 的系列用行号。
- `Dataset`:keyedColumns 可读——维度是声明的或全部 key,行数是**第一个**维度那列的长度。
- `AdvanceChart`:原始数据上的 `encode` 决定各坐标列读第几个元素(多值系列除外);tooltip 参数带原始项和各值的原始格与维度类型。
- `LabelOpt`、`Handlers`:默认标签、`{c}`、`{@}`、模板 `{c}` 读原始项。

### 基准

- 新的 `tools/advchart-oracle/raw-value.js` → `advchart-raw-value.json`:633 条字符串(133 条手挑,500 条种子随机),调用真实的 `echarts.number.numericToNumber` 和 `echarts.format.addCommas`,记下数的位模式和单元格文字。`test.advchart.rawvalue` 逐位比较;另有 2 万个随机 Double(含次正规数和两端)的 `Number(String(x)) = x` 往返检验,以及 `Number` / `parseFloat` 分开的边界、原始项字符串化、key 解析、按维度类型的单元格。
- `series-text.js` 解除 20 条 deferred,新增 N1–N8 和"数据集第二个系列读第三列";N9(`'   '`、`'0x10'` 的解析)标 deferred 等 D9。现在标签 75 例、tooltip 74 例、仪表盘 14 例,另有 15 条 deferred(encode.label / defaultedLabel、tooltip 子行、自动系列名、仪表盘 `splitNumber: 0`、D9)。

### 被推翻的旧测试

- `test.advchart.dataset.pas`:"keyedColumns 暂时没有读取器"改为可读,并钉住行数取第一列、短列越界是空。原处有标注。

### 已知偏差

- **D9,数据解析与上游不一致**:`'   '` 上游是 0、`'0x10'` 是 16、`'Infinity'` 是 ∞,port 的 store 仍是 NaN;`test.advchart.data.pas` 钉的 `'   '` → NaN 是错的。这会动几何和范围,单独一批。
  **[第五十三批已做,见 §87。]**
- 时间维的 tooltip 单元格(上游按**本地时间**格式化成 `yyyy-MM-dd HH:mm:ss`):仍走 Double。
- 函数格式化器、`valueFormatter`、`@Name` 处理器拿到的仍是 Double;`order` 排序仍按 Double。
- JSON 表达不了的:NaN、空洞、显式 undefined、Date、TypedArray;数组里嵌套的数组或对象记为空格。

### 变异测试

63 个。60 个被杀,3 个等价或不可观察。

- 第一轮存活 8 个。补测试后杀掉 5 个:
  - ordinal 单元格(加千分位、当数读):`TyReadableCell` 按维度类型的单元测试;
  - 数据集列位置、默认标签取维度下标、tooltip 单元格取维度下标:基准里加"第二个系列读第三列"(store 第 2 列,表第 3 列),默认标签和单元格都要读对列。
- 另有一个变异体原先编不过(删掉了 for 循环的唯一语句),改成 `if False` 后被杀。
- **等价或不可观察的 3 个**:
  - `x` 守卫从第 2 个字符改成第 1 个:首字符是 `x` 的串 `parseFloat` 已是 NaN,到不了守卫;
  - `parseFloat` 连尾部空白一起修剪:前缀扫描本来不读尾部;
  - 时间维也走原始格:两种写法都不是上游的本地时间格式,属于上面的已知偏差。

### 还在队列里

tooltip 子行 → 旋转标签矩形的分解重组(连同 V8 的 `tan`)、title / legend 的布局合并、D9 数据解析对齐。

## 84. Tier 1 第五十批:tooltip 子行、encode.tooltip / encode.label、默认维度、自动系列名(2026-09-24)

上游的 tooltip 不是"一个数值格":一个系列可以有好几行,标签也不总是值轴那一列。port 以前一律取值轴那列、多个值用两个空格连成一行,K 线四个数挤在一行里,雷达只显示最后一个指标。

### 上游的做法

- **哪些维度进 tooltip**(`dimensionHelper.ts`):`encode.tooltip` 非空就用它;否则类型声明的 tooltip 维(K 线的 open/close/lowest/highest、箱线图的 min…max);再否则跟标签走。
- **哪些维度进标签**:`encode.label` 非空就用它;否则**按位置最后一个**不是类目也不是时间的坐标维,至多一个。类目-类目、时间-类目、时间-时间的散点没有默认标签。多个维度各自 `String()` 后用**一个**空格连,缺值是空串。
- **三个分支**(`seriesFormatTooltip.ts`):
  - 多于一个 tooltip 维,或没有 tooltip 维而原始值是数组:逐个格子;原始项的**任何一个位置**(显示与否、短项没有的不算)带 `displayName` 就改成子行——物品行的值是空串(有值格、只是空),下面每维一行小圆点,名字是 displayName,没有就是 `-`;否则两个空格连成一行。
  - 恰好一个:那一格。
  - 没有 tooltip 维、原始值也不是数组:值本身,不带类型。
- **displayName** 只来自**声明**:系列 `dimensions`(名字即显示名,可另写 `displayName`)、数据集表头或 `dataset.dimensions`、类型注册的维度名(K 线、箱线图,行号前插时那一维叫 `base`)。生成的 `value`/`value0`、坐标名都不算。
- **没声明类型的额外维度**按 `guessOrdinal` 猜:前五项里第一个能说明问题的值是非数字文本(`'-'` 不算)就是类目;原始数据遇到非数组项就停,答"不是类目"。类目格原样印、不加千分位。
- **时间格**:`yyyy-MM-dd HH:mm:ss`,`useUTC` 时按 UTC;不带时区的文本按本地时间解析。
- **给出 encode 时没写的坐标**按坐标顺序取第一个没被占的维度;写成 `-1` 的不映射,也不占位。
- **轴触发**:每个系列是一个无头 section,装着它的行和子行;`order` 排的是这些 section,排序键是系列的**第一个内联原始值**(有子行的系列没有键)。
- **排序比较器**(`SortOrderComparator`):能读成数的在前(Infinity 算);其余不可比,排到尾;但两个都是文本时按文本比,文本对非文本时文本算 0——所以文本总在数和其余之间。
- **雷达**自己的 tooltip:section 以数据项名为头(空则用系列的模型名,再空则 `-`,从不隐藏),每个指标一行小圆点、值是解析后的数;物品触发下 `order` 也生效。
- **系列名两种**:显示名(没写就是空,决定头、轴行名、图例)和模型名(没写是 `series\0<序号>`,写了 `''` 就是 `''`),`{a}`、处理器的 `seriesName` 用模型名。

### port 以前

- tooltip 值取值轴那列;多值两空格一行;没有 `ttmSubItem`;雷达走通用路径。
- 标签取值轴那列:类目-类目的散点标出类目、时间-类目标出日期。
- `encode.tooltip` / `encode.label` 不读;`encode` 的列表只取第一个;`displayName` 不读。
- 数据集给了部分 encode 时,没写的坐标整列为空(`encode: {tooltip: [2]}` 整张图没东西)。
- 排序键是 Double:文本全算 NaN,`'abc'`、`'abd'` 按原顺序;有子行的 K 线按 open 排。
- 未命名系列的 `{a}` 是空。

### 做法

- `Tooltip`:块的排序键改成原始格 `SortCell`(`SortParam` 保留为数值写法);`TyTooltipCompare` 照搬比较器。
- `Data`:每个原始位置的信息表(显示名、声明类型)、`RawPosType`(读它的列的类型 > 声明 > 猜测 > 数)、`GuessRawOrdinals`、tooltip / 标签位置表、`RawWidth`、`DimCoord`。
- `Dataset`:源维度带 `DisplayName`;encode 记下哪些坐标写过、`tooltip` / `label` 列表全部解析;`TyEncodeFillUnclaimed`;`TySeriesDimsSource`(原始数据上 encode 的名字按系列 `dimensions` 解析)。
- `Builder`:声明维度填名字、显示名、类型;K 线类型维度名作显示名,前插的行号叫 `base`;填完猜类目。
- `AdvanceChart`:
  - `SeriesDataEncode` 读系列 `dimensions` 解析名字,并补位没写的坐标;数据集路径同样补位。
  - `ResolveTextDims` 按上游规则定标签和 tooltip 位置。
  - `TipCellsOf` 算三个分支、子行、排序键,时间格按 `useUTC` 格式化;`TooltipContent`、`AxisTooltipContent` 按上游的块树搭;`RadarTooltip`。
  - `SeriesModelName`:`{a}`(标签、饼、漏斗、graph)和参数的 `SeriesName` 用它;头和轴行名仍用显示名。
- `LabelOpt`:store 有标签位置表时按位置取格、一个空格连。
- `Measure` / `Render`:`TyInkText` 在度量和绘制时去掉 NUL。

### 基准

- `series-text.js` 解除 12 条 deferred,新增 N1–N20 及变异测试后补的 8 条判别用例、10 个抽查。现在标签 90 例、tooltip 117 例、仪表盘 14 例;还 deferred 的只剩 3 条(两条 D9 解析、仪表盘 `splitNumber: 0`)。时间用例都写 `useUTC: true`。
- **fpjson 会吞掉 `\u0000`**(扫描器把它当代理对的前半),自动名的 NUL 读不进来。运行器解析前把 `\u0000` 换成 `\u0001`,port 的输出也把 NUL 映射成它再比较,NUL 仍被逐字比较。
- `test.advchart.subrows`:未命名系列的 `[{a}]` 标签和名叫 `series0` 的系列,标签框一样宽、渲染逐像素相同。
- `test.advchart.dataset`:`TyEncodeFillUnclaimed` 的单元测试(写成 `-1` 的不补、不占位)。

### 被推翻的旧测试和旧说法

- `test.advchart.axispointer.pas`:轴触发的行原来直接在轴 section 下,现在每个系列多一层无头 section;测试改为多下钻一层,并断言那一层是无头 section。原处有标注。
- `AdvanceChart.pas` 里 `ValuesText` 的注释说"K 线总走这一支":上游 K 线的维度有显示名,走子行。原处有标注。
- 审计里"基轴的 `tooltip: false` 要实现"一条:上游用例表明,`encode.tooltip` 点名 base 时它照样显示(encode 先写进 otherDims,类型的默认值不覆盖),而不点名时 base 根本进不了 tooltip 维——这个标志永远藏不掉任何东西。实现过又删了,见变异测试。

### 已知偏差

- D9 解析对齐(`'   '`、`'0x10'`、`'Infinity'`):单独一批。
- 仪表盘 `splitNumber: 0`:有意保留。
- 不带时区的日期文本按**本地时间**解析(上游也是),`useUTC` 只管输出;所以这类用例依赖机器时区,fixture 在 UTC+8 下生成。
- 极坐标、热力图的默认维度(port 没有这两种);`encode.y` 等列表只用第一个;`tooltip.valueFormatter`;箱线图的渲染和物品 tooltip。
- 两层带头的轴 section(gap level 2)没有用例覆盖,行为没动。

### 变异测试

50 个,全部被杀。

- 第一轮存活 9 个,逐个补上:
  - 文本对空值/布尔的排序、`'-'` 不说明类型、原始数据的标量首项终止猜测、原始数据的部分 encode 补位、声明的类目类型、类目-类目里比第 0 项长的项、时间-时间的标量项走无类型分支:各补一条上游用例;
  - 写成 `-1` 的坐标不补位:`TyEncodeFillUnclaimed` 单元测试;
  - K 线行号的 `tooltip: false`:补的上游用例反而表明 `encode.tooltip` 点名时 base 照样显示,且不点名时 base 进不了 tooltip 维——整个机制不可达,连同它的 3 个变异体一起删掉,改为给行号维起名 `base`(新变异体被杀)。

### 还在队列里

遗留:旋转标签矩形的分解重组(连同 V8 的 `tan`)、title / legend 的布局合并、D9 数据解析对齐。

## 85. Tier 1 第五十一批:旋转标签矩阵的分解重组与 V8 的 `tan`(2026-09-24)

上游的轴标签是轴组(Group)的子元素:组矩阵乘标签自身的平移和旋转,然后标签被取出来、`decomposeTransform` 成属性、再 `getLocalTransform` 重组。重组出的矩阵和"直接按请求角旋转"差几个 ulp,标签框、重叠框、轴名称的占用区都用它。port 以前直接用请求角。

### 上游的做法

- 标签局部旋转 `lr = remRadian(req − 轴旋转)`,JS 的 `%` 两次;局部矩阵 `local(c, t, lr)`;任何一项超过 5e-5 才有局部变换(`needLocalTransform`),否则就是组矩阵本身。
- 分解(无父、原点 0,顺序照抄):`sx² = m0² + m1²`,`sy² = m2² + m3²`,`r = atan2(m1, m0)`,`sh = π/2 + r − atan2(m3, m2)`,`sy = √sy² · cos sh`,`sx = √sx²`;属性 `rotation = −r`,`skewX = sh`,平移取 m4、m5。
- 重组:`[sx, 0·sx, tan(sh)·sy, sy, 0, 0]`,旋转非零才转,再加平移。`sh` 约为 2π 时 `tan` 要 V8 的:FPC `Tan(2π)` 是 `BCB1A60000000000`,V8 是 `BCB1A62633145C07`。

### port 以前

- `LabelBoxes` 用 `TyMatLocal(X, Y, 请求角)`;没有 needLocal 门;锚点的 `RemRadian` 用 Floor 写法。
- `JsMath` 没有 `tan`。
- 测试层面的容差:gridbounds、labelthinning 的绘图区和刻度、axisnames 移动过的名称与名称框、coordaffine 按 1e-9 比请求角——最后这条在 270°、181° 其实会差一整圈,只是没有用例。

### 做法

- `JsMath`:`TyJsTan`,逐句转写 V8 `ieee754.cc` 的 `tan` / `__kernel_tan`(系数写成位模式),归约沿用 `RemPio2`。
- `Layout`:`TyMatDecompose`、`TyMatRecompose`、`TyNeedLocal`;标签位置记录加 `M`、`HasM`、`DecRotation`(零值是"手搭的规格,用旧路径");`byFrame` 循环里按上游算出 M、分解重组,锚点取乘积的平移;`LabelBoxes` 有 M 就用 M;`AnchorsFor` 改用 `TyRemRadian`,删掉 Floor 版。

### 基准

- `js-math.js` 加独立的 `tan` 数组:23,204 行(原有参数、fdlibm 的分支点、2π 与邻位、±π/2 邻位、kπ、0.6744 附近、2^-28、观测到的斜切值,加上核区间和整圈的种子随机扫描);`TestTanIsV8sToTheBit` 逐位比较,另钉 FPC `Tan(2π)` 不等于 V8。
- `coord-affine.js`:
  - 新增 `labelMatrixSweep`:横轴/纵轴 × 顶部与否 × −360°…360° 每半度,加三个特殊角和 5e-5 门的一行,共 5,777 行,由真 zrender 元素生成;`TestTheLabelMatrixIsUpstreams` 用 port 的原语逐位比较矩阵 2×2、分解后的旋转角和斜切。
  - 新增 8 个图表用例(30°、−90°、270°、181°、−135°、y 轴 −90°、顶部离零点 90°、门);每个标签比较 6 个矩阵分量和分解后的旋转角,都逐位。
- 容差全部去掉:gridbounds 改读 `PlotXYWH` 后 74/74 逐位;labelthinning 的绘图区、刻度、分割线、分割区域全部逐位,且要求每个用例的绘图区都逐位;axisnames 的名称旋转、移动后的锚点、名称框、网格矩形逐位。

### 被推翻的旧测试

- `test.advchart.coordaffine.pas`:轴的请求角按 1e-9 比上游的 `labelRotation`——那是分解后的角,270° 时差 2π。改为逐标签逐位比较分解后的角。
- `test.advchart.gridbounds.pas`、`labelthinning.pas`、`axisnames.pas` 的容差和"矩阵舍入不同"的说明;原处都有标注。

### 已知偏差

- 画标签时仍用请求角(差 ≤ 1.1e-15 rad,亚像素)。
- 分解后各属性都约为 0 时 zrender 重组为单位阵(标签锚在画布原点 5e-5 以内):不做。
- 老式 containLabel 的旋转路径不经过这个矩阵(修正测试后已逐位)。

### 变异测试

16 个。12 个被杀,4 个等价:

- 锚点对齐用的 `remRadian` 换回 Floor:两种写法最多差 1 ulp(2π),落不进对齐判定的 1e-4 分支边界;
- 旋转为 ±0 时照样调用旋转:sin 0 = 0、cos 0 = 1,结果逐位相同;
- 锚点取不带局部旋转的乘积:只有 0 < |c|、|t| ≤ 5e-5 时不同,没有夹具能到;
- `tan` 核的一个系数改末位:那一项的变化约 1e-22,远低于结果的 ulp,两万多个参数都看不出。同一系数改在 2^-32 处的变异体被杀,说明系数确实接上了。

### 还在队列里

title / legend 的 mergeLayoutParam(第五十二批,审计已完成)→ D9 数据解析对齐。

## 86. Tier 1 第五十二批:title / legend 的 mergeLayoutParam 与照抄的 getLayoutRect(2026-09-24)

标题和图例的位置,上游是"选项并进默认值,再按原始值 getLayoutRect"。port 以前各边单独读、共用的宽松解析器求解:默认的 `left: 'center'`、标题的 `top: 15`、图例的 `bottom: 15` 在用户写了对边之后仍然留着,于是 `right: 10` 不动、`bottom: 10` 不动。

### 上游的做法

- **合并**(`mergeLayoutParam`,title 和 legend 都走 `ignoreSize` 分支,滚动图例也是):选项**自己的** left(top)有值——不是 null、不是 `'auto'`——就把 right(bottom)置 null;否则自己的 right(bottom)有值就把 left(top)置 null;宽高不动。判断的是用户写的原值,在并进默认值之前;显式的 null 会留下来。
- **解析**(`parsePositionOption`):四个词精确匹配,去掉 JS 空白后以 `%` 结尾才是百分比,其余字符串 `parseFloat`,null 与未写是 NaN,布尔是 0/1。所以 `'centre'`、`' center'`、`'Center'` 都是读不出的 NaN,`'10px'` 是 10,`true` 是 1。
- **求解**(`getLayoutRect`):NaN 运算按上游顺序;关键字开关看合并后的 `left || right`、`top || bottom`;宽高的兜底;最后 `BoundingRect` 遇负宽翻到另一边。
- **图例**解两次:第一次用选项自己的盒子(关键字照样生效)求折行空间;第二次用测得的大小求位置,测量值胜过写的宽高。`itemAlign` 看合并后的 `left === 'right'`。
- **标题**:文字块大小作宽高;自动对齐按那两个词移位;背景是组的位置加上组内盒子减内边距。

### port 以前

- 不合并;`EdgeIn` 把 `'auto'`、读不出的值、布尔、带空格的词都当成默认值;`'centre'` 算关键字。
- 关键字在折行求解之前就把盒子改写了,竖向 `bottom: 'bottom'` 的折行空间是整个高度(上游只剩 10)。
- 共用求解器的运算顺序不同,只精确到两位小数;负宽度收成 0 而不是翻转。
- `TestARightEdgeAloneDoesNotMoveTheLegend` 钉的正是这个 bug。

### 做法

- `Layout`:原始盒值 `TTyBoxRaw` / `TTyRawBox`(未写、null、数、字符串、布尔、其他),`TyMergeBoxIgnoreSize`、`TyBoxRawPos` / `TyBoxRawResolve`(parsePositionOption)、`TyBoxWord`(`a || b` 取字符串)、`TyGetLayoutRect`(逐句,含 margin 与翻转)。
- `Title`:规格存合并后的原始盒子和两个词;删掉 `ApplyEdgeWords`、`EdgeIn`;布局走 `TyGetLayoutRect`;`textAlign` 不再认 `'centre'`;背景按上游顺序算出 x、y、宽、高(另存 `FrameX/Y/W/H`)。
- `Legend`:同样的规格;公开 `TyLegendWrapRect`、`TyLegendPlaceRect` 两次求解,由 `TyLayoutLegend` 调用;折行上限直接用求出的宽高;`itemAlign` 读合并后的 left。

### 基准

- 新的 `tools/advchart-oracle/box-merge.js` → `advchart-box-merge.json`,400 × 300:24 个标题、16 个图例、1 个滚动图例;记下合并后的每个键(未写 / null / `'auto'` / 值)、按基数解析的结果、两个词、标题的测量、组位置、对齐与背景,图例每个名字的测量、折行空间、内容矩形、放置矩形、列数行数和 itemAlign。生成器内嵌逐句的 JS 副本逐位自查;18 个判别守卫,每个对应一个变异体。
- `test.advchart.boxmerge`:合并结果与解析逐位;标题用夹具自己的宽高做查表测量器,组位置、对齐、背景逐位(竖直居中/底部只比 x 与宽,见偏差);图例折行空间与放置矩形逐位;接线测试走完整的 `TyLayoutLegend`,列数、行数和 itemAlign 与上游一致。

### 被推翻的旧测试和旧说法

- `test.advchart.legend.pas` `TestARightEdgeAloneDoesNotMoveTheLegend` → `TestARightEdgeAloneMovesTheLegend`:右边缘距右 10 减内边距,即 385 / 315。
- `test.advchart.title.pas`:"`right: 0` 单独不动标题"的说明错,补钉 `right: 10` 会移动;"left 先读"的理由改为合并后不可观察;默认规格的断言改成原始盒子。
- 设计日志里 §42 的 `right: 10` 不动、§45 的读序理由、§64 的"`centre` 对别的组件无害"、§76 与 §77 的"只做了 grid",原处都有标注。

### 已知偏差

- 标题 `top: 'middle'` / `'bottom'`:上游每行文字各自竖直对齐,port 整块对齐(背景的 y 与高度不同)。
- 选项根上的 left/top 通过 `getShallow` 漏进组件:不做(画廊里没有)。
- 第二次 `setOption` 的合并、滚动图例的翻页:port 没有这些路径。
- grid 等其他盒子仍用共用求解器。

### 变异测试

21 个。20 个被杀,1 个等价:`x || 0` 把 −0 当成 −0 返回——坐标是 `0 + left + margin`,`0 + (−0)` 就是 +0,逐位相同。

第一轮存活 5 个,补了 4 个上游用例:竖向 `right: 'right'`(itemAlign 读合并后的 left 而不是开关词)、`top: 'center'`、`right: '20% '`(先去空白再判百分号)、一个恰好让背景 x 的两种运算顺序舍入不同的标题("Budget",宽 57.42)。

### 还在队列里

D9 数据解析对齐(`'   '` → 0、`'0x10'` → 16、`'Infinity'` → ∞)。这是计划里的最后一项。

## 87. Tier 1 第五十三批:数据解析对齐上游(D9)(2026-09-24)

store 里的一个格子,上游是 `parseDataValue`:除了恰好的空串,文字都是 `Number()`。port 以前是 `Trim` + `TryStrToFloat`,于是 `'   '`、`'0x10'`、`'Infinity'` 是 NaN,`'Inf'` 反而是无穷——四个都和上游反着。时间格还会先修剪、拒绝越界字段,布尔也不认。

### 上游的做法

- **数值维**:`''` 是 NaN,其余文字 `Number()`——空白是 0,`0x/0o/0b` 是整数,`Infinity` 是无穷,`Inf`、`5e+`、`12px` 是 NaN;数照原样(±∞、−0 保留),布尔 1/0。
- **时间维**:数照原样;布尔是 `new Date(Math.round(true))`,即 1 和 0;文字走 `parseDate`:`TIME_REG` 锚定、不修剪;字段交给 `Date.UTC` / `new Date`——月 13 是下一年一月,日 0 当 1,24 点进到次日,两位年份算 19xx;小数取 `substring(0, 3)`,所以 `'.5'` 是 5 毫秒;时区只读 `slice(0, 3)`,分钟被丢掉;小写 `z` 和纯日期后的 `Z` 都不认。
- **范围**:store 把无穷当端点留着;是**轴的并集**(`unionExtentFromExtent`)丢掉端点不有限的整个系列——所以一个 `'Infinity'` 只让没有别的系列的轴变空白。对数轴的过滤条件 `0 < v < Infinity` 另外丢掉 +∞。
- **下游**:无穷的柱子裁剪成 NaN 矩形,不画;饼图的角度、漏斗的份额算成 NaN,JavaScript 照常往下走。

### port 以前

- 上面的解析全是反的;时间格先 `Trim`、越界字段拒绝、`'.5'` 是半秒、时区读到分钟;布尔在时间维是 NaN。
- 范围把无穷在两处都挡掉,轴的并集不看端点是否有限。
- 饼图、漏斗、柱子遇到无穷在 FPC 里会抛 `EInvalidOp`。

### 做法

- `Data`:`TyParseNumberText`(`''` 是 NaN,否则 `TyJsToNumber`),删掉 `TextToNumber` 和 `FixedFloatSettings`;时间维布尔取 0/1;`TyParseDateMs` 按 `TIME_REG` 逐个 token 扫描、按 `MakeDay` 进位(`DaysFromCivil` 走前推格里历),不修剪;`NoteValue` 与扫描只跳过 NaN,`defPositive` 另跳过 +∞。
- `Series`:轴并集只收两端都有限、`lo ≤ hi` 的系列范围。
- `Pie`、`Funnel`:布局与份额在屏蔽浮点异常的外壳里算;漏斗范围只跳过 NaN(无穷的那一带占满宽度,其余宽度为 0)。
- `Marks`:无穷的柱子布局不画;堆叠在无穷上的无穷(`Inf − Inf`)是 NaN 地板,不画。
- `Graph`:边的 `value` 用同一个解析。

### 基准

- 新的 `tools/advchart-oracle/parse-value.js` → `advchart-parse-value.json`:713 条(213 条手挑,500 条种子随机),从上游**真实 store** 读数值维(柱子的 y)和时间维(时间轴上折线的 x,`useUTC: true`,本地时区的输入不记);`test.advchart.parsevalue` 逐位比较。
- `bar-geometry.js`、`value-axis.js` 各加 G1–G8(空白与十六进制、单系列无穷、多系列里的无穷系列、写了 min/max、对数轴、两种堆叠顺序)。
- `series-text.js` 解除最后两条 D9 的 deferred。
- 单元测试:饼图 `[Infinity, 5]` 不抛异常、角度和份额是 NaN/0;`['   ', '0x10', 5]` 的份额 0/76.19/23.81;漏斗 `[Infinity, 5, 3]` 的份额与带宽;graph 边值。

### 被推翻的旧测试

- `test.advchart.data.pas`:
  - `'   '` → NaN 改为 0;
  - 时间维布尔 NaN 改为 1/0;
  - `'.5'` 是 500 毫秒改为 5;
  - "拒绝不可能的字段"改为按 `Date.UTC` 进位(`TestTimeCarriesOverLikeDateUTC`);
  - "范围忽略无穷"改为范围保留无穷、对数轴丢掉(`TestExtentKeepsInfinityForTheAxisToDrop`)。
  - 原处都有标注。`TyParseDateMs` 头注释里"越界字段拒绝"的理由也就地标了推翻。

### 已知偏差

- 历史时区(V8 对 1000 年这类日期用当地平太阳时,差 343 秒):port 用今天的偏移。
- 坐标系之外、声明为 `int` 的维度(上游 Int32Array):port 不从选项建 int 列。
- 按名字选编码的三值判断(Not / Might / Must):已有偏差,和 D9 无关,另立一项。
- 时间维里数值 ±∞ 仍是 NaN(上游保留),序数维里非字符串的下标。

### 变异测试

23 个。22 个被杀;1 个不可达,连同代码删掉:`TimeClip`——四位年份加两位字段最多到一万年出头,远不到 ±8.64e15 毫秒。另有一个变异体原先编不过,改写后被杀。

### 队列

计划里的任务到这里全部完成。

## 88. Tier 1 第五十四批:visualMap 编码(B1)(2026-09-27)

计划队列清空后按画廊缺口重数,visualMap 34 个文件、排第一(toolbox 39 多是装饰,不挡渲染)。整个系列分四批:B1 模型与连续映射的编码,B2 连续型组件的静态视图,B3 其余通道与逐数据项的系列,B4 分段型。本批是 B1,组件本身还不画。

以前 port 里没有任何地方读 `visualMap`:没写 `type` 的会被诊断成"没有类型",子树不校验;颜色全靠 visualMap 的图(`line-gradient`、`dataset-encode0` 的柱子)画成一个系列色,诊断却说一切正常。

### 上游的做法

- **子类型**:没写 `type` 时,`!categories && (!(pieces ? pieces.length > 0 : splitNumber > 0) || calculable)` 是 continuous,否则 piecewise。按 JavaScript 的真值算:`categories: []` 是 piecewise,`pieces: []` 不是。
- **模型**:extent 是 `asc([min ?? 0, max ?? 200])`;range 没写就是 extent,写了先升序、再夹进 extent。`unboundedRange` 默认 true,这时默认 range 下超出 extent 的值、NaN 都算 inRange。
- **补全**:`target` 和选项自己的 `inRange`/`outOfRange` **逐键**合并,不覆盖——target 已有的键在前,缺的键**追加在后**,所以键的顺序也就是之后施加的顺序。ec2 的 `color`(高到低)在没有 inRange 时反转成 inRange;再没有就用根上的 `gradientColor`。`inRange: {color: null}` 不补,颜色是 undefined。没有 outOfRange 时按 inRange 的键依次补"失效值",颜色旁边再补 `opacity: [0, 0]`。
- **施加顺序**:`prepareVisualTypes` 用的比较函数不是全序,结果取决于 V8 的排序。n < 64 时 V8 是一段 run(降序就反转)再二分插入。`[color, opacity]` 排成 `[opacity, color]`,`[color, opacity, colorHue]` 排成 `[colorHue, opacity, color]`——色相先上、再被颜色盖掉。
- **映射**:值先 `linearMap(v, extent, [0, 1], clamp)`,NaN 一路是 NaN;颜色用 zrender 的 `fastLerp`:0..1 之外(含 NaN)是 undefined,通道 `Math.round`,**alpha 不取整**;数值通道是 `linearMap(n, [0, 1], 值对, clamp)`,单个值补成一对(颜色和符号除外)。
- **优先级**:系列样式(2000)→ 各 visualMap 按组件顺序(4000,数据项写了 `visualMap: false` 就跳过)→ 数据项自己的 itemStyle(4500)。所以数据项的颜色赢,visualMap 的 opacity **替换**系列的。
- **visualMeta**:取值 `e0` 起每次**累加** `(e1 − e0) / 200`,`i ≤ 200 && v < e1`,最后补 `e1`;range 内外两组合并,颜色从系列色出发、opacity 变成颜色的 alpha。
- **折线渐变**(`getVisualGradient`):取最后一个维度落在 x/y 上的 visualMeta,值换成画布坐标,首大于尾就连 outerColors 一起反转;按**画布**宽高裁剪(切点插值颜色);两端各外扩 10px;offset 按跨度归一,两头补 outerColors;global 渐变。`lineStyle.color` 写了线不用它,`areaStyle.color` 写了面积不用它。
- **默认维度**:最后一个不是计算列的维度——横向柱是 y 的类目序号,堆叠线是原始 y 不是累加值,散点 `[x, y, v]` 是第三列,dataset 是最后一列。

### port 以前

- 什么都不读;没写类型的 visualMap 报"没有类型"。
- 颜色解析用 FPC 的银行家舍入:`rgb(30%,0,0)` 是 76(上游 77),alpha 解析时就量化成 8 位。

### 做法

- 新单元 `VisualMap`:`TTyVisualColor`(zrender 的四个 double 加 undefined)、`fastLerp`、`modifyHSL`/`modifyAlpha`、JS 语义的 `linearMap`(NaN 直通)、照抄 V8 的 `TyPrepareVisualTypes`、模型读取与补全(在 JSON 副本上做逐键合并)、值状态、施加、取值(店里有这一列就读店,否则按原始格子解析)、visualMeta、折线渐变。所有可能碰 NaN 的比较都走 JavaScript 语义的 `Lt/Le/Gt/Ge`——FPC 的比较遇 NaN 会抛异常。
- `Color`:新增 `TyTryParseCssRgba`,把原来的解析改成它加打包;通道和 alpha 打包都用 `Math.round`;`rgba(r,g,b)` 三参数按上游是 `Number()`。
- `Complete`/`Diagnose`:`TyOptDefaultSubType`,没写类型的 visualMap 按默认子类型校验,也不再报"没有类型"。
- 控件:`SolveVisualMaps` 在系列配色之后、堆叠之前(默认维度要排除计算列);每个系列每行一条视觉记录。默认色带取主题 accent(`TyAdvChartSeries1`)——上游取主题第一色,这里的主题就是皮肤;根上写了 `gradientColor` 就用它。
- `Marks`:`RowVisual` 先施加视觉行、再让数据项的 `itemStyle.color` 覆盖;行 opacity 替换系列 alpha;映射出的颜色清掉系列渐变;散点取整行而不只是填充色。折线的线与面积在没写自己颜色时用 visualMeta 的渐变或单色。
- tooltip 的色点走同一条行视觉,所以是数据项的颜色。
- 数据项自己的 `itemStyle.opacity` 现在读了,盖过系列的和 visualMap 的(以前完全不读)。
- 诊断:连续型的组件还不画(`rsTyChartVisualMapNotDrawn`),分段型还不映射(`rsTyChartVisualMapPiecewise`),en/zh_CN 都加了。

### 基准

- `tools/advchart-oracle/visualmap-encode.js` → `advchart-visualmap-encode.json`:52 条解析、14 条 `fastLerp`、60 组排序(和真的 `Array.prototype.sort` 比,其中 6 组是 8 个键以上、专门区分"保留 run 但线性插入")、14 条子类型、3 组取值序列,30 个图:组件补全后的键序与施加顺序、每行颜色(zrender 的四个数,alpha 精确)和 opacity、visualMeta、折线与面积的渐变(坐标、offset、颜色逐位)、tooltip 色点。
- `test.advchart.visualmap`:逐位比较;图上的元素另按量化后的颜色和 alpha 再比一遍。测试给选项写上上游的调色板和 `gradientColor`,主题换成 accent 的那一步单独测。

### 已知偏差

- 组件本身不画(B2);分段型不映射(B4)。
- `symbol`、`symbolSize`、`liftZ`、`decal` 不施加;折线的符号仍是系列色;饼、漏斗、雷达、仪表盘、图例按数据项取色的路径不看 visualMap;graph 节点色(B3)。
- 店外的维度按数值解析;上游若是 ordinal 类型会给类目序号。
- 颜色 `rgba(0,0,0,0)` 量化成 0,等于不填充:画出来一样,但上游透明填充仍可命中。
- `rgba()` 里读不出的通道:上游带着 NaN 继续画,这里退回主题色。

### 变异测试

56 个。55 个被杀;1 个等价:`fastLerp` 的 alpha 不夹取——两端 alpha 在解析时已夹进 [0, 1],插值出不了界。

第一轮 7 个存活,补上之后全杀:
- "未定义画成黑色":测试用被测的 `TyVisualToChart` 算期望值,自己跟自己比;改成测试里独立打包。
- "保留 run、只把二分换成线性":只有 8 个键以上的列表分得开,oracle 补了 6 组。
- "行 opacity 乘而不替换"、"映射色保留系列渐变"、"散点只取填充色"、"取第一个 visualMeta":oracle 补 K6c(系列渐变 + opacity 0.5 + 数据项 opacity 0.3)、K6d(散点)、K9g(y、x 两个 meta)。
- 顺带发现数据项的 `itemStyle.opacity` 从来没读过,补上并加了变异。

### 下一批

B2:连续型组件的静态视图(对齐、四种矩阵、101 段渐变的圆角条、端点文字、静态手柄、背景、`positionGroup`),主题键 `TyAdvChartVisualMap*`。

## 89. Tier 1 第五十五批:连续型 visualMap 组件的静态视图(B2)(2026-09-27)

B1 让颜色落到了数据上,组件本身还不画。这一批把连续型组件画出来:渐变条、两端文字、手柄与手柄标签、背景,以及整个组件放在哪。交互(拖手柄、悬停指示器、hoverLink)不在这一批。

### 上游的做法

- **对齐**(`getItemAlign`):`align` 写了且不是 `auto` 就用它;否则把组件当成一根宽 `itemWidth` 的条,在画布上按 `left/right`(竖向)或 `top/bottom`(横向)求一次 `getLayoutRect`,padding 当 margin,再判断 `margin + x + w/2 < W/2`——padding 在这里**算了两遍**。
- **条组的变换**,四种之一:横向不反转是 `rotation π/2`、`scaleX` 由 bottom 决定,横向反转是 `−π/2` 且符号相反,竖向不反转 `scaleY −1`,竖向反转不翻 y;竖向的 `scaleX` 由 left 决定。旋转用 `Math.cos(π/2) = 6.123e-17`,不是 0——`dataset-encode0` 的 "High Score" 因此落在 `y = −9.999999999999991`。
- **两段条**:outOfRange 铺满 `[0, itemHeight]`,inRange 在 `linearMap(区间, extent, [0, itemHeight], clamp)` 之间;都是非全局线性渐变 `(0,0)→(0,1)`,101 个采样点,采样值是 `v0 + step * i`(**乘**,不是累加),颜色来自**控制器**的视觉(按键合并后补上失效色、`symbol`、`symbolSize`,施加顺序同样是 V8 的排序),起点是 `contentColor`,opacity 转成 alpha。
- **两端文字**:`text[1]` 在低端、`text[0]` 在高端,点是 `[itemWidth/2, −textGap]` 或 `[itemWidth/2, itemHeight + textGap]` 经条组变换;对齐方向用 `transformDirection` 变换 bottom/top。
- **手柄**(`calculable`):`handleSize` 是 `itemWidth` 的百分比;图标是 `path://` 药丸,保持比例放进方框;描边宽度是 `handleStyle.borderWidth × 2`、不随缩放;标签在 `[handleSize, 0]` 经手柄变换,文字是 `toFixed(precision)`。6.1.0 发行版**不**推开重叠的两个标签(源码树里有,发行版没有)。
- **背景**:组件先按"草图"(inRange 铺满、手柄在两端)画一遍,背景是那时的包围盒加 padding;再画真实状态。
- **定位**(`positionGroup`):真实状态的包围盒(含背景;边框有宽度时含半个线宽)按盒子参数在画布上求位置,**没有 margin**。
- **包围盒的算法**是 zrender 的:每个子元素的矩形经自己的局部变换,按添加顺序合并——第一个与**自己**合并,所以宽是 `(x + w) − x`;手柄标签最先加入;从 SVG 字符串建的图标路径存进 Float32Array(圆弧的圆心分两次存储、两次取整),多边形的路径数据是普通数组;文字矩形是 TSpan 在行中线上的矩形。

### 做法

- 新单元 `VisualMapView`:视图参数读取(`itemWidth/itemHeight` 按 `parseFloat`,padding 按 CSS 展开,盒子按 ignoreSize 合并,作者写的颜色优先于主题)、`getItemAlign`、四种条组矩阵、101 段渐变、两端文字、手柄与标签、zrender 的 float32 图标管线(解析、`processArc`、`calculateTransform`、`transformPath`、`fromArc`)、包围盒、背景、定位,以及画成元素。
- `VisualMap`:模型多了控制器的视觉(`ControllerKeys`/`Controller`);`TyVisualMapSpecOf` 多一个失效色参数。
- 控件:布局在 `Relayout` 里、图例之后;元素和图例一起进同一张绘制表,`z` 默认 4、全部 silent;`VisualMapLayout(i)` 供测试和宿主读取。连续型不再报"组件没画"(那条资源串删掉了),分段型仍报。
- 主题:`TyAdvChartVisualMap`(文字)、`...Inactive`(未选中段)、`...Border`、`...Background`(透明)、`...Handle`(手柄描边取表面色);`contentColor` 默认是主题 accent。重新生成了 `DefaultTheme.pas` 和 `Css.Catalog.pas`。
- 部分区间的 inRange 条:裁成条的矩形,不是圆角矩形(已知偏差)。

### 基准

- `tools/advchart-oracle/visualmap-view.js` → `advchart-visualmap-view.json`:31 个图、32 个组件(含画廊的 `dataset-encode0`、`calendar-charts`、`heatmap-cartesian` 原文),每个组件记录推导出的对齐、条组矩阵、区间与手柄端点、两段条的点和渐变、文字与手柄标签(位置、对齐、矩形)、手柄矩阵与矩形、背景、两次包围盒、组位置;文字宽度来自 zrender 自己的度量表。18 个自检变异全部变红。第一轮变异后补了四个例子:三项 padding、`textGap 0.1` 与小数 padding(文字矩形的 `(y − h/2 + h/2) − h/2`)、小数条宽的横向条和手柄、只有 opacity 没有颜色的 inRange(条是 `contentColor` 加 alpha 渐变)。
- `test.advchart.visualmapview`:用夹具的度量表替换控件的文字度量,逐位比较;文字另查绘制表里是否在全局位置画出。

### 已知偏差

- 交互、悬停指示器、hoverLink 没有。
- 控制器 `symbolSize` 不是 `itemWidth` 时条是梯形、手柄会缩放——这里仍按矩形(B3)。
- 部分区间的 inRange 条没有圆角裁剪。
- 自定义图标里的曲线(C/Q)按控制点估包围盒,比 zrender 的精确极值大;默认图标只有直线和圆弧,逐位一致。
- 文字只支持单行;`textStyle.align/verticalAlign` 覆盖不读。

### 变异测试

41 个。37 个被杀;4 个等价:
- 控制器补的 `symbol`/`symbolSize` 键:对最多六个类型的全部 28 960 种键序搜过,补不补都不改变颜色类型之间的先后(它们给 B3 用);
- 草图里的 inRange 条按真实区间画:它在铺满的 outOfRange 条里面,合并后的矩形不变;
- 背景矩形的 `(x + w) − x`、第一个子元素和自己合并:都只在矩形单独出现时起作用,而经过 `applyTransform` 的矩形宽本来就是 `max − min`,再加减一次 `x` 数值不变。代码照上游写,没有例子能区分。

第一轮还抓到一个真错:多边形的矩形起初按 float32 算,上游的多边形路径数据是普通数组(只有从 SVG 字符串建的路径才进 Float32Array),部分区间的矩形上游是 68.6,这里是 68.5999984741211。改掉,并把两段条的矩形加进比较。

### 下一批

B3:其余通道(colorHue/Saturation/Lightness/Alpha、symbol、symbolSize、liftZ)、控制器 symbolSize 让条成梯形、折线符号取行颜色、饼/漏斗/雷达/仪表盘/图例按数据项取色、graph 节点色。

## 90. Tier 1 第五十六批:visualMap 其余通道,直角坐标一侧(B3a)(2026-09-27)

B3 按系列拆成两批:这一批是直角坐标系上的——部分颜色通道、`symbol`、`symbolSize`、`liftZ`、折线与散点的逐行符号、控制器 `symbolSize` 让组件的条变成梯形;饼、漏斗、雷达、仪表盘、图例、graph 是 B3b。

### 上游的做法

- **部分颜色**:`colorHue/Saturation/Lightness/Alpha` 改的是**那一刻**的项颜色——系列色,或同一状态里先施加的类型写下的颜色。`modifyHSL` 用 `Math.round`,色相先取整再夹到 0..360(**夹**,不是取模;先夹后取整结果相同,所以那个变异观察不到);alpha 保留。
- **调色板在 visualMap 之后**(优先级 4500),写过任何颜色通道的项不再取调色板色,所以部分颜色总是从系列色出发。
- **`symbol`**:`doMapToArray`,取 `Math.round(linearMap(n, [0,1], [0, len−1]))` 处的名字;`none` 不画。
- **`symbolSize`**:数值线性映射,单个值补成一对;超出范围的默认值是 `[0, 0]`——上游仍建一个零大小的元素,画出来是空。
- **`liftZ`**:每种映射方法都是 `doMapFixed`,**永远取第一个值**,从不插值;没有超出范围的默认值;加在符号的 z2 上。
- **折线的符号取行颜色**:`emptyCircle` 填白、描边是行颜色,`circle` 填行颜色;数据项自己的 `itemStyle.color` 赢。
- **控制器的 `symbolSize`**:缺的状态取另一个状态写的,再没有就是 `[itemWidth, itemWidth]`;`none` 换成默认符号;按最大值缩放到 `[0, itemWidth]`;连续型一对大小不同时首项改成末项的三分之一。条的两端各取强制状态下该端的大小,成梯形;手柄按手柄所在值**自己的状态**取大小,缩放 `size/itemWidth`、x 在 `itemWidth − size/2`,横向时标签再偏 `±(itemWidth − size)/2`。

### port 以前

- B1 已经算了部分颜色,但没有测试钉住;`symbol`、`symbolSize`、`liftZ` 不施加。
- 折线符号一律是系列色;散点的大小只有一条自创的"第三列当直径"规则。
- 组件的条永远是矩形、手柄不缩放。
- B2 发出的组件元素带着默认的数据引用(系列 0、第 0 行),会被当成那一行的标记——这一批的测试查出来的。

### 做法

- `VisualMap`:映射多了名字列表;行记录多了符号、大小、`liftZ`;施加时按上面的规则写;控制器补全按上游写全(另一状态的大小、`none` 换掉、缩放、三分之一)。
- `Marks`:`RowSymbol` 把行上的符号、大小、`liftZ` 叠在系列的符号规格上;散点和折线符号都用它,`none` 不画,`liftZ` 加进 Z2;折线符号取行视觉(颜色、透明度)。
- `VisualMapView`:条的点按控制器大小;手柄按值自己的状态取大小并缩放,横向标签偏移;组件元素的数据引用设成"无"。

### 基准

- `tools/advchart-oracle/visualmap-channels.js` → `advchart-visualmap-channels.json`:17 条 `modifyHSL/modifyAlpha` 直接调用,23 个图(本批用其中 11 个直角坐标的),每行的最终项视觉和上游实际画出的符号元素(填充、描边、透明度、大小、z2),控制器的条点、手柄矩阵和标签;30 个自检变异全变红。
- `test.advchart.visualmapchannels`:颜色在测试里独立量化;圆形符号的宽度逐位比较,矩形符号的角是绝对坐标,宽度按 1e-9 比较。

### 已知偏差

- 大小为 0 的符号:上游有一个不可见的元素,这里不建。
- `symbolSize` 写成 `[w, h]` 对的映射不支持;`symbol` 对 NaN 值上游返回 `{}`,这里不设。
- `decal` 不画。

### 变异测试

24 个,全杀。第一轮一个存活:"手柄按强制的范围内状态取大小"——手柄值通常就是区间端点,落在范围内;只有端点经 `linearMap` 往返后差一点落到范围外才分得开。oracle 补了 C5d:extent `[0, 7]`、range `[0.1, 0.4]`、`itemHeight 150`,上端手柄往返后是 `0.4000000000000001`,取范围外的控制器大小 20,不是范围内的约 7.4。

### 下一批

B3b:饼、漏斗、雷达、仪表盘按数据项取色(调色板在 visualMap 之后、`visualMap: false` 的行按请求顺序取调色板),图例按数据项的色块(零 alpha 补救到 0.2),漏斗不用视觉 opacity,graph 节点色。

## 91. Tier 1 第五十七批:visualMap 与按数据项取色的系列(B3b)(2026-09-27)

饼、漏斗、雷达、仪表盘、graph,以及按数据项的图例色块。

### 上游的做法

- **调色板在编码之后**:按数据项的调色板在优先级 4500,写过任何颜色通道的项跳过它;只有剩下的项向调色板要色,**按要的顺序**,不按行号——`visualMap: false` 的两行拿到的是调色板第 0、第 1 个。系列的 `itemStyle.color` 是部分颜色的起点,也不覆盖映射出的颜色。
- **透明度**:饼保留视觉 opacity;**漏斗不用**——`FunnelView` 用项自己的 `itemStyle.opacity`(默认 1)覆盖多边形的透明度,超出范围的一带是透明色、不透明度 1。
- **雷达**:折线、面积、符号都取行颜色;符号大小取视觉的;雷达系列**不写 `symbol`**,只写 `symbolSize: 8`,视图回落到实心 `circle`。
- **仪表盘**:指针和进度条取行颜色。
- **graph**:节点取视觉颜色(类别色在编码之前),节点自己的颜色最后。被图例关掉的 graph 系列不编码。
- **图例**:按数据项的色块是项的视觉颜色;alpha 为 0 时抬到 0.2,但色块仍继承项的 opacity——默认的超出范围补全里 opacity 也是 0,所以补救常常看不见,只有显式写了超出范围颜色时看得见。

### port 以前

- `PerDatumColours` 按行号给每一行调色板色,再让系列色、项色覆盖;visualMap 不参与。
- 饼没有逐片透明度;雷达符号大小固定;图例色块没有 alpha 补救(只有 graph 类别色块有)、没有透明度。
- 雷达的默认符号是折线的空心 6px 圆环——和 visualMap 无关的老错,这一批的 oracle 查出来的。

### 做法

- `PerDatumColours`:先取行的视觉颜色,其余行按请求顺序向调色板或主题色环要色;系列 `itemStyle.color` 只覆盖没有视觉颜色的行;项自己的颜色最后。饼、漏斗、雷达、仪表盘都走这里。
- 饼:`TTyPieVisual.Alphas` 逐片透明度;漏斗不接。
- 雷达:`TTyRadarVisual.Sizes` 逐环符号大小;`TySymbolDefault('radar')` 改成实心圆 8px。
- 图例:按数据项的来源做 alpha 补救并带上项的透明度(`HasOpacity`/`Opacity`),色块元素用它。
- graph:节点在类别色、系列色之上取视觉颜色,项自己的颜色仍然最后。

### 基准

- 同一个 `advchart-visualmap-channels.json` 的 12 个例子(C3a–c、C7a–e、R1、R2、G1、GL),`test.advchart.visualmapchannels` 新增按数据项的比较:每片、每带、每环(描边、面积、每个符号)、每根指针、每个节点的颜色与透明度,以及图例每个色块的颜色与透明度;另有一条把雷达默认符号钉在上游记录的 `circle`/8 上。
- 零值的饼片上游是零角度扇形,画出来是空;这里不建,测试按"无图"接受。

### 变异测试

11 个,全杀。第一轮一个存活:雷达默认符号 6px——所有雷达例子都有视觉大小;补了上面那条默认值测试。

### 已知偏差

- R1(`radar2`)的滚动图例按普通图例画,色块颜色一致,翻页器没有。
- 仪表盘的标题、数值颜色(`GaugeView.ts:677`)没有记录,不比较。

### 下一批

B4:分段型(`splitNumber`/`pieces`/`categories`、`reformIntervals`、`findPieceIndex`、分段 visualMeta、`PiecewiseView`)。

## 92. Tier 1 第五十八批:分段型 visualMap 的模型与编码(B4a)(2026-09-27)

分段型 visualMap 的三种模式、选中表、补全、映射、逐行编码和 visualMeta。组件视图在 B4b。

### 上游的做法

- **模式**:`pieces` 非空走 pieces,否则 `categories` 为真走 categories,否则 splitNumber。预处理器先把 ec2 的 `splitList` 改名成 `pieces`(仅当没有 `pieces` 键),把段里的 `start`/`end` 改成 `min`/`max`(仅当没有 `min`/`max` 键);类型推断看的是改名后的 `pieces`。
- **splitNumber**:步长 `(max - min) / splitNumber`,精度从 `precision` 起往上加,直到 `toFixed` 不改变步长,最多到 5,**写回** `option.precision`,段文字按写回后的精度;段端点是**累加**的 `curr += step`,最后一段止于 max。`minOpen`/`maxOpen` 各加一个开区间段。
- **pieces**:每个边界依次试 `gte/gt/min`(`lte/lt/max`),**每试一次**都改写闭合标志和 useMinMax,找不到就是 ±∞ 且闭合;`min` 配开放的上界、`max` 配开放的下界时那一端改开。两端相等且都闭合的段带 `value`。竖向且未反向(或横向且反向)时先整体倒序,再 `reformIntervals`:V8 对短数组的排序(降序游程翻转 + 二分插入),扫描时被前一段盖住的端点拉齐,被压成非双闭点的段**删掉**,它的原始下标也从选中表里消失。
- **categories**:段就是类别,竖向且未反向时倒序;映射方法是 `category`,`categoryMap` 按 `option.categories` 原顺序建,没有视觉值的类别从表里删掉、落到默认槽。
- **选中表**:键是段的原始下标(类别模式是类别名);没写的键算选中;`selectedMode: 'single'` 只留第一个。
- **状态**:值所在的段(不找最近)被选中才是 inRange,不在任何段里是 outOfRange。
- **映射**:分段型的归一化是**最近段**的下标摊到 [0, 1];inRange 时段自己的视觉值优先(`getSpecifiedVisual`,不找最近),outOfRange 的段没有视觉值;liftZ 在任何方法下都取第一个值。visualMeta 里的不透明度借 `colorAlpha` 的名义查段视觉值。
- **补全**:某段写了、而选项和 target 的两个状态都没有的视觉类型,在选项的两个状态里补上 visualDefault 的 active/inactive 值——状态因此存在,completeSingle 不再补默认颜色。`!!option.categories` 为真时默认值取列表最后一个元素(标量),控制器缺省的颜色、符号、尺寸也是标量;默认符号是 `itemSymbol`。
- **类别值**:比较的是值的字符串形式;非坐标轴的字符串列里存的是原字符串,坐标轴的列存序号,所以类别轴上的维度永远匹配不上。映射给出 undefined 的不透明度时,样式里的 opacity 被写成 undefined,盖掉散点默认的 0.8,按 1 绘制。
- **visualMeta**:类别模式没有。其余模式把段表两端补上 `[-∞, 首段下界]`、`[末段上界, +∞]`,段之间的空隙补一对 outOfRange 色标,每段按代表值着色——有限段两个色标,开区间段进 outerColors。代表值:值段取值,`[-∞, +∞]` 取 0,其余取中点(开区间段因此是 ±∞)。

### port 以前

- 分段型只记一条"尚未支持"的诊断,系列保留原色。

### 做法

- `TTyVisualMapSpec` 增加 `Mode`、`Pieces`、`Selected`、`Categories`、`Precision`、`Formatter`、`IsCategory`;`TTyVisualMapping` 增加 `Method`、按类别的 `CatVals`/`CatDefault`、`UsePieces`。
- `BuildPieces`/`ReformIntervals`/`V8SortPieces`/`BuildSelected` 照上游三种 resetMethods 逐句移植;`TyVisualFindPiece`、`TyVisualRepresent` 公开。
- `TyVisualValueState`、`TyVisualApply` 各加一个带值文本的重载;旧签名对分段型用 `TyJsNumberToString` 转发。`TyVisualSeriesValues` 的新重载同时给出每行的文本:非坐标轴列里的字符串原样保留。
- `TyVisualMetaOf` 对分段型走 `PiecewiseMeta`;直线的渐变沿用连续型的裁剪与构造。
- 补全在 `TyVisualMapSpecOf` 里:段视觉类型补全、类别默认值、控制器标量默认、`itemSymbol`。
- `SolveVisualMaps` 不再跳过分段型;诊断 `rsTyChartVisualMapPiecewise` 删除(含 .pot/.po)。
- 预处理器的两处改名在 `EffectivePieces` 和段边界读取处就地做,子类型推断同样认 `splitList`。

### 基准

- `tools/advchart-oracle/visualmap-piecewise.js` 真跑 ECharts 6.1,45 个用例:splitNumber(S1–S9、P2、P3)、pieces(P4–P21)、categories(C1–C4)、视图用例的编码部分(V1–V9)、直线(L1、L2),以及画廊 area-pieces、line-sections、line-aqi、candlestick-brush、calendar-heatmap。
- `test.advchart.visualmappiecewise` 逐位比较:模式、范围、写回的精度、类别;每段的键、原始下标、区间与闭合、值、文字、段视觉值、选中、代表值与状态;选中表的键集合;target 与控制器每个状态的键、应用顺序、每个映射的方法、视觉值(类别按下标与默认槽)、hasSpecialVisual;每行每个 visualMap 的段、最近段、状态,行的颜色、不透明度、符号、尺寸,柱与散点实际绘制的颜色和 alpha;visualMeta 的色标与 outerColors;折线与面积的渐变。

### 变异测试

48 个,44 杀、4 个等价。第一轮 8 个存活,补了四个 oracle 用例:
- P19:同一下界、闭合不同的两段,排序靠闭合标志分先后(也杀掉"pieces 不倒序");
- P20:单独的 `{min: 10}`,下端改开;
- P21:`{gte: 5, lte: 5}` 成为值段;
- P18:值段作为最近段(见下,等价)。

等价的四个:
- 值段的最近段更新:pieces 模式的值段同时带 `[v, v]` 区间,区间那一遍做同样的更新;类别模式从不找最近段。
- 低端补段:补上的 `[-∞, 首段下界]` 和缺口填充给出同一对 outOfRange 值。
- `[-∞, +∞]` 的代表值 0:只在没有段时出现,那时任何值都不在段里。
- 值段的代表值:`(v + v) / 2 = v`。

### 已知偏差

- line-aqi 的 dataZoom 没有移植,值轴按未过滤的数据取 0..500(上游 0..400),渐变坐标不同;visualMeta 本身逐位相同,测试只豁免这一条折线比较。
- `formatter` 只支持字符串;函数形式不适用于 JSON 选项。
- 段值或类别写成对象、数组、布尔等非标量时的上游怪行为(例如把数组当颜色)不复刻。

### 下一批

B4b:PiecewiseView(每段一个符号加标签、两端文字、`showLabel` 规则、视图倒序、`layout.box` 的下一矩形项、背景、`positionGroup`)。

## 93. Tier 1 第五十九批:分段型 visualMap 的组件视图(B4b)(2026-09-27)

PiecewiseView 的静态画面:每段一个条目(符号加标签)、两端文字、`layout.box` 排列、背景和整体定位。交互(点击切换选中、悬停联动)不在这一批。

### 上游的做法

- **条目**:每段一组,`createSymbol(符号, 0, 0, itemWidth, itemHeight, 颜色)`。符号和颜色是 `getControllerVisual(代表值, …)`:控制器视觉值,状态按代表值自己的状态(不强制),颜色从 `contentColor` 起,不透明度不并进颜色。类别段的代表值是类别名。
- **标签**:`showLabel` 写了就照写的,否则只在没有 `text` 时显示。x 为 `align === 'right' ? -textGap : itemWidth + textGap`,y 为 itemHeight 的一半;`align` 取 `textStyle.align`,否则取条目对齐;垂直对齐默认 middle;不透明度取 `textStyle.opacity`,否则 outOfRange 时 0.5。
- **条目对齐**:竖向走 `helper.getItemAlign`(和连续型同一个函数),横向是 `align`,`auto` 当 left。
- **顺序**:`horizontal ? inverse : !inverse` 时段表倒过来(竖向默认高值在上);否则把两端文字倒过来。两端文字各自成组,空字符串不画;显示标签时贴条目对齐那一侧,否则居中在条目宽度中点。
- **`layout.box`**:按子组的包围盒一个接一个排,每一步是 `rect.height + (-next.rect.y + rect.y)` 再加 itemGap——后一项只在子组的包围盒不从 0 开始时非零,也就是两端文字(文字矩形从 1 起)挨着条目的地方。
- **背景与定位**:和连续型相同——背景按排好后的整组包围盒加 padding,定位用含背景(边框有宽度时连笔宽)的包围盒。
- **符号包围盒**:圆是 `cx ± r`(`r = min(w, h) / 2`,所以 20.3 × 14.1 的圆 x 是 3.1000000000000005),圆角矩形由直线段和四个 1/4 圆弧(`r = min(w, h) / 4`)求得,矩形 `(x + w) - x`。

### port 以前

- 分段型组件什么都不画。

### 做法

- `TTyVmViewSpec` 增加分段型字段:`Piecewise`(子类型照模型判断)、`ItemGap`、`showLabel`、`selectedMode`(为假时元素静默)、`textStyle` 的 align / verticalAlign / opacity;分段型的 itemHeight 默认 14。
- 新增 `TTyVmItem` 和 `LayoutPiecewise`,`TyLayoutVisualMap` 按子类型分派;连续型的 getItemAlign 抽成共用的 `AutoItemAlign`。
- `TyVmSymbolRect` 用已有的 `PathRect`/`FromArc` 构造圆和圆角矩形的路径算包围盒。
- 画的时候每个条目用 `TyBuildSymbolInBox` 画符号,标签的不透明度乘到文字颜色的 alpha 上。

### 基准

- 连续型视图 oracle 加 V3e(见变异测试)。
- 沿用 `advchart-visualmap-piecewise.json`(第 58 批的 oracle 本来就记录了视图)。`test.advchart.visualmappiecewiseview` 对所有显示的分段组件逐位比较:条目对齐、是否带标签、两端文字、每个子组的类型、段号、位置、包围盒,符号类型、框、颜色、包围盒,标签的文字、锚点、对齐、不透明度、矩形,两次包围盒、背景、组位置;每个标签和两端文字都要在全局坐标处画出、alpha 对。
- 测试用的表测量器原先是大小写不敏感的 `TStringList`,"low" 查到了 "Low" 的宽度;两个视图测试的测量器都改成大小写敏感。

### 变异测试

25 个,全杀。第一轮一个存活:连续型改调共用的 `AutoItemAlign` 时量的是条长还是条宽——连续型 oracle 没有落在中线附近的例子;`visualmap-view.js` 补了 V3e(竖向 left 320:按宽 20 在左,按长 140 会判到右)。

### 已知偏差

- 点击切换选中、悬停联动没有移植;`selectedMode` 只决定元素是否静默。
- 圆、圆角矩形、矩形以外的符号,包围盒取条目框。

### 下一批

visualMap 系列到此完成(B1–B4)。下一步回到画廊缺口清单挑下一个系列。

## 94. Tier 1 第六十批:dataZoom 的处理层(C1)(2026-09-27)

dataZoom 的模型、窗口、过滤和轴范围钉点。slider 组件的画面在 C2,交互在之后。

### 上游的做法

- **类型与目标**:不写 type 的 dataZoom 是 slider。目标轴:写了 `xAxisIndex`/`yAxisIndex`(或 id、`'all'`)就用写的;否则按 orient 取第一根 x(纵向取 y)轴加同一网格里的同向轴,再不行取第一根类目轴。orient 不写时,第一个目标维是 y 才是纵向。
- **宿主**:一根轴只归第一个指向它的 dataZoom;后面指向同一根轴的 dataZoom 自己的 start/end 被忽略,显示宿主的窗口。
- **toolbox 的 select**:`toolbox.feature.dataZoom` 写了就给每根 x 轴、再每根 y 轴各追加一个 select 型 dataZoom(排在作者写的后面),全窗口,filterMode 取 feature 的。它们不画东西,但会接管作者没指向的轴并按全窗口过滤。
- **取值方式**:每一端分别看 percent 还是 value——只写了一个就用那个;都写了看 `rangeMode`,没有就用 percent。读的是作者写的原值,不是合并后的默认值。
- **窗口**:百分比按轴的原始范围(nice 之前:数据、min/max、boundaryGap、含零、柱子起点)线性换算;反过来的一对交换;越界的窗口由 `sliderMove` 整体平移、保持跨度(`-10..50` 成 `0..60`);`minSpan`/`maxSpan` 等把跨度夹进范围。由百分比算出的值按轴像素跨度求精度(`getAcceptableTickPrecision(窗口, 像素, 0.5)`,类目和时间为 0)用 toFixed 取整;正好 0%/100% 的一端取原始范围的端点。`percentInverted` 由取整后的值反算。
- **alignTicks**:对齐到另一根轴、且那根轴也由同一个 dataZoom 控制时,这根轴最后算,用那根轴的 `percentInverted` 当 start/end——zrender 的 `defaults` 保留目标的键,所以它盖过自己写的 start/end。
- **钉点**:不在 0%/100% 的一端成为固定的轴端(fixMM 和 zoomFixMM),nice 不再外扩它;在 0%/100% 的一端照常 nice。被缩放的轴只在 reset 时建一次原始范围,之后不再从过滤后的数据重算。containShape 不加宽被钉住的一端;alignTicks 只要有一端被钉就两端都当固定。
- **过滤**(按 dataZoom 声明顺序,先 reset 本 dataZoom 的所有轴再过滤):`filter` 每一维都在窗口里或是 NaN 才保留;`weakFilter` 某一维在窗口里、或跨过窗口才保留,全 NaN 的行删掉;`empty` 把窗口外的值换成 NaN,行留着,另一根轴不跟着变;`none` 不过滤。维度是 `mapDimensionsAll`——堆叠系列的原值和堆叠结果两维都过滤,所以按堆叠和缩放时底下的系列可能一行不剩。后一个 dataZoom 的原始范围按前一个过滤后的数据算。
- **顺序**:dataZoom 在 1000,堆叠(900)和轴统计(920,柱宽的最小间距)之后——堆叠和间距都按未过滤的数据。

### port 以前

- dataZoom 完全没有接线,带 dataZoom 的图照全量数据画;编辑器还把不写 type 的 dataZoom 报成"没有类型"。
- 笛卡尔标记的 `RawDataIndex` 直接等于视图下标——store 一旦被过滤,逐项 tooltip 和回调会指错行。

### 做法

- 新单元 `tyControls.AdvChart.DataZoom`:模型(目标、宿主、取值方式、select 型)、`TyDzSliderMove`、`TyDzCalculateWindow`、`TyDzParse`(类目名、时间字符串、对数 sanitize)。
- `Series`:把数据并集加原始范围抽成 `TyAxisNoZoomExtent`,dataZoom 和最终定轴共用一份;`TyApplyAxisExtents` 新增带 `TTyAxisZoom` 的重载,被缩放的轴复用 reset 时的原始范围再加钉点;containShape 跳过钉住的一端;alignTicks 的固定端按"有一端被钉就两端固定";`TyAxisAlignTo`、`TyAxisDataDims` 导出;`TyLiPosMinGap` 改读原始行。
- `Data`:`EmptyOutside`(允许类目列,关掉 RawMin/RawMax 快路径);`SelectRange` 遇 NaN 边界不再抛异常。
- `AdvanceChart`:`SolveDataZooms` 放在堆叠之后、定轴之前;公开 `DataZoomCount`/`DataZoomSpec`/`AxisZoom`/`SeriesStore`。
- `Marks`:标记建完后按 store 的 `GetRawIndex` 补 `RawDataIndex`。
- `Complete`:dataZoom 的子类型默认 slider。

### 基准

- `tools/advchart-oracle/datazoom-window.js` 真跑 ECharts 6.1,72 个用例(窗口 W、目标与宿主 T、对齐 A、过滤 F、画廊 10 个),自检 23 条守卫。`test.advchart.datazoomwindow` 逐位比较:每个 dataZoom 的子类型、方向、目标、宿主、取值方式、filterMode、窗口的 value/percent/percentInverted/精度;每根轴的宿主、原始范围、钉点、最终范围、间隔、主刻度;每个系列留下的行及其原始下标、`empty` 后的值,以及柱、散点、折线实际画出的位置(柱按 plot 裁剪后比较)。
- 延后的用例打开了:contain-shape 的 dataZoom 用例进 G10(外加一个"最小间距在窗口外"的用例,证明柱宽按未过滤数据);scale-align 的 E10 改为端到端,另加 E10b、E10c 检查"一端被钉两端固定";visualmappiecewise 去掉了 line-aqi 的豁免。

### 变异测试

39 个,全杀。第一轮 3 个存活,各补一个 oracle 用例:
- W12d:`minSpan` 和 `minValueSpan` 同时写,值跨度优先;
- A3:要对齐的轴在目标里排在前面,仍要最后算;
- W14b:boundaryGap 30%、`splitNumber: 20`、窗口 0–50——0% 那端用过滤前测的原始范围(20),从留下的行重测会是 35。

### 已知偏差

- 折线的 `sampling`(lttb 等)没有移植:area-simple 按采样前的行比较。
- `smooth` 折线画成直线段,不比较它的顶点。
- 这个测试不给测量表,轴标签宽度和上游不同时 plot 位置会变,那样的用例不比较画出的位置(窗口、范围、刻度照比)。
- 选项里写 NaN 无法用 JSON 表达,按 null 处理(对记录到的用例结果相同)。

### 下一批

C2:slider 的静态画面(位置、背景、数据阴影、填充、手柄、移动条、标签)和新的主题键。

## 95. Tier 1 第六十一批:slider dataZoom 的静态画面(C2)(2026-09-29)

slider 组件第一次渲染后的样子:位置、窗口两端、背景、数据阴影、填充、边框、两个手柄、移动条及其图标、两个标签,和它们的绘制顺序。交互在 C3。

### 上游的做法

- **位置**(`_resetLocation`):box 按 `mergeLayoutParam` 合并到 slider 的默认值上(`right/top/width/height` 为占位 `'ph'`,`left/bottom` 为 null;作者写了两个就只留那两个,写了一个就补上默认里的第一个),再把 `'ph'` 换成默认位置:横向在网格下方(`right = W − 网格 x − 网格宽`,`top = H − 30 − 15 − 7`,其中 7 是**常量**,不读 `moveHandleSize`,关掉 brushSelect 时为 0),纵向在网格右侧(`right = 15`,`top = 网格 y`)。网格取第一根目标轴所在网格**排好标签之后**的矩形;极坐标等没有矩形的取画布中间五分之三。然后走 `getLayoutRect`。
- **窗口两端**(`_resetInterval`):用代表轴的 `percent`(不是 `percentInverted`)线性映射到 `[0, 长度]`。
- **手柄**:图标既不是内置符号、也不含 `path://`/`image://` 时补上 `path://`;在 `(−1, 0, 2, 2)` 里按比例居中(`makePath` 'center'),多于 11 个数的路径数据按 float32 存(解析一次、拟合时点存一次、圆弧圆心存两次)。手柄高 = `handleSize` 相对粗细的百分比,宽 = 图标宽高比 × 高。放在窗口两端**往里一像素**。
- **移动条**(brushSelect):`y = 粗细 − 0.5`、高 `moveHandleSize`、圆角 `[0, 0, 2, 2]`;图标边长为条高的 0.8,居中于窗口。还有一块不可见的拖动区。
- **数据阴影**:第一根目标轴上第一个 line/bar/candlestick/scatter 系列(`showDataShadow: true` 时任何系列),读**原始**数据(不经过 dataZoom 过滤、不采样;K 线取 open)。横坐标是**累加**的步长(时间轴按时间戳比例),`round(行数/长度)` 行取一行,跳过的行照样走步长;纵向按数据范围上下各放宽 30% 映射到粗细;空值落到底线再断开。三组(窗口左、窗口内、窗口右)各一个多边形加一条折线,用剪裁区分段,中间一组用 `selectedDataBackground`。
- **组的位置**(`_positionGroup`):读 slider 组包围盒时 `_updateView` 还没跑——手柄未缩放停在 0、填充和移动条宽度为 0、移动图标在 0。包围盒按 zrender 算:折线没有填充,描边按 `max(线宽, 5)` 撑大;手柄的 `strokeNoScale` 在没有全局变换时线宽比例为 1。然后按方向和反向翻转/旋转(横向 y 翻转,纵向转 90°;另一根轴反向时不翻;本轴反向时 x 镜像),视图组平移到"位置 − 翻转后包围盒的左上角"。所以默认 slider 比网格靠右 2.8px。
- **标签**:在视图组里,放在窗口两端外侧半个手柄宽加 5px;横向左右对齐、纵向上下对齐(由 `transformDirection` 决定)。文字:`showDetail` 关掉为空;类目轴取类目名、时间轴取刻度自己的完整日期(最细单位是年/月时到日,否则到秒),数值轴按 `labelPrecision`(默认取窗口的 valuePrecision)toFixed;`labelFormatter` 字符串只换第一个 `{value}`。默认不可见(`handleLabel.show`)。
- **绘制顺序**:遍历顺序上按 z2 稳定排序——背景 −40、阴影多边形 −20、阴影折线 −19、填充/边框/移动条/图标 0、手柄 5、标签 10;文字为空的标签不画、排在最后。

### port 以前

- slider 什么都不画;时间刻度没有 `getLabel`;`empty` 过滤就地改写数据列,读不到原值。

### 做法

- 新单元 `tyControls.AdvChart.ZrPath`:zrender PathProxy 的静态部分——SVG 路径解析(含 processArc)、toStatic 的 float32、`transformPath`、`makePath` 居中拟合、内置符号、圆角矩形、`subPixelOptimize`、精确包围盒(三次/二次曲线极值、圆弧四分点)、描边膨胀、组包围盒累加、局部变换。
- 新单元 `tyControls.AdvChart.DataZoomView`:选项解析、box 合并、`TyLayoutDzSlider`(两个时刻的元素、翻转矩阵、组位置、剪裁、标签、绘制顺序)、`TyBuildDzSliderMarks`。布局在局部屏蔽浮点陷阱下算(零跨度的轴上游照样除以 0),出口处洗掉非有限值。
- `JsMath` 加 `TyJsAcos`(fdlibm e_acos.c,V8 同款)。`Time` 加 `TyTimeFullLabel`,`TTyTimeScale.GetLabel`。`Data` 在 `EmptyOutside` 第一次改写某列时留一份原值,`GetOriginalByRaw` 读它。
- `AdvanceChart`:`SolveDataZoomViews` 在 Relayout 末尾(网格排好之后);`BuildDataZooms` 在绘制表最后;公开 `DataZoomSliderLayout`。
- 主题键 `TyAdvChartDataZoom`(标签)、`…Border`、`…Background`、`…Filler`、`…Handle`、`…MoveHandle`(`color` 是移动图标)、`…Shadow`、`…ShadowSelected`,都从 accent/surface/on-surface 派生。作者写的颜色优先;写了颜色没写透明度时用上游默认透明度(阴影 0.2/0.3,移动条 0.5),用主题色时透明度在颜色里。

### 基准

- `tools/advchart-oracle/datazoom-slider.js` 真跑 ECharts 6.1,54 张图 52 个 slider,自检 19 条守卫。测量表除了 slider 自己的标签,还记下画布上所有文字和各轴的标签,这样 containLabel 的网格和上游落在同一处(mix-zoom-on-value 起初就是差在这里)。
- `test.advchart.datazoomslider` 逐位比较:网格矩形、位置、长度粗细、窗口两端、手柄宽高、移动条高、阴影的两个范围和全部点、slider 组矩阵、`_positionGroup` 读到的每个子元素矩形和局部矩阵、组位置、三个阴影组的剪裁和矩形,每个元素的局部/全局矩阵、包围盒、形状或路径数据(逐条命令逐个参数)、数据长度,两个标签的文字/位置/对齐/矩形,最终矩形和绘制顺序。另有绘制测试(剪裁区、主题填充色、作者的颜色和线宽、默认透明度)。

### 变异测试

61 个。第一轮 7 个存活:
- 补 3 个 oracle 用例杀掉 4 个:D10c(手柄图标带转过的椭圆大弧、移动图标是半圆:圆弧过四分点)、D23(inside 用 `empty` 清空 y 轴窗口外的值,阴影仍读原值——两个"阴影读到被清空的行"的变异)、D24(第一个系列是 pictorialBar,阴影取第二个折线)。
- 3 个等价:网格按组件下标找、去掉 Break 结果相同;内置符号只用 0、±π/2、π、1.5π,归一化前后一样;圆弧解析里的 acos 换成 FPC 的 `ArcCos`——带圆弧的图标都超过 11 个数、存成 float32,一个 ulp 的差别被抹掉。`TyJsAcos` 本身由 jsmath 测试钉住:js-math oracle 新增 3025 个 V8 的 acos 值(随机值加 fdlibm 的分支边界),FPC 的 `ArcCos` 在其中约四分之一上差一个 ulp,在最小次正规数上直接溢出。

### 已知偏差

- 自定义手柄图标在翻转时按旋转画,不做镜像(默认图标上下近似对称,看不出)。
- `pin`、`arrow`、图片图标的包围盒取符号框。

### 下一批

C3:slider 的拖动、点击、刷选和悬停标签,inside 的滚轮缩放和拖动平移,dataZoom 动作(联动的 dataZoom 一起变)。

## 96. Tier 1 第六十二批:dataZoom 的交互(C3)(2026-09-29)

slider 的拖动、点击、刷选、悬停标签,inside 的滚轮缩放和拖动平移,dataZoom 动作和它的联动,以及两条派发路径共用的节流。dataZoom 系列到此完成。

### 上游的做法

- **事件顺序**(zrender Handler):mousemove 时先对旧目标发 mouseout,再发 mousemove(Draggable 的拖动、roam 的平移、刷选都在这里),最后对新目标发 mouseover。所以快速拖动的第一下手柄就离开了指针,mouseout 在"正在拖"之前到达,标签先被藏起来;拖起来之后再离开就不藏。命中测试从顶往下:手柄(悬停的那个 z2 升到 15)、移动区(不可见但照样命中)、没开刷选时的填充、点击面板;slider 的 z 为 4,高于系列。
- **点击规则**:按下和抬起必须落在同一个元素上,点击点离按下点不超过 4px;点击送给点击点下面的元素——刷选之后手柄可能已经移到那里。
- **拖动**(`_onDragMove`):屏幕位移经过 slider 组局部矩阵的**逆矩阵**(纵向时 cos(π/2)=6.1e-17 不是 0),取 x 分量,`sliderMove` 移一端(zoomLock 时整体),min/maxSpan 取**宿主** dataZoom 的、换成像素。`realtime` 时每次变化都派发;否则拖动中不派发、标签按"视图区间会得到的窗口"写(宿主是值模式的那端退回数据端点),松手才派发——松手即使没动也派发。
- **点击面板**:窗口中心移到点击处,跨度不变,越界夹住。
- **刷选**(brushSelect,默认开):按下点击面板开始,移动时刷选框从起点到当前点(终点夹在 slider 内),松开时不到 200ms 且宽度不足 5px 算点击,否则刷选框成为新窗口(再过一遍 min/maxSpan)。刷选框在新的按下时**不清除**,只有视图重建才清——所以之后一次不动的点击会把上一次的刷选框再套用一遍(BRUSH-STALE)。
- **标签**:悬停手柄、移动区(或没开刷选时的填充)、拖动中显示 `emphasis.handleLabel.show`(默认 true),其余时候是 `handleLabel.show`。移动条的高亮是两个位:移动区自己的悬停,和标签显示。
- **动作**:`{type: 'dataZoom', start, end}` 按共享坐标轴找出所有联动的 dataZoom(传递),全部 `setRawRange`:两端都成百分比、值清空,取值方式变 percent。然后**同步**更新;发起的 slider 保留自己的端点(交叉后可能是降序)、刷选框和状态,其他 slider 按窗口重建,inside 的区间每次渲染都取窗口。
- **inside**:每个网格一个 roam 控制器,管这个网格上所有 inside;网格里有一个 inside 能缩放就挂滚轮(全部 zoomLock 时滚轮整个没有,`moveOnMouseWheel` 也跟着没了;缩放处理本身不读 zoomLock),全部禁用就没有控制器。指针在网格矩形里(闭区间)才处理,滚轮不论缩没缩都拦下。缩放系数按 `|delta|` 取 1.1/1.2/1.4,以指针在当前区间里对应的百分比为中心;平移按指针位移占网格边长的比例乘区间跨度,x 轴默认反号、y 轴同号、反向轴再反;`moveOnMouseWheel` 的步长 0.05/0.15/0.4 个跨度。修饰键设置(`'shift'` 等)要对应按键按下才生效。禁用的 inside 照样算区间(视图区间会漂),只是不派发。
- **节流**('fixRate'):默认 100ms(动画开且更新时长大于 0,否则 20)。距上次执行不足间隔的调用延到"上次执行 + 间隔"时再跑,用最新的参数;slider 的延后调用读执行时的区间。滚轮缩放和滚动平移在同一毫秒各派发一次时,第二次就被延后。

### port 以前

- dataZoom 只有静态画面,指针不起作用;`TabStop` 的注释说 dataZoom 落地时要改成可获得焦点。

### 做法

- 新单元 `tyControls.AdvChart.DataZoomAct`:节流、`_updateInterval`、滚轮系数和滚动步长、方向信息、inside 的缩放和平移、交互选项解析、行为设置判断,以及动作、slider 视图状态的记录类型。
- `DataZoomView`:布局接受视图状态(保留的端点和区间、标签显隐、手柄和移动条高亮、刷选框);悬停的手柄 z2 升 10、换悬停颜色,移动条高亮,刷选框画在 slider 组最后。
- `AdvanceChart`:
  - `setRawRange` 的窗口按 dataZoom 保存,重建时写进模型;每次重建都按上游规则重置视图状态(发起动作的 slider 除外)。
  - 指针入口 `DataZoomPointer`(按下、移动、抬起、点击、滚轮),按 zrender 的顺序分派;MouseDown/MouseMove/MouseUp/DoMouseWheel 接到它上面,滚轮进了网格就不再交给 graph。
  - 派发同步重排;公开 `DispatchDataZoom` 和 `OnDataZoom` 事件;节流用可注入的时钟(`DataZoomNow`/`DataZoomTick`),平时由 TTimer 驱动。
  - 光标:手柄是左右/上下调整,移动区是手形、拖动时是移动,刷选面板是十字,其余的可点元素是手形;不是 dataZoom 时还原宿主自己的光标。
  - 只有 slider 状态真的变了才重画视图。
- 主题键 `TyAdvChartDataZoomHandle:hover`、`TyAdvChartDataZoomMoveHandle:hover`、`TyAdvChartDataZoomBrush`。
- `TabStop` 保持 False,注释里标明:上游 dataZoom 只有指针交互,没有键盘绑定,原先的理由不成立。

### 基准

- `tools/advchart-oracle/datazoom-interact.js` 用 zrender 真的 Handler 喂合成指针事件,时钟和定时器是假的(只在事件之间走),66 个场景、523 步,自带 JS 转写逐步复现,17 条守卫。oracle 里的 JS 转写就是上游规则的逐条说明。
- `test.advchart.datazoominteract` 逐步回放:每一步比较派发的动作(条数、是否批量、是否延后、每项的 dataZoom 和起止)、是否拦截、悬停目标和光标,每个 dataZoom 的取值方式和窗口,slider 的端点、区间、拖动态、刷选态、标签显隐和文字、刷选框、手柄和移动条高亮,inside 的区间。另有 API 联动测试和经由控件自己的鼠标处理函数的测试。

### 变异测试

47 个。第一轮 8 个存活:
- 补 5 个 oracle 场景杀掉 5 个:CLICK-SPLIT(移动区按下、往下 3px 在面板上抬起——按下和抬起不是同一元素,点击作废)、BRUSH-CLAMP0(刷选越过左端)、CHAIN2(第二遍才找到的联动)、SPANS-HOST(非宿主 slider 拖动,按宿主 inside 的 minSpan 夹住)、HOVER-OVERLAP(两手柄重叠,悬停的那个 z2 升高仍是目标)。
- 真实鼠标测试改成精确断言,杀掉"一格滚轮当 100"的;节流函数加单元测试(定时器晚到时仍记到期时刻),杀掉"延后执行记触发时刻"的。
- 1 个等价:点击面板的越界检查——能命中面板的点本来就在面板里。

### 已知偏差

- 悬停时手柄和移动条的样式按主题键画,不读作者的 `emphasis.handleStyle`/`emphasis.moveHandleStyle`。
- 指针被别的窗口夺走(CaptureChanged)时按"在最后位置抬起"结束拖动,上游没有对应的事件。
- 触摸的双指缩放没有移植。

### 下一批

dataZoom 系列完成(C1–C3)。下一步回画廊缺口清单挑下一个系列。

## 97. Tier 1 第六十三批:折线的平滑(2026-09-29)

dataZoom 做完后按画廊重数缺口:还不画的系列类型里 custom 13(`renderItem` 是函数,JSON 写不下)、heatmap 12、effectScatter/sankey/tree 各 7;已经画的系列上,`smooth` 出现在 19 个文件里,却一直画成直线段——这是已画内容里最大的走样,先补它。

### 上游的做法

- **读取**(`getSmooth`):数字原样用,不夹(1.5 就是 1.5,0 和负数画直线);其他值按真假取 0.5 或 0——字符串 `'0'`、`'0.3'` 都是 0.5。`smoothMonotone` 只认 `'x'`/`'y'`。
- **点**:布局点存在 Float32Array 里,每个坐标在存入时取一次 float32;**控制点按这些 float32 值用双精度算,自己不再取整**。
- **drawSegment**(poly.ts):一段从 `M` 开始,每个画出的点一个 `C`(不平滑时是 `L`)。离**上一个画出的点**不到 √0.5 px 的点丢掉(直线也丢),前一点不更新;下一点和当前点重合时先跨过重合点;`connectNulls` 时越过空值找下一个合法点。下一点非法、或按计数到了段尾,就是末点:第二个控制点取它自己;首点的第一个控制点也取它自己。中间点按前后两段长度之比分配切线,先把"下一控制点"夹进 `[当前, 下一点]` 的框,由它反推"本控制点"再夹进 `[上一点, 当前]` 的框,最后由本控制点反推下一控制点、不再夹。`'x'`/`'y'` 单调时切线水平/竖直,不用比例、不夹,方向是 `next − prev` 的符号(0 算负)。越界读到的点算非法——段尾常常是这样判出来的。
- **面积**(ECPolygon):每段上沿正向画,底边(被堆叠系列的结果,或原点)在同一组下标上**反向**走,以 `L` 开头,最后 `Z`。底边的平滑取**被堆叠的那个系列**的 smooth(不堆叠为 0),单调和 connectNulls 取本系列的。反向平滑和正向平滑再倒过来差最后一位,得照原样反着走。connectNulls 时空值下面的底点仍合法,底边会经过它。
- **step** 并不关掉平滑(源码注释说会,实际没有):先把点转成阶梯,再照样平滑,每段都是贴着轴的 `C`。
- **包围盒**按曲线极值算(`cubicExtrema` 的重根分支只写不计数),对象坐标的渐变用它。

### port 以前

- `smooth` 不读,平滑折线画成直线段;折线直接把点连起来,不丢近点。

### 做法

- 新单元 `tyControls.AdvChart.LinePath`:`TyLineSmoothOf`、逐字转写的 `TyDrawSegment`、`TyPolylinePath`/`TyPolygonPath`(connectNulls 两端修剪)、按上游写的 `TyTurnPointsIntoStep`、按 `M` 切段、路径包围盒(借 ZrPath 的精确曲线包围盒)。
- `Shape`:多边形和折线可带一组路径命令(移动、直线、三次曲线、闭合)和路径自己的包围盒;`Render` 有命令时照命令画,`TyShapeBounds` 有路径包围盒时用它。**顶点不变**,命中测试和所有读顶点的地方照旧。
- `Marks.BuildLine`:先在整个系列的行上按上游规则建点和底边(底边在空值下方也算),需要时转阶梯,生成折线和面积的路径,按 `M` 切成段;原有按空值切段的逻辑不动,段数对得上时把第 k 段命令挂到第 k 个元素上(只有 port 因底边非法多切一刀时对不上,那一段退回按顶点画)。只有平滑时才换用路径包围盒。
- `Stack` 记下每个系列被堆叠在哪个系列上(`OnSlot`);图表据此给折线规格填 `StackedOnSmooth`。

### 基准

- `tools/advchart-oracle/line-smooth.js` 真跑 ECharts 6.1,79 个用例、115 条折线系列,18 条守卫:平滑量的各种写法、单调 x/y(含反向轴、折返的值轴)、不等距值轴、横向折线、反向轴、空值(断开/连接、首尾空值、面积)、重合点和极短段、一两三个点、面积、六种堆叠、step 加平滑、时间轴、dataZoom、符号、对数轴、极坐标,以及画廊里 18 个用了平滑的文件。
- `test.advchart.linesmooth` 把每个系列的折线元素和面积元素上的命令按顺序接起来,和上游逐条逐数比较前 200 条、用 SHA-1 摘要比较全部,平滑时比较路径包围盒;另有 `smooth` 读取的单元测试,和一个像素测试(曲线中点偏离弦 3px 以上、那里有墨)。

### 变异测试

26 个。第一轮 1 个存活:单调切线在 `next − prev` 为 0 时的方向——没有折返的值轴用例。补 M6 后全杀。

### 已知偏差

- 画廊里有几张图(bump-chart、几张 K 线的均线、line-graphic 等)坐标轴标签的测量和上游不同,网格跟着移,这些系列的路径不比较(按首点判定,测试限定不超过 30 条)。
- 极坐标折线还没有移植。
- 单点面积上游是退化的 `M L Z`,这里不发元素(都画不出东西)。
- 上游 canvas 在画之前把路径数字再取一次 float32(`toStatic`),这里按双精度画,差别在亚像素以下。

### 下一批

回画廊缺口清单:heatmap(12,其中日历坐标 10)与 markLine/markPoint/markArea(合计约 20 个文件)是下一批的候选。

## 98. Tier 1 第六十四批:标注的模型、变换和布局(M1,2026-09-29)

画廊里 markPoint/markLine/markArea 出现在约 20 个文件里,一直不读。标注分四批:M1 只出数字(哪些条目留下、落在哪里、链上读到什么),M2 画 markLine,M3 画 markPoint,M4 画 markArea。

### 上游的做法

- **模型链**:预处理让顶层 `markPoint`/`markLine`/`markArea` 在有系列用到时总存在,它是每个系列标注模型的父模型,自己的选项和默认值合并(作者的键优先)。一个键按 条目 → `series.markX` → 顶层 markX → 默认值 找。系列的 `markX` 没有 `data` 就没有标注;图例关掉的系列不画标注。
- **dataTransform**:没给 x/y 像素、也没给 `coord` 数组的条目,`type` 为 min/max/average/median 时先算统计量,再找**离它最近的那个数据**(值轴局部坐标里比,等距时取在目标之前的一侧,完全相同取第一行)——四种统计都落在某个真实数据上;堆叠时在堆叠结果上找、位置取堆叠值,`value` 取原始值,位置再按**原始值**的精度 `toFixed`(0.125 + 0.25 的堆叠点 0.375 画在 0.38)。没有 type 的条目 `coord = [xAxis, yAxis]`。`coord` 里写 `'min'`/`'max'`/`'average'`/`'median'` 的,按那一维直接算,不找最近、不取整、不管堆叠。
- **统计**:average 跳过空值;median 把数字排序,但用 `count()`(**含空值行**)算下标——`[-,10,20,30,40]` 的中位数是 30,空值够多时读出数组、得 NaN;空序列 median 是 0,min/max 是 ±Infinity。
- **过滤**:`containData` 用刻度的**映射范围**(柱、象形柱、K 线、箱线图把类目轴两端各撑半个带宽),只要给了 x 或 y 像素就不过滤(`'center'` 被 `parseFloat` 当成没给,于是被过滤)。markLine 一维线看值是否在轴上;markArea 有一维是 ±Infinity 就留下,否则看两角的矩形和网格相交。
- **markLine 一维**:`xAxis`/`yAxis` 常数(同时写时 `yAxis` 优先,字符串原样保留),或统计量(在**堆叠结果**上算,不找最近数据),按 `precision`(默认 2,链上读,封顶 20)取整;起点在基轴 `-Infinity`、终点 `+Infinity`,布局时换成轴的两端(`getExtent()[0]`/`[1]`,反向轴已反)。线条目按 `{type, valueIndex, value}` → 起点 → 终点合并、不覆盖:**成对的线 type 永远是 null**,起点的 value/name 先到先得(bar-stack 的 `[{type:'min'},{type:'max'}]` 的值是最小值)。
- **布局**:x/y 按容器(markPoint 的 `relativeTo: 'coordinate'` 按网格,且网格左上角加到**数字**上也加);柱和象形柱先 `clampData` 到**有效范围**再加上本系列柱在带里的偏移 `offset + size/2`(方向看坐标系的基轴);其他类型直接 `dataToPoint`。markArea 先 `clampData`,柱系列在类目轴上贴到刻度坐标(终点角取下一刻度,`alignWithLabel` 时不加);`allClipped` 按有效范围判断,裁掉的不画多边形。
- **视觉**:markPoint 的符号选项按链读(默认 pin、50);markLine 每端的 symbol/symbolRotate/symbolOffset 只读自己再取系列那对中的一个,**symbolSize 顺链读**——默认 `[8, 16]` 整个落到两端。
- **z**:series 2、markArea 1(在系列下)、markPoint/markLine 5;`get('z') || 0`,silent 是标注的或系列的。
- 上游改写它拿到的选项(像素条目写进 `coord`,`coord` 里的 `'min'` 换成数字);不认识的元素(没有 type/xAxis/yAxis 的一维 markLine、不成对的 markArea)在渲染时抛异常。

### port 以前

- 三种标注都不读;顶层 `markLine: {z: -100}` 在编辑器里报"未知选项"。
- 直角坐标系列的默认 z 是 0(上游 2),markArea 的 z 1 会盖在系列上。
- K 线和箱线图不撑开类目轴的映射范围:缩放后的 candlestick-sh(`boundaryGap: false`)蜡烛整体差半个带宽。
- 提示框找最近数据用全局坐标比差值,平局时最后一位可能和上游相反。

### 做法

- 新单元 `tyControls.AdvChart.Marker`:JS 值记录(undefined/null/数字/字符串/其他)、模型链读取和默认值、`TyMkNumCalculate`、`TyMkNearestRows`(局部坐标)、逐字转写的 dataTransform/getAxisInfo/统计定位/过滤/markLine 与 markArea 变换/`clampData`/`getMarkerPosition` 两个分支/无穷端换轴端/x·y 像素;不改选项;上游会抛异常的元素跳过(不计 dataIndex)。
- 图表:`Relayout` 在柱布局之后调 `SolveMarkers`,每个直角坐标系列三块结果;`MarkerLayout(seriesIndex, kind)` 读出。`NearestOnAxis` 改用 `TyMkNearestRows`。
- 直角坐标系列默认 z 改为 2(`Marks`、`Pie` 的默认一并改)。
- `Series` 的 containShape 覆盖 bar、pictorialBar、candlestick、boxplot 四种。
- 编辑器:顶层 markPoint/markLine/markArea 按系列标注的目录节点校验。

### 基准

- `tools/advchart-oracle/markers-layout.js` 真跑 ECharts 6.1,54 个用例(39 个合成、15 个画廊文件),268 个标注条目,20 条守卫;每个用例跑两遍(原样一遍、给元素打标签一遍)得出每个原始元素的去留。
- `test.advchart.markerslayout` 逐字段比较:块的 z/zlevel/silent/count/precision,每个条目的去留、dataIndex、coord、存储值、value、name、端点和四角坐标、allClipped、符号视觉;两根轴的有效/映射范围。画廊里 scatter-weight 两个系列的网格因 containLabel 标签测量不同而移位,跳过(限定不超过 3 条)。另有:上游会抛异常的元素被跳过、两次渲染一致且选项不变、中位数计空值、系列默认 z。

### 变异测试

51 个。第一轮 3 个存活,都是夹具里"答案碰巧一致":
- 平均值不跳过空值:`[-,10,20,30,40]` 的平均 25 和 20 都落在数据 20 上。补 L10(一维平均线直接用统计量)杀掉。
- 两个无穷都换成轴端:值轴上被夹住的端点本来就在轴端。补 A6(类目纵轴,y 落在首末类目的带中心)杀掉。
- allClipped 不先排序:补 A7(反着写、跨过整个范围的区间)杀掉。

### 已知偏差

- 极坐标的标注没有移植。
- 上游遇到不认识的元素整张图渲染失败,这里跳过那个元素。
- `Time.parse` 对数字取整;dataZoom 那边的 `TyDzParse` 对时间轴数字不取整(本批的标注按上游取整)。

### 下一批

M2:markLine 的画面(线段、两端符号、标签位置和墨色)。

## 99. Tier 1 第六十五批:markLine 的画面(M2,2026-09-29)

M1 给出了每条线的两端;这一批把它画出来:线段、两端符号、标签。

### 上游的做法

- **合并出来的线条目**:线的 `lineStyle`、`label`、`z2` 读自 `{type, valueIndex, value}` 依次并入起点、终点条目的结果(不覆盖、对象逐键合并)——起点没写而终点写了的 `lineStyle`/`label` 会作用到线上;终点的 `itemStyle` 不参与。顶层 markLine 同样是它自己的选项并在默认值上。
- **线段**:颜色 `lineStyle.color`,否则起点的填充色(起点 `itemStyle.color` → 系列 markLine → 顶层 markLine → 系列色;K 线的系列色是默认的 `#eb5454`)。zrender 的 Line 在两端 `round(2x)` 相同时把**两端都**贴到起点算出的半像素上(宽 0 不贴;`round(0.4)` 当偶数宽)。虚线 `dashed` 是 `[4w, 2w]`、`dotted` 是 `[w]`,数字和数组原样、不乘线宽。
- **符号**:按整尺寸建(不是单位框缩放),盒子 `(-w/2 + 偏移, -h/2 + 偏移, w, h)`,偏移的百分比按尺寸算。给了非 NaN 的 `symbolRotate`(0 也算)就不再按切线转;否则起点 `π/2 − atan2(ty, tx)`、终点 `−π/2 − atan2(ty, tx)`。箭头的尖和 pin 的尖都在盒子中心——也就是端点上。填充是线的颜色;`empty*` 是线色描边、白填充、线宽 2;`line` 符号只描边;不认识的名字画成矩形;`square` 取短边、靠盒子左上。
- **标签**:默认文字是合并条目的 value(`round(v, 10)`,数字字符串先转数),没有 value 用 name,都没有是空串(不画)。`formatter` 的 `{a}{b}{c}` 各只替换**第一次**出现。位置表照 Line.ts:`start`/`end` 在端点外 `distance` 处,对齐看方向分量**严格**大于 0.8;`inside*`/`middle` 沿线转、`dir` 看切线的 x,旋转中心(origin)设在线上;不认识的位置落在原点。作者的 `align`/`verticalAlign` 覆盖算出来的,`'middle'` 对齐归一成 `'center'`,不认识的归成 left/top。`label.rotate` 替换线的转角,`label.offset` 平移并把旋转中心改为 `-offset`。
- **墨色**:没写颜色时外侧墨 `#333`(暗色 `#ccc`),外加地面色的光晕(宽 2);地面是选项的 `backgroundColor`(否则 transparent),暗不暗看 `darkMode`,否则看亮度 < 0.4。写了颜色就没有自动光晕;`color: 'inherit'` 取线色;不透明度默认跟 `lineStyle.opacity`。
- **z2**:标签的 z2 是**整个系列所有线**里到它为止出现过的最大 z2 加 2。

### port 以前

- markLine 只有 M1 的数字,不画。
- K 线没写颜色时占了色板第一个位置,旁边的柱子拿到第二个颜色(上游是第一个)。
- `TyZrSymbol` 把 pin、arrow、line 当矩形;`roundRect` 半径为 0 时仍走圆角路径。

### 做法

- 新单元 `tyControls.AdvChart.MarkerView`:合并视图(对象列表、先有键者胜、对象逐键合并)、`TyMkLinePictures` 逐字转写上面各条,出每条线的画面记录(线段路径与样式、两个符号的盒子/转角/变换/路径/颜色、标签的文字/位置/旋转中心/变换/对齐/字体/样式/墨色/z2);`TyBuildMarkLines` 把它变成绘制元素:线段用虚线折线,符号用 zrender 路径(圆弧转三次曲线),标签是带锚点和转角的答案标题。作者写的颜色原样用;上游的默认墨色和光晕换成皮肤的标签色和地面色(主题可定制原则)。标注元素暂时静默(标注的提示框还没移植)。
- `ZrPath`:`TyZrSymbol` 补 line、pin、arrow,`roundRect` 半径 0 退回矩形;`TyZrCubic`。`JsMath` 加 `TyJsAsin`(fdlibm e_asin.c,pin 的肩角要逐位)。
- 图表:`SolveMarkers` 算完布局就算画面,`MarkLinePictures(seriesIndex)` 读出;`BuildSeriesList` 在图例之前加入标注元素。`SolveSeriesColors`:K 线没写颜色时取 `#eb5454`、不占色板位。

### 基准

- `tools/advchart-oracle/markers-line.js`(代理写)真跑 ECharts 6.1,57 个用例(45 合成 + 12 画廊)、281 条线、35 条守卫:默认符号、四个方向的对角线、0.8 的边界、反向轴、零长线、半像素(线宽 1/2/3/0/0.4/1.5)、各种虚线、颜色回退链、全部符号类型与覆盖、12 个标签位置在横竖斜和从右往左的线上、距离标量与数对、对齐覆盖与归一、`label.rotate`/`offset`、默认文字与 formatter、字体、暗色地面、z/z2、图例隐藏、NaN 端点、柱。
- `test.advchart.markline` 逐字段比较画面记录(颜色按解析后的四个数比);没写 `color` 的选项注入上游 v6 默认色板,因为端口的默认颜色按设计来自皮肤。另有一个检查绘制列表里确有线段、两个符号和标签的测试。

### 变异测试

49 个。第一轮 8 个存活:
- 等价 1 个:两端各自做半像素——结果只取决于 `round(2x)`,两端相同时答案必然相同。
- 变异本身写错 2 个(`symbolRotate: 0` 改完仍是 0;formatter 只改了第二遍循环而第一遍只换了一个),重写后被 V2 杀掉。
- 夹具没覆盖的 4 个:补 V1(顶层 markLine 的 `label`/`lineStyle` 不是对象,合并时作者的键挡住默认值——没有标签)杀 1 个;V2(系列级 `symbolRotate: 0`、`[10, 0]` 的 roundRect、重复的 `{c}{b}`、低于 5e-5 的标签偏移)杀 2 个;asin 的分支由 js-math oracle 新增的 3031 行 `Math.asin` 和 `TestAsinIsV8sToTheBit` 杀掉。
- pin 的肩角换成 FPC 的 ArcSin 在这批夹具上看不出差别(pin 在 markLine 里少见),留给 M3——pin 是 markPoint 的默认符号。

### 已知偏差

- 上游的默认墨色(`#333`/`#ccc`)和光晕按选项地面算,端口画的时候换成皮肤的标签色和地面色;画面记录里仍是上游的值。
- 标注没有提示框和悬停强调(线宽 3),元素静默。
- 标签的富文本、背景框没有移植;字体按皮肤,作者给的字号和粗细才生效。

### 下一批

M3:markPoint 的画面(pin 的单位框缩放、inside 标签在 0.4 高处)。

## 100. Tier 1 第六十六批:markPoint 的画面(M3,2026-09-30)

### 上游的做法

- **符号**:`createSymbol(type, -1, -1, 2, 2)` 的**单位框**,按 `symbolSize / 2` 缩放——`[w, h]` 的 pin 是被拉伸的单位 pin,不是在 w×h 盒子里建的 pin(pin 的高是 `max(0.6w, h)`,两者不同)。符号组放在点上,路径的局部变换是 偏移 → 转角 → 缩放:`symbolRotate` 逆时针为正,`(r || 0) * π / 180 || 0`(非数字是 0);`symbolOffset` 是像素或尺寸的百分比,y 缺省取 x,不随缩放和转角。`''` 等空名字画**圆**,`'none'` 连标签一起不画,`symbolSize: 0` 不画符号但标签留在点上。
- **样式**:`itemStyle` 顺 条目 → 系列 markPoint → 顶层 markPoint → 默认(`borderWidth: 2`)读;填充缺省是系列色(K 线 `#eb5454`);`setColor` 后 `empty*` 是白填充、系列色描边、线宽 2,`line` 只描边(填充保留样式里的颜色),其余填系列色。描边不随缩放(`strokeNoScale`),画出来的线宽和虚线都除以线缩放(`|m0−1|` 与 `|m3−1|` 都大于 1e-10 才算,否则是 1)。
- **标签矩形**:符号路径的包围盒(描边时按线宽/线缩放撑开,没有填充时至少 5),经**全局**变换(组平移 × 局部)——`BoundingRect.applyTransform` 在非对角项小于 1e-5 时走快路径并翻正负宽高,否则取四角外包。
- **标签**:位置表是 zrender 的 `calculateTextPosition`,默认 `inside`、距离 5;pin 在恰好 `inside` 时把 y 放在矩形 0.4 高处;`'outside'` 当 `'top'`;数组位置不设对齐;不认识的位置落在矩形左上。默认文字是条目的 **value**(不是 coord),按最后一个不是类目/时间的坐标维取(值是数组时取那一维;两维都是类目或时间就没有文字),**不取整**;`formatter` 的 `{c}` 对数组值是逗号连接。
- **墨色**:`inside*` 且有填充时用内侧墨:填充亮度严格 > 0.5 是 `#333`、> 0.2 是 `#eee`,否则 `#ccc`;当"是否暗色模式"等于"墨色亮度 < 0.4"时描边为填充色(浅色地面上 `#eee`/`#ccc` 标签带 2px 填充色描边——默认 pin 就是)。其余位置用外侧墨 + 地面光晕。写了颜色或 `backgroundColor` 就没有自动描边;不透明度默认跟 `itemStyle.opacity`。
- **z2**:符号 z2 顺条目链(默认 0),标签 z2 是整个系列标注组里到它为止的最大 z2 加 2。

### port 以前

- markPoint 只有 M1 的数字,不画。

### 做法

- `MarkerView` 加 `TyMkPointPictures`(逐字转写上面各条,出画面记录:符号类型、组与局部/全局变换、单位框路径、包围盒、线缩放、样式与实际描边;标签文字、矩形、位置、旋转中心、变换、对齐、字体、样式、默认与实际墨色、z2)与 `TyBuildMarkPoints`(符号用 zrender 路径经全局变换;标签是答案标题,上游的默认墨换成皮肤的三档内侧色 `TyAdvChartLabelOn*`、外侧标签色与地面光晕)。
- 图表:`SolveMarkers` 一并算 markPoint 画面,`MarkPointPictures(seriesIndex)` 读出,绘制列表里在 markLine 之前加入。

### 基准

- `tools/advchart-oracle/markers-point.js`(代理写)真跑 ECharts 6.1,43 个用例(38 合成 + 5 画廊)、253 个标注、44 条守卫:各系列类型上的默认 pin、全部符号类型、空心符号、`[w, h]`/0/负尺寸、转角、偏移、keepAspect、系列级与顶层选项、itemStyle 各键与颜色回退、13 个标签位置、pin 的 0.4 规则、`label.rotate`/`offset`/对齐、formatter、字体、标签颜色/描边/背景、三档内侧墨的精确边界(亮度恰为 0.5、0.2)、暗色地面、半透明地面光晕、z/z2/silent、图例隐藏、NaN 点、`relativeTo`。
- `test.advchart.markpoint` 逐字段比较画面记录;另有检查绘制列表里确有 pin 和数值标签的测试。

### 变异测试

38 个,只有 1 个存活:pin 调用点换成 FPC 的 ArcSin。markPoint 的 pin 都是同一个单位 pin,肩角的参数只有一个值(0.4286…),FPC 在这一点上碰巧和 V8 一致——调用点等价;`TyJsAsin` 本身由 js-math 的 3031 行 `Math.asin` 逐位钉住。

### 已知偏差

- `path://`、`image://` 符号没有覆盖(keepAspect 只在它们上起作用);富文本标签(bar-rich-text)只记位置,不画富文本。
- 悬停放大、提示框没有移植,标注元素静默。

### 下一批

M4:markArea 的画面。

## 101. Tier 1 第六十七批:markArea 的画面(M4,2026-09-30)

标注系列的最后一批。

### 上游的做法

- **合并条目**:左上角条目、右下角条目依次并进一个对象(先有键者胜,对象逐键合并)——`itemStyle`、`label` 两角各写一半也会拼起来;名字取左上角的(左上写了 `''` 或 `null` 也会挡住右下角的)。
- **多边形**:四个角 `M L L L Z`;`allClipped` 的区域不画多边形、不画标签,也不参与 z2 累计。
- **填充**:条目写了颜色就用(`'transparent'`、`'none'` 照留);否则系列色经 `modifyAlpha(色, 0.4)`——**替换**原来的 alpha,打印成 `rgba(r,g,b,0.4)`;系列色是渐变对象时原样用;系列色解析不了时 `modifyAlpha` 给 undefined,结果**没有填充**。描边没写就是系列色本身(默认线宽 0,不画)。
- **标签**:默认文字是名字(没有就是空串),`formatter` 的 `{c}` 是合并条目的 value;默认位置 `top`,`position: ''` 当 `inside`。标签矩形是多边形的包围盒(有描边时撑开),没有变换。markArea **不**把 `itemStyle.opacity` 传给标签。`inherit` 色是填充去掉透明度(`modifyAlpha(填充, 1)`),渐变是 `#000`。内侧墨按含 alpha 的亮度(底为黑)分档,所以默认 0.4 透明的填充落在 `#ccc`/`#eee` 档,浅色模式下还带填充色描边;渐变填充是 `#ccc`、无描边。
- **z**:默认 1,在系列(2)下面。

### port 以前

- markArea 只有 M1 的数字,不画。

### 做法

- `MarkerView` 加 `TyMkAreaPictures`/`TyBuildMarkAreas`/`TyMkModifyAlpha`;把 M3 的标签样式、定位、墨色抽成共用的 `StyleLabel`(宿主填充是字符串还是渐变、默认不透明度、pin 规则都由调用方给),标签元素抽成共用的 `EmitLabel`。
- 图表:画面输入加系列色的非字符串形式(渐变);画面计算在屏蔽浮点陷阱下进行——不认识的类目会给出 NaN 角点,上游照画;绘制时跳过 NaN 的区域和标签。

### 基准

- `tools/advchart-oracle/markers-area.js`(代理写)真跑 ECharts 6.1,34 个用例(31 合成 + area-rainfall、line-sections、scatter-weight)、188 个区域、43 条守卫:类目/数值/时间轴、反向角、部分出界、`allClipped`、dataZoom 窗口、柱系列贴刻度、各种颜色字符串(rgba、hsl、8 位 hex、`transparent`、`none`、空串、解析不了的)、系列色回退(含渐变、K 线)、描边与虚线、描边撑开包围盒、两角合并、13 个标签位置、formatter、默认文字、字体、标签颜色与 `inherit`、三档内侧墨的边界、暗色地面、z/z2/silent、图例隐藏、NaN 角点。
- `test.advchart.markarea` 逐字段比较;另有检查区域在系列下面(z 1 对 2)、半透明、带名字标签的绘制测试。

### 变异测试

19 个,1 个存活且等价:渐变填充时去掉"填充是字符串"的判断仍不会给标签描边——渐变时传进来的填充串本来就是空的。

### 已知偏差

- 渐变填充的区域在端口里暂不画填充(只画描边和标签)。
- 标注的提示框、悬停强调没有移植。

### 标注系列小结

M1–M4 完成:markPoint、markLine、markArea 的模型、变换、布局和画面都按上游逐位对上;画廊里用到标注的 16 个文件中,除 matrix-stock(矩阵坐标系)和 bar-rich-text 的富文本标签外都画出来了。

## 102. Tier 1 第六十八批:直角坐标上的热力图(H1,2026-09-30)

热力图 / 日历系列的第一批。

### 上游的做法

- **格子大小**:每个方向是该轴 `calcBandWidth(axis).w + .5`——类目轴是一个类目带宽(像素跨度 ÷(范围跨度 + onBand),范围为 0 时当 1),多出的半像素压住邻格之间的缝;数值轴、时间轴给 NaN,**整个系列什么也不画**。
- **跳过**:值、x、y 有一个不是数,或者 x/y 落在刻度范围外(闭区间,按存储的原值判断,不是类目取整后的值),这一行不画。
- **位置**:点坐标减去半个格子,没有亚像素对齐,不裁剪。
- **样式**:系列样式 → visualMap → 条目 `itemStyle`,所以条目色压过 visualMap,visualMap 压过系列 `itemStyle.color`;`visualMap: false` 的条目保留系列色。圆角取条目的 `itemStyle.borderRadius`,没有就取系列的;没写就是普通矩形。
- **标签**:默认文字是原始条目第三个元素照写的样子(`'07'`、`' 3 '`、`'Infinity'` 都原样),没有就是 `'-'`;默认位置 `inside`,默认不透明度跟格子,`inherit` 色不继承,走自动墨色。`{c}` 是整个原始数组。名字取条目名,没有就取第一个类目维度的类目。
- **z**:系列 2,格子 z2 0,标签 z2 2。

### 顺带修的

- **折线的默认 z 是 3**(LineSeries.ts:161),以前按 2 算,所以同图里的柱子如果声明在后,会盖住折线。钉住旧值的两个测试一起改了。
- **条目自己的 `label`**:以前标签只读系列上的配置;现在数据条目的 `label` 叠在系列配置上(`TyLabelSpecOfNode`),标题元素带着条目下标,展开标签时按 `[系列][原始行]` 查表。
- **标签框按宿主描边撑开**(zrender getBoundingRect):撑开线宽,宿主没有填充时至少 5,两边各一半。
- **`align` / `verticalAlign`(及别名 `baseline`)** 现在会被读取并覆盖位置给出的对齐。
- **数组位置里的百分比**以前被当成像素;现在是宿主矩形的比例,纯数字仍是逻辑像素乘缩放。
- **带小数的类目位置**(比如 2.5)没有名字,以前取整后拿了邻近类目的名字。

### 做法

- `Marks` 注册 `BuildHeatmap`:两根类目轴才画;值从原始条目第三格读(`''`、`'-'` 当空);条目的描边色、线宽覆盖;圆角按原始行查。
- `LabelOpt` 加默认文字 `tldRawThird`;`Labels` 的 `TyExpandLabels` 加条目标签表重载、描边撑开、百分比位置、对齐覆盖。
- 图表:热力图的半像素按 PPI 换算;系列与条目圆角由 `HeatmapRadii`/`HeatmapItemRadii` 读出。

### 基准

- `tools/advchart-oracle/heatmap-cartesian.js`(代理写)真跑 ECharts 6.1,38 个用例、736 行、587 个格子、42 条守卫:画廊的直角坐标热力图、类目轴 boundaryGap、数值/时间轴(不画)、NaN 与出界的行、带小数的位置、反向轴、dataZoom 过滤与不过滤、两个网格、没有 visualMap(G16,用调色板色)、visualMap 连续/分段/超界、`visualMap: false`、条目色、圆角的各种写法、描边、标签位置/对齐/百分比数组/formatter/默认文字、z 与 silent。G12–G17 在开发版上会抛异常,用生产版跑。
- `test.advchart.heatmap` 逐格比较矩形(精确)、圆角、填充、不透明度、描边、标签文字、锚点和对齐;另有折线在柱子上面的绘制测试。基准注入上游调色板和 `gradientColor`,因为端口的默认色按设计来自皮肤。

### 变异测试

24 个,1 个存活且在直角坐标上等价:去掉默认文字 `'-'`——没有第三个元素的行值是 NaN,整格不画,`'-'` 永远不会出现。它在日历上可达(`[日期, 值]` 的原始数组没有第三格),到 H3 会被钉住。

### 已知偏差

- 上游的一个疏漏没有照抄:位置不对应类目的行(如 2.5),在 dataZoom 过滤后按原始下标去存储里拿名字,拿到的是别的行的(G7 的 4.5 那格读出 `'x3'`);端口给空名字。
- 热力图的值固定读原始条目的第三格,`encode` 把值映射到别的列时还不支持。
- 提示框、悬停强调、渐进渲染没有移植。

## 103. Tier 1 第六十九批:日历坐标系和它的画面(H2,2026-09-30)

### 上游的做法

- **日期**:日历只认本地时间,不看 `useUTC`。字符串日期在任何时区都落在同一格;数字时间戳落在运行那台机器上的那一天。
- **盒子合并两遍**:第一遍是 mergeDefaultAndTheme 的按个数合并,默认 `left 80, top 60` 只在没写时补上;第二遍在 cellSize 是数字的方向上开 ignoreSize。写了 `width`,或同时写了 `left` 和 `right`,那个方向的 cellSize 会先被强制成 `'auto'`,哪怕作者写的是数字。第二遍里用户写 `right` 会把默认的 `left` 置空,只在 ignoreSize 的方向上。
- **矩形**:整个画布上的 getLayoutRect,没有边距,也不夹住(默认 `'2017'` 宽 1060,超出 800 的画布)。数字 cellSize 先乘格数当宽高,`'auto'` 的方向用矩形除以格数。
- **范围**:一个元素的数组先拆开;非数组走 `toString()`,四位数字是一整年,`yyyy-m`(分隔符 `/`、`-`,正则里的 `|` 也算,但随后解析失败)是一个月,`yyyy-m-d` 是一天;数组原样取,倒序的会交换。
- **格子**:`(rect.x + 第几周*sw + sw/2) - sw/2`——先算中心再减半格,小数格宽下和直接乘不逐位相等。内容区按格子边框宽度的一半往里收,先收宽度再挪 x,收不下时塌成格子中心的 0×0。
- **范围判断**:比的是完整时间,`时间 >= 起点 && 时间 < 终点 + 一天`,所以 `…T23:59:59.999Z` 在范围内。
- **画面**:日格(z2 0);范围起点、范围内每个月一号、终点后一天各一条 14 点的阶梯折线,再加两条两头各伸出半个线宽的边线(z2 20);年、月、星期名(z2 30)。年在左右时转 π/2,从下往上读。
- **名字**:`nameMap` 只认大小写完全一致的 `'EN'` 和 `'ZH'`,其余字符串(画廊里的 `'cn'`)都回落到图表的语言;数组按周日为 0 取,取不到的那项不画。星期名是 `dayOfWeekAbbr` 的第一个字。
- **formatter**:`formatTplSimple`,每个键只换第一次出现,按参数顺序;替换串里的 `$&`、`$$` 等照 `String.replace` 生效。
- **字体和颜色**:全局 `textStyle` 的字号、字体、粗细会落到月和星期上,颜色不会;年有自己的默认值 20、bolder、sans-serif,压过全局。
- **z**:日历默认 z 2,和系列一样,顺序全靠 z2。

### 做法

- 新单元 `tyControls.AdvChart.Calendar`:`TyCalendarSpecOf` 读选项并照上游合并两遍盒子(`TyCalMergeLayoutParam` 逐行移植 mergeLayoutParam,区分「没有这个键」和「有键但是 undefined」);`TTyCalendar` 实现 `ITyCoordSys`,日期先换成墙上时间,之后全用整天算(一周里第几行、第几周、每月一号),时区只在换算时问一次;`TyBuildCalendar` 按 CalendarView 的顺序出图元。
- 上游 `_getRangeInfo` 的夏令时修正循环不需要:墙上时间没有夏令时。午夜切换夏令时的时区(上游自己在那里少一天)是两边唯一可能不同的地方。
- `UTC` 属性是测试缝:基准在 `TZ=UTC` 下生成,测试打开它就能在任何机器上比较。
- 控件:`SolveCalendars` 在画布上排版每个日历,`BuildSeriesList` 在任何系列之前把日历画进同一个绘制列表(和雷达一样,在「没有系列」的提前返回之前,所以只有日历也会画)。`CalendarLayout(i)` 取排好的日历。
- 颜色按主题规则取现成的键:日格填空心符号用的地面色,格线是分隔线,月线是轴线,月和星期名是轴标签,年是副标题的墨色。作者写的颜色照用。
- 星期名来自库的语言规则(`TyDateTimeNames`):取缩写的第一个字;中文缩写写成「周日」「星期日」时取最后一个字,和上游 ZH 表一致。

### 基准

- `tools/advchart-oracle/calendar-layout.js`(代理写)真跑 ECharts 6.1,78 个用例、103 个日历、11938 个图元:§2.1 盒子表的每一行及更多盒子写法、横竖两个方向、各种范围写法(数字、年、月、`/`、单日、数组、倒序、单元素数组、跨年、闰年二月、月中、数字时间戳)、firstDay 0/1/3/6/`'1'`、标签位置/对齐/边距(含百分比和非法字符串)/显示开关/nameMap/formatter(含重复键和 `$` 模式)/字体颜色/全局 textStyle、格子和分隔线样式(边框 0/0.5/3、虚线、点线、透明度、收缩塌陷)、z、暗色,以及 10 个画廊文件的日历(去掉系列)。每个日历还有 11 个探针日期走 dataToPoint / dataToLayout / dataToCalendarLayout。13 条变异守卫。
- `test.advchart.calendar` 逐位比较矩形、格宽、范围信息、每个日格、每条折线的每个点、每个标签的文字/锚点/旋转/对齐/字号,以及全部探针;颜色用哨兵墨色验证「默认=皮肤、写了=作者」。另有控件级测试:只有日历、没有系列的图表也画出 28 格、4 条线、9 个名字。

### 变异测试

43 个,5 个存活,都已判为等价:

- 盒子第一遍合并整个跳过、`'auto'` 算作有值、按优先级补一个参数:单次 `setOption` 里第二遍在每个方向上都会重现第一遍的结果,优先级补上的只可能是「有键但 undefined」的值。它们要到 `mergeOption` 才有区别,而端口没有移植 `mergeOption`。
- 分隔符里的 `|`:`'2017|2'` 匹配上之后解析失败,不匹配则范围无效,两条路都是不画。
- 起点所在月的「先跳回一号」:端口的月步进本来就落在下个月一号,这段是多余的,已删掉。

### 已知偏差

- 标签锚点不是数(月份边距写成 `'10%'`)时,上游的文字落在 y = -6,基本在画布外;端口不画。
- firstDay 不是 0–6 的整数时上游的阶梯折线会有空洞,端口按取整后的行放点。
- 名字取的是库的语言规则而不是上游的图表语言;测试把语言钉在英文资源串上。
- 字符串边距遇到 `position: 'end'` 时上游会做字符串拼接,端口按数字处理。
- 日历上的系列(热力图、散点、涟漪、关系图、饼图)还没有画——下一批。

## 104. Tier 1 第七十批:日历上的热力图(H3,2026-09-30)

### 上游的做法

- **维度**:日历给系列两个维度,`time` 和 `value`;行的第 0 个元素是日期,第 1 个是值,更多的元素是原始位置(`value0`…),标签和 visualMap 会读到它们——第一行有第三个元素时,visualMap 的默认维度就变成那个多出来的元素,不再是值。
- **格子**:日历的 `dataToLayout(日期).contentRect`——当天的格子按日历自己的边框宽度的一半往里收。**没有**直角坐标上那半像素的放大;收到 0×0 的格子也照画。
- **跳过**:值不是数的行,或日期不在范围内(内容区的 x/y 是 NaN)的行。
- **z**:格子 z2 固定为 1,系列写的 `z2` 不起作用——压在日历的日格(0)上面、月线(20)和名字(30)下面。标签 z2 是 3,同样在月线下面;所有格子先画,再画所有标签。
- **标签**:默认文字仍是原始数组的第三个元素,`[日期, 值]` 的行没有第三个,所以是 `'-'`。
- **引用日历**:`calendarIndex` 或 `calendarId`,都没写就是第一个日历。

### 做法

- `Series`:绑定加 `CalendarIndex`,`coordinateSystem: 'calendar'` 按 `calendarIndex` / `calendarId` 解析(把各日历的 `id` 收集起来交给解析器),解析成功后 `HasAxes` 为假,和雷达一样。
- 控件:日历系列的数据存储是 `time`(时间)和 `value`(浮点)两列;画的时候日历系列不进直角坐标的路径,热力图走 `TyBuildCalendarHeatmap`。
- `Marks`:热力图一格的样式(行的视觉、条目自己的边框和圆角、标题)抽成两种坐标系共用的 `HeatCell`;日历上的格子取内容区、z2 设为 1。
- 日历读日期时按 JS 的 `Math.round` 取整毫秒,零点前不到一毫秒的小数时间戳会进到下一天,和上游一致。
- 上游只取时区偏移里的小时(`'+00:30'` 不偏,`'-05:30'` 偏 5 小时),端口的日期解析本来就是这样(TIME_REG 逐字移植时就只读小时)。

### 基准

- `tools/advchart-oracle/heatmap-calendar.js`(代理写)真跑 ECharts 6.1,30 个用例、49 个热力图系列、4701 行、3359 个格子:日期写法(带时刻、`Z`、各种偏移、数字和小数时间戳、斜杠、非法、`24:00`、`true`)、值写法、同一天多行、formatter、13 种标签位置、条目与系列的边框/圆角/颜色、visualMap 连续/分段/超界、没有 visualMap、日历边框 0/0.5/3 和塌陷、竖排、firstDay、两个日历按下标和 id 引用、z/z2/zlevel、图例隐藏、暗色、多出来的维度、值维度被猜成类目,以及 7 个画廊文件(calendar-simple、heatmap、horizontal、vertical、lunar,以及 charts 和 graph 里的热力图)。28 条变异守卫。
- `test.advchart.heatmapcal` 通过控件画一遍,逐格比较矩形(精确)、z/z2、圆角、填充、不透明度、边框、标签文字/锚点/对齐,并检查标签在自己的格子之上、月线之下。日期是数字或自带偏移的行落在哪一天取决于时区,只在本机时区为 UTC 时比较。

### 变异测试

11 个,全部杀死(第 68 批留下的「默认文字没有 `'-'`」也在这里被 `[日期, 值]` 的行杀死)。中途两个存活:

- 给日历系列设标签的值列:热力图的标签从不读它(`{c}` 是整个原始数组,`{@value}` 按名字,默认文字是原始第三格),这行是死代码,已删。
- 日历读日期时不按 JS 取整:用得上的只有数字时间戳的行,本机不在 UTC 时区就跳过了;而在一天的边界上 FPC 的 `Round` 本来就和 `Math.round` 一致。能看出差别的是范围判断——比起点早 0.4 毫秒的时刻取整后正好是起点,在范围内。补了一个直接测日历的测试。

### 已知偏差

- 上游在值维度被猜成类目(前几行里有非数字的字符串)时保留原始值,`isNaN(null)` 和 `isNaN('')` 为假,于是值为 `null` 或 `''` 的行也会画出格子;端口按数读值,这两种行是空缺。
- 散点、涟漪散点、关系图、饼图在日历上还没有画——下一批。

## 105. Tier 1 第七十一批:日历上的散点和涟漪散点(H4a,2026-09-30)

### 上游的做法

- **位置**:日历的 `dataToPoint([时间, 值])` 只看日期,落在当天格子的中心;值不是数也照画(`'-'`、`null`、缺值都有符号),值从不拿来当尺寸;日期不在范围内就没有点。日历没有面积,不裁剪。
- **符号**:`symbolSize` 走 `normalizeSymbolSize`——数字(或数字字符串)是正方,数组照写,`[a]` 是 a 宽、高为 0;`symbolOffset` 单个值当两个,百分比是符号自身宽/高的比例;条目自己的 `symbol`、`symbolSize`、`symbolRotate`、`symbolOffset` 压过系列的,数组也算。尺寸为 0 的符号仍是一个元素——不画东西、挂着标签,画廊里只显示文字的系列(calendar-pie 的日期、calendar-lunar 的农历)就是这么写的。
- **z2**:符号 100(Symbol.ts:85,系列的 `z2` 选项够不到它),加 visualMap 的 liftZ;标签 102。所以符号在日历的月线(20)和名字(30)上面。这一条在直角坐标上也一样。
- **effectScatter**:符号之外有 `rippleEffect.number` 个涟漪(默认 3、`brushType` 默认 `'fill'`),z2 99、不响应鼠标;`showEffectOn` 不是 `'render'` 时没有涟漪。服务器端渲染只停在动画的第一帧:每个涟漪都是同一个符号形状、同样大小、不透明度 1——描边时正好是符号边上的一圈,填充时被符号盖住。条目可以写自己的 `rippleEffect.number`。

### 做法

- `Marks`:散点一个符号的整段逻辑抽成 `AddScatterSymbol`,直角坐标和日历共用;日历上走 `TyBuildCalendarScatter`。effectScatter 进渲染器表,用同一个散点构建器,涟漪由视觉记录里的 `Ripple*` 字段决定(控件的 `RippleOf` 读选项)。
- 条目自己的符号选项:控件用 `TySymbolSpecOf` 把每个对象条目读成一份完整的符号规格(`SymbolItems`),数组形式也在内;按原始行取。
- `Symbol`:数字字符串的 `symbolSize`、`[a]` 高为 0、单个值的 `symbolOffset`、百分比偏移(`TySymbolResolveOffset` 在行的尺寸定下之后换算)。
- 散点和涟漪散点的条目自己的 `label` 也读了(第 68 批给热力图做的那套)。
- **顺带修的一个真缺陷**:`TySeriesVisual` 是逐字段填的,新加的布尔和整数字段没写进去就是栈上的垃圾值——一个普通散点拿到随机的「有涟漪」和几十亿的涟漪数,画不完。现在新字段都显式清零。

### 基准

- `tools/advchart-oracle/series-calendar.js`(代理写)真跑 ECharts 6.1:散点/涟漪散点/关系图/饼图在日历上,共 20 条守卫。这一批用其中散点和涟漪散点的部分:9 种符号、尺寸/旋转/偏移的各种写法、值和日期的各种写法、同一天多行、条目样式与标签、两种涟漪画法、条目涟漪数、`showEffectOn: 'emphasis'`、zlevel,以及 calendar-charts、effectscatter、pie、lunar 四个画廊文件里的散点系列。
- `test.advchart.seriescal`:通过控件画一遍,逐行比较有没有画、中心(含偏移)、尺寸(圆、矩形、圆角矩形、菱形;转过的圆和转了四分之一圈的矩形)、z/z2、填充/空心的笔色、不透明度、涟漪个数与画法、标签文字/锚点/对齐。数字日期的行只在 UTC 时区的机器上比较。
- `test.advchart.symbol` 加了单个值偏移与百分比偏移的直接测试;`test.advchart.visualmapchannels` 改为期望尺寸为 0 的符号是一个元素、liftZ 叠在 100 上(原来钉的是端口旧的行为)。

### 变异测试

24 个,全部杀死。中途的存活都是覆盖缺口:转过的符号原来不比尺寸、条目的 `symbolOffset` 原来根本没读、系列上单个值的偏移没有用例——各自补了比较或测试。原先按覆盖表读条目标量的 `ItemSymbol` 在改成整份读条目规格后成了死代码,已删。

### 已知偏差

- 涟漪的动画没有移植,只画上游服务器端渲染的第一帧。
- `rippleEffect` 的 `period`、`scale` 只影响动画,静态画面用不到;emphasis 状态没有移植。

## 106. Tier 1 第七十二批:日历上的关系图和饼图(H4b,2026-09-30)

热力图/日历系列的最后一批。

### 上游的做法

- **关系图**:上游建关系图的数据时用的是普通维度名,所以节点的日期**不是**时间维度——它的类型由第一个能下结论的节点猜(guessOrdinal:有限的数或数字字符串算浮点,别的字符串除了 `'-'` 都算类目)。类目列把日期原样存着,浮点列把日期字符串变成 NaN。simpleLayout 只要节点**任何一个**存下来的维度是数就放它,而日期字符串的 `isNaN` 为真——于是一个日期是字符串、值不是数的节点根本不放;第一个节点用时间戳时,后面日期是字符串的节点全丢。位置是日历对存下来的日期做 `dataToPoint`(日历自己解析日期,越界为 NaN)。边两端都放了才画;边 z2 0、节点 z2 100——所以同一个日历上热力图的格子(1)会盖住边。
- **饼图**:`createBoxLayoutReference` 拿饼的坐标去问日历的 `dataToLayout`——坐标是写了的 `coord`,否则是把 `center` 当日期读。饼的盒子和百分比半径以那一天格子的内容区为参照;坐标来自 `center` 时圆心是内容区自己的中心(盒子只影响半径),来自 `coord` 时 `center` 在盒子里照常取百分比。日期越界时格子保留尺寸、没有位置:半径还是数,圆心不是,什么也看不见。扇区 z2 2。

### 做法

- 关系图:`TyGraphSolveAtPoints`——节点放在调用方给的点上(按原始下标,NaN 即不放),边照非 view 坐标系的 simpleLayoutEdge;控件的 `CalendarGraphPoints` 照上游的维度猜测和放置规则算出每个节点的点。
- 饼图:`SolveCalendars` 挪到 `SolvePies` 之前;日历上的饼走 `CalendarPieLayout`,容器是内容区,来自 `center` 时覆盖圆心(连同每个扇区的圆心);没有位置的格子让整个饼无效,不画。日历系列的 time/value 存储不给饼(饼用自己的值列)。

### 基准

- 沿用 `tools/advchart-oracle/series-calendar.js` 的关系图与饼图部分:5 个节点 4 条边(字符串日期带 `'-'` 值、非法日期、时间戳带 `'-'`、曲边、边两端符号)、第一个节点是时间戳的图、8 个饼(固定半径、百分比、内外半径、越界、没写 center、`coord` 加百分比 center、`width: '50%'`、逆时针)、两个日历按下标/id/默认引用,以及 calendar-charts、calendar-graph、calendar-pie 三个画廊文件。
- `test.advchart.seriescal` 新增一个测试:关系图逐节点比较放没放、位置(精确),以及可画的边数;饼图逐扇区比较圆心(精确)与内外半径。

### 变异测试

11 个,3 个存活:

- 关系图的范围判断关掉:基准里没有落在范围外的节点(散点那边同一个 `DatePoint` 有覆盖,这条路径上没有)。记下,不算等价。
- 节点按视图行而不是原始下标取点:没有图例按类目筛选时两者相同,等价。
- 饼拿到日历的 time/value 存储:那个存储的值列恰好也叫 `value`,标量数据也落在它里面,结果相同,等价;排除语句保留,说明意图。

### 已知偏差

- 边的端点截短、曲边采样、饼的标签位置在这一批只记录不比较(直角坐标上的关系图和饼图各自已有测试)。

### 热力图/日历系列小结

H1–H4b 完成:直角坐标热力图、日历坐标系与它的画面、日历上的热力图、散点、涟漪散点、关系图、饼图,都按上游逐位对上;画廊的 10 个日历文件除 custom-calendar-icon(renderItem 是函数)外都画出来了。

## 107. Tier 1 第七十三批:树图——层级、正交布局、节点、曲边、标签(T1,2026-09-30)

层级系列(树图/矩形树图/旭日图,画廊共 19 个文件)的第一批。调研在 scratchpad/wf73:upstream.md、gallery.md、port.md。

### 上游的做法

- **层级**:`series.data` 挂在一个以系列名命名的**虚根**下面,数据行就是这棵树的**先序**:第 0 行是虚根,第 1 行是 `data[0]`。只有 `data[0]`(真根)参与布局;其余的根有数据行、没有位置。虚根深度 0,真根 1。
- **展开**:写了 `collapsed` 的节点照它(`collapsed != null` 才算写了);其余节点深度 ≤ `initialTreeDepth`(默认 2)才展开——真根和它的子节点展开,孙节点看得见但收着,更深的看不见。`expandAndCollapse` 为假、或 `initialTreeDepth` 不是 ≥0 的数(`-1`、非数字字符串)时一律展开;`null` 按 0 算。收起的节点对布局来说是叶子,它的后代没有位置。
- **盒子**:系列走 `box` 布局:没写的 `left/top/right/bottom` 补 `12%`,再做一遍按个数的 `mergeLayoutParam`——写了 `left` 和 `width` 时默认的 `right` 被丢掉。
- **布局**:layoutHelper.ts 就是 d3-hierarchy 的 tree(Reingold-Tilford / Walker):可见节点后序 firstWalk(executeShifts、apportion 的线程与祖先、moveSubtree),先序 secondWalk;同父兄弟间距 1、堂亲 2。然后找最左、最右(并列时先序在前者胜)、最深的节点,`delta = (最左 === 最右) ? 1 : 间距/2`,再按朝向缩放进盒子:LR/RL 的横向是深度、纵向是广度,TB/BT 反之;RL、BT 镜像;`(最深 - 1) || 1` 防单节点除零。运算顺序照原文,不能化简。
- **节点**:默认 `emptyCircle`、7px。空心符号一律 2px 的环(**写死**,盖过 `itemStyle.borderWidth`),环色是节点色,中间是白;收起且有子节点的节点实心。z2 100。
- **边**:每个非真根可见节点一条三次贝塞尔,从父到子,用**子**节点的 lineStyle;控制点 LR/RL `(s.x + (t.x - s.x)·c, s.y)`、`(t.x + (s.x - t.x)·c, t.y)`,TB/BT 对称;曲度只读系列的 `lineStyle.curveness`(默认 0.5)。z2 0——所有边画在所有节点下面。
- **`leaves`**:叶子和收起的节点读 label、itemStyle、lineStyle 时先过 `leaves` 再到系列——但**符号**只读条目自己和系列。
- **标签**:默认显示节点名,位置默认 `inside`(四个朝向都是);标签矩形是符号的单位路径框按描边在单位空间里撑开、再经符号的完整变换(旋转也算)得到的框。
- **颜色**:树的默认色写在系列默认值里(节点 lightsteelblue、边 #cfd2d7),所以**不占色板位**。

### 做法

- 新单元 `tyControls.AdvChart.Tree`:`TyHierarchyOf`(显式栈的先序,行号即上游 dataIndex)、`TyTreeFillStore`(每行一个去掉 `children` 的浅拷贝交给 Builder 新导出的 `TyFillSeriesStoreArray`)、`TyTreeSpecOf`(盒子沿用日历的 `TyCalMergeLayoutParam`)、`TyTreeApplyExpand`(JS 的真值与 `>= 0` 语义)、`TyTreeSolve`(Walker 算法按行号实现,四个朝向)、`TyTreeLabelSpecs`、`TyBuildTreeMarks`(真正的三次曲线路径命令,不采样)。
- 控件:存储分支(在日历分支之前)、`SolveTrees`、`TreeInk`、`BuildSeriesList` 里在展开标签之前画、色板里给树一个不占位的分支;标签的主题部分抽成 `LabelBaseFor`,树的标签默认显示、默认文字是名字。
- 主题:新键 `TyAdvChartTreeNode`(强调色的浅版,代替 lightsteelblue)和 `TyAdvChartTreeEdge`(边框墨);重新生成 DefaultTheme 与目录。
- **标签框**:`TySymbolLabelBox` 按 zrender 的算法算符号标签的参照框(单位框、描边在单位空间撑开、完整变换,pin 有自己的单位框);标题新增 `HasHostBox/HostBox`,展开标签时有它就用它、并用新的 `TyLabelAnchorXYWH` 按 x+w/2 的形式算锚点——原来按 Left/Right 反算宽度,会差最后一位。这一批只给树用;散点、关系图、标注各自的现有测试不受影响。
- **顺带修的真缺陷**:`TySymbolDefault` 逐字段填、新加的百分比偏移字段没写就是垃圾值——没写 `symbolOffset` 的系列可能被随机偏移。现在先 `Default()` 清零。

### 基准

- `tools/advchart-oracle/tree.js`(代理写)真跑 ECharts 6.1,74 个用例、75 个树系列:四个朝向和两个旧别名、径向、不对称树(强制子树移位)、单节点、单子节点、深链、20 个子节点的扇、`initialTreeDepth` 0/1/2/3/-1、`collapsed` 各种位置、`expandAndCollapse: false`、多个根、盒子写法、符号(系列/条目/`leaves` 被忽略)、空心与实心的样式层级、曲度、边样式层级、折线边、标签位置/旋转/显示开关/formatter/背景/`inherit`、值的各种写法,以及 7 个画廊文件(强制关动画)。25 条变异守卫,另有 210 棵随机树与独立转写逐位一致。
- `test.advchart.tree`:通过控件画一遍,逐行比较有没有画、节点位置(精确)、尺寸、环宽、填充/实心、不透明度、z2,每条曲边的四个点(精确)、宽度、颜色、z2,每个标签的文字/锚点(精确)/对齐;另有「树不占色板位」的测试。径向布局和折线边的用例这一批跳过、计数。

### 变异测试

34 个。两个存活:

- 单节点的 `delta` 从 1 改成 0.5:单节点(以及所有广度坐标都是 0 的链)的纵坐标是 `delta·h / (2·delta)`,恒为 `h/2`,等价。
- 去掉按个数的盒子合并:基准里的 `B-wh` 写的是 `left` 和 `width`,被丢掉的 `right` 本来就不参与 getLayoutRect。补了一个直接测试:写 `right` 和 `width`(以及 `bottom` 和 `height`)时默认的 `left`(`top`)必须被丢掉、盒子贴右(贴底)——补后杀死。

### 已知偏差

- 尺寸为 0 的空心节点端口不画环(上游的环宽是 2,但没有尺寸,什么也看不见)。
- 径向布局、折线边、提示框、展开收起的点击、漫游、emphasis 下一批起再做。

## 108. Tier 1 第七十四批:树图——径向布局、径向标签、折线边(T2,2026-09-30)

### 上游的做法

- **径向布局**:同一个 Walker 算法,但间距除以节点深度(`separation / a.depth`;`delta` 用**最左**节点的深度,最左最右可以不同深),广度缩放到 `2π`,深度缩放到盒子短边的一半;`radialCoordinate(角, 半径)` 先减 `π/2`,所以角度从十二点钟开始、在屏幕上顺时针。主组放在盒子**中心**。
- **径向曲边**:在(角、半径)空间里取点:起点、两个控制点(半径按曲度插值、角度分别取父和子的)、终点都由原始坐标重新算,每个坐标再 `|| 0`(NaN 和负零都变成 0)。
- **径向标签**:由节点相对真根的角度决定边和转角——叶子和收起的节点朝外,展开的内部节点朝里,根跟随它第一个和最后一个子节点的中点;位置默认 `left`/`right`,转角默认 `-角度`,作者写的 `position`/`rotate` 优先;以标签框**中心**为原点转(textConfig origin `'center'`),竖直对齐强制 `middle`。
- **折线边**:每个**展开**且有子节点的节点一条路径,用**父**节点的 lineStyle:从父到分叉点(在父与**最后一个**子节点之间 `edgeForkPosition` 处),第一个子节点的枝、横杆到最后一个、最后一个的枝,再补中间各子节点的枝——一条路径、多段。单个子节点就是一条直线。径向布局用折线时开发版抛异常、生产版不画边。

### 做法

- `TyTreeSolve`:径向分支(`TyJsCos`/`TyJsSin` 保证与 V8 逐位一致),`RawX/RawY` 记下原始坐标,主组原点 `GX/GY`(正交是盒子角、径向是盒子中心)。
- `TyBuildTreeMarks`:径向曲边(`Radial0` 做 `|| 0`)、折线边(`PolylineEdge` 逐字转写 TreePath.buildPath,多个 moveTo 子路径)、径向标签(`RadialLabel`:按上游规则定边与转角,再照 zrender `getLocalTransform` 带原点的算法算出最终锚点)。
- 标题新增「固定锚点」:标记自己算好的锚点、内外侧(决定墨色)、对齐和转角,展开标签时照用;作者的 `align` 仍然优先,竖直对齐保持标记给的。
- `TyBuildTreeMarks` 多一个 `APPI` 参数(标签距离按 PPI 缩放)。

### 基准

- 沿用 `tools/advchart-oracle/tree.js`,去掉上一批跳过的径向与折线用例:径向 T7、不对称树、单节点、单子节点、深链、20 扇、非方形盒子、四个象限与正好落在轴上/对角线上/约 π 处的标签、作者转角与位置、收起节点;折线 50%/20%/0.8/'center'、四个朝向、收起节点、单子节点、父节点样式;以及画廊的 tree-radial、tree-polyline。
- `test.advchart.tree`:径向节点位置与曲边四点精确比较;径向标签比较最终锚点(变换的平移)与转角;折线边逐条命令精确比较。

### 变异测试

22 个,2 个存活,都等价:

- 分叉点朝**第一个**子节点量:分叉坐标在深度轴上,兄弟节点深度相同,第一个和最后一个给出同一个值(基准代理也记下了这一点,换成了从子节点一侧量的守卫)。
- 收起的父节点也画折线:收起节点的子节点没有位置,`PolylineEdge` 在子节点没放时本来就不画。

### 已知偏差

- 径向标签的 `offset` 按屏幕坐标加,不随转角转(上游在转后的坐标里加)。
- 提示框、点击展开收起、漫游、emphasis 之后再做。

## 109. Tier 1 第七十五批:旭日图(S1,2026-09-30)

### 上游的做法

- **层级**:和树同一套(虚拟根以系列名命名,先序行号即 dataIndex),但旭日图画**所有**根。
- **补值**(`completeTreeValue`,建树之前改写选项):没写值的节点取子节点之和,写了值的保留(子节点不重新缩放,多了溢出、少了留空),负值和非数都成 0;数组值取第 0 项。标签里的 `{c}` 读的就是补过的值。
- **排序**:没写 `sort` 按值降序,`null` 不排,`'asc'` 升序且相等时反转原顺序,其他字符串按降序。
- **角度**:单位弧度 `2π / 根之和`(和为 0 且 `stillShowZeroSum` 时每个根平分),每块至少 `minAngle`;兄弟节点按各自 `end - start` 累加,所以写了值的父节点和子节点可以不对齐。起始角默认 12 点,`clockwise: false` 反向。
- **半径**:`radius` 标量是外半径、数组是内外;每层等宽 `(r - r0) / (树高 - 1)`;`levels[depth]` 可用 `radius` 覆盖本层,旧写法 `r0`/`r` 在没有 `radius` 时才生效。
- **颜色**:条目 → `levels[depth]` → 系列的 `itemStyle.color` 优先;否则按深度 1 的祖先的**名字**向色板取色(同一个图表里所有旭日图共用一个取色游标),深度大于 1 的再向白色提亮 `(depth-1)/(树高-1)·0.5`,每个通道截断取整。
- **样式**:边框默认白色、宽 1,z2 为 2,`borderRadius` 支持百分比(按 `r`,`r` 为 0 时按 `r0`)。值为 0 的块不画(`renderLabelForZeroData` 除外)。
- **标签**:默认显示名字;锚点在块的中角上——`center` 取内外半径中点(整圆且内半径为 0 时取圆心),`left`/`right` 从内/外缘量 `distance`(默认 5),`outside` 在外缘之外;中角(切向旋转时是 `π/2 - 中角`)落在 π/2 到 3π/2 之间就翻转(π/2 处有 1e-4 的容差),翻转改对齐、给转角加 π;`rotate` 可以是 `radial`/`tangential`/度数;`offset` 被忽略;`label.minAngle` 太小就不显示。

### 做法

- 新单元 `tyControls.AdvChart.Sunburst`:`TySunburstSolve`(补值、排序、中心与半径、递归 `RenderNode`)、`TySunburstColour`、`TySunburstLift`、`TySunburstLabelSpecs`(条目 → 层 → 系列,偏移清零)、`TyBuildSunburstMarks`(扇形用已有的 `TyShapeSector`,标签用上一批的「固定锚点」)。
- 补值挪进 Tree 单元的 `TyTreeCompletedValues`,旭日图的求解和存储共用;`TyTreeFillStore` 多一个参数,旭日图的存储写入补过的值,所以 `{c}` 与上游一致。
- JsMath 新增 `TyJsFMod`:JS 的 `%`,精确余数(逐次减去 2 的幂倍,Sterbenz 保证每步精确),`NormalizeRadian` 靠它逐位对上。
- 控件:存储分支与树共用、`SolveSunbursts`(整块画布,共享取色游标;色板依次取系列自己的、图表的、主题色阶)、`SunburstInk`(边框是图表底色——上游的白)、`BuildSeriesList` 的旭日图分支;`sunburst` 加入「别处画」名单。
- **固定锚点的对齐**:展开标签时,标记给了固定锚点就不再用作者的 `align` 覆盖——旭日图的翻转已经把它算进去了;径向树改在 `RadialLabel` 里自己先应用作者的 `align`,行为不变。
- 上游对未知 `align`(如 `'middle'`)不设半径、锚点是 NaN;端口不画这个标签(和树的 NaN 锚点一样)。

### 基准

- `tools/advchart-oracle/sunburst.js`(代理写)真跑 ECharts 6.1,80 个用例、35 条守卫:补值(缺值、显式值溢出与留空、负值、数组值)、四种排序、中心与半径写法、起始角、逆时针、`minAngle`、零和、层半径与 `r0`/`r` 旧写法、颜色层级与提亮、多个旭日图共用取色、边框与圆角、标签位置/对齐/距离/三种旋转/翻转边界/整圆居中/`minAngle`/formatter 层级,以及画廊 6 例(简单、圆角、单色、标签旋转、饮料、visualMap)。另有独立转写和 440 个随机图逐位一致。
- `test.advchart.sunburst`:通过控件画一遍,逐行比较有没有画、扇形的中心/内外半径/起止角/四个圆角(精确)、z2、填充、边框颜色与宽度、不透明度,每个标签的文字、最终锚点(精确)、转角(精确)、对齐。visualMap 着色的行跳过填充、计数(下一批)。

### 变异测试

40 个,首轮 5 个存活、1 个编不过,都是测试的缺口,补完全部杀死:

- 四个颜色变异(不提亮、提亮四舍五入、按自己名字取色、忽略条目颜色)全部存活——测试把夹具里的 `visualMapFill: false` 当成「有 visualMap 着色」,**所有**填充都被跳过了。改为只跳过真值,并断言跳过的不到一成。
- 数组值只取第 0 项:基准里唯一的数组值在 `V-string` 里,而这个用例按名跳过。补 `TestAnArrayValueCountsItsFirstEntry`。
- 忽略圆角:测试没比较圆角。现在按 `TySectorRadii` 规整夹具里的 `cornerRadius` 后逐个比较。

### 已知偏差

- 字符串值:上游补值用 JS `+`,`'5' + '3'` 拼成 `'053'`;端口按数相加(父节点是 8)。基准里的 `V-string` 按名跳过,`TestStringValuesAddAsNumbers` 钉住端口这一侧。
- 未知 `align` 的标签不画(上游锚点是 NaN)。
- 下钻(`nodeClick`)、回上一层的圆盘、emphasis 的祖先/后代高亮、visualMap 着色、提示框之后再做。

## 110. Tier 1 第七十六批:矩形树图(M1,2026-09-30)

### 上游的做法

- **层级与补值**和旭日图同一套(虚拟根以系列名命名,先序行号即 dataIndex,`completeTreeValue` 逐字相同)。
- **排序不动行号**:每个节点对子节点的**副本**(viewChildren)排序。没写 `sort` 是降序;真值里除了 `'asc'` 都是降序;`false`/`null`/`0`/`''` 不排序,而且**不排序就不做 visibleMin**。降序时值相等,**行号大的在前**(和旭日图相反)。
- **visibleMin 默认 10 px²**:排序后从最小的开始,面积份额不够的去掉,`sum` 在循环里边减边比;留下的按缩小后的和重新分满父节点。值为 0 的子节点在排序时总会被去掉。
- **squarify** 逐句:行面积入栈加、出栈减(不重新求和);`score <= best`(`<` 会在全零行上死循环);`rfl === rect.width` 精确比较决定方向(正方形走横向);行里最后一个取剩余;冲刷行取剩下的全部;`(h - lo) - lou` 从左往右;`area = v / sum * A`。**任何地方都不取整**。
- **边框和间隙不是描边**:每个可见节点(根也算)画一个背景矩形,填充是边框色;没有 view 子节点的节点再画内容矩形,内缩 `borderWidth`。z2 分别是 `depth*100 + 20`、`+30`。
- **坐标是局部的**:全局原点按 zrender 的组变换逐层累加;某一层的局部偏移在两个轴上都不超过 5e-5 时,**这一层没有变换**,直接沿用父节点的。
- **颜色**:没有任何层级写颜色时,图表色板放进 `levels[0].color`(空数组也算写了颜色);父节点把 view 列表里第 k 个子节点映射到 `list[k mod n]`,子孙原样继承,不提亮、不按名字共享。优先级是条目 → 层 → 父节点指定 → 系列。只有没有 view 子节点的节点有填充。
- **标签**:恒为白色,没有自动反色和描边;文字是 formatter,否则按条目 → 层 → 系列取名字;锚点在内容矩形中心,按 `(bw + tx) + cw/2` 的顺序算;zrender 的截断——高度放不下的行丢掉(行高是「国」的宽度)、宽度先减 1、留两个 `a` 的余量再判断 `...` 放不放得下(放不下就不加)、第一轮按字宽累加、第二轮按比例、最多两轮,长度按 UTF-16。标签的 z2 是**先序遍历中已见最大 z2 加 2**,不是宿主加 2。
- **面包屑**默认开:首帧找目标时背景矩形还没有变换,中心点按各节点自己的 `(0, 0, w, h)` 判断——等于一路往下找宽至少半个画布、高至少半个画布的节点,先序里最后一个命中的赢。宽度 `max(字宽 + 16, 25)`,间隔 8,箭头 5;总宽超过可用宽度时从根一侧开始收成 25 宽的空块;整组按多边形外框的并集居中放到底部 15 处(并集按 zrender 的算式算)。字宽用 `12px sans-serif` 量。

### 做法

- 新单元 `tyControls.AdvChart.Treemap`:`TyTreemapSolve`(盒子 20/50 默认 + 按个数合并、squarify/initChildren/filterByThreshold/worst/position 逐句转写、裁剪、组变换累加)、`TyTreemapColour`、`TyTreemapLabelSpecs`、`TyTreemapLabels`、`TyTreemapBreadcrumb`、`TyBuildTreemapMarks`。
- Labels 新增 `TyZrPlainTextLines`:zrender 的纯文本行丢弃与截断,供标签在求解时就切好;标签的 `overflow` 置 none,画家不再二次截断。
- 标题新增 `HasFixedZ2/FixedZ2`,展开标签时照用(矩形树图的累计最大 z2、面包屑文字的 100002)。
- 控件:存储分支与树/旭日图共用(写入补过的值);`SolveTreemaps` 需要量字器,放在 `Relayout` 里旭日图之后;色板只取图表级的(系列的 `color` 是层级映射用的列表,不是色板),否则主题色阶;`TreemapInk`;`BuildSeriesList` 的矩形树图分支;`treemap` 加入「别处画」名单。
- 主题新键:`TyAdvChartTreemapLabel`(白字,任何模式都一样,因为下面是色板色)、`TyAdvChartBreadcrumb`(底色是墨色的淡 alpha、字是 muted)。背景矩形的默认边框色是图表底色(上游的白)。
- 面包屑是静默的(只画不命中);下钻、缩放、悬停色之后再做。

### 基准

- `tools/advchart-oracle/treemap.js`(代理写)真跑 ECharts 6.1,290 个用例:62 个手写(port.md §5 列的全部:排序各种写法、相等值、零值与极小值、全零、父值大于子值和、层级颜色列表、条目/系列颜色、11 个根绕回、无名节点、formatter、窄格与矮格的截断和丢行、中文与换行名字、childrenVisibleMin、visibleMin 300、squareRatio 1、正方形盒子、3e-5 的极小边框、画布外的盒子、面包屑收起/宽度/高度/位置/关闭、中心落在边界上、窄盒子)、画廊 `treemap-simple`、2 个守卫用例、224 个随机用例;21 条守卫全部变红;独立转写与上游 44.6 万项比对零差异。夹具里的测量表与网格边界夹具同格式。
- `test.advchart.treemap`:通过控件画一遍(测字用 zrender 的 SSR 宽度表),逐行比较背景/内容矩形四边(按 `x + tx`、`(x + w) + tx` 精确)、z2、填充;标签的文字、锚点(精确)、z2;面包屑每个点(精确)、文字、锚点、z2、个数。白色背景是端口的底色,跳过、计数。画廊用例钉死 10 个矩形、3 个标签、4 个面包屑。

### 变异测试

49 个(对应上游研究里的 21 条规则,外加排序/颜色链/内缩/标签链/截断各分支/面包屑头尾收起与并集),47 个杀死,2 个存活,都等价:

- 父节点也算填充色:父节点不画内容矩形,填充色无处可见。
- 面包屑并集宽度减 `rx` 而不是 `ux`:面包屑从 0 起向右排,并集的 x 永远是第一块的 0,两者相同。上游研究里那个真正会变的写法(用多边形的 maxX 代替 `x + width`)另列一个变异,基准的守卫用例 `X-guard-union` 把它杀死。

### 已知偏差

- 写了 `fontSize` 的用例跳过标签文字比较(锚点和 z2 照比):端口把作者的字号读进逻辑单位(主题的磅),14 在这里是 14pt 而不是上游的 14px——这是所有系列共有的问题,另立任务。
- 字符串值按数相加(同旭日图)。
- 下钻(`leafDepth`、`▶` 图标)、父节点标题条(`upperLabel` 的文字;布局里的预留已经做了)、`colorSaturation`/`borderColorSaturation`/`colorAlpha`、按值/按 id 映射颜色、图例 single 选择,分别在 M2–M6。

## 111. 选项文本的嵌套深度上限(2026-09-30)

FPC 3.2.2 的 jsonreader 每进一层数组或对象就递归一次,几十万层 `[` 会把栈撑爆——Win64 上接不住,Linux 上是 SIGSEGV,设计器会跟着一起倒。(另一个会话在终端控件里遇到同样的问题,转来的提醒。)

- `SetOptionText` 在交给解析器之前先数嵌套:超过 256 层就当作普通的解析错误拒绝,错误信息带上限数字,位置是多出来的那个括号。字符串和注释里的括号不算(和预解码一样跳过)。没有 `\u` 的快路径也会先数。
- 取 256 而不是更小:真实选项只有几十层,树和矩形树图每层 `children` 多两层,256 给层级留出一百多层。
- 控件不从文件读选项,所以不需要文件大小上限。
- 新字符串 `rsTyOptTooDeep`,pot 与两份 zh_CN po 同步。
- 测试:256 层能解析、257 层报错且列号指向第 257 个开括号、30 万层报错而不是崩溃、字符串和注释里的上千个括号不算。三个变异(去掉上限、字符串里的括号也数、注释里的括号也数)全部杀死。

## 112. Tier 1 第七十七批:旭日图上的 visualMap(S2,2026-09-30)

- **上游**:visualMap(优先级 4000)在旭日图自己的着色(3000)之后运行,覆盖它映射到的每个节点的填充;标签的墨色随新的填充走。
- **做法**:visualMap 的逐行结果本来就算在 `FVisualRows` 里(行号即层级行号,存储里的值是补过的值),`SolveSunbursts` 在 `TySunburstColour` 之后把 `ColorSet` 的行的填充换掉。标签的墨色由展开时按宿主填充决定,自然跟着变。
- **基准**:`sunburst.js` 加 4 个用例:连续型 0..5(范围内渐变、范围外 `outOfRange`)、连续型不写 `outOfRange`(默认的范围外颜色)、分段型三段、两个旭日图只映射 `seriesIndex: 1`。连同画廊的 `sunburst-visualMap`,测试不再跳过 visualMap 行的填充。
- **变异**:去掉覆盖——杀死。

## 113. Tier 1 第七十八批:矩形树图的饱和度着色与父节点标题条(M2 + M3,2026-09-30)

### 上游的做法

- **两个同名键**:条目/层/系列顶层的 `colorSaturation` 是**范围**,父节点用它映射子节点(`levels[d]` 的映射作用在深度 d+1);`itemStyle.colorSaturation` 是节点自己的**值**。
- **映射**:父节点没有颜色列表、自己有颜色时,用链上的 `colorSaturation` 范围,按子节点的值线性映射两次(先到 [0,1],再到范围,都夹紧;端点精确;值域为一点时取中间;单元素范围自己配对)。值域是**排序后、visibleMin 裁剪前**的子节点——被裁掉的 0 值子节点仍然把最小值拉到 0。
- **优先级**:条目 `itemStyle` → 层 `itemStyle` → 父节点映射(一路继承)→ 系列 `itemStyle`。
- **所谓饱和度是 HSL 亮度**:`modifyHSL(c, null, null, s)` 的第四个参数是 L;饱和度 0 不改变颜色(真值判断)。
- **`borderColorSaturation`**(用 `!= null` 判断,0 得黑色):边框 = 节点自己的颜色(已套过饱和度)再改亮度;节点没颜色则**没有边框**,背景矩形什么也不画。
- **dataStyleTask 在视觉之后**:条目自己的 `itemStyle.color` 覆盖叶子的(饱和过的)填充,`borderColor` 覆盖任何节点的边框。
- **标题条只在父节点上**:`upperLabel.show` 且高度非零的父节点,在背景矩形顶部 `upperHeight = max(bw, height)` 的条带里放文字;叶子只保留布局预留、照常画居中标签。文字是 `upperLabel.formatter`,没有就用 `label.formatter`,再没有就用链上的名字;没有默认内边距;截断规则同 M1;默认位置 `[0, '50%']`(左、中),`'inside'` 居中;z2 是遍历中已见最大值(含背景)加 2。
- **标题的墨色是「外侧」规则**:`#333` 加背景色的光晕,不是按条带底色做亮度对比;只有 `position: 'inside'` 且条带有填充时才按亮度分三档。

### 做法

- Treemap 单元:节点记下子节点的值域(只在 initChildren 走到最后时);视觉记录多了继承的饱和度;`CalcColour` 用 VisualMap 已有的 `TyVisualModifyHSL`(逐位对过上游)改亮度;边框饱和度、条目颜色/边框覆盖;`HasStroke` 为假时背景不填充。
- 新 `TyTreemapUpperLabels`:文字、条带(有组变换时负宽翻转)、内边距(CSS 简写)、截断(复用 `TyZrPlainTextLines`)、位置;新 `TyTreemapUpperSpecs`:`upperLabel` 按条目 → 层 → 系列叠在图表自己的标签墨色上。标题挂在背景矩形上,`ItemLabels` 的顺序是行、面包屑、各行标题。
- 墨色:固定锚点 `FixedInside` 只在 `'inside'` 时为真,于是默认是外侧墨色加底色光晕(主题的 `TyAdvChartLabel`),与上游规则同构。

### 基准

- `treemap.js` 由代理扩展:106 个新用例(51 个 M2、55 个 M3,含画廊 `treemap-disk`、`treemap-show-parent`),原 290 个用例逐字节不变;40 条守卫全部变红;转写与上游 76.7 万项零差异。
- `test.advchart.treemap`:新增 `upper` 元素按普通标签比较(锚点加上内边距偏移);画廊测试钉死 disk + show-parent + simple 的 781 个矩形、139 个标签(其中 35 行标题)、6 个面包屑。M2/M3 用例第一次跑就全部逐位对上。

### 变异测试

25 个,20 个杀死,5 个存活:

- 两次线性映射改成一次:内部点完全相同;值域为一点时两者只差最后一位,经 modifyHSL 取整后颜色相同——等价。
- 负宽条带不翻转、无变换时也翻转:负宽条带的文字宽度为 0,截断成空串,不画——锚点不可观测,等价。
- 系列的 `itemStyle.colorSaturation` 压过父节点映射值、标题截断宽度不减内边距:基准缺这两种组合。已请代理在下一批(M4–M6)的夹具里补两个手写用例,补上后重跑这两个变异。

### 已知偏差

- 标签/标题的不透明度(条目或系列 `itemStyle.opacity` 作为标签默认不透明度)没有做:端口的标签不透明度跟随宿主,而矩形树图的矩形本身不用不透明度。
- 写了 `fontSize` 的用例仍跳过文字比较(全局字号单位问题,另有任务)。

## 114. Tier 1 第七十九批:桑基图(K1,2026-09-30)

### 上游的做法

- **图**:节点的键是 `id`,没有就是 `name`,再没有就是下标(字符串化);连线端点是 JSON 数字时按**下标**找、是字符串(包括数字字符串)时按键找,找不到的连线丢掉且不占 dataIndex;`edges` 优先于 `links`、`data` 优先于 `nodes`(按 JS 真值,空数组也算)。键重复或有环时上游直接抛异常、什么也不画——端口同样拒绝这个系列。
- **值**:节点值 = `max(出边和, 入边和, 自己的值 || 0)`,求和跳过 NaN、按连线顺序。**只要有一个节点值为 0,整个图不做松弛迭代**。
- **层**:Kahn 分层(离源点的最长路径);节点自己写 `depth` 只改它自己;`nodeAlign` 默认 `'justify'` 把所有汇点(含孤立点)移到最右,`'right'` 按到汇点的最长路径,其他值等同 `'left'`。`kx = (W - nodeWidth) / maxDepth` 再乘深度;按缩放后的横坐标(SameValueZero)分列、列按键升序。
- **纵向**:全图**一个** ky(最紧的一列);初始位置是列内下标;碰撞消解是稳定的原地排序、先下推再从底部上推一次、不夹顶;松弛时 `alpha` 是 0.99 的**连乘**,右到左(出边)再左到右(入边),Gauss-Seidel,加权平均为 0/0 时退回邻居中心的平均。连线的 sy/ty 按另一端节点的**顶**稳定排序后累加。全程不取整。
- **颜色**:节点值在色板(系列的 `color`、图表的、主题的)上线性映射,输出 `rgba(...)`;链上的 `itemStyle.color` 原样优先(字符串或渐变对象)。
- **连线**:`lineStyle` 按 itemStyle 的键读——`color` 是填充、`borderColor/borderWidth` 是描边、`width` 无效;默认中灰、不透明度 0.2、曲度 0.5;`'source'`/`'target'` 取端点节点的颜色,`'gradient'` 在两端都是字符串颜色时是沿连线方向的线性渐变。带形路径 `M C L C Z`,控制点 `x1(1-c) + x2c`,宽度至少 1。
- **标签**:默认文字是节点的 **id**(不是名字);formatter 每个占位符只替换第一次出现,`{c}` 没有原始值时用布局值;锚点按 zrender 的文字位置表,宿主矩形按描边外扩(无填充时至少 5);z2 是 12。
- **层级**按对齐后的布局深度查找,连线用**源节点**的深度。

### 做法

- 新单元 `tyControls.AdvChart.Sankey`:`TySankeySolve`(图、值、Kahn、对齐、分列、ky、碰撞、松弛、连线深度,按 `ref.js` 逐句转写;稳定插入排序用嵌套比较函数)、`TySankeyColour`(复用 VisualMap 的 `TyVmLinearMap`/`TyVisualFastLerp`)、`TySankeyLabelSpecs`、`TySankeyLabels`、`TyBuildSankeyMarks`(带形用 `TyShapePolygon` + 路径命令,包围盒按 zrender 的三次曲线极值规则算,渐变用 `TTyChartGradient`)。
- 控件:`SolveSankeys`(色板按 zrender 解析原样读,保留 alpha)、`BuildSeriesList` 分支、`sankey` 加入「别处画」名单;新主题键 `TyAdvChartSankeyLink`(墨色的 muted 调)。
- 标签展开:带固定锚点的宿主不再要求矩形有效——某列放不下时节点高度为负,标签照样要画。
- **不可见的几何不输出**:没有连线、有 0 值节点时上游会算出 NaN/无穷坐标,画出来也看不见;端口不输出这些矩形、带形和标签(否则画家会在 NaN 上抛异常)。
- 节点颜色是渐变对象时:矩形用渐变填充,`'source'`/`'target'` 连线沿用它。

### 基准

- `tools/advchart-oracle/sankey.js`(代理写)真跑 ECharts 6.1,446 个用例:110 个手写(两种画布尺寸)、7 个画廊文件 × 两种尺寸、320 个随机;4469 个节点、2511 条连线、4467 个标签、308 个渐变;35 条守卫全部变红;转写与上游 51.5 万项零差异。
- `test.advchart.sankey`:通过控件画一遍,逐项精确比较每条带形的五条路径命令(控制点与端点,按 `x + tx`)、z2、不透明度、填充(颜色/节点颜色/渐变的每个色标),每个节点矩形四边(负高度的圆角矩形按边集合比较——两边都会翻转)、z2、填充,每个标签的文字、锚点、对齐、z2、作者写的墨色;渐变的方向;主题灰连线跳过、计数;上游看不见的几何必须缺席、计数。

### 变异测试

38 个,首轮 4 个存活,补完全部杀死:

- 「一列一个 ky」写成了等价变异(第一列本来就进最小值),换成「用最后一列的 ky」——杀死。
- 松弛求和不跳过 NaN:基准里没有「一条连线缺值、同节点其他连线有值、且迭代在跑」的节点。在 `sankey.js` 加手写用例 `H-relax-nan`(夹具重生成,446 个用例、51.6 万项零差异)——杀死。
- 竖向时渐变方向不变:测试只比较了色标颜色,没比较渐变方向;补上 `x2/y2` 比较——杀死。
- 层级的标签规格不生效:只影响墨色和字体,测试没比较作者写的标签颜色;补上 `colourRule: 'option'` 时的墨色比较——杀死。

### 已知偏差

- NaN/无穷几何不输出(上游输出但不可见)。
- 渐变连线的包围盒不含描边外扩(只在 `lineStyle.borderColor` 与 `'gradient'` 同时出现时有差别)。
- 边标签、强调/聚焦、拖动、提示框、`zoom`/`center` 之后再做。

## 115. Tier 1 第八十批:矩形树图的下钻、按值着色与多系列(M4 + M5 + M6,2026-09-30)

### 上游的做法

- **leafDepth(M4)**:按 squarify 深度(根为 0)数;到了这一层,子节点只保留面积、不再布局也不画,父节点记为「叶根」,当叶子画、标签前加系列**自己的** `drillDownIcon`(默认 `▶`,按 `!= null` 判断文字——空串也加图标);`leafDepth` 只在这一层及以后压过 `childrenVisibleMin`;只要写了 `leafDepth`,首帧面包屑只有根。
- **按值着色(M5)**:`colorMappingBy` 除了 `'index'`/`'id'` 以外一律是线性颜色映射;值取父节点链上的 `visualDimension`(0、空、`'value'` 读补过的值;超出最长值数组的维度是 NaN;标量——包括补出来的和——对每个维度都回答自己);值域是排序后、visibleMin 之前的子节点,`visualMin`/`visualMax` 只放宽;fastLerp:`value = t·(n-1)`,每个通道 `round(L + (R-L)·p)`,alpha 不取整,输出 `rgba(...)`;t 为 NaN 或越界没有颜色,值域为一点时一律取中间。
- **按 id 着色、透明度、位置、富文本(M6)**:id 是条目自己的,没有就用名字(没有 id 的行里第 k 次重复加 `__ec__k`,根按系列名算),再没有就生成;`mapIdToIndex` 是每个系列一个、按先序访问顺序首次出现计数(不可见的子节点也占号)。`colorAlpha` 范围与饱和度同样映射、优先于饱和度范围;值在饱和度之后用 `modifyAlpha`(保留通道),只对真值生效。系列的 `color` 列表在根以下的每一层按序号映射。`label.position` 的 `inside*` 九种按 zrender 表格加 `distance`(默认 0),普通布局在对齐的一侧加内边距;任何 `label.rich` 都切到富文本布局:只截宽过盒子本身的行,盒子按**外框**放(所以默认 `'inside'` 的富文本贴在格子顶部)。图例 `selectedMode: 'single'` 选第一个没被显式关掉的名字,被过滤的系列什么也不画。

### 做法

- Treemap 单元:
  - `InitChildren` / `Squarify` 带上深度,`leafDepth` 截断、`IsLeafRoot`;面包屑按 `HasLeafDepth` 取根。
  - 新 `ValueAt`(按维度取值)、`DimOf`,值域按父节点的维度算;`DimMax` 与 id(`AssignIds`,按上游 `makeIdFromName`)在求解时算好。
  - 视觉:颜色种类多了「映射出的 rgba」;线性映射用 VisualMap 已有的 `TyVisualParsedStop`/`TyVisualFastLerp`,id 映射用每个系列一个的 `TStringList` 计数;透明度值/范围;着色过程整体屏蔽浮点陷阱(NaN 维度要比较)。
  - 标签:钻取图标、`label.padding`/`distance`/`position`、富文本的放置;节点记下标签的水平/竖直锚点,标题交给展开。
- Labels 的 `TyZrPlainTextLines` 多一个 `ARich`:富文本只截宽过盒子本身的行。

### 基准

- `treemap.js` 由代理扩展:121 个新用例(M4 30、M5 33、M6 56,含画廊 `treemap-drill-down`、`treemap-visual`、`treemap-obama`),外加上一批变异测试要的两个缺口用例;原 396 个用例逐字节不变;61 条守卫全部变红;独立转写与上游 36 万项零差异。
- `test.advchart.treemap`:标签的竖直位置按端口自己的锚点比较(居中精确比锚点;顶/底比第一行顶/最后一行底);比较水平对齐;被图例过滤的系列必须一个元素也没有。画廊测试钉死六个文件合计 2155 个矩形、308 个标签(35 行标题)、9 个面包屑。M4–M6 的全部用例第一次通过就逐位对上(只修了一处:着色过程没屏蔽浮点陷阱,NaN 维度在比较时抛异常)。

### 变异测试

31 个,全部杀死:其中 29 个针对 M4–M6(leafDepth 的深度与优先级、图标、面包屑、按值/按 id 映射、维度取值的三条规则、visualMin/Max 只放宽、未定义颜色不继承、透明度的真值与范围优先级、位置/距离/内边距、富文本的截断与外框),另外 2 个是上一批存活、这批补了用例的缺口(系列的 `itemStyle.colorSaturation` 输给父节点映射值、标题截断宽度减内边距)——都杀死。

### 已知偏差

- 写了 `fontSize` 的用例仍跳过标签文字(M4–M6 的随机族里常见,约三成标签);锚点、z2 照比。
- 标签不透明度、`seriesStyleTask` 给每个矩形树图系列占的色板位(对矩形树图自己不可见)没有做。
- 下钻/缩放交互、悬停色之后再做。

## 116. Tier 1 第八十一批:树图的交互——点击展开收起、视图与漫游、悬停与提示框(T3,2026-10-01)

### 上游的做法

- **展开收起就是「把那一行的 `collapsed` 翻过来重新出第一帧」**:研究代理在 6480 个随机状态上逐位验证过(五种布局、折线、leaves 样式、各种 `initialTreeDepth`)。点击节点或它的标签都会切换(边不会);zrender 的点击要求按下与松开是**同一个元素**(节点的圆点和它的标签是两个)且距离不超过 4 像素;只有 `expandAndCollapse === true` 才接点击,而 API 动作不受它限制。切换在 `setOption` 时清空,改尺寸与漫游时保留。上游关动画时的重绘会留下「幽灵边」,基准记录干净的那一帧。
- **视图**:树也有 View——`zoom`/`center`/`scaleLimit` 即使不漫游也作用于**第一帧**(端口以前完全忽略);像素是 `(z*x + 0*y) + mainX`,`mainX = (z*GX + 0*GY) + tx`;符号放大 `(z*ns)*(size/2)`(`nodeScaleRatio` 默认 0.4),标签字号不放大;布局在某个轴上没有跨度时沿用上一帧的包围盒。`roam` 默认关,`roamTrigger` 对树默认 `'global'`。
- **悬停**:树有自己的 `ancestor`/`descendant`/`relative`(`adjacency` 等同 `self`);先全体模糊,再按上游顺序逐行解除,每行「自己的边」(曲线是入边、折线是出分叉)只有在父节点的符号此刻没有模糊时才跟随它。强调时填充提亮、按 `max(1.1, 3/半径)` 放大、z2 加 10;标签 z2 恒为符号 +2。
- **提示框**:一行不带标记的名字-值,名字是从真正的根到该节点、以 `.` 连接的路径,值是第一个值,不是数字就不显示值。

### 做法

- Tree:`TyTreeSolve` 多一个切换掩码,在 `TyTreeApplyExpand` 之后、leaves 模型之前翻转;`TyTreeApplyView` 把视图的缩放和平移套到每个像素、`MapX/MapY` 套到边的每个点,符号尺寸按 `z*ns` 放大;节点元素不再 `Silent`(可以被点、被悬停);标签 `FixedZ2 = 符号 + 2`。
- 控件:
  - `TreeToggle`/`TreeExpanded` 与事件 `OnTreeExpandAndCollapse`;切换掩码按系列放在构建之外,随选项清空。按下时记录目标(数据点 + 是否标签)与位置,松开时比较,距离 ≤ 4 且系列 `expandAndCollapse` 为 JSON `true` 才切换。
  - 每棵树一个 `TTyGraphView`(复用关系图已逐位对上的 View),选项用 Graph 单元新导出的 `TyGraphReadRoamOptions` 读;`TreeDispatchRoam`/`TreeRoam`/`TreeZoom` 与事件 `OnTreeRoam`;拖动与滚轮的宿主扩展到树。漫游动作**同步**重排并重建绘制列表——短拖后的松开要在节点新位置命中它(上游的元素对象是被移动的同一个)。
  - `ApplyTreeHover`:在静态列表里就地改样式,与关系图的悬停同一条路径(`IsTreeDatum` 让指针移动触发重绘,覆盖层的 Lift 跳过树)。
  - `TooltipContent` 的树分支。
- **顺带修正**:`TyLabelAnchorXYWH` 按 zrender 的结合方式算——`right` 是 `x + (distance + width)`,`bottom` 是 `y + (height + distance)`,各「内侧右/下」是 `+ (w - d)`/`+ (h - d)`;桑基图的 `bottom` 同样修正。原先的写法在整数尺寸下碰巧一致,缩放后的符号上差最后一位。

### 基准

- `tools/advchart-oracle/tree-interact.js`(代理写):95 个用例、345 帧(T3a 35 例 190 帧,含 10 组随机 8 次切换;T3b 28 例 76 帧;T3c 32 例 79 帧)外加 13 个提示框记录;30 条守卫全部变红;转写与上游 9.7 万项零差异,每一帧还与「翻转 collapsed 后新建的图」逐位核对。
- `test.advchart.treeinteract`:在控件上重放每一步——切换走 API,点击/拖动/滚轮走真实的鼠标事件,漫游走动作,悬停走 MouseMove——每步后按全局坐标比较节点、边、标签(位置精确、大小近似)、展开状态、事件个数;悬停帧另比较每行符号/标签/边的不透明度、z2 与放大后的尺寸;提示框比较路径、有无值、无标记。点击与拖动后把指针停到 (1,1),与基准一致。

### 变异测试

`m84`:26 个变异(切换时机、点击距离的 4 与 <4、标签与圆点是两个目标、`expandAndCollapse` 的真值门、节点静默、选项保留切换;像素的结合方式、零跨度包围盒、`nodeScaleRatio`、符号不放大、`roamTrigger` 默认、漫游回写、边不过视图;边跟随的两个方向、ancestor/descendant/adjacency、声明的模糊不透明度、禁用的强调、标签 z2、符号不放大;提示框路径与字符串值;`right` 锚点的结合方式)首轮存活 1 个——「按在标签、松在圆点」:基准里这一组依赖 zrender 的精确命中几何,按名跳过了。补了一条直接测试(`left` 标签的节点,在端口自己的几何上按标签、松圆点不切换;同距离的标签到标签是一次点击)后全部杀死。

### 已知偏差

- 被悬停节点的**外侧标签**不随放大的符号移动(上游按放大后的包围盒重新放);被悬停节点提亮后的填充是主题色,不比较。
- 端口节点的命中半径 7.5(与关系图一致),上游 4.5;依赖精确命中几何的两个点击步骤按名跳过。
- `roamTrigger: 'selfRect'` 用节点中心的包围盒近似上游的元素包围盒。
- 其他系列被 `blurScope` 波及的模糊没有做(基准只有单棵树)。

## 117. Tier 1 第八十二批:具名句柄接到每一个 formatter(A1,2026-10-01)

剩余路线图的审计见 `docs/superpowers/plans/2026-10-01-advancechart-remaining-roadmap.md`(Tier 1 28 行完成 10、Tier 2 37 行完成 8、Tier 3 23 行完成 0,约 70 批)。这一批是阶段 A 的第一批:`'@Name'` 以前只接到 `tooltip.formatter` 一处。

### 上游的做法(基准逐项核对过)

- **系列标签** `formatter(params)`:`getDataParams` 的 `dataIndex` 是**原始**下标(dataZoom、图例过滤后都不变);`percent` 只有饼(最大余数的席位)和漏斗(`toFixed(2)`);`dataType` 只在关系图的边、桑基图的节点和边上有,关系图节点没有;树、矩形树图、旭日图的下标从 1 数(0 是虚根);函数的返回值原样作标签,不再过模板。
- **标注**:`componentType` 是 markPoint/markLine/markArea,系列类型、名字、下标是宿主系列的;没有 percent/dataType;markArea 的 value 是 undefined。
- **坐标轴标签**:类目轴 `(类目名, tick - extent[0], null)`——下标从窗口第一个类目数起,interval 的空档看得见;数值/对数轴 `(值, 在 getTicks 里的位置, null)`;时间轴 `(值, i, {level})`,**返回值再过一遍时间模板**。
- **图例** `formatter(name)`;**valueFormatter** `(value, rawDataIndex)`——子行各自格式化、下标 undefined,有子行的那一行拿到空数组;**axisPointer 标签** `params` 带轴维、轴下标、值(类目轴是类目名)和 `seriesData`;**visualMap** 区间 `(lo, hi)`(开口端是 ±Infinity)、单值 `(value)`、类目 `(category)`,连续型只有 calculable 的手柄标签调用;**dataZoom** `(value, valueStr)`;**仪表盘** detail/axisLabel `(value)`;**雷达** `(name, indicator)`——负的 min 且没写 max 时 RadarModel 把 max 写成 0;**日历** 月 `{yyyy, yy, MM, M, nameMap}`、年 `{start, end, nameMap}`。

### 做法

- Handlers:参数记录新增 `Status`、`AxisDimension`/`AxisIndex`、`Level`/`HasLevel`、`ValueText`(值按 JS `String()` 印的样子)、`DefaultText`(没有 formatter 时本来会印的字);`TyChartRunHandler`、`TyChartOneParams`、`TyChartBlankParams`。
- 标签:`TyLabelText` 多三个默认参数(系列下标、类型、颜色、dataType),遇到 `@` 走新的 `TyLabelParams`;漏斗、饼、关系图、树、旭日图、矩形树图、桑基图、标注各自传入。
- 轴:`TyAxisTickLabelAt` 带下标;时间轴的字符串 formatter 也顺带接上(`TyFormatTime`,以前完全不读)。
- 控件:`PointerLabelText`(指针标签和轴 tooltip 的表头走同一个)、`TipValueFormatted`、tooltip 规格读 `valueFormatter`(级联同 formatter;轴触发时按系列+全局)。
- 其余:图例、visualMap 两处、dataZoom、仪表盘、雷达、日历。
- **顺带修的真缺陷**:
  - 柱、折线点、象形柱**不读条目自己的 `label`**(只有热力图和散点读),条目级 formatter/show 被忽略;
  - 仪表盘条目写了 `detail`(哪怕只写 offsetCenter)就把系列的 formatter 清空;
  - 死代码 `CaptionFor` 删掉。

### 基准

- `tools/advchart-oracle/handlers.js`(代理写):64 个用例,每个 `'@Name'` 在上游换成一个把实参编码进返回值的 JS 函数;21 条守卫;两次运行逐字节一致。轴触发的指针位置取整数像素(端口的指针按鼠标坐标)。
- `test.advchart.handlerwiring`:注册同名 Pascal 句柄、按同样编码印参数,比较画面(显示列表的标题 + 坐标轴显示的标签)、tooltip 各行、指针标签三组文字的多重集合;另有一条未注册名字要说出来的测试。fpjson 会吞掉 `\u0000`(自动系列名 `series\0 1`),比较前两边都去掉。

### 变异测试

`m85`:23 个变异(标签的过滤下标、句柄当模板、值当数字、柱不读条目标签、关系图节点的 dataType、桑基图节点用布局值、标注系列类型、markPoint 当 markLine;类目下标、时间模板不格式化、时间没有 level;图例;valueFormatter 不读、子行带下标、轴触发不看系列;指针类目当数、没有 seriesData;visualMap 区间只给一个值、手柄;dataZoom valueStr;仪表盘条目 detail 清掉 formatter;雷达负 min 规则;日历月的两个值对调)。首轮存活 2 个:
- 「桑基图节点用布局值」:基准唯一写了值的节点,写的值恰好不小于流量,布局值等于写的值——补了一个「节点自己的值小于流量」的用例后杀死;
- 「类目下标取刻度位置」:等价——端口的类目刻度列表从窗口第一个类目起逐个列出,位置恒等于序号减去范围起点;公式照上游写法保留。

### 已知偏差

- 关系图、桑基图的**边标签**本来就没画(第 46、79 批),对应的上游文字不比。
- 雷达系列标签没移植(第 35 批),该用例跳过。
- 矩形树图用例:~~作者字号按磅读导致文字更宽被截断,等 A2 修字号后放开~~ **[第 83 批更正:理由不对——这个用例没写字号;是这个测试用真字体量字、上游用 SSR 估算,截断位置不同。矩形树图的文字由 `test.advchart.treemap` 用 zrender 的量字表比,那边已全部放开。]**
- `axisPointer.status: 'show'` 与 `value` 写在选项里时的初始指针没移植,归 B5。
- `tooltip.position` 的函数形式要另一种返回类型,归 B5。

## 118. Tier 1 第八十三批:作者写的字号是 px、根 textStyle、backgroundColor 与 darkMode(A2,2026-10-01)

### 问题

作者在选项里写的 `fontSize` 一直被当成主题的**磅**读——`14` 画成 14pt ≈ 18.7px,大三分之一。15 个读取点无一换算;矩形树图、旭日图、桑基图的测试靠「写了 fontSize 就跳过文字比较」绕开(约三成标签)。根级 `textStyle`、`backgroundColor`、`darkMode`,轴标签/轴名/标题/图例自己的字体与颜色,也都不读。

### 上游的做法(`text-style.js` 逐项核对)

- **字号是 CSS px**:数字、`'14'`、`'14px'` 都是 14px(zrender `parseFontSize`);读不出的串是 12px;`13.5` 就是 13.5。
- **字体属性逐个回落到根 textStyle**(`getFont`、`setTokenTextStyle`),但**组件自己有默认值的属性挡住它**:轴标签的 12px、标题的 18px bold、副标题的 12px、仪表盘的 12/16/30px 都挡住根 fontSize;根 fontWeight/fontFamily 能到轴标签和副标题;轴名、图例、系列标签、visualMap、dataZoom、雷达指示器名三样都接。
- **颜色只给没有默认颜色的独立文字**:轴名接根 color;轴标签、标题、图例有令牌默认色,挡住;挂在图形上的标签从来不接(`setTextStyleCommon` 的 `!isAttached`)。
- **darkMode**:每次更新先按背景亮度定 isDark(`lum(bg, 1) < 0.4`),布尔的 darkMode 再强行覆盖,`'auto'`/缺省不动。它只影响挂着的标签:外侧描边是 `getOutsideStroke`——背景在黑(暗)或白(亮)上合成、不透明;内侧标签只在「isDark 等于墨色是深色」时拿宿主填充作描边。
- 默认字体在 Windows 的 node 下是 `'Microsoft YaHei'`——皮肤的事,不比。

### 做法

- **新单元 `tyControls.FontUnits`**(纯,只用 SysUtils/Math;画家和图表的纯单元都用得上):逻辑字号仍是一个 Integer,像素字号编码为 `cTyFontPxBase + 百分之一像素`——仍为正,所有「字号 > 0 就是画出来的标题」的判断不受影响;`TyFontSizeFromPx`、`TyFontSizeIsPx`、`TyFontPxOf`。画家的两个字体配置过程解码:BGRA 的 `FontHeight = px × PPI/96`,测量画布的 `Font.Height` 在 96 DPI 下与同等磅值走 Size 路径的一致;高 DPI 下磅值路径先把字号取整到整磅(144 DPI 的 9pt 取成 14),像素路径不取整,更准。新单元已登记进 `.lpk`。
- `TyOptFontSize`(Option 单元):数字/数字串/`'Npx'` → px 编码;全部 15 个读取点改用它。
- 轴:`TTyAxisLayoutSpec` 多标签与轴名的颜色;Builder 的 `AuthorFont` 读 `axisLabel`、`nameTextStyle` 的 family/size/weight/color;画轴改走 `AxisTextStyles`——量和画用同一份。
- 控件:`GlobalTextOver`/`GlobalInk` 带「取哪几样」(`TTyTextPick`),每个调用点按上游默认值挑;标题两行的字体 `TitleFontOf`(textStyle/subtextStyle)存在 `FTitleFonts`,布局与绘制共用;图例 `LegendTextOf`(textStyle);`backgroundColor` 在框内画、并作标签的地;`LabelGround` 按 darkMode 强制、按 `getOutsideStroke` 合成。
- **顺带修的真缺陷**:矩形树图虚根没有补值,下钻后根标签的 `{c}` 是 undefined(放开字号用例后才露出来)。
- 测试侧:`TZrSsrMeasurer` 认 px 编码,并照 platform.ts 对字体串含 `mono` 的按字符数量宽;`TPtToPxMeasurer` 让 px 直通;矩形树图测试删掉「写了 fontSize 就跳过文字」,11.3 万项全比。

### 基准

- `tools/advchart-oracle/text-style.js`(代理写):65 个用例、984 段文字,每段记组件、所属、是否挂着、位置、变换、字体五项、填充/描边与自动墨色、盒子;外加 zrender 的 SSR 量字表。守卫若干(根色不进挂着的标签、各组件在根 16 下的字号、`'14pxpx'`、parseFontSize、isDark 表……),三条守卫变异确认会红。
- `test.advchart.textstyle`:网格矩形逐位;轴标签与轴名的锚点(1e-6)和字体;标题、图例、系列标签的字体;暗色用例里每个系列标签的描边有无与颜色。**比的是「上游动了的属性」**:以 `default-everything` 里同组件的值为基线,上游偏离基线处端口必须是作者/根的值,上游没动处端口必须保持主题(不许有作者颜色、不许有像素字号)。另有字符串字号、画轴用的样式等于量的样式、画家解码三条直接测试。

### 变异测试

`m86`:25 个变异(px 按磅解、px 取整到整像素、画家两条像素路径、字符串字号两条、标签字号不读、轴/轴名作者字体、作者颜色、根 textStyle 的六个挑选、标题/图例自己的 textStyle、画轴不看 spec、darkMode 三条与作者背景、矩形树图虚根补值、日历年默认字号)。首轮存活 2 个:
- 「图例接根颜色」:测试的「作者颜色」判定取自上游,端口多接了颜色看不出来——改成按端口实际墨色是否不等于皮肤的图例色判定后杀死;
- 「日历年的默认字号按磅」:等价——年的文字规格恒带自己的 20px(`HasFontSize` 为真),AddText 的默认值用不到。

### 已知偏差

- 系列标签外侧墨色(上游暗 `#ccc`/亮 `#333`)取皮肤的,只比描边。
- `fontStyle`(italic)读不进端口的字体——画家没有斜体参数。
- visualMap、dataZoom、雷达、仪表盘、矩形树图面包屑的根 textStyle 规则按上游默认值推断,基准里没有它们的用例。
- `rem`/`em` 字号当作读不出。

## 119. Tier 1 第八十四批:图表级鼠标事件与事件查询(A3,2026-10-01)

以前只有 LCL 原生的 OnClick/OnMouse*,拿不到「点的是哪根柱子」;上游的 `chart.on('click', [query], handler)` 九种事件都没有。这一批做它们,连同 Tier 3 那行「事件的查询过滤」。

### 上游的做法(`mouse-events.js` 核对)

- **九种事件**:click、dblclick、mousedown、mouseup、mousemove、mouseover、mouseout、globalout、contextmenu。只有命中元素沿宿主/父链找得到 ECData(dataIndex 或 eventData)才发图表事件;空地、轴线、没开 triggerEvent 的标题、silent 系列都不发——**但 zrender 的悬停目标照样换**,从柱子移到轴线就是柱子的 mouseout。
- **click**(zrender `Handler.click`):按下与松开找到的是**同一个元素**(都为空也算,但没有 params)、有按下点、按下点到点击点欧氏距离 ≤ 4;通过的 click 清掉按下点,失败的不清;中间路径不管。dblclick/contextmenu/mousedown/mouseup 没有这条规则;右键有 mousedown/mouseup、没有 click。
- **悬停**:目标变了先对旧的发 mouseout(带新点的坐标),再对新的 mousemove(总是),变了再 mouseover。身份是 **zrender 元素**不是数据项——柱子和它自己的标签之间也 out/over;图例一项是一个目标(子元素都 silent、上面盖一个透明矩形)。离开画布:mouseout 然后 globalout(params 为空、无坐标),悬停目标不忘——回到同一根柱子只有 mousemove。
- **params**:系列项是 `getDataParams`(原始下标);标注是 markPoint/markLine/markArea、componentSubType ''、componentIndex 是同类标注模型的序号、系列字段取宿主;标题 `{componentType, componentIndex}`,正副标题是两个目标;图例(triggerEvent)`{componentIndex, dataIndex=在 legend.data 里的位置, value=名字, seriesIndex}`;轴(triggerEvent)标签 `{targetType:'axisLabel', value, tickIndex, dataIndex(类目轴), xAxisIndex}`、轴名 `{targetType:'axisName', name}`;折线的整条线(系列 triggerEvent)`selfType:'line'` 无 dataIndex;关系图 dataType node/edge;树系 dataType 'main'。
- **查询**(`ECEventProcessor`):字符串是 `main` 或 `main.sub`,空的部分不约束;对象的键以 Index/Name/Id 结尾就定主类型加条件(值为 null 也定主类型),`name`/`dataIndex`/`dataType` 比事件本身,其余键忽略;对着事件所属**模型**严格相等地比(标注比宿主系列),没有模型(globalout)无条件通过。事件名小写化;同一函数同一类型注册两次只留一次。

### 做法

- **新单元 `tyControls.AdvChart.Events`**(纯):`TTyChartEvent`、`TTyChartEventHandler`、`TTyEventModel`、查询解析 `TyEventQueryOf`(对象用 JSON 文本写)与匹配 `TyEventQueryMatches`、`TyChartEventTypeOf`。已进 `.lpk`。
- 参数记录多 `ComponentSubType`、`ComponentIndex`、`SeriesId`、`TargetType`、`TickIndex`、`SelfType`。
- **命中目标**:`TTyChartDatumRef` 多 `Kind`(系列/三种标注/图例)与 `ComponentIndex`,每个构造函数都写——组件目标的 `SeriesIndex` 恒为 -1,所以按系列找行的代码不会把标注当成系列项;标注元素不再 silent(按标注自己的 `silent`),宿主系列放在 `ComponentIndex`;图例每项一个不画的矩形。`HitTestAt` 仍只答系列项,悬停/tooltip/强调不受影响。标题、轴标签/轴名不在显示列表里,`EventTargetAt` 按布局的框判。
- **控件**:`ChartOn`/`ChartOff`、published `OnChartEvent`(全部事件不过滤);`EventMove/Down/Up/DblClick/ContextMenu/Leave` 照 zrender 的状态机;接到 MouseMove/MouseDown/MouseUp/DblClick/DoContextPopup/MouseLeave。
- **顺带修的真缺陷**:
  - 系列的 `silent: true` 从来不读——它的柱子照样能悬停、出 tooltip;
  - 矩形树图、旭日图的元素一直是 silent(`TyChartElement` 默认 silent,构造后没放开),点不中、悬停不到;
  - `TooltipParams` 从 `Default` 起步,新加的「-1 表示没有」字段读成 0。

### 基准

- `tools/advchart-oracle/mouse-events.js`(代理写):37 个用例、175 步、803 个事件;9 个全量处理器 + 42 个带查询的,按固定顺序注册;每步记命中与按序发生的事件。自带规则转写逐步重放全部对上,14 条守卫各自变红。标题用例写明上游默认的 18px/12px(端口的标题在选项没写时取皮肤字体,命中框跟着字体走)。
- `test.advchart.mouseevents`:按 fixture 的注册表用 `ChartOn` 注册(`sameFnAs` 共用同一个方法),逐步驱动控件自己的事件路径,每步比较事件序列:处理器、类型、上游持有的每个字段(且不多出字段)。量字用 zrender 的 SSR 表——测量画布的 `Font.PixelsPerInch` 随测试环境在 72 与 96 之间变,真字体会让标题框差几像素。

### 变异测试

`m87`:28 个变异(查询:子类型、null 仍定主类型、dataIndex 不当组件、其余键约束、name 不比、globalout 被过滤、大小写;注册去重;click 的 4px、同一目标、清按下点、右键;悬停 out 的条件、over/move 的顺序、离开时忘掉悬停、离开时不发 out;params:过滤后的下标、树系 main、折线无 triggerEvent 也发、标注序号按同类、图例找系列、轴 tickIndex;目标:标题一个目标、图例项不是目标、标注 silent、silent 系列、矩形树图/旭日图 silent)。首轮存活 2 个,都是基准缺用例:
- 「params 用过滤后的下标」:没有被 dataZoom 过滤的用例——补了一个窗口从第三个类目起的柱子用例;
- 「标注序号数所有标注」:唯一的 markPoint 在第一个系列上——补了「A 只有 markLine、B 有 markPoint」的用例。
补完后全部杀死。

### 已知偏差

- 上游发布的动作事件(select、selectchanged、legendselectchanged、treemap/sunburst 的下钻……)不在这一批:归 B1、B3、C6;矩形树图、旭日图点击后的下钻画面和图例点击后的切换画面之后的步骤按名停下。
- 轴标签的命中框不随旋转转;markLine/markArea 的 name/value 只有 markPoint 取全了。
- LCL 的 DblClick 没有坐标,用最近一次按下的点。

## 120. Tier 1 第八十五批:富文本与文字盒子的排版引擎(A4,2026-10-01)

端口的标签一直是「一段字」:一种字体、一种墨色、可选描边、锚点加旋转——没有盒子、没有内边距、没有 `rich`。画廊里 12 个文件用 `rich`,标注的富文本只定位不画(第 99、100 批),普通标签的背景框、边框、padding 也都没有(第 81 批)。这一批只做**引擎**:zrender 拿到样式以后怎么排、怎么画;把 ECharts 选项解析成这些样式、接到各处去画,是 A5。

### 上游的做法(zrender 6.1,`wf85/rich.md` 逐行对照)

- **注意版本**:echarts-doc 带的 zrender 是 5.6.1,和实际跑的 6.1.0 在 parseText/Text 上不同(没有 FontMeasureInfo、overflowRect、isTruncated);对照一律用 `D:/Projects/zrender`。
- **量字**:字宽按整串量;字高是「国」字的宽(`getLineHeight`);换行按字符累加(`measureCharWidth`,码点 128 以上都按「国」)。
- **切分**:`/\{([a-zA-Z0-9_]+)\|([^}]*)\}/g`——片段到**第一个** `}` 结束,不嵌套、不转义;未闭合、名字含别的字符都是普通文字;片段里的换行拆成同样式的几段;空行是占位,后来的片段会替换掉占位。
- **量行**:片段自己的 padding(不继承块的)、高度 = 自己的 height 或字高加上下 padding、行高 = 片段的 → 块的 → 自己的高;水平对齐默认取块的,**垂直对齐默认 middle 而不是块的**;`lineOverflow: 'truncate'` 按已完成的行高截,中途截的那一行保留前面的片段;`overflow: 'truncate'` 只截比剩余宽度还宽的片段,定宽片段或剩余不够 padding 就直接清空(不算 isTruncated);百分比宽度**最后**按块宽算,丢掉自己的 padding,而行宽早已按旧宽度加过——所以居中的 `{hr|}` 分隔线从块的中点开始往右画。
- **换行**(`wrapText`):逐字累加,拉丁字母等「字母范围」内是词、其余与 `, & ? / ; ] 空格` 是断点;第一段总是接在当前行后面,哪怕它已经溢出。
- **摆放**:盒子按锚点、对齐与外尺寸定;每行先摆左对齐的一组、再从尾部摆右对齐的一组、剩下的居中;片段按自己的垂直对齐在行里上下;padding 再挪字;字的基线恒为 middle。
- **画的顺序**:块的矩形,然后每个片段按**摆放顺序**先矩形后字。矩形在有背景色、有 lineHeight(不可见的矩形,但算进包围盒)、有边框时才有;既有填充又有边框时先描边、线宽加倍。填充/描边:片段的 → 块的 → 宿主默认;自动描边在片段或块有背景色时取消。
- **普通文字**另一条路:行按**内容高**而不是盒子高对齐锚点,只有背景**颜色**取消自动描边,middle 时垂直 padding 不起作用。

### 做法

- **新单元 `tyControls.AdvChart.RichText`**(纯,已进 `.lpk`):`TTyRtStyle`(zrender 规格化后的样式;`Has*` 就是 JS 的 `'x' in style`)、`TTyRtRich`、`TTyRtDefault`(宿主默认)、`TyRtLayout`——答块(行、片段及其宽高)与按画的顺序排好的矩形和字,都在字自己的坐标系里,锚点与旋转由调用方整体套上。
- 截断复用 `TyZrPlainTextLines`(已是 zrender 的 `truncateSingleLine`);`wrapText` 逐句转写。

### 基准

- `tools/advchart-oracle/rich-text.js`(代理写,附 `wf85/rich.md`):74 个用例、211 段文字、553 个画出的部件;每段记 zrender 收到的块样式与每个 rich 样式、宿主默认、锚点、盒子、行与片段,和按顺序的每个部件(矩形的框/填充/描边/先描边/四角半径,字的位置/对齐/字体/填充/描边)。手算守卫 7 个用例的精确几何、四种 padding、边框加倍、不可见的行高矩形、标题禁盒、切分四例、截断的独立实现、`richInheritPlainLabel`,外加一致性检查与同进程两次运行。
- `test.advchart.richtext`:把 fixture 里 zrender 收到的样式原样交给引擎,逐部件比较:种类、位置尺寸、字、对齐、字号字重、填充、描边及其宽度、先描边、四角半径。量字用 zrender 的 SSR 表。

### 变异测试

`m88`:26 个变异(换行的断点、首行的累计宽、词被切时推出的宽、单行不加上一段的累计;占位替换、空段保留、名字不含数字、片段到最后一个 `}`;行高不继承块的、垂直对齐默认块的、高度不加 padding、百分比保留 padding、定宽片段被截而不是清空、lineOverflow 丢掉中途那行;右组升序、居中偏移忘了剩余、居中 padding、top 片段;边框不加倍、行高不出矩形;片段背景不取消自动描边、填充跳过块的;普通文字按外高对齐、middle 挪 padding、背景不取消自动描边;字高按 1.2 倍)。首轮存活 3 个,都是基准缺用例:
- 「词被切时推出整段累计宽」:居中的单片段行里宽度在位置上抵消——补了一个长词跨过边界的用例,片段带背景让宽度显形;
- 「名字不含数字」:没有带数字的样式名——补了 `{a1_2|…}`;
- 「lineOverflow 丢掉中途那行」:截断总发生在行首——补了第二行第二个片段超高的用例。
补完后全部杀死。

### 已知偏差

- 图片背景(`backgroundColor: {image}`)与图片宽高比没做。
- `fontStyle`(italic)画家画不出。
- 盒子的阴影(`shadowBlur` 等)只随样式带着,引擎不出部件。

## 121. Tier 1 第八十六批:富文本与文字盒子接到各处(A5,2026-10-01)

A4 做了引擎,这一批把它接上:`rich`、背景框、边框、圆角、padding、width/height、overflow、lineHeight、文字阴影,在系列标签、标注、轴标签与轴名、标题、图例、仪表盘读数上按 zrender 的部件画出来。

### 上游的做法(`labelStyle.ts` setTextStyleCommon / setTokenTextStyle,`wf85/rich.md` §7)

- rich 名字是模型链上所有 `rich` 键的并集;每个 rich 样式也沿同一条链级联(条目的 `label.rich.a` 盖在系列的上面)。
- rich 样式的字体四项和文字阴影:自己的 → 普通标签的(`richInheritPlainLabel`,不写就是开)→ 全局 textStyle。关掉继承时回落到全局,也就是 12px normal,不是标签自己的字号。
- align、lineHeight、width、height、verticalAlign(baseline)、ellipsis 只认自己的;padding、边框、圆角、背景也只认自己的,标题的块级盒子被禁掉(rich 的不禁)。
- 颜色:`'inherit'` 是站点给的 inheritColor(柱/符号的视觉色、图例项的文字色、仪表盘的自动色);**独立文字**的 rich 没写颜色时先取根 textStyle.color,再取 inheritColor;挂在图形上的标签从来不取。所以根颜色在独立文字的 rich 片段里压过组件自己的颜色,普通部分仍是组件色。
- 组件固定写进去的样式(轴标签的 fill/对齐、标题的 fill、图例的 x/y/fill)只盖块,不盖 rich。

### 做法

- **类型挪到 `AdvChart.Paint`**:`TTyRtStyle`、`TTyRtDefault`、`TTyRtPiece` 等从 RichText 挪过来——caption 要把这些部件从标签阶段带到渲染。新增 `TTyRtBlockStyle`(站点手里的样式:`Needed`、`IsRich`、块样式、rich 样式)、`TTyRtGlobal`(根 textStyle 与 `richInheritPlainLabel` 的值,零值就是上游默认)、`TTyRtDrawn`、`TyRtPoint`(片段点落到画布:锚点加缩放加逆时针旋转)。样式多了「自己写了哪几项字体」和四个 inherit 标记;部件多了 `DefaultFill`/`DefaultStroke`(颜色来自宿主默认——悬停换色、独立文字在绘制时取皮肤色都靠它)。`TTyElementCaption` 多 `RtPieces`/`RtEmph`/`RtScale`。
- **新单元 `tyControls.AdvChart.RichStyle`**(纯,已进 `.lpk`):`TyRtResolve`(上面那套规则)、`TyRtFinish`(站点知道画块用的字体和 inheritColor 以后补齐 rich 缺的字体项、绑定 inherit)、`TyRtLay`(按缩放布局,量字器是设备 px,样式数值是 CSS px)、`TyRtBounds`/`TyRtDeviceBox`(zrender 的 getBoundingRect:所有子元素的并集,不画的行高矩形也算,描边矩形按画出的线宽外扩;~~无填充时至少 4~~——第二轮变异推翻:zrender 给文字盒子的矩形设了 `strokeContainThreshold = 0`,没有这个下限;另外作者给的文字描边也把那一片的框外扩,自动描边不算)、`TyRtReink`、`TyRtBlockMeasurer`(把块的尺寸当作文字尺寸答回去的量字器——轴的间隔与留白、图例的行、标题两行的高度都量块而不是量标记)。
- **什么时候走块**:rich,或有 padding、背景、有宽度的边框、width、height、lineHeight、文字阴影(没有宽度的 overflow、没有高度的 lineOverflow 在 zrender 里也不起作用,不算)。都没有的文字保持原来的一段字——测试断言整个 fixture 里只有两段文字是一段字(仪表盘的普通标题、盒子被禁的标题)。
- **系列标签**:`TTyLabelSpec` 带上 `Rt`、`RtGlobal` 和读出它的标签节点链(存成 JSON 文本——spec 比选项活得久);`TyLabelSpecOfNode` 每级都把节点接到链头、有需要时重新解析,所以条目、层级的 rich 沿链级联。展开时 `TyLabelBlockPieces`:块用标签字体,inherit 绑宿主填充,默认墨色/光晕取 `TyLabelInk` 对「没写颜色」时的答案,对齐取位置给的;形状是块的设备框。饼图、漏斗自己摆标签,也走同一个函数。悬停时 `TyCaptionToEmphasis` 换墨色也换部件(三处悬停都改用它)。
- **标注**:markPoint/markArea 在 `StyleLabel`、markLine 在自己的标签里按层级链解析;默认墨色是一段字本来会用的那个(内侧三档、外侧皮肤色与地色光晕)。
- **轴**:Builder 解析 `axisLabel`、`nameTextStyle`(轴名的 width/overflow 是 AxisBuilder 定死的 `truncate` + nameTruncate.maxWidth,nameTextStyle 写的不算——已有的 axisnames 基准守着这条),spec 带 `LabelRt`/`NameRt` 和两个量字器(Layout 所有量标签、量轴名的地方都经它们);放置完成后给每个显示的标签和轴名算部件。块的填充是作者色,没写时留空,画轴时由皮肤色补上。
- **标题**:两行各自解析(`DisableBox`),`TyLayoutTitle` 多两个可选量字器,副标题的位置按块高;部件存 `FTitleRt`,`TitleRt` 给测试。
- **图例**:`legend.textStyle` 解析进 `TTyLegendFont`;布局用块量字器;项的颜色既是块的 fill 也是 inheritColor。
- **仪表盘**:读数/标题节点写了 `rich` 才走块,块样式叠在上游读数默认值(width 100、lineHeight 30、padding [5,10]、透明底)上;底板就是块自己的矩形;`TyGaugeFormat` 多 `AKeepRich`,保留标记。
- **渲染** `TyRenderRtPieces`:矩形按 zrender 的 roundRect 夹圆角,既有填充又有边框时先描边;文字逐片段按旋转画,描边照一段字的做法做膨胀;阴影只画偏移的一份(画家没有文字模糊);没有模糊时不画——zrender 只在 `textShadowBlur > 0` 时才给 TSpan 设阴影(第二轮变异补)。

### 基准

- `test.advchart.richwiring`:fixture 的 74 个用例(第二轮后 79 个)全部经真控件(SSR 量字)画一遍,按组件、所属、文字找到端口的那段字,逐部件比:种类、画布上的位置(文字的点、矩形四角,1e-6)、尺寸、文字、对齐、字号字重、填充、描边与线宽、先描边、四角半径、是否画出。皮肤决定的不比:默认墨色与光晕、组件色、`inherit` 指到的调色板颜色只要求有;块字体由皮肤决定的(标题 18px bold 对皮肤 12)不比几何和继承来的字号,作者写的照比。另有:一段字标签不产生部件、带背景的产生;悬停只换默认墨色的片段;块标签的形状就是部件的设备框;containLabel 下 y 轴标签的 padding 真的让出网格。
- 首轮 16 处不对,两个真缺陷:皮肤没写字重时全局字重是 0(关掉继承的 rich 片段字重成 0);块量字器没绑 inherit,图例 `backgroundColor: 'inherit'` 的片段量出来没有矩形,图例整体窄了 6px。全量套件又抓到一个:轴名吃了 nameTextStyle 的 width。
- 另有:条目 rich 沿系列级联、经层级(旭日图)级联;根颜色进独立文字的 rich 片段而不进块;144 DPI 下部件仍是 CSS px(量字器按 DPI 答);饼图、漏斗标签成块(`inherit` 是扇区色)。

### 变异测试

18 个变异(继承开关、独立文字的根颜色、标题禁盒、rich 级联、块量字器的 inherit、DPI 缩放、标签 inherit、标签框取字的框、换墨不看默认标记、标注不解析、轴标签量字器、标题量字器、图例 inherit、仪表盘剥标记、条目链不级联、轴名 width、引擎默认标记、轴块填充取解析值)。首轮存活 5 个,都是基准缺用例:rich 级联与条目链(补了条目、层级两个用例)、DPI(补了 144 的用例)、轴名 width(axisnames 基准本来就杀,首轮只跑了本测试)、轴块填充(补了根颜色的用例)。补完全部杀死。

第二轮 21 个变异存活 7 个,逐个处理:

- **关掉继承的 rich 片段仍取普通标签的阴影**:片段本来就带阴影,基准没比。补上逐片段比阴影(有没有、模糊、偏移、颜色),加 `rich-inherit-off-shadow`。光有「标签写阴影 + 关继承 + 片段不写」杀不掉——片段缺的项在 zrender 里回落到块的阴影,块的就是标签的——所以用例里根 textStyle 也写了阴影颜色和偏移:上游片段取根的颜色和偏移、标签的模糊。
- **`'inherit'` 的填充不绑定**:inherit 指到的是皮肤的调色板色,fixture 说不了。补手写测试:柱内标签 `color: 'inherit'` 的片段是控件画柱子用的颜色,没写颜色的片段是默认墨色(白),两者不同。
- **字重 0 不改 400**:不是等价的。标签、图例、轴标签的皮肤规则都没写 font-weight,解析出来就是 0,站点把 0 交给 `TyRtFinish`。基准原先在块字重和上游不同时跳过字重比较,0 对 normal 于是整片跳过;改成块字重 0 按 400 比,另加手写测试断言皮肤字重是 0、片段是 400。
- **描边矩形不外扩 / 无填充不取 4**:fixture 每段文字加录上游 Text 自己的 `getBoundingRect`(守卫手算:无填充的 1 宽边框外扩正好 1,有填充的按加倍的 2),测试逐段比端口 `TyRtBounds` 落到画布的四角。一比就查出**两个真缺陷**:「无填充至少 4」是错的(zrender 给文字盒子的矩形设了 `strokeContainThreshold = 0`),删掉;作者写的文字描边要外扩 TSpan 的框,补上。再加两个图例用例(token 只有边框、边框加背景)看站点:图例项的宽是组的并集,图标一侧的外溢被组吞掉,端口按 `W` 量多算了半条线宽,三个项位置全偏。量字器加一个 `ITyTextBoxMeasurer`(块量字器实现,答框相对锚点的位置),图例用它按框的真实左右边组项。原来那个 4 的变异随之改成「把下限加回去」。
- **悬停不换默认描边**:核了上游,`_placeToken` 片段没有自己的 stroke 时取合并后样式的 `stroke`/`lineWidth`。补手写测试:`emphasis.label.textBorderColor/Width` 下默认描边的片段换成悬停的颜色和宽度,自带描边的保持。顺带发现端口根本不读 `emphasis.label.textBorderColor`(普通标签也一样),补上。
- **`baseline` 别名**:上游 `setTokenTextStyle` 确实在 verticalAlign 为空时读 `baseline`。加 `rich-baseline-alias`(24px 行里 top/bottom 两个片段),守卫核了位置。
- 另:加 `plain-shadow-offset-only`(只写偏移不写模糊,上游不设阴影),渲染器照此改成没有模糊不画,并补一个数像素的手写测试。

新加 5 个变异(文字描边不外扩、自动描边也外扩、图例不用框位置、悬停描边色不读、无模糊也画阴影)。这 12 个(原 7 个存活的加 5 个新的)重跑全部杀死。fixture 79 个用例,原 74 个除新增的 `bounds` 外逐字节不变,两次运行一致。

### 已知偏差

- 图例的 `legend.data[i].textStyle`、`emphasis.label.rich` 不读;悬停时 rich 只把默认墨色、默认描边的片段换成悬停的(上游里描边来自块样式、本来没描边的片段也会吃到 `emphasis.label.textBorderColor`,这里不换)。
- 矩形树图、旭日图、桑基图自己先截断/换行再盖章,rich 标记会被当成字截;没有用例。
- 漏斗 `color: 'inherit'` 的特殊规则不进块。
- 仪表盘的 rich 不接根 textStyle;文字阴影不模糊;`fontStyle` 仍画不出。

## 122. Tier 1 第八十七批：动画引擎（AN1，2026-10-01）

端口到现在没有动画：setOption 之后一帧画到位。Q7 承诺的「入场动画」要先有引擎——zrender 的 Clip、Track、Animator、Animation 和 Element.animateTo，加上 ECharts 读 `animation*` 选项、决定开不开、用什么时长缓动延迟的那一层。这一批只做引擎和选项解析，不接任何系列；AN2 起逐个系列接上。

### 上游的做法（zrender 6.1 / ECharts 6.1，`wf86/anim.md` 第 1、2 节逐行对照）

- **注意版本**：echarts-doc 里的 zrender 是 5.6.1，对照一律用 `D:/Projects/zrender`（6.1）。
- **模型**：一切都是元素上的属性补间。每个嵌套对象（元素自身、`shape`、`style`）一个 Animator，每个属性一条 Track，每个 Animator 一个 Clip；时间、延迟、时长、循环和**整段一种缓动**都在 Clip 上。每帧 `percent = clamp((now - (首次步进 + delay)) / life, 0, 1)`，`w = easing(percent)`，`值 = (to - from) * w + from`。
- **时钟从第一次步进算起**，不是从 animateTo 算起。浏览器里 setOption 末尾同步 flush 一次，所以同一次 setOption 建的 clip 起点都是那一刻，那一帧已经写回 from 值。`life || 1000`：时长 0 是 1000。延迟期间照样步进、percent 为 0，一直写 from。`percent === 1` 那一帧写 `easing(1)` 的结果并结束——终值是算出来的，0.7 → 0.1 停在 0.09999999999999998。循环重启保留相位：`start = now - elapsed % life`，负延迟从周期中间开始。
- **31 个缓动**按 JS 的运算顺序（`--k`、`k -= c` 先改 k，乘法左结合）；pow/sin/cos/acos 是 V8 的。弹性族的 `a = 0.1` 恒被改成 1、asin 分支是死的。**cubic-bezier**：正则 `/cubic-bezier\(([0-9,\.e ]+)\)/` 没有负号，`1e-1` 也不认；按逗号切、trim 后 `+`，缺的一项是 `+null = 0`（所以三个数的写法**能**解析，`d = 0`——`wf86` 说缺项是 NaN，是错的，fixture 为准）；四项和为 NaN 才放弃。根用盛金公式，平坦情形写了根却返回 0，于是 x(t) = t 的贝塞尔在开区间上恒为 0。名字查不到、大小写不对、空串一律没有缓动，即线性。
- **Track**：按第一帧定类型——数、一维数组、二维数组、颜色（解析成 rgba 插值，写回 `rgba(r,g,b,a)`，rgb 向下取整）、其余离散；类型不一致也离散。ECharts 的 animateTo 不允许离散动画：离散轨在 start 时直接跳到终值。数组按最后一帧对齐（长的截、短的补、NaN 取终帧的），原地写进元素的数组；Float32Array 每次存储都舍入到单精度。
- **animateTo**：嵌套对象在它出现的位置先递归、先建 Animator，元素自身的键最后建；先对同名目标的旧 Animator `stopTracks`（**已 start 未步进的，轨道先步回 0**——setToFinal 把元素留在终值，得把 from 放回去），再丢掉没变的键（非 force），setToFinal 时克隆当前值作第 0 帧、把目标值抄到元素上（同长的类型化数组不抄——这个怪癖照搬）。done 在全部结束且至少一个正常结束时调一次，during 只挂在第一个 Animator 上；没有 Animator 时 done 立刻调。
- **选项**：getShallow 先系列自己的选项（作者写的；没写的键才有系列类型的默认值，如折线的 easing 'linear'、K 线 300），再根选项，再全局默认（'auto'、1000/500、'cubicInOut'、阈值 2000，**没有** delay）。写成 null 的键往下落，也挡住类型默认值。`isAnimationEnabled`：animation 为真且数据量**严格大于**阈值才关。enter 读 `animationDuration/Easing/Delay`，update 读 `*Update`，**leave 什么都不读**：200 ms、cubicOut、0（`removeOpt || {}` 永远是对象）；更新载荷的 animation 覆盖三者。函数形式拿 dataIndex，有的调用点传 null。时长不大于 0 就不动画：停掉、直接设值、`during(1)`、done。

### 做法

- **新单元 `tyControls.AdvChart.Easing`**（纯）：31 个缓动、`TyCubicAt`/`TyCubicRootAt`、`TyCubicBezierParse`（正则语义逐字照搬，`Number()` 用 `TyJsToNumber`）、`TyEasingResolve`/`TyEasingApply`；`'@Name'` 走缓动句柄注册表。非二进制小数的常量从位模式取。
- **新单元 `tyControls.AdvChart.Anim`**：`TTyAnimClip`、`TTyAnimTrack`、`TTyAnimator`、驱动 `TTyAnimation`（双向链表、`Update(now)` 与上游的 update 一一对应、`ClipCount`、`OnWake`）、元素 `TTyAnimElement`（`AnimateTo`/`AnimateFrom`/`StopAnimation`/`Attr`）与现成的属性袋 `TTyAnimBag`。**目标是按点分的键**：`'x'`、`'shape.height'`、`'style.opacity'`，第一个点前的部分就是上游的 targetName；值是 `TTyAnimValue`（数、扁平数组——`Stride` 标二维、`Float32` 标类型化数组——字符串、布尔、null）。AN2 让图元派生自 `TTyAnimElement` 即可接上。时钟 `TyAnimClockMs`：单调来源、整毫秒、以 epoch 为基（小数延迟的舍入跟上游的量级一致）。
- **生命周期**：上游靠 GC；这里元素拥有它建的 Animator，结束的进墓地，只在引擎调用栈清空时释放——done 回调里销毁元素是合法的。元素销毁先把自己的 clip 从驱动上摘掉。引擎入口屏蔽浮点陷阱，NaN 照 JS 传播。
- **新单元 `tyControls.AdvChart.AnimOpt`**：`TTyAnimModel`（自己的选项、根选项、类型键、是否系列、数据量）、`TyAnimGetShallow`、类型默认表（`wf86` 2.1 的表）、`TyAnimIsEnabled`、`TyAnimGetConfig`、`TyAnimateOrSetProps` 与 `TyInitProps`/`TyUpdateProps`/`TyRemoveElement`/`TyFadeOutElement`；函数形式是 `'@Name'`，注册 `TTyAnimTimingHandler = function(ADataIndex: Integer; AHasIndex: Boolean): Double of object`。
- 三个单元已进 `.lpk`。

### 基准

- `tools/advchart-oracle/animation.js`（代理写，附 `wf86/anim.md`）：替换 `Date` 手动步进真 dist，67 个用例在 0…1500 ms 的 12 个采样点记录每个元素的动画属性、动画器数和活动 clip 数，以及每个系列 getShallow 的结果；缓动表 45 行 × 95 个点。6 条守卫。
- `test.advchart.animengine`（24 个测试）：
  - 缓动表逐位比较（4275 个值），resolved 标志一致；
  - **重放**：凡轨道全是数或数组、作用域只有 enter/update/leave 的系列元素，给属性袋 t = 0 的值、按用例自己的选项建模型、交给 `TyInitProps`/`TyUpdateProps`/`TyRemoveElement`，驱动在 T0 = 1700000000000 起的绝对时刻步进，每个采样逐位比较、比较元素的动画器数，以及「被重放元素的动画器之和 = 驱动的 clip 数」；全部动画元素都重放到的用例还比上游的 clips[]。bar-v 七个变体、bar-h 与堆叠六个、其余 186 个元素（散点、雷达、K 线、饼、漏斗、仪表盘指针与进度、折线裁剪矩形、柱/饼/折线更新、离场淡出、阈值）全部逐位对上——折线更新的点是 Float32 数组，靠的是存储时的单精度舍入和 setToFinal 的类型化数组怪癖；
  - 每个用例每个系列的 8 个 getShallow 值与 enabled；六个阈值用例；
  - 手写：时钟从首次步进起、延迟期写 from、stopTracks 步回 from、步进后不步回、stop 带 forwardToLast、leave 时序与载荷覆盖与不重复淡出、零时长直接设值、循环相位、终值差一个 ulp、Float32 舍入与怪癖、颜色字符串、离散跳变与不变的键、during 只挂第一个、life 0 = 1000、stopTracks 删除后跳过下一个动画器、数组按末帧对齐。

### 变异测试

`an1_mutate.py` / `an1_mutate2.py`：27 个变异。第一组 14 个是这批的要害：弹跳常数 7.5625、backIn 的 s 差一位、起点每步重定、起点不加 delay、上下两头的钳制、终值改成 `from*(1-w)+to*w`、终值在 w=1 时直接取目标、`_started === 1` 不步回、leave 时长 300、leave 读模型、leave 缓动改 linear、阈值 `>` 改 `>=`、去掉 Float32 舍入——全部变红。第二组 13 个：同长类型化数组也抄、不变的键不丢、life 0 不改 1000、during 挂到每个动画器、stopTracks 删除后不跳过下一个、颜色四舍五入、类型默认值不读、update 读 enter 的键、载荷不覆盖、平坦根计数、正则收负号、缺项取 NaN、不对齐数组。首轮存活 3 个：
- 「stopTracks 删除后不跳过下一个」：没有同一 targetName 上两个动画器、前一个整个被中止的用例——补了先后两次 animateTo 分别动 x、y，第三次同时动 x、y：上游只中止第一个，第二个被跳过、继续跑（动画器 2 个、clip 2 个）；
- 「不对齐数组」：所有用例的数组首尾等长、没有 NaN——补了不带 setToFinal 的短数组到长数组（前一帧补上末帧的项）与含 NaN 的数组；
- 「平坦根计数」：**等价变异**——这条分支写的根是 0，`cubicAt(0, y1, y2, 1, 0)` 恰好也是 0，计不计数结果一样。
补完后其余全部杀死。

### 已知偏差

- additive（只有 visualMap 连续型指示器用）、渐变插值、逐关键帧缓动、pause/resume、saveTo 与 `__changeFinalValue`（状态机，AN3）没做。
- 数字字符串按数插值；上游归为数却在加法里拼接字符串。字符串形式的 duration/delay 按 `Number()` 取；上游的字符串 delay 会拼到时钟上、让 clip 停在起点。未注册的句柄名当 NaN：时长句柄缺失即不动画。
- 只有一个关键帧且类型未知的轨道按离散处理（上游会写出 `'NaN…'` 之类的字符串）。
- `easingFuncs` 上的原型属性名（`toString` 等）不当缓动。
- 标签的淡入与位移（`#label` 元素）、线的符号逐个弹出（作用域为空的原始 animateTo）、effectScatter 的涟漪、仪表盘数值文字、标注这一批不重放：它们的时序规则在 AN2、AN4。

## 123. Tier 1 第八十八批：选中状态（B1，2026-10-01）

以前端口没有「选中」：`selectedMode`、`select` 块、饼图的 `selectedOffset`、select/unselect/toggleSelect 动作和 selectchanged 事件都不读；悬停高亮是覆盖层上临时画的一份，和任何别的状态都合不起来。`tyControls.AdvChart.Style` 里早就有一套两槽状态机，测试之外从没被调用过。这一批把上游的状态机照搬过来，选中挂在它上面，悬停也搬上去。

### 上游的做法（`wf87/states.md` §0、§1 逐行对照）

- **两层**：悬停、动作、选中只改元素上的**标志**——hoverState（0 常态、1 模糊、2 强调）、selected、`__highByOuter`（动作高亮的位）；下一帧 `applyElementStates` 把标志变成状态列表，**永远先 select、再 emphasis 或 blur**，交给 zrender 的 `useStates`：列表没变什么都不做；空列表所有键回到 rest；否则按列表顺序合并状态对象（后者赢），状态写了的键取状态值，其余回 rest。标签和引导线的列表永远等于宿主的，只在宿主的列表变了时跟着换。
- **默认代理**（`states.ts:225-341`，`emphasis.disabled` 时不装）在 `useStates` 那一刻按元素的**当前**值造状态：emphasis——没写 fill 时抬亮 fill，抬亮的起点在列表里有 select 且 select 声明了 fill 时是**选中色**，否则是常态色；只有没抬 fill 才抬描边；抬亮是每个通道 `×1.1|0`；z2 = 当前 z2 + 10，只在状态存在时（没有 emphasis 对象的标签不抬）。select——z2 = 当前 + 9。blur——当前不透明度 ×0.1（已在 blur 里就保持）。z2 加在**当前**值上，所以一直挂着状态的元素切一次涨一次（选中的扇区悬停进出：11、21、31、40、50……），只有空列表才回 rest。
- **选中模型**（`model/Series.ts:602-741`）：按**名字**（没有名字按 id）做键，同名的项一起选中，`getSelectedDataIndices` 只列第一个的原始下标；selectedMap 是 null、`'all'` 或对象，对象的键是 **JS 的键序**（整数样的键升序在前，其余按插入）。single 和 `true` 换掉整张表只留最后一个；multiple 累加；series 设 `'all'`。unselect 在 series 模式或 `'all'` 时清空一切，否则 `map[name]=false`、下标表记 -1。`select.disabled` 的项进表也进下标，但永远不显示选中。数据项写 `selected: true` 在建模时先选上。
- **动作与事件**（`echarts.ts:2150-2272、3375-3412`）：按 seriesIndex（数组按给的顺序）> seriesId > seriesName 找系列，都没写就是所有系列；按 dataIndexInside（照用）> dataIndex（原始，经 indexOfRawIndex）> name（第一个同名的内部下标）找项。先发不精炼的事件（payload 的拷贝、type 小写：select/unselect/toggleselect），再发 selectchanged `{selected: 显示中的系列里有选中的那些 {dataIndex: 原始下标[], seriesIndex}, isFromClick, fromAction, fromActionPayload, escapeConnect: true}`；**只有注册了处理器**时才发旧事件：点击→map/pieselectchanged，动作 select→*selected，unselect→*unselected，toggleSelect 没有；每个出现在 selected 里的**饼**系列一次（map 那组也只认饼）。
- **点击就派发**（`echarts.ts:2341-2357`）：宿主/父链上第一个带 dataIndex 的元素，selected 就 unselect，否则 select——**不管 selectedMode**；关着的系列照样发 select 和 `selectchanged {selected: []}`，点两次还是 select。顺序：select 的事件在用户的 click 之前。标注也带 dataIndex（标注数据里的序号）和宿主的 seriesIndex，点标注会对宿主系列的同号项派发 select。
- **各类型的样子**：柱的默认 select 是 `{borderColor: tokens.color.primary, borderWidth: 2}`（散点只有边框色），饼、折线没有；饼的 select 平移 `(cos(中角), sin(中角)) × selectedOffset`（系列级，默认 10），标签（布局位置加平移）和引导线一起走，emphasis 半径 = 布局半径 + scaleSize；折线符号 emphasis 缩放 `max(1.1, 3/(size/2))`，select 只有 z2；折线的整条线跟着每个符号的悬停变（onHoverStateChange）。标签在任何状态的 `label.show` 为真时就建出来，常态不显示时 ignore，状态的 show 和常态不同时才翻。

### 做法

- **新单元 `tyControls.AdvChart.States`**（纯，已进 `.lpk`）：`TTyStElement`（标志、三种声明的状态对象、rest 与当前值、当前列表、是否装了代理）、`TTyStItem`（宿主、标签、引导线）、`TyStUseStates`（上面那套 useStates 与默认代理）、`TyStApplyItem`（applyElementStates）、进出 emphasis 与 hbo 位；选中模型 `TTySelModel` 与 select/unselect/toggle/isSelected/indices/initFromData/mapJson，JS 键序在 `MapSet` 里。能变的键：fill、stroke、lineWidth、opacity、z2、平移 x/y、扇形半径、符号缩放、ignore；几何是设备 px，颜色打包。
- **控件**：`FSt` 按系列下标、按**原始**下标存每项的状态（过滤不搬家），每次建完显示列表 `StSync` 认元素（宿主、已摆好的标签、引导线、折线与面积）、刷新 rest 和声明、同步 selected 标志、应用标志，再 `StWrite` 把当前值写回元素。**帧 = 下一次绘制**：标志变了只记脏，`RenderTo`/`RenderCached` 开头 `StApplyChanged`，有元素变了就丢静态层——一次点击（移动、按下、松开、click）之间没有帧，和上游一样只算一帧，z2 不多爬。`Relayout`（Invalidate、换尺寸）算上游的整体更新：先回 rest、套旧列表、再套标志。
- **悬停搬到标志上**：柱、饼、折线/散点（笛卡尔，日历和雷达之外）。在 A3 的 mouseout/mouseover 判定处离开/进入 emphasis（`TTyChartEventTarget` 多了派发者 `HdKind/HdSeries/HdRow`），emphasis 禁用的不是派发者，hbo 非零的不理会；画在静态层。覆盖层不再画这几类的项悬停；坐标轴触发的整列高亮仍走覆盖层，跳过已经由标志点亮的项。其余系列类型的悬停原样留在覆盖层。
- **公开接口**：`DispatchAction(JSON)`（select/unselect/toggleSelect/highlight/downplay，batch 与未知类型答 False）、`SelectedDataIndices`、`SelectedMapText`、`ItemStates`、`LineStates`。事件走 A3 的路：`TTyChartEvent.Payload` 是动作事件的 JSON，查询对它们不过滤（上游 eventInfo 为空）；`TyChartEventTypeOf` 认这十二种。highlight/downplay 只做事件和 hbo 位（highlightKey 按首次使用编号），模糊是 B2 的。
- **样子**：柱/散点默认选中边框取皮肤的**标题字色**（上游的 tokens.color.primary 就是标题色，走皮肤令牌而不硬编码 `#3c3c41`）；rest 没有描边时线宽按 zrender 默认 1；饼的平移用 `TyJsCos/TyJsSin`；声明的 `select.itemStyle`、`select.label.color/show`、`emphasis.*` 按数据项→系列读。标签只因状态才显示时建成 `Ignore` 元素（`TTyChartElement.Ignore`：不画、不命中）；饼的引导线带上扇区的 datum（仍 silent，`IsGuide`）。
- **顺带修的**：折线符号的 z2 一直是系列的 z2（0），上游是 100——悬停时整条线抬到 10 就盖住了所有符号、也挡住它们的命中。改成 100，和散点（第 71 批）一致。整体换 option 时 A3 记着的悬停目标作废（上游那是被删掉的元素，下次移动重新 over）。

### 基准

- `tools/advchart-oracle/select-legend.js`（代理写，附 `wf87/states.md`）跑真的 dist：38 个用例、194 步、240 个事件，自带规则转写逐步重放全部对上，27 条守卫，两次运行逐字节一致。B1 的 17 个用例（`pie-*`、`bar-*`、`line-select`、`action-select-*`、`emphasis-disabled`）：90 步、157 个事件、523 个项快照。
- `test.advchart.select`：每步经真控件（`MouseMove/MouseDown/MouseUp`、`DispatchAction`，SSR 量字），渲染一次当一帧，比较：事件的类型、顺序与 payload 每个字段（旧事件的 `<auto id>` 只要求是字符串，fpjson 读回会吞掉 `\u0000`，原文另测）；selectedMap（键序也比）与选中下标；每项的列表、标志、代理；**画出来的**——显示列表里宿主的 fill/stroke/线宽/不透明度、z2 相对 rest 的距离、扇形的平移/半径/角度、柱的矩形、符号的中心与缩放、标签的位置/隐藏/墨色/z2、引导线的平移、折线。颜色按皮肤映射：fixture 里等于 rest 色的就是端口的 rest 色，它的抬亮就是端口 rest 的抬亮，`#3c3c41` 是皮肤标题色，其余是声明色、逐位比。状态机算的几何（平移、半径、符号缩放）逐位比；从显示列表读回的位置容差 1e-9（平移加到中心上再减回来不一定等于平移本身），饼标签的 rest 位置 1e-6。z2 比到 rest 的距离（端口的 rest z2 是自己的）。
- 首跑就过的之外，全量套件抓到四处：A3 的 mouse-events fixture 里本来就录了 `pub` 处理器收到的 select/selectchanged，过去因为端口不认这些类型被滤掉；现在补注册 `pub`，**全 fixture 每种系列的点击都比 select 事件**——一比就查出标注点击要派发 select（上面那条上游行为）；图例悬停的 highlight 是 B3 的，按名滤掉。一个 visualMap 把符号尺寸映成 NaN 时，声明阶段对 NaN 做有序比较在 FPU 陷阱下抛异常，改成先判 NaN。一个旧测试在同一控件上换两次 option，悬停目标没作废，第二次悬停不 over。
- 另有手写：遗留事件没有注册就不发（OnChartEvent 不算注册）、z2 爬升与空列表复位、batch 与未知动作拒收，以及下面变异补的六条。不属于 B1 的用例顺带跑了一遍：`highlight-bar`、`highlight-pie` 已经全对，其余 focus/blur 与图例的留给 B2、B3。

### 变异测试

45 个变异：列表顺序（emphasis 先合并）、single 留第一个、multiple 换表、series 当 multiple、series 的 unselect 只清一项、`true` 不算 single、按下标做键、unselect 不记 -1、关掉的系列点击不派发、select 在用户 click 之后、disabled 也显示、抬亮总从常态色起、描边与填充都抬、select 抬 10、emphasis 抬 9、z2 不爬（两处）、标签也抬/不抬、禁用仍装代理、饼的 cos/sin 对调、按起始角平移、selectedOffset 不读、标签不跟扇区走、引导线不跟、柱没有默认边框、scaleSize 不读、标志当场应用而不是等帧、折线不跟符号、map 旧事件不认饼、toggleSelect 也发旧事件、isFromClick 丢掉、`'all'` 的下标为空、JS 键序不管、name 取最后一个、dataIndex 当内部下标、`selected: true` 不读、状态的 label.show 不读、状态的标签墨色不写、悬停不管 hbo（进/出两处）、禁用项也接高亮、符号缩放 1、折线符号 z2 回到系列的。

首轮 44 个（一个锚点失配，改后重跑）存活 6 个，五个是基准缺用例，补手写：
- 「`true` 不算 single」：fixture 没有 `selectedMode: true`——补 `[0,2]` 选中后表里只有最后一个。
- 「toggleSelect 也发旧事件」：唯一的 toggleSelect 让饼什么都没选，本来就不发——补一个 toggle 后留着选中的。
- 「JS 键序不管」：名字都不是数字——补 `b、10、02、2`，表是 `{"2","10","b","02"}`、下标 `2,1,0,3`。
- 「name 取最后一个」：重名用例只用点击——补按名选重名项，下标只有第一个。
- 「dataIndex 当内部下标」：没有过滤——补 dataZoom 过滤掉前两个类目，dataIndex 3 是内部 1。
第六个「悬停 over 不管 hbo」在 B1 里是**等价变异**：hbo 非零的项一定已在 emphasis（没有模糊就没有别的去处），over 再设 2 不变；上游 `highlight-focus` 里「带 hbo 却显示 blur」的项要 B2 才有，届时会杀它。**[第 90 批：B2 的重放杀死了它，见 §125。]**另加「悬停 out 不管 hbo」变异，配手写「动作高亮的柱悬停进出仍亮着、downplay 才灭」，杀死。补完重跑全部杀死（等价的那个除外）。

### 已知偏差

- 状态机只接了柱、饼、笛卡尔上的折线/散点/涟漪散点。其余类型（漏斗、雷达、K 线、象形柱、热力图、关系图、树系……）选中模型、动作和事件都有，**没有选中的样子**，悬停仍在覆盖层；它们的默认选中边框（漏斗、关系图、热力图、桑基图、象形柱）随之没有。关系图的边（dataType edge）不进选中模型，selectchanged 的项也不带 dataType。
- highlight/downplay 只有事件与 hbo 位：动作前的 allLeaveBlur、按 focus 的 blurSeries、`notBlur`、折线单点高亮落在符号路径上（悬停离开会清掉它）都是 B2；`excludeSeriesId` 读了。悬停的 focus/blur 也是 B2。**[第 90 批已做，见 §125；漏斗、热力图、K 线、象形柱、旭日图与日历上的散点也接上了状态机。]**
- 整体更新（Invalidate、换尺寸）后先回 rest、再套旧列表、再套标志，这条照上游写了但没有 B1 的用例；上游 `legend-pie` 里那一步（z2 继续爬）和过滤后饼的内部/原始下标对应都是 B3 的。
- payload 没写任何下标字段时什么也不做（上游会对 `undefined` 做选择，拿到 `'e\0\0undefined'` 之类的键）；越界的下标丢掉；batch 不收；动作要在第一次渲染之后（选中模型要建好的数据）。
- 饼常态不显示标签、只在状态里显示时不建标签（上游一直有一个 ignore 的 Text）；状态的 `label.show` 决定是否建标签只读系列级。内侧标签在选中色上不重新挑墨色，标签不透明度不写（模糊在 B2）。
- 渐变不抬亮（原有偏差）；z2 只比到 rest 的距离：端口的 rest z2 自己的（柱 0、饼 0、标签宿主 +1），折线符号已改成上游的 100。
- 旧事件只在 `ChartOn` 注册了该类型时才发，发出时 `OnChartEvent` 也收到一份。

## 124. Tier 1 第八十九批：入场动画（AN2，2026-10-01）

AN1 有了引擎，没有一个系列用它。这一批把驱动接进控件，按 fixture 的顺序把入场动画逐个接上：柱（竖、横、堆叠）、散点、折线（裁剪矩形、符号逐个弹出、符号标签淡入）、饼（扫开、`scale`、玫瑰）、漏斗、仪表盘（指针、进度弧）、雷达、K 线，以及 LabelManager 的标签淡入与引导线描入。热力图格子、坐标轴、图例、标题不动。

### 上游的做法（`wf86/anim.md` 第 3A、3B 节；源码逐行核过）

- **柱**：`animationModel` 为真时创建器先把高（横放时是宽）置 0，再 `initProps(el, {shape: layout}, seriesModel, dataIndex)`；x、y 不动，y 是起点或堆叠底，负值往下长。堆叠的两层各自从自己的底长。
- **散点**：符号路径 `scaleX/Y` 从 0 到 `size/2`、`style.opacity` 从 0 到自己的不透明度，绕路径原点（数据点加 symbolOffset）缩放，入场时序、带 dataIndex；两个动画器、两个 clip。
- **折线**：`hasAnimation = !ssr && get('animation')`——**不看阈值**。裁剪矩形 `createGridClipPath`：区域按线宽一半外扩、宽向上取整、x 有小数时取整并补 1；横向基轴从宽 0 长出（inverse 从右边），竖向从底边长出；`initProps` 不带 dataIndex（延迟函数拿到 null），带 done，所以是 force 动画。符号是原始 `animateTo`：先 `scale 0`，200 ms、**没有缓动**、`setToFinal`，延迟 = `duration × ratio + delay`（ratio 是符号在加 0.1 的区域里沿基轴的位置，inverse 取 1 − ratio；没有区域时 `undefined === undefined` 得 0），延迟写成函数时整条换成 `delay(idx)`；符号的标签 `animateFrom opacity 0`、300 ms、同一个延迟，并关掉 LabelManager。
- **饼**：首次渲染取第一个起始角不是 NaN 的扇区的 `startAngle` 当共同起点，每个扇区两个角都从它补间到自己的；`animationType: 'scale'` 只把 r 从 r0 长出。
- **漏斗**：多边形不透明度从 0 到 `itemStyle.opacity ?? 1`。
- **仪表盘**：指针 `rotation` 从 `-(startAngle + π/2)` 到值的角，进度弧 `endAngle` 从起始角长出，都不带 dataIndex。
- **雷达**：折线和多边形的点全从中心长出；多边形**总在**（没写 areaStyle 也在、也动）。符号不动（fixture 已确认）。
- **K 线**：8 个点的数值维从开盘价的像素长出（`transInit`），300 ms linear。
- **标签**（`LabelManager._animateLabels`）：系列 `isAnimationEnabled` 时，新标签 `opacity 0 → 1`、入场时序、带 dataIndex；`valueAnimation` 的不淡入；引导线 `strokePercent 0 → 1`、不带 dataIndex，和文字的条件无关。宿主动的时候，zrender 每帧按宿主当前的矩形重算文字位置（`updateInnerText`），所以柱顶的标签跟着柱子长。

### 驱动与分层（照 Q7 / §32）

- **一个图表一个 `TTyAnimation`**。时钟 `AnimNow`：NaN 用机器时钟（`TyAnimClockMs`，以 epoch 为基的整毫秒），数字是测试注入的——照 `DataZoomNow` 的样子。
- **同步的第一步**：选项落地后第一次构建绘制列表时布防（创建代理、开动画），紧接着 `Update(now, True)`——上游 setOption 末尾的 flush。同一次绘制已经画出 from 值。挪到下一个 tick，所有时间线都会错开最多 16 ms。
- **16 ms 的 `TTimer`**：有 clip 时开，每一跳 `AnimTick(now)`（推进 + `InvalidateFrame`），clip 清空时停。测试直接调 `AnimTick`；注入了时钟就不开定时器。
- **分层**：动起来的系列属于**动态层**。动画进行中，静态层只画外框和坐标轴（列表照样构建，命中测试要用它），系列、图例等列表元素和标题在动态层逐帧画；最后一个 clip 结束时丢掉静态层，下一帧把静态的系列（静止值）画回静态层，动态层又空了。`HasDynamicContent` 多一个「在动」。一帧的代价是一次 blit 加动态层的那张 BGRA 位图（Q7 量过约 13 ms 的底价）加系列本身；标题跟着进动态层，是为了仍盖在系列上面。
- **什么时候不动**：任何重新布局（尺寸、主题、PPI、dataZoom 同步、树的漫游）都直接到终值——上游 resize 派发 `{duration: 0}`；新的选项再布防一次。AN2 里每次布防都按「首次渲染」处理（同一系列的更新动画是 AN3 的）。

### 绑定：代理

绘制列表每次静态渲染都重建，动画得比它活得久，所以动的不是元素，是**代理**：`TTyChartAnimProxy`（`TTyAnimBag` 派生）按 (系列, 视图行, 角色) 存上游的属性——柱的 `shape.x/y/width/height`、符号的 `scaleX/scaleY/style.opacity`、折线的裁剪矩形、扇区的六个形状量……键名与上游一致，测试直接拿 fixture 比。

- **构建器打标签**：`TTyChartElement` 多一个 `Anim: TTyChartAnim`（角色、键、上游的几何数、标签的宿主与挂法），零值 `carNone` 即不动。柱存裁剪之后带符号的 layout；散点存路径原点和半尺寸；折线符号存点和加 0.1 的区域及基轴方向；折线的线和面存 clip:false 加宽之前的矩形和加宽量；饼和进度弧存**没被 `TyShapeSector` 换过序**的上游角度；指针存枢轴、值的角和起始角；K 线的体和两根影线共用 [开盘价、实体两端、最高最低、脊线、实体两侧]；`TyExpandLabels` 产出的标签记下宿主的插入序号和挂法（位置、距离、`[x, y]` 两项、描边外扩）。饼、漏斗的标签和引导线是绝对定位的，上游也不跟宿主。
- **新单元 `tyControls.AdvChart.AnimView`**（纯，已进 `.lpk`）：`TTyChartAnimSet.Arm` 按上表逐个角色建代理、开动画（`TyInitProps` / 原始 `AnimateTo` / `AnimateFrom`），`Bind` 在每次重建后按键找回代理，`TyAnimBuildFrame` 把列表按代理当前值改写成**这一帧**（插入序号不变，所以动画中命中测试打在帧上，名字仍是列表的元素），跟随标签按「宿主现在的矩形上的锚点 − 静止矩形上的锚点」平移。代理每个键都等于布局值时元素原样不动，所以停下来的图就是静态的那张；差一个 ulp 的静止值照画在那里。
- **控件**：`AnimationMode`（published，`camAuto` 默认 / `camAlways` / `camOff`）、`AnimNow`、`AnimTick`、`AnimClipCount`、`AnimLive`、`AnimProxyCount/AnimProxy/AnimFindProxy`；受保护的 `AnimFrame`。选项里的 `animation: false`（根或系列）在任何模式下都关。

### 现有测试与无头渲染：只在窗口上动

上游每次 setOption 都动。这里的控件还有第二种渲染：`RenderTo`——导出（`SaveToPng`）、设计器、以及几千个按静态版式断言的无头测试。**定为：`camAuto` 只在控件自己的窗口绘制（`Paint`）里布防**；无头渲染画完成态，选项留着等窗口的第一次绘制。设计器任何模式都不动（它没有定时器）。测试动画的地方显式 `camAlways`。没有给现有测试加一行 `animation: false`。示例截图工具（`scripts/make-gallery.ps1`）截的是窗口，要等动画结束（约 1.5 s）再截，或在示例上设 `camOff`。

### 基准

`test.advchart.animenter`（8 个测试）：

- **时间线**：fixture 里 57 个 enter/threshold 用例（effectScatter 除外），真控件 400×300、zrender 的 SSR 量字、`camAlways`、时钟停在 T0 = 1700000000000 渲染（这次渲染就是第 0 个采样），然后 `AnimTick` 到每个采样。fixture 的元素按 id/role/type 映射到代理（`series0:bar/3` → (0, 3, bar)，`0.k.0#label` → 符号 k 的标签，`1#clip` → 裁剪矩形，`k#guide` → 引导线……），每个采样比：每个被记录的键**逐位比**，终值也算在内；唯一的例外是 K 线实体两侧的横坐标——上游做了 subPixelOptimize、端口没有，上下游都不动——比**权重** `(v − from)/(to − from)`（全程为 0，到 1e-9）；fixture 没追踪的键必须不动；代理的动画器数等于元素的；clip 数等于上游的减去推迟元素的动画器数。4668 个元素采样全部对上，其中 576 个按权重。
- **静止**：clip 清零后不再 live；每个键要么等于布局值，要么正好是 `(to − from) × 1 + from`；再渲染一次，凡代理静止在布局上的元素，帧与静态列表逐位相同。
- 手写：无头 `camAuto` 不布防而 `camAlways` 布防；`camOff`、`animation: false`、中途切到 `camOff`；动态层（t = 0 时最高那根柱子三分之一处是地色，结束后是柱色）；柱顶标签跟着柱子走、半透明；热力图只有标签在动；新选项再动一次、改尺寸直接到终值；clip:false 的上游怪癖（见下）。

### clip:false 的怪癖，照搬

折线 `clip: false` 在 `createGridClipPath` 返回**之后**才把裁剪矩形沿值轴加宽；而裁剪动画带 done、是 force 的，四个键都有轨道，第一帧就把没加宽的 y 和 height 写回去。所以上游开着动画时 clip:false 的线最后仍被裁在网格里，关掉动画才真的不裁。用真 dist 探针核过（动画：静止在 y 64、height 157；关动画：y −238、height 761）。端口照搬，测试守着两种情况。

### 变异测试

`an2/mutate.py`：24 个变异，逐个改源码、重编、只跑本测试、还原——柱从 0 长（竖、横各一）、饼的共同起点（每片从自己的起点；取最后一片而不是第一片）、折线符号延迟的三项（`duration × ratio`、`+ delay`、函数按行号调）、符号标签 300 ms、散点缩放的终值与从 0、同步的第一步、阈值（只看 `animation`；数据量当 0）、热力图格子也淡入、引导线、雷达面总在、K 线从开盘价、指针的起点、裁剪矩形的起始宽、clip:false 加宽之后、标签跟随、valueAnimation 不淡入、动态层画列表而不画帧、无头也布防。

首轮存活 1 个：**散点缩放的终值改成 1**。基准原先在「端口终值与上游不同」时一律退到比权重，而权重对终值不敏感——5 和 1 的 0…1 曲线一模一样。这条退路本来只为 K 线实体两侧的 x 准备，却对所有键敞开。改成：终值不同就是错，唯一的例外是 K 线、而且那个坐标在上下游都不动。收紧后重跑，24 个全部杀死。

### 推迟与偏差

- **AN4**：仪表盘读数的数值滚动（`valueAnimation`，fixture 的 `style.text`）、`bar-label` 的标签数值滚动、折线的 `endLabel`、markPoint/markLine/markArea、effectScatter（符号以更新时序缩放 + 涟漪）。测试里这些元素的动画器从上游 clip 数里扣掉。
- **AN3**：同一系列的更新、离场，饼的后续扇区只扫 endAngle，折线的数据差分；现在第二次 setOption 当作新的入场。
- 这一批没接：象形柱、箱线图、关系图/树/矩形树图/旭日图/桑基图的入场；它们的标签也不淡入（LabelManager 的淡入只给柱、散点、热力图、饼、漏斗）。雷达符号的标签端口本来不画。K 线 simple 模式（实体窄于 1.3 px）不动；部分出界的 K 线没有静态裁剪。
- 悬停高亮在动画中画的是静止几何（`PaintEmphasis` 读列表）；命中测试已经跟着帧走。
- 饼在端口里先滤掉负值，视图行号与上游的 dataIndex 在有负值时不一致（延迟函数拿到的序号不同）。
- 一帧仍要开一张控件大小的 BGRA 位图画动态层（Q7 那 13 ms 的底价）；动画期间所有系列、图例、标题都在动态层，不按元素是否在动细分。

## 125. Tier 1 第九十批：聚焦与淡化（B2，2026-10-01）

B1 把悬停、选中、动作高亮搬上了标志加状态代理的模型，但 highlight/downplay 只记 hbo 位、不淡化别的东西，`emphasis.focus` / `blurScope` 除了关系图和树谁都不读，而且状态机只接了柱、饼和笛卡尔上的折线/散点。这一批把上游的 blurSeries / allLeaveBlur 接到同一套标志上，把 highlight/downplay 补成上游的三步，并把状态机推到更多系列类型。

### 上游的做法（`wf87/states.md` §2、§3；`util/states.ts`、`core/echarts.ts` 逐行核过）

- **highlight / downplay**（`echarts.ts:2178-2205、1792-1865`）：每次派发**先 allLeaveBlur 一次**；然后对查询到的每个系列（排除 `excludeSeriesId`），highlight 且没有 `notBlur`、系列级 `emphasis.disabled` 不为真时，按 payload 指的那个元素的 focus 去 blurSeries——指的是列表时取第一个，`|| 0`，那里没有元素就取第一个有元素的，一个都没有才读系列选项（`states.ts:545-586`）；**这一遍对所有系列做完之后**，才逐个系列 enter/leave emphasis：查询到的项（没写就是全部）里是派发者的那些，hbo 置/清 highlightKey 的位，清空后才离开 emphasis。
- **折线的单点高亮**（`LineView.ts:937-1026`）：先 `_changePolyState`（折线和面积直接设标志），payload 是**单个**非负下标时走 `Symbol.highlight()`——`enterEmphasis(符号路径)`，位落在**路径**上、固定是第 0 位、不查是否派发者；列表走整系列的分支（符号组带位）。downplay 那边 `dataIndex >= 0` 对只有一个元素的列表会被 JS 强转成数字，于是也走路径。悬停的派发者是符号**组**，组上没有位，所以悬停进出会把动作高亮清掉（surprise 9）。
- **悬停**（`states.ts:638-695`）：over 先按派发者的 ecData.focus / blurScope 做 blurSeries，再在派发者没有 hbo 时进入 emphasis；out 先 allLeaveBlur，再在没有 hbo 时离开 emphasis。`emphasis.disabled` 的元素根本不是派发者：悬停它什么都不发生（连 allLeaveBlur 都没有）。
- **blurSeries**（`states.ts:429-517`）：focus 假值或 `'none'` 不做；`blurScope` 假值当 `'coordinateSystem'`。逐个**显示中**的系列：坐标系取 `coordinateSystem.master`（笛卡尔的是 grid），两边都有才比，**没有坐标系的只和自己相同**；`scope 'series'` 且不是同一系列、`'coordinateSystem'` 且不同坐标系、`focus 'series'` 且是同一系列，三者之一就跳过；其余整个视图组里每个元素进 blur，**只有** `focus 'self'` 且同一系列时跳过带 hbo 的元素；focus 是下标数组时（树系）再让这些下标的元素离开 blur——对**每一个**被淡化的系列都用目标系列的下标；记 isBlured。focus 的取值只和 `'self'`、`'series'`、`'none'` 比较：其他任何真值（`'adjacency'` 放在柱上、`true`）都淡化范围内的一切、包括自己系列，而且不放过带 hbo 的元素；`blurScope` 写成既不是 `'series'` 也不是 `'coordinateSystem'` 的值就等于全局。
- **allLeaveBlur**（`states.ts:404-427`）：isBlured 的系列整组离开 blur（只把 1 变回 0），全部 isBlured 清掉。
- **折线**：符号组每次 hoverState 变化、折线自己的变化，都经 `onHoverStateChange` 把折线和面积设成同一状态；blurSeries 遍历视图组时折线本身也在里面（没画符号的线也会被淡化）。
- **标签**：状态列表永远等于宿主的；blur 的默认代理给标签自己的不透明度乘 0.1，`blur.label.opacity` 声明了就用声明值。饼永远有一个 Text：常态隐藏、没有任何状态 `label.show` 时它只有 select 状态对象——emphasis 不抬 z2，但 blur 代理照样给它 0.1（surprise 13）。
- **旭日图**（`SunburstPiece.ts:152-160`、`SunburstSeries.ts:270-281`）：focus 默认 `'descendant'`；`ancestor`/`descendant`/`relative` 在建元素时就换成数据下标（祖先从根到自己，子树前序，relative 两者相连；根的下标没有元素）；系列默认 `blur.itemStyle.opacity 0.2`、`blur.label.opacity 0.1`；没有坐标系。
- **各类型**：漏斗、热力图、象形柱、散点的默认选中是 `borderColor: tokens.color.primary`（不带宽度）；K 线的 emphasis 默认 `borderWidth 2`，每个状态按涨跌取 `color`/`color0`、`borderColor`/`borderColor0`（缺边框用颜色），**body 与影线是同一条路径**；象形柱的每个图形各有状态，`emphasis.scale`（默认 false）放大 1.1；漏斗的 emphasis 标签默认显示。

### 做法

- **`States` 单元**：`TTyStItem` 多了符号组自己的 `GroupHover / GroupHbo`（`HasGroup`：折线、散点、涟漪散点的符号，宿主是路径）和 `Parts`（同一派发者下各有状态的其余路径，象形柱的其余图形，列表跟宿主走，和标签一样）。项级的纯函数：`TyStItemHoverEnter/Leave`（看派发者的 hbo）、`TyStItemEnter/LeaveEmphasisBy`（`AOnPath` 即 Symbol.highlight）、`TyStItemEnterBlur`（`ASpareHeld`）、`TyStItemLeaveBlur`；组的每次变化经 `APoly` 带上折线。`TTyStFocus`（none/self/series/other/indices）与 `TTyStScope`、`TyStFocusOf/ScopeOf/BlursSeries` 按上面的比较规则；`TyStFind` 沿节点链取原值。
- **控件**：`StBlurSeries / StAllLeaveBlur`（系列的 `IsBlured`）、`StCoordKey`（`grid<n>`、`calendar<n>`、`radar<n>`，没有坐标系是空串）、`StItemFocus`（数据项 → 旭日的层级 → 系列；旭日的词换成下标）、`StDispatcher`（数据项、折线、面积三种派发者；disabled 不算）。`StHoverOver/Out`、`DoHighDownAction` 照上游的顺序重写；B1 那个把折线 hbo 置位的整系列高亮改成直接设折线状态。
- **标签**：rest 不透明度取宿主建出时的（上游的 defaultOpacity），blur 时写回元素；状态标签读 `[state].label.opacity`。饼的标签没建出来时补一个**不画的**状态元素（只有 select 对象，除非某状态的 `label.show` 写了），让它照上游吃 blur、不抬 z2。漏斗的引导线带上带的 datum、标成 guide，跟着带走状态。
- **推到更多类型**（`TTyStKind`）：热力图（笛卡尔与日历，`sskRect`）、漏斗、K 线（实体是宿主，影线是**跟随者**：取宿主改过的描边/线宽、宿主的不透明度、同样的 z2 增量，不取宿主抬亮的填充）、象形柱（第一个图形是宿主，其余是 Parts，透明的条形命中框不动）、旭日图，以及日历上的散点/涟漪散点（B1 排除了日历；元素和笛卡尔的一样）。这些类型的悬停不再走覆盖层。
- **命中**：折线的命中容差改成 zrender 的 `max(线宽, strokeContainThreshold 5) / 2`（原来是半线宽加 4，即 5 px）——fixture `focus-series-coord` 里柱子中心离折线 3.9 px，上游命中柱子，端口原先命中折线。

### 基准

- `tools/advchart-oracle/select-legend.js` 加了 7 个用例：`focus-funnel-self`（无坐标系的漏斗 self，标签和引导线跟着淡化、按下标高亮）、`focus-heatmap-scatter`（同一 grid 上的热力图 series 与散点 self+series 范围，散点的高亮位在**组**上、悬停不清它）、`focus-candlestick`（K 线淡化同 grid 的折线、emphasis 边框 2、整系列高亮）、`focus-truthy-other`（focus `'adjacency'`、blurScope `'nope'`：自己系列也淡化、饼也淡化、带 hbo 的不放过）、`focus-self-held`（self 放过带 hbo 的元素）、`focus-sunburst`（默认 descendant、默认 0.2/0.1、按节点高亮）、`focus-sunburst-ancestor`（系列 ancestor、单个节点 relative）。规则转写跟着扩展（旭日的树、下标 focus 的离开 blur、各类型默认选中/强调、散点是 Symbol），新增 7 条守卫（self 放过 hbo、真值 focus、未知 scope、K 线边框、旭日默认 focus、下标离开 blur、旭日默认不透明度）。整份 fixture 45 个用例、234 步、251 个事件，转写逐步全对，34 条守卫全过，两次生成逐字节一致。
- `test.advchart.focusblur`：B1 的重放器提成 `TAdvChartSelectHarness`（B1 的测试改为继承它），重放 18 个 B2 用例（原有 11 个加新 7 个）共 100 步、35 个事件、752 个项快照：事件、标志（派发者的 hbo、折线路径的 phbo、组的 hoverState）、列表、画出来的颜色/不透明度/z2/几何、标签（列表、隐藏、墨色、**不透明度**、z2；饼不画的标签只比状态机的值）、折线（列表、描边、线宽、**不透明度**，状态机与画出来的都比）。上游没有元素的项（旭日的虚根）端口也不能有记录。
- 首跑：原有 11 个用例只差 `focus-series-coord / -global` 的一步——就是上面折线命中容差的问题；新用例只差 K 线（重放器取了影线当宿主、线宽只在描边变了时比），改了重放器后全对。
- 手写 11 个：象形柱的图形一起变（抬亮、z2+10、放大 1.1、条形框仍无墨、B 淡化）；K 线影线跟随实体（淡化到 0.1、z2、线宽 2，描边和无填充不变，实体抬亮）；日历是坐标系（同日历的散点淡化、grid 上的柱不动）；折线作为派发者（悬停线段：折线和面积 emphasis、符号不进、M 淡化）；高亮按**项自己的** focus 淡化、指不到元素时取第一个元素的；离开画布就是 mouseout；声明的标签 blur 不透明度；折线高亮的列表走组、downplay 的单元素列表走路径；以及下面变异补的两条。

### 变异测试

`b2_mut.py`：40 个变异，逐个改源码、重编、跑 focusblur、select、mouse-events 三套、还原。清除先于淡化、两种 scope 的匹配、无坐标系只配自己、grid 的身份、self 与 series 对自己系列、self 放过 hbo（不放过 / 谁都放过）、0.1 改 0.2、悬停 over/out 不看 hbo、折线不跟符号、blurSeries 不遍历折线、没有 blur 对象的标签不淡化（隐藏的饼标签）、隐藏的饼标签有 emphasis 对象、单点高亮落在组上、单元素列表不强转、真值 focus 当 none、未知 scope 当 coordinateSystem、下标不离开 blur、旭日没有默认 focus、ancestor 当 descendant、旭日的 0.2、标签 blur 不透明度不读、高亮按系列 focus、notBlur 不读、禁用系列的高亮也淡化、out 不 allLeaveBlur、over 不淡化、K 线没有边框 2、影线不跟随、图形不随列表、象形柱 scale 不读、标签不透明度不写、日历不算坐标系、折线容差回到 5 px、散点没有组、离开画布不 out、新类型没有选中边框。

首轮 39 个存活 1 个：**blurSeries 不遍历折线**——符号组的变化本来就会带上折线，有符号的线分不出来；补手写「不画符号的折线也被淡化」。另加「新类型没有选中边框」（fixture 不点选这些类型），配手写漏斗与热力图的选中边框。补完全部杀死。

### 推迟与偏差

- **桑基图**（adjacency/trajectory）**没做**：它的 focus 是 `{node: [...], edge: [...]}` 两套下标，边是另一份数据（`dataType: 'edge'`），状态模型目前只有节点一套行（B1 起就跳过 `IsEdge`）。要做：`TTyStSeries` 加一套按边下标的行、`StItemAt` 认 dataType、`TTyStFocus` 带两套下标、`StBlurSeries` 分别离开 blur，再给 fixture 加桑基的记录（`getData('edge')`）与转写。
- **关系图、树、矩形树图**保留各自的原地重样式（第 46、81 批），不接共享模型：关系图的 adjacency、树的 ancestor/descendant 已有逐项基准；搬过来要先给它们的节点/边建状态行（同上），而且它们的悬停由提示框的 datum 驱动、按帧重建，和标志模型是两条路。因此它们与共享模型之间**不互相淡化**（笛卡尔上的关系图连带柱子、global 范围跨类型），highlight/downplay 动作对它们只发事件、不改样子。
- **仪表盘、雷达**仍在覆盖层：仪表盘的指针和进度条是两个各自的派发者（`z2EmphasisLift = 0`），雷达的项是组（折线、面积、每个符号各有状态，标签按维度）；需要「一项多派发者」与「组的多路径」两种结构，Parts 只解决后者的一半。箱线图端口没有渲染器；极坐标上的柱/线端口没有。
- 面积在端口里是 silent（拿不到指针），所以「悬停面积只有面积 emphasis」的分支写了但到不了；悬停折线时面积跟着走与上游一致。
- 折线 `showSymbol: false` 时上游会为单点高亮临时建一个符号，端口不建（只设折线状态）。
- 漏斗常态隐藏标签时不建标签，上游默认的 emphasis 标签显示因此看不到（标签只在常态显示时才建，和 B1 的饼一样）；fixture 的漏斗用例标签常态显示。
- 象形柱的标签挂在透明条形框上，上游这个框没有状态对象，标签永远不进状态——端口同样不动它。
- 标注（markPoint/Line/Area）的 `toggleBlurSeries` 不做：被淡化系列的标注不变淡。
- 旭日图悬停原来走覆盖层，会把扇形外半径加 scaleSize 放大；上游旭日的 emphasis 没有半径变化，现在不放大了。

### 留给 B3 的接口

图例悬停就是一次普通的 highlight：B3 在图例项 over 时 `DispatchAction('{"type":"highlight","seriesName":…,"name":null,"excludeSeriesId":[…]}')`（数据图例写 `name`、`seriesName: null`），out 时同样的 downplay；点击的序列是 downplay → legendToggleSelect → highlight。allLeaveBlur、按第 0 项的 focus 淡化（`legend-hover-focus`）、`excludeSeriesId` 都已经在 `DoHighDownAction` 里；图例 `selectedMode: false` 时命中框 silent，什么都不派发。过滤掉的系列 `FBindings[].Hidden`，blurSeries 已跳过。

## 126. Tier 1 第九十一批：更新与离场动画（AN3，2026-10-01）

AN2 之后，第二次设 Option 仍被当成一次新的入场：每根柱子从零长出来，饼重新扫一圈。上游不是这样——同一个系列视图留着上一次的数据，拿新数据跟它做差分，留下的从原来的形状补间到新的，新来的入场，走掉的淡出。这一批把这套接上：柱、饼、散点的更新与离场，折线的 `lineAnimationDiff`，以及漏斗、仪表盘、雷达、K 线的更新（这几样没有 fixture 用例，见偏差）。状态动画（emphasis/blur/select 的过渡）留到 B1 合并之后的 AN3b。

### 上游的做法（`wf86/anim.md` 第 1、2.3、3A、3B、4b、6 节；源码逐行核过，关键点在真 dist 上探针确认）

- **控件的 Option 是 notMerge。** 上游 notMerge 的 setOption 重建所有模型，但系列视图按 `'_ec_' + model.id + '_' + type` 复用；模型 id 来自 `makeIdAndName`：写了 id 用 id，否则用 name（同名的第二个起后缀计数），都没有就是虚名 `'series\0' + 序号`。所以 id、名字或序号相同、类型相同的系列保留视图、拿旧数据做差分；其余系列的视图被移除，它的 group 立刻离开 zr 根节点，**没有淡出**（探针：两个柱系列变一个，第二个当帧消失）。坐标轴、图例这些组件在 notMerge 下是新视图，没有旧 group 可过渡，**`groupTransition` 根本不发生**（探针：同一组数据 merge 下 14 个 clip，notMerge 下 5 个，全是柱子）。fixture 里的 11 个更新用例是 merge 录的；新补充的 fixture 对每个用例按 notMerge 重录一遍，守卫系列元素逐条与 merge 版相同、组件一个都不动。
- **差分**（`data/DataDiffer.ts` 一对一模式）：键是 `getId`——数据项的 id；否则名字（项自己的 name，没有就取第一个类目维度的类目名），第二次起加 `__ec__N`；都没有是 `'e\0\0' + 原始下标`。旧行按顺序走：新数据里还有同键的取最前一个，记为更新，否则删除；剩下的新行按顺序记为新增。回调拿到的是视图下标，即 dataIndex。
- **柱**：更新 `updateProps(el, {shape: layout}, seriesModel, newIndex)`——更新时序，延迟函数拿**新**下标；旧行没有元素（原值不是数）时创建器把长度置零再 updateProps，以更新时序长出来；新增照入场；删除 `removeElementWithFadeOut`。
- **饼**：更新把整个 `sectorShape`（含 `angle`）补间过去，更新时序、新下标；后来新增的一片只扫 `endAngle`，从它自己的起始角出发，**用更新时序**；`animationType: 'scale'` 的新增仍是 r 从 r0 长出、入场时序。`animationTypeUpdate: 'expansion'` 从不保存数据，每次都是首次渲染。
- **散点**：路径的 `scaleX/Y` 以更新时序、新下标补间到 size/2；符号组的 x/y 以更新时序、**不带下标**补间（延迟函数拿到 undefined，`NaN || 0`）；样式（不透明度）直接设上；新增的是新 Symbol，照入场；删除 `fadeOut`：路径的 opacity 与 scale 一起到 0。
- **离场**：`removeElement` 的时序永远是 200 ms、`cubicOut`、延迟 0，不读模型；先摘掉标签和引导线，再淡出，done 时从父节点删掉。离场不停别的动画——入场长到一半就被删的柱子边长边淡。模型不动画时立刻设值、立刻删。K 线、箱线图、LineDraw 的线、雷达删除即刻消失。
- **折线**：符号先按新位置直接摆好（`disableAnimation`）；新旧 layout 点逐个相同（`isPointsSame`，长度不同即不同，`false` 对 `false` 算相同）就不碰折线；否则 `lineAnimationDiff`——`'='` 从旧 layout 点出发（旧点不是数就用新点），`'+'` 从**新数据在旧坐标系里的位置**出发（堆叠底同理：堆在下面的值，没有就旧值轴的起点），`'-'` 丢掉；按新的原始下标排序，写进 Float32Array；两边外包框四个角距离的最大值超过 3000 px 就直接设形状不补间；否则 `polyline.shape.points = current`、`stopAnimation`、`updateProps({points: next})`（更新时序、不带下标），多边形的 `stackedOnPoints` 同样补间、`points` 与折线共用一个数组；`'='` 的符号在折线第一个动画器的 during 里每帧跟到 `__points` 的对应点。裁剪矩形 `initProps` 到新矩形——**入场**时序、不带下标。新符号的标签是 LabelManager 的首次出现：入场时序淡入。
- **copyValue 怪癖**：setToFinal 时同长的类型化数组不抄，折线补间开始前点仍是旧值——同步的第一步马上写回 from，在这里看不出差别。

### 做法

- **上一次渲染的快照**（`TTyChartAnimPrev`）：设 Option 时先记下旧 Option 的系列视图键；新选项布局时（`Relayout` 里，`FAnimPending` 且还没有快照），记下旧绘制列表里所有打了动画标签的元素、旧系列的类型与每行差分键，并把旧的 `TTyChartBuild` **留着不释放**——`'+'` 要用旧坐标系的 `DataToPoint`。代理不再在这次布局里丢掉；布防之后快照和旧 build 一起释放。改尺寸、换主题这类不是新选项的重新布局照旧全部直接到终值。
- **`TTyChartAnimSet.ArmUpdate`**（`AnimView` 单元）：按视图键和类型配对新旧系列，`TyDataDiff` 做差分，把旧代理**带到新行号**上（`(系列, 行, 角色)` 重新建索引），按上面的规则对它 `TyUpdateProps`/`TyInitProps`；没有旧代理时就地从旧元素的标签值建一个。代理的「静止值」换成新布局。没认领的旧代理直接释放（即刻消失的那些）。
- **幽灵**：删除的柱、扇区、漏斗块、散点与折线符号变成幽灵——旧元素的记录加上它的代理，`TyFadeOutElement`/`TyRemoveElement` 让它淡出，done 时标记离开，`AnimTick` 在引擎栈外释放。帧在列表之后追加还在走的幽灵：静默（命中测试打不到）、没有标签（标签当即消失）、不透明度取代理的。
- **折线**：新代理 `linePoly`（`shape.points`，Float32）与 `lineArea`（`shape.stackedOnPoints`）。构建器给每段线和面挂上整条系列的 layout 点、堆叠底与每行数据值（`TTyChartAnim.Pts/Base/Vals`，第几段 `Sub`）。帧里用当前的点按上游的 `buildPath` 重建整条路径、切段、取本段。保留下来的符号代理加了 `x/y`，由折线代理的 during 每帧写入。
- **散点**：代理多了组的 `x/y`；**饼**：多了 `shape.angle`。
- 控件多了 `AnimFindGhost`、`AnimGhostCount`。无头渲染（`camAuto`）新选项时列表照布局画、不绑定旧代理，更新等窗口那次绘制。

### 基准

- `tools/advchart-oracle/animation-update.js`（复制 `animation.js` 的同一套钩子）→ `tests/fixtures/advchart-animation-update.json`：
  - `twins`：主 fixture 的 11 个更新用例，合并后的完整选项按 notMerge 设置，记下 clip 数；守卫：系列元素与 merge 版逐条相同，组件全不动；
  - `cases`：11 个新用例，全部 notMerge——类目平移加延迟函数（看新下标）、补间到 250 ms 时再来第三次选项（从当前值出发）、删掉一个系列（即刻消失）、具名系列换了位置（视图跟着名字走，原位置上的无名系列入场）、散点两种（移动、变大、离场、入场）、折线追加一个极远的点（超过 3000 px 直接设）、面积折线追加一点（点和它的底都从旧坐标出发）、null 补上值、线宽变粗（裁剪矩形以入场时序变大）、`scale` 饼的增删。
- `test.advchart.animupdate`（6 个测试）：真控件 400×300、SSR 量字、`camAlways`，第一个选项在 T0 渲染并跑完，第二个在 T1 = T0 + 10000 设置并渲染（这次渲染布防并走同步第一步），`AnimTick` 到每个采样。fixture 里每个动画元素映射到它的代理（离场的映射到幽灵，按旧行号找），逐采样比：在不在（幽灵到淡出结束为止）；每个被追踪的键**逐位比**，含终值，上游追踪的键代理必须有；代理其余的键不动；代理的动画器数等于它所代表的元素之和（散点的组和路径合用一个代理）；clip 数等于上游的减去 AN4 那部分（旧布局出发的标签位移、引导线点、数值滚动）；帧等于列表加活着的幽灵数；静止时没有幽灵、每个键要么是布局值要么正好是 `(to − from) × 1 + from`、静止在布局上的元素帧与列表逐位相同。22 个用例 1410 个代理采样全部对上。
- 手写：DataDiffer 的重复键、平移、全新；外包框差值（一边全非法是无穷大、两边都非法是 NaN）；幽灵在帧里、静默、没有字、不透明度为 cubicOut 的一半处、淡完即去；改尺寸结束更新；无头渲染下更新等窗口。
- AN2 的「新选项再动一次」改成更新：两根移动、一根淡出，3 个 clip、1 个幽灵。

### 变异测试

`an3/mutate.py`、`an3/mutate2.py`：逐个改源码、重编、跑三个动画测试（本批、AN2、AN1 引擎）、还原。第一轮 26 个：
- 本批测试杀死：柱的更新改入场时序、扇区的更新改入场时序、新增扇区改入场时序、新增柱改更新时序、柱的延迟用旧下标、散点组位置带下标、离场 300 ms、离场 linear、离场读模型的更新时长（这三个 AN1 引擎测试也红）、标签也当幽灵淡出、`'+'` 用新坐标、折线不按原始下标排序、不挂符号跟随、进行中的更新从布局值出发（不接代理）、幽灵不画、符号离场不缩放、旧标签照样淡入；
- AN1 引擎测试杀死：stopTracks 的「已 start 未步进先步回 0」、copyValue 同长类型化数组也抄——这两个在本批的路径上看不出来：同步的第一步紧跟着布防，写回 from 值，抄不抄、步不步回都被它盖住；
- 首轮存活 8 个：幽灵去掉标签（两处都清，互相掩护——删掉 Leave 里那一处，只留 ApplyGhost 的）；`'+'` 的堆叠底用新坐标（shift 用例里新旧坐标恰好重合）；外包框门槛（改成 3000000，那个极远点仍超过——改成去掉门槛）；目标数组不标 Float32（当前值那边已标，轨道按第一帧定类型——改成当前值不标）；裁剪矩形改更新时序（没有裁剪矩形会变的用例）；视图键不看（所有用例的系列都在原位）；`'='` 旧点不是数时取新点；sorted 数组不做单精度舍入。
补了 4 个上游用例（面积折线加点、null 补值、线宽变粗、具名系列换位）和对应的改法，第二轮 8 个里 6 个杀死。剩下两个是**等价变异**：`'='` 旧点为 NaN 时取新点——引擎的 fillArray 本来就把 NaN 帧换成终帧的值（上游 Track.prepare 也是），两层做同一件事；sorted 数组的单精度舍入——当前值以 Float32 存进代理，第一帧写回时已经舍入，之后只在插值的中间量上差不到一个单精度 ulp，所有用例都看不出来。

### 推迟与偏差

- **AN4**：标签从旧布局位移（`LabelManager` 的 oldLayout 过渡：饼标签的 x/y、引导线的点）、`valueAnimation`（`bar-label-update` 的文字）。测试从 clip 数里扣掉它们的动画器。
- **`groupTransition` 不做**：控件只有 notMerge，上游 notMerge 下坐标轴不过渡（见上）。将来若加 merge 式的 setOption，需要把坐标轴画进动态层、按 `anid` 建代理。（第 95 批：merge 式的 setOption 已有（§130），“控件只有 notMerge”这条理由不再成立；坐标轴仍没有代理，合并下轴直接到终值，仍未做。）
- **阶梯线**的更新直接到终值（上游补间阶梯化后的点、符号跟 `__points`，没移植）；`step` 改变时上游会整条重新入场，这里同样直接到终值。
- 漏斗的更新只补间不透明度，多边形的点不补间；仪表盘、雷达、K 线的更新按 3B 的规则做了，没有 fixture 用例。仪表盘「没有旧指针时从 startAngle 当 rotation」的怪癖没有覆盖。
- 端口不构建完全被裁掉的柱子，所以「旧的被裁掉、新的露出来」走的是「旧行无元素」那条路：从零长出，上游是从裁到边上的形状补间。
- 散点更新时样式里的不透明度直接设上；入场的不透明度若还在补间，上游换了 style 对象，旧补间落空，这里补间会接着写。
- `animationTypeUpdate: 'expansion'` 的饼每次重新扫开，旧扇区当即丢掉（上游不删旧扇区，未核实）。
- 删除的系列、类型变了的系列即刻消失——与上游 notMerge 一致。

### AN3b 要做的（B1 合并之后）

1. **stateTransition**：`updateStates`（`core/echarts.ts:2697-2747`）在每次渲染后给有 emphasis 状态的元素、它的标签和引导线设 `stateTransition = {duration, delay, easing}`（系列的 `stateAnimation`，默认 300 ms `cubicOut`），只在 `isAnimationEnabled()` 且元素不在离场时；`duration <= 0` 为 null；脏元素先不带动画恢复 `prevStates`。
2. **zrender 一侧**：`useState/useStates` 经 `canTransition`（非 `noAnimation`、不在 hover 层、`duration > 0`）对变换属性、`getAnimationStyleProps` 里的样式（opacity、fill、stroke、lineWidth、阴影……）和形状里的原始键做 `animateTo`，作用域 `__fromStateTransition`；对象值的键直接赋；没有过渡时正在跑的动画器 `__changeFinalValue`；离开 normal 时先 `saveTo`。这两样 AN1 没做，要先补进引擎并配引擎测试。
3. **端口的接线**：悬停与选中现在由 `PaintEmphasis` 读静态列表直接画——要改成状态代理：每个可高亮元素一个状态代理（或在现有代理上加状态键），emphasis/select/blur 的目标值从 B1 的状态样式里取，动画进行中元素进动态层，帧按代理当前值画；命中测试照旧跟帧。
4. **要覆盖的效果**：饼 emphasis 的 `r + scaleSize`、select 的 `x/y = cos/sin(mid) × selectedOffset`（标签与引导线一起移）；符号的 `hoverScale`（`max(1.1, 3/sizeY)` 等规则）；blur 的不透明度；柱的 emphasis 样式。
5. **基准**：在 `animation.js` 的套路上加 `dispatchAction({type: 'highlight'/'downplay'/'select'})` 的时间线用例（悬停走 `zr.handler`，或直接 `highlight` action），notMerge 下录；与本批一样按代理逐位比。
6. **交互**：动画中再次悬停/移开的打断（stopTracks 与 `__changeFinalValue`）、更新动画进行中进入 emphasis 的组合，各要一个用例。

## 127. Tier 1 第九十二批：标签、标注与持续动画（AN4，2026-10-01）

AN2、AN3 之后还有一圈动画没接：柱子标签的数值滚动、仪表盘读数、折线的末端标签、饼标签从旧位置挪到新位置、markLine 的划出与 markPoint 的弹出、effectScatter 的涟漪，以及坐标轴指示器的滑动。两批的测试一直从上游的 clip 数里减掉这些元素的动画器。这一批把它们都接上，减法删掉，三个 fixture 的 clip 数逐采样与上游完全相同。

### 上游的做法（`wf86/anim.md` 3A §A5、3B §B3/B11–B13；源码逐行核过，几处在真 dist 上探针确认）

- **LabelManager 的旧布局**：`_animateLabels` 对每个有 `oldLayout` 的文字先 `attr(oldLayout)`，再以更新时序、带 dataIndex `updateProps({x, y, rotation})`。挂在宿主上的标签（柱、符号）自身的 x/y 恒为 0，什么也不发生；真正会挪的是饼标签，它们由 `pieLabelLayout` 直接写 `label.x/y`。`oldLayout` 是**上一次布局的终值**，不是当前值：动画进行中再来一次 Option，标签先跳回上一次的终点再出发（新 fixture `pie-update.inflight` 确认）。引导线同理，`shape.points` 从旧点补间，**不带 dataIndex**。漏斗标签靠 `style.x/y` 定位，不走这条路。
- **数值滚动**：只有 BarView 和 GaugeView 调 `setLabelValueAnimation`，别的系列写了 `label.valueAnimation` 也照样淡入。`animateLabelValue` 在值没变（`prevValue === value`）时什么都不做（进行中的那条接着跑）；否则先置 `percent = 0`，以 `percent: 1` 为目标，没有旧值时 `initProps`（入场时序）、有旧值时 `updateProps`（更新时序），during 里用 `interpolateRawValues` 算当前值写字。起点是**进行中那条的插值**，否则是旧值；`source || 0`。数值的精度：写了 `precision` 用它，否则取 `max(getPrecision(起点), getPrecision(终点))`，再 `toFixed`，打印用 `Number#toString`（`-0` 打成 `0`）。文字：没有 formatter 是值本身；模板里 `{c}` 换成插值，其余照常。数值滚动的标签不淡入。
- **折线末端标签**：`endLabel` 是折线 polyline 的 textContent。裁剪矩形入场时，`_endLabelOnDuring` 是裁剪动画的 during：取裁剪矩形的前沿（横向基轴是 `x + width`，inverse 取另一侧），`getIndexRange` 在布局点里找跨过前沿的那一段——跨在空值上（`connectNulls` 关）停在空值前一点；找到就用 `polyline.getPointOn`（直线段线性、曲线段用 `cubicRootAt` 解三次方程）定位、值在两端之间按比例插值；没找到时取第一个点，**直到动画记录里有过一次有效区间**（或 percent 为 1）才取最后一个。创建时先 `during(1)` 设到终态，done 时回到第一次记下的位置。默认 `valueAnimation: true`、`distance: 8`，横向基轴左对齐垂直居中。**更新时裁剪矩形 initProps 不带 during**，末端标签直接站在终点。
- **标注**：markPoint 是 SymbolDraw 的新符号（缩放 0 → size/2、不透明度 0 → 自己的），markLine 是 `Line._createLine`（`shape.percent` 0 → 1，然后 `beforeUpdate` 每帧按 percent 放两端符号——缩放 = percent，终点 = `pointAt(percent)`——和标签：`d = normalize(终点 − 起点)`，percent 为 0 时 d 是零向量，`end` 位置的标签居中）。时序走标注自己的模型链（`markLine` 的 easing 默认 `linear`），**系列的 animationDuration 管不到它**；开关是 `MarkerModel.isAnimationEnabled` = 标注的 `animation` 且宿主系列 `isAnimationEnabled()`。markArea 默认 `animation: false`。探针确认：**notMerge 下标注是新视图**，每次设 Option 都重新入场；markArea 的更新补间在 notMerge 下根本到不了。
- **effectScatter**：构造时 `updateData` 一次（缩放与样式不透明度从 0 入场），紧接着 `EffectSymbol.updateData` 又调一次：缩放以**更新时序**重新补间（第一次的轨道尚未步进就被 stopTracks 步回 0），而 `_updateCommon` 换了 style 对象——不透明度那条补间还在跑、动画器还在数，却不再影响画面。涟漪是原始 `animate('', true)`：`when(period, scale/2)` 与 `animateStyle(true).when(period, {opacity: 0})`，延迟 `-i/n·period + idx/count`（负延迟从周期中途开始，小数延迟在 epoch 量级上舍入），循环重启保留相位；**不受系列 animation 开关约束**。只在 `DIFFICULT_PROPS`（符号类型、周期、缩放、个数）变了才重启，更新时接着跑；删除即刻消失。帧间隔超过一个周期时，跨过的那一帧写出终值再按余数续上（探针：更新用例 t = 0 的涟漪都是 1.25 / 0）。
- **坐标轴指示器**：`BaseAxisPointer.render` 首次显示直接到位；之后 props 与上次不同（propsEqual）时，`determineAnimation` 为真就 `updateProps`（指示器模型链：轴自己的 axisPointer → tooltip.axisPointer，默认 `animation: 'auto'`、200 ms、`exponentialOut`），否则停掉直接设值。`'auto'`：类目轴 bandWidth > 15，或 snap 时 `|extent| / 该坐标系所有系列的数据量` > 15；值轴在 tooltip 触发下默认 snap。根上的 `animation: false` 挡不住它（tooltip 的 `'auto'` 先到）。隐藏只是 hide，下次显示从原处滑过去。clip 在下一个 rAF 才第一次步进。
- **dataZoom / 漫游的载荷动画**：inside 缩放与 realtime 的 slider 派发 `{cubicOut, 100}` 的更新载荷，系列与坐标轴（`groupTransition`）一起补间 100 ms。

### 做法

- **代理加三样**（`AnimView`）：计数（`FVal*`、`ValueDuring`、当前文字 `Text`）；末端标签记录（`TTyChartAnimEndLabel`，挂在裁剪代理上，`EndLabelDuring` / `EndLabelDone` 照抄 `_endLabelOnDuring` 与动画记录）；`MergeFinal` 让一个代理在入场之后再加键。新角色：`gaugeDetail`、`effectSymbol`、`ripple0..n`（键带序号，`TyChartAnimRoleKey`）、`markPoint`、`markLine`（线、两端符号、标签共用一个代理，`shape.percent`）、末端标签读裁剪代理。`TyAnimInterpolateValue` 是 `interpolateRawValues` 的数值分支。
- **构建器打标签**：`TTyElementCaption` 多了 `ValAnim/ValHas/ValNum/ValTpl/ValHasPrec/ValPrec`，文字模板里用 `#1` 占住值的位置（`TyLabelValueTemplate`：`TyLabelText` 加了「值的文字」覆盖参数，formatTpl 的 `{c}` 就落在那里；handler formatter 不滚动）；柱的 `ItemCaption` 记值，`label.valueAnimation/precision` 读进 `TTyLabelSpec`；仪表盘读数（`TyGaugeFormatTpl`）同理。markLine 的四个元素带端点、距离、位置码、dy、切线方向；`TyMkLineAt` 是 `Line.beforeUpdate` 对直线在任意 percent 的那一段（终点、标签位置、对齐）。effectScatter 的涟漪带中心、序号、个数、周期（ms）、缩放、`idx/count`、符号类型，`rippleEffect.period/scale` 读进视觉（含数据项覆盖）。
- **末端标签**是新元素（端口以前没有画 `endLabel`）：控件在折线的标记之后建它——最后一个合法点、`during(1)` 的位置与文字（`LinePath` 新增 `TyPathPointOn`、`TyEndLabelStep`、`TyLastLegalRow`，traps 屏蔽），z2 200，主题字体，墨色按系列色作外侧标签；datum 为空，免得标签展开把它当宿主再展开一次。
- **ArmUpdate**：保留下来的饼标签按旧布局位移；引导线按旧点补间；柱标签、仪表盘读数按上面的规则计数（进行中的接着插值，值没变不动）；标注一律重新入场；effectScatter 的符号按散点规则更新，涟漪按 DIFFICULT_PROPS 决定接着跑还是重启；裁剪代理的末端标签记录在更新时停用。
- **持续动画与分层**：涟漪不停，图表一直 `AnimLive`。只剩循环 clip 时（`AnimLoopOnly`）进入 `AnimContinuous`：静态层重画一次、画除涟漪与 effectScatter 符号（及挂在它们上的标签）之外的一切，动态层每帧只画这三样（`AnimPart`）；入场或更新还在跑时仍按 AN2 的方式整体进动态层。
- **指示器**：独立的 `FPtrAnim` 驱动，按轴（`xAxis0`）一个代理，键是上游指示器的形状（line 的 `x1/y1/x2/y2`，shadow 的 `x/y/width/height`）；`MouseMove` 解析出命中后 `PtrAnimSync`，`PaintAxisPointers` 画在代理当前的位置，标签跟着线走。指示器动画不碰系列分层，定时器在任一驱动有 clip 时开。`camOff` 不建代理（直接跳）。
- **顺带修的**：饼标签的 `cos/sin/atan2` 改用 V8 的（`TyJsCos/TyJsSin/TyJsAtan2`）——标签要从旧位置逐位补间，FPC 的 libm 差一个 ulp 就对不上；`label.valueAnimation` 以前对所有系列都关掉淡入，现在只对柱生效；effectScatter 的标签加入 LabelManager 淡入。

### 帧代价（持续动画）

涟漪是端口第一个不会停的动画。只剩涟漪时，每 16 ms 一帧的代价是：静态层一次 blit，加动态层那张控件大小的 BGRA 位图的分配、填充、合成（Q7 量过的约 13 ms 底价），加涟漪与符号本身。临时探针（800×600、默认主题、`RenderCached` 连画 60 帧，未入库）：静态柱图约 0 ms/帧（只有 blit）；柱图入场约 10.9 ms；十个点的 effectScatter 加一条折线入场约 17.7 ms；入场结束、只剩 60 个涟漪 clip 时约 13.5 ms——分层省下的是系列本身，省不掉的是那张位图。也就是说，一个带 effectScatter 的图表在窗口里会持续占用接近一个核的 UI 线程时间——和上游在浏览器里 rAF 常驻一样，但没有 GPU 合成。分层把每帧要画的系列元素减到涟漪那几个，底价却省不掉。要静止的场合设 `AnimationMode := camOff`，或 `showEffectOn: 'emphasis'`（端口目前不在 emphasis 时启动涟漪，见偏差，等于没有涟漪）。无头渲染（`camAuto` 的 `RenderTo`、导出、设计器）从不布防，不受影响。

### 基准

- `tools/advchart-oracle/animation-an4.js`（复制 `animation-update.js` 的钩子）→ `tests/fixtures/advchart-animation-an4.json`：12 个入场用例（计数：auto 精度、固定精度、模板；仪表盘模板；末端标签：平滑线、空值、不滚动带 formatter、竖向基轴；markLine 的 start / insideEndTop / 两点线与小号 markPoint；标注关闭——markLine 自己关、宿主关；涟漪换周期/缩放/个数/描边；`showEffectOn: 'emphasis'`），5 个更新用例（计数两次打断、仪表盘倒数、饼打断、effectScatter 移动、末端标签折线更新），9 个指示器用例（line、shadow、中途换目标、tooltip 的时长缓动、轴自己的 axisPointer 压过 tooltip 的、`animation: false`、40 个类目带宽 7.5、值轴 snap、根 `animation: false`）。指示器组被加在 zr 根上而不在组件视图里，脚本按「不是任何视图的根」单独记录；派发后不 flush，采样 0 不跑帧（setToFinal 的终值），之后每个采样一帧。7 条守卫，两次生成逐字节一致。
- `test.advchart.animenter`：删掉延期减法，原 fixture 的 57 个入场/阈值用例加上 effectScatter，新 fixture 的 12 个入场用例另起一个测试；计数的文字逐字符串比较；markLine 两端符号、标签与末端标签这些「每帧由别的补间推导」的值，按端口从同一代理推导的结果逐位比较，并检查帧里画出来的位置与推导一致。涟漪的「终值」不比（它从不静止），逐采样逐位比。
- `test.advchart.animupdate`：删掉延期减法；第一次 Option 的收尾改成照 oracle 每 250 ms 一帧（循环 clip 的重启时刻决定相位，逐位比较要求帧时刻一致）；新 fixture 的 5 个更新用例另起一个测试；打断后的终值是 `(to − from) × 1 + from`，from 是布局不知道的中途值，静止检查对布局值放宽到 4e−16 的相对差（逐采样仍逐位）。
- 新单元 `test.advchart.animlabels`（10 个测试）：9 个指示器用例经真控件的 `MouseMove`，每采样逐位比较指示器的移动键、动画器数与指示器 clip 数；手写：精度规则、`TyEndLabelStep` 的各种取舍、帧里的末端标签、值不变不计数、涟漪多周期后相位不变（含跨长间隔那一帧写终值）、只剩循环时分层、散点标签照样淡入、隐藏后再显示从原处滑、`camOff` 直接跳。

### 变异测试

`an4/mutate.py`：37 个变异，逐个改源码、重编、依次跑本批、AN2、AN3 的测试、还原。
- 精度规则（4）：`max` 改 `min`、写了的 precision 不读、只看终点的精度、不取整——全部被手写的精度测试杀死，也都让 fixture 的文字对不上。
- 计数（3）：进行中的从旧值而不是插值出发（`bar-label-update.inflight` 杀死）、值没变也重新计数、有旧值也用入场时序。
- 末端标签（5）：动画记录的「找到过区间」规则去掉、前沿取 `x` 而不是 `x + width`、不加 distance、不插值、跨空值也插值。
- 标注（8）：markLine 用系列的模型（时序与缓动不同）、终点符号不缩放、不移到 `pointAt(percent)`、标签停在终点、零向量不当零、markPoint 不从 0 缩放、不淡入、门槛不看宿主。终点符号与标签这几条只改帧、不改代理，只有「帧里画的与推导一致」那道检查看得见。
- 涟漪（6）：不加 `idx/count`、不加 `-i/n·period`、不循环、循环重启不保留相位（引擎里的那一行）、更新时总是重启、effectScatter 符号缩放用入场时序。
- 标签旧布局（5）：从新布局出发、不带 dataIndex、打断时从当前值而不是上一次终点出发、引导线从新点出发、引导线带 dataIndex。
- 指示器（6）：200 改 300、`exponentialOut` 改 `cubicOut`、带宽门槛 15 改 75、snap 不看、首次显示也滑、轴自己的 axisPointer 不读。

首轮 36 个杀死，存活 1 个：「轴自己的 axisPointer 不读」——fixture 只有写在 tooltip.axisPointer 上的时长。oracle 补了 `axisPointer.axisOwn`（xAxis.axisPointer 600 / linear 压过 tooltip 的 300 / cubicOut，真 dist 上轴的赢），重生成后其余用例逐字节不变，重跑杀死。

### 推迟与偏差

- **dataZoom / 漫游的载荷动画不做**：上游这时是同一个 Option 的 merge 式更新，坐标轴走 `groupTransition`，系列与轴一起补间 100 ms。端口只有 notMerge 的更新路径，也没有坐标轴代理（AN3 已推迟）；只让系列补间、轴跳到终值会让柱子与刻度错位，比不动更糟。等做 merge 式更新与 `groupTransition` 时一起做。上游 fixture 未录。（第 95 批：merge 式更新已有（§130），`groupTransition` 仍未做，这一条仍推迟。）
- **指示器标签**：上游对标签的 x/y 单独以同一时序补间；端口的标签框按皮肤排版，跟着线走，不与上游逐位比较。轴上 `axisPointer` 组件根的动画键（全局 `axisPointer` 选项）不读；悬停高亮的 stateTransition（AN3b）不在这批。
- **末端标签**：状态里的 `endLabel.show`、富文本末端标签（画成一段）、阶梯线（沿未阶梯化的路径走）、只有一个点的折线（没有 run，不画）不支持；值是数组的数据项不滚动（文字停在终值）。浏览器里路径数据画过一次后会转成 Float32Array，平滑线的 `getPointOn` 在浏览器里读的是单精度控制点；oracle（不绘制）与端口都是双精度。
- **计数**：handler formatter、富文本标签、数组原始值不滚动；静止时画的是静态列表的文字（`12.50` 这样的原样文本），上游 during(1) 之后是 `12.5`。
- **markLine** 只按直线做（端口没有 curveness）；percent 为 0 时 `end/start` 标签按零向量居中，对齐用 `TyAnchorBox` 重排，旋转的标签不重排框。markArea 在 notMerge 下从不动画（与上游一致）。
- **effectScatter**：`showEffectOn: 'emphasis'` 的涟漪不启动（上游悬停时启动、离开时清掉）；涟漪与 effectScatter 符号在持续阶段画在动态层，压在其它系列之上（z 序偏差）；涟漪不受 `animation: false` 约束（上游如此），但受 `AnimationMode` 约束。
- 饼标签以外的独立标签（漏斗）更新时不位移（上游靠 `style.x/y` 补间，没有 fixture）。

## 128. Tier 1 第九十三批：图例点击与联动（B3，2026-10-01）

B1、B2 之后，图例仍然只是一张画：`legend.selected` 与 single 模式在加载时读一次，点击、悬停、五个图例动作都没有，`inactiveColor` 这类作者颜色也不读。这一批把上游 LegendModel 的选择、legendAction 的五个动作、LegendView 的点击与悬停联动接上，并让图例动作后的整体更新按上游的顺序重放状态。

### 上游的做法（`wf87/states.md` §0.2、§4、§6；`LegendModel.ts`、`legendAction.ts`、`LegendView.ts`、`core/echarts.ts` 逐行核过，关键处在真 dist 上探针确认）

- **模型把状态放在自己的 option 里**：`init` 时 `option.selected ||= {}`；`optionUpdated`（只在 setOption 时）single 模式选第一个已选中的、否则第一个，其余写 false。`select`：single 模式先把图例数据的每个名字（换行项也算）写 false；`unSelect`：single 模式什么都不做；`toggleSelected`：没有这个键先当 true；`allSelect` 全写 true；`inverseSelect` 没有的键先当 true 再取反。`isSelected` = 映射里没写成假值，且名字在 availableNames 里。
- **动作**（`legendAction.ts:28-92`）：对 payload 查询到的图例（legendIndex——数组按给的顺序——、legendId、legendName，都没写就是全部）调方法，并把这些图例的选中表 AND 成一张 map（跳过 `''` 和 `'\n'`）；然后**每一个**图例对 map 里的每个名字（JS 键序）调 select / unSelect——于是 `selected` 里会出现所有名字，single 模式被重新强制，一个图例的表里出现另一个图例才有的名字；最后事件里的 `selected` 是**写回之后**所有图例的表（AND），不是动作那张——single 模式下 legendAllSelect 的事件是 `{A:false, B:true}`。事件：toggle/select/unselect 是 `{name, selected, type}`（payload 没有 name 时没有这个字段，键是 `'undefined'`），allSelect/inverse 是 `{selected, legendIndex, type}`。默认 `update` 是整体更新，在事件之前同步跑完。
- **整体更新**（`echarts.ts:2429-2539、2667-2748`）：被过滤的系列视图 `chart.remove`，元素没了；重新显示是新元素（标志全零）。复用的元素先 clearStates（记下旧列表），渲染，再 `useStates(旧列表)`、再按标志 applyElementStates——z2 继续爬。饼按名字 filterSelf，内部下标移位，选中按名字保留。
- **视图**（`LegendView.ts:193-506、709-724`）：图例项按名字找系列（`getSeriesByName`，被过滤的也算）是系列图例，否则是数据图例（饼、漏斗按名字）；项组上的处理器：over → `highlight {seriesName|null, name|null, excludeSeriesId}`，out → 同样的 downplay，click → downplay、legendToggleSelect、highlight。项的处理器在 zr 级处理器（选中的派发、用户 click）**之前**。所有子元素 silent，透明命中框 `silent = !selectedMode`：**selectedMode false 时什么都打不到**——没有悬停联动、没有点击、triggerEvent 的鼠标事件也没有。`excludeSeriesId` 是 legendHoverLink 为假值的系列 id：选项写了用选项，否则用类型默认——柱、折线、散点、饼、漏斗等是 true，**热力图、旭日、矩形树图、树图、桑基图没有默认值，所以总被排除**。
- **zrender 的 #6198**：上一个悬停目标被重渲染删掉了（图例项每次整体更新都重建），下一次 mousemove 先在它被找到的那个点重新找一遍，找到的若就是新指针下的元素，既不 out 也不 over；复用的元素（柱子）不重找，指针下换了元素就照常 out 旧的、over 新的。
- **样子**（`getLegendStyle :599-681`）：文字 = 选中 ? textStyle.color : inactiveColor；图标填充 = 系列色或 inactiveColor；描边 = 系列视觉的描边（`itemStyle.borderColor`）或 inactiveBorderColor；线宽 `borderWidth 'auto'` = 系列视觉线宽 > 0 ? 2 : 0；未选中且 `inactiveBorderWidth 'auto'` = 视觉线宽 > 0 **且有描边** ? 2 : 0，写成数字**不用**，保留选中时的宽度。饼的默认 borderWidth 是 1（没有颜色），漏斗是 1 加 neutral00 的白边。有描边的图标包围盒外扩半个线宽。

### 做法

- **`Legend` 单元**：`TyLegendSelectedNode / IsSelected / SelectName / UnSelectName / ToggleName / AllSelect / InverseSelect / ResolveSingle` 直接在选项树里图例节点的 `selected` 对象上读写（控件的 Option 文本仍是宿主写的；同一文本再设不算新选项，不同文本 notMerge 重来。第 95 批起：合并之后 Option 是合并后的选项，合并保留 `selected`，`SetOption(text, True)` 无论文本是否相同都重来，见 §130）；`TyJsKeyOrder` 给出 JS 键序（整数样的键升序在前），`TyLegendSelectedJson` 按它输出。Spec 多了 `InactiveBorderAuto`，Source 多了系列的描边与视觉线宽，Item 多了解析后的图标笔（`HasStroke/Stroke/IconPen`），Ink 多了 `InactiveBorder`、规则线的 `LineInactive/LineInactiveWidth`。命中框在 selectedMode false 时 silent。
- **控件**：`SolveLegendData` 每个选项只做一次加载（`FLegendLoaded`：建 `selected`、single 模式选一个写进表），之后标志一律按表读（不再每次 Rebuild 重新挑 single）。`DoLegendAction` 照 legendAction 的三步；`FullUpdate` 在动作里**同步**整体更新：Relayout（`FStGen` 前进，StSync 走「回 rest、套旧列表、再套标志」）、建显示列表，并按上游重找悬停目标——数据项按（系列、原始下标）认回复用的元素，其余（图例项总是）在最后一个点重找、不发 out/over。没画出来的系列（包括全部被关掉、列表里一个系列都没有时）状态记录清空，重新显示就是新元素。
- **事件目标**：`TTyChartEventTarget` 的 `HdKind 4` 是图例项（`HdName`、`HdLegendSeries`），不管 triggerEvent 都有；mouseover / mouseout 派发 highlight / downplay，click 在选中派发和用户 click 之前跑 downplay → legendToggleSelect → highlight。`LegendExcludeIds` 按类型默认表算 legendHoverLink。`DispatchAction` 收五个图例动作；事件类型表加了 legendselectchanged 等五个。
- **样子**：`LegendTextOf` 读 `inactiveColor`、`inactiveBorderColor`、`lineStyle.inactiveColor / inactiveWidth`（主题的 inactive 墨是默认值）；`LegendBorderOf` 从系列（数据图例再叠数据项）的 `itemStyle.borderColor / borderWidth` 和饼、漏斗的默认值得出图标的描边。
- **顺带修的**：
  - `DispatchAction` 解析 payload 前把 `\u0000` 换成 U+FDD0、解析后换回 #0——fpjson 会把它吞掉，上游自动生成的系列 id 是 `'\0' + 名 + '\0' + n`，图例悬停的 excludeSeriesId 因此一个都对不上（热力图那条手写测试先红了）。
  - **柱的边框从布局里扣掉**（`BarView.ts:924-944, 1078-1092`）：有 borderColor 时取 min(borderWidth, |宽|, |高|)，两边各扣一半，在裁剪之前——夹具 `legend-inactive-custom` 的带边框柱子差半个像素，暴露了它。`TTySeriesVisual.PxScale` 把逻辑线宽换成设备 px。
  - `test.advchart.mouseevents` 不再滤掉图例悬停的 highlight / downplay，`legend-trigger` 跑到最后一步，`pub` 也注册图例的五个事件类型：全部对上。

### 基准

- `tools/advchart-oracle/select-legend.js` 加了 8 个用例：`legend-single-actions`（single 模式下 allSelect 只留最后一个、inverse、unSelect 不动、select 切换、toggle 已选中的不动、select 一个没有的名字后**什么都不显示**——single 只在加载时解决）、`legend-mode-false-action`（selectedMode false 时动作照样过滤和发事件，指针什么都不做）、`legend-held-hover`（悬停柱子时做图例动作：复用、z2 重放、不重找、移开才 out）、`legend-held-hover-moves`（复用的悬停柱子缩走，同一个点上 out 旧的 over 新的）、`legend-pie-inverse`（选中且悬停的扇区被反选过滤、全选后作为新元素回来、按模型选中）、`legend-pie-border`（饼的边框色加默认宽 1：图标笔 2，未选中的 inactiveBorderColor；饼 legendHoverLink false）、`legend-inverse-fresh`（空表反选：没写的当 true，全部关掉）、`legend-reshown-new`（变异补的，见下）。转写修了一处：事件的 `selected` 要在写回之后算（single + allSelect 时转写原先与上游不一致），新增守卫 G-legend-write-back。整份 fixture 53 个用例、276 步、279 个事件，转写全对，35 条守卫全过，两次生成逐字节一致。
- 重放器（`test.advchart.select` 的 `TAdvChartSelectHarness`）补了：`shown: false` 的系列不能画出任何元素、不能有状态记录（选中下标不比，上游只问显示中的系列）；`legend` 的 `selected`（键序也比）与每一项画出来的字色、图标填充、笔（颜色与宽度，上游没有笔时这里也不能有）、不透明度——两个默认色映射到皮肤（`#54555a` 是皮肤的图例字色，`#cfd2d7` 是皮肤的 inactive 墨），选中项的填充是端口自己的系列色，其余逐位比；整体更新后重新取 rest 画面（饼的引导线 rest 随重新布局变了）。
- `test.advchart.legendact`：重放 18 个图例用例共 86 步，全部对上；手写 7 个，期望值取自真 dist 的临时探针：两个图例被强制成同样的状态（legendIndex 数组按序、legendId、legendName、没有 name 的 toggle）、查询到的图例的表 AND、JS 键序（`x、10、2` → `{"2","10","x"}`）、热力图被 legendHoverLink 排除（payload 里的 NUL 原样、排除确实生效）、漏斗图标的白边（端口是图表底色）、selectedMode false 连 triggerEvent 的鼠标事件也没有、Option 文本不变而新文本重新加载。

### 变异测试

`b3/mut.py`：逐个改源码、重编、跑 legendact、mouseevents、legend、select、focusblur 五套、还原。50 个变异：
- 点击：先 toggle 后 downplay、highlight 在 toggle 之前、没有 downplay、图例的处理器排在用户 click 之后；
- 模型：single 的 select 不清别的、single 的 unSelect 照写、加载时不解决 single、每次更新都重新解决 single、toggle 时没写的键当 false、inverse 时没写的键当 false、allSelect 什么都不做、没有写回、查询到的图例的表不 AND、忽略查询、键按插入序；
- 事件：用写回之前的表（两处）、没有 legendIndex、没有 name、事件在更新之前、legendselected 认错动作；
- 更新：推迟到下一次绘制、整体更新不重放旧列表、重新显示的系列沿用旧元素、复用的项也在点上重找、被删的项不重找、什么都没画时状态记录留着；
- 过滤与联动：扇区不按名字过滤、饼按系列名过滤、数据图例按系列派发、系列名永远找不到、系列图例当数据图例、selectedMode false 仍然命中、所有类型都联动、选项的 legendHoverLink 不读、id 里的 NUL 丢掉；
- 样子：inactiveColor / inactiveBorderColor 不读、未选中的图标和文字不换色、未选中的笔用系列描边、inactiveBorderWidth 永不 auto、auto 不看描边、选中笔宽 1、饼默认线宽 0、漏斗没有默认边、系列边框不读、柱不扣边框、柱的边框两边各扣一整份。

首轮 48 个存活 1 个：**重新显示的系列沿用旧元素**——已有用例里被关掉的系列关掉前标志都已清零，新旧元素看不出区别。补上游用例 `legend-reshown-new`（悬停 B1、动作高亮 B2 之后关掉再打开：上游是新元素，没有 hoverState、没有 hbo），杀死；第二轮同时加了两个过滤的变异（扇区不按名字过滤、饼按系列名过滤），都被杀死。补完全部杀死。

### 推迟与偏差

- **图例切换不动画**：整体更新走 Relayout 的「直接到终值」分支并停掉进行中的动画。上游此时被关掉的柱子淡出（`BarView._clear` 的 removeElementWithFadeOut）、重新显示的系列作为新视图入场、留下的补间——要接 AN3 的更新布防，并区分「视图被 remove」与 notMerge 的删除，留给 AN 系列。
- **selector 按钮（全选/反选）和滚动图例（`type: 'scroll'`）的翻页**没做；对应的动作（legendAllSelect / legendInverseSelect）已经在。
- 图例项级的 `inactiveColor` 等（`legend.data[i]` 对象里写的）不读，只读图例级；图例项的 `textStyle` 同样只读图例级（第 83 批起就是）。
- 图标描边只认作者写的 `itemStyle.borderColor / borderWidth` 与饼、漏斗的默认值；K 线等类型自带的默认边框（上游 K 线图例图标会有 2 宽的边）没有建模；折线自绘图标的规则线未选中时用 `lineStyle.inactiveColor / inactiveWidth`，标记点仍是 inactive 墨。
- 漏斗图标的默认边是图表底色而不是上游写死的 `#fff`（主题令牌原则）。
- `legend.selected` 不是对象时（比如写成 `true`）直接换成 `{}`；上游在严格模式下对原始值写属性会抛异常。
- 悬停目标的复用只认数据项（按系列和原始下标）与折线本体；悬停在数据项的标签上时，整体更新后认回的是宿主元素，下一次移动在标签上会多一对 out/over（没有用例）。

## 130. Tier 1 第九十五批：option 合并（A10，2026-10-01）

控件的 `Option` 一直是 notMerge：每次赋值都换一套全新的模型。上游最常用的却是不带 notMerge 的 setOption——拿新选项去合并已有的模型：按 id、名字、序号找到对应的组件和系列，深合并进去，模型身上的状态（图例的选中、roam 的中心和缩放、dataZoom 的窗口、系列的选中）都留着。这一批把这条路接上：`MergeOption`、带 notMerge 开关的 `SetOption`、`GetOptionJson`，以及模型的 id / 名字 / 子类型；并把 §79 留下的“完全相同的文本”的语义理顺。replaceMerge、replaceAll 和序号空洞留给 A11。

### 上游的做法（`wf-a10/merge.md`；`Global.ts` `_mergeOption`、`util/model.ts` `mappingToExists` / `makeIdAndName`、zrender `merge`、`layout.ts` `mergeLayoutParam` 逐行核过，关键处在真 dist 上探针确认）

- **根上不是组件的键**（color、backgroundColor、textStyle、animation*……）：新值为 null 时忽略（根上的 null 删不掉任何东西）；旧值为空时克隆；否则对**根上的值本身**调 zrender 的 `merge`——数组在 `isObject` 眼里也是对象，所以根上的数组**按下标合并**：`color: ['#a','#b','#c']` 再合并 `color: ['#x']` 得 `['#x','#b','#c']`。
- **哪些主类型被访问**：写了（非 null）的组件主类型，加上依赖它们的主类型（`topologicalTravel` 的 `removeEdgeAndAdd`；依赖表从 dist 的各类 `dependencies` 取）。**但预处理器每次都往选项里写东西**（探针：只合并 title 也会跑系列的 mergeOption 和图例的 optionUpdated）：backwardCompat 写 `series`（至少 `[]`），axisPointer 预处理写 `axisPointer: {}`，有 xAxis 和 yAxis 却没有 grid 时写 `grid: {}`。于是**每一次** setOption 都访问系列和所有依赖系列的主类型：每个系列重建数据（树图的展开状态因此丢失），每个图例重新解决 single 模式。grid 和 axisPointer 的那个 `{}` 是谁都没写的模型（getOption 里有），之后写 grid 的选项是合并进它。
- **映射**（`mappingToExists`）：主类型第一次出现时是 replaceAll（按下标一一对应，空洞保留）——但 series 的列表在 initBase 时就有了，所以系列永远是 normalMerge；其余都是 normalMerge：
  1. 结果先按已有的下标排好（空洞也占一个位置），已有组件的下标**永远不动**；
  2. 按 id：新选项的 id（字符串原样，数字按 JS 转成字符串）等于某个已有模型的 id 就落在那里；两个新选项落在同一个 id 上上游直接断言抛错；
  3. 按名字：**只有没写 id 的**新选项按名字找第一个还没被认领、同名的模型（模型的名字是写过的名字，否则上一次的名字，否则 `'series\0' + 下标`——非系列组件也一样）；
  4. 按序号：剩下的每个新选项从 0 开始找第一个没被认领的位置（空洞也算），但带 id 的选项跳过 id 不同的已有模型（“id 只能落进空洞或追加”）；找不到就追加；
  5. `makeIdAndName`：名字是选项的名字、否则已有模型的名字、否则 `'series\0' + 结果下标`；id 是已有模型的 id（**永远不变**）、否则写的 id、否则 `'\0' + 名字 + '\0' + n`，n 取第一个没被任何已有 id、本次写的 id、本次已生成的 id 占用的数。
- **合并**：子类型取新选项的 `type`（真值时），否则已有模型的子类型，否则主类型的默认器（轴 `data ? 'category' : 'value'`，dataZoom `'slider'`，legend `'plain'`，visualMap 按 categories/pieces/splitNumber/calculable）。类相同（系列按 type，轴、dataZoom、legend、visualMap、timeline 按子类型，其余只有一个类）就 `merge(this.option, newOption, true)`：两边都是普通对象才递归，其余——数组、null——原样写进去（**数组整体替换，null 是一个值，键不删除**），新键追加在后面。类不同（bar 换成 line、value 轴换成 category、plain 图例换成 scroll）就**只用新选项**建新模型，旧选项整个丢掉，但 id 沿用这个位置的。
- **模型自己的合并规则**：
  - `mergeLayoutParam`（`box` 布局的组件）：每个方向 `[width, left, right]` / `[height, top, bottom]`，目标是**带默认值的完整选项**。ignoreSize（title、legend、visualMap、toolbox）：新写了有值的 left 就把 right 置 null，反之亦然；其余按计数：合并后正好两个有值或新选项一个都没写，照合并结果；新写了两个以上，只要新的；新写了一个，再按顺序从目标里补第一个**拥有**的键（init 之后三个键都被 `copy` 写成了自有键，值可能是 undefined）。三个键随后全部写回。所以 `grid: {left: 50, width: 300}` 再合并 `{right: 20}` 得 width 300、right 20、left 没了。
  - **系列的盒子跟自己合并**：`SeriesModel.mergeOption` 把 `merge()` 的返回值——也就是 `this.option`——当作新选项交给 `mergeLayoutParam`，每个键都算“新写的”，什么也不丢，盒子就是深合并的结果（探针：树图 left 10%、width 50% 再合并 right 30%，三个都在）。
  - dataZoom：`_doInit` 按每一对（start/startValue、end/endValue）重新定模式——只写了百分比是 percent，只写了值是 value，都写或都没写看 `rangeMode`，再没有就看写没写百分比，否则沿用；value 模式的那一对把百分比置 null。动作（`setRawRange`）把窗口写进 option，所以没写这一对的合并都保留缩放。
  - dataset 的 `transform` 被标成 primitive：整体替换，不合并。
  - legend 的 `selected` 在 option 里（init 时 `||= {}`），像别的对象一样深合并：`selected: {C: false}` 只改 C，别的保留。
- **getOption 返回什么**：模型 option 的克隆，组件主类型一律数组、空洞为 null、末尾的空洞去掉。它是**模型的** option：主题和默认值都合并进去了，模型写的东西（legend 的 `selected`、dataZoom 计算出的窗口、`emphasis.label.show`）都在，访问过但谁都没写的主类型是 `[]`；**没有 id**，id 只在模型上（`getModel().getComponent(t, i).id`）。
- **完全相同的选项**：上游没有“同一段文本”的概念。`setOption(o, true)` 即使 o 不变也是全新的模型——roam、缩放窗口、图例和系列的选中全部重来；`setOption(o)` 把每个键合并到自己身上，写过的都不变，模型的状态全留着（被点掉的图例项仍然关着，除非 o 写了 `selected`），single 模式重新解决一次。

### 做法

- **新单元 `OptionMerge`**（纯 fpjson）：
  - `TTyOptionKeys`：按主类型存上游组件列表的每个位置——有没有模型、id、名字、子类型。**身份放在树旁边**：一个改了名的系列是哪个，树自己说不出来，下一次合并按 id 和名字找人全靠它。一个主类型被访问过就有列表（哪怕是空的），下一次写它就是 normalMerge 而不是 replaceAll。
  - `TyOptionKeysOfTree`（notMerge / 第一次）：写了的主类型按树的下标 replaceAll，其余被访问的给空列表；再补上预处理器的模型（axisPointer、有轴没 grid 时的 grid）——**只在 keys 里**，树里没有，作者没写过。
  - `TyOptionMerge`：先查重复 id（有就整个拒绝，什么都不改）；根上的非组件键按上面的规则；每个被访问的主类型做映射、合并或新建、重写树里的这一项；最后补预处理器的模型。树里一个主类型只在作者写过时才出现；写成单个对象、合并后仍是一个的，仍存成单个对象（不少读者只认对象形式）。keys 里有、树里没有节点的模型（预处理器的 grid）被写到时现建一个空节点再合并——和上游模型的原始 option 一样是 `{}`。
  - 盒子：对端口实际布局的那几种（grid、title、legend、visualMap、tree / sankey / treemap 系列），新选项碰了哪个方向，就按上游算出那个方向合并后的三个键，**全部写进树**（上游的 undefined 写成 null）。读者用 init 的规则读这三个自有键，得到的正是上游此刻的值。默认值和各读者自己用的一致（grid 15% / 10% / 65 / 80，title center / 15，legend center / bottom 15，visualMap 0 / null / null / 0，树 12%，桑基 5% / 20% / 5% / 5%，矩形树 20 / 50）。
  - `TyOptionToJson`：按 getOption 的形状输出——组件主类型一律数组、空洞 null、末尾空洞去掉、根上的 null 不输出；对象按 JS 键序（整数样的键升序在前）；数字按 `Number#toString`（NaN、无穷写 null）；字符串按 `JSON.stringify` 转义。
- **`TTyChartOption`**：`SetOptionText` 之后由 `TyOptionKeysOfTree` 建 keys；新的 `MergeOptionText`（没有树或树不是对象时就是第一次 setOption，即 SetOptionText）：解析失败、不是对象、重复 id 都**拒绝**，树不动、`Error` 说明原因——和 SetOptionText 的“拒绝就清空”不同，因为合并是对眼前画面的编辑，不是声明。合并进来的选项留到下一次设置，报告里的 `NewOpt` 指向它。`ComponentId / ComponentModelName / ComponentSubType / OptionJson`。新的 resourcestring `rsTyOptMergeNotObject`、`rsTyOptDuplicateId`（.pot 与 zh_CN.po 已同步）。
- **控件**：
  - `SetOption(AJson, ANotMerge = False)`：notMerge 就是上游的 notMerge——**同样的文本也重来**；否则 `MergeOption`。
  - `MergeOption(AJson): Boolean`：第一次是 init；否则先记下旧的视图键、合并、把 `Option` 属性的文本换成合并后的 `GetOptionJson`、按报告处理树外的状态、置 `FAnimPending`（这是一次更新）、重画。
  - 树外的状态按位置的命运处理（`MergeKeepStates`）：留下来的系列（kept / merged）保留力导向的 preservedPoints、roam 的写回、选中模型、树图视图的上一个盒子；合并写了 `center` 或 `zoom` 的，roam 状态里对应的那一半换成选项里的（`MergeRoamOverride`，读法与系列的 spec 相同）；新建的系列这些都清掉。树图的展开状态**全部清掉**（每次都访问系列、重建数据）。dataZoom：动作留下的窗口在合并写了这个 dataZoom 的范围（start/end/startValue/endValue/rangeMode 任一）时先写回树里（`MergeBefore`，start/end 百分比、两个值置 null，和 setRawRange 一样），再合并，再按模式规则置 null；没写的保留窗口；数组按新的个数伸长、新的没有窗口。悬停、按下、拖动、状态记录照 notMerge 清空；`FLegendLoaded := False`（图例每次都被访问，single 模式重新解决，`selected` 本身在树里、已合并）。
  - `GetOptionJson`、`ComponentModelId / ComponentModelName / ComponentModelSubType`。
  - **身份从 keys 来**：`AnimViewKeys`（更新动画配对新旧系列视图）改成模型 id；`SeriesModelId`（事件的 seriesId、图例悬停的 excludeSeriesId）先取模型 id；`SeriesNameOf` 在选项没写名字时先用模型留下的非虚名（类型改变后系列只剩新选项，名字仍是原来的——图例仍叫它 S，点 S 仍能关掉它）。

### 完全相同的文本（修正 §79）

§79 记下的偏差是“给 Option 赋和现在一样的文本什么也不做，不等于上游的 notMerge 重置”；B3 又依赖它（“同一文本再设不算新选项”）。问题不在于这条规则错，而在于属性一直被当成 setOption。现在分开：

- **`Option` 属性是声明**：它已经持有的文本再赋一次不是变化。LCL 流式加载、对象查看器、选项编辑器都会原样写回，点掉的图例项不能因此复位。
- **`SetOption(text, True)` 是上游的 notMerge**：同样的文本也是全新的模型，一切重来（fixture `identical-notmerge`）。
- **`SetOption(text)` / `MergeOption(text)` 是上游的合并**：从不是空操作；同样的文本合并到自己身上，状态全留（`identical-merge`）。
- 合并之后属性的文本是合并后的选项（画面与属性一致）；再赋**合并之前**那段文本就是真的变化，回到那个选项（notMerge）。

### 动画

合并是一次更新。系列视图按 `(模型 id, 类型)` 配对，id 在合并里不变：改了名的系列（id 仍是 `'\0A\00'`）保留视图、从原来的柱高补间过去；同样的改名用 notMerge 是新视图（id `'\0B\00'`）、从零长出来（手写测试与 fixture 的 `series-view-kept-on-rename` 一致）。fixture 每一步都记下上游复用了哪个视图，测试逐系列核对“上游复用 ⇔ 端口的 (id, 子类型) 配得上”。

**坐标轴的 `groupTransition` 仍然不做**（§126 推迟时的理由是“控件只有 notMerge，上游 notMerge 下坐标轴不过渡”——这个理由不成立了，原处已标注）：上游合并时坐标轴、网格这些组件视图保留，`groupTransition` 让刻度、标签、分隔线跟着新范围补间。端口没有坐标轴代理，合并下的轴直接跳到终值，系列照常补间——和 notMerge 下一样，与上游合并的画面有差别（AN 系列另立任务）。同理，标注（markPoint/markLine/markArea）在合并下上游是同一个视图、走更新，端口仍按 AN4 的规则每次重新入场；dataZoom / roam 的载荷动画（§127）也仍未做。

### 基准

- `tools/advchart-oracle/option-merge.js` → `tests/fixtures/advchart-option-merge.json`：真 dist（SSR、600×400、每个用例第一个选项 `animation: false`）。**原始合并层**由钩子录：包住所有组件类原型链上的 `init` 和 `mergeOption`，最外层调用时克隆进来的选项（默认值合并之前），之后每次 mergeOption 用 dist 自己的 `zrUtil.merge` 合进去（dataset 的 transform 按 primitive 整体替换）；根上的非组件键按 `_mergeOption` 的三行规则；再叠上端口也存在树里的模型写入——legend 的 `selected`（位置在 init 的键之后）、`mergeLayoutParam` 写回的方向（undefined 记为 null）。dataZoom 的四个范围键不比（端口把动作的窗口放在树外，窗口作为画面结果比较）。每一步记：原始合并层（端口 `GetOptionJson` 应给出的）、每个模型的 id / 名字 / 子类型（NUL 原样）、画面结果（每个系列的行数、是否被图例过滤、柱子的形状、选中的下标、树图每行的展开、graph 的中心和缩放；网格矩形；标题框；dataZoom 窗口）、每个系列用的是第几个视图对象。另记主类型表、依赖表、带子类型的主类型。标题都写明了字号（18 px 粗体，副标题 12 px）：端口的标题字来自主题，上游默认 18 px 粗体，不写明时标题框比不了。
- 52 个用例、134 步：系列按序号 / 追加 / 按名字 / 按 id / id 优先于名字 / 数字 id / id 不匹配时追加 / 名字之后按序号 / 带 id 的名字不匹配 / 改名（id 不变）/ 同名两个 / 类型改变（旧选项丢掉、id 和名字保留、新视图）/ 同类型显式写 / null 项不占序号 / 单个对象 / 改名保留视图而 notMerge 不保留；组件：xAxis 数组、title 由对象变数组、title 按 id、title 第一次出现（replaceAll 留空洞、之后按序号填洞）、legend 第一次写（随系列访问过，normalMerge 压缩空洞）、yAxis 类型改变、轴的默认子类型沿用；深合并、数组替换、null 写入、根上的 null 和 `[]`、根上的数组按下标合并（顺带比较系列颜色）；盒子：title ignoreSize（left→right、'auto'、默认 left 被 right 置 null 后再清掉）、legend、grid 计数规则（一个新键补优先的、两个新键、没写盒子的默认值、不碰盒子）、visualMap、树图系列（自己跟自己合并）；图例：合并后保留选中、`selected` 深合并、single 模式在只合并 title 时也重新解决、legend 类型改变（新模型、选中丢失）；相同文本的合并与 notMerge；dataZoom：动作窗口保留、value 盖过 percent、动作之后只写 end；系列选中保留与类型改变后丢失；树图展开在合并后丢失；graph 的 roam 保留、合并 zoom 只换缩放、合并 center 只换中心；dataset 的 transform 整体替换；预处理器的 axisPointer 与 grid 模型（init 时建的，合并时建的）。
- 守卫（任一失败不写文件）：每一步原始合并层的每个叶子都等于上游 getOption 同一路径上的值（这一层是上游所持有的子集）；逐用例的显式期望（改名 id 不变、类型改变保留 id 丢旧选项、空洞先填、根数组按下标、相同文本保留/重置……）；有盒子写回发生；两次生成逐字节相同。
- `test.advchart.optionmerge`（8 个测试）：真控件 600×400、SSR 量字，每步之后渲染：
  - 重放全部用例：`GetOptionJson` 按结构逐项比（组件内的键序也比，根上的键只比集合）、数字逐位；模型的 id / 名字 / 子类型逐个比（多出来的模型也算错）；行数、过滤、柱子形状（1e-9）、选中下标、树图展开、graph 中心与缩放逐位、网格矩形、标题框、dataZoom 窗口（1e-9）；视图配对。共约一万零七百项。
  - 主类型表、依赖表、子类型表与 dist 一致。
  - 手写：属性是声明（同文本不复位）而 `SetOption(text, True)` 复位、`SetOption(text)` 保留；合并后属性就是合并后的选项，再赋原文本回到原选项；拒绝的合并（解析失败、不是对象、重复 id——连同一选项里的 title 也不合并）什么都不改、下一次成功清掉错误；第一次合并就是 init；合并是更新（改名后柱子从旧高度补间，notMerge 改名从零长出）；类型改变后模型名字仍是 S、按 S 切换图例仍能关掉它。

### 变异测试

`wf-a10/mutate.py`：39 个变异，逐个改源码、重编、依次跑本批、B3（legendact）、AN3（animupdate）与 graph roam 四套测试、还原。

- 映射（5）：不按 id、不按名字、带 id 的选项也按名字、按序号时不跳过 id 不同的模型、没对上的丢掉而不追加；
- 合并（4）：较短的数组保留旧的、null 删除键、根上的数组整体替换、根上的 null 写进去；
- 模型（6）：类型改变也合并、合并不更新名字、id 重新生成、第一次出现也按 normalMerge、虚名从 1 数、生成的 id 可以重复；
- 访问与预处理器（5）：所有主类型都算访问过、不访问依赖者、init 时不建预处理器的模型、合并时不建、轴有 data 也默认 value；
- 盒子与模型规则（5）：不写回盒子、title 不按 ignoreSize、系列的盒子按新选项合并、value 模式不把百分比置空、dataset 的 transform 深合并；
- 树外的状态（6）：动作窗口不写回、合并丢掉所有动作窗口、roam 不按合并覆盖、合并过的系列丢掉状态、树图展开在合并后还留着、合并清掉图例的选中；
- 图例与身份（3）：single 模式不重新解决、视图键按名字、不读模型的名字；
- 属性与更新（5）：属性对同一文本也重来（B3 的测试也红）、notMerge 遇到同一文本跳过、合并后属性仍是合并前的文本、合并不当更新、不取合并前的视图键。

首轮 38 个杀死，存活 1 个：**合并时不建预处理器的模型**——已有用例里的 grid 都是 init 时由预处理器建的。补上游用例 `grid-preprocessed-on-merge`（先是饼图，再合并进坐标轴和柱子——这次合并的预处理器建出 grid——再合并 `grid.width`：上游合并进那个模型，盒子按默认值补出 left 15%），重跑杀死。

### 推迟与偏差

- **A11**：replaceMerge（只按 id 映射、未匹配的已有模型被移除留下空洞、`brandNew` 强制新视图）、整份选项的 replaceAll、空洞在系列下标、图例数据、dataZoom 目标里的跳过；`SetOption` 的选项对象形式（`{notMerge, replaceMerge, lazyUpdate, silent, transition}`）。接口已留好：keys 的列表、映射函数的模式参数、报告里每个位置的命运。
- **notMerge 下系列的 null 项不压缩**：上游 initBase 给 series 预置了列表，所以 `[bar, null, line]` 的 line 是系列 1（虚名 `series\u00001`）；端口的 notMerge 树照写的下标，line 是系列 2。只影响写了 null 系列项的选项，合并时按端口的下标找。
- 盒子写回只做端口实际布局的那几种；calendar（与 cellSize 联动的二次合并）、singleAxis、geo、parallel、matrix、timeline、thumbnail、slider dataZoom、map 系列、grid 的 `outerBounds` 只做深合并——合并没有碰盒子键时与上游相同。
- 预处理器只模拟了它们建的模型（axisPointer、grid）；markPoint/markLine/markArea 的根组件、axisPointer 的 `link` 归一、graphic 的包装、backwardCompat 的旧写法转换、timeline / media / baseOption 都不做（notMerge 下也不做）。
- `emphasis.label.show` 上游只在 init 时由 `label.show` 补（defaultEmphasis），合并改了 `label.show` 之后它保持 init 时的值；端口在读的时候从当前的 `label.show` 补。
- 系列从 dataset 维度自动取的名字（autoSeriesName）不进 keys；合并时按名字找人用的是写过的名字或虚名，维度名变了以后与上游可能不同。
- 选中：合并后留下来的系列保留选中模型，但 `selectedMode` 的改变和新数据里 `selected: true` 的补选（`_initSelectedMapFromData`）不重读。
- 合并后的悬停状态、强调状态记录照 notMerge 清空，下一次移动重新建立；上游复用的元素会带着状态。
- 拒绝的合并（重复 id）整个不生效；上游在断言处抛错，模型可能已经部分合并。
- `GetOptionJson` 是原始合并层：没有主题和默认值、没有模型 id、没有访问过但没写的主类型（上游是 `[]`），根上键的顺序是树里的顺序（上游按拓扑访问顺序）。上游 getOption 中 dataZoom 的 start/end 是计算出的窗口，端口树里是作者写的（动作的窗口在树外，直到合并写到它）。
- 未知的系列类型：上游找不到类时跳过这一项（后面的下标前移）；端口照常占位置。
