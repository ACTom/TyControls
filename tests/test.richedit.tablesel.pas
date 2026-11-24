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
  tyControls.RichEdit.Layout, tyControls.RichEdit, test.richedit.layoutdevice;

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
    procedure TestFormatsReachEveryCell;
    procedure TestCopyIsASmallTableAndTabbedText;
    procedure TestPasteFillsCellByCell;
    procedure TestHighlightCoversWholeCells;
    procedure TestAColumnSelectionPaintsOnlyVisibleRows;
    procedure TestAPartOfALongFileSelectsRowsNotColumns;
    procedure TestSelectingReadsOnlyTheRowsItNeeds;
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
