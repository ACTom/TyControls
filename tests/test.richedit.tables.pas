unit test.richedit.tables;

{ The table commands of TTyRichEdit's document (tyControls.RichEdit.Commands: insert a table,
  insert and delete rows and columns): where a table goes and how it looks, before and after
  a save, here and in the system's RichEdit; what a new row or column takes from the one
  beside it; refusals for tables whose structure cannot change; undo that gives back every
  paragraph's very cell, and redo; the bytes a save keeps; the layout after an edit; tables a
  reader that parses on demand gives in parts; and the other ways of changing a table that
  must go on working on one a command changed. No control, no window. The unit is ASCII:
  Chinese text is built from code points. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit.Layout, tyControls.RichEdit.Find, test.richedit.layoutdevice,
  test.richedit.msftedit;

type
  TTyRichTablesTest = class(TTestCase)
  published
    // making a table
    procedure TestInsertTablePlacesTheTable;
    procedure TestInsertTableWidthsAndBounds;
    procedure TestANewTableHasBordersBeforeAndAfterASave;
    procedure TestANewTablesCellsTakeTheFormatsInEffect;
    procedure TestTheRtfOfANewTable;
    // rows
    procedure TestInsertRowAtEachPlace;
    procedure TestInsertRowBesideCellsOfSeveralParagraphs;
    procedure TestDeleteEachRowOfEachTable;
    procedure TestDeletingTheLastRowRemovesTheTable;
    // columns
    procedure TestColumnsAtEachPlace;
    procedure TestDeletingTheOnlyColumnRemovesTheTable;
    procedure TestIrregularRowsRefuseColumns;
    procedure TestARowFormatKeepsItsCellWords;
    procedure TestSplittingRowFormats;
    // refusals
    procedure TestLockedTableRefusesStructureChanges;
    procedure TestADocumentThatLoadsOrSavesRefuses;
    // what the table has after an edit
    procedure TestRowsAPlainDeleteLeftAreNotTakenAlong;
    procedure TestACellWithNoParagraphGetsOne;
    // tables a reader that parses on demand gives in parts
    procedure TestATableCutByTheLoaderIsEditedWhole;
    procedure TestABigTableCutByTheLoaderIsRefused;
    // undo, redo, memory, bytes, layout
    procedure TestEachCommandUndoesAndRedoesExactly;
    procedure TestAStepHoldsNothingOfTheTextAround;
    procedure TestUntouchedRowsKeepTheirBytes;
    procedure TestTheLayoutFollowsARowEdit;
    procedure TestARowEditVisitsTheTableOnly;
    // the other ways of changing a table, on one a command changed
    procedure TestOtherPathsOnAChangedTable;
    procedure TestChineseTextSurvivesEveryEdit;
    procedure TestTheReadersForAView;
    procedure TestWrittenTablesOpenInWindowsRichEdit;
    // the row below a row, and what a row edit leaves laid out
    procedure TestTheNewLastRowAfterAPlainDeleteClosesTheTable;
    procedure TestTheRowBelowIsTheNextRowThatHasParagraphs;
    procedure TestTheLayoutFollowsARowEditAfterAPlainDelete;
    // costs and what a step keeps
    procedure TestEditsAreLinearInTheTable;
    procedure TestATableStepCountsWhatItKeeps;
    procedure TestASourceOnlyWhereAFileIs;
    procedure TestTableEditsLetGoOfEveryValue;
    procedure TestTheTableCommandCountsItsTable;
    // formats
    procedure TestAColumnOfARowFormatThatCannotBeSplit;
    procedure TestTheParagraphBetweenTwoTablesIsNoListItem;
    procedure TestANewRowDoesNotRepeatTheRowNumbering;
    procedure TestNarrowCellsGetASmallerGap;
    // the paths left
    procedure TestANeighbourPartWithNoUnreadParagraphIsNotWhole;
    procedure TestALoadersRangeWithAParagraphOutsideATable;
    procedure TestARowWithTheTablesEdges;
    // a row named by a position
    procedure TestARowBesideTheRowOfAPosition;
  end;

implementation

{ ---- helpers ---- }

function U(ACode: Cardinal): UTF8String;
begin
  Result := '';
  if ACode < $80 then
    Result := AnsiChar(ACode)
  else if ACode < $800 then
  begin
    SetLength(Result, 2);
    Result[1] := AnsiChar($C0 or (ACode shr 6));
    Result[2] := AnsiChar($80 or (ACode and $3F));
  end
  else
  begin
    SetLength(Result, 3);
    Result[1] := AnsiChar($E0 or (ACode shr 12));
    Result[2] := AnsiChar($80 or ((ACode shr 6) and $3F));
    Result[3] := AnsiChar($80 or (ACode and $3F));
  end;
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOf(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
  SetCodePage(Result, CP_NONE, False);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

// The bytes as text for a message (a code page of no text would show as nothing).
function Txt(const R: RawByteString): string;
var
  s: RawByteString;
begin
  s := R;
  UniqueString(s);
  SetCodePage(s, CP_UTF8, False);
  Result := s;
end;

function SameRaw(const A, B: RawByteString): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[1], @B[1], Length(A)));
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

function LoadDoc(const ABytes: TBytes; AFull: Boolean = False): TTyRichDocument;
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

function SaveBytes(ADoc: TTyRichDocument; out AInfo: TTyRtfWriteInfo): TBytes; overload;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveRtf(ADoc, s, AInfo);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

function SaveBytes(ADoc: TTyRichDocument): TBytes; overload;
var
  info: TTyRtfWriteInfo;
begin
  Result := SaveBytes(ADoc, info);
end;

function NewDoc(const AText: UTF8String): TTyRichDocument;
begin
  Result := TTyRichDocument.CreateFromUtf8(BytesOf(AText));
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): UTF8String;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
end;

function FirstTablePara(ADoc: TTyRichDocument): Integer;
begin
  for Result := 0 to ADoc.Text.ParaCount - 1 do
    if ADoc.CellAt(Result) <> nil then Exit;
  Result := -1;
end;

function TablePos(ADoc: TTyRichDocument): TTyRichPos;
begin
  Result := ADoc.Text.ParaStart(FirstTablePara(ADoc));
end;

{ The table paragraph APara is in (the paragraphs TableInfoAt names), as text: rows - runs of
  paragraphs of one row object - parted by '/', a row's cells by '|' (a cell with no
  paragraph is '#'), a cell's paragraphs by '+'. '' outside a table. }
function TableShape(ADoc: TTyRichDocument; APara: Integer): string;
var
  info: TTyRichTableInfo;
  k, e, ci, j: Integer;
  row: TTyRichRow;
  first: Boolean;
begin
  Result := '';
  if not ADoc.TableInfoAt(APara, info) then Exit;
  ADoc.BeginRead;
  try
    k := info.First;
    while k <= info.Last do
    begin
      row := ADoc.CellAt(k).Row;
      e := k;
      while (e < info.Last) and (ADoc.CellAt(e + 1).Row = row) do Inc(e);
      if k > info.First then Result := Result + '/';
      for ci := 0 to row.CellCount - 1 do
      begin
        if ci > 0 then Result := Result + '|';
        first := True;
        for j := k to e do
          if ADoc.CellAt(j).Index = ci then
          begin
            if not first then Result := Result + '+';
            Result := Result + ParaText(ADoc, j);
            first := False;
          end;
        if first then Result := Result + '#';
      end;
      k := e + 1;
    end;
  finally
    ADoc.EndRead;
  end;
end;

{ Every paragraph: its text, formats, runs and objects, and in a table its cell: the table
  object, the row's index in it, the cell's in the row. }
function Dump(ADoc: TTyRichDocument): string;
var
  i, j: Integer;
  c: TTyRichCell;
  r: TTyRunArray;
begin
  Result := '';
  ADoc.BeginRead;
  try
    for i := 0 to ADoc.Text.ParaCount - 1 do
    begin
      c := ADoc.CellAt(i);
      Result := Result + Format('[%s] P%d {', [ParaText(ADoc, i), ADoc.ParaFormatOf(i)]);
      r := ADoc.RunsOf(i);
      for j := 0 to High(r) do
      begin
        Result := Result + Format(' %d:%d', [r[j].Start, r[j].Format]);
        if r[j].Obj <> nil then Result := Result + '@' + IntToHex(PtrUInt(r[j].Obj), 1);
      end;
      Result := Result + '}';
      if c <> nil then
        Result := Result + Format(' T%s R%d C%d', [IntToHex(PtrUInt(c.Table), 1), c.Row.Index,
          c.Index]);
      Result := Result + LineEnding;
    end;
  finally
    ADoc.EndRead;
  end;
end;

procedure Fill(ADoc: TTyRichDocument; ATablePara, ARow, ACell: Integer; const AText: UTF8String);
var
  f, l: Integer;
begin
  if not ADoc.TableCellParas(ATablePara, ARow, ACell, f, l) then
    raise Exception.CreateFmt('no cell %d, %d', [ARow, ACell]);
  if not ADoc.Execute(TTyRichInsertText.Create(ADoc.Text.ParaStart(f), AText,
    TyRichInheritFormat, False)) then
    raise Exception.Create('the cell refused its text');
end;

{ 'before', an ARows x ACols table with 'rNcM' in each cell, 'after'; no history. }
function TableDoc(ARows, ACols: Integer; const AText: UTF8String = ''): TTyRichDocument;
var
  r, c: Integer;
