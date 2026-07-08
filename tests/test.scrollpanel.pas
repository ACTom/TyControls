unit test.scrollpanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ScrollBox, tyControls.ScrollPanel;
type
  { Pure-kernel tests: drive TyEdgeAutoPan directly, no window handle. This is the
    tested CORE of the control (the timer/drag wiring is real-machine). }
  TScrollPanelPanMathTest = class(TTestCase)
  published
    procedure TestMiddleIsCalm;
    procedure TestNearLeftPansNegativeX;
    procedure TestNearRightPansPositiveX;
    procedure TestNearTopPansNegativeY;
    procedure TestNearBottomPansPositiveY;
    procedure TestRampGrowsTowardEdge;
    procedure TestAtEdgeHitsMaxSpeed;
    procedure TestPastEdgeClampsToMaxSpeed;
    procedure TestCornerPansBothAxes;
    procedure TestZeroMarginDisables;
    procedure TestZeroSpeedDisables;
    procedure TestThinViewportSplitsAtMidpoint;
    procedure TestEmptyViewportNoPan;
    procedure TestNearerEdgeWins;
  end;

  { Re-expose the protected auto-pan seam and RECORD the requested delta so the full
    arming/step pipeline is testable without a live TTyScrollBox scroll offset. }
  TScrollPanelAccess = class(TTyScrollPanel)
  public
    LastDx, LastDy: Integer;
    ApplyCount: Integer;
    ViewportOverride: TRect;
    UseViewportOverride: Boolean;
    function StyleTypeKey: string;
    function CallAutoPanStep(const APos: TPoint): Boolean;
  protected
    function ApplyAutoPanDelta(ADx, ADy: Integer): Boolean; override;
    function AutoPanViewport: TRect; override;
  end;

  TScrollPanelControlTest = class(TTestCase)
  published
    procedure TestTypeKeyInheritedTyPanel;
    procedure TestDefaults;
    procedure TestNegativeMarginClampsToZero;
    procedure TestNegativeSpeedClampsToZero;
    procedure TestStepAtEdgeAppliesDelta;
    procedure TestStepInMiddleAppliesNothing;
    procedure TestAutoScrollOffDisablesStep;
  end;

implementation

{ TScrollPanelAccess }

function TScrollPanelAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

function TScrollPanelAccess.CallAutoPanStep(const APos: TPoint): Boolean;
begin
  Result := AutoPanStep(APos);
end;

function TScrollPanelAccess.ApplyAutoPanDelta(ADx, ADy: Integer): Boolean;
begin
  LastDx := ADx;
  LastDy := ADy;
  Inc(ApplyCount);
  Result := (ADx <> 0) or (ADy <> 0);   // pretend the offset always had room to move
end;

function TScrollPanelAccess.AutoPanViewport: TRect;
begin
  if UseViewportOverride then
    Result := ViewportOverride
  else
    Result := inherited AutoPanViewport;
end;

{ TScrollPanelPanMathTest }

procedure TScrollPanelPanMathTest.TestMiddleIsCalm;
var d: TPoint;
begin
  // Pointer dead-centre of a 200x200 viewport, 24px margin: no pan on either axis.
  d := TyEdgeAutoPan(Point(100, 100), Rect(0, 0, 200, 200), 24, 16);
  AssertEquals('centre dx = 0', 0, d.X);
  AssertEquals('centre dy = 0', 0, d.Y);
end;

procedure TScrollPanelPanMathTest.TestNearLeftPansNegativeX;
var d: TPoint;
begin
  // 5px inside the left edge, vertically centred: pan LEFT (negative dx), no dy.
  d := TyEdgeAutoPan(Point(5, 100), Rect(0, 0, 200, 200), 24, 16);
  AssertTrue(Format('near-left dx negative (got %d)', [d.X]), d.X < 0);
  AssertEquals('near-left dy = 0', 0, d.Y);
end;

procedure TScrollPanelPanMathTest.TestNearRightPansPositiveX;
var d: TPoint;
begin
  // 5px inside the right edge (x=195 in a 0..200 viewport): pan RIGHT (positive dx).
  d := TyEdgeAutoPan(Point(195, 100), Rect(0, 0, 200, 200), 24, 16);
  AssertTrue(Format('near-right dx positive (got %d)', [d.X]), d.X > 0);
  AssertEquals('near-right dy = 0', 0, d.Y);
end;

procedure TScrollPanelPanMathTest.TestNearTopPansNegativeY;
var d: TPoint;
begin
  d := TyEdgeAutoPan(Point(100, 5), Rect(0, 0, 200, 200), 24, 16);
  AssertTrue(Format('near-top dy negative (got %d)', [d.Y]), d.Y < 0);
  AssertEquals('near-top dx = 0', 0, d.X);
end;

