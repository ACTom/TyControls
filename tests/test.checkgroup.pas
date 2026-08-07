unit test.checkgroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.CheckBox, tyControls.GroupBox, tyControls.CheckGroup;
type
  { Exposes protected seams + a handle on the internal children for assertions. }
  TCheckGroupAccess = class(TTyCheckGroup)
  public
    function ChildCount: Integer;              // number of internal TTyCheckBox helpers
    function ChildCaption(AIndex: Integer): string;
    function ChildIsNoDesignVisible(AIndex: Integer): Boolean;
    procedure ClickChild(AIndex: Integer);     // simulate a user toggling checkbox AIndex
    function ChildBounds(AIndex: Integer): TRect;
  end;

  TCheckGroupTest = class(TTestCase)
  private
    FItemChangeCount: Integer;
    FLastItemChangeIdx: Integer;
    procedure HItemChange(Sender: TObject; AIndex: Integer);
  published
    procedure TestTypeKeyInheritedGroupBox;
    procedure TestDefaultColumns;
    procedure TestColumnsClampToOne;
    procedure TestItemsBuildChildCount;
    procedure TestChildrenAreNoDesignVisible;
    procedure TestChildCaptionsMatchItems;
    procedure TestCheckedRoundTrip;
    procedure TestCheckedOutOfRangeRaises;
    procedure TestCheckedCount;
    procedure TestToggleFiresOnItemChange;
    procedure TestSetCheckedIsSilent;
    procedure TestRebuildPreservesCheckedByIndex;
    procedure TestRebuildPreservesCheckedByIdentityOnDelete;
    procedure TestRebuildDoesNotFireOnItemChange;
    procedure TestIsDesignerContainerInherited;
    procedure TestRowsNeverOverlapSoTheFocusRingSurvives;
    procedure TestRowPitchIsNeverShorterThanAHostedCheckBox;
  end;

  { The pure column-layout function is the headless-tested geometry core. }
  TCheckGroupLayoutTest = class(TTestCase)
  published
    procedure TestSingleColumnStacksRows;
    procedure TestTwoColumnsSplitWidthAndFillFirstRow;
    procedure TestColumnMajorFillIsOptIn;
    procedure TestLastColumnAbsorbsWidthRemainder;
    procedure TestOutOfRangeYieldsEmpty;
    procedure TestMoreColumnsThanItemsClamped;
  end;

implementation

{ TCheckGroupAccess }

function TCheckGroupAccess.ChildCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCheckBox then Inc(Result);
end;

function TCheckGroupAccess.ChildCaption(AIndex: Integer): string;
var i, n: Integer;
begin
  Result := '';
  n := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCheckBox then
    begin
      if n = AIndex then Exit(TTyCheckBox(Controls[i]).Caption);
      Inc(n);
    end;
end;

function TCheckGroupAccess.ChildIsNoDesignVisible(AIndex: Integer): Boolean;
var i, n: Integer;
begin
  Result := False;
  n := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCheckBox then
    begin
      if n = AIndex then
        Exit(csNoDesignVisible in TTyCheckBox(Controls[i]).ControlStyle);
      Inc(n);
    end;
end;

procedure TCheckGroupAccess.ClickChild(AIndex: Integer);
var i, n: Integer;
begin
  n := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCheckBox then
    begin
      if n = AIndex then
      begin
        TTyCheckBox(Controls[i]).Click;   // real toggle path -> child OnChange
        Exit;
      end;
      Inc(n);
    end;
end;

function TCheckGroupAccess.ChildBounds(AIndex: Integer): TRect;
var i, n: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  n := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCheckBox then
    begin
      if n = AIndex then Exit(TTyCheckBox(Controls[i]).BoundsRect);
      Inc(n);
    end;
end;

{ TCheckGroupTest }

procedure TCheckGroupTest.HItemChange(Sender: TObject; AIndex: Integer);
begin
  Inc(FItemChangeCount);
  FLastItemChangeIdx := AIndex;
end;

{ The check group had the radio group's row-pitch defect too, one pixel deep instead of
  three: LayoutCheckBoxes tiled at a hardcoded 24 while a hosted TTyCheckBox's own
  Constraints.MinHeight is 25 on the default light theme (caption line + --pad-control,
  floored at --checkbox-size), and LCL clamps every SetBounds up to that minimum. So rows
  overlapped by 1px, and the lower row -- a later sibling, higher in the child z-order --
  shaved the bottom edge off the row above it, which is exactly where the 2px :focus ring
  is drawn. Measured, not assumed: on a real window item0 came back (16..41) and item2
  (40..65).

  EDGE probe: the overlap is at the boundary between rows and is invisible on the last one.
  HONESTY NOTE: this is the ambient net, not the guard -- in this console process the
  caption font measures short enough that the item minimum never exceeds the token, so the
  overlap cannot arise here at all. TestRowPitchIsNeverShorterThanAHostedCheckBox states the
  rule; tests/radiofocusverify checks it on a real window. }
