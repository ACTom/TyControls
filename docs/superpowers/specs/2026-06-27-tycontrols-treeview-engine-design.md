# TTyTreeView ③a — Virtual Engine + Single-Column Tree Design Spec

**Date:** 2026-06-27 · **Status:** approved (design) · **Program:** [new-controls ③ / phase-2] · **Sub-project:** ③a of ③ (③b multi-column, ③c checkboxes/multi-select follow as separate specs)

## Goal

A Ty-native, custom-drawn **virtual** tree control (`TTyTreeView`) that faithfully replicates VirtualTreeView's data-on-demand paradigm — the tree owns a graph of tiny fixed-layout node records and asks the application for counts/flags/text only for the nodes it is about to render, so millions of (or infinitely deep) nodes cost nothing until shown. ③a delivers the engine + a usable single-column plain tree (expand/collapse, selection, keyboard, scrolling, images, tree lines).

## Why faithful (the user's bar)

The user explicitly rejected a "weak/slow" tree ("功能和性能太弱了没有意义") and asked to model VirtualTreeView. So the **virtual node-record store + lazy initialization + incremental-height virtual scroll** are non-negotiable — a simple TObject-per-node tree is out of scope. The reference (read in full) is `…\VirtualTreeViewV5\Source\VirtualTrees.pas` (`TBaseVirtualTree`/`TCustomVirtualStringTree`/`TVirtualStringTree`).

---

## Architecture

One unit `source/tyControls.TreeView.pas` (engine + control are deeply coupled in VTV; keep together, but factor pure algorithms into tested functions). `TTyTreeView = class(TTyCustomControl)`, custom-draw via `TTyPainter`, themed via tokens. Two embedded `TTyScrollBar` instances (vertical/horizontal), as in `TTyListBox`/`TTyMemo`.

### Layered concerns
1. **Node store** — the virtual `PVirtualNode` record graph + 3-stage lazy lifecycle + inlined user data.
2. **Scroll engine** — incremental `TotalHeight`, `FRangeY`, `GetNodeAt(Y)` (subtree-skip + position cache).
3. **Control** — visible-window paint, hit-testing, keyboard/mouse, scrollbars, theming, events.

---

## 1. Virtual node store

```pascal
type
  PTyTreeNode = ^TTyTreeNode;
  TTyNodeState = (nsInitialized, nsHasChildren, nsExpanded, nsVisible, nsSelected,
                  nsHeightMeasured, nsDeleting, nsClearing);
  TTyNodeStates = set of TTyNodeState;
  TTyNodeInitState = (ivsHasChildren, ivsExpanded, ivsSelected, ivsReInit);   // OnInitNode return channel
  TTyNodeInitStates = set of TTyNodeInitState;

  TTyTreeNode = record
    Index, ChildCount: Cardinal;     // position within parent; number of (materialized) children
    NodeHeight: Word;                // pixels
    States: TTyNodeStates;
    TotalCount: Cardinal;            // self + all descendants (count)
    TotalHeight: Cardinal;          // pixels of self + all EXPANDED/visible descendants
    Parent, PrevSibling, NextSibling, FirstChild, LastChild: PTyTreeNode;  // MUST stay at the tail
    Data: record end;                // PLACEHOLDER — inlined user blob (NodeDataSize bytes) follows
  end;
```

- **`record`, not `class`** — no vtable/refcount; `AllocMem(TreeNodeSize + NodeDataSize)` per node, one contiguous block (struct + inlined data). `TreeNodeSize = (SizeOf(TTyTreeNode) + 7) and not 7`.
- A hidden **root** (`FRoot: PTyTreeNode`) whose `ChildCount` is `RootNodeCount` and whose `Parent` points back at the control (cast). The root is never painted, never carries data.
- **`GetNodeData(Node): Pointer`** returns `PByte(@Node^.Data)` (after any internal area). Valid only when `NodeDataSize > 0`; returns nil for nil/root. The app casts to its `P<Rec>` and reads/writes the inlined blob. The app **must release managed fields (string/interface/object) in `OnFreeNode`** (the tree only frees raw bytes; `Finalize(Data^)` or per-field clear).

