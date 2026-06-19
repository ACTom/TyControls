# TyControls PageControl Redesign — Design (SP1)

**Date:** 2026-06-19
**Status:** Approved (decisions) — drafting spec for review

## Why

`TTyTabControl` was built as a *runtime* tabbed panel: its pages are `TTyPanel.Create(Self)` — owned by the control and streamed as nested objects under a `Tabs` collection. The Lazarus form designer only recognises **form-owned** controls as design surfaces, and the form's `GetChildren` skips any child whose `Owner ≠ Form`, so it never descends into our pages. Result: in the designer the page "doesn't exist" — you can't drop controls onto it, and they wouldn't stream if you could. Two design-time patches (`csDesignInteractive`, then `CMDesignHitTest`) couldn't fix that and broke the selection rubber-band on top.

Verified against the Lazarus reference (`custompage.inc:22`, `customnotebook.inc:156-159` & `:256`, `componenteditors.pas:1860`): `TPageControl` pages (`TTabSheet`) are created **Owner = the Form**, `Parent = the page control`, named, with `csAcceptsControls + csDesignFixedBounds + csNoDesignVisible + csNoFocus`, streamed via the default `GetChildren` (`Owner = Root`), switched in the designer through a **component editor** (Add/Delete/Show Page) and `csNoDesignVisible` toggling — the tab control itself is **not** `csDesignInteractive`.

Decision (user): **scrap `TTyTabControl` entirely** and build two purpose-built controls, mirroring Delphi/Lazarus's `TPageControl` vs `TTabControl` split. This spec covers **SP1** only.

## Scope

**SP1 (this spec):**
- `TTyCustomTabStrip` — the shared tab-header engine, extracted from the old `TTyTabControl` (layout, hover, header scroll, close-×, drag-reorder, active cross-fade, keyboard). Page-agnostic; abstract on tab data.
- `TTyTabSheet` — a page (a `TTyPanel`-like container) with a published `Caption` and the design-time `ControlStyle` flags.
- `TTyPageControl` — the real designer **container**: `TTyTabSheet` pages, form-owned + named, `GetChildren` streaming, `csNoDesignVisible` toggling, and a component editor (Add / Delete / Show Next / Show Previous Page).
- Delete `tyControls.TabControl.pas`; update the runtime + design-time packages, `Design.pas` (registration, component editor, palette icons), and migrate the demo's `mainform.lfm` (3 empty tabs → 3 `TTyTabSheet`).
- Tests: re-home the strip-engine tests onto the base/PageControl; add designer-integration tests.

**Out of scope (SP2, separate spec):** `TTyTabSet` (the pure strip, no pages) on the same base. Design-time **header click-to-switch** (fundamentally incompatible with a custom-drawn control + the designer; switching is via the component editor + Object Inspector).

## Architecture

```
TTyCustomTabStrip = class(TTyCustomControl)        // shared header engine
  abstract:  GetTabCount: Integer
             GetTabCaption(i): string
             GetTabClosable(i): Boolean
  hooks (virtual): DoSelectTab(i)        // subclass switches content
                   DoReorderTab(from,to) // subclass reorders its data
                   DoCloseTab(i)         // subclass removes the tab
  owns:      FTabIndex, FTabHeight, hover/close-hover, header+close rects,
             header scroll, drag-reorder gesture, cross-fade animator + timer
  paints:    the header strip; carves the body via AdjustClientRect
  events:    OnChange, OnChanging, OnTabClose, OnReorder
  geometry:  TyTabHeaderRect, TyTabCloseRect, HeaderRectShifted, scroll rects,
             TyDropIndexAt, TyDragThresholdPx (test seams, unchanged semantics)

TTyTabSheet = class(TTyCustomControl)              // one page
  published Caption           // the TAB label only — NOT painted on the page body;
                              // re-lays the host header on change
  renders a themed background surface (typeKey 'TyTabSheet') so dropped controls
    sit on a themed page; no caption/frame text on the body
  ControlStyle += csAcceptsControls, csDesignFixedBounds, csNoDesignVisible, csNoFocus
  Align := alClient; Visible := False
  SetParent: when Parent is TTyPageControl, register self with it (design-drop + load)

TTyPageControl = class(TTyCustomTabStrip)          // the container
  pages: TTyTabSheet children (Owner = the Form / LookupRoot, Parent = Self)
  GetTabCount = PageCount; GetTabCaption(i) = Pages[i].Caption; closable = FTabsClosable
  DoSelectTab(i)  -> ShowOnlyPage(i): Visible + csNoDesignVisible per page
  DoReorderTab    -> reorder the page child list
  DoCloseTab(i)   -> remove (free) the page (after OnTabClose veto)
  published ActivePageIndex (default -1, round-trips via LFM)
  public Pages[i], PageCount, ActivePage, AddTab(caption)/AddPage, RemovePage
  NO Tabs collection — the pages ARE the tabs
```

