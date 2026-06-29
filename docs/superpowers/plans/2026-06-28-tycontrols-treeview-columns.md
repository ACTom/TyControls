# TTyTreeView ③b — Multi-Column + Header + Sort — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development — fresh subagent per task, spec-review + quality-review between tasks. Steps use `- [ ]`.

**Goal:** Extend the merged `TTyTreeView` with a VirtualTreeView-class multi-column layer — a tree-drawn `Header` of resizable / reorderable / sortable `Columns`, a main column carrying the tree chrome, per-column paint + hit-test, `OnCompareNodes` linked-list merge sort, and column auto-size/spring — while preserving byte-for-byte ③a behavior when there are zero columns.

**Architecture:** New `tyControls.TreeView.Columns` unit holds the pure column model (`TTyTreeColumn`/`TTyTreeColumns` + position↔index map + layout/hit math) and `TTyTreeHeader`; `tyControls.TreeView.pas` gains `Header`/`Columns` published sub-objects, a multi-column branch in `RenderTo`/`GetNodeAtPoint`/`MouseDown` (guarded by `Columns.Count > 0`), and the `Sort`/`SortTree` engine. All visual values theme-token-driven; logical-unit column model converted to device only at paint/hit boundaries (reuse the ③a HiDPI discipline).

**Tech stack:** FPC/Lazarus, BGRABitmap, TTyPainter, theme system v2 (.tycss), fpcunit. Reference port: `…\VirtualTreeViewV5`. Spec: `docs/superpowers/specs/2026-06-28-tycontrols-treeview-columns-design.md`.

**Baseline:** `main`/this branch builds at **1217 run / 0 fail / 11 pre-existing env errors**. Conventions every task: `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → failures 0; commit ending `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; never push.

**Non-negotiable invariants to keep green every task:** ③a's `RootNode^.TotalHeight == ΣvisibleHeights` height invariant; all existing ③a TreeView tests; the theme byte-sync (`TestBuiltinMatchesLightTheme`) + golden tests; the events RTTI guard; the palette drift-guard.

---

## Phase A — pure column model (`tyControls.TreeView.Columns`)

### Task A1: column types + the position↔index model

**Files:** Create `source/tyControls.TreeView.Columns.pas`; add to `tycontrols.lpk` (`<Files>` + compile); Test `tests/test.treeview.columns.pas` (+ register in the test project).

`TTyTreeColumn = class(TCollectionItem)` with published `Width`(100)/`MinWidth`(10)/`MaxWidth`(10000)/`Position`/`Alignment`(taLeftJustify)/`CaptionAlignment`(taLeftJustify)/`Text`/`ImageIndex`(-1)/`Options`(`[coVisible,coResizable,coAllowClick,coDraggable]`)/`Tag`; public read-only `Left`; internal `FLeft`. `Width` setter clamps `[MinWidth,MaxWidth]` then notifies the owner. `Position` setter calls `Owner.AdjustPosition(Self, value)`.
`TTyTreeColumns = class(TCollection)` owns `FPositionToIndex: array of Integer` + a back-ref to the header. On `Add`/`Delete`, rebuild/patch `FPositionToIndex` (append new at end position; on delete, remove its slot + shift). `function ColumnByPosition(APos): TTyTreeColumn`.

- [ ] **Step 1: failing tests** — add columns A,B,C; assert default `Position` = 0,1,2; `ColumnByPosition(1)` returns B; `Width` setter clamps below `MinWidth`/above `MaxWidth`; deleting B leaves A,C with positions 0,1 and `FPositionToIndex` consistent.
- [ ] **Step 2:** run → fail (unit missing).
- [ ] **Step 3:** implement the types + `FPositionToIndex` maintenance + clamping.
- [ ] **Step 4:** run → pass.
- [ ] **Step 5:** commit `feat(treeview): column model types + position↔index map`.

