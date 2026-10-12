unit test.db.grid.nav;
{$mode objfpc}{$H+}

{ The data-aware grid, part two (issue #34 phase 2, plan Task 3): every move the user makes
  moves the dataset, and the grid's row only follows it.

  * the keys: Up / Down, PgUp / PgDn by the window's rows (LCL's VisibleRowCount, no overlap
    row), Ctrl+Home / Ctrl+End to the first / last record, Home / End between the columns;
  * the wheel (a real LM_MOUSEWHEEL), one record per notch;
  * a click on another row, Row := from code, Enter: the dataset moves by the row difference;
  * the vertical bar, driven through its public API (ScrollByKey, Position -- a scroll bar never
    takes the focus): for a sequenced dataset its range is the records, its position RecNo - 1
    and moving it sets RecNo; for one that is not sequenced (TNonSeqDataSet says so) it is
    LCL's three positions and moves by direction; no bar when every record fits.

  The records are read off the dataset itself (its ID), never through the grid. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, LMessages, DB, BufDataset, DBGrids,
  fpcunit, testregistry,
  dbfixtures, tyControls.Grid, tyControls.ScrollBar, tyControls.DB.Grid;

type
  { A table that says it cannot be counted or reached by RecNo (a server cursor would). }
  TNonSeqDataSet = class(TBufDataset)
  public
    function IsSequenced: Boolean; override;
  end;

  { A table that counts the RecNo it is sent to (a big jump of the thumb should be one, not a
    walk of MoveBy). }
  TRecNoSpyDataSet = class(TBufDataset)
  protected
    procedure SetRecNo(Value: Longint); override;
  public
    RecNoSets: Integer;
  end;

  { What the suites reach that is protected: the key and mouse paths. }
  TDBGridProbe = class(TTyDBGrid)
  public
    function PressKey(AKey: Word; AShift: TShiftState = []): Word;
    procedure ClickAt(X, Y: Integer; AShift: TShiftState = []);
    procedure ClickCell(ACol, ARow: Integer);
    function Cell(ACol, ARow: Integer): string;
  end;

  TDBGridNavTest = class(TTestCase)
  private
    FForm: TForm;
    FRows: TDbRowsFixture;
    FPeople: TDbFixture;
    FNonSeq: TNonSeqDataSet;
    FNonSeqSrc: TDataSource;
    FGrid: TDBGridProbe;
    FWheelSeen: Integer;
    procedure TakeWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    function ID: Integer;
    function NonSeqID: Integer;
    function ColOf(const AFieldName: string): Integer;
    procedure AssertRowShowsTheRecord(const AWhen: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the keys }
    procedure TestDownAndUpMoveTheRecord;
    procedure TestDownOutOfTheWindowScrollsIt;
    procedure TestPageKeysMoveByTheWindow;
    procedure TestCtrlHomeAndEndAreFirstAndLast;
    procedure TestHomeAndEndMoveBetweenColumns;
    procedure TestEnterMovesToTheNextRecord;
    { the wheel }
    procedure TestWheelMovesOneRecordPerNotch;
    procedure TestWheelHandlerCanTakeTheWheel;
    { the mouse and code }
    procedure TestClickOnAnotherRowMovesByTheDifference;
    procedure TestClickOnTheSameRowMovesOnlyTheColumn;
    procedure TestRowFromCodeMovesTheDataSet;
    { the bar }
    procedure TestSequencedBarIsTheRecords;
    procedure TestSequencedBarSetsRecNo;
    procedure TestTheThumbJumpsByRecNo;
    procedure TestNonSequencedBarHasThreePositions;
    procedure TestNonSequencedBarMovesByDirection;
    procedure TestNoBarWhenEveryRecordFits;
  end;

{ The numbered rows (dbfixtures' TDbRowsFixture layout), into ADS, which is created here. }
procedure FillRowsTable(ADS: TBufDataset);
{ A real wheel notch: LM_MOUSEWHEEL through TControl.WMMouseWheel. }
procedure WheelTick(ATarget: TControl; ADelta: Integer);

implementation

uses
  test.db.edits;

function TNonSeqDataSet.IsSequenced: Boolean;
begin
  Result := False;
end;

procedure TRecNoSpyDataSet.SetRecNo(Value: Longint);
begin
  Inc(RecNoSets);
  inherited SetRecNo(Value);
end;

procedure FillRowsTable(ADS: TBufDataset);
var
  r: Integer;
begin
  with ADS.FieldDefs do
  begin
    Add('ID', ftInteger);
    Add('Name', ftString, 20);
    Add('Amount', ftFloat);
    Add('Flag', ftBoolean);
    Add('Note', ftMemo);
  end;
  ADS.CreateDataset;
  for r := 1 to CFixRowCount do
  begin
    ADS.Append;
    ADS.FieldByName('ID').AsInteger := r;
    ADS.FieldByName('Name').AsString := FixRowName(r);
    ADS.FieldByName('Amount').AsFloat := FixRowAmount(r);
    ADS.FieldByName('Flag').AsBoolean := Odd(r);
    ADS.FieldByName('Note').AsString := Format('Note %.2d', [r]);
    ADS.Post;
  end;
  ADS.First;
end;

procedure WheelTick(ATarget: TControl; ADelta: Integer);
var
  msg: TLMMouseEvent;
begin
  FillChar(msg{%H-}, SizeOf(msg), 0);
  msg.Msg := LM_MOUSEWHEEL;
  msg.WheelDelta := ADelta;
  ATarget.Dispatch(msg);
end;

{ ===================================================================== TDBGridProbe ===== }

function TDBGridProbe.PressKey(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  KeyDown(Result, AShift);
end;

procedure TDBGridProbe.ClickAt(X, Y: Integer; AShift: TShiftState);
begin
  MouseDown(mbLeft, AShift, X, Y);
  MouseUp(mbLeft, AShift, X, Y);
end;

procedure TDBGridProbe.ClickCell(ACol, ARow: Integer);
var
  r: TRect;
begin
  r := CellRect(ACol, ARow);
  ClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

function TDBGridProbe.Cell(ACol, ARow: Integer): string;
begin
  Result := GetCellText(ACol, ARow);
end;

{ =================================================================== TDBGridNavTest ===== }

procedure TDBGridNavTest.SetUp;
begin
  NeedDBWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 500);
  FRows := NewRowsFixture(nil);
  FPeople := NewDbFixture(nil);
  FNonSeq := TNonSeqDataSet.Create(nil);
  FillRowsTable(FNonSeq);
  FNonSeqSrc := TDataSource.Create(nil);
  FNonSeqSrc.DataSet := FNonSeq;
  FGrid := TDBGridProbe.Create(FForm);
  FGrid.Font.PixelsPerInch := 96;
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 520, 260);
end;

procedure TDBGridNavTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FNonSeqSrc);
  FreeAndNil(FNonSeq);
  FreeAndNil(FRows);
  FreeAndNil(FPeople);
  FGrid := nil;
end;

function TDBGridNavTest.ID: Integer;
begin
  Result := FRows.DS.FieldByName('ID').AsInteger;
end;

function TDBGridNavTest.NonSeqID: Integer;
begin
  Result := FNonSeq.FieldByName('ID').AsInteger;
end;

function TDBGridNavTest.ColOf(const AFieldName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FGrid.Columns.Count - 1 do
    if SameText(FGrid.Columns[i].FieldName, AFieldName) then Exit(i);
  Fail('no column for ' + AFieldName);
  Result := -1;
end;

{ The cursor row is the dataset's current record (its row shows the record's name). }
procedure TDBGridNavTest.AssertRowShowsTheRecord(const AWhen: string);
begin
  AssertEquals(AWhen + ': the row is the active record', FGrid.DataLink.ActiveRecord, FGrid.Row);
  AssertEquals(AWhen + ': the row shows the current record',
    FGrid.DataLink.DataSet.FieldByName('Name').DisplayText, FGrid.Cell(ColOf('Name'), FGrid.Row));
end;

{ ---------------------------------------------------------------------- the keys ----- }

procedure TDBGridNavTest.TestDownAndUpMoveTheRecord;
begin
  FGrid.DataSource := FRows.Src;
  AssertEquals('Down consumed', 0, FGrid.PressKey(VK_DOWN));
  FGrid.PressKey(VK_DOWN);
  FGrid.PressKey(VK_DOWN);
  AssertEquals('three Downs: the fourth record', 4, ID);
  AssertEquals('on the fourth row', 3, FGrid.Row);
  AssertRowShowsTheRecord('Down');
  FGrid.PressKey(VK_UP);
  AssertEquals('Up: the third record', 3, ID);
  AssertRowShowsTheRecord('Up');
  FGrid.DataLink.DataSet.First;
  FGrid.PressKey(VK_UP);
  AssertEquals('Up on the first record stays', 1, ID);
  AssertEquals('nothing appended or inserted', CFixRowCount, FRows.DS.RecordCount);
end;

procedure TDBGridNavTest.TestDownOutOfTheWindowScrollsIt;
var
  n, i: Integer;
begin
  FGrid.DataSource := FRows.Src;
  n := FGrid.RowCount;
  AssertTrue('a window smaller than the table', n < CFixRowCount);
  for i := 1 to n do FGrid.PressKey(VK_DOWN);
  AssertEquals('n Downs: record n + 1', n + 1, ID);
  AssertEquals('on the last row of the window', n - 1, FGrid.Row);
  AssertRowShowsTheRecord('past the window');
  AssertEquals('the first row is the second record', FixRowName(2), FGrid.Cell(ColOf('Name'), 0));
end;

procedure TDBGridNavTest.TestPageKeysMoveByTheWindow;
var
  page: Integer;
begin
  FGrid.DataSource := FRows.Src;
  page := FGrid.DataLink.BufferCount;
  AssertEquals('a page is the window''s rows', FGrid.RowCount, page);
  AssertEquals('PgDn consumed', 0, FGrid.PressKey(VK_NEXT));
  AssertEquals('PgDn: a whole window down, no overlap row', 1 + page, ID);
  FGrid.PressKey(VK_NEXT);
  AssertEquals('PgDn again', 1 + 2 * page, ID);
  AssertRowShowsTheRecord('PgDn');
  FGrid.PressKey(VK_PRIOR);
  AssertEquals('PgUp: a whole window up', 1 + page, ID);
  AssertRowShowsTheRecord('PgUp');
  FGrid.PressKey(VK_PRIOR);
  FGrid.PressKey(VK_PRIOR);
  AssertEquals('PgUp stops at the first record', 1, ID);
end;

procedure TDBGridNavTest.TestCtrlHomeAndEndAreFirstAndLast;
begin
  FGrid.DataSource := FRows.Src;
  FGrid.PressKey(VK_DOWN);
  AssertEquals('Ctrl+End consumed', 0, FGrid.PressKey(VK_END, [ssCtrl]));
  AssertEquals('Ctrl+End: the last record', CFixRowCount, ID);
  AssertEquals('on the last row', FGrid.RowCount - 1, FGrid.Row);
  AssertRowShowsTheRecord('Ctrl+End');
  FGrid.PressKey(VK_HOME, [ssCtrl]);
  AssertEquals('Ctrl+Home: the first record', 1, ID);
  AssertEquals('on the first row', 0, FGrid.Row);
  AssertEquals('the first window', FixRowName(1), FGrid.Cell(ColOf('Name'), 0));
end;

procedure TDBGridNavTest.TestHomeAndEndMoveBetweenColumns;
begin
  FGrid.DataSource := FRows.Src;
  FGrid.PressKey(VK_DOWN);
  FGrid.Col := 2;
  FGrid.PressKey(VK_HOME);
  AssertEquals('Home: the first column', 0, FGrid.Col);
  AssertEquals('Home: the same record', 2, ID);
  FGrid.PressKey(VK_END);
  AssertEquals('End: the last column', FGrid.Columns.Count - 1, FGrid.Col);
  AssertEquals('End: the same record', 2, ID);
end;

procedure TDBGridNavTest.TestEnterMovesToTheNextRecord;
begin
  FGrid.DataSource := FRows.Src;
  FGrid.PressKey(VK_RETURN);
  AssertEquals('Enter: the next record', 2, ID);
  AssertRowShowsTheRecord('Enter');
end;

{ --------------------------------------------------------------------- the wheel ----- }

procedure TDBGridNavTest.TestWheelMovesOneRecordPerNotch;
begin
  FGrid.DataSource := FRows.Src;
  WheelTick(FGrid, -120);
  AssertEquals('a notch down: the next record', 2, ID);
  AssertRowShowsTheRecord('a notch');
  WheelTick(FGrid, -240);
  AssertEquals('two notches in one message: two records', 4, ID);
  WheelTick(FGrid, 120);
  AssertEquals('a notch up', 3, ID);
  AssertRowShowsTheRecord('a notch up');
end;

procedure TDBGridNavTest.TakeWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  Inc(FWheelSeen);
  Handled := True;
end;

{ LCL's TControl.DoMouseWheel order: the application's OnMouseWheel first; Handled, the grid
  does nothing more. }
procedure TDBGridNavTest.TestWheelHandlerCanTakeTheWheel;
begin
  FGrid.DataSource := FRows.Src;
  FGrid.OnMouseWheel := @TakeWheel;
  WheelTick(FGrid, -120);
  AssertEquals('the handler saw it', 1, FWheelSeen);
  AssertEquals('handled: the record stays', 1, ID);
  FGrid.OnMouseWheel := nil;
  WheelTick(FGrid, -120);
  AssertEquals('no handler: moved', 2, ID);
end;

{ ------------------------------------------------------------- the mouse and code ----- }

procedure TDBGridNavTest.TestClickOnAnotherRowMovesByTheDifference;
var
  moved: Integer;
begin
  FGrid.DataSource := FRows.Src;
  FGrid.PressKey(VK_DOWN);
  FGrid.PressKey(VK_DOWN);   // record 3, row 2
  FGrid.ClickCell(ColOf('Name'), 5);
  moved := ID;
  AssertEquals('the record three rows down', 6, moved);
  AssertEquals('on the clicked row', 5, FGrid.Row);
  AssertRowShowsTheRecord('click');
  FGrid.ClickCell(ColOf('Amount'), 1);
  AssertEquals('a click higher up', 2, ID);
  AssertEquals('and that column', ColOf('Amount'), FGrid.Col);
end;

procedure TDBGridNavTest.TestClickOnTheSameRowMovesOnlyTheColumn;
begin
  FGrid.DataSource := FRows.Src;
  FGrid.PressKey(VK_DOWN);
  FGrid.ClickCell(ColOf('Amount'), 1);
  AssertEquals('the same record', 2, ID);
  AssertEquals('the clicked column', ColOf('Amount'), FGrid.Col);
end;

procedure TDBGridNavTest.TestRowFromCodeMovesTheDataSet;
begin
  FGrid.DataSource := FRows.Src;
  FGrid.Row := 4;
  AssertEquals('Row := 4: the fifth record', 5, ID);
  AssertRowShowsTheRecord('Row :=');
end;

{ ----------------------------------------------------------------------- the bar ----- }

procedure TDBGridNavTest.TestSequencedBarIsTheRecords;
var
  bar: TTyScrollBar;
begin
  FGrid.DataSource := FRows.Src;
  bar := FGrid.VScrollBar;
  AssertTrue('more records than rows: a bar', bar.Visible);
  AssertEquals('from the first record', 0, bar.Min);
  AssertEquals('to the last', CFixRowCount - 1, bar.Max);
  AssertEquals('a page of the window', FGrid.DataLink.BufferCount, bar.PageSize);
  AssertEquals('on the first', 0, bar.Position);
  FRows.DS.MoveBy(5);
  AssertEquals('RecNo - 1', 5, bar.Position);
  FRows.DS.Last;
  AssertEquals('on the last', CFixRowCount - 1, bar.Position);
  FRows.DS.First;
  AssertEquals('back on the first', 0, bar.Position);
end;

procedure TDBGridNavTest.TestSequencedBarSetsRecNo;
var
  bar: TTyScrollBar;
  k: Word;
  page: Integer;
begin
  FGrid.DataSource := FRows.Src;
  bar := FGrid.VScrollBar;
  page := FGrid.DataLink.BufferCount;
  bar.Position := 19;                     // the thumb put there
  AssertEquals('the thumb: RecNo = position + 1', 20, ID);
  AssertRowShowsTheRecord('thumb');
  k := VK_DOWN;
  AssertTrue('a line down', bar.ScrollByKey(k));
  AssertEquals('a line: the next record', 21, ID);
  AssertEquals('the bar says so', 20, bar.Position);
  k := VK_NEXT;
  bar.ScrollByKey(k);
  AssertEquals('a page: a window of records', 21 + page, ID);
  AssertRowShowsTheRecord('page');
  k := VK_UP;
  bar.ScrollByKey(k);
  AssertEquals('a line up', 20 + page, ID);
  k := VK_END;
  bar.ScrollByKey(k);
  AssertEquals('the end: the last record', CFixRowCount, ID);
  k := VK_HOME;
  bar.ScrollByKey(k);
  AssertEquals('the start: the first record', 1, ID);
  AssertRowShowsTheRecord('the start');
end;

{ The same moves as RecNo would make could be walked with MoveBy; a sequenced dataset is told
  where to go (LCL sets RecNo), which is one jump whatever the distance. }
procedure TDBGridNavTest.TestTheThumbJumpsByRecNo;
var
  spy: TRecNoSpyDataSet;
  src: TDataSource;
  k: Word;
begin
  spy := TRecNoSpyDataSet.Create(nil);
  src := TDataSource.Create(nil);
  try
    FillRowsTable(spy);
    src.DataSet := spy;
    FGrid.DataSource := src;
    spy.RecNoSets := 0;
    FGrid.VScrollBar.Position := 29;
    AssertEquals('the thumb: one RecNo', 1, spy.RecNoSets);
    AssertEquals('to position + 1', 30, spy.FieldByName('ID').AsInteger);
    k := VK_DOWN;
    FGrid.VScrollBar.ScrollByKey(k);
    AssertEquals('a line: RecNo too', 2, spy.RecNoSets);
    AssertEquals('the next record', 31, spy.FieldByName('ID').AsInteger);
  finally
    FGrid.DataSource := nil;
    src.Free;
    spy.Free;
  end;
end;

procedure TDBGridNavTest.TestNonSequencedBarHasThreePositions;
var
  bar: TTyScrollBar;
begin
  FGrid.DataSource := FNonSeqSrc;
  bar := FGrid.VScrollBar;
  AssertTrue('a full window: a bar', bar.Visible);
  AssertEquals('three positions: 0, 2, 4', 4, bar.Max);
  AssertEquals('a page of two', 2, bar.PageSize);
  AssertEquals('at the start', 0, bar.Position);
  FNonSeq.Next;
  AssertEquals('inside', 2, bar.Position);
  FNonSeq.MoveBy(20);
  AssertEquals('still inside, wherever', 2, bar.Position);
  FNonSeq.Last;
  AssertEquals('at the end', 4, bar.Position);
  FNonSeq.First;
  AssertEquals('at the start again', 0, bar.Position);
end;

procedure TDBGridNavTest.TestNonSequencedBarMovesByDirection;
var
  bar: TTyScrollBar;
  k: Word;
  page: Integer;
begin
  FGrid.DataSource := FNonSeqSrc;
  bar := FGrid.VScrollBar;
  page := FGrid.DataLink.BufferCount;
  k := VK_DOWN;
  bar.ScrollByKey(k);                      // 0 -> 1: one step
  AssertEquals('a line: MoveBy(1)', 2, NonSeqID);
  AssertEquals('the bar back inside', 2, bar.Position);
  AssertRowShowsTheRecord('line');
  k := VK_NEXT;
  bar.ScrollByKey(k);                      // 2 -> 4: more than a step
  AssertEquals('a page: MoveBy(the window)', 2 + page, NonSeqID);
  AssertEquals('inside again', 2, bar.Position);
  bar.Position := 0;                       // the thumb to the top: more than a step up
  AssertEquals('the thumb up: MoveBy(-the window), not the first record', 2, NonSeqID);
  k := VK_UP;
  bar.ScrollByKey(k);                      // 2 -> 1
  AssertEquals('a line up', 1, NonSeqID);
  AssertRowShowsTheRecord('line up');
end;

procedure TDBGridNavTest.TestNoBarWhenEveryRecordFits;
begin
  FGrid.DataSource := FPeople.Src;
  AssertTrue('three records in the window', FGrid.RowCount = 3);
  AssertFalse('no bar', FGrid.VScrollBar.Visible);
  FGrid.DataSource := FRows.Src;
  AssertTrue('forty: a bar', FGrid.VScrollBar.Visible);
  FGrid.DataSource := nil;
  AssertFalse('no dataset: no bar', FGrid.VScrollBar.Visible);
end;

initialization
  RegisterTest(TDBGridNavTest);
end.
