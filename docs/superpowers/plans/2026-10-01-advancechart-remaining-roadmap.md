# TTyAdvanceChart 路线图进度审计(Tier 1 / 2 / 3)

- 审计对象:`D:/Projects/ty-advchart`(feat/advancechart-tier2,HEAD `8a7de2df` 合入 D5–D8;初版审计在 feat/advancechart `68f470c1` T3 树图交互;2026-10-13 更新到第 131 批,2026-10-12 里程碑 D1–D4(§174)更新到第 135 批,里程碑 D5–D8(§180)更新到第 141 批)
- 路线图:`docs/superpowers/research/2026-09-01-echarts/10-gap-analysis.md` §5
- 进度日志:`docs/superpowers/specs/2026-09-01-advancechart-tier0.md` §33–§180
- 核对方法:spec 每节的"实现"和"已知偏差/没做"逐条摘出,再到 `source/tyControls.AdvChart.*.pas` 和 `tyControls.AdvanceChart.pas` 里 grep option 键(排除生成的 `Catalog.pas`)。spec 里只说"押后"的一律不算做完。
- 渲染器表(`Marks.pas` `cRenderers` 8 种 + `cElsewhere` 14 种)实际能画的 22 种:bar, line, scatter, effectScatter, candlestick, boxplot, pictorialBar, heatmap, pie, funnel, gauge, radar, graph, tree, sunburst, treemap, sankey, themeRiver, chord, lines, custom, parallel。
- 只注册、没有渲染器的 1 种(`Series.pas` `Reg`):map(等 geo,D14)。
- 画廊语料(`examples/advchart/gallery`,245 个)里的出现次数,用来排优先级:
  - 系列:custom 13, map 4, lines 4, chord 4, boxplot 3, parallel 3, themeRiver 2。
  - 组件:toolbox 37, geo 12, matrix 12, polar 11, graphic 9, brush 5, singleAxis 3, thumbnail 2。
  - 键:emphasis 72, axisPointer 42, focus 37, selectedMode 13, rich 12, animationDuration 11, labelLine 11, valueAnimation 9, universalTransition 6, transform 6, breaks 5。

状态口径:
- **DONE**:行内列出的能力都在,只剩边角偏差。
- **PARTIAL**:主体在,行内点名的子项有缺。
- **NOT STARTED**:没有渲染或逻辑,至多只有注册或读键。

---

## Tier 1(28 行):DONE 25 · PARTIAL 3 · NOT STARTED 0