begin
  Result := NewDoc('before' + #13#10 + 'after');
  if not Result.Execute(TTyRichInsertTable.Create(Result.Text.ParaStart(1), ARows, ACols)) then
    raise Exception.Create('no table');
  for r := 0 to ARows - 1 do
    for c := 0 to ACols - 1 do
      Fill(Result, 1, r, c, Format('r%dc%d', [r, c]) + AText);
  Result.ClearUndo;
end;

function RowEdgesOf(ARow: TTyRichRow): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ARow.BoundaryCount - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(ARow.Boundaries[i]);
  end;
end;

{ The table object of APara has exactly the rows that have paragraphs, in order, and every
  cell of each at least one paragraph; the text's indexes are whole. }
procedure CheckClean(const AMsg: string; ADoc: TTyRichDocument; APara: Integer);
var
  info: TTyRichTableInfo;
  r, k, e, ci: Integer;
  t: TTyRichTable;
  row: TTyRichRow;
  seen: array of Boolean;
begin
  TAssert.AssertEquals(AMsg + ': the text''s integrity', '', ADoc.Text.CheckIntegrity);
  if not ADoc.TableInfoAt(APara, info) then Exit;
  // (one walk of the table's paragraphs, by the cells themselves)
  ADoc.BeginRead;
  try
    t := ADoc.TableAt(APara);
    TAssert.AssertEquals(AMsg + ': the table object''s rows are those with paragraphs',
      info.RowCount, t.RowCount);
    k := info.First;
    r := 0;
    while k <= info.Last do
    begin
      row := ADoc.CellAt(k).Row;
      TAssert.AssertTrue(AMsg + Format(': row %d is the table''s row %d', [r, r]),
        (row.Table = t) and (row.Index = r));
      seen := nil;
      SetLength(seen, row.CellCount);
      e := k;
      while (e <= info.Last) and (ADoc.CellAt(e).Row = row) do
      begin
        seen[ADoc.CellAt(e).Index] := True;
        Inc(e);
      end;
      for ci := 0 to High(seen) do
        TAssert.AssertTrue(AMsg + Format(': cell %d, %d has a paragraph', [r, ci]), seen[ci]);
      k := e;
      Inc(r);
    end;
    TAssert.AssertEquals(AMsg + ': rows', info.RowCount, r);
  finally
    ADoc.EndRead;
  end;
end;

function Exec(ADoc: TTyRichDocument; ACmd: TTyRichCommand): Boolean;
begin
  Result := ADoc.Execute(ACmd);
end;

function Refusal(ADoc: TTyRichDocument; AKind: TTyRichTableEditKind; APos: TTyRichPos;
  AIndex: Integer): TTyRichTableRefusal;
begin
  Result := ADoc.TableEditRefusal(TyRichTableEdit(AKind, APos, AIndex, 2, 2));
end;

function TableCommand(AKind: TTyRichTableEditKind; APos: TTyRichPos;
  AIndex: Integer): TTyRichCommand;
begin
  case AKind of
    rtkInsertTable: Result := TTyRichInsertTable.Create(APos, 2, 2);
    rtkInsertRow: Result := TTyRichInsertRow.Create(APos, AIndex);
    rtkDeleteRow: Result := TTyRichDeleteRow.Create(APos, AIndex);
    rtkInsertColumn: Result := TTyRichInsertColumn.Create(APos, AIndex);
  else
    Result := TTyRichDeleteColumn.Create(APos, AIndex);
  end;
end;

{ The texts of each row's cells after an edit, from the texts before. }
function ShapeWithoutRow(const AShape: string; ARow: Integer): string;
var
  rows: TStringList;
begin
  rows := TStringList.Create;
  try
    rows.Delimiter := '/';
    rows.StrictDelimiter := True;
    rows.DelimitedText := AShape;
    rows.Delete(ARow);
    Result := rows.DelimitedText;
  finally
    rows.Free;
  end;
end;

function MapRows(const AShape: string; AInsert: Boolean; AIndex: Integer): string;
var
  rows, cells: TStringList;
  r: Integer;
begin
  rows := TStringList.Create;
  cells := TStringList.Create;
  try
    rows.Delimiter := '/';
    rows.StrictDelimiter := True;
    rows.DelimitedText := AShape;
    cells.Delimiter := '|';
    cells.StrictDelimiter := True;
    for r := 0 to rows.Count - 1 do
    begin
      cells.DelimitedText := rows[r];
      if AInsert then cells.Insert(AIndex, '') else cells.Delete(AIndex);
      rows[r] := cells.DelimitedText;
    end;
    Result := rows.DelimitedText;
  finally
    cells.Free;
    rows.Free;
  end;
end;

function Layouter: TTyRichLayouter;
begin
  Result := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
end;

{ The boxes of the row block paragraph APara is in: each cell's left, right, sides and line
  widths (not the height: a file read back names its own default font). }
function RowBoxes(ALayouter: TTyRichLayouter; ADoc: TTyRichDocument; APara: Integer): string;
var
  b: TTyBlockLayout;
  row: TTyRowLayout;
  i: Integer;
  s: TTyRowCellSide;
  box: TTyRichCellBox;
begin
  Result := '';
  b := ALayouter.LayoutBlock(ADoc, APara, 600, 96, 1.0);
  try
    TAssert.AssertTrue('a row', b is TTyRowLayout);
    row := TTyRowLayout(b);
    for i := 0 to row.CellCount - 1 do
    begin
      box := row.Cells[i];
      Result := Result + Format('[%d..%d', [box.Left, box.Right]);
      for s := Low(TTyRowCellSide) to High(TTyRowCellSide) do
        if s in box.Sides then Result := Result + Format(' %d:%d', [Ord(s), box.LinePx[s]]);
      Result := Result + ']';
    end;
  finally
    b.Release;
  end;
end;

{ The texts of a document's paragraphs, each with whether it is in a table and its cell's
  index: what a save and a read back must give again. }
function Contents(ADoc: TTyRichDocument): string;
var
  i: Integer;
  c: TTyRichCell;
begin
  Result := '';
  ADoc.BeginRead;
  try
    for i := 0 to ADoc.Text.ParaCount - 1 do
    begin
      c := ADoc.CellAt(i);
      Result := Result + ParaText(ADoc, i);
      if c <> nil then Result := Result + Format('<%d/%d>', [c.Index, c.Row.CellCount]);
      Result := Result + LineEnding;
    end;
  finally
    ADoc.EndRead;
  end;
end;

// The document saved and read back has the same paragraphs, cells and rows.
procedure CheckReadBack(const AMsg: string; ADoc: TTyRichDocument);
var
  d: TTyRichDocument;
  k: Integer;
begin
  d := LoadDoc(SaveBytes(ADoc));
  try
    TAssert.AssertEquals(AMsg + ': read back', Contents(ADoc), Contents(d));
    k := FirstTablePara(ADoc);
    if k >= 0 then
      TAssert.AssertEquals(AMsg + ': its table read back', TableShape(ADoc, k), TableShape(d, k));
  finally
    d.Free;
  end;
end;

// The system's RichEdit reads the cells' texts of a save in order, with the same row and
// cell ends.
procedure CheckRichEdit(const AMsg: string; ADoc: TTyRichDocument);
{$IFDEF WINDOWS}
var
  got: RawByteString;
begin
  if not RichEditText(SaveBytes(ADoc), got) then Exit;
  TAssert.AssertTrue(AMsg + ': what RichEdit reads', SameRaw(ModelAsRichEditText(ADoc), got));
end;
{$ELSE}
begin
end;
{$ENDIF}

{ ---- making a table ---- }

procedure TTyRichTablesTest.TestInsertTablePlacesTheTable;
var
  d: TTyRichDocument;
  before: string;
  i: Integer;
begin
  // at a paragraph's start: before it
  d := NewDoc('one' + #13#10 + 'two');
  try
    before := Dump(d);
    AssertTrue('at a start', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(1), 2, 2)));
    AssertEquals('paragraphs', 6, d.Text.ParaCount);
    AssertEquals('the one before', 'one', ParaText(d, 0));
    AssertTrue('the one before stays out', d.CellAt(0) = nil);
    for i := 1 to 4 do AssertTrue(Format('cell paragraph %d', [i]), d.CellAt(i) <> nil);
    AssertEquals('the paragraph follows the table', 'two', ParaText(d, 5));
    AssertTrue('and is in no table', d.CellAt(5) = nil);
    AssertEquals('the shape', '|/|', TableShape(d, 1));
    CheckClean('at a start', d, 1);
    // right after a table: a paragraph in no table between the two
    AssertTrue('after a table', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(5), 1, 1)));
    AssertEquals('paragraphs with the one between', 8, d.Text.ParaCount);
    AssertTrue('the one between is in no table', d.CellAt(5) = nil);
    AssertEquals('the one between is empty', '', ParaText(d, 5));
    AssertTrue('the second table', (d.CellAt(6) <> nil) and (d.CellAt(6).Table <> d.CellAt(4).Table));
    AssertEquals('the text after both', 'two', ParaText(d, 7));
    d.Undo;
    d.Undo;
    AssertEquals('both undone', before, Dump(d));
  finally
    d.Free;
  end;
  // in the middle: split, the table between the halves
  d := NewDoc('abcd');
  try
    AssertTrue('in the middle', Exec(d, TTyRichInsertTable.Create(2, 1, 2)));
    AssertEquals('paragraphs', 4, d.Text.ParaCount);
    AssertEquals('first half', 'ab', ParaText(d, 0));
    AssertEquals('second half', 'cd', ParaText(d, 3));
    AssertTrue('halves outside', (d.CellAt(0) = nil) and (d.CellAt(3) = nil));
    AssertEquals('one row of two', '|', TableShape(d, 1));
  finally
    d.Free;
  end;
  // at the text's end: the last paragraph stays in front, one follows
  d := NewDoc('abcd');
  try
    AssertTrue('at the end', Exec(d, TTyRichInsertTable.Create(4, 1, 1)));
    AssertEquals('paragraphs', 3, d.Text.ParaCount);
    AssertEquals('the last stays in front', 'abcd', ParaText(d, 0));
    AssertTrue('a cell', d.CellAt(1) <> nil);
    AssertTrue('a paragraph follows, in no table', d.CellAt(2) = nil);
    AssertEquals('it is empty', '', ParaText(d, 2));
  finally
    d.Free;
  end;
  // at the end of an empty last paragraph: before it
  d := NewDoc('ab' + #13#10);
  try
    AssertTrue('at an empty last paragraph', Exec(d, TTyRichInsertTable.Create(d.Text.Length, 1, 1)));
    AssertEquals('paragraphs', 3, d.Text.ParaCount);
    AssertTrue('the cell', d.CellAt(1) <> nil);
    AssertTrue('the empty one follows', (d.CellAt(2) = nil) and (ParaText(d, 2) = ''));
    // in a table: refused, nothing changes
    before := Dump(d);
    AssertTrue('in a table: refused', Refusal(d, rtkInsertTable, d.Text.ParaStart(1), 0) = rtrInTable);
    AssertFalse('in a table: not executed', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(1), 1, 1)));
    AssertEquals('in a table: nothing changed', before, Dump(d));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestInsertTableWidthsAndBounds;
var
  d: TTyRichDocument;
  w: Integer;
  t: TTyRichTable;
begin
  d := NewDoc('x');
  try
    // the document's text width is the one a page-wide layout wraps at
    w := d.TextWidthTwips;
    AssertEquals('the text width is the page layout''s', TyRichLayoutWidth(rwmPage, 0, d, 1440, 1.0), w);
    AssertTrue('a width', w > 1000);
    AssertTrue('three columns', Exec(d, TTyRichInsertTable.Create(0, 2, 3)));
    t := d.TableAt(0);
    AssertEquals('equal columns over the text width', Format('%d,%d,%d', [w div 3, w * 2 div 3, w]),
      RowEdgesOf(t.Rows[0]));
    AssertEquals('every row', RowEdgesOf(t.Rows[0]), RowEdgesOf(t.Rows[1]));
    AssertTrue('the row''s format is the grid''s', SameRaw(TyRtfGridRowFormat([w div 3, w * 2 div 3, w]),
      t.Rows[1].RawFormat));
  finally
    d.Free;
  end;
  d := NewDoc('x');
  try
    AssertTrue('a width of its own', Exec(d, TTyRichInsertTable.Create(0, 1, 3, 5000)));
    AssertEquals('the last edge at the width', '1666,3333,5000', RowEdgesOf(d.TableAt(0).Rows[0]));
    AssertTrue('0 rows', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable, 0, 0, 0, 2)) = rtrOutOfRange);
    AssertTrue('0 columns', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable, 0, 0, 2, 0)) = rtrOutOfRange);
    AssertTrue('64 columns', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable, d.Text.Length, 0, 1, 64)) = rtrOutOfRange);
    AssertTrue('63 columns', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable, d.Text.Length, 0, 1, 63)) = rtrNone);
    AssertTrue('32768 rows', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable, d.Text.Length, 0, 32768, 1)) = rtrOutOfRange);
    AssertTrue('32767 rows', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable, d.Text.Length, 0, 32767, 1)) = rtrNone);
    AssertTrue('a width below a twip a column', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable,
      d.Text.Length, 0, 1, 3, 2)) = rtrOutOfRange);
    AssertTrue('a negative width', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable,
      d.Text.Length, 0, 1, 3, -1)) = rtrOutOfRange);
    AssertTrue('a position past the text', d.TableEditRefusal(TyRichTableEdit(rtkInsertTable,
      d.Text.Length + 1, 0, 1, 1)) = rtrOutOfRange);
    AssertFalse('refused: not executed', Exec(d, TTyRichInsertTable.Create(d.Text.Length, 1, 64)));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestANewTableHasBordersBeforeAndAfterASave;
var
  d, back: TTyRichDocument;
  lo: TTyRichLayouter;
  shown, again, raw: string;
  out_: RawByteString;
  r: Integer;
begin
  d := NewDoc('x');
  lo := Layouter;
  try
    AssertTrue('a table', Exec(d, TTyRichInsertTable.Create(0, 2, 2)));
    Fill(d, 0, 0, 0, 'a');
    Fill(d, 0, 1, 1, 'b');
    shown := RowBoxes(lo, d, 0) + RowBoxes(lo, d, 2);
    // every cell has its left and top line; the last cell its right, the last row its bottom
    AssertTrue('lines on every side: ' + shown, Pos('0:1 1:1]', shown) > 0);
    AssertTrue('the right line', Pos('2:1', shown) > 0);
    AssertTrue('the bottom line', Pos('3:1', shown) > 0);
    out_ := StrOf(SaveBytes(d));
    raw := d.TableAt(0).Rows[0].RawFormat;
    AssertTrue('the row is written with cell borders', Pos(raw, out_) > 0);
    AssertTrue('as Word writes its grid',
      Pos('\clbrdrt\brdrs\brdrw10 \clbrdrl\brdrs\brdrw10 \clbrdrb\brdrs\brdrw10 \clbrdrr\brdrs\brdrw10 \cellx', raw) > 0);
    back := LoadDoc(BytesOf(out_));
    try
      for r := 0 to 1 do
        AssertTrue('read back: the row format is the same bytes', SameRaw(raw,
          back.CellAt(FirstTablePara(back) + 2 * r).Row.RawFormat));
      again := RowBoxes(lo, back, FirstTablePara(back)) + RowBoxes(lo, back, FirstTablePara(back) + 2);
      AssertEquals('the cells look the same after a save and a read', shown, again);
    finally
      back.Free;
    end;
  finally
    lo.Free;
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestANewTablesCellsTakeTheFormatsInEffect;
var
  d: TTyRichDocument;
  p: TTyParaFormat;
  f: TTyCharFormat;
  bold: TTyCharFormatId;
  got: TTyParaFormat;
  k: Integer;
begin
  d := NewDoc('abcd');
  try
    p := TyDefaultParaFormat;
    p.Align := paraCenter;
    p.LeftIndent := 720;
    p.FirstIndent := -360;
    p.RightIndent := 200;
    p.List.Kind := lkBullet;
    p.SpaceAfter := 120;
    AssertTrue('a format', Exec(d, TTyRichSetParaFormat.Create(0, 0, [pffAlign, pffLeftIndent,
      pffFirstIndent, pffRightIndent, pffList, pffSpaceAfter], p)));
    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    AssertTrue('bold', Exec(d, TTyRichSetCharFormat.Create(TyRichRange(0, 2), [cffBold], f)));
    bold := d.TypingFormatAt(2);
    AssertTrue('a table', Exec(d, TTyRichInsertTable.Create(2, 1, 2)));
    for k := 1 to 2 do
    begin
      got := d.Formats.ParaFormat(d.ParaFormatOf(k));
      AssertTrue('the alignment in effect', got.Align = paraCenter);
      AssertEquals('the spacing in effect', 120, got.SpaceAfter);
      AssertTrue('no list', got.List.Kind = lkNone);
      AssertEquals('no left indent', 0, got.LeftIndent);
      AssertEquals('no first indent', 0, got.FirstIndent);
      AssertEquals('no right indent', 0, got.RightIndent);
      AssertEquals('the character format typing there gets', bold, d.RunsOf(k)[0].Format);
      AssertEquals('one empty paragraph', '', ParaText(d, k));
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestTheRtfOfANewTable;
const
  Grid = '\trowd\trgaph108\clbrdrt\brdrs\brdrw10 \clbrdrl\brdrs\brdrw10 \clbrdrb\brdrs\brdrw10 ' +
    '\clbrdrr\brdrs\brdrw10 \cellx2000\clbrdrt\brdrs\brdrw10 \clbrdrl\brdrs\brdrw10 ' +
    '\clbrdrb\brdrs\brdrw10 \clbrdrr\brdrs\brdrw10 \cellx4000';
var
  d: TTyRichDocument;
  o, got: RawByteString;
  a, b: Integer;
