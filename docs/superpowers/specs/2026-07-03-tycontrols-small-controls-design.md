# Three Small Controls — Design

**Goal:** Complete three folded-in "补完现有" controls in one combined effort: a **tri-state `TTyCheckBox`**, an **editable `TTyComboBox`** (csDropDown + autocomplete), and a new **`TTyTabSet`** (pure tab strip).

**Architecture:** All three build on existing code — no large new classes. ① and ② extend the current `TTyCheckBox` / `TTyComboBox` in place (backward-compatible, opt-in). ③ is a thin new control on the already-built `TTyCustomTabStrip` header engine (SP1). One spec → one plan → TDD, in three task-groups.

**Tech Stack:** Lazarus/FPC, `TTyCustomControl`/`TTyGraphicControl` + `TTyPainter` render pipeline, LCL `StdCtrls.TCheckBoxState`, the SP1 `tyControls.TabStrip` engine, theme `.tycss` typeKeys, headless RenderTo pixel tests + fpcunit logic tests.

**Program context:** These are the [[new-controls-program]] folded-in small items. Phase-2 (①②③ big controls) + Dialogs are all merged; v2.1.0 released. This lands after the dialog post-ship fixes ([[dialog-postship-fixes]]).

---

## Current state (verified)
- **`TTyCheckBox`** (`source/tyControls.CheckBox.pas`): a `TTyCustomControl` with only `FChecked: Boolean` + published `Checked` + `OnChange`. `Click` toggles. When checked it enters `tysActive` (accent box + white glyph via `tgCheck`); the caption is resolved `tysActive`-free so only the box gets the accent. RenderTo draws the box + `tgCheck` glyph when checked.
- **`TTyComboBox`** (`source/tyControls.ComboBox.pas`): published `Items`/`ItemIndex`/`Text`/`OnChange`. Code comment confirms it is effectively **`csDropDownList`** today — `Text` is read-only (select-only); the props are published for native-API parity. It already owns a dropdown popup mechanism (shared `TTyDropdownPopup`).
- **`TTyCustomTabStrip`** (`tyControls.TabStrip`, SP1): the page-agnostic header engine — layout/hover/scroll/close-×/drag-reorder/cross-fade/keyboard — with abstract `GetTabCount`/`GetTabCaption` and virtual hooks `DoSelectTab`/`DoReorderTabs`/`RemoveTabData`/`GetTabClosableAt`. `FTabIndex`/`SetTabIndex` are **protected** (subclass publishes selection under its own name); `TabIndex` is public on the base. `TTyPageControl` (SP1) is the container subclass; `TTyTabSet` (SP2, this spec) is the pure-strip subclass.

## Design

### ① tri-state `TTyCheckBox` (modify `source/tyControls.CheckBox.pas`)
- **`State: TCheckBoxState`** (from LCL `StdCtrls`: `cbUnchecked`/`cbChecked`/`cbGrayed`) becomes the **primary** stored state (`FState`). Published, `default cbUnchecked`.
- **`AllowGrayed: Boolean`** published, `default False`.
- **`Checked: Boolean`** stays published for backward-compat, as a **derived** view: read = `FState = cbChecked`; write True → `cbChecked`, False → `cbUnchecked`. Existing code/demo/`.lfm` that use `Checked` keep working unchanged.
- **`Click` cycle:** `AllowGrayed = False` → `cbUnchecked ↔ cbChecked`. `AllowGrayed = True` → `cbUnchecked → cbChecked → cbGrayed → cbUnchecked` (LCL semantics). Setting `State := cbGrayed` programmatically works regardless of `AllowGrayed` (matches LCL: AllowGrayed only gates the user Click cycle).
- **`OnChange`** fires whenever `FState` actually changes (via a `SetState` guard); `SetChecked` routes through `SetState`.
- **Visual (grayed):** add a Painter glyph **`tgCheckIndeterminate`** (a centered filled square inset in the box, the Windows indeterminate look). `CurrentStates`: both `cbChecked` and `cbGrayed` enter `tysActive` (accent box); RenderTo picks the glyph by state — `cbChecked → tgCheck`, `cbGrayed → tgCheckIndeterminate`, `cbUnchecked → none`. Caption stays `tysActive`-free (unchanged).

