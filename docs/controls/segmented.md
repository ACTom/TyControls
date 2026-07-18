# TTySegmented

## 1. 概述

`TTySegmented` 是 TyControls 库中的主题化「分段控制器」控件，继承自 `TTyCustomControl`（窗口化控件，可获得焦点）。它把若干个**互斥**选项排成一行，装进同一条主题化的凹槽（track）里，其中恰有一个处于选中态。典型用途：视图模式切换（列表 / 网格 / 详情）、时间粒度（日 / 周 / 月）、单位切换（℃ / ℉）、图表口径切换——**切换的是一个「值」，不是一个「页面」**。

和相邻控件的边界：

- `TTyTabSet` / `TTyPageControl` 是**页签条**——页签是容器的装饰，点它切换的是**页面**；分段控制器不拥有任何页面、不能放子控件，它就是一个紧凑的取值部件。
- `TTyRadioGroup` 语义相同（单选一组选项），但要花掉一整个带标题的框 + 每个选项一个子控件；本控件只花一个控件、一行高度。

点击选中；**Left / Right 移动选中项**（Home / End 跳到两端）——这是它做成窗口化可聚焦控件的全部理由：图形控件没有句柄，既拿不到焦点也收不到按键。选中的那一段带上 `tysSelected` 状态，主题的 `:selected` 规则因此生效（与 `TTyButton.Down` 是同一个状态、同一条规则）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Segmented` |
| `GetStyleTypeKey` 返回值 | `'TySegmented'`（**凹槽本体**：`background` / `border-*` / `color` / `font-*` / `opacity` / `shadow` / `outline`） |
| 分段 typeKey | `'TySegmentedItem'`（**每一段**：`background` / `border-*` / `color` / `font-*` / `padding`；靠它的 `:selected` / `:hover` / `:disabled` 才读得出来） |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 240 × 30（逻辑像素，构造时设置） |

```pascal
uses tyControls.Segmented;
```

**为什么是窗口化控件（有句柄）？** 因为它要**取焦点**、要吃 **Left/Right 按键**——这两件事图形控件都做不到（没有句柄就没有焦点、收不到 key message）。这也正是它与同批次的 `TTyTag`（图形控件）分道的唯一原因。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Items` | `TStrings` | 空 | 各分段的文字，一行一段。用解析后的 `TySegmentedItem` 样式绘制（**不**读取 LCL `Font.*`）。段内**居中**，放不下时省略号截断（`Mon…`）。**不解析助记符**：没有 Alt+字母 通路，`&` 就是字面字符。 |
| `ItemIndex` | `Integer` | `-1` | 选中的分段，`-1` = 无。**越界即 `-1`**，不会被夹到端点上（见第 5 节）。 |
| `OnChange` | `TNotifyEvent` | `nil` | 见第 4 节。 |
| `AutoSize` | `Boolean` | `False` | 开启后凹槽贴合**最宽**的那条文字（每段都取该宽度 + 段的 `padding`，再加凹槽自身的 `--segmented-pad`）。 |

### 继承的通用成员

`TTySegmented` 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | **变体入口**：对应 `.tycss` 里 `TySegmented.<classname>`。解析分段时**带上同一个 `StyleClass`**，所以 `TySegmentedItem.small` 能跟着凹槽一起换。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |
| `TabStop` | `Boolean` | **`True`** | 默认参与 Tab 焦点链——按键导航是这个控件的立身之本。 |

另暴露 `Enabled` / `Font` / `Align` / `Anchors` / `OnClick` 及 `TTyCustomControl` 基线事件集（含 `OnKeyDown` / `OnEnter` / `OnExit` 等），见 [../events.md](../events.md)。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnChange` | `ItemIndex` **确实发生变化**时触发——点击、按键、代码赋值一视同仁（这是 `TTyListBox.ItemIndex` / `OnChange` 那一对的既有契约，本控件沿用）。重复设成同一个值不是变化，**不**触发。 |
| `OnClick` | `TControl` 基线点击事件，照常触发（分段控制器没有「吞掉点击」的手势，与 `TTyTag` 的 `x` 不同）。 |

> **两个「静默」的口径（有意为之，都有测试守护）：**
> - **编辑 `Items` 把选中项挤掉时**（如 `Items.Delete(2)` 而当前选中第 2 段）：`ItemIndex` 静默归 `-1`，**不触发 `OnChange`**。编辑列表是宿主自己的动作，不是一次用户选择——把宿主自己造成的后果再当成事件回敬给它，只会制造它没请求过的回调。
> - **流式加载（`.lfm`）带来的 `ItemIndex`**：在 `Loaded` 里静默应用。加载一张窗体不是用户选择，而此时 `.lfm` 里的 `OnChange` 处理器**已经挂上了**——在窗体还没显示时就告诉宿主「用户选了什么」是错的。

---

## 5. 关键成员

### 纯规则 / 几何函数（单元级，可无句柄直接调用）

```pascal
function TySegmentedItemRect(AClientWidth, AClientHeight, ACount, APad,
  AIndex: Integer): TRect;
