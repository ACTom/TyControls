# TTyRibbon (full Office Ribbon) — Design

**Status:** approved 2026-07-05. Phase 3 of the [controls-expansion roadmap](2026-07-05-controls-expansion-roadmap.md). Built on branch `feat/controls-expansion`.

## Goal

A full Office-style Ribbon for ty-controls: a top command surface with **tabs → labelled groups → command controls**, plus a Quick Access Toolbar, an application menu, contextual tabs, galleries, and responsive group overflow / ribbon minimize. Custom-drawn (BGRABitmap + `.tycss`), no native controls.

## Leverage (what we already have)

- **Command controls** — Phase-2 Batch C shipped the whole button family (`TTyGlyphButton`, `TTyGlyphContainerButton` = large ribbon button, `TTySpeedButton`, `TTyDropDownButton`, `TTyMenuButton`, `TTyColorButton`, `TTyButtonGroup`) plus `TTyIconFont`/`TTyCharImage` for crisp scalable glyphs. Groups host these directly — no new command controls needed.
- **Designer-container pattern** — reuse the proven `TTyPageControl`/`TTyTabSheet` approach verbatim: the container is form-owned, its pages are streamed via `GetChildren`, a component editor adds/removes pages, and internal chrome is `csNoDesignVisible`. See [[pagecontrol-redesign-program]] and [[designer-internal-subcontrol-leak]] for the hard-won lessons (set `csNoDesignVisible` BEFORE `Visible`; MainColumn-style ordering footguns).
- **Popup host** — `TTyDropdownPopup` (tyControls.Popup) for the app menu, gallery expansion, and overflowed-group dropdowns.
- **Painter** — `TTyPainter` (frame/text/Canvas2D) and the `TyButton` `DrawContent` hook idiom.

## Component breakdown (4 batches)

### R1 — Skeleton (minimum usable ribbon)
- **TTyRibbon** (`TTyCustomControl`, designer container): docked `alTop`; draws the tab strip and hosts the active page's group band; streams `TTyRibbonPage` children via `GetChildren`; `ActivePageIndex`/`ActivePage`; runtime click-a-tab → switch page. New typeKey `TyRibbon` (surface).
- **TTyRibbonPage** (`TTyCustomControl`, like `TTyTabSheet`): a tab — `Caption`; hosts `TTyRibbonGroup`s laid out left→right. New typeKey `TyRibbonTab` (the tab cell: normal/hover/selected).
- **TTyRibbonGroup** (`TTyCustomControl`): a labelled box — `Caption` (title along the bottom), an optional dialog-launcher arrow (bottom-right, `OnDialogLauncher`), and it hosts command controls arranged by the Office rule (one large button fills the height, or small buttons stack in 3 rows). New typeKey `TyRibbonGroup` (box border + title).
- Pure geometry (headless-tested): tab-strip cell layout, group band layout, in-group control layout.

### R2 — Shell integration
- **TTyRibbonQuickAccess** (QAT): a compact command strip that lives in the `TTyForm` title-bar area (above or beside the tabs), holding a few frequently-used commands. Integrates with the existing `TTyTitleBar`.
- **TTyRibbonAppMenu**: the top-left application ("File") button + dropdown — a lightweight backstage: a command list plus a recent-items list, shown via `TTyDropdownPopup`. New typeKey `TyRibbonAppMenu` if its surface differs from the menu popup.

### R3 — Gallery + contextual tabs
- **TTyRibbonGallery** (`TTyCustomControl`): an inline row of thumbnail items with a drop-down to expand the full grid (`TTyDropdownPopup`). Items are a collection (name + glyph/image + optional caption); `ItemIndex`, `OnSelect`. New typeKey `TyRibbonGallery`.
- **Contextual tabs**: `TTyRibbonPage.Context` (a context name) + `TTyRibbon.Contexts` (named contextual groups, each a caption + accent colour). A page whose `Context` is inactive is hidden; `ShowContext(name)`/`HideContext(name)` toggle visibility, and active contextual tabs render with their accent highlight above the strip.

### R4 — Responsive overflow + minimize
- **Group overflow**: when the total natural group widths exceed the ribbon width, groups collapse (in a priority order) to a single drop-down button that reveals the group's controls in a popup. Pure decision function (headless-tested): given group natural widths + available width → which groups collapse.
- **Ribbon minimize**: a chevron / double-click a tab collapses the ribbon to just the tab strip; clicking a tab then shows that page as a transient popup overlay, auto-hiding on click-away.

## Theming

New typeKeys (genuinely new surfaces → own tokens + rules in all 6 themes + golden entries): `TyRibbon`, `TyRibbonTab` (+ `:hover`/`:selected`), `TyRibbonGroup`. R2/R3 add `TyRibbonAppMenu`/`TyRibbonGallery` only if their surface differs from existing tokens (reuse `TyMenuPopup`/`TyListItem` where possible). Command controls inside groups keep `TyButton`. All visual values theme-token-driven (no hard-coded colours), per [[theme-customizability-principle]].

## Design-time model

`TTyRibbon` is a designer container exactly like `TTyPageControl`: `GetChildren` streams the `TTyRibbonPage`s (form-owned), a component editor adds "New Page"/"New Group", and internal chrome uses `csNoDesignVisible`. Groups are containers too (host command controls dropped in the designer). Runtime tab-switch works (the design-time page-switch limitation of custom-draw containers does not affect runtime clicks).

## Testing

- **Headless (pure geometry)**: tab-strip cell rects, group-band layout, in-group control layout, overflow-collapse decision, gallery grid layout, contextual-tab visibility logic. These are the correctness core.
- **Real machine (deferred, user tests)**: on-screen rendering, IDE-designer authoring, tab-click/hover, popup/overflow/minimize interaction, title-bar QAT integration.

## Excluded / deferred

Backstage full-screen view (app menu is a dropdown, not a full backstage), ribbon customization UI, KeyTips (Alt-key overlay badges) — deferred to polish. No DB/data binding (roadmap-excluded).

## Sequencing

R1 → R2 → R3 → R4, each a parallel Workflow batch (agents write isolated new files, controller serially integrates shared files) + a per-batch adversarial review (Workflow, one reviewer per unit) + one commit per batch. One phase plan (`docs/superpowers/plans/2026-07-05-phase3-ribbon.md`) covers all four batches. Update [[controls-expansion-program]] memory at phase end.
