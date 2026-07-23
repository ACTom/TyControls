# TTyTabSet

## 1. 概述

`TTyTabSet` 是 TyControls 库中的**纯页签条**控件，继承自 `TTyCustomTabStrip`（SP1 页签头引擎，位于 `tyControls.TabStrip`）。它**只是一条页签标题栏**——渲染 / 悬停 / 溢出滚动 / 关闭 × / 拖拽重排 / 键盘导航全由引擎负责，但它**不承载任何页面容器**（与 `TTyPageControl` 不同）。页签标题存放在一个 `TStrings`（`Tabs`）里，"选中态"仅由 `TabIndex` + `OnChange` 表达。典型用途：需要一排可切换标签、但内容切换由业务代码自行处理的场景（如自定义视图切换器、筛选条）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TabSet` |
| `GetStyleTypeKey` 返回值 | `'TyTabControl'` |
| 基类 | `TTyCustomTabStrip`（`tyControls.TabStrip`，继承自 `TTyCustomControl`） |
| 默认尺寸 | 240 × 32（逻辑像素，`Create` 中设置） |

在 `.tycss` 文件中，该控件对应的选择器前缀为 **`TyTabControl`**（外框），页签头本身用子部件选择器 **`TyTab`** / **`TyTab:hover`** / **`TyTab:active`**，关闭 × 悬停片用 **`TyTabClose`**。

> **注意：** `GetStyleTypeKey` 刻意返回 `'TyTabControl'`（与 `TTyTabControl` 复用同一套外框主题令牌），而非 `'TyTabSet'`——`.tycss` 中并没有 `TyTabSet` 选择器。

```pascal
uses tyControls.TabSet;
```

---

## 3. 属性表

### 自有 published 属性

`TTyTabSet` 在**本类**上仅新增两个 published 属性：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Tabs` | `TStrings` | `[]`（空列表） | 页签标题列表。内部由 `TStringList` 支撑（以获得其 `OnChange`），但声明类型为 `TStrings`。写入时调用 `Assign` 复制内容；列表变化（增删改）触发重绘并把 `TabIndex` 上界夹紧到 `Count-1`。 |
| `TabIndex` | `Integer` | `-1` | 当前选中页签索引；`-1` 表示无选中。写入等价于调用 `SetTabIndex`（夹紧、触发 `OnChanging` 否决钩子、`DoSelectTab`、`OnChange`）。声明了 `default -1`。 |

### 继承自 `TTyCustomTabStrip` 的 published 成员

引擎在基类的 `published` 段暴露了以下成员，`TTyTabSet` 一并继承：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `TabHeight` | `Integer` | `28` | 页签条高度（逻辑像素）；写入夹紧到 `>= 1`。 |
| `TabsClosable` | `Boolean` | `False` | 为 `True` 时每个页签头右侧渲染关闭 × 字形，点击触发 `OnTabClose`。 |
| `TabStop` | `Boolean` | `True` | 参与键盘 Tab 焦点循环（`Create` 中设 `True`）。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |

> `AnimationsEnabled`（`Boolean`，默认 `True`）在基类声明为 **`public` 而非 `published`**——可在运行时读写，但**不写入 `.lfm`/`.dfm`**。作用：切换页签时是否对新激活页签头做背景交叉淡入；无窗口句柄时直接吸附到终态（保证无头像素测试稳定）。

### 继承的通用成员

`TTyCustomTabStrip` 继承自 `TTyCustomControl`：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

### 状态跟踪字段（protected，不 published）

引擎在基类维护交互状态，`TTyTabSet` 渲染时读取：

| 字段 | 类型 | 说明 |
|------|------|------|
| `FTabIndex` | `Integer` | 当前选中索引（`Tabs` 中命中的页签渲染为 `TyTab:active`） |
| `FHoverTab` | `Integer` | 鼠标悬停的页签索引（`-1`=无），触发该页签的 `TyTab:hover` |
| `FHoverClose` | `Integer` | 关闭 × 被悬停的页签索引（`-1`=无），只读暴露为 `TyTabHoverClose` |
| `FTabsClosable` | `Boolean` | `TabsClosable` 的后备字段 |
| `FDragTab` / `FDragging` / `FDragOrigin` | `Integer` / `Boolean` / `Integer` | 拖拽重排手势状态 |
| `FHeaderScroll` / `FShowScrollAffordance` | `Integer` / `Boolean` | 页签溢出时的横向滚动偏移与左右箭头显隐 |