procedure TCheckGroupTest.TestRowsNeverOverlapSoTheFocusRingSurvives;
var
  F: TForm;
  G: TCheckGroupAccess;
  i, above: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    G := TCheckGroupAccess.Create(F);
    G.Parent := F;
    G.Font.PixelsPerInch := 96;
    G.SetBounds(0, 0, 290, 94);
    G.Columns := 2;
    G.Items.CommaText := 'Alpha,Beta,Gamma,Delta';
    for i := 2 to G.Count - 1 do          // 2 columns -> item i sits under item i-2
    begin
      above := G.ChildBounds(i - 2).Bottom;
      AssertTrue(Format('item %d must start at or below item %d''s bottom, but Top=%d and '
        + 'that bottom is %d (%d px of overlap) -- the lower row paints over the ring at '
        + 'that edge', [i, i - 2, G.ChildBounds(i).Top, above,
                        above - G.ChildBounds(i).Top]),
        G.ChildBounds(i).Top >= above);
    end;
  finally
    F.Free;
  end;
end;

{ The rule the check group now shares with the radio group, stated where a headless test can
  actually hold it -- see TRadioGroupTest.TestRowPitchIsNeverShorterThanAHostedRadio for the
  measured reason live bounds cannot (this process measures the caption font at 9px, a GUI
  process at 17, so the item minimum is 17 here and 25 there and the overlap never arises in
  the runner). The check group's own numbers were a hardcoded pitch of 24 against a hosted
  checkbox minimum of 25: one pixel, same defect, same lost ring edge. }
procedure TCheckGroupTest.TestRowPitchIsNeverShorterThanAHostedCheckBox;
begin
  AssertEquals('the check group''s own reported case: pitch 24, checkbox needs 25',
    25, TyGroupRowPitch(24, 25));
  AssertEquals('a token taller than the item still decides', 32, TyGroupRowPitch(32, 25));
  AssertEquals('a zero pitch is floored to 1', 1, TyGroupRowPitch(0, 0));
end;

procedure TCheckGroupTest.TestTypeKeyInheritedGroupBox;
var G: TTyCheckGroup;
begin
  G := TTyCheckGroup.Create(nil);
  try
    // Reuses the TyGroupBox token — no new .tycss selector.
    AssertEquals('TyGroupBox', (G as ITyStyleable).GetStyleTypeKey);
  finally
    G.Free;
  end;
end;

procedure TCheckGroupTest.TestDefaultColumns;
var G: TTyCheckGroup;
begin
  G := TTyCheckGroup.Create(nil);
  try
    AssertEquals('default Columns is 1', 1, G.Columns);
  finally
    G.Free;
  end;
end;

procedure TCheckGroupTest.TestColumnsClampToOne;
var G: TTyCheckGroup;
begin
  G := TTyCheckGroup.Create(nil);
  try
    G.Columns := 0;
    AssertEquals('Columns:=0 clamps to 1', 1, G.Columns);
    G.Columns := -5;
    AssertEquals('Columns:=-5 clamps to 1', 1, G.Columns);
    G.Columns := 3;
    AssertEquals('Columns:=3 accepted', 3, G.Columns);
  finally
    G.Free;
  end;
end;

procedure TCheckGroupTest.TestItemsBuildChildCount;
var
  F: TForm;
  G: TCheckGroupAccess;
begin
  F := TForm.CreateNew(nil);
  try
    G := TCheckGroupAccess.Create(F);
    G.Parent := F;
    AssertEquals('no items -> no children', 0, G.ChildCount);
    G.Items.Add('A');
    G.Items.Add('B');
    G.Items.Add('C');
    AssertEquals('3 items -> 3 children', 3, G.ChildCount);
    AssertEquals('Count = Items.Count', 3, G.Count);
    G.Items.Delete(0);
    AssertEquals('delete one -> 2 children', 2, G.ChildCount);
    G.Items.Clear;
    AssertEquals('clear -> 0 children', 0, G.ChildCount);
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestChildrenAreNoDesignVisible;
var
  F: TForm;
  G: TCheckGroupAccess;
