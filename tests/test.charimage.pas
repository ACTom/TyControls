unit test.charimage;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, Forms, Controls, Graphics,
  tyControls.Base, tyControls.Types, tyControls.IconFont, tyControls.CharImage;
type
  { Exposes the protected RenderTo so the paint path is exercisable headlessly. }
  TCharImageAccess = class(TTyCharImage)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TCharImageTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestPropertiesRoundTrip;
    procedure TestIconFontRoundTripAndFreeNotification;
    procedure TestSettersDoNotRaise;
    procedure TestGlyphPxHelperExplicit;
    procedure TestGlyphPxHelperAutoFit;
    procedure TestPaintSafeWithFont;
    procedure TestPaintSafeWithNilFont;
  end;
implementation

procedure TCharImageAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TCharImageTest.TestTypeKey;
var
  C: TTyCharImage;
begin
  // Reuses the label token — introduces no new .tycss selector.
  C := TTyCharImage.Create(nil);
  try
    AssertEquals('TyCharImage', (C as ITyStyleable).GetStyleTypeKey);
  finally
    C.Free;
  end;
end;

procedure TCharImageTest.TestDefaults;
var
  C: TTyCharImage;
begin
  C := TTyCharImage.Create(nil);
  try
    AssertEquals('GlyphSize default 0 (auto-fit)', 0, C.GlyphSize);
    AssertTrue('GlyphColor default is the theme sentinel',
      C.GlyphColor = TyGlyphColorDefault);
    AssertEquals('GlyphName default empty', '', C.GlyphName);
    AssertTrue('IconFont default nil', C.IconFont = nil);
  finally
    C.Free;
  end;
end;

procedure TCharImageTest.TestPropertiesRoundTrip;
var
  C: TTyCharImage;
begin
  C := TTyCharImage.Create(nil);
  try
    C.GlyphName := 'save';
    C.GlyphSize := 24;
    C.GlyphColor := TyRGB(200, 40, 40);
    AssertEquals('GlyphName round-trips', 'save', C.GlyphName);
    AssertEquals('GlyphSize round-trips', 24, C.GlyphSize);
    AssertTrue('GlyphColor round-trips', C.GlyphColor = TyRGB(200, 40, 40));

    // Negative GlyphSize clamps to 0 (auto-fit), never a bad size.
    C.GlyphSize := -5;
    AssertEquals('negative GlyphSize clamps to 0', 0, C.GlyphSize);
  finally
    C.Free;
  end;
end;

procedure TCharImageTest.TestIconFontRoundTripAndFreeNotification;
var
  C: TTyCharImage;
  Font: TTyIconFont;
begin
  C := TTyCharImage.Create(nil);
  Font := TTyIconFont.Create(nil);
  try
    Font.MapGlyph('save', $F0C7);
    AssertTrue('IconFont has the mapped glyph', Font.HasGlyph('save'));

    C.IconFont := Font;
    AssertSame('IconFont round-trips', Font, C.IconFont);

    // Freeing the referenced font must nil the reference (FreeNotification).
    Font.Free;
    Font := nil;
    AssertTrue('IconFont nilled after the font is freed', C.IconFont = nil);
  finally
    Font.Free;   // no-op when already freed/nil
    C.Free;
  end;
end;

procedure TCharImageTest.TestSettersDoNotRaise;
var
  C: TTyCharImage;
  Font: TTyIconFont;
begin
  C := TTyCharImage.Create(nil);
  Font := TTyIconFont.Create(nil);
  try
    Font.MapGlyph('save', $F0C7);
    // Exercise every setter; none should raise, in any order.
    C.GlyphName := 'save';
    C.GlyphSize := 16;
    C.IconFont := Font;
    C.GlyphColor := TyRGB(10, 20, 30);
    C.GlyphName := '';
    C.GlyphSize := 0;
    C.IconFont := nil;
    AssertTrue('all setters executed without raising', True);
  finally
    Font.Free;
    C.Free;
  end;
end;

procedure TCharImageTest.TestGlyphPxHelperExplicit;
begin
  // An explicit (already-scaled) size wins regardless of the client box.
  AssertEquals('explicit size wins over box', 24,
    TyCharImageGlyphPx(100, 100, 24, 2));
  AssertEquals('explicit size wins even in a tiny box', 20,
    TyCharImageGlyphPx(4, 4, 20, 2));
end;

procedure TCharImageTest.TestGlyphPxHelperAutoFit;
begin
  // Size 0 -> auto-fit: smaller side minus 2*pad.
  AssertEquals('auto-fit uses smaller side minus padding', 40 - 2 * 2,
    TyCharImageGlyphPx(60, 40, 0, 2));
  AssertEquals('auto-fit on a square box', 30 - 2 * 3,
    TyCharImageGlyphPx(30, 30, 0, 3));
  // Degenerate: padding exceeds the box -> floored at 0, never negative.
  AssertEquals('auto-fit floors at 0', 0,
    TyCharImageGlyphPx(4, 4, 0, 8));
end;

procedure TCharImageTest.TestPaintSafeWithFont;
var
  C: TCharImageAccess;
  Font: TTyIconFont;
  Bmp: TBitmap;
begin
  // Full paint path with a mapped glyph. No real font family is registered, so
  // RenderGlyph yields an empty transparent bitmap — the composite must still be
  // safe. (Real glyph pixels need an installed font + a machine.)
  C := TCharImageAccess.Create(nil);
  Font := TTyIconFont.Create(nil);
  Bmp := TBitmap.Create;
  try
    Font.MapGlyph('save', $F0C7);
    C.IconFont := Font;
    C.GlyphName := 'save';
    C.GlyphSize := 24;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(48, 48);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 48, 48), 96);
    AssertTrue('RenderTo with a font executed without exception', True);

    // Auto-fit path (GlyphSize=0) must also be safe.
    C.GlyphSize := 0;
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 48, 48), 96);
    AssertTrue('auto-fit RenderTo executed without exception', True);
  finally
    Bmp.Free;
    Font.Free;
    C.Free;
  end;
end;

procedure TCharImageTest.TestPaintSafeWithNilFont;
var
  C: TCharImageAccess;
  Bmp: TBitmap;
begin
  // No IconFont, and a non-empty GlyphName: must draw nothing and never crash.
  C := TCharImageAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    C.GlyphName := 'save';   // set, but no font assigned
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(32, 32);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 32, 32), 96);
    AssertTrue('RenderTo with nil IconFont is a safe no-op', True);

    // Empty GlyphName is likewise a safe no-op.
    C.GlyphName := '';
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 32, 32), 96);
    AssertTrue('RenderTo with empty GlyphName is a safe no-op', True);
  finally
    Bmp.Free;
    C.Free;
  end;
end;

initialization
  RegisterTest(TCharImageTest);
end.
