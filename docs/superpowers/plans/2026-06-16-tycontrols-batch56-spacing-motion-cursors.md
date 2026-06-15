# TyControls 批⑤+⑥ 间距去重 + 光标 + 动效 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`). The animation tasks (T4–T7) all apply the **Shared Animation Pattern** below — read it together with the task.

**Goal:** dedupe duplicated spacing literals into shared constants (零可见变化); add native cursors (I-beam text fields, resize cursors); turn motion on by default + add ProgressBar/ScrollBar/TrackBar/TabControl transitions, reusing the existing `TTyAnimator` + headless-snap pattern.

**Tech Stack:** Free Pascal/Lazarus LCL; `tyControls.Animation` (`TTyAnimator`); FPCUnit; PPI=96.

**约定:** 运行 `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`. 基线 **0 failures + 15 env errors (1407 headless noise)**. 提交 `feat(tycontrols): …`. `examples/demo/*` 只读不 stage。

---

## Shared Animation Pattern (T4–T7 apply this)

Reference impl = `source/tyControls.Button.pas` (hover-fade). Each animated control gets:
- private `FAnimEnabled: Boolean;` published `property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;` (NOTE: **default True** for the new controls), a `TTyAnimator` field, a lazy `FTimer: TTimer`.
- `uses` adds `ExtCtrls` (TTimer), `LCLType`, `tyControls.Animation`.
- `Create`: init the animator (`X.DurationMs := 120; X.Easing := teEaseOutCubic;` and the rest), `FAnimEnabled := True;`.
- `EnsureTimer` (lazy, `Interval:=16`, `OnTimer:=@HandleTimer`), `HandleTimer` (`if AdvanceAnimation(FTimer.Interval) then Invalidate; if not <anim>.Running then FTimer.Enabled := False;`), `function AdvanceAnimation(AMs: Integer): Boolean;` (seam for tests; returns `<anim>.Advance(AMs)`).
- `Destroy`: `FreeAndNil(FTimer); inherited;`.
- On the state change (SetPosition / SetTabIndex): set the animator's from/to + target, then:
  ```pascal
  if FAnimEnabled and HandleAllocated then
  begin EnsureTimer; FTimer.Enabled := True; end
  else
    <anim>.SetTargetImmediate(1);   // snap to final → headless/test deterministic
  ```
- `RenderTo` uses the **eased displayed value** (not the raw target) so paint reflects mid-animation; at Eased=1 it equals the final state (so existing pixel tests, which run headless = snapped, are unchanged).
- A test access subclass exposes `AdvanceAnimation` (already protected on Button — make it protected here too) so tests can step the animation without a wall clock.

**Position-animation specifics** (ProgressBar/ScrollBar/TrackBar): the animated quantity is a *displayed position* (`Single`). Keep `FAnimFrom, FAnimTo: Single`. Helper `function DisplayPos: Single;` = `TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased)`. In `SetPosition(new)`: when animating, `FAnimFrom := DisplayPos; FAnimTo := new; FPosAnim.Progress := 0; FPosAnim.Target := 1;` then start timer; when snapping (no handle / disabled / dragging), `FAnimFrom := new; FAnimTo := new; FPosAnim.SetTargetImmediate(1);` so `DisplayPos = new` immediately. `RenderTo` computes the fill/thumb geometry from `DisplayPos` (rounded) instead of `FPosition`.

`TTyAnimator` API (from `tyControls.Animation`): fields `Progress, Target: Single; DurationMs: Integer; Easing: TTyEasing`; methods `Advance(ms): Boolean`, `Running: Boolean`, `Eased: Single`, `SetTargetImmediate(v: Single)`. Helpers `TyLerpF/TyLerpI/TyLerpColor`, easing `teEaseOutCubic`.

---

## Task 1: 批⑤ — shared spacing constants (dedupe)

**Files:** `source/tyControls.Types.pas` + `SpinEdit.pas`, `ComboBox.pas`, `Memo.pas`, `ListBox.pas`, `CheckBox.pas`, `TabControl.pas`; Test `tests/test.types.pas` (or wherever Types is tested).

