# 轻量三件 — TTySplitter / TTyStatusBar / TTyToolBar — Design Spec

**Date:** 2026-06-26
**Program:** new-controls phase, sub-project ① (see `new-controls-program` memory). One combined spec → plan → TDD → merge.
**Status:** design approved (architecture + ToolBar model locked via brainstorming).

## Goal

Add three custom-drawn, fully-themed Ty-native controls that round out everyday layout/chrome needs, at **LCL-common-API parity** ("把 T 换成 TTy 几乎直接用"): a drag-resize **Splitter**, a bottom **StatusBar**, and a **ToolBar**. Each is themeable via the existing `.tycss` token system and verified by headless logic tests + RenderTo pixel tests.

## Architecture (locked)

- **All three descend from `TTyCustomControl`** (windowed) and custom-draw via `TTyPainter` — the same paradigm as the existing 18 controls. They inherit the theme plumbing (`Controller` / `StyleClass` / `StyleOverride` / states / `GetStyleTypeKey`).
  - Rationale: `TStatusBar` and `TToolBar` are OS-drawn in LCL (Win32 COMCTL); descending + repainting them is the native-skinning we deliberately rejected. `TSplitter` is LCL-drawn and *could* be reused, but a uniform single paradigm (every Ty control = `TTyCustomControl` + typeKey + `TTyPainter`) is worth re-implementing its modest resize logic.
- **Every visual value is a theme token** (`theme-customizability-principle`). Three new typeKeys: `TySplitter`, `TyStatusBar`, `TyToolBar`. ToolBar buttons reuse the existing `TyButton` token (ghost variant) — **no new button typeKey**.
- New typeKeys are added to **all 4 theme sources** (`themes/light.tycss`, `dark.tycss`, `showcase.tycss`, `source/tyControls.DefaultTheme.pas`) and kept byte-synced (the `TestBuiltinMatchesLightTheme` guard + golden tests).

## Non-Goals / Deferred (this spec)

- Splitter: `AutoSnap`, `OnCanResize`/`OnMoved` (keep `OnMoved` only if trivial — see below), docked-to-multiple panes beyond the standard single neighbor.
- StatusBar: owner-draw panels (`OnDrawPanel`), panel `Bevel`/`Style=psOwnerDraw`, progress-in-panel.
- ToolBar: dropdown buttons (`tbsDropDown`), `EdgeBorders`, drag-to-rearrange, `Menu`, transparent/`HotImages`/`DisabledImages`.
- General: per-corner radius on these sub-elements beyond the scalar `border-radius`.

---

## 1. TTySplitter (`source/tyControls.Splitter.pas`)

A bar that resizes the control aligned on one side of it, by dragging.

### API (published)
- `Align: TAlign` — republished; **default `alLeft`**. Determines which edge it docks and which sibling it resizes (the control adjacent on the anchored side).
- `MinSize: Integer` — minimum size (px) of the resized sibling; **default 30**.
- `ResizeStyle: TResizeStyle` — `rsUpdate` (live, default) or `rsLine` (draw a ghost line while dragging, apply on release).
- `ResizeAnchor`/`AutoSnap`/`Beveled` — **not** published this round (deferred).
- `OnCanResize: TTySplitterCanResizeEvent` (`Sender; var ANewSize: Integer; var AAccept: Boolean`) — fired before each resize is applied, so the host can clamp `ANewSize` or veto via `AAccept := False`.
- `OnMoved: TNotifyEvent` — fired once after a resize completes.
- Cursor: auto — `crHSplit` for vertical splitters (`alLeft`/`alRight`), `crVSplit` for horizontal (`alTop`/`alBottom`); recomputed when `Align` changes.

### Behavior
- `MouseDown(mbLeft)`: capture, record the target sibling + its current size + the mouse anchor.
- `MouseMove`: compute the drag delta along the split axis → `newSize = TySplitterNewSize(Align, startSize, delta, MinSize, maxSize)`. `rsUpdate` applies immediately; `rsLine` paints a ghost line at the new boundary and defers.
- `MouseUp`: finalize (apply for `rsLine`), release capture, fire `OnMoved`.
- **Target sibling discovery** mirrors `TCustomSplitter.FindAlignControl`: among the parent's controls, the one on the splitter's anchored side whose facing edge is nearest and whose perpendicular extent overlaps the splitter. `maxSize` = the space available without collapsing other siblings past their constraints.

