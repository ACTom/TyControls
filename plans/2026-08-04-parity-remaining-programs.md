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

### aero 黑角:已修(2026-08-07,真机验证)

**上面那个怀疑(`FillCornerGaps` 丢 alpha)量出来是错的。** 画家侧的 alpha 合成一直是对的
(`tests/test.painter.pas` 的 `TestFillCornerGapsPreservesAlpha` 钉死:`#00000014` 盖白底
得 ~235 灰,不是黑)。真正的链条(逐环实测,探针在共享 scratchpad `a0105_probe/`):

1. aero 是 17 个内置里唯一 `TyForm { background: linear-gradient }` 的主题;渐变底不建
   photo backdrop(`RebuildBackdrop` 只认 `tfkImage`)→ 无 glass host;
2. 窗口化子控件重建父背景走 `TyResolveParentBgFill` 的窗体分支,而
   `ITyThemedBackground.ThemedBgColor` **只答纯色**(out 参数就一个颜色)→ 渐变时答 False;
3. 回落读裸 LCL `Color`;`ApplyChromeTheme` 对非纯色背景**从不设** `Color` → 停在
   `clDefault`;`ColorToRGB(clDefault)` = `$20000000 and $FFFFFF` = **纯黑**;
4. 于是 `TyFillParentBg`(整块底)和 `FillCornerGaps`(角隙补丁)都拿到不透明黑——
   画进去的颜色本来就是黑,不是谁丢了 alpha。(那次"切主题读到 #FAFAFA"其实也是
   这个机制:上一主题设过的 `Color` 残留,不只是采到上一帧。)

**修法**(`source/tyControls.Base.pas`,一处):窗体分支加 `TyThemedFormGradient` ——
纯色仍走接口;渐变经 `TyRebaseGradient` 把窗体的 ramp 切成子控件所在的那一段(带 alpha
则压到不透明);残余回落改 `GetColorResolvingParent`(clDefault 永远不再当黑读)。
守卫:`tests/test.formgradientbg.pas`(5 条,全部探**角像素**;修前红,3 条失败信息在
测试头注释里);变异测试 6 只全捕。

**真机(每主题独立进程 + 屏幕 DC 读回)**:aero 角像素 `#000000` → `#EAF0F7`/`#E8EFF6`
(与 6px 外背景差 1 阶,与同窗体图形控件 TTyLabel 的参照偏差同量级);light/showcase
角=底完全相等,没动;其余主题由 golden/paint 套件守(全绿)。截图
`a0105_before_aero.png` / `a0105_after_aero.png` + 4x 裁剪在共享 scratchpad。

**顺带定死了前任没定死的那点:黑角是"一直在",不是仅首帧。** 修前探针在**不挪窗**的
前提下 `RedrawWindow(ERASE|INVALIDATE|ALLCHILDREN)` 强刷,前后两轮角像素都是
`#000000`(机制上也必然:解析器每次 DrawFrame 都确定性地返回同一个黑)。

