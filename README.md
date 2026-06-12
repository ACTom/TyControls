# TyControls

一套支持皮肤/样式的 **Lazarus 控件库**:控件完全自绘(BGRABitmap),用 CSS-lite 文本主题(`.tycss`)统一驱动外观,在 Windows / Linux / macOS 上呈现像素级一致的界面。

```css
:root { --accent: #3B82F6; --radius: 6px; }
TyButton          { background: var(--surface); border-radius: var(--radius); }
TyButton.primary  { background: var(--accent); color: #FFFFFF; }
TyButton:hover    { background: lighten(--surface, 8%); }
TyButton:disabled { opacity: 0.5; }
```

## 特性

- **三层解耦架构** —— 控件层 / 样式引擎 / 绘图原语(`TTyPainter`),控件不写死任何颜色
- **CSS-lite 主题语言** —— `:root` 变量、类型/变体/状态选择器、`lighten/darken/alpha/mix` 颜色函数、线性渐变、9-slice 贴图
- **10 个自绘控件** —— Button、Label、Edit、CheckBox、RadioButton、Panel、ComboBox、ScrollBar、TitleBar、CaptionButton
- **自绘窗框** —— `TTyFormChrome` 一个组件接管无边框窗口:标题栏、拖动、8 向缩放、最小/最大化/关闭、双击最大化(避让任务栏)
- **运行时热切换主题** —— `LoadTheme` 一行代码,全部控件即时重绘
- **HiDPI** —— 所有长度按 PPI 缩放,矢量绘制天然清晰
- **设计期集成** —— 组件面板 "TyControls" 分页,StyleClass 属性下拉
- **148 个单元测试**,全套件内存零泄漏(heaptrc 验证)

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
| [controls/](docs/controls/) | 每控件 API 说明(12 篇:属性 / 事件 / 状态 / 主题变体 / 示例) |
| [KNOWN_GAPS.md](docs/KNOWN_GAPS.md) | v1 已知限制与 Tier-2 计划 |

控件 API 速查:[Button](docs/controls/button.md) ·
[Label](docs/controls/label.md) ·
[Edit](docs/controls/edit.md) ·
[CheckBox](docs/controls/checkbox.md) ·
[RadioButton](docs/controls/radiobutton.md) ·
[Panel](docs/controls/panel.md) ·
[ComboBox](docs/controls/combobox.md) ·
[ScrollBar](docs/controls/scrollbar.md) ·
[TitleBar](docs/controls/titlebar.md) ·
[CaptionButton](docs/controls/captionbutton.md) ·
[FormChrome](docs/controls/formchrome.md) ·
[StyleController](docs/controls/stylecontroller.md)

## 示例

每个控件一个可独立构建的最小工程(纯代码建 UI),外加一个综合 gallery:

| 示例 | 演示内容 |
|---|---|
| [examples/button](examples/button/) | 变体(primary/danger)、禁用态、OnClick |
| [examples/label](examples/label/) | 主题文字颜色、禁用态 |
| [examples/edit](examples/edit/) | 文本输入(UTF-8 安全退格)、焦点态 |
| [examples/checkbox](examples/checkbox/) | 勾选切换、禁用态 |
| [examples/radiobutton](examples/radiobutton/) | 按 Parent 分组的单选互斥 |
| [examples/panel](examples/panel/) | 容器承载子控件、嵌套面板 |
| [examples/combobox](examples/combobox/) | Items/选择/OnChange(v1 点击循环切换) |
| [examples/scrollbar](examples/scrollbar/) | 垂直/水平滚动条、Position/OnChange |
| [examples/formchrome](examples/formchrome/) | 无边框自绘窗框窗口 |
| [examples/theming](examples/theming/) | 自定义 `.tycss` 主题 + 运行时热切换 |
| [examples/demo](examples/demo/) | 综合 gallery:全部控件 + 三主题切换 + 自绘窗框 |

构建任意示例:`lazbuild examples/<名称>/<名称>_example.lpi`(demo 为 `demo.lpi`)。

## 构建与测试

```bash
# 依赖:Lazarus 3.x+ / FPC 3.2.2+ / BGRABitmap(包名 BGRABitmapPack)

lazbuild tycontrols.lpk          # 运行期包
lazbuild tycontrols_dt.lpk       # 设计期包(IDE 安装用)

# 全量构建矩阵(两个包 + 全部示例 + 测试运行器)
bash scripts/build-matrix.sh

# 运行单元测试(148 个)
lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain
```

## 目录结构

```
source/      运行期单元(样式引擎 / TTyPainter / 控件)
designtime/  设计期注册单元
themes/      内置主题:light.tycss / dark.tycss / showcase.tycss
examples/    示例工程(每控件一个 + 综合 demo)
tests/       FPCUnit 测试套件
docs/        中文文档
scripts/     构建脚本
```

## 内置主题

- **light** —— 浅色,中性灰 + 蓝色强调
- **dark** —— 深色,同一套语义令牌派生
- **showcase** —— 渐变门面主题,展示 `linear-gradient` 与阴影能力

三套主题共用同一套 `:root` 语义变量(`--accent` / `--surface` / `--on-surface` / `--border` / `--danger` / `--radius`),换肤即换变量。

## 许可

TyControls 采用**修改版 LGPL**(与 FPC RTL / LCL / BGRABitmap 同款):允许将本库静态链接进闭源商业应用分发;若修改库本身的源码,修改部分需以同样许可开放。

完整条款见 [COPYING.modifiedLGPL.txt](COPYING.modifiedLGPL.txt)(例外条款)与 [COPYING.LGPL.txt](COPYING.LGPL.txt)(LGPL 正文)。
