# TTyAdvanceChart 路线图进度审计(Tier 1 / 2 / 3)

- 审计对象:`D:/Projects/ty-advchart`(feat/advancechart,HEAD `68f470c1` T3 树图交互)
- 路线图:`docs/superpowers/research/2026-09-01-echarts/10-gap-analysis.md` §5
- 进度日志:`docs/superpowers/specs/2026-09-01-advancechart-tier0.md` §33–§116
- 核对方法:spec 每节的"实现"和"已知偏差/没做"逐条摘出,再到 `source/tyControls.AdvChart.*.pas` 和 `tyControls.AdvanceChart.pas` 里 grep option 键(排除生成的 `Catalog.pas`)。spec 里只说"押后"的一律不算做完。
- 渲染器表(`Marks.pas` `cRenderers` + `cElsewhere`)实际能画的 16 种:bar, line, scatter, effectScatter, candlestick, pictorialBar, heatmap, pie, funnel, gauge, radar, graph, tree, sunburst, treemap, sankey。
- 只注册、没有渲染器的 7 种(`Series.pas` `Reg`):boxplot, lines, map, parallel, themeRiver, chord, custom。
- 画廊语料(`examples/advchart/gallery`,245 个)里的出现次数,用来排优先级:
  - 系列:custom 13, map 4, lines 4, chord 4, boxplot 3, parallel 3, themeRiver 2。
  - 组件:toolbox 37, geo 12, matrix 12, polar 11, graphic 9, brush 5, singleAxis 3, thumbnail 2。
  - 键:emphasis 72, axisPointer 42, focus 37, selectedMode 13, rich 12, animationDuration 11, labelLine 11, valueAnimation 9, universalTransition 6, transform 6, breaks 5。

状态口径:
- **DONE**:行内列出的能力都在,只剩边角偏差。
- **PARTIAL**:主体在,行内点名的子项有缺。
- **NOT STARTED**:没有渲染或逻辑,至多只有注册或读键。

---

## Tier 1(28 行):DONE 10 · PARTIAL 14 · NOT STARTED 4

