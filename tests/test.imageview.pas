unit test.imageview;
{$mode objfpc}{$H+}

// Headless tests for TTyImageView derived from the plan contract
// (docs/superpowers/plans/2026-07-11-imageview.md) ONLY. The windowed control
// itself is never instantiated here -- a TTyCustomControl needs a real window
// and crashes the console runner. What IS testable is the pure surface the plan
// factors out for exactly this reason:
//   geometry : TyImageViewFitZoom / TyImageViewClamp / TyImageViewDestRect /
//              TyImageViewAnchorOffset / TyImageViewClampOffset
//   filters  : TyImageViewApplyFilters (pixel-level, non-destructive)
//   animation: TTyAnimator interpolation (wall-clock-free, Advance(ms) explicit)
// Each test is named after the contract rule it pins.

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Animation, tyControls.ImageView;

type
  TTyImageViewTest = class(TTestCase)
  private
    // Unproject a device point back to an image pixel through the SAME DestRect
    // convention the control paints with: img = (device - dst.origin) / zoom.
    function UnprojX(const ADst: TRect; ADeviceX: Integer; AZoom: Double): Double;
    function UnprojY(const ADst: TRect; ADeviceY: Integer; AZoom: Double): Double;
  published
    // --- geometry: TyImageViewFitZoom ---
    procedure TestFitZoomWidthBound;
    procedure TestFitZoomDegenerateReturnsOne;
    // --- geometry: TyImageViewClamp ---
    procedure TestClampBelowLoAboveHiInside;
    // --- geometry: TyImageViewDestRect ---
    procedure TestDestRectCenteredAndSized;
    procedure TestDestRectOffsetShiftsByOffset;
    // --- geometry: TyImageViewAnchorOffset ---
    procedure TestAnchorOffsetKeepsCursorImagePixel;
    // --- geometry: TyImageViewClampOffset ---
    procedure TestClampOffsetSmallImageCenters;
    procedure TestClampOffsetLargeImageHalfRevealBound;
    // --- filters: TyImageViewApplyFilters (pixels) ---
    procedure TestFilterGrayscaleEqualChannelsMidGrey;
    procedure TestFilterInvertComplementsChannels;
    procedure TestFilterTintFullCoversWithTintColor;
    procedure TestFilterAllOffMatchesSourceNonDestructive;
    // --- animation: TTyAnimator interpolation ---
    procedure TestAnimatorInterpolationHalfwayThenComplete;
  end;

implementation

function TTyImageViewTest.UnprojX(const ADst: TRect; ADeviceX: Integer; AZoom: Double): Double;
begin
  Result := (ADeviceX - ADst.Left) / AZoom;
end;

function TTyImageViewTest.UnprojY(const ADst: TRect; ADeviceY: Integer; AZoom: Double): Double;
begin
  Result := (ADeviceY - ADst.Top) / AZoom;
end;

{ --- TyImageViewFitZoom --- }

procedure TTyImageViewTest.TestFitZoomWidthBound;
begin
  // Plan: "the zoom that fits src entirely inside the view (contain)". A 200x100 src in a 100x100
  // view is width-bound: min(100/200, 100/100) = 0.5.
  AssertEquals('200x100 into 100x100 is width-bound -> 0.5',
    0.5, TyImageViewFitZoom(200, 100, 100, 100), 1e-9);
end;

procedure TTyImageViewTest.TestFitZoomDegenerateReturnsOne;
begin
  // Plan: "src or view degenerate (<=0) -> 1.0".
  AssertEquals('zero src width -> 1.0',  1.0, TyImageViewFitZoom(0, 100, 100, 100), 1e-9);
  AssertEquals('zero src height -> 1.0', 1.0, TyImageViewFitZoom(200, 0, 100, 100), 1e-9);
  AssertEquals('zero view width -> 1.0', 1.0, TyImageViewFitZoom(200, 100, 0, 100), 1e-9);
  AssertEquals('zero view height -> 1.0',1.0, TyImageViewFitZoom(200, 100, 100, 0), 1e-9);
end;

