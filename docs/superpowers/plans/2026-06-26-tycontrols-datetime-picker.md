# TTyCalendar + TTyDateTimePicker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use `- [ ]` checkboxes.

**Goal:** Add `TTyCalendar` (drill-down month calendar) + `TTyDateTimePicker` (date/time field with calendar dropdown / spin, nullable, range), and extract a shared `TTyDropdownPopup` (migrating `TTyComboBox` onto it).

**Architecture:** Both controls descend from `TTyCustomControl`, custom-draw via `TTyPainter`, theme-token-driven. The testable core is pure functions (month grid, range, view-zoom, popup-rect, format, segments). The calendar dropdown reuses the extracted popup helper.

**Tech Stack:** FPC/Lazarus LCL, BGRABitmap, the `.tycss` theme engine, fpcunit.

**Spec:** `docs/superpowers/specs/2026-06-26-tycontrols-datetime-picker-design.md`. **Branch:** `feat/datetimepicker`.

---

## Conventions (read once)

- Build runtime pkg `lazbuild tycontrols.lpk`; design-time `lazbuild tycontrols_dt.lpk`; tests `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → read `Number of failures: 0`. **Baseline at branch start: 977 run / 0 failures / 11 pre-existing env-errors.**
- New test unit wired by `RegisterTest(...)` in `initialization` + adding the unit name to `tests/tytests.lpr` `uses` (NOT the `.lpi`).
- `AssertEquals(expected, actual)` — expected first. PPI pinned to 96 in pixel tests.
- New control unit → add an `<Item>` to `tycontrols.lpk`.
- Mirror the established control idiom from `source/tyControls.Splitter.pas` / `tyControls.StatusBar.pas` / `tyControls.GroupBox.pas` (uses clause, `GetStyleTypeKey`, `Paint`→`RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`, `CurrentStyle`, `DrawFrame`, `P.Scale` for every device metric, `TTyFill`, `ResolveFontSize`). Glyphs (arrows/chevrons) via `TTyPainter.DrawGlyph` (`tgChevronDown`/`tgArrowLeft`/`tgArrowRight` etc.).
- Commit per task, English, ending `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

# PHASE A — shared popup helper + ComboBox migration

## Task A1: `TyPopupRect` pure positioning fn + tests

**Files:** Create `source/tyControls.Popup.pas` (pure fn only first); Create `tests/test.popup.pas`; Modify `tycontrols.lpk`, `tests/tytests.lpr`.

- [ ] **Step 1 — test** `tests/test.popup.pas`:
```pascal
unit test.popup;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Popup;
type
  TPopupGeomTest = class(TTestCase)
  published
    procedure TestDropsBelowWhenRoom;
    procedure TestFlipsAboveWhenNoRoom;
  end;
implementation
procedure TPopupGeomTest.TestDropsBelowWhenRoom;
var r: TRect;
begin
  // anchor at y=100..120 on a 1000px-tall screen; 200px content -> drops below at y=120
  r := TyPopupRect(Rect(50, 100, 250, 120), 200, 200, 1000);
  AssertEquals('top below anchor', 120, r.Top);
  AssertEquals('height', 200, r.Bottom - r.Top);
  AssertEquals('left aligned', 50, r.Left);
  AssertEquals('width', 200, r.Right - r.Left);
end;
procedure TPopupGeomTest.TestFlipsAboveWhenNoRoom;
var r: TRect;
begin
  // anchor near the bottom (y=900..920), 200px content, 1000px screen -> not enough below -> flip above
  r := TyPopupRect(Rect(50, 900, 250, 920), 200, 200, 1000);
  AssertEquals('bottom at anchor top', 900, r.Bottom);
  AssertEquals('top = anchor.top - height', 700, r.Top);
end;
initialization
  RegisterTest(TPopupGeomTest);
end.
```
- [ ] **Step 2 — impl** `source/tyControls.Popup.pas` (pure fn only for now):
```pascal
unit tyControls.Popup;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Forms, LCLType, LCLIntf;

// Screen rect for a dropdown of (AContentW x AContentH) anchored to AAnchorScreen.
// Drops below the anchor; flips above when there isn't AContentH room below within AScreenH.
function TyPopupRect(const AAnchorScreen: TRect; AContentW, AContentH, AScreenH: Integer): TRect;

implementation
function TyPopupRect(const AAnchorScreen: TRect; AContentW, AContentH, AScreenH: Integer): TRect;
var belowTop: Integer;
begin
  belowTop := AAnchorScreen.Bottom;
  if (belowTop + AContentH > AScreenH) and (AAnchorScreen.Top - AContentH >= 0) then
  begin
    Result.Top := AAnchorScreen.Top - AContentH;          // flip above
    Result.Bottom := AAnchorScreen.Top;
  end
  else
  begin
    Result.Top := belowTop;
    Result.Bottom := belowTop + AContentH;
  end;
  Result.Left := AAnchorScreen.Left;
  Result.Right := AAnchorScreen.Left + AContentW;
end;
end.
```
- [ ] **Step 3** — wire unit into `tycontrols.lpk`, `test.popup` into `tytests.lpr`. Build + run → 2 tests pass, failures 0.
- [ ] **Step 4** — Commit `feat(popup): TyPopupRect drop/flip positioning fn + tests`.

