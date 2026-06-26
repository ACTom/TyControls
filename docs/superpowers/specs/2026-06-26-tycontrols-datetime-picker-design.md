# TTyCalendar + TTyDateTimePicker Design Spec

**Date:** 2026-06-26 · **Status:** approved (design) · **Program:** [new-controls ② / phase-2]

## Goal

Add two custom-drawn, fully-themed Ty-native date/time controls at LCL-common-API parity:
- **`TTyCalendar`** — a standalone month-grid calendar with drill-down navigation (days → months → years → decades).
- **`TTyDateTimePicker`** — an edit field that shows/edits a date (with a popup calendar) or a time (with per-segment spin), nullable via a check box, range-constrained.

Plus a refactor that extracts the dropdown-popup window logic into a reusable **`TTyDropdownPopup`** helper, migrating `TTyComboBox` onto it (so the popup's platform fixes live in one place and the calendar dropdown reuses them).

## Scope

In: standalone `TTyCalendar` (drill-down, week numbers, today highlight, range greying, keyboard); `TTyDateTimePicker` with `dtkDate` (calendar dropdown) and `dtkTime` (spin) kinds, `ShowCheckBox` nullable, `MinDate`/`MaxDate`, segment editing; locale-aware formatting via LCL `FormatSettings` with `DateFormat`/`TimeFormat` overrides; the shared popup helper + ComboBox migration; theme typeKeys byte-synced across all 6 themes; design-time registration + icons; demo; tests.

Out (deferred): multi-select / date-range selection in the calendar; recurring/holiday decoration; `OnDrawDayItem` owner-draw; time-zone handling; a month/year text drop list (we use the drill-down zoom instead); inline (non-popup) calendar embedding mode for the picker.

---

## Architecture

| Unit | Responsibility |
|---|---|
| `source/tyControls.Popup.pas` (new) | `TTyDropdownPopup` — owns a borderless `TForm`, positions it under (or above) an anchor control, applies a rounded `SetWindowRgn` region, closes on deactivate, re-applies the Qt mask on resize, hosts a caller-supplied content control. Pure position/size math is factored out and testable. |
| `source/tyControls.Calendar.pas` (new) | `TTyCalendar` control + pure date-math helpers (month grid, range clamp, view-zoom transitions) in the interface section. |
| `source/tyControls.DateTimePicker.pas` (new) | `TTyDateTimePicker` control + pure format/parse + segment-edit helpers. |
| `source/tyControls.ComboBox.pas` (modify) | Replace the inline popup fields/methods with a `TTyDropdownPopup` instance hosting the existing `TTyListBox`. Behavior unchanged; existing tests are the regression guard. |
| `themes/*.tycss` + `DefaultTheme.pas` + `BuiltinThemeData.pas` + goldens | New typeKeys (below) added token-based to all 6 themes; mirrors regenerated; goldens re-bootstrapped. |
| `designtime/tyControls.Design.pas` + icon pipeline | Register `TTyCalendar` + `TTyDateTimePicker` + glyphs. |
| `tests/*` + demo | Pure-fn + behavior + pixel tests; demo placement. |

Both controls descend from `TTyCustomControl` and paint via `TTyPainter`, following the established idioms (`GetStyleTypeKey`, `Paint`→`RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`, `CurrentStyle`, `DrawFrame`, `P.Scale` for every device metric, `TTyFill`).

---

## 1. `TTyDropdownPopup` (shared popup helper)

A plain `TComponent`/class (not a control) that encapsulates the dropdown window. Lifts the logic currently embedded in `TTyComboBox` (`FPopup: TForm`, `FPopupRect`, `ApplyPopupRegion`, `PopupResize`, `PopupDeactivate`, the deactivate-reopen-race guard, and the `ComputePopupHeight`-style separation of math from window creation).

**Public API (shape):**
- `constructor Create(AOwner: TComponent)` — lazy; the `TForm` is created on first `Popup`.
- `procedure SetContent(AControl: TControl)` — the hosted control (a `TTyListBox` for combo, a `TTyCalendar` for the picker). Parented into the popup form, `Align := alClient`.
- `procedure Popup(AAnchor: TControl; AContentWidth, AContentHeight: Integer)` — compute the screen rect under `AAnchor` (flip above if it would go off-screen), size the form, apply the rounded region (radius from a settable `CornerRadiusLogical`, scaled to the popup PPI; no-op when 0 or off-Windows), show non-activating, hook deactivate-to-close + Qt resize-mask re-apply.
- `procedure Close` / `function IsOpen: Boolean`.
- `property OnClose: TNotifyEvent` — fired when the popup closes (so the owner can update `DroppedDown`).
- `property CornerRadiusLogical: Integer`.
- A `class function`/standalone pure fn `TyPopupRect(const AAnchorScreen: TRect; AContentW, AContentH, AScreenH: Integer): TRect` for the position-flip math (testable headlessly).

**ComboBox migration:** `TTyComboBox.DoDropDown` builds a `TTyDropdownPopup` (once), `SetContent(FPopupList)`, `Popup(Self, Width, ComputePopupHeight(PPI))`; `OnClose` clears the dropped state. The Qt/region/deactivate code is deleted from ComboBox (now in the helper). The ComboBox popup/keyboard/type-ahead/`ComputePopupHeight` tests must stay green.

---

## 2. `TTyCalendar`

**Published properties:** `Date: TDateTime` (the selected day; time component preserved/ignored as a day), `MinDate: TDateTime` / `MaxDate: TDateTime` (0 = unbounded), `FirstDayOfWeek: TTyWeekDay` (default `wdSunday`; an enum `wdSunday..wdSaturday`), `WeekNumbers: Boolean` (default False), `ShowToday: Boolean` (default True), `ReadOnly: Boolean`, plus re-published `Align`/`Anchors`/`Font`/`StyleClass`/`Controller`. Events: `OnChange: TNotifyEvent` (date changed), `OnViewChange` (drill-down level changed).

**Drill-down views** — `ViewMode: (cvmDays, cvmMonths, cvmYears, cvmDecades)` (public, not published; runtime state, starts at `cvmDays`):
- **Days:** header `‹ <Month YYYY> ›`; a weekday-name row; a 6×7 grid of day cells (leading/trailing days from adjacent months greyed = "other-month"); today highlighted; the selected day filled; out-of-range days disabled; optional week-number column on the left. Prev/next arrows = previous/next month.
- **Months:** header `‹ YYYY ›`; a 4×3 grid of month names; pick a month → zoom into Days of that month. Arrows = prev/next year.
- **Years:** header `‹ YYYY–YYYY ›` (the decade); a 4×3 grid of years; pick → Months. Arrows = prev/next decade.
- **Decades:** header `‹ YYYY–YYYY ›` (the century); a 4×3 grid of decades; pick → Years. Arrows = prev/next century.
- Clicking the header TITLE zooms OUT one level (Days→Months→Years→Decades). Clicking a cell zooms IN (Decades→Years→Months→Days), and at Days level selects the date (fires `OnChange`).

**Keyboard:** arrows move the focused cell within the current view's grid (wrapping into adjacent periods at edges); PageUp/PageDown = arrows' period step (prev/next month/year/decade/century); Home/End = first/last cell of the current period; Enter/Space = zoom-in / select; Esc = (in popup) close, (standalone) zoom out one level if not at Days. Backspace/`-`/`+` not bound.

**Rendering (`RenderTo`):** `DrawFrame` (panel bg + border + radius from `TyCalendar`), then the header band, the weekday row (Days view only), and the grid — each cell resolved from the cell typeKey with the right states. All geometry via `P.Scale`. Today/selected/other-month/disabled are visual states.

**Theme typeKeys (token-driven, byte-synced across all 6 themes):**
- `TyCalendar` — panel surface (bg `var(--surface)` / input-bg, border, radius, padding, font).
- `TyCalendarTitle` — the header title text + the `‹`/`›` arrow glyph color; `:hover` for the clickable title/arrows.
- `TyCalendarWeekday` — weekday-name + week-number labels (muted: `color: var(--muted)`).
- `TyCalendarCell` — a day/month/year/decade cell: base + `:hover` (`--surface-hover`) + `:selected` (`--accent` bg / `--on-accent` text) + `:disabled` (`--muted`, out-of-range/other-month). Today = a ring/outline via the cell's `outline`/`--accent` (an additional minor token or the `:focus`-style outline; today is not a separate typeKey — it reuses an accent outline on the base cell).

**Pure functions (interface, exhaustively tested):**
- `TyCalendarMonthGrid(AYear, AMonth: Word; AFirstDay: TTyWeekDay): TTyDateGrid` — returns the 42 (`6*7`) `TDateTime` day values filling the grid, including leading/trailing other-month days.
- `TyCalendarInRange(ADate, AMin, AMax: TDateTime): Boolean` and `TyCalendarClampDate(...)`.
- `TyCalendarZoomOut`/`TyCalendarZoomIn(AView, ...): cvm…` + the period-range helpers (`TyDecadeStart(AYear)` etc.).
- `TyWeekdayOrder(AFirstDay)` — the 7 weekday indices in display order; `TyISOWeekNumber(ADate)`.

---

## 3. `TTyDateTimePicker`

**Published properties:** `Kind: TTyDateTimeKind` (`dtkDate` / `dtkTime`, default `dtkDate`), `DateTime: TDateTime`, `Date: TDateTime` (date part) / `Time: TDateTime` (time part) convenience, `DateFormat: string` (empty = `FormatSettings.ShortDateFormat`), `TimeFormat: string` (empty = `FormatSettings.ShortTimeFormat` / `LongTimeFormat` if seconds), `MinDate`/`MaxDate`, `ShowCheckBox: Boolean` (default False), `Checked: Boolean` (meaningful only when `ShowCheckBox`; False = null/unset, field greyed), `ReadOnly`, `DroppedDown: Boolean` (read-only-ish; setting True opens). Re-publish `Align`/`Anchors`/`Font`/`StyleClass`/`Controller`. Events: `OnChange`, `OnDropDown`, `OnCloseUp`, `OnChecked`.

**Field rendering + editing (reuses the `TTySpinEdit` inline-edit pattern):** the field text is the value formatted by `DateFormat`/`TimeFormat`. It is split into editable **segments** (e.g. day / month / year, or hour / minute / second) derived from the format string. One segment is "active" (highlighted); `←`/`→` move between segments; typing digits edits the active segment (auto-advances when full / on separator); `↑`/`↓` (and the spin button for `dtkTime`, mouse wheel) increment/decrement the active segment with roll-over + carry; Home/End jump to first/last segment. On commit (Enter / focus-out / dropdown-select) the value is clamped to `[MinDate, MaxDate]`. A blinking caret reuses the existing `TyCaretVisible` facility. When `ShowCheckBox` and unchecked, the field is greyed and non-editable until checked.

- **`dtkDate`:** a dropdown button on the right; clicking (or Alt+Down/F4) opens a `TTyDropdownPopup` hosting a `TTyCalendar` (seeded with the current date + Min/Max + first-day-of-week). Selecting a day writes it back, fires `OnChange`/`OnCloseUp`, closes.
- **`dtkTime`:** up/down spin buttons on the right (no calendar); they step the active time segment.
- **`ShowCheckBox`:** a check box drawn at the field's left edge (reusing the `TyCheckBox` glyph/states); toggling fires `OnChecked` and enables/greys the field.

**Theme typeKeys:** `TyDateTimePicker` — the field box (bg `var(--input-bg)`, border, radius, states `:hover`/`:focus`/`:disabled`, like `TyEdit`); `TyDateTimeButton` — the dropdown/spin button (reuses the field-button look, like the combo/spin button: `var(--surface-chrome)` bg, accent on hover/press). The active-segment highlight uses the existing `--selection` token. The check box reuses `TyCheckBox`.

**Pure functions (interface, tested):**
- `TyFormatDateTime(AValue: TDateTime; const AFormat: string; const AFmt: TFormatSettings): string` (thin, deterministic wrapper over `FormatDateTime` with a fixed `TFormatSettings` so tests are locale-independent).
- `TyDateTimeSegments(const AFormat: string): TTySegmentArray` — parse a format string into segment descriptors (kind = day/month/year/hour/min/sec/ampm, char span, min/max). Drives navigation + editing + the active-segment highlight rect.
- `TySegmentStep(AValue: TDateTime; ASeg: TTySegment; ADelta: Integer): TDateTime` — increment/decrement a segment with roll-over/carry.
- `TySegmentTypeDigit(...)` — apply a typed digit to the active segment (buffer + auto-advance rule).

---

## 4. Localization

All display goes through LCL `DefaultFormatSettings` (which reflect the OS locale): month/weekday names, separators, AM/PM, and the default date/time format. The controls expose `DateFormat`/`TimeFormat` + `FirstDayOfWeek` for explicit override. The pure `Ty*` format/segment functions take an explicit `TFormatSettings` param so tests pin a known locale and stay deterministic; the controls pass `DefaultFormatSettings` at the call site. No new translatable strings (the controls have no fixed English text — everything is locale data or a number).

---

## 5. Testing strategy (mirrors ①)

- **Pure functions** — exhaustive boundary tests: month-grid (incl. Feb leap years, first-day-of-week variants, 6-row overflow), range clamp/in-range, view zoom in/out + period ranges, ISO week number, format/parse with a pinned `TFormatSettings`, segment parsing/step/type-digit (roll-over, carry, clamp).
- **Calendar** — RenderTo pixel tests (selected day = accent, today = outline, disabled = muted) + behavior (keyboard nav across edges, drill-down zoom in/out, range disables out-of-range cells, `OnChange` fires once on select).
- **DateTimePicker** — behavior (segment nav + digit typing + spin roll-over + clamp, dropdown open→pick→close writes back, `ShowCheckBox` greys/null toggles `OnChecked`) + a render smoke/pixel test.
- **Popup helper** — `TyPopupRect` flip math (pure) + a popup smoke (create/show/close without exception). **ComboBox migration: every existing combo test stays green** (the regression guard).
- **Theme** — the new typeKeys byte-synced (`gen-defaulttheme.ps1` + `gen-builtinthemes.ps1`), `GGRID` extended, goldens re-bootstrapped, `TestBuiltinCoversAllTypeKeys` updated.
- **Events** — RTTI guard that both controls publish the standard event set + their specific events.

PPI pinned to 96 in pixel tests; tests use a dedicated `TTyStyleController` + inline `LoadThemeCss` for known colors, or the default theme.

---

## 6. Design-time + demo

Register `TTyCalendar` + `TTyDateTimePicker` on the palette (Design.pas `uses` + `RegisterComponents`), add glyphs to `genicons.lpr` + `gen-icons.ps1 $classes` + `test.paletteicons.pas CClasses` (4-way drift-guard sync). Demo: a `TTyCalendar` plus a `TTyDateTimePicker` (one `dtkDate` with ShowCheckBox, one `dtkTime`), placed in the `.lfm`.

---

## 7. Key decisions (my judgment, per "按你想法来")

1. **Header navigation = drill-down zoom** (days↔months↔years↔decades), not a month/year drop list — matches modern pickers + reuses the same grid renderer for all four views.
2. **Today is a state (accent outline) on `TyCalendarCell`, not a separate typeKey** — keeps the theme surface small while staying token-driven.
3. **Null model:** `ShowCheckBox=False` ⇒ always a value; `ShowCheckBox=True` + `Checked=False` ⇒ null (field greyed). No separate "NullDate" sentinel exposed; `Checked` is the null flag (mirrors LCL).
4. **`dtkTime` has spin buttons, no popup** (LCL parity); the calendar dropdown is `dtkDate`-only.
5. **Popup extraction includes the ComboBox migration this round** (user-approved) — DRY, guarded by combo tests.
6. **Segment editing reuses the SpinEdit inline-edit machinery** rather than embedding a full text editor — dates/times are fixed-shape, segment-structured.

## 8. Phasing (informs the plan, one spec)

Build order: **(a) `TTyDropdownPopup` + ComboBox migration** → **(b) `TTyCalendar`** (pure date math → grid render → drill-down → keyboard → theme) → **(c) `TTyDateTimePicker`** (format/segment pure fns → field render+edit → dtkDate dropdown via popup+calendar → dtkTime spin → ShowCheckBox) → **(d) theme byte-sync + goldens, design-time + icons, demo, final**.
