unit tyControls.Columns;
{$mode objfpc}{$H+}
{ A pure, control-agnostic column model: types, a position<->index map, layout and
  hit-testing, auto-size and spring distribution, and TTyHeader owning TTyColumns.

  It depends on no control and is fully headless-testable. TTyTreeView publishes a
  Header/Columns built from it, and TTyListView's report mode does the same — which is
  why the types are named TTyColumn/TTyColumns/TTyHeader rather than TTyTreeColumn/...
  (they were, until the model was shared). The old names remain as deprecated aliases;
  the unit was called tyControls.TreeView.Columns and still exists under that name as a
  thin compatibility shim. }
interface
uses
  Classes, SysUtils, Math, ImgList, Controls;

const
  NoColumn = -1;   { sentinel: "no column" / not found }

type
  { Column-level option flags (mirrors VTV's TVTColumnOption subset) }
  TTyColumnOption = (
    coVisible,       { column is shown in the header and body }
    coResizable,     { the user can drag the column's right edge to resize }
    coAllowClick,    { clicking the column header fires OnHeaderClick }
    coDraggable,     { the user can drag the column to a new position }
    coAutoSpring     { column participates in spring distribution on resize }
  );
  TTyColumnOptions = set of TTyColumnOption;

  TTyColumns = class;   { forward }
  TTyHeader  = class;   { forward }

  { Header option flags (mirrors VTV's TVTHeaderOption subset) }
  TTyHeaderOption = (
    hoVisible,              { paint the header band above the node area }
    hoColumnResize,         { allow dragging column dividers to resize }
    hoShowSortGlyphs,       { show a sort triangle in the sort column }
    hoHeaderClickAutoSort,  { clicking a section triggers SortTree }
    hoDrag,                 { allow dragging columns to reorder }
    hoAutoResize,           { one column (AutoSizeIndex) fills remaining width }
    hoHotTrack              { highlight the hovered header section }
  );
  TTyHeaderOptions = set of TTyHeaderOption;

  { Sort direction (used by TTyHeader.SortDirection + SortTree).
    Declared here so both the header and the tree can reference it. }
  TTySortDirection = (sdAscending, sdDescending);

  { ===================================================================
    TTyColumn — one column (TCollectionItem)
    =================================================================== }
  TTyColumn = class(TCollectionItem)
  private
    FWidth:            Integer;
    FMinWidth:         Integer;
    FMaxWidth:         Integer;
    FAlignment:        TAlignment;
    FCaptionAlignment: TAlignment;
    FText:             TCaption;
    FImageIndex:       Integer;
    FOptions:          TTyColumnOptions;
    FTag:              NativeInt;
    { internal: absolute left edge set by UpdatePositions }
    FLeft:             Integer;
    { cached visual position — kept in sync by AdjustPosition }
    FPosition:         Cardinal;

    procedure SetWidth(AValue: Integer);
    procedure SetMinWidth(AValue: Integer);
    procedure SetMaxWidth(AValue: Integer);
    procedure SetPosition(AValue: Cardinal);
    procedure SetOptions(AValue: TTyColumnOptions);
    procedure SetAlignment(AValue: TAlignment);
    procedure SetCaptionAlignment(AValue: TAlignment);
    procedure SetText(const AValue: TCaption);
    procedure SetImageIndex(AValue: Integer);
    function  GetOwnerColumns: TTyColumns;
    procedure NotifyOwner;
  protected
    function  GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
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
    property Text:             TCaption               read FText             write SetText;
    property ImageIndex:       Integer              read FImageIndex       write SetImageIndex       default -1;
    property Options:          TTyColumnOptions read FOptions          write SetOptions;
    property Tag:              NativeInt            read FTag              write FTag                default 0;
  end;

  { ===================================================================
    TTyColumns — ordered collection of TTyColumn
    =================================================================== }
  TTyColumns = class(TCollection)
  private
    { Maps visual Position (0-based) -> collection Index.
      Length always = Count.  Maintained by Add/Delete/AdjustPosition. }
    FPositionToIndex: array of Integer;
    { Notify hook: wired by Phase-B header.  May be nil in Phase-A tests. }
    FOnChange: TNotifyEvent;
    { Owning header (Phase B). nil in Phase-A headless tests and during raw
      LFM streaming via the parameterless Create — GetOwner returns it so the
      first-column add hook can reach the header's MainColumn. }
    FOwnerHeader: TTyHeader;

    procedure RebuildPositionMap;
    procedure DoChange;
  protected
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    function  GetOwner: TPersistent; override;
  public
    constructor Create; overload;
    constructor Create(AOwnerHeader: TTyHeader); overload;
    { Lets an owner (the grid) supply its own TTyColumn descendant, so grid-only
      column properties don't have to be pushed down into the shared TTyColumn
      that ListView/TreeView also use. Nil = plain TTyColumn. }
    constructor Create(AOwnerHeader: TTyHeader;
      AItemClass: TCollectionItemClass); overload;

    { Look up the column at visual position APos (0-based). }
    function  ColumnByPosition(APos: Integer): TTyColumn;

    { Recompute FLeft for every visible column (left-to-right, position order). }
    procedure UpdatePositions;

    { Sum of all visible column widths (logical px). }
    function  TotalWidth: Integer;

    { Move ACol to the new visual position ANewPos, shifting others.
      Called by TTyColumn.SetPosition and by drag-reorder. }
    procedure AdjustPosition(ACol: TTyColumn; ANewPos: Integer);

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

  { ===================================================================
    TTyHeader — header band descriptor (Phase B)
    Owned by TTyTreeView; painted by the tree (not a windowed control).
    =================================================================== }
  TTyHeader = class(TPersistent)
  private
    FHeight:        Integer;
    FHeightExplicit: Boolean;   { True once a host/.lfm sets Height; False = follow --header-height (density) }
    FColumns:       TTyColumns;
    FMainColumn:    Integer;
    FSortColumn:    Integer;
    FSortDirection: TTySortDirection;
    FAutoSizeIndex: Integer;
    FImages:        TCustomImageList;
    FOptions:       TTyHeaderOptions;
    FOnChange:      TNotifyEvent;

    procedure SetHeight(AValue: Integer);
    procedure SetMainColumn(AValue: Integer);
    procedure SetSortColumn(AValue: Integer);
    procedure SetSortDirection(AValue: TTySortDirection);
    procedure SetAutoSizeIndex(AValue: Integer);
    procedure SetOptions(AValue: TTyHeaderOptions);
    { Forwarded from FColumns.OnChange }
    procedure ColumnsChanged(Sender: TObject);
  public
    constructor Create; overload;
    { See TTyColumns.Create(AOwnerHeader, AItemClass). }
    constructor Create(AColumnClass: TCollectionItemClass); overload;
    destructor  Destroy; override;
    procedure Assign(ASource: TPersistent); override;

    { Fire FOnChange — called by all mutating setters and by ColumnsChanged. }
    procedure Changed;

    { Hook wired by the tree so it is notified of every header/column change. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;

    { True once a host/.lfm set Height explicitly. A consumer that wants the header
      band to follow the density axis reads this: while False, size the band from
      the '--header-height' token (classic 22 / modern 36); while True, honour the pin. }
    property HeightIsExplicit: Boolean read FHeightExplicit;
  published
    property Height:        Integer              read FHeight        write SetHeight        default 22;
    property Columns:       TTyColumns       read FColumns;
    property MainColumn:    Integer              read FMainColumn    write SetMainColumn    default 0;
    property SortColumn:    Integer              read FSortColumn    write SetSortColumn    default -1;
    property SortDirection: TTySortDirection     read FSortDirection write SetSortDirection default sdAscending;
    property AutoSizeIndex: Integer              read FAutoSizeIndex write SetAutoSizeIndex default -1;
    property Images:        TCustomImageList     read FImages        write FImages;
    property Options:       TTyHeaderOptions read FOptions       write SetOptions;
  end;

  { Names this model carried while it was tree-only. Kept so v2.2 code keeps compiling;
    they are aliases, not distinct types, so `Columns.Add as TTyTreeColumn` still works. }
  TTyTreeColumnOption  = TTyColumnOption  deprecated 'use TTyColumnOption';
  TTyTreeColumnOptions = TTyColumnOptions deprecated 'use TTyColumnOptions';
  TTyTreeColumn        = TTyColumn        deprecated 'use TTyColumn';
  TTyTreeColumns       = TTyColumns       deprecated 'use TTyColumns';
  TTyTreeHeaderOption  = TTyHeaderOption  deprecated 'use TTyHeaderOption';
  TTyTreeHeaderOptions = TTyHeaderOptions deprecated 'use TTyHeaderOptions';
  TTyTreeHeader        = TTyHeader        deprecated 'use TTyHeader';

implementation

{ ---------------------------------------------------------------------------
  TTyColumn
  --------------------------------------------------------------------------- }

constructor TTyColumn.Create(ACollection: TCollection);
begin
  { NOTE: inherited Create calls SetCollection → InsertItem → Notify(cnAdded)
    BEFORE any of our field assignments below run (FWidth is still 0 at that
    point).  We re-run UpdatePositions+DoChange at the end so the owner's
    position cache and any wired OnChange handler see the correct defaults. }
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
  { Re-notify with the correct defaults now set. }
  if Collection <> nil then
  begin
    GetOwnerColumns.UpdatePositions;
    GetOwnerColumns.DoChange;
  end;
end;

procedure TTyColumn.Assign(ASource: TPersistent);
var
  Src: TTyColumn;
begin
  if ASource is TTyColumn then
  begin
    Src := TTyColumn(ASource);
    FWidth            := Src.FWidth;
    FMinWidth         := Src.FMinWidth;
    FMaxWidth         := Src.FMaxWidth;
    FAlignment        := Src.FAlignment;
    FCaptionAlignment := Src.FCaptionAlignment;
    FText             := Src.FText;
    FImageIndex       := Src.FImageIndex;
    FOptions          := Src.FOptions;
    FTag              := Src.FTag;
    { FLeft and FPosition are computed — not copied; let the owning
      collection recompute them via UpdatePositions after assignment. }
    if Collection <> nil then
      GetOwnerColumns.UpdatePositions;
  end
  else
    inherited Assign(ASource);
end;

function TTyColumn.GetDisplayName: string;
begin
  if FText <> '' then
    Result := FText
  else
    Result := inherited GetDisplayName;
end;

function TTyColumn.GetOwnerColumns: TTyColumns;
begin
  Result := Collection as TTyColumns;
end;

procedure TTyColumn.NotifyOwner;
begin
  if Collection <> nil then
    GetOwnerColumns.DoChange;
end;

procedure TTyColumn.SetWidth(AValue: Integer);
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

procedure TTyColumn.SetMinWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FMinWidth = AValue then Exit;
  FMinWidth := AValue;
  { Re-clamp width if needed }
  if FWidth < FMinWidth then
    SetWidth(FMinWidth);
end;

procedure TTyColumn.SetMaxWidth(AValue: Integer);
begin
  if AValue < FMinWidth then AValue := FMinWidth;
  if FMaxWidth = AValue then Exit;
  FMaxWidth := AValue;
  if FWidth > FMaxWidth then
    SetWidth(FMaxWidth);
end;

procedure TTyColumn.SetPosition(AValue: Cardinal);
begin
  if FPosition = AValue then Exit;
  if Collection <> nil then
    GetOwnerColumns.AdjustPosition(Self, AValue);
end;

procedure TTyColumn.SetOptions(AValue: TTyColumnOptions);
begin
  if FOptions = AValue then Exit;
  FOptions := AValue;
  if Collection <> nil then
  begin
    GetOwnerColumns.UpdatePositions;
    GetOwnerColumns.DoChange;
  end;
end;

procedure TTyColumn.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  NotifyOwner;
end;

procedure TTyColumn.SetCaptionAlignment(AValue: TAlignment);
begin
  if FCaptionAlignment = AValue then Exit;
  FCaptionAlignment := AValue;
  NotifyOwner;
end;

procedure TTyColumn.SetText(const AValue: TCaption);
begin
  if FText = AValue then Exit;
  FText := AValue;
  NotifyOwner;
end;

procedure TTyColumn.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  NotifyOwner;
end;

{ ---------------------------------------------------------------------------
  TTyColumns
  --------------------------------------------------------------------------- }

constructor TTyColumns.Create;
begin
  inherited Create(TTyColumn);
  SetLength(FPositionToIndex, 0);
  FOnChange    := nil;
  FOwnerHeader := nil;
end;

constructor TTyColumns.Create(AOwnerHeader: TTyHeader);
begin
  Create;
  FOwnerHeader := AOwnerHeader;
end;

constructor TTyColumns.Create(AOwnerHeader: TTyHeader;
  AItemClass: TCollectionItemClass);
begin
  if AItemClass = nil then AItemClass := TTyColumn;
  inherited Create(AItemClass);
  SetLength(FPositionToIndex, 0);
  FOnChange    := nil;
  FOwnerHeader := AOwnerHeader;
end;

function TTyColumns.GetOwner: TPersistent;
begin
  Result := FOwnerHeader;
end;

procedure TTyColumns.DoChange;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyColumns.RebuildPositionMap;
{ Full rebuild: assign FPosition = Index for every item (natural order),
  then mirror into FPositionToIndex. }
var
  i: Integer;
begin
  SetLength(FPositionToIndex, Count);
  for i := 0 to Count - 1 do
  begin
    FPositionToIndex[i] := i;
    (Items[i] as TTyColumn).FPosition := Cardinal(i);
  end;
end;

procedure TTyColumns.Notify(Item: TCollectionItem;
  Action: TCollectionNotification);
var
  col: TTyColumn;
  oldPos, i: Integer;
begin
  inherited Notify(Item, Action);
  col := Item as TTyColumn;
  case Action of
    cnAdded:
    begin
      { Append the new column at the last visual position. }
      SetLength(FPositionToIndex, Count);
      FPositionToIndex[Count - 1] := col.Index;
      col.FPosition := Cardinal(Count - 1);
      { Footgun guard: when the FIRST column is added and the owning header's
        MainColumn is still NoColumn (e.g. the app assigned MainColumn before
        any column existed, so the setter clamped it to -1), default it to the
        first column — VirtualTreeView does the same. Only fires on the first
        add (Count = 1), so any explicit later choice (incl. an opt-out
        MainColumn := NoColumn, or := 2) is fully respected. The assignment
        goes through SetMainColumn, which now succeeds because Count >= 1. }
      if (Count = 1) and (GetOwner is TTyHeader) and
         (TTyHeader(GetOwner).MainColumn = NoColumn) then
        TTyHeader(GetOwner).MainColumn := 0;
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
          (Items[FPositionToIndex[i]] as TTyColumn).FPosition := Cardinal(i);

        { Now adjust stored indices for the post-delete renumbering: FPC
          decrements every item whose Index > deleted col.Index. }
        for i := 0 to Length(FPositionToIndex) - 1 do
          if FPositionToIndex[i] > col.Index then
            Dec(FPositionToIndex[i]);
      end;
      { Deletion never goes through SetMainColumn (the only other clamp site), so keep
        MainColumn valid + following the index renumber here. Otherwise a stale,
        now-out-of-range MainColumn makes RenderTo's `colIdx = MainColumn` never match
        and ALL tree chrome (expand buttons / images / main caption) silently vanishes.
        Count still includes the column being deleted, so post-delete count = Count - 1. }
      if GetOwner is TTyHeader then
        with TTyHeader(GetOwner) do
        begin
          if FMainColumn = col.Index then
          begin
            if Count - 1 > 0 then FMainColumn := 0 else FMainColumn := NoColumn;
          end
          else if FMainColumn > col.Index then
            Dec(FMainColumn);
          if (FMainColumn <> NoColumn) and (FMainColumn >= Count - 1) then
          begin
            if Count - 1 > 0 then FMainColumn := Count - 2 else FMainColumn := NoColumn;
          end;
        end;
      DoChange;
    end;
    cnExtracting:
      DoChange;
  end;
end;

function TTyColumns.ColumnByPosition(APos: Integer): TTyColumn;
begin
  if (APos < 0) or (APos >= Length(FPositionToIndex)) then
    Result := nil
  else
    Result := Items[FPositionToIndex[APos]] as TTyColumn;
end;

procedure TTyColumns.UpdatePositions;
{ Sweep visible columns in position order; assign FLeft. }
var
  i, colIndex: Integer;
  col: TTyColumn;
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
    col := Items[colIndex] as TTyColumn;
    if coVisible in col.FOptions then
    begin
      col.FLeft := running;
      Inc(running, col.FWidth);
    end;
  end;
end;

function TTyColumns.TotalWidth: Integer;
var
  i, colIndex: Integer;
  col: TTyColumn;
begin
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  Result := 0;
  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyColumn;
    if coVisible in col.FOptions then
      Inc(Result, col.FWidth);
  end;
end;

procedure TTyColumns.AdjustPosition(ACol: TTyColumn; ANewPos: Integer);
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
    (Items[FPositionToIndex[i]] as TTyColumn).FPosition := Cardinal(i);

  UpdatePositions;
  DoChange;
end;

function TTyColumns.ColumnFromPosition(AX, AScrollOffset: Integer): Integer;
{ Left-to-right scan; return the collection Index whose on-screen span
  contains AX.  AScrollOffset > 0 means scrolled right. }
var
  i, colIndex: Integer;
  col: TTyColumn;
  cellLeft, cellRight: Integer;
begin
  Result := NoColumn;
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyColumn;
    if not (coVisible in col.FOptions) then Continue;

    cellLeft  := col.FLeft - AScrollOffset;
    cellRight := cellLeft + col.FWidth;

    if (AX >= cellLeft) and (AX < cellRight) then
      Exit(colIndex);
  end;
end;

function TTyColumns.DetermineSplitterIndex(AX, AScrollOffset: Integer;
  ATolLeft: Integer; ATolRight: Integer): Integer;
{ Reverse-iterate visible+resizable columns; return the Index of the one
  whose right screen-edge is within [edge-ATolLeft, edge+ATolRight] of AX. }
var
  i, colIndex: Integer;
  col: TTyColumn;
  edge: Integer;
begin
  Result := NoColumn;
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  for i := Count - 1 downto 0 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyColumn;
    if not (coVisible in col.FOptions) then Continue;
    if not (coResizable in col.FOptions) then Continue;

    { right screen-edge = absolute right − scroll }
    edge := col.FLeft + col.FWidth - AScrollOffset;

    if (AX >= edge - ATolLeft) and (AX <= edge + ATolRight) then
      Exit(colIndex);
  end;
end;

procedure TTyColumns.ApplyAutoSize(AClientWidth, AAutoSizeIndex: Integer);
{ Set column AAutoSizeIndex.Width so that TotalWidth becomes AClientWidth.
  Delta may be negative (column is too wide). Clamped to [MinWidth, MaxWidth]. }
var
  autoCol: TTyColumn;
  others, needed: Integer;
  i, colIndex: Integer;
  col: TTyColumn;
begin
  if (AAutoSizeIndex < 0) or (AAutoSizeIndex >= Count) then Exit;
  autoCol := Items[AAutoSizeIndex] as TTyColumn;

  { Sum widths of all visible columns except the auto-size one }
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  others := 0;
  for i := 0 to Count - 1 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyColumn;
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

procedure TTyColumns.DistributeSpring(ADeltaWidth: Integer);
{ Share ADeltaWidth across all visible coAutoSpring columns proportionally.
  Uses bonus-pixel remainder so widths stay integral and the sum is exact. }
var
  i, colIndex: Integer;
  col: TTyColumn;
  springTotal, share, remainder: Integer;
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
    col := Items[colIndex] as TTyColumn;
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
    col := Items[springCols[i]] as TTyColumn;
    { Exact proportional share (scaled by springTotal to keep integer math) }
    share := (ADeltaWidth * col.FWidth + remainder) div springTotal;
    remainder := (ADeltaWidth * col.FWidth + remainder) mod springTotal;
    { Clamp (the running `remainder` accumulation already carries the fractional
      pixel forward, so the integer shares sum to ADeltaWidth). }
    col.FWidth := Max(col.FMinWidth, Min(col.FMaxWidth, col.FWidth + share));
  end;

  UpdatePositions;
  DoChange;
end;

{ ---------------------------------------------------------------------------
  TTyHeader
  --------------------------------------------------------------------------- }

constructor TTyHeader.Create;
begin
  Create(nil);
end;

constructor TTyHeader.Create(AColumnClass: TCollectionItemClass);
begin
  inherited Create;
  FHeight        := 22;
  FHeightExplicit := False;
  FMainColumn    := 0;
  FSortColumn    := NoColumn;
  FSortDirection := sdAscending;
  FAutoSizeIndex := NoColumn;
  FImages        := nil;
  FOptions       := [hoVisible, hoColumnResize, hoShowSortGlyphs,
                     hoHeaderClickAutoSort, hoDrag];
  FColumns       := TTyColumns.Create(Self, AColumnClass);
  FColumns.OnChange := @ColumnsChanged;
end;

destructor TTyHeader.Destroy;
begin
  FColumns.Free;
  inherited Destroy;
end;

procedure TTyHeader.ColumnsChanged(Sender: TObject);
begin
  Changed;
end;

procedure TTyHeader.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyHeader.SetHeight(AValue: Integer);
begin
  FHeightExplicit := True;
  if FHeight = AValue then Exit;
  FHeight := AValue;
  Changed;
end;

procedure TTyHeader.SetMainColumn(AValue: Integer);
var
  maxCol: Integer;
begin
  { Clamp to [NoColumn, Columns.Count-1] }
  if FColumns.Count = 0 then
    AValue := NoColumn
  else
  begin
    maxCol := FColumns.Count - 1;
    if AValue < NoColumn then AValue := NoColumn;
    if AValue > maxCol   then AValue := maxCol;
  end;
  if FMainColumn = AValue then Exit;
  FMainColumn := AValue;
  Changed;
end;

procedure TTyHeader.SetSortColumn(AValue: Integer);
begin
  if FSortColumn = AValue then Exit;
  FSortColumn := AValue;
  Changed;
end;

procedure TTyHeader.SetSortDirection(AValue: TTySortDirection);
begin
  if FSortDirection = AValue then Exit;
  FSortDirection := AValue;
  Changed;
end;

procedure TTyHeader.SetAutoSizeIndex(AValue: Integer);
begin
  if FAutoSizeIndex = AValue then Exit;
  FAutoSizeIndex := AValue;
  Changed;
end;

procedure TTyHeader.SetOptions(AValue: TTyHeaderOptions);
begin
  if FOptions = AValue then Exit;
  FOptions := AValue;
  Changed;
end;

procedure TTyHeader.Assign(ASource: TPersistent);
var
  Src: TTyHeader;
  i: Integer;
  srcCol, dstCol: TTyColumn;
begin
  if ASource is TTyHeader then
  begin
    Src := TTyHeader(ASource);
    FHeight        := Src.FHeight;
    FHeightExplicit := Src.FHeightExplicit;
    FSortColumn    := Src.FSortColumn;
    FSortDirection := Src.FSortDirection;
    FAutoSizeIndex := Src.FAutoSizeIndex;
    FImages        := Src.FImages;
    FOptions       := Src.FOptions;
    { Rebuild columns }
    FColumns.Clear;
    for i := 0 to Src.FColumns.Count - 1 do
    begin
      srcCol := Src.FColumns.Items[i] as TTyColumn;
      dstCol := FColumns.Add as TTyColumn;
      dstCol.Assign(srcCol);
    end;
    { MainColumn AFTER the rebuild: each FColumns.Add fires Notify(cnAdded), and the
      first one auto-defaults MainColumn to 0 when it is NoColumn — which would clobber
      a copied opt-out (NoColumn). Assigning here (post-rebuild, Count = Src.Count) lets
      the opt-out and any explicit value survive. }
    FMainColumn := Src.FMainColumn;
    Changed;
  end
  else
    inherited Assign(ASource);
end;

initialization
  { Register sub-object classes so the LFM streaming system can instantiate
    them when loading a .lfm that contains a TTyTreeView with Header/Columns.
    Must be in initialization (before end.) — code after end. is dead. }
  { The aliases also register under the pre-rename names, so a .lfm written by an older
    version still resolves its class references. }
  RegisterClassAlias(TTyColumn,  'TTyTreeColumn');
  RegisterClassAlias(TTyColumns, 'TTyTreeColumns');
  RegisterClassAlias(TTyHeader,  'TTyTreeHeader');
  RegisterClass(TTyColumn);
  RegisterClass(TTyColumns);
  RegisterClass(TTyHeader);

end.