### Task A2: `UpdatePositions` / `TotalWidth` / `AdjustPosition` (reorder)

**Files:** Modify `tyControls.TreeView.Columns.pas`; Test same.

`procedure UpdatePositions` — sweep visible columns in position order, `col.FLeft := running; Inc(running, col.Width)`. `function TotalWidth: Integer` = running after sweep (visible only). `procedure AdjustPosition(col; newPos)` — memmove `FPositionToIndex` so `col` moves to `newPos`, others shift; then `UpdatePositions`.

- [ ] **Step 1: failing tests** — widths A=100,B=50,C=80 → after `UpdatePositions` `FLeft` = 0,100,150 and `TotalWidth`=230; hide B (`coVisible` off) → A,C `FLeft`=0,100, `TotalWidth`=180; `AdjustPosition(C, 0)` → visual order C,A,B and `FLeft` recomputed.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): UpdatePositions/TotalWidth + reorder (AdjustPosition)`.

### Task A3: hit math — `ColumnFromPosition` + `DetermineSplitterIndex`

**Files:** Modify `tyControls.TreeView.Columns.pas`; Test same.

`function ColumnFromPosition(X, AScrollOffset: Integer): Integer` — left-to-right accumulate visible widths (start at `-AScrollOffset`); return the column **Index** whose span contains X, else `NoColumn(-1)`. `function DetermineSplitterIndex(X, AScrollOffset, ATolLeft=3, ATolRight=5): Integer` — reverse-iterate visible columns; if X within `[right-tolLeft, right+tolRight]` of a `coResizable` column's right edge return that Index, else `NoColumn`.

- [ ] **Step 1: failing tests** — A=100,B=50,C=80, scroll 0: `ColumnFromPosition(120)`→B's index, `ColumnFromPosition(300)`→NoColumn; scroll 40: `ColumnFromPosition(70)`→B; `DetermineSplitterIndex(101)`→A (right edge 100 ±tol), `DetermineSplitterIndex(125)`→NoColumn.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): column hit math (ColumnFromPosition + splitter index)`.

### Task A4: auto-size + spring math (pure)

**Files:** Modify `tyControls.TreeView.Columns.pas`; Test same.

`procedure ApplyAutoSize(AClientWidth, AAutoSizeIndex)` — set that column's `Width` so `TotalWidth = AClientWidth` (clamp to its Min/Max; floor at MinWidth). `procedure DistributeSpring(ADeltaWidth)` — share `ADeltaWidth` across `coAutoSpring` visible columns proportionally with an integral bonus-pixel remainder so widths stay whole and sum is exact.

