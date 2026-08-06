# TTyPageControl

## 1. 概述

`TTyPageControl` 是 TyControls 的主题化多页容器，对标 Lazarus 的 `TPageControl`：顶部一排标签页头，每个页签对应一个 `TTyTabSheet` 页面板；同一时刻只显示当前活动页。它**取代了旧的 `TTyTabControl`**——旧控件是“运行期分页面板”，页由控件自身拥有、随 `Tabs` 集合流式化，导致在 IDE 设计器里无法把控件拖进页里。新模型让页成为**窗体拥有、命名、走标准 `GetChildren` 流式化**的真正设计器容器：在设计器里可以直接往每页拖放控件并随 `.lfm` 持久化。

三个单元各司其职：

| 单元 | 类 | 职责 |
|---|---|---|
| `tyControls.TabStrip` | `TTyCustomTabStrip` | 共享的标签头引擎（布局/悬停/横向滚动/关闭×/拖拽重排/活动页交叉淡入/键盘）。与“页”无关，标签数据靠抽象方法供给 |
| `tyControls.TabSheet` | `TTyTabSheet` | 一个页：主题化背景面板 + published `Caption`（页签文字，不画在页面体上）+ 设计期 `ControlStyle` 标志 |
| `tyControls.PageControl` | `TTyPageControl` | 容器：`TTyTabSheet` 页 + 设计器集成（窗体拥有、`GetChildren` 流式化、`csNoDesignVisible` 切换、组件编辑器） |

## 2. typeKey

| 部件 | typeKey | 说明 |
|---|---|---|
| 页控件外框 | `TyPageControl` | `.tycss` 中控件本体的选择器前缀 |
| 页面板 | `TyTabSheet` | 每页背景 |
| 页签头 | `TyTab` | 单个标签头（`:active` 为当前页） |
| 关闭 × 底片 | `TyTabClose` | `TabsClosable = True` 时悬停底片 |

（标签头沿用 `TyTab` / `TyTabClose` 选择器；控件本体用 `TyPageControl`，主题未显式定义时由 seed 派生默认值。）

## 3. 属性与方法

### TTyPageControl

