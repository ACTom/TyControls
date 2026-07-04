# ty-controls — Controls Expansion Roadmap (Phase 3 program)

**Status:** DRAFT for approval — 2026-07-05.

**Intent:** Grow ty-controls toward the breadth of the reference suites (BusinessSkinForm ~130 classes, StyleControls ~200 classes) by implementing **most of their control TYPES, one at a time**, each rebuilt the ty-controls way: BGRABitmap custom-draw + `.tycss` theming, no native reliance, cross-platform pixel-identical. The references tell us **which controls, what for, and how the UI can look** — not how to implement them.

## Why the count is ~130 distinct controls (not ~200+)

The reference class counts are inflated by things that collapse for us:
- **DB / data-aware palettes — CUT.** Both suites ship a full parallel `*DB*` set (~60–80 classes). Excluded entirely (no `TDataSource`).
- **"standard + GP" duplicates collapse into ONE.** StyleControls ships a *standard* AND a *GDI+ (GP, anti-aliased)* version of most controls (`TscButton` + `TscGPButton`, etc.). **ty-controls is always anti-aliased custom-draw**, so each pair is a single `TTy*`.
- **Config-variants become properties, not classes.** `TscGPMeter90` / `Meter120` → one `TTyMeter` with an angle property; `Memo`/`Memo2` → one `TTyMemo`.
- **Engine/tooling — CUT:** image-skin files + Skin Builder, skin adapters, DevExpress adapters, WebBrowser hosts, Zip/UnZip, the print engine + print dialogs. **RichEdit — CUT** (TTyMemo stays plain-text).

What remains is ~130 genuinely distinct control types. Effort tags: **S** (days) / **M** (1–2 wk) / **L** (3–6 wk) / **XL** (multi-month). We ship **one control per merge**, in the phases below.

## Cross-cutting conventions (every new control)

`TTyGraphicControl` (leaf) or `TTyCustomControl` (focus/keyboard) base · `GetStyleTypeKey` + `.tycss` rules in all 6 themes + compiled themes + `GGRID` golden · palette registration + generated icon (+ genicons/$classes/test sync) · `.lpk` unit entry · i18n if user-facing strings · `docs/controls/<name>.md` + index row · headless tests · an `examples/` showcase · `[Unreleased]` CHANGELOG. Visual values are **always** theme tokens.

---

## Phase 1 — Graphics & Instruments (14) · the differentiator, most demo-able, leaf controls

| Control | Eff | Purpose / UI |
|---|---|---|
| **TTyGauge** | M | Value gauge: linear-bar / arc / full-ring styles; track + value fill (gradient), ticks, centered value text. Establishes the arc vocabulary. |
| **TTyMeter** | M | Analog needle meter over a scaled arc + tick labels; `SweepAngle` covers the 90°/120°/270° variants. |
| **TTyLevelMeter** | M | VU / horizontal-or-vertical level bar (segmented or gradient), peak hold. |
| **TTyDial** | M | Rotary knob — drag/wheel rotates a needle to set a value; optional detents (interactive). |
| **TTyGearDial** | M | Gear-styled rotary dial (decorative variant of Dial). |
| **TTyAnalogClock** | S | Hour/minute/second needles from `Time`; `TTimer` tick. |
| **TTyCircularProgress** | S | Determinate ring/circular progress. |
| **TTyActivityIndicator** | S | Indeterminate spinner (rotating arc gap). |
| **TTyGearActivityIndicator** | S | Spinning-gear busy indicator (decorative variant). |
| **TTyActivityBar** | S | Indeterminate *linear* progress (marching band). |
| **TTySwitch** | S | iOS-style pill on/off switch (visual sibling of the existing knob `TTyToggleSwitch`). |
| **TTyUpDown** | S | Standalone up/down spin-button pair (bindable to any edit). |
| **TTySparkline** | S–M | Tiny inline line/bar trend chart (bridge toward charts; no axes). |
| **TTyRating** | S | Star/heart rating control (hover + click to set). |

## Phase 2 — Icon-font, images, buttons, labels, hint (23) · foundation for ribbon/toolbars + cheap breadth

