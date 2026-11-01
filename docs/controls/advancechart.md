# TTyAdvanceChart — API 参考

## 1. 概述

`TTyAdvanceChart` 照 Apache ECharts 6.1 的 option 画图。配置就是 ECharts 的 option，写成 JSON 文本放进 `Option` 属性。ECharts 的配置项手册、示例和网上的现成答案都能直接用。

- 系列：折线、柱、饼、散点、涟漪散点、K 线、箱线、热力图、雷达、仪表盘、漏斗、象形柱、主题河流、平行坐标、关系图、和弦、树图、矩形树图、旭日图、桑基图、地图、lines、自定义系列。
- 组件：标题、图例、提示框、轴指示器、dataZoom、visualMap、toolbox、刷选、时间线、graphic、dataset、标注（markPoint / markLine / markArea）、日历、matrix、缩略图、无障碍描述（aria）。
- 动画、合并更新、动作（dispatchAction）、事件、联动（connect）、导出图片都照 ECharts 的行为。

行为是逐项对着 ECharts 核对的：同一份 option 在 node 里跑真的 ECharts 6.1，取出布局、颜色、事件和动画的数值，再和本控件的结果比。和 ECharts 不一样的地方列在第 12 节。

坐标轴、文字、提示框等的颜色和字体取当前皮肤，换肤时图表跟着变。

`examples/advchart` 载入了 ECharts 官方示例库的 244 个配置，右侧可以直接改配置重画。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.AdvanceChart`（控件）；`tyControls.AdvanceChart.Handlers`（formatter 等注册表、`TTyChartParams`）、`tyControls.AdvanceChart.Events`（`TTyChartEvent`、元素处理器）、`tyControls.AdvanceChart.Geo`（地图、投影）、`tyControls.AdvanceChart.Images`（图像列表） |
| 类 | `TTyCustomAdvanceChart`（全部实现，不发布属性）；`TTyAdvanceChart`（组件面板上的类，只发布属性） |
| 基类 | `TTyCustomControl`（窗口化，可获得焦点） |
| 默认尺寸 | 320 × 200（逻辑像素） |
| 组件面板 | `TyControls Shapes & Charts` |
| typeKey | `TyAdvChart`（图表底与外框，和 `TyPanel` 同一个规则块） |

```pascal
uses tyControls.AdvanceChart;
```

### 子部件的主题键

图表各部分有自己的键，都在 `themes/light.tycss` 里，其他主题继承。常用的几组：

| 键 | 画什么 |
|----|--------|
| `TyAdvChartSeries1` … `TyAdvChartSeries9` | 缺省调色板（option 没写 `color` 时用），都从 `--accent` 算出来 |
| `TyAdvChartTitle`、`TyAdvChartSubtitle` | 主标题、副标题 |
| `TyAdvChartAxisLine`、`TyAdvChartAxisTick`、`TyAdvChartMinorTick`、`TyAdvChartAxisLabel`、`TyAdvChartAxisName`、`TyAdvChartSplitLine`、`TyAdvChartMinorSplitLine`、`TyAdvChartSplitArea` | 坐标轴各部分 |
| `TyAdvChartLabel`、`TyAdvChartLabelOnLight`、`TyAdvChartLabelOnMid`、`TyAdvChartLabelOnDark` | 图形外的标签；图形里的标签按底色深浅分三档 |
| `TyAdvChartTooltip`、`TyAdvChartTooltipValue` | 提示框 |
| `TyAdvChartAxisPointer`、`TyAdvChartAxisPointerLabel`、`TyAdvChartAxisPointerShadow` | 轴指示器 |
| `TyAdvChartLegend*` | 图例（文字、未选中、翻页、选择器按钮） |
| `TyAdvChartDataZoom*`、`TyAdvChartVisualMap*`、`TyAdvChartToolbox*`、`TyAdvChartTimeline*`、`TyAdvChartBrush*` | 各组件 |
| `TyAdvChartLoading`、`TyAdvChartLoadingSpinner` | 加载遮罩 |
| `TyAdvChartFocusItem` | 键盘焦点框 |

完整列表用 `grep TyAdvChart themes/light.tycss` 看。

尺寸令牌（逻辑像素）：

| 令牌 | 缺省 | 作用 |
|------|------|------|
| `--advchart-tick-length` | 5 | 刻度长 |
| `--advchart-minor-tick-length` | 3 | 次刻度长 |
| `--advchart-single-tick-length` | 6 | 单轴刻度长 |
| `--advchart-label-margin` | 8 | 轴标签与轴的距离 |
| `--advchart-name-gap` | 15 | 轴名与轴的距离 |
| `--advchart-axispointer-margin` | 3 | 轴指示器标签与轴的距离 |
| `--advchart-tooltip-gap` | 20 | 提示框与指针的距离 |
| `--advchart-tooltip-marker` | 10 | 提示框里的色点 |
| `--advchart-tooltip-marker-gap` | 6 | 色点与文字的距离 |
| `--advchart-tooltip-gutter` | 20 | 提示框里名字列与数值列的间隔 |

option 里明写的颜色、字号优先于皮肤。

---

## 3. 用法

### 最小例子

```pascal
uses tyControls.AdvanceChart;

var
  Chart: TTyAdvanceChart;
begin
  Chart := TTyAdvanceChart.Create(Self);
  Chart.Parent := Surface;
  Chart.Align := alClient;
  Chart.Option :=
    '{' +
    '  xAxis: { type: "category", data: ["一月", "二月", "三月"] },' +
    '  yAxis: { type: "value" },' +
    '  tooltip: { trigger: "axis" },' +
    '  series: [{ type: "bar", data: [120, 200, 150] }]' +
    '}';
