unit test.db.grid;
{$mode objfpc}{$H+}

{ The data-aware grid, part one (issue #34 phase 2, plan Task 2): TTyDBGrid's columns and its
  record window.

  * the window: the first screen holds the first records, as their fields' DisplayText; the
    grid's current row follows the dataset (Next, Prior, First, Last) and the window scrolls
    when the record leaves it; a resize changes how many records the buffer holds; reading a
    cell -- or painting -- never moves the dataset;
  * the columns: automatic ones from the fields (title, width from DisplayWidth, alignment,
    visibility, read-only), dropped when the dataset closes and when a design column comes;
    design columns show only their fields with the field's defaults until those are set;
    DisplayFormat reaches the field only when the column's own was set;
  * the cells: NULL is empty whatever the cell store holds, a boolean field is a check box
    (checked, unchecked, grayed), a memo shows '(MEMO)' or its text, a blob '(blob)';
  * Options mapped onto the string grid, its client-side sorting kept out, undo off;
  * the form file: design columns survive it, automatic ones and field defaults are not
    written, a fresh grid writes none of its own properties;
  * C7 / C8: the data source going away, CM_GETDATALINK; the type key.

  The window tests run on the fixture's forty numbered rows (dbfixtures, TDbRowsFixture), the
  cell tests on People, whose third row is all NULL. The expected texts are read off the
  dataset itself before the grid is bound, so they do not come through the grid. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, StdCtrls, LMessages, DB, DBCtrls,
  DBGrids, fpcunit, testregistry,
  dbfixtures, tyControls.Columns, tyControls.Grid, tyControls.StyleModel,
  tyControls.DB.Grid;

type
  TProbeDBGrid = class(TTyDBGrid)
  public
    function Cell(ACol, ARow: Integer): string;
    function EditKind(ACol, ARow: Integer): TTyGridEditorKind;
    function HeaderShown: Boolean;
    function IndicatorShown: Boolean;
    function GridOptions: TTyGridOptions;
    function HeaderOptions: TTyHeaderOptions;
    function ViewportBottom: Integer;
    function TypeKey: string;
    procedure RenderOnce;
  end;

  TDBGridTest = class(TTestCase)
  private
    FForm: TForm;
    FRows: TDbRowsFixture;
    FPeople: TDbFixture;
    FGrid: TProbeDBGrid;
    FNames, FAmounts: TStringList;
    procedure Bind(ASource: TDataSource);
    function ColOf(const AFieldName: string): Integer;
    function RowH: Integer;
    procedure AssertWindowFits(const AWhen: string);
    procedure AssertWindowStartsAt(const AWhen: string; ARecord: Integer);
    procedure CalcTotal(Sender: TObject; ACol: Integer; var AValue: Double;
      var AHandled: Boolean);
    function StreamText(AComponent: TComponent): string;
    function ColumnsBlock(const AText: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the record window }
    procedure TestFirstScreenIsTheFirstRecords;
    procedure TestReadingCellsLeavesTheCurrentRecord;
    procedure TestNextAndPriorMoveTheRow;
    procedure TestLeavingTheWindowScrollsIt;
    procedure TestLastAndFirst;
    procedure TestResizeChangesTheBuffer;
    procedure TestClosingEmptiesTheGridAndDropsTheAutoColumns;
    { the columns }
    procedure TestAutoColumnsFollowTheFields;
    procedure TestDesignColumnsShowOnlyTheirFields;
    procedure TestASetTitleWidthAndAlignmentAreKept;
    procedure TestAddingADesignColumnDropsTheAutoColumns;
    procedure TestDisplayFormatReachesTheFieldOnlyWhenSet;
    { the cells }
    procedure TestNullIsEmptyWhateverTheStoreHolds;
    procedure TestBooleanIsACheckBox;
    procedure TestMemoAndBlob;
    { options, sorting }
    procedure TestOptionsMapOntoTheGrid;
    procedure TestRowSelectDropsEditing;
    procedure TestSortingStaysWithTheDataSet;
    procedure TestTheFooterDoesNotTotalTheWindow;
    { the form file }
    procedure TestAFreshGridWritesNoDefaults;
    procedure TestAutoColumnsAndFieldDefaultsAreNotWritten;
    procedure TestDesignColumnsSurviveAFormFile;
    { C7, C8, the type key }
    procedure TestFreedDataSourceUnbinds;
    procedure TestDataSourceRemovedFromItsOwnerUnbinds;
    procedure TestGetDataLinkAnswersTheLink;
    procedure TestTypeKeyHangsOnTheGrid;
  end;

implementation

uses
  test.db.edits;

{ ===================================================================== TProbeDBGrid ===== }

function TProbeDBGrid.Cell(ACol, ARow: Integer): string;
begin
  Result := GetCellText(ACol, ARow);
end;

function TProbeDBGrid.EditKind(ACol, ARow: Integer): TTyGridEditorKind;
begin
  Result := EditorKindFor(ACol, ARow);
end;

function TProbeDBGrid.HeaderShown: Boolean;
begin
  Result := hoVisible in Header.Options;
end;

function TProbeDBGrid.IndicatorShown: Boolean;
begin
  Result := ShowIndicator;
end;

function TProbeDBGrid.GridOptions: TTyGridOptions;
begin
  Result := TTyCustomDrawGrid(Self).Options;
end;

function TProbeDBGrid.HeaderOptions: TTyHeaderOptions;
begin
  Result := Header.Options;
end;

function TProbeDBGrid.ViewportBottom: Integer;
begin
  Result := ViewportH;
end;

function TProbeDBGrid.TypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TProbeDBGrid.RenderOnce;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(Width, Height);
    RenderTo(bmp.Canvas, Rect(0, 0, Width, Height), 96);
  finally
    bmp.Free;
  end;
end;

{ ====================================================================== TDBGridTest ===== }

procedure TDBGridTest.SetUp;
var
  ds: TDataSet;
begin
  NeedDBWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 500);
  FRows := NewRowsFixture(nil);
  FPeople := NewDbFixture(nil);
  { What each record shows, read off the dataset before any grid sees it. }
  FNames := TStringList.Create;
  FAmounts := TStringList.Create;
  ds := FRows.DS;
  ds.First;
  while not ds.EOF do
  begin
    FNames.Add(ds.FieldByName('Name').DisplayText);
    FAmounts.Add(ds.FieldByName('Amount').DisplayText);
    ds.Next;
  end;
  ds.First;
  FGrid := TProbeDBGrid.Create(FForm);
  FGrid.Font.PixelsPerInch := 96;
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 520, 260);
end;

