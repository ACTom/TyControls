# Phase 3 — Ribbon (full Office) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Phase-level plan for Phase 3 of [the roadmap](../specs/2026-07-05-controls-expansion-roadmap.md); design in [the Ribbon spec](../specs/2026-07-05-ribbon-design.md). Built in parallel BATCHES (agents write isolated NEW files; the controller serially integrates the shared files — .lpk, Design.pas, genicons+icons, tytests, README, example — then builds/tests/reviews/commits). ONE plan per phase.

**Goal:** A full Office-style Ribbon — tabs → labelled groups → command controls (reusing the Batch-C button family), plus Quick Access Toolbar, application menu, contextual tabs, galleries, and responsive overflow/minimize.

**Architecture:** Designer-container pattern copied from `TTyPageControl`/`TTyTabSheet` (form-owned pages streamed via `GetChildren`, component editor, `csNoDesignVisible` chrome). Command controls are the existing Batch-C buttons. Popups via `TTyDropdownPopup`. New typeKeys `TyRibbon`/`TyRibbonTab`/`TyRibbonGroup` (+ gallery/app-menu as needed) with rules in all 6 themes + golden.

**Tech Stack:** FPC/Lazarus, BGRABitmap, `.tycss`, fpcunit.

---

## R1 — Skeleton (the minimum usable ribbon)

| Control | Base | Purpose |
|---|---|---|
| **TTyRibbon** | TTyCustomControl (designer container) | Top-docked host: draws the tab strip, hosts the active page's group band, streams `TTyRibbonPage` children via `GetChildren`, `ActivePageIndex`/`ActivePage`, runtime tab-click switches page. typeKey `TyRibbon`. |
| **TTyRibbonPage** | TTyCustomControl (like TTyTabSheet) | A tab page: `Caption`; hosts `TTyRibbonGroup`s left→right. The tab cell paints via typeKey `TyRibbonTab` (`:hover`/`:selected`). |
| **TTyRibbonGroup** | TTyCustomControl | A labelled box: `Caption` (bottom title), optional dialog-launcher arrow (`OnDialogLauncher`), hosts command controls arranged by the Office rule (one large button fills height, or small buttons stack 3 rows). typeKey `TyRibbonGroup`. |

**Pure geometry to unit-test headlessly:** `TyRibbonTabRects` (tab-strip cell layout from captions + widths), `TyRibbonGroupBand` (group rects across the page width), `TyRibbonGroupLayout` (control rects inside a group per the large/stacked rule).

**Theme work (R1):** add `TyRibbon`, `TyRibbonTab` (+`:hover`,`:selected`), `TyRibbonGroup` to all 6 `.tycss` (green literal-valued, as it lacks the shared var set), regen DefaultTheme + BuiltinThemeData, add the new keys to the golden GGRID + regenerate the 3 goldens.

**Designer:** `TTyRibbon.GetChildren` streams pages; a component editor ("New Page" on the ribbon, "New Group" on a page); `csNoDesignVisible` on internal chrome set BEFORE `Visible`.

## R2 — Shell integration

| Control | Purpose |
|---|---|
| **TTyRibbonQuickAccess** | A compact command strip in the `TTyForm` title-bar area holding frequently-used commands; integrates with `TTyTitleBar`. |
| **TTyRibbonAppMenu** | Top-left application ("File") button + dropdown (lightweight backstage): a command list + a recent-items list via `TTyDropdownPopup`. typeKey `TyRibbonAppMenu` only if its surface differs from `TyMenuPopup`. |

## R3 — Gallery + contextual tabs

| Control | Purpose |
|---|---|
| **TTyRibbonGallery** | Inline thumbnail row + drop-down full grid (`TTyDropdownPopup`); items = collection (name + glyph/image + caption), `ItemIndex`, `OnSelect`. typeKey `TyRibbonGallery`. Pure grid-layout helper tested headlessly. |
| **Contextual tabs** | `TTyRibbonPage.Context` + `TTyRibbon.Contexts` (named groups, caption + accent); inactive-context pages hidden; `ShowContext`/`HideContext`; active contextual tabs render with the accent highlight. Pure visibility logic tested. |

## R4 — Responsive overflow + minimize

- **Group overflow**: total natural group widths > ribbon width → collapse groups (priority order) to a single drop-down button revealing the group's controls in a popup. Pure decision function `TyRibbonOverflow(naturalWidths, avail)` → collapsed set, tested headlessly.
- **Ribbon minimize**: chevron / double-click a tab collapses to just the tab strip; a tab click then shows the page as a transient popup overlay (auto-hide on click-away).

---

## Sequencing

1. **R1 first** — skeleton unblocks everything; get a real tab/group/button ribbon rendering + the theme tokens + designer container landed and reviewed.
2. **R2** — shell (QAT + app menu), integrates with TTyForm chrome.
3. **R3** — gallery + contextual tabs (the signature interactions).
4. **R4** — responsive overflow + minimize.
5. Per-batch adversarial review (Workflow, one reviewer per unit) → controller triages (many findings are single-thread-LCL false positives) → fixes + regression tests → one commit. Update [[controls-expansion-program]] memory at phase end. Real-machine verification (rendering, IDE designer, interaction) is the user's, deferred.

## Self-review notes
- One plan per PHASE. Each batch = a parallel Workflow: agents write only NEW files (source/test/doc), return integration data; the controller serially wires the shared files + regen icons + build + review + one commit. Per-control checklist unchanged (source+tests+doc + palette icon + .lpk + index row + example).
- The real design risk is the **designer container** (GetChildren streaming + component editor + no-design-visible leaks) — copy `TTyPageControl` closely and lean on [[pagecontrol-redesign-program]]/[[designer-internal-subcontrol-leak]]. IDE-designer behaviour is untestable headlessly (real-machine).
- Reuse Batch-C buttons as the group's command controls — do NOT build new command controls.
- CHANGELOG only at release, not per batch.