begin
  d := NewDoc('x');
  try
    AssertTrue('a 2 x 2 table', Exec(d, TTyRichInsertTable.Create(0, 2, 2, 4000)));
    Fill(d, 0, 0, 0, 'a');
    Fill(d, 0, 0, 1, 'b');
    Fill(d, 0, 1, 0, 'c');
    Fill(d, 0, 1, 1, 'd');
    o := StrOf(SaveBytes(d));
    a := Pos('\trowd', o);
    b := Pos('\row', Copy(o, Pos('d\cell', o), MaxInt)) + Pos('d\cell', o) - 1;
    AssertTrue('a row', (a > 0) and (b > a));
    // each row's own format, then its cells; the paragraph after the table outside it
    got := Copy(o, a, b + 4 - a);
    SetCodePage(got, CP_UTF8, False);
    AssertEquals('the rows as written', Grid + '\pard\intbl\plain a\cell b\cell\row' + #13#10 +
      Grid + '\pard\intbl c\cell d\cell\row', got);
    AssertTrue('then the paragraph after it', Pos('\row' + #13#10 + '\pard x\par', o) > 0);
  finally
    d.Free;
  end;
end;

{ ---- rows ---- }

procedure TTyRichTablesTest.TestInsertRowAtEachPlace;
var
  d: TTyRichDocument;
  i, f, l, besideOld, besideNew: Integer;
  shape, before: string;
  rows: TStringList;
  p: TTyParaFormat;
  right: TTyParaFormatId;
  t: TTyRichTable;
begin
  for i := 0 to 3 do
  begin
    d := TableDoc(3, 2);
    try
      shape := TableShape(d, 1);
      before := Dump(d);
      // the first cell of the row beside the new one is right-aligned
      p := TyDefaultParaFormat;
      p.Align := paraRight;
      // (the row above it, or for the first the row below it)
      if i > 0 then besideOld := i - 1 else besideOld := 0;
      if i > 0 then besideNew := i - 1 else besideNew := 1;
      d.TableCellParas(1, besideOld, 1, f, l);
      AssertTrue('a format', Exec(d, TTyRichSetParaFormat.Create(f, f, [pffAlign], p)));
      right := d.ParaFormatOf(f);
      d.ClearUndo;
      before := Dump(d);
      AssertTrue(Format('insert row %d', [i]), Exec(d, TTyRichInsertRow.Create(TablePos(d), i)));
      rows := TStringList.Create;
      try
        rows.Delimiter := '/';
        rows.StrictDelimiter := True;
        rows.DelimitedText := shape;
        rows.Insert(i, '|');
        AssertEquals(Format('row %d: the shape', [i]), rows.DelimitedText, TableShape(d, 1));
      finally
        rows.Free;
      end;
      CheckClean(Format('row %d', [i]), d, 1);
      t := d.TableAt(1);
      AssertEquals(Format('row %d: the edges of the row beside it', [i]),
        RowEdgesOf(t.Rows[besideNew]), RowEdgesOf(t.Rows[i]));
      AssertTrue(Format('row %d: the format of the row beside it', [i]),
        SameRaw(t.Rows[besideNew].RawFormat, t.Rows[i].RawFormat));
      d.TableCellParas(1, i, 1, f, l);
      AssertEquals(Format('row %d: the new cell is formatted like the cell beside it', [i]),
        right, d.ParaFormatOf(f));
      d.TableCellParas(1, i, 0, f, l);
      AssertTrue(Format('row %d: and the other like its own', [i]), d.ParaFormatOf(f) <> right);
      CheckReadBack(Format('row %d', [i]), d);
      d.Undo;
      AssertEquals(Format('row %d: undone', [i]), before, Dump(d));
    finally
      d.Free;
    end;
  end;
end;

procedure TTyRichTablesTest.TestInsertRowBesideCellsOfSeveralParagraphs;
var
  d: TTyRichDocument;
  f, l: Integer;
begin
  d := TableDoc(2, 2);
  try
    // Enter in cell 0, 0 and in cell 1, 1: two paragraphs each
    d.TableCellParas(1, 0, 0, f, l);
    AssertTrue('enter', Exec(d, TTyRichInsertText.Create(d.Text.ParaStart(f) + 4, #13#10 + 'x')));
    d.TableCellParas(1, 1, 1, f, l);
    AssertTrue('enter', Exec(d, TTyRichInsertText.Create(d.Text.ParaStart(f) + 4, #13#10 + 'y')));
    AssertEquals('two paragraphs in a cell', 'r0c0+x|r0c1/r1c0|r1c1+y', TableShape(d, 1));
    AssertTrue('between', Exec(d, TTyRichInsertRow.Create(TablePos(d), 1)));
    AssertEquals('one paragraph a new cell', 'r0c0+x|r0c1/|/r1c0|r1c1+y', TableShape(d, 1));
    CheckClean('between', d, 1);
    AssertTrue('after the last', Exec(d, TTyRichInsertRow.Create(TablePos(d), 3)));
    AssertEquals('after the last', 'r0c0+x|r0c1/|/r1c0|r1c1+y/|', TableShape(d, 1));
    CheckClean('after the last', d, 1);
    CheckReadBack('cells of two paragraphs', d);
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestDeleteEachRowOfEachTable;
const
  Names: array[0..2] of string = ('re-zh-table.rtf', 'wp-zh-table.rtf', '');
var
  n, r, r2, k, f, l, f2, l2, rowCount: Integer;
  b, o: TBytes;
  d: TTyRichDocument;
  shape, want, msg: string;
  rows: TStringList;
  info: TTyRichTableInfo;

  function Open: TTyRichDocument;
  begin
    if Names[n] = '' then Result := TableDoc(3, 3) else Result := LoadDoc(b);
  end;

begin
  for n := 0 to High(Names) do
  begin
    if Names[n] <> '' then b := FixtureBytes(Names[n]);
    d := Open;
    try
      shape := TableShape(d, FirstTablePara(d));
      d.TableInfoAt(FirstTablePara(d), info);
      rowCount := info.RowCount;
    finally
      d.Free;
    end;
    for r := 0 to rowCount - 1 do
    begin
      msg := Format('%s row %d', [Names[n], r]);
      want := ShapeWithoutRow(shape, r);
      // the command
      d := Open;
      try
        o := SaveBytes(d);
        AssertTrue(msg + ': deleted', Exec(d, TTyRichDeleteRow.Create(TablePos(d), r)));
        AssertEquals(msg + ': the rows left', want, TableShape(d, FirstTablePara(d)));
        CheckClean(msg, d, FirstTablePara(d));
        CheckReadBack(msg, d);
        CheckRichEdit(msg, d);
        d.Undo;
        AssertTrue(msg + ': undone, saved, the file', SameBytes(o, SaveBytes(d)));
      finally
        d.Free;
      end;
      // the plain delete of the row's paragraphs
      d := Open;
      try
        k := FirstTablePara(d);
        d.TableCellParas(k, r, 0, f, l);
        d.TableInfoAt(f, info);
        AssertTrue(msg + ': a plain delete', Exec(d, TTyRichDelete.Create(d.Text.ParaStart(info.RowFirst),
          d.Text.ParaStart(info.RowLast + 1) - d.Text.ParaStart(info.RowFirst))));
        AssertEquals(msg + ': a plain delete: the rows left', want, TableShape(d, FirstTablePara(d)));
        CheckReadBack(msg + ' (a plain delete)', d);
        CheckRichEdit(msg + ' (a plain delete)', d);
      finally
        d.Free;
      end;
      // runs of rows: from this row to each later one
      for r2 := r + 1 to rowCount - 1 do
      begin
        rows := TStringList.Create;
        d := Open;
        try
          rows.Delimiter := '/';
          rows.StrictDelimiter := True;
          rows.DelimitedText := shape;
          for k := r2 downto r do rows.Delete(k);
          k := FirstTablePara(d);
          d.TableCellParas(k, r, 0, f, l);
          d.TableCellParas(k, r2, 0, f2, l2);
          d.TableInfoAt(f2, info);
          AssertTrue(msg + ': a run of rows', Exec(d, TTyRichDelete.Create(d.Text.ParaStart(f),
            d.Text.ParaStart(info.RowLast + 1) - d.Text.ParaStart(f))));
          if rows.Count > 0 then
            AssertEquals(msg + ': a run of rows left', rows.DelimitedText, TableShape(d, k));
          CheckReadBack(msg + ' (a run)', d);
          CheckRichEdit(msg + ' (a run)', d);
          // and the commands, one row after the other
          d.Undo;
          for k := r2 downto r do
            AssertTrue(msg + ': the commands for a run', Exec(d, TTyRichDeleteRow.Create(TablePos(d), r)));
          if rows.Count > 0 then
          begin
            AssertEquals(msg + ': the commands for a run: the rows left', rows.DelimitedText,
              TableShape(d, FirstTablePara(d)));
            CheckClean(msg + ': the commands for a run', d, FirstTablePara(d));
          end;
          CheckReadBack(msg + ' (commands for a run)', d);
        finally
          d.Free;
          rows.Free;
        end;
      end;
    end;
  end;
end;

procedure TTyRichTablesTest.TestDeletingTheLastRowRemovesTheTable;
var
  d: TTyRichDocument;
  before: string;
begin
  d := TableDoc(1, 2);
  try
    before := Dump(d);
    AssertTrue('the last row', Exec(d, TTyRichDeleteRow.Create(TablePos(d), 0)));
    AssertEquals('nothing of the table stays', -1, FirstTablePara(d));
    AssertEquals('the paragraphs around it, not joined', 'before' + LineEnding + 'after' + LineEnding,
      Contents(d));
    d.Undo;
    AssertEquals('undone', before, Dump(d));
  finally
    d.Free;
  end;
  // a table that ends the text (made so by a plain delete of what followed it)
  d := NewDoc('x');
  try
    AssertTrue('a table', Exec(d, TTyRichInsertTable.Create(1, 1, 1)));
    Fill(d, 1, 0, 0, 'c');
    AssertTrue('the paragraph after it goes', Exec(d, TTyRichDelete.Create(d.Text.Length - 1, 1)));
    AssertTrue('the table ends the text', d.CellAt(d.Text.ParaCount - 1) <> nil);
    before := Dump(d);
    AssertTrue('its last row', Exec(d, TTyRichDeleteRow.Create(TablePos(d), 0)));
    AssertEquals('no table', -1, FirstTablePara(d));
    AssertEquals('an empty paragraph in its place', 'x' + LineEnding + LineEnding, Contents(d));
    AssertEquals('integrity', '', d.Text.CheckIntegrity);
    d.Undo;
    AssertEquals('undone', before, Dump(d));
  finally
    d.Free;
  end;
end;

{ ---- columns ---- }

procedure TTyRichTablesTest.TestColumnsAtEachPlace;
var
  d: TTyRichDocument;
  i, w: Integer;
  shape, before: string;
  e: array of Integer;
  t: TTyRichTable;

  function EdgesStr(const A: array of Integer): string;
  var
    k: Integer;
  begin
    Result := '';
    for k := 0 to High(A) do
    begin
      if k > 0 then Result := Result + ',';
      Result := Result + IntToStr(A[k]);
    end;
  end;

begin
  e := nil;
  for i := 0 to 3 do
  begin
    d := TableDoc(2, 3);
    try
      w := d.TextWidthTwips;
      shape := TableShape(d, 1);
      before := Dump(d);
      AssertTrue(Format('insert column %d', [i]), Exec(d, TTyRichInsertColumn.Create(TablePos(d), i)));
      AssertEquals(Format('column %d: the shape', [i]), MapRows(shape, True, i), TableShape(d, 1));
      CheckClean(Format('column %d', [i]), d, 1);
      // as wide as the cell beside it (all are w / 3 here, give or take a twip); the edges
      // after it moved by that width
      SetLength(e, 4);
      case i of
        0: begin e[0] := w div 3; e[1] := 2 * (w div 3); e[2] := w div 3 + w * 2 div 3; e[3] := w div 3 + w; end;
        1: begin e[0] := w div 3; e[1] := 2 * (w div 3); e[2] := w * 2 div 3 + w div 3; e[3] := w + w div 3; end;
        2: begin e[0] := w div 3; e[1] := w * 2 div 3; e[2] := w * 2 div 3 + (w * 2 div 3 - w div 3);
             e[3] := w + (w * 2 div 3 - w div 3); end;
      else
        begin e[0] := w div 3; e[1] := w * 2 div 3; e[2] := w; e[3] := w + (w - w * 2 div 3); end;
      end;
      t := d.TableAt(1);
      AssertEquals(Format('column %d: the edges', [i]), EdgesStr(e), RowEdgesOf(t.Rows[0]));
      AssertEquals(Format('column %d: every row', [i]), RowEdgesOf(t.Rows[0]), RowEdgesOf(t.Rows[1]));
      CheckReadBack(Format('column %d', [i]), d);
      d.Undo;
      AssertEquals(Format('column %d: undone', [i]), before, Dump(d));
    finally
      d.Free;
    end;
  end;
  for i := 0 to 2 do
  begin
    d := TableDoc(2, 3);
    try
      w := d.TextWidthTwips;
      shape := TableShape(d, 1);
      before := Dump(d);
      AssertTrue(Format('delete column %d', [i]), Exec(d, TTyRichDeleteColumn.Create(TablePos(d), i)));
      AssertEquals(Format('delete %d: the shape', [i]), MapRows(shape, False, i), TableShape(d, 1));
      CheckClean(Format('delete %d', [i]), d, 1);
      SetLength(e, 2);
      case i of
        0: begin e[0] := w * 2 div 3 - w div 3; e[1] := w - w div 3; end;
        1: begin e[0] := w div 3; e[1] := w - (w * 2 div 3 - w div 3); end;
      else
        begin e[0] := w div 3; e[1] := w * 2 div 3; end;
      end;
      AssertEquals(Format('delete %d: the edges', [i]), EdgesStr(e), RowEdgesOf(d.TableAt(1).Rows[1]));
      CheckReadBack(Format('delete %d', [i]), d);
      d.Undo;
      AssertEquals(Format('delete %d: undone', [i]), before, Dump(d));
    finally
      d.Free;
    end;
  end;
end;

procedure TTyRichTablesTest.TestDeletingTheOnlyColumnRemovesTheTable;
var
  d: TTyRichDocument;
  before: string;
begin
  d := TableDoc(3, 1);
  try
    before := Dump(d);
    AssertTrue('the only column', Exec(d, TTyRichDeleteColumn.Create(TablePos(d), 0)));
    AssertEquals('no table', -1, FirstTablePara(d));
    AssertEquals('the paragraphs around it', 'before' + LineEnding + 'after' + LineEnding, Contents(d));
    d.Undo;
    AssertEquals('undone', before, Dump(d));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestIrregularRowsRefuseColumns;
var
  d: TTyRichDocument;
  before: string;
begin
  d := LoadDoc(BytesOf('{\rtf1\ansi\pard first\par' + #13#10 +
    '\trowd\cellx1000\cellx2000\pard\intbl a\cell b\cell\row' + #13#10 +
    '\trowd\cellx1000\cellx2000\cellx3000\pard\intbl c\cell d\cell e\cell\row' + #13#10 +
    '\pard last\par}'));
  try
    AssertEquals('one table of two rows', 'a|b/c|d|e', TableShape(d, 1));
    before := Dump(d);
    AssertTrue('insert column', Refusal(d, rtkInsertColumn, TablePos(d), 1) = rtrIrregularRows);
    AssertTrue('delete column', Refusal(d, rtkDeleteColumn, TablePos(d), 0) = rtrIrregularRows);
    AssertFalse('not executed', Exec(d, TTyRichInsertColumn.Create(TablePos(d), 1)));
    AssertEquals('nothing changed', before, Dump(d));
    AssertTrue('rows still', Refusal(d, rtkInsertRow, TablePos(d), 1) = rtrNone);
    AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 2)));
    AssertEquals('like the row above it', 'a|b/c|d|e/||', TableShape(d, 1));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestARowFormatKeepsItsCellWords;
var
  d, back: TTyRichDocument;
  oldRaw, newRaw, rowWords, newRowWords: RawByteString;
  cells, newCells: TTyRtfCellWords;
  i, k: Integer;
  t: TTyRichTable;
begin
  d := LoadDoc(FixtureBytes('wp-zh-table.rtf'));
  try
    k := FirstTablePara(d);
    oldRaw := d.CellAt(k).Row.RawFormat;
    AssertTrue('WordPad''s row splits', TyRtfSplitRowFormat(oldRaw, 3, rowWords, cells));
    AssertTrue('it has cell borders', Pos('\clbrdrl\brdrw10\brdrs', cells[1]) = 1);
    AssertTrue('and row borders', Pos('\trbrdrl\brdrs\brdrw10 ', rowWords) > 0);
    AssertTrue('insert column', Exec(d, TTyRichInsertColumn.Create(TablePos(d), 1)));
    t := d.TableAt(k);
    for i := 0 to t.RowCount - 1 do
    begin
      newRaw := t.Rows[i].RawFormat;
      AssertTrue('the new row splits', TyRtfSplitRowFormat(newRaw, 4, newRowWords, newCells));
      AssertTrue('the row''s words as they were', SameRaw(rowWords, newRowWords));
      AssertTrue('cell 0''s words', SameRaw(cells[0], newCells[0]));
      AssertTrue('the new cell has the words of the one beside it', SameRaw(cells[0], newCells[1]));
      AssertTrue('cell 1''s words', SameRaw(cells[1], newCells[2]));
      AssertTrue('cell 2''s words', SameRaw(cells[2], newCells[3]));
      // cell 0 is 2768 twips wide (from \trleft5 to \cellx2773): the new cell too, and the
      // edges after it move by that
      AssertTrue('only the edges change', Pos('\cellx2773\', newRaw) > 0);
      AssertTrue('the new cell''s edge', Pos('\cellx5541\', newRaw) > 0);
      AssertTrue('the next edge moved by the width', Pos('\cellx8310\', newRaw) > 0);
      AssertTrue('the last edge', Pos('\cellx11079', newRaw) > 0);
    end;
    back := LoadDoc(SaveBytes(d));
    try
      k := FirstTablePara(back);
      AssertTrue('read back: the format as written', SameRaw(t.Rows[0].RawFormat,
        back.CellAt(k).Row.RawFormat));
    finally
      back.Free;
    end;
    CheckRichEdit('wp-zh-table, a column', d);
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestSplittingRowFormats;
const
  Word2007 = '\trowd \irow0\irowband0\ltrrow\ts11\trgaph108\trleft-108\trbrdrt\brdrs\brdrw10 ' +
    '\trbrdrl\brdrs\brdrw10 \trftsWidth1\trautofit1\tblind0\tblindtype3 \clvertalt\clbrdrt' +
    '\brdrs\brdrw10 \clbrdrl\brdrs\brdrw10 \cltxlrtb\clftsWidth3\clwWidth4261\clshdrawnil ' +
    '\cellx4153\clvertalc\clbrdrb\brdrdb\brdrw15 \clcbpat2\cltxlrtb\clftsWidth3\clwWidth4261 \cellx8414';
var
  rowWords, joined: RawByteString;
  cells: TTyRtfCellWords;
  disp, grid: TTyRowDisplay;
  i: Integer;
  s: TTyRowCellSide;
begin
  AssertTrue('Word''s row', TyRtfSplitRowFormat(Word2007, 2, rowWords, cells));
  AssertEquals('the row''s words', '\trowd \irow0\irowband0\ltrrow\ts11\trgaph108\trleft-108' +
    '\trbrdrt\brdrs\brdrw10 \trbrdrl\brdrs\brdrw10 \trftsWidth1\trautofit1\tblind0\tblindtype3 ',
    rowWords);
  AssertEquals('cell 0', '\clvertalt\clbrdrt\brdrs\brdrw10 \clbrdrl\brdrs\brdrw10 \cltxlrtb' +
    '\clftsWidth3\clwWidth4261\clshdrawnil ', cells[0]);
  AssertEquals('cell 1', '\clvertalc\clbrdrb\brdrdb\brdrw15 \clcbpat2\cltxlrtb\clftsWidth3' +
    '\clwWidth4261 ', cells[1]);
  joined := TyRtfJoinRowFormat(rowWords, cells, [4153, 8414]);
  AssertTrue('put together again: the same', SameRaw(Word2007, joined));
  AssertFalse('a cell more than it has', TyRtfSplitRowFormat(Word2007, 3, rowWords, cells));
  AssertFalse('a group', TyRtfSplitRowFormat('\trowd{\*\tblind 0}\cellx100', 1, rowWords, cells));
  AssertFalse('text', TyRtfSplitRowFormat('\trowd x\cellx100', 1, rowWords, cells));
  AssertFalse('a cell edge with no number', TyRtfSplitRowFormat('\trowd\cellx', 1, rowWords, cells));
  AssertFalse('words after the last edge', TyRtfSplitRowFormat('\trowd\cellx100\clvertalc', 1,
    rowWords, cells));
  AssertFalse('no \trowd', TyRtfSplitRowFormat('\cellx100', 1, rowWords, cells));
  AssertTrue('line breaks between words', TyRtfSplitRowFormat('\trowd' + #13#10 + '\cellx100', 1,
    rowWords, cells));
  // a diagonal's line words are its cell's
  AssertTrue('a diagonal', TyRtfSplitRowFormat('\trowd\cldglu\brdrs\brdrw10 \cellx1000', 1,
    rowWords, cells));
  AssertEquals('the diagonal and its line', '\cldglu\brdrs\brdrw10 ', cells[0]);
  AssertEquals('nothing of it the row''s', '\trowd', rowWords);
  AssertTrue('the other diagonal', TyRtfSplitRowFormat('\trowd\trgaph108\cldgll\brdrdb\brdrcf2' +
    '\clbrdrt\brdrs\cellx1000', 1, rowWords, cells));
  AssertEquals('its line words', '\cldgll\brdrdb\brdrcf2\clbrdrt\brdrs', cells[0]);
  // the numbering words of Word's rows go, and only they
  AssertEquals('numbering left out', '\trowd \ltrrow\trgaph108\cellx1000',
    Txt(TyRtfRowFormatUnnumbered('\trowd \irow3\irowband3\ltrrow\lastrow\trgaph108\cellx1000')));
  AssertEquals('a word that only starts the same stays', '\trowd\irowx\cellx1',
    Txt(TyRtfRowFormatUnnumbered('\trowd\irowx\cellx1')));
  AssertEquals('inside a group it stays', '\trowd{\*\x\irow2}\cellx1',
    Txt(TyRtfRowFormatUnnumbered('\trowd{\*\x\irow2}\cellx1')));
  // the grid looks as a row with no format of its own
  disp := TyRtfRowDisplay(TyRtfGridRowFormat([1000, 2500]));
  grid := TyDefaultRowDisplay(2);
  AssertEquals('half gap', grid.HalfGap, disp.HalfGap);
  AssertEquals('cells', 2, Length(disp.Cells));
  AssertEquals('second edge', 2500, disp.Cells[1].Right);
  for i := 0 to 1 do
  begin
    AssertTrue('sides', disp.Cells[i].Borders = grid.Cells[i].Borders);
    for s := Low(TTyRowCellSide) to High(TTyRowCellSide) do
      AssertEquals('line width', grid.Cells[i].BorderWidth[s], disp.Cells[i].BorderWidth[s]);
  end;
end;

{ ---- refusals ---- }

procedure TTyRichTablesTest.TestLockedTableRefusesStructureChanges;
const
  Merged = '{\rtf1\ansi\pard first\par' + #13#10 +
    '\trowd\clmgf\cellx1000\clmrg\cellx2000\cellx3000\pard\intbl a\cell\cell b\cell\row' + #13#10 +
    '\trowd\cellx1000\cellx2000\cellx3000\pard\intbl c\cell d\cell e\cell\row' + #13#10 +
    '\pard last\par}';

  procedure Check(const AName: string; const ABytes: TBytes; AReason: TTyRichTableRefusal);
  var
    d: TTyRichDocument;
    k, para: Integer;
    kind: TTyRichTableEditKind;
    before: string;
    o: TBytes;
    p: TTyRichPos;
  begin
    d := LoadDoc(ABytes);
    try
      before := Dump(d);
      o := SaveBytes(d);
      AssertTrue(AName + ': saved as the file', SameBytes(ABytes, o));
      para := FirstTablePara(d);
      // anywhere in the table: its first paragraph, and the last of the table's paragraphs
      for k := 0 to 1 do
      begin
        if k = 0 then p := d.Text.ParaStart(para)
        else
        begin
          while (para + 1 < d.Text.ParaCount) and (d.CellAt(para + 1) <> nil) do Inc(para);
          p := d.Text.ParaStart(para);
        end;
        for kind := rtkInsertRow to rtkDeleteColumn do
        begin
          AssertTrue(Format('%s, %d: %d refused with its reason', [AName, k, Ord(kind)]),
            Refusal(d, kind, p, 0) = AReason);
          AssertFalse(Format('%s, %d: %d not executed', [AName, k, Ord(kind)]),
            Exec(d, TableCommand(kind, p, 0)));
        end;
        AssertTrue(AName + ': no table in it', Refusal(d, rtkInsertTable, p, 0) = rtrInTable);
      end;
      AssertEquals(AName + ': untouched', before, Dump(d));
      AssertTrue(AName + ': saved still as the file', SameBytes(ABytes, SaveBytes(d)));
    finally
      d.Free;
    end;
  end;

begin
  Check('hand-word-table-merged.rtf', FixtureBytes('hand-word-table-merged.rtf'), rtrNestedTable);
  Check('word-table-merged.rtf', FixtureBytes('word-table-merged.rtf'), rtrNestedTable);
  Check('merged cells', BytesOf(Merged), rtrMergedCells);
end;

{ RTF of tables one after another, each of ARows rows (three cells), at least ATarget bytes;
  ABig: one more table of ABigRows rows in the middle. }
function TablesRtf(ARows: Integer; ATarget: Int64; ABigRows: Integer = 0): TBytes;
var
  m: TMemoryStream;
  k, i: Integer;
  big: Boolean;

  procedure Add(const S: RawByteString);
  begin
    if S <> '' then m.WriteBuffer(S[1], Length(S));
  end;

  procedure Rows(ACount: Integer; ATable: Integer);
  var
    r: Integer;
  begin
    for r := 0 to ACount - 1 do
      Add(Format('\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 +
        '\pard\intbl t%d r%d a\cell r%d b\cell r%d c\cell\row' + #13#10, [ATable, r, r, r]));
  end;

begin
  m := TMemoryStream.Create;
  try
    Add('{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}}' + #13#10 +
      '\pard\f0\fs24 ');
    k := 0;
    big := ABigRows > 0;
    while m.Size < ATarget do
    begin
      Add('\pard between tables ' + IntToStr(k) + '\par' + #13#10);
      if big and (m.Size > ATarget div 2) then
      begin
        Rows(ABigRows, k);
        big := False;
      end
      else
        Rows(ARows, k);
      Inc(k);
    end;
    Add('\pard the end\par' + #13#10 + '}');
    Result := nil;
    SetLength(Result, m.Size);
    i := m.Size;
    if i > 0 then Move(m.Memory^, Result[0], i);
  finally
    m.Free;
  end;
end;

procedure TTyRichTablesTest.TestADocumentThatLoadsOrSavesRefuses;
var
  d: TTyRichDocument;
  s: TBytesStream;
  load: TTyRtfLoad;
  k: Integer;
begin
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(TablesRtf(20, 3 shl 20));
  try
    load := TyRichBeginLoadRtf(d, s, 64 * 1024);
    AssertTrue('loading', d.Loading);
    k := FirstTablePara(d);
    AssertTrue('a table there', k >= 0);
    AssertTrue('a row while loading', Refusal(d, rtkInsertRow, d.Text.ParaStart(k), 0) = rtrReadOnly);
    AssertTrue('a table while loading', Refusal(d, rtkInsertTable, 0, 0) = rtrReadOnly);
    AssertFalse('not executed', Exec(d, TTyRichInsertRow.Create(d.Text.ParaStart(k), 0)));
    load.Cancel;
    AssertTrue('incomplete', d.Incomplete);
    AssertTrue('a row of an incomplete one', Refusal(d, rtkDeleteRow, d.Text.ParaStart(k), 0) = rtrReadOnly);
    AssertFalse('not executed', Exec(d, TTyRichDeleteRow.Create(d.Text.ParaStart(k), 0)));
  finally
    s.Free;
    d.Free;
  end;
  d := TableDoc(2, 2);
  try
    d.BeginSave;
    try
      AssertTrue('while saving', Refusal(d, rtkInsertColumn, TablePos(d), 0) = rtrReadOnly);
      AssertFalse('not executed', Exec(d, TTyRichInsertColumn.Create(TablePos(d), 0)));
    finally
      d.EndSave;
    end;
    AssertTrue('after the save', Refusal(d, rtkInsertColumn, TablePos(d), 0) = rtrNone);
    AssertTrue('in no table', Refusal(d, rtkInsertRow, 0, 0) = rtrNoTable);
    AssertTrue('a row out of range', Refusal(d, rtkInsertRow, TablePos(d), 3) = rtrOutOfRange);
    AssertTrue('a row to delete out of range', Refusal(d, rtkDeleteRow, TablePos(d), 2) = rtrOutOfRange);
    AssertTrue('a negative row', Refusal(d, rtkDeleteRow, TablePos(d), -1) = rtrOutOfRange);
    AssertTrue('a column out of range', Refusal(d, rtkInsertColumn, TablePos(d), 3) = rtrOutOfRange);
    AssertTrue('a column to delete out of range', Refusal(d, rtkDeleteColumn, TablePos(d), 2) = rtrOutOfRange);
    AssertTrue('the last place for a row', Refusal(d, rtkInsertRow, TablePos(d), 2) = rtrNone);
    AssertTrue('the last place for a column', Refusal(d, rtkInsertColumn, TablePos(d), 2) = rtrNone);
  finally
    d.Free;
  end;
end;

{ ---- what the table has after an edit ---- }

procedure TTyRichTablesTest.TestRowsAPlainDeleteLeftAreNotTakenAlong;
var
  d: TTyRichDocument;
  kind: TTyRichTableEditKind;
  info: TTyRichTableInfo;
  before, after: string;
begin
  for kind := rtkInsertRow to rtkDeleteColumn do
  begin
    d := TableDoc(3, 2);
    try
      // row 1 goes by a plain delete: the table object keeps it, with no paragraph
      d.TableInfoAt(3, info);
      AssertTrue('a plain delete of a row', Exec(d, TTyRichDelete.Create(d.Text.ParaStart(info.RowFirst),
        d.Text.ParaStart(info.RowLast + 1) - d.Text.ParaStart(info.RowFirst))));
      AssertEquals('the object keeps the row', 3, d.TableAt(1).RowCount);
      d.TableInfoAt(1, info);
      AssertEquals('two rows have paragraphs', 2, info.RowCount);
      AssertEquals('the shape', 'r0c0|r0c1/r2c0|r2c1', TableShape(d, 1));
      before := Dump(d);
      AssertTrue(Format('edit %d', [Ord(kind)]), Exec(d, TableCommand(kind, TablePos(d), 1)));
      CheckClean(Format('edit %d', [Ord(kind)]), d, 1);
      after := Dump(d);
      d.Undo;
      AssertEquals(Format('edit %d: undone', [Ord(kind)]), before, Dump(d));
      d.Redo;
      AssertEquals(Format('edit %d: redone', [Ord(kind)]), after, Dump(d));
      CheckReadBack(Format('edit %d', [Ord(kind)]), d);
    finally
      d.Free;
    end;
  end;
end;

procedure TTyRichTablesTest.TestACellWithNoParagraphGetsOne;
var
  d: TTyRichDocument;
  f, l: Integer;
  before: string;
begin
  d := TableDoc(2, 2);
  try
    // the primitives let a cell lose its only paragraph (a plain delete of it, whole)
    d.TableCellParas(1, 0, 1, f, l);
    AssertTrue('a cell''s paragraph goes', Exec(d, TTyRichDelete.Create(d.Text.ParaStart(f),
      d.Text.ParaStart(f + 1) - d.Text.ParaStart(f))));
    AssertEquals('cell 0, 1 has none', 'r0c0|#/r1c0|r1c1', TableShape(d, 1));
    before := Dump(d);
    // (an edit of rows reads the row it puts one beside: that row is the one put right)
    AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 1)));
    AssertEquals('the cell has an empty paragraph again', 'r0c0|/|/r1c0|r1c1', TableShape(d, 1));
    CheckClean('a cell filled', d, 1);
    CheckReadBack('a cell filled', d);
    d.Undo;
    AssertEquals('undone', before, Dump(d));
  finally
    d.Free;
  end;
end;

{ ---- tables a reader that parses on demand gives in parts ---- }

// A paragraph of a table the loader gave as a part of a table that is small.
function CutPara(ADoc: TTyRichDocument): Integer;
var
  i: Integer;
  c: TTyRichCell;
begin
  ADoc.BeginRead;
  try
    for i := 0 to ADoc.Text.ParaCount - 1 do
    begin
      c := ADoc.CellAt(i);
      if (c <> nil) and c.Table.Cut then Exit(i);
    end;
  finally
    ADoc.EndRead;
  end;
  Result := -1;
end;

procedure TTyRichTablesTest.TestATableCutByTheLoaderIsEditedWhole;
var
  b, o: TBytes;
  d, full: TTyRichDocument;
  k, i: Integer;
  info: TTyRichTableInfo;
  kind: TTyRichTableEditKind;
  t: TTyRichTable;
  p: TTyRichPos;
  shape, want: string;
begin
  // tables of 1000 rows (80 KB): a chain across every snapshot, cut where a parsing block ends
  b := TablesRtf(1000, 3 shl 20);
  full := LoadDoc(b, True);
  try
    for kind := rtkInsertRow to rtkDeleteColumn do
    begin
      d := LoadDoc(b);
      try
        k := CutPara(d);
        AssertTrue('a table cut where a block ends', k >= 0);
        AssertTrue('its parts are locked as objects', d.TableAt(k).StructureLocked);
        AssertFalse('for where it lies, not for what it holds', d.TableAt(k).ContentLocked);
        p := d.Text.ParaStart(k);
        AssertTrue(Format('%d: allowed', [Ord(kind)]), Refusal(d, kind, p, 1) = rtrNone);
        AssertTrue('the readers see the table whole', d.TableInfoAt(k, info));
        AssertEquals('all its rows', 1000, info.RowCount);
        shape := TableShape(full, info.First);
        AssertEquals('as a whole parse has it', shape, TableShape(d, k));
        AssertTrue(Format('%d: executed', [Ord(kind)]), Exec(d, TableCommand(kind, p, 1)));
        d.BeginRead;
        try
          t := d.TableAt(info.First);
          for i := info.First to info.First + 10 do
            AssertTrue('one object now', d.TableAt(i) = t);
          AssertFalse('not cut', t.Cut);
        finally
          d.EndRead;
        end;
        case kind of
          rtkInsertRow:
            begin
              want := shape;
              Insert('||/', want, Pos('/', want) + 1);
            end;
          rtkDeleteRow: want := ShapeWithoutRow(shape, 1);
          rtkInsertColumn: want := MapRows(shape, True, 1);
        else
          want := MapRows(shape, False, 1);
        end;
        AssertEquals(Format('%d: the table', [Ord(kind)]), want, TableShape(d, info.First));
        CheckClean(Format('%d', [Ord(kind)]), d, info.First);
        d.Undo;
        o := SaveBytes(d);
        AssertTrue(Format('%d: undone, saved, the file', [Ord(kind)]), SameBytes(b, o));
        AssertTrue(Format('%d: the parts are back', [Ord(kind)]), d.TableAt(k).Cut);
      finally
        d.Free;
      end;
    end;
  finally
    full.Free;
  end;
end;

procedure TTyRichTablesTest.TestABigTableCutByTheLoaderIsRefused;
var
  b: TBytes;
  d: TTyRichDocument;
  k: Integer;
  info: TTyRichTableInfo;
  before: string;
begin
  // a table of 15000 rows (over a megabyte) among small ones
  b := TablesRtf(5, 2 shl 20, 15000);
  d := LoadDoc(b);
  try
    // (only the big table has a row 7000)
    k := 0;
    while (k < d.Text.ParaCount) and (Pos(' r7000 a', ParaText(d, k)) = 0) do Inc(k);
    AssertTrue('the big table', k < d.Text.ParaCount);
    AssertTrue('a part of it', d.TableAt(k).Cut);
    d.TableInfoAt(k, info);
    AssertTrue('a part only', info.RowCount < 15000);
    before := StrOf(SaveBytes(d));
    AssertTrue('refused: too big', Refusal(d, rtkInsertRow, d.Text.ParaStart(k), 0) = rtrNotWhole);
    AssertTrue('refused: too big, a column', Refusal(d, rtkDeleteColumn, d.Text.ParaStart(k), 0) = rtrNotWhole);
    AssertFalse('not executed', Exec(d, TTyRichDeleteRow.Create(d.Text.ParaStart(k), 0)));
    AssertTrue('untouched', SameRaw(before, StrOf(SaveBytes(d))));
  finally
    d.Free;
  end;
end;

{ ---- undo, redo, memory, bytes, layout ---- }

procedure TTyRichTablesTest.TestEachCommandUndoesAndRedoesExactly;
var
  n, cycle: Integer;
  kind: TTyRichTableEditKind;
  d: TTyRichDocument;
  before, after, msg: string;
  b: TBytes;
  p: TTyRichPos;
  t: TTyRichTable;
begin
  for n := 0 to 2 do
    for kind := Low(TTyRichTableEditKind) to High(TTyRichTableEditKind) do
    begin
      case n of
        0: d := TableDoc(3, 3);
        1: d := LoadDoc(FixtureBytes('re-zh-table.rtf'));
      else
        d := LoadDoc(FixtureBytes('wp-zh-table.rtf'));
      end;
      try
        msg := Format('document %d, edit %d', [n, Ord(kind)]);
        if kind = rtkInsertTable then p := 0 else p := TablePos(d);
        t := d.TableAt(FirstTablePara(d));
        b := SaveBytes(d);
        before := Dump(d);
        AssertTrue(msg + ': executed', Exec(d, TableCommand(kind, p, 1)));
        after := Dump(d);
        AssertTrue(msg + ': changed', after <> before);
        AssertEquals(msg + ': one step', 1, d.UndoDepth);
        AssertTrue(msg + ': its description', d.UndoDescription <> '');
        for cycle := 1 to 3 do
        begin
          d.Undo;
          AssertEquals(msg + Format(', cycle %d: undo gives back every paragraph''s cell', [cycle]),
            before, Dump(d));
          AssertTrue(msg + ': the very table object again', d.TableAt(FirstTablePara(d)) = t);
          AssertEquals(msg + ': integrity', '', d.Text.CheckIntegrity);
          AssertTrue(msg + ': saved, the file', SameBytes(b, SaveBytes(d)));
          d.Redo;
          AssertEquals(msg + Format(', cycle %d: redo gives the result again', [cycle]), after, Dump(d));
          AssertEquals(msg + ': integrity after the redo', '', d.Text.CheckIntegrity);
        end;
      finally
        d.Free;
      end;
    end;
end;

procedure TTyRichTablesTest.TestAStepHoldsNothingOfTheTextAround;
var
  kind: TTyRichTableEditKind;
  small, large: Int64;
  d: TTyRichDocument;
  i: Integer;
  s: UTF8String;

  function StepSize(ADoc: TTyRichDocument): Int64;
  begin
    AssertTrue('executed', Exec(ADoc, TableCommand(kind, TablePos(ADoc), 1)));
    Result := ADoc.UndoStep.MemSize;
  end;

begin
  s := '';
  for i := 0 to 20000 do s := s + 'a paragraph of the text around the table' + #13#10;
  for kind := rtkInsertRow to rtkDeleteColumn do
  begin
    d := TableDoc(3, 3);
    try
      small := StepSize(d);
    finally
      d.Free;
    end;
    d := TableDoc(3, 3);
    try
      AssertTrue('text before', Exec(d, TTyRichInsertText.Create(0, s)));
      AssertTrue('text after', Exec(d, TTyRichInsertText.Create(d.Text.Length, #13#10 + s)));
      large := StepSize(d);
    finally
      d.Free;
    end;
    AssertTrue(Format('edit %d: %d bytes in a large document, %d in a small one', [Ord(kind), large,
      small]), large <= small + 1024);
    AssertTrue(Format('edit %d: a few kilobytes (%d)', [Ord(kind), small]), small < 16384);
  end;
end;

procedure TTyRichTablesTest.TestUntouchedRowsKeepTheirBytes;
const
  Names: array[0..1] of string = ('re-zh-table.rtf', 'wp-zh-table.rtf');
var
  n, k, r, f, l: Integer;
  b, o: TBytes;
  d: TTyRichDocument;
  info: TTyRtfWriteInfo;
  tinfo, rinfo: TTyRichTableInfo;
  oo, bb: RawByteString;
  src, nb, first: Int64;
  rowBytes: array of RawByteString;
begin
  for n := 0 to High(Names) do
  begin
    b := FixtureBytes(Names[n]);
    bb := StrOf(b);
    // a new row: written from the model; the rows of the file are its bytes
    d := LoadDoc(b);
    try
      k := FirstTablePara(d);
      d.TableInfoAt(k, tinfo);
      // each row's bytes in the file
      rowBytes := nil;
      SetLength(rowBytes, tinfo.RowCount);
      for r := 0 to tinfo.RowCount - 1 do
      begin
        d.TableCellParas(k, r, 0, f, l);
        d.TableInfoAt(f, rinfo);
        AssertTrue('the row is the file''s', d.Text.ParaLazySource(rinfo.RowFirst, first, nb));
        d.Text.ParaLazySource(rinfo.RowLast, src, nb);
        rowBytes[r] := Copy(bb, first + 1, src + nb - first);
      end;
      AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 1)));
      o := SaveBytes(d, info);
      AssertEquals(Names[n] + ': only the new row is written from the model', 3, info.RewrittenParas);
      oo := StrOf(o);
      for r := 0 to High(rowBytes) do
        AssertTrue(Format('%s: row %d as the file has it', [Names[n], r]), Pos(rowBytes[r], oo) > 0);
      // the paragraphs outside the table
      d.Text.ParaLazySource(0, src, nb);
      AssertTrue(Names[n] + ': the paragraph before', Pos(Copy(bb, src + 1, nb), oo) > 0);
      d.Text.ParaLazySource(d.Text.ParaCount - 1, src, nb);
      AssertTrue(Names[n] + ': the paragraph after', Pos(Copy(bb, src + 1, nb), oo) > 0);
      d.Undo;
      AssertTrue(Names[n] + ': undone: the file', SameBytes(b, SaveBytes(d)));
    finally
      d.Free;
    end;
    // a row deleted: nothing written from the model
    d := LoadDoc(b);
    try
      AssertTrue('a row deleted', Exec(d, TTyRichDeleteRow.Create(TablePos(d), 1)));
      SaveBytes(d, info);
      AssertEquals(Names[n] + ': a deleted row: nothing from the model', 0, info.RewrittenParas);
      d.Undo;
      AssertTrue(Names[n] + ': undone: the file', SameBytes(b, SaveBytes(d)));
    finally
      d.Free;
    end;
    // a column: the table from the model, nothing else
    d := LoadDoc(b);
    try
      AssertTrue('a column', Exec(d, TTyRichInsertColumn.Create(TablePos(d), 1)));
      d.TableInfoAt(FirstTablePara(d), tinfo);
      SaveBytes(d, info);
      AssertEquals(Names[n] + ': a column: the table''s paragraphs from the model',
        tinfo.Last - tinfo.First + 1, info.RewrittenParas);
      d.Undo;
      AssertTrue(Names[n] + ': undone: the file', SameBytes(b, SaveBytes(d)));
    finally
      d.Free;
    end;
  end;
end;

procedure TTyRichTablesTest.TestTheLayoutFollowsARowEdit;
const
  Rows = 2000;
  Mid = 1000;
var
  d: TTyRichDocument;
  lo, fresh: TTyRichLayouter;
  b: TTyBlockLayout;
  i, f, l, misses: Integer;
  firsts: array of Integer;
  kept: Integer;
begin
  d := NewDoc('before' + #13#10 + 'after');
  lo := Layouter;
  fresh := Layouter;
  try
    AssertTrue('a long table', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(1), Rows, 2)));
    // a screen of rows around the middle, laid out
    SetLength(firsts, 21);
    for i := 0 to 20 do
    begin
      d.TableCellParas(1, Mid - 10 + i, 0, f, l);
      firsts[i] := f;
      b := lo.LayoutBlock(d, f, 600, 96, 1.0);
      b.Release;
    end;
    AssertTrue('a row in the middle', Exec(d, TTyRichInsertRow.Create(TablePos(d), Mid)));
    lo.DocumentChanged(d.UndoStep.Change);
    // the rows before the new one: their blocks stay but the row right above it
    kept := 0;
    for i := 0 to 9 do
      if lo.CachedLayout(firsts[i]) <> nil then Inc(kept);
    AssertEquals('the rows above stay laid out, all but the one right above', 9, kept);
    // and those after it, moved by its paragraphs, but the row right below
    AssertTrue('the row right below goes', lo.CachedLayout(firsts[10] + 2) = nil);
    kept := 0;
    for i := 11 to 20 do
      if lo.CachedLayout(firsts[i] + 2) <> nil then Inc(kept);
    AssertEquals('the rows below stay laid out, moved', 10, kept);
    // laid out again: the new row and its two neighbours; the boxes as a new layouter has them
    misses := lo.CacheMisses;
    for i := 0 to 21 do
    begin
      d.TableCellParas(1, Mid - 10 + i, 0, f, l);
      b := lo.LayoutBlock(d, f, 600, 96, 1.0);
      b.Release;
      AssertEquals(Format('row %d: as a new layouter lays it out', [Mid - 10 + i]),
        RowBoxes(fresh, d, f), RowBoxes(lo, d, f));
    end;
    AssertEquals('laid out again: the new row, the row above and the row below', 3,
      lo.CacheMisses - misses);
    AssertEquals('the height index', '', d.Text.CheckIntegrity);
    // the same for a row that goes
    AssertTrue('a row goes', Exec(d, TTyRichDeleteRow.Create(TablePos(d), Mid)));
    lo.DocumentChanged(d.UndoStep.Change);
    fresh.Clear;
    misses := lo.CacheMisses;
    for i := 0 to 20 do
    begin
      d.TableCellParas(1, Mid - 10 + i, 0, f, l);
      b := lo.LayoutBlock(d, f, 600, 96, 1.0);
      b.Release;
      AssertEquals(Format('after a delete, row %d: as a new layouter lays it out', [Mid - 10 + i]),
        RowBoxes(fresh, d, f), RowBoxes(lo, d, f));
    end;
    AssertEquals('laid out again after a delete: the rows above and below the gap', 2,
      lo.CacheMisses - misses);
  finally
    fresh.Free;
    lo.Free;
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestARowEditVisitsTheTableOnly;
const
  Rows = 10000;
var
  d: TTyRichDocument;
  visits: Int64;
  s: UTF8String;
  i: Integer;
begin
  s := '';
  for i := 0 to 999 do s := s + 'text around' + #13#10;
  d := NewDoc(s + 'after');
  try
    AssertTrue('a table of 10000 rows', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(500), Rows, 1)));
    d.TableParaVisits := 0;
    AssertTrue('one row', Exec(d, TTyRichInsertRow.Create(d.Text.ParaStart(500), Rows div 2)));
    visits := d.TableParaVisits;
    { the check (CanExecute) and the edit each read at most the table and the paragraph on
      either side once, and nothing is given cells again: a row named by its index from the
      table's first paragraph - the paragraphs up to it, twice }
    AssertTrue(Format('%d paragraph visits for one row in 10000', [visits]),
      visits <= 3 * Rows + 4);
  finally
    d.Free;
  end;
end;

{ ---- the other ways of changing a table, on one a command changed ---- }

function ReplaceAll(ADoc: TTyRichDocument; const ANeedle, ARepl: UTF8String): Integer;
var
  cmd: TTyRichReplaceAllCommand;
  tally: TTyRichReplaceTally;
begin
  tally := Default(TTyRichReplaceTally);
  cmd := TTyRichReplaceAllCommand.Create(ADoc, ANeedle, ARepl, []);
  cmd.AllAtOnce := True;
  cmd.Tally := @tally;
  ADoc.Execute(cmd);
  Result := tally.Replaced;
end;

procedure TTyRichTablesTest.TestOtherPathsOnAChangedTable;
var
  d, src: TTyRichDocument;
  s: TBytesStream;
  ends: Boolean;
  info: TTyRichTableInfo;
  f, l, k: Integer;
  t, pasted: TTyRichTable;
  rows: TList;
begin
  d := TableDoc(3, 2);
  try
    AssertTrue('a changed table', Exec(d, TTyRichInsertColumn.Create(TablePos(d), 1)));
    AssertEquals('changed', 'r0c0||r0c1/r1c0||r1c1/r2c0||r2c1', TableShape(d, 1));
    // typing and deleting in its cells
    d.TableCellParas(1, 1, 1, f, l);
    AssertTrue('typing in a new cell', Exec(d, TTyRichInsertText.Create(d.Text.ParaStart(f), 'new')));
    d.TableCellParas(1, 0, 0, f, l);
    AssertTrue('deleting in a cell', Exec(d, TTyRichDelete.Create(d.Text.ParaStart(f), 2)));
    AssertEquals('typed and deleted', 'c0||r0c1/r1c0|new|r1c1/r2c0||r2c1', TableShape(d, 1));
    // find and replace in cells
    AssertEquals('replaced in its cells', 2, ReplaceAll(d, 'r1', 'R1'));
    AssertEquals('replaced', 'c0||r0c1/R1c0|new|R1c1/r2c0||r2c1', TableShape(d, 1));
    // copy rows 0 and 1, paste them after the table: rows of their own, nothing shared
    d.TableInfoAt(1, info);
    d.TableCellParas(1, 1, 2, f, l);
    s := TBytesStream.Create;
    try
      TyRichSaveRtfRange(d, s, d.Text.ParaStart(1), d.Text.ParaStart(l + 1) - d.Text.ParaStart(1));
      src := TyRichReadRtfFragment(Copy(s.Bytes, 0, s.Size), ends);
    finally
      s.Free;
    end;
    // (after the text of the last paragraph: the rows go in as rows, apart from the table)
    k := d.Text.ParaCount - 1;
    AssertTrue('pasted', Exec(d, TTyRichInsertFragment.Create(d.Text.Length, src, ends, False,
      TyRichFragmentFilterFor(src, d))));
    d.BeginRead;
    rows := TList.Create;
    try
      t := d.TableAt(1);
      for f := info.First to info.Last do rows.Add(d.CellAt(f).Row);
      pasted := nil;
      for f := info.Last + 1 to d.Text.ParaCount - 1 do
        if d.CellAt(f) <> nil then
        begin
          pasted := d.TableAt(f);
          AssertTrue('a row of its own', rows.IndexOf(d.CellAt(f).Row) < 0);
        end;
      AssertTrue('the pasted rows', pasted <> nil);
      AssertTrue('a table of its own', pasted <> t);
    finally
      rows.Free;
      d.EndRead;
    end;
    AssertEquals('the rows pasted', 'c0||r0c1/R1c0|new|R1c1', TableShape(d, k + 1));
    // the plain delete of whole rows
    d.TableInfoAt(1, info);
    d.TableCellParas(1, 2, 0, f, l);
    d.TableInfoAt(f, info);
    AssertTrue('a plain delete of a row', Exec(d, TTyRichDelete.Create(d.Text.ParaStart(info.RowFirst),
      d.Text.ParaStart(info.RowLast + 1) - d.Text.ParaStart(info.RowFirst))));
    AssertEquals('a row went', 'c0||r0c1/R1c0|new|R1c1', TableShape(d, 1));
    // a save with nothing selected, read back
    CheckReadBack('the paths', d);
    CheckRichEdit('the paths', d);
    // and a command again on what the other paths left
    AssertTrue('a row again', Exec(d, TTyRichInsertRow.Create(TablePos(d), 2)));
    CheckClean('a row again', d, 1);
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestChineseTextSurvivesEveryEdit;
var
  kind: TTyRichTableEditKind;
  d, back: TTyRichDocument;
  zh: UTF8String;
  p: TTyRichPos;
begin
  // U+4E2D U+6587 U+8868 U+683C
  zh := U($4E2D) + U($6587) + U($8868) + U($683C);
  for kind := Low(TTyRichTableEditKind) to High(TTyRichTableEditKind) do
  begin
    d := TableDoc(2, 2, zh);
    try
      AssertTrue('Chinese before', Exec(d, TTyRichInsertText.Create(0, zh)));
      if kind = rtkInsertTable then p := 0 else p := TablePos(d);
      AssertTrue(Format('edit %d', [Ord(kind)]), Exec(d, TableCommand(kind, p, 1)));
      AssertTrue(Format('edit %d: the text in the cells', [Ord(kind)]),
        Pos(zh, TableShape(d, FirstTablePara(d) + Ord(kind = rtkInsertTable) * 5)) > 0);
      back := LoadDoc(SaveBytes(d));
      try
        AssertEquals(Format('edit %d: read back', [Ord(kind)]), Contents(d), Contents(back));
      finally
        back.Free;
      end;
      CheckRichEdit(Format('edit %d, Chinese', [Ord(kind)]), d);
    finally
      d.Free;
    end;
  end;
end;

procedure TTyRichTablesTest.TestTheReadersForAView;
var
  d: TTyRichDocument;
  info: TTyRichTableInfo;
  f, l: Integer;
begin
  d := TableDoc(3, 2);
  try
    d.TableCellParas(1, 1, 0, f, l);
    AssertTrue('enter', Exec(d, TTyRichInsertText.Create(d.Text.ParaStart(f) + 4, #13#10 + 'x')));
    // before 1, row 0: 1 2, row 1: 3 4 5, row 2: 6 7, after 8
    AssertFalse('in no table', d.TableInfoAt(0, info));
    AssertTrue('in a table', d.TableInfoAt(4, info));
    AssertEquals('the table''s first paragraph', 1, info.First);
    AssertEquals('the table''s last paragraph', 7, info.Last);
    AssertEquals('rows', 3, info.RowCount);
    AssertEquals('the row', 1, info.Row);
    AssertEquals('the row''s first paragraph', 3, info.RowFirst);
    AssertEquals('the row''s last paragraph', 5, info.RowLast);
    AssertEquals('the cell', 0, info.Cell);
    AssertEquals('cells in the row', 2, info.CellCount);
    AssertEquals('the cell''s first paragraph', 3, info.CellFirst);
    AssertEquals('the cell''s last paragraph', 4, info.CellLast);
    AssertTrue('a cell', d.TableCellParas(7, 2, 1, f, l));
    AssertEquals('its first', 7, f);
    AssertEquals('its last', 7, l);
    AssertTrue('a cell of two paragraphs', d.TableCellParas(1, 1, 0, f, l));
    AssertEquals('first of two', 3, f);
    AssertEquals('last of two', 4, l);
    AssertFalse('no such row', d.TableCellParas(1, 3, 0, f, l));
    AssertFalse('no such cell', d.TableCellParas(1, 0, 2, f, l));
    AssertFalse('no table', d.TableCellParas(0, 0, 0, f, l));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestWrittenTablesOpenInWindowsRichEdit;
{$IFDEF WINDOWS}
const
  Names: array[0..1] of string = ('re-zh-table.rtf', 'wp-zh-table.rtf');
var
  d: TTyRichDocument;
  got: RawByteString;
  n: Integer;
  kind: TTyRichTableEditKind;
begin
  if not RichEditText(BytesOf('{\rtf1 x\par}'), got) then
  begin
    Ignore('msftedit.dll (the system''s RichEdit) cannot be loaded here');
    Exit;
  end;
  d := TableDoc(3, 3);
  try
    AssertTrue('the control reads a table made here', RichEditText(SaveBytes(d), got));
    AssertTrue('its cells, in order, with the row and cell ends', SameRaw(ModelAsRichEditText(d), got));
  finally
    d.Free;
  end;
  for n := 0 to High(Names) do
    for kind := rtkInsertRow to rtkDeleteColumn do
    begin
      d := LoadDoc(FixtureBytes(Names[n]));
      try
        AssertTrue('an edit', Exec(d, TableCommand(kind, TablePos(d), 1)));
        AssertTrue('the control reads it', RichEditText(SaveBytes(d), got));
        AssertTrue(Format('%s, edit %d: its cells in order, with the row and cell ends',
          [Names[n], Ord(kind)]), SameRaw(ModelAsRichEditText(d), got));
      finally
        d.Free;
      end;
    end;
end;
{$ELSE}
begin
  Ignore('needs the system''s RichEdit (msftedit.dll): Windows only');
end;
{$ENDIF}

{ ---- the row below a row, and what a row edit leaves laid out ---- }

type
  TTyIntArrayT = array of Integer;

// RowBoxes with the row's height.
function RowLook(ALayouter: TTyRichLayouter; ADoc: TTyRichDocument; APara: Integer): string;
var
  b: TTyBlockLayout;
begin
  b := ALayouter.LayoutBlock(ADoc, APara, 600, 96, 1.0);
  try
    Result := RowBoxes(ALayouter, ADoc, APara) + Format(' h%d', [b.Height]);
  finally
    b.Release;
  end;
end;

// The first paragraph of each row of the table paragraph APara is in.
function RowFirsts(ADoc: TTyRichDocument; APara: Integer): TTyIntArrayT;
var
  info: TTyRichTableInfo;
  r, f, l: Integer;
begin
  Result := nil;
  if not ADoc.TableInfoAt(APara, info) then Exit;
  SetLength(Result, info.RowCount);
  for r := 0 to info.RowCount - 1 do
  begin
    ADoc.TableInfoAt(info.First, info);
    ADoc.TableCellParas(info.First, r, 0, f, l);
    if f < 0 then
    begin
      // (a row whose first cell has no paragraph: its first paragraph is another cell's)
      f := info.First;
    end;
    Result[r] := f;
  end;
end;

// Plain delete of row ARow's paragraphs (the table object keeps the row).
procedure PlainDeleteRow(ADoc: TTyRichDocument; ATablePara, ARow: Integer);
var
  info: TTyRichTableInfo;
  f, l: Integer;
begin
  ADoc.TableCellParas(ATablePara, ARow, 0, f, l);
  ADoc.TableInfoAt(f, info);
  if not ADoc.Execute(TTyRichDelete.Create(ADoc.Text.ParaStart(info.RowFirst),
    ADoc.Text.ParaStart(info.RowLast + 1) - ADoc.Text.ParaStart(info.RowFirst))) then
    raise Exception.Create('the rows refused a plain delete');
end;

procedure TTyRichTablesTest.TestTheNewLastRowAfterAPlainDeleteClosesTheTable;
var
  d, two: TTyRichDocument;
  lo: TTyRichLayouter;
begin
  d := TableDoc(3, 2);
  two := TableDoc(2, 2);
  lo := Layouter;
  try
    PlainDeleteRow(d, 1, 2);
    AssertEquals('the object keeps its third row', 3, d.TableAt(1).RowCount);
    // row 1 is the last now: its bottom line and the height of a last row, as in a table of two
    AssertEquals('the new last row', RowLook(lo, two, 3), RowLook(lo, d, 3));
    AssertTrue('its bottom line', Pos('3:1', RowBoxes(lo, d, 3)) > 0);
  finally
    lo.Free;
    two.Free;
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestTheRowBelowIsTheNextRowThatHasParagraphs;
const
  // rows a and b with lines on all sides, row c with a bottom line only: the line between a
  // row and c is the upper row's to draw
  Rtf = '{\rtf1\ansi\pard first\par' + #13#10 +
    '\trowd\clbrdrt\brdrs\clbrdrl\brdrs\clbrdrb\brdrs\clbrdrr\brdrs\cellx2000\pard\intbl a\cell\row' + #13#10 +
    '\trowd\clbrdrt\brdrs\clbrdrl\brdrs\clbrdrb\brdrs\clbrdrr\brdrs\cellx2000\pard\intbl b\cell\row' + #13#10 +
    '\trowd\clbrdrb\brdrs\cellx2000\pard\intbl c\cell\row' + #13#10 +
    '\pard last\par}';
  RtfTwo = '{\rtf1\ansi\pard first\par' + #13#10 +
    '\trowd\clbrdrt\brdrs\clbrdrl\brdrs\clbrdrb\brdrs\clbrdrr\brdrs\cellx2000\pard\intbl a\cell\row' + #13#10 +
    '\trowd\clbrdrb\brdrs\cellx2000\pard\intbl c\cell\row' + #13#10 +
    '\pard last\par}';
var
  d, two: TTyRichDocument;
  lo: TTyRichLayouter;
begin
  d := LoadDoc(BytesOf(Rtf));
  two := LoadDoc(BytesOf(RtfTwo));
  lo := Layouter;
  try
    AssertFalse('above a row with a top line: no bottom line', Pos('3:', RowBoxes(lo, d, 1)) > 0);
    PlainDeleteRow(d, 1, 1);
    lo.Clear;
    AssertTrue('above the row with none: its bottom line', Pos('3:', RowBoxes(lo, d, 1)) > 0);
    AssertEquals('as in a table of the two rows', RowLook(lo, two, 1), RowLook(lo, d, 1));
  finally
    lo.Free;
    two.Free;
    d.Free;
  end;
end;

type
  // forwards a document's changes to a layouter, as the control does
  TLayoutListener = class
  public
    Lo: TTyRichLayouter;
    procedure Changed(Sender: TObject; const AChange: TTyRichChange);
  end;

procedure TLayoutListener.Changed(Sender: TObject; const AChange: TTyRichChange);
begin
  Lo.DocumentChanged(AChange);
end;

procedure TTyRichTablesTest.TestTheLayoutFollowsARowEditAfterAPlainDelete;
var
  n: Integer;
  d: TTyRichDocument;
  lo, fresh: TTyRichLayouter;
  listen: TLayoutListener;
  msg: string;

  procedure LayAll;
  var
    f: TTyIntArrayT;
    i: Integer;
  begin
    f := RowFirsts(d, FirstTablePara(d));
    for i := 0 to High(f) do RowLook(lo, d, f[i]);
  end;

  procedure Compare(const AWhen: string);
  var
    f: TTyIntArrayT;
    i: Integer;
  begin
    fresh.Clear;
    f := RowFirsts(d, FirstTablePara(d));
    for i := 0 to High(f) do
      AssertEquals(Format('%s, %s: row %d as a new layout has it', [msg, AWhen, i]),
        RowLook(fresh, d, f[i]), RowLook(lo, d, f[i]));
    AssertEquals(msg + ': integrity', '', d.Text.CheckIntegrity);
  end;

begin
  for n := 0 to 2 do
  begin
    case n of
      0: d := TableDoc(3, 2);
      1: d := LoadDoc(FixtureBytes('re-zh-table.rtf'));
    else
      d := LoadDoc(FixtureBytes('wp-zh-table.rtf'));
    end;
    msg := Format('document %d', [n]);
    lo := Layouter;
    fresh := Layouter;
    listen := TLayoutListener.Create;
    try
      listen.Lo := lo;
      d.OnChange := @listen.Changed;
      LayAll;
      PlainDeleteRow(d, FirstTablePara(d), Length(RowFirsts(d, FirstTablePara(d))) - 1);
      Compare('the last row deleted');
      LayAll;
      AssertTrue(msg + ': a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 0)));
      Compare('a row inserted');
      LayAll;
      d.Undo;
      Compare('undone');
      LayAll;
      d.Redo;
      Compare('redone');
      LayAll;
      AssertTrue(msg + ': a row deleted', Exec(d, TTyRichDeleteRow.Create(TablePos(d), 1)));
      Compare('a row deleted');
    finally
      d.OnChange := nil;
      listen.Free;
      fresh.Free;
      lo.Free;
      d.Free;
    end;
  end;
end;

{ ---- costs and what a step keeps ---- }

procedure TTyRichTablesTest.TestEditsAreLinearInTheTable;
const
  Rows = 10000;
var
  kind: TTyRichTableEditKind;
  d: TTyRichDocument;
  paras: Int64;
begin
  for kind := rtkInsertRow to rtkDeleteColumn do
  begin
    d := NewDoc('before' + #13#10 + 'after');
    try
      AssertTrue('a long table', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(1), Rows, 2)));
      paras := 2 * Rows;
      d.TableEditSteps := 0;
      AssertTrue(Format('edit %d', [Ord(kind)]), Exec(d, TableCommand(kind, TablePos(d), 1)));
      AssertTrue(Format('edit %d: %d steps for %d paragraphs', [Ord(kind), d.TableEditSteps, paras]),
        d.TableEditSteps <= 6 * paras);
      // an edit of rows: the rows it touches; of columns: every row
      if kind in [rtkInsertRow, rtkDeleteRow] then
        AssertTrue(Format('edit %d: %d steps, the rows it touches', [Ord(kind), d.TableEditSteps]),
          d.TableEditSteps <= 32)
      else
        AssertTrue(Format('edit %d: steps counted', [Ord(kind)]), d.TableEditSteps >= paras);
    finally
      d.Free;
    end;
  end;
end;

procedure TTyRichTablesTest.TestATableStepCountsWhatItKeeps;
var
  d: TTyRichDocument;
  small, large, table: Int64;
  i: Integer;

  function StepOf(ARows: Integer; out ATable: Int64): Int64;
  var
    doc: TTyRichDocument;
  begin
    doc := NewDoc('x');
    try
      AssertTrue('a table', Exec(doc, TTyRichInsertTable.Create(0, ARows, 2)));
      AssertTrue('a row', Exec(doc, TTyRichInsertRow.Create(0, 1)));
      Result := doc.UndoStep.MemSize;
      ATable := doc.TableAt(0).MemSize;
    finally
      doc.Free;
    end;
  end;

begin
  small := StepOf(100, table);
  large := StepOf(1000, table);
  // the row it made and what the text keeps: nothing of the rows it did not touch
  AssertTrue(Format('a row in 1000 rows: %d bytes, in 100: %d', [large, small]),
    large <= small + 256);
  AssertTrue(Format('a row in 1000 rows: %d bytes, the table %d', [large, table]),
    large < table div 16);
  AssertTrue(Format('a row counts what it keeps (%d bytes)', [large]),
    large >= TTyRichRow.InstanceSize + 2 * TTyRichCell.InstanceSize);
  // a history bound by its own count
  d := TTyRichDocument.Create;
  try
    AssertTrue('a table', Exec(d, TTyRichInsertTable.Create(0, 1000, 2)));
    d.MaxUndoBytes := 64 * large;
    for i := 1 to 200 do
      AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(0, 500)));
    AssertTrue(Format('%d bytes held under %d', [d.HistoryBytes, d.MaxUndoBytes]),
      d.HistoryBytes <= d.MaxUndoBytes);
    AssertTrue(Format('the oldest steps went (%d kept)', [d.UndoDepth]),
      (d.UndoDepth >= 1) and (d.UndoDepth < 200));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestASourceOnlyWhereAFileIs;
var
  d: TTyRichDocument;
  i, n, k: Integer;
  own: array of Pointer;
begin
  d := TableDoc(3, 2);
  try
    AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 1)));
    for i := 0 to d.Text.ParaCount - 1 do
      AssertTrue(Format('a document made here: paragraph %d has no source', [i]),
        d.ValueSource(d.Text.ParaData[i]) = nil);
  finally
    d.Free;
  end;
  d := LoadDoc(FixtureBytes('re-zh-table.rtf'));
  try
    // (an edit of rows gives no paragraph of the rows it leaves a value: they are the file's own)
    k := FirstTablePara(d);
    SetLength(own, 9);
    for i := 0 to 8 do own[i] := d.Text.ParaData[k + i];
    AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 1)));
    n := 0;
    for i := 0 to d.Text.ParaCount - 1 do
      if d.ValueSource(d.Text.ParaData[i]) <> nil then Inc(n);
    AssertEquals('a file''s rows: none needs one', 0, n);
    for i := 0 to 2 do
      AssertTrue(Format('row 0, paragraph %d: its very value', [i]), d.Text.ParaData[k + i] = own[i]);
    for i := 3 to 8 do
      AssertTrue(Format('rows 1, 2, paragraph %d: its very value', [i]),
        d.Text.ParaData[k + 3 + i] = own[i]);
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestTableEditsLetGoOfEveryValue;
var
  d: TTyRichDocument;
  before, loaded: Int64;
  i: Integer;
begin
  before := TyRichLiveParaValues;
  d := LoadDoc(FixtureBytes('re-zh-table.rtf'));
  try
    for i := 1 to 50 do
      AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 1)));
    d.ClearUndo;
  finally
    d.Free;
  end;
  AssertEquals('every value went with the document', before, TyRichLiveParaValues);
  d := LoadDoc(FixtureBytes('re-zh-table.rtf'));
  try
    Dump(d);
    loaded := TyRichLiveParaValues;
    for i := 1 to 50 do
      AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(TablePos(d), 1)));
    for i := 1 to 50 do d.Undo;
    d.ClearUndo;
    Dump(d);
    AssertEquals('undone and the history cleared: the values of the file again', loaded,
      TyRichLiveParaValues);
  finally
    d.Free;
  end;
  AssertEquals('and none left', before, TyRichLiveParaValues);
