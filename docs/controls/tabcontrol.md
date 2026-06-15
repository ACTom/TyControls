# TTyTabControl

## 1. 概述

TTyTabControl 是 TyControls 库中的主题化标签页控件，继承自 `TTyCustomControl`。它在顶部渲染一排标签页头，每个页签对应一个 `TTyPanel` 页面板；同一时刻只有当前选中页可见。典型用途：分组设置面板、多步骤表单、属性面板等需要在同一区域切换多组内容的场景。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TabControl` |
| `GetStyleTypeKey` 返回值 | `'TyTabControl'` |
| 页签子部件 typeKey | `'TyTab'` |
| 关闭 × 底片子部件 typeKey | `'TyTabClose'` |

在 `.tycss` 文件中，控件外框对应选择器前缀 `TyTabControl`，各页签对应子部件选择器前缀 `TyTab`，可关闭页签的关闭 × 悬停底片对应 `TyTabClose`。

```pascal
uses tyControls.TabControl;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Tabs` | `TTyTabCollection` | 空集合 | 页签设计期集合（`TOwnedCollection`，元素为 `TTyTabItem`，各项有 published `Caption`）。可在 IDE 对象检查器 / 集合编辑器中增删页签，并随 `.lfm` 持久化；运行时的 `AddTab`/`RemoveTab` 也通过该集合工作。详见第 12 节 |
| `TabIndex` | `Integer` | `-1` | 当前选中页签的零基索引；-1 表示无选中页；赋值时自动裁剪越界值（低于 -1 → -1，大于末尾 → 末尾）；真变化才触发 `OnChange`。published，随 `.lfm` 持久化（载入期写入的值会延迟到 `Loaded` 应用）|
| `TabHeight` | `Integer` | `28` | 页签头条带的逻辑高度（96 DPI 基准像素），绘制时按实际 PPI 自动缩放 |
| `TabsClosable` | `Boolean` | `False` | 为 `True` 时每个页签头右侧渲染一个关闭 × 字形；点击该字形触发 `OnTabClose`。默认关闭，页签头不显示 × |
| `OnTabClose` | `TTyTabCloseEvent` | `nil` | 点击页签关闭 × 字形时触发；签名 `procedure(Sender: TObject; AIndex: Integer; var AllowClose: Boolean)`。详见第 4、11 节 |
| `OnChange` | `TNotifyEvent` | `nil` | 仅当 `TabIndex` 发生真实变化时触发，相同值重复赋值不触发 |
| `TabStop` | `Boolean` | `True` | 控件可通过 Tab 键获得键盘焦点 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### 自有 public 属性与方法

| 成员 | 类型/签名 | 说明 |
|------|-----------|------|
| `Pages[AIndex: Integer]` | `TTyPanel`（只读，indexed property） | 返回指定索引处的页面板；越界返回 `nil` |
| `AddTab(const ACaption: string): TTyPanel` | 方法 | 追加一个新页签，返回对应的 `TTyPanel` 页面板；第一个页签被追加时自动选中（`TabIndex := 0`），不触发 `OnChange` |
| `RemoveTab(AIndex: Integer): void` | 方法 | 移除指定索引的页签及其页面板（连同释放页面板）；自动修正 `TabIndex`；仅当当前活动页因此改变时才触发 `OnChange`。详见第 11 节 |
| `TabCount: Integer` | 方法 | 当前页签数量 |
| `TabCaption(AIndex: Integer): string` | 方法 | 返回指定索引的页签标题；越界返回空字符串 |
| `TyTabHeaderRect(AIndex: Integer): TRect` | 方法 | 返回指定页签头的设备像素矩形（以控件 (0,0) 为原点），主要用于测试与自定义命中检测 |
| `TyTabCloseRect(AIndex: Integer): TRect` | 方法 | 返回指定页签关闭 × 字形的命中矩形（设备像素，控件 (0,0) 本地坐标）；`TabsClosable = False` 或索引越界时返回空矩形 `(0,0,0,0)`，主要用于测试与自定义命中检测 |
| `TyTabHoverClose` | `Integer`（只读 property） | 鼠标当前悬停其关闭 × 的页签索引；无则为 -1。由 `MouseMove`/`MouseLeave` 驱动，独立于整页签悬停。详见第 14 节 |
| `TyHeaderStripWidth: Integer` | 方法 | 所有页签头未偏移时的总宽度（设备像素）。详见第 13 节 |
| `TyMaxHeaderScroll: Integer` | 方法 | 当前 PPI 下页签头条带最大可滚动量（设备像素）；条带未溢出时为 0 |
| `TyTabScrollLeftRect / TyTabScrollRightRect: TRect` | 方法 | 溢出时左/右滚动箭头按钮的矩形（设备像素，控件 (0,0) 本地坐标）；条带未溢出时为空矩形 `(0,0,0,0)` |
| `HeaderRectShifted(AIndex: Integer): TRect` | 方法 | 指定页签头按当前滚动偏移平移后的矩形（设备像素）；越界返回空矩形 |
| `SetHeaderScroll(AValue: Integer): void` | 方法 | 设置页签头条带的滚动偏移（设备像素），自动裁剪到 `[0, TyMaxHeaderScroll]` 并重绘 |
| `ScrollTabIntoView(AIndex: Integer): void` | 方法 | 调整滚动偏移，使指定页签头完整落入可见带内 |
| `TyDragThresholdPx(APPI: Integer): Integer` | 方法 | 按下后判定为拖拽重排（而非点击）所需的最小移动距离（设备像素，按 PPI 缩放；96 DPI 下为 6）|
| `TyDropIndexAt(X, APPI: Integer): Integer` | 方法 | 给定设备像素横坐标 X，返回拖拽应落入的集合索引（以平移后页签头中点判定，纯计算不改状态）|

### 继承的通用成员

每个 TyControls 控件都从 `TTyCustomControl`（`tyControls.Base`）继承以下两个 published 属性：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器；为 `nil` 时自动回退到全局默认控制器 |

---

## 4. 事件与方法

| 事件/方法 | 类型/签名 | 触发时机/说明 |
|-----------|-----------|---------------|
| `OnChange` | `TNotifyEvent` | `TabIndex` 发生真实变化后触发（相同值重复赋值不触发） |
| `OnTabClose` | `TTyTabCloseEvent` | 点击页签关闭 × 字形时触发；通过 `var AllowClose` 决定是否真正移除（置 `False` 即否决） |
| `AddTab(const ACaption): TTyPanel` | 函数 | 见属性表；追加页签并返回页面板 |
| `RemoveTab(AIndex)` | 过程 | 移除指定页签及其页面板并释放之；修正 `TabIndex`，必要时触发 `OnChange`（详见第 11 节） |
| `TabCount` | `Integer` 函数 | 返回当前页签数量 |
| `TabCaption(AIndex)` | `string` 函数 | 返回指定页签的标题文字 |
| `TyTabHeaderRect(AIndex)` | `TRect` 函数 | 返回指定页签头的几何矩形（设备像素，控件本地坐标） |
| `TyTabCloseRect(AIndex)` | `TRect` 函数 | 返回指定页签关闭 × 字形的命中矩形（设备像素，控件本地坐标）；非可关闭或越界时为空矩形 |

### TTyTabCloseEvent 签名

```pascal
TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer;
  var AllowClose: Boolean) of object;
