unit test.radiogroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, ExtCtrls, LCLType,
  fpcunit, testregistry,
  tyControls.Base, tyControls.Controller, tyControls.CheckBox, tyControls.RadioGroup;
type
  TRadioGroupTest = class(TTestCase)
  private
    FForm: TForm;
    FGrp: TTyRadioGroup;
    function SelChangeFired: Boolean;
    procedure OnSel(Sender: TObject);
  private
    FSelCount: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // typeKey / basics
    procedure TestTypeKeyInherited;
    procedure TestDefaultColumns;
    // pure layout math
    procedure TestCellRectSingleColumnStacks;
    procedure TestCellRectRowMajorIsTheDefaultOrder;
    procedure TestCellRectColumnMajorIsOptIn;
    procedure TestCellRectTwoColumnsSplitWidth;
    procedure TestCellRectLastColumnAbsorbsRemainder;
    procedure TestCellRectDegenerate;
    procedure TestCellRectRowsCeil;
    // Items -> child count
    procedure TestItemsPopulateChildren;
    procedure TestItemsRebuildReplacesChildren;
    procedure TestEmptyItemsNoChildren;
    // ItemIndex round-trip
    procedure TestItemIndexWriteChecksChild;
    procedure TestItemIndexReadReflectsChecked;
    procedure TestItemIndexOutOfRangeRaises;
    procedure TestChildrenAreMutuallyExclusive;
    // rebuild survives selection
    procedure TestRebuildPreservesValidIndex;
    procedure TestRebuildDropsNowInvalidIndex;
    procedure TestRebuildPreservesSelectionByIdentity;
    procedure TestControllerPropagatesToChildren;
    // events
    procedure TestClickFiresSelectionChanged;
    procedure TestProgrammaticSetNotifiesToo;
    // designer hygiene
    procedure TestChildrenAreNoDesignVisible;
    procedure TestChildrenOwnedByGroup;
    procedure TestColumnsClampToOne;
  end;

implementation

procedure TRadioGroupTest.TestRebuildPreservesSelectionByIdentity;
begin
  // A mid-list delete must keep the selection on its OWN item, not on the raw slot.
  FGrp.Items.CommaText := 'A,B,C';
  FGrp.ItemIndex := 2;                 // 'C'
  FGrp.Items.Delete(0);                // -> ['B','C']; the selection must FOLLOW 'C' to index 1
  AssertEquals('selection follows the item, not the slot', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestControllerPropagatesToChildren;
var
  Ctl: TTyStyleController;
  i, seen: Integer;
begin
  // A controller assigned AFTER population must re-push onto the existing radio children.
  FGrp.Items.CommaText := 'A,B';       // radios built with the current controller
  Ctl := TTyStyleController.Create(nil);
  try
    FGrp.Controller := Ctl;
    seen := 0;
    for i := 0 to FGrp.ControlCount - 1 do
      if FGrp.Controls[i] is TTyRadioButton then
      begin
        AssertTrue('child follows the group controller',
          TTyRadioButton(FGrp.Controls[i]).Controller = Ctl);
        Inc(seen);
      end;
    AssertEquals('both radios present', 2, seen);
  finally
    FGrp.Controller := nil;            // detach children before freeing the controller
    Ctl.Free;
  end;
end;

function TRadioGroupTest.SelChangeFired: Boolean;
begin
  Result := FSelCount > 0;
end;

procedure TRadioGroupTest.OnSel(Sender: TObject);
begin
  Inc(FSelCount);
end;

procedure TRadioGroupTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 260);
  FGrp := TTyRadioGroup.Create(FForm);
  FGrp.Parent := FForm;
  FGrp.SetBounds(0, 0, 185, 130);
  FGrp.Font.PixelsPerInch := 96;
  FSelCount := 0;
end;

procedure TRadioGroupTest.TearDown;
begin
  FForm.Free;
end;

{ ---- typeKey / basics ---------------------------------------------------- }

procedure TRadioGroupTest.TestTypeKeyInherited;
begin
  // Reuses the inherited TyGroupBox token — NO new .tycss rule.
  AssertEquals('TyGroupBox', (FGrp as ITyStyleable).GetStyleTypeKey);
end;

procedure TRadioGroupTest.TestDefaultColumns;
begin
  AssertEquals('default Columns = 1', 1, FGrp.Columns);
end;

{ ---- pure layout math ---------------------------------------------------- }

procedure TRadioGroupTest.TestCellRectSingleColumnStacks;
var
  client: TRect;
  c0, c1, c2: TRect;
