unit test.popover;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Popover;

type
  { Pure-rules tests: every function here takes plain integers / enums, so they run with no
    component, no window, no screen and no theme at all. This is the popover's testable
    heart — where it lands, which way it flips, and what its frame holds. }
  TTyPopoverRulesTest = class(TTestCase)
  published
    procedure TestSidePerPlacement;
    procedure TestAlignPerPlacement;
    procedure TestPlacementOfRoundTripsEveryPlacement;
    procedure TestOppositeSideIsItsOwnInverse;
    procedure TestSideIsVertical;
    procedure TestPlaceBelowSitsAtOffsetUnderAnchor;
    procedure TestPlaceCentresOnAnchor;
    procedure TestPlaceStartAndEndAlignTheEdges;
    procedure TestPlaceKeepsPreferredSideWhenItFits;
    procedure TestPlaceFlipsWhenPreferredHasNoRoom;
    procedure TestFlipKeepsTheAlignment;
    procedure TestPlaceKeepsPreferredSideWhenNeitherFits;
    procedure TestPlaceDoesNotClampTheMainAxis;
    procedure TestPlaceClampsCrossAxisIntoWorkArea;
    procedure TestPlaceOnTheRightAndItsFlip;
    procedure TestTipAimsAtAnchorCentre;
    procedure TestTipClampedIntoFrame;
    procedure TestTipLocalIsFrameRelative;
    procedure TestLayoutCarvesTheStripOnTheAnchorSide;
    procedure TestLayoutNoArrowGivesBodyTheWholeFrame;
    procedure TestLayoutArrowBoxStraddlesTheTip;
    procedure TestLayoutClampsTheTipIntoTheFrame;
    procedure TestLayoutTitleTakesTopOfBandContentTheRest;
    procedure TestLayoutNoTitleGivesContentTheWholeBand;
    procedure TestLayoutPaddingEatsBandButNotBody;
    procedure TestLayoutStripEatsWholeFrame;
    procedure TestLayoutZeroSizeEmpty;
    procedure TestFrameSizeRoundTripsVertical;
    procedure TestFrameSizeRoundTripsWithTitle;
    procedure TestFrameSizeRoundTripsHorizontal;
    procedure TestFrameSizeSpendsNoGapWithoutContent;
    procedure TestArrowPointsPerSide;
    procedure TestArrowPointsNoneWithoutArrow;
  end;

  { Headless component behaviour: typeKeys, defaults, theme-driven measurement + placement,
    the content adopt/release contract, the dismissal rules and the paint — all with no
    window on screen (a real Show needs a handle the headless runner has not got; the LOOK
    is a real-machine check). }
  TTyPopoverComponentTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FPanel: TWinControl;   // the "container the designer filled" this popover hosts
    FHidden: Integer;      // OnHide fire count
    procedure HandleHide(Sender: TObject);
    function NewPopover: TTyPopover;   // wired to the test controller + the test panel
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeys;
    procedure TestDefaults;
    procedure TestMeasureWrapsContentInPaddingAndStrip;
    procedure TestMeasureAddsTitleLineAndGap;
    procedure TestMeasureNoArrowDropsTheStrip;
    procedure TestMeasureHorizontalPutsTheStripOnTheWidth;
    procedure TestMeasureWithoutContentIsChromeOnly;
    procedure TestArrowSizeMetricRetunesTheFrame;
    procedure TestTitleGapMetricGrowsTheFrame;
    procedure TestOffsetMetricMovesTheFrame;
    procedure TestGeometryPlacesBelowTarget;
    procedure TestGeometryFlipsNearTheWorkAreaBottom;
    procedure TestGeometryTipAimsAtTheTarget;
    procedure TestAdoptedContentLandsInTheContentRect;
    procedure TestHideReleasesContentExactlyAsItWas;
    procedure TestHideIsIdempotent;
    procedure TestShowWithoutTargetIsInert;
    procedure TestDesignTimeShowIsInert;
    procedure TestFreeingContentTakesThePopoverDown;
    procedure TestFreeingControllerFallsBackToTheDefault;
    procedure TestTitleInkFallsBackToTheBodyInk;
    procedure TestTitleInkUsesItsOwnTypeKey;
    procedure TestBodyRendersThemeBackground;
    procedure TestArrowCarriesTheBodyFillPastItsEdge;
    procedure TestNoArrowLeavesNoStrip;
    procedure TestGradientBodyDrawsNoArrow;
    procedure TestTitleBandFillsItsThemeBackground;
    procedure TestNoThemedBackgroundDrawsNothing;
  end;

implementation

const
  { The content the component tests wrap, and a work area of round numbers so a frame rect is
    checkable by hand. }
  CContentW = 200;
  CContentH = 100;
  CPanelL   = 20;    // where the panel sits on its own form before we borrow it
  CPanelT   = 30;
  CWorkL = 0;
  CWorkT = 0;
  CWorkR = 1920;
  CWorkB = 1040;

  { The themed body. Flat values, so every expected number below is arithmetic and not a font
    measurement (the headless runner's default font measures nothing like a UI font's). }
  CPadL = 12;
  CPadT = 10;
  CPadR = 12;
  CPadB = 10;
  CBody = 'TyPopover { background: #FFFFFF; color: #111111; border-radius: 6px;'
        + ' padding: 10px 12px; font-size: 12px; }';

  { Every one of the popover's metrics, PINNED. They must be spelled out rather than left to
    the built-in fallbacks: theme :root vars ALWAYS merge under a loaded theme, so a shipped
    theme that retunes any of these would silently move every expected number below. Pinning
    them also makes each test assert the WIRING (a themed metric moves the geometry), which is
    the claim that matters — the fallback constants are only what a theme that sets none gets. }
  CRootFmt = ':root { --popover-arrow-size: %dpx; --popover-offset: %dpx;'
           + ' --popover-title-gap: %dpx; }';

{ The test theme. The defaults reproduce the built-in fallbacks, so the hand-computed geometry
  below reads the same as the shipped defaults; a test that retunes one passes it here. }
function ThemeCss(AArrow: Integer = TyPopoverArrowSize; AOffset: Integer = TyPopoverOffset;
  ATitleGap: Integer = TyPopoverTitleGap; const ABody: string = CBody;
  const AExtra: string = ''): string;
begin
  Result := Format(CRootFmt, [AArrow, AOffset, ATitleGap]) + ABody + AExtra;
end;

