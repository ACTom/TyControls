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
  Classes, SysUtils, Types, DateUtils,
  Controls, Graphics, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation,
  tyControls.Popup, tyControls.Calendar;

type
  TTyDateTimeKind = (dtkDate, dtkTime);

  TTySegKind = (skNone, skDay, skMonth, skYear, skHour, skMinute, skSecond, skAMPM);

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

    { Segment editing state }
    FSegments:    TTySegmentArray;  // computed from effective format
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

    function  ActiveFormat: string;
    function  EffectiveFormat: string;
    procedure RebuildSegments;
    function  FormattedText: string;
    { Return the text to render for the active segment: uses FDigitBuffer content
      when a buffer is active, otherwise the value from FDateTime. }
    function  ActiveSegDisplayText: string;
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
    function  IsInert: Boolean;
    { Resolve the checkbox box rect within ATextR (left of text content) @APPI. }
    function  CheckBoxRect(const ATextR: TRect; APPI: Integer): TRect;

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
    function  GetDroppedDown: Boolean;
    procedure SetDroppedDown(AValue: Boolean);

  protected
    { Step the active segment by ADelta and commit (protected for test probes). }
    procedure StepActiveSeg(ADelta: Integer);
    { Ensure FPopup + FCalendar are created (lazy init; protected for probes). }
    procedure EnsurePopup;

    function  GetStyleTypeKey: string; override;
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

    property Date:        TDateTime read GetDate    write SetDate;
    property Time:        TDateTime read GetTime    write SetTime;
    { Expose for tests }
    property ActiveSeg:   Integer   read FActiveSeg;
    property Segments:    TTySegmentArray read FSegments;
    property DigitBuffer: string    read FDigitBuffer;
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
    property OnChange:     TNotifyEvent    read FOnChange    write FOnChange;
    property OnDropDown:   TNotifyEvent    read FOnDropDown  write FOnDropDown;
    property OnCloseUp:    TNotifyEvent    read FOnCloseUp   write FOnCloseUp;
    property OnChecked:    TNotifyEvent    read FOnChecked   write FOnChecked;
    property Align;
    property Anchors;
    property Font;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

{ Button rect for the right-side button area (dtkDate = chevron, dtkTime = up/down) }
function TyDateTimeButtonRect(const ALocal: TRect; APPI: Integer): TRect;
{ For dtkTime: top half of the button = up arrow }
function TyDateTimeUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
{ For dtkTime: bottom half = down arrow }
function TyDateTimeDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;

implementation

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
    if Ch in ['y', 'm', 'd', 'h', 'n', 's'] then
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

{ ── Button geometry helpers ──────────────────────────────────────────────── }

function TyDateTimeButtonRect(const ALocal: TRect; APPI: Integer): TRect;
var BtnW, X0: Integer;
begin
  BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  Result := Rect(X0, ALocal.Top, ALocal.Right, ALocal.Bottom);
end;

function TyDateTimeUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
var BtnW, X0, HalfY: Integer;
begin
  BtnW  := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0    := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, ALocal.Top, ALocal.Right, HalfY);
end;

function TyDateTimeDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;
var BtnW, X0, HalfY: Integer;
begin
  BtnW  := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0    := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, HalfY, ALocal.Right, ALocal.Bottom);
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
  FActiveSeg     := 0;
  FDigitBuffer   := '';
  FPopup         := nil;
  FCalendar      := nil;
  FCloseUpTick   := 0;
  Width  := 130;
  Height := 24;
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
  { Scan the EFFECTIVE (normalized) format so segment positions match the
    rendered text positions. }
  FSegments := TyDateTimeSegments(EffectiveFormat);
  if FActiveSeg > High(FSegments) then
    FActiveSeg := 0;
  if Length(FSegments) = 0 then
    FActiveSeg := -1;
  FDigitBuffer := '';
end;

function TTyDateTimePicker.FormattedText: string;
begin
  { Render using the EFFECTIVE format (fixed-width fields). }
  Result := TyFormatDateTime(FDateTime, EffectiveFormat, DefaultFormatSettings);
end;

function TTyDateTimePicker.ActiveSegDisplayText: string;
{ Return the per-segment display text, substituting the buffer content for the
  active segment when a digit buffer is active (buffer-display model). }
var
  Full: string;
  Seg:  TTySegment;
  BufVal, RMin, RMax: Integer;
  SegText: string;
