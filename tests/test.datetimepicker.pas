unit test.datetimepicker;
{$mode objfpc}{$H+}
{
  Task C1 — pure-function tests for tyControls.DateTimePicker.

  All tests use a PINNED TFormatSettings built locally so the host locale
  never leaks.  No GUI, no file I/O.
}
interface

uses
  Classes, SysUtils, Types, DateUtils,
  fpcunit, testregistry,
  tyControls.DateTimePicker;

type
  { Tests for TyFormatDateTime, TyDateTimeSegments, TySegmentStep,
    TySegmentRange }
  TDateTimePickerPureTest = class(TTestCase)
  private
    FFmt: TFormatSettings;
  protected
    procedure SetUp; override;
  published
    { TyFormatDateTime }
    procedure TestFormatDate_yyyymmdd;
    procedure TestFormatTime_hhnnss;

    { TyDateTimeSegments — 'yyyy-mm-dd' }
    procedure TestSegments_DateFormat_Count;
    procedure TestSegments_DateFormat_Year;
    procedure TestSegments_DateFormat_Month;
    procedure TestSegments_DateFormat_Day;

    { TyDateTimeSegments — 'hh:nn:ss' }
    procedure TestSegments_TimeFormat_Count;
    procedure TestSegments_TimeFormat_Hour;
    procedure TestSegments_TimeFormat_Minute;
    procedure TestSegments_TimeFormat_Second;

    { m-after-h rule: 'hh:mm' → second segment is skMinute, NOT skMonth }
    procedure TestSegments_mAfterH_IsMinute;

    { 'mm/dd/yyyy' — leading m WITHOUT preceding h → skMonth }
    procedure TestSegments_mWithoutH_IsMonth;

    { TySegmentRange }
    procedure TestRange_Day;
    procedure TestRange_Month;
    procedure TestRange_Year;
    procedure TestRange_Hour;
    procedure TestRange_Minute;
    procedure TestRange_Second;
    procedure TestRange_AMPM;
    procedure TestRange_None_ReturnsFalse;

    { TySegmentStep — month roll }
    procedure TestStep_Month_Dec_Plus1_WrapsToJan_YearUnchanged;
    procedure TestStep_Month_Jan_Minus1_WrapsToDecYear_Unchanged;

    { TySegmentStep — hour roll }
    procedure TestStep_Hour_23_Plus1_WrapsTo0;
    procedure TestStep_Hour_0_Minus1_WrapsTo23;

    { TySegmentStep — day roll }
    procedure TestStep_Day_31_Plus1_WrapsTo1;

    { TySegmentStep — day clamped after month roll }
    procedure TestStep_Month_Roll_Day31_ClampsToMonthLength;
  end;

implementation

{ ── helpers ──────────────────────────────────────────────────────────────── }

{ Build a segment by scanning AFormat and returning the Nth result (0-based). }
function NthSegment(const AFormat: string; N: Integer): TTySegment;
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments(AFormat);
  if N > High(Segs) then
  begin
    Result.Kind    := skNone;
    Result.StartCh := -1;
    Result.LenCh   := 0;
  end
  else
    Result := Segs[N];
end;

{ ── SetUp ────────────────────────────────────────────────────────────────── }

procedure TDateTimePickerPureTest.SetUp;
begin
  { Pinned locale — deterministic across all machines. }
  FFmt := DefaultFormatSettings;   // start from the runtime struct so all
                                   // fields are initialised
  FFmt.DateSeparator      := '-';
  FFmt.TimeSeparator      := ':';
  FFmt.ShortDateFormat    := 'yyyy-mm-dd';
  FFmt.LongDateFormat     := 'yyyy-mm-dd';
  FFmt.ShortTimeFormat    := 'hh:nn:ss';
  FFmt.LongTimeFormat     := 'hh:nn:ss';
  FFmt.DecimalSeparator   := '.';
end;

{ ── TyFormatDateTime ─────────────────────────────────────────────────────── }

