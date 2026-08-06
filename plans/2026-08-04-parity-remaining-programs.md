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

## 剩下的单控件大特性(按受众排)

> **2026-08-07 更新**:这张表原来是 26 条。经过两轮并行推进,**13 条已做完**、
> **2 条查明审计本来就写错了**(`TTyComboBoxEx.ItemsEx`、`TTyColorBox.Style` 一直都在)、
> **2 条判定不做并写明了理由**(`TTySplitter.ResizeAnchor`、`TTyProgressBar` 的焦点成员)。
> 划掉的行保留原文,后面接的是**做成了什么**和**仍缺什么** —— 下一批要挑的活都在那些
> "仍缺"里,不必再回头读审计。

| 控件 | 缺什么 | 一句话影响 |
|---|---|---|
| ~~`TTyTreeView`~~ | ~~`Items` 节点对象模型 + `Node.Text`~~ | **已做**(`a8d98b7`):扁平 `TCollection` + `Level`(集合顺序即先序,`Items[i]` 直接对上 LCL 的绝对下标);模式由 `Items.Count > 0` 派生,虚拟路径按构造不受影响;两边都给内容当场抛 `ETyTreeItemMode` 并同时点名。`TTyShellTreeView` 覆写 `SupportsItemModel` 拒绝 |
| ~~`TTyCustomTabStrip`~~ | ~~`TabPosition`、`MultiLine`/`RaggedRight`/`RowCount`、标签图标~~ | **已做**(`b7cbdef` + `d1362d2`):轴无关的一套变换(沿主轴滑动→在条带盒里嵌入→反射屏幕 x),侧边条带**不旋转文字**(与 comctl32 的 `TCS_VERTICAL` 故意不同)。`ScrollOpposite` **不做**——它与拖拽重排是同一件事,见 `plans/2026-08-06-tabstrip-multiline-spec.md` |
| ~~`TTyToolBar`~~ | ~~`TToolButton` 整个类~~ | **已做**(`38bde80`):`TTyToolButton` 六种样式全建。`Grouped`(相邻成组)而非 `GroupIndex`,两向可译且都钉住;`ImageIndex` 落到既有的 `ImageName` 上,只有一份图标状态;`Marked`/`Indeterminate` **故意不做**——它们在 LCL 自己那儿就是不生效的属性。**仍缺**(条本身的成员,下一批):`ButtonWidth`、`DropDownWidth`、`List`、`HotImages`、`DisabledImages`、`OnPaintButton` |
| ~~`TTyStringGrid`~~ | ~~`Cols[]`/`Rows[]` 可赋值的 `TStrings`、`Objects[c,r]`~~ | **已做**:对象槽进 `TTyGridCellAttr`(跟着排序/增删行搬家,**不进撤销栈**),`Cols[]`/`Rows[]` 是 `TTyGridStrings` 活视图,赋值不改结构。见 `docs/controls/grid.md`《对象槽与整行整列赋值》 |
| ~~`TTyCustomGrid`~~ | ~~`Options: TGridOptions`~~ | **已做**(`251db2d`):32 个标志逐条判过,21 个进枚举(其中 9 个是既有状态的**视图**,不二次存储)、11 个不做且各写了理由。`goHeaderPushedLook` 需要 `themes/light.tycss` 里的 `TyGridHeaderSection:active`,`goThumbTracking` 需要滚动条的缝——两个缝都指明了 |
| ~~`TTyComboBox`~~ | ~~`Style` 的 7 个取值~~ | **已做**(`feedabc` + `3643653`):四个取值 + `OnDrawItem` + `OnMeasureItem`,全家 6 个类接线。**仍缺 `csSimple`**——常驻列表是另一种控件形态,已在文档里写明 |
| ~~`TTyComboBoxEx`~~ | ~~`ItemsEx` 集合(`TComboExItem`)~~ | **审计写错了 —— 这个早就有**:`TTyComboExItem` 的 `Caption`/`ImageIndex`/`Indent`/`OverlayImageIndex`/`SelectedImageIndex`/`Data` 与 LCL 的 `TComboExItem` 逐项对得上,`ItemsEx` 是 published 的集合、设计期可编辑。核过 `source/tyControls.ComboBoxEx.pas` |
| ~~`TTyMaskEdit`~~ | ~~LCL 掩码语言、槽内定位编辑~~ | **已做**(`a3e9c87`,**破坏性**):掩码编译成逐位的 `TTyMaskCell`,十二个槽码 + `\` 转义 + 大小写区 + `;存字面量;占位符`。`#` 现在直接抛 |
| ~~`TTyDateTimePicker`~~ | ~~null/空日期模型~~ | **已做**(`d93d782`):`TyNullDate` 用 LCL 的那个值,`SetDateTime` **先判空再钳位**(反过来会把"没填"变成 9999-12-31)。**仍缺**:月份/星期名取自 OS 区域而非应用语言(`Calendar` 与本控件各一处) |
| ~~`TTySpinEdit`~~ | ~~`TFloatSpinEdit`(`Value: Double`、`DecimalPlaces`)~~ | **已做**:新控件 `TTyFloatSpinEdit = class(TTyNumericEdit)`(自己的单元 `tyControls.FloatSpinEdit`),不是 `TTySpinEdit` 的后代——LCL 把家族反着建(`spin.pp:146`),且本控件三个 `Integer` 的 public virtual 缝已有外部覆写者。按钮走 `TTyEdit` 的 `RightReserve`/`PaintTrailing`/`TrailingZone`。`DecimalPlaces` 沿用本库既有拼法 `Decimals`(继承自 `TTyNumericEdit`)。见 `docs/controls/floatspinedit.md` |
| ~~`TTyUpDown`~~ | ~~`Associate`、`ArrowKeys`~~ | **已做**(`0f4f0a2`):`Associate` 是**双向**的(照 LCL 的 `GetPosition` 回读),值走 RTTI 找 published 的 `Text` 而不是 LCL 的 `Caption`——照抄 LCL 会让它对本库自己的编辑框静默失效。`ArrowKeys` 从前被以"结构性不可能"拒掉,那是量错了控件 |
| ~~`TTyImageCollection`~~ | ~~设计期像素流式化、多分辨率母版~~ | **已做**:published 的 `Images` 集合,每项 `ImageName` + base64 PNG(base64 是唯一真相,解码出的 BGRA 只是缓存)。**不走 `DefineProperties` 伪属性**——那种窗体在 IDE 里打不开(`examples/demo/mainform.pas:182` 记着这件事)。同名多项 = 多分辨率母版,取"最小的够用的" |
| ~~`TTyValueListEditor`~~ | ~~`KeyOptions`~~ | **已做**(`825138c`):`keyUnique` 按**同级**判重而不是全表——本控件的行是嵌套的,嵌套本身就会造出合法的重名。**仍缺**:`Keys[]` 只读(LCL 的可写) |
| `TTyHeaderControl` | `Sections` 作为对象集合 | (已判定**不做**:见 017d3b9,索引可达全部 facet) |
| ~~`TTyListBox`~~ | ~~`ScrollWidth` 与横向滚动~~ | **已做**(`3643653`):`ScrollWidth` 是你设的数(LCL 语义),超宽出底部滚动条;顺带开了逐行高度的缝。**横条的实际落点没人验过**——那是 LCL 对齐引擎的事,headless 跑不到,只有 `examples/listbox` 的开关能看 |
| ~~`TTyColorBox`~~ | ~~`Style` 作为集合~~ | **审计写错了 —— 早在 `4e3376a` 就是集合**,八个成员与 LCL 一一对应。只有文档里那句"`Style` 被强制为 `csDropDownList`"是错的,已改 |
| `TTyPanel` | `ChildSizing` 子对象 | (基类已 republish,需确认子对象是否真生效) |
| `TTySplitter` | `ResizeAnchor` | **判定:不做,原因不是工作量**(`825138c`)。LCL 里给它赋值的意思是"离开 Align 模式、进入**锚定模式**"(`SetResizeAnchor` 在 `csLoading` 外强制 `Align := alNone`),而本控件没有锚定模式。挡路的是**验证**:锚定模式的位移全由 LCL 对齐引擎产生,而 `AutoSizeDelayed` 让没句柄的窗体整棵树不对齐 —— 任何 headless 守卫都是假绿。前置条件=一条真分配句柄的测试路径。规格见 `docs/controls/splitter.md` §8 |
| `TTyProgressBar` | `TabStop`/`TabOrder`/`OnEnter`/`OnExit` | **判定:不做**(`825138c`)。它是 `TTyGraphicControl`,**没有句柄**;这四个成员声明在 `TWinControl` 上,所以"补上"等于**新声明四个**没人读的成员。守卫钉的是**基类**,将来若改成窗口化控件会当场变红,把决定重新摆到台面上 |

