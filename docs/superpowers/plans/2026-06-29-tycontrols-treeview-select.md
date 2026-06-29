# TTyTreeView ③c — Checkboxes + Tri-State + Multi-Select + Full-Row — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development — fresh subagent per task, spec-review + quality-review between tasks. Steps use `- [ ]`.

**Goal:** Add checkboxes (check/tri-state/radio) with auto-tri-state propagation, multi-selection (Ctrl/Shift/keyboard), full-row select, and the deferred `DeleteNode` `Index` re-sequence to the merged `TTyTreeView` — all opt-in via a new `Options: TTyTreeOptions` set so the default (`[]`) is byte-for-byte ③a/③b.

**Architecture:** Pure helpers (tri-state propagation, range selection, index re-sequence) in `tyControls.TreeView.pas` are unit-tested in isolation; the selection set reuses the existing `nsSelected` bit + an O(1) count + a range anchor; check state lives in two new `TTyTreeNode` byte fields; a `TyTreeCheckBox` theme typeKey drives the box visuals. Spec: `docs/superpowers/specs/2026-06-29-tycontrols-treeview-select-design.md`.

**Baseline:** `main`/this branch builds at **1320 run / 0 fail / 11 pre-existing env errors**. Every task: `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → failures 0; commit ending `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; never push.

**Invariants to keep green every task:** ③a height invariant; all ③a/③b tests (Options default []); theme byte-sync + goldens; events RTTI guard; palette drift-guard; the ③b multi-column + sort behaviour.

---

## Phase A — pure foundations

### Task A1: `DeleteNode` Index re-sequence (fix the ③a deferral)

**Files:** `source/tyControls.TreeView.pas` (`DeleteNode`); Test `tests/test.treeview.pas` (flip the deferred test).

After `DeleteNode` unlinks the node from its parent's sibling list (and before/after the recursive child free), re-stamp the affected parent's remaining children `Index := 0,1,2,…` — BUT skip when `nsClearing in <something>` / the Clear fast-path is active (so `Clear` stays O(n), not O(n²)). Implement as: in `DeleteNode`, after relinking the parent's `FirstChild`/`LastChild`, if NOT clearing, walk the parent's children once re-stamping `Index`.

- [ ] **Step 1: failing test** — find `TestDeleteMiddleChildUpdatesIndices` (currently asserts indices are NOT re-sequenced, per the ③a deferral). Flip it to assert that after deleting the middle of 3 children, the remaining two have `Index` 0 and 1. Add a `TestClearDoesNotResequencePerNode`-style guard if practical (or just rely on the existing Clear test staying green + fast).
- [ ] **Step 2:** run → fail.
- [ ] **Step 3:** implement the guarded re-sequence in `DeleteNode`.
- [ ] **Step 4:** run → pass; the ③a height invariant + Clear tests stay green.
- [ ] **Step 5:** commit `fix(treeview): DeleteNode re-sequences sibling Index (③a deferral; Clear fast-path skips)`.

### Task A2: check types + tri-state propagation pure helpers

**Files:** `source/tyControls.TreeView.pas` (types + `PropagateCheckDown`, `RecomputeParentCheckState`); Test `tests/test.treeview.pas`.

```pascal
TTyCheckType  = (ctNone, ctCheckBox, ctTriStateCheckBox, ctRadioButton);
TTyCheckState = (csUnchecked, csChecked, csMixed);
```
- `procedure PropagateCheckDown(Node: PTyTreeNode; AState: TTyCheckState)` — set every descendant whose CheckType ∈ {ctCheckBox, ctTriStateCheckBox} to AState (skip ctNone/ctRadioButton). Materialises children it needs (InitChildren) or only touches already-initialised children — pick: only already-initialised (lazy-safe; document it).
- `function RecomputeParentCheckState(Node: PTyTreeNode): TTyCheckState` — over Node's check-children (ctCheckBox/ctTriStateCheckBox only; ignore ctRadioButton/ctNone): all csChecked → csChecked; all csUnchecked → csUnchecked; mixed/any csMixed → csMixed; no check-children → leave (return current).

