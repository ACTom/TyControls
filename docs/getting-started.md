# TyControls 上手指南

面向第一次使用 TyControls 的 Lazarus 开发者。

> English: [getting-started.en.md](getting-started.en.md)

---

## 1. 简介

TyControls 是一套面向 Lazarus 的**皮肤控件库**,让你的应用在 Windows、Linux、macOS 上呈现一致的自定义外观,而不依赖任何平台原生控件样式。

**三层架构一句话:**

```
控件层(TTyButton / TTyEdit / …)
  → 样式引擎(TTyStyleController:解析 .tycss,返回属性集)
    → 绘图原语(TTyPainter:封装 BGRABitmap,矢量绘制)
```

三层严格解耦:控件不知道颜色,引擎不知道怎么画,Painter 不知道有控件。

**平台与依赖:**

| 项目 | 要求 |
|---|---|
| Lazarus | 3.x+ |
| FPC | 3.2.2+ |
| 第三方依赖 | BGRABitmap(仅运行期) |
| 目标平台 | Windows / Linux / macOS |

---

## 2. 安装

### 方案 A — IDE 安装(推荐)

1. **安装 BGRABitmapPack**
   - 在 Lazarus IDE 中打开 **包 → 在线包管理器(OPM)**,搜索 `BGRABitmap`,点击安装并重建 IDE;
   - 或者从源码手动安装:`包 → 打开包文件 (.lpk)`,选择 BGRABitmapPack 的 `.lpk`,编译后安装。

2. **编译运行期包**
   打开 `tycontrols.lpk`,点击**编译**。

3. **安装设计期包**
   打开 `tycontrols_dt.lpk`,点击**安装**,IDE 将自动重建。
   重建完成后,组件面板出现 **"TyControls"** 分页,所有控件可直接拖放使用。

> `tycontrols.lpk` 依赖:`BGRABitmapPack`、`LCL`
> `tycontrols_dt.lpk` 依赖:`tycontrols`、`IDEIntf`

### 方案 B — 纯源码路径(无需安装包)

在你的工程 `.lpi` 的 `OtherUnitFiles` 中加入 TyControls 的 `source/` 目录,示例工程就采用这种方式:

```xml
<SearchPaths>
  <OtherUnitFiles Value=".;../../source"/>
  <UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>
</SearchPaths>
```

同时在 `RequiredPackages` 中只列 `LCL` 和 `BGRABitmapPack`(无需 `tycontrols` 包条目)。

---

## 3. 第一个窗体

下面是一个可编译的最小示例,展示如何纯代码创建一个带主题的 `TTyButton`。
完整代码见 `examples/button/`。

### 主程序文件(`.lpr`)

`.lpr` 必须在 `uses` 中包含 `Interfaces`,否则在非 Windows 平台上无法初始化 LCL widgetset:

```pascal
program button_example;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   // 必须:初始化 LCL widgetset
  Forms, umain;

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
```

### 窗体单元

```pascal
unit umain;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找 themes/,兼容 lazbuild 的 lib/<cpu>-<os>/ 输出路径 }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Btn: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := '我的第一个 TyControls 窗体';
  SetBounds(0, 0, 320, 200);
  Position := poScreenCenter;

  // 加载主题到全局控制器
  // 未显式指定 Controller 属性的控件自动注册到 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 创建默认按钮
  Btn := TTyButton.Create(Self);
  Btn.Parent := Self;
  Btn.SetBounds(24, 24, 160, 32);
  Btn.Caption := '默认按钮';

  // 创建主要变体按钮(对应 .tycss 中的 TyButton.primary)
  Btn := TTyButton.Create(Self);
  Btn.Parent := Self;
  Btn.SetBounds(24, 64, 160, 32);
  Btn.Caption := '主要按钮';
  Btn.StyleClass := 'primary';
end;

end.
```

**关键点说明:**

