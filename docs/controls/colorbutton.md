# TTyColorButton

## 1. 概述

`TTyColorButton` 是一个显示**颜色色块**的按钮控件，继承自 [[TTyButton]]。点击时弹出主题化的取色对话框（`TySelectColor`，见 [dialogs.md](dialogs.md) §9.1），用户选定颜色后色块随之更新。典型用途：让用户在窗体上直接挑选前景色 / 填充色 / 高亮色等。

它复用 `TTyButton` 的所有能力（状态、悬停淡入、角标、默认 / 取消键、`ModalResult` 等），只是把按钮内容从居中文字换成了色块（可选附带 `#RRGGBB` 十六进制文字）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ColorButton` |
| `GetStyleTypeKey` 返回值 | `'TyButton'`（**沿用**父类，复用按钮主题令牌，不新增 `.tycss`） |

```pascal
uses tyControls.ColorButton;
```

因为 typeKey 保持 `'TyButton'`，`TTyColorButton` 的外框、内边距、字体、悬停 / 按下 / 禁用状态样式全部由已有的 `TyButton` 选择器驱动，`StyleClass`（如 `TyButton.primary`）同样适用。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `SelectedColor` | `TTyColor` | `$FF3B82F6`（accent 蓝，`TyRGB(59,130,246)`） | 当前色块颜色。**以代码方式设置只会重绘、不触发 `OnColorChange`**（该事件仅用于对话框驱动的变更）。 |
| `ShowText` | `Boolean` | `False` | 为 `True` 时在色块右侧绘制 `#RRGGBB` 十六进制文字（取 `AStyle.TextColor`）；为 `False` 时色块占满内容区。 |
| `DialogCaption` | `string` | `'Select Color'` | 点击后弹出的取色对话框标题栏文字。 |
| `OnColorChange` | `TNotifyEvent` | `nil` | **仅当**用户在对话框中点击"确定"**且颜色确实发生变化**时触发。 |

### 继承自 [[TTyButton]] 的成员

`Caption`、`Default`、`Cancel`、`ModalResult`、`AnimationsEnabled`、`Down`、`ShowBadge` / `BadgeValue` / `BadgePosition`、`Enabled`、`Font`、`Align`、`Anchors`、`StyleClass`、`Controller`、`OnClick` 等一律可用，语义与 [[TTyButton]] 一致。注意：本控件的点击**即为"打开取色对话框"**，`OnClick` 仍会在对话框关闭后照常触发。

---

## 4. 事件语义

- `SelectedColor := someColor`（代码 / 设计器 / 流式载入）：仅重绘，**不**触发 `OnColorChange`。
- 用户点击 → 弹出对话框 → 点击"确定"且颜色改变：先重绘并触发 `OnColorChange`，随后调用 `inherited Click` 触发 `OnClick`。
- 用户点击 → 对话框"取消"，或选了与原值相同的颜色：不触发 `OnColorChange`（`OnClick` 仍会触发）。

这样应用可以用 `OnColorChange` 只响应"真正的颜色变更"，用 `OnClick` 响应"用户点了这个按钮"。

---

## 5. 使用示例

```pascal
uses tyControls.ColorButton, tyControls.Types;

// 设计器中放置 TTyColorButton（命名 BtnFill），或代码创建：
BtnFill := TTyColorButton.Create(Self);
BtnFill.Parent := Self;
BtnFill.SetBounds(16, 16, 120, 30);
BtnFill.SelectedColor := TyRGB(0, 122, 204);
BtnFill.ShowText := True;                 // 色块右侧显示 '#007ACC'
BtnFill.DialogCaption := '选择填充色';
BtnFill.OnColorChange := @FillColorChanged;

procedure TForm1.FillColorChanged(Sender: TObject);
begin
  // 仅在对话框接受且颜色改变时到达这里
  MyShape.FillColor := (Sender as TTyColorButton).SelectedColor;
end;
```

纯辅助函数（可独立使用）：

```pascal
function TyColorHex(AColor: TTyColor): string;   // 返回 '#RRGGBB'（大写，忽略 alpha）

// TyColorHex(TyRGB(59, 130, 246)) = '#3B82F6'
// TyColorHex(TyRGBA(0, 0, 0, 128)) = '#000000'   （alpha 被忽略）
```

---

## 6. 注意事项

- 取色对话框由 `TySelectColor`（`tyControls.Dialogs.Color`，见 [dialogs.md](dialogs.md) §9.1）提供，本身是主题化、模态、自绘的 HSV 取色器（色相条 + HSV 方块 + RGB / CMYK / Hex / Alpha）。
- `SelectedColor` 含 alpha 通道（`TTyColor` 为 `$AARRGGBB`），但色块右侧的 `#RRGGBB` 文字**忽略 alpha**；如需带 alpha 的十六进制，请另行使用 `TyColorToHex(AColor, True)`（`tyControls.ColorMath`）。
- 色块边框优先取解析样式的 `BorderColor`；主题未提供时退化为一条低对比度的半透明灰线，以保证浅色 / 深色主题下色块边缘都可见。

---

## 相关

- [[TTyButton]] — 父类，提供全部按钮能力。
- [对话框子系统](dialogs.md) — `TySelectColor` 取色对话框（§9.1）。