end;
```

`Option` 读的是宽松 JSON：键可以不加引号，字符串可以用单引号，可以有多余的逗号和注释。ECharts 示例里的配置一般能原样贴进来。配置里有 JS 函数时解析会失败，`OptionError` 会提示改写成模板或 `'@名字'`（第 6 节）。

文本解析不了时图表是空的，`OptionError` 写着原因。配置能解析、但有画不了的部分（拼错的轴类型、指向不存在的轴等）时，图照画，问题列在 `Diagnostic` 里。设置配置后就能读，不用等画出来（控件要已经有大小）：

```pascal
for i := 0 to Chart.DiagnosticCount - 1 do
  Memo1.Lines.Add(Chart.Diagnostic(i));
```

### 设置、合并、读回

| ECharts | 本控件 |
|---------|--------|
| `setOption(option)` | `MergeOption(AJson): Boolean`，或 `SetOption(AJson)` |
| `setOption(option, true)`（notMerge） | `SetOption(AJson, True)`，或给 `Option` 赋一段不同的文本 |
| `setOption(option, {replaceMerge, lazyUpdate, silent, transition})` | `SetOption(AJson, AOptsJson: string): Boolean`，或 `SetOption(AJson, AOpts: TTySetOptionOpts): Boolean` |
| `getOption()` | `GetOptionJson: string`；`Option` 属性合并后也读出合并后的树 |
| `resize()` | 不用调，控件尺寸变了自己重排，media 查询也重新判断 |

```pascal
// 只换第一个系列的数据，其余设置、图例选择、缩放窗口都留着
Chart.MergeOption('{ series: [{ data: [80, 90, 100] }] }');

// 整个替换
Chart.SetOption(NewText, True);

// 按 id 替换系列，没对上 id 的系列删掉
Chart.SetOption(NewText, '{"replaceMerge": ["series"]}');
```

几条规则：

- `Option` 是声明式的：赋同样的文本什么都不发生，赋不同的文本等于 notMerge。
- 合并失败（文本解析不了、同一类组件两个相同 id）时 `MergeOption` 答 False，图和配置都不变，`OptionError` 写着原因。
- `GetOptionJson` 是作者写的配置合并后的样子，不带主题和缺省值。组件的 id 用 `ComponentModelId(主类型, 序号)` 取。

### 动作

```pascal
Chart.DispatchAction('{"type": "highlight", "seriesIndex": 0, "dataIndex": 2}');
Chart.DispatchAction('{"type": "showTip", "seriesIndex": 0, "dataIndex": 2}');
Chart.DispatchAction(Payload, True);   // 第二个参数 True = silent，不发事件
```

ECharts 的动作都认：`highlight` / `downplay`、`select` 一组、`legend*`、`showTip` / `hideTip`、`dataZoom`、`brush*`、`timelineChange`、`geoRoam`、`treemap*`、`sunburstRootToNode`、`restore` 等。高亮、选择、图例、`dataZoom`、`brushSelect` 可以写成 `batch`。类型不认识或载荷不是对象时答 False。

只调 dataZoom 时还有一个省事的写法：`DispatchDataZoom(序号, 起始百分比, 结束百分比)`。

### 追加数据

```pascal
Chart.AppendData(0, '[[10, 20], [11, 25], [12, 18]]');
```

对应 `appendData({seriesIndex, data})`。追加的数据在下一帧画上，坐标轴范围保持上一次更新时的样子，和 ECharts 一样。系列不存在、数据不是数组时答 False。

### 导出图片

| 方法 | 说明 |
|------|------|
| `SaveToPng(AFileName)` | 按当前尺寸存 PNG |
| `SaveToFile(AFileName, AOptsJson = '')` | 格式取 `AOptsJson` 的 `type`，没写就看扩展名（`.jpg` / `.jpeg` / `.webp`），否则 PNG |
| `SaveToStream(AStream, AOptsJson = '')`、`SaveToBytes(AOptsJson = '')` | 写进流 / 字节数组 |
| `GetDataURL(AOptsJson = '')` | `data:image/png;base64,...` |
| `RenderToBitmap(AOptsJson = '')` | 不编码的 `TBGRABitmap`，调用方释放 |
| `SaveConnectedToFile` 等 | 联动组里所有图拼成一张（`getConnectedDataURL`） |

`AOptsJson` 就是 ECharts 的导出参数：`type`（`png` / `jpeg` / `webp`）、`pixelRatio`、`backgroundColor`、`excludeComponents`。

- 导出的是画完的图：动画按终态画，鼠标悬停出来的提示框不在图里。
- 没写背景色时用皮肤的底色。要透明写 `backgroundColor: 'transparent'`。
- WebP 要系统里有 libwebp，没有时写出来的是 PNG。

```pascal
Chart.SaveToFile('sales.png', '{"pixelRatio": 2}');
```

### 加载遮罩

```pascal
Chart.ShowLoading('{"text": "加载中…"}');
...
Chart.HideLoading;
```

参数同 ECharts 的 `showLoading('default', opts)`。颜色和字体没写时取皮肤。遮罩显示时，它下面的图形不响应悬停和点击；`zlevel` 比遮罩高的图形画在遮罩上面，照常响应（遮罩的 `zlevel` 缺省 0）。

### 联动

```pascal
Chart1.Group := 'sales';
Chart2.Group := 'sales';
TyChartConnect('sales');        // echarts.connect('sales')
TyChartDisconnect('sales');
```

也可以直接传一组图：`TyChartConnect([Chart1, Chart2])`，返回组名。

### 坐标换算与命中

| ECharts | 本控件 |
|---------|--------|
| `convertToPixel(finder, value)` | `ConvertToPixel(AFinderJson, AValueJson): string`，另有 Double 参数的重载 |
| `convertFromPixel(finder, pixel)` | `ConvertFromPixel(...)` |
| `containPixel(finder, point)` | `ContainPixel(...)` |
| `convertToLayout` | `ConvertToLayout(...)` |
| 鼠标下是哪个数据 | `HitTestAt(X, Y): TTyChartDatumRef`，没有时 `SeriesIndex` 为 -1 |

坐标都是控件客户区的设备像素。

---

## 4. 属性

### published

| 属性 | 类型 | 缺省 | 说明 |
|------|------|------|------|
| `Option` | `string` | `''` | ECharts option 的 JSON 文本 |
| `OptionError` | `string` | `''` | 只读。上一次设置失败的原因，成功时为空 |
| `AnimationMode` | `TTyChartAnimationMode` | `camAuto` | 入场动画什么时候播。`camAuto`：画到屏幕上时播，导出、设计期不播；`camAlways`：每次都播；`camOff`：不播 |
| `Group` | `string` | `''` | 联动组名，对应 `chart.group`；空串表示不在组里 |
| `CoarsePointer` | `TTyChartCoarsePointer` | `ccpAuto` | 粗指针（`useCoarsePointer`）。指针下没有图形时在周围找近的。`ccpAuto` 在桌面平台上是关的，`ccpOn` / `ccpOff` 强制 |
| `PointerSize` | `Integer` | `44` | 粗指针的搜索范围（逻辑像素），0 = 关 |
| `UseDirtyRect` | `Boolean` | `False` | 对应 `useDirtyRect`：只重画变了的区域 |
| `ExactRendering` | `Boolean` | `False` | False 时细线（不到 1 个设备像素）和标签描边用快速画法，长细线快十倍以上；True 时逐像素照浏览器 canvas 的画法 |
| `TabStop` | `Boolean` | `False` | 设成 True 才能用键盘操作图表（第 9 节） |

另发布 `StyleClass` / `StyleOverride` / `Controller`、`Align` / `Anchors` / `BorderSpacing` / `Constraints`、`Color` / `Font` / `ParentFont`、`Enabled` / `Visible` / `PopupMenu` / `TabOrder` 及 `TTyCustomControl` 的基线事件，见 [../events.md](../events.md)。

### public

| 成员 | 说明 |
|------|------|
| `TooltipAutoRichText: Boolean` | 缺省 False：`renderMode` 为 `auto` 时，formatter 返回的文本按 HTML 读，和浏览器里一样。True 时按 richText 读（node 里的行为），标记原样显示 |
| `LoadingShown: Boolean` | 加载遮罩是否显示中 |
| `AriaDescription: string` | 按 `aria` 配置生成的图表描述，`aria` 没开时为空 |
| `DiagnosticCount` / `Diagnostic(i)` | 配置里画不了的部分。设置配置后马上能读：画过的图按上次的尺寸重新排版，没画过的按控件当前的大小和 `Font.PixelsPerInch` 先排一次（之后的第一次绘制不再重排）。控件还没有大小时为 0 |
| `ToolboxError: string` | 工具栏操作（数据视图 Refresh 等）的出错原因 |
| `InvalidateFrame` | 只重画动态层（提示框、指示器等），不重建 |
| `ForgetResolvedImages` | 清掉 `OnResolveImage` 给过的图片，下次重新问 |

---

## 5. 事件

### 图表事件

ECharts 的 `chart.on` / `chart.off` 对应 `ChartOn` / `ChartOff`，另有一个收全部事件的 `OnChartEvent`。

```pascal
uses tyControls.AdvanceChart.Events;