- `TyDefaultController` 是全局单例,由库自动创建。没有手动设置 `Controller` 属性的控件会自动注册到它。
- `LoadTheme(AFileName)` 从文件加载 `.tycss` 主题,并自动通知所有已注册控件重绘。
- `StyleClass` 对应 `.tycss` 中的变体名(如 `'primary'` 匹配 `TyButton.primary { … }`)。

---

## 4. 主题

### 内置默认皮肤(零配置)

TyControls 内置了一套**默认皮肤**(浅色,与 `themes/light.tycss` 一致),已编译进库中。
因此即使你**没有加载任何主题**,控件也会以合理的默认外观显示:

- 未显式设置 `Controller`、且从未调用 `LoadTheme` 的控件 —— 显示内置默认皮肤;
- 在 Lazarus **窗体设计器**中拖放的控件 —— 同样以内置默认皮肤呈现(无需运行程序)。

加载主题会在内置皮肤**之上按 typeKey 覆盖**:

- 加载**完整主题**(`light`/`dark`/`showcase` 定义了所有控件)—— 完全替换内置外观;
- 加载**部分主题**(例如只重定义 `TyButton`,或只改 `:root` 变量后重写若干控件)——
  你写了规则的控件用你的样式,**未提及的控件仍保留内置默认皮肤**,不会变成空白。

> 抑制粒度是"按 typeKey":只要主题为某个 typeKey 写了任意一条规则,该 typeKey 的内置
> 默认就被整体让位给主题(避免内置属性意外渗漏)。

### 内置主题

| 文件 | 说明 |
|---|---|
| `themes/light.tycss` | 浅色主题(白底,蓝色强调色) |
| `themes/dark.tycss` | 深色主题 |
| `themes/builtin/showcase.tycss` | 门面展示主题,突出库的外观辨识度 |

### 加载主题

```pascal
// 全局切换:影响所有使用 TyDefaultController 的控件
TyDefaultController.LoadTheme('themes/dark.tycss');

// 从内存中的 CSS 字符串加载(适合嵌入资源)
TyDefaultController.LoadThemeCss('TyButton { background: #222; color: #FFF; }');
```

### 运行时热切换

调用 `LoadTheme` 或 `LoadThemeCss` 后,Controller 自动调用 `Changed`,所有已注册控件立即 `Invalidate` 并以新主题重绘。无需手动刷新。

### 每窗体局部 Controller

如果某个窗体需要独立主题(不随全局切换),可以在该窗体上放置一个 `TTyStyleController` 组件,然后把该窗体上的控件的 `Controller` 属性指向这个实例:

```pascal
// 代码方式
LocalCtrl := TTyStyleController.Create(Self);
LocalCtrl.LoadTheme('themes/builtin/showcase.tycss');

MyButton.Controller := LocalCtrl;
MyEdit.Controller   := LocalCtrl;
```

在 IDE 设计器中同样可以直接在对象树中拖放 `TTyStyleController` 并通过属性检查器连接。

### 主题文件格式

`.tycss` 是一套 CSS-lite DSL。变量在 `:root` 块中定义,规则按`类型[.变体][:状态]`格式书写:

```css
:root {
  --accent:     #3B82F6;
  --surface:    #FFFFFF;
  --on-surface: #1F2937;
  --border:     #D1D5DB;
  --radius:     6px;
}

TyButton {
  background:    var(--surface);
  color:         var(--on-surface);
  border-color:  var(--border);
  border-radius: var(--radius);
}
TyButton.primary          { background: var(--accent); color: #FFFFFF; }
TyButton.primary:hover    { background: lighten(--accent, 8%); }
TyButton:disabled         { opacity: 0.5; }
```

完整语法参见 [docs/tycss-reference.md](tycss-reference.md)。

---

## 5. 示例一览

所有示例均位于 `examples/` 目录,使用纯代码建 UI(无 `.lfm`)。

