unit tyControls.GridPanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Painter, tyControls.Base, tyControls.Panel;
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
  { TTyGridPanel — a fixed grid-of-cells layout container.

    Subclasses TTyPanel (reuses the 'TyPanel' typeKey; NO new .tycss). It hosts arbitrary
    child controls; each assigned child is placed into the union rectangle of the grid
    cells it spans (col, row, colspan, rowspan), inset on every side by Spacing.

    Track sizing (per column / per row) is one of absolute px, percent-of-total, or
    star/auto (equal share of the leftover). Set a track via SetColumnStyle / SetRowStyle;
    change the grid shape via ColumnCount / RowCount. A child is placed with
    SetCell(AControl, col, row, colspan, rowspan) — its assignment is stored KEYED BY the
    control in an internal list; FreeNotification drops a freed child's assignment.

    Relayout (the pure solver TyGridTrackSizes + TyGridCellRect over every assigned child)
    runs on Resize, on SetCell, and whenever the tracks / counts / spacing change. }
  TTyGridPanel = class(TTyPanel)
  private
    FColumns: TTyGridTracks;
    FRows: TTyGridTracks;
    FSpacing: Integer;
    FInLayout: Boolean;
    { Per-child cell assignment, keyed by the control. Parallel arrays kept in lockstep;
      FCellCtl[i] is the child, FCellCol/Row/ColSpan/RowSpan[i] its placement. A control
      is tracked by FreeNotification so a freed child drops its slot. }
    FCellCtl: array of TControl;
    FCellCol: array of Integer;
    FCellRow: array of Integer;
    FCellColSpan: array of Integer;
    FCellRowSpan: array of Integer;
    FCellCount: Integer;
    procedure SetColumnCount(AValue: Integer);
    procedure SetRowCount(AValue: Integer);
    procedure SetSpacing(AValue: Integer);
    function GetColumnCount: Integer;
    function GetRowCount: Integer;
    function IndexOfCell(AControl: TControl): Integer;
    procedure DropCell(AIndex: Integer);
    procedure Relayout;
  protected
    { NOTE: GetStyleTypeKey is INHERITED from TTyPanel ('TyPanel') — no new .tycss. }
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    { --- Track sizing ------------------------------------------------------------- }
    { Set the sizing of column / row AIndex. AIndex out of range grows the track array
      (padding new tracks as tgtStar) so a caller can size a not-yet-declared track;
      to change the count explicitly use ColumnCount / RowCount. Triggers a relayout. }
    procedure SetColumnStyle(AIndex: Integer; AKind: TTyGridTrackKind; AValue: Integer = 0);
    procedure SetRowStyle(AIndex: Integer; AKind: TTyGridTrackKind; AValue: Integer = 0);
    { Read back a track's sizing; an out-of-range index returns a tgtStar/0 default. }
    function ColumnStyle(AIndex: Integer): TTyGridTrack;
    function RowStyle(AIndex: Integer): TTyGridTrack;
    { --- Cell assignment (code-first API) ---------------------------------------- }
    { Place AControl (must be a child — Parent = Self) into the cell at (ACol, ARow),
      spanning AColSpan columns and ARowSpan rows. Re-calling for the same control
      updates its placement. Spans below 1 clamp to 1. Triggers a relayout. }
    procedure SetCell(AControl: TControl; ACol, ARow: Integer;
      AColSpan: Integer = 1; ARowSpan: Integer = 1);
    { Remove AControl's cell assignment (it is left where it is, no longer laid out).
      No-op if the control was never assigned. }
    procedure RemoveCell(AControl: TControl);
    { True (and fills the out params) when AControl has a cell assignment. For tests. }
    function GetCell(AControl: TControl; out ACol, ARow, AColSpan, ARowSpan: Integer): Boolean;
    { Number of assigned children. Exposed for tests. }
    function CellCount: Integer;
  published
    { The grid dimensions. Growing pads new tracks as tgtStar; shrinking drops the tail.
      A cell assignment outside the new bounds simply resolves to an empty rect. }
    property ColumnCount: Integer read GetColumnCount write SetColumnCount default 2;
    property RowCount: Integer read GetRowCount write SetRowCount default 2;
    { The margin (logical px) inset on every side of a child within its spanned cell rect,
      and thus also the gutter between adjacent cells. Negative clamps to 0. }
    property Spacing: Integer read FSpacing write SetSpacing default 4;
    property Caption;
    property Alignment;
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

{ --- Pure functions -------------------------------------------------------------- }

function TyGridTrackSizes(ATotal, ASpacing: Integer; const ATracks: TTyGridTracks): TTyGridIntArray;
var
  i, n, usable, gutters, used, starCount, starLast: Integer;
  pool, per, given: Integer;
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
  starCount := 0;
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
          Inc(starCount);
          starLast := i;
        end;
    end;
  end;

  // Pass 3: split the leftover equally among the star tracks; last star gets the remainder.
  pool := usable - used;
  if pool < 0 then pool := 0;
  if starCount > 0 then
  begin
    per := pool div starCount;
    given := 0;
    for i := 0 to n - 1 do
      if ATracks[i].Kind = tgtStar then
      begin
        if i = starLast then
          Result[i] := pool - given   // absorb the rounding remainder
        else
        begin
          Result[i] := per;
          Inc(given, per);
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
begin
  inherited Create(AOwner);
  // csAcceptsControls is set by TTyPanel; keep it — this is a real container.
  FSpacing := 4;
  FCellCount := 0;
  // Default 2x2, all-star grid.
  SetLength(FColumns, 2);
  FColumns[0].Kind := tgtStar; FColumns[0].Value := 0;
  FColumns[1].Kind := tgtStar; FColumns[1].Value := 0;
  SetLength(FRows, 2);
  FRows[0].Kind := tgtStar; FRows[0].Value := 0;
  FRows[1].Kind := tgtStar; FRows[1].Value := 0;
  Width := 200;
  Height := 150;
end;

function TTyGridPanel.GetColumnCount: Integer;
begin
  Result := Length(FColumns);
end;

function TTyGridPanel.GetRowCount: Integer;
begin
  Result := Length(FRows);
end;

procedure TTyGridPanel.SetColumnCount(AValue: Integer);
var
  old, i: Integer;
begin
  if AValue < 0 then AValue := 0;
  old := Length(FColumns);
  if old = AValue then Exit;
  SetLength(FColumns, AValue);
  for i := old to AValue - 1 do   // pad new tracks as star
  begin
    FColumns[i].Kind := tgtStar;
    FColumns[i].Value := 0;
  end;
  Relayout;
end;

procedure TTyGridPanel.SetRowCount(AValue: Integer);
var
  old, i: Integer;
begin
  if AValue < 0 then AValue := 0;
  old := Length(FRows);
  if old = AValue then Exit;
  SetLength(FRows, AValue);
  for i := old to AValue - 1 do
  begin
    FRows[i].Kind := tgtStar;
    FRows[i].Value := 0;
  end;
  Relayout;
end;

procedure TTyGridPanel.SetSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSpacing = AValue then Exit;
  FSpacing := AValue;
  Relayout;
end;

procedure TTyGridPanel.SetColumnStyle(AIndex: Integer; AKind: TTyGridTrackKind; AValue: Integer);
var
  i, old: Integer;
begin
  if AIndex < 0 then Exit;
  if AIndex >= Length(FColumns) then
  begin
    old := Length(FColumns);
    SetLength(FColumns, AIndex + 1);
    for i := old to AIndex - 1 do   // pad the gap with star tracks
    begin
      FColumns[i].Kind := tgtStar;
      FColumns[i].Value := 0;
    end;
  end;
  FColumns[AIndex].Kind := AKind;
  FColumns[AIndex].Value := AValue;
  Relayout;
end;

procedure TTyGridPanel.SetRowStyle(AIndex: Integer; AKind: TTyGridTrackKind; AValue: Integer);
var
  i, old: Integer;
begin
  if AIndex < 0 then Exit;
  if AIndex >= Length(FRows) then
  begin
    old := Length(FRows);
    SetLength(FRows, AIndex + 1);
    for i := old to AIndex - 1 do
    begin
      FRows[i].Kind := tgtStar;
      FRows[i].Value := 0;
    end;
  end;
  FRows[AIndex].Kind := AKind;
  FRows[AIndex].Value := AValue;
  Relayout;
end;

function TTyGridPanel.ColumnStyle(AIndex: Integer): TTyGridTrack;
begin
  if (AIndex >= 0) and (AIndex < Length(FColumns)) then
    Result := FColumns[AIndex]
  else
  begin
    Result.Kind := tgtStar;
    Result.Value := 0;
  end;
end;

function TTyGridPanel.RowStyle(AIndex: Integer): TTyGridTrack;
begin
  if (AIndex >= 0) and (AIndex < Length(FRows)) then
    Result := FRows[AIndex]
  else
  begin
    Result.Kind := tgtStar;
    Result.Value := 0;
  end;
end;

function TTyGridPanel.IndexOfCell(AControl: TControl): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FCellCount - 1 do
    if FCellCtl[i] = AControl then Exit(i);
end;

procedure TTyGridPanel.DropCell(AIndex: Integer);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= FCellCount) then Exit;
  // Compact the parallel arrays (order does not matter for layout).
  for i := AIndex to FCellCount - 2 do
  begin
    FCellCtl[i] := FCellCtl[i + 1];
    FCellCol[i] := FCellCol[i + 1];
    FCellRow[i] := FCellRow[i + 1];
    FCellColSpan[i] := FCellColSpan[i + 1];
    FCellRowSpan[i] := FCellRowSpan[i + 1];
  end;
  Dec(FCellCount);
