# Phase 5 — Containers & Layout — Implementation Plan

> **For agentic workers:** implement in the numbered batches below. Each batch = one parallel Workflow (N agents each write ONLY their own new files: `source/tyControls.X.pas` + `tests/test.x.pas` + `docs/controls/x.md`, conflict-free, and RETURN integration data), then the controller SERIALLY integrates the shared files, regenerates icons, builds, tests, and makes ONE commit + an adversarial review. Same pattern as Phases 1–4.

**Goal:** 17 container / layout controls the ty-controls way (BGRABitmap custom-draw + `.tycss`, no native), on branch `feat/controls-expansion`.

**Architecture / reuse:**
- **Hosting containers subclass `TTyPanel`** (`= TTyCustomControl`, `csAcceptsControls`, streams child controls, `AdjustClientRect` for insets). Reuse the `'TyPanel'` typeKey unless a genuinely new surface is needed.
- **Titled groups subclass `TTyGroupBox`** (caption band + framed body). Reuse `'TyGroupBox'`.
- **Decorative / non-hosting controls subclass `TTyGraphicControl`** (no child hosting, cheap). Reuse `'TyPanel'`/`'TyLabel'` tokens or a tiny new one only where the surface is genuinely new.
- **Scrolling** reuses `TTyScrollBar` (embedded, as `TTyListBox`/`TTyMemo` already do) — content offset + a viewport.
- **Toolbar/band hosts** reuse `TTyToolBar` / its layout where possible.

**Cross-cutting per-control checklist (same as Phases 1–4):** control unit + pure-logic headless tests · reuse an existing typeKey (or add `.tycss` in all 6 themes + compiled + `GGRID` golden ONLY for a genuinely new surface) · palette registration in the **`TyControls Containers`** group + generated icon (genicons glyph + `array[0..N]` bound + `$classes`/`CClasses` drift-guards + regen `.lrs`) · `.lpk` unit `<Item>` entry (then `lazbuild tycontrols.lpk` regenerates `tycontrols.pas`) · `designtime/tyControls.Design.pas` uses + `RegisterComponents('TyControls Containers', […])` · `tools/genicons/genicons.lpr` + `scripts/gen-icons.ps1` `$classes` + `tests/test.paletteicons.pas` CClasses + `tests/tytests.lpr` uses · `docs/controls/<name>.md` + README index row · an `examples/containers/` showcase (new, grows per batch) · NO changelog per control (release-time only). i18n: containers have little/no runtime text (captions are user-set); design-time strings only where added.

**Design-surface note (like TTyPageControl/TTyTabSheet):** a hosting container that streams design-time children needs `GetChildren`/`SetChildOrder` + `csAcceptsControls`, and internal helper sub-controls (embedded scrollbars, grips) must be `csNoDesignVisible` so they don't leak into the IDE designer (see [[designer-internal-subcontrol-leak]]).

---

## Batch 1 — Decorative & paint leaves (simplest; establishes the phase)

| Control | Base | typeKey | Mechanics / notes |
|---|---|---|---|
| **TTyBevel** | `TTyGraphicControl` | reuse `TyPanel` | Decorative line or frame; `Shape` (bsBox/bsFrame/bsTopLine/bsBottomLine/bsLeftLine/bsRightLine/bsSpacer), `Style` (raised/lowered). Draw via `TTyPainter` stroke; **derive** the 3D highlight/shadow from the resolved `TyPanel` border/surface via `tyControls.ColorMath` lighten/darken — NO new token, no golden churn. |
| **TTyDivider** | `TTyGraphicControl` | reuse `TyLabel` | Labeled horizontal section divider: a caption + a rule to its right (or centred). Reuse [[ttylabel-theme-locked-draw-in-paint]] text-in-Paint; the rule colour from the resolved label style. `Alignment` for caption position. |
| **TTyPaintPanel** | `TTyPanel` | reuse `TyPanel` | Owner-draw surface: expose `OnPaintSurface(Sender; P: TTyPainter; const R: TRect)` fired after the panel frame, so apps draw with the library painter. Frame/bg from `TyPanel`. |
| **TTySizeBox** | `TTyGraphicControl` | reuse `TyPanel` | Bottom-right resize grip (diagonal dots) that resizes its parent form/host on drag. Pure `TySizeGripDots` geometry + a `Target` (default owner form). |

