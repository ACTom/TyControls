# TyControls v1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Phase 2 of TyControls: five Tier-2 controls + a real ComboBox dropdown, full Edit editing (caret/selection/clipboard), style-pipeline polish, modified-LGPL license, and macOS-verifiable native window enhancements.

**Architecture:** Everything follows the established v1 patterns — controls hold no colors and render via `RenderTo(ACanvas, ARect, APPI)` → `DrawFrame` → `TTyPainter`; sub-parts get their own typeKey (precedent: `TyCaptionButton`); state/geometry logic is headless-testable; every control ships with tests + 3 theme rules + an example project + a Chinese doc.

**Tech Stack:** FPC 3.2.2+/Lazarus, LCL, BGRABitmap (package `BGRABitmapPack`), FPCUnit, LazUTF8, Clipbrd.

**Spec:** `docs/superpowers/specs/2026-06-13-tycontrols-v1.1-design.md` (authoritative for any ambiguity).

---

## Build environment (read once, applies to every task)

- Repo `/Users/tom/Projects/TyControls`, branch `feature/tycontrols-v1.1`.
- `lazbuild` is on PATH. Test loop: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain` → must end `0 errors, 0 failures`. Baseline: 148 tests.
- New test units: add to `tests/tytests.lpr` uses clause; `tests/tytests.lpi` already has the search paths.
- Examples build standalone: `lazbuild examples/<n>/<n>_example.lpi`. Template: `examples/button/` (3 files, pure-code UI, `ThemesDir` upward-search helper).
- Established source patterns to mirror: `source/tyControls.ScrollBar.pas` (geometry helper + control), `source/tyControls.CheckBox.pas` (toggle controls), `source/tyControls.ComboBox.pas`, `source/tyControls.Base.pas` (shared members), `source/tyControls.Form.pas` (chrome).
- Commit after each task with the message given in the task.

## Pinned contract (names used across tasks — do not drift)

```pascal
// LISTBOX — unit source/tyControls.ListBox.pas
TTyListBox = class(TTyCustomControl)            // typeKey 'TyListBox'
  property Items: TStringList;                  // owned, freed in Destroy
  property ItemIndex: Integer;                  // -1 = none; setter clamps+Invalidate+OnChange on real change
  property ItemHeight: Integer;                 // logical px, default 24, scaled by PPI at paint
  property TopIndex: Integer;                   // first visible row (scroll state)
  property OnChange: TNotifyEvent;
  procedure SelectItem(AIndex: Integer);        // public, headless-testable
  function VisibleRows: Integer;                // ClientHeight div scaled ItemHeight (>=1)
end;
// items rendered with ResolveStyle('TyListItem','', states): hover row -> [tysHover], selected -> [tysActive]

// COMBOBOX dropdown — modify source/tyControls.ComboBox.pas
property DroppedDown: Boolean (read-only getter)
procedure DropDown;   // opens popup
procedure CloseUp;    // closes popup
// popup: TForm created on demand, BorderStyle=bsNone, PopupParent=GetParentForm(Self),
// hosts a TTyListBox (Items shared via Assign), OnDeactivate+Esc close, item select -> SelectItem+CloseUp.
// Click toggles DropDown/CloseUp (click-cycle behavior REMOVED).

// PROGRESSBAR — unit source/tyControls.ProgressBar.pas
TTyProgressBar = class(TTyGraphicControl)       // typeKey 'TyProgressBar'; fill typeKey 'TyProgressFill'
  property Min, Max, Position: Integer;         // defaults 0/100/0; Position clamped
end;
function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer): TRect; // pure, exported

// TOGGLESWITCH — unit source/tyControls.ToggleSwitch.pas
TTyToggleSwitch = class(TTyCustomControl)       // typeKey 'TyToggleSwitch'; ON state -> tysActive in CurrentStates
  property Checked: Boolean;
  property OnChange: TNotifyEvent;
  procedure Toggle;                             // public; Click and Space call it
end;

