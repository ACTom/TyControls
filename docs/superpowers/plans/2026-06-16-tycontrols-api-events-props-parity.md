# TyControls API 事件/属性 与原生对齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`. Events first (T1–T8), then properties (T9–T16), then docs (T17). Each task is self-contained; read the cited current code before editing.

**Goal:** bring tyControls' published EVENTS + PROPERTIES to near-LCL-native parity. Most of the event win is a publish-only edit to the two base classes (every override already calls `inherited`); plus per-control events, 2 behavioral bug fixes, and the missing properties.

**Tech Stack:** Free Pascal/Lazarus LCL; FPCUnit; PPI=96; headless event injection via overridden methods + access subclasses.

**约定:** `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`. Baseline **0 failures + 15 env errors (1407 headless noise)**. Commit `feat(tycontrols): …`. `examples/demo/*` 不 stage. Each task: existing tests stay green; new tests inject via methods (no GUI handle needed).

---

## Shared patterns

- **Publish an inherited event/prop:** add `property OnX;` (no type) in the `published` section — re-publishes the ancestor's. Works ONLY because the override calls `inherited` (verified).
- **New control-specific event:** private `FOnX: T<Sig>Event;` + published `property OnX: T<Sig>Event read FOnX write FOnX;` + a `procedure DoX; begin if Assigned(FOnX) then FOnX(Self{,args}); end;` fired at the right point.
- **Headless event test:** create the control (no Parent/Show needed), assign a handler that flips a flag/counter, invoke the method (`MouseDown`/`KeyDown`/`Click`/`Checked:=`/`SetPosition` via an access subclass or public setter), assert the flag. (No window handle required — the dispatch is synchronous in the overridden method → inherited.)
- **Don't touch** theme-conflicting props (`Color/ParentColor/ParentFont/Brush/Bevel*/BorderStyle/DoubleBuffered`) or add `OnPaint` (spec §5).

---

## Task 1: 基线事件/属性发布(base classes)

**Files:** `source/tyControls.Base.pas`; Test `tests/test.base.pas` (or a new `tests/test.baseevents.pas`, registered).

`TTyGraphicControl` published block = Base.pas:38-45 (Enabled/Font/Hint/ShowHint/StyleClass/Controller). `TTyCustomControl` = :74-83 (+TabOrder/TabStop).

- [ ] **Step 1: 失败测试** — assert a graphic control (e.g. `TTyLabel`) and a windowed control (e.g. `TTyEdit`) now expose the events by firing them headlessly:
```pascal
procedure TestBaselineMouseEventFires;
var L: TTyLabel; fired: Boolean;
  procedure H(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer); begin fired := True; end;
begin
  L := TTyLabel.Create(nil);
  try
    fired := False; L.OnMouseDown := @H;   // compile-fails until published
    TLabelAccess(L).DoMouseDown(mbLeft, [], 1, 1);  // access exposes MouseDown
    AssertTrue(fired);
  finally L.Free; end;
end;
procedure TestBaselineKeyEventFiresOnWindowed;  // OnKeyDown on TTyEdit, similar
```
(Add access subclasses exposing `MouseDown`/`KeyDown` if not present.) Also a compile-discriminator: a `TTyLabel.OnKeyDown := @...` must NOT compile (graphic has no key events) — verify by NOT adding it. Register.
- [ ] **Step 2: 确认失败/不编译** (OnMouseDown not published).
- [ ] **Step 3: 实现** — add to **TTyGraphicControl** published block (Base.pas ~38-45):
```pascal
    property OnClick; property OnDblClick;
    property OnMouseDown; property OnMouseUp; property OnMouseMove;
    property OnMouseEnter; property OnMouseLeave;
    property OnMouseWheel; property OnMouseWheelUp; property OnMouseWheelDown;
    property OnContextPopup; property OnResize; property OnChangeBounds;
    property PopupMenu; property Constraints; property BorderSpacing;
    property Cursor; property ParentShowHint; property Action;
```
  Add the SAME block to **TTyCustomControl** published (~74-83), PLUS the focusable Tier B (custom only):