```

- `AIndex`：被点击关闭的页签索引（零基）。
- `AllowClose`：进入回调时为 `True`。保持 `True` 则控件随后自动调用 `RemoveTab(AIndex)` 移除该页签；在回调中置 `False` 即否决本次关闭，页签保持不变。
- 未赋 `OnTabClose` 时，点击 × 等同于直接放行（自动 `RemoveTab`）。

---

## 5. 状态与主题

### TyTabControl — 控件外框

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 控件获得键盘焦点 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

### TyTab — 页签子部件

`TyTab` 是子部件 typeKey，不对应独立控件，由 TTyTabControl 内部渲染每个页签头时使用。

| 伪类 | 触发条件 |
|------|----------|
| 无状态（普通行） | 页签未选中且鼠标未悬停 |
| `:hover` | 鼠标悬停在该页签头上（未选中） |
| `:active` | 该页签当前被选中（`TabIndex = i`） |

> 注意：`:active` 在 `TyTab` 上表示"当前选中页签"，而非"鼠标按下"。这与其他控件的 `:active` 语义（鼠标按住）不同，是有意为之的设计：选中态在外观上应当持续高亮，而不仅在按下瞬间生效。

### light.tycss 内置规则摘要

```css
TyTabControl {
  background: var(--surface);        /* #FFFFFF */
  color: var(--on-surface);          /* #1F2937 */
  border-color: var(--border);       /* #D1D5DB */
  border-width: 1px;
  border-radius: var(--radius);      /* 6px */
}
TyTabControl:hover    { border-color: darken(--border, 10%); }      /* 悬停描边加深（Batch ④） */
TyTabControl:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }  /* 焦点边框 + 焦点环 */
TyTabControl:disabled { opacity: 0.5; }                             /* 禁用半透明（Batch ④） */

