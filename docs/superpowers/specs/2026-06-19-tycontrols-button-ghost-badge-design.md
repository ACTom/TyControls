# TyControls 按钮增强设计：Ghost 变体 + 选中态 + 角标 + 动态 StyleClass 编辑器

- 日期：2026-06-19
- 状态：设计已批准（待菜单 session 合并后实施）
- 范围：`TTyButton` 视觉增强 + CSS 引擎新增一个伪状态 + 设计期 StyleClass 编辑器改造

---

## 1. 背景与目标

用户希望按钮支持两类新能力，并顺带修复一个设计期编辑器的缺陷：

1. **Ghost（透明）按钮 + 选中态**：类似 VS Code 活动栏——平时按钮透明无边框，仅在 **hover / 点击(active) / 选中(selected)** 时显示底色与边框。其中"选中"是一个**常驻状态**，区别于瞬时的 hover/active。
2. **角标（badge）**：按钮上叠加一个数字角标（如未读数 `2`、`1`）。仅显示数字，`>99` 显示 `99+`。角标可主题化（CSS 自定义）。
3. **设计期 StyleClass 下拉修复**：当前 Object Inspector 的 StyleClass 下拉把 `primary/danger/close/min/max` 写死，对**所有**控件都弹同一份（`close/min/max` 其实是 `TyCaptionButton` 的变体，对可拖放控件根本不适用）。应改为**按选中控件的 typeKey 从当前主题动态读取**。

核心原则（用户硬性要求）：**所有视觉值必须由主题令牌（token）驱动，绝不在控件代码里写死颜色/尺寸。** 本设计的所有可见样式都落在 `.tycss` / 内置主题里。

---

## 2. 现状摘要（实现锚点）

- 状态枚举 `TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled)`，集合 `TTyStateSet`，定义在 `source/tyControls.Types.pas`。
- 伪类→状态映射在 `TTyCssParser.PseudoToState`（`source/tyControls.Css.Parser.pas`）：`hover/active/focus/disabled`。选择器文法仅支持 `Type.variant:state`，**无** `::pseudo-element`。
- 状态应用顺序在 `TTyStyleModel.ResolveLayer` 的常量 `cStateOrder: array[0..3] of TTyState = (tysHover, tysFocused, tysActive, tysDisabled)`（后应用者按属性覆盖前者）。
- `CurrentStates` 在 `source/tyControls.Base.pas`：`TTyCustomControl.CurrentStates` 计算 hover/active/focused/disabled；`disabled` 时**提前返回**只含 `tysDisabled`。
- 子元素走**独立 typeKey** 的既有模式：`TyProgressFill / TyTrackThumb / TyToggleKnob / TyListItem / TyMenuItem / TyTextSelection` 等，由控件 `ActiveController.Model.ResolveStyle('TyXxx', ...)` 解析后自绘。**角标沿用这一模式，无需改 parser。**
- `TTyButton`（`source/tyControls.Button.pas`）是 `TTyCustomControl`，`RenderTo` 里画 frame + 居中 caption；已有 hover 背景淡入动画（`TTyAnimator`，约 120ms，`teEaseOutCubic`）。当前淡入混色只解析 `[tysNormal]` 与 `[tysHover]` 两套样式。
- `TyLerpColor → TyMix`（`source/tyControls.Css.Values.pas:128`）**会插值 alpha 通道**，因此"透明纯色 → 不透明纯色"的 alpha 淡入可直接复用现有混色路径。
- 画笔 `TTyPainter`（`source/tyControls.Painter.pas`）已有 `FillBackground`（圆角/胶囊）、`DrawText`（居中、内部用 `FBmp.TextSize` 测量）。**缺**一个对外的文本测宽方法。
- 内置默认皮肤 `source/tyControls.DefaultTheme.pas` 由 `scripts`（`gen-defaulttheme.ps1`，见仓库脚本）**从 `themes/light.tycss` 生成**，并由 `tests/test.defaulttheme.pas` 同步校验字节一致；**禁止手改**，改 `light.tycss` 后重生成。
- 6 个内置主题各自独立定义 `TyButton` + `.primary` + `.danger`（无 `@import` 复用按钮块）：`themes/{light,dark,green,showcase,system,auto}.tycss`。
- 设计期编辑器 `designtime/tyControls.Design.pas`：`TTyStyleClassPropertyEditor.GetValues` 硬编码列表；属性编辑器具 `paValueList + paMultiSelect`（**可编辑下拉**：列表只是建议，用户仍可手打任意 class）。

