# Three Small Controls — Design

**Goal:** Complete three folded-in "补完现有" controls in one combined effort: a **tri-state `TTyCheckBox`**, an **editable `TTyComboBox`** (csDropDown + autocomplete), and a new **`TTyTabSet`** (pure tab strip).

**Architecture:** All three build on existing code — no large new classes. ① and ② extend the current `TTyCheckBox` / `TTyComboBox` in place (backward-compatible, opt-in). ③ is a thin new control on the already-built `TTyCustomTabStrip` header engine (SP1). One spec → one plan → TDD, in three task-groups.

**Tech Stack:** Lazarus/FPC, `TTyCustomControl`/`TTyGraphicControl` + `TTyPainter` render pipeline, LCL `StdCtrls.TCheckBoxState`, the SP1 `tyControls.TabStrip` engine, theme `.tycss` typeKeys, headless RenderTo pixel tests + fpcunit logic tests.

**Program context:** These are the [[new-controls-program]] folded-in small items. Phase-2 + Dialogs merged; v2.1.0 released. Lands after [[dialog-postship-fixes]]. **This spec was adversarially verified against the real code (workflow); the fixes below are folded in.**

---

## Current state (verified against source)
- **`TTyCheckBox`** (`source/tyControls.CheckBox.pas`): a `TTyCustomControl` with only `FChecked: Boolean` (`:10`) + published `Checked` (`:25`) + `OnChange`. `Click` toggles. `CurrentStates` (`:103-112`) adds `tysActive` when `FChecked and Enabled`; caption is resolved `tysActive`-free. RenderTo (`:185-186`) draws `tgCheck` when `FChecked`.
- **`TTyComboBox`** (`source/tyControls.ComboBox.pas`): published `Items`/`ItemIndex`/`Text`/`OnChange`; effectively **`csDropDownList`** today (`Text` select-only). `DropDown()` assigns the FULL `FItems` to the popup (`:364`), guards on `FItems.Count=0` (`:336`), sizes off `FItems.Count` (`:293`). `SelectItem` fires `FOnChange` (`:321-322`); `ResyncIndexFromText` (`:254-271`) **blanks `FText`** when the text isn't in `FItems` (`:269`), called from `ItemsChanged` (`:273-279`). `Click` (`:396-409`) toggles the popup on a click anywhere. Existing detach idiom for programmatic list writes: `FPopupList.OnChange := nil; …; reassign` (`:363-366`). Field-button width = `TyFieldButtonWidth` (`tyControls.Types.pas:94`).
- **`TTyCustomTabStrip`** (`tyControls.TabStrip`, SP1): the header engine. **Abstract to implement:** `GetTabCount`/`GetTabCaption` — AND `GetStyleTypeKey` (inherited `abstract` from `TTyCustomControl`, `tyControls.Base.pas:128`, NOT overridden in TabStrip → a subclass MUST override it or stay abstract; `RenderTo` calls `CurrentStyle`→`GetStyleTypeKey` at `:702`). **Virtual hooks:** `DoSelectTab`/`DoReorderTabs`/`RemoveTabData`/`GetTabClosableAt`. **Already published on the base (inherited free):** `TabsClosable: Boolean default False` (`:179`), `OnTabClose: TTyTabCloseEvent` (`:180`, fired from `DoCloseClick :601-611`), `OnChange`/`OnChanging`/`OnReorder` (`:181-183`, `OnChange` fired by `SetTabIndex :670-671`). `TabIndex` is **public** (`:176`), not published. `FTabIndex`/`SetTabIndex` protected. Tab chrome typeKeys are HARD-CODED in `RenderTo`: `'TyTab'`/`'TyTabControl'`/`'TyTabClose'` (`:381/744/790`) — all defined in `themes/*.tycss` + `BuiltinThemeData.pas` + `DefaultTheme.pas`. `TTyPageControl.GetStyleTypeKey` returns `'TyPageControl'` (`tyControls.PageControl.pas:48-51`) which is **NOT** in any theme (resolves to EmptyStyleSet) — do NOT copy it. `TTyPageControl.RemoveTabData`→`UnregisterPage` (`:156-186`) does the full `FTabIndex` clamp + `OnChange` itself; the base's `DoCloseClick` delegates ALL selection reconciliation to the subclass.