- [ ] **Step 1: failing tests** — build a parent with 3 ctCheckBox children; `PropagateCheckDown(parent, csChecked)` → all 3 csChecked; `RecomputeParentCheckState` over (checked,checked,unchecked) → csMixed; (checked,checked,checked) → csChecked; a ctRadioButton child is ignored by both.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): check types + tri-state propagation pure helpers`.

### Task A3: range-selection pure helper

**Files:** `source/tyControls.TreeView.pas` (`SelectRange` core); Test `tests/test.treeview.pas`.

`procedure SelectRange(AAnchor, ATarget: PTyTreeNode)` — clear the current selection, then select every VISIBLE node from AAnchor to ATarget inclusive, determined by a visible-order walk (`GetFirstVisibleNoInit`…`GetNextVisibleNoInit`); order-independent (works whether anchor is above or below target). Maintains `FSelectionCount`. (Internal selection mutators `InternalAddToSelection`/`InternalRemoveFromSelection` keep `nsSelected` + `FSelectionCount` in sync.)

- [ ] **Step 1: failing tests** — a flat tree of 6 visible nodes; `SelectRange(node2, node4)` → nodes 2,3,4 selected, count 3; `SelectRange(node4, node2)` → same set (order-independent); `SelectRange(n,n)` → just n.
- [ ] **Step 2:** fail. **Step 3:** implement + the internal mutators + `FSelectionCount`. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): SelectRange visible-order helper + selection-count bookkeeping`.

---

## Phase B — checkbox node fields + paint + hit

### Task B1: node check fields + `Checked`/`CheckType`/`CheckState` + `toCheckSupport`

**Files:** `source/tyControls.TreeView.pas` (node record + `TTyTreeOption`/`Options` + properties); Test `tests/test.treeview.pas`.

Add `CheckType: TTyCheckType` + `CheckState: TTyCheckState` to `TTyTreeNode` (recompute `TreeNodeSize` if needed — confirm the data-blob offset test still passes). Add `TTyTreeOption = (toMultiSelect, toCheckSupport, toFullRowSelect, toAutoTristateTracking); TTyTreeOptions = set of …; published Options: TTyTreeOptions default []`. Properties `CheckType[Node]`, `CheckState[Node]`, `Checked[Node]: Boolean` (csChecked). `Options` setter invalidates + (if toCheckSupport changed and multi-column) re-measures.

- [ ] **Step 1: failing tests** — set `CheckType[node] := ctCheckBox`; `Checked[node] := True` → CheckState csChecked; the node-data-blob offset/round-trip test still passes (record grew but blob offset recomputed); `Options` default [].
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): node check fields + Options set + Checked/CheckType/CheckState`.

### Task B2: checkbox paint in the main column

**Files:** `source/tyControls.TreeView.pas` (`RenderTo` main-column x-accumulation); Test `tests/test.treeview.pas` (pixel).

When `toCheckSupport in Options` and `node.CheckType <> ctNone`, reserve a checkbox slot (`P.Scale(16)`) after the expand button, before the image/caption; draw via the resolved `TyTreeCheckBox` style: box (fill+border) + `tgCheck` when csChecked / a mixed mark when csMixed / empty when csUnchecked; `ctRadioButton` → circle + `tgRadioDot` when csChecked. Shift caption/image start right by the slot (and account for it in `FRangeX`). `toCheckSupport` off → no slot (layout == ③b). Use an inline `TyTreeCheckBox{...}` theme for the pixel test (real typeKey lands in Phase E).

- [ ] **Step 1: failing tests** — checked node draws check-glyph ink in the box slot; unchecked draws an empty box (border only, no check ink); radio draws a dot; the caption starts right of the box slot; `toCheckSupport` off → caption at the ③b x (no slot).
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): checkbox/radio paint in the main column`.

