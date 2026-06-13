unit test.tabcontrol.scroll;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Panel, tyControls.TabControl;

type
  { Fresh white-box access subclass for the header-overflow-scroll geometry.
    Deliberately separate from the locked TTyTabControlAccess in
    test.tabcontrol.pas so the existing 408+ tests are untouched. Exposes the
    new pure-geometry helpers plus the internal affordance flag and the visible
    tab band so the into-view assertions can reference the same band the
    implementation uses. }
  TTyTabScrollAccess = class(TTyTabControl)
  public
    function ShowScrollAffordance: Boolean;
    function VisibleLeft: Integer;
    function VisibleRight: Integer;
  end;

  { Geometry tests for header overflow scroll: strip width, clamp, affordance
    rects, into-view, and a regression that a non-overflowing strip behaves
    exactly as before (shift offset 0, no affordance, max scroll 0). }
  TTyTabScrollGeometryTest = class(TTestCase)
  private
    FForm: TForm;
    FTab: TTyTabScrollAccess;
    procedure AddTabs(ACount: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOverflowReportsStripWidthAndMaxScroll;
    procedure TestSetHeaderScrollClampsHighAndLow;
    procedure TestAffordanceRectsNonEmptyOnOverflowEmptyWhenFits;
    procedure TestScrollLastIntoViewThenFirstIntoView;
    procedure TestNoOverflowRegressionUnshifted;
  end;

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

{ TTyTabScrollAccess }

function TTyTabScrollAccess.ShowScrollAffordance: Boolean;
begin
  Result := FShowScrollAffordance;
end;

function TTyTabScrollAccess.VisibleLeft: Integer;
begin
  { The left arrow overlays the start of the strip; the leftmost tab may sit at
    x=0, so the into-view left edge is the true control left. }
  Result := 0;
end;

function TTyTabScrollAccess.VisibleRight: Integer;
begin
  if FShowScrollAffordance then
    Result := FScrollRightRect.Left
  else
    Result := Width;
end;

{ TTyTabScrollGeometryTest }

procedure TTyTabScrollGeometryTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FTab := TTyTabScrollAccess.Create(FForm);
  FTab.Parent := FForm;
  FTab.Font.PixelsPerInch := 96;
end;

procedure TTyTabScrollGeometryTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyTabScrollGeometryTest.AddTabs(ACount: Integer);
var
  I: Integer;
begin
  for I := 1 to ACount do
    FTab.AddTab('Tab ' + IntToStr(I));
end;

{ (1) Many tabs in a narrow control overflow: strip width exceeds the control
  width and there is a positive maximum scroll. }
procedure TTyTabScrollGeometryTest.TestOverflowReportsStripWidthAndMaxScroll;
begin
  FTab.SetBounds(0, 0, 120, 200);
  AddTabs(12);
  AssertTrue('strip wider than control width',
    FTab.TyHeaderStripWidth > 120);
  AssertTrue('positive max header scroll', FTab.TyMaxHeaderScroll > 0);
end;

{ (2) SetHeaderScroll clamps high values to TyMaxHeaderScroll and negatives to
  0. The clamped value is observable through the shift of header 0. }
procedure TTyTabScrollGeometryTest.TestSetHeaderScrollClampsHighAndLow;
var
  MaxScroll, Base0: Integer;
begin
  FTab.SetBounds(0, 0, 120, 200);
  AddTabs(12);
  MaxScroll := FTab.TyMaxHeaderScroll;
  Base0 := FTab.TyTabHeaderRect(0).Left; // unshifted

  FTab.SetHeaderScroll(99999);
  AssertEquals('clamped high to max scroll',
    Base0 - MaxScroll, FTab.HeaderRectShifted(0).Left);

  FTab.SetHeaderScroll(-50);
  AssertEquals('clamped low to zero scroll',
    Base0, FTab.HeaderRectShifted(0).Left);
end;

{ (3) Affordance rects are non-empty when overflowing and (0,0,0,0) when the
  content fits. }
procedure TTyTabScrollGeometryTest.TestAffordanceRectsNonEmptyOnOverflowEmptyWhenFits;
var
  LR, RR: TRect;
begin
  // Overflow: 12 tabs in 120px.
  FTab.SetBounds(0, 0, 120, 200);
  AddTabs(12);
  LR := FTab.TyTabScrollLeftRect;
  RR := FTab.TyTabScrollRightRect;
  AssertTrue('left arrow rect non-empty on overflow',
    (LR.Right > LR.Left) and (LR.Bottom > LR.Top));
  AssertTrue('right arrow rect non-empty on overflow',
    (RR.Right > RR.Left) and (RR.Bottom > RR.Top));

  // Fits: drop to a roomy control with few tabs.
  FForm.Free;
  SetUp;
  FTab.SetBounds(0, 0, 300, 200);
  AddTabs(2);
  LR := FTab.TyTabScrollLeftRect;
  RR := FTab.TyTabScrollRightRect;
  AssertTrue('left arrow rect empty when fits',
    (LR.Left = 0) and (LR.Top = 0) and (LR.Right = 0) and (LR.Bottom = 0));
  AssertTrue('right arrow rect empty when fits',
    (RR.Left = 0) and (RR.Top = 0) and (RR.Right = 0) and (RR.Bottom = 0));
end;

{ (4) ScrollTabIntoView(last) brings the last header fully inside the visible
  band (its shifted right edge within visibleRight); ScrollTabIntoView(0)
  resets so the first header's shifted left edge is within visibleLeft. }
procedure TTyTabScrollGeometryTest.TestScrollLastIntoViewThenFirstIntoView;
var
  Last: Integer;
begin
  FTab.SetBounds(0, 0, 120, 200);
  AddTabs(12);
  Last := FTab.TabCount - 1;

  FTab.ScrollTabIntoView(Last);
  AssertTrue('last header right within visible right',
    FTab.HeaderRectShifted(Last).Right <= FTab.VisibleRight);

  FTab.ScrollTabIntoView(0);
  AssertTrue('first header left within visible left',
    FTab.HeaderRectShifted(0).Left >= FTab.VisibleLeft);
end;

{ (5) REGRESSION: two short tabs in a wide control do not overflow -> zero max
  scroll, no affordance, and the shifted rect equals the unshifted rect (offset
  0), proving pre-existing geometry is unchanged. }
procedure TTyTabScrollGeometryTest.TestNoOverflowRegressionUnshifted;
var
  I: Integer;
  A, B: TRect;
begin
  FTab.SetBounds(0, 0, 300, 200);
  AddTabs(2);
  AssertEquals('no max scroll when content fits', 0, FTab.TyMaxHeaderScroll);
  AssertFalse('no affordance when content fits', FTab.ShowScrollAffordance);
  for I := 0 to FTab.TabCount - 1 do
  begin
    A := FTab.HeaderRectShifted(I);
    B := FTab.TyTabHeaderRect(I);
    AssertTrue('shifted rect equals unshifted rect (offset 0) at ' + IntToStr(I),
      (A.Left = B.Left) and (A.Top = B.Top) and
      (A.Right = B.Right) and (A.Bottom = B.Bottom));
  end;
end;

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
  RegisterTest(TTyTabScrollGeometryTest);
  RegisterTest(TTabScrollGlyphTest);

end.
