unit test.richedit.tablesel;

{ Selecting cells (tyControls.RichEdit.TableSel and the control): the rule that decides it -
  cells are counted by the selected characters, a cell's end mark being one of its own -, the
  rectangle between two cells, whole rows from outside the table, the keys and the mouse's
  zones, what Delete, Backspace, typing and the formats do to selected cells, a copy as a
  small table and tabbed text, a paste filled cell by cell, the highlight, and a column of a
  long table painted where it shows only. A control with the test device and a clipboard of
  the test's; no window. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, LCLType, fpcunit, testregistry, BGRABitmap,
  BGRABitmapTypes, tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TableProps, tyControls.RichEdit.TableSel, tyControls.RichEdit.RtfRead,
  tyControls.RichEdit.Layout, tyControls.RichEdit, tyControls.RichEdit.Builder,
  tyControls.RichEdit.Bookmarks, tyControls.StrConsts, test.richedit.layoutdevice;

type
  TSelRich = class(TTyRichEdit)
  public
    // the next one made draws with the system's fonts (letters with descenders), not the test device
    class var RealFonts: Boolean;
  protected
    function CreateDevice: TTyRichTextDevice; override;
    procedure WriteClipboard(const ARtf: RawByteString; const AText: string); override;
    function ClipboardFlavours: TTyRichClipFlavours; override;
    function ReadClipboardRtf: RawByteString; override;
    function ReadClipboardText: string; override;
  public
    ClipRtf: RawByteString;
    ClipText: string;
    Refusals: TStringList;
    destructor Destroy; override;
    procedure Refused(Sender: TObject; const AReason: string);
    procedure PaintInto(B: TBGRABitmap);
    procedure Press(X, Y: Integer; AShift: TShiftState = []);
    procedure MoveTo(X, Y: Integer; AShift: TShiftState = [ssLeft]);
    procedure Release(X, Y: Integer);
    procedure Key(AKey: Word; AShift: TShiftState = []);
    procedure Typed(const S: string);
    function CursorAtPoint(X, Y: Integer): TCursor;
  end;

  TTyRichTableSelTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TSelRich;
    procedure MakeTable(ARows, ACols: Integer);
    function CellStart(ARow, ACol: Integer): TTyRichPos;
    function CellEnd(ARow, ACol: Integer): TTyRichPos;
    function CellText(ARow, ACol: Integer): string;
    function CellRect(ARow, ACol: Integer): TRect;
    procedure CheckRange(const AMsg: string; R0, C0, R1, C1: Integer);
    procedure CheckWhole(const AMsg: string);
    procedure Sel(AAnchor, ACaret: TTyRichPos);
    function BoldAt(APos: TTyRichPos): Boolean;
    function CentredAt(APos: TTyRichPos): Boolean;
    function RowCount: Integer;
    function ColCount: Integer;
    function HasTable: Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnchorAndCaretInTwoCellsGiveARectangle;
    procedure TestTheCellEndMarkDecidesWholeCell;
    procedure TestOneEndOutsideTakesWholeRows;
    procedure TestIrregularRowsTakeTheCellsUnderTheSpan;
    procedure TestShiftArrowsGrowTheRectangle;
    procedure TestTheSelectMethods;
    procedure TestMouseZones;
    procedure TestTheHandleCoversNoLetter;
    procedure TestDeleteClearsBackspaceRemovesRows;
    procedure TestTypingReplacesTheFirstCell;
    procedure TestNoMarkOfAPairIsLeftAlone;
    procedure TestFormatsReachEveryCell;
    procedure TestCopyIsASmallTableAndTabbedText;
    procedure TestPasteFillsCellByCell;
    procedure TestHighlightCoversWholeCells;
    procedure TestAColumnSelectionPaintsOnlyVisibleRows;
    procedure TestAPartOfALongFileSelectsRowsNotColumns;
    procedure TestSelectingReadsOnlyTheRowsItNeeds;
    procedure TestMarksAtACellsEdgesDecideNothing;
    procedure TestDeleteColumnTakesTheSelectedColumns;
    procedure TestEveryDoorAgreesWithItsCan;
    procedure TestRowsReachedFromOutsideAreWhatTheDoorsTake;
    procedure TestTheCaretAfterRowsGo;
    procedure TestBackspaceAndDeleteOnColumnsRowsAndCells;
    procedure TestDeleteOverANestedRowIsTold;
    procedure TestShiftClickOnAZoneExtendsByRowsOrColumns;
    procedure TestTheRowAndColumnZonesAreWideEnough;
    procedure TestCutOverCellsCopiesAndClears;
    procedure TestTabOverListCellsMovesAndNoLevelChanges;
  end;

implementation

type
  { Parses on demand: paragraph i is cell i mod Cells of row i div Cells of its table; counts
    what it was asked. }
  TSelTableLoader = class(TTyRichParaLoader)
  public
    Calls: Integer;
    ParaFmt: TTyParaFormatId;
    CharFmt: TTyCharFormatId;
    Table: TTyRichTable;
    Cells: Integer;
    constructor Create(ARows, ACells: Integer);
    destructor Destroy; override;
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
  end;

constructor TSelTableLoader.Create(ARows, ACells: Integer);
var
  i: Integer;
begin
  inherited Create;
  Cells := ACells;
  Table := TTyRichTable.Create([1440, 2880]);
  Table.AddRef;
  for i := 1 to ARows do Table.AddRow(ACells);
end;

destructor TSelTableLoader.Destroy;
begin
  Table.Release;
  inherited Destroy;
end;

procedure TSelTableLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
var
  runs: TTyRunArray;
begin
  Inc(Calls);
  runs := nil;
  SetLength(runs, 1);
  runs[0].Start := 0;
  runs[0].Format := CharFmt;
  runs[0].Obj := nil;
  SetParagraph(ADoc, AIndex, ParaFmt, runs,
    Table.Rows[AIndex div Cells].Cells[AIndex mod Cells]);
end;

type
  // another's content, as a drop offers it: text
  TCellOffer = class(TTyRichDropOffer)
  public
    Text: string;
    function Flavours: TTyRichClipFlavours; override;
    function ReadText: string; override;
  end;

function TCellOffer.Flavours: TTyRichClipFlavours;
begin
  Result := [rcfText];
end;

function TCellOffer.ReadText: string;
begin
  Result := Text;
end;

{ ---- the control ---- }

function TSelRich.CreateDevice: TTyRichTextDevice;
begin
  if RealFonts then Result := inherited CreateDevice
  else Result := TTyRichTestDevice.Create;
end;

procedure TSelRich.WriteClipboard(const ARtf: RawByteString; const AText: string);
begin
  ClipRtf := ARtf;
  ClipText := AText;
end;

function TSelRich.ClipboardFlavours: TTyRichClipFlavours;
begin
  Result := [];
  if ClipRtf <> '' then Include(Result, rcfRtf);
  if ClipText <> '' then Include(Result, rcfText);
end;

function TSelRich.ReadClipboardRtf: RawByteString;
begin
  Result := ClipRtf;
end;

function TSelRich.ReadClipboardText: string;
begin
  Result := ClipText;
end;

destructor TSelRich.Destroy;
begin
  Refusals.Free;
  inherited Destroy;
end;

procedure TSelRich.Refused(Sender: TObject; const AReason: string);
begin
  Refusals.Add(AReason);
end;

procedure TSelRich.PaintInto(B: TBGRABitmap);
begin
  RenderTo(B.Canvas, Rect(0, 0, Width, Height), Font.PixelsPerInch);
end;

procedure TSelRich.Press(X, Y: Integer; AShift: TShiftState);
begin
  MouseDown(mbLeft, AShift + [ssLeft], X, Y);
end;

procedure TSelRich.MoveTo(X, Y: Integer; AShift: TShiftState);
begin
  MouseMove(AShift, X, Y);
end;

procedure TSelRich.Release(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TSelRich.Key(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

procedure TSelRich.Typed(const S: string);
var
  k: TUTF8Char;
begin
  k := S;
  UTF8KeyPress(k);
end;

function TSelRich.CursorAtPoint(X, Y: Integer): TCursor;
begin
  Result := CursorAt(X, Y);
end;

{ ---- the fixture ---- }

procedure TTyRichTableSelTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TSelRich.Create(nil);
  FRich.Refusals := TStringList.Create;
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 600, 400);
  FRich.OnEditRefused := @FRich.Refused;
end;

procedure TTyRichTableSelTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

// 'before', an ARows x ACols table of 'rNcM' (each cell 1440 twips), 'after'
procedure TTyRichTableSelTest.MakeTable(ARows, ACols: Integer);
var
  d: TTyRichDocument;
  r, c, f, l: Integer;
begin
  FRich.Lines.Text := 'before' + LineEnding + 'after';
  d := FRich.Document;
  AssertTrue('a table', d.Execute(TTyRichInsertTable.Create(d.Text.ParaStart(1), ARows, ACols,
    1440 * ACols)));
  for r := ARows - 1 downto 0 do
    for c := ACols - 1 downto 0 do
    begin
      d.TableCellParas(1, r, c, f, l);
      d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(f), Format('r%dc%d', [r, c])));
    end;
  d.ClearUndo;
  FRich.UpdateView;
end;