end;

procedure TTyRichTablesTest.TestTheTableCommandCountsItsTable;
var
  small, large: Int64;

  function StepOf(ARows: Integer): Int64;
  var
    d: TTyRichDocument;
  begin
    d := NewDoc('x');
    try
      AssertTrue('a table', Exec(d, TTyRichInsertTable.Create(0, ARows, 1)));
      Result := d.UndoStep.MemSize;
    finally
      d.Free;
    end;
  end;

begin
  // an insert of a table keeps no old value: what grows is the table it keeps for a redo
  small := StepOf(2);
  large := StepOf(202);
  AssertTrue(Format('200 rows more: %d bytes more', [large - small]),
    large - small >= 200 * (TTyRichRow.InstanceSize + TTyRichCell.InstanceSize));
end;

{ ---- formats ---- }

procedure TTyRichTablesTest.TestAColumnOfARowFormatThatCannotBeSplit;
var
  d: TTyRichDocument;
  t: TTyRichTable;
begin
  d := LoadDoc(BytesOf('{\rtf1\ansi\pard first\par' + #13#10 +
    '\trowd\trleft500{\*\x}\cellx1000\cellx2000\pard\intbl a\cell b\cell\row' + #13#10 +
    '\pard last\par}'));
  try
    AssertTrue('a column', Exec(d, TTyRichInsertColumn.Create(TablePos(d), 1)));
    t := d.TableAt(1);
    // cell 0 is 500 wide (from \trleft500): the new one too, the next edge moved by that
    AssertEquals('the edges', '1000,1500,2500', RowEdgesOf(t.Rows[0]));
    AssertTrue('the plain grid of the new edges', SameRaw(TyRtfGridRowFormat([1000, 1500, 2500]),
      t.Rows[0].RawFormat));
    CheckReadBack('a format that cannot be split', d);
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestTheParagraphBetweenTwoTablesIsNoListItem;
var
  d: TTyRichDocument;
  p, got: TTyParaFormat;
  k: Integer;
