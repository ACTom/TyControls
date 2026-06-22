# TTyForm Window Rounded Corners + Drop Shadow — Design

**Date:** 2026-06-20
**Status:** Approved (design) — awaiting spec review → plan

## Goal

Give the borderless `TTyForm` real **rounded window corners** and a real **drop shadow**, both
defined from the `.tycss` theme. "Real" = at the OS-window level (the window silhouette is
actually rounded / actually casts a shadow), not just painted inside the client bitmap.

## The hard constraint (and what it rules out)

`TTyForm` is borderless (`BorderStyle = bsNone`) and hosts **windowed child controls**
(`TTyCustomControl = class(TCustomControl)` → real child HWNDs on Windows). Therefore the
"render the whole window into one per-pixel-alpha ARGB bitmap" approach (`UpdateLayeredWindow`)
is **infeasible** — child HWNDs cannot composite into a layered window's bitmap. So on Windows
we use **OS-assisted** mechanisms only (DWM / window region), never layered windows. We do NOT
change the windowed-child architecture (out of scope, breaks everything).

Key relief: the **native shadow does NOT need a layered window** — DWM (`DwmExtendFrameIntoClientArea`)
and macOS (`NSWindow.hasShadow`) draw the shadow around a normal window with child HWNDs.

## Decision: round corners only where they're anti-aliased

(User decision.) Jagged 1-bit region corners (Win10/GTK2) look worse than square. So:
**round only where the OS gives anti-aliased corners** (Win11, macOS). Older Windows stay
**square** but still get a native (rectangular) shadow.

## Platform matrix

| Platform | Rounded corners | Shadow | Confidence |
|---|---|---|---|
| **Win 11** (22000+) | DWM corner preference (AA). `border-radius` px → `ROUND` (≈8) / `ROUNDSMALL` (≈4) / `DONOTROUND` | **free** with the corners | high |
| **Win Vista/7/8/10** | **square** (no jagged region) | `DwmExtendFrameIntoClientArea` native soft shadow (needs DWM composition on) | **medium — see risk R1** |
| **Win XP** | square | none (no DWM compositor) → fall back to the existing software shadow, or none | high |
| **macOS** (Cocoa) | `contentView.layer.cornerRadius` + `masksToBounds` (AA, exact px) | `NSWindow.hasShadow := True` | high |
| **Linux** (GTK2/GTK3/Qt5/Qt6) | **extension point only — NOT implemented now** | same | n/a |

**No Win10+ floor:** every DWM call is resolved via **runtime `GetProcAddress`** from a
dynamically `LoadLibrary`'d `dwmapi.dll` — never a static `external 'dwmapi.dll'` import (which
would make the EXE fail to launch on XP). On XP the lookups fail → we skip DWM and fall back.
Capability is *probed*, not version-hardcoded: we just call `DwmSetWindowAttribute(hwnd, 33, …)`
(corner preference) and check the `HRESULT` — success ⇒ Win11 path; failure ⇒ try the
`DwmExtendFrameIntoClientArea` shadow path; both absent ⇒ square + software/no shadow.

### Linux extension point (designed, not built)

The chrome unit is **widgetset-aware**: `{$IFDEF LCLGTK2}`, `{$IFDEF LCLGTK3}`, `{$IFDEF LCLQT5}`,
`{$IFDEF LCLQT6}` branches exist as documented stubs so Linux paths slot in without rework.
The future Qt path is the promising one and is documented in the stub: because Qt child widgets
are lightweight (they composite into the top-level surface — no separate-native-window problem
like Win32 HWNDs), Qt can do `Qt::WA_TranslucentBackground` + `FramelessWindowHint` + app-painted
**AA** corners + an app-painted **custom** soft shadow. GTK2 (jagged region only) and GTK3 (no
window shape) cannot meet the AA-only rule and stay square. All Linux work is deferred until a
real Linux+widgetset verification environment exists.

## CSS / theme tokens

```css
TyForm {
  border-radius: 8px;     /* ALREADY parsed (StyleModel ApplyBorderRadius -> TTyStyleSet.BorderRadius).
                             Window uses the UNIFORM BorderRadius. Win11 -> enum, macOS -> exact px,
                             older Win/Linux -> ignored (square). */
  window-shadow: true;    /* NEW boolean token: opt into the OS-native window shadow.
                             On/off only — the OS owns the look (blur/color/spread not customizable,
                             because a custom-styled shadow would need the layered approach we can't use). */
}
```

`window-shadow` parsing (engine change): add a `window-shadow` property handler in
`tyControls.StyleModel` (parse `true`/`false`), a `WindowShadow: Boolean` field + a present-flag
(`tpWindowShadow`) in `TTyStyleSet` (`tyControls.Types`). It resolves like any other property so
`TTyForm` reads it from its resolved style. (Distinct from the existing raster `shadow` token,
which stays control-level / inside-frame.)

## Architecture

New unit **`source/tyControls.WindowEffects.pas`** — keeps all platform/widgetset mess out of
`Form.pas`. Single cross-platform entry:

```pascal
unit tyControls.WindowEffects;
{$mode objfpc}{$H+}
interface
uses Classes, Controls, Forms;
type
  TTyWindowEffect = record
    RadiusPx:  Integer;   // device px; 0 = square
    Shadow:    Boolean;   // window-shadow token
    Maximized: Boolean;   // when maximized -> force square (corners would show desktop)
  end;
{ Apply rounded corners + shadow to AForm's native window per the platform/widgetset.
  Safe to call repeatedly (on show, theme change, DPI change, maximize/restore).
  No-op where unsupported. Never raises — capability is probed, failures degrade. }
procedure TyApplyWindowEffects(AForm: TCustomForm; const AEffect: TTyWindowEffect);
implementation
  // {$IFDEF WINDOWS} ... dynamic dwmapi (DwmSetWindowAttribute corner pref + DwmExtendFrameIntoClientArea
  //                       + DwmIsCompositionEnabled), all via GetProcAddress ... {$ENDIF}
  // {$IFDEF LCLCOCOA} ... NSView(AForm.Handle).window: layer.cornerRadius + masksToBounds + setHasShadow ...
  // {$IFDEF LCLGTK2/LCLGTK3/LCLQT5/LCLQT6} ... documented stubs (no-op) ...
end.
```

Windows internals (all dynamic, all probed):
- Load `dwmapi.dll` once; `GetProcAddress` for `DwmSetWindowAttribute`, `DwmExtendFrameIntoClientArea`,
  `DwmIsCompositionEnabled`. Cache the addresses (nil = unavailable → degrade).
- **Corners:** if `RadiusPx > 0` and not maximized → `DwmSetWindowAttribute(hwnd, 33 {CORNER_PREFERENCE}, @pref, 4)`
  with `pref = ROUNDSMALL` (radius ≤ ~5 device px) else `ROUND`. If the call fails (pre-Win11) → leave square.
  Maximized → `DONOTROUND`.
- **Shadow:** if `Shadow` and `DwmIsCompositionEnabled` → `DwmExtendFrameIntoClientArea(hwnd, MARGINS(1,1,1,1))`.
  Disable (margins 0) when `Shadow=False`.

macOS internals (`{$IFDEF LCLCOCOA}`): cast `AForm.Handle` (a `TCocoaWindowContent`/`NSView`) →
`.window` (`NSWindow`); set `contentView.layer.cornerRadius := RadiusPx`, `masksToBounds := True`
(0 when maximized); `setHasShadow(Shadow)`. (A prior commit `a3ea584` already did `setHasShadow`;
confirm it's present in HEAD and fold it in.)

## Integration into TTyForm

1. Build a `TTyWindowEffect` from the resolved `TyForm` style: `RadiusPx := P.Scale(Style.BorderRadius)`
   (device px), `Shadow := Style.WindowShadow`, `Maximized := WindowState = wsMaximized`.
2. Call `TyApplyWindowEffects` from:
   - **after the handle exists + first shown** (a `DoShow`/`Loaded` hook — the HWND/NSWindow must exist),
   - **`ApplyChromeTheme`** (theme switch may change radius/shadow — re-apply, `Form.pas:~1059`),
   - **DPI change** (radius is device-px → rescale),
   - **maximize/restore** — hook the existing `TTyChromeEngine.ToggleMaximize` (`Form.pas:~681`) so corners
     go square when maximized and round again when restored.
3. **Reconcile with the existing software paint** (`TTyForm.Paint`, `Form.pas:969-1021`):
   - The form always paints a **rectangular** background; the OS clips it to the rounded silhouette where the
     window is actually rounded (Win11/macOS). Where the window stays square (older Windows/Linux), the
     rectangular paint matches the square window — no fake inner rounding. So the painted bg matches the real
     window silhouette on every platform, and the existing software corner-masking for the *window* background
     is removed.
   - When `window-shadow` is active (native shadow on), **disable the software drop shadow** the form draws,
     to avoid a double shadow. (Software shadow remains the XP/compositionless fallback.)

## Risks

- **R1 — non-Win11 native shadow on a pure `WS_POPUP` (bsNone) window.** `DwmExtendFrameIntoClientArea`
  reliably produces a shadow on the common "borderless" pattern that keeps `WS_THICKFRAME` + handles
  `WM_NCCALCSIZE`; on a *pure* `WS_POPUP` (which `bsNone` yields) the shadow may not appear without a
  style tweak. Mitigation: implement + **verify on a real Win10 box**; if it doesn't show, either (a) add a
  minimal `WM_NCCALCSIZE`/style adjustment guarded so it doesn't disturb the existing `TTyChromeEngine`
  resize zones, or (b) accept the **software** shadow on pre-Win11 and reserve native shadow for Win11/macOS.
  Spec leaves (b) as the safe default if (a) proves invasive.
- **R2 — radius enum on Win11.** `border-radius: 6px` can't be honored exactly; it maps to round/small.
  Document the clamp.
- **R3 — verification is manual.** None of the visual results are headless-testable. The user verifies on
  real Win11 / Win10 / macOS.

## Testing

- **Headless (fpcunit):** `window-shadow` parses to `TTyStyleSet.WindowShadow` (true/false/absent); the
  px→enum mapping helper (`RadiusToCornerPref`) returns ROUNDSMALL/ROUND/DONOTROUND for representative
  inputs; `TyApplyWindowEffects` is a safe no-op when the form has no handle / on an unsupported platform
  (does not raise). These exercise the pure logic without a GPU/compositor.
- **Manual (user):** Win11 (AA corners + shadow), Win10 (square + shadow, or software fallback per R1),
  macOS (AA corners + shadow), maximize→square→restore, theme switch changes radius live, HiDPI scaling.

## Out of scope

- Linux implementation (extension-point stubs only; Qt path documented for the future).
- Jagged region corners on old Windows / GTK2 (rejected by the AA-only rule).
- Custom-styled (blur/color/spread) Windows/macOS native shadow (the OS owns it; a custom one needs the
  layered approach blocked by windowed children).
- Changing the windowed-child control architecture.