| Control | Eff | Purpose / UI |
|---|---|---|
| **TTyIconFont** | M | Register an icon font (FontAwesome-style); reference glyphs by name/codepoint. The scalable-vector-icon backbone. |
| **TTyGlyphImageList** | M | Image list whose items are icon-font glyphs (crisp at any DPI), consumed by any control with an image slot. |
| **TTyCharImage** | S | A single icon-font glyph as an image control. |
| **TTyImage** | S | Themed raster image control (with alpha, stretch/fit modes). |
| **TTyImageCollection** | S | DPI-aware raster image collection (companion to the icon-font). |
| **TTyVirtualImageList** | S | Virtual image list drawing from a collection at the target DPI. |
| **TTyGlyphButton** | S | Button whose image is an icon-font glyph. |
| **TTyGlyphContainerButton** | S | Large glyph + caption command button (ribbon-style). |
| **TTySpeedButton** | S | Flat toolbar/momentary button, groupable (radio-in-group). |
| **TTyMenuButton** | S | Button that drops a menu on click. |
| **TTyDropDownButton** | M | Split button: primary action + drop-down arrow to an arbitrary popup. |
| **TTyButtonGroup** | S | Segmented/grouped button bar (single/multi select). |
| **TTyColorButton** | S | Button showing a color swatch, opens the color dialog. |
| **TTyGradientButton** | S | Picks/previews a gradient. |
| **TTyBrushStyleButton** | S | Picks a brush/fill style. |
| **TTyPenStyleButton** | S | Picks a line/pen style. |
| **TTyPenWidthButton** | S | Picks a line width. |
| **TTyShadowStyleButton** | S | Picks a shadow style. |
| **TTyLinkLabel** | S | Hyperlink label (accent + underline + hand cursor + OnClick/URL). |
| **TTyLinkImage** | S | Clickable image acting as a hyperlink. |
| **TTyShadowLabel** | S | Label with a drop-shadow text effect. |
| **TTyGlowLabel** | S | Label with a Vista-style glow text effect. |
| **TTyHint / TTyBalloonHint** | M | **Themed tooltip + balloon hint** replacing the foreign native LCL hint app-wide. High leverage; used by everything. |

## Phase 3 — Ribbon & navigation (23) · bumped early per user

| Control | Eff | Purpose / UI |
|---|---|---|
| **TTyRibbon** | XL | Office-style ribbon: tabbed pages of command **groups** (large/small buttons, in-group galleries), collapse-to-strip. The flagship (needs Phase 2). |
| **TTyRibbonPage** | — | A ribbon tab's page (host for groups). |
| **TTyRibbonGroup** | — | A titled command group inside a page. |
| **TTyRibbonDivider** | S | Vertical divider between groups. |
| **TTyAppButton** | S | The round/File application button. |
| **TTyAppMenu** | M | Application (File) menu: left command pane + right recent-items pane. |
| **TTyAppMenuPage** | S | A page within the app menu. |
| **TTyQuickAccessBar** | S | Always-visible mini command strip in the caption. |
| **TTyGallery** | M | Thumbnail/command gallery (grid of large hover-preview items). |
| **TTyGalleryMenu** | S | The gallery as a drop-down. |
| **TTyToolPager** | M | Ribbon/Outlook-style pager container (switchable pages of tools). |
| **TTyAppPager** | M | Full-app pager (nav rail + pages). |
| **TTyPageViewer** | S | Multi-page host with no tab strip (paged by code). |
| **TTyTabControl** | M | Tab strip that swaps content you host (vs `TTyPageControl` which owns pages). |
| **TTyVertPageControl** | M | Page control with tabs down the side. |
| **TTyVertTabControl** | M | Vertical tab strip. |
| **TTyCategoryButtons** | M | Outlook-style collapsible category button list (nav). |
| **TTyButtonsBar** | S–M | Row/column of command buttons. |
| **TTyLinkBar** | S | Link-style navigation bar. |
| **TTyFrameBar** | M | Stack of collapsible framed sections (accordion). |
| **TTySplitView** | M | Hamburger split view (collapsible side nav + content). |
| **TTyFormTabsBar** | M | Browser-style document tab bar in the window caption. |
| **TTyNavBar** | M | Combined side navigation bar (icons + labels, collapsible) — modern app shell. |

## Phase 4 — Rich inputs & pickers (26) · low-risk long tail, each reuses Edit/Combo/ListBox

