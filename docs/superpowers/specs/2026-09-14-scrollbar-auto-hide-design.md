# 滚动条自动隐藏 —— 设计定稿

> 状态：已定稿（用户 2026-09-14 拍板）· 分支：`feat/3.1` · 需求来源：群友，经另一会话转交

鼠标不在时滚动条淡出，用到时再出现（macOS / Win11 的现代手感）。
本文锁范围与契约，实现步骤另拆到 `docs/superpowers/plans/`。

---

## 1. 已定的前提（不再讨论）

| # | 决定 | 直接后果 |
|---|------|----------|
| 1 | **默认一直显示**，自动隐藏是 opt-in | 3.0 已发布，升到 3.1 现有程序界面不能自己变样 |
| 2 | **槽保留**，隐藏后内容宽度不变 | 收益是少一条视觉噪音，不是省空间。6 个宿主的布局 / 命中 / z 序一行不用动 |
| 3 | **真 overlay（内容铺满、条浮在上面）不做** | 窗口化子控件盖不住内容（重叠部分被句柄咬平），要做得改成宿主内联画条。单列 backlog |
| 4 | **一个 token 承载开关与延时**，`-1` 表示关 | 一条轴没有歧义，见 §2 |
| 5 | **鼠标在内容区上移动不触发显示** | 这是与需求转述不同的地方，理由见 §4 |

**不做清单**：跟随 OS 的「自动隐藏滚动条」系统设置（Windows / macOS 各有开关）——按 widgetset 各做一遍，且 GTK 下读不到系统设置，与跟随明暗同源。单列 backlog。

---

## 2. 主题 token

走**已有的** `Metric` 机制（`tyControls.Controller.pas:631` → `FModel.ResolveMetric`），不给 tycss 加新值类型：

```pascal
const
  TyScrollBarAutoHideVar = '--scrollbar-auto-hide';
  TyScrollBarAutoHideDef = -1;     // 内置默认：关
```

| 值 | 含义 |
|---|---|
| `-1` | 关。滚动条一直显示（**内置主题的值**） |
| `0` | 开，停手立即淡出 |
| `N` | 开，停手 N 毫秒后淡出 |

读法与现有控件一致，**必须走 `ActiveController` 而不是裸 `Controller`**：

```pascal
delayMs := ActiveController.Metric(TyScrollBarAutoHideVar, TyScrollBarAutoHideDef);
```

主题不定义这个变量时，`Metric` 回退到代码里的 `TyScrollBarAutoHideDef`（`-1`）——所以 `light.tycss` / `dark.tycss` 什么都不用写。现代主题（`win11` / `macos` / `fluent` / `material3`）在自己的 `:root` 里写 `1200`；经典主题（`classic` / `xp` / `aero`）不写。

> **待验证（实现第一步）**：`ResolveMetric` 能不能解析负数 `-1`。它下游是 `TyEvalLength`（`'6px'→6`），负号是否被接受未经证实。若不行，改用 `TyEvalFloat` 或在 `ResolveMetric` 补负号支持——**先写一条测试确认，再动代码**。

> **皮肤连锁**：15 个内置皮肤编译进 `BuiltinThemeData`，改了 `themes/builtin/*.tycss` 必须重跑 `scripts/gen-builtinthemes.ps1`。给现代皮肤加这个变量时一并处理。

---

## 3. 控件属性（压过主题）

```pascal
type
  TTyScrollBarAutoHide = (sbahDefault, sbahNever, sbahAuto);
```

| 值 | 含义 |
|---|---|
| `sbahDefault` | 跟主题 token 走（**构造值 = published default**） |
| `sbahNever` | 永远显示，压过主题 |
| `sbahAuto` | 自动隐藏，压过主题（延时仍读 token；token 为 `-1` 时按 §5 的回退延时） |

**必须是三态枚举，不能是 `Boolean`**：`Boolean` 一旦被碰过就永远脱离主题控制，换主题不跟着变——在一个主打换肤的库里这是硬伤。