begin
  Full := FormattedText;
  if (FDigitBuffer = '') or (FActiveSeg < 0) or (FActiveSeg > High(FSegments)) then
  begin
    Result := Full;
    Exit;
  end;
  Seg := FSegments[FActiveSeg];
  if not TySegmentRange(Seg, RMin, RMax) then
  begin
    Result := Full;
    Exit;
  end;
  { Build the segment display string from the buffer:
    zero-pad on the left to match the segment width. }
  BufVal  := StrToIntDef(FDigitBuffer, 0);
  SegText := IntToStr(BufVal);
  while Length(SegText) < Seg.LenCh do
    SegText := '0' + SegText;
  { Splice into the full formatted string }
  Result := Copy(Full, 1, Seg.StartCh) +
            SegText +
            Copy(Full, Seg.StartCh + Seg.LenCh + 1, MaxInt);
end;

{ ── Pixel measurement helper ─────────────────────────────────────────────── }

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

  if Seg.Kind = skYear then
    MaxDigits := 4
  else
    MaxDigits := 2;

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
  if NewVal < RMin then NewVal := RMin;
  if NewVal > RMax then NewVal := RMax;

  DecodeDateTime(FDateTime, Y, M, D, H, Mi, S, MS);
  case Seg.Kind of
    skYear:   Y  := Word(NewVal);
    skMonth:  M  := Word(NewVal);
    skDay:    D  := Word(NewVal);
    skHour:   H  := Word(NewVal);
    skMinute: Mi := Word(NewVal);
    skSecond: S  := Word(NewVal);
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
  Clamped := FDateTime;
  if (FMinDate <> 0) and (Clamped < FMinDate) then Clamped := FMinDate;
  if (FMaxDate <> 0) and (Clamped > FMaxDate) then Clamped := FMaxDate;
  FDateTime := Clamped;
  if (FDateTime <> AOldVal) and Assigned(FOnChange) then
    FOnChange(Self);
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
  FDateTime := TySegmentStep(FDateTime, FSegments[FActiveSeg], ADelta);
  CommitAndFire(OldVal);
end;

{ ── IsInert / CheckBoxRect ───────────────────────────────────────────────── }

function TTyDateTimePicker.IsInert: Boolean;
begin
  Result := FShowCheckBox and not FChecked;
end;

function TTyDateTimePicker.CheckBoxRect(const ATextR: TRect; APPI: Integer): TRect;
{ Returns the small checkbox box rect aligned vertically within ATextR. }
var
  BoxSize, MidY: Integer;
begin
  BoxSize := MulDiv(TyCheckBoxBox, APPI, 96);
  MidY    := ATextR.Top + (ATextR.Bottom - ATextR.Top - BoxSize) div 2;
  Result  := Rect(ATextR.Left, MidY, ATextR.Left + BoxSize, MidY + BoxSize);
end;

{ ── Dropdown helpers (dtkDate) ───────────────────────────────────────────── }

