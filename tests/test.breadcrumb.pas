unit test.breadcrumb;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Breadcrumb;

type
  { Pure-rules tests: the link rule, the state rule, the overflow rule and the geometry all
    take only integers, so they run with no window handle, no theme and no control at all. }
  TTyBreadcrumbRulesTest = class(TTestCase)
  published
    procedure TestAncestorsAreLinks;
    procedure TestTheLastCrumbIsNotALink;
    procedure TestTheEllipsisIsNotALink;
    procedure TestALoneCrumbIsNotALink;
    procedure TestTheCurrentCrumbIsSelected;
    procedure TestALinkRestsNormalAndHovers;
    procedure TestTheEllipsisRestsLikeALink;
    procedure TestDisabledKeepsSelectedAndDropsHover;
    procedure TestCrumbWidthIsPadTextPad;
    procedure TestSepAdvanceIsAirOnBothSides;
    procedure TestTrailWidthPutsOneMarkBetweenEachPair;
    procedure TestWholeTrailFitsUnelided;
    procedure TestOneTooNarrowElidesExactlyOneCrumb;
    procedure TestTheTailGrowsBackWhileItFits;
    procedure TestTheRootIsDroppedWhenItCannotFit;
    procedure TestTheFloorIsWhereYouAre;
    procedure TestATwoCrumbTrailElidesTheRoot;
    procedure TestAnEmptyTrailHasAnEmptyPlan;
    procedure TestThePlanAlwaysEndsWhereYouAre;
    procedure TestTheMarkAlwaysHidesSomething;
    procedure TestAnElidedPlanFitsTheBand;
    procedure TestCrumbsAndMarksTileLeftToRight;
    procedure TestTheBandIsInsetByTheBarPadding;
    procedure TestTheMarkIsCentredInTheBand;
    procedure TestNoMarkAfterTheLastCrumb;
    procedure TestASlotPerPlanEntryAlways;
    procedure TestAnOverflowingCrumbIsClampedNotInverted;
    procedure TestPaddingThatEatsTheBarLeavesNothing;
    procedure TestZeroSizeLeavesNothing;
    procedure TestIndexAtIsTheInverseOfLayout;
    procedure TestIndexAtMarksAndAirAreNone;
    procedure TestPreferredWidthRoundTrips;
    procedure TestPreferredHeightClearsTheMarkSlot;
  end;

  { Headless control behaviour: typeKey, defaults, theme-driven geometry and metrics, the
    click rules, AutoSize measurement, and graceful degradation when a key is undefined. }
  TTyBreadcrumbControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FFired: Integer;      // OnCrumbClick fire count
    FFiredIndex: Integer; // and the index it last carried
    procedure HandleCrumbClick(Sender: TObject; AIndex: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestCrumbsSitInTheThemedBarPadding;
    procedure TestTheSeparatorSizeMetricRetunesTheRhythm;
    procedure TestTheSeparatorGapMetricRetunesTheRhythm;
    procedure TestCrumbAtIsTheInverseOfCrumbRect;
    procedure TestClickingALinkFiresOnCrumbClick;
    procedure TestBackgroundlessBarIsNotClickable;
    procedure TestClickingTheCurrentCrumbFiresNothing;
    procedure TestDraggingOffALinkCancels;
    procedure TestADisabledTrailIgnoresAClick;
    procedure TestAWideBarShowsEveryCrumb;
    procedure TestANarrowBarElidesTheMiddle;
    procedure TestAnElidedCrumbHasNoRect;
    procedure TestClickingTheMarkFiresNothing;
    procedure TestShrinkingItemsClearsAStrandedHover;
    procedure TestPreferredWidthHugsTheWholeTrail;
    procedure TestPreferredWidthGrowsWithACrumb;
    procedure TestPreferredHeightClearsTheSeparatorMetric;
    procedure TestTheBarRendersItsThemeBackground;
    procedure TestTheCurrentCrumbTakesTheSelectedStyle;
    procedure TestAHoveredLinkLightsUp;
    procedure TestTheCurrentCrumbNeverLightsUp;
    procedure TestADisabledTrailKeepsTheCurrentPlate;
    procedure TestTheSeparatorTakesTheBarInk;
    procedure TestAnUndefinedBarKeyDrawsNothing;
    procedure TestAnUndefinedItemKeyStillDrawsCrumbsInTheBarInk;
  end;

implementation

{ The pure tests all speak the same trail so the arithmetic in each is checkable by eye:
  four crumbs 40/50/60/30 px wide, a 20px '…', and a 10px mark with 5px of air each side —
  so one mark advances the trail by exactly 20px and the whole trail is 240px. }
const
  W0 = 40; W1 = 50; W2 = 60; W3 = 30;
  ELLIP = 20;
  SEPSZ = 10; SEPGAP = 5;
  SEPADV = SEPGAP + SEPSZ + SEPGAP;              // 20
  TRAILW = W0 + W1 + W2 + W3 + 3 * SEPADV;       // 240

{ A plan rendered for an assertion message: '0,-1,2,3'. Comparing the whole plan as one
  string says WHICH crumbs came out wrong, where a length + spot check would only say that
  something did. }
function PlanText(const APlan: TTyBreadcrumbPlan): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(APlan) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(APlan[i]);
  end;
end;

function Trail4(AAvail: Integer): TTyBreadcrumbPlan;
begin
  Result := TyBreadcrumbVisiblePlan(AAvail, [W0, W1, W2, W3], ELLIP, SEPSZ, SEPGAP);
end;

{ TTyBreadcrumbRulesTest }

procedure TTyBreadcrumbRulesTest.TestAncestorsAreLinks;
begin
  // Everything before the end is somewhere you can go.
  AssertTrue('the root is a link', TyBreadcrumbIsLink(0, 4));
  AssertTrue('a middle crumb is a link', TyBreadcrumbIsLink(1, 4));
  AssertTrue('the last-but-one is a link', TyBreadcrumbIsLink(2, 4));
end;

procedure TTyBreadcrumbRulesTest.TestTheLastCrumbIsNotALink;
begin
  // The whole visual grammar of a breadcrumb: the end of the trail is where you already
  // are, so it is text, not a link.
  AssertFalse('the current location is not a link', TyBreadcrumbIsLink(3, 4));
  AssertFalse('and neither is anything past the end', TyBreadcrumbIsLink(4, 4));
end;

procedure TTyBreadcrumbRulesTest.TestTheEllipsisIsNotALink;
begin
  // The mark stands for crumbs that were dropped; it is not one of them.
  AssertFalse('the mark is not a place',
    TyBreadcrumbIsLink(TyBreadcrumbEllipsisIndex, 4));
end;

procedure TTyBreadcrumbRulesTest.TestALoneCrumbIsNotALink;
begin
  // One crumb IS the current location, so a one-crumb trail has no links at all.
  AssertFalse('a lone crumb is where you are', TyBreadcrumbIsLink(0, 1));
  AssertFalse('an empty trail has no links', TyBreadcrumbIsLink(0, 0));
end;

procedure TTyBreadcrumbRulesTest.TestTheCurrentCrumbIsSelected;
begin
  // tysSelected, the same resting state TTyButton.Down and a chosen segment carry, so one
  // ':selected' theme rule styles all three.
  AssertTrue('the current crumb is :selected',
    tysSelected in TyBreadcrumbItemStates(3, 4, False, True));
  AssertFalse('and it is not also :normal',
    tysNormal in TyBreadcrumbItemStates(3, 4, False, True));
end;

procedure TTyBreadcrumbRulesTest.TestALinkRestsNormalAndHovers;
begin
  AssertTrue('a resting link is :normal',
    TyBreadcrumbItemStates(0, 4, False, True) = [tysNormal]);
  AssertTrue('a hovered link is :hover',
    TyBreadcrumbItemStates(0, 4, True, True) = [tysHover]);
  AssertFalse('a link is never :selected',
    tysSelected in TyBreadcrumbItemStates(0, 4, True, True));
end;

procedure TTyBreadcrumbRulesTest.TestTheEllipsisRestsLikeALink;
begin
  // The mark must NOT be dressed as the current location — it stands for a dropped run,
  // not for where you are. (-1 = ACount-1 would match on an empty trail; the rule guards.)
  AssertTrue('the mark rests :normal',
    TyBreadcrumbItemStates(TyBreadcrumbEllipsisIndex, 4, False, True) = [tysNormal]);
  AssertTrue('and still does on an empty trail',
    TyBreadcrumbItemStates(TyBreadcrumbEllipsisIndex, 0, False, True) = [tysNormal]);
end;

procedure TTyBreadcrumbRulesTest.TestDisabledKeepsSelectedAndDropsHover;
begin
  // A greyed-out trail must still say WHERE you are, so :selected survives; a disabled
  // control takes no hover, so that does not.
  AssertTrue('disabled keeps :selected on the current crumb',
    TyBreadcrumbItemStates(3, 4, False, False) = [tysSelected, tysDisabled]);
  AssertTrue('disabled swallows a link''s hover',
    TyBreadcrumbItemStates(0, 4, True, False) = [tysDisabled]);
end;

procedure TTyBreadcrumbRulesTest.TestCrumbWidthIsPadTextPad;
begin
  AssertEquals('pad + text + pad', 58, TyBreadcrumbCrumbWidth(50, 4, 4));
  // Negatives are clamped once, at the door, so no caller has to.
  AssertEquals('negatives clamp to zero', 0, TyBreadcrumbCrumbWidth(-5, -1, -1));
end;

procedure TTyBreadcrumbRulesTest.TestSepAdvanceIsAirOnBothSides;
begin
  AssertEquals('gap + slot + gap', 20, TyBreadcrumbSepAdvance(SEPSZ, SEPGAP));
  AssertEquals('no air, just the slot', 10, TyBreadcrumbSepAdvance(10, 0));
  AssertEquals('negatives clamp to zero', 0, TyBreadcrumbSepAdvance(-3, -3));
end;

procedure TTyBreadcrumbRulesTest.TestTrailWidthPutsOneMarkBetweenEachPair;
begin
  // n crumbs, n-1 marks.
  AssertEquals('four crumbs, three marks', TRAILW,
    TyBreadcrumbTrailWidth([W0, W1, W2, W3], SEPSZ, SEPGAP));
  AssertEquals('one crumb, no mark', W0, TyBreadcrumbTrailWidth([W0], SEPSZ, SEPGAP));
  AssertEquals('no crumbs, nothing', 0, TyBreadcrumbTrailWidth([], SEPSZ, SEPGAP));
end;

procedure TTyBreadcrumbRulesTest.TestWholeTrailFitsUnelided;
begin
  // Exactly enough room is enough: no mark, no decisions, the whole path.
  AssertEquals('an exact fit shows everything', '0,1,2,3', PlanText(Trail4(TRAILW)));
  AssertEquals('and so does a roomy band', '0,1,2,3', PlanText(Trail4(TRAILW + 500)));
end;

procedure TTyBreadcrumbRulesTest.TestOneTooNarrowElidesExactlyOneCrumb;
begin
  { One px short of the whole trail. The rule keeps the root (which tree this is), keeps the
    end (where you are), and drops the LEAST useful ancestor — the one furthest from the
    end — replacing it with the mark. Only crumb 1 goes: at 239 there is room for
    40 + 20 + 20(mark) + 20 + 60 + 20 + 30 = 210. }
  AssertEquals('the far ancestor is what goes', '0,-1,2,3', PlanText(Trail4(TRAILW - 1)));
end;

procedure TTyBreadcrumbRulesTest.TestTheTailGrowsBackWhileItFits;
begin
  // 209 is one px short of holding crumb 2 as well (see above), so the mark swallows the
  // whole run 1..2 and the trail is root -> mark -> here.
  AssertEquals('the tail stops where the room does', '0,-1,3', PlanText(Trail4(209)));
  AssertEquals('and one more px buys crumb 2 back', '0,-1,2,3', PlanText(Trail4(210)));
end;

procedure TTyBreadcrumbRulesTest.TestTheRootIsDroppedWhenItCannotFit;
begin
  { 'root -> mark -> here' costs 40+20+20+20+30 = 130. At 129 even the root has to go, and
    the mark then stands for it too: 'mark -> here' = 20+20+30 = 70. Crumb 2 would need
    another 80 (60 + a mark), which 129 has not got. }
  AssertEquals('the root is not sacred either', '-1,3', PlanText(Trail4(129)));
  AssertEquals('one more px and it comes back', '0,-1,3', PlanText(Trail4(130)));
end;

procedure TTyBreadcrumbRulesTest.TestTheFloorIsWhereYouAre;
begin
  // Not even 'mark -> here' (70px) fits: show where you ARE and let the paint ellipsise it.
  // A bar showing only '…' would have said nothing at all.
  AssertEquals('the floor keeps the current location', '3', PlanText(Trail4(69)));
  AssertEquals('and a band of nothing still does', '3', PlanText(Trail4(0)));
end;

procedure TTyBreadcrumbRulesTest.TestATwoCrumbTrailElidesTheRoot;
var
  plan: TTyBreadcrumbPlan;
begin
  { With two crumbs there is nothing BETWEEN root and end for a mark to stand for, so the
    'root -> mark -> tail' form cannot apply — but the root itself can still be dropped.
    Trail = 40 + 20 + 30 = 90; at 89 the answer is 'mark -> here' (70), NOT a clipped
    'root -> here', which would spend the room on the root and clip the one crumb that
    matters clean off the band. }
  plan := TyBreadcrumbVisiblePlan(90, [W0, W3], ELLIP, SEPSZ, SEPGAP);
  AssertEquals('an exact fit shows both', '0,1', PlanText(plan));
  plan := TyBreadcrumbVisiblePlan(89, [W0, W3], ELLIP, SEPSZ, SEPGAP);
  AssertEquals('one px short drops the root, not the end', '-1,1', PlanText(plan));
end;

procedure TTyBreadcrumbRulesTest.TestAnEmptyTrailHasAnEmptyPlan;
begin
  AssertEquals('nothing to show', 0,
    Length(TyBreadcrumbVisiblePlan(500, [], ELLIP, SEPSZ, SEPGAP)));
  AssertEquals('and no mark invented for it', 0,
    Length(TyBreadcrumbVisiblePlan(0, [], ELLIP, SEPSZ, SEPGAP)));
end;

procedure TTyBreadcrumbRulesTest.TestThePlanAlwaysEndsWhereYouAre;
var
  avail: Integer;
  plan: TTyBreadcrumbPlan;
begin
  { The one invariant the whole rule exists to protect, swept across every band width from
    nothing to roomy: a breadcrumb that has lost the current location has stopped being a
    breadcrumb. }
  for avail := 0 to TRAILW + 40 do
  begin
    plan := Trail4(avail);
    AssertTrue(Format('avail=%d: a real trail never plans to nothing', [avail]),
      Length(plan) > 0);
    AssertEquals(Format('avail=%d: the trail ends where you are', [avail]), 3,
      plan[High(plan)]);
  end;
end;

procedure TTyBreadcrumbRulesTest.TestTheMarkAlwaysHidesSomething;
var
  avail, i, shown: Integer;
  plan: TTyBreadcrumbPlan;
  marked: Boolean;
begin
  // A '…' that hides nothing is a lie about the path. Sweep every band width and check the
  // mark only ever appears alongside a genuinely shortened trail.
  for avail := 0 to TRAILW + 40 do
  begin
    plan := Trail4(avail);
    marked := False;
    shown := 0;
    for i := 0 to High(plan) do
      if plan[i] = TyBreadcrumbEllipsisIndex then marked := True else Inc(shown);
    if marked then
      AssertTrue(Format('avail=%d: the mark stands for at least one dropped crumb', [avail]),
        shown < 4);
  end;
end;

procedure TTyBreadcrumbRulesTest.TestAnElidedPlanFitsTheBand;
var
  avail, i, used: Integer;
  plan: TTyBreadcrumbPlan;
  src: array[0..3] of Integer;
begin
  { The other half of the contract: whatever the rule chooses must actually FIT, or the
    elision bought nothing. The floor (a lone crumb the band cannot hold) is the one
    documented exception — there is nothing narrower to fall back to. }
  src[0] := W0; src[1] := W1; src[2] := W2; src[3] := W3;
  for avail := 0 to TRAILW + 40 do
  begin
    plan := Trail4(avail);
    if Length(plan) < 2 then Continue;   // the floor: it is allowed to overflow
    used := High(plan) * SEPADV;
    for i := 0 to High(plan) do
      if plan[i] = TyBreadcrumbEllipsisIndex then
        Inc(used, ELLIP)
      else
        Inc(used, src[plan[i]]);
    AssertTrue(Format('avail=%d: the plan (%s) is %dpx and must fit',
      [avail, PlanText(plan), used]), used <= avail);
  end;
end;

procedure TTyBreadcrumbRulesTest.TestCrumbsAndMarksTileLeftToRight;
var
  S: TTyBreadcrumbSlots;
begin
  { 300x30, bar padding 4/3/4/3 -> the band is x 4..296, y 3..27. The crumbs and the marks
    advance the trail in step: 40, then 20 for the mark, then 50, ... }
  S := TyBreadcrumbLayout(300, 30, [0, 1, 2, 3], [W0, W1, W2, W3], ELLIP,
    4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('the root starts at the band', 4, S[0].ItemRect.Left);
  AssertEquals('and is exactly its measured width', 44, S[0].ItemRect.Right);
  AssertEquals('the mark opens a gap after it', 49, S[0].SepRect.Left);
  AssertEquals('and is the themed slot wide', 59, S[0].SepRect.Right);
  AssertEquals('the next crumb starts a gap past the mark', 64, S[1].ItemRect.Left);
  AssertEquals('at its own width', 114, S[1].ItemRect.Right);
  AssertEquals('and so on', 134, S[2].ItemRect.Left);
  AssertEquals('to the last', 214, S[3].ItemRect.Left);
  AssertEquals('which ends at the trail width', 244, S[3].ItemRect.Right);
end;

procedure TTyBreadcrumbRulesTest.TestTheBandIsInsetByTheBarPadding;
var
  S: TTyBreadcrumbSlots;
begin
  // A crumb spans the band's FULL height: the chip is the whole crumb, and so is its hit
  // target.
  S := TyBreadcrumbLayout(300, 30, [0, 1, 2, 3], [W0, W1, W2, W3], ELLIP,
    9, 5, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('the trail starts at the left padding', 9, S[0].ItemRect.Left);
  AssertEquals('a crumb tops at the top padding', 5, S[0].ItemRect.Top);
  AssertEquals('and bottoms at the bottom padding', 27, S[0].ItemRect.Bottom);
end;

procedure TTyBreadcrumbRulesTest.TestTheMarkIsCentredInTheBand;
var
  S: TTyBreadcrumbSlots;
begin
  // Band y 3..27 (24 tall), slot 10 -> top = 3 + (24-10) div 2 = 10.
  S := TyBreadcrumbLayout(300, 30, [0, 1], [W0, W1], ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('mark top centred in the band', 10, S[0].SepRect.Top);
  AssertEquals('mark bottom', 20, S[0].SepRect.Bottom);
  // A band shorter than the slot squashes it into the band rather than overflowing.
  S := TyBreadcrumbLayout(300, 12, [0, 1], [W0, W1], ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('a short band floors the mark at its top', 3, S[0].SepRect.Top);
  AssertEquals('and clamps it to the band', 9, S[0].SepRect.Bottom);
end;

procedure TTyBreadcrumbRulesTest.TestNoMarkAfterTheLastCrumb;
var
  S: TTyBreadcrumbSlots;
begin
  S := TyBreadcrumbLayout(300, 30, [0, 1, 2, 3], [W0, W1, W2, W3], ELLIP,
    4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertTrue('the trail ends with a crumb, not a mark',
    S[3].SepRect.Right - S[3].SepRect.Left = 0);
  S := TyBreadcrumbLayout(300, 30, [0], [W0], ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('a lone crumb has no mark', 0, S[0].SepRect.Right - S[0].SepRect.Left);
end;

procedure TTyBreadcrumbRulesTest.TestASlotPerPlanEntryAlways;
var
  S: TTyBreadcrumbSlots;
begin
  // The invariant the paint relies on: it walks the plan and the slots together.
  S := TyBreadcrumbLayout(300, 30, [0, TyBreadcrumbEllipsisIndex, 3], [W0, W1, W2, W3],
    ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('one slot per plan entry', 3, Length(S));
  AssertEquals('and each carries its own index', 0, S[0].ItemIndex);
  AssertEquals('the mark included', TyBreadcrumbEllipsisIndex, S[1].ItemIndex);
  AssertEquals('through to the end', 3, S[2].ItemIndex);
  // The mark is laid out at the '…' width, not at the width of some crumb.
  AssertEquals('the mark takes the ellipsis width', ELLIP,
    S[1].ItemRect.Right - S[1].ItemRect.Left);
end;

procedure TTyBreadcrumbRulesTest.TestAnOverflowingCrumbIsClampedNotInverted;
var
  S: TTyBreadcrumbSlots;
begin
  { A plan wider than its band (only the FLOOR case can produce one, but the layout must
    survive any): the band clips, the paint ellipsises, and nothing inverts. 100 wide, pad
    4/4 -> band 4..96. Crumb 0 fits, crumb 1 is clipped, crumbs 2-3 are past the edge. }
  S := TyBreadcrumbLayout(100, 30, [0, 1, 2, 3], [W0, W1, W2, W3], ELLIP,
    4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('the first crumb is untouched', 44, S[0].ItemRect.Right);
  AssertEquals('the second is clipped at the band', 96, S[1].ItemRect.Right);
  AssertTrue('and is not inverted', S[1].ItemRect.Right > S[1].ItemRect.Left);
  AssertEquals('the mark that ran off is empty', 0, S[1].SepRect.Right - S[1].SepRect.Left);
  AssertEquals('a crumb past the edge is empty', 0, S[2].ItemRect.Right - S[2].ItemRect.Left);
  AssertEquals('right through to the last', 0, S[3].ItemRect.Right - S[3].ItemRect.Left);
end;

procedure TTyBreadcrumbRulesTest.TestPaddingThatEatsTheBarLeavesNothing;
var
  S: TTyBreadcrumbSlots;
begin
  S := TyBreadcrumbLayout(12, 30, [0, 1], [W0, W1], ELLIP, 8, 3, 8, 3, SEPSZ, SEPGAP);
  AssertEquals('the slots are still there', 2, Length(S));
  AssertEquals('but hold nothing', 0, S[0].ItemRect.Right - S[0].ItemRect.Left);
  AssertEquals('not even a mark', 0, S[0].SepRect.Right - S[0].SepRect.Left);
  // Vertically too.
  S := TyBreadcrumbLayout(300, 4, [0, 1], [W0, W1], ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('vertical padding can eat it too', 0, S[0].ItemRect.Right - S[0].ItemRect.Left);
end;

procedure TTyBreadcrumbRulesTest.TestZeroSizeLeavesNothing;
var
  S: TTyBreadcrumbSlots;
begin
  S := TyBreadcrumbLayout(0, 30, [0, 1], [W0, W1], ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('zero width: no crumb', 0, S[0].ItemRect.Right - S[0].ItemRect.Left);
  S := TyBreadcrumbLayout(300, 0, [0, 1], [W0, W1], ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('zero height: no crumb', 0, S[0].ItemRect.Right - S[0].ItemRect.Left);
end;

procedure TTyBreadcrumbRulesTest.TestIndexAtIsTheInverseOfLayout;
var
  S: TTyBreadcrumbSlots;
  i: Integer;
  R: TRect;
begin
  // Whatever the layout put somewhere, the hit-test finds there — the two can never drift.
  S := TyBreadcrumbLayout(300, 30, [0, 1, 2, 3], [W0, W1, W2, W3], ELLIP,
    4, 3, 4, 3, SEPSZ, SEPGAP);
  for i := 0 to 3 do
  begin
    R := S[i].ItemRect;
    AssertEquals(Format('the centre of crumb %d hits it', [i]), i,
      TyBreadcrumbIndexAt(S, (R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2));
    AssertEquals(Format('crumb %d owns its left edge', [i]), i,
      TyBreadcrumbIndexAt(S, R.Left, R.Top));
    AssertEquals(Format('crumb %d does not own its right edge', [i]), -1,
      TyBreadcrumbIndexAt(S, R.Right, R.Top));
  end;
end;

procedure TTyBreadcrumbRulesTest.TestIndexAtMarksAndAirAreNone;
var
  S: TTyBreadcrumbSlots;
begin
  S := TyBreadcrumbLayout(300, 30, [0, TyBreadcrumbEllipsisIndex, 3], [W0, W1, W2, W3],
    ELLIP, 4, 3, 4, 3, SEPSZ, SEPGAP);
  AssertEquals('the separator belongs to no crumb', -1,
    TyBreadcrumbIndexAt(S, (S[0].SepRect.Left + S[0].SepRect.Right) div 2, 15));
  AssertEquals('the air before the band does not either', -1,
    TyBreadcrumbIndexAt(S, 1, 15));
  AssertEquals('nor the space above it', -1, TyBreadcrumbIndexAt(S, 10, 1));
  AssertEquals('nor anywhere past the trail', -1, TyBreadcrumbIndexAt(S, 295, 15));
  // The mark answers "nothing" through the SAME line as the gutter: its ItemIndex IS -1.
  AssertEquals('and the mark is not a destination', -1,
    TyBreadcrumbIndexAt(S, (S[1].ItemRect.Left + S[1].ItemRect.Right) div 2, 15));
end;

procedure TTyBreadcrumbRulesTest.TestPreferredWidthRoundTrips;
var
  w: Integer;
begin
  // The contract: a bar of TyBreadcrumbPreferredWidth shows the whole trail, and one px
  // narrower does not.
  w := TyBreadcrumbPreferredWidth([W0, W1, W2, W3], 4, 4, SEPSZ, SEPGAP);
  AssertEquals('pad + trail + pad', 248, w);
  AssertEquals('the whole trail fits at exactly that width', '0,1,2,3',
    PlanText(Trail4(w - 4 - 4)));
  AssertTrue('and does not one px under', PlanText(Trail4(w - 4 - 4 - 1)) <> '0,1,2,3');
end;

procedure TTyBreadcrumbRulesTest.TestPreferredHeightClearsTheMarkSlot;
begin
  // A padded text line is the usual driver...
  AssertEquals('pad + line + pad', 22, TyBreadcrumbPreferredHeight(3, 3, 16, SEPSZ));
  // ...but the mark is centred in the BAND, so a band shorter than the slot would squash
  // the glyph: the band must clear the bare slot too.
  AssertEquals('a tall mark floors the band', 29,
    TyBreadcrumbPreferredHeight(3, 3, 16, 23));
end;

{ TTyBreadcrumbControlTest }

type
  { Reaches the protected paint / measure / input seams. The mouse helpers drive the
    handlers in the same order LCL does. }
  TCrumbAccess = class(TTyBreadcrumb)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressReleaseAt(X, Y: Integer);
    procedure PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
    procedure MoveTo(X, Y: Integer);
    { The size AutoSize would fit the bar to. Called directly rather than through AutoSize
      itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent form has no
      handle (the headless runner never realises one), so driving AutoSize here would assert
      on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

function TCrumbAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TCrumbAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TCrumbAccess.PressReleaseAt(X, Y: Integer);
begin
  PressAtReleaseAt(X, Y, X, Y);
end;

procedure TCrumbAccess.PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
begin
  MouseDown(mbLeft, [], ADownX, ADownY);
  MouseUp(mbLeft, [], AUpX, AUpY);
end;

procedure TCrumbAccess.MoveTo(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TCrumbAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

{ Build a themed, parented, 96-PPI breadcrumb over ANames. Shared by nearly every control
  test, which otherwise repeat the same six lines. }
function MakeCrumb(AForm: TForm; ACtl: TTyStyleController;
  const ANames: array of string): TCrumbAccess;
var
  i: Integer;
begin
  Result := TCrumbAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  for i := 0 to High(ANames) do
    Result.Items.Add(ANames[i]);
end;

{ A short, ordinary path. }
function MakePath(AForm: TForm; ACtl: TTyStyleController): TCrumbAccess;
begin
  Result := MakeCrumb(AForm, ACtl, ['Home', 'Documents', 'Reports']);
end;

{ A six-deep path of long names — deep and wide enough that no sane bar holds it, which is
  what the overflow tests need. }
function MakeDeepPath(AForm: TForm; ACtl: TTyStyleController): TCrumbAccess;
begin
  Result := MakeCrumb(AForm, ACtl, ['Root-Volume-Name', 'Level-One-Folder-Name',
    'Level-Two-Folder-Name', 'Level-Three-Folder', 'Level-Four-Folder', 'Current-Location']);
end;

function RenderCrumb(ACtl: TCrumbAccess): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ACtl.Width, ACtl.Height);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, ACtl.Width, ACtl.Height);
    ACtl.RenderTo(Bmp.Canvas, Rect(0, 0, ACtl.Width, ACtl.Height), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ A strongly blue pixel anywhere in R — a themed chip, which nothing else in these tests
  paints (the bars are white and the inks are white, black or green). }
function HasBlueChip(ABmp: TBGRABitmap; const R: TRect): Boolean;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for y := Max(R.Top, 0) to Min(R.Bottom, ABmp.Height) - 1 do
    for x := Max(R.Left, 0) to Min(R.Right, ABmp.Width) - 1 do
    begin
      px := ABmp.GetPixel(x, y);
      if (px.blue > 180) and (px.red < 120) then Exit(True);
    end;
end;

{ A strongly green pixel anywhere in R — themed INK in these tests, never a fill. }
function HasGreenInk(ABmp: TBGRABitmap; const R: TRect): Boolean;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  for y := Max(R.Top, 0) to Min(R.Bottom, ABmp.Height) - 1 do
    for x := Max(R.Left, 0) to Min(R.Right, ABmp.Width) - 1 do
    begin
      px := ABmp.GetPixel(x, y);
      if (px.green > 120) and (px.green > px.red + 30) and (px.green > px.blue + 30) then
        Exit(True);
    end;
end;

function CentreOf(const R: TRect): TPoint;
begin
  Result := Point((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

{ Every control test pins both metrics and both keys: an unpinned metric would make the
  geometry assertions depend on the compiled-in defaults, and a key left OUT of the CSS is
  backed by the base layer (themes/light.tycss is compiled in), so it would not be undefined
  at all. }
const
  BaseCss =
    ':root { --breadcrumb-separator-size: 10px; --breadcrumb-separator-gap: 5px; }' +
    'TyBreadcrumb { background: #FFFFFF; color: #999999; padding: 3px 4px; font-size: 12px; }' +
    'TyBreadcrumbItem { color: #111111; padding: 0px 4px; }';

procedure TTyBreadcrumbControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FFired := 0;
  FFiredIndex := -99;
end;

procedure TTyBreadcrumbControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyBreadcrumbControlTest.HandleCrumbClick(Sender: TObject; AIndex: Integer);
begin
  Inc(FFired);
  FFiredIndex := AIndex;
end;

procedure TTyBreadcrumbControlTest.TestTypeKey;
var
  T: TCrumbAccess;
begin
  T := TCrumbAccess.Create(FForm);
  T.Parent := FForm;
  try
    AssertEquals('TyBreadcrumb', T.StyleTypeKey);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestDefaults;
var
  T: TTyBreadcrumb;
begin
  T := TTyBreadcrumb.Create(FForm);
  try
    AssertEquals('an empty trail by default', 0, T.Count);
    AssertEquals('default width 300', 300, T.Width);
    AssertEquals('default height 24', 24, T.Height);
    AssertEquals('an empty trail plans nothing', 0, Length(T.TyVisiblePlan));
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestCrumbsSitInTheThemedBarPadding;
var
  T: TCrumbAccess;
  R: TRect;
begin
  // The band is driven by the THEME's padding, not by a literal.
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    R := T.TyCrumbRect(0);
    AssertEquals('the trail starts at the themed left padding', 4, R.Left);
    AssertEquals('a crumb tops at the themed top padding', 3, R.Top);
    AssertEquals('and bottoms at the themed bottom padding', 27, R.Bottom);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestTheSeparatorSizeMetricRetunesTheRhythm;
var
  T: TCrumbAccess;
  S: TTyBreadcrumbSlots;
begin
  { --breadcrumb-separator-size is a skin-tunable metric. The PITCH between two crumbs is
    gap + slot + gap, which is checkable without ever measuring a glyph (headless text
    metrics are not the real GUI's): the distance from crumb 0's right edge to crumb 1's
    left edge must be exactly that. }
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    S := T.TyCrumbSlots;
    AssertEquals('the slot takes the themed size', 10, S[0].SepRect.Right - S[0].SepRect.Left);
    AssertEquals('and the pitch is gap + slot + gap', 20,
      S[1].ItemRect.Left - S[0].ItemRect.Right);

    FCtl.LoadThemeCss(StringReplace(BaseCss, '--breadcrumb-separator-size: 10px',
      '--breadcrumb-separator-size: 20px', []));
    S := T.TyCrumbSlots;
    AssertEquals('a bigger slot is honoured', 20, S[0].SepRect.Right - S[0].SepRect.Left);
    AssertEquals('and widens the pitch with it', 30,
      S[1].ItemRect.Left - S[0].ItemRect.Right);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestTheSeparatorGapMetricRetunesTheRhythm;
var
  T: TCrumbAccess;
  S: TTyBreadcrumbSlots;
begin
  // --breadcrumb-separator-gap is the mark's air, on BOTH sides.
  FCtl.LoadThemeCss(StringReplace(BaseCss, '--breadcrumb-separator-gap: 5px',
    '--breadcrumb-separator-gap: 0px', []));
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    S := T.TyCrumbSlots;
    AssertEquals('no air: the mark hugs the crumb', S[0].ItemRect.Right, S[0].SepRect.Left);
    AssertEquals('and the pitch is the bare slot', 10,
      S[1].ItemRect.Left - S[0].ItemRect.Right);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestCrumbAtIsTheInverseOfCrumbRect;
var
  T: TCrumbAccess;
  i: Integer;
  R: TRect;
  P: TPoint;
begin
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    for i := 0 to 2 do
    begin
      R := T.TyCrumbRect(i);
      P := CentreOf(R);
      AssertEquals(Format('crumb %d is where it was drawn', [i]), i, T.TyCrumbAt(P.X, P.Y));
    end;
    // The bar's own padding gutter belongs to no crumb.
    AssertEquals('the left gutter is nobody''s', -1, T.TyCrumbAt(1, 15));
    AssertEquals('and neither is the air past the trail', -1, T.TyCrumbAt(395, 15));
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestClickingALinkFiresOnCrumbClick;
var
  T: TCrumbAccess;
  P: TPoint;
begin
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    T.OnCrumbClick := @HandleCrumbClick;
    P := CentreOf(T.TyCrumbRect(1));
    T.PressReleaseAt(P.X, P.Y);
    AssertEquals('OnCrumbClick fired once', 1, FFired);
    AssertEquals('carrying the crumb''s Items index', 1, FFiredIndex);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestClickingTheCurrentCrumbFiresNothing;
var
  T: TCrumbAccess;
  P: TPoint;
begin
  // The last crumb is where you already are: navigating to it is not a thing that can
  // happen, so the event that means "go here" must not claim it did.
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    T.OnCrumbClick := @HandleCrumbClick;
    P := CentreOf(T.TyCrumbRect(2));
    T.PressReleaseAt(P.X, P.Y);
    AssertEquals('the current location is not a destination', 0, FFired);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestDraggingOffALinkCancels;
var
  T: TCrumbAccess;
  P0, P1: TPoint;
begin
  // Like any push button: press one crumb, release on another, and the gesture is off. In
  // particular it must not navigate to the crumb the finger LANDED on — that is the click
  // the user just cancelled.
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    T.OnCrumbClick := @HandleCrumbClick;
    P0 := CentreOf(T.TyCrumbRect(0));
    P1 := CentreOf(T.TyCrumbRect(1));
    T.PressAtReleaseAt(P0.X, P0.Y, P1.X, P1.Y);
    AssertEquals('a drag between crumbs navigates nowhere', 0, FFired);
    // And releasing in the gutter is just as dead.
    T.PressAtReleaseAt(P0.X, P0.Y, 1, 15);
    AssertEquals('nor does a drag into the gutter', 0, FFired);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestADisabledTrailIgnoresAClick;
var
  T: TCrumbAccess;
  P: TPoint;
begin
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    T.OnCrumbClick := @HandleCrumbClick;
    P := CentreOf(T.TyCrumbRect(0));
    T.Enabled := False;
    T.PressReleaseAt(P.X, P.Y);
    AssertEquals('a disabled trail navigates nowhere', 0, FFired);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestAWideBarShowsEveryCrumb;
var
  T: TCrumbAccess;
begin
  FCtl.LoadThemeCss(BaseCss);
  T := MakeDeepPath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 2000, 30);
    AssertEquals('room for everything means no mark', '0,1,2,3,4,5',
      PlanText(T.TyVisiblePlan));
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestANarrowBarElidesTheMiddle;
var
  T: TCrumbAccess;
  w, h: Integer;
begin
  { One px narrower than the whole trail needs. The rule then drops the single least useful
    crumb — the ancestor furthest from the end — and nothing else: the root stays (it says
    which tree this is), the near ancestors stay, and where you are stays.
    Measured rather than guessed at: headless text metrics are not the real GUI's, so the
    only honest way to ask for "one px too narrow" is to ask the control what it wanted. }
  FCtl.LoadThemeCss(BaseCss);
  T := MakeDeepPath(FForm, FCtl);
  try
    T.PreferredSize(w, h);
    T.SetBounds(0, 0, w - 1, 30);
    AssertEquals('exactly one crumb goes, and the mark stands in for it',
      '0,-1,2,3,4,5', PlanText(T.TyVisiblePlan));
    // And squeezed hard, the trail still ends where you are.
    T.SetBounds(0, 0, 60, 30);
    AssertEquals('a hopeless bar still says where you are', 5,
      T.TyVisiblePlan[High(T.TyVisiblePlan)]);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestAnElidedCrumbHasNoRect;
var
  T: TCrumbAccess;
  w, h: Integer;
begin
  FCtl.LoadThemeCss(BaseCss);
  T := MakeDeepPath(FForm, FCtl);
  try
    T.PreferredSize(w, h);
    T.SetBounds(0, 0, w - 1, 30);
    AssertEquals('an elided crumb has nowhere to be', 0,
      T.TyCrumbRect(1).Right - T.TyCrumbRect(1).Left);
    AssertTrue('while the ones that survived do',
      T.TyCrumbRect(2).Right > T.TyCrumbRect(2).Left);
    AssertTrue('the current location most of all',
      T.TyCrumbRect(5).Right > T.TyCrumbRect(5).Left);
    // An elided crumb cannot be clicked either — there is nothing there to click.
    T.OnCrumbClick := @HandleCrumbClick;
    T.PressReleaseAt(1, 15);
    AssertEquals('and cannot be reached with the mouse', 0, FFired);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestClickingTheMarkFiresNothing;
var
  T: TCrumbAccess;
  S: TTyBreadcrumbSlots;
  i, w, h: Integer;
  P: TPoint;
  found: Boolean;
begin
  // The '…' is a mark, not a place: it hit-tests as nothing.
  FCtl.LoadThemeCss(BaseCss);
  T := MakeDeepPath(FForm, FCtl);
  try
    T.PreferredSize(w, h);
    T.SetBounds(0, 0, w - 1, 30);
    T.OnCrumbClick := @HandleCrumbClick;
    S := T.TyCrumbSlots;
    found := False;
    for i := 0 to High(S) do
      if S[i].ItemIndex = TyBreadcrumbEllipsisIndex then
      begin
        found := True;
        P := CentreOf(S[i].ItemRect);
        AssertEquals('the mark is not a destination', -1, T.TyCrumbAt(P.X, P.Y));
        T.PressReleaseAt(P.X, P.Y);
      end;
    AssertTrue('the trail did elide (or this tests nothing)', found);
    AssertEquals('clicking the mark navigates nowhere', 0, FFired);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestShrinkingItemsClearsAStrandedHover;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
  P: TPoint;
begin
  { Deleting the tail promotes a LINK to the current location. Its hover must go with it, or
    the trail would light where you already are like somewhere you could go — and the next
    release would fire a navigation to it. }
  FCtl.LoadThemeCss(BaseCss + 'TyBreadcrumbItem:hover { background: #3B82F6; }');
  T := MakeCrumb(FForm, FCtl, ['Home', 'Documents', 'Reports', 'Q3']);
  try
    T.SetBounds(0, 0, 400, 30);
    P := CentreOf(T.TyCrumbRect(2));
    T.MoveTo(P.X, P.Y);
    Reread := RenderCrumb(T);
    try
      AssertTrue('the link is lit to begin with', HasBlueChip(Reread, T.TyCrumbRect(2)));
    finally
      Reread.Free;
    end;

    T.Items.Delete(3);   // crumb 2 is now where you are
    Reread := RenderCrumb(T);
    try
      AssertFalse('the promoted crumb is not lit any more',
        HasBlueChip(Reread, Rect(0, 0, T.Width, T.Height)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestPreferredWidthHugsTheWholeTrail;
var
  T: TCrumbAccess;
  w, h: Integer;
begin
  { The round trip: at its preferred width the bar shows the whole trail, and one px under
    it does not. That is what makes AutoSize mean "never elide". }
  FCtl.LoadThemeCss(BaseCss);
  T := MakeDeepPath(FForm, FCtl);
  try
    T.PreferredSize(w, h);
    T.SetBounds(0, 0, w, 30);
    AssertEquals('the preferred width shows everything', '0,1,2,3,4,5',
      PlanText(T.TyVisiblePlan));
    T.SetBounds(0, 0, w - 1, 30);
    AssertTrue('one px under does not', PlanText(T.TyVisiblePlan) <> '0,1,2,3,4,5');
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestPreferredWidthGrowsWithACrumb;
var
  T: TCrumbAccess;
  before, after, h: Integer;
begin
  // A crumb more costs its own width plus a mark's pitch (20px here).
  FCtl.LoadThemeCss(BaseCss);
  T := MakePath(FForm, FCtl);
  try
    T.PreferredSize(before, h);
    T.Items.Add('Q3');
    T.PreferredSize(after, h);
    AssertTrue('a deeper path needs a wider bar', after > before + 20);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestPreferredHeightClearsTheSeparatorMetric;
var
  T: TCrumbAccess;
  w, lineH, tallH: Integer;
begin
  { The mark is centred in the band, so a band shorter than its slot would squash the glyph:
    a big --breadcrumb-separator-size must push the bar taller. The tiny font is what makes
    the text line the SHORTER of the two, so the slot is provably what is driving it. }
  FCtl.LoadThemeCss(StringReplace(BaseCss, 'font-size: 12px', 'font-size: 6px', []));
  T := MakePath(FForm, FCtl);
  try
    T.PreferredSize(w, lineH);
    FCtl.LoadThemeCss(StringReplace(
      StringReplace(BaseCss, 'font-size: 12px', 'font-size: 6px', []),
      '--breadcrumb-separator-size: 10px', '--breadcrumb-separator-size: 40px', []));
    T.PreferredSize(w, tallH);
    AssertTrue('a small font gives a short bar', lineH < 40 + 6);
    // 3px top + a 40px slot + 3px bottom.
    AssertEquals('a tall mark floors the bar''s height', 46, tallH);
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestTheBarRendersItsThemeBackground;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
  px: TBGRAPixel;
begin
  // The bar paints from the token, not from an LCL colour.
  FCtl.LoadThemeCss(StringReplace(BaseCss, 'TyBreadcrumb { background: #FFFFFF',
    'TyBreadcrumb { background: #3B82F6', []));
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    Reread := RenderCrumb(T);
    try
      // In the bar's own padding gutter: clear of every crumb, so this can only be the bar.
      px := Reread.GetPixel(1, 15);
      AssertTrue('the bar painted in its themed fill', (px.blue > 180) and (px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestTheCurrentCrumbTakesTheSelectedStyle;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
begin
  // The whole visual grammar in one assertion: the theme fills ONLY :selected, and only the
  // last crumb gets a plate.
  FCtl.LoadThemeCss(BaseCss + 'TyBreadcrumbItem:selected { background: #3B82F6; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    Reread := RenderCrumb(T);
    try
      AssertTrue('the current location is plated', HasBlueChip(Reread, T.TyCrumbRect(2)));
      AssertFalse('the root is not', HasBlueChip(Reread, T.TyCrumbRect(0)));
      AssertFalse('nor any other link', HasBlueChip(Reread, T.TyCrumbRect(1)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestAHoveredLinkLightsUp;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
  P: TPoint;
begin
  FCtl.LoadThemeCss(BaseCss + 'TyBreadcrumbItem:hover { background: #3B82F6; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    P := CentreOf(T.TyCrumbRect(1));
    T.MoveTo(P.X, P.Y);
    Reread := RenderCrumb(T);
    try
      AssertTrue('the link under the pointer lights up',
        HasBlueChip(Reread, T.TyCrumbRect(1)));
      AssertFalse('its neighbour does not', HasBlueChip(Reread, T.TyCrumbRect(0)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestTheCurrentCrumbNeverLightsUp;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
  P: TPoint;
begin
  // Hovering where you already are must promise nothing: a chip there would advertise a
  // navigation that cannot happen.
  FCtl.LoadThemeCss(BaseCss + 'TyBreadcrumbItem:hover { background: #3B82F6; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    P := CentreOf(T.TyCrumbRect(2));
    T.MoveTo(P.X, P.Y);
    Reread := RenderCrumb(T);
    try
      AssertFalse('the current location never lights up',
        HasBlueChip(Reread, Rect(0, 0, T.Width, T.Height)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestADisabledTrailKeepsTheCurrentPlate;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
begin
  { Greyed out, the trail must still say WHERE you are — losing the plate would read as
    "this path is nowhere" rather than "you cannot navigate from here". The cascade does it:
    :selected is the resting layer, :disabled wins the ink over it. }
  FCtl.LoadThemeCss(BaseCss +
    'TyBreadcrumbItem:selected { background: #3B82F6; }' +
    'TyBreadcrumbItem:disabled { color: #888888; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    T.Enabled := False;
    Reread := RenderCrumb(T);
    try
      AssertTrue('the plate survives being disabled',
        HasBlueChip(Reread, T.TyCrumbRect(2)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestTheSeparatorTakesTheBarInk;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
  S: TTyBreadcrumbSlots;
begin
  { The mark is the BAR's chrome, so it takes the BAR's `color` — that is why it earns no
    typeKey of its own. White bar, WHITE crumbs, GREEN bar ink: any green in the separator
    slot can only be the mark drawn from `TyBreadcrumb { color }`. }
  FCtl.LoadThemeCss(
    // 14px, not the 10px the layout tests use: those only do arithmetic, which is size-agnostic,
    // but this one needs the mark to be VISIBLE. TTyPainter.DrawGlyph insets a vector glyph by 4
    // LOGICAL px PER SIDE, so a 10px slot leaves a 1px-wide chevron — two faint anti-aliased
    // pixels that no ink predicate can see, and that a user could not either. ~12px is the
    // practical floor for a TyDrawGlyph slot; 14 is this control's default and the size every
    // other glyph slot in the library uses (TyTagCloseSize / TyTabCloseSize).
    ':root { --breadcrumb-separator-size: 14px; --breadcrumb-separator-gap: 5px; }' +
    'TyBreadcrumb { background: #FFFFFF; color: #10B981; padding: 3px 4px; font-size: 12px; }' +
    'TyBreadcrumbItem { color: #FFFFFF; padding: 0px 4px; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    S := T.TyCrumbSlots;
    Reread := RenderCrumb(T);
    try
      AssertTrue('the mark is drawn in the bar''s ink', HasGreenInk(Reread, S[0].SepRect));
      AssertTrue('every one of them', HasGreenInk(Reread, S[1].SepRect));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestAnUndefinedBarKeyDrawsNothing;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
begin
  { A theme that gives the bar no BACKGROUND must degrade, not invent a look: nothing of
    ours is drawn at all — not even the crumbs, whose own key IS defined here.
    The TyBreadcrumb rule below is deliberately present-but-backgroundless rather than
    absent: the compiled-in base layer (themes/light.tycss) backs every typeKey a theme
    omits, so "leave the rule out" would silently stop testing degradation the moment the
    base defines TyBreadcrumb. Any user rule for a typeKey suppresses the whole base layer
    for it (TTyStyleModel.UserHasTypeKey), so this is how you get a genuinely
    background-less key. }
  FCtl.LoadThemeCss(
    'TyBreadcrumb { color: #000000; }' +
    'TyBreadcrumbItem:selected { background: #3B82F6; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    Reread := RenderCrumb(T);
    try
      AssertFalse('no bar key -> no plate, no crumbs, nothing',
        HasBlueChip(Reread, Rect(0, 0, 400, 30)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

procedure TTyBreadcrumbControlTest.TestAnUndefinedItemKeyStillDrawsCrumbsInTheBarInk;
var
  T: TCrumbAccess;
  Reread: TBGRABitmap;
begin
  { The other half of the degradation: a crumb key carrying no COLOUR gets no chips (no
    background to draw one from) but its labels still appear, in the BAR's own ink. White
    bar, GREEN bar ink, and a TyBreadcrumbItem rule with neither background nor color: any
    green inside a crumb's rect can only be a label that inherited the bar's colour — never
    a hard-coded fallback. (The item rule must be PRESENT to suppress the base layer's own
    TyBreadcrumbItem, which does define a colour; omitting it would inherit that and test
    nothing. Same reason as TestAnUndefinedBarKeyDrawsNothing.) }
  FCtl.LoadThemeCss(
    ':root { --breadcrumb-separator-size: 10px; --breadcrumb-separator-gap: 5px; }' +
    'TyBreadcrumb { background: #FFFFFF; color: #10B981; padding: 3px 4px; font-size: 12px; }' +
    'TyBreadcrumbItem { border-radius: 0; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    Reread := RenderCrumb(T);
    try
      AssertTrue('a crumb still draws, in the bar''s ink',
        HasGreenInk(Reread, T.TyCrumbRect(0)));
      AssertTrue('the current location too', HasGreenInk(Reread, T.TyCrumbRect(2)));
      AssertFalse('but nothing invented a chip to sit on',
        HasBlueChip(Reread, Rect(0, 0, 400, 30)));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): a TyBreadcrumb rule with no background makes RenderTo
  draw NOTHING (it exits early), but the input path still hit-tested and fired OnCrumbClick — a
  click navigating to a crumb the user cannot see. Paint and input must agree the control has no
  content. (A user TyBreadcrumb rule suppresses the compiled-in base, so 'no background' is
  reachable in practice, not just theoretical.) }
procedure TTyBreadcrumbControlTest.TestBackgroundlessBarIsNotClickable;
var
  T: TCrumbAccess;
  P: TPoint;
begin
  // Present-but-background-less bar (suppresses the base layer); crumbs would otherwise be here.
  FCtl.LoadThemeCss('TyBreadcrumb { color: #000000; padding: 2px 4px; font-size: 12px; }'
    + 'TyBreadcrumbItem { color: #0000FF; padding: 0px 4px; }');
  T := MakePath(FForm, FCtl);
  try
    T.SetBounds(0, 0, 400, 30);
    T.OnCrumbClick := @HandleCrumbClick;
    P := CentreOf(T.TyCrumbRect(1));   // where crumb 1 WOULD be
    T.PressReleaseAt(P.X, P.Y);
    AssertEquals('a bar that draws nothing fires nothing on a click', 0, FFired);
  finally
    T.Free;
  end;
end;

initialization
  RegisterTest(TTyBreadcrumbRulesTest);
  RegisterTest(TTyBreadcrumbControlTest);
end.