`TTyScrollBar.AutoHide` 声明为 published，**`default sbahDefault` 必须与构造函数赋的值一致**，否则 `.lfm` 写的值被当默认省略、加载后丢失。

**延时不给属性。** 单控件要不同延时是臆想需求（YAGNI）。

### 宿主转发

内嵌滚动条用户拿不到，6 个宿主各暴露一个 `ScrollBarAutoHide`，同样三态、同样默认 `sbahDefault`，在创建内嵌条时转发：

| 宿主 | 内嵌条创建处 |
|---|---|
| `TTyStringGrid` / `TTyDrawGrid` | `tyControls.Grid.pas:3909, 3918` |
| `TTyListBox` | `tyControls.ListBox.pas:985, 1014` |
| `TTyListView` | `tyControls.ListView.pas:1082, 1091` |
| `TTyMemo` | `tyControls.Memo.pas:2358, 2420` |
| `TTyScrollBox` | `tyControls.ScrollBox.pas:373, 385` |
| `TTyTreeView` | `tyControls.TreeView.pas:3200, 3208` |

`TTyValueListEditor` 继承 Grid，不单独处理。

---

## 4. 什么算「还在用」

**任一成立 → 显示且不计时；全不成立 → 起延时表，到点淡出。**

1. `Position` 变化——滚轮 / 键盘 / 轨道点击 / 拖动 / **程序化赋值也算**
2. 鼠标在**滚动条自身**上
3. 拖动进行中（此时延时表根本不起）
4. 滚动条有焦点

### 为什么鼠标在内容区上移动不算

需求转述里是「悬停在宿主内容上就显示、滚动时显示、停手后延时淡出」——这三条自相矛盾：鼠标大部分时间就停在内容区，"停手"永远不会发生，滚动条常驻，自动隐藏等于没做。

macOS 与 Win11 的真实行为是：**滚动才出现，鼠标在内容上移动不出现**；鼠标移到条上才持续显示。本设计按后者。

这条同时消掉了一个实现陷阱：滚动条是窗口化子控件，鼠标从内容移到条上时宿主会收到 `MouseLeave`——若把宿主 hover 当活跃信号，就会在交界处来回抖。现在 `MouseEnter` / `MouseLeave` 只发生在滚动条自己身上，**6 个宿主的鼠标处理一行不用改，只转发属性**。

---

## 5. 淡入淡出

| 参数 | 值 | 理由 |
|---|---|---|
| 淡入 | 120 ms | 与库内现有过渡时长一致。出现要快——用户正在找它 |
| 淡出 | 200 ms | 消失要柔，不打扰 |
| 隐藏态 opacity | `0` | 完全消失，不留幽灵 |
| token 为 `-1` 但属性是 `sbahAuto` 时的回退延时 | 1200 ms | 属性明说要自动隐藏，主题没给延时，取 macOS 量级 |

缓动复用 `TyAnimatorInit(ADurationMs, AEasing)`（`tyControls.Animation.pas:49`）。

### 动画标志必须独立

内嵌滚动条构造时被设 `AnimationsEnabled := False`，管的是**滑块位置**缓动，**有意为之**（滚动要跟手，缓动会让滑块与内容错位）。

淡入淡出**不能共用这个标志**，否则内嵌条永远是跳变——而内嵌条正是这个特性的主场。→ 单开一个内部标志。

---

## 6. 隐藏怎么实现

**用 `opacity`，不用 `Visible := False`。**

- `Visible := False` 会让宿主重新布局把槽收掉，而前提 2 要留槽
- 窗口化控件「不画」也不等于透明——它会露出自己的 LCL `Color`

所以走 `opacity` → `TTyPainter.EndPaint` 铺父底色那条路（`tyControls.Painter.pas:1292`）。

### 这条路的真实条件

```pascal
if (Opacity < 1.0) and (TyAlphaOf(OpacityBase) > 0) then   // 铺不透明父底色再叠
  ... Exit;                                                 // （源码是早退，不是 else）
if Opacity < 1.0 then
  FBmp.ApplyGlobalOpacity(...);                             // 真透明
```