```pascal
    property OnKeyDown; property OnKeyUp; property OnKeyPress; property OnUTF8KeyPress;
    property OnEnter; property OnExit; property OnEditingDone;
```
  IMPORTANT: if a specific event/prop isn't declared on the ancestor (compile error — e.g. some may not exist on `TGraphicControl`/`TCustomControl`), DROP just that one from that block and note it (don't fight the compiler). Likely-safe set is above; verify by building. Do NOT add Tier B to the graphic block.
- [ ] **Step 4: 跑** — new tests PASS; **ALL existing tests UNCHANGED & green** (publishing is additive). 0 failures / 15 errors.
- [ ] **Step 5: Commit** `feat(tycontrols): publish standard mouse/key/focus events + common props on base classes`

---

## Task 2: Edit OnChange-on-typing (BUG FIX)

**Files:** `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

`DoChange` (Edit.pas:225-228) fires `FOnChange`; currently called ONLY from `RestoreState` (:274). Typing paths don't fire it.

- [ ] **Step 1: 失败测试** — assign `OnChange` (counter), inject a char via `UTF8KeyPress`/`InjectKey`, assert counter==1; backspace → +1; `SelText`/`SetText` → +1; and undo/redo still fires.
```pascal
procedure TestOnChangeFiresOnTyping;
var E: TEditAccess; n: Integer;
begin
  E := TEditAccess.Create(nil);
  try
    E.OnChange := <handler that incs n>;
    n := 0; E.DoUTF8KeyPress('a'); AssertEquals('type', 1, n);
    n := 0; E.DoKeyDown(VK_BACK, []); AssertEquals('backspace', 1, n);
    n := 0; E.Text := 'hello'; AssertTrue('settext fired', n >= 1);
  finally E.Free; end;
