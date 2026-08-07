unit test.datetimepicker;
{$mode objfpc}{$H+}
{
  Task C1 — pure-function tests for tyControls.DateTimePicker.
  Task C2 — control tests: probe + synthetic keys, segment editing, pixel test.
  Task C3 — dropdown/spin/ShowCheckBox wiring tests.

  All tests use a PINNED TFormatSettings built locally so the host locale
  never leaks.  No GUI, no file I/O for the pure tests.
}
interface

uses
  Classes, SysUtils, Types, DateUtils, Math, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.DefaultTheme, tyControls.DateTimePicker, tyControls.Calendar;

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

    { TyEffectiveFormat — single letter normalization }
    procedure TestEffectiveFormat_SingleM_Doubled;
    procedure TestEffectiveFormat_SingleD_Doubled;
    procedure TestEffectiveFormat_SingleH_Doubled;
    procedure TestEffectiveFormat_yyyy_Unchanged;
    procedure TestEffectiveFormat_DoubleAlreadyDouble;
    procedure TestEffectiveFormat_MixedSingleAndDouble;
  end;

  { Task C2 — TyDateTimeActiveSegAt pure helper }
  TDateTimeActiveSegAtTest = class(TTestCase)
  published
    procedure TestHitsFirstSegment;
    procedure TestHitsSecondSegment;
    procedure TestHitsThirdSegment;
    procedure TestMissReturnsMinusOne;
    procedure TestSeparatorReturnsMinusOne;
    procedure TestEmptyArrayReturnsMinusOne;
  end;

  { Probe subclass: exposes protected RenderTo + input handlers for tests }
  TTyDateTimePickerProbe = class(TTyDateTimePicker)
  public
    procedure RenderToForTest(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimKeyDown(var Key: Word);
    procedure SimKeyPress(const C: TUTF8Char);
    procedure SimDoExit;
    function  ActiveSegForTest: Integer;
    function  DateTimeForTest: TDateTime;
    function  DigitBufferForTest: string;
    { The click the user would make, and — from the SAME layout call the paint uses —
      where field AIndex is actually painted. A test that asks the first and checks it
      against the second is the only thing that can catch the paint and the hit test
      drifting apart, which is what shipped the month-name bug. }
    procedure SimMouseDown(X, Y: Integer);
    { Draw one frame into a throwaway bitmap so the Painted* record is current. }
    procedure RenderOffscreen;
    function  PaintedSegSpan(AIndex: Integer; out AX1, AX2: Integer): Boolean;
    function  RectsForTest: TTyDateTimeRects;
    { The string the field would DRAW, out of the same call the paint uses -- so a test
      that asserts what an empty field shows is reading the paint's own answer and not a
      second formatter written for the test. }
    function  DisplayTextForTest: string;
    function  OriginXForTest: Integer;
    procedure SimKeyDownWith(var Key: Word; Shift: TShiftState);
  end;

  { The field's horizontal layout — the one source (TyDateTimeRects) and the join it
    exists to hold: the paint and the click hit-test reading their x out of it.
    Declared after the probe because it drives one. }
  TDateTimeLayoutTest = class(TTestCase)
  private
    { Click AX and require field AIndex to come back. Parks the active field elsewhere
      first: a click that resolves to NO field leaves the active one untouched, so
      without the parking a miss would read as a hit whenever the field happened to be
      selected already. Probes the span's INNER EDGES, not just its middle -- a
      middle-only assertion survives any drift narrower than half a field, which is
      every drift that has actually happened here. }
    procedure AssertClickSelects(P: TTyDateTimePickerProbe; AIndex, AX: Integer;
      const AWhere: string);
    procedure AssertPaintedFieldsAnswerTheirOwnClicks(P: TTyDateTimePickerProbe;
      const AContext: string);
  published
    { The pure tiling, no fonts involved. }
    procedure TestTextBoxClearsPaddingAndButton;
    procedure TestNoButtonLeavesTheRectsEmpty;
    procedure TestCheckBoxShiftsTextByItsOwnColumn;
    procedure TestCheckBoxColumnScalesItsTwoTermsSeparately;
    procedure TestSpinHalvesTileTheButtonColumn;
    { Paint and hit-test must agree — the assertion the two sites cannot both pass
      while they disagree. }
    procedure TestClickInThePaintedFieldSelectsThatField;
    procedure TestClickInThePaintedFieldSelectsThatFieldRightAligned;
    procedure TestCheckBoxColumnMovesThePaintedFieldsAndTheClicks;
  end;

  TChangeCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  { The empty value. Two classes of assertion live here and they fail differently:
    the PURE ones pin what "null" means, and the CONTROL ones pin that every write
    path agrees about it. The second set is the whole cost of this feature -- a
    control that accepts null through one door and quietly hands back a real date
    through another is worse than one that cannot express null at all, because the
    caller has no way to know which door it just used. }
  TDateTimeNullTest = class(TTestCase)
  private
    FPicker: TTyDateTimePickerProbe;
    FChanges: Integer;
    procedure CountChange(Sender: TObject);
    { Press AKey and report nothing -- the shift-less path every guard below uses. }
    procedure Press(AKey: Word);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ── what null IS ── }
    procedure NullIsARangeNotABitPattern;
    procedure EqualDateTimeTreatsTwoUnequalNullsAsEqual;
    { ── every write path ── }
    procedure TheProgrammaticSetterKeepsTheValueEmpty;
    procedure TighteningMaxDateDoesNotFillAnEmptyField;
    procedure TighteningMinDateDoesNotFillAnEmptyField;
    procedure LosingFocusDoesNotFillAnEmptyField;
    procedure AnUndoRestoresEmptinessRatherThanADate;
    procedure DateAndTimeReadBackEmptyRatherThanGarbage;
    procedure WritingTheDatePartOfAnEmptyFieldDoesNotComposeAgainstGarbage;
    procedure WritingTheTimePartOfAnEmptyFieldLandsOnARealDay;
    { ── what the user sees and can do ── }
    procedure AnEmptyFieldShowsTextForNullDate;
    procedure AnEmptyFieldHasNoSegmentToHighlight;
    procedure AnEmptyFieldStillMovesBetweenItsFields;
    procedure TypingIntoAnEmptyFieldMaterialisesADate;
    procedure SteppingAnEmptyFieldMaterialisesADate;
    procedure TheTypedDigitsShowWhileTheFieldIsStillEmpty;
    { ── the keys that reach it ── }
    procedure TheNullKeyEmptiesTheFieldAndAnnouncesIt;
    procedure DeleteEmptiesTheFieldToo;
    procedure NullInputAllowedFalseClosesTheKeyNotTheProperty;
    procedure ReadOnlyRefusesTheNullKey;
    procedure AnInertFieldRefusesTheNullKey;
    { ── the parts that measure and seed ── }
    procedure PreferredWidthBudgetsForTheLongerOfTheTwoStrings;
    procedure TheDropdownSeedsFromASeedDateWhenTheFieldIsEmpty;
    { ── streaming ── }
    procedure AnEmptyValueSurvivesAnLfmRoundTrip;
    procedure ADateStreamedBeforeItsBoundsStillLoads;
  end;

  { Control behavior tests (no real window needed) }
  TDateTimePickerControlTest = class(TTestCase)
  private
    FPicker: TTyDateTimePickerProbe;
    FCounter: TChangeCounter;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypingDigitsIntoYearUpdatesDateTime;
    procedure TestUpOnMonthStepsItRollsNoCarry;
    procedure TestRightLeftMoveActiveSeg;
    procedure TestCommitClampsToMaxDate;
    procedure TestProgrammaticWriteFiresOnChangeOnlyWithTheOption;
    procedure TestHomeGoesToFirstSeg;
    procedure TestEndGoesToLastSeg;

    { New tests for review fixes }
    procedure TestReadOnly_BlocksDigitEntry;
    procedure TestReadOnly_BlocksStepUp;
    procedure TestReadOnly_BlocksWheel;
    procedure TestReadOnly_NoOnChange;
    procedure TestAutoAdvance_ValueBranch_Typing3InMonth;
    procedure TestStepPastMaxDate_Clamps;
    procedure TestLeadingZero_BufferDisplayed_NoImmediateWrite;
    procedure TestLeadingZero_ThenDigit_CommitsCorrectMonth;
  end;

  { Pixel / render test }
  TDateTimePickerPixelTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
  published
    procedure TestActiveSegmentHighlightPresent;
    procedure TestButtonGlyphPresent_dtkDate;
    procedure TestButtonGlyphPresent_dtkTime;
  end;

  { Task C3: extended probe that exposes additional test seams.
    Extends TTyDateTimePickerProbe so SimKeyDown/SimKeyPress are inherited. }
  TTyDateTimePickerProbeC3 = class(TTyDateTimePickerProbe)
  public
    { Ensure the lazy popup+calendar are created (calls protected EnsurePopup). }
    procedure EnsurePopupForTest;
    { Everything OpenDropDown does to the calendar BEFORE it needs a screen -- which is
      the half that can raise. Showing the popup itself needs a real window and is out of
      reach headlessly, so the seeding lives in its own method for this to call. }
    procedure SeedPopupCalendarForTest;
    { Simulate a CalendarAccepted call for headless testing.
      Seeds the internal FCalendar with ADate then calls the accept handler. }
    procedure SimCalendarAccept(ADate: TDateTime);
    { Simulate a mouse-down on the up spin button for dtkTime testing.
      Calls StepActiveSeg(+1) directly. }
    procedure SimSpinUp;
    { Simulate a mouse-down on the down spin button for dtkTime testing. }
    procedure SimSpinDown;
    { Simulate toggling the ShowCheckBox (as if the user clicked it). }
    procedure SimToggleCheckBox;
  end;

  { Task C3: dropdown wiring + ShowCheckBox tests }
  TDateTimePickerC3Test = class(TTestCase)
  private
    FPicker:    TTyDateTimePickerProbeC3;
    FChangeCount: Integer;
    FCloseUpCount: Integer;
    FCheckedCount: Integer;
    procedure OnChange(Sender: TObject);
    procedure OnCloseUp(Sender: TObject);
    procedure OnChecked(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { dtkDate CalendarAccepted: DateTime date-part updates + OnChange fires +
      OnCloseUp fires + DroppedDown becomes False. }
    procedure TestCalendarAccept_UpdatesDateAndFiresEvents;
    { dtkDate CalendarAccepted: time-part of DateTime is preserved. }
    procedure TestCalendarAccept_PreservesTimePart;
    { dtkTime spin-up steps the active segment (assert DateTime changed). }
    procedure TestSpinUp_StepsActiveSeg;
    { dtkTime spin-down steps the active segment in the other direction. }
    procedure TestSpinDown_StepsActiveSeg;
    { ShowCheckBox=True, Checked=False: digit key does NOT change DateTime. }
    procedure TestInert_DigitDoesNotChangeDateTime;
    { ShowCheckBox=True, Checked=False: step does NOT change DateTime. }
    procedure TestInert_StepDoesNotChangeDateTime;
    { ShowCheckBox=True, Checked=False: no OnChange fired. }
    procedure TestInert_NoOnChangeFired;
    { ShowCheckBox=True, Checked=False → toggle → Checked becomes True
      and OnChecked fires. }
    procedure TestCheckBoxToggle_FiresOnChecked_FlipsChecked;
    { After toggling Checked, editing is re-enabled (digit key works). }
    procedure TestCheckBoxToggle_ReEnablesEditing;
    { REGRESSION: a picker themed via the global default has Controller=nil; opening
      the dropdown used to deref FCalendar.Controller.Model -> AV. EnsurePopup must
      give the calendar a non-nil (ActiveController) controller. }
    procedure TestDropDownNilControllerNoCrash;
  end;

  { Month & weekday names in the FIELD TEXT follow TyDateTimeNames (the
    app-language seam in tyControls.Calendar), not raw DefaultFormatSettings.
    The precedence machinery itself is tested beside the seam in test.calendar;
    here the two tiers are FORCED and the assertions read the control's own
    output -- FormattedText and the preferred width -- so a BuildDisplay or
    CalculatePreferredSize still passing DefaultFormatSettings goes red. }
  TDateTimePickerNameSourceTest = class(TTestCase)
  private
    FSavedSource: TTyDateTimeNameSource;
    FSavedFmt: TFormatSettings;
    FPicker: TTyDateTimePickerProbe;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheFieldTextFollowsTheForcedTranslationTier;
    procedure TheFieldTextFollowsTheForcedLocaleTier;
    procedure ThePreferredWidthMeasuresTheSameNamesTheFieldRenders;
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

{ ── TyEffectiveFormat ────────────────────────────────────────────────────── }

procedure TDateTimePickerPureTest.TestEffectiveFormat_SingleM_Doubled;
{ A lone 'm' in a format string should become 'mm'. }
begin
  AssertEquals('m→mm', 'mm/dd/yyyy', TyEffectiveFormat('m/d/yyyy'));
end;

procedure TDateTimePickerPureTest.TestEffectiveFormat_SingleD_Doubled;
begin
  AssertEquals('d→dd in m/d/yyyy', 'mm/dd/yyyy', TyEffectiveFormat('m/d/yyyy'));
end;

procedure TDateTimePickerPureTest.TestEffectiveFormat_SingleH_Doubled;
{ 'h:n:s' → 'hh:nn:ss' }
begin
  AssertEquals('h:n:s→hh:nn:ss', 'hh:nn:ss', TyEffectiveFormat('h:n:s'));
end;

procedure TDateTimePickerPureTest.TestEffectiveFormat_yyyy_Unchanged;
{ yyyy must not become yyyyyyyy }
begin
  AssertEquals('yyyy unchanged', 'yyyy-mm-dd', TyEffectiveFormat('yyyy-mm-dd'));
end;

procedure TDateTimePickerPureTest.TestEffectiveFormat_DoubleAlreadyDouble;
{ mm/dd/yyyy: already doubled — must not triple }
begin
  AssertEquals('mm/dd/yyyy unchanged', 'mm/dd/yyyy', TyEffectiveFormat('mm/dd/yyyy'));
end;

procedure TDateTimePickerPureTest.TestEffectiveFormat_MixedSingleAndDouble;
{ 'hh:n:ss' — only 'n' is single → becomes 'hh:nn:ss' }
begin
  AssertEquals('hh:n:ss → hh:nn:ss', 'hh:nn:ss', TyEffectiveFormat('hh:n:ss'));
end;

{ ── TyDateTimeActiveSegAt ────────────────────────────────────────────────── }

procedure TDateTimeActiveSegAtTest.TestHitsFirstSegment;
{ 'yyyy-mm-dd': seg0 = StartCh=0, LenCh=4 → chars 0..3 }
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments('yyyy-mm-dd');
  AssertEquals('char 0 → seg 0', 0, TyDateTimeActiveSegAt(Segs, 0));
  AssertEquals('char 3 → seg 0', 0, TyDateTimeActiveSegAt(Segs, 3));
end;

procedure TDateTimeActiveSegAtTest.TestHitsSecondSegment;
{ seg1 = StartCh=5, LenCh=2 → chars 5..6 }
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments('yyyy-mm-dd');
  AssertEquals('char 5 → seg 1', 1, TyDateTimeActiveSegAt(Segs, 5));
  AssertEquals('char 6 → seg 1', 1, TyDateTimeActiveSegAt(Segs, 6));
end;

procedure TDateTimeActiveSegAtTest.TestHitsThirdSegment;
{ seg2 = StartCh=8, LenCh=2 → chars 8..9 }
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments('yyyy-mm-dd');
  AssertEquals('char 8 → seg 2', 2, TyDateTimeActiveSegAt(Segs, 8));
  AssertEquals('char 9 → seg 2', 2, TyDateTimeActiveSegAt(Segs, 9));
end;

procedure TDateTimeActiveSegAtTest.TestMissReturnsMinusOne;
{ char 10 is beyond the last segment in 'yyyy-mm-dd' (len=10, chars 0..9) }
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments('yyyy-mm-dd');
  AssertEquals('char 10 → -1', -1, TyDateTimeActiveSegAt(Segs, 10));
end;

procedure TDateTimeActiveSegAtTest.TestSeparatorReturnsMinusOne;
{ char 4 is the first '-' separator in 'yyyy-mm-dd' → not in any segment }
var
  Segs: TTySegmentArray;
begin
  Segs := TyDateTimeSegments('yyyy-mm-dd');
  AssertEquals('separator char 4 → -1', -1, TyDateTimeActiveSegAt(Segs, 4));
end;

procedure TDateTimeActiveSegAtTest.TestEmptyArrayReturnsMinusOne;
var
  Segs: TTySegmentArray;
begin
  Segs := nil;
  AssertEquals('empty segs → -1', -1, TyDateTimeActiveSegAt(Segs, 0));
end;

{ ── TTyDateTimePickerProbe ───────────────────────────────────────────────── }

procedure TTyDateTimePickerProbe.RenderToForTest(ACanvas: TCanvas;
  const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyDateTimePickerProbe.SimKeyDown(var Key: Word);
var Sh: TShiftState;
begin
  Sh := [];
  KeyDown(Key, Sh);
end;

procedure TTyDateTimePickerProbe.SimKeyPress(const C: TUTF8Char);
var K: TUTF8Char;
begin
  K := C;
  UTF8KeyPress(K);
end;

procedure TTyDateTimePickerProbe.SimDoExit;
begin
  DoExit;
end;

function TTyDateTimePickerProbe.ActiveSegForTest: Integer;
begin
  Result := ActiveSeg;
end;

function TTyDateTimePickerProbe.DateTimeForTest: TDateTime;
begin
  Result := DateTime;
end;

function TTyDateTimePickerProbe.DigitBufferForTest: string;
begin
  Result := DigitBuffer;
end;

procedure TTyDateTimePickerProbe.SimMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

{ Every "where is it painted" query below RENDERS FIRST and then reads what the render
  wrote down (TTyDateTimePicker.Painted*). Calling FieldLayout here instead would be
  asking the HIT TEST's own source where the paint went -- a tautology that stays green
  through the one change these tests exist to catch, a paint that mirrors while the hit
  test does not. Verified by mutation: that change leaves this file green when the probe
  re-derives, and turns it red when the probe reads the render. }
procedure TTyDateTimePickerProbe.RenderOffscreen;
var
  Host: TBitmap;
  R: TRect;
begin
  R := ClientRect;
  if R.Right <= R.Left then R.Right := R.Left + 1;
  if R.Bottom <= R.Top then R.Bottom := R.Top + 1;
  Host := TBitmap.Create;
  try
    Host.PixelFormat := pf32bit;
    Host.SetSize(R.Right - R.Left, R.Bottom - R.Top);
    RenderTo(Host.Canvas, R, Font.PixelsPerInch);
  finally
    Host.Free;
  end;
end;

function TTyDateTimePickerProbe.PaintedSegSpan(AIndex: Integer;
  out AX1, AX2: Integer): Boolean;
var
  S:       TTyStyleSet;
  EffSize: Integer;
begin
  RenderOffscreen;
  S       := CurrentStyle;
  EffSize := ResolveFontSize(S);
  Result  := SegmentSpanX(PaintedText, PaintedSpans, PaintedOriginX, AIndex,
               S.FontName, EffSize, S.FontWeight, Font.PixelsPerInch, AX1, AX2);
end;

function TTyDateTimePickerProbe.RectsForTest: TTyDateTimeRects;
begin
  RenderOffscreen;
  Result := PaintedRects;
end;

function TTyDateTimePickerProbe.DisplayTextForTest: string;
begin
  RenderOffscreen;
  Result := PaintedText;
end;

function TTyDateTimePickerProbe.OriginXForTest: Integer;
begin
  RenderOffscreen;
  Result := PaintedOriginX;
end;

procedure TTyDateTimePickerProbe.SimKeyDownWith(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

{ ── TChangeCounter ───────────────────────────────────────────────────────── }

procedure TChangeCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ ── TDateTimePickerControlTest SetUp / TearDown ─────────────────────────── }

procedure TDateTimePickerControlTest.SetUp;
begin
  FPicker  := TTyDateTimePickerProbe.Create(nil);
  FCounter := TChangeCounter.Create;
  FPicker.Font.PixelsPerInch := 96;
  { Use a fixed format so tests are locale-independent }
  FPicker.Kind       := dtkDate;
  FPicker.DateFormat := 'yyyy-mm-dd';
  FPicker.DateTime   := EncodeDate(2026, 6, 15);
  FPicker.OnChange   := @FCounter.Handle;
  FCounter.Count     := 0;  // reset after the DateTime assignment above
end;

procedure TDateTimePickerControlTest.TearDown;
begin
  FCounter.Free;
  FPicker.Free;
end;

{ ── Control behavior tests ───────────────────────────────────────────────── }

procedure TDateTimePickerControlTest.TestTypingDigitsIntoYearUpdatesDateTime;
{ Picker at 2026-06-15, active seg = 0 (year).
  Type '2', '0', '2', '7' → year should become 2027.
  The year segment is 4 digits, auto-advances after 4. }
var
  Y, M, D, H, Mi, S, MS: Word;
begin
  FPicker.DateTime := EncodeDate(2026, 6, 15);
  FCounter.Count   := 0;
  { Ensure seg 0 = year }
  AssertEquals('seg 0 is year', Ord(skYear), Ord(FPicker.Segments[0].Kind));
  FPicker.SimKeyPress('2');
  FPicker.SimKeyPress('0');
  FPicker.SimKeyPress('2');
  FPicker.SimKeyPress('7');
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('year updated to 2027', 2027, Integer(Y));
  AssertEquals('month preserved', 6, Integer(M));
  AssertTrue('OnChange fired at least once', FCounter.Count >= 1);
end;

procedure TDateTimePickerControlTest.TestUpOnMonthStepsItRollsNoCarry;
{ Picker at 2026-12-15, active seg = 1 (month).
  VK_UP → month should roll to 1 (Jan), year stays 2026. }
var
  Key: Word;
  Y, M, D, H, Mi, S, MS: Word;
begin
  FPicker.DateTime := EncodeDate(2026, 12, 15);
  FCounter.Count   := 0;
  { Move to month segment }
  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  AssertEquals('now at seg 1', 1, FPicker.ActiveSegForTest);
  Key := VK_UP;
  FPicker.SimKeyDown(Key);
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('year unchanged (no carry)', 2026, Integer(Y));
  AssertEquals('month rolled to Jan', 1, Integer(M));
  AssertEquals('day unchanged', 15, Integer(D));
  AssertTrue('OnChange fired', FCounter.Count >= 1);
end;

procedure TDateTimePickerControlTest.TestRightLeftMoveActiveSeg;
var Key: Word;
begin
  { Start at seg 0 }
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  AssertEquals('start at 0', 0, FPicker.ActiveSegForTest);

  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  AssertEquals('right → seg 1', 1, FPicker.ActiveSegForTest);

  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  AssertEquals('right → seg 2', 2, FPicker.ActiveSegForTest);

  { Right at last should not wrap }
  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  AssertEquals('right at last stays at 2', 2, FPicker.ActiveSegForTest);

  Key := VK_LEFT;
  FPicker.SimKeyDown(Key);
  AssertEquals('left → seg 1', 1, FPicker.ActiveSegForTest);
end;

procedure TDateTimePickerControlTest.TestCommitClampsToMaxDate;
{ Set MaxDate, then assign a date beyond it; DateTime should clamp. }
var
  Y, M, D, H, Mi, S, MS: Word;
begin
  FPicker.MaxDate := EncodeDate(2025, 12, 31);
  FPicker.DateTime := EncodeDate(2026, 6, 15);   // beyond max → should clamp
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('year clamped to 2025', 2025, Integer(Y));
  AssertEquals('month clamped to 12', 12, Integer(M));
  AssertEquals('day clamped to 31', 31, Integer(D));
end;

{ RENAMED from TestOnChangeFiredOnlyOnRealChange, which asserted that a PROGRAMMATIC
  DateTime write fires OnChange -- the behaviour this pass removed. It was green for
  years and it was pinning the defect: `DTP.DateTime := Rec.Due` re-entered the
  application's own handler. OnChange now means "the user changed it" unless
  dtpoDoChangeOnSetDateTime says otherwise, so the test asserts both halves. }
procedure TDateTimePickerControlTest.TestProgrammaticWriteFiresOnChangeOnlyWithTheOption;
begin
  FPicker.DateTime := EncodeDate(2026, 6, 15);
  FCounter.Count := 0;
  { Default Options: a code write is silent, whether or not the value moved. }
  FPicker.DateTime := EncodeDate(2026, 6, 15);
  AssertEquals('same value: no OnChange', 0, FCounter.Count);
  FPicker.DateTime := EncodeDate(2026, 6, 16);
  AssertEquals('different value, no option: still no OnChange', 0, FCounter.Count);
  { Opt in and the old behaviour is back -- still only on a real change. }
  FPicker.Options := [dtpoDoChangeOnSetDateTime];
  FPicker.DateTime := EncodeDate(2026, 6, 16);
  AssertEquals('same value with the option: no OnChange', 0, FCounter.Count);
  FPicker.DateTime := EncodeDate(2026, 6, 17);
  AssertEquals('different value with the option: OnChange once', 1, FCounter.Count);
end;

procedure TDateTimePickerControlTest.TestHomeGoesToFirstSeg;
var Key: Word;
begin
  Key := VK_RIGHT; FPicker.SimKeyDown(Key);
  Key := VK_RIGHT; FPicker.SimKeyDown(Key);
  AssertEquals('now at seg 2', 2, FPicker.ActiveSegForTest);
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  AssertEquals('Home → seg 0', 0, FPicker.ActiveSegForTest);
end;

procedure TDateTimePickerControlTest.TestEndGoesToLastSeg;
var Key: Word;
begin
  Key := VK_HOME; FPicker.SimKeyDown(Key);
  AssertEquals('start at seg 0', 0, FPicker.ActiveSegForTest);
  Key := VK_END;
  FPicker.SimKeyDown(Key);
  AssertEquals('End → last seg (2)', 2, FPicker.ActiveSegForTest);
end;

{ ── New tests ────────────────────────────────────────────────────────────── }

procedure TDateTimePickerControlTest.TestReadOnly_BlocksDigitEntry;
{ ReadOnly=True: typing a digit must not alter DateTime and must not
  populate the digit buffer. }
var
  Before: TDateTime;
begin
  FPicker.ReadOnly := True;
  Before := FPicker.DateTimeForTest;
  FPicker.SimKeyPress('5');
  AssertEquals('DateTime unchanged when ReadOnly', Before, FPicker.DateTimeForTest);
  AssertEquals('DigitBuffer empty when ReadOnly', '', FPicker.DigitBufferForTest);
end;

procedure TDateTimePickerControlTest.TestReadOnly_BlocksStepUp;
{ ReadOnly=True: VK_UP must not change DateTime. }
var
  Key: Word;
  Before: TDateTime;
begin
  FPicker.ReadOnly := True;
  Before := FPicker.DateTimeForTest;
  Key := VK_UP;
  FPicker.SimKeyDown(Key);
  AssertEquals('DateTime unchanged on VK_UP when ReadOnly', Before,
    FPicker.DateTimeForTest);
end;

procedure TDateTimePickerControlTest.TestReadOnly_BlocksWheel;
{ ReadOnly=True: DoMouseWheel must not change DateTime. }
var
  Before: TDateTime;
  Res: Boolean;
begin
  FPicker.ReadOnly := True;
  Before := FPicker.DateTimeForTest;
  Res := FPicker.DoMouseWheel([], 120, Point(0, 0));
  AssertFalse('DoMouseWheel returns False when ReadOnly', Res);
  AssertEquals('DateTime unchanged on wheel when ReadOnly', Before,
    FPicker.DateTimeForTest);
end;

procedure TDateTimePickerControlTest.TestReadOnly_NoOnChange;
{ ReadOnly=True: none of the above must fire OnChange. }
var
  Key: Word;
begin
  FPicker.ReadOnly := True;
  FCounter.Count   := 0;
  FPicker.SimKeyPress('5');
  Key := VK_UP;
  FPicker.SimKeyDown(Key);
  FPicker.DoMouseWheel([], 120, Point(0, 0));
  AssertEquals('OnChange never fires when ReadOnly', 0, FCounter.Count);
end;

procedure TDateTimePickerControlTest.TestAutoAdvance_ValueBranch_Typing3InMonth;
{ Active segment = month (seg 1 in yyyy-mm-dd).
  Typing '3' into a month segment triggers auto-advance because 30 > 12.
  After the finalize the active segment must have moved to seg 2 (day),
  and the month must be 3. }
var
  Key: Word;
  Y, M, D, H, Mi, S, MS: Word;
begin
  FPicker.DateTime := EncodeDate(2026, 6, 15);
  FCounter.Count   := 0;
  { Move to month segment (seg 1) }
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  AssertEquals('active seg is month (1)', 1, FPicker.ActiveSegForTest);
  FPicker.SimKeyPress('3');
  { '3' auto-advances because 30 > 12: month = 3, seg advances to 2 }
  AssertEquals('auto-advanced to seg 2 after typing 3', 2, FPicker.ActiveSegForTest);
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('month is 3 after typing 3', 3, Integer(M));
  AssertTrue('OnChange fired', FCounter.Count >= 1);
end;

procedure TDateTimePickerControlTest.TestStepPastMaxDate_Clamps;
{ Set MaxDate = 2026-06-30.  Start at 2026-06-30.  Step month up.
  TySegmentStep would give 2026-07-30 > MaxDate → CommitAndFire must clamp
  back to MaxDate (2026-06-30). }
var
  Key: Word;
  Y, M, D, H, Mi, S, MS: Word;
begin
  FPicker.DateTime := EncodeDate(2026, 6, 30);
  FPicker.MaxDate  := EncodeDate(2026, 6, 30);
  FCounter.Count   := 0;
  { Move to month segment }
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  AssertEquals('at month seg', 1, FPicker.ActiveSegForTest);
  Key := VK_UP;
  FPicker.SimKeyDown(Key);
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('year still 2026', 2026, Integer(Y));
  AssertEquals('month clamped to 6 by MaxDate', 6, Integer(M));
  AssertEquals('day still 30', 30, Integer(D));
end;

procedure TDateTimePickerControlTest.TestLeadingZero_BufferDisplayed_NoImmediateWrite;
{ Buffer-display model: typing '0' into the month segment must NOT immediately
  write month=1 to FDateTime (premature clamp-write).  The FDateTime month
  must remain as the ORIGINAL value until a second digit or a finalize trigger.
  The digit buffer must contain '0'. }
var
  Key: Word;
  Y, M, D, H, Mi, S, MS: Word;
begin
  FPicker.DateTime := EncodeDate(2026, 6, 15);  // month = 6
  FCounter.Count   := 0;
  { Move to month segment (seg 1) }
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  AssertEquals('active seg is month', 1, FPicker.ActiveSegForTest);
  FPicker.SimKeyPress('0');
  { Buffer holds '0'; FDateTime.month must still be 6 (not clamped to 1) }
  AssertEquals('digit buffer is 0', '0', FPicker.DigitBufferForTest);
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('month unchanged (still 6) after typing 0', 6, Integer(M));
  AssertEquals('OnChange NOT fired while buffer incomplete', 0, FCounter.Count);
end;

procedure TDateTimePickerControlTest.TestLeadingZero_ThenDigit_CommitsCorrectMonth;
{ After typing '0' then '3' into the month segment, the month must be 3.
  Typing '3' completes the 2-digit entry: buffer '03' → month = 3. }
var
  Key: Word;
  Y, M, D, H, Mi, S, MS: Word;
begin
  FPicker.DateTime := EncodeDate(2026, 6, 15);
  FCounter.Count   := 0;
  { Move to month segment }
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  Key := VK_RIGHT;
  FPicker.SimKeyDown(Key);
  FPicker.SimKeyPress('0');
  FPicker.SimKeyPress('3');
  { '03' is exactly 2 digits → auto-finalize; month = 3 }
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('month is 3 after typing 0 then 3', 3, Integer(M));
  AssertEquals('digit buffer cleared after auto-advance', '', FPicker.DigitBufferForTest);
  AssertTrue('OnChange fired', FCounter.Count >= 1);
end;

{ ── Pixel tests ──────────────────────────────────────────────────────────── }

procedure TDateTimePickerPixelTest.TestActiveSegmentHighlightPresent;
{ 130x24 @96ppi. Dark bg, light text.
  Active segment (seg 0, year, leftmost) should produce a highlighted band
  that differs from the background color in the text area left of the button.
  We scan for non-background pixels (not the pure dark bg color #101010)
  that are NOT in the rightmost 18px (button column). Since the highlight
  fill is alpha-blended accent over the dark bg, it should produce pixels
  that are different from both pure background and pure text color. }
var
  Form:    TForm;
  Picker:  TTyDateTimePickerProbe;
  Bmp:     TBitmap;
  Reread:  TBGRABitmap;
  Px:      TBGRAPixel;
  X, Y:    Integer;
  HighlightPixelCount: Integer;
begin
  FCtl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp  := TBitmap.Create;
  try
    { Dark theme: bg #101010, text/glyph #F0F0F0, selection = accent alpha 30% }
    FCtl.LoadThemeCss(
      'TyDateTimePicker { background: #101010; color: #F0F0F0; ' +
      '  border-width: 0px; border-radius: 0px; padding: 2px; }' +
      'TyTextSelection  { background: #3377FF; }');

    Picker := TTyDateTimePickerProbe.Create(Form);
    Picker.Parent     := Form;
    Picker.Controller := FCtl;
    Picker.SetBounds(0, 0, 130, 24);
    Picker.Font.PixelsPerInch := 96;
    Picker.Kind        := dtkDate;
    Picker.DateFormat  := 'yyyy-mm-dd';
    Picker.DateTime    := EncodeDate(2026, 6, 15);
    { Force focused state to true is not possible headlessly, so we check
      that the render at least draws text (ink pixels in the text area).
      For the highlight, we force a render in "focused" mode by checking
      any pixel in the text zone that differs from the pure bg. }

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(130, 24);
    Bmp.Canvas.Brush.Color := $101010;
    Bmp.Canvas.FillRect(0, 0, 130, 24);

    { Render while NOT focused (no highlight) — just a smoke test }
    Picker.RenderToForTest(Bmp.Canvas, Rect(0, 0, 130, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      { Count non-background pixels in the text zone (x=2..111, y=2..21) }
      HighlightPixelCount := 0;
      for Y := 2 to 21 do
        for X := 2 to 111 do
        begin
          Px := Reread.GetPixel(X, Y);
          { Pure bg is #101010 = (16,16,16); count pixels that differ notably }
          if (Px.red > 25) or (Px.green > 25) or (Px.blue > 25) then
            Inc(HighlightPixelCount);
        end;
      { At minimum, text pixels must be present in the text zone (smoke test) }
      AssertTrue('text pixels present in text zone after render',
        HighlightPixelCount > 0);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    FCtl.Free;
  end;
end;

procedure TDateTimePickerPixelTest.TestButtonGlyphPresent_dtkDate;
{ dtkDate: chevron-down glyph should appear in the right-side button column
  (x = 112..129) for a 130x24 control @96ppi (BtnW = Scale(18) = 18). }
var
  Form:   TForm;
  Picker: TTyDateTimePickerProbe;
  Bmp:    TBitmap;
  Reread: TBGRABitmap;
  Px:     TBGRAPixel;
  X, Y:   Integer;
  Found:  Boolean;
begin
  FCtl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp  := TBitmap.Create;
  try
    FCtl.LoadThemeCss(
      'TyDateTimePicker { background: #101010; color: #F0F0F0; ' +
      '  border-width: 0px; border-radius: 0px; padding: 2px; }');

    Picker := TTyDateTimePickerProbe.Create(Form);
    Picker.Parent := Form;
    Picker.Controller := FCtl;
    Picker.SetBounds(0, 0, 130, 24);
    Picker.Font.PixelsPerInch := 96;
    Picker.Kind := dtkDate;
    Picker.DateTime := EncodeDate(2026, 6, 15);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(130, 24);
    Bmp.Canvas.Brush.Color := $101010;
    Bmp.Canvas.FillRect(0, 0, 130, 24);
    Picker.RenderToForTest(Bmp.Canvas, Rect(0, 0, 130, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Found := False;
      for Y := 1 to 22 do
        for X := 112 to 129 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red > 100) and (Px.green > 100) and (Px.blue > 100) then
          begin
            Found := True;
            Break;
          end;
        end;
      AssertTrue('chevron-down glyph drew a light pixel in button column', Found);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    FCtl.Free;
  end;
end;

procedure TDateTimePickerPixelTest.TestButtonGlyphPresent_dtkTime;
{ dtkTime: up/down arrows should appear in the right-side button column. }
var
  Form:   TForm;
  Picker: TTyDateTimePickerProbe;
  Bmp:    TBitmap;
  Reread: TBGRABitmap;
  Px:     TBGRAPixel;
  X, Y:   Integer;
  Found:  Boolean;
begin
  FCtl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp  := TBitmap.Create;
  try
    FCtl.LoadThemeCss(
      'TyDateTimePicker { background: #101010; color: #F0F0F0; ' +
      '  border-width: 0px; border-radius: 0px; padding: 2px; }');

    Picker := TTyDateTimePickerProbe.Create(Form);
    Picker.Parent := Form;
    Picker.Controller := FCtl;
    Picker.SetBounds(0, 0, 130, 24);
    Picker.Font.PixelsPerInch := 96;
    Picker.Kind := dtkTime;
    Picker.TimeFormat := 'hh:nn:ss';
    Picker.DateTime := EncodeTime(10, 30, 0, 0);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(130, 24);
    Bmp.Canvas.Brush.Color := $101010;
    Bmp.Canvas.FillRect(0, 0, 130, 24);
    Picker.RenderToForTest(Bmp.Canvas, Rect(0, 0, 130, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Found := False;
      for Y := 1 to 22 do
        for X := 112 to 129 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red > 100) and (Px.green > 100) and (Px.blue > 100) then
          begin
            Found := True;
            Break;
          end;
        end;
      AssertTrue('up/down arrows drew a light pixel in button column', Found);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    FCtl.Free;
  end;
end;

{ ── TTyDateTimePickerProbeC3 ─────────────────────────────────────────────── }

procedure TTyDateTimePickerProbeC3.EnsurePopupForTest;
begin
  { EnsurePopup is protected — accessible from the subclass. }
  EnsurePopup;
end;

procedure TTyDateTimePickerProbeC3.SeedPopupCalendarForTest;
begin
  SeedPopupCalendar;
end;

procedure TTyDateTimePickerProbeC3.SimCalendarAccept(ADate: TDateTime);
begin
  { Force-create the popup+calendar if not yet done (lazy init). }
  EnsurePopupForTest;
  { Seed the calendar's Date directly. }
  Calendar.Date := ADate;
  { Invoke the accept handler through the calendar's OnAccept event.
    This simulates what happens when the user clicks a day cell or presses Enter. }
  if Assigned(Calendar.OnAccept) then
    Calendar.OnAccept(Calendar);
end;

procedure TTyDateTimePickerProbeC3.SimSpinUp;
begin
  { StepActiveSeg is protected — accessible from the subclass. }
  StepActiveSeg(+1);
end;

procedure TTyDateTimePickerProbeC3.SimSpinDown;
begin
  StepActiveSeg(-1);
end;

procedure TTyDateTimePickerProbeC3.SimToggleCheckBox;
begin
  { Simulate a checkbox toggle. The probe used to fire OnChecked itself, because the
    setter did not -- only the mouse hit-test did, which is why the Space key changed
    the state and told nobody. SetChecked now notifies (LCL does the same from its own
    setter, datetimepicker.pas:1011-1020), so firing it here as well would double. }
  Checked := not Checked;
end;

{ ── TDateTimePickerC3Test ────────────────────────────────────────────────── }

procedure TDateTimePickerC3Test.OnChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

procedure TDateTimePickerC3Test.OnCloseUp(Sender: TObject);
begin
  Inc(FCloseUpCount);
end;

procedure TDateTimePickerC3Test.OnChecked(Sender: TObject);
begin
  Inc(FCheckedCount);
end;

procedure TDateTimePickerC3Test.SetUp;
begin
  FPicker := TTyDateTimePickerProbeC3.Create(nil);
  FPicker.Font.PixelsPerInch := 96;
  FPicker.Kind       := dtkDate;
  FPicker.DateFormat := 'yyyy-mm-dd';
  FPicker.DateTime   := EncodeDate(2026, 6, 15) + EncodeTime(10, 30, 0, 0);
  FPicker.OnChange   := @OnChange;
  FPicker.OnCloseUp  := @OnCloseUp;
  FPicker.OnChecked  := @OnChecked;
  FChangeCount  := 0;
  FCloseUpCount := 0;
  FCheckedCount := 0;
end;

procedure TDateTimePickerC3Test.TearDown;
begin
  FPicker.Free;
end;

procedure TDateTimePickerC3Test.TestCalendarAccept_UpdatesDateAndFiresEvents;
{ Simulate accepting a different date via the calendar: assert:
  - DateTime date-part = accepted date
  - OnChange fired (at least once)
  - OnCloseUp fired (at least once)
  - DroppedDown = False (popup not open) }
var
  Y, M, D, H, Mi, S, MS: Word;
begin
  { Initial: 2026-06-15 }
  FChangeCount  := 0;
  FCloseUpCount := 0;

  { Simulate accepting 2026-07-20 from the calendar }
  FPicker.SimCalendarAccept(EncodeDate(2026, 7, 20));

  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('date-part year', 2026, Integer(Y));
  AssertEquals('date-part month', 7,    Integer(M));
  AssertEquals('date-part day', 20,     Integer(D));
  AssertTrue('OnChange fired at least once', FChangeCount >= 1);
  AssertTrue('OnCloseUp fired at least once', FCloseUpCount >= 1);
  AssertFalse('DroppedDown is False after accept', FPicker.DroppedDown);
end;

procedure TDateTimePickerC3Test.TestCalendarAccept_PreservesTimePart;
{ After accepting a new date the time part of the original DateTime should
  be preserved (not zeroed out). }
var
  Y, M, D, H, Mi, S, MS: Word;
begin
  { Initial DateTime has time 10:30:00 }
  FPicker.SimCalendarAccept(EncodeDate(2026, 8, 1));
  DecodeDateTime(FPicker.DateTimeForTest, Y, M, D, H, Mi, S, MS);
  AssertEquals('time hour preserved', 10, Integer(H));
  AssertEquals('time minute preserved', 30, Integer(Mi));
end;

procedure TDateTimePickerC3Test.TestSpinUp_StepsActiveSeg;
{ dtkTime spin-up: active segment steps +1 → DateTime changes. }
var
  Before, After: TDateTime;
  Key: Word;
begin
  FPicker.Kind       := dtkTime;
  FPicker.TimeFormat := 'hh:nn:ss';
  FPicker.DateTime   := EncodeTime(10, 30, 0, 0);
  FChangeCount := 0;
  { Move to hour segment (seg 0) }
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  Before := FPicker.DateTimeForTest;
  FPicker.SimSpinUp;
  After := FPicker.DateTimeForTest;
  AssertTrue('DateTime changed after spin-up', Before <> After);
  AssertTrue('OnChange fired', FChangeCount >= 1);
end;

procedure TDateTimePickerC3Test.TestSpinDown_StepsActiveSeg;
{ dtkTime spin-down: active segment steps -1 → DateTime changes. }
var
  Before, After: TDateTime;
  Key: Word;
begin
  FPicker.Kind       := dtkTime;
  FPicker.TimeFormat := 'hh:nn:ss';
  FPicker.DateTime   := EncodeTime(10, 30, 0, 0);
  FChangeCount := 0;
  Key := VK_HOME;
  FPicker.SimKeyDown(Key);
  Before := FPicker.DateTimeForTest;
  FPicker.SimSpinDown;
  After := FPicker.DateTimeForTest;
  AssertTrue('DateTime changed after spin-down', Before <> After);
end;

procedure TDateTimePickerC3Test.TestInert_DigitDoesNotChangeDateTime;
{ ShowCheckBox=True, Checked=False → field is inert → digit key must not
  change DateTime and must not fire OnChange. }
var
  Before: TDateTime;
begin
  FPicker.ShowCheckBox := True;
  FPicker.Checked      := False;
  FChangeCount         := 0;
  Before := FPicker.DateTimeForTest;
  FPicker.SimKeyPress('5');
  AssertEquals('DateTime unchanged when inert', Before, FPicker.DateTimeForTest);
  AssertEquals('DigitBuffer empty when inert', '', FPicker.DigitBuffer);
end;

procedure TDateTimePickerC3Test.TestInert_StepDoesNotChangeDateTime;
{ ShowCheckBox=True, Checked=False → VK_UP must not change DateTime. }
var
  Before: TDateTime;
  Key: Word;
begin
  FPicker.ShowCheckBox := True;
  FPicker.Checked      := False;
  FChangeCount         := 0;
  Before := FPicker.DateTimeForTest;
  Key := VK_UP;
  FPicker.SimKeyDown(Key);
  AssertEquals('DateTime unchanged on VK_UP when inert', Before, FPicker.DateTimeForTest);
end;

procedure TDateTimePickerC3Test.TestInert_NoOnChangeFired;
{ ShowCheckBox=True, Checked=False → no OnChange from digit or step. }
var
  Key: Word;
begin
  FPicker.ShowCheckBox := True;
  FPicker.Checked      := False;
  FChangeCount         := 0;
  FPicker.SimKeyPress('3');
  Key := VK_UP;
  FPicker.SimKeyDown(Key);
  AssertEquals('OnChange never fires when inert', 0, FChangeCount);
end;

procedure TDateTimePickerC3Test.TestCheckBoxToggle_FiresOnChecked_FlipsChecked;
{ When ShowCheckBox=True and Checked=False, toggling the checkbox flips
  Checked to True and fires OnChecked. }
begin
  FPicker.ShowCheckBox := True;
  FPicker.Checked      := False;
  FCheckedCount        := 0;
  FPicker.SimToggleCheckBox;
  AssertTrue('Checked is now True after toggle', FPicker.Checked);
  AssertEquals('OnChecked fired once', 1, FCheckedCount);
end;

procedure TDateTimePickerC3Test.TestCheckBoxToggle_ReEnablesEditing;
{ After toggling Checked=True, a digit key MUST update DateTime (field is
  no longer inert). }
var
  Before: TDateTime;
begin
  FPicker.ShowCheckBox := True;
  FPicker.Checked      := False;
  { Toggle on → now Checked=True }
  FPicker.SimToggleCheckBox;
  AssertTrue('Checked is True', FPicker.Checked);
  FChangeCount := 0;
  { Move to seg 0 (year) and type '2026' }
  FPicker.DateTime := EncodeDate(2026, 6, 15);
  Before := FPicker.DateTimeForTest;
  FPicker.SimKeyPress('1');    // digit: should now work
  { Even if it doesn't finalize yet (need more digits for year), the buffer
    should be non-empty — showing editing is unblocked. }
  AssertTrue('DigitBuffer non-empty after re-enabled edit',
    FPicker.DigitBuffer <> '');
end;

procedure TDateTimePickerC3Test.TestDropDownNilControllerNoCrash;
begin
  { FPicker (SetUp) has Controller=nil — the common case when a picker is themed via
    the global TyDefaultController. EnsurePopup used to assign Self.Controller (nil)
    to the calendar, and OpenDropDown then dereferenced FCalendar.Controller.Model,
    crashing the dropdown with an access violation. EnsurePopup must instead hand the
    calendar a valid ActiveController (never nil), so the deref is safe. }
  AssertNull('precondition: picker Controller is nil', FPicker.Controller);
  FPicker.EnsurePopupForTest;
  AssertNotNull('EnsurePopup gave the calendar a non-nil (ActiveController) controller',
    FPicker.Calendar.Controller);
  AssertNotNull('calendar controller has a Model (the .Controller.Model deref that crashed)',
    FPicker.Calendar.Controller.Model);
end;

{ ── TDateTimeLayoutTest ──────────────────────────────────────────────────── }

procedure TDateTimeLayoutTest.AssertClickSelects(P: TTyDateTimePickerProbe;
  AIndex, AX: Integer; const AWhere: string);
var
  K: Word;
begin
  if AIndex = 0 then K := VK_END else K := VK_HOME;
  P.SimKeyDown(K);
  AssertTrue('parked away from field ' + IntToStr(AIndex),
    P.ActiveSegForTest <> AIndex);
  P.SimMouseDown(AX, 12);
  AssertEquals(AWhere + ' of painted field ' + IntToStr(AIndex) + ' selects it',
    AIndex, P.ActiveSegForTest);
end;

procedure TDateTimeLayoutTest.AssertPaintedFieldsAnswerTheirOwnClicks(
  P: TTyDateTimePickerProbe; const AContext: string);
var
  i, X1, X2: Integer;
begin
  for i := 0 to High(P.Segments) do
  begin
    AssertTrue(AContext + ': field ' + IntToStr(i) + ' has a painted span',
      P.PaintedSegSpan(i, X1, X2));
    AssertClickSelects(P, i, X1 + 1,        AContext + ': the left edge');
    AssertClickSelects(P, i, (X1 + X2) div 2, AContext + ': the middle');
    AssertClickSelects(P, i, X2 - 1,        AContext + ': the right edge');
  end;
end;

procedure TDateTimeLayoutTest.TestTextBoxClearsPaddingAndButton;
var L: TTyDateTimeRects;
begin
  L := TyDateTimeRects(Rect(0, 0, 200, 24), 96, Rect(6, 3, 6, 3), 18, False);
  AssertEquals('text starts after the left padding', 6, L.Text.Left);
  AssertEquals('text stops before the button column', 200 - 18, L.Text.Right);
  AssertEquals('text clears the top padding', 3, L.Text.Top);
  AssertEquals('text clears the bottom padding', 24 - 3, L.Text.Bottom);
end;

procedure TDateTimeLayoutTest.TestNoButtonLeavesTheRectsEmpty;
var L: TTyDateTimeRects;
begin
  { dmNone hands the column width down as 0. }
  L := TyDateTimeRects(Rect(0, 0, 200, 24), 96, Rect(6, 3, 6, 3), 0, False);
  AssertTrue('no button rect',      IsRectEmpty(L.Button));
  AssertTrue('no up-half rect',     IsRectEmpty(L.ButtonUp));
  AssertTrue('no down-half rect',   IsRectEmpty(L.ButtonDown));
  AssertEquals('text runs to the frame', 200, L.Text.Right);
end;

procedure TDateTimeLayoutTest.TestCheckBoxShiftsTextByItsOwnColumn;
var L: TTyDateTimeRects;
begin
  L := TyDateTimeRects(Rect(0, 0, 200, 24), 96, Rect(6, 3, 6, 3), 18, True);
  AssertEquals('the indicator sits at the text box start', 6, L.CheckBox.Left);
  AssertEquals('the indicator is the token box wide',
    MulDiv(TyCheckBoxBox, 96, 96), L.CheckBox.Right - L.CheckBox.Left);
  AssertEquals('the string begins past the indicator AND its gap',
    6 + TyDateTimeCheckBoxColumn(96), L.Text.Left);
end;

procedure TDateTimeLayoutTest.TestCheckBoxColumnScalesItsTwoTermsSeparately;
{ At 111 PPI the indicator scales to 19 and the gap to 7, but their SUM scales to 25.
  The hit-test used to reserve the sum and the paint the two terms, so the string the
  user clicked began a pixel to the right of the one the control drew. Pinning the
  two-term form here is what stops that being re-introduced as a "simplification". }
begin
  AssertEquals('the column is the two terms scaled separately',
    MulDiv(TyCheckBoxBox, 111, 96) + MulDiv(TyCheckBoxGap, 111, 96),
    TyDateTimeCheckBoxColumn(111));
  AssertTrue('premise: scaling the SUM would give a different answer at this PPI',
    MulDiv(TyCheckBoxBox + TyCheckBoxGap, 111, 96) <> TyDateTimeCheckBoxColumn(111));
end;

procedure TDateTimeLayoutTest.TestSpinHalvesTileTheButtonColumn;
var L: TTyDateTimeRects;
begin
  L := TyDateTimeRects(Rect(0, 0, 200, 24), 96, Rect(6, 3, 6, 3), 18, False);
  AssertEquals('up half starts at the column',   L.Button.Left,  L.ButtonUp.Left);
  AssertEquals('down half ends at the column',   L.Button.Right, L.ButtonDown.Right);
  AssertEquals('the halves meet with no gap',    L.ButtonUp.Bottom, L.ButtonDown.Top);
  AssertEquals('together they span the column',
    L.Button.Bottom - L.Button.Top,
    (L.ButtonUp.Bottom - L.ButtonUp.Top) + (L.ButtonDown.Bottom - L.ButtonDown.Top));
end;

procedure TDateTimeLayoutTest.TestClickInThePaintedFieldSelectsThatField;
{ THE join. For every field, ask where the highlight is PAINTED and click its middle;
  the field that comes back must be the one that was painted there. The paint and the
  hit-test can only both satisfy this while they agree about the field's x, so any
  second tiling of the width shows up here as a red test rather than as a user clicking
  the year and landing on the month. A month NAME is used deliberately: it is the case
  where format offsets and rendered offsets differ, so the assertion has teeth. }
var
  P: TTyDateTimePickerProbe;
begin
  P := TTyDateTimePickerProbe.Create(nil);
  try
    P.SetBounds(0, 0, 300, 24);
    P.Kind       := dtkDate;
    P.DateFormat := 'dd mmmm yyyy';
    P.DateTime   := EncodeDate(2026, 9, 15);
    AssertPaintedFieldsAnswerTheirOwnClicks(P, 'left-aligned');
  finally
    P.Free;
  end;
end;

procedure TDateTimeLayoutTest.TestClickInThePaintedFieldSelectsThatFieldRightAligned;
{ Alignment moves the whole string, so it moves both the highlight and the hit test --
  or it moves one of them, which is the bug this pins. }
var
  P: TTyDateTimePickerProbe;
begin
  P := TTyDateTimePickerProbe.Create(nil);
  try
    P.SetBounds(0, 0, 300, 24);
    P.Kind       := dtkDate;
    P.DateFormat := 'dd mmmm yyyy';
    P.DateTime   := EncodeDate(2026, 9, 15);
    P.Alignment  := taRightJustify;
    AssertPaintedFieldsAnswerTheirOwnClicks(P, 'right-aligned');
  finally
    P.Free;
  end;
end;

procedure TDateTimeLayoutTest.TestCheckBoxColumnMovesThePaintedFieldsAndTheClicks;
{ The checkbox is the column the two sites composed differently. With one showing, the
  painted fields and the clicks must still meet. }
var
  P: TTyDateTimePickerProbe;
begin
  P := TTyDateTimePickerProbe.Create(nil);
  try
    P.SetBounds(0, 0, 300, 24);
    P.Kind         := dtkDate;
    P.DateFormat   := 'dd mmmm yyyy';
    P.DateTime     := EncodeDate(2026, 9, 15);
    P.ShowCheckBox := True;
    P.Checked      := True;
    AssertEquals('the text box has moved right by the checkbox column',
      P.RectsForTest.CheckBox.Left + TyDateTimeCheckBoxColumn(P.Font.PixelsPerInch),
      P.RectsForTest.Text.Left);
    AssertPaintedFieldsAnswerTheirOwnClicks(P, 'with a checkbox');
  finally
    P.Free;
  end;
end;

{ ── TDateTimeNullTest ───────────────────────────────────────────────────── }

type
  { A host for the streaming guards. Declared here rather than reused from another
    unit so the .lfm this test writes is this test's own. }
  TNullHostForm = class(TForm)
  published
    DTP: TTyDateTimePicker;
  end;

procedure TDateTimeNullTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TDateTimeNullTest.Press(AKey: Word);
var K: Word;
begin
  K := AKey;
  FPicker.SimKeyDown(K);
end;

procedure TDateTimeNullTest.SetUp;
begin
  FPicker := TTyDateTimePickerProbe.Create(nil);
  FPicker.SetBounds(0, 0, 300, 24);
  FPicker.Kind       := dtkDate;
  FPicker.DateFormat := 'yyyy-mm-dd';
  FPicker.DateTime   := EncodeDate(2026, 9, 15);
  FChanges := 0;
end;

procedure TDateTimeNullTest.TearDown;
begin
  FreeAndNil(FPicker);
end;

procedure TDateTimeNullTest.NullIsARangeNotABitPattern;
{ The predicate has to answer for values that never came from TyNullDate: a NaN out
  of a database driver, an infinity out of a bad cast, a float that lost its last
  digits round-tripping through text. Pinning it as `= TyNullDate` would pass every
  test written with TyNullDate and fail every one of those. }
begin
  AssertTrue('the sentinel itself',            TyDateIsNull(TyNullDate));
  AssertTrue('LCL spelling is the same value', TyDateIsNull(NullDate));
  AssertTrue('a DIFFERENT out-of-range value is null too',
    TyDateIsNull(TDateTime(1.9e+308)));
  AssertTrue('an infinity is null',  TyDateIsNull(TDateTime(Math.Infinity)));
  AssertTrue('a NaN is null',        TyDateIsNull(TDateTime(Math.NaN)));
  AssertTrue('below the floor is null too',
    TyDateIsNull(TDateTime(-1.9e+308)));
  AssertFalse('a real date is not null',  TyDateIsNull(EncodeDate(2026, 9, 15)));
  AssertFalse('zero is a DATE (30 Dec 1899), not an absence',
    TyDateIsNull(TDateTime(0)));
  AssertFalse('the last representable instant is still a date',
    TyDateIsNull(SysUtils.MaxDateTime));
  AssertFalse('and so is the first', TyDateIsNull(SysUtils.MinDateTime));
end;

procedure TDateTimeNullTest.EqualDateTimeTreatsTwoUnequalNullsAsEqual;
begin
  AssertTrue('two nulls that are not bit-equal still mean the same thing',
    TyEqualDateTime(TyNullDate, TDateTime(1.9e+308)));
  AssertFalse('null is not a date', TyEqualDateTime(TyNullDate, EncodeDate(2026, 1, 1)));
  AssertFalse('a date is not null', TyEqualDateTime(EncodeDate(2026, 1, 1), TyNullDate));
  AssertTrue('and dates still compare as dates',
    TyEqualDateTime(EncodeDate(2026, 1, 1), EncodeDate(2026, 1, 1)));
  AssertFalse('two different dates do not',
    TyEqualDateTime(EncodeDate(2026, 1, 1), EncodeDate(2026, 1, 2)));
end;

procedure TDateTimeNullTest.TheProgrammaticSetterKeepsTheValueEmpty;
{ THE assertion. SetDateTime pulls every write inside the absolute limits, and
  TyNullDate is above the ceiling BY CONSTRUCTION -- so the clamp that exists to stop
  a user typing year 0001 is also the clamp that turns "no date" into 31 Dec 9999.
  A field that reads back a real date after being emptied is the failure mode this
  whole feature is judged on. }
begin
  FPicker.DateTime := TyNullDate;
  AssertTrue('the field is empty', FPicker.DateIsNull);
  AssertTrue('and it did not become the biggest date the clamp allows',
    FPicker.DateTime > SysUtils.MaxDateTime);
  { NORMALISATION, and it carries more weight than it looks like it does. Every write
    lands on exactly TyNullDate, whatever out-of-range value came in -- which is what
    lets the plain `<>` comparisons inside the control stay correct without each of them
    reaching for TyEqualDateTime. Break this and those comparisons start answering
    "changed" for two values that are both empty. }
  FPicker.DateTime := EncodeDate(2026, 1, 1);
  FPicker.DateTime := TDateTime(1.9e+308);
  AssertTrue('a DIFFERENT empty value normalises to the one sentinel',
    FPicker.DateTime = TyNullDate);
  FPicker.DateTime := EncodeDate(2026, 1, 1);
  FPicker.DateTime := TDateTime(Math.NaN);
  AssertTrue('and so does a NaN', FPicker.DateTime = TyNullDate);
end;

procedure TDateTimeNullTest.TighteningMaxDateDoesNotFillAnEmptyField;
{ MaxDate's setter re-clamps a standing value that is now out of range. An empty value
  is out of range by construction, so the ordinary `if FDateTime > FMaxDate` sees it as
  a date that overshot and "corrects" it -- silently filling the field the user just
  cleared, from a line that never mentions the value at all. }
begin
  FPicker.DateTime := TyNullDate;
  FPicker.MaxDate  := EncodeDate(2030, 1, 1);
  AssertTrue('still empty after the ceiling moved', FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.TighteningMinDateDoesNotFillAnEmptyField;
begin
  FPicker.DateTime := TyNullDate;
  FPicker.MinDate  := EncodeDate(2020, 1, 1);
  AssertTrue('still empty after the floor moved', FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.LosingFocusDoesNotFillAnEmptyField;
{ DoExit commits, and the commit clamps. Same trap as MaxDate, reached by tabbing away. }
begin
  FPicker.DateTime := TyNullDate;
  FPicker.SimDoExit;
  AssertTrue('still empty after focus-out', FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.AnUndoRestoresEmptinessRatherThanADate;
{ Escape restores the focus-in snapshot. The edit has to be a USER one: a programmatic
  DateTime write is documented to become the new baseline (SetDateTime re-confirms), so
  reverting one would be throwing away the record the host just loaded.

  The trap is the comparison. `FDateTime <> FConfirmedDateTime` on two empty values is
  arithmetic on out-of-range floats, and the restore either fires a spurious OnChange or
  -- the direction that actually loses data -- decides nothing changed and leaves the
  date sitting in a field the user meant to clear. }
begin
  FPicker.DateTime := TyNullDate;
  FPicker.ConfirmChanges;
  Press(VK_HOME);
  Press(VK_UP);                       { a user gesture: the arrow fills the field }
  AssertFalse('premise: it holds a date now', FPicker.DateIsNull);
  FPicker.UndoChanges;
  AssertTrue('Escape put the emptiness back', FPicker.DateIsNull);
  { And the other direction: undoing to a DATE from an empty edit must still restore. }
  FPicker.DateTime := EncodeDate(2026, 5, 5);
  FPicker.ConfirmChanges;
  Press(VK_N);
  AssertTrue('premise: the user cleared it', FPicker.DateIsNull);
  FPicker.UndoChanges;
  AssertFalse('Escape put the date back', FPicker.DateIsNull);
  AssertEquals('the very date that was there', 2026, YearOf(FPicker.DateTime));
end;

procedure TDateTimeNullTest.DateAndTimeReadBackEmptyRatherThanGarbage;
{ Date is Trunc(FDateTime) and Time is Frac(FDateTime). Both of those on 1.7e308 are
  meaningless at best and a range error at worst, and the value they produce would be
  written straight into the host's record. }
begin
  FPicker.DateTime := TyNullDate;
  AssertTrue('Date reports empty', TyDateIsNull(FPicker.Date));
  AssertTrue('Time reports empty', TyDateIsNull(FPicker.Time));
end;

procedure TDateTimeNullTest.WritingTheDatePartOfAnEmptyFieldDoesNotComposeAgainstGarbage;
{ SetDate keeps the TIME part of the standing value. There is no time part in an empty
  value, so the composition has to notice rather than add a fraction of infinity. }
begin
  FPicker.DateTime := TyNullDate;
  FPicker.Date     := EncodeDate(2026, 3, 4);
  AssertFalse('the field now holds a date', FPicker.DateIsNull);
  AssertEquals('the year written', 2026, YearOf(FPicker.DateTime));
  AssertEquals('the month written',   3, MonthOf(FPicker.DateTime));
  AssertEquals('the day written',     4, DayOf(FPicker.DateTime));
  AssertEquals('with no time smuggled in from the empty value', 0.0,
    Double(Frac(FPicker.DateTime)), 1e-9);
end;

procedure TDateTimeNullTest.WritingTheTimePartOfAnEmptyFieldLandsOnARealDay;
{ The mirror image: SetTime keeps the DATE part, and an empty value has none. }
begin
  FPicker.DateTime := TyNullDate;
  FPicker.Time     := 0.5;   { 12:00 }
  AssertFalse('the field now holds a value', FPicker.DateIsNull);
  AssertEquals('the time is the one written', 0.5,
    Double(Frac(FPicker.DateTime)), 1e-6);
  AssertEquals('and the day it landed on is today, not 30 Dec 1899',
    Int64(Trunc(SysUtils.Date)), Int64(Trunc(FPicker.DateTime)));
end;

procedure TDateTimeNullTest.AnEmptyFieldShowsTextForNullDate;
begin
  FPicker.DateTime := TyNullDate;
  AssertEquals('the default is LCL''s', TyDefaultTextForNullDate,
    FPicker.TextForNullDate);
  AssertEquals('and it is what the field draws', TyDefaultTextForNullDate,
    FPicker.DisplayTextForTest);
  FPicker.TextForNullDate := '(no deadline)';
  AssertEquals('a host''s own wording reaches the paint', '(no deadline)',
    FPicker.DisplayTextForTest);
end;

procedure TDateTimeNullTest.AnEmptyFieldHasNoSegmentToHighlight;
{ 'NULL' has no year in it. A highlight measured against the date's spans would land
  on characters that are not there -- which on a short string means a band drawn past
  the text, and on the hit-test side a click resolving to a field the paint never drew. }
var X1, X2: Integer;
begin
  FPicker.DateTime := TyNullDate;
  AssertFalse('no painted span for field 0', FPicker.PaintedSegSpan(0, X1, X2));
  AssertFalse('nor for the last one',
    FPicker.PaintedSegSpan(High(FPicker.Segments), X1, X2));
  { And the click that would have landed in a field resolves to nothing rather than
    to whichever field the DATE's spans would have put there. }
  Press(VK_END);
  FPicker.SimMouseDown(FPicker.RectsForTest.Text.Left + 2, 12);
  AssertEquals('a click on an empty field does not move the selection',
    High(FPicker.Segments), FPicker.ActiveSegForTest);
  AssertTrue('and it certainly does not invent a date', FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.AnEmptyFieldStillMovesBetweenItsFields;
{ The FIELD LIST comes from the format, not from the value, so it exists whether or not
  a date does. Losing it would mean an empty field could be tabbed into and then had no
  reachable place to start typing. }
begin
  FPicker.DateTime := TyNullDate;
  Press(VK_HOME);
  AssertEquals('parked on the first field', 0, FPicker.ActiveSegForTest);
  Press(VK_RIGHT);
  AssertEquals('and the arrow still moves', 1, FPicker.ActiveSegForTest);
end;

procedure TDateTimeNullTest.TypingIntoAnEmptyFieldMaterialisesADate;
{ FinalizeBuffer decodes the STANDING value to get the fields it is not changing.
  Decoding an empty one raises, so the field has to start from a seed. }
begin
  FPicker.DateTime := TyNullDate;
  FPicker.OnChange := @CountChange;
  Press(VK_HOME);                     { the year field of 'yyyy-mm-dd' }
  FPicker.SimKeyPress('2');
  FPicker.SimKeyPress('0');
  FPicker.SimKeyPress('3');
  FPicker.SimKeyPress('1');
  AssertFalse('typing a year filled the field', FPicker.DateIsNull);
  AssertEquals('with the year that was typed', 2031, YearOf(FPicker.DateTime));
  AssertEquals('and the month/day came from today, not from year zero',
    MonthOf(SysUtils.Date), MonthOf(FPicker.DateTime));
  AssertEquals('exactly one change was announced', 1, FChanges);
end;

procedure TDateTimeNullTest.SteppingAnEmptyFieldMaterialisesADate;
{ TySegmentStep decodes the standing value too. }
begin
  FPicker.DateTime := TyNullDate;
  Press(VK_HOME);
  Press(VK_UP);
  AssertFalse('the arrow filled the field', FPicker.DateIsNull);
  AssertEquals('one year on from the seed', YearOf(SysUtils.Date) + 1,
    YearOf(FPicker.DateTime));
end;

procedure TDateTimeNullTest.TheTypedDigitsShowWhileTheFieldIsStillEmpty;
{ The digit buffer is a "commit on leave" model: the value stays as it was until the
  field fills. On an empty field that means the value is STILL EMPTY while the user is
  typing -- so the display has to show the partly-typed date rather than go on saying
  NULL, or the keystrokes vanish into a field that never acknowledges them. }
begin
  FPicker.DateTime := TyNullDate;
  Press(VK_HOME);
  FPicker.SimKeyPress('2');
  AssertTrue('premise: one digit has not committed anything yet', FPicker.DateIsNull);
  AssertTrue('and the field is no longer showing the null text',
    FPicker.DisplayTextForTest <> TyDefaultTextForNullDate);
  AssertTrue('it is showing what was typed',
    Pos('2', FPicker.DisplayTextForTest) > 0);
end;

procedure TDateTimeNullTest.TheNullKeyEmptiesTheFieldAndAnnouncesIt;
{ N is LCL's key for this (datetimepicker.pas:3731). Emptying the field from the
  keyboard is a USER edit, so it announces itself -- unlike the programmatic setter,
  which is deliberately silent. }
begin
  FPicker.OnChange := @CountChange;
  Press(VK_N);
  AssertTrue('N emptied the field', FPicker.DateIsNull);
  AssertEquals('and said so once', 1, FChanges);
  Press(VK_N);
  AssertEquals('pressing it again changes nothing and announces nothing',
    1, FChanges);
end;

procedure TDateTimeNullTest.DeleteEmptiesTheFieldToo;
{ Ours, not LCL's -- LCL binds only N, which is a letter nobody guesses. Delete is
  what a user reaches for to clear a field, and binding it costs one case label. }
begin
  Press(VK_DELETE);
  AssertTrue('Delete empties the field', FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.NullInputAllowedFalseClosesTheKeyNotTheProperty;
{ The flag governs the USER, not the host. A form that means "required" wants the
  keyboard route shut; refusing its own `DTP.DateTime := Rec.Due` -- which may be null
  because the column is -- would be refusing the caller's data. }
begin
  AssertTrue('on by default, as LCL', FPicker.NullInputAllowed);
  FPicker.NullInputAllowed := False;
  Press(VK_N);
  AssertFalse('the key is refused', FPicker.DateIsNull);
  Press(VK_DELETE);
  AssertFalse('and so is Delete', FPicker.DateIsNull);
  FPicker.DateTime := TyNullDate;
  AssertTrue('but the property still writes through', FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.ReadOnlyRefusesTheNullKey;
begin
  FPicker.ReadOnly := True;
  Press(VK_N);
  AssertFalse('a read-only field cannot be emptied from the keyboard',
    FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.AnInertFieldRefusesTheNullKey;
{ IsInert blocks every edit, and clearing the value is an edit. The ordering matters:
  the Space branch deliberately sits ABOVE the inert gate (it is the only way back),
  and N must not be tempted up there with it. }
begin
  FPicker.ShowCheckBox := True;
  FPicker.Checked      := False;
  Press(VK_N);
  AssertFalse('an unchecked field is not editable, including to empty',
    FPicker.DateIsNull);
end;

procedure TDateTimeNullTest.PreferredWidthBudgetsForTheLongerOfTheTwoStrings;
{ The field can show either string, so it has to be wide enough for both. Measuring
  only the date is how an AutoSize field set to "Not scheduled" clips the words it was
  just told to display. }
var
  WithShort, WithLong: Integer;
  H: Integer;
begin
  FPicker.AutoSize := False;
  FPicker.TextForNullDate := 'X';
  WithShort := 0; H := 0;
  FPicker.GetPreferredSize(WithShort, H);
  FPicker.TextForNullDate :=
    'no deadline has been set for this item at all';
  WithLong := 0; H := 0;
  FPicker.GetPreferredSize(WithLong, H);
  AssertTrue('the longer null text asks for more width (' +
    IntToStr(WithShort) + ' -> ' + IntToStr(WithLong) + ')', WithLong > WithShort);
end;

procedure TDateTimeNullTest.TheDropdownSeedsFromASeedDateWhenTheFieldIsEmpty;
{ OpenDropDown assigns the picker's date into the calendar, and the calendar's setter
  RAISES on anything outside its range (tyControls.Calendar.pas:510-516). An empty
  value is outside every range, so an unguarded seed does not merely show the wrong
  month -- it throws out of the click that opened the popup. }
var
  P: TTyDateTimePickerProbeC3;
begin
  P := TTyDateTimePickerProbeC3.Create(nil);
  try
    P.SetBounds(0, 0, 300, 24);
    P.Kind     := dtkDate;
    P.DateTime := TyNullDate;
    { The seeding, not the showing: the raise would come from here, and showing a real
      popup window is out of reach without a screen. }
    P.EnsurePopupForTest;
    P.SeedPopupCalendarForTest;
    AssertNotNull('the seeding returned rather than throwing', P.Calendar);
    AssertEquals('the calendar starts on the seed day',
      Int64(Trunc(SysUtils.Date)), Int64(Trunc(P.Calendar.Date)));
    AssertTrue('and opening it did not fill the picker', P.DateIsNull);
  finally
    P.Free;
  end;
end;

procedure TDateTimeNullTest.AnEmptyValueSurvivesAnLfmRoundTrip;
{ The sentinel is written and read as an ordinary float. It need not come back
  bit-identical for the field to still read as empty -- that is exactly why the
  predicate is a range test -- but it does have to come back OUT OF RANGE. }
var
  Src, Dst: TNullHostForm;
  MS: TMemoryStream;
  D: TTyDateTimePicker;
begin
  Src := TNullHostForm.CreateNew(nil);
  Dst := TNullHostForm.CreateNew(nil);
  MS  := TMemoryStream.Create;
  try
    Src.Name       := 'NullHost1';
    Src.DTP        := TTyDateTimePicker.Create(Src);
    Src.DTP.Name   := 'DTP';
    Src.DTP.Parent := Src;
    Src.DTP.DateTime := TyNullDate;
    Src.DTP.TextForNullDate := '(none)';
    AssertTrue('premise: the source is empty', Src.DTP.DateIsNull);
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);
    D := Dst.FindComponent('DTP') as TTyDateTimePicker;
    AssertNotNull('the picker survived', D);
    AssertTrue('and it is still empty', D.DateIsNull);
    AssertEquals('the null wording streamed too', '(none)', D.TextForNullDate);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

procedure TDateTimeNullTest.ADateStreamedBeforeItsBoundsStillLoads;
{ A .lfm lists properties in declaration order, so DateTime arrives BEFORE MinDate and
  MaxDate -- i.e. while the field is still unbounded, holding a value its own bounds
  will later reject. Turning that into an exception aborts ReadComponent and the whole
  window refuses to open, which is what tyControls.Calendar.pas:505-509 carves an
  explicit csLoading branch out to avoid. This control clamps instead of raising, and
  this guard is what stops a later "validate the value" edit changing that quietly. }
var
  Host: TNullHostForm;
  MS: TStringStream;
  BinStream: TMemoryStream;
  D: TTyDateTimePicker;
  Lfm: string;
begin
  { A hand-written .lfm with the value BEFORE the bounds and OUTSIDE them. }
  Lfm :=
    'object NullHost2: TNullHostForm'#13#10 +
    '  object DTP: TTyDateTimePicker'#13#10 +
    '    DateTime = 44000'#13#10 +          { 2020-06-19 }
    '    MinDate = 45000'#13#10 +           { 2023-03-15 -- above the value }
    '    MaxDate = 46000'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
  Host      := TNullHostForm.CreateNew(nil);
  MS        := TStringStream.Create(Lfm);
  BinStream := TMemoryStream.Create;
  try
    ObjectTextToBinary(MS, BinStream);
    BinStream.Position := 0;
    { The assertion IS that this returns. }
    BinStream.ReadComponent(Host);
    D := Host.FindComponent('DTP') as TTyDateTimePicker;
    AssertNotNull('the form opened and the picker is on it', D);
    AssertEquals('and the out-of-range value was clamped, not rejected',
      Int64(45000), Int64(Trunc(D.DateTime)));
  finally
    BinStream.Free;
    MS.Free;
    Host.Free;
  end;
end;

{ ── TDateTimePickerNameSourceTest ────────────────────────────────────────── }

procedure TDateTimePickerNameSourceTest.SetUp;
begin
  FSavedSource := TyDateTimeNameSource;
  FSavedFmt    := DefaultFormatSettings;
  FPicker      := TTyDateTimePickerProbe.Create(nil);
  FPicker.Font.PixelsPerInch := 96;
  FPicker.Kind       := dtkDate;
  FPicker.DateFormat := 'dd mmmm yyyy';          // a format that ASKS for a name
  FPicker.DateTime   := EncodeDate(2026, 8, 15);
end;

procedure TDateTimePickerNameSourceTest.TearDown;
begin
  FPicker.Free;
  TyDateTimeNameSource  := FSavedSource;
  DefaultFormatSettings := FSavedFmt;
end;

procedure TDateTimePickerNameSourceTest.TheFieldTextFollowsTheForcedTranslationTier;
{ DisplayTextForTest is the PAINT's own recorded string (RenderOffscreen ->
  FPaintedText), so this pins the pixel path, not a parallel formatter. }
begin
  DefaultFormatSettings.LongMonthNames[8] := 'LocaleProbeAug';
  TyDateTimeNameSource := dnTranslation;
  AssertEquals('the field text renders the app language''s month name',
    '15 August 2026', FPicker.DisplayTextForTest);
end;

procedure TDateTimePickerNameSourceTest.TheFieldTextFollowsTheForcedLocaleTier;
begin
  DefaultFormatSettings.LongMonthNames[8] := 'LocaleProbeAug';
  TyDateTimeNameSource := dnLocale;
  AssertEquals('the field text renders the locale''s month name when forced to',
    '15 LocaleProbeAug 2026', FPicker.DisplayTextForTest);
end;

procedure TDateTimePickerNameSourceTest.ThePreferredWidthMeasuresTheSameNamesTheFieldRenders;
{ CalculatePreferredSize measures the WIDEST renderable value (30 September). Give
  the locale a September name three times as long as English's: if the width
  query still measured DefaultFormatSettings while the paint renders the
  translation, the two answers converge and this assertion dies. }
var
  wTrans, hTrans, wLocale, hLocale: Integer;
begin
  DefaultFormatSettings.LongMonthNames[9] := 'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW';
  TyDateTimeNameSource := dnTranslation;
  FPicker.InvalidatePreferredSize;      // LCL caches; a stale cache would compare
  FPicker.GetPreferredSize(wTrans, hTrans);
  TyDateTimeNameSource := dnLocale;
  FPicker.InvalidatePreferredSize;      // ...one measurement against itself
  FPicker.GetPreferredSize(wLocale, hLocale);
  AssertTrue(Format('width follows the name source: locale(W*30)=%d must exceed '
    + 'translation(September)=%d', [wLocale, wTrans]), wLocale > wTrans);
end;

initialization
  RegisterTest(TDateTimePickerPureTest);
  RegisterTest(TDateTimeNullTest);
  RegisterTest(TDateTimeLayoutTest);
  RegisterTest(TDateTimeActiveSegAtTest);
  RegisterTest(TDateTimePickerControlTest);
  RegisterTest(TDateTimePickerPixelTest);
  RegisterTest(TDateTimePickerC3Test);
  RegisterTest(TDateTimePickerNameSourceTest);

end.
