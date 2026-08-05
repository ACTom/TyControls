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
  Classes, SysUtils, Math, Controls, LCLType, tyControls.ImageCollection;

const
  NoColumn = -1;   { sentinel: "no column" / not found }

type
  { The horizontal extent of ONE column, in whatever coordinate space the caller's
    origin and PPI put it: device px for a paint, logical px for a hit test.
    Left/Right only -- the vertical extent is the caller's band (a row, the header
    strip, the whole viewport) and never belongs to the column model. }
  TTyColumnSpan = record
    Left, Right: Integer;
  end;

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
    FSizePriority:     Integer;
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
    function  GetVisible: Boolean;
    procedure SetVisible(AValue: Boolean);
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
    { This column's horizontal span, scaled and placed by the caller's origin/PPI.
      A thin accessor over the unit-level TyColumnSpan (which see) -- it exists only
      so a call site reads `col.Span(cellOrigin, PPI)` rather than restating which
      two fields feed the formula. }
    function Span(AOriginX, APPI: Integer): TTyColumnSpan;
    { Read-only public: current absolute left edge (set by UpdatePositions).
      Note: this is NOT scroll-adjusted — paint code subtracts FOffsetX itself.
      PUBLIC and read by hosts, so its meaning is fixed: LOGICAL px, un-scrolled,
      un-scaled. Span() is the supported way to turn it into an x. }
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
    { Per-column visibility as its own boolean, the way LCL publishes it
      (TGridColumn.Visible, grids.pas:626). The STORAGE is still the coVisible element
      of Options -- this is a view onto it, not a second flag, so the two can never
      disagree. `stored False` for that reason: Options already streams the truth, and
      writing both into a .lfm would let a later Options= line silently undo an earlier
      Visible= line (the same reason GridLines is a stored-False alias of GridLineStyle
      over in the grid).

      Worth having anyway: `Columns[i].Visible := False` is what every ported line says,
      and in the collection editor a checkbox is findable where a set element is not. }
    property Visible:          Boolean              read GetVisible        write SetVisible          stored False default True;
    { LCL's names for the width bounds (TGridColumn.MinSize / MaxSize, grids.pas:618-619).
      Aliases of MinWidth / MaxWidth, which stay the storage and the streamed pair.

      NOTE A DEFAULT DIFFERENCE, deliberately kept: LCL's DEFMINSIZE = DEFMAXSIZE = 0,
      both meaning "unbounded", while ours are 10 and 10000. A ported column that never
      mentioned MinSize/MaxSize therefore gains a 10..10000 clamp here. Adopting 0/0
      would remove the floor that keeps a dragged column from collapsing to nothing, so
      the bounds stay; assign 0 explicitly to get LCL's unbounded behaviour. }
    property MinSize:          Integer              read FMinWidth         write SetMinWidth         stored False;
    property MaxSize:          Integer              read FMaxWidth         write SetMaxWidth         stored False;
    { Weight this column pulls when the owner distributes spare width
      (TTyCustomGrid.AutoFillColumns). LCL's TGridColumn.SizePriority
      (grids.pas:622, DEFSIZEPRIORITY = 1 at :80), same meaning and same default:

        0  -- never auto-sized; the column keeps whatever width it has.
        1  -- the default; an equal share with every other participant.
        n  -- pulls n times as hard, so 'give the description column most of the
              slack' is one number rather than an event handler.

      Nothing reads this while AutoFillColumns is off, so it costs a grid that does
      not use it exactly nothing. }
    property SizePriority:     Integer              read FSizePriority     write FSizePriority       default 1;
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
    function  GetColumn(AIndex: Integer): TTyColumn;
    procedure SetColumn(AIndex: Integer; AValue: TTyColumn);
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

    { Typed collection surface, matching TGridColumns (grids.pas:661 `function Add:
      TGridColumn`, :670 `property Items[Index]: TGridColumn ... default`).

      Until these existed the collection was plain TCollection, so `Items[i]` came back
      as TCollectionItem and `Columns[3].Width := 40` -- the default-array form every
      line of ported column code uses -- did not compile at all. Even our OWN code paid
      the tax: `TTyColumn(FHeader.Columns.Items[i])` appears dozens of times in the grid.

      The item class is still whatever the owner asked for (see the three-argument
      Create), so a grid's Items[] really holds TTyGridColumn; TTyColumn is the widest
      type every consumer shares, and a further cast still narrows it. }
    function  Add: TTyColumn;
    property  Items[AIndex: Integer]: TTyColumn read GetColumn write SetColumn; default;
    { Look up the column at visual position APos (0-based). }
    function  ColumnByPosition(APos: Integer): TTyColumn;
    { Find a column by its caption; nil when no column carries it. LCL's
      TGridColumns.ColumnByTitle (grids.pas:663) -- our caption field is named Text
      rather than Title, hence the parameter name, but the lookup is the same one.
      Case-insensitive: a caption is display text, and a report generator matching
      column names should not care that a designer typed 'Total' where the spec said
      'TOTAL'. First match wins when captions repeat. }
    function  ColumnByTitle(const ATitle: string): TTyColumn;

    { Recompute FLeft for every visible column (left-to-right, position order). }
    procedure UpdatePositions;

    { Sum of all visible column widths (logical px). }
    function  TotalWidth: Integer;

    { Move ACol to the new visual position ANewPos, shifting others.
      Called by TTyColumn.SetPosition and by drag-reorder. }
    procedure AdjustPosition(ACol: TTyColumn; ANewPos: Integer);

    { Return the collection Index of the column whose on-screen span contains AX.
      AX / AOriginX / APPI are the SAME three the paints hand to Span() -- device
      px and the paint PPI -- so a hit test is literally the paint's own span
      arithmetic re-run, not a second derivation of it. Returns NoColumn when AX
      is beyond all visible columns. }
    function  ColumnFromPosition(AX, AOriginX, APPI: Integer): Integer;

    { Return the collection Index of a resizable column whose right screen-edge
      is within [right-ATolLeft, right+ATolRight] of AX, or NoColumn.
      Reverse-iterates so rightmost edge wins at overlapping boundaries.
      AX/AOriginX/APPI as in ColumnFromPosition; the two tolerances are LOGICAL
      px and are scaled by APPI here (see the body). }
    function  DetermineSplitterIndex(AX, AOriginX, APPI: Integer;
                                     ATolLeft: Integer = 3;
                                     ATolRight: Integer = 5): Integer;

    { Set column AAutoSizeIndex.Width so that TotalWidth = AClientWidth,
      clamped to that column's [MinWidth, MaxWidth]. }
    procedure ApplyAutoSize(AClientWidth, AAutoSizeIndex: Integer);

    { Distribute ADeltaWidth across all visible coAutoSpring columns
      proportionally (integral bonus-pixel remainder so widths stay whole
      and the sum of deltas is exact). }
    procedure DistributeSpring(ADeltaWidth: Integer);

    { Set ABSOLUTE widths so every visible column together fills AClientWidth, sharing
      the spare space by SizePriority. This is what LCL's AutoFillColumns does
      (grids.pas:1224 + CalcAutoSizeColumn at :987), and it is the multi-column
      counterpart of ApplyAutoSize, which can only fatten ONE designated column.

      Rules, in the order they matter:
        - SizePriority = 0 columns keep their current width and come out of the budget
          first: "never auto-size me" has to hold even when that leaves the others
          nothing;
        - the rest share the remaining budget in proportion to SizePriority, each
          clamped to its own [MinWidth, MaxWidth];
        - a column that hits a clamp retires and its leftover is redistributed over the
          ones still free, repeatedly. Without that pass a single narrow-MaxWidth column
          silently swallows slack it cannot use and the row comes up short;
        - integral throughout, and the last free column absorbs the rounding remainder
          so the sum is EXACT -- one pixel of gap at the right edge is precisely what a
          user notices about a "fill the width" feature. }
    procedure DistributeFill(AClientWidth: Integer);

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
    FImages:        TTyVirtualImageList;
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
    { Icon source for the column headers, indexed by TTyColumn.ImageIndex. LCL's
      equivalent is TCustomHeaderControl.Images (comctrls.pp:4037).

      Typed TTyVirtualImageList, not LCL's TCustomImageList. That is not a preference:
      TTyVirtualImageList renders on demand instead of holding a fixed-resolution set, so
      it is NOT a TCustomImageList descendant -- which meant that while this property was
      typed TCustomImageList, the only lists assignable to it were exactly the ones no
      TTyPainter can draw. The property was unusable by construction, and every consumer
      that wanted header icons carried a private second list to work around it
      (TTyCustomGrid.Images still does, and says so). }
    property Images:        TTyVirtualImageList  read FImages        write FImages;
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

{ ---------------------------------------------------------------------------
  The ONE place a column's Left/Width becomes an x.
  --------------------------------------------------------------------------- }

{ Turn a column's LOGICAL left/width into a span, given the x that logical 0 sits at
  (AOriginX) and the pixel density to scale by (APPI; 96 = no scaling).

  This exists because the same three-term formula
      left := origin + Scale(col.Left);  right := left + Scale(col.Width)
  used to be written out at NINE call sites -- the two hit tests below plus seven
  paints across ListView and TreeView -- each combining ScaleI/MulDiv/P.Scale, a
  scroll offset and a cell origin in its own way. Nine copies of one formula is nine
  chances to get eight of them right, and this control family has already shipped the
  failure that produces: a column that paints in one place and answers clicks in
  another. Passing the origin in (rather than a scroll offset) is deliberate -- it is
  what lets ONE function serve callers whose FOffsetX has opposite signs; see the
  comment on ColumnFromPosition.

  Callers supply the origin already in their own space -- and since the hit tests
  moved into device px there is only ONE space left, so a hit test and the paint it
  answers for pass an IDENTICAL pair:
    * TTyTreeView paint + hit tests -> ContentRect.Left + FOffsetX (FOffsetX <= 0), APPI = PPI
    * TTyListView paint + hit tests -> -FOffsetX                   (FOffsetX >= 0), APPI = Dpi
  Nothing else may compute a column x. }
function TyColumnSpan(ALogicalLeft, ALogicalWidth, AOriginX, APPI: Integer): TTyColumnSpan;

implementation

function TyColumnSpan(ALogicalLeft, ALogicalWidth, AOriginX, APPI: Integer): TTyColumnSpan;
begin
  { MulDiv, not a hand-rolled (a*p) div 96: it is what every existing call site used
    (ScaleI, TTyPainter.Scale and the inline MulDivs are all MulDiv(n, PPI, 96)), and
    its round-half-away-from-zero differs from div's truncation on exactly the odd
    half-pixels where a column edge is most likely to land. APPI = 96 is the identity,
    which is how the logical-space hit tests get today's arithmetic unchanged. }
  Result.Left  := AOriginX + MulDiv(ALogicalLeft, APPI, 96);
  Result.Right := Result.Left + MulDiv(ALogicalWidth, APPI, 96);
end;

{ ---------------------------------------------------------------------------
  TTyColumn
  --------------------------------------------------------------------------- }

function TTyColumn.Span(AOriginX, APPI: Integer): TTyColumnSpan;
begin
  Result := TyColumnSpan(FLeft, FWidth, AOriginX, APPI);
end;

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
  FSizePriority     := 1;      { DEFSIZEPRIORITY, as in LCL (grids.pas:80) }
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
    FSizePriority     := Src.FSizePriority;
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

function TTyColumn.GetVisible: Boolean;
begin
  Result := coVisible in FOptions;
end;

procedure TTyColumn.SetVisible(AValue: Boolean);
var
  o: TTyColumnOptions;
begin
  { Routed through SetOptions, not straight at FOptions: hiding a column has to re-run
    UpdatePositions and notify the header, and that bookkeeping lives there. Writing the
    flag directly is exactly how a "hidden column still takes up width" bug gets made. }
  o := FOptions;
  if AValue then Include(o, coVisible) else Exclude(o, coVisible);
  SetOptions(o);
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

function TTyColumns.GetColumn(AIndex: Integer): TTyColumn;
begin
  Result := TTyColumn(inherited Items[AIndex]);
end;

procedure TTyColumns.SetColumn(AIndex: Integer; AValue: TTyColumn);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyColumns.Add: TTyColumn;
begin
  Result := TTyColumn(inherited Add);
end;

function TTyColumns.ColumnByTitle(const ATitle: string): TTyColumn;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if SameText(Items[i].Text, ATitle) then Exit(Items[i]);
  Result := nil;
end;

function TTyColumns.ColumnByPosition(APos: Integer): TTyColumn;
begin
  if (APos < 0) or (APos >= Length(FPositionToIndex)) then
    Result := nil
  else
    Result := Items[FPositionToIndex[APos]];
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

function TTyColumns.ColumnFromPosition(AX, AOriginX, APPI: Integer): Integer;
{ Left-to-right scan; return the collection Index whose on-screen span
  contains AX.

  ONE SPACE, DEVICE PX. AX, AOriginX and APPI are exactly what the caller's PAINT
  passes to Span() -- the same origin, the same PPI -- so the boundary this answers
  IS the boundary that was drawn, by construction rather than by agreement.

  这三个参数取代了旧的 (AX, AScrollOffset) 逻辑像素对。旧签名在 96 DPI 之外会把同一
  条列边界舍入两次:命中侧 MulDiv(device, 96, PPI) 向下折算,绘制侧 MulDiv(left, PPI, 96)
  向上折算,两次半像素取整不必然落回同一格。实测 PPI 120/144/168/192 × 宽度 100..109,
  50 组里有 22 组的首个可命中像素比首个绘制像素靠左一格 —— 也就是某一列的最后一个像素
  会回答成下一列。改成"只在一个空间里比较、只在边界处换算"后,差值恒为 0。

  The origin form is also what lets the two controls share this: TTyTreeView stores
  FOffsetX <= 0 and passes CR.Left + FOffsetX, TTyListView stores it >= 0 and passes
  -FOffsetX. Both mean "where logical x 0 currently sits", which is what an origin is
  -- and it is the quantity a right-to-left reflection has to mirror, so the axis is
  now expressed in the one form mirroring can consume. }
var
  i, colIndex: Integer;
  col: TTyColumn;
  span: TTyColumnSpan;
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

    span := col.Span(AOriginX, APPI);

    if (AX >= span.Left) and (AX < span.Right) then
      Exit(colIndex);
  end;
end;

function TTyColumns.DetermineSplitterIndex(AX, AOriginX, APPI: Integer;
  ATolLeft: Integer; ATolRight: Integer): Integer;
{ Reverse-iterate visible+resizable columns; return the Index of the one
  whose right screen-edge is within [edge-ATolLeft, edge+ATolRight] of AX.

  AX/AOriginX/APPI are device px (see ColumnFromPosition). THE TOLERANCES ARE NOT:
  ±3/5 describes how big the grab zone should FEEL, so it is a logical measurement
  and is scaled here. Leaving it in device px would silently halve the physical grip
  at 192 PPI -- the same class of regression as any other unscaled constant, and the
  reason the tolerance did not simply follow AX into device space when the rest did.
  At APPI = 96 the scaling is the identity, so nothing moves at the default density. }
var
  i, colIndex, tolL, tolR: Integer;
  col: TTyColumn;
  span: TTyColumnSpan;
begin
  Result := NoColumn;
  if Length(FPositionToIndex) <> Count then
    RebuildPositionMap;

  tolL := MulDiv(ATolLeft,  APPI, 96);
  tolR := MulDiv(ATolRight, APPI, 96);

  for i := Count - 1 downto 0 do
  begin
    colIndex := FPositionToIndex[i];
    if (colIndex < 0) or (colIndex >= Count) then Continue;
    col := Items[colIndex] as TTyColumn;
    if not (coVisible in col.FOptions) then Continue;
    if not (coResizable in col.FOptions) then Continue;

    { The grip is the span's RIGHT edge -- read off the same span the body hit test
      and the paints use, never recomputed, so the divider can never end up beside
      the border it is supposed to be on. }
    span := col.Span(AOriginX, APPI);

    if (AX >= span.Right - tolL) and (AX <= span.Right + tolR) then
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

procedure TTyColumns.DistributeFill(AClientWidth: Integer);
var
  free_: array of Integer;      { collection indices still free to move }
  freeCount, weightTotal, budget, i, colIndex, w, given, lastFree: Integer;
  col: TTyColumn;
  clamped, anyChanged: Boolean;
begin
  if Count = 0 then Exit;
  if AClientWidth < 0 then AClientWidth := 0;

  { Budget = client width minus every visible column that does NOT participate. }
  budget := AClientWidth;
  SetLength(free_, Count);
  freeCount := 0;
  weightTotal := 0;
  for i := 0 to Count - 1 do
  begin
    col := Items[i];
    if not (coVisible in col.FOptions) then Continue;
    if col.FSizePriority <= 0 then
    begin
      Dec(budget, col.FWidth);
      Continue;
    end;
    free_[freeCount] := i;
    Inc(freeCount, 1);
    Inc(weightTotal, col.FSizePriority);
  end;
  SetLength(free_, freeCount);
  if (freeCount = 0) or (weightTotal <= 0) then Exit;
  if budget < 0 then budget := 0;
  anyChanged := False;

  { Clamp pass: hand out proportional shares, retire whatever hit a bound, repeat.
    Terminates because every round either retires a column or finds nothing to retire. }
  repeat
    clamped := False;
    for i := 0 to freeCount - 1 do
    begin
      col := Items[free_[i]];
      w := (budget * col.FSizePriority) div weightTotal;
      if w < col.FMinWidth then w := col.FMinWidth
      else if w > col.FMaxWidth then w := col.FMaxWidth
      else Continue;                          { still free }
      { Retire it at its clamped width and take it out of the budget. }
      if col.FWidth <> w then anyChanged := True;
      col.FWidth := w;
      Dec(budget, w);
      Dec(weightTotal, col.FSizePriority);
      free_[i] := free_[freeCount - 1];
      Dec(freeCount);
      clamped := True;
      Break;                                  { indices shifted; restart the sweep }
    end;
  until (not clamped) or (freeCount = 0) or (weightTotal <= 0);

  if budget < 0 then budget := 0;

  { Unclamped remainder: proportional shares, and the LAST one takes what is left so the
    widths sum to the budget exactly rather than one pixel short. }
  given := 0;
  lastFree := freeCount - 1;
  for i := 0 to freeCount - 1 do
  begin
    colIndex := free_[i];
    col := Items[colIndex];
    if i = lastFree then w := budget - given
    else w := (budget * col.FSizePriority) div weightTotal;
    if w < col.FMinWidth then w := col.FMinWidth;
    if w > col.FMaxWidth then w := col.FMaxWidth;
    if col.FWidth <> w then anyChanged := True;
    col.FWidth := w;
    Inc(given, w);
  end;

  { Notify ONLY when a width actually moved. This is not an optimisation: the owner's
    OnChange runs UpdateScrollBars, which is where this method is called from, so an
    unconditional DoChange recurses until the stack gives out (it did -- a segfault,
    not a hang, and with no output at all). Converging on "nothing left to change" is
    what breaks the loop, exactly as ApplyAutoSize's `if autoCol.FWidth <> needed` does. }
  if not anyChanged then Exit;
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
