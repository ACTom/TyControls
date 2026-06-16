unit test.form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, StdCtrls,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Form;

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

  TContentPanelTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestPaintSmoke;
  end;

  TTyFormTest = class(TTestCase)
  published
    procedure TestBorderlessFromBirth;
    procedure TestTitleBarIsTopBand;
    procedure TestContentIsClientBelowBand;
    procedure TestSubComponentsNamedAndFlagged;
    procedure TestChildOnContentSitsBelowBand;
    procedure TestDefensiveLoadedReparentsStrayChild;
    procedure TestApplyChromeThemeSetsColorFromToken;
    procedure TestTitleBarDragArmsViaEngine;
    procedure TestDblClickMaximizeToggles;
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

  TContentPanelAccess = class(TTyContentPanel)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TTyFormAccess = class(TTyForm)
  public
    function TB: TTyTitleBar;
    function Content: TTyContentPanel;
    procedure CallLoaded;
    function EngineDragging: Boolean;
    function EngineMaximized: Boolean;
    procedure SetEngineMaximized(AValue: Boolean);
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

procedure TContentPanelAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TTyFormAccess.TB: TTyTitleBar; begin Result := TitleBar; end;
function TTyFormAccess.Content: TTyContentPanel; begin Result := ContentPanel; end;
procedure TTyFormAccess.CallLoaded; begin Loaded; end;
function TTyFormAccess.EngineDragging: Boolean; begin Result := FEngine.Dragging; end;
function TTyFormAccess.EngineMaximized: Boolean; begin Result := FEngine.Maximized; end;
procedure TTyFormAccess.SetEngineMaximized(AValue: Boolean); begin FEngine.Maximized := AValue; end;

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

{ TContentPanelTest }

procedure TContentPanelTest.TestTypeKey;
var P: TTyContentPanel;
begin
  P := TTyContentPanel.Create(nil);
  try
    AssertEquals('typekey', 'TyContentPanel', P.GetStyleTypeKey);
  finally
    P.Free;
  end;
end;

procedure TContentPanelTest.TestPaintSmoke;
var
  P: TTyContentPanel;
  Bmp: TBitmap;
begin
  P := TTyContentPanel.Create(nil);
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(100, 80);
      TContentPanelAccess(P).SmokeRender(Bmp.Canvas, Rect(0, 0, 100, 80), 96);
      AssertTrue('content panel RenderTo executed without exception', True);
    finally
      Bmp.Free;
    end;
  finally
    P.Free;
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

procedure TTyFormTest.TestTitleBarIsTopBand;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    AssertTrue('titlebar exists', F.TB <> nil);
    AssertTrue('titlebar alTop', F.TB.Align = alTop);
    AssertEquals('titlebar at y=0', 0, F.TB.Top);
    AssertEquals('default title height', 32, F.TB.Height);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestContentIsClientBelowBand;
var F: TTyFormAccess;
begin
  { Structural proof of the content-below-band guarantee (headless-deterministic).
    Realized alignment needs a window handle the headless runner can't create
    (AutoSizeDelayed suppresses the align pass while the form is not visible), so
    we assert the STRUCTURE that LCL guarantees yields the geometry: an alClient
    content panel fills the area below an alTop title band. Realized pixel geometry
    is verified manually in the Lazarus designer (plan's manual checklist); see the
    design spec's verified LCL AlignControls analysis (2026-06-17 ... §4). }
  F := TTyFormAccess.CreateNew(nil);
  try
    AssertTrue('content exists', F.Content <> nil);
    AssertTrue('content alClient', F.Content.Align = alClient);
    AssertTrue('titlebar alTop reserves the band', F.TB.Align = alTop);
    AssertEquals('resize ring left', 6, F.Content.BorderSpacing.Left);
    AssertEquals('resize ring right', 6, F.Content.BorderSpacing.Right);
    AssertEquals('resize ring bottom', 6, F.Content.BorderSpacing.Bottom);
    AssertEquals('no ring at top (title band sits there)', 0, F.Content.BorderSpacing.Top);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestSubComponentsNamedAndFlagged;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    AssertEquals('titlebar name', 'TyTitleBar', F.TB.Name);
    AssertEquals('content name', 'TyContent', F.Content.Name);
    AssertTrue('titlebar subcomponent', csSubComponent in F.TB.ComponentStyle);
    AssertTrue('content subcomponent', csSubComponent in F.Content.ComponentStyle);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestChildOnContentSitsBelowBand;
var
  F: TTyFormAccess;
  Btn: TButton;
begin
  { A control added to the content panel is parented to FContent (the alClient
    region below the band), not the form root. Combined with the alClient/alTop
    structure, that places it below the title band. Realized absolute geometry is
    GUI-verified (manual checklist); the parenting + alignment contract proven here
    is the headless-deterministic guarantee. }
  F := TTyFormAccess.CreateNew(nil);
  try
    Btn := TButton.Create(F);
    Btn.Parent := F.Content;
    AssertTrue('child lives in the content panel', Btn.Parent = F.Content);
    AssertTrue('content alClient below the alTop band',
      (F.Content.Align = alClient) and (F.TB.Align = alTop));
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestDefensiveLoadedReparentsStrayChild;
var
  F: TTyFormAccess;
  Stray: TButton;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    Stray := TButton.Create(F);
    Stray.Parent := F;
    F.CallLoaded;
    AssertTrue('stray reparented into content', Stray.Parent = F.Content);
    AssertTrue('titlebar still on form', F.TB.Parent = F);
    AssertTrue('content still on form', F.Content.Parent = F);
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
    Ctl.LoadThemeCss('TyForm { background: #123456; }');
    F.ApplyChromeTheme(Ctl);
    AssertEquals('form Color from TyForm token',
      Integer(RGBToColor($12, $34, $56)), Integer(F.Color));
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TTyFormTest.TestTitleBarDragArmsViaEngine;
var F: TTyFormAccess;
begin
  { Pressing the title bar arms the engine's window-drag (FForm is the form itself). }
  F := TTyFormAccess.CreateNew(nil);
  try
    TTitleBarAccess(F.TB).InjectMouseDown(mbLeft, [], 10, 5);
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
    F.SetEngineMaximized(True);
    TTitleBarAccess(F.TB).InjectDblClick;
    AssertFalse('dbl-click toggled maximize off', F.EngineMaximized);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TFormHelpersTest);
  RegisterTest(TResizeCursorTest);
  RegisterTest(TCaptionButtonTest);
  RegisterTest(TTitleBarTest);
  RegisterTest(TCaptionButtonPaintTest);
  RegisterTest(TTitleBarPaintTest);
  RegisterTest(TRescaleMetricTest);
  RegisterTest(TCaptionButtonHoverGlyphTest);
  RegisterTest(TContentPanelTest);
  RegisterTest(TTyFormTest);

end.
