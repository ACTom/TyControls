# Events and properties overview (API parity)

> 中文版见 [events.md](events.md)。

This page summarizes the event contract across the library: the baseline event set every control exposes (Tier A / Tier B), each control's specific events, and the properties deliberately not exposed because themes own the visuals.

> The goal of the parity work is for TyControls' event/property panels in the Object Inspector to match native LCL controls as closely as possible. Both the baseline and the control-specific events are published by each control's own published section. Since 4.0 the two base classes publish nothing (like LCL's `TControl`), and neither does each control's `TTyCustomXxx` parent; for what to publish when you derive from them yourself, see [subclassing.en.md](subclassing.en.md).

---

## 1. Baseline events (every control)

Every control inherits from one of two base classes (`tyControls.Base`):

| Base class | LCL parent | Purpose | Tiers |
|------|----------|------|----------|
| `TTyGraphicControl` | `TGraphicControl` | Non-windowed lightweight controls (no handle, cannot take keyboard focus) | **Tier A** only |
| `TTyCustomControl` | `TCustomControl` | Windowed focusable controls (handle, Tab navigation, keyboard) | **Tier A + Tier B** |

The `TTyGraphicControl` descendants are the display-only controls (`TTyLabel` / `TTyProgressBar` / `TTyDivider` / `TTyImage` / `TTyShape` / `TTyBadge` / `TTyTag` / `TTyGauge` / `TTyMeter` / `TTyChart` / `TTySparkline` / `TTyArrow` / `TTyBevel`, about 28 in all), so they expose Tier A only. Everything else (Button / Edit / Memo / SpinEdit / ComboBox / CheckBox / RadioButton / ScrollBar / TrackBar / TabControl / ToggleSwitch / ListBox / Panel / GroupBox and the rest) inherits `TTyCustomControl` and exposes both tiers.

### Tier A — mouse / general events and properties (published by every control)

| Member | Kind | Description |
|------|------|------|
| `OnClick` | event | Click |
| `OnDblClick` | event | Double click |
| `OnMouseDown` | event | Mouse button pressed |
| `OnMouseUp` | event | Mouse button released |
| `OnMouseMove` | event | Mouse moved |
| `OnMouseEnter` | event | Pointer entered the control |
| `OnMouseLeave` | event | Pointer left the control |
| `OnMouseWheel` | event | Wheel (with delta) |
| `OnMouseWheelUp` | event | Wheel up |
| `OnMouseWheelDown` | event | Wheel down |
| `OnMouseWheelHorz` | event | Horizontal wheel (with delta); tilt wheels and touchpad horizontal gestures arrive only here |
| `OnMouseWheelLeft` | event | Horizontal wheel left |
| `OnMouseWheelRight` | event | Horizontal wheel right |
| `OnContextPopup` | event | Context-menu trigger |
| `OnResize` | event | Size changed |
| `OnChangeBounds` | event | Position or size (BoundsRect) changed |
| `OnShowHint` | event | Hint about to show; use it to vary the hint by pointer position |
| `OnPaint` | event | Fires after the control has painted itself, with the control's own `Canvas`; overlay a badge / marker / debug rectangle without subclassing |
| `OnDragOver` | event | Drag passing over this control (accept or reject the drop) |
| `OnDragDrop` | event | Dropped onto this control |
| `OnStartDrag` | event | This control started a drag |
| `OnEndDrag` | event | Drag finished |
| `Visible` | property | Visibility (`default True`) |
| `AutoSize` | property | Size to the control's preferred size (`CalculatePreferredSize`); `default False`. One-line edits and combo boxes take their height from the font and keep their width (as LCL's TEdit); status bars, headers and tab strips keep their theme height and grow when the font needs more; badges, ratings, calendars and scroll bars (thickness only) take their content. Controls with no natural size -- memos, list and tree views, grids, list boxes, gauges, shapes -- keep their bounds, as LCL's own do |
| `DragMode` | property | `dmManual` / `dmAutomatic`; automatic makes the control a drag source |
| `DragKind` | property | `dkDrag` / `dkDock` |
| `DragCursor` | property | Pointer shape while dragging |
| `PopupMenu` | property | Associated context menu |
| `Constraints` | property | Size constraints (min/max width/height) |
| `BorderSpacing` | property | Auto-layout spacing |
| `Cursor` | property | Pointer shape (edits default to `crIBeam`, …) |
| `ParentShowHint` | property | Inherit the parent's `ShowHint` |
| `Action` | property | Associated `TAction` |

> These are properties and events the LCL parents already have (mostly public or protected there), republished by each control's published section; dispatch goes through `inherited` and matches native behavior exactly. Drag-and-drop is declared by `TControl` and dispatched by the LCL above the paint layer, so it behaves identically on custom-drawn controls — it only needed publishing.

### Tier B — keyboard / focus events (windowed controls only)