---

## 4. 事件

`TTyTabSet` 自身**不新增事件**；下列专有事件全部由基类 `TTyCustomTabStrip` published，直接继承可用：

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | `TabIndex` 实际改变（选中另一页签）后触发；被 `OnChanging` 否决或设为当前值不触发。 |
| `OnChanging` | `TTyTabChangingEvent` | 切换**之前**；签名 `(Sender; ANewIndex: Integer; var AllowChange: Boolean)`，把 `AllowChange := False` 即可**否决**切换（不改 `TabIndex`、不触发 `OnChange`、无淡入）。`csLoading` 流式加载期间**不**触发。 |
| `OnTabClose` | `TTyTabCloseEvent` | 点击页签头关闭 × 时触发；签名 `(Sender; AIndex: Integer; var AllowClose: Boolean)`，进入时 `AllowClose = True`。放行则控件自动从 `Tabs` 移除该页签并修正 `TabIndex`；置 `False` 否决关闭。 |
| `OnReorder` | `TTyTabReorderEvent` | 一次拖拽重排手势提交后触发一次；签名 `(Sender; AFromIndex, AToIndex: Integer)` 报告净移动。纯点击不触发。 |

> 除上表外，`TTyTabSet` 还暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因其为可聚焦的 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

外框（`TyTabControl`）与页签头（`TyTab`）使用不同的状态：

| 选择器 | 伪类 | 触发条件 |
|--------|------|----------|
| `TyTabControl` | `:hover` | 鼠标悬停控件 |
| `TyTabControl` | `:focus` | 获得键盘焦点 |
| `TyTabControl` | `:disabled` | `Enabled = False` |
| `TyTab` | `:hover` | 鼠标悬停在该页签头（`FHoverTab`） |
| `TyTab` | `:active` | 该页签为当前选中项（`I = FTabIndex`） |

> **`TyTab:active` = 选中态：** 引擎渲染时把 `I = FTabIndex` 的页签头解析为 `[tysActive]`，因此"选中"用 `:active` 表达；悬停但未选中的页签用 `:hover`，其余用 `:normal`。切换页签时新激活头的背景从 inactive 交叉淡入到 active（约 120ms，`AnimationsEnabled` 控制，无句柄时吸附）。

### light.tycss 内置规则摘要

外框（复用 `TyTabControl` 令牌）：

```css
TyTabControl {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
}
TyTabControl:hover    { border-color: var(--input-border-hover); }
TyTabControl:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyTabControl:disabled { opacity: var(--disabled-opacity); }
```

页签头与关闭片：

```css
TyTab {
  background: var(--surface-tab-rest);
  color: var(--on-surface);
  padding: 4px;
  border-radius: var(--radius) var(--radius) 0 0;  /* 顶部圆角 */
}
TyTab:hover  { background: var(--surface-tab-hover); }
TyTab:active { background: var(--surface); color: var(--accent); }  /* 选中：白底 + accent 文字 */
/* TyTabClose：关闭 × 悬停时的令牌驱动底片（--overlay-hover 填充 + --radius 圆角） */
```

