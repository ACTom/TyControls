unit test.parity.ranges;
{ LCL parity for the three range/sentinel behaviours that used to fail SILENTLY.

  1. TTyCalendar.Date  — an out-of-range assignment was clamped and the caller was
     never told, so `Cal.Date := X; if Cal.Date <> X then` was the only way to find
     out and nobody writes that. LCL raises EInvalidDate (calendar.pp:293-304,
     :322-339). We now raise ETyInvalidDate too, with the clamp still reachable
     under its own name, and with streaming carved out so a .lfm cannot fail to load.

  2. TTyCheckGroup.Checked[] — an out-of-range read answered False and an
     out-of-range write was dropped, so an off-by-one looked like an unchecked item.
     LCL raises naming the class, the index and the maximum
     (include/customcheckgroup.inc:173-177, :313-338).

  3. TTyCustomTabStrip.TabHeight — 0 is OUR sentinel for "no strip", where LCL's 0
     means "size it from the font". We keep 0 = no strip (a shipped, demoed
     capability LCL only reaches via ShowTabs), and give the auto meaning a NAME
     (TyTabHeightAuto) so it is reachable and reversible instead of being lost the
     moment a host pins a height. Also pins the relayout that pinning the fallback
     value used to skip.

  Every guard here was watched RED against the pre-fix source before the fix landed. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, DateUtils, Controls, Forms, LCLType,
  fpcunit, testregistry,
  tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Calendar, tyControls.CheckGroup, tyControls.TabStrip;

type
  { --- Defect 1: TTyCalendar out-of-range date --- }
  TCalendarRangeTest = class(TTestCase)
  private
    FCal: TTyCalendar;
    { Assigns ADate and returns the raised message, or '' when nothing was raised. }
    function AssignAndCatch(ADate: TDateTime): string;
    function AssignDateTimeAndCatch(ADate: TDateTime): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAboveMaxDateRaises;
    procedure TestBelowMinDateRaises;
    procedure TestRaiseLeavesTheOldDateIntact;
    procedure TestMessageNamesTheDateAndBothBounds;
    procedure TestInRangeAssignmentIsSilent;
    procedure TestUnboundedCalendarAcceptsAnyDate;
    procedure TestOnlyMaxBoundStillGuards;
    procedure TestOnlyMinBoundStillGuards;
    procedure TestDateTimeAliasGuardsToo;
    procedure TestSetDateClampedStillClamps;
    procedure TestSetDateClampedNeverRaises;
    procedure TestTighteningMaxDateClampsInsteadOfRaising;
    procedure TestTighteningMinDateClampsInsteadOfRaising;
  end;

  { Streaming must survive an out-of-range date whatever order the .lfm lists the
    properties in — a form that fails to load is a far worse outcome than a clamp. }
  TCalendarStreamingTest = class(TTestCase)
  private
    function LoadFromLfmText(const ALfm: string): TTyCalendar;
  published
    procedure TestBoundsBeforeDateStillLoads;
    procedure TestDateBeforeBoundsStillLoads;
  end;

  { --- Defect 2: TTyCheckGroup out-of-range index --- }
  TCheckGroupRangeTest = class(TTestCase)
  private
    FForm: TForm;
    FGrp: TTyCheckGroup;
    function ReadAndCatch(AIndex: Integer): string;
    function WriteAndCatch(AIndex: Integer; AValue: Boolean): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestReadAboveRangeRaises;
    procedure TestReadBelowRangeRaises;
    procedure TestWriteAboveRangeRaises;
    procedure TestWriteBelowRangeRaises;
    procedure TestMessageNamesClassIndexAndMaximum;
    procedure TestInRangeAccessStaysSilent;
    procedure TestEmptyGroupRaisesForEveryIndex;
    procedure TestRejectedWriteChangesNothing;
  end;

  { --- Defect 3: TTyCustomTabStrip.TabHeight --- }
  { Minimal concrete strip: the header engine is abstract, so supply two tabs.

    The observable is the REPAINT count, not the resulting height. In the broken case
    the height read back correctly and everything downstream of the getter agreed — the
    only thing missing was that SetTabHeight returned early and never told the control
    anything had changed, so the pages kept covering the band until something else
    happened to invalidate it. Realign would be the more direct probe but LCL runs no
    alignment while the parent form has no handle, so AlignControls is unreachable in a
    headless runner (test.pagecontrol documents the same limitation); Realign and
    Invalidate sit on the same side of the early Exit, so counting the repaint pins it. }
  TStripProbe = class(TTyCustomTabStrip)
  private
    FRepaints: Integer;
  protected
    function GetTabCount: Integer; override;
    function GetTabCaption(AIndex: Integer): string; override;
  public
    procedure Invalidate; override;
    function ClientTopInset: Integer;
    property Repaints: Integer read FRepaints write FRepaints;
  end;

  TTabHeightSentinelTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FStrip: TStripProbe;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestZeroStillMeansNoStrip;
    procedure TestZeroSurvivesTheGetter;
    procedure TestUnsetFollowsTheDensityToken;
    procedure TestAutoSentinelUnpinsBackToTheTheme;
    procedure TestAutoSentinelIsNotConfusedWithHidden;
    procedure TestPinningTheFallbackValueIsNotANoOp;
    procedure TestUnpinningIsNotANoOp;
    procedure TestExplicitHeightIsStreamedAndZeroRoundTrips;
  end;

implementation

{ ============================ Defect 1: TTyCalendar ========================== }

procedure TCalendarRangeTest.SetUp;
begin
  FCal := TTyCalendar.Create(nil);
end;

procedure TCalendarRangeTest.TearDown;
begin
  FreeAndNil(FCal);
end;

function TCalendarRangeTest.AssignAndCatch(ADate: TDateTime): string;
begin
  Result := '';
  try
    FCal.Date := ADate;
  except
    on E: Exception do Result := E.ClassName + '|' + E.Message;
  end;
end;

function TCalendarRangeTest.AssignDateTimeAndCatch(ADate: TDateTime): string;
begin
  Result := '';
  try
    FCal.DateTime := ADate;
  except
    on E: Exception do Result := E.ClassName + '|' + E.Message;
  end;
end;

procedure TCalendarRangeTest.TestAboveMaxDateRaises;
var
  msg: string;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 30);
  msg := AssignAndCatch(EncodeDate(2026, 7, 15));
  AssertTrue('a date past MaxDate must raise, not be quietly coerced', msg <> '');
  AssertTrue('and it must be the documented class, got: ' + msg,
    Pos('ETyInvalidDate', msg) = 1);