**连带**:裸 `TForm`(未设 Color)上的 TTy 控件同样黑角(同一 clDefault 类缺陷),
修后为浅系统灰。两条老测试(`test.groupbox` 标题带、`test.splitter` 抓点)当年是
**踩着黑底才绿的**(splitter 的 +50 蓝优阈值按黑底标定;groupbox 的 `red<100` 其实
量的是黑带),已按白底重标(见各自注释)——又一例 tests-that-pin-the-bug。

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
| ~~`TTyToolBar`~~ | ~~`TToolButton` 整个类~~ | **已做**(`38bde80`):`TTyToolButton` 六种样式全建。`Grouped`(相邻成组)而非 `GroupIndex`,两向可译且都钉住;`ImageIndex` 落到既有的 `ImageName` 上,只有一份图标状态;`Marked`/`Indeterminate` **故意不做**——它们在 LCL 自己那儿就是不生效的属性。**条本身的六个成员也做完了**(本批):`ButtonWidth` = LCL 语义的**下限**(不是统一宽,LCL 的样式集合原样含"不含 `tbsButtonDrop`"这条豁免;可逆——条记着借出的宽度,`FLentImages` 模式的宽度版,Ex 条的溢出判定同一来源);`DropDownWidth` = 0 跟 `--drop-arrow-width` 令牌、正值钉住(标签条 `ImagesWidth` 先例,画/命中/首选宽一个仲裁值);`List` **默认反向**(`True`=图标在旁)——自动尺寸图标占满行高,LCL 的 `False` 默认会让 `ShowCaptions=True` 一个标题都画不出;下发走 `AdoptGlyphLayout`(`AdoptShowCaption` 契约),`GlyphLayout` 在工具按钮上重声明 `stored`+`nodefault`;`OnPaintButton` = LCL 的整体替换签名(六样式全过,`AState` 1-6 真值,不做 LCL 非 Flat 时 1/4→2 的谎报),`SaveHandleState` 括号+按钮裁剪+角探针守卫;`HotImages`/`DisabledImages` **拒绝**——管线把集合图**染成状态 TextColor**,逐状态换色本来就是主题的,残余只有逐状态换形状,拒绝钉在 `TestHotAndDisabledImagesAreDeliberatelyAbsent`,将来要做的缝(`TTyGlyphButtonBase` 受保护虚 glyph 源解析器)写在 `docs/controls/toolbar.md` |
| ~~`TTyStringGrid`~~ | ~~`Cols[]`/`Rows[]` 可赋值的 `TStrings`、`Objects[c,r]`~~ | **已做**:对象槽进 `TTyGridCellAttr`(跟着排序/增删行搬家,**不进撤销栈**),`Cols[]`/`Rows[]` 是 `TTyGridStrings` 活视图,赋值不改结构。见 `docs/controls/grid.md`《对象槽与整行整列赋值》 |
| ~~`TTyCustomGrid`~~ | ~~`Options: TGridOptions`~~ | **已做**(`251db2d`):32 个标志逐条判过,21 个进枚举(其中 9 个是既有状态的**视图**,不二次存储)、11 个不做且各写了理由。`goHeaderPushedLook` 需要 `themes/light.tycss` 里的 `TyGridHeaderSection:active`,`goThumbTracking` 需要滚动条的缝——两个缝都指明了 |
| ~~`TTyComboBox`~~ | ~~`Style` 的 7 个取值~~ | **已做**(`feedabc` + `3643653`):四个取值 + `OnDrawItem` + `OnMeasureItem`,全家 6 个类接线。~~仍缺 `csSimple`~~ **`csSimple` 也已做**(`208a443`):Win32 语义逐条实测,停靠列表就是同一个弹层实例;pick-only 七子类映射成 `csDropDownList`(即 LCL 自家 `SetEditBox(False)` 的映射) |
| ~~`TTyComboBoxEx`~~ | ~~`ItemsEx` 集合(`TComboExItem`)~~ | **审计写错了 —— 这个早就有**:`TTyComboExItem` 的 `Caption`/`ImageIndex`/`Indent`/`OverlayImageIndex`/`SelectedImageIndex`/`Data` 与 LCL 的 `TComboExItem` 逐项对得上,`ItemsEx` 是 published 的集合、设计期可编辑。核过 `source/tyControls.ComboBoxEx.pas` |
| ~~`TTyMaskEdit`~~ | ~~LCL 掩码语言、槽内定位编辑~~ | **已做**(`a3e9c87`,**破坏性**):掩码编译成逐位的 `TTyMaskCell`,十二个槽码 + `\` 转义 + 大小写区 + `;存字面量;占位符`。`#` 现在直接抛 |
| ~~`TTyDateTimePicker`~~ | ~~null/空日期模型~~ | **已做**(`d93d782`):`TyNullDate` 用 LCL 的那个值,`SetDateTime` **先判空再钳位**(反过来会把"没填"变成 9999-12-31)。~~仍缺:月份/星期名取自 OS 区域~~ **也已做**(`d674fd4`,连同 `Calendar` 与本控件各一处) |
| ~~`TTySpinEdit`~~ | ~~`TFloatSpinEdit`(`Value: Double`、`DecimalPlaces`)~~ | **已做**:新控件 `TTyFloatSpinEdit = class(TTyNumericEdit)`(自己的单元 `tyControls.FloatSpinEdit`),不是 `TTySpinEdit` 的后代——LCL 把家族反着建(`spin.pp:146`),且本控件三个 `Integer` 的 public virtual 缝已有外部覆写者。按钮走 `TTyEdit` 的 `RightReserve`/`PaintTrailing`/`TrailingZone`。`DecimalPlaces` 沿用本库既有拼法 `Decimals`(继承自 `TTyNumericEdit`)。见 `docs/controls/floatspinedit.md` |
| ~~`TTyUpDown`~~ | ~~`Associate`、`ArrowKeys`~~ | **已做**(`0f4f0a2`):`Associate` 是**双向**的(照 LCL 的 `GetPosition` 回读),值走 RTTI 找 published 的 `Text` 而不是 LCL 的 `Caption`——照抄 LCL 会让它对本库自己的编辑框静默失效。`ArrowKeys` 从前被以"结构性不可能"拒掉,那是量错了控件 |
| ~~`TTyImageCollection`~~ | ~~设计期像素流式化、多分辨率母版~~ | **已做**:published 的 `Images` 集合,每项 `ImageName` + base64 PNG(base64 是唯一真相,解码出的 BGRA 只是缓存)。**不走 `DefineProperties` 伪属性**——那种窗体在 IDE 里打不开(`examples/demo/mainform.pas:182` 记着这件事)。同名多项 = 多分辨率母版,取"最小的够用的" |
| ~~`TTyValueListEditor`~~ | ~~`KeyOptions`~~ | **已做**(`825138c`):`keyUnique` 按**同级**判重而不是全表——本控件的行是嵌套的,嵌套本身就会造出合法的重名。~~仍缺:`Keys[]` 只读~~ **也已做**(`14d98dc`,LCL 形状:不查重、不看 ReadOnly、越界空操作) |
| `TTyHeaderControl` | `Sections` 作为对象集合 | (已判定**不做**:见 017d3b9,索引可达全部 facet) |
| ~~`TTyListBox`~~ | ~~`ScrollWidth` 与横向滚动~~ | **已做**(`3643653`):`ScrollWidth` 是你设的数(LCL 语义),超宽出底部滚动条;顺带开了逐行高度的缝。~~**横条的实际落点没人验过**——那是 LCL 对齐引擎的事,headless 跑不到,只有 `examples/listbox` 的开关能看~~ **落点真机验过(2026-08-07)**:贴底、全宽、拖得动,截图 `a5db2fbf_listbox_*`(见下方真机目验清单) |
| ~~`TTyColorBox`~~ | ~~`Style` 作为集合~~ | **审计写错了 —— 早在 `4e3376a` 就是集合**,八个成员与 LCL 一一对应。只有文档里那句"`Style` 被强制为 `csDropDownList`"是错的,已改 |
| ~~`TTyPanel`~~ | ~~`ChildSizing` 子对象~~ | **真机验过,生效(2026-08-07)**:表格布局(`.lfm` 流式的 `Layout`+`ControlsPerLine`)把六个叠在 (8,8) 的按钮铺成 3×2;运行时改 `EnlargeHorizontal:=crsHomogenousChildResize` 当场把 80px 按钮拉到 105 填满行;同探针里一块裸 `TPanel`(同设置同子控件)三个轴逐项同行为。唯一意外:`ShrinkHorizontal:=crsScaleChilds` **不把子控件缩到首选尺寸以下**(窄到 100 的面板里 28px 按钮原样溢出)——`TPanel` 上一模一样(27px 照样溢出),是 LCL 全局语义不是本库的缝。探针与截图:`a5db2fbf_csprobe*`(scratchpad) |
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
3. **单控件特性**:上表里划掉的行后面那些"**仍缺**"就是下一批的清单。~~最靠前的
   `TTyToolBar` 条本身的六个成员~~(**已做**,见上表工具条行)。剩下按受众排:
   `TTyComboBox.csSimple`、日历与日期框的月份/星期名跟随应用语言而不是 OS 区域、
   `TTyValueListEditor.Keys[]` 可写。
