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

### 实证结果(2026-08-06,真机)——**结论:就是几行,4 条可以全收**

探针:`.lfm` 建的 `TTyForm`(带真 `TTyTitleBar`),四个停靠站放在 `TTyFormSurface` 里,
拖的是**真鼠标输入**(`mouse_event` 注入系统输入队列,由 Windows 命中测试、走真实消息泵和
LCL `DragManager`),**不是 `ManualDock`**。

**先说一件必须先查的事:`TTyPanel` 这 9 个成员早在 `4e3376a` 就已经 republish 了。**
提要里"先在 `TTyPanel` 上 republish"这一步不用做——它已经在。
(又一次 `capability-built-but-not-wired`:说"缺 X"之前先查 X 在不在。)

真机拖放,四个站**全部接受停靠,且一行源码都没改**(`DockSite` 在 `TWinControl` 上是
public,所以能从代码里打开来测):

| 站 | 真拖放 | `DockClientCount` | RTTI 已 published |
|---|---|---|---|
| `TTyPanel` | DOCKED | 0→1 | **9/9**(`4e3376a`) |
| `TTyGroupBox` | DOCKED | 0→1 | **0/9** |
| `TTyPageControl` | DOCKED | 0→1 | **0/9** |
| `TTyControlBar` | DOCKED | 0→1 | **9/9**(继承自 `TTyPanel`,白捡) |

`TTyPanel` 上把九个事件全接上跑一遍,真拖放依次触发:
`OnStartDock 1 / OnGetSiteInfo 25 / OnDockOver 17 / OnDockDrop 1 / OnEndDock 1(Target=Site)`,
结束后 `DockClient.Parent=Site`、`HostDockSite=Site`、`DockClientCount=1`。

**关键结构问题的答案:`TTyFormSurface` 不挡。** 站的 `Parent` 就是 `Surface`,
`AdjustClientRect` 也没有妨碍 `FindDragTarget` 找到它。

**探针自身做过变异测试**(否则"4/4 全 DOCKED"可能只是个永远打印 DOCKED 的假绿):
同一段代码、同一次拖放,只把 `DockSite` 置 `False` →
`REFUSED,DockClientCount 0->0,DockDrop=0,HostDockSite=nil`。探针分得出来。

**所以剩下的工作量 = 给 `TTyGroupBox` 和 `TTyPageControl` 各补 9 行 `property`,没有实现。**
(这两个文件本轮有别的 agent 在改,故未动手。)

顺带证实了 `tyControls.Panel.pas` 注释里的说法:`OnGetSiteInfo` / `OnGetDockCaption` /
`OnStartDock` / `OnEndDock` 在 `TWinControl` 上是 **protected**——拿一个 `TWinControl`
引用去赋值会直接编译不过(`identifier idents no member "OnGetSiteInfo"`)。
也就是说这四个**连代码都够不着**,republish 不只是"给设计器看",是唯一的通路。

**headless 那份测试是真绿但覆盖不到这里**:`tests/test.parity.container.pas` 全程只调
`ManualDock`,那是编程接口,直接 reparent,根本不经过 `DragManager`,也就不会碰
`OnStartDock`/`OnGetSiteInfo`/`OnDockOver`/`OnEndDock` 这四个。该文件 303-307 行的注释
自己也承认了这一点。所以它不算假绿,只是**测的是另一件事**。

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

### 实证结果(2026-08-06,真机)——**结论:不值得,建议关掉这一条**

**一、`TTyPaintPanel` 现在就能放子控件,所以它不可能变成图形控件。**
不是推理,是真放了一个:`TTyPaintPanel = class(TTyPanel)`,`csAcceptsControls = True`,
把一个 `TTyButton` 认到它里面 → `Parent=TTyPaintPanel`、`ControlCount=1`、
`HandleAllocated=True`,且 `GetParent(子.Handle) = 面板.Handle`(真的 Win32 父子窗口)。
`TGraphicControl` 没句柄,认不了任何东西。**这一条到此为止。**

**二、上面那个"渐变/图片被自己的擦除截断"的前提,已经不成立了。**
`a1c31d1`(本轮已并入)修的就是这件事,提交信息末尾写得很明白:
"这是对那个促使有人提议把 `TTySpeedButton` 挪到 `TGraphicControl` 的缺陷的**相称修法**。
一个函数,所有渐变父控件上的窗口化控件一次修好。"
真机复核(`themes/green.tycss`,真图片背景):6px 外的背景与控件角像素只差 1~3 个色阶
(那是照片本身的噪点),4 倍放大截图里 SpeedButton 的圆角外照片是**连续的**,
`TTyPaintPanel` 更是整块透明——只看得见它的子按钮。**没有可见的擦除矩形。**

**三、但量出来一个真的、可见的残留缺陷,而且它不支持改基类。**
17 个内置主题各起一个独立进程、置前、6 秒后从屏幕 DC 读回控件左上角像素:

> **只有 `aero` 一个主题**,窗口化控件四角出现纯 `#000000` 的硬角块(1/17)。
> 同一窗体里的图形控件 `TTyLabel` 角像素干净。6 倍放大截图里,两个 SpeedButton、
> `TTyPaintPanel`、连它里面的子按钮,四角全是黑的。

这就是记忆里的 `windowed-control-shadow-corners`(角隙填充)。`aero` 的特殊之处不是"有阴影"
——`showcase`/`office`/`fluent` 也定义了 `shadow:`,且都不黑——而是**只有它同时是
`TyForm { background: linear-gradient(...) }` 的渐变底 + 控件带阴影**。
所以怀疑是角隙填充在"渐变父背景 + 带 alpha 的阴影色"这一组合下丢了 alpha,把
`#00000014` 当成 `#000000` 写了进去。

**这不构成改基类的理由**:它是 1/17 的主题级缺陷,已经有 `FillCornerGaps` 这条便宜的修法,
而 `TTyPaintPanel` 无论如何都改不动(见第一条)。**建议:把程序 C 关掉,
另开一张小票修 `aero` 的角隙填充。**

**没能定死的一点(别当结论用)**:黑角是"仅首帧"还是"一直在",没验成——
强制重绘那次窗口被最小化/还原挪了位,前后截图不是同一块区域,不可比。
另外探针内部那版"切主题连续采样"的扫描**不可信**(它给 `aero` 读到 `#FAFAFA`,
那正好是上一个主题 `adwaita` 的背景色,典型的采到上一帧);**上表用的是每主题独立进程那一版。**

---

## 剩下 26 条真正的单控件大特性(按受众排)

| 控件 | 缺什么 | 一句话影响 |
|---|---|---|
| `TTyTreeView` | `Items: TTreeNodes` 整个节点对象模型 + `Node.Text` | 移植过来的 `Items.AddChild(nil,'Root')` 全部编译不过;OI 里没有树节点编辑器 |
| `TTyCustomTabStrip` | `TabPosition`、`MultiLine`/`RaggedRight`/`RowCount`、整套标签图标 | 标签条只能在顶边、只能一行、不能带图标 |
| `TTyToolBar` | `TToolButton` 整个类(6 种 style、`Down`、`Grouped`、`DropdownMenu`…) | 工具条按钮的类型系统整个没有 |
| ~~`TTyStringGrid`~~ | ~~`Cols[]`/`Rows[]` 可赋值的 `TStrings`、`Objects[c,r]`~~ | **已做**:对象槽进 `TTyGridCellAttr`(跟着排序/增删行搬家,**不进撤销栈**),`Cols[]`/`Rows[]` 是 `TTyGridStrings` 活视图,赋值不改结构。见 `docs/controls/grid.md`《对象槽与整行整列赋值》 |
| `TTyCustomGrid` | `Options: TGridOptions`(~32 个行为标志集合) | 设计器里一个地方翻所有行为开关的入口没有 |
| `TTyComboBox` | `Style` 的 7 个取值(含 owner-draw 三种) | 只有一种下拉形态 |
| ~~`TTyComboBoxEx`~~ | ~~`ItemsEx` 集合(`TComboExItem`)~~ | **审计写错了 —— 这个早就有**:`TTyComboExItem` 的 `Caption`/`ImageIndex`/`Indent`/`OverlayImageIndex`/`SelectedImageIndex`/`Data` 与 LCL 的 `TComboExItem` 逐项对得上,`ItemsEx` 是 published 的集合、设计期可编辑。核过 `source/tyControls.ComboBoxEx.pas` |
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

1. ~~**程序 B 的实证**~~ **已做完(2026-08-06)。结论是"几行搞定"。**
   剩余动作只有一个:给 `TTyGroupBox` 和 `TTyPageControl` 各补 9 行 `property`
   (照抄 `tyControls.Panel.pas:76-84`),外加两条 RTTI 守卫。
   `TTyPanel`(`4e3376a`)和 `TTyControlBar`(继承)这两条**已经可以直接勾掉**。
2. **RTL 定性**(一句话决定):做,还是在文档里写明不支持。**现在这种既不做也不说的状态最差。**
3. **26 条单控件特性**按上表受众排,继续按控件分区并行推进。
4. ~~**程序 C 先量后改**~~ **已量完(2026-08-06)。结论是不改,建议关掉这一条**
   ——`TTyPaintPanel` 是能放子控件的真容器,变不了图形控件;而原本的视觉理由已被
   `a1c31d1` 用一个函数修掉了。**替代动作**:开一张小票修 `aero` 主题下窗口化控件的黑角
   (1/17 主题,`FillCornerGaps` 在"渐变底 + 带 alpha 阴影"下疑似丢 alpha)。