- [ ] **Step 1: failing tests** — A=100,B=50,C=80, client=300, autosize=B → B becomes 120 (`TotalWidth`=300); client=150 with B.MinWidth=40 → B clamps to 40; spring: A,C `coAutoSpring`, delta −30 → A,C shrink by 15 each (sum exact), no fractional drift over repeated calls.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): column auto-size + spring distribution`.

---

## Phase B — header object + wiring into TTyTreeView

### Task B1: `TTyTreeHeader` + published `Header`/`Columns`

**Files:** Modify `tyControls.TreeView.Columns.pas` (add `TTyTreeHeader`); Modify `tyControls.TreeView.pas` (uses + `FHeader` field + published `Header`); Test `tests/test.treeview.columns.pas`.

`TTyTreeHeader = class(TPersistent)` owns `FColumns`, publishes `Height`(22)/`Columns`/`MainColumn`(0)/`SortColumn`(-1)/`SortDirection`(sdAscending)/`AutoSizeIndex`(-1)/`Images`/`Options`(`[hoVisible,hoColumnResize,hoShowSortGlyphs,hoHeaderClickAutoSort,hoDrag]`). A `FOnChange`/`Changed` notify wired to the tree → `Header.Changed` calls the tree's `HeaderChanged` (recompute `FRangeX` from `TotalWidth`, re-inset `ContentRect`, `InvalidateTreeLayout`). `MainColumn` setter clamps `[NoColumn, Count-1]`. Tree gets `property Header: TTyTreeHeader read FHeader write SetHeader` (assign-through). Construct `FHeader` in the tree ctor, free in dtor.

- [ ] **Step 1: failing tests** — tree has a `Header` with empty `Columns`; add 3 columns via `Header.Columns.Add`; `Header.Columns.Count`=3; `MainColumn:=5` clamps to 2; setting a column `Width` fires `HeaderChanged` (observe via `FRangeX` = `TotalWidth`).
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass (existing ③a tests unaffected — 0-column default).
- [ ] **Step 5:** commit `feat(treeview): TTyTreeHeader + published Header/Columns wired to layout`.

### Task B2: `ContentRect`/`FRangeX` honor the header (0-column compat preserved)

**Files:** Modify `tyControls.TreeView.pas` (`ContentRect`, `UpdateScrollBars`/`HeaderChanged`); Test `tests/test.treeview.pas`.

When `Header.Options` has `hoVisible` AND `Columns.Count > 0`: `ContentRect.Top += P.Scale(Header.Height)` (device); `FRangeX := Header.Columns.TotalWidth` (logical→ the H-bar uses it as today). When `Columns.Count = 0`: unchanged ③a (`ContentRect` no header inset; `FRangeX` = measured-text accumulation).

- [ ] **Step 1: failing tests** — with 0 columns `ContentRect.Top` = padding only (③a); add columns + `hoVisible` → `ContentRect.Top` = padding + `Scale(Header.Height)`; `FRangeX` = `TotalWidth`; hide header (`hoVisible` off) → no top inset.
- [ ] **Step 2:** fail. **Step 3:** implement the guarded branch. **Step 4:** pass + all ③a tests green.
- [ ] **Step 5:** commit `feat(treeview): ContentRect header inset + FRangeX from column total (0-col = ③a)`.

---

## Phase C — multi-column paint

### Task C1: per-column node paint (main-column chrome + flat cells)

**Files:** Modify `tyControls.TreeView.pas` (`RenderTo` per-row block); Test `tests/test.treeview.pas` (pixel).

Replace the single caption block with: if `Columns.Count = 0` run the ③a path verbatim; else compute the visible column layout (`FLeft − FOffsetX`), inner-loop columns overlapping `CR`, clip each cell, draw main-column chrome (indent/lines/button/image at the main column's cell-left) only when `colIndex = MainColumn`, else flat; per-cell caption via `OnGetTextWithType`/`OnGetText` (main fallback), aligned by `Column.Alignment`, ellipsis, within `[cellLeft+margin, cellRight−margin]`. Pass the real column index to `OnGetImageIndex`/`OnPaintText`. Publish `OnGetTextWithType` (the already-declared field).

- [ ] **Step 1: failing tests** — 3 columns (main=0), inline theme; render; assert: column-1 caption ink starts within column 1's x-span (right of column 0); right-aligned column-2 text sits in the cell's right half; the expand button/indent appear ONLY in column 0; 0-column render identical to ③a (re-run an existing ③a pixel test).
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): per-column node paint — main-column chrome + aligned flat cells`.

### Task C2: header band paint (captions + sort glyph + hover)

**Files:** Modify `tyControls.TreeView.pas` (`RenderTo` header band); Test `tests/test.treeview.pas` (pixel).

Before/above the node area, when `hoVisible` + columns: fill `TyTreeHeader` bg; per visible column draw a `TyTreeHeaderSection` cell at `FLeft − FOffsetX` (caption by `CaptionAlignment`, optional `ImageIndex` glyph, `:hover` when `hoHotTrack` and hovered, divider line `var(--border)`); in `SortColumn` when `hoShowSortGlyphs` draw an up/down triangle (token color) reserving caption space. Header scrolls horizontally with `FOffsetX` so it aligns with the cells. (typeKeys land in Phase G but use an inline theme here.)