**渲染细节：** 控件顶部为高 `TabHeight` 的页签条，其下**只画一条基线**（用 `TyTabControl` 的 `border-color` / `border-width`，落在页签条底部上叠 1px 处），**不画内容区外框** —— 本控件不承载页面，画框只会在页签下方留一个空盒子（`Height > TabHeight` 时尤其明显）。托管页面的 `TTyPageControl` 仍然画完整外框，两者由基类 `HasPageBody` 区分。因此把 `Height` 设成等于 `TabHeight` 最干净：页签条就是控件本身，下方内容由宿主自己摆放。页签头宽度 = 文本宽度 + `2×padding`，最小 `TyTabMinWidth`；可关闭时右侧预留关闭 × 槽位。页签总宽超过控件宽度时，两端出现左右箭头（`tgArrowLeft`/`tgArrowRight`），支持点击箭头、滚轮、`ScrollTabIntoView` 横向滚动。关闭 × 用 `tgClose` 字形以 `TextColor` 绘制，悬停时其下垫一块 `TyTabClose` 令牌片。**只有页签头背景参与淡入动画**，文本 / 字形 / 几何不受影响。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.TabSet;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var Bar: TTyTabSet;
Bar := TTyTabSet.Create(Self);
Bar.Parent := Self;
Bar.SetBounds(20, 56, 480, 34);
Bar.TabHeight := 32;

// Tabs：TStrings，逐条添加标题
Bar.Tabs.Add('概览');
Bar.Tabs.Add('详情');
Bar.Tabs.Add('通知(锁定)');
Bar.Tabs.Add('设置');

Bar.TabIndex := 0;          // 初始选中第一个页签
Bar.TabsClosable := True;   // 页签头显示关闭 ×

Bar.OnChange   := @TabChanged;
Bar.OnChanging := @TabChanging;   // 切换前否决钩子
Bar.OnTabClose := @TabClosing;    // 关闭否决钩子
Bar.OnReorder  := @TabReordered;  // 拖拽重排提交

// 切换回调：读取当前页签
procedure TMainForm.TabChanged(Sender: TObject);
begin
  ShowMessage(Format('当前页签：%s（TabIndex=%d）',
    [Bar.TabCaption(Bar.TabIndex), Bar.TabIndex]));
end;

// 否决切换到第 3 页
procedure TMainForm.TabChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
begin
  if ANewIndex = 2 then AllowChange := False;
end;
```

`TabCaption(AIndex)`（基类 public 方法）安全返回指定索引的标题，越界返回 `''`。

---

## 7. 注意事项

- **纯页签条，无页面容器：** `TTyTabSet` 只画一条标题栏，**不管理任何子页面**——内容切换须由业务代码在 `OnChange` 中自行完成。需要"页签 + 页面"一体的容器请用 `TTyPageControl`。
- **选中态即 `TabIndex`：** 没有 `ActivePage` 之类概念，"选中"完全由 `TabIndex`（`-1` = 无）表达，读取标题用 `Tabs[i]` 或 `TabCaption(i)`。
- **`Tabs` 赋值用 `Assign`：** 写入 `Tabs` 属性时内部调用 `FTabs.Assign(AValue)` 整体替换；`TabIndex` 不自动重置，仅在超过新上界时被夹到 `Count-1`。
- **关闭页签的 `OnChange` 语义：** 关闭**选中且非末尾**的页签时，`TabIndex` 数值不变（只是底层标题变了），此时**刻意不触发** `OnChange`，仅重绘；关闭会导致 `TabIndex` 变化的情形才通过 `SetTabIndex` 触发 `OnChange`。
- **直接 `Tabs.Delete` 低于选中项的已知失同步：** 通过关闭 × 走 `RemoveTabData` 会正确调整高亮；但**直接**对 `Tabs` 在选中项**之下**做 `Delete`，因裸 `TStringList.OnChange` 不携带索引，高亮会错位一格（源码标注的已知、不常见 desync）。删除位于或高于选中项时只夹紧上界。
- **重排后选中钉在位置：** `DoReorderTabs` 后 `FTabIndex` 不随被拖动的页签调整——**选中态钉在位置索引上**（与 `TTyPageControl` 一致）。
- **typeKey 为 `TyTabControl`：** 主题化时写 `TyTabControl` / `TyTab` 选择器，`.tycss` 中不存在 `TyTabSet`。
- **DFM 序列化：** `TabIndex` 声明 `default -1`、`TabHeight` 声明 `default 28`、`TabsClosable` 声明 `default False`，取默认值时不写入 `.lfm`/`.dfm`。
- **Alt+助记符：** 页签标题支持 `&` 助记符——`DialogChar` 在 `Enabled` 时扫描标题的加速键并 `SetTabIndex` 切换到匹配页签。