end;

procedure TTyGridPanel.SetCell(AControl: TControl; ACol, ARow: Integer;
  AColSpan: Integer; ARowSpan: Integer);
var
  idx, cap: Integer;
begin
  if AControl = nil then Exit;
  if AColSpan < 1 then AColSpan := 1;
  if ARowSpan < 1 then ARowSpan := 1;
  idx := IndexOfCell(AControl);
  if idx < 0 then
  begin
    // Append a new slot; grow the parallel arrays if needed.
    cap := Length(FCellCtl);
    if FCellCount >= cap then
    begin
      if cap = 0 then cap := 4 else cap := cap * 2;
      SetLength(FCellCtl, cap);
      SetLength(FCellCol, cap);
      SetLength(FCellRow, cap);
      SetLength(FCellColSpan, cap);
      SetLength(FCellRowSpan, cap);
    end;
    idx := FCellCount;
    Inc(FCellCount);
    FCellCtl[idx] := AControl;
    // Track the control so a free drops its assignment (safe if already notified).
    AControl.FreeNotification(Self);
  end;
  FCellCol[idx] := ACol;
  FCellRow[idx] := ARow;
  FCellColSpan[idx] := AColSpan;
  FCellRowSpan[idx] := ARowSpan;
  Relayout;
end;

procedure TTyGridPanel.RemoveCell(AControl: TControl);
var
  idx: Integer;