end;

procedure TCalendarRangeTest.TestBelowMinDateRaises;
var
  msg: string;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 30);
  msg := AssignAndCatch(EncodeDate(2026, 5, 15));
  AssertTrue('a date before MinDate must raise', msg <> '');
  AssertTrue('and it must be the documented class, got: ' + msg,
    Pos('ETyInvalidDate', msg) = 1);
end;

{ A rejected write must not half-apply: the old date, and the view anchored on it,
  stay exactly where they were. Clamping used to leave a THIRD value behind (the
  bound), which is the value the caller never asked for in the first place. }
procedure TCalendarRangeTest.TestRaiseLeavesTheOldDateIntact;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 30);
  FCal.Date    := EncodeDate(2026, 6, 15);
  AssignAndCatch(EncodeDate(2027, 1, 1));
  AssertEquals('the rejected assignment left the old date alone',
    DateOf(EncodeDate(2026, 6, 15)), DateOf(FCal.Date));
  AssertEquals('and the view anchor did not drift', 6, FCal.ViewMonth);
  AssertEquals('and the view year did not drift', 2026, FCal.ViewYear);
end;

{ LCL's rsInvalidDateRangeHint prints the offending date AND both bounds so the
  developer can see which end was violated without a debugger. Ours must too —
  an exception that only says "bad date" costs the same round trip as the clamp did. }
procedure TCalendarRangeTest.TestMessageNamesTheDateAndBothBounds;
var
  msg: string;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 30);
  msg := AssignAndCatch(EncodeDate(2026, 7, 15));
  AssertTrue('message names the offending date, got: ' + msg,
    Pos(DateToStr(EncodeDate(2026, 7, 15)), msg) > 0);
  AssertTrue('message names MinDate, got: ' + msg,
    Pos(DateToStr(EncodeDate(2026, 6, 1)), msg) > 0);
  AssertTrue('message names MaxDate, got: ' + msg,
    Pos(DateToStr(EncodeDate(2026, 6, 30)), msg) > 0);
end;

