# TyControls 控件完善程序 · Phase 0 设计文档 — 横切基线(主题可定制的圆角 + 焦点环 + 键盘激活 + 基线属性)

- **日期:** 2026-06-14
- **前置:** `main`(v1–v1.6 正式版 + 内部 v1.7–v1.12 + 当前 TTyMemo WordWrap 工作;~600 测试)。
- **定位:** "完善现有控件"是一个**多-spec 程序**;本文是它的**第一个 spec**。后续按批逐控件补"高频专属属性 + 视觉细节"(批① 文本类、批② 选择类、批③ 容器/导航、批④ 视觉扫尾),各自独立 spec→plan→实现。
- **执行约定:** 沿用项目惯例 —— 几何/像素测试钉 `PPI=96`;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests -a --format=plain`;现有测试保持全绿、不改既有测试的语义(A 方案**有意**改变 titlebar/tab 渲染的像素基线测试除外,见 §6);`examples/demo/mainform.lfm` + `demo.lpi` 若有用户未提交改动则勿碰。

---

## 1. 动机

审计(2026-06-14)确认:库功能已远超原 v1 范围,但存在两类**横切短板**,且都因"在控件代码里写死视觉值/缺少基础设施"而无法靠单个控件修复:

1. **默认主题视觉不一致。** `TyTitleBar`、`TyTab`、`TyCaptionButton` 呈直角,而 `TyPanel`/`TyTabControl`/内容页用 `var(--radius)` 圆角;主题里还散落硬编码 `3px/4px/8px/12px`。根因:渲染原语 `FillBackground/StrokeBorder` **只支持四角统一圆角**,无法表达"标题栏/页签只圆上面两角、下边与内容齐平",于是主题只能把它们设成方角回避。
2. **缺少统一的交互基线。** 任何控件**都没有焦点环**(键盘用户无聚焦反馈);键盘激活不一致(CheckBox/RadioButton 有 `TabStop` 却无 `Space` 处理,Button 无 `Space/Enter`);`Enabled/Font/Hint/TabOrder` 等基线属性在各控件 published 不齐(Panel/GroupBox/ComboBox 缺 `Font` 等)。

## 2. 核心原则(用户指令)

**控件代码不写死任何视觉值。** 圆角、焦点环的宽度/颜色/作用角一律由**主题令牌 / CSS 属性**表达。默认三套主题 + 内置兜底烘焙"**A · 全局统一圆角**";偏好直角或其它风格的买家通过自定义 `.tycss` 覆盖(改 `--radius: 0`、给某 typeKey 写 `border-radius`、或 `outline: 0` 关焦点环)即可。新增 DSL 属性一律 **纯叠加、100% 向后兼容**。

## 3. 范围(Phase 0 = 一个 spec,实现分两条工作流顺序推进)

### 工作流 A — 视觉地基(让圆角/焦点环可被主题表达)

**A1. Per-corner `border-radius`(标准 CSS)。**
- DSL:`border-radius` 接受 **1 值**(四角相同,现有写法,完全向后兼容)与 **4 值** `border-radius: <tl> <tr> <br> <bl>`(标准 CSS 顺序:左上→右上→右下→左下)。可选支持长写 `border-top-left-radius` / `border-top-right-radius` / `border-bottom-right-radius` / `border-bottom-left-radius`。
- 数据模型:`TTyStyleSet` 增 4 个角字段(`RadiusTL/TR/BR/BL: Integer`),保留现有 `BorderRadius: Integer` 作为"统一值/简写"以维持现有代码与控件直接引用(写 1 值时四角与 `BorderRadius` 同值)。`tpBorderRadius` 仍是"是否设置过圆角"的 Present 位;4 值与 1 值都置该位。`TyMergeStyleSet` 合并时整组(4 角 + 统一值)一起覆盖。
- 渲染:Painter 的圆角原语支持 per-corner —— BGRABitmap 的 `FillRoundRectAntialias` / `RoundRectAntialias` 带 `TRoundRectangleOptions`,可对单独某角用 `rr*Square` 方化。为各角不同半径,采用"按角半径选择是否方化 + 统一基准半径"的近似,或在四角半径不等时退化为路径绘制(实现细节留给 plan;**验收只要求**:`6px 6px 0 0` 渲染出"上圆下方"、`6px` 渲染出"四角圆"、`0` 渲染出"四角方")。
- 兼容:现有主题全部是 1 值 `border-radius`,渲染**逐像素不变**。

**A2. `outline` 焦点环属性。**
- DSL:`outline: <width> <color>`(空格分隔,宽度=带 `px` 长度,颜色=任意颜色表达式),可选 `outline-offset: <len>`。新增 `tpOutline` + `TTyStyleSet.OutlineColor/OutlineWidth/OutlineOffset`,加入 merge。
- 语义:焦点环**只写在 `:focus` 规则里**,因此只有控件聚焦时样式才解析出 `tpOutline`,焦点环随之出现;失焦即消失。无需控件代码判断"是否聚焦"。
- 绘制:`DrawFrame` 在描边之后,若 `tpOutline in Present` 则画焦点环。**因 painter 位图按控件自身 rect 裁剪,没有外侧空间画外环**,焦点环画在控件 rect **内侧**:在边框内由 `OutlineOffset`(默认小值,如 2 逻辑 px)起、宽 `OutlineWidth`、颜色 `OutlineColor`,圆角随 per-corner 半径内缩。
- 范围:Phase 0 用 `:focus`(任意方式聚焦即显示),确定且可像素测试;真正的"仅键盘 `:focus-visible`"(需输入模态跟踪 + 新伪类)留作后续增强,不在本 spec。

**A3. 默认主题落 A(`themes/light|dark|showcase.tycss` + `DefaultTheme.pas` 内置兜底逐字一致)。**
- 统一 `--radius` 作为常规控件圆角来源;`TyTitleBar`/`TyTab`/`TyTabControl` 顶部圆角(per-corner `<r> <r> 0 0`)、内容/面板全角、`TyCaptionButton` 顺势协调。
- 合理化散落硬编码半径;**保留有意例外**(ToggleSwitch 胶囊、TrackThumb 圆点等几何性圆角)。
- 新增 `--focus-ring` 语义令牌(色,默认 `var(--accent)`)+ 给所有**可聚焦 typeKey** 的 `:focus { outline: 2px var(--focus-ring); }`。三套主题共用同一组令牌。

### 工作流 B — 行为基线

**B1. 键盘激活**(全部带 `Enabled` 守卫,沿用 v1.5 "禁用即早退、不消费键"策略;不破坏现有 `Tab` 导航下传):
- `TTyButton`:`Space`/`Enter` → 触发 `Click`。
- `TTyCheckBox`:`Space` → 切换 `Checked`(+ `OnClick`)。
- `TTyRadioButton`:`Space` → 选中(组内方向键移动留到批②)。
- `TTyToggleSwitch`:已有 `Space`,补 `Enter`。

**B2. 统一 published 基线属性。**
- 在基类 `TTyGraphicControl` / `TTyCustomControl` 的 `published` 段集中发布 `Enabled`、`Font`、`Hint`、`ShowHint`、`TabOrder`(`TabStop` 多数控件构造时已置位,保持);所有控件继承,清理各控件里重复/遗漏的声明,补齐审计点名的缺口(Panel/GroupBox/ComboBox 缺 `Font` 等)。
- `Font` 发布在基类后,确保其 `PixelsPerInch` 仍正确参与现有度量路径(`TyConfigureTextFont`),不改度量语义。

## 4. 关键数据流与不变量

- 控件 `Paint` → `CurrentStyle`(`ResolveStyle(typeKey, StyleClass, CurrentStates)`)→ `DrawFrame(Painter, Rect, Style)`。`tysFocused` 已经在 `TTyCustomControl.CurrentStates` 中(`if Focused`),`DoEnter/DoExit` 已 `Invalidate`——**焦点环零新增状态机改动**,只是 `DrawFrame` 多画一层 + 主题多一条 `:focus` 规则。
- 三层解耦不变量保持:控件不写死圆角/焦点环值(全部来自 Style),引擎不画(只产出 `TTyStyleSet`),Painter 不知控件(只按 rect + 角半径 + 颜色画)。

## 5. 不做(Phase 0 显式排除)

- `:focus-visible`(仅键盘焦点环)与输入模态跟踪。
- 各控件的**专属**高频属性(`ReadOnly`/`MaxLength`/`PasswordChar`/`GroupIndex`/`MultiSelect`/`TabPosition`/SpinEdit 可输入 等)——属批①~④。
- 无障碍(IAccessible)、RTL、Tooltip 窗口自绘、右键菜单、光标闪烁——后续程序或独立 spec。
- `border-radius` 的百分比值、椭圆角(`/` 双半径语法);`margin`/per-side 边框/dashed-dotted——仍按 v1.6 KNOWN_GAPS 推迟。

## 6. 验收

- 现有 ~600 测试保持全绿;新增测试覆盖:
  - **DSL**:`border-radius` 1 值与 4 值解析(`tpBorderRadius` + 四角值)、长写角(若实现)、`outline`/`outline-offset` 解析、两者 merge 覆盖。
  - **Painter**:per-corner 像素探针(`6 6 0 0` 上圆下方:上角背景被圆角"切掉"、下角是方的;`0` 四方;`6` 四圆)、焦点环像素(内侧出现指定色环)。
  - **DrawFrame 探针**(复用 `TDrawFrameProbe`):`tpOutline` present 时画环、不 present 时不画。
  - **键盘激活**:Button `Space`/`Enter` 触发 `OnClick`、CheckBox/Radio `Space` 改状态、ToggleSwitch `Enter`;各自 `Enabled=False` 时为空操作(不消费键)。
  - **主题**:三套 `ResolveStyle` 对 `TyTitleBar`/`TyTab` 解析出顶部 per-corner 半径、对可聚焦 typeKey 解析出 `tpOutline`;内置兜底 `TyBuiltinThemeCss` 与 `light.tycss` 逐字一致(沿用 `test.defaulttheme` 同步断言)。
- **有意的基线更新**:A 方案改变 `TyTitleBar`/`TyTab`(及 demo 截图)的渲染——相应的既有像素测试基线一并更新并在测试注释说明;其余 typeKey 用 1 值 radius,渲染零变化。
- 构建矩阵全绿(`scripts/build-matrix.sh`);heaptrc 0 泄漏;终审通过(reviewer 跑 per-corner + 焦点环像素探针,确认非 titlebar/tab 的控件渲染零变化);`docs/tycss-reference.md` 同步新增 `border-radius` 4 值、`outline`/`outline-offset`、`--focus-ring` 令牌说明。

## 7. 兼容性与回滚

加属性是纯叠加;`border-radius` 1 值路径保持旧行为;焦点环只在主题写了 `:focus { outline }` 时出现。默认主题的视觉变化是**预期**的(项目尚无 release tag,允许改进默认观感);任何买家可用自定义 `.tycss` 完全覆盖回直角/无焦点环。回滚 = 撤销主题改动即恢复旧观感,引擎新属性不被任何规则引用即为惰性。
