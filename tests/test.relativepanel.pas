unit test.relativepanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.Panel, tyControls.RelativePanel;
type
  { Pure relative-layout solver — the headless-tested core. Exercised DIRECTLY with
    no window handle: build a TTyRelativeItemArray, call TyRelativeSolve, assert the
    resolved Left/Top. }
  TTyRelativeSolveTest = class(TTestCase)
  private
    function Solve(const AItems: array of TTyRelativeItem;
      const AParent: TRect; ASpacing: Integer): TTyRelativePosArray;
  published
    procedure TestEmpty;
    procedure TestSingleParentOrigin;
    procedure TestAlignParentEachEdge;
    procedure TestCenterHorizontal;
    procedure TestCenterVertical;
    procedure TestCenterInParent;
    procedure TestCenterOddRoundsDown;
    procedure TestRightOfChain;
    procedure TestBelowChain;
    procedure TestLeftOfPlacesBeforeSibling;
    procedure TestAbovePlacesAboveSibling;
    procedure TestAlignLeftOfSharesEdge;
    procedure TestAlignRightOfSharesRightEdge;
    procedure TestAlignTopBottomOf;
    procedure TestSpacingApplied;
    procedure TestZeroSpacing;
    procedure TestOutOfOrderSolvesTopologically;
    procedure TestTwoItemCycleFallsBackToOrigin;
    procedure TestThreeItemCycleFallsBack;
    procedure TestUnknownAnchorIgnored;
    procedure TestSelfAnchorIgnored;
    procedure TestParentAlignPlusSiblingCombined;
    procedure TestParentOffsetOrigin;
    procedure TestPositionWinsOverEdgeAlign;
  end;

  { The control shell: typeKey reuse, SetRules/GetRules/ClearRules keyed by control,
    Notification drops a freed child's rules, PerformLayout places children. }
  TTyRelativePanelTest = class(TTestCase)
  private
    FForm: TForm;
    function MakeChild(AParent: TWinControl; AW, AH: Integer): TControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsPanel;
    procedure TestSetAndGetRules;
    procedure TestSetRulesWithAnchor;
    procedure TestEmptyRuleSetClears;
    procedure TestClearRules;
    procedure TestRuledChildCount;
    procedure TestLayoutPlacesRightOfSibling;
    procedure TestLayoutCentersInParent;
    procedure TestChildKeepsOwnSize;
    procedure TestFreedChildDropsRules;
    procedure TestFreedAnchorClearsAnchorNotRec;
    procedure TestSpacingReflows;
    procedure TestReplaceRules;
  end;

implementation

type
  TRelPanelAccess = class(TTyRelativePanel)
  public
    function StyleTypeKey: string;
  end;

function TRelPanelAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

{ Build a TTyRelativeItem inline. }
function It(AId, AW, AH: Integer; ARules: TTyRelativeRules;
  AAnchor: Integer = -1): TTyRelativeItem;
begin
  Result.Id := AId;
  Result.W := AW;
  Result.H := AH;
  Result.Rules := ARules;
  Result.AnchorId := AAnchor;
end;

{ TTyRelativeSolveTest }

function TTyRelativeSolveTest.Solve(const AItems: array of TTyRelativeItem;
  const AParent: TRect; ASpacing: Integer): TTyRelativePosArray;
var
  arr: TTyRelativeItemArray;
  i: Integer;
begin
  SetLength(arr, Length(AItems));
  for i := 0 to High(AItems) do
    arr[i] := AItems[i];
  Result := TyRelativeSolve(arr, AParent, ASpacing);
end;

procedure TTyRelativeSolveTest.TestEmpty;
var pos: TTyRelativePosArray;
begin
  pos := Solve([], Rect(0, 0, 100, 100), 8);
  AssertEquals('empty -> empty result', 0, Length(pos));
end;

procedure TTyRelativeSolveTest.TestSingleParentOrigin;
var pos: TTyRelativePosArray;
begin
  // No rules -> parent content origin.
  pos := Solve([It(0, 40, 20, [])], Rect(0, 0, 200, 100), 8);
  AssertEquals('left = parent origin', 0, pos[0].Left);
  AssertEquals('top = parent origin', 0, pos[0].Top);
end;

procedure TTyRelativeSolveTest.TestAlignParentEachEdge;
var pos: TTyRelativePosArray;
begin
  // parent 0..200 x 0..100; item 40x20.
  pos := Solve([It(0, 40, 20, [traAlignParentRight, traAlignParentBottom])],
    Rect(0, 0, 200, 100), 8);
  AssertEquals('parent-right: left = 200-40', 160, pos[0].Left);
  AssertEquals('parent-bottom: top = 100-20', 80, pos[0].Top);

  pos := Solve([It(0, 40, 20, [traAlignParentLeft, traAlignParentTop])],
    Rect(0, 0, 200, 100), 8);
  AssertEquals('parent-left: left = 0', 0, pos[0].Left);
  AssertEquals('parent-top: top = 0', 0, pos[0].Top);
end;

procedure TTyRelativeSolveTest.TestCenterHorizontal;
var pos: TTyRelativePosArray;
begin
  pos := Solve([It(0, 40, 20, [traCenterHorizontal])], Rect(0, 0, 200, 100), 8);
  AssertEquals('center-h: (200-40)/2 = 80', 80, pos[0].Left);
  AssertEquals('center-h leaves top at origin', 0, pos[0].Top);
end;

procedure TTyRelativeSolveTest.TestCenterVertical;
var pos: TTyRelativePosArray;
begin
  pos := Solve([It(0, 40, 20, [traCenterVertical])], Rect(0, 0, 200, 100), 8);
  AssertEquals('center-v: (100-20)/2 = 40', 40, pos[0].Top);
  AssertEquals('center-v leaves left at origin', 0, pos[0].Left);
end;

procedure TTyRelativeSolveTest.TestCenterInParent;
var pos: TTyRelativePosArray;
begin
  pos := Solve([It(0, 40, 20, [traCenterInParent])], Rect(0, 0, 200, 100), 8);
  AssertEquals('center-both left', 80, pos[0].Left);
  AssertEquals('center-both top', 40, pos[0].Top);
end;

procedure TTyRelativeSolveTest.TestCenterOddRoundsDown;
var pos: TTyRelativePosArray;
begin
  // (201-40) div 2 = 80 (integer div, rounds toward zero).
  pos := Solve([It(0, 40, 20, [traCenterHorizontal])], Rect(0, 0, 201, 100), 8);
  AssertEquals('odd centering rounds down', 80, pos[0].Left);
end;

procedure TTyRelativeSolveTest.TestRightOfChain;
var pos: TTyRelativePosArray;
begin
  // A parent-left (id 0, w 50), B rightOf A (id 1, w 30), C rightOf B (id 2, w 20).
  // spacing 10. A.left=0; B.left = 0+50+10 = 60; C.left = 60+30+10 = 100.
  pos := Solve([
    It(0, 50, 20, [traAlignParentLeft]),
    It(1, 30, 20, [trRightOf], 0),
    It(2, 20, 20, [trRightOf], 1)
  ], Rect(0, 0, 300, 100), 10);
  AssertEquals('A parent-left', 0, pos[0].Left);
  AssertEquals('B rightOf A', 60, pos[1].Left);
  AssertEquals('C rightOf B', 100, pos[2].Left);
end;

procedure TTyRelativeSolveTest.TestBelowChain;
var pos: TTyRelativePosArray;
begin
  // A parent-top (h 30), B below A (h 20), C below B (h 10). spacing 5.
  // A.top=0; B.top = 0+30+5 = 35; C.top = 35+20+5 = 60.
  pos := Solve([
    It(0, 40, 30, [traAlignParentTop]),
    It(1, 40, 20, [trBelow], 0),
    It(2, 40, 10, [trBelow], 1)
  ], Rect(0, 0, 200, 200), 5);
  AssertEquals('A parent-top', 0, pos[0].Top);
  AssertEquals('B below A', 35, pos[1].Top);
  AssertEquals('C below B', 60, pos[2].Top);
end;

procedure TTyRelativeSolveTest.TestLeftOfPlacesBeforeSibling;
var pos: TTyRelativePosArray;
begin
  // A at parent-right (w 40, parent 200) -> A.left = 160.
  // B leftOf A (w 30), spacing 10 -> B.right = A.left - 10 = 150; B.left = 150-30 = 120.
  pos := Solve([
    It(0, 40, 20, [traAlignParentRight]),
    It(1, 30, 20, [trLeftOf], 0)
  ], Rect(0, 0, 200, 100), 10);
  AssertEquals('A parent-right', 160, pos[0].Left);
  AssertEquals('B leftOf A', 120, pos[1].Left);
end;

procedure TTyRelativeSolveTest.TestAbovePlacesAboveSibling;
var pos: TTyRelativePosArray;
begin
  // A parent-bottom (h 20, parent 100) -> A.top = 80.
  // B above A (h 30), spacing 10 -> B.bottom = 80-10 = 70; B.top = 70-30 = 40.
  pos := Solve([
    It(0, 40, 20, [traAlignParentBottom]),
    It(1, 40, 30, [trAbove], 0)
  ], Rect(0, 0, 200, 100), 10);
  AssertEquals('A parent-bottom', 80, pos[0].Top);
  AssertEquals('B above A', 40, pos[1].Top);
end;

procedure TTyRelativeSolveTest.TestAlignLeftOfSharesEdge;
var pos: TTyRelativePosArray;
begin
  // A rightOf-nothing but centered (w 40, parent 200) -> A.left = 80.
  // B alignLeftOf A (w 30) -> B.left = A.left = 80 (no spacing).
  pos := Solve([
    It(0, 40, 20, [traCenterHorizontal]),
    It(1, 30, 20, [traAlignLeftOf], 0)
  ], Rect(0, 0, 200, 100), 10);
  AssertEquals('A centered', 80, pos[0].Left);
  AssertEquals('B shares A left edge', 80, pos[1].Left);
end;

procedure TTyRelativeSolveTest.TestAlignRightOfSharesRightEdge;
var pos: TTyRelativePosArray;
begin
  // A parent-left (w 50) -> A.left=0, A.right=50.
  // B alignRightOf A (w 30) -> B.right = A.right = 50; B.left = 50-30 = 20.
  pos := Solve([
    It(0, 50, 20, [traAlignParentLeft]),
    It(1, 30, 20, [traAlignRightOf], 0)
  ], Rect(0, 0, 200, 100), 10);
  AssertEquals('A parent-left', 0, pos[0].Left);
  AssertEquals('B shares A right edge', 20, pos[1].Left);
end;

procedure TTyRelativeSolveTest.TestAlignTopBottomOf;
var pos: TTyRelativePosArray;
begin
  // A centered-v (h 20, parent 100) -> A.top = 40, A.bottom = 60.
  // B alignTopOf A (h 10) -> B.top = 40.  C alignBottomOf A (h 10) -> C.bottom = 60 => top 50.
  pos := Solve([
    It(0, 40, 20, [traCenterVertical]),
    It(1, 40, 10, [traAlignTopOf], 0),
    It(2, 40, 10, [traAlignBottomOf], 0)
  ], Rect(0, 0, 200, 100), 10);
  AssertEquals('A centered-v top', 40, pos[0].Top);
  AssertEquals('B aligns A top', 40, pos[1].Top);
  AssertEquals('C aligns A bottom', 50, pos[2].Top);
end;

procedure TTyRelativeSolveTest.TestSpacingApplied;
var pos: TTyRelativePosArray;
begin
  pos := Solve([
    It(0, 50, 20, [traAlignParentLeft]),
    It(1, 30, 20, [trRightOf], 0)
  ], Rect(0, 0, 300, 100), 25);
  AssertEquals('rightOf uses spacing 25: 0+50+25', 75, pos[1].Left);
end;

procedure TTyRelativeSolveTest.TestZeroSpacing;
var pos: TTyRelativePosArray;
begin
  pos := Solve([
    It(0, 50, 20, [traAlignParentLeft]),
    It(1, 30, 20, [trRightOf], 0)
  ], Rect(0, 0, 300, 100), 0);
  AssertEquals('zero spacing: rightOf abuts (0+50)', 50, pos[1].Left);
end;

procedure TTyRelativeSolveTest.TestOutOfOrderSolvesTopologically;
var pos: TTyRelativePosArray;
begin
  // Items given in REVERSE dependency order: C(rightOf B), B(rightOf A), A(parent-left).
  // The solver must place A first, then B, then C regardless of array order.
  pos := Solve([
    It(2, 20, 20, [trRightOf], 1),   // C depends on B
    It(1, 30, 20, [trRightOf], 0),   // B depends on A
    It(0, 50, 20, [traAlignParentLeft])
  ], Rect(0, 0, 300, 100), 10);
  // array idx 2 is A, idx 1 is B, idx 0 is C.
  AssertEquals('A (idx2) at origin', 0, pos[2].Left);
  AssertEquals('B (idx1) rightOf A', 60, pos[1].Left);
  AssertEquals('C (idx0) rightOf B', 100, pos[0].Left);
end;

procedure TTyRelativeSolveTest.TestTwoItemCycleFallsBackToOrigin;
var pos: TTyRelativePosArray;
begin
  // A rightOf B, B rightOf A -> cycle. Both fall back to parent origin (sibling rule
  // dropped). Never infinite-loops.
  pos := Solve([
    It(0, 40, 20, [trRightOf], 1),
    It(1, 40, 20, [trRightOf], 0)
  ], Rect(5, 7, 200, 100), 10);
  AssertEquals('cycle A left -> parent origin', 5, pos[0].Left);
  AssertEquals('cycle B left -> parent origin', 5, pos[1].Left);
  AssertEquals('cycle A top -> parent origin', 7, pos[0].Top);
end;

procedure TTyRelativeSolveTest.TestThreeItemCycleFallsBack;
var pos: TTyRelativePosArray;
begin
  // A rightOf B, B rightOf C, C rightOf A -> 3-cycle; all fall back to origin.
  pos := Solve([
    It(0, 40, 20, [trRightOf], 1),
    It(1, 40, 20, [trRightOf], 2),
    It(2, 40, 20, [trRightOf], 0)
  ], Rect(0, 0, 300, 100), 10);
  AssertEquals('3-cycle A origin', 0, pos[0].Left);
  AssertEquals('3-cycle B origin', 0, pos[1].Left);
  AssertEquals('3-cycle C origin', 0, pos[2].Left);
end;

procedure TTyRelativeSolveTest.TestUnknownAnchorIgnored;
var pos: TTyRelativePosArray;
begin
  // B rightOf id=99 which does not exist -> sibling rule ignored, B falls to origin.
  // (Its parent/center rules would still apply — here none, so parent origin.)
  pos := Solve([
    It(0, 50, 20, [traAlignParentLeft]),
    It(1, 30, 20, [trRightOf], 99)
  ], Rect(3, 4, 300, 100), 10);
  AssertEquals('A placed', 3, pos[0].Left);
  AssertEquals('B unknown anchor -> parent origin left', 3, pos[1].Left);
  AssertEquals('B unknown anchor -> parent origin top', 4, pos[1].Top);
end;

procedure TTyRelativeSolveTest.TestSelfAnchorIgnored;
var pos: TTyRelativePosArray;
begin
  // A rightOf itself -> self-anchor is not a dependency and is skipped; A -> origin.
  pos := Solve([It(0, 40, 20, [trRightOf], 0)], Rect(2, 2, 100, 100), 10);
  AssertEquals('self-anchor -> parent origin', 2, pos[0].Left);
end;

procedure TTyRelativeSolveTest.TestParentAlignPlusSiblingCombined;
var pos: TTyRelativePosArray;
begin
  // B: parent-top (vertical) + rightOf A (horizontal). The two axes are independent.
  // A parent-left (w 50) -> left 0; B rightOf A -> left 60; B parent-top -> top 0.
  pos := Solve([
    It(0, 50, 30, [traAlignParentLeft, traAlignParentTop]),
    It(1, 30, 20, [trRightOf, traAlignParentTop], 0)
  ], Rect(0, 0, 300, 100), 10);
  AssertEquals('B rightOf A (horizontal)', 60, pos[1].Left);
  AssertEquals('B parent-top (vertical)', 0, pos[1].Top);
end;

procedure TTyRelativeSolveTest.TestParentOffsetOrigin;
var pos: TTyRelativePosArray;
begin
  // Parent content rect offset by padding (10,12); center must add that origin.
  pos := Solve([It(0, 40, 20, [traCenterInParent])], Rect(10, 12, 210, 112), 8);
  // width 200, height 100; center left = 10 + (200-40)/2 = 90; top = 12 + (100-20)/2 = 52.
  AssertEquals('centered within offset parent left', 90, pos[0].Left);
  AssertEquals('centered within offset parent top', 52, pos[0].Top);
end;

procedure TTyRelativeSolveTest.TestPositionWinsOverEdgeAlign;
var pos: TTyRelativePosArray;
begin
  // Both alignLeftOf AND rightOf on B against A: position (rightOf) is applied last and wins.
  // A parent-left w50 -> left 0. alignLeftOf would give 0; rightOf gives 0+50+10=60. Expect 60.
  pos := Solve([
    It(0, 50, 20, [traAlignParentLeft]),
    It(1, 30, 20, [traAlignLeftOf, trRightOf], 0)
  ], Rect(0, 0, 300, 100), 10);
  AssertEquals('position rule wins over edge-align', 60, pos[1].Left);
end;

{ TTyRelativePanelTest }

procedure TTyRelativePanelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyRelativePanelTest.TearDown;
begin
  FForm.Free;
end;

function TTyRelativePanelTest.MakeChild(AParent: TWinControl; AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(0, 0, AW, AH);
  Result := c;
end;

procedure TTyRelativePanelTest.TestTypeKeyIsPanel;
var RP: TRelPanelAccess;
begin
  RP := TRelPanelAccess.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  AssertEquals('reuses TyPanel typeKey', 'TyPanel', RP.StyleTypeKey);
end;

procedure TTyRelativePanelTest.TestSetAndGetRules;
var
  RP: TTyRelativePanel;
  ch: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 200, 100);
  ch := MakeChild(RP, 40, 20);
  RP.SetRules(ch, [traCenterInParent]);
  AssertTrue('rules round-trip', RP.GetRules(ch) = [traCenterInParent]);
end;

procedure TTyRelativePanelTest.TestSetRulesWithAnchor;
var
  RP: TTyRelativePanel;
  a, b: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 300, 100);
  a := MakeChild(RP, 50, 20);
  b := MakeChild(RP, 30, 20);
  RP.SetRules(a, [traAlignParentLeft]);
  RP.SetRules(b, [trRightOf], a);
  AssertTrue('anchor round-trip', RP.GetAnchor(b) = a);
  AssertTrue('no anchor when none set', RP.GetAnchor(a) = nil);
