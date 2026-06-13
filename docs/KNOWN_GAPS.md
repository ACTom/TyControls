# TyControls — Known Gaps (v1 / v1.1)

These behaviors are intentionally NOT implemented or are tracked for a future
Tier-2 native enhancement layer.

## Form chrome (TTyFormChrome) native window behavior

- Windows Aero Snap (edge tiling) is not supported; dragging to a screen edge
  moves the form but does not trigger snap-to-half or snap-to-quadrant tiling.
- Borderless-window native drop shadow: **resolved on macOS** (v1.1). After
  `BorderStyle := bsNone`, `InstallChrome` now calls
  `NSView(Form.Handle).window.setHasShadow(True)` via the LCL-Cocoa handle
  convention (`Form.Handle` is a `TCocoaWindowContent` NSView; `.window` gives
  the backing `NSWindow`). The call is wrapped in `{$IFDEF LCLCOCOA}` so
  non-Cocoa builds are unaffected.
  Windows DWM drop shadow remains pending — no cross-compile verification
  environment is available to test or debug the DWM API path.
- macOS traffic-light (red/yellow/green) caption buttons are not emulated;
  TyControls draws its own close/min/max glyphs (`TTyCaptionButton`) instead.
  macOS users do not get platform-standard window controls. A visual approximation
  using `ShowGlyphOnHoverOnly` is documented in
  [docs/recipes-traffic-lights.md](recipes-traffic-lights.md).
- Cross-monitor DPI switching: **metrics now rescale on monitor-PPI change**
  (v1.1). `TTyFormChrome` stores `FInstalledPPI` at install time and chains the
  host form's `OnChangeBounds` event (previous handler is saved and restored on
  uninstall). When the form's monitor PPI changes, `TitleHeight` and the title
  bar's `FButtonWidth` are rescaled via `TyRescaleChromeMetric` (MulDiv with
  half-up rounding). The pure function and handler-chaining are unit-tested.
  Multi-monitor manual validation pending (only one physical monitor available
  in the build environment).
- `TTyFormChrome.Active := False` restores the original `BorderStyle`, the
  form's previous mouse handlers, and the `OnChangeBounds` chain. Toggling
  chrome on/off repeatedly at runtime is not a tested scenario. Recommended
  usage remains: activate once at startup and leave it `True` for the lifetime
  of the form.

## Controls

- `TTyEdit` has no word-level jump (v1.1): Ctrl/Cmd+Left/Right arrow does not
  calculate word boundaries; the key event is passed through to the parent
  window unmodified.
- `TTyCheckBox` / `TTyRadioButton` `opacity` and `shadow`: **resolved in v1.1**.
  The rendering path now routes through `DrawFrame` which applies both
  properties; they are fully effective for all typeKeys including checkbox and
  radiobutton.

## Design-time rendering

- The Lazarus form designer shows the native (non-skinned) frame; full
  self-drawn window chrome appears only at runtime. This is the standard
  behavior for skin-window libraries and is expected.

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

## Package / build

- The demo project builds against the source path (`../../source`) because
  the unregistered package link is not auto-injected by `lazbuild`. A real
  consumer should install `tycontrols.lpk` via the Lazarus IDE package manager,
  which registers the package and injects it automatically.
