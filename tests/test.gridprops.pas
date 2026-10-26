unit test.gridprops;
{ #127: grid properties that did nothing or only half -- Header.AutoSizeIndex counts frozen
  columns once and leaves room for the vertical bar; IndicatorWidth updates the scroll bars;
  a header group's Level / Alignment and GroupRowFormat repaint; a column added in code or by
  CSV takes DefaultColWidth, as LCL's do, while a form file's columns stay as they were saved;
  Header.SortColumn / SortDirection sort the rows, a form file's included; MinColWidth /
  MaxColWidth bound the automatic widths too; and SortKind = gskAuto on the grid looks at each
  column's contents. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Forms, fpcunit, testregistry,
  tyControls.Columns, tyControls.Grid;

type
  TGridProbe = class(TTyStringGrid)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
    function ViewW: Integer;
    function ViewH: Integer;
  end;

  TGridPropsTest = class(TTestCase)
  private
    FAsked: Integer;
    procedure CanSort(Sender: TObject; ACol: Integer; var AAllow: Boolean);
    function NewGrid(AColWidths: array of Integer): TGridProbe;
    function TextAtRow(G: TTyStringGrid; ACol, APos: Integer): string;
  published
    procedure TestAutoSizeIndexCountsAFrozenColumnOnce;
    procedure TestAutoSizeIndexLeavesRoomForTheVerticalBar;
    procedure TestIndicatorWidthUpdatesTheScrollBars;
    procedure TestHeaderGroupLevelAndAlignmentRepaint;
    procedure TestGroupRowFormatRepaints;
    procedure TestANewColumnTakesDefaultColWidth;
    procedure TestACsvColumnTakesDefaultColWidth;
    procedure TestAFormFilesColumnsKeepTheirWidth;
    procedure TestAFormFilesColumnsKeepTheirWidthWhateverTheOrder;
    procedure TestHeaderSortColumnSortsTheRows;
    procedure TestAFormFilesSortSortsTheRows;
    procedure TestASortAsksOnce;
    procedure TestMaxColWidthBoundsTheAutoFit;
    procedure TestMaxColWidthBoundsAutoSizeIndex;
    procedure TestAutoSortKindReadsTheColumn;
  end;

implementation

procedure TGridProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

function TGridProbe.ViewW: Integer;
begin
  Result := ViewportW;
end;

function TGridProbe.ViewH: Integer;
begin
  Result := ViewportH;
end;

procedure TGridPropsTest.CanSort(Sender: TObject; ACol: Integer; var AAllow: Boolean);
begin
  Inc(FAsked);
end;

function TGridPropsTest.NewGrid(AColWidths: array of Integer): TGridProbe;
var
  i: Integer;
begin
  Result := TGridProbe.Create(nil);
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 300, 200);
  for i := 0 to High(AColWidths) do
    (Result.Header.Columns.Add as TTyColumn).Width := AColWidths[i];
end;

function TGridPropsTest.TextAtRow(G: TTyStringGrid; ACol, APos: Integer): string;
begin
  Result := G.Cells[ACol, G.DisplayToData(APos)];
end;

procedure TGridPropsTest.TestAutoSizeIndexCountsAFrozenColumnOnce;
var
  g: TGridProbe;
begin
  g := NewGrid([50, 40, 80]);
  try
    g.FixedCols := 1;
    g.Header.AutoSizeIndex := 1;
    g.Header.Options := g.Header.Options + [hoAutoResize];
    AssertEquals('the auto column takes what the other two leave', g.ViewW - 130,
      g.ColWidths[1]);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestAutoSizeIndexLeavesRoomForTheVerticalBar;
var
  g: TGridProbe;
