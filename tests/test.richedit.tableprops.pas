unit test.richedit.tableprops;

{ The properties of a table's cells and rows (tyControls.RichEdit.TableProps): what is read
  of a file Word saved - compared with what Word itself reports of each cell -, what a save
  writes after an edit (the row made again with the words it does not know, the other rows
  as the file's bytes, the colours in the colour table), the edits over a range of cells as
  one undo step, tables with merged cells and with a nested table, rows that look alike
  sharing one record, and what an edit costs in a long table. No control, no window. The
  unit is ASCII: Chinese text is built from code points. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.TableProps,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout,
  test.richedit.layoutdevice;

type
  TTyRichTablePropsTest = class(TTestCase)
  published
    procedure TestEveryPropertyIsDecoded;
    procedure TestAnUntouchedRowKeepsItsBytes;
    procedure TestAChangedRowKeepsTheWordsItDoesNotKnow;
    procedure TestColoursGoThroughTheColourTable;
    procedure TestSetCellPropsOverARange;
    procedure TestMergedTablesTakePropertyEdits;
    procedure TestTheRowHoldingANestedTableRefuses;
    procedure TestIdenticalRowsShareOneRecord;
    procedure TestAPropertyEditCostsTheRowsItTouches;
    procedure TestRowPropertiesAndWidths;
    procedure TestARowEditLeavesTheOtherRowsAsTheyAre;
    procedure TestTheLayoutShowsWhatWasSet;
  end;

implementation

{ ---- helpers ---- }

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

function FixtureLines(const AName: string): TStringList;
begin
  Result := TStringList.Create;
  Result.LoadFromFile(FixtureDir + AName);
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

// The first paragraph of the ANth table (from 0), -1 for none.
function TablePara(ADoc: TTyRichDocument; AN: Integer): Integer;
var
  i: Integer;
  t, prev: TTyRichTable;
begin
  prev := nil;
  ADoc.BeginRead;
  try
    for i := 0 to ADoc.Text.ParaCount - 1 do
    begin
      t := ADoc.TableAt(i);
      if (t <> nil) and (t <> prev) and ((i = 0) or (ADoc.TableAt(i - 1) <> t)) then
      begin
        if AN = 0 then Exit(i);
        Dec(AN);
      end;
      prev := t;
    end;
  finally
    ADoc.EndRead;
  end;
  Result := -1;
end;

function TablePos(ADoc: TTyRichDocument; AN: Integer = 0): TTyRichPos;
begin
  Result := ADoc.Text.ParaStart(TablePara(ADoc, AN));
end;

// The start of the first paragraph of row ARow of the table at ATablePara.
function RowPos(ADoc: TTyRichDocument; ATablePara, ARow: Integer): TTyRichPos;
var
  info: TTyRichTableInfo;
  f, l: Integer;
begin
  TAssert.AssertTrue('a table', ADoc.TableInfoAt(ATablePara, info));
  TAssert.AssertTrue('a cell', ADoc.TableCellParas(ATablePara, ARow, 0, f, l));
  Result := ADoc.Text.ParaStart(f);
  if info.RowCount = 0 then Result := -1;
end;

{ 'before', an ARows x ACols table with 'rNcM' in each cell, 'after'; no history. }
function TableDoc(ARows, ACols: Integer): TTyRichDocument;
var
  r, c, f, l: Integer;
begin
  Result := NewDoc('before' + #13#10 + 'after');
  if not Result.Execute(TTyRichInsertTable.Create(Result.Text.ParaStart(1), ARows, ACols)) then
    raise Exception.Create('no table');
  for r := 0 to ARows - 1 do
    for c := 0 to ACols - 1 do
    begin
      if not Result.TableCellParas(1, r, c, f, l) then raise Exception.Create('no cell');
      if not Result.Execute(TTyRichInsertText.Create(Result.Text.ParaStart(f),
        Format('r%dc%d', [r, c]), TyRichInheritFormat, False)) then
        raise Exception.Create('no text');
    end;
  Result.ClearUndo;
end;

function NoProps: TTyRichCellProps;
begin
  Result := Default(TTyRichCellProps);
end;

function Shading(AColor: TColor): TTyRichCellProps;
begin
  Result := NoProps;
  Result.Valid := [rcpShading];
  Result.Shading := AColor;
end;

function PropsText(const P: TTyRichCellProps): string;
var
  s: TTyRichCellSide;
begin
  Result := Format('w%d sh%d va%d', [P.WidthTwips, Integer(P.Shading), Ord(P.VAlign)]);
  for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    Result := Result + Format(' b%d:%d/%d/%d p%d', [Ord(s), Ord(P.Borders[s].Style),
      P.Borders[s].WidthTwips, Integer(P.Borders[s].Color), P.Pad[s]]);
end;

// Every cell's properties of the table at ATable (rows as TableInfoAt counts them).
function AllCells(ADoc: TTyRichDocument; ATable: Integer): string;
var
  info: TTyRichTableInfo;
  r, c: Integer;
  p: TTyRichCellProps;
  pos: TTyRichPos;
begin
  Result := '';
  pos := TablePos(ADoc, ATable);
  ADoc.TableInfoAt(ADoc.Text.ParaOfPos(pos), info);
  for r := 0 to info.RowCount - 1 do
  begin
    c := 0;
    repeat
      p := ADoc.CellProps(pos, r, c);
      if p.Valid = [] then Break;
      Result := Result + Format('%d,%d %s', [r, c, PropsText(p)]) + LineEnding;
      Inc(c);
    until False;
  end;
end;

function Exec(ADoc: TTyRichDocument; ACmd: TTyRichCommand): Boolean;
begin
  Result := ADoc.Execute(ACmd);
end;

function PosOf(const ASub, AIn: RawByteString; AFrom: Integer = 1): Integer;
var
  i: Integer;
begin
  for i := AFrom to Length(AIn) - Length(ASub) + 1 do
    if CompareMem(@AIn[i], @ASub[1], Length(ASub)) then Exit(i);
  Result := 0;
end;

function StartsWith(const A, APrefix: RawByteString): Boolean;
begin
  Result := (Length(A) >= Length(APrefix)) and
    ((APrefix = '') or CompareMem(@A[1], @APrefix[1], Length(APrefix)));
end;

function EndsWith(const A, ASuffix: RawByteString): Boolean;
begin
  Result := (Length(A) >= Length(ASuffix)) and
    ((ASuffix = '') or CompareMem(@A[Length(A) - Length(ASuffix) + 1], @ASuffix[1], Length(ASuffix)));
end;

// The rows a table's row objects say (the first table of ADoc): how many distinct formats.
function DistinctFormats(ADoc: TTyRichDocument; ATablePara: Integer): Integer;
var
  t: TTyRichTable;
  seen: TList;
  i: Integer;
begin
  seen := TList.Create;
  try
    ADoc.BeginRead;
    try
      t := ADoc.TableAt(ATablePara);
      for i := 0 to t.RowCount - 1 do
        if seen.IndexOf(t.Rows[i].Format) < 0 then seen.Add(t.Rows[i].Format);
    finally
      ADoc.EndRead;
    end;
    Result := seen.Count;
  finally
    seen.Free;
  end;
end;

{ ---- what is read ---- }

// Word's line styles (WdLineStyle) as ours
function WordStyle(AStyle: Integer): TTyRichBorderStyle;
begin
  case AStyle of
    0: Result := rbsNone;
    2: Result := rbsDotted;
    3, 4: Result := rbsDashed;
    7: Result := rbsDouble;
  else
    Result := rbsSingle;
  end;
end;

// Word's colours (BGR as a TColor is, wdColorAutomatic for automatic)
function WordColor(AValue: Int64; AAuto: TColor): TColor;
begin
  if AValue = -16777216 then Result := AAuto else Result := TColor(AValue);
end;

function PtTwips(const S: string): Integer;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := Round(StrToFloat(S, fs) * 20);
end;

procedure TTyRichTablePropsTest.TestEveryPropertyIsDecoded;
var
  lines, f, b, bs: TStringList;
  d: TTyRichDocument;
  i, table, row, col, n: Integer;
  s: TTyRichCellSide;
  p: TTyRichCellProps;
  rp: TTyRichRowProps;
  pos: TTyRichPos;
  msg: string;
  full: Boolean;
  fs, ls: Integer;
begin
  lines := FixtureLines('word-table-styled.cells.txt');
  f := TStringList.Create;
  b := TStringList.Create;
  bs := TStringList.Create;
  try
    bs.Delimiter := ' ';
    bs.StrictDelimiter := True;
    f.Delimiter := #9;
    f.StrictDelimiter := True;
    b.Delimiter := '/';
    b.StrictDelimiter := True;
    for full := False to True do
    begin
      d := LoadDoc(FixtureBytes('word-table-styled.rtf'), full);
      try
        table := -1;
        n := 0;
        for i := 0 to lines.Count - 1 do
        begin
          if Copy(lines[i], 1, 9) = '# table 1' then table := 0;
          if Copy(lines[i], 1, 9) = '# table 2' then table := 1;
          if (lines[i] = '') or (lines[i][1] = '#') then Continue;
          f.DelimitedText := lines[i];
          row := StrToInt(f[0]) - 1;
          col := StrToInt(f[1]) - 1;
          pos := TablePos(d, table);
          p := d.CellProps(pos, row, col);
          msg := Format('load %d, table %d, cell %d,%d', [Ord(full), table + 1, row + 1, col + 1]);
          AssertTrue(msg + ': a cell', p.Valid <> []);
          AssertEquals(msg + ': width', PtTwips(f[2]), p.WidthTwips);
          AssertEquals(msg + ': shading', Integer(WordColor(StrToInt64(f[3]), clNone)),
            Integer(p.Shading));
          bs.DelimitedText := f[4];
          for s := Low(TTyRichCellSide) to High(TTyRichCellSide) do
          begin
            b.DelimitedText := bs[Ord(s)];
            AssertEquals(msg + Format(': border %d style', [Ord(s)]),
              Ord(WordStyle(StrToInt(b[0]))), Ord(p.Borders[s].Style));
            // (eighths of a point: 2.5 twips)
            AssertEquals(msg + Format(': border %d width', [Ord(s)]), StrToInt(b[1]) * 5 div 2,
              p.Borders[s].WidthTwips);
            AssertEquals(msg + Format(': border %d colour', [Ord(s)]),
              Integer(WordColor(StrToInt64(b[2]), clDefault)), Integer(p.Borders[s].Color));
            AssertEquals(msg + Format(': padding %d', [Ord(s)]), PtTwips(f[5 + Ord(s)]),
              p.Pad[s]);
          end;
          case StrToInt(f[9]) of
            0: AssertEquals(msg + ': at the top', Ord(rcvTop), Ord(p.VAlign));
            1: AssertEquals(msg + ': centred', Ord(rcvCenter), Ord(p.VAlign));
          else
            AssertEquals(msg + ': at the bottom', Ord(rcvBottom), Ord(p.VAlign));
          end;
          if table = 0 then
          begin
            // the cell is the one of that text
            AssertTrue(msg + ': its paragraphs', d.TableCellParas(d.Text.ParaOfPos(pos), row, col,
              fs, ls));
            AssertEquals(msg + ': its text', f[10], ParaText(d, fs));
          end;
          Inc(n);
        end;
        AssertEquals('every cell Word reports', 20, n);
        // the rows: Word's rule 0 (auto) / 1 (at least) / 2 (exactly), the table centred
        pos := TablePos(d, 0);
        rp := d.RowProps(pos, 0);
        AssertEquals('row 1: as high as its content', 0, rp.HeightTwips);
        AssertEquals('row 1: centred', Ord(rraCenter), Ord(rp.Align));
        rp := d.RowProps(pos, 1);
        AssertEquals('row 2: at least 30 pt', 600, rp.HeightTwips);
        rp := d.RowProps(pos, 2);
        AssertEquals('row 3: exactly 40 pt', -800, rp.HeightTwips);
        AssertEquals('row 3: its cells'' padding', 108, rp.DefaultPad[rcsLeft]);
        AssertEquals('no row 4', True, d.RowProps(pos, 3).Valid = []);
        AssertEquals('no cell 4', True, d.CellProps(pos, 0, 3).Valid = []);
      finally
        d.Free;
      end;
    end;
  finally
    bs.Free;
    b.Free;
    f.Free;
    lines.Free;
  end;
end;

{ ---- what a save writes ---- }

procedure TTyRichTablePropsTest.TestAnUntouchedRowKeepsItsBytes;
var
  d: TTyRichDocument;
  orig, got: RawByteString;
  p1, p2, e0: Integer;
  info: TTyRtfWriteInfo;
  b: TTyRichCellProps;
begin
  orig := StrOf(FixtureBytes('word-table-styled.rtf'));
  d := LoadDoc(BytesOf(orig));
  try
    AssertTrue('opened and saved: the file', SameBytes(BytesOf(orig), SaveBytes(d)));
    // the middle row's middle cell: a border
    b := NoProps;
    b.Valid := [rcpBorderBottom];
    b.Borders[rcsBottom] := TyRichBorder(rbsSingle, 20, clDefault);
    AssertTrue('a border', Exec(d, TTyRichSetCellProps.Create(TablePos(d), 1, 1, 1, 1, b)));
    got := StrOf(SaveBytes(d, info));
    AssertEquals('the row''s paragraphs written from the model', 3, info.RewrittenParas);
    // everything before the row (the first row with it) and after it is the file's
    p1 := PosOf('\trowd \irow1', orig);
    e0 := p1;
    while (e0 > 1) and (Copy(orig, e0, 4) <> '\row') do Dec(e0);
    p2 := PosOf('\trowd \irow2', orig);
    AssertTrue('the places', (p1 > 0) and (e0 > 1) and (p2 > p1));
    AssertTrue('the first row: the file''s bytes', StartsWith(got, Copy(orig, 1, e0 + 3)));
    AssertTrue('the last row and the rest: the file''s bytes',
      EndsWith(got, Copy(orig, p2, Length(orig) - p2 + 1)));
    AssertTrue('the row made again names its border', PosOf('\clbrdrb\brdrs\brdrw20', got) > 0);
    // and undone, the file again
    d.Undo;
    AssertTrue('undone: the file', SameBytes(BytesOf(orig), SaveBytes(d)));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePropsTest.TestAChangedRowKeepsTheWordsItDoesNotKnow;
const
  Known: array[0..13] of string = ('\irow1', '\irowband1', '\ltrrow', '\ts11',
    '\trftsWidth1', '\trftsWidthB3', '\tblrsid12601538', '\tblind0', '\tblindtype3',
    '\trbrdrh\brdrdot\brdrw10\brdrcf2', '\clftsWidth3\clwWidth1600', '\cltxlrtb',
    '\clpadfl3', '\trpaddfr3');
var
  d, back: TTyRichDocument;
  orig, got, def: RawByteString;
  before, after: string;
  i, a, z: Integer;
  pos: TTyRichPos;
  want: TTyRichCellProps;
begin
  orig := StrOf(FixtureBytes('word-table-styled.rtf'));
  d := LoadDoc(BytesOf(orig));
  try
    before := AllCells(d, 0);
    pos := TablePos(d);
    AssertTrue('a shading', Exec(d, TTyRichSetCellProps.Create(pos, 1, 0, 1, 0,
      Shading(RGBToColor($99, $CC, $FF)))));
    AssertEquals('one step', 1, d.UndoDepth);
    want := d.CellProps(pos, 1, 0);
    AssertEquals('its shading', Integer(RGBToColor($99, $CC, $FF)), Integer(want.Shading));
    after := AllCells(d, 0);
    got := StrOf(SaveBytes(d));
    // the row's definition as written: from its \trowd to its first paragraph
    a := PosOf('\trowd \irow1', got);
    AssertTrue('the row made again', a > 0);
    z := PosOf('\pard', got, a);
    def := Copy(got, a, z - a);
    for i := 0 to High(Known) do
      AssertTrue(Format('the word it does not know, %s, is in the row: %s', [Known[i], def]),
        PosOf(RawByteString(Known[i]), def) > 0);
    AssertTrue('Word''s padding words as they were (left as \clpadt)',
      PosOf('\clpadl100\clpadt200\clpadb100\clpadr200', def) > 0);
    // the other rows: the file's (the header has the new colour)
    a := PosOf('\trowd \irow0', orig);
    z := PosOf('\trowd \irow1', orig);
    while (z > a) and (Copy(orig, z, 4) <> '\row') do Dec(z);
    AssertTrue('the row before', PosOf(Copy(orig, a, z + 4 - a), got) > 0);
    AssertTrue('the rows after', EndsWith(got, Copy(orig, PosOf('\trowd \irow2', orig),
      Length(orig))));
    // read back: the very properties, every cell
    back := LoadDoc(BytesOf(got));
    try
      AssertEquals('read back, every cell', after, AllCells(back, 0));
      AssertEquals('read back, the merged table too', AllCells(d, 1), AllCells(back, 1));
    finally
      back.Free;
    end;
    // what changed is the one shading
    AssertTrue('only the one shading changed', before <> after);
    d.Undo;
    AssertEquals('undone', before, AllCells(d, 0));
    AssertTrue('undone: the file', SameBytes(BytesOf(orig), SaveBytes(d)));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePropsTest.TestColoursGoThroughTheColourTable;
var
  d, back: TTyRichDocument;
  orig, got, tbl: RawByteString;
  p: TTyRichCellProps;
  pos: TTyRichPos;
  a, z: Integer;
begin
  // a file's table: the new colour at the end of the file's colour table
  orig := StrOf(FixtureBytes('word-table-styled.rtf'));
  d := LoadDoc(BytesOf(orig));
  try
    pos := TablePos(d);
    p := NoProps;
    p.Valid := [rcpShading, rcpBorderTop];
    p.Shading := RGBToColor(18, 52, 86);
    p.Borders[rcsTop] := TyRichBorder(rbsDashed, 15, RGBToColor(255, 0, 0));
    AssertTrue('a shading and a border', Exec(d, TTyRichSetCellProps.Create(pos, 0, 2, 0, 2, p)));
    got := StrOf(SaveBytes(d));
    a := PosOf('{\colortbl', got);
    z := PosOf('}', got, a);
    tbl := Copy(got, a, z - a);
    AssertTrue('the new colour is in the table', PosOf('\red18\green52\blue86;', tbl) > 0);
    AssertEquals('one colour more', Length(Copy(orig, a, PosOf('}', orig, a) - a)) +
      Length('\red18\green52\blue86;'), Length(tbl));
    // (red is the file's colour 6 already)
    AssertTrue('a colour the file has: its number', PosOf('\clbrdrt\brdrdash\brdrw15\brdrcf6', got) > 0);
    AssertTrue('the shading: the new number', PosOf('\clcbpat23', got) > 0);
    back := LoadDoc(BytesOf(got));
    try
      p := back.CellProps(TablePos(back), 0, 2);
      AssertEquals('read back: the shading', Integer(RGBToColor(18, 52, 86)), Integer(p.Shading));
      AssertEquals('read back: the border''s colour', Integer(RGBToColor(255, 0, 0)),
        Integer(p.Borders[rcsTop].Color));
      AssertEquals('read back: the border''s style', Ord(rbsDashed), Ord(p.Borders[rcsTop].Style));
    finally
      back.Free;
    end;
  finally
    d.Free;
  end;
  // a document made here: a colour table of its own
  d := TableDoc(2, 2);
  try
    AssertTrue('a shading', Exec(d, TTyRichSetCellProps.Create(TablePos(d), 1, 1, 1, 1,
      Shading(RGBToColor(1, 2, 3)))));
    got := StrOf(SaveBytes(d));
    AssertTrue('in the colour table', PosOf('\red1\green2\blue3;', got) > 0);
    back := LoadDoc(BytesOf(got));
    try
      AssertEquals('read back', Integer(RGBToColor(1, 2, 3)),
        Integer(back.CellProps(TablePos(back), 1, 1).Shading));
      AssertEquals('read back: the cell beside it', Integer(clNone),
        Integer(back.CellProps(TablePos(back), 1, 0).Shading));
    finally
      back.Free;
    end;
  finally
    d.Free;
  end;
end;

{ ---- edits ---- }

procedure TTyRichTablePropsTest.TestSetCellPropsOverARange;
var
  d: TTyRichDocument;
  bytes0, bytes1: TBytes;
  before, after: string;
  p, q: TTyRichCellProps;
  pos: TTyRichPos;
  r, c: Integer;
  inside: Boolean;
begin
  d := TableDoc(4, 3);
  try
    pos := TablePos(d);
    bytes0 := SaveBytes(d);
    before := AllCells(d, 0);
    p := NoProps;
    p.Valid := [rcpShading, rcpBorderBottom, rcpPadLeft, rcpVAlign];
    p.Shading := clYellow;
    p.Borders[rcsBottom] := TyRichBorder(rbsDouble, 30, clBlue);
    p.Pad[rcsLeft] := 200;
    p.VAlign := rcvBottom;
    AssertTrue('a rectangle', Exec(d, TTyRichSetCellProps.Create(pos, 1, 0, 2, 1, p)));
    AssertEquals('one step', 1, d.UndoDepth);
    for r := 0 to 3 do
      for c := 0 to 2 do
      begin
        q := d.CellProps(pos, r, c);
        inside := (r in [1, 2]) and (c in [0, 1]);
        AssertEquals(Format('cell %d,%d: shading', [r, c]), inside, q.Shading = clYellow);
        AssertEquals(Format('cell %d,%d: bottom', [r, c]), inside, q.Borders[rcsBottom].Style = rbsDouble);
        AssertEquals(Format('cell %d,%d: padding', [r, c]), inside, q.Pad[rcsLeft] = 200);
        AssertEquals(Format('cell %d,%d: alignment', [r, c]), inside, q.VAlign = rcvBottom);
        // what was not named stays
        AssertEquals(Format('cell %d,%d: the top', [r, c]), Ord(rbsSingle), Ord(q.Borders[rcsTop].Style));
      end;
    after := AllCells(d, 0);
    bytes1 := SaveBytes(d);
    d.Undo;
    AssertEquals('undone: every cell', before, AllCells(d, 0));
    AssertTrue('undone: the bytes', SameBytes(bytes0, SaveBytes(d)));
    d.Redo;
    AssertEquals('redone', after, AllCells(d, 0));
    AssertTrue('redone: the bytes', SameBytes(bytes1, SaveBytes(d)));
    // a cell's own padding taken away: the row's again
    p := NoProps;
    p.Valid := [rcpPadLeft];
    p.Pad[rcsLeft] := -1;
    AssertTrue('no padding of its own', Exec(d, TTyRichSetCellProps.Create(pos, 1, 0, 1, 0, p)));
    AssertEquals('the row''s', 108, d.CellProps(pos, 1, 0).Pad[rcsLeft]);
    // refused: out of range, nothing changes
    AssertEquals('row out of range', Ord(rtrOutOfRange), Ord(d.TablePropsRefusal(
      TTyRichSetCellProps(TTyRichSetCellProps.Create(pos, 3, 0, 4, 0, p)).Edit)));
    AssertFalse('refused', Exec(d, TTyRichSetCellProps.Create(pos, 0, 3, 0, 3, p)));
    AssertFalse('no table', Exec(d, TTyRichSetCellProps.Create(0, 0, 0, 0, 0, p)));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePropsTest.TestMergedTablesTakePropertyEdits;
var
  d, back: TTyRichDocument;
  orig, got: RawByteString;
  pos: TTyRichPos;
  p: TTyRichCellProps;
  rp: TTyRichRowProps;
begin
  orig := StrOf(FixtureBytes('word-table-styled.rtf'));
  d := LoadDoc(BytesOf(orig));
  try
    // the second table: a wide cell and a cell over two rows
    pos := TablePos(d, 1);
    AssertTrue('its structure stays locked', TTyRichInsertRow.Create(pos, 0).Refusal(d) =
      rtrMergedCells);
    AssertTrue('a shading', Exec(d, TTyRichSetCellProps.Create(pos, 1, 0, 2, 3, Shading(clAqua))));
    AssertEquals('the merged cell''s first row', Integer(clAqua), Integer(d.CellProps(pos, 1, 0).Shading));
    AssertEquals('the merged cell''s second row', Integer(clAqua), Integer(d.CellProps(pos, 2, 0).Shading));
    rp := Default(TTyRichRowProps);
    rp.Valid := [rrpHeight];
    rp.HeightTwips := 500;
    AssertTrue('a row height', Exec(d, TTyRichSetRowProps.Create(pos, 0, 0, rp)));
    p := NoProps;
    p.Valid := [rcpWidth];
    p.WidthTwips := 3000;
    AssertFalse('a width: refused', Exec(d, TTyRichSetCellProps.Create(pos, 0, 0, 0, 0, p)));
    AssertEquals('a width: why', Ord(rtrMergedCells),
      Ord(TTyRichSetCellProps(TTyRichSetCellProps.Create(pos, 0, 0, 0, 0, p)).Refusal(d)));
    got := StrOf(SaveBytes(d));
    AssertTrue('the merge words stay', (PosOf('\clvmgf', got) > 0) and (PosOf('\clvmrg', got) > 0));
    back := LoadDoc(BytesOf(got));
    try
      AssertEquals('read back: every cell', AllCells(d, 1), AllCells(back, 1));
      AssertEquals('read back: the height', 500, back.RowProps(TablePos(back, 1), 0).HeightTwips);
      AssertEquals('read back: the first table', AllCells(d, 0), AllCells(back, 0));
    finally
      back.Free;
    end;
    d.Undo;
    d.Undo;
    AssertTrue('undone: the file', SameBytes(BytesOf(orig), SaveBytes(d)));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePropsTest.TestTheRowHoldingANestedTableRefuses;
var
  d, back: TTyRichDocument;
  orig, got: RawByteString;
  pos: TTyRichPos;
  t: TTyRichTable;
  r, nested: Integer;
begin
  orig := StrOf(FixtureBytes('word-table-merged.rtf'));
  d := LoadDoc(BytesOf(orig));
  try
    pos := TablePos(d);
    nested := -1;
    d.BeginRead;
    try
      t := d.TableAt(d.Text.ParaOfPos(pos));
      for r := 0 to t.RowCount - 1 do
        if t.Rows[r].HoldsNestedTable then nested := r;
    finally
      d.EndRead;
    end;
    AssertTrue('a row with a nested table', nested > 0);
    AssertEquals('that row refuses', Ord(rtrNestedTable), Ord(TTyRichSetCellProps(
      TTyRichSetCellProps.Create(pos, nested, 0, nested, 0, Shading(clLime))).Refusal(d)));
    AssertFalse('nothing changes', Exec(d, TTyRichSetCellProps.Create(pos, 0, 0, nested, 0,
      Shading(clLime))));
    AssertEquals('nothing in the history', 0, d.UndoDepth);
    // the other rows take it
    AssertTrue('the first row', Exec(d, TTyRichSetCellProps.Create(pos, 0, 0, 0, 0, Shading(clLime))));
    got := StrOf(SaveBytes(d));
    AssertTrue('the nested table''s words are there', (PosOf('\nestrow', got) > 0) and
      (PosOf('\nesttableprops', got) > 0));
    back := LoadDoc(BytesOf(got));
    try
      AssertEquals('read back', Integer(clLime), Integer(back.CellProps(TablePos(back), 0, 0).Shading));
      AssertEquals('read back: the rest', AllCells(d, 0), AllCells(back, 0));
    finally
      back.Free;
    end;
    d.Undo;
    AssertTrue('undone: the file', SameBytes(BytesOf(orig), SaveBytes(d)));
  finally
    d.Free;
  end;
end;

{ ---- what it costs ---- }

procedure TTyRichTablePropsTest.TestIdenticalRowsShareOneRecord;
const
  Rows = 10000;
var
  d, back: TTyRichDocument;
  pool: Integer;
  s: RawByteString;
  i: Integer;
begin
  pool := TyRichRowFormatCount;
  d := NewDoc('before' + #13#10 + 'after');
  try
    AssertTrue('a long table', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(1), Rows, 3)));
    AssertEquals('one record for its rows', 1, DistinctFormats(d, 1));
    // read from a file: once more one
    back := LoadDoc(SaveBytes(d));
    try
      AssertEquals('read: one record', 1, DistinctFormats(back, 1));
    finally
      back.Free;
    end;
    // one changed: two kinds, two records
    AssertTrue('a shading', Exec(d, TTyRichSetCellProps.Create(d.Text.ParaStart(1), 7, 1, 7, 1,
      Shading(clRed))));
    AssertEquals('two records', 2, DistinctFormats(d, 1));
    AssertTrue('the pool holds as many as there are kinds', TyRichRowFormatCount <= pool + 2);
  finally
    d.Free;
  end;
  // Word numbers its rows (\irowN): bytes of their own, one look
  s := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}{\colortbl;\red255\green0\blue0;}' + #13#10;
  for i := 0 to 1999 do
    s := s + Format('\trowd \irow%d\irowband%d\trgaph108\trleft-108\clbrdrt\brdrs\brdrw10\brdrcf1 ' +
      '\clcbpat1\cellx2000\cellx4000\pard\intbl a\cell b\cell\row', [i, i]) + #13#10;
  s := s + '\pard after\par}';
  d := LoadDoc(BytesOf(s));
  try
    AssertEquals('2000 numbered rows: one record', 1, DistinctFormats(d, 0));
    AssertEquals('their shading', Integer(clRed), Integer(d.CellProps(0, 1999, 0).Shading));
    AssertEquals('the other cell has none', Integer(clNone), Integer(d.CellProps(0, 1999, 1).Shading));
  finally
    d.Free;
  end;
  AssertEquals('the pool lets go of them', pool, TyRichRowFormatCount);
end;

procedure TTyRichTablePropsTest.TestAPropertyEditCostsTheRowsItTouches;
const
  Rows = 10000;
var
  d: TTyRichDocument;
  k: Integer;
  pos: TTyRichPos;
  bytes: TBytes;
  rp: TTyRichRowProps;
  info: TTyRichTableInfo;
begin
  d := NewDoc('before' + #13#10 + 'after');
  try
    AssertTrue('a long table', Exec(d, TTyRichInsertTable.Create(d.Text.ParaStart(1), Rows, 3)));
    k := 1 + 3 * (Rows div 2);
    pos := d.Text.ParaStart(k);
    d.TableParaVisits := 0;
    d.TableEditSteps := 0;
    AssertTrue('a cell of the middle row', Exec(d, TTyRichSetCellProps.Create(pos, Rows div 2, 1,
      Rows div 2, 1, Shading(clRed))));
    { the check and the edit each read the row's three paragraphs and the one on either side
      (and the one at the position once more); the cells given: the row once more }
    AssertTrue(Format('%d paragraph visits for one cell in %d rows', [d.TableParaVisits, Rows]),
      d.TableParaVisits <= 3 * 3 + 6);
    AssertTrue(Format('%d steps', [d.TableEditSteps]), d.TableEditSteps <= 8);
    AssertTrue('the step keeps the row', d.UndoStep.MemSize < 4096);
    AssertEquals('set', Integer(clRed), Integer(d.CellProps(pos, Rows div 2, 1).Shading));
    // a query: the paragraph at the position only
    d.TableParaVisits := 0;
    rp := d.RowProps(pos, 0);
    AssertTrue('a row''s properties', rp.Valid <> []);
    AssertEquals('a query reads one paragraph', 1, d.TableParaVisits);
    bytes := SaveBytes(d);
  finally
    d.Free;
  end;
  { Read from that file, parsed on demand: a table bigger than the reader parses at once is
    given in parts - one part's rows are counted in it, and an edit reads no more than its
    part. }
  d := LoadDoc(bytes);
  try
    pos := d.Text.ParaStart(k);
    AssertTrue('read: a part of the table', d.TableAt(k).Cut);
    AssertTrue('read: its row', d.TableInfoAt(k, info));
    AssertTrue('read: a part', info.RowCount < Rows);
    d.TableParaVisits := 0;
    AssertTrue('read: a cell of the part', Exec(d, TTyRichSetCellProps.Create(pos,
      info.Row, 0, info.Row, 0, Shading(clBlue))));
    AssertTrue(Format('read: %d paragraph visits, not the table''s', [d.TableParaVisits]),
      d.TableParaVisits <= 3 * (info.Last - info.First + 3));
    AssertEquals('read: the earlier one', Integer(clRed), Integer(d.CellProps(pos, info.Row, 1).Shading));
    AssertEquals('read: the new one', Integer(clBlue), Integer(d.CellProps(pos, info.Row, 0).Shading));
  finally
    d.Free;
  end;
  // a table of a file the reader parses at once: as one made here
  d := TableDoc(1000, 3);
  try
    bytes := SaveBytes(d);
  finally
    d.Free;
  end;
  d := LoadDoc(bytes);
  try
    k := 1 + 3 * 500;
    pos := d.Text.ParaStart(k);
    AssertFalse('read whole', d.TableAt(k).Cut);
    d.TableParaVisits := 0;
    AssertTrue('read: a cell of the middle row', Exec(d, TTyRichSetCellProps.Create(pos,
      500, 2, 500, 2, Shading(clBlue))));
    AssertTrue(Format('read: %d paragraph visits', [d.TableParaVisits]),
      d.TableParaVisits <= 3 * 3 + 6);
    AssertEquals('read: set', Integer(clBlue), Integer(d.CellProps(pos, 500, 2).Shading));
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePropsTest.TestRowPropertiesAndWidths;
var
  d, back: TTyRichDocument;
  pos: TTyRichPos;
  rp: TTyRichRowProps;
  p: TTyRichCellProps;
  w0, w1, w2: Integer;
begin
  d := TableDoc(3, 3);
  try
    pos := TablePos(d);
    w0 := d.CellProps(pos, 1, 0).WidthTwips;
    w1 := d.CellProps(pos, 1, 1).WidthTwips;
    w2 := d.CellProps(pos, 1, 2).WidthTwips;
    p := NoProps;
    p.Valid := [rcpWidth];
    p.WidthTwips := 1000;
    AssertTrue('a width', Exec(d, TTyRichSetCellProps.Create(pos, 1, 1, 1, 1, p)));
    AssertEquals('the cell before stays', w0, d.CellProps(pos, 1, 0).WidthTwips);
    AssertEquals('the cell', 1000, d.CellProps(pos, 1, 1).WidthTwips);
    AssertEquals('the cell after moves, as wide as it was', w2, d.CellProps(pos, 1, 2).WidthTwips);
    AssertEquals('another row stays', w1, d.CellProps(pos, 0, 1).WidthTwips);
    rp := Default(TTyRichRowProps);
    rp.Valid := [rrpHeight, rrpAlign, rrpLeft, rrpPad];
    rp.HeightTwips := -720;
    rp.Align := rraRight;
    rp.LeftTwips := 300;
    rp.DefaultPad[rcsLeft] := 50;
    rp.DefaultPad[rcsTop] := 40;
    rp.DefaultPad[rcsRight] := -1;
    rp.DefaultPad[rcsBottom] := 30;
    AssertTrue('the rows', Exec(d, TTyRichSetRowProps.Create(pos, 0, 2, rp)));
    rp := d.RowProps(pos, 2);
    AssertEquals('exactly', -720, rp.HeightTwips);
    AssertEquals('at the right', Ord(rraRight), Ord(rp.Align));
    AssertEquals('left', 300, rp.LeftTwips);
    AssertEquals('pad left', 50, rp.DefaultPad[rcsLeft]);
    AssertEquals('pad right as it was', 108, rp.DefaultPad[rcsRight]);
    AssertEquals('the cells move with the row: as wide', w0, d.CellProps(pos, 2, 0).WidthTwips);
    AssertEquals('a cell takes the row''s padding', 40, d.CellProps(pos, 2, 0).Pad[rcsTop]);
    back := LoadDoc(SaveBytes(d));
    try
      AssertEquals('read back: every cell', AllCells(d, 0), AllCells(back, 0));
      rp := back.RowProps(TablePos(back), 1);
      AssertEquals('read back: height', -720, rp.HeightTwips);
      AssertEquals('read back: left', 300, rp.LeftTwips);
      AssertEquals('read back: align', Ord(rraRight), Ord(rp.Align));
      AssertEquals('read back: pad bottom', 30, rp.DefaultPad[rcsBottom]);
    finally
      back.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRichTablePropsTest.TestARowEditLeavesTheOtherRowsAsTheyAre;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  r0, r2: TTyRichRow;
  before, after: TTyRichCellProps;
  pos: TTyRichPos;
begin
  d := TableDoc(3, 2);
  try
    pos := TablePos(d);
    d.BeginRead;
    try
      t := d.TableAt(1);
      r0 := t.Rows[0];
      r2 := t.Rows[2];
    finally
      d.EndRead;
    end;
    before := d.CellProps(pos, 1, 0);
    AssertTrue('a shading', Exec(d, TTyRichSetCellProps.Create(pos, 1, 0, 1, 0, Shading(clRed))));
    d.BeginRead;
    try
      AssertTrue('the same table object', d.TableAt(1) = t);
      AssertTrue('the rows around it: the same objects', (t.Rows[0] = r0) and (t.Rows[2] = r2));
      AssertTrue('the row: a new one, in its place', t.Rows[1].Edited and (t.Rows[1].Index = 1));
      AssertTrue('its paragraphs have it', d.CellAt(3).Row = t.Rows[1]);
    finally
      d.EndRead;
    end;
    // an insert of a row beside it, and the one beside that: the rows are the document's
    AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(pos, 2)));
    after := d.CellProps(pos, 2, 0);
    AssertEquals('the new row looks like the one above it', Integer(clRed), Integer(after.Shading));
    AssertEquals('the next row is the old row 2', Integer(clNone), Integer(d.CellProps(pos, 3, 0).Shading));
    d.Undo;
    d.Undo;
    AssertEquals('undone', PropsText(before), PropsText(d.CellProps(pos, 1, 0)));
    d.BeginRead;
    try
      AssertTrue('undone: the very rows', (t.Rows[0] = r0) and (t.Rows[2] = r2) and
        not t.Rows[1].Edited and (t.RowCount = 3));
    finally
      d.EndRead;
    end;
    // a plain delete takes a row away: the next edit of rows puts the table's rows right
    AssertTrue('a plain delete of row 1', Exec(d, TTyRichDelete.Create(d.Text.ParaStart(3),
      d.Text.ParaStart(5) - d.Text.ParaStart(3))));
    AssertEquals('the object keeps the row for now', 3, t.RowCount);
    AssertTrue('a row', Exec(d, TTyRichInsertRow.Create(pos, 2)));
    d.BeginRead;
    try
      AssertTrue('still the same table object', d.TableAt(1) = t);
      AssertTrue('its rows: those with paragraphs, the new one last', (t.RowCount = 3) and
        (t.Rows[0] = r0) and (t.Rows[1] = r2) and (t.Rows[2].Index = 2));
    finally
      d.EndRead;
    end;
    d.Undo;
    d.BeginRead;
    try
      AssertTrue('undone: the rows as the delete left them', (t.RowCount = 3) and (t.Rows[1].Index = 1) and
        (t.Rows[2] = r2) and (r2.Index = 2));
    finally
      d.EndRead;
    end;
  finally
    d.Free;
  end;
