unit test.listselection;
{ #123: a list box's selection stays on the rows it was on through an insert, a delete and
  a rebuild; ItemIndex written with MultiSelect makes that row the selection, as LCL's
  (win32wsstdctrls.pp:1025); with ExtendedSelect = False the arrow keys move only the caret,
  as Win32 and Qt do; and TTyOfficeListBox's group headers cannot be selected through the
  multi-select paths either. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, LCLType, fpcunit, testregistry,
  tyControls.ListBox, tyControls.OfficeListBox;

type
  TListKeyProbe = class(TTyListBox)
  public
    procedure Key(AKey: Word; AShift: TShiftState);
  end;

  TOfficeKeyProbe = class(TTyOfficeListBox)
  public
    procedure Key(AKey: Word; AShift: TShiftState);
  end;

  TListSelectionTest = class(TTestCase)
  private
    FChanges: Integer;
    procedure Changed(Sender: TObject);
    function NewList(AMulti: Boolean): TListKeyProbe;
    function NewOffice: TOfficeKeyProbe;
  published
    procedure TestItemIndexInMultiSelectMakesThatRowTheSelection;
    procedure TestAnInsertMovesTheSelectionWithItsRow;
    procedure TestAnInsertMovesTheMultiSelection;
    procedure TestADeleteMovesTheSelectionWithItsRow;
    procedure TestDeletingTheSelectedRowSelectsNothing;
    procedure TestADeleteMovesTheMultiSelection;
    procedure TestANewListDropsTheSelection;
    procedure TestTheRangeAnchorFollowsItsRow;
    procedure TestSimpleMultiSelectArrowsMoveOnlyTheCaret;
    procedure TestOfficeArrowsStepOverAHeader;
    procedure TestOfficeRangeLeavesTheHeaderOut;
    procedure TestOfficeSelectAllLeavesTheHeadersOut;
  end;

implementation

procedure TListKeyProbe.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

procedure TOfficeKeyProbe.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

procedure TListSelectionTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

function TListSelectionTest.NewList(AMulti: Boolean): TListKeyProbe;
begin
  Result := TListKeyProbe.Create(nil);
  Result.MultiSelect := AMulti;
  Result.Items.Add('a');
  Result.Items.Add('b');
  Result.Items.Add('c');
  Result.Items.Add('d');
end;

function TListSelectionTest.NewOffice: TOfficeKeyProbe;
begin
  Result := TOfficeKeyProbe.Create(nil);
  Result.MultiSelect := True;
  Result.AddHeader('Group 1');   // 0
  Result.AddItem('a');           // 1
  Result.AddHeader('Group 2');   // 2
  Result.AddItem('b');           // 3
end;

procedure TListSelectionTest.TestItemIndexInMultiSelectMakesThatRowTheSelection;
var
  l: TListKeyProbe;
begin
  l := NewList(True);
  try
    l.Selected[0] := True;
    l.Selected[2] := True;
    l.ItemIndex := 3;
    AssertEquals('one row selected', 1, l.SelCount);
    AssertTrue('the written one', l.Selected[3]);
    AssertFalse('the others let go', l.Selected[0]);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestAnInsertMovesTheSelectionWithItsRow;
var
  l: TListKeyProbe;
begin
  l := NewList(False);
  try
    l.ItemIndex := 1;
    l.Items.Insert(0, 'z');
    AssertEquals('the selection follows its row', 'b', l.Items[l.ItemIndex]);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestAnInsertMovesTheMultiSelection;
var
  l: TListKeyProbe;
begin
  l := NewList(True);
  try
    l.Selected[1] := True;
    l.Selected[2] := True;
    l.Items.Insert(1, 'z');
    AssertFalse('the new row is not selected', l.Selected[1]);
    AssertTrue('b still is', l.Selected[2]);
    AssertTrue('and c', l.Selected[3]);
    AssertEquals('two rows', 2, l.SelCount);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestADeleteMovesTheSelectionWithItsRow;
var
  l: TListKeyProbe;
begin
  l := NewList(False);
  try
    l.ItemIndex := 2;
    l.Items.Delete(0);
    AssertEquals('the selection follows its row', 'c', l.Items[l.ItemIndex]);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestDeletingTheSelectedRowSelectsNothing;
var
  l: TListKeyProbe;
begin
  l := NewList(False);
  try
    l.ItemIndex := 1;
    l.Items.Delete(1);
    AssertEquals('it went with its row', -1, l.ItemIndex);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestADeleteMovesTheMultiSelection;
var
  l: TListKeyProbe;
begin
  l := NewList(True);
  try
    l.Selected[3] := True;
    l.Items.Delete(1);
    AssertTrue('d, now row 2, still selected', l.Selected[2]);
    AssertEquals('one row', 1, l.SelCount);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestANewListDropsTheSelection;
var
  l: TListKeyProbe;
  other: TStringList;
begin
  l := NewList(False);
  other := TStringList.Create;
  try
    other.Add('w');
    other.Add('x');
    other.Add('y');
    other.Add('z');
    l.ItemIndex := 1;
    l.Items.Assign(other);
    AssertEquals('none of the new rows was selected', -1, l.ItemIndex);
    l.ItemIndex := 2;
    FChanges := 0;
    l.OnChange := @Changed;
    l.Items := other;   // the property: SetItems, which does its own bookkeeping
    AssertEquals('the same through Items :=', -1, l.ItemIndex);
    AssertEquals('and the selection that went is reported', 1, FChanges);
  finally
    other.Free;
    l.Free;
  end;
end;

procedure TListSelectionTest.TestTheRangeAnchorFollowsItsRow;
var
  l: TListKeyProbe;
begin
  l := NewList(True);
  try
    l.ItemIndex := 1;            // b: the caret and the anchor
    l.Items.Insert(0, 'z');      // b is row 2 now
    l.Key(VK_DOWN, [ssShift]);
    AssertEquals('the range runs from b', 2, l.SelCount);
    AssertFalse('not from the row b left', l.Selected[1]);
    l.ItemIndex := 2;            // b again
    l.Items.Delete(0);           // b is row 1
    l.Key(VK_DOWN, [ssShift]);
    AssertEquals('from b after a delete too', 2, l.SelCount);
    AssertTrue('b in it', l.Selected[1]);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestSimpleMultiSelectArrowsMoveOnlyTheCaret;
var
  l: TListKeyProbe;
begin
  l := NewList(True);
  try
    l.ExtendedSelect := False;
    l.Selected[0] := True;
    l.Key(VK_DOWN, []);
    l.Key(VK_DOWN, []);
    AssertEquals('the caret moved', 1, l.ItemIndex);
    AssertTrue('the selection did not', l.Selected[0]);
    AssertFalse('the caret''s row is not selected by the move', l.Selected[1]);
    l.Key(VK_DOWN, [ssShift]);
    AssertEquals('no ranges either', 1, l.SelCount);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestOfficeArrowsStepOverAHeader;
var
  l: TOfficeKeyProbe;
begin
  l := NewOffice;
  try
    l.ItemIndex := 1;
    l.Key(VK_DOWN, []);
    AssertEquals('onto the next item, not the header', 3, l.ItemIndex);
    AssertFalse('the header is not selected', l.Selected[2]);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestOfficeRangeLeavesTheHeaderOut;
var
  l: TOfficeKeyProbe;
begin
  l := NewOffice;
  try
    l.ItemIndex := 1;
    l.Key(VK_DOWN, [ssShift]);
    AssertTrue('the range reaches b', l.Selected[3]);
    AssertFalse('without the header between', l.Selected[2]);
    l.SelectRange(0, 3, True);
    AssertFalse('nor through SelectRange', l.Selected[0]);
  finally
    l.Free;
  end;
end;

procedure TListSelectionTest.TestOfficeSelectAllLeavesTheHeadersOut;
var
  l: TOfficeKeyProbe;
begin
  l := NewOffice;
  try
    l.SelectAll;
    AssertEquals('the two items', 2, l.SelCount);
    l.Selected[0] := True;
    AssertFalse('nor through Selected[]', l.Selected[0]);
  finally
    l.Free;
  end;
end;

initialization
  RegisterTest(TListSelectionTest);
end.
