# TyControls

Lazarus 自绘控件库。162 个控件全部由 BGRABitmap 绘制,外观由 `.tycss` 文本主题统一控制,在 Windows、Linux、macOS 上显示效果完全一致。

> **English:** [README.en.md](README.en.md) · **更新日志:** [CHANGELOG.md](CHANGELOG.md)

![Ant Design Pro 布局示例](docs/images/antd-antdesign.png)

**同一个程序,只换一个主题名:**

| `classic` | `win11` | `material3` |
|---|---|---|
| ![classic 主题](docs/images/antd-classic.png) | ![win11 主题](docs/images/antd-win11.png) | ![material3 主题](docs/images/antd-material3.png) |

四张图是同一份 `.lfm`、同一份代码,只改了主题名。主题不只换配色:`classic` 下按钮是立体边框、方角、渐变标题带。

### 亮 / 暗 / 图片主题

| 亮色 | 暗色 | `green`(图片主题) |
|---|---|---|
| ![亮色](docs/images/demo-light.png) | ![暗色](docs/images/demo-dark.png) | ![绿色图片主题](docs/images/demo-green.png) |

亮暗是同一个主题文件里的两套 `@mode` 取值,可跟随操作系统。`green` 是照片背景加半透明控件的图片主题。

### 几个控件的样子

| | |
|---|---|
| **`TTyStringGrid`** 冻结列、行号槽、汇总带<br>![数据网格](docs/images/grid.png) | **`TTyTreeView`** 虚拟树、多列、三态复选<br>![虚拟树](docs/images/treeview.png) |
| **富输入控件** 数值 / 货币 / 掩码 / 滑块 / 计算器<br>![富输入](docs/images/inputs.png) | **自绘对话框** 取色器<br>![取色对话框](docs/images/colordialog.png) |

---

## 特性

- **162 个控件**:按钮、输入、列表、数据网格、虚拟树、Ribbon、日历、Shell 文件浏览、20 个自绘对话框,一套配齐
- **三平台一致**:完全自绘,不包装原生控件,同一份代码在三个平台上渲染出同样的界面
- **主题换肤**:17 个内置主题一个属性切换,支持运行时热切换、跟随系统明暗和强调色;主题是文本文件,改外观不用重编译
- **经典与现代两种风格**:从 Win95 / XP 的立体风到 Win11 / Material 的扁平风都能做,控件密度也可整体切换
- **HiDPI**:矢量绘制,任意缩放比例下清晰;跨屏拖动自动适配新 DPI
- **设计器支持完整**:组件面板拖放、容器控件直接拖入、主题效果设计期可见、File → New 工程模板
- **内置 2022 个矢量图标**(Lucide),按名字取用,不用则不占体积
- **中英文界面**,gettext `.po` 翻译
- **6000+ 单元测试**,全套无内存泄漏

## 支持平台

| 平台 | Widgetset |
|---|---|
| Windows | Win32 / Win64 |
| Linux | GTK2、Qt5、Qt6;GTK3 部分支持(Wayland 下有[已知问题](docs/known-issues.md)) |
| macOS | Cocoa |

依赖:Lazarus 3.x+、FPC 3.2.2+、BGRABitmap(OPM 包名 `BGRABitmapPack`)。

---

## 快速开始

**1. 安装包**

Lazarus 里打开 `tycontrols_dt.lpk`,点 **Use → Install**,IDE 重新编译并重启。运行期包 `tycontrols.lpk` 作为依赖自动安装。

**2. 新建工程**

**File → New… → Project → TyControls 应用程序**

模板生成的主窗体已带自绘标题栏、内容容器 `Surface` 和样式控制器。控件放在 `Surface` 里(`TTyForm` 的可视控件都放它上面,图形控件必须放进去,详见 [TTyForm 文档](docs/controls/ttyform.md))。给已有工程加窗体用 **File → New… → Form → TyControls 窗体**。

**3. 换主题**

选中窗体上的 `TTyStyleController`,把 `ThemeName` 改成任意内置主题名。设计器里立即生效,运行时改同一个属性即热切换。

完整步骤见 [docs/getting-started.md](docs/getting-started.md)。

---

## 控件清单

162 个控件,分 16 个组件面板分页。每个控件的属性、事件、主题键说明见 **[docs/controls/](docs/controls/)**。

### 核心 · `TyControls`(2)

| 控件 | 说明 |
|---|---|
| `TTyStyleController` | 样式控制器:加载主题、切换密度、跟随系统亮暗 |
| `TTyNativeStyler` | 让原生 / 第三方 LCL 控件跟随当前主题着色 |

