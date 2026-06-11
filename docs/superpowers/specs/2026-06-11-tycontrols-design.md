# TyControls 设计文档

- **日期:** 2026-06-11
- **状态:** 已通过头脑风暴确认,待用户审阅
- **定位:** 面向其他 Lazarus 开发者的可分发/可售皮肤控件组件库

---

## 1. 背景与目标

客户希望我们为 Lazarus 打造一套**支持皮肤/样式的控件集**,并将其作为产品分发/出售给其他 Lazarus 开发者。

因此本库的成功标准不是"能跑",而是"**别的开发者愿意把它拖进自己的工程并为之付费**"。这反推出几条硬约束:

- 能拖进 Lazarus 窗体设计器,设计期实时渲染(所见即所得)。
- 打成 package,安装简单。
- API 贴近 LCL 习惯,学习成本低。
- 消费这套库的开发者能为**自己的产品**轻松定制配色/皮肤(改主色、做暗色模式只需几行)。
- HiDPI(高分屏)清晰显示是硬指标。
- 跨平台一致外观作为卖点。

## 2. 范围

### 2.1 v1 交付范围

- **三层解耦架构**:控件层 / 样式引擎 / 绘图原语层。
- **样式引擎**:参数型 design tokens(palette + 语义角色)+ CSS-lite 文本 DSL(`.tycss`)+ 始终可用的 Pascal 代码 API。
- **Tier-1 控件(8 个)**:Button、Label、Edit、CheckBox、RadioButton、Panel、ComboBox、ScrollBar。
- **窗体皮肤子系统**:`TTyFormChrome` + `TTyTitleBar`,含跨平台拖动、边角缩放、最小化/最大化/还原/关闭、双击标题栏最大化、最大化避让任务栏。
- **内置主题**:Light、Dark,外加一套有辨识度的门面主题(Material-ish 或 Fluent-ish,具体风格落到实现期定,文档标 TBD)。
- **跨平台**:Windows / Linux / macOS 同等对待,Windows 作主测试目标。
- **打包**:运行期 `tycontrols.lpk` + 设计期 `tycontrols_dt.lpk`。
- **示例工程 + 文档**(上手指南、DSL 规范、API 说明)。

### 2.2 非目标(本次不做)

- 完整通用 CSS 实现(后代/子选择器、specificity 级联)。
- QML/WinUI 式控件模板引擎(重定义控件内部视觉结构)。
- 位图皮肤包(整包预渲染图)作为**主**授权方式——仅作 `.tycss` 内可嵌入的 9-slice 选项保留。
- 状态过渡动画(hover 渐隐等)。

### 2.3 Tier-2 已知缺口(显式记录,避免被误认为"已覆盖")

窗体子系统在 v1 用**跨平台手动实现**,换来一致外观,但牺牲以下原生窗口行为,留作 Tier-2 native 增强层逐步补回:

- Windows Aero Snap(贴边分屏)。
- 无边框窗口的原生投影阴影。
- macOS 红绿灯(交通灯)按钮。
- 跨屏移动时的 DPI 切换细节。

## 3. 整体架构:三层解耦

```
┌─────────────────────────────────────────────────────────────┐
│  控件层  TTyButton / TTyEdit / TTyCheckBox / TTyTitleBar …   │
│  - 继承 LCL 基类,镜像 LCL 属性名(Caption/Enabled/OnClick)  │
│  - 自己不画,只声明「我是什么类型 + 当前什么状态」           │
└───────────────┬─────────────────────────────────────────────┘
                │ 查询 ResolveStyle(typeKey, styleClass, stateSet)
┌───────────────▼─────────────────────────────────────────────┐
│  样式引擎  TTyStyleController(非可视组件)                   │
│  - CSS-lite 解析器 → 样式模型(palette + 类型×变体×状态×属性) │
│  - 把 (类型,变体,状态集) 解析合并成一个属性集 TTyStyleSet    │
│  - 唯一真相;运行期/设计期可热切换主题,变更广播 Invalidate  │
└───────────────┬─────────────────────────────────────────────┘
                │ 属性集(颜色/圆角/渐变/边框/字体/9宫格…)
┌───────────────▼─────────────────────────────────────────────┐
│  绘图原语  TTyPainter(封装 BGRABitmap)                      │
│  - FillRoundRect / Border / Gradient / Shadow / NineSlice /  │
│    DrawText / DrawGlyph                                       │
│  - 控件只调它,绝不直接碰 BGRA → 后端真正可替换               │
└─────────────────────────────────────────────────────────────┘
```

