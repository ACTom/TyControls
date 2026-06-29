# TTyTreeView ③d — Engine Enhancements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development — fresh subagent per task, spec-review + quality-review between tasks. Steps use `- [ ]`.

**Goal:** Add variable per-node row height, incremental search, and per-cell owner-draw to `TTyTreeView`, all opt-in (default == ③c), resting on a shared `GetCellRect` refactor. First sub-project of phase-3 「TreeView 高级」.

**Architecture:** Extract `GetCellRect` from `RenderTo` (single source of cell geometry) first; then variable height (the engine is already per-node — wire `OnMeasureItem` into `InitNode`), incremental search (`UTF8KeyPress` + buffer/timeout), and owner-draw hooks (`OnBeforeCellPaint`/`OnAfterCellPaint`/`OnDrawNode`, GDI-clipped to the cell). Spec: `docs/superpowers/specs/2026-06-29-tycontrols-treeview-d-enhance-design.md`.

**Baseline:** `main` builds at **1395 run / 0 fail / 11 pre-existing env errors**. Every task: `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → failures 0; commit ending `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; never push.

**Invariants every task:** ③a height invariant (`RootNode.TotalHeight == Σ visible NodeHeight`); all ③a/③b/③c tests (new options default off + new events unassigned → identical behavior); theme byte-sync/goldens; events RTTI guard; HiDPI.

---

## Phase A — `GetCellRect` (the shared spine)

### Task A1: extract `GetCellRect`, refactor `RenderTo` to use it

**Files:** `source/tyControls.TreeView.pas`; Test `tests/test.treeview.pas`.

Add `function GetCellRect(Node: PTyTreeNode; Column: Integer; out ACellRect: TRect): Boolean;` returning the cell's DEVICE rect (same space as `ACanvas`), accounting for `FOffsetX`/`FOffsetY`, the header band inset, the main-column chrome slots (indent/button/checkbox/image) vs flat columns, per-column `FLeft`, and HiDPI (`MulDiv(.,PPI,96)`). `Column = -1`/main column → the main cell. `False` if the node isn't visible. Then refactor `RenderTo` so its per-cell `cellRect` comes from the SAME geometry (call `GetCellRect` per painted cell, or factor the math into a shared local both use) — paint and `GetCellRect` must not drift.

- [ ] **Step 1: failing tests** — build a tree (PPI 96), expand; assert `GetCellRect(node, 0)` matches the manually-computed device rect (row top = visible-index × Scale(NodeHeight) below the header; left = contentLeft + main-column offset); a column-2 cell rect sits in column 2's x-span; an off-screen (scrolled-past) node → False; at PPI=144 the rect scales. Cross-check: the rect equals where `RenderTo` paints that cell (render to a bitmap, find the caption ink, confirm it's inside the rect).
- [ ] **Step 2:** fail. **Step 3:** implement + refactor RenderTo. **Step 4:** pass; ALL ③a/b/c paint tests stay green (refactor is behavior-preserving).
- [ ] **Step 5:** commit `refactor(treeview): GetCellRect helper (single source of cell geometry; RenderTo uses it)`.

---

## Phase B — variable per-node row height

### Task B1: `toVariableNodeHeight` + `OnMeasureItem` + `NodeHeight[]`

**Files:** `source/tyControls.TreeView.pas`; Test `tests/test.treeview.pas`.

Add `toVariableNodeHeight` to `TTyTreeOption`. `TTyTreeMeasureItemEvent = procedure(Sender: TTyTreeView; ACanvas: TCanvas; Node: PTyTreeNode; var ANodeHeight: Integer) of object;` published `OnMeasureItem`. At the END of `InitNode(Node)`: if `toVariableNodeHeight` + `OnMeasureItem` assigned + not `(nsHeightMeasured in States)`: `h := Node^.NodeHeight; OnMeasureItem(Self, Canvas, Node, h); if h <> Node^.NodeHeight then begin AdjustTotalHeight(Node, h - Node^.NodeHeight); Node^.NodeHeight := Word(h); end; Include(Node^.States, nsHeightMeasured);`. Public `property NodeHeight[Node]: Integer read GetNodeHeight write SetNodeHeight` — `SetNodeHeight` applies the delta via `AdjustTotalHeight` + `Include(nsHeightMeasured)` + `InvalidateTreeLayout`/`Invalidate`. (Measure ONLY in InitNode — never GetNodeAt.)

- [ ] **Step 1: failing tests** — `OnMeasureItem` returns height = 18 + 6×(Index mod 3) for a flat tree; after init/paint, `RootNode^.TotalHeight == Σ` of those heights (invariant holds with variable heights); `GetNodeAt(y)` lands on the correct node across the varied heights; `NodeHeight[node] := 40` bumps TotalHeight by the delta; `toVariableNodeHeight` off → every node = `FDefaultNodeHeight` (== ③c).
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass + invariant test green.
- [ ] **Step 5:** commit `feat(treeview): variable per-node row height (OnMeasureItem + toVariableNodeHeight + NodeHeight[])`.

---

## Phase C — incremental search

### Task C1: `toIncrementalSearch` + `UTF8KeyPress` + buffer/timeout + `OnIncrementalSearch`