begin
  idx := IndexOfCell(AControl);
  if idx < 0 then Exit;
  DropCell(idx);
  if AControl <> nil then AControl.RemoveFreeNotification(Self);
  Relayout;
end;

function TTyGridPanel.GetCell(AControl: TControl;
  out ACol, ARow, AColSpan, ARowSpan: Integer): Boolean;
var
  idx: Integer;
begin
  ACol := 0; ARow := 0; AColSpan := 0; ARowSpan := 0;
  idx := IndexOfCell(AControl);
  Result := idx >= 0;
  if Result then
  begin
    ACol := FCellCol[idx];
    ARow := FCellRow[idx];
    AColSpan := FCellColSpan[idx];
    ARowSpan := FCellRowSpan[idx];
  end;
end;

function TTyGridPanel.CellCount: Integer;
begin
  Result := FCellCount;
end;

procedure TTyGridPanel.Notification(AComponent: TComponent; Operation: TOperation);
var
  idx: Integer;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) then
  begin
    // A freed / re-parented tracked child must drop its cell assignment (no dangling key).
    idx := IndexOfCell(TControl(AComponent));
    if idx >= 0 then DropCell(idx);
  end;
end;

procedure TTyGridPanel.Relayout;
var
  cr: TRect;
  colW, rowH, colX, rowY: TTyGridIntArray;
  i: Integer;
  cellR: TRect;
  child: TControl;
begin
  if csDestroying in ComponentState then Exit;
  if FInLayout then Exit;
  FInLayout := True;
  try
    cr := ClientRect;
    // Resolve both axes over the client area.
    colW := TyGridTrackSizes(cr.Right - cr.Left, FSpacing, FColumns);
    rowH := TyGridTrackSizes(cr.Bottom - cr.Top, FSpacing, FRows);
    colX := TyGridTrackOrigins(colW, FSpacing);
    rowY := TyGridTrackOrigins(rowH, FSpacing);

    for i := 0 to FCellCount - 1 do
    begin
      child := FCellCtl[i];
      if child = nil then Continue;
      if child.Parent <> Self then Continue;   // only lay out our own children
      cellR := TyGridCellRect(colX, colW, rowY, rowH,
        FCellCol[i], FCellRow[i], FCellColSpan[i], FCellRowSpan[i]);
      // Inset by Spacing on every side (also produces the gutter look between cells).
      // Fold in the client-rect origin (cr.Left/Top may be non-zero on a bordered panel).
      InflateRect(cellR, -FSpacing, -FSpacing);
      OffsetRect(cellR, cr.Left, cr.Top);
      if cellR.Right < cellR.Left then cellR.Right := cellR.Left;
      if cellR.Bottom < cellR.Top then cellR.Bottom := cellR.Top;
      child.SetBounds(cellR.Left, cellR.Top,
        cellR.Right - cellR.Left, cellR.Bottom - cellR.Top);
    end;
  finally
    FInLayout := False;
  end;
  Invalidate;
end;

procedure TTyGridPanel.Resize;
begin
  inherited Resize;
  Relayout;
end;

end.
