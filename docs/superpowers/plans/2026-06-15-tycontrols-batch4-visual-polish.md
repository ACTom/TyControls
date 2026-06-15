# TyControls 批④ 视觉细节扫尾 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Tasks are SEQUENTIAL (shared theme files + byte-sync invariant make parallel edits unsafe).

**Goal:** 状态规则对等 + 消除 render-code 硬编码视觉常量/统一选区高亮 + 子元素圆角统一 + 子元素色策略 typeKey 化 + checkbox 选中态复活,全部令牌驱动。

**Architecture:** 主题改动落 4 源(light/dark/showcase .tycss + DefaultTheme.pas),light↔Default 逐字节;子元素经 `ActiveController.Model.ResolveStyle('<子typeKey>','',states)` 取样式(沿用 TyTrackThumb 范式)。

**Tech Stack:** Free Pascal/Lazarus LCL;CSS-lite .tycss;FPCUnit;PPI=96。

**约定:** 运行 `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`。基线 **0 failures + 15 env errors(error 1407,忽略)**。提交 `feat(tycontrols): …`。`examples/demo/*` 是用户测试台——每个任务只 stage 自己的源/主题/测试文件。

---

## 0. 铁律 · BYTE-SYNC(每个含主题改动的任务必做)

任何 `.tycss` 改动必须**同时**改 4 个文件:
1. `themes/light.tycss`(真源)
2. `themes/dark.tycss`(暗色:`darken`↔`lighten` 对调,色值用暗色基)
3. `themes/showcase.tycss`(变体:用其既有量级)
4. `source/tyControls.DefaultTheme.pas`(内置:**与 light.tycss 逐字节相同**——把同样的文本加进 Pascal 字符串常量 `TyBuiltinThemeCss` 的对应位置)

`tests/test.defaulttheme.pas::TestBuiltinMatchesLightTheme` 强制 light↔Default 一致(`NormalizeCss`=每行 TrimRight + 整体 Trim)。**每个主题任务的最后一步必须确认这条测试绿**;不一致会红。改 dark/showcase 不被该测试覆盖,但属本批要求,须一并改并人工核对。

**参考量级(light.tycss 现状):** 输入框 `:hover { border-color: darken(--border, 10%); }`;`:disabled { opacity: 0.5; }`;焦点 `outline: 2px var(--focus-ring)`;焦点边框 `border-color: var(--accent)`。dark.tycss 对应处用 `lighten(--border, …%)`;showcase 禁用 `opacity: 0.45`。

---

## Task 1: 主题1a — 给 4 控件补 :disabled

**Files:** `themes/light.tycss`、`dark.tycss`、`showcase.tycss`、`source/tyControls.DefaultTheme.pas`;Test `tests/test.defaulttheme.pas` + 一个状态解析测试单元(见下)。

- [ ] **Step 1: 失败测试**——在一个合适的样式测试单元(如 `tests/test.stylemodel.pas` 或新建 `tests/test.batch4states.pas` 并注册)加:加载内置主题,`ResolveStyle('TyScrollBar','',[tysDisabled])` 等 4 个 typeKey 解析出 `Opacity < 1.0`(`tpOpacity in Present` 且 `Opacity ≈ 0.5`)。先断言 4 个都 <1。
```pascal
procedure TestDisabledOpacityParity;
var M: TTyStyleModel; S: TTyStyleSet;
  procedure Chk(const K: string);
  begin
    S := M.ResolveStyle(K, '', [tysDisabled]);
    AssertTrue(K + ' has opacity', tpOpacity in S.Present);
    AssertTrue(K + ' opacity<1', S.Opacity < 0.99);
  end;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromString(TyBuiltinThemeCss);   // or the controller's built-in load path
    Chk('TyScrollBar'); Chk('TyTrackBar'); Chk('TyTabControl'); Chk('TyProgressBar');
  finally M.Free; end;
end;
```
  （按本仓 model 加载 API 调整：参考现有样式测试怎么实例化 `TTyStyleModel`/`TTyStyleController` 并加载内置主题；`TyBuiltinThemeCss` 在 `tyControls.DefaultTheme`。Opacity 字段名以 `TTyStyleSet` 实际为准——grep `Opacity`。）
