# TTyScrollBar — API 参考

## 1. 概述

`TTyScrollBar` 是 TyControls 库中的滚动条控件，支持垂直和水平两种方向。控件自绘轨道背景和滑块（thumb），通过 `TyScrollThumbRect` 纯函数计算 thumb 的几何位置，无需外部状态。`OnChange` 仅在 `Position` 真正发生变化时触发，防止冗余通知。

`TyScrollThumbRect` 是该单元导出的独立几何工具函数，可在自绘场景中单独使用。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ScrollBar` |
| typeKey（轨道 / 端部箭头） | `TyScrollBar` |
| typeKey（滑块子部件） | `TyScrollThumb` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 16 × 160（垂直，逻辑像素） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Kind` | `TTyScrollBarKind` | `sbVertical` | 方向。`sbVertical`：竖向；`sbHorizontal`：横向。改变后触发 `Invalidate`。 |
| `Min` | `Integer` | `0` | 最小位置值。赋值时若 `Position < Min` 则自动夹紧 `Position := Min`。 |
| `Max` | `Integer` | `100` | 最大位置值。赋值时若 `Position > Max` 则自动夹紧 `Position := Max`。 |
| `Position` | `Integer` | `0` | 当前位置，范围 `[Min, Max]`。赋值时自动夹紧；仅在值真正变化时触发 `OnChange`。 |
| `PageSize` | `Integer` | `10` | 页面大小（可见内容大小），决定 thumb 在轨道中的比例长度。不可为负（负值被夹为 0）。**当 `LargeChange = 0`（默认）时它也是**点击轨道空白处和 `PageUp`/`PageDown` 的步进量。 |
| `LargeChange` | `Integer` | `0` | **（API parity 新增）** 翻页步进量：点轨道、`PageUp`/`PageDown`、`scPageUp`/`scPageDown`。早前 `PageSize` 身兼两职，于是**滑块比例与翻页步长无法分开选**：把 `PageSize` 调小去瘦滑块，翻页也跟着变成一行。LCL 里两者分开（`stdctrls.pp:106`；`PageSize` 只喂 `ScrollInfo.nPage`，`LargeChange` 只驱动翻页）。**默认值有意与 LCL 不同**：LCL 是 `1`，而本库的列表框 / 网格 / 备忘录 / 树 / 滚动容器全都内嵌这个滑块并把 `PageSize` 设为视口大小，跟随 LCL 会让每一次点轨道只走 1 个单位。`0` = “按 `PageSize` 翻页”，即这个属性存在之前的行为。 |
| `SmallChange` | `Integer` | `1` | 单步步进量：点击端部箭头按钮、按方向键各步进 ±`SmallChange`。最小为 1（赋值 <1 被夹为 1）。 |
| `AnimationsEnabled` | `Boolean` | `True` | **（API parity 新增 published）** 控制程序化 Position 变化（键盘 / 滚轮 / 轨道点击）时 thumb 的缓动动画（约 120 ms，EaseOutCubic）；实时拖拽与无头环境瞬时跟随。 |
| `LiveTracking` | `Boolean` | `True` | **（新增）** 拖动 thumb 时 `Position` 是**持续跟随**（`True`，出厂值，也是本控件一贯的行为）还是**只在松手时落一次**（`False`）。这就是 LCL `goThumbTracking` 所需要的那道缝，详见下方 §4「拖动的两种提交方式」。 |
| `AutoHide` | `TTyScrollBarAutoHide` | `sbahDefault` | **（新增）** 滚动条闲下来之后要不要淡出。`sbahDefault` 跟主题走（令牌 `--scrollbar-auto-hide`）；`sbahNever` 永远显示、`sbahAuto` 一定淡出，两者都压过主题。延时没有属性，要调改主题。详见下方 §7「自动隐藏」。 |
| `OnChange` | `TNotifyEvent` | `nil` | Position 真实变化时触发（包括 `DragThumbTo` 引起的变化）。 |
| `OnScroll` | `TScrollEvent` | `nil` | **（API parity 新增）** 键盘 / 轨道点击 / 端部按钮触发的滚动；签名 `(Sender; ScrollCode: TScrollCode; var ScrollPos: Integer)`，可在 handler 中改写 `ScrollPos` 覆盖目标位置。**鼠标滚轮直接改写 Position（触发 `OnChange`），不经 `DoScroll`，因此不触发 `OnScroll`。** |
| `Align` | `TAlign` | — | 布局对齐方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（使用全局默认） | 关联的样式控制器。 |

