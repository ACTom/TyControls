unit test.form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms,
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
  end;

  TFormChromeTest = class(TTestCase)
  published
    procedure TestDefaultTitleHeight;
    procedure TestDefaultBorderZone;
    procedure TestDefaultShowFlags;
    procedure TestTitleBarCreated;
    procedure TestActiveDefaultsFalse;
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

  TFormChromeChangeBoundsTest = class(TTestCase)
  published
    procedure TestChangeBoundsHookedOnInstall;
    procedure TestChangeBoundsRestoredOnUninstall;
    procedure TestFormChromeFreeWhileActiveNoDangling;
    procedure TestFormChromeInstallPreservesBounds;
  end;

  TCaptionButtonHoverGlyphTest = class(TTestCase)
  published
    procedure TestGlyphRenderedByDefault;
    procedure TestNoGlyphWhenHoverOnlyAndNotHovered;
    procedure TestGlyphRenderedWhenHoverOnlyAndHovered;
  end;

  { Lifecycle events (OnCloseQuery veto / OnClose) + TitleBar mouse-slot isolation:
    after Task 1 published OnMouseDown/Move/Up/DblClick on the base classes,
    TTyTitleBar exposes those slots to users. The chrome must NOT use the event
    slots for its window-drag/double-click-maximize wiring (it now uses METHOD
    OVERRIDES that call inherited), so a user-assigned OnMouseDown still fires
    AND the chrome's drag still works. }
  TFormChromeLifecycleTest = class(TTestCase)
  published
    procedure TestOnCloseQueryVetoBlocksClose;
    procedure TestOnCloseQueryAllowFiresClose;
    procedure TestOnMinimizeFires;
    procedure TestOnRestoreFiresViaMaxRestoreAction;
    procedure TestTitleBarMouseDownEventFiresAndDragStillWorks;
    procedure TestTitleBarDblClickEventFiresAndMaximizeStillWorks;
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
  end;

  { Exposes the private DoClose path + the FDragging/FMaximized state so the
    chrome's lifecycle/veto logic can be driven headlessly. }
  TChromeAccess = class(TTyFormChrome)
  public
    procedure InjectClose;
    procedure InjectMinimize;
    procedure InjectMaxRestore;
    procedure SetForm(AForm: TCustomForm);
    procedure SetMaximized(AValue: Boolean);
    function IsDragging: Boolean;
    function IsMaximized: Boolean;
  end;

  { Counts lifecycle/event callbacks for assertions. }
  TLifecycleProbe = class
  public
    CloseFired: Integer;
    MinimizeFired: Integer;
    MaximizeFired: Integer;
    RestoreFired: Integer;
    MouseDownFired: Integer;
    DblClickFired: Integer;
    VetoClose: Boolean;
    procedure OnCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure OnClose(Sender: TObject);
    procedure OnMinimize(Sender: TObject);
    procedure OnMaximize(Sender: TObject);
    procedure OnRestore(Sender: TObject);
    procedure OnMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OnDblClick(Sender: TObject);
  end;

  { Probe object for tracking OnChangeBounds restoration }
  TChangeBoundsProbe = class
  public
    WasCalled: Boolean;
    procedure Handler(Sender: TObject);
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

procedure TChromeAccess.InjectClose;
begin
  DoClose(Self);
end;

procedure TChromeAccess.InjectMinimize;
begin
  DoMinimize(Self);
end;

procedure TChromeAccess.InjectMaxRestore;
begin
  DoMaxRestore(Self);
end;

procedure TChromeAccess.SetForm(AForm: TCustomForm);
begin
  FForm := AForm;
end;

procedure TChromeAccess.SetMaximized(AValue: Boolean);
begin
  FMaximized := AValue;
end;

function TChromeAccess.IsDragging: Boolean;
begin
  Result := FDragging;
end;

function TChromeAccess.IsMaximized: Boolean;
begin
  Result := FMaximized;
end;

procedure TLifecycleProbe.OnCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if VetoClose then
    CanClose := False;
end;

procedure TLifecycleProbe.OnClose(Sender: TObject);
begin
  Inc(CloseFired);
end;

procedure TLifecycleProbe.OnMinimize(Sender: TObject);
begin
  Inc(MinimizeFired);
end;

procedure TLifecycleProbe.OnMaximize(Sender: TObject);
begin
  Inc(MaximizeFired);
end;

procedure TLifecycleProbe.OnRestore(Sender: TObject);
begin
  Inc(RestoreFired);
end;

procedure TLifecycleProbe.OnMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  Inc(MouseDownFired);
end;

procedure TLifecycleProbe.OnDblClick(Sender: TObject);
begin
  Inc(DblClickFired);
end;

procedure TChangeBoundsProbe.Handler(Sender: TObject);
begin
  WasCalled := True;
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

procedure TFormChromeTest.TestDefaultTitleHeight;
var
  C: TTyFormChrome;
begin
  C := TTyFormChrome.Create(nil);
  try
    AssertEquals('titleheight', 32, C.TitleHeight);
  finally
    C.Free;
  end;
end;

procedure TFormChromeTest.TestDefaultBorderZone;
var
  C: TTyFormChrome;
begin
  C := TTyFormChrome.Create(nil);
  try
    AssertEquals('borderzone', 6, C.BorderZone);
  finally
    C.Free;
  end;
end;

procedure TFormChromeTest.TestDefaultShowFlags;
var
  C: TTyFormChrome;
begin
  C := TTyFormChrome.Create(nil);
  try
    AssertTrue('min', C.ShowMinimize);
    AssertTrue('max', C.ShowMaximize);
  finally
    C.Free;
  end;
end;

procedure TFormChromeTest.TestTitleBarCreated;
var
  C: TTyFormChrome;
begin
  C := TTyFormChrome.Create(nil);
  try
    AssertTrue('titlebar', C.TitleBar <> nil);
  finally
    C.Free;
  end;
end;

procedure TFormChromeTest.TestActiveDefaultsFalse;
var
  C: TTyFormChrome;
begin
  C := TTyFormChrome.Create(nil);
  try
    AssertFalse('active', C.Active);
  finally
    C.Free;
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

{ TFormChromeChangeBoundsTest }

procedure TFormChromeChangeBoundsTest.TestChangeBoundsHookedOnInstall;
var
  F: TForm;
  C: TTyFormChrome;
begin
  F := TForm.CreateNew(nil);
  C := TTyFormChrome.Create(F);
  try
    C.Active := True;
    AssertTrue('OnChangeBounds should be hooked after install',
      Assigned(TForm(F).OnChangeBounds));
  finally
    C.Active := False;
    F.Free;
  end;
end;

procedure TFormChromeChangeBoundsTest.TestChangeBoundsRestoredOnUninstall;
var
  F: TForm;
  C: TTyFormChrome;
  Probe: TChangeBoundsProbe;
begin
  Probe := TChangeBoundsProbe.Create;
  F := TForm.CreateNew(nil);
  C := TTyFormChrome.Create(F);
  try
    { Assign probe before installing }
    TForm(F).OnChangeBounds := @Probe.Handler;
    C.Active := True;
    { Uninstall should restore the probe }
    C.Active := False;
    AssertTrue('OnChangeBounds should be restored to probe after uninstall',
      TForm(F).OnChangeBounds = @Probe.Handler);
  finally
    F.Free;
    Probe.Free;
  end;
end;

procedure TFormChromeChangeBoundsTest.TestFormChromeFreeWhileActiveNoDangling;
var
  F: TForm;
  Chrome: TTyFormChrome;
begin
  { Observed in this headless env: TTyFormChrome.Create(F) makes F the Owner,
    so HostForm <> nil and InstallChrome DOES run on Active := True, hijacking
    F.OnMouseDown/OnMouseMove/OnMouseUp/OnChangeBounds with the chrome's own
    methods (same path verified by TestChangeBoundsHookedOnInstall).
    Without a destructor, freeing the chrome while Active=True leaves F holding
    method pointers into freed memory -> dangling handlers. The destructor must
    call UninstallChrome to restore them. }
  F := TForm.CreateNew(nil);
  try
    Chrome := TTyFormChrome.Create(F);
    Chrome.Active := True;     { InstallChrome hijacks F.OnMouseDown etc. }
    { Sanity: confirm the hijack actually happened in this env }
    AssertTrue('precondition: chrome hijacked OnMouseDown on install',
      Assigned(TForm(F).OnMouseDown));
    Chrome.Free;               { destructor must UninstallChrome }
    AssertFalse('host OnMouseDown cleared after chrome free',
      Assigned(TForm(F).OnMouseDown));
    AssertFalse('host OnMouseMove cleared after chrome free',
      Assigned(TForm(F).OnMouseMove));
    AssertFalse('host OnMouseUp cleared after chrome free',
      Assigned(TForm(F).OnMouseUp));
    AssertFalse('host OnChangeBounds cleared after chrome free',
      Assigned(TForm(F).OnChangeBounds));
  finally
    F.Free;
  end;
end;

procedure TFormChromeChangeBoundsTest.TestFormChromeInstallPreservesBounds;
var
  F: TForm;
  Chrome: TTyFormChrome;
  B: TRect;
begin
  { InstallChrome sets BorderStyle:=bsNone, which recreates the window handle.
    The widgetset then re-places the window; on a multi-monitor virtual desktop
    with negative coordinates (a monitor above/left of the primary) the window
    can land off-screen (negative Top). The fix captures BoundsRect before the
    border change and restores it after HandleNeeded.

    NOTE: in this headless test env changing BorderStyle may not actually move
    the window, so this assertion can pass even before the fix. The fix's real
    purpose is the multi-monitor (negative virtual coords) case, which cannot be
    reproduced headlessly. This test is kept as a regression guard that install
    never DISTURBS the form's bounds. }
  F := TForm.CreateNew(nil);
  try
    F.SetBounds(120, 80, 400, 300);
    B := F.BoundsRect;
    Chrome := TTyFormChrome.Create(F);
    Chrome.Active := True;     { InstallChrome changes BorderStyle -> must restore bounds }
    AssertEquals('Left preserved', B.Left, F.BoundsRect.Left);
    AssertEquals('Top preserved',  B.Top,  F.BoundsRect.Top);
    AssertEquals('Width preserved', B.Right - B.Left, F.BoundsRect.Right - F.BoundsRect.Left);
    AssertEquals('Height preserved', B.Bottom - B.Top, F.BoundsRect.Bottom - F.BoundsRect.Top);
  finally
    F.Free;  { chrome owned by F, freed with it; its destructor uninstalls }
  end;
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

{ TFormChromeLifecycleTest }

procedure TFormChromeLifecycleTest.TestOnCloseQueryVetoBlocksClose;
var
  C: TChromeAccess;
  P: TLifecycleProbe;
begin
  { With OnCloseQuery returning CanClose:=False, DoClose must abort before the
    OnClose event (and FForm.Close) — observe via the OnClose counter staying 0.
    No real window needed: the veto path returns before touching FForm. }
  C := TChromeAccess.Create(nil);
  P := TLifecycleProbe.Create;
  try
    P.VetoClose := True;
    C.OnCloseQuery := @P.OnCloseQuery;
    C.OnClose := @P.OnClose;
    C.InjectClose;
    AssertEquals('veto: OnClose must NOT fire', 0, P.CloseFired);
  finally
    C.Free;
    P.Free;
  end;
end;

procedure TFormChromeLifecycleTest.TestOnCloseQueryAllowFiresClose;
var
  C: TChromeAccess;
  P: TLifecycleProbe;
begin
  { CanClose left True -> OnClose fires (then FForm.Close, guarded by FForm<>nil
    so harmless headlessly). }
  C := TChromeAccess.Create(nil);
  P := TLifecycleProbe.Create;
  try
    P.VetoClose := False;
    C.OnCloseQuery := @P.OnCloseQuery;
    C.OnClose := @P.OnClose;
    C.InjectClose;
    AssertEquals('allow: OnClose fires once', 1, P.CloseFired);
  finally
    C.Free;
    P.Free;
  end;
end;

procedure TFormChromeLifecycleTest.TestOnMinimizeFires;
var
  C: TChromeAccess;
  P: TLifecycleProbe;
begin
  { DoMinimize fires OnMinimize before its 'if FForm<>nil' guard, so this needs no
    real window: drive it on an un-installed chrome (FForm=nil). }
  C := TChromeAccess.Create(nil);
  P := TLifecycleProbe.Create;
  try
    C.OnMinimize := @P.OnMinimize;
    C.InjectMinimize;
    AssertEquals('OnMinimize fired once', 1, P.MinimizeFired);
  finally
    C.Free;
    P.Free;
  end;
end;

procedure TFormChromeLifecycleTest.TestOnRestoreFiresViaMaxRestoreAction;
var
  F: TForm;
  C: TChromeAccess;
  P: TLifecycleProbe;
begin
  { ToggleMaximize's restore branch (FMaximized=True) only re-applies saved bounds
    and fires OnRestore — it never touches FForm.Handle, so it runs headlessly on a
    handle-less injected form. We inject FForm + FMaximized=True directly (no
    InstallChrome, so no win32 handle is forced). DoMaxRestore is the caption-button
    action. }
  F := TForm.CreateNew(nil);
  C := TChromeAccess.Create(nil);
  P := TLifecycleProbe.Create;
  try
    C.SetForm(F);
    C.SetMaximized(True);
    C.OnMaximize := @P.OnMaximize;
    C.OnRestore := @P.OnRestore;
    C.InjectMaxRestore;   { restore branch -> OnRestore }
    AssertEquals('OnRestore fired once', 1, P.RestoreFired);
    AssertEquals('OnMaximize not fired on restore', 0, P.MaximizeFired);
    AssertFalse('no longer maximized after restore', C.IsMaximized);
  finally
    C.Free;
    F.Free;
    P.Free;
  end;
end;

procedure TFormChromeLifecycleTest.TestTitleBarMouseDownEventFiresAndDragStillWorks;
var
  F: TForm;
  C: TChromeAccess;
  TB: TTitleBarAccess;
  P: TLifecycleProbe;
begin
  { Critical isolation test: after the user assigns TTyTitleBar.OnMouseDown, the
    chrome's window-drag (FDragging) must STILL be armed when the titlebar is
    pressed — because chrome wires drag via a method override that calls inherited
    (which fires the user's OnMouseDown), not by hijacking the event slot.
    Headless: inject FForm directly (the drag-arm path reads no handle), so no
    InstallChrome / win32 control is created. }
  F := TForm.CreateNew(nil);
  C := TChromeAccess.Create(nil);
  P := TLifecycleProbe.Create;
  try
    C.SetForm(F);
    TB := TTitleBarAccess(C.TitleBar);
    TB.OnMouseDown := @P.OnMouseDown;   { user assigns the now-free slot }
    TB.InjectMouseDown(mbLeft, [], 10, 5);
    AssertEquals('user OnMouseDown fired (inherited called)', 1, P.MouseDownFired);
    AssertTrue('chrome drag armed despite user OnMouseDown', C.IsDragging);
  finally
    C.Free;
    F.Free;
    P.Free;
  end;
end;

procedure TFormChromeLifecycleTest.TestTitleBarDblClickEventFiresAndMaximizeStillWorks;
var
  F: TForm;
  C: TChromeAccess;
  TB: TTitleBarAccess;
  P: TLifecycleProbe;
begin
  { Same isolation for DblClick: user OnDblClick fires AND the chrome's maximize
    toggle (via the DblClick override -> ToggleMaximize) runs. Headless: start
    FMaximized=True so ToggleMaximize takes the restore branch (no FForm.Handle
    access) -> FMaximized flips to False, proving the chrome handler ran. }
  F := TForm.CreateNew(nil);
  C := TChromeAccess.Create(nil);
  P := TLifecycleProbe.Create;
  try
    C.SetForm(F);
    C.SetMaximized(True);
    TB := TTitleBarAccess(C.TitleBar);
    TB.OnDblClick := @P.OnDblClick;
    TB.InjectDblClick;
    AssertEquals('user OnDblClick fired (inherited called)', 1, P.DblClickFired);
    AssertFalse('chrome maximize toggled (restored) despite user OnDblClick',
      C.IsMaximized);
  finally
    C.Free;
    F.Free;
    P.Free;
  end;
end;

initialization
  RegisterTest(TFormHelpersTest);
  RegisterTest(TResizeCursorTest);
  RegisterTest(TCaptionButtonTest);
  RegisterTest(TTitleBarTest);
  RegisterTest(TFormChromeTest);
  RegisterTest(TCaptionButtonPaintTest);
  RegisterTest(TTitleBarPaintTest);
  RegisterTest(TRescaleMetricTest);
  RegisterTest(TFormChromeChangeBoundsTest);
  RegisterTest(TCaptionButtonHoverGlyphTest);
  RegisterTest(TFormChromeLifecycleTest);

end.
