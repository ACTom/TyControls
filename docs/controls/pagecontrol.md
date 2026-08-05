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
| `TabsClosable` | `Boolean`（默认 False） | 页签头是否显示关闭 × |
| `AnimationsEnabled` | `Boolean`（默认 True） | 切页时活动页签头是否交叉淡入（无窗口句柄时直接定格，保证 headless 测试稳定） |
| `OnChange` / `OnChanging` / `OnTabClose` / `OnReorder` | 事件 | 切换后 / 切换前可否决 / 点关闭×可否决 / 拖拽重排提交后 |

页签文字来自各页的 `TTyTabSheet.Caption`（没有 `Tabs` 集合）。

### TTyTabSheet

| 成员 | 说明 |
|---|---|
| `Caption`（published） | 该页的**标签文字**；改动时通知宿主重排标签头（经重写 `TextChanged`）；**不**画在页面体上。**它就是 `TControl.Caption`**：`Caption` 与 `Text` 是同一个字符串，早先的 `FCaption` 影子字段已去掉 |
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
- **右到左镜像**：`BiDiMode := bdRightToLeft` 时整条标签带镜像——第 0 页的页签在**最右**，往左排；关闭 × 挪到每个页签头的**左**边；两个溢出箭头对调两端并且各自转向（"上一批"那个永远在阅读起点，也就是镜像时的右端）；向后滚动时标签带往**右**滑；`←/→` 跟着眼睛走（左键=下一页）。`Home/End` 与 `Ctrl+Tab` 是**逻辑**首尾/循环，不翻。
  **页面体不镜像**：`TabPosition` 目前没有左/右边标签这一形态，所以页面体的左右边界没有可镜像的东西，`AdjustClientRect` 照旧只扣顶部条带。**页内子控件也不镜像**（`Align`/`Anchors` 排布跟随 LCL，见 [panel.md](panel.md)）；但 `BiDiMode` 会按 LCL 的 `ParentBiDiMode` 传播给页里的控件，所以页上的复选框、标签等各自会翻自己的指示器与文字。
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