- [ ] **Step 2: 确认失败/不编译。** `lazbuild tests/tytests.lpi`(4 typeKey 无 :disabled → opacity 不 present → 断言失败)。
- [ ] **Step 3: 实现（4 源 byte-sync）。** 在 light.tycss 各 typeKey 块后加:
  - `TyScrollBar:disabled { opacity: 0.5; }`(紧接 `TyScrollBar:active` 行后,line ~109)
  - `TyTrackBar:disabled { opacity: 0.5; }`(接 `TyTrackBar:focus` 后,line ~180)
  - `TyTabControl:disabled { opacity: 0.5; }`(接 `TyTabControl:focus` 后,line ~206)
  - `TyProgressBar:disabled { opacity: 0.5; }`(接 `TyProgressBar` 块后,line ~159)
  把**完全相同的 4 行**加进 `DefaultTheme.pas` 的 `TyBuiltinThemeCss` 对应位置(保持与 light 行序一致)。dark.tycss 同样加(opacity 与浅色同 `0.5`)。showcase.tycss 用 `opacity: 0.45`(与其现有禁用量级一致——先 grep showcase 现有 `:disabled` 确认是 0.45)。
- [ ] **Step 4: 跑。** 新用例 PASS;`TestBuiltinMatchesLightTheme` PASS(byte-sync);0 failures。
- [ ] **Step 5: Commit** `feat(tycontrols): add :disabled to ScrollBar/TrackBar/TabControl/ProgressBar (state parity)`

---

## Task 2: 主题1b — Toggle :hover、ScrollBar/TabControl :focus、List/Button/Tab :hover 边框

**Files:** 4 主题源;Test 同 batch4 状态单元。

- [ ] **Step 1: 失败测试**——解析断言:`ResolveStyle('TyToggleSwitch','',[tysHover])` 的 Background ≠ 其 normal Background;`ResolveStyle('TyScrollBar','',[tysFocused])` 有 `tpOutline`(OutlineWidth>0);`ResolveStyle('TyTabControl','',[tysFocused]).BorderColor` = accent(`#3B82F6`);`ResolveStyle('TyListBox','',[tysHover]).BorderColor` = `darken(#D1D5DB,10%)`(与 `ResolveStyle('TyEdit','',[tysHover]).BorderColor` 相等)。
```pascal
procedure TestStateRuleParity;
var M: TTyStyleModel; tog0, togH, edH, lbH, sbF, tcF: TTyStyleSet;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromString(TyBuiltinThemeCss);
    tog0 := M.ResolveStyle('TyToggleSwitch','',[]);
    togH := M.ResolveStyle('TyToggleSwitch','',[tysHover]);
    AssertTrue('toggle hover differs', togH.Background.Color <> tog0.Background.Color);
    sbF := M.ResolveStyle('TyScrollBar','',[tysFocused]);
    AssertTrue('scrollbar focus ring', (tpOutline in sbF.Present) and (sbF.OutlineWidth > 0));
    tcF := M.ResolveStyle('TyTabControl','',[tysFocused]);
    AssertTrue('tabcontrol focus border=accent', tcF.BorderColor = TyRGB($3B,$82,$F6));
    edH := M.ResolveStyle('TyEdit','',[tysHover]);
    lbH := M.ResolveStyle('TyListBox','',[tysHover]);
    AssertTrue('listbox hover border = input hover border', lbH.BorderColor = edH.BorderColor);
  finally M.Free; end;
end;
```
  （`TyRGB`/字段名按实际 API；若无 `TyRGB`,用解析出的 32 位值常量比较。）
- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现（4 源 byte-sync）。** light.tycss:
  - `TyToggleSwitch:hover { background: darken(--surface, 22%); }`(插在 `TyToggleSwitch:active` 前,line ~171;基础是 `darken(--surface,18%)`,hover 略深)
  - `TyScrollBar:focus { outline: 2px var(--focus-ring); }`(接 `TyScrollBar:active` 后)
  - `TyTabControl:focus` 改为 `{ border-color: var(--accent); outline: 2px var(--focus-ring); }`(line ~206,在原 outline 基础上加 border-color)
  - `TyListBox:hover { border-color: darken(--border, 10%); }`(接 `TyListBox` 块后,line ~144 区)
  - `TyButton:hover` 改为 `{ background: darken(--surface, 4%); border-color: darken(--border, 10%); }`(line ~25,在原 background 基础上加 border-color)
  - `TyTabControl:hover { border-color: darken(--border, 10%); }`(接 TyTabControl:focus 后)
  mirror 到 DefaultTheme.pas 逐字节;dark.tycss 用 `lighten(--surface,…)`/`lighten(--border,12%)`(对照 dark 现有输入框 hover 值取同量);showcase 用其量级。
