# 更新日志

本文件记录 **ty-controls** 的所有重要变更。项目采用 3 段式语义化版本号(`主版本.次版本.修订号`)。
所有控件均由 BGRABitmap 全自绘、由轻量 `.tycss` 文本主题统一着色 —— 在 Windows、Linux、macOS 上
像素级一致。

> English: [CHANGELOG.en.md](CHANGELOG.en.md).

## [3.0.0-Beta] — 2026-08-14

3.0 是第一个正式版本线。本版包含大量新控件与 LCL 兼容性对齐,其中部分变更不向后兼容,升级前请通读「变更」一节。

### 新增

- 数据网格 `TTyStringGrid` / `TTyDrawGrid`:冻结行列、百万行虚拟化、多列排序、条件筛选与内嵌筛选行、多级分组与小计、单元格合并、汇总带、16 种内置编辑器与自定义编辑器接口、逐格样式与边框、树形列、行列拖动重排、版式持久化、CSV 导入导出、与 Excel 互粘、每格 `Objects[]`、`Rows` / `Cols` 的 `TStrings` 视图、撤销 / 重做。
- 14 个现代 UI 控件:`TTyCard`、`TTyTag`、`TTyBadge`、`TTyAlert`、`TTyNotification`、`TTyPopover`、`TTySegmented`、`TTyPagination`、`TTySteps`、`TTyBreadcrumb`、`TTyTransfer`、`TTyTreeSelect`、`TTyCascader`、`TTyEmpty`。
- 新控件 `TTyFloatSpinEdit`(小数微调框)、`TTyLucideImageList`(内置 Lucide 图标的图像列表)、`TTyIconBrowserDialog`(带搜索的图标浏览器)。
- `TTyVirtualImageList` 改为继承 `TCustomImageList`,可直接赋给任何 LCL / 第三方控件。
- 图标可按名字引用:`TTyImage`、表头列、标签页、树节点、`TTyComboBoxEx`、列表视图项新增 `ImageName` 系列属性,重排图像列表不影响取图。
- 所有控件新增 `OnPaint`,在控件绘制完成后追加自绘。
- `TTyForm.StyleOverride`:运行时用一段 CSS 覆盖单个窗体的外观。
- `TTyTreeView` 新增 `Items` 节点集合,设计期可编辑;虚拟模式不受影响。
- 标签条:`TabPosition` 支持上下左右、页签图标、`MultiLine` 多行。
- 下拉框:owner-draw(`csOwnerDrawFixed` 等)、`csSimple` 常驻列表、逐项行高、`ItemHeight` / `TextHint` / `ReadOnly`、可写的 `DroppedDown`、`SelStart` / `SelText`、`OnGetItems` 懒加载;列表框横向滚动(`ScrollWidth`)。
- `TTyToolBar`:`TTyToolButton` 六种按钮样式、`Grouped` 相邻分组、`HotImages` / `DisabledImages`、`ShowCaptions`、`ButtonWidth` / `DropDownWidth` / `List`、`OnPaintButton`、指定换行位置。
- 日期时间选择器:空值支持(`NullInputAllowed` / `NullDate` / `TextForNullDate`)、两位年份按 `CenturyFrom` 展开、`LeadingZeros`、`Esc` 撤销本次编辑、A / P 键设上下午、空格切换勾选框。
- `TTyUpDown`:`Associate` 双向绑定、`OnChanging` / `OnChangingEx` 可否决步进、带方向的 `OnArrowClick`、`MinRepeatInterval`。
- 文本控件:`TTyMemo.Alignment` / `CharCase`、`TTyEdit.EchoMode`、`Modified`、多播 `OnChange`、公开的 `CaretLine` / `CaretCol` / `SetCaret`、无障碍角色声明。
- 形状:`TTyShape` 补齐 LCL 的 15 种形状并支持自定义多边形(`OnShapePoints`)、新增 `OnShapeClick`;`TTyStarShape.PointDown`;`TTyArrow` 三角形箭头。
- `TTyImage`:共享图标集(`Images` / `ImageIndex`)、`StretchInEnabled` / `StretchOutEnabled`、`KeepOriginXWhenClipped` / `KeepOriginYWhenClipped`、`AntialiasingMode`、`OnPictureChanged`。
- `TTyImageCollection.Images` 进入 `.lfm`,设计期可编辑,同名多项构成多分辨率母版。
- 容器停靠:`TTyPanel` / `TTyGroupBox` / `TTyPageControl` / `TTyControlBar` 支持 `DockSite` 与整套停靠事件。
- 滑块刻度(`TickMarks` / `TickStyle` / `Reversed`);进度条 `Step` / `StepIt` / `StepBy`、条上文字、四方向。
- `TTyScrollBar.LiveTracking`;`TTySplitter.AutoSnap`;`TTyPanel.VerticalAlignment`;`TTyDivider.LeftIndent`。
- 状态栏 `AutoHint` 与自绘格(`OnDrawPanel`);菜单栏 `RightJustify`;右键菜单 OwnerDraw 协议、`TrackButton`、`SubMenuImages`、`GlyphShowMode`。
- 网格 `Options` 集合:一处开关约 21 个 LCL 行为旗标。
- 日历、日期框的月份与星期名跟随应用语言。
- 分组控件:`Buttons[]` / `CheckEnabled[]` / `OnItemClick`,方向键可在选项间移动。
- 列表、下拉、勾选、取色控件批量补齐 LCL 成员:三态 `State[]`、`ItemEnabled[]`、可写的 `Colors[]`、`OnSelectionChange`、`ExtendedSelect`、`TTyComboBoxEx.ItemsEx` 设计期可编辑等。
- shell 控件:`Root` / `Path` / `ObjectTypes` / `FileSortType` / `OnAddItem` 等成员补齐;树、列表、过滤下拉可互相关联。
- 值列表:`KeyOptions`、可写的 `Keys[]`。
- 主题:新增语义色 `--success` / `--warning`,角标令牌 `--badge-inset` / `--badge-min-size`。
- 新示例 antdesign:仿 Ant Design Pro 后台,运行时换肤。