- [ ] **Step 1: 失败/守卫测试** — add a tiny const-value assertion (guards against accidental drift later):
```pascal
procedure TestSpacingConstants;
begin
  AssertEquals(18, TyFieldButtonWidth);
  AssertEquals(12, TyScrollbarSize);
  AssertEquals(16, TyCheckBoxBox);
  AssertEquals(6,  TyCheckBoxGap);
  AssertEquals(48, TyTabMinWidth);
end;
```
(It won't compile until the consts exist → that's the red.) Register it.
- [ ] **Step 2: 确认不编译** (consts undefined). `lazbuild tests/tytests.lpi`.
- [ ] **Step 3: 实现** — in `tyControls.Types` interface `const` section add:
```pascal
  TyFieldButtonWidth = 18;
  TyScrollbarSize    = 12;
  TyCheckBoxBox      = 16;
  TyCheckBoxGap      = 6;
  TyTabPad           = 12;
  TyTabMinWidth      = 48;
  TyTabCloseSize     = 14;
  TyTabGap           = 6;
  TyTabMargin        = 6;
  TyTabArrowBand     = 16;
```
Then replace the literals (value-identical) — ensure each unit `uses tyControls.Types` (all do):
  - `SpinEdit.pas` ~76, ~87 (`MulDiv(18,…)`), ~298 (`P.Scale(18)`) → `TyFieldButtonWidth`.
  - `ComboBox.pas` ~146 (`Result := 18;` in `ButtonWidthLogical`) → `Result := TyFieldButtonWidth;`.
  - `Memo.pas` ~1182 (`MulDiv(12,…)`); `ListBox.pas` ~368 (`MulDiv(12,…)`), ~583 (`MulDiv(12,…)`) → `TyScrollbarSize`.
  - `CheckBox.pas` ~146, ~269 (`P.Scale(16)`) → `TyCheckBoxBox`; ~147, ~270 (`P.Scale(6)`) → `TyCheckBoxGap`.
  - `TabControl.pas` RebuildLayout ~364 (`12`), ~365 (`48`), ~366 (`14`), ~367 (`6` Gap), ~368 (`6` Margin), ~404/~408 (`16` arrow) → `TyTabPad/TyTabMinWidth/TyTabCloseSize/TyTabGap/TyTabMargin/TyTabArrowBand`. (Leave drag-threshold `6` @~558 and frame-overlap `1` @~1012 as-is — distinct semantics.)
- [ ] **Step 4: 跑** — new test PASS; **all existing geometry/pixel tests UNCHANGED & green** (values identical → zero behavior change). 0 failures / 15 errors.
- [ ] **Step 5: Commit** `refactor(tycontrols): dedupe duplicated spacing literals into shared Ty* constants`

---

## Task 2: 批⑥ — cursors (I-beam text fields + form resize)

**Files:** `source/tyControls.Edit.pas`, `Memo.pas`, `SpinEdit.pas`, `Form.pas`; Test the relevant test units.

- [ ] **Step 1: 失败测试** — assert text controls set `crIBeam` and the form sets resize cursors per hit zone:
```pascal
procedure TestTextControlsUseIBeamCursor;
var E: TTyEdit;
begin
  E := TTyEdit.Create(nil);
  try AssertEquals(crIBeam, E.Cursor); finally E.Free; end;
end;
```
(+ analogous for Memo, SpinEdit.) For the form, add a test that drives the resize hit-test + asserts the cursor (use an access subclass exposing the cursor-set path or `FormMouseMove`); if driving the form headlessly is hard, at minimum unit-test a pure helper `TyResizeCursor(AHit): TCursor` mapping each `bh*` zone → `crSize*` and assert all mappings.
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现:**
  - `Edit.pas`/`Memo.pas`/`SpinEdit.pas` `Create`: `Cursor := crIBeam;` (uses `Controls` for `crIBeam`/TCursor — already present in most; add if missing).
  - `Form.pas`: add a pure `function TyResizeCursor(AHit: TTyBorderHit): TCursor;` (bhLeft/bhRight→crSizeWE; bhTop/bhBottom→crSizeNS; bhTopLeft/bhBottomRight→crSizeNWSE; bhTopRight/bhBottomLeft→crSizeNESW; else crDefault). In `FormMouseMove` (~524), when NOT actively resizing/moving, `Cursor := TyResizeCursor(TyHitTestBorder(...))`. (Read the actual `bh*` enum names + `TyHitTestBorder` signature first; use the real names.)
