# TTyScrollPanel

## 1. 概述

TTyScrollPanel 是 TyControls 库中的**自动平移滚动容器**，继承自 `TTyScrollBox`（本批次的滚动容器基类）。它把父类完整的“视口 + 内嵌滚动条 + 子控件按滚动位偏移”机制原样继承下来，只额外添加**一件事**——**边缘自动平移（edge auto-pan）**：当用户正在拖拽（橡皮筋框选、拖动某个子控件、或一次拖放 DnD）且指针进入视口某条边缘的 `EdgeMargin` 带内时，面板会朝那条边自动滚动，指针离边越近滚得越快。这正是“把拖动对象拽到列表边缘、列表就自己继续滚”的经典手感，也是设计期 / 拖放场景里最常用的辅助。

本控件被测的**核心**是纯函数 `TyEdgeAutoPan`（见第 4 节）：给定指针位置、视口矩形、边缘带宽与最大速度，返回本帧应施加的滚动增量 `(dx, dy)`。这段数学完全 headless 可测。真正驱动它的定时器、以及给它喂实时指针的拖拽 / DnD 接线属于交互路径，需真机验证（运行时由一个 `TTimer` 每帧调用 `AutoPanTo`→`AutoPanStep`）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ScrollPanel` |
| `GetStyleTypeKey` 返回值 | `'TyScrollBox'`（**继承自 `TTyScrollBox`，刻意不重写**） |
| 基类 | `TTyScrollBox`（滚动容器，继承自 `TTyPanel` = `TTyCustomControl`，有窗口句柄、可作父容器） |

在 `.tycss` 文件中，本控件走 `TyScrollBox` 选择器着色（背景/边框/内边距令牌），与 [`TTyScrollBox`](scrollbox.md) 完全一致——**注意它不再是 `TyPanel`**：`TTyScrollBox` 在 2026-07 的 typeKey 审计中拿到了自己的键（滚动井下沉、面板抬起，两者观感相反），本控件作为它的子类自动继承了新键。

**这个借用是刻意保留的、也是正确的：** 一个会边缘自动平移的面板**就是一个滚动井**——它加的是一个**手势**，不是一个新表面；它一个额外的像素都不画，`AutoPanTo` / `AutoPanStep` 只改滚动偏移。让它和 `TTyScrollBox` 共用一个键，正是"改滚动井的皮肤，两者一起变"这个应有的行为。源码单元头也这么写着。

**子部件 typeKey：没有。** 视口只有一个盒子样式，两条内嵌滚动条是真正的 `TTyScrollBar` 子控件，走 `TyScrollBar` / `TyScrollThumb`。

```pascal
uses tyControls.ScrollPanel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `AutoScroll` | `Boolean` | `True` | 自动平移总开关。为 `False` 时 `AutoPanTo` 变为 no-op（面板仍可用滚轮 / 滚动条滚动，行为等同其 `TTyScrollBox` 基类）；置 `False` 会立即停止任何正在进行的自动平移 |
| `EdgeMargin` | `Integer` | `24` | 触发自动平移的边缘带**逻辑**宽度（px@96ppi）；越大则离边越远就开始平移。使用时按 `MulDiv(值, PPI, 96)` 做 DPI 缩放；赋负值钳制为 `0` |
| `MaxSpeed` | `Integer` | `16` | 到达（或越过）边缘时每帧的**逻辑**最大滚动增量（px@96ppi）；增量从边缘带内边界处的 `0` 线性升到此值。DPI 缩放同上；赋负值钳制为 `0` |

### 自有公开成员（非 published）

| 成员 | 签名 | 说明 |
|------|------|------|
| `AutoPanTo` | `procedure (const AClientPos: TPoint)` | 用实时指针（**客户区坐标**）武装 / 刷新自动平移。在拖拽处理器里每次指针移动都调用它；只要指针停在某条边缘带内，就启动定时器持续滚动，指针离开边缘带则暂停（拖拽仍在进行，保持武装）。真机路径（需要运行的消息循环） |
| `StopAutoPan` | `procedure` | 停止任何正在进行的自动平移。应在拖拽结束 / `MouseUp` / `OnEndDrag` 时调用 |
| `AutoPanActive` | `Boolean`（只读属性） | 自动平移定时器是否处于活动状态 |

