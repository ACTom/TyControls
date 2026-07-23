unit test.sizebox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Css.Values, tyControls.SizeBox;
type
  { Pure-geometry tests: no window handle, drive the unit-level functions directly. }
  TSizeBoxGeomTest = class(TTestCase)
  published
    procedure TestApplyDeltaGrowShrink;
    procedure TestApplyDeltaClampsToMin;
    procedure TestApplyDeltaMinFloorAtOne;
    procedure TestGripDotsTriangleCountAndCorner;
    procedure TestGripDotsScaleWithDpi;
    procedure TestGripHitBottomRightOnly;
    procedure TestGripHitDpiScales;
  end;

  { Re-expose the protected surface so headless tests can drive the control
    without a real window handle (mirrors the listbox/ splitter access idiom). }
  TSizeBoxAccess = class(TTySizeBox)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressLeft(Shift: TShiftState; X, Y: Integer);
    procedure DragTo(Shift: TShiftState; X, Y: Integer);
    procedure ReleaseLeft(Shift: TShiftState; X, Y: Integer);
  end;

  TSizeBoxControlTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestDefaultSize;
    procedure TestTargetFreeNotificationClears;
    procedure TestDragResizesExplicitTarget;
    procedure TestDragClampsToTargetMinConstraint;
    procedure TestDragOutsideGripDoesNothing;
    procedure TestButtonlessMoveStopsDrag;
    procedure TestGripDotsDerivedFromBorderColor;
  end;

implementation

{ TSizeBoxAccess }

function TSizeBoxAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TSizeBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TSizeBoxAccess.PressLeft(Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(mbLeft, Shift, X, Y);
end;

procedure TSizeBoxAccess.DragTo(Shift: TShiftState; X, Y: Integer);
begin
  MouseMove(Shift, X, Y);
end;

procedure TSizeBoxAccess.ReleaseLeft(Shift: TShiftState; X, Y: Integer);
begin
  MouseUp(mbLeft, Shift, X, Y);
end;

{ TSizeBoxGeomTest }

procedure TSizeBoxGeomTest.TestApplyDeltaGrowShrink;
var sz: TSize;
begin
  sz := TySizeApplyDelta(200, 150, 40, 25, 10, 10);
  AssertEquals('width grows by dx', 240, sz.cx);
  AssertEquals('height grows by dy', 175, sz.cy);
  sz := TySizeApplyDelta(200, 150, -30, -20, 10, 10);
  AssertEquals('width shrinks by dx', 170, sz.cx);
  AssertEquals('height shrinks by dy', 130, sz.cy);
end;

procedure TSizeBoxGeomTest.TestApplyDeltaClampsToMin;
var sz: TSize;
begin
  // A large negative drag must not go below the requested minimums.
  sz := TySizeApplyDelta(200, 150, -1000, -1000, 120, 90);
  AssertEquals('width floored at min', 120, sz.cx);
  AssertEquals('height floored at min', 90, sz.cy);
  // Exactly at the min boundary stays put.
  sz := TySizeApplyDelta(200, 150, -80, -60, 120, 90);
  AssertEquals('width lands exactly on min', 120, sz.cx);
  AssertEquals('height lands exactly on min', 90, sz.cy);
end;

procedure TSizeBoxGeomTest.TestApplyDeltaMinFloorAtOne;
var sz: TSize;
begin
  // Min <= 0 is coerced to 1 — a control can never collapse to a zero dimension.
  sz := TySizeApplyDelta(50, 50, -1000, -1000, 0, -5);
  AssertEquals('width floored at 1 when min<=0', 1, sz.cx);
  AssertEquals('height floored at 1 when min<=0', 1, sz.cy);
end;

procedure TSizeBoxGeomTest.TestGripDotsTriangleCountAndCorner;
var
  dots: TTyRectArray;
  i, right, bottom, cornerScore: Integer;
begin
  // 3/2/1 diagonal ladder = 6 dots. Use a comfortably large box so the whole ladder
  // sits inside the bottom-right quadrant (on a tiny 16px box it legitimately reaches
  // near the centre — the ladder spans ~3 diagonal steps).
  dots := TySizeGripDots(Rect(0, 0, 48, 48), 96);
  AssertEquals('classic size grip has 6 dots', 6, Length(dots));
  right := 48; bottom := 48;
  cornerScore := Low(Integer);
  for i := 0 to High(dots) do
  begin
    AssertTrue(Format('dot %d inside right edge', [i]), dots[i].Right <= right);
    AssertTrue(Format('dot %d inside bottom edge', [i]), dots[i].Bottom <= bottom);
    AssertTrue(Format('dot %d inside top-left origin', [i]),
      (dots[i].Left >= 0) and (dots[i].Top >= 0));
    AssertTrue(Format('dot %d in bottom-right quadrant', [i]),
      (dots[i].Left >= right div 2) and (dots[i].Top >= bottom div 2));
    AssertTrue(Format('dot %d is non-empty', [i]),
      (dots[i].Right > dots[i].Left) and (dots[i].Bottom > dots[i].Top));
    // Track the most bottom-right dot — it must be index 0 (the corner anchor).
    if dots[i].Left + dots[i].Top > cornerScore then cornerScore := dots[i].Left + dots[i].Top;
  end;
  AssertEquals('dot 0 is the corner-most (bottom-right) dot',
    dots[0].Left + dots[0].Top, cornerScore);
end;

procedure TSizeBoxGeomTest.TestGripDotsScaleWithDpi;
var
  d96, d192: TTyRectArray;
  w96, w192: Integer;
begin
  d96  := TySizeGripDots(Rect(0, 0, 32, 32), 96);
  d192 := TySizeGripDots(Rect(0, 0, 64, 64), 192);
  AssertEquals('dot count is DPI-independent', Length(d96), Length(d192));
  // Dot side grows with DPI (logical 2px -> 2px @96, 4px @192).
  w96  := d96[0].Right  - d96[0].Left;
  w192 := d192[0].Right - d192[0].Left;
  AssertTrue(Format('dot grows with DPI (%d @96 -> %d @192)', [w96, w192]), w192 > w96);
end;

procedure TSizeBoxGeomTest.TestGripHitBottomRightOnly;
var
  r: TRect;
begin
  r := Rect(0, 0, 16, 16);
  // The very corner is inside the grip.
  AssertTrue('bottom-right corner hits', TySizeGripHit(r, 96, Point(15, 15)));
  // The top-left corner is well outside.
  AssertFalse('top-left corner misses', TySizeGripHit(r, 96, Point(1, 1)));
  // A point on the up-left anti-diagonal, still near the corner, hits.
  AssertTrue('near-corner diagonal hits', TySizeGripHit(r, 96, Point(13, 13)));
  // A point in the top-right (outside the bottom-right triangle) misses.
  AssertFalse('top-right misses', TySizeGripHit(r, 96, Point(15, 1)));
  // A point outside the rect entirely misses.
  AssertFalse('beyond-right-edge misses', TySizeGripHit(r, 96, Point(30, 15)));
end;

procedure TSizeBoxGeomTest.TestGripHitDpiScales;
var
  r: TRect;
  p: TPoint;
begin
  // At 96 ppi the grip extent is 3*4+3 = 15 px from the corner; a point 20px in misses.
  r := Rect(0, 0, 40, 40);
  p := Point(40 - 20, 40 - 1);   // 20px left of the right edge, 1px up
  AssertFalse('20px-in point misses at 96 ppi', TySizeGripHit(r, 96, p));
  // At 192 ppi the extent doubles (3*8+6 = 30 px), so the SAME point now hits.
  AssertTrue('same point hits at 192 ppi (larger grip)', TySizeGripHit(r, 192, p));
end;

{ TSizeBoxControlTest }

procedure TSizeBoxControlTest.TestTypeKey;
var
  F: TForm;
  Acc: TSizeBoxAccess;
begin
  F := TForm.CreateNew(nil);
  try
    Acc := TSizeBoxAccess.Create(F);
    Acc.Parent := F;
    AssertEquals('owns TySizeBox', 'TySizeBox', Acc.StyleTypeKey);
  finally
    F.Free;
  end;
end;

procedure TSizeBoxControlTest.TestDefaultSize;
var
  F: TForm;
  Sb: TTySizeBox;
begin
  F := TForm.CreateNew(nil);
  try
    Sb := TTySizeBox.Create(F);
    AssertEquals('default width ~16', 16, Sb.Width);
    AssertEquals('default height ~16', 16, Sb.Height);
    AssertEquals('NW-SE resize cursor', Ord(crSizeNWSE), Ord(Sb.Cursor));
  finally
    F.Free;
  end;
end;

procedure TSizeBoxControlTest.TestTargetFreeNotificationClears;
var
  F: TForm;
  Sb: TTySizeBox;
  Victim: TControl;
begin
  F := TForm.CreateNew(nil);
  try
    Sb := TTySizeBox.Create(F);
    Sb.Parent := F;
    Victim := TControl.Create(F);
    Victim.Parent := F;
    Sb.Target := Victim;
    AssertTrue('target assigned', Sb.Target = Victim);
    Victim.Free;                        // free-notification must clear the reference
    AssertTrue('target cleared after free', Sb.Target = nil);
  finally
    F.Free;
  end;
end;

procedure TSizeBoxControlTest.TestDragResizesExplicitTarget;
var
  F: TForm;
  Acc: TSizeBoxAccess;
  Victim: TControl;
  gx, gy: Integer;
begin
  // Drive the grip's mouse handlers directly. The grip must be pressed INSIDE its hit
  // region; ClientToScreen is identity in a headless form (no window offset), so the
  // screen-space delta equals the client-space mouse delta.
  F := TForm.CreateNew(nil);
  try
    F.SetBounds(0, 0, 400, 400);

    Victim := TControl.Create(F);
    Victim.Parent := F;
    Victim.SetBounds(10, 10, 200, 150);

    Acc := TSizeBoxAccess.Create(F);
    Acc.Parent := F;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(300, 300, 16, 16);
    Acc.Target := Victim;

    // Press the very corner dot (inside the hit region), drag +50,+30.
    gx := 15; gy := 15;
    Acc.PressLeft([], gx, gy);
    Acc.DragTo([ssLeft], gx + 50, gy + 30);
    Acc.ReleaseLeft([ssLeft], gx + 50, gy + 30);

    AssertEquals('target width grew by dx', 250, Victim.Width);
    AssertEquals('target height grew by dy', 180, Victim.Height);
  finally
    F.Free;
  end;
end;

procedure TSizeBoxControlTest.TestDragClampsToTargetMinConstraint;
var
  F: TForm;
  Acc: TSizeBoxAccess;
  Victim: TControl;
  gx, gy: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    F.SetBounds(0, 0, 400, 400);

    Victim := TControl.Create(F);
    Victim.Parent := F;
    Victim.SetBounds(10, 10, 200, 150);
    Victim.Constraints.MinWidth := 120;
    Victim.Constraints.MinHeight := 90;

    Acc := TSizeBoxAccess.Create(F);
    Acc.Parent := F;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(300, 300, 16, 16);
    Acc.Target := Victim;

    gx := 15; gy := 15;
    Acc.PressLeft([], gx, gy);
    Acc.DragTo([ssLeft], gx - 1000, gy - 1000);   // shrink hard
    Acc.ReleaseLeft([ssLeft], gx - 1000, gy - 1000);

    AssertEquals('width floored at target MinWidth', 120, Victim.Width);
    AssertEquals('height floored at target MinHeight', 90, Victim.Height);
  finally
    F.Free;
  end;
end;

procedure TSizeBoxControlTest.TestDragOutsideGripDoesNothing;
var
  F: TForm;
  Acc: TSizeBoxAccess;
  Victim: TControl;
begin
  // A press in the top-left (outside the bottom-right grip triangle) must not start a
  // drag, so the target keeps its size even as the mouse moves.
  F := TForm.CreateNew(nil);
  try
    F.SetBounds(0, 0, 400, 400);

    Victim := TControl.Create(F);
    Victim.Parent := F;
    Victim.SetBounds(10, 10, 200, 150);

    Acc := TSizeBoxAccess.Create(F);
    Acc.Parent := F;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(300, 300, 16, 16);
    Acc.Target := Victim;

    Acc.PressLeft([], 1, 1);                 // top-left: outside the grip
    Acc.DragTo([ssLeft], 60, 40);
    Acc.ReleaseLeft([ssLeft], 60, 40);

    AssertEquals('width unchanged (no drag started)', 200, Victim.Width);
    AssertEquals('height unchanged (no drag started)', 150, Victim.Height);
  finally
    F.Free;
  end;
end;

procedure TSizeBoxControlTest.TestButtonlessMoveStopsDrag;
var
  F: TForm;
  Acc: TSizeBoxAccess;
  Victim: TControl;
  gx, gy: Integer;
begin
  // A stolen/missed MouseUp (capture theft, modal, Alt+Tab) leaves the drag armed; a later
  // button-less move (Shift=[]) must NOT keep resizing — the ssLeft guard clears the drag.
  F := TForm.CreateNew(nil);
  try
    F.SetBounds(0, 0, 400, 400);
    Victim := TControl.Create(F);
    Victim.Parent := F;
    Victim.SetBounds(10, 10, 200, 150);

    Acc := TSizeBoxAccess.Create(F);
    Acc.Parent := F;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(300, 300, 16, 16);
    Acc.Target := Victim;

    gx := 15; gy := 15;
    Acc.PressLeft([], gx, gy);            // drag armed
    Acc.DragTo([], gx + 50, gy + 30);     // button NOT held -> guard bails, no resize
    AssertEquals('width unchanged on button-less move', 200, Victim.Width);
    AssertEquals('height unchanged on button-less move', 150, Victim.Height);
    // The drag was cleared, so even a subsequent ssLeft move does nothing (must re-press).
    Acc.DragTo([ssLeft], gx + 80, gy + 60);
    AssertEquals('still unchanged — drag was cleared, not just skipped', 200, Victim.Width);
  finally
    F.Free;
  end;
end;

procedure TSizeBoxControlTest.TestGripDotsDerivedFromBorderColor;
{ The grip highlight is DERIVED from the theme's border-color (TyLighten(seed,55)),
  never hard-coded. Theme the border a saturated blue, render, and prove a
  blue-dominant highlight pixel appears in the bottom-right grip band — and that
  its exact value matches TyLighten of the themed seed. }
var
  Ctl: TTyStyleController;
  F: TForm;
  Sb: TSizeBoxAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  x, y: Integer;
  px, hiPx: TBGRAPixel;
  seed, expectHi: TTyColor;
  FoundBlue, FoundExact: Boolean;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // A blue border, no background fill, so the white pre-fill shows through and the
    // derived blue highlight dots stand out.
    Ctl.LoadThemeCss('TyPanel, TySizeBox { background: none; border-width: 0px; border-color: #2060E0; }');
    seed := $FF2060E0;                 // #2060E0 as $AARRGGBB
    expectHi := TyLighten(seed, 55);

    Sb := TSizeBoxAccess.Create(F);
    Sb.Parent := F;
    Sb.Controller := Ctl;
    Sb.Font.PixelsPerInch := 96;
    Sb.SetBounds(0, 0, 24, 24);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(24, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 24, 24);
    Sb.RenderTo(Bmp.Canvas, Rect(0, 0, 24, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Scan the bottom-right quadrant for the derived-blue highlight. Capture the
      // first blue-dominant pixel AND (separately) any pixel whose blue exactly matches
      // TyLighten(seed,55) — proving the colour is theme-derived, not an arbitrary
      // constant. hiPx holds the captured highlight (not a stale end-of-scan pixel).
      FoundBlue := False;
      FoundExact := False;
      hiPx := Reread.GetPixel(0, 0);
      for x := 12 to 23 do
        for y := 12 to 23 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.blue > px.red + 40) and (px.blue > px.green) then
          begin
            if not FoundBlue then hiPx := px;
            FoundBlue := True;
          end;
          // Interior of a highlight dot (solid FillRect, no AA) hits the exact value.
          if Abs(Integer(px.blue) - Integer(TyBlueOf(expectHi))) <= 1 then
            FoundExact := True;
        end;
      AssertTrue('grip has a blue-dominant highlight dot (derived from border-color)',
        FoundBlue);
      AssertTrue(Format('a grip pixel matches TyLighten(seed,55) blue exactly (expected ~%d, got %d)',
        [TyBlueOf(expectHi), hiPx.blue]),
        FoundExact);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TSizeBoxGeomTest);
  RegisterTest(TSizeBoxControlTest);
end.
