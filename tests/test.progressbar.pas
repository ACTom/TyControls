unit test.progressbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ProgressBar;
type
  TProgressBarAccess = class(TTyProgressBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TTyProgressBarGeometryTest = class(TTestCase)
  published
    procedure TestPosZeroGivesWidthZero;
    procedure TestPosMidGivesHalfWidth;
    procedure TestPosMaxGivesFullWidth;
    procedure TestMaxEqualsMinGivesWidthZero;
    procedure TestPosAboveMaxGivesFull;
    procedure TestPosBelowMinGivesZero;
  end;

  TTyProgressBarControlTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyProgressBar;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestPositionClampsToMax;
    procedure TestPositionClampsToMin;
    procedure TestSetSamePositionNoInvalidate;
  end;

  TTyProgressBarPixelTest = class(TTestCase)
  published
    procedure TestFillPixelBlueAt50Percent;
    procedure TestPartialFillRoundsLeadingLeftCornersOnly;
    procedure TestFullFillRoundsTrailingCorners;
  end;

implementation

procedure TProgressBarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ TTyProgressBarGeometryTest }

procedure TTyProgressBarGeometryTest.TestPosZeroGivesWidthZero;
var
  R: TRect;
begin
  R := TyProgressFillRect(Rect(0, 0, 200, 20), 0, 100, 0);
  AssertEquals('fill width = 0 at Pos=0', 0, R.Right - R.Left);
end;

procedure TTyProgressBarGeometryTest.TestPosMidGivesHalfWidth;
var
  R: TRect;
begin
  R := TyProgressFillRect(Rect(0, 0, 200, 20), 0, 100, 50);
  AssertEquals('fill right = 100 at Pos=50', 100, R.Right);
  AssertEquals('fill left = 0', 0, R.Left);
end;

procedure TTyProgressBarGeometryTest.TestPosMaxGivesFullWidth;
var
  R: TRect;
begin
  R := TyProgressFillRect(Rect(0, 0, 200, 20), 0, 100, 100);
  AssertEquals('fill right = 200 at Pos=Max', 200, R.Right);
end;

procedure TTyProgressBarGeometryTest.TestMaxEqualsMinGivesWidthZero;
var
  R: TRect;
begin
  R := TyProgressFillRect(Rect(0, 0, 200, 20), 50, 50, 50);
  AssertEquals('degenerate: Max=Min gives width 0', 0, R.Right - R.Left);
end;

procedure TTyProgressBarGeometryTest.TestPosAboveMaxGivesFull;
var
  R: TRect;
begin
  // Pure fn does NOT clamp — just compute with given values: Pos>Max → full
  R := TyProgressFillRect(Rect(0, 0, 200, 20), 0, 100, 150);
  AssertEquals('Pos > Max → fill right = 200', 200, R.Right);
end;

procedure TTyProgressBarGeometryTest.TestPosBelowMinGivesZero;
var
  R: TRect;
begin
  // Pure fn: Pos < Min → width 0
  R := TyProgressFillRect(Rect(0, 0, 200, 20), 0, 100, -10);
  AssertEquals('Pos < Min → fill width 0', 0, R.Right - R.Left);
end;

{ TTyProgressBarControlTest }

procedure TTyProgressBarControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 100);
  FBar := TTyProgressBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.SetBounds(0, 0, 200, 20);
  FBar.Font.PixelsPerInch := 96;
end;

