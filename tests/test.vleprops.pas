unit test.vleprops;
{ #124: TTyValueListEditor's Sorted orders the root rows it shows and keeps rows that share a
  key; with ScrollWidth the splitter, the expand triangles and the cell editor scroll with the
  rows; ReadOnly set while a cell editor is open closes it without committing; and the
  multi-selection stays on its rows through an expand. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, LCLType, fpcunit, testregistry,
  tyControls.ValueListEditor;

type
  TVleProbe = class(TTyValueListEditor)
  public
    procedure ScrollSideways(ADx: Integer);
    { Where the paint puts the row: RenderTo hands PaintItemContent these bounds. }
    function RowLeft: Integer;
    function RowRight: Integer;
    procedure Down(X, Y: Integer);
    procedure Move(X, Y: Integer);
    procedure Up(X, Y: Integer);
  end;

  TVlePropsTest = class(TTestCase)
  private
    function NewScrolled: TVleProbe;
  published
    procedure TestSortedOrdersTheRowsAndKeepsDuplicates;
    procedure TestARenameKeepsTheOrder;
    procedure TestATypedRenameKeepsTheOrder;
    procedure TestTheSplitterScrollsWithTheRows;
    procedure TestTheTriangleScrollsWithTheRows;
    procedure TestTheEditorScrollsWithTheRows;
    procedure TestReadOnlyClosesAnOpenEditorUncommitted;
    procedure TestTheMultiSelectionStaysOnItsRowsThroughAnExpand;
  end;

implementation

procedure TVleProbe.ScrollSideways(ADx: Integer);
begin
  HScrollOffset := ADx;
end;

function TVleProbe.RowLeft: Integer;
var r: Integer;
begin
  RowContentBounds(ClientWidth, Font.PixelsPerInch, Result, r);
end;

function TVleProbe.RowRight: Integer;
var l: Integer;
begin
  RowContentBounds(ClientWidth, Font.PixelsPerInch, l, Result);
end;

procedure TVleProbe.Down(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TVleProbe.Move(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TVleProbe.Up(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

function TVlePropsTest.NewScrolled: TVleProbe;
begin
  Result := TVleProbe.Create(nil);
  Result.SetBounds(0, 0, 300, 200);
  Result.Font.PixelsPerInch := 96;
  Result.ScrollWidth := 900;
  Result.ScrollSideways(60);
end;

procedure TVlePropsTest.TestSortedOrdersTheRowsAndKeepsDuplicates;
var
  v: TTyValueListEditor;
begin
  v := TTyValueListEditor.Create(nil);
  try
    v.AddRow('b', '1');
    v.AddRow('a', '2');
    v.AddRow('a', '3');
    v.Sorted := True;
    AssertEquals('every row is still there', 3, v.RowCount);
    AssertEquals('and shown', 3, v.Items.Count);
    AssertEquals('in key order', 'a', v.Keys[0]);
    AssertEquals('the rows sharing a key in the order they came', '2', v.ValueFromIndex[0]);
    AssertEquals('', '3', v.ValueFromIndex[1]);
    AssertEquals('', 'b', v.Keys[2]);
  finally
    v.Free;
  end;
end;

procedure TVlePropsTest.TestARenameKeepsTheOrder;
var
  v: TTyValueListEditor;
begin
  v := TTyValueListEditor.Create(nil);
  try
    v.Sorted := True;
    v.AddRow('a', '1');
    v.AddRow('b', '2');
    v.AddRow('c', '3');
    v.Keys[0] := 'z';
    AssertEquals('the renamed row moves to its place', 'z', v.Keys[2]);
    AssertEquals('', 'b', v.Keys[0]);
  finally
    v.Free;
  end;
end;

procedure TVlePropsTest.TestATypedRenameKeepsTheOrder;
var
  v: TTyValueListEditor;
  k: Word;
begin
  v := TTyValueListEditor.Create(nil);
  try
    v.SetBounds(0, 0, 200, 200);
    v.Font.PixelsPerInch := 96;
    v.KeyOptions := [keyEdit];
    v.Sorted := True;
    v.AddRow('a', '1');
    v.AddRow('b', '2');
    v.AddRow('c', '3');
    v.BeginKeyEdit(0);
    v.InlineEditor.Text := 'z';
    k := VK_RETURN;
    v.InlineEditor.OnKeyDown(v.InlineEditor, k, []);   // Enter commits the rename
    AssertEquals('the renamed row moves to its place', 'z', v.Keys[2]);
  finally
    v.Free;
  end;
end;

procedure TVlePropsTest.TestTheSplitterScrollsWithTheRows;
var
  v: TVleProbe;
  split: Integer;
begin
  v := NewScrolled;
  try
    v.AddRow('k', 'v');
    split := v.RowLeft + v.KeyColumnWidth;   // where PaintItemContent draws the divider
    v.Down(split, 5);
    v.Move(split + 20, 5);
    v.Up(split + 20, 5);
    AssertEquals('the drawn divider is the one that drags', 130, v.KeyColumnWidth);
  finally
    v.Free;
  end;
end;

procedure TVlePropsTest.TestTheTriangleScrollsWithTheRows;
var
  v: TVleProbe;
  r: TTyValueRow;
begin
  v := NewScrolled;
  try
    r := v.AddRow('parent', '');
    r.AddChild('child', '1');
    v.SetExpanded(r, False);   // rows with children start expanded
    v.Down(v.RowLeft + 4, v.ItemRect(0).Top + 4);   // on the drawn triangle
    AssertTrue('the drawn triangle expands', r.Expanded);
  finally
    v.Free;
  end;
end;

procedure TVlePropsTest.TestTheEditorScrollsWithTheRows;
var
  v: TVleProbe;
begin
  v := NewScrolled;
  try
    v.AddRow('k', 'v');
    v.BeginEdit(0);
    AssertEquals('the editor opens over the drawn value cell',
      v.RowLeft + v.KeyColumnWidth, v.InlineEditor.Left);
    AssertEquals('to its drawn right edge', v.RowRight,
      v.InlineEditor.Left + v.InlineEditor.Width);
  finally
    v.Free;
  end;
end;

procedure TVlePropsTest.TestReadOnlyClosesAnOpenEditorUncommitted;
var
  v: TTyValueListEditor;
begin
  v := TTyValueListEditor.Create(nil);
  try
    v.SetBounds(0, 0, 200, 200);
    v.Font.PixelsPerInch := 96;
    v.AddRow('k', 'old');
    v.BeginEdit(0);
    AssertEquals('setup: the editor is open', 0, v.EditingRow);
    v.InlineEditor.Text := 'new';
    v.ReadOnly := True;
    AssertEquals('closed', -1, v.EditingRow);
    AssertEquals('without the edit', 'old', v.ValueFromIndex[0]);
  finally
    v.Free;
  end;
end;

procedure TVlePropsTest.TestTheMultiSelectionStaysOnItsRowsThroughAnExpand;
var
  v: TTyValueListEditor;
  a: TTyValueRow;
begin
  v := TTyValueListEditor.Create(nil);
  try
    v.MultiSelect := True;
    a := v.AddRow('a', '');
    a.AddChild('a1', '');
    v.AddRow('b', '');
    v.AddRow('c', '');
    v.SetExpanded(a, False); // rows with children start expanded
    v.Selected[1] := True;   // b
    v.Selected[2] := True;   // c
    v.SetExpanded(a, True);  // a1 is row 1 now
    AssertFalse('the new row is not selected', v.Selected[1]);
    AssertTrue('b still is', v.Selected[2]);
    AssertTrue('and c', v.Selected[3]);
  finally
    v.Free;
  end;
end;

initialization
  RegisterTest(TVlePropsTest);
end.