TyTab {
  background: darken(--surface, 5%);
  color: var(--on-surface);
  padding: 4px;
  border-radius: var(--radius) var(--radius) 0 0;
}
TyTab:hover  { background: darken(--surface, 2%); }
TyTab:active { background: var(--surface); color: var(--accent); }

/* 可关闭页签的关闭 × 悬停底片（tier-a 着色面） */
TyTabClose { background: var(--overlay-hover); border-radius: var(--radius); }
```

> **状态等价性（Batch ④）：** `TyTabControl` 补齐了 `:hover`（描边加深）、`:focus`（蓝色边框 + 焦点环）、`:disabled`（`opacity` 半透明）三条规则，与 `TyEdit` / `TyListBox` 等控件的状态外观对齐。`:focus` 不仅改 `border-color`，还经 `outline` 绘制一圈焦点环。

---

## 6. 布局机制（AdjustClientRect）

TTyTabControl 重写了 `AdjustClientRect`，在客户区顶部保留 `TabHeight` 逻辑像素（按 PPI 缩放后）供页签头条带使用：

```
控件矩形
┌──────────────────────────────────┐
│  [页签1]  [页签2]  [页签3]       │  ← TabHeight（默认28 px @ 96 DPI）
├──────────────────────────────────┤
│                                  │
│   客户区（alClient 页面板自动     │
│   填满此区域）                   │
│                                  │
└──────────────────────────────────┘
```

因为 `AdjustClientRect` 会偏移顶部，以 `Align = alClient` 创建的页面板会自动落在页签头条带以下，无需手动计算位置。

---

## 7. Controller 传播

`TTyTabControl` 在两处将自身的 `Controller` 自动传播给各页面板：

1. **`AddTab` 时**：新建页面板后立即将 `Self.Controller` 赋给它；
2. **`SetController` 时**：控件自身的 `Controller` 改变时，遍历所有已存在的页面板并同步更新。

这保证了即使先创建页签再切换 Controller，所有页面板也始终与外框使用同一套主题渲染。

---

## 8. 键盘操作

| 按键 | 行为 |
|------|------|
| `Ctrl+Tab` | 切换到后一页签；**循环**（在最后一个页签时回到第 0 页） |
| `Ctrl+Shift+Tab` | 切换到前一页签；**循环**（在第 0 页时回到最后一页） |
| `Ctrl+PageDown`（Ctrl+VK_NEXT） | 切换到后一页签；已在最后一个页签时不动（**钳制**，不循环） |
| `Ctrl+PageUp`（Ctrl+VK_PRIOR） | 切换到前一页签；已在第一个页签时不动（**钳制**，不循环） |
| `Home`（VK_HOME） | 跳到第一个页签（索引 0） |
| `End`（VK_END） | 跳到最后一个页签 |
| `←`（VK_LEFT） | 切换到前一页签；已在第一个页签时不动（钳制，不循环） |
| `→`（VK_RIGHT） | 切换到后一页签；已在最后一个页签时不动（钳制，不循环） |

> `Ctrl+Tab` / `Ctrl+Shift+Tab` 循环换页；`Ctrl+PageDown` / `Ctrl+PageUp` 与 `←` / `→` 仅在两端之间步进、到端即止（不循环）。

切换页签通过 `TabIndex :=` 路由到 `SetTabIndex`：钳制越界、显示目标页、将其滚入可见区（`ScrollTabIntoView`）并触发 `OnChange`。每个被处理的按键消费后不再传递（`Key := 0`）。控件需要获得焦点（`TabStop = True`，默认启用）才能响应键盘。

---

## 9. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.TabControl;

// 加载主题（通常在窗体 Create 最顶部执行一次）
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建 TabControl
var TC: TTyTabControl;
TC := TTyTabControl.Create(Self);
TC.Parent := Self;
TC.SetBounds(16, 16, 400, 260);
TC.OnChange := @HandleTabChange;

// 添加页签，AddTab 返回页面板
var Page1: TTyPanel;
Page1 := TC.AddTab('基本设置');

var Page2: TTyPanel;
Page2 := TC.AddTab('高级');

var Page3: TTyPanel;
Page3 := TC.AddTab('关于');

// 向页面板里放控件，像操作普通 TTyPanel 一样
var Lbl: TTyLabel;
Lbl := TTyLabel.Create(Page1);
Lbl.Parent := Page1;
Lbl.SetBounds(12, 12, 200, 24);
Lbl.Caption := '这里是"基本设置"页的内容';

// 切换到第二页（0-based）
TC.TabIndex := 1;
```

