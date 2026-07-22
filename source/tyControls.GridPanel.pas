unit tyControls.GridPanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Painter, tyControls.Controller, tyControls.Base, tyControls.Panel;
type
  { A track (column or row) is sized in one of three ways:
      tgtAbsolute — a fixed logical-px length (Value = the px count).
      tgtPercent  — a percentage (Value = 0..100) of the ORIGINAL total minus spacing.
      tgtStar     — a "star" / auto track: shares the leftover space EQUALLY with the
                    other star tracks (Value is ignored; every star gets an equal slice,
                    the LAST star absorbs the integer-division rounding remainder). }
  TTyGridTrackKind = (tgtAbsolute, tgtPercent, tgtStar);

  TTyGridTrack = record
    Kind: TTyGridTrackKind;
    Value: Integer;   // px for tgtAbsolute; 0..100 for tgtPercent; ignored for tgtStar
  end;
  TTyGridTracks = array of TTyGridTrack;

  { Local integer-array alias (tyControls.Types has no shared one; declaring our own
    avoids a hard dependency on the per-unit TTyIntArray in Edit/Memo). }
  TTyGridIntArray = array of Integer;

type
  { TTyGridPanel — a droppable N×M grid of form-owned TTyGridCell containers.

    Subclasses TTyPanel (reuses the 'TyPanel' typeKey; NO new .tycss). Setting
    ColumnCount × RowCount materialises that many TTyGridCell child containers, each
    owned by the form and parented to the grid (mirrors TTyPageControl/TTyTabSheet);
    a control dropped into a cell is constrained (alClient) to that cell. Track sizes
    come from the published ColumnSizes/RowSizes strings (empty = all-star / equal),
    solved by the pure TyGridTrackSizes/TyGridTrackOrigins/TyGridCellRect. No spanning. }
  TTyGridCellArray = array of TObject;   // TTyGridCell; TObject avoids a cyclic uses

  TTyGridPanel = class(TTyPanel)
  private
    FCells: array of TObject;        // flat, one TTyGridCell per (col,row); index = row*Cols+col
    FColumnCount: Integer;
    FRowCount: Integer;
    FColumnSizes: string;
    FRowSizes: string;
    FSpacing: Integer;
    FInLayout: Boolean;
    FDestroying: Boolean;
    FHadStreamedCells: Boolean;      // a cell registered while csLoading -> streamed load
    procedure SetColumnCount(AValue: Integer);
    procedure SetRowCount(AValue: Integer);
    procedure SetColumnSizes(const AValue: string);
    procedure SetRowSizes(const AValue: string);
    procedure SetSpacing(AValue: Integer);
    function  GetCell(ACol, ARow: Integer): TObject;   // returns TTyGridCell or nil
    function  CellIndex(ACol, ARow: Integer): Integer;
    procedure EnsureCells;           // create/destroy cells to match Count, preserve in-bounds
    procedure DiscardProvisionalCells;  // free the constructor-seeded default cells
    procedure Relayout;
  protected
    function  GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Resize; override;
    procedure Loaded; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Public so TTyGridCell.SetParent (a different unit) can self-register. Idempotent. }
    procedure RegisterCell(ACell: TObject);
    procedure UnregisterCell(ACell: TObject; AFree: Boolean);
    function  CellCount: Integer;
    { Test/iteration accessor: the i-th registered cell (registration order), or nil. }
    function  CellAt(AIndex: Integer): TObject;
    { Cell at (col,row), or nil. Cast the result to TTyGridCell in cell-aware code. }
    property  Cells[ACol, ARow: Integer]: TObject read GetCell;
  published
    property ColumnCount: Integer read FColumnCount write SetColumnCount default 2;
    property RowCount: Integer read FRowCount write SetRowCount default 2;
    property ColumnSizes: string read FColumnSizes write SetColumnSizes;
    property RowSizes: string read FRowSizes write SetRowSizes;
    property Spacing: Integer read FSpacing write SetSpacing default 4;
  end;

{ --- Pure, headless-tested grid math --------------------------------------------- }