- [ ] **Step 1: failing tests** — render header; assert header band occupies the top `Scale(Height)` px; column captions paint within their x-spans; a sort triangle appears in `SortColumn` and NOT in others; horizontal scroll shifts header captions by the same delta as the cells.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): header band paint — captions + sort glyph + divider`.

---

## Phase D — header hit-test + resize + reorder

### Task D1: hit-test surface (header parts + column out-param)

**Files:** Modify `tyControls.TreeView.pas` (`TTyTreeHitPart`, `GetNodeAtPoint` overload, new `GetHeaderHitAt`); Test `tests/test.treeview.pas`.

Extend `TTyTreeHitPart` with `hpHeaderSection,hpHeaderDivider`. Add `GetNodeAtPoint(X,Y; out APart; out AColumn)` (column via `ColumnFromPosition` using `FOffsetX`; keep the ③a 2-out overload delegating with a discarded column). Add `function GetHeaderHitAt(X,Y; out APart; out AColumn): Boolean` — true when `Y < Scale(Header.Height)` and `hoVisible`; `DetermineSplitterIndex` → `hpHeaderDivider`, else `hpHeaderSection` + `ColumnFromPosition`.

- [ ] **Step 1: failing tests** — 3 columns; a point in column 2's body row → node + column 2 + `hpLabel`; a header-body point → `GetHeaderHitAt` true, `hpHeaderSection` + right column; a point on a column's right border in the header → `hpHeaderDivider` + that column.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): header/column hit-test (parts + column index)`.

### Task D2: column resize (drag a divider)

**Files:** Modify `tyControls.TreeView.pas` (`MouseDown`/`MouseMove`/`MouseUp` header branch); Test `tests/test.treeview.pas` (via the access helper).

MouseDown when `GetHeaderHitAt` → `hpHeaderDivider`: record `FResizeCol` + `FResizeStartLeft := col.FLeft`, capture. MouseMove while resizing: `col.Width := MulDiv(X,96,PPI) + FOffsetX_logical − FResizeStartLeft` (clamped via setter); `UpdatePositions`; `Invalidate`; fire `OnColumnResized(col)`. MouseUp: release + `OnColumnResized` final. (`MouseMove` also sets the resize cursor when hovering a divider.)

- [ ] **Step 1: failing tests** — simulate MouseDown on column-0 divider, MouseMove +30px, MouseUp → column 0 `Width` increased by ~30 (logical); clamps at `MaxWidth`; `OnColumnResized` fired.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): column resize by dragging the header divider`.

### Task D3: column drag-reorder (ghost + drop-mark)

**Files:** Modify `tyControls.TreeView.pas` (header MouseDown/Move/Up + a drag-overlay paint in `RenderTo`); Test `tests/test.treeview.pas`.

MouseDown on `hpHeaderSection` with `hoDrag`+`coDraggable` → `FDragCol` + `FDragPending` + start X. MouseMove past threshold → `FDragging`: compute the target position from `ColumnFromPosition`; paint a translucent ghost of the dragged header cell at the cursor + a drop-mark caret at the target boundary (in `RenderTo`'s header band). MouseUp: if target ≠ source `Columns.AdjustPosition(FDragCol, targetPos)` + `UpdatePositions` + `OnColumnReorder(old,new)`; if no movement, fall through to header-click (Phase E). Clear drag state.

- [ ] **Step 1: failing tests** — simulate a header drag of column 0 to position 2 → visual order becomes B,C,A (positions) and `FLeft` recomputed; a same-spot press+release does NOT reorder (so click-sort still works).
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): header drag-to-reorder columns (ghost + drop-mark)`.

### Task D4: auto-size on resize + `Resize`

**Files:** Modify `tyControls.TreeView.pas` (`Resize`, `HeaderChanged`); Test `tests/test.treeview.pas`.

