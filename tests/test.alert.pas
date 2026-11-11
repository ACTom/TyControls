unit test.alert;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, TypInfo, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.StyleModel,
  tyControls.BuiltinThemes, tyControls.Alert;

type
  { Pure-rules tests: TyAlertVariant / TyAlertGlyph / TyAlertLayout / TyAlertPreferredHeight
    take only integers and enums, so they run with no window handle and no control at all. }
  TTyAlertLayoutTest = class(TTestCase)
  published
    procedure TestTypeMapsToVariantName;
    procedure TestTypeMapsToGlyph;
    procedure TestTextColumnSpansPaddedBand;
    procedure TestIconSlotHugsLeftOfBand;
    procedure TestNoIconSlotWhenHidden;
    procedure TestIconGapSeparatesIconAndText;
    procedure TestCloseSlotHugsRightOfBand;
    procedure TestNoCloseSlotWhenNotClosable;
    procedure TestCloseGapSeparatesTextAndSlot;
    procedure TestSlotsCentreOnMessageLine;
    procedure TestNoDescriptionRectWhenAbsent;
    procedure TestDescriptionSitsAGapBelowMessage;
    procedure TestTwoLineBlockCentredInPaddedBand;
    procedure TestNarrowBannerKeepsCloseDropsIconAndText;
    procedure TestSlotTallerThanBannerIsClamped;
    procedure TestPaddingEatsWholeBanner;
    procedure TestZeroSizeEmpty;
    procedure TestPreferredHeightRoundTripsOneLine;
    procedure TestPreferredHeightRoundTripsTwoLine;
    procedure TestPreferredHeightClearsIconSlot;
    procedure TestPreferredHeightClearsCloseSlot;
  end;

  { Headless control behaviour: typeKey, defaults, the type->variant wiring, theme-driven
    geometry, the close gesture (and its interaction with the banner's own OnClick),
    AutoSize, and graceful degradation when the theme leaves a key undefined. }
  TTyAlertControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FClosed: Integer;      // OnClose fire count
    FClicked: Integer;     // OnClick fire count
    FAllowClose: Boolean;  // what the OnClose handler answers
    procedure HandleClose(Sender: TObject; var AllowClose: Boolean);
    procedure HandleClick(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestStyleVariantFollowsAlertType;
    procedure TestUserStyleClassLayersOnTopOfVariant;
    procedure TestVariantPaintsItsOwnBackground;
    procedure TestCloseRectEmptyWhenNotClosable;
    procedure TestCloseRectFollowsThemePadding;
    procedure TestIconRectEmptyWhenShowIconFalse;
    procedure TestIconSizeMetricRetunesSlot;
    procedure TestClickCloseFiresOnCloseAndHides;
    procedure TestCloseWorksUnderActiveStatePadding;
    procedure TestBackgroundlessAlertIsInert;
    procedure TestCloseVetoKeepsAlertVisible;
    procedure TestClickCloseDoesNotFireOnClick;
    procedure TestClickBodyFiresOnClickNotOnClose;
    procedure TestDragOffCloseCancelsGesture;
    procedure TestPreferredHeightGrowsForDescription;
    procedure TestPreferredWidthIsUnconstrained;
    procedure TestBarRendersThemeBackground;
    procedure TestIconRendersThemeInk;
    procedure TestCloseGlyphRendersThemeInk;
    procedure TestUndefinedBarKeyDrawsNothing;
    procedure TestUndefinedCloseKeyFallsBackToBarInk;
  end;

  { The action row in the pure geometry: where the actions sit, what they push aside, and
    what gives way when the banner is too narrow or too short for them. }
  TTyAlertActionLayoutTest = class(TTestCase)
  published
    procedure TestNoActionsIsTheOldLayout;
    procedure TestOneActionHugsBandRight;
    procedure TestActionsSitInOrderBeforeTheClose;
    procedure TestTextStopsAnActionGapBeforeTheRow;
    procedure TestOneActionFewerGivesItsWidthBack;
    procedure TestActionsCentreOnMessageLine;
    procedure TestActionTallerThanBannerIsClamped;
    procedure TestNarrowBannerServesCloseThenActionsThenIcon;
    procedure TestActionsThatDoNotFitAreCutFromTheEnd;
    procedure TestNegativeActionInputsAreClamped;
    procedure TestPreferredHeightWithoutActionsIsTheOldOne;
    procedure TestPreferredHeightUnchangedWhenTheActionFits;
    procedure TestPreferredHeightClearsATallAction;
    procedure TestPreferredHeightClearsATallActionUnderUnevenPadding;
    procedure TestPreferredHeightClearsATallActionBesideTwoLines;
    procedure TestPreferredHeightIsTheSmallestThatClears;
  end;

  { The Actions collection on the control: geometry from the theme, hit testing, the click
    gesture against the banner's own OnClick and the close glyph, streaming, the four looks
    of an action, hints and the hooks a subclass has. }
  TTyAlertActionControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FClosed: Integer;
    FClicked: Integer;
    FActed: Integer;                 // OnAction fire count
    FLastAction: TTyAlertAction;     // what the last OnAction named
    procedure HandleClose(Sender: TObject; var AllowClose: Boolean);
    procedure HandleClick(Sender: TObject);
    procedure HandleAction(Sender: TObject; AAction: TTyAlertAction);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestActionDefaults;
    procedure TestActionRectsRunInOrderToTheBandEdge;
    procedure TestActionRectsStopBeforeTheClose;
    procedure TestActionGapTokenSpacesTheRow;
    procedure TestActionGapReadsStyleOverride;
    procedure TestBaseThemeAgreesWithTheConstants;
    procedure TestActionWidthFollowsItsCaption;
    procedure TestActionPaddingComesFromItsStyle;
    procedure TestActionWithoutPaddingTakesTheBuiltInOne;
    procedure TestHiddenActionGivesItsWidthBack;
    procedure TestActionRectOutOfRangeIsEmpty;
    procedure TestRightToLeftMirrorsTheRow;
    procedure TestActionAtFollowsTheRects;
    procedure TestActionAtSeesDisabledButNotHidden;
    procedure TestClickFiresOnActionOnly;
    procedure TestClickWithCloseFiresOnActionNotOnClose;
    procedure TestCloseBesideActionsStillCloses;
    procedure TestDownOnOneUpOnAnotherFiresNothing;
    procedure TestDownOnActionUpOnBodyFiresNothing;
    procedure TestDownOnBodyUpOnActionIsABannerClick;
    procedure TestDisabledActionFiresNothing;
    procedure TestDisabledBannerFiresNothing;
    procedure TestRightButtonFiresNothing;
    procedure TestRightButtonDuringAPressDoesNotEndIt;
    procedure TestRightButtonDoesNotPressAnAction;
    procedure TestActionWorksUnderActiveStatePadding;
    procedure TestBackgroundlessAlertHasNoLiveActions;
    procedure TestActionRemovedDuringThePressFiresNothing;
    procedure TestActionsStreamRoundTrip;
    procedure TestAssignCopiesTheActions;
    procedure TestActionInkComesFromItsKey;
    procedure TestActionWithoutColourTakesTheBarInk;
    procedure TestActionWithoutFontTakesTheBarFont;
    procedure TestActionWithoutWeightTakesTheBarWeight;
    procedure TestVariantReachesTheAction;
    procedure TestBannerColourOverrideLeavesDisabledInkAlone;
    procedure TestActionBorderIsDrawn;
    procedure TestCaptionKeepsClearOfTheActionPadding;
    procedure TestHoverPaddingDoesNotMoveTheCaption;
    procedure TestHoverLightsOnlyTheActionUnderThePointer;
    procedure TestLeavingClearsTheHover;
    procedure TestPressedLookFollowsThePointer;
    procedure TestPressOnActionDoesNotPressTheBar;
    procedure TestPressElsewhereLightsNoAction;
    procedure TestPointerOverActionsAsksForARepaint;
    procedure TestChangingAnActionAsksForARepaint;
    procedure TestDisabledActionTakesDisabledInkAndNoHover;
    procedure TestDisabledBannerDisablesEveryAction;
    procedure TestPreferredHeightUnchangedByAFittingAction;
    procedure TestPreferredHeightGrowsForATallAction;
    procedure TestHintComesFromTheActionUnderThePointer;
    procedure TestSubclassCanTakeOverTheAction;
    procedure TestSubclassCanMeasureAndDrawTheAction;
    procedure TestDrawActionIsHandedWhatTheActionInherits;
    procedure TestActionWithoutRoomIsNotDrawn;
    procedure TestEveryBuiltinThemeStylesTheAction;
  end;

implementation

const
  { The one CSS the control tests share: a plain bar with room for everything. Padding
    8/12 and a 12px font are the AntD-ish shape the geometry tests assume in miniature.
    NOTE every test that needs a themed value states it HERE (or in its own CSS): a user
    rule for a typeKey suppresses the whole built-in base layer, so nothing bleeds in. }
  cBarCss = 'TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 12px; }';

type
  { Reaches the protected paint + mouse seams. The mouse helpers drive the handlers in the
    SAME order LCL does (TControl.WMLButtonUp runs Click and only then DoMouseUp), which is
    exactly the ordering TTyAlert.Click relies on to swallow a close gesture. }
  TAlertAccess = class(TTyAlert)
  public
    Invalidations: Integer;   // how many repaints the control has asked for
    procedure Invalidate; override;
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressReleaseAt(X, Y: Integer);
    procedure PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
    { The two halves of a left click, and the pointer moving with no button held. Up
      keeps the LCL order: Click first, and only for a release inside the control. }
    procedure Down(X, Y: Integer);
    procedure Up(X, Y: Integer);
    procedure MoveTo(X, Y: Integer);
    procedure Leave;
    procedure RightPressReleaseAt(X, Y: Integer);
    { A whole left click on the middle of an action. }
    procedure ClickAction(AIndex: Integer);
    function ActionCentre(AIndex: Integer): TPoint;
    { The geometry the paint and the hit test share, for the current size. }
    function Lay: TTyAlertLayout;
    { What LCL asks a control before it shows a hint at (X, Y): the text, and the rect
      the pointer has to leave before it asks again. }
    function HintAt(X, Y: Integer; out ARect: TRect): string;
    { The size AutoSize would fit the banner to. Called directly rather than through
      AutoSize itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent form
      has no handle (the headless runner never realises one), so driving AutoSize here
      would assert on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

procedure TAlertAccess.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

function TAlertAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TAlertAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TAlertAccess.PressReleaseAt(X, Y: Integer);
begin
  PressAtReleaseAt(X, Y, X, Y);
end;

procedure TAlertAccess.PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
begin
  MouseDown(mbLeft, [], ADownX, ADownY);
  // LCL synthesises Click BEFORE MouseUp, and only when the release is inside the client
  // rect (TControl.WMLButtonUp) — mirror both rules here.
  if (AUpX >= 0) and (AUpY >= 0) and (AUpX < Width) and (AUpY < Height) then
    Click;
  MouseUp(mbLeft, [], AUpX, AUpY);
end;

procedure TAlertAccess.Down(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TAlertAccess.Up(X, Y: Integer);
begin
  if (X >= 0) and (Y >= 0) and (X < Width) and (Y < Height) then
    Click;
  MouseUp(mbLeft, [], X, Y);
end;

procedure TAlertAccess.MoveTo(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TAlertAccess.Leave;
begin
  MouseLeave;
end;

procedure TAlertAccess.RightPressReleaseAt(X, Y: Integer);
begin
  // LCL makes no Click out of the right button.
  MouseDown(mbRight, [], X, Y);
  MouseUp(mbRight, [], X, Y);
end;

function TAlertAccess.ActionCentre(AIndex: Integer): TPoint;
var
  R: TRect;
begin
  R := ActionRect(AIndex);
  Result := Point((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

procedure TAlertAccess.ClickAction(AIndex: Integer);
var
  p: TPoint;
begin
  p := ActionCentre(AIndex);
  PressReleaseAt(p.X, p.Y);
end;

function TAlertAccess.Lay: TTyAlertLayout;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch);
end;

function TAlertAccess.HintAt(X, Y: Integer; out ARect: TRect): string;
var
  info: THintInfo;
begin
  info := Default(THintInfo);
  info.HintControl := Self;
  info.CursorPos := Point(X, Y);
  info.CursorRect := ClientRect;
  info.HintStr := Hint;
  Perform(CM_HINTSHOW, 0, LParam(PtrUInt(@info)));
  ARect := info.CursorRect;
  Result := info.HintStr;
end;

procedure TAlertAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

{ Render AAlert into a fresh WxH bitmap over a white backdrop and hand back a BGRA
  re-read of it. The caller frees the result. Every pixel probe below goes through this
  so they all share one backdrop and one AA bias. }
function RenderToBGRA(AAlert: TAlertAccess; AWidth, AHeight: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AWidth, AHeight);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, AWidth, AHeight);
    AAlert.RenderTo(Bmp.Canvas, Rect(0, 0, AWidth, AHeight), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ Is there a pixel inside ARect that is convincingly GREEN (#10B981-ish: green well ahead
  of both red and blue)? The probe every "…renders the themed ink" test uses — it asserts
  STRUCTURE (the themed ink reached these pixels), never a glyph's exact extents, which
  the headless runner's fallback font would make meaningless. }
function HasGreenInk(R: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  Px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= R.Width) or (y >= R.Height) then Continue;
      Px := R.GetPixel(x, y);
      if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
        Exit(True);
    end;
end;

{ TTyAlertLayoutTest }

procedure TTyAlertLayoutTest.TestTypeMapsToVariantName;
begin
  // These four strings ARE the theme's contract (TyAlert.info / .success / …): the theme
  // pass writes rules against them, so a rename here is a breaking change.
  AssertEquals('info', TyAlertVariant(atInfo));
  AssertEquals('success', TyAlertVariant(atSuccess));
  AssertEquals('warning', TyAlertVariant(atWarning));
  AssertEquals('error', TyAlertVariant(atError));
end;

procedure TTyAlertLayoutTest.TestTypeMapsToGlyph;
begin
  // The other half of what AlertType is FOR: it picks the mark the control draws.
  AssertTrue('info -> tgInfo', TyAlertGlyph(atInfo) = tgInfo);
  AssertTrue('success -> tgSuccess', TyAlertGlyph(atSuccess) = tgSuccess);
  AssertTrue('warning -> tgWarning', TyAlertGlyph(atWarning) = tgWarning);
  AssertTrue('error -> tgError', TyAlertGlyph(atError) = tgError);
end;

procedure TTyAlertLayoutTest.TestTextColumnSpansPaddedBand;
var
  L: TTyAlertLayout;
begin
  // 300 wide, pad 12/12, no icon, no x -> the text column is the banner inset by padding.
  L := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('text starts at left padding', 12, L.MessageRect.Left);
  AssertEquals('text ends at right padding', 288, L.MessageRect.Right);
end;

procedure TTyAlertLayoutTest.TestIconSlotHugsLeftOfBand;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, True, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('slot left = band left', 12, L.IconRect.Left);
  AssertEquals('slot is the given size', 16, L.IconRect.Right - L.IconRect.Left);
end;

procedure TTyAlertLayoutTest.TestNoIconSlotWhenHidden;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no icon slot', 0, L.IconRect.Right - L.IconRect.Left);
  // …and the text reclaims the space the slot would have taken.
  AssertEquals('text starts at the band edge', 12, L.MessageRect.Left);
end;

procedure TTyAlertLayoutTest.TestIconGapSeparatesIconAndText;
var
  L: TTyAlertLayout;
begin
  // Icon 16 at x=12 ends at 28; gap 8 -> the text starts at 36.
  L := TyAlertLayout(300, 40, True, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('icon ends', 28, L.IconRect.Right);
  AssertEquals('text starts a gap after the icon', 36, L.MessageRect.Left);
end;

procedure TTyAlertLayoutTest.TestCloseSlotHugsRightOfBand;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, False, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('slot right = band right', 288, L.CloseRect.Right);
  AssertEquals('slot left = band right - size', 274, L.CloseRect.Left);
end;

procedure TTyAlertLayoutTest.TestNoCloseSlotWhenNotClosable;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no close slot', 0, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('text reaches the band edge', 288, L.MessageRect.Right);
end;

procedure TTyAlertLayoutTest.TestCloseGapSeparatesTextAndSlot;
var
  L: TTyAlertLayout;
begin
  // Slot left 274; close gap 8 -> the text stops at 266.
  L := TyAlertLayout(300, 40, False, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('text stops a gap before the slot', 266, L.MessageRect.Right);
end;

procedure TTyAlertLayoutTest.TestSlotsCentreOnMessageLine;
var
  L: TTyAlertLayout;
begin
  // One line: H=40, pad 8/8 -> avail 24, block 16 -> blockT = 8 + (24-16) div 2 = 12,
  // so the message line spans 12..28 and its centre is 20. A 16px icon slot centres on
  // 20 -> 12..28; a 14px close slot -> 13..27.
  L := TyAlertLayout(300, 40, True, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message line top', 12, L.MessageRect.Top);
  AssertEquals('message line bottom', 28, L.MessageRect.Bottom);
  AssertEquals('icon centred on the message line', 12, L.IconRect.Top);
  AssertEquals('icon bottom', 28, L.IconRect.Bottom);
  AssertEquals('x centred on the message line', 13, L.CloseRect.Top);
  AssertEquals('x bottom', 27, L.CloseRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestNoDescriptionRectWhenAbsent;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, True, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no description band', 0, L.DescriptionRect.Right - L.DescriptionRect.Left);
end;

procedure TTyAlertLayoutTest.TestDescriptionSitsAGapBelowMessage;
var
  L: TTyAlertLayout;
begin
  // Two lines of 16 with a 2px gap = a 34px block. H=60, pad 8/8 -> avail 44,
  // blockT = 8 + (44-34) div 2 = 13. Message 13..29, gap 2, description 31..47.
  L := TyAlertLayout(300, 60, True, True, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message line', 13, L.MessageRect.Top);
  AssertEquals('message ends', 29, L.MessageRect.Bottom);
  AssertEquals('description starts a text-gap below', 31, L.DescriptionRect.Top);
  AssertEquals('description ends', 47, L.DescriptionRect.Bottom);
  // Both lines share the one text column.
  AssertEquals('same left edge', L.MessageRect.Left, L.DescriptionRect.Left);
  AssertEquals('same right edge', L.MessageRect.Right, L.DescriptionRect.Right);
end;

procedure TTyAlertLayoutTest.TestTwoLineBlockCentredInPaddedBand;
var
  L: TTyAlertLayout;
begin
  // The two-line form is where the "slots centre on the MESSAGE line" rule earns its
  // keep: the icon must sit beside the HEADLINE, not float between the two lines.
  L := TyAlertLayout(300, 60, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('icon tracks the message line, not the block centre', L.MessageRect.Top,
    L.IconRect.Top);
  AssertTrue('icon sits above the description', L.IconRect.Bottom <= L.DescriptionRect.Top);
  // The x centres on the same line (14 tall vs the line's 16 -> inset by 1).
  AssertEquals('x centred on the message line', 14, L.CloseRect.Top);
end;

procedure TTyAlertLayoutTest.TestNarrowBannerKeepsCloseDropsIconAndText;
var
  L: TTyAlertLayout;
begin
  // The priority chain, close > icon > text, at the two widths that exercise it.
  // W=54: band 12..42. The x (14) is served first and keeps its FULL slot at 28..42;
  // the close gap then leaves the text column at 12..20, so the icon is squeezed into
  // those 8px and the text collapses rather than showing a sliver.
  L := TyAlertLayout(54, 40, True, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('the x keeps its full slot', 14, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('the x still hugs the band right', 42, L.CloseRect.Right);
  AssertEquals('the icon starts at the band edge', 12, L.IconRect.Left);
  AssertEquals('the icon takes only what is left', 20, L.IconRect.Right);
  AssertEquals('text dropped', 0, L.MessageRect.Right - L.MessageRect.Left);

  // W=40: band 12..28 — the x alone fills it, so even the icon goes. The x survives
  // whatever happens: it is the banner's only affordance.
  L := TyAlertLayout(40, 40, True, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('the x still keeps its full slot', 14, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('icon dropped too', 0, L.IconRect.Right - L.IconRect.Left);
  AssertEquals('text still dropped', 0, L.MessageRect.Right - L.MessageRect.Left);
end;

procedure TTyAlertLayoutTest.TestSlotTallerThanBannerIsClamped;
var
  L: TTyAlertLayout;
begin
  // A 10px banner can't hold a 16px icon slot or a 14px x: squash them into the height,
  // never past it. The message line centres on 8, so the 16px icon wants -8..8 (floored
  // to 0) and the 14px x wants 1..15 (its bottom clamped) — neither escapes the banner.
  L := TyAlertLayout(300, 10, True, False, True, 12, 0, 12, 0, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('icon top floors at 0', 0, L.IconRect.Top);
  AssertEquals('icon bottom clamped to the height', 10, L.IconRect.Bottom);
  AssertEquals('x top', 1, L.CloseRect.Top);
  AssertEquals('x bottom clamped to the height', 10, L.CloseRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestPaddingEatsWholeBanner;
var
  L: TTyAlertLayout;
begin
  // Padding wider than the banner: nothing fits — every rect empty, never inverted.
  L := TyAlertLayout(20, 40, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no icon', 0, L.IconRect.Right - L.IconRect.Left);
  AssertEquals('no message', 0, L.MessageRect.Right - L.MessageRect.Left);
  AssertEquals('no description', 0, L.DescriptionRect.Right - L.DescriptionRect.Left);
  AssertEquals('no x', 0, L.CloseRect.Right - L.CloseRect.Left);
end;

procedure TTyAlertLayoutTest.TestZeroSizeEmpty;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(0, 40, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('zero width: no message', 0, L.MessageRect.Right - L.MessageRect.Left);
  AssertEquals('zero width: no x', 0, L.CloseRect.Right - L.CloseRect.Left);
  L := TyAlertLayout(300, 0, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('zero height: no message', 0, L.MessageRect.Right - L.MessageRect.Left);
  AssertEquals('zero height: no icon', 0, L.IconRect.Right - L.IconRect.Left);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightRoundTripsOneLine;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // The contract: a banner of TyAlertPreferredHeight lands the text block exactly on its
  // padding. pad 8 + line 16 + pad 8 = 32.
  h := TyAlertPreferredHeight(False, False, False, 8, 8, 16, 16, 2, 16, 14);
  AssertEquals('pad + line + pad', 32, h);
  L := TyAlertLayout(300, h, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message sits on the top padding', 8, L.MessageRect.Top);
  AssertEquals('and clears the bottom padding', h - 8, L.MessageRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightRoundTripsTwoLine;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // pad 8 + (16 + gap 2 + 16) + pad 8 = 50.
  h := TyAlertPreferredHeight(False, True, False, 8, 8, 16, 16, 2, 16, 14);
  AssertEquals('pad + line + gap + line + pad', 50, h);
  L := TyAlertLayout(300, h, False, True, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message sits on the top padding', 8, L.MessageRect.Top);
  AssertEquals('description clears the bottom padding', h - 8, L.DescriptionRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightClearsIconSlot;
var
  plain, withIcon: Integer;
begin
  // A tiny line with no padding is shorter than the 16px icon slot: showing the icon must
  // grow the banner to clear it, or TyAlertLayout squashes the glyph.
  plain := TyAlertPreferredHeight(False, False, False, 0, 0, 6, 6, 2, 16, 14);
  AssertEquals('a bare 6px line', 6, plain);
  withIcon := TyAlertPreferredHeight(True, False, False, 0, 0, 6, 6, 2, 16, 14);
  AssertEquals('grew to clear the icon slot', 16, withIcon);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightClearsCloseSlot;
var
  h: Integer;
begin
  h := TyAlertPreferredHeight(False, False, True, 0, 0, 6, 6, 2, 16, 14);
  AssertEquals('grew to clear the close slot', 14, h);
  // A banner already taller than both slots is not padded out to them.
  h := TyAlertPreferredHeight(True, False, True, 8, 8, 16, 16, 2, 16, 14);
  AssertEquals('no floor applied when the content is taller', 32, h);
end;

{ TTyAlertControlTest }

procedure TTyAlertControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FClosed := 0;
  FClicked := 0;
  FAllowClose := True;
end;

procedure TTyAlertControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyAlertControlTest.HandleClose(Sender: TObject; var AllowClose: Boolean);
begin
  Inc(FClosed);
  AllowClose := FAllowClose;
end;

procedure TTyAlertControlTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TTyAlertControlTest.TestTypeKey;
var
  A: TAlertAccess;
begin
  A := TAlertAccess.Create(FForm);
  A.Parent := FForm;
  try
    AssertEquals('TyAlert', A.StyleTypeKey);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestDefaults;
var
  A: TTyAlert;
begin
  A := TTyAlert.Create(FForm);
  try
    AssertTrue('type defaults to info', A.AlertType = atInfo);
    AssertEquals('no message', '', A.Message);
    AssertEquals('no description', '', A.Description);
    AssertFalse('one-line by default', A.HasDescription);
    AssertTrue('icon shown by default', A.ShowIcon);
    AssertFalse('not closable by default', A.Closable);
    AssertEquals('default width 320', 320, A.Width);
    AssertEquals('default height 40', 40, A.Height);
    AssertTrue('props published', IsPublishedProp(A, 'AlertType')
      and IsPublishedProp(A, 'Message') and IsPublishedProp(A, 'Description')
      and IsPublishedProp(A, 'ShowIcon') and IsPublishedProp(A, 'Closable'));
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestStyleVariantFollowsAlertType;
var
  A: TTyAlert;
begin
  A := TTyAlert.Create(FForm);
  try
    AssertEquals('info by default', 'info', A.StyleVariant);
    A.AlertType := atWarning;
    AssertEquals('the type owns the variant', 'warning', A.StyleVariant);
    A.AlertType := atError;
    AssertEquals('error', 'error', A.StyleVariant);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestUserStyleClassLayersOnTopOfVariant;
var
  A: TTyAlert;
begin
  // The documented interaction: the TYPE always contributes its variant token FIRST and a
  // user StyleClass is appended, so the semantic look can never be silently dropped while
  // an explicit class still layers over it per-property (the engine's ordinary cascade).
  A := TTyAlert.Create(FForm);
  try
    A.AlertType := atSuccess;
    A.StyleClass := 'compact';
    AssertEquals('type token first, user class after', 'success compact', A.StyleVariant);
    // Whitespace-only is not a token: it must not leave a trailing separator behind.
    A.StyleClass := '   ';
    AssertEquals('blank class adds nothing', 'success', A.StyleVariant);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestVariantPaintsItsOwnBackground;
var
  A: TAlertAccess;
  R: TBGRABitmap;
  Px: TBGRAPixel;
begin
  // Proof that AlertType really reaches the style resolve: the base rule is white and only
  // the .error variant is red, so a red bar can only have come from the type's token.
  FCtl.LoadThemeCss(cBarCss + 'TyAlert.error { background: #EF4444; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.AlertType := atError;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      // Well inside the bar, clear of the icon slot and of any text.
      Px := R.GetPixel(150, 4);
      AssertTrue('the error variant painted its own fill',
        (Px.red > 180) and (Px.green < 120) and (Px.blue < 120));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseRectEmptyWhenNotClosable;
var
  A: TTyAlert;
  R: TRect;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.SetBounds(0, 0, 300, 40);
    R := A.TyAlertCloseRect;
    AssertEquals('no slot while Closable=False', 0, R.Right - R.Left);
    // Turning it on materialises the slot with no other change.
    A.Closable := True;
    R := A.TyAlertCloseRect;
    AssertTrue('slot appears when Closable=True', R.Right > R.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseRectFollowsThemePadding;
var
  A: TTyAlert;
  R: TRect;
begin
  // The slot's right edge is driven by the THEME's right padding, not a literal.
  FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 20px; font-size: 12px; }');
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := A.TyAlertCloseRect;
    AssertEquals('slot right = width - themed right padding', 280, R.Right);
    AssertEquals('slot is the default 14px slot', TyAlertCloseSize, R.Right - R.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestIconRectEmptyWhenShowIconFalse;
var
  A: TTyAlert;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.SetBounds(0, 0, 300, 40);
    AssertTrue('icon slot present by default', A.TyAlertIconRect.Right > A.TyAlertIconRect.Left);
    A.ShowIcon := False;
    AssertEquals('no icon slot once hidden', 0,
      A.TyAlertIconRect.Right - A.TyAlertIconRect.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestIconSizeMetricRetunesSlot;
var
  A: TTyAlert;
  R: TRect;
begin
  // --alert-icon-size is a skin-tunable metric: a theme that sets it moves the geometry,
  // proving the slot size is not baked into the control.
  FCtl.LoadThemeCss(':root { --alert-icon-size: 24px; }' + cBarCss);
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.SetBounds(0, 0, 300, 40);
    R := A.TyAlertIconRect;
    AssertEquals('slot takes the themed size', 24, R.Right - R.Left);
    AssertEquals('and still hugs the padded band left', 12, R.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestClickCloseFiresOnCloseAndHides;
var
  A: TAlertAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    R := A.TyAlertCloseRect;
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired once', 1, FClosed);
    AssertFalse('default action hid the banner', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseVetoKeepsAlertVisible;
var
  A: TAlertAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    FAllowClose := False;   // the host wants to own the banner's fate
    R := A.TyAlertCloseRect;
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose still fired', 1, FClosed);
    AssertTrue('veto suppressed the default hide', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestClickCloseDoesNotFireOnClick;
var
  A: TAlertAccess;
  R: TRect;
begin
  // The whole point of the split gesture: "dismiss this notice" must not also read as
  // "the user clicked the notice" (a banner whose body opens a details pane otherwise
  // both dismisses AND navigates).
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    A.OnClick := @HandleClick;
    R := A.TyAlertCloseRect;
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired', 1, FClosed);
    AssertEquals('OnClick swallowed', 0, FClicked);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestClickBodyFiresOnClickNotOnClose;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    A.OnClick := @HandleClick;
    A.PressReleaseAt(120, 20);   // mid-bar, far from the slot (which starts near x=274)
    AssertEquals('OnClick fired', 1, FClicked);
    AssertEquals('OnClose did not', 0, FClosed);
    AssertTrue('banner still visible', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestDragOffCloseCancelsGesture;
var
  A: TAlertAccess;
  R: TRect;
begin
  // Press the x, drag onto the message, release: like any push button the gesture is
  // cancelled — no close, and no stray OnClick either (the press was never the bar's).
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    A.OnClick := @HandleClick;
    R := A.TyAlertCloseRect;
    A.PressAtReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2, 120, 20);
    AssertEquals('no close', 0, FClosed);
    AssertEquals('no click', 0, FClicked);
    AssertTrue('banner still visible', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestPreferredHeightGrowsForDescription;
var
  A: TAlertAccess;
  w, oneLine, twoLine: Integer;
begin
  // Setting a Description switches the banner to its two-line form, which must be taller
  // by exactly a text gap plus a line.
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'Disk almost full';
    A.PreferredSize(w, oneLine);
    A.Description := 'Free at least 2 GB to continue.';
    A.PreferredSize(w, twoLine);
    AssertTrue('the second line made the banner taller', twoLine > oneLine);
    // The exact growth: gap + one more line (both lines share the one TyAlert font, so
    // the extra line is the same height as the first).
    AssertEquals('grew by gap + a line', oneLine + TyAlertTextGap + (oneLine - 8 - 8),
      twoLine);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestPreferredWidthIsUnconstrained;
var
  A: TAlertAccess;
  w, h: Integer;
begin
  // AutoSize hugs the HEIGHT only. 0 is LCL's "no preferred width — keep the bounds you
  // were given", which is what lets a banner span its host via Align/Anchors.
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'a rather long headline that would want a very wide banner indeed';
    A.PreferredSize(w, h);
    AssertEquals('no preferred width', 0, w);
    AssertTrue('but a real preferred height', h > 0);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestBarRendersThemeBackground;
var
  A: TAlertAccess;
  R: TBGRABitmap;
  Px: TBGRAPixel;
begin
  // A strongly blue TyAlert fill: probe the bar and assert it is the themed fill — i.e.
  // the banner paints from the token, not from an LCL colour.
  FCtl.LoadThemeCss(
    'TyAlert { background: #3B82F6; color: #FFFFFF; border-radius: 4px; padding: 8px 12px; font-size: 12px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'heads up';
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      // Well inside the bar, clear of the rounded corners and of the glyphs.
      Px := R.GetPixel(150, 4);
      AssertTrue('bar painted in the themed fill', (Px.blue > 180) and (Px.red < 120));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestIconRendersThemeInk;
var
  A: TAlertAccess;
  R: TBGRABitmap;
begin
  // White bar, GREEN ink: any green pixel in the icon slot can only be the status glyph
  // drawn in the theme's colour. (Structure, not extents — see HasGreenInk.)
  FCtl.LoadThemeCss(
    'TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px; font-size: 12px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.AlertType := atWarning;
    A.Message := 'heads up';
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('status glyph drawn in the themed ink', HasGreenInk(R, A.TyAlertIconRect));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseGlyphRendersThemeInk;
var
  A: TAlertAccess;
  R: TBGRABitmap;
begin
  // White bar, white bar-ink, GREEN x: any green pixel in the slot can only be the
  // TyAlertClose colour — proving the x resolves from its OWN typeKey.
  FCtl.LoadThemeCss(
    'TyAlert { background: #FFFFFF; color: #FFFFFF; padding: 8px 12px; font-size: 12px; }' +
    'TyAlertClose { color: #10B981; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'heads up';
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('x drawn in the TyAlertClose ink', HasGreenInk(R, A.TyAlertCloseRect));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestUndefinedBarKeyDrawsNothing;
const
  // The ONLY difference between the two phases is the background declaration. Everything
  // that could draw green ink (the colour, the icon, the x) is identical in both.
  cInk = ' color: #10B981; padding: 8px 12px; font-size: 12px; }';
var
  A: TAlertAccess;
  R: TBGRABitmap;
  whole: TRect;
begin
  // Graceful degradation: a theme that touches TyAlert but gives it no `background` gets
  // NO banner rather than a hard-coded one. (A user rule for a typeKey suppresses the
  // whole built-in base layer, so this stays true once the theme pass ships a base
  // TyAlert rule — which is exactly why the rule here is present-but-backgroundless
  // rather than absent.)
  whole := Rect(0, 0, 300, 40);
  FCtl.LoadThemeCss('TyAlert {' + cInk);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.AlertType := atError;
    A.Message := 'heads up';
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertFalse('an unbacked TyAlert key paints nothing at all', HasGreenInk(R, whole));
    finally
      R.Free;
    end;
    // …and adding the background — the ONE thing that was missing — brings the very same
    // ink back. Without this half, a broken green probe would pass the assertion above.
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF;' + cInk);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('a backed key paints that same ink', HasGreenInk(R, whole));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestUndefinedCloseKeyFallsBackToBarInk;
var
  A: TAlertAccess;
  R: TBGRABitmap;
begin
  // Graceful degradation for the SECONDARY key: TyAlertClose exists but sets no colour
  // and no background, so the x inherits the BAR's ink and gets no chip — never a
  // hard-coded colour. (Again a present-but-silent rule, so the built-in base layer is
  // suppressed and the assertion survives the theme pass.)
  FCtl.LoadThemeCss(
    'TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px; font-size: 12px; }' +
    'TyAlertClose { border-radius: 3px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'heads up';
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('the x fell back to the bar''s own ink',
        HasGreenInk(R, A.TyAlertCloseRect));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): MouseDown ran `inherited` (which sets FPressed) BEFORE
  hit-testing the close x, so PtOnClose resolved the :active variant — whose padding moved the
  close rect off the painted (resting) x. A press squarely on the visible x then read as a body
  press and never closed. The hit-test must use the RESTING geometry. }
procedure TTyAlertControlTest.TestCloseWorksUnderActiveStatePadding;
var
  A: TAlertAccess;
  R: TRect;
begin
  // :active shifts the padding hard (12 -> 40). The x is PAINTED at rest; pressing it must close.
  FCtl.LoadThemeCss(cBarCss + 'TyAlert:active { background: #FFFFFF; padding: 8px 40px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm; A.Controller := FCtl; A.Font.PixelsPerInch := 96;
    A.Closable := True; A.SetBounds(0, 0, 300, 40); A.OnClose := @HandleClose;
    R := A.TyAlertCloseRect;   // the RESTING (painted) slot
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('a press on the visible x closes, despite :active padding', 1, FClosed);
  finally
    A.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): a background-less (theme-degraded) alert paints NOTHING
  but still swallowed clicks and could self-hide over the invisible x. Input must honour the
  paint's "no banner" decision. }
procedure TTyAlertControlTest.TestBackgroundlessAlertIsInert;
var
  A: TAlertAccess;
begin
  // Present-but-background-less (suppresses the base layer); Closable so an x would otherwise sit.
  FCtl.LoadThemeCss('TyAlert { color: #111111; padding: 8px 12px; font-size: 12px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm; A.Controller := FCtl; A.Font.PixelsPerInch := 96;
    A.Closable := True; A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose; A.OnClick := @HandleClick;
    A.PressReleaseAt(150, 20);   // body
    A.PressReleaseAt(285, 20);   // where the invisible x's slot would be
    AssertEquals('an invisible banner fires no OnClick', 0, FClicked);
    AssertEquals('...and no OnClose', 0, FClosed);
    AssertTrue('...and did not hide itself', A.Visible);
  finally
    A.Free;
  end;
end;

{ ----- the action row: pure geometry ------------------------------------------------------ }

function RectW(const R: TRect): Integer;
begin
  Result := R.Right - R.Left;
end;

function RectH(const R: TRect): Integer;
begin
  Result := R.Bottom - R.Top;
end;

function SameRect(const A, B: TRect): Boolean;
begin
  Result := (A.Left = B.Left) and (A.Top = B.Top) and (A.Right = B.Right)
    and (A.Bottom = B.Bottom);
end;

{ One shape for every pure action-row test: padding 12/8/12/8, lines of 16, a 16px icon slot
  with an 8px gap after it, a 14px close slot with a 10px gap before it, and 6px in front of
  every action. Three different gaps on purpose: a rule that reached for the wrong one moves
  a number here. }
function ActLayout(AW, AH: Integer; AIcon, ADesc, AClose: Boolean;
  const AWidths: array of Integer; AActionH: Integer): TTyAlertLayout;
begin
  Result := TyAlertLayout(AW, AH, AIcon, ADesc, AClose, 12, 8, 12, 8, 16, 16, 16, 8, 2, 10, 14,
    AWidths, AActionH, 6);
end;

{ TTyAlertActionLayoutTest }

procedure TTyAlertActionLayoutTest.TestNoActionsIsTheOldLayout;
var
  before, after: TTyAlertLayout;
begin
  // The full shape: icon, two lines, close.
  before := TyAlertLayout(300, 60, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 10, 14);
  after := ActLayout(300, 60, True, True, True, [], 22);
  AssertEquals('no action rects', 0, Length(after.ActionRects));
  AssertEquals('nor from the call without actions', 0, Length(before.ActionRects));
  AssertTrue('icon', SameRect(before.IconRect, after.IconRect));
  AssertTrue('message', SameRect(before.MessageRect, after.MessageRect));
  AssertTrue('description', SameRect(before.DescriptionRect, after.DescriptionRect));
  AssertTrue('close', SameRect(before.CloseRect, after.CloseRect));
  // ...and the bare one: the text column still runs to the band edge.
  after := ActLayout(300, 40, False, False, False, [], 22);
  AssertEquals('text reaches the band edge', 288, after.MessageRect.Right);
end;

procedure TTyAlertActionLayoutTest.TestOneActionHugsBandRight;
var
  L: TTyAlertLayout;
begin
  // No close glyph: the row ends where the content band ends (300 - 12).
  L := ActLayout(300, 40, False, False, False, [50], 22);
  AssertEquals('one rect per width', 1, Length(L.ActionRects));
  AssertEquals('ends at the band right', 288, L.ActionRects[0].Right);
  AssertEquals('as wide as asked', 238, L.ActionRects[0].Left);
end;

procedure TTyAlertActionLayoutTest.TestActionsSitInOrderBeforeTheClose;
var
  L: TTyAlertLayout;
begin
  // Close slot 274..288; the row stops a close gap (10) short of it, at 264. Three widths,
  // all different, 6 apart: 40 + 6 + 50 + 6 + 30 = 132, so the row starts at 132.
  L := ActLayout(300, 40, False, False, True, [40, 50, 30], 22);
  AssertEquals('the close keeps its slot', 274, L.CloseRect.Left);
  AssertEquals(3, Length(L.ActionRects));
  AssertEquals('first starts the row', 132, L.ActionRects[0].Left);
  AssertEquals('first ends', 172, L.ActionRects[0].Right);
  AssertEquals('second follows a gap later', 178, L.ActionRects[1].Left);
  AssertEquals('second ends', 228, L.ActionRects[1].Right);
  AssertEquals('third follows a gap later', 234, L.ActionRects[2].Left);
  AssertEquals('third stops a close gap before the x', 264, L.ActionRects[2].Right);
end;

procedure TTyAlertActionLayoutTest.TestTextStopsAnActionGapBeforeTheRow;
var
  L: TTyAlertLayout;
begin
  // The row starts at 132 (see above); the text column gives way a gap (6) before it.
  L := ActLayout(300, 40, True, False, True, [40, 50, 30], 22);
  AssertEquals('text still starts after the icon', 36, L.MessageRect.Left);
  AssertEquals('text stops before the row', 126, L.MessageRect.Right);
  // Both lines share the one column.
  L := ActLayout(300, 60, True, True, True, [40, 50, 30], 22);
  AssertEquals('so does the description', 126, L.DescriptionRect.Right);
end;

procedure TTyAlertActionLayoutTest.TestOneActionFewerGivesItsWidthBack;
var
  two, one: TTyAlertLayout;
begin
  two := ActLayout(300, 40, False, False, False, [40, 50], 22);
  one := ActLayout(300, 40, False, False, False, [40], 22);
  AssertEquals('two actions: text stops at', 186, two.MessageRect.Right);
  // The 50px action and the gap in front of it go back to the text.
  AssertEquals('one action: text stops at', 242, one.MessageRect.Right);
  AssertEquals('and the remaining action moves to the band edge', 288, one.ActionRects[0].Right);
  AssertEquals(248, one.ActionRects[0].Left);
end;

procedure TTyAlertActionLayoutTest.TestActionsCentreOnMessageLine;
var
  L: TTyAlertLayout;
begin
  // One line: the message line is 12..28, centre 20; a 22px action sits 9..31.
  L := ActLayout(300, 40, False, False, False, [40, 50], 22);
  AssertEquals('one line: top', 9, L.ActionRects[0].Top);
  AssertEquals('one line: bottom', 31, L.ActionRects[0].Bottom);
  AssertEquals('the whole row shares the band', L.ActionRects[0].Top, L.ActionRects[1].Top);
  AssertEquals(L.ActionRects[0].Bottom, L.ActionRects[1].Bottom);
  // Two lines in a 60px banner: the message line is 13..29, centre 21, so the action sits
  // 10..32 beside the HEADLINE. Centred in the banner it would be 19..41.
  L := ActLayout(300, 60, False, True, False, [40], 22);
  AssertEquals('two lines: top', 10, L.ActionRects[0].Top);
  AssertEquals('two lines: bottom', 32, L.ActionRects[0].Bottom);
end;

procedure TTyAlertActionLayoutTest.TestActionTallerThanBannerIsClamped;
var
  L: TTyAlertLayout;
begin
  // A 10px banner cannot hold a 22px action: squashed into the height, never past it.
  L := ActLayout(300, 10, False, False, False, [40], 22);
  AssertEquals('top floors at 0', 0, L.ActionRects[0].Top);
  AssertEquals('bottom clamped to the height', 10, L.ActionRects[0].Bottom);
end;

procedure TTyAlertActionLayoutTest.TestNarrowBannerServesCloseThenActionsThenIcon;
var
  L: TTyAlertLayout;
begin
  // W=160: band 12..148. The x keeps 134..148, the row ends at 124 and needs 96, so it
  // starts at 28 with both actions whole. That leaves the text column 12..22: the icon is
  // squeezed into those 10px and the text collapses.
  L := ActLayout(160, 40, True, False, True, [40, 50], 22);
  AssertEquals('the x keeps its full slot', 14, RectW(L.CloseRect));
  AssertEquals('first action whole', 40, RectW(L.ActionRects[0]));
  AssertEquals('first action starts', 28, L.ActionRects[0].Left);
  AssertEquals('second action whole', 50, RectW(L.ActionRects[1]));
  AssertEquals('second action ends before the x', 124, L.ActionRects[1].Right);
  AssertEquals('the icon starts at the band edge', 12, L.IconRect.Left);
  AssertEquals('and takes only what the actions left', 22, L.IconRect.Right);
  AssertEquals('text dropped', 0, RectW(L.MessageRect));
end;

procedure TTyAlertActionLayoutTest.TestActionsThatDoNotFitAreCutFromTheEnd;
var
  L: TTyAlertLayout;
begin
  // W=100: band 12..88, the x keeps 74..88, the row may use 12..64. Three actions need 132:
  // they are laid from the band edge in order, the first whole, the second cut at 64, the
  // third gone. Nothing is left for the icon or the text.
  L := ActLayout(100, 40, True, False, True, [40, 50, 30], 22);
  AssertEquals('the x keeps its full slot', 14, RectW(L.CloseRect));
  AssertEquals('first starts at the band edge', 12, L.ActionRects[0].Left);
  AssertEquals('first whole', 52, L.ActionRects[0].Right);
  AssertEquals('second starts a gap later', 58, L.ActionRects[1].Left);
  AssertEquals('second is cut where the row ends', 64, L.ActionRects[1].Right);
  AssertEquals('third dropped', 0, RectW(L.ActionRects[2]));
  AssertEquals('icon dropped', 0, RectW(L.IconRect));
  AssertEquals('text dropped', 0, RectW(L.MessageRect));

  // The same without a close glyph: the row may run to the band edge (58).
  L := ActLayout(70, 40, False, False, False, [40, 50], 22);
  AssertEquals('first whole', 52, L.ActionRects[0].Right);
  AssertEquals('second has nowhere to start', 0, RectW(L.ActionRects[1]));

  // W=40: the x alone fills the band; every action goes, the x survives.
  L := ActLayout(40, 40, True, False, True, [40, 50, 30], 22);
  AssertEquals('the x still keeps its full slot', 14, RectW(L.CloseRect));
  AssertEquals('no first action', 0, RectW(L.ActionRects[0]));
  AssertEquals('no second action', 0, RectW(L.ActionRects[1]));
  AssertEquals('no third action', 0, RectW(L.ActionRects[2]));
end;

procedure TTyAlertActionLayoutTest.TestNegativeActionInputsAreClamped;
var
  neg, zero: TTyAlertLayout;
begin
  // A negative width and a negative gap read as 0: the neighbour sits where it would
  // beside a zero-width action with no gap, and nothing comes out inverted.
  neg := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 10, 14,
    [-5, 40], 22, -3);
  zero := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 10, 14,
    [0, 40], 22, 0);
  AssertTrue('the neighbour is where a zero width leaves it',
    SameRect(zero.ActionRects[1], neg.ActionRects[1]));
  AssertEquals('and so is the end of the text', zero.MessageRect.Right, neg.MessageRect.Right);
  AssertEquals('whole', 40, RectW(neg.ActionRects[1]));
  AssertEquals('at the band edge', 288, neg.ActionRects[1].Right);
  AssertEquals('the negative one has no width', 0, RectW(neg.ActionRects[0]));
  // A negative height leaves no band at all.
  neg := ActLayout(300, 40, False, False, False, [40], -4);
  AssertEquals('no height, no rect', 0, RectH(neg.ActionRects[0]));
  AssertEquals('...and no width', 0, RectW(neg.ActionRects[0]));
end;

procedure TTyAlertActionLayoutTest.TestPreferredHeightWithoutActionsIsTheOldOne;
begin
  // An action height of 0 is "no visible action": the three shapes the old function has
  // (plain, two lines, floored by a slot) come out as before.
  AssertEquals('one line', TyAlertPreferredHeight(False, False, False, 8, 8, 16, 16, 2, 16, 14),
    TyAlertPreferredHeight(False, False, False, 8, 8, 16, 16, 2, 16, 14, 0));
  AssertEquals('two lines', TyAlertPreferredHeight(True, True, True, 8, 8, 16, 16, 2, 16, 14),
    TyAlertPreferredHeight(True, True, True, 8, 8, 16, 16, 2, 16, 14, 0));
  AssertEquals('icon floor', TyAlertPreferredHeight(True, False, False, 0, 0, 6, 6, 2, 16, 14),
    TyAlertPreferredHeight(True, False, False, 0, 0, 6, 6, 2, 16, 14, 0));
end;

procedure TTyAlertActionLayoutTest.TestPreferredHeightUnchangedWhenTheActionFits;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // pad 8 + line 16 + pad 8 = 32, and a 22px action centred on that line (5..27) is whole.
  h := TyAlertPreferredHeight(False, False, False, 8, 8, 16, 16, 2, 16, 14, 22);
  AssertEquals('the banner is no taller for it', 32, h);
  L := ActLayout(300, h, False, False, False, [40], 22);
  AssertEquals('the action is whole', 22, RectH(L.ActionRects[0]));
  AssertEquals(5, L.ActionRects[0].Top);
end;

procedure TTyAlertActionLayoutTest.TestPreferredHeightClearsATallAction;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // A 40px action beside a 16px line: the banner grows to hold it.
  h := TyAlertPreferredHeight(False, False, False, 8, 8, 16, 16, 2, 16, 14, 40);
  AssertEquals('grew to the action', 40, h);
  L := ActLayout(300, h, False, False, False, [40], 40);
  AssertEquals('the action is whole', 40, RectH(L.ActionRects[0]));
  AssertEquals('from the top edge', 0, L.ActionRects[0].Top);
end;

procedure TTyAlertActionLayoutTest.TestPreferredHeightClearsATallActionUnderUnevenPadding;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // The action centres on the MESSAGE line, and uneven padding moves that line off the
  // banner's centre -- so "at least as tall as the action" is not enough. pad 0/16, line 16,
  // action 24: a 32px banner has the line at 0..16 and the action would start at -4.
  h := TyAlertPreferredHeight(False, False, False, 0, 16, 16, 16, 2, 16, 14, 24);
  AssertEquals('all the padding below', 40, h);
  L := TyAlertLayout(300, h, False, False, False, 12, 0, 12, 16, 16, 16, 16, 8, 2, 10, 14,
    [40], 24, 6);
  AssertEquals('the action is whole', 24, RectH(L.ActionRects[0]));
  // ...and the other way round the action would run off the bottom: at 32 the line is
  // 16..32 and the action wants 12..36. 39 is the first height that holds it (line 19..35,
  // action 15..39).
  h := TyAlertPreferredHeight(False, False, False, 16, 0, 16, 16, 2, 16, 14, 24);
  AssertEquals('all the padding above', 39, h);
  L := TyAlertLayout(300, h, False, False, False, 12, 16, 12, 0, 16, 16, 16, 8, 2, 10, 14,
    [40], 24, 6);
  AssertEquals('the action is whole', 24, RectH(L.ActionRects[0]));
  AssertEquals('and ends on the bottom edge', 39, L.ActionRects[0].Bottom);
end;

procedure TTyAlertActionLayoutTest.TestPreferredHeightClearsATallActionBesideTwoLines;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // Two lines are 50 tall, which is more than the 40px action -- but the action sits beside
  // the HEADLINE (8..24), where it would start at -4. The banner grows until it does not.
  h := TyAlertPreferredHeight(False, True, False, 8, 8, 16, 16, 2, 16, 14, 40);
  AssertEquals(58, h);
  L := ActLayout(300, h, False, True, False, [40], 40);
  AssertEquals('the action is whole', 40, RectH(L.ActionRects[0]));
  AssertEquals('from the top edge', 0, L.ActionRects[0].Top);
end;

procedure TTyAlertActionLayoutTest.TestPreferredHeightIsTheSmallestThatClears;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // No padding, a 16px line, a 21px action: 21 is enough (line 2..18, action 0..21)...
  h := TyAlertPreferredHeight(False, False, False, 0, 0, 16, 16, 2, 16, 14, 21);
  AssertEquals(21, h);
  L := TyAlertLayout(300, h, False, False, False, 12, 0, 12, 0, 16, 16, 16, 8, 2, 10, 14,
    [40], 21, 6);
  AssertEquals('whole at the preferred height', 21, RectH(L.ActionRects[0]));
  // ...and one pixel less is not.
  L := TyAlertLayout(300, h - 1, False, False, False, 12, 0, 12, 0, 16, 16, 16, 8, 2, 10, 14,
    [40], 21, 6);
  AssertTrue('squashed one pixel below it', RectH(L.ActionRects[0]) < 21);
end;

{ ----- the action row: the control -------------------------------------------------------- }

const
  { cBarCss plus an action key that states everything the geometry and the ink read: a user
    rule for a typeKey shuts the built-in one out, so nothing from the base theme bleeds in. }
  cActCss = cBarCss + 'TyAlertAction { color: #111111; padding: 2px 8px; font-size: 12px; }';
  { A white bar with WHITE ink: the message and the icon vanish, so any colour found in the
    banner was put there by an action. }
  cBlankBarCss = 'TyAlert { background: #FFFFFF; color: #FFFFFF; padding: 8px 12px; font-size: 12px; }';

type
  { What a subclass can take over: the action itself, the width of what it shows, and the
    drawing. Each override reports that it ran. }
  TAlertSub = class(TAlertAccess)
  public
    Taken: Integer;            // DoAction calls
    SwallowAction: Boolean;    // do not pass DoAction on
    ContentW: Integer;         // > 0: what ActionContentWidth answers
    Drawn: Integer;            // DrawAction calls in the last render
    DrawnRects: array of TRect;
    DrawnActions: array of TTyAlertAction;
    LastStyle: TTyStyleSet;    // the style the last DrawAction call was handed
    SkipDraw: Boolean;         // do not pass DrawAction on
  protected
    procedure DoAction(AAction: TTyAlertAction); override;
    function ActionContentWidth(APainter: TTyPainter; AAction: TTyAlertAction;
      const AStyle: TTyStyleSet): Integer; override;
    procedure DrawAction(APainter: TTyPainter; AAction: TTyAlertAction; const ARect: TRect;
      const AStyle: TTyStyleSet); override;
  end;

procedure TAlertSub.DoAction(AAction: TTyAlertAction);
begin
  Inc(Taken);
  if not SwallowAction then inherited DoAction(AAction);
end;

function TAlertSub.ActionContentWidth(APainter: TTyPainter; AAction: TTyAlertAction;
  const AStyle: TTyStyleSet): Integer;
begin
  if ContentW > 0 then
    Result := ContentW
  else
    Result := inherited ActionContentWidth(APainter, AAction, AStyle);
end;

procedure TAlertSub.DrawAction(APainter: TTyPainter; AAction: TTyAlertAction;
  const ARect: TRect; const AStyle: TTyStyleSet);
begin
  Inc(Drawn);
  SetLength(DrawnRects, Drawn);
  DrawnRects[Drawn - 1] := ARect;
  SetLength(DrawnActions, Drawn);
  DrawnActions[Drawn - 1] := AAction;
  LastStyle := AStyle;
  if not SkipDraw then inherited DrawAction(APainter, AAction, ARect, AStyle);
end;

procedure SetUpActionAlert(A: TAlertAccess; AForm: TForm; ACtl: TTyStyleController;
  const ACaptions: array of string);
var
  i: Integer;
begin
  A.Parent := AForm;
  A.Controller := ACtl;
  A.Font.PixelsPerInch := 96;
  A.Message := 'Changed on disk';
  A.SetBounds(0, 0, 400, 40);
  for i := 0 to High(ACaptions) do
    A.Actions.Add.Caption := ACaptions[i];
end;

{ A 400x40 banner with one action per caption. Wide enough that three actions, the message
  and the close glyph all fit whole. }
function NewActionAlert(AForm: TForm; ACtl: TTyStyleController;
  const ACaptions: array of string): TAlertAccess;
begin
  Result := TAlertAccess.Create(AForm);
  SetUpActionAlert(Result, AForm, ACtl, ACaptions);
end;

function IsGreen(const Px: TBGRAPixel): Boolean;
begin
  Result := (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30);
end;

function IsRed(const Px: TBGRAPixel): Boolean;
begin
  Result := (Px.red > 150) and (Px.red > Px.green + 60) and (Px.red > Px.blue + 60);
end;

function IsBlue(const Px: TBGRAPixel): Boolean;
begin
  Result := (Px.blue > 180) and (Px.blue > Px.red + 60) and (Px.blue > Px.green + 60);
end;

function HasRedInk(R: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= R.Width) or (y >= R.Height) then Continue;
      if IsRed(R.GetPixel(x, y)) then Exit(True);
    end;
end;

{ The banner rendered as it stands, one pixel of it. }
function PixelOf(A: TAlertAccess; X, Y: Integer): TBGRAPixel;
var
  R: TBGRABitmap;
begin
  R := RenderToBGRA(A, A.Width, A.Height);
  try
    Result := R.GetPixel(X, Y);
  finally
    R.Free;
  end;
end;

{ A pixel of an action's chip that no caption reaches: three pixels into its horizontal
  padding (8px in every theme these tests load), on its middle line. }
function ChipPixel(A: TAlertAccess; AIndex: Integer): TBGRAPixel;
var
  R: TRect;
begin
  R := A.ActionRect(AIndex);
  Result := PixelOf(A, R.Left + 3, (R.Top + R.Bottom) div 2);
end;

function InkIn(A: TAlertAccess; const ARect: TRect; AGreen: Boolean): Boolean;
var
  R: TBGRABitmap;
begin
  R := RenderToBGRA(A, A.Width, A.Height);
  try
    if AGreen then Result := HasGreenInk(R, ARect) else Result := HasRedInk(R, ARect);
  finally
    R.Free;
  end;
end;

{ TTyAlertActionControlTest }

procedure TTyAlertActionControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FClosed := 0;
  FClicked := 0;
  FActed := 0;
  FLastAction := nil;
end;

procedure TTyAlertActionControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyAlertActionControlTest.HandleClose(Sender: TObject; var AllowClose: Boolean);
begin
  Inc(FClosed);
  AllowClose := False;   // keep the banner where the test can go on asking it
end;

procedure TTyAlertActionControlTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TTyAlertActionControlTest.HandleAction(Sender: TObject; AAction: TTyAlertAction);
begin
  Inc(FActed);
  FLastAction := AAction;
end;

procedure TTyAlertActionControlTest.TestDefaults;
var
  A: TTyAlert;
begin
  A := TTyAlert.Create(FForm);
  try
    AssertNotNull('the collection is there from the start', A.Actions);
    AssertEquals('and empty', 0, A.Actions.Count);
    AssertTrue('published', IsPublishedProp(A, 'Actions') and IsPublishedProp(A, 'OnAction'));
    AssertNull('no action anywhere on a banner without one', A.ActionAt(150, 20));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionDefaults;
var
  A: TTyAlert;
  act: TTyAlertAction;
begin
  A := TTyAlert.Create(FForm);
  try
    act := A.Actions.Add;
    AssertSame('Add hands back the new item', A.Actions[0], act);
    AssertEquals('no caption', '', act.Caption);
    AssertTrue('enabled', act.Enabled);
    AssertTrue('visible', act.Visible);
    AssertEquals('no hint', '', act.Hint);
    AssertEquals('tag 0', 0, act.Tag);
    AssertTrue('published', IsPublishedProp(act, 'Caption') and IsPublishedProp(act, 'Enabled')
      and IsPublishedProp(act, 'Visible') and IsPublishedProp(act, 'Hint')
      and IsPublishedProp(act, 'Tag'));
    // What the collection editor lists: the caption once there is one.
    AssertTrue('unnamed: not the caption', act.DisplayName <> 'Reload');
    act.Caption := 'Reload';
    AssertEquals('named by its caption', 'Reload', act.DisplayName);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionRectsRunInOrderToTheBandEdge;
var
  A: TAlertAccess;
  r0, r1, r2: TRect;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Merge', 'Keep Mine']);
  try
    r0 := A.ActionRect(0);
    r1 := A.ActionRect(1);
    r2 := A.ActionRect(2);
    AssertTrue('first has a rect', (RectW(r0) > 0) and (RectH(r0) > 0));
    AssertTrue('second has a rect', (RectW(r1) > 0) and (RectH(r1) > 0));
    AssertTrue('third has a rect', (RectW(r2) > 0) and (RectH(r2) > 0));
    AssertTrue('in collection order', (r0.Right <= r1.Left) and (r1.Right <= r2.Left));
    AssertEquals('the last ends at the themed right padding', 400 - 12, r2.Right);
    AssertEquals('one band', r0.Top, r2.Top);
    AssertEquals(r0.Bottom, r2.Bottom);
    AssertTrue('inside the banner', (r0.Top >= 0) and (r0.Bottom <= 40));
    AssertTrue('after the message', A.Lay.MessageRect.Right <= r0.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionRectsStopBeforeTheClose;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(':root { --alert-close-gap: 10px; }' + cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    AssertEquals('setup: no close, the row ends at the band', 388, A.ActionRect(1).Right);
    A.Closable := True;
    AssertEquals('the x is where it was without actions', 388, A.TyAlertCloseRect.Right);
    AssertEquals('the row stops a close gap before it', A.TyAlertCloseRect.Left - 10,
      A.ActionRect(1).Right);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionGapTokenSpacesTheRow;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(':root { --alert-action-gap: 6px; }' + cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    AssertEquals('between two actions', 6, A.ActionRect(1).Left - A.ActionRect(0).Right);
    AssertEquals('and between the text and the first', 6,
      A.ActionRect(0).Left - A.Lay.MessageRect.Right);
    FCtl.LoadThemeCss(':root { --alert-action-gap: 20px; }' + cActCss);
    AssertEquals('a theme widens it', 20, A.ActionRect(1).Left - A.ActionRect(0).Right);
    AssertEquals(20, A.ActionRect(0).Left - A.Lay.MessageRect.Right);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionGapReadsStyleOverride;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(':root { --alert-action-gap: 6px; }' + cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    AssertEquals('the theme''s', 6, A.ActionRect(1).Left - A.ActionRect(0).Right);
    A.StyleOverride := '--alert-action-gap: 30px;';
    AssertEquals('this banner''s own', 30, A.ActionRect(1).Left - A.ActionRect(0).Right);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestBaseThemeAgreesWithTheConstants;
var
  S: TTyStyleSet;
begin
  // FCtl has loaded nothing: this is the built-in base theme. Its values are the unit's
  // fallbacks, so a banner looks the same whether a theme names them or not.
  AssertEquals('--alert-action-gap', TyAlertActionGap, FCtl.Metric(TyAlertActionGapVar, -1));
  S := FCtl.Model.ResolveStyle('TyAlertAction', 'info', [tysNormal]);
  AssertTrue('the base theme pads an action', tpPadding in S.Present);
  AssertEquals('left', TyAlertActionPadX, S.Padding.Left);
  AssertEquals('right', TyAlertActionPadX, S.Padding.Right);
  AssertEquals('top', TyAlertActionPadY, S.Padding.Top);
  AssertEquals('bottom', TyAlertActionPadY, S.Padding.Bottom);
end;

procedure TTyAlertActionControlTest.TestActionWidthFollowsItsCaption;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['OK', 'Keep My Version']);
  try
    AssertTrue('the longer caption makes the wider action',
      RectW(A.ActionRect(1)) > RectW(A.ActionRect(0)) + 20);
    A.Actions[0].Caption := 'Keep My Version';
    AssertEquals('the same caption, the same width', RectW(A.ActionRect(1)),
      RectW(A.ActionRect(0)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionPaddingComesFromItsStyle;
var
  A: TAlertAccess;
  w, h: Integer;
begin
  FCtl.LoadThemeCss(cActCss);   // 2px 8px
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.SetBounds(0, 0, 400, 60);   // room for the taller action below
    w := RectW(A.ActionRect(0));
    h := RectH(A.ActionRect(0));
    FCtl.LoadThemeCss(cBarCss + 'TyAlertAction { color: #111111; padding: 6px 20px; font-size: 12px; }');
    AssertEquals('12px more on each side', w + 24, RectW(A.ActionRect(0)));
    AssertEquals('4px more above and below', h + 8, RectH(A.ActionRect(0)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionWithoutPaddingTakesTheBuiltInOne;
var
  A: TAlertAccess;
  named: TRect;
begin
  // The fallback is spelled out as a theme first, then left out: the same rect both times.
  FCtl.LoadThemeCss(cBarCss + Format('TyAlertAction { color: #111111; padding: %dpx %dpx; font-size: 12px; }',
    [TyAlertActionPadY, TyAlertActionPadX]));
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    named := A.ActionRect(0);
    FCtl.LoadThemeCss(cBarCss + 'TyAlertAction { color: #111111; font-size: 12px; }');
    AssertTrue('a key that sets no padding gets the built-in one',
      SameRect(named, A.ActionRect(0)));
    // An explicit zero is a value, not an absence.
    FCtl.LoadThemeCss(cBarCss + 'TyAlertAction { color: #111111; padding: 0px; font-size: 12px; }');
    AssertEquals('padding: 0 is honoured', RectW(named) - 2 * TyAlertActionPadX,
      RectW(A.ActionRect(0)));
    AssertEquals(RectH(named) - 2 * TyAlertActionPadY, RectH(A.ActionRect(0)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestHiddenActionGivesItsWidthBack;
var
  A: TAlertAccess;
  r0, r1, r2: TRect;
  textR: Integer;
begin
  FCtl.LoadThemeCss(':root { --alert-action-gap: 6px; }' + cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Merge', 'Keep Mine']);
  try
    r0 := A.ActionRect(0);
    r1 := A.ActionRect(1);
    r2 := A.ActionRect(2);
    textR := A.Lay.MessageRect.Right;
    A.Actions[1].Visible := False;
    AssertEquals('the hidden one has no rect', 0, RectW(A.ActionRect(1)));
    AssertTrue('the last stays at the band edge', SameRect(r2, A.ActionRect(2)));
    AssertEquals('the first closes up to it', r2.Left - 6, A.ActionRect(0).Right);
    AssertEquals('and keeps its width', RectW(r0), RectW(A.ActionRect(0)));
    AssertEquals('the message gets the action and its gap', textR + RectW(r1) + 6,
      A.Lay.MessageRect.Right);
    A.Actions[1].Visible := True;
    AssertTrue('shown again, it is back where it was', SameRect(r1, A.ActionRect(1)));
    AssertEquals(textR, A.Lay.MessageRect.Right);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionRectOutOfRangeIsEmpty;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Merge', 'Keep Mine']);
  try
    AssertTrue('setup: a real index has a rect', RectW(A.ActionRect(2)) > 0);
    AssertEquals('below the range', 0, RectW(A.ActionRect(-1)));
    AssertEquals('past the range', 0, RectW(A.ActionRect(3)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestRightToLeftMirrorsTheRow;
var
  A: TAlertAccess;
  l0, l1: TRect;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.Closable := True;
    l0 := A.ActionRect(0);
    l1 := A.ActionRect(1);
    AssertTrue('setup: the row is on the right, in reading order',
      (l0.Left > 200) and (l0.Left < l1.Left));
    A.BiDiMode := bdRightToLeft;
    AssertTrue('first mirrored', SameRect(TyMirrorRectX(l0, 400), A.ActionRect(0)));
    AssertTrue('second mirrored', SameRect(TyMirrorRectX(l1, 400), A.ActionRect(1)));
    AssertTrue('the row is on the left, the first action nearest the text',
      (A.ActionRect(0).Right < 200) and (A.ActionRect(0).Left > A.ActionRect(1).Left));
    AssertTrue('still between the close glyph and the text',
      (A.TyAlertCloseRect.Right <= A.ActionRect(1).Left)
      and (A.ActionRect(0).Right <= A.Lay.MessageRect.Left));
    // The hit test reads the same mirrored rects.
    p := A.ActionCentre(1);
    AssertSame('a click lands on what is drawn there', A.Actions[1], A.ActionAt(p.X, p.Y));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionAtFollowsTheRects;
var
  A: TAlertAccess;
  r0, r1, rc: TRect;
  i: Integer;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Merge', 'Keep Mine']);
  try
    A.Closable := True;
    for i := 0 to 2 do
    begin
      p := A.ActionCentre(i);
      AssertSame('the middle of action ' + IntToStr(i), A.Actions[i], A.ActionAt(p.X, p.Y));
    end;
    r0 := A.ActionRect(0);
    r1 := A.ActionRect(1);
    AssertSame('the top-left pixel belongs to it', A.Actions[0], A.ActionAt(r0.Left, r0.Top));
    AssertSame('the last pixel too', A.Actions[0], A.ActionAt(r0.Right - 1, r0.Bottom - 1));
    AssertNull('the gap between two actions is nobody''s',
      A.ActionAt((r0.Right + r1.Left) div 2, (r0.Top + r0.Bottom) div 2));
    AssertTrue('setup: there is banner above the row', r0.Top > 0);
    AssertNull('above the row', A.ActionAt((r0.Left + r0.Right) div 2, r0.Top - 1));
    AssertNull('below the row', A.ActionAt((r0.Left + r0.Right) div 2, r0.Bottom));
    AssertNull('the message is not an action', A.ActionAt(60, 20));
    rc := A.TyAlertCloseRect;
    AssertNull('nor is the close glyph',
      A.ActionAt((rc.Left + rc.Right) div 2, (rc.Top + rc.Bottom) div 2));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionAtSeesDisabledButNotHidden;
var
  A: TAlertAccess;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    p := A.ActionCentre(0);
    A.Actions[0].Enabled := False;
    AssertSame('a disabled action is still what is there', A.Actions[0], A.ActionAt(p.X, p.Y));
    A.Actions[0].Visible := False;
    AssertNull('a hidden one is not', A.ActionAt(p.X, p.Y));
    // With the first one hidden, what is drawn at the row's place is the SECOND action.
    A.Actions.Add.Caption := 'Keep Mine';
    p := A.ActionCentre(1);
    AssertSame('the visible action, not the hidden one before it', A.Actions[1],
      A.ActionAt(p.X, p.Y));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestClickFiresOnActionOnly;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Merge', 'Keep Mine']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    A.ClickAction(1);
    AssertEquals('OnAction fired once', 1, FActed);
    AssertSame('for the action that was clicked', A.Actions[1], FLastAction);
    AssertEquals('the banner was not clicked', 0, FClicked);
    A.ClickAction(0);
    AssertEquals(2, FActed);
    AssertSame('each click names its own action', A.Actions[0], FLastAction);
    AssertEquals(0, FClicked);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestClickWithCloseFiresOnActionNotOnClose;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.Closable := True;
    A.OnAction := @HandleAction;
    A.OnClose := @HandleClose;
    A.ClickAction(1);   // the action right beside the x
    AssertEquals('OnAction fired', 1, FActed);
    AssertEquals('OnClose did not', 0, FClosed);
    AssertTrue('the banner is still there', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestCloseBesideActionsStillCloses;
var
  A: TAlertAccess;
  rc: TRect;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.Closable := True;
    A.OnAction := @HandleAction;
    A.OnClose := @HandleClose;
    A.OnClick := @HandleClick;
    rc := A.TyAlertCloseRect;
    A.PressReleaseAt((rc.Left + rc.Right) div 2, (rc.Top + rc.Bottom) div 2);
    AssertEquals('OnClose fired', 1, FClosed);
    AssertEquals('no action', 0, FActed);
    AssertEquals('no banner click', 0, FClicked);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDownOnOneUpOnAnotherFiresNothing;
var
  A: TAlertAccess;
  p0, p1: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    p0 := A.ActionCentre(0);
    p1 := A.ActionCentre(1);
    A.PressAtReleaseAt(p0.X, p0.Y, p1.X, p1.Y);
    AssertEquals('neither action', 0, FActed);
    AssertEquals('nor the banner', 0, FClicked);
    // The same two points, each on its own, do fire: the gesture is what failed above.
    A.PressAtReleaseAt(p1.X, p1.Y, p1.X, p1.Y);
    AssertEquals(1, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDownOnActionUpOnBodyFiresNothing;
var
  A: TAlertAccess;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    p := A.ActionCentre(0);
    A.PressAtReleaseAt(p.X, p.Y, 60, 20);     // released on the message
    AssertEquals('dragged off: no action', 0, FActed);
    AssertEquals('and the press was never the banner''s', 0, FClicked);
    A.PressAtReleaseAt(p.X, p.Y, -5, -5);     // released outside the banner
    AssertEquals(0, FActed);
    AssertEquals(0, FClicked);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDownOnBodyUpOnActionIsABannerClick;
var
  A: TAlertAccess;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    p := A.ActionCentre(0);
    A.PressAtReleaseAt(60, 20, p.X, p.Y);
    AssertEquals('the press did not start on the action', 0, FActed);
    AssertEquals('it started on the banner, and ended inside it', 1, FClicked);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDisabledActionFiresNothing;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    A.Actions[0].Enabled := False;
    A.ClickAction(0);
    AssertEquals('a disabled action does nothing', 0, FActed);
    AssertEquals('and its click is not the banner''s either', 0, FClicked);
    A.ClickAction(1);
    AssertEquals('its neighbour still works', 1, FActed);
    A.Actions[0].Enabled := True;
    A.ClickAction(0);
    AssertEquals('enabled again, it fires', 2, FActed);
    AssertSame(A.Actions[0], FLastAction);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDisabledBannerFiresNothing;
var
  A: TAlertAccess;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.OnAction := @HandleAction;
    A.Enabled := False;
    A.ClickAction(0);
    AssertEquals('a disabled banner has no live action', 0, FActed);
    A.Enabled := True;
    A.ClickAction(0);
    AssertEquals('enabled again, it fires', 1, FActed);
    // Disabled while the button is down: the release does nothing either.
    p := A.ActionCentre(0);
    A.Down(p.X, p.Y);
    A.Enabled := False;
    A.Up(p.X, p.Y);
    AssertEquals('disabled mid-press', 1, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestRightButtonDuringAPressDoesNotEndIt;
var
  A: TAlertAccess;
  p: TPoint;
begin
  // The left button is held on an action; the right one goes down and up over it. That is
  // not the release the press is waiting for: nothing fires, and the left release still
  // completes the click.
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    p := A.ActionCentre(0);
    A.Down(p.X, p.Y);
    A.RightPressReleaseAt(p.X, p.Y);
    AssertEquals('the right button fired nothing', 0, FActed);
    A.Up(p.X, p.Y);
    AssertEquals('the left release is still the click', 1, FActed);
    AssertEquals('and still not the banner''s', 0, FClicked);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestRightButtonFiresNothing;
var
  A: TAlertAccess;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    p := A.ActionCentre(0);
    A.RightPressReleaseAt(p.X, p.Y);
    AssertEquals('the right button is not a click on an action', 0, FActed);
    // ...and it leaves nothing armed: the next left click on the banner is the banner's.
    A.PressReleaseAt(60, 20);
    AssertEquals(1, FClicked);
    AssertEquals(0, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestRightButtonDoesNotPressAnAction;
var
  A: TAlertAccess;
  p: TPoint;
begin
  // The pressed look is the left button's. Held down, the right button leaves the action
  // as it was (a context menu is about to open over it, not a click).
  FCtl.LoadThemeCss(cActCss + 'TyAlertAction:active { background: #EF4444; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    p := A.ActionCentre(0);
    A.MouseDown(mbRight, [], p.X, p.Y);
    AssertFalse('right button down: not pressed', IsRed(ChipPixel(A, 0)));
    A.MouseUp(mbRight, [], p.X, p.Y);
    A.Down(p.X, p.Y);
    AssertTrue('left button down: pressed', IsRed(ChipPixel(A, 0)));
    A.Up(p.X, p.Y);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionWorksUnderActiveStatePadding;
var
  A: TAlertAccess;
begin
  // :active moves the right padding from 12 to 60, which would carry the row 48px to the
  // left. The action is PAINTED at rest; a press on it is a press on it.
  FCtl.LoadThemeCss(cActCss + 'TyAlert:active { background: #FFFFFF; padding: 8px 60px; }');
  A := NewActionAlert(FForm, FCtl, ['OK']);
  try
    A.OnAction := @HandleAction;
    AssertTrue('setup: the shift is wider than the action', RectW(A.ActionRect(0)) < 48);
    A.ClickAction(0);
    AssertEquals('a press on the visible action fires it', 1, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestBackgroundlessAlertHasNoLiveActions;
var
  A: TAlertAccess;
begin
  // A banner that painted nothing has no button the user could have aimed at.
  FCtl.LoadThemeCss('TyAlert { color: #111111; padding: 8px 12px; font-size: 12px; }' +
    'TyAlertAction { color: #111111; padding: 2px 8px; font-size: 12px; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.OnAction := @HandleAction;
    A.OnClick := @HandleClick;
    A.ClickAction(0);
    AssertEquals('no action', 0, FActed);
    AssertEquals('no click', 0, FClicked);
    // The one thing missing was the background.
    FCtl.LoadThemeCss(cActCss);
    A.ClickAction(0);
    AssertEquals('with a banner to click, it fires', 1, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionRemovedDuringThePressFiresNothing;
var
  A: TAlertAccess;
  p: TPoint;
begin
  // Pressed on the first action; the host deletes it while the button is down (a refresh
  // from a timer), so the second action becomes item 0. Released on that one: it was never
  // pressed, and the one that was is gone.
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.OnAction := @HandleAction;
    p := A.ActionCentre(0);
    A.Down(p.X, p.Y);
    A.Actions.Delete(0);
    p := A.ActionCentre(0);
    A.Up(p.X, p.Y);
    AssertEquals('nothing fires', 0, FActed);
    A.ClickAction(0);
    AssertEquals('a whole click on the survivor does', 1, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionsStreamRoundTrip;
var
  A, B: TTyAlert;
  f2: TForm;
  ms, txt: TMemoryStream;
  lfm: string;
begin
  if GetClass('TTyAlert') = nil then RegisterClass(TTyAlert);
  A := TTyAlert.Create(FForm);
  A.Name := 'Bar';
  A.Parent := FForm;
  with A.Actions.Add do
  begin
    Caption := 'Reload';
    Hint := 'Read the file again';
    Tag := 7;
  end;
  with A.Actions.Add do
  begin
    Caption := 'Keep Mine';
    Enabled := False;
  end;
  with A.Actions.Add do
  begin
    Caption := 'Merge';
    Visible := False;
  end;
  f2 := nil;
  ms := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    ms.WriteComponent(FForm);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(lfm, PChar(txt.Memory), txt.Size);
    AssertTrue('the collection is in the form file', Pos('Actions = <', lfm) > 0);
    AssertTrue('caption', Pos('Caption = ''Reload''', lfm) > 0);
    AssertTrue('hint', Pos('Hint = ''Read the file again''', lfm) > 0);
    AssertTrue('tag', Pos('Tag = 7', lfm) > 0);
    AssertTrue('the disabled one says so', Pos('Enabled = False', lfm) > 0);
    AssertTrue('the hidden one says so', Pos('Visible = False', lfm) > 0);
    AssertEquals('the defaults are not written', 0,
      Pos('Enabled = True', lfm) + Pos('Visible = True', lfm) + Pos('Tag = 0', lfm));
    ms.Position := 0;
    f2 := TForm.CreateNew(nil);
    ms.ReadComponent(f2);
    B := f2.FindComponent('Bar') as TTyAlert;
    AssertEquals('three actions came back', 3, B.Actions.Count);
    AssertEquals('Reload', B.Actions[0].Caption);
    AssertEquals('Read the file again', B.Actions[0].Hint);
    AssertEquals(7, B.Actions[0].Tag);
    AssertTrue('first: enabled and visible', B.Actions[0].Enabled and B.Actions[0].Visible);
    AssertEquals('Keep Mine', B.Actions[1].Caption);
    AssertFalse('second: disabled', B.Actions[1].Enabled);
    AssertTrue('second: visible', B.Actions[1].Visible);
    AssertEquals('Merge', B.Actions[2].Caption);
    AssertFalse('third: hidden', B.Actions[2].Visible);
    AssertTrue('third: enabled', B.Actions[2].Enabled);
  finally
    txt.Free;
    ms.Free;
    f2.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestAssignCopiesTheActions;
var
  A, B: TTyAlert;
begin
  A := TTyAlert.Create(FForm);
  B := TTyAlert.Create(FForm);
  with A.Actions.Add do
  begin
    Caption := 'Reload';
    Hint := 'Read the file again';
    Tag := 7;
    Enabled := False;
  end;
  with A.Actions.Add do
  begin
    Caption := 'Merge';
    Visible := False;
  end;
  B.Actions.Add.Caption := 'stale';
  B.Actions := A.Actions;
  AssertEquals('the list is replaced, not appended to', 2, B.Actions.Count);
  AssertTrue('by copies', B.Actions[0] <> A.Actions[0]);
  AssertEquals('Reload', B.Actions[0].Caption);
  AssertEquals('Read the file again', B.Actions[0].Hint);
  AssertEquals(7, B.Actions[0].Tag);
  AssertFalse(B.Actions[0].Enabled);
  AssertTrue(B.Actions[0].Visible);
  AssertEquals('Merge', B.Actions[1].Caption);
  AssertFalse(B.Actions[1].Visible);
  AssertTrue(B.Actions[1].Enabled);
end;

procedure TTyAlertActionControlTest.TestActionInkComesFromItsKey;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cBlankBarCss + 'TyAlertAction { color: #10B981; padding: 2px 8px; font-size: 12px; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    AssertTrue('the caption is drawn in the action''s ink', InkIn(A, A.ActionRect(0), True));
    AssertFalse('and only there', InkIn(A, A.Lay.MessageRect, True));
    AssertFalse('setup: nothing red yet', InkIn(A, A.ActionRect(0), False));
    FCtl.LoadThemeCss(cBlankBarCss + 'TyAlertAction { color: #EF4444; padding: 2px 8px; font-size: 12px; }');
    AssertTrue('another theme, another ink', InkIn(A, A.ActionRect(0), False));
    AssertFalse('the old one is gone', InkIn(A, A.ActionRect(0), True));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionWithoutColourTakesTheBarInk;
var
  A: TAlertAccess;
begin
  // A key that sets no colour: the caption is written in the banner's own ink, as the
  // close glyph is.
  FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px; font-size: 12px; }' +
    'TyAlertAction { padding: 2px 8px; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    AssertTrue('green bar ink, green caption', InkIn(A, A.ActionRect(0), True));
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #EF4444; padding: 8px 12px; font-size: 12px; }' +
      'TyAlertAction { padding: 2px 8px; }');
    AssertTrue('red bar ink, red caption', InkIn(A, A.ActionRect(0), False));
    AssertFalse(InkIn(A, A.ActionRect(0), True));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionWithoutFontTakesTheBarFont;
var
  A: TAlertAccess;
  small: TRect;
begin
  FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 12px; }' +
    'TyAlertAction { padding: 2px 8px; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    A.SetBounds(0, 0, 400, 80);   // room for the 24px line below
    small := A.ActionRect(0);
    // The banner's font doubles and the action key still names none: the action follows.
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 24px; }' +
      'TyAlertAction { padding: 2px 8px; }');
    AssertTrue('taller with the banner''s font', RectH(A.ActionRect(0)) > RectH(small) + 8);
    AssertTrue('and wider', RectW(A.ActionRect(0)) > RectW(small) + 8);
    // A font of its own wins over the banner's.
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 24px; }' +
      'TyAlertAction { padding: 2px 8px; font-size: 12px; }');
    AssertEquals('its own size: the small height again', RectH(small), RectH(A.ActionRect(0)));
    AssertEquals('and the small width', RectW(small), RectW(A.ActionRect(0)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionWithoutWeightTakesTheBarWeight;
var
  A: TAlertAccess;
  regular: Integer;
begin
  // The same for the weight: a bold banner writes bold actions, which are wider.
  FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 12px; font-weight: 400; }' +
    'TyAlertAction { padding: 2px 8px; }');
  A := NewActionAlert(FForm, FCtl, ['Keep My Version']);
  try
    regular := RectW(A.ActionRect(0));
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 12px; font-weight: 700; }' +
      'TyAlertAction { padding: 2px 8px; }');
    AssertTrue('wider in the banner''s bold', RectW(A.ActionRect(0)) > regular);
    // A weight of its own wins over the banner's.
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 12px; font-weight: 700; }' +
      'TyAlertAction { padding: 2px 8px; font-weight: 400; }');
    AssertEquals('its own weight: the regular width again', regular, RectW(A.ActionRect(0)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestBannerColourOverrideLeavesDisabledInkAlone;
var
  A: TAlertAccess;
begin
  // StyleOverride's `color` is the banner's live ink, and it reaches the actions as it
  // reaches any part. It is not laid over :disabled: a disabled action in the live ink
  // would look live.
  FCtl.LoadThemeCss(cBlankBarCss + 'TyAlertAction { color: #FFFFFF; padding: 2px 8px; font-size: 12px; }' +
    'TyAlertAction:disabled { color: #10B981; }');
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.Actions[1].Enabled := False;
    AssertFalse('setup: the enabled action is in the theme''s (white) ink',
      InkIn(A, A.ActionRect(0), False));
    A.StyleOverride := 'color: #EF4444;';
    AssertTrue('the override inks the enabled action', InkIn(A, A.ActionRect(0), False));
    AssertTrue('the disabled one keeps the :disabled ink', InkIn(A, A.ActionRect(1), True));
    AssertFalse('and takes none of the override', InkIn(A, A.ActionRect(1), False));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionBorderIsDrawn;
var
  A: TAlertAccess;
  R: TRect;
begin
  // A theme that outlines its actions: the border of the key is stroked round the rect.
  // The probe is just inside the rect's left edge on its middle line, where no caption
  // reaches.
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    R := A.ActionRect(0);
    AssertFalse('no border in the theme, none drawn',
      IsGreen(PixelOf(A, R.Left + 1, (R.Top + R.Bottom) div 2)));
    FCtl.LoadThemeCss(cBarCss + 'TyAlertAction { color: #111111; padding: 2px 8px; font-size: 12px;' +
      ' border-color: #10B981; border-width: 2px; }');
    R := A.ActionRect(0);
    AssertTrue('the themed border is drawn',
      IsGreen(PixelOf(A, R.Left + 1, (R.Top + R.Bottom) div 2)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestCaptionKeepsClearOfTheActionPadding;
var
  A: TAlertAccess;
  R: TRect;
begin
  // Lopsided padding, 30px before the caption and 4px after it: the 20px at the leading end
  // of the rect stay clear of ink. (Centred in the whole rect, the caption would start 17px
  // in.) Right to left the leading end is the right one.
  FCtl.LoadThemeCss(cBlankBarCss +
    'TyAlertAction { color: #10B981; padding: 2px 4px 2px 30px; font-size: 12px; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    R := A.ActionRect(0);
    AssertTrue('setup: the caption is drawn', InkIn(A, R, True));
    AssertFalse('nothing in the leading padding',
      InkIn(A, Rect(R.Left, R.Top, R.Left + 20, R.Bottom), True));
    AssertTrue('the caption runs to the trailing end',
      InkIn(A, Rect(R.Right - 20, R.Top, R.Right, R.Bottom), True));
    A.BiDiMode := bdRightToLeft;
    R := A.ActionRect(0);
    AssertTrue('setup: the caption is drawn mirrored', InkIn(A, R, True));
    AssertFalse('mirrored: nothing in the leading padding, now on the right',
      InkIn(A, Rect(R.Right - 20, R.Top, R.Right, R.Bottom), True));
    AssertTrue('mirrored: the caption runs to the left end',
      InkIn(A, Rect(R.Left, R.Top, R.Left + 20, R.Bottom), True));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestHoverPaddingDoesNotMoveTheCaption;
var
  A: TAlertAccess;
  R, lead: TRect;
  p: TPoint;
begin
  // The row is measured at rest, so it is drawn with the resting padding in every state.
  // A :hover rule that pads the caption 40px in would push it out of the 24px after the
  // resting padding; it stays where it was.
  FCtl.LoadThemeCss(cBlankBarCss +
    'TyAlertAction { color: #10B981; padding: 2px 8px; font-size: 12px; }' +
    'TyAlertAction:hover { padding: 2px 8px 2px 40px; }');
  A := NewActionAlert(FForm, FCtl, ['Keep My Version']);
  try
    R := A.ActionRect(0);
    lead := Rect(R.Left + 8, R.Top, R.Left + 32, R.Bottom);
    AssertTrue('setup: at rest the caption starts right after the padding', InkIn(A, lead, True));
    p := A.ActionCentre(0);
    A.MoveTo(p.X, p.Y);
    AssertTrue('the rect did not move', SameRect(R, A.ActionRect(0)));
    AssertTrue('and the caption did not either', InkIn(A, lead, True));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestVariantReachesTheAction;
var
  A: TAlertAccess;
begin
  // The action resolves under the banner's variant, so a theme can tint the actions of one
  // kind of banner: only .warning is green here.
  FCtl.LoadThemeCss(cBlankBarCss + 'TyAlertAction { color: #FFFFFF; padding: 2px 8px; font-size: 12px; }' +
    'TyAlertAction.warning { color: #10B981; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    AssertFalse('an info banner: the plain rule', InkIn(A, A.ActionRect(0), True));
    A.AlertType := atWarning;
    AssertTrue('a warning banner: its variant''s ink', InkIn(A, A.ActionRect(0), True));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestHoverLightsOnlyTheActionUnderThePointer;
var
  A: TAlertAccess;
  p0, p1: TPoint;
begin
  FCtl.LoadThemeCss(cActCss + 'TyAlertAction:hover { background: #10B981; }');
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    p0 := A.ActionCentre(0);
    p1 := A.ActionCentre(1);
    AssertFalse('at rest: no chip', IsGreen(ChipPixel(A, 0)));
    A.MoveTo(p0.X, p0.Y);
    AssertTrue('the action under the pointer lights', IsGreen(ChipPixel(A, 0)));
    AssertFalse('its neighbour does not', IsGreen(ChipPixel(A, 1)));
    A.MoveTo(p1.X, p1.Y);
    AssertTrue('the pointer moved on: the neighbour lights', IsGreen(ChipPixel(A, 1)));
    AssertFalse('and the first goes out', IsGreen(ChipPixel(A, 0)));
    // The chip is the theme's: another theme, another colour, the same pointer.
    FCtl.LoadThemeCss(cActCss + 'TyAlertAction:hover { background: #3B82F6; }');
    AssertTrue('a blue theme, a blue chip', IsBlue(ChipPixel(A, 1)));
    AssertFalse(IsGreen(ChipPixel(A, 1)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestLeavingClearsTheHover;
var
  A: TAlertAccess;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cActCss + 'TyAlertAction:hover { background: #10B981; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    p := A.ActionCentre(0);
    A.MoveTo(p.X, p.Y);
    AssertTrue('setup: lit', IsGreen(ChipPixel(A, 0)));
    A.MoveTo(60, 20);   // onto the message
    AssertFalse('off the action, still on the banner', IsGreen(ChipPixel(A, 0)));
    A.MoveTo(p.X, p.Y);
    AssertTrue('setup: lit again', IsGreen(ChipPixel(A, 0)));
    A.Leave;
    AssertFalse('off the banner', IsGreen(ChipPixel(A, 0)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestPressedLookFollowsThePointer;
var
  A: TAlertAccess;
  p0, p1: TPoint;
begin
  FCtl.LoadThemeCss(cActCss + 'TyAlertAction:hover { background: #10B981; }' +
    'TyAlertAction:active { background: #EF4444; }');
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.OnAction := @HandleAction;
    p0 := A.ActionCentre(0);
    p1 := A.ActionCentre(1);
    // No move before the press (a touch): the press itself says where the pointer is.
    A.Down(p0.X, p0.Y);
    AssertTrue('held down: the pressed look', IsRed(ChipPixel(A, 0)));
    A.MoveTo(60, 20);
    AssertFalse('dragged off: not pressed', IsRed(ChipPixel(A, 0)));
    AssertFalse('nor hovered', IsGreen(ChipPixel(A, 0)));
    A.MoveTo(p1.X, p1.Y);
    AssertFalse('over another action: that one is not pressed', IsRed(ChipPixel(A, 1)));
    AssertFalse('and does not light, the press is not its', IsGreen(ChipPixel(A, 1)));
    A.MoveTo(p0.X, p0.Y);
    AssertTrue('dragged back: pressed again', IsRed(ChipPixel(A, 0)));
    A.Up(p0.X, p0.Y);
    AssertTrue('released: hovered', IsGreen(ChipPixel(A, 0)));
    AssertEquals('and the click counted', 1, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestPressOnActionDoesNotPressTheBar;
var
  A: TAlertAccess;
  p: TPoint;
begin
  // (60, 4) is bar: right of the icon slot, above the message line.
  FCtl.LoadThemeCss(cActCss + 'TyAlert:active { background: #EF4444; }');
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    p := A.ActionCentre(0);
    A.Down(p.X, p.Y);
    AssertFalse('the bar does not go :active behind a pressed action', IsRed(PixelOf(A, 60, 4)));
    A.Up(p.X, p.Y);
    A.Down(60, 20);
    AssertTrue('a press on the bar itself does', IsRed(PixelOf(A, 60, 4)));
    A.Up(60, 20);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestPressElsewhereLightsNoAction;
var
  A: TAlertAccess;
  p, pd: TPoint;
  rc: TRect;
begin
  // A press belongs to where it started. Held on the bar, on the x or on a disabled action
  // and dragged over an enabled one, it does not light that one; with no button down the
  // same pointer does.
  FCtl.LoadThemeCss(cActCss + 'TyAlertAction:hover { background: #10B981; }');
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    A.Closable := True;
    A.OnClose := @HandleClose;
    A.Actions[1].Enabled := False;
    p := A.ActionCentre(0);
    A.Down(60, 20);                       // on the bar
    A.MoveTo(p.X, p.Y);
    AssertFalse('a press from the bar', IsGreen(ChipPixel(A, 0)));
    A.Up(p.X, p.Y);
    AssertTrue('released: the pointer is just a pointer again', IsGreen(ChipPixel(A, 0)));
    A.Leave;
    rc := A.TyAlertCloseRect;
    A.Down((rc.Left + rc.Right) div 2, (rc.Top + rc.Bottom) div 2);   // on the x
    A.MoveTo(p.X, p.Y);
    AssertFalse('a press from the close glyph', IsGreen(ChipPixel(A, 0)));
    A.Up(p.X, p.Y);
    AssertEquals('and dragged off the x, it closed nothing', 0, FClosed);
    A.Leave;
    pd := A.ActionCentre(1);
    A.Down(pd.X, pd.Y);                   // on the disabled action
    A.MoveTo(p.X, p.Y);
    AssertFalse('a press from a disabled action', IsGreen(ChipPixel(A, 0)));
    A.Up(p.X, p.Y);
    AssertTrue('released: lit', IsGreen(ChipPixel(A, 0)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestPointerOverActionsAsksForARepaint;
var
  A: TAlertAccess;
  p0, p1: TPoint;
  n: Integer;
begin
  // The looks above are only seen if the control asks to be painted again when the action
  // under the pointer changes -- and it should not ask while nothing changes.
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    p0 := A.ActionCentre(0);
    p1 := A.ActionCentre(1);
    A.MoveTo(60, 20);
    n := A.Invalidations;
    A.MoveTo(61, 20);
    AssertEquals('moving over the message changes nothing', n, A.Invalidations);
    A.MoveTo(p0.X, p0.Y);
    AssertTrue('onto an action', A.Invalidations > n);
    n := A.Invalidations;
    A.MoveTo(p0.X + 1, p0.Y);
    AssertEquals('within the same action: nothing new', n, A.Invalidations);
    A.MoveTo(p1.X, p1.Y);
    AssertTrue('onto its neighbour', A.Invalidations > n);
    n := A.Invalidations;
    A.Leave;
    AssertTrue('off the banner', A.Invalidations > n);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestChangingAnActionAsksForARepaint;
var
  A: TAlertAccess;
  n: Integer;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, ['Reload']);
  try
    n := A.Invalidations;
    A.Actions[0].Caption := 'Reload';
    AssertEquals('the same caption again: nothing to repaint', n, A.Invalidations);
    A.Actions[0].Caption := 'Reload from disk';
    AssertTrue('a new caption', A.Invalidations > n);
    n := A.Invalidations;
    A.Actions[0].Enabled := False;
    AssertTrue('disabled', A.Invalidations > n);
    n := A.Invalidations;
    A.Actions[0].Visible := False;
    AssertTrue('hidden', A.Invalidations > n);
    n := A.Invalidations;
    A.Actions.Add;
    AssertTrue('an action added', A.Invalidations > n);
    n := A.Invalidations;
    A.Actions.Delete(1);
    AssertTrue('an action removed', A.Invalidations > n);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDisabledActionTakesDisabledInkAndNoHover;
var
  A: TAlertAccess;
  p: TPoint;
begin
  FCtl.LoadThemeCss(cBlankBarCss + 'TyAlertAction { color: #FFFFFF; padding: 2px 8px; font-size: 12px; }' +
    'TyAlertAction:disabled { color: #10B981; }' +
    'TyAlertAction:hover { background: #EF4444; }');
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    AssertFalse('setup: enabled, the plain ink', InkIn(A, A.ActionRect(0), True));
    A.Actions[0].Enabled := False;
    AssertTrue('disabled: the :disabled ink', InkIn(A, A.ActionRect(0), True));
    AssertFalse('its neighbour keeps the plain one', InkIn(A, A.ActionRect(1), True));
    p := A.ActionCentre(0);
    A.MoveTo(p.X, p.Y);
    AssertFalse('a disabled action does not light', IsRed(ChipPixel(A, 0)));
    p := A.ActionCentre(1);
    A.MoveTo(p.X, p.Y);
    AssertTrue('an enabled one does', IsRed(ChipPixel(A, 1)));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDisabledBannerDisablesEveryAction;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cBlankBarCss + 'TyAlertAction { color: #FFFFFF; padding: 2px 8px; font-size: 12px; }' +
    'TyAlertAction:disabled { color: #10B981; }');
  A := NewActionAlert(FForm, FCtl, ['Reload', 'Keep Mine']);
  try
    AssertFalse('setup: the plain ink', InkIn(A, A.ActionRect(1), True));
    A.Enabled := False;
    AssertTrue('first', InkIn(A, A.ActionRect(0), True));
    AssertTrue('second', InkIn(A, A.ActionRect(1), True));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestPreferredHeightUnchangedByAFittingAction;
var
  A: TAlertAccess;
  w, bare, withAction: Integer;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, []);
  try
    A.PreferredSize(w, bare);
    A.Actions.Add.Caption := 'Reload';
    A.PreferredSize(w, withAction);
    AssertEquals('a 2px-padded action fits beside the line', bare, withAction);
    AssertEquals('and the width is still the host''s', 0, w);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestPreferredHeightGrowsForATallAction;
var
  A: TAlertAccess;
  w, bare, tall: Integer;
begin
  // 20px above and below the caption: the action is a line + 40, the bare banner a line + 16.
  FCtl.LoadThemeCss(cBarCss + 'TyAlertAction { color: #111111; padding: 20px 8px; font-size: 12px; }');
  A := NewActionAlert(FForm, FCtl, []);
  try
    A.PreferredSize(w, bare);
    A.Actions.Add.Caption := 'Reload';
    A.PreferredSize(w, tall);
    AssertEquals('the banner grows to the action', bare + 24, tall);
    A.Height := tall;
    AssertEquals('which is then drawn whole', tall, RectH(A.ActionRect(0)));
    A.Actions[0].Visible := False;
    A.PreferredSize(w, tall);
    AssertEquals('hidden, it asks for nothing', bare, tall);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestHintComesFromTheActionUnderThePointer;
var
  A: TAlertAccess;
  p0, p1: TPoint;
  r: TRect;
begin
  FCtl.LoadThemeCss(cActCss);
  A := NewActionAlert(FForm, FCtl, []);
  try
    A.Hint := 'bar';
    AssertEquals('no actions: the banner''s hint', 'bar', A.HintAt(60, 20, r));
    AssertTrue('for the whole banner', SameRect(A.ClientRect, r));
    A.Actions.Add.Caption := 'Reload';
    A.Actions.Add.Caption := 'Keep Mine';
    p0 := A.ActionCentre(0);
    AssertEquals('actions without hints: still the banner''s', 'bar', A.HintAt(p0.X, p0.Y, r));
    AssertTrue('and still for the whole banner', SameRect(A.ClientRect, r));
    A.Actions[0].Hint := 'Read the file again';
    p0 := A.ActionCentre(0);
    p1 := A.ActionCentre(1);
    AssertEquals('over an action with a hint', 'Read the file again', A.HintAt(p0.X, p0.Y, r));
    AssertTrue('until the pointer leaves it', SameRect(A.ActionRect(0), r));
    AssertEquals('over one without: the banner''s', 'bar', A.HintAt(p1.X, p1.Y, r));
    AssertTrue('until the pointer leaves that one', SameRect(A.ActionRect(1), r));
    AssertEquals('below it', 'bar', A.HintAt(p0.X, A.Height - 1, r));
    AssertTrue(PtInRect(r, Point(p0.X, A.Height - 1)));
    AssertFalse('moving up onto it asks again', PtInRect(r, p0));
    AssertEquals('beside the row: the banner''s', 'bar', A.HintAt(60, 20, r));
    AssertTrue('for where the pointer is', PtInRect(r, Point(60, 20)));
    AssertFalse('but reaching an action asks again', PtInRect(r, p0) or PtInRect(r, p1));
    // A hidden action between two others answers for nothing: the pointer on the third
    // gets the third's hint, not the hidden one's.
    A.Actions[1].Hint := 'hidden';
    A.Actions.Add.Caption := 'Merge';
    A.Actions[2].Hint := 'Merge both';
    A.Actions[1].Visible := False;
    p1 := A.ActionCentre(2);
    AssertEquals('past a hidden action', 'Merge both', A.HintAt(p1.X, p1.Y, r));
    AssertTrue(SameRect(A.ActionRect(2), r));
    A.Actions[1].Visible := True;
    A.Actions[1].Hint := '';
    A.Actions.Delete(2);
    p0 := A.ActionCentre(0);
    p1 := A.ActionCentre(1);
    // Above an action is not on it either.
    AssertEquals('bar', A.HintAt(p0.X, 0, r));
    AssertTrue(PtInRect(r, Point(p0.X, 0)));
    AssertFalse('moving down onto it asks again', PtInRect(r, p0));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestSubclassCanTakeOverTheAction;
var
  A: TAlertSub;
begin
  FCtl.LoadThemeCss(cActCss);
  A := TAlertSub.Create(FForm);
  try
    SetUpActionAlert(A, FForm, FCtl, ['Reload']);
    A.OnAction := @HandleAction;
    A.ClickAction(0);
    AssertEquals('the click goes through DoAction', 1, A.Taken);
    AssertEquals('which fires the event', 1, FActed);
    A.SwallowAction := True;
    A.ClickAction(0);
    AssertEquals(2, A.Taken);
    AssertEquals('unless the subclass keeps it', 1, FActed);
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestSubclassCanMeasureAndDrawTheAction;
var
  A: TAlertSub;
  R: TBGRABitmap;
begin
  FCtl.LoadThemeCss(cBlankBarCss + 'TyAlertAction { color: #10B981; padding: 2px 8px; font-size: 12px; }');
  A := TAlertSub.Create(FForm);
  try
    SetUpActionAlert(A, FForm, FCtl, ['Reload', 'Keep Mine']);
    // The width of what an action shows is the subclass's to say; the padding is added to it.
    A.ContentW := 100;
    AssertEquals('content + 8px on each side', 116, RectW(A.ActionRect(0)));
    A.ContentW := 60;
    AssertEquals(76, RectW(A.ActionRect(1)));
    // Every action that has a rect is drawn through DrawAction, with that rect.
    A.Drawn := 0;
    R := RenderToBGRA(A, 400, 40);
    try
      AssertEquals('one call per action', 2, A.Drawn);
      AssertTrue('first rect', SameRect(A.ActionRect(0), A.DrawnRects[0]));
      AssertTrue('second rect', SameRect(A.ActionRect(1), A.DrawnRects[1]));
      AssertTrue('setup: the built-in drawing inked it', HasGreenInk(R, A.ActionRect(0)));
    finally
      R.Free;
    end;
    A.Actions[0].Visible := False;
    A.SkipDraw := True;
    A.Drawn := 0;
    R := RenderToBGRA(A, 400, 40);
    try
      AssertEquals('a hidden action is not drawn', 1, A.Drawn);
      AssertSame('the visible one is, as itself', A.Actions[1], A.DrawnActions[0]);
      AssertTrue('in its own rect', SameRect(A.ActionRect(1), A.DrawnRects[0]));
      AssertFalse('and a subclass that draws nothing leaves nothing', HasGreenInk(R, A.ActionRect(1)));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestDrawActionIsHandedWhatTheActionInherits;
var
  A: TAlertSub;
  R: TBGRABitmap;
begin
  // The style DrawAction gets is the one the caption is written with: where the key is
  // silent it carries the banner's ink and font, and says so in Present, so an override
  // can read it like any resolved style.
  FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px;' +
    ' font-family: Courier New; font-size: 13px; font-weight: 700; }' +
    'TyAlertAction { padding: 2px 8px; }');
  A := TAlertSub.Create(FForm);
  try
    SetUpActionAlert(A, FForm, FCtl, ['Reload']);
    R := RenderToBGRA(A, 400, 40);
    R.Free;
    AssertEquals('setup: drawn', 1, A.Drawn);
    AssertTrue('ink: the banner''s', A.LastStyle.TextColor = TyRGBA($10, $B9, $81, 255));
    AssertTrue('ink is marked present', tpTextColor in A.LastStyle.Present);
    AssertEquals('font: the banner''s family', 'Courier New', A.LastStyle.FontName);
    AssertTrue('family is marked present', tpFontName in A.LastStyle.Present);
    AssertEquals('the banner''s size', 13, A.LastStyle.FontSize);
    AssertTrue('size is marked present', tpFontSize in A.LastStyle.Present);
    AssertEquals('the banner''s weight', 700, TyFontWeightOf(A.LastStyle.FontWeight));
    AssertTrue('weight is marked present', tpFontWeight in A.LastStyle.Present);
    // A banner that names no family or weight hands none on.
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px; font-size: 13px; }' +
      'TyAlertAction { padding: 2px 8px; }');
    R := RenderToBGRA(A, 400, 40);
    R.Free;
    AssertFalse('no family to inherit, none claimed', tpFontName in A.LastStyle.Present);
    AssertFalse('no weight to inherit, none claimed', tpFontWeight in A.LastStyle.Present);
    // And what the key does set is its own.
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px;' +
      ' font-family: Courier New; font-size: 13px; font-weight: 700; }' +
      'TyAlertAction { padding: 2px 8px; color: #EF4444; font-family: Arial; font-size: 11px; font-weight: 400; }');
    R := RenderToBGRA(A, 400, 40);
    R.Free;
    AssertTrue('its own ink', A.LastStyle.TextColor = TyRGBA($EF, $44, $44, 255));
    AssertEquals('its own family', 'Arial', A.LastStyle.FontName);
    AssertEquals('its own size', 11, A.LastStyle.FontSize);
    AssertEquals('its own weight', 400, TyFontWeightOf(A.LastStyle.FontWeight));
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestActionWithoutRoomIsNotDrawn;
var
  A: TAlertSub;
  R: TBGRABitmap;
  i, withRect: Integer;
begin
  FCtl.LoadThemeCss(cActCss);
  A := TAlertSub.Create(FForm);
  try
    SetUpActionAlert(A, FForm, FCtl, ['Reload', 'Merge', 'Keep Mine']);
    A.Width := 110;   // band 12..98: not all three fit
    withRect := 0;
    for i := 0 to 2 do
      if RectW(A.ActionRect(i)) > 0 then Inc(withRect);
    AssertTrue('setup: the first has room', RectW(A.ActionRect(0)) > 0);
    AssertEquals('setup: the last has none', 0, RectW(A.ActionRect(2)));
    A.Drawn := 0;
    R := RenderToBGRA(A, A.Width, A.Height);
    try
      AssertEquals('only the actions that have a rect are drawn', withRect, A.Drawn);
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertActionControlTest.TestEveryBuiltinThemeStylesTheAction;
const
  cModes: array[0..1] of string = ('light', 'dark');
  cTypes: array[0..3] of TTyAlertType = (atInfo, atSuccess, atWarning, atError);
var
  names: TStringArray;
  i, md, t: Integer;
  m: TTyStyleModel;
  rest, hov, act, dis, bar: TTyStyleSet;
  bad, where, v: string;
begin
  // The action is drawn from four things, and a skin that lost one of them shows it as a
  // button that does not answer the pointer, or a disabled one that looks live. Every
  // compiled-in theme, both modes, all four kinds of banner.
  bad := '';
  names := TyBuiltinThemeNames;
  AssertTrue('setup: there are built-in themes', Length(names) > 2);
  for i := 0 to High(names) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss(TyBuiltinThemeCss(names[i]));
      for md := 0 to High(cModes) do
      begin
        m.SetMode(cModes[md]);
        for t := 0 to High(cTypes) do
        begin
          v := TyAlertVariant(cTypes[t]);
          where := names[i] + '/' + cModes[md] + '/' + v + ' ';
          bar := m.ResolveStyle('TyAlert', v, [tysNormal]);
          rest := m.ResolveStyle('TyAlertAction', v, [tysNormal]);
          hov := m.ResolveStyle('TyAlertAction', v, [tysHover]);
          act := m.ResolveStyle('TyAlertAction', v, [tysHover, tysActive]);
          dis := m.ResolveStyle('TyAlertAction', v, [tysDisabled]);
          if not (tpPadding in rest.Present) then bad := bad + where + 'no padding; ';
          // At rest the caption is in its own ink or the banner's; one of them must be there.
          if not ((tpTextColor in rest.Present) or (tpTextColor in bar.Present)) then
            bad := bad + where + 'no ink; ';
          if not (tpBackground in hov.Present) then bad := bad + where + 'no hover chip; ';
          if not (tpBackground in act.Present) then
            bad := bad + where + 'no pressed chip; '
          else if (tpBackground in hov.Present)
            and (act.Background.Color = hov.Background.Color) then
            bad := bad + where + 'pressed looks like hover; ';
          if not (tpTextColor in dis.Present) then
            bad := bad + where + 'no disabled ink; '
          else if (tpTextColor in bar.Present) and (dis.TextColor = bar.TextColor) then
            bad := bad + where + 'disabled looks enabled; ';
        end;
      end;
    finally
      m.Free;
    end;
  end;
  AssertEquals('every built-in theme draws the four looks of an action', '', bad);
end;

initialization
  RegisterTest(TTyAlertLayoutTest);
  RegisterTest(TTyAlertControlTest);
  RegisterTest(TTyAlertActionLayoutTest);
  RegisterTest(TTyAlertActionControlTest);
end.
