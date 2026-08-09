unit test.form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, Menus, StdCtrls, LCLType, LMessages,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Form,
  tyControls.Base, tyControls.Menu, tyControls.ThemeRegistry, tyControls.BuiltinThemes,
  { ac2363: the control half of the same per-monitor DPI report -- see
    TControlDpiRoundTripTest. StdCtrls is here for the plain LCL TButton that rides in the
    same form as the control group. }
  tyControls.Button, tyControls.CheckBox, tyControls.TyLabel, tyControls.ToggleSwitch,
  tyControls.ButtonGroup, tyControls.Edit,
  tyControls.WindowEffects;   // TyLastWindowEffect/TyWindowEffectApplies apply-pipe seam

type
  TFormHelpersTest = class(TTestCase)
  published
    procedure TestCenterIsNone;
    procedure TestLeftEdge;
    procedure TestRightEdge;
    procedure TestTopEdge;
    procedure TestBottomEdge;
    procedure TestTopLeftCorner;
    procedure TestTopRightCorner;
    procedure TestBottomLeftCorner;
    procedure TestBottomRightCorner;
    procedure TestZeroZoneIsNone;
    procedure TestMaximizedBoundsEqualsWorkArea;
  end;

  { Pure resize gating: TyResizeHitFor returns bhNone for every point when not
    AResizable, and is identical to TyHitTestBorder when AResizable. }
  TResizeHitForTest = class(TTestCase)
  published
    procedure TestNotResizableEdgeIsNone;
    procedure TestNotResizableCornerIsNone;
    procedure TestNotResizableInteriorIsNone;
    procedure TestResizableMatchesHitTestLeftEdge;
    procedure TestResizableMatchesHitTestRightEdge;
    procedure TestResizableMatchesHitTestTopEdge;
    procedure TestResizableMatchesHitTestBottomEdge;
    procedure TestResizableMatchesHitTestTopLeftCorner;
    procedure TestResizableMatchesHitTestBottomRightCorner;
    procedure TestResizableMatchesHitTestInterior;
  end;

  { Pure Linux resize-gutter math: TyResizeGutterRect insets AClient by AZone on each
    side only when (ANeedsGutter and AResizable and not AMaximized); else unchanged. }
  TResizeGutterTest = class(TTestCase)
  published
    procedure TestInsetsWhenAllConditionsMet;
    procedure TestUnchangedWhenNotResizable;
    procedure TestUnchangedWhenMaximized;
    procedure TestUnchangedWhenNoGutter;
    procedure TestTinyClientClampsNonNegativeExtent;
  end;

  { Pure Windows NC hit-test mapper (TyNcHitTest): window-relative point -> HT* code.
    Edge zones (within AZone of an edge) -> HTLEFT..HTBOTTOMRIGHT; the caption band
    (y < ACaptionH, not on an edge) -> HTCAPTION; interior -> HTCLIENT; and when not
    resizable, NO edge codes ever (HTCAPTION/HTCLIENT only). Coords are device px
    (PPI-independent). Compiled + tested on every platform (the mapper is pure). }
  TNcHitTestTest = class(TTestCase)
  published
    procedure TestLeftEdgeIsHtLeft;
    procedure TestRightEdgeIsHtRight;
    procedure TestTopEdgeIsHtTop;
    procedure TestBottomEdgeIsHtBottom;
    procedure TestTopLeftCornerIsHtTopLeft;
    procedure TestTopRightCornerIsHtTopRight;
    procedure TestBottomLeftCornerIsHtBottomLeft;
    procedure TestBottomRightCornerIsHtBottomRight;
    procedure TestCaptionBandIsHtCaption;
    procedure TestInteriorIsHtClient;
    procedure TestBelowCaptionIsHtClient;
    procedure TestTopEdgeWinsOverCaption;
    procedure TestNotResizableEdgeIsHtClient;
    procedure TestNotResizableCornerIsHtClient;
    procedure TestNotResizableCaptionStillHtCaption;
    procedure TestNotResizableInteriorIsHtClient;
    procedure TestZeroCaptionNeverCaption;
  end;

  { Pure NC hit-test composition (TyResolveNcHit): DefWindowProc's answer + the mapper.
    The OS keeps the sizing frame it still owns (HTLEFT..HTBOTTOMRIGHT); everything else it
    reports is remapped by TyNcHitTest — including the phantom caption / sysmenu / min / max /
    close band it infers from the WS_CAPTION the window only carries to get Aero Snap. A
    maximized (or fixed) window keeps no frame codes at all and hit-tests caption/client only. }
  TNcHitResolveTest = class(TTestCase)
  published
    procedure TestKeepsOsSizingFrame;
    procedure TestKeepsOsCorner;
    procedure TestPhantomCloseBecomesCaption;
    procedure TestPhantomMinButtonBelowCaptionBecomesClient;
    procedure TestPhantomCaptionBelowBandBecomesClient;
    procedure TestClientTopStripBecomesTopResize;
    procedure TestMaximizedDropsOsEdgeCode;
    procedure TestMaximizedTopBandStaysCaption;
    procedure TestNotResizableDropsOsEdgeCode;
  end;

  { Where a maximized window lands when a title-bar drag tears it loose (TyRestoreDragBounds):
    the saved SIZE, positioned so the pointer keeps its proportional grip along the title bar. }
  TRestoreDragBoundsTest = class(TTestCase)
  published
    procedure TestKeepsNormalSize;
    procedure TestCentreGripStaysCentred;
    procedure TestLeftGripStaysNearLeftEdge;
    procedure TestRightGripStaysNearRightEdge;
    procedure TestTopMatchesMaximizedTop;
    procedure TestDegenerateSavedRectFallsBackToHalf;
    procedure TestCursorOutsideClampsInside;
  end;

  { Pure mapping from a border-resize hit zone to the native resize cursor.
    bhNone -> crDefault; left/right -> crSizeWE; top/bottom -> crSizeNS;
    topLeft/bottomRight -> crSizeNWSE; topRight/bottomLeft -> crSizeNESW. }
  TResizeCursorTest = class(TTestCase)
  published
    procedure TestNoneIsDefault;
    procedure TestLeftIsSizeWE;
    procedure TestRightIsSizeWE;
    procedure TestTopIsSizeNS;
    procedure TestBottomIsSizeNS;
    procedure TestTopLeftIsSizeNWSE;
    procedure TestBottomRightIsSizeNWSE;
    procedure TestTopRightIsSizeNESW;
    procedure TestBottomLeftIsSizeNESW;
  end;

  TCaptionButtonTest = class(TTestCase)
  published
    procedure TestCloseVariantAndGlyph;
    procedure TestMinVariantAndGlyph;
    procedure TestMaxVariantAndGlyph;
    procedure TestRestoreVariantAndGlyph;
    procedure TestTypeKey;
  end;

  TTitleBarTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestCaptionProperty;
    procedure TestDefaultAlignIsTop;
    procedure TestHasThreeButtons;
    procedure TestButtonKinds;
    procedure TestButtonsRightAlignedAfterResize;
    procedure TestRightInsetHonorsHiddenButtons;
    procedure TestAdjustClientRectLeavesMiddleStrip;
    procedure TestLayoutPacksRemainingVisibleButton;
    procedure TestButtonWidthFollowsThemeMetric;
    procedure TestExplicitButtonWidthOverridesMetric;
    procedure TestClassicCaptionButtonsGapped;
    procedure TestDefaultCaptionButtonsFlush;
    procedure TestCloseButtonSyncsCloseVariant;
  end;

  TCaptionButtonPaintTest = class(TTestCase)
  published
    procedure TestPaintSmoke;
  end;

  TTitleBarPaintTest = class(TTestCase)
  published
    procedure TestPaintSmoke;
  end;

  { ===== a6256: the cross-monitor DPI contract for the title bar ==============
    Forum report (Antek, PerMonitorV2 manifest, real hardware): dragging a window
    from a 100% monitor to a 250% one made TyTitleBar "far too tall", and dragging
    back left the layout "broken FOREVER".

    Root cause: TTyChromeEngine.HandleChangeBounds used to do

      FTitleBar.Height := TyRescaleChromeMetric(FTitleBar.Height, FInstalled, ACur)

    -- it multiplied the CURRENT height. That composes with LCL's own DPI pass
    (TControl.DoAutoAdjustLayout scales the same alTop child), so one crossing
    scaled twice; and `X := round(X*a)` is not invertible, so it never came back.

    These tests pin the cure: the height is DERIVED from PPI-independent inputs,
    which makes it (a) idempotent -- applying it twice at the same PPI cannot grow
    it -- and (b) exactly reversible across a 96 -> 240 -> 96 round trip. They are
    written against the accumulating helper too, so that if anyone re-introduces
    the multiply-the-running-value shape the difference is visible in one file. }
  TTitleBarDpiTest = class(TTestCase)
  published
    procedure TestDeviceHeightScalesWithPPI;
    procedure TestDeviceHeightIsIdempotent;
    procedure TestDeviceHeightRoundTripsExactly;
    procedure TestPinnedTitleHeightRoundTripsExactly;
    procedure TestAccumulatingRescaleSquares;
    procedure TestExplicitButtonWidthRoundTripsExactly;
    procedure TestLclScalingAfterTheEngineDoesNotDoubleTheBar;
  end;

  { ===== ac2363: the CONTROL half of the same per-monitor DPI report ==========
    a6256 fixed the chrome (the title bar was multiplying an already-scaled height).
    The controls had the same shape one layer down, and it is what the tester meant
    by "layout broken FOREVER": a control that writes a DEVICE-px Constraints floor
    recomputed that floor from the new Font.PixelsPerInch (LCL's ScaleFontsPPI runs
    first, control.inc:4224, and the font change reaches Invalidate) WHILE LCL was
    independently scaling the very same Constraints (control.inc:3232). One crossing,
    two applications.

    Measured on this harness before the fix, 96 -> 240 -> 96:

      TButton  (plain LCL)  26 ->  65 ->  26   exact       <- the control group
      TTyEdit               26 ->  65 ->  26   exact
      TTyButton             29 -> 175 ->  70   *** stuck ***
      TTyLabel              26 -> 100 ->  40   *** stuck ***
      TTyCheckBox           26 -> 150 ->  60   *** stuck ***
      TTyToggleSwitch      120 -> 488 -> 195 -> 219 (w)     *** and COMPOUNDING ***

    The plain LCL button and TTyEdit are IN THE SAME FORM on purpose: they are the
    control group that makes "this is ours, not LCL's" answerable in one run, and
    TTyToggleSwitch is the reason the trip count is three -- its width kept climbing
    on trips a single there-and-back never reached.

    These run headless. The plan for this work said verification could not be
    (citing memory/headless-tests-never-run-lcl-align), and that is true of the
    ALIGN engine but not of this: AutoAdjustLayout is a direct recursion over
    Controls[], it never asks the align engine for anything, and the whole defect
    reproduces without a handle. Confirmed identical with a shown window. }
  TControlDpiRoundTripTest = class(TTestCase)
  private
    { False = leave the LCL default ParentFont = True; see Build and
      TestRoundTripsWithTheLclDefaultParentFontToo. }
    FPinOwnFont: Boolean;
    { >= 0: shrink every control to its own floor plus this many logical px, which is what
      makes most of these tests edge probes. < 0: leave the designed bounds alone. }
    FTighten: Integer;
    FForm: TTyForm;
    FCtl: TTyStyleController;
    FCtls: array of TControl;
    FNames: array of string;
    FStart: array of TRect;
    procedure Track(const AName: string; ACtl: TControl);
    procedure Build(APPI: Integer = 96);
    procedure SitOnFloor(ASlackPx: Integer);
    procedure Cross(APPI: Integer);
    procedure SnapStart;
    function BoundsOf(AIndex: Integer): TRect;
    procedure AssertThreeTripsAreExact;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPlainLclControlRoundTripsExactly;
    procedure TestEveryControlRoundTripsExactlyOverThreeTrips;
    procedure TestRoundTripsWithTheLclDefaultParentFontToo;
    procedure TestFloorScalesWithPPI;
    procedure TestSingleCrossingDoesNotSquareTheFactor;
    procedure TestCrossingIsIdempotentAtOnePPI;
    procedure TestFloorAfterCrossingEqualsFloorBornAtThatPPI;
  end;

  TRescaleMetricTest = class(TTestCase)
  published
    procedure TestScaleUp;
    procedure TestScaleDown;
    procedure TestIdentity;
    procedure TestRoundsHalfUp;
  end;

  TCaptionButtonHoverGlyphTest = class(TTestCase)
  published
    procedure TestGlyphRenderedByDefault;
    procedure TestNoGlyphWhenHoverOnlyAndNotHovered;
    procedure TestGlyphRenderedWhenHoverOnlyAndHovered;
  end;

  TTyFormTest = class(TTestCase)
  published
    procedure TestBorderlessFromBirth;
    procedure TestStartsWithNoTitleBar;
    procedure TestCreatingTitleBarAutoAssigns;
    procedure TestFreeingTitleBarNilsProperty;
    procedure TestApplyChromeThemeSetsColorFromToken;
    procedure TestApplyChromeThemePropagatesController;
    procedure TestControllerPropertyThemesAndPropagates;
    procedure TestFreeingControllerNilsProperty;
    procedure TestTitleBarDragArmsViaEngine;
    procedure TestTitleBarTopZoneDoesNotArmDrag;
    procedure TestDblClickMaximizeToggles;
    procedure TestResizableDefaultsTrue;
    procedure TestResizableRoundTrips;
    procedure TestResizableEdgePressStartsResize;
    procedure TestNonResizableEdgePressDoesNotStartResize;
    procedure TestNonResizableDisablesMaxButton;
    procedure TestNonResizableGatesMaximize;
  end;

  { Bugs #2 + #3 — the maximized window's chrome.
      #2 the window manager can maximize the window itself (Aero Snap to the top edge, Win+Up,
         the taskbar menu). The widgetset reports it through Resizing(), and the chrome must
         adopt that state or the window is "maximized but not restorable".
      #3 a maximized window must still be draggable: the drag tears it loose (restores it under
         the pointer) and continues, which is what every native title bar does. }
  TMaximizedChromeTest = class(TTestCase)
  published
    procedure TestMaximizedPressArmsDrag;
    procedure TestMaximizedDragRestoresUnderPointer;
    procedure TestMaximizedClickBelowThresholdKeepsMaximized;
    procedure TestNativeMaximizeAdoptedByChrome;
    procedure TestNativeRestoreClearsMaximized;
    procedure TestMinimizeKeepsMaximizedState;
    procedure TestEngineMaximizeSurvivesRestoredReport;
    procedure TestNativeMaximizeRestoresThroughWindowState;
    procedure TestDesigningIgnoresWindowStateReport;
  end;

  { FIX #1: the photo backdrop must (re)build on theme-apply WITHOUT a paint cycle.
    Loads the green image-bg theme, gives the form a client size, calls RebuildBackdrop
    directly (no WM_PAINT), and asserts FSharpBackdrop exists at the client size. Also
    checks that a non-image theme leaves no stale backdrop. This is the core of FIX #1:
    a WS_CLIPCHILDREN form tiled by children never gets a WM_PAINT, so the old in-Paint-
    only snapshot left the photo missing until a min/restore. }
  TTyFormBackdropTest = class(TTestCase)
  private
    function GreenThemePath: string;
  published
    procedure TestRebuildBackdropBuildsWithoutPaint;
    procedure TestRebuildBackdropMatchesClientSize;
    procedure TestNonImageThemeHasNoBackdrop;
  end;

  { Verifies Task 6: TTyForm.MenuBar association + the non-mac shortcut dispatch
    path. On a non-DARWIN target the menu bar OWNS shortcut dispatch — the form's
    IsShortcut override forwards the key message to FMenuBar.Menu.IsShortCut, which
    matches it against the menu's items and fires the matching item's OnClick.

    NOTE (verified Win32 deviation): TMenu.IsShortcut derives the modifier set via
    KeyDataToShiftState -> MsgKeyDataToShiftState, which on Win32 reads Ctrl/Shift/
    Meta from the LIVE keyboard (GetKeyState) and ONLY reads ssAlt from KeyData
    (MK_ALT). A headless test cannot force Ctrl through KeyData, so this test uses an
    Alt-modified shortcut (deterministic via KeyData) to exercise the SAME dispatch
    path the plan's Ctrl+S sketch intends. FFired is set by the item's OnClick. }
  TTyMenuFormTest = class(TTestCase)
  private
    FFired: Boolean;
    procedure ItemClick(Sender: TObject);
  published
    procedure TestPrimaryMenuBarDispatchesShortcut;
    procedure TestMenuBarAssociationAndFreeNotification;
    procedure TestNoMenuBarLeavesShortcutToInherited;
  end;

  { Pure caption-button resolution: close<=biSystemMenu, min<=biMinimize,
    max<=(biMaximize and Resizable). }
  TCaptionButtonsTest = class(TTestCase)
  published
    procedure TestAllIconsResizable;
    procedure TestMaximizeNeedsResizable;
    procedure TestEmptyIconsNoButtons;
    procedure TestCloseOnly;
    procedure TestMinCloseNoMaxIcon;
  end;

  { A standalone TitleBar (no owning form): the three Show* switches toggle the
    matching caption button Visible. }
  TTitleBarSwitchesTest = class(TTestCase)
  published
    procedure TestDefaultsAllVisible;
    procedure TestHideMinimize;
    procedure TestHideMaximize;
    procedure TestHideClose;
  end;

  { TTyForm is always bsNone: assigning any other border style is coerced back. }
  TFormBorderStyleTest = class(TTestCase)
  published
    procedure TestDefaultIsNone;
    procedure TestAssignSizeableCoercedToNone;
  end;

  { An associated form drives its bar's buttons from BorderIcons + Resizable.
    Design-mode is used so SetTitleBar does not arm the runtime chrome engine. }
  TFormDrivesBarTest = class(TTestCase)
  private
    function MakeFormWithBar: TTyForm;
  published
    procedure TestBorderIconsHideMinimize;
    procedure TestCloseOnly;
    procedure TestResizableFalseHidesMaximize;
    procedure TestEmptyBorderIconsHidesAllRuntime;
  end;

  { A title bar belonging to another form cannot be associated. }
  TTitleBarGuardTest = class(TTestCase)
  published
    procedure TestForeignBarRaises;
    procedure TestOwnBarSucceeds;
  end;

  { Window-shade (roll-up): CaptionAction routes caption double-click; ToggleRollUp collapses
    the form to its title bar height and restores it. }
  TRollUpTest = class(TTestCase)
  published
    procedure TestDefaultCaptionActionIsMaximize;
    procedure TestRollUpCollapsesToTitleBar;
    procedure TestRollUpRestoresFullHeight;
    procedure TestDblClickRollsUpWhenModeSet;
    procedure TestNoOpWithoutTitleBar;
  end;

  { TTyForm.StyleOverride (runtime per-window chrome override) + the window-effects apply pipe.
    Two seams under pin:
    - CurrentStyle / ResolveChromeStyle: the override merges OVER the resolved TyForm style via
      the ONE shared parser+merge (TTyStyleModel.ResolveOverride + TyMergeStyleSet), leaving
      unmentioned theme properties intact and re-binding var(--x) on a theme switch.
    - TyApplyWindowEffects' TyLastWindowEffect seam: window-shadow / border-radius — from the
      THEME and from a runtime StyleOverride assignment — reach the platform apply layer, at
      first apply, on a live flip, and across an engine maximize/restore. This is the headless
      guard for forum bug #14 ("window-shadow: false is ignored"): before the fix the value
      died between resolve and DWM; the resolve-level tests alone stayed green. }
  TFormStyleOverrideTest = class(TTestCase)
  published
    procedure TestOverrideWinsOverThemeAndKeepsUnmentioned;
    procedure TestThemeShadowOffReachesApplyPipe;
    procedure TestOverrideFlipsShadowLiveThroughApplyPipe;
    procedure TestOverrideRadiusZeroReachesApplyPipe;
    procedure TestOverrideWithoutControllerStillFlipsShadow;
    procedure TestOverrideSurvivesMaximizeRestore;
    procedure TestOverrideVarRebindsOnThemeSwitch;
  end;

