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
    is what lies under the span. (A table read as a grid will redo this on its columns.)
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
  SysUtils, tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands;

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
  its right edge. }
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

implementation

uses
  Math, tyControls.RichEdit.TableProps, tyControls.RichEdit.RtfRead, tyControls.RichEdit.Bookmarks;

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
    FindRows;
    // rows the items need below the table's last
    want := 0;
    for i := 0 to High(FItems) do want := Max(want, FItems[i].Row + 1);
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
begin
  e := ARow.CellEdges;
  if (ACell < 0) or (ACell > High(e)) then
  begin
    ALeft := 0;
    ARight := 0;
    Exit;
  end;
  if ACell = 0 then ALeft := ARow.Format.Row.LeftTwips else ALeft := e[ACell - 1];
  ARight := e[ACell];
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
  // the paragraphs of the first and the last selected character (a paragraph's end mark is
  // its last character)
  ka := t.ParaOfPos(s);
  kb := t.ParaOfPos(e - 1);
  wholeRows := False;
  ADoc.BeginRead;
  try
    ca := ADoc.CellAt(ka);
    cb := ADoc.CellAt(kb);
    if (ca = nil) and (cb = nil) then Exit;
    if (ca <> nil) and (ca = cb) then
    begin
      // one cell: whole from its first character to its end mark, or text inside it
      if not TyRichCellParasOf(ADoc, ka, f, l) then Exit;
      if (s <> t.ParaStart(f)) or (e - 1 <> t.ParaStart(l) + t.ParaLength(l)) then Exit;
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
      Result.Range.TablePos := t.ParaStart(f);
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
