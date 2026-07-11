# TTyHtmlLabel

## 概述

`TTyHtmlLabel` 是一个**迷你 HTML 标签**(`TTyCustomControl`)—— 渲染一个**行内子集**的带格式文本,
不是浏览器。支持粗/斜/下划线/删除线、字体色与字号、链接、换行,自动换行。**零新增主题 token**
(`GetStyleTypeKey='TyLabel'`;文字取主题色,链接取 accent)。

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

## 关键设计

- **纯解析可无头测**:`TyHtmlParse(html): TTyHtmlRunArray` —— 用样式栈把标签解析成富文本 run 序列
  (Text / Bold / Italic / Underline / Strike / LineBreak / Color+HasColor / SizePt / Href),`<br>` 为断行 run,
  实体解码,畸形容错(栈不下溢、`<` 无闭合当字面、未知标签跳过)。渲染/命中测试靠真机。
- **链接**:accent 色 + 下划线;悬停变手型(离开还原用户 Cursor,不硬置 crDefault),`MouseUp` 触发 `OnLinkClick`。
- 空白折叠(连续空白→一个空格);混合字号本行顶对齐(v1 简化)。

## 关联

见 `docs/superpowers/plans/2026-07-12-phase9-finish.md`。纯文本标签见 [TTyLabel](label.md)。