| 成员 | 类型 | 说明 |
|---|---|---|
| `ActivePageIndex` | `Integer`（published, 默认 -1） | 当前活动页零基索引；-1 表示无；赋值裁剪越界；真变化才触发 `OnChange`；随 `.lfm` 往返（载入期写入的值在 `Loaded` 应用） |
| `ActivePage` | `TTyTabSheet`（published） | 当前活动页（读/写；写入即切到该页）。与 `TPageControl` 一致已 published：设计器与 `.lfm` 从此能按**页引用**指定显示哪一页——按索引指定的话，一旦有人重排页签，索引就悄悄指向了另一页。二者指的是同一个选择，`ActivePageIndex` 保留给更方便用索引的代码 |
| `Pages[i]` | `TTyTabSheet`（public, 只读 indexed） | 第 i 页；越界返回 `nil` |
| `PageCount` | `Integer` | 页数 |
| `AddPage(caption)` / `AddTab(caption)` | `: TTyTabSheet` | 追加一页（`Owner` = 控件的 Owner，即窗体；`Parent` = 控件），返回该页；首次追加自动选中 |
| `AddTabSheet` | `: TTyTabSheet` | LCL 的写法与签名（`TPageControl.AddTabSheet`）：不带 caption 参数，返回新页。这是现有 Delphi / Lazarus 代码里建页最常见的一种写法，也是本类此前唯一不认的一种。caption 留空而不是自动生成 `TabSheet1`——LCL 也留空，凭空造一个标签只会变成宿主还得注意去清掉的文字 |
| `RemovePage(i)` | 方法 | 移除并释放第 i 页，自动修正活动页 |
| `MovePage(from, to)` | 方法 | 把某页（连同它的页签）从一个位置挪到另一个位置。重排原语一直存在，但只是个由页签拖拽驱动的 **protected** 钩子，应用代码根本无从排序页面。两端都会裁剪，越界或原地不动直接忽略。`TTyTabSheet.PageIndex` 的公开入口 |
| `IndexOfPageAt(X, Y)` / `IndexOfPageAt(P)` | `: Integer` | 某点落在哪一**页**上，无则 -1。与 `IndexOfTabAt` 问的是不同的问题：那个问页签头，这个问页面体，所以落在页签条上不算页命中，反之亦然。只有活动页有像素，因此最多只有一个索引会应答 |
| `TabHeight` | `Integer`（不设时跟随主题：经典 28 / 现代 38） | 页签头条带逻辑高度（按 PPI 缩放）。`0` = **完全不要条带**（页面铺满控件，由宿主自己驱动切页）；`TyTabHeightAuto`（-1，含任意负值）= 交回主题的 `--control-height`。详见 §注意事项 |
| `TabPosition` | `TTabPosition`（published, 默认 `tpTop`） | 标签条贴在哪条边：`tpTop` / `tpBottom` / `tpLeft` / `tpRight`。LCL 的类型与 LCL 的四个取值，所以移植过来的 `TabPosition := tpBottom` 直接编译、`.lfm` 直接流入。**与 LCL 的一处刻意分歧见 §6「侧边标签不旋转文字」** |
| `MultiLine` | `Boolean`（published, 默认 False） | 标签放不下时**折行**而不是溢出滚动：填满一行就换下一行，条带随之变厚。打开后**溢出箭头一定消失**、滚动偏移归零（两条互斥的路，见 §6「折行」）。LCL 的名字与默认值 |
| `RaggedRight` | `Boolean`（published, 默认 False） | `MultiLine` 打开时，一行内的页签是否保持自然宽度、行尾留白。**默认 False = 拉伸铺满整行**——这是 LCL 的极性（`TCS_RAGGEDRIGHT` 这个样式位是属性为 **True** 时才设的，不设它 comctl32 才拉伸）。`MultiLine` 关着时无效 |
| `RowCount` | `Integer`（public, **只读**） | 折出来的行数：无页签时 0，`MultiLine` 关着时恒 1。行数是布局的**结果**不是输入，所以没有 setter；也正因为没有 setter 才不能 published（`TWriter.WriteProperty` 会跳过无 setter 的属性，对象检查器则报"无法读取"） |
| `TabsClosable` | `Boolean`（默认 False） | 页签头是否显示关闭 × |
| `Images` | `TTyVirtualImageList`（published, 默认 nil） | 页签图标的来源，按各页的 `ImageIndex` 取。类型是 `TTyVirtualImageList` 而不是 LCL 的 `TCustomImageList`：本库的虚拟列表按需渲染、因而**不是** `TCustomImageList` 的后代，属性若写成 LCL 类型，能赋进去的就只剩下 `TTyPainter` 一个都画不出来的那些（`TTyHeader.Images` 正是为此改的类型）。赋值会注册 `FreeNotification`，列表先被释放时引用自动置 nil |
| `ImagesWidth` | `Integer`（published, 默认 0） | 图标渲染边长（逻辑像素）。`0` = 跟随主题令牌 `--tab-icon-size`（默认 16），密度换挡时图标跟着走；非 0 = 钉死。LCL 的 `ImagesWidth` 是从多分辨率列表里**挑一档**，本库的虚拟列表要多大画多大，所以这里是一个尺寸请求。负值按 0 处理 |
| `OnGetImageIndex` | `procedure(Sender; AIndex; var AImageIndex)` | 图标索引的**最终决定权**。在读过该页自己的 `ImageIndex` **之后**触发，`AImageIndex` 以那个值作**种子**——所以处理器看得见自己在覆盖什么，没有处理器时逐页的值原样生效。与 `TTyTreeView.OnGetImageIndex` 同一条优先级规则（控件级列表 → 逐项覆盖 → 事件最后），不另立第三套 |
| `AnimationsEnabled` | `Boolean`（默认 True） | 切页时活动页签头是否交叉淡入（无窗口句柄时直接定格，保证 headless 测试稳定） |
| `OnChange` / `OnChanging` / `OnTabClose` / `OnReorder` | 事件 | 切换后 / 切换前可否决 / 点关闭×可否决 / 拖拽重排提交后 |

