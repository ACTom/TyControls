unit test.radiogroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Base, tyControls.CheckBox, tyControls.RadioGroup;
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
    procedure TestCellRectColumnMajorOrder;
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
    procedure TestItemIndexOutOfRangeClears;
    procedure TestChildrenAreMutuallyExclusive;
    // rebuild survives selection
    procedure TestRebuildPreservesValidIndex;
    procedure TestRebuildDropsNowInvalidIndex;
    // events
    procedure TestClickFiresSelectionChanged;
    procedure TestProgrammaticSetIsSilent;
    // designer hygiene
    procedure TestChildrenAreNoDesignVisible;
    procedure TestChildrenOwnedByGroup;
    procedure TestColumnsClampToOne;
  end;

implementation

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

procedure TRadioGroupTest.TestCellRectColumnMajorOrder;
var
  client: TRect;
  c0, c1, c2, c3: TRect;
begin
  // 4 items, 2 columns => rows = 2. Column-major: index 0,1 in col0 (rows 0,1),
  // index 2,3 in col1 (rows 0,1).
  client := Rect(0, 0, 200, 120);
  c0 := TyRadioGroupCellRect(client, 4, 2, 0);
  c1 := TyRadioGroupCellRect(client, 4, 2, 1);
  c2 := TyRadioGroupCellRect(client, 4, 2, 2);
  c3 := TyRadioGroupCellRect(client, 4, 2, 3);
  // 0 and 1 share the left column (same Left), 2 and 3 the right column.
  AssertEquals('idx0 left col', c0.Left, c1.Left);
  AssertEquals('idx2 right col', c2.Left, c3.Left);
  AssertTrue('right column is further right', c2.Left > c0.Left);
  // 0 above 1 (column-major fills down first)
  AssertTrue('idx1 below idx0 in same column', c1.Top > c0.Top);
  // 0 and 2 are the top row of their columns -> same Top
  AssertEquals('idx0 and idx2 same row', c0.Top, c2.Top);
end;

procedure TRadioGroupTest.TestCellRectTwoColumnsSplitWidth;
var
  client: TRect;
  c0, c2: TRect;
begin
  client := Rect(0, 0, 200, 120);
  c0 := TyRadioGroupCellRect(client, 4, 2, 0);   // col 0
  c2 := TyRadioGroupCellRect(client, 4, 2, 2);   // col 1
  AssertEquals('col0 left', 0, c0.Left);
  AssertEquals('col0 right = half', 100, c0.Right);
  AssertEquals('col1 left = half', 100, c2.Left);
  AssertEquals('col1 right = full', 200, c2.Right);
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

procedure TRadioGroupTest.TestCellRectRowsCeil;
var
  client: TRect;
  c0, c1, c2, c3, c4: TRect;
begin
  // 5 items, 2 columns => rows = ceil(5/2) = 3. col0: 0,1,2 ; col1: 3,4.
  client := Rect(0, 0, 200, 200);
  c0 := TyRadioGroupCellRect(client, 5, 2, 0);
  c1 := TyRadioGroupCellRect(client, 5, 2, 1);
  c2 := TyRadioGroupCellRect(client, 5, 2, 2);
  c3 := TyRadioGroupCellRect(client, 5, 2, 3);
  c4 := TyRadioGroupCellRect(client, 5, 2, 4);
  // col0 holds 3 rows
  AssertEquals('c0,c1 same col', c0.Left, c1.Left);
  AssertEquals('c1,c2 same col', c1.Left, c2.Left);
  AssertTrue('c3 in the second column', c3.Left > c0.Left);
  AssertEquals('c3,c4 same col', c3.Left, c4.Left);
  // c3 aligns to the top row of col1 (same Top as c0)
  AssertEquals('c3 top-row aligns with c0', c0.Top, c3.Top);
  AssertTrue('c4 below c3', c4.Top > c3.Top);
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

procedure TRadioGroupTest.TestItemIndexOutOfRangeClears;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.ItemIndex := 1;
  AssertEquals('set to 1', 1, FGrp.ItemIndex);
  FGrp.ItemIndex := 99;   // out of range -> clears
  AssertEquals('out-of-range clears selection', -1, FGrp.ItemIndex);
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

procedure TRadioGroupTest.TestProgrammaticSetIsSilent;
begin
  FGrp.Items.Add('A');
  FGrp.Items.Add('B');
  FGrp.OnSelectionChanged := @OnSel;
  FSelCount := 0;
  FGrp.ItemIndex := 1;   // programmatic -> must NOT fire OnSelectionChanged
  AssertEquals('programmatic set is silent', 0, FSelCount);
  AssertEquals('but the index still took', 1, FGrp.ItemIndex);
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
