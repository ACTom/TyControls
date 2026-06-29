# TTyTreeView ③d — Engine Enhancements (Variable Height + Incremental Search + Per-Cell Owner-Draw) — Design Spec

**Date:** 2026-06-29
**Sub-project:** ③d of phase-3 「TreeView 高级」 (the advanced VTV-parity layer). The base `TTyTreeView` (③a engine + ③b columns/sort + ③c checkboxes/multi-select) is complete on `main`. ③d is the first phase-3 sub-project; ③e (inline editing) and ③f (intra-tree node drag-drop) follow as separate specs. Sequenced first because all three of its features are small (S/S-M), introduce no new child control, and share one refactor (`GetCellRect`) that ③e also needs.
**Branch:** `feat/treeview-d` (off `main`).

## 1. Goal

Add three deferred VTV-class engine features to `TTyTreeView`, all opt-in (default behaves exactly like ③c):
1. **Variable per-node row height** — each node may have its own height via `OnMeasureItem`.
2. **Incremental search** — type-to-find: typed characters jump focus to the next matching visible node.
3. **Per-cell owner-draw** — `OnBeforeCellPaint`/`OnAfterCellPaint` hooks + full `OnDrawNode` cell replacement (the `TVirtualDrawTree` story).

Plus the shared refactor they rest on: a `GetCellRect(Node, Column)` helper that reproduces `RenderTo`'s cell geometry without painting (also required by ③e).

## 2. Scope (user-approved 2026-06-29; v2.1.0 holds for phase-3)

**IN:** variable row height (`OnMeasureItem` + `toVariableNodeHeight` + public `NodeHeight[]`); incremental search (`toIncrementalSearch` + `OnIncrementalSearch` + buffer/timeout); per-cell owner-draw (`OnBeforeCellPaint`/`OnAfterCellPaint` + `OnDrawNode` + `toOwnerDraw`); the `GetCellRect` helper.

**DEFERRED:** inline editing (③e), node drag-drop (③f), clipboard / selection serialization (later). `OnDrawNode` is single-cell owner-draw, not a separate `TTyDrawTree` class.

## 3. Architecture

### 3.0 Shared refactor — `GetCellRect`

`RenderTo` computes each cell's device rect inline (the `colCellLeft`/`colCellRight`/`rowTop`/`rowH` accumulation, incl. `contentLeft = CR.Left + FOffsetX`, the main-column indent/button/checkbox/image slots, and per-column `FLeft`). Extract:
```pascal
function GetCellRect(Node: PTyTreeNode; Column: Integer; out ACellRect: TRect): Boolean;
```
Returns the cell's **device** rect (same coordinate space as `ACanvas`/`Paint`), accounting for scroll (`FOffsetX`/`FOffsetY`), the header band inset, and HiDPI (`P.Scale`/`MulDiv(.,PPI,96)` — the established discipline). `Column = -1` (or the main column) for the single-column / main-column cell. Returns `False` if the node isn't currently visible (off-screen). `RenderTo` is refactored to USE this helper for its per-cell rect so paint and `GetCellRect` cannot drift (single source of truth). This is the load-bearing change; ③e (editing) reuses it to position the editor.

### 3.1 Variable per-node row height

The engine is already per-node: `TTyTreeNode.NodeHeight: Word` exists, `nsHeightMeasured` is a reserved state bit, and `AdjustTotalHeight`/`GetNodeAt`/`ValidateCache`/`ScrollIntoView`/the paint loop all sum/scale per-node `NodeHeight` (the height invariant is `RootNode.TotalHeight == Σ visible NodeHeight`). So variable height is mostly wiring:
- New option `toVariableNodeHeight`.
- New event `TTyTreeMeasureItemEvent = procedure(Sender: TTyTreeView; ACanvas: TCanvas; Node: PTyTreeNode; var ANodeHeight: Integer) of object;` published `OnMeasureItem`.
- **Measure point:** at the END of `InitNode(Node)`, when `toVariableNodeHeight` and `OnMeasureItem` assigned and `nsHeightMeasured` not yet set: fire `OnMeasureItem` (ANodeHeight defaults to the current/default), then if the returned height differs from `Node^.NodeHeight` call `AdjustTotalHeight(Node, newH - oldH)` and set `Node^.NodeHeight := newH`; `Include(nsHeightMeasured)`. **Measure ONLY in `InitNode`, never in `GetNodeAt`** (re-entrant layout risk). The paint loop already calls `InitNode` before reading `NodeHeight`, so measurement happens at the right time.
- Public `property NodeHeight[Node: PTyTreeNode]: Integer read GetNodeHeight write SetNodeHeight;` — `SetNodeHeight` applies the delta via `AdjustTotalHeight` + `Include(nsHeightMeasured)` + invalidate (programmatic override, like VTV `SetNodeHeight`).
- **Cold-cache caveat:** `ValidateCache` walks `GetNextVisibleNoInit` (no init), so on a cold rebuild it would use unmeasured heights. Mitigation: when `toVariableNodeHeight` is set, the paint pass that calls `InitNode` (which measures) marks the layout dirty if any height changed, forcing a cache rebuild next access. Keep it correct + simple; a measured node stays measured (cached in the field).
- `DoMouseWheel`/PageUp-Dn use `FDefaultNodeHeight` for the page estimate — acceptable approximation with variable heights (document it).

### 3.2 Incremental search