---

## 建议的下一步顺序

1. ~~**程序 B 的实证**~~ **做完了(2026-08-06),而且四条全收(`240956c` / `aa1a776`)。**
   `TTyPanel`(`4e3376a`)、`TTyControlBar`(继承)、`TTyGroupBox`、`TTyPageControl` 现在都
   published 了那九个成员,RTTI 守卫覆盖四个站。**这一条可以关掉。**
2. ~~**RTL 定性**~~ **定了:做,而且做了。**状态与逐控件的完成度见 `docs/rtl.md`;
   仍然拒绝镜像的地方(功能区、网格竖条、下拉箭头、值列表编辑器…)由
   `tests/test.rtl.pas` 的 `TRtlExclusionTest` 逐条钉住,每条都写了拒绝的理由。
3. **单控件特性**:上表里划掉的行后面那些"**仍缺**"就是下一批的清单。按受众排,现在最靠前的是
   —— `TTyToolBar` 条本身的六个成员(`ButtonWidth`/`DropDownWidth`/`List`/`HotImages`/
   `DisabledImages`/`OnPaintButton`)、`TTyComboBox.csSimple`、日历与日期框的
   月份/星期名跟随应用语言而不是 OS 区域、`TTyValueListEditor.Keys[]` 可写。
4. ~~**程序 C 先量后改**~~ **量完了(2026-08-06),结论是不改。**
   `TTyPaintPanel` 是能放子控件的真容器(实测:子控件有真 Win32 父子句柄),变不了图形控件;
   原本的视觉理由已被 `a1c31d1` 用一个函数修掉。**这一条可以关掉。**
   **替代动作(仍未做)**:`aero` 主题下窗口化控件的四角是纯黑硬角块(17 个内置主题里只有它一个)。
   `aero` 的特殊之处是**同时**有渐变的 `TyForm` 底和带 alpha 的控件阴影,怀疑 `FillCornerGaps` 
   在这个组合下把 `#00000014` 当成 `#000000` 写了进去。

## 这一轮之后仍然欠的账(不在上表里的)

- **39 个 example 仍从代码字面量拼用户可见文案**(已修 `tabset`、`ribbon`)。按量排:
  `listview` 16、`theming` 14、`tabcontrol` 12、`edit`/`grid`/`treeview` 各 10、
  `inputs`/`trackbar` 各 7、`shapes` 6,再往下是长尾。机械但量大。
- **`examples/inputs` 十三个列标题被右边缘切掉**。要逐列决定是折行、缩写还是重排,
  不是一次扫描能扫完的,所以整条留着没动。
- **`TTyPanel` 的 `Caption` 垂直居中且没有 `Layout`**,任何盖住面板中部的子控件都会和它撞字。
  真正的修法是给 `TTyPanel` 加 `Layout`。
- **网格的 `ReadOnly` 拦得住七条编辑路径,拦不住 Ctrl+V / Ctrl+X / 填充柄**。
  已写进 `docs/controls/grid.md` 的已知缺口,修法三行,但它改的是数据写入语义,要单独定。
