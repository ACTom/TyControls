# TTySplitter

## 1. 概述

TTySplitter 是 TyControls 库中的主题化分隔条控件，继承自 `TTyCustomControl`。它是一根置于停靠面板之间的可拖动分隔条：按住鼠标左键横向或纵向拖动，即可改变相邻停靠面板的尺寸。典型用途：在 `alLeft`/`alRight` 或 `alTop`/`alBottom` 停靠布局中，让用户实时调节侧栏宽度或上下区高度。分隔条中央绘制三点“握把”提示，可拖动方向由自身 `Align` 决定。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Splitter` |
| `GetStyleTypeKey` 返回值 | `'TySplitter'` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TySplitter`。

```pascal
uses tyControls.Splitter;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MinSize` | `Integer` | `30` | 被调整面板允许的最小轴向尺寸；`SetMinSize` 写入时将负值夹到 `0`（已定义 `default 30`，参与 DFM 差量存储）。**它是不是一道拖不过去的地板，取决于 `AutoSnap`** |
| `AutoSnap` | `Boolean` | `True` | 拖过 `MinSize` 时把面板**收起到 0**，而不是钉在 `MinSize` 上。关掉它，面板就再没有任何手势能关闭——`MinSize` 成了一道拖不过去的地板，"把侧栏拖没"这件事做不到。LCL 也是默认开（`extctrls.pp` 的 `AutoSnap` 默认 `True`） |
| `ResizeStyle` | `TResizeStyle` | `rsUpdate` | 拖动反馈方式，**四个取值全部生效**：`rsUpdate` = 拖动过程中实时更新目标尺寸；`rsLine` / `rsPattern` = 延迟到松开鼠标才应用一次，拖动过程中画一条实时预览带（前者实心，后者虚线）；`rsNone` = 延迟应用且不画任何预览（已定义 `default rsUpdate`） |
| `Align` | `TAlign` | `alLeft` | 停靠方向，**决定分隔条方向与光标**（见第 5 节）；本控件把默认值重定义为 `alLeft`（已定义 `default alLeft`） |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

> 构造函数中默认设置 `Align := alLeft`、`Width := 5`、`Height := 100`，并调用 `UpdateCursor` 初始化光标。

### 继承的通用成员

TTySplitter 继承自 `TTyCustomControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

**状态跟踪字段（protected/private，不 published）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `FDragging` | `Boolean` | 鼠标左键按下并锁定拖动目标后为 `True`，`MouseUp` 时复位 |
| `FTarget` | `TControl` | 当前正在调整尺寸的相邻面板（`MouseDown` 时由 `FindResizeTarget` 求得，`MouseUp` 后置 `nil`） |
| `FMouseStart` | `Integer` | 拖动起点的鼠标**屏幕**坐标（轴向分量），用于 1:1 跟随鼠标 |
| `FStartSize` | `Integer` | 拖动开始时目标面板的轴向尺寸 |
| `FBand` | `TTySplitterBand` | `rsLine` / `rsPattern` 拖动中的预览带，`MouseDown` 建、`MouseUp` 释放；其余时候为 `nil` |

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnCanResize` | `TTySplitterCanResizeEvent` | 每次**协商**新尺寸时触发——`rsUpdate` 下即每次应用之前，延迟样式下还包括每一次移动预览带；签名 `(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean)`。可在 handler 中改写 `ANewSize` 以钳制目标尺寸，或把 `AAccept := False` 否决本次调整 |
| `OnMoved` | `TNotifyEvent` | 拖动结束（`MouseUp`）时触发，**且仅当目标尺寸相对起始值实际发生了改变**（对齐 `TCustomSplitter` 行为）；尺寸未变则不触发 |

> 除上表外，TTySplitter 还暴露**基线事件集**（Tier A 鼠标 / 通用事件 + Tier B 键盘 / 焦点事件，因其为 `TTyCustomControl`）。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停（内置主题用它把握把点变为强调色） |

> TTySplitter 未重写 `CurrentStates`，沿用 `TTyCustomControl` 的基础状态机制；内置主题仅使用 `:hover`（`:focus`/`:active`/`:disabled` 规则未在 light.tycss 中为该 typeKey 定义）。

### light.tycss 内置规则摘要

```css
TySplitter {
  background: none;           /* 默认无背景填充，分隔条“透明”嵌入布局 */
  color: var(--muted);        /* 握把三点的默认颜色 */
}
TySplitter:hover {
  color: var(--accent);       /* 悬停时握把点变为强调色 */
}
```

**渲染细节：** `RenderTo` 先走 `DrawFrame` 路径（若主题设置了 `background` 则据此填充，内置主题默认 `none`），再在控件中央绘制 **3 个握把圆点**，颜色取当前样式的 `TextColor`（即 `color` 令牌）。圆点直径与间距经 DPI 缩放（`P.Scale(2)` / `P.Scale(3)`）。方向随 `Align`：竖直分隔条（`alLeft`/`alRight`）三点**纵向**排列，水平分隔条（`alTop`/`alBottom`）三点**横向**排列。

**预览带（`rsLine` / `rsPattern`）：** 颜色取的是**同一个** `TextColor` 令牌——握把点用的那个，所以写
`TySplitter { color: ... }` 会把握把和预览带一起改，没有任何颜色被写死在代码里。（不给预览带单独开一个
typeKey，是因为那样得先在每一个已发布的主题里补上一条规则，它才解析得出东西来。）

预览带是一个**临时的兄弟窗口**，不是画在父控件 DC 上的一笔：Win32 上父控件的 DC 会被它的子窗口裁掉，
画在那儿的带子会藏到它正要预览的那几块面板后面去。它由分隔条持有（拖动中被释放的分隔条会带走它），
在松手时以及"按键已经不在了"的中止路径上都会拆掉——否则一次被别人截走的 `MouseUp` 会把它永远留在版面上。