function TTyRichTableSelTest.CellStart(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(f);
end;

// after the cell's end mark
function TTyRichTableSelTest.CellEnd(ARow, ACol: Integer): TTyRichPos;
var
  f, l: Integer;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  Result := FRich.Document.Text.ParaStart(l) + FRich.Document.Text.ParaLength(l) + 1;
end;

function TTyRichTableSelTest.CellText(ARow, ACol: Integer): string;
var
  f, l: Integer;
  t: TTyRichText;
begin
  AssertTrue('the cell', FRich.Document.TableCellParas(1, ARow, ACol, f, l));
  t := FRich.Document.Text;
  Result := t.GetText(t.ParaStart(f), t.ParaStart(l) + t.ParaLength(l) - t.ParaStart(f));
end;

// the cell's box on the client: from where its text starts (the padding, 7 px, before it)
function TTyRichTableSelTest.CellRect(ARow, ACol: Integer): TRect;
var
  r: TRect;
begin
  r := FRich.PositionRect(CellStart(ARow, ACol), False);
  Result := Rect(r.Left - 7, r.Top - 1, r.Left - 7 + 96, r.Bottom + 1);
end;

procedure TTyRichTableSelTest.CheckRange(const AMsg: string; R0, C0, R1, C1: Integer);
var
  g: TTyRichCellRange;
begin
  g := FRich.SelectedCells;
  AssertTrue(AMsg + ': cells', g.InTable);
  AssertEquals(AMsg + ': row 0', R0, g.Row0);
  AssertEquals(AMsg + ': col 0', C0, g.Col0);
  AssertEquals(AMsg + ': row 1', R1, g.Row1);
  AssertEquals(AMsg + ': col 1', C1, g.Col1);
end;

procedure TTyRichTableSelTest.Sel(AAnchor, ACaret: TTyRichPos);
begin
  FRich.SelStart := AAnchor;
  FRich.SelLength := ACaret - AAnchor;
end;

function TTyRichTableSelTest.RowCount: Integer;
var
  info: TTyRichTableInfo;
begin
  AssertTrue('a table', FRich.Document.TableInfoAt(1, info));
  Result := info.RowCount;
end;

function TTyRichTableSelTest.ColCount: Integer;
var
  info: TTyRichTableInfo;
begin
  AssertTrue('a table', FRich.Document.TableInfoAt(1, info));
  Result := info.CellCount;
end;

function TTyRichTableSelTest.HasTable: Boolean;
var
  k: Integer;
begin
  Result := False;
  for k := 0 to FRich.Document.Text.ParaCount - 1 do
    if FRich.Document.CellAt(k) <> nil then Exit(True);
end;

function TTyRichTableSelTest.BoldAt(APos: TTyRichPos): Boolean;
var
  runs: TTyRunArray;
  d: TTyRichDocument;
begin
  d := FRich.Document;
  runs := d.RunsOf(d.Text.ParaOfPos(APos));
  Result := fsBold in d.Formats.CharFormat(runs[0].Format).Style;
end;

function TTyRichTableSelTest.CentredAt(APos: TTyRichPos): Boolean;
var
  d: TTyRichDocument;
begin
  d := FRich.Document;
  Result := d.Formats.ParaFormat(d.ParaFormatOf(d.Text.ParaOfPos(APos))).Align = paraCenter;
end;

{ ---- the rule ---- }

procedure TTyRichTableSelTest.TestAnchorAndCaretInTwoCellsGiveARectangle;
begin
  MakeTable(4, 4);
  // inside cell 1,1 to inside cell 2,2: rows 1..2, columns 1..2 - either way round
  Sel(CellStart(1, 1) + 1, CellStart(2, 2) + 2);
  CheckRange('down', 1, 1, 2, 2);
  Sel(CellStart(2, 2) + 2, CellStart(1, 1) + 1);
  CheckRange('up', 1, 1, 2, 2);
  // a column the other way: cell 0,3 to cell 3,1
  Sel(CellStart(0, 3), CellStart(3, 1) + 1);
  CheckRange('to the left', 0, 1, 3, 3);
  AssertFalse('not the table', FRich.SelectedCells.WholeTable);
  Sel(CellStart(0, 0), CellEnd(3, 3));
  CheckRange('all', 0, 0, 3, 3);
  AssertTrue('the table', FRich.SelectedCells.WholeTable);
end;

procedure TTyRichTableSelTest.TestTheCellEndMarkDecidesWholeCell;
var
  g: TTyRichCellRange;
begin
  MakeTable(2, 2);
  // to the end mark, inclusive: the cell whole - the caret then stands at the next cell's start
  Sel(CellStart(0, 0), CellEnd(0, 0));
  AssertEquals('the caret at the next cell''s start', CellStart(0, 1), FRich.SelStart + FRich.SelLength);
  CheckRange('one cell whole', 0, 0, 0, 0);
  // short of it: the text in the cell (what Tab into a cell gives)
  Sel(CellStart(0, 0), CellEnd(0, 0) - 1);
  g := FRich.SelectedCells;
  AssertFalse('the text inside', g.InTable);
  // from inside the cell to its end mark: text too (not from its start)
  Sel(CellStart(0, 0) + 1, CellEnd(0, 0));
  AssertFalse('part of it to the end mark', FRich.SelectedCells.InTable);
  // nothing selected
  Sel(CellStart(1, 1), CellStart(1, 1));
  AssertFalse('a caret', FRich.SelectedCells.InTable);
end;

procedure TTyRichTableSelTest.TestOneEndOutsideTakesWholeRows;
begin
  MakeTable(3, 3);
  // from 'before' into cell 1,1: rows 0..1, every cell
  Sel(2, CellStart(1, 1) + 1);
  CheckRange('from before', 0, 0, 1, 2);
  // from cell 1,2 to 'after'
  Sel(CellStart(1, 2) + 1, FRich.Document.Text.Length);
  CheckRange('to after', 1, 0, 2, 2);
  AssertFalse('rows 1..2 are not the table', FRich.SelectedCells.WholeTable);
  Sel(1, FRich.Document.Text.Length - 1);
  AssertFalse('both ends outside: text', FRich.SelectedCells.InTable);
  // whole rows are every cell of them, whatever the span of the cells the ends are in
  Sel(2, CellStart(1, 1) + 1);
  CheckWhole('from before');
  { the selection holds text outside the table too: the keys keep a text selection's rules
    (across cells: refused), they do not clear the cells }
  FRich.Refusals.Clear;
  FRich.Key(VK_DELETE);
  AssertEquals('Delete from before: as a text selection', 1, FRich.Refusals.Count);
  AssertEquals('the cells are not cleared', 'r0c2', CellText(0, 2));
end;

procedure TTyRichTableSelTest.CheckWhole(const AMsg: string);
var
  area: TTyRichCellArea;
  d: TTyRichDocument;
  r, c: Integer;
begin
  d := FRich.Document;
  area := TyRichCellArea(d, FRich.SelStart, FRich.SelStart + FRich.SelLength);
  d.BeginRead;
  try
    for r := 0 to 1 do
      for c := 0 to 2 do
        AssertTrue(Format('%s: cell %d,%d', [AMsg, r, c]), TyRichCellInArea(area,
          d.CellAt(d.Text.ParaOfPos(CellStart(r, c))).Row, c));
  finally
    d.EndRead;
  end;
end;

procedure TTyRichTableSelTest.TestIrregularRowsTakeTheCellsUnderTheSpan;
const
  Rtf = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx1440\cellx2880\cellx4320\pard\intbl a0\cell a1\cell a2\cell\row' +
    '\trowd\cellx2160\cellx4320\pard\intbl b0\cell b1\cell\row' +
    '\trowd\cellx3000\cellx4320\pard\intbl c0\cell c1\cell\row\pard after\par}';
var
  st: TStringStream;
  d: TTyRichDocument;
  area: TTyRichCellArea;

  function InAt(APara, ACell: Integer): Boolean;
  begin
    Result := TyRichCellInArea(area, d.CellAt(APara).Row, ACell);
  end;

begin
  st := TStringStream.Create(Rtf);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  d := FRich.Document;
  // from a1 (1440..2880) to b0 (0..2160): the span 0..2880
  Sel(d.Text.ParaStart(1) + 1, d.Text.ParaStart(3) + 1);
  area := TyRichCellArea(d, FRich.SelStart, FRich.SelStart + FRich.SelLength);
  d.BeginRead;
  try
    AssertTrue('cells', area.Range.InTable);
    AssertTrue('a0', InAt(0, 0));
    AssertTrue('a1', InAt(1, 1));
    AssertFalse('a2 (2880..4320) is not', InAt(2, 2));
    AssertTrue('b0', InAt(3, 0));
    AssertTrue('b1 (2160..4320) overlaps it', InAt(4, 1));
  finally
    d.EndRead;
  end;
  // from a2 (2880..4320) to b1 (2160..4320): a1 (1440..2880) reaches into that span
  Sel(d.Text.ParaStart(2) + 1, d.Text.ParaStart(4) + 1);
  area := TyRichCellArea(d, FRich.SelStart, FRich.SelStart + FRich.SelLength);
  d.BeginRead;
  try
    AssertTrue('a1 overlaps it', InAt(1, 1));
    AssertFalse('a0 does not', InAt(0, 0));
    AssertFalse('b0 (0..2160) ends where it starts', InAt(3, 0));
  finally
    d.EndRead;
  end;
  // a2 to c0: 0..4320, every cell of the three rows
  Sel(d.Text.ParaStart(2), d.Text.ParaStart(5) + 1);
  area := TyRichCellArea(d, FRich.SelStart, FRich.SelStart + FRich.SelLength);
  d.BeginRead;
  try
    AssertTrue('the table', area.Range.WholeTable);
    AssertTrue('b1', InAt(4, 1));
    AssertTrue('c1', InAt(6, 1));
  finally
    d.EndRead;
  end;
end;

procedure TTyRichTableSelTest.TestShiftArrowsGrowTheRectangle;
begin
  MakeTable(3, 3);
  Sel(CellStart(0, 0), CellStart(0, 0));
  // Shift+Right past the cell's end mark: the cell whole, then into the next
  FRich.Key(VK_END, [ssShift]);
  FRich.Key(VK_RIGHT, [ssShift]);
  CheckRange('Shift+End, Shift+Right', 0, 0, 0, 0);
  FRich.Key(VK_RIGHT, [ssShift]);
  CheckRange('one more', 0, 0, 0, 1);
  FRich.Key(VK_DOWN, [ssShift]);
  CheckRange('Shift+Down', 0, 0, 1, 1);
  FRich.Key(VK_DOWN, [ssShift]);
  CheckRange('again', 0, 0, 2, 1);
  // Shift+click in cell 1,2
  FRich.Press(CellRect(1, 2).Left + 20, CellRect(1, 2).Top + 4, [ssShift]);
  FRich.Release(CellRect(1, 2).Left + 20, CellRect(1, 2).Top + 4);
  CheckRange('Shift+click', 0, 0, 1, 2);
  // a drag of text across a cell's edge
  FRich.Press(CellRect(2, 0).Left + 20, CellRect(2, 0).Top + 4);
  FRich.MoveTo(CellRect(2, 1).Left + 20, CellRect(2, 1).Top + 4);
  FRich.Release(CellRect(2, 1).Left + 20, CellRect(2, 1).Top + 4);
  CheckRange('a drag', 2, 0, 2, 1);
end;

procedure TTyRichTableSelTest.TestTheSelectMethods;
var
  p: TTyRichPos;
  r, c: Integer;
begin
  MakeTable(3, 3);
  Sel(CellStart(1, 2) + 1, CellStart(1, 2) + 1);
  AssertTrue('the caret''s cell', FRich.CaretCell(p, r, c));
  AssertEquals('row', 1, r);
  AssertEquals('col', 2, c);
  AssertTrue('a cell', FRich.SelectCell);
  CheckRange('SelectCell', 1, 2, 1, 2);
  AssertTrue('a row', FRich.SelectRow);
  CheckRange('SelectRow', 1, 0, 1, 2);
  Sel(CellStart(1, 2), CellStart(1, 2));
  AssertTrue('a column', FRich.SelectColumn);
  CheckRange('SelectColumn', 0, 2, 2, 2);
  AssertTrue('the table', FRich.SelectTable);
  CheckRange('SelectTable', 0, 0, 2, 2);
  AssertTrue('whole', FRich.SelectedCells.WholeTable);
  Sel(1, 1);
  AssertFalse('outside a table', FRich.SelectCell);
  AssertFalse('outside a table: no cell', FRich.CaretCell(p, r, c));
end;

procedure TTyRichTableSelTest.TestMouseZones;
var
  a, b: TRect;
  hp: TPoint;
  x, y: Integer;
begin
  MakeTable(3, 3);
  FRich.UpdateView;
  a := CellRect(1, 1);
  // just inside the cell's left edge: the cell; dragged to the next one: both
  // (past the band of the cell's edge, which resizes the column)
  AssertEquals('the cell''s edge', crSizeWE, FRich.CursorAtPoint(a.Left + 1, a.Top + 5));
  AssertEquals('the cell''s zone', crArrow, FRich.CursorAtPoint(a.Left + 4, a.Top + 5));
  AssertEquals('the text beside it', crIBeam, FRich.CursorAtPoint(a.Left + 12, a.Top + 5));
  FRich.Press(a.Left + 4, a.Top + 5);
  FRich.Release(a.Left + 4, a.Top + 5);
  CheckRange('a click in the cell''s zone', 1, 1, 1, 1);
  b := CellRect(2, 2);
  FRich.Press(a.Left + 4, a.Top + 5);
  FRich.MoveTo(b.Left + 30, b.Top + 5);
  FRich.Release(b.Left + 30, b.Top + 5);
  CheckRange('a drag from it', 1, 1, 2, 2);
  // the table's left margin: the row; dragged up: two rows
  a := CellRect(1, 0);
  FRich.Press(a.Left - 3, a.Top + 5);
  FRich.Release(a.Left - 3, a.Top + 5);
  CheckRange('a click left of the row', 1, 0, 1, 2);
  FRich.Press(a.Left - 3, a.Top + 5);
  FRich.MoveTo(a.Left + 30, CellRect(0, 0).Top + 5);
  FRich.Release(a.Left + 30, CellRect(0, 0).Top + 5);
  CheckRange('a drag of rows', 0, 0, 1, 2);
  // just above a column: the column; dragged right: two columns
  a := CellRect(0, 1);
  AssertEquals('the column''s zone', crUpArrow, FRich.CursorAtPoint(a.Left + 30, a.Top - 2));
  FRich.Press(a.Left + 30, a.Top - 2);
  FRich.Release(a.Left + 30, a.Top - 2);
  CheckRange('a click above the column', 0, 1, 2, 1);
  FRich.Press(a.Left + 30, a.Top - 2);
  FRich.MoveTo(CellRect(2, 2).Left + 30, CellRect(2, 2).Top + 5);
  FRich.Release(CellRect(2, 2).Left + 30, CellRect(2, 2).Top + 5);
  CheckRange('a drag of columns', 0, 1, 2, 2);
  // the handle: shown while the pointer is over the table, a click on it the whole table
  a := CellRect(0, 0);
  FRich.MoveTo(a.Left + 30, a.Top + 5, []);
  { the handle: above the table's top-left corner, left of it where there is room (here the
    table starts at the text's left edge: it stands at that edge) }
  hp := Point(-1, -1);
  for y := a.Top - 1 downto a.Top - 20 do
    for x := 0 to a.Left + 12 do
      if (hp.X < 0) and (FRich.CursorAtPoint(x, y) = crSizeAll) then hp := Point(x, y);
  AssertTrue('the handle', hp.X >= 0);
  AssertTrue('above the table', hp.Y < a.Top);
  FRich.Press(hp.X, hp.Y);
  FRich.Release(hp.X, hp.Y);
  CheckRange('the handle''s click', 0, 0, 2, 2);
  AssertTrue('the whole table', FRich.SelectedCells.WholeTable);
  // away from the table: no handle
  FRich.MoveTo(300, 380, []);
  AssertTrue('no handle there', FRich.CursorAtPoint(hp.X, hp.Y) <> crSizeAll);
end;

{ The handle stands on the table's top-left corner: shown, the letters of the line above
  (one that starts with a wide W, at the text's left edge) keep every pixel above their
  descenders, at 100 % and 150 %; and a press on it selects the table. }
procedure TTyRichTableSelTest.TestTheHandleCoversNoLetter;
var
  keep: TSelRich;
  z, x, y, ppi, top, cut, ink: Integer;
  g: TBGRAPixel;
  b0, b1: TBGRABitmap;
  a, ln, hr: TRect;
  d: TTyRichDocument;
  f, l: Integer;
  p0, p1: TBGRAPixel;
  hp: TPoint;
begin
  // with the system's fonts: the test device's letters fill their line, descenders or not
  keep := FRich;
  TSelRich.RealFonts := True;
  try
    FRich := TSelRich.Create(nil);
  finally
    TSelRich.RealFonts := False;
  end;
  FRich.Refusals := TStringList.Create;
  FRich.Controller := FCtl;
  try
  for z := 0 to 1 do
  begin
    if z = 0 then ppi := 96 else ppi := 144;
    FRich.Font.PixelsPerInch := ppi;
    FRich.SetBounds(0, 0, 600 * ppi div 96, 300 * ppi div 96);
    MakeTable(2, 2);
    d := FRich.Document;
    FRich.Lines[0] := 'Wide letters stand here: Wg';
    FRich.UpdateView;
    d.TableCellParas(1, 0, 0, f, l);
    a := FRich.PositionRect(d.Text.ParaStart(f), False);
    ln := FRich.PositionRect(0, False);
    b0 := TBGRABitmap.Create(FRich.Width, FRich.Height, BGRA(255, 0, 255));
    b1 := TBGRABitmap.Create(FRich.Width, FRich.Height, BGRA(255, 0, 255));
    try
      FRich.MoveTo(a.Left + 10, a.Top + 2, []);
      // the handle: found by its cursor near the corner
      hp := Point(-1, -1);
      for y := ln.Top to a.Bottom do
        for x := 0 to a.Left do
          if (hp.X < 0) and (FRich.CursorAtPoint(x, y) = crSizeAll) then hp := Point(x, y);
      AssertTrue(Format('%d: a handle', [ppi]), hp.X >= 0);
      FRich.PaintInto(b1);
      FRich.MoveTo(FRich.Width - 20, FRich.Height - 20, []);
      FRich.PaintInto(b0);
      // somewhere it is drawn
      hr := Rect(0, ln.Top, a.Left + 20, a.Bottom);
      top := 0;
      for y := hr.Top to hr.Bottom - 1 do
        for x := hr.Left to hr.Right - 1 do
        begin
          p0 := b0.GetPixel(x, y);
          p1 := b1.GetPixel(x, y);
          if (p0.red <> p1.red) or (p0.green <> p1.green) or (p0.blue <> p1.blue) then Inc(top);
        end;
      AssertTrue(Format('%d: the handle is drawn', [ppi]), top > 0);
      { the line above: every pixel of its letters down to the baseline (the W's lowest ink)
        as it was }
      g := b0.GetPixel(FRich.Width - 30, ln.Top + 2);
      cut := ln.Top;
      for y := ln.Top to ln.Bottom - 1 do
        for x := ln.Left to ln.Left + (ln.Bottom - ln.Top) do
        begin
          p0 := b0.GetPixel(x, y);
          if (p0.red <> g.red) or (p0.green <> g.green) or (p0.blue <> g.blue) then cut := y + 1;
        end;
      AssertTrue(Format('%d: the W found', [ppi]), cut > ln.Top + 2);
      ink := 0;
      for y := ln.Top to cut - 1 do
        for x := 0 to FRich.Width - 1 do
        begin
          p0 := b0.GetPixel(x, y);
          if (p0.red = g.red) and (p0.green = g.green) and (p0.blue = g.blue) then Continue;
          Inc(ink);
          p1 := b1.GetPixel(x, y);
          AssertTrue(Format('%d: a letter''s pixel at %d,%d', [ppi, x, y]), (p0.red = p1.red) and
            (p0.green = p1.green) and (p0.blue = p1.blue));
        end;
      AssertTrue(Format('%d: letters', [ppi]), ink > 50);
    finally
      b0.Free;
      b1.Free;
    end;
    FRich.MoveTo(a.Left + 10, a.Top + 2, []);
    FRich.Press(hp.X, hp.Y);
    FRich.Release(hp.X, hp.Y);
    AssertTrue(Format('%d: the table', [ppi]), FRich.SelectedCells.WholeTable);
  end;
  finally
    FRich.Free;
    FRich := keep;
  end;
end;

{ ---- what selected cells take ---- }

procedure TTyRichTableSelTest.TestDeleteClearsBackspaceRemovesRows;
var
  info: TTyRichTableInfo;
begin
  MakeTable(3, 3);
  Sel(CellStart(0, 1), CellStart(1, 2) + 1);
  FRich.Key(VK_DELETE);
  AssertEquals('cleared', '', CellText(0, 1));
  AssertEquals('cleared too', '', CellText(1, 2));
  AssertEquals('outside the rectangle', 'r0c0', CellText(0, 0));
  AssertEquals('below it', 'r2c1', CellText(2, 1));
  AssertTrue('the cells stay', FRich.Document.TableInfoAt(1, info) and (info.RowCount = 3));
  FRich.Undo;
  AssertEquals('one step back', 'r0c1', CellText(0, 1));
  AssertEquals('one step back, all of it', 'r1c2', CellText(1, 2));
  // Backspace on some cells of a row: as Delete
  Sel(CellStart(0, 1), CellEnd(0, 1));
  FRich.Key(VK_BACK);
  AssertEquals('Backspace on a cell clears it', '', CellText(0, 1));
  FRich.Undo;
  // whole rows: they go
  Sel(CellStart(1, 0), CellEnd(1, 2));
  FRich.Key(VK_BACK);
  AssertTrue('a row less', FRich.Document.TableInfoAt(1, info) and (info.RowCount = 2));
  AssertEquals('the next row came up', 'r2c0', CellText(1, 0));
  FRich.Undo;
  // two whole rows, from a cell of the first to a cell of the second
  Sel(CellStart(0, 0), CellEnd(1, 2));
  FRich.Key(VK_BACK);
  AssertTrue('two rows less', FRich.Document.TableInfoAt(1, info) and (info.RowCount = 1));
  AssertEquals('the last row is left', 'r2c0', CellText(0, 0));
  FRich.Undo;
  AssertTrue('undone: three rows', FRich.Document.TableInfoAt(1, info) and (info.RowCount = 3));
  // the whole table
  Sel(CellStart(0, 0), CellEnd(2, 2));
  FRich.Key(VK_BACK);
  AssertFalse('no table', FRich.Document.TableInfoAt(1, info) and (FRich.Document.CellAt(1) <> nil));
end;

procedure TTyRichTableSelTest.TestTypingReplacesTheFirstCell;
begin
  MakeTable(3, 3);
  Sel(CellStart(1, 1), CellStart(2, 2) + 1);
  FRich.Typed('x');
  AssertEquals('the first cell has it', 'x', CellText(1, 1));
  AssertEquals('the others are left', 'r1c2', CellText(1, 2));
  AssertEquals('the others are left, below', 'r2c2', CellText(2, 2));
  AssertEquals('the caret after it', CellStart(1, 1) + 1, FRich.SelStart);
end;

procedure TTyRichTableSelTest.TestFormatsReachEveryCell;
var
  r, c: Integer;
  inside: Boolean;
begin
  MakeTable(3, 3);
  // cells 0,1 .. 1,2: the rectangle - not the text between in reading order (cell 1,0)
  Sel(CellStart(0, 1), CellStart(1, 2) + 1);
  FRich.SelAttributes.Bold := True;
  FRich.Paragraph.Alignment := taCenter;
  for r := 0 to 2 do
    for c := 0 to 2 do
    begin
      inside := (r <= 1) and (c >= 1);
      AssertEquals(Format('cell %d,%d: bold', [r, c]), inside, BoldAt(CellStart(r, c)));
      AssertEquals(Format('cell %d,%d: centred', [r, c]), inside, CentredAt(CellStart(r, c)));
    end;
  FRich.Undo;
  FRich.Undo;
  AssertFalse('undone', BoldAt(CellStart(1, 2)));
end;

procedure TTyRichTableSelTest.TestCopyIsASmallTableAndTabbedText;
var
  d: TTyRichDocument;
  s: TBytesStream;
  info: TTyRichTableInfo;
  k: Integer;
begin
  MakeTable(3, 3);
  Sel(CellStart(0, 1), CellStart(1, 2) + 1);
  FRich.CopyToClipboard;
  AssertEquals('tabbed text', 'r0c1' + #9 + 'r0c2' + LineEnding + 'r1c1' + #9 + 'r1c2', FRich.ClipText);
  d := TTyRichDocument.Create;
  try
    s := TBytesStream.Create;
    try
      s.WriteBuffer(FRich.ClipRtf[1], Length(FRich.ClipRtf));
      s.Position := 0;
      TyRichLoadRtfFull(d, s);
    finally
      s.Free;
    end;
    k := 0;
    while (k < d.Text.ParaCount) and (d.CellAt(k) = nil) do Inc(k);
    AssertTrue('a table', d.TableInfoAt(k, info));
    AssertEquals('2 rows', 2, info.RowCount);
    AssertEquals('2 cells', 2, info.CellCount);
    AssertEquals('its first cell', 'r0c1', d.Text.GetText(d.Text.ParaStart(k), d.Text.ParaLength(k)));
    AssertEquals('its last cell', 'r1c2', d.Text.GetText(d.Text.ParaStart(info.Last),
      d.Text.ParaLength(info.Last)));
  finally
    d.Free;
  end;
  // text in a cell: text
  Sel(CellStart(2, 2), CellStart(2, 2) + 3);
  FRich.CopyToClipboard;
  AssertEquals('a cell''s text', 'r2c', FRich.ClipText);
end;

procedure TTyRichTableSelTest.TestPasteFillsCellByCell;
const
  WordTable = '{\rtf1\ansi{\fonttbl{\f0 Calibri;}}\trowd\cellx1000\cellx2000\pard\intbl A1\cell A2\cell\row' +
    '\trowd\cellx1000\cellx2000\pard\intbl B1\cell B2\cell\row\pard\par}';
var
  info: TTyRichTableInfo;
  offer: TCellOffer;
  p: TRect;
begin
  MakeTable(2, 3);
  // ours: copy two cells, paste at cell 1,0 - one row more is added
  Sel(CellStart(0, 1), CellStart(1, 2) + 1);
  FRich.CopyToClipboard;
  Sel(CellStart(1, 0), CellStart(1, 0));
  FRich.PasteFromClipboard;
  AssertEquals('ours: 1,0', 'r0c1', CellText(1, 0));
  AssertEquals('ours: 1,1', 'r0c2', CellText(1, 1));
  AssertEquals('ours: 2,0 (a row added)', 'r1c1', CellText(2, 0));
  AssertEquals('ours: 2,1', 'r1c2', CellText(2, 1));
  AssertEquals('ours: the rest of the row stays', 'r1c2', CellText(1, 2));
  AssertTrue('three rows', FRich.Document.TableInfoAt(1, info) and (info.RowCount = 3));
  FRich.Undo;
  AssertTrue('undone: two rows', FRich.Document.TableInfoAt(1, info) and (info.RowCount = 2));
  AssertEquals('undone: the cell', 'r1c0', CellText(1, 0));
  // Word's: RTF only
  FRich.ClipRtf := WordTable;
  FRich.ClipText := '';
  Sel(CellStart(0, 0), CellStart(0, 0));
  FRich.PasteFromClipboard;
  AssertEquals('Word''s: 0,0', 'A1', CellText(0, 0));
  AssertEquals('Word''s: 1,1', 'B2', CellText(1, 1));
  AssertEquals('Word''s: beside it', 'r0c2', CellText(0, 2));
  // a spreadsheet's text, wider than the table from where it goes: told once, the rest left out
  FRich.ClipRtf := '';
  FRich.ClipText := 'x1' + #9 + 'x2' + #9 + 'x3' + #13#10 + 'y1' + #9 + 'y2' + #9 + 'y3' + #13#10;
  FRich.Refusals.Clear;
  Sel(CellStart(0, 1), CellStart(0, 1));
  FRich.PasteFromClipboard;
  AssertEquals('text: 0,1', 'x1', CellText(0, 1));
  AssertEquals('text: 1,2', 'y2', CellText(1, 2));
  AssertEquals('told once', 1, FRich.Refusals.Count);
  // text with no tab: as today (into the caret's cell)
  FRich.ClipText := 'plain';
  Sel(CellStart(0, 0), CellStart(0, 0));
  FRich.PasteFromClipboard;
  AssertEquals('plain text: as before', 'plainA1', CellText(0, 0));
  FRich.Undo;
  // another's text dropped on a cell: as its paste
  offer := TCellOffer.Create;
  try
    offer.Text := 'd1' + #9 + 'd2';
    FRich.UpdateView;
    p := CellRect(1, 0);
    FRich.DropEnter(offer, p.Left + 20, p.Top + 4, []);
    FRich.DropOn(p.Left + 20, p.Top + 4, []);
  finally
    offer.Free;
  end;
  AssertEquals('dropped: 1,0', 'd1', CellText(1, 0));
  AssertEquals('dropped: 1,1', 'd2', CellText(1, 1));
end;

{ A bookmark from one cell to another: cells cleared, or rows deleted, that take one of its
  marks leave no lone mark - the bookmark goes whole or stays whole. }
procedure TTyRichTableSelTest.TestNoMarkOfAPairIsLeftAlone;
var
  B: TTyRichBuilder;
  s0, e0: TTyRichPos;
  t: TTyRichText;
  LastCount: string;

  procedure Build;
  begin
    B := TTyRichBuilder.Create;
    try
      B.Text('before').Paragraph;
      B.Table([1440, 1440]).Cell.Text('a').BookmarkStart('bm').Text('b').Cell.Text('c');
      B.Row.Cell.Text('d').Cell.Text('e').BookmarkEnd('bm').Text('f').EndTable;
      B.Text('after');
      FRich.SetContent(B);
    finally
      B.Free;
    end;
    FRich.Document.ClearUndo;
  end;

  // the bookmark marks in the text: as many starts as ends
  function Lone: Boolean;
  var
    k, st, en: Integer;
    runs: TTyRunArray;
    j: Integer;
  begin
    st := 0;
    en := 0;
    t := FRich.Document.Text;
    for k := 0 to t.ParaCount - 1 do
    begin
      runs := FRich.Document.RunsOf(k);
      for j := 0 to High(runs) do
        if runs[j].Obj is TTyRichBookmarkMark then
          if TTyRichBookmarkMark(runs[j].Obj).Kind = rbmStart then Inc(st) else Inc(en);
    end;
    Result := st <> en;
    LastCount := Format('%d starts, %d ends', [st, en]);
  end;

begin
  Build;
  AssertTrue('the bookmark', FRich.FindBookmark('bm', s0, e0));
  AssertFalse('no lone mark to begin with', Lone);
  // the first cell alone, cleared: it holds the start
  Sel(CellStart(0, 0), CellEnd(0, 0));
  FRich.Key(VK_DELETE);
  AssertFalse('a cell cleared: no lone mark ' + LastCount, Lone);
  FRich.Undo;
  AssertTrue('back', FRich.FindBookmark('bm', s0, e0));
  // the first row deleted (it holds the start)
  Sel(CellStart(0, 0), CellEnd(0, 1));
  FRich.Key(VK_BACK);
  AssertFalse('a row deleted: no lone mark', Lone);
  FRich.Undo;
  // both cells cleared
  Sel(CellStart(0, 0), CellEnd(1, 1));
  FRich.Key(VK_DELETE);
  AssertFalse('all of it cleared: no lone mark', Lone);
end;

{ Bookmark marks at a cell's start or end - zero-width - decide nothing about whether a cell
  is covered: a selection that covers all of a cell's text and its end mark covers the cell,
  wherever among the marks at its start it begins (a place set at a bookmark's start rests
  after its opening mark). Row 0's first cell begins with a bookmark's start and ends with its
  end; row 1's last cell likewise; in row 2 a bookmark starts at the end of cell 0 and ends at
  the start of cell 1. The select methods, a selection by positions and Shift+arrows select
  what they say; deleting, cutting and the cell formats work; no lone mark is left. }
procedure TTyRichTableSelTest.TestMarksAtACellsEdgesDecideNothing;
var
  B: TTyRichBuilder;
  info: TTyRichTableInfo;
  counts: string;
  s0, e0: TTyRichPos;

  procedure Build;
  begin
    B := TTyRichBuilder.Create;
    try
      B.Text('before').Paragraph;
      B.Table([1440, 1440, 1440]);
      B.Cell.BookmarkStart('a').Text('r0c0').BookmarkEnd('a').Cell.Text('r0c1').Cell.Text('r0c2');
      B.Row.Cell.Text('r1c0').Cell.Text('r1c1').Cell.BookmarkStart('b').Text('r1c2').BookmarkEnd('b');
      B.Row.Cell.Text('r2c0').BookmarkStart('c').Cell.BookmarkEnd('c').Text('r2c1').Cell.Text('r2c2');
      B.EndTable;
      B.Text('after');
      FRich.SetContent(B);
    finally
      B.Free;
    end;
    FRich.Document.ClearUndo;
    FRich.UpdateView;
  end;

  // as many bookmark starts as ends
  function NoLone: Boolean;
  var
    k, j, st, en: Integer;
    runs: TTyRunArray;
    t: TTyRichText;
  begin
    st := 0;
    en := 0;
    t := FRich.Document.Text;
    for k := 0 to t.ParaCount - 1 do
    begin
      runs := FRich.Document.RunsOf(k);
      for j := 0 to High(runs) do
        if runs[j].Obj is TTyRichBookmarkMark then
          if TTyRichBookmarkMark(runs[j].Obj).Kind = rbmStart then Inc(st) else Inc(en);
    end;
    counts := Format('%d starts, %d ends', [st, en]);
    Result := st = en;
  end;

  function Rows: Integer;
  begin
    AssertTrue('a table', FRich.Document.TableInfoAt(1, info));
    Result := info.RowCount;
  end;

  // a selection by positions, as code sets one: the length from where the start rests
  procedure SelTo(AAnchor, ACaret: TTyRichPos);
  begin
    FRich.SelStart := AAnchor;
    FRich.SelLength := ACaret - FRich.SelStart;
  end;

  procedure Caret(ARow, ACol: Integer);
  begin
    SelTo(CellStart(ARow, ACol) + 2, CellStart(ARow, ACol) + 2);
  end;

begin
  Build;
  // the select methods
  Caret(0, 0);
  AssertTrue('a cell', FRich.SelectCell);
  CheckRange('SelectCell, a bookmark at its start and end', 0, 0, 0, 0);
  AssertTrue('a row', FRich.SelectRow);
  CheckRange('SelectRow', 0, 0, 0, 2);
  Caret(0, 0);
  AssertTrue('a column', FRich.SelectColumn);
  CheckRange('SelectColumn', 0, 0, 2, 0);
  AssertTrue('the table', FRich.SelectTable);
  CheckRange('SelectTable', 0, 0, 2, 2);
  Caret(1, 2);
  AssertTrue('the last cell', FRich.SelectCell);
  CheckRange('SelectCell, the row''s last', 1, 2, 1, 2);
  Caret(2, 1);
  AssertTrue('a cell beginning with an end mark', FRich.SelectCell);
  CheckRange('SelectCell after a bookmark''s end', 2, 1, 2, 1);
  Caret(2, 0);
  AssertTrue('a cell ending with a start mark', FRich.SelectCell);
  CheckRange('SelectCell before a bookmark''s start', 2, 0, 2, 0);
  // by positions: from before or after the marks at the start, to the end mark
  SelTo(CellStart(0, 0), CellEnd(0, 0));
  CheckRange('positions: from the cell''s start', 0, 0, 0, 0);
  SelTo(CellStart(0, 0) + 1, CellEnd(0, 0));
  CheckRange('positions: from after the opening mark', 0, 0, 0, 0);
  SelTo(CellEnd(0, 0), CellStart(0, 0) + 1);
  CheckRange('positions: backwards', 0, 0, 0, 0);
  SelTo(CellStart(2, 1) + 1, CellEnd(2, 1));
  CheckRange('positions: after a closing mark', 2, 1, 2, 1);
  SelTo(CellStart(0, 0) + 2, CellEnd(0, 0));
  AssertFalse('positions: from inside its text - text', FRich.SelectedCells.InTable);
  // Shift+arrows from the cell's start
  SelTo(CellStart(0, 0), CellStart(0, 0));
  FRich.Key(VK_END, [ssShift]);
  FRich.Key(VK_RIGHT, [ssShift]);
  CheckRange('Shift+End, Shift+Right', 0, 0, 0, 0);
  FRich.Key(VK_RIGHT, [ssShift]);
  CheckRange('one more', 0, 0, 0, 1);
  FRich.Key(VK_DOWN, [ssShift]);
  CheckRange('Shift+Down', 0, 0, 1, 1);
  SelTo(CellStart(1, 2), CellStart(1, 2));
  FRich.Key(VK_END, [ssShift]);
  FRich.Key(VK_RIGHT, [ssShift]);
  CheckRange('the last cell, a bookmark''s end before its end mark', 1, 2, 1, 2);
  // a bookmark from the end of cell 2,0 to the start of cell 2,1
  SelTo(CellStart(2, 0), CellStart(2, 0));
  FRich.Key(VK_END, [ssShift]);
  FRich.Key(VK_RIGHT, [ssShift]);
  CheckRange('Shift: the cell ending with a bookmark''s start', 2, 0, 2, 0);
  FRich.Key(VK_RIGHT, [ssShift]);
  CheckRange('Shift: into the cell beginning with its end', 2, 0, 2, 1);
  // row 0 cut, selected by positions from its start
  SelTo(CellStart(0, 0), CellEnd(0, 2));
  FRich.CutToClipboard;
  AssertEquals('row 0 cut', 2, Rows);
  AssertTrue('no lone mark (row 0 cut): ' + counts, NoLone);
  FRich.Undo;
  AssertEquals('row 0 back', 3, Rows);
  // a row deleted by a selection from the row's start, Backspace
  SelTo(CellStart(0, 0), CellEnd(0, 2));
  CheckRange('row 0 by positions', 0, 0, 0, 2);
  FRich.Key(VK_BACK);
  AssertEquals('row 0 deleted', 2, Rows);
  AssertTrue('no lone mark: ' + counts, NoLone);
  FRich.Undo;
  AssertEquals('back', 3, Rows);
  // SelectRow then Backspace, on the row whose last cell ends with one
  Caret(1, 2);
  AssertTrue('row 1', FRich.SelectRow);
  FRich.Key(VK_BACK);
  AssertEquals('row 1 deleted', 2, Rows);
  AssertTrue('no lone mark (row 1): ' + counts, NoLone);
  FRich.Undo;
  // row 2 cut: the bookmark across its cells goes with it whole
  Caret(2, 1);
  AssertTrue('row 2', FRich.SelectRow);
  FRich.CutToClipboard;
  AssertEquals('row 2 cut', 2, Rows);
  AssertTrue('no lone mark (row 2): ' + counts, NoLone);
  FRich.Undo;
  AssertEquals('back again', 3, Rows);
  // cells cleared: the bookmark stays whole
  Caret(2, 1);
  AssertTrue('cell 2,1', FRich.SelectCell);
  FRich.Key(VK_DELETE);
  // (its text gone; the bookmark's closing mark stays, the bookmark whole)
  AssertEquals('cleared', 0, Pos('r2c1', CellText(2, 1)));
  AssertTrue('the bookmark kept', FRich.FindBookmark('c', s0, e0));
  AssertTrue('no lone mark (a cell cleared): ' + counts, NoLone);
  FRich.Undo;
  Caret(0, 0);
  FRich.SelectCell;
  FRich.Key(VK_DELETE);
  AssertTrue('no lone mark (the first cell cleared): ' + counts, NoLone);
  FRich.Undo;
  // the cell-format doors
  Caret(0, 0);
  AssertTrue('a row', FRich.SelectRow);
  AssertTrue('shading on the row', FRich.SetCellShading(clYellow));
  AssertEquals('every cell of it', clYellow, FRich.Document.CellProps(CellStart(0, 0), 0, 2).Shading);
  AssertTrue('borders on the row', FRich.SetCellBorders(rbpAll, TyRichBorder(rbsDouble, 30, clRed)));
  Caret(2, 1);
  AssertTrue('cell 2,1', FRich.SelectCell);
  AssertTrue('shading on it', FRich.SetCellShading(clAqua));
  AssertEquals('that cell', clAqua, FRich.Document.CellProps(CellStart(0, 0), 2, 1).Shading);
  AssertEquals('not the one before', clNone, FRich.Document.CellProps(CellStart(0, 0), 2, 0).Shading);
  AssertTrue('no lone mark at the end: ' + counts, NoLone);
end;


{ ---- the doors on what is selected ---- }

{ Delete Column takes the selected cells' columns, counted by the grid: a column, a rectangle
  of several rows, the last column, every column (the table); rows of different cells refuse
  it, told once. Insert Column on a selected column puts one beside it. }
procedure TTyRichTableSelTest.TestDeleteColumnTakesTheSelectedColumns;
const
  Rtf = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard before\par' +
    '\trowd\cellx1440\cellx2880\cellx4320\pard\intbl a0\cell a1\cell a2\cell\row' +
    '\trowd\cellx2160\cellx4320\pard\intbl b0\cell b1\cell\row\pard after\par}';
var
  st: TStringStream;
begin
  MakeTable(4, 4);
  Sel(CellStart(0, 1) + 1, CellStart(0, 1) + 1);
  AssertTrue('a column', FRich.SelectColumn);
  AssertTrue('deleted', FRich.DeleteColumn);
  AssertTrue('the table stays', HasTable);
  AssertEquals('three columns', 3, ColCount);
  AssertEquals('four rows', 4, RowCount);
  AssertEquals('the next column came left', 'r0c2', CellText(0, 1));
  AssertEquals('the next column came left, below', 'r3c2', CellText(3, 1));
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  FRich.Undo;
  // a 2 x 2 rectangle
  Sel(CellStart(1, 1), CellStart(2, 2) + 1);
  CheckRange('the rectangle', 1, 1, 2, 2);
  AssertTrue('deleted', FRich.DeleteColumn);
  AssertEquals('two columns', 2, ColCount);
  AssertEquals('the first stays', 'r0c0', CellText(0, 0));
  AssertEquals('the last came left', 'r0c3', CellText(0, 1));
  FRich.Undo;
  // the last column (the selection ends after the table's last cell)
  Sel(CellStart(1, 3) + 1, CellStart(1, 3) + 1);
  AssertTrue('the last column', FRich.SelectColumn);
  AssertTrue('the last column: may', FRich.CanDeleteColumn);
  AssertTrue('the last column deleted', FRich.DeleteColumn);
  AssertEquals('three columns left', 3, ColCount);
  AssertEquals('its neighbour stays', 'r0c2', CellText(0, 2));
  FRich.Undo;
  // every column, two rows: the table
  Sel(CellStart(1, 0) + 1, CellStart(2, 3) + 1);
  CheckRange('every column', 1, 0, 2, 3);
  AssertTrue('every column deleted', FRich.DeleteColumn);
  AssertFalse('the table went', HasTable);
  FRich.Undo;
  // Insert Column on a selected column: one, right of it
  Sel(CellStart(0, 1) + 1, CellStart(0, 1) + 1);
  AssertTrue('a column', FRich.SelectColumn);
  AssertTrue('inserted', FRich.InsertColumn(True));
  AssertEquals('five columns', 5, ColCount);
  AssertEquals('the new one empty', '', CellText(0, 2));
  AssertEquals('the next moved right', 'r0c2', CellText(0, 3));
  // rows of different cells: refused, told once, the table as it was
  st := TStringStream.Create(Rtf);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  Sel(FRich.Document.Text.ParaStart(2) + 1, FRich.Document.Text.ParaStart(4) + 1);
  AssertTrue('cells', FRich.SelectedCells.InTable);
  FRich.Refusals.Clear;
  AssertFalse('refused', FRich.DeleteColumn);
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertTrue('the table as it was', HasTable and (FRich.Document.Text.ParaCount = 7));
end;

{ Every insert and delete of rows, columns and the table, with its Can... answer, on every kind
  of cell selection - a caret, a rectangle, one ending at the table's last cell, whole rows, a
  whole column, the whole table, rows reached from before and from after the table: the
  answer is yes and the door does it. }
procedure TTyRichTableSelTest.TestEveryDoorAgreesWithItsCan;
const
  Doors: array[0..6] of string = ('InsertRow below', 'InsertRow above', 'InsertColumn right',
    'InsertColumn left', 'DeleteRow', 'DeleteColumn', 'DeleteTable');
  Kinds: array[0..7] of string = ('a caret', 'a rectangle', 'to the last cell', 'whole rows',
    'the last column', 'the table', 'from before', 'to after');
var
  dk, sk: Integer;
  can, done: Boolean;
  what: string;
begin
  for sk := 0 to High(Kinds) do
    for dk := 0 to High(Doors) do
    begin
      MakeTable(4, 4);
      case sk of
        0: Sel(CellStart(1, 1) + 1, CellStart(1, 1) + 1);
        1: Sel(CellStart(1, 1), CellStart(2, 2) + 1);
        2: Sel(CellStart(2, 2), CellEnd(3, 3));
        3: Sel(CellStart(1, 0), CellEnd(2, 3));
        4:
          begin
            Sel(CellStart(1, 3) + 1, CellStart(1, 3) + 1);
            FRich.SelectColumn;
          end;
        5: FRich.SelectTable;
        6: Sel(2, CellStart(1, 1) + 1);
      else
        Sel(CellStart(2, 1) + 1, FRich.Document.Text.Length);
      end;
      if sk = 5 then
      begin
        Sel(CellStart(0, 0) + 1, CellStart(0, 0) + 1);
        FRich.SelectTable;
      end;
      what := Doors[dk] + ', ' + Kinds[sk];
      AssertTrue(what + ': cells', (sk = 0) or FRich.SelectedCells.InTable);
      case dk of
        0, 1: can := FRich.CanInsertRow;
        2, 3: can := FRich.CanInsertColumn;
        4: can := FRich.CanDeleteRow;
        5: can := FRich.CanDeleteColumn;
      else
        can := FRich.CanDeleteTable;
      end;
      FRich.Refusals.Clear;
      case dk of
        0: done := FRich.InsertRow(True);
        1: done := FRich.InsertRow(False);
        2: done := FRich.InsertColumn(True);
        3: done := FRich.InsertColumn(False);
        4: done := FRich.DeleteRow;
        5: done := FRich.DeleteColumn;
      else
        done := FRich.DeleteTable;
      end;
      AssertTrue(what + ': may', can);
      AssertTrue(what + ': done (' + FRich.Refusals.Text + ')', done);
      AssertEquals(what + ': nothing told', 0, FRich.Refusals.Count);
    end;
end;

{ A selection with one end outside the table shows whole rows: the format and resize doors
  take those rows, every cell of them, and say so in their Can... answers; typing, Backspace,
  Delete and Cut stay refused, told once. }
procedure TTyRichTableSelTest.TestRowsReachedFromOutsideAreWhatTheDoorsTake;
var
  r, c: Integer;
  before: string;
  e0: TTyRichEdges;

  function Shaded(ARow, ACol: Integer): Boolean;
  begin
    Result := FRich.Document.CellProps(CellStart(0, 0), ARow, ACol).Shading = clYellow;
  end;

  function EdgeOf(ARow: Integer): Integer;
  begin
    FRich.Document.BeginRead;
    try
      e0 := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(CellStart(ARow, 0))).Row.CellEdges;
      // the second column's width (the caret's cell's)
      Result := e0[1] - e0[0];
    finally
      FRich.Document.EndRead;
    end;
  end;

begin
  MakeTable(4, 4);
  // from before the table into cell 1,1: rows 0 and 1
  Sel(2, CellStart(1, 1) + 1);
  AssertTrue('may format', FRich.CanFormatCells);
  AssertTrue('shaded', FRich.SetCellShading(clYellow));
  for r := 0 to 3 do
    for c := 0 to 3 do
      AssertEquals(Format('from before: %d,%d', [r, c]), r <= 1, Shaded(r, c));
  FRich.Undo;
  // from cell 2,1 to after the table: rows 2 and 3
  Sel(CellStart(2, 1) + 1, FRich.Document.Text.Length);
  AssertTrue('may format, to after', FRich.CanFormatCells);
  AssertTrue('shaded, to after', FRich.SetCellShading(clYellow));
  for r := 0 to 3 do
    for c := 0 to 3 do
      AssertEquals(Format('to after: %d,%d', [r, c]), r >= 2, Shaded(r, c));
  FRich.Undo;
  // a column's width: the rows it covers
  e0 := nil;
  Sel(2, CellStart(1, 1) + 1);
  AssertTrue('may resize', FRich.CanResizeColumns);
  AssertTrue('a width', FRich.SetColumnWidth(2000));
  AssertEquals('row 0 changed', 2000, EdgeOf(0));
  AssertEquals('row 1 changed', 2000, EdgeOf(1));
  AssertEquals('row 2 as it was', 1440, EdgeOf(2));
  FRich.Undo;
  // the keys: refused as before, told once
  Sel(2, CellStart(1, 1) + 1);
  before := FRich.Text;
  FRich.Refusals.Clear;
  FRich.Typed('x');
  AssertEquals('typing refused, told once', 1, FRich.Refusals.Count);
  FRich.Refusals.Clear;
  FRich.Key(VK_BACK);
  AssertEquals('Backspace refused, told once', 1, FRich.Refusals.Count);
  FRich.Refusals.Clear;
  FRich.Key(VK_DELETE);
  AssertEquals('Delete refused, told once', 1, FRich.Refusals.Count);
  FRich.Refusals.Clear;
  FRich.CutToClipboard;
  AssertEquals('Cut refused, told once', 1, FRich.Refusals.Count);
  AssertEquals('nothing changed', before, FRich.Text);
end;

{ After Backspace on selected rows the caret stands at the start of the first cell of the row
  that took their place - after the table's last row, at the start of the paragraph after it. }
procedure TTyRichTableSelTest.TestTheCaretAfterRowsGo;
var
  c: Integer;
begin
  for c := 0 to 2 do
  begin
    MakeTable(3, 3);
    Sel(CellStart(1, c) + 1, CellStart(1, c) + 1);
    AssertTrue('a row', FRich.SelectRow);
    FRich.Key(VK_BACK);
    AssertEquals(Format('%d: two rows', [c]), 2, RowCount);
    AssertEquals(Format('%d: the caret at the next row''s first cell', [c]), CellStart(1, 0), FRich.SelStart);
    AssertEquals(Format('%d: nothing selected', [c]), 0, FRich.SelLength);
  end;
  MakeTable(3, 3);
  Sel(CellStart(2, 1) + 1, CellStart(2, 1) + 1);
  AssertTrue('the last row', FRich.SelectRow);
  FRich.Key(VK_BACK);
  AssertEquals('the caret after the table', FRich.Document.Text.ParaStart(
    FRich.Document.Text.ParaCount - 1), FRich.SelStart);
end;

{ As Word: Backspace on whole columns deletes them, on whole rows the rows, on the table the
  table, on other cells clears them; Delete always clears and never removes structure. }
procedure TTyRichTableSelTest.TestBackspaceAndDeleteOnColumnsRowsAndCells;
begin
  MakeTable(3, 3);
  Sel(CellStart(0, 1) + 1, CellStart(0, 1) + 1);
  FRich.SelectColumn;
  FRich.Key(VK_BACK);
  AssertEquals('Backspace on a column: it goes', 2, ColCount);
  AssertEquals('the next came left', 'r0c2', CellText(0, 1));
  FRich.Undo;
  Sel(CellStart(0, 1) + 1, CellStart(0, 1) + 1);
  FRich.SelectColumn;
  FRich.Key(VK_DELETE);
  AssertEquals('Delete on a column: it stays', 3, ColCount);
  AssertEquals('cleared', '', CellText(1, 1));
  FRich.Undo;
  Sel(CellStart(1, 0), CellEnd(1, 2));
  FRich.Key(VK_DELETE);
  AssertEquals('Delete on a row: it stays', 3, RowCount);
  AssertEquals('cleared too', '', CellText(1, 0));
  FRich.Undo;
  Sel(CellStart(1, 0), CellEnd(1, 2));
  FRich.Key(VK_BACK);
  AssertEquals('Backspace on a row: it goes', 2, RowCount);
  FRich.Undo;
  Sel(CellStart(0, 0), CellStart(1, 1) + 1);
  FRich.Key(VK_BACK);
  AssertEquals('Backspace on a rectangle: cleared', '', CellText(1, 1));
  AssertEquals('Backspace on a rectangle: the columns stay', 3, ColCount);
  FRich.Undo;
  FRich.SelectTable;
  FRich.Key(VK_DELETE);
  AssertTrue('Delete on the table: it stays', HasTable);
  FRich.Undo;
  FRich.SelectTable;
  FRich.Key(VK_BACK);
  AssertFalse('Backspace on the table: it goes', HasTable);
end;

{ Delete over cells of which a row holds a nested table: the others are cleared, that row is
  left as it is and that is told once, as the format doors tell it. }
procedure TTyRichTableSelTest.TestDeleteOverANestedRowIsTold;
const
  Doc = '{\rtf1 \pard before\par' +
    '\trowd\cellx1440\cellx2880\pard\intbl a\cell \pard\intbl b\cell\row' +
    '\trowd\cellx1440\cellx2880\pard\intbl c\cell \pard\intbl\itap2 x' +
    '\nestcell{\*\nesttableprops\trowd\cellx500\nestrow}{\nonesttables\par}\pard\intbl\cell\row' +
    '\pard after\par}';
var
  st: TStringStream;
begin
  st := TStringStream.Create(Doc);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.UpdateView;
  Sel(CellStart(0, 0), CellEnd(1, 0));
  AssertTrue('cells', FRich.SelectedCells.InTable);
  FRich.Refusals.Clear;
  FRich.Key(VK_DELETE);
  AssertEquals('row 0 cleared', '', CellText(0, 0));
  AssertEquals('the nested row as it was', 'c', CellText(1, 0));
  AssertEquals('told once', 1, FRich.Refusals.Count);
  AssertEquals('why', rsRichEditRefusedResizeNested, FRich.Refusals[0]);
end;

{ Shift+click on a row's zone extends the selection by whole rows from the anchor's row; on a
  column's zone by whole columns from the anchor's column. }
procedure TTyRichTableSelTest.TestShiftClickOnAZoneExtendsByRowsOrColumns;
var
  a: TRect;
  x: Integer;

  // a point of row ARow's zone: found by the press that selects that row
  function RowZoneX(ARow: Integer): Integer;
  var
    i: Integer;
  begin
    Result := -1;
    a := CellRect(ARow, 0);
    for i := 0 to a.Left + 20 do
      if FRich.CursorAtPoint(i, a.Top + 5) = crArrow then
      begin
        Sel(CellStart(ARow, 1) + 1, CellStart(ARow, 1) + 1);
        FRich.Press(i, a.Top + 5);
        FRich.Release(i, a.Top + 5);
        if FRich.SelectedCells.InTable and (FRich.SelectedCells.Col0 = 0) and
           (FRich.SelectedCells.Col1 = 3) then
          Exit(i);
      end;
  end;

begin
  MakeTable(4, 4);
  FRich.UpdateView;
  x := RowZoneX(2);
  AssertTrue('the row zone', x >= 0);
  Sel(CellStart(0, 1) + 1, CellStart(0, 1) + 1);
  a := CellRect(2, 0);
  FRich.Press(x, a.Top + 5, [ssShift]);
  FRich.Release(x, a.Top + 5);
  CheckRange('Shift+click on row 2''s zone', 0, 0, 2, 3);
  // a column: from the anchor's
  Sel(CellStart(1, 1) + 1, CellStart(1, 1) + 1);
  a := CellRect(0, 2);
  AssertEquals('the column''s zone', crUpArrow, FRich.CursorAtPoint(a.Left + 30, a.Top - 2));
  FRich.Press(a.Left + 30, a.Top - 2, [ssShift]);
  FRich.Release(a.Left + 30, a.Top - 2);
  CheckRange('Shift+click on column 2''s zone', 0, 1, 3, 2);
end;

{ The zone left of a row is at least 6 device-independent pixels wide inside the control - for
  a table at the margin and for Word's (\trleft-108), at 100 % and 150 % -, a press there
  selects the row; the zone above a column likewise. }
procedure TTyRichTableSelTest.TestTheRowAndColumnZonesAreWideEnough;
const
  WordRtf = '{\rtf1\ansi{\fonttbl{\f0 Arial;}}\pard before\par' +
    '\trowd\trgaph108\trleft-108\cellx1440\cellx2880\pard\intbl a0\cell a1\cell\row' +
    '\trowd\trgaph108\trleft-108\cellx1440\cellx2880\pard\intbl b0\cell b1\cell\row' +
    '\pard after\par}';
var
  k, ppi, x, y, n, need: Integer;
  st: TStringStream;
  a: TRect;
begin
  for k := 0 to 3 do
  begin
    if k mod 2 = 0 then ppi := 96 else ppi := 144;
    FRich.Font.PixelsPerInch := ppi;
    FRich.SetBounds(0, 0, 600 * ppi div 96, 400 * ppi div 96);
    if k < 2 then MakeTable(2, 2)
    else
    begin
      st := TStringStream.Create(WordRtf);
      try
        FRich.LoadFromStream(st);
      finally
        st.Free;
      end;
    end;
    FRich.UpdateView;
    need := 6 * ppi div 96;
    // the row zone: pixels whose press selects row 1
    a := CellRect(1, 0);
    y := a.Top + 5 * ppi div 96;
    n := 0;
    for x := 0 to FRich.Width div 4 do
      if FRich.CursorAtPoint(x, y) = crArrow then
      begin
        Sel(CellStart(0, 0) + 1, CellStart(0, 0) + 1);
        FRich.Press(x, y);
        FRich.Release(x, y);
        if FRich.SelectedCells.InTable and (FRich.SelectedCells.Row0 = 1) and
           (FRich.SelectedCells.Row1 = 1) and (FRich.SelectedCells.Col1 = 1) and
           (FRich.SelectedCells.Col0 = 0) then
          Inc(n);
      end;
    AssertTrue(Format('%d: the row zone %d px (at least %d)', [k, n, need]), n >= need);
    // the column zone: pixels above the first row whose press selects column 1
    a := CellRect(0, 1);
    n := 0;
    for y := a.Top - 12 * ppi div 96 to a.Top + 4 * ppi div 96 do
      if FRich.CursorAtPoint(a.Left + 30, y) = crUpArrow then
      begin
        Sel(CellStart(1, 0) + 1, CellStart(1, 0) + 1);
        FRich.Press(a.Left + 30, y);
        FRich.Release(a.Left + 30, y);
        if FRich.SelectedCells.InTable and (FRich.SelectedCells.Col0 = 1) and
           (FRich.SelectedCells.Col1 = 1) and (FRich.SelectedCells.Row1 = 1) then
          Inc(n);
      end;
    AssertTrue(Format('%d: the column zone %d px (at least %d)', [k, n, need]), n >= need);
  end;
end;

{ As Word: Cut over cells copies them and clears what they hold - the rows and columns stay -,
  one undo step; whole rows, columns or the table go as Backspace takes them. CanCut says what
  the door does: off for a selection that reaches outside the table. }
procedure TTyRichTableSelTest.TestCutOverCellsCopiesAndClears;
begin
  MakeTable(3, 3);
  Sel(CellStart(0, 0), CellStart(1, 1) + 1);
  AssertTrue('may cut', FRich.CanCut);
  FRich.Refusals.Clear;
  FRich.CutToClipboard;
  AssertEquals('nothing refused', 0, FRich.Refusals.Count);
  AssertEquals('copied as tabbed text', 'r0c0' + #9 + 'r0c1' + LineEnding + 'r1c0' + #9 + 'r1c1', FRich.ClipText);
  AssertEquals('cleared', '', CellText(0, 0));
  AssertEquals('cleared too', '', CellText(1, 1));
  AssertEquals('outside it as it was', 'r0c2', CellText(0, 2));
  AssertEquals('the rows stay', 3, RowCount);
  AssertEquals('the columns stay', 3, ColCount);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  FRich.Undo;
  AssertEquals('undone', 'r0c0', CellText(0, 0));
  // whole rows: they go, as with Backspace
  Sel(CellStart(1, 0), CellEnd(1, 2));
  FRich.CutToClipboard;
  AssertEquals('a row cut', 2, RowCount);
  FRich.Undo;
  // reaching outside the table: not offered, refused as before
  Sel(2, CellStart(1, 1) + 1);
  AssertFalse('not from outside', FRich.CanCut);
end;

// every cell's paragraph a numbered item
procedure NumberEveryCell(R: TSelRich; AFirst, ALast: TTyRichPos);
begin
  R.SelStart := AFirst;
  R.SelLength := ALast - AFirst;
  R.Paragraph.Numbering := lkDecimal;
  R.Document.ClearUndo;
end;

function LevelAt(R: TSelRich; APos: TTyRichPos): Integer;
var
  d: TTyRichDocument;
begin
  d := R.Document;
  Result := d.Formats.ParaFormat(d.ParaFormatOf(d.Text.ParaOfPos(APos))).List.Level;
end;

{ Tab in a table goes from cell to cell and never changes a list level there - also with cells
  selected whose paragraphs are list items. }
procedure TTyRichTableSelTest.TestTabOverListCellsMovesAndNoLevelChanges;
var
  r, c: Integer;
begin
  MakeTable(3, 3);
  FRich.WantTabs := True;
  NumberEveryCell(FRich, CellStart(0, 0), CellEnd(2, 2));
  AssertEquals('(items)', Ord(lkDecimal), Ord(FRich.Document.Formats.ParaFormat(
    FRich.Document.ParaFormatOf(FRich.Document.Text.ParaOfPos(CellStart(1, 1)))).List.Kind));
  Sel(CellStart(0, 1), CellStart(1, 2) + 1);
  AssertTrue('cells', FRich.SelectedCells.InTable);
  FRich.Key(VK_TAB);
  FRich.Key(VK_TAB, [ssShift]);
  Sel(CellStart(1, 1), CellStart(1, 1));
  FRich.Key(VK_TAB);
  AssertTrue('Tab went to the next cell', FRich.SelStart >= CellStart(1, 2));
  for r := 0 to 2 do
    for c := 0 to 2 do
      AssertEquals(Format('%d,%d: its level as it was', [r, c]), 0, LevelAt(FRich, CellStart(r, c)));
  AssertEquals('no step', 0, FRich.Document.UndoDepth);
end;

{ ---- painting ---- }

procedure TTyRichTableSelTest.TestHighlightCoversWholeCells;
var
  b: TBGRABitmap;
  a, c: TRect;
  hi, plain, q: TBGRAPixel;
begin
  MakeTable(3, 3);
  b := TBGRABitmap.Create(FRich.Width, FRich.Height, BGRA(255, 0, 255));
  try
    Sel(CellStart(1, 1), CellStart(1, 1));
    FRich.PaintInto(b);
    a := CellRect(1, 1);
    plain := b.GetPixel(a.Right - 10, a.Top + 5);
    Sel(CellStart(0, 0), CellEnd(1, 1));
    FRich.PaintInto(b);
    // the cell whole, also where it has no text (the right of its box, its padding)
    hi := b.GetPixel(a.Right - 10, a.Top + 5);
    AssertFalse('the selected cell''s empty part is highlighted', (hi.red = plain.red) and
      (hi.green = plain.green) and (hi.blue = plain.blue));
    q := b.GetPixel(a.Left + 3, a.Bottom - 3);
    AssertTrue('its padding too', (q.red = hi.red) and (q.green = hi.green) and (q.blue = hi.blue));
    c := CellRect(1, 2);
    q := b.GetPixel(c.Right - 10, c.Top + 5);
    AssertTrue('a cell beside it is not', (q.red = plain.red) and (q.green = plain.green) and
      (q.blue = plain.blue));
    // one cell whole: the same
    Sel(CellStart(1, 1), CellEnd(1, 1));
    FRich.PaintInto(b);
    q := b.GetPixel(a.Right - 10, a.Top + 5);
    AssertTrue('one cell whole: highlighted', (q.red = hi.red) and (q.green = hi.green) and
      (q.blue = hi.blue));
    q := b.GetPixel(c.Right - 10, c.Top + 5);
    AssertTrue('one cell whole: the next is not', (q.red = plain.red) and (q.green = plain.green) and
      (q.blue = plain.blue));
    // a text selection in a cell: its text only, not the cell
    Sel(CellStart(1, 1), CellStart(1, 1) + 2);
    FRich.PaintInto(b);
    q := b.GetPixel(a.Right - 10, a.Top + 5);
    AssertTrue('text selected: the cell''s empty part is not', (q.red = plain.red) and
      (q.green = plain.green) and (q.blue = plain.blue));
  finally
    b.Free;
  end;
end;

procedure TTyRichTableSelTest.TestAColumnSelectionPaintsOnlyVisibleRows;
const
  Rows = 10000;
var
  d: TTyRichDocument;
  b: TBGRABitmap;
begin
  FRich.Lines.Text := 'before' + LineEnding + 'after';
  d := FRich.Document;
  AssertTrue('a long table', d.Execute(TTyRichInsertTable.Create(d.Text.ParaStart(1), Rows, 3)));
  Sel(d.Text.ParaStart(1 + 3 * 5000 + 1), d.Text.ParaStart(1 + 3 * 5000 + 1));
  AssertTrue('a column', FRich.SelectColumn);
  CheckRange('the column', 0, 1, Rows - 1, 1);
  b := TBGRABitmap.Create(FRich.Width, FRich.Height, BGRA(255, 0, 255));
  try
    FRich.CellRowsPainted := 0;
    FRich.PaintInto(b);
    AssertTrue(Format('%d rows highlighted', [FRich.CellRowsPainted]),
      (FRich.CellRowsPainted > 0) and (FRich.CellRowsPainted <= 2 * (FRich.Height div 10)));
  finally
    b.Free;
  end;
end;

procedure TTyRichTableSelTest.TestAPartOfALongFileSelectsRowsNotColumns;
var
  s: string;
  i, k: Integer;
  st: TStringStream;
begin
  // a table of more than a megabyte: the reader gives it in parts
  s := '{\rtf1\ansi{\fonttbl{\f0 Arial;}}' + LineEnding;
  for i := 0 to 14999 do
    s := s + Format('\trowd\cellx3000\cellx6000\pard\intbl row %d of the long table, cell one\cell row %d cell two\cell\row', [i, i]) + LineEnding;
  s := s + '\pard after\par}';
  st := TStringStream.Create(s);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  k := 2 * 7000;
  AssertTrue('a part', FRich.Document.TableAt(k).Cut);
  Sel(FRich.Document.Text.ParaStart(k), FRich.Document.Text.ParaStart(k));
  AssertTrue('a cell', FRich.SelectCell);
  AssertTrue('the cell', FRich.SelectedCells.InTable);
  AssertTrue('a row', FRich.SelectRow);
  FRich.Refusals.Clear;
  AssertFalse('a column: no', FRich.SelectColumn);
  AssertEquals('told why', 1, FRich.Refusals.Count);
  AssertFalse('the table: no', FRich.SelectTable);
end;

{ A table whose paragraphs are read when asked: the cells of a selection in its middle are
  found from the rows its two ends are in, not from the rows before them. }
procedure TTyRichTableSelTest.TestSelectingReadsOnlyTheRowsItNeeds;
const
  Rows = 1000;
var
  d: TTyRichDocument;
  ld: TSelTableLoader;
  s: RawByteString;
  i: Integer;
  area: TTyRichCellArea;
begin
  SetLength(s, 4 * Rows - 1);
  for i := 1 to 2 * Rows do
  begin
    s[2 * i - 1] := 'x';
    if i < 2 * Rows then s[2 * i] := #10;
  end;
  d := TTyRichDocument.CreateFromUtf8(BytesOf(s));
  try
    ld := TSelTableLoader.Create(Rows, 2);
    ld.ParaFmt := d.Formats.InternPara(TyDefaultParaFormat);
    ld.CharFmt := d.DefaultCharFormatId;
    d.InstallLoader(ld, True);
    // row 500 cell 1 to row 501 cell 0: two rows, both cells
    area := TyRichCellArea(d, d.Text.ParaStart(1001), d.Text.ParaStart(1002) + 1);
    AssertTrue('cells', area.Range.InTable);
    AssertEquals('row 500', 500, area.Range.Row0);
    AssertEquals('to 501', 501, area.Range.Row1);
    AssertTrue(Format('parsed %d paragraphs', [ld.Calls]), ld.Calls <= 8);
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichTableSelTest);
end.