## Task A2: `TTyDropdownPopup` (extract the window logic from ComboBox)

**Files:** Modify `source/tyControls.Popup.pas` (add the class); read `source/tyControls.ComboBox.pas` for the exact logic to lift.

- [ ] **Step 1** — Add `TTyDropdownPopup = class` to `tyControls.Popup.pas`. Lift the popup-window mechanics from `TTyComboBox` (read `DoDropDown` ~line 343-392, `ApplyPopupRegion`, `PopupResize`, `PopupDeactivate`, the deferred-Qt-reapply + the deactivate-reopen-race guard, `ForceSquareSurface := TyQtIsWayland`). API:
```pascal
  TTyDropdownPopup = class
  private
    FForm: TForm;
    FContent: TControl;
    FRect: TRect;
    FCornerRadiusLogical: Integer;
    FOnClose: TNotifyEvent;
    procedure FormDeactivate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure ApplyRegion(AWidth, AHeight: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetContent(AControl: TControl);          // parented into the form, alClient
    procedure Popup(AAnchor: TControl; AContentWidth, AContentHeight: Integer);
    procedure Close;
    function IsOpen: Boolean;
    property CornerRadiusLogical: Integer read FCornerRadiusLogical write FCornerRadiusLogical;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property Form: TForm read FForm;                    // for the owner to set KeyPreview/OnKeyDown
  end;
```
`Popup` computes `FRect := TyPopupRect(AnchorScreenRect, AContentWidth, AContentHeight, Screen.Height)`, sizes/shows the form non-activating, calls `ApplyRegion`, and stores state for the Qt deferred re-apply. `Close` hides + fires `OnClose` (guard the deactivate-reopen race exactly as ComboBox did). `Destroy` frees the form.
- [ ] **Step 2** — Build runtime pkg → exit 0. Add a smoke test to `tests/test.popup.pas` (`TPopupSmokeTest`): create a popup, `SetContent(a TPanel)`, but DO NOT require showing a real window headlessly — just assert `IsOpen=False` initially and that Create/Destroy don't raise. (Real show is covered by the ComboBox tests after migration.)
- [ ] **Step 3** — Commit `feat(popup): TTyDropdownPopup window helper (extracted dropdown mechanics)`.

## Task A3: migrate `TTyComboBox` onto `TTyDropdownPopup`

**Files:** Modify `source/tyControls.ComboBox.pas`.