// TRACKBAR — unit source/tyControls.TrackBar.pas
TTyTrackBar = class(TTyCustomControl)           // typeKey 'TyTrackBar'; thumb typeKey 'TyTrackThumb'
  property Min, Max, Position: Integer;         // defaults 0/100/0
  property OnChange: TNotifyEvent;              // fires only on real Position change
  function ThumbRect: TRect;                    // public for tests
  procedure DragTo(AXAlongTrack: Integer);      // public, headless-testable (mouse handlers call it)
end;

// GROUPBOX — unit source/tyControls.GroupBox.pas
TTyGroupBox = class(TTyCustomControl)           // typeKey 'TyGroupBox'
  property Caption;                             // drawn embedded in the top border
end;

// EDIT (full editing) — modify source/tyControls.Edit.pas
property CaretPos: Integer;                     // codepoint index 0..UTF8Length(Text); clamped
property SelStart: Integer;                     // codepoint index of selection start (min of anchor/caret)
property SelLength: Integer;                    // codepoints; 0 = no selection
function SelText: string;
procedure SelectAll;
procedure CopyToClipboard; procedure CutToClipboard; procedure PasteFromClipboard;
// internal: FCaret, FSelAnchor (codepoint indices). All ops via LazUTF8 (UTF8Copy/UTF8Length).
// Keys: Left/Right/Home/End (+Shift extends), Backspace/Delete, printable insert (replaces selection),
// Ctrl+A / Ctrl+C/X/V — accept BOTH ssCtrl and ssMeta. Mouse: click positions caret, drag selects,
// double-click selects all.

// CAPTIONBUTTON — modify source/tyControls.Form.pas
property ShowGlyphOnHoverOnly: Boolean;         // default False; True: glyph drawn only when hover/pressed