{ --- TyImageViewClamp --- }

procedure TTyImageViewTest.TestClampBelowLoAboveHiInside;
begin
  // Plan: "clamp to [lo,hi]".
  AssertEquals('below lo -> lo',    2.0, TyImageViewClamp(-5.0, 2.0, 8.0), 1e-9);
  AssertEquals('above hi -> hi',    8.0, TyImageViewClamp(100.0, 2.0, 8.0), 1e-9);
  AssertEquals('inside -> unchanged', 5.0, TyImageViewClamp(5.0, 2.0, 8.0), 1e-9);
end;

{ --- TyImageViewDestRect --- }

procedure TTyImageViewTest.TestDestRectCenteredAndSized;
var
  dst: TRect;
  leftMargin, rightMargin, topMargin, bottomMargin: Integer;
begin
  // Plan: the image is centred in the view (equal left/right margins) and its
  // size = round(src*zoom). 100x100 src, 200x200 view, zoom 0.5, no offset ->
  // 50x50 image centred with 75px margins all round.
  dst := TyImageViewDestRect(100, 100, 200, 200, 0.5, 0.0, 0.0);
  AssertEquals('width = round(src*zoom)',  Round(100 * 0.5), dst.Right - dst.Left);
  AssertEquals('height = round(src*zoom)', Round(100 * 0.5), dst.Bottom - dst.Top);

  leftMargin   := dst.Left;
  rightMargin  := 200 - dst.Right;
  topMargin    := dst.Top;
  bottomMargin := 200 - dst.Bottom;
  AssertEquals('equal left/right margins (centred)', leftMargin, rightMargin);
  AssertEquals('equal top/bottom margins (centred)', topMargin, bottomMargin);
end;

procedure TTyImageViewTest.TestDestRectOffsetShiftsByOffset;
var
  dst0, dst1: TRect;
begin
  // Plan: "a pan offset shifts it by the offset."
  dst0 := TyImageViewDestRect(100, 100, 200, 200, 0.5, 0.0, 0.0);
  dst1 := TyImageViewDestRect(100, 100, 200, 200, 0.5, 10.0, -20.0);
  AssertEquals('offset +10 shifts left by 10', dst0.Left + 10, dst1.Left);
  AssertEquals('offset -20 shifts top by -20', dst0.Top - 20, dst1.Top);
  // Extents are unchanged by a pure pan.
  AssertEquals('pan keeps width',  dst0.Right - dst0.Left, dst1.Right - dst1.Left);
  AssertEquals('pan keeps height', dst0.Bottom - dst0.Top, dst1.Bottom - dst1.Top);
end;

{ --- TyImageViewAnchorOffset --- }

procedure TTyImageViewTest.TestAnchorOffsetKeepsCursorImagePixel;
var
  newOffX, newOffY: Double;
  dstOld, dstNew: TRect;
  imgOldX, imgOldY, imgNewX, imgNewY: Double;
const
  Z0 = 1.0;
  Z1 = 2.0;
  SrcW = 100; SrcH = 100;
  ViewW = 200; ViewH = 200;
  AnchorX = 140; AnchorY = 140;
begin
  // Plan: zooming about a cursor point keeps the IMAGE pixel under the cursor
  // fixed. Unproject the cursor with the OLD and the NEW zoom/offset (through
  // the same DestRect the control draws with) and assert equal within 1px.
  dstOld := TyImageViewDestRect(SrcW, SrcH, ViewW, ViewH, Z0, 0.0, 0.0);
  imgOldX := UnprojX(dstOld, AnchorX, Z0);
  imgOldY := UnprojY(dstOld, AnchorY, Z0);

  TyImageViewAnchorOffset(Z0, Z1, AnchorX, AnchorY, ViewW, ViewH,
    0.0, 0.0, newOffX, newOffY);

  dstNew := TyImageViewDestRect(SrcW, SrcH, ViewW, ViewH, Z1, newOffX, newOffY);
  imgNewX := UnprojX(dstNew, AnchorX, Z1);
  imgNewY := UnprojY(dstNew, AnchorY, Z1);

  AssertEquals('cursor image-pixel X unchanged by zoom', imgOldX, imgNewX, 1.0);
  AssertEquals('cursor image-pixel Y unchanged by zoom', imgOldY, imgNewY, 1.0);
