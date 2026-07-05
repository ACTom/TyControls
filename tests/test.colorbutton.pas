unit test.colorbutton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics,
  tyControls.Base, tyControls.Types, tyControls.Painter, tyControls.ColorButton;
type
  // Expose the protected DrawContent so a headless render can be exercised without
  // opening the (GUI-only) colour dialog.
  TTyColorButtonAccess = class(TTyColorButton)
  public
    procedure CallDrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet);
  end;

  TColorButtonTest = class(TTestCase)
  private
    FChanged: Integer;
    procedure HandleColorChange(Sender: TObject);
  published
    procedure TestTypeKeyStaysTyButton;
    procedure TestHexKnownValues;
    procedure TestHexIgnoresAlpha;
    procedure TestDefaultSelectedColor;
    procedure TestSelectedColorRoundTrips;
    procedure TestProgrammaticSetDoesNotFireOnColorChange;
    procedure TestShowTextTogglePublished;
    procedure TestDialogCaptionDefault;
    procedure TestDrawContentSafeNoText;
    procedure TestDrawContentSafeWithText;
    procedure TestDrawContentSafeDegenerateRect;
  end;
implementation

procedure TTyColorButtonAccess.CallDrawContent(APainter: TTyPainter;
  const AContentRect: TRect; const AStyle: TTyStyleSet);
begin
  DrawContent(APainter, AContentRect, AStyle);
end;

procedure TColorButtonTest.HandleColorChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TColorButtonTest.TestTypeKeyStaysTyButton;
var B: TTyColorButton;
begin
  // Reuses the button token — must NOT introduce a new typeKey.
  B := TTyColorButton.Create(nil);
  try
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally B.Free; end;
end;

procedure TColorButtonTest.TestHexKnownValues;
begin
  AssertEquals('accent blue', '#3B82F6', TyColorHex(TyRGB(59, 130, 246)));
  AssertEquals('black', '#000000', TyColorHex(TyRGB(0, 0, 0)));
  AssertEquals('white', '#FFFFFF', TyColorHex(TyRGB(255, 255, 255)));
end;

procedure TColorButtonTest.TestHexIgnoresAlpha;
begin
  // Same RGB, different alpha -> identical hex (alpha is dropped, upper-case).
  AssertEquals('alpha ignored', '#3B82F6', TyColorHex(TyRGBA(59, 130, 246, 0)));
  AssertEquals('alpha ignored 2', TyColorHex(TyRGB(18, 52, 86)),
    TyColorHex(TyRGBA(18, 52, 86, 128)));
end;

procedure TColorButtonTest.TestDefaultSelectedColor;
var B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertEquals('default = accent blue $FF3B82F6',
      Integer(TyRGB(59, 130, 246)), Integer(B.SelectedColor));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestSelectedColorRoundTrips;
var B: TTyColorButtonAccess;
begin
  B := TTyColorButtonAccess.Create(nil);
  try
    B.SelectedColor := TyRGB(200, 100, 50);
    AssertEquals('round-trips', Integer(TyRGB(200, 100, 50)), Integer(B.SelectedColor));
    AssertEquals('hex reflects new colour', '#C86432', TyColorHex(B.SelectedColor));
    AssertTrue('SelectedColor published', IsPublishedProp(B, 'SelectedColor'));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestProgrammaticSetDoesNotFireOnColorChange;
var B: TTyColorButton;
begin
  // OnColorChange is dialog-driven only; a programmatic setter must not fire it.
  FChanged := 0;
  B := TTyColorButton.Create(nil);
  try
    B.OnColorChange := @HandleColorChange;
    B.SelectedColor := TyRGB(10, 20, 30);
    B.SelectedColor := TyRGB(10, 20, 30);   // no-op (same value)
    B.SelectedColor := TyRGB(40, 50, 60);
    AssertEquals('programmatic set never fires OnColorChange', 0, FChanged);
    AssertTrue('OnColorChange published', IsPublishedProp(B, 'OnColorChange'));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestShowTextTogglePublished;
var B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertFalse('ShowText default False', B.ShowText);
    B.ShowText := True;
    AssertTrue('ShowText toggles', B.ShowText);
    AssertTrue('ShowText published', IsPublishedProp(B, 'ShowText'));
  finally B.Free; end;
end;

procedure TColorButtonTest.TestDialogCaptionDefault;
var B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertEquals('DialogCaption default', 'Select Color', B.DialogCaption);
    AssertTrue('DialogCaption published', IsPublishedProp(B, 'DialogCaption'));
  finally B.Free; end;
end;

// --- headless DrawContent smoke tests (paint into a bitmap, must not raise) ---

procedure TColorButtonTest.TestDrawContentSafeNoText;
var
  B: TTyColorButtonAccess; Bmp: TBitmap; P: TTyPainter; S: TTyStyleSet;
begin
  B := TTyColorButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.SelectedColor := TyRGB(0, 200, 100);
    B.ShowText := False;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(88, 30);
    S := EmptyStyleSet;
    P := TTyPainter.Create;
    try
      P.BeginPaint(Bmp.Canvas, Rect(0, 0, 88, 30), 96);
      B.CallDrawContent(P, Rect(4, 4, 84, 26), S);
      P.EndPaint;
    finally P.Free; end;
    AssertTrue('DrawContent (no text) executed without exception', True);
  finally Bmp.Free; B.Free; end;
end;

procedure TColorButtonTest.TestDrawContentSafeWithText;
var
  B: TTyColorButtonAccess; Bmp: TBitmap; P: TTyPainter; S: TTyStyleSet;
begin
  B := TTyColorButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.SelectedColor := TyRGB(59, 130, 246);
    B.ShowText := True;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 30);
    S := EmptyStyleSet;
    S.FontSize := 12;
    S.FontWeight := 400;
    S.TextColor := TyRGB(30, 30, 30);
    P := TTyPainter.Create;
    try
      P.BeginPaint(Bmp.Canvas, Rect(0, 0, 120, 30), 96);
      B.CallDrawContent(P, Rect(4, 4, 116, 26), S);
      P.EndPaint;
    finally P.Free; end;
    AssertTrue('DrawContent (with hex text) executed without exception', True);
  finally Bmp.Free; B.Free; end;
end;

procedure TColorButtonTest.TestDrawContentSafeDegenerateRect;
var
  B: TTyColorButtonAccess; Bmp: TBitmap; P: TTyPainter; S: TTyStyleSet;
begin
  // A zero/negative content rect must be a no-op, never a crash.
  B := TTyColorButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(10, 10);
    S := EmptyStyleSet;
    P := TTyPainter.Create;
    try
      P.BeginPaint(Bmp.Canvas, Rect(0, 0, 10, 10), 96);
      B.CallDrawContent(P, Rect(5, 5, 5, 5), S);   // empty rect
      B.CallDrawContent(P, Rect(8, 8, 2, 2), S);   // inverted rect
      P.EndPaint;
    finally P.Free; end;
    AssertTrue('DrawContent tolerates a degenerate rect', True);
  finally Bmp.Free; B.Free; end;
end;

initialization
  RegisterTest(TColorButtonTest);
end.