### Task B3: checkbox hit-test (`hpCheckBox`)

**Files:** `source/tyControls.TreeView.pas` (`TTyTreeHitPart` + `GetNodeAtPoint`); Test `tests/test.treeview.pas`.

Add `hpCheckBox` to `TTyTreeHitPart`; in `GetNodeAtPoint`, when `toCheckSupport` + node has a checkbox, the box slot x-range → `hpCheckBox` (between the button slot and the image/label). Must match the B2 paint x exactly (same scale/offset).

- [ ] **Step 1: failing tests** — a click in the checkbox slot of a checkable node → that node + `hpCheckBox`; a click on the label → `hpLabel`; `toCheckSupport` off → no `hpCheckBox`.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): checkbox hit-test (hpCheckBox)`.

---

## Phase C — check behaviour + tri-state + radio

### Task C1: `ToggleCheck` + events + radio exclusivity + propagation wiring

**Files:** `source/tyControls.TreeView.pas` (`ToggleCheck`, `MouseDown` hpCheckBox, `KeyDown` Space, events); Test `tests/test.treeview.pas`.

`procedure ToggleCheck(Node)`: fire `OnChecking(Node; var Allowed)` (default True); if allowed: ctCheckBox → toggle checked/unchecked; ctTriStateCheckBox → user cycles unchecked→checked→unchecked (mixed only via propagation); ctRadioButton → set checked + uncheck ctRadioButton siblings. Then if `toAutoTristateTracking`: `PropagateCheckDown` (for tri-state parents) + walk parents calling `RecomputeParentCheckState`. Fire `OnChecked(Node)`. `MouseDown` on `hpCheckBox` → `ToggleCheck` (does NOT change selection). `Space` key with `toCheckSupport` → `ToggleCheck(FocusedNode)`. Publish `OnChecking`/`OnChecked`.

- [ ] **Step 1: failing tests** — click checkbox slot → toggles CheckState, fires OnChecked, selection unchanged; radio click → siblings uncheck; with `toAutoTristateTracking`, checking a tri-state parent checks the subtree + a parent rolls to csMixed when a child is unchecked; `OnChecking` returning Allowed:=False blocks the change.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): ToggleCheck + OnChecking/OnChecked + radio exclusivity + auto-tri-state`.

---

## Phase D — multi-select + full-row

### Task D1: multi-select mouse (Ctrl/Shift/plain) + selection API

**Files:** `source/tyControls.TreeView.pas` (`MouseDown` multi-select branch, `FRangeAnchor`, selection API); Test `tests/test.treeview.pas`.

When `toMultiSelect`: plain click → clear + select one + anchor; Ctrl+click → toggle membership + anchor; Shift+click → `SelectRange(FRangeAnchor, node)`; Ctrl+Shift+click → extend range without clearing. Public `SelectedCount`, `GetFirstSelected`/`GetNextSelected`, `SelectAll`, `OnSelectionChanged` (fire once per gesture). `toMultiSelect` off → single-select path (③a/③b) unchanged.

- [ ] **Step 1: failing tests** — Ctrl+click two nodes → both selected, count 2; Shift+click after an anchor → the visible range; plain click → collapses to one; `OnSelectionChanged` fired once per gesture; `toMultiSelect` off → single-select (re-run an existing single-select test).
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): multi-select mouse (Ctrl/Shift) + selection API + OnSelectionChanged`.

### Task D2: multi-select keyboard + full-row

**Files:** `source/tyControls.TreeView.pas` (`KeyDown`, `MouseDown` full-row); Test `tests/test.treeview.pas`.

Keyboard (when `toMultiSelect`): `Shift+↓/↑` extend (move caret + SelectRange anchor→caret); `Ctrl+Space` toggle focused; `Ctrl+A` SelectAll; plain arrows → move + single-select + reset anchor. `toFullRowSelect`: `MouseDown`/`GetNodeAtPoint` treat a click anywhere in the row (any column / past text) as a node hit → selects.

- [ ] **Step 1: failing tests** — Shift+Down extends the selection by one; Ctrl+A selects all visible; Ctrl+Space toggles the focused node; with `toFullRowSelect`, a click far right (past the text / in column 2) selects the row; without it, only a label/main-cell click selects.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): multi-select keyboard (Shift/Ctrl) + full-row select`.