type
  { Reaches the protected placement / paint / style seams. BeginShowing is everything a real
    Show does EXCEPT putting the window up, which is precisely the part a headless runner
    cannot do — so the whole placement + adoption rule set is drivable from here. }
  TPopAccess = class(TTyPopover)
  public
    function BeginShowing(const AAnchorScreen, AWorkArea: TRect;
      APPI: Integer): TTyPopoverGeometry;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; ASide: TTyPopoverSide;
      ATipLocal, APPI: Integer);
    function TitleInk: TTyColor;
    function PopoverStyle: TTyStyleSet;
  end;

function TPopAccess.BeginShowing(const AAnchorScreen, AWorkArea: TRect;
  APPI: Integer): TTyPopoverGeometry;
begin
  Result := inherited BeginShowing(AAnchorScreen, AWorkArea, APPI);
end;

procedure TPopAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; ASide: TTyPopoverSide;
  ATipLocal, APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, ASide, ATipLocal, APPI);
end;

function TPopAccess.TitleInk: TTyColor;
begin
  Result := inherited TitleInk;
end;

function TPopAccess.PopoverStyle: TTyStyleSet;
begin
  Result := inherited PopoverStyle;
end;

{ ============================== TTyPopoverRulesTest ============================== }

procedure TTyPopoverRulesTest.TestSidePerPlacement;
begin
  // The side is the popup's half of a placement: all three top-ish placements are psvTop.
  AssertTrue('top', TyPopoverSide(ppTop) = psvTop);
  AssertTrue('top-left', TyPopoverSide(ppTopLeft) = psvTop);
  AssertTrue('top-right', TyPopoverSide(ppTopRight) = psvTop);
  AssertTrue('bottom', TyPopoverSide(ppBottom) = psvBottom);
  AssertTrue('bottom-left', TyPopoverSide(ppBottomLeft) = psvBottom);
  AssertTrue('bottom-right', TyPopoverSide(ppBottomRight) = psvBottom);
  AssertTrue('left', TyPopoverSide(ppLeft) = psvLeft);
  AssertTrue('left-top', TyPopoverSide(ppLeftTop) = psvLeft);
  AssertTrue('left-bottom', TyPopoverSide(ppLeftBottom) = psvLeft);
  AssertTrue('right', TyPopoverSide(ppRight) = psvRight);
  AssertTrue('right-top', TyPopoverSide(ppRightTop) = psvRight);
  AssertTrue('right-bottom', TyPopoverSide(ppRightBottom) = psvRight);
end;

procedure TTyPopoverRulesTest.TestAlignPerPlacement;
begin
  // The alignment is the other half: the bare side name means centred, and the compound
  // names say which pair of edges line up.
  AssertTrue('top is centred', TyPopoverAlign(ppTop) = palCenter);
  AssertTrue('bottom is centred', TyPopoverAlign(ppBottom) = palCenter);
  AssertTrue('left is centred', TyPopoverAlign(ppLeft) = palCenter);
  AssertTrue('right is centred', TyPopoverAlign(ppRight) = palCenter);
  AssertTrue('top-left starts', TyPopoverAlign(ppTopLeft) = palStart);
  AssertTrue('bottom-left starts', TyPopoverAlign(ppBottomLeft) = palStart);
  AssertTrue('left-top starts', TyPopoverAlign(ppLeftTop) = palStart);
  AssertTrue('right-top starts', TyPopoverAlign(ppRightTop) = palStart);
  AssertTrue('top-right ends', TyPopoverAlign(ppTopRight) = palEnd);
  AssertTrue('bottom-right ends', TyPopoverAlign(ppBottomRight) = palEnd);
  AssertTrue('left-bottom ends', TyPopoverAlign(ppLeftBottom) = palEnd);
  AssertTrue('right-bottom ends', TyPopoverAlign(ppRightBottom) = palEnd);
end;

procedure TTyPopoverRulesTest.TestPlacementOfRoundTripsEveryPlacement;
var
  p: TTyPopoverPlacement;
begin
  // Splitting a placement and re-composing it must give back the SAME placement, for all
  // twelve — this is what a flip relies on to keep the user's alignment.
  for p := Low(TTyPopoverPlacement) to High(TTyPopoverPlacement) do
    AssertTrue('round-trips ' + IntToStr(Ord(p)),
      TyPopoverPlacementOf(TyPopoverSide(p), TyPopoverAlign(p)) = p);
end;

procedure TTyPopoverRulesTest.TestOppositeSideIsItsOwnInverse;
var
  s: TTyPopoverSide;
begin
  AssertTrue('top <-> bottom', TyPopoverOppositeSide(psvTop) = psvBottom);
  AssertTrue('bottom <-> top', TyPopoverOppositeSide(psvBottom) = psvTop);
  AssertTrue('left <-> right', TyPopoverOppositeSide(psvLeft) = psvRight);
  AssertTrue('right <-> left', TyPopoverOppositeSide(psvRight) = psvLeft);
  // Flipping twice is not flipping: a side that flips must be able to flip back.
  for s := Low(TTyPopoverSide) to High(TTyPopoverSide) do
    AssertTrue('double flip is identity',
      TyPopoverOppositeSide(TyPopoverOppositeSide(s)) = s);
end;

procedure TTyPopoverRulesTest.TestSideIsVertical;
begin
  // Above/below stack along Y (so the strip eats height); beside stacks along X.
  AssertTrue('top is vertical', TyPopoverSideIsVertical(psvTop));
  AssertTrue('bottom is vertical', TyPopoverSideIsVertical(psvBottom));
  AssertFalse('left is not', TyPopoverSideIsVertical(psvLeft));
  AssertFalse('right is not', TyPopoverSideIsVertical(psvRight));
end;

procedure TTyPopoverRulesTest.TestPlaceBelowSitsAtOffsetUnderAnchor;
var
  g: TTyPopoverGeometry;
begin
  // Anchor 100..180 x 100..124, frame 224x128, offset 4: the frame's TOP edge sits the
  // offset below the anchor's bottom — the strip inside it then spans down to the tip.
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottom, 4, 8);
  AssertTrue('below the anchor', g.Side = psvBottom);
  AssertEquals('frame top = anchor bottom + offset', 128, g.Frame.Top);
  AssertEquals('frame bottom', 256, g.Frame.Bottom);
  AssertEquals('frame is the size we asked for', 224, g.Frame.Right - g.Frame.Left);
end;

procedure TTyPopoverRulesTest.TestPlaceCentresOnAnchor;
var
  g: TTyPopoverGeometry;
begin
  // Anchor centre 140, frame 224 wide -> left = 140 - 112.
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottom, 4, 8);
  AssertEquals('centred on the anchor', 28, g.Frame.Left);
  AssertEquals('and therefore ends here', 252, g.Frame.Right);