When `hoAutoResize` + `AutoSizeIndex ≥ 0`: on `Resize` and after a non-auto column resize, call `Columns.ApplyAutoSize(ContentWidthLogical, AutoSizeIndex)`; `coAutoSpring` columns use `DistributeSpring` when the user resizes a sibling. Recompute `FRangeX`.

- [ ] **Step 1: failing tests** — `hoAutoResize`, `AutoSizeIndex=1`, content width 300, columns 100/?/80 → column 1 = 120; resize the control wider by 50 → column 1 grows by 50; spring columns share a manual delta.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): column auto-size on resize + spring`.

---

## Phase E — sort

### Task E1: sibling linked-list merge sort (pure-ish) + `OnCompareNodes`

**Files:** Modify `tyControls.TreeView.pas` (`Sort`, the merge helper, `OnCompareNodes`); Test `tests/test.treeview.pas`.

`OnCompareNodes(Sender; Node1,Node2; Column; var Result)`. `procedure Sort(Node; Column; ADir; DoInit)`: if `DoInit` ensure children initialized (`InitChildren`+`InitNode` each); if `ChildCount>1` merge-sort the `FirstChild→NextSibling` list comparing `DoCompare(a,b,Column)` (ascending) or its negation (descending); then sweep to re-link `PrevSibling`, re-stamp `Index:=0..`, set `Parent.FirstChild/LastChild`. Pointers stable.

- [ ] **Step 1: failing tests** — build a parent with children whose data sorts to a known order; `OnCompareNodes` compares an app key; `Sort(parent, 0, sdAscending, True)` → sibling order ascending, `Index` re-stamped 0..n-1, `PrevSibling`/`LastChild` correct; descending reverses; a single-child / zero-child node is a no-op; **the ③a height invariant still holds** after sort.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): OnCompareNodes + sibling-list merge Sort(node,column,dir)`.

### Task E2: `SortTree` (recursive, lazy-aware) + cache rebuild

**Files:** Modify `tyControls.TreeView.pas` (`SortTree`); Test `tests/test.treeview.pas`.

`procedure SortTree(Column; ADir)`: `Sort(FRoot, …)`, then recurse into each **initialized** child, skipping **collapsed** subtrees; wrap in begin/end-update; after: `ValidateCache` (visible order changed) + `Invalidate`. Cross-check `GetNodeAt` after sort matches a fresh visible-order walk.

- [ ] **Step 1: failing tests** — a 3-level tree; `SortTree(0, sdAscending)` → every initialized level sorted; a collapsed branch unsorted until expanded (if it inits on expand) ; after sort `GetNodeAt(y)` equals the linear visible walk for sampled y; height invariant holds.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): SortTree recursive lazy-aware + cache rebuild`.

### Task E3: header-click sort wiring + sort glyph state

**Files:** Modify `tyControls.TreeView.pas` (header MouseUp click → sort; `SortColumn`/`SortDirection` setters); Test `tests/test.treeview.pas`.

On a header-section click (no drag/resize) with `hoHeaderClickAutoSort`+`coAllowClick`: if clicked = `SortColumn` toggle `SortDirection` else set `SortColumn` + sdAscending → `SortTree(SortColumn, SortDirection)`; fire `OnHeaderClick(Column)`. `SortColumn`/`SortDirection` setters also call `SortTree` when auto-sort on. The Phase C2 glyph already reads `SortColumn`/`SortDirection`.

- [ ] **Step 1: failing tests** — simulate a header click on column 1 → `SortColumn`=1, `SortDirection`=asc, `OnCompareNodes` fired with column 1, order sorted; click again → desc; click column 0 → `SortColumn`=0 asc.
- [ ] **Step 2:** fail. **Step 3:** implement. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(treeview): header-click sort (toggle direction) + glyph`.

---

## Phase F — theme, events, design-time, demo, finish

### Task F1: theme typeKeys `TyTreeHeader` / `TyTreeHeaderSection` + goldens