function TySegmentedIndexAt(AClientWidth, AClientHeight, ACount, APad,
  X, Y: Integer): Integer;
function TySegmentedValidIndex(ACurrent, ACount: Integer): Integer;
function TySegmentedStepIndex(ACurrent, ACount, ADelta: Integer): Integer;
function TySegmentedPreferredWidth(ACount, AMaxTextWidth, AItemPadLeft, AItemPadRight,
  ATrackPad, AMinItemWidth: Integer): Integer;
```

全部整数入参、无控件状态、无句柄、无主题依赖，测试直接调用（`tests/test.segmented.pas`）。要点：

- **`TySegmentedItemRect`**：内容带 = 凹槽按 `APad`（`--segmented-pad`）**四边**内缩；各段**等分**该带并**精确铺满**——第 i 段的右边 **就是** 第 i+1 段的左边，既没有点击会掉进去的缝，也没有底片会漏出来的空隙。除不尽时用整数除法，各段宽度相差至多 1px（余数按 floor 边界自然分摊，不是堆到某一段）。
- **`TySegmentedIndexAt`** 是 `TySegmentedItemRect` 的**逆**（它就是扫描后者产出的矩形），所以**点到哪一段，就是画在那里的那一段**，两者永远不会漂移。凹槽的 `padding` 边沟不属于任何一段：点它返回 `-1`，**不清除**已有选择。
- **`TySegmentedValidIndex`**：越界 = `-1`（**无**），不夹到端点。要第 3 段而只有 3 段的调用方，想要的是一个不存在的段；悄悄给它最后一段是撒谎。
- **`TySegmentedStepIndex`**：Left/Right 的规则——两端**夹住、不回绕**（一行短选项一眼看得全，跑到头就该停，而不是瞬移到对面；与 `TTyCustomTabStrip` 的 VK_LEFT/RIGHT 一致）。从 `-1`（无选择）起步则**从来的那一端进入**：Right 取第一段，Left 取最后一段。
- **`TySegmentedPreferredWidth`** 是 `TySegmentedItemRect` 的**逆**：把它的结果当 `AClientWidth` 回喂（同 `ACount` / `APad`），每一段正好是「最宽文字 + 段 `padding`」那么宽（已有往返测试守护）。**所有段共用最宽者的宽度**——选项宽度参差的分段控制器看着就是坏的。

### 公开成员

```pascal
function Count: Integer;                    // 分段数
function TySegmentRect(AIndex: Integer): TRect;   // 第 AIndex 段的矩形(设备像素, (0,0)-local); 越界为空
function TySegmentAt(X, Y: Integer): Integer;     // 客户区 (X,Y) 落在哪一段; 边沟/界外为 -1
```

`TySegmentRect` / `TySegmentAt` 与绘制**同源**（同一对纯函数、同一份主题令牌），因此「画在哪」和「点得中哪」天然一致。

---

## 6. 状态与主题

### 支持的伪类状态

- **凹槽**（`TySegmented`）：`:hover` / `:active` / **`:focus`** / `:disabled` 由基类状态机计算。**焦点属于整个凹槽**，不属于某一段——这是平台上分段控制器的读法（整件描一圈焦点环，「当前是哪个」由底片自己说），也不需要额外代码：基类的 `CurrentStates` 已经把 `tysFocused` 给了凹槽的样式，`DrawFrame` 照常描 `outline`。
- **分段**（`TySegmentedItem`）：状态取的是**这一段自己的**——
  - `:selected`：`ItemIndex` 指向的那一段。**与 `TTyButton.Down` 注入的是同一个状态**，因此一条 `:selected` 规则同时管住「按下的按钮」和「选中的分段」。
  - `:hover`：指针精确落在该段上（**逐段**亮，不是整条凹槽一起亮）。
  - `:disabled`：控件 `Enabled = False` 时每一段都有。

> **`:disabled` 保留 `:selected`（有意偏离 `TTyButton`）：** `TTyButton.Down` 在禁用时会**丢掉** `tysSelected`；本控件**不丢**。选择是这个控件唯一要说的话，禁用时把底片弄没，读起来会变成「什么都没选」而不是「这个你改不了」。引擎的 `ResolveLayer` 把 `:selected` 当**静止层最先**应用、把 `:disabled` **最后**应用（最高优先级），所以底片留得住、而禁用的笔色照样压得过它——不需要控件里写任何分支。

### 主题令牌摘要

```css
TySegmented {
  background: var(--overlay-hover);     /* 凹槽:表面上一层淡淡的 on-surface 覆盖 */
  color: var(--on-surface);             /* 段标签的兜底笔色(见下方「降级」) */
  border-radius: var(--radius);
  font-size: var(--font-size-base);
}
TySegmented:focus    { outline: 2px var(--focus-ring); }   /* 焦点环描整件 */
TySegmented:disabled { opacity: var(--disabled-opacity); }

