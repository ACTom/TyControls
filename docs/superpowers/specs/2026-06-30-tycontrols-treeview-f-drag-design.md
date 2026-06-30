# ③f Intra-Tree Node Drag-Drop — Design

**Date:** 2026-06-30
**Status:** approved-to-build (phase-3 FINAL piece; scope pre-approved 2026-06-29)
**Branch:** `feat/treeview-f` (off main `6ea24ac`)

## Goal

Drag a node to a new position within the SAME tree — reorder among siblings or reparent — opt-in
via `toNodeDrag`. Pure MOVE (no copy). VTV-ish: a public `MoveNode` engine + `OnDragOver` veto +
`OnNodeMoved`. The control owns the structure; the node-data blob travels with the node, so the
app needs no write-back (unlike ③e).

## Non-goals (deferred)

- OLE / cross-tree / external drag sources or drop targets.
- Multi-node drag (drag the whole selection) — v1 drags the single pressed node.
- Auto-scroll when the cursor nears the top/bottom edge mid-drag (NOTE it; v1 drops within the
  currently-visible window — scroll first).
- A copy-on-Ctrl-drag mode.

## Types

`TTyTreeDropMode = (dmNone, dmAbove, dmOn, dmBelow)` — drop position relative to the target.

## Public API

- `function MoveNode(ANode, ATarget: PTyTreeNode; AMode: TTyTreeDropMode): Boolean;` — the pure
  move. Relinks the sibling lists, adjusts both parent chains' `TotalCount`/`TotalHeight`,
  re-stamps `Index`, sets `ANode.Parent`. Returns False when invalid (see `CanMoveNode`).
  Public — also usable programmatically.
- `function CanMoveNode(ANode, ATarget: PTyTreeNode; AMode: TTyTreeDropMode): Boolean;` — the
  validity predicate: non-nil, `ANode <> ATarget`, `AMode <> dmNone`, `ANode <> FRoot`, `ATarget`
  is NOT `ANode` nor a descendant of `ANode` (circular-reparent guard), and the move is not a
  no-op (would leave `ANode` exactly where it is). Shared by `MoveNode`, the default `OnDragOver`,
  and the drop-mark gating.
- read-only `IsDraggingNode: Boolean`, `DropTargetNode: PTyTreeNode`, `DropMode: TTyTreeDropMode`.

## Events

- `OnDragOver(Sender; Src, Target: PTyTreeNode; Mode: TTyTreeDropMode; var Allowed: Boolean)` —
  per-target/-mode veto. `Allowed` defaults to `CanMoveNode(Src, Target, Mode)`; the handler may
  only further restrict (a handler that sets `Allowed := True` on an invalid move is still blocked
  by `MoveNode`'s own guard — `CanMoveNode` is the hard gate).
- `OnNodeMoved(Sender; Node: PTyTreeNode)` — after a successful move (`Node.Parent` is the new
  parent; `Index` re-stamped).

## Option

Add `toNodeDrag` to `TTyTreeOption`. `Options = []` ⇒ no drag (every prior test green).

## MoveNode logic

1. `if not CanMoveNode(...) then Exit(False)`.
2. New parent + insert point: `dmOn` → `newParent := ATarget`, append as last child; `dmAbove` →
   `newParent := ATarget.Parent`, insert before `ATarget`; `dmBelow` → `newParent := ATarget.Parent`,
   insert after `ATarget`. (Root's children use `FRoot` as `newParent`.)
3. **Unlink** `ANode` from its current parent's child list (fix the neighbours' `NextSibling`/
   `PrevSibling`, the parent's `FirstChild`/`LastChild`/`ChildCount`); subtract `ANode`'s subtree
   (`SubtreeCount` + `SubtreeHeight`) from the OLD parent chain up to `FRoot`
   (`AdjustTotalCount`/`AdjustTotalHeight`, the existing spine).
4. **Link** `ANode` at the new position (fix `NextSibling`/`PrevSibling`/`FirstChild`/`LastChild`/
   `ChildCount`, set `ANode.Parent := newParent`); add `ANode`'s subtree to the NEW parent chain.
5. `newParent` gains `nsHasChildren`; on `dmOn`, auto-expand `newParent` (`Include(nsExpanded)` +
   height adjust) so the drop is visible.
6. **Re-stamp `Index`** for `ANode`'s OLD sibling list and the NEW sibling list (the ③c
   re-sequence helper — `Index` is sibling position).
7. `InvalidateTreeLayout` (position cache + `FTotalHeight` recompute). No node is freed, so cached
   pointers stay valid.
8. `Result := True`.

`ANode`'s descendants keep their relative structure; their depth changes implicitly (level is
computed by walking `Parent`, not stored).

## Drag state machine (mouse) — mirrors the ③b header-reorder shape

State: `FDragNode`, `FDragActive: Boolean`, `FDragStartPos: TPoint`, `FDropTarget`,
`FDropMode: TTyTreeDropMode`.

- **`MouseDown`** (after the existing hit-test/selection): if `(toNodeDrag in FOptions)` and the
  hit landed on a node label/image region (`FLastMouseHitPart in [hpLabel, hpImage]`, NOT the
  expand button / checkbox) ⇒ `FDragNode := FLastMouseNode; FDragStartPos := Point(X, Y);
  FDragActive := False`. (Selection still happens normally; the drag only ARMS here.)
