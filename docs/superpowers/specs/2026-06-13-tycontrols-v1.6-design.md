# TyControls v1.6 设计文档 — CSS DSL 完整度

- **日期:** 2026-06-13;自主推进。
- **前置:** main(@b6d98ce,v1–v1.5.1,327 测试)。
- **动机:** 审计发现买家写标准 CSS `border: 1px solid #888` 会被**静默忽略**(引擎只认 `border-width`/`border-color` 长写法)。本阶段补齐最常用的 CSS 写法,降低买家上手摩擦,且 100% 向后兼容。

## 范围

1. **`border-style` 属性 + `none` 抑制边框。** 新增 `TTyBorderStyle = (tbsSolid, tbsNone)`(默认 solid),`TTyStyleSet.BorderStyle` + `tpBorderStyle`。`border-style: none` 即使 `border-width>0` 也不画边框;`solid` 正常。`DrawFrame` 据此判断。
2. **`border: <width> [style] <color>` 简写。** 解析为 border-width + border-style + border-color 三者(顺序宽松:宽度=带 px 的长度;style=solid/none 关键字;其余当颜色)。缺省 style=solid。设置三个 Present 位。
3. **`background-color` 作为 `background` 的别名**(标准 CSS 习惯;等价于 `background: <color>`,纯色)。
4. **`rgb(r,g,b)` / `rgba(r,g,b,a)` 标准颜色函数**(r/g/b 0..255,a 0..1)。与现有 hex / `lighten/darken/alpha/mix` 并存。

## 行为细节
- `EmptyStyleSet`:`BorderStyle` 默认 `tbsSolid`(枚举序 0,Default() 即得),且 `tpBorderStyle` **不** present——保持现有"未写 border-style 即按 solid 画"的行为不变。
- `DrawFrame`(Base.pas 两处 TTyGraphicControl/TTyCustomControl):边框绘制条件改为
  `(tpBorderColor in Present) and (BorderWidth>0) and not ((tpBorderStyle in Present) and (BorderStyle=tbsNone))`。
- `TyMergeStyleSet`:补 `if tpBorderStyle in AOver.Present then ABase.BorderStyle := AOver.BorderStyle;`。
- `border` 简写解析在 `TyApplyDeclaration`:按空格切 token(注意颜色 token 可能是 `rgb(…)`/`var(…)`/函数,含空格/逗号——用 SplitArgs 风格或对函数 token 做括号配对切分;最简:先识别带 `px`/纯数字的为 width、`solid`/`none` 为 style,**其余整体**(可能含空格)为 color 表达式,交给 `TyEvalColor`)。v1.6 限制:`border` 简写的颜色若是带内部空格的复杂表达式需谨慎切分——优先支持 `1px solid #888` / `2px solid var(--accent)` / `1px solid rgb(0,0,0)` 这类常见形式。
- `rgb()/rgba()`:在 `TyEvalColor` 的函数分派里加分支;`rgb(r,g,b)`→`TyRGB`;`rgba(r,g,b,a)`→`TyRGBA(r,g,b,Round(a*255))`(a 0..1;若带 `%` 则 /100)。参数用 SplitArgs 切。

## 不做
`margin`(无控件消费,加了是死属性);`border-radius` 每角分写;`box-shadow` 多层;dashed/dotted 边框样式(仅 none/solid)。

## 验收
327 + 新增测试全绿(border-style none 抑制、border 简写三 token、background-color 别名、rgb/rgba);现有主题渲染零变化(都用长写法,新特性是叠加);构建矩阵全绿;heaptrc 0;终审通过;tycss-reference 文档同步。新增可选:给某示例/主题演示 `border:` 简写。