- [ ] **Step 4: 跑** — new tests PASS; existing tests green.
- [ ] **Step 5: Commit** `feat(tycontrols): I-beam cursor on text fields + resize cursors on form border zones`

---

## Task 3: 批⑥ — Button + Toggle animations default ON

**Files:** `source/tyControls.Button.pas`, `tyControls.ToggleSwitch.pas`; Tests `tests/test.button*.pas`, `test.toggleswitch.pas`.

- [ ] **Step 1: 失败测试** — assert the new default:
```pascal
procedure TestAnimationsEnabledDefaultsTrue;
var B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try AssertTrue(B.AnimationsEnabled); finally B.Free; end;
end;
```
(+ analogous for ToggleSwitch.) Register.
- [ ] **Step 2: 确认失败** (currently default False).
- [ ] **Step 3: 实现** — in both controls: change the property to `default True`, set `FAnimEnabled/FAnimationsEnabled := True` in `Create`. Nothing else changes (snap path still used headless: tests run via `RenderTo` with no handle, so `HandleAllocated=False` → MouseEnter/SetChecked still snap → existing pixel tests unchanged).
- [ ] **Step 4: 跑** — new tests PASS. **CRITICAL:** existing Button/Toggle pixel + behavior tests stay green (snap-when-headless). If a test asserted `AnimationsEnabled=False` default, update it to True (intent: documents the default). 0 failures / 15 errors.
- [ ] **Step 5: Commit** `feat(tycontrols): Button hover-fade + Toggle knob-slide enabled by default`

---

## Task 4: 批⑥ — ProgressBar fill animation

**Files:** `source/tyControls.ProgressBar.pas`; Test `tests/test.progressbar.pas`.

- [ ] **Step 1: 失败测试** — use an access subclass exposing `AdvanceAnimation`. Set Position 0→100 with a handle-less control (so the trigger sets up the animator but, per the snap rule, NO-handle snaps...). Because headless snaps, test the animator seam directly: force `AnimationsEnabled := True`, drive a *manual* animation by calling the SetPosition path that sets from/to, then `AdvanceAnimation(60)` (half of 120ms) and assert `DisplayPos` is strictly between old and new; `AdvanceAnimation(120)` → `DisplayPos = new`. Expose `DisplayPos` via the access subclass.
```pascal
procedure TestProgressFillAnimatesMidway;
var P: TProgAccess;
begin
  P := TProgAccess.Create(nil);
  try
    P.Max := 100; P.SetPositionAnimating(0);   // helper that forces the animating path
    P.SetPositionAnimating(100);
    P.AdvanceAnimation(60);
    AssertTrue('midway', (P.DisplayPos > 5) and (P.DisplayPos < 95));
    P.AdvanceAnimation(120);
    AssertTrue('settled', Abs(P.DisplayPos - 100) < 0.5);
  finally P.Free; end;
end;
```
(Design the access seam so the animating path is reachable without a window handle — e.g. an internal `SetPositionEx(v; AAnimate: Boolean)` the public `SetPosition` calls with `AAnimate := FAnimEnabled and HandleAllocated`; the test calls `SetPositionEx(v, True)` directly.)
- [ ] **Step 2: 确认失败/不编译.**
- [ ] **Step 3: 实现** — apply the **Shared Animation Pattern** (position-animation variant): add `FAnimEnabled` (default True), `FPosAnim: TTyAnimator`, `FAnimFrom/FAnimTo: Single`, `FTimer`, `DisplayPos`, `EnsureTimer/HandleTimer/AdvanceAnimation`, `Destroy` frees timer. `SetPosition` routes through the animate/snap decision. `RenderTo` (the partial-fill rect from batch④) computes the fill from `Round(DisplayPos)` mapped to Min..Max instead of `FPosition`. Keep the batch④ per-corner rounding logic, just driven by DisplayPos.
- [ ] **Step 4: 跑** — new test PASS; existing ProgressBar pixel tests (headless, snapped) UNCHANGED & green. 0 failures / 15 errors.
- [ ] **Step 5: Commit** `feat(tycontrols): ProgressBar fill eases to new Position (default on, headless-snap safe)`