begin
  g := NewGrid([50, 40, 80]);
  try
    g.RowCount := 200;   // taller than the grid: the vertical bar shows
    g.Header.AutoSizeIndex := 1;
    g.Header.Options := g.Header.Options + [hoAutoResize];
    AssertTrue('setup: the bar takes room', g.ViewW < g.ClientWidth);
    AssertEquals('the columns end where the bar starts', g.ViewW,
      g.ColWidths[0] + g.ColWidths[1] + g.ColWidths[2]);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestIndicatorWidthUpdatesTheScrollBars;
var
  g: TGridProbe;
begin
  g := NewGrid([90, 90, 90]);
  try
    g.ShowIndicator := True;   // 30 + 270 = 300: it all fits
    AssertEquals('setup: no horizontal bar', g.ClientHeight, g.ViewH);
    g.IndicatorWidth := 60;
    AssertTrue('a wider row-header slot brings the bar', g.ViewH < g.ClientHeight);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestHeaderGroupLevelAndAlignmentRepaint;
var
  g: TGridProbe;
  hg: TTyGridHeaderGroup;
begin
  g := NewGrid([90, 90]);
  try
    hg := g.HeaderGroups.Add;
    hg.LastCol := 1;
    g.Invalidations := 0;
    hg.Alignment := taLeftJustify;
    AssertTrue('Alignment repaints', g.Invalidations > 0);
    g.Invalidations := 0;
    hg.Level := 1;
    AssertTrue('Level repaints', g.Invalidations > 0);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestGroupRowFormatRepaints;
var
  g: TGridProbe;
begin
  g := NewGrid([90]);
  try
    g.Invalidations := 0;
    g.GroupRowFormat := '%s (%d)';
    AssertTrue('the group rows show it', g.Invalidations > 0);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestANewColumnTakesDefaultColWidth;
var
  g: TGridProbe;
begin
  g := NewGrid([]);
  try
    g.DefaultColWidth := 150;
    AssertEquals('as LCL''s columns do', 150, (g.Header.Columns.Add as TTyColumn).Width);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestACsvColumnTakesDefaultColWidth;
var
  g: TGridProbe;
begin
  g := NewGrid([]);
  try
    g.DefaultColWidth := 150;
    g.LoadFromCSVText('a,b' + LineEnding + '1,2');
    AssertEquals('a loaded column too', 150, g.ColWidths[1]);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestAFormFilesColumnsKeepTheirWidth;
var
  src, dst: TForm;
  g: TTyStringGrid;
  ms: TMemoryStream;
begin
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    g := TTyStringGrid.Create(src);
    g.Name := 'G';
    g.Parent := src;
    g.DefaultColWidth := 150;
    (g.Header.Columns.Add as TTyColumn).Width := 100;   // TTyColumn's default: not written
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    g := dst.FindComponent('G') as TTyStringGrid;
    AssertEquals('read back as it was saved', 100, g.ColWidths[0]);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TGridPropsTest.TestAFormFilesColumnsKeepTheirWidthWhateverTheOrder;