end;

procedure TTyRelativePanelTest.TestEmptyRuleSetClears;
var
  RP: TTyRelativePanel;
  ch: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  ch := MakeChild(RP, 40, 20);
  RP.SetRules(ch, [traCenterInParent]);
  AssertEquals('one ruled child', 1, RP.RuledChildCount);
  RP.SetRules(ch, []);   // empty set = clear
  AssertEquals('empty rule set clears', 0, RP.RuledChildCount);
  AssertTrue('rules now empty', RP.GetRules(ch) = []);
end;

procedure TTyRelativePanelTest.TestClearRules;
var
  RP: TTyRelativePanel;
  ch: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  ch := MakeChild(RP, 40, 20);
  RP.SetRules(ch, [traAlignParentRight]);
  RP.ClearRules(ch);
  AssertEquals('cleared', 0, RP.RuledChildCount);
end;

procedure TTyRelativePanelTest.TestRuledChildCount;
var
  RP: TTyRelativePanel;
  a, b, c: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  a := MakeChild(RP, 40, 20);
  b := MakeChild(RP, 40, 20);
  c := MakeChild(RP, 40, 20);
  AssertEquals('none ruled yet', 0, RP.RuledChildCount);
  RP.SetRules(a, [traAlignParentLeft]);
  RP.SetRules(b, [traAlignParentRight]);
  AssertEquals('two ruled', 2, RP.RuledChildCount);
  RP.SetRules(c, [traCenterInParent]);
  AssertEquals('three ruled', 3, RP.RuledChildCount);