- New option `toIncrementalSearch`; private `FSearchBuffer: string`, `FSearchLastTick: QWord`, published `FSearchTimeout: Integer` (default 1000 ms).
- Event `TTyTreeIncrementalSearchEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; const ASearchText: string; var AMatch: Boolean) of object;` published `OnIncrementalSearch`. If unassigned, the default match is a case-insensitive prefix test against the node's text (`OnGetText`/`OnGetTextWithType` for the main column).
- **Input:** override `UTF8KeyPress(var UTF8Key: TUTF8Char)` — LCL delivers printable chars here (after `KeyDown`). When `toIncrementalSearch` and the char is printable: if `GetTickCount64 - FSearchLastTick > FSearchTimeout` reset `FSearchBuffer`; append the char; `FSearchLastTick := GetTickCount64`; walk `GetNextVisibleNoInit` from `FFocusedNode` (wrapping) calling the match; on first match `FocusedNode := matchNode` (selects + `ScrollIntoView`). Re-pressing the same single char advances to the next match (VTV behavior).
- **Backspace:** intercept `VK_BACK` in `KeyDown` when `toIncrementalSearch` and `FSearchBuffer <> ''` → pop the last char + re-search; consume the key.
- **Lazy:** visible-only walk (`GetNextVisibleNoInit`) — never force-init the whole tree (document the limitation vs VTV's `isAll`).
- **Edit suppression:** (forward-compat for ③e) skip incremental search while an editor is active.

### 3.3 Per-cell owner-draw

- New events: `TTyTreeCellPaintEvent = procedure(Sender: TTyTreeView; ACanvas: TCanvas; Node: PTyTreeNode; Column: Integer; const ACellRect: TRect) of object;` published `OnBeforeCellPaint` + `OnAfterCellPaint`. `TTyTreeDrawNodeEvent` (same shape) published `OnDrawNode`; new option `toOwnerDraw`.
- **In `RenderTo`'s per-cell block** (both single- and multi-column paths), using the `GetCellRect`-derived `cellRect`:
  - Fire `OnBeforeCellPaint(ACanvas, node, colIdx, cellRect)` BEFORE the cell's default content (after the row bg). The app may fill the cell bg / draw a backdrop.
  - If `toOwnerDraw` AND `OnDrawNode` assigned: call `OnDrawNode(ACanvas, node, colIdx, cellRect)` and SKIP the default text/image draw for that cell (the app owns it).
  - Else draw the default content (chrome/image/caption) as today.
  - After the default content (and the existing `OnPaintText`): fire `OnAfterCellPaint(ACanvas, node, colIdx, cellRect)` for overlays.
- **Clip:** the BGRA clip (`P.Bitmap.ClipRect`) clips the painter, NOT the GDI `ACanvas`. Around the owner-draw callbacks, `IntersectClipRect(ACanvas.Handle, cellRect)` (save/restore the region) so app GDI draws stay within the cell — mirror how `FImages.Draw(ACanvas,…)` already writes to the shared DC.
- All visual values the DEFAULT path draws stay token-driven; the owner-draw hooks hand the app the canvas + rect and make no color decisions.

### 3.4 Events / options summary

New events: `OnMeasureItem`, `OnIncrementalSearch`, `OnBeforeCellPaint`, `OnAfterCellPaint`, `OnDrawNode`. New options: `toVariableNodeHeight`, `toIncrementalSearch`, `toOwnerDraw` (added to `TTyTreeOption`). New property `NodeHeight[]`. New published `SearchTimeout`. New public method `GetCellRect`. **Default (`Options` empty of the new flags, events unassigned) == ③c behavior exactly.**

## 4. Testing strategy

**Pure / engine:**
- `GetCellRect`: for a known tree at PPI=96 and PPI=144, the rect of node N column C matches the painted geometry (cross-check against a manual `P.Scale` computation); off-screen node → False; with `FOffsetX`/`FOffsetY` set, the rect shifts correctly.
- Variable height: `OnMeasureItem` returning per-node heights → `RootNode.TotalHeight == Σ measured heights` (the ③a invariant holds with variable heights); `GetNodeAt(y)` lands on the right node with mixed heights; `NodeHeight[node] := h` updates TotalHeight by the delta; `toVariableNodeHeight` off → all nodes `FDefaultNodeHeight` (== ③c).
- Incremental search: a search-string match walks to the right visible node (default prefix match); `OnIncrementalSearch` override is honored; timeout resets the buffer; Backspace pops; re-press advances; `toIncrementalSearch` off → typing does nothing special.

**Control-level (RenderTo pixel):**
- Owner-draw: `OnBeforeCellPaint` fills a cell with a probe color → that color appears in the cell rect under the default text; `toOwnerDraw`+`OnDrawNode` → the default caption is NOT drawn (app fully owns), the app's probe IS; `OnAfterCellPaint` overlay appears on top. The cell rect passed equals `GetCellRect`.
- **Back-compat:** every ③a/③b/③c test stays green (new options default off, new events unassigned → identical paint/layout). HiDPI PPI=144 variable-height + GetCellRect test.

## 5. Key decisions

1. **`GetCellRect` is the shared spine** — extract it first, refactor `RenderTo` to use it, so paint/measure/edit/owner-draw all agree. ③e depends on it.
2. **Measure only in `InitNode`** (not `GetNodeAt`) — avoids re-entrant layout; the engine is already per-node so this is wiring, not a rewrite.
3. **Incremental search via `UTF8KeyPress`** (printable) + `KeyDown` (Backspace) — LCL's `WM_CHAR` equivalent; visible-only walk for the lazy model.
4. **Owner-draw clips GDI via `IntersectClipRect(ACanvas.Handle, …)`** (the BGRA clip doesn't bind GDI) — same DC-sharing as the existing image draw.
5. **All opt-in; default == ③c** — guarded by the new option flags + `Assigned(event)` checks.
