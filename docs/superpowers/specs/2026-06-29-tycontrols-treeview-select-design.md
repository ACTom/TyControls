# TTyTreeView ③c — Checkboxes + Tri-State + Multi-Select + Full-Row — Design Spec

**Date:** 2026-06-29
**Sub-project:** ③c of the TreeView 专项 — the final layer. ③a (virtual engine + single-column) and ③b (multi-column + header + sort) are DONE + merged to `main` (`de01437`).
**Branch:** `feat/treeview-select` (off `main`).

## 1. Goal

Add the remaining VirtualTreeView-class interaction layers to `TTyTreeView`: **checkboxes** (check / tri-state / radio) with optional auto-tri-state propagation, **multi-selection** (Ctrl/Shift/keyboard), and **full-row select** — plus fix the ③a deferral where `DeleteNode` does not re-sequence sibling `Index`. No new class; everything is **opt-in** so a tree with the new options off behaves byte-for-byte like ③a/③b (single-select, no checkboxes).

## 2. Scope (user-approved 2026-06-29)

**IN:**
- **DeleteNode `Index` re-sequence** (fix the ③a deferral).
- **Multi-select** — `toMultiSelect`; Ctrl+click toggle, Shift+click range, plain click single; keyboard Shift+↑/↓, Ctrl+Space, Ctrl+A; selection iteration + `OnSelectionChanged`.
- **Full-row select** — `toFullRowSelect`; click any column selects the row (highlight already spans the row from ③b).
- **Checkboxes** — `toCheckSupport`; per-node `CheckType` ∈ {`ctNone`, `ctCheckBox`, `ctTriStateCheckBox`, `ctRadioButton`} and `CheckState` ∈ {`csUnchecked`, `csChecked`, `csMixed`}; drawn in the main column; click toggles; `OnChecking`/`OnChecked`.
- **Auto-tri-state tracking** — `toAutoTristateTracking`; checking a tri-state parent checks/unchecks the whole subtree, and a parent shows `csMixed` when its check-children differ. (Radio children are sibling-exclusive and excluded from the rollup — see §3.4.)
- **Theme** — `TyTreeCheckBox` typeKey (box fill/border + check/mix glyph color), byte-synced across the 6 themes.

**DEFERRED (later / never):** `ctButton` check type, OLE drag-drop of selections, inline editing, incremental search, the multi-select "draw selection rectangle" (rubber-band), save/restore selection streams.

## 3. Architecture

### 3.1 Multi-selection

The selection set IS "all nodes whose `States` contains `nsSelected`" (the bit already exists from ③a). New private state:
- `FSelectionCount: Integer` — kept in sync as nodes gain/lose `nsSelected` (so `SelectedCount` is O(1)).
- `FRangeAnchor: PTyTreeNode` — the anchor for Shift-range selection (set on a plain/Ctrl click; the Shift range runs anchor→clicked).
- `FFocusedNode` stays the focus/caret (unchanged).

Options live in a new `TreeOptions`-style set (or individual published Booleans — see §3.6); the relevant flag is `toMultiSelect`.

**Mouse (in `MouseDown`, multi-select branch when `toMultiSelect`):**
- **Plain click** on node N → clear the whole selection, select N, `FRangeAnchor := N`, `FocusedNode := N`.
- **Ctrl+click** N → toggle `nsSelected` on N (add/remove from the set), `FRangeAnchor := N`, `FocusedNode := N` (no clear).
- **Shift+click** N → clear the set, then select every VISIBLE node from `FRangeAnchor` to N inclusive (walk visible order; anchor unchanged), `FocusedNode := N`. (Ctrl+Shift+click extends without clearing.)
- When `toMultiSelect` is off → the ③a/③b single-select path runs unchanged.

**Range selection** uses a visible-order walk (`GetFirstVisibleNoInit`…`GetNextVisibleNoInit`) to find which of {anchor, target} comes first, then selects the inclusive run — NO dependence on sibling `Index` (so it is correct regardless of the Index fix; the Index fix is separate hygiene).

**Keyboard (`KeyDown`, when `toMultiSelect`):**
- `Shift+↓/↑` → extend the selection by moving the caret and selecting the run anchor→caret.
- `Ctrl+Space` → toggle `nsSelected` on the focused node.
- `Ctrl+A` → select all visible (initialized) nodes.
- Plain `↑/↓/Home/End/…` (no modifier) → move focus + single-select (collapse the set to the caret), `FRangeAnchor := caret`.