| 行 | 状态 | 证据 | 缺什么 |
|---|---|---|---|
| line:areaStyle(+origin)、smooth、smoothMonotone、step、connectNulls、clip、showSymbol | DONE | §36 areaStyle/origin/step/connectNulls;§38 showSymbol/showAllSymbol;§78 线裁剪;§97 smooth + smoothMonotone(`LinePath.pas`,`Marks.pas:385`) | 单点面积不出元素(§97);float32 `toStatic` 取整没做(§97);极坐标上的 line 归 polar 行 |
| 符号库:10 内置 + empty* + symbolSize/Rotate/Offset/KeepAspect | DONE | §37 `Symbol.pas`;§99 补 pin/arrow/line 到 `TyZrSymbol`;§105 逐项 symbol* | `image://` 不画(§37/§62);旋转后的 roundRect 退化成直角(§37) |
| bar:calcBarWidthAndOffset、横向、borderRadius、showBackground | DONE | §34 求解器;§40 四角圆角/showBackground/clip;§70 基线与 barMinHeight | NaN 行没有背景条(§40/§70);borderWidth 内缩没做(§70);`barMinWidth: 0`(§70);`backgroundStyle` 颜色读了但主题优先 |
| 堆叠:stack + stackStrategy×4 + stackOrder + addSafe | DONE | §35 `Stack.pas`;§46 图例过滤改变成员;§148 极坐标柱按基值与符号的像素累加器(`lastStackCoords`) | — |
| scatter / bubble | DONE | §37;§90 visualMap symbolSize 通道 | 回调形式的 symbolSize 只能走 visualMap 或第三列替身 |
| 饼图:start/endAngle、clockwise、padAngle、minAngle、roseType、selectedOffset、emphasis.scale、percentPrecision | DONE | §39 布局/minAngle/roseType;§41 扇区圆角;§57 emphasis.scale;§69 最大余数 `{d}`;`Pie.pas:428-458` endAngle/clockwise/padAngle/roseType;§123 选中态与 selectedOffset(标签、引导线一起平移);§129 选中平移与 emphasis 放大的状态过渡;§180 系列与数据项的 `itemStyle.opacity`(此前只画 visualMap 的) | 扇区命中仍用整环,圆角外一点也算中(§41);常态隐藏、只在状态里显示的标签不建(§123/§144);内侧标签在选中色上不重挑墨色(§123) |
| 坐标轴解剖:axisLine(+onZero、箭头)、axisTick、minorTick、axisLabel、splitLine(+配色循环)、minorSplitLine、splitArea、name* / nameTruncate | DONE | §48 显隐默认、minorTick/minorSplitLine;§51 onZero/offset;§53/§77 rotate/margin/inside;§68 字符串 formatter;§72 name/nameLocation/nameGap/nameRotate;§74 tick/split 跟标签走;§117 函数 formatter;§118 轴标签与轴名的作者字体、颜色;§121 轴标签与轴名的 rich/盒子;§136 axisLine 箭头、nameTruncate、splitLine/splitArea 颜色列表轮流取(跨渲染保色) | 轴线与箭头颜色走皮肤 `TyAdvChartAxisLine`,不读 `axisLine.lineStyle.color`(§136);splitLine 的 width/type、splitArea 的 opacity 仍是皮肤的(§136);`image://` 箭头不画(§136);截成空串的轴名当没有名字(§136) |
| 多轴:position、offset、第二 Y 轴、gridIndex、alignTicks | DONE | §51 offset/onZeroAxisIndex;§82 alignTicks(`scaleCalcAlign`);Builder `gridIndex`/`position` | alignTicks 与 inverse、containShape 的交互没做(§82);写了 `breaks` 的轴照上游不参加 alignTicks(§169) |
| `axisLabel.interval: 'auto'` + ±1 滞回缓存 | DONE | §73 `calculateCategoryInterval`(采样、×1.3、7px 下限、旋转投影);§136 滞回缓存(只抑制减一、resize 不用,按轴记忆,notMerge 清空) | replaceMerge 删轴不补时记忆留到这个下标再有新轴才清;隐藏的轴不量间隔(§136);量的是主题字体而不是上游的 12px,拥挤类目上可差一档(§145);时间线组件的跨渲染缓存不做(§165) |
| 时间轴:12 级阶梯、分级 tick、日历边界、级别格式器、24 个格式 token、本地化月/周名 | DONE | §52 `Time.pas` 分级阶梯/日历步进/级别标签;§67 flat extent 与 min/maxInterval;`Time.pas:98` 24 个 token 与默认分级模板;§117 字符串与 `@Name` formatter;§139 上游替换链、按级别对象与级联、`{primary|}` 走富文本、指针标签与轴 tooltip 表头走 getLabel | 改应用语言后不重建就不重标(§52);没有 `locale` 选项,月名走本库三级规则(§139,有意);毫秒级 getLabel 到不了(§139);日历算术钳在公元 1–9999 年(§139) |
| 图例组件:orient/align/盒子折行、逐项图标、selectedMode + **点击切换**、未选样式、formatter、selector | DONE | §45 绘制与折行;§46 过滤;§65 类别入图例;§86 mergeLayoutParam;`Legend.pas` 读 formatter/icon/orient/align;§117 `@Name` formatter;§128 点击切换、五个图例动作与 legendselectchanged、悬停联动高亮、作者 textStyle/inactiveColor;§131 切换的过渡;§133 selector 按钮与 scroll 翻页(legendScroll、翻页补间);§135 找不到名字的项不画 | `legend.data[i]` 里的 inactiveColor/textStyle 不读(§121/§128);`image://` 翻页图标不画(§133);`emphasis.selectorLabel` 只读颜色(§133);按钮命中是整个盒子(§133) |
| tooltip:trigger、triggerOn、formatter 模板、valueFormatter、order、position、delay、alwaysShowContent | PARTIAL | §55 item trigger 与 richText 盒;§56 axis trigger 与 order;§69 模板;§84 子行/encode.tooltip;§117 valueFormatter 与各处 `@Name`;§135 position 四种写法与函数形式、showDelay/hideDelay/alwaysShowContent 计时器、只在有 tooltip 组件时出、markers/heatmap/sunburst/treemap/sankey 的 tooltip、`axisPointer.status: 'show'` 的初始指针 | **`triggerOn: 'click'` 仍不出盒子**(§135);Invalidate、dataZoom、动作重建时盒子被清掉,alwaysShowContent 也不 keepShow(§135);未写的 confine 按真(有意偏差,§135);状态显示的指针只认直角坐标(§135);旭日/矩形树图/桑基的格式器参数走通用 TooltipParams(§135);**connect 的组里不跨图联动**(不走 updateAxisPointer / showTip / hideTip,§179/§180,见 D8b) |
| axisPointer:line / shadow / cross、snap、值标签药丸、滑动动画 | DONE | §56 三种类型、snap、九字段优先级;§68 标签 precision/formatter;§77 夹住的像素;§127 滑动动画('auto' 判定、轴自己的 axisPointer 优先);§136 值轴/时间轴的 shadow 带;§146 极坐标指示器 | 极坐标指示器不做移动动画(§146);指示器标签按皮肤排版、跟着线走,不与上游逐位比(§127);`triggerEmphasis` 不读(§179);link 见 Tier 3 |
| markPoint / markLine / markArea:四种定位 + min/max/average/median | DONE | §98 模型/变换/布局(coord、x/y、xAxis/yAxis、type 统计、relativeTo);§99–§101 三种画面;`Marker.pas` median 等;§119 标注不再 silent、发鼠标事件;§121 富文本标签画出;§127/§134 markLine 划出、markPoint 弹出与合并下的更新;§135 标注 tooltip;§140 markArea 渐变/图案填充;§148 极坐标上的 markPoint/markLine | 更新按数据下标配对,增删重排会配错(§134);被淡化系列的标注不变淡(§125);markPoint 的 path/image 符号(§100);极坐标上 markArea 不建(上游抛错,§148);单轴上不建标注(§153) |
| 标签引擎:13 矩形 + 9 扇区位置、distance/rotate/offset、模板、内外自动对比色、overflow/ellipsis | DONE | §43 13 个位置与模板;§69 `{a0}`/`$` 替换;§81 自动墨色 + halo;`LabelOpt.pas:273` overflow;§117 函数 formatter;§118 根 textStyle 与 darkMode 描边;§121 背景框/边框/padding/文字阴影;§148 9 个扇区位置 | textBorderType 没做(§81);`fontStyle` 斜体画家画不出(§118/§120);文字阴影不模糊(§121);图片背景没做(§120) |
| 标签去碰撞:hideOverlap(AABB + OBB SAT)、moveOverlap(shiftLayoutOnXY) | DONE | §73 轴标签 hideOverlap 与 OBB 求交;§72 nameMoveOverlap;§138 系列 labelLayout 的 hideOverlap/moveOverlap、x/y/dx/dy/rotate 与 `@Name`;§144 饼先挪后藏 | endLabel、漏斗标签不进清单(§138);labelLayout 的 width/height 读了不应用、draggable 不做(§138);雷达轴标签 hideOverlap(§82) |
| 调色板:colorLayer、colorBy、逐系列色板、按名字记忆 | DONE | §49 按名字的色板游标、colorBy data;§65 graph 共用游标;§115 treemap 的系列 `color` 列表;§140 colorLayer、colorBy 按「类型-colorBy」共享作用域、主题九色也走游标与名字备忘 | treemap 的 seriesStyleTask 色板槽(§115);逐数据取色没接 heatmap/lines/parallel(§140/§164);调色板里的渐变条目只取第一个色标(§140) |
| 渐变(线性 + 径向)和图案填充 | DONE | §50 colorStops、线性/径向、global;§88 visualMap 全局渐变;§140 `type: 'pattern'`(含旋转/缩放)、markArea 渐变与图案填充;§167 decal 平铺图案 | 图案只认 `data:` URL,描边的图案不画(§140);图例图标上的渐变用图标盒子(§140);文字渐变按上游本来就不做 |
| 动画引擎:31 种缓动 + cubic-bezier、进入/更新/离开、duration/delay/easing、animationThreshold、stateAnimation、标签从 oldLayout 过渡 | PARTIAL | Q7 文档:静态层缓存和 `InvalidateFrame`;§122 AN1 引擎(31 缓动 + cubic-bezier、Clip/Track/Animator、animation* 选项与阈值);§124 AN2 入场;§126 AN3 更新与离场;§127 AN4 标签旧布局、valueAnimation、标注、涟漪、指示器滑动;§129 AN3b 状态过渡(stateAnimation);§131 AN5 图例/dataZoom 的整体更新与坐标轴 groupTransition;§134 AN6 合并式 setOption 的过渡 | **象形柱、关系图、树、矩形树图、旭日图、桑基图没有入场**(§124;旭日/矩形树图只有下钻过渡,§150);**仪表盘、雷达、关系图、树、矩形树图、桑基图的悬停没有状态过渡**(§129/§150);阶梯线更新直接到终值(§126);轴名、次刻度、分隔区域不做 groupTransition(§131);渐变插值、逐关键帧缓动、pause/resume(§122) |
| 状态贯通:emphasis lift(-0.1)、blur ×0.1、select z2、focus/blurScope、selectedMode、select/highlight 动作与事件 | PARTIAL | §57 hover emphasis(lift、scale、disabled);§80 graph 的 focus adjacency/blur/blurScope;§116 tree 的 ancestor/descendant/blur;§123 B1 状态机(select 状态、系列 selectedMode、select/unselect/toggleSelect 动作与 selectchanged,悬停改为原地);§125 B2 blurSeries/allLeaveBlur 推到漏斗、热力图、K 线、象形柱、旭日图,highlight/downplay 三步;§128 图例悬停联动;§129 状态过渡;§143/§148/§149 箱线图、极坐标柱线、桑基图接上状态机 | **关系图、树、矩形树图仍是各自的原地重样式**,不接共享模型:与其它系列不互相淡化,highlight/downplay 对它们只发事件(§125/§149/§150);**仪表盘、雷达仍走覆盖层**(§125);被淡化系列的标注不变淡(§125);large 元素点击不派发 select(§152);饼、漏斗常态隐藏的标签不建,状态里的 label.show 看不到(§123/§125) |
| 事件载荷 + HitTestAt 返回它 + 9 种鼠标事件带数据上下文 | DONE | §54 `HitTestAt` → `TTyChartDatumRef`(含 rawDataIndex);`Handlers.pas` `TTyChartCallbackParams`;§79/§96/§116 OnGraphRoam、OnDataZoom、OnTreeRoam、OnTreeExpandAndCollapse;§119 九种图表级鼠标事件带 params(`ChartOn`/`ChartOff`/`OnChartEvent`,照 zrender 的悬停状态机);§123/§128/§132 select、legendselectchanged、updated 等动作事件 | 轴标签命中框不随旋转转;markLine/markArea 的 name/value 不全(§119);LCL 的 DblClick 没坐标,用最近一次按下点(§119);时间线刻度不是数据项,不发图表鼠标事件(§165);toolbox 的 restore/magictypechanged/dataviewchanged 不在 `ChartOn` 事件表里(§166) |
| dataZoom:inside 手势(修饰键)+ slider + 窗口模型 + filterMode×4 | DONE | §94 处理层(filterMode×4、rangeMode、span);§95 slider 静态(数据阴影、手柄、标签);§96 交互(inside/修饰键/zoomLock/realtime/节流/brushSelect/动作/光标) | 触摸捏合(§96);作者写的 `emphasis.handleStyle` 不读(§96);翻转时手柄图标旋转而不是镜像(§95) |
| 数据管道:encode(18 角色)、dimensions、seriesLayoutBy、dataset、默认编码 | DONE | §47 dataset/encode/seriesLayoutBy/sourceHeader;§83 原始值通道、keyedColumns;§84 encode.tooltip/label、displayName;§87 D9 解析 | encode 列表只取第一项(§84);heatmap 值列固定取第 3 个元素(§102);geo 角色要等 geo(D14;polar 的两维 §148 已有);TypedArray 无法经 JSON 传入 |
| 采样:lttb / minmax / average / sum / max / min / nearest | DONE | §137 B10 七种采样器(lttb 按上游变体、按设备像素算速率) | 函数形式的 `sampling` 不支持(§137);上游会抛异常的 lttb 不抛(§137);dataZoom 动作后按原始网格读尺寸(§137);格式器句柄的 Values 是采样后的值(§137) |
| 系列裁剪到绘图区 | DONE | §40 bar clip;§62 pictorial clip;§78 line/area 按 `getArea`,scatter 用 getArea(0.1) | 裁剪矩形在渲染时取整,y 方向差半像素(§78) |
| `media` 响应式查询(6 个键) | DONE | §142 B12 查询键、`baseOption` + `media` 合并(`resetOption('media')`)、Resize/Loaded 时重新判定 | 上游会抛错的查询当不成立(§142);`resetOption('recreate')` 不单独提供(§132/§142);合并后 `Option` 属性不含 media(§142) |
| 导出:excludeComponents、backgroundColor、显式像素比 | DONE | 有 `SaveToPng`(`AdvanceChart.pas:10171`),经 RenderTo 出图;§141 B11 excludeComponents、backgroundColor、pixelRatio,`SaveToStream` 等流与字节导出(PNG/JPEG) | 悬停的提示框、指示器、强调不进导出(§141);只有 PNG 与 JPEG(§141);没写背景时画皮肤底而不是透明(§141) |
| Loading 指示器 | DONE | §141 B11 `ShowLoading`/`HideLoading`(上游 default 转圈,用 A6 的帧驱动) | 遮罩不接管指针,挡不住悬停与点击(§141);`zlevel`、`fontStyle` 不读(§141) |