### 按钮 · `TyControls Buttons`(8)

| 控件 | 说明 |
|---|---|
| `TTyButton` | 按钮,支持 primary / danger / ghost 变体和数字徽标 |
| `TTyGlyphButton` | 带图标的按钮 |
| `TTyGlyphContainerButton` | 只放图标的方形按钮,常用于工具条 |
| `TTySpeedButton` | 可保持按下态的快捷按钮 |
| `TTyDropDownButton` | 分裂按钮:左半执行、右半展开菜单 |
| `TTyMenuButton` | 整个按钮都是下拉触发器 |
| `TTyColorButton` | 显示并选择颜色的按钮 |
| `TTyButtonGroup` | 分段按钮条,相邻段共边、单选 |

### 标签与标记 · `TyControls Labels`(7)

| 控件 | 说明 |
|---|---|
| `TTyLabel` | 文本标签,支持自动换行(含中日韩逐字断行)和助记符 |
| `TTyHtmlLabel` | 支持行内 HTML 子集(粗体 / 斜体 / 链接 / 颜色)的标签 |
| `TTyLinkLabel` | 超链接文字 |
| `TTyShadowLabel` | 带投影的标签 |
| `TTyGlowLabel` | 带发光描边的标签 |
| `TTyTag` | 可关闭的标签胶囊 |
| `TTyBadge` | 数字 / 圆点角标,可吸附到任意控件 |

### 文本与数值输入 · `TyControls Edits`(14)

| 控件 | 说明 |
|---|---|
| `TTyEdit` | 单行文本框:选区、剪贴板、词级导航 |
| `TTyMemo` | 多行文本框 |
| `TTySpinEdit` | 整数微调框 |
| `TTyFloatSpinEdit` | 小数微调框,步长可小于 1 |
| `TTyNumericEdit` | 只接受数字的输入框,失焦时千分位格式化 |
| `TTyCurrencyEdit` | 货币输入框 |
| `TTyMaskEdit` | 掩码输入框(电话、身份证、日期等) |
| `TTyURLEdit` | 网址输入框,尾部带打开按钮 |
| `TTyComboEdit` | 文本框 + 下拉箭头,下拉内容自定义 |
| `TTyTrackEdit` | 内嵌滑块的数值输入框 |
| `TTyCalcEdit` | 内嵌计算器的输入框 |
| `TTyCalcCurrencyEdit` | 货币版计算器输入框 |
| `TTyCalculator` | 独立计算器面板 |
| `TTyUpDown` | 独立的上下微调按钮,可绑定其他控件 |

### 勾选与开关 · `TyControls Choices`(6)

| 控件 | 说明 |
|---|---|
| `TTyCheckBox` | 复选框,支持三态 |
| `TTyRadioButton` | 单选按钮 |
| `TTyToggleSwitch` | 开关 |
| `TTyRadioGroup` | 带标题框的单选组 |
| `TTyCheckGroup` | 带标题框的复选组 |
| `TTySegmented` | 分段控制器 |

### 列表与下拉 · `TyControls Lists`(14)

| 控件 | 说明 |
|---|---|
| `TTyComboBox` | 下拉框,可编辑,支持前缀补全 |
| `TTyListBox` | 列表框 |
| `TTyCheckListBox` | 每行带复选框的列表 |
| `TTyMRUComboBox` | 记住最近输入的下拉框 |
| `TTyComboBoxEx` | 每项可带图标的下拉框 |
| `TTyOfficeComboBox` | 带分组标题的下拉框 |
| `TTyOfficeListBox` | 带分组标题的列表 |
| `TTyAdvancedComboBox` | 每项两行(标题 + 副标题 + 图标)的下拉框 |
| `TTyAdvancedListBox` | 每项两行的富列表 |
| `TTyCheckComboBox` | 可多选的下拉框 |
| `TTyValueListEditor` | 属性表:左键右值,每行可指定编辑器 |
| `TTyTransfer` | 双列表穿梭框 |
| `TTyTreeSelect` | 树形下拉选择器 |
| `TTyCascader` | 级联选择器(省 / 市 / 区) |

### 颜色 / 字体 / 文件选择器 · `TyControls Pickers`(11)

