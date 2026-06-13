# TyControls 上手指南

面向第一次使用 TyControls 的 Lazarus 开发者。

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
| `themes/showcase.tycss` | 门面展示主题,突出库的外观辨识度 |

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
LocalCtrl.LoadTheme('themes/showcase.tycss');

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
| `tabcontrol/` | `TTyTabControl` 标签页切换、AddTab、键盘 ←/→ 导航、溢出表头滚动、拖拽重排序、设计期 `Tabs` 集合 | `lazbuild examples/tabcontrol/tabcontrol_example.lpi` |
| `spinedit/` | `TTySpinEdit` 数值微调、上/下箭头、方向键/滚轮步进、Min/Max/Increment | `lazbuild examples/spinedit/spinedit_example.lpi` |
| `memo/` | `TTyMemo` 多行文本编辑、回车换行、跨行退格/删除、导航、垂直滚动条/滚轮 | `lazbuild examples/memo/memo_example.lpi` |
| `formchrome/` | `TTyFormChrome` 无边框自绘窗框窗口 | `lazbuild examples/formchrome/formchrome_example.lpi` |
| `theming/` | 自定义 `.tycss` 主题 + 运行时热切换 | `lazbuild examples/theming/theming_example.lpi` |
| `demo/` | 综合示例:所有控件 + 三主题运行时热切换 + 自绘窗框 | `lazbuild examples/demo/demo.lpi` |

构建示例时需确保已安装 `tycontrols.lpk`(方案 A),或在 `lazbuild` 命令行追加 `--add-package tycontrols`。

---

## 6. HiDPI

TyControls 的所有长度令牌(圆角、边框宽度、内边距等)在绘制时按窗体 PPI 自动缩放。绘图后端 BGRABitmap 采用矢量路径渲染,在高分屏上天然清晰,无需应用层做任何额外处理。

---

## 7. 已知限制

完整列表见 [docs/KNOWN_GAPS.md](KNOWN_GAPS.md)。以下是最需要提前了解的几项:

1. **`TTyMemo` 编辑能力裁剪** — 多行编辑器提供可靠的逐码点编辑内核(回车换行、跨行退格/删除、二维方向键 + Home/End 导航、垂直滚动条/滚轮),但**有意推迟**以下能力到未来 Tier-2:无选区、无区段剪贴板、无自动换行、无横向滚动(超长行被右边裁剪)、无撤销/重做、无词级跳转(`Ctrl`/`Cmd` 仅把 `Home`/`End` 重定向到文档首尾)、无光标闪烁。注意:这些是 `TTyMemo` 的限制;单行的 `TTyEdit` **已支持**选区、剪贴板、水平滚动与词级导航。

2. **窗框 Tier-2 缺口** — `TTyFormChrome` 采用跨平台手动实现,Windows Aero Snap 贴边分屏、Windows DWM 原生投影阴影、macOS 原生红绿灯按钮等原生窗口行为尚未实现。macOS 原生阴影与跨屏 DPI 重缩放已在 v1.1 解决。

3. **设计期渲染** — 拖放到窗体上的 TyControls 控件在 Lazarus 设计器中会以**内置默认皮肤**
   呈现(零配置可见)。注意:完整的自绘**窗框**(`TTyFormChrome`)仍只在运行期呈现,
   设计器显示的是原生(未换肤)窗口框架——这是此类皮肤库的通常行为。
