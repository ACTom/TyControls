# 对话框子系统（Dialogs）

## 1. 概述

TyControls 对话框子系统提供一套**自绘、主题化、模态**的对话框解决方案，单元为 `tyControls.Dialogs`。

核心设计原则：

- **自绘**：对话框继承自 `TTyDialog`（`TTyForm` 的子类），外观完全由 `.tycss` 主题驱动，无系统边框。
- **主题化**：背景色、按钮样式、标题高度等均取自 `TTyStyleController` 令牌，不硬编码任何颜色。
- **模态**：所有对话框以 `ShowModal` 方式调用，返回 `TModalResult`。
- **双层 API**：`Ty`-前缀全局函数是**主要 API**（仿照 LCL `MessageDlg`/`ShowMessage`，一行调用）；`TTyMessage` 非可视组件是**设计期辅助**（在对象检视器中配置后一行 `Execute`）。

---

## 2. 单元与安装

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Dialogs` |
| 组件面板页 | **TyControls Dialogs** |
| 组件 | `TTyMessage`（非可视） |

```pascal
uses tyControls.Dialogs;
```

> **注意**：`TyMessage` 全局函数（`TyShowMessage`、`TyMessageDlg` 等）仅需 `uses tyControls.Dialogs`，无需在窗体上放置任何组件。`TTyMessage` 组件是可选的设计期辅助。

---

## 3. TTyDialog — 自定义对话框基类

`TTyDialog` 是所有自绘模态对话框的**基类**，本身也可在运行期直接实例化以构建简单的自定义对话框。

### 3.1 特性

- 出生无边框（继承自 `TTyForm`，`BorderStyle = bsNone`）
- 标题栏仅含**关闭按钮**（`BorderIcons = [biSystemMenu]`）
- 不可缩放（`Resizable = False`）
- 居中于主窗体（`Position = poMainFormCenter`）
- 内置 Enter / Esc 键响应：Enter 触发默认按钮，Esc 触发取消按钮

### 3.2 按钮栏

底部有一个 44px 高的透明按钮条（`TTyPanel`，`Align = alBottom`）。调用 `AddButton` 后，按钮从右向左自动排列（索引 0 为最右侧的主按钮）。

```pascal
function AddButton(
  const ACaption: string;
  AResult: TModalResult;
  ADefault: Boolean = False;
  ACancel:  Boolean = False
): TTyButton;
```

- `ADefault = True`：Enter 键触发此按钮
- `ACancel = True`：Esc 键（或 `CancelDialog`）触发此按钮

### 3.3 内容区与自动尺寸

```pascal
function ContentRect: TRect;
// 返回内容区矩形（标题栏以下、按钮条以上）

procedure AutoSizeToContent(AContentW, AContentH: Integer);
// 依据内容尺寸自动调整对话框大小，同时保证按钮条能容纳全部按钮
```

### 3.4 派生自定义对话框

```pascal
type
  TMyConfirmDlg = class(TTyDialog)
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
  end;

constructor TMyConfirmDlg.CreateNew(AOwner: TComponent; Num: Integer);
var lbl: TTyLabel;
begin
  inherited CreateNew(AOwner, Num);
  Caption := '请确认';
  lbl := TTyLabel.Create(Self);
  lbl.Parent := Self;
  lbl.Caption := '确定要删除所选项目吗？';
  lbl.SetBounds(16, TitleHeight + 12, 240, 24);
  AddButton('删除', mrOK,     True,  False);
  AddButton('取消', mrCancel, False, True);
  AutoSizeToContent(272, 40);
end;

// 调用：
var dlg: TMyConfirmDlg;
dlg := TMyConfirmDlg.CreateNew(Application);
if dlg.ShowModal = mrOK then
  DoDelete;