| 行 | 状态 | 证据 | 缺什么 |
|---|---|---|---|
| line:areaStyle(+origin)、smooth、smoothMonotone、step、connectNulls、clip、showSymbol | DONE | §36 areaStyle/origin/step/connectNulls;§38 showSymbol/showAllSymbol;§78 线裁剪;§97 smooth + smoothMonotone(`LinePath.pas`,`Marks.pas:385`) | 单点面积不出元素(§97);float32 `toStatic` 取整没做(§97);极坐标上的 line 归 polar 行 |
| 符号库:10 内置 + empty* + symbolSize/Rotate/Offset/KeepAspect | DONE | §37 `Symbol.pas`;§99 补 pin/arrow/line 到 `TyZrSymbol`;§105 逐项 symbol* | `image://` 不画(§37/§62);旋转后的 roundRect 退化成直角(§37) |
| bar:calcBarWidthAndOffset、横向、borderRadius、showBackground | DONE | §34 求解器;§40 四角圆角/showBackground/clip;§70 基线与 barMinHeight | NaN 行没有背景条(§40/§70);borderWidth 内缩没做(§70);`barMinWidth: 0`(§70);`backgroundStyle` 颜色读了但主题优先 |
| 堆叠:stack + stackStrategy×4 + stackOrder + addSafe | DONE | §35 `Stack.pas`;§46 图例过滤改变成员 | 极坐标柱的像素累加器(归 polar 行) |
| scatter / bubble | DONE | §37;§90 visualMap symbolSize 通道 | 回调形式的 symbolSize 只能走 visualMap 或第三列替身 |
| 饼图:start/endAngle、clockwise、padAngle、minAngle、roseType、selectedOffset、emphasis.scale、percentPrecision | PARTIAL | §39 布局/minAngle/roseType;§41 扇区圆角;§57 emphasis.scale;§69 最大余数 `{d}`;`Pie.pas:428-458` endAngle/clockwise/padAngle/roseType | **selectedOffset / 选中态**(源码里 0 处命中,依赖 select 状态);扇区命中仍用整环(§41) |
| 坐标轴解剖:axisLine(+onZero、箭头)、axisTick、minorTick、axisLabel、splitLine(+配色循环)、minorSplitLine、splitArea、name* / nameTruncate | PARTIAL | §48 显隐默认、minorTick/minorSplitLine;§51 onZero/offset;§53/§77 rotate/margin/inside;§68 字符串 formatter;§72 name/nameLocation/nameGap/nameRotate;§74 tick/split 跟标签走 | **axisLine.symbol 箭头**(Builder 不读 `symbol`);**nameTruncate**(0 命中);**splitLine/splitArea 颜色数组循环**(§48/§74:改成单个主题令牌);函数 formatter(`@Name` 没接到轴标签);轴线/名称颜色和字号走主题,不读作者值(§48/§72) |
| 多轴:position、offset、第二 Y 轴、gridIndex、alignTicks | DONE | §51 offset/onZeroAxisIndex;§82 alignTicks(`scaleCalcAlign`);Builder `gridIndex`/`position` | alignTicks 与 inverse、断轴、containShape 的交互没做(§82) |
| `axisLabel.interval: 'auto'` + ±1 滞回缓存 | PARTIAL | §73 `calculateCategoryInterval`(采样、×1.3、7px 下限、旋转投影) | **滞回缓存**:跨 setOption/缩放记住上次间隔,没做(§73);Q7 文档把它记为 5000 点重建 7.5 s 的下一步 |
| 时间轴:12 级阶梯、分级 tick、日历边界、级别格式器、24 个格式 token、本地化月/周名 | PARTIAL | §52 `Time.pas` 分级阶梯/日历步进/级别标签;§67 flat extent 与 min/maxInterval;`Time.pas:98` 24 个 token 与默认分级模板 | **`axisLabel.formatter` 在时间轴上完全不读**:字符串模板、按级别的对象、回调都没有(`Builder.pas:2632` 时间轴走 `TyTimeLabel`,不看 formatter);`{primary|…}` 富文本用 typeKey 替代;改应用语言后不重建就不重标(§52) |
| 图例组件:orient/align/盒子折行、逐项图标、selectedMode + **点击切换**、未选样式、formatter、selector | PARTIAL | §45 绘制与折行;§46 过滤;§65 类别入图例;§86 mergeLayoutParam;`Legend.pas` 读 formatter/icon/orient/align | **点击切换**(`MouseUp` 只处理 tree 展开收起,`Legend.pas:21` 自述"THE CLICK… not here");**selector 按钮**;**scroll 图例翻页**(§45/§86/§91);作者 `textStyle.color` / `inactiveColor` 不读(Legend 头注释) |
| tooltip:trigger、triggerOn、formatter 模板、valueFormatter、order、position、delay、alwaysShowContent | PARTIAL | §55 item trigger 与 richText 盒;§56 axis trigger 与 order;§69 模板;§84 子行/encode.tooltip | **position**(四种写法都没做);**valueFormatter**(模板或 `@Name` 都不接,§55/§83);**showDelay/hideDelay/alwaysShowContent**:读了不执行(`Tooltip.pas:513` "RECORDED, NOT OBEYED");`confine` 恒为真(有意偏差);markers/heatmap/sunburst/treemap/sankey 没有 tooltip(§99–§114);`@Name` 只接到 tooltip.formatter 一处(`AdvanceChart.pas:9825`) |
| axisPointer:line / shadow / cross、snap、值标签药丸、滑动动画 | PARTIAL | §56 三种类型、snap、九字段优先级;§68 标签 precision/formatter;§77 夹住的像素 | **滑动动画**(没有动画引擎);**值轴上的 shadow 带**(§56);link / triggerEmphasis(归 Tier 3) |
| markPoint / markLine / markArea:四种定位 + min/max/average/median | DONE | §98 模型/变换/布局(coord、x/y、xAxis/yAxis、type 统计、relativeTo);§99–§101 三种画面;`Marker.pas` median 等 | 标注 silent,没有 hover 和 tooltip(§99–§101);富文本标签只定位不画(§99/§100);markArea 渐变不填(§101);markPoint 的 path/image 符号(§100);极坐标标注 |
| 标签引擎:13 矩形 + 9 扇区位置、distance/rotate/offset、模板、内外自动对比色、overflow/ellipsis | PARTIAL | §43 13 个位置与模板;§69 `{a0}`/`$` 替换;§81 自动墨色 + halo;`LabelOpt.pas:273` overflow | **9 个扇区位置**(依赖 polar,§43);函数 formatter(`@Name` 没接到系列标签);标签背景框/边框/padding(§81);global textStyle、textBorderType、textShadow(§81) |
| 标签去碰撞:hideOverlap(AABB + OBB SAT)、moveOverlap(shiftLayoutOnXY) | PARTIAL | §73 轴标签 hideOverlap 与 OBB 求交;§72 nameMoveOverlap | **系列标签**的 `labelLayout.hideOverlap` / `moveOverlap` 都没有(§43:"重叠时叠着画");雷达轴标签 hideOverlap(§82) |
| 调色板:colorLayer、colorBy、逐系列色板、按名字记忆 | PARTIAL | §49 按名字的色板游标、colorBy data;§65 graph 共用游标;§115 treemap 的系列 `color` 列表 | **colorLayer**(0 命中);colorBy 的独立作用域(§49:只做了 pie 的顺序);treemap 的 seriesStyleTask 色板槽(§115) |
| 渐变(线性 + 径向)和图案填充 | PARTIAL | §50 colorStops、线性/径向、global;§88 visualMap 全局渐变 | **`type: 'pattern'` / image 图案**(§50);markArea 渐变填充(§101);文字渐变按上游本来就不做 |
| 动画引擎:31 种缓动 + cubic-bezier、进入/更新/离开、duration/delay/easing、animationThreshold、stateAnimation、标签从 oldLayout 过渡 | NOT STARTED | Q7 文档:静态层缓存和 `InvalidateFrame` 已落地,`PaintDynamic` 是有意留空的;源码没有 easing 表(`animationEasing` 只出现在一个测试夹具字符串里),只有 dataZoom 节流读 `animation`/`animationDurationUpdate` 定间隔(`DataZoomAct.pas:196`) | 全部:缓动库、帧驱动、元素补间、进入/更新/离开、状态动画、标签动画、阈值 |
| 状态贯通:emphasis lift(-0.1)、blur ×0.1、select z2、focus/blurScope、selectedMode、select/highlight 动作与事件 | PARTIAL | §57 hover emphasis(lift、scale、disabled);§80 graph 的 focus adjacency/blur/blurScope;§116 tree 的 ancestor/descendant/blur | **blur/focus 只有 graph 和 tree**,bar/line/pie/…的 `focus: 'series'/'self'` 不压暗别人(§57/§80);**select 状态、系列 selectedMode**(只有图例和 visualMap 读它);**highlight/downplay/select 动作和事件**(§80);`emphasis.label`(§57/§80);半透明/重叠的标记叠加高亮画错(§57) |
| 事件载荷 + HitTestAt 返回它 + 9 种鼠标事件带数据上下文 | PARTIAL | §54 `HitTestAt` → `TTyChartDatumRef`(含 rawDataIndex);`Handlers.pas` `TTyChartCallbackParams`;§79/§96/§116 OnGraphRoam、OnDataZoom、OnTreeRoam、OnTreeExpandAndCollapse | **图表级数据事件**(click/dblclick/mousedown/up/move/over/out/globalout/contextmenu 带 params)没有;只 publish 了 LCL 原生的 OnClick/OnMouse* |
| dataZoom:inside 手势(修饰键)+ slider + 窗口模型 + filterMode×4 | DONE | §94 处理层(filterMode×4、rangeMode、span);§95 slider 静态(数据阴影、手柄、标签);§96 交互(inside/修饰键/zoomLock/realtime/节流/brushSelect/动作/光标) | 触摸捏合(§96);作者写的 `emphasis.handleStyle` 不读(§96);翻转时手柄图标旋转而不是镜像(§95) |
| 数据管道:encode(18 角色)、dimensions、seriesLayoutBy、dataset、默认编码 | DONE | §47 dataset/encode/seriesLayoutBy/sourceHeader;§83 原始值通道、keyedColumns;§84 encode.tooltip/label、displayName;§87 D9 解析 | encode 列表只取第一项(§84);heatmap 值列固定取第 3 个元素(§102);polar/geo 角色要等对应坐标系;TypedArray 无法经 JSON 传入 |
| 采样:lttb / minmax / average / sum / max / min / nearest | NOT STARTED | `sampling` 在源码里只出现在一句注释里(`Graph.pas:806`);§94 明确没移植 | 全部 |
| 系列裁剪到绘图区 | DONE | §40 bar clip;§62 pictorial clip;§78 line/area 按 `getArea`,scatter 用 getArea(0.1) | 裁剪矩形在渲染时取整,y 方向差半像素(§78) |
| `media` 响应式查询(6 个键) | NOT STARTED | `media` 的 12 处命中全是 `median` | 全部;而且依赖 option 合并(baseOption + media 片段) |
| 导出:excludeComponents、backgroundColor、显式像素比 | PARTIAL | 有 `SaveToPng`(`AdvanceChart.pas:10171`),经 RenderTo 出图 | 三个选项都没有(0 命中);没有流/字节形式的 getDataURL 等价物 |
| Loading 指示器 | NOT STARTED | `showLoading` / `loading` 都是 0 命中 | 全部 |