procedure TTyProgressBarControlTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyProgressBarControlTest.TestTypeKey;
begin
  AssertEquals('TyProgressBar', (FBar as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyProgressBarControlTest.TestPositionClampsToMax;
begin
  FBar.Max := 100;
  FBar.Position := 150;
  AssertEquals('Position clamped to Max=100', 100, FBar.Position);
end;

procedure TTyProgressBarControlTest.TestPositionClampsToMin;
begin
  FBar.Min := 0;
  FBar.Position := -5;
  AssertEquals('Position clamped to Min=0', 0, FBar.Position);
end;

procedure TTyProgressBarControlTest.TestSetSamePositionNoInvalidate;
begin
  FBar.Position := 50;
  FBar.Position := 50;  // second set should not crash / be idempotent
  AssertEquals('Position stays 50', 50, FBar.Position);
end;

{ TTyProgressBarPixelTest }

procedure TTyProgressBarPixelTest.TestFillPixelBlueAt50Percent;
{ Stylesheet: track dark, fill blue (#3B82F6).
  ProgressBar 200x20, Pos=50 (50% fill) → right half is fill, left half too:
  Actually Pos=50/100 → fill covers 0..100.
  - Pixel at (50, 10) is inside the fill => blue-dominant (B>180, R<120)
  - Pixel at (150, 10) is outside the fill => NOT blue-dominant
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  Bar: TProgressBarAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxFill, PxTrack: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyProgressBar { background: #202020; border-width: 0px; border-radius: 0px; }' +
      'TyProgressFill { background: #3B82F6; border-radius: 0px; }');
    Bar := TProgressBarAccess.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.Position := 50;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 20);
    Bar.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 20), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxFill  := Reread.GetPixel(50, 10);   // inside fill (0..100)
      PxTrack := Reread.GetPixel(150, 10);  // outside fill (100..200)

      AssertTrue('fill pixel: blue > 180 (blue-dominant)', PxFill.blue > 180);
      AssertTrue('fill pixel: red < 120 (not red)',        PxFill.red < 120);

      AssertTrue('track pixel: NOT blue-dominant (B <= R+80)', PxTrack.blue <= PxTrack.red + 80);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TTyProgressBarPixelTest.TestPartialFillRoundsLeadingLeftCornersOnly;
{ Partial fill (50%) with a large border-radius: only the LEFT (origin) corners
  round; the RIGHT (leading) edge stays SQUARE so the mid-track edge is a clean
  vertical line, not a floating pill.
  Track 200x20, border-width 0, radius 10. At Pos=50/100 fill covers x=0..100.
  - Fill LEFT-top corner (2,2) is rounded => track/bg shows => NOT blue-dominant.
  - Fill RIGHT-top corner (97,2) is square => fill shows => blue-dominant.
  - Center (50,10) is fill => blue-dominant. }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Bar: TProgressBarAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxLeftCorner, PxRightCorner, PxCenter: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyProgressBar { background: #202020; border-width: 0px; border-radius: 10px; }' +
      'TyProgressFill { background: #3B82F6; border-radius: 10px; }');
    Bar := TProgressBarAccess.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.Position := 50;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 20);
    Bar.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 20), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxLeftCorner  := Reread.GetPixel(2, 2);    // rounded leading-from-origin corner
      PxRightCorner := Reread.GetPixel(97, 2);   // square leading edge at mid-track
      PxCenter      := Reread.GetPixel(50, 10);  // interior of fill

      AssertTrue('left-top corner rounded => NOT blue (track shows)',
        PxLeftCorner.blue <= PxLeftCorner.red + 80);
      AssertTrue('right-top corner square => blue (fill shows)',
        PxRightCorner.blue > 180);
      AssertTrue('center is fill => blue',
        PxCenter.blue > 180);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TTyProgressBarPixelTest.TestFullFillRoundsTrailingCorners;
{ Full fill (100%): the fill matches the track, so ALL four corners round again.
  The trailing (right-top) corner that was square at 50% is now rounded.
  Track 200x20, radius 10, fill covers x=0..200.
  - Fill RIGHT-top corner (197,2) is rounded => track/bg shows => NOT blue. }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Bar: TProgressBarAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxRightCorner, PxCenter: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyProgressBar { background: #202020; border-width: 0px; border-radius: 10px; }' +
      'TyProgressFill { background: #3B82F6; border-radius: 10px; }');
    Bar := TProgressBarAccess.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.Position := 100;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 20);
    Bar.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 20), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxRightCorner := Reread.GetPixel(197, 2);  // now rounded trailing corner
      PxCenter      := Reread.GetPixel(100, 10); // interior of fill

      AssertTrue('right-top corner rounded at full => NOT blue (track shows)',
        PxRightCorner.blue <= PxRightCorner.red + 80);
      AssertTrue('center is fill => blue',
        PxCenter.blue > 180);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyProgressBarGeometryTest);
  RegisterTest(TTyProgressBarControlTest);
  RegisterTest(TTyProgressBarPixelTest);
end.