dlg.Free;
```

### 3.5 IDE 新建项

在 Lazarus IDE 中选择 **文件 > 新建…**，在 TyControls 分类下选择 **TyControls Dialog**，即可得到一个已继承自 `TTyDialog` 的窗体单元模板，标题栏和按钮栏已就绪，直接在内容区设计你的控件与按钮。

---

## 4. TyMessage — 全局函数（主要 API）

这组全局函数是调用消息对话框的**首选方式**，接口与 LCL 的 `MessageDlg`/`ShowMessage` 对齐，因此迁移成本极低。

### 4.1 对话框类型（`TMsgDlgType`）

复用 LCL 的 `TMsgDlgType`（来自 `Dialogs` 单元）：

| 枚举值 | 标题（已翻译） | 图标 |
|--------|--------------|------|
| `mtWarning` | Warning / 警告 | ! 橙色圆 |
| `mtError` | Error / 错误 | × 红色圆 |
| `mtConfirmation` | Confirm / 确认 | ? 蓝色圆 |
| `mtInformation` | Information / 信息 | i 蓝色圆 |
| `mtCustom` | （空，需传 ATitle） | 无图标 |

### 4.2 按钮集合（`TMsgDlgButtons`）

复用 LCL 的 `TMsgDlgButtons`（集合类型）与 `TMsgDlgBtn` 枚举：

`mbYes`、`mbNo`、`mbOK`、`mbCancel`、`mbAbort`、`mbRetry`、`mbIgnore`、`mbAll`、`mbNoToAll`、`mbYesToAll`、`mbHelp`、`mbClose`

按钮在对话框中按照固定顺序从右至左排列（Yes > YesToAll > No > NoToAll > All > OK > Retry > Ignore > Abort > Cancel > Close > Help）；传入空集合时自动退化为 `[mbOK]`。

### 4.3 API

```pascal
// 纯提示：一个 OK 按钮，mtInformation 类型，不返回值
procedure TyShowMessage(const AMsg: string);

// 标准消息对话框，返回 TModalResult（mrYes / mrNo / mrOK / mrCancel / …）
function TyMessageDlg(
  const AMsg:   string;
  ADlgType:     TMsgDlgType;
  AButtons:     TMsgDlgButtons;
  AHelpCtx:     Longint = 0
): TModalResult;

// 同上，但指定弹出位置（左上角坐标）
function TyMessageDlgPos(
  const AMsg:   string;
  ADlgType:     TMsgDlgType;
  AButtons:     TMsgDlgButtons;
  AHelpCtx:     Longint;
  X, Y:         Integer
): TModalResult;
```

### 4.4 代码示例

```pascal
uses tyControls.Dialogs;

// 简单提示
TyShowMessage('保存成功。');

// 确认删除
if TyMessageDlg('确定要删除所选文件吗？', mtConfirmation, [mbYes, mbNo]) = mrYes then
  DeleteFile(FileName);

// 错误提示
TyMessageDlg('无法连接到服务器。', mtError, [mbOK]);

// 警告（含帮助上下文）
TyMessageDlg('磁盘空间不足。', mtWarning, [mbOK], 1001);

// 指定位置
TyMessageDlgPos('操作已完成。', mtInformation, [mbOK], 0, 200, 150);
```

---

## 5. TTyMessage — 设计期组件

`TTyMessage` 是一个**非可视组件**（`TComponent` 后裔），在设计器组件面板的 **TyControls Dialogs** 页可以找到它。它将 `TyMessageDlg` 的常用参数封装为 published 属性，便于在对象检视器中配置、在代码中一行调用。

### 5.1 Published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Title` | `string` | `''` | 对话框标题；非空时覆盖类型自动标题 |
| `Msg` | `string` | `''` | 消息正文 |
| `DlgType` | `TMsgDlgType` | `mtInformation` | 对话框语义类型（影响标题和图标） |
| `Buttons` | `TMsgDlgButtons` | `[mbOK]` | 按钮集合 |

### 5.2 方法

```pascal
function Execute: TModalResult;
```

构建并模态显示对话框，返回 `TModalResult`。对话框显示后自动释放。`Buttons` 为空时退化为 `[mbOK]`。

### 5.3 使用示例

在窗体上放置一个 `TTyMessage`，在对象检视器中设置：

```
DlgType = mtConfirmation
Buttons = [mbYes, mbNo]
Msg     = 确定要退出吗？
```

在代码中：

```pascal
if MsgConfirmExit.Execute = mrYes then
  Close;
```

---

## 6. 国际化（i18n）

消息对话框的**按钮标题**（"确定"/"取消"/"是"/"否" 等）和**对话框类型标题**（"警告"/"错误"/"确认"/"信息"）均为 `resourcestring`，位于 `tyControls.StrConsts` 单元，对应 zh_CN 词条在 `languages/tycontrols.strconsts.zh_CN.po`。

切换语言后（如通过 `LCLTranslator.SetDefaultLang('zh_CN')`），按钮文字自动随之更新，无需修改控件代码。

---

## 7. 注意事项