### Pure function (headless-tested)
```
function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;
```
Clamps `AStartSize ± ADelta` (sign by `AAlign`) into `[AMinSize, AMaxSize]`. Tested across all 4 aligns + clamp boundaries.

### Theme — typeKey `TySplitter`
- `background` (default transparent / `var(--surface)`), `border-radius` (0).
- A centered **grip**: 3 short dots (vertical splitter) / 3 dots in a row (horizontal), drawn in `color` (`var(--muted)`); `TySplitter:hover { color: var(--accent) }`.

---

## 2. TTyStatusBar (`source/tyControls.StatusBar.pas`)

A themed bottom bar showing text panels.

### Types
```
TTyStatusPanel = class(TCollectionItem)
  Text: string;
  Width: Integer;        // fixed px; <= 0 => this panel fills the remaining width
  Alignment: TAlignment; // taLeftJustify default
end;
TTyStatusPanels = class(TOwnedCollection of TTyStatusPanel);
```

### API (published)
- `Panels: TTyStatusPanels` — the panel collection (designer-editable).
- `SimplePanel: Boolean` — **default False**; when True the bar shows `SimpleText` across the full width (panels ignored).
- `SimpleText: string`.
- `SizeGrip: Boolean` — **default True**; draws the diagonal resize-grip dots at the bottom-right.
- `Align` — republished, **default `alBottom`**; height is theme-driven (see token), not user-set per LCL convention (`AutoSize`-like fixed height).

### Behavior / render
- Fixed height from the `TyStatusBar` token (`height`-ish via font + padding; default ≈ 22px logical).
- `SimplePanel`: one text run, left-aligned, padded.
- Else: lay panels left-to-right by `Width`; a panel with `Width <= 0` fills the remaining width; only the FIRST such panel fills (later `<=0` panels get 0). A 1px themed separator is drawn between adjacent panels. Each panel's `Text` is clipped + aligned within its rect.
- `SizeGrip`: 3 diagonal rows of dots in the bottom-right corner, `var(--muted)`.

### Pure function (headless-tested)
```
function TyStatusPanelRects(const AWidths: array of Integer; ATotalWidth, APadding: Integer): TRectArray;
```
Given panel widths + bar width, returns each panel's rect (fill rule, no overflow). Tested: fixed widths, a fill panel, overflow truncation, single panel.

### Theme — typeKey `TyStatusBar`
- `background` (`var(--surface)` / a slightly distinct `var(--surface-2)` if present), `border-top` color (`var(--border)`), `color` (text, `var(--text)`), `font-size`, `padding`.
- Separator + grip use `var(--border)` / `var(--muted)`.

---

## 3. TTyToolBar (`source/tyControls.ToolBar.pas`)

A bar that auto-arranges its child controls (typically `TTyButton`s in ghost/flat style) in a row, optionally wrapping.

### API (published)
- `ButtonHeight: Integer` — **default 0** (= theme default ≈ 24px logical); applied to child `TTyButton`s.
- `ButtonSpacing: Integer` — gap between items; **default 2**.
- `Indent: Integer` — left/top inset before the first item; **default 4**.
- `Wrapable: Boolean` — **default True**; when an item would overflow the bar width, wrap to the next row (bar auto-grows height by rows).
- `ShowCaptions: Boolean` — **default False**; propagated to child `TTyButton`s (caption visibility).
- `Images: TImageList` — propagated to child `TTyButton`s (so a button's `ImageIndex` resolves against the bar's list).
- `Flat: Boolean` — **default True**; when True child `TTyButton`s default to the ghost (flat) variant; documented as cosmetic given the buttons are themed.
- `Align` — republished, **default `alTop`**; height auto-derives from `ButtonHeight` + rows + padding.