const
  { DefaultColWidth read BEFORE the column: a column without a Width line was saved at
    TTyColumn's 100, and must come back at 100. }
  LFM =
    'object F: TForm' + LineEnding +
    '  object G: TTyStringGrid' + LineEnding +
    '    DefaultColWidth = 150' + LineEnding +
    '    Header.Columns = <' + LineEnding +
    '      item' + LineEnding +
    '      end>' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
var
  f: TForm;
  ts: TStringStream;
  bs: TMemoryStream;
  g: TTyStringGrid;
begin
  f := TForm.CreateNew(nil);
  ts := TStringStream.Create(LFM);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(f);
    g := f.FindComponent('G') as TTyStringGrid;
    AssertEquals('as it was saved', 100, g.ColWidths[0]);
    AssertEquals('while new ones take the default', 150,
      (g.Header.Columns.Add as TTyColumn).Width);
  finally
    bs.Free;
    ts.Free;
    f.Free;
  end;
end;

procedure TGridPropsTest.TestHeaderSortColumnSortsTheRows;
var
  g: TGridProbe;
begin
  g := NewGrid([90]);
  try
    g.RowCount := 3;
    g.Cells[0, 0] := 'b';
    g.Cells[0, 1] := 'c';
    g.Cells[0, 2] := 'a';
    g.Header.SortColumn := 0;
    AssertEquals('the rows sort, not just the arrow', 'a', TextAtRow(g, 0, 0));
    g.Header.SortDirection := sdDescending;
    AssertEquals('the direction too', 'c', TextAtRow(g, 0, 0));
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestAFormFilesSortSortsTheRows;
const
  LFM =
    'object F: TForm' + LineEnding +
    '  object G: TTyStringGrid' + LineEnding +
    '    Header.Columns = <' + LineEnding +
    '      item' + LineEnding +
    '      end>' + LineEnding +
    '    Header.SortColumn = 0' + LineEnding +
    '    Header.SortDirection = sdDescending' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
var
  f: TForm;
  ts: TStringStream;
  bs: TMemoryStream;
  g: TTyStringGrid;
begin
  f := TForm.CreateNew(nil);
  ts := TStringStream.Create(LFM);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(f);
    g := f.FindComponent('G') as TTyStringGrid;
    AssertTrue('the grid''s own sort is the saved one before any data',
      g.SortDirection = sdDescending);
    { A form file holds no cells: the data comes at run time. }
    g.LoadFromCSVText('b' + LineEnding + 'c' + LineEnding + 'a');
    AssertEquals('the saved sort is in force', 'c', TextAtRow(g, 0, 0));
  finally
    bs.Free;
    ts.Free;
    f.Free;
  end;
end;

procedure TGridPropsTest.TestASortAsksOnce;
var
  g: TGridProbe;
begin
  g := NewGrid([90, 90]);
  try
    g.RowCount := 3;
    g.Cells[1, 0] := 'x';
    g.SortByColumn(0, sdAscending);
    FAsked := 0;
    g.OnCanSort := @CanSort;
    g.SortByColumn(1, sdDescending);
    { The grid showing its own sort in the header is not the host changing it. }
    AssertEquals('one sort, one question', 1, FAsked);
    AssertTrue('in the direction asked for', g.SortDirection = sdDescending);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestMaxColWidthBoundsTheAutoFit;
var
  g: TGridProbe;
begin
  g := NewGrid([90]);
  try
    g.RowCount := 1;
    g.Cells[0, 0] := StringOfChar('W', 80);
    g.MaxColWidth := 60;
    g.AutoFitColumn(0);
    AssertEquals('the fit stops at the limit', 60, g.ColWidths[0]);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestMaxColWidthBoundsAutoSizeIndex;
var
  g: TGridProbe;
begin
  g := NewGrid([50, 40]);
  try
    g.MaxColWidth := 120;
    g.Header.AutoSizeIndex := 1;
    g.Header.Options := g.Header.Options + [hoAutoResize];
    AssertEquals('the auto column stops at the limit', 120, g.ColWidths[1]);
  finally
    g.Free;
  end;
end;

procedure TGridPropsTest.TestAutoSortKindReadsTheColumn;
var
  g: TGridProbe;
begin
  g := NewGrid([90, 90]);
  try
    g.SortKind := gskAuto;
    g.RowCount := 3;
    g.Cells[0, 0] := '10';
    g.Cells[0, 1] := '9';
    g.Cells[0, 2] := '100';
    g.Cells[1, 0] := 'b10';
    g.Cells[1, 1] := 'b9';
    g.Cells[1, 2] := 'b100';
    g.SortByColumn(0, sdAscending);
    AssertEquals('a column of numbers sorts as numbers', '9', TextAtRow(g, 0, 0));
    AssertEquals('', '100', TextAtRow(g, 0, 2));
    g.SortByColumn(1, sdAscending);
    AssertEquals('a column of text as text', 'b10', TextAtRow(g, 1, 0));
  finally
    g.Free;
  end;
end;

initialization
  RegisterTest(TGridPropsTest);
end.