### 继承的通用成员

TTyScrollPanel 继承自 `TTyScrollBox` → `TTyPanel` → `TTyCustomControl`（`tyControls.Base`），因此拥有滚动容器的全部能力（内嵌滚动条、`AdjustClientRect`、子控件偏移）以及基础的 `StyleClass` / `StyleOverride` / `Controller` / `Anchors` / `Align` 等（完整清单见基类文档）。

**状态跟踪字段（private，不 published）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `FAutoPanActive` | `Boolean` | 有拖拽 / DnD 正在武装自动平移时为 `True` |
| `FLastPanPos` | `TPoint` | 最近一次喂给平移的指针位置（客户区 px）——定时器每帧从此位置继续，故指针“停在边缘不动”时也能持续滚 |
| `FPanTimer` | `TTimer` | 懒创建，仅在自动平移真正运行时才建立；`~16ms`（约 60fps）。析构里先 `FreeAndNil`，避免拆卸期回调 |

**构造时默认值：** `AutoScroll = True`，`EdgeMargin = 24`，`MaxSpeed = 16`。

---

## 4. 纯函数（单元级，无需窗口句柄，可直接单测）

本控件的价值在于**正确的边缘平移数学**。下面这个单元级纯函数是自动平移的核心，测试直接调用：

```pascal
function TyEdgeAutoPan(const AMousePos: TPoint; const AViewport: TRect;
  AEdgeMargin, AMaxSpeed: Integer): TPoint;
```

给定指针 `AMousePos`、视口矩形 `AViewport`（两者同一坐标系）、边缘带宽 `AEdgeMargin` 与每帧最大速度 `AMaxSpeed`，返回本帧应施加的滚动增量 `(dx, dy)`：

| 情形 | 行为 |
|------|------|
| **中间平静区** | 指针在某轴上离两条边都超过 `AEdgeMargin` → 该轴增量为 `0` |
| **接近边缘（斜坡）** | 指针进入边缘带后，增量从内边界处的 `0` **线性升**至边缘处的 `AMaxSpeed` |
| **朝顶 / 左边** | 增量为**负**（内容向上 / 向左滚） |
| **朝底 / 右边** | 增量为**正**（内容向下 / 向右滚） |
| **越过边缘** | 指针被拖到视口外时，增量钳制在 `AMaxSpeed`（拖过边界只会满速滚，不会更快） |
| **禁用守卫** | `AEdgeMargin <= 0` 或 `AMaxSpeed <= 0` → 返回 `(0,0)` |
| **薄视口守卫** | 某轴太窄容不下两条不重叠的边缘带时，把带宽钳为该轴一半，从中点一分为二——每半仍朝各自的边平移，无死重叠区、不重复计数 |
| **空视口** | `span <= 0`（退化矩形）→ 该轴永不平移 |

> 每帧的实际滚动落地（把 `(dx,dy)` 加到 `TTyScrollBox` 的滚动偏移）属于交互路径，需真机验证；上述平移数学则完全 headless 可测。控件内部通过受保护的 `AutoPanStep` → `ApplyAutoPanDelta` 两级“接缝”把纯计算与偏移落地隔开，测试用访问子类覆写 `ApplyAutoPanDelta` 即可在无实时偏移的情况下观察请求的增量。

---

## 5. 事件

TTyScrollPanel 未在 `published` 节声明专有事件。自动平移逻辑通过公开方法 `AutoPanTo` / `StopAutoPan` 由宿主的拖拽处理器驱动，不经外部事件回调。作为 `TTyScrollBox` 后代，它暴露基类的 Tier A/B 基线事件（`OnMouseDown`/`OnMouseMove`/`OnMouseUp`/`OnDragOver` 等，完整清单见 [../events.md](../events.md)）。

