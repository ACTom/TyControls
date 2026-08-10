# Reparent TTyVirtualImageList to TCustomImageList

Status: **planned, not started.** The working tree is at the pre-refactor baseline
(6197 tests, 0 failures, both packages clean). One partial attempt was made and reverted --
see "Why it was reverted".

## The decision

`TTyVirtualImageList` descends from `TCustomImageList` instead of `TTyComponent`. It KEEPS its
on-demand rendering (`RenderIndex(i, anyPx)`) and ADDITIONALLY bakes rasters at registered
widths so stock LCL controls can consume it. Every image-list property in the library widens to
`TCustomImageList`, and consumers pick a path at draw time: ours -> vector on demand; anything
else -> LCL `Draw`/`DrawForPPI`.

Widening is not a breaking change for existing forms (a `TTyVirtualImageList` still assigns);
it is purely additive for users, and it means every one of those 21 properties accepts a stock
or third-party list for the first time.

### What it dissolves

- `TTyTreeView.Images` (LCL-typed, no name lookup) -- the library's own tree can finally take
  the library's own list.
- `TTyLCLImageList` -- the bridge becomes unnecessary and retires into this class.
- `TTyShellTreeView`'s owned list, `TTySelectPathForm`'s bare `TImageList`.
- The Ty half of `TTyMenu`'s two-path row drawing.

### What it does NOT dissolve

LCL's own `TMenuItem.ImageIndex`. That object is not ours; there is nowhere to put a name
without subclassing `TMenuItem` or keeping a side map. **Document as a boundary; do not fake it.**

## Verified by experiment (do not re-derive)

A patched copy with `TTyVirtualImageList = class(TCustomImageList)` COMPILES: FPC 3.2.2 + LCL
4.4, 0 errors, 1 warning (the `RemoveAllHandlersOfObject` hiding, item 3 below).

- `TCustomImageList` and `TLCLComponent` publish NOTHING -- every property is `public`
  (imglist.pp:266-430, lclclasses.pp:45-63). The earlier objection that reparenting drags in
  published `Width`/`Masked`/`DrawingStyle` was wrong: that is `TImageList` (controls.pp:2492).
- The IDE's image-list editor is registered on `TImageList`, not `TCustomImageList`
  (imagelisteditor.pp:1200) -- descending does not inherit LCL's bitmap editor.
- Resolutions are created with no Owner (imglist.inc:1184), so they never reach `Notification`,
  `Components[]` or the `.lfm`.
- Nothing in source/, designtime/ or tests/ depends on the current ancestry.

## The six corrections that MUST be built in

Each was measured, not reasoned. Skipping any of them ships a silent defect.

1. **`Count` must mean one thing.** `function Count` (= `Names.Count`) HIDES the inherited
   non-virtual property with no diagnostic: measured 2 through a `TTyVirtualImageList`
   reference and 0 through a `TCustomImageList` one, same object. Delete the function; the
   baked count is the count; spell `Names.Count` where the name list is meant. ~26 call sites
   are bounds checks of the form `AIndex < Images.Count` and behave identically once the list
   always bakes.

2. **Register the base width FIRST.** `Count` -> `GetResolution(FWidth)` and `GetResolution`
   CREATES a resolution when that width is not registered (imglist.inc:1174-1199) -- measured
   `ResolutionCount` 2 -> 3 from a single `Count` call. With the base width registered first,
   `Count` is a read. This invariant deserves its own test.

3. **`RemoveAllHandlersOfObject` must be `override`.** `TLCLComponent` declares it virtual
   (lclclasses.pp:57); the current declaration hides it (the one compile warning).

4. **`DefaultSize` becomes a VIEW of `Width`.** They are independent today: measured
   `DefaultSize = 20` while `Width = Height = 16`, i.e. the same object drawing at two
   different sizes depending on the reference type. One state, two spellings.

