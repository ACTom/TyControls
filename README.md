# TyControls

一套支持皮肤/样式的 **Lazarus 控件库**:控件完全自绘(BGRABitmap),用 CSS-lite 文本主题(`.tycss`)统一驱动外观,在 Windows / Linux / macOS 上呈现像素级一致的界面。

> **English:** [README.en.md](README.en.md) ·  **更新日志:** [CHANGELOG.md](CHANGELOG.md)

```css
:root { --accent: #3B82F6; --radius: 6px; }
TyButton          { background: var(--surface); border-radius: var(--radius); }
TyButton.primary  { background: var(--accent); color: #FFFFFF; }
TyButton:hover    { background: lighten(--surface, 8%); }
TyButton:disabled { opacity: 0.5; }
```

## 特性

- **三层解耦架构** —— 控件层 / 样式引擎 / 绘图原语(`TTyPainter`),控件不写死任何颜色
- **CSS-lite 主题语言** —— `:root` 变量、类型/变体/状态选择器、`rgb/rgba/lighten/darken/alpha/mix` 颜色函数、`border` 简写、线性渐变、9-slice 贴图,以及双 `@mode`(亮/暗同文件)、`@import`、跟随系统亮暗 + 强调色
- **20+ 核心自绘控件** —— Button、Label、Edit、Memo、SpinEdit、CheckBox(三态)、RadioButton、Panel、GroupBox、ComboBox(可编辑 + 前缀自动补全)、ListBox、ScrollBar、ProgressBar、ToggleSwitch、TrackBar、PageControl(+TabSheet)、TabSet、Splitter、StatusBar、ToolBar、DateTimePicker、Calendar、TitleBar、CaptionButton
- **扩展控件族(140+ 个类型,全部自绘 · 跨平台)** —— **仪表/图表**:Gauge / Meter / Dial / AnalogClock / Sparkline / Rating / CircularProgress / 活动指示器 + `TTyChart`(折线/柱/饼);**Ribbon 与导航**:Ribbon(页/组/应用菜单/QAT/Gallery/Backstage);**富输入与选择器**:数值/货币/掩码/URL/Combo/滑块/计算器编辑、颜色/字体/文件 combo、颜色/HS 拾取器、`TTyValueListEditor`(属性检视);**容器与布局**:Bevel/Divider/PaintPanel、RadioGroup/CheckGroup、ScrollBox/ExPanel、GridPanel/RelativePanel、ToolBarEx/ControlBar/CoolBar、HeaderControl、ListGroupPanel;**列表/树/shell**:`TTyListView`(报表/图标/平铺 + 虚拟)、`TTyShellTreeView`/`TTyShellListView`/`TTyShellComboBox`/`TTyFilterComboBox`(文件系统后备);**菜单/效果**:MenuEx/ImagesMenu、矢量图元(Shape/Star/Arrow)、`TTyImageView`(平移/缩放 + BGRA 滤镜)、`TTyHtmlLabel`(行内 HTML 子集)、`tyControls.Transitions`(滑入/淡入过渡)
- **Ant Design 补齐控件族(14 个 · 全部自绘 · 20 主题可用 · 各有 API 文档)** —— **卡片与标记**:`TTyCard`(标题/内容/操作三段式,`hoverable` 只需一条 `TyCard:hover`)、`TTyTag`(可关闭标签胶囊,变体走 `StyleClass`)、`TTyBadge`(**独立**数字/圆点角标,`Target` 吸附任意控件);**反馈**:`TTyAlert`(**内联**警告条 info/success/warning/error)、`TTyNotification`(角落浮出、自动消失的 toast)、`TTyPopover`(**能放控件**的气泡浮层);**导航与流程**:`TTySegmented`(分段控制器)、`TTyPagination`(分页器)、`TTySteps`(向导步骤条,横竖两向)、`TTyBreadcrumb`(面包屑);**录入**:`TTyTransfer`(双列表穿梭框)、`TTyTreeSelect`(树形下拉)、`TTyCascader`(级联选择);**空状态**:`TTyEmpty`(插画 + 文案 + 可选操作)
- **数据网格 `TTyStringGrid`(三层:`TTyCustomGrid` / `TTyDrawGrid` / `TTyStringGrid`)** —— 冻结行列(四窗格)· 虚拟化(百万行只画可视窗口)· 稀疏单元格存储 · 二维光标 + 区域多选 · 内嵌滚动条 · 可变行高 · **编辑**(16 种内建编辑器:文本/数值/微调/滑动条/勾选框/下拉/日期/时间/颜色/评分/多行/掩码/密码/计算器/省略号按钮,逐格指定)· **显示**(文字/进度条/评分/图片/按钮/色块,与编辑正交)· 点列头排序(稳定归并)· **Excel 式列筛选**(搜索框 + 逐值计数 + 空白项)· 分组折叠 + **分组小计** · 单元格合并 · 汇总带(合计/均值/最小/最大/计数,只统计筛选后可见行)· **选区外框 + 填充柄**(复制/等差外推/循环重复)· 行号槽 · 隐藏列 · 剪贴板(Excel 格式)+ CSV 导入导出 · 列拖宽与拖动重排
- **虚拟树 `TTyTreeView`** —— VirtualTreeView 级别的虚拟树:数据按需加载(可承载百万级节点)、多列 + 可拖拽表头(调宽 / 重排 / 排序)、复选框 + 三态 + 单选节点、多选(Ctrl/Shift)+ 整行选择、可变行高、增量输入查找、单元格自绘、**内联编辑**(F2 / 双击)、**节点拖放**(重排 / 改变父子关系)
- **原生窗口 `TTyForm`** —— 无边框 + 自绘标题栏(可关联 `TTyTitleBar`):Windows 原生窗口缩放(`Resizable`)、最大化避让任务栏、系统圆角 + 原生投影(Windows 11 DWM / macOS,可经 CSS 关闭)。窗体的控件承载在内容容器 **`TTyFormSurface`**(名为 `Surface`,铺满窗体)上 —— **所有控件都放在它里面**,新建窗体模板已自带,详见[窗体结构](#窗体结构)
- **文本编辑能力** —— `TTyEdit` 单行(选区 / 剪贴板 / 水平滚动 / 词级导航)、`TTyMemo` 多行(2D 导航 / 跨行编辑 / 垂直滚动)、`TTySpinEdit` 数值微调;自绘编辑支持输入法(Qt6 / GTK2)
- **键盘助记符** —— `&` 加速键,Alt 下划线显示 + Alt+字母激活,覆盖菜单与各控件
- **原生控件协调 `TTyNativeStyler`** —— 让第三方 / LCL 原生控件跟随当前主题着色
- **对话框子系统** —— 自绘主题化模态对话框：`TyShowMessage` / `TyMessageDlg`(mtWarning/mtError/mtConfirmation/mtInformation + 全套 LCL 按钮集)全局函数 + `TTyDialog` 可派生基类(Enter/Esc + 右对齐按钮条) + `TTyMessage` 设计期组件；**输入类对话框**：`TyInputQuery`(单行文本) / `TyPasswordBox`(掩码密码) / `TyTextQuery`(可缩放多行) / `TySelectValue`(列表单选) / `TySelectDirectory`(文件夹选择器)；**拾取器**：`TySelectColor`(HSV/RGB/CMYK/Alpha 全双向取色器) / `TyFontDialog`(字体族/字号/样式/颜色 + 实时预览)；按钮标题与类型名称已国际化(resourcestring + zh_CN)；以及**非模态**查找/替换（`TTyFindDialog` / `TTyReplaceDialog`，对齐 LCL `TFindDialog`）和进度对话框（`TTyProgressDialog`）；**文件对话框**：`TTyOpenDialog` / `TTySaveDialog` + 图片版 + 预览版（右侧图片/文本预览 + `OnPreview` 自定义），三层 API 对齐 LCL
- **国际化(i18n)** —— `resourcestring` + 英 / 简体中文 `.po` 词条(主题诊断、设计期、演示);演示程序可运行时切换语言
- **状态切换动画** —— `TTyToggleSwitch` 旋钮在 ON/OFF 间滑动、`TTyButton` 悬停背景淡入淡出;可逐控件 `AnimationsEnabled` 开启,纯算法内核可步进、可测试
- **零配置默认皮肤 + 运行时热切换** —— 未加载主题或在设计器中拖放即有合理外观;`LoadTheme` 一行换肤,全部控件即时重绘
- **HiDPI** —— 所有长度按 PPI 缩放,矢量绘制天然清晰
- **设计期集成** —— 组件面板 "TyControls" 分页、StyleClass 属性下拉、PageControl 页管理组件编辑器、每控件只读 `About`
- **2800+ 个单元测试**,全套件内存零泄漏(heaptrc 验证)

## 快速开始

```pascal
uses tyControls.Controller, tyControls.Button;

// 加载主题(未显式指定 Controller 的控件自动使用全局控制器)
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建一个主要按钮
Btn := TTyButton.Create(Self);
Btn.Parent := Self;
Btn.Caption := '确定';
Btn.StyleClass := 'primary';   // 对应 .tycss 中的 TyButton.primary
```

> 注意:工程 `.lpr` 的 `uses` 必须以 `Interfaces` 开头(LCL 控件库的通用要求)。

完整步骤(安装包、第一个窗体、主题切换)见 **[docs/getting-started.md](docs/getting-started.md)**。

## 窗体结构

`TTyForm` 的控件承载在一个内容容器 **`TTyFormSurface`** 上 —— 每个窗体有且只有一个,名叫 `Surface`,铺满整个窗体。**把控件都放进它里面。**

- **新建窗体不用管**:File > New 的 *TyControls Form / Application* 模板已经带好 `Surface`,标题栏也在里面;在设计器里拖控件本来就落进它。
- **图形控件必须放进去**:`TTyLabel`、`TTyShape` 这类无窗口的图形控件是画在父控件身上的 —— 直接放在窗体上会被 `Surface` 挡住、**看不见**。你这么放时设计器会提示。
- **非可视组件仍留在窗体上**:样式控制器、定时器、对话框组件、图像列表、菜单等不受影响。
- **对话框(`TTyDialog`)没有 `Surface`**:它不可缩放,不需要。控件照常直接放在对话框上。

它为什么存在:无边框可缩放窗口画不到自己最外圈的像素,右/下边会留下一条没画上的细边;而子窗口能画到真正的边缘,所以窗体的主题背景改由 `Surface` 来画。在设计器里选中它,`Purpose` 属性里有完整说明。

**迁移现有窗体**:把原本直接放在窗体上的控件移进 `Surface` 即可(非可视组件不动)。参考 [examples/button/umain.lfm](examples/button/umain.lfm)。


## 文档

| 文档 | 内容 |
|---|---|
| [getting-started.md](docs/getting-started.md) | 安装、第一个窗体、主题加载与切换、HiDPI |
| [tycss-reference.md](docs/tycss-reference.md) | `.tycss` 样式语言权威参考:全部属性、函数、选择器、合并顺序 |
| [controls/](docs/controls/) | 单控件 API 说明(属性 / 事件 / 状态 / 主题变体 / 示例) |
| [CHANGELOG.md](CHANGELOG.md) | 版本更新日志 |
| [KNOWN_GAPS.md](docs/KNOWN_GAPS.md) | 已知限制与后续计划 |

> 较新的控件(`TTyTreeView`、`TTySplitter`、`TTyStatusBar`、`TTyToolBar`、`TTyDateTimePicker`、`TTyCalendar`、`TTyTabSet`)均已提供独立示例工程(见下方)与 [控件 API 文档](docs/controls/)。

## 示例

每个控件一个可独立构建的最小工程(窗体均为**设计式 `.lfm`**,非代码创建),外加综合 gallery 与 TreeView 专项 showcase:

| 示例 | 演示内容 |
|---|---|
| [examples/antdesign](examples/antdesign/) | **TyControls Pro**:仿 Ant Design Pro 的后台系统(侧边导航 + 6 个页面),默认 antdesign 皮肤,可运行时换肤 |
| [examples/grid](examples/grid/) | **TTyStringGrid**(6 个页签):冻结行列 / 百万行虚拟数据源 / 排序筛选分组 / 16 种编辑器 / 选择与剪贴板 / 事件钩子 |
| [examples/treeview](examples/treeview/) | **TTyTreeView showcase**:百万级虚拟树 / 多列 + 排序 / 复选 + 三态 + 单选 / 多选 + 整行 / 内联编辑 / 节点拖放 |
| [examples/demo](examples/demo/) | 综合 gallery:全部控件 + 多主题切换 + 自绘窗框 + 运行时切换语言 |
| [examples/dialogs](examples/dialogs/) | **全部 11 个自绘对话框**:消息 / 输入 / 密码 / 文本 / 选值 / 选路径 / 颜色 / 字体 / 查找 / 替换 / 进度(含模态与无模态) |
| [examples/edit](examples/edit/) | 文本输入、选区、剪贴板、词级导航、鼠标定位 |
| [examples/memo](examples/memo/) | 多行编辑、跨行编辑、2D 导航、内嵌垂直滚动条 |
| [examples/combobox](examples/combobox/) | Items / 选择 / OnChange、真实下拉弹层 |
| [examples/listbox](examples/listbox/) | 条目列表、键盘导航、内嵌自动滚动条 |
| [examples/spinedit](examples/spinedit/) | 数值微调、箭头 / 方向键 / 滚轮、Min/Max/Increment |
| [examples/tabcontrol](examples/tabcontrol/) | `TTyPageControl` + `TTyTabSheet`:多页签容器、切换 ActivePage、各页独立内容 |
| [examples/tabset](examples/tabset/) | `TTyTabSet`:纯标签条、`TabIndex` 切换、OnChange |
| [examples/calendar](examples/calendar/) | `TTyCalendar`:日期选择、日/月/年下钻、Min/MaxDate |
| [examples/datetimepicker](examples/datetimepicker/) | `TTyDateTimePicker`:日期下拉日历 + 时间分段微调 |
| [examples/splitter](examples/splitter/) | `TTySplitter`:面板间可拖拽分隔 |
| [examples/statusbar](examples/statusbar/) | `TTyStatusBar`:底部多分区状态栏 |
| [examples/toolbar](examples/toolbar/) | `TTyToolBar` + `TTyToolSeparator`:工具条与分隔符 |
| [examples/menu](examples/menu/) | `TTyMenuBar` + `TTyPopupMenu`:菜单栏 + 右键弹出菜单 |
| [examples/shapes](examples/shapes/) | `TTyShape` / `TTyStarShape` / `TTyArrow`:矢量形状、`StyleOverride` 改色、滑块调参、换主题 |
| [examples/listview](examples/listview/) | `TTyListView`:五视图、排序、多选 + 框选、复选框 + F2 改名、**按类型分组折叠**、10 万行虚拟模式 |
| [examples/theming](examples/theming/) | 自定义 `.tycss` 主题 + 运行时热切换 |

其余单控件示例(button / label / checkbox / radiobutton / panel / groupbox / scrollbar / progressbar / toggleswitch / trackbar)见 [examples/](examples/)。**所有示例窗体均为设计式 `.lfm`,采用 `TTyForm` + `TTyTitleBar` 自绘窗框,并在标题栏内置换肤下拉(运行时切换内置主题)。** 构建任意示例:`lazbuild examples/<名称>/<名称>_example.lpi`(demo 为 `demo.lpi`,treeview 为 `treeviewshowcase.lpi`)。

## 构建与测试

```bash
# 依赖:Lazarus 3.x+ / FPC 3.2.2+ / BGRABitmap(包名 BGRABitmapPack)

lazbuild tycontrols.lpk          # 运行期包
lazbuild tycontrols_dt.lpk       # 设计期包(IDE 安装用)

# 全量构建矩阵(两个包 + 全部示例 + 测试运行器)
bash scripts/build-matrix.sh

# 运行单元测试
lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain
```

## 目录结构

```
source/      运行期单元(样式引擎 / TTyPainter / 控件)
designtime/  设计期注册单元
themes/      主题源:根目录 auto/dark/light/green/system;builtin/ 为编译内置的结构皮肤源;palettes/ 为精选调色板
examples/    示例工程(每控件一个 + 综合 demo + treeview showcase)
tests/       FPCUnit 测试套件
docs/        文档
scripts/     构建与发布脚本
```

## 主题

全部内置主题都**编译进二进制**——`default`(`@mode` 亮/暗同文件的中性基底)、`system`(跟随操作系统亮暗 + 强调色),以及一整套**结构皮肤**(`office` / `win11` / `xp` / `classic` / `macos` / `material3` …),应用无需 `themes/` 文件夹即可按名切换(`TyBuiltinThemeNames` 列出全部)。这些皮肤的 `.tycss` 源同时保留在 `themes/builtin/`,是给使用者**照着改自己主题的参考**,运行时并不动态读取。仓库另提供 `green`(图片主题,仍是文件)与 `themes/palettes/` 精选调色板。所有主题共用同一套 `:root` 语义变量(`--accent` / `--surface` / `--on-surface` / `--border` / `--danger` / `--radius` …),换肤即换变量;`--accent` 可运行时覆盖(一套主题看任意品牌色);`LoadTheme` / `ThemeName` 热切换,全部控件即时重绘。

## 启用翻译

TyControls 自身的界面字符串(对话框按钮、标签、ThemeLint 诊断信息等)使用独立于宿主应用的
resourcestring 目录。LCL 的 `SetDefaultLang('', LangDir)` 只会自动加载
`languages/<exe名>.<lang>.po`,不会加载控件库自身的目录 —— 因此无论应用选了哪种界面语言,这些字符串
都会停留在英文 msgid 上。需要在 `SetDefaultLang` 之后、创建任何窗体之前,显式加载控件库的目录:

```pascal
uses ..., LCLTranslator;
...
SetDefaultLang('', LangDir);
TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');
Application.CreateForm(TMainForm, MainForm);
```

请将目录部署为 `languages/tycontrols.<lang>.po`(本仓库构建产物)—— 一个**不含点号**的文件主名 ——
与你应用自己的 `.po` 文件一起放在可执行文件自身的 `languages/` 目录下。**不要**命名为
`tycontrols.strconsts.<lang>.po`:LCL 的 `FindLocaleFileName` 会对传入的文件主名调用
`ChangeFileExt`,它会把 `strconsts` 前的那个点当成扩展名分隔符并将其剥离,导致无论实际部署了什么文件,
查找的都会是 `tycontrols.<lang>.po`。把第三个参数(`LocaleFileName`)传成 `'tycontrols'`
可以让文件查找保持无点号,而第四个参数(`LocaleUnitName`)则传入真实的带点单元名
`tyControls.StrConsts`,以保证 resourcestring 标识符仍能正确匹配。完整示例见
[examples/demo](examples/demo/)(`demo.lpr` + `examples/demo/languages/tycontrols.zh_CN.po`)。

若要在非 zh_CN 环境的机器上强制输出中文(例如测试用途),需显式指定语言而非依赖自动检测 ——
`SetDefaultLang('')` 与 `Lang` 参数为空的 `TranslateUnitResourceStringsEx` 都会自动检测操作系统区域
(或读取已支持的 `--lang=` 命令行参数),此时应直接传入 `'zh_CN'`:

```pascal
SetDefaultLang('zh_CN', LangDir);
TranslateUnitResourceStringsEx('zh_CN', LangDir, 'tycontrols', 'tyControls.StrConsts');
```

## 许可

TyControls 采用**修改版 LGPL**(与 FPC RTL / LCL / BGRABitmap 同款):允许将本库静态链接进闭源商业应用分发;若修改库本身的源码,修改部分需以同样许可开放。

完整条款见 [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt)(例外条款)与 [COPYING.LGPL.txt](COPYING.LGPL.txt)(LGPL 正文)。