`OpacityBase` 全项目**只有一处**赋值（`tyControls.Base.pas:1321`），条件是 `TyResolveParentBg` 成功。滚动条的父是 `TTyCustomControl` 且有主题背景时成功——所以常规场景走的是第一条路。

> **已知风险，用数据定**：`TyResolveParentBg`（`tyControls.Base.pas:1223`）用 `TyFillCentreColor` 取**一个中心代表色**铺平；而带 rect 的 `TyResolveParentBgFill`（`:1106`）注释明确说单色版会把渐变 "smeared flat"。所以渐变列表底、`green` 图片主题下，半透明滚动条底下可能显出一块平色。
>
> **实现第一步在 `green` 主题下量色差**，再二选一：
> - 无感 → 照用，记为已知限制
> - 明显 → 修 opacity 路径改用带 rect 的渐变切片版。这会**顺带修好现存的 `:disabled` 半透明在图片主题下的同一个毛病**（一直存在，没人报过），代价是动 `Base.pas` / `Painter.pas` 共享文件，与另外两个会话有合并冲突面

### 隐藏态仍然可交互

窗口化控件即使 `opacity = 0` 也照常收鼠标。这是**期望行为**：鼠标移到条的位置 → `MouseEnter` → 先显示出来，再谈点击。与 macOS 一致。

---

## 7. 设计期 / headless

- **`csDesigning`：永不隐藏。** 设计器里看不见滚动条是不可接受的
- **headless / 无 timer**：直接到终态，不跑动画，按库内现有惯例

---

## 8. 纯主题档（不占开发量）

「移到滚动条本身上才显示」不用改代码，一段 CSS 就够。补进 `docs/controls/scrollbar.md` 当菜谱：

```css
TyScrollBar { background: var(--chrome-bar-bg); color: var(--scroll-handle);
  border-radius: var(--radius-scroll); opacity: 0.3; }
TyScrollBar:hover  { color: var(--scroll-handle-hover); opacity: 1; }
TyScrollBar:active { color: var(--accent); opacity: 1; }
TyScrollBar:focus  { outline: 2px var(--focus-ring); }
TyScrollBar:disabled { opacity: var(--disabled-opacity); }
```

**必须抄全整块**——用户层写了 `TyScrollBar` 任一条，内置那块（`themes/light.tycss:394-402`）就整体作废。

文档里**必须带上 §6 那条限定**：渐变底 / 图片主题下半透明会铺平色块。不能只给菜谱不给边界。

---

## 9. 顺手修的 doc bug

`docs/controls/scrollbar.md` 只说 `TTyListBox` 与 `TTyMemo` 的内嵌条是静态的，实际 Grid / ListView / ScrollBox / TreeView 也都设了 `AnimationsEnabled := False`。改成 6 个宿主全列。

---

## 10. 测试策略

headless 可测的：

- token 解析：`-1` / `0` / `N` 三种值各自的结果（**含负号能否解析这一条**）
- 三态属性的优先级：`sbahNever` / `sbahAuto` 压过 token，`sbahDefault` 跟随 token
- published default 与构造值一致（RTTI 守卫，库内已有同类）
- 状态机：四个活跃信号各自能否把已隐藏的条唤回；全部撤去后是否进入延时
- 拖动中不隐藏
- `csDesigning` 下永不隐藏
- 宿主转发：6 个宿主各自把属性传到了内嵌条上（**这条是重点——「建好没接线」是本项目的默认故障**）

headless **测不到**、必须真机看的：

- 淡入淡出的观感与时长
- `green` 图片主题下的色块（§6 的判据）
- 隐藏态下鼠标移过去能否唤回并点中

---

## 11. 验收

1. 默认主题下行为与 3.0 完全一致（滚动条一直显示）
2. 现代主题下：滚动出现、停手 1.2 s 淡出、鼠标移到条上持续显示
3. `AutoHide := sbahNever` 能在自动隐藏的主题下强制常显
4. `Form.StyleOverride` 里一行 `TyScrollBar { --scrollbar-auto-hide: -1; }` 能全局关掉
5. 6 个宿主的内嵌条都听话
6. 全量测试绿，无内存泄漏
