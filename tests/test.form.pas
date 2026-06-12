unit test.form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, fpcunit, testregistry,
  tyControls.Painter, tyControls.Form;

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

implementation

type
  TCaptionButtonAccess = class(TTyCaptionButton)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TTitleBarAccess = class(TTyTitleBar)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TCaptionButtonAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTitleBarAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
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

initialization
  RegisterTest(TFormHelpersTest);
  RegisterTest(TCaptionButtonTest);
  RegisterTest(TTitleBarTest);
  RegisterTest(TFormChromeTest);
  RegisterTest(TCaptionButtonPaintTest);
  RegisterTest(TTitleBarPaintTest);

end.
