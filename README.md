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
- **20+ 自绘控件** —— Button、Label、Edit、Memo、SpinEdit、CheckBox、RadioButton、Panel、GroupBox、ComboBox、ListBox、ScrollBar、ProgressBar、ToggleSwitch、TrackBar、PageControl(+TabSheet)、Splitter、StatusBar、ToolBar、DateTimePicker、Calendar、TitleBar、CaptionButton
- **虚拟树 `TTyTreeView`** —— VirtualTreeView 级别的虚拟树:数据按需加载(可承载百万级节点)、多列 + 可拖拽表头(调宽 / 重排 / 排序)、复选框 + 三态 + 单选节点、多选(Ctrl/Shift)+ 整行选择、可变行高、增量输入查找、单元格自绘、**内联编辑**(F2 / 双击)、**节点拖放**(重排 / 改变父子关系)
- **原生窗口 `TTyForm`** —— 无边框 + 自绘标题栏(可关联 `TTyTitleBar`):Windows 原生窗口缩放(`Resizable`)、最大化避让任务栏、系统圆角 + 原生投影(Windows 11 DWM / macOS,可经 CSS 关闭)
- **文本编辑能力** —— `TTyEdit` 单行(选区 / 剪贴板 / 水平滚动 / 词级导航)、`TTyMemo` 多行(2D 导航 / 跨行编辑 / 垂直滚动)、`TTySpinEdit` 数值微调;自绘编辑支持输入法(Qt6 / GTK2)
- **键盘助记符** —— `&` 加速键,Alt 下划线显示 + Alt+字母激活,覆盖菜单与各控件
- **原生控件协调 `TTyNativeStyler`** —— 让第三方 / LCL 原生控件跟随当前主题着色
- **国际化(i18n)** —— `resourcestring` + 英 / 简体中文 `.po` 词条(主题诊断、设计期、演示);演示程序可运行时切换语言
- **状态切换动画** —— `TTyToggleSwitch` 旋钮在 ON/OFF 间滑动、`TTyButton` 悬停背景淡入淡出;可逐控件 `AnimationsEnabled` 开启,纯算法内核可步进、可测试
- **零配置默认皮肤 + 运行时热切换** —— 未加载主题或在设计器中拖放即有合理外观;`LoadTheme` 一行换肤,全部控件即时重绘
- **HiDPI** —— 所有长度按 PPI 缩放,矢量绘制天然清晰
- **设计期集成** —— 组件面板 "TyControls" 分页、StyleClass 属性下拉、PageControl 页管理组件编辑器、每控件只读 `About`
- **1500+ 个单元测试**,全套件内存零泄漏(heaptrc 验证)

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

## 文档

| 文档 | 内容 |
|---|---|
| [getting-started.md](docs/getting-started.md) | 安装、第一个窗体、主题加载与切换、HiDPI |
| [tycss-reference.md](docs/tycss-reference.md) | `.tycss` 样式语言权威参考:全部属性、函数、选择器、合并顺序 |
| [controls/](docs/controls/) | 单控件 API 说明(属性 / 事件 / 状态 / 主题变体 / 示例) |
| [CHANGELOG.md](CHANGELOG.md) | 版本更新日志 |
| [KNOWN_GAPS.md](docs/KNOWN_GAPS.md) | 已知限制与后续计划 |

> 较新的控件(`TTyTreeView`、`TTySplitter`、`TTyStatusBar`、`TTyToolBar`、`TTyDateTimePicker`、`TTyCalendar`)暂以示例工程演示,独立 API 文档待补 —— 见下方示例与 [CHANGELOG.md](CHANGELOG.md)。

## 示例

每个控件一个可独立构建的最小工程(纯代码建 UI),外加综合 gallery 与 TreeView 专项 showcase:

| 示例 | 演示内容 |
|---|---|
| [examples/treeview](examples/treeview/) | **TTyTreeView showcase**:百万级虚拟树 / 多列 + 排序 / 复选 + 三态 + 单选 / 多选 + 整行 / 内联编辑 / 节点拖放 |
| [examples/demo](examples/demo/) | 综合 gallery:全部控件 + 多主题切换 + 自绘窗框 + 运行时切换语言 |
| [examples/edit](examples/edit/) | 文本输入、选区、剪贴板、词级导航、鼠标定位 |
| [examples/memo](examples/memo/) | 多行编辑、跨行编辑、2D 导航、内嵌垂直滚动条 |
| [examples/combobox](examples/combobox/) | Items / 选择 / OnChange、真实下拉弹层 |
| [examples/listbox](examples/listbox/) | 条目列表、键盘导航、内嵌自动滚动条 |
| [examples/spinedit](examples/spinedit/) | 数值微调、箭头 / 方向键 / 滚轮、Min/Max/Increment |
| [examples/tabcontrol](examples/tabcontrol/) | 标签页切换、可关闭页签、键盘导航、溢出滚动、拖拽重排 |
| [examples/formchrome](examples/formchrome/) | 无边框自绘窗框窗口 |
| [examples/theming](examples/theming/) | 自定义 `.tycss` 主题 + 运行时热切换 |

其余每控件示例(button / label / checkbox / radiobutton / panel / groupbox / scrollbar / progressbar / toggleswitch / trackbar)见 [examples/](examples/)。构建任意示例:`lazbuild examples/<名称>/<名称>_example.lpi`(demo 为 `demo.lpi`,treeview 为 `treeviewshowcase.lpi`)。

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
themes/      主题文件(light / dark / green / showcase / system …)
examples/    示例工程(每控件一个 + 综合 demo + treeview showcase)
tests/       FPCUnit 测试套件
docs/        文档
scripts/     构建与发布脚本
```

## 主题

仓库 `themes/` 提供 `light` / `dark` / `green` / `showcase` 等 `.tycss`,另有一组**编译内置**的精选双模式主题(`@mode` 亮/暗同文件)与 `system`(跟随操作系统亮暗 + 强调色)。所有主题共用同一套 `:root` 语义变量(`--accent` / `--surface` / `--on-surface` / `--border` / `--danger` / `--radius` …),换肤即换变量;`LoadTheme` 运行时热切换,全部控件即时重绘。

## 许可

TyControls 采用**修改版 LGPL**(与 FPC RTL / LCL / BGRABitmap 同款):允许将本库静态链接进闭源商业应用分发;若修改库本身的源码,修改部分需以同样许可开放。

完整条款见 [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt)(例外条款)与 [COPYING.LGPL.txt](COPYING.LGPL.txt)(LGPL 正文)。