- 对话框本身不含 `TTyStyleController`；当其 `Controller` 未设置时，自动回退到库全局的默认控制器 `TyDefaultController`（`tyControls.Controller` 中惰性创建的全局单例）获取主题，从而与应用其余部分保持一致的视觉风格。
- 内容区控件**直接放在窗体上**（`Parent := <对话框>`，如 §3.4 示例中的 `lbl.Parent := Self`），位于标题栏之下、底部按钮条之上——可用区域由 `ContentRect` 给出。通过 IDE 模板创建时会自动落在这一区域内。
- 消息图标颜色（错误/警告/信息）在 S1 版本中使用语义固定色；后续版本将引入 `--error`/`--warning`/`--info` 主题令牌以实现完全主题驱动的图标色。
- S1 消息对话框使用固定内容尺寸（消息标签约 260×40，`AutoSizeToContent(320, 56)`），过长或多行的消息文本可能被裁剪；自动文字量度与动态尺寸调整将在 S2 版本中跟进。

---

## 8. 输入类对话框（S2）

S2 阶段新增一组**输入类**对话框，均位于 `tyControls.Dialogs` 单元（文件夹选择器另在 `tyControls.Dialogs.SelectPath`）。每个对话框都有对应的全局函数（主要 API）和非可视设计期组件（位于 **TyControls Dialogs** 组件面板页）。

### 8.1 TyInputDialog — 单行文本输入

`TTyInputDialog` / 全局函数 `TyInputQuery` 与 `TyInputBox`：弹出一个带单行文本框的模态对话框，用于获取用户输入的单行字符串。

```pascal
uses tyControls.Dialogs;

// 方式一：query 风格，in-place 修改 value，返回是否点击"确定"
var s: string;
s := '初始值';
if TyInputQuery('重命名', '请输入新名称：', s) then
  Rename(OldName, s);

// 方式二：box 风格，直接返回输入值（取消时返回 default）
var name: string;
name := TyInputBox('新建项目', '项目名称：', 'Untitled');
```

设计期：在窗体上放置 `TTyInputDialog`，在对象检视器中设置 `Caption`、`Prompt`、`Value`，代码中调用 `Execute: Boolean`。

### 8.2 TyPasswordDialog — 掩码密码输入

`TTyPasswordDialog` / 全局函数 `TyPasswordBox` 与 `TyPasswordQuery`：带掩码字符（默认 `●`）的密码输入对话框，输入内容不可见。

```pascal
uses tyControls.Dialogs;

// 方式一：返回输入的密码字符串（取消时返回空字符串）
var pwd: string;
pwd := TyPasswordBox('登录', '请输入密码：');
if pwd <> '' then
  Login(User, pwd);

// 方式二：query 风格，返回是否点击"确定"
var pwd: string;
pwd := '';
if TyPasswordQuery('修改密码', '请输入新密码：', pwd) then
  ChangePassword(pwd);
```

### 8.3 TyTextDialog — 多行文本输入（可缩放）

`TTyTextDialog` / 全局函数 `TyTextQuery`：可缩放的多行文本输入对话框（基于 `TTyMemo`），适用于备注、描述等较长文本。

> **注意：返回值末尾携带一个换行符**（`LineEnding`）——这与 `TTyMemo.Text` / `TStrings.Text` 的 LCL 语义一致；往返读取结果稳定，不会累积叠加。如果调用方需要去掉末尾换行，自行 `TrimRight` 一次即可。

```pascal
uses tyControls.Dialogs;

var note: string;
note := '';
if TyTextQuery('编辑备注', '请输入备注内容：', note) then
begin
  // note 末尾含一个 LineEnding，按需裁剪：
  note := TrimRight(note);
  SaveNote(note);
end;
```

### 8.4 TySelectValueDialog — 列表单选

`TTySelectValueDialog` / 全局函数 `TySelectValue`：从 `TStrings` 列表中单选一项，双击直接确认。返回所选条目的索引（`items[index]` 即选中值）。

```pascal
uses tyControls.Dialogs;

var
  items: TStringList;
  idx: Integer;
begin
  items := TStringList.Create;
  try
    items.Add('选项 A');
    items.Add('选项 B');
    items.Add('选项 C');
    idx := 0; // 初始选中
    if TySelectValue('请选择', '选择一个选项：', items, idx) then
      ShowMessage('你选择了：' + items[idx]);
  finally
    items.Free;
  end;
end;
```

### 8.5 TySelectPathDialog — 文件夹选择器（可缩放）

`TTySelectPathDialog` / 全局函数 `TySelectDirectory`（位于 `tyControls.Dialogs.SelectPath`）：懒加载目录树，仅显示目录、支持"新建文件夹"按钮，对话框可拖拽边框缩放。