### 类型定义

```pascal
TTyScrollBarKind = (sbHorizontal, sbVertical);
TTyScrollBarAutoHide = (sbahDefault, sbahNever, sbahAuto);
```

注意：枚举定义中 `sbHorizontal` 序数值为 0，`sbVertical` 为 1；但 `Kind` 属性的默认值为 `sbVertical`。

`TTyScrollBarAutoHide` 三个值的含义见 §7。

## 4. 方法与事件

### public 方法

#### `procedure BeginThumbDrag(AGrabPosAlongTrack: Integer)`

开始拖动 thumb。`AGrabPosAlongTrack` 是鼠标在轨道方向上的坐标（相对于控件客户区）：

- 计算当前 thumb 的像素起始位置（`ThumbStart`）。
- 记录抓取偏移：`FDragGrabOffset := AGrabPosAlongTrack - ThumbStart`。
- 设置 `FDragging := True`。

通常在 `OnMouseDown` 中调用，`AGrabPosAlongTrack` 传入 `Y`（垂直）或 `X`（水平）。

#### `procedure DragThumbTo(APosAlongTrack: Integer)`

拖动过程中更新位置。若 `FDragging = False` 则立即退出（无操作）。

计算逻辑：

1. 获取当前 thumb 的像素长度（`ThumbLen`）。
2. `FreeSpace := TrackLength - ThumbLen`（最小为 1）。
3. `NewTop := APosAlongTrack - FDragGrabOffset`，夹紧至 `[0, FreeSpace]`。
4. `NewPos := Min + (NewTop * (Max - Min)) div FreeSpace`。
5. 触发 `OnScroll(scTrack, NewPos)`。
6. `LiveTracking = True`（默认）时通过 `Position := NewPos` 赋值（自动夹紧并在变化时触发
   `OnChange`）；`LiveTracking = False` 时**只**把 `NewPos` 记作待提交值并重画 thumb，
   `Position` 不动。

通常在 `OnMouseMove` 中调用。

#### `procedure EndThumbDrag`

结束拖动。触发 `OnScroll(scPosition)` 与 `OnScroll(scEndScroll)`，然后将 `FDragging := False`。
`LiveTracking = False` 时**这里才是整个拖动手势唯一一次写 `Position`**（因而也是唯一一次
`OnChange`）。通常在 `OnMouseUp` 中调用。

#### `property TrackPosition: Integer`（只读）

thumb **当前所在**的位置值。除了 `LiveTracking = False` 的拖动过程中，它恒等于 `Position`；
在那段过程里 thumb 已经动了而 `Position` 还没动，两者之差就是这个模式本身。宿主想在拖动中做
预览（比如在 thumb 旁边浮一个行号提示）就读它，其余场合一律读 `Position`。

### 拖动的两种提交方式（`LiveTracking`）

| | `LiveTracking = True`（默认） | `LiveTracking = False` |
|---|---|---|
| 拖动中 thumb | 跟随鼠标 | 跟随鼠标（**一样**跟手） |
| 拖动中 `Position` | 每步都变 | 不变 |
| 拖动中 `OnChange` | 每步一次 | 不触发 |
| 拖动中 `OnScroll(scTrack)` | 每步一次 | **每步一次**（建议值） |
| 松手 | `scPosition` / `scEndScroll` | `scPosition` / `scEndScroll` + 一次 `OnChange` |
| 最终落点 | 相同 | 相同 |

要点：

- **推迟的是提交，不是 thumb。** thumb 不动的拖动就是个死控件，所以关掉之后 thumb 照样跟手。
- **`scTrack` 照发。** 原生滚动条在关掉实时跟随时也照样发 `SB_THUMBTRACK`，是宿主自己决定
  理不理。这条不发的话这个模式就只剩「卡住」，而不是「便宜」——一个每行都要查一次数据库的
  宿主正是靠 `scTrack` 做预览、靠松手才真的跳过去。
- **只影响拖动这一个连续手势。** 端部箭头、点轨道翻页、滚轮、键盘都是离散的一步，两种模式下
  都立刻生效；原生滚动条也不推迟它们。
- **出厂为 `True`**，即这个属性存在之前的行为——本控件已经发布，默认换行为等于给每一张现有
  窗体换行为。

```pascal
// 昂贵的宿主：拖动中只预览，松手才真滚
Bar.LiveTracking := False;
Bar.OnScroll := @PreviewRow;      // scTrack 里更新提示，不动数据
Bar.OnChange := @CommitScroll;    // 松手时才发生，整个手势一次
```

