# TTyEdit

## 1. 概述

TTyEdit 是 TyControls 库中的主题化单行文本输入控件，继承自 `TTyCustomControl`。典型用途：用户输入姓名、搜索关键词、数字等单行文本，支持 UTF-8 安全退格（按字符删除，不截断多字节序列），焦点时显示光标。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Edit` |
| `GetStyleTypeKey` 返回值 | `'TyEdit'` |

在 `.tycss` 文件中，该控件对应的选择器前缀为 `TyEdit`。

```pascal
uses tyControls.Edit;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Text` | `string` | `''` | 输入框当前内容；赋值会触发重绘，但**不**触发 `OnChange` 事件（见注意事项） |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled`，控件不响应键盘/鼠标输入 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器；字体族与大小优先由主题控制 |
| `Align` | `TAlign` | `alNone` | 父容器内的停靠方式 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 随父控件调整大小时的锚点 |

### 继承的通用成员

TTyEdit 继承自 `TTyCustomControl`（`tyControls.Base`），与其他 TyControls 控件共享以下 published 属性：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名，对应 `.tycss` 选择器的 `.classname` 部分 |
| `Controller` | `TTyStyleController` | `nil`（使用全局 `TyDefaultController`） | 指定使用哪个样式控制器 |

**状态跟踪字段（protected，不 published）：**

| 字段/状态 | 类型 | 说明 |
|-----------|------|------|
| `FHover` | `Boolean` | 鼠标悬停时为 `True`，触发 `:hover` 主题状态 |
| `FPressed` | `Boolean` | 鼠标左键按下时为 `True`，触发 `:active` 主题状态 |
| `Focused` | `Boolean` | 获得键盘焦点时触发 `:focus` 主题状态，并显示光标 |
| `Enabled = False` | — | 触发 `:disabled` 主题状态 |

**构造时自动设置 `TabStop := True`**，确保控件可以被 Tab 键导航。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击控件时 |

> **注意：** 当前版本没有 `OnChange` 事件。文本通过按键实时变化，但没有回调通知。若需要监听内容变化，可继承 `TTyEdit` 并重写 `UTF8KeyPress` / `KeyDown`，或在用户完成输入后主动读取 `Text` 属性。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

### light.tycss 内置规则摘要

```css
TyEdit {
  background: var(--surface);        /* #FFFFFF */
  color: var(--on-surface);          /* #1F2937 */
  border-color: var(--border);       /* #D1D5DB */
  border-width: 1px;
  border-radius: var(--radius);      /* 6px */
  padding: 4px;
  font-size: 10px;
}
TyEdit:hover    { border-color: darken(--border, 10%); }
TyEdit:focus    { border-color: var(--accent); }   /* #3B82F6，蓝色高亮边框 */
TyEdit:disabled { opacity: 0.5; }
```

聚焦时除边框变蓝外，渲染器还会在内容区域左侧绘制一条 1px 宽的竖线光标，颜色与 `TextColor` 相同。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Edit, tyControls.Button, tyControls.TyLabel;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 基础输入框
var Edit: TTyEdit;
Edit := TTyEdit.Create(Self);
Edit.Parent := Self;
Edit.SetBounds(24, 48, 300, 32);
Edit.Text := '初始内容';

// 禁用态
var EditDisabled: TTyEdit;
EditDisabled := TTyEdit.Create(Self);
EditDisabled.Parent := Self;
EditDisabled.SetBounds(24, 100, 300, 32);
EditDisabled.Text := '只读，无法编辑';
EditDisabled.Enabled := False;

// 读取输入内容
procedure TMainForm.ReadClicked(Sender: TObject);
begin
  ShowMessage('输入内容：' + Edit.Text);
end;
```

完整可运行示例参见 `examples/edit/umain.pas`。

---

## 7. 注意事项

- **UTF-8 安全退格：** `InjectBackspace` 方法会从字符串末尾向前跳过所有 UTF-8 续字节（`$80`–`$BF`），找到字符边界后再删除，因此删除中文等多字节字符时不会产生截断或乱码。
- **无 OnChange 事件：** 当前实现不提供 `OnChange`，如需监听输入变化，参考上方事件节的替代方案。
- **光标仅为视觉提示：** 光标位置固定在内容区左侧，不跟随文本长度移动，也不支持鼠标定位或选区操作——这是当前版本的已知限制。
- **粘贴/拖拽不支持：** 输入仅通过 `UTF8KeyPress`（字符输入）和 `KeyDown`（退格）处理，系统剪贴板粘贴等高级编辑功能尚未实现。
- **Tab 导航：** 构造时自动启用 `TabStop`，因此可与其他 `TTyCustomControl` 子类一起参与 Tab 键顺序导航。
- **Text 赋值不触发回调：** `SetText` 仅更新内部字段并重绘，不会触发任何事件。
