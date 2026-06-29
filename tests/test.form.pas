unit test.form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, Menus, LCLType, LMessages,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Form,
  tyControls.Menu;

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
  end;

  TCaptionButtonPaintTest = class(TTestCase)
  published
    procedure TestPaintSmoke;
  end;

  TTitleBarPaintTest = class(TTestCase)
  published
    procedure TestPaintSmoke;
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
    procedure TestDblClickMaximizeToggles;
    procedure TestResizableDefaultsTrue;
    procedure TestResizableRoundTrips;
    procedure TestResizableEdgePressStartsResize;
    procedure TestNonResizableEdgePressDoesNotStartResize;
    procedure TestNonResizableDisablesMaxButton;
    procedure TestNonResizableGatesMaximize;
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

implementation

type
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
    { Drive the form's own (protected) mouse entry points headlessly — exactly the path
      the widgetset uses — so the engine's resize gating can be exercised without a handle. }
    procedure InjectFormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure InjectFormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    { Build a TLMKey for AKey + AShift and run it through the form's IsShortcut
      override exactly as the widgetset would, returning whether it was consumed.
      ssAlt is encoded into KeyData (MK_ALT) so the match is deterministic headless. }
    function TestIsShortCut(AKey: Word; AShift: TShiftState): Boolean;
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
    AssertEquals('right inset = one button width', T.ButtonWidth, T.RightInset);
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
    TTitleBarAccess(F.TitleBar).InjectMouseDown(mbLeft, [], 10, 5);
    AssertTrue('engine drag armed via title bar', F.EngineDragging);
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
  { Resizable (default): a left-button press in the edge zone arms the engine resize.
    SetBounds gives the form a known size so (2,50) lands in the left border zone. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.SetBounds(0, 0, 200, 100);
    F.InjectFormMouseDown(mbLeft, [], 2, 50);
    AssertTrue('edge press started a resize', F.EngineResizing);
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
  { Setting Resizable=False disables the title-bar max button (a fixed window can't maximize). }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.MakeTitleBar;
    AssertTrue('max button enabled while resizable', F.TB.MaxButton.Enabled);
    F.Resizable := False;
    AssertFalse('max button disabled when not resizable', F.TB.MaxButton.Enabled);
    F.Resizable := True;
    AssertTrue('max button re-enabled when resizable again', F.TB.MaxButton.Enabled);
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

initialization
  RegisterTest(TFormHelpersTest);
  RegisterTest(TResizeHitForTest);
  RegisterTest(TResizeGutterTest);
  RegisterTest(TResizeCursorTest);
  RegisterTest(TCaptionButtonTest);
  RegisterTest(TTitleBarTest);
  RegisterTest(TCaptionButtonPaintTest);
  RegisterTest(TTitleBarPaintTest);
  RegisterTest(TRescaleMetricTest);
  RegisterTest(TCaptionButtonHoverGlyphTest);
  RegisterTest(TTyFormTest);
  RegisterTest(TTyMenuFormTest);

end.