### 光标（由 Align 派生）

`UpdateCursor` 根据 `Align` 设置 `Cursor`：

| Align | 分隔条方向 | 拖动方向 | 光标 |
|-------|-----------|----------|------|
| `alLeft` / `alRight` | 竖直（`Vertical = True`） | 横向，改变邻居**宽度** | `crHSplit` |
| `alTop` / `alBottom` | 水平（`Vertical = False`） | 纵向，改变邻居**高度** | `crVSplit` |

光标在三处刷新：构造函数、`Loaded`（.lfm 流式载入后重新派生）、以及 **`MouseEnter`**——因为运行期代码在构造之后才设置 `Align`（例如 `Align := alTop`）时不会经过 `Loaded`，若不在悬停时重新派生就会残留构造时的 `alLeft`（`crHSplit`）光标。因此**鼠标进入控件时始终按当前 `Align` 重新校正光标**。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Panel, tyControls.Splitter;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

var
  LeftPanel: TTyPanel;
  VSplit: TTySplitter;

// 左栏（alLeft，先创建）
LeftPanel := TTyPanel.Create(Self);
LeftPanel.Parent := ClientHost;
LeftPanel.Align := alLeft;
LeftPanel.Width := 220;

// 竖直分隔条：Align=alLeft → 横向拖动，改变左栏宽度
VSplit := TTySplitter.Create(Self);
VSplit.Parent := ClientHost;
VSplit.Align := alLeft;
VSplit.Left := LeftPanel.Width;   // 显式停靠到左栏右侧，固定停靠次序
VSplit.Width := 6;
VSplit.MinSize := 120;            // 左栏最小宽度（拖过它会收起，除非 AutoSnap := False）
VSplit.ResizeStyle := rsUpdate;   // 实时更新（rsLine/rsPattern 画预览带、松手才提交；rsNone 无预览）
VSplit.OnCanResize := @HandleCanResize;
VSplit.OnMoved := @HandleMoved;

// 右侧客户区（alClient，最后创建）
RightHost := TTyPanel.Create(Self);
RightHost.Parent := ClientHost;
RightHost.Align := alClient;

procedure TMainForm.HandleCanResize(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
begin
  // 可在此改写 ANewSize 钳制尺寸，或 AAccept := False 否决本次调整
  FStatus.Caption := Format('拖动中 · 目标尺寸 %d px', [ANewSize]);
end;

procedure TMainForm.HandleMoved(Sender: TObject);
begin
  FStatus.Caption := Format('拖动完成 · 左栏宽 %d px', [LeftPanel.Width]);
end;
```

---

## 7. 注意事项

- **方向完全由 Align 决定：** 不存在独立的方向属性——`alLeft`/`alRight` 为竖直分隔条（横向拖动改宽度，`crHSplit`），`alTop`/`alBottom` 为水平分隔条（纵向拖动改高度，`crVSplit`）。运行期改动 `Align` 后，光标会在下次 `MouseEnter` 时自动校正。
- **调整目标是“锚定侧”的相邻同级控件：** `FindResizeTarget` 查找紧贴分隔条锚定一侧的兄弟控件（`alLeft` 取其左侧、`alTop` 取其上方、`alRight`/`alBottom` 反之），且需在垂直方向上有重叠。因此左栏必须先于分隔条创建并 parent；代码创建时通常需显式设置分隔条的 `Left`/`Top` 以固定停靠次序（见示例）。
- **拖动以屏幕坐标测量：** `MouseDown` 记录鼠标的屏幕坐标 `FMouseStart`，拖动时以屏幕坐标求 delta，使调整 1:1 跟随鼠标；对 `alLeft`/`alTop` 这类“边拖边滑”的分隔条，用控件本地坐标会出现半速跟随的问题，故刻意使用屏幕坐标。
- **尺寸钳制：** 新尺寸经 `TySplitterNewSize` 计算，上界为父容器客户区可用尺寸减去分隔条自身厚度（`Parent.ClientWidth/ClientHeight - Width/Height`）；下界看 `AutoSnap`：**开（默认）时拖过 `MinSize` 就收到 0**，关时钉在 `MinSize`。`SetMinSize` 会把负的 `MinSize` 夹到 `0`。
- **预览与提交出自同一次钳制：** 钳制 + `OnCanResize` 否决被收进一个 `NegotiateSize`，预览带和松手提交都调它。一个会跟提交结果对不上的预览，比没有预览更糟——所以 `AutoSnap` 也必须走进这个共享路径，否则拖到底时带子收不起来而松手却把面板关了。
- **`OnCanResize` 在延迟样式下每次移动都触发：** `rsLine` / `rsPattern` 拖动时每移一次就问一遍（预览要知道该停在哪儿），松手提交时再问一遍。否决时预览带停在原处不动。
- **OnMoved 仅在尺寸真正改变时触发：** 若一次拖动结束后目标尺寸与起始值相同（例如被 `MinSize`/上界钳住或被 `OnCanResize` 否决），则不触发 `OnMoved`。
- **控件默认透明：** 内置主题 `background: none`，分隔条本身不绘制背景框，只在中央画三点握把；如需可见分隔背景，可在主题中为 `TySplitter` 设置 `background`（`DrawFrame` 路径会应用它）。
- **DFM 序列化：** `MinSize`（`default 30`）、`AutoSnap`（`default True`）、`ResizeStyle`（`default rsUpdate`）、`Align`（`default alLeft`）均声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。
- **预览带需真机验证：** 带子压在指针底下、依赖分隔条持有鼠标捕获，无头测试跑不到这条路——发版前每种 `ResizeStyle` 至少手拖一次。