### 变更

- `TTyForm` 的可视控件改放在内容容器 `Surface`(`TTyFormSurface`)上,现有窗体需把控件移入 `Surface`;非可视组件与 `TTyDialog` 不受影响。详见 [docs/controls/ttyform.md](docs/controls/ttyform.md)。
- `TTyMaskEdit` 掩码语言改为 LCL / Delphi 语法(`0` / `9` / `L` / `A` / `C` / `H` / `B`、大小写区、`;` 分段);旧语法的 `#` 掩码会抛异常。空掩码框改为显示占位符(`SpaceChar`),`Text` 返回显示串,取值用新增的 `MaskedValue`;失焦自动校验,未填完抛 `ETyMaskError`(`ValidateEdit` 可主动调用);`Text` 赋值与粘贴一样走掩码。
- `TTyMemo.SelStart` / `SelLength` 按完整换行符计数,与 `Text` 的偏移一致。
- `TTyEdit` / `TTyMemo` 的 `ClearSelection` 改为删除选中文本(LCL 语义),原「仅收起选区」改名 `CollapseSelection`。
- `TTyListBox.Items` 类型由 `TStringList` 改为 `TStrings`。
- 所有 `Images` 属性统一为 `TCustomImageList`,同时接受本库矢量列表与普通 LCL 图像列表。
- `TTyVirtualImageList` / `TTyGlyphImageList` 的 `Draw` 改为 LCL 参数顺序 `(Canvas, X, Y, Index, Enabled)`,带尺寸的版本改名 `DrawIndex`;旧的四整数调用会编译失败。
- 数据网格:`VisibleRowCount` 改为视口可容纳的行数(过滤后行数用 `FilteredRowCount`);`ClearRows` / `ClearCols` 改为删除行列(清内容用 `ClearRowContents` / `ClearColContents`);`SaveToStream` / `LoadFromStream` 改存完整版式(CSV 用 `SaveToCSVStream` / `LoadFromCSVStream`);`Selection` 可写;新增的 `Objects` / `Cols` / `Rows` 可能与派生类的同名成员冲突(编译期报重复标识符)。
- `TTyValueListEditor`:`Values` 改为按键名取用(按行号用 `ValueFromIndex`),`ValueOf` 取消;`VisibleRowCount` 改为视口行数(原含义改名 `DisplayRowCount`);`InsertRow` 改为 LCL 签名;`RowCount` 可写。
- `TTyTreeView`:`GetNodeAt(X, Y)` 改为 LCL 含义(原方法改名 `GetNodeAtOffset`);`Selected` 改为返回当前节点(按下标改用 `NodeSelected[]`);`OnDragOver` 等 LCL 拖放事件归还给应用(树内拖动否决改用 `OnNodeDragOver`)。
- `TTyListView` 的 `OnChange` / `OnChanging` / `OnSelectItem` 改为 LCL 签名;重复选中已选中的行不再触发 `OnSelectItem`。
- `TTyScrollBox.ScrollBy` 与 `TTyMemo.ScrollBy` 改为滚动视图 / 文本。
- `TTyImage`:`Proportional` 不再放大图片;`Center` 与 `Transparent` 默认值改为 `False`(与 `TImage` 一致),依赖旧默认值的窗体需显式设置。
- `TTySpinEdit`:`MaxValue` 默认改为 0(不限制);`MinValue = MaxValue` 表示不限;`OnChange` 改为每次键入触发,提交值变化用新增的 `OnValueChange`。
- `TTyDateTimePicker`:`DateTime` 程序赋值不再触发 `OnChange`(旧行为用 `dtpoDoChangeOnSetDateTime`);格式串不再自动翻倍单字母字段;点相邻月灰格会选中并翻月(旧行为用 `dsNoMonthChange`)。
- `TTyCalendar`:`FirstDayOfWeek` 默认跟随系统;`Date` 越界赋值抛异常(需要钳制用 `SetDateClamped`)。
- `TTyCheckGroup.Checked[]` 与 `TTyRadioGroup.ItemIndex` 越界赋值抛异常。
- `TTyCheckGroup` / `TTyRadioGroup` 多列排布默认改为行优先(新属性 `ColumnLayout`,LCL 默认值);单列分组不受影响。
- `TTyToolBar.Indent` 只作用于横向,纵向内距改用新增的 `ContentPadY`。
- shell 控件:`TTyShellListView.Refresh` 改名 `UpdateView`;`TTyShellTreeView.SelectPath` 改为返回 `Boolean` 的函数,`Directory` 赋非法路径抛异常;目录展开默认每次重新读盘(`ecmKeepChildren` 恢复旧行为);`OnGetText` 等 7 个事件槽归还给应用。
- `TTyScrollPanel.AutoScroll` 改名 `AutoPan`。
- `TTyPanel` / `TTyTabSheet` / `TTyDivider` 的 `Caption` 与 `Text` 合一。
- `TTyCheckComboBox`:`Objects[]` 归应用所有;项状态的 `Checked` 改为 `State: TCheckBoxState` 并新增 `Enabled`。
- `TTyColorButton`:新增 LCL 同名同类型的 `ButtonColor` 与 `OnColorChanged`;`OnColorChange` 改为任何改色都触发;`Caption` 解析 `&` 助记符。
- `TTyEdit.PasswordChar := #0` 表示关闭掩码显示。
- `TTyGauge` 不再发布 `Caption`。
- `TTyTabStrip.TabHeight`:负数表示自动高度,0 仍为隐藏标签条。
- `TTyHeaderControl`:三个 section 事件的首参改为 `TTyHeaderControl` 类型;`OnSectionResize` 改为松手时触发一次,拖动过程用新增的 `OnSectionTrack`。
- `TTyUpDown`:`OnArrowClick` 改到值变化之后触发;`Wrap` 改为进位而不是丢弃溢出。
- `TTyTrackBar`:`Frequency` 默认改为 1;`Orientation` 会交换宽高。
- `TTyPaintPanel` 设计期默认尺寸改为 105×105。
- `TTyGlyphLayout` 新增 `glRight` / `glBottom`(追加在末尾);`HasGlyphSource` 改名 `CanShowGlyph` 并转为 public。
- 主题令牌:微调按钮的箭头覆盖令牌由 `--glyph-arrow-up/down` 改名 `--glyph-triangle-up/down`。