| 控件 | 说明 |
|---|---|
| `TTyColorBox` | 颜色下拉框 |
| `TTyColorComboBox` | 颜色下拉框,末尾带「更多…」打开取色对话框 |
| `TTyColorListBox` | 颜色列表 |
| `TTyColorGrid` | 方格调色板 |
| `TTyLColorPicker` | 亮度条取色器 |
| `TTyHSColorPicker` | 色相 / 饱和度取色器 |
| `TTyFontComboBox` | 字体下拉框,逐项用自身字体预览 |
| `TTyFontListBox` | 字体列表 |
| `TTyFontSizeComboBox` | 字号下拉框 |
| `TTyFilterComboBox` | 文件类型过滤下拉框 |
| `TTyShellComboBox` | 目录下拉框 |

### 仪表与指示器 · `TyControls Gauges`(12)

| 控件 | 说明 |
|---|---|
| `TTyGauge` | 仪表:线性 / 弧形 / 环形 |
| `TTyMeter` | 指针式仪表盘 |
| `TTyLevelMeter` | 电平表,分段点亮 + 峰值保持 |
| `TTyDial` | 旋钮 |
| `TTyGearDial` | 齿轮外圈旋钮 |
| `TTyAnalogClock` | 模拟时钟 |
| `TTyCircularProgress` | 环形进度 |
| `TTyActivityIndicator` | 旋转忙碌指示环 |
| `TTyActivityBar` | 不确定进度条 |
| `TTyGearActivityIndicator` | 齿轮忙碌指示 |
| `TTySparkline` | 迷你趋势图 |
| `TTyRating` | 星级评分 |

### 条状控件 · `TyControls Bars`(15)

| 控件 | 说明 |
|---|---|
| `TTyTrackBar` | 滑块 |
| `TTyProgressBar` | 进度条 |
| `TTyScrollBar` | 滚动条 |
| `TTyStatusBar` | 状态栏 |
| `TTyToolBar` | 工具条 |
| `TTyToolButton` | 工具条按钮:命令 / 开关 / 下拉 / 分组 / 分隔等六种样式 |
| `TTyToolSeparator` | 工具条分隔符 |
| `TTyToolBarEx` | 放不下的按钮自动折进溢出菜单的工具条 |
| `TTyControlBar` | 按宽度自动折行分带的容器 |
| `TTyCoolBar` | 可拖动的带条容器 |
| `TTyAlert` | 内联警告条:信息 / 成功 / 警告 / 错误 |
| `TTyPagination` | 分页器 |
| `TTySteps` | 步骤条 |
| `TTyBreadcrumb` | 面包屑导航 |
| `TTyHeaderControl` | 独立列头条 |

### 容器与布局 · `TyControls Containers`(20)

| 控件 | 说明 |
|---|---|
| `TTyPanel` | 面板 |
| `TTyGroupBox` | 分组框 |
| `TTyCard` | 卡片:标题 / 内容 / 操作 |
| `TTyExPanel` | 可折叠面板 |
| `TTyScrollBox` | 滚动容器 |
| `TTyScrollPanel` | 拖到边缘自动滚动的容器 |
| `TTyGridPanel` | 设计器网格容器,格子可直接拖入控件 |
| `TTyRelativePanel` | 按相对关系布局的容器 |
| `TTyPageControl` | 多页容器,页面可直接拖入控件 |
| `TTyTabSheet` | `TTyPageControl` 的页 |
| `TTyTabSet` | 纯页签条,不承载页面 |
| `TTySplitter` | 分隔条 |
| `TTyBevel` | 凹凸装饰线 |
| `TTyDivider` | 分隔线,可带标题 |
| `TTyPaintPanel` | 自绘面板 |
| `TTySizeBox` | 右下角尺寸手柄 |
| `TTyToolGroupPanel` | 工具分组容器 |
| `TTyListGroupPanel` | 带分组标题的列表容器 |
| `TTyTitleBar` | 自绘标题栏,配合 `TTyForm` |
| `TTyEmpty` | 空状态:插画 + 文案 + 操作按钮 |

### 数据视图 · `TyControls Data Views`(10)

| 控件 | 说明 |
|---|---|
| `TTyStringGrid` | 数据网格:冻结、虚拟化、编辑、筛选、分组、撤销重做 |
| `TTyDrawGrid` | 内容自绘的网格 |
| `TTyTreeView` | 虚拟树,可承载百万节点;多列、三态复选、内联编辑、拖放 |
| `TTyListView` | 列表视图:报表 / 图标 / 平铺等五种视图 + 分组 + 虚拟模式 |
| `TTyShellTreeView` | 文件系统目录树 |
| `TTyShellListView` | 文件系统文件列表 |
| `TTyCalendar` | 日历:日 / 月 / 年下钻 |
| `TTyDateTimePicker` | 日期时间选择器,支持空值 |
| `TTyImageView` | 图片查看器:平移、缩放、滤镜 |
| `TTyPreviewBox` | 文件预览框 |

