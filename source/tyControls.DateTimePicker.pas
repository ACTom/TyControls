unit tyControls.DateTimePicker;
{$mode objfpc}{$H+}
{
  tyControls.DateTimePicker — pure-function section (Task C1)
                            + TTyDateTimePicker control (Task C2 + C3).

  No-carry / roll-within-field decision
  ======================================
  TySegmentStep adjusts exactly ONE field (year/month/day/hour/minute/second)
  and wraps it within its own valid range WITHOUT carrying into adjacent fields.
  Examples:
    month 12 + 1  → month 1,  year unchanged
    hour  23 + 1  → hour  0,  date unchanged
    day   31 + 1  → day   1,  month unchanged

  This matches the behaviour of the LCL TDateTimePicker (and Windows
  DATETIMEPICK_CLASS), where each segment spins independently. The day is
  additionally clamped to the length of the *current* month after rolling, so
  e.g. rolling from day 31 in a 30-day month still yields a valid date.

  Fixed-width field normalization
  ================================
  TyEffectiveFormat normalizes single field specifiers to double (m→mm, d→dd,
  h→hh, n→nn, s→ss) so every rendered field is zero-padded to a fixed width.
  This means format character positions == rendered text positions, making the
  segment highlight and click hit-test accurate regardless of the actual value.
  yyyy/yy are left unchanged; literals are preserved verbatim.

  Digit buffer / commit-on-leave model (Task C2)
  ================================================
  FDigitBuffer accumulates typed digit characters for the active segment but
  does NOT write to FDateTime until the segment is "complete" or a finalize
  trigger fires.  While a buffer is active the rendered text shows the buffered
  digits (zero-padded / as-typed) instead of the FDateTime value, so the user
  sees exactly what they typed with no premature clamping flicker.

  Finalize triggers: segment auto-complete (length-full OR value×10 > segMax),
  ←/→/Home/End/Enter/Escape on navigation, ↑/↓ (step), focus-out.
  On finalize with a non-empty buffer: parse → clamp to [segMin,segMax] →
  write FDateTime → clamp to [MinDate,MaxDate] → CommitAndFire → clear buffer.

  dtkDate dropdown (Task C3)
  ==========================
  FPopup: TTyDropdownPopup is lazy (created on first open) and lives for the
  lifetime of the picker.  FCalendar: TTyCalendar is owned by the PICKER
  (Create(Self)) — not by the popup form — so FreeAndNil(FPopup) never
  double-frees the calendar, and the destructor frees both independently:
    FreeAndNil(FPopup);    // frees the popup helper + its form (not calendar)
    FreeAndNil(FCalendar); // frees the calendar (owned by Self)
  SetContent(FCalendar) only parents the calendar into the popup form; it does
  not transfer ownership (the popup's destructor sets FContent := nil without
  freeing it, per TTyDropdownPopup.Destroy).

  Calendar OnAccept vs OnChange:
    OnAccept fires when the user clicks a day cell or presses Enter/Space; this
    is the CLOSE trigger so that arrow-key navigation does NOT dismiss the popup.
    OnChange fires on every navigation step (arrow keys) and updates FDateTime
    immediately (so the picker's field text tracks while the popup is open) but
    does NOT close the popup.

  ShowCheckBox / Checked inert state:
    When ShowCheckBox=True and Checked=False the control is "null": all editing
    (digit entry, step, wheel, dropdown open) is blocked.  Clicking the checkbox
    area toggles Checked and fires OnChecked.  When ShowCheckBox=False the
    Checked property is irrelevant and IsInert always returns False.
}

interface

uses
  Classes, SysUtils, Types, DateUtils, Math, LazUTF8,
  Controls, Graphics, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Animation,
  tyControls.Popup, tyControls.Calendar;

const
  { LCL's sentinels for "as far as this control will go" (datetimepicker.pas:63, :77).
    LCL seeds MinDate/MaxDate to these so its picker is ALWAYS bounded; ours keeps 0 =
    unbounded (changing that would flip the meaning of every `if MinDate <> 0` in the
    wild), but the two values are now reachable by name, and an UNBOUNDED field is
    still held inside them so a user cannot type a year the calendar cannot draw.
    TheSmallestDate is 1 Oct 1752: LCL's own comment says widgetset calendars
    misrender anything earlier, and a date entered here can end up in one of those. }
  TyTheSmallestDate = TDateTime(-53780.0);   // 1 Oct 1752
  TyTheBiggestDate  = TDateTime(2958465.0);  // 31 Dec 9999
  TheSmallestDate   = TyTheSmallestDate;
  TheBiggestDate    = TyTheBiggestDate;

  { LCL's TTimeFormat members (datetimepicker.pas:105-107) as the patterns they mean,
    so `DTP.TimeFormat := tf24` from a ported unit compiles and does the right thing.
    Ours is a FormatDateTime pattern rather than an enum -- the picker is format-string
    driven end to end -- so these are the two patterns that enum selects, not a second
    type. Anything else is still just a pattern. }
  tf12 = 'hh:nn:ss AM/PM';
  tf24 = 'hh:nn:ss';

  { The pivot LCL defaults CenturyFrom to (datetimepicker.pas:4079). }
  TyDefaultCenturyFrom = 1941;

  { ── The empty value ──────────────────────────────────────────────────────

    "No date chosen" needs a representation, and TDateTime has no spare member --
    every bit pattern in range is a real instant, and 0 is 30 Dec 1899, a date a
    form can legitimately hold. So the empty state is a value FAR OUTSIDE the
    range, exactly as LCL does it (datetimepicker.pas:60), and to the same number
    so a value handed over from an LCL picker or read out of the same database
    column arrives here still empty.

    TyDateIsNull is deliberately a RANGE test, not `= TyNullDate`: a value that
    round-tripped through a .lfm, a float cast or a NaN from a database driver
    need not come back bit-identical, and "slightly different infinity" must not
    read as "5 June 4000-something". Every WRITE normalises to TyNullDate, so the
    stored value is always exactly this one and plain comparisons downstream stay
    honest; every READ tests the range. }
  TyNullDate = TDateTime(1.7e+308);
  NullDate   = TyNullDate;          // LCL's spelling

  { What an empty field shows. LCL's own default (datetimepicker.pas:4077), and
    deliberately a LITERAL rather than a resourcestring: it is a property default,
    so translating it would make the .lfm a form writes depend on the locale it was
    saved under. An application that wants "(none)" -- in any language -- sets
    TextForNullDate itself, and that string is the app's to translate. }
  TyDefaultTextForNullDate = 'NULL';

type
  TTyDateTimeKind = (dtkDate, dtkTime);

  { skMilliSec closes the one field a format string could DISPLAY but nothing could
    select, type or step: EncodeDateTime preserves the millisecond component, so a
    value seeded from Now carried a sub-second nobody could see or clear. }
  TTySegKind = (skNone, skDay, skMonth, skYear, skHour, skMinute, skSecond, skAMPM,
                skMilliSec);

  { LCL's TDateTimePickerOption (datetimepicker.pas:131-146) minus dtpoFlatButton,
    which selects between a raised and a flat drop-down button -- a purely visual axis
    that belongs in the theme here, and which our chevron already draws flat. Adding it
    as a published flag nothing reads is exactly the defect this pass exists to remove. }
  TTyDateTimePickerOption = (
    dtpoDoChangeOnSetDateTime,  // fire OnChange on a programmatic DateTime write too
    dtpoEnabledIfUnchecked,     // keep the field editable while the checkbox is clear
    dtpoAutoCheck,              // set Checked when the value is changed
    dtpoResetSelection);        // focus-in always lands on the first field
  TTyDateTimePickerOptions = set of TTyDateTimePickerOption;
  TDateTimePickerOption  = TTyDateTimePickerOption;
  TDateTimePickerOptions = TTyDateTimePickerOptions;

  { Which affordance sits at the right-hand edge. LCL's TDTDateMode
    (datetimepicker.pas:125) member for member.
      dmComboBox  the default, and the only value that keeps Kind in charge: a date
                  field drops a calendar, a time field spins.
      dmUpDown    spin buttons, whatever the Kind -- a date field that steps without
                  ever opening a popup.
      dmNone      no button, and no button COLUMN either: the text gets the width back.
                  This is the one a grid cell or a compact toolbar wants; before, the
                  space was reserved whether or not anything could use it. }
  TTyDTDateMode = (dmComboBox, dmUpDown, dmNone);
  TDTDateMode   = TTyDTDateMode;

  { Describes one editable segment inside a formatted date/time string.
    StartCh and LenCh are 0-based character indices into the EFFECTIVE FORMAT
    string (see TyEffectiveFormat), which has the same positions as the rendered
    text because every field is rendered fixed-width (zero-padded). }
  TTySegment = record
    Kind:    TTySegKind;
    StartCh: Integer;   // 0-based start in the effective format string
    LenCh:   Integer;   // number of format characters in this segment
  end;

  TTySegmentArray = array of TTySegment;

{ Normalize AFormat so every single-letter field specifier becomes double:
    m → mm,  d → dd,  h → hh,  n → nn,  s → ss
  yyyy and yy are left unchanged.  Literal characters and quoted text are
  copied verbatim.  The result is used for BOTH rendering (TyFormatDateTime)
  and segment scanning (TyDateTimeSegments), ensuring that format character
  positions equal rendered-text positions (every field is leading-zero padded). }
function TyEffectiveFormat(const AFormat: string): string;

{ True when ADateTime carries no date at all -- see TyNullDate for why this is a
  range test and not an equality one. LCL spells it IsNullDate
  (datetimepicker.pas:600) and computes the same predicate. }
function TyDateIsNull(const ADateTime: TDateTime): Boolean;

{ Equality that treats two empty values as equal. Ordinary `=` would answer False
  for two nulls that came from different round trips, which is how "the value did
  not change" turns into a spurious OnChange -- and, worse, how an Escape that
  should restore an empty field restores a date instead.
  LCL: EqualDateTime, datetimepicker.pas:594. }
function TyEqualDateTime(const A, B: TDateTime): Boolean;

{ Thin deterministic wrapper around the RTL FormatDateTime.
  Always uses AFmt so locale never leaks. }
function TyFormatDateTime(AValue: TDateTime; const AFormat: string;
  const AFmt: TFormatSettings): string;

{ Scan AFormat and return one TTySegment per recognisable date/time field run.
  Supported tokens (FPC FormatDateTime conventions):
    y / yy / yyy / yyyy  → skYear
    m / mm               → skMonth  (but see the m-after-h rule below)
    d / dd               → skDay
    h / hh               → skHour
    n / nn               → skMinute
    s / ss               → skSecond
    am/pm  or  a/p       → skAMPM

  m-after-h rule (FPC / Delphi convention):
    An "m"-run that immediately follows an "h"/"hh" token (ignoring separator
    characters in between) is treated as minutes (skMinute), not as month
    (skMonth).  This handles formats like 'hh:mm' or 'h:m' correctly while
    'mm/dd/yyyy' keeps the first "m" as month.

  Literal characters (separators, spaces, quoted text) are skipped — they do
  NOT produce segments.  Uppercase input is accepted (case-insensitive scan). }
function TyDateTimeSegments(const AFormat: string): TTySegmentArray;

{ Adjust the single field described by ASeg in AValue by ADelta steps.
  Roll-within-field, no carry (see unit header comment). }
function TySegmentStep(AValue: TDateTime; const ASeg: TTySegment;
  ADelta: Integer): TDateTime;

{ Return the valid [AMin, AMax] range for ASeg's field.
  Returns False (and leaves AMin/AMax 0) when ASeg.Kind = skNone. }
function TySegmentRange(const ASeg: TTySegment;
  out AMin, AMax: Integer): Boolean;

{ Return the segment index (0-based into ASegs) whose character span contains
  ACharIndex (0-based). Returns -1 when ACharIndex is outside all segments.
  Used for click hit-testing: measure the substring up to the click → pass the
  resulting character offset here. }
function TyDateTimeActiveSegAt(const ASegs: TTySegmentArray;
  ACharIndex: Integer): Integer;

{ The next offset the click hit-test may stop at, walking forward from the 0-based BYTE
  offset AOffset in AText. Offsets are bytes because that is what the segment table holds
  (TTySegment.StartCh counts the format string's bytes, and the fixed-width fields make the
  format's offsets equal the rendered text's), but they must only ever land BETWEEN
  characters: the walk this replaced stepped one byte at a time, so with a Chinese format
  ('yyyy年mm月dd日' — every separator three bytes) it measured prefixes that cut a separator
  in half. What a renderer makes of a partial sequence's width is anyone's guess, so the
  click could resolve to the neighbouring field. A named function purely so the invariant —
  every offset the walk visits is a character boundary — is testable without a mouse. }
function TyDateTimeNextCharOffset(const AText: string; AOffset: Integer): Integer;

{ Renders AValue with AFormat AND reports where each field landed in the RESULT --
  ASpans[i].StartCh/LenCh are byte offsets into the returned string, matched one for
  one with TyDateTimeSegments(AFormat).

  This exists because the old model inferred rendered offsets from the FORMAT string:
  TyEffectiveFormat doubled every single specifier so that "the 4th format character"
  and "the 4th rendered character" were the same place. That invariant bought the
  segment highlight and the click hit-test their arithmetic, and it cost two things.
  It made LeadingZeros=False unreachable by construction -- an author's 'd/m/yyyy' was
  silently rewritten to 'dd/mm/yyyy', a format string that appeared to be ignored. And
  it was already false for month NAMES: 'mmmm' is 4 format characters and 'September'
  is 9 rendered ones, so every field after the month sat at the wrong pixel and a click
  on the year selected the month. Measuring the render instead of indexing the format
  removes both at once.

  ALeadingZeros=False drops the padding zero from day, month and hour -- the three
  fields LCL's LeadingZeros governs (datetimepicker.pas:2795-2836). Minute, second and
  millisecond stay padded there and here: '9:5' is not a time. }
function TyRenderDateTime(AValue: TDateTime; const AFormat: string;
  const AFmt: TFormatSettings; ALeadingZeros: Boolean;
  out ASpans: TTySegmentArray): string;

{ Expands a year the user typed with fewer than three digits, against the pivot
  ACenturyFrom: at or above the pivot's last two digits it belongs to the pivot's
  century, below it to the next one. LCL does the same against CenturyFrom
  (datetimepicker.pas:1690-1697, default 1941). Longer input is already explicit and
  passes through untouched. }
function TyExpandShortYear(ATyped: Integer; ADigits: Integer;
  ACenturyFrom: Word): Integer;

{ Every horizontal landmark the field has, in DEVICE pixels relative to its client
  rect's origin -- what TyDateTimeRects (below the class) answers.

  The paint and the click hit-test used to tile the field's width SEPARATELY, each
  deriving the padding inset, the checkbox column and the button column from the same
  tokens by its own arithmetic, with a comment in the hit-test asking whoever edited one
  to remember the other. That is the shape the month-name bug came out of: two
  computations that agreed right up until they didn't, and a note where an invariant
  should have been. RenderTo, MouseDown and the preferred-width query now read their x
  out of THIS and nothing re-derives one; the model is TyHeaderSectionRects
  (HeaderControl.pas), for exactly the same reason.

  Text is the box the string is drawn in AND hit-tested against, already clear of the
  padding, the checkbox and the button column. CheckBox, Button, ButtonUp and ButtonDown
  come back EMPTY when the field has no such part, so a caller that forgets to ask
  whether the part exists still cannot hit one that was never drawn. }
type
  TTyDateTimeRects = record
    Text:       TRect;
    CheckBox:   TRect;
    Button:     TRect;
    ButtonUp:   TRect;
    ButtonDown: TRect;
  end;

{ TTyDateTimePicker — field render + segment editing (Task C2).
  Dropdown/time-spin/ShowCheckBox behavior is wired in Task C3. }
type
  TTyDateTimePicker = class(TTyCustomControl)
  private
    FKind:        TTyDateTimeKind;
    FDateTime:    TDateTime;
    FMinDate:     TDateTime;
    FMaxDate:     TDateTime;
    FDateFormat:  string;
    FTimeFormat:  string;
    FReadOnly:    Boolean;
    FOnChange:    TNotifyEvent;
    FOnDropDown:  TNotifyEvent;
    FOnCloseUp:   TNotifyEvent;
    FOnChecked:   TNotifyEvent;
    FShowCheckBox: Boolean;
    FChecked:      Boolean;
    FAlignment:    TAlignment;
    FLeadingZeros: Boolean;
    FCenturyFrom:  Word;
    FOptions:      TTyDateTimePickerOptions;
    FDateMode:     TTyDTDateMode;
    FNullInputAllowed: Boolean;
    FTextForNullDate:  TCaption;
    { The value as of the last focus-in (or the last programmatic write). Escape
      restores it -- see KeyDown. LCL calls this FConfirmedDateTime. }
    FConfirmedDateTime: TDateTime;

    { Segment editing state }
    FSegments:    TTySegmentArray;  // field kinds + their spans in the FORMAT string
    FActiveSeg:   Integer;          // index into FSegments; -1 = none
    FDigitBuffer: string;           // accumulated digit chars for current seg
                                    // (not yet written to FDateTime)

    { Dropdown state (dtkDate) }
    FPopup:       TTyDropdownPopup; // lazy; created on first open; freed in Destroy
    FCalendar:    TTyCalendar;      // owned by Self (NOT the popup form); created
                                    // on first open alongside FPopup; freed in Destroy.
                                    // SetContent(FCalendar) only parents the calendar
                                    // into the popup form — ownership stays with Self.
    FCloseUpTick: QWord;            // tick at last CloseUp for the reopen-race guard
    FMouseDownOnButton: Boolean;    // chevron pressed in MouseDown -> open the dropdown in Click

    { What the LAST PAINT actually used. Recorded, not re-derived.

      The invariant this control exists to hold is "a click lands in the field that was
      drawn under it", and the way it holds it is that RenderTo and MouseDown read one
      FieldLayout call. But a TEST that checks the invariant by calling FieldLayout
      itself is asking the hit test where the paint went -- it proves the two callers of
      one function agree, which they do by construction, and it stays green through a
      change that mirrors the paint and leaves the hit test behind. That is exactly the
      defect this control has already shipped once.
      So the paint writes down what it used, and the guards read THAT. }
    FPaintedRects:   TTyDateTimeRects;
    FPaintedOriginX: Integer;
    FPaintedText:    string;
    FPaintedSpans:   TTySegmentArray;

    function  ActiveFormat: string;
    function  EffectiveFormat: string;
    procedure RebuildSegments;
    function  FormattedText: string;
    { The string the control actually draws, plus where each field landed IN IT.
      Both come out of one call because they must agree: the highlight rect, the click
      hit-test and the digit buffer all index the same string, and the previous code
      derived their offsets from a different one (the format). ASpans is indexed like
      FSegments. }
    procedure BuildDisplay(out AText: string; out ASpans: TTySegmentArray);
    { Digits a field accepts -- what the buffer pads itself to while typing. }
    function  SegmentDigitWidth(const ASeg: TTySegment): Integer;
    { Left edge of the rendered text inside ATextR, honouring Alignment. The highlight
      and the hit-test both need it; drawing gets it from P.DrawText's own alignment. }
    function  TextOriginX(const ATextR: TRect; const AText, AFontName: string;
                AFontSizePx, AFontWeight, APPI: Integer): Integer;
    { Pixel x of the start of character ACharIdx in the rendered text,
      relative to the text-content rect's left edge. }
    function  MeasureCharX(const AText, AFontName: string;
                ACharIdx, AFontSizePx, AFontWeight, APPI: Integer): Integer;
    { Accumulate ADigit into FDigitBuffer only (no FDateTime write).
      Returns True when the segment is now "full" (auto-advance condition)
      so the caller knows to call FinalizeBuffer + advance. }
    function  AccumulateDigit(ADigit: Char): Boolean;
    { Parse FDigitBuffer → clamp to segment range → write FDateTime → clamp
      to [MinDate,MaxDate] → CommitAndFire(AOldVal) → clear buffer.
      No-op when FDigitBuffer is empty.  AAdvance: if True, also increment
      FActiveSeg (auto-advance to next segment). }
    procedure FinalizeBuffer(AOldVal: TDateTime; AAdvance: Boolean);
    { Commit: clamp FDateTime to [MinDate,MaxDate] and fire OnChange if changed.
      AOldVal is the value before any digit/step that triggered the commit. }
    procedure CommitAndFire(AOldVal: TDateTime);
    { Step the active segment by ADelta and commit.
      Moved to protected so test probes (in other units) can call it directly. }
    // procedure StepActiveSeg(ADelta: Integer);   [moved to protected]

    { Returns True when the field is inert: ShowCheckBox=True AND Checked=False.
      All editing and dropdown must be blocked when this is True. }
    function  HourOf(AValue: TDateTime): Integer;
    { True when the active format carries an am/pm token, i.e. the hour field is
      showing 1..12 rather than 0..23. }
    function  TwelveHourFormat: Boolean;
    { True when the right-hand button opens the calendar (as opposed to spinning, or
      not being there at all). Kind alone used to decide this. }
    function  HasDropDownButton: Boolean;
    function  HasSpinButtons: Boolean;
    { The button column's token width in LOGICAL px, 0 under dmNone. There were two of
      these, one scaling through the painter and one through the control's PPI, on the
      stated grounds that the painter carried the theme's own factor -- it does not
      (TTyPainter.Scale is MulDiv by PPI and nothing else), so the second answer was never
      a different answer, only a second place to change. }
    function  ButtonColumnLogical: Integer;
    { The same column in DEVICE px, for the callers that need a width rather than a rect. }
    function  ButtonWidthDev: Integer;
    function  IsInert: Boolean;
    { Which field the click at device AX lands in, or -1. The walk steps a whole CHARACTER
      at a time and stops at the first one whose right edge reaches AX; it lives here so
      that the paint's highlight and this share not just the string and its spans but the
      x the string starts at. }
    function  SegmentAtX(const AText: string; const ASpans: TTySegmentArray;
                AOriginX, AX: Integer; const AFontName: string;
                AFontSizePx, AFontWeight, APPI: Integer): Integer;

    { Dropdown helpers (dtkDate) }
    { Ensure FPopup + FCalendar are created (lazy init).
      Moved to protected so test probes can call it. }
    // procedure EnsurePopup;   [moved to protected]
    { Open the calendar dropdown. }
    procedure OpenDropDown;
    { Close the dropdown (if open). }
    procedure CloseDropDown;
    { TTyDropdownPopup.OnClose handler: marks DroppedDown=False + fires OnCloseUp. }
    procedure PopupClosed(Sender: TObject);
    { Popup form KeyDown: closes on Escape. }
    procedure PopupFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    { TTyCalendar.OnChange handler: writes the date part back to FDateTime +
      fires OnChange (via SetDateTime).  Does NOT close the popup so that
      arrow-key navigation inside the calendar does not dismiss it. }
    procedure CalendarChange(Sender: TObject);
    { TTyCalendar.OnAccept handler: writes the date part back + closes the popup.
      Fires OnChange (via SetDateTime) then FPopup.Close. }
    procedure CalendarAccepted(Sender: TObject);

    procedure SetKind(AValue: TTyDateTimeKind);
    procedure SetDateTime(AValue: TDateTime);
    procedure SetDate(AValue: TDateTime);
    function  GetDate: TDateTime;
    procedure SetTime(AValue: TDateTime);
    function  GetTime: TDateTime;
    procedure SetDateFormat(const AValue: string);
    procedure SetTimeFormat(const AValue: string);
    procedure SetMinDate(AValue: TDateTime);
    procedure SetMaxDate(AValue: TDateTime);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetShowCheckBox(AValue: Boolean);
    procedure SetChecked(AValue: Boolean);
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLeadingZeros(AValue: Boolean);
    procedure SetCenturyFrom(AValue: Word);
    procedure SetDateMode(AValue: TTyDTDateMode);
    procedure SetNullInputAllowed(AValue: Boolean);
    procedure SetTextForNullDate(const AValue: TCaption);
    { The date an EMPTY field starts editing from. Today, pulled inside every bound
      that applies. Typing a digit or pressing an arrow on an empty field has to
      produce a valid date to modify, and picking one at random -- 30 Dec 1899, say,
      which is what the raw zero is -- makes the first keystroke jump the user to a
      century they did not ask for. LCL composes against the same expression
      (datetimepicker.pas:1306). }
    function  NullSeedDate: TDateTime;
    { Re-measure + relayout after anything that changes the rendered content. }
    procedure ContentChanged;
    function  GetDroppedDown: Boolean;
    procedure SetDroppedDown(AValue: Boolean);

  protected
    { Everything the paint and the click both need, out of ONE call: the field's rects,
      the resolved style and font size behind them, the string the control is showing,
      that string's field spans, and the x the string actually starts at. Any x the
      control needs comes from here -- see TyDateTimeRects for what re-deriving one cost
      last time. Protected so a probe can ask where a field is PAINTED and then click it,
      which is the only way a test can catch the two drifting apart again. }
    procedure FieldLayout(const ALocal: TRect; APPI: Integer;
      out ARects: TTyDateTimeRects; out AStyle: TTyStyleSet;
      out AFontSizePx: Integer; out AText: string;
      out ASpans: TTySegmentArray; out AOriginX: Integer);
    { The device-x span field AIndex OCCUPIES -- what the highlight fills. False when
      AIndex names no field. The paint fills exactly this and the hit-test resolves
      clicks inside it, so a click on the middle of a highlighted field must select that
      field: that is the one assertion the two sites cannot both satisfy while disagreeing,
      which is why it is reachable from a probe. }
    function  SegmentSpanX(const AText: string; const ASpans: TTySegmentArray;
                AOriginX, AIndex: Integer; const AFontName: string;
                AFontSizePx, AFontWeight, APPI: Integer;
                out AX1, AX2: Integer): Boolean;
    { Step the active segment by ADelta and commit (protected for test probes). }
    procedure StepActiveSeg(ADelta: Integer);
    { Ensure FPopup + FCalendar are created (lazy init; protected for probes). }
    procedure EnsurePopup;
    { Copy the picker's bounds and value into the reused popup calendar. Split out of
      OpenDropDown so it can be exercised without a real window: everything here can
      RAISE (the calendar rejects an out-of-range date), while the rest of OpenDropDown
      needs a screen. }
    procedure SeedPopupCalendar;

    function  GetStyleTypeKey: string; override;
    { What the field needs to show its own content without clipping: padding, the
      checkbox if there is one, the widest text this format can produce, and the button
      column. Measured, not assumed -- a roomier skin changes every one of those, and a
      fixed 130px meant the text clipped instead of the control growing. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    function  DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
                MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
                X, Y: Integer); override;
    { Open/toggle the dropdown on Click (not MouseDown) — mirrors TTyComboBox so the
      popup isn't immediately deactivated by the mouse-up that follows MouseDown. }
    procedure Click; override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    { Take the current value as the one Escape reverts to. LCL calls this
      ConfirmChanges (datetimepicker.pas:1979-1983); it happens on focus-in and on a
      programmatic write, so "undo" means "undo what the USER did since then". }
    { True when the field holds no date. The question a host asks before writing the
      value into an optional column, and the one this control could not answer at all
      before: an "optional deadline" had nowhere to put "none". LCL: same name,
      datetimepicker.pas:4194. }
    function DateIsNull: Boolean;
    procedure ConfirmChanges;
    { Restore the confirmed value (LCL's UndoChanges, :1985-1997). }
    procedure UndoChanges;

    property Date:        TDateTime read GetDate    write SetDate;
    property Time:        TDateTime read GetTime    write SetTime;
    { Expose for tests }
    property ActiveSeg:   Integer   read FActiveSeg;
    property Segments:    TTySegmentArray read FSegments;
    property DigitBuffer: string    read FDigitBuffer;
    { The layout the last RenderTo drew with -- see the fields for why a guard has to
      read this rather than call FieldLayout again. Empty until the first paint. }
    property PaintedRects:   TTyDateTimeRects read FPaintedRects;
    property PaintedOriginX: Integer          read FPaintedOriginX;
    property PaintedText:    string           read FPaintedText;
    property PaintedSpans:   TTySegmentArray  read FPaintedSpans;
    { Expose popup and calendar for test probes }
    property Popup:       TTyDropdownPopup read FPopup;
    property Calendar:    TTyCalendar      read FCalendar;

  published
    { Published so DateTime appears in the Object Inspector and is streamed. }
    property DateTime:    TDateTime       read FDateTime    write SetDateTime;
    property Kind:         TTyDateTimeKind read FKind        write SetKind        default dtkDate;
    property DateFormat:   string          read FDateFormat  write SetDateFormat;
    property TimeFormat:   string          read FTimeFormat  write SetTimeFormat;
    property MinDate:      TDateTime       read FMinDate     write SetMinDate;
    property MaxDate:      TDateTime       read FMaxDate     write SetMaxDate;
    property ReadOnly:     Boolean         read FReadOnly    write SetReadOnly    default False;
    property ShowCheckBox: Boolean         read FShowCheckBox write SetShowCheckBox default False;
    property Checked:      Boolean         read FChecked     write SetChecked     default True;
    property DroppedDown:  Boolean         read GetDroppedDown write SetDroppedDown;
    { Horizontal placement of the whole date/time string inside the field. A date column
      next to numeric ones is conventionally right-aligned and there was no way to say
      so; LCL has had Alignment since forever (datetimepicker.pas:455). The segment
      highlight and the click hit-test move with it -- an alignment that the mouse does
      not follow is worse than none. }
    property Alignment:    TAlignment      read FAlignment   write SetAlignment   default taLeftJustify;
    { False drops the padding zero from day, month and hour: 9/7/2026, not 09/07/2026.
      Until now the padding was structural -- the format was rewritten to force it --
      so an explicit 'd/m/yyyy' came out as 'dd/mm/yyyy' and looked ignored. }
    property LeadingZeros: Boolean         read FLeadingZeros write SetLeadingZeros default True;
    { The pivot a SHORT typed year expands against: 26 becomes 2026, 40 becomes 2040,
      and with the default 1941 anything below 41 rolls into the next century. It is
      read by the expansion in FinalizeBuffer -- it is the knob on a behaviour, not a
      value stored for its own sake. }
    property CenturyFrom:  Word            read FCenturyFrom write SetCenturyFrom default TyDefaultCenturyFrom;
    { LCL's Options set (datetimepicker.pas:456), default [] as there. The one that
      changes existing behaviour is dtpoDoChangeOnSetDateTime -- see SetDateTime. }
    property Options:      TTyDateTimePickerOptions read FOptions write FOptions default [];
    { Which right-hand affordance the field carries, and whether it reserves a column
      at all. Was hardwired to Kind, so a date field could only drop a calendar and the
      button column was spent whether or not anything used it. }
    property DateMode:     TTyDTDateMode   read FDateMode    write SetDateMode    default dmComboBox;
    { Off by default, unlike LCL's picker (datetimepicker.pas:394 publishes it True):
      turning it on for everyone would resize every field on every existing form. On,
      the control measures its own text, checkbox and button and grows to fit -- which
      is what a skin with a larger font or fatter padding needs, and what the fixed
      130px width could not do. }
    property AutoSize;
    { Whether the USER may empty the field (N or Delete). Code can always write
      DateTime := TyNullDate -- LCL draws the line in the same place
      (datetimepicker.pas:3731 checks it, SetDateTime :1202 does not), and it is the
      right place: a form that means "required" wants the keyboard route closed, not
      its own load-this-record line refused. }
    property NullInputAllowed: Boolean read FNullInputAllowed
             write SetNullInputAllowed default True;
    { What the field shows while empty. No `default` on purpose (LCL says nodefault
      for the same reason): the initial value is a non-empty string, so a form that
      legitimately wants an empty one has to be able to stream it. }
    property TextForNullDate: TCaption read FTextForNullDate
             write SetTextForNullDate;
    property OnChange:     TNotifyEvent    read FOnChange    write FOnChange;
    property OnDropDown:   TNotifyEvent    read FOnDropDown  write FOnDropDown;
    property OnCloseUp:    TNotifyEvent    read FOnCloseUp   write FOnCloseUp;
    property OnChecked:    TNotifyEvent    read FOnChecked   write FOnChecked;
    { LCL's name for the same event (datetimepicker.pas:415-416). One storage, two
      names, so a ported form's `OnCheckBoxChange = Handler` streams instead of leaving
      the handler silently orphaned. OnChecked stays the persisted one. }
    property OnCheckBoxChange: TNotifyEvent read FOnChecked  write FOnChecked stored False;
    property Align;
    property Anchors;
    property Font;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

{ Button rect for the right-side button area (dtkDate = chevron, dtkTime = up/down) }
function TyDateTimeButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
{ For dtkTime: top half of the button = up arrow }
function TyDateTimeUpButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
{ For dtkTime: bottom half = down arrow }
function TyDateTimeDownButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;

{ ── PURE, headless-tested field geometry (all in DEVICE pixels) ───────────── }

{ APaddingLogical is the resolved style's padding and AButtonWLogical the button
  column's token width, both in LOGICAL px; AButtonWLogical is 0 when the field has no
  button at all (dmNone), which is what empties the three button rects.

  ARightToLeft MIRRORS the finished tiling about ALocal's vertical centre -- one
  reflection over all five rects at the very end, not a direction branch per part.
  That is the shape TyCaptionLayoutFor and TyStatusPanelRects already use, and the
  reason to insist on it here is this control's history: five parts, each with its
  own x expression, is five chances to mirror four. Reflecting the finished record
  cannot mirror four. The button column lands at the physical LEFT (the trailing
  edge in either direction, which is also where Windows puts it under
  WS_EX_LAYOUTRTL), the text box takes what is left, and the indicator comes to rest
  at the text box's reading start -- its right edge. Up/down is untouched: the spin
  halves reflect onto themselves. }
function TyDateTimeRects(const ALocal: TRect; APPI: Integer;
  const APaddingLogical: TRect; AButtonWLogical: Integer;
  AShowCheckBox: Boolean; ARightToLeft: Boolean = False): TTyDateTimeRects;

{ What the checkbox reserves at the reading start of the text box: the indicator plus its
  gap. Scaled as TWO terms because the indicator is DRAWN MulDiv(TyCheckBoxBox) wide and
  the gap sits beside it -- scaling their sum instead lands a pixel out at any PPI that is
  not a whole multiple of 96, and that one pixel is precisely where the paint and the hit
  test used to part company. }
function TyDateTimeCheckBoxColumn(APPI: Integer): Integer;

implementation

{ ── The empty value ──────────────────────────────────────────────────────── }

function TyDateIsNull(const ADateTime: TDateTime): Boolean;
begin
  { NaN first: every comparison against a NaN is False, so the range tests below
    would let one through as a perfectly ordinary date. A database driver handing
    back a NaN for a NULL column is exactly the case this order exists for. }
  Result := IsNan(Double(ADateTime)) or IsInfinite(Double(ADateTime)) or
            (ADateTime > SysUtils.MaxDateTime) or
            (ADateTime < SysUtils.MinDateTime);
end;

function TyEqualDateTime(const A, B: TDateTime): Boolean;
begin
  if TyDateIsNull(A) then
    Result := TyDateIsNull(B)
  else
    Result := (not TyDateIsNull(B)) and (A = B);
end;

{ ── TyEffectiveFormat ────────────────────────────────────────────────────── }

function TyEffectiveFormat(const AFormat: string): string;
{ Walk the format string and double any single-letter field specifier:
    m → mm,  d → dd,  h → hh,  n → nn,  s → ss
  yyyy / yyy / yy are left as-is (year already has explicit width).
  Quoted text ('...' or "...") is copied verbatim.
  All other characters (separators, literals) are copied as-is. }
var
  Fmt: string;
  i, N: Integer;
  Ch: Char;
  RunStart, RunLen: Integer;
  RunCh: Char;
begin
  Fmt := LowerCase(AFormat);
  N   := Length(Fmt);
  Result := '';
  i := 1;
  while i <= N do
  begin
    Ch := Fmt[i];

    { Quoted literal — copy verbatim until the matching quote }
    if Ch in ['''', '"'] then
    begin
      Result := Result + AFormat[i];
      Inc(i);
      while (i <= N) and (Fmt[i] <> Ch) do
      begin
        Result := Result + AFormat[i];
        Inc(i);
      end;
      if i <= N then
      begin
        Result := Result + AFormat[i];  // closing quote
        Inc(i);
      end;
      Continue;
    end;

    { Year runs: copy as-is regardless of length }
    if Ch = 'y' then
    begin
      RunStart := i;
      RunLen   := 0;
      while (i <= N) and (Fmt[i] = 'y') do begin Inc(RunLen); Inc(i); end;
      Result := Result + Copy(AFormat, RunStart, RunLen);
      Continue;
    end;

    { Single-letter field specifiers that must be doubled }
    if Ch in ['m', 'd', 'h', 'n', 's'] then
    begin
      RunStart := i;
      RunCh    := Ch;
      RunLen   := 0;
      while (i <= N) and (Fmt[i] = RunCh) do begin Inc(RunLen); Inc(i); end;
      if RunLen = 1 then
        { Single → double for fixed-width rendering }
        Result := Result + Ch + Ch
      else
        Result := Result + Copy(AFormat, RunStart, RunLen);
      Continue;
    end;

    { am/pm and a/p tokens — copy verbatim (already fixed-width) }
    if Ch = 'a' then
    begin
      if (i + 4 <= N) and (LowerCase(Copy(AFormat, i, 5)) = 'am/pm') then
      begin
        Result := Result + Copy(AFormat, i, 5);
        Inc(i, 5);
      end
      else if (i + 2 <= N) and (LowerCase(Copy(AFormat, i, 3)) = 'a/p') then
      begin
        Result := Result + Copy(AFormat, i, 3);
        Inc(i, 3);
      end
      else
      begin
        Result := Result + AFormat[i];
        Inc(i);
      end;
      Continue;
    end;

    { Everything else: separator / literal — copy as-is }
    Result := Result + AFormat[i];
    Inc(i);
  end;
end;

{ ── TyFormatDateTime ─────────────────────────────────────────────────────── }

function TyFormatDateTime(AValue: TDateTime; const AFormat: string;
  const AFmt: TFormatSettings): string;
begin
  Result := FormatDateTime(AFormat, AValue, AFmt);
end;

{ ── TyDateTimeSegments ───────────────────────────────────────────────────── }

function TyDateTimeSegments(const AFormat: string): TTySegmentArray;
{ Scan the format string left-to-right.  A "run" is a maximal sequence of
  the same recognisable letter.  We also detect the special two-letter
  tokens 'am/pm' and 'a/p'.

  State: LastFieldKind tracks the last *field* kind we emitted so the
  m-after-h rule can be applied.  Separator characters reset nothing — only
  actual field tokens matter for the m-after-h rule. }
var
  Fmt:          string;
  i, N:         Integer;
  Ch:           Char;
  RunStart:     Integer;
  RunCh:        Char;
  RunLen:       Integer;
  Kind:         TTySegKind;
  LastFieldKind: TTySegKind;  // last emitted segment's kind (skNone = none yet)
  Seg:          TTySegment;
begin
  Result := nil;
  Fmt := LowerCase(AFormat);    // normalise once; all comparisons are lowercase
  N := Length(Fmt);
  i := 1;                       // 1-based (Pascal strings)
  LastFieldKind := skNone;

  while i <= N do
  begin
    Ch := Fmt[i];

    { ── am/pm and a/p — must check before single 'a' ── }
    if (Ch = 'a') then
    begin
      if (i + 3 <= N) and (Copy(Fmt, i, 4) = 'am/p') and
         (i + 4 <= N) and (Fmt[i + 4] = 'm') then
      begin
        { "am/pm" — 5 chars }
        Seg.Kind    := skAMPM;
        Seg.StartCh := i - 1;   // 0-based
        Seg.LenCh   := 5;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Seg;
        LastFieldKind := skAMPM;
        Inc(i, 5);
        Continue;
      end
      else if (i + 2 <= N) and (Copy(Fmt, i, 3) = 'a/p') then
      begin
        { "a/p" — 3 chars }
        Seg.Kind    := skAMPM;
        Seg.StartCh := i - 1;
        Seg.LenCh   := 3;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Seg;
        LastFieldKind := skAMPM;
        Inc(i, 3);
        Continue;
      end
      else
      begin
        { Lone 'a' — not a recognised token, treat as separator }
        Inc(i);
        Continue;
      end;
    end;

    { ── recognised single-letter field tokens ── }
    if Ch in ['y', 'm', 'd', 'h', 'n', 's', 'z'] then
    begin
      { Consume the run }
      RunStart := i;
      RunCh    := Ch;
      RunLen   := 0;
      while (i <= N) and (Fmt[i] = RunCh) do
      begin
        Inc(RunLen);
        Inc(i);
      end;

      { Determine kind }
      case RunCh of
        'y': Kind := skYear;
        'd': Kind := skDay;
        'h': Kind := skHour;
        'n': Kind := skMinute;
        's': Kind := skSecond;
        'z': Kind := skMilliSec;
        'm':
          begin
            { m-after-h rule: if the most-recently-emitted field was skHour,
              this "m"-run means minutes regardless of separator chars between. }
            if LastFieldKind = skHour then
              Kind := skMinute
            else
              Kind := skMonth;
          end;
      else
        Kind := skNone;   // unreachable, but keeps the compiler happy
      end;

      if Kind <> skNone then
      begin
        Seg.Kind    := Kind;
        Seg.StartCh := RunStart - 1;   // 0-based
        Seg.LenCh   := RunLen;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Seg;
        LastFieldKind := Kind;
      end;
      Continue;
    end;

    { ── everything else is a separator / literal — skip one char ── }
    Inc(i);
  end;
end;

{ ── TySegmentRange ───────────────────────────────────────────────────────── }

function TySegmentRange(const ASeg: TTySegment;
  out AMin, AMax: Integer): Boolean;
begin
  AMin := 0;
  AMax := 0;
  case ASeg.Kind of
    skDay:    begin AMin := 1;  AMax := 31;   Result := True; end;
    skMonth:  begin AMin := 1;  AMax := 12;   Result := True; end;
    skYear:   begin AMin := 1;  AMax := 9999; Result := True; end;
    skHour:   begin AMin := 0;  AMax := 23;   Result := True; end;
    skMinute: begin AMin := 0;  AMax := 59;   Result := True; end;
    skSecond: begin AMin := 0;  AMax := 59;   Result := True; end;
    skMilliSec: begin AMin := 0; AMax := 999; Result := True; end;
    skAMPM:   begin AMin := 0;  AMax := 1;    Result := True; end;
  else
    Result := False;
  end;
end;

{ ── TySegmentStep ────────────────────────────────────────────────────────── }

function TySegmentStep(AValue: TDateTime; const ASeg: TTySegment;
  ADelta: Integer): TDateTime;
{ Decode AValue → Y/M/D/H/Min/S/MS, adjust the segment's field using
  roll-within-field (wrap without carry), re-encode.

  Day clamping rule: after rolling the day, if the result exceeds the number
  of days in the *current* month (M unchanged), clamp it to DaysInAMonth(Y,M).
  This ensures 'day 31 in a 30-day month + 0' is also corrected, but the
  primary case is after a month-roll when the old day no longer fits. }
var
  Y, M, D, H, Min, S, MS: Word;
  RangeMin, RangeMax: Integer;
  Field: Integer;
  Span: Integer;
begin
  DecodeDateTime(AValue, Y, M, D, H, Min, S, MS);

  { Fetch the field value and its range }
  case ASeg.Kind of
    skYear:   Field := Y;
    skMonth:  Field := M;
    skDay:    Field := D;
    skHour:   Field := H;
    skMinute: Field := Min;
    skSecond: Field := S;
    skMilliSec: Field := MS;
    skAMPM:   Field := H div 12;   // 0 = AM, 1 = PM
  else
    begin
      Result := AValue;
      Exit;
    end;
  end;

  if not TySegmentRange(ASeg, RangeMin, RangeMax) then
  begin
    Result := AValue;
    Exit;
  end;

  { Roll-within-field: shift + wrap, no carry }
  Span  := RangeMax - RangeMin + 1;
  Field := ((Field - RangeMin + ADelta) mod Span + Span) mod Span + RangeMin;

  { Write back }
  case ASeg.Kind of
    skYear:
      begin
        Y := Word(Field);
        { After year roll, clamp day to the month's length }
        if D > DaysInAMonth(Y, M) then
          D := DaysInAMonth(Y, M);
      end;
    skMonth:
      begin
        M := Word(Field);
        { After month roll, clamp day to the new month's length.
          The year is intentionally NOT changed (no-carry rule). }
        if D > DaysInAMonth(Y, M) then
          D := DaysInAMonth(Y, M);
      end;
    skDay:   D   := Word(Field);
    skHour:  H   := Word(Field);
    skMinute: Min := Word(Field);
    skSecond: S   := Word(Field);
    skMilliSec: MS := Word(Field);
    skAMPM:
      begin
        { Toggle AM/PM by adding or subtracting 12 hours; keep within 0..23 }
        if Field = 0 then
          H := H mod 12           // → AM: 0..11
        else
          H := H mod 12 + 12;     // → PM: 12..23
      end;
  end;

  Result := EncodeDateTime(Y, M, D, H, Min, S, MS);
end;

{ ── TyDateTimeActiveSegAt ─────────────────────────────────────────────────── }

function TyDateTimeActiveSegAt(const ASegs: TTySegmentArray;
  ACharIndex: Integer): Integer;
{ Return the index of the segment that contains ACharIndex (0-based char
  position in the format string). Returns -1 when no segment covers it. }
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(ASegs) do
    if (ACharIndex >= ASegs[i].StartCh) and
       (ACharIndex < ASegs[i].StartCh + ASegs[i].LenCh) then
    begin
      Result := i;
      Exit;
    end;
end;

{ ── TyDateTimeNextCharOffset ─────────────────────────────────────────────── }

function TyDateTimeNextCharOffset(const AText: string; AOffset: Integer): Integer;
{ AOffset is 0-based and assumed to sit on a character boundary (the walk starts at 0 and
  only ever advances by this function, so it stays on one). A malformed byte advances by
  one so a broken string can never spin the caller's loop forever. }
var
  n: Integer;
begin
  if AOffset < 0 then Exit(0);
  if AOffset >= Length(AText) then Exit(Length(AText));
  n := UTF8CodepointSize(@AText[AOffset + 1]);
  if n < 1 then n := 1;
  Result := AOffset + n;
  if Result > Length(AText) then Result := Length(AText);
end;

{ ── TyRenderDateTime ─────────────────────────────────────────────────────── }

{ Zero-pads S on the left to AWidth. }
function TyPadLeft(const S: string; AWidth: Integer): string;
begin
  Result := S;
  while Length(Result) < AWidth do Result := '0' + Result;
end;

{ The rendered text of ONE field. ARawToken is the field's own slice of the format
  string -- needed for the meridiem, whose CASE follows the way the author wrote it
  ('AM/PM' vs 'am/pm'), exactly as FormatDateTime does it. }
function TySegmentDisplay(const ASeg: TTySegment; const ARawToken: string;
  Y, M, D, H, Mi, S, MS: Word; const AFmt: TFormatSettings;
  ALeadingZeros, ATwelveHour: Boolean): string;
var
  hh, dow: Integer;
begin
  case ASeg.Kind of
    skYear:
      case ASeg.LenCh of
        1, 2: Result := TyPadLeft(IntToStr(Y mod 100), 2);
        3:    Result := TyPadLeft(IntToStr(Y), 3);
      else
        Result := TyPadLeft(IntToStr(Y), 4);
      end;
    skMonth:
      if ASeg.LenCh >= 4 then
        Result := AFmt.LongMonthNames[M]
      else if ASeg.LenCh = 3 then
        Result := AFmt.ShortMonthNames[M]
      else if ALeadingZeros then
        Result := TyPadLeft(IntToStr(M), 2)
      else
        Result := IntToStr(M);
    skDay:
      if ASeg.LenCh >= 3 then
      begin
        { 'ddd'/'dddd' are weekday NAMES in FormatDateTime, not the day number. }
        dow := DayOfWeek(EncodeDate(Y, M, D));
        if ASeg.LenCh >= 4 then
          Result := AFmt.LongDayNames[dow]
        else
          Result := AFmt.ShortDayNames[dow];
      end
      else if ALeadingZeros then
        Result := TyPadLeft(IntToStr(D), 2)
      else
        Result := IntToStr(D);
    skHour:
      begin
        hh := H;
        if ATwelveHour then
        begin
          hh := H mod 12;
          if hh = 0 then hh := 12;
        end;
        if ALeadingZeros then
          Result := TyPadLeft(IntToStr(hh), 2)
        else
          Result := IntToStr(hh);
      end;
    skMinute:   Result := TyPadLeft(IntToStr(Mi), 2);
    skSecond:   Result := TyPadLeft(IntToStr(S),  2);
    skMilliSec: Result := TyPadLeft(IntToStr(MS), 3);
    skAMPM:
      begin
        if ASeg.LenCh = 3 then          { 'a/p' }
          if H < 12 then Result := 'A' else Result := 'P'
        else                            { 'am/pm' }
          if H < 12 then Result := 'AM' else Result := 'PM';
        if ARawToken = LowerCase(ARawToken) then
          Result := LowerCase(Result);
      end;
  else
    Result := '';
  end;
end;

function TyRenderDateTime(AValue: TDateTime; const AFormat: string;
  const AFmt: TFormatSettings; ALeadingZeros: Boolean;
  out ASpans: TTySegmentArray): string;
var
  Segs: TTySegmentArray;
  i, si, N: Integer;
  Y, M, D, H, Mi, S, MS: Word;
  Twelve: Boolean;
  Ch: Char;
  T: string;
begin
  { Reuse the scanner rather than re-deriving the field list: it already carries the
    m-after-h rule, and two independent readings of the same format is how the format
    offsets and the rendered offsets drifted apart in the first place. }
  Segs := TyDateTimeSegments(AFormat);
  SetLength(ASpans, Length(Segs));
  DecodeDateTime(AValue, Y, M, D, H, Mi, S, MS);
  Twelve := False;
  for i := 0 to High(Segs) do
    if Segs[i].Kind = skAMPM then Twelve := True;

  Result := '';
  N := Length(AFormat);
  i  := 1;      // 1-based into AFormat
  si := 0;      // next segment to emit
  while i <= N do
  begin
    if (si <= High(Segs)) and (Segs[si].StartCh = i - 1) then
    begin
      T := TySegmentDisplay(Segs[si], Copy(AFormat, i, Segs[si].LenCh),
             Y, M, D, H, Mi, S, MS, AFmt, ALeadingZeros, Twelve);
      ASpans[si].Kind    := Segs[si].Kind;
      ASpans[si].StartCh := Length(Result);
      ASpans[si].LenCh   := Length(T);
      Result := Result + T;
      Inc(i, Segs[si].LenCh);
      Inc(si);
      Continue;
    end;

    Ch := AFormat[i];
    { Quoted literal: FormatDateTime emits the contents without the quotes. }
    if (Ch = '''') or (Ch = '"') then
    begin
      Inc(i);
      while (i <= N) and (AFormat[i] <> Ch) do
      begin
        Result := Result + AFormat[i];
        Inc(i);
      end;
      if i <= N then Inc(i);
      Continue;
    end;
    { '/' and ':' are placeholders for the locale's separators in FormatDateTime, not
      literals; a German build must still get 30.07.2026 out of 'dd/mm/yyyy'. }
    if Ch = '/' then
      Result := Result + AFmt.DateSeparator
    else if Ch = ':' then
      Result := Result + AFmt.TimeSeparator
    else
      Result := Result + Ch;
    Inc(i);
  end;
end;

{ ── TyExpandShortYear ────────────────────────────────────────────────────── }

function TyExpandShortYear(ATyped: Integer; ADigits: Integer;
  ACenturyFrom: Word): Integer;
begin
  Result := ATyped;
  if ADigits > 2 then Exit;        // three or four digits is already an explicit year
  if ATyped < 0 then Exit;
  if ATyped >= (ACenturyFrom mod 100) then
    Result := ATyped + 100 * (ACenturyFrom div 100)
  else
    Result := ATyped + 100 * (ACenturyFrom div 100 + 1);
end;

{ ── Button geometry helpers ──────────────────────────────────────────────── }

function TyDateTimeButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
var BtnW, X0: Integer;
begin
  if ABtnWDev > 0 then BtnW := ABtnWDev else BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  Result := Rect(X0, ALocal.Top, ALocal.Right, ALocal.Bottom);
end;

function TyDateTimeUpButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
var BtnW, X0, HalfY: Integer;
begin
  if ABtnWDev > 0 then BtnW := ABtnWDev else BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0    := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, ALocal.Top, ALocal.Right, HalfY);
end;

function TyDateTimeDownButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
var BtnW, X0, HalfY: Integer;
begin
  if ABtnWDev > 0 then BtnW := ABtnWDev else BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0    := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, HalfY, ALocal.Right, ALocal.Bottom);
end;

{ ── TyDateTimeCheckBoxColumn / TyDateTimeRects — the one source ──────────── }

function TyDateTimeCheckBoxColumn(APPI: Integer): Integer;
begin
  Result := MulDiv(TyCheckBoxBox, APPI, 96) + MulDiv(TyCheckBoxGap, APPI, 96);
end;

function TyDateTimeRects(const ALocal: TRect; APPI: Integer;
  const APaddingLogical: TRect; AButtonWLogical: Integer;
  AShowCheckBox: Boolean; ARightToLeft: Boolean): TTyDateTimeRects;
var
  BtnW, BoxSize, MidY: Integer;
begin
  Result := Default(TTyDateTimeRects);
  if AButtonWLogical > 0 then
    BtnW := MulDiv(AButtonWLogical, APPI, 96)
  else
    BtnW := 0;

  { The text box is the client less the padding and less the button column. Padding.Right
    is deliberately NOT subtracted: the button column already holds that edge, and when
    there is no button the field has always run its text to the frame. }
  Result.Text := Rect(
    ALocal.Left   + MulDiv(APaddingLogical.Left,   APPI, 96),
    ALocal.Top    + MulDiv(APaddingLogical.Top,    APPI, 96),
    ALocal.Right  - BtnW,
    ALocal.Bottom - MulDiv(APaddingLogical.Bottom, APPI, 96));

  { The indicator is centred in the text box's height and sits at its reading start; the
    string then begins past the indicator AND its gap. }
  if AShowCheckBox then
  begin
    BoxSize := MulDiv(TyCheckBoxBox, APPI, 96);
    MidY    := Result.Text.Top +
               (Result.Text.Bottom - Result.Text.Top - BoxSize) div 2;
    Result.CheckBox  := Rect(Result.Text.Left, MidY,
                             Result.Text.Left + BoxSize, MidY + BoxSize);
    Result.Text.Left := Result.Text.Left + TyDateTimeCheckBoxColumn(APPI);
  end;

  { A column too narrow to scale to a single pixel is no column: leaving the rects empty
    is what keeps a click off a button the paint never drew. }
  if BtnW > 0 then
  begin
    Result.Button     := TyDateTimeButtonRect(ALocal, APPI, BtnW);
    Result.ButtonUp   := TyDateTimeUpButtonRect(ALocal, APPI, BtnW);
    Result.ButtonDown := TyDateTimeDownButtonRect(ALocal, APPI, BtnW);
  end;

  { MIRROR once, at the very end, over the FINISHED record. Every part above was tiled
    left-to-right and none of them knows about direction; reflecting them together is
    what makes "the paint mirrored but the hit test did not" unrepresentable rather than
    merely untested -- both sides read this record. LCL's BidiFlipRect (controls.pp:2966)
    does the arithmetic, the same lever TyCaptionLayoutFor and TyStatusPanelRects pull.

    An EMPTY part is left exactly as it is. Reflecting Rect(0,0,0,0) about the client
    would hand back Rect(W,0,W,0) -- still empty by IsRectEmpty, but a rect sitting on a
    real edge, one arithmetic slip away from becoming a button a click could find where
    the paint drew nothing. }
  if ARightToLeft then
  begin
    Result.Text := BidiFlipRect(Result.Text, ALocal, True);
    if not IsRectEmpty(Result.CheckBox) then
      Result.CheckBox := BidiFlipRect(Result.CheckBox, ALocal, True);
    if not IsRectEmpty(Result.Button) then
    begin
      Result.Button     := BidiFlipRect(Result.Button,     ALocal, True);
      Result.ButtonUp   := BidiFlipRect(Result.ButtonUp,   ALocal, True);
      Result.ButtonDown := BidiFlipRect(Result.ButtonDown, ALocal, True);
    end;
  end;
end;

{ ── TTyDateTimePicker ────────────────────────────────────────────────────── }

constructor TTyDateTimePicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop        := True;
  Cursor         := crArrow;
  FKind          := dtkDate;
  FDateTime      := Now;
  FMinDate       := 0;
  FMaxDate       := 0;
  FDateFormat    := '';
  FTimeFormat    := '';
  FReadOnly      := False;
  FShowCheckBox  := False;
  FChecked       := True;
  FAlignment     := taLeftJustify;
  FLeadingZeros  := True;
  FCenturyFrom   := TyDefaultCenturyFrom;
  FOptions       := [];
  FDateMode      := dmComboBox;
  FNullInputAllowed := True;
  FTextForNullDate  := TyDefaultTextForNullDate;
  FConfirmedDateTime := FDateTime;
  FActiveSeg     := 0;
  FDigitBuffer   := '';
  FPopup         := nil;
  FCalendar      := nil;
  FCloseUpTick   := 0;
  Width  := 130;
  Height := TyDensityHeight(ActiveController, 24);
  RebuildSegments;
end;

destructor TTyDateTimePicker.Destroy;
begin
  { Free the popup helper first: it hides the form and fires OnClose
    (PopupClosed), which accesses FPopup.CloseUpTick.  Detach the handler
    before freeing so we don't re-enter during destruction. }
  if FPopup <> nil then
    FPopup.OnClose := nil;
  FreeAndNil(FPopup);
  { FCalendar is owned by Self (not by the popup form), so free it after the
    popup to avoid any use-after-free if the popup form tried to access it. }
  FreeAndNil(FCalendar);
  inherited Destroy;
end;

function TTyDateTimePicker.GetStyleTypeKey: string;
begin
  Result := 'TyDateTimePicker';
end;

{ ── Active format resolution ─────────────────────────────────────────────── }

function TTyDateTimePicker.ActiveFormat: string;
begin
  { The fallback PATTERNS deliberately stay DefaultFormatSettings even when a
    translation is loaded: field order (2026/8/7 vs 8/7/2026) and separators are
    locale conventions, not language, and an English-speaking user on a Chinese
    machine still reads that machine's date order. Only NAMES the pattern asks
    for ('mmmm', 'ddd') follow the app's language -- BuildDisplay resolves those
    through TyDateTimeNames. }
  if FKind = dtkDate then
  begin
    if FDateFormat <> '' then
      Result := FDateFormat
    else
      Result := DefaultFormatSettings.ShortDateFormat;
  end
  else
  begin
    if FTimeFormat <> '' then
      Result := FTimeFormat
    else
      Result := DefaultFormatSettings.ShortTimeFormat;
  end;
end;

function TTyDateTimePicker.EffectiveFormat: string;
{ Returns a normalized version of ActiveFormat where every single-letter
  field specifier is doubled (m→mm, d→dd, etc.) to guarantee fixed-width
  rendering so that format positions == rendered text positions. }
begin
  Result := TyEffectiveFormat(ActiveFormat);
end;

procedure TTyDateTimePicker.RebuildSegments;
begin
  { Scan the AUTHOR'S format, not the doubled one. The doubling existed only to make
    format offsets equal rendered offsets; BuildDisplay now reports the rendered
    offsets directly, so the format can stay exactly as it was written -- which is what
    lets LeadingZeros=False and month names work at all. }
  FSegments := TyDateTimeSegments(ActiveFormat);
  if FActiveSeg > High(FSegments) then
    FActiveSeg := 0;
  if Length(FSegments) = 0 then
    FActiveSeg := -1;
  FDigitBuffer := '';
end;

function TTyDateTimePicker.FormattedText: string;
var
  Spans: TTySegmentArray;
begin
  BuildDisplay(Result, Spans);
end;

function TTyDateTimePicker.SegmentDigitWidth(const ASeg: TTySegment): Integer;
begin
  case ASeg.Kind of
    skYear:     if ASeg.LenCh >= 3 then Result := 4 else Result := 2;
    skMilliSec: Result := 3;
  else
    Result := 2;
  end;
end;

procedure TTyDateTimePicker.BuildDisplay(out AText: string;
  out ASpans: TTySegmentArray);
var
  BufText: string;
  i, Delta: Integer;
  Base: TDateTime;
begin
  { An EMPTY field has no date to format, and TyRenderDateTime on the sentinel would
    decode an out-of-range value. Two cases, and the second is the one that is easy to
    miss:

    * nothing typed yet -> show TextForNullDate and report NO spans. Zero spans is what
      suppresses the highlight and what makes a click resolve to no field: the string on
      screen is 'NULL', which has no year in it, and a span measured against the date's
      offsets would put a highlight over characters that are not there.

    * digits being typed -> the value is STILL empty (the buffer does not commit until
      the field fills), so a naive null branch here would keep saying 'NULL' while the
      user typed into it and the keystrokes would vanish into a field that never
      acknowledged them. Render the SEED instead, and splice the buffer into it as
      usual, so what is on screen is the date being built. }
  if TyDateIsNull(FDateTime) then
  begin
    if (FDigitBuffer = '') or (FActiveSeg < 0) then
    begin
      AText  := FTextForNullDate;
      ASpans := nil;
      Exit;
    end;
    Base := NullSeedDate;
  end
  else
    Base := FDateTime;

  { TyDateTimeNames, not raw DefaultFormatSettings: 'mmmm'/'ddd' names follow the
    app's language (tier order in tyControls.Calendar), separators and field
    order stay the locale's. Resolved here on every rebuild, so a language
    switched at run time is honoured by the next repaint. }
  AText := TyRenderDateTime(Base, ActiveFormat, TyDateTimeNames,
             FLeadingZeros, ASpans);
  if (FDigitBuffer = '') or (FActiveSeg < 0) or (FActiveSeg > High(ASpans)) then Exit;

  { Show exactly what was typed, so there is no premature-clamp flicker; pad it to the
    field's digit width only when the field is padded anyway, otherwise a '1' typed
    into a LeadingZeros=False day would jump to '01' and back. }
  BufText := FDigitBuffer;
  if FLeadingZeros then
    BufText := TyPadLeft(BufText, SegmentDigitWidth(FSegments[FActiveSeg]));

  Delta := Length(BufText) - ASpans[FActiveSeg].LenCh;
  AText := Copy(AText, 1, ASpans[FActiveSeg].StartCh) + BufText +
           Copy(AText, ASpans[FActiveSeg].StartCh + ASpans[FActiveSeg].LenCh + 1, MaxInt);
  ASpans[FActiveSeg].LenCh := Length(BufText);
  { Everything after the spliced field moved; leaving the spans stale is how the
    highlight and the mouse would disagree with the text mid-typing. }
  for i := FActiveSeg + 1 to High(ASpans) do
    Inc(ASpans[i].StartCh, Delta);
end;

{ ── Pixel measurement helper ─────────────────────────────────────────────── }

function TTyDateTimePicker.TextOriginX(const ATextR: TRect;
  const AText, AFontName: string;
  AFontSizePx, AFontWeight, APPI: Integer): Integer;
var
  Bmp: TBGRABitmap;
  TextW: Integer;
  Rtl: Boolean;
  Eff: TAlignment;
begin
  Rtl := IsRightToLeft;
  { Alignment is a READING-order value here, resolved to a physical one exactly as
    TTyPainter.DrawText will resolve the same property a few lines later -- one lookup,
    two callers, so the origin the highlight and the hit test measure from cannot end up
    on the other side of the box from the glyphs. It OVERRIDES rather than defaults: a
    caption the author pinned to taLeftJustify sits on the right in a mirrored field,
    because TAlignment has no "unset" member to distinguish the two (docs/rtl.md, and
    LCL does the same at grids.pas:4006). The stored property is never rewritten. }
  Eff    := BidiFlipAlignment(FAlignment, Rtl);
  Result := ATextR.Left;
  { The unmirrored fast path, byte for byte as it was: a left-justified string starts at
    the box's left edge and no measurement is needed. Mirrored, the clamp below can bite
    even here, so the measurement has to happen. }
  if (Eff = taLeftJustify) and not Rtl then Exit;
  if AText = '' then Exit;
  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, AFontName, AFontSizePx, AFontWeight, APPI);
    TextW := Bmp.TextSize(AText).cx;
  finally
    Bmp.Free;
  end;
  if Eff = taRightJustify then
    Result := ATextR.Right - TextW
  else if Eff = taCenter then
    Result := ATextR.Left + (ATextR.Right - ATextR.Left - TextW) div 2;
  { A string wider than its box has to spill off ONE end, and it must be the end the
    reader finishes at -- a field whose first character is off the edge has nothing
    legible in it. So the clamp pins the READING START inside: the left edge normally,
    the right edge when the field is mirrored. }
  if Rtl then
  begin
    if Result + TextW > ATextR.Right then Result := ATextR.Right - TextW;
  end
  else
    if Result < ATextR.Left then Result := ATextR.Left;
end;

function TTyDateTimePicker.MeasureCharX(const AText, AFontName: string;
  ACharIdx, AFontSizePx, AFontWeight, APPI: Integer): Integer;
var
  Bmp: TBGRABitmap;
  Sub: string;
begin
  if (ACharIdx <= 0) or (AText = '') then
  begin
    Result := 0;
    Exit;
  end;
  if ACharIdx > Length(AText) then ACharIdx := Length(AText);
  Sub := Copy(AText, 1, ACharIdx);
  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, AFontName, AFontSizePx, AFontWeight, APPI);
    Result := Bmp.TextSize(Sub).cx;
  finally
    Bmp.Free;
  end;
end;

{ ── Digit buffer accumulation ────────────────────────────────────────────── }

function TTyDateTimePicker.AccumulateDigit(ADigit: Char): Boolean;
{ Append ADigit to FDigitBuffer without writing FDateTime.
  Returns True when the segment is "full" (auto-advance condition):
    - MaxDigits reached, OR
    - for non-year: NewVal * 10 > RMax (can't add another digit and stay valid). }
var
  Seg:       TTySegment;
  RMin, RMax: Integer;
  NewBuf:    string;
  NewVal:    Integer;
  MaxDigits: Integer;
begin
  Result := False;
  if FActiveSeg < 0 then Exit;
  if FActiveSeg > High(FSegments) then Exit;
  Seg := FSegments[FActiveSeg];
  if not TySegmentRange(Seg, RMin, RMax) then Exit;

  NewBuf := FDigitBuffer + ADigit;
  NewVal := StrToIntDef(NewBuf, -1);
  if NewVal < 0 then Exit;  // non-digit sneaked in

  MaxDigits := SegmentDigitWidth(Seg);

  FDigitBuffer := NewBuf;  // store buffer (no FDateTime write yet)

  if Length(NewBuf) >= MaxDigits then
    Result := True
  else if (Seg.Kind <> skYear) and (NewVal * 10 > RMax) then
    Result := True;
  { Result = True → caller should call FinalizeBuffer(OldVal, True) }
end;

{ ── Buffer finalization ──────────────────────────────────────────────────── }

procedure TTyDateTimePicker.FinalizeBuffer(AOldVal: TDateTime; AAdvance: Boolean);
{ Parse FDigitBuffer, clamp to segment range, write FDateTime, commit.
  AAdvance = True means also increment FActiveSeg (auto-advance path). }
var
  Seg:       TTySegment;
  RMin, RMax: Integer;
  NewVal:    Integer;
  Y, M, D, H, Mi, S, MS: Word;
  NewDT:     TDateTime;
begin
  if (FDigitBuffer = '') or (FActiveSeg < 0) or (FActiveSeg > High(FSegments)) then
  begin
    FDigitBuffer := '';
    Exit;
  end;
  Seg := FSegments[FActiveSeg];
  if not TySegmentRange(Seg, RMin, RMax) then
  begin
    FDigitBuffer := '';
    Exit;
  end;

  NewVal := StrToIntDef(FDigitBuffer, RMin);
  { A year typed with one or two digits is shorthand, not the year AD 26. Without this
    the digits went in verbatim and DoExit committed them, so typing 26 and tabbing away
    silently stored 0026 -- wrong DATA, with nothing on screen saying so. }
  if Seg.Kind = skYear then
    NewVal := TyExpandShortYear(NewVal, Length(FDigitBuffer), FCenturyFrom);
  if NewVal < RMin then NewVal := RMin;
  if NewVal > RMax then NewVal := RMax;

  { The fields this keystroke is NOT changing come from the standing value, and an EMPTY
    field has none to decode -- DecodeDateTime on the sentinel would raise. Start from
    the seed instead, which is the same date BuildDisplay has been showing the user
    while they typed, so the month and day that end up stored are the ones that were on
    screen. Note FDateTime itself is still empty at this point: the materialisation
    happens below, in one place, when the new value is written. }
  if TyDateIsNull(FDateTime) then
    DecodeDateTime(NullSeedDate, Y, M, D, H, Mi, S, MS)
  else
    DecodeDateTime(FDateTime, Y, M, D, H, Mi, S, MS);
  case Seg.Kind of
    skYear:   Y  := Word(NewVal);
    skMonth:  M  := Word(NewVal);
    skDay:    D  := Word(NewVal);
    skHour:
      { In a 12-hour format the field SHOWS 1..12, so the digits the user typed are a
        12-hour reading and must be put back through the meridiem they are looking at.
        Storing them raw meant typing 3 at 15:00 silently produced 03:00 -- the display
        still read "03 PM" until the next repaint, and the value was twelve hours out.
        LCL maps it the same way (datetimepicker.pas:1708-1724). }
      if TwelveHourFormat then
      begin
        if H < 12 then
        begin
          if NewVal = 12 then H := 0 else H := Word(NewVal);
        end
        else
        begin
          if NewVal = 12 then H := 12 else H := Word(NewVal + 12);
        end;
        if H > 23 then H := 23;
      end
      else
        H := Word(NewVal);
    skMinute: Mi := Word(NewVal);
    skSecond: S  := Word(NewVal);
    skMilliSec: MS := Word(NewVal);
  else
    FDigitBuffer := '';
    Exit;
  end;
  if D > DaysInAMonth(Y, M) then D := DaysInAMonth(Y, M);
  try
    NewDT := EncodeDateTime(Y, M, D, H, Mi, S, MS);
  except
    FDigitBuffer := '';
    Exit;
  end;
  FDateTime := NewDT;
  FDigitBuffer := '';

  if AAdvance and (FActiveSeg < High(FSegments)) then
    Inc(FActiveSeg);

  CommitAndFire(AOldVal);
end;

{ ── Commit / step ────────────────────────────────────────────────────────── }

procedure TTyDateTimePicker.CommitAndFire(AOldVal: TDateTime);
{ Clamp FDateTime to [MinDate,MaxDate] and fire OnChange if the value
  actually changed relative to AOldVal. }
var
  Clamped: TDateTime;
begin
  { An EMPTY value is outside every bound BY CONSTRUCTION, so the clamps below would read
    it as a date that overshot and "correct" it to 31 Dec 9999. That is the single
    failure that would make this feature worse than not having it: the field the user
    just cleared reads back as a real date, and nothing tells the caller which happened.
    So an empty value skips the clamping entirely and only the notification runs. }
  if TyDateIsNull(FDateTime) then
  begin
    FDateTime := TyNullDate;   { normalise, so later plain comparisons stay honest }
    if not TyEqualDateTime(FDateTime, AOldVal) then
    begin
      { dtpoAutoCheck deliberately does NOT fire here. It exists so that editing a value
        implies the value is wanted; clearing it means the opposite, and ticking the
        "I have a date" box at the moment the date goes away is the wrong way round. }
      if Assigned(FOnChange) then FOnChange(Self);
    end;
    Invalidate;
    Exit;
  end;
  Clamped := FDateTime;
  if (FMinDate <> 0) and (Clamped < FMinDate) then Clamped := FMinDate;
  if (FMaxDate <> 0) and (Clamped > FMaxDate) then Clamped := FMaxDate;
  { A 4-digit year field let a user type 0001 or 9999 into an UNBOUNDED picker, and
    dates before Oct 1752 are what LCL refuses outright because widgetset calendars
    misdraw them -- a value entered here can be handed to one of those. So the absolute
    limits apply whether or not MinDate/MaxDate were set. }
  if Clamped < TyTheSmallestDate then Clamped := TyTheSmallestDate;
  if Clamped > TyTheBiggestDate  then Clamped := TyTheBiggestDate;
  FDateTime := Clamped;
  if FDateTime <> AOldVal then
  begin
    { dtpoAutoCheck: an edit implies the value is wanted, so the box follows it
      (LCL datetimepicker.pas:4007). }
    if (dtpoAutoCheck in FOptions) and FShowCheckBox and not FChecked then
      Checked := True;
    if Assigned(FOnChange) then FOnChange(Self);
  end;
  Invalidate;
end;

procedure TTyDateTimePicker.StepActiveSeg(ADelta: Integer);
var
  OldVal: TDateTime;
begin
  if FReadOnly then Exit;
  if FActiveSeg < 0 then Exit;
  if FActiveSeg > High(FSegments) then Exit;
  OldVal := FDateTime;
  { Commit any pending digit buffer before stepping }
  if FDigitBuffer <> '' then
    FinalizeBuffer(OldVal, False);
  OldVal    := FDateTime;
  { Same reason as FinalizeBuffer: TySegmentStep decodes the value it is stepping, and
    an empty field has none. An arrow on an empty field therefore fills it -- from the
    seed, stepped once -- which is the behaviour that makes an emptied field reachable
    again without the mouse. }
  if TyDateIsNull(FDateTime) then
    FDateTime := TySegmentStep(NullSeedDate, FSegments[FActiveSeg], ADelta)
  else
    FDateTime := TySegmentStep(FDateTime, FSegments[FActiveSeg], ADelta);
  CommitAndFire(OldVal);
end;

{ ── IsInert / CheckBoxRect ───────────────────────────────────────────────── }

{ Hour of the day, 0..23 -- so the A/P keys can tell whether the meridiem already reads
  what was pressed and step only when it does not. }
function TTyDateTimePicker.HourOf(AValue: TDateTime): Integer;
var
  h, m, sec, ms: Word;
begin
  { DecodeTime on the empty sentinel would raise, and this runs off an A/P keystroke --
    the seed carries no time, so an empty field reads as midnight and 'P' steps it into
    the afternoon, which is the same thing that would happen on a freshly seeded one. }
  if TyDateIsNull(AValue) then AValue := NullSeedDate;
  DecodeTime(AValue, h, m, sec, ms);
  Result := h;
end;

function TTyDateTimePicker.TwelveHourFormat: Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FSegments) do
    if FSegments[i].Kind = skAMPM then Exit(True);
end;

function TTyDateTimePicker.HasDropDownButton: Boolean;
begin
  Result := (FDateMode = dmComboBox) and (FKind = dtkDate);
end;

function TTyDateTimePicker.HasSpinButtons: Boolean;
begin
  Result := (FDateMode = dmUpDown) or
            ((FDateMode = dmComboBox) and (FKind = dtkTime));
end;

function TTyDateTimePicker.ButtonColumnLogical: Integer;
begin
  if FDateMode = dmNone then
    Result := 0
  else
    Result := ActiveController.Metric('--field-button-width', TyFieldButtonWidth);
end;

function TTyDateTimePicker.ButtonWidthDev: Integer;
begin
  Result := MulDiv(ButtonColumnLogical, Font.PixelsPerInch, 96);
end;

function TTyDateTimePicker.IsInert: Boolean;
begin
  { dtpoEnabledIfUnchecked keeps the field editable while the box is clear -- LCL's
    flag of the same name (datetimepicker.pas:1024). Without it an unchecked picker
    refuses every gesture, which is the right default but not the only useful one. }
  Result := FShowCheckBox and not FChecked and
            not (dtpoEnabledIfUnchecked in FOptions);
end;

procedure TTyDateTimePicker.FieldLayout(const ALocal: TRect; APPI: Integer;
  out ARects: TTyDateTimeRects; out AStyle: TTyStyleSet;
  out AFontSizePx: Integer; out AText: string;
  out ASpans: TTySegmentArray; out AOriginX: Integer);
begin
  AStyle      := CurrentStyle;
  AFontSizePx := ResolveFontSize(AStyle);
  { The direction is asked ONCE, here, and every x downstream is whatever this call
    produced -- the paint's, the hit test's and the preferred width's alike. }
  ARects      := TyDateTimeRects(ALocal, APPI, AStyle.Padding,
                   ButtonColumnLogical, FShowCheckBox, IsRightToLeft);
  { The string and its spans come out of one call because they must agree; the origin
    then comes out of the SAME text box the string will be drawn in, which is the join
    the hit-test used to make for itself against a rect it built separately. }
  BuildDisplay(AText, ASpans);
  AOriginX    := TextOriginX(ARects.Text, AText, AStyle.FontName, AFontSizePx,
                   AStyle.FontWeight, APPI);
end;

function TTyDateTimePicker.SegmentSpanX(const AText: string;
  const ASpans: TTySegmentArray; AOriginX, AIndex: Integer;
  const AFontName: string; AFontSizePx, AFontWeight, APPI: Integer;
  out AX1, AX2: Integer): Boolean;
begin
  AX1    := 0;
  AX2    := 0;
  Result := (AIndex >= 0) and (AIndex <= High(ASpans));
  if not Result then Exit;
  { Spans are offsets into AText itself -- measured, not inferred from the format -- so a
    month NAME or an unpadded day no longer drags the highlight off the field. }
  AX1 := AOriginX + MeasureCharX(AText, AFontName, ASpans[AIndex].StartCh,
           AFontSizePx, AFontWeight, APPI);
  AX2 := AOriginX + MeasureCharX(AText, AFontName,
           ASpans[AIndex].StartCh + ASpans[AIndex].LenCh,
           AFontSizePx, AFontWeight, APPI);
  if AX2 <= AX1 then AX2 := AX1 + MulDiv(8, APPI, 96);  // degenerate guard
end;

function TTyDateTimePicker.SegmentAtX(const AText: string;
  const ASpans: TTySegmentArray; AOriginX, AX: Integer;
  const AFontName: string; AFontSizePx, AFontWeight, APPI: Integer): Integer;
var
  Bmp:     TBGRABitmap;
  TextX:   Integer;
  CharIdx: Integer;
  NextIdx: Integer;
  TxtLen:  Integer;
begin
  Result := -1;
  TxtLen := Length(AText);
  if TxtLen = 0 then Exit;
  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, AFontName, AFontSizePx, AFontWeight, APPI);
    { The step is a whole CHARACTER (TyDateTimeNextCharOffset), so the measured prefix is
      never a Chinese separator cut down the middle -- see that function for why the
      offset stays in bytes. }
    TextX   := AX - AOriginX;
    CharIdx := 0;
    while CharIdx < TxtLen do
    begin
      NextIdx := TyDateTimeNextCharOffset(AText, CharIdx);
      if Bmp.TextSize(Copy(AText, 1, NextIdx)).cx >= TextX then
        Break;
      CharIdx := NextIdx;
    end;
    Result := TyDateTimeActiveSegAt(ASpans, CharIdx);
  finally
    Bmp.Free;
  end;
end;

{ ── Dropdown helpers (dtkDate) ───────────────────────────────────────────── }

procedure TTyDateTimePicker.EnsurePopup;
begin
  if FPopup <> nil then Exit;

  { Create the calendar first (owned by Self, so FreeAndNil(FCalendar) frees it). }
  FCalendar             := TTyCalendar.Create(Self);
  FCalendar.Controller  := ActiveController;
  FCalendar.OnChange    := @CalendarChange;
  FCalendar.OnAccept    := @CalendarAccepted;

  { Create the popup helper (owns its form; does NOT own FCalendar). }
  FPopup            := TTyDropdownPopup.Create;
  FPopup.Controller := ActiveController;
  FPopup.OnClose    := @PopupClosed;

  { Parent the calendar into the popup form (SetContent does NOT transfer ownership). }
  FPopup.SetContent(FCalendar);

  { Allow Escape to close the popup from anywhere in the popup form. }
  FPopup.Form.KeyPreview := True;
  FPopup.Form.OnKeyDown  := @PopupFormKeyDown;
end;

procedure TTyDateTimePicker.OpenDropDown;
var
  CalStyle: TTyStyleSet;
  Radius: Integer;
begin
  if IsInert then Exit;
  { DateMode, not Kind, decides whether there is a calendar to drop. }
  if not HasDropDownButton then Exit;
  if (FPopup <> nil) and FPopup.IsOpen then Exit;

  { Guard the click-while-open reopen race: the popup deactivates (fires
    PopupClosed → Close) BEFORE the picker's MouseDown/Click handler runs.
    Suppress reopen if CloseUp happened within the last 200 ms. }
  if GetTickCount64 - FCloseUpTick <= 200 then Exit;

  EnsurePopup;
  SeedPopupCalendar;

  CalStyle := ActiveController.Model.ResolveStyle('TyCalendar', '', []);
  Radius   := CalStyle.BorderRadius;
  FPopup.CornerRadiusLogical := Radius;
  FPopup.Controller := ActiveController;

  if Assigned(FOnDropDown) then FOnDropDown(Self);

  { Show the popup below (or above) the picker control -- hanging from the edge the
    field reads FROM, so a mirrored picker drops its calendar under its own reading
    start rather than trailing off the far side of the control. }
  FPopup.Popup(Self, 240, 220, IsRightToLeft);
  Invalidate;
end;

procedure TTyDateTimePicker.SeedPopupCalendar;
begin
  if FCalendar = nil then Exit;

  { Seed the calendar from the picker's current state -- BOUNDS FIRST.

    The popup calendar is reused across opens, so it still carries the previous open's
    MinDate/MaxDate. Assigning Date first therefore validated the new date against the
    OLD range: if the picker's range moved between opens, the date the picker legitimately
    holds is out of the calendar's stale range. That used to clamp silently and recover by
    luck -- the popup then showed a date the picker did not hold -- and now that an
    out-of-range assignment raises, it would abort the dropdown instead. Setting the
    bounds first means the date is only ever checked against the range it belongs to. }
  FCalendar.MinDate       := FMinDate;
  FCalendar.MaxDate       := FMaxDate;
  { An EMPTY field has no date to show the calendar, and DateOf on the sentinel does not
    produce one -- it produces a value the calendar's own setter RAISES on
    (tyControls.Calendar.pas:510-516), so an unguarded seed does not merely open on the
    wrong month, it throws out of the click that opened the popup. Show the seed instead:
    today, pulled inside the same bounds. Note this does NOT fill the picker -- the field
    stays empty until the user actually picks a day. }
  if DateIsNull then
    FCalendar.Date := NullSeedDate
  else
    FCalendar.Date := DateOf(FDateTime);
  { Was pinned to wdSunday, which quietly overrode the calendar's own locale default --
    so on a Monday-first machine the dropdown disagreed with a standalone calendar on
    the same form. Let the calendar decide; a host that wants a fixed column order sets
    it on the calendar it can reach through the Calendar property. }
  FCalendar.FirstDayOfWeek := wdLocaleDefault;
  { Use ActiveController (falls back to the global default when Controller is nil) —
    a picker themed via the global TyDefaultController has Controller=nil, and the
    old FCalendar.Controller.Model deref here crashed the dropdown with an AV. }
  FCalendar.Controller    := ActiveController;
end;

procedure TTyDateTimePicker.CloseDropDown;
begin
  if (FPopup <> nil) and FPopup.IsOpen then
    FPopup.Close
  else
  begin
    { Headless path: no real window, but still update tick and fire events. }
    FCloseUpTick := GetTickCount64;
    Invalidate;
    if Assigned(FOnCloseUp) then FOnCloseUp(Self);
  end;
end;

procedure TTyDateTimePicker.PopupClosed(Sender: TObject);
begin
  if FPopup <> nil then
    FCloseUpTick := FPopup.CloseUpTick;
  Invalidate;
  if Assigned(FOnCloseUp) then FOnCloseUp(Self);
end;

procedure TTyDateTimePicker.PopupFormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    CloseDropDown;
    Key := 0;
  end;
end;

procedure TTyDateTimePicker.CalendarChange(Sender: TObject);
{ OnChange: arrow-key navigation inside the popup.  Update the date part of
  FDateTime so the picker text follows live, but do NOT close the popup. }
var
  OldVal: TDateTime;
begin
  if FCalendar = nil then Exit;
  OldVal    := FDateTime;
  { Keep the time part; replace only the date part -- except that an EMPTY field has no
    time part, and Frac of the sentinel is not one. Navigating the calendar over an empty
    field FILLS it, which is what the user asked for by moving the selection. }
  if TyDateIsNull(FDateTime) then
    FDateTime := DateOf(FCalendar.Date)
  else
    FDateTime := DateOf(FCalendar.Date) + Frac(FDateTime);
  { Clamp to [MinDate, MaxDate] }
  if (FMinDate <> 0) and (FDateTime < FMinDate) then FDateTime := FMinDate;
  if (FMaxDate <> 0) and (FDateTime > FMaxDate) then FDateTime := FMaxDate;
  if not TyEqualDateTime(FDateTime, OldVal) then
    if Assigned(FOnChange) then FOnChange(Self);
  Invalidate;
end;

procedure TTyDateTimePicker.CalendarAccepted(Sender: TObject);
{ OnAccept: user clicked a day cell or pressed Enter.  Commit the date and
  close the popup.  SetDateTime handles clamping + OnChange.
  Uses CloseDropDown so both the real-window path (fires PopupClosed→OnCloseUp)
  and the headless test path (CloseDropDown's else-branch fires OnCloseUp) work. }
var
  NewDate, OldVal: TDateTime;
begin
  if FCalendar = nil then Exit;
  { Same as CalendarChange: no time part to keep when the field is empty. Picking a day
    is the gesture that fills an empty field. }
  if TyDateIsNull(FDateTime) then
    NewDate := DateOf(FCalendar.Date)
  else
    NewDate := DateOf(FCalendar.Date) + Frac(FDateTime);
  OldVal  := FDateTime;
  SetDateTime(NewDate);
  { Picking a day in the dropdown is a USER edit, so it must notify even though it goes
    through the (now silent) programmatic setter. Without this line the one gesture the
    dropdown exists for became the one gesture that told nobody. }
  if (not TyEqualDateTime(FDateTime, OldVal))
     and not (dtpoDoChangeOnSetDateTime in FOptions)
     and Assigned(FOnChange) then
    FOnChange(Self);
  { Close after committing — CloseDropDown handles both the real-window path
    (FPopup.Close → PopupClosed → FOnCloseUp) and the headless path
    (directly fires FOnCloseUp). }
  CloseDropDown;
end;

{ ── Focus ────────────────────────────────────────────────────────────────── }

procedure TTyDateTimePicker.DoEnter;
begin
  inherited DoEnter;
  { Snapshot on the way in: this is the value Escape restores, so it has to be taken
    before the user can touch anything. }
  ConfirmChanges;
  { dtpoResetSelection: always land on the first field rather than wherever the last
    visit left the caret (LCL datetimepicker.pas:2852). }
  if (dtpoResetSelection in FOptions) and (Length(FSegments) > 0) then
    FActiveSeg := 0;
  Invalidate;
end;

procedure TTyDateTimePicker.DoExit;
var SavedDT: TDateTime;
begin
  inherited DoExit;
  SavedDT := FDateTime;
  { Commit any pending digit buffer on focus-out }
  if FDigitBuffer <> '' then
    FinalizeBuffer(SavedDT, False)
  else
    CommitAndFire(SavedDT);
  Invalidate;
end;

{ ── Rendering ────────────────────────────────────────────────────────────── }

procedure TTyDateTimePicker.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P:         TTyPainter;
  S:         TTyStyleSet;
  CbS:       TTyStyleSet;
  L:         TTyDateTimeRects;
  R, TextR:  TRect;
  EffSize:   Integer;
  Txt:       string;
  TextColor: TTyColor;
  { Selection highlight }
  SelStyle:  TTyStyleSet;
  SelFill:   TTyFill;
  SegX1, SegX2, OriginX: Integer;
  SegRect:   TRect;
  Spans:     TTySegmentArray;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    { Armed with the direction, so the Alignment handed to DrawText below is resolved by
      the painter's own BidiFlipAlignment -- the same two-row lookup TextOriginX used to
      place the highlight. Opting in is only safe because the GEOMETRY mirrors too: a
      painter that flips the text while the rects stay put is precisely the "drawn on the
      right, answers on the left" defect this library has shipped three times. }
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    { Every x below -- the text box, the checkbox, the button column and the origin the
      string starts at -- comes out of this one call, and so does the hit-test's. }
    FieldLayout(R, APPI, L, S, EffSize, Txt, Spans, OriginX);
    { Write down what this frame is about to draw with, before anything is drawn with it.
      Every x below comes from these four, so a guard that reads them is reading the
      paint's own answer rather than re-asking the function the hit test asks. }
    FPaintedRects   := L;
    FPaintedOriginX := OriginX;
    FPaintedText    := Txt;
    FPaintedSpans   := Copy(Spans, 0, Length(Spans));
    DrawFrame(P, R, S);
    TextR := L.Text;

    { ShowCheckBox: the column is already reserved in TextR; draw the glyph in it }
    if FShowCheckBox then
    begin
      { Resolve checkbox style from TyCheckBox typeKey }
      if FChecked then
        CbS := ActiveController.Model.ResolveStyle('TyCheckBox', '', [tysActive])
      else
        CbS := ActiveController.Model.ResolveStyle('TyCheckBox', '', []);
      P.FillBackground(L.CheckBox, CbS.Background, CbS.BorderRadius);
      P.StrokeBorder(L.CheckBox, CbS.BorderRadius, CbS.BorderWidth, CbS.BorderColor);
      if FChecked then
        P.DrawGlyph(L.CheckBox, tgCheck, CbS.TextColor, 2);
    end;

    { Determine text color: muted when inert (ShowCheckBox + not Checked) }
    TextColor := S.TextColor;
    if IsInert then
    begin
      { Resolve muted color from TyCheckBox :disabled or fall back to half-opacity }
      CbS := ActiveController.Model.ResolveStyle('TyCheckBox', '', [tysDisabled]);
      TextColor := CbS.TextColor;
    end;

    { 1. Active-segment highlight (drawn BEFORE text so glyphs appear on top)
         Only when focused AND field is not inert. }
    if Focused and not IsInert and
       (FActiveSeg >= 0) and (FActiveSeg <= High(Spans)) then
    begin
      SelStyle := ActiveController.Model.ResolveStyle('TyTextSelection', '', []);
      SelFill  := Default(TTyFill);
      SelFill.Kind  := tfkSolid;
      SelFill.Color := SelStyle.Background.Color;

      if SegmentSpanX(Txt, Spans, OriginX, FActiveSeg, S.FontName, EffSize,
           S.FontWeight, APPI, SegX1, SegX2) then
      begin
        SegRect := Rect(SegX1, TextR.Top, SegX2, TextR.Bottom);
        P.FillBackground(SegRect, SelFill, 0);
      end;
    end;

    { 2. Draw the formatted text }
    P.DrawText(TextR, Txt, S.FontName, EffSize, S.FontWeight,
      TextColor, FAlignment, tlCenter, False);

    { 3. Right-side button area — the rects come back empty under dmNone }
    if not IsRectEmpty(L.Button) then
    begin
      if HasDropDownButton then
        { The same fixed-size chevron every other drop field draws. DrawGlyph STRETCHES its
          mark to fill the rect it is given, so on a full-height button zone this came out a
          wide flat V unlike any combo box in the library -- 'that drop arrow is ugly, make it
          the same as the combo box's' was exactly right. }
        TyDrawDropChevron(P, ActiveController, L.Button, S.TextColor)
      else if HasSpinButtons then
      begin
        { Same spinner shape and slot rule as TTySpinEdit -- one element, one style. }
        P.DrawGlyph(TySquareGlyphBox(L.ButtonUp),   tgTriangleUp,   S.TextColor, 2, 1);
        P.DrawGlyph(TySquareGlyphBox(L.ButtonDown), tgTriangleDown, S.TextColor, 2, 1);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyDateTimePicker.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyDateTimePicker.CalculatePreferredSize(
  var PreferredWidth, PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  Bmp: TBGRABitmap;
  EffSize, PPI, TextW, TextH, NullW: Integer;
  Txt: string;
  Spans: TTySegmentArray;
  Widest: TDateTime;
begin
  inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
  S       := CurrentStyle;
  EffSize := ResolveFontSize(S);
  PPI     := Font.PixelsPerInch;

  { Measure a value whose fields are as wide as this format can render, not the value
    that happens to be showing: a field sized to "1 May" clips the day it is switched
    to September, and LeadingZeros=False makes that a routine occurrence. 30 September
    is the widest month name in most locales and gives two-digit day/hour/minute. }
  Widest := EncodeDateTime(2026, 9, 30, 22, 58, 58, 888);
  { Same name source as BuildDisplay -- measuring the locale's names for a field
    that renders the app language's would size the box for the wrong string. }
  Txt := TyRenderDateTime(Widest, ActiveFormat, TyDateTimeNames,
           FLeadingZeros, Spans);
  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, S.FontName, EffSize, S.FontWeight, PPI);
    TextW := Bmp.TextSize(Txt).cx;
    TextH := Bmp.TextSize(Txt).cy;
    { The field can show EITHER string, so it has to be wide enough for both. Measuring
      only the date is how a picker whose TextForNullDate reads "no deadline set" clips
      the words the moment it is emptied -- and an AutoSize field would have shrunk to
      the date's width and stayed there. Measured unconditionally rather than only when
      the field happens to be empty, because the width must not change under the user
      when the value does. }
    NullW := Bmp.TextSize(FTextForNullDate).cx;
    if NullW > TextW then TextW := NullW;
  finally
    Bmp.Free;
  end;

  PreferredWidth := MulDiv(S.Padding.Left + S.Padding.Right, PPI, 96)
                  + TextW + ButtonWidthDev;
  { The same column the text box reserves, from the same function that reserves it -- a
    width query that budgets for a different checkbox than the paint draws is how a field
    ends up one pixel short of the text it just asked to fit. }
  if FShowCheckBox then
    Inc(PreferredWidth, TyDateTimeCheckBoxColumn(PPI));
  { One character of slack: TextSize rounds down on some backends and a date that just
    fits is a date that clips on the next repaint. }
  Inc(PreferredWidth, MulDiv(EffSize, PPI, 96) div 2 + 2);

  PreferredHeight := MulDiv(S.Padding.Top + S.Padding.Bottom, PPI, 96) + TextH;
  if PreferredHeight < TyDensityHeight(ActiveController, 24) then
    PreferredHeight := TyDensityHeight(ActiveController, 24);
end;

{ ── Keyboard ─────────────────────────────────────────────────────────────── }

procedure TTyDateTimePicker.KeyDown(var Key: Word; Shift: TShiftState);
var OldVal: TDateTime;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);

  { Escape: close the dropdown if it is open, otherwise revert the whole edit.
    It used to drop only the half-typed digits, so a month the user had spun with the
    arrow keys survived the Escape -- the one gesture everybody uses to mean "forget
    it" quietly did almost nothing. LCL restores its focus-in snapshot here
    (datetimepicker.pas:3725-3730 -> UndoChanges). ReadOnly has nothing to revert. }
  if Key = VK_ESCAPE then
  begin
    if (FPopup <> nil) and FPopup.IsOpen then
      CloseDropDown
    else if not FReadOnly then
      UndoChanges
    else
      FDigitBuffer := '';
    Invalidate;
    Key := 0;
    Exit;
  end;

  { Alt+Down or F4: toggle the dropdown, when there is one to toggle }
  if HasDropDownButton then
  begin
    if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
    begin
      if (FPopup <> nil) and FPopup.IsOpen then
        CloseDropDown
      else
        OpenDropDown;
      Key := 0;
      Exit;
    end;
  end;

  { If field is inert (ShowCheckBox + not Checked), block all further editing }
  { Space toggles the enable checkbox, and this MUST sit above the IsInert gate below.
    IsInert is `ShowCheckBox and not Checked`, so an unchecked picker refuses every key --
    which meant the one key that could switch it on was refused too. The box is a ~12px
    mouse target, so with the gate in front of this branch a keyboard user could tab to
    the control and had no way to make it editable at all. }
  if (Key = VK_SPACE) and (Shift = []) and FShowCheckBox and not FReadOnly then
  begin
    Checked := not FChecked;
    Key := 0;
    Exit;
  end;
  if IsInert then Exit;

  { N (LCL's key, datetimepicker.pas:3731) and Delete empty the field. Delete is ours:
    LCL binds only the letter, which nobody guesses, while Delete is what a user reaches
    for to clear a field and costs one label here. Both are USER gestures, so unlike the
    programmatic setter they announce themselves -- CommitAndFire does that, and it also
    means pressing the key twice is silent the second time. }
  if ((Key = VK_N) or (Key = VK_DELETE)) and (Shift = []) then
  begin
    if FNullInputAllowed and not FReadOnly then
    begin
      OldVal       := FDateTime;
      FDateTime    := TyNullDate;
      FDigitBuffer := '';
      CommitAndFire(OldVal);
    end;
    Key := 0;
    Exit;
  end;

  case Key of
    VK_LEFT, VK_RIGHT:
      begin
        { MIRRORING: these arrows step between FIELDS -- year to month to day -- not
          between characters, so by the criterion in §6.3 item 4 of
          plans/2026-08-04-rtl-mirroring-scope.md they are LAYOUT direction and they
          swap. This control is the one case that criterion was written to settle: it
          can be typed into, which makes it look like the text-editing exclusion, but
          nothing here moves a caret. Left unswapped, a right-to-left user pressing the
          key that points at the next field walks away from it.

          Finalize any pending buffer first, whichever way we are about to move. }
        OldVal := FDateTime;
        if FDigitBuffer <> '' then FinalizeBuffer(OldVal, False);
        if (Key = VK_RIGHT) <> IsRightToLeft then
        begin
          if FActiveSeg < High(FSegments) then Inc(FActiveSeg);
        end
        else
          if FActiveSeg > 0 then Dec(FActiveSeg);
        Invalidate; Key := 0;
      end;
    VK_HOME:
      begin
        OldVal := FDateTime;
        if FDigitBuffer <> '' then FinalizeBuffer(OldVal, False);
        FActiveSeg := 0;
        Invalidate; Key := 0;
      end;
    VK_END:
      begin
        OldVal := FDateTime;
        if FDigitBuffer <> '' then FinalizeBuffer(OldVal, False);
        if Length(FSegments) > 0 then FActiveSeg := High(FSegments);
        Invalidate; Key := 0;
      end;
    VK_UP:
      begin
        if not FReadOnly then StepActiveSeg(+1);
        Key := 0;
      end;
    VK_DOWN:
      begin
        if not FReadOnly then StepActiveSeg(-1);
        Key := 0;
      end;
    VK_RETURN:
      begin
        OldVal := FDateTime;
        if FDigitBuffer <> '' then
          FinalizeBuffer(OldVal, False)
        else
          CommitAndFire(OldVal);
        Key := 0;
      end;
  end;
end;

procedure TTyDateTimePicker.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  OldVal:   TDateTime;
  AutoAdv:  Boolean;
begin
  if not Enabled then Exit;
  inherited UTF8KeyPress(UTF8Key);
  if FReadOnly then Exit;
  if IsInert then Exit;
  { A / P set AM / PM directly when the meridiem field is selected. Without this the
    only way to change it was the up/down arrow or the wheel, so a touch-typist filling
    the field left to right hit a dead stop at the last segment -- and 'A'/'P' is what
    every native picker accepts. Set, not toggle: pressing A twice must leave AM. }
  if (Length(UTF8Key) = 1) and (UpCase(UTF8Key[1]) in ['A', 'P'])
     and (FActiveSeg >= 0) and (FActiveSeg <= High(FSegments))
     and (FSegments[FActiveSeg].Kind = skAMPM) then
  begin
    if UpCase(UTF8Key[1]) = 'A' then
    begin
      if HourOf(FDateTime) >= 12 then StepActiveSeg(-1);
    end
    else
      if HourOf(FDateTime) < 12 then StepActiveSeg(1);
    UTF8Key := '';
    Exit;
  end;
  { A date/time separator commits the field being typed and moves on, so a user can type
    1/2/2026 straight through instead of reaching for the arrow key between fields. Every
    native picker does this; ours only advanced when a field filled up, which means a
    single-digit month left the caret parked. }
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in ['/', '-', '.', ',', ':', ' ']) then
  begin
    OldVal := FDateTime;
    if FDigitBuffer <> '' then
      FinalizeBuffer(OldVal, True)          { commit + advance }
    else if FActiveSeg < High(FSegments) then
    begin
      Inc(FActiveSeg);
      Invalidate;
    end;
    UTF8Key := '';
    Exit;
  end;
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in ['0'..'9']) then
  begin
    OldVal  := FDateTime;
    AutoAdv := AccumulateDigit(UTF8Key[1]);
    if AutoAdv then
      { Buffer full: finalize + auto-advance to next segment }
      FinalizeBuffer(OldVal, True)
    else
      { Still accumulating: just redraw to show buffer content }
      Invalidate;
  end;
end;

{ ── Mouse wheel ──────────────────────────────────────────────────────────── }

function TTyDateTimePicker.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  if FReadOnly then Exit(False);
  if IsInert then Exit(False);
  if WheelDelta > 0 then
    StepActiveSeg(+1)
  else
    StepActiveSeg(-1);
  Result := True;
end;

{ ── Mouse down — segment hit-test + button clicks ────────────────────────── }

procedure TTyDateTimePicker.Click;
begin
  inherited Click;
  if FMouseDownOnButton then
  begin
    FMouseDownOnButton := False;
    { Toggle: when the popup is open, the click's deactivate already closed it (and
      OpenDropDown's 200ms guard suppresses an immediate reopen); otherwise open it.
      Mirrors TTyComboBox.Click — opening here (not in MouseDown) avoids the mouse-up
      activation change closing the just-shown popup. }
    if DroppedDown then CloseDropDown
    else OpenDropDown;
  end;
end;

procedure TTyDateTimePicker.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  S:        TTyStyleSet;
  L:        TTyDateTimeRects;
  EffSize:  Integer;
  Txt:      string;
  HitSeg:   Integer;
  OriginX:  Integer;
  CbBoxR:   TRect;
  Spans:    TTySegmentArray;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  FMouseDownOnButton := False;
  if Button = mbLeft then
  begin
    { The same rects the paint used, from the same call the paint uses -- there is no
      second tiling of the field's width to keep in step any more. }
    FieldLayout(ClientRect, Font.PixelsPerInch, L, S, EffSize, Txt, Spans, OriginX);

    { ── Checkbox area click ─────────────────────────────────────────────── }
    if FShowCheckBox then
    begin
      { Expand hit area slightly (easy to miss tiny box) }
      CbBoxR := Rect(L.CheckBox.Left - 2, L.CheckBox.Top - 2,
                     L.CheckBox.Right + 2, L.CheckBox.Bottom + 2);
      if PtInRect(CbBoxR, Point(X, Y)) then
      begin
        { Through the property, so the notification happens in one place. }
        Checked := not FChecked;
        try
          if CanFocus then SetFocus;
        except
        end;
        Exit;
      end;
    end;

    { ── Button area click ───────────────────────────────────────────────── }
    if not IsRectEmpty(L.Button) and PtInRect(L.Button, Point(X, Y)) then
    begin
      if HasDropDownButton then
      begin
        { Chevron pressed → remember it; the actual open happens in Click (so the
          mouse-up that follows MouseDown can't immediately deactivate-close the popup). }
        if not IsInert then
          FMouseDownOnButton := True;
      end
      else if HasSpinButtons and not FReadOnly and not IsInert then
      begin
        if PtInRect(L.ButtonUp, Point(X, Y)) then
          StepActiveSeg(+1)
        else
          StepActiveSeg(-1);
      end;
    end
    else if not IsInert then
    begin
      { ── Segment hit-test ─────────────────────────────────────────────── }
      { The string, the spans and the origin are the paint's own -- resolving a click
        against offsets derived from the FORMAT is what put the caret on the month when
        the user clicked the year in 'dd mmmm yyyy'. }
      HitSeg := SegmentAtX(Txt, Spans, OriginX, X, S.FontName, EffSize,
                  S.FontWeight, Font.PixelsPerInch);
      if HitSeg >= 0 then
      begin
        FActiveSeg   := HitSeg;
        FDigitBuffer := '';
        Invalidate;
      end;
    end;

    try
      if CanFocus then SetFocus;
    except
    end;
  end;
end;

{ ── Property setters ─────────────────────────────────────────────────────── }

{ Everything that changes what the field RENDERS also changes what it needs to be wide
  enough for, so each of these re-measures. Leaving that out is how AutoSize ends up
  "implemented" but never actually growing: the first measurement would stand forever. }
procedure TTyDateTimePicker.ContentChanged;
begin
  InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TTyDateTimePicker.SetKind(AValue: TTyDateTimeKind);
begin
  if FKind = AValue then Exit;
  FKind := AValue;
  RebuildSegments;
  ContentChanged;
end;

{ BEHAVIOUR CHANGE: a programmatic write is SILENT unless dtpoDoChangeOnSetDateTime is
  in Options -- LCL's rule (UpdateDate(dtpoDoChangeOnSetDateTime in FOptions),
  datetimepicker.pas:1210, and cDefOptions = []).

  It used to fire unconditionally, so the ordinary "load this record into the form"
  line re-entered the application's own OnChange handler: the dirty flag came up on a
  form nobody had touched, and a handler that wrote back to the model looped. There was
  no flag to turn it off. If your handler genuinely wants to run on code writes, put
  dtpoDoChangeOnSetDateTime in Options; if it wants to run on user edits only -- which
  is what OnChange means everywhere else -- you now get that for free. }
procedure TTyDateTimePicker.SetDateTime(AValue: TDateTime);
begin
  { The empty value is checked BEFORE any clamp, and normalised to exactly TyNullDate.
    Order is the whole of it: the sentinel is above the ceiling by construction, so a
    clamp reached first turns "no date" into 31 Dec 9999 and the field reads back as a
    date the caller never wrote. Normalising means the stored value is always this one,
    so `FDateTime <> AOldVal` downstream keeps working on plain floats.

    NullInputAllowed is deliberately NOT consulted here. It governs the USER's keyboard
    route, not the host's own writes -- a form that loads a record whose column is NULL
    is passing its data, not typing, and LCL draws the line in the same place
    (datetimepicker.pas:1202 does not check it; :3731 does). }
  if TyDateIsNull(AValue) then
    AValue := TyNullDate
  else
  begin
    if (FMinDate <> 0) and (AValue < FMinDate) then AValue := FMinDate;
    if (FMaxDate <> 0) and (AValue > FMaxDate) then AValue := FMaxDate;
    if AValue < TyTheSmallestDate then AValue := TyTheSmallestDate;
    if AValue > TyTheBiggestDate  then AValue := TyTheBiggestDate;
  end;
  if TyEqualDateTime(FDateTime, AValue) then Exit;
  FDateTime := AValue;
  FDigitBuffer := '';
  { The value the host just supplied is the new baseline: Escape must undo what the
    USER did afterwards, not throw away the record that was just loaded. }
  FConfirmedDateTime := FDateTime;
  if (dtpoDoChangeOnSetDateTime in FOptions) and Assigned(FOnChange) then
    FOnChange(Self);
  Invalidate;
end;

procedure TTyDateTimePicker.ConfirmChanges;
begin
  FConfirmedDateTime := FDateTime;
end;

procedure TTyDateTimePicker.UndoChanges;
begin
  FDigitBuffer := '';
  { TyEqualDateTime, not `<>`: restoring an EMPTY snapshot over a date has to count as a
    change, and restoring one empty value over another must not.

    The second half is currently unreachable and the reason is worth recording rather
    than rediscovering: both values here came through SetDateTime or CommitAndFire, which
    normalise every empty write to exactly TyNullDate, so two empty values are always
    bit-identical and plain `<>` gives the same answer (verified by mutation -- swapping
    it back survives). This spelling stays because it does not depend on that invariant
    holding somewhere else. }
  if not TyEqualDateTime(FDateTime, FConfirmedDateTime) then
  begin
    FDateTime := FConfirmedDateTime;
    { A revert IS a change from the handler's point of view -- the value it was last
      told about is no longer the value -- so OnChange fires as for any other user
      gesture. }
    if Assigned(FOnChange) then FOnChange(Self);
  end;
  Invalidate;
end;

{ Date and Time each keep the HALF of the standing value they are not writing -- and an
  empty value has no halves. Trunc and Frac of the sentinel are meaningless at best, and
  the number they produce would go straight into the host's record. Each of these three
  cases exists in LCL for the same reason (SetDate, datetimepicker.pas:1194-1200). }
procedure TTyDateTimePicker.SetDate(AValue: TDateTime);
begin
  if TyDateIsNull(AValue) then
    SetDateTime(TyNullDate)
  else if DateIsNull then
    { Nothing to keep: the new date starts at midnight rather than picking up a
      fraction of infinity. }
    SetDateTime(Trunc(AValue))
  else
    SetDateTime(Trunc(AValue) + Frac(FDateTime));
end;

function TTyDateTimePicker.GetDate: TDateTime;
begin
  if DateIsNull then Result := TyNullDate
  else Result := Trunc(FDateTime);
end;

procedure TTyDateTimePicker.SetTime(AValue: TDateTime);
begin
  if TyDateIsNull(AValue) then
    SetDateTime(TyNullDate)
  else if DateIsNull then
    { A time needs a day to sit on. The seed is today pulled inside the bounds, not the
      raw zero -- writing a time into an empty field must not silently date it 1899. }
    SetDateTime(NullSeedDate + Frac(AValue))
  else
    SetDateTime(Trunc(FDateTime) + Frac(AValue));
end;

function TTyDateTimePicker.GetTime: TDateTime;
begin
  if DateIsNull then Result := TyNullDate
  else Result := Frac(FDateTime);
end;

procedure TTyDateTimePicker.SetDateFormat(const AValue: string);
begin
  if FDateFormat = AValue then Exit;
  FDateFormat := AValue;
  if FKind = dtkDate then RebuildSegments;
  ContentChanged;
end;

procedure TTyDateTimePicker.SetTimeFormat(const AValue: string);
begin
  if FTimeFormat = AValue then Exit;
  FTimeFormat := AValue;
  if FKind = dtkTime then RebuildSegments;
  ContentChanged;
end;

{ Moving a bound re-clamps a standing value that now sits outside it. An EMPTY value sits
  outside EVERY bound by construction, so `FDateTime > FMaxDate` is true of it -- and
  without the guard the ceiling's setter reads the emptiness as a date that overshot and
  fills the field in, from a line that never mentions the value at all. LCL guards both
  the same way (`if not DateIsNull then`, datetimepicker.pas:1232, :1251).

  Only the CEILING can actually trip today, and it is worth writing down which one is
  load-bearing: the sentinel sits at the top of the range, so `FDateTime < FMinDate` is
  False of it and removing the floor's guard changes no observable behaviour (verified by
  mutation -- that mutant survives). It stays because it is the same guard, and because
  it is only unreachable while SetDateTime normalises every empty write to the POSITIVE
  sentinel; TyDateIsNull also accepts values below the floor, and a negative one stored
  raw would go straight through here. The normalisation is what makes it unreachable and
  the normalisation is pinned (test.datetimepicker,
  TheProgrammaticSetterKeepsTheValueEmpty). }
procedure TTyDateTimePicker.SetMinDate(AValue: TDateTime);
begin
  if FMinDate = AValue then Exit;
  FMinDate := AValue;
  if not DateIsNull then
    if (FMinDate <> 0) and (FDateTime < FMinDate) then SetDateTime(FMinDate);
  Invalidate;
end;

procedure TTyDateTimePicker.SetMaxDate(AValue: TDateTime);
begin
  if FMaxDate = AValue then Exit;
  FMaxDate := AValue;
  if not DateIsNull then
    if (FMaxDate <> 0) and (FDateTime > FMaxDate) then SetDateTime(FMaxDate);
  Invalidate;
end;

procedure TTyDateTimePicker.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  Invalidate;
end;

procedure TTyDateTimePicker.SetShowCheckBox(AValue: Boolean);
begin
  if FShowCheckBox = AValue then Exit;
  FShowCheckBox := AValue;
  ContentChanged;
end;

{ The event lives HERE, not at the mouse hit-test, so every route that flips the box
  announces it. Space used to toggle Checked without notifying anyone -- the keyboard
  path had been given the state change and not the event. LCL fires CheckBoxChange from
  its own setter too (datetimepicker.pas:1011-1020), deliberately unlike OnChange:
  a checkbox has no "user vs code" distinction worth drawing. }
procedure TTyDateTimePicker.SetChecked(AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  Invalidate;
  if Assigned(FOnChecked) then FOnChecked(Self);
end;

procedure TTyDateTimePicker.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyDateTimePicker.SetLeadingZeros(AValue: Boolean);
begin
  if FLeadingZeros = AValue then Exit;
  FLeadingZeros := AValue;
  { Only the RENDERING changes -- the field list comes from the author's format and is
    unaffected -- but the buffer's padding does, so drop it rather than redraw it at
    the other width mid-entry. }
  FDigitBuffer := '';
  ContentChanged;
end;

procedure TTyDateTimePicker.SetCenturyFrom(AValue: Word);
begin
  if FCenturyFrom = AValue then Exit;
  FCenturyFrom := AValue;
end;

procedure TTyDateTimePicker.SetDateMode(AValue: TTyDTDateMode);
begin
  if FDateMode = AValue then Exit;
  { Close first: switching away from dmComboBox with the calendar down would leave a
    popup on screen belonging to a control that no longer has a way to close it. }
  if (FDateMode = dmComboBox) and DroppedDown then CloseDropDown;
  FDateMode := AValue;
  { The button column's width changed, so the text rect did too. }
  ContentChanged;
end;

procedure TTyDateTimePicker.SetNullInputAllowed(AValue: Boolean);
begin
  { Storage only, exactly as LCL (datetimepicker.pas:1171): turning the permission off
    does not retroactively fill in a field that is already empty -- the host would have
    no idea what date to put there, and quietly inventing one is how a "required" flag
    ends up writing today's date into every blank row. }
  FNullInputAllowed := AValue;
end;

procedure TTyDateTimePicker.SetTextForNullDate(const AValue: TCaption);
begin
  if FTextForNullDate = AValue then Exit;
  FTextForNullDate := AValue;
  { ContentChanged, not just Invalidate: this string is one of the two the preferred
    width is the maximum of, so an AutoSize field that switches to "Not scheduled"
    has to re-measure or it clips the text it was just told to show. }
  ContentChanged;
end;

function TTyDateTimePicker.NullSeedDate: TDateTime;
begin
  Result := Trunc(SysUtils.Date);
  if (FMinDate <> 0) and (Result < FMinDate) then Result := FMinDate;
  if (FMaxDate <> 0) and (Result > FMaxDate) then Result := FMaxDate;
  if Result < TyTheSmallestDate then Result := TyTheSmallestDate;
  if Result > TyTheBiggestDate  then Result := TyTheBiggestDate;
end;

function TTyDateTimePicker.DateIsNull: Boolean;
begin
  Result := TyDateIsNull(FDateTime);
end;

function TTyDateTimePicker.GetDroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

procedure TTyDateTimePicker.SetDroppedDown(AValue: Boolean);
begin
  if AValue then
    OpenDropDown
  else
    CloseDropDown;
end;

end.