完整可运行示例参见 `examples/tabcontrol/`。

---

## 10. 注意事项

- **页签溢出可横向滚动**（v1.10）：当所有页签头宽度之和超过控件宽度时，页签头条带可横向滚动——条带两端显示 ◀ / ▶ 滚动箭头按钮，鼠标在条带上滚轮也能滚动，且切换选中页时会自动把该页签滚入可见区。详见第 13 节。
- **`AddTab` 第一个页签自动选中**：首次调用 `AddTab` 时，控件会直接将 `FTabIndex` 置为 0 并显示该页，不经过 `SetTabIndex` 设置器，因此不触发 `OnChange`。后续调用 `AddTab` 追加更多页签时，当前选中页不变。
- **页面板由 TabControl 拥有**：`AddTab` 创建的 `TTyPanel` 以 `TTyTabControl` 为 Owner，无需也不应手动释放它们——TabControl 析构时会自动释放。
- **`TabIndex = -1`**：赋值为 -1 时所有页面板均隐藏；正常使用时无需主动赋 -1（添加第一个页签后控件会自动选中第 0 页）。
- **子部件 `TyTab` 的 `:active` 含义**：指"被选中"，而非通用控件中的"鼠标按下"。主题作者为 `TyTab:active` 设置样式即可控制当前选中页签的高亮外观。
- **活动页签头切换交叉淡入（batch⑤+⑥）**：切换 `TabIndex` 时，**页签头**的活动高亮（`TyTab:active` 着色）会在新旧页签之间交叉淡入，而**页面板（内容）瞬间切换**。由 `AnimationsEnabled`（默认 `True`）控制；headless / 设计器下瞬间吸附。详见第 15 节。

---

## 11. 可关闭页签与运行时移除（v1.4）

### TabsClosable 与关闭 × 字形

将 `TabsClosable` 置为 `True` 后，每个页签头右侧绘制一个关闭 × 字形。`TabsClosable` 默认为 `False`，此时页签头不显示 ×。用户点击某个页签的 × 时，控件触发 `OnTabClose`。

`TyTabCloseRect(AIndex)` 返回该 × 字形的命中矩形（设备像素，控件 (0,0) 本地坐标），主要供测试与自定义命中检测使用；当 `TabsClosable = False` 或索引越界时返回空矩形 `(0,0,0,0)`。