- [ ] **Step 4: 跑。** 新用例 PASS;byte-sync PASS;现有 Button/Edit 等测试不回归(注意 TyButton:hover 现在多了 border-color——若有像素测试断言 hover 边框不变,确认是预期变化)。
- [ ] **Step 5: Commit** `feat(tycontrols): Toggle hover, ScrollBar/TabControl focus, List/Button/Tab hover-border (state parity)`

---

## Task 3: 主题2a — 新 :root 令牌 + TyTextSelection/TyTextHint/TyTabClose typeKey

**Files:** 4 主题源;Test batch4 状态单元。

- [ ] **Step 1: 失败测试**——`ResolveStyle('TyTextSelection','',[]).Background.Color` = accent@30%(alpha 字节 ≈ $4D);`ResolveStyle('TyTextHint','',[]).TextColor` = on-surface@50%;`ResolveStyle('TyTabClose','',[]).Background` present。断言这三个 typeKey 解析出非空预期值。
- [ ] **Step 2: 确认失败**(typeKey 未定义 → 空样式)。
- [ ] **Step 3: 实现（4 源 byte-sync）。** light.tycss `:root` 加三令牌(在 `--focus-ring` 后):
  ```
  --selection:     alpha(var(--accent), 0.30);
  --muted:         alpha(var(--on-surface), 0.5);
  --overlay-hover: alpha(var(--on-surface), 0.12);
  ```
  文件末尾(或合适分区)加 typeKey:
  ```
  TyTextSelection { background: var(--selection); }
  TyTextHint      { color: var(--muted); }
  TyTabClose      { background: var(--overlay-hover); border-radius: var(--radius); }
  ```
  mirror DefaultTheme.pas 逐字节。dark.tycss:`--selection: alpha(var(--accent),0.30)`(同),`--muted: alpha(var(--on-surface),0.5)`(暗色 on-surface 基),`--overlay-hover: alpha(#FFFFFF, 0.14)`(暗底用白洗)。showcase:`--overlay-hover: alpha(#FFFFFF, 0.18)`(其既有量级),其余同。三 typeKey 各源相同写法(引用各自令牌)。
- [ ] **Step 4: 跑。** 新用例 PASS;byte-sync PASS。
- [ ] **Step 5: Commit** `feat(tycontrols): add --selection/--muted/--overlay-hover tokens + TyTextSelection/TyTextHint/TyTabClose typeKeys`

---

## Task 4: 主题2b — Edit/Memo 选区带 + 占位符改令牌解析

**Files:** `source/tyControls.Edit.pas`、`tyControls.Memo.pas`;Test `tests/test.edit.pas`、`test.memo.pas`。

