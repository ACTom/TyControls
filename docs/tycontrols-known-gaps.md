> **Superseded.** This file has been consolidated into [`KNOWN_GAPS.md`](KNOWN_GAPS.md),
> which covers all v1 limitations including form chrome, controls, style engine,
> and package/build. Please refer to that file going forward.

# TyControls — Known Gaps (Window Subsystem, v1)

> **Historical note:** the window subsystem described here was originally the
> `TTyFormChrome` controller. That controller has since been **removed** and
> replaced by the `TTyForm = class(TForm)` window base class (see
> [controls/ttyform.md](controls/ttyform.md)). The native-behavior gaps below
> still apply to `TTyForm`. The current, authoritative list lives in
> [`KNOWN_GAPS.md`](KNOWN_GAPS.md).

The window subsystem (`TTyForm` / `TTyTitleBar`, formerly `TTyFormChrome`) is a
cross-platform manual implementation chosen for consistent appearance across
Windows, Linux, and macOS. It deliberately does NOT implement the following
native behaviors. These are tracked for a Tier-2 native enhancement layer and
must NOT be assumed present.

## Not implemented in v1

- **Windows Aero Snap** — dragging to a screen edge does not trigger
  snap-to-half / snap-to-quadrant tiling. Drag only moves the form.
- **Native drop shadow on borderless windows** — because the form uses
  `BorderStyle := bsNone`, the OS-provided window shadow is lost. v1 renders
  no substitute shadow around the form frame.
- **macOS traffic-light buttons** — the close/minimize/maximize buttons are
  drawn by `TTyCaptionButton` (vector glyphs), not the native macOS red/yellow/
  green controls; macOS users do not get platform-standard window controls.
- **Cross-monitor DPI switching** — see [`KNOWN_GAPS.md`](KNOWN_GAPS.md): chrome
  metrics now rescale on monitor-PPI change (v1.1); multi-monitor manual
  validation remains pending.

## Scope note

Maximize uses the active monitor work area (`Screen.MonitorFromWindow(...)`
`.WorkareaRect` via `TyMaximizedBounds`) so the taskbar is avoided, but the
above native integrations remain out of scope for v1.
