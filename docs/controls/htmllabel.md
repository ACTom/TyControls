# TTyHtmlLabel

## 概述

`TTyHtmlLabel` 是一个**迷你 HTML 标签**(`TTyCustomControl`)—— 渲染一个**行内子集**的带格式文本,
不是浏览器。支持粗/斜/下划线/删除线、字体色与字号、链接、换行,自动换行。typeKey 是它**自己的**
`'TyHtmlLabel'`(文字取主题色,链接色见下文「主题」一节)。

## 支持的子集

`<b> <i> <u> <s>`、`<font color=#rrggbb size=N>`、`<a href="...">`、`<br>` + 纯文本。
实体:`&lt; &gt; &amp; &quot; &nbsp;`。标签大小写不敏感;畸形/未知标签**容错跳过**,永不崩。
**不做**:表格、图片、CSS、列表、块级嵌套(`<div><p>`)。

## 用法

```pascal
uses tyControls.HtmlLabel;

Lbl := TTyHtmlLabel.Create(Self);
Lbl.Parent := Panel1;
Lbl.Html := '欢迎使用 <b>TyControls</b>,更多见 ' +
            '<a href="https://github.com/ACTom/TyControls">项目主页</a>。';
Lbl.OnLinkClick := @LinkClicked;

procedure TForm1.LinkClicked(Sender: TObject; const AHref: string);
begin
  OpenURL(AHref);   // LCLIntf.OpenURL
end;
```

## 属性 / 事件

| 成员 | 说明 |
|---|---|
| `Html: string` | HTML 子集文本。写它重解析 + 重排 + 重绘。 |
| `WordWrap: Boolean` | 按宽度自动换行。默认 True。 |
| `OnLinkClick(Sender; const AHref)` | 点击 `<a>` 链接触发。 |
| `AutoSize` | 按内容自适应尺寸。 |

## 主题

| typeKey | 画什么 |
|---|---|
| `TyHtmlLabel` | 整个控件:背景(默认透明)、正文字色 `color`、`font-family`/`font-size`/`font-weight`、`padding`(内容区四边内缩)、`:disabled { opacity }`。 |

`TyHtmlLabel` 是本控件自己的键,不再借 `TyLabel`。在 `themes/light.tycss` 里它与 `TyLabel`
写在同一条规则的选择器列表中(`TyLabel, TyHtmlLabel, ... { }`),所以解析出来的值与从前逐字节
相同 —— 这一步开的是**钩子**,不改外观。想让富文本块用与静态标签不同的字号/字重/底色,单独写
一条 `TyHtmlLabel { ... }` 即可;**不要**改 `TyLabel` —— 那会连带改掉全应用的每一个静态标签。

**子部件暂不可单独主题化。** `<a>` 链接的墨色目前**不经任何 typeKey**:`RenderTo` 直接内联解析
`'color: var(--accent);'`,链接色因此被钉死在 `--accent` 上,任何选择器都够不着。子部件键
(`TyHtmlLabelLink`)属于本轮**有意推迟**的扩展,现在**并不存在**,别往主题里写。当前唯一能改
链接色的办法是改 `--accent`(影响全应用强调色)。下划线 / 删除线的粗细同样是代码里的
`P.Scale(1)` 字面量,不是令牌。

## 关键设计

- **纯解析可无头测**:`TyHtmlParse(html): TTyHtmlRunArray` —— 用样式栈把标签解析成富文本 run 序列
  (Text / Bold / Italic / Underline / Strike / LineBreak / Color+HasColor / SizePt / Href),`<br>` 为断行 run,
  实体解码,畸形容错(栈不下溢、`<` 无闭合当字面、未知标签跳过)。渲染/命中测试靠真机。
- **链接**:accent 色 + 下划线;悬停变手型(离开还原用户 Cursor,不硬置 crDefault),`MouseUp` 触发 `OnLinkClick`。
- 空白折叠(连续空白→一个空格);混合字号本行顶对齐(v1 简化)。

## 关联

见 `docs/superpowers/plans/2026-07-12-phase9-finish.md`。纯文本标签见 [TTyLabel](label.md)。