4. ~~**程序 C 先量后改**~~ **量完了(2026-08-06),结论是不改。**
   `TTyPaintPanel` 是能放子控件的真容器(实测:子控件有真 Win32 父子句柄),变不了图形控件;
   原本的视觉理由已被 `a1c31d1` 用一个函数修掉。**这一条可以关掉。**
   ~~**替代动作(仍未做)**:`aero` 主题下窗口化控件的四角是纯黑硬角块(17 个内置主题里只有它一个)。
   `aero` 的特殊之处是**同时**有渐变的 `TyForm` 底和带 alpha 的控件阴影,怀疑 `FillCornerGaps` 
   在这个组合下把 `#00000014` 当成 `#000000` 写了进去。~~
   **已修(2026-08-07),而且那个怀疑是错的**——黑来自渐变窗体背景解析不出、回落到
   `ColorToRGB(clDefault)`,不是画家丢 alpha。链条、修法、真机前后对比见上面
   "程序 C"一节末尾的《aero 黑角:已修》。

## 这一轮之后仍然欠的账(不在上表里的)

> **2026-08-07 二轮更新**:原四条全部还清 —— example 文案大扫除 `fc24079`(43 例约 740 条)、
> `inputs` 截断 `fc24079`、Panel 垂直轴 `14d98dc`(改型对齐 LCL 的 `TVerticalAlignment`)、
> 网格 `ReadOnly` 三缺口 `14d98dc`。现在欠的是下面这些:

