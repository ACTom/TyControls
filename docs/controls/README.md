# 控件 API 文档

TyControls 全部控件的逐控件说明（属性 / 事件 / 状态 / 主题变体 / 示例）。所有控件由 BGRABitmap
全自绘、由 `.tycss` 文本主题统一着色。样式语言参考见 [../tycss-reference.md](../tycss-reference.md)，
通用事件基线见 [../events.md](../events.md)。

## 窗口与镶边

| 控件 | 说明 |
|------|------|
| [TTyForm](ttyform.md) | 自绘无边框窗体基类，`BorderIcons` 驱动 caption 按钮 |
| [TTyTitleBar](titlebar.md) | 可关联的标题栏（`Form.TitleBar` 模式） |
| [caption 按钮](captionbutton.md) | 标题栏的最小化 / 最大化 / 关闭按钮 |
| [窗口镶边总览](formchrome.md) | 窗口镶边整体机制与配置 |

## 按钮与选择

| 控件 | 说明 |
|------|------|
| [TTyButton](button.md) | 按钮：primary / danger / ghost 变体、`:selected`、数字徽标 |
| [TTyCheckBox](checkbox.md) | 复选框，支持三态（`State` / `AllowGrayed`） |
| [TTyRadioButton](radiobutton.md) | 单选按钮（同容器互斥） |
| [TTyToggleSwitch](toggleswitch.md) | 开关（ON/OFF 滑块） |
| [TTySegmented](segmented.md) | 分段控制器(一排互斥选项,可聚焦 + 左右键切换) |

## 命令与分组按钮

| 控件 | 说明 |
|------|------|
| [TTyGlyphButton](glyphbuttons.md) | 图标命令按钮（图标在左 + 标题，复用 TyButton 主题） |
| [TTyGlyphContainerButton](glyphbuttons.md) | Ribbon 风格大按钮（大图标在上 + 标题） |
| [TTySpeedButton](glyphbuttons.md) | 扁平工具栏切换按钮（可按 GroupIndex 分组单选） |
| [TTyDropDownButton](dropbuttons.md) | 分裂式下拉按钮（主区点击 + 箭头区弹出菜单） |
| [TTyMenuButton](dropbuttons.md) | 菜单按钮（整按钮点击即弹出菜单） |
| [TTyColorButton](colorbutton.md) | 颜色按钮（色板 + 点击弹出取色对话框） |
| [TTyButtonGroup](buttongroup.md) | 分段按钮条（等分 N 段，单选/多选） |

## Ribbon

| 控件 | 说明 |
|------|------|
| [TTyRibbon](ribbon.md) | Office 式命令带宿主（标签条 + 分组带，复用 Batch-C 按钮） |
| [TTyRibbonPage](ribbon.md) | Ribbon 标签页（托管分组，`GetChildren` 流式） |
| [TTyRibbonGroup](ribbon.md) | 带标题的分组盒（可选对话框启动器箭头） |
| [TTyRibbonAppMenu](ribbonappmenu.md) | 左上角强调色应用（文件）按钮，下拉命令 + 最近项 |
| [TTyRibbonQuickAccess](ribbonquickaccess.md) | 快速访问栏（标题栏行的紧凑命令带） |
| [TTyRibbonGallery](ribbongallery.md) | 画廊（内联缩略格 + 下拉网格） |
| [TTyRibbonBackstage](ribbonbackstage.md) | 全窗口 backstage（Office「文件」视图:左侧命令栏 + 右侧内容） |

## 文本输入