### Three-stage lazy lifecycle (the heart)
1. **Skeleton** — `SetChildCount(node, N)` / `MakeNewNode` allocate N blank child blocks, wiring only `Index` + the four links; `States := [nsVisible]`. **No app event.** `RootNodeCount := 1_000_000` ⇒ ~1M small allocations, zero app calls.
2. **Init node** — `InitNode(node)` fires `OnInitNode(Sender, Parent, Node, var InitStates)` **once** (guarded by `nsInitialized`), the first time the node is navigated-to / painted. The app sets `ivsHasChildren`/`ivsExpanded` and populates the data blob. `InitNode` translates the `ivs*` flags into permanent `ns*` states.
3. **Init children** — `InitChildren(node)` fires `OnInitChildren(Sender, Node, var ChildCount)` **once** (gated by `nsHasChildren`), the first time the node is expanded. Setting `ChildCount` allocates the children (which then init lazily as they scroll in).
- **`nsHasChildren` is decoupled from actual children**: a node draws the `[+]` button with `FirstChild = nil`/`ChildCount = 0`. This is the single trick that makes deep/infinite trees free.

### Navigation iterators (init-on-touch, skip collapsed)
`GetFirst`, `GetNext` (depth-first pre-order, materializes on touch), `GetFirstChild`, `GetLastChild`, `GetNextSibling`, `GetPrevSibling`, `GetParent`, `GetNodeLevel`, and the **screen-order** workhorses `GetFirstVisible`/`GetNextVisible`/`GetPreviousVisible` (descend into children only when `nsExpanded`; step over collapsed subtrees in O(1); init only nodes landed on; honor `nsVisible`). `*NoInit` variants for read-only walks (paint/scroll use these to avoid side-effects).

---

## 2. Scroll engine (the performance core)

- **`TotalHeight` maintained incrementally.** When a node is inserted/deleted/expanded/collapsed/height-changed, `AdjustTotalHeight(node, delta)` walks only from that node up to the root applying the delta. The root's `TotalHeight` is the whole virtual image height. **Never rescan the tree.**
- **Vertical range** `FRangeY := FRoot.TotalHeight` drives the vertical `TTyScrollBar` (max = FRangeY, page = ClientHeight, pos = -FOffsetY). `FOffsetY ≤ 0`.
- **`GetNodeAt(Y): (node, nodeTop)`** maps a pixel offset to the covering node + its absolute top, in **O(depth + local scan)**, NOT O(total):
  - Walk visible nodes from a starting point, but **skip whole collapsed/invisible subtrees by their `TotalHeight`** (if `Y >= runningTop + node.TotalHeight` and the node is collapsed, advance `runningTop` by the node's own `NodeHeight` only; if expanded, the subtree's `TotalHeight` is the span).
  - **Position cache** `FPositionCache: array of (Node, AbsoluteTop)` — one entry every `CACHE_STEP` (≈2000) *visible* nodes, built in one pass, binary-searchable. `GetNodeAt` binary-searches the cache for the nearest mark at/below `Y`, then linear-scans ≤CACHE_STEP visible nodes. This bounds the "flat 1M siblings" case to O(log + 2000). The cache is invalidated/rebuilt lazily (a `tsValidating`-style dirty flag) on structure/expand/collapse/height change. **This binary-search-over-marks + incremental TotalHeight is the defining performance feature and the hardest part — it gets dedicated correctness tests.**