procedure TForm1.BarClick(Sender: TObject; const AEvent: TTyChartEvent);
begin
  ShowMessage(AEvent.Params.Name + ': ' + AEvent.Params.ValueText);
end;

FClickId := Chart.ChartOn('click', @BarClick, 'series.bar');
...
Chart.ChartOff(FClickId);
```

| 成员 | 说明 |
|------|------|
| `ChartOn(AType, AHandler, AQuery = ''): Integer` | 注册，返回 id；图表不发的类型返回 -1。`AQuery` 可以是空、`'series.bar'` 这样的类型，或 `'{"seriesIndex": 1}'` 这样的 JSON。查询只过滤鼠标事件，动作事件和渲染事件不受查询影响（和 ECharts 一样） |
| `ChartOff(AId)` | 注销 |
| `OnChartEvent` | 每个鼠标事件和动作事件都会到这里，不过滤 |

处理器签名：`procedure(Sender: TObject; const AEvent: TTyChartEvent) of object`。

`TTyChartEvent` 的字段：

| 字段 | 说明 |
|------|------|
| `EventType` | 小写的事件名，如 `'click'` |
| `HasParams` / `Params` | 鼠标事件的参数（`TTyChartCallbackParams`：`SeriesIndex`、`SeriesName`、`DataIndex`、`RawDataIndex`、`Name`、`Values`、`ValueText`、`Color`、`ComponentType` 等，同 ECharts 的 params） |
| `HasOffset` / `OffsetX` / `OffsetY` | 指针位置，客户区像素；`globalout` 没有 |
| `Payload` | 动作事件的对象，JSON 文本；鼠标事件为空 |

`ChartOn` 认 ECharts 的 `chart.on` 能收到的所有类型（大小写不限，按小写比较）：

- 鼠标：`click`、`dblclick`、`mousedown`、`mouseup`、`mousemove`、`mouseover`、`mouseout`、`globalout`、`contextmenu`
- 选择与高亮：`select`、`unselect`、`toggleselect`、`selectchanged`、`highlight`、`downplay`，以及旧式的 `pieselectchanged`、`pieselected`、`pieunselected`、`mapselectchanged`、`mapselected`、`mapunselected` 和 `pietoggleselect`、`pieselect`、`pieunselect`、`maptoggleselect`、`mapselect`、`mapunselect`
- 图例：`legendselectchanged`、`legendselected`、`legendunselected`、`legendselectall`、`legendinverseselect`、`legendscroll`
- 缩放、提示框、指示器、工具栏：`datazoom`、`showtip`、`hidetip`、`updateaxispointer`、`restore`、`magictypechanged`、`dataviewchanged`、`globalcursortaken`
- 刷选与平行坐标：`brush`、`brushend`、`brushselected`、`axisareaselected`、`parallelaxisexpand`
- 系列：`dragnode`、`graphroam`、`treeroam`、`sankeyroam`、`treeexpandandcollapse`、`focusnodeadjacency`、`unfocusnodeadjacency`、`sunburstroottonode`、`sunbursthighlight`、`sunburstunhighlight`、`treemapzoomtonode`、`treemaproottonode`、`treemapmove`、`treemaprender`、`changeaxisorder`
- 其他组件：`geoselectchanged`、`geoselected`、`geounselected`、`georoam`、`datarangeselected`、`timelinechanged`、`timelineplaychanged`、`axisbreakchanged`
- 渲染：`updated`、`rendered`、`finished`

动作事件的 `Payload` 是 ECharts 交给处理函数的那个对象（动作载荷的副本，`type` 换成小写的事件名）。拖动、滚轮漫游关系图 / 树图 / 桑基图，点击展开树图节点，缩略图拖动，都会发出对应的动作事件，和 ECharts 一样。`expandaxisbreak`、`collapseaxisbreak`、`toggleaxisbreak` 只在联动内部使用，ECharts 不交给 `chart.on`，这里也返回 -1；断轴的公开事件是 `axisbreakchanged`。

### 专有事件

| 事件 | 签名 | 触发时机 |
|------|------|----------|
| `OnChartEvent` | `(Sender; const AEvent: TTyChartEvent)` | 见上 |
| `OnDataZoom` | `(Sender; const AAction: TTyDzAction)` | 每次 dataZoom 动作，不管来自拖动、滚轮、工具栏还是代码 |
| `OnGraphRoam` | `(Sender; const APayload: TTyGraphRoamPayload)` | 关系图平移、缩放 |
| `OnTreeRoam` | 同上 | 树图平移、缩放 |
| `OnSankeyRoam` | 同上 | 桑基图平移、缩放 |
| `OnTreeExpandAndCollapse` | `(Sender; ASeriesIndex, ADataIndex: Integer)` | 树图节点展开或收起 |
| `OnToolboxSaveAsImage` | `(Sender; var AFileName: string; const AOptsJson: string; var AHandled: Boolean)` | 点工具栏的「保存为图片」。`AHandled := True` 表示自己处理了，不弹保存对话框 |
| `OnDataViewContent` | `(Sender; const AOptionJson: string; var AContent: TTyChartDataViewContent; var AHandled: Boolean)` | 数据视图打开时，代替 `optionToContent`（第 8 节） |
| `OnDataViewApply` | `(Sender; const AContent: TTyChartDataViewContent; const AOptionJson: string; var ANewOption: string; var AHandled: Boolean)` | 数据视图点 Refresh 时，代替 `contentToOption`（第 8 节） |
| `OnResolveImage` | `(Sender; const AUrl: string; var AImage: TBGRABitmap)` | 配置里有图表自己取不到的图片（第 7 节） |
| `OnTooltipHtml` | `(Sender; const AHtml: string; const AInk: TTyTooltipInk; var ALines: TTyTooltipLineArray; var AHandled: Boolean)` | 提示框要画一段 HTML 时。不处理就用内置的读法 |

`TTyDzAction` 在 `tyControls.AdvanceChart.DataZoomAct`，`TTyGraphRoamPayload` 在 `tyControls.AdvanceChart.Graph`，`TTyTooltipInk` / `TTyTooltipLineArray` 在 `tyControls.AdvanceChart.Tooltip`，`TTyChartDataViewContent` 在 `tyControls.AdvanceChart.Handlers`。

---

## 6. 函数型选项

ECharts 里很多选项可以写成 JS 函数（`formatter`、`symbolSize`、`renderItem` 等）。option 是文本，放不下函数，所以有两种写法：

- 模板字符串：`formatter: '{b}: {c} ({d}%)'`，和 ECharts 一样，不用注册。
- 具名处理器：`formatter: '@Money'`，在 Pascal 里用对应的 `TyChartRegister*` 注册一个叫 `Money` 的方法，图表画的时候调它。

```pascal
uses tyControls.AdvanceChart.Handlers;