| 控件 | 说明 |
|------|------|
| [TTyEdit](edit.md) | 单行文本框：选区、剪贴板、词级导航、IME |
| [TTyNumericEdit](numericedit.md) | 数值编辑框（输入过滤 + 失焦分组格式化 + 限幅，Phase 4 参考实现） |
| [TTyCurrencyEdit](currencyedit.md) | 货币编辑框（NumericEdit + 货币符号，仅显示态加符号） |
| [TTyMaskEdit](maskedit.md) | 掩码编辑框（日期 / 电话 / IP；LCL / Delphi 的掩码语言，就地覆写录入 + 自动字面量） |
| [TTyURLEdit](urledit.md) | URL 编辑框（尾部"打开"按钮，默认浏览器打开） |
| [TTyComboEdit](comboedit.md) | 带下拉按钮的编辑框（OnDropDown 弹任意 popup，组合式基座） |
| [TTyTrackEdit](trackedit.md) | 数值编辑框 + 内嵌迷你滑块（拖动设值，NumericEdit 派生） |
| [TTyCalculator](calculator.md) | 四则运算计算器（显示 + 5×4 键盘阵，可键盘输入；供下拉复用） |
| [TTyCalcEdit](calcedit.md) | 数值编辑框 + 计算器下拉（尾部按钮弹计算器，结果写回） |
| [TTyCalcCurrencyEdit](calcedit.md) | 货币编辑框 + 计算器下拉（CurrencyEdit + 计算器弹层） |
| [TTyColorBox](colorbox.md) | 命名颜色组合框（字段/下拉每项色块+名，逐项自绘地基控件） |
| [TTyColorComboBox](colorcombobox.md) | ColorBox + “更多…”行开取色对话框 |
| [TTyColorListBox](colorlistbox.md) | 命名颜色列表框（ColorBox 的列表版，每行色块+名） |
| [TTyColorGrid](colorgrid.md) | 色板网格（网格排列色块，点格选色，16 色默认调色板） |
| [TTyLColorPicker](lcolorpicker.md) | 明度取色竖条（固定色相/饱和度，拖动取明度值） |
| [TTyHSColorPicker](hscolorpicker.md) | 色相×饱和度取色方块（2D，配 LColorPicker 成 HSL 取色器，拖动选色） |
| [TTyFontComboBox](fontcombobox.md) | 字体族组合框（每项用自己的字体画，所见即所得） |
| [TTyFontListBox](fontlistbox.md) | 字体族列表框（FontComboBox 的列表版） |
| [TTyFontSizeComboBox](fontsizecombobox.md) | 可编辑字号组合框（预设 6…72，也可手输） |
| [TTyMemo](memo.md) | 多行编辑器：2D 导航、内嵌滚动条 |
| [TTySpinEdit](spinedit.md) | 数值微调框（箭头 / 方向键 / 滚轮，Min/Max/Increment） |
| [TTyFloatSpinEdit](floatspinedit.md) | 小数微调框（`Value: Double` + `Double` 步长，NumericEdit 派生，带完整文本引擎） |
| [TTyUpDown](updown.md) | 独立上/下微调按钮对（按住连发，绑定到任意控件） |
| [TTyComboBox](combobox.md) | 下拉框：只读选择 + 可编辑 `csDropDown` + 前缀自动补全 |
| [TTyMRUComboBox](mrucombobox.md) | 最近使用（MRU）组合框（提交值去重置顶、`MaxItems` 裁尾） |
| [TTyComboBoxEx](comboboxex.md) | 带每项图标的组合框（字段/下拉共享图文绘制，图标索引存 Objects） |

## 列表与数据