begin
  F := TForm.CreateNew(nil);
  try
    G := TCheckGroupAccess.Create(F);
    G.Parent := F;
    G.Items.Add('X');
    G.Items.Add('Y');
    AssertTrue('child 0 is csNoDesignVisible', G.ChildIsNoDesignVisible(0));
    AssertTrue('child 1 is csNoDesignVisible', G.ChildIsNoDesignVisible(1));
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestChildCaptionsMatchItems;
var
  F: TForm;
  G: TCheckGroupAccess;
begin
  F := TForm.CreateNew(nil);
  try
    G := TCheckGroupAccess.Create(F);
    G.Parent := F;
    G.Items.Add('Apple');
    G.Items.Add('Pear');
    AssertEquals('child 0 caption', 'Apple', G.ChildCaption(0));
    AssertEquals('child 1 caption', 'Pear', G.ChildCaption(1));
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestCheckedRoundTrip;
var
  F: TForm;
  G: TTyCheckGroup;
begin
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.Items.Add('A');
    G.Items.Add('B');
    G.Items.Add('C');
    AssertFalse('all start unchecked', G.Checked[0]);
    G.Checked[1] := True;
    AssertTrue('index 1 now checked', G.Checked[1]);
    AssertFalse('index 0 still unchecked (independent)', G.Checked[0]);
    AssertFalse('index 2 still unchecked (independent)', G.Checked[2]);
    G.Checked[1] := False;
    AssertFalse('index 1 unchecked again', G.Checked[1]);
  finally
    F.Free;
  end;
end;

{ RENAMED from TestCheckedOutOfRangeSafe, which asserted the exact defect: an
  out-of-range read answering False and an out-of-range write being dropped is not
  "safe", it is an off-by-one that reads as a legitimately unticked item and a write
  the user appears to have undone. LCL raises here
  (include/customcheckgroup.inc:313-338) and so do we now. The full contract --
  message shape, empty group, half-applied writes -- lives in
  test.parity.ranges.TCheckGroupRangeTest; this keeps the sibling assertion honest. }
procedure TCheckGroupTest.TestCheckedOutOfRangeRaises;
var
  F: TForm;
  G: TTyCheckGroup;
  belowRaised, aboveRaised, writeRaised: Boolean;
begin
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.Items.Add('only');
    belowRaised := False;
    try
      if G.Checked[-1] then ;
    except
      on E: EListError do belowRaised := True;
    end;
    AssertTrue('read below range raises EListError', belowRaised);

    aboveRaised := False;
    try
      if G.Checked[5] then ;
    except
      on E: EListError do aboveRaised := True;
    end;
    AssertTrue('read above range raises EListError', aboveRaised);

    writeRaised := False;
    try
      G.Checked[9] := True;
    except
      on E: EListError do writeRaised := True;
    end;
    AssertTrue('a write past the end raises rather than vanishing', writeRaised);

    AssertFalse('the real item is untouched by any of it', G.Checked[0]);
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestCheckedCount;
var
  F: TForm;
  G: TTyCheckGroup;
begin
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.Items.Add('A');
    G.Items.Add('B');
    G.Items.Add('C');
    AssertEquals('none checked', 0, G.CheckedCount);
    G.Checked[0] := True;
    G.Checked[2] := True;
    AssertEquals('two checked', 2, G.CheckedCount);
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestToggleFiresOnItemChange;
var
  F: TForm;
  G: TCheckGroupAccess;
begin
  F := TForm.CreateNew(nil);
  try
    G := TCheckGroupAccess.Create(F);
    G.Parent := F;
    G.OnItemChange := @HItemChange;
    G.Items.Add('A');
    G.Items.Add('B');

    FItemChangeCount := 0;
    FLastItemChangeIdx := -99;
    G.ClickChild(1);
    AssertEquals('toggling child 1 fires OnItemChange once', 1, FItemChangeCount);
    AssertEquals('event carries the toggled index', 1, FLastItemChangeIdx);
    AssertTrue('child 1 became checked', G.Checked[1]);
  finally
    F.Free;
  end;
end;

{ A programmatic write must NOT be reported as a user change -- this test used to
  assert the opposite, which is how the re-entrancy went unnoticed. }
procedure TCheckGroupTest.TestSetCheckedIsSilent;
var
  F: TForm;
  G: TTyCheckGroup;