| Event | Description |
|------|------|
| `OnKeyDown` | Key pressed (virtual key) |
| `OnKeyUp` | Key released |
| `OnKeyPress` | Character key (ANSI) |
| `OnUTF8KeyPress` | UTF-8 character key (multi-byte safe) |
| `OnEnter` | Got focus |
| `OnExit` | Lost focus |
| `OnEditingDone` | Editing finished (focus lost or Enter) |

> Tier B events are declared by `TWinControl`, so only windowed controls (the `TTyCustomControl` descendants) publish them. `TTyLabel` / `TTyDivider` and the other graphic controls cannot take focus and do not.

> Two container properties are also windowed-only: `BorderWidth` (insets the child area) and `ChildSizing` (the LCL per-container layout engine). Both are `TWinControl` members and meaningless on graphic controls.

---

## 2. Control-specific events

Beyond the baseline, these events are published per control:

| Control | Event | Type | Fires |
|------|------|------|----------|
| `TTyEdit` | `OnChange` | `TNotifyEvent` | Text changed by typing / clipboard / undo / redo; `Text :=` assignment does **not** fire it |
| `TTyMemo` | `OnChange` | `TNotifyEvent` | After the text model changes (insert / split / backspace / delete / merge); caret movement alone does not fire |
| `TTyMemo` | `OnSelectionChange` | `TNotifyEvent` | Caret position **or** selection changed (keys / clicks / Shift-selection / programmatic); debounced |
| `TTySpinEdit` | `OnChange` | `TNotifyEvent` | The edit **text** changed — every keystroke / delete / step / clamp / `Value :=` (LCL `TCustomEdit.Change` equivalent) |
| `TTySpinEdit` | `OnValueChange` | `TNotifyEvent` | The committed `Value` actually moved; not during typing |
| `TTyComboBox` | `OnChange` | `TNotifyEvent` | `ItemIndex` / text changed (including programmatic) |
| `TTyComboBox` | `OnSelect` | `TNotifyEvent` | **User**-driven selection (dropdown pick / keyboard); programmatic `ItemIndex` does not fire it |
| `TTyComboBox` | `OnDropDown` | `TNotifyEvent` | Dropdown opened |
| `TTyComboBox` | `OnCloseUp` | `TNotifyEvent` | Dropdown closed |
| `TTyCheckBox` | `OnChange` | `TNotifyEvent` | `Checked` actually changed |
| `TTyRadioButton` | `OnChange` | `TNotifyEvent` | `Checked` actually changed; siblings being unchecked each fire their own `OnChange` |
| `TTyScrollBar` | `OnScroll` | `TScrollEvent` | Keyboard / track / button scrolling; `(Sender; ScrollCode: TScrollCode; var ScrollPos: Integer)` — the handler may rewrite `ScrollPos` |
| `TTyTrackBar` | `OnChange` | `TNotifyEvent` | `Position` changed (including wheel steps) |
| `TTyCustomTabStrip` (`TTyTabSet` / `TTyPageControl`) | `OnChanging` | `TTyTabChangingEvent` | Before a tab switch; `(Sender; ANewIndex: Integer; var AllowChange: Boolean)` — set `AllowChange := False` to veto |
| `TTyCustomTabStrip` (same) | `OnReorder` | `TTyTabReorderEvent` | Once, after a drag reorder; `(Sender; AFromIndex, AToIndex: Integer)` |
| `TTyProgressBar` | `OnChange` | `TNotifyEvent` | After `Position` / `Min` / `Max` actually changed |

> **`TTyForm` uses the standard `TForm` lifecycle events.** `TTyForm` *is* a `TForm`, so `OnCloseQuery` / `OnClose` / `OnShow` / `OnActivate` / `WindowState` are the standard published form events. See [controls/ttyform.md](controls/ttyform.md).

> **Wheel stepping:** `TTyScrollBar` and `TTyTrackBar` support wheel steps with LCL conventions: wheel-up decreases a scroll bar's `Position` (content scrolls up) but increases a track bar's. Scroll-bar wheel writes `Position` directly (fires `OnChange`), bypassing `DoScroll`, so it does not fire `OnScroll`.

> **TitleBar mouse events are free.** `TTyTitleBar` implements window dragging and double-click-maximize via method overrides, so its published `OnMouseDown` / `OnMouseMove` / `OnMouseUp` / `OnDblClick` slots are available to the application — attaching handlers does not break chrome behavior.

---

## 3. Properties deliberately not exposed (themes own the visuals)

TyControls' hard rule is that visuals belong to the theme (`.tycss`): colors, fonts, borders, and shadows come from theme tokens, never from hardcoded control values or per-control native overrides. These `TControl` / `TWinControl` properties are therefore not published:

| Not exposed | Why |
|--------------|------|
| `Color` / `ParentColor` | Background comes from the theme's `background` token |
| `ParentFont` (`Font` is published) | A name, style, colour or size set on the control, or on a container it sits in, wins over the theme, and `StyleOverride` wins over that. The form's own font does not count: the form-wide font is the theme's `--font-family` / `--font-size-base`. A value set equal to the container's is the container's. The same goes for the text inside a control (list rows, cells, tabs, headers), except that the selected or current item keeps the theme's highlight colour |
| `Brush` | Fills come from the painter + theme |
| `Bevel*` (Inner/Outer/Kind/Width/Edges) | Native 3D borders conflict with theme border semantics |
| `BorderStyle` | Border style comes from the theme's `border-*` tokens |
| `DoubleBuffered` | Forced on (BGRABitmap offscreen composition); turning it off causes flicker and tearing |