### 修复

- 可编辑下拉框不再画双层边框。
- 微调按钮、滚动条端头、标签条滚动键改画实心三角,图标内距过大一并修正。
- 菜单按钮与日期框的下拉标记改与下拉框一致。
- 滑块条:轨道改为居中细槽(新主题键 `TyTrackGroove`),刻度不再压在轨道上。
- 编辑框族尾部小部件与边框的间距统一。
- `window-shadow: false`:阴影真正关闭;失焦不再露出系统经典标题栏;边框可正常拖拽缩放;固定尺寸窗口也有阴影了。
- 250% 缩放下标题栏不再双倍高;最小化 / 最大化 / 关闭按钮描边不再加粗。
- 跨屏 DPI(PerMonitorV2)往返拖动后布局可精确还原。
- aero 主题补上真正的暗色模式;classic 固定为无暗色;15 个内置主题的 danger 按钮全部生效;aero 下窗口化控件四角不再出现黑块。
- 渐变容器上的窗口化控件背景按所在位置取渐变切片,不再是一块突兀的纯色。
- 单选组:点击即获得焦点;行距不再重叠;整组只占一个 Tab 停靠点。
- CoolBar / ToolBarEx / ControlBar:子控件不再擦掉容器边框;CoolBar 抓柄拖动语义对齐原生并支持换序。
- 滚动框:拖动滑块不再闪烁;视口内对齐的子控件跟随滚动。
- 只读网格堵住粘贴、剪切、填充柄三个绕过口;逐格 / 逐列锁定对填充生效;新增 Ctrl+X。
- 网格:粘贴超界自动扩行扩列;CSV 含换行的字段不再串行;排序三角正常显示;分组不再丢排序列;合并区跟随增删行;`hoAutoResize` 与列头图标生效;空值排序位置不随方向翻转。
- 一批「属性面板可设但无效」的成员修复:`TTySplitter.ResizeStyle`、工具条 `ShowCaptions`、树节点 `Ghosted`、右键菜单 `OnPopup` / `Close` / 动态菜单项、`TTyColorButton.Caption`、`TTyScrollBar.LargeChange`、`TTyColorBox.Style`、菜单项 `ShowAlwaysCheckable`、`TTyPanel.BorderWidth`、`ActivePage` 等转为 published。
- 掩码框:粘贴与 `InjectBackspace` / `InjectDelete` 不再绕过掩码;Delete 不再删掉掩码分隔符。
- 菜单:禁用的顶级菜单画灰且不可点;无子项顶级项触发 `OnClick`;菜单项 `Hint` 发布到 `Application.Hint`;`AutoCheck` 项未勾选时画空框;禁用项图标画灰。
- `TTyShape` / `TTyStarShape` 按实际形状判定点击,新增 `PtInShape`。
- 勾选框的本地化真值词实时生效;工具条按钮文字量宽与绘制同源,英文不再截断;Ribbon 的 File 页签可翻译;43 个示例约 740 条文案可翻译。
- 42 个示例补上应用清单(common-controls v6 与 DPI 声明)。
- 速度按钮 `Down := True` 会弹起同组按钮;单选列表框 `ClearSelection` 生效;取色下拉写入调色板外颜色不再追加行;文件树 `ShowHidden` 立即生效;F2 重命名后列表重新读盘;`TTyShellListView.OnCompare` 会被调用;文件大小列单位可翻译。
- 列头:最后一段宽度如实报告(新增 `EffectiveSectionWidth`);段宽约束在四条改宽路径上一致生效;列头图标真正画出。
- 拖动重排标签页不再让页头页体错位;页移到另一个 `TTyPageControl` 后旧容器不再持有它。
- File → New 的 TyControls Dialog 模板不再生成两条标题栏,也不再报 `EClassNotFound`。
- 无边框可缩放窗口右 / 下边缘的细白边消除。
- macOS:中文渲染不再锯齿、不再裁掉下半部分;输入法候选框跟随光标(Edit / Memo)。
- GTK2:容器面板不再显示为黑色;模态对话框可拖动。
- `TTyMemo`:行末退格与末行行首退格后的光标位置正确。

