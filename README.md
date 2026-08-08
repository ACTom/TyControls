# TyControls

一套支持皮肤/样式的 **Lazarus 控件库**:控件完全自绘(BGRABitmap),用 CSS-lite 文本主题(`.tycss`)统一驱动外观,在 Windows / Linux / macOS 上呈现像素级一致的界面。

> **English:** [README.en.md](README.en.md) · **更新日志:** [CHANGELOG.md](CHANGELOG.md)

![Ant Design Pro 布局示例](docs/images/antd-antdesign.png)

**同一个程序,只换一个主题名:**

| `classic` | `win11` | `material3` |
|---|---|---|
| ![classic 主题](docs/images/antd-classic.png) | ![win11 主题](docs/images/antd-win11.png) | ![material3 主题](docs/images/antd-material3.png) |

上面四张图是**同一份 `.lfm`、同一份业务代码**,区别只有一个主题名。控件里没有任何一个硬编码的颜色、圆角或线宽 —— 全部来自主题令牌。注意 `classic` 那张:变的不只是配色,连按钮的立体边框、标题带的渐变、方角都变了。

### 亮 / 暗 / 图片主题

综合 gallery 示例(`examples/demo`),同一个窗体:

| 亮色 | 暗色 | `green`(图片主题) |
|---|---|---|
| ![亮色](docs/images/demo-light.png) | ![暗色](docs/images/demo-dark.png) | ![绿色图片主题](docs/images/demo-green.png) |

亮/暗是同一份 `.tycss` 里的两套 `@mode` 取值,可以跟随操作系统。`green` 演示的是主题能做到什么程度 —— 半透明控件浮在一张照片背景上,9-slice 贴图 + `alpha()` 颜色函数,没有一行控件代码为它改动过。

### 几个控件的样子

| | |
|---|---|
| **`TTyStringGrid`** —— 冻结列、行号槽、汇总带、单元格标记色<br>![数据网格](docs/images/grid.png) | **`TTyTreeView`** —— 虚拟树、多列、三态复选<br>![虚拟树](docs/images/treeview.png) |
| **富输入控件** —— 数值 / 货币 / 掩码 / 滑块 / 计算器编辑<br>![富输入](docs/images/inputs.png) | **自绘对话框** —— 取色器:HSV + RGB / CMYK / Alpha 全双向<br>![取色对话框](docs/images/colordialog.png) |

---

## 特性