begin
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.OnItemChange := @HItemChange;
    G.Items.Add('A');
    G.Items.Add('B');

    FItemChangeCount := 0;
    FLastItemChangeIdx := -99;
    G.Checked[0] := True;
    AssertTrue('the write lands', G.Checked[0]);
    AssertEquals('Checked[0]:=True does not fire OnItemChange', 0, FItemChangeCount);

    G.Checked[0] := False;
    AssertFalse('and back off', G.Checked[0]);
    AssertEquals('still silent', 0, FItemChangeCount);
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestRebuildPreservesCheckedByIndex;
var
  F: TForm;
  G: TTyCheckGroup;
begin
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.Items.Add('A');
    G.Items.Add('B');
    G.Items.Add('C');
    G.Checked[0] := True;
    G.Checked[2] := True;

    // Append an item: a full rebuild happens; indices 0..2 must keep their state,
    // the new index 3 defaults unchecked.
    G.Items.Add('D');
    AssertEquals('rebuilt to 4 children', 4, G.Count);
    AssertTrue('index 0 stayed checked across rebuild', G.Checked[0]);
    AssertFalse('index 1 stayed unchecked across rebuild', G.Checked[1]);
    AssertTrue('index 2 stayed checked across rebuild', G.Checked[2]);
    AssertFalse('new index 3 defaults unchecked', G.Checked[3]);
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestRebuildPreservesCheckedByIdentityOnDelete;
var
  F: TForm;
  G: TTyCheckGroup;
begin
  // A mid-list delete must keep each check on its OWN item (by identity), not on the raw slot.
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.Items.CommaText := 'A,B,C';
    G.Checked[2] := True;              // only 'C' is checked
    G.Items.Delete(0);                 // -> ['B','C']; the check must FOLLOW 'C' to index 1
    AssertEquals('two items remain', 2, G.Items.Count);
    AssertFalse('B (new index 0) is not checked', G.Checked[0]);
    AssertTrue('C survived to index 1 and stays checked', G.Checked[1]);
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestRebuildDoesNotFireOnItemChange;
{ Restoring checked state during a rebuild must NOT fire OnItemChange (only a
  real user/programmatic toggle should). }
var
  F: TForm;
  G: TTyCheckGroup;
begin
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.Items.Add('A');
    G.Checked[0] := True;
    G.OnItemChange := @HItemChange;   // wire AFTER the initial state set

    FItemChangeCount := 0;
    G.Items.Add('B');                 // triggers a rebuild that restores index 0 = checked
    AssertEquals('rebuild restoring state fires nothing', 0, FItemChangeCount);
    AssertTrue('index 0 still checked after rebuild', G.Checked[0]);
  finally
    F.Free;
  end;
end;

procedure TCheckGroupTest.TestIsDesignerContainerInherited;
var G: TTyCheckGroup;
begin
  G := TTyCheckGroup.Create(nil);
  try
    // Inherited from TTyGroupBox: the IDE treats it as a container.
    AssertTrue('check group is a designer container',
      csAcceptsControls in G.ControlStyle);
  finally
    G.Free;
  end;
end;

{ TCheckGroupLayoutTest }

procedure TCheckGroupLayoutTest.TestSingleColumnStacksRows;
var r0, r1, r2: TRect;
begin
  // client (0,0)-(100,300), 3 items, 1 column, rowH 20.
  r0 := TyCheckGroupCellRect(Rect(0, 0, 100, 300), 3, 1, 0, 20);
  r1 := TyCheckGroupCellRect(Rect(0, 0, 100, 300), 3, 1, 1, 20);
  r2 := TyCheckGroupCellRect(Rect(0, 0, 100, 300), 3, 1, 2, 20);
  AssertEquals('row 0 top', 0, r0.Top);
  AssertEquals('row 1 top', 20, r1.Top);
  AssertEquals('row 2 top', 40, r2.Top);
  AssertEquals('single column spans full width', 100, r0.Right - r0.Left);
  AssertEquals('row height honored', 20, r0.Bottom - r0.Top);
end;

{ RENAMED. This used to be TestTwoColumnsSplitWidthAndFillFirstColumn -- its name asserted
  that the grid fills column 0 top-down first, which is what made a multi-column group
  disagree, silently, with the same .lfm loaded in Lazarus. The default is now LCL's
  clHorizontalThenVertical; the old order is still reachable, see the next test. }