- [ ] **Step 1** — Replace the inline popup fields/methods with a `FPopup: TTyDropdownPopup` that hosts `FPopupList: TTyListBox`. `DoDropDown` → ensure popup created once, `FPopup.SetContent(FPopupList)`, set the list's controller/items/selection, `FPopup.CornerRadiusLogical := <resolved list radius>`, `FPopup.Form.KeyPreview/OnKeyDown := @PopupKeyDown`, `FPopup.OnClose := @PopupClosed` (clears dropped state), `FPopup.Popup(Self, Width, ComputePopupHeight(Font.PixelsPerInch))`. Remove `ApplyPopupRegion`/`PopupResize`/`PopupDeactivate`/the raw `FPopup: TForm` window code (now in the helper). Keep `ComputePopupHeight` (combo-specific) + `PopupListChange`/`PopupKeyDown`. `DroppedDown` → `FPopup <> nil and FPopup.IsOpen`.
- [ ] **Step 2 — verify the regression guard:** `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → **all existing ComboBox tests stay green**, failures 0. If a combo test breaks, the migration changed behavior — fix the helper/migration, don't weaken the test.
- [ ] **Step 3** — Commit `refactor(combobox): use shared TTyDropdownPopup for the dropdown (behavior unchanged)`.

---

# PHASE B — TTyCalendar

## Task B1: calendar date-math pure functions + tests

**Files:** Create `source/tyControls.Calendar.pas` (pure fns + types only first); Create `tests/test.calendar.pas`; wire into lpk + tytests.lpr.

- [ ] **Step 1 — test** `tests/test.calendar.pas` covering: month grid (Feb 2024 leap = 29 days; first-day-of-week Sunday vs Monday changes the leading blanks; grid is exactly 42 entries; first cell ≤ the 1st, last ≥ the month end), `TyCalendarInRange`/`TyCalendarClampDate` (below min → min, above max → max, 0 bounds = unbounded), `TyDecadeStart(2026)=2020`, `TyISOWeekNumber` (a known date, e.g. 2026-01-01), `TyWeekdayOrder(wdMonday)` = `[1,2,3,4,5,6,0]`. Write exact-value asserts. (Use `EncodeDate` to build inputs.)
- [ ] **Step 2 — impl** the pure section of `source/tyControls.Calendar.pas`:
```pascal
unit tyControls.Calendar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, DateUtils, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyWeekDay = (wdSunday, wdMonday, wdTuesday, wdWednesday, wdThursday, wdFriday, wdSaturday);
  TTyCalView = (cvmDays, cvmMonths, cvmYears, cvmDecades);
  TTyDateGrid = array[0..41] of TDateTime;   // 6 rows x 7 cols