procedure TTyDateTimePicker.EnsurePopup;
begin
  if FPopup <> nil then Exit;

  { Create the calendar first (owned by Self, so FreeAndNil(FCalendar) frees it). }
  FCalendar             := TTyCalendar.Create(Self);
  FCalendar.Controller  := Self.Controller;
  FCalendar.OnChange    := @CalendarChange;
  FCalendar.OnAccept    := @CalendarAccepted;

  { Create the popup helper (owns its form; does NOT own FCalendar). }
  FPopup            := TTyDropdownPopup.Create;
  FPopup.Controller := Self.Controller;
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
  if FKind <> dtkDate then Exit;
  if (FPopup <> nil) and FPopup.IsOpen then Exit;

  { Guard the click-while-open reopen race: the popup deactivates (fires
    PopupClosed → Close) BEFORE the picker's MouseDown/Click handler runs.
    Suppress reopen if CloseUp happened within the last 200 ms. }
  if GetTickCount64 - FCloseUpTick <= 200 then Exit;

  EnsurePopup;

  { Seed the calendar from the picker's current state. }
  FCalendar.Date          := DateOf(FDateTime);
  FCalendar.MinDate       := FMinDate;
  FCalendar.MaxDate       := FMaxDate;
  FCalendar.FirstDayOfWeek := wdSunday;
  FCalendar.Controller    := Self.Controller;

  { Match the popup corner radius to the calendar's resolved border-radius. }
  CalStyle := FCalendar.Controller.Model.ResolveStyle('TyCalendar', '', []);
  Radius   := CalStyle.BorderRadius;
  FPopup.CornerRadiusLogical := Radius;
  FPopup.Controller := Self.Controller;

  if Assigned(FOnDropDown) then FOnDropDown(Self);

  { Show the popup below (or above) the picker control. }
  FPopup.Popup(Self, 240, 220);
  Invalidate;
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
  { Keep the time part; replace only the date part. }
  FDateTime := DateOf(FCalendar.Date) + Frac(FDateTime);
  { Clamp to [MinDate, MaxDate] }
  if (FMinDate <> 0) and (FDateTime < FMinDate) then FDateTime := FMinDate;
  if (FMaxDate <> 0) and (FDateTime > FMaxDate) then FDateTime := FMaxDate;
  if (FDateTime <> OldVal) and Assigned(FOnChange) then
    FOnChange(Self);
  Invalidate;
end;

procedure TTyDateTimePicker.CalendarAccepted(Sender: TObject);
{ OnAccept: user clicked a day cell or pressed Enter.  Commit the date and
  close the popup.  SetDateTime handles clamping + OnChange.
  Uses CloseDropDown so both the real-window path (fires PopupClosed→OnCloseUp)
  and the headless test path (CloseDropDown's else-branch fires OnCloseUp) work. }
var
  NewDate: TDateTime;
begin
  if FCalendar = nil then Exit;
  NewDate := DateOf(FCalendar.Date) + Frac(FDateTime);
  SetDateTime(NewDate);
  { Close after committing — CloseDropDown handles both the real-window path
    (FPopup.Close → PopupClosed → FOnCloseUp) and the headless path
    (directly fires FOnCloseUp). }
  CloseDropDown;
end;

{ ── Focus ────────────────────────────────────────────────────────────────── }

procedure TTyDateTimePicker.DoEnter;
begin
  inherited DoEnter;
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
  R, TextR, BtnR, CbR: TRect;
  BtnW, CbW, EffSize: Integer;
  Txt:       string;
  TextColor: TTyColor;
  { Selection highlight }
  SelStyle:  TTyStyleSet;
  SelFill:   TTyFill;
  SegX1, SegX2: Integer;
  SegRect:   TRect;
  { Button area }
  UpR, DnR:  TRect;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);

    BtnW  := P.Scale(TyFieldButtonWidth);
    EffSize := ResolveFontSize(S);

    { Base text content rect: left padding to right minus button column }
    TextR := Rect(
      R.Left  + P.Scale(S.Padding.Left),
      R.Top   + P.Scale(S.Padding.Top),
      R.Right - BtnW,
      R.Bottom - P.Scale(S.Padding.Bottom));

    { ShowCheckBox: reserve space at the left and draw the checkbox glyph }
    CbW := 0;
    if FShowCheckBox then
    begin
      CbW := P.Scale(TyCheckBoxBox) + P.Scale(TyCheckBoxGap);
      CbR := CheckBoxRect(TextR, APPI);
      { Resolve checkbox style from TyCheckBox typeKey }
      if FChecked then
        CbS := ActiveController.Model.ResolveStyle('TyCheckBox', '', [tysActive])
      else
        CbS := ActiveController.Model.ResolveStyle('TyCheckBox', '', []);
      P.FillBackground(CbR, CbS.Background, CbS.BorderRadius);
      P.StrokeBorder(CbR, CbS.BorderRadius, CbS.BorderWidth, CbS.BorderColor);
      if FChecked then
        P.DrawGlyph(CbR, tgCheck, CbS.TextColor, 2);
      { Shift text rect right past the checkbox }
      TextR.Left := TextR.Left + CbW;
    end;

    { Determine text color: muted when inert (ShowCheckBox + not Checked) }
    TextColor := S.TextColor;
    if IsInert then
    begin
      { Resolve muted color from TyCheckBox :disabled or fall back to half-opacity }
      CbS := ActiveController.Model.ResolveStyle('TyCheckBox', '', [tysDisabled]);
      TextColor := CbS.TextColor;
    end;

    { Use buffer-display text: shows digit buffer content for active segment
      while the user is mid-entry, so no premature-clamp flicker. }
    Txt := ActiveSegDisplayText;

    { 1. Active-segment highlight (drawn BEFORE text so glyphs appear on top)
         Only when focused AND field is not inert. }
    if Focused and not IsInert and
       (FActiveSeg >= 0) and (FActiveSeg <= High(FSegments)) then
    begin
      SelStyle := ActiveController.Model.ResolveStyle('TyTextSelection', '', []);
      SelFill  := Default(TTyFill);
      SelFill.Kind  := tfkSolid;
      SelFill.Color := SelStyle.Background.Color;

      { Measure pixel x of segment start/end in the displayed text.
        Because we use the effective (normalized) format, every field is
        fixed-width: format character positions == rendered text positions,
        so StartCh/LenCh index directly into the rendered string. }
      SegX1 := TextR.Left + MeasureCharX(Txt, S.FontName,
                  FSegments[FActiveSeg].StartCh,
                  EffSize, S.FontWeight, APPI);
      SegX2 := TextR.Left + MeasureCharX(Txt, S.FontName,
                  FSegments[FActiveSeg].StartCh + FSegments[FActiveSeg].LenCh,
                  EffSize, S.FontWeight, APPI);
      if SegX2 <= SegX1 then SegX2 := SegX1 + P.Scale(8);  // degenerate guard
      SegRect := Rect(SegX1, TextR.Top, SegX2, TextR.Bottom);
      P.FillBackground(SegRect, SelFill, 0);
    end;

    { 2. Draw the formatted text }
    P.DrawText(TextR, Txt, S.FontName, EffSize, S.FontWeight,
      TextColor, taLeftJustify, tlCenter, False);

    { 3. Right-side button area }
    BtnR := TyDateTimeButtonRect(R, APPI);
    if FKind = dtkDate then
    begin
      P.DrawGlyph(BtnR, tgChevronDown, S.TextColor, 2);
    end
    else
    begin
      UpR := TyDateTimeUpButtonRect(R, APPI);
      DnR := TyDateTimeDownButtonRect(R, APPI);
      P.DrawGlyph(UpR,  tgArrowUp,   S.TextColor, 2);
      P.DrawGlyph(DnR,  tgArrowDown, S.TextColor, 2);
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

{ ── Keyboard ─────────────────────────────────────────────────────────────── }

procedure TTyDateTimePicker.KeyDown(var Key: Word; Shift: TShiftState);
var OldVal: TDateTime;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);

  { Escape: close dropdown if open, otherwise clear digit buffer }
  if Key = VK_ESCAPE then
  begin
    if (FPopup <> nil) and FPopup.IsOpen then
    begin
      CloseDropDown;
      Key := 0;
    end
    else
    begin
      FDigitBuffer := '';
      Invalidate; Key := 0;
    end;
    Exit;
  end;

  { Alt+Down or F4: toggle dropdown for dtkDate }
  if FKind = dtkDate then
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
  if IsInert then Exit;

  case Key of
    VK_LEFT:
      begin
        { Finalize any pending buffer before moving the cursor }
        OldVal := FDateTime;
        if FDigitBuffer <> '' then FinalizeBuffer(OldVal, False);
        if FActiveSeg > 0 then Dec(FActiveSeg);
        Invalidate; Key := 0;
      end;
    VK_RIGHT:
      begin
        OldVal := FDateTime;
        if FDigitBuffer <> '' then FinalizeBuffer(OldVal, False);
        if FActiveSeg < High(FSegments) then Inc(FActiveSeg);
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
  EffSize:  Integer;
  TextLeft: Integer;
  Txt:      string;
  Bmp:      TBGRABitmap;
  TextX:    Integer;
  CharIdx:  Integer;
  HitSeg:   Integer;
  TxtLen:   Integer;
  PaddingL: Integer;
  CbBoxR:   TRect;
  TextR:    TRect;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  FMouseDownOnButton := False;
  if Button = mbLeft then
  begin
    { ── Checkbox area click ─────────────────────────────────────────────── }
    if FShowCheckBox then
    begin
      S        := CurrentStyle;
      PaddingL := MulDiv(S.Padding.Left, Font.PixelsPerInch, 96);
      { Recompute text rect exactly as in RenderTo (without scale rounding diff) }
      TextR := Rect(
        PaddingL,
        MulDiv(S.Padding.Top, Font.PixelsPerInch, 96),
        ClientRect.Right - MulDiv(TyFieldButtonWidth, Font.PixelsPerInch, 96),
        ClientRect.Bottom - MulDiv(S.Padding.Bottom, Font.PixelsPerInch, 96));
      CbBoxR := CheckBoxRect(TextR, Font.PixelsPerInch);
      { Expand hit area slightly (easy to miss tiny box) }
      CbBoxR := Rect(CbBoxR.Left - 2, CbBoxR.Top - 2,
                     CbBoxR.Right + 2, CbBoxR.Bottom + 2);
      if PtInRect(CbBoxR, Point(X, Y)) then
      begin
        { Toggle Checked }
        FChecked := not FChecked;
        Invalidate;
        if Assigned(FOnChecked) then FOnChecked(Self);
        try
          if CanFocus then SetFocus;
        except
        end;
        Exit;
      end;
    end;

    { ── Button area click ───────────────────────────────────────────────── }
    if PtInRect(TyDateTimeButtonRect(ClientRect, Font.PixelsPerInch), Point(X, Y)) then
    begin
      if FKind = dtkDate then
      begin
        { Chevron pressed → remember it; the actual open happens in Click (so the
          mouse-up that follows MouseDown can't immediately deactivate-close the popup). }
        if not IsInert then
          FMouseDownOnButton := True;
      end
      else if (FKind = dtkTime) and not FReadOnly and not IsInert then
      begin
        if PtInRect(TyDateTimeUpButtonRect(ClientRect, Font.PixelsPerInch), Point(X, Y)) then
          StepActiveSeg(+1)
        else
          StepActiveSeg(-1);
      end;
    end
    else if not IsInert then
    begin
      { ── Segment hit-test ─────────────────────────────────────────────── }
      S        := CurrentStyle;
      EffSize  := ResolveFontSize(S);
      TextLeft := MulDiv(S.Padding.Left, Font.PixelsPerInch, 96);
      { If ShowCheckBox, add the checkbox+gap to the text left offset }
      if FShowCheckBox then
        Inc(TextLeft, MulDiv(TyCheckBoxBox + TyCheckBoxGap, Font.PixelsPerInch, 96));
      Txt      := FormattedText;
      TxtLen   := Length(Txt);

      { Convert click X to a character offset by finding the character
        whose right edge passes the click coordinate. }
      if (Txt <> '') and (TxtLen > 0) then
      begin
        Bmp := TBGRABitmap.Create(1, 1);
        try
          TyConfigureTextFont(Bmp, S.FontName, EffSize, S.FontWeight,
            Font.PixelsPerInch);
          TextX   := X - TextLeft;
          CharIdx := 0;
          while CharIdx < TxtLen do
          begin
            if Bmp.TextSize(Copy(Txt, 1, CharIdx + 1)).cx >= TextX then
              Break;
            Inc(CharIdx);
          end;
          HitSeg := TyDateTimeActiveSegAt(FSegments, CharIdx);
          if HitSeg >= 0 then
          begin
            FActiveSeg   := HitSeg;
            FDigitBuffer := '';
            Invalidate;
          end;
        finally
          Bmp.Free;
        end;
      end;
    end;

    try
      if CanFocus then SetFocus;
    except
    end;
  end;
end;

{ ── Property setters ─────────────────────────────────────────────────────── }

procedure TTyDateTimePicker.SetKind(AValue: TTyDateTimeKind);
begin
  if FKind = AValue then Exit;
  FKind := AValue;
  RebuildSegments;
  Invalidate;
end;

procedure TTyDateTimePicker.SetDateTime(AValue: TDateTime);
begin
  if (FMinDate <> 0) and (AValue < FMinDate) then AValue := FMinDate;
  if (FMaxDate <> 0) and (AValue > FMaxDate) then AValue := FMaxDate;
  if FDateTime = AValue then Exit;
  FDateTime := AValue;
  FDigitBuffer := '';
  if Assigned(FOnChange) then FOnChange(Self);
  Invalidate;
end;

procedure TTyDateTimePicker.SetDate(AValue: TDateTime);
begin
  { Keep the time part, replace only the date part }
  SetDateTime(Trunc(AValue) + Frac(FDateTime));
end;

function TTyDateTimePicker.GetDate: TDateTime;
begin
  Result := Trunc(FDateTime);
end;

procedure TTyDateTimePicker.SetTime(AValue: TDateTime);
begin
  { Keep the date part, replace only the time part }
  SetDateTime(Trunc(FDateTime) + Frac(AValue));
end;

function TTyDateTimePicker.GetTime: TDateTime;
begin
  Result := Frac(FDateTime);
end;

procedure TTyDateTimePicker.SetDateFormat(const AValue: string);
begin
  if FDateFormat = AValue then Exit;
  FDateFormat := AValue;
  if FKind = dtkDate then RebuildSegments;
  Invalidate;
end;

procedure TTyDateTimePicker.SetTimeFormat(const AValue: string);
begin
  if FTimeFormat = AValue then Exit;
  FTimeFormat := AValue;
  if FKind = dtkTime then RebuildSegments;
  Invalidate;
end;

procedure TTyDateTimePicker.SetMinDate(AValue: TDateTime);
begin
  if FMinDate = AValue then Exit;
  FMinDate := AValue;
  if (FMinDate <> 0) and (FDateTime < FMinDate) then SetDateTime(FMinDate);
  Invalidate;
end;

procedure TTyDateTimePicker.SetMaxDate(AValue: TDateTime);
begin
  if FMaxDate = AValue then Exit;
  FMaxDate := AValue;
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
  Invalidate;
end;

procedure TTyDateTimePicker.SetChecked(AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  Invalidate;
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