页签文字来自各页的 `TTyTabSheet.Caption`（没有 `Tabs` 集合）。

### TTyTabSheet

| 成员 | 说明 |
|---|---|
| `Caption`（published） | 该页的**标签文字**；改动时通知宿主重排标签头（经重写 `TextChanged`）；**不**画在页面体上。**它就是 `TControl.Caption`**：`Caption` 与 `Text` 是同一个字符串，早先的 `FCaption` 影子字段已去掉 |
| `ImageIndex`（published, 默认 -1） | 该页页签的图标，索引进宿主的 `Images`；-1 = 无图标。名字、类型、默认值都与 `TTabSheet.ImageIndex` 一致。**它长在页上而不是宿主的一个平行数组里**，理由与 `Caption` 相同：重排必须把图标连同页一起带走，而按位置索引的第二个数组会把 2 号槽的图标悄悄交给挪进 2 号槽的那一页 |
| `PageIndex`（published, `stored False`） | 该页在宿主里的位置，**可写**：赋值即**移动**该页（连同页签）。此前排序只能靠用户拖页签——重排原语是 protected 且没有任何入口——所以"最近使用顺序""按文档名排序"这类由数据决定的顺序，从代码里完全表达不出来。`stored False`（与 `TTabSheet` 一致）：顺序已经由页流式化的先后承载，再存一份就是同一个事实有两个真相来源 |
| `PageControl`（public, 读/写） | 该页所属的宿主，**读/写**——赋值即把页搬到另一个宿主，与 `TTabSheet.PageControl` 一致。此前只能读 `Parent` 再硬转型，那对任何 parent 都编译得过、只在运行期才炸。类型是 `TTyCustomTabStrip` 而非 `TTyPageControl`，这一点由单元依赖图决定：`tyControls.PageControl` 的 **interface** 需要 `TTyTabSheet`（页数组、`AddPage` 的返回类型），所以具体宿主类型无法出现在本单元的 interface 里，否则 interface 段循环引用。标签条基类是编译期能表达"这是个标签宿主"的最近类型；页级成员仍需转型 |
| `OnShow` / `OnHide`（published） | 本页成为 / 不再是活动页时触发。此前逐页的进入/离开逻辑（延迟加载内容、离开时校验）只能集中到宿主的 `OnChange` 里再按索引 if/case 分发，页无法拥有自己的行为；移植过来的 `OnShow`/`OnHide` 处理器也无处可挂。名字、签名与触发时机都与 `TCustomPage` 一致（经 `CM_VISIBLECHANGED`） |
| `Left` / `Top` / `Width` / `Height` / `TabOrder` / `Visible` | 六个都重声明为 `stored False`（与 `TCustomPage` 一致）。它们统统归宿主管：构造时强制 `Align := alClient` 与 `Visible := False`，宿主每次切页都会重写 `Visible`。序列化的话，每一页都会往 `.lfm` 里写一个 `Visible = False` 和一组载入时会被对齐引擎覆盖掉的 bounds——纯噪声，每次进设计器都让 diff 再翻腾一遍，而且那个被持久化的 `Visible = False` 要靠 `Loaded` 跑起来才被撤销，而不是压根就没写过。**只影响写入**；已经带着这些值的旧 `.lfm` 照常读取 |
| `ControlStyle` | 构造时加 `csAcceptsControls, csDesignFixedBounds, csNoDesignVisible, csNoFocus`；`Align = alClient` |

> **换宿主时的注销（一个真实缺陷的修复）**：离开一个宿主与加入一个宿主同样是页列表事件，而此前只接了加入那一半——注销挂在 `Notification(opRemove)` 上，那是页被**释放**时触发的，不是被重新 parent 时。于是把一页搬到第二个宿主，会让它同时被两个宿主计数、画页签、并从 `Pages[]` 里发出来：旧宿主还在为一个已经不在它里面的控件画标签页。现在 `TTyTabSheet.SetParent` 两半都做（拆除过程中跳过——`Notification` 已经覆盖释放路径）。