| 目录 | 说明 | 构建命令 |
|---|---|---|
| `button/` | `TTyButton` 的默认/primary/danger 变体与禁用态 | `lazbuild examples/button/button_example.lpi` |
| `label/` | `TTyLabel` 文字颜色与变体 | `lazbuild examples/label/label_example.lpi` |
| `edit/` | `TTyEdit` 文本输入、选区、剪贴板、词级导航(Ctrl/Alt+←/→)、焦点态 | `lazbuild examples/edit/edit_example.lpi` |
| `checkbox/` | `TTyCheckBox` 勾选与禁用 | `lazbuild examples/checkbox/checkbox_example.lpi` |
| `radiobutton/` | `TTyRadioButton` 单选组 | `lazbuild examples/radiobutton/radiobutton_example.lpi` |
| `panel/` | `TTyPanel` 容器控件与标题(含嵌套面板) | `lazbuild examples/panel/panel_example.lpi` |
| `combobox/` | `TTyComboBox` Items/选择/OnChange、真实下拉弹层 | `lazbuild examples/combobox/combobox_example.lpi` |
| `scrollbar/` | `TTyScrollBar` 垂直/水平、Position/OnChange | `lazbuild examples/scrollbar/scrollbar_example.lpi` |
| `listbox/` | `TTyListBox` 条目列表、键盘导航、内嵌滚动条 | `lazbuild examples/listbox/listbox_example.lpi` |
| `progressbar/` | `TTyProgressBar` 进度更新 | `lazbuild examples/progressbar/progressbar_example.lpi` |
| `toggleswitch/` | `TTyToggleSwitch` 开关切换、ON/OFF 主题 | `lazbuild examples/toggleswitch/toggleswitch_example.lpi` |
| `trackbar/` | `TTyTrackBar` 拖动滑块、方向键步进 | `lazbuild examples/trackbar/trackbar_example.lpi` |
| `groupbox/` | `TTyGroupBox` 分组容器、RadioButton 分组 | `lazbuild examples/groupbox/groupbox_example.lpi` |
| `tabcontrol/` | `TTyPageControl` + `TTyTabSheet` 多页容器：切换 `ActivePage`、键盘 ←/→ 导航、溢出表头滚动、拖拽重排序 | `lazbuild examples/tabcontrol/tabcontrol_example.lpi` |
| `spinedit/` | `TTySpinEdit` 数值微调、上/下箭头、方向键/滚轮步进、Min/Max/Increment | `lazbuild examples/spinedit/spinedit_example.lpi` |
| `memo/` | `TTyMemo` 多行文本编辑、回车换行、跨行退格/删除、导航、垂直滚动条/滚轮 | `lazbuild examples/memo/memo_example.lpi` |
| `formchrome/` | `TTyForm` 无边框自绘窗框窗口（继承 `TTyForm`） | `lazbuild examples/formchrome/formchrome_example.lpi` |
| `theming/` | 自定义 `.tycss` 主题 + 运行时热切换 | `lazbuild examples/theming/theming_example.lpi` |
| `demo/` | 综合示例:所有控件 + 三主题运行时热切换 + 自绘窗框 | `lazbuild examples/demo/demo.lpi` |

构建示例时需确保已安装 `tycontrols.lpk`(方案 A),或在 `lazbuild` 命令行追加 `--add-package tycontrols`。

---

## 6. HiDPI

TyControls 的所有长度令牌(圆角、边框宽度、内边距等)在绘制时按窗体 PPI 自动缩放。绘图后端 BGRABitmap 采用矢量路径渲染,在高分屏上天然清晰,无需应用层做任何额外处理。

---

## 7. 已知限制

以下是最需要提前了解的几项(双向文本与右到左布局另见 [docs/rtl.md](rtl.md)):

