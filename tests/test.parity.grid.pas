unit test.parity.grid;
{ LCL parity for TTyCustomGrid / TTyStringGrid: six members that carried an LCL name
  while meaning something else.

  Five of the six could bite SILENTLY -- the ported call compiled and did the wrong
  thing -- so each gets a guard here that fails if the old meaning ever comes back:

    VisibleRowCount   was DisplayRowCount (a data metric). Ported paging maths paged
                      by "rows that passed the filter"; with 10000 filtered-in rows it
                      paged 10000 at a time. Now a viewport metric, as in LCL
                      (grids.pas:1301 / GetVisibleRowCount at 2274).
    Selection         was a read-only function, so a saved rect could not be put back.
                      Now read/write (grids.pas:1292).
    ClearRows/Cols    blanked cell CONTENT over a band while LCL's DELETE rows/columns
                      (grids.pas:10285-10316). Band blanking is now ClearRowContents /
                      ClearColContents, and the LCL names do the structural delete.
    SaveToStream      took ADelimiter with a DEFAULT, so `Grid.SaveToStream(ms)` from
                      ported code compiled and quietly wrote bare CSV -- losing columns,
                      widths, frozen counts and position. CSV over a stream now lives
                      under LCL's own name for it (SaveToCSVStream, grids.pas:1815) and
                      SaveToStream carries the full state.
    CSV titles        the header row was mandatory in both directions; LCL's
                      WriteTitles / UseTitles make it optional.

  The sixth, GridLineStyle, is a collision we KEPT (ours = which axes get lines, LCL's =
  the pen style). It cannot bite silently -- the enum types differ, so every ported use
  is a compile error -- so the guard is that the divergence stays documented. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Grid;

type
  { Promotes the protected scroll offsets -- the position half of the state stream
    cannot be checked without them. }
  TGridScrollAccess = class(TTyStringGrid)
  public
    property ScrollX;
    property ScrollY;
  end;

  { Common fixture: a 400x300 grid, 4 columns of 80, rows 20 high, header band hidden
    so the viewport maths is not perturbed by it. }
  TGridParityFixture = class(TTestCase)
  protected
    FForm: TForm;
    FCtl: TTyStyleController;
    { Returns the BARE class on purpose: every member these guards touch has to be
      reachable from a plain TTyStringGrid variable, i.e. from a host. A promoting
      subclass would let a member slip back into protected and still test green. }
    function NewGrid: TTyStringGrid;
    function NewScrollGrid: TGridScrollAccess;
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  { VisibleRowCount must answer "how many rows fit on screen", never "how many rows
    survived the filter". }
  TGridViewportMetricTest = class(TGridParityFixture)
  published
    procedure TestVisibleRowCountIsBoundedByTheViewportNotTheRowCount;
    procedure TestVisibleRowCountShrinksWithTheViewport;
    procedure TestVisibleRowCountCountsWholeGridWhenItFits;
    procedure TestDataMetricsStillAvailableUnderTheirOwnNames;
  end;

  { Selection has to round-trip: read a rect, put it back, get the same selection. }
  TGridSelectionWritableTest = class(TGridParityFixture)
  published
    procedure TestSelectionRoundTripsThroughARect;
    procedure TestSelectionClampsOutOfRangeRects;
    procedure TestAllNegativeRectCancelsTheSelection;
    procedure TestSelectionNormalisesAReversedRect;
  end;

  { ClearRows/ClearCols are structural; the band blanking answers to a different name. }
  TGridStructuralClearTest = class(TGridParityFixture)
  published
    procedure TestClearRowsDeletesEveryRow;
    procedure TestClearRowsReportsWhetherItChangedAnything;
    procedure TestClearColsDeletesEveryColumn;
    procedure TestClearColsReportsWhetherItChangedAnything;
    procedure TestClearRowContentsStillOnlyBlanksTheBand;
    procedure TestClearColContentsStillOnlyBlanksTheBand;
  end;

  { SaveToStream/LoadFromStream carry the whole grid, not just the text. }
  TGridStateStreamTest = class(TGridParityFixture)
  published
    procedure TestStreamRoundTripsStructureAndPosition;
    procedure TestStreamRoundTripsTheScrollOffset;
    procedure TestStreamKeepsFilteredOutRows;
    procedure TestLoadFromStreamRefusesPlainCsv;
    procedure TestLoadFromStreamRefusesAnEmptyStream;
    procedure TestCsvOverAStreamStillWorksUnderItsOwnName;
  end;

  { The CSV title row is optional in both directions. }
  TGridCsvTitlesTest = class(TGridParityFixture)
  published
    procedure TestSaveCanOmitTheTitleRow;
    procedure TestLoadCanTreatTheFirstLineAsData;
    procedure TestTitlelessRoundTripKeepsEveryRow;
  end;

  { GridLineStyle: the kept divergence must stay written down. }
  TGridLineStyleDivergenceTest = class(TTestCase)
  published
    procedure TestDivergenceIsDocumented;
  end;

implementation

{ TGridParityFixture }

procedure TGridParityFixture.SetUp;
begin
  inherited SetUp;
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
end;

procedure TGridParityFixture.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TGridParityFixture.NewGrid: TTyStringGrid;
begin
  Result := NewScrollGrid;
end;

function TGridParityFixture.NewScrollGrid: TGridScrollAccess;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TGridScrollAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 80;
    c.Text := 'C' + IntToStr(i);
  end;
  Result.Header.Options := Result.Header.Options - [hoVisible];
  Result.DefaultRowHeight := 20;
  Result.RowCount := 10;
end;

{ TGridViewportMetricTest }

{ The defect in one assertion: with 100 rows in a 300px viewport the old
  VisibleRowCount answered 100. A viewport metric cannot exceed what the viewport
  holds, and at 20px a row a 300px viewport holds ~15. }
procedure TGridViewportMetricTest.TestVisibleRowCountIsBoundedByTheViewportNotTheRowCount;
var
  G: TTyStringGrid;
  n: Integer;
begin
  G := NewGrid;
  G.RowCount := 100;
  n := G.VisibleRowCount;
  AssertTrue('VisibleRowCount must not be the row count (it is a viewport metric)',
    n < G.RowCount);
  { Pinned to within one row of the viewport instead of a magic number, so the guard
    survives a client-area or scrollbar tweak but not a return to the data metric.
    LCL leaves one row of overlap for paging (grids.pas:2274), hence the +2. }
  AssertTrue('at most as many rows as the viewport holds',
    n * G.DefaultRowHeight <= G.ClientHeight);
  AssertTrue('and not far fewer either',
    (n + 2) * G.DefaultRowHeight > G.ClientHeight);
end;

{ A viewport metric follows the viewport. A data metric would not move at all. }
procedure TGridViewportMetricTest.TestVisibleRowCountShrinksWithTheViewport;
var
  G: TTyStringGrid;
  tall, short: Integer;
begin
  G := NewGrid;
  G.RowCount := 100;
  tall := G.VisibleRowCount;
  G.Height := 120;
  short := G.VisibleRowCount;
  AssertTrue('a shorter grid shows fewer rows', short < tall);
  AssertEquals('while the data metric is untouched', 100, G.DisplayRowCount);
end;

{ LCL drops the paging overlap when the whole grid fits (grids.pas:2274 `if
  GridHeight<=ClientHeight then inc`), so a 5-row grid answers 5, not 4. }
procedure TGridViewportMetricTest.TestVisibleRowCountCountsWholeGridWhenItFits;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.RowCount := 5;
  AssertEquals('a grid that fits reports all of its rows', 5, G.VisibleRowCount);
  G.RowCount := 0;
  AssertEquals('an empty grid shows nothing', 0, G.VisibleRowCount);
end;

{ The old meaning was not lost, it was already spelled two other ways. }
procedure TGridViewportMetricTest.TestDataMetricsStillAvailableUnderTheirOwnNames;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.RowCount := 5;
  G.Cells[0, 0] := 'keep';
  G.Cells[0, 1] := 'drop';
  G.Cells[0, 2] := 'keep';
  G.Cells[0, 3] := 'drop';
  G.Cells[0, 4] := 'keep';
  G.SetColumnFilter(0, 'keep');
  AssertEquals('DisplayRowCount is the data metric', 3, G.DisplayRowCount);
  AssertEquals('FilteredRowCount says the same thing', 3, G.FilteredRowCount);
end;

{ TGridSelectionWritableTest }

procedure TGridSelectionWritableTest.TestSelectionRoundTripsThroughARect;
var
  G: TTyStringGrid;
  saved, back: TRect;
begin
  G := NewGrid;
  G.SelectRange(1, 1, 2, 3);
  saved := G.Selection;

  G.ClearSelection;
  AssertEquals('the selection really was dropped', 1, G.SelectedCellCount);

  G.Selection := saved;                    { the whole point: it is writable }
  back := G.Selection;
  AssertEquals('left survives the round trip', saved.Left, back.Left);
  AssertEquals('top survives the round trip', saved.Top, back.Top);
  AssertEquals('right survives the round trip', saved.Right, back.Right);
  AssertEquals('bottom survives the round trip', saved.Bottom, back.Bottom);
  AssertTrue('and the cells really are selected again', G.IsCellSelected(1, 2));
  AssertFalse('without spilling outside the rect', G.IsCellSelected(3, 2));
end;

procedure TGridSelectionWritableTest.TestSelectionClampsOutOfRangeRects;
var
  G: TTyStringGrid;
  r: TRect;
begin
  G := NewGrid;                            { 4 columns, 10 rows }
  G.Selection := Rect(-3, -2, 99, 99);
  r := G.Selection;
  AssertEquals('left clamped into the grid', 0, r.Left);
  AssertEquals('top clamped into the grid', 0, r.Top);
  AssertEquals('right clamped to the last column', 3, r.Right);
  AssertEquals('bottom clamped to the last row', 9, r.Bottom);
end;

{ LCL treats an all-negative rect as "cancel" (grids.pas SetSelection -> CancelSelection),
  and a rect read back from an empty selection is exactly that shape -- so without this
  branch a save/restore of "nothing selected" would select the top-left corner instead. }
procedure TGridSelectionWritableTest.TestAllNegativeRectCancelsTheSelection;
var
  G: TTyStringGrid;
  r: TRect;
begin
  G := NewGrid;
  G.SelectRange(0, 0, 3, 5);         { cursor ends up at the far corner, (3,5) }
  AssertTrue('something is selected first', G.SelectedCellCount > 1);

  G.Selection := Rect(-1, -1, -1, -1);
  AssertEquals('an all-negative rect cancels', 1, G.SelectedCellCount);
  { WHERE it collapses is the whole point, and asserting only the count does not say
    it: without the cancel branch the rect just clamps to (0,0,0,0), which is also a
    one-cell selection -- it passes the count check while having silently yanked the
    cursor to the top-left corner. Cancelling collapses onto the CURSOR. }
  r := G.Selection;
  AssertEquals('it collapses onto the cursor, not onto the origin', 3, r.Left);
  AssertEquals('it collapses onto the cursor, not onto the origin', 5, r.Top);
  AssertEquals('cursor column untouched', 3, G.Col);
  AssertEquals('cursor row untouched', 5, G.Row);
end;

procedure TGridSelectionWritableTest.TestSelectionNormalisesAReversedRect;
var
  G: TTyStringGrid;
  r: TRect;
begin
  G := NewGrid;
  G.Selection := Rect(3, 6, 1, 2);          { bottom-right to top-left }
  r := G.Selection;
  AssertEquals('normalised left', 1, r.Left);
  AssertEquals('normalised top', 2, r.Top);
  AssertEquals('normalised right', 3, r.Right);
  AssertEquals('normalised bottom', 6, r.Bottom);
  AssertTrue('and it selects the same block either way', G.IsCellSelected(2, 4));
end;

{ TGridStructuralClearTest }

procedure TGridStructuralClearTest.TestClearRowsDeletesEveryRow;
var
  G: TTyStringGrid;
  r, c: Integer;
begin
  G := NewGrid;
  G.RowCount := 6;
  for r := 0 to 5 do
    for c := 0 to 3 do
      G.Cells[c, r] := Format('%d-%d', [c, r]);
  G.FixedRows := 2;

  AssertTrue('ClearRows reports that it changed the grid', G.ClearRows);
  AssertEquals('every row is gone', 0, G.RowCount);
  AssertEquals('the columns are NOT touched', 4, G.Header.Columns.Count);
  { Sparse storage keyed by (col,row): leaving the strings behind would resurrect the
    old contents the moment RowCount grew again. }
  AssertEquals('no cell content is left behind', 0, G.StoredCellCount);
  AssertEquals('the frozen row count goes with the rows', 0, G.FixedRows);
end;

procedure TGridStructuralClearTest.TestClearRowsReportsWhetherItChangedAnything;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertTrue('first call clears', G.ClearRows);
  AssertFalse('second call has nothing to clear', G.ClearRows);
end;

procedure TGridStructuralClearTest.TestClearColsDeletesEveryColumn;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Cells[0, 0] := 'x';
  G.FixedCols := 1;
  AssertTrue('ClearCols reports that it changed the grid', G.ClearCols);
  AssertEquals('every column is gone', 0, G.Header.Columns.Count);
  AssertEquals('no cell content is left behind', 0, G.StoredCellCount);
  AssertEquals('the frozen column count goes with the columns', 0, G.FixedCols);
end;

procedure TGridStructuralClearTest.TestClearColsReportsWhetherItChangedAnything;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertTrue('first call clears', G.ClearCols);
  AssertFalse('second call has nothing to clear', G.ClearCols);
end;

{ The band blanking still exists -- under a name that cannot be reached by a ported
  ClearRows call. }
procedure TGridStructuralClearTest.TestClearRowContentsStillOnlyBlanksTheBand;
var
  G: TTyStringGrid;
  r, c: Integer;
begin
  G := NewGrid;
  G.RowCount := 6;
  for r := 0 to 5 do
    for c := 0 to 3 do
      G.Cells[c, r] := Format('%d-%d', [c, r]);

  G.ClearRowContents(1, 2);
  AssertEquals('the rows are still there', 6, G.RowCount);
  AssertEquals('blanked inside the band', '', G.Cells[0, 1]);
  AssertEquals('blanked inside the band', '', G.Cells[3, 2]);
  AssertEquals('untouched above the band', '0-0', G.Cells[0, 0]);
  AssertEquals('untouched below the band', '0-3', G.Cells[0, 3]);
end;

procedure TGridStructuralClearTest.TestClearColContentsStillOnlyBlanksTheBand;
var
  G: TTyStringGrid;
  r, c: Integer;
begin
  G := NewGrid;
  G.RowCount := 6;
  for r := 0 to 5 do
    for c := 0 to 3 do
      G.Cells[c, r] := Format('%d-%d', [c, r]);

  G.ClearColContents(1, 2);
  AssertEquals('the columns are still there', 4, G.Header.Columns.Count);
  AssertEquals('blanked inside the band', '', G.Cells[1, 0]);
  AssertEquals('blanked inside the band', '', G.Cells[2, 5]);
  AssertEquals('untouched left of the band', '0-0', G.Cells[0, 0]);
  AssertEquals('untouched right of the band', '3-0', G.Cells[3, 0]);
end;

{ TGridStateStreamTest }

{ Everything a CSV stream silently threw away: column widths, hidden columns, frozen
  counts, the cursor and the selection. }
procedure TGridStateStreamTest.TestStreamRoundTripsStructureAndPosition;
var
  G, G2: TTyStringGrid;
  ms: TMemoryStream;
  r: Integer;
  sel: TRect;
begin
  G := NewGrid;
  G.RowCount := 6;
  for r := 0 to 5 do
  begin
    G.Cells[0, r] := 'v' + IntToStr(r);
    G.Cells[1, r] := IntToStr(r * 10);
  end;
  { A field that only a real CSV escaper survives -- the state stream must not have
    grown its own second set of quoting rules. }
  G.Cells[2, 3] := 'has,comma' + LineEnding + 'and newline';
  TTyColumn(G.Header.Columns.Items[1]).Width := 137;
  G.HideColumn(2);
  G.FixedCols := 1;
  G.FixedRows := 2;
  { Anchored at the BOTTOM-RIGHT with the cursor at the top-left -- i.e. selected
    upwards. Reading Selection back normalises that to (0,1,2,3), so a restore that
    only replays the rect lands the cursor on the wrong corner and the next Shift+Up
    would extend the wrong way. Saving anchor AND cursor is what this pins. }
  G.SelectRange(2, 3, 0, 1);

  ms := TMemoryStream.Create;
  G2 := NewGrid;
  try
    G.SaveToStream(ms);
    AssertTrue('something was written', ms.Size > 0);
    ms.Position := 0;
    G2.LoadFromStream(ms);

    AssertEquals('row count', 6, G2.RowCount);
    AssertEquals('content', 'v5', G2.Cells[0, 5]);
    AssertEquals('escaped content', 'has,comma' + LineEnding + 'and newline',
      G2.Cells[2, 3]);
    AssertEquals('column count', 4, G2.Header.Columns.Count);
    AssertEquals('column title', 'C1', TTyColumn(G2.Header.Columns.Items[1]).Text);
    AssertEquals('column width', 137, TTyColumn(G2.Header.Columns.Items[1]).Width);
    AssertTrue('hidden column stays hidden', G2.IsHiddenColumn(2));
    AssertEquals('frozen columns', 1, G2.FixedCols);
    AssertEquals('frozen rows', 2, G2.FixedRows);
    AssertEquals('cursor column (the corner it was actually on)', 0, G2.Col);
    AssertEquals('cursor row (the corner it was actually on)', 1, G2.Row);
    sel := G2.Selection;
    AssertEquals('selection left', 0, sel.Left);
    AssertEquals('selection top', 1, sel.Top);
    AssertEquals('selection right', 2, sel.Right);
    AssertEquals('selection bottom', 3, sel.Bottom);
  finally
    ms.Free;
  end;
end;

{ Scroll is the other half of "position" and it is the half most easily lost, because
  restoring the cursor scrolls the grid on its own: MoveCursor calls ScrollIntoView.
  So the offset has to be applied AFTER the cursor, and this is what says so. }
procedure TGridStateStreamTest.TestStreamRoundTripsTheScrollOffset;
var
  G, G2: TGridScrollAccess;
  ms: TMemoryStream;
begin
  G := NewScrollGrid;
  G.RowCount := 100;                   { 2000px of content in a 300px viewport }
  { Cursor near the top, view scrolled far past it -- the state you get by spinning the
    wheel without touching the cursor. It is chosen deliberately: if the offset were
    restored BEFORE the cursor, restoring the cursor would ScrollIntoView and drag the
    view back up, and a test whose cursor sat inside the restored viewport would never
    notice. }
  G.MoveCursor(0, 5);
  G.ScrollY := 800;
  AssertEquals('the grid really is scrolled away from the cursor', 800, G.ScrollY);

  ms := TMemoryStream.Create;
  G2 := NewScrollGrid;
  try
    G.SaveToStream(ms);
    ms.Position := 0;
    G2.LoadFromStream(ms);
    AssertEquals('the scroll offset came back', 800, G2.ScrollY);
    AssertEquals('and the cursor is still where it was', 5, G2.Row);
  finally
    ms.Free;
  end;
end;

{ The content section walks DATA rows, not display order. Written in display order a
  filtered grid would save only the rows that happened to be showing -- the saved file
  would be missing data, and every saved row index would point somewhere else. }
procedure TGridStateStreamTest.TestStreamKeepsFilteredOutRows;
var
  G, G2: TTyStringGrid;
  ms: TMemoryStream;
begin
  G := NewGrid;
  G.RowCount := 4;
  G.Cells[0, 0] := 'keep';
  G.Cells[0, 1] := 'drop';
  G.Cells[0, 2] := 'keep';
  G.Cells[0, 3] := 'drop';
  G.SetColumnFilter(0, 'keep');
  AssertEquals('the filter really is on', 2, G.DisplayRowCount);

  ms := TMemoryStream.Create;
  G2 := NewGrid;
  try
    G.SaveToStream(ms);
    ms.Position := 0;
    G2.LoadFromStream(ms);
    AssertEquals('all four rows were saved', 4, G2.RowCount);
    AssertEquals('including the filtered-out ones, at their own index',
      'drop', G2.Cells[0, 1]);
    AssertEquals('and the visible ones did not shift', 'keep', G2.Cells[0, 2]);
  finally
    ms.Free;
  end;
end;

{ A stream in the old CSV shape must fail loudly. Guessing would put us straight back
  into "one call, two formats, no way to tell which you got". }
procedure TGridStateStreamTest.TestLoadFromStreamRefusesPlainCsv;
var
  G: TTyStringGrid;
  ms: TMemoryStream;
  raised: Boolean;
begin
  G := NewGrid;
  ms := TMemoryStream.Create;
  try
    G.SaveToCSVStream(ms);
    ms.Position := 0;
    raised := False;
    try
      G.LoadFromStream(ms);
    except
      on E: Exception do raised := True;
    end;
    AssertTrue('LoadFromStream must reject a bare CSV stream, not guess', raised);
  finally
    ms.Free;
  end;
end;

{ An empty stream is not a saved grid either -- silently clearing the control would
  make "the file was truncated" look exactly like "the user saved an empty table". }
procedure TGridStateStreamTest.TestLoadFromStreamRefusesAnEmptyStream;
var
  G: TTyStringGrid;
  ms: TMemoryStream;
  raised: Boolean;
begin
  G := NewGrid;
  G.RowCount := 3;
  G.Cells[0, 0] := 'still here';
  ms := TMemoryStream.Create;
  try
    raised := False;
    try
      G.LoadFromStream(ms);
    except
      on E: Exception do raised := True;
    end;
    AssertTrue('an empty stream must not pass for a saved grid', raised);
    AssertEquals('and the grid must be left alone', 'still here', G.Cells[0, 0]);
  finally
    ms.Free;
  end;
end;

procedure TGridStateStreamTest.TestCsvOverAStreamStillWorksUnderItsOwnName;
var
  G, G2: TTyStringGrid;
  ms: TMemoryStream;
begin
  G := NewGrid;
  G.RowCount := 3;
  G.Cells[0, 0] := 'a';
  G.Cells[0, 1] := 'b;semi';
  G.Cells[0, 2] := 'c';

  ms := TMemoryStream.Create;
  G2 := NewGrid;
  try
    G.SaveToCSVStream(ms, ';');
    ms.Position := 0;
    G2.LoadFromCSVStream(ms, ';');
    AssertEquals('rows', 3, G2.RowCount);
    AssertEquals('content', 'a', G2.Cells[0, 0]);
    AssertEquals('a field holding the delimiter still survives', 'b;semi',
      G2.Cells[0, 1]);
  finally
    ms.Free;
  end;
end;

{ TGridCsvTitlesTest }

procedure TGridCsvTitlesTest.TestSaveCanOmitTheTitleRow;
var
  G: TTyStringGrid;
  sl: TStringList;
begin
  G := NewGrid;
  G.RowCount := 2;
  G.Cells[0, 0] := 'r0';
  G.Cells[0, 1] := 'r1';

  sl := TStringList.Create;
  try
    sl.Text := G.SaveToCSVText(',');
    AssertEquals('titles on by default: header + 2 rows', 3, sl.Count);
    AssertEquals('and the header is line 0', 'C0,C1,C2,C3', sl[0]);

    sl.Text := G.SaveToCSVText(',', -1, -1, -1, -1, False);
    AssertEquals('titles off: data only', 2, sl.Count);
    AssertEquals('so line 0 is the first data row', 'r0,,,', sl[0]);
  finally
    sl.Free;
  end;
end;

procedure TGridCsvTitlesTest.TestLoadCanTreatTheFirstLineAsData;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.LoadFromCSVText('a,b' + LineEnding + 'c,d', ',', False, -1, 0, False);
  AssertEquals('no line was eaten as a header', 2, G.RowCount);
  AssertEquals('first line is data', 'a', G.Cells[0, 0]);
  AssertEquals('second line is data', 'c', G.Cells[0, 1]);
  AssertEquals('and the column titles were left alone', 'C0',
    TTyColumn(G.Header.Columns.Items[0]).Text);
end;

{ Both halves off must compose: a headerless export re-imported headerless keeps every
  row. Get one of the two flags wrong and a row silently becomes a header. }
procedure TGridCsvTitlesTest.TestTitlelessRoundTripKeepsEveryRow;
var
  G, G2: TTyStringGrid;
  txt: string;
begin
  G := NewGrid;
  G.RowCount := 3;
  G.Cells[0, 0] := 'p';
  G.Cells[0, 1] := 'q';
  G.Cells[0, 2] := 'r';
  txt := G.SaveToCSVText(',', -1, -1, -1, -1, False);

  G2 := NewGrid;
  G2.LoadFromCSVText(txt, ',', False, -1, 0, False);
  AssertEquals('every row came back', 3, G2.RowCount);
  AssertEquals('in order', 'p', G2.Cells[0, 0]);
  AssertEquals('in order', 'r', G2.Cells[0, 2]);
end;

{ TGridLineStyleDivergenceTest }

{ GridLineStyle is the one collision we kept: ours picks WHICH AXES get lines, LCL's is
  the pen style (grids.pas:1266, TPenStyle). Renaming ours would break every streamed
  .lfm that already carries the property, and the enum types differ so no ported use can
  compile by accident -- which leaves "say so, loudly" as the whole fix. This guard makes
  the saying-so load-bearing: delete the note and the suite goes red. }
procedure TGridLineStyleDivergenceTest.TestDivergenceIsDocumented;
var
  doc: TStringList;
  fn, all: string;
begin
  fn := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'docs' + PathDelim
        + 'controls' + PathDelim + 'grid.md';
  AssertTrue('grid.md must exist at ' + fn, FileExists(fn));
  doc := TStringList.Create;
  try
    doc.LoadFromFile(fn);
    all := doc.Text;
    AssertTrue('grid.md must warn that GridLineStyle is NOT the LCL TPenStyle',
      (Pos('GridLineStyle', all) > 0) and (Pos('TPenStyle', all) > 0));
  finally
    doc.Free;
  end;
end;

initialization
  RegisterTest(TGridViewportMetricTest);
  RegisterTest(TGridSelectionWritableTest);
  RegisterTest(TGridStructuralClearTest);
  RegisterTest(TGridStateStreamTest);
  RegisterTest(TGridCsvTitlesTest);
  RegisterTest(TGridLineStyleDivergenceTest);
end.
