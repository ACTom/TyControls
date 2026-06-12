# TyControls — Known Gaps (v1)

These behaviors are intentionally NOT implemented in v1. They are tracked
for a future Tier-2 native enhancement layer.

## Form chrome (TTyFormChrome) native window behavior

- Windows Aero Snap (edge tiling) is not supported; dragging to a screen edge
  moves the form but does not trigger snap-to-half or snap-to-quadrant tiling.
- Borderless-window native drop shadow is not provided. Because the form uses
  `BorderStyle := bsNone` the OS-provided window shadow is lost; v1 renders no
  substitute shadow around the form frame.
- macOS traffic-light (red/yellow/green) caption buttons are not emulated;
  TyControls draws its own close/min/max glyphs (`TTyCaptionButton`) instead.
  macOS users do not get platform-standard window controls.
- Cross-monitor DPI switching is not handled; moving a window between monitors
  with different scaling factors does not re-scale chrome metrics on the fly.
  PPI is sampled from the host form's font at paint time.
- `TTyFormChrome.Active := False` restores the original `BorderStyle` and the
  form's previous mouse handlers, but toggling chrome on/off repeatedly at
  runtime is not a tested scenario. Recommended usage remains: activate once
  at startup and leave it `True` for the lifetime of the form.

## Design-time rendering

- The Lazarus form designer shows the native (non-skinned) frame; full
  self-drawn window chrome appears only at runtime. This is the standard
  behavior for skin-window libraries and is expected.

## Controls

- `TTyComboBox` has no real dropdown popup in v1. Clicking the control cycles
  through the `Items` list in place; a floating popup list is a Tier-2 item.

## Style engine

- Nine-slice `url()` asset paths must not contain spaces. The style lexer splits
  dotted tokens; spaces are stripped when the filename is reconstructed, so a
  path like `my assets/bg.png` will be silently misread. Keep asset filenames
  and directory names space-free.
- A `shadow:` value's color must be a single token — a bare hex value
  (`#0000002E`), a CSS custom property (`var(--x)`), or a bare variable name
  (`--x`). A comma-bearing color function such as `alpha(c, a)` or `mix(...)`
  cannot be used in `shadow` because the value is space-split into
  offset / blur / color; use hex-alpha notation instead (e.g. `#0000002E`).
- Control-wide `opacity` dims controls that render through `DrawFrame`
  (Button, Label, Edit, Panel, ComboBox, ScrollBar, TitleBar, CaptionButton).
  `TTyCheckBox` and `TTyRadioButton` draw only a glyph + caption without
  `DrawFrame`, so `opacity` and `shadow` have no effect on them in v1.

## Package / build

- The demo project builds against the source path (`../../source`) because
  the unregistered package link is not auto-injected by `lazbuild`. A real
  consumer should install `tycontrols.lpk` via the Lazarus IDE package manager,
  which registers the package and injects it automatically.
