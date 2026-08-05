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
| `SelectedColor` | `TTyColor` | `$FF3B82F6`（accent 蓝，`TyRGB(59,130,246)`） | 当前色块颜色。**任何**方式的变更（代码赋值、对话框接受）都会重绘并触发 `OnColorChange`；仅流式载入期间（`csLoading`）抑制，否则每次载入 `.lfm` 都会在窗体建成前发一次事件。 |
| `ButtonColor` | `TColor` | 同 `SelectedColor`（`stored False`，不写入 `.lfm`） | LCL 的名字和 LCL 的**类型**（`dialogs.pp:370`）。它是 `SelectedColor` 的第二个**视图**，不是第二个值：读写都换算（`TTyColor` 是 ARGB，`TColor` 不带 alpha，写入时保留当前 alpha）。`stored False` 是故意的——published 属性无论是否 `stored` 都能从 `.lfm` **读**进来，所以移植过来的 `ButtonColor = clRed` 能加载；不写出去则保证自家 `.lfm` 不会用两个名字存同一个颜色。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 本类**重新声明**基类默认值（`TTyButton` 是 `taCenter`），构造函数同步设置。理由：标题画在色块**右侧剩下的那条**里，从那条的左缘起排才贴着色块。仍可设成 `taCenter` / `taRightJustify`，色块不动。 |
| `ShowText` | `Boolean` | `False` | 为 `True` 时在色块右侧绘制 `#RRGGBB` 十六进制文字（取 `AStyle.TextColor`）；为 `False` 时色块占满内容区。**`Caption` 非空时它不起作用**——两者共用同一个文字位，`Caption` 优先。 |
| `DialogCaption` | `string` | `'Select Color'` | 点击后弹出的取色对话框标题栏文字。 |
| `OnColorChange` | `TNotifyEvent` | `nil` | `SelectedColor` **实际发生变化**时触发，不区分来源。 |
| `OnColorChanged` | `TNotifyEvent` | `nil` | LCL 对同一个通知的叫法（`dialogs.pp:387-388`），和 `OnColorChange` 只差一个字母。两个都会触发，`OnColorChange` 在前。各自有独立字段，所以各自按自己的名字流式化，保存时不会把宿主的处理器悄悄改名。 |

### 自有 public 方法

| 方法 | 返回 | 说明 |
|------|------|------|
| `ContentText` | `string` | 这个按钮**实际会画出来**的那串文字：`Caption` 非空时返回 `Caption`，否则 `ShowText` 时返回 `#RRGGBB`，两者都没有则为空串（纯色块）。`AutoSize` 的宽度测量量的就是它——画什么就量什么，否则被裁掉的正是用户唯一填过的那个属性。 |

### 继承自 [[TTyButton]] 的成员

`Caption`、`Default`、`Cancel`、`ModalResult`、`AnimationsEnabled`、`Down`、`ShowBadge` / `BadgeValue` / `BadgePosition`、`Enabled`、`Font`、`Align`、`Anchors`、`StyleClass`、`Controller`、`OnClick` 等一律可用，语义与 [[TTyButton]] 一致。`Caption` 非空时画在色块右侧，并**优先于** `ShowText` 的 `#RRGGBB`（两者共用同一个文字位；`ShowText` 只在没有 `Caption` 时才起作用）。注意：本控件的点击**即为"打开取色对话框"**，`OnClick` 在**对话框弹出之前**触发。

---

## 4. 事件语义

- `SelectedColor := someColor`（代码 / 设计器）：重绘并触发 `OnColorChange`；只有流式载入（`csLoading`）期间静默。
- 用户点击：**先**触发 `OnClick`（此时读到的还是**变更前**的颜色，处理器可以据此否决或改配置），**再**弹出取色对话框；点击"确定"且颜色改变时走与代码赋值同一条路径——重绘并触发 `OnColorChange`。
- 用户点击 → 对话框"取消"，或选了与原值相同的颜色：不触发 `OnColorChange`（`OnClick` 已经触发过了）。

以前 `OnColorChange` 只认对话框驱动的变更，于是"让某个预览跟着颜色走"这类处理器在用户挑色时有效、在程序恢复一个存档值时静默失效——恰好是没人会去测的那一半。现在两条路径合一：`OnColorChange` 表示"颜色变了"，`OnClick` 表示"用户点了这个按钮"。

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
  // 颜色只要真的变了就到这里（含代码赋值），流式载入期间除外
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

- **`Btn.ButtonColor := clRed` 是每个 `TColorButton` 用户都会写的那一行**：走 `ButtonColor` 才有 `TColor` → ARGB 的换算；直接把 `TColor` 赋给 `SelectedColor` 会被当成 ARGB 读，静默出错。
- **标题现在走助记符解析：** 与其它按钮一致，`&Save` 会给 `S` 加下划线，并遵守 `ShowAccelChar`；以前本控件把 `&` 原样画出，同一窗体上的按钮各画各的。
- 取色对话框由 `TySelectColor`（`tyControls.Dialogs.Color`，见 [dialogs.md](dialogs.md) §9.1）提供，本身是主题化、模态、自绘的 HSV 取色器（色相条 + HSV 方块 + RGB / CMYK / Hex / Alpha）。
- `SelectedColor` 含 alpha 通道（`TTyColor` 为 `$AARRGGBB`），但色块右侧的 `#RRGGBB` 文字**忽略 alpha**；如需带 alpha 的十六进制，请另行使用 `TyColorToHex(AColor, True)`（`tyControls.ColorMath`）。
- 色块边框优先取解析样式的 `BorderColor`；主题未提供时退化为一条低对比度的半透明灰线，以保证浅色 / 深色主题下色块边缘都可见。

---

## 相关

- [[TTyButton]] — 父类，提供全部按钮能力。
- [对话框子系统](dialogs.md) — `TySelectColor` 取色对话框（§9.1）。
- **右到左镜像：** `BiDiMode := bdRightToLeft` 时色块移到右侧、标题移到它左边。宽度计算不变（`CalculatePreferredSize` 无需分支），只是同样的三段换了顺序。