### OnTabClose 与否决关闭

`OnTabClose` 签名为 `procedure(Sender: TObject; AIndex: Integer; var AllowClose: Boolean)`：

- 进入回调时 `AllowClose = True`；
- 保持 `True`（或未挂接 `OnTabClose`）→ 控件随后自动调用 `RemoveTab(AIndex)` 移除该页；
- 在回调中将 `AllowClose := False` → **否决**本次关闭，页签保持不变。

```pascal
procedure TForm1.TabClosing(Sender: TObject; AIndex: Integer;
  var AllowClose: Boolean);
begin
  // 禁止关闭第 0 页（例如"常规"页常驻）
  if AIndex = 0 then
    AllowClose := False;
end;

// 启用可关闭页签并挂接回调
TC.TabsClosable := True;
TC.OnTabClose   := @TabClosing;
```

### RemoveTab(AIndex)

`RemoveTab(AIndex)` 移除指定索引的页签及其页面板（连同 `Free` 释放页面板）。其行为：

- **修正 `TabIndex`**：
  - 全部页签删完 → `TabIndex` 变为 `-1`；
  - 删除位置在当前选中页之前（`AIndex < TabIndex`）→ `TabIndex` 自动减 1，保持选中同一页；
  - 删除的正是当前选中页（`AIndex = TabIndex`）且它是末尾页 → `TabIndex` 回退到新的末尾页；
  - 删除的正是当前选中页且它不是末尾页（中间页）→ `TabIndex` 数值不变，原本其后一页移入该索引并成为新的活动页；
  - 删除位置在当前选中页之后（`AIndex > TabIndex`）→ `TabIndex` 不变，仍选中同一页。
- **`OnChange` 触发条件**：仅当移除导致**当前活动页面板发生改变**时才触发 `OnChange`；若移除的是非活动页（活动页面板不变），不触发。

也可不依赖 ×，直接在代码中调用 `RemoveTab` 进行运行时移除：

```pascal
TC.RemoveTab(2);   // 移除第 3 个页签（0-based）及其页面板
```

### 外部释放页面板的安全处理

即便绕过 `RemoveTab`、在外部直接 `Free` 某个页面板，控件也能安全处理：`TTyTabControl` 重写了 `Notification`，在收到 `opRemove` 通知时自动把该页面板从内部数组中摘除（修正 `TabIndex`、刷新显示），**不会留下悬挂指针**。因此外部释放页面板与调用 `RemoveTab` 在数据结构层面是一致且安全的（区别仅在于是否由控件代为 `Free`）。

---

## 12. 设计期页签（v1.7）

### Tabs 集合

`TTyTabControl` 暴露了一个 published 的 `Tabs` 集合属性，用于在 IDE 中直接编辑页签，而无需在代码里调用 `AddTab`：

- `Tabs` 的类型是 `TTyTabCollection`（继承自 `TOwnedCollection`），其元素类型为 `TTyTabItem`。
- `TTyTabItem` 有一个 published 的 `Caption: string` 属性（即页签标题），并通过 `GetDisplayName` 在集合编辑器中以标题显示；其托管的页面板以只读属性 `Page: TTyPanel` 暴露（不参与流式化，由控件按需创建）。
- 集合会随 `.lfm` 持久化：每个页签项的 `Caption` 写入流，对应的页面板作为嵌套的 `object TTyPanel` 子控件块单独流式化。
- 选中页通过 published `TabIndex`（默认 -1）同样随 `.lfm` 往返；载入期写入的 `TabIndex` 会被捕获并在 `Loaded` 中应用。

### 在 IDE 中编辑页签

设计期注册（`tyControls.Design`）为 `Tabs` 提供了两条访问途径：