**核心不变量:控件不知道颜色,引擎不知道怎么画,Painter 不知道有控件。** 三层各自能独立测试、独立替换。这条边界是整库可维护性的命根子,任何 PR 都不得跨层穿透(例如控件里直接写死颜色、或直接调 BGRA)。

## 4. 绘图原语层:TTyPainter

- **职责**:把"属性集 + 矩形 + PPI"翻译成像素;是唯一接触 BGRABitmap 的地方。
- **后端**:BGRABitmap(矢量、抗锯齿、alpha 混合、HiDPI 友好)。
- **接口(初版)**:
  - `BeginPaint(ACanvas; const ARect; APPI)` / `EndPaint`(把离屏 BGRABitmap blit 回控件 Canvas)。
  - `FillRoundRect(rect, radius, fill)`,`fill` 支持纯色与 linear-gradient。
  - `StrokeBorder(rect, radius, color, width)`。
  - `DropShadow(rect, radius, color, blur, offset)`。
  - `NineSlice(image, rect, insets)`(9-slice 贴图,供嵌入位图皮肤用)。
  - `DrawText(rect, text, font, color, align, ellipsis)`。
  - `DrawGlyph(rect, glyph, color)`(系统按钮图标等,矢量绘制)。
- **HiDPI**:所有长度入参以 96dpi 逻辑像素表达,Painter 内部按 `APPI` 缩放;矢量绘制保证清晰。

## 5. 样式引擎

### 5.1 样式模型(内存中的唯一真相)

- **Palette / design tokens**:语义角色集合,如 `--accent`、`--surface`、`--on-surface`、`--border`、`--danger`、`--radius`、`--spacing`。一套皮肤换 palette 即可派生亮/暗/品牌色。
- **样式模型结构**:`typeKey → { base: 属性集, variants: {name → 属性集}, states: {state → 属性集} }`。
- **解析合并(ResolveStyle)**:给定 `(typeKey, styleClass, stateSet)`,按固定优先级合并出最终 `TTyStyleSet`:
  1. `base`(Normal 基线)
  2. 命中的 `variants`(命名变体,如 `primary`)
  3. 叠加态 `:hover` / `:focus`
  4. 覆盖态 `:active`(pressed)
  5. 最高优先 `:disabled`
- **代码 API**:`TTyStyleSet`/palette 可纯代码构建,不依赖任何文件——支持"纯代码主题"。

### 5.2 CSS-lite DSL(`.tycss`)规范

**词法**:`/* */` 注释;标识符;颜色 `#rgb` / `#rrggbb` / `#rrggbbaa`;长度 `12px`;百分比 `8%`;字符串;函数调用。

**语法**:
```
规则      = 选择器 "{" 声明* "}"
选择器    = 类型名 [ "." 变体名 ] [ ":" 状态名 ]      // 三者可组合,如 TyButton.primary:hover
声明      = 属性名 ":" 值 ";"
变量块    = ":root" "{" ("--" 名 ":" 值 ";")* "}"
```

**选择器档位(CSS-lite,锁定)**:仅支持
- 类型选择器:`TyButton`
- 命名变体:`TyButton.primary`(精确匹配,空格分隔可多变体)
- 状态伪类:`:hover` / `:active`(pressed)/ `:focus` / `:disabled`
- 三者组合:`TyButton.primary:hover`

**明确不支持**:后代/子/兄弟组合器、通配符、specificity 级联。匹配是"精确键 + 固定优先级合并",无需通用选择器引擎。

**变量与函数**:`:root` 定义全局变量;`var(--x)` 引用;函数 `lighten(c, %)` / `darken(c, %)` / `alpha(c, a)` / `mix(c1, c2, %)`。

**支持的属性(初版)**:`background`(纯色 / `linear-gradient(...)`)、`color`、`border-color`、`border-width`、`border-radius`、`padding`、`font-family`、`font-size`、`font-weight`、`opacity`、`shadow`、`background-image`(9-slice:`url(...) slice(上 右 下 左)`)。