### 性能

- 网格单元格文本跨帧缓存,大表滚动的绘制耗时降至约原来的 1/20。
- 跨屏 DPI 同步耗时减少 42%。

## [2.2.0] — 2026-07-04

一个大型功能版本。主角是**对话框子系统**:为 **TTyForm** 补齐完整的窗口镶边(caption 按钮),
新增 **11 个全自绘对话框组件**及配套全局函数、IDE 集成与独立示例;同时新增**三个小控件**
(三态 CheckBox、可编辑 ComboBox、TTyTabSet),为全部控件补齐 API 文档,并修复大量在真机上
(尤其 Windows 10)才暴露的显示问题。

### 新增 — 对话框

- **TTyForm 窗口镶边** —— 标题栏的最小化 / 最大化 / 关闭按钮现由 `BorderIcons` 统一控制
  (`BorderIcons:=[]` 去掉全部按钮),窗口可否缩放由 `Resizable` 决定;旧的 `ShowMinimize` /
  `ShowMaximize` 属性已移除。
- **11 个全自绘对话框组件** —— 与 LCL 对齐,既可作为组件拖放,也提供全局函数直接调用:
  - **消息框**(`TyShowMessage` / `TyMessageDlg`)—— 完整的按钮组合、结果与类型图标。
  - **输入 / 密码 / 多行文本**(`TyInputQuery` / `TyPasswordQuery` / `TyTextQuery`)。
  - **列表取值**、**文件夹选择**(带新建文件夹、可展开目录树)。
  - **取色器**(HSV + 色相条 + RGB / CMYK / Alpha / Hex)、**字体选择器**(字族 / 字号 / 样式 / 颜色 / 预览)。
  - **查找 / 替换**(无模态,`OnFind` / `OnReplace`)、**进度对话框**(可取消)。
  - 全部对话框都支持 `OnShow` / `OnClose` / `OnCanClose` 事件。