### ② editable `TTyComboBox` + autocomplete (modify `source/tyControls.ComboBox.pas`)
- **`Style: TTyComboBoxStyle = (csDropDownList, csDropDown)`** published, `default csDropDownList` (current behavior unchanged — the guarded default branch).
- **`csDropDown`:** the text area hosts an **embedded `TTyEdit` child** (created in the constructor, hidden until `Style = csDropDown`; reuses TTyEdit's editing/caret/IME/undo logic — the same "embed a themed TTyEdit" pattern as the TreeView inline editor). `Text` becomes read-write; typing edits the `TTyEdit`, whose `OnChange` updates the combo's `Text`.
- **autocomplete (prefix filter):** on the embedded edit's `OnChange`, filter `Items` by **case-insensitive prefix** of the current text → auto-open the dropdown showing only matches (empty text → show all). Selecting an item / Enter fills `Text` and closes; Esc closes without changing `Text`. The filter is a pure function `TyFilterItemsByPrefix(AItems, APrefix): TStringList/indices` (headless-testable).
- **`csDropDownList` branch:** entirely unchanged (no embedded edit; select-only; existing render + popup).
- The embedded edit sits in the combo's text rect (minus the dropdown-button zone); it's themed via the combo's controller (child gets the controller like other embedded controls). `ReadOnly`/keyboard: down-arrow opens/moves in the dropdown; typing filters.

### ③ `TTyTabSet` (new unit `source/tyControls.TabSet.pas`)
- **`TTyTabSet = class(TTyCustomTabStrip)`** — reuses the SP1 header engine (layout/hover/scroll/close-×/drag-reorder/keyboard all inherited).
- **`Tabs: TStrings`** (backing `TStringList`; assigning/editing → invalidate + re-layout via the base). **`TabIndex: Integer`** published (surfaces the base's protected selection). **`OnChange: TNotifyEvent`** (fires on selection change).
- Implement the base abstracts/hooks: `GetTabCount = Tabs.Count`, `GetTabCaption(i) = Tabs[i]`, `DoSelectTab(i)` → set `FTabIndex` + fire `OnChange`, `DoReorderTabs(from,to)` → move the `Tabs` entry, `RemoveTabData(i)` → delete the `Tabs` entry (for close-×).
- Expose the engine's optional abilities: **`ShowCloseButtons: Boolean`** + **`OnCloseTab: TTyTabCloseEvent`** (delete the tab / let the app veto), and drag-reorder (on by default — engine already does it; reorders `Tabs`).
- **Streaming/design-time:** `RegisterClass(TTyTabSet)` in `initialization` (LFM load); register on the palette; a **new palette icon** (a tab-strip glyph) added to the 4-way lockstep (see cross-cutting).
- Edge cases: empty `Tabs` → `TabIndex = -1`, nothing painted; deleting the selected tab clamps `TabIndex`.

### Cross-cutting (all three)
- **Theme:** ① reuses `TyCheckBox` (grayed distinguished purely by the new glyph — no new typeKey). ② reuses `TyComboBox` for the frame + `TyEdit` for the embedded editor. ③ reuses the SP1 tab-strip typeKeys (`TyTab`/`TyTabStrip` or whatever `TTyPageControl` uses — verify and reuse). Only add a new token if a control genuinely can't be expressed with existing ones; if added, **byte-sync all six themes** (light/dark/showcase `.tycss` + `DefaultTheme.pas` via the two generators) + re-bootstrap goldens.
- **Palette icons:** only **`TTyTabSet`** is a new component needing a glyph. Add it to ALL FOUR lockstep lists (`tools/genicons/genicons.lpr` `Glyphs[]` + a `GTyTabSet` draw proc; `scripts/gen-icons.ps1` `$classes`; `tests/test.paletteicons.pas` `CClasses`; the `RegisterComponents` call) or the drift-guard fails; regenerate `.lrs`. `TTyCheckBox`/`TTyComboBox` already have icons (unchanged).
- **Testing (headless):** ① State cycle (both AllowGrayed modes) + Checked↔State mapping + RenderTo glyph per state (3 states) pixel-check. ② `TyFilterItemsByPrefix` pure round-trip + construct-only editable combo (embedded edit present when `Style=csDropDown`, absent otherwise) + Text read/write; the live dropdown-filter interaction is GUI (real-machine). ③ `GetTabCount`/`GetTabCaption` from `Tabs`, `DoSelectTab`→`TabIndex`+`OnChange`, `DoReorderTabs`→`Tabs` order, close→delete; a RenderTo strip pixel-check.
- **demo:** add the three to `examples/demo/mainform.lfm` (designer surface — the user places them; if we add, edit the `.lfm` not code, per [[demo-edits-lfm-not-code]]).
- **i18n:** none of the three carry runtime text of their own (captions are user-set) → no new resourcestrings.

## Error handling
- **CheckBox:** `AllowGrayed` only gates the Click cycle; programmatic `State := cbGrayed` always allowed (LCL parity). `Checked`/`State` stay consistent through the shared `SetState`.
- **ComboBox:** `csDropDown` with an empty filter shows all items; a typed value with no match leaves the dropdown empty but `Text` keeps what the user typed (free input). Switching `Style` at runtime shows/hides the embedded edit. `csDropDownList` path untouched → zero regression risk for existing users.
- **TabSet:** empty `Tabs` → `TabIndex=-1`; reorder/close keep `TabIndex` valid; assigning `Tabs` resets selection sanely.

## Testing
New/extended headless units: `tests/test.checkbox.pas` (or extend existing) for tri-state; `tests/test.combobox.pas` for the prefix filter + editable construct; `tests/test.tabset.pas` for the strip. Register in `tests/tytests.lpr`. Keep **failures 0 / errors 11**; baseline **1622 run** (grows by the new tests). RenderTo pixel tests for the grayed glyph + tab strip; PPI=96 for logic, add a HiDPI check only if a control stores logical + paints scaled (checkbox/combobox already handle their own DPI; tabset inherits the SP1 engine's).

## Non-goals
- ComboBox **fuzzy/substring** match or inline auto-complete-selection (prefix only, per user).
- TabSet interactions beyond what the SP1 engine already provides (no new gestures).
- No changes to `TTyRadioButton`, `TTyPageControl`, or the popup engine.
- No new theme token unless a control can't be expressed with existing ones.

## Files
- **Modify** `source/tyControls.CheckBox.pas` — tri-state (`State`/`AllowGrayed`/`Checked`-derived/cycle/glyph).
- **Modify** `source/tyControls.ComboBox.pas` — `Style` + embedded `TTyEdit` + prefix filter.
- **Modify** `source/tyControls.Painter.pas` — `tgCheckIndeterminate` glyph (+ `TTyGlyphKind` member).
- **Create** `source/tyControls.TabSet.pas` — `TTyTabSet`. Add to `tycontrols.lpk`.
- **Modify** `designtime/tyControls.Design.pas` — register `TTyTabSet` (+ uses).
- **Modify** `tools/genicons/genicons.lpr`, `scripts/gen-icons.ps1`, `tests/test.paletteicons.pas` — TabSet icon 4-way lockstep; regenerate `designtime/tycontrols_icons.lrs` + `designtime/icons/TTyTabSet*.png`.
- **Modify** themes only if a new token is required (byte-sync six + goldens).
- **Create** `tests/test.tabset.pas`, extend `tests/test.checkbox.pas`/`test.combobox.pas`; register in `tests/tytests.lpr`.
- **Modify** `examples/demo/mainform.lfm` (+ handlers in `.pas`) to showcase the three.