end;

{ --- TyImageViewClampOffset --- }

procedure TTyImageViewTest.TestClampOffsetSmallImageCenters;
var
  offX, offY: Double;
begin
  // Plan: "image smaller than viewport -> centred (off=0)". 100x100 src at zoom 0.5 = 50x50,
  // smaller than the 200x200 view -> any requested pan clamps to 0 (centred).
  offX := 50.0;
  offY := -37.0;
  TyImageViewClampOffset(100, 100, 200, 200, 0.5, offX, offY);
  AssertEquals('small image X centres to 0', 0.0, offX, 1e-9);
  AssertEquals('small image Y centres to 0', 0.0, offY, 1e-9);
end;

procedure TTyImageViewTest.TestClampOffsetLargeImageHalfRevealBound;
var
  offX, offY, bound: Double;
begin
  // Plan: "larger -> never reveal more than half the empty gap (off limited to +/-(scaled-view)/2)".
  // 400x400 src at zoom 1.0 in a 200x200 view: scaled=400, bound=(400-200)/2=100.
  bound := (400 * 1.0 - 200) / 2;   // 100

  // A far-past-bound request clamps to the bound (cannot pan past half-reveal).
  offX := 10000.0;
  offY := -10000.0;
  TyImageViewClampOffset(400, 400, 200, 200, 1.0, offX, offY);
  AssertTrue('over-pan X clamped within +/- bound', Abs(offX) <= bound + 1e-6);
  AssertTrue('over-pan Y clamped within +/- bound', Abs(offY) <= bound + 1e-6);
  AssertEquals('positive over-pan lands on +bound', bound, offX, 1.0);
  AssertEquals('negative over-pan lands on -bound', -bound, offY, 1.0);

  // A within-bound offset is left untouched.
  offX := bound / 2;
  offY := -bound / 2;
  TyImageViewClampOffset(400, 400, 200, 200, 1.0, offX, offY);
  AssertEquals('within-bound X unchanged', bound / 2, offX, 1e-9);
  AssertEquals('within-bound Y unchanged', -bound / 2, offY, 1e-9);
end;

{ --- TyImageViewApplyFilters (pixels) --- }

procedure TTyImageViewTest.TestFilterGrayscaleEqualChannelsMidGrey;
var
  src, outp: TBGRABitmap;
  px: TBGRAPixel;
begin
  // Plan: "after grayscale every pixel has r=g=b on a small image"; a pure blue -> a mid-grey (r=g=b,
  // not pinned to 0 or 255).
  src := TBGRABitmap.Create(4, 4, BGRA(0, 0, 255, 255));
  try
    outp := TyImageViewApplyFilters(src, {gray}True, 0, False, False, clNone, 0);
    try
      px := outp.GetPixel(1, 1);
      AssertEquals('grayscale r=g', px.red, px.green);
      AssertEquals('grayscale g=b', px.green, px.blue);
      AssertTrue('blue -> mid-grey, not black', px.red > 0);
      AssertTrue('blue -> mid-grey, not white', px.red < 255);
    finally
      outp.Free;
    end;
  finally
    src.Free;
  end;
end;

procedure TTyImageViewTest.TestFilterInvertComplementsChannels;
var
  src, outp: TBGRABitmap;
  px: TBGRAPixel;
begin
  // Plan: "after invert r'=255-r" (and g'/b' likewise).
  src := TBGRABitmap.Create(4, 4, BGRA(10, 20, 30, 255));
  try
    outp := TyImageViewApplyFilters(src, False, 0, False, {invert}True, clNone, 0);
    try
      px := outp.GetPixel(2, 2);
      AssertEquals('invert red  = 255-10', 245, px.red);
      AssertEquals('invert green= 255-20', 235, px.green);
      AssertEquals('invert blue = 255-30', 225, px.blue);
    finally
      outp.Free;
    end;
  finally
    src.Free;
  end;