end;

procedure TTyPopoverRulesTest.TestPlaceStartAndEndAlignTheEdges;
var
  g: TTyPopoverGeometry;
begin
  // A 300-wide anchor, so both alignments have room to be told apart from centring.
  g := TyPopoverPlace(Rect(100, 100, 400, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottomLeft, 4, 8);
  AssertEquals('left-aligned: shared left edge', 100, g.Frame.Left);
  g := TyPopoverPlace(Rect(100, 100, 400, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottomRight, 4, 8);
  AssertEquals('right-aligned: shared right edge', 400, g.Frame.Right);
  g := TyPopoverPlace(Rect(100, 100, 400, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottom, 4, 8);
  AssertEquals('centred is neither', 138, g.Frame.Left);
end;

procedure TTyPopoverRulesTest.TestPlaceKeepsPreferredSideWhenItFits;
var
  g: TTyPopoverGeometry;
begin
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottom, 4, 8);
  AssertFalse('room below: no flip', g.Flipped);
  AssertTrue('side is the one asked for', g.Side = psvBottom);
end;

procedure TTyPopoverRulesTest.TestPlaceFlipsWhenPreferredHasNoRoom;
var
  g: TTyPopoverGeometry;
begin
  // 16px of work area under the anchor, but 1000 above it: the popup must go ABOVE rather
  // than off the bottom — the whole point of the flip, and why a popover never covers the
  // thing it belongs to.
  g := TyPopoverPlace(Rect(100, 1000, 180, 1024), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottom, 4, 8);
  AssertTrue('flipped', g.Flipped);
  AssertTrue('now above the anchor', g.Side = psvTop);
  AssertEquals('frame bottom = anchor top - offset', 996, g.Frame.Bottom);
  AssertEquals('frame top', 868, g.Frame.Top);
end;

procedure TTyPopoverRulesTest.TestFlipKeepsTheAlignment;
var
  g: TTyPopoverGeometry;
begin
  // A ppBottomLeft with no room below is a ppTopLeft — never a ppTop. The flip changes the
  // SIDE and nothing else; the alignment is the user's and survives it.
  g := TyPopoverPlace(Rect(100, 1000, 400, 1024), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottomLeft, 4, 8);
  AssertTrue('flipped to the top', g.Side = psvTop);
  AssertEquals('still left-aligned', 100, g.Frame.Left);
end;

procedure TTyPopoverRulesTest.TestPlaceKeepsPreferredSideWhenNeitherFits;
var
  g: TTyPopoverGeometry;
begin
  // A 200-tall work area cannot hold a 128 frame either side of an anchor in the middle of
  // it. There is no right answer left, so the caller's own request wins rather than a
  // second wrong one.
  g := TyPopoverPlace(Rect(100, 90, 180, 114), 224, 128,
    Rect(0, 0, 1920, 200), ppBottom, 4, 8);
  AssertFalse('no flip: the other side is no better', g.Flipped);
  AssertTrue('kept the requested side', g.Side = psvBottom);
end;

procedure TTyPopoverRulesTest.TestPlaceDoesNotClampTheMainAxis;
var
  g: TTyPopoverGeometry;
begin
  // Deliberate: a popup that slides along its main axis stops reading as belonging to its
  // anchor, and its arrow would point at nothing. The flip is the whole overflow strategy
  // on this axis — when it cannot help, the frame stays glued and overhangs.
  g := TyPopoverPlace(Rect(100, 90, 180, 114), 224, 128,
    Rect(0, 0, 1920, 200), ppBottom, 4, 8);
  AssertEquals('still glued to the anchor edge', 118, g.Frame.Top);
  AssertTrue('and therefore overhangs the work area', g.Frame.Bottom > 200);
end;

procedure TTyPopoverRulesTest.TestPlaceClampsCrossAxisIntoWorkArea;
var
  g: TTyPopoverGeometry;
begin
  // Cross-axis sliding IS right: the popup stays beside its anchor either way.
  // Anchor hard against a 300-wide work area's right edge.
  g := TyPopoverPlace(Rect(280, 100, 300, 124), 224, 128,
    Rect(0, 0, 300, 1040), ppBottom, 4, 8);
  AssertEquals('slid in off the right edge', 76, g.Frame.Left);
  AssertEquals('right edge on the work area', 300, g.Frame.Right);
  // A frame WIDER than the work area hugs the LEFT (reading) edge, not the right.
  g := TyPopoverPlace(Rect(80, 100, 120, 124), 224, 128,
    Rect(0, 0, 200, 1040), ppBottom, 4, 8);
  AssertEquals('oversized frame hugs the left edge', 0, g.Frame.Left);
end;

procedure TTyPopoverRulesTest.TestPlaceOnTheRightAndItsFlip;
var
  g: TTyPopoverGeometry;
begin
  // Beside the anchor: the main axis is X and the strip eats WIDTH, so the fit test is on
  // the frame's width.
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 232, 120,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppRight, 4, 8);
  AssertTrue('to the right', g.Side = psvRight);
  AssertEquals('frame left = anchor right + offset', 184, g.Frame.Left);
  AssertEquals('cross-axis centred on the anchor', 52, g.Frame.Top);
  // No room to the right, plenty to the left -> flip.
  g := TyPopoverPlace(Rect(250, 100, 280, 124), 232, 120,
    Rect(0, 0, 300, 1040), ppRight, 4, 8);
  AssertTrue('flipped', g.Flipped);
  AssertTrue('now to the left', g.Side = psvLeft);
  AssertEquals('frame right = anchor left - offset', 246, g.Frame.Right);
end;

procedure TTyPopoverRulesTest.TestTipAimsAtAnchorCentre;
var
  g: TTyPopoverGeometry;
begin
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottom, 4, 8);
  AssertEquals('tip on the anchor centre', 140, g.TipX);
  AssertEquals('tip on the frame near edge', 128, g.TipY);
  // Beside: the tip is on the frame's LEFT edge, aimed at the anchor's vertical centre.
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 232, 120,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppRight, 4, 8);
  AssertEquals('tip on the frame left edge', 184, g.TipX);
  AssertEquals('tip on the anchor centre', 112, g.TipY);
end;

procedure TTyPopoverRulesTest.TestTipClampedIntoFrame;
var
  g: TTyPopoverGeometry;