**Files:** `source/tyControls.TreeView.pas`; Test `tests/test.treeview.pas`.

Add `toIncrementalSearch` option; private `FSearchBuffer: string`, `FSearchLastTick: QWord`; published `SearchTimeout: Integer` (default 1000). `TTyTreeIncrementalSearchEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; const ASearchText: string; var AMatch: Boolean) of object;` published `OnIncrementalSearch` (default = case-insensitive prefix match on the node's main-column text). Override `UTF8KeyPress(var UTF8Key: TUTF8Char)`: when `toIncrementalSearch` + printable: timeout-reset, append, walk `GetNextVisibleNoInit` from `FFocusedNode` (wrapping) → first match `FocusedNode := match`. Intercept `VK_BACK` in `KeyDown` (when searching) to pop + re-search. Suppress while an editor is active (forward-compat: guard on a `FEditing` flag that's always False until ③e).

- [ ] **Step 1: failing tests** — a tree with named nodes; simulate typing "ba" via the test `UTF8KeyPress` accessor → focus lands on the first visible node whose text starts with "ba"; `OnIncrementalSearch` override is honored; after `SearchTimeout` the buffer resets (simulate by setting `FSearchLastTick` back); Backspace pops a char; `toIncrementalSearch` off → typing changes nothing.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): incremental type-to-find search (toIncrementalSearch + OnIncrementalSearch)`.

---

## Phase D — per-cell owner-draw

### Task D1: `OnBeforeCellPaint`/`OnAfterCellPaint` + `OnDrawNode`/`toOwnerDraw`

**Files:** `source/tyControls.TreeView.pas`; Test `tests/test.treeview.pas` (pixel).

`TTyTreeCellPaintEvent = procedure(Sender: TTyTreeView; ACanvas: TCanvas; Node: PTyTreeNode; Column: Integer; const ACellRect: TRect) of object;` published `OnBeforeCellPaint` + `OnAfterCellPaint`. `TTyTreeDrawNodeEvent` (same shape) published `OnDrawNode`; add `toOwnerDraw` to `TTyTreeOption`. In `RenderTo`'s per-cell block (both paths), with `cellRect := GetCellRect(...)`: fire `OnBeforeCellPaint` (after row bg, before content); if `toOwnerDraw` + `OnDrawNode` assigned → call it + SKIP the default content; else default content; then fire `OnAfterCellPaint`. Wrap the callbacks with `IntersectClipRect(ACanvas.Handle, cellRect)` (save/restore the clip region) so app GDI stays in the cell.

- [ ] **Step 1: failing tests** — inline theme; `OnBeforeCellPaint` fills the cell with a probe RGB → that color appears in the cell rect (and the default caption still draws on top); `toOwnerDraw`+`OnDrawNode` drawing a probe → the default caption is ABSENT (app owns the cell), the probe present; `OnAfterCellPaint` overlay present; the `ACellRect` passed equals `GetCellRect`. Non-vacuous pixel scans.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass; default (no owner-draw events) == ③c paint.
- [ ] **Step 5:** commit `feat(treeview): per-cell owner-draw (OnBeforeCellPaint/OnAfterCellPaint/OnDrawNode + toOwnerDraw)`.

---

## Phase E — events guard, showcase, finish

### Task E1: events RTTI guard
**Files:** `tests/test.treeview.events.pas`. Add `OnMeasureItem`, `OnIncrementalSearch`, `OnBeforeCellPaint`, `OnAfterCellPaint`, `OnDrawNode` to the guard (match the published set). Commit `test(treeview): RTTI guard for ③d events`.

### Task E2: showcase + finish/merge
**Files:** `examples/treeview/showcasemain.pas` (add a page or extend one): a variable-height + owner-draw demo (e.g. a node painted with a custom backdrop via `OnBeforeCellPaint`, taller rows via `OnMeasureItem`) + an incremental-search hint. Build the showcase (`lazbuild examples/treeview/treeviewshowcase.lpi` exit 0). Then **superpowers:finishing-a-development-branch** (verify → options → merge per user) + opus final adversarial review (whole ③d: GetCellRect correctness, measure-timing/cache, search edge cases, owner-draw clip) before merge, mirroring ③a/b/c. Commit `example(treeview): variable-height + owner-draw showcase page`.

---

## Self-review notes
- **Spec coverage:** GetCellRect (A1), variable height (B1), incremental search (C1), owner-draw (D1), events+showcase+finish (E1-E2) — every spec §3 sub-section maps to a task.
- **Type consistency:** `GetCellRect`, `toVariableNodeHeight`/`OnMeasureItem`/`NodeHeight[]`, `toIncrementalSearch`/`OnIncrementalSearch`/`SearchTimeout`/`FSearchBuffer`, `toOwnerDraw`/`OnBeforeCellPaint`/`OnAfterCellPaint`/`OnDrawNode` used consistently.
- **Back-compat:** new options default off + events unassigned ⇒ ③c behavior; asserted by re-running ③a/b/c tests each task.
- **HiDPI:** GetCellRect + variable height tested at PPI=144.
- **③e dependency:** GetCellRect (A1) + the `FEditing` suppression flag (C1) are the hooks ③e (inline editing) builds on.