end;

procedure TTyImageViewTest.TestFilterTintFullCoversWithTintColor;
var
  src, outp: TBGRABitmap;
  px: TBGRAPixel;
  tint: TColor;
begin
  // Plan: "tint amount=100 fully covers with the tint colour" -- every pixel becomes the tint.
  tint := RGBToColor(200, 50, 100);
  src := TBGRABitmap.Create(4, 4, BGRA(10, 20, 30, 255));
  try
    outp := TyImageViewApplyFilters(src, False, 0, False, False, tint, 100);
    try
      px := outp.GetPixel(3, 0);
      AssertEquals('tint full red',   200, px.red);
      AssertEquals('tint full green',  50, px.green);
      AssertEquals('tint full blue',  100, px.blue);
    finally
      outp.Free;
    end;
  finally
    src.Free;
  end;
end;

procedure TTyImageViewTest.TestFilterAllOffMatchesSourceNonDestructive;
var
  src, outp: TBGRABitmap;
  x, y: Integer;
  sp, op: TBGRAPixel;
begin
  // Plan: "all off -> return a copy of ASource" AND "ASource unchanged" (non-destructive).
  // Distinct per-pixel colours so an accidental fill/mutation would be caught.
  src := TBGRABitmap.Create(4, 4);
  for y := 0 to 3 do
    for x := 0 to 3 do
      src.SetPixel(x, y, BGRA(x * 30, y * 30, 100, 255));

  try
    outp := TyImageViewApplyFilters(src, False, 0, False, False, clNone, 0);
    try
      for y := 0 to 3 do
        for x := 0 to 3 do
        begin
          op := outp.GetPixel(x, y);
          // Output reproduces the source pixels exactly.
          AssertEquals(Format('all-off out red @%d,%d', [x, y]),   x * 30, op.red);
          AssertEquals(Format('all-off out green @%d,%d', [x, y]), y * 30, op.green);
          AssertEquals(Format('all-off out blue @%d,%d', [x, y]),  100,    op.blue);
          // Source is untouched: filters must not mutate FSource in place.
          sp := src.GetPixel(x, y);
          AssertEquals(Format('source red intact @%d,%d', [x, y]),   x * 30, sp.red);
          AssertEquals(Format('source green intact @%d,%d', [x, y]), y * 30, sp.green);
          AssertEquals(Format('source blue intact @%d,%d', [x, y]),  100,    sp.blue);
        end;
      // A distinct buffer, not the same object handed back.
      AssertTrue('filters return a NEW bitmap (caller-owned)', outp <> src);
    finally
      outp.Free;
    end;
  finally
    src.Free;
  end;
end;

{ --- TTyAnimator interpolation (wall-clock-free) --- }

procedure TTyImageViewTest.TestAnimatorInterpolationHalfwayThenComplete;
var
  a: TTyAnimator;
  eased, v: Single;
const
  FromV = 100.0;
  ToV = 300.0;
begin
  // Plan: "TyAnimatorInit + manual Advance(halfway) -> TyLerpF(from,to,eased) lies
  // between (from,to); after Advance reaches the duration Running=False and value=to."
  a := TyAnimatorInit(200, teEaseOutCubic);

  a.Advance(100);                     // half the 200ms duration
  eased := a.Eased;
  AssertTrue('running mid-animation', a.Running);
  AssertTrue('eased strictly > 0', eased > 0.0);
  AssertTrue('eased strictly < 1', eased < 1.0);

  v := TyLerpF(FromV, ToV, eased);
  AssertTrue('lerp strictly above from', v > FromV);
  AssertTrue('lerp strictly below to', v < ToV);

  a.Advance(100);                     // reaches the full 200ms
  AssertFalse('not running at end', a.Running);
  AssertEquals('eased lands on 1.0', 1.0, a.Eased, 1e-6);
  v := TyLerpF(FromV, ToV, a.Eased);
  AssertEquals('lerp value == to at completion', ToV, v, 1e-4);
end;

initialization
  RegisterTest(TTyImageViewTest);
end.