- **`MouseMove`:**
  - Arm→active: `if (ssLeft in Shift) and (toNodeDrag in FOptions) and (FDragNode <> nil) and not
    FDragActive and (manhattan(pt, FDragStartPos) > Scale(4))` ⇒ `FDragActive := True`.
  - While active: hit-test the node under the cursor → `FDropTarget`; `FDropMode` from the cursor's
    Y within that row (top third → `dmAbove`, middle → `dmOn`, bottom third → `dmBelow`; empty
    area → `dmNone`); `allowed := CanMoveNode(FDragNode, FDropTarget, FDropMode)`; fire `OnDragOver`
    (var `allowed`); `if not allowed then FDropMode := dmNone`; set `Cursor`; `Invalidate` for the
    drop-mark. SKIP the normal hover/hot-node update while dragging.
- **`MouseUp`:** `if FDragActive then begin if (FDropTarget <> nil) and (FDropMode <> dmNone) and
  MoveNode(FDragNode, FDropTarget, FDropMode) then OnNodeMoved; EndNodeDrag; end` else the normal
  MouseUp. `EndNodeDrag` clears all drag state + `Invalidate`.
- **`KeyDown` `VK_ESCAPE`** while `FDragActive` ⇒ `EndNodeDrag` (cancel, no move).
- **Teardown:** `DeleteNode`/`Clear` of (or containing) `FDragNode`/`FDropTarget` ⇒ `EndNodeDrag`
  + null the pointers (dangling hygiene, alongside `FLastMouseNode`/`FHotNode`/`FEditNode`).
  `toNodeDrag` removed mid-drag (`SetOptions`) ⇒ `EndNodeDrag`.

## Drop-mark paint (`RenderTo`)

When `FDragActive` and `FDropMode <> dmNone` and `FDropTarget` visible:
- `dmAbove` / `dmBelow`: a `Scale(2)` accent horizontal line at the target row's top / bottom,
  starting at the target's text-left (`CellTextRect`-style indent so it reads as "between these
  siblings at this level").
- `dmOn`: an accent rounded-rect outline (or tint) over the target row.
- Accent color from the theme (the SAME accent the ③b header-drag drop-mark uses — no hard-coded
  color, no new typeKey). Drawn after the rows, before/with the other overlays.

## Coords / HiDPI

Reuse the row-rect / `GetCellRect` math; mark thickness `Scale(2)`; the Y-thirds use the row band.
No new device↔logical conversions beyond the existing spine.

## Tests

**Pure (F1 — headless, the bulk):**
1. `dmAbove`/`dmBelow` reorder within the same parent — sibling order + `Index` re-stamped; `dmOn`
   reparents (newParent `ChildCount`+1, `nsHasChildren`, `ANode.Parent = newParent`).
2. Move across DIFFERENT parents — old parent `ChildCount`−1, new +1; both chains' `TotalCount` /
   `TotalHeight` correct (assert the root `TotalCount` is conserved).
3. Circular rejected: `MoveNode(parent, ownChild, dmOn)` ⇒ False, tree unchanged.
4. Self / `dmNone` / no-op (e.g. `dmBelow` the node already directly below… i.e. moving a node to
   its current slot) ⇒ False, unchanged.
5. `CanMoveNode` predicate matrix.
6. Auto-expand on `dmOn` into a collapsed target.

**Drag (F2 — simulated mouse via the test access subclass):**
7. `MouseDown` arms `FDragNode` only on `hpLabel`/`hpImage` + `toNodeDrag`; not on button/checkbox.
8. `MouseMove` past `Scale(4)` starts the drag; mode-from-Y (top/mid/bottom thirds).
9. `OnDragOver` veto → `dmNone` → `MouseUp` performs no move.
10. Valid drop → `MoveNode` ran + `OnNodeMoved` fired once.
11. `VK_ESCAPE` cancels (no move).
12. `DeleteNode`/`Clear` during a drag clears state (no UAF on next paint).
13. `Options = []` ⇒ no drag; all prior tree tests green.

## Files

- **Modify** `source/tyControls.TreeView.pas`: `toNodeDrag`; `TTyTreeDropMode`; drag state +
  `MoveNode`/`CanMoveNode`/`IsDescendant`/`EndNodeDrag`; the `MouseDown`/`MouseMove`/`MouseUp`/
  `KeyDown` drag wiring; drop-mark paint in `RenderTo`; teardown in `DeleteNode`/`Clear`/
  `SetOptions`; the 2 events + the events-RTTI guard; reuse the `Index` re-sequence + the
  `AdjustTotalCount`/`AdjustTotalHeight` spine + `CellTextRect`.
- **Tests** `tests/test.treeview.drag.pas` (new) + the RTTI-guard count bump.
- **Showcase** `examples/treeview/showcasemain.pas`: enable `toNodeDrag` on a tab (the structure
  tree), optional status-bar note on `OnNodeMoved`. (The blob rides with the node — no write-back.)
- **Theme:** drop-mark uses the existing accent; no new typeKey (verify against the ③b drag-mark).

## Out-of-scope confirmations

- No node-record growth (drag state on the control).
- `Index` is sibling-position (re-stamped here, consistent with ③c's `DeleteNode`/sort).
- `MoveNode` is the single structural primitive; the mouse machine is a thin driver over it.
