unit test.controlbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.ControlBar;
type
  { Pure packing tests — the headless-tested core (no window handle). }
  TControlBarPackTest = class(TTestCase)
  published
    procedure TestZeroChildren;
    procedure TestSingleBand;
    procedure TestGripperIndent;
    procedure TestSpacingBetweenChildren;
    procedure TestWrapsToSecondBand;
    procedure TestChildWiderThanRowGetsOwnBand;
    procedure TestDegenerateAvailPinsAtGripper;
    procedure TestBandHeightApplied;
  end;

  { A thin probe: run the protected AlignControls synchronously + read band info. }
  TControlBarAccess = class(TTyControlBar)
  public
    function StyleTypeKey: string;
    procedure ForceLayout;
  end;

  { The control: typeKey reuse, band assignment keyed by child, drop-on-free. }
  TControlBarControlTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsPanel;
    procedure TestArrangesChildrenOnOneBand;
    procedure TestWrapAssignsSecondBand;
    procedure TestBandAssignmentDroppedOnFree;
    procedure TestBandIndexOfUnknownIsMinusOne;
  end;

implementation

{ helper: a plain themed child of a given width on the bar }
function MakeChild(AParent: TWinControl; AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(0, 0, AW, AH);
  Result := c;
end;

{ TControlBarAccess }
function TControlBarAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TControlBarAccess.ForceLayout;
var dummy: TRect;
begin
  // AlignControls uses ClientWidth internally; in the headless runner ClientWidth
  // matches Width, so positions are deterministic (matches the toolbar test idiom).
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;

// ---------------------------------------------------------------------------
// TControlBarPackTest — pure TyControlBarPack
// ---------------------------------------------------------------------------
procedure TControlBarPackTest.TestZeroChildren;
var r: TTyRectArray;
begin
  r := TyControlBarPack([], 300, 26, 12, 3);
  AssertEquals('no rects for zero children', 0, Length(r));
end;

procedure TControlBarPackTest.TestSingleBand;
var r: TTyRectArray;
begin
  // Two 60-wide children on a 300px bar, gripper 12, spacing 3, bandHeight 26.
  r := TyControlBarPack([Size(60, 20), Size(60, 20)], 300, 26, 12, 3);
  AssertEquals('count', 2, Length(r));
  // Both on band 0 (same Top).
  AssertEquals('c0.top', 0, r[0].Top);
  AssertEquals('c1.top on same band', 0, r[1].Top);
  AssertEquals('c0.bottom = bandHeight', 26, r[0].Bottom);
end;

procedure TControlBarPackTest.TestGripperIndent;
var r: TTyRectArray;
begin
  // The first child starts past the gripper column (left = gripperW).
  r := TyControlBarPack([Size(60, 20)], 300, 26, 12, 3);
  AssertEquals('first child indented past the gripper', 12, r[0].Left);
  AssertEquals('first child right = gripper + width', 72, r[0].Right);
end;

procedure TControlBarPackTest.TestSpacingBetweenChildren;
var r: TTyRectArray;
begin
  // c1.left = gripper(12) + c0.width(60) + spacing(3) = 75.
  r := TyControlBarPack([Size(60, 20), Size(40, 20)], 300, 26, 12, 3);
  AssertEquals('c0.left', 12, r[0].Left);
  AssertEquals('c1.left = gripper + c0.width + spacing', 75, r[1].Left);
  AssertEquals('c1.right', 115, r[1].Right);
end;

procedure TControlBarPackTest.TestWrapsToSecondBand;
var r: TTyRectArray;
begin
  // Bar 100 wide, gripper 12 -> usable 88. Three 40-wide children:
  //   c0 @12..52, c1 @55..95 (fits, since 95 <= 12+88=100), c2 would be @98..138 -> overflow
  //   -> c2 wraps to band 1.
  r := TyControlBarPack([Size(40, 20), Size(40, 20), Size(40, 20)], 100, 26, 12, 3);
  AssertEquals('c0.top band0', 0, r[0].Top);
  AssertEquals('c1.top band0', 0, r[1].Top);
  // band 1 top = bandHeight(26) + spacing(3) = 29
  AssertEquals('c2 wrapped to band1 top', 29, r[2].Top);
  AssertEquals('c2 restarts at the gripper indent', 12, r[2].Left);
end;

procedure TControlBarPackTest.TestChildWiderThanRowGetsOwnBand;
var r: TTyRectArray;
begin
  // Usable = 80 - 12 = 68. A 200-wide child is clamped to the usable width and does not
  // loop; a following child wraps to band 1.
  r := TyControlBarPack([Size(200, 20), Size(30, 20)], 80, 26, 12, 3);
  AssertEquals('oversized child clamped to usable width', 68, r[0].Right - r[0].Left);
  AssertEquals('oversized child on band0', 0, r[0].Top);
  AssertEquals('following child wraps to band1', 29, r[1].Top);
end;

procedure TControlBarPackTest.TestDegenerateAvailPinsAtGripper;
var r: TTyRectArray;
begin
  // avail (10) <= gripperW (12): usable clamps to 0, children get zero width at the gripper.
  r := TyControlBarPack([Size(40, 20)], 10, 26, 12, 3);
  AssertEquals('child pinned at gripper edge', 12, r[0].Left);
  AssertEquals('zero usable width', 0, r[0].Right - r[0].Left);
end;

procedure TControlBarPackTest.TestBandHeightApplied;
var r: TTyRectArray;
begin
  // Every returned rect is exactly bandHeight tall regardless of the child's own cy.
  r := TyControlBarPack([Size(60, 12), Size(60, 40)], 300, 30, 12, 3);
  AssertEquals('c0 height = bandHeight', 30, r[0].Bottom - r[0].Top);
  AssertEquals('c1 height = bandHeight', 30, r[1].Bottom - r[1].Top);
end;

// ---------------------------------------------------------------------------
// TControlBarControlTest — the shell control
// ---------------------------------------------------------------------------
procedure TControlBarControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TControlBarControlTest.TearDown;
begin
  FForm.Free;
end;

procedure TControlBarControlTest.TestTypeKeyIsPanel;
var CB: TControlBarAccess;
begin
  CB := TControlBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  AssertEquals('reuses TyPanel typeKey', 'TyPanel', CB.StyleTypeKey);
end;

procedure TControlBarControlTest.TestArrangesChildrenOnOneBand;
var
  CB: TControlBarAccess;
  A, B: TControl;
begin
  CB := TControlBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.Align := alNone;
  CB.SetBounds(0, 0, 400, 40);
  CB.GripperWidth := 12;
  CB.BandSpacing := 3;
  CB.BandHeight := 26;

  A := MakeChild(CB, 60, 20);
  B := MakeChild(CB, 60, 20);
  CB.ForceLayout;

  // A starts past the gripper; B right after A + spacing; both on band 0.
  AssertEquals('A.Left = gripperWidth', 12, A.Left);
  AssertEquals('B.Left = gripper + A.width + spacing', 75, B.Left);
  AssertEquals('A on band 0', 0, CB.BandIndexOf(A));
  AssertEquals('B on band 0', 0, CB.BandIndexOf(B));
  AssertEquals('band height applied to child', 26, A.Height);
end;

procedure TControlBarControlTest.TestWrapAssignsSecondBand;
var
  CB: TControlBarAccess;
  A, B, C: TControl;
begin
  CB := TControlBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.Align := alNone;
  CB.SetBounds(0, 0, 100, 200);   // tall enough that auto-grow does not confound the test
  CB.GripperWidth := 12;
  CB.BandSpacing := 3;
  CB.BandHeight := 26;

  A := MakeChild(CB, 40, 20);
  B := MakeChild(CB, 40, 20);
  C := MakeChild(CB, 40, 20);   // overflows the 100px row -> wraps to band 1
  CB.ForceLayout;

  AssertEquals('A on band 0', 0, CB.BandIndexOf(A));
  AssertEquals('B on band 0', 0, CB.BandIndexOf(B));
  AssertEquals('C wrapped to band 1', 1, CB.BandIndexOf(C));
end;

procedure TControlBarControlTest.TestBandAssignmentDroppedOnFree;
var
  CB: TControlBarAccess;
  A, B: TControl;
begin
  CB := TControlBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  CB.Align := alNone;
  CB.SetBounds(0, 0, 400, 40);

  A := MakeChild(CB, 60, 20);
  B := MakeChild(CB, 60, 20);
  CB.ForceLayout;
  AssertEquals('B tracked before free', 0, CB.BandIndexOf(B));

  // Free A: its band assignment must be dropped (Notification), and B must NOT be
  // orphaned to a stale/wrong slot.
  A.Free;
  AssertEquals('freed child no longer tracked', -1, CB.BandIndexOf(A));
  // B is still a child and still resolvable after a relayout.
  CB.ForceLayout;
  AssertEquals('surviving child still on band 0', 0, CB.BandIndexOf(B));
end;

procedure TControlBarControlTest.TestBandIndexOfUnknownIsMinusOne;
var
  CB: TControlBarAccess;
  Stray: TControl;
begin
  CB := TControlBarAccess.Create(FForm);
  CB.Parent := FForm;
  CB.Font.PixelsPerInch := 96;
  Stray := TTyPanel.Create(FForm);
  Stray.Parent := FForm;   // NOT a child of the bar
  AssertEquals('unknown control -> -1', -1, CB.BandIndexOf(Stray));
end;

initialization
  RegisterTest(TControlBarPackTest);
  RegisterTest(TControlBarControlTest);
end.
