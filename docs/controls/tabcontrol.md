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

在 `.tycss` 文件中，控件外框对应选择器前缀 `TyTabControl`，各页签对应子部件选择器前缀 `TyTab`。

```pascal
uses tyControls.TabControl;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `TabHeight` | `Integer` | `28` | 页签头条带的逻辑高度（96 DPI 基准像素），绘制时按实际 PPI 自动缩放 |
| `OnChange` | `TNotifyEvent` | `nil` | 仅当 `TabIndex` 发生真实变化时触发，相同值重复赋值不触发 |
| `TabStop` | `Boolean` | `True` | 控件可通过 Tab 键获得键盘焦点 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### 自有 public 属性与方法

| 成员 | 类型/签名 | 说明 |
|------|-----------|------|
| `TabIndex` | `Integer`（读写） | 当前选中页签的零基索引；-1 表示无选中页；赋值时自动裁剪越界值（低于 -1 → -1，大于末尾 → 末尾）；真变化才触发 `OnChange` |
| `Pages[AIndex: Integer]` | `TTyPanel`（只读，indexed property） | 返回指定索引处的页面板；越界返回 `nil` |
| `AddTab(const ACaption: string): TTyPanel` | 方法 | 追加一个新页签，返回对应的 `TTyPanel` 页面板；第一个页签被追加时自动选中（`TabIndex := 0`），不触发 `OnChange` |
| `TabCount: Integer` | 方法 | 当前页签数量 |
| `TabCaption(AIndex: Integer): string` | 方法 | 返回指定索引的页签标题；越界返回空字符串 |
| `TyTabHeaderRect(AIndex: Integer): TRect` | 方法 | 返回指定页签头的设备像素矩形（以控件 (0,0) 为原点），主要用于测试与自定义命中检测 |

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
| `AddTab(const ACaption): TTyPanel` | 函数 | 见属性表；追加页签并返回页面板 |
| `TabCount` | `Integer` 函数 | 返回当前页签数量 |
| `TabCaption(AIndex)` | `string` 函数 | 返回指定页签的标题文字 |
| `TyTabHeaderRect(AIndex)` | `TRect` 函数 | 返回指定页签头的几何矩形（设备像素，控件本地坐标） |

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

TyTab {
  background: darken(--surface, 5%);
  color: var(--on-surface);
  padding: 4px;
}
TyTab:hover  { background: darken(--surface, 2%); }
TyTab:active { background: var(--surface); color: var(--accent); }
```

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
| `←`（VK_LEFT） | 切换到前一页签；已在第一个页签时不循环 |
| `→`（VK_RIGHT） | 切换到后一页签；已在最后一个页签时不循环 |

键被消费后不再传递（`Key := 0`）。控件需要获得焦点（`TabStop = True`，默认启用）才能响应键盘。

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

- **页签溢出不滚动**：当所有页签标题的宽度之和超过控件宽度时，超出部分会被画布裁剪，不提供滚动页签条。这是 v1.2 已知限制，参见 [docs/KNOWN_GAPS.md](../KNOWN_GAPS.md)。
- **`AddTab` 第一个页签自动选中**：首次调用 `AddTab` 时，控件会直接将 `FTabIndex` 置为 0 并显示该页，不经过 `SetTabIndex` 设置器，因此不触发 `OnChange`。后续调用 `AddTab` 追加更多页签时，当前选中页不变。
- **页面板由 TabControl 拥有**：`AddTab` 创建的 `TTyPanel` 以 `TTyTabControl` 为 Owner，无需也不应手动释放它们——TabControl 析构时会自动释放。
- **`TabIndex = -1`**：赋值为 -1 时所有页面板均隐藏；正常使用时无需主动赋 -1（添加第一个页签后控件会自动选中第 0 页）。
- **子部件 `TyTab` 的 `:active` 含义**：指"被选中"，而非通用控件中的"鼠标按下"。主题作者为 `TyTab:active` 设置样式即可控制当前选中页签的高亮外观。