## Design

### ① tri-state `TTyCheckBox` (modify `source/tyControls.CheckBox.pas`)
- **Replace `FChecked` with `FState: TCheckBoxState`** (LCL `StdCtrls`: `cbUnchecked`/`cbChecked`/`cbGrayed`). Do NOT keep `FChecked` as a separate field (would desync). Add `SetState(AValue)` (the sole mutator: guard-if-equal, `Invalidate`, fire `OnChange`).
- **`State: TCheckBoxState`** published, `default cbUnchecked`.
- **`AllowGrayed: Boolean`** published, `default False`.
- **`Checked: Boolean`** stays published (backward-compat, and the `.lfm` streaming both `Checked=True` and `State=cbChecked` is benign — LCL does the same): read = `FState = cbChecked`; `SetChecked` **delegates to `SetState`** (True→cbChecked, False→cbUnchecked). Existing code/demo using `Checked` keeps working.
- **`Click` cycle:** `AllowGrayed=False` → `cbUnchecked ↔ cbChecked`. `AllowGrayed=True` → `cbUnchecked → cbChecked → cbGrayed → cbUnchecked`. Programmatic `State := cbGrayed` is allowed regardless of `AllowGrayed` (LCL parity — AllowGrayed only gates the user Click cycle).
- **`CurrentStates`:** include `tysActive` when **`(FState in [cbChecked, cbGrayed]) and Enabled`** (NOT the derived `Checked`, or grayed loses its accent box). Caption stays `tysActive`-free.
- **RenderTo:** replace `if FChecked then DrawGlyph(...tgCheck...)` with `case FState of cbChecked: DrawGlyph(...tgCheck...); cbGrayed: DrawGlyph(...tgCheckIndeterminate...); cbUnchecked: (nothing) end`.
- **Painter:** add `tgCheckIndeterminate` to `TTyGlyphKind` (`source/tyControls.Painter.pas:14-15`) **AND its `DrawGlyph` case in the SAME edit** (the `case` at `:431-485` has NO `else`; a member with no case draws nothing → the exhaustive smoke test `TestDrawGlyphAllKinds` (`tests/test.painter.pas:185,194`) would regress). Glyph = a centered filled square inset in the box (Windows indeterminate look), e.g. `FillRectAntialias` on an inset rect.

### ② editable `TTyComboBox` + autocomplete (modify `source/tyControls.ComboBox.pas`)
- **`Style: TTyComboBoxStyle = (csDropDownList, csDropDown)`** published, `default csDropDownList` (guarded default branch — the `csDropDownList` render/click/popup paths stay byte-for-byte unchanged; zero regression for existing users).
- **`csDropDown`:** an embedded **`TTyEdit` child** (`FEditor`, created in the constructor, visible only when `Style=csDropDown`), **sized to the text rect MINUS the `TyFieldButtonWidth` chevron zone** (so the chevron stays on the combo surface and still routes to `TTyComboBox.Click`). Reuses TTyEdit editing/caret/IME/undo; themed via the parent controller (child gets the controller like other embedded controls). `Text` becomes read-write, mirrored from `FEditor.Text`.
- **autocomplete (prefix filter):** a pure `TyFilterItemsByPrefix(AItems, APrefix): TStringList` (case-insensitive prefix) feeds a new **`FVisibleItems: TStringList`**. On the editor's `OnChange`: rebuild `FVisibleItems`, and drive the popup's `Items.Assign` + count/height off **`FVisibleItems`, not `FItems`** (the `csDropDownList` path keeps assigning `FItems`). Empty text → all items. **Empty filtered result → explicit `CloseUp`** (do NOT rely on the `FItems.Count=0` guard, which keys off the unfiltered list). Selecting a row / Enter fills `Text`; Esc closes without changing `Text`.
- **Re-entrancy guard (REQUIRED):** the editor fires `OnChange` per keystroke, and writing back into `FEditor.Text` (autocomplete commit) re-fires it → a filter/open loop, plus double-firing the combo's own `OnChange`. When programmatically setting `FEditor.Text`, **detach the editor's `OnChange` first, then reassign** (mirror the existing `FPopupList.OnChange := nil; …; reassign` idiom at `:363-366`). The combo's `OnChange` fires once per committed value, not per keystroke.
- **Open triggers (csDropDown, document explicitly):** typing filters+opens; the **chevron-zone click** toggles; `VK_DOWN` opens. A click in the text area does NOT toggle (the `FEditor` child consumes it via `TTyEdit.MouseDown`→`SetFocus`, no bubble) — this is correct `csDropDown` behavior.
- **`ResyncIndexFromText`:** in the `csDropDown` path, decouple `FText` from the list — set `FItemIndex := Items.IndexOf(FText)` (may be `-1`) but **do NOT blank `FText`** on no-match. Gate the existing `FText := ''` clear (`:269`) behind `Style = csDropDownList`, so an `Items` mutation during free-input editing can't wipe the user's typing.