**Verify:** pure geometry/shape tests (TyBevelRect/shape mapping, TySizeGripHit); OnPaintSurface fires with a painter; Divider text+rule layout. **No new tokens / no golden churn** — all four reuse `TyPanel`/`TyLabel` and derive any 3D shading via ColorMath.

---

## Batch 2 — Titled groups from a `TStrings`

| Control | Base | typeKey | Mechanics / notes |
|---|---|---|---|
| **TTyRadioGroup** | `TTyGroupBox` | reuse `TyGroupBox` + `TyRadioButton` | Auto-populate `TTyRadioButton` children from `Items: TStrings`; `Columns`; `ItemIndex`; `OnSelectionChange`. Rebuild children on Items change (mutual exclusion is inherent to radios). |
| **TTyCheckGroup** | `TTyGroupBox` | reuse `TyGroupBox` + `TyCheckBox` | Same but `TTyCheckBox` children; `Checked[i]`; `OnItemChange`. |
| **TTyToolGroupPanel** | `TTyGroupBox` | reuse `TyGroupBox` + `TyButton` | A ribbon-group-style titled box of tool buttons (host children + a caption band); lighter than a ribbon group (no dialog launcher). Mostly a themed titled host. |

**Verify:** Items→child count/relayout, ItemIndex/Checked round-trips, Columns math, mutual-exclusion (radio). No new tokens (reuse GroupBox/RadioButton/CheckBox/Button). Gotcha: child radios/checks are INTERNAL — `csNoDesignVisible`; rebuild must free old children (owned) cleanly.

---

## Batch 3 — Scrolling & collapsible containers

| Control | Base | typeKey | Mechanics / notes |
|---|---|---|---|
| **TTyScrollBox** | `TTyPanel` | reuse `TyPanel` | Scrolling container: embedded `TTyScrollBar`(s) appear when content exceeds the viewport; child controls offset by scroll pos (`AdjustClientRect` + child origin shift). Mirror the `TTyListBox` embedded-scrollbar pattern. |
| **TTyScrollPanel** | `TTyScrollBox` | reuse `TyPanel` | Auto-scroll panel: edge auto-pan on drag-near-edge (design-time / DnD helper). Thin subclass. |
| **TTyExPanel** | `TTyPanel` | reuse `TyPanel` (+ header via `TyGroupBox`/`TyButton`) | Collapsible/expandable panel: a clickable header toggles `Collapsed`, animating the body height via the eased-position kernel (like progressbar/trackbar); `OnExpand`/`OnCollapse`. |

**Verify:** scroll range/thumb math (reuse ScrollBar helpers), child-offset on scroll, collapse height animation snaps headlessly, header hit-test. Embedded scrollbars/header `csNoDesignVisible`. This is the batch most likely to need the real inline-editor/scroll-commit care — but no inline editor here, just child layout.

---

## Batch 4 — Layout containers

| Control | Base | typeKey | Mechanics / notes |
|---|---|---|---|
| **TTyGridPanel** | `TTyPanel` | reuse `TyPanel` | Fixed grid-of-cells layout: `RowCount`/`ColumnCount` + per-track sizing (absolute/percent/auto), child `Row`/`Column`/`Span` via a control-collection; positions children on resize. Pure `TyGridTrackSizes`/`TyGridCellRect` geometry (heavily unit-tested — the value of the control is correct layout math). |
| **TTyRelativePanel** | `TTyPanel` | reuse `TyPanel` | Anchor-to-sibling relative layout: each child has rules (LeftOf/RightOf/Above/Below/AlignLeft…/AlignParent…); topological-order solve → positions. Pure `TyRelativeSolve` geometry (unit-tested; cycle-safe). |