procedure TCalendarRangeTest.TestInRangeAssignmentIsSilent;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 30);
  AssertEquals('an in-range date must not raise',
    '', AssignAndCatch(EncodeDate(2026, 6, 15)));
  AssertEquals('and it is stored verbatim',
    DateOf(EncodeDate(2026, 6, 15)), DateOf(FCal.Date));
end;

{ MinDate = MaxDate = 0 is "unbounded" throughout this unit. An unbounded calendar
  must never raise — otherwise every default-constructed calendar becomes a hazard. }
procedure TCalendarRangeTest.TestUnboundedCalendarAcceptsAnyDate;
begin
  AssertEquals('no bounds -> no guard',
    '', AssignAndCatch(EncodeDate(1900, 1, 1)));
  AssertEquals('the far date is stored verbatim',
    DateOf(EncodeDate(1900, 1, 1)), DateOf(FCal.Date));
end;

procedure TCalendarRangeTest.TestOnlyMaxBoundStillGuards;
begin
  FCal.MaxDate := EncodeDate(2026, 6, 30);
  AssertTrue('a half-open range still guards its closed end',
    AssignAndCatch(EncodeDate(2026, 7, 1)) <> '');
  AssertEquals('and leaves the open end alone',
    '', AssignAndCatch(EncodeDate(1990, 1, 1)));
end;

procedure TCalendarRangeTest.TestOnlyMinBoundStillGuards;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  AssertTrue('a half-open range still guards its closed end',
    AssignAndCatch(EncodeDate(2026, 5, 31)) <> '');
  AssertEquals('and leaves the open end alone',
    '', AssignAndCatch(EncodeDate(2090, 1, 1)));
end;

{ DateTime is the LCL-named alias onto the same storage, and LCL range-checks
  exactly there (calendar.pp:322-339). Both names must behave identically or the
  alias becomes a way to smuggle a bad date past the guard. }
procedure TCalendarRangeTest.TestDateTimeAliasGuardsToo;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 30);
  AssertTrue('DateTime := out-of-range must raise as Date := does',
    AssignDateTimeAndCatch(EncodeDate(2026, 7, 15)) <> '');
end;

{ The clamp did not disappear, it got a name. A caller that genuinely wants
  "put it as close as you can" says so, and the reader can see that it did. }
procedure TCalendarRangeTest.TestSetDateClampedStillClamps;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 10);
  FCal.SetDateClamped(EncodeDate(2026, 6, 25));
  AssertEquals('clamped up to MaxDate',
    DateOf(EncodeDate(2026, 6, 10)), DateOf(FCal.Date));
  FCal.SetDateClamped(EncodeDate(2026, 1, 1));
  AssertEquals('clamped down to MinDate',
    DateOf(EncodeDate(2026, 6, 1)), DateOf(FCal.Date));
end;

procedure TCalendarRangeTest.TestSetDateClampedNeverRaises;
var
  raised: string;
begin
  FCal.MinDate := EncodeDate(2026, 6, 1);
  FCal.MaxDate := EncodeDate(2026, 6, 10);
  raised := '';
  try
    FCal.SetDateClamped(EncodeDate(2030, 1, 1));
  except
    on E: Exception do raised := E.ClassName;
  end;
  AssertEquals('the clamping entry point is the quiet one, by contract', '', raised);
end;

{ Tightening a bound past the current date is NOT a bad assignment — the caller
  changed the rules, not the value. LCL clamps here too (ApplyLimits,
  calendar.pp:353-361); raising would make MinDate/MaxDate unusable at run time. }
procedure TCalendarRangeTest.TestTighteningMaxDateClampsInsteadOfRaising;
var
  raised: string;
begin
  FCal.Date := EncodeDate(2026, 6, 25);
  raised := '';
  try
    FCal.MaxDate := EncodeDate(2026, 6, 10);
  except
    on E: Exception do raised := E.ClassName;
  end;
  AssertEquals('tightening MaxDate must not raise', '', raised);
  AssertEquals('it clamps the standing date',
    DateOf(EncodeDate(2026, 6, 10)), DateOf(FCal.Date));
end;

procedure TCalendarRangeTest.TestTighteningMinDateClampsInsteadOfRaising;
var
  raised: string;
begin
  FCal.Date := EncodeDate(2026, 6, 5);
  raised := '';
  try
    FCal.MinDate := EncodeDate(2026, 6, 15);
  except
    on E: Exception do raised := E.ClassName;
  end;
  AssertEquals('tightening MinDate must not raise', '', raised);
  AssertEquals('it clamps the standing date',
    DateOf(EncodeDate(2026, 6, 15)), DateOf(FCal.Date));