begin
  d := NewDoc('item');
  try
    p := TyDefaultParaFormat;
    p.List.Kind := lkBullet;
    p.LeftIndent := 720;
    p.FirstIndent := -360;
    AssertTrue('a bullet item', Exec(d, TTyRichSetParaFormat.Create(0, 0, [pffList, pffLeftIndent,
      pffFirstIndent], p)));
    AssertTrue('a table before it', Exec(d, TTyRichInsertTable.Create(0, 1, 1)));
    k := d.Text.ParaCount - 1;
    AssertTrue('the item follows the table', d.CellAt(k) = nil);
    AssertTrue('a table at the item''s start', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(k),
      1, 1)));
    AssertTrue('a paragraph between', d.CellAt(1) = nil);
    got := d.Formats.ParaFormat(d.ParaFormatOf(1));
    AssertTrue('it is no list item', got.List.Kind = lkNone);
    AssertEquals('no indent', 0, got.LeftIndent);
    AssertEquals('no first indent', 0, got.FirstIndent);
    got := d.Formats.ParaFormat(d.ParaFormatOf(d.Text.ParaCount - 1));
    AssertTrue('the item after the tables is one still', got.List.Kind = lkBullet);
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestANewRowDoesNotRepeatTheRowNumbering;
const
  R0 = '\trowd \irow0\irowband0\ltrrow\trgaph108\trleft-108\clbrdrt\brdrs\brdrw10 \cellx2000';
  R1 = '\trowd \irow1\irowband1\lastrow \ltrrow\trgaph108\trleft-108\clbrdrt\brdrs\brdrw10 \cellx2000';