procedure TDateTimePickerPureTest.TestFormatDate_yyyymmdd;
begin
  AssertEquals('2026-03-07',
    TyFormatDateTime(EncodeDate(2026, 3, 7), 'yyyy-mm-dd', FFmt));
end;

procedure TDateTimePickerPureTest.TestFormatTime_hhnnss;
begin
  AssertEquals('14:05:09',
    TyFormatDateTime(EncodeTime(14, 5, 9, 0), 'hh:nn:ss', FFmt));
end;

{ ── TyDateTimeSegments: 'yyyy-mm-dd' ────────────────────────────────────── }

procedure TDateTimePickerPureTest.TestSegments_DateFormat_Count;
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments('yyyy-mm-dd');
  AssertEquals('segment count', 3, Length(Segs));
end;

procedure TDateTimePickerPureTest.TestSegments_DateFormat_Year;
var
  Seg: TTySegment;
begin
  Seg := NthSegment('yyyy-mm-dd', 0);
  AssertTrue('year kind', Seg.Kind = skYear);
  AssertEquals('year start', 0, Seg.StartCh);
  AssertEquals('year len', 4, Seg.LenCh);
end;

procedure TDateTimePickerPureTest.TestSegments_DateFormat_Month;
var
  Seg: TTySegment;
begin
  Seg := NthSegment('yyyy-mm-dd', 1);
  AssertTrue('month kind', Seg.Kind = skMonth);
  AssertEquals('month start', 5, Seg.StartCh);
  AssertEquals('month len', 2, Seg.LenCh);
end;

procedure TDateTimePickerPureTest.TestSegments_DateFormat_Day;
var
  Seg: TTySegment;
begin
  Seg := NthSegment('yyyy-mm-dd', 2);
  AssertTrue('day kind', Seg.Kind = skDay);
  AssertEquals('day start', 8, Seg.StartCh);
  AssertEquals('day len', 2, Seg.LenCh);
end;

{ ── TyDateTimeSegments: 'hh:nn:ss' ──────────────────────────────────────── }

procedure TDateTimePickerPureTest.TestSegments_TimeFormat_Count;
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments('hh:nn:ss');
  AssertEquals('segment count', 3, Length(Segs));
end;

procedure TDateTimePickerPureTest.TestSegments_TimeFormat_Hour;
var
  Seg: TTySegment;
begin
  Seg := NthSegment('hh:nn:ss', 0);
  AssertTrue('hour kind', Seg.Kind = skHour);
  AssertEquals('hour start', 0, Seg.StartCh);
  AssertEquals('hour len', 2, Seg.LenCh);
end;

procedure TDateTimePickerPureTest.TestSegments_TimeFormat_Minute;
var
  Seg: TTySegment;
begin
  Seg := NthSegment('hh:nn:ss', 1);
  AssertTrue('minute kind', Seg.Kind = skMinute);
  AssertEquals('minute start', 3, Seg.StartCh);
  AssertEquals('minute len', 2, Seg.LenCh);
end;

procedure TDateTimePickerPureTest.TestSegments_TimeFormat_Second;
var
  Seg: TTySegment;
begin
  Seg := NthSegment('hh:nn:ss', 2);
  AssertTrue('second kind', Seg.Kind = skSecond);
  AssertEquals('second start', 6, Seg.StartCh);
  AssertEquals('second len', 2, Seg.LenCh);
end;

{ ── m-after-h rule ───────────────────────────────────────────────────────── }

procedure TDateTimePickerPureTest.TestSegments_mAfterH_IsMinute;
{ 'hh:mm' — 'mm' immediately follows 'hh' (separated only by ':') → skMinute }
var
  Seg: TTySegment;
begin
  Seg := NthSegment('hh:mm', 1);
  AssertTrue('hh:mm second seg is skMinute', Seg.Kind = skMinute);
end;