**`goThumbTracking`(LCL 对标)**:`TTyGrid.Options` 现在有这一位了——`goThumbTracking`,
它是这个属性的**视图**(读写都落到两条滚动条的 `LiveTracking` 上,不另存一份),
详见 [grid.md](grid.md) 的对照表。

逐条设置仍然可用,而且是唯一能只关一条轴的写法:

```pascal
Grid.VScrollBar.LiveTracking := False;   // VScrollBar / HScrollBar 是 TTyCustomGrid 的公开只读属性
Grid.HScrollBar.LiveTracking := False;
```

注意两者的粒度不同:`Options` 里那一位是**两条一起**翻,而直接写属性可以只关一条。
只关了一条时 `goThumbTracking` 读出来是**关**(getter 读纵向那条),再写 `Options`
的别的位不会把横向那条带回来。

#### `function GetStyleTypeKey: string`（override）

返回固定字符串 `'TyScrollBar'`。

### 端部箭头按钮与交互

控件在轨道两端各渲染一个箭头按钮（垂直：顶/底；水平：左/右）。为给按钮腾出空间，**轨道（track）从客户区两端各内缩一个按钮尺寸**：

- 按钮尺寸 = 轨道横向厚度（`TyScrollButtonSize`：垂直取宽度，水平取高度）。
- 轨道矩形由 `TyScrollTrackRect(Client, Kind, ButtonSize)` 计算；thumb 与点击命中均基于内缩后的轨道。
- **退化：** 当控件主轴长度 `<= 2 × 按钮尺寸`（太短放不下两个按钮）时，不保留箭头带，整个客户区都是轨道。

鼠标交互（`MouseDown`，仅左键）：

| 命中位置 | 行为 |
|----------|------|
| 端部箭头按钮（Lo / Hi） | `Position ∓= SmallChange`（Lo 减、Hi 加），并尝试 `SetFocus` |
| thumb 本体 | 开始拖动（`BeginThumbDrag` + `MouseCapture`） |
| 轨道空白处（thumb 之外） | 朝点击方向翻一页 `Position ∓= PageSize` |

### 键盘操作

控件需获得焦点才响应（独立摆放的条 `TabStop` 默认 `True`，参见注意事项）。每个被处理的按键消费后不再传递（`Key := 0`）。

| 按键 | 行为 |
|------|------|
| `↑` / `↓`（垂直） | `Position ∓= SmallChange`（↑ 减、↓ 加） |
| `←` / `→`（水平） | `Position ∓= SmallChange`（← 减、→ 加） |
| `PageUp`（VK_PRIOR） | `Position -= PageSize` |
| `PageDown`（VK_NEXT） | `Position += PageSize` |
| `Home`（VK_HOME） | `Position := Min` |
| `End`（VK_END） | `Position := Max` |

> 方向键按 `Kind` 区分主轴：垂直用 `↑`/`↓`，水平用 `←`/`→`。所有步进结果都经 `SetPosition` 钳制到 `[Min, Max]`。

### 独立几何函数

#### `function TyScrollThumbRect(...): TRect`

```pascal
function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer): TRect;
```

纯函数，无副作用，根据参数计算 thumb 在轨道矩形内的像素位置。

**算法：**

- `Span := (AMax - AMin) + APageSize`
- 退化条件（`Span <= 0` 或 `APageSize <= 0` 或 `AMax <= AMin`）：thumb 填满整个轨道，返回 `ATrack`。
- `ThumbLen := (APageSize * TrackLen) div Span`，夹紧至 `[1, TrackLen]`。
- `FreeSpace := TrackLen - ThumbLen`。
- `Travel := AMax - AMin`。
- `Pos0 := clamp(APosition - AMin, 0, Travel)`。
- `Offset := (Pos0 * FreeSpace) div Travel`（`Travel <= 0` 时 `Offset = 0`）。
- 垂直：`Result := Rect(Left, Top+Offset, Right, Top+Offset+ThumbLen)`。
- 水平：`Result := Rect(Left+Offset, Top, Left+Offset+ThumbLen, Bottom)`。

**Thumb 与轨道的比例关系：**

```
ThumbLen / TrackLen ≈ PageSize / (Max - Min + PageSize)
```

`PageSize` 越大，thumb 越长（代表可见内容比例大）；`Max - Min` 越大，thumb 越短。