| 控件 | 说明 |
|------|------|
| [TTyCheckListBox](checklistbox.md) | 每行带勾选框的列表（勾选状态存 Objects，排序不错位；空格 / 点框切换） |
| [TTyCheckComboBox](checkcombobox.md) | 下拉勾选组合框（多选、弹层常开，字段显勾选汇总） |
| [TTyValueListEditor](valuelisteditor.md) | 名/值两列编辑器（属性表；值列内联编辑，F2/点选） |
| [TTyOfficeListBox](officelistbox.md) | 带不可选分组标题行的列表框（Office 风格分组） |
| [TTyOfficeComboBox](officecombobox.md) | 带分组标题行的组合框（下拉按组分节，标题行不可选） |
| [TTyAdvancedListBox](advancedlistbox.md) | 富行列表框（每行 图标 + 加粗标题 + 暗色副标题） |
| [TTyAdvancedComboBox](advancedcombobox.md) | 富行组合框（下拉每项 图标+标题+副标题；字段显图标+标题） |
| [TTyListBox](listbox.md) | 列表框：键盘导航、内嵌自动滚动条 |
| [TTyTreeView](treeview.md) | 虚拟树（VirtualTreeView 级）：百万节点、多列 + 排序、复选 + 三态 + 单选、多选 + 整行、内联编辑、节点拖放、逐单元格自绘 |
| [TTyListView](listview.md) | 平铺项视图（TreeView 的非层级兄弟）：报表 / 列表 / 大图标 / 小图标 / 平铺五种模式、列 + 排序、多选 + 框选、虚拟模式（十万行零对象） |
| [TTyStringGrid](grid.md) | 自绘数据网格(TTyCustomGrid / TTyDrawGrid / TTyStringGrid 三层):冻结行列、虚拟化渲染(百万行)、多列排序 / 类型化过滤 / 分组、分组表头、离散多选与选区聚合、逐格外观与边框、换行与行高三件套、列级编辑声明 + EditLink 扩展点、智能粘贴 |
| [TTyShellListView](shelllistview.md) | 文件系统后备的项视图（TTyListView 适配器）：显示目录内容、四列、排序、F2 重命名、按类型分组 |
| [TTyShellTreeView](shelltreeview.md) | 文件系统后备的目录树（TTyTreeView 适配器）：只显示文件夹、懒加载展开、路径定位 |
| [TTyFilterComboBox](filtercombobox.md) | 过滤预设下拉（TTyComboBox 适配器）：解析 LCL 过滤串，选中段即生效掩码 |
| [TTyShellComboBox](shellcombobox.md) | 查找范围下拉（TTyComboBox 适配器）：当前目录面包屑 + 盘符，点行跳转 |
| [tyControls.FileSystem](filesystem.md) | 上面这几个文件系统控件共用的**非可视工具单元**：目录枚举、根位置、排序与过滤（不是控件，不进面板） |
| [TTyTransfer](transfer.md) | 双列表穿梭框(源/目标两栏 + 移动键;经典桌面控件) |
| [TTyTreeSelect](treeselect.md) | 树形下拉(字段 + 弹出真 `TTyTreeView`) |
| [TTyCascader](cascader.md) | 级联选择(省/市/区;选中左列展开右列) |

## 容器与布局

| 控件 | 说明 |
|------|------|
| [TTyPanel](panel.md) | 通用容器面板 |
| [TTyCard](card.md) | 卡片容器（标题条 + 内容 + 操作条,一整块主题化表面） |
| [TTyGroupBox](groupbox.md) | 带标题的分组框 |
| [TTyPageControl](pagecontrol.md) | 多页签容器（含 `TTyTabSheet`） |
| [TTyTabSet](tabset.md) | 纯标签条（非页容器） |
| [TTySplitter](splitter.md) | 面板间可拖拽分隔条 |
| [TTyToolBar](toolbar.md) | 工具条 + `TTyToolSeparator` 分隔符 |
| [TTyStatusBar](statusbar.md) | 底部多分区状态栏 |
| [TTyBevel](bevel.md) | 装饰性 3D 线条 / 边框（凹槽 / 凸脊，主题驱动） |
| [TTyDivider](divider.md) | 带标题的水平分割线（标题 + 细线，`Alignment` 决定标题左/中/右） |
| [TTyPaintPanel](paintpanel.md) | 自绘表面面板（`OnPaintSurface` 把 `TTyPainter` 交给应用同遍绘制） |
| [TTySizeBox](sizebox.md) | 右下角尺寸拖拽手柄 |
| [TTyRadioGroup](radiogroup.md) | 单选组容器（`Items` 自动生成互斥单选,`Columns` 分列） |
| [TTyCheckGroup](checkgroup.md) | 复选组容器（每项一复选框,各项独立） |
| [TTyToolGroupPanel](toolgrouppanel.md) | 带标题的工具按钮组（Ribbon 组风格,流式换行 + `AddButton`） |
| [TTyScrollBox](scrollbox.md) | 滚动视口容器（内容溢出自动显示内嵌滚动条） |
| [TTyScrollPanel](scrollpanel.md) | 自动平移滚动容器（拖到视口边缘朝该边自动滚） |
| [TTyExPanel](expanel.md) | 可折叠/展开面板（点标题栏折叠,高度缓动动画） |
| [TTyGridPanel](gridpanel.md) | 固定网格布局（列×行轨道:绝对/百分比/star,`SetCell` 跨格摆放） |
| [TTyRelativePanel](relativepanel.md) | 相对布局（子控件按规则相对兄弟/父容器摆放,拓扑求解,环安全） |
| [TTyToolBarEx](toolbarex.md) | 带溢出 `»` 折叠的工具条（非换行时尾部按钮收进弹出浮层） |
| [TTyControlBar](controlbar.md) | 可停靠工具带宿主（子控件排成水平 band/行,带左侧抓手） |
| [TTyCoolBar](coolbar.md) | Rebar：抓手拖拽移动band间的缝（改邻带宽度）、拖过邻带可换序、拖到行下另起一行（继承 TTyControlBar） |
| [TTyHeaderControl](headercontrol.md) | 独立列头条（分节:标题/宽度/对齐/排序,点击排序 + 拖边界调宽） |
| [TTyListGroupPanel](listgrouppanel.md) | Outlook 式分组可展开列表（手风琴,`AddGroup`/`AddItem`） |
| [TTyPreviewBox](previewbox.md) | 可复用预览控件（图片走 TTyImage / 文本走只读 TTyMemo / 占位 / 交出位图·文本自定义） |
| [TTyImageView](imageview.md) | 图片查看器：平移/缩放（平滑动画）+ 非破坏性 BGRA 滤镜（灰度/模糊/锐化/反相/着色） |
| [TTyChart](chart.md) | 折线/柱/饼/环形图：设计期系列、自动量程 + nice 刻度、网格、图例、标题、悬停数值 tooltip（BGRA Canvas2D） |
| [Transitions](transitions.md) | 过渡动画工具（非控件）：滑入（跨平台）/ 淡入（Win）出现动画,基于动画内核 |
| [TTyHtmlLabel](htmllabel.md) | 迷你 HTML 标签：行内子集（粗/斜/下/删、字体色·字号、链接、`<br>`）+ 自动换行 |