function TForm1.Money(const AParams: TTyChartParams): string;
begin
  Result := AParams[0].Name + ': ' + FormatFloat('#,##0.00', AParams[0].Values[0]);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  TyChartRegisterFormatter('Money', @Money);
  Chart.Option := '{ ..., series: [{ type: "bar", data: [1200.5, 980],' +
    ' label: { show: true, formatter: "@Money" } }] }';
end;
```

注册表是全局的，所有图表共用。注册时名字不带 `@`；同名再注册会替换旧的；每个都有对应的 `TyChartUnregister*`。配置里写了没注册的名字，formatter 会显示一行提示，其他处理器按 ECharts 里「不是函数」的情况处理。

| 注册函数 | 单元 | 用在哪些选项 | 处理器签名 |
|----------|------|--------------|------------|
| `TyChartRegisterFormatter` | `.Handlers` | 各处的 `formatter`、`valueFormatter`，dataZoom 的 `labelFormatter` | `function(const AParams: TTyChartParams): string of object` |
| `TyChartRegisterVisualHandler` | `.Handlers` | 系列和标注的 `symbol`、`symbolSize`、`symbolRotate`、`symbolOffset`，`itemStyle.color` | `function(const AParams: TTyChartCallbackParams): TJSONData of object`（返回值由调用方释放，nil 表示 undefined） |
| `TyChartRegisterPositionHandler` | `.Handlers` | `tooltip.position` | `function(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos of object` |
| `TyChartRegisterLabelLayoutHandler` | `.Handlers` | 系列的 `labelLayout` | `function(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout of object` |
| `TyChartRegisterToolboxHandler` | `.Handlers` | 自定义工具 `toolbox.feature.myXxx.onclick` | `procedure(ASender: TObject; const AFeature, AIcon: string) of object` |
| `TyChartRegisterOptionToContent` | `.Handlers` | `toolbox.feature.dataView.optionToContent` | `function(const AOption: string): TTyChartDataViewContent of object` |
| `TyChartRegisterContentToOption` | `.Handlers` | `toolbox.feature.dataView.contentToOption` | `function(const AContent: TTyChartDataViewContent; const AOption: string): string of object` |
| `TyChartRegisterAxisPointerMapper` | `.Handlers` | `axisPointer.link[i].mapper` | `function(AValue: Double; const ASource, ATarget: TTyChartMapperAxis): Double of object` |
| `TyChartRegisterElementHandler` | `.Events` | graphic 元素的 `onclick`、`onmouseover`、`ondrag` 等 | `function(Sender: TObject; const AEvent: TTyChartElementEvent): Boolean of object`（True 停止冒泡） |
| `TyChartRegisterRenderItem` | `.Custom` | 自定义系列的 `renderItem` | `function(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData of object` |
| `TyChartRegisterDuring` | `.GfxEl` | graphic 和自定义系列元素的 `during` | `procedure(AApi: TTyGfxDuringApi) of object` |
| `TyChartRegisterAnimTiming` | `.AnimOpt` | `animationDuration`、`animationDelay` 及其 `Update` 版本 | `function(ADataIndex: Integer; AHasIndex: Boolean): Double of object` |
| `TyChartRegisterAnimDelay` | `.AnimOpt` | 需要第二个参数的 `animationDelay`（同名时先于上一行） | `function(ADataIndex: Integer; AHasIndex: Boolean; const AParams: TTyAnimDelayParams): Double of object` |
| `TyChartRegisterUtDelay` | `.AnimOpt` | `universalTransition.delay` | `function(AIndex, ACount: Integer): Double of object` |
| `TyChartRegisterEasing` | `.Easing` | `animationEasing`、`animationEasingUpdate` | `function(APercent: Double): Double of object`（名字区分大小写） |
| `TyChartRegisterSampler` | `.Sampling` | 折线和柱的 `sampling` | `function(const AFrame: TTyDoubleArray): Double of object` |
| `TyChartRegisterGeoProjection` | `.Geo` | geo 和地图的 `projection.project`、`projection.unproject` | `function(AX, AY: Double; out ARX, ARY: Double): Boolean of object` |

单元名都省了前缀 `tyControls.AdvanceChart`。另外两个按名字注册、但不是 `'@'` 写法的：`TyChartRegisterMap`、`TyChartRegisterImageList`（第 7 节）。

dataset 的自定义 transform 用 `TyRegisterDataTransform('命名空间:名字', @Proc)`（`tyControls.AdvanceChart.DataTransform`），对应 `echarts.registerTransform`。`filter`、`sort`、`boxplot` 和 ecStat 的 `regression`、`histogram`、`clustering` 已经内置。

---

## 7. 图片与地图

### 图片

图表自己不联网，也不读文件。配置里的图片（`symbol: 'image://...'`、图案填充、graphic 的 image 元素、SVG 地图里的 `<image>` 等）按下面的顺序找：

| 写法 | 来源 |
|------|------|
| `data:image/png;base64,...` | 直接解码 |
| `image://列表名/序号` | 图像列表里的第几张（从 0 数）。列表名是用 `TyChartRegisterImageList` 注册的名字，或图表所在窗体上同名的 `TCustomImageList` 组件 |
| 其他（http 地址、文件路径） | 问 `OnResolveImage`，回答会记住 |

```pascal
uses tyControls.AdvanceChart.Images;

TyChartRegisterImageList('icons', ImageList1);
// option: symbol: 'image://icons/3'

procedure TForm1.ChartResolveImage(Sender: TObject; const AUrl: string;
  var AImage: TBGRABitmap);
begin
  if FileExists(AUrl) then
    AImage := TBGRABitmap.Create(AUrl);   // 交给图表后由图表释放
end;
```

图像列表按落到屏幕上的设备像素挑最合适的分辨率。`OnResolveImage` 不给图（`AImage` 留 nil）时，那张图不画。

### 地图

`map` 系列和 `geo` 组件要先注册地图，对应 `echarts.registerMap`：

```pascal
uses tyControls.AdvanceChart.Geo, FileUtil;

TyChartRegisterMap('iceland', ReadFileToString('maps/iceland.geo.json'));
TyChartRegisterMap('sicily', ReadFileToString('maps/sicily.svg'));   // SVG 地图
// option: series: [{ type: "map", map: "iceland" }]
```

| 函数 | 说明 |
|------|------|
| `TyChartRegisterMap(AName, AGeoJson, ASpecialAreas = ''): Boolean` | 注册 GeoJSON，或 `{geoJSON, specialAreas}` 包装形式，或 SVG 文本。解析失败答 False |
| `TyChartGetMap(AName, out AGeoJson, ASpecialAreas): Boolean` | 读回注册的文本 |
| `TyChartMapRegistered(AName): Boolean` | 是否注册过 |
| `TyChartUnregisterMap(AName)` | 去掉 |

配置用到没注册的地图时，那一块是空的，`Diagnostic` 里会说缺哪张图。

`examples/advchart/maps` 带了示例用的几张地图（美国、瑞士、冰岛和几张 SVG），`maps.json` 写着名字和文件的对应关系，`umaps.pas` 是注册它们的代码。

库和示例都不带画国界的地图（`china`、`world` 等）。需要的话自己准备合适的 GeoJSON 注册进去。示例里把这类文件放进 `maps/`，命名为 `<名字>.json` 或 `<名字>.geo.json`，就会被读到。

---

## 8. 工具栏与数据视图

`toolbox` 的各个工具都能用：保存图片、还原、数据视图、区域缩放、切换类型、刷选。

- 保存图片：先触发 `OnToolboxSaveAsImage`，没人处理就弹保存对话框，再调 `SaveToFile`。
- 自定义工具：`onclick: '@名字'`，用 `TyChartRegisterToolboxHandler` 注册。

### 数据视图

数据视图是一个模态对话框，有两页，编辑的是同一份文本：

| 页 | 内容 |
|----|------|
| 表格 | 每块数据一个表格，可以直接改单元格 |
| 文本 | ECharts 的那段文本（Tab 分列、换行分行） |

点 Refresh 时取当前那一页的内容，解析后合并回图表。解析出错不会抛异常，原因写在 `ToolboxError`。`readOnly: true` 时两页都只读。

`optionToContent` / `contentToOption` 有两种接法：

- 配置里写 `optionToContent: '@名字'`，用 `TyChartRegisterOptionToContent` / `TyChartRegisterContentToOption` 注册。
- 不写在配置里，用事件 `OnDataViewContent` / `OnDataViewApply`。事件先于配置里的处理器，`AHandled := True` 后配置里的就不再调。

内容（`TTyChartDataViewContent`）有四种形式，由 `Kind` 决定：

| `Kind` | 内容 | 对话框里怎么显示 |
|--------|------|------------------|
| `cdvHtml` | `Text` 是 HTML | 每个 `<table>` 变成表格页上的一个表格，其余文字放在文本页 |
| `cdvText` | `Text` 是纯文本 | 原样放在文本页 |
| `cdvTable` | `Tables` 是表格（`Caption`、`Header`、`Rows`） | 表格页 |
| `cdvControl` | `Control` 是你建的 `TWinControl`（不设 Parent） | 代替两页显示。没有 Owner 时由图表释放 |

`contentToOption` 拿到的是用户改过的内容，返回要合并的 option 文本；返回空串表示不合并。只写了两者之一时，Refresh 不读回内容，和 ECharts 的规则一样。

---

## 9. 键盘与无障碍

### 键盘

ECharts 没有键盘操作，这部分是本控件加的。`TabStop` 缺省是 False，图表不拿焦点。设成 True 后，点击或 Tab 让图表获得焦点：

| 键 | 作用 |
|----|------|
| ← / → | 同一系列的上一个 / 下一个数据项，按数据顺序 |
| ↑ / ↓ | 上一个 / 下一个系列的同一位置 |
| Home / End | 系列的第一项 / 最后一项 |
| PageUp / PageDown | 跳系列长度的十分之一 |
| Enter / Space | 选中或取消选中当前项（系列设了 `selectedMode` 时） |
| Esc | 清掉当前项 |
| Tab / Shift+Tab | 图表里的下一个 / 上一个停靠点，到头后离开图表 |

当前项会高亮、出提示框，外面画一圈焦点框（`TyAdvChartFocusItem`），并发 `highlight` / `downplay` 事件。

停靠点按顺序是：数据项、标注、geo 区域、图例、visualMap、dataZoom、时间线、工具栏、刷选，图表里有哪个算哪个。在组件上用方向键走它的各部分（图例项、工具栏按钮等）；dataZoom、visualMap 上 Shift+方向键缩小或放大范围。

代码里也能设：`SetKeyboardItem(系列, 数据下标)`、`ClearKeyboardItem`、`SetKeyboardStop(...)`。

### 读屏

图表给读屏软件一棵树：图表本身（名字是第一个标题），每个系列一个列表，每个数据项一个列表项（每个系列最多 1000 项），后面是图例、工具栏等组件。图表的描述是自动生成的一句话；配置写了 `aria` 时按 `aria` 的设置生成（`AriaDescription`）。

| 平台 | 支持情况 |
|------|----------|
| Windows | 支持。控件自己提供 MSAA，讲述人（经 UIA）和 NVDA 都能读 |
| Qt5 / Qt6 | 支持，经 LCL 交给 Qt。焦点移动不会通知读屏软件 |
| GTK2 / GTK3、macOS（Cocoa） | 不支持。LCL 在这几个平台上没有把无障碍树交出去 |

---

## 10. 设计期

| 操作 | 打开什么 |
|------|----------|
| 对象查看器里 `Option` 的「...」，或双击图表 | option 编辑器 |
| 右键「图表 option（ECharts）...」 | 同上 |
| 右键「图表系列与数据...」，或 option 编辑器里的「系列与数据...」按钮 | 系列与数据编辑器 |

option 编辑器：

- 带语法高亮的编辑区，按 ECharts 的配置项自动补全。
- 配置项参考树，可以过滤、看每个键的说明，双击把键插到光标处。
- 实时诊断列表，双击一条跳到出问题的位置。
- 「验证」「格式化」按钮。

系列与数据编辑器：

- 左边列出系列，可以增删、调顺序；选中后编辑类型、名字等常用键。
- 右边分「数据」「数据集」「预览」几页，数据在表格里改。
- 改动只写回改了的那几处，其余的键、顺序、注释、引号都保持原样。
- 要重写整段文本或会丢掉注释时，点确定前会先问。

`OptionError` 在对象查看器里只读显示，设计期就能看到配置哪里写错了。

---

## 11. HiDPI

- 按设备像素画。option 里写的像素值按 PPI / 96 放大，150% 缩放下 `fontSize: 12` 画出来是 18 个设备像素。
- `HitTestAt`、坐标换算、事件里的 `OffsetX` / `OffsetY` 都是控件客户区的设备像素。
- 窗体移到 PPI 不同的显示器上时，图表重新排版。
- 导出的 `pixelRatio` 相对逻辑像素：`pixelRatio: 2` 导出的图是逻辑尺寸的两倍。不写时按控件当前的 PPI。
- 图像列表按设备像素挑分辨率，150% 下 16 像素的图标会用 24 像素那一档（列表里有的话）。

---

## 12. 与 ECharts 的差异

### 配置与函数

- option 是 JSON 文本，写不进 JS 函数、`NaN`、`undefined`、`Date`、TypedArray。
- 函数型选项写成 `'@名字'`，指向注册的 Pascal 方法（第 6 节）。
- 处理器是返回字符串或数值的 Pascal 方法，没有 `undefined`：比如 matrix 的 formatter 不能靠返回 null 表示「不改」。
- 没有 `registerTheme` 和主题名，颜色走皮肤。
- 没有 `locale` 选项和 `registerLocale`。月名、星期名、图例的「全选 / 反选」、工具栏标题等文字跟库的语言设置走。
- `TyChartGetMap` 答注册时的文本，不是解析后的对象。
- 没有 SVG 渲染器，也没有 `getZr`。自定义系列 api 里的 `getWidth`、`getHeight`、`getDevicePixelRatio` 照有。
- 自定义系列的 `autoBatch` 不起作用。每个元素单独画，只在半透明图形重叠处看得出差别。
- dataset `filter` 的 `reg` 正则一次匹配超过五千万步就当出错（ECharts 会一直回溯，页面卡住）。
- 类目超过 2^20 个的窗口不画；`splitNumber` 最多 1000 段；`logBase` 写成小于等于 1、负数或文字时按 10。
- 十六进制颜色按严格格式读，`#12g` 这类写错的颜色用主题色。读不出的颜色用主题色或不画。

### 主题与文字

- 缺省调色板、轴线、分割线、提示框、刷选框等的颜色取皮肤。浅色皮肤下多数和 ECharts 的缺省一样。option 里的 `color`、`darkMode`、`backgroundColor`、根上的 `textStyle` 照读。
- 没写字号和字体的文字用皮肤的（ECharts 是 12px sans-serif）。类目轴自动隔几个显示标签，可能因此和 ECharts 差一档。
- 写了的 `fontSize` 按像素读。`rem`、`em` 不支持。
- 字用系统的字体引擎量和画（Windows GDI、Linux FreeType、macOS CoreText），和浏览器的度量不同。标签宽度、截断位置、网格边距会差几个像素。

### 绘制

- `ExactRendering` 缺省 False。比 1 个设备像素还细的实线和标签描边走快速画法，和浏览器有细小的像素差。设成 True 照 canvas 逐像素画，慢。
- 用 BGRABitmap 画，不是浏览器的 canvas。半透明的细线比 canvas 浅一些，抗锯齿的边缘不逐像素相同。
- 阴影的模糊（包括地图热力图的模糊）是近似算法，和浏览器不逐像素相同。
- SVG 地图里斜切或拉伸过的文字，先画成位图再变形。
- 力导向布局、散点抖动（jitter）、聚类用固定的随机种子，每次结果一样。力导向的迭代步数有上限。
- `zlevel` 照 ECharts 分层画、分层找命中，只有这几处不同：提示框、坐标轴指示器、悬停层、键盘焦点环总在最上面；加载遮罩不会低于坐标轴和标题的 `zlevel`；数据量过渐进门槛的散点、带拖尾的 lines，ECharts 会自动另分一层（遮罩因此在它们下面），这里不分。
- 关系图的边标签、lines 系列的标签，`emphasis`、`select`、`blur` 的 `label` 里写的 `position`、`distance`、`offset`、`rotate` 不读，进了状态标签还在原处。
- 系列的 `labelLayout` 写了 `x`、`y`、`align`、`verticalAlign`、`fontSize`、`width`、`height` 或 `moveOverlap` 时，状态里写的 `position` 等四项不读。
- 开着动画时，状态把柱子或符号的边框改宽，挂在上面的标签不跟着边框挪；关掉动画时跟着挪。
- 饼图按状态里的 `position` 摆标签时，直接摆到放大后的扇区上，不跟着扇区放大的过渡一点点移过去。
- 圆形雷达的分割区域只有一种颜色时，相邻两环之间有一道很淡的接缝（ECharts 把同色的环合成一条路径）。
- 命中检测是近似的。正好落在图形边上的点（扇区边缘、圆头柱的两端、K 线和箱线的线宽、抽样过的折线）可能和 ECharts 判得不同。

### 提示框

- 提示框画在控件里面，不会伸出控件。没写 `confine` 时按 `true` 处理，写了照写的来。
- 缺省内容按 richText 方式排版，不是 html 模式的那套 HTML。
- formatter 返回的 HTML 只读常用的部分：换行、块、加粗、斜体、颜色、字号、色点、表格的行。不排版图片、对齐、自动换行、块背景。要自己排就用 `OnTooltipHtml`。`TooltipAutoRichText` 设成 True 则按 richText 原样显示。
- `enterable` 不适用；`position` 函数拿不到 `dom` 参数。

### 交互与事件

- 事件用 `ChartOn` / `ChartOff` / `OnChartEvent`。`ChartOn` 对图表不发的类型返回 -1（ECharts 的 `chart.on` 什么名字都收，只是永远不触发）。
- `GraphRoam`、`TreeToggle` 这类直接调用的方法不发事件；同样的操作用 `DispatchAction` 发动作时会发。
- `chart.group` 是 `Group` 属性，空串表示不在组里。
- 键盘操作和读屏是本控件加的，ECharts 没有。
- 拖动只认左键。
- 宿主的 `OnMouseWheel` 已经处理掉的滚轮，图表收不到。
- LCL 的双击不带坐标，按最近一次按下的位置算。鼠标捕获丢失时，当作在最后的位置松开。
- `setOption` 之后、下一次重画之前，鼠标碰到的是屏幕上那一帧。
- CSS 光标名转成 LCL 的光标，对不上的（`copy`、`zoom-in` 等）用宿主自己的光标。
- 矩形树图的 `nodeClick: 'link'` 不打开浏览器。
- `geoRoam` 动作的载荷里有坏值时，那几个键忽略（ECharts 会把视图弄坏）。

### 工具栏与导出

- 数据视图是模态对话框（表格页 + 文本页）。`optionToContent` 返回的 HTML 读成表格和文字，不画样式。Refresh 出错不抛异常，原因在 `ToolboxError`。
- 导出没写背景色时画皮肤的底色，不是透明。要透明写 `backgroundColor: 'transparent'`。
- 导出只有 PNG、JPEG、WebP。`type: 'svg'` 得到的是 PNG。WebP 要 libwebp，没有时写 PNG。
- 导出图里没有提示框，也没有 lines 的拖尾。
- 联动组合并导出时，每张图按整像素贴。

### 合并与读回

- `Option` 赋一段不同的文本等于 notMerge，合并后读出的是合并后的树。
- `GetOptionJson` 是作者写的配置合并后的样子：没有主题和缺省值，没有组件 id（用 `ComponentModelId` 取），没有 media 项和 timeline 的各帧。
- roam 之后的中心和缩放不写回配置文本，用 `GeoRoamState` 等方法读。
- matrix 里写成 null 的键按没写处理，落到缺省值。

### ECharts 会抛错的写法

- ECharts 抛错、整次 `setOption` 失败的写法，这里只跳过出错的那一项、组件或数据集，原因写进 `Diagnostic`。比如主题河流各层行数不同、matrix 的合并格跨进正文、large 散点用 `image://` 符号。
- 同一类组件两个相同 id、`replaceMerge` 写了不存在的类型：整次合并拒绝，图不变，`OptionError` 写着原因。
- 不认识的系列类型照样占一个下标（ECharts 不把它放进列表，后面系列的下标会错开）。
- 诊断会报 ECharts 不读的键。ECharts 3 的旧写法照读，不报「已弃用」。

### 动画方面

- 换皮肤时，进行中的悬停、选中等状态过渡直接跳到终值（ECharts 换主题会接着播完）。
- `stateAnimation.delay` 不能写成函数。
- universal transition 还有几处没做：
  - 样式只过渡填充、描边、线宽和透明度，阴影、`fillOpacity`、`strokeOpacity` 和渐变不过渡；
  - 被图例关掉的旧系列不参与过渡；
  - 几个图形合并成一个时，只有第一段能点到；离场途中画的是合并后的整体，不是各段；
  - 维度编码不读 dataset、`seriesLayoutBy: 'row'` 和 time 列；
  - 按视图分组的过渡只支持关系图节点。
- 树图里保留下来的节点没了子节点时，ECharts 会留下一段没人删的连线，这里不留。
- `AnimationMode` 为 `camAuto` 时，控件不在屏幕上的那段时间里派发的动作，动画最多晚一帧开始；`camAlways` 和 ECharts 同帧。
- geo 的旋转、斜切漫游不做过渡，过渡途中区域的描边宽度不跟着缩放。
- lines 拖尾的 `motionBlur` 只模糊 lines 系列自己。
- 坐标轴指示器的标签框大小按皮肤的排版定，过渡的只是框的位置。
- 点时间线刻度时，提示框会在时间线切换后消失。

### 平台

- 读屏：Windows 是控件自己的 MSAA（没有原生 UIA、IAccessible2），Qt 经 LCL，GTK 和 macOS 不支持（第 9 节）。
- 没有触摸：双指缩放没有，`CoarsePointer` 的 `ccpAuto` 在桌面上等于关。
- 时区：Windows 上没有完整的 IANA 历史时区，很早年份的本地时间可能和浏览器差几分钟。零时区又有夏令时的地方，日历按天算可能差一天。
- 动画由消息循环里的定时器驱动，每 16 毫秒一帧，精度是毫秒。

### 性能

- 很长的折线（几百个点以上）局部重画时整条重描，一次约 0.2 秒。
- 几十万个数据点的大图：设配置要零点几秒到一秒，dataZoom 拖一步要零点几秒，50 万根柱分块画完要四五秒。
- 7000 多条 0.5 像素曲线的平行坐标，分块画完约 2 秒。

---

## 13. 关联

简单的折线、柱、饼图见 [TTyChart](chart.md)；单值迷你趋势线见 [TTySparkline](sparkline.md)。从 `TTyCustomAdvanceChart` 派生自己的图表控件见 [../subclassing.md](../subclassing.md)。