---

## 3. 功能 A：Ghost 变体 + 选中态

### A1. 引擎：新增 `:selected` 伪状态

- **`tyControls.Types`**：在 `TTyState` **末尾追加** `tysSelected`，即
  `TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled, tysSelected)`。
  > 追加在末尾而非中间，保持现有枚举序号不变，避免影响任何序号相关逻辑与 golden 基线。枚举序号**不**决定级联顺序（由 `cStateOrder` 决定）。
- **`tyControls.Css.Parser`**：`PseudoToState` 增加 `selected → tysSelected`，并加别名 `checked → tysSelected`（两者等价）。
- **`tyControls.StyleModel`**：`cStateOrder` 扩为 5 元素并把 selected 放**最前**：
  `(tysSelected, tysHover, tysFocused, tysActive, tysDisabled)`。
  selected 作为"常驻底层"最先应用，使 hover/active 的瞬时反馈能按属性覆盖它（文法不支持 `:selected:hover` 组合选择器，组合态完全靠级联逐属性合并实现）。`disabled` 仍最后、最高优先级。

### A2. 控件：`TTyButton.Down` 属性

- 新增 published `Down: Boolean`（默认 `False`）。setter：值变更 → `Invalidate`（不触发 `OnClick`）。
- override `CurrentStates`：`inherited` 之后，若 `Enabled and FDown` 则 `Include(Result, tysSelected)`；并从结果中去掉 `tysNormal`（与既有"有任一非 normal 态则不含 normal"的语义一致）。`disabled` 时 `inherited` 已提前返回只含 `tysDisabled`，selected 不叠加（disabled 优先，符合既有设计）。
- **互斥分组**：本期不内建 `GroupIndex`/单选。VS Code 活动栏的"同组仅一个选中"由应用在 `OnClick` 里自行切换各按钮 `Down`。`GroupIndex` 与"点击自动 toggle"列为未来扩展（见 §10）。

### A3. 动画修正：选中态下的 hover 淡入取色

当前 `RenderTo` 的混色固定解析 `[tysNormal]`/`[tysHover]`。对选中的 ghost 按钮，静止态应是 selected 而非 normal，否则 hover 淡入会从错误底色起步。

- 改为：静止态样式 = `ResolveStyle(typeKey, StyleClass, CurrentStates - [tysHover])`，悬停态样式 = `ResolveStyle(typeKey, StyleClass, CurrentStates + [tysHover])`，在二者背景间按 `Eased` 插值。
- 仅当两端背景均为 `tfkSolid` 时插值（与现状一致；ghost 的透明底也是 `tfkSolid`，故 alpha 淡入有效）。非纯色（渐变/图片）端退化为瞬时切换（与现状一致）。
- 该改动对非 ghost、非选中按钮的可见结果不变（`CurrentStates - [tysHover]` 在那种情形即 `[tysNormal]`、`+[tysHover]` 即 `[tysHover]`），故既有 golden/逐像素测试不受影响。

### A4. 主题：内置 `ghost` 变体

在 `themes/light.tycss` 增加（再生成 `DefaultTheme.pas`），并按各主题 token 习惯同步到其余 5 个主题：

```css
TyButton.ghost {
  background: alpha(var(--surface-hover), 0);   /* 透明但仍是纯色 → alpha 淡入有效 */
  color: var(--on-surface);
  border-color: alpha(var(--border), 0);        /* 透明边框：保留边框宽度，hover 时不跳尺寸 */
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 6px;
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}
TyButton.ghost:hover    { background: var(--surface-hover); border-color: var(--input-border-hover); }
TyButton.ghost:active   { background: var(--surface-active); }
TyButton.ghost:selected { background: var(--surface-active); border-color: var(--accent); }
TyButton.ghost:focus    { outline: 2px var(--focus-ring); }
TyButton.ghost:disabled { opacity: var(--disabled-opacity); }
```