- **IDE 集成** —— 新增 **TyControls Dialogs** 组件面板分组、11 个对话框的调色板图标、File > New 的
  **TyControls Dialog** 模板;设计器中双击任一对话框组件即可预览。
- **示例** —— 新增独立的 **dialogs 示例**演示全部 11 个对话框;主 demo 也加入了对话框网格。

### 新增 — 三个小控件

- **三态 CheckBox** —— `State` / `AllowGrayed`,带灰显(不确定态)。
- **可编辑 ComboBox** —— `csDropDown` 自由输入 + 前缀自动补全。
- **TTyTabSet** —— 纯标签条控件(非页容器)。

### 新增 — 文档

- 为**全部控件补齐逐控件 API 文档**(属性 / 事件 / 状态 / 主题变体 / 代码示例),覆盖此前缺文档的
  TreeView、Calendar、DateTimePicker、Splitter、StatusBar、ToolBar、TabSet、菜单、NativeStyler 等,
  并新增控件文档索引 `docs/controls/`。

### 新增 — 示例整体翻新

- 所有单控件示例统一采用 **TTyForm + TTyTitleBar** 自绘窗框,并更充分地演示各控件特性。
- 新增 7 个专属示例:tabset、calendar、datetimepicker、splitter、statusbar、toolbar、menu;
  `tabcontrol` 示例改用 TTyPageControl + TTyTabSheet。

### 修复

- **Windows 10 窗口发白 / 透明** —— 窗口及容器(对话框、分组框、页签、禁用控件)在 Windows 10 上
  不再透出玻璃或白色,窗口失去焦点时也不再整片变白。
- **禁用控件发虚** —— 禁用状态的控件文字不再发虚、背景不再透白。
- **可缩放窗口侧边竖条** —— 可缩放窗口左右两侧不再出现主题色 / 白色竖条。
- **可编辑 ComboBox 输入** —— 输入时不再丢失焦点或字符,自动补全弹层不再闪烁,点选补全项会填入正确的值。
- **标签滚动箭头** —— 标签过多时,左右滚动箭头不再遮住首 / 尾标签。
- **日期选择器下拉崩溃** —— 使用全局默认主题时,打开日历下拉不再崩溃。
- **进度对话框闪烁** —— 进度对话框的文字与进度条不再闪烁。
- **双击最大化崩溃** —— 多显示器 / 特殊配置下双击标题栏最大化不再崩溃。
- **中文界面** —— 中文系统下消息框按钮显示"确定 / 取消"等,dialogs 与 demo 示例界面跟随系统语言显示中文。
- **示例修复** —— 修复若干示例的启动崩溃与显示问题(radiobutton 启动崩溃、GroupBox 标题遮挡、
  splitter 拖动方向等)。

## [2.1.1] — 2026-06-30

一个修复版本,集中处理 green 图片主题的真机观感,以及 IDE 设计期的若干小问题。

### 修复

- **green 主题** —— 所有容器(toolbar、titlebar、statusbar、panel、groupbox、tab、分隔符、滚动条)
  改为 **100% 透明**,照片背景干净透出,不再有磨砂或纯色填充。
- **TTyForm 玻璃/照片背景** —— 应用主题时即时重建:用 Custom… 选图片主题后背景图**立刻出现**
  (不再需要先最小化/最大化触发);工具栏、状态栏也会采样照片透出。
- **最小化** —— 主窗口最小化到任务栏(而不是缩到屏幕角落的小方块);最小化弹出子窗口不再连累整个应用。
- **TTyToolBar 分隔符** —— 实心主题下与工具栏背景无缝(去掉怪异的填充色块),图片主题下透出照片。
- **IDE 设计器**
  - 切换 **TTyPageControl** 页面后旧页控件不再残留(先置 `csNoDesignVisible` 再改 `Visible`,使可见性即时重算)。
  - **TTyTreeView / TTyListBox / TTyMemo** 的内部子控件(滚动条、TTyTreeView 的内联编辑器)不再在设计器中露出。