procedure TScrollPanelPanMathTest.TestNearBottomPansPositiveY;
var d: TPoint;
begin
  d := TyEdgeAutoPan(Point(100, 195), Rect(0, 0, 200, 200), 24, 16);
  AssertTrue(Format('near-bottom dy positive (got %d)', [d.Y]), d.Y > 0);
  AssertEquals('near-bottom dx = 0', 0, d.X);
end;

procedure TScrollPanelPanMathTest.TestRampGrowsTowardEdge;
var dNear, dFar: TPoint;
begin
  // Deeper into the band = faster. Compare 3px-in (fast) vs 20px-in (slow), both
  // inside a 24px band on the left edge.
  dFar  := TyEdgeAutoPan(Point(20, 100), Rect(0, 0, 200, 200), 24, 16);
  dNear := TyEdgeAutoPan(Point(3,  100), Rect(0, 0, 200, 200), 24, 16);
  AssertTrue('both pan left', (dFar.X < 0) and (dNear.X < 0));
  AssertTrue(Format('closer to edge pans faster (near |%d| > far |%d|)',
    [dNear.X, dFar.X]), Abs(dNear.X) > Abs(dFar.X));
end;

procedure TScrollPanelPanMathTest.TestAtEdgeHitsMaxSpeed;
var d: TPoint;
begin
  // Exactly ON the left edge (dist 0): full max speed toward it.
  d := TyEdgeAutoPan(Point(0, 100), Rect(0, 0, 200, 200), 24, 16);
  AssertEquals('at-edge dx = -maxSpeed', -16, d.X);
end;

procedure TScrollPanelPanMathTest.TestPastEdgeClampsToMaxSpeed;
var d: TPoint;
begin
  // Pointer dragged BEYOND the left edge (x=-50): clamps to -maxSpeed, never faster.
  d := TyEdgeAutoPan(Point(-50, 100), Rect(0, 0, 200, 200), 24, 16);
  AssertEquals('past-edge dx clamped to -maxSpeed', -16, d.X);
end;

procedure TScrollPanelPanMathTest.TestCornerPansBothAxes;
var d: TPoint;
begin
  // Top-left corner: both axes pan negative simultaneously.
  d := TyEdgeAutoPan(Point(2, 2), Rect(0, 0, 200, 200), 24, 16);
  AssertTrue(Format('corner dx negative (got %d)', [d.X]), d.X < 0);
  AssertTrue(Format('corner dy negative (got %d)', [d.Y]), d.Y < 0);
end;

procedure TScrollPanelPanMathTest.TestZeroMarginDisables;
var d: TPoint;
begin
  d := TyEdgeAutoPan(Point(0, 0), Rect(0, 0, 200, 200), 0, 16);
  AssertEquals('zero margin -> no dx', 0, d.X);
  AssertEquals('zero margin -> no dy', 0, d.Y);
end;

procedure TScrollPanelPanMathTest.TestZeroSpeedDisables;
var d: TPoint;
begin
  d := TyEdgeAutoPan(Point(0, 0), Rect(0, 0, 200, 200), 24, 0);
  AssertEquals('zero speed -> no dx', 0, d.X);
  AssertEquals('zero speed -> no dy', 0, d.Y);
end;

procedure TScrollPanelPanMathTest.TestThinViewportSplitsAtMidpoint;
var dLeft, dRight: TPoint;
begin
  // A 30px-wide viewport with a 24px requested margin: the bands would overlap, so
  // each is capped to half (15px). A pointer in the left half pans left, right half
  // pans right — NO dead overlap zone, no double-counting.
  dLeft  := TyEdgeAutoPan(Point(5,  50), Rect(0, 0, 30, 100), 24, 16);
  dRight := TyEdgeAutoPan(Point(25, 50), Rect(0, 0, 30, 100), 24, 16);
  AssertTrue(Format('thin: left half pans left (got %d)', [dLeft.X]),  dLeft.X < 0);
  AssertTrue(Format('thin: right half pans right (got %d)', [dRight.X]), dRight.X > 0);
end;

procedure TScrollPanelPanMathTest.TestEmptyViewportNoPan;
var d: TPoint;
begin
  // Degenerate empty viewport: never pans (span <= 0 on both axes).
  d := TyEdgeAutoPan(Point(0, 0), Rect(10, 10, 10, 10), 24, 16);
  AssertEquals('empty viewport dx = 0', 0, d.X);
  AssertEquals('empty viewport dy = 0', 0, d.Y);
end;

procedure TScrollPanelPanMathTest.TestNearerEdgeWins;
var d: TPoint;
begin
  // On a wide axis, a pointer near the RIGHT edge but comfortably far from the left
  // pans right only (the nearer edge is chosen, no left-band leakage).
  d := TyEdgeAutoPan(Point(495, 250), Rect(0, 0, 500, 500), 24, 16);
  AssertTrue(Format('nearer-right pans positive (got %d)', [d.X]), d.X > 0);
