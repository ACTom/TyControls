# TTyTreeView ③b — Multi-Column + Header + Sort — Design Spec

**Date:** 2026-06-28
**Sub-project:** ③b of the TreeView 专项 (③a virtual engine + single-column tree is DONE + merged to `main` `fb7e21a`; ③c checkboxes/multi-select follows as a separate spec).
**Branch:** `feat/treeview-columns` (off `main`).

## 1. Goal

Extend the merged `TTyTreeView` with a faithful (VirtualTreeView-class) **multi-column** layer: a `Header` of resizable, reorderable, sortable columns; a designated **main column** that carries the tree chrome (indent / expand buttons / tree lines / node image) while the other columns render as flat text cells. No new control class — `TTyTreeView` is extended in place (per ③a spec decision §7.2).

**Non-negotiable invariant:** with **zero columns** the control behaves byte-for-byte like ③a (single implicit column). Columns are opt-in.

## 2. Scope (user-approved 2026-06-28)

**IN:**
- **Columns** — `Width` / `MinWidth` / `MaxWidth` / `Position` / `Alignment` / `CaptionAlignment` / `Text` (caption) / `ImageIndex` / `Options` (`coVisible`, `coResizable`, `coAllowClick`, `coDraggable`, `coAutoSpring`).
- **Header** — painted by the tree (not a windowed control), above the node area: `Height`, `Columns`, `MainColumn`, `SortColumn`, `SortDirection`, `Options` (`hoVisible`, `hoColumnResize`, `hoShowSortGlyphs`, `hoHeaderClickAutoSort`, `hoDrag`, `hoAutoResize`, `hoHotTrack`).
- **Main column** — tree indent/buttons/lines/image only in `MainColumn`; other columns are flat cells.
- **Per-column paint** — inner column loop in `RenderTo`, per-cell clip + `OnGetText(Node, Column, …)` + per-column `Alignment`.
- **Column resize** — drag a column's right border (splitter zone), clamp `[MinWidth, MaxWidth]`.
- **Header-click sort** — toggle `SortColumn`/`SortDirection`, draw the sort glyph, run `SortTree` via `OnCompareNodes`.
- **Column drag-reorder** — drag a header cell to a new `Position` (drag visual + drop-mark), relink the position map.
- **Column auto-size / spring** — `hoAutoResize` + `AutoSizeIndex` (one column fills the remaining client width); `coAutoSpring` columns redistribute on resize.

**DEFERRED (③c / later):** fixed (frozen) columns (`coFixed`), header checkboxes, owner-draw header/cells, header-height drag, double-click auto-fit, animated resize, smart-resize (visible-only auto-fit), header right-click visibility popup, per-column tree-node checkboxes (③c), multi-select/full-row (③c), inline cell editing (later).

## 3. Architecture

### 3.1 Column model — `TTyTreeColumn` (TCollectionItem) + `TTyTreeColumns` (TCollection)

`TTyTreeColumns` is owned by `TTyTreeHeader`. Each `TTyTreeColumn` publishes:

| Property | Type | Default | Notes |
|---|---|---|---|
| `Width` | Integer | 100 | logical px; setter clamps to `[MinWidth, MaxWidth]`, calls `UpdatePositions` + invalidates |
| `MinWidth` | Integer | 10 | resize floor |
| `MaxWidth` | Integer | 10000 | resize ceiling |
| `Position` | Cardinal | sequential | **visual** slot (0 = leftmost). Writing it relinks `FPositionToIndex` (see below) |
| `Alignment` | TAlignment | taLeftJustify | cell content alignment |
| `CaptionAlignment` | TAlignment | taLeftJustify | header caption alignment |
| `Text` | string | '' | header caption |
| `ImageIndex` | Integer | -1 | header glyph (from `Header.Images`) |
| `Options` | `TTyTreeColumnOptions` | `[coVisible, coResizable, coAllowClick, coDraggable]` | flag set |
| `Tag` | NativeInt | 0 | app data |

Read-only public: `Left: Integer` (current on-screen left = absolute `FLeft − scroll`). Internal: `FLeft` (absolute left from column 0), set by `UpdatePositions`.

```pascal
TTyTreeColumnOption = (coVisible, coResizable, coAllowClick, coDraggable, coAutoSpring);
TTyTreeColumnOptions = set of TTyTreeColumnOption;
```

