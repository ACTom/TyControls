unit tyControls.RichEdit.TableSel;

{ Which cells of a table a selection covers. A selection is still the anchor and the caret,
  nothing more; this unit reads cells off it by one rule: the cells a selection covers are
  those of its SELECTED CHARACTERS, and a cell's end mark - the end of its last paragraph -
  is one of that cell's characters.

  - Both ends in one cell: the cell is selected whole when the selection runs from the
    cell's first character to its end mark, inclusive (the caret then stands at the next
    cell's start, but nothing of that cell is selected); otherwise it is a selection of text
    inside the cell.
  - The ends in two cells of one table: the rectangle between them - the rows from the one
    to the other, and in each the cells whose horizontal extent meets the span of the two
    corner cells (from the left edge of the one more to the left to the right edge of the
    one more to the right). In a table whose rows all have the same edges that is cells
    Col0 .. Col1 of every row; in one whose rows differ (Word's wide cells, merged cells) it
    is what lies under the span. A rectangle that touches a merged cell grows to hold it
    whole - a cell merged across reaches as far as its merge does, one merged down brings its
    rows - until nothing more joins (the grid's rule, read off the rows around the area:
    tyControls.RichEdit.Grid). So does a merged cell selected whole on its own.
  - One end outside the table: every cell of the rows the selection touches.
  - Anything else (both ends outside, ends in two tables): no cell range - a text
    selection.

  The rows are found by paragraphs, not by numbers: the corner cells' rows are where the
  selection's ends are, so a paint asks no more than "is this row between those paragraphs".
  Row numbers (TTyRichCellRange.Row0 / Row1) come from the document
  (TTyRichDocument.TableRowIndex). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.TableProps, tyControls.RichEdit.Grid;

type
  TTyRichCellRange = record
    InTable: Boolean;
    TablePos: TTyRichPos;
    Row0, Col0, Row1, Col1: Integer;
    WholeTable: Boolean;
  end;

  { A cell range and what tells its cells: the paragraphs of its rows, the table they are of,
    the horizontal span (twips) a cell of those rows must meet - or every cell. }
  TTyRichCellArea = record
    Range: TTyRichCellRange;
    Table: TTyRichTable;
    FirstPara, LastPara: Integer;
    X0, X1: Int64;
    AllCells: Boolean;
    { One end of the selection is outside the table: the rows are its cells (what shows), but
      the selection holds text outside them too - edits, copies and formats keep the rules of
      a text selection (TyRichCellsEditable). }
    Outside: Boolean;
  end;

{ The cells the selection AAnchor .. ACaret covers (Range.InTable False: none - a text
  selection). Reads the paragraphs at the ends, the rows they are in, and - when one end is
  outside the table - the paragraphs from it to the table. }
function TyRichCellArea(ADoc: TTyRichDocument; AAnchor, ACaret: TTyRichPos): TTyRichCellArea;
{ Cell ACell of row ARow is in the area (the row's paragraphs are between FirstPara and
  LastPara: the caller knows which paragraphs it has). }
function TyRichCellInArea(const AArea: TTyRichCellArea; ARow: TTyRichRow; ACell: Integer): Boolean;
{ The paragraphs of the row / of the cell paragraph APara is in (a walk over that row). }
function TyRichRowParas(ADoc: TTyRichDocument; APara: Integer; out AFirst, ALast: Integer): Boolean;
function TyRichCellParasOf(ADoc: TTyRichDocument; APara: Integer; out AFirst, ALast: Integer): Boolean;
{ A cell's horizontal extent in twips: from its left edge (the row's left for the first) to
  its right edge - for a cell merged across with the marks (\clmgf / \clmrg), the extent of
  the merged box it is part of. }
procedure TyRichCellExtent(ARow: TTyRichRow; ACell: Integer; out ALeft, ARight: Int64);
{ The area's rows are whole: every cell of each of them is in it. }
function TyRichAreaWholeRows(ADoc: TTyRichDocument; const AArea: TTyRichCellArea): Boolean;
{ The selection is cells and nothing else - both its ends in the table: Delete, Backspace,
  typing, the formats, a copy and a paste act on the cells. }
function TyRichCellsEditable(const AArea: TTyRichCellArea): Boolean;

type
  TTyRichCellFillKind = (rcfClear, rcfText, rcfContent);

  { What one cell gets: its content cleared, plain text in the format of its first
    character, or another document's content (taken over: the command frees it) as the
    cell's paragraphs. Row: from the command's first row (0); Col: the cell's index in it. }
  TTyRichCellFillItem = record
    Row, Col: Integer;
    Kind: TTyRichCellFillKind;
    Text: UTF8String;
    Source: TTyRichDocument;
    Fragment: TTyRichFragment;
  end;

  { Cells of the table a position is in filled or cleared, as one command and one undo step:
    each cell named gets its content replaced (a cell keeps one paragraph when cleared). Rows
    the items name past the table's last row are added below it first (like its last row);
    an item for a cell a row does not have is left out and counted (Dropped). What goes in
    is made at the first run and put in again by a redo. }
  TTyRichCellsEdit = class(TTyRichCommand)
  private
    FPos: TTyRichPos;
    FItems: array of TTyRichCellFillItem;
    FDescription: string;
    FDropped: Integer;
    procedure DeleteKeepingMarks(ADoc: TTyRichDocument; AFrom, ATo: TTyRichPos);
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    { APos: a position in the first row the items count from. }
    constructor Create(APos: TTyRichPos; const ADescription: string);
    destructor Destroy; override;
    procedure AddClear(ARow, ACol: Integer);
    procedure AddText(ARow, ACol: Integer; const AText: UTF8String);
    procedure AddContent(ARow, ACol: Integer; ASource: TTyRichDocument);
    function Count: Integer;
    { The first row is the one APos is in now (before it runs: a cut ahead of it in the same
      step moved it). }
    procedure MoveTo(APos: TTyRichPos);
    function Description: string; override;
    property Dropped: Integer read FDropped;
  end;

type
  { After rows (or a table) that held one mark of a bookmark went in the same step: the
    bookmark's other mark, outside them, goes too - no lone mark is left. Each mark is given
    by where it was before the rows went (APos) and its name; at its run the place is found
    again from how much text went (the rows lay from ACut on: a mark after them moved back by
    that much). }
  TTyRichDropLoneMarks = class(TTyRichCommand)
  private
    FPos: array of TTyRichPos;
    FNames: array of UTF8String;
    FLen0, FCut: TTyRichPos;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(ADoc: TTyRichDocument; ACut: TTyRichPos);
    procedure Add(APos: TTyRichPos; const AName: UTF8String);
    function Count: Integer;
  end;

{ The bookmarks one of whose marks lies in paragraphs AFirst .. ALast and the other outside
  them: a command dropping those outside marks (nil: none). }
function TyRichLoneMarksOutside(ADoc: TTyRichDocument; AFirst, ALast: Integer): TTyRichDropLoneMarks;

{ ---- one edge, one definition ----

  A line two cells share is defined twice in a file: as the one cell's side and as the other's
  facing side. Word keeps both the same - it shows one line and tells it from either cell -
  and so does this control for every line it writes: a border given to a cell's side is given
  to the facing side too, in the same step, and the table edits leave both sides alike. Only
  a file made elsewhere can still have two that differ (the layout then draws the wider, the
  later cell's at the same width: where Word may show another line). }

type
  { The lines of a rectangle of cells: its outline's four sides and its inner lines. }
  TTyRichCellLine = (rclLeft, rclTop, rclRight, rclBottom, rclInsideH, rclInsideV);
  TTyRichCellLines = set of TTyRichCellLine;

  { The cells' sides a border goes to (Mark), and then the facing sides of the cells beside
    them: in a row, the cell before / after (by index); between rows, the cells of the row
    above / below whose whole edge lies inside the span the marked cells' edge covers there
    (positions within CRichSharedEdgeTwips) - a cell that only partly shares it keeps its own
    side, as does a cell wider than the span. Rows that hold a nested table are left as they
    are and counted. The parts: TTyRichSetCellProps, as few as the marks allow. }
  TTyRichBorderPlan = class
  private
    FPos: TTyRichPos;
    FFirst: Integer;
    FLeft: array of Integer;
    FEdges: array of TTyRichEdges;
    FNested: array of Boolean;
    FOwn: array of array of TTyRowCellSides;
    function CellLeft(I, C: Integer): Integer;
    function CellCount(I: Integer): Integer;
  public
    { The rows ARow0 - 1 .. ARow1 + 1 of the table APos is in are read. }
    constructor Create(ADoc: TTyRichDocument; APos: TTyRichPos; ARow0, ARow1: Integer);
    procedure Mark(ARow0, ACol0, ARow1, ACol1: Integer; ASides: TTyRowCellSides);
    { The sides that make ALines of the rectangle rows ARow0 .. ARow1, cells ACol0 .. ACol1 -
      each row's last cell in it its right edge (ACol1 past a row's cells: to its last). }
    procedure MarkLines(ARow0, ACol0, ARow1, ACol1: Integer; ALines: TTyRichCellLines);
    { The parts, ABorder on every side marked and on every side facing one, added to AComp;
      ASkipped: rows left as they are (they hold a nested table) added. }
    procedure AddParts(AComp: TTyRichCompositeCommand; const ABorder: TTyRichBorder;
      var ASkipped: Integer);
  end;

  { After a table edit (rows or columns in or out): both sides of every line two cells share
    made alike in rows ARow0 .. ARow1 (cut to the table's) and between them - the side that
    loses takes the other's border, the winner being the line the layout draws there (the
    wider, the later cell's at the same width), so nothing a person sees changes. Between rows
    only cells whose edges are where the other's are (within CRichSharedEdgeTwips); a row that
    holds a nested table is left as it is. Planned at its first run, from the table as the
    edit before it in the step left it; a row already alike is not touched. }
  TTyRichAgreeEdges = class(TTyRichCompositeCommand)
  private
    FPos: TTyRichPos;
    FRow0, FRow1: Integer;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(APos: TTyRichPos; ARow0, ARow1: Integer);
  end;

implementation

uses
  Math, tyControls.RichEdit.RtfRead, tyControls.RichEdit.Bookmarks;

function TyRichCellsEditable(const AArea: TTyRichCellArea): Boolean;
begin
  Result := AArea.Range.InTable and not AArea.Outside;
end;

constructor TTyRichDropLoneMarks.Create(ADoc: TTyRichDocument; ACut: TTyRichPos);
begin
  inherited Create;
  FLen0 := ADoc.Text.Length;
  FCut := ACut;
end;

procedure TTyRichDropLoneMarks.Add(APos: TTyRichPos; const AName: UTF8String);
begin
  SetLength(FPos, Length(FPos) + 1);
  SetLength(FNames, Length(FNames) + 1);
  FPos[High(FPos)] := APos;
  FNames[High(FNames)] := AName;
end;

function TTyRichDropLoneMarks.Count: Integer;
begin
  Result := Length(FPos);
end;

procedure TTyRichDropLoneMarks.DoExecute(ADoc: TTyRichDocument);
var
  i, j: Integer;
  p, d: TTyRichPos;
  o: TTyRichObject;
  order: array of Integer;
begin
  d := FLen0 - ADoc.Text.Length;
  // the last first: the places before stay where they are
  order := nil;
  SetLength(order, Length(FPos));
  for i := 0 to High(order) do order[i] := i;
  for i := 1 to High(order) do
  begin
    j := i;
    while (j > 0) and (FPos[order[j - 1]] < FPos[order[j]]) do
    begin
      p := order[j];
      order[j] := order[j - 1];
      order[j - 1] := p;
      Dec(j);
    end;
  end;
  for i := 0 to High(order) do
  begin
    p := FPos[order[i]];
    if p >= FCut then Dec(p, d);
    ADoc.BeginRead;
    try
      o := ADoc.ObjectAt(p);
    finally
      ADoc.EndRead;
    end;
    if (o is TTyRichBookmarkMark) and TyRichSameBookmarkName(TTyRichBookmarkMark(o).Name,
       FNames[order[i]]) then
      DeleteObjectAt(ADoc, p);
  end;
end;

function TyRichLoneMarksOutside(ADoc: TTyRichDocument; AFirst, ALast: Integer): TTyRichDropLoneMarks;
var
  t: TTyRichText;
  k, j, i, n: Integer;
  runs: TTyRunArray;
  ps, lo, hi, s, e: TTyRichPos;
  names: array of UTF8String;
  kinds: array of TTyRichBookmarkKind;
  paired: array of Boolean;
begin
  Result := nil;
  t := ADoc.Text;
  lo := t.ParaStart(AFirst);
  hi := t.ParaStart(ALast) + t.ParaLength(ALast);
  n := 0;
  names := nil;
  kinds := nil;
  ADoc.BeginRead;
  try
    for k := AFirst to ALast do
    begin
      runs := ADoc.RunsOf(k);
      ps := t.ParaStart(k);
      for j := 0 to High(runs) do
        if runs[j].Obj is TTyRichBookmarkMark then
        begin
          SetLength(names, n + 1);
          SetLength(kinds, n + 1);
          names[n] := TTyRichBookmarkMark(runs[j].Obj).Name;
          kinds[n] := TTyRichBookmarkMark(runs[j].Obj).Kind;
          Inc(n);
        end;
    end;
  finally
    ADoc.EndRead;
  end;
  if n = 0 then Exit;
  paired := nil;
  SetLength(paired, n);
  for i := 0 to n - 1 do
    if (kinds[i] = rbmStart) and not paired[i] then
      for j := i + 1 to n - 1 do
        if (kinds[j] = rbmEnd) and not paired[j] and TyRichSameBookmarkName(names[i], names[j]) then
        begin
          paired[i] := True;
          paired[j] := True;
          Break;
        end;
  for i := 0 to n - 1 do
  begin
    if paired[i] then Continue;
    // its other mark: where the bookmark's marks are
    if not TyRichFindBookmark(ADoc, names[i], s, e) then Continue;
    if kinds[i] = rbmStart then s := e;
    if (s < lo) or (s > hi) then
    begin
      if Result = nil then Result := TTyRichDropLoneMarks.Create(ADoc, hi);
      Result.Add(s, names[i]);
    end;
  end;
end;

{ ---- one edge, one definition ---- }

const
  CBorderCellProp: array[TTyRichCellSide] of TTyRichCellProp = (rcpBorderLeft, rcpBorderTop,
    rcpBorderRight, rcpBorderBottom);

function SideProps(ASide: TTyRichCellSide; const ABorder: TTyRichBorder): TTyRichCellProps;
begin
  Result := Default(TTyRichCellProps);
  Result.Valid := [CBorderCellProp[ASide]];
  Result.Borders[ASide] := ABorder;
end;

constructor TTyRichBorderPlan.Create(ADoc: TTyRichDocument; APos: TTyRichPos; ARow0, ARow1: Integer);
var
  rows: TTyRichRowList;
  n, i, c: Integer;
begin
  inherited Create;
  FPos := APos;
  ADoc.BeginRead;
  try
    if not ADoc.TableRowsAt(APos, ARow0 - 1, ARow1 + 1, rows, FFirst, n) then rows := nil;
    SetLength(FLeft, Length(rows));
    SetLength(FEdges, Length(rows));
    SetLength(FNested, Length(rows));
    SetLength(FOwn, Length(rows));
    for i := 0 to High(rows) do
    begin
      FLeft[i] := rows[i].Format.Row.LeftTwips;
      FEdges[i] := rows[i].CellEdges;
      FNested[i] := rows[i].HoldsNestedTable;
      SetLength(FOwn[i], Length(FEdges[i]));
      for c := 0 to High(FOwn[i]) do FOwn[i][c] := [];
    end;
  finally
    ADoc.EndRead;
  end;
end;

function TTyRichBorderPlan.CellCount(I: Integer): Integer;
begin
  Result := Length(FEdges[I]);
end;

function TTyRichBorderPlan.CellLeft(I, C: Integer): Integer;
begin
  if C = 0 then Result := FLeft[I] else Result := FEdges[I][C - 1];
end;

procedure TTyRichBorderPlan.Mark(ARow0, ACol0, ARow1, ACol1: Integer; ASides: TTyRowCellSides);
var
  r, i, c: Integer;
begin
  for r := ARow0 to ARow1 do
  begin
    i := r - FFirst;
    if (i < 0) or (i > High(FOwn)) then Continue;
    for c := Math.Max(ACol0, 0) to Math.Min(ACol1, CellCount(i) - 1) do
      FOwn[i][c] := FOwn[i][c] + ASides;
  end;
end;

procedure TTyRichBorderPlan.MarkLines(ARow0, ACol0, ARow1, ACol1: Integer; ALines: TTyRichCellLines);
var
  r, i, c, last: Integer;
  sd: TTyRowCellSides;
begin
  for r := ARow0 to ARow1 do
  begin
    i := r - FFirst;
    if (i < 0) or (i > High(FOwn)) then Continue;
    last := Math.Min(ACol1, CellCount(i) - 1);
    for c := Math.Max(ACol0, 0) to last do
    begin
      sd := [];
      if (rclLeft in ALines) and (c = ACol0) then Include(sd, rcsLeft);
      if (rclRight in ALines) and (c = last) then Include(sd, rcsRight);
      if (rclTop in ALines) and (r = ARow0) then Include(sd, rcsTop);
      if (rclBottom in ALines) and (r = ARow1) then Include(sd, rcsBottom);
      if rclInsideH in ALines then
      begin
        if r < ARow1 then Include(sd, rcsBottom);
        if r > ARow0 then Include(sd, rcsTop);
      end;
      if rclInsideV in ALines then
      begin
        if c < last then Include(sd, rcsRight);
        if c > ACol0 then Include(sd, rcsLeft);
      end;
      FOwn[i][c] := FOwn[i][c] + sd;
    end;
  end;
end;

procedure TTyRichBorderPlan.AddParts(AComp: TTyRichCompositeCommand; const ABorder: TTyRichBorder;
  var ASkipped: Integer);
var
  all: array of array of TTyRowCellSides;
  i, c, a, b, j, lo, hi: Integer;
  sd: TTyRichCellSide;
  pend: Boolean;
  pr0, pr1, pa, pb: Integer;
  runs: Integer;

  // the cells of row AI whose whole edge lies inside ALo .. AHi get ASide
  procedure Face(AI, ALo, AHi: Integer; ASide: TTyRichCellSide);
  var
    k: Integer;
  begin
    if (AI < 0) or (AI > High(all)) then Exit;
    for k := 0 to CellCount(AI) - 1 do
      if (CellLeft(AI, k) >= ALo - CRichSharedEdgeTwips) and
         (FEdges[AI][k] <= AHi + CRichSharedEdgeTwips) then
        Include(all[AI][k], ASide);
  end;

  procedure Flush(ASide: TTyRichCellSide);
  begin
    if not pend then Exit;
    pend := False;
    AComp.Add(TTyRichSetCellProps.Create(FPos, FFirst + pr0, pa, FFirst + pr1, pb,
      SideProps(ASide, ABorder)));
  end;

begin
  all := nil;
  SetLength(all, Length(FOwn));
  for i := 0 to High(FOwn) do all[i] := Copy(FOwn[i]);
  for i := 0 to High(FOwn) do
  begin
    for c := 0 to CellCount(i) - 1 do
    begin
      if (rcsLeft in FOwn[i][c]) and (c > 0) then Include(all[i][c - 1], rcsRight);
      if (rcsRight in FOwn[i][c]) and (c < CellCount(i) - 1) then Include(all[i][c + 1], rcsLeft);
    end;
    // between rows: by the span each run of marked cells covers
    for sd := rcsTop to rcsBottom do
    begin
      if sd = rcsRight then Continue;
      c := 0;
      while c < CellCount(i) do
      begin
        if not (sd in FOwn[i][c]) then
        begin
          Inc(c);
          Continue;
        end;
        a := c;
        while (c + 1 < CellCount(i)) and (sd in FOwn[i][c + 1]) do Inc(c);
        lo := CellLeft(i, a);
        hi := FEdges[i][c];
        if sd = rcsTop then Face(i - 1, lo, hi, rcsBottom) else Face(i + 1, lo, hi, rcsTop);
        Inc(c);
      end;
    end;
  end;
  // rows that hold a nested table: told, not touched
  for i := 0 to High(all) do
    if FNested[i] then
    begin
      j := 0;
      for c := 0 to High(all[i]) do
        if all[i][c] <> [] then j := 1;
      Inc(ASkipped, j);
    end;
  // each side: runs of cells, a run the same in the rows below it one part
  for sd := Low(TTyRichCellSide) to High(TTyRichCellSide) do
  begin
    pend := False;
    pr0 := 0;
    pr1 := 0;
    pa := 0;
    pb := 0;
    for i := 0 to High(all) do
    begin
      if FNested[i] then
      begin
        Flush(sd);
        Continue;
      end;
      runs := 0;
      c := 0;
      while c < Length(all[i]) do
      begin
        if not (sd in all[i][c]) then
        begin
          Inc(c);
          Continue;
        end;
        a := c;
        while (c + 1 < Length(all[i])) and (sd in all[i][c + 1]) do Inc(c);
        b := c;
        Inc(runs);
        if pend and (pr1 = i - 1) and (pa = a) and (pb = b) and (runs = 1) then
          pr1 := i
        else
        begin
          Flush(sd);
          pend := True;
          pr0 := i;
          pr1 := i;
          pa := a;
          pb := b;
        end;
        Inc(c);
      end;
      // (a row with no run, or with several: nothing runs on past it)
      if runs <> 1 then Flush(sd);
    end;
    Flush(sd);
  end;
end;

constructor TTyRichAgreeEdges.Create(APos: TTyRichPos; ARow0, ARow1: Integer);
begin
  inherited Create;
  FPos := APos;
  FRow0 := ARow0;
  FRow1 := ARow1;
end;

type
  TTyRichAgreeChange = record
    Row, Cell: Integer;
    Side: TTyRichCellSide;
    Border: TTyRichBorder;
  end;

procedure TTyRichAgreeEdges.DoExecute(ADoc: TTyRichDocument);
var
  rows: TTyRichRowList;
  first, n: Integer;
  ch: array of TTyRichAgreeChange;
  nch: Integer;

  function BorderOf(AI, AC: Integer; ASide: TTyRichCellSide): TTyRichBorder;
  var
    f: TTyRichRowFormat;
  begin
    f := rows[AI].Format;
    if (AC >= 0) and (AC < Length(f.Cells)) then Result := f.Cells[AC].Props.Borders[ASide]
    else Result := TyRichBorder(rbsNone, 0);
  end;


  procedure Change(AI, AC: Integer; ASide: TTyRichCellSide; const B: TTyRichBorder);
  begin
    if nch = Length(ch) then SetLength(ch, nch * 2 + 8);
    ch[nch].Row := AI;
    ch[nch].Cell := AC;
    ch[nch].Side := ASide;
    ch[nch].Border := B;
    Inc(nch);
  end;

  { The earlier side (AI, AC, ASide) and the later one (AJ, AD, AFace): the loser takes the
    winner's border - the wider, the later's at the same width (the line drawn there). }
  procedure Agree(AI, AC: Integer; ASide: TTyRichCellSide; AJ, AD: Integer; AFace: TTyRichCellSide);
  var
    e, l: TTyRichBorder;
  begin
    e := BorderOf(AI, AC, ASide);
    l := BorderOf(AJ, AD, AFace);
    if TyRichSameBorder(e, l) then Exit;
    // (the layout's rule: the line drawn there stays - TyRichLaterLineWins)
    if TyRichLaterLineWins(e, l) then Change(AI, AC, ASide, l)
    else Change(AJ, AD, AFace, e);
  end;

  function LeftOf(AI, AC: Integer; const AE: TTyRichEdges): Integer;
  begin
    if AC = 0 then Result := rows[AI].Format.Row.LeftTwips else Result := AE[AC - 1];
  end;

  procedure Plan;
  var
    ea, eb: TTyRichEdges;
    i, a, b, na, nb, k, m, j: Integer;
    merged: Boolean;
  begin
    nch := 0;
    ch := nil;
    for i := 0 to High(rows) do
    begin
      if rows[i].HoldsNestedTable then Continue;
      for a := 0 to rows[i].CellCount - 2 do Agree(i, a, rcsRight, i, a + 1, rcsLeft);
      if (i = High(rows)) or rows[i + 1].HoldsNestedTable then Continue;
      ea := rows[i].CellEdges;
      eb := rows[i + 1].CellEdges;
      na := Length(ea);
      nb := Length(eb);
      // (cells paired by where their edges are: the layout's pairing, TyRichFacingCell)
      for a := 0 to na - 1 do
      begin
        b := TyRichFacingCell(ea, LeftOf(i, 0, ea), a, eb, LeftOf(i + 1, 0, eb));
        if b >= 0 then Agree(i, a, rcsBottom, i + 1, b, rcsTop);
      end;
    end;
    { The parts: a change the same in the next row (the same cell, side and border) runs on
      into it - a column put in a long table is one part. }
    k := 0;
    while k < nch do
    begin
      if ch[k].Row < 0 then
      begin
        Inc(k);
        Continue;
      end;
      m := ch[k].Row;
      j := k + 1;
      repeat
        merged := False;
        while (j < nch) and (ch[j].Row <= m + 1) do
        begin
          if (ch[j].Row = m + 1) and (ch[j].Cell = ch[k].Cell) and (ch[j].Side = ch[k].Side) and
             TyRichSameBorder(ch[j].Border, ch[k].Border) then
          begin
            ch[j].Row := -1;
            Inc(m);
            merged := True;
            Inc(j);
            Break;
          end;
          Inc(j);
        end;
      until not merged;
      Add(TTyRichSetCellProps.Create(FPos, first + ch[k].Row, ch[k].Cell, first + m, ch[k].Cell,
        SideProps(ch[k].Side, ch[k].Border)));
      ch[k].Row := -1;
      Inc(k);
    end;
  end;

begin
  if Count = 0 then
  begin
    ADoc.BeginRead;
    try
      if ADoc.TableRowsAt(FPos, FRow0, FRow1, rows, first, n) then Plan;
    finally
      ADoc.EndRead;
    end;
  end;
  inherited DoExecute(ADoc);
end;

function TyRichAreaWholeRows(ADoc: TTyRichDocument; const AArea: TTyRichCellArea): Boolean;
var
  c: TTyRichCell;
  l, r: Int64;
  k: Integer;
begin
  if not AArea.Range.InTable then Exit(False);
  if AArea.AllCells then Exit(True);
  Result := True;
  ADoc.BeginRead;
  try
    for k := 0 to 1 do
    begin
      if k = 0 then c := ADoc.CellAt(AArea.FirstPara) else c := ADoc.CellAt(AArea.LastPara);
      if c = nil then Exit(False);
      TyRichCellExtent(c.Row, 0, l, r);
      if AArea.X0 > l then Result := False;
      TyRichCellExtent(c.Row, c.Row.CellCount - 1, l, r);
      if AArea.X1 < r then Result := False;
    end;
  finally
    ADoc.EndRead;
  end;
end;

{ ---- TTyRichCellsEdit ---- }

constructor TTyRichCellsEdit.Create(APos: TTyRichPos; const ADescription: string);
begin
  inherited Create;
  FPos := APos;
  FDescription := ADescription;
end;

destructor TTyRichCellsEdit.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FItems) do
  begin
    FItems[i].Source.Free;
    FItems[i].Fragment.Free;
  end;
  inherited Destroy;
end;

procedure TTyRichCellsEdit.AddClear(ARow, ACol: Integer);
begin
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := Default(TTyRichCellFillItem);
  FItems[High(FItems)].Row := ARow;
  FItems[High(FItems)].Col := ACol;
  FItems[High(FItems)].Kind := rcfClear;
end;

procedure TTyRichCellsEdit.AddText(ARow, ACol: Integer; const AText: UTF8String);
begin
  AddClear(ARow, ACol);
  FItems[High(FItems)].Kind := rcfText;
  FItems[High(FItems)].Text := AText;
end;

procedure TTyRichCellsEdit.AddContent(ARow, ACol: Integer; ASource: TTyRichDocument);
begin
  AddClear(ARow, ACol);
  FItems[High(FItems)].Kind := rcfContent;
  FItems[High(FItems)].Source := ASource;
end;

function TTyRichCellsEdit.Count: Integer;
begin
  Result := Length(FItems);
end;

procedure TTyRichCellsEdit.MoveTo(APos: TTyRichPos);
begin
  FPos := APos;
end;

function TTyRichCellsEdit.Description: string;
begin
  Result := FDescription;
end;

{ [AFrom, ATo) of a cell goes - but a bookmark's mark whose other mark lies outside it stays
  (the bookmark collapses where the content was, as in Word; the engine's own deletion leaves
  such marks to go inside a cell): no lone mark is left behind. }
procedure TTyRichCellsEdit.DeleteKeepingMarks(ADoc: TTyRichDocument; AFrom, ATo: TTyRichPos);
var
  t: TTyRichText;
  k, j, i, n: Integer;
  runs: TTyRunArray;
  ps, p, e: TTyRichPos;
  pos: array of TTyRichPos;
  bms: array of TTyRichBookmarkMark;
  paired: array of Boolean;
  kept: array of TTyRichPos;
begin
  t := ADoc.Text;
  n := 0;
  pos := nil;
  bms := nil;
  ADoc.BeginRead;
  try
    for k := t.ParaOfPos(AFrom) to t.ParaOfPos(ATo - 1) do
    begin
      runs := ADoc.RunsOf(k);
      ps := t.ParaStart(k);
      for j := 0 to High(runs) do
      begin
        p := ps + runs[j].Start;
        if (p < AFrom) or (p >= ATo) or not (runs[j].Obj is TTyRichBookmarkMark) then Continue;
        SetLength(pos, n + 1);
        SetLength(bms, n + 1);
        pos[n] := p;
        bms[n] := TTyRichBookmarkMark(runs[j].Obj);
        Inc(n);
      end;
    end;
  finally
    ADoc.EndRead;
  end;
  paired := nil;
  SetLength(paired, n);
  for i := 0 to n - 1 do
    if (bms[i].Kind = rbmStart) and not paired[i] then
      for j := i + 1 to n - 1 do
        if (bms[j].Kind = rbmEnd) and not paired[j] and
          TyRichSameBookmarkName(bms[i].Name, bms[j].Name) then
        begin
          paired[i] := True;
          paired[j] := True;
          Break;
        end;
  kept := nil;
  for i := 0 to n - 1 do
    if not paired[i] then
    begin
      SetLength(kept, Length(kept) + 1);
      kept[High(kept)] := pos[i];
    end;
  // the stretches between the bms kept, the last first (the places before stay)
  e := ATo;
  for i := High(kept) downto 0 do
  begin
    if e > kept[i] + 1 then DeleteRange(ADoc, kept[i] + 1, e - kept[i] - 1);
    e := kept[i];
  end;
  if e > AFrom then DeleteRange(ADoc, AFrom, e - AFrom);
end;

procedure TTyRichCellsEdit.DoExecute(ADoc: TTyRichDocument);
var
  t: TTyRichText;
  starts: array of Integer;
  i, j, k, f, l, rows, want, last: Integer;
  c: TTyRichCell;
  s, e: TTyRichPos;
  tables: TTyRichTables;
  flt: TTyRichFragmentFilter;

  // the first paragraph of every row from the command's first row to the table's last
  procedure FindRows;
  var
    p, a, b: Integer;
    d: TTyRichCell;
  begin
    starts := nil;
    p := t.ParaOfPos(FPos);
    if not TyRichRowParas(ADoc, p, a, b) then
      raise ETyRichModel.Create('The cells to fill are in no table');
    while True do
    begin
      SetLength(starts, Length(starts) + 1);
      starts[High(starts)] := a;
      // (the rows the items name, no more: a long table is not walked to its end)
      if Length(starts) >= want then Break;
      if b + 1 >= t.ParaCount then Break;
      d := ADoc.CellAt(b + 1);
      if d = nil then Break;
      TyRichRowParas(ADoc, b + 1, a, b);
    end;
  end;

begin
  t := ADoc.Text;
  FDropped := 0;
  ADoc.BeginRead;
  try
    // rows the items need below the table's last
    want := 1;
    for i := 0 to High(FItems) do want := Max(want, FItems[i].Row + 1);
    FindRows;
    rows := Length(starts);
    while rows < want do
    begin
      tables := nil;
      EditTable(ADoc, TyRichTableEdit(rtkInsertRow, t.ParaStart(starts[rows - 1]), CRichRowBelow),
        tables);
      for k := 0 to High(tables) do tables[k].Release;
      FindRows;
      if Length(starts) <= rows then
        raise ETyRichModel.Create('A row could not be added');
      rows := Length(starts);
    end;
    // the cells, from the last to the first: the places before each stay where they are
    for i := High(FItems) downto 0 do
    begin
      FindRows;
      if FItems[i].Row >= Length(starts) then Continue;
      // the cell's paragraphs: from the row's first, the cell of that index
      k := starts[FItems[i].Row];
      last := t.ParaCount - 1;
      f := -1;
      l := -1;
      j := k;
      while j <= last do
      begin
        c := ADoc.CellAt(j);
        if (c = nil) or (c.Row <> ADoc.CellAt(k).Row) then Break;
        if c.Index = FItems[i].Col then
        begin
          if f < 0 then f := j;
          l := j;
        end;
        Inc(j);
      end;
      if f < 0 then
      begin
        Inc(FDropped);
        Continue;
      end;
      s := t.ParaStart(f);
      e := t.ParaStart(l) + t.ParaLength(l);
      if e > s then DeleteKeepingMarks(ADoc, s, e);
      case FItems[i].Kind of
        rcfText:
          if FItems[i].Text <> '' then InsertText(ADoc, s, FItems[i].Text);
        rcfContent:
          begin
            if FItems[i].Fragment = nil then
            begin
              flt := TyRichFragmentFilterFor(FItems[i].Source, ADoc);
              try
                FItems[i].Fragment := TTyRichFragment.Create(ADoc, s, FItems[i].Source, False, True,
                  flt);
              finally
                flt.Free;
              end;
              FreeAndNil(FItems[i].Source);
            end;
            if FItems[i].Fragment.PartCount > 0 then InsertFragment(ADoc, s, FItems[i].Fragment);
          end;
      end;
    end;
  finally
    ADoc.EndRead;
  end;
end;

procedure TyRichCellExtent(ARow: TTyRichRow; ACell: Integer; out ALeft, ARight: Int64);
var
  e: TTyRichEdges;
  a, b: Integer;
begin
  e := ARow.CellEdges;
  if (ACell < 0) or (ACell > High(e)) then
  begin
    ALeft := 0;
    ARight := 0;
    Exit;
  end;
  // (merged across with the marks: the box from the first cell to the last continuing it)
  a := ACell;
  while (a > 0) and (TyRichCellHMerge(ARow, a) = Ord(rcmContinue)) do Dec(a);
  b := ACell;
  if (TyRichCellHMerge(ARow, a) = Ord(rcmFirst)) or (a < ACell) then
    while (b < High(e)) and (TyRichCellHMerge(ARow, b + 1) = Ord(rcmContinue)) do Inc(b);
  if a = 0 then ALeft := ARow.Format.Row.LeftTwips else ALeft := e[a - 1];
  ARight := e[b];
end;

{ The area grown over the merged cells it touches: across to every merged cell's whole
  extent, down and up to the rows a vertical merge it touches takes, until nothing more
  joins. Reads the rows of the area and the one above and below it each round. }
procedure GrowOverSpans(ADoc: TTyRichDocument; var AArea: TTyRichCellArea);
var
  changed: Boolean;
  k, f, l, i, pf, pl, nf, nl, o: Integer;
  c, nc: TTyRichCell;
  row: TTyRichRow;
  cl, cr: Int64;
  vm: Integer;
begin
  if AArea.AllCells or (AArea.FirstPara < 0) then Exit;
  repeat
    changed := False;
    k := AArea.FirstPara;
    while k <= AArea.LastPara do
    begin
      c := ADoc.CellAt(k);
      if (c = nil) or not TyRichRowParas(ADoc, k, f, l) then Break;
      row := c.Row;
      for i := 0 to row.CellCount - 1 do
      begin
        if not TyRichCellInArea(AArea, row, i) then Continue;
        TyRichCellExtent(row, i, cl, cr);
        if cl < AArea.X0 then
        begin
          AArea.X0 := cl;
          changed := True;
        end;
        if cr > AArea.X1 then
        begin
          AArea.X1 := cr;
          changed := True;
        end;
        vm := TyRichCellVMerge(row, i);
        // continues the cell above: that row joins
        if (f = AArea.FirstPara) and (vm = Ord(rcmContinue)) and (f > 0) then
        begin
          nc := ADoc.CellAt(f - 1);
          if (nc <> nil) and (nc.Table = c.Table) and TyRichRowParas(ADoc, f - 1, pf, pl) then
          begin
            AArea.FirstPara := pf;
            changed := True;
          end;
        end;
        // goes on in the row below: that row joins
        if (l = AArea.LastPara) and (vm <> Ord(rcmNone)) and (l + 1 < ADoc.Text.ParaCount) then
        begin
          nc := ADoc.CellAt(l + 1);
          if (nc <> nil) and (nc.Table = c.Table) and TyRichRowParas(ADoc, l + 1, nf, nl) then
          begin
            o := TyRichFacingCell(row.CellEdges, row.Format.Row.LeftTwips, i, nc.Row.CellEdges,
              nc.Row.Format.Row.LeftTwips);
            if (o >= 0) and (TyRichCellVMerge(nc.Row, o) = Ord(rcmContinue)) then
            begin
              AArea.LastPara := nl;
              changed := True;
            end;
          end;
        end;
      end;
      k := l + 1;
    end;
  until not changed;
end;

function TyRichRowParas(ADoc: TTyRichDocument; APara: Integer; out AFirst, ALast: Integer): Boolean;
var
  c, d: TTyRichCell;
  last: Integer;
begin
  AFirst := -1;
  ALast := -1;
  ADoc.BeginRead;
  try
    c := ADoc.CellAt(APara);
    if c = nil then Exit(False);
    AFirst := APara;
    while AFirst > 0 do
    begin
      d := ADoc.CellAt(AFirst - 1);
      if (d = nil) or (d.Row <> c.Row) then Break;
      Dec(AFirst);
    end;
    ALast := APara;
    last := ADoc.Text.ParaCount - 1;
    while ALast < last do
    begin
      d := ADoc.CellAt(ALast + 1);
      if (d = nil) or (d.Row <> c.Row) then Break;
      Inc(ALast);
    end;
    Result := True;
  finally
    ADoc.EndRead;
  end;
end;

function TyRichCellParasOf(ADoc: TTyRichDocument; APara: Integer; out AFirst, ALast: Integer): Boolean;
var
  c: TTyRichCell;
  last: Integer;
begin
  AFirst := -1;
  ALast := -1;
  ADoc.BeginRead;
  try
    c := ADoc.CellAt(APara);
    if c = nil then Exit(False);
    AFirst := APara;
    while (AFirst > 0) and (ADoc.CellAt(AFirst - 1) = c) do Dec(AFirst);
    ALast := APara;
    last := ADoc.Text.ParaCount - 1;
    while (ALast < last) and (ADoc.CellAt(ALast + 1) = c) do Inc(ALast);
    Result := True;
  finally
    ADoc.EndRead;
  end;
end;

function TyRichCellInArea(const AArea: TTyRichCellArea; ARow: TTyRichRow; ACell: Integer): Boolean;
var
  l, r: Int64;
begin
  if not AArea.Range.InTable then Exit(False);
  if AArea.AllCells then Exit(True);
  TyRichCellExtent(ARow, ACell, l, r);
  // (an empty cell - no width - is in when its place is)
  if r <= l then Result := (l >= AArea.X0) and (l < AArea.X1)
  else Result := (l < AArea.X1) and (r > AArea.X0);
end;

{ Every character of AFrom .. ATo - 1 is a zero-width mark: a bookmark's or a field's (none:
  True). Call it inside a read scope. }
function MarksOnly(ADoc: TTyRichDocument; AFrom, ATo: TTyRichPos): Boolean;
var
  p: TTyRichPos;
  o: TTyRichObject;
begin
  for p := AFrom to ATo - 1 do
  begin
    o := ADoc.ObjectAt(p);
    if not ((o is TTyRichBookmarkMark) or (o is TTyRichFieldMark)) then Exit(False);
  end;
  Result := True;
end;

function TyRichCellArea(ADoc: TTyRichDocument; AAnchor, ACaret: TTyRichPos): TTyRichCellArea;
var
  t: TTyRichText;
  s, e: TTyRichPos;
  ka, kb, f, l, k, ra, rb, n, last: Integer;
  ca, cb, c: TTyRichCell;
  al, ar, bl, br: Int64;
  wholeRows: Boolean;
begin
  Result := Default(TTyRichCellArea);
  Result.FirstPara := -1;
  Result.LastPara := -1;
  if AAnchor = ACaret then Exit;
  t := ADoc.Text;
  if AAnchor < ACaret then
  begin
    s := AAnchor;
    e := ACaret;
  end
  else
  begin
    s := ACaret;
    e := AAnchor;
  end;
  if (s < 0) or (e > t.Length) then Exit;
  wholeRows := False;
  ADoc.BeginRead;
  try
    { Zero-width marks (a bookmark's, a field's) at the start of the paragraph the selection
      ends in are none of its characters: a place set after a bookmark's closing mark at a
      cell's start rests after it, and the selection still ends with the cell before. }
    kb := t.ParaOfPos(e - 1);
    if (t.ParaStart(kb) > s) and (t.ParaStart(kb) < e) and MarksOnly(ADoc, t.ParaStart(kb), e) then
      e := t.ParaStart(kb);
    // the paragraphs of the first and the last selected character (a paragraph's end mark is
    // its last character)
    ka := t.ParaOfPos(s);
    kb := t.ParaOfPos(e - 1);
    ca := ADoc.CellAt(ka);
    cb := ADoc.CellAt(kb);
    if (ca = nil) and (cb = nil) then Exit;
    if (ca <> nil) and (ca = cb) then
    begin
      { one cell: whole from its first character to its end mark, or text inside it - the
        zero-width marks at its start (a bookmark's, a field's) decide nothing: a place set at
        a bookmark's start rests after its opening mark }
      if not TyRichCellParasOf(ADoc, ka, f, l) then Exit;
      if (s < t.ParaStart(f)) or not MarksOnly(ADoc, t.ParaStart(f), s) or
         (e - 1 <> t.ParaStart(l) + t.ParaLength(l)) then
        Exit;
      Result.Range.InTable := True;
      Result.Table := ca.Table;
      TyRichCellExtent(ca.Row, ca.Index, Result.X0, Result.X1);
      Result.Range.Col0 := ca.Index;
      Result.Range.Col1 := ca.Index;
      ADoc.TableRowIndex(ka, ra, n);
      Result.Range.Row0 := ra;
      Result.Range.Row1 := ra;
      // (the area's paragraphs are its rows', as for a rectangle)
      TyRichRowParas(ADoc, ka, f, l);
      Result.FirstPara := f;
      Result.LastPara := l;
      // (a merged cell: the rows it takes)
      GrowOverSpans(ADoc, Result);
      Result.Range.TablePos := t.ParaStart(Result.FirstPara);
      if Result.FirstPara <> f then
      begin
        ADoc.TableRowIndex(Result.FirstPara, ra, n);
        Result.Range.Row0 := ra;
      end;
      if Result.LastPara <> l then
      begin
        ADoc.TableRowIndex(Result.LastPara, ra, n);
        Result.Range.Row1 := ra;
      end;
      Result.Range.WholeTable := (n = 1) and (ca.Row.CellCount = 1);
      Exit;
    end;
    if (ca <> nil) and (cb <> nil) then
    begin
      // two cells: of one table, the rectangle between them
      if ca.Table <> cb.Table then Exit;
      Result.Table := ca.Table;
      TyRichRowParas(ADoc, ka, Result.FirstPara, l);
      TyRichRowParas(ADoc, kb, f, Result.LastPara);
      TyRichCellExtent(ca.Row, ca.Index, al, ar);
      TyRichCellExtent(cb.Row, cb.Index, bl, br);
      if al < bl then Result.X0 := al else Result.X0 := bl;
      if ar > br then Result.X1 := ar else Result.X1 := br;
      if ca.Index < cb.Index then
      begin
        Result.Range.Col0 := ca.Index;
        Result.Range.Col1 := cb.Index;
      end
      else
      begin
        Result.Range.Col0 := cb.Index;
        Result.Range.Col1 := ca.Index;
      end;
    end
    else
    begin
      // one end outside the table: every cell of the rows the selection touches
      wholeRows := True;
      Result.AllCells := True;
      Result.Outside := True;
      if ca = nil then
      begin
        // from before the table: its first paragraph is the first of the table after ka
        Result.Table := cb.Table;
        k := ka + 1;
        while (k < kb) and not ((ADoc.CellAt(k) <> nil) and (ADoc.CellAt(k).Table = cb.Table)) do Inc(k);
        Result.FirstPara := k;
        TyRichRowParas(ADoc, kb, f, Result.LastPara);
      end
      else
      begin
        // to after it: its last paragraph is the last of the table before kb
        Result.Table := ca.Table;
        TyRichRowParas(ADoc, ka, Result.FirstPara, l);
        k := l;
        last := t.ParaCount - 1;
        while k < Min(kb, last) do
        begin
          c := ADoc.CellAt(k + 1);
          if (c = nil) or (c.Table <> ca.Table) then Break;
          Inc(k);
        end;
        Result.LastPara := k;
      end;
      Result.Range.Col0 := 0;
      c := ADoc.CellAt(Result.FirstPara);
      Result.Range.Col1 := c.Row.CellCount - 1;
    end;
    Result.Range.InTable := True;
    // (a rectangle that touches a merged cell: grown to hold it whole)
    GrowOverSpans(ADoc, Result);
    Result.Range.TablePos := t.ParaStart(Result.FirstPara);
    ADoc.TableRowIndex(Result.FirstPara, ra, n);
    ADoc.TableRowIndex(Result.LastPara, rb, n);
    Result.Range.Row0 := ra;
    Result.Range.Row1 := rb;
    // the whole table: its first row to its last, and every cell of them
    if (ra = 0) and (rb = n - 1) then
    begin
      if wholeRows then
        Result.Range.WholeTable := True
      else
      begin
        c := ADoc.CellAt(Result.FirstPara);
        TyRichCellExtent(c.Row, 0, al, ar);
        TyRichCellExtent(c.Row, c.Row.CellCount - 1, bl, br);
        Result.Range.WholeTable := (Result.X0 <= al) and (Result.X1 >= br);
        c := ADoc.CellAt(Result.LastPara);
        TyRichCellExtent(c.Row, 0, al, ar);
        TyRichCellExtent(c.Row, c.Row.CellCount - 1, bl, br);
        Result.Range.WholeTable := Result.Range.WholeTable and (Result.X0 <= al) and (Result.X1 >= br);
      end;
    end;
  finally
    ADoc.EndRead;
  end;
end;

end.
