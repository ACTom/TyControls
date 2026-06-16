# TTyForm Window Architecture Design

**Date:** 2026-06-17
**Status:** Design (awaiting user review → implementation plan)
**Supersedes the chrome direction in:** the FormChrome research notes; the prior "controller-primary, TTyForm optional-later" recommendation is **inverted** here on verified evidence.

---

## 1. Goal

Replace the controller-style window chrome (`TTyFormChrome`, a `TComponent` attached to an ordinary `TForm`) with a thin **`TTyForm = class(TForm)`** descendant that is the single, design-time-WYSIWYG path for custom window chrome (custom title bar, reserved content area, future ribbon/menu/toolbar bands). Plain native windows keep using plain `TForm`. The controller is **retired**.

This closes four issues the user raised:

1. **Covering bug** — enabling chrome made the title bar overpaint existing controls (they kept their design-time `Top` and rendered under the band).
2. **Rigid title bar** — the title bar could not be customized/filled by the developer (VS-Code-style buttons, combos, menu).
3. **Ribbon future** — no clean seam for a later ribbon-style band.
4. **Is a `TForm` descendant necessary?** — answered: not strictly necessary, but it is the genuinely simpler primary architecture once design-time WYSIWYG and a growing band stack are wanted.

## 2. Decisions already made (do not relitigate)

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | `TTyForm = class(TForm)` is the **sole** chrome path. | Solves the covering bug *by construction*; gives design-time WYSIWYG; scales to bands. |
| D2 | Plain `TForm` is the **native** path (no chrome). | "Want native = use `TForm`; want chrome = descend from `TTyForm`." |
| D3 | **Remove** `TTyFormChrome` (controller). Its main use case (chrome on an existing plain `TForm`) evaporates under D1/D2. | Single chrome path; deletes the fragile runtime-reparent/content-injection problem entirely. |
| D4 | Window behavior (drag / edge-resize / maximize / multi-monitor DPI) is factored into a form-agnostic **`TTyChromeEngine`** that `TTyForm` owns and delegates to. | Keeps `TTyForm` thin; preserves headless testability; makes re-adding a controller cheap later (bridge not burned). |
| D5 | Content area is a dedicated **`alClient` `TTyContentPanel`**, **not** form-level `AdjustClientRect`. | Verified against LCL source: `AdjustClientRect` does **not** shift free-placed/anchored children (see §4). A ContentPanel is the only correct way to get WYSIWYG for designer-dropped controls. |
| D6 | Design-time WYSIWYG is **layout-level** (geometry honest; title-bar **skin** renders unthemed in the designer, like every other tyControl). | The designer has no runtime theme context. Accepted. |
| D7 | Demo is **split into two**: a native (`TForm`) demo and a `TTyForm` demo. | The `TTyForm` demo's designer placement doubles as the mandatory manual WYSIWYG verification. |

## 3. Architecture overview

```
TTyForm = class(TForm)                 // borderless (bsNone) from construction
  ├─ FTitleBar : TTyTitleBar  (alTop,   SetSubComponent, Name='TyTitleBar')   // band 0
  │     ├─ system buttons (min/max/close) — code-owned, right gutter
  │     └─ [Q2] caption/icon left zone + AdjustClientRect content strip
  ├─ (future bands: menu / ribbon / toolbar — alTop, created before FContent)
  └─ FContent  : TTyContentPanel (alClient, SetSubComponent, Name='TyContent') // reserved client area
        └─ user controls live here (their (0,0) already starts below the band)

TTyChromeEngine (owned by TTyForm)     // form-agnostic window behavior
  drag-move · edge-resize + hover cursors · custom borderless maximize/restore · DPI rescale
```

Key properties of this shape:

- **Covering bug gone by construction.** `FTitleBar` (alTop) reserves the top strip via the *aligned* layout path; `FContent` (alClient) fills the remainder strictly below it. User controls are children of `FContent`, whose own origin is below the band — so they never overlap it, at design time or runtime.
- **Lifecycle for free.** `TTyForm` *is* a `TForm`, so `OnCloseQuery`/`OnClose`/`WindowState`/etc. are the standard, already-published form events. The custom `OnMinimize/OnMaximize/OnRestore` of `TTyFormChrome` are **dropped**; caption buttons call `Close` / set `WindowState:=wsMinimized` / `Engine.ToggleMaximize`.
- **No handle-rebuild dance.** `TTyFormChrome` had to capture+restore bounds across a live `BorderStyle:=bsNone` handle rebuild ([Form.pas:485-504](../../../source/tyControls.Form.pas#L485-L504)). `TTyForm` is born `bsNone`, so that whole concern disappears.

## 4. Verified design-time mechanism (the load-bearing core)

This was pinned against the actual LCL 4.4.0 source at `C:\lazarus\lcl` (five independent refutation vectors, all failed). It is the reason for D5.

**Claim:** Overriding `AdjustClientRect` on a form to inset the top by the band height does **not** move a designer-dropped, anchored (`Align=alNone`, `Anchors=[akLeft,akTop]`) child below the band. Such a child keeps its raw `Top` and overlaps the band — the original bug. `AdjustClientRect`'s inset reaches **only aligned** children.

**Decisive code path** (`TWinControl.AlignControls`, `wincontrol.inc`):
1. `AdjustClientRect(RemainingClientRect)` writes the inset into `RemainingClientRect` **only** (`:3259`).
2. The parent client size used for anchored math comes from the **raw** `GetLogicalClientRect` (`:3260-3262`), which `TWinControl` does not override → `TControl.GetLogicalClientRect` = `ClientRect` = `(0,0,W,H)`. `TWinControl.GetClientRect` (`:4035-4152`) returns the widget-set/raw rect and never calls `AdjustClientRect`.
3. The `alNone`/anchored branch (`:2824-2941`) sets `NewTop := GetAnchorSidePosition(akTop, CurBaseBounds.Top)`; with no `AnchorSide.Control` (designer default) this returns the **raw** `Top` unchanged.
4. `RemainingClientRect` (the only inset carrier) is consumed **exclusively** by the aligned case `alLeft/alTop/alRight/alBottom/alClient` (`:2950-3072`). The `alNone` branch never reads it.
5. `GetClientOrigin = Parent.ClientOrigin + FLeft + FTop` (`control.inc:1632-1639`) — no inset.

**Library proof in isolation:** [tyControls.GroupBox.pas:43-47](../../../source/tyControls.GroupBox.pas#L43-L47) overrides *only* `AdjustClientRect` — aligned children inset below the caption; free-placed children overlap it.

**Consequence:** A single `alClient` `TTyContentPanel` *is* inset below the band (it goes through the aligned path). User controls are then anchored to the ContentPanel's own `(0,0)`, already below the band → correct at design time and runtime, with no dependence on `AdjustClientRect` shifting `alNone` controls.

## 5. Component design

### 5.1 `TTyContentPanel` (new) — `tyControls.Form.pas`

- `TTyContentPanel = class(TTyCustomControl)`; `GetStyleTypeKey = 'TyContentPanel'`.
- Paints its background from the `TyContentPanel` theme token (theme hard-rule compliant), defaulting in `DefaultTheme` to the same background as `TyForm` so the window looks seamless.
- No special behavior; it exists to be the reserved, design-time-parentable client region.

### 5.2 `TTyForm` (new) — `tyControls.Form.pas`

Constructor (after `inherited Create`):
```pascal
BorderStyle := bsNone;                       // borderless from birth
FTitleBar := TTyTitleBar.Create(Self);
FTitleBar.Name := 'TyTitleBar';
FTitleBar.SetSubComponent(True);
FTitleBar.Parent := Self;  FTitleBar.Align := alTop;  FTitleBar.Height := TitleHeight@PPI;
FContent := TTyContentPanel.Create(Self);
FContent.Name := 'TyContent';
FContent.SetSubComponent(True);
FContent.Parent := Self;   FContent.Align := alClient;
FEngine := TTyChromeEngine.Create(Self, FTitleBar);
```
- **Streaming:** `SetSubComponent(True)` + fixed `Name`s are mandatory — a user form descends from `TTyForm`, so its `.lfm` is an *inherited* stream and the reader matches these sub-controls to the live instances **by name** (`FindComponent`), never recreating them. No `GetChildren`/`DefineProperties` overrides are needed: designer-dropped user controls (`Owner = the form`, `Parent = FContent`) already stream as direct form-root `object` blocks and reattach to `FContent` on load via `SetParentComponent`.
- **Defensive `Loaded` override:** reparent any user child that ended up with `Parent = the form` (not `FContent`) into `FContent`, skipping `FTitleBar`/`FContent` themselves; idempotent. This neutralizes the one item not provable from LCL source — *which* parent the IDE designer picks on drop — and is also harmless at runtime.
- **Window-behavior overrides** (each calls `inherited` first, so published `OnMouseDown/...` stay free):
  - `MouseDown/MouseMove/MouseUp` → `FEngine.FormMouseDown/Move/Up` (edge-resize + hover cursor).
  - `DoChangeBounds` → `FEngine.HandleChangeBounds` (DPI rescale).
- **Published:** `TitleHeight` (re-lays the band), `BorderZone`, `ShowMinimize`, `ShowMaximize`; read-only `TitleBar` and `ContentPanel` accessors. Standard `TForm` events (`OnCloseQuery`, `OnClose`, …) are inherited.
- Title-bar mouse → drag/maximize is wired through the engine (see §5.4), not event slots.

### 5.3 `TTyChromeEngine` (new) — `tyControls.Form.pas`

`TTyChromeEngine = class(TObject)`; created with `(AForm: TCustomForm; ATitleBar: TTyTitleBar)`; owned/freed by `TTyForm`. Holds the state currently scattered in `TTyFormChrome`:

- **Drag-move:** `TitleBarMouseDown/Move/Up` (from `FDragging`, `FDragStart`) — ports [Form.pas:543-566](../../../source/tyControls.Form.pas#L543-L566).
- **Edge-resize + hover cursors:** `FormMouseDown/Move/Up` (from `FResizing`, `FResizeHit`, `FResizeStartBounds`, `FResizeStartMouse`, `BorderZone`) — ports [Form.pas:573-642](../../../source/tyControls.Form.pas#L573-L642).
- **Custom borderless maximize/restore:** `ToggleMaximize` (from `FMaximized`, `FSavedBounds`) — ports [Form.pas:669-693](../../../source/tyControls.Form.pas#L669-L693).
- **DPI rescale:** `HandleChangeBounds` rescales band height + button width on monitor-PPI change — ports [Form.pas:644-667](../../../source/tyControls.Form.pas#L644-L667), mirroring the `CapHAtPPI` idiom.
- The pure functions `TyHitTestBorder`, `TyResizeCursor`, `TyMaximizedBounds`, `TyRescaleChromeMetric` stay **unchanged** (already unit-tested).

The engine takes a `TCustomForm` reference that tests can inject without a real handle (preserving the current headless-injection test style).

### 5.4 `TTyTitleBar` changes

- **Retarget the chrome reference:** the `FChrome: TTyFormChrome` field + mouse-override delegation (currently [Form.pas:392-418](../../../source/tyControls.Form.pas#L392-L418)) now point at the **engine**: `FEngine.TitleBarMouseDown/Move/Up/DblClick`. `MouseDown/Move/Up/DblClick` still call `inherited` first (published mouse slots stay free — preserved behavior, preserved tests).
- **System buttons** (min/max/close) stay code-owned children, laid out in the right gutter. Their `OnClick` wires to: `Close` (close), `WindowState:=wsMinimized` (min), `FEngine.ToggleMaximize` (max/restore).
- **[Q2] Customizable content zone:**
  - `LayoutButtons` ([Form.pas:340-354](../../../source/tyControls.Form.pas#L340-L354)) and the caption rect ([Form.pas:378](../../../source/tyControls.Form.pas#L378)) currently hard-code `3 * FButtonWidth`. Replace with a **right inset = sum of VISIBLE buttons** (honor `ShowMinimize`/`ShowMaximize`).
  - Add a left inset (icon + caption) and override `AdjustClientRect` to return the middle strip, so aligned children (and a future menu host) auto-confine, mirroring [GroupBox.pas:43-47](../../../source/tyControls.GroupBox.pas#L43-L47).
  - Publish `Align`, `Anchors`, `ButtonWidth`; add `ShowIcon`/`Icon`.
  - **Scope note:** runtime-placed and *aligned* title-bar children work this cycle. Full design-time WYSIWYG for *free-placed* title-bar children has the same `alNone` caveat as the form did; it is **deferred** (a future inner title-bar content sub-panel, symmetric with `FContent`, if wanted).

### 5.5 `TTyCaptionButton`

Unchanged (kinds, glyphs, hover-only glyph). Its tests carry over as-is.

### 5.6 `TTyFormChrome` — **removed**

Delete the class, its registration, and its tests (porting coverage per §7). Remove from `tyControls.Design.pas` `RegisterComponents` and remove `TTyTitleBar` from the palette list (it is a sub-component now, not separately droppable).

## 6. Ribbon seam (Q3) — design-only this cycle

No ribbon control is built. The seam is locked so a later ribbon is purely additive:

1. **Reserved client region exists** — `FContent` (done by this architecture).
2. **Bands are plain `alTop` children** stacked above `FContent`, created in top-to-bottom order so each reserves its strip before `FContent` fills. The title bar is band 0; a ribbon is "just another band" below it.
3. **Reserve theme typeKeys** `TyRibbon` / `TyRibbonTab` / `TyRibbonGroup` (naming decision only — do not assign them to anything else). A later `TTyRibbon` will be a `TTyTabControl`-derived, chrome-agnostic `alTop` control that reserves its body via `AdjustClientRect` and works on native-bordered forms too.

## 7. Test strategy

**Keep unchanged** (pure functions / unaffected controls):
`TFormHelpersTest`, `TResizeCursorTest`, `TRescaleMetricTest`, `TCaptionButtonTest`, `TCaptionButtonPaintTest`, `TCaptionButtonHoverGlyphTest`.

**Adapt:** `TTitleBarTest` / `TTitleBarPaintTest` — update `TestButtonsRightAlignedAfterResize` for the visible-button inset; add a test that the caption/content inset honors `ShowMinimize/ShowMaximize`.

**Port `TTyFormChrome` tests → `TTyForm` + `TTyChromeEngine`:**
- Defaults (`TitleHeight=32`, `BorderZone=6`, show-flags) → `TTyForm` defaults.
- Drag-arm + title-bar mouse-slot isolation (`TestTitleBarMouseDownEventFiresAndDragStillWorks`) → engine drag via title-bar override.
- DblClick maximize isolation → engine `ToggleMaximize` via title-bar override.
- Restore branch (`TestOnRestoreFiresViaMaxRestoreAction`) → engine `ToggleMaximize` restore (headless, no handle).
- `TestFormChromeFreeWhileActiveNoDangling` / `TestChangeBounds*` / `TestFormChromeInstallPreservesBounds` become **moot** (no event-slot hijack, born `bsNone`); replace with engine teardown + a geometry test.

**New headless tests:**
- **Geometry:** construct `TTyForm`, realign, assert `FTitleBar.Top=0`, `Align=alTop`; `FContent.Align=alClient`; `FContent.Top = FTitleBar.Height`.
- **Load-bearing fact:** an `alNone` child placed directly on the form at `Top=0` overlaps the band (raw `Top`); the same child placed on `FContent` sits below the band — directly exercises the §4 path and documents *why* the ContentPanel exists.
- **Streaming round-trip:** build a `TTyForm` with a child parented to `FContent`, write to LRS, read back into a fresh instance; assert `FTitleBar`/`FContent` are **not** duplicated (name-matched), the user child reattaches under `FContent`, names stable. Mirror the TabControl streaming-test harness.

**Manual (Lazarus IDE — cannot be headless; document as a checklist):** the designer's default insertion parent for a dropped control (does it land in `FContent`?); live drag/drop visuals; the unthemed-vs-runtime title-bar skin.

**Baseline invariant:** keep the suite green (current: 0 failures + the known 15 win32 "error 1407" headless env errors). PPI=96.

## 8. Migration / removal checklist

- **`tyControls.Form.pas`:** add `TTyContentPanel`, `TTyForm`, `TTyChromeEngine`; retarget `TTyTitleBar` to the engine; apply Q2; delete `TTyFormChrome`.
- **`designtime/tyControls.Design.pas`:** drop `TTyFormChrome` and `TTyTitleBar` from `RegisterComponents` ([Design.pas:68-73](../../../designtime/tyControls.Design.pas#L68-L73)).
- **Theme:** add a `TyContentPanel` block to `DefaultTheme.pas` and `themes/*.tycss` (mirror `TyPanel`/`TyForm` background); document the reserved `TyRibbon*` typeKeys.
- **Demo (user's test bed — designer-driven, coordinate with user):**
  - **Native demo:** plain `TForm` showing the controls in a normal OS window.
  - **`TTyForm` demo:** `TChromeForm = class(TTyForm)`; drop `Chrome`/`TTyFormChrome`; content controls (e.g. `LblInfo`) move into the content area. The `.lfm` placement is done in the Lazarus designer by the user — this is also the manual WYSIWYG verification. The scaffolding `.pas` can be provided; final placement is the user's.
  - `examples/demo/mainform.*` and `examples/formchrome/umain.pas` also reference `TTyFormChrome` and must be migrated or removed so the projects compile.
- **Docs:** update `docs/controls/formchrome.md`, `titlebar.md`, `captionbutton.md`, `events.md`, `KNOWN_GAPS.md` to the new model.

## 9. Scope

**This cycle (build):** `TTyChromeEngine` extraction · `TTyForm` + `TTyContentPanel` (WYSIWYG, streaming, defensive `Loaded`, engine delegation) · `TTyTitleBar` Q2 content zone + visible-button math · remove `TTyFormChrome` · port/extend tests · split demo · reserve ribbon typeKeys · docs.

**Deferred (additive later):** `File > New > TTyForm` IDE template + ancestor-aware `.lfm` forward-compat guarantees · an inner title-bar content sub-panel for design-time-WYSIWYG title-bar content · actual `TTyMenuBar` / `TTyRibbon` / toolbar band controls.

## 10. Risks & open items

- **IDE default insertion parent (principal residual risk):** not provable from LCL source (the designer unit is outside `lcl`). Mitigation: defensive `Loaded` reparent (§5.2) + manual IDE check during implementation. If the designer drops onto the form root and the `Loaded` pass is insufficient at *design* time, a follow-up (e.g. surfacing `FContent` as the designated container) may be needed.
- **Inherited-stream cleanliness:** sub-control published properties must have sensible defaults so the inherited `.lfm` stays minimal and name-matching is clean.
- **Band ordering is load-bearing** once multiple bands exist: bands must be created/aligned top-to-bottom so each reserves its strip before `FContent`. Document the creation order.
- **Design-time skin is unthemed** (D6) — state explicitly in docs so reviewers don't read the unstyled band as a bug.
- **Demo breakage during transition:** removing `TTyFormChrome` breaks `chromeform`, `mainform`, and the standalone `formchrome` example simultaneously; the removal task must migrate/retire all three so the projects compile (coordinate demo `.lfm` work with the user).

## 11. Design decisions log

- **Controller → descendant (inverts prior rec):** verification showed the controller's covering-bug fix (runtime content-panel injection + child reparenting) is unbuilt, precedent-free, and fires mid-stream with no `Loaded` hook; `TComponent` cannot use `AdjustClientRect`. The descendant deletes that whole problem by construction.
- **ContentPanel over form-level `AdjustClientRect`:** forced by the §4 LCL finding (only aligned children are inset).
- **Engine as a separate object (not inline in `TTyForm`):** keeps `TTyForm` thin, preserves headless injection testing, and keeps the door open to a future controller without rework.
- **Drop custom lifecycle events:** `TTyForm` inherits the real `TForm` lifecycle; re-publishing `OnClose`/`OnCloseQuery` is unnecessary.