**Position ↔ Index indirection** (the heart of column ordering, copied from VTV):
- `Index` = `TCollectionItem.Index` (collection slot; changes on delete; never the visual order).
- `Position` = visual slot.
- `TTyTreeColumns.FPositionToIndex: array of Integer` maps `Position → Index`. Every paint/hit loop iterates `Position 0..Count-1`, looks up `Items[FPositionToIndex[pos]]`.
- `UpdatePositions`: sweep visible columns in position order, `col.FLeft := running; running += col.Width`. Single source of truth for cell left edges.
- `AdjustPosition(col, newPos)`: memmove `FPositionToIndex` so the slot map stays consistent (used by `Position` setter + drag-reorder).
- `TotalWidth`: `running` after the sweep = Σ visible column widths → drives `FRangeX`.
- `ColumnFromPosition(X, accountScroll): Integer`: O(n) left-to-right accumulation → column Index under X (the click→column map).

### 3.2 Header — `TTyTreeHeader` (TPersistent), `published Header`

Owned by `TTyTreeView`, **painted by the tree** in `RenderTo` (no separate window). Publishes:

| Property | Type | Default | Notes |
|---|---|---|---|
| `Height` | Integer | 22 | header band height (logical) |
| `Columns` | `TTyTreeColumns` | — | the collection |
| `MainColumn` | Integer | 0 | column carrying tree chrome; clamped `[0, Count-1]`, `NoColumn(-1)` when empty |
| `SortColumn` | Integer | -1 (`NoColumn`) | writing → `SortTree` when auto-sort active |
| `SortDirection` | `(sdAscending, sdDescending)` | sdAscending | writing → `SortTree` when auto-sort active |
| `AutoSizeIndex` | Integer | -1 | column inflated to fill remaining width (when `hoAutoResize`) |
| `Images` | TCustomImageList | nil | header glyph list |
| `Options` | `TTyTreeHeaderOptions` | `[hoVisible, hoColumnResize, hoShowSortGlyphs, hoHeaderClickAutoSort, hoDrag]` | flag set |

```pascal
TTyTreeHeaderOption = (hoVisible, hoColumnResize, hoShowSortGlyphs,
  hoHeaderClickAutoSort, hoDrag, hoAutoResize, hoHotTrack);
TTyTreeHeaderOptions = set of TTyTreeHeaderOption;
```

The tree calls `Header.Changed` → `InvalidateTreeLayout` + recompute `FRangeX`/`ContentRect` when the header mutates.

### 3.3 Main column