// FORMCHROME DPI — modify source/tyControls.Form.pas
function TyRescaleChromeMetric(AValue, AFromPPI, AToPPI: Integer): Integer; // pure, exported: MulDiv semantics
```

New typeKeys (themes must style ALL of them): `TyListBox`, `TyListItem`, `TyProgressBar`, `TyProgressFill`, `TyToggleSwitch`, `TyTrackBar`, `TyTrackThumb`, `TyGroupBox`.

---

## P1 · POLISH

### Task POLISH.1: ScrollBar thumb uses themed TextColor

**Files:** Modify `source/tyControls.ScrollBar.pas` (RenderTo); Test `tests/test.controls.scrollbar.pas`; possibly themes.

- [ ] Failing test: render a scrollbar offscreen with a stylesheet where `TyScrollBar { background: #202020; color: #FF0000; }`, assert a pixel inside the thumb rect is red-dominant and a track pixel outside the thumb is not.
- [ ] Implement: in `RenderTo`, fill the thumb with a solid `TTyFill` built from `S.TextColor` (`tfkSolid`) instead of `S.Background`. Keep radius behavior.
- [ ] Check all 3 themes give `TyScrollBar` a sensible `color` (thumb) distinct from `background` (track); adjust themes if a theme leaves the thumb invisible.
- [ ] Suite green. Commit: `fix(tycontrols): scrollbar thumb uses themed color (TextColor)`

### Task POLISH.2: CheckBox/Radio render through DrawFrame

**Files:** Modify `source/tyControls.CheckBox.pas` (both RenderTo); Test `tests/test.checkbox.pas`; themes if needed.

- [ ] Failing test: with a stylesheet `TyCheckBox { opacity: 0.5; background: #FF0000; }`, RenderTo over a white bitmap → assert the pixel shows blended (not pure) red, proving DrawFrame ran and opacity applied.
- [ ] Implement: both `TTyCheckBox.RenderTo` and `TTyRadioButton.RenderTo` call `DrawFrame(P, ARect, S)` first, then glyph + caption (unchanged layout).
- [ ] Verify the 3 themes keep these controls visually transparent-backed (add explicit `background: alpha(#000000, 0);` only if a base rule now paints something unwanted).
- [ ] Suite green. Commit: `fix(tycontrols): checkbox/radio render via DrawFrame (opacity/shadow/background now apply)`

### Task POLISH.3: Modified-LGPL license

**Files:** Create `COPYING.modifiedLGPL.txt`; Modify `README.md`.

- [ ] Add the standard FPC/Lazarus modified-LGPL text (LGPL-2.1 + the static-linking exception clause as shipped in Lazarus's own COPYING.modifiedLGPL.txt — reproduce that exact wording, do not paraphrase legal text).
- [ ] README: add `## 许可` section — 修改版 LGPL,允许静态链接进闭源应用,修改库本身需开源;链接许可文件.
- [ ] Commit: `docs: add modified-LGPL license`

## P2 · EDIT (full editing)

### Task EDIT.1: Caret model + keyboard movement + insert/delete at caret

**Files:** Modify `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

- [ ] Failing tests (table): with Text=`'a你b'` (3 codepoints):
  - `CaretPos` defaults to end after SetText (3); setting CaretPos=99 clamps to 3, -1 clamps to 0.
  - `InjectKey('X')` at CaretPos=1 → Text=`'aX你b'`, CaretPos=2.
  - Backspace at CaretPos=2 (after `'你'`... construct explicitly) removes ONE codepoint before caret; Delete removes one after.
  - KeyDown VK_LEFT/VK_RIGHT move by one codepoint and clamp at ends; VK_HOME→0, VK_END→UTF8Length.
- [ ] Implement: `FCaret` field; rewrite `InjectKey`/`InjectBackspace` (+ new `InjectDelete`) caret-aware using LazUTF8; `KeyDown` handles VK_LEFT/RIGHT/HOME/END/DELETE. Keep UTF-8 regression tests passing.
- [ ] Suite green. Commit: `feat(tycontrols): caret-aware editing in TTyEdit (UTF-8 codepoint model)`

### Task EDIT.2: Selection model + keyboard selection

**Files:** Modify `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

- [ ] Failing tests: `FSelAnchor` semantics via public API — after SetText, SelLength=0; Shift+Right twice from 0 → SelStart=0, SelLength=2, SelText=first two codepoints; typing a char with active selection replaces it (Text + caret correct); Backspace with selection deletes selection only; `SelectAll` → SelStart=0, SelLength=UTF8Length; plain (unshifted) Left/Right collapses selection to its edge.
- [ ] Implement: anchor field; Shift-modified movement extends; helpers `HasSelection`, `DeleteSelection`. Ctrl+A (and ssMeta+A) → SelectAll.
- [ ] Suite green. Commit: `feat(tycontrols): selection model in TTyEdit (Shift+keys, replace-on-type, Ctrl+A)`

### Task EDIT.3: Mouse caret/selection + clipboard

**Files:** Modify `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

- [ ] Mouse: expose `CaretIndexAtX(AX: Integer): Integer` (pure-ish: cumulative codepoint widths via a TBitmap canvas measure at current font; nearest boundary). Failing test: monospace-ish assertion — index 0 at x≤left padding; index = UTF8Length at far right. MouseDown sets caret+anchor via it; MouseMove (button down) moves caret (drag-select); double-click selects all (use a click-counter on MouseDown with `ssDouble` in Shift).
- [ ] Clipboard: `CopyToClipboard` (writes SelText via Clipbrd), `CutToClipboard` (copy+delete selection), `PasteFromClipboard` (insert clipboard text at caret/replace selection, strip CR/LF). KeyDown: Ctrl/Meta+C/X/V. Failing tests use the real Clipboard (set it, paste, assert Text); if the headless cocoa clipboard proves flaky in tests, inject a protected virtual `ReadClipboard/WriteClipboard` pair and test through overrides — prefer the real one first.
- [ ] Suite green. Commit: `feat(tycontrols): mouse caret/drag-select and clipboard in TTyEdit`

### Task EDIT.4: Caret + selection rendering

**Files:** Modify `source/tyControls.Edit.pas` (RenderTo); Test `tests/test.edit.pas`.

- [ ] Failing pixel test: stylesheet gives `TyEdit:focus { border-color: #0000FF; }`; render focused edit with a selection covering known glyph span → assert a pixel inside the selection band differs from the plain background and carries blue dominance (selection fill = focus border-color at ~35% alpha); assert caret column pixel at CaretPos x-offset is text-colored when no selection.
- [ ] Implement in RenderTo: selection band drawn before text (rect from cumulative widths of SelStart..SelStart+SelLength); caret vertical line at caret x (existing caret code adapted from fixed-left to measured x).
- [ ] Suite green. Commit: `feat(tycontrols): render selection band and caret at measured position`

## P3 · LISTBOX

### Task LIST.1: TTyListBox core

**Files:** Create `source/tyControls.ListBox.pas`; Test (new) `tests/test.listbox.pas` (+ tytests.lpr uses).

- [ ] Failing tests: typeKey='TyListBox'; Items owned (free test via heaptrc-clean suite); SelectItem clamps (out-of-range → -1) and fires OnChange only on real change; keyboard VK_UP/VK_DOWN move ItemIndex within bounds; `VisibleRows` math (ClientHeight 100, ItemHeight 24@96ppi → 4); `TopIndex` clamps to keep selection visible after keyboard move (ItemIndex below view → TopIndex increases).
- [ ] Implement per pinned contract (mirror ComboBox's Items handling + ScrollBar's keyboard pattern). Mouse click → `SelectItem(TopIndex + Y div scaledItemHeight)` when in range. Wheel scrolls TopIndex.
- [ ] Suite green. Commit: `feat(tycontrols): add TTyListBox with selection, keyboard and scroll state`

### Task LIST.2: ListBox rendering + embedded scrollbar

**Files:** Modify `source/tyControls.ListBox.pas`; Test `tests/test.listbox.pas`.

- [ ] Failing pixel test: stylesheet `TyListBox { background:#101010; } TyListItem { color:#CCCCCC; } TyListItem:active { background:#3B82F6; }` → RenderTo with 3 items, ItemIndex=1: row-1 band pixel is blue-dominant; row-0 is not.
- [ ] Implement RenderTo: DrawFrame for the box; per visible row resolve `TyListItem` with `[tysActive]` for selected / `[tysHover]` for hovered row (track hover row in MouseMove) and paint row band (FillBackground) + item text (DrawText, Padding-inset).
- [ ] Embedded scrollbar: when Items.Count > VisibleRows, create/show a child `TTyScrollBar` (Align=alRight, width 12 logical) bound: Max=Items.Count-VisibleRows, Position=TopIndex, OnChange syncs TopIndex; hidden otherwise. Test: count>rows → scrollbar child exists+visible; shrink items → hidden.
- [ ] Suite green. Commit: `feat(tycontrols): ListBox themed item rendering and embedded scrollbar`

## P4 · DROPDOWN

### Task DROP.1: Real ComboBox dropdown popup

**Files:** Modify `source/tyControls.ComboBox.pas`; Test `tests/test.controls.combobox.pas`; update `examples/combobox/umain.pas` comment + `docs/controls/combobox.md` + `docs/KNOWN_GAPS.md` (remove the no-popup gap).

- [ ] Failing tests (headless-safe): `DropDown` creates the popup form (assert `DroppedDown=True`, popup ListBox shares item count); selecting in the popup's ListBox (call its SelectItem + simulated confirm) updates combo Text/ItemIndex and `DroppedDown=False`; `CloseUp` idempotent; combo `Click` now toggles DroppedDown (old cycle test REPLACED — clicking no longer changes ItemIndex).
- [ ] Implement per contract: lazy popup TForm (bsNone, no taskbar — `ShowInTaskBar:=stNever`), position below combo via `ControlToScreen`, width=combo width, height=min(8, Items.Count)*scaled ItemHeight; hosts TTyListBox (Items.Assign, ItemIndex synced); ListBox OnChange → combo.SelectItem + CloseUp (select-on-click; confirm via the ListBox click path); popup OnDeactivate → CloseUp; ESC in popup/combo → CloseUp. Popup freed in combo Destroy.
- [ ] Manual smoke note for the executor: build `examples/combobox` and run it briefly is OPTIONAL (GUI); the headless tests are the gate.
- [ ] Update the 3 docs (combobox.md 行为段、KNOWN_GAPS 删该条、example 注释) in the same commit.
- [ ] Suite green. Commit: `feat(tycontrols): real ComboBox dropdown popup (replaces click-cycle)`

## P5 · CONTROLS-C

### Task C2.1: TTyProgressBar (+ TyProgressFillRect)

**Files:** Create `source/tyControls.ProgressBar.pas`; Test (new) `tests/test.progressbar.pas`.

- [ ] Failing tests: pure `TyProgressFillRect` table — track (0,0,200,20): Min=0 Max=100 Pos=0 → width 0; Pos=50 → right=100; Pos=100 → right=200; Max=Min → width 0; Pos clamps. Control: typeKey; Position setter clamps + Invalidate.
- [ ] Implement; RenderTo: DrawFrame (track) + FillBackground of `ResolveStyle('TyProgressFill','',[]).Background` over the fill rect (radius from fill style). Pixel test: fill style `TyProgressFill { background:#3B82F6; }`, Pos=50 → pixel at 25% width is blue, at 75% is not.
- [ ] Suite green. Commit: `feat(tycontrols): add TTyProgressBar with pure fill-rect geometry`

### Task C2.2: TTyToggleSwitch

**Files:** Create `source/tyControls.ToggleSwitch.pas`; Test (new) `tests/test.toggleswitch.pas`.

- [ ] Failing tests: typeKey; `Toggle` flips Checked + fires OnChange once; Click calls Toggle; Space (KeyDown VK_SPACE) toggles; `CurrentStates` includes tysActive when Checked (override CurrentStates: inherited + [tysActive] if FChecked) — assert via a probe subclass.
- [ ] Implement; RenderTo: DrawFrame on a pill rect (radius=height/2 — pass S.BorderRadius if set else half height), knob = filled circle (painter FillBackground on square rect with full radius) using `S.TextColor`, knob at left when off / right when on. Pixel test with `TyToggleSwitch { background:#444444; color:#FFFFFF; } TyToggleSwitch:active { background:#3B82F6; }`: knob-side pixel white; ON track pixel blue.
- [ ] Suite green. Commit: `feat(tycontrols): add TTyToggleSwitch (ON maps to :active)`

### Task C2.3: TTyTrackBar (+ TyTrackThumb)

**Files:** Create `source/tyControls.TrackBar.pas`; Test (new) `tests/test.trackbar.pas`.

- [ ] Failing tests: typeKey; `ThumbRect` math (track width 200, thumb logical 12@96: Pos=0 → Left=0; Pos=100 → Right=200; Pos=50 centered); `DragTo` maps x→Position with clamping (0→Min, beyond→Max), OnChange only on change; VK_LEFT/RIGHT step ±1 clamped.
- [ ] Implement (mirror ScrollBar's drag pattern; simpler: thumb fixed logical 12 wide, travel = width - thumbW). RenderTo: DrawFrame (groove drawn as the control frame), thumb via `ResolveStyle('TyTrackThumb','', thumb states)` FillBackground; hover/drag states on thumb.
- [ ] Suite green. Commit: `feat(tycontrols): add TTyTrackBar with draggable themed thumb`

### Task C2.4: TTyGroupBox

**Files:** Create `source/tyControls.GroupBox.pas`; Test (new) `tests/test.groupbox.pas`.

- [ ] Failing tests: typeKey; hosts a child (ControlCount=1 after parenting a TButton); Caption settable.
- [ ] Implement: container (mirror Panel); RenderTo draws frame inset from the caption line (border starts at half caption height), caption text drawn top-left over a gap in the border — simplest correct visual: draw frame on Rect(0, capH div 2, W, H), then caption text at x=Scale(12) on a background-colored band behind it. Pixel smoke: caption pixels present.
- [ ] Suite green. Commit: `feat(tycontrols): add TTyGroupBox container with embedded caption`

## P6 · NATIVE (macOS-verifiable)

### Task NAT.1: macOS native shadow for borderless chrome

**Files:** Modify `source/tyControls.Form.pas` (InstallChrome); no headless test possible — code review + manual gate.

- [ ] Implement: `{$IFDEF LCLCOCOA}` after `BorderStyle:=bsNone` and once the form has a handle: `NSWindow(...).setHasShadow(True)` (use CocoaInt/CocoaAll: `TCocoaWindow`/`NSWindow` from the form Handle — `NSView(Form.Handle).window` pattern; consult LCL cocoa interface for the canonical cast) + `invalidateShadow` on resize end. Wrap so non-cocoa builds compile unchanged (pure no-op).
- [ ] Verify: `lazbuild examples/formchrome/formchrome_example.lpi` still builds; full suite still green (chrome unit compiles into the runner). Manual visual check is the user's; note it in the report.
- [ ] Update `docs/KNOWN_GAPS.md`: macOS shadow item resolved; Windows DWM shadow remains (no cross-compile verification environment).
- [ ] Commit: `feat(tycontrols): native NSWindow shadow for borderless chrome on macOS`

### Task NAT.2: Cross-monitor DPI rescale

**Files:** Modify `source/tyControls.Form.pas`; Test `tests/test.form.pas`.

- [ ] Failing test: pure `TyRescaleChromeMetric(32, 96, 144) = 48`, `(48,144,96)=32`, identity at equal PPI, rounds half-up.
- [ ] Implement pure function; wire: FormChrome stores `FInstalledPPI`; hook the host form's `OnChangeBounds` (preserving any prior handler, same pattern as the mouse handlers) → if `Monitor.PixelsPerInch <> FInstalledPPI`, rescale `TitleHeight` (and the title bar's button width) via the function, update FInstalledPPI, Invalidate. Single-monitor runtime behavior can't be exercised here — the pure function + wiring-presence test (handler chained and restored on uninstall) is the gate.
- [ ] Update KNOWN_GAPS DPI item: metrics now rescale on monitor change (verified by unit math; multi-monitor manual validation pending).
- [ ] Suite green. Commit: `feat(tycontrols): rescale chrome metrics on cross-monitor DPI change`

### Task NAT.3: Traffic-light style support

**Files:** Modify `source/tyControls.Form.pas` (TTyCaptionButton); Test `tests/test.form.pas`; Create `docs/recipes-traffic-lights.md`.

- [ ] Failing test: `ShowGlyphOnHoverOnly=True` + not hovered → RenderTo produces NO glyph strokes over the button face (pixel equality with a glyph-less render); hovered probe (set FHover via protected access subclass) → glyph appears.
- [ ] Implement the property gate in RenderTo.
- [ ] Write `docs/recipes-traffic-lights.md` (中文): complete `.tycss` snippet — `TyCaptionButton.close/{.min}/{.max}` circular (border-radius half of button), red/yellow/green backgrounds, hover darken, plus `Chrome.TitleBar.CloseButton.ShowGlyphOnHoverOnly:=True` code line; note it approximates macOS, not native.
- [ ] Suite green. Commit: `feat(tycontrols): ShowGlyphOnHoverOnly caption buttons + traffic-light recipe`

## P7 · INTEGRATION

### Task INT.1: Themes + theme-load tests for all new typeKeys

**Files:** Modify `themes/light.tycss`, `themes/dark.tycss`, `themes/showcase.tycss`, `tests/test.themes.pas`.

- [ ] Failing test first: extend `test.themes.pas` — for each shipped theme, resolve `TyListBox` base (tpBackground present), `TyListItem:active` (tpBackground), `TyProgressFill` (tpBackground), `TyToggleSwitch:active` (tpBackground), `TyTrackThumb` (tpBackground), `TyGroupBox` (tpBorderColor present).
- [ ] Add rules to all 3 themes (each theme's palette-consistent): TyListBox (surface bg+border+radius), TyListItem (transparent base / hover lighten / active accent), TyProgressBar (track) + TyProgressFill (accent; showcase may use a 90deg gradient), TyToggleSwitch (gray track, :active accent, color=knob white), TyTrackBar (groove) + TyTrackThumb (accent, :hover lighten), TyGroupBox (border+radius, transparent bg).
- [ ] Suite green. Commit: `feat(themes): style all v1.1 typeKeys in light/dark/showcase`

### Task INT.2: Package, design-time registration, demo gallery

**Files:** Modify `tycontrols.lpk`, `designtime/tyControls.Design.pas`, `examples/demo/mainform.pas`.

- [ ] `tycontrols.lpk`: add the 5 new units (ListBox/ProgressBar/ToggleSwitch/TrackBar/GroupBox), bump Files Count accordingly. `lazbuild tycontrols.lpk` green.
- [ ] Design unit: register the 5 new classes on the 'TyControls' palette page. `lazbuild tycontrols_dt.lpk` green.
- [ ] Demo gallery: add one instance of each new control (and the ComboBox now drops down for real). `lazbuild examples/demo/demo.lpi` green.
- [ ] Suite green. Commit: `build(tycontrols): register v1.1 controls in package, IDE palette and demo`

### Task INT.3: Example projects for new controls

**Files:** Create `examples/listbox/`, `examples/progressbar/`, `examples/toggleswitch/`, `examples/trackbar/`, `examples/groupbox/` (3 files each, template `examples/button/`).

- [ ] listbox: items + selection label + enough items to show the embedded scrollbar. progressbar: a TTyTrackBar driving a TTyProgressBar (nice cross-demo). toggleswitch: two switches + state label. trackbar: value label + OnChange. groupbox: two groups hosting radios (cross-demo of grouping).
- [ ] Each builds: `lazbuild examples/<n>/<n>_example.lpi`. build-matrix picks them up automatically (glob).
- [ ] Commit: `feat(examples): add v1.1 control example projects`

### Task INT.4: Documentation sync

**Files:** Create `docs/controls/{listbox,progressbar,toggleswitch,trackbar,groupbox}.md`; Modify `docs/controls/{combobox,edit,scrollbar,checkbox,radiobutton}.md`, `docs/tycss-reference.md`, `docs/getting-started.md`, `README.md`, `docs/KNOWN_GAPS.md`.

- [ ] 5 new control docs (中文, follow the existing 12-doc structure; verify每个 published 属性 against source).
- [ ] Updates: combobox.md (真下拉行为), edit.md (光标/选区/剪贴板 API), scrollbar.md (thumb=color), checkbox/radiobutton.md (DrawFrame/opacity 生效), tycss-reference.md (新 typeKey 表 + TyListItem/TyProgressFill/TyTrackThumb 状态语义 + ScrollBar color 限制段删除), getting-started/README 示例表 + 控件速查加新条目, KNOWN_GAPS 全面修订 (删 ComboBox 弹层条、macOS 阴影条;保留 Windows 项并注明原因).
- [ ] Commit: `docs: sync documentation for v1.1 (new controls, edit, dropdown, native)`

### Task INT.5: Final verification

- [ ] `bash scripts/build-matrix.sh` → matrix OK (2 packages + all examples + runner).
- [ ] Full suite green; run once with heaptrc (`-gh` via temporary CustomOptions in tytests.lpi, then revert) → 0 unfreed blocks.
- [ ] `git status` clean. Commit anything stray. Report totals (test count, new controls, docs).

---

## Self-review checklist (done at authoring)

- Spec §2 controls ↔ LIST/DROP/C2 tasks; §3 polish ↔ POLISH/EDIT; §4 native ↔ NAT; §5 acceptance ↔ INT. TabControl/Windows correctly absent.
- Names cross-checked against the pinned contract; themes/tests/docs reference the same 8 new typeKeys.
