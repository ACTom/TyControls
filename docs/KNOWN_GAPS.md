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

- `TTyCheckBox` / `TTyRadioButton` `opacity` and `shadow`: **resolved in v1.1**.
  The rendering path now routes through `DrawFrame` which applies both
  properties; they are fully effective for all typeKeys including checkbox and
  radiobutton.
- `TTyMemo` editing core + selection (v1.11), deferred features: the multi-line
  editor ships a reliable per-codepoint editing core (Enter/Backspace/Delete with
  cross-line merge, 2-D arrow + Home/End navigation, vertical scrollbar/wheel) and
  — as of **v1.11** — a full 2-D **text selection** layer mirroring `TTyEdit`:
  selection anchor (`Shift`+arrows/Home/End extend, mouse-drag highlight, per-line
  selection band, `SelText`/`SelectAll`/`ClearSelection`), **range clipboard**
  (`Ctrl/Cmd+A/C/X/V`; paste splits on CR/LF into multiple lines; copy/cut via the
  same virtual `ReadClipboardText`/`WriteClipboardText` hooks as `TTyEdit`), and
  **word navigation** (`Ctrl/Alt+Left/Right` move by word, crossing line
  boundaries; `Ctrl/Alt+Backspace/Delete` delete the adjacent word and fall back to
  the cross-line merge at a line edge). As of **v1.12** both text controls also
  ship snapshot-based **undo/redo** (`Ctrl/Cmd+Z` undo; `Ctrl/Cmd+Y` or
  `Ctrl/Cmd+Shift+Z` redo) with a bounded (~200-step) history and typing
  coalescing — `TTyEdit` additionally gained an `OnChange` event, which (like
  `TTyMemo.OnChange`) fires on undo/redo. The following remain intentionally
  **deferred** to a future Tier-2 layer:
  - **No word-wrap**: lines render with `WordBreak=False`; one logical line is
    always one visual row, never reflowed to the control width.
  - **No horizontal scroll / long lines clipped**: no horizontal scrollbar or
    auto-scroll; lines wider than the content area are clipped at the right
    edge and the caret can move off-screen horizontally without following.
  - **No caret blink**: the caret is a static 1px bar drawn only when focused
    and the caret line is visible; there is no `TTimer`-driven blink.
  See [controls/memo.md](controls/memo.md) §10 (gaps) and §11 (undo/redo) for
  the per-control writeup.
- **Drop shadows / elevation on embedded controls — deliberately deferred.**
  Batch⑤+⑥ shipped per-control motion (cursors, hover-fade, knob-slide, eased
  progress/scrollbar/trackbar position, tab-header cross-fade) but intentionally
  did NOT add Material-style drop shadows or elevation to the controls. LCL clips
  an embedded `TControl`'s painting to its own bounds, so a shadow drawn inside a
  control's `Paint` cannot bleed past its edges into the parent — a faithful
  elevation effect would require painting on the parent surface (or a separate
  overlay window), which is out of scope for this batch. Deferred to a future
  Tier-2 enhancement layer.

## Design-time rendering

- Controls dropped onto a form now render with the **built-in default skin**
  in the Lazarus designer (zero-config, visible without running). Only the full
  self-drawn window chrome (`TTyFormChrome`) remains runtime-only: the designer
  shows the native (non-skinned) window frame. This is the standard behavior for
  skin-window libraries and is expected.

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