{ Resolve a line of tracks to concrete pixel lengths along one axis.

  ATotal   — the full axis length available (the client width or height).
  ASpacing — the gutter counted BETWEEN adjacent tracks: (n-1) gutters are subtracted
             from the available length before the tracks are sized (n = track count).
             Negative clamps to 0.
  ATracks  — the track sizing descriptors.

  Order of resolution (matching WPF/CSS grid semantics):
    1) tgtAbsolute tracks take their Value px.
    2) tgtPercent tracks take round(Value/100 * usable), where `usable` is the axis
       length minus the gutters (the ORIGINAL usable, NOT reduced by the absolute tracks).
    3) the leftover (usable minus absolute minus percent, floored at 0) is split EQUALLY
       among the tgtStar tracks; the LAST star track absorbs the integer-division remainder.

  Over-subscription (absolutes + percents exceed usable) never yields a negative track and
  never yields a negative star pool: individual lengths are clamped to >= 0. Returns an
  array of length Length(ATracks); an empty track list returns an empty array. }
function TyGridTrackSizes(ATotal, ASpacing: Integer; const ATracks: TTyGridTracks): TTyGridIntArray;

{ The union rectangle of the cells a child spans, in the SAME coordinate space as the
  passed line origins/lengths.

  AColX/AColW — per-column left origin and width (parallel arrays; length = column count).
  ARowY/ARowH — per-row top origin and height.
  ACol/ARow   — the top-left cell of the span.
  AColSpan/ARowSpan — how many columns/rows the child covers (values < 1 treated as 1).

  The span is CLAMPED to the grid (a span running off the right/bottom edge stops at the
  last track). An out-of-range ACol or ARow (or empty track lists) yields an EMPTY rect
  (Rect(0,0,0,0)). }
function TyGridCellRect(const AColX, AColW, ARowY, ARowH: TTyGridIntArray;
  ACol, ARow, AColSpan, ARowSpan: Integer): TRect;

{ Line origins (the left/top of each track) from a resolved length array + the gutter
  spacing: origin[0] = 0, origin[i] = origin[i-1] + length[i-1] + spacing. Exposed so the
  control (and tests) can turn TyGridTrackSizes output into per-track positions. }
function TyGridTrackOrigins(const ALengths: TTyGridIntArray; ASpacing: Integer): TTyGridIntArray;

{ Parse a designer track-template string into tracks. Comma-separated tokens:
  'N*' or '*' = star (N shares, default 1); 'N%' = percent; 'N' = absolute px.
  An EMPTY string yields ADefaultCount all-star tracks (equal distribution). }
function TyParseGridTracks(const ASpec: string; ADefaultCount: Integer): TTyGridTracks;

implementation

uses
  tyControls.GridCell;

{ --- Pure functions -------------------------------------------------------------- }

function TyGridTrackSizes(ATotal, ASpacing: Integer; const ATracks: TTyGridTracks): TTyGridIntArray;
var
  i, n, usable, gutters, used, starWeight, starLast: Integer;
  pool, w, given: Integer;
begin
  Result := nil;
  n := Length(ATracks);
  SetLength(Result, n);
  if n = 0 then Exit;
  if ASpacing < 0 then ASpacing := 0;

  // Usable axis length after removing the (n-1) gutters between tracks. Floored at 0.
  gutters := (n - 1) * ASpacing;
  usable := ATotal - gutters;
  if usable < 0 then usable := 0;

  // Pass 1 + 2: absolute then percent (both measured against the ORIGINAL usable).
  used := 0;
  starWeight := 0;
  starLast := -1;
  for i := 0 to n - 1 do
  begin
    case ATracks[i].Kind of
      tgtAbsolute:
        begin
          Result[i] := ATracks[i].Value;
          if Result[i] < 0 then Result[i] := 0;
          Inc(used, Result[i]);
        end;
      tgtPercent:
        begin
          // round(Value% of usable). Value clamped to [0,100].
          if ATracks[i].Value <= 0 then
            Result[i] := 0
          else if ATracks[i].Value >= 100 then
            Result[i] := usable
          else
            Result[i] := (ATracks[i].Value * usable + 50) div 100;
          if Result[i] < 0 then Result[i] := 0;
          Inc(used, Result[i]);
        end;
      tgtStar:
        begin
          Result[i] := 0;   // filled in pass 3
          // Weighted share: 'N*' has Value=N shares; '*' (Value 0/1) counts as one.
          w := ATracks[i].Value;
          if w < 1 then w := 1;
          Inc(starWeight, w);
          starLast := i;
        end;
    end;
  end;

  // Pass 3: split the leftover among the star tracks IN PROPORTION to their weight;
  // the last star absorbs the integer-division remainder so the sum is exact.
  pool := usable - used;
  if pool < 0 then pool := 0;
  if starWeight > 0 then
  begin
    given := 0;
    for i := 0 to n - 1 do
      if ATracks[i].Kind = tgtStar then
      begin
        if i = starLast then
          Result[i] := pool - given   // absorb the rounding remainder
        else
        begin
          w := ATracks[i].Value;
          if w < 1 then w := 1;
          Result[i] := (pool * w) div starWeight;
          Inc(given, Result[i]);
        end;
        if Result[i] < 0 then Result[i] := 0;
      end;
  end;