procedure TDateTimePickerPureTest.TestSegments_mWithoutH_IsMonth;
{ 'mm/dd/yyyy' — 'mm' has no preceding 'h' run → skMonth }
var
  Seg: TTySegment;
begin
  Seg := NthSegment('mm/dd/yyyy', 0);
  AssertTrue('mm/dd/yyyy first seg is skMonth', Seg.Kind = skMonth);
end;

{ ── TySegmentRange ───────────────────────────────────────────────────────── }

procedure TDateTimePickerPureTest.TestRange_Day;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skDay; Seg.StartCh := 0; Seg.LenCh := 2;
  AssertTrue(TySegmentRange(Seg, AMin, AMax));
  AssertEquals('day min', 1,  AMin);
  AssertEquals('day max', 31, AMax);
end;

procedure TDateTimePickerPureTest.TestRange_Month;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skMonth; Seg.StartCh := 0; Seg.LenCh := 2;
  AssertTrue(TySegmentRange(Seg, AMin, AMax));
  AssertEquals('month min', 1,  AMin);
  AssertEquals('month max', 12, AMax);
end;

procedure TDateTimePickerPureTest.TestRange_Year;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skYear; Seg.StartCh := 0; Seg.LenCh := 4;
  AssertTrue(TySegmentRange(Seg, AMin, AMax));
  AssertEquals('year min', 1,    AMin);
  AssertEquals('year max', 9999, AMax);
end;

procedure TDateTimePickerPureTest.TestRange_Hour;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skHour; Seg.StartCh := 0; Seg.LenCh := 2;
  AssertTrue(TySegmentRange(Seg, AMin, AMax));
  AssertEquals('hour min', 0,  AMin);
  AssertEquals('hour max', 23, AMax);
end;

procedure TDateTimePickerPureTest.TestRange_Minute;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skMinute; Seg.StartCh := 0; Seg.LenCh := 2;
  AssertTrue(TySegmentRange(Seg, AMin, AMax));
  AssertEquals('minute min', 0,  AMin);
  AssertEquals('minute max', 59, AMax);
end;

procedure TDateTimePickerPureTest.TestRange_Second;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skSecond; Seg.StartCh := 0; Seg.LenCh := 2;
  AssertTrue(TySegmentRange(Seg, AMin, AMax));
  AssertEquals('second min', 0,  AMin);
  AssertEquals('second max', 59, AMax);
end;

procedure TDateTimePickerPureTest.TestRange_AMPM;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skAMPM; Seg.StartCh := 0; Seg.LenCh := 5;
  AssertTrue(TySegmentRange(Seg, AMin, AMax));
  AssertEquals('ampm min', 0, AMin);
  AssertEquals('ampm max', 1, AMax);
end;

procedure TDateTimePickerPureTest.TestRange_None_ReturnsFalse;
var
  AMin, AMax: Integer;
  Seg: TTySegment;
begin
  Seg.Kind := skNone; Seg.StartCh := 0; Seg.LenCh := 0;
  AssertFalse(TySegmentRange(Seg, AMin, AMax));
end;

{ ── TySegmentStep ────────────────────────────────────────────────────────── }

procedure TDateTimePickerPureTest.TestStep_Month_Dec_Plus1_WrapsToJan_YearUnchanged;
{ 2026-12-15 → month +1 → 2026-01-15 (year unchanged: no-carry rule) }
var
  Segs: TTySegmentArray;
  Before, After: TDateTime;
  Y, M, D, H, Min, S, MS: Word;
begin
  Segs   := TyDateTimeSegments('yyyy-mm-dd');
  Before := EncodeDate(2026, 12, 15);
  After  := TySegmentStep(Before, Segs[1], +1);   // Segs[1] = month segment
  DecodeDateTime(After, Y, M, D, H, Min, S, MS);
  AssertEquals('year unchanged', 2026, Integer(Y));
  AssertEquals('month wraps to Jan', 1, Integer(M));
  AssertEquals('day unchanged', 15, Integer(D));
end;