var
  b: TBytes;
  d: TTyRichDocument;
  t: TTyRichTable;
  info: TTyRtfWriteInfo;
  o: RawByteString;
begin
  b := BytesOf('{\rtf1\ansi\pard first\par' + #13#10 + R0 + #13#10 + '\pard\intbl a\cell\row' +
    #13#10 + R1 + #13#10 + '\pard\intbl b\cell\row' + #13#10 + '\pard last\par}');
  d := LoadDoc(b);
  try
    AssertTrue('a row above', Exec(d, TTyRichInsertRow.Create(TablePos(d), 0)));
    AssertTrue('a row below', Exec(d, TTyRichInsertRow.Create(TablePos(d), 3)));
    t := d.TableAt(1);
    AssertEquals('rows', 4, t.RowCount);
    AssertEquals('the new first row: the format of the row below it, not its number',
      '\trowd \ltrrow\trgaph108\trleft-108\clbrdrt\brdrs\brdrw10 \cellx2000', Txt(t.Rows[0].RawFormat));
    AssertEquals('the new last row: the format of the row above it, not its number',
      '\trowd \ltrrow\trgaph108\trleft-108\clbrdrt\brdrs\brdrw10 \cellx2000', Txt(t.Rows[3].RawFormat));
    AssertTrue('the rows of the file keep their format', SameRaw(R0, t.Rows[1].RawFormat) and
      SameRaw(R1, t.Rows[2].RawFormat));
    o := StrOf(SaveBytes(d, info));
    AssertEquals('only the new rows written from the model', 2, info.RewrittenParas);
    AssertTrue('the file''s first row as its bytes', Pos(R0 + #13#10 + '\pard\intbl a\cell\row', o) > 0);
    AssertTrue('the file''s last row as its bytes', Pos(R1 + #13#10 + '\pard\intbl b\cell\row', o) > 0);
    CheckReadBack('rows beside numbered ones', d);
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestNarrowCellsGetASmallerGap;
var
  d, back, two: TTyRichDocument;
  t: TTyRichTable;
  raw: RawByteString;
  lo: TTyRichLayouter;
  b: TTyBlockLayout;
  row: TTyRowLayout;
  i, gapPx: Integer;
begin
  d := NewDoc('x');
  lo := Layouter;
  try
    // A4 less the margins: 8306 twips, 63 cells of 131 or 132
    AssertEquals('the text width', 8306, d.TextWidthTwips);
    AssertTrue('63 columns', Exec(d, TTyRichInsertTable.Create(0, 2, 63)));
    t := d.TableAt(0);
    raw := t.Rows[0].RawFormat;
    // the largest g with 2g + 20 <= 131
    AssertEquals('the half gap', 1, Pos('\trowd\trgaph55\clbrdrt', raw));
    AssertTrue('the grid of these edges', SameRaw(TyRtfGridRowFormat(t.Rows[0].CellEdges), raw));
    gapPx := TyRichTwipsToPx(55, 96, 1.0);
    b := lo.LayoutBlock(d, 0, 600, 96, 1.0);
    try
      row := TTyRowLayout(b);
      for i := 0 to row.CellCount - 1 do
        AssertTrue(Format('cell %d: room for text', [i]),
          row.Cells[i].Right - row.Cells[i].Left - 2 * gapPx >= 0);
    finally
      b.Release;
    end;
    back := LoadDoc(SaveBytes(d));
    try
      AssertTrue('read back: the format', SameRaw(raw, back.CellAt(FirstTablePara(back)).Row.RawFormat));
      AssertEquals('read back: the boxes', RowBoxes(lo, d, 0), RowBoxes(lo, back, FirstTablePara(back)));
    finally
      back.Free;
    end;
    // a column less: the grid made again for the new edges
    AssertTrue('a column less', Exec(d, TTyRichDeleteColumn.Create(0, 0)));
    t := d.TableAt(0);
    AssertTrue('the grid of the new edges', SameRaw(TyRtfGridRowFormat(t.Rows[0].CellEdges),
      t.Rows[0].RawFormat));
    // a grid made here follows its narrowest cell through a column edit; a file's own format
    // keeps its gap
    two := LoadDoc(BytesOf('{\rtf1\ansi\pard first\par' + #13#10 + Txt(TyRtfGridRowFormat([1000, 1150])) +
      '\pard\intbl a\cell b\cell\row' + #13#10 + '\trowd\trgaph65\cellx1000\cellx1150' +
      '\pard\intbl c\cell d\cell\row' + #13#10 + '\pard last\par}'));
    try
      AssertEquals('a cell of 150 twips: a gap of 65', '\trowd\trgaph65\clbrdrt',
        Copy(Txt(two.TableAt(1).Rows[0].RawFormat), 1, 23));
      AssertTrue('the narrow column goes', Exec(two, TTyRichDeleteColumn.Create(two.Text.ParaStart(1), 1)));
      AssertTrue('the grid: Word''s gap again', SameRaw(TyRtfGridRowFormat([1000]),
        two.TableAt(1).Rows[0].RawFormat));
      AssertEquals('the file''s own format: its gap as it was', '\trowd\trgaph65\cellx1000',
        Txt(two.TableAt(1).Rows[1].RawFormat));
    finally
      two.Free;
    end;
    // wide cells keep Word's gap
    AssertEquals('wide cells', 1, Pos('\trowd\trgaph108\', TyRtfGridRowFormat([1000, 2000])));
    AssertEquals('a cell of 236 twips', 1, Pos('\trowd\trgaph108\', TyRtfGridRowFormat([236])));
    AssertEquals('a cell of 235 twips', 1, Pos('\trowd\trgaph107\', TyRtfGridRowFormat([235])));
    AssertEquals('a cell narrower than its lines', 1, Pos('\trowd\trgaph0\', TyRtfGridRowFormat([10])));
  finally
    lo.Free;
    d.Free;
  end;
end;

{ ---- the paths left ---- }

procedure TTyRichTablesTest.TestANeighbourPartWithNoUnreadParagraphIsNotWhole;
var
  d: TTyRichDocument;
  k, f, l, f2, l2: Integer;
  cmd: TTyRichReplaceAllCommand;
  before: RawByteString;
  tally: TTyRichReplaceTally;
begin
  d := LoadDoc(TablesRtf(1000, 3 shl 20));
  try
    k := CutPara(d);
    AssertTrue('a cut table', k >= 0);
    d.TableParas(k, f, l);
    // the part next to it
    if (l + 1 < d.Text.ParaCount) and (d.CellAt(l + 1) <> nil) and d.TableAt(l + 1).Cut then
      d.TableParas(l + 1, f2, l2)
    else
    begin
      AssertTrue('a part before it', (f > 0) and (d.CellAt(f - 1) <> nil) and d.TableAt(f - 1).Cut);
      d.TableParas(f - 1, f2, l2);
    end;
    AssertTrue('editable while the parts are unread', Refusal(d, rtkInsertRow, d.Text.ParaStart(k), 0) = rtrNone);
    // every paragraph of that part edited: none of it says any more whose bytes it is
    tally := Default(TTyRichReplaceTally);
    cmd := TTyRichReplaceAllCommand.Create(d, ' ', '_', [], d.Text.ParaStart(f2),
      d.Text.ParaStart(l2) + d.Text.ParaLength(l2) - d.Text.ParaStart(f2));
    cmd.AllAtOnce := True;
    cmd.Tally := @tally;
    AssertTrue('the part edited', d.Execute(cmd));
    AssertTrue('every paragraph of it', tally.Replaced >= l2 - f2 + 1);
    // (a document that parses on demand makes its objects again when it reads again: what
    // is compared is what a save writes)
    before := StrOf(SaveBytes(d));
    AssertTrue('refused: not whole', Refusal(d, rtkInsertRow, d.Text.ParaStart(k), 0) = rtrNotWhole);
    AssertTrue('refused from the edited part too', Refusal(d, rtkDeleteRow, d.Text.ParaStart(f2), 0) = rtrNotWhole);
    AssertFalse('not executed', Exec(d, TTyRichInsertRow.Create(d.Text.ParaStart(k), 0)));
    AssertTrue('nothing changed', SameRaw(before, StrOf(SaveBytes(d))));
  finally
    d.Free;
  end;
end;

type
  // gives a cut table "whole" as a range that reaches past it
  TReachingLoader = class(TTyRichParaLoader)
  public
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
    function WholeTable(ADoc: TTyRichDocument; AIndex: Integer;
      out AFirst, ALast: Integer): Boolean; override;
  end;

  TTableDocAccess = class(TTyRichDocument)
  public
    procedure Mark(AFirstPara: Integer; ATable: TTyRichTable; const ACellParas: array of Integer);
  end;

procedure TReachingLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
begin
end;

function TReachingLoader.WholeTable(ADoc: TTyRichDocument; AIndex: Integer;
  out AFirst, ALast: Integer): Boolean;
begin
  AFirst := 0;
  ALast := ADoc.Text.ParaCount - 1;
  Result := True;
end;

procedure TTableDocAccess.Mark(AFirstPara: Integer; ATable: TTyRichTable;
  const ACellParas: array of Integer);
var
  u: TTyRichUndoData;
begin
  u := MarkTable(AFirstPara, ATable, ACellParas);
  u.Free;
end;

procedure TTyRichTablesTest.TestALoadersRangeWithAParagraphOutsideATable;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  before: string;
begin
  d := NewDoc('a' + #13#10 + 'b' + #13#10 + 'c' + #13#10 + 'd');
  try
    d.InstallLoader(TReachingLoader.Create, True);
    t := TTyRichTable.Create([1000], False, True);
    t.AddRow(1);
    t.AddRow(1);
    TTableDocAccess(d).Mark(1, t, [1, 1]);
    AssertTrue('a part', d.TableAt(1).Cut);
    before := Dump(d);
    AssertTrue('a range with paragraphs in no table: not whole',
      Refusal(d, rtkInsertRow, d.Text.ParaStart(1), 0) = rtrNotWhole);
    AssertFalse('not executed', Exec(d, TTyRichDeleteRow.Create(d.Text.ParaStart(1), 0)));
    AssertEquals('nothing changed', before, Dump(d));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablesTest.TestARowWithTheTablesEdges;
var
  d: TTyRichDocument;
  t: TTyRichTable;
begin
  d := NewDoc('a' + #13#10 + 'b' + #13#10 + 'c' + #13#10 + 'd' + #13#10 + 'e');
  try
    // rows with no edges of their own: the table's
    t := TTyRichTable.Create([1000, 2500]);
    t.AddRow(2);
    t.AddRow(2);
    TTableDocAccess(d).Mark(0, t, [1, 1, 1, 1]);
    AssertEquals('no edges of their own', 0, d.TableAt(0).Rows[0].BoundaryCount);
    AssertTrue('a column at the end', Exec(d, TTyRichInsertColumn.Create(0, 2)));
    // as wide as the one left of it, 1500
    AssertEquals('the new edges', '1000,2500,4000', RowEdgesOf(d.TableAt(0).Rows[0]));
    AssertEquals('every row', '1000,2500,4000', RowEdgesOf(d.TableAt(0).Rows[1]));
    AssertEquals('the shape', 'a|b|/c|d|', TableShape(d, 0));
  finally
    d.Free;
  end;
end;

{ ---- a row named by a position ---- }

{ CRichRowAbove / CRichRowBelow: the row right above / below the row the position is in, the
  same edit as with its index, for the same reads of the table; undone and redone exactly. }
procedure TTyRichTablesTest.TestARowBesideTheRowOfAPosition;
var
  d, e: TTyRichDocument;
  r, side: Integer;
  p: TTyRichPos;
  before, after, msg: string;
  visits: Int64;
begin
  for r := 0 to 2 do
    for side := 0 to 1 do
    begin
      msg := Format('row %d, side %d', [r, side]);
      e := TableDoc(3, 2);
      d := TableDoc(3, 2);
      try
        e.TableParaVisits := 0;
        AssertTrue(msg + ': by its index', Exec(e, TTyRichInsertRow.Create(TablePos(e), r + side)));
        visits := e.TableParaVisits;
        // a position inside the row's second cell
        p := d.Text.ParaStart(1 + 2 * r + 1) + 1;
        AssertTrue(msg + ': allowed', Refusal(d, rtkInsertRow, p, CRichRowBelow) = rtrNone);
        before := Dump(d);
        d.TableParaVisits := 0;
        if side = 1 then
          AssertTrue(msg + ': below', Exec(d, TTyRichInsertRow.Create(p, CRichRowBelow)))
        else
          AssertTrue(msg + ': above', Exec(d, TTyRichInsertRow.Create(p, CRichRowAbove)));
        { (by its index from the table's first paragraph: the rows up to it; by a position: the
          position's row too, on the way to the row above it - in the check and the edit) }
        AssertTrue(msg + Format(': no more reads (%d, by its index %d)', [d.TableParaVisits,
          visits]), d.TableParaVisits <= visits + 2 * 2);
        AssertEquals(msg + ': the same table', TableShape(e, 1), TableShape(d, 1));
        after := Dump(d);
        d.Undo;
        AssertEquals(msg + ': undone', before, Dump(d));
        d.Redo;
        AssertEquals(msg + ': redone', after, Dump(d));
      finally
        d.Free;
        e.Free;
      end;
    end;
  d := TableDoc(2, 2);
  try
    AssertTrue('outside a table: no table', Refusal(d, rtkInsertRow, 0, CRichRowBelow) = rtrNoTable);
    AssertFalse('outside a table: not done', Exec(d, TTyRichInsertRow.Create(0, CRichRowAbove)));
    AssertTrue('another negative index: out of range',
      Refusal(d, rtkInsertRow, TablePos(d), -3) = rtrOutOfRange);
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichTablesTest);

end.