end;

function TyGridTrackOrigins(const ALengths: TTyGridIntArray; ASpacing: Integer): TTyGridIntArray;
var
  i, n, x: Integer;
begin
  Result := nil;
  n := Length(ALengths);
  SetLength(Result, n);
  if n = 0 then Exit;
  if ASpacing < 0 then ASpacing := 0;
  x := 0;
  for i := 0 to n - 1 do
  begin
    Result[i] := x;
    Inc(x, ALengths[i] + ASpacing);
  end;
end;

function TyParseGridTracks(const ASpec: string; ADefaultCount: Integer): TTyGridTracks;
var
  parts: TStringList;
  i, v, e: Integer;
  tok: string;
begin
  Result := nil;
  if Trim(ASpec) = '' then
  begin
    if ADefaultCount < 0 then ADefaultCount := 0;
    SetLength(Result, ADefaultCount);
    for i := 0 to ADefaultCount - 1 do
    begin
      Result[i].Kind := tgtStar;
      Result[i].Value := 1;
    end;
    Exit;
  end;
  parts := TStringList.Create;
  try
    parts.Delimiter := ',';
    parts.StrictDelimiter := True;
    parts.DelimitedText := ASpec;
    SetLength(Result, parts.Count);
    for i := 0 to parts.Count - 1 do
    begin
      tok := Trim(parts[i]);
      if (tok <> '') and (tok[Length(tok)] = '*') then
      begin
        Result[i].Kind := tgtStar;
        Val(Copy(tok, 1, Length(tok) - 1), v, e);
        if (e <> 0) or (v < 1) then v := 1;   // '*' alone -> 1 share
        Result[i].Value := v;
      end
      else if (tok <> '') and (tok[Length(tok)] = '%') then
      begin
        Result[i].Kind := tgtPercent;
        Val(Copy(tok, 1, Length(tok) - 1), v, e);
        if e <> 0 then v := 0;
        Result[i].Value := v;
      end
      else
      begin
        Result[i].Kind := tgtAbsolute;
        Val(tok, v, e);
        if e <> 0 then v := 0;
        Result[i].Value := v;
      end;
    end;
  finally
    parts.Free;
  end;
end;

function TyGridCellRect(const AColX, AColW, ARowY, ARowH: TTyGridIntArray;
  ACol, ARow, AColSpan, ARowSpan: Integer): TRect;
var
  nc, nr, lastCol, lastRow: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  nc := Length(AColX);
  nr := Length(ARowY);
  // Guard mismatched parallel arrays too (defensive): use the shorter of X/W and Y/H.
  if Length(AColW) < nc then nc := Length(AColW);
  if Length(ARowH) < nr then nr := Length(ARowH);
  if (nc = 0) or (nr = 0) then Exit;
  // Out-of-range top-left cell -> empty rect.
  if (ACol < 0) or (ACol >= nc) or (ARow < 0) or (ARow >= nr) then Exit;

  if AColSpan < 1 then AColSpan := 1;
  if ARowSpan < 1 then ARowSpan := 1;

  // Clamp the span to the last in-range track.
  lastCol := ACol + AColSpan - 1;
  if lastCol >= nc then lastCol := nc - 1;
  lastRow := ARow + ARowSpan - 1;
  if lastRow >= nr then lastRow := nr - 1;

  Result.Left := AColX[ACol];
  Result.Top := ARowY[ARow];
  Result.Right := AColX[lastCol] + AColW[lastCol];
  Result.Bottom := ARowY[lastRow] + ARowH[lastRow];
end;

{ TTyGridPanel }