## 4. 设计器里使用

1. 从 “TyControls” 调色板拖一个 `TTyPageControl` 到窗体。
2. 右键控件 → 组件编辑器动词：
   - **Add Page** —— 新建一页（窗体拥有、自动命名、设为活动页）。
   - **Delete Page** —— 删除当前活动页。
   - **Show Next Page / Show Previous Page** —— 切换活动页。
   - 也可在对象检查器改 `ActivePageIndex` 或 `ActivePage` 切页（两者都已 published）。
3. 把控件拖到**当前可见页**的主体上——落在该 `TTyTabSheet` 上，随 `.lfm` 持久化（嵌套在该页的 `object` 块里）。切到别的页继续拖，逐页布局。

> **没有“点页签头切页”**：本控件是自绘的，不像原生 `TPageControl` 能靠 OS 原生控件在设计期点 tab 切页；自绘控件无法既让设计器转发点击切页、又保留正常的选中/拖放（详见设计的根因分析）。因此设计期切页一律用组件编辑器动词 / 对象检查器。

改动控件库代码后需重新编译/安装 `tycontrols_dt.lpk` 并重启 Lazarus，调色板与设计器才用上新行为。

## 5. 给每页添加控件（代码）

```pascal
var Pg: TTyTabSheet;
Pg := PageCtrl.AddPage('设置');     // 返回新页
MyEdit.Parent := Pg;                 // 往该页放控件
MyEdit2.Parent := PageCtrl.Pages[0]; // 或按索引
PageCtrl.ActivePage := Pg;           // 切到该页
```

## 6. 标签头能力（继承自 TTyCustomTabStrip）

- **横向滚动**：标签头溢出时显示左右箭头；`ScrollTabIntoView`/`SetHeaderScroll`/`TyMaxHeaderScroll` 等几何 API（设备像素）供测试与自定义命中。
- **拖拽重排**：按住页签头拖动可重排页顺序，提交后触发 `OnReorder(从, 到)`。选中项钉在**位置**上而不是跟着被拖的那一页走；此前只有页签头遵守这条规则，`Visible` 属于页对象、数组重排后没有任何东西重新赋值它，于是把一页拖过选中页会让"高亮的页签"和"显示的页面"对不上，直到下一次点击才恢复。现在 `DoReorderTabs` 末尾重新应用 `ShowOnlyPage`。

### 带 LCL 名字的几何 / 命中 / 滚动成员

这三个（加上 `TTyPageControl.IndexOfPageAt`）用的是 LCL 的名字，因此必须承担 LCL 的**语义**——引擎里本来就各有一个近似的孪生成员，而三处的孪生成员回答的都是**另一个问题**，那正是移植过来的调用点绑错成员、拿到一个貌似合理的错误答案而非编译错误的方式。

