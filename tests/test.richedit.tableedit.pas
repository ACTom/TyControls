unit test.richedit.tableedit;

{ Tables through TTyRichEdit: Tab and Shift+Tab from cell to cell and Tab's new row at the end
  of the table a person sees; the table actions (InsertTable, InsertRow, InsertColumn,
  DeleteRow, DeleteColumn, DeleteTable), where each leaves the caret and what its undo and
  redo put back; their refusals, told in the control's words; the Can... answers an action's
  Update asks for, and what they cost; tables of a file read on demand; the caret's keys,
  the view and the paths that stay as they were on a table an action changed.

  Headless, on the editor's probe (TEditProbe of test.richedit.edit: the test device, the
  clipboard double, the counters). No window, no system clipboard, no input method. Every
  bound is a count, never a time (the times are the performance suite's). The unit is
  ASCII. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.Layout,
  tyControls.RichEdit, test.richedit.control, test.richedit.edit;

type
  TTyRichTableEditTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TEditProbe;
    FSelChanges: Integer;
    // what an action asked from a save's progress handler did
    FSaveCalls, FSaveDone, FSaveRefused: Integer;
    FSaveReason: string;
    procedure SelChanged(Sender: TObject);
    procedure ActWhileSaving(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function NewProbe: TEditProbe;
    procedure LoadInto(AProbe: TEditProbe; const ABytes: TBytes; AFinish: Boolean = True);
    procedure LoadRtf(const S: RawByteString);
    procedure Press(AKey: Word; AShift: TShiftState = []);
    procedure ResetEvents;
    procedure PaintAll(AProbe: TEditProbe);
    procedure CheckSel(const AWhat: string; AStart, ALength: TTyRichPos);
    procedure CheckRefused(const AWhat: string; AResult: Boolean; const AReason: string);
    procedure CheckLikeFresh(const AWhat: string);
    procedure CheckCaretShown(const AWhat: string);
    procedure LongTable(ARows: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // Tab
    procedure TestTabMovesBetweenCellsAndAddsARowAtTheEnd;
    procedure TestTabPassesOverMergedCellsAndRefusesARowThere;
    procedure TestTabGoesOnIntoTablesThatTouch;
    procedure TestTabOutsideATableAndWithoutWantTabs;
    procedure TestTabWithReadOnlyMovesAndAddsNothing;
    procedure TestATabThatMovesReadsNoTable;
    // the actions
    procedure TestInsertTableAtTheCaretAndAtASelection;
    procedure TestInsertRowAndColumnOnEitherSide;
    procedure TestDeleteRowsAndColumnsTheSelectionTouches;
    procedure TestDeleteTable;
    procedure TestUndoAndRedoOfEachActionPlaceTheSelection;
    procedure TestEveryRefusalIsToldWithItsReason;
    // what an action's Update asks
    procedure TestTheCanFunctionsAnswerAsTheActions;
    procedure TestTheCanFunctionsAnswerFromWhatTheyFound;
    // tables of a file read on demand
    procedure TestTablesOfAFileReadOnDemand;
    procedure TestTheCanFunctionsReadNoUnreadPartOfAFile;
    // the caret, the view and the other paths after an action
    procedure TestCaretKeysAfterStructureEdits;
    procedure TestTheViewIsAFreshControlsAfterEachAction;
    procedure TestARowEditLaysOutOnlyTheRowsItChanged;
    procedure TestThePathsThatStayAsTheyWereOnAChangedTable;
    // which cells a selection takes, which paragraph a caret stands for, the edges
    procedure TestDeleteColumnTakesTheColumnOfEveryCellCovered;
    procedure TestTheCaretStandsForOneParagraphForEveryAction;
    procedure TestTheTableKeysAndActionsAtTheEdges;
    procedure TestSeveralColumnsGoFromTheirOwnTable;
    procedure TestWholeRowsOfTablesThatTouch;
    procedure TestTheAnswersHoldNoTableOfAnOldContent;
  end;

implementation

const
  BS = '\';

{ ---- helpers ---- }

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function FixtureFile(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): string;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
end;

function FirstTablePara(ADoc: TTyRichDocument): Integer;
begin
  for Result := 0 to ADoc.Text.ParaCount - 1 do
    if ADoc.CellAt(Result) <> nil then Exit;
  Result := -1;
end;

{ The table paragraph APara is in as text: rows parted by '/', cells by '|', a cell's
  paragraphs by '+'. '' outside a table. }
function Shape(ADoc: TTyRichDocument; APara: Integer): string;
var
  info: TTyRichTableInfo;
  k, e, ci, j: Integer;
  row: TTyRichRow;
  first: Boolean;
begin
  Result := '';
  if (APara < 0) or not ADoc.TableInfoAt(APara, info) then Exit;
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
      end;
      k := e + 1;
    end;
  finally
    ADoc.EndRead;
  end;
end;

function CellDef(ARight: Integer; const AWords: RawByteString = ''): RawByteString;
begin
  Result := AWords + BS + 'clbrdrt' + BS + 'brdrs' + BS + 'brdrw10 ' + BS + 'clbrdrl' + BS +
    'brdrs' + BS + 'brdrw10 ' + BS + 'clbrdrb' + BS + 'brdrs' + BS + 'brdrw10 ' + BS + 'clbrdrr' +
    BS + 'brdrs' + BS + 'brdrw10 ' + BS + 'cellx' + IntToStr(ARight);
end;

function Head: RawByteString;
begin
  Result := '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' +
    #13#10 + BS + 'pard' + BS + 'f0 before' + BS + 'par' + #13#10;
end;

{ A row of the cells' texts (AWords: each cell's own words before its borders). }
function RowRtf(const ATexts: array of string; const AWords: array of RawByteString): RawByteString;
var
  c: Integer;
begin
  Result := BS + 'trowd' + BS + 'trgaph108';
  for c := 0 to High(ATexts) do
    if c <= High(AWords) then Result := Result + CellDef(1500 * (c + 1), AWords[c])
    else Result := Result + CellDef(1500 * (c + 1));
  Result := Result + BS + 'pard' + BS + 'intbl ';
  for c := 0 to High(ATexts) do Result := Result + ATexts[c] + BS + 'cell ';
  Result := Result + BS + 'row' + #13#10;
end;

{ 'before', an ARows x ACols table with 'rRcC' in each cell (empty at the cell numbers of
  AEmpty, counted row by row), 'after'. }
function TableRtf(ARows, ACols: Integer; const AEmpty: array of Integer): RawByteString;
var
  r, c, i: Integer;
  texts: array of string;
  empty: Boolean;
begin
  Result := Head;
  texts := nil;
  SetLength(texts, ACols);
  for r := 0 to ARows - 1 do
  begin
    for c := 0 to ACols - 1 do
    begin
      empty := False;
      for i := 0 to High(AEmpty) do
        if AEmpty[i] = r * ACols + c then empty := True;
      if empty then texts[c] := '' else texts[c] := Format('r%dc%d', [r, c]);
    end;
    Result := Result + RowRtf(texts, []);
  end;
  Result := Result + BS + 'pard after' + BS + 'par' + #13#10 + '}';
end;

{ Two rows of three cells, the second cell of the first merged into the first. }
function MergedRtf: RawByteString;
begin
  Result := Head + RowRtf(['a', '', 'c'], [BS + 'clmgf', BS + 'clmrg']) +
    RowRtf(['d', 'e', 'f'], []) + BS + 'pard after' + BS + 'par' + #13#10 + '}';
end;

// Rows of two and of three cells.
function IrregularRtf: RawByteString;
begin
  Result := Head + RowRtf(['a', 'b'], []) + RowRtf(['c', 'd', 'e'], []) + BS + 'pard after' +
    BS + 'par' + #13#10 + '}';
end;

// 'before', a 1 x 2 table, 'mid', a 2 x 2 table, 'after'.
function TwoTablesRtf: RawByteString;
begin
  Result := Head + RowRtf(['a0', 'a1'], []) + BS + 'pard mid' + BS + 'par' + #13#10 +
    RowRtf(['b0', 'b1'], []) + RowRtf(['b2', 'b3'], []) + BS + 'pard after' + BS + 'par' +
    #13#10 + '}';
end;

{ Tables of ARows rows (3 cells: 't<table> r<row> a', 'r<row> b', 'r<row> c'), a paragraph
  between each two, until the file is ATarget bytes; ABigRows > 0: one table of that many rows
  half way. What a reader that parses on demand gives in parts. }
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
      Add(Format(BS + 'trowd' + BS + 'trgaph108' + BS + 'cellx2400' + BS + 'cellx4800' + BS +
        'cellx7200' + #13#10 + BS + 'pard' + BS + 'intbl t%d r%d a' + BS + 'cell r%d b' + BS +
        'cell r%d c' + BS + 'cell' + BS + 'row' + #13#10, [ATable, r, r, r]));
  end;

begin
  m := TMemoryStream.Create;
  try
    Add('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'ansicpg936' + BS + 'deff0{' + BS + 'fonttbl{' + BS +
      'f0' + BS + 'fnil' + BS + 'fcharset134 SimSun;}}' + #13#10 + BS + 'pard' + BS + 'f0' + BS +
      'fs24 ');
    k := 0;
    big := ABigRows > 0;
    while m.Size < ATarget do
    begin
      Add(BS + 'pard between tables ' + IntToStr(k) + BS + 'par' + #13#10);
      if big and (m.Size > ATarget div 2) then
      begin
        Rows(ABigRows, k);
        big := False;
      end
      else
        Rows(ARows, k);
      Inc(k);
    end;
    Add(BS + 'pard the end' + BS + 'par' + #13#10 + '}');
    Result := nil;
    SetLength(Result, m.Size);
    i := m.Size;
    if i > 0 then Move(m.Memory^, Result[0], i);
  finally
    m.Free;
  end;
end;

function LoadDoc(const ABytes: TBytes): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    TyRichLoadRtf(Result, s);
  finally
    s.Free;
  end;
end;

function SaveOf(AProbe: TTyRichEdit): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    AProbe.SaveToStream(s, rfRtf);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

{ The first paragraph of cell ACell of row ARow of the table paragraph APara is in. }
function CellPara(ADoc: TTyRichDocument; APara, ARow, ACell: Integer): Integer;
var
  l: Integer;
begin
  if not ADoc.TableCellParas(APara, ARow, ACell, Result, l) then
    raise Exception.CreateFmt('no cell %d, %d', [ARow, ACell]);
end;

// paragraphs of a document read on demand that are parsed (have a value)
function ParsedParas(ADoc: TTyRichDocument): Integer;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to ADoc.Text.ParaCount - 1 do
    if ADoc.Text.ParaData[k] <> nil then Inc(Result);
end;

type
  // A table put on existing paragraphs, as a program's own command can (MarkTable).
  TMarkTableCommand = class(TTyRichCommand)
  private
    FFirst: Integer;
    FTable: TTyRichTable;
    FCells: array of Integer;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(AFirst: Integer; ATable: TTyRichTable; const ACells: array of Integer);
  end;

constructor TMarkTableCommand.Create(AFirst: Integer; ATable: TTyRichTable;
  const ACells: array of Integer);
var
  i: Integer;
begin
  inherited Create;
  FFirst := AFirst;
  FTable := ATable;
  SetLength(FCells, Length(ACells));
  for i := 0 to High(ACells) do FCells[i] := ACells[i];
end;

procedure TMarkTableCommand.DoExecute(ADoc: TTyRichDocument);
begin
  MarkTable(ADoc, FFirst, FTable, FCells);
end;

function ThreeByTwo: TTyRichTable;
begin
  Result := TTyRichTable.Create([1500, 3000]);
  Result.AddRow(2);
  Result.AddRow(2);
  Result.AddRow(2);
end;

function TwoByTwo: TTyRichTable;
begin
  Result := TTyRichTable.Create([1500, 3000]);
  Result.AddRow(2);
  Result.AddRow(2);
end;

// 'before', a 1 x 2 table, 'mid', a table of one cell, 'after'.
function TouchRtf: RawByteString;
begin
  Result := Head + RowRtf(['a0', 'a1'], []) + BS + 'pard mid' + BS + 'par' + #13#10 +
    RowRtf(['b0'], []) + BS + 'pard after' + BS + 'par' + #13#10 + '}';
end;

{ 'before', an ARows x ACols table with 'rRcC', a paragraph 'm', a 2 x 2 table with 'bRcC',
  'after'. }
function TwoTablesApartRtf(ARows, ACols: Integer): RawByteString;
var
  r, c: Integer;
  texts: array of string;
begin
  Result := Head;
  texts := nil;
  SetLength(texts, ACols);
  for r := 0 to ARows - 1 do
  begin
    for c := 0 to ACols - 1 do texts[c] := Format('r%dc%d', [r, c]);
    Result := Result + RowRtf(texts, []);
  end;
  Result := Result + BS + 'pard m' + BS + 'par' + #13#10 + RowRtf(['b0c0', 'b0c1'], []) +
    RowRtf(['b1c0', 'b1c1'], []) + BS + 'pard after' + BS + 'par' + #13#10 + '}';
end;

// An ARows x ACols table's shape ('rRcC' cells) without the columns of AGone.
function ShapeWithout(ARows, ACols: Integer; const AGone: array of Integer): string;
var
  r, c, i: Integer;
  gone, first: Boolean;
begin
  Result := '';
  for r := 0 to ARows - 1 do
  begin
    if r > 0 then Result := Result + '/';
    first := True;
    for c := 0 to ACols - 1 do
    begin
      gone := False;
      for i := 0 to High(AGone) do
        if AGone[i] = c then gone := True;
      if gone then Continue;
      if not first then Result := Result + '|';
      Result := Result + Format('r%dc%d', [r, c]);
      first := False;
    end;
  end;
end;

type
  // A table that counts the objects of its kind alive.
  TCountedTable = class(TTyRichTable)
  public
    class var Live: Integer;
    constructor Create(const AColBoundaries: array of Integer);
    destructor Destroy; override;
  end;

constructor TCountedTable.Create(const AColBoundaries: array of Integer);
begin
  inherited Create(AColBoundaries);
  Inc(Live);
end;

destructor TCountedTable.Destroy;
begin
  Dec(Live);
  inherited Destroy;
end;

type
  // A paragraph loader that leaves every paragraph plain - or, with Fail, raises.
  TFailingLoader = class(TTyRichParaLoader)
  public
    Fail: Boolean;
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
  end;

  TBuilderAccess = class(TTyRichDocBuilder)
  end;

  // The editor's probe on a document that reads its paragraphs through TFailingLoader.
  TLoaderProbe = class(TEditProbe)
  protected
    function CreateDocument: TTyRichDocument; override;
  public
    Loader: TFailingLoader;
  end;

procedure TFailingLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
begin
  if Fail then raise Exception.Create('the paragraph cannot be read');
end;

function TLoaderProbe.CreateDocument: TTyRichDocument;
begin
  Result := TTyRichDocument.CreateFromUtf8(RawBytes('before' + #10 + 'after'));
  Loader := TFailingLoader.Create;
  Result.InstallLoader(Loader, True);
end;

{ ---- the suite ---- }

procedure TTyRichTableEditTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
  ResetEvents;
end;

procedure TTyRichTableEditTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

function TTyRichTableEditTest.NewProbe: TEditProbe;
begin
  Result := TEditProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.OnSelectionChange := @SelChanged;
  Result.ResetCounts;
end;

procedure TTyRichTableEditTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichTableEditTest.ResetEvents;
begin
  FSelChanges := 0;
  if FRich <> nil then
  begin
    FRich.Refused := 0;
    FRich.LastReason := '';
  end;
end;

procedure TTyRichTableEditTest.LoadInto(AProbe: TEditProbe; const ABytes: TBytes;
  AFinish: Boolean);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(ABytes);
  try
    AProbe.LoadFromStream(st);
  finally
    st.Free;
  end;
  if AFinish then AProbe.FinishLoading;
  AProbe.UpdateView;
end;

procedure TTyRichTableEditTest.LoadRtf(const S: RawByteString);
begin
  LoadInto(FRich, RawBytes(S));
  ResetEvents;
end;

procedure TTyRichTableEditTest.Press(AKey: Word; AShift: TShiftState);
begin
  FRich.Press(AKey, AShift);
end;

procedure TTyRichTableEditTest.PaintAll(AProbe: TEditProbe);
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AProbe.Width, AProbe.Height);
    AProbe.PaintPart(bmp.Canvas, Rect(0, 0, AProbe.Width, AProbe.Height), True);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichTableEditTest.CheckSel(const AWhat: string; AStart, ALength: TTyRichPos);
begin
  AssertEquals(AWhat + ': the selection''s start', AStart, FRich.SelStart);
  AssertEquals(AWhat + ': its length', ALength, FRich.SelLength);
end;

procedure TTyRichTableEditTest.CheckRefused(const AWhat: string; AResult: Boolean;
  const AReason: string);
begin
  AssertFalse(AWhat + ': not done', AResult);
  AssertEquals(AWhat + ': told once', 1, FRich.Refused);
  AssertEquals(AWhat + ': why', AReason, FRich.LastReason);
  ResetEvents;
end;

{ The caret's rectangle is inside the text (scrolled into view). }
procedure TTyRichTableEditTest.CheckCaretShown(const AWhat: string);
var
  r, w: TRect;
begin
  FRich.UpdateView;
  r := FRich.PositionRect(FRich.CaretIndex);
  w := FRich.TextWindow;
  AssertTrue(AWhat + ': the caret is laid out', r.Bottom > r.Top);
  AssertTrue(Format('%s: the caret in view (%d..%d in %d..%d)', [AWhat, r.Top, r.Bottom, w.Top,
    w.Bottom]), (r.Top >= w.Top) and (r.Bottom <= w.Bottom));
end;

function Shown(ABar: TControl): Boolean;
begin
  Result := (ABar <> nil) and ABar.Visible;
end;

{ What the control shows equals what a new control shows of the same document - the same
  file, the same selection and scroll position: every pixel of the surface, and the scroll
  range. }
procedure TTyRichTableEditTest.CheckLikeFresh(const AWhat: string);
var
  fresh: TEditProbe;
  x, y, diff, fx, fy: Integer;
  a, b: PBGRAPixel;
begin
  CheckCaretShown(AWhat);
  fresh := NewProbe;
  try
    fresh.SetBounds(0, 0, FRich.Width, FRich.Height);
    LoadInto(fresh, SaveOf(FRich));
    fresh.SelStart := FRich.SelStart;
    fresh.SelLength := FRich.SelLength;
    fresh.ScrollY := FRich.ScrollY;
    fresh.UpdateView;
    PaintAll(FRich);
    PaintAll(fresh);
    AssertEquals(AWhat + ': the same scroll position', FRich.ScrollY, fresh.ScrollY);
    AssertEquals(AWhat + ': the same height', FRich.Document.Text.TotalHeight,
      fresh.Document.Text.TotalHeight);
    AssertEquals(AWhat + ': a vertical bar on both or neither', Shown(FRich.VBar), Shown(fresh.VBar));
    AssertEquals(AWhat + ': a horizontal bar on both or neither', Shown(FRich.HBar), Shown(fresh.HBar));
    if Shown(FRich.VBar) then
      AssertEquals(AWhat + ': the same scroll range', FRich.VBar.Max, fresh.VBar.Max);
    if Shown(FRich.HBar) then
      AssertEquals(AWhat + ': the same scroll range across', FRich.HBar.Max, fresh.HBar.Max);
    diff := 0;
    fx := -1;
    fy := -1;
    for y := 0 to FRich.Height * FRich.Scale - 1 do
    begin
      a := FRich.Surf.ScanLine[y];
      b := fresh.Surf.ScanLine[y];
      for x := 0 to FRich.Width * FRich.Scale - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) then
        begin
          if diff = 0 then
          begin
            fx := x;
            fy := y;
          end;
          Inc(diff);
        end;
        Inc(a);
        Inc(b);
      end;
    end;
    AssertEquals(Format('%s: pixels that differ from a new control''s (the first at %d,%d)',
      [AWhat, fx, fy]), 0, diff);
  finally
    fresh.Free;
  end;
end;

procedure TTyRichTableEditTest.LongTable(ARows: Integer);
var
  d: TTyRichDocument;
begin
  FRich.Lines.Text := 'before' + LineEnding + 'after';
  d := FRich.Document;
  AssertTrue('a long table', d.Execute(TTyRichInsertTable.Create(d.Text.ParaStart(1), ARows, 2)));
  d.ClearUndo;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichTableEditTest.ActWhileSaving(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
var
  before: Integer;
begin
  Inc(FSaveCalls);
  if FSaveCalls > 1 then Exit;
  before := FRich.Refused;
  if FRich.InsertRow then Inc(FSaveDone);
  if FRich.CanInsertRow then Inc(FSaveDone);
  FSaveRefused := FRich.Refused - before;
  FSaveReason := FRich.LastReason;
end;

{ ---- Tab ---- }

procedure TTyRichTableEditTest.TestTabMovesBetweenCellsAndAddsARowAtTheEnd;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;
  visits: Int64;
begin
  // cell 0, 1 empty
  LoadRtf(TableRtf(2, 3, [1]));
  FRich.WantTabs := True;
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  AssertEquals('the table', 'r0c0||r0c2/r1c0|r1c1|r1c2', Shape(d, f));
  FRich.SelStart := t.ParaStart(f) + 2;
  d.ClearUndo;
  visits := d.TableParaVisits;
  ResetEvents;
  Press(VK_TAB);
  CheckSel('an empty cell: the caret', t.ParaStart(f + 1), 0);
  Press(VK_TAB);
  CheckSel('the next cell: its content', t.ParaStart(f + 2), 4);
  AssertEquals('the caret at its end', t.ParaStart(f + 2) + 4, FRich.CaretIndex);
  Press(VK_TAB);
  CheckSel('the next row''s first cell', t.ParaStart(f + 3), 4);
  Press(VK_TAB);
  CheckSel('its second', t.ParaStart(f + 4), 4);
  Press(VK_TAB);
  CheckSel('the last cell', t.ParaStart(f + 5), 4);
  Press(VK_TAB, [ssShift]);
  CheckSel('Shift+Tab: the cell before', t.ParaStart(f + 4), 4);
  Press(VK_TAB, [ssShift]);
  Press(VK_TAB, [ssShift]);
  CheckSel('Shift+Tab: back to the row above''s last', t.ParaStart(f + 2), 4);
  Press(VK_TAB, [ssShift]);
  CheckSel('Shift+Tab: the empty cell', t.ParaStart(f + 1), 0);
  Press(VK_TAB, [ssShift]);
  CheckSel('Shift+Tab: the first cell', t.ParaStart(f), 4);
  AssertEquals('one report a move', 10, FSelChanges);
  Press(VK_TAB, [ssShift]);
  CheckSel('Shift+Tab in the first cell: nothing', t.ParaStart(f), 4);
  AssertEquals('nothing to report', 10, FSelChanges);
  AssertFalse('moves: no undo step', d.CanUndo);
  AssertFalse('moves: not modified', d.Modified);
  AssertEquals('moves: the table not read', visits, d.TableParaVisits);
  AssertEquals('moves: the text as it was', 'r0c0||r0c2/r1c0|r1c1|r1c2', Shape(d, f));
  AssertEquals('nothing told', 0, FRich.Refused);
  // the last cell of the last row: a row below, its first cell
  FRich.SelStart := t.ParaStart(f + 4);
  Press(VK_TAB);
  CheckSel('the last cell again', t.ParaStart(f + 5), 4);
  Press(VK_TAB);
  AssertEquals('a row below', 'r0c0||r0c2/r1c0|r1c1|r1c2/||', Shape(d, f));
  CheckSel('the new row''s first cell', t.ParaStart(f + 6), 0);
  AssertTrue('the paragraph after it outside the table', d.CellAt(f + 9) = nil);
  AssertEquals('the paragraph after it', 'after', ParaText(d, f + 9));
  AssertEquals('an undo step', rsRichUndoInsertRow, d.UndoDescription);
  AssertTrue('modified', d.Modified);
  FRich.Undo;
  AssertEquals('undone', 'r0c0||r0c2/r1c0|r1c1|r1c2', Shape(d, f));
  CheckSel('undone: the cell selected again', t.ParaStart(f + 5), 4);
  AssertFalse('one step', d.CanUndo);
  FRich.Redo;
  AssertEquals('redone', 'r0c0||r0c2/r1c0|r1c1|r1c2/||', Shape(d, f));
  CheckSel('redone: the new row''s first cell', t.ParaStart(f + 6), 0);
  FRich.Undo;
  // Ctrl+Tab: a tab character in the cell
  FRich.SelStart := t.ParaStart(f);
  Press(VK_TAB, [ssCtrl]);
  AssertEquals('Ctrl+Tab: a tab character', #9 + 'r0c0', ParaText(d, f));
  AssertEquals('Ctrl+Tab: the caret behind it', t.ParaStart(f) + 1, FRich.CaretIndex);
end;

procedure TTyRichTableEditTest.TestTabPassesOverMergedCellsAndRefusesARowThere;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;
begin
  LoadRtf(MergedRtf);
  FRich.WantTabs := True;
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  AssertEquals('the table', 'a||c/d|e|f', Shape(d, f));
  AssertTrue('merged cells', d.TableAt(f).ContentLocked);
  FRich.SelStart := t.ParaStart(f);
  Press(VK_TAB);
  CheckSel('the cell merged away passed over', t.ParaStart(f + 2), 1);
  Press(VK_TAB, [ssShift]);
  CheckSel('back: the merged cell', t.ParaStart(f), 1);
  Press(VK_TAB);
  Press(VK_TAB);
  CheckSel('the next row', t.ParaStart(f + 3), 1);
  Press(VK_TAB);
  Press(VK_TAB);
  CheckSel('the last cell', t.ParaStart(f + 5), 1);
  d.ClearUndo;
  ResetEvents;
  // its structure cannot change: the row is refused, told, and nothing moves
  Press(VK_TAB);
  AssertEquals('refused: told once', 1, FRich.Refused);
  AssertEquals('refused: why', rsRichEditRefusedMergedCells, FRich.LastReason);
  CheckSel('refused: the selection stays', t.ParaStart(f + 5), 1);
  AssertEquals('refused: the table as it was', 'a||c/d|e|f', Shape(d, f));
  AssertFalse('refused: no step', d.CanUndo);
  AssertEquals('refused: no move reported', 0, FSelChanges);
end;

procedure TTyRichTableEditTest.TestTabGoesOnIntoTablesThatTouch;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, m: Integer;
begin
  LoadRtf(TwoTablesRtf);
  FRich.WantTabs := True;
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  m := f + 2;
  AssertEquals('the paragraph between them', 'mid', ParaText(d, m));
  // the paragraph between them goes (by code, with its separator): they touch
  AssertTrue('the paragraph between deleted', d.Execute(TTyRichDelete.Create(t.ParaStart(m),
    t.ParaLength(m) + 1)));
  FRich.UpdateView;
  d.BeginRead;
  try
    AssertTrue('two tables', (d.TableAt(f + 1) <> nil) and (d.TableAt(f + 2) <> nil) and
      (d.TableAt(f + 1) <> d.TableAt(f + 2)));
  finally
    d.EndRead;
  end;
  d.ClearUndo;
  FRich.SelStart := t.ParaStart(f);
  Press(VK_TAB);
  CheckSel('the first table''s last cell', t.ParaStart(f + 1), 2);
  Press(VK_TAB);
  CheckSel('on into the next table, no row added', t.ParaStart(f + 2), 2);
  AssertFalse('nothing added', d.CanUndo);
  AssertEquals('the first table as it was', 'a0|a1', Shape(d, f));
  Press(VK_TAB, [ssShift]);
  CheckSel('back into the first', t.ParaStart(f + 1), 2);
  FRich.SelStart := t.ParaStart(f + 5);
  Press(VK_TAB);
  // the row goes into the table object the caret is in
  AssertEquals('a row at the end', 'b0|b1/b2|b3/|', Shape(d, f + 2));
  AssertEquals('the first table as it was still', 'a0|a1', Shape(d, f));
  CheckSel('its first cell', t.ParaStart(f + 6), 0);
end;

procedure TTyRichTableEditTest.TestTabOutsideATableAndWithoutWantTabs;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;
begin
  LoadRtf(TableRtf(2, 2, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  // without WantTabs Tab is the form's, in a table too
  FRich.SelStart := t.ParaStart(f);
  AssertEquals('Tab left to the form', VK_TAB, FRich.KeyResult(VK_TAB, []));
  AssertEquals('Shift+Tab left to the form', VK_TAB, FRich.KeyResult(VK_TAB, [ssShift]));
  CheckSel('nothing moved', t.ParaStart(f), 0);
  AssertEquals('nothing typed', 'r0c0|r0c1/r1c0|r1c1', Shape(d, f));
  // with it, outside a table: a tab character, as before
  FRich.WantTabs := True;
  FRich.SelStart := 0;
  AssertEquals('Tab taken', 0, FRich.KeyResult(VK_TAB, []));
  AssertEquals('a tab', #9 + 'before', ParaText(d, 0));
  Press(VK_TAB, [ssShift]);
  AssertEquals('Shift+Tab outside: a tab too', #9#9 + 'before', ParaText(d, 0));
  AssertEquals('the table as it was', 'r0c0|r0c1/r1c0|r1c1', Shape(d, f));
end;

procedure TTyRichTableEditTest.TestTabWithReadOnlyMovesAndAddsNothing;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;
begin
  LoadRtf(TableRtf(2, 2, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  FRich.WantTabs := True;
  FRich.ReadOnly := True;
  FRich.SelStart := t.ParaStart(f);
  Press(VK_TAB);
  CheckSel('a viewer moves', t.ParaStart(f + 1), 4);
  Press(VK_TAB, [ssShift]);
  CheckSel('both ways', t.ParaStart(f), 4);
  FRich.SelStart := t.ParaStart(f + 3);
  AssertEquals('Tab in the last cell taken', 0, FRich.KeyResult(VK_TAB, []));
  AssertEquals('no row', 'r0c0|r0c1/r1c0|r1c1', Shape(d, f));
  AssertEquals('nothing told, as a typed character', 0, FRich.Refused);
  AssertFalse('no step', d.CanUndo);
  Press(VK_TAB, [ssCtrl]);
  AssertEquals('Ctrl+Tab: nothing', 'r1c1', ParaText(d, f + 3));
  // a viewer of a plain text document: nothing told either
  FRich.PlainText := True;
  FRich.SelStart := t.ParaStart(f + 3);
  Press(VK_TAB);
  AssertEquals('a plain text viewer: nothing told', 0, FRich.Refused);
  // its editor: told that a plain text document holds no table
  FRich.ReadOnly := False;
  FRich.SelStart := t.ParaStart(f + 3);
  Press(VK_TAB);
  AssertEquals('plain text: told', 1, FRich.Refused);
  AssertEquals('plain text: why', rsRichEditRefusedPlainTable, FRich.LastReason);
  AssertEquals('plain text: no row', 'r0c0|r0c1/r1c0|r1c1', Shape(d, f));
end;

procedure TTyRichTableEditTest.TestATabThatMovesReadsNoTable;
const
  Rows = 10000;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k: Integer;
  engine: Int64;
begin
  LongTable(Rows);
  FRich.WantTabs := True;
  d := FRich.Document;
  t := d.Text;
  k := 1 + 2 * (Rows div 2);
  FRich.SelStart := t.ParaStart(k);
  FRich.UpdateView;
  d.TableParaVisits := 0;
  FRich.ResetCounts;
  Press(VK_TAB);
  CheckSel('the next cell', t.ParaStart(k + 1), 0);
  Press(VK_TAB);
  CheckSel('the next row', t.ParaStart(k + 2), 0);
  Press(VK_TAB, [ssShift]);
  CheckSel('back', t.ParaStart(k + 1), 0);
  AssertEquals('no table paragraph visited', 0, d.TableParaVisits);
  AssertTrue(Format('%d paragraphs laid out', [FRich.LaidParas]), FRich.LaidParas < 100);
  AssertFalse('no step', d.CanUndo);
  { a row by Tab in the last cell, and by InsertRow: the engine's own reads only - of the row
    beside the position (a row named by its place reads that row, not the table) }
  d.TableParaVisits := 0;
  AssertTrue('the engine''s row', d.Execute(TTyRichInsertRow.Create(t.ParaStart(2 * Rows),
    CRichRowBelow)));
  engine := d.TableParaVisits;
  d.Undo;
  AssertTrue(Format('the engine reads the row (%d)', [engine]), (engine > 0) and (engine <= 16));
  FRich.SelStart := t.ParaStart(2 * Rows);
  d.TableParaVisits := 0;
  Press(VK_TAB);
  AssertEquals('Tab''s row: the engine''s reads, no more', engine, d.TableParaVisits);
  AssertEquals('Tab''s row: below the last', '', ParaText(d, 2 * Rows + 1));
  AssertTrue('Tab''s row: in the table', d.CellAt(2 * Rows + 2) <> nil);
  CheckSel('Tab''s row: its first cell', t.ParaStart(2 * Rows + 1), 0);
  FRich.Undo;
  FRich.SelStart := t.ParaStart(k);
  d.TableParaVisits := 0;
  AssertTrue('InsertRow', FRich.InsertRow);
  AssertEquals('InsertRow: the engine''s reads, no more', engine, d.TableParaVisits);
  CheckSel('InsertRow: the new row''s first cell', t.ParaStart(k + 2), 0);
  FRich.Undo;
  d.TableParaVisits := 0;
  AssertTrue('InsertRow above', FRich.InsertRow(False));
  AssertEquals('InsertRow above: the engine''s reads, no more', engine, d.TableParaVisits);
  CheckSel('InsertRow above: the new row''s first cell', t.ParaStart(k), 0);
end;

{ ---- the actions ---- }

procedure TTyRichTableEditTest.TestInsertTableAtTheCaretAndAtASelection;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, k: Integer;
begin
  LoadRtf(Head + BS + 'pard two' + BS + 'par' + #13#10 + '}');
  d := FRich.Document;
  t := d.Text;
  // inside a paragraph: split, the table between the parts, the caret in its first cell
  FRich.SelStart := 3;
  AssertTrue('a table', FRich.InsertTable(2, 3));
  f := FirstTablePara(d);
  AssertEquals('the paragraph''s first part', 'bef', ParaText(d, 0));
  AssertEquals('the table after it', 1, f);
  AssertEquals('2 x 3', '||/||', Shape(d, f));
  AssertEquals('the second part after it', 'ore', ParaText(d, f + 6));
  CheckSel('the caret in the first cell', t.ParaStart(f), 0);
  AssertEquals('one step', rsRichUndoInsertTable, d.UndoDescription);
  CheckCaretShown('a table');
  // with a selection: at its start, the selected text stays
  k := f + 7;
  AssertEquals('two', 'two', ParaText(d, k));
  FRich.SelStart := t.ParaStart(k);
  FRich.SelLength := 3;
  AssertTrue('a table at the selection', FRich.InsertTable(1, 2));
  AssertEquals('the selected text stays', 'two', ParaText(d, k + 2));
  AssertEquals('the table before it', '|', Shape(d, k));
  CheckSel('the caret in its first cell', t.ParaStart(k), 0);
  // right after a table (the start of the paragraph after it): a paragraph keeps them apart
  FRich.SelStart := t.ParaStart(f + 6);
  AssertTrue('a table after a table', FRich.InsertTable(1, 1));
  AssertEquals('the paragraph that keeps them apart', '', ParaText(d, f + 6));
  AssertTrue('outside a table', d.CellAt(f + 6) = nil);
  CheckSel('the caret in the new table''s cell', t.ParaStart(f + 7), 0);
  d.BeginRead;
  try
    AssertTrue('the new table', (d.CellAt(f + 7) <> nil) and (d.TableAt(f + 7) <> d.TableAt(f)));
  finally
    d.EndRead;
  end;
end;

procedure TTyRichTableEditTest.TestInsertRowAndColumnOnEitherSide;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;
  shape0: string;
begin
  LoadRtf(TableRtf(3, 3, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  shape0 := Shape(d, f);
  // the caret in cell 1, 1
  FRich.SelStart := t.ParaStart(f + 4) + 1;
  AssertTrue('a row below', FRich.InsertRow);
  AssertEquals('below', 'r0c0|r0c1|r0c2/r1c0|r1c1|r1c2/||/r2c0|r2c1|r2c2', Shape(d, f));
  CheckSel('its first cell', t.ParaStart(f + 6), 0);
  AssertEquals('a step', rsRichUndoInsertRow, d.UndoDescription);
  FRich.Undo;
  AssertEquals('undone', shape0, Shape(d, f));
  CheckSel('undone: the caret back', t.ParaStart(f + 4) + 1, 0);
  AssertTrue('a row above', FRich.InsertRow(False));
  AssertEquals('above', 'r0c0|r0c1|r0c2/||/r1c0|r1c1|r1c2/r2c0|r2c1|r2c2', Shape(d, f));
  CheckSel('the new row''s first cell', t.ParaStart(f + 3), 0);
  FRich.Undo;
  FRich.SelStart := t.ParaStart(f + 4) + 1;
  AssertTrue('a column right', FRich.InsertColumn);
  AssertEquals('right', 'r0c0|r0c1||r0c2/r1c0|r1c1||r1c2/r2c0|r2c1||r2c2', Shape(d, f));
  CheckSel('its cell of the caret''s row', t.ParaStart(f + 4 + 2), 0);
  AssertEquals('a step', rsRichUndoInsertColumn, d.UndoDescription);
  FRich.Undo;
  AssertTrue('a column left', FRich.InsertColumn(False));
  AssertEquals('left', 'r0c0||r0c1|r0c2/r1c0||r1c1|r1c2/r2c0||r2c1|r2c2', Shape(d, f));
  CheckSel('its cell of the caret''s row', t.ParaStart(f + 4 + 1), 0);
  FRich.Undo;
  AssertEquals('all undone', shape0, Shape(d, f));
  { a selection inside the table selects cells (tyControls.RichEdit.TableSel): as many rows as
    it spans, below its last }
  FRich.SelStart := t.ParaStart(f) + 1;
  FRich.SelLength := t.ParaStart(f + 8) + 2 - FRich.SelStart;
  AssertTrue('rows below the selected cells', FRich.InsertRow);
  AssertEquals('below the last, as many as selected', shape0 + '/||/||/||', Shape(d, f));
  CheckSel('its first cell', t.ParaStart(f + 9), 0);
  FRich.Undo;
  FRich.SelStart := t.ParaStart(f + 8) + 2;
  FRich.SelLength := t.ParaStart(f) + 1 - FRich.SelStart;
  AssertEquals('the caret end at the first cell', t.ParaStart(f) + 1, FRich.CaretIndex);
  AssertTrue('columns left of the selected cells', FRich.InsertColumn(False));
  AssertEquals('left of the first, as many as selected', '|||r0c0|r0c1|r0c2/|||r1c0|r1c1|r1c2/|||r2c0|r2c1|r2c2',
    Shape(d, f));
  CheckSel('the new cell of its row', t.ParaStart(f), 0);
end;

procedure TTyRichTableEditTest.TestDeleteRowsAndColumnsTheSelectionTouches;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;
  shape0: string;
begin
  LoadRtf(TableRtf(3, 3, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  shape0 := Shape(d, f);
  // one row: the caret's; the caret into the row that took its place
  FRich.SelStart := t.ParaStart(f + 4) + 1;
  AssertTrue('a row', FRich.DeleteRow);
  AssertEquals('row 1 gone', 'r0c0|r0c1|r0c2/r2c0|r2c1|r2c2', Shape(d, f));
  CheckSel('the same cell of the row below', t.ParaStart(f + 4), 0);
  AssertEquals('a step', rsRichUndoDeleteRow, d.UndoDescription);
  FRich.Undo;
  AssertEquals('undone', shape0, Shape(d, f));
  // the last row: into the row above
  FRich.SelStart := t.ParaStart(f + 7);
  AssertTrue('the last row', FRich.DeleteRow);
  AssertEquals('row 2 gone', 'r0c0|r0c1|r0c2/r1c0|r1c1|r1c2', Shape(d, f));
  CheckSel('the same cell of the row above', t.ParaStart(f + 4), 0);
  FRich.Undo;
  // rows the selection touches: one step
  FRich.SelStart := t.ParaStart(f + 2) + 1;
  FRich.SelLength := t.ParaStart(f + 3) + 1 - FRich.SelStart;
  AssertTrue('two rows', FRich.DeleteRow);
  AssertEquals('rows 0 and 1 gone', 'r2c0|r2c1|r2c2', Shape(d, f));
  CheckSel('the caret end''s cell of the row below', t.ParaStart(f), 0);
  AssertEquals('one step', rsRichUndoDeleteRow, d.UndoDescription);
  FRich.Undo;
  AssertEquals('undone in one', shape0, Shape(d, f));
  FRich.SelStart := t.ParaStart(f + 4);
  FRich.SelLength := t.ParaStart(f + 8) + 1 - FRich.SelStart;
  AssertTrue('the last two rows', FRich.DeleteRow);
  AssertEquals('rows 1 and 2 gone', 'r0c0|r0c1|r0c2', Shape(d, f));
  CheckSel('the row above', t.ParaStart(f + 2), 0);
  FRich.Undo;
  // from before the table: its rows from the first
  FRich.SelStart := 2;
  FRich.SelLength := t.ParaStart(f + 4) + 1 - 2;
  AssertTrue('rows from before the table', FRich.DeleteRow);
  AssertEquals('rows 0 and 1 gone (before the table stays)', 'r2c0|r2c1|r2c2', Shape(d, f));
  AssertEquals('before', 'before', ParaText(d, 0));
  FRich.Undo;
  FRich.SelStart := 2;
  FRich.SelLength := t.ParaStart(f + 4) + 1 - 2;
  AssertTrue('columns from before the table', FRich.DeleteColumn);
  AssertEquals('the whole first row covered: every column, the table', -1, FirstTablePara(d));
  FRich.Undo;
  // all of them: the table; the caret to what followed it
  FRich.SelStart := t.ParaStart(f) + 1;
  FRich.SelLength := t.ParaStart(f + 8) + 1 - FRich.SelStart;
  AssertTrue('every row', FRich.DeleteRow);
  AssertEquals('no table', -1, FirstTablePara(d));
  AssertEquals('what followed it', 'after', ParaText(d, 1));
  CheckSel('the caret there', t.ParaStart(1), 0);
  FRich.Undo;
  AssertEquals('undone', shape0, Shape(d, f));
  // one column: the caret's; the caret into the cell that took its place
  FRich.SelStart := t.ParaStart(f + 4) + 1;
  AssertTrue('a column', FRich.DeleteColumn);
  AssertEquals('column 1 gone', 'r0c0|r0c2/r1c0|r1c2/r2c0|r2c2', Shape(d, f));
  CheckSel('the cell right of it', t.ParaStart(f + 3), 0);
  AssertEquals('a step', rsRichUndoDeleteColumn, d.UndoDescription);
  FRich.Undo;
  FRich.SelStart := t.ParaStart(f + 5);
  AssertTrue('the last column', FRich.DeleteColumn);
  AssertEquals('column 2 gone', 'r0c0|r0c1/r1c0|r1c1/r2c0|r2c1', Shape(d, f));
  CheckSel('the cell left of it', t.ParaStart(f + 3), 0);
  FRich.Undo;
  // the columns between the selection's two cells, one step
  FRich.SelStart := t.ParaStart(f + 1);
  FRich.SelLength := t.ParaStart(f + 5) + 1 - FRich.SelStart;
  AssertTrue('two rows'' cells', FRich.DeleteColumn);
  // (row 0 from cell 1 on and row 1 to cell 2: every column is covered)
  AssertEquals('every column: the table', -1, FirstTablePara(d));
  AssertEquals('one step', rsRichUndoDeleteTable, d.UndoDescription);
  FRich.Undo;
  AssertEquals('undone at once', shape0, Shape(d, f));
  FRich.SelStart := t.ParaStart(f + 3);
  FRich.SelLength := t.ParaStart(f + 4) + 1 - FRich.SelStart;
  AssertTrue('the first two columns', FRich.DeleteColumn);
  AssertEquals('columns 0 and 1 gone', 'r0c2/r1c2/r2c2', Shape(d, f));
  CheckSel('the cell that took their place', t.ParaStart(f + 1), 0);
  FRich.Undo;
  // all of them: the table
  FRich.SelStart := t.ParaStart(f);
  FRich.SelLength := t.ParaStart(f + 2) + 1 - FRich.SelStart;
  AssertTrue('every column', FRich.DeleteColumn);
  AssertEquals('no table', -1, FirstTablePara(d));
  CheckSel('the caret at what followed it', t.ParaStart(1), 0);
  FRich.Undo;
  AssertEquals('undone at last', shape0, Shape(d, f));
end;

procedure TTyRichTableEditTest.TestDeleteTable;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, k: Integer;
  shape0: string;
begin
  LoadRtf(TableRtf(3, 2, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  shape0 := Shape(d, f);
  FRich.SelStart := t.ParaStart(f + 3) + 1;
  FRich.SelLength := 2;
  AssertTrue('the table', FRich.DeleteTable);
  AssertEquals('gone', -1, FirstTablePara(d));
  AssertEquals('two paragraphs', 2, t.ParaCount);
  CheckSel('the caret at what followed it', t.ParaStart(1), 0);
  AssertEquals('a step', rsRichUndoDeleteTable, d.UndoDescription);
  FRich.Undo;
  AssertEquals('undone', shape0, Shape(d, f));
  CheckSel('undone: the selection back', t.ParaStart(f + 3) + 1, 2);
  FRich.Redo;
  AssertEquals('redone', -1, FirstTablePara(d));
  CheckSel('redone: the caret', t.ParaStart(1), 0);
  // merged cells do not keep it
  LoadRtf(MergedRtf);
  t := d.Text;
  f := FirstTablePara(d);
  FRich.SelStart := t.ParaStart(f + 4);
  AssertTrue('a table of merged cells', FRich.DeleteTable);
  AssertEquals('gone too', -1, FirstTablePara(d));
  { A table that ends the text (made by code): what is left after it is a paragraph in no
    table, the one the engine's last row leaves (a deletion to the text's end would join the
    paragraph before with the last cell). }
  FRich.Lines.Text := 'x' + LineEnding + 'a' + LineEnding + 'b' + LineEnding + 'c' + LineEnding + 'd';
  t := d.Text;
  AssertTrue('a table', d.Execute(TMarkTableCommand.Create(1, TwoByTwo, [1, 1, 1, 1])));
  AssertTrue('the table ends the text', d.CellAt(t.ParaCount - 1) <> nil);
  FRich.UpdateView;
  FRich.SelStart := t.ParaStart(2);
  AssertTrue('the table at the end', FRich.DeleteTable);
  AssertEquals('what is left', 'x', ParaText(d, 0));
  AssertEquals('and a paragraph after it', 2, t.ParaCount);
  AssertEquals('no table', -1, FirstTablePara(d));
  CheckSel('the caret in it', t.ParaStart(1), 0);
  AssertEquals('one step', rsRichUndoDeleteTable, d.UndoDescription);
  // rows down to the end of a table that ends the text: the rows above stay the last
  FRich.Lines.Text := 'x' + LineEnding + 'a' + LineEnding + 'b' + LineEnding + 'c' + LineEnding +
    'd' + LineEnding + 'e' + LineEnding + 'g';
  t := d.Text;
  AssertTrue('three rows', d.Execute(TMarkTableCommand.Create(1, ThreeByTwo, [1, 1, 1, 1, 1, 1])));
  FRich.UpdateView;
  FRich.SelStart := t.ParaStart(3);
  FRich.SelLength := t.Length - FRich.SelStart;
  AssertTrue('its last two rows', FRich.DeleteRow);
  AssertEquals('the first row left', 'a|b', Shape(d, 1));
  AssertEquals('and a paragraph after it', 4, t.ParaCount);
  AssertTrue('in no table', d.CellAt(3) = nil);
  AssertEquals('one step', rsRichUndoDeleteRow, d.UndoDescription);
  CheckSel('the caret end''s cell of the row above', t.ParaStart(2), 0);
  // the whole text a table
  FRich.Lines.Text := 'a' + LineEnding + 'b' + LineEnding + 'c' + LineEnding + 'd';
  t := d.Text;
  AssertTrue('a table', d.Execute(TMarkTableCommand.Create(0, TwoByTwo, [1, 1, 1, 1])));
  AssertEquals('all of it a table', 0, FirstTablePara(d));
  AssertTrue('to its end', d.CellAt(t.ParaCount - 1) <> nil);
  FRich.UpdateView;
  FRich.SelStart := t.ParaStart(3);
  d.ClearUndo;
  AssertTrue('the whole text', FRich.DeleteTable);
  AssertEquals('no table', -1, FirstTablePara(d));
  AssertEquals('nothing left', 0, t.Length);
  AssertEquals('one step', rsRichUndoDeleteTable, d.UndoDescription);
  FRich.Undo;
  AssertEquals('undone', 'a|b/c|d', Shape(d, 0));
  AssertFalse('one step only', d.CanUndo);
  AssertEquals('integrity', '', t.CheckIntegrity);
end;

procedure TTyRichTableEditTest.TestUndoAndRedoOfEachActionPlaceTheSelection;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, n: Integer;
  ok: Boolean;
  s, l, c, s2, c2: TTyRichPos;
  shape0: string;
begin
  LoadRtf(TableRtf(3, 3, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  shape0 := Shape(d, f);
  for n := 0 to 6 do
  begin
    // a selection from cell 1, 1 back to cell 1, 0: the caret before the anchor
    FRich.SelStart := t.ParaStart(f + 4) + 3;
    FRich.SelLength := t.ParaStart(f + 3) + 1 - FRich.SelStart;
    s := FRich.SelStart;
    l := FRich.SelLength;
    c := FRich.CaretIndex;
    AssertEquals(Format('%d: the caret first', [n]), s, c);
    case n of
      0: ok := FRich.InsertRow;
      1: ok := FRich.InsertRow(False);
      2: ok := FRich.InsertColumn;
      3: ok := FRich.InsertColumn(False);
      4: ok := FRich.DeleteRow;
      5: ok := FRich.DeleteColumn;
    else
      ok := FRich.DeleteTable;
    end;
    AssertTrue(Format('%d: done', [n]), ok);
    s2 := FRich.SelStart;
    c2 := FRich.CaretIndex;
    AssertEquals(Format('%d: a caret', [n]), 0, FRich.SelLength);
    FRich.Undo;
    AssertEquals(Format('%d: undone', [n]), shape0, Shape(d, f));
    AssertEquals(Format('%d: undone: the start', [n]), s, FRich.SelStart);
    AssertEquals(Format('%d: undone: the length', [n]), l, FRich.SelLength);
    AssertEquals(Format('%d: undone: the caret end', [n]), c, FRich.CaretIndex);
    FRich.Redo;
    AssertEquals(Format('%d: redone: the caret', [n]), c2, FRich.CaretIndex);
    AssertEquals(Format('%d: redone: where the action left it', [n]), s2, FRich.SelStart);
    AssertEquals(Format('%d: redone: no selection', [n]), 0, FRich.SelLength);
    FRich.Undo;
    AssertEquals(Format('%d: undone again', [n]), shape0, Shape(d, f));
  end;
  // InsertTable: the selection outside the table back
  FRich.SelStart := 1;
  FRich.SelLength := 3;
  AssertTrue('a table', FRich.InsertTable(1, 1));
  c2 := FRich.CaretIndex;
  FRich.Undo;
  CheckSel('InsertTable undone', 1, 3);
  FRich.Redo;
  CheckSel('InsertTable redone', c2, 0);
end;

procedure TTyRichTableEditTest.TestEveryRefusalIsToldWithItsReason;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, i: Integer;
  st: TMemoryStream;
  sl: TStringList;
  before: string;

  procedure Each(const AWhat, AReason: string);
  var
    j: Integer;
    r: Boolean;
  begin
    for j := 0 to 5 do
    begin
      case j of
        0: r := FRich.InsertRow;
        1: r := FRich.InsertColumn;
        2: r := FRich.DeleteRow;
        3: r := FRich.DeleteColumn;
        4: r := FRich.DeleteTable;
      else
        r := FRich.InsertTable(2, 2);
      end;
      if AReason = '' then
      begin
        // a viewer: nothing, and nothing told, as for its other user's actions
        AssertFalse(Format('%s, %d: not done', [AWhat, j]), r);
        AssertEquals(Format('%s, %d: nothing told', [AWhat, j]), 0, FRich.Refused);
      end
      else
        CheckRefused(Format('%s, %d', [AWhat, j]), r, AReason);
    end;
    AssertEquals(AWhat + ': nothing changed', before, Shape(d, f));
  end;

begin
  LoadRtf(TableRtf(2, 2, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  before := Shape(d, f);
  FRich.SelStart := t.ParaStart(f);
  d.ClearUndo;
  // the control's states: ReadOnly, a plain text document
  FRich.ReadOnly := True;
  Each('read-only', '');
  FRich.ReadOnly := False;
  FRich.PlainText := True;
  Each('plain text', rsRichEditRefusedPlainTable);
  FRich.PlainText := False;
  AssertFalse('no step', d.CanUndo);
  ResetEvents;
  // not in a table
  FRich.SelStart := 0;
  CheckRefused('no table: a row', FRich.InsertRow, rsRichEditRefusedNoTable);
  CheckRefused('no table: a column', FRich.DeleteColumn, rsRichEditRefusedNoTable);
  CheckRefused('no table: the table', FRich.DeleteTable, rsRichEditRefusedNoTable);
  // a table into a table; a size out of range
  FRich.SelStart := t.ParaStart(f + 1);
  CheckRefused('into a table', FRich.InsertTable(2, 2), rsRichEditRefusedTableInTable);
  FRich.SelStart := 0;
  CheckRefused('no rows', FRich.InsertTable(0, 2),
    Format(rsRichEditRefusedTableSize, [CRichMaxTableRows, CRichMaxTableCols]));
  CheckRefused('too many columns', FRich.InsertTable(2, CRichMaxTableCols + 1),
    Format(rsRichEditRefusedTableSize, [CRichMaxTableRows, CRichMaxTableCols]));
  AssertEquals('nothing changed', before, Shape(d, f));
  AssertFalse('no step', d.CanUndo);
  // merged cells
  LoadRtf(MergedRtf);
  t := d.Text;
  f := FirstTablePara(d);
  before := Shape(d, f);
  FRich.SelStart := t.ParaStart(f + 4);
  for i := 0 to 3 do
    case i of
      0: CheckRefused('merged: a row', FRich.InsertRow, rsRichEditRefusedMergedCells);
      1: CheckRefused('merged: a column', FRich.InsertColumn, rsRichEditRefusedMergedCells);
      2: CheckRefused('merged: delete a row', FRich.DeleteRow, rsRichEditRefusedMergedCells);
    else
      CheckRefused('merged: delete a column', FRich.DeleteColumn, rsRichEditRefusedMergedCells);
    end;
  // several rows and columns: the same reason
  FRich.SelStart := t.ParaStart(f);
  FRich.SelLength := t.ParaStart(f + 4) - t.ParaStart(f);
  CheckRefused('merged: two rows', FRich.DeleteRow, rsRichEditRefusedMergedCells);
  CheckRefused('merged: two columns', FRich.DeleteColumn, rsRichEditRefusedMergedCells);
  AssertEquals('merged: nothing changed', before, Shape(d, f));
  // a table inside a cell
  LoadInto(FRich, FixtureFile('word-table-merged.rtf'));
  t := d.Text;
  ResetEvents;
  f := FirstTablePara(d);
  FRich.SelStart := t.ParaStart(f);
  CheckRefused('nested: a row', FRich.InsertRow, rsRichEditRefusedNestedTable);
  CheckRefused('nested: a column', FRich.DeleteColumn, rsRichEditRefusedNestedTable);
  // rows of different numbers of cells: columns only
  LoadRtf(IrregularRtf);
  t := d.Text;
  f := FirstTablePara(d);
  FRich.SelStart := t.ParaStart(f);
  CheckRefused('irregular: a column', FRich.InsertColumn, rsRichEditRefusedIrregularRows);
  CheckRefused('irregular: delete a column', FRich.DeleteColumn, rsRichEditRefusedIrregularRows);
  AssertTrue('irregular: a row', FRich.InsertRow);
  AssertEquals('irregular: nothing told for a row', 0, FRich.Refused);
  // as many columns as a table can have
  FRich.Lines.Text := 'x';
  t := d.Text;
  FRich.SelStart := 0;
  AssertTrue('63 columns', FRich.InsertTable(1, CRichMaxTableCols));
  ResetEvents;
  CheckRefused('a column too many', FRich.InsertColumn,
    Format(rsRichEditRefusedTableColumns, [CRichMaxTableCols]));
  AssertTrue('one fewer', FRich.DeleteColumn);
  // loading
  // (slices small enough that the load is still going on)
  FRich.Slices(4096, 4096);
  LoadInto(FRich, TablesRtf(5, 2 shl 20), False);
  t := d.Text;
  ResetEvents;
  AssertTrue('loading', FRich.Loading);
  f := FirstTablePara(d);
  FRich.SelStart := t.ParaStart(f);
  before := Shape(d, f);
  Each('loading', rsRichEditRefusedLoading);
  FRich.FinishLoading;
  FRich.Slices(CRtfFirstSliceBytes, CRichLoadStepBytes);
  // saving (a document long enough for the save to report its progress, a table first)
  sl := TStringList.Create;
  try
    for i := 0 to 39999 do sl.Add('A line of text that the save writes out: ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  t := d.Text;
  AssertTrue('a table first', d.Execute(TTyRichInsertTable.Create(0, 2, 2)));
  FRich.UpdateView;
  FRich.SelStart := 0;
  ResetEvents;
  // saving: asked from the save's progress
  FRich.OnSaveProgress := @ActWhileSaving;
  FSaveCalls := 0;
  FSaveDone := 0;
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, rfText);
  finally
    st.Free;
    FRich.OnSaveProgress := nil;
  end;
  AssertTrue('the save asked', FSaveCalls > 0);
  AssertEquals('saving: refused, and no for an Update', 0, FSaveDone);
  AssertEquals('saving: told once', 1, FSaveRefused);
  AssertEquals('saving: why', rsRichEditRefusedSaving, FSaveReason);
end;

{ ---- what an action's Update asks ---- }

procedure TTyRichTableEditTest.TestTheCanFunctionsAnswerAsTheActions;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;

  procedure Check(const AWhat: string; AIn, ATable, ARows, AColIns, AColDel, ADelTable: Boolean);
  begin
    AssertEquals(AWhat + ': in a table', AIn, FRich.InTable);
    AssertEquals(AWhat + ': insert a table', ATable, FRich.CanInsertTable);
    AssertEquals(AWhat + ': insert a row', ARows, FRich.CanInsertRow);
    AssertEquals(AWhat + ': delete a row', ARows, FRich.CanDeleteRow);
    AssertEquals(AWhat + ': insert a column', AColIns, FRich.CanInsertColumn);
    AssertEquals(AWhat + ': delete a column', AColDel, FRich.CanDeleteColumn);
    AssertEquals(AWhat + ': delete the table', ADelTable, FRich.CanDeleteTable);
    AssertEquals(AWhat + ': nothing told', 0, FRich.Refused);
  end;

begin
  LoadRtf(TableRtf(2, 2, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  FRich.SelStart := 0;
  Check('outside', False, True, False, False, False, False);
  FRich.SelStart := t.ParaStart(f + 2);
  Check('in a cell', True, False, True, True, True, True);
  // a selection from outside into the table: InsertTable goes at its start
  FRich.SelStart := 1;
  FRich.SelLength := t.ParaStart(f + 2) - 1;
  Check('from outside in', True, True, True, True, True, True);
  // whole rows selected down to the next paragraph: the caret stands for the last selected
  FRich.SelStart := t.ParaStart(f + 2);
  FRich.SelLength := t.ParaStart(f + 4) - t.ParaStart(f + 2);
  Check('the last row, whole', True, False, True, True, True, True);
  FRich.SelStart := t.ParaStart(f + 2);
  FRich.ReadOnly := True;
  Check('read-only', True, False, False, False, False, False);
  FRich.ReadOnly := False;
  FRich.PlainText := True;
  Check('plain text', True, False, False, False, False, False);
  FRich.PlainText := False;
  FRich.Enabled := False;
  Check('disabled', True, False, False, False, False, False);
  FRich.Enabled := True;
  FRich.BeginEdit;
  try
    Check('inside an edit block', True, False, False, False, False, False);
  finally
    FRich.EndEdit;
  end;
  Check('after it', True, False, True, True, True, True);
  // what a table forbids
  LoadRtf(MergedRtf);
  t := d.Text;
  FRich.SelStart := t.ParaStart(FirstTablePara(d) + 4);
  Check('merged', True, False, False, False, False, True);
  LoadRtf(IrregularRtf);
  t := d.Text;
  FRich.SelStart := t.ParaStart(FirstTablePara(d));
  Check('irregular', True, False, True, False, False, True);
  FRich.Lines.Text := 'x';
  t := d.Text;
  FRich.SelStart := 0;
  AssertTrue('63 columns', FRich.InsertTable(1, CRichMaxTableCols));
  Check('63 columns', True, False, True, False, True, True);
  // loading
  // (slices small enough that the load is still going on)
  FRich.Slices(4096, 4096);
  LoadInto(FRich, TablesRtf(5, 2 shl 20), False);
  t := d.Text;
  ResetEvents;
  AssertTrue('loading', FRich.Loading);
  FRich.SelStart := t.ParaStart(FirstTablePara(d));
  Check('loading', True, False, False, False, False, False);
  FRich.FinishLoading;
  FRich.Slices(CRtfFirstSliceBytes, CRichLoadStepBytes);
  Check('loaded', True, False, True, True, True, True);
end;

procedure TTyRichTableEditTest.TestTheCanFunctionsAnswerFromWhatTheyFound;
const
  Rows = 10000;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k: Integer;
  first: Int64;
  r: TRect;

  procedure AskAll;
  begin
    FRich.InTable;
    FRich.CanInsertTable;
    FRich.CanInsertRow;
    FRich.CanInsertColumn;
    FRich.CanDeleteRow;
    FRich.CanDeleteColumn;
    FRich.CanDeleteTable;
  end;

begin
  LongTable(Rows);
  d := FRich.Document;
  t := d.Text;
  // a second table, of one cell, after the long one's 'after'
  AssertTrue('a second table', d.Execute(TTyRichInsertTable.Create(t.Length, 1, 1)));
  d.ClearUndo;
  FRich.UpdateView;
  AssertTrue('the second table', d.CellAt(2 * Rows + 2) <> nil);
  k := 1 + 2 * (Rows div 2);
  FRich.SelStart := t.ParaStart(k);
  d.TableParaVisits := 0;
  AssertTrue('a row can be inserted', FRich.CanInsertRow);
  first := d.TableParaVisits;
  // the table read once: its paragraphs and the one on either side
  AssertEquals('the first answer: the table read once', 2 * Rows + 2, first);
  AskAll;
  AskAll;
  AssertEquals('asked again: nothing read', first, d.TableParaVisits);
  { Moves inside the table - a key, another, a click in another row: what is true of the
    whole table is kept, nothing is read again. }
  Press(VK_DOWN);
  AssertEquals('Down', t.ParaStart(k + 2), FRich.CaretIndex);
  AskAll;
  Press(VK_RIGHT);
  AskAll;
  FRich.UpdateView;
  r := FRich.PositionRect(t.ParaStart(k + 4));
  FRich.PressAt(r.Left + 1, (r.Top + r.Bottom) div 2);
  FRich.ReleaseAt(r.Left + 1, (r.Top + r.Bottom) div 2);
  AssertEquals('a click in another row', t.ParaStart(k + 4), FRich.CaretIndex);
  AskAll;
  AssertEquals('moves inside the table: nothing read', first, d.TableParaVisits);
  AssertTrue('the answers there', FRich.CanInsertRow and FRich.CanDeleteColumn);
  // an edit: read again
  FRich.SelText := 'x';
  AskAll;
  AssertEquals('an edit: read again', 2 * first, d.TableParaVisits);
  // the caret into another table: that one read (its cell and the paragraph on either side)
  FRich.SelStart := t.ParaStart(2 * Rows + 2);
  AskAll;
  AssertEquals('another table: read', 2 * first + 3, d.TableParaVisits);
  FRich.SelStart := t.ParaStart(k);
  AskAll;
  AssertEquals('back in the first: read again', 3 * first + 3, d.TableParaVisits);
  // outside a table: nothing read; and the answers follow the caret
  FRich.SelStart := 0;
  AskAll;
  AssertEquals('outside: nothing read', 3 * first + 3, d.TableParaVisits);
  AssertFalse('outside: no row', FRich.CanInsertRow);
  FRich.SelStart := t.ParaStart(k);
  AssertTrue('inside: a row', FRich.CanInsertRow);
  // the caret end alone moves (the anchor stays in the table): asked again
  FRich.SelLength := t.Length - FRich.SelStart;
  AssertFalse('the caret end outside: no row', FRich.CanInsertRow);
  FRich.SelLength := 1;
  AssertTrue('the caret end back in a cell: a row', FRich.CanInsertRow);
  FRich.SelStart := t.ParaStart(k);
  // a state of the document is part of the answer
  FRich.ReadOnly := True;
  AssertFalse('read-only', FRich.CanInsertRow);
  FRich.ReadOnly := False;
  AssertTrue('again', FRich.CanInsertRow);
end;

{ ---- tables of a file read on demand ---- }

procedure TTyRichTableEditTest.TestTablesOfAFileReadOnDemand;
var
  b, o: TBytes;
  d, probe: TTyRichDocument;
  t: TTyRichText;
  k, i, f: Integer;
  info: TTyRichTableInfo;
  before: string;
  q: TTyRichPos;
begin
  // while the load runs: every action and Tab's row refused, the reason told
  // (slices small enough that the load is still going on)
  FRich.Slices(4096, 4096);
  LoadInto(FRich, TablesRtf(5, 2 shl 20), False);
  ResetEvents;
  FRich.WantTabs := True;
  d := FRich.Document;
  t := d.Text;
  AssertTrue('loading', FRich.Loading);
  f := FirstTablePara(d);
  before := Shape(d, f);
  // the first table's last cell (the paragraph after it is read)
  d.TableInfoAt(f, info);
  FRich.SelStart := t.ParaStart(info.Last);
  Press(VK_TAB);
  AssertEquals('Tab''s row while loading: told', 1, FRich.Refused);
  AssertEquals('Tab''s row while loading: why', rsRichEditRefusedLoading, FRich.LastReason);
  AssertEquals('no row', before, Shape(d, f));
  ResetEvents;
  FRich.SelStart := t.ParaStart(f);
  Press(VK_TAB);
  CheckSel('Tab moves while loading', t.ParaStart(f + 1), Length('r0 b'));
  CheckRefused('loading: a row', FRich.InsertRow, rsRichEditRefusedLoading);
  CheckRefused('loading: a column', FRich.DeleteColumn, rsRichEditRefusedLoading);
  CheckRefused('loading: the table', FRich.DeleteTable, rsRichEditRefusedLoading);
  CheckRefused('loading: a table', FRich.InsertTable(1, 1), rsRichEditRefusedLoading);
  FRich.FinishLoading;
  FRich.Slices(CRtfFirstSliceBytes, CRichLoadStepBytes);
  // a small table the reader cut where a parsing block ends: edited whole
  b := TablesRtf(1000, 3 shl 20);
  probe := LoadDoc(b);
  try
    k := -1;
    probe.BeginRead;
    try
      for i := 0 to probe.Text.ParaCount - 1 do
        if (probe.CellAt(i) <> nil) and probe.CellAt(i).Table.Cut then
        begin
          k := i;
          Break;
        end;
    finally
      probe.EndRead;
    end;
  finally
    probe.Free;
  end;
  AssertTrue('a table cut where a block ends', k >= 0);
  LoadInto(FRich, b);
  t := d.Text;
  ResetEvents;
  FRich.SelStart := t.ParaStart(k);
  FRich.UpdateView;
  d.BeginRead;
  try
    AssertTrue('a part', d.TableAt(k).Cut);
  finally
    d.EndRead;
  end;
  // (only part of the table drawn)
  AssertTrue('a part of the table on screen', FRich.VisibleBlockCount < 100);
  AssertTrue('a row: yes', FRich.CanInsertRow);
  AssertTrue('a row', FRich.InsertRow);
  AssertEquals('nothing told', 0, FRich.Refused);
  d.TableInfoAt(k, info);
  AssertEquals('all its rows and the new one', 1001, info.RowCount);
  CheckCaretShown('a row in a table read in parts');
  AssertTrue('the caret in the new row', d.CellAt(t.ParaOfPos(FRich.CaretIndex)) <> nil);
  AssertEquals('in its first cell', 0, d.CellAt(t.ParaOfPos(FRich.CaretIndex)).Index);
  AssertTrue('a column', FRich.DeleteColumn);
  FRich.Undo;
  FRich.Undo;
  o := SaveOf(FRich);
  AssertTrue('undone, saved: the file', SameBytes(b, o));
  // a table over the size bound: refused, the reason told; Tab still moves
  b := TablesRtf(5, 2 shl 20, 15000);
  LoadInto(FRich, b);
  t := d.Text;
  ResetEvents;
  k := 0;
  while (k < t.ParaCount) and (Pos(' r7000 a', ParaText(d, k)) = 0) do Inc(k);
  AssertTrue('the big table', k < t.ParaCount);
  FRich.SelStart := t.ParaStart(k);
  FRich.UpdateView;
  AssertTrue('the cheap answer: yes', FRich.CanInsertRow);
  CheckRefused('too large: a row', FRich.InsertRow, rsRichEditRefusedTableNotWhole);
  CheckRefused('too large: a column', FRich.InsertColumn, rsRichEditRefusedTableNotWhole);
  CheckRefused('too large: delete a row', FRich.DeleteRow, rsRichEditRefusedTableNotWhole);
  CheckRefused('too large: the table', FRich.DeleteTable, rsRichEditRefusedDeleteNotWhole);
  q := t.ParaStart(k + 1);
  Press(VK_TAB);
  CheckSel('Tab moves in it', q, Length('r7000 b'));
  o := SaveOf(FRich);
  AssertTrue('untouched', SameBytes(b, o));
end;

procedure TTyRichTableEditTest.TestTheCanFunctionsReadNoUnreadPartOfAFile;
var
  b: TBytes;
  probe, d: TTyRichDocument;
  k, i, parsed, a, c: Integer;
  bytes: Int64;
begin
  b := TablesRtf(1000, 3 shl 20);
  probe := LoadDoc(b);
  try
    k := -1;
    probe.BeginRead;
    try
      for i := 0 to probe.Text.ParaCount - 1 do
        if (probe.CellAt(i) <> nil) and probe.CellAt(i).Table.Cut then
        begin
          k := i;
          Break;
        end;
    finally
      probe.EndRead;
    end;
  finally
    probe.Free;
  end;
  AssertTrue('a table cut where a block ends', k >= 0);
  LoadInto(FRich, b);
  d := FRich.Document;
  FRich.SelStart := d.Text.ParaStart(k);
  FRich.UpdateView;
  parsed := ParsedParas(d);
  bytes := TyRichRtfLoadOf(d).ParsedBytes;
  AssertTrue('in a table', FRich.InTable);
  AssertTrue('a row', FRich.CanInsertRow);
  AssertTrue('a column', FRich.CanInsertColumn);
  AssertTrue('delete a row', FRich.CanDeleteRow);
  AssertTrue('delete a column', FRich.CanDeleteColumn);
  AssertTrue('delete the table', FRich.CanDeleteTable);
  AssertFalse('no table in it', FRich.CanInsertTable);
  AssertEquals('no paragraph read for them', parsed, ParsedParas(d));
  AssertEquals('no byte of the file parsed for them', bytes, TyRichRtfLoadOf(d).ParsedBytes);
  { A selection put (inside an update) from a paragraph's start to another's, neither read
    yet: whether it is whole rows is not read to answer either. }
  a := d.Text.ParaCount - 60;
  c := d.Text.ParaCount - 40;
  for i := a - 1 to c do
    AssertTrue(Format('paragraph %d not read yet', [i]), d.Text.ParaData[i] = nil);
  parsed := ParsedParas(d);
  bytes := TyRichRtfLoadOf(d).ParsedBytes;
  d.BeginUpdate;
  try
    FRich.SelStart := d.Text.ParaStart(a);
    FRich.SelLength := d.Text.ParaStart(c) - d.Text.ParaStart(a);
    FRich.InTable;
    FRich.CanInsertTable;
    FRich.CanInsertRow;
    FRich.CanInsertColumn;
    FRich.CanDeleteRow;
    FRich.CanDeleteColumn;
    FRich.CanDeleteTable;
    AssertEquals('the selection: no paragraph read', parsed, ParsedParas(d));
    AssertEquals('the selection: no byte parsed', bytes, TyRichRtfLoadOf(d).ParsedBytes);
  finally
    d.EndUpdate;
  end;
  // the caret put (inside an update: nothing laid out) in a paragraph not read yet
  k := d.Text.ParaCount - 20;
  AssertTrue('a paragraph not read yet', d.Text.ParaData[k] = nil);
  parsed := ParsedParas(d);
  d.BeginUpdate;
  try
    FRich.SelStart := d.Text.ParaStart(k);
    AssertFalse('answered as outside a table', FRich.InTable);
    AssertEquals('and not read for it', parsed, ParsedParas(d));
  finally
    d.EndUpdate;
  end;
  // once the paragraph is read, the real answer: that answer was not kept
  d.BeginRead;
  try
    AssertTrue('a table paragraph', d.CellAt(k) <> nil);
  finally
    d.EndRead;
  end;
  AssertEquals('the caret still there', d.Text.ParaStart(k), FRich.CaretIndex);
  AssertTrue('read: in a table', FRich.InTable);
  AssertTrue('read: a row', FRich.CanInsertRow);
end;

{ ---- the caret, the view, the other paths ---- }

procedure TTyRichTableEditTest.TestCaretKeysAfterStructureEdits;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, n: Integer;
  r: TRect;

  procedure Keys(const AWhen: string; AAbove, ANew, ABelow: Integer);
  begin
    // Up and Down at the cell's x: the row block above and below
    FRich.SelStart := t.ParaStart(AAbove);
    Press(VK_DOWN);
    AssertEquals(AWhen + ': Down', t.ParaStart(ANew), FRich.CaretIndex);
    Press(VK_DOWN);
    AssertEquals(AWhen + ': Down again', t.ParaStart(ABelow), FRich.CaretIndex);
    Press(VK_UP);
    AssertEquals(AWhen + ': Up', t.ParaStart(ANew), FRich.CaretIndex);
    // Right and Left through its empty cells
    Press(VK_RIGHT);
    AssertEquals(AWhen + ': Right', t.ParaStart(ANew + 1), FRich.CaretIndex);
    Press(VK_LEFT);
    AssertEquals(AWhen + ': Left', t.ParaStart(ANew), FRich.CaretIndex);
    Press(VK_END);
    AssertEquals(AWhen + ': End of an empty cell', t.ParaStart(ANew), FRich.CaretIndex);
    Press(VK_HOME);
    AssertEquals(AWhen + ': Home', t.ParaStart(ANew), FRich.CaretIndex);
    Press(VK_END, [ssCtrl]);
    AssertEquals(AWhen + ': Ctrl+End', t.Length, FRich.CaretIndex);
    Press(VK_HOME, [ssCtrl]);
    AssertEquals(AWhen + ': Ctrl+Home', 0, FRich.CaretIndex);
    Press(VK_NEXT);
    AssertEquals(AWhen + ': PageDown to the last line', t.ParaCount - 1,
      t.ParaOfPos(FRich.CaretIndex));
    Press(VK_PRIOR);
    AssertEquals(AWhen + ': PageUp to the first', 0, t.ParaOfPos(FRich.CaretIndex));
    // a click in the cell
    FRich.UpdateView;
    r := FRich.PositionRect(t.ParaStart(ANew + 1));
    FRich.PressAt(r.Left + 1, (r.Top + r.Bottom) div 2);
    FRich.ReleaseAt(r.Left + 1, (r.Top + r.Bottom) div 2);
    AssertEquals(AWhen + ': a click', t.ParaStart(ANew + 1), FRich.CaretIndex);
  end;

begin
  LoadRtf(TableRtf(3, 2, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  // a row inserted below row 0: its empty cells between row 0 and the old row 1
  FRich.SelStart := t.ParaStart(f);
  AssertTrue('a row', FRich.InsertRow);
  Keys('a new row', f, f + 2, f + 4);
  for n := 0 to 1 do
  begin
    FRich.Undo;
    // undone: from row 0 down into row 1 again
    FRich.SelStart := t.ParaStart(f);
    Press(VK_DOWN);
    AssertEquals(Format('%d: undone: Down', [n]), t.ParaStart(f + 2), FRich.CaretIndex);
    AssertEquals(Format('%d: undone: the old row', [n]), 'r1c0', ParaText(d, f + 2));
    FRich.Redo;
    Keys(Format('%d: redone', [n]), f, f + 2, f + 4);
  end;
  FRich.Undo;
  // a column inserted: the new cells in the middle of every row
  FRich.SelStart := t.ParaStart(f);
  AssertTrue('a column', FRich.InsertColumn);
  FRich.SelStart := t.ParaStart(f);
  Press(VK_RIGHT);
  Press(VK_RIGHT);
  Press(VK_RIGHT);
  Press(VK_RIGHT);
  Press(VK_RIGHT);
  AssertEquals('Right into the new cell', t.ParaStart(f + 1), FRich.CaretIndex);
  Press(VK_DOWN);
  AssertEquals('Down: the new cell of the next row', t.ParaStart(f + 4), FRich.CaretIndex);
  FRich.Undo;
  // a row deleted: from the row above down into the row that took its place
  FRich.SelStart := t.ParaStart(f + 2);
  AssertTrue('row 1 deleted', FRich.DeleteRow);
  FRich.SelStart := t.ParaStart(f);
  Press(VK_DOWN);
  AssertEquals('Down: the row that took its place', t.ParaStart(f + 2), FRich.CaretIndex);
  AssertEquals('which is the old row 2', 'r2c0', ParaText(d, f + 2));
  Press(VK_DOWN);
  AssertEquals('Down: what followed the table', f + 4, t.ParaOfPos(FRich.CaretIndex));
  FRich.Undo;
  // the table deleted: the paragraphs around it
  FRich.SelStart := t.ParaStart(f + 2);
  AssertTrue('the table', FRich.DeleteTable);
  Press(VK_UP);
  AssertEquals('Up: the paragraph before', 0, t.ParaOfPos(FRich.CaretIndex));
  Press(VK_DOWN);
  AssertEquals('Down: the paragraph after', t.ParaStart(1), FRich.CaretIndex);
  FRich.Undo;
  FRich.SelStart := 0;
  Press(VK_DOWN);
  AssertEquals('undone: Down into the table', t.ParaStart(f), FRich.CaretIndex);
  FRich.Redo;
  FRich.SelStart := 0;
  Press(VK_DOWN);
  AssertEquals('redone: Down to after', t.ParaStart(1), FRich.CaretIndex);
end;

procedure TTyRichTableEditTest.TestTheViewIsAFreshControlsAfterEachAction;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, n: Integer;
  ok: Boolean;
  what: string;
begin
  { Wide enough for every table here: the horizontal extent is the widest block laid out so
    far, by design (it is never measured over the document), so a table made narrower again
    would leave a bar a new control has not. }
  FRich.SetBounds(0, 0, 700, 300);
  LoadRtf(TableRtf(6, 3, [4]));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  for n := 0 to 6 do
  begin
    FRich.SelStart := t.ParaStart(f + 7);
    FRich.UpdateView;
    PaintAll(FRich);
    case n of
      0: ok := FRich.InsertRow;
      1: ok := FRich.InsertRow(False);
      2: ok := FRich.InsertColumn;
      3: ok := FRich.InsertColumn(False);
      4: ok := FRich.DeleteRow;
      5: ok := FRich.DeleteColumn;
    else
      ok := FRich.DeleteTable;
    end;
    what := Format('action %d', [n]);
    AssertTrue(what, ok);
    CheckLikeFresh(what);
    FRich.Undo;
    CheckLikeFresh(what + ', undone');
    FRich.Redo;
    CheckLikeFresh(what + ', redone');
    FRich.Undo;
  end;
  // a table inserted, and the caret scrolled to it at the view's bottom
  FRich.SelStart := t.Length;
  FRich.UpdateView;
  PaintAll(FRich);
  AssertTrue('a table', FRich.InsertTable(4, 4));
  CheckLikeFresh('a new table');
  FRich.Undo;
  CheckLikeFresh('a new table, undone');
  FRich.Redo;
  CheckLikeFresh('a new table, redone');
end;

procedure TTyRichTableEditTest.TestARowEditLaysOutOnlyTheRowsItChanged;
const
  Rows = 2000;
var
  d: TTyRichDocument;
  t: TTyRichText;
  k, held: Integer;
begin
  LongTable(Rows);
  d := FRich.Document;
  t := d.Text;
  k := 1 + 2 * (Rows div 2);
  FRich.SelStart := t.ParaStart(k);
  FRich.UpdateView;
  PaintAll(FRich);
  held := FRich.VisibleBlockCount;
  FRich.ResetCounts;
  AssertTrue('a row', FRich.InsertRow);
  FRich.UpdateView;
  PaintAll(FRich);
  // the new row, the row above it (its bottom line) and the row below it, two cells each
  AssertEquals(Format('rows laid out again of %d shown', [held]), 3 * 2, FRich.LaidParas);
  FRich.ResetCounts;
  FRich.Undo;
  FRich.UpdateView;
  PaintAll(FRich);
  AssertTrue(Format('undone: %d paragraphs laid out again', [FRich.LaidParas]),
    FRich.LaidParas <= 2 * 2);
  FRich.ResetCounts;
  AssertTrue('a row deleted', FRich.DeleteRow);
  FRich.UpdateView;
  PaintAll(FRich);
  AssertTrue(Format('a row deleted: %d paragraphs laid out again', [FRich.LaidParas]),
    FRich.LaidParas <= 2 * 2);
  CheckCaretShown('a row deleted');
  FRich.Undo;
  FRich.UpdateView;
  PaintAll(FRich);
  FRich.ResetCounts;
  AssertTrue('a column', FRich.InsertColumn);
  FRich.UpdateView;
  PaintAll(FRich);
  { A column changes every row: those the view holds (the screen and one either side) are
    laid out again, not the table's other rows. }
  AssertTrue(Format('a column: %d paragraphs laid out again', [FRich.LaidParas]),
    (FRich.LaidParas > 0) and (FRich.LaidParas <= 3 * 150));
  CheckCaretShown('a column');
end;

procedure TTyRichTableEditTest.TestThePathsThatStayAsTheyWereOnAChangedTable;
const
  RowsRtf = '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'trowd' + BS + 'cellx1000' + BS + 'cellx2000' +
    BS + 'pard' + BS + 'intbl p1' + BS + 'cell p2' + BS + 'cell' + BS + 'row}';
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, n, w, skipped: Integer;
  before: string;
begin
  for n := 0 to 1 do
  begin
    LoadRtf(TableRtf(3, 3, []));
    d := FRich.Document;
    t := d.Text;
    f := FirstTablePara(d);
    // a table an action changed: a row inserted, a column deleted
    FRich.SelStart := t.ParaStart(f);
    AssertTrue('a row', FRich.InsertRow);
    FRich.SelStart := t.ParaStart(f);
    if n = 0 then AssertTrue('a column gone', FRich.DeleteColumn)
    else AssertTrue('a column', FRich.InsertColumn);
    before := Shape(d, f);
    // a row's paragraphs
    w := 2 + 2 * n;
    ResetEvents;
    { a selection across a cell's edge selects those cells (tyControls.RichEdit.TableSel):
      typing, Delete and Backspace take them, each one step }
    FRich.SelStart := t.ParaStart(f) + 1;
    FRich.SelLength := t.ParaStart(f + 1) + 1 - FRich.SelStart;
    FRich.Key8('x');
    AssertEquals('typed over cells: taken', 0, FRich.Refused);
    AssertTrue('typed over cells: the first cell', Pos('x|', Shape(d, f)) = 1);
    FRich.Undo;
    AssertEquals('typed over cells: undone', before, Shape(d, f));
    FRich.SelStart := t.ParaStart(f) + 1;
    FRich.SelLength := t.ParaStart(f + 1) + 1 - FRich.SelStart;
    Press(VK_DELETE);
    AssertEquals('Delete over cells: taken', 0, FRich.Refused);
    AssertTrue('Delete over cells: cleared', Pos('|', Shape(d, f)) = 1);
    FRich.Undo;
    AssertEquals('Delete over cells: undone', before, Shape(d, f));
    FRich.SelStart := t.ParaStart(f) + 1;
    FRich.SelLength := t.ParaStart(f + 1) + 1 - FRich.SelStart;
    Press(VK_BACK);
    AssertEquals('Backspace over cells: taken', 0, FRich.Refused);
    AssertTrue('Backspace over cells: changed', Shape(d, f) <> before);
    FRich.Undo;
    AssertEquals('Backspace over cells: undone', before, Shape(d, f));
    // a cut, a paste of plain text and a replace over them: refused, as before
    FRich.SelStart := t.ParaStart(f) + 1;
    FRich.SelLength := t.ParaStart(f + 1) + 1 - FRich.SelStart;
    ResetEvents;
    FRich.CutToClipboard;
    CheckRefused('Cut over cells', False, rsRichEditRefusedCells);
    FRich.ClipRtf := '';
    FRich.ClipText := 'pasted';
    FRich.PasteFromClipboard;
    CheckRefused('Paste over cells', False, rsRichEditRefusedCells);
    AssertEquals('replace over cells: nothing replaced', 0,
      FRich.ReplaceAll(ParaText(d, f) + LineEnding + ParaText(d, f + 1), 'y', [], skipped));
    AssertEquals('replace over cells: skipped', 1, skipped);
    AssertEquals('nothing changed', before, Shape(d, f));
    { whole rows: Delete clears their cells (the first row's - the inserted one is empty),
      Backspace and Cut take them }
    FRich.SelStart := t.ParaStart(f);
    FRich.SelLength := t.ParaStart(f + w) - FRich.SelStart;
    Press(VK_DELETE);
    AssertEquals('Delete: whole rows', 0, FRich.Refused);
    AssertTrue('Delete: their cells cleared', Shape(d, f) <> before);
    FRich.Undo;
    AssertEquals('undone', before, Shape(d, f));
    FRich.SelStart := t.ParaStart(f + w);
    FRich.SelLength := t.ParaStart(f + 2 * w) - FRich.SelStart;
    Press(VK_BACK);
    AssertEquals('Backspace: whole rows', 0, FRich.Refused);
    AssertTrue('Backspace: a row less', Shape(d, f) <> before);
    FRich.Undo;
    FRich.SelStart := t.ParaStart(f + w);
    FRich.SelLength := t.ParaStart(f + 2 * w) - FRich.SelStart;
    FRich.CutToClipboard;
    AssertEquals('Cut: whole rows', 0, FRich.Refused);
    AssertTrue('Cut: a row less', Shape(d, f) <> before);
    FRich.Undo;
    AssertEquals('undone again', before, Shape(d, f));
    // rows pasted with the caret in a cell: cell by cell from it
    FRich.SelStart := t.ParaStart(f);
    FRich.ClipRtf := RowsRtf;
    FRich.ClipText := '';
    FRich.PasteFromClipboard;
    AssertEquals('pasted into a cell: not refused', 0, FRich.Refused);
    AssertEquals('as many rows', Length(before) - Length(StringReplace(before, '/', '', [rfReplaceAll])),
      Length(Shape(d, f)) - Length(StringReplace(Shape(d, f), '/', '', [rfReplaceAll])));
    AssertTrue('the rows'' cells in the cells', Pos('p1|p2', Shape(d, f)) = 1);
    FRich.Undo;
    // rows pasted over whole rows: cell by cell from their first
    FRich.SelStart := t.ParaStart(f + w);
    FRich.SelLength := t.ParaStart(f + 2 * w) - FRich.SelStart;
    FRich.PasteFromClipboard;
    AssertEquals('rows over rows: not refused', 0, FRich.Refused);
    AssertTrue('rows over rows: there', Pos('/p1|p2', Shape(d, f)) > 0);
    FRich.Undo;
    AssertEquals('nothing changed at last', before, Shape(d, f));
  end;
end;

{ ---- which cells, which paragraph, the edges ---- }

procedure TTyRichTableEditTest.TestDeleteColumnTakesTheColumnOfEveryCellCovered;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f: Integer;
  shape0: string;

  procedure Sel(AAnchor, ACaret: TTyRichPos);
  begin
    FRich.SelStart := AAnchor;
    FRich.SelLength := ACaret - AAnchor;
  end;

  procedure Check(const AWhat, AShape: string; ACaretPara: Integer = -1);
  begin
    AssertTrue(AWhat + ': done', FRich.DeleteColumn);
    if ACaretPara >= 0 then CheckSel(AWhat + ': the caret', t.ParaStart(ACaretPara), 0);
    if AShape = '' then
    begin
      AssertEquals(AWhat + ': the table gone', -1, FirstTablePara(d));
      AssertEquals(AWhat + ': a step of its own', rsRichUndoDeleteTable, d.UndoDescription);
    end
    else
    begin
      AssertEquals(AWhat + ': the columns left', AShape, Shape(d, f));
      AssertEquals(AWhat + ': one step', rsRichUndoDeleteColumn, d.UndoDescription);
    end;
    FRich.Undo;
    AssertEquals(AWhat + ': undone', shape0, Shape(d, f));
  end;

begin
  LoadRtf(TableRtf(2, 3, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  shape0 := Shape(d, f);
  // from before the table into row 1: every cell of row 0 is covered
  Sel(2, t.ParaStart(f + 3) + 2);
  Check('from before the table into row 1', '');
  // from after the table back into row 0's last cell: every cell of row 1 is covered
  Sel(t.ParaStart(f + 6) + 2, t.ParaStart(f + 2) + 1);
  Check('from after the table into row 0', '');
  // from before the table into row 0: the cells up to the end's
  Sel(2, t.ParaStart(f + 1) + 1);
  Check('from before the table into row 0', 'r0c2/r1c2');
  // ends in rows next to each other: the start's cell to its row's end, the end's row to its cell
  Sel(t.ParaStart(f + 2) + 1, t.ParaStart(f + 3) + 1);
  // (the caret in its row's cell that took the place of the first column that went)
  Check('row 0''s last cell to row 1''s first', 'r0c1/r1c1', f + 1);
  Sel(t.ParaStart(f + 3) + 1, t.ParaStart(f + 2) + 1);
  Check('the same, reversed', 'r0c1/r1c1');
  Sel(t.ParaStart(f + 1) + 1, t.ParaStart(f + 4) + 1);
  Check('row 0''s second cell to row 1''s second', '');
  // in one row, reversed
  Sel(t.ParaStart(f + 2) + 1, t.ParaStart(f + 1) + 1);
  Check('in one row, reversed', 'r0c0/r1c0');
end;

procedure TTyRichTableEditTest.TestTheCaretStandsForOneParagraphForEveryAction;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, m: Integer;
begin
  // a selection from the paragraph above to the first cell's start: the caret is in that cell
  LoadRtf(TableRtf(2, 2, []));
  FRich.WantTabs := True;
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  FRich.SelStart := 2;
  FRich.SelLength := t.ParaStart(f) - 2;
  AssertTrue('in a table', FRich.InTable);
  AssertTrue('a row: yes', FRich.CanInsertRow);
  AssertTrue('a row', FRich.InsertRow);
  AssertEquals('below the caret''s row', 'r0c0|r0c1/|/r1c0|r1c1', Shape(d, f));
  AssertEquals('nothing told', 0, FRich.Refused);
  FRich.Undo;
  FRich.SelStart := 2;
  FRich.SelLength := t.ParaStart(f) - 2;
  Press(VK_TAB);
  CheckSel('Tab from the same cell', t.ParaStart(f + 1), 4);
  { inside the table from a cell's inside to the next row's start: the cells of rows 0 and 1
    (tyControls.RichEdit.TableSel) - as many columns and rows as they span }
  LoadRtf(TableRtf(3, 2, []));
  t := d.Text;
  f := FirstTablePara(d);
  FRich.SelStart := t.ParaStart(f) + 2;
  FRich.SelLength := t.ParaStart(f + 4) - FRich.SelStart;
  AssertTrue('columns', FRich.InsertColumn);
  AssertEquals('right of the selected cells', 'r0c0|r0c1||/r1c0|r1c1||/r2c0|r2c1||', Shape(d, f));
  FRich.Undo;
  FRich.SelStart := t.ParaStart(f) + 2;
  FRich.SelLength := t.ParaStart(f + 4) - FRich.SelStart;
  AssertTrue('rows', FRich.InsertRow);
  AssertEquals('below the selected rows', 'r0c0|r0c1/r1c0|r1c1/|/|/r2c0|r2c1', Shape(d, f));
  FRich.Undo;
  // whole rows down to the next row's start: the caret stands for the last of them
  FRich.SelStart := t.ParaStart(f + 2);
  FRich.SelLength := t.ParaStart(f + 4) - FRich.SelStart;
  AssertTrue('a row below whole rows', FRich.InsertRow);
  AssertEquals('below the selected row', 'r0c0|r0c1/r1c0|r1c1/|/r2c0|r2c1', Shape(d, f));
  FRich.Undo;
  // Tab with the last row selected whole, down to the paragraph after the table: its last
  // cell's Tab - a row below
  FRich.SelStart := t.ParaStart(f + 4);
  FRich.SelLength := t.ParaStart(f + 6) - FRich.SelStart;
  Press(VK_TAB);
  AssertEquals('Tab: a row below the selected one', 'r0c0|r0c1/r1c0|r1c1/r2c0|r2c1/|', Shape(d, f));
  CheckSel('Tab: its first cell', t.ParaStart(f + 6), 0);
  FRich.Undo;
  // two tables that touch, a selection from the first ending at the second's cell: Tab's row
  // goes into the second, below the caret's row
  LoadRtf(TouchRtf);
  t := d.Text;
  f := FirstTablePara(d);
  m := f + 2;
  AssertTrue('the paragraph between deleted', d.Execute(TTyRichDelete.Create(t.ParaStart(m),
    t.ParaLength(m) + 1)));
  FRich.UpdateView;
  AssertEquals('the second table', 'b0', Shape(d, f + 2));
  FRich.SelStart := t.ParaStart(f + 1) + 1;
  FRich.SelLength := t.ParaStart(f + 2) - FRich.SelStart;
  Press(VK_TAB);
  AssertEquals('the first table as it was', 'a0|a1', Shape(d, f));
  AssertEquals('a row in the second', 'b0/', Shape(d, f + 2));
  CheckSel('its cell', t.ParaStart(f + 3), 0);
end;

procedure TTyRichTableEditTest.TestTheTableKeysAndActionsAtTheEdges;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, n, i: Integer;
  before: string;
  ok: Boolean;
  lp: TLoaderProbe;

  function Act(AIndex: Integer): Boolean;
  begin
    case AIndex of
      0: Result := FRich.InsertRow;
      1: Result := FRich.InsertColumn;
      2: Result := FRich.DeleteRow;
      3: Result := FRich.DeleteColumn;
      4: Result := FRich.DeleteTable;
    else
      Result := FRich.InsertTable(2, 2);
    end;
  end;

begin
  LoadRtf(TableRtf(2, 2, []));
  FRich.WantTabs := True;
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  // a composition open in the cell goes in before Tab moves
  FRich.SelStart := t.ParaStart(f);
  FRich.UpdateComposition('xy');
  AssertTrue('composing', FRich.Composing);
  Press(VK_TAB);
  AssertFalse('the composition ended', FRich.Composing);
  AssertEquals('it went in where it was', 'xyr0c0', ParaText(d, f));
  CheckSel('then Tab moved', t.ParaStart(f + 1), 4);
  FRich.Undo;
  // Alt+Tab and Meta+Tab are not the table's keys: a tab character, as outside a table
  FRich.SelStart := t.ParaStart(f);
  Press(VK_TAB, [ssAlt]);
  AssertEquals('Alt+Tab: a tab character', #9 + 'r0c0', ParaText(d, f));
  Press(VK_TAB, [ssMeta]);
  AssertEquals('Meta+Tab: a tab character', #9#9 + 'r0c0', ParaText(d, f));
  FRich.Undo;
  FRich.Undo;
  before := Shape(d, f);
  FRich.SelStart := t.ParaStart(f);
  // disabled, inside BeginEdit, inside the document's update: nothing, nothing told
  for n := 0 to 2 do
  begin
    case n of
      0: FRich.Enabled := False;
      1: FRich.BeginEdit;
    else
      d.BeginUpdate;
    end;
    try
      ResetEvents;
      for i := 0 to 5 do
      begin
        ok := Act(i);
        AssertFalse(Format('%d, %d: not done', [n, i]), ok);
      end;
      AssertEquals(Format('%d: nothing told', [n]), 0, FRich.Refused);
    finally
      case n of
        0: FRich.Enabled := True;
        1: FRich.EndEdit;
      else
        d.EndUpdate;
      end;
    end;
    AssertEquals(Format('%d: nothing changed', [n]), before, Shape(d, f));
  end;
  AssertTrue('afterwards: done', FRich.InsertRow);
  // a read that raises: the answer is no, and it is not kept - asked again, read again
  lp := TLoaderProbe.Create(nil);
  try
    lp.Controller := FCtl;
    lp.Font.PixelsPerInch := 96;
    lp.SetBounds(0, 0, 400, 300);
    d := lp.Document;
    t := d.Text;
    AssertTrue('a table', d.Execute(TTyRichInsertTable.Create(t.ParaStart(1), 2, 2)));
    lp.UpdateView;
    lp.SelStart := t.ParaStart(2);
    // the paragraphs around the table sent back unread: a read of the table reads them
    AssertTrue('before unread', TBuilderAccess.UnsetParagraph(d, 0, t.ParaData[0]));
    AssertTrue('after unread', TBuilderAccess.UnsetParagraph(d, 5, t.ParaData[5]));
    lp.Loader.Fail := True;
    AssertFalse('the read raised: no', lp.CanInsertRow);
    AssertEquals('nothing told', 0, lp.Refused);
    lp.Loader.Fail := False;
    AssertTrue('asked again: read again, yes', lp.CanInsertRow);
  finally
    lp.Free;
  end;
end;

{ Several columns go as one step of column deletes, each of the same table - whatever the parts
  before it took away of the rows above the caret's, and with another table after it. }
procedure TTyRichTableEditTest.TestSeveralColumnsGoFromTheirOwnTable;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, r: Integer;
  before: TBytes;
  msg, shape0, other: string;

  procedure Sel(AAnchor, ACaret: TTyRichPos);
  begin
    FRich.SelStart := AAnchor;
    FRich.SelLength := ACaret - AAnchor;
  end;

  procedure Check(const AWhat, AShape: string);
  var
    after: string;
  begin
    before := SaveOf(FRich);
    ResetEvents;
    AssertTrue(AWhat + ': done', FRich.DeleteColumn);
    AssertEquals(AWhat + ': nothing told', 0, FRich.Refused);
    AssertEquals(AWhat + ': the columns left', AShape, Shape(d, f));
    AssertEquals(AWhat + ': one step', rsRichUndoDeleteColumn, d.UndoDescription);
    after := Shape(d, f);
    FRich.Undo;
    AssertTrue(AWhat + ': undone, the file''s bytes', SameBytes(before, SaveOf(FRich)));
    FRich.Redo;
    AssertEquals(AWhat + ': redone', after, Shape(d, f));
    FRich.Undo;
  end;

begin
  // two cells of row 1 of a 2 x 3 table
  LoadRtf(TableRtf(2, 3, []));
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  Sel(t.ParaStart(f + 4) + 1, t.ParaStart(f + 5) + 1);
  Check('two cells of the lower row', ShapeWithout(2, 3, [1, 2]));
  // 3 x 3, from row 1's last cell to row 2's first: columns 0 and 2
  LoadRtf(TableRtf(3, 3, []));
  t := d.Text;
  f := FirstTablePara(d);
  Sel(t.ParaStart(f + 5) + 1, t.ParaStart(f + 6) + 1);
  Check('row 1''s last cell to row 2''s first', ShapeWithout(3, 3, [0, 2]));
  // 3 x 4: two and three columns in each row, column 0 among them, one reversed
  LoadRtf(TableRtf(3, 4, []));
  t := d.Text;
  f := FirstTablePara(d);
  for r := 0 to 2 do
  begin
    msg := Format('row %d', [r]);
    Sel(t.ParaStart(f + 4 * r + 1) + 1, t.ParaStart(f + 4 * r + 2) + 1);
    Check(msg + ': columns 1 and 2', ShapeWithout(3, 4, [1, 2]));
    Sel(t.ParaStart(f + 4 * r) + 1, t.ParaStart(f + 4 * r + 2) + 1);
    Check(msg + ': columns 0 to 2', ShapeWithout(3, 4, [0, 1, 2]));
    Sel(t.ParaStart(f + 4 * r + 3) + 1, t.ParaStart(f + 4 * r + 2) + 1);
    Check(msg + ': columns 2 and 3, reversed', ShapeWithout(3, 4, [2, 3]));
  end;
  // a second table after a paragraph of one character: never touched
  LoadRtf(TwoTablesApartRtf(2, 3));
  t := d.Text;
  f := FirstTablePara(d);
  AssertEquals('the paragraph between', 'm', ParaText(d, f + 6));
  other := Shape(d, f + 7);
  AssertEquals('the second table', 'b0c0|b0c1/b1c0|b1c1', other);
  shape0 := Shape(d, f);
  Sel(t.ParaStart(f + 4) + 1, t.ParaStart(f + 5) + 1);
  before := SaveOf(FRich);
  AssertTrue('two cells of the first table''s last row', FRich.DeleteColumn);
  AssertEquals('its columns 1 and 2 gone', ShapeWithout(2, 3, [1, 2]), Shape(d, f));
  AssertEquals('the second table as it was', other, Shape(d, f + 3));
  FRich.Undo;
  AssertEquals('undone', shape0, Shape(d, f));
  AssertTrue('undone: the file''s bytes', SameBytes(before, SaveOf(FRich)));
  FRich.Redo;
  AssertEquals('redone: the second table as it was', other, Shape(d, f + 3));
end;

{ Two tables that came to touch, every row of both selected down to the paragraph after them:
  the caret stands for the last selected row, the second table's; DeleteRow takes the rows of
  the caret's table. }
procedure TTyRichTableEditTest.TestWholeRowsOfTablesThatTouch;
var
  d: TTyRichDocument;
  t: TTyRichText;
  f, m: Integer;
begin
  LoadRtf(TwoTablesRtf);
  d := FRich.Document;
  t := d.Text;
  f := FirstTablePara(d);
  m := f + 2;
  AssertTrue('the paragraph between deleted', d.Execute(TTyRichDelete.Create(t.ParaStart(m),
    t.ParaLength(m) + 1)));
  FRich.UpdateView;
  AssertEquals('the second table', 'b0|b1/b2|b3', Shape(d, f + 2));
  FRich.SelStart := t.ParaStart(f);
  FRich.SelLength := t.ParaStart(f + 6) - FRich.SelStart;
  AssertTrue('in a table', FRich.InTable);
  AssertTrue('a row: yes', FRich.CanDeleteRow);
  AssertTrue('the rows', FRich.DeleteRow);
  AssertEquals('nothing told', 0, FRich.Refused);
  AssertEquals('the first table stays', 'a0|a1', Shape(d, f));
  AssertEquals('the second table''s rows gone', 'after', ParaText(d, f + 2));
  FRich.Undo;
  AssertEquals('undone', 'b0|b1/b2|b3', Shape(d, f + 2));
  FRich.SelStart := t.ParaStart(f);
  FRich.SelLength := t.ParaStart(f + 6) - FRich.SelStart;
  AssertTrue('a row below', FRich.InsertRow);
  AssertEquals('below the second table''s last row', 'b0|b1/b2|b3/|', Shape(d, f + 2));
end;

{ The table found for the Can... answers is not kept alive by them once the content changed. }
procedure TTyRichTableEditTest.TestTheAnswersHoldNoTableOfAnOldContent;
var
  d: TTyRichDocument;
  t: TTyRichText;
  tbl: TTyRichTable;
  n: Integer;
begin
  for n := 0 to 1 do
  begin
    FRich.Lines.Text := 'a' + LineEnding + 'b' + LineEnding + 'c' + LineEnding + 'd' + LineEnding + 'x';
    d := FRich.Document;
    t := d.Text;
    tbl := TCountedTable.Create([1500, 3000]);
    tbl.AddRow(2);
    tbl.AddRow(2);
    AssertTrue('a table', d.Execute(TMarkTableCommand.Create(0, tbl, [1, 1, 1, 1])));
    d.ClearUndo;
    FRich.UpdateView;
    FRich.SelStart := t.ParaStart(2);
    AssertTrue('a row: yes', FRich.CanInsertRow);
    AssertEquals('the table alive', 1, TCountedTable.Live);
    if n = 0 then
      // a new content
      FRich.Lines.Text := 'y'
    else
    begin
      // the table deleted, the history let go
      AssertTrue('the table deleted', FRich.DeleteTable);
      d.ClearUndo;
    end;
    AssertEquals(Format('%d: no table alive', [n]), 0, TCountedTable.Live);
  end;
end;

initialization
  RegisterTest(TTyRichTableEditTest);

end.