constructor TTyGridPanel.Create(AOwner: TComponent);
var i: Integer;
begin
  inherited Create(AOwner);
  FColumnCount := 2;
  FRowCount := 2;
  FSpacing := 4;
  Width := 200;
  Height := 150;
  { Seed the default 2x2 UNCONDITIONALLY and tag the cells provisional. FPC's TReader
    sets csLoading only AFTER Create returns (reader.inc: Create at ~952, csLoading at
    ~959), so a `if not csLoading` guard here is a no-op during streaming — a streamed
    grid would seed a default AND take the streamed cells (double-create). Instead we
    always seed, then Loaded discards these provisional cells if real cells streamed in;
    a designer palette-drop / code path keeps them. }
  EnsureCells;
  for i := 0 to High(FCells) do
    TTyGridCell(FCells[i]).Provisional := True;
end;

destructor TTyGridPanel.Destroy;
begin
  FDestroying := True;
  inherited Destroy;                // cells owned by the form (or Self) freed normally
end;

function TTyGridPanel.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';              // transparent layout host; reuse the panel key
end;

procedure TTyGridPanel.SetController(AValue: TTyStyleController);
var i: Integer;
begin
  inherited SetController(AValue);
  { Re-propagate to existing cells (mirrors TTyPageControl.SetController). }
  for i := 0 to High(FCells) do
    if FCells[i] <> nil then
      TTyGridCell(FCells[i]).Controller := AValue;
end;

function TTyGridPanel.CellIndex(ACol, ARow: Integer): Integer;
var i: Integer; c: TTyGridCell;
begin
  Result := -1;
  for i := 0 to High(FCells) do
  begin
    c := TTyGridCell(FCells[i]);
    if (c <> nil) and (c.Col = ACol) and (c.Row = ARow) then Exit(i);
  end;
end;

function TTyGridPanel.GetCell(ACol, ARow: Integer): TObject;
var idx: Integer;
begin
  idx := CellIndex(ACol, ARow);
  if idx >= 0 then Result := FCells[idx] else Result := nil;
end;

function TTyGridPanel.CellCount: Integer;
begin
  Result := Length(FCells);
end;

function TTyGridPanel.CellAt(AIndex: Integer): TObject;
begin
  if (AIndex >= 0) and (AIndex <= High(FCells)) then Result := FCells[AIndex]
  else Result := nil;
end;

procedure TTyGridPanel.RegisterCell(ACell: TObject);
var i: Integer;
begin
  for i := 0 to High(FCells) do
    if FCells[i] = ACell then Exit;         // idempotent
  SetLength(FCells, Length(FCells) + 1);
  FCells[High(FCells)] := ACell;
  TTyGridCell(ACell).Controller := Self.Controller;
  { A cell registering while the GRID is csLoading is a STREAMED cell — the
    constructor's provisional seed registers with csLoading clear. Note it so Loaded
    can drop the provisional defaults in favour of the streamed cells. }
  if csLoading in ComponentState then
    FHadStreamedCells := True;
  if not (csLoading in ComponentState) then Relayout;
end;

procedure TTyGridPanel.UnregisterCell(ACell: TObject; AFree: Boolean);
var idx, j: Integer;
begin
  idx := -1;
  for j := 0 to High(FCells) do
    if FCells[j] = ACell then begin idx := j; Break; end;
  if idx < 0 then Exit;
  for j := idx to High(FCells) - 1 do FCells[j] := FCells[j + 1];
  SetLength(FCells, Length(FCells) - 1);
  if AFree and (ACell <> nil) then TTyGridCell(ACell).Free;
  if not (csDestroying in ComponentState) then Relayout;
end;

procedure TTyGridPanel.DiscardProvisionalCells;
var i: Integer; cell: TTyGridCell;
begin
  i := 0;
  while i <= High(FCells) do
  begin
    cell := TTyGridCell(FCells[i]);
    if (cell <> nil) and cell.Provisional then
      UnregisterCell(cell, True)   // frees + shrinks FCells; do not Inc(i)
    else
      Inc(i);
  end;
end;

procedure TTyGridPanel.EnsureCells;
var
  col, row: Integer;
  cell: TTyGridCell;
  cellOwner: TComponent;
  i: Integer;
  wanted: TTyGridCell;