| Control | Eff | Purpose / UI |
|---|---|---|
| **TTyMaskEdit** | S | Edit with an input mask (date/phone/IP…). |
| **TTyNumericEdit** | S | Float edit with thousands/decimals formatting. |
| **TTyCurrencyEdit** | S | Currency-formatted edit (symbol, grouping). |
| **TTyCalcEdit** | M | Edit with a drop-down calculator. |
| **TTyCalcCurrencyEdit** | S | Calc edit in currency mode. |
| **TTyCalculator** | M | Standalone calculator control. |
| **TTyURLEdit** | S | Edit that renders/launches a hyperlink. |
| **TTyTrackEdit** | S | Edit paired with an inline slider. |
| **TTyComboEdit** | S | Edit with a custom drop-down (button + arbitrary popup). |
| **TTyComboBoxEx** | M | Combo with per-item image/indent (icon-font aware). |
| **TTyCheckListBox** | S | List box with a checkbox per row. |
| **TTyCheckComboBox** | M | Combo whose drop-down is a checkable list (multi-select summary). |
| **TTyMRUComboBox** | S | Most-recently-used history combo. |
| **TTyOfficeListBox / TTyOfficeComboBox** | M | Office-style grouped list/combo. |
| **TTyHorzListBox** | S | Horizontally scrolling list. |
| **TTyAdvancedListBox / TTyAdvancedComboBox** | M | Enhanced list/combo (headers, per-item layout). |
| **TTyColorBox** | S | Combo of named colors with swatches. |
| **TTyColorComboBox** | S | Color combo with a "more…" custom option. |
| **TTyColorListBox** | S | List of named colors. |
| **TTyColorGrid** | S | Palette grid selector. |
| **TTyHSColorPicker** | M | Hue/saturation square picker (extract from ColorDialog). |
| **TTyLColorPicker** | S | Luminance bar picker. |
| **TTyFontComboBox** | M | Font-family combo, each item rendered in its own font. |
| **TTyFontListBox** | S | Font-family list. |
| **TTyFontSizeComboBox** | S | Font-size combo. |
| **TTyValueListEditor** | M | Two-column name/value property editor (a light inspector). |

## Phase 5 — Containers & layout (17)

| Control | Eff | Purpose / UI |
|---|---|---|
| **TTyExPanel** | M | Collapsible/expandable panel (animated header). |
| **TTyScrollBox** | M | Scrolling container (embedded TTyScrollBars) for oversized content. |
| **TTyScrollPanel** | S–M | Auto-scroll panel with edge auto-pan. |
| **TTyPaintPanel** | S | Owner-draw panel (an `OnPaint` surface using the painter). |
| **TTyBevel** | S | Decorative bevel line/frame. |
| **TTyDivider** | S | Labeled horizontal section divider. |
| **TTyRadioGroup** | S | Titled group auto-populating radios from a `TStrings`. |
| **TTyCheckGroup** | S | Titled group of checkboxes from a `TStrings`. |
| **TTyControlBar** | M | Dockable band host for toolbars. |
| **TTyCoolBar** | M | Rebar (draggable/resizable bands). |
| **TTyToolBarEx** | S | Toolbar with overflow chevron + wrapping. |
| **TTyHeaderControl** | S–M | Standalone column-header strip (extract from tree/grid header). |
| **TTyGridPanel** | M | Fixed grid-of-cells layout container. |
| **TTyRelativePanel** | M | Anchor-to-sibling relative layout container. |
| **TTyToolGroupPanel** | S | A titled group of tool buttons (ribbon-group outside a ribbon). |
| **TTyListGroupPanel** | M | Grouped/expandable list-of-items panel. |
| **TTySizeBox** | S | Bottom-right resize grip. |

## Phase 6 — Menus & window-shell extras (8)

| Control / feature | Eff | Purpose / UI |
|---|---|---|
| **TTyMenuEx** | M | Enhanced menu: header/section captions, side banner, icon column, checkable groups. |
| **TTyImagesMenu** | S | Image-list-backed menu helper. |
| **TTyMDITabsBar** | M | MDI child tab bar. |
| **TTyTrayIcon** | S | System-tray icon (minimize-to-tray integration). |
| **TTyForm: MDI client** | M | Themed MDI client area + child window chrome. |
| **TTyForm: roll-up / shade** | S | Double-click caption to roll the window up to its title bar. |
| **TTyForm: inactive dimming** | S | Dim (brightness/grayscale) a form when it loses focus. |
| **TTyForm: acrylic/mica backdrop** | M | Win11 Fluent/acrylic translucent window background (extends the existing WindowEffects). |

## Phase 7 — Shell / file-system + themed file dialogs (18)