### 菜单 · `TyControls Menus`(4)

| 控件 | 说明 |
|---|---|
| `TTyMenuBar` | 主菜单栏 |
| `TTyPopupMenu` | 右键菜单 |
| `TTyImagesMenu` | 带图标的菜单 |
| `TTyMenuEx` | 扩展菜单 |

### Ribbon · `TyControls Ribbon`(7)

| 控件 | 说明 |
|---|---|
| `TTyRibbon` | Ribbon 主体 |
| `TTyRibbonPage` | Ribbon 页 |
| `TTyRibbonGroup` | 页内功能组 |
| `TTyRibbonAppMenu` | 应用菜单(File)按钮 |
| `TTyRibbonQuickAccess` | 快速访问工具栏 |
| `TTyRibbonGallery` | 图库,可展开成弹出网格 |
| `TTyRibbonBackstage` | 全窗口后台视图 |

### 图像与提示 · `TyControls Images`(9)

| 控件 | 说明 |
|---|---|
| `TTyIconFont` | 图标字体:按码点或名字取矢量图标,随主题着色 |
| `TTyCharImage` | 把一个图标字形当图片用 |
| `TTyImage` | 图片控件 |
| `TTyGlyphImageList` | 图标字体驱动的图像列表 |
| `TTyImageCollection` | 多分辨率图像集,按 DPI 取图 |
| `TTyVirtualImageList` | 按需生成任意尺寸的图像列表;本身是标准 `TCustomImageList`,可赋给任何控件,支持按名字取图 |
| `TTyHint` | 主题化提示气泡 |
| `TTyBalloonHint` | 带箭头的气球提示 |
| `TTyPopover` | 可承载控件的气泡浮层 |

**内置图标(Lucide)**:加一行 `uses tyControls.Icons.Lucide` 就有 2022 个矢量图标,按名字取用:

```pascal
CharImage1.IconFont  := TyLucideFont;
CharImage1.GlyphName := 'house';
```

字体内嵌在单元里,不用随程序分发文件;不 `uses` 就不进最终程序。组件面板上的 `TTyLucideImageList` 可以直接当图像列表拖放使用。许可为 ISC / MIT,商用无需署名,随发布带上 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) 即可。

### 图形与图表 · `TyControls Shapes & Charts`(4)

| 控件 | 说明 |
|---|---|
| `TTyShape` | 矢量形状:矩形 / 圆 / 三角 / 菱形 / 星形等 15 种,支持自定义多边形 |
| `TTyStarShape` | 星形,角数可调 |
| `TTyArrow` | 方向箭头 |
| `TTyChart` | 图表:折线 / 柱状 / 饼图 |

### 对话框 · `TyControls Dialogs`(20)

| 控件 | 说明 |
|---|---|
| `TTyMessage` | 消息框 |
| `TTyInputDialog` | 文本输入对话框 |
| `TTyPasswordDialog` | 密码输入对话框 |
| `TTyTextDialog` | 多行文本对话框 |
| `TTySelectValueDialog` | 列表单选对话框 |
| `TTySelectPathDialog` | 文件夹选择对话框 |
| `TTyColorDialog` | 取色对话框:HSV / RGB / CMYK / Alpha |
| `TTyFontDialog` | 字体对话框,带实时预览 |
| `TTyFindDialog` | 查找对话框 |
| `TTyReplaceDialog` | 查找替换对话框 |
| `TTyProgressDialog` | 进度对话框 |
| `TTyAboutDialog` | 关于对话框 |
| `TTyOpenDialog` | 打开文件对话框 |
| `TTySaveDialog` | 保存文件对话框 |
| `TTyOpenPictureDialog` | 打开图片对话框,带缩略图 |
| `TTySavePictureDialog` | 保存图片对话框 |
| `TTyOpenPreviewDialog` | 打开对话框 + 自定义预览 |
| `TTySavePreviewDialog` | 保存对话框 + 自定义预览 |
| `TTyNotification` | 角落通知,自动消失 |
| `TTyIconBrowserDialog` | 图标浏览器 |

