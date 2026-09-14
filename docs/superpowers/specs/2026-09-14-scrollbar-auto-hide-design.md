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

> **`-1` 可行，已查证（2026-09-14）**：`ResolveMetric`（`tyControls.StyleModel.pas:1156`）→ `TyEvalLength`（`tyControls.Css.Values.pas:361`）→ `ParsePctOrNum` → `StrToFloat`。
> 中间那道「裸 `--name` 当变量引用」的判断要求**头两个字符都是 `-`**（`(E[1]='-') and (E[2]='-')`），`-1` 的第二个字符是 `1`，躲得过去；也不以 `px` 结尾，不会被剥尾。`StrToFloat` 接受负号，外层还有 `try/except` 回退默认值。
> **求值代码一行都不用改。** §10 仍保留一条负号回归测试——这条链路上任何一环收紧了字符判断，都会静默把 `-1` 变成默认值。

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

**`TTyValueListEditor` 继承的是 `TTyListBox` 不是 Grid**（2026-09-15 查证，`tyControls.ValueListEditor.pas:116`：`class(TTyListBox)`）。本文原先写成 Grid，是错的。它因此继承的是**惰性**滚动条那一套，不是急切的——给它写测试必须先塞够内容把条撑出来，否则「找不到条」会被误读成「转发没生效」。不需要单独实现，但这个区别在写测试时是真的。

---

## 4. 什么算「还在用」

**任一成立 → 显示且不计时；全不成立 → 起延时表，到点淡出。**

1. `Position` 变化——滚轮 / 键盘 / 轨道点击 / 拖动 / **程序化赋值也算**
2. 鼠标在**滚动条自身**上
3. 拖动进行中（此时延时表根本不起）
4. 滚动条有焦点——**只对独立摆放的条有效**：6 个宿主创建内嵌条时一律 `TabStop := False`（拖条不能把焦点从列表抢走），内嵌条永远拿不到焦点

> **四条都是「显示**且**不计时」，不是只有不计时**（2026-09-14 澄清）。前三条的「显示」有现成通道（`MouseEnter` → `NoteActivity`；拖动必然先经过 enter；设计期从 1.0 起步且永不武装），唯独焦点没有——得单独加一个 `DoEnter` → `NoteActivity`。
>
> 少了这一半的后果是真的：独立条淡到 0、定时器停摆，用户 Tab 过来，**焦点就停在一个看不见的控件上**，而且连「按住不放」那条臂都没人去跑。键盘可达性上这是缺陷，不是小事。

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

> **淡入淡出时长是代码常量，不走 token——这是决定，不是漏掉的**（2026-09-14）。硬规则说「视觉值必须走主题 token」，而时长算不算视觉值有争议；决定性的理由是**库里现有的过渡时长全是代码常量**（位置缓动的 120 ms 就写死在调用处），只给滚动条淡出开一个 token 会让这套东西一半在主题里一半在代码里。
>
> 要 token 化就**整体**做：把所有过渡时长一起搬进主题，那是一个独立的话题（motion token），不是这个特性该顺手开的头。在那之前，想调快调慢改常量。

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

> **范围已缩小（2026-09-15，Task 5 审查）**：`opacity = 0` 是这条路的**退化点**——平板色会把 `TyFillParentBg` 辛苦画进 `FBmp` 的正确背景整个盖掉，而滚动条是窗口化控件，那块矩形没有别人会重画。**这是自动隐藏独有的新暴露**：既有的 opacity 消费者只有 `:disabled`，取值 0.5，**从来不到 0**。
>
> Task 5 因此在 `RenderTo` 里加了一条早退——**这一帧 opacity 为 0 就只铺父背景然后收工**，根本不进合成分支。于是：
>
> | 状态 | 走哪条路 | 还有没有平板色风险 |
> |---|---|---|
> | 完全隐藏（**常驻**） | 早退，只铺父背景 | **没有了**，背景像素级正确 |
> | 淡入淡出途中（约 200 ms） | 合成分支 | 仍有，但只是一瞬 |
> | 静止全可见 | 非合成分支（早退） | 不涉及 |
>
> 所以 **Task 9 要量的只剩过渡期那 200 ms**，暴露面比原来小得多。常驻态的平板色已经不存在了。

### 隐藏态仍然可交互

窗口化控件即使 `opacity = 0` 也照常收鼠标。这是**期望行为**：鼠标移到条的位置 → `MouseEnter` → 先显示出来，再谈点击。与 macOS 一致。

### 与宿主的 `Visible` 正交

Grid / ListView / ScrollBox / TreeView 建条时就 `Visible := False`，运行时按「内容装不装得下」开关它。自动隐藏**只动 opacity，绝不碰 `Visible`**：

| 情形 | `Visible` | `FFadeLevel` |
|---|---|---|
| 内容装得下，不需要这条 | `False`（宿主管） | 不参与 |
| 需要，正在用 | `True` | `1` |
| 需要，已淡出 | `True`（**仍是 True**） | `0` |

把淡出做成 `Visible := False` 会让宿主重新布局把槽收掉，与前提 2 冲突。

---

## 7. 设计期 / headless

- **`csDesigning`：永不隐藏。** 设计器里看不见滚动条是不可接受的
- **headless：不建 timer，由调用方驱动 `AutoHideTick`。**

> **这条原来写的是「直接到终态，不跑动画」，是错的**（2026-09-14 纠正）。照字面实现会让整个测试套件变红——headless 恰恰是**唯一**能逐帧观察淡入淡出的地方，`FadingIgnoresAnimationsEnabled` 就是在无句柄的条上断言一个中间值。真正的规则是：**没有句柄就不创建 `TTimer`**（真机由 timer 推，headless 由测试推），动画本身照跑。

### 初始状态：可见，直到第一次被用过才开始计时

一条刚显示出来、还没人碰过的滚动条**保持完全可见**，不会自己淡出。

macOS 是隐藏起步的，但那是 overlay 模式——条不占槽，藏起来什么也不留下。**我们占槽**（前提 2），隐藏起步只会让用户看见一条空着的槽，比看见滚动条更费解。自动隐藏的价值是「用完之后消失」，不是「一开始就不在」。

代价是**一条从来没被滚动过的条会一直显示**。这是有意的，不是漏洞。

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
4. `Form.StyleOverride` 里一行 **`:root { --scrollbar-auto-hide: -1; }`** 能全局关掉。

   **必须是 `:root`,写进类型规则不生效**（2026-09-14 查证）：`Metric` 读的是 `FMergedVars`，而 `RebuildMergedVars`（`tyControls.StyleModel.pas:1199`）只收 `FBaseVars` + 用户 `:root` + 当前 `@mode` 的 `:root`。写在 `TyScrollBar { ... }` 里的 `--var` 只进那条规则自己的 `Decls`，永远到不了 `FMergedVars`。更糟的是规则里的未知属性是**静默丢弃**的（不像未知函数会抛），所以照错写法验收会看到「没报错、看起来生效了」而其实什么都没发生。
5. 6 个宿主的内嵌条都听话
6. 全量测试绿，无内存泄漏