begin
  // The frame had to slide right off the anchor's centre (work area 200 wide, anchor at its
  // far left): the tip is clamped so the triangle's base still lands ON the frame, an
  // arrow-size in from its corner. It no longer points at the anchor's middle — a well-formed
  // arrow beats a correct one that spills outside the window.
  g := TyPopoverPlace(Rect(0, 100, 16, 124), 224, 128,
    Rect(0, 0, 200, 1040), ppBottom, 4, 8);
  AssertEquals('frame hugs the work area left', 0, g.Frame.Left);
  AssertEquals('tip clamped an arrow-size in', 8, g.TipX);
end;

procedure TTyPopoverRulesTest.TestTipLocalIsFrameRelative;
var
  g: TTyPopoverGeometry;
begin
  // The one number that crosses from screen space into frame space.
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 224, 128,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppBottom, 4, 8);
  AssertEquals('tipX - frame.Left', 112, TyPopoverTipLocal(g));
  g := TyPopoverPlace(Rect(100, 100, 180, 124), 232, 120,
    Rect(CWorkL, CWorkT, CWorkR, CWorkB), ppRight, 4, 8);
  AssertEquals('beside: tipY - frame.Top', 60, TyPopoverTipLocal(g));
end;

procedure TTyPopoverRulesTest.TestLayoutCarvesTheStripOnTheAnchorSide;
var
  L: TTyPopoverLayout;
