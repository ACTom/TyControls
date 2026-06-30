# ③f Intra-Tree Node Drag-Drop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox (`- [ ]`) steps. Spec: `docs/superpowers/specs/2026-06-30-tycontrols-treeview-f-drag-design.md`.

**Goal:** Drag a node to a new position within the same tree (reorder / reparent), opt-in `toNodeDrag`, via a pure `MoveNode` engine + a thin mouse driver + an accent drop-mark; events `OnDragOver`/`OnNodeMoved`.

**Architecture:** `MoveNode(Node, Target, Mode)` is the single structural primitive (relink siblings + adjust both parent chains' count/height + re-stamp Index + circular guard). The mouse state machine (MouseDown arm → MouseMove threshold+track → MouseUp commit) drives it. Drop-mark painted in RenderTo with the theme accent.

**Tech Stack:** FPC/Lazarus, `source/tyControls.TreeView.pas`, headless tests, `lazbuild tycontrols.lpk` + `tests/tytests.lpi`.

**Baseline:** main `6ea24ac`, suite **1494 / 0 fail / 11 env errors**. Node type is `PTyTreeNode`. Every phase keeps failures 0 and `Options=[]` byte-identical.

---

### Task F1: Pure `MoveNode` / `CanMoveNode` engine

**Files:** Modify `source/tyControls.TreeView.pas`. Test `tests/test.treeview.drag.pas` (new; register in `tytests.lpr`).

- [ ] **Step 1 — explore:** find the node record fields (`Parent`/`NextSibling`/`PrevSibling`/`FirstChild`/`LastChild`/`ChildCount` — confirm the exact names), the subtree count/height accessors, the `AdjustTotalCount`/`AdjustTotalHeight` spine, the `Index` re-sequence helper added in ③c (`DeleteNode`'s sibling renumber), `InvalidateTreeLayout`, `nsHasChildren`/`nsExpanded`, `FRoot`, and how children are appended (the `AddChild` linking code — mirror its pointer fixups).
- [ ] **Step 2 — failing tests:** add `TTreeDragF1Test` with the pure tests from the spec (§Tests 1–6): reorder above/below (Index re-stamped), reparent on (ChildCount/nsHasChildren/Parent), cross-parent counts+heights (root TotalCount conserved), circular rejected, self/dmNone/no-op rejected, auto-expand on dmOn. Build the runner, run, see them FAIL.
- [ ] **Step 3 — implement:**
  - `TTyTreeDropMode = (dmNone, dmAbove, dmOn, dmBelow);` (near the other tree enums).
  - `function IsDescendant(ANode, APossibleAncestor: PTyTreeNode): Boolean;` — walk `ANode.Parent` to `FRoot`; True if it meets `APossibleAncestor`.
  - `function CanMoveNode(ANode, ATarget: PTyTreeNode; AMode: TTyTreeDropMode): Boolean;` — per spec (non-nil, `ANode<>ATarget`, `AMode<>dmNone`, `ANode<>FRoot`, NOT `IsDescendant(ATarget, ANode)` and `ATarget<>ANode`, and not a no-op: compute the would-be (newParent, after-node) and return False if it equals ANode's current (parent, prevSibling)).
  - `function MoveNode(ANode, ATarget: PTyTreeNode; AMode: TTyTreeDropMode): Boolean;` — per spec §MoveNode logic (unlink + subtract old chain, link + add new chain, `Parent`, `nsHasChildren`, auto-expand on dmOn, re-stamp Index on both sibling lists, `InvalidateTreeLayout`). Reuse the existing AddChild/DeleteNode pointer-fixup + Adjust* + Index-reseq code paths; do NOT hand-roll new count/height math if a helper exists.
- [ ] **Step 4 — run, expect PASS** + full suite 0 fail. Assert root `TotalCount` conserved across a cross-parent move.
- [ ] **Step 5 — commit:** `feat(treeview): ③f F1 — MoveNode/CanMoveNode pure intra-tree move engine`.

---

### Task F2: Drag state machine (mouse + Esc) + option + events

**Files:** Modify `source/tyControls.TreeView.pas`. Test `tests/test.treeview.drag.pas`.

- [ ] **Step 1 — explore:** the current `MouseDown`/`MouseMove`/`MouseUp` bodies (how they hit-test, set `FLastMouseNode`/`FLastMouseHitPart`/`FLastMouseColumn`, update the hot/hover node, do selection), the `KeyDown` `case`, and how the existing tests simulate mouse via the access subclass.
- [ ] **Step 2 — failing tests:** `TTreeDragF2Test` (spec §Tests 7–13): MouseDown arms `FDragNode` only on `hpLabel`/`hpImage` + `toNodeDrag`; MouseMove past `Scale(4)` starts the drag; mode-from-Y thirds; `OnDragOver` veto→no move; valid drop→MoveNode+`OnNodeMoved`; Esc cancels; DeleteNode during drag clears; `Options=[]` no drag.
- [ ] **Step 3 — implement:**
  - Add `toNodeDrag` to `TTyTreeOption`. Fields `FDragNode`, `FDragActive: Boolean`, `FDragStartPos: TPoint`, `FDropTarget: PTyTreeNode`, `FDropMode: TTyTreeDropMode`. Read-only `IsDraggingNode`/`DropTargetNode`/`DropMode`. Init in ctor.
  - Events `FOnDragOver: TTyTreeDragOverEvent` (`Sender;Src;Target;Mode;var Allowed`) + `FOnNodeMoved: TTyTreeNodeEvent` (reuse the existing node-event type if its signature is `(Sender;Node)`), published.
  - `procedure EndNodeDrag;` — clear all drag state + `Invalidate`.
  - `MouseDown`: arm per spec (gate on `toNodeDrag` + `FLastMouseHitPart in [hpLabel,hpImage]`).
  - `MouseMove`: threshold-start + while-active track (`FDropTarget`/`FDropMode` from hit-test + Y-thirds, `OnDragOver` veto, `Invalidate`); skip hover update while `FDragActive`.
  - `MouseUp`: commit (`MoveNode` + `OnNodeMoved`) or normal; `EndNodeDrag`.
  - `KeyDown` `VK_ESCAPE` while dragging → `EndNodeDrag`.
  - Teardown: `DeleteNode`/`Clear` clear+null `FDragNode`/`FDropTarget`; `SetOptions` `EndNodeDrag` when `toNodeDrag` removed.
- [ ] **Step 4 — run, expect PASS** + full suite 0 fail (existing MouseDown selection / hover tests must stay green).
- [ ] **Step 5 — commit:** `feat(treeview): ③f F2 — node-drag state machine (arm/threshold/track/commit) + toNodeDrag + events`.

---

### Task F3: Drop-mark paint (above/below line, on outline) — theme accent

**Files:** Modify `source/tyControls.TreeView.pas`. Test `tests/test.treeview.drag.pas` (render assertions).

- [ ] **Step 1 — explore:** how `RenderTo` resolves the accent color (find how the ③b header-drag drop-mark / any accent overlay gets its color — reuse that, NO hard-coded color), and where in `RenderTo` to draw an overlay after the rows. Find the row-rect + `CellTextRect` text-left for the indent.
- [ ] **Step 2 — failing test:** a `RenderTo`-to-bitmap test that, with an active drag + a known `FDropTarget`/`FDropMode`, asserts accent-colored pixels appear at the expected mark location (top edge for `dmAbove`, bottom for `dmBelow`, a row outline for `dmOn`) and NOT when `FDropMode=dmNone`. (Set the drag state via the access subclass.)
- [ ] **Step 3 — implement:** in `RenderTo`, after the rows, `if FDragActive and (FDropMode<>dmNone) and <FDropTarget visible>`: draw the mark — `dmAbove`/`dmBelow` a `Scale(2)` accent line at the target row top/bottom from the target text-left to the content right; `dmOn` an accent rounded-rect/outline over the target row. Accent from the resolved theme (same source as the header drag-mark).
- [ ] **Step 4 — run, expect PASS** + full suite 0 fail.
- [ ] **Step 5 — commit:** `feat(treeview): ③f F3 — drop-mark paint (above/below line, on-outline) via theme accent`.

---

### Task F4: Events-RTTI + showcase + adversarial review + finish

- [ ] **Step 1 — events RTTI guard:** add `OnDragOver`/`OnNodeMoved` to `tests/test.treeview.events.pas`'s `AssertPub` set. Green.
- [ ] **Step 2 — showcase:** in `examples/treeview/showcasemain.pas`, enable `toNodeDrag` on a suitable tab (a structural tree — e.g. the columns/structure tree); optional status-bar note in `OnNodeMoved`. The node-data blob travels with the node, so no write-back. Rebuild `-B`, exit 0.
- [ ] **Step 3 — full verify:** `lazbuild tycontrols.lpk` (0) + suite (0 fail) + `lazbuild -B examples/treeview/treeviewshowcase.lpi` (0) + `lazbuild -B examples/demo/demo.lpi` (0).
- [ ] **Step 4 — adversarial review:** 2 read-only opus reviewers over the ③f diff — one pointer/lifecycle/circular-guard/count-height-conservation lens, one mouse-gesture/coords/drop-mark/VTV-parity lens. Triage; fix real findings; re-verify.
- [ ] **Step 5 — finish branch:** superpowers:finishing-a-development-branch → present options → (user merges to main + real-machine test the drag).

---

## Self-review notes
- **`MoveNode` is the only structural mutator** — `CanMoveNode` is the single validity gate (the drag UI, the public API, and `OnDragOver`'s default all route through it). A malicious `OnDragOver` setting `Allowed:=True` can't bypass it (MoveNode re-checks).
- **Count/height conservation:** the root `TotalCount` must be identical before/after any move — assert it. Reuse `AdjustTotalCount`/`AdjustTotalHeight`; subtract from the old chain BEFORE relinking, add to the new chain AFTER.
- **Dangling hygiene:** `FDragNode`/`FDropTarget` join `FLastMouseNode`/`FHotNode`/`FEditNode` in the `DeleteNode`/`Clear` null-out. A drag that frees its own source (can't normally happen mid-gesture, but `Clear` from an event could) ⇒ `EndNodeDrag`.
- **`Options=[]` invariance:** every drag path gates on `toNodeDrag` (MouseDown arm) or `FDragActive`/`FDragNode<>nil` (Move/Up/paint), so a non-drag tree is byte-identical.
- **Reuse, don't re-roll:** the Index re-sequence (③c), the Adjust* spine (③a), `CellTextRect` (③e), the accent-resolution (③b drag-mark) all exist — call them.
