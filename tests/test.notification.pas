unit test.notification;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
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

initialization
  RegisterTest(TTyNotificationRulesTest);
  RegisterTest(TTyNotificationComponentTest);
end.
