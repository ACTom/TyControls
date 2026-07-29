unit test.coolbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.ControlBar, tyControls.CoolBar;

type
  { Pure band math — the headless-tested core (no window handle). }
  TCoolBarMathTest = class(TTestCase)
  published
    procedure TestResizeGrows;
    procedure TestResizeClampsToMin;
    procedure TestResizeClampsToMax;
    procedure TestResizeUnboundedWhenMaxNonPositive;
    procedure TestResizeInvertedRangeCollapsesToFloor;
    procedure TestResizeMinFlooredAtOne;
    procedure TestGripperHitInside;
    procedure TestGripperHitOutsideRight;
    procedure TestGripperHitOutsideVertical;
    procedure TestGripperHitZeroWidthNeverHits;
    // per-band packing (the CoolBar shape, as opposed to a ControlBar's one grip per row)
    procedure TestPackGivesEveryBandItsOwnGripper;
    procedure TestPackWrapsWhenABandDoesNotFit;
    procedure TestPackHonoursAnExplicitBreak;
    procedure TestPackFirstBandCannotBreak;
    procedure TestPackClampsABandWiderThanTheRow;
    // what a grip drag MEANS
    procedure TestDragBelowThresholdDecidesNothing;
    procedure TestVerticalDragMovesTheBand;
    procedure TestHorizontalDragResizes;
    procedure TestVerticalWinsAMixedDrag;
  end;

  { A probe exposing the protected geometry + the private band map indirectly. }
  TCoolBarAccess = class(TTyCoolBar)
  public
    function StyleTypeKey: string;
    function BandRect(ACtl: TControl): TRect;
    function GripPx: Integer;
    procedure CallMouseDown(X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseUp(X, Y: Integer);
  end;

  { The control: the per-child band map — keyed, drop-on-free, clamp defaults. }
  TCoolBarControlTest = class(TTestCase)
  private
    FForm: TForm;
    function MakeBand(AParent: TWinControl; AL, AT, AW, AH: Integer): TControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsPanel;
    procedure TestSetGetBandWidth;
    procedure TestBandWidthKeyedByControl;
    procedure TestBandMapDroppedOnFree;
    procedure TestDefaultMinWidthWhenUnset;
    procedure TestPerBandMinOverridesDefault;
    procedure TestMaxWidthUnboundedByDefault;
    procedure TestBandRectIsRowLeftGripper;
    procedure TestEveryBandIsGrippable;
    procedure TestGripperDragResizesBand;
    procedure TestGripperDragHonoursMinClamp;
  end;

implementation

{ TCoolBarAccess }
function TCoolBarAccess.StyleTypeKey: string;               begin Result := GetStyleTypeKey; end;
function TCoolBarAccess.BandRect(ACtl: TControl): TRect;    begin Result := BandRectFor(ACtl); end;
function TCoolBarAccess.GripPx: Integer;                    begin Result := GripperWidthPx; end;
procedure TCoolBarAccess.CallMouseDown(X, Y: Integer);      begin MouseDown(mbLeft, [ssLeft], X, Y); end;
procedure TCoolBarAccess.CallMouseMove(X, Y: Integer);      begin MouseMove([ssLeft], X, Y); end;
procedure TCoolBarAccess.CallMouseUp(X, Y: Integer);        begin MouseUp(mbLeft, [], X, Y); end;

{ =========================== pure math =========================== }

procedure TCoolBarMathTest.TestResizeGrows;
begin
  // start 100, drag +30, min 20, max 300 -> 130
  AssertEquals('grows by dx', 130, TyCoolBandResize(100, 30, 20, 300));
  AssertEquals('shrinks by dx', 70, TyCoolBandResize(100, -30, 20, 300));
end;

procedure TCoolBarMathTest.TestResizeClampsToMin;
begin
  // drag far left below the floor -> clamped to min
  AssertEquals('clamped to min', 20, TyCoolBandResize(100, -500, 20, 300));
end;

procedure TCoolBarMathTest.TestResizeClampsToMax;
begin
  AssertEquals('clamped to max', 300, TyCoolBandResize(100, 500, 20, 300));
end;

procedure TCoolBarMathTest.TestResizeUnboundedWhenMaxNonPositive;
begin
  // max <= 0 means unbounded — only the floor applies
  AssertEquals('unbounded max grows freely', 5000, TyCoolBandResize(100, 4900, 20, 0));
  AssertEquals('unbounded (negative) max grows freely', 5000, TyCoolBandResize(100, 4900, 20, -1));
end;

procedure TCoolBarMathTest.TestResizeInvertedRangeCollapsesToFloor;
begin
  // max < min is nonsense -> collapse the range to the floor
  AssertEquals('inverted range -> floor', 50, TyCoolBandResize(100, 500, 50, 10));
end;

procedure TCoolBarMathTest.TestResizeMinFlooredAtOne;
begin
  // a zero/negative min is floored at 1 so a band never vanishes
  AssertEquals('min floored at 1', 1, TyCoolBandResize(100, -500, 0, 300));
  AssertEquals('min floored at 1 (neg)', 1, TyCoolBandResize(100, -500, -9, 300));
end;

procedure TCoolBarMathTest.TestGripperHitInside;
begin
  // band (10..200, 0..40), gripper 10 -> the 10..20 column
  AssertTrue('point on gripper', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(12, 20)));
  AssertTrue('left edge inclusive', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(10, 0)));
