unit tyControls.TreeView.Columns;
{$mode objfpc}{$H+}
{ Phase A — pure column model: types, position<->index map, layout/hit, auto-size/spring.
  No dependency on TTyTreeView; fully headless-testable.
  Phase B will wire TTyTreeHeader into TTyTreeView. }
interface
uses
  Classes, SysUtils, Math;

const
  NoColumn = -1;   { sentinel: "no column" / not found }

type
  { Column-level option flags (mirrors VTV's TVTColumnOption subset) }
  TTyTreeColumnOption = (
    coVisible,       { column is shown in the header and body }
    coResizable,     { the user can drag the column's right edge to resize }
    coAllowClick,    { clicking the column header fires OnHeaderClick }
    coDraggable,     { the user can drag the column to a new position }
    coAutoSpring     { column participates in spring distribution on resize }
  );
  TTyTreeColumnOptions = set of TTyTreeColumnOption;

  { Sort direction (used by TTyTreeHeader.SortDirection + SortTree) }
  TTySortDirection = (sdAscending, sdDescending);

  TTyTreeColumns = class;   { forward }

  { ===================================================================
    TTyTreeColumn — one column (TCollectionItem)
    =================================================================== }
  TTyTreeColumn = class(TCollectionItem)
  private
    FWidth:            Integer;
    FMinWidth:         Integer;
    FMaxWidth:         Integer;
    FAlignment:        TAlignment;
    FCaptionAlignment: TAlignment;
    FText:             string;
    FImageIndex:       Integer;
    FOptions:          TTyTreeColumnOptions;
    FTag:              NativeInt;
    { internal: absolute left edge set by UpdatePositions }
    FLeft:             Integer;
    { cached visual position — kept in sync by AdjustPosition }
    FPosition:         Cardinal;

    procedure SetWidth(AValue: Integer);
    procedure SetMinWidth(AValue: Integer);
    procedure SetMaxWidth(AValue: Integer);
    procedure SetPosition(AValue: Cardinal);
    procedure SetOptions(AValue: TTyTreeColumnOptions);
    procedure SetAlignment(AValue: TAlignment);
    procedure SetCaptionAlignment(AValue: TAlignment);
    procedure SetText(const AValue: string);
    procedure SetImageIndex(AValue: Integer);
    function  GetOwnerColumns: TTyTreeColumns;
    procedure NotifyOwner;
  protected
    function  GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    { Read-only public: current absolute left edge (set by UpdatePositions).
      Note: this is NOT scroll-adjusted — paint code subtracts FOffsetX itself. }
    property Left: Integer read FLeft;
  published
    property Width:            Integer              read FWidth            write SetWidth            default 100;
    property MinWidth:         Integer              read FMinWidth         write SetMinWidth         default 10;
    property MaxWidth:         Integer              read FMaxWidth         write SetMaxWidth         default 10000;
    property Position:         Cardinal             read FPosition         write SetPosition;
    property Alignment:        TAlignment           read FAlignment        write SetAlignment        default taLeftJustify;
    property CaptionAlignment: TAlignment           read FCaptionAlignment write SetCaptionAlignment default taLeftJustify;
    property Text:             string               read FText             write SetText;
    property ImageIndex:       Integer              read FImageIndex       write SetImageIndex       default -1;
    property Options:          TTyTreeColumnOptions read FOptions          write SetOptions;
    property Tag:              NativeInt            read FTag              write FTag                default 0;
  end;

  { ===================================================================
    TTyTreeColumns — ordered collection of TTyTreeColumn
    =================================================================== }
  TTyTreeColumns = class(TCollection)
  private
    { Maps visual Position (0-based) -> collection Index.
      Length always = Count.  Maintained by Add/Delete/AdjustPosition. }
    FPositionToIndex: array of Integer;
    { Notify hook: wired by Phase-B header.  May be nil in Phase-A tests. }
    FOnChange: TNotifyEvent;

    procedure RebuildPositionMap;
    procedure DoChange;
  protected
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
  public
    constructor Create;

    { Look up the column at visual position APos (0-based). }
    function  ColumnByPosition(APos: Integer): TTyTreeColumn;

    { Recompute FLeft for every visible column (left-to-right, position order). }
    procedure UpdatePositions;

    { Sum of all visible column widths (logical px). }
    function  TotalWidth: Integer;

    { Move ACol to the new visual position ANewPos, shifting others.
      Called by TTyTreeColumn.SetPosition and by drag-reorder. }
    procedure AdjustPosition(ACol: TTyTreeColumn; ANewPos: Integer);

    { Return the collection Index of the column whose on-screen span contains AX.
      AScrollOffset is the current FOffsetX (positive = scrolled right).
      Returns NoColumn when AX is beyond all visible columns. }
    function  ColumnFromPosition(AX, AScrollOffset: Integer): Integer;

    { Return the collection Index of a resizable column whose right screen-edge
      is within [right-ATolLeft, right+ATolRight] of AX, or NoColumn.
      Reverse-iterates so rightmost edge wins at overlapping boundaries. }
    function  DetermineSplitterIndex(AX, AScrollOffset: Integer;
                                     ATolLeft: Integer = 3;
                                     ATolRight: Integer = 5): Integer;

    { Set column AAutoSizeIndex.Width so that TotalWidth = AClientWidth,
      clamped to that column's [MinWidth, MaxWidth]. }
    procedure ApplyAutoSize(AClientWidth, AAutoSizeIndex: Integer);

    { Distribute ADeltaWidth across all visible coAutoSpring columns
      proportionally (integral bonus-pixel remainder so widths stay whole
      and the sum of deltas is exact). }
    procedure DistributeSpring(ADeltaWidth: Integer);

    { Notify hook wired by the header in Phase B. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

{ ---------------------------------------------------------------------------
  TTyTreeColumn
  --------------------------------------------------------------------------- }

constructor TTyTreeColumn.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FWidth            := 100;
  FMinWidth         := 10;
  FMaxWidth         := 10000;
  FAlignment        := taLeftJustify;
  FCaptionAlignment := taLeftJustify;
  FImageIndex       := -1;
  FOptions          := [coVisible, coResizable, coAllowClick, coDraggable];
  FLeft             := 0;
  FTag              := 0;
  { Position is assigned by TTyTreeColumns.Notify after the item is added. }
end;

function TTyTreeColumn.GetDisplayName: string;
begin
  if FText <> '' then
    Result := FText
  else
    Result := inherited GetDisplayName;
end;

function TTyTreeColumn.GetOwnerColumns: TTyTreeColumns;
begin
  Result := Collection as TTyTreeColumns;
end;

procedure TTyTreeColumn.NotifyOwner;
begin
  if Collection <> nil then
    GetOwnerColumns.DoChange;
end;

procedure TTyTreeColumn.SetWidth(AValue: Integer);
begin
  { Clamp to [MinWidth, MaxWidth] }
  AValue := Max(FMinWidth, Min(FMaxWidth, AValue));
  if FWidth = AValue then Exit;
  FWidth := AValue;
  if Collection <> nil then
  begin
    GetOwnerColumns.UpdatePositions;
    GetOwnerColumns.DoChange;
  end;
end;

procedure TTyTreeColumn.SetMinWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FMinWidth = AValue then Exit;
  FMinWidth := AValue;
  { Re-clamp width if needed }
  if FWidth < FMinWidth then
    SetWidth(FMinWidth);
end;

procedure TTyTreeColumn.SetMaxWidth(AValue: Integer);
begin
  if AValue < FMinWidth then AValue := FMinWidth;
  if FMaxWidth = AValue then Exit;
  FMaxWidth := AValue;
  if FWidth > FMaxWidth then
    SetWidth(FMaxWidth);
end;

procedure TTyTreeColumn.SetPosition(AValue: Cardinal);
begin
  if FPosition = AValue then Exit;
  if Collection <> nil then
    GetOwnerColumns.AdjustPosition(Self, AValue);
end;

procedure TTyTreeColumn.SetOptions(AValue: TTyTreeColumnOptions);
begin
  if FOptions = AValue then Exit;
  FOptions := AValue;
  if Collection <> nil then
  begin
    GetOwnerColumns.UpdatePositions;
    GetOwnerColumns.DoChange;
  end;
end;

procedure TTyTreeColumn.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  NotifyOwner;
end;

procedure TTyTreeColumn.SetCaptionAlignment(AValue: TAlignment);
begin
  if FCaptionAlignment = AValue then Exit;
  FCaptionAlignment := AValue;
  NotifyOwner;
end;

procedure TTyTreeColumn.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  NotifyOwner;
end;

procedure TTyTreeColumn.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  NotifyOwner;
end;

{ ---------------------------------------------------------------------------
  TTyTreeColumns
  --------------------------------------------------------------------------- }

constructor TTyTreeColumns.Create;
begin
  inherited Create(TTyTreeColumn);
  SetLength(FPositionToIndex, 0);
  FOnChange := nil;
end;

procedure TTyTreeColumns.DoChange;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTreeColumns.RebuildPositionMap;
{ Full rebuild: assign FPosition = Index for every item (natural order),
  then mirror into FPositionToIndex. }
var
  i: Integer;
begin
  SetLength(FPositionToIndex, Count);
  for i := 0 to Count - 1 do
  begin
    FPositionToIndex[i] := i;
    (Items[i] as TTyTreeColumn).FPosition := Cardinal(i);
  end;
end;

procedure TTyTreeColumns.Notify(Item: TCollectionItem;
  Action: TCollectionNotification);
var
  col: TTyTreeColumn;
  oldPos, i: Integer;
begin
  inherited Notify(Item, Action);
  col := Item as TTyTreeColumn;
  case Action of
    cnAdded:
    begin
      { Append the new column at the last visual position. }
      SetLength(FPositionToIndex, Count);
      FPositionToIndex[Count - 1] := col.Index;
      col.FPosition := Cardinal(Count - 1);
      UpdatePositions;
      DoChange;
    end;
    cnDeleting:
    begin
      { Find the visual position slot for this column and remove it. }
      oldPos := -1;
      for i := 0 to Length(FPositionToIndex) - 1 do
        if FPositionToIndex[i] = col.Index then
        begin
          oldPos := i;
          Break;
        end;
      if oldPos >= 0 then
      begin
        { Shift the slot array left by one (still uses old indices). }
        for i := oldPos to Length(FPositionToIndex) - 2 do
          FPositionToIndex[i] := FPositionToIndex[i + 1];
        SetLength(FPositionToIndex, Length(FPositionToIndex) - 1);

        { Re-stamp FPosition on the surviving columns FIRST (collection still
          has the old numbering during cnDeleting, so Items[old index] works). }
        for i := 0 to Length(FPositionToIndex) - 1 do
          (Items[FPositionToIndex[i]] as TTyTreeColumn).FPosition := Cardinal(i);

        { Now adjust stored indices for the post-delete renumbering: FPC
          decrements every item whose Index > deleted col.Index. }
        for i := 0 to Length(FPositionToIndex) - 1 do
          if FPositionToIndex[i] > col.Index then
            Dec(FPositionToIndex[i]);
      end;
      DoChange;
    end;
    cnExtracting:
      DoChange;
  end;
end;

function TTyTreeColumns.ColumnByPosition(APos: Integer): TTyTreeColumn;
begin
  if (APos < 0) or (APos >= Length(FPositionToIndex)) then
    Result := nil
  else
    Result := Items[FPositionToIndex[APos]] as TTyTreeColumn;
end;

procedure TTyTreeColumns.UpdatePositions;
{ Sweep visible columns in position order; assign FLeft. }
var
  i, colIndex: Integer;
  col: TTyTreeColumn;
  running: Integer;
begin
  { After a delete the FPositionToIndex array may reference stale indices.
    Rebuild it now to be safe. }
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  running := 0;
  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyTreeColumn;
    if coVisible in col.FOptions then
    begin
      col.FLeft := running;
      Inc(running, col.FWidth);
    end;
  end;
end;

function TTyTreeColumns.TotalWidth: Integer;
var
  i, colIndex: Integer;
  col: TTyTreeColumn;
begin
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  Result := 0;
  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyTreeColumn;
    if coVisible in col.FOptions then
      Inc(Result, col.FWidth);
  end;
end;

procedure TTyTreeColumns.AdjustPosition(ACol: TTyTreeColumn; ANewPos: Integer);
{ Move ACol to visual position ANewPos, shifting the others. }
var
  oldPos, newPos, i, temp: Integer;
begin
  { Clamp target }
  newPos := Max(0, Min(ANewPos, Count - 1));

  { Find ACol's current position in FPositionToIndex }
  oldPos := -1;
  for i := 0 to Length(FPositionToIndex) - 1 do
    if FPositionToIndex[i] = ACol.Index then
    begin
      oldPos := i;
      Break;
    end;
  if (oldPos < 0) or (oldPos = newPos) then Exit;

  temp := FPositionToIndex[oldPos];
  if oldPos < newPos then
  begin
    { Moving right: shift [oldPos+1 .. newPos] one slot left }
    for i := oldPos to newPos - 1 do
      FPositionToIndex[i] := FPositionToIndex[i + 1];
  end
  else
  begin
    { Moving left: shift [newPos .. oldPos-1] one slot right }
    for i := oldPos downto newPos + 1 do
      FPositionToIndex[i] := FPositionToIndex[i - 1];
  end;
  FPositionToIndex[newPos] := temp;

  { Update FPosition on every column to match the new map }
  for i := 0 to Length(FPositionToIndex) - 1 do
    (Items[FPositionToIndex[i]] as TTyTreeColumn).FPosition := Cardinal(i);

  UpdatePositions;
  DoChange;
end;

function TTyTreeColumns.ColumnFromPosition(AX, AScrollOffset: Integer): Integer;
{ Left-to-right scan; return the collection Index whose on-screen span
  contains AX.  AScrollOffset > 0 means scrolled right. }
var
  i, colIndex: Integer;
  col: TTyTreeColumn;
  cellLeft, cellRight: Integer;
begin
  Result := NoColumn;
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyTreeColumn;
    if not (coVisible in col.FOptions) then Continue;

    cellLeft  := col.FLeft - AScrollOffset;
    cellRight := cellLeft + col.FWidth;

    if (AX >= cellLeft) and (AX < cellRight) then
      Exit(colIndex);
  end;
end;

function TTyTreeColumns.DetermineSplitterIndex(AX, AScrollOffset: Integer;
  ATolLeft: Integer; ATolRight: Integer): Integer;
{ Reverse-iterate visible+resizable columns; return the Index of the one
  whose right screen-edge is within [edge-ATolLeft, edge+ATolRight] of AX. }
var
  i, colIndex: Integer;
  col: TTyTreeColumn;
  edge: Integer;
begin
  Result := NoColumn;
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  for i := Count - 1 downto 0 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyTreeColumn;
    if not (coVisible in col.FOptions) then Continue;
    if not (coResizable in col.FOptions) then Continue;

    { right screen-edge = absolute right − scroll }
    edge := col.FLeft + col.FWidth - AScrollOffset;

    if (AX >= edge - ATolLeft) and (AX <= edge + ATolRight) then
      Exit(colIndex);
  end;
end;

procedure TTyTreeColumns.ApplyAutoSize(AClientWidth, AAutoSizeIndex: Integer);
{ Set column AAutoSizeIndex.Width so that TotalWidth becomes AClientWidth.
  Delta may be negative (column is too wide). Clamped to [MinWidth, MaxWidth]. }
var
  autoCol: TTyTreeColumn;
  others, needed: Integer;
  i, colIndex: Integer;
  col: TTyTreeColumn;
begin
  if (AAutoSizeIndex < 0) or (AAutoSizeIndex >= Count) then Exit;
  autoCol := Items[AAutoSizeIndex] as TTyTreeColumn;

  { Sum widths of all visible columns except the auto-size one }
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  others := 0;
  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyTreeColumn;
    if not (coVisible in col.FOptions) then Continue;
    if colIndex = AAutoSizeIndex then Continue;
    Inc(others, col.FWidth);
  end;

  needed := AClientWidth - others;
  { Clamp to the column's own limits }
  needed := Max(autoCol.FMinWidth, Min(autoCol.FMaxWidth, needed));
  { Floor at MinWidth even if client is very small }
  if needed < autoCol.FMinWidth then
    needed := autoCol.FMinWidth;

  if autoCol.FWidth <> needed then
  begin
    autoCol.FWidth := needed;
    UpdatePositions;
    DoChange;
  end;
end;

procedure TTyTreeColumns.DistributeSpring(ADeltaWidth: Integer);
{ Share ADeltaWidth across all visible coAutoSpring columns proportionally.
  Uses bonus-pixel remainder so widths stay integral and the sum is exact. }
var
  i, colIndex: Integer;
  col: TTyTreeColumn;
  springTotal, share, remainder, bonus: Integer;
  springCols: array of Integer;   { collection indices of spring columns }
  springCount: Integer;
begin
  if ADeltaWidth = 0 then Exit;
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  { Collect visible spring columns and their total width }
  SetLength(springCols, Count);
  springCount := 0;
  springTotal := 0;
  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyTreeColumn;
    if not (coVisible in col.FOptions) then Continue;
    if not (coAutoSpring in col.FOptions) then Continue;
    springCols[springCount] := colIndex;
    Inc(springCount);
    Inc(springTotal, col.FWidth);
  end;
  SetLength(springCols, springCount);

  if (springCount = 0) or (springTotal = 0) then Exit;

  { Distribute proportionally with integral bonus-pixel remainder.
    We accumulate the real (fractional) delta per column and round at each step
    so the cumulative rounding error never exceeds 1 pixel. }
  remainder := 0;   { fractional remainder * springTotal, to avoid floats }
  for i := 0 to springCount - 1 do
  begin
    col := Items[springCols[i]] as TTyTreeColumn;
    { Exact proportional share (scaled by springTotal to keep integer math) }
    share := (ADeltaWidth * col.FWidth + remainder) div springTotal;
    remainder := (ADeltaWidth * col.FWidth + remainder) mod springTotal;
    { Bonus pixel for the first column if remainder > 0 (Bresenham-style) }
    bonus := 0;
    if i = springCount - 1 then
    begin
      { Last column absorbs any remaining fractional pixel }
      bonus := 0;  { absorbed via remainder accumulation above }
    end;
    { Clamp }
    col.FWidth := Max(col.FMinWidth, Min(col.FMaxWidth, col.FWidth + share + bonus));
  end;

  UpdatePositions;
  DoChange;
end;

end.