**示例**:
```css
:root {
  --accent:  #3B82F6;
  --surface: #1E1E1E;
  --radius:  6px;
}
TyButton {
  background: var(--surface);
  border-radius: var(--radius);
  color: #FFFFFF;
}
TyButton.primary  { background: var(--accent); }
TyButton:hover    { background: lighten(--surface, 8%); }
TyButton:active   { background: darken(--surface, 6%); }
TyButton:disabled { opacity: 0.5; }
```

### 5.3 TTyStyleController(编排组件)

- 非可视组件,持有当前主题(palette + 已解析样式模型)。
- 提供全局默认实例;也可在某窗体上放置实例做局部覆盖。
- `LoadFromFile(.tycss)` / `LoadFromCode(...)`;支持热重载:文件或主题变更 → 广播 → 所有挂载控件 `Invalidate`(运行期与设计期均生效)。

## 6. 控件层

### 6.1 基类

- `TTyStyleable`(共享行为/接口):暴露 `typeKey`、`StyleClass`(命名变体,如 `'primary danger'`)、当前 `state`;在 `Paint` 里 `ResolveStyle` 后用 `TTyPainter` 绘制;监听 Controller 变更。
- `TTyGraphicControl`(继承 `TGraphicControl`):轻量、不可聚焦(Label、Panel)。
- `TTyCustomControl`(继承 `TCustomControl`):可聚焦、有窗口句柄(Button、Edit、ComboBox…)。

### 6.2 API 约定

- 属性名镜像 LCL:`Caption / Color / Enabled / Font / Align / Anchors / OnClick …`,让消费者近似 `TButton → TTyButton` 直接替换,零学习成本。
- 额外公共属性:`StyleClass`(命名变体)、可选关联 `StyleController`。

### 6.3 状态

每控件维护状态集:`Normal / Hover / Pressed(:active) / Focused / Disabled`,可叠加(如 Focused+Hover),按 5.1 的优先级合并。

### 6.4 Tier-1 控件清单(8 个)

Button、Label、Edit、CheckBox、RadioButton、Panel、ComboBox、ScrollBar。

### 6.5 HiDPI

所有长度令牌按窗体 PPI 缩放(`Scale96ToFont` 等),BGRA 矢量绘制天然清晰。

## 7. 窗体皮肤子系统

### 7.1 TTyFormChrome(非可视组件,拖到普通 TForm 上)

- 运行期把 `Form.BorderStyle := bsNone`,注入 `TTyTitleBar` 停靠顶部,接管窗口行为。
- **优点:消费者无需改窗体祖先类,plain TForm 即可用**,接入摩擦最低(类似 AlphaControls/rmControls 的"皮肤窗体"思路)。
- 接管的窗口行为(v1,跨平台手动实现):
  - 标题区拖动移动(手动跟随 `Left/Top`)。
  - 8 方向边角缩放(手动靠边命中检测 + `SetBounds`)。
  - 最小化 / 最大化 / 还原 / 关闭。
  - 双击标题栏最大化。
  - 最大化用 `Screen.WorkAreaRect` 避让任务栏。

### 7.2 TTyTitleBar(自绘控件)

- 含 app icon、caption、系统按钮(min/max/close)。
- 系统按钮做成独立控件类型 `TyCaptionButton` + 变体 `.close` / `.min` / `.max`,因此样式写成 `TyCaptionButton.close:hover`,落在"类型+变体+状态"档位内,**不需要后代选择器**(与 §5.2 的 CSS-lite 约束一致)。
- 标题栏本体与系统按钮全部由 `.tycss` 驱动,走同一套 Painter,**零架构例外**。

### 7.3 设计期表现

- 设计器内 WYSIWYG 只能尽力近似(设计器仍显示原生框);完整自绘窗框在运行期呈现——此为该类皮肤库通例,文档需向使用者说明。

## 8. 内置主题

`Light`、`Dark` 两套必做;再加一套有辨识度的门面主题(Material-ish vs Fluent-ish,实现期定,文档标 TBD)。三套共用同一套令牌体系,证明"换 palette 即换肤"。