- 设计要点：base 用 `alpha(<令牌>, 0)` 得到"透明纯色"，使 hover 背景 alpha `0→255` 平滑淡入；边框同理透明但**保留 `border-width`**，避免 hover 时 1px 尺寸跳动。
- 各主题按自身 token 习惯落地（如 `green` 用 `darken(--surface, n%)`/字面 `0.5`，`showcase` 的 hover 用渐变——ghost 块保持简洁一致，hover/active 用该主题已有的 surface 令牌即可，不必引入渐变）。
- 用法：`Btn.StyleClass := 'ghost';`，选中由 `Btn.Down := True;` 驱动。

---

## 4. 功能 B：角标（badge）

### B1. 控件新增成员（`TTyButton`）

| 成员 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `ShowBadge` | `Boolean` | `False` | 角标总开关；`False` 时完全不绘制、不调用事件 |
| `BadgeValue` | `Integer` | `0` | 角标数值 |
| `BadgePosition` | `TTyBadgePosition` | `bpBottomRight` | 角标所在角：`bpTopLeft / bpTopRight / bpBottomLeft / bpBottomRight`；默认右下（与 VS Code 活动栏一致） |
| `OnBadgeDisplay` | `TTyBadgeDisplayEvent` | `nil` | 显示前的用户钩子，可改文本/决定是否显示 |

类型声明（建议放 `tyControls.Button` 或 `tyControls.Types`）：

```pascal
TTyBadgePosition = (bpTopLeft, bpTopRight, bpBottomLeft, bpBottomRight);
TTyBadgeDisplayEvent = procedure(Sender: TObject; AValue: Integer;
  var AText: string; var AVisible: Boolean) of object;
```

`ShowBadge / BadgeValue / BadgePosition` 的 setter 均在值变更后 `Invalidate`。

### B2. 显示规则

1. `ShowBadge = False` → 不绘制（事件都不调用）。
2. `ShowBadge = True`：
   - 先算默认：`AText := IfThen(AValue > 99, '99+', IntToStr(AValue))`；`AVisible := True`（**默认显示，含 `0`**）。
   - 若 `Assigned(OnBadgeDisplay)` 则调用之，允许用户改写 `AText` 与 `AVisible`（如 `AValue < 3` 时置 `AVisible := False`，或自定义文本）。
   - 最终当 `AVisible and (AText <> '')` 时绘制。

> 设计取舍：是否在值小时隐藏属"业务策略"，因人而异——故默认显示、由事件让用户完全自定义（包括"0 不显示""<3 不显示""显示成别的文案"）。

### B3. `TyBadge` typeKey 与主题

沿用独立 typeKey 子元素模式（零 parser 改动）。在 `light.tycss`（+ 同步其余主题、再生成 DefaultTheme）增加：

```css
TyBadge {
  background: var(--accent);          /* 默认蓝，与 VS Code 活动栏角标一致；可主题化 */
  color: var(--on-accent);
  border-radius: var(--radius-round); /* 胶囊 */
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-bold);
  padding: 0px 4px;                   /* 上下 0、左右 4：胶囊横向留白 */
}
```

> `padding: 0px 4px` 经现有 `ParsePadding` 两值解析为 top/bottom=0、left/right=4，可用。

### B4. 渲染细节

- 画笔新增对外测宽方法：`function TTyPainter.TextWidth(const AText, AFontName: string; AFontSizeLogical, AWeight: Integer): Integer;`（内部 `TyConfigureTextFont` + `FBmp.TextSize(AText).cx`），与 `DrawText` 同一字体配置，保证测宽=绘制宽。
- 在 `TTyButton.RenderTo` 末尾（caption 之后、`EndPaint` 之前）：
  1. 若不满足 §B2 显示条件则跳过。
  2. `BadgeS := ResolveStyle('TyBadge', '', [])`。
  3. 胶囊高度 ≈ 文本字高 + 上下 padding（按 `BadgeS.FontSize`/缩放计算）；宽度 = `max(高度, 文本测宽 + 左右 padding)`（单字符≈正圆，多字符成胶囊）。
  4. 按 `BadgePosition` 把胶囊贴到对应角，并内缩约 2px（逻辑 px，经 `Scale`）。**窗口控件不能画到自身边界外，故角标内嵌于按钮内**；若按钮过小则裁剪（可接受）。
  5. 用 `BadgeS` 画圆角背景（`FillBackground`）+ 居中 `DrawText`。圆角半径取 `TyClampRadius(主题 border-radius, 胶囊半高)`——既尊重更小的主题半径，又保证小角标恒为胶囊/正圆、永不超过半高。背景填充令牌/文字色全部来自 `BadgeS`（主题驱动）。