end;

procedure TCoolBarMathTest.TestGripperHitOutsideRight;
begin
  // x=20 is just past the half-open right edge (10+10)
  AssertFalse('past the gripper column', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(20, 20)));
  AssertFalse('well past', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(150, 20)));
end;

procedure TCoolBarMathTest.TestGripperHitOutsideVertical;
begin
  AssertFalse('above band', TyCoolGripperHit(Rect(10, 5, 200, 40), 10, Point(12, 2)));
  AssertFalse('bottom exclusive', TyCoolGripperHit(Rect(10, 0, 200, 40), 10, Point(12, 40)));
end;

procedure TCoolBarMathTest.TestGripperHitZeroWidthNeverHits;
begin
  AssertFalse('no gripper -> no hit', TyCoolGripperHit(Rect(10, 0, 200, 40), 0, Point(10, 20)));
end;

{ =========================== control =========================== }

procedure TCoolBarControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 500, 300);
end;

procedure TCoolBarControlTest.TearDown;
begin
  FForm.Free;
end;

function TCoolBarControlTest.MakeBand(AParent: TWinControl; AL, AT, AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(AL, AT, AW, AH);
  Result := c;
end;

procedure TCoolBarControlTest.TestTypeKeyIsPanel;
var CB: TCoolBarAccess;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  AssertEquals('owns TyCoolBar', 'TyCoolBar', CB.StyleTypeKey);
end;

procedure TCoolBarControlTest.TestSetGetBandWidth;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('unset band width is 0 (auto)', 0, CB.GetBandWidth(b));
  CB.SetBandWidth(b, 140);
  AssertEquals('band width stored', 140, CB.GetBandWidth(b));
  AssertEquals('child width follows the given band width', 140, b.Width);
end;

procedure TCoolBarControlTest.TestBandWidthKeyedByControl;
var CB: TCoolBarAccess; b1, b2: TControl;
begin
  // The map is keyed by control, not by position: removing one band must not shift
  // the OTHER band's stored width.
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b1 := MakeBand(CB, 0, 0, 80, 30);
  b2 := MakeBand(CB, 90, 0, 80, 30);
  CB.SetBandWidth(b1, 120);
  CB.SetBandWidth(b2, 200);
  b1.Free;                       // drops b1's entry (opRemove)
  AssertEquals('b2 keeps its width after b1 freed', 200, CB.GetBandWidth(b2));
end;

procedure TCoolBarControlTest.TestBandMapDroppedOnFree;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  CB.SetBandWidth(b, 150);
  CB.SetBandMinWidth(b, 40);
  b.Free;
  // A fresh band placed where b was must read as unset (0), proving the old entry went.
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('freed band metadata dropped', 0, CB.GetBandWidth(b));
  AssertEquals('freed band min dropped -> default', 24, CB.BandMinWidth(b));
end;

procedure TCoolBarControlTest.TestDefaultMinWidthWhenUnset;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('unset min -> DefaultBandMinWidth', 24, CB.BandMinWidth(b));
end;

procedure TCoolBarControlTest.TestPerBandMinOverridesDefault;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  CB.SetBandMinWidth(b, 64);
  AssertEquals('per-band min wins over default', 64, CB.BandMinWidth(b));
end;

procedure TCoolBarControlTest.TestMaxWidthUnboundedByDefault;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 0, 0, 80, 30);
  AssertEquals('unset max is 0 (unbounded)', 0, CB.BandMaxWidth(b));
  CB.SetBandMaxWidth(b, 300);
  AssertEquals('max stored', 300, CB.BandMaxWidth(b));
