# TyControls 事件与属性总览（API parity）

> English: [events.en.md](events.en.md)

本页汇总 TyControls 全库控件的**事件契约**：每个控件都暴露的**基线事件集**（Tier A / Tier B）、各控件的**专有事件**，以及为遵守"主题拥有视觉"原则而**刻意不暴露**的与主题冲突的属性。

> 本批次（API events+properties parity）的目标是让 TyControls 控件在 Lazarus 对象查看器（Object Inspector）中的事件/属性面板尽量与原生 LCL 控件**对齐**，便于设计期挂接事件、用 DFM/LFM 流式保存。基线事件全部由两个基类统一 published，专有事件由各控件单独 published。

---

## 1. 基线事件集（所有控件都暴露）

TyControls 的全部控件继承自两个基类之一（`tyControls.Base`）：

| 基类 | LCL 父类 | 用途 | 暴露层级 |
|------|----------|------|----------|
| `TTyGraphicControl` | `TGraphicControl` | **非窗口化**轻量控件（无句柄、不可获得键盘焦点） | 仅 **Tier A** |
| `TTyCustomControl` | `TCustomControl` | **窗口化**可聚焦控件（有句柄、可 Tab 导航、接收键盘） | **Tier A + Tier B** |

继承自 `TTyGraphicControl` 的是纯展示 / 无需焦点的那一批（`TTyLabel` / `TTyProgressBar` / `TTyDivider` / `TTyImage` / `TTyShape` / `TTyBadge` / `TTyTag` / `TTyGauge` / `TTyMeter` / `TTyChart` / `TTySparkline` / `TTyArrow` / `TTyBevel` 等，共约 28 个），**因此只有 Tier A 事件**；**其余所有控件**（Button / Edit / Memo / SpinEdit / ComboBox / CheckBox / RadioButton / ScrollBar / TrackBar / TabControl / ToggleSwitch / ListBox / Panel / GroupBox / ContentPanel / 以及 `TTyForm` 标题栏的 TitleBar/CaptionButton 等）继承自 `TTyCustomControl`，**Tier A + Tier B 全部具备**。

### Tier A —— 鼠标 / 通用事件与属性（两个基类都有，**全控件可用**）

| 成员 | 类别 | 说明 |
|------|------|------|
| `OnClick` | 事件 | 单击 |
| `OnDblClick` | 事件 | 双击 |
| `OnMouseDown` | 事件 | 鼠标按下 |
| `OnMouseUp` | 事件 | 鼠标松开 |
| `OnMouseMove` | 事件 | 鼠标移动 |
| `OnMouseEnter` | 事件 | 指针进入控件 |
| `OnMouseLeave` | 事件 | 指针离开控件 |
| `OnMouseWheel` | 事件 | 滚轮（带 delta） |
| `OnMouseWheelUp` | 事件 | 滚轮上滚 |
| `OnMouseWheelDown` | 事件 | 滚轮下滚 |
| `OnMouseWheelHorz` | 事件 | 横向滚轮（带 delta）；倾斜轮 / 触控板横向手势只从这里到达 |
| `OnMouseWheelLeft` | 事件 | 横向滚轮左滚 |
| `OnMouseWheelRight` | 事件 | 横向滚轮右滚 |
| `OnContextPopup` | 事件 | 右键 / 上下文菜单触发 |
| `OnResize` | 事件 | 尺寸变化 |
| `OnChangeBounds` | 事件 | 位置或尺寸（BoundsRect）变化 |
| `OnShowHint` | 事件 | 提示即将显示时；用于按指针所在位置给出不同的 Hint 文本 |
| `OnPaint` | 事件 | 控件**画完自己之后**触发，拿到的是控件自己的 `Canvas`；用来叠一个角标 / 一层覆盖 / 一个调试矩形，不必再派生子类 |
| `OnDragOver` | 事件 | 拖动经过本控件（决定是否接受放置） |
| `OnDragDrop` | 事件 | 在本控件上放下 |
| `OnStartDrag` | 事件 | 本控件作为拖动源开始拖动 |
| `OnEndDrag` | 事件 | 拖动结束 |
| `Visible` | 属性 | 是否可见（`default True`；此前只能从代码设，对象查看器与 `.lfm` 里都没有） |
| `AutoSize` | 属性 | 是否按控件自己的首选尺寸（`CalculatePreferredSize`）自动调整大小；`default False`，未实现首选尺寸的控件保持原有 bounds |
| `DragMode` | 属性 | `dmManual` / `dmAutomatic`；置 `dmAutomatic` 即可让控件成为拖动源 |
| `DragKind` | 属性 | 拖动种类（`dkDrag` / `dkDock`） |
| `DragCursor` | 属性 | 拖动过程中的指针形状 |
| `PopupMenu` | 属性 | 关联的右键菜单 |
| `Constraints` | 属性 | 尺寸约束（min/max width/height） |
| `BorderSpacing` | 属性 | 自动布局留白 |
| `Cursor` | 属性 | 鼠标指针形状（文本框默认 `crIBeam` 等） |
| `ParentShowHint` | 属性 | 是否继承父控件的 `ShowHint` |
| `Action` | 属性 | 关联的 `TAction` |

