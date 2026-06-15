unit test.controls.scrollbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  Forms, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.ScrollBar;
type
  TTyScrollGeometryTest = class(TTestCase)
  published
    procedure TestVerticalThumbAtTop;
    procedure TestVerticalThumbAtBottom;
    procedure TestVerticalThumbMidway;
    procedure TestHorizontalThumbAtTop;
    procedure TestZeroRangeFillsTrack;
    procedure TestScrollTrackInsetGeometry;
  end;

  TTyScrollBarDragTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyScrollBar;
    FChanges: Integer;
    procedure OnBarChange(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDragMovesPosition;
    procedure TestDragFiresOnChange;
    procedure TestDragClampsAtMax;
    procedure TestPaintSmoke;
  end;

  TTyScrollBarThumbColorTest = class(TTestCase)
  published
    procedure TestThumbPixelUsesTextColor;
  end;

  TTyScrollBarMouseTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThumbDragMovesPosition;
    procedure TestTrackClickBelowThumbPagesDown;
    procedure TestDisabledScrollbarMouseIgnored;
    procedure TestArrowButtonsStepSmallChange;
    procedure TestScrollBarKeyboard;
  end;

implementation
type
  TScrollAccess = class(TTyScrollBar)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallMouseDown(Btn: TMouseButton; X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseUp(Btn: TMouseButton; X, Y: Integer);
    procedure DoMouseDown(Shift: TShiftState; X, Y: Integer);
    procedure DoKeyDown(Key: Word; Shift: TShiftState);
  end;
procedure TScrollAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;
procedure TScrollAccess.CallMouseDown(Btn: TMouseButton; X, Y: Integer);
begin
  MouseDown(Btn, [], X, Y);
end;
procedure TScrollAccess.CallMouseMove(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;
procedure TScrollAccess.CallMouseUp(Btn: TMouseButton; X, Y: Integer);
begin
  MouseUp(Btn, [], X, Y);
end;
procedure TScrollAccess.DoMouseDown(Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(mbLeft, Shift, X, Y);
end;
procedure TScrollAccess.DoKeyDown(Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;
procedure TTyScrollGeometryTest.TestVerticalThumbAtTop;
var
  R: TRect;
begin
  // track 0,0..20,200 ; range 0..100 ; page 25 ; pos 0
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 0, 25);
  AssertEquals('thumb top at position 0', 0, R.Top);
  AssertEquals('thumb left spans track', 0, R.Left);
  AssertEquals('thumb right spans track', 20, R.Right);
  // 25/(100-0+25)=25/125=0.2 of 200 = 40
  AssertEquals('thumb height = page fraction of track', 40, R.Bottom - R.Top);
end;
procedure TTyScrollGeometryTest.TestVerticalThumbAtBottom;
var
  R: TRect;
begin
  // pos 100 is max (range 0..100, page 25 -> effective max 100)
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 100, 25);
  AssertEquals('thumb bottom hugs track end', 200, R.Bottom);
  AssertEquals('thumb height stays page-sized', 40, R.Bottom - R.Top);
end;
procedure TTyScrollGeometryTest.TestVerticalThumbMidway;
var
  R: TRect;
begin
  // pos 50 of travel 100 -> 0.5 of free space (200-40=160) -> top 80
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 50, 25);
  AssertEquals('thumb top at half travel', 80, R.Top);
  AssertEquals('thumb height stays page-sized', 40, R.Bottom - R.Top);
end;
procedure TTyScrollGeometryTest.TestHorizontalThumbAtTop;
var
  R: TRect;
begin
  R := TyScrollThumbRect(Rect(0, 0, 200, 20), sbHorizontal, 0, 100, 0, 25);
  AssertEquals('horizontal thumb left at position 0', 0, R.Left);
  AssertEquals('horizontal thumb top spans track', 0, R.Top);
  AssertEquals('horizontal thumb bottom spans track', 20, R.Bottom);
  AssertEquals('horizontal thumb width = page fraction', 40, R.Right - R.Left);
end;
procedure TTyScrollGeometryTest.TestZeroRangeFillsTrack;
var
  R: TRect;
begin
  // min=max -> nothing to scroll, thumb fills whole track
  R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 5, 5, 5, 10);
  AssertEquals('degenerate range: thumb top is track top', 0, R.Top);
  AssertEquals('degenerate range: thumb fills track', 200, R.Bottom);
end;
procedure TTyScrollGeometryTest.TestScrollTrackInsetGeometry;
begin
  AssertEquals('vertical button size = width', 16, TyScrollButtonSize(Rect(0,0,16,160), sbVertical));
  AssertEquals('horizontal button size = height', 12, TyScrollButtonSize(Rect(0,0,200,12), sbHorizontal));
  // vertical: track insets top+bottom by button size
  AssertEquals('v track top', 16, TyScrollTrackRect(Rect(0,0,16,160), sbVertical, 16).Top);
  AssertEquals('v track bottom', 144, TyScrollTrackRect(Rect(0,0,16,160), sbVertical, 16).Bottom);
  // degenerate: too short -> whole client (no buttons)
  AssertEquals('degenerate keeps full', 0, TyScrollTrackRect(Rect(0,0,16,20), sbVertical, 16).Top);
  AssertEquals('degenerate keeps full2', 20, TyScrollTrackRect(Rect(0,0,16,20), sbVertical, 16).Bottom);
end;
procedure TTyScrollBarDragTest.OnBarChange(Sender: TObject);
begin
  Inc(FChanges);
end;
procedure TTyScrollBarDragTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FBar := TTyScrollBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Kind := sbVertical;
  FBar.SetBounds(0, 0, 16, 200);
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.PageSize := 25;
  FBar.Position := 0;
  FChanges := 0;
  FBar.OnChange := @OnBarChange;
end;
procedure TTyScrollBarDragTest.TearDown;
begin
  FForm.Free;
end;
procedure TTyScrollBarDragTest.TestDragMovesPosition;
begin
  // Coords account for the inset track (16px buttons at each end on a 16x200
  // vertical bar -> track y in [16,184), len 168, thumb ~33, FreeSpace ~135,
  // TrackStart=16). Grab at thumb top (y=16, pos 0) and drag down into the
  // track to land at the mid position: ((84-16)*100) div 135 = 50.
  FBar.BeginThumbDrag(16);
  FBar.DragThumbTo(84);
  AssertEquals('drag of free-space moves to mid position', 50, FBar.Position);
end;
procedure TTyScrollBarDragTest.TestDragFiresOnChange;
begin
  // Grab the thumb at its top (y=16, the inset-track start) and drag down.
  FBar.BeginThumbDrag(16);
  FBar.DragThumbTo(84);
  AssertTrue('OnChange fired at least once during drag', FChanges >= 1);
end;
procedure TTyScrollBarDragTest.TestDragClampsAtMax;
begin
  // Grab the thumb at its top (y=16, inset-track start) and drag far past the
  // track end; clamping to TrackStart+FreeSpace still pins Position at Max.
  FBar.BeginThumbDrag(16);
  FBar.DragThumbTo(10000);
  AssertEquals('drag past end clamps at Max', 100, FBar.Position);
end;
procedure TTyScrollBarDragTest.TestPaintSmoke;
var
  Acc: TScrollAccess;
  Bmp: TBitmap;
begin
  Acc := TScrollAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.SetBounds(0, 0, 16, 160);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(16, 160);
    Acc.SmokeRender(Bmp.Canvas, Rect(0, 0, 16, 160), 96);
    AssertTrue('scrollbar RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;
{ TTyScrollBarThumbColorTest }

procedure TTyScrollBarThumbColorTest.TestThumbPixelUsesTextColor;
{ Stylesheet: track is near-black (#202020), thumb color is red (#FF0000).
  Vertical scrollbar Min=0 Max=100 Page=25 Pos=0 in a 16x200 bitmap.
  Track is inset by a 16px button-size at each end (Task 4), so the track is
  y in [16,184), len 168, and the thumb (25/125 of 168 ~= 33px) occupies the
  top of the track, roughly y in [16,49).
  - Pixel at (8, 30) must be inside the thumb => red-dominant (R>200, G<80).
  - Pixel at (8, 150) is in the track below the thumb => NOT red-dominant.
}
var
  Ctl: TTyStyleController;
  Bar: TScrollAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxThumb, PxTrack: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyScrollBar { background: #202020; color: #FF0000; border-radius: 0px; }');
    Bar := TScrollAccess.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.Kind := sbVertical;
    Bar.SetBounds(0, 0, 16, 200);
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.PageSize := 25;
    Bar.Position := 0;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(16, 200);
    Bar.SmokeRender(Bmp.Canvas, Rect(0, 0, 16, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxThumb := Reread.GetPixel(8, 30);   // inside thumb (inset track ~[16,49))
      PxTrack := Reread.GetPixel(8, 150);  // in track below thumb

      AssertTrue('thumb pixel R > 200 (red-dominant)',  PxThumb.red > 200);
      AssertTrue('thumb pixel G < 80 (not greenish)',   PxThumb.green < 80);

      AssertTrue('track pixel not red-dominant (R <= G+80)', PxTrack.red <= PxTrack.green + 80);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ TTyScrollBarMouseTest }

procedure TTyScrollBarMouseTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyScrollBarMouseTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyScrollBarMouseTest.TestThumbDragMovesPosition;
var
  Bar: TScrollAccess;
  Track, ThumbR: TRect;
  CenterY: Integer;
begin
  Bar := TScrollAccess.Create(FForm);
  Bar.Parent := FForm;
  Bar.Font.PixelsPerInch := 96;
  Bar.Kind := sbVertical;
  Bar.SetBounds(0, 0, 16, 160);
  Bar.Min := 0;
  Bar.Max := 100;
  Bar.PageSize := 10;
  Bar.Position := 0;

  // The control now hit-tests/positions the thumb against the INSET track
  // (16px buttons at each end -> track y in [16,144)), so compute the thumb
  // against that same inset track to land the grab on it.
  Track := TyScrollTrackRect(Rect(0, 0, 16, 160), sbVertical,
    TyScrollButtonSize(Rect(0, 0, 16, 160), sbVertical));
  ThumbR := TyScrollThumbRect(Track, sbVertical, 0, 100, 0, 10);
  CenterY := (ThumbR.Top + ThumbR.Bottom) div 2;

  Bar.CallMouseDown(mbLeft, 8, CenterY);
  Bar.CallMouseMove(8, 140);   // toward bottom of the inset track
  Bar.CallMouseUp(mbLeft, 8, 140);

  AssertTrue(Format('thumb drag toward bottom moves Position substantially (actual %d)',
    [Bar.Position]), Bar.Position > 50);
end;

procedure TTyScrollBarMouseTest.TestTrackClickBelowThumbPagesDown;
var
  Bar: TScrollAccess;
begin
  Bar := TScrollAccess.Create(FForm);
  Bar.Parent := FForm;
  Bar.Font.PixelsPerInch := 96;
  Bar.Kind := sbVertical;
  Bar.SetBounds(0, 0, 16, 160);
  Bar.Min := 0;
  Bar.Max := 100;
  Bar.PageSize := 10;
  Bar.Position := 0;

  // Track is inset by 16px buttons at each end -> track y in [16,144); the
  // thumb at pos 0 sits at the top of it (~[16,27)). Click at y=100, which is
  // in the inset track below the thumb, to page down by one PageSize.
  Bar.CallMouseDown(mbLeft, 8, 100);

  AssertTrue(Format('track click below thumb pages down by ~PageSize (actual %d)',
    [Bar.Position]), Abs(Bar.Position - 10) <= 2);
end;

procedure TTyScrollBarMouseTest.TestDisabledScrollbarMouseIgnored;
var
  Bar: TScrollAccess;
  Track, ThumbR: TRect;
  CenterY: Integer;
begin
  Bar := TScrollAccess.Create(FForm);
  Bar.Parent := FForm;
  Bar.Font.PixelsPerInch := 96;
  Bar.Kind := sbVertical;
  Bar.SetBounds(0, 0, 16, 160);
  Bar.Min := 0;
  Bar.Max := 100;
  Bar.PageSize := 10;
  Bar.Position := 0;
  Bar.Enabled := False;

  // Thumb computed against the inset track (16px buttons each end); a disabled
  // bar must ignore the mouse regardless, so Position stays 0.
  Track := TyScrollTrackRect(Rect(0, 0, 16, 160), sbVertical,
    TyScrollButtonSize(Rect(0, 0, 16, 160), sbVertical));
  ThumbR := TyScrollThumbRect(Track, sbVertical, 0, 100, 0, 10);
  CenterY := (ThumbR.Top + ThumbR.Bottom) div 2;

  Bar.CallMouseDown(mbLeft, 8, CenterY);
  Bar.CallMouseMove(8, 140);
  Bar.CallMouseUp(mbLeft, 8, 140);

  AssertEquals('disabled scrollbar ignores mouse: Position unchanged', 0, Bar.Position);
end;

procedure TTyScrollBarMouseTest.TestArrowButtonsStepSmallChange;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(FForm);
  SA.Parent := FForm;
  SA.Kind := sbVertical;
  SA.SetBounds(0, 0, 16, 160);
  SA.Min := 0;
  SA.Max := 100;
  SA.PageSize := 10;
  SA.SmallChange := 5;
  SA.Position := 50;
  SA.DoMouseDown([], 8, 4);          // top arrow button (y in [0,16))
  AssertEquals('top arrow -SmallChange', 45, SA.Position);
  SA.DoMouseDown([], 8, 156);        // bottom arrow button (y in [144,160))
  AssertEquals('bottom arrow +SmallChange', 50, SA.Position);
end;

procedure TTyScrollBarMouseTest.TestScrollBarKeyboard;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(FForm);
  SA.Parent := FForm;
  SA.Kind := sbVertical;
  SA.Min := 0;
  SA.Max := 100;
  SA.PageSize := 10;
  SA.SmallChange := 1;
  SA.Position := 50;
  SA.DoKeyDown(VK_DOWN, []);  AssertEquals('down +small', 51, SA.Position);
  SA.DoKeyDown(VK_UP, []);    AssertEquals('up -small', 50, SA.Position);
  SA.DoKeyDown(VK_NEXT, []);  AssertEquals('pgdn +page', 60, SA.Position);
  SA.DoKeyDown(VK_PRIOR, []); AssertEquals('pgup -page', 50, SA.Position);
  SA.DoKeyDown(VK_HOME, []);  AssertEquals('home min', 0, SA.Position);
  SA.DoKeyDown(VK_END, []);   AssertEquals('end max', 100, SA.Position);
end;

initialization
  RegisterTest(TTyScrollGeometryTest);
  RegisterTest(TTyScrollBarDragTest);
  RegisterTest(TTyScrollBarThumbColorTest);
  RegisterTest(TTyScrollBarMouseTest);
end.
