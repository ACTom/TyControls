unit test.columns.compat;
{$mode objfpc}{$H+}
{ Guards the deprecated tyControls.TreeView.Columns shim.

  Nothing else in the repo uses that unit any more, so without this test it would never be
  compiled and could rot silently. It exercises exactly what v2.2 code does: `uses
  tyControls.TreeView.Columns`, the old type names, and the enum VALUES — a type alias does
  not carry an enumeration's values into scope, so the shim has to re-export them by hand. }
interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  {$WARN SYMBOL_DEPRECATED OFF}
  {$WARN 5043 OFF}   // "Symbol is deprecated" — the whole point of this unit
  tyControls.TreeView.Columns,
  tyControls.Columns;

type
  TColumnsCompatTest = class(TTestCase)
  published
    procedure TestOldTypeNamesStillResolve;
    procedure TestOldEnumValuesStillResolve;
    procedure TestAliasesAreTheSameTypes;
    procedure TestClassAliasRegisteredForOldLfm;
  end;

implementation

procedure TColumnsCompatTest.TestOldTypeNamesStillResolve;
var
  hdr: tyControls.TreeView.Columns.TTyTreeHeader;
  col: tyControls.TreeView.Columns.TTyTreeColumn;
begin
  hdr := tyControls.TreeView.Columns.TTyTreeHeader.Create;
  try
    // The v2.2 idiom: add a column through the collection and cast to the old name.
    col := hdr.Columns.Add as tyControls.TreeView.Columns.TTyTreeColumn;
    col.Text := 'Name';
    col.Width := 120;
    AssertEquals('column added', 1, hdr.Columns.Count);
    AssertEquals('width kept', 120, hdr.Columns.TotalWidth);
    AssertEquals('NoColumn re-exported', -1, tyControls.TreeView.Columns.NoColumn);
  finally
    hdr.Free;
  end;
end;

procedure TColumnsCompatTest.TestOldEnumValuesStillResolve;
var
  opts: tyControls.TreeView.Columns.TTyTreeColumnOptions;
  hopts: tyControls.TreeView.Columns.TTyTreeHeaderOptions;
  dir: tyControls.TreeView.Columns.TTySortDirection;
begin
  // Set literals over the re-exported enum values — the thing a bare type alias breaks.
  opts := [coVisible, coResizable, coAllowClick, coDraggable, coAutoSpring];
  AssertTrue('coVisible in set', coVisible in opts);

  hopts := [hoVisible, hoColumnResize, hoShowSortGlyphs, hoHeaderClickAutoSort,
            hoDrag, hoAutoResize, hoHotTrack];
  AssertTrue('hoHotTrack in set', hoHotTrack in hopts);

  dir := sdDescending;
  AssertTrue('sdDescending resolves', dir = sdDescending);
  AssertTrue('sdAscending resolves', sdAscending <> sdDescending);
end;

procedure TColumnsCompatTest.TestAliasesAreTheSameTypes;
var
  col: tyControls.Columns.TTyColumn;
  hdr: tyControls.Columns.TTyHeader;
begin
  // Aliases, not distinct types: a new-name instance IS an old-name instance.
  hdr := tyControls.Columns.TTyHeader.Create;
  try
    col := hdr.Columns.Add as tyControls.Columns.TTyColumn;
    AssertTrue('new name is old name',
      col is tyControls.TreeView.Columns.TTyTreeColumn);
    AssertTrue('header likewise',
      hdr is tyControls.TreeView.Columns.TTyTreeHeader);
  finally
    hdr.Free;
  end;
end;

procedure TColumnsCompatTest.TestClassAliasRegisteredForOldLfm;
begin
  // A .lfm written before the rename names the classes; RegisterClassAlias resolves them.
  AssertTrue('TTyTreeColumn resolves', GetClass('TTyTreeColumn') <> nil);
  AssertTrue('TTyTreeColumns resolves', GetClass('TTyTreeColumns') <> nil);
  AssertTrue('TTyTreeHeader resolves', GetClass('TTyTreeHeader') <> nil);
  AssertTrue('and they are the renamed classes',
    GetClass('TTyTreeColumn') = tyControls.Columns.TTyColumn);
end;

initialization
  RegisterTest(TColumnsCompatTest);
end.