`TTyCustomTabStrip` and `TTyTabSheet` live in their own units (`tyControls.TabStrip.pas`, `tyControls.TabSheet.pas`); `TTyPageControl` in `tyControls.PageControl.pas`. Keeping them separate keeps each file focused and lets SP2's `TTyTabSet` reuse the base without pulling in page logic.

## Designer integration (the crux)

Mirrors the Lazarus reference exactly:

1. **Page ownership.** Pages are created `Owner := Self.Owner` (the form / LookupRoot; fall back to `Self` if `Owner = nil`), `Parent := Self`. This is what makes the designer treat a page as a real, droppable, persistable surface. (Reference: `customnotebook.inc:156-159`.)
2. **Naming.** The component editor's "Add Page" creates the page **through the IDE designer hook** so it gets a unique name (`TyTabSheet1`, …) and marks the form modified. Runtime `AddTab` needs no name.
3. **Streaming.** No `GetChildren` override — the default `TWinControl.GetChildren` returns child controls whose `Owner = Root`. Because pages (and controls dropped on them) are form-owned, they stream the standard way: pages nest under the page control, their children nest under each page. (Reference: `TCustomTabControl` does not override `GetChildren`.)
4. **Load reconciliation.** `TTyTabSheet.SetParent` registers the page with its `TTyPageControl` parent (adds to the page list, relays the header) — handling both a design-time drop and a streamed load. `TTyPageControl.Loaded` then applies the streamed `ActivePageIndex`.
5. **Active-page visibility.** `ShowOnlyPage(i)` sets `Visible := (j = i)` and toggles `csNoDesignVisible` (set on inactive pages, cleared on the active one) so the designer shows only the active page. (Reference: `UpdateDesignerFlags`.)
6. **The page control is NOT `csDesignInteractive`** and has no `CMDesignHitTest` — so the designer's normal selection/drag/drop on the control works. Switching pages at design time is done via the component editor verbs and the `ActivePageIndex` property.
7. **The page control is NOT `csAcceptsControls`** (only the pages are). The designer resolves the deepest `csAcceptsControls` control at the cursor, so a drop on the visible page area lands on the `TTyTabSheet`, never directly on the strip — mirroring `TCustomTabControl` (`ControlStyle := []`).

### Component editor — `TTyPageControlEditor`

Verbs (mirrors `TTabControlComponentEditor`):
- **Add Page** — create a `TTyTabSheet` via the hook, name it, make it active.
- **Delete Page** — delete the active page via `Hook.DeletePersistent`.
- **Show Next Page / Show Previous Page** — move `ActivePageIndex`.

Registered in `Design.pas` via `RegisterComponentEditor(TTyPageControl, TTyPageControlEditor)`.

## Public API (TTyPageControl) — mapped from TTyTabControl

| Old (TTyTabControl) | New (TTyPageControl) |
|---|---|
| `Tabs: TTyTabCollection` (captions+pages) | **removed** — pages carry their own `Caption` |
| `AddTab(caption): TTyPanel` | `AddTab(caption): TTyTabSheet` (alias `AddPage`) |
| `RemoveTab(i)` | `RemovePage(i)` |
| `Pages[i]: TTyPanel` | `Pages[i]: TTyTabSheet` |
| `TabCount` | `PageCount` |
| `TabIndex` (published, def -1) | `ActivePageIndex` (published, def -1) + `ActivePage: TTyTabSheet` |
| `TabHeight`, `TabsClosable` | unchanged |
| `OnChange/OnChanging/OnTabClose/OnReorder` | unchanged (on the base) |
| `AnimationsEnabled` | unchanged |
| header geometry test seams | unchanged (on the base) |

## .lfm format + demo migration