begin
  // 3 items, 1 column, a client tall enough that the grid is NOT centered off (grid
  // 66 < 200) -> rows stack by 22 from a centered top.
  client := Rect(0, 0, 180, 200);
  c0 := TyRadioGroupCellRect(client, 3, 1, 0);
  c1 := TyRadioGroupCellRect(client, 3, 1, 1);
  c2 := TyRadioGroupCellRect(client, 3, 1, 2);
  // one column -> full client width
  AssertEquals('col width = full client', 0, c0.Left);
  AssertEquals('col width = full client', 180, c0.Right);
  // stacked by row height (22)
  AssertEquals('row spacing = 22', c0.Top + 22, c1.Top);
  AssertEquals('row spacing = 22', c1.Top + 22, c2.Top);
  AssertEquals('row height = 22', 22, c0.Bottom - c0.Top);
end;

{ RENAMED. This used to be TestCellRectColumnMajorOrder and it asserted, by name, the very
  thing that was wrong: the grid filled DOWN column 0 first while the same .lfm loaded in
  Lazarus filled ACROSS row 0 first, so a ported multi-column group silently reordered the
  user's options and nothing anywhere said so. The default is now LCL's. }
procedure TRadioGroupTest.TestCellRectRowMajorIsTheDefaultOrder;
var
  client: TRect;
  c0, c1, c2, c3: TRect;
begin
  // 4 items, 2 columns => 2 rows. Row-major: index 0,1 across row 0; index 2,3 across row 1.
  client := Rect(0, 0, 200, 120);
  c0 := TyRadioGroupCellRect(client, 4, 2, 0);
  c1 := TyRadioGroupCellRect(client, 4, 2, 1);
  c2 := TyRadioGroupCellRect(client, 4, 2, 2);
  c3 := TyRadioGroupCellRect(client, 4, 2, 3);
  // 0 and 1 share the TOP row; 2 and 3 the second one.
  AssertEquals('idx0 and idx1 on the same row', c0.Top, c1.Top);
  AssertEquals('idx2 and idx3 on the same row', c2.Top, c3.Top);
  AssertTrue('the second row is lower', c2.Top > c0.Top);
  // 1 is to the RIGHT of 0 (row-major fills across first)
  AssertTrue('idx1 right of idx0 on the same row', c1.Left > c0.Left);
  // 0 and 2 head their rows -> same Left
  AssertEquals('idx0 and idx2 start the same column', c0.Left, c2.Left);
end;

{ The opt-out. Column-major is still reachable, it is simply no longer the silent default. }
procedure TRadioGroupTest.TestCellRectColumnMajorIsOptIn;
var
  client: TRect;
  c0, c1, c2, c3: TRect;
begin
  client := Rect(0, 0, 200, 120);
  c0 := TyRadioGroupCellRect(client, 4, 2, 0, 0, clVerticalThenHorizontal);
  c1 := TyRadioGroupCellRect(client, 4, 2, 1, 0, clVerticalThenHorizontal);
  c2 := TyRadioGroupCellRect(client, 4, 2, 2, 0, clVerticalThenHorizontal);
  c3 := TyRadioGroupCellRect(client, 4, 2, 3, 0, clVerticalThenHorizontal);
  AssertEquals('idx0 left col', c0.Left, c1.Left);
  AssertEquals('idx2 right col', c2.Left, c3.Left);
  AssertTrue('right column is further right', c2.Left > c0.Left);
  AssertTrue('idx1 below idx0 in same column', c1.Top > c0.Top);
  AssertEquals('idx0 and idx2 same row', c0.Top, c2.Top);
end;

procedure TRadioGroupTest.TestCellRectTwoColumnsSplitWidth;
var
  client: TRect;
  c0, c1: TRect;
begin
  client := Rect(0, 0, 200, 120);
  // Row-major: the SECOND column is index 1, not index 2.
  c0 := TyRadioGroupCellRect(client, 4, 2, 0);   // col 0
  c1 := TyRadioGroupCellRect(client, 4, 2, 1);   // col 1
  AssertEquals('col0 left', 0, c0.Left);
  AssertEquals('col0 right = half', 100, c0.Right);
  AssertEquals('col1 left = half', 100, c1.Left);
  AssertEquals('col1 right = full', 200, c1.Right);
end;

procedure TRadioGroupTest.TestCellRectLastColumnAbsorbsRemainder;
var
  client: TRect;
  c0, c1, c2: TRect;
