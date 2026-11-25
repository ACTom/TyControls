unit tyControls.RichEdit.Grid;

{ A table as a grid. Its columns are the union of every cell's edges (positions in twips;
  edges within CRichEdgeSlackTwips of each other are one); a cell covers one or more of
  those columns and one or more rows. A file says the same thing two ways and both read as
  this one: merge marks (\clmgf / \clmrg across, \clvmgf / \clvmrg down) and one wide cell
  (what Word writes for cells merged across). A cell that continues a vertical merge is a
  cell of its row's text (Word keeps an empty one there) and COVERED: the place is the cell
  above's. So is a cell that continues a merge across (\clmrg): its place is the first's.

  The grid is made on demand, by a walk of the table's rows (linear in them); nothing that
  runs for a key, a caret's move or a paint makes it - those go by the rows around the caret
  (TyRichGridBuildCount counts the grids made, for the tests that hold them to none). }

{$mode objfpc}{$H+}

interface

uses
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.RowFormat;

type
  { A cell of a table's grid. Row: the row it starts in; Col: the grid column it starts at;
    RowSpan, ColSpan: the rows and the grid columns it covers (ColSpan 0: a cell of no
    width, at no place); Cell: its index among its row's cells (-1: a place where no cell is -
    a row shorter than the grid). Asked for a place (TTyRichGrid.Cell) or for a covered cell
    (CellOf): Covered True, and the fields are those of the cell that covers it; CoveredCell
    is then the place's own cell in its row's text (-1: none - the place is inside a wide
    cell). }
  TTyRichGridCell = record
    Row, Col, RowSpan, ColSpan: Integer;
    Cell: Integer;
    Covered: Boolean;
    CoveredCell: Integer;
  end;

  TTyRichGrid = class
  private
    FEdges: array of Integer;
    FRowCount, FColCount: Integer;
    // the cells that start somewhere (each place's owner is one of them)
    FStarts: array of TTyRichGridCell;
    FStartCount: Integer;
    // per place (row * FColCount + col): its owner in FStarts (-1 none), its own cell there
    FOwner, FOwn: array of Integer;
    // per row: where its cells' entries begin in FCellCol, and per cell its first grid column
    FRowCells: array of Integer;
    FCellCol, FCellCols: array of Integer;
    function ColAt(ATwips: Integer): Integer;
    function AddStart(ARow, ACol, AColSpan, ACell: Integer): Integer;
  public
    { The grid's columns. }
    function ColCount: Integer;
    property RowCount: Integer read FRowCount;
    { The grid's edges in twips: AIndex 0 the left of its first column, ColCount the right of
      its last. }
    function Edge(AIndex: Integer): Integer;
    function ColWidth(ACol: Integer): Integer;
    { The cell at the place (ARow, ACol). }
    function Cell(ARow, ACol: Integer): TTyRichGridCell;
    { Cell ACellIndex of row ARow (its index among the row's cells), as the grid has it. }
    function CellOf(ARow, ACellIndex: Integer): TTyRichGridCell;
    function CellCountOfRow(ARow: Integer): Integer;
    { Every place is the place of one cell at most, every cell's places a rectangle: a check
      for tests (True: consistent). }
    function Consistent: Boolean;
  end;

{ The grid of these rows (a table's, in order). The caller frees it. }
function TyRichBuildGrid(const ARows: TTyRichRowList): TTyRichGrid;
{ The grid of the table APos is in (nil in no table). One walk of the table's rows. }
function TyRichTableGrid(ADoc: TTyRichDocument; APos: TTyRichPos): TTyRichGrid;
{ How many grids were made since the program started. }
function TyRichGridBuildCount: Int64;

{ A row's cell ACell as a vertical merge has it: rcmFirst, rcmContinue or rcmNone (also for
  a cell the row's format does not have). }
function TyRichCellVMerge(ARow: TTyRichRow; ACell: Integer): TTyRowCellMerge;
{ ... and across: rcmNone, rcmFirst, or rcmContinue (it continues the cell before). }
function TyRichCellHMerge(ARow: TTyRichRow; ACell: Integer): TTyRowCellMerge;
{ Cell ACell of row ARow continues the cell above it (row AAbove, the row before it in the
  table; nil: none) - the grid's rule, with no grid made: it is marked to continue a merge
  down (rcmContinue), and AAbove has a cell at its extent - its left and right edges within
  the slack (CRichEdgeSlackTwips), a cell merged across in marks taken at the extent of its
  marks on either side. A cell marked so at another width, or under nothing, is a cell of
  its own. A cell that continues a merge across in marks (rcmContinue across) goes where the
  first of its marks goes: that one is asked. No grid is made and nothing is allocated. }
function TyRichCellContinuesAbove(AAbove, ARow: TTyRichRow; ACell: Integer): Boolean;

implementation

uses
  SysUtils, tyControls.RichEdit.TableProps;

var
  GBuilds: Int64 = 0;

function TyRichGridBuildCount: Int64;
begin
  Result := GBuilds;
end;

function TyRichCellVMerge(ARow: TTyRichRow; ACell: Integer): TTyRowCellMerge;
var
  f: TTyRichRowFormat;
begin
  Result := rcmNone;
  f := ARow.Format;
  if (ACell < 0) or (ACell >= f.CellCount) then Exit;
  Result := f.Cells[ACell].VMerge;
end;

function TyRichCellHMerge(ARow: TTyRichRow; ACell: Integer): TTyRowCellMerge;
var
  f: TTyRichRowFormat;
begin
  Result := rcmNone;
  f := ARow.Format;
  if (ACell < 0) or (ACell >= f.CellCount) then Exit;
  Result := f.Cells[ACell].HMerge;
end;

// the extent of cell ACell of ARow (twips), over the cells its across-merge marks take on
procedure MarkedExtent(ARow: TTyRichRow; ACell: Integer; out ALeft, ARight: Integer);
var
  e: TTyRichEdges;
  m: Integer;
begin
  e := ARow.CellEdges;
  if ACell = 0 then ALeft := ARow.Format.Row.LeftTwips else ALeft := e[ACell - 1];
  ARight := e[ACell];
  if TyRichCellHMerge(ARow, ACell) <> rcmFirst then Exit;
  m := ACell + 1;
  while (m <= High(e)) and (TyRichCellHMerge(ARow, m) = rcmContinue) do
  begin
    if e[m] > ARight then ARight := e[m];
    Inc(m);
  end;
end;

function TyRichCellContinuesAbove(AAbove, ARow: TTyRichRow; ACell: Integer): Boolean;
var
  e: TTyRichEdges;
  l, r, al, ar, j: Integer;
begin
  Result := False;
  if (AAbove = nil) or (ARow = nil) then Exit;
  e := ARow.CellEdges;
  if (ACell < 0) or (ACell > High(e)) then Exit;
  // (a cell merged across in marks: the first of its marks)
  while (ACell > 0) and (TyRichCellHMerge(ARow, ACell) = rcmContinue) do Dec(ACell);
  if TyRichCellVMerge(ARow, ACell) <> rcmContinue then Exit;
  MarkedExtent(ARow, ACell, l, r);
  e := AAbove.CellEdges;
  for j := 0 to High(e) do
  begin
    if TyRichCellHMerge(AAbove, j) = rcmContinue then Continue;
    MarkedExtent(AAbove, j, al, ar);
    if (Abs(al - l) <= CRichEdgeSlackTwips) and (Abs(ar - r) <= CRichEdgeSlackTwips) then Exit(True);
    if al > l + CRichEdgeSlackTwips then Exit;
  end;
end;

procedure SortInts(var A: array of Integer; ALo, AHi: Integer);
var
  i, j, p, t: Integer;
begin
  while ALo < AHi do
  begin
    i := ALo;
    j := AHi;
    p := A[(ALo + AHi) div 2];
    repeat
      while A[i] < p do Inc(i);
      while A[j] > p do Dec(j);
      if i <= j then
      begin
        t := A[i];
        A[i] := A[j];
        A[j] := t;
        Inc(i);
        Dec(j);
      end;
    until i > j;
    if j - ALo < AHi - i then
    begin
      if ALo < j then SortInts(A, ALo, j);
      ALo := i;
    end
    else
    begin
      if i < AHi then SortInts(A, i, AHi);
      AHi := j;
    end;
  end;
end;

function Math_Max0(A: Integer): Integer; inline;
begin
  if A < 0 then Result := 0 else Result := A;
end;

{ ---- TTyRichGrid ---- }

function TTyRichGrid.ColCount: Integer;
begin
  Result := FColCount;
end;

function TTyRichGrid.Edge(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > High(FEdges)) then Exit(0);
  Result := FEdges[AIndex];
end;

function TTyRichGrid.ColWidth(ACol: Integer): Integer;
begin
  if (ACol < 0) or (ACol >= FColCount) then Exit(0);
  Result := FEdges[ACol + 1] - FEdges[ACol];
end;

// the edge nearest ATwips
function TTyRichGrid.ColAt(ATwips: Integer): Integer;
var
  lo, hi, m: Integer;
begin
  lo := 0;
  hi := High(FEdges);
  if hi < 0 then Exit(0);
  while lo < hi do
  begin
    m := (lo + hi) div 2;
    if FEdges[m] + CRichEdgeSlackTwips < ATwips then lo := m + 1 else hi := m;
  end;
  Result := lo;
end;

function TTyRichGrid.AddStart(ARow, ACol, AColSpan, ACell: Integer): Integer;
begin
  if FStartCount = Length(FStarts) then SetLength(FStarts, FStartCount * 2 + 16);
  Result := FStartCount;
  Inc(FStartCount);
  FStarts[Result].Row := ARow;
  FStarts[Result].Col := ACol;
  FStarts[Result].RowSpan := 1;
  FStarts[Result].ColSpan := AColSpan;
  FStarts[Result].Cell := ACell;
  FStarts[Result].Covered := False;
  FStarts[Result].CoveredCell := -1;
end;

function TTyRichGrid.Cell(ARow, ACol: Integer): TTyRichGridCell;
var
  s: Integer;
begin
  Result := Default(TTyRichGridCell);
  Result.Row := ARow;
  Result.Col := ACol;
  Result.RowSpan := 1;
  Result.ColSpan := 1;
  Result.Cell := -1;
  Result.CoveredCell := -1;
  if (ARow < 0) or (ARow >= FRowCount) or (ACol < 0) or (ACol >= FColCount) then Exit;
  s := FOwner[ARow * FColCount + ACol];
  if s < 0 then Exit;
  Result := FStarts[s];
  Result.Covered := (Result.Row <> ARow) or (Result.Col <> ACol);
  if Result.Covered then Result.CoveredCell := FOwn[ARow * FColCount + ACol];
end;

function TTyRichGrid.CellCountOfRow(ARow: Integer): Integer;
begin
  if (ARow < 0) or (ARow >= FRowCount) then Exit(0);
  Result := FRowCells[ARow + 1] - FRowCells[ARow];
end;

function TTyRichGrid.CellOf(ARow, ACellIndex: Integer): TTyRichGridCell;
var
  c, n: Integer;
begin
  Result := Default(TTyRichGridCell);
  Result.Row := ARow;
  Result.Cell := ACellIndex;
  Result.CoveredCell := -1;
  if (ACellIndex < 0) or (ACellIndex >= CellCountOfRow(ARow)) then Exit;
  c := FCellCol[FRowCells[ARow] + ACellIndex];
  n := FCellCols[FRowCells[ARow] + ACellIndex];
  if (c < 0) or (n <= 0) then
  begin
    // a cell of no width: at no place
    Result.Col := Math_Max0(c);
    Result.RowSpan := 1;
    Result.ColSpan := 0;
    Exit;
  end;
  Result := Cell(ARow, c);
  if (Result.Row = ARow) and (Result.Cell = ACellIndex) then
  begin
    Result.Covered := False;
    Result.CoveredCell := -1;
  end
  else
  begin
    Result.Covered := True;
    Result.CoveredCell := ACellIndex;
  end;
end;

function TTyRichGrid.Consistent: Boolean;
var
  r, c, s, i, j: Integer;
  st: TTyRichGridCell;
begin
  Result := False;
  for s := 0 to FStartCount - 1 do
  begin
    st := FStarts[s];
    if st.ColSpan = 0 then Continue;
    for i := st.Row to st.Row + st.RowSpan - 1 do
      for j := st.Col to st.Col + st.ColSpan - 1 do
      begin
        if (i >= FRowCount) or (j >= FColCount) then Exit;
        if FOwner[i * FColCount + j] <> s then Exit;
      end;
  end;
  // and no place is an owner's that does not reach it
  for r := 0 to FRowCount - 1 do
    for c := 0 to FColCount - 1 do
    begin
      s := FOwner[r * FColCount + c];
      if s < 0 then Continue;
      st := FStarts[s];
      if (r < st.Row) or (r >= st.Row + st.RowSpan) or (c < st.Col) or (c >= st.Col + st.ColSpan) then
        Exit;
    end;
  Result := True;
end;

function TyRichBuildGrid(const ARows: TTyRichRowList): TTyRichGrid;
var
  g: TTyRichGrid;
  all: array of Integer;
  n, r, i, k, c0, c1, j, s, prev, left, total: Integer;
  e: TTyRichEdges;
  row: TTyRichRow;
  l, rt, up, last: Integer;
  hm, vm: TTyRowCellMerge;
  edges: array of TTyRichEdges;
  lefts: array of Integer;

  // the grid column after cell AI of row AR and the cells its across-merge marks take on
  function AcrossEnd(AR, AI, AC1: Integer): Integer;
  var
    m: Integer;
  begin
    Result := AC1;
    if TyRichCellHMerge(ARows[AR], AI) <> rcmFirst then Exit;
    m := AI + 1;
    while (m <= High(edges[AR])) and (TyRichCellHMerge(ARows[AR], m) = rcmContinue) do
    begin
      if edges[AR][m] > edges[AR][m - 1] then Result := g.ColAt(edges[AR][m]);
      Inc(m);
    end;
  end;

begin
  Inc(GBuilds);
  g := TTyRichGrid.Create;
  try
    g.FRowCount := Length(ARows);
    SetLength(edges, g.FRowCount);
    SetLength(lefts, g.FRowCount);
    // every edge of every row
    n := 0;
    all := nil;
    for r := 0 to g.FRowCount - 1 do
    begin
      edges[r] := ARows[r].CellEdges;
      lefts[r] := ARows[r].Format.Row.LeftTwips;
      Inc(n, Length(edges[r]) + 1);
    end;
    SetLength(all, n);
    k := 0;
    for r := 0 to g.FRowCount - 1 do
    begin
      all[k] := lefts[r];
      Inc(k);
      for i := 0 to High(edges[r]) do
      begin
        all[k] := edges[r][i];
        Inc(k);
      end;
    end;
    if n > 0 then SortInts(all, 0, n - 1);
    // one edge for those within the slack of the first of them
    SetLength(g.FEdges, n);
    k := 0;
    for i := 0 to n - 1 do
      if (k = 0) or (all[i] - g.FEdges[k - 1] > CRichEdgeSlackTwips) then
      begin
        g.FEdges[k] := all[i];
        Inc(k);
      end;
    SetLength(g.FEdges, k);
    g.FColCount := Math_Max0(k - 1);
    SetLength(g.FOwner, g.FRowCount * g.FColCount);
    SetLength(g.FOwn, g.FRowCount * g.FColCount);
    for i := 0 to High(g.FOwner) do
    begin
      g.FOwner[i] := -1;
      g.FOwn[i] := -1;
    end;
    SetLength(g.FRowCells, g.FRowCount + 1);
    total := 0;
    for r := 0 to g.FRowCount - 1 do
    begin
      g.FRowCells[r] := total;
      Inc(total, Length(edges[r]));
    end;
    g.FRowCells[g.FRowCount] := total;
    SetLength(g.FCellCol, total);
    SetLength(g.FCellCols, total);
    for r := 0 to g.FRowCount - 1 do
    begin
      row := ARows[r];
      e := edges[r];
      left := lefts[r];
      prev := -1;
      last := -1;
      for i := 0 to High(e) do
      begin
        if i = 0 then l := left else l := e[i - 1];
        rt := e[i];
        c0 := g.ColAt(l);
        if rt <= l then c1 := c0 else c1 := g.ColAt(rt);
        g.FCellCol[g.FRowCells[r] + i] := c0;
        g.FCellCols[g.FRowCells[r] + i] := c1 - c0;
        if c1 <= c0 then Continue;
        hm := TyRichCellHMerge(row, i);
        vm := TyRichCellVMerge(row, i);
        s := -1;
        // (the start above this cell's first column, if any)
        if r > 0 then up := g.FOwner[(r - 1) * g.FColCount + c0] else up := -1;
        if (hm = rcmContinue) and (prev >= 0) and (g.FStarts[prev].Row = r) then
        begin
          // across: the cell before reaches over this one
          s := prev;
          if c1 > g.FStarts[s].Col + g.FStarts[s].ColSpan then
            g.FStarts[s].ColSpan := c1 - g.FStarts[s].Col;
        end
        else if (hm = rcmContinue) and (last >= 0) and (g.FStarts[last].Row < r) and
          (c0 >= g.FStarts[last].Col) and (c1 <= g.FStarts[last].Col + g.FStarts[last].ColSpan) then
          // across, in a row a merge down continues into: the merge's place
          s := last
        else if (vm = rcmContinue) and (up >= 0) and (g.FStarts[up].Col = c0) and
          (g.FStarts[up].Col + g.FStarts[up].ColSpan = AcrossEnd(r, i, c1)) then
        begin
          { down: the cell above reaches into this row - only when it has this cell's extent
            (its left and right edges, within the slack; a cell merged across in marks: the
            extent of its marks); a continuation of another width, or of nothing, is a cell of
            its own (as Word shows such a file: the parts unmerged) }
          s := up;
          g.FStarts[s].RowSpan := r - g.FStarts[s].Row + 1;
        end
        else
          s := g.AddStart(r, c0, c1 - c0, i);
        for j := c0 to c1 - 1 do
          if g.FOwner[r * g.FColCount + j] < 0 then
          begin
            g.FOwner[r * g.FColCount + j] := s;
            if (g.FStarts[s].Row <> r) or (g.FStarts[s].Cell <> i) then g.FOwn[r * g.FColCount + j] := i;
          end;
        if g.FStarts[s].Row = r then prev := s else prev := -1;
        last := s;
      end;
    end;
    Result := g;
    g := nil;
  finally
    g.Free;
  end;
end;

function TyRichTableGrid(ADoc: TTyRichDocument; APos: TTyRichPos): TTyRichGrid;
var
  rows: TTyRichRowList;
  first, count: Integer;
begin
  Result := nil;
  ADoc.BeginRead;
  try
    if not ADoc.TableRowsAt(APos, 0, MaxInt, rows, first, count) then Exit;
    Result := TyRichBuildGrid(rows);
  finally
    ADoc.EndRead;
  end;
end;

end.