| 成员 | 语义，以及它不是哪个孪生成员 |
|---|---|
| `TabRect(i)` | 页签头**绘制时**的矩形——已应用滚动偏移与左侧内缩。`TyTabHeaderRect` 是**未偏移**的内容空间矩形：标签条放得下时两者相同，放不下时正好差一个滚动偏移——而那恰恰是调用方要把菜单/浮层放到某个页签上时需要区分的时刻 |
| `DisplayRect` | 页面**体**在控件内占的矩形（控件局部设备像素，标签条以下）。此前这个内缩只存在于 `AdjustClientRect` 内部，没有任何对外访问点 |
| `IndexOfTabAt(X, Y)` / `IndexOfTabAt(P)` | 某点下是哪个页签，无则 **-1**。`TyDropIndexAt` 不是它、也不能拿来当它用：那是拖拽重排的落点解析器，按偏移后的中点找**最近的槽位**并裁剪进 `[0, Count-1]`，因此**永远说不出"这里没有页签"**——问它"右键点在最后一个页签之后的空白条带上是哪个"，它会回答最后一个页签。基于它做右键菜单或逐页签 tooltip，菜单就会开在用户根本没瞄准的页签上。本方法命中的是真实的偏移后页签矩形，要求点落在条带内，其余一律返回 -1（含两个溢出箭头——它们不是页签） |
| `ScrollTabs(Delta)` | 按 **Delta 个页签**滚动标签条——LCL 的单位（`comctrls.pp:711/862`），不是我们的。`SetHeaderScroll` 收的是**设备像素**，所以把移植来的 `ScrollTabs(2)` 机械改名过去会滚动两个像素，看上去像什么都没发生。实现落在页签边界上而不是按平均页签宽度换算，因为各页签的标题宽度通常差别很大 |
- **可关闭页签**：`TabsClosable = True` 时每页签头右侧有关闭 ×，点击触发 `OnTabClose`（可否决）。
- **活动页交叉淡入**：切页时活动页签头背景从非活动样式淡入活动样式（仅页签头颜色淡入，页内容瞬时切换）。
- **键盘**：`←/→` 上一/下一页（右到左镜像时两键对调，见下），`Home/End` 首/末页，`Ctrl+Tab` / `Ctrl+PageUp/PageDown` 切页。
- **`TabPosition`——标签条贴哪条边**：`tpTop`（默认）/ `tpBottom` / `tpLeft` / `tpRight`。四种形态走**同一套布局与同一个坐标变换**：`RebuildLayout` 始终把标签排成一条**一维的行程**（沿"主轴"，阅读序，第 0 个在起点），`ToScreenRect` 再把这条行程嵌进控件的方框里。`tpTop` 时那个嵌入是恒等映射，所以默认形态与加这个属性之前**逐字节相同**。
  - 顶/底：主轴是横的，每个页签**宽度**=标题盒，条带**厚度**=一个 `TabHeight`。
  - 左/右：主轴是竖的，每个页签**高度**=一个 `TabHeight`，条带**厚度**=**最宽的那个标题盒**。
  - **侧边标签不旋转文字（与 LCL 的刻意分歧）**：LCL 的 `tpLeft/tpRight` 转交给 comctl32 的 `TCS_VERTICAL`，那会把标题**旋转 90°**；本库不旋转——侧边条带是一摞等高、文字正立的行，宽度取最长的标题。这既是当代主题化侧边栏（VS Code、Ant Design 的 `tabPosition="left"`）的做法，也是本库画笔在任意 DPI 下能画清楚的做法；转一次 90° 的文字在自绘管线里要么糊要么得另开一条渲染路径。
  - `AdjustClientRect` / `DisplayRect` 跟着扣**对应那条边**：`tpBottom` 扣底、`tpLeft` 扣左、`tpRight` 扣右。
  - **键盘**：主轴是竖的时候 `↑/↓` 走上一/下一页；主轴是横的时候 `↑/↓` **不被吞掉**（顶部条带上的 `↑/↓` 一直是留给宿主/页内容的，加了侧边形态也不能改这一点）。`←/→` 四种形态下都走。
  - **溢出箭头**跟着主轴转向：侧边条带上是"上/下"两个 V 形，分别贴在条带的上下两端。
  - `TTyRibbon` 也是这套标签头引擎的子类，但它自己的 File 页签、折叠 V 形与 KeyTip 角标都钉死在顶边，所以 `TabPosition` **只在 `TTyPageControl` / `TTyTabSet` 上 published**，功能区的对象检查器里看不到它。

