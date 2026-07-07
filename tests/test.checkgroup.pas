unit test.checkgroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.CheckBox, tyControls.CheckGroup;
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
    procedure TestCheckedOutOfRangeSafe;
    procedure TestCheckedCount;
    procedure TestToggleFiresOnItemChange;
    procedure TestSetCheckedFiresOnItemChange;
    procedure TestRebuildPreservesCheckedByIndex;
    procedure TestRebuildPreservesCheckedByIdentityOnDelete;
    procedure TestRebuildDoesNotFireOnItemChange;
    procedure TestIsDesignerContainerInherited;
  end;

  { The pure column-layout function is the headless-tested geometry core. }
  TCheckGroupLayoutTest = class(TTestCase)
  published
    procedure TestSingleColumnStacksRows;
    procedure TestTwoColumnsSplitWidthAndFillFirstColumn;
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

procedure TCheckGroupTest.TestCheckedOutOfRangeSafe;
var
  F: TForm;
  G: TTyCheckGroup;
begin
  F := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(F);
    G.Parent := F;
    G.Items.Add('only');
    AssertFalse('read below range -> False', G.Checked[-1]);
    AssertFalse('read above range -> False', G.Checked[5]);
    G.Checked[-1] := True;   // must be a no-op, not a crash
    G.Checked[9] := True;    // must be a no-op, not a crash
    AssertFalse('the real item stays unchecked', G.Checked[0]);
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

procedure TCheckGroupTest.TestSetCheckedFiresOnItemChange;
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
    AssertEquals('Checked[0]:=True fires OnItemChange once', 1, FItemChangeCount);
    AssertEquals('event carries index 0', 0, FLastItemChangeIdx);

    FItemChangeCount := 0;
    G.Checked[0] := True;   // same value -> child OnChange has an early-out -> no fire
    AssertEquals('setting the same value does not fire', 0, FItemChangeCount);
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

procedure TCheckGroupLayoutTest.TestTwoColumnsSplitWidthAndFillFirstColumn;
var r0, r1, r2, r3: TRect;
begin
  // 4 items, 2 columns, width 200 -> two 100px columns, 2 rows each.
  // Fill column 0 first (indices 0,1), then column 1 (indices 2,3).
  r0 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 0, 20);
  r1 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 1, 20);
  r2 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 2, 20);
  r3 := TyCheckGroupCellRect(Rect(0, 0, 200, 400), 4, 2, 3, 20);

  AssertEquals('item 0 in left column', 0, r0.Left);
  AssertEquals('item 1 in left column', 0, r1.Left);
  AssertEquals('item 0 top row', 0, r0.Top);
  AssertEquals('item 1 second row (fills first column top-down)', 20, r1.Top);

  AssertEquals('item 2 in right column', 100, r2.Left);
  AssertEquals('item 3 in right column', 100, r3.Left);
  AssertEquals('item 2 top row', 0, r2.Top);
  AssertEquals('item 3 second row', 20, r3.Top);
end;

procedure TCheckGroupLayoutTest.TestLastColumnAbsorbsWidthRemainder;
var r0, r1: TRect;
begin
  // width 201, 2 columns: colW = 100; last column runs to 201.
  r0 := TyCheckGroupCellRect(Rect(0, 0, 201, 400), 4, 2, 0, 20);   // left col
  r1 := TyCheckGroupCellRect(Rect(0, 0, 201, 400), 4, 2, 2, 20);   // right col (index 2)
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