begin
  // Below the anchor -> the arrow hangs off the popup's TOP edge, so the strip is carved
  // from the top and the body is everything under it.
  L := TyPopoverLayout(224, 128, psvBottom, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('body starts below the strip', 8, L.BodyRect.Top);
  AssertEquals('body ends at the frame', 128, L.BodyRect.Bottom);
  // Above the anchor -> the strip is at the BOTTOM.
  L := TyPopoverLayout(224, 128, psvTop, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('body starts at the frame', 0, L.BodyRect.Top);
  AssertEquals('body ends above the strip', 120, L.BodyRect.Bottom);
  // Right of the anchor -> the strip is on the popup's LEFT.
  L := TyPopoverLayout(232, 120, psvRight, 60, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('body starts right of the strip', 8, L.BodyRect.Left);
  // Left of the anchor -> the strip is on the popup's RIGHT.
  L := TyPopoverLayout(232, 120, psvLeft, 60, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('body ends before the strip', 224, L.BodyRect.Right);
end;

procedure TTyPopoverRulesTest.TestLayoutNoArrowGivesBodyTheWholeFrame;
var
  L: TTyPopoverLayout;
begin
  L := TyPopoverLayout(224, 128, psvBottom, 112, False, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('no strip carved', 0, L.BodyRect.Top);
  AssertEquals('body is the frame', 128, L.BodyRect.Bottom);
  AssertEquals('and there is no arrow', 0, L.ArrowRect.Right - L.ArrowRect.Left);
end;

procedure TTyPopoverRulesTest.TestLayoutArrowBoxStraddlesTheTip;
var
  L: TTyPopoverLayout;
begin
  // The box is the tip plus/minus a half-base, and it is exactly the strip deep.
  L := TyPopoverLayout(224, 128, psvBottom, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('box left', 104, L.ArrowRect.Left);
  AssertEquals('box right', 120, L.ArrowRect.Right);
  AssertEquals('box top', 0, L.ArrowRect.Top);
  AssertEquals('box is the strip deep', 8, L.ArrowRect.Bottom);
  AssertEquals('apex X', 112, L.ArrowTip.X);
  AssertEquals('apex on the frame edge', 0, L.ArrowTip.Y);
end;

procedure TTyPopoverRulesTest.TestLayoutClampsTheTipIntoTheFrame;
var
  L: TTyPopoverLayout;
begin
  // A tip nearer the corner than a half-base would put the triangle's base off the frame.
  L := TyPopoverLayout(224, 128, psvBottom, 2, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('tip pushed in to an arrow-size', 8, L.ArrowTip.X);
  AssertEquals('box now starts at the frame edge', 0, L.ArrowRect.Left);
  L := TyPopoverLayout(224, 128, psvBottom, 300, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('and pulled in from the far edge', 216, L.ArrowTip.X);
  AssertEquals('box ends at the frame edge', 224, L.ArrowRect.Right);
end;

procedure TTyPopoverRulesTest.TestLayoutTitleTakesTopOfBandContentTheRest;
var
  L: TTyPopoverLayout;
begin
  // Frame 224 x 150 = strip 8 + pad 10 + title 16 + gap 6 + content 100 + pad 10.
  L := TyPopoverLayout(224, 150, psvBottom, 112, True, True, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('title starts at the padded band', 12, L.TitleRect.Left);
  AssertEquals('title top = strip + top padding', 18, L.TitleRect.Top);
  AssertEquals('title is one line tall', 34, L.TitleRect.Bottom);
  AssertEquals('content starts a gap under it', 40, L.ContentRect.Top);
  AssertEquals('content ends at the bottom padding', 140, L.ContentRect.Bottom);
  AssertEquals('content spans the padded band', 200, L.ContentRect.Right - L.ContentRect.Left);
end;

procedure TTyPopoverRulesTest.TestLayoutNoTitleGivesContentTheWholeBand;
var
  L: TTyPopoverLayout;
begin
  L := TyPopoverLayout(224, 128, psvBottom, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('no title band', 0, L.TitleRect.Bottom - L.TitleRect.Top);
  AssertEquals('content takes the band top', 18, L.ContentRect.Top);
  AssertEquals('and its whole height', 100, L.ContentRect.Bottom - L.ContentRect.Top);
end;

procedure TTyPopoverRulesTest.TestLayoutPaddingEatsBandButNotBody;
var
  L: TTyPopoverLayout;
begin
  // 20 wide, padded 12 each side: nothing is left to lay out INSIDE the body — but the body
  // itself is still there and still draws. Empty means "nothing here", never "inverted".
  L := TyPopoverLayout(20, 128, psvBottom, 10, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertTrue('the body survives', L.BodyRect.Right > L.BodyRect.Left);
  AssertEquals('but no content fits', 0, L.ContentRect.Right - L.ContentRect.Left);
  AssertEquals('nor a title', 0, L.TitleRect.Right - L.TitleRect.Left);
end;

procedure TTyPopoverRulesTest.TestLayoutStripEatsWholeFrame;
var
  L: TTyPopoverLayout;
begin
  // A frame shorter than its own arrow strip: there is no popup here at all.
  L := TyPopoverLayout(224, 6, psvBottom, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('no body', 0, L.BodyRect.Bottom - L.BodyRect.Top);
  AssertEquals('no arrow', 0, L.ArrowRect.Right - L.ArrowRect.Left);
  AssertEquals('no content', 0, L.ContentRect.Right - L.ContentRect.Left);
end;

procedure TTyPopoverRulesTest.TestLayoutZeroSizeEmpty;
var
  L: TTyPopoverLayout;
begin
  L := TyPopoverLayout(0, 128, psvBottom, 112, True, True, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('zero width: no body', 0, L.BodyRect.Right - L.BodyRect.Left);
  AssertEquals('zero width: no content', 0, L.ContentRect.Right - L.ContentRect.Left);
  L := TyPopoverLayout(224, 0, psvBottom, 112, True, True, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('zero height: no body', 0, L.BodyRect.Bottom - L.BodyRect.Top);
  AssertEquals('zero height: no content', 0, L.ContentRect.Bottom - L.ContentRect.Top);
end;

procedure TTyPopoverRulesTest.TestFrameSizeRoundTripsVertical;
var
  sz: TSize;
  L: TTyPopoverLayout;
begin
  // The contract: a frame of TyPopoverFrameSize(w, h) holds exactly w x h of content.
  sz := TyPopoverFrameSize(200, 100, psvBottom, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('pad + content + pad', 224, sz.cx);
  AssertEquals('strip + pad + content + pad', 128, sz.cy);
  L := TyPopoverLayout(sz.cx, sz.cy, psvBottom, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('content fits exactly (w)', 200, L.ContentRect.Right - L.ContentRect.Left);
  AssertEquals('content fits exactly (h)', 100, L.ContentRect.Bottom - L.ContentRect.Top);
end;

procedure TTyPopoverRulesTest.TestFrameSizeRoundTripsWithTitle;
var
  sz: TSize;
  L: TTyPopoverLayout;
begin
  sz := TyPopoverFrameSize(200, 100, psvBottom, True, True, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('width is not a function of the title', 224, sz.cx);
  AssertEquals('grew by the title line and its gap', 150, sz.cy);
  L := TyPopoverLayout(sz.cx, sz.cy, psvBottom, 112, True, True, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('content still fits exactly', 100, L.ContentRect.Bottom - L.ContentRect.Top);
  AssertEquals('and the title got its whole line', 16, L.TitleRect.Bottom - L.TitleRect.Top);
end;

procedure TTyPopoverRulesTest.TestFrameSizeRoundTripsHorizontal;
var
  sz: TSize;
  L: TTyPopoverLayout;
begin
  // Beside the anchor the strip is spent on the WIDTH, not the height.
  sz := TyPopoverFrameSize(200, 100, psvRight, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('strip + pad + content + pad', 232, sz.cx);
  AssertEquals('height carries no strip', 120, sz.cy);
  L := TyPopoverLayout(sz.cx, sz.cy, psvRight, 60, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('content fits exactly (w)', 200, L.ContentRect.Right - L.ContentRect.Left);
  AssertEquals('content fits exactly (h)', 100, L.ContentRect.Bottom - L.ContentRect.Top);
  // And with the arrow off, the strip is not spent at all.
  sz := TyPopoverFrameSize(200, 100, psvRight, False, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('no arrow: no strip', 224, sz.cx);
end;

procedure TTyPopoverRulesTest.TestFrameSizeSpendsNoGapWithoutContent;
var
  sz: TSize;
begin
  // The gap exists only BETWEEN the title and the content: with nothing under it, a titled
  // popup must not carry a gap to nowhere. (Mirrors what TyPopoverLayout does.)
  sz := TyPopoverFrameSize(200, 0, psvBottom, True, True, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('strip + pad + title + pad, no gap', 44, sz.cy);
  // Nor does an untitled one carry a title line.
  sz := TyPopoverFrameSize(200, 0, psvBottom, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertEquals('strip + pad + pad', 28, sz.cy);
end;

procedure TTyPopoverRulesTest.TestArrowPointsPerSide;
var
  L: TTyPopoverLayout;
  tip, b1, b2: TPoint;
begin
  // The two base corners are on the strip's INNER edge — the one that meets the body — so
  // the triangle's two slanted sides run from there out to the apex.
  L := TyPopoverLayout(224, 128, psvBottom, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertTrue('has an arrow', TyPopoverArrowPoints(L, psvBottom, tip, b1, b2));
  AssertEquals('apex on the top edge', 0, tip.Y);
  AssertEquals('base is on the body edge', 8, b1.Y);
  AssertEquals('base spans the box (left)', 104, b1.X);
  AssertEquals('base spans the box (right)', 120, b2.X);

  L := TyPopoverLayout(224, 128, psvTop, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertTrue('has an arrow', TyPopoverArrowPoints(L, psvTop, tip, b1, b2));
  AssertEquals('apex on the bottom edge', 128, tip.Y);
  AssertEquals('base is on the body edge', 120, b1.Y);

  L := TyPopoverLayout(232, 120, psvRight, 60, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertTrue('has an arrow', TyPopoverArrowPoints(L, psvRight, tip, b1, b2));
  AssertEquals('apex on the left edge', 0, tip.X);
  AssertEquals('base is on the body edge', 8, b1.X);
  AssertEquals('base spans the box (top)', 52, b1.Y);
  AssertEquals('base spans the box (bottom)', 68, b2.Y);

  L := TyPopoverLayout(232, 120, psvLeft, 60, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertTrue('has an arrow', TyPopoverArrowPoints(L, psvLeft, tip, b1, b2));
  AssertEquals('apex on the right edge', 232, tip.X);
  AssertEquals('base is on the body edge', 224, b1.X);
end;

procedure TTyPopoverRulesTest.TestArrowPointsNoneWithoutArrow;
var
  L: TTyPopoverLayout;
  tip, b1, b2: TPoint;
begin
  L := TyPopoverLayout(224, 128, psvBottom, 112, False, False, 12, 10, 12, 10, 16, 6, 8);
  AssertFalse('no arrow, no points', TyPopoverArrowPoints(L, psvBottom, tip, b1, b2));
  // And nothing to draw when the strip could not be carved at all.
  L := TyPopoverLayout(224, 6, psvBottom, 112, True, False, 12, 10, 12, 10, 16, 6, 8);
  AssertFalse('degenerate frame, no points', TyPopoverArrowPoints(L, psvBottom, tip, b1, b2));
end;

{ ============================ TTyPopoverComponentTest ============================ }

procedure TTyPopoverComponentTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  // The container a designer would have filled with buttons and left hidden on the form.
  FPanel := TWinControl.Create(FForm);
  FPanel.Parent := FForm;
  FPanel.SetBounds(CPanelL, CPanelT, CContentW, CContentH);
  FPanel.Visible := False;
  FHidden := 0;
end;

procedure TTyPopoverComponentTest.TearDown;
begin
  FForm.Free;   // takes the panel with it
  FCtl.Free;
end;

procedure TTyPopoverComponentTest.HandleHide(Sender: TObject);
begin
  Inc(FHidden);
end;

function TTyPopoverComponentTest.NewPopover: TTyPopover;
begin
  Result := TPopAccess.Create(nil);
  Result.Controller := FCtl;
  Result.Content := FPanel;
end;

procedure TTyPopoverComponentTest.TestTypeKeys;
begin
  AssertEquals('TyPopover', TTyPopover.StyleTypeKey);
  AssertEquals('TyPopoverTitle', TTyPopover.TitleStyleTypeKey);
end;

procedure TTyPopoverComponentTest.TestDefaults;
var
  P: TTyPopover;
begin
  P := TTyPopover.Create(nil);
  try
    AssertTrue('drops below its target by default', P.Placement = ppBottom);
    AssertTrue('arrow on by default', P.ShowArrow);
    AssertTrue('a flyout dismisses on a click away', P.CloseOnClickOutside);
    AssertTrue('and on Escape', P.CloseOnEscape);
    AssertEquals('no title', '', P.Title);
    AssertNull('no target', P.Target);
    AssertNull('no content', P.Content);
    AssertFalse('not showing', P.Showing);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestMeasureWrapsContentInPaddingAndStrip;
var
  P: TTyPopover;
  sz: TSize;
begin
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    sz := P.MeasureFrameAtPPI(96);
    AssertEquals('themed padding both sides of the content',
      CPadL + CContentW + CPadR, sz.cx);
    AssertEquals('themed arrow strip + padding + the content',
      TyPopoverArrowSize + CPadT + CContentH + CPadB, sz.cy);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestMeasureAddsTitleLineAndGap;
var
  P: TPopAccess;
  plain, titled: TSize;
begin
  // The title's line is measured in the THEME's font, so it cannot be a literal here — but
  // the DIFFERENCE a title makes must be exactly that line plus the themed gap.
  FCtl.LoadThemeCss(ThemeCss);
  P := TPopAccess(NewPopover);
  try
    plain := P.MeasureFrameAtPPI(96);
    P.Title := 'Confirm';
    titled := P.MeasureFrameAtPPI(96);
    AssertEquals('grew by one measured line + the themed gap',
      plain.cy + P.TitleHeightAt(96) + TyPopoverTitleGap, titled.cy);
    AssertEquals('the width is not a function of the title', plain.cx, titled.cx);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestMeasureNoArrowDropsTheStrip;
var
  P: TTyPopover;
  sz: TSize;
begin
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    P.ShowArrow := False;
    sz := P.MeasureFrameAtPPI(96);
    AssertEquals('no strip in the height', CPadT + CContentH + CPadB, sz.cy);
    AssertEquals('width untouched', CPadL + CContentW + CPadR, sz.cx);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestMeasureHorizontalPutsTheStripOnTheWidth;
var
  P: TTyPopover;
  sz: TSize;
begin
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    P.Placement := ppRight;
    sz := P.MeasureFrameAtPPI(96);
    AssertEquals('the strip is spent on the width',
      TyPopoverArrowSize + CPadL + CContentW + CPadR, sz.cx);
    AssertEquals('and not on the height', CPadT + CContentH + CPadB, sz.cy);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestMeasureWithoutContentIsChromeOnly;
var
  P: TTyPopover;
  sz: TSize;
begin
  // A contentless popover is legal (if pointless) — never a crash, and never a guessed size.
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    P.Content := nil;
    sz := P.MeasureFrameAtPPI(96);
    AssertEquals('just the padding', CPadL + CPadR, sz.cx);
    AssertEquals('just the strip and the padding', TyPopoverArrowSize + CPadT + CPadB, sz.cy);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestArrowSizeMetricRetunesTheFrame;
var
  P: TTyPopover;
  sz: TSize;
begin
  // --popover-arrow-size is a skin-tunable metric: a theme that sets it moves the frame,
  // proving the strip is not baked into the control.
  FCtl.LoadThemeCss(ThemeCss(14));
  P := NewPopover;
  try
    sz := P.MeasureFrameAtPPI(96);
    AssertEquals('the themed strip, not the built-in one',
      14 + CPadT + CContentH + CPadB, sz.cy);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestTitleGapMetricGrowsTheFrame;
var
  P: TPopAccess;
  tight, loose: Integer;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, 6));
  P := TPopAccess(NewPopover);
  try
    P.Title := 'Confirm';
    tight := P.MeasureFrameAtPPI(96).cy;
  finally
    P.Free;
  end;
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, 20));
  P := TPopAccess(NewPopover);
  try
    P.Title := 'Confirm';
    loose := P.MeasureFrameAtPPI(96).cy;
    AssertEquals('exactly the extra themed gap', tight + 14, loose);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestOffsetMetricMovesTheFrame;
var
  P: TTyPopover;
  g: TTyPopoverGeometry;
begin
  // --popover-offset is the gap between the anchor and the frame: a theme that widens it
  // pushes the whole popup away, hit-test/paint and all.
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, 20));
  P := NewPopover;
  try
    g := P.GeometryIn(Rect(100, 100, 180, 124), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    AssertEquals('anchor bottom + the themed offset', 144, g.Frame.Top);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestGeometryPlacesBelowTarget;
var
  P: TTyPopover;
  g: TTyPopoverGeometry;
begin
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    g := P.GeometryIn(Rect(100, 100, 180, 124), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    AssertTrue('below', g.Side = psvBottom);
    AssertFalse('room to spare: no flip', g.Flipped);
    AssertEquals('anchor bottom + offset', 124 + TyPopoverOffset, g.Frame.Top);
    AssertEquals('the measured frame width',
      CPadL + CContentW + CPadR, g.Frame.Right - g.Frame.Left);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestGeometryFlipsNearTheWorkAreaBottom;
var
  P: TTyPopover;
  g: TTyPopoverGeometry;
begin
  // The whole reason the placement is a PREFERENCE: a target near the bottom gets its
  // popover above it rather than off the screen.
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    g := P.GeometryIn(Rect(100, 1000, 180, 1024), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    AssertTrue('flipped', g.Flipped);
    AssertTrue('above the target', g.Side = psvTop);
    AssertEquals('frame bottom = target top - offset', 1000 - TyPopoverOffset, g.Frame.Bottom);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestGeometryTipAimsAtTheTarget;
var
  P: TTyPopover;
  g: TTyPopoverGeometry;
begin
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    g := P.GeometryIn(Rect(100, 100, 180, 124), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    AssertEquals('tip on the target centre', 140, g.TipX);
    AssertEquals('tip on the frame edge nearest the target', g.Frame.Top, g.TipY);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestAdoptedContentLandsInTheContentRect;
var
  P: TPopAccess;
begin
  // The point of the whole component: the app's own container, with its own live controls in
  // it, ends up INSIDE the popup at the frame's content rect — and at its designed size,
  // because the frame was measured from it (the round-trip is what stops it drifting).
  FCtl.LoadThemeCss(ThemeCss);
  P := TPopAccess(NewPopover);
  try
    P.BeginShowing(Rect(100, 100, 180, 124), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    AssertTrue('the popover is up', P.Showing);
    AssertTrue('the container left its own form', FPanel.Parent <> FForm);
    AssertTrue('it is visible in the popup', FPanel.Visible);
    AssertEquals('placed at the band left', CPadL, FPanel.Left);
    AssertEquals('placed under the strip + top padding',
      TyPopoverArrowSize + CPadT, FPanel.Top);
    AssertEquals('at its designed width', CContentW, FPanel.Width);
    AssertEquals('at its designed height', CContentH, FPanel.Height);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestHideReleasesContentExactlyAsItWas;
var
  P: TPopAccess;
begin
  // We only BORROW the container: its parent, bounds and visibility all come back, so the
  // form the designer built is exactly as it was between two Shows.
  FCtl.LoadThemeCss(ThemeCss);
  P := TPopAccess(NewPopover);
  try
    P.BeginShowing(Rect(100, 100, 180, 124), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    P.Hide;
    AssertFalse('down', P.Showing);
    AssertSame('back on its own form', FForm, FPanel.Parent);
    AssertEquals('original left', CPanelL, FPanel.Left);
    AssertEquals('original top', CPanelT, FPanel.Top);
    AssertEquals('original width', CContentW, FPanel.Width);
    AssertEquals('original height', CContentH, FPanel.Height);
    AssertFalse('and hidden again, as it was', FPanel.Visible);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestHideIsIdempotent;
var
  P: TPopAccess;
begin
  FCtl.LoadThemeCss(ThemeCss);
  P := TPopAccess(NewPopover);
  try
    P.OnHide := @HandleHide;
    P.BeginShowing(Rect(100, 100, 180, 124), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    P.Hide;
    AssertEquals('OnHide fired once per dismissal', 1, FHidden);
    P.Hide;
    AssertEquals('a Hide on a hidden popover fires nothing', 1, FHidden);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestShowWithoutTargetIsInert;
var
  P: TTyPopover;
begin
  // A popover is always ABOUT something: with nothing to point at there is nowhere to put it.
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    P.Show;
    AssertFalse('nothing happened', P.Showing);
    AssertSame('and the container never moved', FForm, FPanel.Parent);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestDesignTimeShowIsInert;
var
  P: TTyPopover;
begin
  // A popover is a runtime gesture, not a designer preview: the IDE must never end up with
  // the form's container re-parented into a stray popup window.
  FCtl.LoadThemeCss(ThemeCss);
  P := NewPopover;
  try
    TPopAccess(P).SetDesigning(True, False);   // protected in TComponent; reach it via the access class
    P.ShowAt(Rect(100, 100, 180, 124));
    AssertFalse('inert', P.Showing);
    AssertSame('the container stayed put', FForm, FPanel.Parent);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestFreeingContentTakesThePopoverDown;
var
  P: TPopAccess;
begin
  // The container is being freed out from under a live popup: there is nothing left to show
  // and nothing left to hand back, so the popover goes down rather than dangle.
  FCtl.LoadThemeCss(ThemeCss);
  P := TPopAccess(NewPopover);
  try
    P.BeginShowing(Rect(100, 100, 180, 124), Rect(CWorkL, CWorkT, CWorkR, CWorkB), 96);
    AssertTrue('up', P.Showing);
    FreeAndNil(FPanel);
    AssertNull('the reference is dropped, not dangled', P.Content);
    AssertFalse('and the popup came down', P.Showing);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestFreeingControllerFallsBackToTheDefault;
var
  P: TPopAccess;
  c: TTyStyleController;
begin
  // The ActiveController rule: a popover whose controller went away resolves against the
  // global default rather than dereferencing a freed one.
  c := TTyStyleController.Create(nil);
  P := TPopAccess(NewPopover);
  try
    P.Controller := c;
    AssertSame('wired', c, P.Controller);
    c.Free;
    AssertNull('dropped, not dangled', P.Controller);
    // Still resolvable — via TyDefaultController, which is what ActiveController falls to.
    P.MeasureFrameAtPPI(96);
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestTitleInkFallsBackToTheBodyInk;
var
  P: TPopAccess;
begin
  // NOTE the TyPopoverTitle rule is PRESENT-but-colourless rather than simply omitted: with
  // the property cascade off (the default) the engine applies its built-in base layer to any
  // typeKey the loaded theme leaves untouched, so an omitted rule would resolve the SHIPPED
  // title and this would test the engine, not the control.
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap, CBody,
    'TyPopoverTitle { font-weight: 700; }'));
  P := TPopAccess(NewPopover);
  try
    P.Title := 'Confirm';
    AssertEquals('no title colour -> the popup''s own ink',
      Int64(P.PopoverStyle.TextColor), Int64(P.TitleInk));
  finally
    P.Free;
  end;
end;

procedure TTyPopoverComponentTest.TestTitleInkUsesItsOwnTypeKey;
var
  P: TPopAccess;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap, CBody,
    'TyPopoverTitle { color: #10B981; }'));
  P := TPopAccess(NewPopover);
  try
    P.Title := 'Confirm';
    AssertTrue('the title takes TyPopoverTitle''s colour, not the body''s',
      P.TitleInk <> P.PopoverStyle.TextColor);
    AssertEquals('and it is the one the theme named', Int64(TyRGB($10, $B9, $81)),
      Int64(P.TitleInk));
  finally
    P.Free;
  end;
end;

{ TestBodyRendersThemeBackground
  Theme: a strongly blue TyPopover fill. Probe the body's centre and assert it is the themed
  fill — i.e. the popup paints from the token, not from an LCL colour. }
procedure TTyPopoverComponentTest.TestBodyRendersThemeBackground;
var
  P: TPopAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap,
    'TyPopover { background: #3B82F6; color: #FFFFFF; border-radius: 6px;'
    + ' padding: 10px 12px; font-size: 12px; }'));
  Bmp := TBitmap.Create;
  P := TPopAccess(NewPopover);
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(224, 128);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, 224, 128);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 224, 128), psvBottom, 112, 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(112, 64);   // well inside the body, clear of its rounded corners
      AssertTrue('body painted in the themed fill',
        (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    P.Free;
    Bmp.Free;
  end;
end;

{ TestArrowCarriesTheBodyFillPastItsEdge
  The arrow is the body carried out past its own edge, so it must be the body's colour — and
  only WHERE the triangle is: the rest of the strip stays untouched, which is what makes the
  window's shaped silhouette read as a wedge rather than a bar. }
procedure TTyPopoverComponentTest.TestArrowCarriesTheBodyFillPastItsEdge;
var
  P: TPopAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap,
    'TyPopover { background: #3B82F6; color: #FFFFFF; border-radius: 6px;'
    + ' padding: 10px 12px; font-size: 12px; }'));
  Bmp := TBitmap.Create;
  P := TPopAccess(NewPopover);
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(224, 128);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, 224, 128);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 224, 128), psvBottom, 112, 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // Apex (112,0), base (104,8)..(120,8): at y=4 the wedge spans x 108..116.
      Px := Reread.GetPixel(112, 4);
      AssertTrue('the wedge is the body fill', (Px.blue > 180) and (Px.red < 120));
      // Same strip, far from the wedge: nothing drawn, so the canvas shows through.
      Px := Reread.GetPixel(20, 3);
      AssertTrue('the rest of the strip is untouched',
        (Px.red > 200) and (Px.green < 60) and (Px.blue < 60));
    finally
      Reread.Free;
    end;
  finally
    P.Free;
    Bmp.Free;
  end;
end;

{ TestNoArrowLeavesNoStrip
  ShowArrow off: the body IS the frame, so the pixels the strip would have occupied are body. }
procedure TTyPopoverComponentTest.TestNoArrowLeavesNoStrip;
var
  P: TPopAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap,
    'TyPopover { background: #3B82F6; color: #FFFFFF; border-radius: 0px;'
    + ' padding: 10px 12px; font-size: 12px; }'));
  Bmp := TBitmap.Create;
  P := TPopAccess(NewPopover);
  try
    P.ShowArrow := False;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(224, 128);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, 224, 128);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 224, 128), psvBottom, 112, 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(20, 3);   // where the strip WOULD be
      AssertTrue('the body reaches the frame edge', (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    P.Free;
    Bmp.Free;
  end;
end;

{ TestGradientBodyDrawsNoArrow
  Graceful degradation: the arrow is the body's SOLID fill carried out past its edge, so a
  gradient body has no one colour to carry — and this library never invents one. The strip is
  still reserved (nothing shifts); the popup simply reads as a floating card. }
procedure TTyPopoverComponentTest.TestGradientBodyDrawsNoArrow;
var
  P: TPopAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap,
    'TyPopover { background: linear-gradient(90deg, #3B82F6, #1D4ED8); color: #FFFFFF;'
    + ' border-radius: 0px; padding: 10px 12px; font-size: 12px; }'));
  Bmp := TBitmap.Create;
  P := TPopAccess(NewPopover);
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(224, 128);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, 224, 128);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 224, 128), psvBottom, 112, 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(112, 64);
      AssertTrue('the gradient body still paints', (Px.blue > 140) and (Px.red < 120));
      Px := Reread.GetPixel(112, 3);   // dead centre of where the wedge would be
      AssertTrue('but no wedge was invented in the strip',
        (Px.red > 200) and (Px.green < 60) and (Px.blue < 60));
    finally
      Reread.Free;
    end;
  finally
    P.Free;
    Bmp.Free;
  end;
end;

{ TestTitleBandFillsItsThemeBackground
  TyPopoverTitle sets its own background: the header strip must take THAT fill (not the
  body's), proving the band resolves from its own typeKey. }
procedure TTyPopoverComponentTest.TestTitleBandFillsItsThemeBackground;
var
  P: TPopAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  L: TTyPopoverLayout;
  h: Integer;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap, CBody,
    'TyPopoverTitle { background: #10B981; color: #FFFFFF; }'));
  Bmp := TBitmap.Create;
  P := TPopAccess(NewPopover);
  try
    P.Title := 'Confirm';
    h := P.MeasureFrameAtPPI(96).cy;
    L := P.LayoutIn(224, h, psvBottom, 112, 96);
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(224, h);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, 224, h);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 224, h), psvBottom, 112, 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // The band's left edge, clear of the headline's glyphs.
      Px := Reread.GetPixel(L.TitleRect.Right - 2,
        (L.TitleRect.Top + L.TitleRect.Bottom) div 2);
      AssertTrue('the band is the TyPopoverTitle fill',
        (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30));
    finally
      Reread.Free;
    end;
  finally
    P.Free;
    Bmp.Free;
  end;
end;

{ TestNoThemedBackgroundDrawsNothing
  A theme whose TyPopover rule declares no background gets NO popup — not a hard-coded one.
  NOTE the rule must be PRESENT-but-backgroundless rather than simply omitted: with the
  property cascade off (the default) the engine applies its built-in base layer to any typeKey
  the loaded theme leaves untouched, so an omitted rule would resolve the SHIPPED body and this
  would test the engine, not the control. }
procedure TTyPopoverComponentTest.TestNoThemedBackgroundDrawsNothing;
var
  P: TPopAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(ThemeCss(TyPopoverArrowSize, TyPopoverOffset, TyPopoverTitleGap,
    'TyPopover { color: #111111; padding: 10px 12px; font-size: 12px; }'));
  Bmp := TBitmap.Create;
  P := TPopAccess(NewPopover);
  try
    P.Title := 'Confirm';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(224, 150);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(0, 0, 224, 150);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 224, 150), psvBottom, 112, 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // Not the body, not the arrow, not the title: nothing at all.
      Px := Reread.GetPixel(112, 75);
      AssertTrue('nothing painted in the middle',
        (Px.red > 200) and (Px.green < 60) and (Px.blue < 60));
      Px := Reread.GetPixel(112, 4);
      AssertTrue('nor a wedge in the strip',
        (Px.red > 200) and (Px.green < 60) and (Px.blue < 60));
    finally
      Reread.Free;
    end;
  finally
    P.Free;
    Bmp.Free;
  end;
end;

initialization
  RegisterTest(TTyPopoverRulesTest);
  RegisterTest(TTyPopoverComponentTest);
end.
