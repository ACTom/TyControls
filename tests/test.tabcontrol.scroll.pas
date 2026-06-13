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
{ tgArrowLeft: the chevron tip sits at the left-mid edge. Assert a glyph pixel
  exists in the left-mid region and the far-right column near the top stays
  background (alpha 0). }
begin
  MakePainter(24, 24, 96);
  FPainter.DrawGlyph(Rect(0, 0, 24, 24), tgArrowLeft, TyRGBA(0, 0, 0, 255), 2);
  AssertTrue('left-mid is glyph-colored',
    GlyphInBox(0, 8, 8, 16));
  AssertEquals('far-right top is background',
    0, PixelAt(23, 1).alpha);
end;

procedure TTabScrollGlyphTest.TestArrowRightPointsRight;
{ tgArrowRight mirrors tgArrowLeft: the chevron tip sits at the right-mid edge.
  Assert a glyph pixel exists in the right-mid region and the far-left column
  near the top stays background (alpha 0). }
begin
  MakePainter(24, 24, 96);
  FPainter.DrawGlyph(Rect(0, 0, 24, 24), tgArrowRight, TyRGBA(0, 0, 0, 255), 2);
  AssertTrue('right-mid is glyph-colored',
    GlyphInBox(16, 8, 23, 16));
  AssertEquals('far-left top is background',
    0, PixelAt(0, 1).alpha);
end;

initialization
  RegisterTest(TTabScrollGlyphTest);

end.