| Control | Eff | Purpose / UI |
|---|---|---|
| **TTyShellTreeView** | M | OS folder tree (data-provider + icons over TTyTreeView). |
| **TTyShellListView** | M | OS folder contents (over TTyListView). |
| **TTyFileListBox** | S | Classic file list of a directory. |
| **TTyDirectoryListBox** | S | Classic directory list. |
| **TTyDriveComboBox** | S | Drive picker combo. |
| **TTyShellComboBox** | S | Shell path/breadcrumb combo. |
| **TTyFilterComboBox** | S | File-filter combo for dialogs. |
| **TTyFileListView** | M | Icon/report file list-view. |
| **TTyDirTreeView** | M | Directory-only tree. |
| **TTyDirectoryEdit** | S | Edit + folder-browse button. |
| **TTyFileEdit / TTySaveFileEdit** | S | Edit + open / save-file browse button. |
| **TTyOpenDialog / TTySaveDialog** | L | Fully themed file open/save (list/tree + filters + path box) replacing native. |
| **TTyOpenPictureDialog / TTySavePictureDialog** | M | The above with an image preview pane. |
| **TTyOpenPreviewDialog / TTySavePreviewDialog** | M | Generic preview-pane file dialogs. |

## Phase 8 — Data views & the Grid (5) · LATE — the Grid gets its OWN detailed design

Deferred to the end on purpose: `TTyGrid` is a large control (TreeView-scale) that deserves a dedicated spec of its own when we reach it.

| Control | Eff | Purpose / UI |
|---|---|---|
| **TTyGrid** | XL | String/draw grid: virtual rows+cols, sort, inline cell editors, per-cell custom draw. **Separate detailed design later.** |
| **TTyListView** | L | Report/icon/list/tile views with columns, selection, sort (non-tree sibling of TreeView). |
| **TTyGridView** | M | Wrapping item/thumbnail grid. |
| **TTyOfficeGridView** | M | Office-style grid view (headers, grouping). |
| **TTyPropertyGrid** | L | Two-column property inspector (categories, per-type editors) — a power-user staple. |

## Phase 9 — Polish, effects, graphics utilities (6)

| Control / feature | Eff | Purpose / UI |
|---|---|---|
| **Transitions & effects** | M | Form/panel fade/slide transitions + control hover effects on the animation kernel. |
| **TTyImageView / effects** | M | Image viewer with pan/zoom + basic effect filters (blur/tint/grayscale) via BGRA. |
| **TTyShape** | S | Vector shape primitive (rect/ellipse/line/polygon) for diagrams. |
| **TTyStarShape / TTyArrow** | S | Decorative vector shapes. |
| **TTyHtmlLabel** | L (optional) | Mini-HTML label (subset renderer) — borderline; only if a real need appears. |
| **TTyChart (basic)** | L (optional) | Line/bar/pie chart — a differentiation opportunity; minimal first, scope-guarded. |

---

## Rough totals

Phase 1: 14 · Phase 2: 23 · Phase 3: 23 · Phase 4: 26 · Phase 5: 17 · Phase 6: 8 · Phase 7: 18 · Phase 8: 5 · Phase 9: 6 — **≈140 controls/features.** (Some collapse or split as we go.)

## Sequencing rationale

1. **Graphics first** — differentiator + best demo; leaf controls de-risk the pipeline.
2. **Icon-font foundation next** — small, and a hard prerequisite for a good Ribbon + toolbars.
3. **Ribbon early** (per user) at Phase 3, right after its foundation.
4. **Cheap long tail (4–5)** — steady, low-risk breadth, one control per merge.
5. **Menus/shell extras (6)** — window-shell features that build on existing chrome.
6. **Shell + file dialogs (7)** — build on the views.
7. **Grid & data views (8) LAST** — biggest/riskiest; the Grid gets its own dedicated design.
8. **Polish/effects (9)** — final gloss + optional charts.

## Open questions for the user

1. **Effort is real** — ≈140 controls is a long, open-ended program. Run it open-endedly (one control per merge, this order) or cap at certain phases for now?
2. **Ribbon placement** — Phase 3 (after the icon-font it needs) OK, or do you want it even sooner?
3. Any **excluded** items you actually want back, or any **phase reordering**?

## Next step after approval

Lock Phase 1, and I'll turn each control into a bite-sized implementation plan (`docs/superpowers/plans/…`) and execute it subagent-driven, one control at a time, starting with **TTyGauge**.