procedure TCheckGroupLayoutTest.TestTwoColumnsSplitWidthAndFillFirstRow;
var r0, r1, r2, r3: TRect;
begin
  // 4 items, 2 columns, width 200 -> two 100px columns, 2 rows each.
  // Fill row 0 first (indices 0,1), then row 1 (indices 2,3).
  r0 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 0, 20);
  r1 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 1, 20);
  r2 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 2, 20);
  r3 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 3, 20);

  AssertEquals('item 0 in left column', 0, r0.Left);
  AssertEquals('item 1 in right column (fills first row left-to-right)', 100, r1.Left);
  AssertEquals('item 0 top row', 0, r0.Top);
  AssertEquals('item 1 also top row', 0, r1.Top);

  AssertEquals('item 2 in left column', 0, r2.Left);
  AssertEquals('item 3 in right column', 100, r3.Left);
  AssertEquals('item 2 second row', 20, r2.Top);
  AssertEquals('item 3 second row', 20, r3.Top);
end;

{ The opt-out: the pre-3.0 order, now something a form asks for rather than something it
  gets without being told. }
procedure TCheckGroupLayoutTest.TestColumnMajorFillIsOptIn;
var r0, r1, r2, r3: TRect;
begin
  r0 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 0, 20, clVerticalThenHorizontal);
  r1 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 1, 20, clVerticalThenHorizontal);
  r2 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 2, 20, clVerticalThenHorizontal);
  r3 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 3, 20, clVerticalThenHorizontal);

  AssertEquals('item 0 in left column', 0, r0.Left);
  AssertEquals('item 1 in left column', 0, r1.Left);
  AssertEquals('item 1 second row (fills first column top-down)', 20, r1.Top);
  AssertEquals('item 2 in right column', 100, r2.Left);
  AssertEquals('item 2 top row', 0, r2.Top);
  AssertEquals('item 3 second row', 20, r3.Top);
end;

procedure TCheckGroupLayoutTest.TestLastColumnAbsorbsWidthRemainder;
var r0, r1: TRect;
begin
  // width 201, 2 columns: colW = 100; last column runs to 201.
  // Row-major: the right column is index 1.
  r0 := TyCheckGroupCellRect(Rect(0, 0, 201, 400), 4, 2, 0, 20);   // left col
  r1 := TyCheckGroupCellRect(Rect(0, 0, 201, 400), 4, 2, 1, 20);   // right col
  AssertEquals('left column right edge = colW', 100, r0.Right);
  AssertEquals('right column extends to full width (absorbs remainder)', 201, r1.Right);
end;

procedure TCheckGroupLayoutTest.TestOutOfRangeYieldsEmpty;
var r: TRect;
begin
  r := TyCheckGroupCellRect(Rect(0, 0, 100, 100), 3, 1, -1, 20);
  AssertTrue('negative index -> empty', (r.Right - r.Left = 0) and (r.Bottom - r.Top = 0));
  r := TyCheckGroupCellRect(Rect(0, 0, 100, 100), 3, 1, 3, 20);
  AssertTrue('index >= count -> empty', (r.Right - r.Left = 0) and (r.Bottom - r.Top = 0));
  r := TyCheckGroupCellRect(Rect(0, 0, 100, 100), 0, 1, 0, 20);
  AssertTrue('zero count -> empty', (r.Right - r.Left = 0) and (r.Bottom - r.Top = 0));
  r := TyCheckGroupCellRect(Rect(0, 0, 100, 100), 3, 0, 0, 20);
  AssertTrue('zero columns -> empty', (r.Right - r.Left = 0) and (r.Bottom - r.Top = 0));
  r := TyCheckGroupCellRect(Rect(0, 0, 100, 100), 3, 1, 0, 0);
  AssertTrue('zero rowH -> empty', (r.Right - r.Left = 0) and (r.Bottom - r.Top = 0));
end;

procedure TCheckGroupLayoutTest.TestMoreColumnsThanItemsClamped;
var r0, r1: TRect;
begin
  // 2 items but 5 requested columns: effective columns clamp to 2, each ~half width.
  r0 := TyCheckGroupCellRect(Rect(0, 0, 100, 200), 2, 5, 0, 20);
  r1 := TyCheckGroupCellRect(Rect(0, 0, 100, 200), 2, 5, 1, 20);
  AssertEquals('item 0 left column', 0, r0.Left);
  AssertEquals('item 1 right column (not stacked)', 50, r1.Left);
  AssertEquals('both on the top row', 0, r0.Top);
  AssertEquals('item 1 also top row', 0, r1.Top);
end;

initialization
  RegisterTest(TCheckGroupTest);
  RegisterTest(TCheckGroupLayoutTest);
end.