#### `function TyScrollButtonSize(...): Integer` / `function TyScrollTrackRect(...): TRect`

```pascal
function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;
```

两个导出的纯几何函数，配合端部箭头按钮使用：`TyScrollButtonSize` 返回箭头按钮的尺寸（= 轨道横向厚度）；`TyScrollTrackRect` 返回从客户区两端各内缩一个按钮尺寸后的轨道矩形（主轴太短放不下两个按钮时返回整个客户区）。控件内部用它们定位 thumb 与命中检测，也可在自绘场景中单独调用。

### 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | `Position` 属性值真实变化时（包括 `DragThumbTo` 间接触发） |
| `OnScroll` | `TScrollEvent` | **（API parity 新增）** 键盘 / 轨道点击 / 端部按钮滚动时，经 `DoScroll` 分发；`var ScrollPos: Integer` 可被 handler 改写以覆盖目标位置。鼠标滚轮**不**触发此事件（仅触发 `OnChange`）。 |

> **滚轮步进（API parity 新增）：** `TTyScrollBar` 现支持鼠标滚轮步进——滚轮上滚减小 `Position`（向上滚动内容），步进量为 `SmallChange`，直接改写 `Position` 并触发 `OnChange`。除上表外还暴露**基线事件集**（Tier A + Tier B），见 [../events.md](../events.md)。

## 5. 状态与主题

### 状态

TTyScrollBar 继承 `TTyCustomControl` 的状态机制：

| 状态常量 | 触发条件 |
|----------|----------|
| `tysNormal` | 正常 |
| `tysHover` | 鼠标悬停在控件上 |
| `tysActive` | 鼠标左键按下 |
| `tysFocused` | 键盘焦点（独立摆放的条 `TabStop` 默认 `True`，参与 Tab 循环；宿主内嵌的条不拿焦点） |
| `tysDisabled` | `Enabled = False` |

### 支持的伪类状态（TyScrollBar 轨道）

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 控件获得键盘焦点（绘制焦点环）。独立摆放的条 Tab 过去或点一下就会出现；内嵌条不拿焦点，点它焦点归宿主，焦点环画的是宿主的 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False`（统一施加 `opacity` 半透明，与其余控件状态一致） |

### light.tycss 内置规则

```css
TyScrollBar {
  background: var(--chrome-bar-bg);      /* 轨道背景 */
  color: var(--scroll-handle);           /* 端部箭头墨色（tier-b 字形） */
  border-radius: var(--radius-scroll);
}
TyScrollBar:hover  { color: var(--scroll-handle-hover); }
TyScrollBar:active { color: var(--accent); }
TyScrollBar:focus    { outline: 2px var(--focus-ring); }   /* 焦点环 */
TyScrollBar:disabled { opacity: var(--disabled-opacity); }

/* 滑块由独立子部件 typeKey 着色（tier-a 着色面） */
TyScrollThumb        { background: var(--scroll-handle); border-radius: var(--radius-scroll); }
TyScrollThumb:hover  { background: var(--scroll-handle-hover); }
TyScrollThumb:active { background: var(--accent); }
```

另有一个 metric 令牌 `--scrollbar-auto-hide`，控制闲下来之后淡不淡出，`light.tycss` 里是 `-1`（不淡）。见 §7。

宿主内嵌的条贴着宿主的边，滑道圆角不读 `TyScrollBar` 的 `border-radius`，读令牌 `--radius-scroll-embedded`，`light.tycss` 里是 `0`（方角）。改成非零，滑道两端会露出宿主底色的缺口。滑块照旧用 `TyScrollThumb` 的圆角。

### 纯主题菜谱：平时淡、碰到才亮

不动一行代码，只靠皮肤让滚动条平时退到背景里：

```css
TyScrollBar { background: var(--chrome-bar-bg); color: var(--scroll-handle);
  border-radius: var(--radius-scroll); opacity: 0.3; }
