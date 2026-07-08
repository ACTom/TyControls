# TTyCoolBar

## 1. 概述

`TTyCoolBar` 是 TyControls 库中的 **rebar（可调节带）容器**，继承自 `TTyControlBar`（同批次由兄弟控件提供的"带打包"基类）。它把每个子控件停靠成一条水平"带"（band），并在每条带的左侧提供一个**夹具（gripper）**——用户可以：

- **拖动夹具左右移动**：改变该带的宽度（在每带最小 / 最大宽度之间钳制）；
- **拖动夹具上下移动**：把该带重排（reorder）到新的带序（真机交互）。

与父类 `TTyControlBar` 的区别在于：`TTyCoolBar` 让每条带**可拖动重排、可拖动改宽**，并为每条带引入按子控件键控的 `Width` / `MinWidth` / `MaxWidth` 元数据。典型用途：经典 Office / IE 风格的可拖拽工具带条（每条带可独立伸缩、换位）。

> **交互 vs 数学：** 真正的拖动（鼠标捕获、实时重排动画）属于真机行为；夹具**命中判定**与**改宽钳制**这两处几何被抽成纯函数（`TyCoolGripperHit` / `TyCoolBandResize`），可无窗口 headless 单测。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.CoolBar` |
| `GetStyleTypeKey` 返回值 | `'TyPanel'`（**刻意复用**基类的 TyPanel 令牌，**不新增任何 .tycss**） |
| 基类 | `TTyControlBar`（带打包容器；同样 `GetStyleTypeKey='TyPanel'`） |
| 默认夹具宽度 | 10（逻辑像素） |
| 默认带最小宽度 | 24（逻辑像素） |

```pascal
uses tyControls.CoolBar, tyControls.ControlBar, tyControls.Panel;
```

---

## 3. 属性表

### 3.1 TTyCoolBar 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `GripperWidth` | `Integer` | `10` | 每条带左侧夹具列的逻辑宽度（像素）。夹具是可拖拽区域；改值触发 `Realign` 重新打包各带。 |
| `DefaultBandMinWidth` | `Integer` | `24` | 未单独设置 `MinWidth` 的带在拖动改宽时的下限（逻辑像素）。 |
| `Align` / `Anchors` | — | — | 停靠 / 锚点（继承）。 |
| `StyleClass` / `Controller` | — | — | CSS 类名 / 样式控制器（继承）。 |

### 3.2 每带元数据 API（按子控件键控）

带的宽度 / 钳制**不是**按位置索引的平行数组，而是以子控件 `TControl` 为键存储；因此**重排、删除其它带都不会串位**，子控件被 free 时其条目在 `Notification(opRemove)` 中自动丢弃。

| 方法 | 说明 |
|------|------|
| `SetBandWidth(ACtl, AWidth)` | 设定某带的固定 / 指定宽度（逻辑像素）；`AWidth <= 0` 清除为 auto。会把子控件宽度同步为该值并 `Realign`。 |
| `GetBandWidth(ACtl): Integer` | 读取某带的存储宽度（未设为 `0` = auto）。 |
| `SetBandMinWidth(ACtl, AMinWidth)` | 设定某带拖动改宽的下限；未设时回退 `DefaultBandMinWidth`。 |
| `SetBandMaxWidth(ACtl, AMaxWidth)` | 设定上限；`0` = 无上限。 |
| `BandMinWidth(ACtl): Integer` | 生效下限（自有 min 优先，否则默认，且不小于 1）。 |
| `BandMaxWidth(ACtl): Integer` | 生效上限（`0` = 无上限）。 |

### 3.3 继承成员

继承自 `TTyControlBar` → `TTyCustomControl`：`Enabled` / `Font` / `Hint` / `TabOrder` / Tier A 鼠标事件 + Tier B 键盘焦点事件等。完整清单见 [../events.md](../events.md)。

---

## 4. 纯函数（headless 单测的核心）

```pascal
{ 拖动夹具后带的新宽度：起始宽 AStartW + 位移 ADx，钳制到 [AMinW .. AMaxW]。
  AMaxW <= 0 表示无上限（只作用下限）；AMinW 至少为 1，带永不塌缩为 0。 }
function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;

{ 命中判定：APt 是否落在 ABandRect 左侧 AGripperW 像素宽的夹具列内（设备像素）。
  右边界半开、上闭下开，与 LCL 命中一致；AGripperW <= 0 → 无夹具 → 永远 False。 }
function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;
```

- `TyCoolBandResize`：`AMaxW < AMinW` 的非法区间会塌缩到下限；`AMinW <= 0` 被抬到 1。
- `TyCoolGripperHit`：左边界 inclusive、右边界 `Left+AGripperW` exclusive；纵向 `Top` inclusive、`Bottom` exclusive。

---

## 5. 事件

`TTyCoolBar` **无自有专有事件**——它只暴露基线事件集。拖动重排 / 改宽的语义变更由基类打包机制处理；命令响应挂在各**子控件**上（如子带里的按钮 `OnClick`）。

---

## 6. 状态与主题

`TTyCoolBar` 复用 `'TyPanel'` 令牌，外观（背景 / 边框）完全由主题的 `TyPanel` 规则决定，**无新增 tycss**。夹具本身用 painter 图元（点列 / 短线）在带左缘绘制（真机可见），颜色取自当前样式的文本 / 边框色，仍为主题令牌驱动。

---

## 7. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.CoolBar, tyControls.Panel, tyControls.Button;

var
  Cool: TTyCoolBar;
  Band1, Band2: TTyPanel;
begin
  TyDefaultController.LoadTheme('themes/light.tycss');

  Cool := TTyCoolBar.Create(Self);
  Cool.Parent := Self;
  Cool.Align := alTop;
  Cool.GripperWidth := 10;          // 每条带左侧夹具列宽度

  // 第一条带：一个子容器（可再放按钮 / 编辑器等）
  Band1 := TTyPanel.Create(Self);
  Band1.Parent := Cool;             // 关键：父控件是 CoolBar → 成为一条带
  Cool.SetBandWidth(Band1, 160);    // 给这条带一个固定宽度
  Cool.SetBandMinWidth(Band1, 80);  // 拖动改宽的下限

  // 第二条带
  Band2 := TTyPanel.Create(Self);
  Band2.Parent := Cool;
  Cool.SetBandWidth(Band2, 200);
  Cool.SetBandMaxWidth(Band2, 400); // 拖动改宽的上限
end;
```

---

## 8. 注意事项

- **子控件即一条带：** 把子控件 `Parent := CoolBar` 即成为一条带；`TTyCoolBar` 是 `csAcceptsControls` 容器（继承自基类）。
- **元数据按控件键控：** `Width` / `MinWidth` / `MaxWidth` 以子控件为键存储；重排、删除其它带不串位，子控件 free 时条目自动丢弃（`Notification/opRemove`）。切勿假设它按位置索引。
- **拖动分辨（真机）：** `MouseDown` 命中夹具后进入拖动；横向位移 → 改宽（`TyCoolBandResize` 钳制），纵向位移 → 重排（真机细化）。当前实现以横向改宽为主，重排的方向消歧属真机 refinement。
- **改宽是逻辑像素：** 拖动位移从设备像素折算为逻辑像素（`MulDiv(dx,96,PPI)`）再钳制，带宽以逻辑像素存储。
- **无新增 tycss：** 复用 `'TyPanel'` 令牌，主题只需定义 `TyPanel` 规则。
- **DFM 序列化：** `GripperWidth`（`default 10`）/ `DefaultBandMinWidth`（`default 24`）声明了默认值，等于默认值时不写入 `.lfm`/`.dfm`。