TySegmentedItem          { color: var(--muted);            /* 未选中:弱化 */
                           border-radius: var(--radius-sm);/* 比凹槽略小 => "滑块嵌在槽里" */
                           padding: 4px 10px;
                           font-size: var(--font-size-base); }
TySegmentedItem:hover    { background: var(--overlay-hover); color: var(--on-surface); }
TySegmentedItem:selected { background: var(--surface); color: var(--on-surface);
                           shadow: 0 1 2 #0000001F; }      /* 抬起来的滑块 */
TySegmentedItem:disabled { color: alpha(var(--on-surface), 0.38); }
```

> **变体是 `StyleClass`，不是枚举：** 控件对变体名一无所知，主题定义几个就有几个（`TySegmented.small` + `TySegmentedItem.small` 成对写，因为解析分段时带的是同一个 `StyleClass`）。语义色变体直接落在调色板上：`--accent` / `--danger` / **`--success`** / **`--warning`** 及其 `on(...)` 配对都是现成的（`--info` 就是 `--accent`，AntD 的 info 本就是品牌蓝，没有单独的 seed）。

**未定义时优雅降级**（均有测试守护）：

| 缺什么 | 结果 |
|--------|------|
| 整条 `TySegmented` 规则（无 `background`） | **什么都不画**——连分段也不画（哪怕 `TySegmentedItem` 有定义）。主题没认领这个 key，控件就不自己发明观感。 |
| `TySegmentedItem` 的 `background` | **不画底片**。只给 `:selected` 写填充的主题，因此白得「只有选中的那段有滑块」——控件里没有对应的分支。 |
| `TySegmentedItem` 的 `color` | 文字用**凹槽自己的** `color`。**绝不**回退到任何硬编码颜色。 |
| `TySegmentedItem` 的 `font-*` | 同上，回退到凹槽的字体令牌——只给 `TySegmented` 写了 `font-size` 的主题，段标签照样是对的字号。 |

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--segmented-pad` | `2`（= `TySegmentedPad`） | 凹槽**四边**的内缩：绕在滑块外面那一圈仍然可见的凹槽，正是「滑块嵌在槽里」而非「一排按钮」的由来 |
| `--segmented-min-width` | `48`（= `TySegmentedMinWidth`，与 `TyTabMinWidth` 一致，3 段分段器与 3 页签条节奏统一） | `AutoSize` 测量时单段宽度的下限——`A`/`B`/`C` 这种单字选项否则只有几个像素宽，点都点不中 |

两个常量都只是**该令牌的默认值**（主题两个都不写时才用得上），在每个调用点按 PPI 缩放到设备像素。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Segmented;

TyDefaultController.LoadTheme('themes/light.tycss');

var Seg: TTySegmented;

// 视图模式切换
Seg := TTySegmented.Create(Self);
Seg.Parent := Surface;
Seg.Items.Add('列表');
Seg.Items.Add('网格');
Seg.Items.Add('详情');
Seg.ItemIndex := 0;             // 代码赋值同样会触发 OnChange —— 这里先定初值、后挂处理器
Seg.OnChange := @HandleViewChange;
Seg.AutoSize := True;
Seg.Left := 16; Seg.Top := 16;
```

```pascal
procedure TForm1.HandleViewChange(Sender: TObject);
begin
  case (Sender as TTySegmented).ItemIndex of
    0: ShowListView;
    1: ShowGridView;
    2: ShowDetailView;
  end;
end;
```

**批量换选项时避免抖动**——先改 `Items` 再定选择（改 `Items` 会把越界的选择静默清成 `-1`）：

```pascal
Seg.Items.BeginUpdate;
try
  Seg.Items.Clear;
  Seg.Items.AddStrings(FNewModes);
finally
  Seg.Items.EndUpdate;
end;
Seg.ItemIndex := 0;   // 列表定型之后再选
```

---

## 8. 注意事项

- **它切「值」，不切「页」：** 需要切换**页面**请用 `TTyPageControl`；`TTySegmented` 不是容器，子控件不能以它为 `Parent`。
- **点击在「按下」时就选中**（不是抬起时）：分段控制器是个开关，家里的页签条（`TTyCustomTabStrip`）也是按下即切。按在边沟上（凹槽的 `padding`）是**惰性**的——返回 `-1`，不会把用户看得见的选择清掉。
- **越界 = 无选择，不是端点：** `ItemIndex := 7`（只有 3 段）得到 `-1`，不是 `2`。
- **Left/Right 两端夹住、不回绕；** Home/End 跳两端。所有被处理的按键都会被**吞掉**（`Key := 0`）；反过来，**禁用**或**空列表**时按键**不吞**——留给窗体去处理它本来要做的事（有测试守护）。
- **文字用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **不解析助记符：** 没有 Alt+字母 通路（选中靠鼠标和方向键），段文字里的 `&` 就是字面字符。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
