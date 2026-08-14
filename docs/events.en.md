# Events and properties overview (API parity)

> 中文版见 [events.md](events.md)。

This page summarizes the event contract across the library: the baseline event set every control exposes (Tier A / Tier B), each control's specific events, and the properties deliberately not exposed because themes own the visuals.

> The goal of the parity work is for TyControls' event/property panels in the Object Inspector to match native LCL controls as closely as possible. Baseline events are published by the two base classes; control-specific events are published per control.

---

## 1. Baseline events (every control)

Every control inherits from one of two base classes (`tyControls.Base`):

| Base class | LCL parent | Purpose | Tiers |
|------|----------|------|----------|
| `TTyGraphicControl` | `TGraphicControl` | Non-windowed lightweight controls (no handle, cannot take keyboard focus) | **Tier A** only |
| `TTyCustomControl` | `TCustomControl` | Windowed focusable controls (handle, Tab navigation, keyboard) | **Tier A + Tier B** |

The `TTyGraphicControl` descendants are the display-only controls (`TTyLabel` / `TTyProgressBar` / `TTyDivider` / `TTyImage` / `TTyShape` / `TTyBadge` / `TTyTag` / `TTyGauge` / `TTyMeter` / `TTyChart` / `TTySparkline` / `TTyArrow` / `TTyBevel`, about 28 in all), so they expose Tier A only. Everything else (Button / Edit / Memo / SpinEdit / ComboBox / CheckBox / RadioButton / ScrollBar / TrackBar / TabControl / ToggleSwitch / ListBox / Panel / GroupBox and the rest) inherits `TTyCustomControl` and exposes both tiers.

### Tier A — mouse / general events and properties (both base classes, all controls)

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
| `AutoSize` | property | Size to the control's preferred size (`CalculatePreferredSize`); `default False` |
| `DragMode` | property | `dmManual` / `dmAutomatic`; automatic makes the control a drag source |
| `DragKind` | property | `dkDrag` / `dkDock` |
| `DragCursor` | property | Pointer shape while dragging |
| `PopupMenu` | property | Associated context menu |
| `Constraints` | property | Size constraints (min/max width/height) |
| `BorderSpacing` | property | Auto-layout spacing |
| `Cursor` | property | Pointer shape (edits default to `crIBeam`, …) |
| `ParentShowHint` | property | Inherit the parent's `ShowHint` |
| `Action` | property | Associated `TAction` |

> These members re-publish what the LCL parents already have; dispatch goes through `inherited` and matches native behavior exactly. Drag-and-drop is declared by `TControl` and dispatched by the LCL above the paint layer, so it behaves identically on custom-drawn controls — it only needed publishing.

### Tier B — keyboard / focus events (`TTyCustomControl` only)

| Event | Description |
|------|------|
| `OnKeyDown` | Key pressed (virtual key) |
| `OnKeyUp` | Key released |
| `OnKeyPress` | Character key (ANSI) |
| `OnUTF8KeyPress` | UTF-8 character key (multi-byte safe) |
| `OnEnter` | Got focus |
| `OnExit` | Lost focus |
| `OnEditingDone` | Editing finished (focus lost or Enter) |

> Tier B events are declared by `TWinControl`, so only windowed `TTyCustomControl` descendants expose them. `TTyLabel` / `TTyDivider` and the other graphic controls cannot take focus and do not.

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
| `Font` (published only to carry PPI/size) / `ParentFont` | Family and size are theme-controlled; `Font` exists to carry PPI |
| `Brush` | Fills come from the painter + theme |
| `Bevel*` (Inner/Outer/Kind/Width/Edges) | Native 3D borders conflict with theme border semantics |
| `BorderStyle` | Border style comes from the theme's `border-*` tokens |
| `DoubleBuffered` | Forced on (BGRABitmap offscreen composition); turning it off causes flicker and tearing |

> **`BorderWidth` is not a border width.** It is published on `TTyCustomControl`, but it is a layout property (child-area inset). The painted border's width comes only from the theme's `border-width` token.

> **`OnPaint` is an overlay, not a takeover.** It fires after the control has painted and been composited, handing you the LCL `Canvas` — you draw on top of the finished control and cannot alter the themed layer. That is why it does not violate the themes-own-visuals rule. It differs from `TTyPaintPanel.OnPaintSurface` / `TTyPreviewBox.OnPaintPreview`, which fire before composition and hand you a `TTyPainter` for theme-token-aware drawing.

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