> **`BorderWidth` is not a border width.** Every windowed control publishes it, but it is a layout property (child-area inset). The painted border's width comes only from the theme's `border-width` token.

> **`OnPaint` is an overlay, not a takeover.** It fires after the control has painted and been composited, handing you the LCL `Canvas` — you draw on top of the finished control and cannot alter the themed layer. That is why it does not violate the themes-own-visuals rule. It differs from `TTyPaintPanel.OnPaintSurface` / `TTyPreviewBox.OnPaintPreview`, which fire before composition and hand you a `TTyPainter` for theme-token-aware drawing.

### Drawing on the layer on a Retina screen

On a macOS Retina screen the painter draws at the screen's real pixels: its layer is S times the control's size (usually S = 2) and is put back at the control's size when done. Wherever you get a `TTyPainter` (`OnPaintSurface`, `OnPaintPreview`, the grid's `OnDrawCell`, a subclass overriding `RenderTo`), keep the following in mind.

No change needed:

- The painter's own methods (`FillBackground`, `StrokeBorder`, `DrawText`, `DrawGlyph`, …) take control coordinates as before.
- `Bitmap.Canvas2D` comes with an S-times transform already set: control coordinates and line widths as before. The painter set that transform, so do not replace it wholesale: `resetTransform` and `setTransform` drop the S from coordinates (on Retina the drawing lands in the top-left quarter, at half size), and `strokeResetTransform` drops it from line widths (lines come out half as thick). For a temporary translate, rotate or scale, wrap it in `save` / `restore` and call `translate`, `rotate` or `scale` in between; if you really must start from scratch, follow it with `scale(P.DeviceScale, P.DeviceScale)`, and put line widths back with `strokeScale`.
- The painter's path API (`BeginPath`, `MoveTo` / `LineTo`, `FillPath`, `StrokePath`, `PathContains`, `Translate` and the rest) takes control coordinates as before. `ResetTransform` goes back to that S-times transform, not to the identity, so paths after it are still in control coordinates.

Calls that work on `Bitmap` directly (`FillRect`, `PutImage`, `ClipRect`, `DrawLine`, …) count layer pixels, so convert:

| Use | What it does |
|---|---|
| `P.Dev(x)` / `P.Dev(R)` / `P.Dev(Pt)` | control coordinates to layer pixels |
| `P.DeviceScale` | this frame's S; 1 on Windows and Linux, where `Dev` returns its argument |
| `P.RasterPPI` | the PPI to give a font on the bitmap, instead of `P.PPI` |
| `P.DrawRule(x1, y1, x2, y2, c)` | a horizontal or vertical 1-px line, one control pixel wide at any S; `Bitmap.DrawLine` is half as thick on Retina |
| `P.DrawGlyphBitmap` | takes a bitmap in layer pixels |

```pascal
// Before: half the position and half the size on Retina
APainter.Bitmap.FillRect(R.Left, R.Top, R.Right, R.Bottom, BGRA(255, 0, 0), dmSet);
// After: right at any S
APainter.Bitmap.FillRect(APainter.Dev(R), BGRA(255, 0, 0), dmSet);
```

To go back to one-times drawing everywhere (to rule it out while debugging, say), set `TyDeviceScaleRendering := False` (unit `tyControls.Painter`) at startup.

---

## 4. Event behavior conventions

### 4.1 Disabled controls fire no input events

With `Enabled = False`, controls do not respond to input: keys are not consumed, mouse and wheel are ignored, `DoMouseWheel` returns `False`. So a disabled control never fires `OnClick` / `OnKey*` / `OnMouseWheel` / its `OnChange` from input. Whether programmatic assignment (`Checked :=`, `Position :=`) fires events is documented per control and is independent of `Enabled`.

### 4.2 Embedded scroll bars are private

The `TTyScrollBar` embedded inside `TTyMemo` / `TTyListBox` / combo dropdowns is a private sub-widget: not in the Object Inspector, no exposed `OnScroll` / `OnChange`, no thumb easing. Listen to the host control's events (a memo's `OnChange` / `OnSelectionChange`) instead.

### 4.3 Programmatic assignment and events

The trap worth memorizing: `TTyEdit.Text :=` / `TTyMemo.Text :=` do **not** fire `OnChange` (they update the field, record an undo step, and repaint). `Checked` / `Position` / `Value` fire their `OnChange` whenever the value actually changes, programmatic or not — see each control's docs.

---

## 5. Related docs

- Per-control event and property details: the Events and Properties sections of `docs/controls/<control>.md`.
- Theme tokens and sub-part typeKeys: [tycss-reference.en.md](tycss-reference.en.md).
- Bidirectional text and right-to-left status: [rtl.md](rtl.md).
