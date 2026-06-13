unit test.tabcontrol.scroll;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter;

type
  { Painter probe for the new tab-scroll arrow glyphs. The directional asserts
    prove the polyline chevron points the correct way: tgArrowLeft has its tip
    toward the left-mid edge (so a far-right pixel stays background), and
    tgArrowRight mirrors it (tip toward the right-mid edge, far-left stays
    background). }
  TTabScrollGlyphTest = class(TTestCase)
  private
    FHost: TBitmap;
    FPainter: TTyPainter;
    procedure MakePainter(AWidth, AHeight, APPI: Integer);
    procedure FreePainter;
    function PixelAt(X, Y: Integer): TBGRAPixel;
    // True if any pixel inside the (inclusive) box has alpha above threshold.
    function GlyphInBox(L, T, R, B: Integer): Boolean;
  protected
    procedure TearDown; override;
  published
    procedure TestArrowLeftPointsLeft;
    procedure TestArrowRightPointsRight;
  end;

implementation

procedure TTabScrollGlyphTest.MakePainter(AWidth, AHeight, APPI: Integer);
begin
  FHost := TBitmap.Create;
  FHost.SetSize(AWidth, AHeight);
  FPainter := TTyPainter.Create;
  FPainter.BeginPaint(FHost.Canvas, Rect(0, 0, AWidth, AHeight), APPI);
end;

procedure TTabScrollGlyphTest.FreePainter;
begin
  if Assigned(FPainter) then
  begin
    FPainter.EndPaint;
    FreeAndNil(FPainter);
  end;
  FreeAndNil(FHost);
end;

function TTabScrollGlyphTest.PixelAt(X, Y: Integer): TBGRAPixel;
begin
  Result := FPainter.Bitmap.GetPixel(X, Y);
end;

function TTabScrollGlyphTest.GlyphInBox(L, T, R, B: Integer): Boolean;
var
  x, y: Integer;
begin
  Result := False;
  for y := T to B do
    for x := L to R do
      if PixelAt(x, y).alpha > 100 then
        Exit(True);
end;

procedure TTabScrollGlyphTest.TearDown;
begin
  FreePainter;
  inherited TearDown;
end;

procedure TTabScrollGlyphTest.TestArrowLeftPointsLeft;
{ tgArrowLeft must POINT LEFT: its chevron arms diverge on the LEFT half, well
  above the horizontal shaft. The discriminating assertions sample boxes in the
  rows y=7..10 -- strictly ABOVE the shaft rows (y=cy=11..12 at PPI=96, Rect
  0,0,24,24) -- so the full-width shaft cannot satisfy them. A left-pointing
  chevron paints in the LEFT off-shaft box and leaves the RIGHT off-shaft box
  empty; a wrongly right-pointing chevron would fail BOTH. }
begin
  MakePainter(24, 24, 96);
  FPainter.DrawGlyph(Rect(0, 0, 24, 24), tgArrowLeft, TyRGBA(0, 0, 0, 255), 2);
  // Chevron arm present on the left, above the shaft.
  AssertTrue('left chevron arm is glyph-colored (off-shaft)',
    GlyphInBox(4, 7, 10, 10));
  // No chevron on the right above the shaft: proves the tip is NOT to the right.
  AssertFalse('right region above shaft is background (chevron does not point right)',
    GlyphInBox(14, 7, 19, 10));
  // Cross-check the mirrored rows below the shaft behave the same way.
  AssertTrue('left chevron arm present below shaft',
    GlyphInBox(4, 13, 10, 16));
  AssertFalse('right region below shaft is background',
    GlyphInBox(14, 13, 19, 16));
end;

procedure TTabScrollGlyphTest.TestArrowRightPointsRight;
{ tgArrowRight mirrors tgArrowLeft and must POINT RIGHT: its chevron arms
  diverge on the RIGHT half, above/below the shaft. Same off-shaft sampling
  strategy (rows y=7..10 and y=13..16, away from the y=cy shaft) so the
  full-width shaft is irrelevant to the directional verdict. A right-pointing
  chevron paints in the RIGHT off-shaft box and leaves the LEFT off-shaft box
  empty; a wrongly left-pointing chevron would fail BOTH. }
begin
  MakePainter(24, 24, 96);
  FPainter.DrawGlyph(Rect(0, 0, 24, 24), tgArrowRight, TyRGBA(0, 0, 0, 255), 2);
  // Chevron arm present on the right, above the shaft.
  AssertTrue('right chevron arm is glyph-colored (off-shaft)',
    GlyphInBox(14, 7, 19, 10));
  // No chevron on the left above the shaft: proves the tip is NOT to the left.
  AssertFalse('left region above shaft is background (chevron does not point left)',
    GlyphInBox(4, 7, 10, 10));
  // Cross-check the mirrored rows below the shaft.
  AssertTrue('right chevron arm present below shaft',
    GlyphInBox(14, 13, 19, 16));
  AssertFalse('left region below shaft is background',
    GlyphInBox(4, 13, 10, 16));
end;

initialization
  RegisterTest(TTabScrollGlyphTest);

end.