- [ ] **Step 1: 失败测试**——选区像素测试:渲染一段有选区的 Edit,选区带像素的色相应接近 accent(`--selection`=accent@30% over 背景 → 偏蓝),而非旧的 FocusBorderColor 灰蓝。最稳的判定:选区带像素的 B 通道明显高于 R 通道(accent #3B82F6 蓝多)。占位符:渲染空 Edit + TextHint,占位文字像素存在且比正文淡(muted)。给出能区分新旧的断言(旧 $59 over focus-border 也偏蓝,所以改用"选区带色 == 解析的 TyTextSelection.Background.Color"更稳:在测试里 `ResolveStyle('TyTextSelection',...)` 取期望色,断言选区带某像素等于该色 over 背景的合成)。
- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现。** Edit.pas RenderTo(line ~1311-1320):删 `BandAlpha := $59;` 与基于 `FocusBorderColor` 的 `BandColor` 推导,改:
  ```pascal
  SelStyle := ActiveController.Model.ResolveStyle('TyTextSelection', '', []);
  BandColor := SelStyle.Background.Color;   // already alpha(accent,0.30)
  BandFill := Default(TTyFill); BandFill.Kind := tfkSolid; BandFill.Color := BandColor;
  ```
  (声明 `SelStyle: TTyStyleSet;`;`FocusBorderColor`/`BandAlpha` 若仅用于此可删。)占位符(line ~1331):
  ```pascal
  HintStyle := ActiveController.Model.ResolveStyle('TyTextHint', '', []);
  HintColor := HintStyle.TextColor;
  ```
  Memo.pas 同样改其选区带(audit 指 ~2191-2193)与占位(若 Memo 有 TextHint;若无占位则只改选区)。grep 两文件确认 `$59`/`$80` 0 残留。
- [ ] **Step 4: 跑。** 选区/占位像素测试 PASS;现有 Edit/Memo 选区、光标、密码掩码等测试不回归(选区色变了——更新任何断言旧灰蓝具体值的测试为新 accent 源,保持"选区带可见且覆盖选中字"的意图)。`grep -n '\$59\|\$80' source/tyControls.Edit.pas source/tyControls.Memo.pas` → 空。
- [ ] **Step 5: Commit** `feat(tycontrols): Edit/Memo selection + hint via TyTextSelection/TyTextHint tokens (kill $59/$80 literals)`

---

## Task 5: 主题2c — Tab 关闭芯片改 TyTabClose 令牌

**Files:** `source/tyControls.TabControl.pas`;Test `tests/test.tabcontrol.pas`。

- [ ] **Step 1: 失败测试**——关闭芯片 hover 像素 = 解析的 `TyTabClose.Background` over tab 背景的合成色(不再是 TabStyle.TextColor@48)。或更简:grep 断言源码不含字面 `, 48)` 的 CloseHi 与 `FillBackground(CloseRect, CloseHi, 3)`。优先像素:渲染 closable tab,hover 其 close 区,芯片像素 ≈ TyTabClose 合成色。
- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现。** TabControl.pas RenderTo(line ~1066-1072):把
  ```pascal
  CloseHi.Color := TyRGBA(TyRedOf(TabStyle.TextColor), TyGreenOf(TabStyle.TextColor), TyBlueOf(TabStyle.TextColor), 48);
  P.FillBackground(CloseRect, CloseHi, 3);
  ```
  改为:
  ```pascal
  CloseS := ActiveController.Model.ResolveStyle('TyTabClose', '', []);
  CloseHi := Default(TTyFill); CloseHi.Kind := tfkSolid; CloseHi.Color := CloseS.Background.Color;
  P.FillBackground(CloseRect, CloseHi, CloseS.BorderRadius);
  ```
  (声明 `CloseS: TTyStyleSet;`。`TyTabClose.border-radius: var(--radius)` 已在 Task 3 主题里;若想用 tab 自身圆角也可 `TabStyle.BorderRadius`——按 spec 用 TyTabClose.BorderRadius 即可,保持令牌驱动。)
- [ ] **Step 4: 跑。** 新用例 PASS;现有 tab 测试不回归;`grep -n ', 48)\|CloseHi, 3)' source/tyControls.TabControl.pas` → 空。
- [ ] **Step 5: Commit** `feat(tycontrols): Tab close-chip via TyTabClose token (kill literal radius 3 + alpha 48)`

---

## Task 6: 主题3a — TyListItem 圆角 + 行填充内缩

**Files:** 4 主题源 + `source/tyControls.ListBox.pas`;Test `tests/test.controls.listbox.pas`。

- [ ] **Step 1: 失败测试**——`ResolveStyle('TyListItem','',[]).BorderRadius > 0`;且选中行像素:行矩形四角的角像素**不是**行填充色(accent),证明圆角切掉了角(在内缩 + 圆角下,角落露出 listbox 背景)。
- [ ] **Step 2: 确认失败**(TyListItem 无 border-radius → 0 → 方角)。
- [ ] **Step 3: 实现。** 4 源给 `TyListItem` 加 `border-radius: var(--radius);`(light line ~150 块内,DefaultTheme 镜像,dark/showcase 同)。ListBox.pas 行绘制:确认选中/hover 行的填充矩形按 listbox padding(`S.Padding`,主题 `TyListBox padding:2px`)左右内缩,使圆角可见(若当前行铺满宽度,把行 fill rect 左右各内缩 `P.Scale(S.Padding.Left/Right)` 或一个小内缩;读 `ListBox.pas:~615` 区现状再定)。RowStyle.BorderRadius 已传入 FillBackground。
- [ ] **Step 4: 跑。** 新用例 PASS;byte-sync PASS;现有 listbox 渲染/选择测试不回归(若某测试断言行填充铺满到边,更新为内缩后的范围,保持"选中行高亮可见"意图)。
- [ ] **Step 5: Commit** `feat(tycontrols): rounded TyListItem rows (border-radius:var(--radius) + padding inset)`

---

## Task 7: 主题3b — ProgressBar 部分填充 per-corner

**Files:** `source/tyControls.ProgressBar.pas`;Test `tests/test.progressbar.pas`(或现有 progress 测试单元)。

- [ ] **Step 1: 失败测试**——50% 进度时:fill 的**左**上/下角是圆角(角像素 = 背景,非 fill 色),**右**上/下角是直角(角像素 = fill 色,因为右缘在中途不应圆);100% 时四角随 track 圆角。
- [ ] **Step 2: 确认失败**(当前用 uniform `FillS.BorderRadius` → 右缘也圆)。
- [ ] **Step 3: 实现。** ProgressBar.pas(line ~124-126):partial(value<max)时用 per-corner `TyCorners(r, 0, 0, r)`(左上、左下=r;右上、右下=0;按 painter per-corner 重载参数序——读 `Base.pas`/`Painter.pas` 的 `TyCorners`/`FillBackground(rect,fill,TTyCorners)` 签名确定四角顺序),`r := FillS.BorderRadius`;full(value=max)时用 uniform `FillS.BorderRadius`(四角圆)。横向进度;若支持竖向同理镜像。
- [ ] **Step 4: 跑。** 新用例 PASS;现有 progress 测试不回归。
- [ ] **Step 5: Commit** `feat(tycontrols): ProgressBar partial-fill rounds only the leading (left) corners`

---

## Task 8: 主题3c — Radio 点 / Toggle 旋钮半径从令牌封顶

**Files:** `source/tyControls.CheckBox.pas`、`tyControls.ToggleSwitch.pas`;Test 对应单元。

- [ ] **Step 1: 失败测试**——纯几何/单测:封顶函数 `min(S.BorderRadius, halfSide)`。Radio 默认 `TyRadioButton border-radius:8px`、box 16px → half=8 → 仍正圆(默认不变);但若主题把 radius 设 2,点应变方一点。给一个断言:用一个临时小 radius 样式时点半径 = 该 radius(而非 div-2)。最简:暴露/单测一个 `pure ClampRadius(aRadius, aHalf): Integer = Min(aRadius, aHalf)` 并在两控件用它。
- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现。** CheckBox.pas radio 点(line ~241):`DotRadius := Min(S.BorderRadius, BoxSize div 2)` 取代裸 `BoxSize div 2`(注意单位:S.BorderRadius 是逻辑 px,BoxSize 可能是设备 px——统一到同一单位再 Min;读现状)。ToggleSwitch.pas 旋钮(line ~227):`KnobRadiusLogical := Min(S.BorderRadius, KnobLogical div 2)` 取代 `KnobLogical div 2`(S 这里指 Toggle 的 CurrentStyle;Task 9 后旋钮色走 TyToggleKnob,但半径可用 TyToggleKnob.BorderRadius 或 Toggle S.BorderRadius——选其一并与默认 12px 一致使默认仍圆)。默认令牌(8/12)使两者仍封成正圆 → **默认零像素变化**。
- [ ] **Step 4: 跑。** 新用例 PASS;现有 checkbox/radio/toggle 像素测试**默认不变**(若变则封顶逻辑错)。
- [ ] **Step 5: Commit** `feat(tycontrols): radio dot + toggle knob radius clamps to token (default unchanged)`

---

## Task 9: 主题4a — TyScrollThumb / TyToggleKnob typeKey + 解析

**Files:** 4 主题源 + `source/tyControls.ScrollBar.pas`、`tyControls.ToggleSwitch.pas`;Test 对应单元。

- [ ] **Step 1: 失败测试**——`ResolveStyle('TyScrollThumb','',[]).Background.Color` = `var(--border)`(= #D1D5DB),`:hover`=darken,`:active`=accent;`ResolveStyle('TyToggleKnob','',[]).Background.Color` = #FFFFFF。且像素:ScrollBar thumb 像素 = 解析的 TyScrollThumb 背景(= 旧 S.TextColor 借色,默认观感不变);Toggle 旋钮像素 = #FFFFFF(不变)。
- [ ] **Step 2: 确认失败**(typeKey 未定义)。
- [ ] **Step 3: 实现（4 源 byte-sync + 代码）。** light.tycss 加:
  ```
  TyScrollThumb { background: var(--border); border-radius: 4px; }
  TyScrollThumb:hover  { background: darken(--border, 15%); }
  TyScrollThumb:active { background: var(--accent); }
  TyToggleKnob  { background: #FFFFFF; border-radius: 12px; }
  ```
  (镜像 DefaultTheme;dark/showcase 用各自基色。值 = 今天 ScrollBar `color`/:hover/:active 与 Toggle `color`,保证默认不变。)ScrollBar.RenderTo:thumb 色从 `S.TextColor` 改 `ActiveController.Model.ResolveStyle('TyScrollThumb','',ThumbStates).Background.Color`,其中 ThumbStates 按当前 hover/active(若 ScrollBar 现无 thumb 态跟踪,至少用 `[]`,thumb 默认色即可——读现状决定是否接 hover/active)。ToggleSwitch.RenderTo:`KnobFill.Color := ResolveStyle('TyToggleKnob','',[]).Background.Color` 取代 `S.TextColor`。(原 `TyScrollBar.color`/:hover/:active 与 `TyToggleSwitch.color` 现在 thumb/knob 不再读 → 成为 vestigial;**保留**以最小化 4 源改动面,reviewer 记一笔即可。)
- [ ] **Step 4: 跑。** 新用例 PASS;byte-sync PASS;ScrollBar/Toggle 现有像素测试默认观感不变。
- [ ] **Step 5: Commit** `feat(tycontrols): TyScrollThumb + TyToggleKnob typeKeys (sub-element color parity, default unchanged)`

---

## Task 10: 主题4b — checkbox/radio 选中态复活 + :active 白字形 + padding

**Files:** `source/tyControls.CheckBox.pas` + 4 主题源;Test `tests/test.controls.checkbox.pas`(或实际单元名)。

- [ ] **Step 1: 失败测试**——(a) `FChecked=True` 的 TTyCheckBox,其 `CurrentStates` 含 `tysActive`(若有 access);(b) 像素:选中 checkbox 的 **box 子元素**填充 = accent(#3B82F6),box 内字形(勾)= 白;**caption 区背景不变**(仍透明/surface,不被染 accent);(c) box 左缘较未加 padding 右移 ~Scale(4)。
- [ ] **Step 2: 确认失败**(当前选中态不进 tysActive,:active 永不触发;无 padding)。
- [ ] **Step 3: 实现。** CheckBox.pas:覆写 `CurrentStates`(或在解析 box 样式处)使 `FChecked` → `Include(tysActive)`,**仅作用于 box 子元素样式解析**(读 CheckBox.pas 确认 box 用哪次 ResolveStyle/CurrentStyle;让 box 的解析带 tysActive,caption/控件背景不带——若 box 与控件共用 CurrentStyle 则需把 box 单独解析,或确认 :active 只影响 box 绘制路径,见 spec §3.4 实现注)。4 源:`TyCheckBox:active`/`TyRadioButton:active` 改为 `{ background: var(--accent); color: #FFFFFF; }`(加 color);给 `TyCheckBox`/`TyRadioButton` 基块加 `padding: 4px;`。镜像 DefaultTheme;dark/showcase 同。CheckBox.pas box 命中/绘制用 `S.Padding` 内缩。
- [ ] **Step 4: 跑。** 新用例 PASS(box accent + 白勾 + caption 不变 + 右移);byte-sync PASS;现有 checkbox/radio 测试——选中态视觉变了,更新断言旧观感的测试为新(box accent),保留"勾可见/Checked 语义"意图;radio 互斥/Space 等行为测试不受影响。
- [ ] **Step 5: Commit** `feat(tycontrols): revive checkbox/radio :active (accent box + white glyph) + 4px padding`

---

## Task 11: 顺手项 — SpinEdit 走 ResolveFontSize

**Files:** `source/tyControls.SpinEdit.pas`;Test `tests/test.spinedit.pas`。

- [ ] **Step 1: 失败/防回归测试**——SpinEdit 文本在主题 `font-size:9px` 下渲染高度对应 9pt(而非孤儿 12)。可用现有字号像素测试思路;或断言渲染用的 size = `ResolveFontSize(S)`。先确认现有 SpinEdit 字号测试是否钉了 12——若钉了,本任务会改其期望(预期变化:SpinEdit 文本从 12 的 fallback 改为主题 9px)。
- [ ] **Step 2: 确认现状。**
- [ ] **Step 3: 实现。** SpinEdit.pas(line ~301):把孤儿字面 fallback `12` 改为 `ResolveFontSize(S)`(`TTyCustomControl.ResolveFontSize`,优先 theme font-size → Font.Size → 9)。与 spec 一致(本批仅收 SpinEdit;Edit/Memo 自有 fallback 留后)。
- [ ] **Step 4: 跑。** 现有 SpinEdit 测试绿(必要时把钉死 12 的字号期望更新为 9px 主题值,保留光标/编辑行为意图)。
- [ ] **Step 5: Commit** `feat(tycontrols): SpinEdit text size via ResolveFontSize (drop orphan literal 12)`

---

## Task 12: 文档 + tycss 约定 + 全量回归

**Files:** `docs/tycss-reference.md`、`docs/controls/*.md`(受影响:checkbox/radiobutton、scrollbar、trackbar、tabcontrol、progressbar、toggleswitch、listbox、edit/memo、spinedit);全量 + 矩阵。

- [ ] **Step 1: docs/tycss-reference.md** —— 写下两层色策略约定:**tier-a**(彩色面子元素 thumb/knob/fill/progress → 专用 typeKey:TyScrollThumb/TyToggleKnob/TyTrackThumb/TyProgressFill);**tier-b**(单色字形 勾/点/箭头/✕ → 借 `S.TextColor` 作 ink,显式合规)。补登新令牌(`--selection`/`--muted`/`--overlay-hover`)与新 typeKey(TyTextSelection/TyTextHint/TyTabClose/TyScrollThumb/TyToggleKnob)。
- [ ] **Step 2: docs/controls/** —— 各受影响控件 md 补:新增 :disabled/:hover/:focus 状态;选区/占位令牌;列表行圆角;checkbox/radio 选中 accent + padding;SpinEdit 字号统一。只记实际所改。
- [ ] **Step 3: 全量回归 + 矩阵**
  ```bash
  lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain
  bash scripts/build-matrix.sh
  ```
  Expected:0 failures(+15 env);`TestBuiltinMatchesLightTheme` 绿;`== matrix OK ==`。
- [ ] **Step 4: Commit** `docs(tycontrols): batch4 tier-a/b color convention, new tokens/typeKeys, per-control state/visual updates`

---

## 完成后
全套件 + 矩阵 + heaptrc 0 + 终审(reviewer 核:4 源 byte-sync、无 `$59/$80/3/48` 残留、子元素 typeKey 默认观感不变、checkbox 选中只染 box、选区=accent 源、列表行圆角、progress 左角、各 :disabled 真生效);本地快进合并 main + 删分支;更新记忆(批④ 完成,批⑤ = 子元素间距令牌化/checkbox 已并入④则批⑤聚焦间距+阴影/动效)。

## Self-Review(规划者自查,已执行)
- **Spec 覆盖**:主题1→T1(:disabled)+T2(hover/focus/边框);主题2→T3(令牌/typeKey)+T4(Edit/Memo 选区/占位)+T5(Tab 芯片);主题3→T6(列表行圆角)+T7(progress 角)+T8(radio/knob 半径);主题4→T9(thumb/knob typeKey)+T10(checkbox 选中+padding);顺手→T11(SpinEdit);文档→T12。
- **byte-sync**:每个主题任务(T1/T2/T3/T6/T9/T10)Step 末确认 `TestBuiltinMatchesLightTheme`;铁律段集中说明 4 源同步。
- **类型/名一致**:typeKey 名 TyTextSelection/TyTextHint/TyTabClose/TyScrollThumb/TyToggleKnob 全程一致;令牌 --selection/--muted/--overlay-hover 一致;`ResolveStyle('<key>','',states).Background.Color`/`.TextColor`/`.BorderRadius` 范式统一(沿用 TyTrackThumb)。
- **向后兼容/有意变化**:默认观感不变项(thumb/knob typeKey、radio/knob 半径封顶)与有意可见变化项(:disabled 变暗、Toggle hover、List/Button/Tab hover 边框、ScrollBar focus 环、选区 accent、列表行圆角、checkbox 选中 accent、checkbox padding 右移、SpinEdit 9px)分别在各任务标注;实现者需在改既有像素测试时保留断言意图、只更新期望值。
- **无占位符**:令牌/typeKey 文本、code 改点(含 grepped 行号)、解析范式、测试判定均具体;dark/showcase 的"按现有量级取值"是明确指令(读对应文件取同量),非占位。
