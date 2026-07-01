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
| `mtWarning` | Warning / 警告 | ⚠ 橙色圆 |
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

- 对话框本身不含 `TTyStyleController`；它从 `Application.MainForm` 所在的全局控制器（`TyDefaultController`）获取主题，与主窗口视觉风格保持一致。
- `TTyDialog` 派生类在 `.lfm` 中流式序列化时，与普通 `TTyForm` 一样，内容区控件挂在 `ContentPanel` 下方。通过 IDE 模板创建时已自动处理好这一点。
- 消息图标颜色（错误/警告/信息）在 S1 版本中使用语义固定色；后续版本将引入 `--error`/`--warning`/`--info` 主题令牌以实现完全主题驱动的图标色。