> 这些成员只是把 LCL 父类**已有**的 published 成员重新 published（声明在基类的 `published` 段）；事件分发链路全部走 `inherited`，与原生行为一致——基类**没有**改写任何分发逻辑，仅打开了对象查看器中的可见性。
>
> **拖放为什么"白捡"：** `DragMode` / `OnDragOver` / `OnDragDrop` 等全部由 `TControl` 声明、由 LCL 完成分发，拖放的判定发生在绘制层**之上**，所以自绘控件与原生控件的拖放行为完全一致。它们此前只是没被重新 published——`Ctl.DragMode := dmAutomatic` 从代码里一直编得过，缺的是对象查看器与流式化的那一份。`Visible` 同理。

### Tier B —— 键盘 / 焦点事件（仅 `TTyCustomControl`，即可聚焦控件）

| 事件 | 说明 |
|------|------|
| `OnKeyDown` | 按键按下（虚拟键） |
| `OnKeyUp` | 按键松开 |
| `OnKeyPress` | 字符按键（ANSI） |
| `OnUTF8KeyPress` | UTF-8 字符按键（多字节安全） |
| `OnEnter` | 获得焦点 |
| `OnExit` | 失去焦点 |
| `OnEditingDone` | 编辑完成（失焦或回车提交时） |

> Tier B 事件由 `TWinControl` 声明，因此只有窗口化的 `TTyCustomControl` 子类暴露。`TTyLabel` / `TTyDivider` 等 `TTyGraphicControl` 子类**不**暴露键盘 / 焦点事件——它们不可获得焦点。

> **仅窗口化基类的两个容器属性：** `BorderWidth`（把子控件区域整体内缩若干像素）与 `ChildSizing`（LCL 的每容器子控件布局引擎：`Layout` / `ControlsPerLine` / 各方向间距 / `EnlargeHorizontal` 等）也只在 `TTyCustomControl` 上 published——二者都是 `TWinControl` 成员，对不承载子控件的图形控件没有意义。两者的分发同样全在 `TWinControl` 的对齐流程里，基类只是打开了可见性。

---

## 2. 各控件专有事件

下表列出在基线之外，各控件**单独 published** 的专有事件。