### ③ `TTyTabSet` (new unit `source/tyControls.TabSet.pas`)
- **`TTyTabSet = class(TTyCustomTabStrip)`** — reuses the SP1 header engine (layout/hover/scroll/close-×/drag-reorder/keyboard inherited).
- **`Tabs: TStrings`** (backing `TStringList`; assign/edit → invalidate + re-layout). **`published property TabIndex: Integer read FTabIndex write SetTabIndex default -1;`** — re-surfaces the base's *public* `TabIndex` for streaming (the one genuine new declaration).
- **Inherited free (do NOT redeclare):** `OnChange`/`OnChanging`/`OnReorder` (already published + fired), `TabsClosable: Boolean` (the show-close-buttons switch), `OnTabClose: TTyTabCloseEvent` (the close event). If a friendlier name is wanted, `ShowCloseButtons` may be a thin alias forwarding to `TabsClosable` — but no second close event.
- **Override the abstracts/hooks:**
  - `GetStyleTypeKey: string` → **`'TyTabControl'`** (REQUIRED — else the class is abstract and `EAbstractError`s on instantiation; `'TyTabControl'` is a real themed frame key).
  - `GetTabCount` = `Tabs.Count`; `GetTabCaption(i)` = `Tabs[i]`.
  - `DoSelectTab(i)` → set `FTabIndex` + fire `OnChange` (base's `SetTabIndex` already does this if used; ensure the selection path routes through it).
  - `DoReorderTabs(from,to)` → move the `Tabs` entry.
  - `RemoveTabData(i)` → **owns the full reconciliation** (base `DoCloseClick` only calls `RemoveTabData`, nothing else): `Tabs.Delete(i)` + clamp `FTabIndex` (decrement if `i < FTabIndex`; clamp to `High(Tabs)` if the removed index was last; `-1` when empty) + `Invalidate` + fire `OnChange` if the effective selection moved — mirror `TTyPageControl.UnregisterPage` (`:156-186`).
- **Streaming/design-time:** `RegisterClass(TTyTabSet)` in `initialization` **before `end.`** (dead-code-after-`end.` gotcha); register on the palette; add a new palette icon (below).

### Cross-cutting (all three)
- **Theme:** ① reuses `TyCheckBox` (grayed distinguished by the new glyph — no new typeKey). ② reuses `TyComboBox` (frame) + `TyEdit` (embedded editor). ③ reuses the real tab typeKeys **`TyTab` / `TyTabControl` / `TyTabClose`** (all already in `themes/*.tycss` + `BuiltinThemeData.pas` + `DefaultTheme.pas`; `GetStyleTypeKey='TyTabControl'`). **No new token, no theme/golden change needed.**
- **Palette icon (only `TTyTabSet` is new):** add `'TTyTabSet'` to all FOUR lockstep lists — `tools/genicons/genicons.lpr` `Glyphs[]` (+ a `GTyTabSet` draw proc), `scripts/gen-icons.ps1` `$classes`, `tests/test.paletteicons.pas` `CClasses`, and `RegisterComponents('TyControls', [...])` in `designtime/tyControls.Design.pas:684-692` (the MAIN group, not Dialogs). **Bump the two fixed-array bounds:** `genicons.lpr:278` `array[0..39]`→`array[0..40]` and `test.paletteicons.pas:18` `array[0..39]`→`array[0..40]` (compile errors if missed; the drift-guard checks membership, not the counts). Then regenerate `designtime/tycontrols_icons.lrs` + `designtime/icons/TTyTabSet*.png` via `pwsh scripts/gen-icons.ps1`.
- **Testing (headless):** ① State cycle (both AllowGrayed modes) + Checked↔State mapping + RenderTo glyph per state (3 states, incl. `tgCheckIndeterminate` renders pixels). ② `TyFilterItemsByPrefix` pure round-trip; construct-only editable combo (FEditor present iff `Style=csDropDown`, sized minus the chevron zone); `Text` free-input survives an `Items` change; ItemIndex=-1 on no-match. Live filter/open/re-entrancy is GUI (real-machine). ③ `GetTabCount`/`GetTabCaption` from `Tabs`; `DoSelectTab`→`TabIndex`+`OnChange`; `DoReorderTabs`→`Tabs` order; `RemoveTabData`→`Tabs.Delete` + `FTabIndex` clamp + OnChange; a RenderTo strip pixel-check; `GetStyleTypeKey='TyTabControl'`.
- **demo:** add the three to `examples/demo/mainform.lfm` (designer surface — edit the `.lfm`, not code, per [[demo-edits-lfm-not-code]]).
- **i18n:** none carry runtime text of their own → no new resourcestrings.

## Error handling
- **CheckBox:** `AllowGrayed` gates only the Click cycle; programmatic `State:=cbGrayed` always allowed. `Checked`/`State` consistent via the shared `SetState`.
- **ComboBox:** `csDropDown` empty filter → all items; no-match → dropdown closes (explicit `CloseUp`) but `Text` keeps the typed value + `ItemIndex=-1`; switching `Style` shows/hides `FEditor`; re-entrancy guarded. `csDropDownList` path untouched.
- **TabSet:** empty `Tabs` → `TabIndex=-1`, nothing painted; reorder/close keep `TabIndex` valid (reconciled in `RemoveTabData`); assigning `Tabs` resets selection sanely.

## Non-goals
- ComboBox fuzzy/substring match or inline auto-complete-selection (prefix only).
- TabSet interactions beyond the SP1 engine; no new close event or duplicate switches.
- No changes to `TTyRadioButton`, `TTyPageControl`, or the popup engine.
- No new theme token.

## Files
- **Modify** `source/tyControls.CheckBox.pas` — `FState`-based tri-state (State/AllowGrayed/Checked-derived/cycle; CurrentStates + RenderTo on FState).
- **Modify** `source/tyControls.Painter.pas` — `tgCheckIndeterminate` enum member + DrawGlyph case (same edit).
- **Modify** `source/tyControls.ComboBox.pas` — `Style` + embedded `TTyEdit` + `FVisibleItems`/`TyFilterItemsByPrefix` + re-entrancy guard + `ResyncIndexFromText` free-input gate.
- **Create** `source/tyControls.TabSet.pas` — `TTyTabSet` (incl. `GetStyleTypeKey='TyTabControl'`, `RemoveTabData` reconcile). Add to `tycontrols.lpk`.
- **Modify** `designtime/tyControls.Design.pas` — register `TTyTabSet` on `'TyControls'` (+ uses).
- **Modify** `tools/genicons/genicons.lpr` (`GTyTabSet` + `Glyphs[]` + `array[0..40]`), `scripts/gen-icons.ps1` (`$classes`), `tests/test.paletteicons.pas` (`CClasses` + `array[0..40]`); regenerate `designtime/tycontrols_icons.lrs` + `designtime/icons/TTyTabSet*.png`.
- **Create** `tests/test.tabset.pas`; extend `tests/test.checkbox.pas`/`test.combobox.pas` (create if absent); register in `tests/tytests.lpr`.
- **Modify** `examples/demo/mainform.lfm` (+ handlers in `.pas`) to showcase the three.
