# TyControls 控件完善程序 · 批④ 视觉细节扫尾 设计文档 — 状态对等 + 消除硬编码/统一选区 + 子元素圆角统一 + 子元素色策略

- **日期:** 2026-06-15
- **前置:** `main`(Phase 0 + 批①②③ 已合入,685 测试,0 失败,15 无头 env 错误)。
- **定位:** "完善现有控件"程序的**批④**(视觉细节扫尾)。范围由一次穷举式视觉一致性审计(66 项发现 / 7 维)归并而来;用户选定 **主题 1+2+3+4 全做** + 2 个顺手项。单一 spec;实现按 主题1→2→3→4 推进(由稳到深)。
- **执行约定:** 沿用项目惯例 —— 像素/状态测试钉 `PPI=96`;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe -a --format=plain`;现有测试保持全绿、不改既有测试语义。基线:0 failures + 15 无头 win32(error 1407)env 错误(非回归)。`examples/demo/*` 是用户测试台,可改可提交但**每个任务只 stage 自己的文件**。

---

## 0. 铁律(贯穿全批,最高风险)

**每条主题层(.tycss)改动必须同步落到 4 个源,且其中 light↔Default 逐字节一致:**
1. `themes/light.tycss`(浅色,**真源**)
2. `themes/dark.tycss`(暗色对等)
3. `themes/showcase.tycss`(变体)
4. `source/tyControls.DefaultTheme.pas`(内置默认皮肤,**必须与 light.tycss 逐字节相同**)

`tests/test.defaulttheme.pas::TestBuiltinMatchesLightTheme`(`NormalizeCss` = 每行 TrimRight + 整体 Trim)强制 light↔Default 一致 —— **任何只改 light 不改 Default(或反之)的提交都会红**。每个含主题改动的任务,最后一步必须确认这条测试绿。所有视觉值令牌驱动,控件代码内**绝不**出现字面色/魔法视觉常量(HARD RULE)。

## 1. 动机(审计结论)

三大跨控件不一致:(1) **状态规则缺口** —— `TyScrollBar`/`TyTrackBar`/`TyTabControl`/`TyProgressBar` 完全无 `:disabled`(禁用态零反馈,TrackBar 还拦输入却无提示);`TyToggleSwitch` 无 `:hover`;`TyScrollBar` 无 `:focus`;带边框盒子家族悬停边框三种做法不一。(2) **真·HARD-RULE 违规** —— Edit/Memo 选区带字面 `$59` alpha、占位符 `S.TextColor@$80`、Tab 关闭芯片字面 `radius 3 + alpha 48`,均不可主题化;且选中文字(半透明边框洗)与选中列表行(实心 `--accent`)毫不相干。(3) **子元素圆角/色策略漂移** —— 列表行在圆角盒子里是硬方角;progress 部分填充前缘中途变圆;radio 点/旋钮用 `div-2` 魔法绕过令牌;ScrollBar thumb / Toggle 旋钮借 `S.TextColor` 而其孪生 TrackThumb/ProgressFill 有专用 typeKey。

## 2. 核心原则

新增令牌/typeKey 的默认值 = 今天的观感(借色照搬),除显式标注的"有意可见变化"外向后兼容。沿用 `TyTrackThumb`/`TyProgressFill` 的"RenderTo 里 `ActiveController.Model.ResolveStyle('<子typeKey>', '', states)` 取子元素样式"成熟范式。

## 3. 范围

### 3.1 主题 1 · 状态规则对等(几乎纯主题层)

全部落 4 源(byte-sync):
- **补 `:disabled { opacity: 0.5 }`**(showcase `0.45`,与现有禁用控件一致)给:`TyScrollBar`、`TyTrackBar`、`TyTabControl`、`TyProgressBar`。容器 opacity 在 `EndPaint` 统一施加,子元素随之变暗,**无需代码改动**(确认各控件 `CurrentStyle` 在 `not Enabled` 时已含 `tysDisabled` —— Base 已统一处理)。
- **`TyToggleSwitch:hover`**:`darken(--surface, …%)`(暗色 `lighten`,showcase 取其变体值),与同族 hover 量级一致。
- **`TyScrollBar:focus { outline: 2px var(--focus-ring); }`**:加 `:focus` 规则(4 源)。**不**设 `TabStop`(滚动条惯例不进 Tab 序;聚焦经 `MouseDown` 的 SetFocus,焦点环此时可见)。
- **`TyTabControl:focus { border-color: var(--accent); }`**:对齐其它可聚焦盒子(目前仅 outline)。
- **悬停边框收敛(用户选"全加")**:给所有带边框的**交互**盒子补 `:hover { border-color: <与输入框家族现有 :hover 边框相同的 darken(--border,…) 值> }`(暗色 `lighten`)。受影响:`TyListBox`、`TyButton`、`TyTabControl`(content frame)。输入框 `TyEdit`/`TyMemo`/`TyComboBox`/`TySpinEdit` 已有,**不改**。勾选框 `TyCheckBox`/`TyRadioButton` 保留其 box 的 `--accent` hover(那是 box 子元素,语义不同)。**容器 `TyPanel`/`TyGroupBox` 不加**(无交互悬停语义)。
  - 实现前先读 `TyEdit:hover` 的现有 `border-color`,新规则用**同一**函数与百分比,避免引入第三种 hover 边框量级。

### 3.2 主题 2 · 消除硬编码 + 统一选区(代码 + 令牌)

- **新增 3 个 `:root` 令牌**(4 源):
  - `--selection: alpha(var(--accent), 0.30);`
  - `--muted: alpha(var(--text), 0.5);`(`--text` 用各主题既有的正文文字令牌名;若无独立 `--text`,用 `--on-surface` 等现有正文色令牌——实现时按真源实际令牌名取)
  - `--overlay-hover: <半透明悬停遮罩>;`(浅色 `alpha(#000, …)` 或 `darken` 的半透明等价;暗色对应;showcase 沿用其现有 `alpha(#FFF,0.18)` 量级。目标:三主题统一一个令牌,值各主题自定但**控件代码只引用令牌**)
- **新增 2 个文本子元素 typeKey**(4 源,RenderTo 解析):
  - `TyTextSelection { background: var(--selection); }`
  - `TyTextHint { color: var(--muted); }`
- **Edit/Memo 选区带**(`source/tyControls.Edit.pas:~1313-1319`、`tyControls.Memo.pas:~2191-2193`):删 `BandAlpha:=$59` over FocusBorderColor,改 `ResolveStyle('TyTextSelection', '', [])` 取 `Background.Color` 画选区带。**有意可见变化**:选中文字由灰蓝边框调 → accent 调(与选中列表行同源)。
- **Edit/Memo 占位符**(`source/tyControls.Edit.pas:~1331`,Memo 同位):删 `S.TextColor@$80`,改 `ResolveStyle('TyTextHint','',[]).TextColor`。`--muted`=text@50% 时观感几乎不变。
- **Tab 关闭芯片**(`source/tyControls.TabControl.pas:~1069-1072`):删字面 `radius 3` 与程序 `TyRGBA(...,48)`,芯片底用 `--overlay-hover` 令牌(经一个 hover-overlay 子 typeKey 或解析 `--overlay-hover`—— 用 `TyTabClose { background: var(--overlay-hover) }` 子 typeKey,与 §3.5 文档约定一致),圆角用 `TabStyle.BorderRadius`。同一 `--overlay-hover` 也用到标题栏 caption 按钮悬停(`source/tyControls.Form.pas` caption button hover),统一三主题现有不一致(darken 不透明 vs alpha)。

### 3.3 主题 3 · 子元素圆角统一(代码 + 令牌)

- **`TyListItem { border-radius: var(--radius); }`**(4 源)。代码已传 `RowStyle.BorderRadius`(`tyControls.ListBox.pas:~615`)→ 主要是主题改动;但需确认**行填充矩形按 ListBox padding 内缩**,否则圆角贴边不可见(若当前行填充铺满宽度,内缩 `Scale(padding)` 使圆角可见——小代码改)。**有意可见变化**:选中/hover 行 方角 → 圆角(showcase `--radius:10px` 最明显)。
- **ProgressBar 部分填充**(`source/tyControls.ProgressBar.pas:~124-126`):partial 时仅左两角圆、满值四角圆 —— 用 per-corner `TyCorners(r,0,0,r)`(已有 painter per-corner 重载)。消除前缘中途浮动药丸。几何改动,令牌值不变。
- **Radio 圆点**(`source/tyControls.CheckBox.pas:~241`):半径从裸 `BoxSize div 2` → `S.BorderRadius` 上限封顶到 `BoxSize div 2`(令牌 8px 仍封成正圆 → **默认零变化**,但可被主题调)。
- **Toggle 旋钮**(`source/tyControls.ToggleSwitch.pas:~228`):半径从 `KnobLogical div 2` → `S.BorderRadius` 上限封顶到圆(默认零变化)。
- 不做:`--radius-sm` 派生令牌(YAGNI,留后)。

### 3.4 主题 4 · 子元素色策略 typeKey + checkbox 选中态(代码 + 令牌 + 文档)

- **新增 `TyScrollThumb` typeKey**(4 源,镜像 `TyTrackThumb`):`{ background: <当前 ScrollBar 主题里 thumb 用的色>; :hover; :active }`。ScrollBar.RenderTo thumb 从 `S.TextColor` 改 `ResolveStyle('TyScrollThumb','',ThumbStates).Background.Color`。**默认值 = 今天 ScrollBar `color:` 槽里那个 thumb 色**(把 thumb 色从 `TyScrollBar.color` 迁到 `TyScrollThumb.background`,解析色不变 → **默认零变化**;ScrollBar 的 `color` 槽迁移后是否保留见实现注)。
- **新增 `TyToggleKnob` typeKey**(4 源):`{ background: <当前旋钮色,如 #FFFFFF>; border-radius: 12px; }`。ToggleSwitch.RenderTo 旋钮从 `S.TextColor` 改 `ResolveStyle('TyToggleKnob','',[]).Background.Color`(默认零变化)。
- **checkbox/radio 选中态复活**:`TTyCheckBox`/`TTyRadioButton` 覆写 `CurrentStates`(或等价钩子),`FChecked` 时 `Include(tysActive)`,让已定义却永不触发的 `:active { background: var(--accent) }`(light.tycss:~65/77)真正绘制;并补 `:active { color: #FFFFFF }`(4 源),选中字形读白。**有意可见变化**:选中 checkbox/radio 获得 accent 填充 + 白勾/白点。
  - **实现注**:先读 `CheckBox.pas` 确认 `:active` 的 `background`/`color` 落在**勾选 box 子元素**(及其字形),而非整个控件矩形(caption 区不应变 accent)。若 box 用 `CurrentStyle` 解析,则 `tysActive` 自然只染 box;若 box 另走子 typeKey,则把 `:active` 加到该子 typeKey。像素测试须验证 caption 背景不变、仅 box 变 accent。
- **`docs/tycss-reference.md`** 写下两层色策略约定:**tier-a**(彩色面子元素:thumb/knob/fill/progress)→ 专用 typeKey;**tier-b**(单色字形:勾/点/箭头/✕)→ 借 `S.TextColor` 作 ink。使 ComboBox 箭头、SpinEdit 箭头、ScrollBar 端箭头、Tab 关闭 ✕、勾选字形 等"借色"显式合规、非缺口。

### 3.5 顺手项(随大范围)

- **SpinEdit 文本走 `ResolveFontSize(S)`**(`source/tyControls.SpinEdit.pas:~301`):去掉孤儿字面 fallback `12`,统一到库级 `ResolveFontSize`(接上记忆里的 font-resolution 收口;SpinEdit 与 Edit/Memo 的 12pt 自有 fallback 是已知分裂,本项先收 SpinEdit)。纯代码。**注意**:确认改后 SpinEdit 现有字号/光标像素测试仍绿(若测试钉了 12pt,按实际渲染调或保留显式 size)。
- **`TyCheckBox`/`TyRadioButton` 加 `padding: 4px`**(4 源):与兄弟输入框 4px 内缩对齐(box 现贴左边)。**有意可见变化**:勾选框 box 右移 ~4px。确认 box 命中/绘制用 padding 内缩。

## 4. 新增令牌 / typeKey 汇总(便于核对 4 源同步)

- **令牌(:root):** `--selection`、`--muted`、`--overlay-hover`(× 4 源,各主题取各自值)。
- **typeKey:** `TyTextSelection`、`TyTextHint`、`TyScrollThumb`(+ :hover/:active)、`TyToggleKnob`、`TyTabClose`(关闭芯片 overlay);checkbox/radio 新增 `:active{color:#FFFFFF}`;4 控件新增 `:disabled`;Toggle 新增 `:hover`;ScrollBar/TabControl 新增 `:focus`;List/Button/Tab 新增 `:hover` 边框。
- 每一项都 × 4 源,light↔Default 逐字节。

## 5. 不做(批④显式排除)

- `--radius-sm` 派生小圆角令牌(YAGNI)。
- 间距/尺寸令牌化(主题5:field-button/scrollbar-size/tab-layout 魔法数;values 当前一致,是防漂移非可见 bug → 留批⑤/后续)。
- 阴影/高程、动效/过渡、光标、弹层 chrome(主题6:结构性、需产品决策 → 独立后续 spec)。
- Edit/Memo 自有 12pt fallback 与 ResolveFontSize 的彻底统一(本批仅收 SpinEdit;Edit/Memo 留后)。
- `OutlineOffset` 让焦点环外移(目前 0,环压在边框上)—— 留后(全控件一致改动,独立)。

## 6. 验收

- 现有 685 测试保持全绿(尤其 byte-sync `TestBuiltinMatchesLightTheme`、各控件现有像素/状态测试)。新增测试:
  - **主题1**:4 控件 `:disabled` 解析出 opacity<1(或禁用渲染整体变暗的像素探针);Toggle `:hover` 背景变化;ScrollBar/TabControl `:focus` 出现 outline/accent 边框;List/Button/Tab `:hover` 边框色 = 输入框同值。
  - **主题2**:`--selection`/`--muted`/`--overlay-hover` 解析;`TyTextSelection`/`TyTextHint` 子 typeKey 解析出预期色;Edit/Memo 选区带像素 = accent 源(非旧灰蓝);占位符像素 = muted;Tab 关闭芯片 hover 像素令牌驱动(无 `$59/$80/3/48` 残留 —— grep 源码确认 0 命中)。
  - **主题3**:`TyListItem` 解析出 `BorderRadius>0`,选中行圆角像素(角像素背景 ≠ 行填充色);ProgressBar partial 左圆右方、满值四圆的角像素;radio/toggle 半径封顶纯函数/几何(默认仍正圆)。
  - **主题4**:`TyScrollThumb`/`TyToggleKnob` 解析出预期 background(= 旧借色);ScrollBar thumb / Toggle 旋钮像素 = 新 typeKey 色(= 旧观感);checkbox/radio `FChecked` 时 `CurrentStates` 含 `tysActive` + 选中像素 accent 填充 + 白字形。
  - **顺手项**:SpinEdit 字号经 ResolveFontSize(现有测试绿);checkbox/radio box 右移(命中/像素左缘 + ~Scale(4))。
- 每个含主题改动的任务:`TestBuiltinMatchesLightTheme` 必须绿(light↔Default 同步)。
- `bash scripts/build-matrix.sh` 全绿;heaptrc 0;终审通过;`docs/controls/*.md`(受影响控件)+ `docs/tycss-reference.md`(两层色约定 + 新令牌/typeKey)同步。

## 7. 兼容性 / 有意的可见变化清单

加令牌/typeKey/状态规则,默认值 = 今天观感。**有意的、必须记录的可见变化**(类比批③ Panel 居中,用户已在 demo 测试台确认):
1. 禁用 `TyScrollBar`/`TyTrackBar`/`TyTabControl`/`TyProgressBar` 现在可见变暗(修了 bug)。
2. `TyToggleSwitch` 新增 hover 反馈。
3. 所有带边框**交互**盒子(含 List/Button/Tab)新增 hover 边框变化。
4. `TyScrollBar` 点击聚焦后显示焦点环(仍不进 Tab 序)。
5. Edit/Memo 选区带由灰蓝边框调 → **accent 调**。
6. 选中列表行 方角 → 圆角。
7. **选中 `TyCheckBox`/`TyRadioButton` 获 accent 填充 + 白勾/点。**
8. `TyCheckBox`/`TyRadioButton` box 右移 ~4px(padding 对齐)。

买家若不要某项,可通过 `.tycss` 覆盖对应 typeKey/令牌还原(全部令牌驱动)。