---

## Phase E — theme, events, design-time, demo, finish

### Task E1: `TyTreeCheckBox` typeKey + goldens

**Files:** `themes/*.tycss` (all 6), generated mirrors, `tests/test.themes.pas` (`GGRID`), `tests/golden/*`, `tests/test.defaulttheme.pas`.

Add `TyTreeCheckBox` (spec §4) to every theme (green concrete-value), run both generators, extend `GGRID` (+1 bound), re-bootstrap goldens (additive), add `AssertBg('TyTreeCheckBox', [])`. Switch B2's inline-theme checkbox paint to the real typeKey.

- [ ] **Steps:** add CSS → regenerate → GGRID → goldens (additive) → coverage assert → byte-sync/golden/dual-mode green. Commit `feat(treeview): TyTreeCheckBox typeKey across all themes + goldens`.

### Task E2: events RTTI guard

**Files:** `tests/test.treeview.events.pas`. Add `OnChecking`, `OnChecked`, `OnSelectionChanged` (match the actual published set). Commit `test(treeview): RTTI guard for check/selection events`.

### Task E3: design-time — Options + check props stream

**Files:** `source/tyControls.TreeView.pas` (ensure `Options` + any new published props stream), Design.pas if needed. Confirm an `.lfm` with `Options=[toMultiSelect,toCheckSupport,...]` round-trips; `lazbuild tycontrols_dt.lpk` exit 0; palette drift-guard passes. Commit `feat(treeview): stream Options at design time` (only if changes needed).

### Task E4: demo + finish/merge

**Files:** `examples/demo/mainform.lfm` + `mainform.pas`.

Upgrade the demo's multi-column `TyColTree` (or `TyTree1`) with `Options := [toCheckSupport, toMultiSelect, toAutoTristateTracking, toFullRowSelect]`, set some nodes' `CheckType` (a tri-state parent + ctCheckBox children, one ctRadioButton group), wire `OnChecked`/`OnSelectionChanged` to a status label. Build the demo.

- [ ] **Steps:** demo checkboxes + multi-select + handlers; `lazbuild examples/demo/demo.lpi` exit 0; full suite green; then **superpowers:finishing-a-development-branch** (verify → options → merge per user) + opus final adversarial review (whole ③c) before merge, mirroring ③a/③b. Commit `example(demo): checkboxes + multi-select TreeView`.

---

## Self-review notes
- **Spec coverage:** Index fix (A1), propagation (A2), range (A3), check fields/paint/hit (B1-B3), check behaviour+radio+tri-state (C1), multi-select mouse/keyboard+full-row (D1-D2), theme/events/dt/demo (E1-E4) — every spec §3 sub-section maps to a task.
- **Type consistency:** `TTyCheckType`/`TTyCheckState`/`TTyTreeOption`/`TTyTreeOptions`, `PropagateCheckDown`/`RecomputeParentCheckState`, `SelectRange`/`FSelectionCount`/`FRangeAnchor`, `hpCheckBox`, `ToggleCheck`, `OnChecking`/`OnChecked`/`OnSelectionChanged` used consistently.
- **Back-compat:** `Options` default [] keeps ③a/③b; asserted by re-running single-select + ③b tests each interactive task.
- **HiDPI:** the checkbox slot + hit convert logical→device at paint/hit (reuse the discipline); E-phase adds a PPI=144 checkbox test.