begin
  if csLoading in ComponentState then Exit;   // Loaded reconciles instead
  if Owner <> nil then cellOwner := Owner else cellOwner := Self;
  // 1) free cells now out of bounds (col>=ColumnCount or row>=RowCount)
  i := 0;
  while i <= High(FCells) do
  begin
    cell := TTyGridCell(FCells[i]);
    if (cell = nil) or (cell.Col >= FColumnCount) or (cell.Row >= FRowCount)
       or (cell.Col < 0) or (cell.Row < 0) then
      UnregisterCell(cell, True)               // shrinks FCells; do not Inc(i)
    else
      Inc(i);
  end;
  // 2) create any missing (col,row) in bounds
  for row := 0 to FRowCount - 1 do
    for col := 0 to FColumnCount - 1 do
    begin
      wanted := TTyGridCell(GetCell(col, row));
      if wanted = nil then
      begin
        cell := TTyGridCell.Create(cellOwner);
        cell.Col := col;
        cell.Row := row;
        cell.Parent := Self;                   // SetParent -> RegisterCell
      end;
    end;
  Relayout;
end;

procedure TTyGridPanel.SetColumnCount(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FColumnCount = AValue then Exit;
  FColumnCount := AValue;
  EnsureCells;
end;

procedure TTyGridPanel.SetRowCount(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FRowCount = AValue then Exit;
  FRowCount := AValue;
  EnsureCells;
end;

procedure TTyGridPanel.SetColumnSizes(const AValue: string);
begin
  if FColumnSizes = AValue then Exit;
  FColumnSizes := AValue;
  Relayout;
end;

procedure TTyGridPanel.SetRowSizes(const AValue: string);
begin
  if FRowSizes = AValue then Exit;
  FRowSizes := AValue;
  Relayout;
end;

procedure TTyGridPanel.SetSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSpacing = AValue then Exit;
  FSpacing := AValue;
  Relayout;
end;

procedure TTyGridPanel.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyGridCell) then
    UnregisterCell(AComponent, False);        // LCL already freeing it
end;

procedure TTyGridPanel.Resize;
begin
  inherited Resize;
  Relayout;
end;

procedure TTyGridPanel.Loaded;
begin
  inherited Loaded;
  { Cells self-registered via SetParent during streaming; FCells now holds the streamed
    cells PLUS the provisional 2x2 the constructor seeded. If real cells streamed in,
    drop the provisional ones (they were only a placeholder); then reconcile against
    ColumnCount/RowCount (covers a hand-edited .lfm with no cells, where the provisional
    defaults are kept and grown/shrunk to match). }
  if FHadStreamedCells then
    DiscardProvisionalCells;
  EnsureCells;
end;

procedure TTyGridPanel.Relayout;
var
  cr: TRect;
  cols, rows: TTyGridTracks;
  colW, rowH, colX, rowY: TTyGridIntArray;
  i: Integer;
  cell: TTyGridCell;
  cellR: TRect;
begin
  if csDestroying in ComponentState then Exit;
  if csLoading in ComponentState then Exit;
  if FInLayout then Exit;
  FInLayout := True;
  try
    cr := ClientRect;
    cols := TyParseGridTracks(FColumnSizes, FColumnCount);
    rows := TyParseGridTracks(FRowSizes, FRowCount);
    colW := TyGridTrackSizes(cr.Right - cr.Left, FSpacing, cols);
    rowH := TyGridTrackSizes(cr.Bottom - cr.Top, FSpacing, rows);
    colX := TyGridTrackOrigins(colW, FSpacing);
    rowY := TyGridTrackOrigins(rowH, FSpacing);
    for i := 0 to High(FCells) do
    begin
      cell := TTyGridCell(FCells[i]);
      if cell = nil then Continue;
      if (cell.Col < 0) or (cell.Col >= Length(colW)) then Continue;
      if (cell.Row < 0) or (cell.Row >= Length(rowH)) then Continue;
      cellR := TyGridCellRect(colX, colW, rowY, rowH, cell.Col, cell.Row, 1, 1);
      OffsetRect(cellR, cr.Left, cr.Top);
      cell.SetBounds(cellR.Left, cellR.Top,
        cellR.Right - cellR.Left, cellR.Bottom - cellR.Top);
    end;
  finally
    FInLayout := False;
  end;
  Invalidate;
end;

procedure TTyGridPanel.Paint;
begin
  inherited Paint;
  // design-time grid lines added in Task 5
end;

end.