implementation

const
  { ac2363: logical px of headroom TControlDpiRoundTripTest leaves above each control's own
    floor. Small enough that a DOUBLE-scaled floor (~6.25x at 240, against a box of 2.5x)
    still overflows the box -- that is what makes the class an edge probe, and a mutant
    proved it necessary. Large enough to absorb the measurement's own non-linearity in PPI.
    See TControlDpiRoundTripTest.Build. }
  TySlack = 4;

type
  { ac2363: ParentFont is PROTECTED on TControl (published only from TWinControl down), and
    TControlDpiRoundTripTest holds its controls as plain TControl so that a plain LCL
    TButton can ride in the same array as the control group. A descendant declared here
    reaches the protected member. }
  TParentFontAccess = class(TControl);

  TCaptionButtonAccess = class(TTyCaptionButton)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SetHover(AValue: Boolean);
  end;

  TTitleBarAccess = class(TTyTitleBar)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { Expose protected mouse entry points for headless injection. }
    procedure InjectMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure InjectDblClick;
    procedure CallAdjustClientRect(var ARect: TRect);
    procedure CallLayoutButtons;
  end;

  TTyFormAccess = class(TTyForm)
  public
    function TB: TTyTitleBar;
    function MakeTitleBar: TTyTitleBar;
    function EngineDragging: Boolean;
    function EngineMaximized: Boolean;
    function EngineResizing: Boolean;
    procedure SetEngineMaximized(AValue: Boolean);
    { The chrome engine itself, so a test can drive the cursor-parameterised drag entry points
      (TitleBarDragBegin/Update) with synthetic screen points — Mouse.CursorPos, which the LCL
      mouse handlers feed them, is whatever the real pointer happens to be doing. }
    function Engine: TTyChromeEngine;
    { Replay what the widgetset reports after an OS-driven size change (LM_SIZE ->
      TScrollingWinControl.WMSize -> Resizing), which is how Aero Snap reaches the chrome. }
    procedure InjectResizing(AState: TWindowState);
    { Drive the form's own (protected) mouse entry points headlessly — exactly the path
      the widgetset uses — so the engine's resize gating can be exercised without a handle. }
    procedure InjectFormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure InjectFormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    { Build a TLMKey for AKey + AShift and run it through the form's IsShortcut
      override exactly as the widgetset would, returning whether it was consumed.
      ssAlt is encoded into KeyData (MK_ALT) so the match is deterministic headless. }
    function TestIsShortCut(AKey: Word; AShift: TShiftState): Boolean;
    { Drive the (protected) offscreen backdrop build directly, and read the resulting
      snapshot — to prove FIX #1: an image theme builds FSharpBackdrop with NO paint cycle. }
    procedure CallRebuildBackdrop;
    function SharpBackdrop: TBGRABitmap;
  end;

procedure TCaptionButtonAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TCaptionButtonAccess.SetHover(AValue: Boolean);
begin
  FHover := AValue;
end;

procedure TTitleBarAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTitleBarAccess.InjectMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(Button, Shift, X, Y);
end;

procedure TTitleBarAccess.InjectDblClick;
begin
  DblClick;
end;

procedure TTitleBarAccess.CallAdjustClientRect(var ARect: TRect);
begin AdjustClientRect(ARect); end;

procedure TTitleBarAccess.CallLayoutButtons;
begin LayoutButtons; end;

function TTyFormAccess.TB: TTyTitleBar; begin Result := TitleBar; end;

{ Creating a TTyTitleBar owned by the form triggers auto-assign via Notification. }
function TTyFormAccess.MakeTitleBar: TTyTitleBar;
begin Result := TTyTitleBar.Create(Self); end;

function TTyFormAccess.EngineDragging: Boolean; begin Result := FEngine.Dragging; end;
function TTyFormAccess.EngineMaximized: Boolean; begin Result := FEngine.Maximized; end;
function TTyFormAccess.EngineResizing: Boolean; begin Result := FEngine.Resizing; end;
procedure TTyFormAccess.SetEngineMaximized(AValue: Boolean); begin FEngine.Maximized := AValue; end;
function TTyFormAccess.Engine: TTyChromeEngine; begin Result := FEngine; end;
procedure TTyFormAccess.InjectResizing(AState: TWindowState); begin Resizing(AState); end;

procedure TTyFormAccess.InjectFormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin MouseDown(Button, Shift, X, Y); end;

procedure TTyFormAccess.InjectFormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin MouseUp(Button, Shift, X, Y); end;

function TTyFormAccess.TestIsShortCut(AKey: Word; AShift: TShiftState): Boolean;
var msg: TLMKey;
begin
  FillChar(msg, SizeOf(msg), 0);
  msg.CharCode := AKey;
  // Encode the modifiers that the Win32 MsgKeyDataToShiftState reads from KeyData.
  // Only ssAlt is KeyData-derived there; Ctrl/Shift/Meta come from GetKeyState and
  // cannot be forced headlessly, so deterministic tests use ssAlt.
  if ssAlt in AShift then msg.KeyData := msg.KeyData or PtrInt(MK_ALT);
  Result := IsShortcut(msg);
end;

procedure TTyFormAccess.CallRebuildBackdrop; begin RebuildBackdrop; end;
function TTyFormAccess.SharpBackdrop: TBGRABitmap;
begin
  // FSharpBackdrop is private; read it through the public ITyGlassHost accessor the form
  // implements (GlassSharpBackdrop returns FSharpBackdrop). Same value child controls sample.
  Result := (Self as ITyGlassHost).GlassSharpBackdrop;
end;

const
  CR: TRect = (Left: 0; Top: 0; Right: 200; Bottom: 100);
  ZONE = 6;

procedure TFormHelpersTest.TestCenterIsNone;
begin
  AssertTrue('center', TyHitTestBorder(CR, Point(100, 50), ZONE) = bhNone);
end;

procedure TFormHelpersTest.TestLeftEdge;
begin
  AssertTrue('left', TyHitTestBorder(CR, Point(2, 50), ZONE) = bhLeft);
end;

procedure TFormHelpersTest.TestRightEdge;
begin
  AssertTrue('right', TyHitTestBorder(CR, Point(198, 50), ZONE) = bhRight);
end;

procedure TFormHelpersTest.TestTopEdge;
begin
  AssertTrue('top', TyHitTestBorder(CR, Point(100, 2), ZONE) = bhTop);
end;

procedure TFormHelpersTest.TestBottomEdge;
begin
  AssertTrue('bottom', TyHitTestBorder(CR, Point(100, 98), ZONE) = bhBottom);
end;

procedure TFormHelpersTest.TestTopLeftCorner;
begin
  AssertTrue('topleft', TyHitTestBorder(CR, Point(2, 2), ZONE) = bhTopLeft);
end;

procedure TFormHelpersTest.TestTopRightCorner;
begin
  AssertTrue('topright', TyHitTestBorder(CR, Point(198, 2), ZONE) = bhTopRight);
end;

procedure TFormHelpersTest.TestBottomLeftCorner;
begin
  AssertTrue('bottomleft', TyHitTestBorder(CR, Point(2, 98), ZONE) = bhBottomLeft);
end;

procedure TFormHelpersTest.TestBottomRightCorner;
begin
  AssertTrue('bottomright', TyHitTestBorder(CR, Point(198, 98), ZONE) = bhBottomRight);
end;

procedure TFormHelpersTest.TestZeroZoneIsNone;
begin
  AssertTrue('zerozone', TyHitTestBorder(CR, Point(0, 0), 0) = bhNone);
end;

procedure TFormHelpersTest.TestMaximizedBoundsEqualsWorkArea;
var
  Wa, R: TRect;
begin
  Wa := Rect(0, 0, 1920, 1040);
  R := TyMaximizedBounds(Wa);
  AssertEquals('left', 0, R.Left);
  AssertEquals('top', 0, R.Top);
  AssertEquals('right', 1920, R.Right);
  AssertEquals('bottom', 1040, R.Bottom);
end;

{ TResizeHitForTest — pure resize gating }

procedure TResizeHitForTest.TestNotResizableEdgeIsNone;
begin
  { A genuine edge point that TyHitTestBorder would flag must be bhNone when not resizable. }
  AssertTrue('left edge gated', TyResizeHitFor(False, CR, Point(2, 50), ZONE) = bhNone);
end;

procedure TResizeHitForTest.TestNotResizableCornerIsNone;
begin
  AssertTrue('corner gated', TyResizeHitFor(False, CR, Point(2, 2), ZONE) = bhNone);
end;

procedure TResizeHitForTest.TestNotResizableInteriorIsNone;
begin
  AssertTrue('interior gated', TyResizeHitFor(False, CR, Point(100, 50), ZONE) = bhNone);
end;

procedure TResizeHitForTest.TestResizableMatchesHitTestLeftEdge;
begin
  AssertTrue('left matches', TyResizeHitFor(True, CR, Point(2, 50), ZONE)
    = TyHitTestBorder(CR, Point(2, 50), ZONE));
end;

procedure TResizeHitForTest.TestResizableMatchesHitTestRightEdge;
begin
  AssertTrue('right matches', TyResizeHitFor(True, CR, Point(198, 50), ZONE)
    = TyHitTestBorder(CR, Point(198, 50), ZONE));
end;

procedure TResizeHitForTest.TestResizableMatchesHitTestTopEdge;
begin
  AssertTrue('top matches', TyResizeHitFor(True, CR, Point(100, 2), ZONE)
    = TyHitTestBorder(CR, Point(100, 2), ZONE));
end;

procedure TResizeHitForTest.TestResizableMatchesHitTestBottomEdge;
begin
  AssertTrue('bottom matches', TyResizeHitFor(True, CR, Point(100, 98), ZONE)
    = TyHitTestBorder(CR, Point(100, 98), ZONE));
end;

procedure TResizeHitForTest.TestResizableMatchesHitTestTopLeftCorner;
begin
  AssertTrue('topleft matches', TyResizeHitFor(True, CR, Point(2, 2), ZONE)
    = TyHitTestBorder(CR, Point(2, 2), ZONE));
end;

procedure TResizeHitForTest.TestResizableMatchesHitTestBottomRightCorner;
begin
  AssertTrue('bottomright matches', TyResizeHitFor(True, CR, Point(198, 98), ZONE)
    = TyHitTestBorder(CR, Point(198, 98), ZONE));
end;

procedure TResizeHitForTest.TestResizableMatchesHitTestInterior;
begin
  { Interior must agree too (both bhNone) — gating only changes the not-resizable case. }
  AssertTrue('interior matches', TyResizeHitFor(True, CR, Point(100, 50), ZONE)
    = TyHitTestBorder(CR, Point(100, 50), ZONE));
end;

{ TResizeGutterTest — pure Linux gutter math }

procedure TResizeGutterTest.TestInsetsWhenAllConditionsMet;
var R: TRect;
begin
  R := TyResizeGutterRect(CR, ZONE, True, False, True);
  AssertEquals('left inset', CR.Left + ZONE, R.Left);
  AssertEquals('top inset', CR.Top + ZONE, R.Top);
  AssertEquals('right inset', CR.Right - ZONE, R.Right);
  AssertEquals('bottom inset', CR.Bottom - ZONE, R.Bottom);
end;

procedure TResizeGutterTest.TestUnchangedWhenNotResizable;
var R: TRect;
begin
  R := TyResizeGutterRect(CR, ZONE, False, False, True);
  AssertTrue('unchanged when not resizable',
    (R.Left = CR.Left) and (R.Top = CR.Top) and (R.Right = CR.Right) and (R.Bottom = CR.Bottom));
end;

procedure TResizeGutterTest.TestUnchangedWhenMaximized;
var R: TRect;
begin
  R := TyResizeGutterRect(CR, ZONE, True, True, True);
  AssertTrue('unchanged when maximized',
    (R.Left = CR.Left) and (R.Top = CR.Top) and (R.Right = CR.Right) and (R.Bottom = CR.Bottom));
end;

procedure TResizeGutterTest.TestUnchangedWhenNoGutter;
var R: TRect;
begin
  { Windows/Cocoa path: NeedsGutter=False -> never inset even when resizable + not maximized. }
  R := TyResizeGutterRect(CR, ZONE, True, False, False);
  AssertTrue('unchanged on no-gutter platform',
    (R.Left = CR.Left) and (R.Top = CR.Top) and (R.Right = CR.Right) and (R.Bottom = CR.Bottom));
end;

procedure TResizeGutterTest.TestTinyClientClampsNonNegativeExtent;
var R, Tiny: TRect;
begin
  { A client smaller than 2*AZone must not invert: far edges clamp to the near ones. }
  Tiny := Rect(0, 0, 4, 4);   // 4 < 2*6 -> would go negative without the clamp
  R := TyResizeGutterRect(Tiny, ZONE, True, False, True);
  AssertTrue('right not < left', R.Right >= R.Left);
  AssertTrue('bottom not < top', R.Bottom >= R.Top);
end;

{ TNcHitTestTest — pure Windows NC hit-test mapper.
  WR is a window rect at the origin (NC hit-test works in window-relative coords);
  CAPH is a caption-band height so y<CAPH (away from an edge) maps to HTCAPTION. }
const
  WR: TRect = (Left: 0; Top: 0; Right: 300; Bottom: 200);
  CAPH = 32;

procedure TNcHitTestTest.TestLeftEdgeIsHtLeft;
begin
  { A point in the left strip, vertically clear of the top/bottom zones, is HTLEFT. }
  AssertEquals(TyHTLEFT, TyNcHitTest(WR, Point(2, 100), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestRightEdgeIsHtRight;
begin
  AssertEquals(TyHTRIGHT, TyNcHitTest(WR, Point(298, 100), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestTopEdgeIsHtTop;
begin
  AssertEquals(TyHTTOP, TyNcHitTest(WR, Point(150, 2), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestBottomEdgeIsHtBottom;
begin
  AssertEquals(TyHTBOTTOM, TyNcHitTest(WR, Point(150, 198), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestTopLeftCornerIsHtTopLeft;
begin
  AssertEquals(TyHTTOPLEFT, TyNcHitTest(WR, Point(2, 2), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestTopRightCornerIsHtTopRight;
begin
  AssertEquals(TyHTTOPRIGHT, TyNcHitTest(WR, Point(298, 2), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestBottomLeftCornerIsHtBottomLeft;
begin
  AssertEquals(TyHTBOTTOMLEFT, TyNcHitTest(WR, Point(2, 198), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestBottomRightCornerIsHtBottomRight;
begin
  AssertEquals(TyHTBOTTOMRIGHT, TyNcHitTest(WR, Point(298, 198), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestCaptionBandIsHtCaption;
begin
  { y < CAPH, x well clear of the left/right edge zones -> the title-bar drag band. }
  AssertEquals(TyHTCAPTION, TyNcHitTest(WR, Point(150, 16), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestInteriorIsHtClient;
begin
  AssertEquals(TyHTCLIENT, TyNcHitTest(WR, Point(150, 100), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestBelowCaptionIsHtClient;
begin
  { Just below the caption band but clear of every edge -> client. }
  AssertEquals(TyHTCLIENT, TyNcHitTest(WR, Point(150, CAPH + 1), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestTopEdgeWinsOverCaption;
begin
  { A point inside BOTH the caption band and the top resize zone must be the resize
    edge (top wins), so the top border stays grabbable on a captioned window. }
  AssertEquals(TyHTTOP, TyNcHitTest(WR, Point(150, 1), ZONE, CAPH, True));
end;

procedure TNcHitTestTest.TestNotResizableEdgeIsHtClient;
begin
  { Not resizable: an edge point must NOT return an edge code. Below the caption band
    (so not HTCAPTION) it is plain HTCLIENT. }
  AssertEquals(TyHTCLIENT, TyNcHitTest(WR, Point(2, 100), ZONE, CAPH, False));
end;

procedure TNcHitTestTest.TestNotResizableCornerIsHtClient;
begin
  { A bottom corner (below the caption band) when not resizable -> HTCLIENT, never a corner code. }
  AssertEquals(TyHTCLIENT, TyNcHitTest(WR, Point(298, 198), ZONE, CAPH, False));
end;

procedure TNcHitTestTest.TestNotResizableCaptionStillHtCaption;
begin
  { Not resizable still allows the caption drag band (a fixed window can be moved). }
  AssertEquals(TyHTCAPTION, TyNcHitTest(WR, Point(150, 16), ZONE, CAPH, False));
end;

procedure TNcHitTestTest.TestNotResizableInteriorIsHtClient;
begin
  AssertEquals(TyHTCLIENT, TyNcHitTest(WR, Point(150, 100), ZONE, CAPH, False));
end;

procedure TNcHitTestTest.TestZeroCaptionNeverCaption;
begin
  { ACaptionH = 0 (no associated title bar): a near-top interior point is HTCLIENT,
    never HTCAPTION — there is no drag band. (The top edge zone still resizes.) }
  AssertEquals(TyHTCLIENT, TyNcHitTest(WR, Point(150, 10), ZONE, 0, True));
end;

{ TNcHitResolveTest — TyResolveNcHit over the same WR/CAPH/ZONE window as above. The first
  argument is what DefWindowProc answered for that point. }

procedure TNcHitResolveTest.TestKeepsOsSizingFrame;
begin
  { The OS owns the left/right/bottom sizing frame (it reaches into the invisible outer resize
    margin), so its answer is passed straight through — even for a point the mapper would call
    plain client. }
  AssertEquals(TyHTLEFT,
    TyResolveNcHit(TyHTLEFT, WR, Point(150, 100), ZONE, CAPH, True, False));
end;

procedure TNcHitResolveTest.TestKeepsOsCorner;
begin
  AssertEquals(TyHTBOTTOMRIGHT,
    TyResolveNcHit(TyHTBOTTOMRIGHT, WR, Point(150, 100), ZONE, CAPH, True, False));
end;

procedure TNcHitResolveTest.TestPhantomCloseBecomesCaption;
begin
  { WS_CAPTION (carried only so the shell grants Aero Snap) makes DefWindowProc report caption
    hot-spots for a caption we never draw — a click there would CLOSE the window. Inside our
    title band the point must come back as an ordinary caption drag instead. }
  AssertEquals(TyHTCAPTION,
    TyResolveNcHit(TyHTCLOSE, WR, Point(280, 16), ZONE, CAPH, True, False));
end;

procedure TNcHitResolveTest.TestPhantomMinButtonBelowCaptionBecomesClient;
begin
  { Same phantom band, but on a form whose title bar is shorter than the OS caption it thinks
    it has (here: none at all, ACaptionH = 0) -> plain client, never a minimize hot-spot. }
  AssertEquals(TyHTCLIENT,
    TyResolveNcHit(TyHTMINBUTTON, WR, Point(240, 20), ZONE, 0, True, False));
end;

procedure TNcHitResolveTest.TestPhantomCaptionBelowBandBecomesClient;
begin
  AssertEquals(TyHTCLIENT,
    TyResolveNcHit(TyHTCAPTION, WR, Point(150, 100), ZONE, CAPH, True, False));
end;

procedure TNcHitResolveTest.TestClientTopStripBecomesTopResize;
begin
  { The flush title bar leaves the top edge inside the CLIENT (the OS says HTCLIENT there),
    so the mapper has to re-add the top resize strip. }
  AssertEquals(TyHTTOP,
    TyResolveNcHit(TyHTCLIENT, WR, Point(150, 1), ZONE, CAPH, True, False));
end;

procedure TNcHitResolveTest.TestMaximizedDropsOsEdgeCode;
begin
  { A maximized window has no sizing border: even if the OS still reports one, the point is
    client (here: well below the caption band). }
  AssertEquals(TyHTCLIENT,
    TyResolveNcHit(TyHTBOTTOM, WR, Point(150, 100), ZONE, CAPH, True, True));
end;

procedure TNcHitResolveTest.TestMaximizedTopBandStaysCaption;
begin
  { The whole title band of a maximized window is caption — including the strip that would be
    the top resize edge when normal. Reporting HTCAPTION there is what makes the OS run its
    "restore under the cursor and keep dragging" loop. }
  AssertEquals(TyHTCAPTION,
    TyResolveNcHit(TyHTCLIENT, WR, Point(150, 1), ZONE, CAPH, True, True));
end;

procedure TNcHitResolveTest.TestNotResizableDropsOsEdgeCode;
begin
  AssertEquals(TyHTCLIENT,
    TyResolveNcHit(TyHTRIGHT, WR, Point(150, 100), ZONE, CAPH, False, False));
end;

{ TRestoreDragBoundsTest }

const
  MAXR: TRect = (Left: 0; Top: 40; Right: 1000; Bottom: 840);   // a "maximized" work-area rect
  NORMR: TRect = (Left: 300; Top: 200; Right: 700; Bottom: 500); // 400 x 300 to restore to

procedure TRestoreDragBoundsTest.TestKeepsNormalSize;
var R: TRect;
begin
  R := TyRestoreDragBounds(MAXR, NORMR, Point(500, 50));
  AssertEquals('width', 400, R.Right - R.Left);
  AssertEquals('height', 300, R.Bottom - R.Top);
end;

procedure TRestoreDragBoundsTest.TestCentreGripStaysCentred;
var R: TRect;
begin
  { Grabbed at the middle of the maximized width -> the restored window hangs from its middle. }
  R := TyRestoreDragBounds(MAXR, NORMR, Point(500, 50));
  AssertEquals('left', 500 - 200, R.Left);
end;

procedure TRestoreDragBoundsTest.TestLeftGripStaysNearLeftEdge;
var R: TRect;
begin
  { 10% in from the left of the maximized window -> 10% in from the left of the restored one
    (40px), NOT centred and NOT left-aligned with the old rect. }
  R := TyRestoreDragBounds(MAXR, NORMR, Point(100, 50));
  AssertEquals('left', 100 - 40, R.Left);
end;

procedure TRestoreDragBoundsTest.TestRightGripStaysNearRightEdge;
var R: TRect;
begin
  R := TyRestoreDragBounds(MAXR, NORMR, Point(900, 50));
  AssertEquals('left', 900 - 360, R.Left);
end;

procedure TRestoreDragBoundsTest.TestTopMatchesMaximizedTop;
var R: TRect;
begin
  { Vertically the pointer keeps its offset from the top edge, so it stays on the title bar. }
  R := TyRestoreDragBounds(MAXR, NORMR, Point(500, 50));
  AssertEquals('top', MAXR.Top, R.Top);
end;

procedure TRestoreDragBoundsTest.TestDegenerateSavedRectFallsBackToHalf;
var R: TRect;
begin
  { Never maximized through the engine (no saved rect): half the maximized window, still under
    the pointer — a zero-size restore would make the window vanish. }
  R := TyRestoreDragBounds(MAXR, Rect(0, 0, 0, 0), Point(500, 50));
  AssertEquals('width', 500, R.Right - R.Left);
  AssertEquals('height', 400, R.Bottom - R.Top);
  AssertTrue('pointer inside', (R.Left <= 500) and (R.Right >= 500));
end;

procedure TRestoreDragBoundsTest.TestCursorOutsideClampsInside;
var R: TRect;
begin
  { A pointer beyond the maximized rect (multi-monitor drag) must still end up ON the restored
    window, not past its edge. }
  R := TyRestoreDragBounds(MAXR, NORMR, Point(1400, 50));
  AssertTrue('pointer not left of the window', R.Left <= 1400);
  AssertTrue('pointer not right of the window', R.Right >= 1400);
end;

{ TResizeCursorTest }

procedure TResizeCursorTest.TestNoneIsDefault;
begin
  AssertEquals(crDefault, TyResizeCursor(bhNone));
end;

procedure TResizeCursorTest.TestLeftIsSizeWE;
begin
  AssertEquals(crSizeWE, TyResizeCursor(bhLeft));
end;

procedure TResizeCursorTest.TestRightIsSizeWE;
begin
  AssertEquals(crSizeWE, TyResizeCursor(bhRight));
end;

procedure TResizeCursorTest.TestTopIsSizeNS;
begin
  AssertEquals(crSizeNS, TyResizeCursor(bhTop));
end;

procedure TResizeCursorTest.TestBottomIsSizeNS;
begin
  AssertEquals(crSizeNS, TyResizeCursor(bhBottom));
end;

procedure TResizeCursorTest.TestTopLeftIsSizeNWSE;
begin
  AssertEquals(crSizeNWSE, TyResizeCursor(bhTopLeft));
end;

procedure TResizeCursorTest.TestBottomRightIsSizeNWSE;
begin
  AssertEquals(crSizeNWSE, TyResizeCursor(bhBottomRight));
end;

procedure TResizeCursorTest.TestTopRightIsSizeNESW;
begin
  AssertEquals(crSizeNESW, TyResizeCursor(bhTopRight));
end;

procedure TResizeCursorTest.TestBottomLeftIsSizeNESW;
begin
  AssertEquals(crSizeNESW, TyResizeCursor(bhBottomLeft));
end;

procedure TCaptionButtonTest.TestCloseVariantAndGlyph;
var
  B: TTyCaptionButton;
begin
  B := TTyCaptionButton.Create(nil);
  try
    B.Kind := cbkClose;
    AssertEquals('variant', 'close', B.KindVariant);
    AssertTrue('glyph', B.KindGlyph = tgClose);
  finally
    B.Free;
  end;
end;

procedure TCaptionButtonTest.TestMinVariantAndGlyph;
var
  B: TTyCaptionButton;
begin
  B := TTyCaptionButton.Create(nil);
  try
    B.Kind := cbkMin;
    AssertEquals('variant', 'min', B.KindVariant);
    AssertTrue('glyph', B.KindGlyph = tgMinimize);
  finally
    B.Free;
  end;
end;

procedure TCaptionButtonTest.TestMaxVariantAndGlyph;
var
  B: TTyCaptionButton;
begin
  B := TTyCaptionButton.Create(nil);
  try
    B.Kind := cbkMax;
    AssertEquals('variant', 'max', B.KindVariant);
    AssertTrue('glyph', B.KindGlyph = tgMaximize);
  finally
    B.Free;
  end;
end;

procedure TCaptionButtonTest.TestRestoreVariantAndGlyph;
var
  B: TTyCaptionButton;
begin
  B := TTyCaptionButton.Create(nil);
  try
    B.Kind := cbkRestore;
    AssertEquals('variant', 'restore', B.KindVariant);
    AssertTrue('glyph', B.KindGlyph = tgRestore);
  finally
    B.Free;
  end;
end;

procedure TCaptionButtonTest.TestTypeKey;
var
  B: TTyCaptionButton;
begin
  B := TTyCaptionButton.Create(nil);
  try
    AssertEquals('typekey', 'TyCaptionButton', B.GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TTitleBarTest.TestTypeKey;
var
  T: TTyTitleBar;
begin
  T := TTyTitleBar.Create(nil);
  try
    AssertEquals('typekey', 'TyTitleBar', T.GetStyleTypeKey);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestCaptionProperty;
var
  T: TTyTitleBar;
begin
  T := TTyTitleBar.Create(nil);
  try
    T.Caption := 'Hello';
    AssertEquals('caption', 'Hello', T.Caption);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestDefaultAlignIsTop;
var
  T: TTyTitleBar;
begin
  { A title bar belongs at the top: the constructor defaults Align to alTop so a freshly
    dropped/created bar snaps to the top strip without manual alignment. }
  T := TTyTitleBar.Create(nil);
  try
    AssertTrue('default Align is alTop', T.Align = alTop);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestHasThreeButtons;
var
  T: TTyTitleBar;
begin
  T := TTyTitleBar.Create(nil);
  try
    AssertTrue('min', T.MinButton <> nil);
    AssertTrue('max', T.MaxButton <> nil);
    AssertTrue('close', T.CloseButton <> nil);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestClassicCaptionButtonsGapped;
{ classic sets --caption-button-margin/-gap, so the caption buttons float inset from the title-bar
  edges with a gap between them (Win9x 3D squares). }
var tb: TTitleBarAccess; c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  tb := TTitleBarAccess.Create(nil); c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'classic';
    tb.Controller := c; tb.SetBounds(0, 0, 200, 34); tb.CallLayoutButtons;
    AssertTrue('caption buttons inset from the top (margin)', tb.CloseButton.Top > 0);
    AssertTrue('close inset from the right edge (margin)',
      tb.CloseButton.Left + tb.CloseButton.Width < tb.ClientWidth);
    AssertTrue('gap between adjacent buttons',
      tb.CloseButton.Left > tb.MaxButton.Left + tb.MaxButton.Width);
  finally tb.Free; c.Free; end;
end;

procedure TTitleBarTest.TestDefaultCaptionButtonsFlush;
{ Themes without the spacing metrics keep the flush look: top-aligned, flush-right, contiguous. }
var tb: TTitleBarAccess; c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  tb := TTitleBarAccess.Create(nil); c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'default';
    tb.Controller := c; tb.SetBounds(0, 0, 200, 34); tb.CallLayoutButtons;
    AssertEquals('flush top', 0, tb.CloseButton.Top);
    AssertEquals('flush right', tb.ClientWidth, tb.CloseButton.Left + tb.CloseButton.Width);
    AssertEquals('contiguous (no gap)', tb.MaxButton.Left + tb.MaxButton.Width, tb.CloseButton.Left);
  finally tb.Free; c.Free; end;
end;

procedure TTitleBarTest.TestCloseButtonSyncsCloseVariant;
{ cbkClose is the enum default (0); setting Kind := cbkClose on a fresh button must STILL sync
  StyleClass to 'close' (else `TyCaptionButton.close {}` rules — XP's red close — never match). }
var b: TTyCaptionButton;
begin
  b := TTyCaptionButton.Create(nil);
  try
    b.Kind := cbkClose;
    AssertEquals('close button StyleClass synced', 'close', b.StyleClass);
  finally b.Free; end;
end;

procedure TTitleBarTest.TestButtonWidthFollowsThemeMetric;
{ A theme's --caption-button-width metric sizes the caption buttons: classic sets 32, default
  has none (falls back to 46). Assert RELATIVELY (headless PPI != 96): classic < default. }
var T: TTyTitleBar; c: TTyStyleController; wDefault, wClassic: Integer;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  T := TTyTitleBar.Create(nil);
  c := TTyStyleController.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    T.Controller := c;
    c.ThemeName := 'default';                 // no metric -> 46 default
    wDefault := T.RightInset;                 // RightInset reads the metric fresh
    c.ThemeName := 'classic';                 // --caption-button-width: 32
    wClassic := T.RightInset;
    AssertTrue('classic caption buttons narrower than default', wClassic < wDefault);
    AssertTrue('classic width still positive', wClassic > 0);
  finally
    T.Free; c.Free;
  end;
end;

procedure TTitleBarTest.TestExplicitButtonWidthOverridesMetric;
{ An explicitly-set ButtonWidth pins the width, overriding the theme metric (per-instance wins). }
var T: TTyTitleBar; c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  T := TTyTitleBar.Create(nil);
  c := TTyStyleController.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    T.Controller := c;
    c.ThemeName := 'classic';                 // width metric would give 28
    T.ButtonWidth := 50;                      // explicit override
    // Check the button's own width (not RightInset — classic's margin metric also adds to that).
    AssertEquals('explicit ButtonWidth wins over the theme width metric', 50, T.CloseButton.Width);
  finally
    T.Free; c.Free;
  end;
end;

procedure TTitleBarTest.TestButtonKinds;
var
  T: TTyTitleBar;
begin
  T := TTyTitleBar.Create(nil);
  try
    AssertTrue('min kind', T.MinButton.Kind = cbkMin);
    AssertTrue('max kind', T.MaxButton.Kind = cbkMax);
    AssertTrue('close kind', T.CloseButton.Kind = cbkClose);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestButtonsRightAlignedAfterResize;
var
  T: TTyTitleBar;
begin
  T := TTyTitleBar.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    AssertEquals('close at right', 300, T.CloseButton.Left + T.CloseButton.Width);
    AssertTrue('max left of close', T.MaxButton.Left < T.CloseButton.Left);
    AssertTrue('min left of max', T.MinButton.Left < T.MaxButton.Left);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestRightInsetHonorsHiddenButtons;
var T: TTyTitleBar;
begin
  T := TTyTitleBar.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    T.MinButton.Visible := False;
    T.MaxButton.Visible := False;   { only close visible -> right inset = 1 button }
    AssertEquals('close still flush right', 300, T.CloseButton.Left + T.CloseButton.Width);
    // RightInset = 1 visible button's EFFECTIVE (device-px) width. Compare to the button's own
    // width, not the logical ButtonWidth property — they differ once DPI-scaled (headless PPI != 96).
    AssertEquals('right inset = one button width', T.CloseButton.Width, T.RightInset);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestAdjustClientRectLeavesMiddleStrip;
var T: TTyTitleBar; R: TRect;
begin
  T := TTyTitleBar.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    R := Rect(0, 0, 300, 32);
    TTitleBarAccess(T).CallAdjustClientRect(R);
    AssertTrue('left inset applied', R.Left > 0);
    AssertTrue('right inset applied', R.Right < 300);
    AssertTrue('strip non-empty', R.Right > R.Left);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestLayoutPacksRemainingVisibleButton;
var T: TTitleBarAccess;
begin
  { Hiding the MIDDLE (max) button must re-pack right-to-left: min slides right to
    abut close, proving LayoutButtons packs only visible buttons (not by slot). }
  T := TTitleBarAccess.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    T.MaxButton.Visible := False;
    T.CallLayoutButtons;
    AssertEquals('close flush right', 300, T.CloseButton.Left + T.CloseButton.Width);
    AssertEquals('min packs into the freed middle slot (abuts close)',
      T.CloseButton.Left, T.MinButton.Left + T.MinButton.Width);
  finally
    T.Free;
  end;
end;

procedure TCaptionButtonPaintTest.TestPaintSmoke;
var
  Acc: TCaptionButtonAccess;
  Bmp: TBitmap;
begin
  Acc := TCaptionButtonAccess.Create(nil);
  try
    Acc.Kind := cbkClose;
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(46, 32);
      Acc.SmokeRender(Bmp.Canvas, Rect(0, 0, 46, 32), 96);
      AssertTrue('caption button RenderTo executed without exception', True);
    finally
      Bmp.Free;
    end;
  finally
    Acc.Free;
  end;
end;

procedure TTitleBarPaintTest.TestPaintSmoke;
var
  Acc: TTitleBarAccess;
  Bmp: TBitmap;
begin
  Acc := TTitleBarAccess.Create(nil);
  try
    Acc.Caption := 'Test';
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(300, 32);
      Acc.SmokeRender(Bmp.Canvas, Rect(0, 0, 300, 32), 96);
      AssertTrue('titlebar RenderTo executed without exception', True);
    finally
      Bmp.Free;
    end;
  finally
    Acc.Free;
  end;
end;

{ TRescaleMetricTest }

{ ===== a6256: TTitleBarDpiTest ============================================== }

procedure TTitleBarDpiTest.TestDeviceHeightScalesWithPPI;
{ The bar must actually follow the monitor: a 250% monitor gets a taller bar. Asserted as a
  RATIO against the 96 answer rather than an absolute, so a density/theme change to
  --titlebar-height cannot make this test lie about what it is checking. }
var f: TTyForm; b: TTyTitleBar; h96, h240: Integer;
begin
  f := TTyForm.CreateNew(nil);
  b := TTyTitleBar.Create(f);
  try
    b.Parent := f;
    f.TitleBar := b;
    h96  := TyTitleBarDeviceHeight(f, b, 96);
    h240 := TyTitleBarDeviceHeight(f, b, 240);
    AssertTrue('a bar height at 96 PPI is positive', h96 > 0);
    AssertEquals('96 -> 240 scales the bar by exactly 240/96',
      MulDiv(h96, 240, 96), h240);
  finally
    f.Free;
  end;
end;

procedure TTitleBarDpiTest.TestDeviceHeightIsIdempotent;
{ THE "far too tall" GUARD. The old code fed the running height back into the rescaler, so
  two passes over one monitor change squared the factor (96->240 twice = 6.25x, not 2.5x).
  A derived height cannot do that: asking for the height at 240 twice gives 240's height. }
var f: TTyForm; b: TTyTitleBar; first, second: Integer;
begin
  f := TTyForm.CreateNew(nil);
  b := TTyTitleBar.Create(f);
  try
    b.Parent := f;
    f.TitleBar := b;
    first := TyTitleBarDeviceHeight(f, b, 240);
    b.Height := first;                      // simulate the first pass having been applied
    second := TyTitleBarDeviceHeight(f, b, 240);
    AssertEquals('asking twice at the same PPI must not grow the bar', first, second);
  finally
    f.Free;
  end;
end;

procedure TTitleBarDpiTest.TestLclScalingAfterTheEngineDoesNotDoubleTheBar;
{ THE ORDERING GUARD, and the reason "sometimes" was in the report.

  a6256 made the height DERIVED, which fixes the case where LCL scales first and the engine
  corrects afterwards. It does not fix the other order. Crossing a monitor can deliver
  ChangeBounds BEFORE WM_DPICHANGED: the engine derives the right height and records the new
  PPI, LCL's own pass then multiplies that already-correct height by the DPI ratio, and the
  next ChangeBounds sees CurPPI = FInstalledPPI and declines to correct anything. The bar
  stays ~2.5x too tall -- until some later crossing happens to arrive in the other order,
  which is why a second run "could not reproduce it".

  So: run LCL's own adjustment pass on a form whose bar is ALREADY correct for the new PPI,
  and require the height to still be the derived one. }
var
  f: TTyForm;
  b: TTyTitleBar;
  want: Integer;
begin
  f := TTyForm.CreateNew(nil);
  b := TTyTitleBar.Create(f);
  try
    b.Parent := f;
    f.TitleBar := b;
    { The engine got there first: the bar is already right for 240. }
    want := TyTitleBarDeviceHeight(f, b, 240);
    b.Height := want;
    { Now LCL's pass runs, multiplying every alTop child by the ratio. Without the
      DoAutoAdjustLayout override this leaves 2.5 * want. }
    f.AutoAdjustLayout(lapAutoAdjustForDPI, 96, 240, f.Width, f.Width);
    AssertEquals('LCL scaled a bar the engine had already sized; the height must be '
      + 're-derived, not multiplied', want, b.Height);
  finally
    f.Free;
  end;
end;

procedure TTitleBarDpiTest.TestDeviceHeightRoundTripsExactly;
{ THE "broken FOREVER" GUARD. Drag out to 250% and back: the bar must be byte-identical to
  where it started. Three crossings each way, because the reported failure was cumulative --
  one trip looked nearly right, repeated trips did not. }
var f: TTyForm; b: TTyTitleBar; start, i: Integer;
begin
  f := TTyForm.CreateNew(nil);
  b := TTyTitleBar.Create(f);
  try
    b.Parent := f;
    f.TitleBar := b;
    start := TyTitleBarDeviceHeight(f, b, 96);
    for i := 1 to 3 do
    begin
      b.Height := TyTitleBarDeviceHeight(f, b, 240);
      b.Height := TyTitleBarDeviceHeight(f, b, 96);
    end;
    AssertEquals('three 96->240->96 round trips leave the bar exactly as it started',
      start, TyTitleBarDeviceHeight(f, b, 96));
    AssertEquals('and the applied height agrees', start, b.Height);
  finally
    f.Free;
  end;
end;

procedure TTitleBarDpiTest.TestPinnedTitleHeightRoundTripsExactly;
{ A host that PINS TitleHeight must get the same treatment: the pin scales with the monitor
  and comes back unchanged, because what is remembered is the PPI-independent value, not the
  running device one.

  Deliberately stated WITHOUT any absolute pixel number. The headless suite does not run at
  96 PPI (TTitleBarTest.TestButtonWidthFollowsThemeMetric says so in as many words), so an
  `expected 40` here would be asserting the test host's DPI, not the library's contract. }
var f: TTyForm; b: TTyTitleBar; i, unpinned, h96, h240: Integer;
begin
  f := TTyForm.CreateNew(nil);
  b := TTyTitleBar.Create(f);
  try
    b.Parent := f;
    f.TitleBar := b;
    unpinned := TyTitleBarDeviceHeight(f, b, 96);
    f.TitleHeight := 200;              // far from any density metric, so "honoured" is unambiguous
    h96 := TyTitleBarDeviceHeight(f, b, 96);
    AssertTrue('an explicit TitleHeight overrides the density metric', h96 <> unpinned);

    h240 := TyTitleBarDeviceHeight(f, b, 240);
    AssertEquals('the pin scales with the monitor, exactly 240/96',
      MulDiv(h96, 240, 96), h240);

    for i := 1 to 3 do
    begin
      b.Height := TyTitleBarDeviceHeight(f, b, 240);
      b.Height := TyTitleBarDeviceHeight(f, b, 96);
    end;
    AssertEquals('a pinned height survives three 96->240->96 round trips unchanged',
      h96, TyTitleBarDeviceHeight(f, b, 96));
    AssertEquals('and the applied height agrees', h96, b.Height);
  finally
    f.Free;
  end;
end;

procedure TTitleBarDpiTest.TestAccumulatingRescaleSquares;
{ Not a test of new code -- a test of WHY the new code has the shape it has, so nobody
  "simplifies" the derived helper back into the accumulating one.

  TyRescaleChromeMetric is still correct AT WHAT IT DOES (convert one value between two
  PPIs) and is still used that way. The defect was that it ran on a value LCL had ALREADY
  scaled, so one monitor crossing applied the factor twice.

  Recorded here because the first guess about this bug was wrong: the suspicion was
  round-trip ROUNDING loss, and there is none -- over 16..120 px against 120/144/240/250
  PPI, three there-and-back trips return the exact starting value for every height. The
  companion assert below pins that, so the real mechanism stays legible. }
var one, two, i, v: Integer;
begin
  { The shape that DOES bite: two applications of one crossing. 96 -> 250 on a 32 px bar. }
  one := TyRescaleChromeMetric(32, 96, 250);
  two := TyRescaleChromeMetric(one, 96, 250);
  AssertEquals('one application scales 32 px by 250/96', 83, one);
  AssertEquals('a SECOND application squares the factor -- the "far too tall" bug', 216, two);
  AssertTrue('so double application is not a rounding nuisance, it is 2.6x too big',
    two > 2 * one);

  { And the thing it was NOT: rounding across a there-and-back trip is exact. }
  v := 32;
  for i := 1 to 3 do
  begin
    v := TyRescaleChromeMetric(v, 96, 250);
    v := TyRescaleChromeMetric(v, 250, 96);
  end;
  AssertEquals('rounding alone round-trips exactly (it was never the defect)', 32, v);
end;

procedure TTitleBarDpiTest.TestExplicitButtonWidthRoundTripsExactly;
{ The caption buttons were the third multiplication in the same chain: HandleChangeBounds
  also rescaled FButtonWidth in place. A pin now carries the PPI it was taken at, so the
  effective width is derived from that pair -- identity at the pinning PPI (which
  TTitleBarTest.TestExplicitButtonWidthOverridesMetric pins) and reversible elsewhere. }
var T: TTyTitleBar; c: TTyStyleController; i: Integer;
begin
  T := TTyTitleBar.Create(nil);
  c := TTyStyleController.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    T.Controller := c;
    T.ButtonWidth := 50;
    AssertEquals('at the PPI it was pinned at, the pin is the identity',
      50, T.CloseButton.Width);
    { Force three more layout passes through public API (ShowMinimize re-lays the cluster).
      Each pass re-derives the effective width; none of them may move the pin. }
    for i := 1 to 3 do
    begin
      T.ShowMinimize := False;
      T.ShowMinimize := True;
    end;
    AssertEquals('re-deriving the width three times does not drift the pin',
      50, T.CloseButton.Width);
    AssertEquals('and the published property still reads back what was set', 50, T.ButtonWidth);
  finally
    T.Free; c.Free;
  end;
end;

procedure TRescaleMetricTest.TestScaleUp;
begin
  AssertEquals('32@96->144 = 48', 48, TyRescaleChromeMetric(32, 96, 144));
end;

procedure TRescaleMetricTest.TestScaleDown;
begin
  AssertEquals('48@144->96 = 32', 32, TyRescaleChromeMetric(48, 144, 96));
end;

procedure TRescaleMetricTest.TestIdentity;
begin
  AssertEquals('40@96->96 = 40', 40, TyRescaleChromeMetric(40, 96, 96));
end;

procedure TRescaleMetricTest.TestRoundsHalfUp;
begin
  { 33 * 144 / 96 = 49.5 → should round to 50
    Formula: (33*144 + 96 div 2) div 96 = (4752 + 48) div 96 = 4800 div 96 = 50 }
  AssertEquals('33@96->144 rounds half-up to 50', 50, TyRescaleChromeMetric(33, 96, 144));
end;

{ TCaptionButtonHoverGlyphTest }

procedure TCaptionButtonHoverGlyphTest.TestGlyphRenderedByDefault;
var
  Ctl: TTyStyleController;
  Btn: TCaptionButtonAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  CX, CY: Integer;
  DarkFound: Boolean;
  X, Y: Integer;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Btn := TCaptionButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCaptionButton { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }');
    Btn.Controller := Ctl;
    Btn.Kind := cbkClose;
    Btn.ShowGlyphOnHoverOnly := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(24, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 24, 24);
    Btn.SmokeRender(Bmp.Canvas, Rect(0, 0, 24, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      { Glyph is centered at 12x12 area (10px). Check 5x5 center for dark px }
      CX := 12;
      CY := 12;
      DarkFound := False;
      for X := CX - 5 to CX + 5 do
        for Y := CY - 5 to CY + 5 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red < 128) or (Px.green < 128) or (Px.blue < 128) then
            DarkFound := True;
        end;
      AssertTrue('Default: glyph strokes should be visible', DarkFound);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Btn.Free;
    Ctl.Free;
  end;
end;

procedure TCaptionButtonHoverGlyphTest.TestNoGlyphWhenHoverOnlyAndNotHovered;
var
  Ctl: TTyStyleController;
  Btn: TCaptionButtonAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  CX, CY: Integer;
  DarkFound: Boolean;
  X, Y: Integer;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Btn := TCaptionButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCaptionButton { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }');
    Btn.Controller := Ctl;
    Btn.Kind := cbkClose;
    Btn.ShowGlyphOnHoverOnly := True;
    Btn.SetHover(False);  { explicitly not hovered }

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(24, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 24, 24);
    Btn.SmokeRender(Bmp.Canvas, Rect(0, 0, 24, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      CX := 12;
      CY := 12;
      DarkFound := False;
      for X := CX - 5 to CX + 5 do
        for Y := CY - 5 to CY + 5 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red < 128) or (Px.green < 128) or (Px.blue < 128) then
            DarkFound := True;
        end;
      AssertFalse('HoverOnly+not hovered: glyph must not appear', DarkFound);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Btn.Free;
    Ctl.Free;
  end;
end;

procedure TCaptionButtonHoverGlyphTest.TestGlyphRenderedWhenHoverOnlyAndHovered;
var
  Ctl: TTyStyleController;
  Btn: TCaptionButtonAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  CX, CY: Integer;
  DarkFound: Boolean;
  X, Y: Integer;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Btn := TCaptionButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCaptionButton { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
      'TyCaptionButton:hover { background: #FFFFFF; color: #000000; border-width: 0px; }');
    Btn.Controller := Ctl;
    Btn.Kind := cbkClose;
    Btn.ShowGlyphOnHoverOnly := True;
    Btn.SetHover(True);  { simulated hover }

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(24, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 24, 24);
    Btn.SmokeRender(Bmp.Canvas, Rect(0, 0, 24, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      CX := 12;
      CY := 12;
      DarkFound := False;
      for X := CX - 5 to CX + 5 do
        for Y := CY - 5 to CY + 5 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red < 128) or (Px.green < 128) or (Px.blue < 128) then
            DarkFound := True;
        end;
      AssertTrue('HoverOnly+hovered: glyph should appear', DarkFound);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Btn.Free;
    Ctl.Free;
  end;
end;

{ TTyFormTest }

procedure TTyFormTest.TestBorderlessFromBirth;
var F: TTyForm;
begin
  F := TTyForm.CreateNew(nil);
  try
    AssertTrue('born bsNone', F.BorderStyle = bsNone);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestStartsWithNoTitleBar;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    AssertTrue('empty by default', F.TitleBar = nil);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestCreatingTitleBarAutoAssigns;
var
  F: TTyFormAccess;
  TB: TTyTitleBar;
begin
  { Creating a title bar owned by the form fires Notification(opInsert), which
    routes through SetTitleBar and auto-assigns it (Menu pattern). The test form is
    NOT csDesigning, so it also wires at runtime. }
  F := TTyFormAccess.CreateNew(nil);
  try
    TB := TTyTitleBar.Create(F);
    AssertTrue('auto-assigned', F.TitleBar = TB);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestFreeingTitleBarNilsProperty;
var
  F: TTyFormAccess;
  TB: TTyTitleBar;
begin
  { Freeing the associated bar fires Notification(opRemove), nilling the property. }
  F := TTyFormAccess.CreateNew(nil);
  try
    TB := TTyTitleBar.Create(F);
    AssertTrue('auto-assigned', F.TitleBar = TB);
    TB.Free;
    AssertTrue('nil after free', F.TitleBar = nil);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestApplyChromeThemeSetsColorFromToken;
var
  F: TTyFormAccess;
  Ctl: TTyStyleController;
begin
  { ApplyChromeTheme must resolve the TyForm token and drive the form Color
    (window backdrop / resize-ring color), not hard-code it. }
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.MakeTitleBar;  { associate a bar so the chrome block runs }
    Ctl.LoadThemeCss('TyForm { background: #123456; }');
    F.ApplyChromeTheme(Ctl);
    AssertEquals('form Color from TyForm token',
      Integer(RGBToColor($12, $34, $56)), Integer(F.Color));
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TTyFormTest.TestApplyChromeThemePropagatesController;
var
  F: TTyFormAccess;
  Ctl: TTyStyleController;
begin
  { ApplyChromeTheme must assign the SAME controller to every chrome
    sub-component, so the whole window chrome themes from one controller. }
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.MakeTitleBar;  { associate a bar so the chrome propagation runs }
    Ctl.LoadThemeCss('TyForm { background: #123456; }');
    F.ApplyChromeTheme(Ctl);
    AssertTrue('titlebar uses the passed controller', F.TB.Controller = Ctl);
    AssertTrue('min button uses the passed controller', F.TB.MinButton.Controller = Ctl);
    AssertTrue('max button uses the passed controller', F.TB.MaxButton.Controller = Ctl);
    AssertTrue('close button uses the passed controller', F.TB.CloseButton.Controller = Ctl);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TTyFormTest.TestControllerPropertyThemesAndPropagates;
var
  F: TTyFormAccess;
  Ctl: TTyStyleController;
begin
  { Assigning the new published Controller property applies the theme (drives the form
    Color) AND propagates the controller to the chrome — i.e. it routes through
    ApplyChromeTheme, so the association is declarative (.lfm / Object Inspector). }
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.MakeTitleBar;
    Ctl.LoadThemeCss('TyForm { background: #123456; }');
    F.Controller := Ctl;
    AssertTrue('Controller property reads back', F.Controller = Ctl);
    AssertEquals('form Color themed from the controller',
      Integer(RGBToColor($12, $34, $56)), Integer(F.Color));
    AssertTrue('titlebar got the controller', F.TB.Controller = Ctl);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TTyFormTest.TestFreeingControllerNilsProperty;
var
  F: TTyFormAccess;
  Ctl: TTyStyleController;
begin
  { Freeing the bound controller fires Notification(opRemove), nilling the property so the
    form never paints through a dangling controller. }
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.Controller := Ctl;
    AssertTrue('bound', F.Controller = Ctl);
    Ctl.Free;
    Ctl := nil;
    AssertTrue('nil after free', F.Controller = nil);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TTyFormTest.TestTitleBarDragArmsViaEngine;
var F: TTyFormAccess;
begin
  { Pressing the title bar arms the engine's window-drag (FForm is the form itself).
    The bar is created owned by the form, so it auto-assigns + wires at runtime. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    { Press BELOW the top resize hot-zone (the top FBorderZone=6 px is now a top-edge
      resize zone, not drag) so this exercises the window-drag path. }
    TTitleBarAccess(F.TitleBar).InjectMouseDown(mbLeft, [], 10, 16);
    AssertTrue('engine drag armed via title bar', F.EngineDragging);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestTitleBarTopZoneDoesNotArmDrag;
var F: TTyFormAccess;
begin
  { A press in the top resize hot-zone (Y < FBorderZone) is a top-edge resize gesture, NOT a
    window drag (the native OS handoff is a no-op headless; the point is the drag path is
    bypassed). Default Resizable=True + not maximized, so the hot-zone is active. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    TTitleBarAccess(F.TitleBar).InjectMouseDown(mbLeft, [], 10, 2);
    AssertFalse('top hot-zone press must not arm a window drag', F.EngineDragging);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestDblClickMaximizeToggles;
var F: TTyFormAccess;
begin
  { Double-clicking the title bar toggles the engine maximize state. Start maximized
    so ToggleMaximize takes the restore branch (no window handle needed headless). }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.SetEngineMaximized(True);
    TTitleBarAccess(F.TitleBar).InjectDblClick;
    AssertFalse('dbl-click toggled maximize off', F.EngineMaximized);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestResizableDefaultsTrue;
var F: TTyForm;
begin
  { The published Resizable defaults True — the borderless window is resizable (the fix). }
  F := TTyForm.CreateNew(nil);
  try
    AssertTrue('Resizable defaults True', F.Resizable);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestResizableRoundTrips;
var F: TTyForm;
begin
  F := TTyForm.CreateNew(nil);
  try
    F.Resizable := False;
    AssertFalse('reads back False', F.Resizable);
    F.Resizable := True;
    AssertTrue('reads back True', F.Resizable);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestResizableEdgePressStartsResize;
var F: TTyFormAccess;
begin
  { Resizable (default): a left-button press in the edge zone. SetBounds gives the form a
    known size so (2,50) lands in the left border zone.
      - Non-Windows: the engine's MANUAL BoundsRect-drag resize arms (FResizing=True).
      - Windows: the manual path is DISABLED (Phase B — native WS_THICKFRAME + WM_NCHITTEST
        own resize), so the engine must NOT arm; the OS drives resize via the NC subclass
        (not observable headlessly). ManualResizeEnabled returns False there. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.SetBounds(0, 0, 200, 100);
    F.InjectFormMouseDown(mbLeft, [], 2, 50);
    {$IFDEF WINDOWS}
    AssertFalse('Windows: manual engine resize disabled (native NC owns it)', F.EngineResizing);
    {$ELSE}
    AssertTrue('edge press started a resize', F.EngineResizing);
    {$ENDIF}
    F.InjectFormMouseUp(mbLeft, [], 2, 50);   // release so nothing lingers
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestNonResizableEdgePressDoesNotStartResize;
var F: TTyFormAccess;
begin
  { Resizable=False: the SAME edge press must NOT start a resize (gating via TyResizeHitFor). }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.SetBounds(0, 0, 200, 100);
    F.Resizable := False;
    F.InjectFormMouseDown(mbLeft, [], 2, 50);
    AssertFalse('edge press gated when not resizable', F.EngineResizing);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestNonResizableDisablesMaxButton;
var F: TTyFormAccess;
begin
  { Setting Resizable=False hides the title-bar max button (a fixed window can't maximize).
    SyncCaptionButtons uses ShowMaximize (Visible), not just Enabled, so the button is hidden. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    AssertTrue('max button visible while resizable', F.TB.MaxButton.Visible);
    F.Resizable := False;
    AssertFalse('max button hidden when not resizable', F.TB.MaxButton.Visible);
    F.Resizable := True;
    AssertTrue('max button visible again when resizable', F.TB.MaxButton.Visible);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestNonResizableGatesMaximize;
var F: TTyFormAccess;
begin
  { Resizable=False gates the double-click-maximize path (engine ToggleMaximize early-exits
    from the not-maximized state). Start NOT maximized; a dbl-click must leave it not maximized. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.Resizable := False;
    AssertFalse('precondition: not maximized', F.EngineMaximized);
    TTitleBarAccess(F.TitleBar).InjectDblClick;
    AssertFalse('maximize gated when not resizable', F.EngineMaximized);
  finally
    F.Free;
  end;
end;

{ TMaximizedChromeTest }

procedure TMaximizedChromeTest.TestMaximizedPressArmsDrag;
var F: TTyFormAccess;
begin
  { Bug #3, first half: a press on a MAXIMIZED title bar must arm the drag. It used to be
    dropped on the floor ("a maximized window has no position"), which is exactly why a
    maximized window could not be dragged at all. Driven through the real mouse entry point so
    the whole bar -> engine wiring is exercised; y=16 clears the top resize hot-zone. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.SetBounds(0, 0, 1000, 800);
    F.SetEngineMaximized(True);
    TTitleBarAccess(F.TitleBar).InjectMouseDown(mbLeft, [], 500, 16);
    AssertTrue('press on a maximized caption must arm the drag', F.EngineDragging);
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestMaximizedDragRestoresUnderPointer;
var F: TTyFormAccess; Expect: TRect;
begin
  { Bug #3, second half: once the pointer actually travels, the window is torn loose — restored
    to its saved SIZE, placed so the pointer keeps its grip on the title bar — and the drag goes
    on from there. Cursor points are passed explicitly (the LCL handlers read Mouse.CursorPos,
    which no headless test can steer). }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.SetBounds(0, 0, 1000, 800);                       // the maximized geometry
    F.Engine.SavedBounds := Rect(120, 90, 520, 390);    // 400 x 300 to restore to
    F.SetEngineMaximized(True);
    F.Engine.TitleBarDragBegin(Point(500, 10));
    AssertTrue('precondition: the press armed the drag', F.EngineDragging);
    F.Engine.TitleBarDragUpdate(Point(560, 30));
    AssertFalse('the drag tore the window loose', F.EngineMaximized);
    Expect := TyRestoreDragBounds(Rect(0, 0, 1000, 800), Rect(120, 90, 520, 390), Point(560, 30));
    AssertEquals('restored width', 400, F.Width);
    AssertEquals('restored height', 300, F.Height);
    AssertEquals('restored left keeps the pointer grip', Expect.Left, F.Left);
    AssertTrue('max button back to the maximize glyph', F.TB.MaxButton.Kind = cbkMax);
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestMaximizedClickBelowThresholdKeepsMaximized;
var F: TTyFormAccess;
begin
  { A click (or the first half of a double-click) on a maximized caption jiggles the pointer by
    a pixel or two. That must NOT restore the window, or double-click-to-restore would fight a
    spurious tear-loose. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.SetBounds(0, 0, 1000, 800);
    F.Engine.SavedBounds := Rect(120, 90, 520, 390);
    F.SetEngineMaximized(True);
    F.Engine.TitleBarDragBegin(Point(500, 10));
    F.Engine.TitleBarDragUpdate(Point(502, 11));
    AssertTrue('still maximized below the drag threshold', F.EngineMaximized);
    AssertEquals('window not moved', 1000, F.Width);
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestNativeMaximizeAdoptedByChrome;
var F: TTyFormAccess;
begin
  { Bug #2: the window manager maximized the window itself (Aero Snap to the top edge, Win+Up,
    the taskbar menu) and the widgetset reports it here. The chrome must adopt that state —
    otherwise the window sits maximized with a "maximize" glyph that maximizes it AGAIN. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    AssertFalse('precondition: not maximized', F.EngineMaximized);
    F.InjectResizing(wsMaximized);
    AssertTrue('chrome adopted the OS maximize', F.EngineMaximized);
    AssertTrue('recorded as the window manager''s', F.Engine.NativeMaximized);
    AssertTrue('caption button shows restore', F.TB.MaxButton.Kind = cbkRestore);
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestNativeRestoreClearsMaximized;
var F: TTyFormAccess;
begin
  { ..and the matching restore (Win+Down, dragging the snapped window off the top edge) must
    put the chrome back. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.InjectResizing(wsMaximized);
    F.InjectResizing(wsNormal);
    AssertFalse('chrome followed the OS restore', F.EngineMaximized);
    AssertFalse('native flag cleared', F.Engine.NativeMaximized);
    AssertTrue('caption button back to maximize', F.TB.MaxButton.Kind = cbkMax);
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestMinimizeKeepsMaximizedState;
var F: TTyFormAccess;
begin
  { Minimizing a maximized window must not make the chrome forget it was maximized: Windows
    brings it back maximized, and a chrome that reset would show rounded corners + a maximize
    glyph on a full-screen window. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.InjectResizing(wsMaximized);
    F.InjectResizing(wsMinimized);
    AssertTrue('still maximized after a minimize', F.EngineMaximized);
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestEngineMaximizeSurvivesRestoredReport;
var F: TTyFormAccess;
begin
  { The engine's OWN maximize is a plain work-area SetBounds, so the widgetset reports every
    resize it causes as "restored". Honouring those reports would cancel the maximize the
    instant it happened — only a maximize the OS itself owns may be cleared this way. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.SetEngineMaximized(True);      // engine (work-area) maximize: not the OS's
    F.InjectResizing(wsNormal);
    AssertTrue('engine maximize not cancelled by a restored report', F.EngineMaximized);
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestNativeMaximizeRestoresThroughWindowState;
var F: TTyFormAccess;
begin
  { The restore button on an OS-maximized window must go back THROUGH the OS (which holds the
    restore rect), not through the engine's saved bounds — those belong to a maximize that
    never happened. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    F.WindowState := wsMaximized;    // as the widgetset would have left it
    F.InjectResizing(wsMaximized);
    AssertTrue('precondition: chrome adopted the OS maximize', F.EngineMaximized);
    F.Engine.ToggleMaximize;         // the caption button / double-click path
    AssertFalse('no longer maximized', F.EngineMaximized);
    AssertFalse('native flag cleared', F.Engine.NativeMaximized);
    AssertEquals('restored through the window state', Ord(wsNormal), Ord(F.WindowState));
  finally
    F.Free;
  end;
end;

procedure TMaximizedChromeTest.TestDesigningIgnoresWindowStateReport;
var F: TTyFormAccess;
begin
  { The designer must never drive the live chrome (it would square the corners of the design
    surface and poke the IDE's window). }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.SetDesigning(True, False);
    F.InjectResizing(wsMaximized);
    AssertFalse('design surface state left alone', F.EngineMaximized);
  finally
    F.Free;
  end;
end;

{ TTyFormBackdropTest }

function TTyFormBackdropTest.GreenThemePath: string;
begin
  // Same repo-relative resolution the golden tests use (test.themes.pas): the exe runs
  // from tests/, so the themes dir is one level up. Loading via the file sets the theme
  // base dir so url(assets/background.jpg) resolves to a real, loadable image.
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + 'green.tycss';
end;

procedure TTyFormBackdropTest.TestRebuildBackdropBuildsWithoutPaint;
var F: TTyFormAccess; Ctl: TTyStyleController;
begin
  if not FileExists(GreenThemePath) then
  begin
    AssertTrue('green.tycss not found — skipping backdrop build test', True);
    Exit;
  end;
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.SetBounds(0, 0, 320, 240);   // a client size to snapshot (no handle / no paint)
    Ctl.ThemeFile := GreenThemePath;
    F.ApplyChromeTheme(Ctl);       // arms FController + FGlassBlurLogical; also calls RebuildBackdrop
    F.CallRebuildBackdrop;         // explicit: prove the snapshot builds with NO WM_PAINT
    AssertTrue('image theme builds FSharpBackdrop without a paint cycle',
      F.SharpBackdrop <> nil);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TTyFormBackdropTest.TestRebuildBackdropMatchesClientSize;
var F: TTyFormAccess; Ctl: TTyStyleController;
begin
  if not FileExists(GreenThemePath) then
  begin
    AssertTrue('green.tycss not found — skipping backdrop size test', True);
    Exit;
  end;
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.SetBounds(0, 0, 320, 240);
    Ctl.ThemeFile := GreenThemePath;
    F.ApplyChromeTheme(Ctl);
    F.CallRebuildBackdrop;
    AssertTrue('backdrop exists', F.SharpBackdrop <> nil);
    AssertEquals('backdrop width = client width', F.ClientWidth, F.SharpBackdrop.Width);
    AssertEquals('backdrop height = client height', F.ClientHeight, F.SharpBackdrop.Height);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TTyFormBackdropTest.TestNonImageThemeHasNoBackdrop;
var F: TTyFormAccess; Ctl: TTyStyleController;
begin
  // A solid (non-image) theme must leave NO backdrop — RebuildBackdrop frees + clears it.
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.SetBounds(0, 0, 320, 240);
    Ctl.LoadThemeCss('TyForm { background: #123456; }');
    F.ApplyChromeTheme(Ctl);
    F.CallRebuildBackdrop;
    AssertTrue('solid theme leaves no photo backdrop', F.SharpBackdrop = nil);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

{ TTyMenuFormTest }

procedure TTyMenuFormTest.ItemClick(Sender: TObject);
begin
  FFired := True;
end;

procedure TTyMenuFormTest.TestPrimaryMenuBarDispatchesShortcut;
var
  frm: TTyFormAccess;
  bar: TTyMenuBar;
  mm: TMainMenu;
  it: TMenuItem;
begin
  FFired := False;
  frm := TTyFormAccess.CreateNew(nil);
  try
    mm := TMainMenu.Create(frm);
    it := TMenuItem.Create(mm);
    it.Caption := 'Save';
    it.ShortCut := ShortCut(Ord('S'), [ssAlt]);   // Alt -> deterministic via KeyData
    it.OnClick := @ItemClick;
    mm.Items.Add(it);
    bar := TTyMenuBar.Create(frm);
    bar.Parent := frm;
    bar.Menu := mm;
    frm.MenuBar := bar;                           // designate the primary menu bar
    AssertTrue('form routes Alt+S to the menu', frm.TestIsShortCut(Ord('S'), [ssAlt]));
    AssertTrue('item OnClick fired', FFired);
  finally
    frm.Free;
  end;
end;

procedure TTyMenuFormTest.TestMenuBarAssociationAndFreeNotification;
var
  frm: TTyFormAccess;
  bar: TTyMenuBar;
begin
  { Assigning MenuBar stores the reference; freeing the bar nils it (FreeNotification). }
  frm := TTyFormAccess.CreateNew(nil);
  try
    bar := TTyMenuBar.Create(frm);
    bar.Parent := frm;
    frm.MenuBar := bar;
    AssertTrue('MenuBar stored', frm.MenuBar = bar);
    bar.Free;
    AssertTrue('MenuBar nilled after the bar is freed', frm.MenuBar = nil);
  finally
    frm.Free;
  end;
end;

procedure TTyMenuFormTest.TestNoMenuBarLeavesShortcutToInherited;
var
  frm: TTyFormAccess;
begin
  { With no MenuBar associated, the override must fall through to inherited and not
    consume the key (no menu => nothing matches). }
  frm := TTyFormAccess.CreateNew(nil);
  try
    AssertFalse('unconsumed with no menu bar', frm.TestIsShortCut(Ord('S'), [ssAlt]));
  finally
    frm.Free;
  end;
end;

{ TFormBorderStyleTest }

procedure TFormBorderStyleTest.TestDefaultIsNone;
var f: TTyForm;
begin
  f := TTyForm.CreateNew(nil);
  try AssertTrue('default bsNone', f.BorderStyle = bsNone);
  finally f.Free; end;
end;

procedure TFormBorderStyleTest.TestAssignSizeableCoercedToNone;
var f: TTyForm;
begin
  f := TTyForm.CreateNew(nil);
  try
    f.BorderStyle := bsSizeable;
    AssertTrue('coerced back to bsNone', f.BorderStyle = bsNone);
  finally f.Free; end;
end;

{ TTitleBarSwitchesTest }

procedure TTitleBarSwitchesTest.TestDefaultsAllVisible;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    AssertTrue('min default', bar.ShowMinimize);
    AssertTrue('max default', bar.ShowMaximize);
    AssertTrue('close default', bar.ShowClose);
  finally bar.Free; end;
end;

procedure TTitleBarSwitchesTest.TestHideMinimize;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    bar.ShowMinimize := False;
    AssertFalse('min hidden', bar.MinButton.Visible);
    AssertTrue('max still', bar.MaxButton.Visible);
  finally bar.Free; end;
end;

procedure TTitleBarSwitchesTest.TestHideMaximize;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    bar.ShowMaximize := False;
    AssertFalse('max hidden', bar.MaxButton.Visible);
  finally bar.Free; end;
end;

procedure TTitleBarSwitchesTest.TestHideClose;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    bar.ShowClose := False;
    AssertFalse('close hidden', bar.CloseButton.Visible);
  finally bar.Free; end;
end;

{ TCaptionButtonsTest }

procedure TCaptionButtonsTest.TestAllIconsResizable;
begin
  AssertTrue('all three when all icons + resizable',
    TyResolveCaptionButtons([biSystemMenu, biMinimize, biMaximize], True)
      = [cbfMinimize, cbfMaximize, cbfClose]);
end;

procedure TCaptionButtonsTest.TestMaximizeNeedsResizable;
begin
  AssertTrue('no max when not resizable, even with biMaximize',
    TyResolveCaptionButtons([biSystemMenu, biMinimize, biMaximize], False)
      = [cbfMinimize, cbfClose]);
end;

procedure TCaptionButtonsTest.TestEmptyIconsNoButtons;
begin
  AssertTrue('empty icons -> no buttons',
    TyResolveCaptionButtons([], True) = []);
end;

procedure TCaptionButtonsTest.TestCloseOnly;
begin
  AssertTrue('systemmenu only -> close only',
    TyResolveCaptionButtons([biSystemMenu], True) = [cbfClose]);
end;

procedure TCaptionButtonsTest.TestMinCloseNoMaxIcon;
begin
  AssertTrue('min+close, no maximize icon -> no max even if resizable',
    TyResolveCaptionButtons([biSystemMenu, biMinimize], True)
      = [cbfMinimize, cbfClose]);
end;

{ TFormDrivesBarTest }

function TFormDrivesBarTest.MakeFormWithBar: TTyForm;
var f: TTyFormAccess;
begin
  f := TTyFormAccess.CreateNew(nil);
  f.SetDesigning(True, False);            // avoid arming the runtime engine (no Monitor/handle)
  TTyTitleBar.Create(f);                  // Owner = the form; auto-assigns via Notification
  Result := f;
end;

procedure TFormDrivesBarTest.TestBorderIconsHideMinimize;
var f: TTyForm;
begin
  f := MakeFormWithBar;
  try
    f.BorderIcons := [biSystemMenu, biMaximize];   // no biMinimize
    AssertFalse('min hidden', f.TitleBar.MinButton.Visible);
    AssertTrue('max shown', f.TitleBar.MaxButton.Visible);
    AssertTrue('close shown', f.TitleBar.CloseButton.Visible);
  finally f.Free; end;
end;

procedure TFormDrivesBarTest.TestCloseOnly;
var f: TTyForm;
begin
  f := MakeFormWithBar;
  try
    f.BorderIcons := [biSystemMenu];
    AssertTrue('close', f.TitleBar.CloseButton.Visible);
    AssertFalse('no min', f.TitleBar.MinButton.Visible);
    AssertFalse('no max', f.TitleBar.MaxButton.Visible);
  finally f.Free; end;
end;

procedure TFormDrivesBarTest.TestResizableFalseHidesMaximize;
var f: TTyForm;
begin
  f := MakeFormWithBar;
  try
    f.BorderIcons := [biSystemMenu, biMinimize, biMaximize];
    f.Resizable := False;
    AssertFalse('max hidden when not resizable', f.TitleBar.MaxButton.Visible);
    AssertTrue('min still', f.TitleBar.MinButton.Visible);
  finally f.Free; end;
end;

procedure TFormDrivesBarTest.TestEmptyBorderIconsHidesAllRuntime;
var f: TTyFormAccess;
begin
  f := TTyFormAccess.CreateNew(nil);   // runtime (NOT designing): exercises the live sync path
  f.MakeTitleBar;
  try
    f.BorderIcons := [];               // must reach the form: a dialog can drop all caption buttons
    AssertFalse('no close', f.TB.CloseButton.Visible);
    AssertFalse('no min', f.TB.MinButton.Visible);
    AssertFalse('no max', f.TB.MaxButton.Visible);
    f.BorderIcons := [biSystemMenu];
    AssertTrue('close restored', f.TB.CloseButton.Visible);
  finally f.Free; end;
end;

procedure TTitleBarGuardTest.TestForeignBarRaises;
var f1, f2: TTyFormAccess; bar: TTyTitleBar; raised: Boolean;
begin
  f1 := TTyFormAccess.CreateNew(nil); f2 := TTyFormAccess.CreateNew(nil);
  f1.SetDesigning(True, False); f2.SetDesigning(True, False);
  bar := TTyTitleBar.Create(f2);   // belongs to f2 (auto-assigns to f2)
  raised := False;
  try
    f1.TitleBar := bar;
  except
    on E: EInvalidOperation do raised := True;
  end;
  try AssertTrue('foreign bar rejected', raised);
  finally f1.Free; f2.Free; end;
end;

procedure TTitleBarGuardTest.TestOwnBarSucceeds;
var f: TTyFormAccess; bar: TTyTitleBar;
begin
  f := TTyFormAccess.CreateNew(nil); f.SetDesigning(True, False);
  bar := TTyTitleBar.Create(f);    // auto-assigns to f
  try
    AssertTrue('own bar associated', f.TitleBar = bar);
  finally f.Free; end;
end;

{ TRollUpTest }

procedure TRollUpTest.TestDefaultCaptionActionIsMaximize;
var f: TTyFormAccess;
begin
  f := TTyFormAccess.CreateNew(nil);
  try
    AssertEquals('default caption action is maximize', Ord(tcaMaximize), Ord(f.CaptionAction));
  finally f.Free; end;
end;

procedure TRollUpTest.TestRollUpCollapsesToTitleBar;
var f: TTyFormAccess; bar: TTyTitleBar;
begin
  f := TTyFormAccess.CreateNew(nil);
  try
    bar := TTyTitleBar.Create(f);   // auto-associates at runtime
    bar.Height := 34;
    f.SetBounds(0, 0, 400, 300);
    f.CaptionAction := tcaRollUp;
    f.ToggleRollUp;
    AssertTrue('rolled up', f.RolledUp);
    AssertEquals('height collapsed to the title bar', f.TitleHeight, f.Height);
  finally f.Free; end;
end;

procedure TRollUpTest.TestRollUpRestoresFullHeight;
var f: TTyFormAccess; bar: TTyTitleBar;
begin
  f := TTyFormAccess.CreateNew(nil);
  try
    bar := TTyTitleBar.Create(f);
    bar.Height := 34;
    f.SetBounds(0, 0, 400, 300);
    f.ToggleRollUp;   // collapse
    f.ToggleRollUp;   // restore
    AssertFalse('no longer rolled', f.RolledUp);
    AssertEquals('full height restored', 300, f.Height);
  finally f.Free; end;
end;

procedure TRollUpTest.TestDblClickRollsUpWhenModeSet;
var f: TTyFormAccess; bar: TTitleBarAccess;
begin
  f := TTyFormAccess.CreateNew(nil);
  try
    bar := TTitleBarAccess.Create(f);   // auto-associates + arms the engine
    bar.Height := 34;
    f.SetBounds(0, 0, 400, 300);
    f.CaptionAction := tcaRollUp;
    bar.InjectDblClick;
    AssertTrue('caption double-click rolled up', f.RolledUp);
    AssertEquals('collapsed to the title bar', f.TitleHeight, f.Height);
  finally f.Free; end;
end;

procedure TRollUpTest.TestNoOpWithoutTitleBar;
var f: TTyFormAccess;
begin
  f := TTyFormAccess.CreateNew(nil);
  try
    f.SetBounds(0, 0, 400, 300);
    f.CaptionAction := tcaRollUp;
    f.ToggleRollUp;   // no title bar -> nothing to roll up to
    AssertFalse('not rolled without a title bar', f.RolledUp);
    AssertEquals('height unchanged', 300, f.Height);
  finally f.Free; end;
end;

{ TFormStyleOverrideTest }

{ Same lazy widgetset bootstrap as test.base's NeedWidgetSet (console runner registers no
  window classes -> CreateHandle error 1407); needed here because the apply-pipe tests pin the
  effects layer through a REAL HWND. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TFormStyleOverrideTest.TestOverrideWinsOverThemeAndKeepsUnmentioned;
var F: TTyFormAccess; Ctl: TTyStyleController; S: TTyStyleSet;
begin
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyForm { window-shadow: true; border-radius: 10; }');
    F.ApplyChromeTheme(Ctl);
    F.StyleOverride := 'window-shadow: false;';
    S := F.CurrentStyle;
    AssertTrue('window-shadow present after merge', tpWindowShadow in S.Present);
    AssertFalse('override window-shadow:false WINS over the theme''s true', S.WindowShadow);
    AssertEquals('unmentioned theme border-radius survives the merge', 10, S.BorderRadius);
  finally
    Ctl.Free; F.Free;
  end;
end;

procedure TFormStyleOverrideTest.TestThemeShadowOffReachesApplyPipe;
var F: TTyFormAccess; Ctl: TTyStyleController; c0: Cardinal;
begin
  { Forum #14's exact scenario, pinned at the APPLY seam (not just resolve): a theme's
    TyForm { window-shadow: false; } must arrive at TyApplyWindowEffects with Shadow=False. }
  NeedWidgetSet;
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.HandleNeeded;
    Ctl.LoadThemeCss('TyForm { window-shadow: false; }');
    c0 := TyWindowEffectApplies;
    F.ApplyChromeTheme(Ctl);
    AssertTrue('theme apply reached the effects layer', TyWindowEffectApplies > c0);
    AssertFalse('theme window-shadow:false arrived at the apply layer', TyLastWindowEffect.Shadow);
  finally
    Ctl.Free; F.Free;
  end;
end;

procedure TFormStyleOverrideTest.TestOverrideFlipsShadowLiveThroughApplyPipe;
var F: TTyFormAccess; Ctl: TTyStyleController; c0: Cardinal;
begin
  { The forum user's ACTUAL use case for StyleOverride: flip the native shadow at runtime on
    one window. The setter must re-apply the chrome immediately — no repaint/show needed. }
  NeedWidgetSet;
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.HandleNeeded;
    Ctl.LoadThemeCss('TyForm { background: #FFFFFF; }');   // no shadow token -> default ON
    F.ApplyChromeTheme(Ctl);
    AssertTrue('default-on shadow before the flip', TyLastWindowEffect.Shadow);
    c0 := TyWindowEffectApplies;
    F.StyleOverride := 'window-shadow: false;';
    AssertTrue('assignment re-applied the chrome by itself', TyWindowEffectApplies > c0);
    AssertFalse('live flip OFF landed at the apply layer', TyLastWindowEffect.Shadow);
    F.StyleOverride := '';
    AssertTrue('clearing the override restores default-on live', TyLastWindowEffect.Shadow);
  finally
    Ctl.Free; F.Free;
  end;
end;

procedure TFormStyleOverrideTest.TestOverrideRadiusZeroReachesApplyPipe;
var F: TTyFormAccess; Ctl: TTyStyleController; c0: Cardinal;
begin
  { border-radius: 0 against a theme that HAD a radius — the "partly working" report's other
    half — at first apply and on a live override flip. }
  NeedWidgetSet;
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.HandleNeeded;
    Ctl.LoadThemeCss('TyForm { border-radius: 12; }');
    F.ApplyChromeTheme(Ctl);
    AssertEquals('theme radius at the apply layer', 12, TyLastWindowEffect.RadiusPx);
    c0 := TyWindowEffectApplies;
    F.StyleOverride := 'border-radius: 0;';
    AssertTrue('assignment re-applied the chrome', TyWindowEffectApplies > c0);
    AssertEquals('radius 0 landed at the apply layer', 0, TyLastWindowEffect.RadiusPx);
  finally
    Ctl.Free; F.Free;
  end;
end;

procedure TFormStyleOverrideTest.TestOverrideWithoutControllerStillFlipsShadow;
var F: TTyFormAccess;
begin
  { No Controller assigned: the effects path resolves via the built-in default controller, and
    StyleOverride must merge there too (the default theme sets no window-shadow -> default on). }
  NeedWidgetSet;
  F := TTyFormAccess.CreateNew(nil);
  try
    F.HandleNeeded;
    F.ApplyWindowEffects;
    AssertTrue('built-in default resolves shadow-on (default-on policy)', TyLastWindowEffect.Shadow);
    F.StyleOverride := 'window-shadow: false;';
    AssertFalse('override flips the shadow with no Controller assigned', TyLastWindowEffect.Shadow);
    F.StyleOverride := '';
    AssertTrue('cleared override returns to default-on', TyLastWindowEffect.Shadow);
  finally
    F.Free;
  end;
end;

procedure TFormStyleOverrideTest.TestOverrideSurvivesMaximizeRestore;
var F: TTyFormAccess; Ctl: TTyStyleController;
begin
  { Third timing: engine maximize/restore re-applies the effects (ApplyMaximizedState), and the
    override + theme values must survive both transitions. }
  NeedWidgetSet;
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    F.MakeTitleBar;
    F.SetBounds(10, 10, 400, 300);
    F.HandleNeeded;
    Ctl.LoadThemeCss('TyForm { border-radius: 9; }');
    F.ApplyChromeTheme(Ctl);
    F.StyleOverride := 'window-shadow: false;';
    AssertFalse('precondition: shadow off before maximize', TyLastWindowEffect.Shadow);
    F.Engine.ToggleMaximize;
    AssertTrue('maximize re-applied with Maximized=True', TyLastWindowEffect.Maximized);
    AssertFalse('shadow-off survives maximize', TyLastWindowEffect.Shadow);
    AssertEquals('theme radius still resolved while maximized', 9, TyLastWindowEffect.RadiusPx);
    F.Engine.ToggleMaximize;
    AssertFalse('restore re-applied with Maximized=False', TyLastWindowEffect.Maximized);
    AssertFalse('shadow-off survives restore', TyLastWindowEffect.Shadow);
  finally
    Ctl.Free; F.Free;
  end;
end;

procedure TFormStyleOverrideTest.TestOverrideVarRebindsOnThemeSwitch;
var F: TTyFormAccess; Ctl: TTyStyleController;
begin
  { var(--x) in an override binds against the ACTIVE theme and re-binds after a switch (the
    override cache is keyed on ThemeVersion — same contract as every control's StyleOverride). }
  F := TTyFormAccess.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(':root { --edge: 4; } TyForm { background: #FFFFFF; }');
    F.ApplyChromeTheme(Ctl);
    F.StyleOverride := 'border-radius: var(--edge);';
    AssertEquals('override var bound against the first theme', 4, F.CurrentStyle.BorderRadius);
    Ctl.LoadThemeCss(':root { --edge: 7; } TyForm { background: #FFFFFF; }');
    AssertEquals('override var re-bound after the theme switch', 7, F.CurrentStyle.BorderRadius);
  finally
    Ctl.Free; F.Free;
  end;
end;

{ ===== ac2363: TControlDpiRoundTripTest ===================================== }

procedure TControlDpiRoundTripTest.Track(const AName: string; ACtl: TControl);
begin
  SetLength(FCtls, Length(FCtls) + 1);
  SetLength(FNames, Length(FCtls));
  SetLength(FStart, Length(FCtls));
  FCtls[High(FCtls)] := ACtl;
  FNames[High(FCtls)] := AName;
end;

procedure TControlDpiRoundTripTest.Build(APPI: Integer);
{ One form, eight controls, all of them at a genuine APPI (96 unless a caller says otherwise)
  and an explicit font size. Every design number below is written at 96 and scaled by APPI/96
  on the way in, so Build(240) produces the form a machine whose ONLY monitor is 250% would
  have built -- which is what TestFloorAfterCrossingEqualsFloorBornAtThatPPI compares against.

  Both normalising lines are load-bearing; neither is there to make the test pass.

  Font.PixelsPerInch := 96 -- TFont is born at the SCREEN's PPI (font.inc:625) and the
  console runner reports 72, so without this the "before" state would be measured at a PPI
  the trip never returns to, and the round trip would be asserted against a start that never
  existed on a 96 DPI monitor.

  TySlack is the logical px of headroom each control keeps above its own floor -- small
  enough to keep this an edge probe, large enough to absorb the measurement's own
  non-linearity in PPI. See the loop at the bottom.

  Font.Size := 9 -- pins the caption measurement so it says the same thing before and after
  the trip. Leaving it at 0 hits a SEPARATE defect, the "second latch": with Font.Height = 0
  (the default) LCL's DPI pass ASSIGNS an explicit height on the first crossing
  (DoScaleFontPPI, control.inc:1972-1973), so Font.Size goes 0 -> 12, and TyResolveFontSize
  then takes the explicit-size branch instead of the theme's. The caption is measured with a
  bigger font after the crossing than before it, permanently. Measured with Size unset:
  TTyCheckBox's floor 70x17 -> 78x20, TTyToggleSwitch's 108 -> 126, and neither comes back.

  WHY THE PIN IS STILL HERE NOW THAT THE SECOND LATCH IS GUARDED -- read this before
  deleting the line, because the obvious reading of the fix is that it can go.

  The guard lives on the two CONTROL bases (TTyGraphicControl.ScaleFontsPPI and
  TTyCustomControl.ScaleFontsPPI, tyControls.Base.pas; its own suite is
  tests/test.dpi.fontlatch.pas). TTyForm is neither of those, and it is not guarded. The
  children here inherit their font from the FORM, so what still latches is the form's
  Font.Height, and the pin is what stops it.

  MEASURED, not assumed. Deleting just this line and rebuilding leaves six of the seven
  tests in this class GREEN and fails exactly one -- TestRoundTripsWithTheLclDefaultParentFontToo,
  the only one that runs with the LCL default ParentFont = True, i.e. the only one whose
  controls take their font FROM the form -- with `TTyToggleSwitch: width after three
  96->240->96 trips expected <120> but was <126>`. That 126 is the same number section 5 of
  the plan recorded for this defect. Adding the identical six-line guard to
  TTyForm.ScaleFontsPPI and deleting this line makes all seven pass; that experiment was
  run, and reverted, because tyControls.Form.pas was out of scope for the change that added
  the control-side guard. It is the whole of the follow-up.

  So: when TTyForm gets the same guard, this line and the FCtls[i].Font.Size pin below can
  both go, and this class becomes an unpinned round-trip test. Until then the pin is load
  bearing, and it is a pin against the FORM's font, not against the controls'. }
var
  i: Integer;
  b: TButton;
  e: TTyEdit;
  tb: TTyButton;
  lb: TTyLabel;
  cb: TTyCheckBox;
  rb: TTyRadioButton;
  ts: TTyToggleSwitch;
  bg: TTyButtonGroup;
  function S(AValue: Integer): Integer;   // one design number, at APPI
  begin
    Result := MulDiv(AValue, APPI, 96);
  end;

begin
  SetLength(FCtls, 0); SetLength(FNames, 0); SetLength(FStart, 0);
  { A controller of this test's own, so the caption measurements do not depend on whichever
    theme an earlier test happened to leave on TyDefaultController. That order-dependence is
    not hypothetical: with the ambient theme the full suite leaves behind, TTyButton's width
    floor at 240 is 175 px where 2.5x the 96 answer is 165, and the extra 10 px is enough to
    ratchet a control that sits exactly on its floor. Declaring the tokens the floors are
    derived from makes the run say the same thing whatever ran before it. No type rules --
    an empty rule set for a typeKey falls through to the base layer, and writing partial
    ones is how a theme erases a control (see memory/variant-only-rule-erases-control). }
  FreeAndNil(FCtl);
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(':root { --font-size-base: 9; --line-height: 14; ' +
                    '--checkbox-size: 14; --checkbox-gap: 6; }');

  FForm := TTyForm.CreateNew(nil);
  FForm.SetBounds(50, 50, S(640), S(480));
  FForm.Font.PixelsPerInch := APPI;
  { The FORM's font carries the explicit size, so that a ParentFont child inherits a
    non-zero Font.Height and LCL never has to invent one. That conversion --
    `if AFont.Height = 0 then AFont.Height := MulDiv(GetFontData(...).Height,
    AFont.PixelsPerInch, Screen.PixelsPerInch)`, DoScaleFontPPI, control.inc:1972 -- uses
    Screen.PixelsPerInch as its reference, and the console test runner reports 72 while
    these fonts claim 96, so it would silently enlarge every caption by a third on the
    FIRST crossing and never undo it.

    THIS PIN IS STILL REQUIRED, and it is now a pin against the FORM's font specifically:
    the control bases are guarded against that latch (tyControls.Base.pas ScaleFontsPPI,
    tests/test.dpi.fontlatch.pas) but TTyForm is not. Deleting this line fails exactly one
    test in this class -- the ParentFont = True one -- with TTyToggleSwitch 120 -> 126.
    Measured, both directions; the full reasoning and the follow-up are in Build's header
    comment above. Do not delete it on the strength of "the second latch is fixed now". }
  FForm.Font.Size := 9;

  b := TButton.Create(FForm);   b.Parent := FForm;  b.SetBounds(S(10), S(10), S(100), S(26));
  b.Caption := 'Plain LCL';                                Track('TButton (plain LCL)', b);
  e := TTyEdit.Create(FForm);   e.Parent := FForm;  e.SetBounds(S(10), S(50), S(120), S(26));
  e.Controller := FCtl;                                    Track('TTyEdit', e);
  tb := TTyButton.Create(FForm); tb.Parent := FForm; tb.SetBounds(S(10), S(90), S(100), S(29));
  tb.Caption := 'Ty button'; tb.Controller := FCtl;        Track('TTyButton', tb);
  lb := TTyLabel.Create(FForm);  lb.Parent := FForm; lb.SetBounds(S(10), S(130), S(120), S(26));
  lb.Caption := 'Ty label'; lb.Controller := FCtl;         Track('TTyLabel', lb);
  cb := TTyCheckBox.Create(FForm); cb.Parent := FForm; cb.SetBounds(S(10), S(170), S(120), S(26));
  cb.Caption := 'Ty check'; cb.Controller := FCtl;         Track('TTyCheckBox', cb);
  rb := TTyRadioButton.Create(FForm); rb.Parent := FForm; rb.SetBounds(S(10), S(210), S(120), S(26));
  rb.Caption := 'Ty radio'; rb.Controller := FCtl;         Track('TTyRadioButton', rb);
  ts := TTyToggleSwitch.Create(FForm); ts.Parent := FForm; ts.SetBounds(S(10), S(250), S(120), S(26));
  ts.Caption := 'Ty switch'; ts.Controller := FCtl;        Track('TTyToggleSwitch', ts);
  bg := TTyButtonGroup.Create(FForm); bg.Parent := FForm; bg.SetBounds(S(10), S(290), S(200), S(28));
  bg.Items.Text := 'One'#10'Two'#10'Three'; bg.Controller := FCtl;
                                                           Track('TTyButtonGroup', bg);

  for i := 0 to High(FCtls) do
  begin
    FCtls[i].Font.PixelsPerInch := APPI;
    if FPinOwnFont then
      FCtls[i].Font.Size := 9
    else
      { Put back what touching the font just cleared (TControl.FontChanged sets
        FParentFont := False, control.inc:621). ParentFont = True is the LCL DEFAULT and it
        takes a completely different route through the DPI pass -- see
        TestRoundTripsWithTheLclDefaultParentFontToo. Re-copies the form's font, which the
        line above has already put at APPI. }
      TParentFontAccess(FCtls[i]).ParentFont := True;
    FCtls[i].Invalidate;   // settles each control's own floor AT APPI, before anything moves
  end;

  { Now bring every control down to just above its own floor.

    Sizing the box off the FLOOR rather than off a designer's round number is what makes
    this an edge probe, and a mutant is why. With the original TTyLabel -- 26 px tall
    against a 9 px floor -- even a floor that had been scaled TWICE (57 px) still fitted
    inside the 65 px box the crossing produced, so nothing was ever clamped and the mutant
    that deleted the graphic base's guard passed all six tests. The slack has to be small
    enough that a doubled floor (~6.25x at 240, against a box of 2.5x) overflows it, which
    at these floor sizes it does by tens of pixels.

    Not ZERO slack, though, and the reason is worth stating because it is a real limit of
    the fix rather than a convenience: a MEASURED floor is not exactly proportional to PPI,
    while LCL scales bounds and Constraints proportionally. A control sitting exactly on its
    floor therefore ratchets by however much the measurement is super-proportional -- it
    grows at 240 and the proportional return cannot undo it. TySlack px of slack at 96 buys
    2.5x that at 240, which absorbs the couple of pixels the measurement actually moves
    under a pinned theme and font size. See plans/2026-08-08-permonitor-dpi.md section 4.

    The second pass matters too: TTyToggleSwitch's WIDTH floor is derived from its Height
    (the 44:24 pill), so shrinking the box moves the floor and the pair has to settle. }
  if FTighten >= 0 then SitOnFloor(S(FTighten));
  SnapStart;
end;

procedure TControlDpiRoundTripTest.SitOnFloor(ASlackPx: Integer);
{ Size every control to its own floor plus ASlackPx. Twice, because two of these floors are
  functions of the box as well as of the PPI and have to settle against each other. }
var i, pass: Integer;
begin
  for pass := 1 to 2 do
    for i := 0 to High(FCtls) do
    begin
      if FCtls[i].Constraints.MinHeight > 0 then
        FCtls[i].Height := FCtls[i].Constraints.MinHeight + ASlackPx;
      if FCtls[i].Constraints.MinWidth > 0 then
        FCtls[i].Width := FCtls[i].Constraints.MinWidth + ASlackPx;
      FCtls[i].Invalidate;
    end;
end;

procedure TControlDpiRoundTripTest.Cross(APPI: Integer);
{ Exactly what a monitor crossing does: TCustomForm.WMDPIChanged (customform.inc:2273)
  turns WM_DPICHANGED into this one call. Nothing here is simulated except the message. }
begin
  FForm.AutoAdjustLayout(lapAutoAdjustForDPI, FForm.PixelsPerInch, APPI,
    FForm.Width, MulDiv(FForm.Width, APPI, FForm.PixelsPerInch));
end;

function TControlDpiRoundTripTest.BoundsOf(AIndex: Integer): TRect;
begin
  Result := Rect(FCtls[AIndex].Left, FCtls[AIndex].Top,
                 FCtls[AIndex].Width, FCtls[AIndex].Height);  // R/B carry W/H, not edges
end;

procedure TControlDpiRoundTripTest.SnapStart;
var i: Integer;
begin
  for i := 0 to High(FCtls) do FStart[i] := BoundsOf(i);
end;

procedure TControlDpiRoundTripTest.SetUp;
begin
  inherited SetUp;
  FPinOwnFont := True;
  FTighten := TySlack;
end;

procedure TControlDpiRoundTripTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  SetLength(FCtls, 0);
  SetLength(FNames, 0);
  SetLength(FStart, 0);
  inherited TearDown;
end;

procedure TControlDpiRoundTripTest.TestPlainLclControlRoundTripsExactly;
{ THE CONTROL GROUP, asserted first and on its own. If this one ever fails, the harness or
  LCL is at fault and nothing else in this class means anything. Stated as its own test so
  that distinction survives in the failure list rather than in someone's memory. }
var r: TRect;
begin
  Build;
  Cross(240);
  Cross(96);
  r := BoundsOf(0);
  AssertEquals('plain LCL TButton width after 96->240->96', FStart[0].Right, r.Right);
  AssertEquals('plain LCL TButton height after 96->240->96', FStart[0].Bottom, r.Bottom);
  AssertEquals('plain LCL TButton top after 96->240->96', FStart[0].Top, r.Top);
end;

procedure TControlDpiRoundTripTest.TestEveryControlRoundTripsExactlyOverThreeTrips;
{ THE "broken FOREVER" GUARD. Three trips, not one: TTyToggleSwitch's width was 195 after
  one there-and-back and 219 after three, so a single trip hides exactly the error that
  compounds -- and compounding is what "forever" means to the person dragging the window. }
begin
  Build;
  AssertThreeTripsAreExact;
end;

procedure TControlDpiRoundTripTest.AssertThreeTripsAreExact;
var i, t: Integer; r: TRect;
begin
  for t := 1 to 3 do
  begin
    Cross(240);
    Cross(96);
  end;
  for i := 0 to High(FCtls) do
  begin
    r := BoundsOf(i);
    AssertEquals(FNames[i] + ': left after three 96->240->96 trips', FStart[i].Left, r.Left);
    AssertEquals(FNames[i] + ': top after three 96->240->96 trips', FStart[i].Top, r.Top);
    AssertEquals(FNames[i] + ': width after three 96->240->96 trips', FStart[i].Right, r.Right);
    AssertEquals(FNames[i] + ': height after three 96->240->96 trips', FStart[i].Bottom, r.Bottom);
  end;
end;

procedure TControlDpiRoundTripTest.TestRoundTripsWithTheLclDefaultParentFontToo;
{ THE SECOND ROUTE, and the one the first version of this test was blind to.

  ParentFont = True is the LCL default, and it changes WHEN the control's font reaches the
  new PPI. TControl.AutoAdjustLayout saves ParentFont and restores it in a finally
  (control.inc:4221/4228), and restoring it re-copies the PARENT's font -- which is still at
  the old PPI, because TWinControl.AutoAdjustLayout walks the children before itself. So on
  exit from a ParentFont child's own pass its font is back where it started, and the new one
  only arrives later, via the parent's pass and CM_PARENTFONTCHANGED.

  A fix that re-derives the floor at the end of the child's own pass therefore measures at
  the OLD PPI in this configuration and clamps the bounds to that. Measured before the
  Font.PixelsPerInch = AToPPI test was added to tyControls.Base.pas: TTyButton went
  100x29 -> 250x72 -> 175x70 -- the crossing looked right and the return was still
  "broken forever". Every other test in this class pins the control's own font (which sets
  ParentFont = False) and all of them passed while that was broken.

  This one keeps the DESIGNED bounds rather than shrinking to the floor, because it probes
  a different edge: the route the font takes, not the margin between the box and the floor.
  Shrinking as well would stack the section-4d ratchet on top and confuse the two -- and
  with an unpinned font that ratchet is larger, because the ink is the system font's and
  further from linear in PPI. The defect this test exists for needs no tight box at all:
  with the designed bounds and no fix, TTyButton ends at 175x70 having started at 100x29. }
begin
  FPinOwnFont := False;
  FTighten := -1;
  Build;
  AssertThreeTripsAreExact;
end;

procedure TControlDpiRoundTripTest.TestFloorScalesWithPPI;
{ The other half of the contract, and the reason the fix is not "stop scaling": a control
  must actually FOLLOW the monitor. Asserted as a band around 2.5x rather than an absolute,
  because the exact device height at 240 comes from a font measurement and is not required
  to be linear -- only proportional. }
var i, h240: Integer;
begin
  Build;
  Cross(240);
  for i := 0 to High(FCtls) do
  begin
    h240 := FCtls[i].Height;
    AssertTrue(Format('%s: 96->240 must make it taller (%d -> %d)',
      [FNames[i], FStart[i].Bottom, h240]), h240 > FStart[i].Bottom);
    AssertTrue(Format('%s: 96->240 should scale by about 240/96, got %d -> %d',
      [FNames[i], FStart[i].Bottom, h240]),
      (h240 * 10 >= FStart[i].Bottom * 22) and (h240 * 10 <= FStart[i].Bottom * 29));
  end;
end;

procedure TControlDpiRoundTripTest.TestSingleCrossingDoesNotSquareTheFactor;
{ THE "far too tall" GUARD, in the form the report described. Double application squares
  the factor: 2.5 becomes 6.25, and the measured TTyButton went 29 -> 175 (6.03x, the
  shortfall being the font's own non-linearity). 4x is a floor no correct answer can reach
  and no squared one can stay under, so it separates the two cases with room to spare. }
var i: Integer;
begin
  Build;
  Cross(240);
  for i := 0 to High(FCtls) do
    AssertTrue(Format('%s: one 96->240 crossing applied the factor TWICE (%d -> %d)',
      [FNames[i], FStart[i].Bottom, FCtls[i].Height]),
      FCtls[i].Height < FStart[i].Bottom * 4);
end;

procedure TControlDpiRoundTripTest.TestCrossingIsIdempotentAtOnePPI;
{ Re-running the pass at the PPI the control is ALREADY at must not move it. LCL short-
  circuits this at the form (TCustomDesignControl.AutoAdjustLayout returns when AToPPI is
  the current one), so the call is made on each control directly -- which is also the only
  way to see whether the post-pass re-derivation is itself idempotent, i.e. whether the
  floor is a function of the PPI or of how many times it has been asked.

  Run at the class's normal slack, not on the floor: a control sitting exactly on its floor
  can end a crossing a pixel or two under it (plans/2026-08-08-permonitor-dpi.md section 4d
  says why that is a documented limit and not a bug), and a second pass would legitimately
  clamp that back, which is a different thing from the pass not being idempotent. }
var i, w, h: Integer;
begin
  Build;
  Cross(240);
  for i := 0 to High(FCtls) do
  begin
    w := FCtls[i].Width;
    h := FCtls[i].Height;
    FCtls[i].AutoAdjustLayout(lapAutoAdjustForDPI, 240, 240, FForm.Width, FForm.Width);
    AssertEquals(FNames[i] + ': a second pass at the same PPI must not change the width',
      w, FCtls[i].Width);
    AssertEquals(FNames[i] + ': a second pass at the same PPI must not change the height',
      h, FCtls[i].Height);
  end;
end;

procedure TControlDpiRoundTripTest.TestFloorAfterCrossingEqualsFloorBornAtThatPPI;
{ THE "derived, not scaled" GUARD, and the only one that fails if the post-pass
  re-derivation is deleted.

  After a crossing to 240 a control's Constraints floor must be the floor it would have
  computed had it been BORN on a 250% monitor -- not LCL's proportional rescale of the 96
  answer. The two are close but not equal, because a caption's measured width is not linear
  in PPI: measured here, TTyCheckBox is 70 px at 96 and 171 px at 240, where the rescale
  would say 175. That gap is the whole point. A floor that is a product of round-off factors
  drifts a little further every crossing; a floor that is F(current PPI) cannot.

  Crossed to 137 rather than 240 because 137/96 is not a round ratio and is therefore the
  harsher probe of the two. Stated honestly: it is not harsh ENOUGH. A mutant that deletes
  the re-derivation entirely -- leaving LCL's proportional rescale of the old floor as the
  final answer -- survives this test at 240 AND at 137, because with the pinned 9 pt font
  every floor in this harness happens to rescale to exactly the value a fresh measurement
  gives. The two answers only separate where a caption's ink is non-linear in PPI, which
  this deliberately clean font is not. So read this test as pinning the SHAPE (the floor is
  asked for, not inherited) rather than as proof that the re-derivation is load-bearing;
  plans/2026-08-08-permonitor-dpi.md section 4e records that survivor and why the code is
  kept anyway. }
const
  AwkwardPPI = 137;
var
  i: Integer;
  crossedW, crossedH: array of Integer;
  crossedBounds: array of TRect;
  names: array of string;
begin
  Build(96);
  Cross(AwkwardPPI);
  SetLength(crossedW, Length(FCtls));
  SetLength(crossedH, Length(FCtls));
  SetLength(crossedBounds, Length(FCtls));
  SetLength(names, Length(FCtls));
  for i := 0 to High(FCtls) do
  begin
    crossedW[i] := FCtls[i].Constraints.MinWidth;
    crossedH[i] := FCtls[i].Constraints.MinHeight;
    crossedBounds[i] := BoundsOf(i);
    names[i] := FNames[i];
  end;
  FreeAndNil(FForm);

  Build(AwkwardPPI);   // the same form, born on that monitor
  { Give the born-at-240 controls the crossed form's exact geometry before comparing. Two
    of these floors are functions of the box as well as the PPI (TTyToggleSwitch's width
    from its Height), so without this the comparison would be measuring the difference
    between two box sizes and calling it a difference between two floors. }
  for i := 0 to High(FCtls) do
  begin
    FCtls[i].SetBounds(crossedBounds[i].Left, crossedBounds[i].Top,
                       crossedBounds[i].Right, crossedBounds[i].Bottom);
    FCtls[i].Invalidate;
  end;
  for i := 0 to High(FCtls) do
  begin
    AssertEquals(names[i] + ': width floor after 96->240 must equal the floor born at 240',
      FCtls[i].Constraints.MinWidth, crossedW[i]);
    AssertEquals(names[i] + ': height floor after the crossing must equal the floor born there',
      FCtls[i].Constraints.MinHeight, crossedH[i]);
  end;
end;

initialization
  RegisterTest(TFormHelpersTest);
  RegisterTest(TResizeHitForTest);
  RegisterTest(TResizeGutterTest);
  RegisterTest(TNcHitTestTest);
  RegisterTest(TNcHitResolveTest);
  RegisterTest(TRestoreDragBoundsTest);
  RegisterTest(TResizeCursorTest);
  RegisterTest(TCaptionButtonTest);
  RegisterTest(TTitleBarTest);
  RegisterTest(TCaptionButtonPaintTest);
  RegisterTest(TTitleBarPaintTest);
  RegisterTest(TRescaleMetricTest);
  RegisterTest(TCaptionButtonHoverGlyphTest);
  RegisterTest(TTyFormTest);
  RegisterTest(TMaximizedChromeTest);
  RegisterTest(TTyFormBackdropTest);
  RegisterTest(TTyMenuFormTest);
  RegisterTest(TCaptionButtonsTest);
  RegisterTest(TTitleBarSwitchesTest);
  RegisterTest(TFormBorderStyleTest);
  RegisterTest(TFormDrivesBarTest);
  RegisterTest(TTitleBarGuardTest);
  RegisterTest(TRollUpTest);
  RegisterTest(TFormStyleOverrideTest);
  RegisterTest(TTitleBarDpiTest);   // a6256: cross-monitor DPI contract for the title bar
  RegisterTest(TControlDpiRoundTripTest);   // ac2363: the same contract for the CONTROLS

end.