function TyWeekdayOrder(AFirst: TTyWeekDay): TWeekDaySet;   // see note below; or array[0..6] of Integer
function TyCalendarMonthGrid(AYear, AMonth: Word; AFirst: TTyWeekDay): TTyDateGrid;
function TyCalendarInRange(ADate, AMin, AMax: TDateTime): Boolean;
function TyCalendarClampDate(ADate, AMin, AMax: TDateTime): TDateTime;
function TyDecadeStart(AYear: Integer): Integer;
function TyISOWeekNumber(ADate: TDateTime): Integer;
```
Implement: `TyWeekdayOrder` returns the 7 day-of-week indices (0=Sun) starting at `AFirst` (use an `array[0..6] of Integer`, NOT a set — fix the declaration to `TTyWeekdayOrderArray = array[0..6] of Integer`). `TyCalendarMonthGrid`: find the 1st of the month, walk back to the first `AFirst`-weekday on/before it, then fill 42 consecutive days. `InRange`: `(AMin=0) or (ADate>=AMin)) and ((AMax=0) or (ADate<=AMax))` on the date part (`DateOf`). `ClampDate` accordingly. `TyDecadeStart`: `(AYear div 10)*10`. `TyISOWeekNumber`: use `DateUtils.WeekOfTheYear` (ISO-8601).
- [ ] **Step 3** — wire into lpk + tytests.lpr. Build + run → green.
- [ ] **Step 4** — Commit `feat(calendar): date-math pure fns (month grid / range / zoom / ISO week) + tests`.

## Task B2: `TTyCalendar` control — Days view render + select + keyboard

**Files:** Modify `source/tyControls.Calendar.pas` (add the control).

- [ ] **Step 1** — Add `TTyCalendar = class(TTyCustomControl)` per the spec API (`Date`/`MinDate`/`MaxDate`/`FirstDayOfWeek`/`WeekNumbers`/`ShowToday`/`ReadOnly`, `OnChange`/`OnViewChange`, `GetStyleTypeKey='TyCalendar'`, default size ~240x220). For THIS task implement only the **Days** view: `RenderTo` draws `DrawFrame` (TyCalendar) + header band (`‹` `<MonthName YYYY>` `›` via `TyCalendarTitle` text + `DrawGlyph` arrows) + weekday row (`TyCalendarWeekday`, names from `DefaultFormatSettings.ShortDayNames` reordered by `TyWeekdayOrder`) + the 6x7 day grid from `TyCalendarMonthGrid`, each cell resolved from `TyCalendarCell` with states: `:selected` when `DateOf(cell)=DateOf(Date)`, `:disabled` when other-month or out-of-range, today = an accent outline when `ShowToday and DateOf(cell)=DateOf(Now)`. Optional week-number column when `WeekNumbers`. A pure helper `TyCalendarHitCell(const AClientRect: TRect; AHeaderH, AWeekdayH, AColW, ARowH, ACols: Integer; X, Y: Integer): Integer` returns the grid index at a point (testable). Mouse-down on a day selects (clamp to range, ignore disabled) → `Date := ...; OnChange`. Mouse-down on arrows = prev/next month (FViewAnchor month state). Keyboard: arrows move a focused-cell index (re-derive into the grid, crossing months), PageUp/Dn = ±1 month, Home/End = first/last enabled day, Enter/Space select.
- [ ] **Step 2** — Behavior tests (in `test.calendar.pas`, a `TCalendarControlTest` using a probe exposing `RenderTo` + synthetic key/mouse): select a day via key+Enter → `Date` updates + `OnChange` fired once; out-of-range day stays unselectable; PageDown moves to next month. Pixel test: selected day cell has an accent-dominant pixel under a known inline theme.
- [ ] **Step 3** — Build + run → green. Commit `feat(calendar): TTyCalendar Days view (grid render, select, keyboard, range)`.

## Task B3: drill-down views (Months / Years / Decades)

**Files:** Modify `source/tyControls.Calendar.pas`.

- [ ] **Step 1** — Add `ViewMode` runtime state + the zoom logic. Header title click → `TyCalendarZoomOut(ViewMode)` (Days→Months→Years→Decades, capped); a cell click in a non-Days view → set the period + `TyCalendarZoomIn` one level. `RenderTo` branches on `ViewMode`: Months = 4x3 month-name grid (`ShortMonthNames`), title `<YYYY>`, arrows ±1 year; Years = 4x3 years of the decade, title `<decadeStart>–<+9>`, arrows ±10y; Decades = 4x3 decades of the century, arrows ±100y. Reuse `TyCalendarCell` for all view cells; reuse a shared 4x3/6x7 grid hit-test. `OnViewChange` fires on zoom. Pure fns `TyCalendarZoomIn`/`TyCalendarZoomOut(AView): TTyCalView`.
- [ ] **Step 2** — Tests: zoom-out from Days reaches Decades in 3 steps; picking a month in Months view zooms to Days of that month; picking in Years/Decades narrows correctly. Build + run → green.
- [ ] **Step 3** — Commit `feat(calendar): drill-down Months/Years/Decades views + zoom`.

---

# PHASE C — TTyDateTimePicker

## Task C1: format + segment pure functions + tests

**Files:** Create `source/tyControls.DateTimePicker.pas` (pure section only); Create `tests/test.datetimepicker.pas`; wire in.

- [ ] **Step 1 — test** with a PINNED `TFormatSettings` (so locale doesn't leak): `TyFormatDateTime(EncodeDate(2026,3,7), 'yyyy-mm-dd', fmt) = '2026-03-07'`; `TyDateTimeSegments('yyyy-mm-dd')` yields 3 segments (year span 0..3 / month 5..6 / day 8..9) with kinds year/month/day; `TySegmentStep` on the month segment of 2026-12-15 by +1 rolls to January (and carries the year per LCL behavior — decide: roll-within-segment, NO carry, matching LCL DateTimePicker which rolls the field independently — document it); `TySegmentTypeDigit` building '0','3' into the month segment yields 3 and auto-advances.
- [ ] **Step 2 — impl** the pure section:
```pascal
type
  TTyDateTimeKind = (dtkDate, dtkTime);
  TTySegKind = (skNone, skDay, skMonth, skYear, skHour, skMinute, skSecond, skAMPM);
  TTySegment = record Kind: TTySegKind; StartCh, LenCh: Integer; end;
  TTySegmentArray = array of TTySegment;