**Files:** `themes/*.tycss` (all 6), `tyControls.DefaultTheme.pas` + `tyControls.BuiltinThemeData.pas` (generated), `tests/test.themes.pas` (`GGRID`), `tests/golden/*`, `tests/test.defaulttheme.pas`.

Add the two typeKeys (spec §4) to every theme (green concrete-value), run `gen-defaulttheme.ps1` + `gen-builtinthemes.ps1`, extend `GGRID` (+2 bound), re-bootstrap goldens (delete `{light,dark,showcase}` + run twice; purely additive), add `AssertBg('TyTreeHeader', [])` to `TestBuiltinCoversAllTypeKeys`. Switch the Phase C2 inline-theme header paint to resolve the real typeKeys.

- [ ] **Steps:** add CSS → regenerate both mirrors → extend GGRID → re-bootstrap goldens (additive) → coverage assert → byte-sync + golden + dual-mode tests green. Commit `feat(treeview): TyTreeHeader/TyTreeHeaderSection typeKeys across all themes + goldens`.

### Task F2: events RTTI guard for the new events

**Files:** `tests/test.treeview.events.pas`.

Add the new published events to the guard: `OnGetTextWithType`, `OnCompareNodes`, `OnColumnResized`, `OnColumnReorder`, `OnHeaderClick` (match the actual published set). Commit `test(treeview): RTTI guard for column/sort events`.

### Task F3: design-time — stream `Header`/`Columns`; no new palette class

**Files:** `tyControls.TreeView.pas` (ensure `Header`/`Columns` stream; `TTyTreeColumns` registered for streaming if needed), Design.pas (verify the existing `TTyTreeView` registration covers the new sub-objects; add a `TTyTreeColumns`/`TTyTreeColumn` component-editor only if trivial). Confirm a `.lfm` with `Header.Columns` round-trips. No new icon (same class).

- [ ] **Steps:** verify LFM round-trip of a tree with 3 columns (a headless stream/unstream test or a demo .lfm load); `lazbuild tycontrols_dt.lpk` exit 0; palette drift-guard still passes. Commit `feat(treeview): stream Header/Columns at design time`.

### Task F4: demo — a multi-column sortable tree + finish/merge

**Files:** `examples/demo/mainform.lfm` + `mainform.pas`.

Add (or upgrade the existing `TyTree1`) a multi-column instance: 3 columns (Name/Size/Modified), `MainColumn=0`, `hoHeaderClickAutoSort`, an `OnGetTextWithType` returning per-column text, an `OnCompareNodes` comparing the active column. Keep it in the .lfm (designer) with code handlers. Build the demo.

- [ ] **Steps:** add the demo columns + handlers; `lazbuild examples/demo/demo.lpi` exit 0; full suite green; then **superpowers:finishing-a-development-branch** (verify tests → present options → merge per user). Final adversarial review (opus, whole column layer) before merge, mirroring ③a. Commit `example(demo): multi-column sortable TreeView`.

---

## Self-review notes
- **Spec coverage:** columns(A1-A4,B), header(B1), paint(C1-C2), hit/resize/reorder/autosize(D1-D4), sort(E1-E3), theme/events/dt/demo(F1-F4) — every spec §3 sub-section maps to a task.
- **Type consistency:** `FPositionToIndex`, `UpdatePositions`, `TotalWidth`, `ColumnFromPosition`, `DetermineSplitterIndex`, `AdjustPosition`, `Sort`/`SortTree`, `OnCompareNodes`, `hpHeaderSection/hpHeaderDivider`, `OnGetTextWithType` used consistently across tasks.
- **0-column compat** guarded in B2/C1 and asserted by re-running ③a tests each paint task.
- **HiDPI:** column model logical; convert at paint/hit (D2 resize, C1/C2 paint) — reuse ③a discipline; F-phase adds a PPI=144 column test if not already covered.