### Behavior / layout
- The bar **lays out its child controls itself** (not via LCL `Align`), in child order, left-to-right from `Indent`, vertically centered, `ButtonSpacing` between, wrapping when `Wrapable`. Re-layout on resize, child add/remove, and child bounds change.
- On a child `TTyButton` being parented: best-effort apply `ButtonHeight`, `Flat`→ghost, `ShowCaptions`, `Images`.
- **Separator**: a lightweight `TTyToolSeparator = class(TTyGraphicControl)` — a thin themed vertical divider (fixed small width); dropped between buttons and laid out like any other child. No special toolbar logic.

### Pure function (headless-tested)
```
function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TRectArray;
```
Returns each item's rect + the row count. Tested: single row, wrap to N rows, spacing/indent math, an item wider than the bar.

### Theme — typeKey `TyToolBar`
- `background` (`var(--surface)`), `border-bottom` color (`var(--border)`), `padding`.
- Buttons reuse `TyButton` (ghost) — no new token.

---

## Events (parity — do NOT omit)

All three descend from `TTyCustomControl`, so they **inherit the full published event set** — verify each exposes it (it should, additively, from the base):
- **Tier A:** `OnClick`, `OnDblClick`, `OnMouseDown/Up/Move`, `OnMouseEnter/Leave`, `OnMouseWheel/Up/Down`, `OnContextPopup`, `OnResize`, `OnChangeBounds`.
- **Tier B:** `OnKeyDown/Up/Press`, `OnUTF8KeyPress`, `OnEnter`, `OnExit`, `OnEditingDone`.

Each `Mouse*`/`Click` override **must call `inherited`** so the events fire (the established additive invariant). A headless RTTI test asserts a representative subset is published on each of the three classes.

Control-specific events/helpers:
- **TTySplitter:** `OnCanResize` (veto/clamp before apply) + `OnMoved` (after). Both fire from the drag handler around the size application.
- **TTyStatusBar:** standard `OnClick`/`OnDblClick`/`OnMouseDown` inherited; add a public `PanelAtPos(X, Y: Integer): Integer` helper so the host can resolve which panel was clicked inside those handlers (returns -1 outside any panel / in SimplePanel mode). `OnDrawPanel` (owner-draw) stays deferred.
- **TTyToolBar:** inherited set covers it; each child `TTyButton` carries its own `OnClick`. No toolbar-specific event this round.

---

## Cross-cutting

### Theme integration
- Add `TySplitter`, `TyStatusBar`, `TyToolBar` rules to `themes/light.tycss`, `dark.tycss`, `showcase.tycss`, and `source/tyControls.DefaultTheme.pas`, byte-synced (light ↔ Default identical). New golden expectations regenerated for the 3 typeKeys; `TestBuiltinMatchesLightTheme` stays green.

### Design-time
- `RegisterComponents('TyControls', [TTySplitter, TTyStatusBar, TTyToolBar, TTyToolSeparator])` in `designtime/tyControls.Design.pas`.
- Palette icons generated via the existing `gen-icons.ps1` pipeline (BGRA glyphs → `.lrs`), incl. HiDPI variants; drift-guard updated.
- `About` read-only property inherited from the base (already present).

### Demo
- Place a `TTySplitter` (between two panels), a `TTyStatusBar` (alBottom, 2-3 panels), and a `TTyToolBar` (alTop, a few ghost `TTyButton`s + a separator) in `examples/demo/mainform.lfm` (designer-driven, per project rule).

### Testing
- **Headless logic**: `TySplitterNewSize`, `TyStatusPanelRects`, `TyToolbarLayout` pure-function tests (boundary + multi-case).
- **Behavior**: splitter drag (synthetic MouseDown/Move/Up → sibling resized + clamped); statusbar panel hit/layout; toolbar child arrangement on add/resize/wrap.
- **RenderTo pixel tests**: each control rendered headlessly against the 3 themes (the new typeKeys produce the expected fills/grip/separators). Existing pixel/golden tests stay byte-identical (additive — no change to existing controls).

## Decomposition note

One spec, but the plan sequences the controls independently (Splitter → StatusBar → ToolBar), each a self-contained set of TDD tasks producing a working, tested control before the next. Folded-in small items (`TTyTabSet`, tri-state CheckBox, editable ComboBox) are **separate** later specs, not part of this one.