procedure TDateTimePickerPureTest.TestStep_Month_Jan_Minus1_WrapsToDecYear_Unchanged;
{ 2026-01-15 → month -1 → 2026-12-15 (year unchanged) }
var
  Segs: TTySegmentArray;
  Before, After: TDateTime;
  Y, M, D, H, Min, S, MS: Word;
begin
  Segs   := TyDateTimeSegments('yyyy-mm-dd');
  Before := EncodeDate(2026, 1, 15);
  After  := TySegmentStep(Before, Segs[1], -1);
  DecodeDateTime(After, Y, M, D, H, Min, S, MS);
  AssertEquals('year unchanged', 2026, Integer(Y));
  AssertEquals('month wraps to Dec', 12, Integer(M));
  AssertEquals('day unchanged', 15, Integer(D));
end;

procedure TDateTimePickerPureTest.TestStep_Hour_23_Plus1_WrapsTo0;
{ 23:30 → hour +1 → 00:30 }
var
  Segs: TTySegmentArray;
  Before, After: TDateTime;
  Y, M, D, H, Min, S, MS: Word;
begin
  Segs   := TyDateTimeSegments('hh:nn:ss');
  Before := EncodeDateTime(2026, 6, 1, 23, 30, 0, 0);
  After  := TySegmentStep(Before, Segs[0], +1);   // Segs[0] = hour
  DecodeDateTime(After, Y, M, D, H, Min, S, MS);
  AssertEquals('hour wraps to 0', 0, Integer(H));
  AssertEquals('minute unchanged', 30, Integer(Min));
end;

procedure TDateTimePickerPureTest.TestStep_Hour_0_Minus1_WrapsTo23;
{ 00:30 → hour -1 → 23:30 }
var
  Segs: TTySegmentArray;
  Before, After: TDateTime;
  Y, M, D, H, Min, S, MS: Word;
begin
  Segs   := TyDateTimeSegments('hh:nn:ss');
  Before := EncodeDateTime(2026, 6, 1, 0, 30, 0, 0);
  After  := TySegmentStep(Before, Segs[0], -1);
  DecodeDateTime(After, Y, M, D, H, Min, S, MS);
  AssertEquals('hour wraps to 23', 23, Integer(H));
end;

procedure TDateTimePickerPureTest.TestStep_Day_31_Plus1_WrapsTo1;
{ Day 31 + 1 → Day 1 (roll within field, month unchanged) }
var
  Segs: TTySegmentArray;
  Before, After: TDateTime;
  Y, M, D, H, Min, S, MS: Word;
begin
  Segs   := TyDateTimeSegments('yyyy-mm-dd');
  Before := EncodeDate(2026, 1, 31);   // January has 31 days
  After  := TySegmentStep(Before, Segs[2], +1);   // Segs[2] = day
  DecodeDateTime(After, Y, M, D, H, Min, S, MS);
  AssertEquals('month unchanged', 1, Integer(M));
  AssertEquals('day wraps to 1', 1, Integer(D));
end;

procedure TDateTimePickerPureTest.TestStep_Month_Roll_Day31_ClampsToMonthLength;
{ 2026-01-31 → month +1 → 2026-02-28 (Feb has 28 days in 2026 — clamp) }
var
  Segs: TTySegmentArray;
  Before, After: TDateTime;
  Y, M, D, H, Min, S, MS: Word;
begin
  Segs   := TyDateTimeSegments('yyyy-mm-dd');
  Before := EncodeDate(2026, 1, 31);
  After  := TySegmentStep(Before, Segs[1], +1);   // month +1: Jan → Feb
  DecodeDateTime(After, Y, M, D, H, Min, S, MS);
  AssertEquals('year unchanged', 2026, Integer(Y));
  AssertEquals('month is Feb', 2, Integer(M));
  AssertEquals('day clamped to 28', 28, Integer(D));
end;

initialization
  RegisterTest(TDateTimePickerPureTest);

end.