end;

procedure TTyRelativePanelTest.TestLayoutPlacesRightOfSibling;
var
  RP: TTyRelativePanel;
  a, b: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.Spacing := 10;
  RP.SetBounds(0, 0, 300, 100);
  a := MakeChild(RP, 50, 20);
  b := MakeChild(RP, 30, 20);
  RP.SetRules(a, [traAlignParentLeft, traAlignParentTop]);
  RP.SetRules(b, [trRightOf], a);
  RP.PerformLayout;
  // a at content origin (padding may inset, but a is parent-left/top = content origin).
  AssertEquals('b.left = a.left + a.width + spacing', a.Left + a.Width + 10, b.Left);
end;

procedure TTyRelativePanelTest.TestLayoutCentersInParent;
var
  RP: TTyRelativePanel;
  ch: TControl;
  cr: TRect;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 200, 100);
  ch := MakeChild(RP, 40, 20);
  RP.SetRules(ch, [traCenterInParent]);
  RP.PerformLayout;
  // Center is symmetric within the content rect: (ch.Left - contentLeft) equals
  // (contentRight - ch.Right) within 1px (integer rounding).
  cr := Rect(0, 0, 0, 0); // recompute expectation from symmetry rather than padding value.
  AssertTrue('horizontally centered (symmetric within 1px)',
    Abs((ch.Left) - (RP.Width - (ch.Left + ch.Width))) <= 2);
  AssertTrue('vertically centered (symmetric within 1px)',
    Abs((ch.Top) - (RP.Height - (ch.Top + ch.Height))) <= 2);
  if cr.Left = 0 then ; // silence unused