| 控件 | 事件 | 类型 | 触发时机 |
|------|------|------|----------|
| `TTyEdit` | `OnChange` | `TNotifyEvent` | 文本因键盘编辑 / 剪贴板 / 撤销 / 重做变化时；`Text :=` 赋值**不**触发 |
| `TTyEdit` | `OnEditingDone` | （Tier B） | 失焦或回车提交时（基线 Tier B） |
| `TTyMemo` | `OnChange` | `TNotifyEvent` | 文本模型（插入 / 拆分 / 退格 / 删除 / 合并）变化后；纯光标移动不触发 |
| `TTyMemo` | `OnSelectionChange` | `TNotifyEvent` | 光标位置**或**选区范围变化时（方向键 / 点击 / Shift 选区 / 程序化设置光标）；自带去抖（caret 与 anchor 都未变则不触发） |
| `TTySpinEdit` | `OnChange` | `TNotifyEvent` | 编辑框**文字**变化时——每次键入 / 删除 / 步进 / 夹紧 / `Value :=`（等价 LCL `TCustomEdit.Change`）；文字没真的变则不触发 |
| `TTySpinEdit` | `OnValueChange` | `TNotifyEvent` | 提交后的 `Value` 真的移动时；键入过程中**不**触发 |
| `TTyComboBox` | `OnChange` | `TNotifyEvent` | `ItemIndex` / 文本变化时（含程序化） |
| `TTyComboBox` | `OnSelect` | `TNotifyEvent` | **用户**驱动的选择（下拉选取 / 键盘导航）后触发；程序化设置 `ItemIndex` **不**触发 |
| `TTyComboBox` | `OnDropDown` | `TNotifyEvent` | 下拉列表打开时 |
| `TTyComboBox` | `OnCloseUp` | `TNotifyEvent` | 下拉列表收起时 |
| `TTyCheckBox` | `OnChange` | `TNotifyEvent` | `Checked` 实际改变时（设为当前值不触发） |
| `TTyRadioButton` | `OnChange` | `TNotifyEvent` | `Checked` 实际改变时；选中某个单选钮时，被**取消选中的同组兄弟**各自经过自己的 `SetChecked` 也会**各自触发**其 `OnChange` |
| `TTyScrollBar` | `OnScroll` | `TScrollEvent` | 键盘 / 轨道点击 / 按钮触发的滚动；签名为 `(Sender; ScrollCode: TScrollCode; var ScrollPos: Integer)`，可在 handler 中改写 `ScrollPos` 覆盖目标位置 |
| `TTyTrackBar` | `OnChange` | `TNotifyEvent` | `Position` 变化时（含滚轮步进） |
| `TTyCustomTabStrip`(`TTyTabSet` / `TTyPageControl` 继承) | `OnChanging` | `TTyTabChangingEvent` | 切换页签**之前**；签名 `(Sender; ANewIndex: Integer; var AllowChange: Boolean)`，把 `AllowChange := False` 即可**否决**切换 |
| `TTyCustomTabStrip`(同上) | `OnReorder` | `TTyTabReorderEvent` | 拖拽重排松手后触发一次；签名 `(Sender; AFromIndex, AToIndex: Integer)` |
| `TTyProgressBar` | `OnChange` | `TNotifyEvent` | `Position` / `Min` / `Max` 实际变化后 |

> **`TTyForm` 使用标准 `TForm` 生命周期事件：** 自绘窗框窗口现在通过继承 `TTyForm = class(TForm)` 获得（旧的非可视控制器 `TTyFormChrome` 已**移除**）。`TTyForm` *就是*一个 `TForm`，因此 `OnCloseQuery` / `OnClose` / `OnShow` / `OnActivate` / `WindowState` 等都是标准的、已 published 的窗体事件，直接在对象查看器里挂接即可。旧 `TTyFormChrome` 的自定义 `OnMinimize` / `OnMaximize` / `OnRestore` 事件**已废弃**——标题栏最小化按钮设 `WindowState := wsMinimized`、最大化由引擎 `ToggleMaximize` 处理、关闭走标准 `Close`（`OnCloseQuery` → `OnClose`）。详见 [controls/ttyform.md](controls/ttyform.md)。

> **滚轮步进：** `TTyScrollBar` 与 `TTyTrackBar` 现支持鼠标滚轮步进。约定与原生 LCL 一致：ScrollBar 滚轮上滚减小 `Position`（向上滚动内容）；TrackBar 滚轮上滚**增大** `Position`（与滑块方向一致，二者相反）。ScrollBar 滚轮直接改写 `Position`（触发 `OnChange`），**不**经过 `DoScroll`，因此**不**触发 `OnScroll`。

> **TitleBar 鼠标事件已释放：** `TTyTitleBar`（`TTyForm` 的标题栏子组件）原先把鼠标事件用于窗口拖动 / 双击最大化。现在改为**方法覆写**（`MouseDown/Move/Up`、`DblClick` 内先调 `inherited`、再委托给 `TTyForm` 拥有的 `TTyChromeEngine`），从而把**published 的 `OnMouseDown/OnMouseMove/OnMouseUp/OnDblClick` 事件槽位释放给用户**——挂接它们不会破坏窗框的拖动 / 最大化逻辑。

---

## 3. 刻意未暴露的属性（与主题冲突）

TyControls 的硬性原则是**视觉由主题（.tycss）拥有**：颜色、字体、边框、阴影等一律来自主题令牌，**不**在控件代码里写死，也**不**通过原生属性让用户在对象查看器里随意覆盖。因此下列原生 `TControl` / `TWinControl` 属性**刻意不 published**：