**API:** `Selected[Node]: Boolean` (getter/setter works for multi), `SelectedCount: Integer`, `GetFirstSelected`/`GetNextSelected(Node)` iterators, `ClearSelection`, `SelectAll`, `SelectRange(AAnchor, ATarget)`, `OnSelectionChanged: TNotifyEvent` (fired once per user gesture, not per node). Single-select `FocusedNode`/`Selected` semantics preserved when `toMultiSelect` off (back-compat: existing `SetSelected` keeps its single-select behavior unless multi-select is engaged — internally route through a shared `InternalAddToSelection`/`InternalRemoveFromSelection` that maintains `FSelectionCount`).

### 3.2 Checkboxes — node fields

`TTyTreeNode` gains two byte fields (fits in existing alignment padding; `TreeNodeSize` recomputed):
```pascal
TTyCheckType  = (ctNone, ctCheckBox, ctTriStateCheckBox, ctRadioButton);
TTyCheckState = (csUnchecked, csChecked, csMixed);
…
CheckType:  TTyCheckType;   // default ctNone
CheckState: TTyCheckState;  // default csUnchecked
```
Defaults: a fresh node is `ctNone`/`csUnchecked`. The app sets `CheckType[node]` (or a tree-wide `DefaultCheckType` applied in `InitNode`, or `OnInitNode` sets it). `toCheckSupport` gates all checkbox painting/hit/behaviour; off → no checkbox column space, ③a/③b layout unchanged.

### 3.3 Checkbox paint + hit (main column)

In the main column's x-accumulation (after the expand button, before the image/caption), when `toCheckSupport` and `node.CheckType <> ctNone`, reserve a checkbox slot (`P.Scale(16)`-ish) and draw:
- `ctCheckBox`/`ctTriStateCheckBox`: a box (`TyTreeCheckBox` fill+border) with a check glyph (`tgCheck`) when `csChecked`, a dash/filled-square when `csMixed`, empty when `csUnchecked`.
- `ctRadioButton`: a circle with a dot (`tgRadioDot`) when `csChecked`.
All colors from the resolved `TyTreeCheckBox` style (box bg/border) + glyph color token — NO hard-coded colors.
`GetNodeAtPoint` gains an `hpCheckBox` part (the checkbox slot) so `MouseDown` can toggle without selecting. The checkbox slot shifts the caption/image start right by the slot width (and `GetNodeAtPoint`/`FRangeX` account for it, mirroring the image-slot reservation pattern).

### 3.4 Check behaviour + tri-state propagation

`MouseDown` on `hpCheckBox` (or `Space` with `toCheckSupport`) → `ToggleCheck(node)`:
- `ctCheckBox`: `csUnchecked` ↔ `csChecked`.
- `ctTriStateCheckBox`: user-click cycles `csUnchecked` → `csChecked` (→ `csUnchecked`); `csMixed` is set only by propagation, not by direct click.
- `ctRadioButton`: set `csChecked`; uncheck all `ctRadioButton` siblings (sibling-exclusive). Radio does not roll up into a parent's tri-state.
Fire `OnChecking(node; var Allowed)` before, `OnChecked(node)` after.

`toAutoTristateTracking` (when on):
- **Down**: checking/unchecking a node with check-children sets every descendant (ctCheckBox/ctTriStateCheckBox) to the same state.
- **Up**: after a change, walk parents; a parent with `ctTriStateCheckBox` becomes `csChecked` if ALL its check-children are checked, `csUnchecked` if all unchecked, else `csMixed`. Radio children are ignored in the rollup.
The down/up propagation is implemented as **pure helpers** (`PropagateCheckDown`, `RecomputeParentCheckState`) tested in isolation against known trees.

### 3.5 DeleteNode `Index` re-sequence (③a deferral fix)

After `DeleteNode` unlinks a node, re-stamp the remaining siblings' `Index` (0..n-1) on the affected parent — O(siblings), NOT O(whole tree). SKIP when `nsClearing` is set (the `Clear` fast-path frees everything without per-node resequencing → avoids O(n²)). Flip the deferred test `TestDeleteMiddleChildUpdatesIndices` to assert the re-sequenced indices.

### 3.6 Options surface