5. **Suppress the pixel blob via `DefineProperties`, not via empty `WriteData`.**
   `TComponent.DesignInfo` is PUBLIC (classesh.inc:1987), so the override can re-register
   Left/Top itself and drop `Bitmap`/`BitmapAdv` entirely. Empty `WriteData` overrides leave
   `Bitmap = { }` AND `BitmapAdv = { }` behind (measured on the real `TTyLCLImageList`), which
   would rewrite every existing form the first time the IDE saved it.
   **`TTyLCLImageList` currently uses the inferior method and its comment claims the residue is
   unavoidable. That comment is wrong; fix it when this lands.**

6. **`Version` recovery is TWO links.** Re-declare the published read-only property AND add
   `RegisterPropertyEditor(TypeInfo(string), TTyVirtualImageList, 'Version', TTyVersionEditor)`
   -- `test.version`'s `InheritsFromAnEditorBase` checks ancestry against the bases it parses
   out of Design.pas, and the class will no longer descend from `TTyComponent`.

## Hazards to design around

- **`Images.Width := 24` CLEARS the baked list** (SetWidth -> SetWidthHeight -> Clear,
  imglist.inc:1993-1999) while `Names.Count` is unchanged. `Width`/`Height` are public and
  non-virtual, so this cannot be prevented -- only refilled from. Correction 4 routes the
  library's own writes through one place; a user's raw `Width :=` remains a documented trap
  (already pinned for the bridge by tests/test.lclimagelist.pas).
- **A drifting pixel size permanently grows the list.** `ResolutionForPPI[w, ppi, 1]` CREATES
  the resolution: measured `ResolutionCount` 4 -> 5 for a 20px request against [16,24,32,48].
  Every converted call site passes exactly such a number (`rowH - Scale(6)`, `AHeaderH -
  ScaleI(4)`, ...). The shared helper must route through **registered** widths
  (`FindResolution`), never hand a raw pixel size to `ResolutionForPPI`.
- **`HeaderImageList: TTyVirtualImageList; virtual`** (Grid.pas:1451). FPC has no covariant
  return types, so widening it breaks every override, in-tree and downstream.
  `tests/test.parity.grid.members.pas:199` fails to COMPILE -- loud, which is the good case.
  Same shape, non-virtual: ListView.pas:425/433, AdvancedListBox.pas:45/97,
  ShellComboBox.pas:155.
- **Hi-DPI, stock consumers.** `TScaledImageListResolution.Draw` routes to the NON-virtual
  `StretchDraw` whenever the canvas scale factor is not 1 (imglist.inc:129-142), so on a scaled
  Cocoa/Qt canvas a stock consumer gets the baked raster STRETCHED. There is no hook. Ours
  take the vector path and are unaffected. Unverified off win32 -- only win32 LCL units are
  built here.
- **`TTyHeader` is a `TPersistent`** (Columns.pas:305) with a bare-field `Images` write: no
  setter, no FreeNotification. The dangling reference already exists; widening neither creates
  nor fixes it. It is shared by `TTyCustomGrid` and `TTyListView`, so one retype moves two
  controls.
- **`TTyCustomGrid.SetImages` has no FreeNotification at all** (Grid.pas:5687-5692) -- a
  pre-existing dangling-pointer bug worth fixing while in there.

## Order of work

1. The class: reparent + fill logic + corrections 1-6. Full suite must stay green.
2. The shared draw/measure helper, routed through registered widths.
3. Widen the 21 properties, control by control, each with its own suite run.
4. Retire `TTyLCLImageList`; its tests move over as regression guards.
5. Retrofit `TTyShellTreeView`, `TTySelectPathForm`, the menu's Ty branch.
6. Make the bundled pack a droppable image list.
7. Then, and only then, the `ImageName` rollout -- most sites get simpler after this.

## Why it was reverted

The first attempt landed the declaration change before the members that make it compile, and
finishing it properly needs more room than was left. A half-migrated tree is worse than none:
the class would have been reparented with `function Count` still hiding the inherited property
-- precisely the silent defect correction 1 exists to prevent. Reverted to the green baseline;
the findings above are the durable part.