TyScrollBar:hover  { color: var(--scroll-handle-hover); opacity: 1; }
TyScrollBar:active { color: var(--accent); opacity: 1; }
TyScrollBar:focus  { outline: 2px var(--focus-ring); }
TyScrollBar:disabled { opacity: var(--disabled-opacity); }
```

**整块抄全，别只抄要改的那一条。** 皮肤里只要出现了 `TyScrollBar` 的任意一条规则，内置的那一整块就作废——不是逐条合并，`:hover` / `:focus` / `:disabled` 一起没。只写一句 `TyScrollBar { opacity: 0.3 }`，得到的是一条没有轨道底色、没有圆角、没有焦点环的滚动条。

**半透明的条压在渐变或图片背景上，它那一竖条是单点采样出来的平色，不跟着背景走**——这份菜谱的 `opacity: 0.3`、内置的 `:disabled`，以及自动隐藏的淡入淡出过程，走的都是同一条合成分支。

### 渲染细节

- `DrawFrame` 绘制轨道背景（使用 `TyScrollBar` 的 `background`），并施加 `:focus` 焦点环、`:disabled` 的 `opacity`。
- **滑块（thumb）是独立子部件 typeKey `TyScrollThumb`**（tier-a 着色面）：渲染器解析 `TyScrollThumb` 的样式，用其 `background.Color` 构造 `tfkSolid` 填充、以其 `border-radius` 为圆角绘制 thumb 矩形——不再借用 `TyScrollBar` 的 `color`。`TyScrollThumb` 支持 `:hover` / `:active`，其内置默认（`var(--scroll-handle)` / hover `var(--scroll-handle-hover)` / active `var(--accent)`、`border-radius: var(--radius-scroll)`）与旧版借用 `color` 时的渲染结果**逐字一致**，老主题升级后外观不变。
- **端部箭头**仍是 tier-b 单色字形，墨色取 `TyScrollBar` 的 `color`（`TextColor`）。要单独改箭头颜色，改 `TyScrollBar { color: … }`；要改滑块颜色，改 `TyScrollThumb { background: … }`。详见 [tycss-reference.md](../tycss-reference.md) §8.3。
- 没有内置命名变体（`.class`）。

## 6. 状态过渡动画（batch⑤+⑥）

`TTyScrollBar` 支持滑块（thumb）在 **程序化** `Position` 改变时平滑过渡到新位置，由 `tyControls.Animation` 单元的 `TTyAnimator` 驱动。

控件身上有**两套**互不相干的过渡：

| 过渡 | 时长 / 曲线 | 归谁管 |
|------|------------|--------|
| 滑块位置缓动 | 120ms，`teEaseOutCubic` | `AnimationsEnabled` |
| 自动隐藏的淡入 / 淡出 | 120ms / 200ms，`teEaseOutCubic` | `AutoHide` 与主题令牌，见 §7 |

**`AnimationsEnabled` 不管淡入淡出。** 六个宿主内嵌的条全都把 `AnimationsEnabled` 关掉了，它们的淡入淡出照跑。两套字段、两个定时器，别串着看。本节余下部分只讲滑块那一套。

### 开关属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AnimationsEnabled` | `Boolean` | `True` | 是否启用滑块位置过渡动画。published，可写入 `.lfm`。 |

> 滑块这套**没有**单独的时长 / 缓动曲线属性可供配置——时长与缓动在控件内部固定。

### 行为

- **程序化变化才缓动：** 启用（`True`，默认）且有窗口句柄时，由**键盘 / 滚轮 / 点击轨道空白翻页 / 端部箭头**等引起的 `Position` 变化会让绘制的滑块从旧位置**缓动**到新位置（约 **120ms**，缓动曲线 `teEaseOutCubic`）。
- **拖动始终瞬时：** 用户**拖动滑块**（`DragThumbTo`）时滑块**实时跟手、不缓动**——拖拽期间绘制即贴当前位置，避免延迟感。
- **关闭（`False`）：** 所有 `Position` 变化都瞬间反映到滑块位置。
- 控件尚无窗口句柄（headless / 设计器）时，无论开关如何都**瞬间吸附到终态**（**headless-snap**）——因此既有的逐像素 thumb 几何测试不受影响。
- 内部按需创建一个 `TTimer`（约 60fps）推进动画，抵达目标后自动停止；动画逻辑可在测试中以显式毫秒步进确定性驱动。

> **NOTE — 内嵌滚动条的滑块按设计为静态：** 六个宿主（`TTyStringGrid` / `TTyDrawGrid`、`TTyListBox`、`TTyListView`、`TTyMemo`、`TTyScrollBox`、`TTyTreeView`）内部创建的滚动条，在创建时都被显式设为 `AnimationsEnabled := False`。这是**有意为之**：内容跟随滚动需要即时反馈，滑块缓动反而会与内容产生位置错位，因此内嵌滚动条始终瞬时跟随，不参与缓动。**关掉的只是滑块缓动，自动隐藏的淡入淡出不受影响**，照淡。独立使用 `TTyScrollBar` 时默认启用缓动，不受此影响。

