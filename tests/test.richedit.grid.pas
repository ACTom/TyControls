unit test.richedit.grid;

{ A table as a grid (tyControls.RichEdit.Grid): Word's merged table read as the grid Word
  itself shows (its gridSpan / vMerge, as its XML says them - the fixture beside the file),
  merge marks and wide cells read as one grid, files with merged cells opened and saved as
  their bytes, and the grid made on demand only. No control, no window. The unit is ASCII:
  the fixtures' Chinese text is compared as bytes. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Types, Controls, Graphics, LCLType, fpcunit, testregistry, tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.RtfRead,
  tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout, tyControls.RichEdit.TableSel,
  tyControls.RichEdit, tyControls.RichEdit.Grid, tyControls.RichEdit.Commands, BGRABitmap,
  BGRABitmapTypes, test.richedit.layoutdevice;

type
  TTyRichGridTest = class(TTestCase)
  published
    procedure TestWordsMergedTableGivesTheGridWordShows;
    procedure TestWideCellsAndMergeFlagsAreTheSameGrid;
    procedure TestOpenSaveStaysByteIdentical;
    procedure TestARowShorterThanTheGridHasEmptyPlaces;
    procedure TestEdgesAFewTwipsApartAreOne;
  end;

  TGridRich = class(TTyRichEdit)
  protected
    function CreateDevice: TTyRichTextDevice; override;
  public
    procedure Key(AKey: Word; AShift: TShiftState = []);
    function CursorAtPoint(X, Y: Integer): TCursor;
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
    procedure TestACellThatContinuesAMergeButHoldsTextIsReached;
    procedure TestTheHeightIndexFollowsASpansRows;
    procedure TestARowsEdgeIsNotInsideASpan;
    procedure TestUndoOfAMergeAndASplitGivesTheHeightsBack;
  end;

  { A cell merged over rows laid out (TTyRichLayouter, the test device, no control): its
    content over its rows' joint height - each row as tall as its own cells make it, the last
    row grown by what the merged cell needs more, an exact row not -, placed in that height by
    its vertical alignment; the rows it covers show the rest of it, answer a point in it with
    its positions, and go with it when it changes. }
  TTyRichSpanLayoutTest = class(TTestCase)
  private
    FDoc: TTyRichDocument;
    FLay: TTyRichLayouter;
    procedure Open(const ARtf: RawByteString);
    function Row(APara: Integer; APPI: Integer = 96): TTyRowLayout;
    procedure Changed;
  protected
    procedure TearDown; override;
  published
    procedure TestLayoutOfSpans;
    procedure TestTheJointHeightComesFromThePlainCells;
    procedure TestEachAlignmentInTheJointHeight;
    procedure TestAnExactRowDoesNotGrow;
    procedure TestAPointInACoveredPlaceLandsInTheSpan;
    procedure TestAnEditInASpanLaysOutOnlyItsRows;
    procedure TestANeighbourInAMiddleRowMovesTheCentredContent;
    procedure TestTheCoveredRowShowsTheRestOfTheContent;
    procedure TestALineTwoRowsShareIsDrawnOnce;
    procedure TestASpanOverMoreRowsThanAGroupKeepsItsLook;
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

function TGridRich.CursorAtPoint(X, Y: Integer): TCursor;
begin
  Result := CursorAt(X, Y);
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
  { the covered cell's own place: the span's cell - below its one line, that line at the
    point's x (its start), as in a tall plain cell }
  r := FRich.ParagraphRect(4);
  p := FRich.PositionAtPoint(r.Left + 2, (r.Top + r.Bottom) div 2);
  AssertEquals('in the span''s cell', 1, FRich.Document.Text.ParaOfPos(p));
  AssertEquals('on its last line, at the point''s x', PS(FRich, 1), p);
end;

const
  { x | A over three rows beside cells of six lines | twenty paragraphs after the table: A 1,
    b 2-7, the covered cells 8 and 15, d 9-14, f 16-21, the first after 22. }
  CThree = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\clvmgf\cellx1500\cellx3000\pard\intbl A\cell b\par b\par b\par b\par b\par b\cell\row' +
    '\trowd\clvmrg\cellx1500\cellx3000\pard\intbl\cell d\par d\par d\par d\par d\par d\cell\row' +
    '\trowd\clvmrg\cellx1500\cellx3000\pard\intbl\cell f\par f\par f\par f\par f\par f\cell\row' +
    '\pard p1\par p2\par p3\par p4\par p5\par p6\par p7\par p8\par p9\par p10\par' +
    'p11\par p12\par p13\par p14\par p15\par p16\par p17\par p18\par p19\par p20\par}';

{ Lines typed into a merged cell while its last row is below the view: the height index has
  every row of the span right at once - the content's height, the first paragraph after the
  table where a fresh layout of the same document puts it. }
procedure TTyRichGridControlTest.TestTheHeightIndexFollowsASpansRows;
var
  fresh: TGridRich;
  st: TBytesStream;
  last, after, k: Integer;
  t: TTyRichText;
begin
  FRich.SetBounds(0, 0, 600, 40);
  Load(CThree);
  FRich.ContentHeight;
  { 24 lines more at the merged cell's end (by the document: the view stays at the top, the
    span's last row several views below it, where the view lays nothing out), and the paint
    that follows }
  AssertTrue('typed', FRich.Document.Execute(TTyRichInsertText.Create(PS(FRich, 1) + 1,
    DupeString(#10'a', 24))));
  FRich.UpdateView;
  t := FRich.Document.Text;
  // A 1-25, B 26-31, covered 32, D 33-38, covered 39, F 40-45, after 46
  last := 39;
  after := 46;
  AssertTrue(Format('the last row views below the view (%d)', [t.ParaTop(last)]),
    t.ParaTop(last) > 4 * FRich.Height);
  fresh := TGridRich.Create(nil);
  try
    fresh.Controller := FCtl;
    fresh.Font.PixelsPerInch := 96;
    fresh.SetBounds(0, 0, 600, 40);
    st := TBytesStream.Create;
    try
      FRich.SaveToStream(st, rfRtf);
      st.Position := 0;
      fresh.LoadFromStream(st, rfRtf);
    finally
      st.Free;
    end;
    fresh.FinishLoading;
    fresh.ContentHeight;
    for k := 1 to after do
      AssertEquals(Format('paragraph %d''s height in the index', [k]),
        fresh.Document.Text.ParaHeight(k), t.ParaHeight(k));
    AssertEquals('the content''s height', fresh.ContentHeight, FRich.ContentHeight);
    AssertEquals('the first paragraph after the table', fresh.ParagraphRect(after).Top,
      FRich.ParagraphRect(after).Top);
  finally
    fresh.Free;
  end;
  AssertTrue('the last row grew', t.ParaHeight(last) > t.ParaHeight(33));
end;

{ A row's bottom is an edge to drag only where it is a line: not inside a merged cell (the
  first row's bottom under A), beside it (B's) and under the merged cell's last row it is. }
procedure TTyRichGridControlTest.TestARowsEdgeIsNotInsideASpan;
var
  x0, x1, y, y0, y1: Integer;
begin
  Load(CSpans);
  FRich.UpdateView;
  // (the first two cells' middles - 1500 twips, 100 pixels each: away from their edges)
  x0 := FRich.ParagraphRect(1).Left + 40;
  x1 := x0 + 100;
  // the first row's bottom: the first north-south place under B
  y0 := -1;
  for y := FRich.ParagraphRect(2).Top to FRich.Height - 1 do
    if FRich.CursorAtPoint(x1, y) = crSizeNS then
    begin
      y0 := y;
      Break;
    end;
  AssertTrue('the first row''s bottom beside the span', y0 >= 0);
  AssertTrue('not inside the span', FRich.CursorAtPoint(x0, y0) <> crSizeNS);
  // the next: the span's last row's bottom
  y1 := -1;
  for y := y0 + 8 to FRich.Height - 1 do
    if FRich.CursorAtPoint(x1, y) = crSizeNS then
    begin
      y1 := y;
      Break;
    end;
  AssertTrue('the second row''s bottom', y1 > y0);
  AssertEquals('under the span''s last row: an edge', Ord(crSizeNS), Ord(FRich.CursorAtPoint(x0, y1)));
end;

{ A merge undone gives every row its height back, the table's end its place; so does a split
  undone. }
procedure TTyRichGridControlTest.TestUndoOfAMergeAndASplitGivesTheHeightsBack;
const
  T3 = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\cellx1500\cellx3000\pard\intbl a1\par a2\par a3\cell b\cell\row' +
    '\trowd\cellx1500\cellx3000\pard\intbl c\cell d1\par d2\cell\row' +
    '\pard after\par}';
var
  before, merged, now: TIntegerDynArray;
  i: Integer;

  function Tops: TIntegerDynArray;
  var
    k: Integer;
  begin
    FRich.ContentHeight;
    Result := nil;
    SetLength(Result, FRich.Document.Text.ParaCount);
    for k := 0 to High(Result) do Result[k] := FRich.ParagraphRect(k).Top;
  end;

begin
  Load(T3);
  before := Tops;
  // a1 .. c: the first column of both rows
  FRich.SelStart := PS(FRich, 1);
  FRich.SelLength := PS(FRich, 5) + 1 - PS(FRich, 1);
  AssertTrue('merged', FRich.MergeCells);
  merged := Tops;
  FRich.Undo;
  now := Tops;
  for i := 0 to High(before) do
    AssertEquals(Format('the merge undone: paragraph %d', [i]), before[i], now[i]);
  FRich.Redo;
  FRich.SelStart := PS(FRich, 1);
  AssertTrue('split', FRich.SplitCell(1, 2));
  FRich.Undo;
  now := Tops;
  for i := 0 to High(merged) do
    AssertEquals(Format('the split undone: paragraph %d', [i]), merged[i], now[i]);
end;

{ Word writes one line's cells up to 15 twips apart from row to row: one edge of the grid;
  16 apart, two. }
procedure TTyRichGridTest.TestEdgesAFewTwipsApartAreOne;
const
  Near = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx1000\cellx2000\pard\intbl A\cell B\cell\row' +
    '\trowd\cellx1012\cellx2000\pard\intbl C\cell D\cell\row' +
    '\pard\par}';
  Far = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx1000\cellx2000\pard\intbl A\cell B\cell\row' +
    '\trowd\cellx1016\cellx2000\pard\intbl C\cell D\cell\row' +
    '\pard\par}';
var
  d: TTyRichDocument;
  g: TTyRichGrid;
begin
  d := LoadDoc(BytesOf(Near));
  try
    g := TyRichTableGrid(d, 0);
    try
      AssertEquals('12 twips apart: one edge', 2, g.ColCount);
      AssertEquals('each cell one column', 1, g.CellOf(1, 0).ColSpan);
    finally
      g.Free;
    end;
  finally
    d.Free;
  end;
  d := LoadDoc(BytesOf(Far));
  try
    g := TyRichTableGrid(d, 0);
    try
      AssertEquals('16 apart: two', 3, g.ColCount);
      AssertEquals('the first row''s second cell over two columns', 2, g.CellOf(0, 1).ColSpan);
      AssertTrue('consistent', g.Consistent);
    finally
      g.Free;
    end;
  finally
    d.Free;
  end;
end;

{ A file may put text in a cell that continues a merge down: it is shown, so it is a cell of
  its own - Tab, the arrows and a click reach it. }
procedure TTyRichGridControlTest.TestACellThatContinuesAMergeButHoldsTextIsReached;
const
  Held = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\clvmgf\cellx1500\cellx3000\cellx4500\pard\intbl A\cell B\cell C\cell\row' +
    '\trowd\clvmrg\cellx1500\cellx3000\cellx4500\pard\intbl Z\cell D\cell E\cell\row' +
    '\pard\par}';
var
  r: TRect;
begin
  Load(Held);
  FRich.SelStart := PS(FRich, 3);
  FRich.Key(VK_TAB);
  AssertEquals('Tab: the cell with text', 4, FRich.Document.Text.ParaOfPos(FRich.SelStart));
  FRich.SelStart := PS(FRich, 5);
  FRich.Key(VK_LEFT);
  AssertEquals('Left: into it', 4, ParaOfCaret);
  r := FRich.ParagraphRect(4);
  AssertEquals('a click: there', 4, FRich.Document.Text.ParaOfPos(
    FRich.PositionAtPoint(r.Left + 2, (r.Top + r.Bottom) div 2)));
end;

{ ---- a cell merged over rows, laid out ---- }

const
  { x | A1..A4 over two rows beside B and D | after: paragraphs 0, 1-4, 5 (B), 6 (covered),
    7 (D), 8. }
  CTall = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\clvmgf\cellx1500\cellx3000\pard\intbl A1\par A2\par A3\par A4\cell B\cell\row' +
    '\trowd\clvmrg\cellx1500\cellx3000\pard\intbl \cell D\cell\row' +
    '\pard after\par}';

{ A one-line merged cell (its vertical alignment AAlign) over two rows whose other cells are
  three lines each: paragraphs 0 x, 1 A, 2-4 B, 5 covered, 6-8 D, 9 after. }
function ShortSpan(const AAlign: string): RawByteString;
begin
  Result := '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\clvmgf' + AAlign + '\cellx1500\cellx3000\pard\intbl A\cell B1\par B2\par B3\cell\row' +
    '\trowd\clvmrg' + AAlign + '\cellx1500\cellx3000\pard\intbl \cell D1\par D2\par D3\cell\row' +
    '\pard after\par}';
end;

procedure TTyRichSpanLayoutTest.Open(const ARtf: RawByteString);
begin
  FreeAndNil(FLay);
  FreeAndNil(FDoc);
  FDoc := LoadDoc(BytesOf(ARtf));
  FLay := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
end;

procedure TTyRichSpanLayoutTest.TearDown;
begin
  FreeAndNil(FLay);
  FreeAndNil(FDoc);
end;

// the row paragraph APara is in, laid out (the reference given back: the cache keeps it)
function TTyRichSpanLayoutTest.Row(APara: Integer; APPI: Integer): TTyRowLayout;
var
  b: TTyBlockLayout;
begin
  b := FLay.LayoutBlock(FDoc, APara, 600, APPI, 1.0);
  AssertTrue('a row', b is TTyRowLayout);
  Result := TTyRowLayout(b);
  b.Release;
end;

procedure TTyRichSpanLayoutTest.Changed;
begin
  FLay.DocumentChanged(FDoc.UndoStep.Change);
end;

{ A merged cell's content taller than its rows: the first row as tall as its own cell (B), the
  last grown by what the content needs more; the content over both, its caret below the first
  row's bottom; no grid made. }
procedure TTyRichSpanLayoutTest.TestLayoutOfSpans;
var
  r0, r1: TTyRowLayout;
  need: Integer;
  n: Int64;
  c: TRect;
begin
  n := TyRichGridBuildCount;
  Open(CTall);
  r0 := Row(1);
  r1 := Row(6);
  AssertEquals('the first row: its own cell B', r0.Cells[1].Need, r0.Height);
  need := r0.Cells[0].PadTop + r0.Cells[0].ContentHeight + r0.Cells[0].PadBottom;
  if rcsBottom in r1.Cells[0].Sides then Inc(need, r1.Cells[0].LinePx[rcsBottom]);
  AssertTrue('the content is taller than the first row', need > r0.Height);
  AssertEquals('the last row grown by what it needs more', need - r0.Height, r1.Height);
  AssertTrue('more than its own cell D', r1.Height > r1.Cells[1].Need);
  AssertEquals('the merged cell over both rows', r0.Height + r1.Height, r0.Cells[0].SpanHeight);
  AssertTrue('the row below it covered', r1.Cells[0].Covered);
  // the caret at A4's end: below the first row's bottom, inside the merged cell
  c := r0.CaretRect(r0.Items[3].Pos + 2);
  AssertTrue(Format('the caret in the last line (%d..%d, first row %d)', [c.Top, c.Bottom,
    r0.Height]), (c.Top >= r0.Height) and (c.Bottom <= r0.Cells[0].SpanHeight));
  AssertEquals('no grid made', n, TyRichGridBuildCount);
end;

{ A short merged cell: its rows as tall as their own cells (three lines each), it laid out
  over the two together. }
procedure TTyRichSpanLayoutTest.TestTheJointHeightComesFromThePlainCells;
var
  r0, r1: TTyRowLayout;
begin
  Open(ShortSpan(''));
  r0 := Row(1);
  r1 := Row(5);
  AssertEquals('the first row: B', r0.Cells[1].Need, r0.Height);
  AssertEquals('the second row: D', r1.Cells[1].Need, r1.Height);
  AssertEquals('the joint height', r0.Height + r1.Height, r0.Cells[0].SpanHeight);
  AssertEquals('top: under its padding', r0.Cells[0].PadTop, r0.Items[0].Y);
end;

{ Top, centre, bottom: the offset in the joint height to the pixel, at 100 % and 150 %. }
procedure TTyRichSpanLayoutTest.TestEachAlignmentInTheJointHeight;
const
  Aligns: array[0..2] of string = ('', '\clvertalc', '\clvertalb');
var
  r0, r1: TTyRowLayout;
  a, p, ppi, room, want: Integer;
begin
  for p := 0 to 1 do
    for a := 0 to 2 do
    begin
      if p = 0 then ppi := 96 else ppi := 144;
      Open(ShortSpan(Aligns[a]));
      r0 := Row(1, ppi);
      r1 := Row(5, ppi);
      room := r0.Height + r1.Height - r0.Cells[0].PadTop - r0.Cells[0].PadBottom -
        r0.Cells[0].ContentHeight;
      case a of
        1: want := room div 2;
        2: want := room;
      else
        want := 0;
      end;
      AssertTrue('room to place it in', room > 0);
      AssertEquals(Format('alignment %d at %d PPI', [a, ppi]), r0.Cells[0].PadTop + want,
        r0.Items[0].Y);
    end;
end;

{ An exact last row does not grow: the merged cell's content is cut off at its bottom. }
procedure TTyRichSpanLayoutTest.TestAnExactRowDoesNotGrow;
var
  r0, r1: TTyRowLayout;
begin
  Open('{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\clvmgf\cellx1500\cellx3000\pard\intbl A1\par A2\par A3\par A4\cell B\cell\row' +
    '\trowd\trrh-300\clvmrg\cellx1500\cellx3000\pard\intbl \cell D\cell\row' +
    '\pard after\par}');
  r0 := Row(1);
  r1 := Row(6);
  AssertEquals('exactly its height', TyRichTwipsToPx(300, 96, 1.0), r1.Height);
  AssertEquals('the first row: its own cell', r0.Cells[1].Need, r0.Height);
  AssertTrue('the content more than the rows',
    r0.Cells[0].ContentHeight > r0.Height + r1.Height);
  AssertEquals('the merged cell: the rows'' height', r0.Height + r1.Height, r0.Cells[0].SpanHeight);
end;

{ A point in the covered row's place answers the merged cell's position there - the same the
  first row answers for that height (a position before the covered row's own). }
procedure TTyRichSpanLayoutTest.TestAPointInACoveredPlaceLandsInTheSpan;
var
  r0, r1: TTyRowLayout;
  x, y, got, want: Integer;
  e: Boolean;
begin
  Open(CTall);
  r0 := Row(1);
  r1 := Row(6);
  x := r0.Cells[0].Left + 3;
  for y := 0 to r1.Height - 1 do
  begin
    got := FDoc.Text.ParaStart(6) + r1.PosAtPoint(x, y, e);
    want := FDoc.Text.ParaStart(1) + r0.PosAtPoint(x, r0.Height + y, e);
    AssertEquals(Format('at %d', [y]), want, got);
    AssertTrue('in the merged cell', (FDoc.Text.ParaOfPos(got) >= 1) and
      (FDoc.Text.ParaOfPos(got) <= 4));
  end;
  // below its last line: its last line
  AssertEquals('below the content: the last line', 4, FDoc.Text.ParaOfPos(FDoc.Text.ParaStart(6) +
    r1.PosAtPoint(x, r1.Height - 1, e)));
  // the plain cell beside it is its own
  AssertEquals('D is D', 7, FDoc.Text.ParaOfPos(FDoc.Text.ParaStart(6) +
    r1.PosAtPoint(r1.Cells[1].Left + 3, 2, e)));
end;

{ A key in the merged cell: its rows go (the row below them stays, as the paragraph above),
  and laid out again they take the new content's height. }
procedure TTyRichSpanLayoutTest.TestAnEditInASpanLaysOutOnlyItsRows;
var
  r1: TTyRowLayout;
  h1: Integer;
  b: TTyBlockLayout;
begin
  Open(CTall);
  b := FLay.LayoutBlock(FDoc, 0, 600, 96, 1.0);
  b.Release;
  Row(1);
  r1 := Row(6);
  h1 := r1.Height;
  b := FLay.LayoutBlock(FDoc, 8, 600, 96, 1.0);
  b.Release;
  AssertTrue('a line more in A4', FDoc.Execute(TTyRichInsertText.Create(FDoc.Text.ParaStart(4) + 2,
    #10 + 'A5')));
  Changed;
  AssertNull('the merged cell''s row goes', FLay.CachedLayout(1));
  AssertNull('the row it covers goes too', FLay.CachedLayout(7));
  AssertNotNull('the paragraph above stays', FLay.CachedLayout(0));
  AssertNotNull('the paragraph below stays', FLay.CachedLayout(9));
  r1 := Row(7);
  AssertTrue(Format('the last row taller (%d, was %d)', [r1.Height, h1]), r1.Height > h1);
end;

{ A merged cell over three rows, centred: a line more in the middle row's other cell makes the
  rows taller and moves the merged cell's content down. }
procedure TTyRichSpanLayoutTest.TestANeighbourInAMiddleRowMovesTheCentredContent;
const
  Three = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard x\par' +
    '\trowd\clvmgf\clvertalc\cellx1500\cellx3000\pard\intbl A\cell B\cell\row' +
    '\trowd\clvmrg\clvertalc\cellx1500\cellx3000\pard\intbl \cell D\cell\row' +
    '\trowd\clvmrg\clvertalc\cellx1500\cellx3000\pard\intbl \cell F\cell\row' +
    '\pard after\par}';
var
  y0: Integer;
begin
  Open(Three);
  y0 := Row(1).Items[0].Y;
  // D is paragraph 4
  AssertTrue('a line more in D', FDoc.Execute(TTyRichInsertText.Create(FDoc.Text.ParaStart(4) + 1,
    #10 + 'D2')));
  Changed;
  AssertTrue(Format('the centred content lower (%d, was %d)', [Row(1).Items[0].Y, y0]),
    Row(1).Items[0].Y > y0);
end;

{ The covered row draws the merged cell's lines that fall in it (the test device logs each
  text it draws). }
procedure TTyRichSpanLayoutTest.TestTheCoveredRowShowsTheRestOfTheContent;
var
  r1: TTyRowLayout;
  bmp: TBGRABitmap;
  i, found: Integer;
  st: TTyRichPaintStyle;
  log: TStringList;
begin
  Open(CTall);
  Row(1);
  r1 := Row(6);
  st := TyRichDefaultPaintStyle;
  log := TTyRichTestDevice(FLay.Device).DrawLog;
  log.Clear;
  bmp := TBGRABitmap.Create(600, r1.Height + 20, BGRAWhite);
  try
    r1.Paint(bmp, 0, 10, Rect(0, 0, 600, r1.Height + 20), st, 0, 0);
  finally
    bmp.Free;
  end;
  found := 0;
  for i := 0 to log.Count - 1 do
    if Copy(log[i], 1, 1) = 'A' then Inc(found);
  AssertTrue('a line of the merged cell drawn by the covered row: ' + log.CommaText, found > 0);
  AssertTrue('A1 is the first row''s: not here', Pos('A1|', log.Text) = 0);
end;

{ The rows of a table painted one under the other, as the view stacks them; the ink rows at
  x AX from AY0 to AY1 (not the white ground). }
function InkRun(ALay: TTyRichLayouter; ADoc: TTyRichDocument; const AFirsts: array of Integer;
  APPI, AX, AY0, AY1: Integer): Integer;
var
  bmp: TBGRABitmap;
  y, i: Integer;
  b: TTyBlockLayout;
  st: TTyRichPaintStyle;
  p: TBGRAPixel;
begin
  st := TyRichDefaultPaintStyle;
  bmp := TBGRABitmap.Create(800, 400, BGRAWhite);
  try
    y := 0;
    for i := 0 to High(AFirsts) do
    begin
      b := ALay.LayoutBlock(ADoc, AFirsts[i], 800, APPI, 1.0);
      try
        b.Paint(bmp, 0, y, Rect(0, 0, 800, 400), st, 0, 0);
        Inc(y, b.Height);
      finally
        b.Release;
      end;
    end;
    Result := 0;
    for y := AY0 to AY1 do
    begin
      p := bmp.GetPixel(AX, y);
      if (p.red < 250) or (p.green < 250) or (p.blue < 250) then Inc(Result);
    end;
  finally
    bmp.Free;
  end;
end;

{ Along the edge two rows share, each part two cells really share has one line at one place:
  a cell over three columns above three cells - their tops and its bottom are one line, as
  wide as the same line between two rows of three (one pixel at 100 % and 150 %); a wider
  line on one side wins on the part they share. }
procedure TTyRichSpanLayoutTest.TestALineTwoRowsShareIsDrawnOnce;
const
  B = '\clbrdrt\brdrs\brdrw10\clbrdrl\brdrs\brdrw10\clbrdrb\brdrs\brdrw10\clbrdrr\brdrs\brdrw10';
  Wide30 = '\clbrdrt\brdrs\brdrw10\clbrdrl\brdrs\brdrw10\clbrdrb\brdrs\brdrw30\clbrdrr\brdrs\brdrw10';
  function Doc(const AWideLook: string): RawByteString;
  begin
    Result := '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
      '\trowd' + AWideLook + '\cellx4500\pard\intbl\cell\row' +
      '\trowd' + B + '\cellx1500' + B + '\cellx3000' + B + '\cellx4500\pard\intbl\cell\cell\cell\row' +
      '\trowd' + B + '\cellx1500' + B + '\cellx3000' + B + '\cellx4500\pard\intbl\cell\cell\cell\row' +
      '\pard\par}';
  end;
var
  p, ppi, h0, h1, x, across, plain, wide: Integer;
  r: TTyRowLayout;
begin
  for p := 0 to 1 do
  begin
    if p = 0 then ppi := 96 else ppi := 144;
    Open(Doc(B));
    r := Row(0, ppi);
    h0 := r.Height;
    h1 := Row(1, ppi).Height;
    // the middle of the second column
    x := (Row(1, ppi).Cells[1].Left + Row(1, ppi).Cells[1].Right) div 2;
    across := InkRun(FLay, FDoc, [0, 1, 4], ppi, x, h0 - 4, h0 + 3);
    plain := InkRun(FLay, FDoc, [0, 1, 4], ppi, x, h0 + h1 - 4, h0 + h1 + 3);
    AssertEquals(Format('the wide cell''s edge with three: one line (%d PPI)', [ppi]), plain, across);
    AssertEquals(Format('one pixel (%d PPI)', [ppi]), 1, plain);
    // a wider bottom on the wide cell: it, not both
    Open(Doc(Wide30));
    h0 := Row(0, ppi).Height;
    wide := InkRun(FLay, FDoc, [0, 1, 4], ppi, x, h0 - 6, h0 + 3);
    h1 := TyRichTwipsToPx(30, ppi, 1.0);
    if h1 < 1 then h1 := 1;
    AssertEquals(Format('the wider wins, alone (%d PPI)', [ppi]), h1, wide);
  end;
end;

{ A cell merged over more rows than a group lays out together is laid out row by row: its
  content in its first row (that row as tall as it needs), and still one cell to look at - no
  line inside it, its shading in every row. }
procedure TTyRichSpanLayoutTest.TestASpanOverMoreRowsThanAGroupKeepsItsLook;
const
  Look = '\clcbpat1\clbrdrt\brdrs\brdrw10\clbrdrl\brdrs\brdrw10\clbrdrb\brdrs\brdrw10\clbrdrr\brdrs\brdrw10';
var
  s: RawByteString;
  i, n: Integer;
  r0, r1: TTyRowLayout;
begin
  n := 1100;
  s := '{\rtf1\ansi{\fonttbl{\f0 Arial;}}{\colortbl;\red200\green220\blue255;}\pard x\par';
  for i := 0 to n - 1 do
  begin
    s := s + '\trowd';
    if i = 0 then s := s + '\clvmgf' else s := s + '\clvmrg';
    s := s + Look + '\cellx1500\cellx3000\pard\intbl';
    if i = 0 then s := s + ' A1\par A2\par A3';
    s := s + '\cell b\cell\row';
  end;
  Open(s + '\pard after\par}');
  r0 := Row(1);
  r1 := Row(5);
  AssertEquals('laid out row by row: no joint height', 0, r0.Cells[0].SpanHeight);
  AssertFalse('nothing covered by a slice', r1.Cells[0].Covered);
  AssertTrue('its content in its first row', r0.Height >= r0.Cells[0].Need);
  AssertFalse('no line under the first row inside it', rcsBottom in r0.Cells[0].Sides);
  AssertFalse('none over the second', rcsTop in r1.Cells[0].Sides);
  AssertEquals('its shading in the rows below', r0.Cells[0].Shading, r1.Cells[0].Shading);
  AssertTrue('shaded', r1.Cells[0].Shading <> clNone);
end;

initialization
  RegisterTest(TTyRichGridTest);
  RegisterTest(TTyRichGridControlTest);
  RegisterTest(TTyRichSpanLayoutTest);
end.