begin
  // width 205 / 3 columns = 68 each, last column extends to 205.
  client := Rect(0, 0, 205, 120);
  c0 := TyRadioGroupCellRect(client, 3, 3, 0);
  c1 := TyRadioGroupCellRect(client, 3, 3, 1);
  c2 := TyRadioGroupCellRect(client, 3, 3, 2);
  AssertEquals('col0 0..68', 0, c0.Left);
  AssertEquals('col0 right', 68, c0.Right);
  AssertEquals('col1 68..136', 68, c1.Left);
  AssertEquals('col1 right', 136, c1.Right);
  AssertEquals('col2 left', 136, c2.Left);
  AssertEquals('col2 absorbs remainder to 205', 205, c2.Right);
end;

procedure TRadioGroupTest.TestCellRectDegenerate;
begin
  AssertTrue('count<=0 -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 0, 1, 0)));
  AssertTrue('columns<=0 -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 3, 0, 0)));
  AssertTrue('index<0 -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 3, 1, -1)));
  AssertTrue('index>=count -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,180,120), 3, 1, 3)));
  AssertTrue('zero-area client -> empty', IsRectEmpty(TyRadioGroupCellRect(Rect(0,0,0,0), 3, 1, 0)));
end;

{ Row count is ceil(Count/Columns) in BOTH fill orders — that is what makes the two orders a
  permutation of the same grid rather than two different grids. Asserted on the column-major
  order, where the row count is what decides when a column wraps. }
procedure TRadioGroupTest.TestCellRectRowsCeil;
var
  client: TRect;
  c0, c1, c2, c3, c4: TRect;
begin
  // 5 items, 2 columns => rows = ceil(5/2) = 3. Column-major: col0 gets 0,1,2 ; col1 gets 3,4.
  client := Rect(0, 0, 200, 200);
  c0 := TyRadioGroupCellRect(client, 5, 2, 0, 0, clVerticalThenHorizontal);
  c1 := TyRadioGroupCellRect(client, 5, 2, 1, 0, clVerticalThenHorizontal);
  c2 := TyRadioGroupCellRect(client, 5, 2, 2, 0, clVerticalThenHorizontal);
  c3 := TyRadioGroupCellRect(client, 5, 2, 3, 0, clVerticalThenHorizontal);
  c4 := TyRadioGroupCellRect(client, 5, 2, 4, 0, clVerticalThenHorizontal);
  // col0 holds 3 rows
  AssertEquals('c0,c1 same col', c0.Left, c1.Left);
  AssertEquals('c1,c2 same col', c1.Left, c2.Left);
  AssertTrue('c3 in the second column', c3.Left > c0.Left);
  AssertEquals('c3,c4 same col', c3.Left, c4.Left);
  // c3 aligns to the top row of col1 (same Top as c0)
  AssertEquals('c3 top-row aligns with c0', c0.Top, c3.Top);
  AssertTrue('c4 below c3', c4.Top > c3.Top);
  { The row-major default lays the SAME 5 items on the same 3 rows, just walked the other
    way: 0 1 / 2 3 / 4. Asserting the row count from both sides is what stops a future edit
    from "fixing" one order into a different grid shape. }
  AssertEquals('row-major puts idx2 on row 1',
    TyRadioGroupCellRect(client, 5, 2, 2).Top, c1.Top);
  AssertEquals('row-major puts idx4 on row 2',
    TyRadioGroupCellRect(client, 5, 2, 4).Top, c2.Top);
end;

{ ---- Items -> child count ------------------------------------------------ }

procedure TRadioGroupTest.TestItemsPopulateChildren;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  AssertEquals('one radio child per item', 3, FGrp.Count);
end;

procedure TRadioGroupTest.TestItemsRebuildReplacesChildren;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  AssertEquals('2 children', 2, FGrp.Count);
  FGrp.Items.Clear;
  FGrp.Items.Add('X');
  AssertEquals('rebuilt to 1 child', 1, FGrp.Count);
end;

procedure TRadioGroupTest.TestEmptyItemsNoChildren;
begin
  AssertEquals('no items -> no children', 0, FGrp.Count);
end;

{ ---- ItemIndex round-trip ------------------------------------------------ }

procedure TRadioGroupTest.TestItemIndexWriteChecksChild;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 1;
  AssertEquals('ItemIndex round-trips', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestItemIndexReadReflectsChecked;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  AssertEquals('no selection initially', -1, FGrp.ItemIndex);
  FGrp.ItemIndex := 0;
  AssertEquals('reads back index 0', 0, FGrp.ItemIndex);
end;

{ This asserted the clear in its own name -- the sixth test in this pass to pin the
  defect it was standing next to. Clearing made `ItemIndex := 99` on a two-item group
  indistinguishable from `ItemIndex := -1`, so an off-by-one read as "the user deselected". }
procedure TRadioGroupTest.TestItemIndexOutOfRangeRaises;
var
  raised: Boolean;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.ItemIndex := 1;
  AssertEquals('set to 1', 1, FGrp.ItemIndex);
  raised := False;
  try
    FGrp.ItemIndex := 99;
  except
    on E: EListError do raised := True;
  end;
  AssertTrue('out-of-range raises', raised);
  AssertEquals('and the selection survives the refusal', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestChildrenAreMutuallyExclusive;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 0;
  FGrp.ItemIndex := 2;
  // exactly one selected -> ItemIndex is a single value, confirms exclusivity
  AssertEquals('only the last set stays', 2, FGrp.ItemIndex);
end;

{ ---- rebuild survives selection ------------------------------------------ }

procedure TRadioGroupTest.TestRebuildPreservesValidIndex;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 1;
  // add a 4th item -> rebuild; index 1 still valid
  FGrp.Items.Add('D');
  AssertEquals('4 children now', 4, FGrp.Count);
  AssertEquals('index 1 survives the rebuild', 1, FGrp.ItemIndex);
end;

procedure TRadioGroupTest.TestRebuildDropsNowInvalidIndex;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.Items.Add('C');
  FGrp.ItemIndex := 2;
  // shrink to 1 item -> index 2 no longer valid -> cleared
  FGrp.Items.Clear;
  FGrp.Items.Add('Only');
  AssertEquals('1 child', 1, FGrp.Count);
  AssertEquals('stale index cleared after shrink', -1, FGrp.ItemIndex);
end;

{ ---- events -------------------------------------------------------------- }

procedure TRadioGroupTest.TestClickFiresSelectionChanged;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.OnSelectionChanged := @OnSel;
  FSelCount := 0;
  // Simulate a user click on the second radio child by invoking its Click (which the
  // base TTyRadioButton routes through Checked -> OnChange -> our ChildChanged).
  // The children are parented to the group in item order, so Controls[1] is item 1.
  (FGrp.Controls[1] as TTyRadioButton).Click;
  AssertTrue('click fired OnSelectionChanged', SelChangeFired);
  AssertEquals('selection moved to clicked child', 1, FGrp.ItemIndex);
  AssertEquals('exactly one fire for the gesture', 1, FSelCount);
end;

{ This used to assert silence -- its own name said IsSilent -- and that was the bug: the
  selection changed and nobody was told, so a handler keeping a detail panel in step with
  the choice worked when the user clicked and silently did not when the app restored a
  saved selection. LCL notifies either way, deliberately ("to be delphi compat"). The
  re-entrancy guard is still doing its job: ONE notification, not one per child. }
procedure TRadioGroupTest.TestProgrammaticSetNotifiesToo;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.OnSelectionChanged := @OnSel;
  FSelCount := 0;
  FGrp.ItemIndex := 1;
  AssertEquals('a programmatic set notifies', 1, FSelCount);
  AssertEquals('exactly once, not once per child', 1, FSelCount);
  AssertEquals('and the index took', 1, FGrp.ItemIndex);
  FGrp.ItemIndex := 1;
  AssertEquals('an unchanged write stays silent', 1, FSelCount);
end;

{ ---- designer hygiene ---------------------------------------------------- }

procedure TRadioGroupTest.TestChildrenAreNoDesignVisible;
var
  i: Integer;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  for i := 0 to FGrp.ControlCount - 1 do
    if FGrp.Controls[i] is TTyRadioButton then
      AssertTrue('radio child must be csNoDesignVisible',
        csNoDesignVisible in TTyRadioButton(FGrp.Controls[i]).ControlStyle);
end;

procedure TRadioGroupTest.TestChildrenOwnedByGroup;
begin
  FGrp.Items.Add('A');
  AssertSame('radio child owned by the group', FGrp, (FGrp.Controls[0] as TTyRadioButton).Owner);
  AssertSame('radio child parented to the group', FGrp, (FGrp.Controls[0] as TTyRadioButton).Parent);
end;

procedure TRadioGroupTest.TestColumnsClampToOne;
begin
  FGrp.Columns := 0;
  AssertEquals('columns clamp to >= 1', 1, FGrp.Columns);
  FGrp.Columns := -5;
  AssertEquals('negative clamps to 1', 1, FGrp.Columns);
  FGrp.Columns := 3;
  AssertEquals('valid columns accepted', 3, FGrp.Columns);
end;

initialization
  RegisterTest(TRadioGroupTest);
end.