## 7. 自动隐藏

闲下来就把滚动条淡掉，再用的时候淡回来。macOS 和 Win11 上就是这个做派。

出厂**关着**：`light.tycss` 把 `--scrollbar-auto-hide` 写成 `-1`，经典世代的皮肤一行不写、继承它。切到下面那六个皮肤才会看见条自己消失。

### 主题令牌 `--scrollbar-auto-hide`

一条轴，没有歧义的零：

| 值 | 含义 |
|----|------|
| `-1` | 关。条一直显示。**内置默认**，`light.tycss` 写的就是它。 |
| `0` | 开。停手即淡出。 |
| `N` | 开。空闲 N 毫秒后淡出。 |

写 `1200` 的六个皮肤：`win11`、`macos`、`fluent`、`material3`、`adwaita`、`ubuntu`——平台上真用遮盖式滚动条的那几个。

一行不写、因而继承 `-1` 的：经典世代的 `classic` / `xp` / `aero`，外加 `win10`、`office`、`showcase`、`antdesign`、`bootstrap`、`breeze`。`win10` 是刻意留的：Win32 桌面滚动条从不自动隐藏，会隐藏的是 UWP。`office` 同理，对标的是桌面版那张脸，不是网页版。

### `AutoHide` 属性

| 值 | 行为 |
|----|------|
| `sbahDefault` | 跟主题走。出厂值。 |
| `sbahNever` | 永远显示，压过主题。 |
| `sbahAuto` | 一定淡出，压过主题；延时仍然读主题，主题说关就退回 1200ms。 |

`sbahAuto` 碰上一个说「关」的主题不跟着关，而是退到 1200ms。一个明写着要隐藏、结果不隐藏的属性是在撒谎。

**三态枚举，不是 Boolean，这是有意的。** Boolean 一旦被碰过就永远脱离主题控制，换肤不跟着变——在一个主打换肤的库里这是硬伤。三态里 `sbahDefault` 是个真正的「我不表态」，随时能回到主题手上。

**延时故意不给属性。** 单条滚动条要一个跟别处不一样的延时，是臆想需求；整体调快调慢改主题。

### 宿主转发

六个宿主各有一个 published 的 `ScrollBarAutoHide`，三个值、默认值都和 `AutoHide` 一样，写下去落到它内嵌的那一条（或两条）上：

`TTyStringGrid` / `TTyDrawGrid`、`TTyListBox`、`TTyListView`、`TTyMemo`、`TTyScrollBox`、`TTyTreeView`。`TTyValueListEditor` 从 `TTyCustomListBox` 继承，不必单列。

```pascal
Memo1.ScrollBarAutoHide := sbahNever;   // 这个 Memo 的条不许消失，不管皮肤怎么说
```

### 一句话全库关掉

升上来嫌它淡、又不想去动主题文件：往 controller 上贴一层 tycss 补丁。

```pascal
TyDefaultController.StyleOverride := ':root { --scrollbar-auto-hide: -1; }';
```

补丁叠在主题最上面，换肤、换密度都冲不掉；清掉写 `''`。自备 controller 的贴到自己那一个上。

**必须是 controller 上的 `StyleOverride`。** 控件和窗体上那个同名属性只收裸声明（`color: red;` 这一类），带选择器的 `:root { ... }` 它解析不过，当成空补丁悄悄扔掉——写下去一点动静都没有。令牌要从 controller 这条路进去，才进得了 metric 读的那张变量表。

### 什么算「还在用」

下面任一条成立，延时表就不起；全不成立才开始计时：

- `Position` 变了——滚轮、键盘、点轨道、拖动，**以及宿主代码直接赋值**
- 指针**在宿主上**——鼠标落到列表、网格、树、备忘或滚动框的任何位置，它的条就出来
- 指针压在条本身上
- 正在拖
- 有焦点（只有独立摆放的条会有）

指针离开宿主才开始倒计时，到点淡出。鼠标不在这个列表上的时候，它的滚动条本来也没有理由还杵在那儿。

跟的是 Fluent / UWP 那一路：进到可滚动区域就出细条，移到条上再变宽。macOS 含蓄些，非滚不出；这边没跟，因为本库的条占一条槽而不是浮在内容上，它出来的时候不盖住任何东西。