- 角标独立于按钮 hover/active/selected 态，恒按 `TyBadge` 静止样式绘制。

---

## 5. 功能 C：设计期 StyleClass 编辑器（按 typeKey + 主题动态）

### C1. Model 新增 API

```pascal
{ 收集 ATypeKey 在 base 层 + user 层定义过的、去重的 variant（.class，忽略 :state）。
  供设计期 StyleClass 下拉精确列出"该控件类型在当前主题下可用的 class"。 }
procedure TTyStyleModel.GetVariantsForType(const ATypeKey: string; AList: TStrings);
```

实现：扫描 `FBaseRules` 与 `FRules`，对 `SameText(TypeName, ATypeKey)` 且 `Variant <> ''` 的条目收集 `Variant`，大小写不敏感去重（手动 `SameText` 比较或 `AList` 设 `CaseSensitive := False`/`Sorted`），稳定排序便于显示。

### C2. 编辑器改造（`designtime/tyControls.Design.pas`）

`TTyStyleClassPropertyEditor.GetValues` 改为：

1. `comp := GetComponent(0)`；若 `Supports(comp, ITyStyleable, sty)` 取 `typeKey := sty.GetStyleTypeKey`，否则回退当前硬编码（或空）。
2. 取该控件的 model：若 `comp` 的 published `Controller <> nil` 用 `Controller.Model`，否则用 `TyDefaultController.Model`。
3. `model.GetVariantsForType(typeKey, list)`，逐项 `Proc(list[i])`。

### C3. 行为说明

- **按控件**：`TTyButton` 只列 `primary / danger`（及新增 `ghost`）；`Edit/Panel` 无 variant → 空；`close/min/max`（`TyCaptionButton`）不再串台。
- **主题动态**：设计期若窗体上有 `TTyStyleController` 且设了 `ThemeFile`，其 setter 在 .lfm 流式载入时即 `LoadTheme` 把主题灌进 `FModel`——主题自定义 class（如 `TyButton.cta`）自动出现在下拉。未挂 controller 的控件走默认 controller，列出内置层 class（始终可用）。
- **零维护**：以后任何主题/控件新增 class，下拉自动反映；`ghost` 加进主题后会自动出现在按钮下拉里（正好验证机制）。
- 下拉仍 `paValueList`（可编辑）：列表只是建议，用户仍可手打任意 class。
- **边界**：用默认 controller 的控件设计期仅见内置 class（自定义主题未注入默认 model）；要见自定义 class 即在窗体放 `TTyStyleController` 并设 `ThemeFile`（推荐用法）。"不挂 controller 也能按某主题文件提示"列为未来扩展（YAGNI）。
- 多选不同类型控件时取 `GetComponent(0)` 的 typeKey（标准行为）；跨类型取交集列为可选优化。

---

## 6. 涉及文件清单

**源码**
- `source/tyControls.Types.pas` — `TTyState` 追加 `tysSelected`；（可选）`TTyBadgePosition`。
- `source/tyControls.Css.Parser.pas` — `PseudoToState` 加 `selected`/`checked`。
- `source/tyControls.StyleModel.pas` — `cStateOrder` 扩 5 元素；新增 `GetVariantsForType`。
- `source/tyControls.Base.pas` — 仅当需要：确认 `CurrentStates` 语义（实际 selected 注入在 Button 的 override 内）。
- `source/tyControls.Button.pas` — `Down` + override `CurrentStates`；`ShowBadge/BadgeValue/BadgePosition/OnBadgeDisplay`；`RenderTo` 角标绘制 + 动画取色修正；类型声明。
- `source/tyControls.Painter.pas` — 新增 `TextWidth`。
- `source/tyControls.DefaultTheme.pas` — **由 light.tycss 重生成**（勿手改）。