- ~~**网格 Ctrl+X 手势未接线**(从来就没有过;守卫已就位,接=一行 `Ord('X'): CutToClipboard`,grid.md 已写明)。~~
  **已接(2026-08-07)**:`KeyDown` 里与 C/V 一排(修饰键跟自家 C/V 用 Ctrl,不跟 LCL 的 Shift+X——grids.pas:7815 它家 C/V 用 ssModifier、X 却写成 ssShift)。
  手势级测试 `TestCtrlXGestureCutsAndReadOnlyDegradesToCopy` 只走 KeyDown 不直调方法;两个变异(删绑定/绑成复制)都当场红。grid.md 剪贴板一节已同步。
- ~~**`goHeaderPushedLook` 等着 `themes/light.tycss` 的 `TyGridHeaderSection:active` 规则**~~
  **主题那一半已就位(2026-08-08)**:`TyGridHeaderSection:active { background: var(--surface-active); }`
  写进 `themes/light.tycss` 基础层(`--surface-active` = 本库“按下”的既有令牌,同 `TyButton:active`;
  它比列头带自己的 `--surface-chrome` 深,按下那段在带子上读得出来)。**15 套内置皮肤无一改写
  `TyGridHeaderSection`,因此全部继承**——没有“皮肤要跟进”的欠账。
  守卫:`tests/test.themes.pas` 的 `TestPressedGridHeaderSectionIsNotInert` 逐主题×逐模式断言
  按下态与静止态**解析不同**;golden 第 2 号状态槽(`STATES[2] = [tysActive]`)记着值
  (light/dark/showcase 各改 1 行:`bg=k0` → 实心)。变异(删规则)当场红。
  **仍欠控件侧,收标志前必须做完**(`source/tyControls.Grid.pas`,本轮不在改动范围):
  ①`TTyGridOption` 末尾追加 `goHeaderPushedLook`(只增不改序);②记录被按住的列头段
  (照 `FHoverHeaderCol` 那套);③`RenderHeaderSections` 对该段用 `[tysActive]` 解析。
  **注意**:该标志此前并非“已发布却无效”,而是**明确拒收**(`TTyGridOption` 21/32 的取舍里没有它),
  拒收理由正是缺这条规则——所以现在是“缝补好了、可以收了”,不是“修好了一个 bug”。
- **`goThumbTracking` 等着滚动条的缝**(`251db2d` 指名)。
- **工具条逐状态换形图标**:需要 `GlyphButtons.pas` 的受保护 glyph 源解析器缝(`b133548` 指名);
  换**色**已由主题管。另:绘制箭头与命中区差一个右内边距的既有偏差(与 `TTyDropDownButton` 同源,两处必须同改)。