> 这条规则一度写反。2026-09-14 的设计稿定的是「指针在内容上不算」，理由写着「Win11 也是滚动才出现」——那句话对 macOS 成立，对 Win11 不成立。用户真机第一次用就撞上了：「鼠标移动到列表上的时候，scrollbar 并没有显示，只有用中键滚动，或者鼠标移动到 scrollbar 上面的时候，才会显示」。当时还有一层担心，说指针大部分时间停在内容上、条就永远闲不下来——那是把「停手」读成了「停止滚动」；读成「指针离开这个控件」，矛盾就没了。

**写宿主的人要知道的那个坑**：条是窗口化子控件，指针从内容挪到条上时**宿主收到的是 `MouseLeave`**。所以「宿主被 hover」和「条被 hover」必须合起来判，任一为真都算还在用；只认一个，交界处就会闪一下。宿主把自己的 hover 状态用 `TTyScrollBar.SetHostHovered` 喂给它的每一条条——两条都要喂。`TTyScrollBox` 喂的是 `CM_MOUSEENTER` / `CM_MOUSELEAVE` 而不是 `MouseEnter`：它的内容是别的控件，指针落在里面那颗按钮上时 LCL 只把消息广播给它，不调用它的 `MouseEnter`。

### 时长

淡入 120ms，淡出 200ms，都是 `teEaseOutCubic`。出现要快，用户正在找它；消失要柔，别打扰。

两个数是代码常量（`TyScrollBarFadeInMs` / `TyScrollBarFadeOutMs`），不是主题令牌。全库今天的过渡时长都是常量，单把这一处令牌化，得到的是一半可配一半写死，比两头都不做更糟。

### 设计期不淡

IDE 里条恒亮，否则摆版的时候找不着它。

除此之外没有豁免：句柄一到手延时表就起来，一条谁也没碰过的条照样会自己淡掉。

## 8. 代码示例

### 基本垂直滚动条

```pascal
uses tyControls.ScrollBar;

var
  SB: TTyScrollBar;
begin
  SB := TTyScrollBar.Create(Self);
  SB.Parent := Self;
  SB.Kind := sbVertical;
  SB.Left := 200;
  SB.Top := 10;
  SB.Width := 16;
  SB.Height := 200;
  SB.Min := 0;
  SB.Max := 90;    // 内容总行数 - 可见行数
  SB.PageSize := 10;
  SB.Position := 0;
  SB.OnChange := @OnScrollChange;
end;

procedure TForm1.OnScrollChange(Sender: TObject);
begin
  // 同步滚动内容
  MyListArea.TopRow := TTyScrollBar(Sender).Position;
end;
```

### 集成鼠标拖动

```pascal
procedure TForm1.ScrollBarMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    // 垂直时传 Y，水平时传 X
    FScrollBar.BeginThumbDrag(Y);
end;

procedure TForm1.ScrollBarMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if ssLeft in Shift then
    FScrollBar.DragThumbTo(Y);
end;

procedure TForm1.ScrollBarMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FScrollBar.EndThumbDrag;
end;
```

### 直接使用 TyScrollThumbRect（自绘场景）

```pascal
uses tyControls.ScrollBar;

var
  Track: TRect;
  Thumb: TRect;
begin
  Track := Rect(0, 0, 16, 200);
  Thumb := TyScrollThumbRect(Track, sbVertical, 0, 90, 30, 10);
  // 在自己的 Canvas 上绘制 Thumb
  Canvas.FillRect(Thumb);
end;
```

## 9. 注意事项