end;

procedure TCoolBarControlTest.TestBandRectIsRowLeftGripper;
var CB: TCoolBarAccess; b: TControl; r: TRect;
begin
  { A CoolBar gives EVERY band its own gripper, immediately to the band's left -- so the band
    rect IS that gripper strip, not the whole child. Under the inherited ControlBar model it was
    one grip per ROW and this rect spanned the child; that model is why band 2 in the containers
    demo had no handle at all. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);   // first-of-row child sits at Left = gripW (10)
  AssertEquals('gripper is 10px at 96 PPI', 10, CB.GripPx);
  r := CB.BandRect(b);
  AssertEquals('gripper starts a grip-width left of the child', 0, r.Left);
  AssertEquals('and ends where the child begins', 10, r.Right);
  AssertEquals('band top = child top', 0, r.Top);
  AssertEquals('band bottom = child bottom', 30, r.Bottom);
end;

procedure TCoolBarControlTest.TestEveryBandIsGrippable;
var CB: TCoolBarAccess; b0, b1: TControl; r0, r1: TRect;
begin
  { The reported bug, inverted into a guard. This test used to assert the OPPOSITE -- that a
    band which is not first on its row has no gripper -- which is a ControlBar's one-grip-per-row
    model wearing a CoolBar's name, and is exactly why the demo's second band had no handle to
    grab. Every band owns a gripper, and each one is its OWN, not a shared row-left column. }
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b0 := MakeBand(CB, 10, 0, 80, 30);
  b1 := MakeBand(CB, 200, 0, 80, 30);   // further right on the SAME row
  r0 := CB.BandRect(b0);
  r1 := CB.BandRect(b1);
  AssertFalse('the first band is grippable', IsRectEmpty(r0));
  AssertFalse('so is the second', IsRectEmpty(r1));
  AssertTrue('and they are different grippers, not one shared column', r0.Left <> r1.Left);
  AssertEquals('the second grip sits just left of its own band', 190, r1.Left);
  AssertEquals('and ends where that band begins', 200, r1.Right);
end;

procedure TCoolBarControlTest.TestGripperDragResizesBand;
var CB: TCoolBarAccess; b: TControl;
begin
  // Grab the row-left gripper (x in 0..10), drag right by 50 -> the band width grows 50.
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);     // first-of-row: gripper column = x in [0..10)
  CB.SetBandWidth(b, 80);
  CB.CallMouseDown(5, 15);              // on the gripper
  CB.CallMouseMove(55, 15);            // +50 px
  CB.CallMouseUp(55, 15);
  AssertEquals('band width grew by the drag delta', 130, CB.GetBandWidth(b));
end;

procedure TCoolBarControlTest.TestGripperDragHonoursMinClamp;
var CB: TCoolBarAccess; b: TControl;
begin
  CB := TCoolBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  b := MakeBand(CB, 10, 0, 80, 30);
  CB.SetBandWidth(b, 80);
  CB.SetBandMinWidth(b, 50);
  CB.CallMouseDown(5, 15);
  CB.CallMouseMove(5 - 500, 15);        // drag far left, way past the floor
  CB.CallMouseUp(5 - 500, 15);
  AssertEquals('drag clamps to the per-band min', 50, CB.GetBandWidth(b));
end;

{ ── per-band packing ───────────────────────────────────────────────────────────
  A ControlBar reserves ONE gripper per row, at the row's left edge, so only the first
  control on a row is grabbable. A CoolBar gives EVERY band its own gripper -- which is what
  makes an individual band draggable, and what Delphi's and Lazarus's TCoolBar draw. These
  pin that difference and the row-breaking rules. }

type TSizeArr = array of TSize;

function Sizes(const AW: array of Integer): TSizeArr;
var i: Integer;
begin
  SetLength(Result, Length(AW));
  for i := 0 to High(AW) do
  begin
    Result[i].cx := AW[i];
    Result[i].cy := 24;
  end;
end;