- ~~**`TTyPanel.ChildSizing`**:基类已 republish,**子对象是否真生效从未验过**(headless 跑不到对齐引擎,要真机探针)。~~
  **验过,生效,行已收**(2026-08-07,真机探针;细节见上表 `TTyPanel` 行——含 `ShrinkHorizontal` 不缩到首选以下是 LCL 全局语义的实证)。
- ~~**`examples/panel` 左上面板标题被 Say hello 按钮盖住**(一处 .lfm 布局)。~~
  **已修(2026-08-07)**:`OuterPanel` 加 `VerticalAlignment = taAlignTop`(`14d98dc` 刚落的属性,顺带在 example 里露了脸)。
  选它不选挪按钮:默认标题带**就是**面板垂直中线,190 高的面板里 Top=80 的按钮怎么摆都在带上,而 0..40 顶条按构造无子控件;
  文字零改动 → 两个 `.po` 的 msgid 天然同步。中英截图:`a5db2fbf_panel_en.png` / `a5db2fbf_panel_zh.png`(scratchpad)。
- **README 双语的 "3949 个单元测试" 计数已烂**(2026-08-07 实测 5904,且各 agent 还在加);发版前以 `tytests --all` 的输出为准顺手改。
- ~~**CHANGELOG 未覆盖最近两波**~~ **已补齐(2026-08-07)**:`ec37153` 一次补两波(新控件 + 继续补齐 + 修复三节),
  aero 暗色/chrome 归族随各自提交带了条目(`e294f45`/`c23e45c`/`abc6c42`)。
- **2026-08-07 晚间新开的两单**:examples/toolbar 补 TTyToolButton 演示面(六样式+Grouped+DropdownMenu+OnPaintButton,
  顺带改掉"未接线"旧说明);~~暗色残留键诊断修复(TyScrollContent/TyGridCell/Bevel/BarWrap 在暗 aero 下仍是亮面,
  修完进一致性扫描)~~ **四个键已逐一定性(2026-08-08),只有一个是主题层的账:**
  - **`TyScrollContent` —— 是主题层的账,已修。** 这个键**在任何一层都没有规则**;
    而 `TTyScrollContent.Paint` 只做一次 `FillBackground`,还包在 `if tpBackground in S.Present` 里,
    于是守卫恒假、视口**一个像素都不画**,露出 widgetset 给那个窗口的擦除色。
    `TTyForm.ApplyChromeTheme` 只为**纯色**窗体底重新播种擦除色 → 渐变底皮肤(aero)留着系统灰。
    **真机取色实证**(探针读控件自己的 HWND DC,取四角+中心;源码留在 scratchpad `a90d73f1_probe/`):
    | | 修复前 | 修复后 |
    |---|---|---|
    | aero / light | `F0F0F0` (luma 240) | `FFFFFF` |
    | **aero / dark** | **`F0F0F0` (luma 240) ← 亮斑** | **`1E1E1E` (luma 30)** |
    | default / light | `F5F5F5` | `FFFFFF` |
    | default / dark | `1E1E1E` | `1E1E1E` |
    最后一行正是**为什么这个 bug 只在 aero 上看得见**:`default` 是纯色窗体底,擦除色被按模式重播了;
    aero 是渐变,没人重播。顺带暴露 aero **浅色**模式下视口也一直是 `F0F0F0` 而非主题的白——没人注意过。
    修法:`themes/light.tycss` 基础层加 `TyScrollContent { background: var(--surface); }`(随模式种子走)。
    守卫:`test.modecoherence` 把它加进 `cSurfaceKeys`,**并新增 `cMustPaintKeys` 不透明下限**——
    因为该扫描对"透明"是宽容跳过的,而对这类"只画底色"的控件,**缺失就是 bug**,宽容正好把它放过去。
    变异证明:删规则 → 新守卫红(点名 `default/light`);删规则**且**把下限中和 → **旧扫描全绿**,
    可见这条下限是真新增信号,不是与既有断言重复。
  - **`TyGridCell` —— 不是主题层的账。** `TTyGridPanel` 的窗口化布局格**借用**了 `TTyGrid` 数据格的键
    (`GridPanel.pas` 的 `TTyGridCell.GetStyleTypeKey` → `'TyGridCell'`,典型的"借来的 typeKey"),
    而基础层 `background: none` 对网格正文**是刻意且正确的**。关键是 **`TTyGridCell.Paint` 是个空方法**——
    它根本不解析、不填任何东西,所以**在这个键(或任何键)下写什么值都不会改变一个像素**。
    亮斑纯粹是一个"拒绝作画的窗口化控件"的擦除色。**控件侧**两条路:给布局格自己的 typeKey,
    或让它的 `Paint` 像 `TTyGridPanel` 那样填父背景。
  - **`TyBevel` —— 不是主题层的账。** 解析出来的底色本就随模式一致(走容器族那条共享规则),而控件从不填它。
    暗色下刺眼的亮轨来自 **`source/tyControls.Bevel.pas:197`** 的
    `hiC := TyBevelLighten(baseC, 0.55)`:**不分模式**地把边框色朝**纯白**混 55%
    (配套的 `loC := TyBevelDarken(baseC, 0.45)` 朝黑)。暗色下 `#3F3F46` 混成约 `#A5A5A9` → 亮轨。
    这是控件内部的**模式盲派生**,任何 resolve 级扫描都看不见。修在那处派生(按模式选混向,或走令牌)。
  - **`BarWrap`(换行工具条)—— 未复现为独立缺陷。** `TTyToolBarEx` 不覆写 `GetStyleTypeKey`,
    走的就是 `TyToolBar`;而 `TyToolBar` 早已在 `cSurfaceKeys` 里、且随 `--chrome-bar-bg` 按模式定义
    (`abc6c42` 那波已把 aero 的 rebar/tabs 归入冷色 chrome 族)。`Wrapable = True` 时它**完全走基类布局**。
    真正显浅的是它**所在的容器**(scroll 视口),即上面第一条——修完这条,那条带子跟着对。
    若真机复验仍见异常,再单独立项。
  **本轮只动主题层**(`themes/light.tycss` + 两个生成源 + 测试 + 文档);Bevel/GridPanel 两处**控件侧**修复
  按分工留给后续,理由与确切行号如上,不必重新推导。
