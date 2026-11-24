unit test.richedit.grid;

{ A table as a grid (tyControls.RichEdit.Grid): Word's merged table read as the grid Word
  itself shows (its gridSpan / vMerge, as its XML says them - the fixture beside the file),
  merge marks and wide cells read as one grid, files with merged cells opened and saved as
  their bytes, and the grid made on demand only. No control, no window. The unit is ASCII:
  the fixtures' Chinese text is compared as bytes. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LCLType, fpcunit, testregistry, tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.RtfRead,
  tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout, tyControls.RichEdit.TableSel,
  tyControls.RichEdit, tyControls.RichEdit.Grid, test.richedit.layoutdevice;

type
  TTyRichGridTest = class(TTestCase)
  published
    procedure TestWordsMergedTableGivesTheGridWordShows;
    procedure TestWideCellsAndMergeFlagsAreTheSameGrid;
    procedure TestOpenSaveStaysByteIdentical;
    procedure TestARowShorterThanTheGridHasEmptyPlaces;
  end;

  TGridRich = class(TTyRichEdit)
  protected
    function CreateDevice: TTyRichTextDevice; override;
  public
    procedure Key(AKey: Word; AShift: TShiftState = []);
  end;

  { The grid in the control: a selection grows over spans, Tab, Shift+Tab and the arrows pass
    covered cells, a hit in a span lands in its cell; no key makes the grid. }
  TTyRichGridControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TGridRich;
    procedure Load(const ARtf: RawByteString);
    function ParaOfCaret: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSelectionGrowsToWholeMergedCells;
    procedure TestTabAndArrowsFollowTheGrid;
    procedure TestAHitInASpanLandsInItsCell;
  end;

{ The listing of the grid of the table at ATablePos, in the form of
  tests/fixtures/rtf/word-table-styled.grid.txt: 'grid' and the columns' widths, then a line
  per row - each cell as gridSpan/vMerge/width/text, two spaces apart (a cell that continues
  a merge across is no cell of its own: left out). For the files a person compares with
  Word's own grid. }
function TyRichGridListing(ADoc: TTyRichDocument; ATablePos: TTyRichPos): TStringList;

implementation

{ ---- helpers ---- }

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'rtf' + PathDelim;
end;

function FixtureBytes(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(FixtureDir + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function LoadDoc(const ABytes: TBytes; AFull: Boolean = True): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    try
      if AFull then TyRichLoadRtfFull(Result, s) else TyRichLoadRtf(Result, s);
    except
      Result.Free;
      raise;
    end;
  finally
    s.Free;
  end;
end;

function SaveBytes(ADoc: TTyRichDocument): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveRtf(ADoc, s);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

// The first paragraph of the ANth table (from 0), -1 for none.
function TablePara(ADoc: TTyRichDocument; AN: Integer): Integer;
var
  i: Integer;
  t: TTyRichTable;
begin
  ADoc.BeginRead;
  try
    for i := 0 to ADoc.Text.ParaCount - 1 do
    begin
      t := ADoc.TableAt(i);
      if (t <> nil) and ((i = 0) or (ADoc.TableAt(i - 1) <> t)) then
      begin
        if AN = 0 then Exit(i);
        Dec(AN);
      end;
    end;
  finally
    ADoc.EndRead;
  end;
  Result := -1;
end;

function IfThen(B: Boolean; const T, F: string): string;
begin
  if B then Result := T else Result := F;
end;

function TyRichGridListing(ADoc: TTyRichDocument; ATablePos: TTyRichPos): TStringList;
var
  g: TTyRichGrid;
  r, i, f, l, k, tp: Integer;
  gc: TTyRichGridCell;
  line, vm, txt: string;
begin
  Result := TStringList.Create;
  g := TyRichTableGrid(ADoc, ATablePos);
  if g = nil then Exit;
  try
    tp := ADoc.Text.ParaOfPos(ATablePos);
    line := 'grid';
    for i := 0 to g.ColCount - 1 do line := line + ' ' + IntToStr(g.ColWidth(i));
    Result.Add(line);
    for r := 0 to g.RowCount - 1 do
    begin
      line := 'row';
      for i := 0 to g.CellCountOfRow(r) - 1 do
      begin
        gc := g.CellOf(r, i);
        if gc.ColSpan = 0 then Continue;
        // (merged across into the cell before: no cell of its own)
        if gc.Covered and (gc.Row = r) then Continue;
        if gc.Covered then vm := 'cont'
        else if gc.RowSpan > 1 then vm := 'restart'
        else vm := '-';
        txt := '';
        if ADoc.TableCellParas(tp, r, i, f, l) then
          for k := f to l do txt := txt + ADoc.Text.GetText(ADoc.Text.ParaStart(k), ADoc.Text.ParaLength(k));
        line := line + Format('%s%d/%s/%d/%s', [IfThen(line = 'row', ' ', '  '), gc.ColSpan, vm,
          g.Edge(gc.Col + gc.ColSpan) - g.Edge(gc.Col), txt]);
      end;
      Result.Add(line);
    end;
  finally
    g.Free;
  end;
end;

{ AGot against AWant (comment lines out of it), widths within two twips. }
procedure CompareListings(ATest: TTestCase; AWant, AGot: TStrings);
var
  want: TStringList;
  i, j: Integer;
  a, b, pa, pb: TStringList;
begin
  want := TStringList.Create;
  a := TStringList.Create;
  b := TStringList.Create;
  pa := TStringList.Create;
  pb := TStringList.Create;
  try
    for i := 0 to AWant.Count - 1 do
      if (Trim(AWant[i]) <> '') and (Copy(Trim(AWant[i]), 1, 1) <> '#') then want.Add(Trim(AWant[i]));
    ATest.AssertEquals('lines', want.Count, AGot.Count);
    for i := 0 to want.Count - 1 do
    begin
      a.Delimiter := ' ';
      a.StrictDelimiter := False;
      a.DelimitedText := want[i];
      b.Delimiter := ' ';
      b.StrictDelimiter := False;
      b.DelimitedText := AGot[i];
      ATest.AssertEquals(Format('line %d: cells [%s] [%s]', [i, want[i], AGot[i]]), a.Count, b.Count);
      ATest.AssertEquals(Format('line %d: kind', [i]), a[0], b[0]);
      for j := 1 to a.Count - 1 do
        if a[0] = 'grid' then
          ATest.AssertTrue(Format('line %d: column %d %s ~ %s', [i, j, a[j], b[j]]),
            Abs(StrToInt(a[j]) - StrToInt(b[j])) <= 2)
        else
        begin
          pa.Delimiter := '/';
          pa.StrictDelimiter := True;
          pa.DelimitedText := a[j];
          pb.Delimiter := '/';
          pb.StrictDelimiter := True;
          pb.DelimitedText := b[j];
          ATest.AssertEquals(Format('line %d cell %d: parts', [i, j]), 4, pb.Count);
          ATest.AssertEquals(Format('line %d cell %d: span', [i, j]), pa[0], pb[0]);
          ATest.AssertEquals(Format('line %d cell %d: vMerge', [i, j]), pa[1], pb[1]);
          ATest.AssertTrue(Format('line %d cell %d: width %s ~ %s', [i, j, pa[2], pb[2]]),
            Abs(StrToInt(pa[2]) - StrToInt(pb[2])) <= 2);
          ATest.AssertEquals(Format('line %d cell %d: text', [i, j]), pa[3], pb[3]);
        end;
    end;
  finally
    pb.Free;
    pa.Free;
    b.Free;
    a.Free;
    want.Free;
  end;
end;

{ ---- tests ---- }

{ Table 2 of the Word file: a wide cell over two columns, a cell over two rows and a cell
  over two columns and two rows - the grid Word's own XML gives (gridSpan, vMerge, widths). }
procedure TTyRichGridTest.TestWordsMergedTableGivesTheGridWordShows;
var
  d: TTyRichDocument;
  want, got: TStringList;
  full: Boolean;
  g: TTyRichGrid;
begin
  want := TStringList.Create;
  try
    want.LoadFromFile(FixtureDir + 'word-table-styled.grid.txt');
    for full := False to True do
    begin
      d := LoadDoc(FixtureBytes('word-table-styled.rtf'), full);
      try
        got := TyRichGridListing(d, d.Text.ParaStart(TablePara(d, 1)));
        try
          CompareListings(Self, want, got);
        finally
          got.Free;
        end;
        g := TyRichTableGrid(d, d.Text.ParaStart(TablePara(d, 1)));
        try
          AssertTrue('consistent', g.Consistent);
          AssertEquals('4 columns', 4, g.ColCount);
          AssertEquals('the 2 x 2 span', 2, g.Cell(2, 2).RowSpan);
          AssertEquals('... across', 2, g.Cell(2, 2).ColSpan);
          AssertTrue('its place below is covered', g.Cell(3, 3).Covered);
          AssertEquals('by it', 2, g.Cell(3, 3).Row);
          AssertEquals('... the cell of the row there', 2, g.Cell(3, 3).CoveredCell);
          AssertTrue('inside the wide cell: no cell of its own', g.Cell(0, 1).Covered and
            (g.Cell(0, 1).CoveredCell = -1) and (g.Cell(0, 1).Cell = 0));
        finally
          g.Free;
        end;
      finally
        d.Free;
      end;
    end;
  finally
    want.Free;
  end;
end;

const
  // the same table twice: a cell over two columns as one wide cell / as merge marks, and a
  // cell over two rows
  CWide = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx2000\cellx3000\pard\intbl A\cell B\cell\row' +
    '\trowd\clvmgf\cellx1000\cellx2000\cellx3000\pard\intbl C\cell D\cell E\cell\row' +
    '\trowd\clvmrg\cellx1000\cellx2000\cellx3000\pard\intbl\cell F\cell G\cell\row' +
    '\pard\par}';
  CFlags = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\clmgf\cellx1000\clmrg\cellx2000\cellx3000\pard\intbl A\cell\cell B\cell\row' +
    '\trowd\clvmgf\cellx1000\cellx2000\cellx3000\pard\intbl C\cell D\cell E\cell\row' +
    '\trowd\clvmrg\cellx1000\cellx2000\cellx3000\pard\intbl\cell F\cell G\cell\row' +
    '\pard\par}';

procedure TTyRichGridTest.TestWideCellsAndMergeFlagsAreTheSameGrid;
var
  d1, d2: TTyRichDocument;
  a, b: TStringList;
  g: TTyRichGrid;
begin
  d1 := LoadDoc(BytesOf(CWide));
  d2 := LoadDoc(BytesOf(CFlags));
  try
    a := TyRichGridListing(d1, 0);
    b := TyRichGridListing(d2, 0);
    try
      AssertEquals('the wide cell''s', 'grid 1000 1000 1000', a[0]);
      AssertEquals('the first row', 'row 2/-/2000/A  1/-/1000/B', a[1]);
      AssertEquals('the second', 'row 1/restart/1000/C  1/-/1000/D  1/-/1000/E', a[2]);
      AssertEquals('the third', 'row 1/cont/1000/  1/-/1000/F  1/-/1000/G', a[3]);
      AssertEquals('one grid', a.Text, b.Text);
    finally
      a.Free;
      b.Free;
    end;
    g := TyRichTableGrid(d2, 0);
    try
      AssertTrue('consistent', g.Consistent);
      AssertTrue('the second mark''s cell is covered', g.CellOf(0, 1).Covered);
      AssertEquals('... by the first', 0, g.CellOf(0, 1).Cell);
      AssertEquals('the span over two rows', 2, g.CellOf(1, 0).RowSpan);
      AssertTrue('its cell below is covered', g.CellOf(2, 0).Covered and (g.CellOf(2, 0).Row = 1));
    finally
      g.Free;
    end;
  finally
    d1.Free;
    d2.Free;
  end;
end;

{ Every file of the fixtures with a table opens and saves as its bytes - merged cells, wide
  cells and nested tables among them. }
procedure TTyRichGridTest.TestOpenSaveStaysByteIdentical;
const
  Files: array[0..4] of string = ('word-table-styled.rtf', 'word-table-merged.rtf',
    'hand-word-table-merged.rtf', 'wp-zh-table.rtf', 're-zh-table.rtf');
var
  i: Integer;
  b: TBytes;
  d: TTyRichDocument;
begin
  for i := 0 to High(Files) do
  begin
    if not FileExists(FixtureDir + Files[i]) then Continue;
    b := FixtureBytes(Files[i]);
    d := LoadDoc(b);
    try
      AssertTrue(Files[i], SameBytes(b, SaveBytes(d)));
    finally
      d.Free;
    end;
  end;
end;

{ A row with fewer cells than the grid's columns: its places past its last cell are no
  cell's; every cell is still at one place. }
procedure TTyRichGridTest.TestARowShorterThanTheGridHasEmptyPlaces;
const
  Short = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx1000\cellx2000\cellx3000\pard\intbl A\cell B\cell C\cell\row' +
    '\trowd\cellx1000\pard\intbl D\cell\row' +
    '\pard\par}';
var
  d: TTyRichDocument;
  g: TTyRichGrid;
  n: Int64;
begin
  d := LoadDoc(BytesOf(Short));
  try
    n := TyRichGridBuildCount;
    g := TyRichTableGrid(d, 0);
    try
      AssertEquals('one grid made', n + 1, TyRichGridBuildCount);
      AssertEquals('3 columns', 3, g.ColCount);
      AssertEquals('its cell', 0, g.Cell(1, 0).Cell);
      AssertEquals('past it: none', -1, g.Cell(1, 1).Cell);
      AssertFalse('... not covered', g.Cell(1, 2).Covered);
      AssertTrue('consistent', g.Consistent);
    finally
      g.Free;
    end;
  finally
    d.Free;
  end;
end;

{ ---- the control ---- }

function TGridRich.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichTestDevice.Create;
end;

procedure TGridRich.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

const
  { 'x', then a table of three rows: A over two rows (its cell below covered), B C / D E
    beside it, then F and G - G a wide cell over two columns; the paragraphs: 0 x, 1 A, 2 B,
    3 C, 4 the covered cell, 5 D, 6 E, 7 F, 8 G, 9 the last. }
  CSpans = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\clvmgf\cellx1500\cellx3000\cellx4500\pard\intbl A\cell B\cell C\cell\row' +
    '\trowd\clvmrg\cellx1500\cellx3000\cellx4500\pard\intbl\cell D\cell E\cell\row' +
    '\trowd\cellx1500\cellx4500\pard\intbl F\cell G\cell\row' +
    '\pard\par}';

procedure TTyRichGridControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TGridRich.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 600, 400);
  FRich.WantTabs := True;
end;

procedure TTyRichGridControlTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

procedure TTyRichGridControlTest.Load(const ARtf: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(BytesOf(ARtf));
  try
    FRich.LoadFromStream(st, rfRtf);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
end;

function TTyRichGridControlTest.ParaOfCaret: Integer;
begin
  Result := FRich.Document.Text.ParaOfPos(FRich.SelStart + FRich.SelLength);
end;

function PS(R: TTyRichEdit; APara: Integer): TTyRichPos;
begin
  Result := R.Document.Text.ParaStart(APara);
end;

// from the start of paragraph AFrom to after the end mark of paragraph ATo
procedure SelCells(R: TTyRichEdit; AFrom, ATo: Integer);
begin
  R.SelStart := PS(R, AFrom);
  R.SelLength := PS(R, ATo) + R.Document.Text.ParaLength(ATo) + 1 - PS(R, AFrom);
end;

procedure TTyRichGridControlTest.TestSelectionGrowsToWholeMergedCells;
var
  g: TTyRichCellRange;
  n: Int64;
begin
  Load(CSpans);
  n := TyRichGridBuildCount;
  // B to D: cells of no span - as they are
  SelCells(FRich, 2, 5);
  g := FRich.SelectedCells;
  AssertTrue('cells', g.InTable);
  AssertEquals('B..D: from row 0', 0, g.Row0);
  AssertEquals('B..D: to row 1', 1, g.Row1);
  AssertFalse('B..D: not the table', g.WholeTable);
  // A whole: the span - both its rows
  SelCells(FRich, 1, 1);
  g := FRich.SelectedCells;
  AssertEquals('A: row 0', 0, g.Row0);
  AssertEquals('A: and the row it reaches into', 1, g.Row1);
  // D to F: F's cell column meets the covered cell (row 0 joins), G's wide cell reaches to
  // the right edge - the whole table, grown round by round
  SelCells(FRich, 5, 7);
  g := FRich.SelectedCells;
  AssertEquals('D..F: up to the span''s row', 0, g.Row0);
  AssertEquals('D..F: to row 2', 2, g.Row1);
  AssertTrue('D..F: the whole table', g.WholeTable);
  // E to G: G is wide, but the span's column is not reached
  SelCells(FRich, 6, 8);
  g := FRich.SelectedCells;
  AssertEquals('E..G: from row 1', 1, g.Row0);
  AssertEquals('E..G: to row 2', 2, g.Row1);
  AssertFalse('E..G: not the table', g.WholeTable);
  // SelectCell on the span: it whole
  FRich.SelStart := PS(FRich, 1);
  AssertTrue('SelectCell', FRich.SelectCell);
  g := FRich.SelectedCells;
  AssertEquals('SelectCell: both rows', 1, g.Row1 - g.Row0);
  AssertEquals('no grid made for any of it', n, TyRichGridBuildCount);
end;

procedure TTyRichGridControlTest.TestTabAndArrowsFollowTheGrid;
var
  n: Int64;
begin
  Load(CSpans);
  n := TyRichGridBuildCount;
  // Tab from C: the covered cell passed, D
  FRich.SelStart := PS(FRich, 3);
  FRich.Key(VK_TAB);
  AssertEquals('Tab: D', 5, FRich.Document.Text.ParaOfPos(FRich.SelStart));
  FRich.Key(VK_TAB, [ssShift]);
  AssertEquals('Shift+Tab: back to C', 3, FRich.Document.Text.ParaOfPos(FRich.SelStart));
  // Down from A: past the span, to F
  FRich.SelStart := PS(FRich, 1);
  FRich.Key(VK_DOWN);
  AssertEquals('Down from the span: the row below it', 7, ParaOfCaret);
  // Up from F: into the span's cell
  FRich.Key(VK_UP);
  AssertEquals('Up into the span: its cell', 1, ParaOfCaret);
  // Down from B: D (no span there)
  FRich.SelStart := PS(FRich, 2);
  FRich.Key(VK_DOWN);
  AssertEquals('Down from B: D', 5, ParaOfCaret);
  // Left from D's start: the covered cell passed - C's end
  FRich.SelStart := PS(FRich, 5);
  FRich.Key(VK_LEFT);
  AssertEquals('Left: C', 3, ParaOfCaret);
  FRich.Key(VK_RIGHT);
  AssertEquals('Right: D again', 5, ParaOfCaret);
  AssertEquals('no grid made by a key', n, TyRichGridBuildCount);
end;

procedure TTyRichGridControlTest.TestAHitInASpanLandsInItsCell;
var
  r: TRect;
  p: TTyRichPos;
begin
  Load(CSpans);
  // the covered cell's own place: the span's cell, at its text's end
  r := FRich.ParagraphRect(4);
  p := FRich.PositionAtPoint(r.Left + 2, (r.Top + r.Bottom) div 2);
  AssertEquals('in the span''s cell', 1, FRich.Document.Text.ParaOfPos(p));
  AssertEquals('at its end', PS(FRich, 1) + 1, p);
end;

initialization
  RegisterTest(TTyRichGridTest);
  RegisterTest(TTyRichGridControlTest);
end.