`MainColumn` is the only column that draws indent + expand button + tree lines + the node image (today's ③a chrome). All other columns draw a flat text cell. When `Columns.Count = 0`, the implicit single column behaves as `MainColumn` = the ③a path. `Header.Images` is the header-glyph list; the node image list stays `TTyTreeView.Images` and only renders in the main column (matching ③a).

### 3.4 Per-column paint (`RenderTo`)

`ContentRect` top edge is inset by `Header.Height` when `hoVisible`. The per-row loop's caption block (③a lines ~1769–1818) becomes an inner column loop:

```
ColumnsLayout := Header.Columns.LayoutVisible(contentLeft)   // [(colIndex, cellLeft, cellWidth)] in position order, scroll-shifted
for each (colIndex, cellLeft, cellWidth) where cellLeft < CR.Right and cellLeft+cellWidth > CR.Left:
  clip painter to [cellLeft, CR.top..bottom, cellLeft+cellWidth]
  if colIndex = MainColumn:
      draw indent + tree-lines + expand-button + node-image  (the ③a chrome, anchored at cellLeft)
      captionX := cellLeft + indent(+button+image slots)
  else:
      captionX := cellLeft + Margin
  text := OnGetText/OnGetTextWithType(Node, colIndex)
  DrawText(text) aligned by Column.Alignment, ellipsis, into [captionX .. cellLeft+cellWidth-Margin]
  OnPaintText(Node, colIndex)
FRangeX := Header.Columns.TotalWidth    // horizontal range = Σ widths (replaces the per-row text-width accumulation)
```

When `Columns.Count = 0`: skip the layout, run the existing single-column ③a path verbatim, keep `FRangeX` = measured-text accumulation (③a behavior).

### 3.5 Header paint + hit-test

**Paint** (top band, when `hoVisible`): fill `TyTreeHeader` background; for each visible column in position order draw a `TyTreeHeaderSection` cell (`FLeft − scroll, 0, width, Height`) with caption (`CaptionAlignment`), optional `ImageIndex` glyph, `:hover` state when `hoHotTrack`, and — in `SortColumn` when `hoShowSortGlyphs` — an up/down sort triangle (color from token). Header X is scrolled by `FOffsetX` exactly like the cells, so columns and headers stay aligned.

**Hit-test** (new, when click Y < `Header.Height`):
- **Splitter zone** (`DetermineSplitterIndex`): within ±3/5 px of a column's right edge AND `hoColumnResize` AND `coResizable` → `hpHeaderDivider` + the column to resize.
- **Section body**: else → `hpHeaderSection` + `ColumnFromPosition(X)`.

Extend `TTyTreeHitPart` with `hpHeaderSection`, `hpHeaderDivider`. Add a `Column: Integer` out-param to the node hit path (`GetNodeAtPoint`) and a header hit path (`GetHeaderHitAt(X,Y)`); `MouseDown` dispatches header vs node by Y.

### 3.6 Column resize tracking

MouseDown on `hpHeaderDivider` → record `FTrackColumn` + `FTrackStartLeft := col.FLeft` + capture. MouseMove → `col.Width := XlogicalScroll − FTrackStartLeft` (clamped by the setter); `UpdatePositions`; fire `OnColumnResized`/repaint. MouseUp → release. (Resize measured in logical px via the HiDPI conversion established in ③a — `MulDiv(deviceX, 96, PPI)` where the column model is logical.)

### 3.7 Column drag-reorder

MouseDown on `hpHeaderSection` with `hoDrag` + `coDraggable` → `FDragPending` + record start X. MouseMove past a small threshold → `FDragging`: draw a translucent drag ghost of the header cell following the cursor + a drop-mark (insertion caret) at the nearest column boundary computed from `ColumnFromPosition`. MouseUp → if dropped on a different slot, `Columns.AdjustPosition(col, newPosition)` (relink `FPositionToIndex`) + `UpdatePositions`, fire `OnColumnReorder`. Click (no drag) falls through to header-click sort.

### 3.8 Column auto-size / spring

- `hoAutoResize` + `AutoSizeIndex ≥ 0`: after any width/structural change, set the auto-size column's width so `TotalWidth = clientWidth` (clamped to its Min/Max); recompute on `Resize`.
- `coAutoSpring` columns: when the user resizes one column, the spring columns share the delta proportionally so the total tracks the client width. Spring redistribution uses a bonus-pixel remainder so widths stay integral.
- These are layout-only; they call `UpdatePositions` + repaint, never touch the vertical engine.

### 3.9 Sort

**Event:** `OnCompareNodes(Sender: TTyTreeView; Node1, Node2: PTyTreeNode; Column: Integer; var Result: Integer)` — app returns <0 / 0 / >0 in **natural** order (direction handled internally).

**`Sort(Node, Column, Direction, DoInit)`** — one parent level:
1. If `DoInit` and node not expanded-with-children: `InitChildren(Node)` (fires `OnInitChildren`) + init each direct child (`InitNode`) so lazy children exist before compare.
2. If `ChildCount > 1`: **merge sort on the `FirstChild`→`NextSibling` linked list** (top-down recursive merge, comparing via `OnCompareNodes(…, Column)`; ascending vs descending = which side wins ties — two merge variants, comparator always natural-order).
3. Sweep the sorted list: re-link `PrevSibling`, re-stamp `Index := 0,1,2,…`, set `Parent.FirstChild`/`LastChild`. Node **pointers are stable** (only links change).

**`SortTree(Column, Direction)`** — recursive: `Sort(FRoot, …)` then recurse into each **initialized** child, skipping **collapsed** subtrees (they sort lazily on expand if auto-sort). Wrap in a begin/end-update to suppress repaints; `ValidateCache` (positions changed) + `Invalidate` after.

**Trigger:** header click with `hoHeaderClickAutoSort` → if clicked column = `SortColumn` toggle direction, else set `SortColumn` + that column's default direction → `SortTree`. Also `SortColumn`/`SortDirection` setters call `SortTree` when auto-sort is on. `Tree.SortTree` is also callable manually.

**Index note:** the sort re-stamps `Index` for every sorted sibling, so the ③a "DeleteNode doesn't re-sequence Index" deferral does **not** affect ③b (sort overwrites Index in order; `OnCompareNodes` compares pointers, not Index). The DeleteNode O(n) re-sequence remains a ③c concern (Shift-click range-by-Index). `ValidateCache` is called after sort because visible order (and thus `GetNodeAt`) changed — the position cache must rebuild.

### 3.10 Events (new / changed)

- **Publish** `OnGetText` as the column-aware `OnGetTextWithType`-shaped event? **No** — keep ③a's `OnGetText(Node; var Text)` (single-/main-column compat, non-breaking) AND publish the already-declared `OnGetTextWithType(Node; Column; TextType; var CellText)`. Paint: if `OnGetTextWithType` assigned use it per column; else for the main/only column fall back to `OnGetText`.
- `OnGetImageIndex` / `OnPaintText` — already carry `Column`; pass the real column index (③a passed −1).
- New: `OnCompareNodes`, `OnColumnResized(Column)`, `OnColumnReorder(OldPos, NewPos)`, `OnHeaderClick(Column)`, `OnHeaderClicking(Column; var Allow)` (optional).

### 3.11 Hit-test surface

```pascal
TTyTreeHitPart = (hpNowhere, hpButton, hpImage, hpLabel, hpIndent,
  hpHeaderSection, hpHeaderDivider);
```
`GetNodeAtPoint(X, Y; out APart; out AColumn): PTyTreeNode` (overload preserving the ③a 2-out form for compat) and `GetHeaderHitAt(X, Y; out APart; out AColumn)`.

## 4. Theme typeKeys (byte-synced across all 6 themes + goldens)

- `TyTreeHeader` — the header band: `background: var(--surface-chrome)` (green concrete), border-bottom `var(--border)`, font.
- `TyTreeHeaderSection` — a column header cell: base (bg `none`, color `var(--on-surface)`), `:hover` (`var(--surface-hover)` when `hoHotTrack`), `:pressed`/`:selected` (the sort column — subtle `var(--surface-active)`), sort-glyph color from `var(--on-surface)`/`var(--muted)`. Divider line `var(--border)`.

Byte-sync procedure (identical to ③a D1): add the CSS to every `themes/*.tycss` (green concrete-value), run `gen-defaulttheme.ps1` + `gen-builtinthemes.ps1`, extend `GGRID` (+2 bound), re-bootstrap `tests/golden/{light,dark,showcase}.golden.txt` (delete + run twice; purely additive), add `AssertBg('TyTreeHeader', [])` to `TestBuiltinCoversAllTypeKeys`.

## 5. Testing strategy

**Pure functions (headless, deterministic) — the correctness spine:**
- Column layout: `UpdatePositions`/`TotalWidth`/`LayoutVisible` — given widths+positions+scroll, the cell rects. Reorder via `AdjustPosition`.
- `ColumnFromPosition(X)` — X → column, incl. scroll offset + boundaries.
- `DetermineSplitterIndex(X)` — ±3/5 px tolerance, reverse iteration.
- Auto-size/spring math — `AutoSizeIndex` fills remainder; spring redistribution sums to client width, integral.
- **Merge-sort on a sibling linked list** — a standalone function over a test list, asc/desc, stability, re-stamped `Index`, re-linked `PrevSibling`/`LastChild` (cross-check against a sorted array).

**Control-level (RenderTo pixel + hit-test):**
- Header renders captions + sort glyph in the sort column; columns paint at the right x; main-column chrome only in `MainColumn`.
- Per-column text alignment (left/right/center) lands in the right half of the cell.
- Hit-test: a click in column 2's body → that node + column 2; a click on a divider → `hpHeaderDivider` + the resizing column; a header-body click → `hpHeaderSection`.
- Resize: simulate divider drag → column Width changes + clamps.
- Reorder: simulate header drag → `Position` map relinks.
- Sort: header click → `SortTree` runs, `OnCompareNodes` fires with the column, sibling order changes, `Index` re-stamped, the **③a height invariant still holds** (`RootNode.TotalHeight == ΣvisibleHeights`), `GetNodeAt` cross-checks after sort.
- **Backward-compat:** 0 columns → every ③a test still passes; the ③a demo tree unchanged.
- **HiDPI:** a PPI=144 test for header height + column x + divider hit (reuse the ③a logical/device discipline).

## 6. Scope boundaries

| Sub-project | Contents |
|---|---|
| ③a (done) | virtual engine + single-column tree |
| **③b (this)** | columns (width/align/visible/resizable/draggable/spring), header (captions/resize/reorder/click-sort/auto-size), main-column chrome, per-column paint+hit, `OnCompareNodes` sort, header typeKeys, multi-column demo |
| ③c | checkboxes + tri-state + multi-select (Ctrl/Shift, needs DeleteNode Index re-sequence) + full-row-select |
| later/never | fixed columns, header checkboxes, owner-draw, inline editing, drag-drop/OLE, animation, header popup, smart/animated resize |

## 7. Key decisions

1. **Extend `TTyTreeView`, no new class** (③a §7.2). `Header`/`Columns` are sub-objects (`TPersistent`/`TCollection`), streamed as published sub-properties.
2. **Header is tree-drawn, not a windowed control** — simpler, avoids a child-window z-order/scroll-sync problem; consistent with ③a's all-custom-draw paint.
3. **0 columns = ③a** — the multi-column path is a branch guarded by `Columns.Count > 0`; the single-column path is untouched so no ③a regression.
4. **Logical-unit column model** — `Width`/`FLeft`/`Header.Height` are logical px; convert to device only at paint/hit boundaries (`P.Scale` / `MulDiv(…,96,PPI)`), reusing the ③a HiDPI discipline.
5. **Sort re-stamps `Index`** — so ③b needs no DeleteNode-Index fix; that stays a ③c task.
6. **Reorder is full drag** (user-approved) with a ghost + drop-mark; programmatic `Position` also works.
7. **`OnGetText` stays non-breaking** — column-aware text via the published `OnGetTextWithType`; `OnGetText` remains for the main/only column.
