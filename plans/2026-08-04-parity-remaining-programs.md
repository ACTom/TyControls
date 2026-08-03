# 对齐清单里剩下的三个"程序",以及为什么它们不能当控件缺口修

审计的 566 条站得住的缺口里,**45 条标 LARGE**。其中 **19 条其实是 3 件事**,散落在 19 个
控件条目上;剩下 26 条才是真正的单控件大特性。

把这 19 条当成 19 个控件缺口逐个修,结果一定是这轮一直在清的那种缺陷:
**属性面板给了一个控件根本不看的开关**(`TTyColorButton.Caption` 就是这么来的)。
`tests/test.parity.pas` 里的 `LyingPropertiesStayUnpublished` 专门钉着这件事 ——
`BiDiMode` 至今不许 published,就是因为绘制层一行都没实现它。

---

## 程序 A —— RTL / BiDi(13 条,全 LARGE)

**涉及**:`TTyEdit`、`TTyPanel`、`TTyListBox`、`TTyScrollBar`、`TTyPopupMenu`、`TTyLabel`+`TTyDivider`、
`TTyCustomGrid`、`TTyHeaderControl`、`TTyDateTimePicker`、`TTyPageControl`+`TTyTabSheet`、
`TTyButton` 全族、`TTyCheckBox`/`TTyRadioButton`/`TTyGroupBox`/`TTyCheckGroup`/`TTyRadioGroup`、
`TTyStatusBar`/`TTyStatusPanel`/`TTyCoolBar`/`TTyControlBar`。

**现状(已核过)**:`tyControls.Painter.pas` 与 `tyControls.Base.pas` 里对 BiDi 的引用数是 **0**。
`tyControls.Memo.pas` 里已经把这个决定写进源码注释:该控件是自绘的,`BidiMode` 不在范围内。

**为什么不能逐控件修**:RTL 不是每个控件各加一个属性。它要的是一整套贯穿绘制层的能力 ——
双向文本分段(bidi runs)、镜像后的测量与命中测试、镜像的内边距、镜像的滚动原点。
只加属性不做绘制,等于给 14 个控件各造一个假开关。

**先决**:`TTyPainter` 要先有 RTL 文本能力,这是一整个绘制层的工作,不是控件层的。

**判据**:要么排成一个独立 program 做,要么在 `docs/` 里写明"本库不支持 RTL",
让移植的人一眼看到,而不是让他们在属性面板里找一个不存在的开关。
**目前是第三种状态:既没做,也没写。** 这一条必须先定,再谈别的。

---

## 程序 B —— 停靠(dock)管道(4 条)

**涉及**:`TTyPanel`、`TTyPageControl`、`TTyGroupBox`、`TTyControlBar`。

`DockSite` / `UseDockManager` / `OnDockDrop` / `OnDockOver` / `OnStartDock` / `OnEndDock` /
`OnUnDock` / `OnGetSiteInfo` / `OnGetDockCaption`。

**要点**:这些**是 `TWinControl` 已有的成员** —— 和 `Visible`、整个 Drag 面一样,
代码里本来就编得过,缺的只是 published 和 `.lfm`。审计里"没 published 就是缺口"那条结论
在这里同样成立,但**与 BiDi 有本质区别**:拖放停靠的实现在 LCL 的 `TWinControl` 里,
不在我们的绘制层。也就是说这一批**很可能真的只是 republish**,几行的事。

**下一步**:先做一个实证 —— 在一个 `TTyPanel` 上 republish `DockSite` 及那组事件,
写一个真机探针验证一个控件能不能停靠进去。**能,就是几行;不能,就说明我们的
`AdjustClientRect`/`Surface` 结构挡了 LCL 的停靠管理器,那才是真工作量。**
headless 测不出来 —— 停靠走的是真实鼠标与窗口消息。

**优先级判断**:受众小(这是框架管道,不是用户天天看见的东西),但**如果验证下来真是几行**,
那它的性价比在整个剩余清单里排第一。

---

## 程序 C —— 图形控件 vs 窗口化控件的祖先(2 条)

**涉及**:`TTySpeedButton`、`TTyPaintPanel`。

LCL 的 `TSpeedButton` 和 `TPaintBox` 都是 `TGraphicControl` —— **没有窗口句柄**,
所以它们在父控件的画面上是真正透明的。我们这两个继承自 `TTyCustomControl`(窗口化),
于是父控件背景上的渐变、图片、圆角在它们的矩形里会被自己的擦除截断。

