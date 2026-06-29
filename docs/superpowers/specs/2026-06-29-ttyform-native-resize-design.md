# TTyForm Native Window Resize (cross-platform) — Design Spec

**Date:** 2026-06-29
**Component:** `TTyForm` / `TTyChromeEngine` (`source/tyControls.Form.pas`), with `ApplyWindowEffects` (`tyControls.WindowEffects`).
**Branch:** `feat/ttyform-resize` (off `main`) — independent of the ③ TreeView work.

## 1. Goal

Make the borderless `TTyForm` **edge-resizable on every platform**, with native feel where the OS allows, content still drawn to the window edge, plus a published **`Resizable`** property to opt out (fixed-size windows). Today neither the demo nor any real `TTyForm` can be resized — this is a real bug, not a showcase mistake.

## 2. Background — why resize is broken today

`TTyForm.SetupChrome` sets `BorderStyle := bsNone` and creates a `TTyChromeEngine`. Edge-resize is driven by the **form's own** `MouseDown`/`MouseMove` (overridden in `TTyForm`, forwarded to `TTyChromeEngine.FormMouseDown`/`FormMouseMove`), which hit-tests the edge via `TyHitTestBorder(Rect(0,0,Width,Height), pt, FBorderZone)` and then drags `FForm.BoundsRect`.

The bug: a normal `TTyForm` fills its client area with child controls (`alClient` content + status bar + the title bar). Child controls are separate windowed HWNDs that capture the mouse within their bounds, so **the form's own `MouseMove`/`MouseDown` never fire near the edges** → `TyHitTestBorder` never triggers → no resize cursor, no resize. There is **no `WM_NCHITTEST` handler and no content gutter**, so the edges are unreachable. Confirmed: demo + the TreeView showcase both cannot resize.

## 3. Architecture

### 3.0 The two sub-problems

1. **Reception** — the form must "see" the mouse at its edges (currently blocked by full-client children).
2. **Execution** — once an edge press is detected, actually resize the window.

Platforms differ mainly in (1). The design keeps the shared edge math and gives each widgetset a strategy.

### 3.1 Shared

- Keep `TyHitTestBorder` + `FBorderZone` (the edge-zone geometry) — reused by every platform path and the fallback.
- New published property **`Resizable: Boolean`** (default `True`) — see §3.6.
- A per-widgetset resize strategy selected by `{$IFDEF}` in `TTyForm` (Win32 / GTK2 / Qt5 / Qt6 / Cocoa), with the existing engine drag as the universal fallback.

### 3.2 Windows (Win32) — native non-client resize  *(primary, build + test now)*

The modern custom-chrome technique (Chrome / VS Code / WinUI):

- **Window style:** after the handle exists (and on `Resizable` change), ensure `WS_THICKFRAME` is in the style (`GetWindowLong`/`SetWindowLong` + `SetWindowPos(..., SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER)`). `WS_THICKFRAME` gives the OS a real sizing border + Aero-snap + native maximize.
- **`WM_NCCALCSIZE`:** intercept (override `TTyForm.WndProc`, or a message method) and collapse the non-client area so the client fills the whole window (the title bar/border chrome disappears) while the `WS_THICKFRAME` sizing border remains a hit-testable **non-client** region. (Exact return value — full 0 vs. keep 1px — tuned on a real machine against the DWM rounded-corners/shadow from `ApplyWindowEffects`; documented as a risk in §6.)
- **`WM_NCHITTEST`:** return `HTLEFT/HTRIGHT/HTTOP/HTBOTTOM/HTTOPLEFT/HTTOPRIGHT/HTBOTTOMLEFT/HTBOTTOMRIGHT` for the edge zones (reuse `TyHitTestBorder` mapped to window coords), `HTCAPTION` for the title-bar drag band, `HTCLIENT` elsewhere. When `not Resizable` → never return edge codes (only `HTCAPTION`/`HTCLIENT`).
- **Why this fixes reception:** the sizing border is genuine **non-client** area; child controls live in the client area and cannot cover it, so the OS receives the edge hits regardless of `alClient` content. Execution is the OS's native resize.
- **Engine on Windows:** disable the engine's manual `FormMouseMove` resize (native owns it) to avoid double-handling. Drag may also move to native via `HTCAPTION` (gives Aero-snap + shake) — *decision: prefer native `HTCAPTION` drag on Windows*; keep the engine drag for the title bar only if a regression appears.
- **WndProc discipline:** the override must call `inherited WndProc` for everything it doesn't handle; keep it tiny. (Unrelated to the dwarf-streaming hang — no streaming here — but keep the chrome init path unchanged.)

### 3.3 Linux (GTK2 / Qt5 / Qt6) — WM handoff + gutter  *(hooks now, real-machine verify later)*

- **Reception (1):** a thin **resize gutter** — `TTyForm.AdjustClientRect` insets the client rect by `FBorderZone` px on each side when `Resizable`, so `alClient` children stop short of the edge and the form's edge strip receives the mouse. The form already paints its themed background (`ITyThemedBackground`) so the gutter is just window background. *Gutter is applied only on widgetsets that need it (`{$IFDEF LCLGtk2 or LCLQt5 or LCLQt6}`), NOT on Windows/Cocoa.*
- **Execution (2):** in `FormMouseDown` at an edge (`TyHitTestBorder <> bhNone`), instead of the manual `BoundsRect` drag, hand off to the compositor:
  - **GTK2:** `gtk_window_begin_resize_drag(GtkWindow, GdkWindowEdge, button, root_x, root_y, timestamp)`.
  - **Qt5/Qt6:** `QWidget.windowHandle.startSystemResize(Qt::Edges)` (Qt ≥ 5.15; Qt6 ✓).
  - Native handle obtained from the LCL widgetset (`TQtWidget`/`GtkWidget` via `Handle`).