## 日期与时间

| 控件 | 说明 |
|------|------|
| [TTyCalendar](calendar.md) | 日历：日 / 月 / 年下钻、Min/MaxDate |
| [TTyDateTimePicker](datetimepicker.md) | 日期时间选择器：下拉日历 + 时间分段微调 |

## 范围与进度

| 控件 | 说明 |
|------|------|
| [TTyTrackBar](trackbar.md) | 滑块（连续取值） |
| [TTyScrollBar](scrollbar.md) | 滚动条 |
| [TTyProgressBar](progressbar.md) | 进度条 |

## 图形与仪表

| 控件 | 说明 |
|------|------|
| [TTyGauge](gauge.md) | 数值仪表：线性 / 弧形 / 环形，缓动值动画 |
| [TTyCircularProgress](circularprogress.md) | 环形进度指示器（ProgressBar 的环形版，复用仪表主题） |
| [TTyActivityIndicator](activityindicator.md) | 不确定态忙碌指示器（旋转弧 spinner） |
| [TTyActivityBar](activitybar.md) | 不确定态线性进度条（左右行进的 marching band） |
| [TTyGearActivityIndicator](gearactivityindicator.md) | 不确定态忙碌指示器（旋转齿轮，ActivityIndicator 的机械变体） |
| [TTyMeter](meter.md) | 模拟指针仪表（表盘 + 刻度 + 指针） |
| [TTyLevelMeter](levelmeter.md) | 电平条 / VU 表（连续或分段点亮 + 峰值保持，水平 / 垂直） |
| [TTyDial](dial.md) | 可交互旋钮（拖动 / 滚轮 / 方向键改值） |
| [TTyAnalogClock](analogclock.md) | 模拟时钟表盘（时 / 分 / 秒针，可自动走时） |
| [TTySparkline](sparkline.md) | 内联迷你趋势图（折线 / 柱，无轴） |
| [TTyRating](rating.md) | 星级评分（悬停预览 / 点击 / 半星） |
| [TTyGearDial](geardial.md) | 齿轮旋钮（可拖动 / 滚轮的旋钮变体） |

## 矢量形状