```pascal
uses tyControls.Dialogs.SelectPath;

var dir: string;
dir := '';
if TySelectDirectory('选择输出目录', 'C:\Users', dir) then
  OutputDir := dir;
```

### 8.6 非可视设计期组件

以下 5 个非可视组件位于 **TyControls Dialogs** 组件面板页，每个组件均封装了对应对话框的 published 属性，代码中一行 `Execute` 即可显示：

| 组件 | 对应全局函数 | `Execute` 返回值 |
|------|------------|----------------|
| `TTyInputDialog` | `TyInputQuery` | `Boolean`（`True` = 确定） |
| `TTyPasswordDialog` | `TyPasswordQuery` | `Boolean` |
| `TTyTextDialog` | `TyTextQuery` | `Boolean` |
| `TTySelectValueDialog` | `TySelectValue` | `Boolean` |
| `TTySelectPathDialog` | `TySelectDirectory` | `Boolean` |

```pascal
// 示例：设计器中放置 TTyInputDialog，命名为 DlgRename
DlgRename.Caption := '重命名';
DlgRename.Prompt  := '请输入新名称：';
DlgRename.Value   := CurrentName;
if DlgRename.Execute then
  Rename(CurrentName, DlgRename.Value);
```

---

## 9. 拾取器对话框（S3）

S3 阶段新增**取色器**与**字体对话框**两个拾取器，取色器位于 `tyControls.Dialogs.Color`，字体对话框位于 `tyControls.Dialogs.Font`（设计期组件在 **TyControls Dialogs** 面板页）。

### 9.1 TyColorDialog — 取色器

弹出 HSV 色彩选择对话框，含色相条 + HSV 方块 + RGB / CMYK / Hex 输入框 + Alpha 滑块，所有通道全双向同步。

**全局函数**（主要 API）：

```pascal
// 原生 TTyColor（含 alpha），返回是否点击"确定"
function TySelectColor(const ACaption: string; var AColor: TTyColor): Boolean;

// LCL TColor + 独立 Alpha 字节，返回是否点击"确定"
function TySelectColor(const ACaption: string; var AColor: TColor; var AAlpha: Byte): Boolean;
```

```pascal
uses tyControls.Dialogs.Color;

// 原生 TTyColor 用法
var c: TTyColor;
c := TyRGBA(255, 128, 0, 255);
if TySelectColor('选择颜色', c) then
  MyControl.Color := c;

// LCL TColor + Alpha 用法
var col: TColor;
    alpha: Byte;
col   := clBlue;
alpha := 200;
if TySelectColor('选择颜色', col, alpha) then
begin
  MyControl.Color := col;
  MyControl.Alpha := alpha;
end;
```

**设计期组件 `TTyColorDialog`**：`Color: TTyColor`（原生）/ `LCLColor: TColor` / `Alpha: Byte` 三者互为视图；调用 `Execute: Boolean` 显示对话框。

```pascal
// 在窗体上放置 TTyColorDialog，命名为 DlgColor
DlgColor.Color := MyShape.FillColor;
if DlgColor.Execute then
  MyShape.FillColor := DlgColor.Color;
```

### 9.2 TyFontDialog — 字体对话框

弹出字体选择对话框，可设置字体族、字号、粗体/斜体/下划线/删除线、颜色（内嵌取色器），并实时预览效果；对话框可拖拽边框缩放。

**全局函数**（主要 API）：

```pascal
// 就地修改 AFont；用户点击"确定"返回 True，"取消"返回 False（AFont 保持不变）
function TyFontDialog(AFont: TFont): Boolean;
```

```pascal
uses tyControls.Dialogs.Font;

if TyFontDialog(MyEdit.Font) then
  MyEdit.Invalidate; // 字体已就地更新，刷新控件即可
```

**设计期组件 `TTyFontDialog`**：`Font: TFont` 属性保存当前字体；调用 `Execute: Boolean` 显示对话框（`True` = 确定，字体已修改）。

```pascal
// 在窗体上放置 TTyFontDialog，命名为 DlgFont
DlgFont.Font.Assign(Memo1.Font);
if DlgFont.Execute then
  Memo1.Font.Assign(DlgFont.Font);
```

> **注意**：两个组件均在 **TyControls Dialogs** 组件面板页可以找到。字体对话框的颜色选择器复用 `TTyColorDialog` 内核，保证视觉一致性。