end;
```
- [ ] **Step 2: 确认失败** (n stays 0 on typing).
- [ ] **Step 3: 实现** — find the text-mutation funnel and ensure `DoChange` fires EXACTLY ONCE per user-facing text change. READ Edit.pas: the low-level ops are `InjectKey`/`InjectBackspace`/`InjectDelete`/`DeleteSelection`/`InsertStringAt`(paste)/`CutToClipboard`/`SetText`. Preferred: if there's a single funnel (e.g. all keyboard edits route through one method), call `DoChange` there after a real change; else call `DoChange` at the end of each public mutation. AVOID double-fire on selection-replace (delete+insert) — fire once. `SetText` (:428): add `DoChange` after the assignment (it changed FText). Keep `RestoreState`'s `DoChange`. Respect `FSuspendUndo` is about UNDO, not OnChange — OnChange should still fire for composite ops, once. Verify no infinite recursion (DoChange must not re-enter a mutation).
- [ ] **Step 4: 跑** — typing/backspace/delete/paste/cut/SetText each fire OnChange once; undo/redo still fire; existing Edit tests green.
- [ ] **Step 5: Commit** `fix(tycontrols): TTyEdit.OnChange now fires on typing/edit (was only on undo/redo)`

---

## Task 3: CheckBox + RadioButton OnChange

**Files:** `source/tyControls.CheckBox.pas`; Test the checkbox test unit.

`TTyCheckBox.SetChecked` (:86-91) and `TTyRadioButton.SetChecked` only `Invalidate`. Neither has `OnChange`.

- [ ] **Step 1: 失败测试** — `Checked := True` fires `OnChange`; setting to the same value does NOT; Click toggles and fires. For radio, checking fires its OnChange (and the auto-unchecked sibling fires its own).
- [ ] **Step 2: 确认失败/不编译** (no OnChange).
- [ ] **Step 3: 实现** — both classes: private `FOnChange: TNotifyEvent;` + published `property OnChange: TNotifyEvent read FOnChange write FOnChange;` + in `SetChecked`, after `FChecked := AValue; Invalidate;` add `if Assigned(FOnChange) then FOnChange(Self);` (guarded by the existing `if FChecked = AValue then Exit;` so it fires only on real change). For RadioButton, the `UncheckSiblings` path sets siblings' FChecked — ensure siblings fire their OnChange too (route through their SetChecked or fire explicitly).
- [ ] **Step 4: 跑** — new tests PASS; existing checkbox/radio tests green.
- [ ] **Step 5: Commit** `feat(tycontrols): TTyCheckBox/TTyRadioButton.OnChange`

---

## Task 4: ComboBox OnSelect/OnDropDown/OnCloseUp

**Files:** `source/tyControls.ComboBox.pas`; Test combobox unit.

- [ ] **Step 1: 失败测试** — selecting an item (via the closed-state keyboard/SelectItem path) fires `OnSelect`; `DropDown` fires `OnDropDown`; `CloseUp` fires `OnCloseUp`. (`DropDown` is virtual — use it / an access.)
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现** — add `FOnSelect/FOnDropDown/FOnCloseUp: TNotifyEvent` + published `OnSelect/OnDropDown/OnCloseUp` + `DoSelect/DoDropDown/DoCloseUp`. Fire `DoSelect` when the user picks an item (the SelectItem/keyboard-select path, distinct from programmatic ItemIndex if the lib distinguishes — match LCL: OnSelect on user pick). Fire `DoDropDown` in `DropDown`, `DoCloseUp` in `CloseUp`. READ ComboBox.pas for the exact methods. Publish `OnClick` if not already (comes via base now — verify base T1 covers it; ComboBox derives TTyCustomControl).
- [ ] **Step 4: 跑;Step 5: Commit** `feat(tycontrols): TTyComboBox OnSelect/OnDropDown/OnCloseUp`

---

## Task 5: ScrollBar OnScroll + Track/ScrollBar wheel-step

**Files:** `source/tyControls.ScrollBar.pas`, `tyControls.TrackBar.pas`; Tests both units.

- [ ] **Step 1: 失败测试** — ScrollBar: a handler `OnScroll(Sender; ScrollCode; var ScrollPos)` fires when Position changes via keyboard/track-click/arrow (assert it's called with a sane ScrollCode). Wheel: `DoMouseWheel` over ScrollBar steps Position by SmallChange; over TrackBar steps by LineSize. (Inject via the `DoMouseWheel`/access.)
- [ ] **Step 2: 确认失败** (no OnScroll; wheel no-op).
- [ ] **Step 3: 实现:**
  - ScrollBar: `type TTyScrollEvent = procedure(Sender: TObject; ScrollCode: TScrollCode; var ScrollPos: Integer) of object;` (use LCL `TScrollCode` from `StdCtrls`/`Controls`). `FOnScroll` + published `OnScroll`. Fire `DoScroll(code, pos)` from the keyboard/arrow/track-paging paths (map to scEndScroll/scLineUp/scPageDown/etc.) BEFORE committing Position, honoring the `var ScrollPos` the handler may adjust. Keep OnChange too.
  - Both: override `function DoMouseWheel(Shift; WheelDelta; MousePos): Boolean; override;` — `Position := Position - Sign(WheelDelta)*<step>` (ScrollBar step=SmallChange, TrackBar step=LineSize; wheel-up increases or decreases per platform convention — match native: wheel up → decrease scrollbar Position / increase trackbar? use the LCL convention, document). Return True (handled). Call inherited for the OnMouseWheel event to still fire.
- [ ] **Step 4: 跑;Step 5: Commit** `feat(tycontrols): TTyScrollBar.OnScroll + wheel-step on ScrollBar/TrackBar`

---

## Task 6: TabControl OnChanging (veto) + OnReorder

**Files:** `source/tyControls.TabControl.pas`; Test tabcontrol unit.

- [ ] **Step 1: 失败测试** — `OnChanging(Sender; NewIndex; var AllowChange)` returning `AllowChange:=False` prevents the tab switch (TabIndex unchanged); returning True allows it (+ OnChange fires after). Drag-reorder fires `OnReorder`.
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现** — `TTyTabChangingEvent = procedure(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean) of object;`. In `SetTabIndex`, before committing the new index: call `DoChanging(newIndex, allow)`; if not allow, abort (keep old index). `OnReorder: TNotifyEvent` (or with from/to indices) fired at the end of the drag-reorder commit (READ the reorder code). Keep `OnChange`/`OnTabClose`.
- [ ] **Step 4: 跑;Step 5: Commit** `feat(tycontrols): TTyTabControl OnChanging (veto) + OnReorder`

---

## Task 7: Memo OnSelectionChange + publish AnimationsEnabled + ProgressBar OnChange

**Files:** `Memo.pas`, `Button.pas`, `ProgressBar.pas`, `ScrollBar.pas`; Tests respective.

- [ ] **Step 1: 失败测试** — Memo: moving the caret / changing selection (without text change) fires `OnSelectionChange`. ProgressBar: `Position:=` fires `OnChange`. AnimationsEnabled now published on Button/ProgressBar/ScrollBar (assert it's settable as a published prop — or a compile/RTTI check; simplest: a test that sets it — already public, so this is about the `published` keyword; a `GetPropInfo` RTTI test or just confirm streaming. A light test: it's published if `IsPublishedProp(B, 'AnimationsEnabled')`).
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现:**
  - Memo: `FOnSelectionChange: TNotifyEvent` + published + fire `DoSelectionChange` from the caret/selection funnel (Memo has AfterCaretMove-style funnel — read it) when selection or caret changes without a text mutation.
  - ProgressBar: `FOnChange: TNotifyEvent` + published `OnChange` + fire from `SetPosition` (and optionally SetMin/SetMax) on real change.
  - Move `AnimationsEnabled` from `public` to `published` in Button, ProgressBar, ScrollBar (read each — the property exists in public; re-place under published, keep `default True`).
- [ ] **Step 4: 跑;Step 5: Commit** `feat(tycontrols): Memo.OnSelectionChange, ProgressBar.OnChange, publish AnimationsEnabled (Button/Progress/Scroll)`

---

## Task 8: FormChrome lifecycle events + TitleBar mouse-slot isolation

**Files:** `source/tyControls.Form.pas`; Test `tests/test.form.pas`/`test.formchrome.pas`.

- [ ] **Step 1: 失败测试** — `OnCloseQuery(Sender; var CanClose)` returning False prevents close (FForm.Close not called); `OnClose`/`OnMinimize`/`OnMaximize`/`OnRestore` fire from their actions. AND: `TTyTitleBar` now exposes `OnMouseDown` to the user WITHOUT breaking the chrome's window-drag (i.e. the chrome's drag still works after a user assigns OnMouseDown — because chrome uses a method override, not the event slot).
- [ ] **Step 2: 确认失败.**
- [ ] **Step 3: 实现:**
  - `TTyFormChrome`: add `FOnCloseQuery: TCloseQueryEvent` (`procedure(Sender; var CanClose: Boolean)`), `FOnClose/FOnMinimize/FOnMaximize/FOnRestore: TNotifyEvent` + published. In `DoClose`: `CanClose := True; DoCloseQuery(CanClose); if CanClose then begin DoClose-event; FForm.Close; end;`. Fire Minimize/Maximize/Restore from the caption-button handlers.
  - **TitleBar isolation:** currently `TTyFormChrome` does `FTitleBar.OnMouseDown := @...` etc. Change `TTyTitleBar` to handle drag/double-click via **overridden methods** (`MouseDown`/`MouseMove`/`MouseUp`/`DblClick`) that call a chrome callback (e.g. an `OnDragXxx` internal field the chrome sets, or a direct reference), AND call `inherited` so the user's published `OnMouseDown` still fires. Goal: the base-published `OnMouseDown/Move/Up/DblClick` on TTyTitleBar are now user-assignable without clobbering the drag. READ Form.pas to pick the cleanest refactor (likely: TTyTitleBar gets an internal `FChrome` ref + method overrides that call FChrome.HandleTitleDrag + inherited).
- [ ] **Step 4: 跑;Step 5: Commit** `feat(tycontrols): TTyFormChrome lifecycle events + free TitleBar mouse-event slots (drag via method override)`

---

## Task 9: Edit properties

**Files:** `source/tyControls.Edit.pas`; Test edit unit.

- [ ] Add (each with a failing test first): `SelStart`/`SelLength`/`SelText` (read/write, mapped to the existing `FSelAnchor`/`FCaret` selection model — SelStart=min(anchor,caret), SelLength=|caret-anchor|, SelText=the selected substring; setting them moves the selection); `Alignment: TAlignment` (default taLeftJustify; affects DrawText H-align + caret X); `CharCase: TEditCharCase` (ecNormal/ecUpperCase/ecLowerCase — transform inserted chars in the typing path); `NumbersOnly: Boolean` (reject non-digit input). Test each semantic. Commit `feat(tycontrols): TTyEdit SelStart/SelLength/SelText + Alignment/CharCase/NumbersOnly`.

---

## Task 10: Memo properties

**Files:** `Memo.pas`; Test memo unit.

- [ ] Add: `SelStart`/`SelLength`/`SelText`/`CaretPos` (flat-offset accessors over the line/col model); `Text` (whole-string get/set over `Lines`); `WantTabs: Boolean` (Tab inserts vs navigates); `WantReturns: Boolean` (Enter newlines vs default-button). `ScrollBars: TScrollStyle` (ssNone/ssVertical/ssHorizontal/ssBoth + auto variants — control the existing FScrollBar visibility). **DEEP-FLAG:** if `ScrollBars` full enum proves a large feature, implement ssNone/ssVertical/ssAutoVertical (the meaningful ones for a vertical memo) and note the rest deferred. Test each. Commit `feat(tycontrols): TTyMemo Sel*/CaretPos/Text/WantTabs/WantReturns/ScrollBars`.

---

## Task 11: SpinEdit properties

**Files:** `SpinEdit.pas`; Test spinedit unit.

- [ ] Add: `ReadOnly: Boolean` (blocks text edit + the +/- buttons? match LCL TSpinEdit: ReadOnly blocks editing; keep stepping disabled too for consistency — decide & document), `Alignment`, `MaxLength`. Test ReadOnly intercepts editing. Commit `feat(tycontrols): TTySpinEdit ReadOnly + Alignment + MaxLength`.

---

## Task 12: ComboBox properties

**Files:** `ComboBox.pas`; Test combobox unit.

- [ ] Add: `DropDownCount: Integer` (visible rows in the dropdown popup — size the popup), `Sorted: Boolean` (sort Items, maintain ItemIndex on the same item), `MaxLength`, `CharCase`. **DEEP-FLAG:** `Sorted` must keep the selected item selected after sorting — test it. Commit `feat(tycontrols): TTyComboBox DropDownCount/Sorted/MaxLength/CharCase`.

---

## Task 13: Button properties (Default/Cancel/ModalResult)

**Files:** `Button.pas`; Test button unit.

- [ ] Add `Default: Boolean`, `Cancel: Boolean`, `ModalResult: TModalResult`. Default = clicked on form Enter; Cancel = on Esc; clicking sets the host form's ModalResult. **DEEP-FLAG:** the Enter/Esc routing needs the form's dialog-key mechanism. Implement via: handle `CM_DIALOGKEY`/`Application` key, OR the simplest LCL-idiomatic path (a `TButton` sets `Default`/`Cancel` and the form's `DefaultControl`/`CancelControl` or CM_DIALOGCHAR). Test: with Default=True, a form-level Enter fires the button's Click (inject via the form's key path or a focused-control KeyDown that routes). If full form-routing is too deep, implement the properties + the ModalResult-on-click + best-effort Default/Cancel and FLAG the routing depth. Commit `feat(tycontrols): TTyButton Default/Cancel/ModalResult`.

---

## Task 14: ToggleSwitch Caption

**Files:** `ToggleSwitch.pas`; Test toggle unit.

- [ ] Add `Caption: string` — drawn as a text label beside the switch (resolve font/size from style like other captions; lay out switch + gap + caption). Test the caption renders (pixel ink present) + the switch still toggles. Commit `feat(tycontrols): TTyToggleSwitch.Caption`.

---

## Task 15: Label properties

**Files:** `TyLabel.pas`; Test label unit.

- [ ] Add: `Alignment`, `Layout` (vertical), `WordWrap: Boolean`, `AutoSize: Boolean` (resize to text extent), `Transparent: Boolean` (confirm current default), `FocusControl: TWinControl` (click/mnemonic focuses target). **DEEP-FLAG:** `AutoSize`+`WordWrap` need text measurement + `CalculatePreferredSize`/`SetBounds`; implement using the painter's measure or LCL canvas measure; if the full AutoSize+WordWrap interaction proves large, implement Alignment/Layout/Transparent/FocusControl now and flag AutoSize/WordWrap if needed. Test each. Commit `feat(tycontrols): TTyLabel Alignment/Layout/WordWrap/AutoSize/Transparent/FocusControl`.

---

## Task 16: ListBox properties

**Files:** `ListBox.pas`; Test listbox unit.

- [ ] Add `Sorted: Boolean` (sort Items, maintain ItemIndex/selection). **DEEP-FLAG `Columns`:** multi-column listbox is a large rendering change — assess in TDD; if large, do `Sorted` now and split `Columns` to a follow-up (note it). Test Sorted ordering + selection persistence. Commit `feat(tycontrols): TTyListBox.Sorted (+ Columns assessed)`.

---

## Task 17: docs + full regression + matrix

**Files:** `docs/controls/*.md`, new `docs/events.md`; full suite + matrix.

- [ ] **Step 1: docs** — new `docs/events.md`: the baseline event set all controls now expose (Tier A + Tier B), the per-control specific events, and the DELIBERATELY-SKIPPED theme-conflicting props (Color/ParentColor/ParentFont/Bevel/BorderStyle/DoubleBuffered) with the reason. Update each affected `docs/controls/*.md` with its new events + properties.
- [ ] **Step 2: 全量 + 矩阵**
```bash
lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain
bash scripts/build-matrix.sh
```
Expected: 0 failures (+15 env); `== matrix OK ==`; heaptrc 0.
- [ ] **Step 3: Commit** `docs(tycontrols): document baseline events, per-control events/properties, and skipped theme-conflict props`

---

## 完成后
全套件 + 矩阵 + heaptrc 0 + 终审(reviewer 核:基线发布点亮全部且现有像素测试不变、2 个 bug 修复正确、各专属事件触发/否决语义、属性 getter/setter 语义、TitleBar 拖动经方法 override 不被用户事件覆盖、跳过项确未引入、深 flag 项的取舍记录);本地快进合并 main + 删分支;更新记忆。

## Self-Review(规划者自查,已执行)
- **Spec 覆盖**:基线发布→T1;事件 bug→T2(Edit)/T3(CheckBox+Radio);专属事件→T4(Combo)/T5(Scroll+wheel)/T6(Tab)/T7(Memo+AnimationsEnabled+Progress)/T8(Chrome+TitleBar);属性→T9–T16;文档→T17。跳过项/OnPaint/三态 按 spec §5 排除。
- **关键事实锚定**:base published 块行号、Edit `DoChange`/`FSuspendUndo`/SetText、CheckBox/Radio `SetChecked` 均已读实。其余任务引用审计 file:line + 指示实现者先读当前方法。
- **无头安全**:事件经方法注入(无需 handle);属性多为纯 getter/setter + 渲染像素(PPI=96)。
- **风险/深 flag**:Memo ScrollBars、ComboBox Sorted、Button Default/Cancel 路由、Label AutoSize/WordWrap、ListBox Columns 显式标注"过深则拆后续"。
- **类型/名一致**:`DoChange`/`FOnChange`/`OnSelectionChange`/`TTyScrollEvent`/`TTyTabChangingEvent`/`DoChanging`/`DoSelect` 等前后一致;基线发布 Tier A/B 分块明确(graphic 不含 Tier B)。
- **TitleBar**:明确改为方法 override + inherited,腾出事件槽(spec §3.4 / §6.6)。