- **真机目验清单**:aero 修复前后对比(agent 已截图,但用户没看过)、csSimple、日历/日期框语言切换、
  ~~listbox 横向滚动条的真实落点(demo 开关在,没人看过)~~、~~日期框**弹出**日历的语言(程序化拉不起来,手动点一次)~~、
  ~~`OnPaintButton` 赋值后的即时重绘~~、`examples/rtl` 的既有清单。
  **2026-08-07 划掉的三条全部真机验过(agent a5db2fbf,截图在 scratchpad)**:
  - listbox 横条:开关一按,横条**贴着列表框底边、全宽、厚度合理**(吃掉一行高度),拇指长度 ≈ 388/700 成比例;
    真鼠标拖拽后拇指右移、行内容左滑。`a5db2fbf_listbox_before.png` / `_hbar_on.png` / `_hbar_scrolled.png`(+ 底条放大 `*_bottomcrop.png`)。
  - `OnPaintButton`:真点击运行时赋值,点完**零后续输入**,工具条三个按钮自己变成了 handler 的洋红块(`b133548` 那条闭环)。
    `a5db2fbf_paintbtn_before.png` / `_after.png`。
  - 日期框弹出日历:真鼠标点 chevron 拉开(弹层是懒建的独立顶层窗,240×220,贴着字段正下方);
    **OS 区域是 zh-CN** 而 `--lang=en` 下月份/星期是 **August 2026 / Mon..Sun**,`--lang=zh_CN` 下是 **八月 2026 / 周一..周日**——
    跟应用语言、不跟 OS,`d674fd4` 最后一个缺口闭合。`a5db2fbf_dtp_popup_en.png` / `_dtp_popup_zh.png`(主窗 `_dtp_main_*.png`)。


