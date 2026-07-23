# TyControls

一套支持皮肤/样式的 **Lazarus 控件库**:控件完全自绘(BGRABitmap),用 CSS-lite 文本主题(`.tycss`)统一驱动外观,在 Windows / Linux / macOS 上呈现像素级一致的界面。

> **English:** [README.en.md](README.en.md) · **更新日志:** [CHANGELOG.md](CHANGELOG.md)

![Ant Design Pro 布局示例](docs/images/antd-antdesign.png)

**同一个程序,只换一个主题名:**

| `classic` | `win11` | `material3` |
|---|---|---|
| ![classic 主题](docs/images/antd-classic.png) | ![win11 主题](docs/images/antd-win11.png) | ![material3 主题](docs/images/antd-material3.png) |

上面四张图是**同一份 `.lfm`、同一份业务代码**,区别只有一个主题名。控件里没有任何一个硬编码的颜色、圆角或线宽 —— 全部来自主题令牌。注意 `classic` 那张:变的不只是配色,连按钮的立体边框、标题带的渐变、方角都变了。

---

## 特性

- **完全自绘** —— 每个控件都用 BGRABitmap 画出来,不包装原生控件。同一份代码在 Windows、Linux、macOS 上是同一套像素。
- **外观与代码分离** —— 颜色、圆角、边框、内距、字号、阴影、渐变、9-slice 贴图全部写在 `.tycss` 文本里。改外观不用重编译,`LoadTheme` 一行运行时热切换。
- **结构级换肤** —— 主题不只是换配色:`render-style` 能把按钮从扁平换成 3D 立体边框,几何令牌能改变控件的固有尺寸。
- **两代密度** —— 经典(Win32 尺度)与现代(Web 尺度)是一条与配色**正交**的轴,`Controller.Density` 一个属性切换。
- **跟随系统** —— 亮/暗模式与强调色可跟随操作系统;单文件 `@mode` 同时携带两套值。
- **160 个可拖放控件**,分 16 个组件面板分页 —— 见[控件清单](#控件清单)。
- **设计器优先** —— 每个控件都有面板图标、只读 `Version` 属性、`StyleClass` 下拉。`TTyPageControl` 的页与 `TTyGridPanel` 的格子是**真正的设计器容器**:直接往里拖控件,随 `.lfm` 存盘。
- **HiDPI** —— 所有长度按 PPI 缩放,矢量绘制天然清晰。
- **国际化** —— 库自身的界面字符串走 `resourcestring` + `.po`,随库提供英文与简体中文。
- **3949 个单元测试**,全套件内存零泄漏(heaptrc 验证)。外观另有像素级 golden 守卫 —— 主题解析结果的任何一次变动都必须是有意的。

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

它为什么存在:无边框可缩放窗口画不到自己最外圈的像素,右/下边会留一条没画上的细边;而子窗口能画到真正的边缘,所以窗体的主题背景改由 `Surface` 来画。设计器里选中它,`Purpose` 属性有完整说明。

**迁移现有窗体**:把原本直接放在窗体上的控件移进 `Surface` 即可(非可视组件不动)。参考 [examples/button/umain.lfm](examples/button/umain.lfm)。

---

## 控件清单

160 个可从组件面板拖放的控件,分 16 个分页。逐控件的属性 / 事件 / 状态 / 主题键说明见 **[docs/controls/](docs/controls/)**。

### 核心 · `TyControls`(2)
`TTyStyleController` 样式控制器 · `TTyNativeStyler` 让原生 / 第三方 LCL 控件跟随当前主题

### 按钮 · `TyControls Buttons`(8)
`TTyButton` · `TTyGlyphButton` 图标按钮 · `TTyGlyphContainerButton` · `TTySpeedButton` · `TTyDropDownButton` 分裂下拉 · `TTyMenuButton` · `TTyColorButton` · `TTyButtonGroup` 分段按钮条

### 标签与标记 · `TyControls Labels`(7)
`TTyLabel` · `TTyHtmlLabel` 行内 HTML 子集 · `TTyLinkLabel` · `TTyShadowLabel` · `TTyGlowLabel` · `TTyTag` 可关闭标签 · `TTyBadge` 数字 / 圆点角标

### 文本与数值输入 · `TyControls Edits`(13)
`TTyEdit` · `TTyMemo` 多行 · `TTySpinEdit` · `TTyNumericEdit` · `TTyCurrencyEdit` · `TTyMaskEdit` 掩码 · `TTyURLEdit` · `TTyComboEdit` · `TTyTrackEdit` 内嵌滑块 · `TTyCalcEdit` / `TTyCalcCurrencyEdit` 内嵌计算器 · `TTyCalculator` · `TTyUpDown`

### 勾选与开关 · `TyControls Choices`(6)
`TTyCheckBox` 三态 · `TTyRadioButton` · `TTyToggleSwitch` · `TTyRadioGroup` · `TTyCheckGroup` · `TTySegmented` 分段控制器

### 列表与下拉 · `TyControls Lists`(14)
`TTyComboBox` 可编辑 + 前缀补全 · `TTyListBox` · `TTyCheckListBox` · `TTyMRUComboBox` 历史 · `TTyComboBoxEx` 带图 · `TTyOfficeComboBox` / `TTyOfficeListBox` 分组 · `TTyAdvancedComboBox` / `TTyAdvancedListBox` 双行 · `TTyCheckComboBox` 多选 · `TTyValueListEditor` 属性检视 · `TTyTransfer` 穿梭框 · `TTyTreeSelect` 树形下拉 · `TTyCascader` 级联

### 颜色 / 字体 / 文件选择器 · `TyControls Pickers`(11)
`TTyColorBox` · `TTyColorComboBox` · `TTyColorListBox` · `TTyColorGrid` 调色板 · `TTyLColorPicker` / `TTyHSColorPicker` · `TTyFontComboBox` / `TTyFontListBox` / `TTyFontSizeComboBox` · `TTyFilterComboBox` · `TTyShellComboBox`

### 仪表与指示器 · `TyControls Gauges`(12)
`TTyGauge` 线性 / 弧形 / 环形 · `TTyMeter` 指针表 · `TTyLevelMeter` 电平 · `TTyDial` / `TTyGearDial` 旋钮 · `TTyAnalogClock` · `TTyCircularProgress` · `TTyActivityIndicator` / `TTyActivityBar` / `TTyGearActivityIndicator` 忙碌指示 · `TTySparkline` 迷你趋势 · `TTyRating` 评分

### 条状控件 · `TyControls Bars`(14)
`TTyTrackBar` · `TTyProgressBar` · `TTyScrollBar` · `TTyStatusBar` · `TTyToolBar` + `TTyToolSeparator` · `TTyToolBarEx` 溢出折叠 · `TTyControlBar` / `TTyCoolBar` 可拖动带 · `TTyAlert` 内联警告条 · `TTyPagination` 分页器 · `TTySteps` 步骤条 · `TTyBreadcrumb` 面包屑 · `TTyHeaderControl` 列头条

### 容器与布局 · `TyControls Containers`(20)
`TTyPanel` · `TTyGroupBox` · `TTyCard` 卡片 · `TTyExPanel` 可折叠 · `TTyScrollBox` / `TTyScrollPanel` · `TTyGridPanel` **设计器网格** · `TTyRelativePanel` · `TTyPageControl` + `TTyTabSheet` **设计器多页容器** · `TTyTabSet` 纯页签条 · `TTySplitter` · `TTyBevel` · `TTyDivider` · `TTyPaintPanel` 自绘面 · `TTySizeBox` · `TTyToolGroupPanel` · `TTyListGroupPanel` · `TTyTitleBar` · `TTyEmpty` 空状态

### 数据视图 · `TyControls Data Views`(10)
`TTyStringGrid` / `TTyDrawGrid` **数据网格** · `TTyTreeView` **虚拟树** · `TTyListView` 五视图 · `TTyShellTreeView` / `TTyShellListView` 文件系统 · `TTyCalendar` · `TTyDateTimePicker` · `TTyImageView` 平移缩放 + 滤镜 · `TTyPreviewBox`

### 菜单 · `TyControls Menus`(4)
`TTyMenuBar` · `TTyPopupMenu` · `TTyImagesMenu` · `TTyMenuEx`

### Ribbon · `TyControls Ribbon`(7)
`TTyRibbon` + `TTyRibbonPage` + `TTyRibbonGroup` · `TTyRibbonAppMenu` · `TTyRibbonQuickAccess` · `TTyRibbonGallery` · `TTyRibbonBackstage`

### 图像与提示 · `TyControls Images`(9)
`TTyIconFont` 图标字体 · `TTyCharImage` · `TTyImage` · `TTyGlyphImageList` · `TTyImageCollection` · `TTyVirtualImageList` · `TTyHint` · `TTyBalloonHint` · `TTyPopover` 可放控件的气泡

### 图形与图表 · `TyControls Shapes & Charts`(4)
`TTyShape` · `TTyStarShape` · `TTyArrow` · `TTyChart` 折线 / 柱 / 饼

### 对话框 · `TyControls Dialogs`(19)
`TTyMessage` · `TTyInputDialog` · `TTyPasswordDialog` · `TTyTextDialog` · `TTySelectValueDialog` · `TTySelectPathDialog` · `TTyColorDialog` · `TTyFontDialog` · `TTyFindDialog` / `TTyReplaceDialog` 无模态 · `TTyProgressDialog` · `TTyAboutDialog` · `TTyOpenDialog` / `TTySaveDialog` + 图片版 + 预览版 · `TTyNotification` 角落浮出

> 有三个控件的能力远超一行清单能写下的:
> **[`TTyStringGrid`](docs/controls/grid.md)** —— 冻结行列、百万行虚拟化、16 种内建编辑器、Excel 式列筛选、分组小计、撤销/重做、剪贴板与 CSV 导入导出;
> **[`TTyTreeView`](docs/controls/treeview.md)** —— 数据按需加载的虚拟树、多列可拖表头、三态复选、内联编辑、节点拖放;
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

> **文件主名不能带点号。** 第三个参数必须是 `'tycontrols'` —— LCL 的 `FindLocaleFileName` 会对它调 `ChangeFileExt`,传 `'tycontrols.strconsts'` 会把 `.strconsts` 当扩展名剥掉。第四个参数才传真实的带点单元名 `tyControls.StrConsts`。
>
> 要强制指定语言(不依赖系统区域检测),两处都传语言名:`SetDefaultLang('zh_CN', LangDir)` + `TranslateUnitResourceStringsEx('zh_CN', …)`。

完整示例见 [examples/demo](examples/demo/)。

---

## 许可

TyControls 采用**修改版 LGPL**(与 FPC RTL / LCL / BGRABitmap 同款):允许将本库静态链接进闭源商业应用分发;若修改库本身的源码,修改部分需以同样许可开放。

完整条款见 [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt)(例外条款)与 [COPYING.LGPL.txt](COPYING.LGPL.txt)(LGPL 正文)。