| 未暴露的属性 | 原因 |
|--------------|------|
| `Color` / `ParentColor` | 背景色由主题 `background` 令牌决定，不接受控件级覆盖 |
| `Font`（仅暴露用于 PPI/字号传递）/ `ParentFont` | 字体族与字号优先由主题控制；`Font` 虽 published，但其作用是传 PPI，主题令牌覆盖字体族/大小 |
| `Brush` | 填充由 Painter + 主题决定 |
| `Bevel*`（BevelInner/Outer/Kind/Width/Edges） | 立体边框是原生外观，与主题边框语义冲突 |
| `BorderStyle` | 边框样式由主题 `border-*` 令牌决定 |
| `DoubleBuffered` | **强制开启**（BGRABitmap 离屏合成），不允许关闭——关闭会导致闪烁与绘制撕裂 |

> **别把 `BorderWidth` 当边框宽度。** `TWinControl.BorderWidth` 已在 `TTyCustomControl` 上 published，但它是**布局**属性（子控件区域的内缩量），与画出来的那条边无关；边框的粗细仍然只由主题的 `border-width` 令牌决定，控件不暴露任何覆盖它的原生属性。

> **`OnPaint` 不在此列——它是"叠加"而不是"接管"。** 控件的外观仍然只由 Painter + 主题决定；`OnPaint` 在控件**画完并合成到画布之后**才触发，宿主程序只能在成品之上再画东西，改不了主题画出来的那一层。所以它不违反"视觉由主题拥有"：它加的是**应用自己的**标记（角标、选中框、调试矩形），不是控件的皮肤。
>
> 为什么钩子不在 `Paint` 里：全库的绘制都是"先画进 BGRA 图层、再由 `TTyPainter.EndPaint` 合成到画布"，**合成会覆盖此前直接画到画布上的一切**。因此钩子挂在 `Paint` 的上一层——图形控件在 `TTyGraphicControl.WndProc`（`LM_PAINT` 之后），窗口化控件在 `TTyCustomControl.PaintWindow`（`inherited` 之后）——这两处是"合成一定已经结束"的**唯一**汇合点，且无需逐控件接线。未挂 handler 时零开销；设计期同 LCL 一样照常触发。
>
> 与 `TTyPaintPanel.OnPaintSurface` / `TTyPreviewBox.OnPaintPreview` 的区别：那两个在**合成之前**触发、拿到的是 `TTyPainter`（可以用主题令牌参与控件自己的绘制）；`OnPaint` 在**合成之后**触发、拿到的是 LCL `Canvas`（只能覆盖在上面）。

> 这一原则的完整说明见仓库的「Theme-customizability principle」：凡视觉值必须由主题令牌驱动，永不在控件代码中写死。

---

## 4. 事件行为约定（重要）

### 4.1 禁用控件不触发输入事件（Enabled 守卫）

所有控件在 `Enabled = False` 时**不响应输入**：键盘事件不被消费、鼠标按下/滚轮被忽略、`DoMouseWheel` 返回 `False`。因此 `Enabled = False` 的控件**不会触发** `OnClick` / `OnKey*` / `OnMouseWheel` / 各自的 `OnChange` 等由输入驱动的事件。程序化属性赋值（如 `Checked :=`、`Position :=`）是否触发事件由各控件文档单独说明，与 `Enabled` 无关。

### 4.2 内嵌滚动条是静态的（不暴露事件）

`TTyMemo` / `TTyListBox` / `TTyComboBox` 下拉等内部**内嵌**的 `TTyScrollBar` 是控件私有的子部件，不参与对象查看器、不暴露其 `OnScroll`/`OnChange`，并且其 thumb **不做缓动动画**（直接跟随，避免内嵌滚动产生视觉延迟）。用户应监听**宿主控件**自身的事件（如 Memo 的 `OnChange`/`OnSelectionChange`），而非内嵌滚动条。

### 4.3 程序化赋值与事件

多数控件遵循"程序化赋值不触发回调"的约定中最易踩坑的一项：`TTyEdit.Text :=` / `TTyMemo.Text :=` 赋值**不**触发 `OnChange`（仅更新字段、记撤销步并重绘）。`Checked` / `Position` / `Value` 等则在**值实际改变**时触发对应 `OnChange`（无论程序化或交互），具体以各控件文档为准。

---

## 5. 相关文档

- 各控件的事件 / 属性细节见 `docs/controls/<控件>.md` 的「事件」与「属性表」节。
- 主题令牌与子部件 typeKey 见 [tycss-reference.md](tycss-reference.md)。
- 双向文本与右到左布局的现状见 [rtl.md](rtl.md)。
