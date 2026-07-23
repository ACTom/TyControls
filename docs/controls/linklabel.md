# TTyLinkLabel

## 1. 概述

TTyLinkLabel 是**主题化超链接标签**,继承自 `TTyGraphicControl`(非窗口化,不可获得键盘焦点)。文字以主题**强调色(accent)**绘制并带一条 1px 下划线(横跨实测文字宽度,类似"关于"对话框中的主页链接)。鼠标悬停时强调色略微提亮;点击时若 `AutoOpen = True` 且 `URL` 非空,则通过 `OpenURL` 打开链接。适用于"访问主页 / 查看文档 / 打开链接"等可点击文字。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.LinkLabel` |
| `GetStyleTypeKey` 返回值 | `'TyLinkLabel'`(**自有键**:字体族 / 字号 / 字重 / `:disabled` 透明度取自它)|
| 链接墨色 typeKey | `'TyLinkLabelLink'`(**自有键**:取其 `color` 作为链接色 + 下划线色)|

两个键都是本控件自己的。`TyLinkLabel` 在 `themes/light.tycss` 里与 `TyLabel` 并列写在同一条规则的
选择器列表中,`TyLinkLabelLink` 则是一条独立规则(`TyLinkLabelLink { color: var(--accent); }`),
因此解析值与从前完全一致 —— 拆键开的是钩子,不改外观。

链接墨色从前借 `'TyGaugeFill'`:那意味着**给仪表盘换个填充色就会把全应用的超链接一起换掉**,
而链接色本身反倒无法单独主题化。现在改链接色写 `TyLinkLabelLink`,别碰 `TyGaugeFill`。

```pascal
uses tyControls.LinkLabel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 链接文字;以 accent 色绘制并加下划线。 |
| `URL` | `string` | `''` | 点击时打开的目标地址。 |
| `AutoOpen` | `Boolean` | `True` | 为 `True` 且 `URL` 非空时,`Click` 中调用 `OpenURL(URL)` 打开链接;为 `False` 时仅触发 `OnClick`,不自动打开。 |
| `Alignment` | `TAlignment` | `taLeftJustify` | 文字**水平**对齐;下划线随对齐方式定位。 |
| `Layout` | `TTextLayout` | `tlCenter` | 文字**垂直**对齐。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时触发 `:disabled` 主题状态(降低不透明度)。 |
| `Font` | `TFont` | 系统默认 | 传递 PPI 给渲染器;字体族与字号优先由主题控制。 |
| `Align` | `TAlign` | `alNone` | 父容器内停靠方式。 |
| `Anchors` | `TAnchors` | `[akLeft, akTop]` | 锚点。 |

### 继承的通用成员

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | CSS 类名,对应 `.tycss` 选择器的 `.classname`。 |
| `Controller` | `TTyStyleController` | `nil`(用全局 `TyDefaultController`)| 指定样式控制器。 |

> 光标在 `Create` 中设为 `crHandPoint`(手形)。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 鼠标点击时(`TGraphicControl` 内置支持);先触发 `OnClick`,随后若 `AutoOpen` 且 `URL` 非空再打开链接。 |

> **基线事件集:** 继承自 `TTyGraphicControl`(非窗口化),仅暴露 **Tier A** 基线事件(鼠标 / 通用),**无** Tier B 键盘 / 焦点事件。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停(此时链接色提亮约 15%)|
| `:active` | 鼠标左键按下 |
| `:disabled` | `Enabled = False` |

> `:focus` **不支持**(`TTyGraphicControl` 无窗口句柄,不可聚焦)。

### 解析的主题键

| typeKey | 画什么 |
|---------|--------|
| `TyLinkLabel` | 控件盒子:背景(默认透明)、`font-family` / `font-size` / `font-weight`、`opacity`(`:disabled` 时整体变淡)。 |
| `TyLinkLabelLink` | 链接墨色:它的 `color` 同时用于**文字**和那条 1px 下划线。 |

两条都要写才算把这个控件主题化完:字号字重在 `TyLinkLabel`,颜色在 `TyLinkLabelLink`。

```css
TyLinkLabel     { font-size: 12px; font-weight: 500; }
TyLinkLabelLink { color: #0A66C2; }
```

> **状态在链接墨色上不生效(现状,非设计):** `LinkColor` 解析 `TyLinkLabelLink` 时传的是**空状态集**,
> 所以 `TyLinkLabelLink:hover` / `:disabled` 是**死选择器**;悬停提亮是代码里的 `TyLighten(col, 15)`,
> 不走主题。此外本控件**不读 `padding`**(内容区取整个矩形),下划线的下沉量 `P.Scale(3)` 与
> 1px 厚度也是代码字面量 —— 这些都是已知待补项,不要指望用主题去调。

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.LinkLabel;

TyDefaultController.LoadTheme('themes/light.tycss');

var Link: TTyLinkLabel;
Link := TTyLinkLabel.Create(Self);
Link.Parent := Self;
Link.SetBounds(24, 24, 220, 22);
Link.Caption := '访问项目主页';
Link.URL := 'https://example.com';
// 默认 AutoOpen = True,点击即用系统浏览器打开 URL

// 只触发 OnClick、不自动打开(自定义处理):
Link.AutoOpen := False;
Link.OnClick := @DoCustomNavigate;
```

---

## 7. 注意事项

- **无键盘焦点:** 基类是 `TGraphicControl`,没有 HWND,`:focus` 伪类永不生效。
- **下划线绘制:** `TTyPainter.DrawText` 不带下划线参数,故先绘制文字,再用 `P.FillBackground` 在实测文字宽度下方补一条 1px accent 线(宽度夹紧到内容宽度,不会溢出)。
- **颜色主题化:** 链接色不硬编码,始终从 `TyLinkLabelLink` 的 `color` 解析(悬停态再经 `TyLighten` 提亮),更换主题即换色;要单独改链接色只改这一条规则,不会波及别的控件。
- **单元名:** 单元名是 `tyControls.LinkLabel`。
- **几何辅助:** 下划线定位逻辑抽为纯函数 `TyLinkUnderlineRect`,已单元测试(左 / 右 / 居中 / 越界夹紧 / 负宽)。