end;

procedure TTyRelativePanelTest.TestChildKeepsOwnSize;
var
  RP: TTyRelativePanel;
  ch: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 200, 100);
  ch := MakeChild(RP, 44, 22);
  RP.SetRules(ch, [traCenterInParent]);
  RP.PerformLayout;
  AssertEquals('width preserved', 44, ch.Width);
  AssertEquals('height preserved', 22, ch.Height);
end;

procedure TTyRelativePanelTest.TestFreedChildDropsRules;
var
  RP: TTyRelativePanel;
  a, b: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 300, 100);
  a := MakeChild(RP, 50, 20);
  b := MakeChild(RP, 30, 20);
  RP.SetRules(a, [traAlignParentLeft]);
  RP.SetRules(b, [trRightOf], a);
  AssertEquals('two ruled', 2, RP.RuledChildCount);
  b.Free;   // freeing a ruled child must drop its rec via Notification
  AssertEquals('freed child dropped from rule list', 1, RP.RuledChildCount);
end;

procedure TTyRelativePanelTest.TestFreedAnchorClearsAnchorNotRec;
var
  RP: TTyRelativePanel;
  a, b: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 300, 100);
  a := MakeChild(RP, 50, 20);
  b := MakeChild(RP, 30, 20);
  RP.SetRules(a, [traAlignParentLeft]);
  RP.SetRules(b, [trRightOf], a);
  a.Free;   // freeing the ANCHOR: a's own rec drops; b keeps its rec but loses the anchor
  AssertEquals('anchor rec dropped, b kept', 1, RP.RuledChildCount);
  AssertTrue('b anchor cleared to nil', RP.GetAnchor(b) = nil);
  AssertTrue('b rules still present', RP.GetRules(b) = [trRightOf]);