---

## Task 5: 批⑥ — ScrollBar thumb animation (snap during drag; embedded off)

**Files:** `source/tyControls.ScrollBar.pas` + `ListBox.pas`, `Memo.pas` (set embedded scrollbar `AnimationsEnabled := False`); Test `tests/test.controls.scrollbar.pas`.

- [ ] **Step 1: 失败测试** — like T4: force-animating `SetPosition`, `AdvanceAnimation(60)` → thumb DisplayPos midway, `AdvanceAnimation(120)` → settled. PLUS a drag-snap test: with `FDragging := True` (via access), `SetPosition(new)` → `DisplayPos = new` immediately (no animation while dragging). Use the existing `TScrollAccess` (extend it).
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现** — apply Shared Animation Pattern (position variant) to ScrollBar. `SetPosition`: if `FDragging` → snap (`SetTargetImmediate`, DisplayPos=new) so the thumb tracks the mouse; else animate (when enabled+handle) or snap. `RenderTo`/`TyScrollThumbRect` driven by `Round(DisplayPos)` instead of `FPosition` for the thumb (the track-paging math + drag math stay on `FPosition`; only the *painted* thumb uses DisplayPos). `BeginThumbDrag` should sync DisplayPos to FPosition on grab. Add `AnimationsEnabled` (default True).
  - In `ListBox.pas` + `Memo.pas` where they create the embedded `FScrollBar`, set `FScrollBar.AnimationsEnabled := False;` right after creation (content scrolling stays instant).
- [ ] **Step 4: 跑** — new tests PASS; existing scrollbar drag/paging/geometry tests green (drag snaps → thumb pixel tests unchanged; programmatic tests via RenderTo are headless → snap). 0 failures / 15 errors.
- [ ] **Step 5: Commit** `feat(tycontrols): ScrollBar thumb eases on programmatic Position change (drag instant; embedded scrollbars static)`

---

## Task 6: 批⑥ — TrackBar thumb animation (snap during drag)

**Files:** `source/tyControls.TrackBar.pas`; Test `tests/test.trackbar.pas`.

- [ ] **Step 1: 失败测试** — same shape as T5 (animate midway/settle; `FDragging` → snap). Use the existing `TTyTrackBarProbe` (extend it).
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现** — apply Shared Animation Pattern (position variant) to TrackBar, mirroring T5: `SetPosition` snaps during `FDragging`, else animates; `RenderTo`/`ThumbRect` painted thumb from `Round(DisplayPos)` (the geometry pure-fns `TyTrackThumbOffset` etc. from batch③ take a position arg → pass `Round(DisplayPos)` for paint; keep `FPosition` for hit-test/keyboard/value). `AnimationsEnabled` default True.
- [ ] **Step 4: 跑** — new tests PASS; existing trackbar geometry/drag/keyboard tests green (drag snaps; headless snaps). 0 failures / 15 errors.
- [ ] **Step 5: Commit** `feat(tycontrols): TrackBar thumb eases on programmatic Position change (drag instant)`

---

## Task 7: 批⑥ — TabControl active-tab header cross-fade

**Files:** `source/tyControls.TabControl.pas`; Test `tests/test.tabcontrol.pas`.