**主题**
- `themes/light.tycss`（权威源）、`themes/{dark,green,showcase,system,auto}.tycss` — 各加 `TyButton.ghost` 全套态 + `TyBadge`。

**设计期**
- `designtime/tyControls.Design.pas` — 动态 `GetValues`。

**文档**
- `docs/controls/button.md` — Down/selected、ghost 用法、角标属性/事件/规则、`TyBadge` 主题键。
- （可能）`docs/tycss-reference.md` — `:selected` 伪状态、`TyButton.ghost`、`TyBadge` 键。

**示例（避开菜单 session）**
- `examples/button/umain.pas` — ghost+选中、角标演示。**不**改 `examples/demo/*`（菜单 session 在用）。

**测试**：见 §7。

---

## 7. 测试计划

- **Parser**：`:selected`/`:checked` → `tysSelected`；未知伪类仍报错。
- **级联**：`cStateOrder` 含 selected；selected+hover 组合时逐属性合并结果正确（hover 覆盖 selected 的冲突属性、保留 selected 独有属性如 border-color）。
- **Button.Down**：`Down=True` 使 `CurrentStates` 含 `tysSelected`；`disabled` 时仍只 `tysDisabled`（Down 不叠加）。
- **Ghost 像素**：ghost 各态（normal 透明、hover/active/selected 显边底）逐像素；hover 淡入中间帧 alpha 插值（headless 下瞬时吸附，保证确定性）。
- **角标**：开关（False 不画）、`99+` 截断、默认显示 `0`、`OnBadgeDisplay` 改文本/置 `AVisible:=False` 隐藏、四个 `BadgePosition` 位置正确、`TyBadge` 主题色生效。
- **GetVariantsForType**：对 `TyButton` 返回含 `primary/danger/ghost` 去重集；对无变体 typeKey 返回空；加载自定义主题后含其 class。
- **同步**：`test.defaulttheme` 仍字节一致（改 light.tycss 后重生成）。
- **回归**：现有 golden / 逐像素按钮测试不破（§A3 已论证非 ghost 路径取色不变）。

---

## 8. 与菜单 session 的协调（排序）

- 菜单 session 正在改 `source/tyControls.Menu.pas`、`examples/demo/demo.lpi`、`examples/demo/mainform.lfm`。本设计**不触碰**这些文件。
- 唯一潜在交叠：`source/tyControls.Types.pas`（菜单可能加菜单相关类型）与主题文件（菜单加了 `TyMenu*` 键）。本设计对 Types 仅在枚举**末尾追加**一个值、对主题仅**新增** `TyButton.ghost`/`TyBadge` 块，均为追加、冲突面小且易合并。
- **实施时机**：等菜单 session 合并后再开工，先 `git pull`/rebase 到含菜单改动的分支，再落地本设计。

---

## 9. 非目标（YAGNI）

- 角标内容不支持任意文本/图标，仅数字（`>99 → 99+`）+ 事件改写文本。
- 角标不支持 per-instance `StyleOverride`（只走 `TyBadge` 主题键/全局自定义）。
- 不内建按钮 `GroupIndex`/单选互斥、不内建点击自动 toggle。
- 设计期编辑器不内建"独立主题文件路径"提示源（靠 controller 的 `ThemeFile`）。

## 10. 未来扩展（备忘）

- `GroupIndex` + 点击自动 toggle，做成真正的单选工具栏。
- 角标支持小圆点（无数字）模式 / 文本角标。
- 设计期"项目级设计主题路径"，让无 controller 的控件也能提示自定义 class。
- 跨类型多选时下拉取 typeKey 交集。

## 11. 风险与开放问题

- `cStateOrder` 改 5 元素需同步检查所有遍历该数组的代码（目前仅 `ResolveLayer`）。
- ghost 在 `showcase`（渐变 hover）主题下：ghost 块用纯色 surface 令牌即可，不必渐变；若后续要渐变 hover，淡入会退化为瞬时（可接受）。
- 角标在极小按钮上的裁剪行为（接受裁剪，不做自动放大按钮）。
- 设计期能否在 .lfm 载入时拿到已 `LoadTheme` 的 controller model：依赖 LCL 流式调用 published setter 的标准行为；实施时以一个真实 IDE 验证（属系统级、headless 无法覆盖）。