## 9. 设计期集成

- `Register` 把控件注册到组件面板 "TyControls" 分页。
- `StyleClass` 提供属性编辑器下拉(列出当前主题已声明的变体)。
- 设计期可选当前预览主题。
- 设计期单独打在 `tycontrols_dt.lpk`,依赖 LazIDEIntf,避免运行期库牵连 IDE 依赖。

## 10. 打包与工程结构

```
/source        运行期单元(包入口 + painter + style + controls + form)
/design        设计期注册 + 属性编辑器
/themes        light.tycss / dark.tycss / showcase.tycss
/examples      demo 工程(覆盖全部控件 + 主题切换 + 自绘窗框)
/docs          DSL 规范 / 上手指南 / API 说明
/tests         FPCUnit 单测
tycontrols.lpk        (运行期,仅依赖 BGRABitmap)
tycontrols_dt.lpk     (设计期,依赖 LazIDEIntf)
```

- 组件前缀 `TTy`;主题文件后缀 `.tycss`。
- 目标:Lazarus 3.x / FPC 3.2.2+,只用稳定特性。
- 运行期唯一第三方依赖:BGRABitmap。

## 11. 测试策略

三层各自可独立测试,这是三层解耦的直接红利:

- **样式引擎(最易测,纯数据无 UI)**:CSS-lite 解析的单元测试(词法/语法/错误恢复)、变量与函数求值、`ResolveStyle` 合并优先级。用 FPCUnit。
- **绘图原语**:`TTyPainter` 渲染到离屏 BGRABitmap,做快照/像素断言。
- **控件**:状态机迁移、属性→typeKey/StyleClass 映射、Controller 变更重绘。
- **跨平台**:Windows / Linux / macOS 编译 + 渲染快照对比。
- **示例工程**:作为人工冒烟,覆盖全部控件、主题热切换、自绘窗框拖动/缩放/最大化。

## 12. 成功标准

- 8 个 Tier-1 控件 + 窗体子系统在三平台编译运行,HiDPI 清晰。
- 开发者能用 **< 10 行代码**切换 Light/Dark 或改主色。
- `.tycss` 热重载即时生效(运行期与设计期)。
- 控件拖进设计器即用,设计期实时渲染。
- 文档 + 可运行 demo 工程齐全。

## 13. 决策记录(锁定表)

| 维度 | 决策 |
|---|---|
| 定位 | 卖给其他 Lazarus 开发者的可分发组件库 |
| 渲染后端 | BGRABitmap |
| 架构 | 三层解耦:控件 / 样式引擎 / TTyPainter |
| 主题构成 | 参数型 design tokens(palette + 语义角色) |
| 主题格式 | CSS-lite(`.tycss`):类型+变体+状态伪类+变量,无后代/specificity |
| 代码 API | 始终提供,可纯代码建主题 |
| v1 控件 | Tier-1 共 8 个 |
| 窗体皮肤 | v1 含自绘标题栏(`TTyFormChrome` + `TTyTitleBar`),原生级窗口行为留 Tier-2 |
| 平台 | 跨平台同等,Windows 主测 |
| 内置主题 | Light + Dark + 门面主题(风格 TBD) |
| 版本目标 | Lazarus 3.x / FPC 3.2.2+ |
| 命名/打包 | 前缀 `TTy`,运行期 `tycontrols.lpk` + 设计期 `tycontrols_dt.lpk` |
| 位图皮肤 | 仅作 `.tycss` 内可嵌入 9-slice 选项,非主路 |
| 动画 | v1 不做(Tier-2 可选) |

## 14. 未来方向(Tier-2 及以后)

- 窗体 native 增强层:Aero Snap、原生阴影、macOS 红绿灯、跨屏 DPI。
- Tier-2 控件:ListBox、TrackBar/Slider、ProgressBar、ToggleSwitch、GroupBox、TabControl。
- Tier-3 重控件:Grid/DataView、TreeView、Menu、ToolBar、Calendar。
- 状态过渡动画。
- 位图皮肤包导入器(把外部整包图转成内嵌 9-slice 主题)。
- 门面主题风格最终定稿(Material-ish vs Fluent-ish)。