**Verify:** exhaustive layout-math tests (track sizing incl. percent+auto+star, cell rects, span; relative solve incl. chains + parent-align + cycle guard). No new tokens. The layout SOLVE is pure and headless — this batch is highly testable.

---

## Batch 5 — Bands & extended toolbars

| Control | Base | typeKey | Mechanics / notes |
|---|---|---|---|
| **TTyToolBarEx** | `TTyToolBar` | reuse `TyToolBar` | Toolbar with **wrapping** + an **overflow "»" chevron** popup (reuse `tyControls.PopupSurface` + the ribbon overflow pattern) when items exceed the width. |
| **TTyControlBar** | `TTyPanel` | reuse `TyPanel` | Dockable band host: hosts toolbars in rows/bands with drag handles; band layout + row packing. |
| **TTyCoolBar** | `TTyControlBar` | reuse `TyPanel` | Rebar — draggable/resizable bands (grip per band, resize by drag). Extends ControlBar. |

**Verify:** wrap/overflow split math (reuse `TyRibbonVisibleGroupCount`-style), band row-packing geometry, band drag/resize hit-tests (interaction real-machine; geometry unit-tested). Overflow popup reuses PopupSurface (proven).

---

## Batch 6 — Header strip & grouped list

| Control | Base | typeKey | Mechanics / notes |
|---|---|---|---|
| **TTyHeaderControl** | `TTyCustomControl` | reuse `TyTreeHeader` (from tree) or a new `TyHeader` | Standalone column-header strip: sections with text/width/alignment, drag-resize + click (sort indicator). Extract/reuse the tree/grid header renderer if cleanly separable; else a small new surface. |
| **TTyListGroupPanel** | `TTyPanel` | reuse `TyPanel` (+ `TyListItem`) | Grouped/expandable list-of-items panel (Outlook-nav / accordion): named groups each expand/collapse to reveal their items; item + group models. Reuse the ExPanel collapse animation + list-item paint. |

**Verify:** header section geometry + resize hit-test + sort-indicator; list-group expand/collapse + item hit-test. TTyHeaderControl may add a `TyHeader` token if not cleanly reusing the tree header (decide at build: prefer reuse).

---

## Palette note

All 17 register into the existing **`TyControls Containers`** palette group. Keep the `gen-icons.ps1` drift-guard happy: group-description comments on their OWN line before each `RegisterComponents`, never inline after the group-name comma.

## New theme tokens (minimize)

**Default to ZERO new tokens.** Everything reuses `TyPanel`/`TyGroupBox`/`TyToolBar`/`TyLabel`/`TyButton`/`TyListItem`/`TyRadioButton`/`TyCheckBox`/`TyTreeHeader` and derives any 3D shading via `tyControls.ColorMath`. The only possible exception is `TTyHeaderControl` (Batch 6) IF the tree header can't be cleanly reused — decide then, default to reuse. A new `.tycss` rule (6 themes + compiled + `GGRID` golden) is added ONLY for a genuinely new surface.

## Phase review + wrap

Per-batch adversarial review (Workflow: reviewer per unit → controller triages → fixes + regression tests → the batch's commit). After all 6 batches: a whole-phase review, update `docs/controls/README.md`, and the `examples/containers/` showcase. Phase 6 (menus & window-shell) is NEXT after Phase 5.

## Self-review notes

- Layout controls (GridPanel/RelativePanel) are mostly PURE geometry → the bulk of their value is heavily-unit-tested solve math; the hosting/streaming is the thin shell.
- Hosting containers need `GetChildren`/`csAcceptsControls` + `csNoDesignVisible` on internal helpers ([[designer-internal-subcontrol-leak]]).
- Reuse `TTyScrollBar` for all scrolling (don't reinvent); reuse `TTyPainter.Bitmap.Canvas2D` for bevels/grips (no new primitives).
- Batch 1 first (decorative leaves) to shake out the phase's palette/registration/token flow before the heavier layout/band batches.