- **`MultiLine`——折行而不是滚动**：`MultiLine := True` 时，行程沿主轴填满一行就**换行**，条带厚度变成 `RowCount ×` 一行的厚度。一行的厚度还是原来那一个值（顶/底是 `TabHeight`，左/右是最宽的标题盒），没有新令牌。
  - **折行与溢出滚动互斥，打开折行就一定关掉箭头**：内容已经全部可见，再留一条箭头带等于凭空吃掉两端各 16px、并把每行的第一个页签推到箭头底下。`TyMaxHeaderScroll` 因此在折行时恒为 0，正在生效的滚动偏移会被**丢弃**（而不是保留一个已经无处可去的偏移）。
  - **一个比整条带还宽的页签独占一行并允许溢出边界**——没有更窄的地方能放它。这条不能省：省掉它，这种页签会在行首就触发折行、被推到下一行，**上面留下一整行空的**。
  - **`RaggedRight = False`（默认）把每一行拉伸铺满**，余数逐个像素发下去而不是丢掉：只用 `extra div n`，一行最多会差 n-1 个像素到不了条带边缘，在有页签边框的皮肤上就是每行行尾一个看得见的缺口。只有一个页签的那一行同样被拉成整条带宽（comctl32 也是如此，这正是多行标签看起来"两端对齐"的原因）。
  - **左/右条带的"多行"是多列**：主轴竖着走，折行就是开一列新的，条带宽度变成 `RowCount ×` 最宽标题盒。同一段代码、同一句话——这是布局本来就是一维的结果，也是这一点上我们与 comctl32（`TCS_MULTILINE` + `TCS_VERTICAL`）**一致**的地方。
  - **命中/拖拽落点在折行下比较两个轴**：命中原来只比主轴（单行时每个页签的次轴范围就是整条带，与两轴等价），折行后两个页签会占同一段主轴，只比主轴会让第 1 行整行**画得出来却点不到**。拖拽落点从"第一个中点在指针之后"变成 `(行, 主轴中点)` 的**字典序**比较；指针的行会被**钳进条带**，所以 `RowCount = 1` 时字典序精确退化成原来那条规则（不是近似）。
  - **不做「选中行重排」，因此也不提供 `ScrollOpposite`（与 LCL 的刻意分歧）**：Delphi/comctl32 在 `MultiLine` 下点了非贴近页面体那一行的页签时会**重排行**，把被选中的那一行挪到贴着页面体，`TCS_SCROLLOPPOSITE` 决定其余的行往哪边走。本库不这么做，理由不是省事：那个重排会把"选中"从一个**渲染状态**变成**布局输入**，而本控件有一件 comctl32 从来没有的事——**拖拽重排**。拖拽时选中钉在**位置**上，所以一次跨行的重排会改变"哪一行被选中"，行随即重排，页签在指针底下**换了位置**；这正是本控件历来最容易出问题的那条缝。代价是：`tpTop` 下只有最后一行的页签会与页面体的框融成一体，活动页签在别的行里靠填色区分。若将来要做，`ScrollOpposite` 必须与行重排在**同一次改动**里落地，否则就是一个 published 却什么都不做的属性。
  - 折出来的行会一直吃条带厚度，行数够多时页面体会被挤没（`InsetForBand` 会把体裁到零）。comctl32 同样如此。

- **页签图标**：`Images`（控件级列表）+ 每页的 `ImageIndex`（逐项覆盖）+ `OnGetImageIndex`（最终决定权），三层的顺序与 `TTyListView` / `TTyTreeView` 一致。图标槽位在**测量阶段**就预留进标题盒（`--tab-icon-size` + `--tab-icon-gap`），所以页签会按图标宽度**变宽**，它旁边的页签一个像素都不动。没有 `Images` 时整条路径不产生任何开销、也不改变任何一个像素。