---

## Tier 2(37 行):DONE 8 · PARTIAL 10 · NOT STARTED 19

| 行 | 状态 | 证据 | 缺什么 |
|---|---|---|---|
| polar 坐标系 + 极坐标 line/bar/scatter、扇区 cornerRadius、roundCap | NOT STARTED | line/bar 注册时列了 `polar`(`Series.pas:417`),但 `AdvanceChart.pas:5817` "polar, geo -- NOT PORTED";§63/§84/§97/§98 都记为没移植 | 全部;连带 9 个扇区标签位置、极坐标堆叠、极坐标标注、极坐标上的 line smooth |
| radar 组件 + 系列(含跨轴刻度对齐) | DONE | §61 `Radar.pas`;§82 scaleCalcAlign 环对齐;§84 雷达 tooltip;§91 visualMap | 系列数据点标签没实现(§69);轴标签 hideOverlap / fixMinMax(§82);radius 为 0 时不画(§82) |
| gauge:色带弧、progress、指针 + anchor、title/detail、valueAnimation、多值 | PARTIAL | §60 `Gauge.pas`(色带、path:// 指针、anchor、progress roundCap、detail);§91 逐行颜色 | **valueAnimation**(依赖动画);gauge 标题/详情颜色没核对(§91);`splitNumber: 0` 有意偏差 |
| funnel | DONE | §59 `Funnel.pas`(sort/align/gap/min/max/minSize/maxSize、幻影尖端) | `funnelAlign` 合并了两套词汇(有意偏差) |
| candlestick:OCLH、doji、自动布局、large、dataZoom 迷你图维度 | PARTIAL | §58 渲染器(涨跌/doji/borderColorDoji);§95 数据阴影用 open | **barWidth/barMaxWidth/barMinWidth 不读**,固定半个 band(`Marks.pas:1985`);**large 模式**;containShape(§75);subPixelOptimize(§76) |
| boxplot + boxplot 统计变换 | NOT STARTED | 只有注册和维度(`Series.pas:424`);`cRenderers` 里没有它;§84 "Boxplot rendering … open" | 渲染器、item tooltip、`prepareBoxplotData` / dataset transform `boxplot` |
| visualMap:连续 + 分段、8 通道、inRange/outOfRange、hoverLink、多边形条 | PARTIAL | §88–§93(B1–B4):两种子类型的模型、编码、组件视图、color/opacity/hue/sat/light/alpha/symbol/symbolSize/liftZ 通道、梯形条;§112 sunburst | **交互**:手柄拖动、hover 指示器、**hoverLink**、分段点击选中(§89/§93,`hoverLink` 0 命中);**decal 通道**(§88/§90) |
| 直角坐标热力图 | DONE | §102 H1 `BuildHeatmap` | tooltip / hover emphasis / progressive(§102,归其它行);`encode` 改值列不支持 |
| effectScatter 涟漪 | PARTIAL | §105 涟漪 number/brushType/showEffectOn;`Marks.pas:1631` | **只画第一帧静态涟漪**,没有动画;`rippleEffect.period/scale` 没用上(§105) |
| pictorialBar:repeat 求解、symbolClip、symbolBoundingData、pxSign | DONE | §62 `Pictorial.pas`(四个矩形、repeat 两遍求解、clip、boundingData、镜像) | `image://` 符号画不出(画廊 forest/hill/spirit 为空);path:// 不能镜像;逐项 `[w,h]` symbolSize;`label.position: 'outside'`(§62/§70) |
| sunburst:径向细分、levels、下钻、算法配色阶梯、径向/切向标签 | PARTIAL | §109 S1 布局/levels/配色/标签;§112 visualMap | **下钻 nodeClick / 返回父级的圆盘**;emphasis 的 ancestor/descendant;tooltip(§109) |
| treemap:squarified、面包屑、upperLabel、视觉子引擎、下钻 + 缩放 | PARTIAL | §110 squarify/面包屑(静态);§113 饱和度/upperLabel;§115 leafDepth、colorMappingBy、colorAlpha、rich 布局 | **下钻/缩放交互**(点击下钻、`zoomToNode`、roam、点面包屑);hover 配色、tooltip(§115);标签 opacity(§113) |
| tree:Buchheim、径向、4 朝向、2 种边、展开收起 | DONE | §107 T1、§108 T2、§116 T3(点击、roam、hover、tooltip) | 跨系列 blurScope(§116);hover 放大时外侧标签不跟着动;命中半径 7.5 对上游 4.5 |
| sankey:分层、松弛、飘带、orient、节点拖动、focus trajectory | PARTIAL | §114 K1 分层/松弛/飘带/两个方向/levels/渐变连线 | **节点拖动**;**focus: 'trajectory'** 和 emphasis;tooltip;边标签;zoom/center roam(§114) |
| graph:none/circular/force、autoCurveness、边裁剪、categories、focus adjacency、节点拖动 | PARTIAL | §63–§66 布局/曲率/箭头/类别/直角坐标;§79 roam;§80 adjacency/blur | **节点拖动**(§66/§79);边标签(§80);逐边 lineStyle、节点 border/opacity(§65/§66/§80);逐节点 label(§79) |
| chord:环形布局、minAngle 借角求解、飘带、渐变飘带 | NOT STARTED | 只有注册(`Series.pas:443`) | 全部(画廊 4 个) |
| singleAxis + themeRiver | NOT STARTED | 只有注册(`Series.pas:437`)和 dataZoom 的 singleAxisIndex 读取 | 全部 |
| 日历坐标系 + 日历热力图 | DONE | §103 H2 坐标系;§104 H3 热力图;§105/§106 日历上的 scatter/effectScatter/graph/pie | 用库的语言而不是图表 locale 取名字(§103);边距写成百分比字符串时不画 |
| View 坐标系 + RoamController(平移/缩放、scaleLimit、roamTrigger、preserveAspect、nodeScaleRatio) | DONE | §79 graph roam;§116 tree view/roam | 捏合缩放;`roamTrigger: 'selfRect'` 是近似;roam 动画;拖动后不抑制 click(§79);非均匀视图的箭头与线宽(§79) |
| brush:4 种形状、8 手柄 cover、inBrush/outOfBrush、brushLink、globalPan 互斥 | NOT STARTED | 源码里的 `brush` 命中全是 dataZoom slider 的 brushSelect(§95/§96) | 全部 |
| toolbox 原生工具条:saveAsImage、restore、框选 dataZoom、magicType、brush、自定义按钮 | NOT STARTED | 只有 `toolbox.feature.dataZoom` 会生成 select 型 dataZoom 模型(§94,`DataZoom.pas:524`),工具条本身不画 | 工具条视图和每个 feature(画廊 37 个文件有 toolbox) |
| timeline 组件 | NOT STARTED | 0 实现(只在 Tooltip.pas 一句注释里提到) | 全部;还依赖 option 合并 |
| 富文本引擎(`{name|content}`、逐片段盒子/图片/百分比宽度、lineOverflow) | NOT STARTED | 只有痕迹:treemap 遇到 `label.rich` 切换成 rich 截断布局(§115,`Treemap.pas:1307`);markers 检测到 rich 只保留文字不画(`MarkerView.pas:149`);补全器认 rich 通配(`Complete.pas:390`) | 解析器、样式继承、片段排版、渲染,以及到各处的接线(画廊 12 个文件用 rich) |
| Decal 图案 + aria 描述 | NOT STARTED | `decal` 只在 visualMap 通道名单里,注明"is not drawn"(`VisualMap.pas:2278`);`aria` 0 命中(按整词查) | 全部 |
| `graphic` 覆盖组件 | NOT STARTED | 0 命中 | 全部(画廊 9 个) |
| SVG `path://` | DONE | §37 符号;§60 gauge 指针;§89/§95 手柄图标;`ZrPath.pas` | — |
| `custom` 系列 | NOT STARTED | 只有注册(`Series.pas:447`);§97/§106 记 renderItem 是函数,JSON 写不下 | 全部(画廊 13 个,不画的类型里排第一);可以走 `@Name` 句柄 |
| `large` 模式批量路径 + 算术命中扫描 | NOT STARTED | 按整词查 `large` 只命中注释;§36 画廊把 large 压力用例排除了 | 全部 |
| 渐进 / 分块绘制 | NOT STARTED | 0 命中;heatmap progressive 记为押后(§102) | 全部 |
| `appendData` 流式追加 | NOT STARTED | 0 命中 | 全部 |
| lines 系列 | NOT STARTED | 只有注册(`Series.pas:428`,绑在 geo 上) | 全部 |
| `convertToPixel` / `convertFromPixel` / `containPixel` 公开 API | NOT STARTED | 0 命中;内部已有 `DataToPoint`/`PointToData`(§76) | 公开包装和 finder 解析(工作量小) |
| 坐标轴附加:containShape、dataMin/dataMax、jitter(+ beeswarm)、customValues | PARTIAL | §75 containShape;§67/§78 dataMin/dataMax | **jitter**(0 命中);**customValues**(§68/§73/§74) |
| labelLine 自动走线(nearestPointOnPath、limitTurnAngle、limitSurfaceAngle) | NOT STARTED | 只有 pie/funnel 的直两段引导线(§44/§59);三个算法都是 0 命中 | 全部 |
| 饼图 avoidLabelOverlap 完整求解器 | PARTIAL | §44 单个标签的外侧定位;`PieLabel.pas` 读了 alignTo/edgeDistance/bleedMargin/distanceToLabelLine | **求解器本体**:上下平移、椭圆上重算 x、借空间、截断;`PieLabel.pas:27` 自述"WHAT IS NOT HERE: the overlap solver" |
| `endLabel` + `label.valueAnimation` | NOT STARTED | `endLabel` 的命中全是轴的 showMin/MaxLabel(`TTyAxisEndLabel`) | 全部 |
| parallel + parallelAxis + 逐轴刷选 | NOT STARTED | 只有注册;§49 记它的视觉取用路径不同 | 全部 |

---

## Tier 3(23 行):DONE 0 · PARTIAL 5 · NOT STARTED 18

| 行 | 状态 | 证据 | 缺什么 |
|---|---|---|---|
| geo 坐标系(GeoJSON、区域命中、specialAreas、nameMap、boundingCoords、layoutCenter/Size、样式与选中) | NOT STARTED | `AdvanceChart.pas:5817` "polar, geo -- NOT PORTED";§33 | 全部(画廊 12 个) |
| map 系列 + 固定投影 | NOT STARTED | 只有注册 | 全部 |
| geo 上的热力图 | NOT STARTED | heatmap 注册时列了 geo,没有实现 | 全部 |
| `matrix` 坐标系 | NOT STARTED | `matrix` 的命中全是仿射矩阵;§101 matrix-stock 没画 | 全部(画廊 12 个) |
| `coordinateSystemUsage: 'box'` | PARTIAL | §106 pie 摆进日历格子(用 `coord` 或把 center 写成日期);§104–§106 系列落在日历格 | matrix 格子里的宿主;在格子里嵌坐标系或组件(grid/legend…) |
| 断轴(v6):分段映射、锯齿、刻度剪枝、展开收起动作 | PARTIAL | Tier 0 契约 ②:断轴 mapper 和 `test.advchart.scale.break`;§51/§67/§73/§76 都记"断轴还没接到任何 option" | option 接线、随机锯齿缓存、刻度剪枝、nice 扣除断开区间(§67)、expand/collapse 动作(画廊 5 个) |
| `realtimeSort` 柱状竞赛 | NOT STARTED | 0 命中 | 全部;依赖动画 |
| Universal transition + 形状变形 | NOT STARTED | 0 命中 | 全部;依赖动画 |
| `keyframeAnimation` + 过渡小语言 | NOT STARTED | 0 命中 | 全部 |
| 叠加动画 | NOT STARTED | — | 全部 |
| `thumbnail` 小地图 | NOT STARTED | 0 命中 | 全部 |
| parallel `axisExpandable` 鱼眼 | NOT STARTED | — | 全部(先要 parallel) |
| `axisPointer.link` + mapper | NOT STARTED | §56 把 link 列为押后 | 全部 |
| 跨控件联动 + 组合导出 | NOT STARTED | — | 全部 |
| dataset transform 管线(filter DSL、sort、管道、多输出) | NOT STARTED | `Dataset.pas` 头注释 "WHAT IS NOT HERE: dataset.transform";§47 | 全部(画廊 6 个) |
| 统计变换:回归、k-means、直方图 | NOT STARTED | `regression` 0 命中 | 全部 |
| `setOption` 式 option 树 + normal/replace 合并 | PARTIAL | Tier 0 第 4 项:宽松 JSON 树 + 整体替换(notMerge,`Option.pas:17-21`);§79 resize 与重设保留 roam | **normalMerge / replaceMerge / replaceAll、id/name 匹配**;把完全相同的 Option 文本当成 no-op,而不是 notMerge 重置(§79);media、timeline、toolbox restore/magicType 都依赖合并 |
| 事件的查询过滤 | NOT STARTED | 本来就没有图表级事件 | 全部(可以跟 Tier 1 的事件行一起做) |
| 粗指针命中回退 | NOT STARTED | — | 全部 |
| 脏矩形 / 缓存表面绘制 | PARTIAL | Q7 静态层缓存 `TTyPaintCache` + `InvalidateFrame` 已落地(一帧 1.18 ms) | 脏矩形(Q7 定为 Tier 3,只有像素成为瓶颈时才做) |
| 批量动作 + 细化事件 | NOT STARTED | — | 全部 |
| 设计期:系列/数据编辑对话框、属性编辑器、组件编辑器动词 | PARTIAL | `designtime/tyControls.Design.AdvChart.Editor.pas`:Option 的 SynEdit 编辑器(补全、参考树、诊断)+ `TComponentEditor` 动词 + `RegisterPropertyEditor`(Tier 0 第 6 项) | 结构化的系列/数据编辑对话框(`Values` 属性编辑器在 option 树 API 下已经不适用) |
| 键盘导航 + MSAA/UIA | NOT STARTED | 控件是 `TabStop := False`(§96 有意为之) | 全部 |

---

## 路线图行之外的押后项(§33–§116)

这些押后项在 spec 里写明了,但没有落在任何路线图行里,或只是某行的边角。按主题归并;§ 号是出处。

**全局或横切**

- **作者写的 `fontSize` 按 pt 而不是 px 解释。** 这是全库问题,测试靠跳过文字来绕开(§110/§113/§115,约三成标签)。应该第一批修。
- `@Name` 具名句柄只接到了 `tooltip.formatter` 一处。系列 label、axisLabel、legend、markers、visualMap/dataZoom 的 labelFormatter、`tooltip.valueFormatter` 都没接(§68/§69/§83)。
- 根级的 `textStyle`、`backgroundColor`、`darkMode` 都不读,背景取皮肤(§81)。
- 轴名、轴标签的字号和颜色不读作者写的值(§71/§72)。
- 标签描边(halo)是按整数偏移盖章,不是真轮廓,半透明描边会偏暗(§81)。
- `textBorderType`、`textShadow*` 没做;显式描边不撑大包围盒(§81)。
- 标签定位时没有按宿主描边撑大包围盒,所有系列有边框的符号标签都偏半个边框(§79)。
- 没有 tooltip 组件时照样出 tooltip(§66,全库)。
- 颜色 alpha 按字节取整,所以 `rgba(…,0.5)` 会落进另一档墨色(§81)。
- `rgba(0,0,0,0)` 被量化成"不填充",因而命中不到(§88)。
- 历史时区(V8 用地方平均时)、声明为 int 的维度、时间维上的 ±∞、序数维上的非字符串下标(§87)。

**坐标轴与布局**

- 刻度和轴线的 `subPixelOptimizeLine`,以及 y 轴刻度的 `ct·c` 项(§77)。
- 旋转标签按请求角度画,与分解重组后的矩阵差 ≤1.1e-15 rad(§85)。
- grid 盒子仍走共用求解器:`left: 'right'` 等关键字和 D12 合并没做(§71/§86)。
- top+bottom 超过高度时的 grid 盒子(§73)。
- 根级 left/top 通过 getShallow 漏进组件,没做(§86)。
- 标题 `top: 'middle'/'bottom'` 应该逐行对齐,现在是整块对齐(§86)。
- 斜的轴名或障碍物要用 OBB,现在不移(§72)。
- 旋转后的多行轴名只画一行(§72)。
- 轴名 tooltip 和 `triggerEvent` 没做(§72)。
- `axisLabel.minMargin`,以及估算里的 width+overflow(§71/§73)。
- 对数轴:非整数幂走 FPC 的 `Power`;`logBase ≤ 1` 当成 10(§67)。
- 数字 `data: []` 的类目轴不画;超过 2^20 个类目当成空轴(§78)。

**系列细节**

- graph:
  - 力导向在 webkit-dep 上约 1.4 s,步数上限 2000,可选 Barnes–Hut 或分帧(§64);
  - 边命中容差 4 px(§80);
  - `trigger: 'axis'` 时 graph 失去叠加高亮(§80)。
- 叠加式 emphasis 在半透明或重叠的标记上画错;graph 已改成原地高亮,其它系列还是叠加(§57/§80)。
- pictorialBar:hover 的命中目标是透明的柱矩形,不是符号组(§62)。
- 符号的描边宽度不计入单位长度(§62)。
- visualMap:
  - 尺寸为 0 的符号不建元素,而上游建一个不可见元素(§90);
  - `symbolSize` 的 `[w,h]` 对不支持;NaN 值的 symbol 没处理(§90);
  - 部分区间的 inRange 条没有圆角裁剪(§89);
  - 自定义图标的包围盒按控制点估(§89/§93/§95);
  - 连续型只支持单行文字,也不读 align 覆盖(§89)。
- 数据维:不在存储里的维度被当成数字解析,上游是序数下标(§88)。
- treemap:标签和 upperLabel 的 opacity 不跟 itemStyle.opacity(§113/§115)。
- sunburst:字符串值按数字相加,上游是字符串拼接;不认识的 `align` 就不画标签(§109)。
- sankey:NaN/Inf 几何不输出;渐变连线的包围盒不含描边(§114)。
- tree:径向标签的 `offset` 在屏幕空间加,没跟着旋转(§108)。
- 日历:名字用库的 locale 而不是图表的;`margin` 写成字符串且位置为 end 时的拼接差异(§103)。
- markers:
  - 上游会抛异常的元素这里跳过(§98);
  - `Time.parse` 与 `TyDzParse` 的取整不一致(§98)。

**交互细节**

- 拖动后没有抑制 click;拖动中 hover 命中一直是旧的,直到下次重画(§79)。
- 触摸捏合缩放没做(§79/§96)。
- roam 的光标样式只给了 dataZoom(§79/§96)。

---

## 剩余工作的依赖顺序批次

每批 1–3 天。"前置"写批次编号。原则是先做地基(句柄接线、字号、事件、富文本、动画、option 合并),再做依赖它们的功能;同一层里按画廊出现频次排先后。

### 阶段 A:地基

| 批 | 内容 | 天 | 前置 |
|---|---|---|---|
| A1 | `@Name` 句柄全面接线:系列 label、axisLabel(含时间轴)、legend.formatter、markers、visualMap/dataZoom labelFormatter、tooltip.valueFormatter、tooltip.position 的函数形式;参数记录统一走 `TTyChartCallbackParams` | 2 | — |
| A2 | 文字单位与全局文本:作者 fontSize 按 px(修 §110 全局问题)、根 textStyle / backgroundColor / darkMode、轴名与轴标签的作者字号和颜色 | 2 | — |
| A3 | 事件 E1:图表级 9 种鼠标事件带 params(click、dblclick、mousedown/up/move/over/out、globalout、contextmenu),顺带做 Tier 3 的"事件查询过滤" | 2 | A1 |
| A4 | 富文本 R1:`{style|text}` 解析、rich 样式继承链、片段量测与排版(width/height/align/padding/lineHeight/背景/边框/圆角),普通标签的背景框也走这里(§81) | 3 | A2 |
| A5 | 富文本 R2:接到系列 label、markers(§99/§100)、treemap/gauge rich、tooltip、轴标签;lineOverflow/truncate、百分比宽度 | 3 | A4 |
| A6 | 动画 AN1:缓动表(31 种 + cubic-bezier)、帧驱动(TTimer + TTyAnimator)、实现 `PaintDynamic`、元素属性补间、读 animation/threshold/duration/delay/easing(delay 可用 `@Name`) | 3 | — |
| A7 | 动画 AN2:各系列的进入动画(柱从基线长出、线和面积裁剪展开、饼扫角、散点缩放、仪表指针、层级系列淡入缩放),动画结束交回静态层,动画中的命中 | 3 | A6 |
| A8 | 动画 AN3:更新和离开(元素身份按系列 id/name + 数据名键)、option 变化/图例切换/dataZoom 时差分过渡、`*Update` 参数、stateAnimation | 3 | A7 |
| A9 | 动画 AN4:标签从 oldLayout 过渡、`valueAnimation`(gauge detail、label)、axisPointer 滑动、roam/dataZoom 动画、effectScatter 涟漪循环 | 2–3 | A8 |
| A10 | option 合并 MG1:`MergeOption` 的 normalMerge(组件与系列按 id/name/索引匹配)、完全相同文本的语义修正(§79) | 3 | — |
| A11 | option 合并 MG2:replaceMerge / replaceAll / 索引空洞 | 2–3 | A10 |

### 阶段 B:把 Tier 1 做完

| 批 | 内容 | 天 | 前置 |
|---|---|---|---|
| B1 | 状态 S1:select 状态、系列 selectedMode、pie selectedOffset、highlight/downplay/select/unselect/toggleSelect 动作与事件 | 3 | A3 |
| B2 | 状态 S2:focus/blur/blurScope 推广到所有系列(用 graph/tree 的原地重样式替换叠加高亮)、emphasis.label、图例 hover 联动高亮、sunburst ancestor/descendant、sankey trajectory | 3 | B1 |
| B3 | 图例 L1:点击切换 + legendselectchanged 事件 + legendToggleSelect 等动作;作者 textStyle.color / inactiveColor | 2 | A3 |
| B4 | 图例 L2:selector 按钮 + scroll 图例翻页(pageIcons、scrollDataIndex) | 2–3 | B3 |
| B5 | tooltip 收尾:position 四种写法、showDelay/hideDelay/alwaysShowContent 计时器、只在有 tooltip 组件时出(§66)、markers/heatmap/sunburst/treemap/sankey 的 tooltip | 2 | A1 |
| B6 | 坐标轴收尾:axisLine 箭头、nameTruncate、splitLine/splitArea 颜色数组循环、interval 'auto' 的 ±1 滞回缓存、axisPointer 值轴 shadow 带 | 2 | — |
| B7 | 时间轴 formatter:字符串模板(24 token)、按级别对象的级联、`{primary|}` 走富文本 | 2 | A1, A5 |
| B8 | 标签去碰撞:系列 labelLayout 的 hideOverlap(AABB/OBB)和 moveOverlap(shiftLayoutOnXY)、labelLayout 的 x/y/dx/dy/rotate | 2–3 | — |
| B9 | 调色板与填充:colorLayer、colorBy 作用域、`pattern` 填充、markArea 渐变填充 | 2 | — |
| B10 | 采样:lttb(上游变体)/ minmax / average / sum / max / min / nearest | 2 | — |
| B11 | 导出 + Loading:excludeComponents / backgroundColor / pixelRatio / 流与字节导出;showLoading/hideLoading(转圈用 A6 的帧驱动) | 2 | A6 |
| B12 | media:6 个查询键、baseOption + media 合并、resize 时重新判定 | 1–2 | A10 |
| B13 | 饼图 avoidLabelOverlap 求解器(平移、椭圆重算、bleedMargin、edgeDistance、截断) | 3 | B8 |
| B14 | labelLine 自动走线(nearestPointOnPath、limitTurnAngle、limitSurfaceAngle、smooth) | 2 | B13 |
| B15 | endLabel(valueAnimation 部分用 A9 的) | 1–2 | A9 |

### 阶段 C:Tier 2 的系列与组件

| 批 | 内容 | 天 | 前置 |
|---|---|---|---|
| C1 | candlestick 收尾(barWidth/barMaxWidth/barMinWidth、containShape、subPixelOptimize)+ boxplot 渲染器、统计变换与 tooltip | 3 | — |
| C2 | `convertToPixel` / `convertFromPixel` / `containPixel` + finder;jitter(beeswarm)与 customValues | 2 | — |
| C3 | polar P1:polar 坐标系、angleAxis/radiusAxis、轴与网格绘制、极坐标 axisPointer | 3 | — |
| C4 | polar P2:极坐标上的 line/bar/scatter/effectScatter/heatmap、9 个扇区标签位置、roundCap(Sausage)与柱扇区圆角、极坐标堆叠与标注、dataZoom 目标 | 3 | C3 |
| C5 | graph/sankey 交互:节点拖动、sankey 的 tooltip/边标签/roam、graph 边标签与逐边 lineStyle | 2–3 | B2 |
| C6 | sunburst/treemap 交互:sunburst 下钻与返回圆盘、treemap 点击下钻/zoomToNode/面包屑点击/roam/hover/tooltip | 3 | B2(可选 A8 做下钻动画) |
| C7 | visualMap 交互:手柄拖动(calculable/realtime)、hover 指示器、双向 hoverLink、分段点击选中 | 2–3 | B2 |
| C8 | large 模式:bar/line/scatter/candlestick 的批量路径、算术命中扫描、largeThreshold | 3 | C1 |
| C9 | progressive + appendData:按帧时间预算分块绘制、progressiveThreshold/ChunkMode、appendData API | 2–3 | A6, C8 |
| C10 | singleAxis + themeRiver | 2–3 | — |
| C11 | chord(环形布局、minAngle 借角、飘带、渐变飘带) | 2–3 | — |
| C12 | lines 系列(直角坐标先行;两点/折线、端点符号、effect 拖尾走 A9) | 2–3 | A9 |
| C13 | graphic 组件(13 种元素、$action、变换、bounding、文字走富文本) | 3 | A5 |
| C14 | custom 系列 CU1:`renderItem` 作 `@Name` 句柄、api.value/coord/size/style/visual/barLayout、元素类型复用 C13 | 3 | A1, C13 |
| C15 | custom CU2:极坐标/日历/singleAxis 上的 custom、过渡动画 | 2 | C14, C3, A8 |
| C16 | toolbox:原生工具条、saveAsImage、restore、dataZoom 选择与回退(模型已有)、magicType、自定义按钮、dataView 原生对话框 | 3 | B11, A10, A3 |
| C17 | brush BR1:组件模型、4 种形状、带 8 手柄的 cover、single/multiple 模式 | 3 | A3 |
| C18 | brush BR2:inBrush/outOfBrush 视觉、brushLink、brushSelected 事件、与 dataZoom/roam 的 globalPan 互斥、toolbox 的 brush 按钮 | 3 | C17, C16 |
| C19 | parallel PA1:parallel 坐标系 + parallelAxis + 系列 | 3 | — |
| C20 | parallel PA2:逐轴刷选(areaSelectStyle) | 2 | C19, C18 |
| C21 | timeline:组件视图、播放/暂停/单步计时、option 数组合并到 baseOption、autoPlay/loop/rewind、checkpoint 滑动 | 3 | A10, A6 |
| C22 | decal + aria:图案生成(LCM 平铺、旋转、6 种内置)、aria.decal 自动分配、visualMap decal 通道、aria 描述文字 | 2–3 | B9 |

### 阶段 D:Tier 3

| 批 | 内容 | 天 | 前置 |
|---|---|---|---|
| D1 | 断轴:`breaks` 接到已有 mapper、随机锯齿缓存、刻度剪枝、nice 扣除断开区间、展开收起动作 | 3 | — |
| D2 | dataset transform:注册表、filter DSL(不含 reg)、sort、管道、多输出 | 3 | — |
| D3 | 统计变换:回归 4 种、k-means、直方图 4 种分箱 | 3 | D2 |
| D4 | realtimeSort 柱状竞赛 | 2–3 | A8 |
| D5 | universalTransition(UT1–UT3:dividePath/combine/separate 变形、groupId 方向嗅探) | 3×3 | A8 |
| D6 | keyframeAnimation + 过渡小语言、叠加动画 | 3 | A8, C13 |
| D7 | thumbnail 小地图;parallel axisExpandable | 3 | C19 |
| D8 | axisPointer.link + mapper;跨控件联动(共享控制器)+ 组合导出;批量动作 | 3 | B1, B11 |
| D9 | 粗指针命中回退 + 脏矩形 | 2–3 | — |
| D10 | 设计期的系列/数据结构化编辑对话框 | 3 | — |
| D11 | 键盘导航 + UIA/MSAA(接 aria 描述) | 3 | B1, C22 |
| D12 | matrix 坐标系(MX1–MX3:树形表头、定位代数、合并单元格) | 3×3 | — |
| D13 | coordinateSystemUsage 'box':matrix/日历格子里嵌坐标系和组件 | 3×2 | D12 |
| D14 | geo(GE1–GE4):GeoJSON 解析 + registerMap、投影接口、区域绘制/命中/选中、roam、map 系列、geo 上的 scatter/lines/heatmap | 3×4 | C12 |

合计约 70 批。阶段 A(11 批,约 28 天)是后面几乎所有交互和视觉行的前置:A1/A3 解锁事件、图例、tooltip;A4/A5 解锁时间轴格式、graphic、标注富文本;A6–A9 解锁 valueAnimation、realtimeSort、universalTransition、涟漪、loading、progressive;A10 解锁 media、timeline、toolbox。

如果按画廊的覆盖收益,而不是按地基先行来排:A1 → A2 → A3 → B3(图例点击)→ B1/B2(状态,emphasis 72、focus 37)→ A4/A5(rich 12)→ C16(toolbox 37)→ C3/C4(polar 11)→ C14(custom 13)→ A6–A9(动画)。