Introduce a published options set to group the toggles (VTV-style), e.g.:
```pascal
TTyTreeOption  = (toMultiSelect, toCheckSupport, toFullRowSelect, toAutoTristateTracking);
TTyTreeOptions = set of TTyTreeOption;
property Options: TTyTreeOptions ...;   // default []  (= ③a/③b behaviour)
```
(Existing ShowButtons/ShowTreeLines/etc. stay as their own published Booleans — do not fold them in, to avoid churning ③a's API.) Changing `Options` invalidates + repaints; turning `toCheckSupport` on/off changes the main-column layout (re-measure `FRangeX` if multi-column).

### 3.7 Full-row select

`toFullRowSelect`: `GetNodeAtPoint` returns the node for a click ANYWHERE in the row (any column / past the text), and the selection highlight spans the full row (already true from ③b). Without it, only a click on the main-column label/cell selects (the ③a behavior). Low-effort: gate the "treat any in-row X as a node hit" in `MouseDown`.

## 4. Theme typeKey (byte-synced across all 6 themes + goldens)

- `TyTreeCheckBox` — the checkbox box: base (`background: var(--input-bg)`, `border-color: var(--border)`, `border-width: var(--input-border-width)`, `radius`), `:checked`/`:selected` (box `background: var(--accent)` so the check sits on accent), check/dot glyph color `var(--on-accent)`/`var(--on-surface)`, `:disabled` muted. (Reuse the existing `TyCheckBox` token values for visual consistency, but a tree-scoped typeKey so the tree controls its own checkbox metrics.)

Byte-sync procedure (identical to ③a D1 / ③b F1): add CSS to every `themes/*.tycss` (green concrete-value), run `gen-defaulttheme.ps1` + `gen-builtinthemes.ps1`, extend `GGRID`, re-bootstrap goldens (additive), add `AssertBg('TyTreeCheckBox', [])` to `TestBuiltinCoversAllTypeKeys`.

## 5. Testing strategy

**Pure functions (the correctness spine):**
- **Tri-state propagation** — `PropagateCheckDown(parentState)` sets all descendants; `RecomputeParentCheckState(children states)` → checked/unchecked/mixed (radio ignored). Table-driven over known child-state combinations.
- **Range selection** — given a visible sequence + anchor + target, the inclusive selected run (order-independent of which is first); radio-exclusivity within siblings.
- **DeleteNode Index** — delete a middle child → remaining siblings re-stamped 0..n-1; Clear does NOT pay O(n²) (no per-node resequence under nsClearing); the ③a height invariant still holds.

**Control-level:**
- Checkbox paint: a checked/mixed/unchecked/radio node draws the right glyph in the main-column slot; the slot shifts the caption right; `toCheckSupport` off → no slot (layout == ③b).
- Hit: a click in the checkbox slot → `hpCheckBox` (toggles, does NOT select); a click on the label → selects.
- Multi-select: Ctrl+click toggles set membership; Shift+click selects the visible range; `SelectedCount`/iterators; Ctrl+A; `OnSelectionChanged` fires once per gesture; `toMultiSelect` off → single-select == ③a/③b (re-run an existing single-select test).
- Check behaviour: toggling a tri-state parent with `toAutoTristateTracking` sets the subtree + rolls the parent to mixed when children differ; radio click unchecks siblings.
- **Back-compat:** every ③a/③b test stays green (Options default []).
- **HiDPI:** the checkbox slot + hit at PPI=144 (reuse the discipline).

## 6. Scope boundaries

| Sub-project | Contents |
|---|---|
| ③a (done) | virtual engine + single-column tree |
| ③b (done) | multi-column + header + sort |
| **③c (this)** | checkboxes (check/tri-state/radio) + auto-tri-state + multi-select (Ctrl/Shift/keyboard) + full-row + DeleteNode Index fix + demo |
| later/never | ctButton, OLE drag-drop, inline edit, incremental search, rubber-band select, selection persistence |

## 7. Key decisions

1. **Extend `TTyTreeView`, no new class**; everything opt-in via a new `Options: TTyTreeOptions` set; default `[]` == ③a/③b.
2. **Selection set = `nsSelected` bits** (+ O(1) `FSelectionCount`), not a separate list — reuses the existing bit, iterates by visible walk; `FRangeAnchor` for Shift.
3. **Check state stored IN the node record** (`CheckType`/`CheckState` bytes) — VTV-faithful, no app-side storage; `toCheckSupport` off → fields inert, zero layout cost.
4. **Range select by visible-order walk**, not sibling `Index` — correct independent of the Index fix; the Index fix is separate hygiene (and flips the deferred ③a test).
5. **Tri-state propagation = pure helpers**, unit-tested in isolation; radio excluded from rollup.
6. **`TyTreeCheckBox` theme typeKey** — checkbox visuals token-driven, no hard-coded colors.