- **右到左镜像**：`BiDiMode := bdRightToLeft` 时整条标签带镜像——第 0 页的页签在**最右**，往左排；关闭 × 挪到每个页签头的**左**边（图标也跟着挪到右边）；两个溢出箭头对调两端并且各自转向（"上一批"那个永远在阅读起点，也就是镜像时的右端）；向后滚动时标签带往**右**滑；`←/→` 跟着眼睛走（左键=下一页）。`Home/End` 与 `Ctrl+Tab` 是**逻辑**首尾/循环，不翻。
  **左/右边标签的镜像是"换边"，不是"倒序"**：镜像反射的是**屏幕横轴**。顶/底条带的主轴就是横轴，所以反射把页签顺序倒过来（一直如此）；左/右条带的主轴是竖的，横轴反射碰不到它——反射到的是**次轴**，于是 `tpLeft` 的条带整条搬到**右**边（`tpRight` 搬到左边），条带内每一行里的关闭 × 与图标也各自换端，而**上下顺序不变**，`↑/↓` 也不对调。这与"`Home/End` 是逻辑首尾"是同一条判据：横向反射不可能给一条竖着走的行程重新排序。相应地，页面体现在会被扣在**镜像后**的那条边上。
  **页内子控件不镜像**（`Align`/`Anchors` 排布跟随 LCL，见 [panel.md](panel.md)）；但 `BiDiMode` 会按 LCL 的 `ParentBiDiMode` 传播给页里的控件，所以页上的复选框、标签等各自会翻自己的指示器与文字。
  一个**名字会骗人的成员**：`TyTabScrollLeftRect` 是"上一批"箭头，镜像时它在**右**端；`TyTabScrollRightRect` 在左端。改名是破坏性变更，收益不抵成本，所以名字保留、在这里写清楚。取指针坐标请用 `TabRect(i)`（绘制时的矩形），不要用 `TyTabHeaderRect(i)`——后者是**阅读序内容空间**的矩形，镜像时它不是屏幕坐标。
- **`TabHeight` 的三种取值（与 LCL 的差异，刻意保留）**：
  | 取值 | 含义 |
  |------|------|
  | 不设 | 跟随主题 `--control-height`：经典 28、现代 38 |
  | `> 0` | 钉住该逻辑高度，并写入 `.lfm` |
  | `0` | **完全不要条带**——页面铺满控件，宿主自己驱动切页（侧边栏、分段控制器）。会写入 `.lfm`，重新载入后仍然没有条带 |
  | `TyTabHeightAuto`（`-1`，任意负值同义） | **交回主题**，回到"不设"状态 |

  LCL 的 `TabHeight` 是 `Smallint`，`<= 0` 一律表示"按字体自动定高"，且只在 `> 0` 时序列化。本库的 `0` 另有其义：LCL 要"不要条带"得写 `ShowTabs := False`，而我们没有那个属性，`0` 就是它——例子 `examples/tabcontrol` 在运行期来回切换的正是这个。所以 `0` 保持原义，LCL 的"自动"落在 `<= 0` 的**负半边**并有了名字 `TyTabHeightAuto`：从 Lazarus 移植过来的 `TabHeight := -1` 行为与在 Lazarus 里一致，不会静默变成"藏掉条带"。**唯一要注意的是显式写字面量 `0` 却指望"自动"的移植代码**——它想要的是 `TyTabHeightAuto`；Lazarus 生成的 `.lfm` 里永远不会带这个坑，因为 LCL 根本不序列化 `0`。
  - 类型保持 `Integer` 而非 LCL 的 `Smallint`：默认 `{$R-}` 下窄化会让过大的赋值静默回绕，那正是本轮要清理的同一类静默错误。
  - `stored` 条件是"宿主钉过它"而非 LCL 的 `> 0`：设计期定的 `0` 是一个真实决定，用 `> 0` 会在每次重新载入时把它丢掉，条带又悄悄冒回来。

## 7. 流式化（.lfm）

与 `TPageControl` 同构——页是窗体拥有的子控件，走默认 `GetChildren`（`Owner = Root`），页和页内控件都按标准方式嵌套保存：

```
object TabCtrl1: TTyPageControl
  ActivePageIndex = 0
  object TyTabSheet1: TTyTabSheet
    Caption = 'Tab 1'
    object Btn: TTyButton ... end   // 拖到该页的控件，嵌套于此
  end
  object TyTabSheet2: TTyTabSheet
    Caption = 'Tab 2'
  end
end
```

载入时页经 `TTyTabSheet.SetParent` 自动注册到宿主，`ActivePageIndex` 在 `Loaded` 应用。运行期表单加载需要页类已注册——`TTyTabSheet`/`TTyPageControl` 在各自单元 `initialization` 调用 `RegisterClass`。

## 8. 仅要“标签条”而非容器？

若只需要一排标签（不托管页、自己在 `OnChange` 里切内容），请用 **`TTyTabSet`**（SP2，纯标签条，与 `TTyPageControl` 共享 `TTyCustomTabStrip` 基类）。
