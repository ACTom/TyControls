# TyControls 控件完善程序 · 批⑤+⑥ 间距去重 + 光标 + 动效 设计文档

- **日期:** 2026-06-16
- **前置:** `main`(Phase 0 + 批①②③④ + empty-FontName 修复 已合入,706 测试,0 失败,15 无头 env 错误)。
- **定位:** 程序的 **批⑤(间距令牌化的最小版:去重)** + **批⑥(结构性视觉:光标 + 动效;阴影按用户决定跳过)** 合并为一个 spec(用户"一起做")。
- **执行约定:** 沿用项目惯例 —— 像素/状态测试钉 `PPI=96`;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe -a --format=plain`;现有测试保持全绿、不改既有测试语义(动画默认开但无头 snap,现有像素测试仍断言终态)。基线:0 failures + 15 无头 win32(error 1407)env 错误(非回归)。`examples/demo/*` 是用户测试台,每个任务只 stage 自己的文件。

---

## 1. 动机 / 用户决策

批④ 审计的 Theme5(间距漂移)、Theme6(结构性:阴影/动效/光标)落地,按用户拍板:
- **批⑤ = 最小去重**:把重复写死的逻辑像素尺寸各合并为一个共享命名常量(防漂移),**不**扩展样式引擎、**不**改默认 Create 尺寸。零可见变化。
- **批⑥ 阴影 = 跳过**(LCL 内嵌控件被裁到自身边界,溢出投影画不出;唯一可行处是 ComboBox 下拉弹层,用户选择本批不做)。
- **批⑥ 光标 = 原生正确集**:文本框 `crIBeam`、窗体缩放区 `crSize*`;按钮/勾选/标签保持箭头(Windows 桌面惯例,不上手型光标)。
- **批⑥ 动效 = 默认开 + 几个关键过渡**:现有 Button/Toggle 动画默认打开,再补 ProgressBar 填充、ScrollBar/TrackBar thumb、TabControl 活动标签 的过渡。沿用现成 `TTyAnimator` + 无头 snap 安全模式。

## 2. 核心原则

去重零行为变化(同值)。光标是功能性属性(非主题视觉值),在代码里设无妨。动效全部沿用既有无头安全模式:**timer 仅在 `HandleAllocated` 时创建/启动;无 handle 或 `AnimationsEnabled=False` 时 `SetTargetImmediate` 直接 snap 到终态** → 现有像素测试(经 `RenderTo`,无 handle)断言终态,保持全绿。

## 3. 范围

### 3.1 批⑤ · 间距去重(`source/tyControls.Types.pas` + 各控件)

在 `tyControls.Types` 增加一组共享逻辑像素常量,各重复站点改引用同一常量(值不变):

```pascal
const
  TyFieldButtonWidth = 18;   // SpinEdit 上下按钮 + ComboBox 下拉按钮宽
  TyScrollbarSize    = 12;   // ListBox/Memo 内嵌滚动条宽
  TyCheckBoxBox      = 16;   // CheckBox/RadioButton 勾选框/圆点外框
  TyCheckBoxGap      = 6;    // 勾选框到标题的间距
  // TabControl 表头布局
  TyTabPad           = 12;   // 标签左右内边距
  TyTabMinWidth      = 48;   // 标签最小宽
  TyTabCloseSize     = 14;   // 关闭 ✕ 尺寸
  TyTabGap           = 6;    // ✕ 与标题间距
  TyTabMargin        = 6;    // ✕ 右边距
  TyTabArrowBand     = 16;   // 滚动箭头带宽
```

替换站点(审计确认的精确位置,值全部 = 现状):
- `SpinEdit.pas`:`MulDiv(18,…)`/`P.Scale(18)` × 3(~76, 87, 298)→ `TyFieldButtonWidth`。
- `ComboBox.pas`:`ButtonWidthLogical` 里的 `18`(~146)→ `TyFieldButtonWidth`(`ButtonWidthLogical` 可保留为返回常量的函数,或直接用常量)。
- `Memo.pas`(~1182)/`ListBox.pas`(~368, 583):`MulDiv(12,…)` → `TyScrollbarSize`。
- `CheckBox.pas`:box `P.Scale(16)`(~146, 269)→ `TyCheckBoxBox`;gap `P.Scale(6)`(~147, 270)→ `TyCheckBoxGap`。
- `TabControl.pas` RebuildLayout(~364-368, 404-408):`12/48/14/6/6/16` → 对应常量。`drag 阈值 6`(~558)与 `frame overlap 1`(~1012)留作各自语义,不强行并入(不同含义)。

无任何值变化 → 编译过、现有测试全绿即验收(无新行为测试;可选一个"常量值正确"的轻断言)。

### 3.2 批⑥ · 光标(`source/tyControls.Edit.pas`、`Memo.pas`、`SpinEdit.pas`、`Form.pas`)

- **文本框 `crIBeam`**:Edit/Memo/SpinEdit 在 `Create` 设 `Cursor := crIBeam`。(ComboBox 是只读下拉,保持箭头。)
- **窗体缩放光标**:`Form.pas` 的 `FormMouseMove`(~524)里,用已有 `TyHitTestBorder` 的命中区设光标:`bhLeft/bhRight→crSizeWE`、`bhTop/bhBottom→crSizeNS`、`bhTopLeft/bhBottomRight→crSizeNWSE`、`bhTopRight/bhBottomLeft→crSizeNESW`、`bhNone→crDefault`。仅在非拖动态更新光标(拖动中维持当前)。
- 其余控件保持默认箭头(Windows 桌面按钮/勾选不用手型)。
- `LCLType` 的 `crIBeam`/`crSize*` 常量;确认各单元 uses(必要时加 `Controls`)。

### 3.3 批⑥ · 动效(`Animation.pas` 复用;Button/Toggle/ProgressBar/ScrollBar/TrackBar/TabControl)

通用模式(沿用 Button/Toggle 现有写法):每控件
- `FAnimEnabled: Boolean`(published `AnimationsEnabled`,**默认 True**)+ 一个 `TTyAnimator`(`DurationMs:=120; Easing:=teEaseOutCubic`)+ 懒创建 `FTimer: TTimer`(16ms);
- 状态变更时:若 `AnimationsEnabled and HandleAllocated` 则设 animator 目标 + `EnsureTimer`/`Enabled:=True`;否则 `SetTargetImmediate`(snap);
- `HandleTimer`:`Advance(FTimer.Interval)`,`Invalidate`,`Running=False` 时停 timer;
- `Destroy` 显式 `FreeAndNil(FTimer)`。

具体过渡:
- **Button hover-fade / Toggle knob-slide**:已实现,仅把 `AnimationsEnabled` 默认 `False`→`True`。
- **ProgressBar 填充**:新增"显示位置"动画 —— `SetPosition` 改为把 animator 从当前显示值过渡到新值;`RenderTo` 用 `TyLerpF(FAnimFrom, FAnimTo, anim.Eased)`(或等价)算填充宽度。无 handle/关闭则 snap(=现状)。
- **ScrollBar + TrackBar thumb**:`SetPosition` 程序性变更时把 thumb 显示位置过渡到新值;**拖动中**(`FDragging`)直接 snap(thumb 跟手,不延迟)。`RenderTo` 用显示位置算 thumb。**内嵌滚动条**(ListBox/Memo 创建的 FScrollBar)在创建时设 `AnimationsEnabled := False`,保证内容滚动即时不拖泥带水;独立 ScrollBar/TrackBar 默认动画。
- **TabControl 活动标签**:切页时(`SetTabIndex`)对**活动标签表头**做 120ms 颜色淡入(新活动标签背景由非活动样式 `TyLerpColor` 过渡到活动样式)。**不**做页面内容交叉淡出(页是子控件,LCL 无法 alpha 混合)——动画只在表头 `RenderTo` 内。

## 4. 不做(批⑤+⑥ 显式排除)

- 阴影/高程(LCL 限制;含 ComboBox 下拉真投影)——本批跳过(留后)。
- 间距的**完整主题令牌化**(新 CSS 属性/样式字段);默认 Create 尺寸归一化。
- TabControl 页面内容交叉淡出、ComboBox 下拉开合动画、CheckBox 勾选淡入(可作后续"动效第二波")。
- 全局 `TyAnimationsEnabled` 总开关(暂用每控件 `AnimationsEnabled`;若以后要一键关全部再加)。

## 5. 验收

- 现有 706 测试保持全绿(动画默认开但无头 snap → 现有像素测试断言终态不变;若有测试断言 `AnimationsEnabled=False` 默认值,更新为 True 并保留意图)。新增测试:
  - **批⑤**:可选——断言常量值(`TyFieldButtonWidth=18` 等)或纯编译通过 + 现有 SpinEdit/ComboBox/Memo/ListBox/CheckBox/Tab 几何测试不变。
  - **光标**:Edit/Memo/SpinEdit `Cursor=crIBeam`;窗体 `FormMouseMove` 在各 border 命中区设对应 `crSize*`(用 access/直接调,断言 `Cursor`)。
  - **动效**:每控件 —— (a) `AnimationsEnabled=False`(或无 handle)时 `RenderTo` 像素 = 终态(snap,现有测试覆盖);(b) animator 推进的纯/集成测试:设新目标后 `AdvanceAnimation(部分时长)`,断言显示值/像素在起止之间(中间态),`Advance(≥120ms)` 到终态;(c) 拖动中 ScrollBar/TrackBar thumb 即时(`FDragging` 时 snap)。ProgressBar/Scroll/Track 默认 `AnimationsEnabled=True`。
  - 无头安全:timer 仅 `HandleAllocated`;测试经 `RenderTo` 无 handle → 默认 snap,确定性。
- `bash scripts/build-matrix.sh` 全绿;heaptrc 0(新 timer 在 Destroy 释放);终审通过;`docs/controls/*.md`(受影响:edit/memo/spinedit 光标;progressbar/scrollbar/trackbar/tabcontrol/button/toggleswitch 的 `AnimationsEnabled`)同步。

## 6. 兼容性 / 有意的可见行为变化

- 去重:零变化。
- 光标:文本框显示 I 形、窗体边缘显示缩放光标——纯增强,符合原生预期。
- 动效:**默认开是有意的行为变化**——Button 悬停淡入、Toggle 旋钮滑动、Progress 填充缓动、Scroll/Track thumb 程序性变更缓动、Tab 活动标签淡入。无头/测试 snap 到终态(不破坏像素测试)。需要静态的 app 可设各控件 `AnimationsEnabled := False`。内嵌滚动条强制关动画(内容滚动即时)。
