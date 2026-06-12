# TyControls — Known Gaps (Window Subsystem, v1)

The v1 window subsystem (`TTyFormChrome` / `TTyTitleBar`) is a cross-platform
manual implementation chosen for consistent appearance across Windows, Linux,
and macOS. It deliberately does NOT implement the following native behaviors.
These are tracked for a Tier-2 native enhancement layer and must NOT be assumed
present in v1.

## Not implemented in v1

- **Windows Aero Snap** — dragging to a screen edge does not trigger
  snap-to-half / snap-to-quadrant tiling. Drag only moves the form.
- **Native drop shadow on borderless windows** — because the form uses
  `BorderStyle := bsNone`, the OS-provided window shadow is lost. v1 renders
  no substitute shadow around the form frame.
- **macOS traffic-light buttons** — the close/minimize/maximize buttons are
  drawn by `TTyCaptionButton` (vector glyphs), not the native macOS red/yellow/
  green controls; macOS users do not get platform-standard window controls.
- **Cross-monitor DPI switching** — moving a maximized or dragged window between
  monitors with different scaling factors does not re-scale chrome metrics on
  the fly; PPI is sampled from the host form's font at paint time.
- **`TTyFormChrome.Active` is set-once at startup** — setting `Active := False`
  after the chrome has been applied clears the internal form reference but does
  NOT restore the original `BorderStyle`; the window remains borderless. Treat
  `Active` as a startup switch and leave it `True` for the lifetime of the form.

## Scope note

Maximize uses the active monitor work area (`Screen.MonitorFromWindow(...)`
`.WorkareaRect` via `TyMaximizedBounds`) so the taskbar is avoided, but the
above native integrations remain out of scope for v1.