---

## Tier 2(37 行):DONE 34 · PARTIAL 3 · NOT STARTED 0

| 行 | 状态 | 证据 | 缺什么 |
|---|---|---|---|
| polar 坐标系 + 极坐标 line/bar/scatter、扇区 cornerRadius、roundCap | DONE | §146 C3 polar 坐标系、angleAxis/radiusAxis、轴与网格、极坐标 axisPointer 与换算;§148 C4 极坐标上的 line/bar/scatter/effectScatter/heatmap、9 个扇区标签位置、roundCap(Sausage)与扇区圆角、极坐标堆叠、markPoint/markLine、dataZoom 目标 | polar 上滚轮/拖动的 inside dataZoom 不触发(§148);极坐标指示器不动画(§146);极坐标柱不走 labelLine(§148);动画开着时径向柱的百分比圆角与切向标签转角按终态算(§148);`polar.tooltip` 不读(§146);格子里的 polar 归 Tier 3 的 `'box'` 行 |
| radar 组件 + 系列(含跨轴刻度对齐) | DONE | §61 `Radar.pas`;§82 scaleCalcAlign 环对齐;§84 雷达 tooltip;§91 visualMap | 系列数据点标签没实现(§69);轴标签 hideOverlap / fixMinMax(§82);radius 为 0 时不画(§82) |
| gauge:色带弧、progress、指针 + anchor、title/detail、valueAnimation、多值 | DONE | §60 `Gauge.pas`(色带、path:// 指针、anchor、progress roundCap、detail);§91 逐行颜色;§121 读数/标题的 rich;§124 指针与进度弧入场;§127 detail 的 valueAnimation | gauge 标题/详情颜色没核对(§91);悬停仍走覆盖层、没有状态过渡(§125/§129);rich 不接根 textStyle(§121);`splitNumber: 0` 有意偏差 |
| funnel | DONE | §59 `Funnel.pas`(sort/align/gap/min/max/minSize/maxSize、幻影尖端) | `funnelAlign` 合并了两套词汇(有意偏差) |
| candlestick:OCLH、doji、自动布局、large、dataZoom 迷你图维度 | DONE | §58 渲染器(涨跌/doji/borderColorDoji);§95 数据阴影用 open;§143 barWidth/barMaxWidth/barMinWidth、containShape、subPixelOptimize、部分出界裁剪;§152 large 模式(三条按 sign 的路径) | 数据项自己的 itemStyle 颜色不读(§143);simple 模式(实体窄于 1.3px)不动画(§124);新来的 K 线更新直接到终值(§143);命中近似 zrender contain(§143) |
| boxplot + boxplot 统计变换 | DONE | §143 C1 渲染器、`prepareBoxplotData` 与 dataset transform `'boxplot'`、item tooltip、状态机、入场与更新 | emphasis 阴影不画(§143);visualMap 与逐数据取色不接,图例图标没按上游建模(§143);decal 不画(§167) |
| visualMap:连续 + 分段、8 通道、inRange/outOfRange、hoverLink、多边形条 | DONE | §88–§93(B1–B4):两种子类型的模型、编码、组件视图、color/opacity/hue/sat/light/alpha/symbol/symbolSize/liftZ 通道、梯形条;§112 sunburst;§151 C7 手柄拖动(calculable/realtime)、hover 指示器、双向 hoverLink、分段点击选中、selectDataRange、additive 动画;decal 通道上游本身不施加,端口照做(§88/§167,不算缺口) | 手柄标签的淡入淡出直接切(§151);不改光标、只认左键、不支持触摸(§151);indicatorStyle 阴影、`emphasis.handleStyle` 不读(§151) |
| 直角坐标热力图 | DONE | §102 H1 `BuildHeatmap`;§125 状态机;§135 tooltip;§154 渐进分块 | `encode` 改值列不支持;tooltip 维固定取第三个元素(§135);逐数据取色没接(§140) |
| effectScatter 涟漪 | DONE | §105 涟漪 number/brushType/showEffectOn;`Marks.pas:1631`;§127 涟漪循环动画(period/scale、相位、只剩循环时的持续层) | `showEffectOn: 'emphasis'` 的涟漪不启动(§127);持续阶段涟漪画在动态层、压在其它系列之上(z 序,§127) |
| pictorialBar:repeat 求解、symbolClip、symbolBoundingData、pxSign | DONE | §62 `Pictorial.pas`(四个矩形、repeat 两遍求解、clip、boundingData、镜像) | `image://` 符号画不出(画廊 forest/hill/spirit 为空);path:// 不能镜像;逐项 `[w,h]` symbolSize;`label.position: 'outside'`(§62/§70) |
| sunburst:径向细分、levels、下钻、算法配色阶梯、径向/切向标签 | DONE | §109 S1 布局/levels/配色/标签;§112 visualMap;§125 emphasis 的 ancestor/descendant 与 blur;§135 tooltip;§150 nodeClick 下钻、返回圆盘、sunburstRootToNode 与下钻过渡 | 入场与 setOption/图例/dataZoom 的更新不过渡(§150);`sunburstHighlight/Unhighlight` 旧动作没接(§150);decal 不画(§167) |
| treemap:squarified、面包屑、upperLabel、视觉子引擎、下钻 + 缩放 | PARTIAL | §110 squarify/面包屑(静态);§113 饱和度/upperLabel;§115 leafDepth、colorMappingBy、colorAlpha、rich 布局;§135 tooltip;§150 点击下钻、zoomToNode、叶根 rootToNode、面包屑点击、roam、悬停原地提亮与下钻过渡 | **emphasis/blur/select 声明的颜色、`emphasis.focus`(ancestor/descendant)、`emphasis.disabled` 不读**,不在共享状态模型上,悬停没有状态过渡(§150);面包屑不接悬停、不发鼠标事件(§150);标签 opacity(§113);没有 payload 的渲染(setOption、换主题)不过渡(§150);decal 不画(§167) |
| tree:Buchheim、径向、4 朝向、2 种边、展开收起 | DONE | §107 T1、§108 T2、§116 T3(点击、roam、hover、tooltip) | 跨系列 blurScope(§116);hover 放大时外侧标签不跟着动;命中半径 7.5 对上游 4.5 |
| sankey:分层、松弛、飘带、orient、节点拖动、focus trajectory | DONE | §114 K1 分层/松弛/飘带/两个方向/levels/渐变连线;§135 tooltip;§149 C5 节点拖动(dragNode)、状态机的两套行与 adjacency/trajectory、边标签、roam | highlight/downplay 只写 dataType 时什么都不做(§149);与关系图之间不互相淡化(§149);没有入场动画(§124);decal 不画(§167) |
| graph:none/circular/force、autoCurveness、边裁剪、categories、focus adjacency、节点拖动 | PARTIAL | §63–§66 布局/曲率/箭头/类别/直角坐标;§79 roam;§80 adjacency/blur;§149 C5 节点拖动(none/circular/force)、边标签、逐边宽度/类型/透明度/颜色/两端符号 | **节点的 `itemStyle.opacity`、节点自己的 `label` 不读**(§79/§80);力导向拖动按 `layoutAnimation: false` 的样子,节点不跟指针(§149);只拖 view 上的关系图(§149);`edgeLabel.rotate/offset` 不读(§149);不接共享状态模型(§149);没有入场动画(§124) |
| chord:环形布局、minAngle 借角求解、飘带、渐变飘带 | DONE | §155 C11 环形布局、minAngle 借角、飘带与渐变飘带、状态、tooltip、入场 | 更新不补间,直接跳到新形状(§155);连线的虚线、阴影、decal 不读(§155);标签模板的 `{@dim}` 不替换(§155) |
| singleAxis + themeRiver | DONE | §153 C10 单轴坐标系、轴与指示器、themeRiver、单轴上的散点/涟漪散点、dataZoom 目标、convertToPixel | 单轴上不建标注(§153);单轴上 inside dataZoom 的漫游不做(§153);themeRiver 更新不补间(§153) |
| 日历坐标系 + 日历热力图 | DONE | §103 H2 坐标系;§104 H3 热力图;§105/§106 日历上的 scatter/effectScatter/graph/pie | 用库的语言而不是图表 locale 取名字(§103);边距写成百分比字符串时不画 |
| View 坐标系 + RoamController(平移/缩放、scaleLimit、roamTrigger、preserveAspect、nodeScaleRatio) | DONE | §79 graph roam;§116 tree view/roam | 捏合缩放;`roamTrigger: 'selfRect'` 是近似;roam 动画;拖动后不抑制 click(§79);非均匀视图的箭头与线宽(§79) |
| brush:4 种形状、8 手柄 cover、inBrush/outOfBrush、brushLink、globalPan 互斥 | DONE | §162 C17 组件模型、4 种形状、8 手柄 cover、single/multiple、brush/brushEnd 动作;§163 C18 inBrush/outOfBrush 视觉、brushLink、brushselected、globalPan 互斥、toolbox 的 brush 按钮与预处理器;§166 平行轴上的逐轴刷选 | brushselected 的 `areas` 现在是模型区域的整个对象(§180);缺省的刷选颜色是皮肤的,事件里 brushStyle 的 fill / stroke 与上游令牌不同(同调色板,§180);覆盖框总在最上,不看 z(§162);样式只画填充/描边/线宽/不透明度(§162);geoIndex 等 D14;散点按未抖动的点选、极坐标柱不选(§163);非 96 PPI 不保证逐位(§162);导出时 `excludeComponents: ['brush']` 藏不掉框,与上游一致(不算缺口) |
| toolbox 原生工具条:saveAsImage、restore、框选 dataZoom、magicType、brush、自定义按钮 | DONE | §94 `toolbox.feature.dataZoom` 的 select 型 dataZoom 模型;§160 C16 原生工具条、saveAsImage、restore、dataZoom 选择与回退、magicType、自定义按钮、dataView 对话框;§163 brush 按钮 | `image://` 图标不画(§160);工具栏自己的 tooltip 不做(§160);dataView 是模态对话框,optionToContent/contentToOption 不支持(§160);magicType 只抄作者写的键(§160);`type: 'svg'` 存出来是 PNG(§160) |
| timeline 组件 | DONE | §165 C21 组件视图、播放/暂停/单步计时、`options` 各帧合并到 baseOption、autoPlay/loop/rewind、checkpoint 拖动、timelineChange/timelinePlayChange 动作 | 只有第一个时间线有视图(§165);刻度不是数据项,没有 tooltip 与图表鼠标事件(§165);标签的 `@Name` formatter、rich、overflow 不做(§165);`image://` 按钮与符号不画(§165) |
| 富文本引擎(`{name|content}`、逐片段盒子/图片/百分比宽度、lineOverflow) | DONE | §120 A4 引擎(切分、样式继承、片段量测与排版、truncate/lineOverflow、百分比宽度、wrapText);§121 A5 接到系列标签、标注、轴标签与轴名、标题、图例、仪表盘 | 图片背景没做(§120);`legend.data[i].textStyle`、`emphasis.label.rich` 不读(§121);矩形树图/旭日图/桑基图先截断再盖章,rich 标记会被当字截(§121);斜体画不出(§120) |
| Decal 图案 + aria 描述 | PARTIAL | §167 C22 decal 图案生成(LCM 平铺、旋转、6 种内置)、aria.decal 自动分配、柱/饼/漏斗/折线面积/图例图标上画出、aria 描述文字(`AriaDescription`);visualMap 的 decal 通道上游本身不施加,端口照做(§88/§167,不算缺口) | **雷达面积、桑基、旭日、矩形树图、K 线、箱线图、热力图、象形柱、custom、large 批量与渐进路径不画 decal**(§167);没写颜色的 decal 用皮肤键而不是黑色 20%(§167);描述交给 UIA/MSAA 归 D11 |
| `graphic` 覆盖组件 | DONE | §157 C13 元素类型、$action、变换、bounding、文字走富文本、拖动、过渡与离场 | clipPath、元素 tooltip、during 不做(§157/§177);拖动只平移、不发 ondrag 事件(§157);图片只认 `data:` URL(§157);z 映射成整数(§157) |
| SVG `path://` | DONE | §37 符号;§60 gauge 指针;§89/§95 手柄图标;`ZrPath.pas` | — |
| `custom` 系列 | DONE | §159 C14 `renderItem` 作 `@Name` 句柄、api.value/coord/size/style/visual/barLayout、元素复用 C13;§161 C15 极坐标/日历/单轴/'none' 上的 custom、enter/update 过渡、根上的 focus/blurScope、tooltipDisabled、`api.visual` 看得到 visualMap | geo(D14)、matrix(D12)上不画(§161);clipPath、autoBatch 不做(§161);关键帧已有(§177)、textContent 的淡入已有(§180),universal transition 不收 custom(§173);渐进渲染没有(§161);文字/图片元素的状态不做(§159);decal 不画(§167) |
| `large` 模式批量路径 + 算术命中扫描 | DONE | §152 C8 bar/line/scatter/candlestick 的批量路径、算术命中扫描、largeThreshold;§156 lines 的 large 批 | 极坐标、日历与 path:// 符号的 large 散点仍逐项画(§152);点 large 元素不派发 select(§152);柱的 30 ms throttle 不做(§152);阴影不画(§152) |
| 渐进 / 分块绘制 | DONE | §154 C9 按帧时间预算分块、progressiveThreshold/ChunkMode、增量图层(热力图、散点、柱、K 线、平行系列) | zlevel 分层不建(§154);rendered/finished 只在部分重绘时发(§154);lines、custom 没有渐进(§156/§161) |
| `appendData` 流式追加 | DONE | §154 C9 `AppendData` API,按冻结的直角坐标轴重画 | dataset 与 typed array 不收(§154);冻结范围只覆盖直角坐标轴,极坐标/日历/dataZoom 窗口不重算(§154);lines 的 appendData 没专门处理(§156) |
| lines 系列 | DONE | §156 C12 直角/极坐标/日历上的两点线与折线、端点符号、effect 与拖尾(motion blur 模拟)、large 批 | geo 上的 lines 等 D14(§156);渐进渲染没有(§156);effect 符号不是指针目标(§156);更新不补间(§156);曲线按 32 段折线近似(§156) |
| `convertToPixel` / `convertFromPixel` / `containPixel` 公开 API | DONE | §145 C2 `ConvertToPixel`/`ConvertFromPixel`/`ContainPixel` 与 finder;§146/§148/§153/§164 polar、单轴、parallel 的分派 | geo、matrix 的 finder 答不出(D14/D12);数组 finder 当找不到(§145) |
| 坐标轴附加:containShape、dataMin/dataMax、jitter(+ beeswarm)、customValues | DONE | §75 containShape;§67/§78 dataMin/dataMax;§145 jitter(beeswarm,固定种子 xorshift32)、axisLabel/axisTick 的 customValues;§152 large 散点的 jitter | resize 后不累积(上游越 resize 越散,§145);随机数是固定种子(§145);customValues 写成对象或串没有基准(§145) |
| labelLine 自动走线(nearestPointOnPath、limitTurnAngle、limitSurfaceAngle) | DONE | §138 LabelManager 布局;§144 饼求解器;§147 B14 nearestPointOnPath、limitTurnAngle、limitSurfaceAngle、smooth 与各状态,散点/涟漪散点/折线符号/直角坐标柱建线 | 热力图、象形柱、K 线、关系图、树、旭日、桑基、雷达、极坐标柱不建线(§147/§148);lineStyle 只读 color/width/opacity/type(§147);平滑线描入时画直的前缀(§147) |
| 饼图 avoidLabelOverlap 完整求解器 | DONE | §44 单个标签的外侧定位;`PieLabel.pas` 读了 alignTo/edgeDistance/bleedMargin/distanceToLabelLine;§144 B13 求解器(上下平移、椭圆重算 x、借空间、截断,先挪后藏) | `overflow: 'break'/'breakAll'` 不换行(§144);NaN 扇区与只在状态里显示的标签不进清单(§144);数据项级的 label/labelLine 不读(§144) |
| `endLabel` + `label.valueAnimation` | DONE | §127 AN4 末端标签(新元素,按裁剪前沿定位、值插值)与柱、仪表盘的 `label.valueAnimation`(上游也只有这两种);B15 没有单开批 | 状态里的 `endLabel.show`、富文本末端标签、阶梯线、单点折线不支持(§127);endLabel 不进 labelLayout 清单(§138);handler formatter、富文本、数组值不滚动(§127) |
| parallel + parallelAxis + 逐轴刷选 | DONE | §164 C19 parallel 坐标系、parallelAxis、系列、axisAreaSelect、axisExpandable 静态布局;§166 C20 逐轴刷选(areaSelectStyle、realtime、getCoverInfoList) | axisExpandable 的交互见 Tier 3(§178);更新不补间(§164);dataset 与 encode 不接(§164);轴颜色走皮肤、逐数据取色没接(§164) |

---

## Tier 3(23 行):DONE 10 · PARTIAL 7 · NOT STARTED 6

| 行 | 状态 | 证据 | 缺什么 |
|---|---|---|---|
| geo 坐标系(GeoJSON、区域命中、specialAreas、nameMap、boundingCoords、layoutCenter/Size、样式与选中) | NOT STARTED | `AdvanceChart.pas:5817` "polar, geo -- NOT PORTED";§33 | 全部(画廊 12 个) |
| map 系列 + 固定投影 | NOT STARTED | 只有注册 | 全部 |
| geo 上的热力图 | NOT STARTED | heatmap 注册时列了 geo,没有实现 | 全部 |
| `matrix` 坐标系 | NOT STARTED | `matrix` 的命中全是仿射矩阵;§101 matrix-stock 没画 | 全部(画廊 12 个) |
| `coordinateSystemUsage: 'box'` | PARTIAL | §106 pie 摆进日历格子(用 `coord` 或把 center 写成日期);§104–§106 系列落在日历格 | matrix 格子里的宿主;在格子里嵌坐标系或组件(grid/legend…) |
| 断轴(v6):分段映射、锯齿、刻度剪枝、展开收起动作 | PARTIAL | Tier 0 契约 ②:断轴 mapper 和 `test.advchart.scale.break`;§169 D1 `breaks` 接到 value / time 轴(解析、合并重叠、两种 gap)、随机锯齿与按断开 id 的缓存、刻度剪枝(两种模式)、nice 用扣掉断开的线性跨度、断开区与断开标签、展开 / 收起 / toggle 动作与 `axisbreakchanged`(上游基准 `advchart-axis-breaks.json`) | log 轴与 singleAxis 上的 `breaks`(上游有,端口不接);转了角度的断开标签不按 OBB 移开;断开区不参加过渡动画;formatter 与事件参数里没有 `break`(§169) |
| `realtimeSort` 柱状竞赛 | DONE | §172 D4 `realtimeSort` 与类目轴的 `categorySortInfo`(刻度 ↔ 序号双向映射)、`rendered` 里的次序检查与 `changeAxisOrder` 动作 / 事件、初次排序与后续排序的两种过渡、竞赛柱裁剪后留着 `ignore`、标签计数接着走(上游基准 `advchart-realtime-sort.json`) | 被覆盖的旧 `rendered` 监听不另算;竞赛轴上的 dataZoom、notMerge / replaceMerge 下的第一帧没有基准;查次序的时机按端口的绘制(§172) |
| Universal transition + 形状变形 | PARTIAL | §173 D5 UT1 形状变形引擎(`Morph.pas`:贝塞尔化、对齐、旋转搜索、`split` / `clone`、hilbert 排序)与一对一过渡;§175 UT2 合并 / 拆分、`groupId` / `dataGroupId`、`divideShape`、`delay(index, count)`、列表键;§176 UT3 `childGroupId` 与方向嗅探、编码维度、多层钻取、树图 ↔ 旭日图;§180 下钻后的旭日图从数据仍记着的扇区出发(上游基准 `advchart-universal-transition*.json`) | **只有柱、饼扇区、散点 / 折线符号、树图、旭日图进变形**,批里有 custom、漏斗、极坐标柱、象形柱等就整批不做(§173);标签不跟变形帧走(§173);同类型的树图 / 旭日图批不做,旭日图重设颜色没有样式过渡(§176);setOption 的 `transition` 参数没有(§173/§176) |
| `keyframeAnimation` + 过渡小语言 | DONE | §177 D6 graphic 与 custom 元素的 `keyframeAnimation`(百分比、缓动、循环、延迟、离散键、恢复)、`transition` / `enterFrom` / `leaveTo` 写在 style / shape / extra 上、`enterAnimation` / `updateAnimation` 的 additive;§180 custom textContent 入场淡入(上游基准 `advchart-keyframe-animation.json`) | `during` 不做;clipPath 的关键帧随 clipPath 没有;被停光的动画器端口释放(§177) |
| 叠加动画 | DONE | §151 引擎的 additive(`TTyAnimCfg.Additive`、轨道 `AddValue`、`GetAdditiveTrack`),visualMap 连续型指示器在用;§177 graphic / custom 的 `updateAnimation.additive` 与关键帧 | — |
| `thumbnail` 小地图 | DONE | §178 D7 graph 的缩略图:框与内容框、副本、窗口、拖动平移与滚轮缩放、跟着 graph 的 roam(上游基准 `advchart-thumbnail-axisexpand.json`) | 盒子放在 calendar / matrix 上没做;双指缩放、光标、缩略图元素的鼠标事件不做;副本的缺省颜色是皮肤的(§178) |
| parallel `axisExpandable` 鱼眼 | DONE | §164 静态布局(窗口、折起的轴、藏标签、截名称);§178 D7 `axisExpandTriggerOn` 的点击 / 移动、滑动与跳转、`parallelAxisExpand` 动作与事件、节流 / 防抖 | 展开不补间(§164/§178);多个 parallel 共用一个窗口数组时各自一份(§178) |
| `axisPointer.link` + mapper | DONE | §179 D8 按 index / id / name 与 `'all'` 分组、mapper 句柄、目标不吸附、分组次序;§180 补了同一网格里两根 x 轴、多个源、与极坐标重叠的用例,吸附只吸到轴上的值(上游基准 `advchart-connect-link-batch.json`) | 候选轴只有 tooltip 轴(上游还收 `axisPointer.show` 的轴);`triggerEmphasis` 不读;mapper 返回不了类目名(§179) |
| 跨控件联动 + 组合导出 | PARTIAL | §179 D8 `Group`、`TyChartConnect` / `TyChartDisconnect`、事件 → 动作的转发与挂起、`escapeConnect`、silent、组合导出(`GetConnectedDataURL`、saveAsImage);§180 resize 与时间线的更新带上 brushSelect | **tooltip 与指示器不跨图联动**(`updateAxisPointer` / `showTip` / `hideTip` 三个动作与事件没有,见 D8b);组合导出按整像素贴图、没有 SVG(§179) |
| dataset transform 管线(filter DSL、sort、管道、多输出) | DONE | `Dataset.pas` 头注释;§47;§143 数据集串联(fromDatasetIndex/Id、fromTransformResult)、管道、多输出、`'boxplot'` 变换(`TTyDatasetCache`);§170 D2 transform 注册表、filter 条件语言(and / or / not、六种比较、parser)、sort(V8 TimSort 逐位、incomparable)、维度名去重、上游抛错的写法给诊断 `dataset[%d] has no table`(上游基准 `advchart-dataset-transform.json`) | `reg` 运算符照路线图不做;上游整次 `setOption` 失败处端口只让相关数据集没有表;`print` 不做(§170) |
| 统计变换:回归、k-means、直方图 | DONE | §171 D3 `ecStat:regression`(linear / exponential / logarithmic / polynomial,公式与 formulaOn)、`ecStat:histogram`(squareRoot / scott / freedmanDiaconis / sturges)、`ecStat:clustering`(二分 k-means,随机数接图表的流)(上游基准 `advchart-stat-transforms.json`) | 不用 `registerTransform` 就有;只认 JSON 的数(ecStat 的 `isNumber` 放过数字串);迭代、阶数、刻度数有上限;toFixed 只到 20 位(§171) |
| `setOption` 式 option 树 + normal/replace 合并 | DONE | Tier 0 第 4 项:宽松 JSON 树 + 整体替换(notMerge,`Option.pas:17-21`);§79 resize 与重设保留 roam;§130 A10 `MergeOption`/`SetOption` 的 normalMerge(id/name/索引)、完全相同文本的语义、`GetOptionJson`;§132 A11 replaceMerge、索引空洞、选项对象形式与 updated 事件;§142/§160/§165 media、toolbox restore/magicType、timeline 走合并 | 整份的 replaceAll(`resetOption('recreate')`)不单独提供(§132);`GetOptionJson` 是原始合并层(§130);重复 id 的合并整个不生效(§130);未知系列类型照常占位置(§130) |
| 事件的查询过滤 | DONE | §119 A3 字符串与对象查询(ECEventProcessor 规则)、`ChartOn`/`ChartOff` 去重 | — |
| 粗指针命中回退 | NOT STARTED | — | 全部 |
| 脏矩形 / 缓存表面绘制 | PARTIAL | Q7 静态层缓存 `TTyPaintCache` + `InvalidateFrame` 已落地(一帧 1.18 ms) | 脏矩形(Q7 定为 Tier 3,只有像素成为瓶颈时才做) |
| 批量动作 + 细化事件 | PARTIAL | §151 highlight/downplay 的 `batch` 与 `{type, batch:[…]}` 事件;§163 brushselected 的批载荷;§132 updated;§154 rendered/finished;§179 select 三个、图例五个、dataZoom、brushSelect 的 batch,`DispatchAction(json, silent)`;§180 批项读自己的 type | 其余动作带 batch 仍答 False(§179);rendered/finished 不是每次重绘都发(§154);挂起动作只有 brushSelect 建了模(§179) |
| 设计期:系列/数据编辑对话框、属性编辑器、组件编辑器动词 | PARTIAL | `designtime/tyControls.Design.AdvChart.Editor.pas`:Option 的 SynEdit 编辑器(补全、参考树、诊断)+ `TComponentEditor` 动词 + `RegisterPropertyEditor`(Tier 0 第 6 项) | 结构化的系列/数据编辑对话框(`Values` 属性编辑器在 option 树 API 下已经不适用) |
| 键盘导航 + MSAA/UIA | NOT STARTED | 控件是 `TabStop := False`(§96 有意为之);§167 的 `AriaDescription` 已能给出描述文字 | 全部(UIA/MSAA 可以接 §167 的描述) |

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
| D1 | **[PARTIAL,第 132 批 §169;log 轴与 singleAxis 的断开未接]** 断轴:`breaks` 接到已有 mapper、随机锯齿缓存、刻度剪枝、nice 扣除断开区间、展开收起动作 | 3 | — |
| D2 | **[DONE,第 133 批 §170]** dataset transform:注册表、filter DSL(不含 reg)、sort、管道、多输出 | 3 | — |
| D3 | **[DONE,第 134 批 §171]** 统计变换:回归 4 种、k-means、直方图 4 种分箱 | 3 | D2 |
| D4 | **[DONE,第 135 批 §172]** realtimeSort 柱状竞赛 | 2–3 | A8 |
| D5 | **[PARTIAL,第 136–138 批 §173、§175、§176,里程碑 §180;只有柱、扇区、符号、树图、旭日图进变形]** universalTransition(UT1–UT3:dividePath/combine/separate 变形、groupId 方向嗅探) | 3×3 | A8 |
| D6 | **[DONE,第 139 批 §177]** keyframeAnimation + 过渡小语言、叠加动画 | 3 | A8, C13 |
| D7 | **[DONE,第 140 批 §178]** thumbnail 小地图;parallel axisExpandable | 3 | C19 |
| D8 | **[PARTIAL,第 141 批 §179;tooltip 与指示器的跨图联动拆到 D8b]** axisPointer.link + mapper;跨控件联动(共享控制器)+ 组合导出;批量动作 | 3 | B1, B11 |
| D8b | **[新增,里程碑 §180]** connect 组里的 tooltip / 指示器联动:`updateAxisPointer`(载荷的 `axesInfo` 限定轴与值、`currTrigger`、`x` / `y`)、`showTip`(按 `seriesIndex` + `dataIndex`、按 `x` / `y`、按 `axesInfo` 定位,`findPointFromSeries`)、`hideTip` 三个动作与它们的事件,指针由鼠标驱动改成由载荷驱动,tooltip 视图的 manualShowTip / manualHideTip | 2–3 | D8 |
| D9 | 粗指针命中回退 + 脏矩形 | 2–3 | — |
| D10 | 设计期的系列/数据结构化编辑对话框 | 3 | — |
| D11 | 键盘导航 + UIA/MSAA(接 aria 描述) | 3 | B1, C22 |
| D12 | matrix 坐标系(MX1–MX3:树形表头、定位代数、合并单元格) | 3×3 | — |
| D13 | coordinateSystemUsage 'box':matrix/日历格子里嵌坐标系和组件 | 3×2 | D12 |
| D14 | geo(GE1–GE4):GeoJSON 解析 + registerMap、投影接口、区域绘制/命中/选中、roam、map 系列、geo 上的 scatter/lines/heatmap | 3×4 | C12 |

合计约 70 批。阶段 A(11 批,约 28 天)是后面几乎所有交互和视觉行的前置:A1/A3 解锁事件、图例、tooltip;A4/A5 解锁时间轴格式、graphic、标注富文本;A6–A9 解锁 valueAnimation、realtimeSort、universalTransition、涟漪、loading、progressive;A10 解锁 media、timeline、toolbox。

如果按画廊的覆盖收益,而不是按地基先行来排:A1 → A2 → A3 → B3(图例点击)→ B1/B2(状态,emphasis 72、focus 37)→ A4/A5(rich 12)→ C16(toolbox 37)→ C3/C4(polar 11)→ C14(custom 13)→ A6–A9(动画)。