| 控件 | 说明 |
|------|------|
| [TTyShape](shape.md) | 矢量形状图元：矩形 / 圆角矩形 / 正方形 / 椭圆 / 圆 / 三角形 / 菱形 / 线 |
| [TTyStarShape](starshape.md) | N 角星（点数与内外半径比可调） |
| [TTyArrow](arrow.md) | 块状方向箭头（上 / 下 / 左 / 右，头部与箭杆比例可调） |

## 文字

| 控件 | 说明 |
|------|------|
| [TTyLabel](label.md) | 文本标签（支持助记符下划线） |
| [TTyLinkLabel](linklabel.md) | 超链接标签（accent + 下划线，点击打开 URL） |
| [TTyShadowLabel](shadowlabel.md) | 带投影的文字标签 |
| [TTyGlowLabel](glowlabel.md) | 带发光光晕的文字标签 |

## 提示

| 控件 | 说明 |
|------|------|
| [TTyHint](hint.md) | 主题化气泡提示（替换原生 LCL tooltip，全应用生效） |
| [TTyBalloonHint](balloonhint.md) | 带指针的气泡标注（标题 + 正文 + 可选图标） |
| [TTyPopover](popover.md) | **能放控件**的气泡浮层(Hint/BalloonHint 只能放文本 —— 这是功能性缺口) |
| [TTyAlert](alert.md) | **内联**警告条(info / success / warning / error 四型,可关闭) |
| [TTyNotification](notification.md) | 角落浮出、自动消失的 toast(四型 + 四角 + 悬停暂停) |

## 标记与徽标

| 控件 | 说明 |
|------|------|
| [TTyTag](tag.md) | 标签 / 胶囊（颜色变体走 `StyleClass`,可选关闭 `x`） |
| [TTyBadge](badge.md) | 独立数字 / 圆点角标（`Target` 吸附到任意控件的角上） |
| [TTyEmpty](empty.md) | 空状态占位(插画 + 文案 + 可选操作;列表 / 树 / 表格标配) |

## 导航与流程

| 控件 | 说明 |
|------|------|
| [TTyPagination](pagination.md) | 分页器(上一页/下一页 + 页码 + `…` 省略;不依赖 Grid,配任意列表) |
| [TTySteps](steps.md) | 向导步骤条(已完成 / 当前 / 待办由 `StepIndex` 派生,横竖两向) |
| [TTyBreadcrumb](breadcrumb.md) | 面包屑(末项即当前位置、不是链接;溢出省略) |

## 图标与图像

| 控件 | 说明 |
|------|------|
| [TTyIconFont](iconfont.md) | 图标字体源（注册 .ttf、name→codepoint、渲染字形） |
| [TTyCharImage](charimage.md) | 单个图标字体字形作为图像控件 |
| [TTyGlyphImageList](glyphimagelist.md) | 图标字体字形图像列表（供 Ty 控件消费） |
| [TTyImage](image.md) | 主题化位图图像控件（拉伸/等比/居中） |
| [TTyImageCollection](imagecollection.md) | DPI 感知的命名位图集合 |
| [TTyVirtualImageList](imagecollection.md) | 从集合按目标 DPI 绘制的虚拟图像列表 |

## 菜单

| 控件 | 说明 |
|------|------|
| [菜单](menu.md) | `TTyMenuBar`（菜单栏）+ `TTyPopupMenu`（右键弹出菜单） |

## 对话框

| 控件 | 说明 |
|------|------|
| [对话框](dialogs.md) | 全部 11 个自绘对话框组件 + 全局函数（消息 / 输入 / 密码 / 文本 / 选值 / 选路径 / 颜色 / 字体 / 查找 / 替换 / 进度） |
| [文件对话框](filedialog.md) | TTyOpen/Save + 图片版 + 通用预览版（右侧图片/文本预览 + OnPreview 自定义）：树+列表+查找范围+过滤+文件名,三层 API 对齐 LCL |

## 主题与集成

| 控件 | 说明 |
|------|------|
| [TTyStyleController](stylecontroller.md) | 样式控制器：加载 / 切换 `.tycss` 主题 |
| [TTyNativeStyler](nativestyler.md) | 非可视组件：把原生 / 第三方 LCL 控件按主题着色 |