end;

{ ---------------------- Defect 1: streaming carve-out ---------------------- }

function TCalendarStreamingTest.LoadFromLfmText(const ALfm: string): TTyCalendar;
var
  TextStream, BinStream: TMemoryStream;
begin
  Result := TTyCalendar.Create(nil);
  TextStream := TMemoryStream.Create;
  BinStream  := TMemoryStream.Create;
  try
    TextStream.Write(ALfm[1], Length(ALfm));
    TextStream.Position := 0;
    ObjectTextToBinary(TextStream, BinStream);
    BinStream.Position := 0;
    BinStream.ReadComponent(Result);
  finally
    BinStream.Free;
    TextStream.Free;
  end;
end;

{ The bounds land first, then a date outside them. With a raising setter and no
  csLoading carve-out this is an EInvalidDate escaping ReadComponent — i.e. the
  whole form refuses to open because one date drifted out of range. }
procedure TCalendarStreamingTest.TestBoundsBeforeDateStillLoads;
var
  Cal: TTyCalendar;
begin
  Cal := nil;
  try
    Cal := LoadFromLfmText(
      'object Cal1: TTyCalendar'#13#10 +
      '  MinDate = 46023'#13#10 +      // 2026-01-01
      '  MaxDate = 46387'#13#10 +      // 2026-12-31
      '  Date = 47000'#13#10 +         // 2028-09-26 — well past MaxDate
      'end'#13#10);
    AssertNotNull('the component loaded at all', Cal);
    AssertEquals('the out-of-range streamed date was clamped, not fatal',
      DateOf(46387.0), DateOf(Cal.Date));
  finally
    Cal.Free;
  end;
end;

{ The order the IDE actually writes (Date is declared before MinDate/MaxDate), so
  the date arrives while the calendar is still unbounded and the bounds re-clamp
  it afterwards. Pinned so a later property reorder cannot silently change which
  of the two paths a real .lfm takes. }
procedure TCalendarStreamingTest.TestDateBeforeBoundsStillLoads;
var
  Cal: TTyCalendar;
begin
  Cal := nil;
  try
    Cal := LoadFromLfmText(
      'object Cal2: TTyCalendar'#13#10 +
      '  Date = 47000'#13#10 +
      '  MinDate = 46023'#13#10 +
      '  MaxDate = 46387'#13#10 +
      'end'#13#10);
    AssertNotNull('the component loaded at all', Cal);
    AssertEquals('the bounds clamped it on arrival',
      DateOf(46387.0), DateOf(Cal.Date));
  finally
    Cal.Free;
  end;
end;

{ =========================== Defect 2: TTyCheckGroup ========================= }

procedure TCheckGroupRangeTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FGrp  := TTyCheckGroup.Create(FForm);
  FGrp.Parent := FForm;
end;

procedure TCheckGroupRangeTest.TearDown;
begin
  FreeAndNil(FForm);   // owns FGrp
  FGrp := nil;
end;

function TCheckGroupRangeTest.ReadAndCatch(AIndex: Integer): string;
var
  b: Boolean;
begin
  Result := '';
  try
    b := FGrp.Checked[AIndex];
    if b then Result := '';      // silence the "assigned and never used" hint
  except
    on E: Exception do Result := E.ClassName + '|' + E.Message;
  end;
end;

function TCheckGroupRangeTest.WriteAndCatch(AIndex: Integer; AValue: Boolean): string;
begin
  Result := '';
  try
    FGrp.Checked[AIndex] := AValue;
  except
    on E: Exception do Result := E.ClassName + '|' + E.Message;
  end;
end;

procedure TCheckGroupRangeTest.TestReadAboveRangeRaises;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  AssertTrue('Checked[2] on a 2-item group must raise, not answer False',
    ReadAndCatch(2) <> '');
end;

procedure TCheckGroupRangeTest.TestReadBelowRangeRaises;
begin
  FGrp.Items.Add('A');
  AssertTrue('Checked[-1] must raise', ReadAndCatch(-1) <> '');
end;

procedure TCheckGroupRangeTest.TestWriteAboveRangeRaises;
begin
  FGrp.Items.Add('A');
  AssertTrue('a write past the end must raise, not be dropped',
    WriteAndCatch(9, True) <> '');
end;

procedure TCheckGroupRangeTest.TestWriteBelowRangeRaises;
begin
  FGrp.Items.Add('A');
  AssertTrue('a negative write must raise', WriteAndCatch(-1, True) <> '');
end;

{ LCL's rsIndexOutOfBounds is '%s Index %d out of bounds 0 .. %d' filled with
  ClassName / the bad index / Count-1. Reproduce all three facts: an off-by-one in
  a form with six groups on it is only actionable if the message says WHICH group
  and HOW far off. }
procedure TCheckGroupRangeTest.TestMessageNamesClassIndexAndMaximum;
var
  msg: string;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  msg := ReadAndCatch(7);
  AssertTrue('names the class, got: ' + msg, Pos('TTyCheckGroup', msg) > 0);
  AssertTrue('names the offending index, got: ' + msg, Pos('7', msg) > 0);
  AssertTrue('names the maximum valid index, got: ' + msg, Pos('2', msg) > 0);
end;

procedure TCheckGroupRangeTest.TestInRangeAccessStaysSilent;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  AssertEquals('an in-range read is quiet', '', ReadAndCatch(1));
  AssertEquals('an in-range write is quiet', '', WriteAndCatch(1, True));
  AssertTrue('and the write landed', FGrp.Checked[1]);
end;

{ An empty group has NO valid index: the old code answered False for every one of
  them, which is indistinguishable from a real unchecked item and is exactly how a
  populate-then-read ordering bug hides. }
procedure TCheckGroupRangeTest.TestEmptyGroupRaisesForEveryIndex;
begin
  AssertTrue('index 0 of an empty group is out of range', ReadAndCatch(0) <> '');
  AssertTrue('so is a write', WriteAndCatch(0, True) <> '');
end;

procedure TCheckGroupRangeTest.TestRejectedWriteChangesNothing;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Checked[0] := True;
  WriteAndCatch(5, True);
  AssertTrue('the real items are untouched by a rejected write', FGrp.Checked[0]);
  AssertFalse('and the other one too', FGrp.Checked[1]);
  AssertEquals('CheckedCount is unchanged', 1, FGrp.CheckedCount);
end;

{ ========================== Defect 3: TabHeight ============================= }

function TStripProbe.GetTabCount: Integer;
begin
  Result := 2;
end;

function TStripProbe.GetTabCaption(AIndex: Integer): string;
begin
  if AIndex = 0 then Result := 'One' else Result := 'Two';
end;

procedure TStripProbe.Invalidate;
begin
  Inc(FRepaints);
  inherited Invalidate;
end;

{ The device-px top inset the strip claims from its client rect — what the pages
  actually sit below, and the only end-to-end evidence that TabHeight took effect. }
function TStripProbe.ClientTopInset: Integer;
var
  R: TRect;
begin
  R := Rect(0, 0, 300, 200);
  AdjustClientRect(R);
  Result := R.Top;
end;

procedure TTabHeightSentinelTest.SetUp;
begin
  TyRegisterBuiltinThemes;
  FCtl := TTyStyleController.Create(nil);
  FCtl.ThemeName := 'default';
  FStrip := TStripProbe.Create(nil);
  FStrip.Controller := FCtl;
  FStrip.SetBounds(0, 0, 300, 200);
end;

procedure TTabHeightSentinelTest.TearDown;
begin
  FreeAndNil(FStrip);
  FreeAndNil(FCtl);
end;

{ Kept deliberately: 0 = no strip at all is a shipped capability (the tabcontrol
  example toggles it live) and LCL has no TabHeight value that reaches it — it
  spells the same thing ShowTabs := False. Turning 0 into "auto" for parity would
  delete the feature, so 0 stays and the AUTO meaning gets its own name below. }
procedure TTabHeightSentinelTest.TestZeroStillMeansNoStrip;
begin
  FStrip.TabHeight := 0;
  AssertEquals('no strip means no client inset at all', 0, FStrip.ClientTopInset);
end;

procedure TTabHeightSentinelTest.TestZeroSurvivesTheGetter;
begin
  FStrip.TabHeight := 0;
  AssertEquals('0 reads back as 0, not as the theme height', 0, FStrip.TabHeight);
end;

procedure TTabHeightSentinelTest.TestUnsetFollowsTheDensityToken;
var
  classicH, modernH: Integer;
begin
  FCtl.Density := tdClassic;
  classicH := FStrip.TabHeight;
  FCtl.Density := tdModern;
  modernH := FStrip.TabHeight;
  AssertEquals('classic keeps the historical 28', 28, classicH);
  AssertTrue('unset follows --control-height into modern density', modernH > classicH);
end;

{ THE fix for "0 means two different things": the auto meaning is reachable under
  a name instead of being unreachable once a host pins a height. Without this a
  pinned strip can never go back to following the theme, and the only value that
  looked like "auto" (0) silently hides it. }
procedure TTabHeightSentinelTest.TestAutoSentinelUnpinsBackToTheTheme;
var
  themeH: Integer;
begin
  FCtl.Density := tdModern;
  themeH := FStrip.TabHeight;          // unset -> follows the token
  FStrip.TabHeight := 44;
  AssertEquals('pinned wins', 44, FStrip.TabHeight);
  FStrip.TabHeight := TyTabHeightAuto;
  AssertEquals('and TyTabHeightAuto hands it back to the theme',
    themeH, FStrip.TabHeight);
end;

{ The two sentinels must not collapse into each other: LCL treats every value <= 0
  as auto, so a ported `TabHeight := -1` must NOT land on our hidden strip. }
procedure TTabHeightSentinelTest.TestAutoSentinelIsNotConfusedWithHidden;
begin
  FStrip.TabHeight := TyTabHeightAuto;
  AssertTrue('auto is a visible strip', FStrip.ClientTopInset > 0);
  FStrip.TabHeight := -5;
  AssertTrue('any negative reads as auto, as it does in LCL',
    FStrip.ClientTopInset > 0);
end;

{ At modern density an unset strip is taller than the classic fallback field value.
  Pinning that fallback SHRINKS the strip — but the old guard compared the raw
  field (already 28) instead of the effective height (38) and returned early, so
  the pages were never re-aligned and kept covering the strip. Same failure the
  TabHeight := 30 report described, reached from the other side. }
procedure TTabHeightSentinelTest.TestPinningTheFallbackValueIsNotANoOp;
var
  before, effBefore: Integer;
begin
  FCtl.Density := tdModern;
  effBefore := FStrip.TabHeight;
  AssertTrue('precondition: modern is taller than the classic fallback 28',
    effBefore > 28);
  before := FStrip.Repaints;
  FStrip.TabHeight := 28;              // equal to the raw field, NOT to the effect
  AssertEquals('the effective height really did change', 28, FStrip.TabHeight);
  AssertTrue('so the band shrinking must have been acted on, not just recorded',
    FStrip.Repaints > before);
end;

procedure TTabHeightSentinelTest.TestUnpinningIsNotANoOp;
var
  before: Integer;
begin
  FCtl.Density := tdModern;
  FStrip.TabHeight := 28;
  before := FStrip.Repaints;
  FStrip.TabHeight := TyTabHeightAuto;
  AssertTrue('going back to auto changes the height, so it must be acted on',
    FStrip.Repaints > before);
end;

{ 0 must round-trip through a .lfm. LCL streams TabHeight only when > 0, which for
  us would drop the "no strip" design decision on every reload — so the stored
  condition deliberately tracks "the host pinned it", not "it is positive". }
procedure TTabHeightSentinelTest.TestExplicitHeightIsStreamedAndZeroRoundTrips;
var
  MS: TMemoryStream;
  Src, Dst: TStripProbe;
begin
  MS  := TMemoryStream.Create;
  Src := TStripProbe.Create(nil);
  Dst := TStripProbe.Create(nil);
  try
    Src.Name := 'Strip1';
    Src.TabHeight := 0;
    MS.WriteComponent(Src);
    MS.Position := 0;
    MS.ReadComponent(Dst);
    AssertEquals('a pinned 0 survives streaming', 0, Dst.TabHeight);
    AssertEquals('and still means no strip', 0, Dst.ClientTopInset);
  finally
    Dst.Free;
    Src.Free;
    MS.Free;
  end;
end;

initialization
  RegisterClasses([TStripProbe]);
  RegisterTest(TCalendarRangeTest);
  RegisterTest(TCalendarStreamingTest);
  RegisterTest(TCheckGroupRangeTest);
  RegisterTest(TTabHeightSentinelTest);
end.