## 论坛反馈 triage(2026-08-07,https://forum.lazarus.freepascal.org/index.php/topic,74355)

Antek(主要测试者)两页反馈逐条对账:

| # | 问题 | 状态 |
|---|---|---|
| #4/#5 | demo 右/下不能拉伸、dialogs 客户区花 | **已修**(TTyFormSurface,作者已回) |
| #7a | Aero Snap 拖顶不最大化 | **已修**,Antek #13 亲测确认 |
| #7b | 最大化窗口不能拖动还原 | **早已修**(`55adc88`,`TyRestoreDragBounds` 按光标比例还原继续拖;Antek 用的旧 commit)。我 triage 时只看论坛引用的旧注释没先 grep 代码——又一次 capability-built-but-not-wired 类错误。**真机复验通过**(2026-08-07,agent a2b19d,真鼠标 mouse_event):双击最大化→按住标题栏拖 >4px→窗口还原为保存尺寸(520x340 精确)、光标按比例扣在标题栏(74% 屏宽处握在 72% 窗宽,注入异步误差 ±10px)、拖拽无缝继续(两段拖 grab offset 恒定 (374,26)、跟手到落点);双击最大化按住不放+12px 移动**不拽走**,最大化条上双击还原按住不放+50px 移动**也不拽走**(历史回归双向钉死)。手势级 headless 钉子已存在(TMaximizedChromeTest 3 条+TRestoreDragBoundsTest 7 条),无需新增;截图 a2b19d_gesture_*.png |
| #8 | **TTySteps 方向键无效**(焦点拿不到);作者当时说"整个焦点系统要系统性修" | → 新单(连带点击取焦点全面复核) |
| #12/#15 | **TTyScrollBox 四连**:滚动条被子面板盖住 / 滚轮第一格方向反 / 拖滑块闪烁 / 内容跳动;tyscrollcontent 一度不可用 | 拖拽已修过一轮,**其余待复现修复** → 新单 |
| #14 | **`window-shadow: false` 不生效**(border-radius 局部生效);另问 TTyForm 有没有运行时 StyleOverride | **已修 + 已建**(2026-08-07,agent a2b19d 工作树)。根因:可缩放 TTyForm 是 WS_CAPTION\|WS_THICKFRAME 窗口,阴影是 DWM **标准窗框阴影**,与 DwmExtendFrameIntoClientArea margins 无关——解析层一直是对的,死在 DWM 应用层。修法:关阴影=DWMWA_NCRENDERING_POLICY:=DISABLED + WM_NCCALCSIZE 全窗框吞并(关渲染后 L/R/B 窗框带会被画成经典残框,Win10 19044 实测);开阴影=ENABLED(显式设,同 HWND 可实时翻转;顺带修好固定尺寸 WS_POPUP 窗口从未有过阴影的老缺口)。TTyForm.StyleOverride 已建:复用 ResolveOverride+TyMergeStyleSet(一个解析器),经 ResolveChromeStyle 进入全部 7 个 TyForm 解析点,赋值即重铺 chrome(实时翻 shadow/radius 真机验过)。守卫:TFormStyleOverrideTest(7)+TWindowEffectsTest 扩(3,含 DWMWA_NCRENDERING_ENABLED 真句柄回读);真机截图 a2b19d_auto_*.png(scratchpad)。border-radius"局部生效"=Win10 上圆角偏好本来就是 no-op(永远方角),三个时机在 apply seam 全钉;Win11 真机(shadow-off 连带方角?)仍待验 |
| #16 | **HighDPI PerMonitorV2**:跨屏 2-4 秒重算、回来布局永久坏、TyTitleBar 过高 | **未修,作者承诺下周** → 新单(最大) |
| #18a | containers 编译报 unknown property autoscroll | **已修**(d93e676 + check-lfm-props 守卫,他用的 a1c31d1 太旧) |
| #18b | **antdesign 反馈页的输入对话框偶尔关不掉** | 未复现过 → 新单(复现优先;怀疑 EnableWindow 时序,见 swallowed-cm-message-inherited) |