## [2.1.0] — 2026-06-30

一个大型功能版本。主角是 **TTyTreeView**(一个 VirtualTreeView 级别的虚拟树),同时新增另外五个控件、
为 **TTyForm** 加入原生窗口缩放与窗口特效,并为整个库加上键盘助记符。

### 新增 — 新控件

- **TTyTreeView** —— 虚拟、数据按需加载的树,可承载百万级节点:
  - 三阶段惰性初始化;增量高度/位置缓存 + 快速命中测试。
  - 多列 + 可拖拽表头 —— 列**调宽**、**重排**、**自动列宽 / 弹性列**。
  - **排序** —— `OnCompareNodes`、点击表头切换升降序(带方向箭头)、惰性感知的归并排序。
  - **复选框** + 三态 + 自动三态传播,以及**单选(radio)**节点。
  - **多选**(Ctrl / Shift / Ctrl+A)与**整行选择**。
  - **逐节点可变行高**(`OnMeasureItem`)。
  - **增量输入查找**(type-to-find)。
  - **逐单元格自绘**(`OnDrawNode` / `OnAfterCellPaint`)。
  - **内联单元格编辑**(F2 / 双击;Enter 提交、Esc 取消;`OnEditing` / `OnNewText`)。
  - **树内节点拖放** —— 重排或改变父子关系,带 accent 落点标记与循环重父化守卫。
- **TTySplitter** —— 拖动以调整相邻控件大小。
- **TTyStatusBar** —— 分栏状态栏。
- **TTyToolBar** —— 带分隔符的工具栏。
- **TTyDateTimePicker** —— 分段式日期/时间编辑 + 下拉日历 + 时间微调。
- **TTyCalendar** —— 支持 日 → 月 → 年 逐级钻取的日历。

### 新增 — TTyForm

- 原生窗口**缩放**(Windows 自绘边框:`WS_THICKFRAME` + `WM_NCCALCSIZE` / `WM_NCHITTEST`),
  新增 **`Resizable`** 属性;最大化铺满显示器工作区;标题栏拖动 + 顶边缩放。
- 系统**圆角 + 原生投影**(Windows 11 DWM / macOS),默认开启,可通过 CSS 关闭。

### 新增 — 交互、主题、国际化

- **助记符(Mnemonics)** —— `&` 加速键,Alt 下划线显示 + Alt+字母激活,覆盖菜单、按钮、复选框、
  单选钮、分组框、标签、标签页。
- **TTyNativeStyler** —— 让原生 / 第三方 LCL 控件与当前主题协调一致。
- **TTyComboBox** —— 共享的主题化下拉浮层。
- **国际化** —— `resourcestring` + 英文与简体中文 `.po` 词条(主题诊断、设计期字符串、演示程序),
  演示程序支持运行时切换语言。

### 修复

- **TreeView** —— 节点图标不显示(ImageList 绘制被 BGRA 合成覆盖,改为合成之后再画;真正的根因是
  在加列之前就设了 `MainColumn`);HiDPI 垂直轴(滚动 / 命中测试 / 滚动到可见);超大范围的内嵌
  滚动条(最小滑块尺寸、64 位位置映射、构造期创建);展开箭头尺寸;水平滚动;销毁时托管节点数据
  泄漏;删除 / 清空时多选计数完整性。
- **TTyForm** —— 最大化底边钻到任务栏下方;双击最大化"原地变大";顶边缩放;顶部边框过宽。
- **主题** —— 双模式主题以无模式方式加载时崩溃;`TTyNativeStyler` 在深色主题下的文字颜色。
- **TTyEdit** —— 光标高度改为跟随字体行高(原先绑定盒子高度,在树的内联编辑器等紧凑宿主里只有半高)。
- **TTyMemo** —— 文本测量性能(逐行宽度缓存)。

### 平台

- **macOS** —— 编译 + 运行修复(系统主题检测用 process 单元、`CGFloat`、多显示器启动定位)。
- 自绘编辑控件的**输入法(IME)**支持(Qt6 / GTK2)。

### 说明

- 原生窗口缩放本版本**仅 Windows**;GTK / Qt / Cocoa 回退到手动缩放边距(原生交接计划中)。

## [2.0.0] — 2026-06-20

2.x 初始基线:基于 `.tycss` v2 主题引擎(先合并后解析、分层 token、双 `@mode`、跟随系统亮/暗 + 强调色、
热重载 + lint)的全自绘控件集,12 套内置主题,逐控件 `About` 元数据,以及发布工具链。