procedure TDBGridTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FRows);
  FreeAndNil(FPeople);
  FreeAndNil(FNames);
  FreeAndNil(FAmounts);
  FGrid := nil;
end;

procedure TDBGridTest.Bind(ASource: TDataSource);
begin
  FGrid.DataSource := ASource;
end;

function TDBGridTest.ColOf(const AFieldName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FGrid.Columns.Count - 1 do
    if SameText(FGrid.Columns[i].FieldName, AFieldName) then Exit(i);
  Fail('no column for ' + AFieldName);
  Result := -1;
end;

function TDBGridTest.RowH: Integer;
var
  r: TRect;
begin
  r := FGrid.CellRect(0, 0);
  Result := r.Bottom - r.Top;
  AssertTrue('a row has a height', Result > 0);
end;

{ The buffer holds every whole row the body has room for, and no more: the last row ends
  inside the viewport, and another one would not. Measured on the painted geometry
  (CellRect), not on the grid's own arithmetic. }
procedure TDBGridTest.AssertWindowFits(const AWhen: string);
var
  r: TRect;
begin
  AssertTrue(AWhen + ': some rows', FGrid.RowCount > 1);
  AssertTrue(AWhen + ': fewer rows than records', FGrid.RowCount < CFixRowCount);
  AssertEquals(AWhen + ': the buffer is the rows', FGrid.RowCount, FGrid.DataLink.BufferCount);
  r := FGrid.CellRect(0, FGrid.RowCount - 1);
  AssertTrue(AWhen + ': the last row is whole', r.Bottom <= FGrid.ViewportBottom);
  AssertTrue(AWhen + ': one more row would not be', r.Bottom + RowH > FGrid.ViewportBottom);
end;

{ Row 0 of the grid shows record ARecord (1-based), and every row after it the next. }
procedure TDBGridTest.AssertWindowStartsAt(const AWhen: string; ARecord: Integer);
var
  r, nameCol, amountCol: Integer;
begin
  nameCol := ColOf('Name');
  amountCol := ColOf('Amount');
  for r := 0 to FGrid.RowCount - 1 do
  begin
    AssertEquals(Format('%s: row %d Name', [AWhen, r]), FNames[ARecord - 1 + r],
      FGrid.Cell(nameCol, r));
    AssertEquals(Format('%s: row %d Amount', [AWhen, r]), FAmounts[ARecord - 1 + r],
      FGrid.Cell(amountCol, r));
  end;
end;

function TDBGridTest.StreamText(AComponent: TComponent): string;
var
  bin, txt: TMemoryStream;
begin
  bin := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    bin.WriteComponent(AComponent);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    SetString(Result, PChar(txt.Memory), txt.Size);
  finally
    txt.Free;
    bin.Free;
  end;
end;

{ The 'Columns = < ... >' part of a form file text ('' when there is none). }
function TDBGridTest.ColumnsBlock(const AText: string): string;
var
  p, q: Integer;
begin
  Result := '';
  p := Pos('Columns = <', AText);
  if p = 0 then Exit;
  q := Pos('>', Copy(AText, p, MaxInt));
  Result := Copy(AText, p, q);
end;

{ ------------------------------------------------------------- the record window ------ }

procedure TDBGridTest.TestFirstScreenIsTheFirstRecords;
begin
  Bind(FRows.Src);
  AssertWindowFits('bound');
  AssertWindowStartsAt('bound', 1);
  AssertEquals('on the first row', 0, FGrid.Row);
end;

procedure TDBGridTest.TestReadingCellsLeavesTheCurrentRecord;
var
  r, c, active: Integer;
begin
  Bind(FRows.Src);
  FRows.DS.MoveBy(3);
  active := FGrid.DataLink.ActiveRecord;
  for r := 0 to FGrid.RowCount - 1 do
    for c := 0 to FGrid.Columns.Count - 1 do
      FGrid.Cell(c, r);
  FGrid.RenderOnce;
  AssertEquals('the dataset is where it was', 4, FRows.DS.FieldByName('ID').AsInteger);
  AssertEquals('so is the link''s record', active, FGrid.DataLink.ActiveRecord);
  AssertEquals('the cursor too', 3, FGrid.Row);
end;

procedure TDBGridTest.TestNextAndPriorMoveTheRow;
begin
  Bind(FRows.Src);
  FRows.DS.Next;
  AssertEquals('Next', 1, FGrid.Row);
  FRows.DS.Next;
  FRows.DS.Next;
  AssertEquals('Next twice more', 3, FGrid.Row);
  FRows.DS.Prior;
  AssertEquals('Prior', 2, FGrid.Row);
  AssertWindowStartsAt('inside the window', 1);
end;

procedure TDBGridTest.TestLeavingTheWindowScrollsIt;
var
  n: Integer;
begin
  Bind(FRows.Src);
  n := FGrid.RowCount;
  FRows.DS.MoveBy(n);   // record n + 1, one past the window
  AssertEquals('on the last row', n - 1, FGrid.Row);
  AssertWindowStartsAt('scrolled by one', 2);
  AssertEquals('the current row shows the current record',
    FRows.DS.FieldByName('Name').DisplayText, FGrid.Cell(ColOf('Name'), FGrid.Row));
end;

procedure TDBGridTest.TestLastAndFirst;
var
  n: Integer;
begin
  Bind(FRows.Src);
  n := FGrid.RowCount;
  FRows.DS.Last;
  AssertEquals('Last: on the last row', n - 1, FGrid.Row);
  AssertWindowStartsAt('Last', CFixRowCount - n + 1);
  FRows.DS.First;
  AssertEquals('First: on the first row', 0, FGrid.Row);
  AssertWindowStartsAt('First', 1);
end;

procedure TDBGridTest.TestResizeChangesTheBuffer;
var
  n, h: Integer;
begin
  Bind(FRows.Src);
  n := FGrid.RowCount;
  h := RowH;
  FGrid.Height := FGrid.Height + 3 * h;
  AssertEquals('three rows taller, three records more', n + 3, FGrid.RowCount);
  AssertWindowFits('taller');
  AssertWindowStartsAt('taller', 1);
  FGrid.Height := FGrid.Height - 5 * h;
  AssertEquals('five rows shorter, five records fewer', n - 2, FGrid.RowCount);
  AssertWindowFits('shorter');
  AssertWindowStartsAt('shorter', 1);
end;

{ The in-memory table forgets its rows when it closes, so the window is checked again on rows
  appended after the reopen. }
procedure TDBGridTest.TestClosingEmptiesTheGridAndDropsTheAutoColumns;
var
  r: Integer;
begin
  Bind(FRows.Src);
  AssertEquals('a column per field', FRows.DS.FieldCount, FGrid.Columns.Count);
  AssertTrue('automatic', FGrid.Columns[0].IsAutomatic);
  FRows.DS.Close;
  AssertEquals('closed: no rows', 0, FGrid.RowCount);
  AssertEquals('closed: no automatic columns', 0, FGrid.Columns.Count);
  FRows.DS.Open;
  AssertEquals('open again: the columns', FRows.DS.FieldCount, FGrid.Columns.Count);
  AssertEquals('open again: no records, no rows', 0, FGrid.RowCount);
  for r := 1 to 3 do
    FRows.DS.AppendRecord([r, FixRowName(r), FixRowAmount(r), Odd(r), '']);
  AssertEquals('three records appended', 3, FGrid.RowCount);
  for r := 0 to 2 do
    AssertEquals('row ' + IntToStr(r), FNames[r], FGrid.Cell(ColOf('Name'), r));
  AssertEquals('on the last one appended', 2, FGrid.Row);
end;

{ ------------------------------------------------------------------- the columns ------ }

procedure TDBGridTest.TestAutoColumnsFollowTheFields;
var
  ds: TDataSet;
  idW, nameW: Integer;
begin
  ds := FRows.DS;
  ds.FieldByName('Amount').DisplayLabel := 'Total';
  ds.FieldByName('Name').DisplayWidth := 30;
  ds.FieldByName('ID').DisplayWidth := 3;
  ds.FieldByName('Note').Visible := False;
  ds.FieldByName('ID').ReadOnly := True;
  Bind(FRows.Src);
  AssertEquals('field order', 'ID', FGrid.Columns[0].FieldName);
  AssertEquals('title: DisplayLabel', 'Total', FGrid.Columns[ColOf('Amount')].Text);
  AssertEquals('title: FieldName', 'Name', FGrid.Columns[ColOf('Name')].Text);
  AssertTrue('a number to the right',
    FGrid.Columns[ColOf('Amount')].Alignment = taRightJustify);
  AssertTrue('a string to the left', FGrid.Columns[ColOf('Name')].Alignment = taLeftJustify);
  AssertTrue('a check box centred', FGrid.Columns[ColOf('Flag')].Alignment = taCenter);
  AssertFalse('a hidden field''s column is hidden', FGrid.Columns[ColOf('Note')].Visible);
  AssertTrue('a visible one is not', FGrid.Columns[ColOf('Name')].Visible);
  AssertTrue('a read-only field''s column is read-only', FGrid.Columns[0].ReadOnly);
  AssertFalse('another is not', FGrid.Columns[ColOf('Name')].ReadOnly);
  { The width is the DisplayWidth's: thirty characters against three. }
  nameW := FGrid.Columns[ColOf('Name')].Width;
  idW := FGrid.Columns[0].Width;
  AssertEquals('Name: the default field width',
    FGrid.DefaultFieldWidth(ds.FieldByName('Name'), 'Name'), nameW);
  AssertTrue(Format('thirty characters are wider than three (%d vs %d)', [nameW, idW]),
    nameW > 3 * idW);
end;

procedure TDBGridTest.TestDesignColumnsShowOnlyTheirFields;
var
  c: TTyDBGridColumn;
  r: Integer;
  amount: TField;
begin
  amount := FRows.DS.FieldByName('Amount');
  amount.DisplayLabel := 'Total';
  c := FGrid.Columns.Add;
  c.FieldName := 'Amount';
  c := FGrid.Columns.Add;
  c.FieldName := 'Name';
  Bind(FRows.Src);
  AssertEquals('only the two', 2, FGrid.Columns.Count);
  AssertFalse('design columns', FGrid.Columns[0].IsAutomatic or FGrid.Columns[1].IsAutomatic);
  AssertSame('the field', amount, FGrid.Columns[0].Field);
  for r := 0 to FGrid.RowCount - 1 do
  begin
    AssertEquals('Amount first', FAmounts[r], FGrid.Cell(0, r));
    AssertEquals('Name second', FNames[r], FGrid.Cell(1, r));
  end;
  AssertEquals('the field''s title', 'Total', FGrid.Columns[0].Text);
  AssertEquals('the field''s width', FGrid.DefaultFieldWidth(amount, 'Total'),
    FGrid.Columns[0].Width);
  AssertTrue('the field''s alignment', FGrid.Columns[0].Alignment = taRightJustify);
end;

procedure TDBGridTest.TestASetTitleWidthAndAlignmentAreKept;
var
  c: TTyDBGridColumn;
begin
  c := FGrid.Columns.Add;
  c.Text := 'Mine';
  c.Width := 100;          // the width a column is born with: set is set
  c.Alignment := taCenter;
  c.FieldName := 'Amount';
  Bind(FRows.Src);
  AssertEquals('title', 'Mine', c.Text);
  AssertEquals('width', 100, c.Width);
  AssertTrue('alignment', c.Alignment = taCenter);
  FRows.DS.Close;
  FRows.DS.Open;
  AssertEquals('title after a reopen', 'Mine', c.Text);
  AssertEquals('width after a reopen', 100, c.Width);
end;

procedure TDBGridTest.TestAddingADesignColumnDropsTheAutoColumns;
var
  c: TTyDBGridColumn;
begin
  Bind(FRows.Src);
  AssertEquals('automatic columns', FRows.DS.FieldCount, FGrid.Columns.Count);
  c := FGrid.Columns.Add;
  c.FieldName := 'Name';
  AssertEquals('the design column alone', 1, FGrid.Columns.Count);
  AssertEquals('showing its field', FNames[0], FGrid.Cell(0, 0));
  FGrid.Columns.Delete(0);
  AssertEquals('the last design column gone: automatic ones again',
    FRows.DS.FieldCount, FGrid.Columns.Count);
end;

procedure TDBGridTest.TestDisplayFormatReachesTheFieldOnlyWhenSet;
var
  amount: TNumericField;
  plain, formatted: TTyDBGridColumn;
begin
  amount := FRows.DS.FieldByName('Amount') as TNumericField;
  amount.DisplayFormat := '0.0';
  plain := FGrid.Columns.Add;
  plain.FieldName := 'Amount';
  Bind(FRows.Src);
  AssertEquals('a column without one leaves the field''s', '0.0', amount.DisplayFormat);
  AssertEquals('and reads it', '0.0', plain.DisplayFormat);
  AssertEquals('the cell in the field''s format', FormatFloat('0.0', FixRowAmount(1)),
    FGrid.Cell(0, 0));
  formatted := FGrid.Columns.Add;
  formatted.DisplayFormat := '0.000';
  formatted.FieldName := 'Amount';
  AssertEquals('a column with one pushes it', '0.000', amount.DisplayFormat);
  AssertEquals('the cell in it', FormatFloat('0.000', FixRowAmount(1)), FGrid.Cell(1, 0));
end;

{ --------------------------------------------------------------------- the cells ------ }

procedure TDBGridTest.TestNullIsEmptyWhateverTheStoreHolds;
var
  nameCol: Integer;
begin
  Bind(FPeople.Src);
  nameCol := ColOf('Name');
  AssertEquals('three records', 3, FGrid.RowCount);
  AssertEquals('row 1', CFixNames[1], FGrid.Cell(nameCol, 0));
  FGrid.Cells[nameCol, 2] := 'junk';
  AssertEquals('NULL is empty', '', FGrid.Cell(nameCol, 2));
end;

procedure TDBGridTest.TestBooleanIsACheckBox;
var
  col: Integer;
begin
  Bind(FPeople.Src);
  col := ColOf('Active');
  AssertTrue('a check box', FGrid.EditKind(col, 0) = gekCheckBox);
  AssertTrue('True: checked', FGrid.CellCheckState(col, 0) = cbChecked);
  AssertTrue('False: unchecked', FGrid.CellCheckState(col, 1) = cbUnchecked);
  AssertTrue('NULL: grayed', FGrid.CellCheckState(col, 2) = cbGrayed);
  FGrid.OptionsExtra := [dgeAutoColumns];
  col := ColOf('Active');
  AssertTrue('no check box column: text', FGrid.EditKind(col, 0) <> gekCheckBox);
  FPeople.DS.First;
  AssertEquals('the field''s text', FPeople.DS.FieldByName('Active').DisplayText,
    FGrid.Cell(col, 0));
end;

procedure TDBGridTest.TestMemoAndBlob;
var
  noteCol: Integer;
  memoText: string;
begin
  FPeople.DS.First;
  memoText := FPeople.DS.FieldByName('Note').DisplayText;
  AssertTrue('the field says what it is, not what it holds', memoText <> CFixNotes[1]);
  Bind(FPeople.Src);
  noteCol := ColOf('Note');
  AssertEquals('a memo: its DisplayText', memoText, FGrid.Cell(noteCol, 0));
  AssertEquals('a blob', '(blob)', FGrid.Cell(ColOf('Pic'), 0));
  FGrid.Options := FGrid.Options + [dgDisplayMemoText];
  AssertEquals('dgDisplayMemoText: the text', CFixNotes[1], FGrid.Cell(noteCol, 0));
  AssertEquals('row 2', CFixNotes[2], FGrid.Cell(noteCol, 1));
end;

{ ------------------------------------------------------------ options, sorting ------- }

procedure TDBGridTest.TestOptionsMapOntoTheGrid;
begin
  AssertTrue('LCL''s defaults', FGrid.Options = TyDBGridDefaultOptions);
  AssertTrue('LCL''s extra defaults', FGrid.OptionsExtra = [dgeAutoColumns, dgeCheckboxColumn]);
  AssertTrue('titles: the header', FGrid.HeaderShown);
  AssertTrue('the indicator', FGrid.IndicatorShown);
  AssertTrue('row and column lines', FGrid.GridLineStyle = glsBoth);
  AssertTrue('Tab', goTabs in FGrid.GridOptions);
  AssertTrue('column sizing', goColSizing in FGrid.GridOptions);
  AssertTrue('column moving', goColMoving in FGrid.GridOptions);
  AssertFalse('no cell ranges', goRangeSelect in FGrid.GridOptions);
  AssertFalse('no row sizing', goRowSizing in FGrid.GridOptions);
  AssertFalse('no row moving', goRowMoving in FGrid.GridOptions);
  AssertFalse('the selection stays when unfocused', FGrid.HideSelectionWhenInactive);
  FGrid.Options := FGrid.Options - [dgTitles, dgIndicator, dgRowLines, dgTabs, dgColumnResize,
    dgAlwaysShowSelection] + [dgCellHints, dgRowHighlight];
  AssertFalse('no titles: no header', FGrid.HeaderShown);
  AssertFalse('no indicator', FGrid.IndicatorShown);
  AssertTrue('column lines only', FGrid.GridLineStyle = glsVertical);
  AssertFalse('no Tab', goTabs in FGrid.GridOptions);
  AssertFalse('no column sizing', goColSizing in FGrid.GridOptions);
  AssertTrue('cell hints', goCellHints in FGrid.GridOptions);
  AssertTrue('row highlight', goRowHighlight in FGrid.GridOptions);
  AssertTrue('the selection fades when unfocused', FGrid.HideSelectionWhenInactive);
end;

procedure TDBGridTest.TestRowSelectDropsEditing;
begin
  FGrid.Options := FGrid.Options + [dgRowSelect, dgRowHighlight];
  AssertTrue('whole rows', FGrid.SelectionMode = gsmRow);
  AssertFalse('no editing', dgEditing in FGrid.Options);
  AssertFalse('no row highlight of its own', dgRowHighlight in FGrid.Options);
end;

procedure TDBGridTest.TestSortingStaysWithTheDataSet;
var
  r: Integer;
  rect: TRect;
begin
  Bind(FRows.Src);
  AssertEquals('no undo', 0, FGrid.UndoLimit);
  AssertFalse('a header click does not sort', hoHeaderClickAutoSort in FGrid.HeaderOptions);
  FGrid.SortByColumn(ColOf('Name'), sdDescending);
  AssertWindowStartsAt('after a sort in the grid', 1);
  { The string grid's filter reads the cell text it is given -- and would drop every row but
    one from the display. Here each row keeps its place on screen. }
  FGrid.SetColumnFilterEx(ColOf('Name'), gfoEquals, FNames[2]);
  AssertEquals('every row displayed', FGrid.RowCount, FGrid.DisplayRowCount);
  for r := 0 to FGrid.RowCount - 1 do
  begin
    rect := FGrid.CellRect(ColOf('Name'), r);
    AssertFalse('row ' + IntToStr(r) + ' is on screen', IsRectEmpty(rect));
    AssertEquals('row ' + IntToStr(r) + ' in buffer order', r * RowH,
      rect.Top - FGrid.CellRect(ColOf('Name'), 0).Top);
  end;
end;

procedure TDBGridTest.CalcTotal(Sender: TObject; ACol: Integer; var AValue: Double;
  var AHandled: Boolean);
begin
  AValue := 42;
  AHandled := True;
end;

procedure TDBGridTest.TestTheFooterDoesNotTotalTheWindow;
var
  col: Integer;
begin
  Bind(FRows.Src);
  col := ColOf('Amount');
  FGrid.Columns[col].Aggregate := gagSum;
  FGrid.ShowFooter := True;
  AssertEquals('the rows on screen are not summed', 0, FGrid.AggregateValue(col), 0);
  FGrid.OnColumnCalc := @CalcTotal;
  AssertEquals('the application''s total', 42, FGrid.AggregateValue(col), 0);
end;

{ ---------------------------------------------------------------- the form file ------ }

procedure TDBGridTest.TestAFreshGridWritesNoDefaults;
var
  g: TTyDBGrid;
  s: string;
begin
  g := TTyDBGrid.Create(nil);
  try
    s := StreamText(g);
    AssertEquals('Options', 0, Pos('Options', s));
    AssertEquals('Columns', 0, Pos('Columns', s));
    AssertEquals('ReadOnly', 0, Pos('ReadOnly', s));
  finally
    g.Free;
  end;
end;

procedure TDBGridTest.TestAutoColumnsAndFieldDefaultsAreNotWritten;
var
  c: TTyDBGridColumn;
  block: string;
begin
  FRows.DS.FieldByName('Amount').DisplayLabel := 'Total';
  Bind(FRows.Src);
  AssertTrue('automatic columns', FGrid.Columns.Count > 0);
  AssertEquals('automatic columns are not written', '', ColumnsBlock(StreamText(FGrid)));
  c := FGrid.Columns.Add;
  c.FieldName := 'Amount';
  block := ColumnsBlock(StreamText(FGrid));
  AssertTrue('a design column is: ' + block, Pos('FieldName = ''Amount''', block) > 0);
  AssertEquals('the field''s title is not: ' + block, 0, Pos('Text = ', block));
  AssertEquals('the field''s width is not: ' + block, 0, Pos('Width = ', block));
  AssertEquals('the field''s alignment is not: ' + block, 0, Pos('Alignment = ', block));
  AssertEquals('nor a DisplayFormat never set: ' + block, 0, Pos('DisplayFormat', block));
end;

procedure TDBGridTest.TestDesignColumnsSurviveAFormFile;
var
  dm, dm2: TDataModule;
  src: TDataSource;
  g, g2: TTyDBGrid;
  c: TTyDBGridColumn;
  ms: TMemoryStream;
begin
  dm := TDataModule.CreateNew(nil);
  dm2 := TDataModule.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    dm.Name := 'Root';
    src := TDataSource.Create(dm);
    src.Name := 'Src';
    g := TTyDBGrid.Create(dm);
    g.Name := 'Grid';
    g.DataSource := src;
    c := g.Columns.Add;
    c.FieldName := 'Amount';
    c.DisplayFormat := '0.00';
    c.Text := 'Total';
    c.Width := 77;
    c := g.Columns.Add;
    c.FieldName := 'Name';
    g.Options := g.Options + [dgDisplayMemoText] - [dgIndicator];
    g.OptionsExtra := [dgeAutoColumns];
    ms.WriteComponent(dm);
    ms.Position := 0;
    ms.ReadComponent(dm2);
    g2 := dm2.FindComponent('Grid') as TTyDBGrid;
    AssertNotNull('read back', g2);
    AssertSame('DataSource', dm2.FindComponent('Src'), g2.DataSource);
    AssertEquals('two columns', 2, g2.Columns.Count);
    AssertEquals('FieldName', 'Amount', g2.Columns[0].FieldName);
    AssertEquals('DisplayFormat', '0.00', g2.Columns[0].DisplayFormat);
    AssertEquals('Text', 'Total', g2.Columns[0].Text);
    AssertEquals('Width', 77, g2.Columns[0].Width);
    AssertEquals('second FieldName', 'Name', g2.Columns[1].FieldName);
    AssertEquals('second DisplayFormat', '', g2.Columns[1].DisplayFormat);
    AssertEquals('second title: the field name while there is no field', 'Name',
      g2.Columns[1].Text);
    AssertFalse('design columns', g2.Columns[1].IsAutomatic);
    AssertTrue('Options', g2.Options = g.Options);
    AssertTrue('OptionsExtra', g2.OptionsExtra = [dgeAutoColumns]);
  finally
    ms.Free;
    dm2.Free;
    dm.Free;
  end;
end;

{ ---------------------------------------------------------- C7, C8, the type key ----- }

procedure TDBGridTest.TestFreedDataSourceUnbinds;
begin
  Bind(FRows.Src);
  AssertTrue('rows', FGrid.RowCount > 0);
  FRows.Src.Free;
  AssertNull('DataSource', FGrid.DataSource);
  AssertEquals('no rows', 0, FGrid.RowCount);
  AssertEquals('no automatic columns', 0, FGrid.Columns.Count);
  FGrid.RenderOnce;
end;

procedure TDBGridTest.TestDataSourceRemovedFromItsOwnerUnbinds;
var
  src: TDataSource;
begin
  src := TDataSource.Create(FForm);
  try
    src.DataSet := FRows.DS;
    Bind(src);
    AssertTrue('bound', FGrid.RowCount > 0);
    FForm.RemoveComponent(src);
    AssertNull('DataSource after opRemove', FGrid.DataSource);
    AssertEquals('unbound', 0, FGrid.RowCount);
  finally
    src.Free;
  end;
end;

procedure TDBGridTest.TestGetDataLinkAnswersTheLink;
var
  link: TObject;
begin
  Bind(FRows.Src);
  link := TObject(PtrUInt(FGrid.Perform(CM_GETDATALINK, 0, 0)));
  AssertNotNull('a link', link);
  AssertTrue('a data link', link is TDataLink);
  AssertSame('on the grid''s data source', FRows.Src, TDataLink(link).DataSource);
end;

procedure TDBGridTest.TestTypeKeyHangsOnTheGrid;
var
  chain: TStringArray;
begin
  AssertEquals('its own key', 'TyDBGrid', FGrid.TypeKey);
  chain := TyTypeKeyChain('TyDBGrid');
  AssertEquals('two keys', 2, Length(chain));
  AssertEquals('then the grid''s', 'TyGrid', chain[1]);
end;

initialization
  RegisterClass(TDataSource);
  RegisterTest(TDBGridTest);
end.
