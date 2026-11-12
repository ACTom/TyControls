unit test.notification;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  test.danglingrefs,  // BeginPoison / EndPoison
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Notification,
  tyControls.Alert;   // atInfo..atError — TTyNotificationType is an ALIAS of TTyAlertType,
                      // so the enum VALUES still live in the aliased unit.

type
  { Pure-rules tests: every function here takes plain integers / enums, so they run with no
    component, no window and no theme at all. }
  TTyNotificationRulesTest = class(TTestCase)
  published
    procedure TestTypeGlyphPerKind;
    procedure TestTypeClassPerKind;
    procedure TestTopCornersStackDownBottomCornersUp;
    procedure TestStackOffsetSumsHeightsAndGaps;
    procedure TestStackOffsetIgnoresZeroHeightCards;
    procedure TestStackOffsetEmptyIsZero;
    procedure TestRectHugsEachCorner;
    procedure TestRectStacksAwayFromAnchoredEdge;
    procedure TestRectClampsTallStackIntoWorkArea;
    procedure TestRectClampsOversizedCard;
    procedure TestHeightSumsPaddingTitleGapLines;
    procedure TestHeightNoTitleDropsTitleAndGap;
    procedure TestHeightFloorsToIconSize;
    procedure TestHeightNoIconDoesNotFloor;
    procedure TestLayoutCloseHugsBandTopRight;
    procedure TestLayoutNoCloseGivesColumnTheWholeBand;
    procedure TestLayoutIconHugsBandLeft;
    procedure TestLayoutTitleAndMessageShareTheColumn;
    procedure TestLayoutNoTitleGivesMessageTheColumn;
    procedure TestLayoutNoIconStartsColumnAtBand;
    procedure TestLayoutNarrowCardKeepsCloseDropsRest;
    procedure TestLayoutPaddingEatsWholeCard;
    procedure TestLayoutZeroSizeEmpty;
    procedure TestLayoutCloseSlotClampedByShortCard;
    procedure TestAdvanceAccumulates;
    procedure TestAdvancePausedFreezes;
    procedure TestAdvanceIgnoresNonPositiveTick;
    procedure TestExpiredAtOrPastDuration;
    procedure TestZeroDurationNeverExpires;
    procedure TestAHostOnScreenWithRoomIsUsable;
    procedure TestAHostNotOnScreenIsNotUsable;
    procedure TestAMinimisedHostIsNotUsable;
    procedure TestAHostNarrowerOrShorterThanTheCardIsNotUsable;
  end;

  { Headless component behaviour: typeKeys, defaults, theme-driven geometry + inks, the
    close/click gestures, the countdown and the corner stack — all with no window (a real
    Show needs a handle the headless runner has not got; the LOOK is a real-machine check). }
  TTyNotificationComponentTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FClosed: Integer;
    FClicked: Integer;
    procedure HandleClose(Sender: TObject);
    procedure HandleClick(Sender: TObject);
    function NewNote: TTyNotification;   // a toast wired to the test controller
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeys;
    procedure TestDefaults;
    procedure TestNegativeDurationClampsToStay;
    procedure TestCloseRectEmptyWhenNotClosable;
    procedure TestCloseRectFollowsThemePadding;
    procedure TestCloseSizeMetricRetunesSlot;
    procedure TestIconSizeMetricRetunesMarkSlot;
    procedure TestWidthMetricDrivesMeasuredCard;
    procedure TestMeasureGrowsWithMessageLines;
    procedure TestMeasureFloorsToTheMarkSlot;
    procedure TestMarkTakesTypeVariantInk;
    procedure TestMarkFallsBackToCardInkWithoutVariantRule;
    procedure TestTextInkIgnoresTypeVariant;
    procedure TestClickCloseHidesAndFiresOnClose;
    procedure TestClickCloseDoesNotFireOnClick;
    procedure TestClickCardFiresOnClickAndKeepsToast;
    procedure TestDragOffCloseCancelsGesture;
    procedure TestUnclosableIgnoresClickWhereXWouldBe;
    procedure TestAutoDismissAtDuration;
    procedure TestZeroDurationStaysUntilHidden;
    procedure TestHoverFreezesCountdown;
    procedure TestPauseOnHoverOffKeepsCounting;
    procedure TestHideIsIdempotent;
    procedure TestSlotHugsChosenCorner;
    procedure TestSecondToastStacksBelowFirst;
    procedure TestOtherCornerDoesNotStack;
    procedure TestClosingMiddleToastRestacksTheRest;
    procedure TestCardRendersThemeBackground;
    procedure TestCloseGlyphRendersThemeInk;
    procedure TestNoThemedBackgroundDrawsNothing;
  end;

  { A toast placed inside a form (HostForm), with no window on screen: the host's window is
    stood in for (see THostStub), so every rule -- which area, which stack, when it falls back
    to the screen, when it is re-placed -- runs headless. The hosts are real TForms, never
    shown, for their identity and for LCL's own change-handler lists. }
  TTyNotificationHostTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FAreaAsks: Integer;
    FTrim: TRect;          // what HandleHostArea takes off each edge
    procedure HandleHostArea(Sender: TObject; var AArea: TRect);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHostFormDefaultsToNoHost;
    procedure TestWithoutAHostTheSlotIsTheScreenCornerAsBefore;
    procedure TestWithoutAHostTheRealScreenWorkAreaIsUsed;
    procedure TestAHostedSlotHugsEachCornerOfTheHostArea;
    procedure TestToastsOfOneHostStack;
    procedure TestToastsOfTwoHostsDoNotPushEachOther;
    procedure TestScreenAndHostedToastsDoNotPushEachOther;
    procedure TestSlotRectInCountsOnlyTheToastsOwnStack;
    procedure TestTheSlotMovesWithTheHostArea;
    procedure TestAHostNotOnScreenSendsItsToastToTheScreen;
    procedure TestAMinimisedHostSendsItsToastToTheScreen;
    procedure TestAHostSmallerThanTheCardSendsItsToastToTheScreen;
    procedure TestAFormNeverShownIsNotAHost;
    procedure TestAToastSentToTheScreenStacksWithTheScreenToasts;
    procedure TestAMovedHostRePlacesItsShowingToasts;
    procedure TestAHostIsWatchedOnlyWhileItsToastIsUp;
    procedure TestChangingHostFormMovesTheToastAndTheWatch;
    procedure TestAHostComingBackTakesItsToastBack;
    procedure TestAFreedToastIsOffItsHostsHandlerLists;
    procedure TestFreeingTheHostClearsHostForm;
    procedure TestFreeingTheHostSendsItsShowingToastToTheScreen;
    procedure TestAToastOwnedByItsHostGoesDownWithItNotToTheScreen;
    procedure TestOnGetHostAreaTrimsTheArea;
    procedure TestOnGetHostAreaIsNotAskedWithoutAUsableWindow;
    procedure TestAnAreaTrimmedBelowTheCardFallsBack;
    procedure TestHostFormSurvivesTheFormFile;
  end;

  { The same, against real windows: a form shown off screen, a toast really shown in it. What
    the headless suite cannot reach is here -- that the placement reads the real form's client
    area in screen coordinates, and that LCL really reports a move, a resize and a hide. }
  TTyNotificationHostWindowTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FAreaAsks: Integer;
    function ClientOnScreen: TRect;
    procedure Pump;
    procedure HandleHostArea(Sender: TObject; var AArea: TRect);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAToastOpensInItsHostsCorner;
    procedure TestAHostsScrollBarsAreNotPartOfItsArea;
    procedure TestAToastShownBeforeItsHostJoinsItWhenTheHostAppears;
    procedure TestTheToastFollowsItsHostWhenItMovesAndResizes;
    procedure TestAHiddenHostSendsItsToastToTheScreenAndTakesItBack;
    procedure TestAToastShownWhileItsHostIsMinimisedGoesToTheScreen;
    procedure TestOnGetHostAreaIsNotAskedOfAMinimisedWindow;
    procedure TestFreeingTheHostSendsItsToastsToTheScreen;
  end;

implementation

const
  { The card size every component test measures against, and a work area of round numbers so
    a slot rect is checkable by hand. }
  CCardW = 300;
  CCardH = 80;
  CWorkL = 0;
  CWorkT = 0;
  CWorkR = 1920;
  CWorkB = 1040;

  { Every one of the toast's metrics, PINNED. They must be spelled out rather than left to the
    built-in fallbacks: theme :root vars ALWAYS merge under a loaded theme, so a shipped theme
    that retunes any of these would silently move every expected number below. Pinning them
    also makes each test assert the WIRING (a themed metric moves the geometry), which is the
    claim that matters — the fallback constants are only what a theme that sets none gets. }
  CRootFmt = ':root { --notification-width: %dpx; --notification-icon-size: %dpx;'
           + ' --notification-close-size: %dpx; --notification-gap: %dpx;'
           + ' --notification-margin: %dpx; --notification-stack-gap: %dpx; }';

  { The card rule. Flat values, so every expected number is arithmetic and not a font
    measurement (the headless runner's default font measures nothing like a UI font's). }
  CCard = 'TyNotification { background: #FFFFFF; color: #111111; padding: 12px 14px;'
        + ' font-size: 12px; }';

{ The test theme. Defaults reproduce the built-in fallbacks, so the hand-computed geometry
  below reads the same as the shipped defaults; a test that retunes one passes it here. }
function ThemeCss(AWidth: Integer = 340; AIcon: Integer = 24; AClose: Integer = 14;
  AGap: Integer = 8; AMargin: Integer = 16; AStackGap: Integer = 8;
  const ACard: string = CCard; const AExtra: string = ''): string;
begin
  Result := Format(CRootFmt, [AWidth, AIcon, AClose, AGap, AMargin, AStackGap])
    + ACard + AExtra;
end;

type
  { Reaches the protected paint / gesture / style seams. The mouse helpers hand in the client
    size the toast WINDOW would have supplied — which is exactly why they need no window. }
  TNoteAccess = class(TTyNotification)
  public
    procedure BeginShowing;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Layout(AW, AH, APPI: Integer): TTyNotificationLayout;
    function MarkInk: TTyColor;
    function TextInk: TTyColor;
    procedure MoveTo(X, Y: Integer);
    procedure LeaveCard;
    procedure PressReleaseAt(X, Y: Integer);
    procedure PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
  end;

procedure TNoteAccess.BeginShowing;
begin
  inherited BeginShowing;
end;

procedure TNoteAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TNoteAccess.Layout(AW, AH, APPI: Integer): TTyNotificationLayout;
begin
  Result := LayoutFor(AW, AH, APPI);
end;

function TNoteAccess.MarkInk: TTyColor;
begin
  Result := inherited MarkInk;
end;

function TNoteAccess.TextInk: TTyColor;
begin
  Result := inherited TextInk;
end;

procedure TNoteAccess.MoveTo(X, Y: Integer);
begin
  DoMouseMove(X, Y, CCardW, CCardH, 96);
end;

procedure TNoteAccess.LeaveCard;
begin
  DoMouseLeave;
end;

procedure TNoteAccess.PressReleaseAt(X, Y: Integer);
begin
  PressAtReleaseAt(X, Y, X, Y);
end;

procedure TNoteAccess.PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
begin
  DoMouseDown(ADownX, ADownY, CCardW, CCardH, 96);
  DoMouseUp(AUpX, AUpY, CCardW, CCardH, 96);
end;

{ ============================ TTyNotificationRulesTest ============================ }

procedure TTyNotificationRulesTest.TestTypeGlyphPerKind;
begin
  // The mark is the painter's own status glyph, one per kind — so a theme can swap any of
  // them for an icon-font codepoint without this unit knowing.
  AssertTrue('info shows the info mark', TyNotificationTypeGlyph(atInfo) = tgInfo);
  AssertTrue('success shows the tick', TyNotificationTypeGlyph(atSuccess) = tgSuccess);
  AssertTrue('warning shows the triangle', TyNotificationTypeGlyph(atWarning) = tgWarning);
  AssertTrue('error shows the cross', TyNotificationTypeGlyph(atError) = tgError);
end;

procedure TTyNotificationRulesTest.TestTypeClassPerKind;
begin
  // The type is a StyleClass, not a code branch: these four names are the whole contract
  // between the control and the theme.
  AssertEquals('info', TyNotificationTypeClass(atInfo));
  AssertEquals('success', TyNotificationTypeClass(atSuccess));
  AssertEquals('warning', TyNotificationTypeClass(atWarning));
  AssertEquals('error', TyNotificationTypeClass(atError));
end;

procedure TTyNotificationRulesTest.TestTopCornersStackDownBottomCornersUp;
begin
  // The stack always grows AWAY from the edge the first card is anchored to.
  AssertTrue('top-left stacks down', TyNotificationStacksDown(npTopLeft));
  AssertTrue('top-right stacks down', TyNotificationStacksDown(npTopRight));
  AssertFalse('bottom-left stacks up', TyNotificationStacksDown(npBottomLeft));
  AssertFalse('bottom-right stacks up', TyNotificationStacksDown(npBottomRight));
end;

procedure TTyNotificationRulesTest.TestStackOffsetSumsHeightsAndGaps;
begin
  // Two cards of 80 and 60 above me, gap 8 -> I sit (80+8)+(60+8) along.
  AssertEquals('heights + one gap each', 156, TyNotificationStackOffset([80, 60], 8));
  AssertEquals('one card', 88, TyNotificationStackOffset([80], 8));
end;

procedure TTyNotificationRulesTest.TestStackOffsetIgnoresZeroHeightCards;
begin
  // A card with no height occupies nothing, so it must not push the stack by a whole gap for
  // something nobody can see.
  AssertEquals('a 0-height card contributes nothing at all', 88,
    TyNotificationStackOffset([80, 0], 8));
  AssertEquals('nor does a negative one', 88, TyNotificationStackOffset([0, 80, -5], 8));
end;

procedure TTyNotificationRulesTest.TestStackOffsetEmptyIsZero;
var
  none: TTyNotificationHeights;
begin
  SetLength(none, 0);
  AssertEquals('first card in the corner', 0, TyNotificationStackOffset(none, 8));
  AssertEquals('a negative gap is clamped, not honoured', 80,
    TyNotificationStackOffset([80], -20));
end;

procedure TTyNotificationRulesTest.TestRectHugsEachCorner;
var
  WA, R: TRect;
begin
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  R := TyNotificationRect(npTopLeft, WA, 340, 80, 16, 0);
  AssertEquals('top-left x', 16, R.Left);
  AssertEquals('top-left y', 16, R.Top);
  R := TyNotificationRect(npTopRight, WA, 340, 80, 16, 0);
  AssertEquals('top-right hugs the right edge', CWorkR - 16, R.Right);
  AssertEquals('top-right y', 16, R.Top);
  R := TyNotificationRect(npBottomLeft, WA, 340, 80, 16, 0);
  AssertEquals('bottom-left x', 16, R.Left);
  AssertEquals('bottom-left hugs the bottom edge', CWorkB - 16, R.Bottom);
  R := TyNotificationRect(npBottomRight, WA, 340, 80, 16, 0);
  AssertEquals('bottom-right x', CWorkR - 16, R.Right);
  AssertEquals('bottom-right y', CWorkB - 16, R.Bottom);
end;

procedure TTyNotificationRulesTest.TestRectStacksAwayFromAnchoredEdge;
var
  WA, R: TRect;
begin
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  // A top corner pushes the newcomer DOWN; the elder keeps the corner.
  R := TyNotificationRect(npTopRight, WA, 340, 80, 16, 88);
  AssertEquals('pushed down by the stack offset', 16 + 88, R.Top);
  // A bottom corner pushes it UP.
  R := TyNotificationRect(npBottomRight, WA, 340, 80, 16, 88);
  AssertEquals('pushed up by the stack offset', CWorkB - 16 - 88, R.Bottom);
end;

procedure TTyNotificationRulesTest.TestRectClampsTallStackIntoWorkArea;
var
  WA, R: TRect;
begin
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  // A stack taller than the screen piles at the far edge: an overlapped toast is still
  // readable, one marched off screen is not.
  R := TyNotificationRect(npTopRight, WA, 340, 80, 16, 5000);
  AssertEquals('clamped to the bottom of the work area', CWorkB, R.Bottom);
  R := TyNotificationRect(npBottomRight, WA, 340, 80, 16, 5000);
  AssertEquals('clamped to the top of the work area', CWorkT, R.Top);
end;

procedure TTyNotificationRulesTest.TestRectClampsOversizedCard;
var
  R: TRect;
begin
  // Card bigger than the work area: pinned to the origin rather than pushed off it.
  R := TyNotificationRect(npTopRight, Rect(0, 0, 200, 100), 340, 200, 16, 0);
  AssertEquals('left-clamped', 0, R.Left);
  AssertEquals('top-clamped', 0, R.Top);
end;

procedure TTyNotificationRulesTest.TestHeightSumsPaddingTitleGapLines;
begin
  // pad 12 + title 16 + gap 8 + 2 lines x 15 + pad 12 = 78 (the 24 mark does not floor it).
  AssertEquals(78, TyNotificationHeight(16, 15, 2, 12, 12, 8, 24, True, True));
end;

procedure TTyNotificationRulesTest.TestHeightNoTitleDropsTitleAndGap;
begin
  // No title -> no title line AND no gap (the gap only exists BETWEEN the two):
  // pad 12 + 2 x 15 + pad 12 = 54.
  AssertEquals(54, TyNotificationHeight(16, 15, 2, 12, 12, 8, 24, True, False));
  // No message either -> the mark's floor is all that is left: 12 + 24 + 12.
  AssertEquals(48, TyNotificationHeight(16, 15, 0, 12, 12, 8, 24, True, False));
end;

procedure TTyNotificationRulesTest.TestHeightFloorsToIconSize;
begin
  // The mark sits BESIDE the text, so a one-line toast must still clear it:
  // content 15 < mark 24 -> 12 + 24 + 12.
  AssertEquals(48, TyNotificationHeight(16, 15, 1, 12, 12, 8, 24, True, False));
end;

procedure TTyNotificationRulesTest.TestHeightNoIconDoesNotFloor;
begin
  // Without a mark there is nothing to clear: 12 + 15 + 12.
  AssertEquals(39, TyNotificationHeight(16, 15, 1, 12, 12, 8, 24, False, False));
  AssertTrue('a degenerate card still has a height',
    TyNotificationHeight(0, 0, 0, 0, 0, 0, 0, False, False) >= 1);
end;

procedure TTyNotificationRulesTest.TestLayoutCloseHugsBandTopRight;
var
  L: TTyNotificationLayout;
begin
  // 300x80, pad 14/12, close 14: the slot's right edge is the band's right edge and it sits
  // at the band's TOP (the toast's corner affordance).
  L := TyNotificationLayout(300, 80, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('slot right = band right', 286, L.CloseRect.Right);
  AssertEquals('slot left = band right - size', 272, L.CloseRect.Left);
  AssertEquals('slot top = band top', 12, L.CloseRect.Top);
  AssertEquals('slot is square-sized', 14, L.CloseRect.Bottom - L.CloseRect.Top);
end;

procedure TTyNotificationRulesTest.TestLayoutNoCloseGivesColumnTheWholeBand;
var
  L: TTyNotificationLayout;
begin
  L := TyNotificationLayout(300, 80, True, True, False, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
  // No x -> the text column runs all the way to the band's right edge.
  AssertEquals('the text reclaims the slot column', 286, L.TitleRect.Right);
end;

procedure TTyNotificationRulesTest.TestLayoutIconHugsBandLeft;
var
  L: TTyNotificationLayout;
begin
  L := TyNotificationLayout(300, 80, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('mark starts at the band left', 14, L.IconRect.Left);
  AssertEquals('mark is its themed square', 24, L.IconRect.Right - L.IconRect.Left);
  // The 16px title line is shorter than the 24px mark, so centring on it would push the mark
  // out of the band: it top-aligns instead.
  AssertEquals('mark clamped into the band', 12, L.IconRect.Top);
  AssertEquals('mark bottom', 36, L.IconRect.Bottom);
end;

procedure TTyNotificationRulesTest.TestLayoutTitleAndMessageShareTheColumn;
var
  L: TTyNotificationLayout;
begin
  L := TyNotificationLayout(300, 80, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  // Column = band left + mark + gap .. slot left - gap.
  AssertEquals('column starts past the mark', 14 + 24 + 8, L.TitleRect.Left);
  AssertEquals('column stops a gap before the slot', 272 - 8, L.TitleRect.Right);
  AssertEquals('title takes the column top', 12, L.TitleRect.Top);
  AssertEquals('title is one title line tall', 12 + 16, L.TitleRect.Bottom);
  // The message takes the rest, a gap below the title.
  AssertEquals('message starts a gap below the title', 12 + 16 + 8, L.MessageRect.Top);
  AssertEquals('message runs to the band bottom', 68, L.MessageRect.Bottom);
  AssertEquals('and shares the title column', L.TitleRect.Left, L.MessageRect.Left);
  AssertEquals('to the same right edge', L.TitleRect.Right, L.MessageRect.Right);
end;

procedure TTyNotificationRulesTest.TestLayoutNoTitleGivesMessageTheColumn;
var
  L: TTyNotificationLayout;
begin
  L := TyNotificationLayout(300, 80, True, False, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('no title', 0, L.TitleRect.Right - L.TitleRect.Left);
  AssertEquals('message starts at the band top', 12, L.MessageRect.Top);
  AssertEquals('message runs to the band bottom', 68, L.MessageRect.Bottom);
  // With no title line to sit beside, the mark centres in the whole band: the band (12..68)
  // is 56 tall, so a 24 mark starts at 12 + (56-24) div 2 = 28.
  AssertEquals('mark centres in the band', 28, L.IconRect.Top);
end;

procedure TTyNotificationRulesTest.TestLayoutNoIconStartsColumnAtBand;
var
  L: TTyNotificationLayout;
begin
  L := TyNotificationLayout(300, 80, False, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('no mark', 0, L.IconRect.Right - L.IconRect.Left);
  AssertEquals('the text reclaims the mark column', 14, L.TitleRect.Left);
end;

procedure TTyNotificationRulesTest.TestLayoutNarrowCardKeepsCloseDropsRest;
var
  L: TTyNotificationLayout;
begin
  // Band = 40-14-14 = 12 px, narrower than the 14px slot. The x is the toast's only way out,
  // so it keeps what there is; the mark cannot fit beside it and the column collapses.
  L := TyNotificationLayout(40, 80, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('slot clamped to the band left', 14, L.CloseRect.Left);
  AssertEquals('slot clamped to the band right', 26, L.CloseRect.Right);
  AssertEquals('no mark', 0, L.IconRect.Right - L.IconRect.Left);
  AssertEquals('no title', 0, L.TitleRect.Right - L.TitleRect.Left);
  AssertEquals('no message', 0, L.MessageRect.Right - L.MessageRect.Left);
end;

procedure TTyNotificationRulesTest.TestLayoutPaddingEatsWholeCard;
var
  L: TTyNotificationLayout;
begin
  // Padding wider than the card: nothing fits — every rect empty, never inverted.
  L := TyNotificationLayout(20, 80, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('no title', 0, L.TitleRect.Right - L.TitleRect.Left);
  // ...and the same when the VERTICAL padding eats it.
  L := TyNotificationLayout(300, 20, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('no message', 0, L.MessageRect.Right - L.MessageRect.Left);
end;

procedure TTyNotificationRulesTest.TestLayoutZeroSizeEmpty;
var
  L: TTyNotificationLayout;
begin
  L := TyNotificationLayout(0, 80, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('zero width: no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
  L := TyNotificationLayout(300, 0, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('zero height: no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
end;

procedure TTyNotificationRulesTest.TestLayoutCloseSlotClampedByShortCard;
var
  L: TTyNotificationLayout;
begin
  // A band shorter than the slot squashes it into the band, never past it.
  L := TyNotificationLayout(300, 30, True, True, True, 14, 12, 14, 12, 24, 8, 14, 16);
  AssertEquals('slot top = band top', 12, L.CloseRect.Top);
  AssertEquals('slot bottom clamped to the band', 18, L.CloseRect.Bottom);
end;

procedure TTyNotificationRulesTest.TestAdvanceAccumulates;
begin
  AssertEquals(100, TyNotificationAdvance(0, 100, False));
  AssertEquals(450, TyNotificationAdvance(350, 100, False));
end;

procedure TTyNotificationRulesTest.TestAdvancePausedFreezes;
begin
  // Frozen, not slowed: a paused countdown does not move at all.
  AssertEquals(350, TyNotificationAdvance(350, 100, True));
  AssertEquals(350, TyNotificationAdvance(350, 99999, True));
end;

procedure TTyNotificationRulesTest.TestAdvanceIgnoresNonPositiveTick;
begin
  AssertEquals('a zero tick is a no-op', 350, TyNotificationAdvance(350, 0, False));
  AssertEquals('a tick never rewinds the countdown', 350,
    TyNotificationAdvance(350, -100, False));
end;

procedure TTyNotificationRulesTest.TestExpiredAtOrPastDuration;
begin
  AssertFalse('still running', TyNotificationExpired(4499, 4500));
  AssertTrue('up exactly at the duration', TyNotificationExpired(4500, 4500));
  AssertTrue('and past it', TyNotificationExpired(9000, 4500));
end;

procedure TTyNotificationRulesTest.TestZeroDurationNeverExpires;
begin
  // 0 = "stay until closed": the whole contract of a toast the user must acknowledge.
  AssertFalse(TyNotificationExpired(0, 0));
  AssertFalse(TyNotificationExpired(999999, 0));
end;

function HostAt(AVisible, AMinimized: Boolean; const AArea: TRect): TTyNotificationHostState;
begin
  Result.Visible := AVisible;
  Result.Minimized := AMinimized;
  Result.ClientArea := AArea;
end;

procedure TTyNotificationRulesTest.TestAHostOnScreenWithRoomIsUsable;
begin
  AssertTrue('a roomy client area takes the card',
    TyNotificationHostUsable(HostAt(True, False, Rect(300, 200, 1100, 800)), 340, 80));
  // Exactly the card: it still goes in (the margin gives way before the host does).
  AssertTrue('an area exactly the card''s size still takes it',
    TyNotificationHostUsable(HostAt(True, False, Rect(300, 200, 640, 280)), 340, 80));
end;

procedure TTyNotificationRulesTest.TestAHostNotOnScreenIsNotUsable;
begin
  // The same roomy area as above: only the window not being on screen says no.
  AssertFalse('a form that is not on screen has no corner to stand in',
    TyNotificationHostUsable(HostAt(False, False, Rect(300, 200, 1100, 800)), 340, 80));
end;

procedure TTyNotificationRulesTest.TestAMinimisedHostIsNotUsable;
begin
  AssertFalse('a minimised form has no client area on screen',
    TyNotificationHostUsable(HostAt(True, True, Rect(300, 200, 1100, 800)), 340, 80));
end;

procedure TTyNotificationRulesTest.TestAHostNarrowerOrShorterThanTheCardIsNotUsable;
begin
  AssertFalse('one px narrower than the card',
    TyNotificationHostUsable(HostAt(True, False, Rect(300, 200, 639, 800)), 340, 80));
  AssertFalse('one px shorter than the card',
    TyNotificationHostUsable(HostAt(True, False, Rect(300, 200, 1100, 279)), 340, 80));
  AssertFalse('an empty area',
    TyNotificationHostUsable(HostAt(True, False, Rect(300, 200, 300, 200)), 340, 80));
end;

{ ========================= TTyNotificationComponentTest ========================= }

procedure TTyNotificationComponentTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FClosed := 0;
  FClicked := 0;
end;

procedure TTyNotificationComponentTest.TearDown;
begin
  FCtl.Free;
end;

procedure TTyNotificationComponentTest.HandleClose(Sender: TObject);
begin
  Inc(FClosed);
end;

procedure TTyNotificationComponentTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

function TTyNotificationComponentTest.NewNote: TTyNotification;
begin
  Result := TNoteAccess.Create(nil);
  Result.Controller := FCtl;
end;

procedure TTyNotificationComponentTest.TestTypeKeys;
begin
  AssertEquals('TyNotification', TTyNotification.StyleTypeKey);
  AssertEquals('TyNotificationClose', TTyNotification.CloseStyleTypeKey);
end;

procedure TTyNotificationComponentTest.TestDefaults;
var
  N: TTyNotification;
begin
  N := TTyNotification.Create(nil);
  try
    AssertEquals('no title', '', N.Title);
    AssertEquals('no message', '', N.Message);
    AssertTrue('info by default', N.NotificationType = atInfo);
    AssertEquals('4.5s, as AntD', TyNotificationDuration, N.Duration);
    AssertTrue('top-right by default', N.Position = npTopRight);
    AssertTrue('closable by default', N.Closable);
    AssertTrue('marked by default', N.ShowIcon);
    AssertTrue('pauses on hover by default', N.PauseOnHover);
    AssertFalse('not showing until Show', N.Showing);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestNegativeDurationClampsToStay;
var
  N: TTyNotification;
begin
  N := NewNote;
  try
    N.Duration := -1;
    AssertEquals('a negative duration is a typo, not a rule', 0, N.Duration);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestCloseRectEmptyWhenNotClosable;
var
  N: TTyNotification;
  R: TRect;
begin
  FCtl.LoadThemeCss(ThemeCss);
  N := NewNote;
  try
    N.Closable := False;
    R := N.CloseRectIn(CCardW, CCardH, 96);
    AssertEquals('no slot while Closable=False', 0, R.Right - R.Left);
    // Turning it on materialises the slot with no other change.
    N.Closable := True;
    R := N.CloseRectIn(CCardW, CCardH, 96);
    AssertTrue('slot appears when Closable=True', R.Right > R.Left);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestCloseRectFollowsThemePadding;
var
  N: TTyNotification;
  R: TRect;
begin
  // The slot's edges are driven by the THEME's padding, not by a literal in the control.
  FCtl.LoadThemeCss(ThemeCss(340, 24, 14, 8, 16, 8,
    'TyNotification { background: #FFFFFF; color: #111111; padding: 20px 30px;'
    + ' font-size: 12px; }'));
  N := NewNote;
  try
    R := N.CloseRectIn(CCardW, CCardH, 96);
    AssertEquals('slot right = width - themed right padding', CCardW - 30, R.Right);
    AssertEquals('slot top = themed top padding', 20, R.Top);
    AssertEquals('slot keeps the themed size', 14, R.Right - R.Left);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestCloseSizeMetricRetunesSlot;
var
  N: TTyNotification;
  R: TRect;
begin
  // --notification-close-size is a skin-tunable metric: a theme that sets it moves the
  // geometry (and with it the hit-test), proving the slot is not baked into the control.
  FCtl.LoadThemeCss(ThemeCss(340, 24, 22));
  N := NewNote;
  try
    R := N.CloseRectIn(CCardW, CCardH, 96);
    AssertEquals('slot takes the themed size', 22, R.Right - R.Left);
    AssertEquals('and is still right-aligned in the band', CCardW - 14, R.Right);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestIconSizeMetricRetunesMarkSlot;
var
  N: TNoteAccess;
  L: TTyNotificationLayout;
begin
  FCtl.LoadThemeCss(ThemeCss(340, 32));
  N := TNoteAccess(NewNote);
  try
    N.Title := 'heads up';
    L := N.Layout(CCardW, CCardH, 96);
    AssertEquals('mark takes the themed size', 32, L.IconRect.Right - L.IconRect.Left);
    // ...and the text column starts past it, so the mark is extra room, not room stolen.
    AssertEquals('the column follows the mark', 14 + 32 + 8, L.TitleRect.Left);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestWidthMetricDrivesMeasuredCard;
var
  N: TTyNotification;
begin
  FCtl.LoadThemeCss(ThemeCss(260));
  N := NewNote;
  try
    // The card does not measure its text: its width is the theme's, flat.
    AssertEquals('the card takes the themed width', 260, N.MeasureAtPPI(96).cx);
    N.Message := 'a message far longer than two hundred and sixty pixels of anything';
    AssertEquals('and a long message does not widen it', 260, N.MeasureAtPPI(96).cx);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestMeasureGrowsWithMessageLines;
var
  N: TTyNotification;
  oneLine, threeLines: Integer;
begin
  // The message does not wrap — it splits on line breaks — so more lines is a taller card.
  FCtl.LoadThemeCss(ThemeCss);
  N := NewNote;
  try
    N.Title := 'saved';
    N.Message := 'one';
    oneLine := N.MeasureAtPPI(96).cy;
    N.Message := 'one' + LineEnding + 'two' + LineEnding + 'three';
    threeLines := N.MeasureAtPPI(96).cy;
    AssertTrue('three lines need a taller card', threeLines > oneLine);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestMeasureFloorsToTheMarkSlot;
var
  N: TTyNotification;
  withMark, withoutMark: Integer;
begin
  // A tiny-font, title-less toast is shorter than the mark's slot, so the mark floors the
  // card's height; hiding the mark lets the card shrink back to its text.
  FCtl.LoadThemeCss(ThemeCss(340, 24, 14, 8, 16, 8,
    'TyNotification { background: #FFFFFF; color: #111111; padding: 12px 14px;'
    + ' font-size: 6px; }'));
  N := NewNote;
  try
    N.Message := 'done';
    withMark := N.MeasureAtPPI(96).cy;
    AssertEquals('the floor is padding + the themed mark slot', 12 + 24 + 12, withMark);
    N.ShowIcon := False;
    withoutMark := N.MeasureAtPPI(96).cy;
    AssertTrue('with no mark to clear, the card shrinks to its text',
      withoutMark < withMark);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestMarkTakesTypeVariantInk;
var
  N: TNoteAccess;
begin
  // ONE typeKey carries two text roles: the base rule's colour is the title/message ink and
  // the TYPE VARIANT's colour is the mark's.
  FCtl.LoadThemeCss(ThemeCss(340, 24, 14, 8, 16, 8, CCard,
    'TyNotification.success { color: #10B981; }'));
  N := TNoteAccess(NewNote);
  try
    N.NotificationType := atSuccess;
    AssertEquals('the mark takes the variant''s ink',
      Integer(TyRGB($10, $B9, $81)), Integer(N.MarkInk));
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestMarkFallsBackToCardInkWithoutVariantRule;
var
  N: TNoteAccess;
begin
  // Graceful degradation: with no TyNotification.<type> rule the variant cascade resolves to
  // the base rule, so the mark simply takes the card's own ink — never a hard-coded colour.
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.NotificationType := atError;
    AssertEquals('mark ink = card ink', Integer(N.TextInk), Integer(N.MarkInk));
    AssertEquals('which is the theme''s',
      Integer(TyRGB($11, $11, $11)), Integer(N.MarkInk));
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestTextInkIgnoresTypeVariant;
var
  N: TNoteAccess;
begin
  // The variant colours the MARK, not the prose: a success toast still reads in the card ink.
  FCtl.LoadThemeCss(ThemeCss(340, 24, 14, 8, 16, 8, CCard,
    'TyNotification.success { color: #10B981; }'));
  N := TNoteAccess(NewNote);
  try
    N.NotificationType := atSuccess;
    AssertEquals('title/message keep the card ink',
      Integer(TyRGB($11, $11, $11)), Integer(N.TextInk));
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestClickCloseHidesAndFiresOnClose;
var
  N: TNoteAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.OnClose := @HandleClose;
    N.BeginShowing;
    R := N.CloseRectIn(CCardW, CCardH, 96);
    N.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired once', 1, FClosed);
    AssertFalse('and the toast is gone', N.Showing);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestClickCloseDoesNotFireOnClick;
var
  N: TNoteAccess;
  R: TRect;
begin
  // The whole point of the split gesture: "get rid of this" must not also read as "the user
  // chose this" (a toast whose click opens a log would open it on the way out otherwise).
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.OnClose := @HandleClose;
    N.OnClick := @HandleClick;
    N.BeginShowing;
    R := N.CloseRectIn(CCardW, CCardH, 96);
    N.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired', 1, FClosed);
    AssertEquals('OnClick swallowed', 0, FClicked);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestClickCardFiresOnClickAndKeepsToast;
var
  N: TNoteAccess;
begin
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.OnClose := @HandleClose;
    N.OnClick := @HandleClick;
    N.BeginShowing;
    N.PressReleaseAt(20, 40);   // well left of the slot (which starts at x=272)
    AssertEquals('OnClick fired', 1, FClicked);
    AssertEquals('OnClose did not', 0, FClosed);
    // A click is not a dismissal: what it means is the host's business.
    AssertTrue('the toast stays up', N.Showing);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestDragOffCloseCancelsGesture;
var
  N: TNoteAccess;
  R: TRect;
begin
  // Press the x, drag onto the card, release: like any push button the gesture is cancelled —
  // no close, and no stray OnClick either (the press was never the card's).
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.OnClose := @HandleClose;
    N.OnClick := @HandleClick;
    N.BeginShowing;
    R := N.CloseRectIn(CCardW, CCardH, 96);
    N.PressAtReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2, 20, 40);
    AssertEquals('no close', 0, FClosed);
    AssertEquals('no click', 0, FClicked);
    AssertTrue('still showing', N.Showing);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestUnclosableIgnoresClickWhereXWouldBe;
var
  N: TNoteAccess;
begin
  // Closable=False: the same coordinates are ordinary card surface, so they click.
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.Closable := False;
    N.OnClose := @HandleClose;
    N.OnClick := @HandleClick;
    N.BeginShowing;
    N.PressReleaseAt(279, 19);   // where the x sits on a closable toast
    AssertEquals('no close on an unclosable toast', 0, FClosed);
    AssertEquals('the press is a plain card click', 1, FClicked);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestAutoDismissAtDuration;
var
  N: TNoteAccess;
begin
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.Duration := 500;
    N.OnClose := @HandleClose;
    N.BeginShowing;
    AssertFalse('not up yet', N.AdvanceTime(400));
    AssertTrue('still showing', N.Showing);
    AssertTrue('this tick dismissed it', N.AdvanceTime(100));
    AssertFalse('gone', N.Showing);
    AssertEquals('OnClose fired once', 1, FClosed);
    // A tick after the dismissal must not fire anything a second time.
    AssertFalse('a late tick is inert', N.AdvanceTime(1000));
    AssertEquals('OnClose still once', 1, FClosed);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestZeroDurationStaysUntilHidden;
var
  N: TNoteAccess;
begin
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.Duration := 0;
    N.OnClose := @HandleClose;
    N.BeginShowing;
    AssertFalse('no countdown at all', N.AdvanceTime(100000));
    AssertTrue('still up', N.Showing);
    N.Hide;
    AssertFalse('gone only when told', N.Showing);
    AssertEquals('OnClose fired for the explicit Hide', 1, FClosed);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestHoverFreezesCountdown;
var
  N: TNoteAccess;
begin
  // A toast must not expire out from under someone who is reading it.
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.Duration := 1000;
    N.BeginShowing;
    N.MoveTo(20, 40);   // on the card, clear of the x
    AssertFalse('frozen while hovered', N.AdvanceTime(5000));
    AssertTrue('still showing', N.Showing);
    N.LeaveCard;
    AssertTrue('and it resumes on leave', N.AdvanceTime(1000));
    AssertFalse('dismissed', N.Showing);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestPauseOnHoverOffKeepsCounting;
var
  N: TNoteAccess;
begin
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.Duration := 1000;
    N.PauseOnHover := False;
    N.BeginShowing;
    N.MoveTo(20, 40);
    AssertTrue('the pointer no longer stops the clock', N.AdvanceTime(1000));
    AssertFalse('dismissed under the pointer', N.Showing);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestHideIsIdempotent;
var
  N: TNoteAccess;
begin
  FCtl.LoadThemeCss(ThemeCss);
  N := TNoteAccess(NewNote);
  try
    N.OnClose := @HandleClose;
    N.BeginShowing;
    N.Hide;
    N.Hide;
    N.Hide;
    AssertEquals('OnClose fires once per dismissal, not once per call', 1, FClosed);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestSlotHugsChosenCorner;
var
  N: TTyNotification;
  WA, R: TRect;
begin
  FCtl.LoadThemeCss(ThemeCss);
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  N := NewNote;
  try
    N.Title := 'saved';
    N.Message := 'all good';
    // The default corner: top-right, one themed margin in on both axes.
    R := N.SlotRectIn(WA, 96);
    AssertEquals('hugs the right edge', CWorkR - 16, R.Right);
    AssertEquals('and the top edge', CWorkT + 16, R.Top);
    AssertEquals('at the themed width', 340, R.Right - R.Left);
    N.Position := npBottomLeft;
    R := N.SlotRectIn(WA, 96);
    AssertEquals('hugs the left edge', CWorkL + 16, R.Left);
    AssertEquals('and the bottom edge', CWorkB - 16, R.Bottom);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestSecondToastStacksBelowFirst;
var
  N1, N2: TNoteAccess;
  WA, R1, R2: TRect;
begin
  FCtl.LoadThemeCss(ThemeCss);
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  N1 := TNoteAccess(NewNote);
  N2 := TNoteAccess(NewNote);
  try
    N1.Title := 'first';
    N2.Title := 'second';
    N1.BeginShowing;
    N2.BeginShowing;
    R1 := N1.SlotRectIn(WA, 96);
    R2 := N2.SlotRectIn(WA, 96);
    AssertEquals('the elder keeps the corner', CWorkT + 16, R1.Top);
    AssertEquals('the newcomer sits one themed gap below it', R1.Bottom + 8, R2.Top);
  finally
    N2.Free;
    N1.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestOtherCornerDoesNotStack;
var
  N1, N2: TNoteAccess;
  WA, R2: TRect;
begin
  // A stack is per-corner: a toast in another corner is not above me.
  FCtl.LoadThemeCss(ThemeCss);
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  N1 := TNoteAccess(NewNote);
  N2 := TNoteAccess(NewNote);
  try
    N1.Title := 'first';
    N2.Title := 'second';
    N2.Position := npTopLeft;
    N1.BeginShowing;
    N2.BeginShowing;
    R2 := N2.SlotRectIn(WA, 96);
    AssertEquals('the top-left toast still owns its own corner', CWorkT + 16, R2.Top);
  finally
    N2.Free;
    N1.Free;
  end;
end;

procedure TTyNotificationComponentTest.TestClosingMiddleToastRestacksTheRest;
var
  N1, N2, N3: TNoteAccess;
  WA, R2Before, R3After: TRect;
begin
  // One closing out of the MIDDLE of a stack must not leave a hole.
  FCtl.LoadThemeCss(ThemeCss);
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  N1 := TNoteAccess(NewNote);
  N2 := TNoteAccess(NewNote);
  N3 := TNoteAccess(NewNote);
  try
    N1.Title := 'a';
    N2.Title := 'b';
    N3.Title := 'c';
    N1.BeginShowing;
    N2.BeginShowing;
    N3.BeginShowing;
    R2Before := N2.SlotRectIn(WA, 96);
    AssertTrue('the third starts below the second', N3.SlotRectIn(WA, 96).Top > R2Before.Top);
    N2.Hide;
    R3After := N3.SlotRectIn(WA, 96);
    AssertEquals('the toast below moves up into the gap', R2Before.Top, R3After.Top);
  finally
    N3.Free;
    N2.Free;
    N1.Free;
  end;
end;

{ TestCardRendersThemeBackground
  Theme: a strongly blue TyNotification fill. Probe inside the card's padding band and assert
  it is the themed fill — i.e. the card paints from the token, not from an LCL colour. }
procedure TTyNotificationComponentTest.TestCardRendersThemeBackground;
var
  N: TNoteAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(ThemeCss(340, 24, 14, 8, 16, 8,
    'TyNotification { background: #3B82F6; color: #FFFFFF; padding: 12px 14px;'
    + ' font-size: 12px; }'));
  Bmp := TBitmap.Create;
  N := TNoteAccess(NewNote);
  try
    N.Title := 'saved';
    N.Message := 'all good';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(CCardW, CCardH);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, CCardW, CCardH);
    N.RenderTo(Bmp.Canvas, Rect(0, 0, CCardW, CCardH), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // Inside the left padding band: no glyph, no text, no corner.
      Px := Reread.GetPixel(4, CCardH div 2);
      AssertTrue('card painted in the themed fill', (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    N.Free;
    Bmp.Free;
  end;
end;

{ TestCloseGlyphRendersThemeInk
  TyNotificationClose sets its own colour: the x must take THAT ink (not the card's text
  colour), proving the glyph resolves from its own typeKey. }
procedure TTyNotificationComponentTest.TestCloseGlyphRendersThemeInk;
var
  N: TNoteAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  R: TRect;
  x, y: Integer;
  found: Boolean;
begin
  // White card, white ink (so the mark and the text are invisible), GREEN x: any green pixel
  // in the slot can only be the TyNotificationClose colour.
  FCtl.LoadThemeCss(ThemeCss(340, 24, 14, 8, 16, 8,
    'TyNotification { background: #FFFFFF; color: #FFFFFF; padding: 12px 14px;'
    + ' font-size: 12px; }',
    'TyNotificationClose { color: #10B981; }'));
  Bmp := TBitmap.Create;
  N := TNoteAccess(NewNote);
  try
    N.Title := 'saved';
    R := N.CloseRectIn(CCardW, CCardH, 96);
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(CCardW, CCardH);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, CCardW, CCardH);
    N.RenderTo(Bmp.Canvas, Rect(0, 0, CCardW, CCardH), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      found := False;
      for y := R.Top to R.Bottom - 1 do
        for x := R.Left to R.Right - 1 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('x drawn in the TyNotificationClose ink', found);
    finally
      Reread.Free;
    end;
  finally
    N.Free;
    Bmp.Free;
  end;
end;

{ TestNoThemedBackgroundDrawsNothing
  A theme whose TyNotification rule declares no background gets NO card — not a hard-coded
  one. NOTE the rule must be PRESENT-but-backgroundless rather than simply omitted: with the
  property cascade off (the default) the engine applies its built-in base layer to any typeKey
  the loaded theme leaves untouched, so an omitted rule would resolve the SHIPPED card and this
  would test the engine, not the control. }
procedure TTyNotificationComponentTest.TestNoThemedBackgroundDrawsNothing;
var
  N: TNoteAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(ThemeCss(340, 24, 14, 8, 16, 8,
    'TyNotification { color: #111111; padding: 12px 14px; font-size: 12px; }'));
  Bmp := TBitmap.Create;
  N := TNoteAccess(NewNote);
  try
    N.Title := 'saved';
    N.Message := 'all good';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(CCardW, CCardH);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, CCardW, CCardH);
    N.RenderTo(Bmp.Canvas, Rect(0, 0, CCardW, CCardH), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // Not the card, not the title, not the mark, not the x: nothing at all.
      Px := Reread.GetPixel(CCardW div 2, CCardH div 2);
      AssertTrue('nothing painted in the middle',
        (Px.red > 200) and (Px.green < 60) and (Px.blue < 60));
      Px := Reread.GetPixel(2, 2);
      AssertTrue('nor in the corner',
        (Px.red > 200) and (Px.green < 60) and (Px.blue < 60));
    finally
      Reread.Free;
    end;
  finally
    N.Free;
    Bmp.Free;
  end;
end;

{ ============================ TTyNotificationHostTest ============================ }

const
  { Two host areas: neither at the origin, neither the size of the other or of the screen, so
    a rect worked out against the wrong area cannot land on the right numbers. }
  CHostAL = 300;
  CHostAT = 200;
  CHostAW = 800;
  CHostAH = 600;
  CHostBL = 1200;
  CHostBT = 100;
  CHostBW = 700;
  CHostBH = 500;
  { Where the real-window suite puts "the screen": far off it, so a toast that falls back
    does not flash on the desktop the tests run on. }
  COffL = -9000;
  COffT = -9000;
  COffR = -7000;
  COffB = -8000;

type
  { A stand-in host: a real TForm for its identity and for LCL's own change-handler lists,
    never shown. What a toast would read from the window comes from here instead: the "client
    area" is the form's own bounds (so SetBounds both moves the area and makes LCL report the
    change), and on-screen / minimised are plain switches. }
  THostStub = class(TForm)
  public
    SimVisible: Boolean;
    SimMinimized: Boolean;
    { What LCL does when Visible changes, without putting a window on screen. }
    procedure FireVisibleChanged;
  end;

  { A toast that reads a THostStub instead of a window and a pinned rect instead of the
    screen. Any other form (and an empty WorkArea) goes to the real thing. }
  THostedNote = class(TNoteAccess)
  public
    WorkArea: TRect;       // stands in for the screen work area
    StateReads: Integer;   // how often the host window was looked at
    Changes: Integer;      // how often the host reported a change
    function HostState: TTyNotificationHostState; override;
    function ScreenArea: TRect; override;
    procedure HostChanged; override;
    { Up, with a window to place but none on screen. }
    procedure ShowWindowless;
    procedure PlaceWindow;
    function WindowRect: TRect;
    function WindowShown: Boolean;
  end;

procedure THostStub.FireVisibleChanged;
begin
  VisibleChanged;
end;

function THostedNote.HostState: TTyNotificationHostState;
begin
  Inc(StateReads);
  if HostForm is THostStub then
  begin
    Result.Visible := THostStub(HostForm).SimVisible;
    Result.Minimized := THostStub(HostForm).SimMinimized;
    Result.ClientArea := HostForm.BoundsRect;
  end
  else
    Result := inherited HostState;
end;

var
  { How often a toast that is being destroyed was placed on the screen. Counted here because
    the toast itself is gone by the time a test could ask it. }
  GDyingScreenAsks: Integer = 0;

function THostedNote.ScreenArea: TRect;
begin
  if csDestroying in ComponentState then Inc(GDyingScreenAsks);
  if IsRectEmpty(WorkArea) then
    Result := inherited ScreenArea
  else
    Result := WorkArea;
end;

procedure THostedNote.HostChanged;
begin
  Inc(Changes);
  inherited HostChanged;
end;

procedure THostedNote.ShowWindowless;
begin
  BeginShowing;
  NeedWindow;
  inherited PlaceWindow;
end;

procedure THostedNote.PlaceWindow;
begin
  inherited PlaceWindow;
end;

function THostedNote.WindowRect: TRect;
begin
  Result := Window.BoundsRect;
end;

function THostedNote.WindowShown: Boolean;
begin
  Result := (Window <> nil) and Window.Visible;
end;

{ A stand-in host at the given "client area", on screen. }
function NewHost(AL, AT, AW, AH: Integer): THostStub;
begin
  Result := THostStub.CreateNew(nil);
  Result.SetBounds(AL, AT, AW, AH);
  Result.SimVisible := True;
  // LCL reports a form's bounds change on the next message; this one is the fixture's, not
  // the test's, so let it go by before anything listens.
  Forms.Application.ProcessMessages;
end;

function NewHostA: THostStub;
begin
  Result := NewHost(CHostAL, CHostAT, CHostAW, CHostAH);
end;

function NewHostB: THostStub;
begin
  Result := NewHost(CHostBL, CHostBT, CHostBW, CHostBH);
end;

{ A toast in AHost (nil = none), themed by ACtl, with the fixture's screen. }
function NewHosted(ACtl: TTyStyleController; AHost: TCustomForm): THostedNote;
begin
  Result := THostedNote.Create(nil);
  Result.Controller := ACtl;
  Result.WorkArea := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  Result.Title := 'saved';
  Result.HostForm := AHost;
end;

{ Logical px -> the px PlaceWindow works in. }
function Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

function RectStr(const R: TRect): string;
begin
  Result := Format('(%d,%d)-(%d,%d)', [R.Left, R.Top, R.Right, R.Bottom]);
end;

procedure TTyNotificationHostTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ThemeCss);
  FAreaAsks := 0;
  FTrim := Rect(0, 0, 0, 0);
end;

procedure TTyNotificationHostTest.TearDown;
begin
  FCtl.Free;
end;

procedure TTyNotificationHostTest.HandleHostArea(Sender: TObject; var AArea: TRect);
begin
  Inc(FAreaAsks);
  Inc(AArea.Left, FTrim.Left);
  Inc(AArea.Top, FTrim.Top);
  Dec(AArea.Right, FTrim.Right);
  Dec(AArea.Bottom, FTrim.Bottom);
end;

procedure TTyNotificationHostTest.TestHostFormDefaultsToNoHost;
var
  N: TTyNotification;
begin
  N := TTyNotification.Create(nil);
  try
    AssertNull('no host until one is set', N.HostForm);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostTest.TestWithoutAHostTheSlotIsTheScreenCornerAsBefore;
var
  H: THostStub;
  N1, N2: THostedNote;
  cy: Integer;
  WA: TRect;
begin
  // A usable host exists, but nobody set it: the toast must not so much as look at one.
  WA := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  H := NewHostA;
  N1 := NewHosted(FCtl, nil);
  N2 := NewHosted(FCtl, nil);
  try
    cy := N1.MeasureAtPPI(96).cy;
    AssertEquals('top-right', RectStr(Rect(CWorkR - 16 - 340, CWorkT + 16, CWorkR - 16, CWorkT + 16 + cy)),
      RectStr(N1.SlotRect(96)));
    N1.Position := npTopLeft;
    AssertEquals('top-left', RectStr(Rect(CWorkL + 16, CWorkT + 16, CWorkL + 16 + 340, CWorkT + 16 + cy)),
      RectStr(N1.SlotRect(96)));
    N1.Position := npBottomLeft;
    AssertEquals('bottom-left', RectStr(Rect(CWorkL + 16, CWorkB - 16 - cy, CWorkL + 16 + 340, CWorkB - 16)),
      RectStr(N1.SlotRect(96)));
    N1.Position := npBottomRight;
    AssertEquals('bottom-right', RectStr(Rect(CWorkR - 16 - 340, CWorkB - 16 - cy, CWorkR - 16, CWorkB - 16)),
      RectStr(N1.SlotRect(96)));
    // And stacked: the second is one themed gap further from the corner.
    N2.Position := npBottomRight;
    N1.BeginShowing;
    N2.BeginShowing;
    AssertEquals('the second, stacked',
      RectStr(Rect(CWorkR - 16 - 340, CWorkB - 16 - cy - 8 - cy, CWorkR - 16, CWorkB - 16 - cy - 8)),
      RectStr(N2.SlotRect(96)));
    AssertEquals('which is what SlotRectIn gives for that area',
      RectStr(N2.SlotRectIn(WA, 96)), RectStr(N2.SlotRect(96)));
    AssertEquals('a toast with no host never looks at one', 0, N1.StateReads + N2.StateReads);
    AssertFalse('and asked outright, no host is not a host on screen', N1.HostState.Visible);
  finally
    N2.Free;
    N1.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestWithoutAHostTheRealScreenWorkAreaIsUsed;
var
  N: TTyNotification;
begin
  // No stand-in at all: the area is the one the unit has always used.
  N := TTyNotification.Create(nil);
  try
    N.Controller := FCtl;
    N.Title := 'saved';
    // Every corner: a task bar takes one edge only, so one corner alone could not tell the
    // work area from the whole screen.
    AssertEquals('top-right', RectStr(N.SlotRectIn(Screen.WorkAreaRect, 96)), RectStr(N.SlotRect(96)));
    N.Position := npTopLeft;
    AssertEquals('top-left', RectStr(N.SlotRectIn(Screen.WorkAreaRect, 96)), RectStr(N.SlotRect(96)));
    N.Position := npBottomLeft;
    AssertEquals('bottom-left', RectStr(N.SlotRectIn(Screen.WorkAreaRect, 96)), RectStr(N.SlotRect(96)));
    N.Position := npBottomRight;
    AssertEquals('bottom-right', RectStr(N.SlotRectIn(Screen.WorkAreaRect, 96)), RectStr(N.SlotRect(96)));
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAHostedSlotHugsEachCornerOfTheHostArea;
var
  H: THostStub;
  N: THostedNote;
  cy: Integer;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    cy := N.MeasureAtPPI(96).cy;
    AssertEquals('top-right of the host',
      RectStr(Rect(CHostAL + CHostAW - 16 - 340, CHostAT + 16, CHostAL + CHostAW - 16, CHostAT + 16 + cy)),
      RectStr(N.SlotRect(96)));
    N.Position := npTopLeft;
    AssertEquals('top-left of the host',
      RectStr(Rect(CHostAL + 16, CHostAT + 16, CHostAL + 16 + 340, CHostAT + 16 + cy)),
      RectStr(N.SlotRect(96)));
    N.Position := npBottomLeft;
    AssertEquals('bottom-left of the host',
      RectStr(Rect(CHostAL + 16, CHostAT + CHostAH - 16 - cy, CHostAL + 16 + 340, CHostAT + CHostAH - 16)),
      RectStr(N.SlotRect(96)));
    N.Position := npBottomRight;
    AssertEquals('bottom-right of the host',
      RectStr(Rect(CHostAL + CHostAW - 16 - 340, CHostAT + CHostAH - 16 - cy,
        CHostAL + CHostAW - 16, CHostAT + CHostAH - 16)),
      RectStr(N.SlotRect(96)));
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestToastsOfOneHostStack;
var
  H: THostStub;
  N1, N2: THostedNote;
  R1, R2: TRect;
begin
  H := NewHostA;
  N1 := NewHosted(FCtl, H);
  N2 := NewHosted(FCtl, H);
  try
    N1.Position := npBottomLeft;
    N2.Position := npBottomLeft;
    N1.BeginShowing;
    N2.BeginShowing;
    R1 := N1.SlotRect(96);
    R2 := N2.SlotRect(96);
    AssertEquals('the elder keeps the host''s corner', CHostAT + CHostAH - 16, R1.Bottom);
    AssertEquals('the newcomer sits one themed gap above it', R1.Top - 8, R2.Bottom);
    AssertEquals('against the same edge of the host', CHostAL + 16, R2.Left);
  finally
    N2.Free;
    N1.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestToastsOfTwoHostsDoNotPushEachOther;
var
  HA, HB: THostStub;
  A1, B1, A2: THostedNote;
begin
  HA := NewHostA;
  HB := NewHostB;
  A1 := NewHosted(FCtl, HA);
  B1 := NewHosted(FCtl, HB);
  A2 := NewHosted(FCtl, HA);
  try
    A1.BeginShowing;
    B1.BeginShowing;
    A2.BeginShowing;
    AssertEquals('the other form''s toast has its own corner', CHostBT + 16, B1.SlotRect(96).Top);
    AssertEquals('in its own form', CHostBL + CHostBW - 16, B1.SlotRect(96).Right);
    AssertEquals('and is not counted between the two that share a form',
      A1.SlotRect(96).Bottom + 8, A2.SlotRect(96).Top);
  finally
    A2.Free;
    B1.Free;
    A1.Free;
    HB.Free;
    HA.Free;
  end;
end;

procedure TTyNotificationHostTest.TestScreenAndHostedToastsDoNotPushEachOther;
var
  H: THostStub;
  S1, A1, S2, A2: THostedNote;
begin
  H := NewHostA;
  S1 := NewHosted(FCtl, nil);
  A1 := NewHosted(FCtl, H);
  S2 := NewHosted(FCtl, nil);
  A2 := NewHosted(FCtl, H);
  try
    S1.BeginShowing;
    A1.BeginShowing;
    S2.BeginShowing;
    A2.BeginShowing;
    AssertEquals('the first screen toast has the screen corner', CWorkT + 16, S1.SlotRect(96).Top);
    AssertEquals('the first form toast has the form''s, not a place under it',
      CHostAT + 16, A1.SlotRect(96).Top);
    AssertEquals('the second screen toast counts only the first screen toast',
      S1.SlotRect(96).Bottom + 8, S2.SlotRect(96).Top);
    AssertEquals('the second form toast counts only the first form toast',
      A1.SlotRect(96).Bottom + 8, A2.SlotRect(96).Top);
  finally
    A2.Free;
    S2.Free;
    A1.Free;
    S1.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestSlotRectInCountsOnlyTheToastsOwnStack;
var
  H: THostStub;
  S1, A1, A2, S2, S3: THostedNote;
  Any: TRect;
  cy: Integer;
begin
  // SlotRectIn takes whatever area it is handed, but whose toasts are stacked before this one
  // is still the toast's own business: a form toast counts its form's, a screen toast the
  // screen's. Two screen toasts come before the form's second toast and one form toast, so
  // counting the wrong stack (2), or both (3), cannot give the right number (1); and the last
  // screen toast has two of its own before it and four in all.
  Any := Rect(5000, 3000, 6000, 4000);
  H := NewHostA;
  S1 := NewHosted(FCtl, nil);
  S2 := NewHosted(FCtl, nil);
  A1 := NewHosted(FCtl, H);
  A2 := NewHosted(FCtl, H);
  S3 := NewHosted(FCtl, nil);
  try
    cy := S1.MeasureAtPPI(96).cy;
    S1.BeginShowing;
    S2.BeginShowing;
    A1.BeginShowing;
    A2.BeginShowing;
    S3.BeginShowing;
    AssertEquals('the second form toast is behind one card', 3000 + 16 + (cy + 8),
      A2.SlotRectIn(Any, 96).Top);
    AssertEquals('the third screen toast behind two', 3000 + 16 + 2 * (cy + 8),
      S3.SlotRectIn(Any, 96).Top);
  finally
    S3.Free;
    S2.Free;
    A2.Free;
    A1.Free;
    S1.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestTheSlotMovesWithTheHostArea;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    AssertEquals('setup', CHostAL + CHostAW - 16, N.SlotRect(96).Right);
    // Moved AND resized, by different amounts on each axis.
    H.SetBounds(CHostAL + 250, CHostAT - 70, CHostAW - 100, CHostAH + 40);
    AssertEquals('the right edge went with the host''s', CHostAL + 250 + CHostAW - 100 - 16,
      N.SlotRect(96).Right);
    AssertEquals('and the top with its top', CHostAT - 70 + 16, N.SlotRect(96).Top);
    N.Position := npBottomLeft;
    AssertEquals('the bottom with its bottom', CHostAT - 70 + CHostAH + 40 - 16,
      N.SlotRect(96).Bottom);
    AssertEquals('the left with its left', CHostAL + 250 + 16, N.SlotRect(96).Left);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAHostNotOnScreenSendsItsToastToTheScreen;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    AssertEquals('setup: on screen, the host has it', CHostAT + 16, N.SlotRect(96).Top);
    H.SimVisible := False;
    AssertEquals('not on screen: the screen corner', CWorkT + 16, N.SlotRect(96).Top);
    AssertEquals('of the screen work area', CWorkR - 16, N.SlotRect(96).Right);
    AssertSame('and the property still names the host', H, N.HostForm);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAMinimisedHostSendsItsToastToTheScreen;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    H.SimMinimized := True;
    AssertEquals('minimised: the screen corner', CWorkT + 16, N.SlotRect(96).Top);
    AssertEquals('of the screen work area', CWorkR - 16, N.SlotRect(96).Right);
    H.SimMinimized := False;
    AssertEquals('restored: the host again', CHostAT + 16, N.SlotRect(96).Top);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAHostSmallerThanTheCardSendsItsToastToTheScreen;
var
  H: THostStub;
  N: THostedNote;
  cy: Integer;
begin
  H := NewHost(CHostAL, CHostAT, 339, CHostAH);
  N := NewHosted(FCtl, H);
  try
    cy := N.MeasureAtPPI(96).cy;
    AssertEquals('one px narrower than the card: the screen', CWorkR - 16, N.SlotRect(96).Right);
    H.SetBounds(CHostAL, CHostAT, 340, CHostAH);
    // The margin gives way: the card fills the host edge to edge.
    AssertEquals('exactly the card''s width: the host', CHostAL + 340, N.SlotRect(96).Right);
    H.SetBounds(CHostAL, CHostAT, CHostAW, cy - 1);
    AssertEquals('one px shorter than the card: the screen', CWorkT + 16, N.SlotRect(96).Top);
    H.SetBounds(CHostAL, CHostAT, CHostAW, cy);
    AssertEquals('exactly the card''s height: the host', CHostAT, N.SlotRect(96).Top);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAFormNeverShownIsNotAHost;
var
  F: TForm;
  N: THostedNote;
begin
  // No stand-in: a plain form, read the way the unit really reads one. It has never been
  // shown, so it has no client area on screen to stand in.
  F := TForm.CreateNew(nil);
  N := NewHosted(FCtl, F);
  try
    F.SetBounds(CHostAL, CHostAT, CHostAW, CHostAH);
    AssertEquals('the screen corner', CWorkR - 16, N.SlotRect(96).Right);
    AssertEquals('not the form''s', CWorkT + 16, N.SlotRect(96).Top);
    AssertTrue('and it did ask the form', N.StateReads > 0);
  finally
    N.Free;
    F.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAToastSentToTheScreenStacksWithTheScreenToasts;
var
  H: THostStub;
  S1, T, S2: THostedNote;
begin
  H := NewHostA;
  H.SimVisible := False;
  S1 := NewHosted(FCtl, nil);
  T := NewHosted(FCtl, H);
  S2 := NewHosted(FCtl, nil);
  try
    S1.BeginShowing;
    T.BeginShowing;
    S2.BeginShowing;
    AssertEquals('it queues under the screen toast before it', S1.SlotRect(96).Bottom + 8,
      T.SlotRect(96).Top);
    AssertEquals('on the screen', CWorkR - 16, T.SlotRect(96).Right);
    AssertEquals('and the screen toast after it queues under it', T.SlotRect(96).Bottom + 8,
      S2.SlotRect(96).Top);
  finally
    S2.Free;
    T.Free;
    S1.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAMovedHostRePlacesItsShowingToasts;
var
  H: THostStub;
  N1, N2, S: THostedNote;
  RS: TRect;
begin
  H := NewHostA;
  N1 := NewHosted(FCtl, H);
  N2 := NewHosted(FCtl, H);
  S := NewHosted(FCtl, nil);
  try
    N1.ShowWindowless;
    N2.ShowWindowless;
    S.ShowWindowless;
    AssertEquals('setup: the window is in the host''s corner', CHostAL + CHostAW - Px(16),
      N1.WindowRect.Right);
    AssertEquals('setup', CHostAT + Px(16), N1.WindowRect.Top);
    RS := S.WindowRect;
    AssertEquals('setup: the screen toast is in the screen''s', CWorkT + Px(16), RS.Top);

    H.SetBounds(CHostAL + 250, CHostAT - 70, CHostAW - 100, CHostAH);
    Forms.Application.ProcessMessages;

    AssertEquals('the window went with the host''s right edge',
      CHostAL + 250 + CHostAW - 100 - Px(16), N1.WindowRect.Right);
    AssertEquals('and with its top', CHostAT - 70 + Px(16), N1.WindowRect.Top);
    AssertEquals('the second went along', CHostAL + 250 + CHostAW - 100 - Px(16),
      N2.WindowRect.Right);
    AssertEquals('still one gap below the first', N1.WindowRect.Bottom + Px(8), N2.WindowRect.Top);
    AssertEquals('the screen toast stayed where it was', RectStr(RS), RectStr(S.WindowRect));

    // Dismissed, a toast is not re-placed any more, even told outright that its host changed.
    RS := N1.WindowRect;
    N1.Hide;
    H.SetBounds(CHostAL, CHostAT, CHostAW, CHostAH);
    Forms.Application.ProcessMessages;
    N1.HostChanged;
    AssertEquals('a dismissed toast''s window is left alone', RectStr(RS), RectStr(N1.WindowRect));
    AssertEquals('and the one still up took the corner it left', CHostAT + Px(16), N2.WindowRect.Top);
  finally
    S.Free;
    N2.Free;
    N1.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAHostIsWatchedOnlyWhileItsToastIsUp;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    H.SetBounds(CHostAL + 10, CHostAT, CHostAW, CHostAH);
    Forms.Application.ProcessMessages;
    H.FireVisibleChanged;
    AssertEquals('a toast that is not up follows nothing', 0, N.Changes);

    N.BeginShowing;
    H.SetBounds(CHostAL + 20, CHostAT, CHostAW, CHostAH);
    Forms.Application.ProcessMessages;
    AssertEquals('up: the host''s move reaches it', 1, N.Changes);
    H.FireVisibleChanged;
    AssertEquals('and so does the host being shown or hidden', 2, N.Changes);

    N.Hide;
    H.SetBounds(CHostAL + 30, CHostAT, CHostAW, CHostAH);
    Forms.Application.ProcessMessages;
    H.FireVisibleChanged;
    AssertEquals('dismissed: it has let go of the host', 2, N.Changes);

    // Up again: watched again, once (not once per Show).
    N.BeginShowing;
    N.BeginShowing;
    H.FireVisibleChanged;
    AssertEquals('shown again: watched again, once', 3, N.Changes);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestChangingHostFormMovesTheToastAndTheWatch;
var
  HA, HB: THostStub;
  N: THostedNote;
begin
  HA := NewHostA;
  HB := NewHostB;
  N := NewHosted(FCtl, HA);
  try
    N.ShowWindowless;
    AssertEquals('setup: in the first host', CHostAL + CHostAW - Px(16), N.WindowRect.Right);

    N.HostForm := HB;
    AssertEquals('re-placed into the new host at once', CHostBL + CHostBW - Px(16),
      N.WindowRect.Right);
    AssertEquals('in its corner', CHostBT + Px(16), N.WindowRect.Top);

    N.Changes := 0;
    HA.SetBounds(CHostAL + 10, CHostAT, CHostAW, CHostAH);
    Forms.Application.ProcessMessages;
    HA.FireVisibleChanged;
    AssertEquals('the host it left is no longer watched', 0, N.Changes);
    HB.SetBounds(CHostBL + 10, CHostBT, CHostBW, CHostBH);
    Forms.Application.ProcessMessages;
    AssertEquals('the host it joined is', 1, N.Changes);
    AssertEquals('and followed', CHostBL + 10 + CHostBW - Px(16), N.WindowRect.Right);

    N.HostForm := nil;
    AssertEquals('no host: the screen corner', CWorkR - Px(16), N.WindowRect.Right);
    AssertEquals('of the work area', CWorkT + Px(16), N.WindowRect.Top);
    N.Changes := 0;
    HB.SetBounds(CHostBL + 20, CHostBT, CHostBW, CHostBH);
    Forms.Application.ProcessMessages;
    HB.FireVisibleChanged;
    AssertEquals('and nothing is watched', 0, N.Changes);
  finally
    N.Free;
    HB.Free;
    HA.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAHostComingBackTakesItsToastBack;
var
  H: THostStub;
  T, S: THostedNote;
begin
  H := NewHostA;
  H.SimVisible := False;
  T := NewHosted(FCtl, H);
  S := NewHosted(FCtl, nil);
  try
    T.ShowWindowless;
    S.ShowWindowless;
    AssertEquals('setup: shown while its host is away, it took the screen corner',
      CWorkT + Px(16), T.WindowRect.Top);
    AssertEquals('setup: and the screen toast queued under it', T.WindowRect.Bottom + Px(8),
      S.WindowRect.Top);

    H.SimVisible := True;
    H.FireVisibleChanged;
    AssertEquals('the host took its toast back', CHostAL + CHostAW - Px(16), T.WindowRect.Right);
    AssertEquals('into its corner', CHostAT + Px(16), T.WindowRect.Top);
    AssertEquals('and the screen toast closed the gap it left', CWorkT + Px(16), S.WindowRect.Top);

    H.SimVisible := False;
    H.FireVisibleChanged;
    AssertEquals('away again: back on the screen, ahead of the toast shown after it',
      CWorkT + Px(16), T.WindowRect.Top);
    AssertEquals('which makes room', T.WindowRect.Bottom + Px(8), S.WindowRect.Top);
  finally
    S.Free;
    T.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAFreedToastIsOffItsHostsHandlerLists;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  try
    N := NewHosted(FCtl, H);
    N.BeginShowing;
    // Freed while up, with the freed memory poisoned: a handler left on the host's lists
    // would be called into it.
    BeginPoison;
    try
      N.Free;
      H.FireVisibleChanged;
      H.SetBounds(CHostAL + 10, CHostAT, CHostAW, CHostAH);
      Forms.Application.ProcessMessages;
    finally
      EndPoison;
    end;
  finally
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestFreeingTheHostClearsHostForm;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    AssertSame('setup', H, N.HostForm);
    FreeAndNil(H);
    AssertNull('a freed host is let go of', N.HostForm);
    AssertEquals('and the toast is a screen toast again', CWorkR - 16, N.SlotRect(96).Right);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestFreeingTheHostSendsItsShowingToastToTheScreen;
var
  H: THostStub;
  T, S: THostedNote;
begin
  H := NewHostA;
  T := NewHosted(FCtl, H);
  S := NewHosted(FCtl, nil);
  try
    T.ShowWindowless;
    S.ShowWindowless;
    AssertEquals('setup: in the host', CHostAT + Px(16), T.WindowRect.Top);
    AssertEquals('setup: the screen toast has the screen corner', CWorkT + Px(16), S.WindowRect.Top);
    BeginPoison;
    try
      FreeAndNil(H);
      AssertEquals('the toast it held went to the screen', CWorkR - Px(16), T.WindowRect.Right);
      AssertEquals('to its corner', CWorkT + Px(16), T.WindowRect.Top);
      AssertEquals('and the screen toast shown after it made room', T.WindowRect.Bottom + Px(8),
        S.WindowRect.Top);
      T.PlaceWindow;   // nothing left that reads the freed form
      T.Hide;
    finally
      EndPoison;
    end;
  finally
    S.Free;
    T.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAToastOwnedByItsHostGoesDownWithItNotToTheScreen;
var
  H: THostStub;
  T, S: THostedNote;
begin
  // The usual arrangement: the toast is a component ON its host form. Freeing the form frees
  // the toast; it must not first be sent to the screen's corner for the moment in between.
  H := NewHostA;
  T := THostedNote.Create(H);
  T.Controller := FCtl;
  T.WorkArea := Rect(CWorkL, CWorkT, CWorkR, CWorkB);
  T.Title := 'saved';
  T.HostForm := H;
  S := NewHosted(FCtl, nil);
  try
    T.ShowWindowless;
    S.ShowWindowless;
    AssertEquals('setup: in the host', CHostAT + Px(16), T.WindowRect.Top);
    GDyingScreenAsks := 0;
    BeginPoison;
    try
      FreeAndNil(H);   // takes T with it
    finally
      EndPoison;
    end;
    AssertEquals('a toast going down with its form is not placed on the screen on the way',
      0, GDyingScreenAsks);
    AssertEquals('and the screen toast is where it was', CWorkT + Px(16), S.WindowRect.Top);
  finally
    S.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestOnGetHostAreaTrimsTheArea;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    // A title bar across the top, a status bar across the bottom, uneven sides.
    FTrim := Rect(11, 32, 7, 22);
    N.OnGetHostArea := @HandleHostArea;
    AssertEquals('top edge below what the host took off', CHostAT + 32 + 16, N.SlotRect(96).Top);
    AssertEquals('right edge inside it', CHostAL + CHostAW - 7 - 16, N.SlotRect(96).Right);
    N.Position := npBottomLeft;
    AssertEquals('bottom edge above it', CHostAT + CHostAH - 22 - 16, N.SlotRect(96).Bottom);
    AssertEquals('left edge inside it', CHostAL + 11 + 16, N.SlotRect(96).Left);
    AssertTrue('the handler was asked', FAreaAsks > 0);
    N.OnGetHostArea := nil;
    AssertEquals('no handler: the whole client area', CHostAT + CHostAH - 16, N.SlotRect(96).Bottom);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestOnGetHostAreaIsNotAskedWithoutAUsableWindow;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, nil);
  try
    N.OnGetHostArea := @HandleHostArea;
    N.SlotRect(96);
    AssertEquals('no host: nothing to ask about', 0, FAreaAsks);
    N.HostForm := H;
    H.SimVisible := False;
    N.SlotRect(96);
    AssertEquals('a host that is not on screen has no area to trim', 0, FAreaAsks);
    H.SimVisible := True;
    H.SimMinimized := True;
    N.SlotRect(96);
    AssertEquals('nor has a minimised one', 0, FAreaAsks);
    H.SimMinimized := False;
    N.SlotRect(96);
    AssertTrue('on screen: asked', FAreaAsks > 0);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestAnAreaTrimmedBelowTheCardFallsBack;
var
  H: THostStub;
  N: THostedNote;
begin
  H := NewHostA;
  N := NewHosted(FCtl, H);
  try
    N.OnGetHostArea := @HandleHostArea;
    FTrim := Rect(CHostAW - 340, 0, 0, 0);
    AssertEquals('what is left is exactly the card''s width: still the host',
      CHostAL + CHostAW - 340, N.SlotRect(96).Left);
    FTrim := Rect(CHostAW - 339, 0, 0, 0);
    AssertEquals('one px less: the screen', CWorkR - 16, N.SlotRect(96).Right);
  finally
    N.Free;
    H.Free;
  end;
end;

procedure TTyNotificationHostTest.TestHostFormSurvivesTheFormFile;
var
  Src, Dst: TForm;
  N: TTyNotification;
  MS: TMemoryStream;
  SS: TStringStream;
  Back: TComponent;
begin
  // The usual arrangement: the toast sits on the form it is shown in.
  Src := TForm.CreateNew(nil);
  Dst := TForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostRoot';   // as in the designer: a reference to a nameless form is not written
    N := TTyNotification.Create(Src);
    N.Name := 'Toast';
    N.HostForm := Src;
    MS.WriteComponent(Src);
    MS.Position := 0;
    SS := TStringStream.Create('');
    try
      ObjectBinaryToText(MS, SS);
      AssertTrue('written as the form file''s reference to its own form: ' + SS.DataString,
        Pos('HostForm = Owner', SS.DataString) > 0);
    finally
      SS.Free;
    end;
    MS.Position := 0;
    MS.ReadComponent(Dst);
    Back := Dst.FindComponent('Toast');
    AssertNotNull('the toast came back', Back);
    AssertSame('hosted by the form it was read into', Dst, (Back as TTyNotification).HostForm);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ ========================== TTyNotificationHostWindowTest ========================== }

procedure TTyNotificationHostWindowTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ThemeCss);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 640, 480);   // off screen, but really shown
  FForm.Show;
  Pump;
end;

procedure TTyNotificationHostWindowTest.TearDown;
begin
  FreeAndNil(FForm);
  Pump;
  FCtl.Free;
end;

procedure TTyNotificationHostWindowTest.Pump;
begin
  // Twice: LCL reports a form's bounds change through a queued call, and what that call does
  // (moving the toast's window) is itself delivered as messages.
  Forms.Application.ProcessMessages;
  Forms.Application.ProcessMessages;
end;

function TTyNotificationHostWindowTest.ClientOnScreen: TRect;
var
  O: TPoint;
begin
  O := FForm.ClientOrigin;
  Result := Bounds(O.X, O.Y, FForm.ClientWidth, FForm.ClientHeight);
end;

function NewWindowed(ACtl: TTyStyleController; AHost: TCustomForm): THostedNote;
begin
  Result := NewHosted(ACtl, AHost);
  Result.WorkArea := Rect(COffL, COffT, COffR, COffB);
  Result.Duration := 0;   // nothing here waits, so nothing may time out under it
end;

procedure TTyNotificationHostWindowTest.TestAToastOpensInItsHostsCorner;
var
  N: THostedNote;
  CA: TRect;
begin
  N := NewWindowed(FCtl, FForm);
  try
    N.Show;
    Pump;
    CA := ClientOnScreen;
    AssertTrue('setup: the client area is not the window''s outer rect (it has a caption)',
      CA.Top > FForm.Top);
    AssertTrue('the toast is on screen', N.WindowShown);
    AssertEquals('one margin inside the client area''s right edge', CA.Right - Px(16),
      N.WindowRect.Right);
    AssertEquals('one margin below its top', CA.Top + Px(16), N.WindowRect.Top);
    N.Position := npBottomLeft;
    Pump;
    AssertEquals('one margin inside its left edge', CA.Left + Px(16), N.WindowRect.Left);
    AssertEquals('one margin above its bottom', CA.Bottom - Px(16), N.WindowRect.Bottom);
    N.Hide;
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostWindowTest.TestAHostsScrollBarsAreNotPartOfItsArea;
var
  N: THostedNote;
  CA: TRect;
begin
  // An LCL form's Width and Height ARE its client size until it shows scroll bars; with them
  // the client area is what is left inside the bars, and that is where the corner is.
  FForm.HorzScrollBar.Range := 3000;
  FForm.VertScrollBar.Range := 3000;
  Pump;
  AssertTrue(Format('setup: both bars take room (client %dx%d of %dx%d)',
    [FForm.ClientWidth, FForm.ClientHeight, FForm.Width, FForm.Height]),
    (FForm.ClientWidth < FForm.Width) and (FForm.ClientHeight < FForm.Height));
  N := NewWindowed(FCtl, FForm);
  try
    N.Position := npBottomRight;
    N.Show;
    Pump;
    CA := ClientOnScreen;
    AssertEquals('one margin inside the vertical bar', CA.Right - Px(16), N.WindowRect.Right);
    AssertEquals('one margin above the horizontal bar', CA.Bottom - Px(16), N.WindowRect.Bottom);
    N.Hide;
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostWindowTest.TestAToastShownBeforeItsHostJoinsItWhenTheHostAppears;
var
  Late: TForm;
  N: THostedNote;
  O: TPoint;
begin
  // A toast raised from the host's OnCreate: the form has no window yet.
  Late := TForm.CreateNew(nil);
  N := NewWindowed(FCtl, Late);
  try
    Late.SetBounds(-3000, -4000, 500, 400);
    N.Show;
    Pump;
    AssertEquals('setup: no window to stand in yet, so the screen''s corner', COffR - Px(16),
      N.WindowRect.Right);
    // LCL makes the window when auto-sizing is let go, after Visible is already True -- and
    // it is in that gap that it reports the visible change.
    Late.DisableAutoSizing;
    try
      Late.Visible := True;
      AssertFalse('setup: Visible, and its window not made yet', Late.HandleAllocated);
      AssertEquals('Visible is not yet on screen: still the screen''s corner', COffR - Px(16),
        N.SlotRect(Screen.PixelsPerInch).Right);
    finally
      Late.EnableAutoSizing;
    end;
    Pump;
    O := Late.ClientOrigin;
    AssertEquals('the host appeared: the toast is in it', O.X + Late.ClientWidth - Px(16),
      N.WindowRect.Right);
    AssertEquals('in its corner', O.Y + Px(16), N.WindowRect.Top);
    N.Hide;
  finally
    N.Free;
    Late.Free;
  end;
end;

procedure TTyNotificationHostWindowTest.TestTheToastFollowsItsHostWhenItMovesAndResizes;
var
  N: THostedNote;
  Was, CA: TRect;
begin
  N := NewWindowed(FCtl, FForm);
  try
    N.Show;
    Pump;
    Was := ClientOnScreen;
    FForm.SetBounds(-3600, -3900, 700, 520);
    Pump;
    CA := ClientOnScreen;
    AssertTrue('setup: the corner really moved on both axes',
      (CA.Right <> Was.Right) and (CA.Top <> Was.Top));
    AssertEquals('the toast went with the right edge', CA.Right - Px(16), N.WindowRect.Right);
    AssertEquals('and with the top', CA.Top + Px(16), N.WindowRect.Top);
    N.Hide;
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostWindowTest.TestAHiddenHostSendsItsToastToTheScreenAndTakesItBack;
var
  N: THostedNote;
  CA: TRect;
begin
  N := NewWindowed(FCtl, FForm);
  try
    N.Show;
    Pump;
    FForm.Hide;
    Pump;
    AssertEquals('host hidden: the screen''s corner', COffR - Px(16), N.WindowRect.Right);
    AssertEquals('of the work area', COffT + Px(16), N.WindowRect.Top);
    FForm.Show;
    Pump;
    CA := ClientOnScreen;
    AssertEquals('host shown again: back in it', CA.Right - Px(16), N.WindowRect.Right);
    AssertEquals('in its corner', CA.Top + Px(16), N.WindowRect.Top);
    N.Hide;
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostWindowTest.TestAToastShownWhileItsHostIsMinimisedGoesToTheScreen;
var
  N: THostedNote;
  CA: TRect;
begin
  N := NewWindowed(FCtl, FForm);
  try
    FForm.WindowState := wsMinimized;
    Pump;
    N.Show;
    Pump;
    AssertEquals('shown while its host is an icon: the screen''s corner', COffR - Px(16),
      N.WindowRect.Right);
    AssertEquals('of the work area', COffT + Px(16), N.WindowRect.Top);
    // LCL reports neither the minimise nor the restore to a form's change handlers, so the
    // toast goes back at the host's next move or resize (or the toast's own next Show).
    FForm.WindowState := wsNormal;
    Pump;
    FForm.SetBounds(-3600, -3900, 700, 520);
    Pump;
    CA := ClientOnScreen;
    AssertEquals('restored and moved: in the host', CA.Right - Px(16), N.WindowRect.Right);
    AssertEquals('in its corner', CA.Top + Px(16), N.WindowRect.Top);
    N.Hide;
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostWindowTest.HandleHostArea(Sender: TObject; var AArea: TRect);
begin
  Inc(FAreaAsks);
end;

procedure TTyNotificationHostWindowTest.TestOnGetHostAreaIsNotAskedOfAMinimisedWindow;
var
  N: THostedNote;
begin
  // Where the toast lands cannot tell whether the window was read as minimised: on Windows an
  // icon's client area is empty, so it is too small for the card either way. Whether the host
  // is asked for its area can.
  N := NewWindowed(FCtl, FForm);
  try
    N.OnGetHostArea := @HandleHostArea;
    FAreaAsks := 0;
    N.SlotRect(Screen.PixelsPerInch);
    AssertTrue('setup: a window on screen is asked', FAreaAsks > 0);
    FForm.WindowState := wsMinimized;
    Pump;
    FAreaAsks := 0;
    N.SlotRect(Screen.PixelsPerInch);
    AssertEquals('an icon has no area to narrow', 0, FAreaAsks);
  finally
    N.Free;
  end;
end;

procedure TTyNotificationHostWindowTest.TestFreeingTheHostSendsItsToastsToTheScreen;
var
  N1, N2: THostedNote;
begin
  // Two toasts up in a real form, neither owned by it, and the form freed under them: each
  // hears of it in turn, and the one told first re-stacks the other while that one still
  // names the dying form.
  N1 := NewWindowed(FCtl, FForm);
  N2 := NewWindowed(FCtl, FForm);
  try
    N1.Show;
    N2.Show;
    Pump;
    AssertEquals('setup: both in the host', ClientOnScreen.Right - Px(16), N2.WindowRect.Right);
    BeginPoison;
    try
      FreeAndNil(FForm);
      Pump;
      AssertNull('the first let go of it', N1.HostForm);
      AssertNull('and the second', N2.HostForm);
      AssertEquals('the first is in the screen''s corner', COffT + Px(16), N1.WindowRect.Top);
      AssertEquals('of the work area', COffR - Px(16), N1.WindowRect.Right);
      AssertEquals('the second one gap below it', N1.WindowRect.Bottom + Px(8), N2.WindowRect.Top);
    finally
      EndPoison;
    end;
    N1.Hide;
    N2.Hide;
  finally
    N2.Free;
    N1.Free;
  end;
end;

initialization
  RegisterClass(TTyNotification);
  RegisterTest(TTyNotificationRulesTest);
  RegisterTest(TTyNotificationComponentTest);
  RegisterTest(TTyNotificationHostTest);
  RegisterTest(TTyNotificationHostWindowTest);
end.