`TTyStringGrid`、`TTyTreeView`、`TTyForm` 的完整能力见各自文档:[grid.md](docs/controls/grid.md) · [treeview.md](docs/controls/treeview.md) · [ttyform.md](docs/controls/ttyform.md)。

---

## 主题

内置主题编译进二进制,程序不用带 `themes/` 文件夹就能按名切换:

| 主题 | 说明 |
|---|---|
| `default` | 中性基底,亮暗同文件 |
| `system` | 跟随操作系统亮暗和强调色 |
| `win11` `win10` `xp` `classic` `aero` | Windows 各代风格 |
| `macos` `adwaita` `breeze` `ubuntu` | macOS 与 Linux 桌面风格 |
| `material3` `fluent` `antdesign` `bootstrap` | 常见设计体系 |
| `office` | Office 风格 |
| `showcase` | 展示主题 |

另有图片主题 `green`(以文件提供)和 `themes/palettes/` 调色板。所有主题共用同一套语义变量,`--accent` 可在运行时覆盖成任意品牌色。

写自己的主题见 [docs/themes.md](docs/themes.md),`.tycss` 语言参考见 [docs/tycss-reference.md](docs/tycss-reference.md)。

---

## 示例

每个示例都可独立构建:`lazbuild examples/<名称>/<工程>.lpi`。

| 示例 | 内容 |
|---|---|
| [antdesign](examples/antdesign/) | 仿 Ant Design Pro 后台(侧边导航 + 6 页),运行时换肤 |
| [demo](examples/demo/) | 综合演示:全部控件 + 多主题 + 切换语言 |
| [grid](examples/grid/) | 数据网格:冻结 / 百万行 / 排序筛选分组 / 16 种编辑器 / 撤销重做 |
| [treeview](examples/treeview/) | 虚拟树:百万节点 / 多列 / 复选 / 内联编辑 / 拖放 |
| [dialogs](examples/dialogs/) | 全部自绘对话框 |
| [theming](examples/theming/) | 自定义主题 + 运行时热切换 |
| [ribbon](examples/ribbon/) | Ribbon 全家桶 |
| [containers](examples/containers/) | 布局容器 |
| [listview](examples/listview/) | 列表视图:五视图 / 分组 / 10 万行虚拟 |
| [inputs](examples/inputs/) | 富输入控件 |
| [shapes](examples/shapes/) | 形状控件 + `StyleOverride` |
| [rtl](examples/rtl/) | 从右往左镜像与双向文本 |
| [icons](examples/icons/) | 图标字体 |
| [transitions](examples/transitions/) | 滑入 / 淡入过渡 |

其余 30 多个单控件示例见 [examples/](examples/)。

---

## 文档

| 文档 | 内容 |
|---|---|
| [getting-started.md](docs/getting-started.md) | 安装、第一个窗体、主题、HiDPI |
| [controls/](docs/controls/) | 逐控件 API 说明 |
| [themes.md](docs/themes.md) | 写自己的主题 |
| [tycss-reference.md](docs/tycss-reference.md) | `.tycss` 语言参考 |
| [events.md](docs/events.md) | 通用事件约定 |
| [rtl.md](docs/rtl.md) | 双向文本与右到左布局 |
| [known-issues.md](docs/known-issues.md) | 已知问题 |
| [CHANGELOG.md](CHANGELOG.md) | 更新日志 |

---

## 界面语言

库自带中英文界面。LCL 的 `SetDefaultLang` 只加载应用自己的 `.po`,库的翻译要多加一行:

```pascal
uses ..., LCLTranslator;

SetDefaultLang('', LangDir);                                                        // 应用
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');  // 控件库
```

部署时把 `languages/tycontrols.<语言>.po` 与应用自己的 `.po` 放在同一个 `languages/` 目录。注意两点:

- 部署文件名是 `tycontrols.<语言>.po`,由源码里的 `tycontrols.strconsts.<语言>.po` 改名而来。第三个参数必须传 `'tycontrols'`(不能带点,LCL 会把点号后面当扩展名剥掉),第四个参数传真实单元名 `tyControls.StrConsts`。
- 英文部署也要带 `tycontrols.en.po`,它是日历和日期框的月份、星期名跟随应用语言的开关。

完整示例见 [examples/demo](examples/demo/)。

---

## 许可

修改版 LGPL,与 FPC RTL / LCL / BGRABitmap 相同:可以静态链接进闭源商业软件分发;修改库本身的源码时,修改部分需以同样许可开放。

完整条款见 [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt) 与 [COPYING.LGPL.txt](COPYING.LGPL.txt)。