end;

procedure TTyRelativePanelTest.TestSpacingReflows;
var
  RP: TTyRelativePanel;
  a, b: TControl;
  before: Integer;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 300, 100);
  a := MakeChild(RP, 50, 20);
  b := MakeChild(RP, 30, 20);
  RP.SetRules(a, [traAlignParentLeft]);
  RP.SetRules(b, [trRightOf], a);
  RP.Spacing := 5;
  before := b.Left;
  RP.Spacing := 30;   // wider gap must push b further right
  AssertTrue('increasing spacing moves b right', b.Left > before);
  AssertEquals('b moved by the spacing delta', before + (30 - 5), b.Left);
end;

procedure TTyRelativePanelTest.TestReplaceRules;
var
  RP: TTyRelativePanel;
  ch: TControl;
begin
  RP := TTyRelativePanel.Create(FForm);
  RP.Parent := FForm;
  RP.Font.PixelsPerInch := 96;
  RP.SetBounds(0, 0, 200, 100);
  ch := MakeChild(RP, 40, 20);
  RP.SetRules(ch, [traAlignParentLeft]);
  AssertTrue('first rule set', RP.GetRules(ch) = [traAlignParentLeft]);
  RP.SetRules(ch, [traAlignParentRight]);   // replace, not add a second rec
  AssertEquals('still one rec after replace', 1, RP.RuledChildCount);
  AssertTrue('rules replaced', RP.GetRules(ch) = [traAlignParentRight]);
end;

initialization
  RegisterTest(TTyRelativeSolveTest);
  RegisterTest(TTyRelativePanelTest);
end.