典型接线：在拖拽 `OnDragOver` 或橡皮筋 `OnMouseMove` 里把指针位置传给 `AutoPanTo(ScreenToClient(...))`，在 `OnDragDrop`/`OnEndDrag`/`OnMouseUp` 里调 `StopAutoPan`。

---

## 6. 状态与主题

沿用 `TTyScrollBox` 的着色（`TyScrollBox` 令牌），支持基础的 `:hover` / `:active` / `:disabled` / `:focus` 伪类。自动平移本身**不绘制任何额外视觉**——它只改变滚动偏移，外观与一个普通 `TTyScrollBox` 无异。因此它**没有自己的键**，也不需要。

---

## 7. 代码示例

```pascal
uses
  Controls, Types, tyControls.Controller, tyControls.ScrollPanel;

var
  Pane: TTyScrollPanel;

// 在窗体上放一个自动平移滚动面板
Pane := TTyScrollPanel.Create(Self);
Pane.Parent := Self;
Pane.Align := alClient;
// 默认 AutoScroll=True, EdgeMargin=24, MaxSpeed=16；如需更“灵敏”可加大边缘带：
// Pane.EdgeMargin := 40;

// 在拖放处理器里，把指针位置喂给自动平移（客户区坐标）：
procedure TForm1.PaneDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  Accept := True;
  TTyScrollPanel(Sender).AutoPanTo(Point(X, Y));   // 靠近边缘即自动滚动
end;

procedure TForm1.PaneDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  TTyScrollPanel(Sender).StopAutoPan;              // 落下时停止平移
  // ... 处理放置 ...
end;
```

---

## 8. 注意事项

- **薄壳子类，刻意共用滚动井的键：** `GetStyleTypeKey` 不重写，直接继承 `TTyScrollBox` 的 `'TyScrollBox'`（该键在 2026-07 审计中已从 `'TyPanel'` 拆出）。本控件只加行为、不加表面，因此不该有自己的键；要改它的外观，改 `TyScrollBox` 规则（会同时作用于普通滚动框，这是预期的）。
- **纯数学是被测核心：** `TyEdgeAutoPan` 是完全 headless 的纯函数（斜坡 / 钳制 / 薄视口分裂 / 禁用守卫都在此），单测直接调用；定时器 + 拖拽接线是真机路径。
- **坐标系一致：** `AutoPanTo` 的指针位置必须与 `AutoPanViewport`（默认 `ClientRect`）**同一坐标系**（客户区 px）。从屏幕坐标来时先 `ScreenToClient`。
- **指针停在边缘也持续滚：** 定时器从 `FLastPanPos` 每帧续滚，因此拖拽对象“压在边缘不动”时列表仍持续滚动，符合直觉；指针回到中间平静区则暂停（仍武装），拖拽结束需显式 `StopAutoPan`。
- **DPI 缩放：** `EdgeMargin` / `MaxSpeed` 是逻辑值（96ppi 基准），使用时按 `MulDiv(值, Font.PixelsPerInch, 96)` 缩放；负值钳为 `0`。
- **AutoScroll 关闭即退化：** `AutoScroll := False` 时 `AutoPanTo`/`AutoPanStep` 均为 no-op，面板仍是一个可用滚轮 / 滚动条滚动的普通 `TTyScrollBox`。
- **定时器安全：** `FPanTimer` 由 `Self` 拥有但析构里先 `FreeAndNil`，避免拆卸期 `OnTimer` 触发（沿用 `TTyScrollBar` 的定时器拆卸约定）。
- **滚动落地接缝：** 每帧增量经受保护的 `ApplyAutoPanDelta` 落到基类偏移；此钩子被刻意隔离在一处，由批次控制器接到 `TTyScrollBox` 暴露的公共滚动接口（见集成说明）。在接线完成前它是安全的 no-op，不影响纯核心与武装逻辑的可测性。
</content>