- [ ] **Step 1: 失败测试** — force-animating tab switch: set TabIndex 0→1 via the animating path, `AdvanceAnimation(60)` → the active-tab header background is between the inactive and active colors (a pixel in the newly-active tab header is neither exactly inactive nor exactly active bg); `AdvanceAnimation(120)` → equals active bg. Use a controlled theme with distinct `TyTab` vs `TyTab:active` backgrounds; probe the new active tab header pixel. (If a precise mid-color probe is brittle, assert the animator seam: `DisplayActiveFade` between 0 and 1 mid, =1 settled.)
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现** — apply Shared Animation Pattern to TabControl with a 0→1 fade animator `FTabFade`. On `SetTabIndex` change: `FTabFade.Progress:=0; FTabFade.Target:=1` + animate/snap. In the header `RenderTo`, for the **newly-active** tab, blend its background from the inactive-state to active-state style via `TyLerpColor(inactiveBg, activeBg, FTabFade.Eased)`; other tabs unchanged. Resolve both `TyTab` (normal) and `TyTab:active` styles (like Button blends normal/hover). **Do NOT** touch page child-control visibility timing (pages still switch via `ShowOnlyPage` immediately — only the header color fades). `AnimationsEnabled` default True.
  - Keep it minimal/correct: at Eased=1 the active tab is exactly the active style (so existing tab pixel tests, headless-snapped, are unchanged).
- [ ] **Step 4: 跑** — new test PASS; existing tabcontrol tests green (headless snap → active tab exactly active style). 0 failures / 15 errors.
- [ ] **Step 5: Commit** `feat(tycontrols): TabControl active-tab header cross-fades on switch (header only; pages switch instantly)`

---

## Task 8: docs + full regression + matrix

**Files:** `docs/controls/*.md`; full suite + matrix.

- [ ] **Step 1: docs** — `edit.md`/`memo.md`/`spinedit.md`: I-beam cursor. `button.md`/`toggleswitch.md`/`progressbar.md`/`scrollbar.md`/`trackbar.md`/`tabcontrol.md`: `AnimationsEnabled` (default True; what animates; headless-snaps; set False for static). Note embedded scrollbars are static. Note shadows deliberately deferred (LCL embedded-control limitation).
- [ ] **Step 2: 全量 + 矩阵**
```bash
lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain
bash scripts/build-matrix.sh
```
Expected: 0 failures (+15 env); `== matrix OK ==`; heaptrc 0 (all new FTimer freed in Destroy).
- [ ] **Step 3: Commit** `docs(tycontrols): batch5+6 cursors + AnimationsEnabled per-control + spacing-constant notes`

---

## 完成后
全套件 + 矩阵 + heaptrc 0 + 终审(reviewer 核:去重零值变化、光标原生正确、每个动画 headless-snap 终态=旧像素、拖动即时、内嵌滚动条静态、timer 在 Destroy 释放);本地快进合并 main + 删分支;更新记忆(批⑤+⑥ 完成,剩阴影/完整令牌化/第二波动效)。

## Self-Review(规划者自查,已执行)
- **Spec 覆盖**:批⑤去重→T1;光标→T2;Button/Toggle 默认开→T3;Progress→T4;Scroll(+embedded off)→T5;Track→T6;Tab→T7;docs→T8。阴影按 spec 跳过。
- **无头安全**:每动画任务 Step4 显式要求现有像素测试不变(snap-when-headless),T3 显式处理"默认值断言"更新。
- **类型/名一致**:`AnimationsEnabled`/`AdvanceAnimation`/`DisplayPos`/`FAnimEnabled`/`TTyAnimator`(Advance/Eased/Running/SetTargetImmediate)/`TyLerpF/Color`/`Ty*` 常量 前后一致;位置动画统一用 `DisplayPos = TyLerpF(FAnimFrom,FAnimTo,Eased)` 范式。
- **可见行为变化**:动画默认开(spec 已列为有意变化);拖动即时、内嵌滚动条静态(避免滚动迟滞);Tab 仅表头淡入(页面即时,规避 LCL 子控件 alpha 限制)。
- **无占位符**:Shared Pattern 给完整范式;各任务给精确注入点(SetPosition/RenderTo/SetTabIndex + 文件行);测试经 access seam 直接驱动 `AdvanceAnimation`(规避无头无 timer)。