New format (identical shape to `TPageControl`):
```
object TyPageControl1: TTyPageControl
  ActivePageIndex = 0
  object TyTabSheet1: TTyTabSheet
    Caption = 'Tab 1'
    <dropped controls nest here>
  end
  object TyTabSheet2: TTyTabSheet
    Caption = 'Tab 2'
  end
end
```
Breaking change (no back-compat shim — single trivial consumer). Migrate `examples/demo/mainform.lfm`: the current `TabCtrl1: TTyTabControl` with `Tabs = <item 'Tab 1' …>` becomes `TabCtrl1: TTyPageControl` with three nested empty `TTyTabSheet` objects and `ActivePageIndex = 1` (was `TabIndex = 1`). Demo code (`mainform.pas`) references only `TabCtrl1` as a field — verify no `.Tabs`/`AddTab` usage; adjust if any.

## Design.pas / packages

- `RegisterComponents('TyControls', [...])`: remove `TTyTabControl`; add `TTyPageControl` and `TTyTabSheet`. (`TTyTabSheet` is registered so it can be selected in the OI, like `TTabSheet`; it is created via the component editor, not dropped from the palette — acceptable, matches `TTabSheet`.)
- Remove the `TTyTabControlEditor` ("Edit Tabs…") and its `Tabs` collection property editor; add `RegisterComponentEditor(TTyPageControl, TTyPageControlEditor)`.
- Update `uses` (remove `tyControls.TabControl`, add the three new units).
- Runtime package `tyControls.lpk` and `tycontrols_dt.lpk`: swap the unit list.
- **Palette icons:** remove `TTyTabControl`, add `TTyPageControl` + `TTyTabSheet` in `genicons.lpr` Glyphs[], `gen-icons.ps1` $classes, and `test.paletteicons.pas` CClasses, then regenerate. The drift-guard added to `gen-icons.ps1` enforces this set == `RegisterComponents`. (Reuse the old TabControl glyph for `TyPageControl`; give `TyTabSheet` a single-page glyph.)

## Removal of TTyTabControl

Delete `source/tyControls.TabControl.pas` and its tests (`test.tabcontrol*.pas` — collection/streaming/scroll/reorder/closehover). The header-engine behaviour they covered is re-tested against `TTyCustomTabStrip`/`TTyPageControl` via access subclasses.

## Testing

**Headless (fpcunit):**
- Strip engine (re-homed): header geometry, hover, scroll overflow + `ScrollTabIntoView`, drag-reorder (`TyDropIndexAt`/threshold), close-× hit + `OnTabClose` veto, cross-fade animation seams, keyboard nav — driven via a `TTyCustomTabStrip` access subclass and via `TTyPageControl`.
- PageControl: `AddTab` returns a `TTyTabSheet` whose `Parent = the control`; `Owner = the control's Owner` (form) when the control has an owner; `Pages[i]`/`PageCount`/`ActivePage`/`ActivePageIndex` behave; switching toggles page `Visible`; `ShowOnlyPage` toggles `csNoDesignVisible`; `OnChange`/`OnChanging` veto.
- TTyTabSheet: `Caption` published; constructor sets the four `ControlStyle` flags + `Align=alClient`; `SetParent` registers with a `TTyPageControl` parent.
- Streaming round-trip: build a form with a `TTyPageControl` + 2 pages + a control on page 2 in code, stream to a string via `TWriter`, read back via `TReader`, assert the pages and the nested control survive with correct parents and `ActivePageIndex`. (This is the regression guard for the whole fix.)
- Palette `.lrs`: existing `test.paletteicons` after the class-set update.

**Manual (IDE only — cannot be headless):** drop `TTyPageControl`, use Add Page, drop a control on a page, switch pages, save/reload, confirm persistence; rebuild `tycontrols_dt.lpk` + restart Lazarus.

## Risks / notes

- **Largest change this area has seen.** The base extraction (~1000 lines of header logic) is the bulk; behaviour is preserved (it's re-homed, not rewritten) and guarded by the re-homed tests.
- **Load reconciliation order** (pages stream before `Loaded`) is the subtle part — covered by the `TWriter`/`TReader` round-trip test.
- No backward compatibility with the old `.lfm` page format — only the demo used it (3 empty tabs), migrated here.
- `TTyTabSheet` registered but not palette-dropped (created via the editor) — matches `TTabSheet`.