end;

{ The cell boxes of the row block paragraph APara is in: their lines and the alignment of
  their content. }
function Boxes(ADoc: TTyRichDocument; APara: Integer): string;
var
  lay: TTyRichLayouter;
  b: TTyBlockLayout;
  row: TTyRowLayout;
  i: Integer;
  s: TTyRowCellSide;
begin
  Result := '';
  lay := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  try
    b := lay.LayoutBlock(ADoc, APara, 600, 96, 1.0);
    try
      TAssert.AssertTrue('a row', b is TTyRowLayout);
      row := TTyRowLayout(b);
      for i := 0 to row.CellCount - 1 do
      begin
        Result := Result + Format('[%d..%d va%d', [row.Cells[i].Left, row.Cells[i].Right,
          Ord(row.Cells[i].VAlign)]);
        for s := Low(TTyRowCellSide) to High(TTyRowCellSide) do
          if s in row.Cells[i].Sides then Result := Result + Format(' %d:%d', [Ord(s), row.Cells[i].LinePx[s]]);
        Result := Result + ']';
      end;
    finally
      b.Release;
    end;
  finally
    lay.Free;
  end;
end;

procedure TTyRichTablePropsTest.TestTheLayoutShowsWhatWasSet;
var
  d: TTyRichDocument;
  before, after: string;
  p: TTyRichCellProps;
begin
  d := TableDoc(2, 2);
  try
    before := Boxes(d, 1);
    p := NoProps;
    p.Valid := [rcpBorderTop, rcpVAlign];
    p.Borders[rcsTop] := TyRichBorder(rbsSingle, 60);
    p.VAlign := rcvCenter;
    AssertTrue('a border and an alignment', Exec(d, TTyRichSetCellProps.Create(TablePos(d), 0, 0,
      0, 0, p)));
    after := Boxes(d, 1);
    // (60 twips at 96 pixels an inch: 4 pixels; the line made here: 1)
    AssertTrue('the cell''s top line, before: ' + before, Pos('[0..', before) = 1);
    AssertTrue('the cell''s top line, after: ' + after, Pos(' 1:4', after) > 0);
    AssertTrue('the content centred: ' + after, Pos('va1', after) > 0);
    AssertTrue('the other cell as it was: ' + after, Pos(Copy(before, Pos('][', before) + 1, MaxInt),
      after) > 0);
    d.Undo;
    AssertEquals('undone', before, Boxes(d, 1));
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichTablePropsTest);
end.
