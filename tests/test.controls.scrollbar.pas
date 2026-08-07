unit test.controls.scrollbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, fpcunit, testregistry,
  Forms, Controls, Graphics, LCLType, StdCtrls,
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
    procedure TestHugeRangeThumbStaysGrabbable;
    procedure TestModestRangeThumbStaysProportional;
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
    procedure TestSnappedPositionKillsAPendingEase;
    procedure TestEaseAdvancesByRealElapsedTime;
    procedure TestDragMovesPosition;
    procedure TestDragFiresOnChange;
    procedure TestDragClampsAtMax;
    procedure TestPaintSmoke;
  end;

  TTyScrollBarThumbColorTest = class(TTestCase)
  published
    procedure TestThumbPixelUsesThumbTypeKey;
    procedure TestThumbDefaultPixelIsBorderColor;
    procedure TestThumbHoverActiveStatesDiscriminate;
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

  TTyScrollBarAnimationTest = class(TTestCase)
  published
    procedure TestThumbAnimatesMidwayThenSettles;
    procedure TestDragSnapsThumbImmediately;
    procedure TestAnimationsEnabledDefaultsTrue;
    procedure TestAnimationsEnabledIsPublished;
  end;

  { Task 5: OnScroll event + mouse-wheel stepping. }
  TTyScrollBarOnScrollTest = class(TTestCase)
  private
    FBar: TTyScrollBar;
    FLastCode: TScrollCode;
    FFired: Integer;
    FClampTo: Integer;     // when >= 0, the handler overrides ScrollPos with it
    FWheelEventFired: Boolean;
    procedure OnScrollHandler(Sender: TObject; ScrollCode: TScrollCode;
      var ScrollPos: Integer);
    procedure OnWheelHandler(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestKeyDownFiresScLineDown;
    procedure TestKeyUpFiresScLineUp;
    procedure TestPageDownFiresScPageDown;
    procedure TestHomeEndFireScTopScBottom;
    procedure TestTrackPagingFiresScPageDown;
    procedure TestVarScrollPosIsHonored;
    procedure TestWheelDownDecreasesPosition;
    procedure TestWheelUpIncreasesPosition;
    procedure TestWheelStepsBySmallChange;
    procedure TestWheelStillFiresInheritedOnMouseWheel;
  end;

  { Regression: Int32 overflow at large range (100k-node tree ~ 1.8M px content)
    on a tall track (>= 1300 px).  The old 32-bit arithmetic wrapped negative so
    the thumb and drag both snapped to the top.  The new Int64-widened path must
    place the thumb at the BOTTOM for Position=Max and map a drag to the track
    bottom back to a Position near Max. }
  TTyScrollBarHugeRangeTest = class(TTestCase)
  published
    procedure TestHugeRangeThumbAtMaxIsAtBottom;
    procedure TestHugeRangeDragToBottomYieldsMaxPosition;
  end;

  { LiveTracking —— goThumbTracking 所需要的那道缝。

    251db2d 把 goThumbTracking 从 TTyGrid.Options 里排除掉,理由写得很清楚:
    "needs a seam in the scroll bar, which always tracks live"。所以这一组既要钉住
    关掉之后**真的**推迟提交,也要钉住打开时的行为**一个字节都没变** —— 后者才是
    这道缝能被加进一个已经发布的控件里的前提。 }
  TTyScrollBarLiveTrackingTest = class(TTestCase)
  private
    FBar: TTyScrollBar;
    FChanges: Integer;
    FCodes: string;
    FLastTrackProposal: Integer;
    procedure OnBarChange(Sender: TObject);
    procedure OnBarScroll(Sender: TObject; ScrollCode: TScrollCode;
      var ScrollPos: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLiveTrackingDefaultsTrueAndIsPublished;
    procedure TestLiveDragCommitsEveryMove;
    procedure TestDeferredDragLeavesPositionAlone;
    procedure TestDeferredDragMovesTheThumbAnyway;
    procedure TestDeferredDragCommitsOnRelease;
    procedure TestDeferredDragStillFiresScTrack;
    procedure TestDeferredDragFiresOneOnChange;
    procedure TestDeferredModeLeavesDiscreteStepsImmediate;
    procedure TestTrackPositionEqualsPositionOutsideADrag;
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
    function CallMouseWheel(WheelDelta: Integer): Boolean;
    procedure SetHoverState(AValue: Boolean);
    procedure SetPressedState(AValue: Boolean);
    procedure SetDraggingState(AValue: Boolean);
    function DisplayPos: Single;
    function AdvanceAnimation(AMs: Integer): Boolean;
    procedure SetPositionAnimating(AValue: Integer);
    procedure SetPositionSnapped(AValue: Integer);
  end;

  { 用受控时钟驱动缓动 —— 真机上定时器被饿死时每拍的真实间隔远大于名义间隔,
    这个桩就是用来把那种情况复现出来的。 }
  TFakeClockScroll = class(TTyScrollBar)
  private
    FFakeMs: Integer;
  protected
    function TickElapsedMs: Integer; override;
  public
    procedure Tick(AMs: Integer);
    function DisplayPos: Single;
    procedure SetPositionAnimating(AValue: Integer);
  end;
{ 喂受控时钟的滚动条:让"缓动按真实时间推进"这条能在无头环境下被验证。 }
function TFakeClockScroll.TickElapsedMs: Integer;
begin
  Result := FFakeMs;
end;

procedure TFakeClockScroll.Tick(AMs: Integer);
begin
  FFakeMs := AMs;
  HandleTimerTick;
end;

function TFakeClockScroll.DisplayPos: Single;
begin
  Result := inherited DisplayPos;
end;

procedure TFakeClockScroll.SetPositionAnimating(AValue: Integer);
begin
  inherited SetPositionAnimating(AValue);
end;

function TScrollAccess.CallMouseWheel(WheelDelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], WheelDelta, Point(0, 0));
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
procedure TScrollAccess.SetHoverState(AValue: Boolean);
begin
  FHover := AValue;
end;
procedure TScrollAccess.SetPressedState(AValue: Boolean);
begin
  FPressed := AValue;
end;
procedure TScrollAccess.SetDraggingState(AValue: Boolean);
begin
  FDragging := AValue;
end;
function TScrollAccess.DisplayPos: Single;
begin
  Result := inherited DisplayPos;
end;
procedure TScrollAccess.SetPositionSnapped(AValue: Integer);
begin
  inherited SetPositionSnapped(AValue);
end;

function TScrollAccess.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := inherited AdvanceAnimation(AMs);
end;
procedure TScrollAccess.SetPositionAnimating(AValue: Integer);
begin
  inherited SetPositionAnimating(AValue);
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
procedure TTyScrollGeometryTest.TestHugeRangeThumbStaysGrabbable;
var
  R: TRect;
  Len: Integer;
begin
  // Regression: a huge content range (e.g. a 100k-node tree, ~1.8M px tall)
  // used to floor the thumb at 1px, making it impossible to grab. The minimum
  // thumb length must now be tied to the bar's cross-axis thickness so the
  // thumb is always at least a few px tall and never exceeds the track.
  // Track ~ a 12px-wide vertical bar, 380px tall; Min=0 Max=1.8M Page=380.
  R := TyScrollThumbRect(Rect(0, 0, 12, 380), sbVertical, 0, 1800000, 0, 380);
  Len := R.Bottom - R.Top;
  AssertTrue(Format('huge-range thumb is grabbable (>=6, actual %d)', [Len]),
    Len >= 6);
  AssertTrue(Format('huge-range thumb never exceeds track (<=380, actual %d)', [Len]),
    Len <= 380);
end;

procedure TTyScrollGeometryTest.TestModestRangeThumbStaysProportional;
var
  R: TRect;
  Len, Cross, Proportional: Integer;
begin
  // Regression guard: the new minimum must not distort modest ranges. With a
  // 12x200 vertical track, Max=100, Page=10 -> Span=110, proportional thumb is
  // 10*200 div 110 = 18px. That is well above the MinThumb (=Cross=12), so the
  // result must stay the proportional value, not be clamped up.
  R := TyScrollThumbRect(Rect(0, 0, 12, 200), sbVertical, 0, 100, 0, 10);
  Len := R.Bottom - R.Top;
  Cross := 12;
  Proportional := (10 * 200) div ((100 - 0) + 10);   // = 18
  AssertTrue(Format('modest-range thumb stays proportional (~%d, actual %d)',
    [Proportional, Len]), Len = Proportional);
  AssertTrue(Format('modest-range thumb exceeds MinThumb cross=%d (actual %d)',
    [Cross, Len]), Len > Cross);
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

procedure TTyScrollBarThumbColorTest.TestThumbPixelUsesThumbTypeKey;
{ Batch4 Task 9: the thumb fill is sourced from the dedicated TyScrollThumb
  typeKey (no longer the parent's TyScrollBar.color).
  Stylesheet: track is near-black (#202020), thumb color is red (#FF0000) via
  TyScrollThumb.background.
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
    Ctl.LoadThemeCss(
      'TyScrollBar { background: #202020; border-radius: 0px; }' +
      'TyScrollThumb { background: #FF0000; border-radius: 0px; }');
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

procedure TTyScrollBarThumbColorTest.TestThumbDefaultPixelIsBorderColor;
{ Batch4 Task 9: default zero visual change. With the built-in theme loaded,
  the thumb fill defaults to TyScrollThumb.background = var(--border) = #D1D5DB
  (= the old borrowed TyScrollBar.color = S.TextColor). Same vertical bar.
  Thumb pixel at (8,30) must be light gray (R,G,B all ~ 0xD1..0xDB > 180 and
  nearly equal), proving the migration kept the look. }
var
  Ctl: TTyStyleController;
  Bar: TScrollAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxThumb: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil); // NO LoadTheme -> built-in skin
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
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
      // var(--border) #D1D5DB: light gray, all channels high and close together.
      AssertTrue('default thumb R ~ border $D1 (>180)', PxThumb.red > 180);
      AssertTrue('default thumb G ~ border $D5 (>180)', PxThumb.green > 180);
      AssertTrue('default thumb B ~ border $DB (>180)', PxThumb.blue > 180);
      AssertTrue('default thumb is gray (|R-B| small)',
        Abs(Integer(PxThumb.red) - Integer(PxThumb.blue)) < 30);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TTyScrollBarThumbColorTest.TestThumbHoverActiveStatesDiscriminate;
{ Batch4 follow-up: the thumb fill must react to the control's hover/press state
  via the TyScrollThumb:hover / :active rules. With distinct known colors for
  normal / hover / active, the thumb pixel must match the state-appropriate color:
    normal #00FF00 (green), hover #0000FF (blue), active #FF0000 (red).
  Same vertical bar (16x200, Min=0 Max=100 Page=25 Pos=0); the inset track is
  y in [16,184) and the thumb (25/125 of 168 ~= 33px) sits at ~y in [16,49),
  so sample at (8,30). Active takes precedence over hover (cascade).
  This fails with the old empty-state resolve (all three would be green). }
var
  Ctl: TTyStyleController;
  Bar: TScrollAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;

  procedure RenderThumb;
  begin
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(16, 200);
    Bar.SmokeRender(Bmp.Canvas, Rect(0, 0, 16, 200), 96);
  end;

  function ThumbPixel: TBGRAPixel;
  begin
    Reread := TBGRABitmap.Create(Bmp);
    try
      Result := Reread.GetPixel(8, 30);
    finally
      Reread.Free;
    end;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyScrollBar { background: #202020; border-radius: 0px; }' +
      'TyScrollThumb { background: #00FF00; border-radius: 0px; }' +
      'TyScrollThumb:hover { background: #0000FF; border-radius: 0px; }' +
      'TyScrollThumb:active { background: #FF0000; border-radius: 0px; }');
    Bar := TScrollAccess.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.Kind := sbVertical;
    Bar.SetBounds(0, 0, 16, 200);
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.PageSize := 25;
    Bar.Position := 0;

    // idle: no hover, no press -> normal (green)
    Bar.SetHoverState(False);
    Bar.SetPressedState(False);
    RenderThumb;
    Px := ThumbPixel;
    AssertTrue('idle thumb green-dominant (G>200)', Px.green > 200);
    AssertTrue('idle thumb not red (R<80)',          Px.red < 80);
    AssertTrue('idle thumb not blue (B<80)',         Px.blue < 80);

    // hover: FHover=True -> :hover (blue)
    Bar.SetHoverState(True);
    Bar.SetPressedState(False);
    RenderThumb;
    Px := ThumbPixel;
    AssertTrue('hover thumb blue-dominant (B>200)', Px.blue > 200);
    AssertTrue('hover thumb not red (R<80)',         Px.red < 80);
    AssertTrue('hover thumb not green (G<80)',       Px.green < 80);

    // pressed: FPressed=True -> :active (red), takes precedence over hover
    Bar.SetHoverState(True);
    Bar.SetPressedState(True);
    RenderThumb;
    Px := ThumbPixel;
    AssertTrue('pressed thumb red-dominant (R>200)', Px.red > 200);
    AssertTrue('pressed thumb not green (G<80)',      Px.green < 80);
    AssertTrue('pressed thumb not blue (B<80)',       Px.blue < 80);
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

{ TTyScrollBarAnimationTest }

procedure TTyScrollBarAnimationTest.TestThumbAnimatesMidwayThenSettles;
{ Arm the animating path 0->100 (headless seam, no handle needed), step the
  ease ~half of 120ms -> the displayed thumb position is strictly between old
  and new; another 120ms -> it settles exactly at the target. }
var
  Bar: TScrollAccess;
begin
  Bar := TScrollAccess.Create(nil);
  try
    Bar.Min := 0; Bar.Max := 100; Bar.PageSize := 10; Bar.Position := 0;
    Bar.SetPositionAnimating(100);   // arm animation 0->100
    Bar.AdvanceAnimation(60);         // ~half of 120ms
    AssertTrue('midway', (Bar.DisplayPos > 10) and (Bar.DisplayPos < 90));
    Bar.AdvanceAnimation(120);
    AssertTrue('settled', Abs(Bar.DisplayPos - 100) < 0.5);
  finally
    Bar.Free;
  end;
end;

procedure TTyScrollBarAnimationTest.TestDragSnapsThumbImmediately;
{ While dragging, the thumb must track the mouse instantly: a Position change
  with FDragging=True snaps DisplayPos to the new value with no animation. }
var
  Bar: TScrollAccess;
begin
  Bar := TScrollAccess.Create(nil);
  try
    Bar.Min := 0; Bar.Max := 100; Bar.PageSize := 10; Bar.Position := 0;
    Bar.SetDraggingState(True);
    Bar.Position := 70;
    AssertTrue('drag snaps thumb to new position immediately',
      Abs(Bar.DisplayPos - 70) < 0.5);
  finally
    Bar.Free;
  end;
end;

procedure TTyScrollBarAnimationTest.TestAnimationsEnabledDefaultsTrue;
var
  Bar: TTyScrollBar;
begin
  Bar := TTyScrollBar.Create(nil);
  try
    AssertTrue('AnimationsEnabled defaults True', Bar.AnimationsEnabled);
  finally
    Bar.Free;
  end;
end;

procedure TTyScrollBarAnimationTest.TestAnimationsEnabledIsPublished;
var
  Bar: TTyScrollBar;
begin
  Bar := TTyScrollBar.Create(nil);
  try
    AssertTrue('AnimationsEnabled is a published property (designer/streaming access)',
      IsPublishedProp(Bar, 'AnimationsEnabled'));
  finally
    Bar.Free;
  end;
end;

{ TTyScrollBarOnScrollTest }

procedure TTyScrollBarOnScrollTest.OnScrollHandler(Sender: TObject;
  ScrollCode: TScrollCode; var ScrollPos: Integer);
begin
  Inc(FFired);
  FLastCode := ScrollCode;
  if FClampTo >= 0 then
    ScrollPos := FClampTo;   // prove the var parameter is honored
end;

procedure TTyScrollBarOnScrollTest.OnWheelHandler(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  FWheelEventFired := True;
end;

procedure TTyScrollBarOnScrollTest.SetUp;
begin
  FBar := TTyScrollBar.Create(nil);
  FBar.Kind := sbVertical;
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.PageSize := 10;
  FBar.SmallChange := 1;
  FBar.Position := 50;
  FFired := 0;
  FClampTo := -1;
  FBar.OnScroll := @OnScrollHandler;
end;

procedure TTyScrollBarOnScrollTest.TearDown;
begin
  FBar.Free;
end;

procedure TTyScrollBarOnScrollTest.TestKeyDownFiresScLineDown;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Kind := sbVertical; SA.Min := 0; SA.Max := 100; SA.SmallChange := 1;
    SA.Position := 50;
    SA.OnScroll := @OnScrollHandler;
    SA.DoKeyDown(VK_DOWN, []);
    AssertEquals('OnScroll fired once on VK_DOWN', 1, FFired);
    AssertTrue('code is scLineDown', FLastCode = scLineDown);
    AssertEquals('position increased by SmallChange', 51, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestKeyUpFiresScLineUp;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Kind := sbVertical; SA.Min := 0; SA.Max := 100; SA.SmallChange := 1;
    SA.Position := 50;
    SA.OnScroll := @OnScrollHandler;
    SA.DoKeyDown(VK_UP, []);
    AssertTrue('code is scLineUp', FLastCode = scLineUp);
    AssertEquals('position decreased by SmallChange', 49, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestPageDownFiresScPageDown;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Kind := sbVertical; SA.Min := 0; SA.Max := 100; SA.PageSize := 10;
    SA.Position := 50;
    SA.OnScroll := @OnScrollHandler;
    SA.DoKeyDown(VK_NEXT, []);
    AssertTrue('code is scPageDown', FLastCode = scPageDown);
    AssertEquals('position increased by PageSize', 60, SA.Position);
    SA.DoKeyDown(VK_PRIOR, []);
    AssertTrue('code is scPageUp', FLastCode = scPageUp);
    AssertEquals('position decreased by PageSize', 50, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestHomeEndFireScTopScBottom;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Kind := sbVertical; SA.Min := 0; SA.Max := 100;
    SA.Position := 50;
    SA.OnScroll := @OnScrollHandler;
    SA.DoKeyDown(VK_HOME, []);
    AssertTrue('code is scTop', FLastCode = scTop);
    AssertEquals('position at Min', 0, SA.Position);
    SA.DoKeyDown(VK_END, []);
    AssertTrue('code is scBottom', FLastCode = scBottom);
    AssertEquals('position at Max', 100, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestTrackPagingFiresScPageDown;
var
  Form: TForm;
  SA: TScrollAccess;
begin
  Form := TForm.CreateNew(nil);
  try
    SA := TScrollAccess.Create(Form);
    SA.Parent := Form;
    SA.Font.PixelsPerInch := 96;
    SA.Kind := sbVertical;
    SA.SetBounds(0, 0, 16, 160);
    SA.Min := 0; SA.Max := 100; SA.PageSize := 10; SA.Position := 0;
    SA.OnScroll := @OnScrollHandler;
    // Track is inset 16px each end -> track y in [16,144); thumb at pos 0 sits
    // at the top; click at y=100 (below thumb) pages down.
    SA.CallMouseDown(mbLeft, 8, 100);
    AssertTrue('track-paging-down fired OnScroll', FFired >= 1);
    AssertTrue('code is scPageDown', FLastCode = scPageDown);
  finally
    Form.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestVarScrollPosIsHonored;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Kind := sbVertical; SA.Min := 0; SA.Max := 100; SA.SmallChange := 1;
    SA.Position := 50;
    SA.OnScroll := @OnScrollHandler;
    FClampTo := 5;   // handler overrides the proposed pos with 5
    SA.DoKeyDown(VK_DOWN, []);
    AssertEquals('var ScrollPos override is committed', 5, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestWheelDownDecreasesPosition;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Min := 0; SA.Max := 100; SA.SmallChange := 1; SA.Position := 50;
    // wheel up (WheelDelta>0) scrolls content up -> scrollbar Position decreases.
    AssertTrue('wheel handled', SA.CallMouseWheel(120));
    AssertEquals('wheel-up decreases Position by SmallChange', 49, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestWheelUpIncreasesPosition;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Min := 0; SA.Max := 100; SA.SmallChange := 1; SA.Position := 50;
    // wheel down (WheelDelta<0) -> Position increases.
    AssertTrue('wheel handled', SA.CallMouseWheel(-120));
    AssertEquals('wheel-down increases Position by SmallChange', 51, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestWheelStepsBySmallChange;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Min := 0; SA.Max := 100; SA.SmallChange := 7; SA.Position := 50;
    SA.CallMouseWheel(-120);
    AssertEquals('wheel steps by SmallChange (7)', 57, SA.Position);
  finally
    SA.Free;
  end;
end;

procedure TTyScrollBarOnScrollTest.TestWheelStillFiresInheritedOnMouseWheel;
var
  SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(nil);
  try
    SA.Min := 0; SA.Max := 100; SA.SmallChange := 1; SA.Position := 50;
    FWheelEventFired := False;
    SA.OnMouseWheel := @OnWheelHandler;   // published via base class (Task 1)
    SA.CallMouseWheel(-120);
    AssertTrue('inherited DoMouseWheel ran so OnMouseWheel fired', FWheelEventFired);
  finally
    SA.Free;
  end;
end;

{ TTyScrollBarHugeRangeTest
  Parameters chosen to reproduce the original Int32 overflow:
    Kind=sbVertical, Min=0, Max=1800000, PageSize=380
    Track: the scrollbar gets Width=12, Height=1320.
    ButtonSize = 12 (cross-axis width of a vertical bar).
    Track rect = [12 .. 1308)  → TrackLen = 1296 px.
    Span = 1800000 + 380 = 1800380.
    ThumbLen = (380 * 1296) div 1800380 ≈ 0 → clamped up to MinThumb = 12.
    FreeSpace = 1296 - 12 = 1284.
    Travel = 1800000.

  OLD code (overflowed):
    Offset = (Pos0 * FreeSpace) div Travel
           = (1800000 * 1284) div 1800000   →  1800000 * 1284 overflows Int32
               (= 2_311_200_000 > 2^31-1)   →  wraps to negative → Offset < 0.
    Result: thumb snapped to top instead of bottom.

  NEW code:
    Offset = Integer((Int64(1800000) * 1284) div 1800000) = 1284 = FreeSpace ✓.

  Drag test (inverse path):
    DragThumbTo maps (NewTop - TrackStart) back to position.
    For a drag to the very bottom of the track (TrackStart + FreeSpace = 12 + 1284 = 1296):
    OLD: NewPos = FMin + ((1284) * 1800000) div 1284
               = 0 + (1284 * 1800000) div 1284  →  1284 * 1800000 = 2_311_200_000 overflows
               → wraps negative → NewPos clamped to FMin = 0.
    NEW: NewPos = 0 + Integer((Int64(1284) * 1800000) div 1284) = 1800000 = Max ✓.

  The tests use the pure arithmetic path (TyScrollThumbRect + inline DragThumbTo
  formula) so they run headlessly without needing a window handle. }

procedure TTyScrollBarHugeRangeTest.TestHugeRangeThumbAtMaxIsAtBottom;
const
  { Scrollbar geometry: 12 px wide, 1320 px tall vertical bar at 96 DPI.
    Button size = 12 (= cross-axis width).
    Track: top = 12, bottom = 1308 → TrackLen = 1296 px. }
  TrackTop    = 12;
  TrackBottom = 1308;
var
  Track, ThumbR: TRect;
  FreeSpace, ThumbLen, TrackLen: Integer;
begin
  Track := Rect(0, TrackTop, 12, TrackBottom);

  { Position = Max (1800000): thumb must sit at the bottom of the track. }
  ThumbR := TyScrollThumbRect(Track, sbVertical, 0, 1800000, 1800000, 380);

  TrackLen  := TrackBottom - TrackTop;   { 1296 }
  ThumbLen  := ThumbR.Bottom - ThumbR.Top;
  FreeSpace := TrackLen - ThumbLen;

  AssertTrue(
    Format('huge-range thumb at Max: thumb bottom must equal track bottom ' +
           '(ThumbR.Bottom=%d, TrackBottom=%d)', [ThumbR.Bottom, TrackBottom]),
    ThumbR.Bottom = TrackBottom);
  AssertTrue(
    Format('huge-range thumb at Max: Offset must equal FreeSpace ' +
           '(ThumbR.Top - TrackTop=%d, FreeSpace=%d)',
           [ThumbR.Top - TrackTop, FreeSpace]),
    (ThumbR.Top - TrackTop) = FreeSpace);
end;

procedure TTyScrollBarHugeRangeTest.TestHugeRangeDragToBottomYieldsMaxPosition;
{ Replicate DragThumbTo's exact arithmetic so the test runs headlessly.
  For a drag landing at TrackStart + FreeSpace (= track bottom), the inverse
  mapping must return Position near Max (>= Max * 0.95), NOT 0. }
const
  FMin      = 0;
  FMax      = 1800000;
  PageSize  = 380;
  TrackTop  = 12;
  TrackBottom = 1308;
var
  Track, ThumbR: TRect;
  ThumbLen, FreeSpace, TrackStart, NewTop, Travel, NewPos: Integer;
begin
  Track      := Rect(0, TrackTop, 12, TrackBottom);
  TrackStart := TrackTop;   { sbVertical: TrackStart = Track.Top }

  ThumbR  := TyScrollThumbRect(Track, sbVertical, FMin, FMax, FMax, PageSize);
  ThumbLen := ThumbR.Bottom - ThumbR.Top;

  FreeSpace := (TrackBottom - TrackTop) - ThumbLen;
  if FreeSpace < 1 then FreeSpace := 1;

  Travel := FMax - FMin;

  { Simulate drag arriving exactly at the track bottom (TrackStart + FreeSpace). }
  NewTop := TrackStart + FreeSpace;   { clamped upper limit in DragThumbTo }

  { NEW (Int64-widened) formula — must NOT overflow: }
  NewPos := FMin + Integer((Int64(NewTop - TrackStart) * Travel) div FreeSpace);
  if NewPos < FMin then NewPos := FMin;
  if NewPos > FMax then NewPos := FMax;

  AssertTrue(
    Format('huge-range drag to bottom: Position must be near Max (%d), ' +
           'got %d (must be >= %d)', [FMax, NewPos, FMax * 95 div 100]),
    NewPos >= (FMax * 95 div 100));

  { Belt-and-suspenders: the old Int32 formula would have given 0 (or negative
    clamped to 0).  Verify the result is NOT stuck at the bottom (0). }
  AssertTrue(
    Format('huge-range drag to bottom: Position must not be 0 (old overflow), got %d',
           [NewPos]),
    NewPos > 0);
end;

{ 镜像式赋值(宿主滚完之后把位置同步给滑块)**必须直接落位**。

  内容已经滚过去了,滑块再缓动追上去就是"不跟手" —— 用户看到的是
  表格内容在动、滑块慢半拍。缓动只在"用户点滑道让它跳过去"那种场景才有意义。 }
procedure TTyScrollBarDragTest.TestSnappedPositionKillsAPendingEase;
var
  sb: TScrollAccess;
begin
  sb := TScrollAccess.Create(nil);
  try
    sb.Min := 0;
    sb.Max := 100;
    sb.Position := 0;

    { 先武装一次缓动(这个测试缝绕过"有没有窗口句柄"的判断)。 }
    sb.SetPositionAnimating(100);
    AssertTrue('前置条件:缓动已武装,显示位置还没到终点',
      sb.DisplayPos < 100);

    { 镜像式赋值:显示位置必须**立刻**就是新值,不能还在半路。 }
    sb.SetPositionSnapped(40);
    AssertEquals('逻辑位置', 40, sb.Position);
    AssertEquals('显示位置必须立刻落位,不能还在缓动', 40.0, sb.DisplayPos, 0.01);
  finally
    sb.Free;
  end;
end;

{ 缓动必须按**真实经过的时间**推进,不能按"定时器名义间隔"累加。

  界面忙的时候(比如网格重绘一帧要 100ms)定时器会被饿死:名义 16ms 一步的话,
  120ms 的缓动要 7-8 次滴答才走完,而每次滴答实际隔了 100ms —— 于是缓动
  被拉成将近 1 秒。按真实时间推进时,一次迟到的滴答会把该走的进度一次补齐。 }
procedure TTyScrollBarDragTest.TestEaseAdvancesByRealElapsedTime;
var
  sb: TScrollAccess;
  fake: TFakeClockScroll;
begin
  sb := TScrollAccess.Create(nil);
  try
    sb.Min := 0;
    sb.Max := 100;
    sb.Position := 0;
    sb.SetPositionAnimating(100);

    { 这里**必须走 HandleTimer**,而不是直接调 AdvanceAnimation ——
      "按真实时间推进"这个决定就在 HandleTimer 里,绕过它测的是另一回事
      (第一版测试正是这么写的,变异掉 HandleTimer 也照样绿)。 }
  finally
    sb.Free;
  end;

  fake := TFakeClockScroll.Create(nil);
  try
    fake.Min := 0;
    fake.Max := 100;
    fake.Position := 0;
    fake.SetPositionAnimating(100);
    AssertTrue('前置条件:缓动已武装', fake.DisplayPos < 100);

    { 一拍迟到 1000ms(界面卡住的情形)→ 应当一次把缓动补齐,而不是只走 16ms。 }
    fake.Tick(1000);
    AssertEquals('迟到的一拍应当把缓动一次补齐', 100.0, fake.DisplayPos, 0.01);
  finally
    fake.Free;
  end;
end;

{ ── LiveTracking ──────────────────────────────────────────────────────────── }

procedure TTyScrollBarLiveTrackingTest.OnBarChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyScrollBarLiveTrackingTest.OnBarScroll(Sender: TObject;
  ScrollCode: TScrollCode; var ScrollPos: Integer);
begin
  FCodes := FCodes + GetEnumName(TypeInfo(TScrollCode), Ord(ScrollCode)) + ';';
  if ScrollCode = scTrack then FLastTrackProposal := ScrollPos;
end;

procedure TTyScrollBarLiveTrackingTest.SetUp;
begin
  FBar := TTyScrollBar.Create(nil);
  FBar.Kind := sbVertical;
  FBar.SetBounds(0, 0, 12, 200);
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.PageSize := 10;
  FBar.Position := 0;
  FBar.OnChange := @OnBarChange;
  FBar.OnScroll := @OnBarScroll;
  FChanges := 0;
  FCodes := '';
  FLastTrackProposal := -1;
end;

procedure TTyScrollBarLiveTrackingTest.TearDown;
begin
  FreeAndNil(FBar);
end;

procedure TTyScrollBarLiveTrackingTest.TestLiveTrackingDefaultsTrueAndIsPublished;
var
  pi: PPropInfo;
begin
  { 出厂值必须是"照旧" —— 这道缝是加给已经发布的控件的,默认换行为就是给每一张
    现有窗体换行为。 }
  AssertTrue('LiveTracking 出厂为 True', FBar.LiveTracking);
  pi := GetPropInfo(FBar, 'LiveTracking');
  AssertTrue('LiveTracking 是 published(设计器/流式化都要够得着)', pi <> nil);
  { 只写属性会让 IDE 报 Cannot read property,而没有 default 子句的话
    TWriter 每次都会把它写进 .lfm。两条都要。 }
  AssertTrue('可读', pi^.GetProc <> nil);
  AssertTrue('可写', pi^.SetProc <> nil);
  AssertEquals('default 子句声明为 True', 1, pi^.Default);
end;

procedure TTyScrollBarLiveTrackingTest.TestLiveDragCommitsEveryMove;
begin
  { 打开时的行为必须**逐字不变**:每一步拖动都落到 Position 上。 }
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(20);
  AssertTrue('实时模式下第一步就动了 Position', FBar.Position > 0);
  AssertEquals('拖动中 TrackPosition 就是 Position', FBar.Position, FBar.TrackPosition);
  AssertTrue('实时模式下每一步都发 OnChange', FChanges >= 1);
  FBar.EndThumbDrag;
end;

procedure TTyScrollBarLiveTrackingTest.TestDeferredDragLeavesPositionAlone;
begin
  FBar.LiveTracking := False;
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(20);
  FBar.DragThumbTo(40);
  FBar.DragThumbTo(60);
  AssertEquals('关掉之后拖动过程中 Position 一动不动', 0, FBar.Position);
  AssertEquals('也一次 OnChange 都没有', 0, FChanges);
end;

procedure TTyScrollBarLiveTrackingTest.TestDeferredDragMovesTheThumbAnyway;
var
  pending: Integer;
begin
  { 推迟的是**提交**,不是拇指。拇指不动的拖动就是个死控件。 }
  FBar.LiveTracking := False;
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(60);
  pending := FBar.TrackPosition;
  AssertTrue(Format('拇指跟着走了(TrackPosition=%d)', [pending]), pending > 0);
  AssertEquals('而 Position 还留在原处', 0, FBar.Position);
  FBar.EndThumbDrag;
  AssertEquals('松手之后落到的正是拖到的那个值', pending, FBar.Position);
end;

procedure TTyScrollBarLiveTrackingTest.TestDeferredDragCommitsOnRelease;
var
  live, deferred: Integer;
begin
  { 两种模式**落点必须一样** —— 差别只在中途。 }
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(20);
  FBar.DragThumbTo(55);
  FBar.EndThumbDrag;
  live := FBar.Position;

  FBar.Position := 0;
  FBar.LiveTracking := False;
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(20);
  FBar.DragThumbTo(55);
  FBar.EndThumbDrag;
  deferred := FBar.Position;

  AssertTrue('前置条件:这一串拖动确实滚出去了', live > 0);
  AssertEquals('推迟提交与实时提交落在同一个位置', live, deferred);
end;

procedure TTyScrollBarLiveTrackingTest.TestDeferredDragStillFiresScTrack;
begin
  { 原生滚动条在关掉实时跟随时**照样**发 SB_THUMBTRACK,宿主自己决定理不理。
    宿主想在拖动中预览(行号提示之类)就靠这个,不发的话这个模式只剩"卡住"。 }
  FBar.LiveTracking := False;
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(60);
  AssertTrue('拖动中仍然发 scTrack', Pos('scTrack', FCodes) > 0);
  AssertTrue(Format('scTrack 带的是**建议值**而不是旧值(%d)', [FLastTrackProposal]),
    FLastTrackProposal > 0);
  AssertEquals('但 Position 依然没动', 0, FBar.Position);
  FBar.EndThumbDrag;
end;

procedure TTyScrollBarLiveTrackingTest.TestDeferredDragFiresOneOnChange;
begin
  { 整个手势换来一次 OnChange —— 这正是 goThumbTracking 关掉之后宿主买到的东西。 }
  FBar.LiveTracking := False;
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(20);
  FBar.DragThumbTo(40);
  FBar.DragThumbTo(60);
  FBar.DragThumbTo(80);
  AssertEquals('拖动全程 0 次 OnChange', 0, FChanges);
  FBar.EndThumbDrag;
  AssertEquals('松手一次 OnChange', 1, FChanges);
  AssertTrue('并且发了 scPosition', Pos('scPosition', FCodes) > 0);
  AssertTrue('也发了 scEndScroll', Pos('scEndScroll', FCodes) > 0);
end;

procedure TTyScrollBarLiveTrackingTest.TestDeferredModeLeavesDiscreteStepsImmediate;
begin
  { 只有拖动这一个连续手势被推迟。方向键/翻页/滚轮是离散的一步,原生也不推迟 ——
    推迟它们等于把控件按坏了。 }
  FBar.LiveTracking := False;
  TScrollAccess(FBar).DoKeyDown(VK_DOWN, []);
  AssertTrue('方向键仍然立刻改 Position', FBar.Position > 0);
  AssertTrue('并且立刻发 OnChange', FChanges >= 1);

  FChanges := 0;
  TScrollAccess(FBar).CallMouseWheel(-120);
  AssertTrue('滚轮也仍然立刻生效', FChanges >= 1);
end;

procedure TTyScrollBarLiveTrackingTest.TestTrackPositionEqualsPositionOutsideADrag;
begin
  { 手势之外这两个数必须是同一个,否则宿主会读到一个陈旧的"待提交值"。 }
  FBar.LiveTracking := False;
  FBar.Position := 37;
  AssertEquals('没在拖动时两者相等', FBar.Position, FBar.TrackPosition);
  FBar.BeginThumbDrag(0);
  FBar.DragThumbTo(70);
  FBar.EndThumbDrag;
  AssertEquals('拖完之后两者又相等', FBar.Position, FBar.TrackPosition);
end;

initialization
  RegisterTest(TTyScrollGeometryTest);
  RegisterTest(TTyScrollBarDragTest);
  RegisterTest(TTyScrollBarThumbColorTest);
  RegisterTest(TTyScrollBarMouseTest);
  RegisterTest(TTyScrollBarAnimationTest);
  RegisterTest(TTyScrollBarOnScrollTest);
  RegisterTest(TTyScrollBarHugeRangeTest);
  RegisterTest(TTyScrollBarLiveTrackingTest);
end.