1. **`TTyMemo` 的右到左只做了一半** — 多行编辑器的编辑能力已经补齐:选区、区段剪贴板(`Ctrl`/`Cmd` + `A`/`C`/`X`/`V`)、`WordWrap`、横向滚动条、撤销/重做、按词跳转与按词删除、光标闪烁、`ReadOnly` / `MaxLength` —— 本节旧文把这七项全列成"有意推迟到 Tier-2",那是写在实现落地之前的,早就不成立了。**真正还缺的是右到左的镜像那一半:** 双向文本的**排版**是对的(走 UAX #9,阿拉伯语/希伯来语的词序与连写都正确),光标与点击定位也已经是视觉序的;但控件自己的滚动条、边距、对齐不翻转,所以 `BidiMode` 依然**不 published** —— 一个只兑现一半的属性不发布,是这个库的硬规则。另有两个必须先知道的后果:跨书写方向的选区会画成多条选区带,`Home` / `End` 仍是逻辑端点。详见 [docs/controls/memo.md](controls/memo.md) 与 [docs/rtl.md](rtl.md)。

2. **窗框 Tier-2 缺口** — 自绘窗框现通过继承 `TTyForm = class(TForm)` 获得（旧控制器 `TTyFormChrome` 已移除）。其跨平台手动实现下,macOS 原生红绿灯按钮等原生窗口行为尚未实现;Windows Aero Snap(贴边平铺 + 拖到顶端最大化)、DWM 原生投影阴影与 macOS 原生阴影已实现。详见 [docs/controls/ttyform.md](controls/ttyform.md)。

3. **跨屏 DPI:能来回还原,但不是逐像素相等** — 旧文这一条写的是"跨屏 DPI 重缩放已在 v1.1 解决",那句话对**窗框**成立、对**控件**不成立,一直到本轮才补上:六个控件类把尺寸下限写成**设备像素**,而 LCL 在同一份 `Constraints` 上再缩放一次,于是过一次屏就乘两遍(`TTyButton` 29 → 175 → 70),回程按比例缩也解不开。现在下限在**当前 PPI 上重新测量**,一趟 96 → 240 → 96 能回到原值。两条剩余的容差,是权衡后接受的、不是缺陷:

   - **正好卡在下限上的控件会棘轮式长大**。LCL 按比例缩放 bounds 与 `Constraints`,而"按字形量出来的下限"不是 PPI 的严格线性函数,所以没有余量的控件在高 PPI 下会(正确地)变大,回程的比例缩放无从得知该撤销多少。实测约 4~10 px,**一趟之后收敛**,不发散。
   - **刚过完一次屏时可能比下限低约 1 px**(`Round` 的半偶入),下一次任意 `SetBounds` 就会纠正。

   还有一条在本库**下面**、库自己看不见的坑值得提前知道:LCL 的 `DoScaleFontPPI` 会用 `Screen.PixelsPerInch` 把未设置的 `Font.Height` 替换成一个具体值,一次且不可逆。主显示器不是 96 DPI 的机器上,第一次跨屏会把所有字号永久按比例改一遍 —— 这发生在本库任何代码之前。规避办法:给窗体显式设置字号。

   跨屏要真的生效还需要程序清单声明 PerMonitorV2(`.lpi` 里 `<DpiAware Value="True/PM_V2"/>`,并确保工程有 `{$R *.res}`);本仓库的 `demo` 与 `containers` 两个示例已经声明。

4. **设计期渲染** — 拖放到窗体上的 TyControls 控件在 Lazarus 设计器中会以**内置默认皮肤**
   呈现(零配置可见)。`TTyForm` 的**布局**在设计器中是 WYSIWYG 的(标题栏占顶部条带、
   内容面板填充其下,拖入内容面板的控件就位于条带下方);唯一的设计期缺口是标题栏的自绘
   **皮肤**未换肤——设计器没有运行期主题上下文,标题栏显示内置默认外观而非你加载的 `.tycss`
   主题,与全库其它控件一致,这不是缺陷。