function TyFormatDateTime(AValue: TDateTime; const AFormat: string; const AFmt: TFormatSettings): string;
function TyDateTimeSegments(const AFormat: string): TTySegmentArray;     // parse format letters into editable segments
function TySegmentStep(AValue: TDateTime; const ASeg: TTySegment; ADelta: Integer): TDateTime;
function TySegmentRange(const ASeg: TTySegment; out AMin, AMax: Integer): Boolean;  // e.g. month 1..12
```
`TyDateTimeSegments` scans the format for runs of `y/m/d/h/n/s` (and `am/pm`), emitting a segment per run (skip literals/separators). `TySegmentStep` decodes the value, adjusts the one field with **roll-within-field** (month 12→1 with no year carry — LCL-style; document this in a comment), re-encodes. `TySegmentRange` returns the field's valid range. Decision: **roll-within-field, no carry** (matches LCL `TDateTimePicker`).
- [ ] **Step 3** — wire in. Build + run → green. Commit `feat(datetimepicker): format + segment pure fns (parse/step/range) + tests`.

## Task C2: `TTyDateTimePicker` field render + segment editing

**Files:** Modify `source/tyControls.DateTimePicker.pas` (add the control).

- [ ] **Step 1** — Add `TTyDateTimePicker = class(TTyCustomControl)` per the spec API. `GetStyleTypeKey='TyDateTimePicker'`. `RenderTo`: `DrawFrame` (TyDateTimePicker, edit-like) + the formatted text drawn via `DrawText`, with the ACTIVE segment's character span highlighted (a `--selection` fill behind those chars — measure the segment's pixel span by measuring the substring up to `StartCh` and the segment text). A right-side button area (`TyDateTimeButton`): `dtkDate` draws a chevron-down (`tgChevronDown`); `dtkTime` draws up+down arrows. Reuse the blinking caret facility (`TyCaretVisible`). Segment editing keyboard: `←/→` change active segment, digits edit via `TySegmentTypeDigit`, `↑/↓` + wheel = `TySegmentStep(±1)`, Home/End first/last segment, Enter/focus-out commit+clamp to `[MinDate,MaxDate]` + `OnChange`. The spin button (dtkTime) / a press on the date chevron triggers the dropdown (C3).
- [ ] **Step 2** — Tests (probe with synthetic keys): typing into the year segment updates `DateTime`; `↑` on the month segment steps it (roll, no carry); commit clamps to MaxDate; `OnChange` fires. A render smoke/pixel test (the active-segment highlight present). Build + run → green.
- [ ] **Step 3** — Commit `feat(datetimepicker): field render + segment editing (type/spin/nav/clamp)`.

## Task C3: dtkDate dropdown (popup + calendar) + dtkTime spin + ShowCheckBox

**Files:** Modify `source/tyControls.DateTimePicker.pas`.

- [ ] **Step 1** — `dtkDate` dropdown: a `FPopup: TTyDropdownPopup` hosting a `FCalendar: TTyCalendar`; opening (chevron click / Alt+Down / F4) seeds the calendar (`Date`/`MinDate`/`MaxDate`/`FirstDayOfWeek`/`Controller`), `FPopup.Popup(Self, <calWidth>, <calHeight>)`; the calendar's `OnChange` writes the date back, fires `OnChange`/`OnCloseUp`, closes the popup; `OnDropDown` fires on open. `dtkTime`: the up/down buttons step the active segment (no popup). `ShowCheckBox`: draw a `TyCheckBox`-style box at the left; when `ShowCheckBox` and not `Checked`, grey the text + block editing/dropdown; toggling the box fires `OnChecked` + enables. `DroppedDown` get/set.
- [ ] **Step 2** — Tests: open dropdown → pick a calendar day → `DateTime` updates + popup closes + `OnCloseUp` fired; `ShowCheckBox` unchecked greys + `Checked:=False` blocks edits + `OnChecked` fires on toggle. (Dropdown open may need a real window; if headless can't show it, test the wiring via the calendar's OnChange handler directly + a probe, like the combo tests do.) Build + run → green.
- [ ] **Step 3** — Commit `feat(datetimepicker): dtkDate calendar dropdown + dtkTime spin + ShowCheckBox null`.

---

# PHASE D — theme, design-time, demo, finish

## Task D1: theme typeKeys across all themes + goldens

**Files:** all `themes/*.tycss`; regenerate `DefaultTheme.pas` + `BuiltinThemeData.pas`; `tests/test.themes.pas` (GGRID); `tests/golden/*`; `tests/test.defaulttheme.pas`.

- [ ] **Step 1** — Add token-based blocks to EVERY theme (`light/dark/showcase/auto/green/system`; green uses concrete values where it lacks a token — it lacks `--surface-chrome` etc., see the ① learnings):
```css
TyCalendar { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: 6px; font-size: var(--font-size-base); }
TyCalendarTitle { color: var(--on-surface); font-weight: var(--font-weight-bold); }
TyCalendarTitle:hover { color: var(--accent); }
TyCalendarWeekday { color: var(--muted); font-size: var(--font-size-base); }
TyCalendarCell { background: none; color: var(--on-surface); border-radius: var(--radius-sm); }
TyCalendarCell:hover { background: var(--surface-hover); }
TyCalendarCell:selected { background: var(--accent); color: var(--on-accent); }
TyCalendarCell:disabled { color: var(--muted); }
TyDateTimePicker { background: var(--input-bg); color: var(--on-surface); border-color: var(--border); border-width: var(--input-border-width); border-radius: var(--radius); padding: 4px 6px; font-size: var(--font-size-base); }
TyDateTimePicker:hover { border-color: var(--input-border-hover); }
TyDateTimePicker:focus { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyDateTimePicker:disabled { opacity: var(--disabled-opacity); }
TyDateTimeButton { background: var(--surface-chrome); color: var(--on-surface); }
TyDateTimeButton:hover { background: var(--surface-hover); color: var(--accent); }
```
- [ ] **Step 2** — `powershell -File gen-defaulttheme.ps1` AND `powershell -File gen-builtinthemes.ps1` (the latter for auto/system mirrors — needed, per ①). Confirm `TestBuiltinMatchesLightTheme` + dual-base/system sync pass.
- [ ] **Step 3** — Extend `GGRID` in `tests/test.themes.pas` by the new typeKeys (`'TyCalendar|','TyCalendarTitle|','TyCalendarWeekday|','TyCalendarCell|','TyDateTimePicker|','TyDateTimeButton|'`) and bump the array bound by 6. Delete `tests/golden/{light,dark,showcase}.golden.txt`, run once to re-bootstrap, run again → green; confirm the golden diff is **purely additive**.
- [ ] **Step 4** — Add `AssertBg('TyCalendar', [])` / `AssertBg('TyDateTimePicker', [])` to `TestBuiltinCoversAllTypeKeys`.
- [ ] **Step 5** — Full suite green. Commit `feat(theme): calendar + datetimepicker typeKeys across all themes + goldens`.

## Task D2: events RTTI guard

- [ ] Create `tests/test.datetime.events.pas` asserting `TTyCalendar` publishes the standard set + `OnChange`/`OnViewChange`, and `TTyDateTimePicker` publishes the set + `OnChange`/`OnDropDown`/`OnCloseUp`/`OnChecked` (via `TypInfo.GetPropInfo`). Wire into `tytests.lpr`. Build + run → green. Commit `test(datetime): RTTI guard for published events`.

## Task D3: design-time registration + icons

- [ ] Add `tyControls.Calendar, tyControls.DateTimePicker` to `designtime/tyControls.Design.pas` `uses` + `TTyCalendar, TTyDateTimePicker` to `RegisterComponents`. Add `GTTyCalendar`/`GTTyDateTimePicker` glyphs to `tools/genicons/genicons.lpr` (`Glyphs[]` + bound), the two class names to `scripts/gen-icons.ps1 $classes` and `tests/test.paletteicons.pas CClasses` (bump bound). Run `pwsh -File scripts/gen-icons.ps1` (drift-guard must pass). `lazbuild tycontrols_dt.lpk` exit 0; suite green (`test.paletteicons`). Commit `feat(designtime): register calendar + datetimepicker on the palette + icons`.

## Task D4: demo + finish

- [ ] Place a `TTyCalendar` + a `TTyDateTimePicker` (one `dtkDate` with `ShowCheckBox`, one `dtkTime`) in `examples/demo/mainform.lfm` + fields + `uses`. `lazbuild examples/demo/demo.lpi` exit 0. Commit `example(demo): showcase TTyCalendar + TTyDateTimePicker`.
- [ ] Final: full verify (all packages + tests + demo), then **superpowers:finishing-a-development-branch** → merge to main. Update `new-controls-program` memory (② done).

---

## Deferred / non-goals (confirm none dropped silently)

Multi-select/range selection; holiday/owner-draw day decoration; time-zone; inline (non-popup) calendar mode for the picker; a month/year text drop list (drill-down zoom replaces it). See spec §Scope.
