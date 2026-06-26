unit tyControls.DateTimePicker;
{$mode objfpc}{$H+}
{
  tyControls.DateTimePicker — pure-function section (Task C1).

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
}

interface

uses
  Classes, SysUtils, Types, DateUtils;

type
  TTyDateTimeKind = (dtkDate, dtkTime);

  TTySegKind = (skNone, skDay, skMonth, skYear, skHour, skMinute, skSecond, skAMPM);

  { Describes one editable segment inside a formatted date/time string.
    StartCh and LenCh are 0-based character indices into the FORMAT template
    (not the rendered value), so the picker can highlight the right span. }
  TTySegment = record
    Kind:    TTySegKind;
    StartCh: Integer;   // 0-based start in the format string
    LenCh:   Integer;   // number of format characters in this segment
  end;

  TTySegmentArray = array of TTySegment;

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

implementation

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

end.