- **完全自绘** —— 每个控件都用 BGRABitmap 画出来,不包装原生控件。同一份代码在 Windows、Linux、macOS 上是同一套像素。
- **外观与代码分离** —— 颜色、圆角、边框、内距、字号、阴影、渐变、9-slice 贴图全部写在 `.tycss` 文本里。改外观不用重编译,`LoadTheme` 一行运行时热切换。
- **结构级换肤** —— 主题不只是换配色:`render-style` 能把按钮从扁平换成 3D 立体边框,几何令牌能改变控件的固有尺寸。
- **两代密度** —— 经典(Win32 尺度)与现代(Web 尺度)是一条与配色**正交**的轴,`Controller.Density` 一个属性切换。
- **跟随系统** —— 亮/暗模式与强调色可跟随操作系统;单文件 `@mode` 同时携带两套值。
- **162 个可拖放控件**,分 16 个组件面板分页 —— 见[控件清单](#控件清单)。
- **设计器优先** —— `TTyPageControl` 的页与 `TTyGridPanel` 的格子是**真正的设计器容器**:直接往里拖控件、在设计器里看到最终效果、随 `.lfm` 存盘,不需要写一行布局代码。换主题在设计器里就能看到。
- **HiDPI** —— 所有长度按 PPI 缩放,矢量绘制天然清晰;跨屏(PerMonitorV2)拖动时窗口与控件按新 DPI **重新推导**尺寸,来回拖动可精确还原。
- **国际化** —— 库自身的界面字符串走 `resourcestring` + `.po`,随库提供英文与简体中文。
- **6060 个单元测试**,全套件内存零泄漏(heaptrc 验证)。外观另有像素级 golden 守卫 —— 主题解析结果的任何一次变动都必须是有意的。

---

## 快速开始

**1. 安装包**

Lazarus 里打开 `tycontrols_dt.lpk`(设计期包)→ **Use → Install**,IDE 重新编译并重启。运行期包 `tycontrols.lpk` 会作为依赖自动装上。

> 依赖:Lazarus 3.x+ / FPC 3.2.2+ / **BGRABitmap**(OPM 包名 `BGRABitmapPack`)。

**2. 新建工程**

**File → New… → Project → TyControls 应用程序**

模板直接给出一个装配好的 `TTyForm` 主窗体:自绘标题栏、内容承载容器 `Surface`、`TTyStyleController` 都已就位并互相关联。往 `Surface` 上拖控件即可。

> 给已有工程加窗体用 **File → New… → Form → TyControls 窗体**。

**3. 换主题**

选中主窗体上的 `TTyStyleController`,把 `ThemeName` 设成任意内置主题名(`default` / `system` / `win11` / `classic` / `material3` / …)。设计器里立刻可见,运行期改同一个属性即热切换。

完整步骤(第一个窗体、主题切换、HiDPI、部署)见 **[docs/getting-started.md](docs/getting-started.md)**。

---

## 窗体结构

`TTyForm` 的控件承载在一个内容容器 **`TTyFormSurface`** 上 —— 每个窗体有且只有一个,名叫 `Surface`,铺满整个窗体。**把控件都放进它里面。**

- **新建窗体不用管**:两个模板都已带好 `Surface`,设计器里拖控件本来就落进它。
- **图形控件必须放进去**:`TTyLabel`、`TTyShape` 这类无窗口的图形控件画在父控件身上 —— 直接放在窗体上会被 `Surface` 挡住、**看不见**。你这么放时设计器会提示。
- **非可视组件仍留在窗体上**:样式控制器、定时器、对话框组件、图像列表、菜单等不受影响。
- **对话框(`TTyDialog`)没有 `Surface`**:它不可缩放,不需要;控件照常直接放上去。

**它为什么存在 —— 根源是 Windows。** 可缩放的顶层窗口带 `WS_THICKFRAME`,而 Windows 给它的 DWM 后备表面比窗口可见区**小一圈**(高度只有 `窗口高 - 2×边框`),于是窗体自己的 GDI 客户区 DC 被裁短,右边和下边会留一条**画不上去**的死带。子窗口没有这层边框,后备表面覆盖它的完整矩形,能一直画到边缘 —— 所以 `TTyForm` 把主题背景交给 `Surface` 画,而不是画在自己身上。

这个容器在所有 widgetset 上都是无害的,所以不为 Windows 单独分叉。它还顺带解决了第二件事:因为控件是 `Surface` 的**子控件**,`TTyLabel` 这类无窗口控件画在 `Surface` 的画布上、正常可见 —— 如果只是在窗体最底层垫一张图,它们反而会被盖住。

设计器里选中 `Surface`,`Purpose` 属性里有同样的说明。

---

## 控件清单

162 个可从组件面板拖放的控件,分 16 个分页。逐控件的属性 / 事件 / 状态 / 主题键说明见 **[docs/controls/](docs/controls/)**。

### 核心 · `TyControls`(2)

| 控件 | 用来干嘛 |
|---|---|
| `TTyStyleController` | 样式控制器:加载主题、切换密度、跟随系统亮暗;控件通过它取样式 |
| `TTyNativeStyler` | 让原生 / 第三方 LCL 控件跟随当前主题着色 |

### 按钮 · `TyControls Buttons`(8)

| 控件 | 用来干嘛 |
|---|---|
| `TTyButton` | 基础按钮,支持 primary / danger / ghost 变体与数字徽标 |
| `TTyGlyphButton` | 带图标的按钮,图标来自图标字体或图像集 |
| `TTyGlyphContainerButton` | 只放一个图标的方形按钮,常用于工具条 |
| `TTySpeedButton` | 可保持按下态的快捷按钮 |
| `TTyDropDownButton` | 分裂按钮:左半执行、右半展开菜单 |
| `TTyMenuButton` | 整颗按钮都是下拉触发器 |
| `TTyColorButton` | 显示并选择一个颜色的按钮 |
| `TTyButtonGroup` | 分段按钮条,相邻段共边、单选 |

### 标签与标记 · `TyControls Labels`(7)

| 控件 | 用来干嘛 |
|---|---|
| `TTyLabel` | 文本标签,支持自动换行(含中日韩逐字断行)与助记符 |
| `TTyHtmlLabel` | 支持行内 HTML 子集(粗体 / 斜体 / 链接 / 颜色)的标签 |
| `TTyLinkLabel` | 超链接文字,带下划线与悬停高亮 |
| `TTyShadowLabel` | 带投影的标签 |
| `TTyGlowLabel` | 带发光描边的标签 |
| `TTyTag` | 可关闭的标签胶囊,用于筛选条件、状态标记 |
| `TTyBadge` | 数字 / 圆点角标,可吸附到任意控件的右上角 |

### 文本与数值输入 · `TyControls Edits`(14)

| 控件 | 用来干嘛 |
|---|---|
| `TTyEdit` | 单行文本框:选区、剪贴板、词级导航、水平滚动 |
| `TTyMemo` | 多行文本框:二维导航、跨行编辑、垂直滚动 |
| `TTySpinEdit` | 数值微调框,带上下箭头 |
| `TTyFloatSpinEdit` | 小数微调框,`Value` 是 `Double`,步长也可以是小数 |
| `TTyNumericEdit` | 只接受数字的输入框,失焦时按千分位格式化 |
| `TTyCurrencyEdit` | 货币输入框,自动加货币符号 |
| `TTyMaskEdit` | 按掩码约束输入(电话、身份证、日期等) |
| `TTyURLEdit` | 网址输入框,尾部带打开按钮 |
| `TTyComboEdit` | 文本框 + 下拉箭头,下拉内容由你决定 |
| `TTyTrackEdit` | 文本框内嵌一条滑块,数值可拖可输 |
| `TTyCalcEdit` | 文本框内嵌计算器按钮,点开即算 |
| `TTyCalcCurrencyEdit` | 货币版的计算器输入框 |
| `TTyCalculator` | 独立的计算器面板 |
| `TTyUpDown` | 独立的上下微调按钮,可绑定到别的控件 |

### 勾选与开关 · `TyControls Choices`(6)

| 控件 | 用来干嘛 |
|---|---|
| `TTyCheckBox` | 复选框,支持三态 |
| `TTyRadioButton` | 单选按钮 |
| `TTyToggleSwitch` | 开关,旋钮在两态间滑动 |
| `TTyRadioGroup` | 带标题框的单选组,自动排布 |
| `TTyCheckGroup` | 带标题框的复选组 |
| `TTySegmented` | 分段控制器:一排互斥选项,选一个值而不是切一页 |

### 列表与下拉 · `TyControls Lists`(14)

| 控件 | 用来干嘛 |
|---|---|
| `TTyComboBox` | 下拉框,可编辑并支持前缀自动补全 |
| `TTyListBox` | 条目列表,键盘导航 + 内嵌滚动条 |
| `TTyCheckListBox` | 每行带复选框的列表 |
| `TTyMRUComboBox` | 记住最近输入并置顶的下拉框 |
| `TTyComboBoxEx` | 每项可带图标的下拉框 |
| `TTyOfficeComboBox` | 带分组标题带的下拉框 |
| `TTyOfficeListBox` | 带分组标题带的列表 |
| `TTyAdvancedComboBox` | 每项两行(标题 + 副标题 + 图标)的下拉框 |
| `TTyAdvancedListBox` | 每项两行的富列表 |
| `TTyCheckComboBox` | 可多选的下拉框,字段显示已选摘要 |
| `TTyValueListEditor` | 属性检视表:左键右值,每行可指定编辑器类型 |
| `TTyTransfer` | 双列表穿梭框,在两侧之间搬条目 |
| `TTyTreeSelect` | 下拉里是一棵树的选择器 |
| `TTyCascader` | 级联选择:逐级展开的多列选择器 |

### 颜色 / 字体 / 文件选择器 · `TyControls Pickers`(11)

| 控件 | 用来干嘛 |
|---|---|
| `TTyColorBox` | 颜色下拉框,每项一个色块 |
| `TTyColorComboBox` | 颜色下拉框,末尾带「更多…」打开取色对话框 |
| `TTyColorListBox` | 颜色列表 |
| `TTyColorGrid` | 方格调色板 |
| `TTyLColorPicker` | 亮度条取色器 |
| `TTyHSColorPicker` | 色相 / 饱和度平面取色器 |
| `TTyFontComboBox` | 字体下拉框,每项用该字体自身预览 |
| `TTyFontListBox` | 字体列表 |
| `TTyFontSizeComboBox` | 字号下拉框 |
| `TTyFilterComboBox` | 文件类型过滤器下拉框 |
| `TTyShellComboBox` | 目录下拉框,配合文件视图使用 |

### 仪表与指示器 · `TyControls Gauges`(12)

| 控件 | 用来干嘛 |
|---|---|
| `TTyGauge` | 仪表:线性 / 弧形 / 环形三种形态 |
| `TTyMeter` | 指针式仪表盘,带刻度 |
| `TTyLevelMeter` | 电平表,分段点亮 + 峰值保持 |
| `TTyDial` | 旋钮 |
| `TTyGearDial` | 带齿轮外圈的装饰旋钮 |
| `TTyAnalogClock` | 模拟时钟 |
| `TTyCircularProgress` | 环形进度,中心显示百分比 |
| `TTyActivityIndicator` | 旋转的忙碌指示环 |
| `TTyActivityBar` | 不确定进度的滚动条 |
| `TTyGearActivityIndicator` | 齿轮造型的忙碌指示 |
| `TTySparkline` | 迷你趋势图,嵌在卡片或表格里 |
| `TTyRating` | 星级评分,支持悬停预览 |

### 条状控件 · `TyControls Bars`(15)

| 控件 | 用来干嘛 |
|---|---|
| `TTyTrackBar` | 滑块 |
| `TTyProgressBar` | 进度条 |
| `TTyScrollBar` | 滚动条 |
| `TTyStatusBar` | 底部多分区状态栏 |
| `TTyToolBar` | 工具条 |
| `TTyToolButton` | 工具条按钮:六种样式(命令 / 开关 / 分裂下拉 / 附箭头下拉 / 空位 / 分隔线)、相邻单选组、强制断行 |
| `TTyToolSeparator` | 工具条分隔符 |
| `TTyToolBarEx` | 装不下的按钮自动折进溢出菜单的工具条 |
| `TTyControlBar` | 按宽度自动折行分带的多带容器（仅排布，暂无拖动） |
| `TTyCoolBar` | Windows 风格的可拖动带条 |
| `TTyAlert` | 内联警告条:信息 / 成功 / 警告 / 错误 |
| `TTyPagination` | 分页器 |
| `TTySteps` | 步骤条,横竖两向 |
| `TTyBreadcrumb` | 面包屑导航 |
| `TTyHeaderControl` | 独立的列头条,可调宽、可排序 |

### 容器与布局 · `TyControls Containers`(20)

| 控件 | 用来干嘛 |
|---|---|
| `TTyPanel` | 基础面板 |
| `TTyGroupBox` | 带标题的分组框 |
| `TTyCard` | 卡片:标题 / 内容 / 操作三段式 |
| `TTyExPanel` | 可折叠面板,标题栏带展开箭头 |
| `TTyScrollBox` | 可滚动容器 |
| `TTyScrollPanel` | 拖到边缘自动滚动的容器 |
| `TTyGridPanel` | **设计器网格**:设几行几列就出几个格子,直接往格子里拖控件 |
| `TTyRelativePanel` | 按相对关系(在谁右边、与谁对齐)布局的容器 |
| `TTyPageControl` | **设计器多页容器**,页是真正可拖入控件的容器 |
| `TTyTabSheet` | `TTyPageControl` 的一页 |
| `TTyTabSet` | 纯页签条,不承载页面;内容切换由你自己处理 |
| `TTySplitter` | 可拖拽的面板分隔条 |
| `TTyBevel` | 凹凸装饰线 |
| `TTyDivider` | 分隔线,可带居中标题 |
| `TTyPaintPanel` | 把画布交给你自己画的面板 |
| `TTySizeBox` | 右下角的尺寸手柄 |
| `TTyToolGroupPanel` | 工具分组容器 |
| `TTyListGroupPanel` | 带分组标题的列表容器 |
| `TTyTitleBar` | 自绘标题栏,配合 `TTyForm` 使用 |
| `TTyEmpty` | 空状态:插画 + 文案 + 可选操作按钮 |

### 数据视图 · `TyControls Data Views`(10)

| 控件 | 用来干嘛 |
|---|---|
| `TTyStringGrid` | **数据网格**:冻结、虚拟化、编辑、筛选、分组、撤销重做 |
| `TTyDrawGrid` | 数据由事件提供的网格,内容自绘 |
| `TTyTreeView` | **虚拟树**:按需加载,可承载百万节点;多列、复选、内联编辑、拖放;另有可选的 `Items` 节点集合,设计器里就能把树填好 |
| `TTyListView` | 列表视图:报表 / 图标 / 平铺 / 列表 / 小图标五视图 + 分组 + 虚拟模式 |
| `TTyShellTreeView` | 文件系统目录树 |
| `TTyShellListView` | 文件系统文件列表 |
| `TTyCalendar` | 日历:日 / 月 / 年下钻 |
| `TTyDateTimePicker` | 日期时间选择器,下拉日历 + 分段时间微调;可表示"未选日期"(`DateIsNull`) |
| `TTyImageView` | 图片查看器:平移、缩放、BGRA 滤镜 |
| `TTyPreviewBox` | 文件预览框,配合文件对话框使用 |

### 菜单 · `TyControls Menus`(4)

| 控件 | 用来干嘛 |
|---|---|
| `TTyMenuBar` | 主菜单栏 |
| `TTyPopupMenu` | 右键弹出菜单 |
| `TTyImagesMenu` | 每项带图标的菜单 |
| `TTyMenuEx` | 扩展菜单,支持更丰富的项样式 |

### Ribbon · `TyControls Ribbon`(7)

| 控件 | 用来干嘛 |
|---|---|
| `TTyRibbon` | Ribbon 主体,承载多个页 |
| `TTyRibbonPage` | Ribbon 的一页 |
| `TTyRibbonGroup` | 页内的一个功能组 |
| `TTyRibbonAppMenu` | 左上角的应用菜单(File)按钮 |
| `TTyRibbonQuickAccess` | 快速访问工具栏 |
| `TTyRibbonGallery` | 图库:一排可视化选项,可展开成弹出网格 |
| `TTyRibbonBackstage` | 全窗口的后台视图(File 展开后那一屏) |

### 图像与提示 · `TyControls Images`(9)

| 控件 | 用来干嘛 |
|---|---|
| `TTyIconFont` | 图标字体:按码点取矢量图标,随主题着色 |
| `TTyCharImage` | 把一个图标字体字形当图片用 |
| `TTyImage` | 图片控件,支持透明与缩放模式 |
| `TTyGlyphImageList` | 图标字体驱动的图像列表 |
| `TTyImageCollection` | 多分辨率图像集,按 DPI 取最合适的一张 |
| `TTyVirtualImageList` | 从图像集按需生成指定尺寸的图像列表 |
| `TTyHint` | 主题化的提示气泡 |
| `TTyBalloonHint` | 带箭头的气球提示 |
| `TTyPopover` | **能放控件**的气泡浮层,不只是文字 |

### 图形与图表 · `TyControls Shapes & Charts`(4)

| 控件 | 用来干嘛 |
|---|---|
| `TTyShape` | 矢量形状:矩形 / 圆 / 椭圆 / 三角 / 菱形 / 圆角矩形 / 线 |
| `TTyStarShape` | 星形,角数可调 |
| `TTyArrow` | 方向箭头 |
| `TTyChart` | 图表:折线 / 柱状 / 饼图 |

### 对话框 · `TyControls Dialogs`(19)

| 控件 | 用来干嘛 |
|---|---|
| `TTyMessage` | 消息框(信息 / 警告 / 错误 / 确认) |
| `TTyInputDialog` | 单行文本输入对话框 |
| `TTyPasswordDialog` | 掩码密码输入对话框 |
| `TTyTextDialog` | 可缩放的多行文本对话框 |
| `TTySelectValueDialog` | 列表单选对话框 |
| `TTySelectPathDialog` | 文件夹选择对话框 |
| `TTyColorDialog` | 取色对话框:HSV / RGB / CMYK / Alpha 全双向,附常用色速取网格 |
| `TTyFontDialog` | 字体对话框,带实时预览 |
| `TTyFindDialog` | 查找对话框(无模态) |
| `TTyReplaceDialog` | 查找替换对话框(无模态) |
| `TTyProgressDialog` | 进度对话框 |
| `TTyAboutDialog` | 关于对话框 |
| `TTyOpenDialog` | 打开文件对话框 |
| `TTySaveDialog` | 保存文件对话框 |
| `TTyOpenPictureDialog` | 打开图片对话框,带缩略图 |
| `TTySavePictureDialog` | 保存图片对话框 |
| `TTyOpenPreviewDialog` | 打开对话框 + 右侧自定义预览 |
| `TTySavePreviewDialog` | 保存对话框 + 右侧自定义预览 |
| `TTyNotification` | 角落浮出的通知,自动消失 |

> 有三个控件的能力远超一行清单能写下的:
> **[`TTyStringGrid`](docs/controls/grid.md)** —— 冻结行列、百万行虚拟化、16 种内建编辑器、Excel 式列筛选、分组小计、撤销/重做、剪贴板与 CSV 导入导出;
> **[`TTyTreeView`](docs/controls/treeview.md)** —— 数据按需加载的虚拟树、多列可拖表头、三态复选、内联编辑、节点拖放,以及设计期可编辑的 `Items` 节点集合;
> **[`TTyForm`](docs/controls/ttyform.md)** —— 无边框自绘窗口,含原生缩放、系统圆角与投影。

---

## 主题

全部内置主题都**编译进二进制**,应用无需带 `themes/` 文件夹即可按名切换(`TyBuiltinThemeNames` 列出全部)。

| 主题 | 说明 |
|---|---|
| `default` | `@mode` 亮/暗同文件的中性基底 |
| `system` | 跟随操作系统亮暗 + 强调色 |
| `win11` `win10` `xp` `classic` `aero` | Windows 各世代 |
| `macos` `adwaita` `breeze` `ubuntu` | macOS 与 Linux 桌面 |
| `material3` `fluent` `antdesign` `bootstrap` | 设计体系 |
| `office` | Office 风格 |
| `showcase` | 门面展示主题 |

另有 `green`(图片主题,以文件形式提供)与 `themes/palettes/` 精选调色板。所有主题共用同一套 `:root` 语义变量,`--accent` 可运行时覆盖 —— 一套主题看任意品牌色。

**写自己的主题** → [docs/themes.md](docs/themes.md) · **`.tycss` 语言完整参考** → [docs/tycss-reference.md](docs/tycss-reference.md)

---

## 示例

每个示例都是可独立构建的最小工程:`lazbuild examples/<名称>/<工程>.lpi`。

| 示例 | 演示内容 |
|---|---|
| [antdesign](examples/antdesign/) | **TyControls Pro** —— 仿 Ant Design Pro 后台(侧边导航 + 6 页),运行时换肤 |
| [demo](examples/demo/) | 综合 gallery:全部控件 + 多主题 + 运行时切换语言 |
| [grid](examples/grid/) | `TTyStringGrid` 六页:冻结 / 百万行虚拟 / 排序筛选分组 / 16 种编辑器 / 撤销重做 |
| [treeview](examples/treeview/) | `TTyTreeView`:百万级虚拟树 / 多列排序 / 三态复选 / 内联编辑 / 节点拖放 |
| [dialogs](examples/dialogs/) | 全部 11 个自绘对话框(含模态与无模态) |
| [theming](examples/theming/) | 自定义 `.tycss` 主题 + 运行时热切换 |
| [ribbon](examples/ribbon/) | Ribbon:页 / 组 / 应用菜单 / QAT / Gallery / Backstage |
| [containers](examples/containers/) | `TTyGridPanel` / `TTyExPanel` / `TTyScrollBox` 等布局容器 |
| [listview](examples/listview/) | `TTyListView`:五视图 / 分组折叠 / 10 万行虚拟 |
| [inputs](examples/inputs/) | 富输入:数值 / 货币 / 掩码 / URL / 滑块 / 计算器编辑 |
| [shapes](examples/shapes/) | `TTyShape` / `TTyStarShape` / `TTyArrow` + `StyleOverride` |
| [rtl](examples/rtl/) | 从右往左镜像 + 双向文本:**方向**与**语言(英语/阿拉伯语)两个独立开关**,可分别查看"只镜像""只换字""真正的阿拉伯语界面"三种状态;逐区标注**什么镜像、什么还不镜像**,并单列一页给**故意不镜像**的三个控件与"真实程序里怎么开"的做法 |
| [icons](examples/icons/) | `TTyIconFont` 图标字体 |
| [transitions](examples/transitions/) | 滑入 / 淡入过渡 |

其余单控件示例(button / label / labels / edit / memo / combobox / listbox / spinedit / checkbox / radiobutton / panel / groupbox / scrollbar / progressbar / toggleswitch / trackbar / splitter / statusbar / toolbar / menu / calendar / datetimepicker / tabcontrol / tabset / chart / gauge / hint / htmllabel / imageview / filedialog / shell)见 [examples/](examples/)。

---

## 文档

| 文档 | 内容 |
|---|---|
| [getting-started.md](docs/getting-started.md) | 安装、第一个窗体、主题加载与切换、HiDPI |
| [controls/](docs/controls/) | 逐控件 API 说明(属性 / 事件 / 状态 / 主题键 / 示例) |
| [themes.md](docs/themes.md) | 写自己的主题 |
| [tycss-reference.md](docs/tycss-reference.md) | `.tycss` 语言权威参考:属性、函数、选择器、合并顺序、typeKey 目录 |
| [events.md](docs/events.md) | 通用事件分层约定 |
| [rtl.md](docs/rtl.md) | 双向文本与右到左布局:哪些控件已镜像、哪些还没有、怎么打开 |
| [CHANGELOG.md](CHANGELOG.md) | 版本更新日志 |

---

## 界面语言

TyControls 自身的界面字符串(对话框按钮、ThemeLint 诊断等)使用**独立于宿主应用**的 resourcestring 目录,随库提供英文与简体中文。

LCL 的 `SetDefaultLang` 只加载**你的应用**的 `.po`,不会加载控件库的 —— 所以要多加一行:

```pascal
uses ..., LCLTranslator;

SetDefaultLang('', LangDir);                                                       // 你的应用
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');  // 控件库
Application.CreateForm(TMainForm, MainForm);
```

把 `languages/tycontrols.<lang>.po` 与你自己的 `.po` 一起放进可执行文件旁的 `languages/` 目录。
**英文部署也要带上 `tycontrols.en.po`** —— 它几乎是空的,但里面的语言哨兵是日历/日期框
把月份、星期名从"跟随操作系统区域"切到"跟随应用语言"的开关;不带它,`--lang=en` 下这两个控件
仍显示 OS 区域的名字(机制详见 [docs/controls/calendar.md](docs/controls/calendar.md) §8)。

> **文件主名不能带点号。** 第三个参数必须是 `'tycontrols'` —— LCL 的 `FindLocaleFileName` 会对它调 `ChangeFileExt`,传 `'tycontrols.strconsts'` 会把 `.strconsts` 当扩展名剥掉。第四个参数才传真实的带点单元名 `tyControls.StrConsts`。
>
> 要强制指定语言(不依赖系统区域检测),两处都传语言名:`SetDefaultLang('zh_CN', LangDir)` + `TranslateUnitResourceStringsEx('zh_CN', …)`。

完整示例见 [examples/demo](examples/demo/)。

---

## 许可

TyControls 采用**修改版 LGPL**(与 FPC RTL / LCL / BGRABitmap 同款):允许将本库静态链接进闭源商业应用分发;若修改库本身的源码,修改部分需以同样许可开放。

完整条款见 [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt)(例外条款)与 [COPYING.LGPL.txt](COPYING.LGPL.txt)(LGPL 正文)。