1. **OnChange 防重入：** `SetPosition` 先夹紧值，若夹紧后与原值相同则不调用 `OnChange`，无需在回调中过滤重复值。
2. **SetMin/SetMax 自动夹紧 Position：** 修改 `Min` 或 `Max` 时若导致 `Position` 越界，会静默调整 `Position`（不触发 `OnChange`，仅触发 `Invalidate`）。
3. **BeginThumbDrag 的坐标系：** `AGrabPosAlongTrack` 和 `APosAlongTrack` 均为**控件客户区坐标**，垂直时取鼠标 Y，水平时取鼠标 X，与控件的 `ClientRect` 基准一致。
4. **退化情形：** 当 `Max <= Min` 或 `PageSize <= 0` 时，`TyScrollThumbRect` 返回整个轨道矩形（thumb 填满），此时拖动无意义。
5. **TabStop：** 独立摆放的 `TTyScrollBar` 是个键盘控件（方向键 / PgUp / PgDn / Home / End），`TabStop` published 且默认 `True`，和原生 `TScrollBar` 一致。六个宿主内嵌的条在代码里把它设成 `False`，不参与焦点循环；点它也不拿焦点，焦点交给宿主（宿主本身不参与焦点时原地不动，焦点已在宿主的行内编辑器里时也不动），方向键照旧落在宿主上。
6. **水平时默认尺寸不自动翻转：** `Kind` 改变后，控件的宽/高不会自动对调，需手动交换 `Width` 和 `Height`。
7. **滑块过渡动画（batch⑤+⑥）：** `AnimationsEnabled` 默认 `True`，程序化 `Position` 变化（键盘/滚轮/翻页/箭头）时滑块缓动到新位置（约 120ms），**拖动则始终瞬时跟手**；headless / 设计器下瞬间吸附。六个宿主（`TTyStringGrid` / `TTyDrawGrid`、`TTyListBox`、`TTyListView`、`TTyMemo`、`TTyScrollBox`、`TTyTreeView`）的**内嵌滚动条按设计置为静态**（`AnimationsEnabled := False`）；这**只关滑块缓动，不关自动隐藏的淡入淡出**。详见上文「状态过渡动画」。
8. **自动隐藏出厂是关的，但六个皮肤打开了它。** `win11` / `macos` / `fluent` / `material3` / `adwaita` / `ubuntu` 下滚动条闲 1200ms 就会淡掉，这是主题的决定，不是 bug。要按控件摁住它：`AutoHide := sbahNever`，或者宿主上的 `ScrollBarAutoHide := sbahNever`。详见 §7。

## 附：API parity 备注（本轮）

### `Kind` 默认值与 LCL 不同，有意保留

本库：`sbVertical`；LCL `TCustomScrollBar`：`sbHorizontal`（`stdctrls.pp:105`）。**不跟随**，理由与 `TTyTrackBar.Max` 一样：这只是一个默认值，不改变语义，而 published 默认值一改，**所有现有的竖向 `.lfm`（因为等于默认而没存盘）会静默变成横向**；本控件的构造函数默认尺寸（宽 = `--scrollbar-size`、高 = 160）也是竖向的。从 Lazarus 移植时请显式写 `Kind`。

### RTL 镜像：`MirrorHorizontal`，**不**跟 `BiDiMode`

横向滚动条在 RTL 下**原点在右端**：`Min` 在右，`Position` 变大滑块往**左**走。这是 Windows 对镜像窗口的既定行为，不是本库的选择。打开的方式是 `MirrorHorizontal := True`（默认 `False`）：

| 跟着翻的 | 不翻的 |
|---|---|
| 滑块位置（`TyScrollThumbRect` 的 `ARightToLeft` 参数） | 两端按钮的**字形**——左端仍是左箭头 |
| 拖拽的反算（放下的位置读回 `Position`） | 轨道矩形与按钮尺寸（本来就左右对称，翻了等于没翻） |
| 命中：点滑块=抓住，点轨道=往点击方向翻页 | `Home` / `End`（逻辑首尾，不是视觉首尾） |
| 左端按钮变成"加"，右端变成"减" | 滚轮（不是空间方向） |
| ← / → 跟着滑块走：← 让 `Position` 变大 | 竖向滚动条：**完全不受影响** |

字形不翻不是漏做：把"左端左箭头、右端右箭头"这一对镜像一次，得到的还是它自己——所以 Windows 的镜像横条看上去和普通横条一模一样，变的是滑块在哪、哪个按钮往哪走。

**为什么是 opt-in、不读 `BiDiMode`。** 本库里内嵌横向滚动条的有 `TTyGrid`、`TTyListView`、`TTyMemo`、`TTyTreeView`、`TTyScrollBox` 五个，它们的**内容**都还没镜像。滚动条自己读 `BiDiMode` 的话，就会出现"`Position=Min` 的滑块停在右边，而它驱动的文档还是从左边开始"——这正是这一轮一直在清的"画在一侧、点在另一侧"，只是上移了一层。宿主在**镜像自己内容的那次提交里**顺手打开它。`TTyScrollBox` 明确不打开，理由见 `docs/controls/scrollbox.md`。

绘制与命中共用 `TyScrollThumbRect` 同一次调用，翻转本身只有 `TyScrollMirrorOffset` 一处，绘制与拖拽反算都经过它——所以"只翻了一半"在结构上不可能。守卫在 `tests/test.rtl.pas`（`TRtlScrollBarGeometryTest` / `TRtlScrollBarControlTest`）。

`BidiMode` / `ParentBidiMode` 本身仍然不 published（全库一致，见 `docs/rtl.md`）。