- **Wayland:** resize via `_NET_WM_MOVERESIZE` works (compositor-driven) — distinct from the known Wayland *positioning* limitation ([[form-chrome-architecture]]), which is unaffected here.
- **Fallback:** if `startSystemResize` is unavailable (Qt < 5.15), the engine's manual `BoundsRect` drag still runs (gutter provides reception).

### 3.4 macOS (Cocoa)  *(hook now, real-machine verify later)*

- Set the `NSWindow` `styleMask` to include `NSWindowStyleMaskResizable` when `Resizable` (clear it otherwise). A borderless + resizable `NSWindow` lets the window server handle edge reception and resize natively — no gutter needed. `NSWindow` reached via the LCL Cocoa handle.

### 3.5 Fallback (unknown/other widgetset)

Existing engine manual resize + the gutter for reception + `FormMouseMove` cursor feedback. Behaves as designed (just now actually reachable, thanks to the gutter).

### 3.6 The `Resizable` property

```pascal
property Resizable: Boolean read FResizable write SetResizable default True;
```
`SetResizable` re-applies the active platform strategy:
- **Windows:** add/remove `WS_THICKFRAME` + `SWP_FRAMECHANGED`; `WM_NCHITTEST` stops returning edge codes.
- **Linux:** toggle the `AdjustClientRect` gutter (+ `Realign`/`Invalidate`); the edge handoff is gated.
- **macOS:** toggle `NSWindowStyleMaskResizable`.
- **All:** the engine's `TyHitTestBorder` resize is gated; **maximize is disabled** when `not Resizable` (a fixed window can't maximize) — hide/disable the title-bar max button (drive `ShowMaximize` or the button's `Enabled`) and gate the title-bar double-click maximize.

Design-time: published so it persists in the `.lfm`; applied at runtime (the chrome paths already guard `csDesigning`).

### 3.7 Events / surface summary

New published `Resizable: Boolean` (default True). No other public API change. Internal: a `TTyForm.WndProc`/message handlers on Win32, `AdjustClientRect` gutter on GTK/Qt, `styleMask` tweak on Cocoa, native-handoff in the engine's edge path, all `{$IFDEF}`-guarded. `TyHitTestBorder` unchanged.

## 4. Testing strategy

- **Pure / headless:** `TyHitTestBorder` is already covered. Add tests that the engine returns `bhNone` (no resize) when `Resizable=False`; that `AdjustClientRect` insets by `FBorderZone` **only** on gutter widgetsets **and** only when `Resizable` (guard via the same IFDEF or a test seam). Regression: existing `TTyForm`/chrome tests + the 1413/0/11-style baseline stay green; window effects (corners/shadow) still apply.
- **Real-machine (can't be headless — needs a window manager):** Windows matrix — resize from all 4 edges + 4 corners, the resize cursors, Aero-snap, double-click-title maximize + the max button, a DPI change mid-session, multi-monitor; title-bar drag still works; content reaches the edge; `Resizable=False` → no resize, no maximize, drag + close still work. Linux (GTK + Qt, X11 + Wayland) and macOS deferred to those machines.

## 5. Key decisions

1. **Windows = native NC resize** (`WS_THICKFRAME` + `WM_NCCALCSIZE` + `WM_NCHITTEST`) — best UX, solves reception via the NC border, content to the edge, native snap/maximize.
2. **Linux/macOS = OS handoff** (`begin_resize_drag` / `startSystemResize` / resizable `styleMask`); Linux needs a thin gutter for reception.
3. **`Resizable: Boolean` (default True)** opts out → fixed window + maximize disabled. (Conceptually the `bsSizeable` vs `bsSingle` choice that `BorderStyle` can no longer express on a `bsNone` form.)
4. **Keep `TyHitTestBorder` + the engine** as the universal fallback.
5. **Windows-first:** built + real-machine tested now; Linux/macOS hooks implemented but verified later on those machines.
6. **Don't regress** window effects (DWM corners/shadow), maximize, multi-monitor DPI, or the title-bar drag; `WndProc` override minimal + always chains `inherited`.

## 6. Risks / open questions

- **`WM_NCCALCSIZE` × DWM corners/shadow:** the exact client-rect adjustment that keeps `ApplyWindowEffects`' rounded corners + shadow without a 1px top-line artifact — needs real-machine iteration (a known fiddly area of custom-frame Windows apps).
- **Native maximize vs the engine's `FMaximized` borderless-maximize:** on Windows, prefer native (`HTCAPTION` + `SW_MAXIMIZE`) and reconcile/retire the engine's `FMaximized` bookkeeping so the max/restore button + state stay correct.
- **LCL native-handle access** for `startSystemResize` / `gtk_window_begin_resize_drag` / `NSWindow.styleMask` — confirm each widgetset exposes the handle cleanly from `TTyForm.Handle`; isolate the glue behind small `{$IFDEF}` helpers.
- **Replace vs keep engine drag on Windows** — leaning replace (native `HTCAPTION` for snap/shake); revisit if drag regresses.

## 7. Out of scope

Inline TreeView editing (③e), TreeView features (③d), any non-`TTyForm` control. This spec is the window-chrome resize fix only.
