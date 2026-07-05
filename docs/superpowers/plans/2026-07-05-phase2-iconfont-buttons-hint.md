# Phase 2 — Icon-font · Buttons · Labels · Hint — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Phase-level plan for Phase 2 of [the roadmap](../specs/2026-07-05-controls-expansion-roadmap.md). Built in parallel BATCHES (agents write isolated new files; the controller serially integrates the shared files — .lpk, Design.pas, genicons+icons, tytests, README, example). ONE plan per phase.

**Goal:** Ship the foundation the Ribbon (Phase 3) needs — a scalable **icon-font** glyph source + image infrastructure — plus the cheap-breadth **button** and **label** family and a **themed Hint** that replaces the foreign-looking native LCL tooltip app-wide.

**Why this phase now:** the user bumped Ribbon early; a good Ribbon needs crisp scalable icons on its buttons/galleries. The icon-font unlocks that, and the button/hint family are the other Ribbon ingredients. Hint is also the single highest polish-per-hour item (native hints break the themed look in every real app).

**Architecture / conventions (same as Phase 1):** BGRABitmap custom-draw + `.tycss`; leaf `TTyGraphicControl` or focus `TTyCustomControl`; reuse existing typeKeys where a control is a variant (buttons → `TyButton`, labels → `TyLabel`) so most controls need NO new theme rules; new controls with a genuinely new surface get their own typeKey + rules-in-6-themes + golden. Per-control checklist unchanged (source+tests+doc + palette icon + .lpk + index row + example). CHANGELOG only at release.

**Tech Stack:** FPC/Lazarus, BGRABitmap (glyph text rendering), `.tycss`, fpcunit.

---

## Batch A — Hint + Labels (quick wins, independent, no icon-font dependency)

| Control | Base | Purpose |
|---|---|---|
| **TTyHint** | popup | Themed tooltip window replacing the native LCL hint (hook `Application.OnShowHint` / a custom hint window class). Rounded, themed surface + text; the single most visible consistency fix. |
| **TTyBalloonHint** | popup | A pointer/balloon variant (title + body + optional icon) for richer callouts. |
| **TTyLinkLabel** | TTyGraphicControl | Hyperlink label (accent + underline + hand cursor + OnClick/URL) — extract from the About-dialog link. Reuses `TyLabel` theming + accent from `TyGaugeFill`/a link token. |
| **TTyLinkImage** | TTyGraphicControl | Clickable image acting as a hyperlink. |
| **TTyShadowLabel** | TTyGraphicControl | Label with a drop-shadow text effect (draw text twice, offset, in a shadow colour). |
| **TTyGlowLabel** | TTyGraphicControl | Label with a soft glow (blurred halo behind the text via BGRA). |

## Batch B — Icon-font + image infrastructure (the foundation)

| Control | Purpose |
|---|---|
| **TTyIconFont** | Non-visual: register an icon font (FontAwesome-style, from a file or an installed family) and map glyph *names* → codepoints. Renders a glyph to a BGRA bitmap at a given size + colour (via BGRA text). The scalable-vector-icon backbone. |
| **TTyGlyphImageList** | An image list whose items are icon-font glyphs, rendered crisply at the consumer's DPI/size on demand — drop-in wherever a control takes an `Images`/glyph. |
| **TTyCharImage** | A single icon-font glyph shown as an image control. |
| **TTyImage** | Themed raster image control (alpha, stretch/fit modes). |
| **TTyImageCollection** | DPI-aware raster image collection (the raster companion to the icon-font). |
| **TTyVirtualImageList** | Virtual image list drawing from a collection at the target DPI. |

Design note: TTyIconFont/TTyGlyphImageList is the meatiest task — BGRA glyph rasterisation + a name→codepoint map + a clean consumer API (an `ImageList` property + `ImageIndex`, or a `GlyphName` string). Unit-test the pure map (name→codepoint) + size math headlessly.

## Batch C — Buttons (depend on Batch B for glyph buttons)

| Control | Base | Purpose |
|---|---|---|
| **TTySpeedButton** | TTyCustomControl | Flat/toolbar momentary button, groupable (radio-in-group). Reuses `TyButton` theming. |
| **TTyGlyphButton** | TTyCustomControl | Button whose image is an icon-font glyph (crisp any DPI). |
| **TTyGlyphContainerButton** | TTyCustomControl | Large glyph + caption command button (ribbon-style). |
| **TTyMenuButton** | TTyCustomControl | Button that drops a menu on click. |
| **TTyDropDownButton** | TTyCustomControl | Split button: primary action + drop-down arrow to a popup. |
| **TTyButtonGroup** | TTyCustomControl | Segmented/grouped button bar (single/multi select). |
| **TTyColorButton** | TTyCustomControl | Swatch button opening the colour dialog. |

## Batch D — Graphic style-picker buttons (decorative, optional / last)

TTyGradientButton, TTyBrushStyleButton, TTyPenStyleButton, TTyPenWidthButton, TTyShadowStyleButton — small drawing-tool pickers; low priority, do only if useful for a paint-style demo.

---

## Sequencing

1. **Batch A first** — Hint + labels are independent, high-visibility, and unblock nothing else (fast momentum, no icon-font dependency).
2. **Batch B** — the icon-font + image foundation; the hard/meaty part, and a hard prerequisite for glyph buttons + the Ribbon.
3. **Batch C** — the button family (glyph buttons need Batch B).
4. **Batch D** — optional style-picker buttons.
5. Adversarial review after each batch (Explore agent), fix findings, one commit per batch. Phase review at the end; update [[controls-expansion-program]] memory. Then Phase 3 = **Ribbon**.

## Self-review notes
- One plan per PHASE. Each batch = a parallel Workflow: agents write only NEW files (source/test/doc), return integration data; controller serially wires shared files + regen icons + build + review + one commit.
- Icon-font is the phase's real design risk (font rasterisation, DPI, consumer API) — give it its own careful batch (B) and a focused review.
- Hint hooks the LCL hint system (Application.OnShowHint / HintWindowClass) — verify it doesn't fight the existing chrome; test the pure geometry (balloon pointer placement) headlessly, eyeball the rest on a real machine.