1. **集合属性编辑器**：在对象检查器中为 `Tabs` 属性注册了标准的 `TCollectionPropertyEditor`，点击 `Tabs` 旁的 `...` 即可打开标准集合编辑对话框，增删页签、编辑各项 `Caption`。
2. **"Edit Tabs..." 组件动词**：注册了组件编辑器 `TTyTabControlEditor`，在控件右键上下文菜单中提供 **"Edit Tabs..."** 项，直接打开同一个集合编辑器（`EditCollection(..., Tabs, 'Tabs')`）。

> 在演示工程中，页签即定义在 `.lfm` 里（而非运行时代码）。

### 集合与运行时 API 的关系

`Tabs` 集合是页签的**唯一权威来源**，内部的标题数组与页面板数组始终与它保持同步：

- `AddTab(caption)` 实际上是向 `Tabs` 集合 `Add` 一个新项并设置其 `Caption`，集合的 `Notify(cnAdded)` 创建对应页面板，返回值仍是该页面板（`Item.Page`）。
- `RemoveTab(AIndex)` 删除对应页面板时，会同步从 `Tabs` 集合删除对应项（反之，从集合删除某项也会摘除并释放其页面板）。
- 因此无论是设计期通过集合编辑器增删，还是运行时调用 `AddTab` / `RemoveTab`，最终都经过同一条同步路径，二者可以混用。

```pascal
// 运行时也可直接操作 Tabs 集合
var Item: TTyTabItem;
Item := TC.Tabs.Add;
Item.Caption := '新页';
// Item.Page 即该页签的页面板
```

---

## 13. 页签溢出横向滚动（v1.10）

当所有页签头的宽度之和超过控件宽度时，页签头条带进入溢出模式，可横向滚动：

- **滚动箭头按钮**：条带左右两端各渲染一个箭头字形按钮（`tgArrowLeft` / `tgArrowRight`）。点击左/右箭头按当前 PPI 缩放后的 ~40 逻辑像素步进滚动条带（自动裁剪到合法范围）。
- **鼠标滚轮**：鼠标位于页签头条带上方时滚动滚轮即可横向滚动条带（向上/向后滚减小偏移，向下/向前滚增大偏移）；步进同样约 40 逻辑像素。用户挂接的滚轮处理器优先消费。
- **自动滚入可见区**：切换选中页时（含键盘 ← / →），若目标页签头不完整可见，控件会自动调整滚动偏移把它滚入可见带内（`ScrollTabIntoView`）。
- 溢出时绘制会将页签头裁剪到两个箭头之间的可见带，箭头按钮始终绘制在最上层，不会被平移后的页签头覆盖；条带未溢出时不保留箭头带、滚动偏移恒为 0。

相关只读几何方法（设备像素、控件 (0,0) 本地坐标），主要供测试与自定义命中检测：

| 方法 | 含义 |
|------|------|
| `TyHeaderStripWidth` | 所有页签头未偏移时的总宽度 |
| `TyMaxHeaderScroll` | 最大可滚动量；未溢出时为 0 |
| `TyTabScrollLeftRect` / `TyTabScrollRightRect` | 左 / 右箭头按钮矩形；未溢出时为空矩形 |
| `HeaderRectShifted(AIndex)` | 指定页签头按当前滚动偏移平移后的矩形 |

也可在代码中直接控制滚动：`SetHeaderScroll(AValue)` 设置偏移（裁剪到 `[0, TyMaxHeaderScroll]`），`ScrollTabIntoView(AIndex)` 把指定页签滚入可见区。

---

## 14. 拖拽重排与关闭 × 独立高亮（v1.10）

### 拖拽重排页签

可通过按住并拖拽页签头来重排页签顺序：

- 在某页签头上按下左键时，控件先将其选中，并把它**预备**为拖拽候选（记下按下位置）。
- 若指针随后移动超过拖拽阈值（`TyDragThresholdPx`，按 PPI 缩放的小阈值，96 DPI 下为 6 设备像素），手势从"点击"切换为实时重排；移动不足阈值即松开则仍是一次普通点击（只选中、不重排）。
- 进入重排后，每次移动会按指针当前 X 解析出的落点索引（以平移后页签头中点判定，见 `TyDropIndexAt`）重新落位被拖页签——通过把对应 `Tabs` 集合项的 `Index` 改为目标位置实现，集合随即同步内部数组（活动选中跟随页面板对象本身，而非索引）。
- 松开左键（`MouseUp`）或指针离开控件（`MouseLeave`）即解除拖拽候选，避免无新按下时的误触重排。