**这条与本轮已知的两个坑直接相关**:
- 窗口化控件不能投阴影(见记忆 `windowed-control-shadow-corners`);
- 窗口化的 ghost 控件会擦到父控件的 LCL `Color`(见 `windowed-ghost-erases-to-parent-color`)。

**这是破坏性变更**:改基类会改变 `Handle`、焦点能力、以及子控件容纳能力。
`TTyPaintPanel` 尤其要看清楚 —— 它现在能不能放子控件?能的话就不能变图形控件。

**判据**:先量清楚**现在到底难看到什么程度**(在带图片主题的窗体上放一个 SpeedButton,
截图),再决定值不值得为它付一次破坏性变更。**不要先改再看。**

---

## 剩下 26 条真正的单控件大特性(按受众排)

| 控件 | 缺什么 | 一句话影响 |
|---|---|---|
| `TTyTreeView` | `Items: TTreeNodes` 整个节点对象模型 + `Node.Text` | 移植过来的 `Items.AddChild(nil,'Root')` 全部编译不过;OI 里没有树节点编辑器 |
| `TTyCustomTabStrip` | `TabPosition`、`MultiLine`/`RaggedRight`/`RowCount`、整套标签图标 | 标签条只能在顶边、只能一行、不能带图标 |
| `TTyToolBar` | `TToolButton` 整个类(6 种 style、`Down`、`Grouped`、`DropdownMenu`…) | 工具条按钮的类型系统整个没有 |
| `TTyStringGrid` | `Cols[]`/`Rows[]` 可赋值的 `TStrings`、`Objects[c,r]` | `Grid.Rows[3] := MyList` 与"每格挂一个对象"两条常用写法没有 |
| `TTyCustomGrid` | `Options: TGridOptions`(~32 个行为标志集合) | 设计器里一个地方翻所有行为开关的入口没有 |
| `TTyComboBox` | `Style` 的 7 个取值(含 owner-draw 三种) | 只有一种下拉形态 |
| `TTyComboBoxEx` | `ItemsEx` 集合(`TComboExItem`) | 这个控件存在的理由本身 |
| `TTyMaskEdit` | LCL 掩码语言(~20 个 token)、槽内定位编辑 | 掩码语言是我们自己的三码;光标不能落进任意槽 |
| `TTyDateTimePicker` | 整个 null/空日期模型(`NullInputAllowed`/`NullDate`) | 字段清不空,"未填写"表达不了 |
| `TTySpinEdit` | `TFloatSpinEdit`(`Value: Double`、`DecimalPlaces`) | 小数版本整个没有 |
| `TTyUpDown` | `Associate`、`ArrowKeys` | 上下按钮绑不到伴随编辑框 |
| `TTyImageCollection` | 设计期像素流式化、多分辨率母版 | 图标进不了 `.lfm`;HiDPI 只能缩放不能换母版 |
| `TTyValueListEditor` | `KeyOptions` | 运行时能不能改键/加行/删行,没有开关 |
| `TTyHeaderControl` | `Sections` 作为对象集合 | (已判定**不做**:见 017d3b9,索引可达全部 facet) |
| `TTyListBox` | `ScrollWidth` 与横向滚动 | 比客户区宽的项看不全 |
| `TTyColorBox` | `Style` 作为集合(组合调色板) | 调色板内容不可组合 |
| `TTyPanel` | `ChildSizing` 子对象 | (基类已 republish,需确认子对象是否真生效) |
| `TTySplitter` | `ResizeAnchor` | 只能按 `Align` 推断改哪边 |
| `TTyProgressBar` | `TabStop`/`TabOrder`/`OnEnter`/`OnExit` | 它在 LCL 里是能拿焦点的 |

---

## 建议的下一步顺序

1. **程序 B 的实证**(半天):republish 一组 dock 成员 + 一个真机停靠探针。
   结论要么"几行搞定,收 4 条",要么"结构挡着,单独排期"。
2. **RTL 定性**(一句话决定):做,还是在文档里写明不支持。**现在这种既不做也不说的状态最差。**
3. **26 条单控件特性**按上表受众排,继续按控件分区并行推进。
4. **程序 C 先量后改**,不要先改。