- **Paint** uses `GetNodeAt(Window.Top)` for the first row (positioned by the sub-row remainder `Window.Top - nodeTop`), then `GetNextVisibleNoInit` until the canvas passes `Window.Bottom`. So paint cost = visible rows, independent of total node count.
- **Horizontal:** `FRangeX` = max measured node content width; `FOffsetX` shifts the window; the horizontal `TTyScrollBar` is shown only when content exceeds the client width. (No position cache — width isn't a prefix-sum problem.)

**The performance invariant (asserted by tests):** with N total nodes and V visible rows, paint and `GetNodeAt` cost depend on V (and tree depth / cache step), not N. A test builds a large lazy tree and asserts `GetNodeAt` touches a bounded number of nodes regardless of N.

---

## 3. The control (paint + interaction)

`TTyTreeView = class(TTyCustomControl)`, `GetStyleTypeKey = 'TyTreeView'`, default size ~200×160.

**RenderTo (visible window):** `DrawFrame` (TyTreeView surface/border), clip to the content area (minus scrollbars), then per visible row (from `GetNodeAt`): node background (selected/hot/normal from `TyTreeNode` states), tree lines (`toShowTreeLines`, computed per indent slot from sibling presence), the expand/collapse button (`toShowButtons`, only when `nsHasChildren`; a themed chevron/▸▾ glyph via `DrawGlyph`), state/normal image (`Images` + `OnGetImageIndex`), the caption text (`OnGetText`, ellipsis-shortened, `OnPaintText` hook). Indent = level × `Indent` px. `toShowRoot` toggles whether top-level nodes get an indent slot for buttons. `EmptyListMessage` when the tree is empty. All device metrics via `P.Scale`.

**Hit-testing** `GetNodeAt(point) + part`: returns the node + which part (`hpButton`/`hpImage`/`hpLabel`/`hpIndent`/`hpNowhere`) by reproducing the paint order's x-accumulation.

**Mouse:** click a row → select + focus (fires `OnChange`/`OnFocusChanged`); click the button (or, with `toToggleOnDblClick`, double-click the row) → toggle `Expanded` (fires `OnExpanding`/`OnExpanded`/`OnCollapsing`/`OnCollapsed`, vetoable); wheel scrolls; `toHotTrack` tracks the hovered node.

**Keyboard:** ↑/↓ move the focused node (visible-order), ←/→ collapse/expand (or move to parent/first child), Home/End first/last visible, PageUp/PageDown by a viewport, `+`/`-`/`*` expand/collapse/FullExpand-of-node, Enter activates. (Navigation + expand/collapse are always enabled in ③a; read-only/editing concerns are deferred.)

**Scrollbars:** two embedded `TTyScrollBar` (vertical over `FRangeY`, horizontal over `FRangeX`), shown/hidden by need, wired to `FOffsetY`/`FOffsetX`; the content rect insets for whichever bars are visible. (`AnimationsEnabled := False` on them, like ListBox, so content scroll is instant.)

**Theme typeKeys (token-driven, byte-synced across all 6 themes):**
- `TyTreeView` — the control surface (bg `var(--input-bg)`, border, radius, padding, font).
- `TyTreeNode` — a row: base (`background: none; color: var(--on-surface)`) + `:hover` (`--surface-hover`) + `:selected` (`--accent` bg / `--on-accent` text; unfocused = `--surface-active`) + `:disabled` (`--muted`).
- Tree-line color + the expand-button glyph color come from tokens (reuse `--border` / `--muted` / the node text color); no hard-coded colors.

---

## 4. ③a API surface

**Published properties:** `RootNodeCount: Cardinal`, `NodeDataSize: Integer` (-1 until set), `DefaultNodeHeight: Integer` (≈18), `Indent: Integer` (≈16), `Images: TImageList`, `TreeOptions` (a slim object exposing `toShowButtons`/`toShowTreeLines`/`toShowRoot`/`toToggleOnDblClick`/`toHotTrack` as booleans for v1), `EmptyListMessage: string`, re-published `Align`/`Anchors`/`Font`/`StyleClass`/`Controller`/`TabStop`.

**Public (not published) state:** `FocusedNode: PTyTreeNode`, `Selected[Node]: Boolean`, `Expanded[Node]: Boolean`, `ChildCount[Node]: Cardinal`, `RootNode: PTyTreeNode`, `TotalNodeCount`/`VisibleCount`.

**Events:** `OnInitNode`, `OnInitChildren`, `OnFreeNode`, `OnGetText`, `OnGetImageIndex`, `OnExpanding`, `OnExpanded`, `OnCollapsing`, `OnCollapsed`, `OnChange` (selection), `OnFocusChanged`, `OnNodeClick`, `OnNodeDblClick`, `OnPaintText`. (Standard mouse/key events inherited from `TTyCustomControl`.)

**Methods:** `GetNodeData(Node): Pointer`; `AddChild(Parent): PTyTreeNode`; `DeleteNode(Node)`; `Clear`; `BeginUpdate`/`EndUpdate`; `FullExpand`/`FullCollapse` (optionally of a subtree); `ScrollIntoView(Node)`; `GetNodeLevel(Node): Integer`; the navigation iterators (§1).

---

## 5. Testing strategy

- **Node store + scroll engine — headless (no window handle needed):** a test attaches `OnInitChildren`/`OnInitNode` handlers, sets `RootNodeCount`, expands nodes, and asserts: skeleton allocation fires no init; `OnInitNode` fires once per node on first touch; `nsHasChildren` draws-as-expandable without children; `OnInitChildren` fires once on expand; `GetNodeLevel`/iterator order (depth-first + visible-order) are correct; `TotalCount`/`TotalHeight` correct after expand/collapse/delete; `GetNodeAt(Y)` returns the right node+top; `AddChild`/`DeleteNode`/`Clear` (with `OnFreeNode` firing) maintain invariants.
- **Performance invariant test:** build a deep + a flat-large lazy tree; assert `GetNodeAt` and a paint pass touch a bounded count of nodes independent of total N (e.g. instrument an init/visit counter), proving virtualization.
- **Render pixel tests:** indent per level, the expand button present on `nsHasChildren`, a selected row painted accent, tree lines present under `toShowTreeLines`.
- **Events RTTI guard;** theme typeKeys byte-synced (`gen-defaulttheme.ps1` + `gen-builtinthemes.ps1`) + golden re-bootstrap + `GGRID` extension.
- **Memory:** a test that builds + clears a tree and (where detectable) confirms `OnFreeNode` fires for every node, so app data can be released.

PPI pinned to 96 in pixel tests; a dedicated `TTyStyleController` + inline `LoadThemeCss` for known colors.

---

## 6. Design-time + demo

Register `TTyTreeView` on the palette + a glyph (4-way drift-guard). Demo: a `TTyTreeView` with a small `OnInitChildren`/`OnInitNode`/`OnGetText` handler set producing a few lazy levels (the canonical demo), placed in the demo form.

---

## 7. Key decisions (my judgment, "按你想法来")

1. **Faithful raw-record store** (`NodeDataSize` + `GetNodeData: Pointer` + `OnFreeNode`), VTV-API-compatible — chosen over a safer TObject-per-node model, per the "model on VirtualTreeView" intent (the cost: managed fields need `Finalize` in `OnFreeNode`, documented).
2. **One class `TTyTreeView`** (string-based) for ③a, not the VTV Base/String split — simpler; the multi-column/checkbox layers (③b/③c) extend it, not a new class.
3. **Position cache IS in ③a** — it's the defining performance feature the user wants; deferring it would make ③a "weak." It's the hardest part and gets dedicated tests.
4. **Embedded `TTyScrollBar`** (themed), not native LCL scrollbars — consistent with ListBox/Memo.
5. **Single selection + focused node only** in ③a; multi-select is ③c.

## 8. Deferred to ③b / ③c / later (confirm none dropped silently)

③b: multi-column + `Header`/`Columns` + column resize + header-click sort + `OnCompareNodes`. ③c: checkboxes (`toCheckSupport` + per-node `CheckType`/`CheckState` + tri-state) + multi-select (Ctrl/Shift) + full-row-select. Later/never: inline editing, drag-drop/OLE, animation, incremental search, variable node height, owner-draw-only tree (`OnBeforeCellPaint`/`OnAfterCellPaint` cover custom draw), stream persistence, fixed columns, hints polish.

## 9. Phasing (informs the plan, one spec)

Build order within ③a: **(a) node store + lazy lifecycle** (record, AllocMem, SetChildCount, InitNode/InitChildren, iterators, GetNodeData) — pure-ish, exhaustively headless-tested → **(b) scroll engine** (incremental TotalHeight, FRangeY, GetNodeAt + position cache) — headless-tested incl. the perf invariant → **(c) the control** (RenderTo visible-window, hit-test, mouse/keyboard, embedded scrollbars) → **(d) theme + events + design-time + demo + finish**.