end;

{ TScrollPanelAccess control tests }

procedure TScrollPanelControlTest.TestTypeKeyInheritedTyPanel;
var
  F: TForm;
  Acc: TScrollPanelAccess;
begin
  F := TForm.CreateNew(nil);
  try
    Acc := TScrollPanelAccess.Create(F);
    Acc.Parent := F;
    // Reuses the TyPanel typeKey (GetStyleTypeKey not overridden past TTyScrollBox).
    AssertEquals('TyPanel', Acc.StyleTypeKey);
  finally
    F.Free;
  end;
end;

procedure TScrollPanelControlTest.TestDefaults;
var
  F: TForm;
  P: TTyScrollPanel;
begin
  F := TForm.CreateNew(nil);
  try
    P := TTyScrollPanel.Create(F);
    P.Parent := F;
    AssertTrue('AutoScroll default True', P.AutoScroll);
    AssertEquals('EdgeMargin default 24', 24, P.EdgeMargin);
    AssertEquals('MaxSpeed default 16', 16, P.MaxSpeed);
    AssertFalse('AutoPan not active at rest', P.AutoPanActive);
  finally
    F.Free;
  end;
end;

procedure TScrollPanelControlTest.TestNegativeMarginClampsToZero;
var
  F: TForm;
  P: TTyScrollPanel;
begin
  F := TForm.CreateNew(nil);
  try
    P := TTyScrollPanel.Create(F);
    P.Parent := F;
    P.EdgeMargin := -10;
    AssertEquals('negative margin clamps to 0', 0, P.EdgeMargin);
  finally
    F.Free;
  end;
end;

procedure TScrollPanelControlTest.TestNegativeSpeedClampsToZero;
var
  F: TForm;
  P: TTyScrollPanel;
begin
  F := TForm.CreateNew(nil);
  try
    P := TTyScrollPanel.Create(F);
    P.Parent := F;
    P.MaxSpeed := -5;
    AssertEquals('negative speed clamps to 0', 0, P.MaxSpeed);
  finally
    F.Free;
  end;
end;

procedure TScrollPanelControlTest.TestStepAtEdgeAppliesDelta;
var
  F: TForm;
  Acc: TScrollPanelAccess;
begin
  F := TForm.CreateNew(nil);
  try
    Acc := TScrollPanelAccess.Create(F);
    Acc.Parent := F;
    Acc.Font.PixelsPerInch := 96;   // pin scale (macOS defaults to 72)
    Acc.UseViewportOverride := True;
    Acc.ViewportOverride := Rect(0, 0, 200, 200);
    // Pointer on the left edge -> the step must request a negative-dx apply.
    AssertTrue('step at edge scrolled', Acc.CallAutoPanStep(Point(0, 100)));
    AssertEquals('step applied once', 1, Acc.ApplyCount);
    AssertTrue(Format('applied dx negative (got %d)', [Acc.LastDx]), Acc.LastDx < 0);
    AssertEquals('applied dy zero', 0, Acc.LastDy);
  finally
    F.Free;
  end;
end;

procedure TScrollPanelControlTest.TestStepInMiddleAppliesNothing;
var
  F: TForm;
  Acc: TScrollPanelAccess;
begin
  F := TForm.CreateNew(nil);
  try
    Acc := TScrollPanelAccess.Create(F);
    Acc.Parent := F;
    Acc.Font.PixelsPerInch := 96;
    Acc.UseViewportOverride := True;
    Acc.ViewportOverride := Rect(0, 0, 200, 200);
    AssertFalse('middle step does not scroll', Acc.CallAutoPanStep(Point(100, 100)));
    AssertEquals('middle step never calls apply', 0, Acc.ApplyCount);
  finally
    F.Free;
  end;
end;

procedure TScrollPanelControlTest.TestAutoScrollOffDisablesStep;
var
  F: TForm;
  Acc: TScrollPanelAccess;
begin
  F := TForm.CreateNew(nil);
  try
    Acc := TScrollPanelAccess.Create(F);
    Acc.Parent := F;
    Acc.Font.PixelsPerInch := 96;
    Acc.UseViewportOverride := True;
    Acc.ViewportOverride := Rect(0, 0, 200, 200);
    Acc.AutoScroll := False;
    // Even on the edge, AutoScroll off means the step is a no-op.
    AssertFalse('AutoScroll off: no scroll on edge', Acc.CallAutoPanStep(Point(0, 100)));
    AssertEquals('AutoScroll off: apply never called', 0, Acc.ApplyCount);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TScrollPanelPanMathTest);
  RegisterTest(TScrollPanelControlTest);
end.
</content>