```pascal
// 阈值与落点为纯计算，可用于测试或自定义命中
PxThreshold := TC.TyDragThresholdPx(96);   // 96 DPI 下 = 6
DropIdx     := TC.TyDropIndexAt(X, 96);     // X 处应落入的页签索引
```

### 关闭 × 的独立 :hover 高亮

当 `TabsClosable = True` 时，关闭 × 字形拥有**独立于整页签**的悬停高亮：

- 仅当指针精确落在某页签的关闭 × 命中矩形内时，该 × 才点亮——在 × 后面绘制一块圆角底片，× 字形本身以全不透明度叠加，使关闭目标一目了然。
- **底片样式由子部件 typeKey `TyTabClose` 驱动（Batch ④，tier-a 着色面）：** 底片色取 `TyTabClose` 的 `background`（默认 `var(--overlay-hover)`——基于前景色的半透明叠加），圆角取其 `border-radius`（默认 `var(--radius)`）。这取代了早前写死的"半径 3 + alpha 48"两个魔法常量，使关闭底片的颜色与圆角可在主题中统一定制。
- **× 笔画本身仍是 tier-b 单色字形，** 墨色取 `TyTab` 的 `color`（`TextColor`）。换言之关闭 × = `TyTabClose` 底片（tier-a）+ `TyTab.color` 墨迹（tier-b），详见 [tycss-reference.md](../tycss-reference.md) §8.3。
- 当前被悬停其 × 的页签索引可通过只读属性 `TyTabHoverClose` 读取（无则为 -1），由 `MouseMove` / `MouseLeave` 驱动；它与整页签悬停（影响 `TyTab:hover` 外观）相互独立。
- 拖拽重排进行中不视为关闭 × 悬停，任何残留高亮会被清除。

---

## 15. 活动页签头交叉淡入（batch⑤+⑥）

切换选中页时，`TTyTabControl` 让**活动页签头**的高亮在新旧页签之间**交叉淡入**，由 `tyControls.Animation` 单元的 `TTyAnimator` 驱动。**仅页签头参与动画——页面板（内容区）瞬间切换**，不淡入淡出。

### 开关属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AnimationsEnabled` | `Boolean` | `True` | 是否启用活动页签头交叉淡入动画。**public 属性，不 published**（不写入 `.lfm`），需在代码中设置。 |

> 这是唯一的动画开关，**没有**单独的时长 / 缓动曲线属性可供配置——时长与缓动在控件内部固定。

### 行为

- **启用（`True`，默认）且控件已分配窗口句柄（`HandleAllocated`）时：** 改变 `TabIndex`（点击 / 键盘 / 赋值）后，旧活动页签头的 `TyTab:active` 着色淡出、新活动页签头淡入，时长约 **120ms**，缓动曲线 `teEaseOutCubic`。页面板内容在切换的同一时刻立即显示/隐藏，**不**参与淡入。
- **关闭（`False`）：** 页签头高亮瞬间切换到新活动页签。
- 控件尚无窗口句柄（headless / 设计器）时，无论开关如何都**瞬间吸附到终态**（**headless-snap**）——因此既有的逐像素页签头测试不受影响。
- 内部按需创建一个 `TTimer`（约 60fps）推进动画，抵达目标后自动停止；动画逻辑可在测试中以显式毫秒步进确定性驱动。

```pascal
// AnimationsEnabled 默认即为 True（活动页签头交叉淡入）；
// 如需瞬时切换可显式关闭：TC.AnimationsEnabled := False;
TC.TabIndex := 2;   // 第 3 页签头高亮交叉淡入（约 120ms）；对应页面板瞬间显示
```