procedure TCoolBarMathTest.TestPackGivesEveryBandItsOwnGripper;
var r: TTyRectArray;
begin
  // Two bands that fit on one row: each starts a gripper-width past where the previous ended.
  r := TyCoolBarPack(Sizes([100, 80]), [], 400, 24, 10, 4);
  AssertEquals('band 0 starts after its own gripper', 10, r[0].Left);
  AssertEquals('band 0 ends where its width says', 110, r[0].Right);
  // band 1: 110 + spacing 4 = 114, then ITS gripper -> 124
  AssertEquals('band 1 starts after ITS OWN gripper too', 124, r[1].Left);
  AssertEquals('both on the same row', r[0].Top, r[1].Top);
end;

procedure TCoolBarMathTest.TestPackWrapsWhenABandDoesNotFit;
var r: TTyRectArray;
begin
  r := TyCoolBarPack(Sizes([100, 100]), [], 150, 24, 10, 4);
  AssertEquals('band 0 on row 0', 0, r[0].Top);
  AssertTrue('band 1 wrapped to the next row', r[1].Top > r[0].Top);
  AssertEquals('and restarts at the row left, past its gripper', 10, r[1].Left);
end;

procedure TCoolBarMathTest.TestPackHonoursAnExplicitBreak;
var r: TTyRectArray;
begin
  { The point of dragging a band onto its own row: it must break even though it FITS where
    it was. Without this the packer would simply put it back. }
  r := TyCoolBarPack(Sizes([100, 80]), [False, True], 400, 24, 10, 4);
  AssertTrue('the broken band moved to a new row', r[1].Top > r[0].Top);
  AssertEquals('and starts at the row left', 10, r[1].Left);
end;

procedure TCoolBarMathTest.TestPackFirstBandCannotBreak;
var r: TTyRectArray;
begin
  // There is no row above the first band to leave, so a Break on it must be inert.
  r := TyCoolBarPack(Sizes([100]), [True], 400, 24, 10, 4);
  AssertEquals('first band stays on row 0', 0, r[0].Top);
end;

procedure TCoolBarMathTest.TestPackClampsABandWiderThanTheRow;
var r: TTyRectArray;
begin
  // A band wider than the bar must fit its own row exactly rather than overflow it.
  r := TyCoolBarPack(Sizes([500]), [], 200, 24, 10, 4);
  AssertEquals('clamped to the row', 200, r[0].Right);
  AssertTrue('never negative', r[0].Right >= r[0].Left);
end;

{ ── what a grip drag means ─────────────────────────────────────────────────────
  A CoolBar's gripper does two jobs and the pointer's direction picks between them, as in
  Delphi's and Lazarus's TCoolBar. Resizing every band by its handle -- which is all ours used
  to do -- is a ControlBar's idea; the handle is there to MOVE the band. }

procedure TCoolBarMathTest.TestDragBelowThresholdDecidesNothing;
begin
  // A twitch must not silently resize or move anything.
  AssertTrue('still', TyCoolDragMode(0, 0, 4) = cdNone);
  AssertTrue('under threshold both ways', TyCoolDragMode(3, 3, 4) = cdNone);
end;

procedure TCoolBarMathTest.TestVerticalDragMovesTheBand;
begin
  AssertTrue('down moves', TyCoolDragMode(0, 20, 4) = cdMove);
  AssertTrue('up moves too', TyCoolDragMode(0, -20, 4) = cdMove);
end;

procedure TCoolBarMathTest.TestHorizontalDragResizes;
begin
  AssertTrue('right resizes', TyCoolDragMode(20, 0, 4) = cdResize);
  AssertTrue('left resizes', TyCoolDragMode(-20, 0, 4) = cdResize);
end;

procedure TCoolBarMathTest.TestVerticalWinsAMixedDrag;
begin
  { Dragging a band down to another row is never perfectly vertical. If a sideways wobble could
    flip the meaning, the band would resize instead of moving -- the drag has to commit to the
    axis the user is actually travelling along. }
  AssertTrue('mostly down is a move', TyCoolDragMode(6, 20, 4) = cdMove);
  AssertTrue('mostly sideways is a resize', TyCoolDragMode(20, 6, 4) = cdResize);
end;

initialization
  RegisterTest(TCoolBarMathTest);
  RegisterTest(TCoolBarControlTest);
end.
