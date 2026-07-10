unit tyControls.ListView;
{$mode objfpc}{$H+}
{ TTyListView — a custom-drawn, virtual-capable list/report view.

  Design: docs/superpowers/specs/2026-07-10-listview-design.md
  Plan  : docs/superpowers/plans/2026-07-10-listview-sp1.md (task 2 contract)

  Two coordinate systems run through this control and mixing them is the classic
  source of bugs, so every conversion site is commented with its direction:

    - item index    : stable, 0..ItemCount-1, independent of the sort order. EVERY
                      public/published member and EVERY event speaks only this.
    - display pos   : the (possibly sorted) visual slot, 0..ItemCount-1. It never
                      leaves the private/protected layer; it is what the pure
                      tyControls.ListView.Layout functions take and return.

  FOrder[displayPos] = itemIndex  (display -> item; identity when unsorted)
  FRank [itemIndex ] = displayPos  (item -> display; the O(1) inverse)

  Sorting only permutes FOrder; it never mutates Items and never calls a write
  method, because a shell data source is immutable. Selection is a bit array keyed
  by ITEM index, so it survives a re-sort and a view switch untouched.

  All geometry comes from tyControls.ListView.Layout: TyListItemRect is the single
  source of a cell rect and TyListItemAt is its verified inverse — this control
  never computes a cell rect by hand. Theme tokens are borrowed from the tree view
  (GetStyleTypeKey = 'TyTreeView'); zero new tokens are introduced. }
interface
uses
  Classes, SysUtils, Types, Math, DateUtils, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ScrollBar, tyControls.Columns, tyControls.ImageCollection,
  tyControls.ListView.Layout;

const
  { The RowHeight property's default, in logical px. Public because a published property's
    `default` directive needs a compile-time constant visible where the property is declared. }
  TyLvRowHeight = 22;

type
  { Per-item state flags. lisChecked/lisCut are surfaced through GetItemState so a
    theme/renderer can react; SP1 does not draw checkboxes (that is SP2). }
  TTyListItemState  = (lisChecked, lisCut, lisDisabled);
  TTyListItemStates = set of TTyListItemState;

  TTyListView  = class;   { forward }
  TTyListItems = class;   { forward }

  { ===================================================================
    TTyListItem — one row of the built-in collection (non-virtual mode)
    =================================================================== }
  TTyListItem = class(TCollectionItem)
  private
    FCaption:    string;
    FSubItems:   TStrings;
    FImageIndex: Integer;
    FData:       Pointer;
    FStates:     TTyListItemStates;
    procedure SetCaption(const AValue: string);
    procedure SetSubItems(AValue: TStrings);
    procedure SetImageIndex(AValue: Integer);
    procedure SetStates(AValue: TTyListItemStates);
    procedure SubItemsChanged(Sender: TObject);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(ASource: TPersistent); override;
    { Opaque per-item payload; not streamed. }
    property Data: Pointer read FData write FData;
    { Item state flags (checked/cut/disabled). Public (not published) — the built-in
      GetItemState reads it; the design-time contract only publishes text/image. }
    property States: TTyListItemStates read FStates write SetStates;
  published
    property Caption:    string  read FCaption    write SetCaption;
    { Columns 1..N (column 0 is Caption). }
    property SubItems:   TStrings read FSubItems  write SetSubItems;
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
  end;

  { ===================================================================
    TTyListItems — the built-in item collection
    =================================================================== }
  TTyListItems = class(TCollection)
  private
    FOwner:    TPersistent;
    FOnChange: TNotifyEvent;
    function GetItem(AIndex: Integer): TTyListItem;
    procedure SetItem(AIndex: Integer; AValue: TTyListItem);
  protected
    function GetOwner: TPersistent; override;
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TTyListItem;
    property Items[AIndex: Integer]: TTyListItem read GetItem write SetItem; default;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { Events. Every AIndex/AColumn is an ITEM index / column index; a var out-param is
    the LCL convention (mirrors TListView's owner-data events). }
  TTyListGetTextEvent  = procedure(Sender: TObject; AIndex, AColumn: Integer;
                                   var AText: string) of object;
  TTyListGetImageEvent = procedure(Sender: TObject; AIndex, AColumn: Integer;
                                   var AImageIndex: Integer) of object;
  TTyListGetStateEvent = procedure(Sender: TObject; AIndex: Integer;
                                   var AStates: TTyListItemStates) of object;
  TTyListCompareEvent  = procedure(Sender: TObject; AIndex1, AIndex2, AColumn: Integer;
                                   var ACompare: Integer) of object;
  TTyListColumnEvent   = procedure(Sender: TObject; AColumn: Integer) of object;
  TTyListItemEvent     = procedure(Sender: TObject; AIndex: Integer) of object;

  { ===================================================================
    TTyListView
    =================================================================== }
  TTyListView = class(TTyCustomControl)
  private
    { data }
    FItems:      TTyListItems;
    FItemCount:  Integer;         { OwnerData row count }
    FOwnerData:  Boolean;
    { view }
    FViewStyle:         TTyListViewStyle;
    FRowHeight:         Integer;   { logical px; report row height }
    FHeader:            TTyHeader;
    FShowColumnHeaders: Boolean;
    FGridLines:         Boolean;
    FRowSelect:         Boolean;
    FHotTrack:          Boolean;
    FLargeImages:       TTyVirtualImageList;
    FSmallImages:       TTyVirtualImageList;
    { sort }
    FSortColumn:    Integer;
    FSortDirection: TTySortDirection;
    FSortKind:      TTyListSortKind;
    FAutoSort:      Boolean;
    { selection / focus (all keyed by ITEM index) }
    FMultiSelect: Boolean;
    FItemIndex:   Integer;        { focused item index, -1 = none }
    FAnchor:      Integer;        { shift-range anchor, item index }
    FHot:         Integer;        { hot-tracked item index, -1 = none }
    { Cursor feedback over a header divider. We RESTORE what was there rather than forcing
      crDefault, so an app that set its own Cursor keeps it once the pointer moves off the
      divider. }
    FSavedCursor:      TCursor;
    FCursorOverridden: Boolean;
    FSelected:    array of Boolean;
    { order maps (private only) }
    FOrder:   array of Integer;   { display pos -> item index }
    FRank:    array of Integer;   { item index -> display pos }
    FSortBuf: array of Integer;   { merge-sort scratch }
    { scrolling (device pixels, both axes, 0..range) }
    FOffsetX, FOffsetY: Integer;
    FVScroll, FHScroll: TTyScrollBar;
    FSyncingScroll:     Boolean;
    { interaction state }
    { What the last MouseDown landed on. DblClick carries no coordinates, and a
      double-click in the header must not activate the focused ITEM. }
    FPressHit:     TTyListHitPart;
    FResizing:     Boolean;
    FResizeCol:    Integer;
    FResizeStartX: Integer;
    FResizeStartW: Integer;
    FMarquee:      Boolean;
    FMarqueeStart: TPoint;
    FMarqueeCur:   TPoint;
    { type-ahead }
    FSearchBuffer:  string;
    FSearchTime:    TDateTime;
    FSearchTimeout: Integer;
    { batching }
    FUpdateCount: Integer;
    { events }
    FOnGetItemText:   TTyListGetTextEvent;
    FOnGetItemImage:  TTyListGetImageEvent;
    FOnGetItemState:  TTyListGetStateEvent;
    FOnCompare:       TTyListCompareEvent;
    FOnColumnClick:   TTyListColumnEvent;
    FOnItemActivate:  TTyListItemEvent;
    FOnSelectItem:    TTyListItemEvent;
    FOnChange:        TNotifyEvent;

    procedure ItemsCollectionChanged(Sender: TObject);
    procedure HeaderChanged(Sender: TObject);
    procedure VScrollChange(Sender: TObject);
    procedure HScrollChange(Sender: TObject);

    procedure SetOwnerData(AValue: Boolean);
    procedure SetItemCount(AValue: Integer);
    procedure SetViewStyle(AValue: TTyListViewStyle);
    procedure SetRowHeight(AValue: Integer);
    procedure SetShowColumnHeaders(AValue: Boolean);
    procedure SetGridLines(AValue: Boolean);
    procedure SetRowSelect(AValue: Boolean);
    procedure SetHotTrack(AValue: Boolean);
    procedure SetMultiSelect(AValue: Boolean);
    procedure SetItems(AValue: TTyListItems);
    procedure SetHeader(AValue: TTyHeader);
    procedure SetSortColumn(AValue: Integer);
    procedure SetSortDirection(AValue: TTySortDirection);
    procedure SetSortKind(AValue: TTyListSortKind);
    procedure SetAutoSort(AValue: Boolean);
    procedure SetLargeImages(AValue: TTyVirtualImageList);
    procedure SetSmallImages(AValue: TTyVirtualImageList);
    function  GetItemIndex: Integer;
    procedure SetItemIndex(AValue: Integer);
    function  GetSelected(AIndex: Integer): Boolean;
    procedure SetSelected(AIndex: Integer; AValue: Boolean);

    { device-pixel scale from the control's DPI (mirrors ListBox: no painter needed) }
    function  Dpi: Integer;
    function  ScaleI(ALogical: Integer): Integer;
    function  UnscaleI(ADevice: Integer): Integer;

    { order / rank / selection housekeeping }
    procedure RebuildOrder;
    procedure SyncRank;
    procedure SyncArrays;
    procedure EnsureSelectedLen;
    procedure ClearAllBits;
    procedure ClampIndex(var AIndex: Integer);
    function  IsSelectedItem(AItem: Integer): Boolean; { item index }
    procedure SetSingleSelection(AItem: Integer);      { item index }
    procedure SelectRangeByDisplay(AAnchorItem, ATargetItem: Integer);
    procedure DoChange;
    procedure DoSelectItem(AItem: Integer);
    function  StatesFor(AItem: Integer): TTyStateSet;  { item index }

    { text accessor handed (as a callback) to the pure prefix-match loop. Its AIndex
      argument is a DISPLAY position so type-ahead follows the visible sort order. }
    function  GetDisplayText(ADisplayPos: Integer): string;

    { layout / metrics (all device pixels) }
    procedure FillMetrics(out AMetrics: TTyListMetrics; AViewW, AViewH: Integer);

    { compare + stable sort of FOrder }
    function  CompareItems(AItemA, AItemB: Integer): Integer;
    procedure MergeSortOrder(ALo, AHi: Integer);

    { rendering helpers }
    procedure RenderHeader(P: TTyPainter; const M: TTyListMetrics; const AFrame: TTyStyleSet);
    procedure RenderGridLines(P: TTyPainter; const M: TTyListMetrics; const AFrame: TTyStyleSet);
    procedure RenderMarquee(P: TTyPainter; const AFrame: TTyStyleSet);
    procedure RenderReportRow(P: TTyPainter; AIndex: Integer; const ACell: TRect;
      const AStyle: TTyStyleSet);
    procedure RenderFlowCell(P: TTyPainter; AIndex: Integer; const ACell: TRect;
      const AStyle: TTyStyleSet);
    procedure DrawImage(P: TTyPainter; AList: TTyVirtualImageList;
      AImageIndex, AX, AY, ASizePx: Integer);

    { mouse helpers }
    procedure ItemMouseSelect(AItem: Integer; Shift: TShiftState);
    procedure ApplyMarquee;
    procedure EndInteractions;
    function  MeasureTextW(ABmp: TBGRABitmap; const AText: string;
                           const AStyle: TTyStyleSet): Integer;   { device px }
    procedure SetDividerCursor(AOn: Boolean);
    procedure UpdateHoverCursor(X, Y: Integer);
  protected
    { The boundary between the two index spaces. FOrder/FRank themselves stay private --
      a descendant has no business reshuffling the display order -- but reading the map
      is exactly what a descendant (and a test) needs: TTyShellListView wants to know
      which item a display row is showing, without ever seeing the arrays. }
    function  DisplayToItem(APos: Integer): Integer;   { display pos -> item index, -1 if out of range }
    function  ItemToDisplay(AItem: Integer): Integer;  { item index -> display pos, -1 if out of range }

    { The embedded bars, read-only. A descendant may want to observe them, and the thumb's
      Max/PageSize contract is otherwise only verifiable by eye -- which is exactly how a
      wrong Max survived the first pass. }
    property VScrollBar: TTyScrollBar read FVScroll;
    property HScrollBar: TTyScrollBar read FHScroll;
    procedure UpdateScrollBars;
    { The device-px metrics of the current layout pass. A RenderItem override needs them. }
    function  CurrentMetrics: TTyListMetrics;

    { The single data intake. Painting, hit-testing, sorting and type-ahead call ONLY
      these four; there is no second "if OwnerData" anywhere else. Override two of them
      (count + text, say) to back the view with an external store. }
    function GetItemCount: Integer; virtual;
    function GetItemText(AIndex, AColumn: Integer): string; virtual;
    function GetItemImageIndex(AIndex, AColumn: Integer): Integer; virtual;
    function GetItemState(AIndex: Integer): TTyListItemStates; virtual;

    function GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;

    { The per-item paint seam TreeView never had. ACell is client coords; AStyle the
      resolved 'TyTreeNode' style for AStates. }
    procedure RenderItem(P: TTyPainter; AIndex: Integer; const ACell: TRect;
      const AStyle: TTyStyleSet; AStates: TTyStateSet); virtual;

    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Virtual-mode / batch bookkeeping. }
    procedure BeginUpdate;
    procedure EndUpdate;
    { Call after the app mutated its own store in OwnerData mode: resizes the order /
      rank / selection arrays, clamps focus/anchor/hot, re-sorts when AutoSort. }
    procedure ItemsChanged;

    procedure Sort;

    { Selection API — all ITEM indices. }
    function  SelCount: Integer;
    procedure SelectAll;
    procedure ClearSelection;
    { Iterate selected ITEM indices; pass -1 to get the first. }
    function  GetNextSelected(var AIndex: Integer): Boolean;
    property  Selected[AIndex: Integer]: Boolean read GetSelected write SetSelected;

    { Hit-testing / scrolling — ITEM indices in, ITEM indices out. }
    function  GetItemAt(X, Y: Integer): Integer;
    function  GetHitPart(X, Y: Integer): TTyListHitPart;
    procedure ScrollIntoView(AIndex: Integer);
    { Widen/narrow a column to fit its header caption and its cell text. Also bound to a
      double-click on the column's right divider. }
    procedure AutoFitColumn(AColumn: Integer);

    property ItemIndex: Integer read GetItemIndex write SetItemIndex;
  published
    property ViewStyle: TTyListViewStyle read FViewStyle write SetViewStyle default lvsReport;
    { Report row height in logical px, DPI-scaled at paint time. A file dialog wants
      denser rows than a general list, and there is no theme token for it. }
    property RowHeight: Integer read FRowHeight write SetRowHeight default TyLvRowHeight;
    property OwnerData: Boolean read FOwnerData write SetOwnerData default False;
    property ItemCount: Integer read FItemCount write SetItemCount default 0;
    property Items: TTyListItems read FItems write SetItems;
    property Header: TTyHeader read FHeader write SetHeader;
    property ShowColumnHeaders: Boolean read FShowColumnHeaders write SetShowColumnHeaders default True;
    property GridLines: Boolean read FGridLines write SetGridLines default False;
    property RowSelect: Boolean read FRowSelect write SetRowSelect default True;
    property HotTrack: Boolean read FHotTrack write SetHotTrack default False;
    property MultiSelect: Boolean read FMultiSelect write SetMultiSelect default False;
    property SortColumn: Integer read FSortColumn write SetSortColumn default -1;
    property SortDirection: TTySortDirection read FSortDirection write SetSortDirection default sdAscending;
    property SortKind: TTyListSortKind read FSortKind write SetSortKind default lskText;
    property AutoSort: Boolean read FAutoSort write SetAutoSort default True;
    property LargeImages: TTyVirtualImageList read FLargeImages write SetLargeImages;
    property SmallImages: TTyVirtualImageList read FSmallImages write SetSmallImages;

    property OnGetItemText:  TTyListGetTextEvent  read FOnGetItemText  write FOnGetItemText;
    property OnGetItemImage: TTyListGetImageEvent read FOnGetItemImage write FOnGetItemImage;
    property OnGetItemState: TTyListGetStateEvent read FOnGetItemState write FOnGetItemState;
    property OnCompare:      TTyListCompareEvent  read FOnCompare      write FOnCompare;
    property OnColumnClick:  TTyListColumnEvent   read FOnColumnClick  write FOnColumnClick;
    property OnItemActivate: TTyListItemEvent     read FOnItemActivate write FOnItemActivate;
    property OnSelectItem:   TTyListItemEvent     read FOnSelectItem   write FOnSelectItem;
    property OnChange:       TNotifyEvent         read FOnChange       write FOnChange;

    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  { Logical-px (96-PPI baseline) layout constants; each is scaled per-DPI. }
  TyLvHGap      = 10;   { horizontal gap between flow cells }
  TyLvVGap      = 8;    { vertical gap between flow cells / rows }
  TyLvPad       = 3;    { cell inner padding unit (fed to TyListCellSize) }
  TyLvLabelH    = 16;   { label line height }
  TyLvLargeIcon = 48;   { icon edge for lvsIcon / lvsTile }
  TyLvSmallIcon = 16;   { icon edge for the other styles }
  { Label column widths. The label gets a width of its OWN -- sizing a cell from the icon
    alone leaves room for about four characters, which is what the first real-machine pass
    of this control found. }
  TyLvIconLabelW  = 88;   { lvsIcon: label under the icon }
  TyLvSmallLabelW = 150;  { lvsSmallIcon / lvsList: label right of a small icon }
  { lvsTile: two lines right of a large icon. 150 keeps three tiles across a ~700px pane
    while still fitting a '2026-07-10 08:30' second line; 180 dropped it to two. }
  TyLvTileLabelW  = 150;
  TyLvTextMargin = 4;   { text inset inside a report cell / header cell }
  { Rubber-band translucency. The colour comes from the theme; see RenderMarquee. }
  TyLvMarqueeFillAlpha = 60;
  TyLvMarqueeEdgeAlpha = 180;

{ ---------------------------------------------------------------------------
  TTyListItem
  --------------------------------------------------------------------------- }

constructor TTyListItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FSubItems := TStringList.Create;
  TStringList(FSubItems).OnChange := @SubItemsChanged;
  FImageIndex := -1;
  FStates := [];
end;

destructor TTyListItem.Destroy;
begin
  FSubItems.Free;
  inherited Destroy;
end;

procedure TTyListItem.Assign(ASource: TPersistent);
var
  src: TTyListItem;
begin
  if ASource is TTyListItem then
  begin
    src := TTyListItem(ASource);
    FCaption := src.FCaption;
    FSubItems.Assign(src.FSubItems);
    FImageIndex := src.FImageIndex;
    FStates := src.FStates;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

function TTyListItem.GetDisplayName: string;
begin
  if FCaption <> '' then
    Result := FCaption
  else
    Result := inherited GetDisplayName;
end;

procedure TTyListItem.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

procedure TTyListItem.SetSubItems(AValue: TStrings);
begin
  FSubItems.Assign(AValue);
  Changed(False);
end;

procedure TTyListItem.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  Changed(False);
end;

procedure TTyListItem.SetStates(AValue: TTyListItemStates);
begin
  if FStates = AValue then Exit;
  FStates := AValue;
  Changed(False);
end;

procedure TTyListItem.SubItemsChanged(Sender: TObject);
begin
  Changed(False);
end;

{ ---------------------------------------------------------------------------
  TTyListItems
  --------------------------------------------------------------------------- }

constructor TTyListItems.Create(AOwner: TPersistent);
begin
  inherited Create(TTyListItem);
  FOwner := AOwner;
end;

function TTyListItems.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

function TTyListItems.Add: TTyListItem;
begin
  Result := TTyListItem(inherited Add);
end;

function TTyListItems.GetItem(AIndex: Integer): TTyListItem;
begin
  Result := TTyListItem(inherited Items[AIndex]);
end;

procedure TTyListItems.SetItem(AIndex: Integer; AValue: TTyListItem);
begin
  inherited Items[AIndex] := AValue;
end;

procedure TTyListItems.Notify(Item: TCollectionItem; Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyListItems.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if Assigned(FOnChange) then FOnChange(Self);
end;

{ ---------------------------------------------------------------------------
  TTyListView — lifecycle
  --------------------------------------------------------------------------- }

constructor TTyListView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TTyListItems.Create(Self);
  FItems.OnChange := @ItemsCollectionChanged;

  FViewStyle         := lvsReport;
  FRowHeight         := TyLvRowHeight;
  FShowColumnHeaders := True;
  FGridLines         := False;
  FRowSelect         := True;
  FHotTrack          := False;
  FMultiSelect       := False;
  FOwnerData         := False;
  FItemCount         := 0;

  FSortColumn    := -1;
  FSortDirection := sdAscending;
  FSortKind      := lskText;
  FAutoSort      := True;

  FItemIndex := -1;
  FAnchor    := -1;
  FHot       := -1;

  FResizeCol     := NoColumn;
  FSearchTimeout := 1000;

  { Header sub-object; wire its change hook so column edits re-layout. }
  FHeader := TTyHeader.Create;
  FHeader.OnChange := @HeaderChanged;

  { Two embedded scrollbars, eager + hidden + non-designable (see TreeView 1835). }
  FVScroll := TTyScrollBar.Create(Self);
  FVScroll.Parent            := Self;
  FVScroll.Kind              := sbVertical;
  FVScroll.AnimationsEnabled := False;
  FVScroll.OnChange          := @VScrollChange;
  FVScroll.ControlStyle      := FVScroll.ControlStyle + [csNoDesignVisible];
  FVScroll.Visible           := False;

  FHScroll := TTyScrollBar.Create(Self);
  FHScroll.Parent            := Self;
  FHScroll.Kind              := sbHorizontal;
  FHScroll.AnimationsEnabled := False;
  FHScroll.OnChange          := @HScrollChange;
  FHScroll.ControlStyle      := FHScroll.ControlStyle + [csNoDesignVisible];
  FHScroll.Visible           := False;

  TabStop := True;
  Width   := 280;
  Height  := 180;

  RebuildOrder;
end;

destructor TTyListView.Destroy;
begin
  FHeader.OnChange := nil;
  FHeader.Free;
  FItems.OnChange := nil;
  FItems.Free;
  { FVScroll / FHScroll owned by Self, freed by TComponent. }
  inherited Destroy;
end;

function TTyListView.GetStyleTypeKey: string;
begin
  { Borrow the tree tokens — zero new theme tokens. }
  Result := 'TyTreeView';
end;

procedure TTyListView.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  if FVScroll <> nil then FVScroll.Controller := AValue;
  if FHScroll <> nil then FHScroll.Controller := AValue;
end;

procedure TTyListView.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FLargeImages then FLargeImages := nil;
    if AComponent = FSmallImages then FSmallImages := nil;
  end;
end;

{ ---------------------------------------------------------------------------
  Data intake — the ONLY four readers
  --------------------------------------------------------------------------- }

function TTyListView.GetItemCount: Integer;
begin
  if FOwnerData then
    Result := FItemCount
  else
    Result := FItems.Count;
end;

function TTyListView.GetItemText(AIndex, AColumn: Integer): string;
begin
  Result := '';
  if FOwnerData then
  begin
    if Assigned(FOnGetItemText) then
      FOnGetItemText(Self, AIndex, AColumn, Result);
    Exit;
  end;
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  if AColumn <= 0 then
    Result := FItems[AIndex].Caption
  else if AColumn - 1 < FItems[AIndex].SubItems.Count then
    Result := FItems[AIndex].SubItems[AColumn - 1];
end;

function TTyListView.GetItemImageIndex(AIndex, AColumn: Integer): Integer;
begin
  Result := -1;
  if FOwnerData then
  begin
    if Assigned(FOnGetItemImage) then
      FOnGetItemImage(Self, AIndex, AColumn, Result);
    Exit;
  end;
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  { The built-in item carries a single image, shown in the main/first column. }
  if AColumn <= 0 then
    Result := FItems[AIndex].ImageIndex;
end;

function TTyListView.GetItemState(AIndex: Integer): TTyListItemStates;
begin
  Result := [];
  if FOwnerData then
  begin
    if Assigned(FOnGetItemState) then
      FOnGetItemState(Self, AIndex, Result);
    Exit;
  end;
  if (AIndex >= 0) and (AIndex < FItems.Count) then
    Result := FItems[AIndex].States;
end;

{ ---------------------------------------------------------------------------
  Scale helpers
  --------------------------------------------------------------------------- }

function TTyListView.Dpi: Integer;
begin
  Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyListView.ScaleI(ALogical: Integer): Integer;
begin
  Result := MulDiv(ALogical, Dpi, 96);
end;

function TTyListView.UnscaleI(ADevice: Integer): Integer;
begin
  Result := MulDiv(ADevice, 96, Dpi);
end;

{ ---------------------------------------------------------------------------
  Order / rank / selection housekeeping
  --------------------------------------------------------------------------- }

procedure TTyListView.RebuildOrder;
var
  cnt, i: Integer;
begin
  cnt := GetItemCount;
  SetLength(FOrder, cnt);
  SetLength(FRank, cnt);
  for i := 0 to cnt - 1 do
  begin
    FOrder[i] := i;   { display i shows item i }
    FRank[i]  := i;   { item i sits at display i }
  end;
end;

procedure TTyListView.SyncRank;
var
  p: Integer;
begin
  { Rebuild the inverse map after FOrder was permuted. }
  if Length(FRank) <> Length(FOrder) then
    SetLength(FRank, Length(FOrder));
  for p := 0 to High(FOrder) do
    FRank[FOrder[p]] := p;   { item FOrder[p] now lives at display p }
end;

procedure TTyListView.SyncArrays;
var
  cnt: Integer;
begin
  cnt := GetItemCount;
  if (Length(FOrder) <> cnt) or (Length(FRank) <> cnt) then
  begin
    RebuildOrder;
    if FAutoSort and (FSortColumn >= 0) then
      Sort;   { re-permutes FOrder + SyncRank }
  end;
  if Length(FSelected) <> cnt then
    SetLength(FSelected, cnt);
  ClampIndex(FItemIndex);
  ClampIndex(FAnchor);
  ClampIndex(FHot);
end;

procedure TTyListView.EnsureSelectedLen;
begin
  if Length(FSelected) <> GetItemCount then
    SetLength(FSelected, GetItemCount);
end;

procedure TTyListView.ClearAllBits;
var
  i: Integer;
begin
  EnsureSelectedLen;
  for i := 0 to High(FSelected) do
    FSelected[i] := False;
end;

procedure TTyListView.ClampIndex(var AIndex: Integer);
var
  cnt: Integer;
begin
  cnt := GetItemCount;
  if AIndex >= cnt then AIndex := cnt - 1;   { cnt=0 -> -1 }
  if AIndex < -1 then AIndex := -1;
end;

function TTyListView.DisplayToItem(APos: Integer): Integer;
begin
  { display pos -> item index (bounds-guarded so stale indices never crash) }
  if (APos >= 0) and (APos < Length(FOrder)) then
    Result := FOrder[APos]
  else
    Result := -1;
end;

function TTyListView.ItemToDisplay(AItem: Integer): Integer;
begin
  { item index -> display pos (bounds-guarded) }
  if (AItem >= 0) and (AItem < Length(FRank)) then
    Result := FRank[AItem]
  else
    Result := -1;
end;

function TTyListView.IsSelectedItem(AItem: Integer): Boolean;
begin
  if (AItem < 0) or (AItem >= GetItemCount) then Exit(False);
  if FMultiSelect then
  begin
    if AItem < Length(FSelected) then
      Result := FSelected[AItem]
    else
      Result := False;
  end
  else
    Result := (AItem = FItemIndex);
end;

procedure TTyListView.SetSingleSelection(AItem: Integer);
begin
  EnsureSelectedLen;
  ClearAllBits;
  if (AItem >= 0) and FMultiSelect and (AItem < Length(FSelected)) then
    FSelected[AItem] := True;
  FItemIndex := AItem;
  FAnchor    := AItem;
  Invalidate;
  DoChange;
  DoSelectItem(AItem);
end;

procedure TTyListView.SelectRangeByDisplay(AAnchorItem, ATargetItem: Integer);
var
  aPos, tPos, lo, hi, p, it: Integer;
begin
  EnsureSelectedLen;
  if AAnchorItem < 0 then AAnchorItem := ATargetItem;
  aPos := ItemToDisplay(AAnchorItem);   { item index -> display pos }
  tPos := ItemToDisplay(ATargetItem);   { item index -> display pos }
  if TyListRangeBounds(aPos, tPos, lo, hi) then
  begin
    ClearAllBits;
    for p := lo to hi do
    begin
      it := DisplayToItem(p);           { display pos -> item index }
      if (it >= 0) and (it < Length(FSelected)) then
        FSelected[it] := True;
    end;
  end;
end;

procedure TTyListView.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyListView.DoSelectItem(AItem: Integer);
begin
  if Assigned(FOnSelectItem) then FOnSelectItem(Self, AItem);
end;

function TTyListView.StatesFor(AItem: Integer): TTyStateSet;
begin
  Result := [];
  if not Enabled then
  begin
    Include(Result, tysDisabled);
    Exit;
  end;
  if IsSelectedItem(AItem) then
    Include(Result, tysSelected);
  if FHotTrack and (AItem = FHot) then
    Include(Result, tysHover);
  if Result = [] then
    Include(Result, tysNormal);
end;

function TTyListView.GetDisplayText(ADisplayPos: Integer): string;
begin
  { callback domain is DISPLAY position -> map to item, then read column 0 }
  Result := GetItemText(DisplayToItem(ADisplayPos), 0);
end;

{ ---------------------------------------------------------------------------
  Metrics + scrollbars
  --------------------------------------------------------------------------- }

procedure TTyListView.FillMetrics(out AMetrics: TTyListMetrics; AViewW, AViewH: Integer);
var
  sz: TSize;
  icon: Integer;
begin
  AMetrics := Default(TTyListMetrics);
  AMetrics.ViewStyle := FViewStyle;
  AMetrics.ViewportW := AViewW;
  AMetrics.ViewportH := AViewH;
  AMetrics.HGap := ScaleI(TyLvHGap);
  AMetrics.VGap := ScaleI(TyLvVGap);
  AMetrics.Pad  := ScaleI(TyLvPad);
  if FViewStyle in [lvsIcon, lvsTile] then icon := TyLvLargeIcon else icon := TyLvSmallIcon;
  AMetrics.IconPx := ScaleI(icon);
  AMetrics.LabelH := ScaleI(TyLvLabelH);
  case FViewStyle of
    lvsIcon: AMetrics.LabelW := ScaleI(TyLvIconLabelW);
    lvsTile: AMetrics.LabelW := ScaleI(TyLvTileLabelW);
  else
    AMetrics.LabelW := ScaleI(TyLvSmallLabelW);
  end;
  AMetrics.RowH   := ScaleI(FRowHeight);
  if (FViewStyle = lvsReport) and FShowColumnHeaders and (hoVisible in FHeader.Options) then
    AMetrics.HeaderH := ScaleI(FHeader.Height)
  else
    AMetrics.HeaderH := 0;
  AMetrics.ReportWidth := ScaleI(FHeader.Columns.TotalWidth);
  sz := TyListCellSize(AMetrics);
  AMetrics.CellW := sz.cx;
  AMetrics.CellH := sz.cy;
end;

function TTyListView.CurrentMetrics: TTyListMetrics;
var
  vw, vh, sb: Integer;
begin
  sb := ScaleI(TyScrollbarSize);
  vw := ClientWidth;
  vh := ClientHeight;
  if (FVScroll <> nil) and FVScroll.Visible then Dec(vw, sb);
  if (FHScroll <> nil) and FHScroll.Visible then Dec(vh, sb);
  if vw < 0 then vw := 0;
  if vh < 0 then vh := 0;
  FillMetrics(Result, vw, vh);
end;

procedure TTyListView.UpdateScrollBars;
var
  cnt, sb, vw, vh, pass, regionH, maxV, maxH: Integer;
  m: TTyListMetrics;
  ext: TSize;
  needV, needH, vertCap, horzCap: Boolean;
begin
  if csDestroying in ComponentState then Exit;
  cnt := GetItemCount;
  sb  := ScaleI(TyScrollbarSize);
  { Which axis can scroll at all (see the flow table in the Layout unit). }
  vertCap := FViewStyle in [lvsReport, lvsIcon, lvsSmallIcon, lvsTile];
  horzCap := FViewStyle in [lvsReport, lvsList];

  needV := False;
  needH := False;
  vw := ClientWidth;
  vh := ClientHeight;
  { Two passes converge the cross-steal (a bar on one axis shrinks the other). }
  for pass := 0 to 1 do
  begin
    vw := ClientWidth  - IfThen(needV, sb, 0);
    vh := ClientHeight - IfThen(needH, sb, 0);
    if vw < 0 then vw := 0;
    if vh < 0 then vh := 0;
    FillMetrics(m, vw, vh);
    ext := TyListContentExtent(cnt, m);
    needV := vertCap and (ext.cy > vh - m.HeaderH);
    needH := horzCap and (ext.cx > vw);
  end;

  vw := ClientWidth  - IfThen(needV, sb, 0);
  vh := ClientHeight - IfThen(needH, sb, 0);
  if vw < 0 then vw := 0;
  if vh < 0 then vh := 0;
  FillMetrics(m, vw, vh);
  ext := TyListContentExtent(cnt, m);

  regionH := vh - m.HeaderH;
  if regionH < 0 then regionH := 0;

  { Clamp scroll offsets to the (device-pixel) content range. }
  maxV := ext.cy - regionH;  if maxV < 0 then maxV := 0;
  maxH := ext.cx - vw;       if maxH < 0 then maxH := 0;
  if FOffsetY > maxV then FOffsetY := maxV;
  if FOffsetY < 0 then FOffsetY := 0;
  if FOffsetX > maxH then FOffsetX := maxH;
  if FOffsetX < 0 then FOffsetX := 0;

  { Vertical bar. }
  if needV then
  begin
    FVScroll.Width := sb;
    FVScroll.Controller := Self.Controller;
    if not FVScroll.Dragging then
      FVScroll.SetBounds(ClientWidth - sb, 0, sb, ClientHeight - IfThen(needH, sb, 0));
    FSyncingScroll := True;
    try
      FVScroll.Min      := 0;
      { Max is the maximum POSITION, not the content size -- TyScrollThumbRect sizes the
        thumb as PageSize/((Max-Min)+PageSize) and only reaches the track end at
        Position = Max. Feeding it ext.cy would undersize the thumb, leave a permanent gap
        below it, and make a drag to the bottom snap back. Same convention as TTyListBox. }
      FVScroll.Max      := maxV;
      FVScroll.PageSize := regionH;
      FVScroll.Position := FOffsetY;
    finally
      FSyncingScroll := False;
    end;
    FVScroll.Visible := True;
  end
  else
  begin
    FVScroll.Visible := False;
    FOffsetY := 0;
  end;

  { Horizontal bar. }
  if needH then
  begin
    FHScroll.Height := sb;
    FHScroll.Controller := Self.Controller;
    if not FHScroll.Dragging then
      FHScroll.SetBounds(0, ClientHeight - sb, ClientWidth - IfThen(needV, sb, 0), sb);
    FSyncingScroll := True;
    try
      FHScroll.Min      := 0;
      FHScroll.Max      := maxH;   { maximum position, not content width -- see above }
      FHScroll.PageSize := vw;
      FHScroll.Position := FOffsetX;
    finally
      FSyncingScroll := False;
    end;
    FHScroll.Visible := True;
  end
  else
  begin
    FHScroll.Visible := False;
    FOffsetX := 0;
  end;
end;

procedure TTyListView.VScrollChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FOffsetY := FVScroll.Position;
  Invalidate;
end;

procedure TTyListView.HScrollChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FOffsetX := FHScroll.Position;
  Invalidate;
end;

{ ---------------------------------------------------------------------------
  Sorting
  --------------------------------------------------------------------------- }

function TTyListView.CompareItems(AItemA, AItemB: Integer): Integer;
var
  c: Integer;
begin
  if Assigned(FOnCompare) then
  begin
    c := 0;
    FOnCompare(Self, AItemA, AItemB, FSortColumn, c);
    { The built-in comparator bakes direction in; a user handler does not, so we
      apply it here. The tie-break below is NEVER flipped, keeping the sort stable
      in both directions. }
    if FSortDirection = sdDescending then c := -c;
  end
  else
    c := TyListCompareCells(GetItemText(AItemA, FSortColumn),
                            GetItemText(AItemB, FSortColumn),
                            FSortKind, FSortDirection);
  if c = 0 then
    c := AItemA - AItemB;   { stable tie-break by item index }
  Result := c;
end;

procedure TTyListView.MergeSortOrder(ALo, AHi: Integer);
var
  mid, i, j, k: Integer;
begin
  if ALo >= AHi then Exit;
  mid := (ALo + AHi) div 2;
  MergeSortOrder(ALo, mid);
  MergeSortOrder(mid + 1, AHi);
  i := ALo; j := mid + 1; k := ALo;
  while (i <= mid) and (j <= AHi) do
  begin
    if CompareItems(FOrder[i], FOrder[j]) <= 0 then
    begin
      FSortBuf[k] := FOrder[i]; Inc(i);
    end
    else
    begin
      FSortBuf[k] := FOrder[j]; Inc(j);
    end;
    Inc(k);
  end;
  while i <= mid do begin FSortBuf[k] := FOrder[i]; Inc(i); Inc(k); end;
  while j <= AHi do begin FSortBuf[k] := FOrder[j]; Inc(j); Inc(k); end;
  for k := ALo to AHi do
    FOrder[k] := FSortBuf[k];
end;

procedure TTyListView.Sort;
var
  cnt: Integer;
begin
  cnt := GetItemCount;
  if Length(FOrder) <> cnt then
    RebuildOrder;
  if FSortColumn < 0 then
  begin
    { Not sorting: restore identity order (selection/focus untouched). }
    RebuildOrder;
    Invalidate;
    Exit;
  end;
  if cnt > 1 then
  begin
    SetLength(FSortBuf, cnt);
    MergeSortOrder(0, cnt - 1);
    SetLength(FSortBuf, 0);
  end;
  SyncRank;
  Invalidate;
end;

{ ---------------------------------------------------------------------------
  Public API — batching / virtual mode
  --------------------------------------------------------------------------- }

procedure TTyListView.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TTyListView.EndUpdate;
begin
  if FUpdateCount > 0 then Dec(FUpdateCount);
  if FUpdateCount = 0 then
    ItemsChanged;
end;

procedure TTyListView.ItemsChanged;
var
  cnt: Integer;
begin
  if FUpdateCount > 0 then Exit;
  cnt := GetItemCount;
  SetLength(FSelected, cnt);   { keep existing bits; new slots default False }
  RebuildOrder;                { identity order + rank }
  ClampIndex(FItemIndex);
  ClampIndex(FAnchor);
  ClampIndex(FHot);
  if FAutoSort and (FSortColumn >= 0) then
    Sort;                      { re-permute FOrder + SyncRank }
  Invalidate;
end;

procedure TTyListView.ItemsCollectionChanged(Sender: TObject);
begin
  if FOwnerData then Exit;     { the collection is dormant in virtual mode }
  ItemsChanged;
end;

procedure TTyListView.HeaderChanged(Sender: TObject);
begin
  if csLoading in ComponentState then Exit;
  Invalidate;
end;

{ ---------------------------------------------------------------------------
  Public API — selection
  --------------------------------------------------------------------------- }

function TTyListView.SelCount: Integer;
var
  i: Integer;
begin
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    Result := 0;
    for i := 0 to High(FSelected) do
      if FSelected[i] then Inc(Result);
  end
  else if (FItemIndex >= 0) and (FItemIndex < GetItemCount) then
    Result := 1
  else
    Result := 0;
end;

procedure TTyListView.SelectAll;
var
  i: Integer;
  anyChanged: Boolean;
begin
  if not FMultiSelect then Exit;
  EnsureSelectedLen;
  anyChanged := False;
  for i := 0 to High(FSelected) do
    if not FSelected[i] then begin FSelected[i] := True; anyChanged := True; end;
  if anyChanged then
  begin
    Invalidate;
    DoChange;
  end;
end;

procedure TTyListView.ClearSelection;
var
  i: Integer;
  anyChanged: Boolean;
begin
  anyChanged := False;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    for i := 0 to High(FSelected) do
      if FSelected[i] then begin FSelected[i] := False; anyChanged := True; end;
  end;
  if FItemIndex <> -1 then
  begin
    FItemIndex := -1;
    anyChanged := True;
  end;
  if anyChanged then
  begin
    Invalidate;
    DoChange;
  end;
end;

function TTyListView.GetNextSelected(var AIndex: Integer): Boolean;
var
  i, cnt: Integer;
begin
  { AIndex is an ITEM index; pass -1 to get the first. }
  cnt := GetItemCount;
  Result := False;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    for i := AIndex + 1 to cnt - 1 do
      if (i >= 0) and (i < Length(FSelected)) and FSelected[i] then
      begin
        AIndex := i;
        Exit(True);
      end;
  end
  else if (FItemIndex >= 0) and (FItemIndex < cnt) and (AIndex < FItemIndex) then
  begin
    AIndex := FItemIndex;
    Exit(True);
  end;
end;

function TTyListView.GetItemIndex: Integer;
begin
  Result := FItemIndex;
end;

procedure TTyListView.SetItemIndex(AValue: Integer);
begin
  if (AValue < 0) or (AValue >= GetItemCount) then AValue := -1;
  if FItemIndex = AValue then Exit;
  SetSingleSelection(AValue);
end;

function TTyListView.GetSelected(AIndex: Integer): Boolean;
begin
  Result := IsSelectedItem(AIndex);
end;

procedure TTyListView.SetSelected(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= GetItemCount) then Exit;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    if FSelected[AIndex] = AValue then Exit;
    FSelected[AIndex] := AValue;
    Invalidate;
    DoChange;
  end
  else if AValue then
    SetSingleSelection(AIndex);
end;

{ ---------------------------------------------------------------------------
  Public API — hit-testing / scrolling
  --------------------------------------------------------------------------- }

function TTyListView.GetItemAt(X, Y: Integer): Integer;
var
  m: TTyListMetrics;
  pos: Integer;
begin
  SyncArrays;
  m := CurrentMetrics;
  { display pos from the pure inverse, then map back to a stable item index }
  pos := TyListItemAt(Point(X, Y), GetItemCount, m, FOffsetX, FOffsetY);
  Result := DisplayToItem(pos);   { display pos -> item index (-1 stays -1) }
end;

function TTyListView.GetHitPart(X, Y: Integer): TTyListHitPart;
var
  m: TTyListMetrics;
  logX, logScroll: Integer;
begin
  SyncArrays;
  m := CurrentMetrics;
  if (FViewStyle = lvsReport) and (m.HeaderH > 0) and (Y < m.HeaderH) then
  begin
    logX      := UnscaleI(X);          { device -> logical (column model is logical) }
    logScroll := UnscaleI(FOffsetX);
    if (hoColumnResize in FHeader.Options) and
       (FHeader.Columns.DetermineSplitterIndex(logX, logScroll) <> NoColumn) then
      Result := lhpDivider
    else
      Result := lhpHeader;
    Exit;
  end;
  if TyListItemAt(Point(X, Y), GetItemCount, m, FOffsetX, FOffsetY) >= 0 then
    Result := lhpLabel
  else
    Result := lhpNowhere;
end;

procedure TTyListView.ScrollIntoView(AIndex: Integer);
var
  m: TTyListMetrics;
  pos, regionH: Integer;
  rect0: TRect;
  vertCap, horzCap: Boolean;
begin
  SyncArrays;
  if (AIndex < 0) or (AIndex >= GetItemCount) then Exit;
  m := CurrentMetrics;
  pos := ItemToDisplay(AIndex);        { item index -> display pos }
  if pos < 0 then Exit;
  { Cell at zero scroll = its content-space rect (plus HeaderH). }
  rect0 := TyListItemRect(pos, GetItemCount, m, 0, 0);
  regionH := m.ViewportH - m.HeaderH;
  if regionH < 0 then regionH := 0;

  vertCap := FViewStyle in [lvsReport, lvsIcon, lvsSmallIcon, lvsTile];
  horzCap := FViewStyle in [lvsReport, lvsList];

  if vertCap then
  begin
    if rect0.Top - FOffsetY < m.HeaderH then
      FOffsetY := rect0.Top - m.HeaderH
    else if rect0.Bottom - FOffsetY > m.ViewportH then
      FOffsetY := rect0.Bottom - m.ViewportH;
    if FOffsetY < 0 then FOffsetY := 0;
  end;
  if horzCap then
  begin
    if rect0.Left - FOffsetX < 0 then
      FOffsetX := rect0.Left
    else if rect0.Right - FOffsetX > m.ViewportW then
      FOffsetX := rect0.Right - m.ViewportW;
    if FOffsetX < 0 then FOffsetX := 0;
  end;

  UpdateScrollBars;
  Invalidate;
end;

{ ---------------------------------------------------------------------------
  Property setters
  --------------------------------------------------------------------------- }

procedure TTyListView.SetOwnerData(AValue: Boolean);
begin
  if FOwnerData = AValue then Exit;
  FOwnerData := AValue;
  ItemsChanged;
end;

procedure TTyListView.SetItemCount(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FItemCount = AValue then Exit;
  FItemCount := AValue;
  if FOwnerData then
    ItemsChanged;
end;

procedure TTyListView.SetRowHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FRowHeight = AValue then Exit;
  FRowHeight := AValue;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyListView.SetViewStyle(AValue: TTyListViewStyle);
begin
  if FViewStyle = AValue then Exit;
  FViewStyle := AValue;
  { A view switch changes the scrolling axis: reset offsets so nothing is stranded. }
  FOffsetX := 0;
  FOffsetY := 0;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyListView.SetShowColumnHeaders(AValue: Boolean);
begin
  if FShowColumnHeaders = AValue then Exit;
  FShowColumnHeaders := AValue;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyListView.SetGridLines(AValue: Boolean);
begin
  if FGridLines = AValue then Exit;
  FGridLines := AValue;
  Invalidate;
end;

procedure TTyListView.SetRowSelect(AValue: Boolean);
begin
  if FRowSelect = AValue then Exit;
  FRowSelect := AValue;
  Invalidate;
end;

procedure TTyListView.SetHotTrack(AValue: Boolean);
begin
  if FHotTrack = AValue then Exit;
  FHotTrack := AValue;
  if not FHotTrack then FHot := -1;
  Invalidate;
end;

procedure TTyListView.SetMultiSelect(AValue: Boolean);
var
  i: Integer;
begin
  if FMultiSelect = AValue then Exit;
  EnsureSelectedLen;

  if not AValue then
  begin
    { Collapsing to single. The survivor is the focused item. A programmatic
      `Selected[i] := True` sets a bit without moving the focus, so a multi-selection can
      exist with no focused item at all -- in that case adopt the first selected item
      rather than silently discarding the whole selection. }
    if (FItemIndex < 0) or (FItemIndex >= GetItemCount) then
    begin
      FItemIndex := -1;
      for i := 0 to High(FSelected) do
        if FSelected[i] then
        begin
          FItemIndex := i;
          Break;
        end;
    end;
    FAnchor := FItemIndex;
  end;

  FMultiSelect := AValue;
  { Clean slate so stale multi bits never resurface. In single mode the selection IS
    FItemIndex (see IsSelectedItem/SelCount), so there is no bit to set. }
  ClearAllBits;
  if FMultiSelect and (FItemIndex >= 0) and (FItemIndex < Length(FSelected)) then
    FSelected[FItemIndex] := True;
  Invalidate;
  DoChange;
end;

procedure TTyListView.SetItems(AValue: TTyListItems);
begin
  FItems.Assign(AValue);
  ItemsChanged;
end;

procedure TTyListView.SetHeader(AValue: TTyHeader);
begin
  FHeader.Assign(AValue);
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyListView.SetSortColumn(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;
  if FSortColumn = AValue then Exit;
  FSortColumn := AValue;
  Sort;
end;

procedure TTyListView.SetSortDirection(AValue: TTySortDirection);
begin
  if FSortDirection = AValue then Exit;
  FSortDirection := AValue;
  if FSortColumn >= 0 then Sort else Invalidate;
end;

procedure TTyListView.SetSortKind(AValue: TTyListSortKind);
begin
  if FSortKind = AValue then Exit;
  FSortKind := AValue;
  if FSortColumn >= 0 then Sort;
end;

procedure TTyListView.SetAutoSort(AValue: Boolean);
begin
  if FAutoSort = AValue then Exit;
  FAutoSort := AValue;
end;

procedure TTyListView.SetLargeImages(AValue: TTyVirtualImageList);
begin
  if FLargeImages = AValue then Exit;
  if FLargeImages <> nil then FLargeImages.RemoveFreeNotification(Self);
  FLargeImages := AValue;
  if FLargeImages <> nil then FLargeImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyListView.SetSmallImages(AValue: TTyVirtualImageList);
begin
  if FSmallImages = AValue then Exit;
  if FSmallImages <> nil then FSmallImages.RemoveFreeNotification(Self);
  FSmallImages := AValue;
  if FSmallImages <> nil then FSmallImages.FreeNotification(Self);
  Invalidate;
end;

{ ---------------------------------------------------------------------------
  Rendering
  --------------------------------------------------------------------------- }

procedure TTyListView.DrawImage(P: TTyPainter; AList: TTyVirtualImageList;
  AImageIndex, AX, AY, ASizePx: Integer);
var
  bmp: TBGRABitmap;
begin
  if (AList = nil) or (AImageIndex < 0) or (ASizePx <= 0) then Exit;
  bmp := AList.RenderIndex(AImageIndex, ASizePx);
  try
    P.Bitmap.PutImage(AX, AY, bmp, dmDrawWithTransparency);
  finally
    bmp.Free;
  end;
end;

procedure TTyListView.RenderReportRow(P: TTyPainter; AIndex: Integer; const ACell: TRect;
  const AStyle: TTyStyleSet);
var
  posIdx, colIdx, colLeft, colRight, textLeft, mainCol, imgPx, ii: Integer;
  col: TTyColumn;
  txt: string;
  tc: TTyColor;
  tr: TRect;
begin
  mainCol := FHeader.MainColumn;
  if tpTextColor in AStyle.Present then tc := AStyle.TextColor
  else tc := CurrentStyle.TextColor;
  imgPx := ScaleI(TyLvSmallIcon);
  for posIdx := 0 to FHeader.Columns.Count - 1 do
  begin
    col := FHeader.Columns.ColumnByPosition(posIdx);
    if col = nil then Continue;
    if not (coVisible in col.Options) then Continue;
    colIdx := col.Index;
    { report cell rect Left = -FOffsetX; column x = that + Scale(col.Left) }
    colLeft  := ACell.Left + ScaleI(col.Left);
    colRight := colLeft + ScaleI(col.Width);
    textLeft := colLeft + ScaleI(TyLvTextMargin);
    if colIdx = mainCol then
    begin
      ii := GetItemImageIndex(AIndex, colIdx);
      if (FSmallImages <> nil) and (ii >= 0) then
      begin
        DrawImage(P, FSmallImages, ii, colLeft + ScaleI(2),
          ACell.Top + (ACell.Bottom - ACell.Top - imgPx) div 2, imgPx);
        textLeft := colLeft + ScaleI(TyLvTextMargin) + imgPx + ScaleI(2);
      end;
    end;
    txt := GetItemText(AIndex, colIdx);
    tr := Rect(textLeft, ACell.Top, colRight - ScaleI(TyLvTextMargin), ACell.Bottom);
    if tr.Left < tr.Right then
      P.DrawText(tr, txt, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
        tc, col.Alignment, tlCenter, True);
  end;
end;

procedure TTyListView.RenderFlowCell(P: TTyPainter; AIndex: Integer; const ACell: TRect;
  const AStyle: TTyStyleSet);
var
  imgList: TTyVirtualImageList;
  imgPx, ii, pad, ix, iy, tx: Integer;
  tc: TTyColor;
  lbl, sub: string;
  tr: TRect;
begin
  if tpTextColor in AStyle.Present then tc := AStyle.TextColor
  else tc := CurrentStyle.TextColor;
  pad := ScaleI(TyLvPad);
  { Must agree with FillMetrics, which sizes the cell from the LARGE icon for both lvsIcon
    and lvsTile. Testing only lvsIcon here drew a 16px glyph inside a cell laid out for 48. }
  if FViewStyle in [lvsIcon, lvsTile] then
  begin
    imgList := FLargeImages; imgPx := ScaleI(TyLvLargeIcon);
  end
  else
  begin
    imgList := FSmallImages; imgPx := ScaleI(TyLvSmallIcon);
  end;
  ii  := GetItemImageIndex(AIndex, 0);
  lbl := GetItemText(AIndex, 0);
  case FViewStyle of
    lvsIcon:
      begin
        { icon centered on top, label below }
        ix := ACell.Left + (ACell.Right - ACell.Left - imgPx) div 2;
        iy := ACell.Top + 2 * pad;
        DrawImage(P, imgList, ii, ix, iy, imgPx);
        tr := Rect(ACell.Left + pad, iy + imgPx + pad, ACell.Right - pad, ACell.Bottom - pad);
        if tr.Top < tr.Bottom then
          P.DrawText(tr, lbl, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
            tc, taCenter, tlTop, True);
      end;
    lvsTile:
      begin
        { icon at left, two text lines at right }
        ix := ACell.Left + pad;
        iy := ACell.Top + (ACell.Bottom - ACell.Top - imgPx) div 2;
        DrawImage(P, imgList, ii, ix, iy, imgPx);
        tx  := ix + imgPx + 2 * pad;
        sub := GetItemText(AIndex, 1);
        tr := Rect(tx, ACell.Top + pad, ACell.Right - pad, ACell.Top + pad + ScaleI(TyLvLabelH));
        if tr.Left < tr.Right then
          P.DrawText(tr, lbl, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
            tc, taLeftJustify, tlCenter, True);
        tr := Rect(tx, tr.Bottom, ACell.Right - pad, ACell.Bottom - pad);
        if (tr.Left < tr.Right) and (sub <> '') then
          P.DrawText(tr, sub, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
            tc, taLeftJustify, tlCenter, True);
      end;
  else
    begin
      { lvsSmallIcon / lvsList: icon at left, single label at right }
      ix := ACell.Left + pad;
      iy := ACell.Top + (ACell.Bottom - ACell.Top - imgPx) div 2;
      DrawImage(P, imgList, ii, ix, iy, imgPx);
      tx := ix + imgPx + 2 * pad;
      tr := Rect(tx, ACell.Top, ACell.Right - pad, ACell.Bottom);
      if tr.Left < tr.Right then
        P.DrawText(tr, lbl, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
          tc, taLeftJustify, tlCenter, True);
    end;
  end;
end;

procedure TTyListView.RenderItem(P: TTyPainter; AIndex: Integer; const ACell: TRect;
  const AStyle: TTyStyleSet; AStates: TTyStateSet);
begin
  { Highlight only selected / hovered cells (a normal TyTreeNode has no row fill). }
  if ((tysSelected in AStates) or (tysHover in AStates)) and (tpBackground in AStyle.Present) then
    P.FillBackground(ACell, AStyle.Background, 0);
  if FViewStyle = lvsReport then
    RenderReportRow(P, AIndex, ACell, AStyle)
  else
    RenderFlowCell(P, AIndex, ACell, AStyle);
end;

procedure TTyListView.RenderHeader(P: TTyPainter; const M: TTyListMetrics;
  const AFrame: TTyStyleSet);
var
  hb, hs: TTyStyleSet;
  posIdx, colLeft, colRight, sortSz: Integer;
  col: TTyColumn;
  cellR, tr, sortR: TRect;
  tc: TTyColor;
  useSec: Boolean;
  border: TBGRAPixel;
begin
  hb := ActiveController.Model.ResolveStyle('TyTreeHeader', '', []);
  hs := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', []);
  border := TyColorToBGRA(AFrame.BorderColor);

  { band background }
  if tpBackground in hb.Present then
    P.FillBackground(Rect(0, 0, M.ViewportW, M.HeaderH), hb.Background, 0)
  else if tpBackground in AFrame.Present then
    P.FillBackground(Rect(0, 0, M.ViewportW, M.HeaderH), AFrame.Background, 0);

  useSec := tpTextColor in hs.Present;
  if useSec then tc := hs.TextColor else tc := AFrame.TextColor;

  for posIdx := 0 to FHeader.Columns.Count - 1 do
  begin
    col := FHeader.Columns.ColumnByPosition(posIdx);
    if col = nil then Continue;
    if not (coVisible in col.Options) then Continue;
    colLeft  := ScaleI(col.Left) - FOffsetX;
    colRight := colLeft + ScaleI(col.Width);
    if colRight <= 0 then Continue;
    if colLeft >= M.ViewportW then Continue;
    cellR := Rect(colLeft, 0, colRight, M.HeaderH);
    if cellR.Left < 0 then cellR.Left := 0;
    if cellR.Right > M.ViewportW then cellR.Right := M.ViewportW;

    if tpBackground in hs.Present then
      P.FillBackground(cellR, hs.Background, 0);

    sortSz := 0;
    if (hoShowSortGlyphs in FHeader.Options) and (col.Index = FSortColumn) then
      sortSz := ScaleI(10);

    tr := Rect(cellR.Left + ScaleI(TyLvTextMargin), 0,
               cellR.Right - ScaleI(TyLvTextMargin) - sortSz, M.HeaderH);
    if tr.Left < tr.Right then
    begin
      if useSec then
        P.DrawText(tr, col.Text, hs.FontName, ResolveFontSize(hs), hs.FontWeight,
          tc, col.CaptionAlignment, tlCenter, True)
      else
        P.DrawText(tr, col.Text, AFrame.FontName, ResolveFontSize(AFrame), AFrame.FontWeight,
          tc, col.CaptionAlignment, tlCenter, True);
    end;

    if sortSz > 0 then
    begin
      sortR := Rect(cellR.Right - sortSz - ScaleI(TyLvTextMargin), ScaleI(2),
                    cellR.Right - ScaleI(TyLvTextMargin), M.HeaderH - ScaleI(2));
      if sortR.Right > sortR.Left then
      begin
        if FSortDirection = sdAscending then
          P.DrawGlyph(sortR, tgArrowUp, tc, ScaleI(1), 1)
        else
          P.DrawGlyph(sortR, tgArrowDown, tc, ScaleI(1), 1);
      end;
    end;

    { right-edge divider }
    if colRight - 1 < M.ViewportW then
      P.Bitmap.DrawLine(colRight - 1, 0, colRight - 1, M.HeaderH, border, False);
  end;

  { bottom border of the header band }
  P.Bitmap.DrawLine(0, M.HeaderH - 1, M.ViewportW, M.HeaderH - 1, border, False);
end;

procedure TTyListView.RenderGridLines(P: TTyPainter; const M: TTyListMetrics;
  const AFrame: TTyStyleSet);
var
  first, last, pos, posIdx, x: Integer;
  col: TTyColumn;
  cell: TRect;
  border: TBGRAPixel;
begin
  border := TyColorToBGRA(AFrame.BorderColor);
  { horizontal lines under each visible row }
  if TyListVisibleRange(GetItemCount, M, FOffsetX, FOffsetY, first, last) then
    for pos := first to last do
    begin
      cell := TyListItemRect(pos, GetItemCount, M, FOffsetX, FOffsetY);
      P.Bitmap.DrawLine(0, cell.Bottom - 1, M.ViewportW, cell.Bottom - 1, border, False);
    end;
  { vertical lines at each column's right edge }
  for posIdx := 0 to FHeader.Columns.Count - 1 do
  begin
    col := FHeader.Columns.ColumnByPosition(posIdx);
    if col = nil then Continue;
    if not (coVisible in col.Options) then Continue;
    x := ScaleI(col.Left) + ScaleI(col.Width) - FOffsetX;
    if (x > 0) and (x < M.ViewportW) then
      P.Bitmap.DrawLine(x - 1, M.HeaderH, x - 1, M.ViewportH, border, False);
  end;
end;

procedure TTyListView.RenderMarquee(P: TTyPainter; const AFrame: TTyStyleSet);
var
  box: TRect;
  sel: TTyStyleSet;
  acc: TTyColor;
  t: Integer;
begin
  box.Left   := FMarqueeStart.X; box.Right  := FMarqueeCur.X;
  box.Top    := FMarqueeStart.Y; box.Bottom := FMarqueeCur.Y;
  if box.Left > box.Right then begin t := box.Left; box.Left := box.Right; box.Right := t; end;
  if box.Top  > box.Bottom then begin t := box.Top; box.Top := box.Bottom; box.Bottom := t; end;
  { accent from the theme (TyTreeNode:selected bg), never a hard-coded colour }
  sel := ActiveController.Model.ResolveStyle('TyTreeNode', '', [tysSelected]);
  if tpBackground in sel.Present then acc := sel.Background.Color
  else acc := AFrame.BorderColor;
  { The HUE is the theme's; only the translucency is fixed. A rubber band has no theme
    token of its own and this batch adds none, so the two alphas are constants -- the same
    deviation TTyOfficeListBox makes when it derives its header band from the text colour
    at a fixed alpha. A theme change still recolours the band. }
  P.Bitmap.FillRect(box.Left, box.Top, box.Right, box.Bottom,
    BGRA(TyRedOf(acc), TyGreenOf(acc), TyBlueOf(acc), TyLvMarqueeFillAlpha),
    dmDrawWithTransparency);
  P.Bitmap.Rectangle(box.Left, box.Top, box.Right, box.Bottom,
    BGRA(TyRedOf(acc), TyGreenOf(acc), TyBlueOf(acc), TyLvMarqueeEdgeAlpha),
    dmDrawWithTransparency);
end;

procedure TTyListView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, rowStyle: TTyStyleSet;
  m: TTyListMetrics;
  cnt, first, last, pos, item, w, h: Integer;
  cell, clientBox, saved: TRect;
  states: TTyStateSet;
begin
  UpdateScrollBars;
  SyncArrays;

  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    w := ARect.Right - ARect.Left;
    h := ARect.Bottom - ARect.Top;
    clientBox := Rect(0, 0, w, h);
    S := CurrentStyle;
    DrawFrame(P, clientBox, S);

    m := CurrentMetrics;
    cnt := GetItemCount;

    { Clip the item region (below the header, inside the scrollbars). }
    saved := P.Bitmap.ClipRect;
    P.Bitmap.ClipRect := Rect(0, m.HeaderH, m.ViewportW, m.ViewportH);

    if TyListVisibleRange(cnt, m, FOffsetX, FOffsetY, first, last) then
      for pos := first to last do
      begin
        item := DisplayToItem(pos);   { display pos -> item index }
        if item < 0 then Continue;
        cell := TyListItemRect(pos, cnt, m, FOffsetX, FOffsetY);
        states := StatesFor(item);
        rowStyle := ActiveController.Model.ResolveStyle('TyTreeNode', '', states);
        RenderItem(P, item, cell, rowStyle, states);
      end;

    if (FViewStyle = lvsReport) and FGridLines then
      RenderGridLines(P, m, S);

    P.Bitmap.ClipRect := saved;

    if (FViewStyle = lvsReport) and (m.HeaderH > 0) then
      RenderHeader(P, m, S);

    if FMarquee then
      RenderMarquee(P, S);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyListView.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyListView.Resize;
begin
  inherited Resize;
  UpdateScrollBars;
end;

{ ---------------------------------------------------------------------------
  Mouse
  --------------------------------------------------------------------------- }

procedure TTyListView.ItemMouseSelect(AItem: Integer; Shift: TShiftState);
begin
  EnsureSelectedLen;
  if not FMultiSelect then
  begin
    SetSingleSelection(AItem);
    Exit;
  end;
  if ssShift in Shift then
  begin
    SelectRangeByDisplay(FAnchor, AItem);   { anchor stays; range via display order }
    FItemIndex := AItem;
    Invalidate;
    DoChange;
    DoSelectItem(AItem);
  end
  else if ssCtrl in Shift then
  begin
    if AItem < Length(FSelected) then
      FSelected[AItem] := not FSelected[AItem];
    FItemIndex := AItem;
    FAnchor := AItem;
    Invalidate;
    DoChange;
    DoSelectItem(AItem);
  end
  else
    SetSingleSelection(AItem);
end;

procedure TTyListView.ApplyMarquee;
var
  box: TRect;
  hits: TTyIntArray;
  m: TTyListMetrics;
  i, it, t: Integer;
begin
  box.Left := FMarqueeStart.X; box.Right := FMarqueeCur.X;
  box.Top := FMarqueeStart.Y; box.Bottom := FMarqueeCur.Y;
  if box.Left > box.Right then begin t := box.Left; box.Left := box.Right; box.Right := t; end;
  if box.Top > box.Bottom then begin t := box.Top; box.Top := box.Bottom; box.Bottom := t; end;
  m := CurrentMetrics;
  hits := TyListMarqueeHits(box, GetItemCount, m, FOffsetX, FOffsetY);   { display positions }
  EnsureSelectedLen;
  ClearAllBits;
  for i := 0 to High(hits) do
  begin
    it := DisplayToItem(hits[i]);   { display pos -> item index }
    if (it >= 0) and (it < Length(FSelected)) then
      FSelected[it] := True;
  end;
  if Length(hits) > 0 then
    FItemIndex := DisplayToItem(hits[High(hits)]);
  DoChange;
end;

procedure TTyListView.EndInteractions;
begin
  if FResizing or FMarquee then
  begin
    FResizing := False;
    FMarquee := False;
    MouseCapture := False;
    { The next MouseMove re-decides; MouseLeave restores if the pointer went away. }
    Invalidate;
  end;
end;

procedure TTyListView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  m: TTyListMetrics;
  cnt, pos, item, logX, logScroll, dividerCol, clickCol: Integer;
  col: TTyColumn;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  try
    if CanFocus then SetFocus;
  except
    { headless / test environments may reject focus }
  end;

  SyncArrays;
  m := CurrentMetrics;
  cnt := GetItemCount;
  FPressHit := GetHitPart(X, Y);

  { Header band (report mode). }
  if (FViewStyle = lvsReport) and (m.HeaderH > 0) and (Y < m.HeaderH) then
  begin
    logX      := UnscaleI(X);          { device -> logical (column model is logical) }
    logScroll := UnscaleI(FOffsetX);
    dividerCol := NoColumn;
    if hoColumnResize in FHeader.Options then
      dividerCol := FHeader.Columns.DetermineSplitterIndex(logX, logScroll);
    if dividerCol <> NoColumn then
    begin
      { Double-click on a divider fits the column to its content, as in Explorer. }
      if ssDouble in Shift then
      begin
        AutoFitColumn(dividerCol);
        Exit;
      end;
      FResizing := True;
      FResizeCol := dividerCol;
      FResizeStartX := X;
      FResizeStartW := (FHeader.Columns.Items[dividerCol] as TTyColumn).Width;
      { A press with no prior MouseMove (a tap, a synthetic click) still shows the grab
        cursor for the duration of the drag; MouseMove exits early while FResizing. }
      SetDividerCursor(True);
      MouseCapture := True;
      Exit;
    end;
    clickCol := FHeader.Columns.ColumnFromPosition(logX, logScroll);
    if clickCol <> NoColumn then
    begin
      if Assigned(FOnColumnClick) then FOnColumnClick(Self, clickCol);
      col := FHeader.Columns.Items[clickCol] as TTyColumn;
      if FAutoSort and (coAllowClick in col.Options) then
      begin
        if FSortColumn = clickCol then
        begin
          if FSortDirection = sdAscending then FSortDirection := sdDescending
          else FSortDirection := sdAscending;
        end
        else
        begin
          FSortColumn := clickCol;
          FSortDirection := sdAscending;
        end;
        Sort;
      end;
    end;
    Exit;
  end;

  { Item area. }
  pos := TyListItemAt(Point(X, Y), cnt, m, FOffsetX, FOffsetY);   { -> display pos }
  if pos >= 0 then
  begin
    item := DisplayToItem(pos);   { display pos -> item index }
    if item >= 0 then
      ItemMouseSelect(item, Shift);
  end
  else
  begin
    { Empty space: clear (unless Ctrl-extending) and, in multi-select, start a marquee. }
    if not (ssCtrl in Shift) then
      ClearSelection;
    if FMultiSelect then
    begin
      FMarquee := True;
      FMarqueeStart := Point(X, Y);
      FMarqueeCur := Point(X, Y);
      MouseCapture := True;
    end;
  end;
end;

{ Width of AText in DEVICE px, using the same font configuration DrawText would. ABmp is a
  scratch 1x1 bitmap the caller owns -- BGRA text measurement wants a bitmap but not a canvas,
  so this works with no window. }
function TTyListView.MeasureTextW(ABmp: TBGRABitmap; const AText: string;
  const AStyle: TTyStyleSet): Integer;
begin
  if AText = '' then Exit(0);
  TyConfigureTextFont(ABmp, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
    Font.PixelsPerInch);
  Result := ABmp.TextSize(AText).cx;
end;

{ Fit a column to its content: the header caption and the cell text of the first
  TyLvAutoFitSample display rows. The extras mirror what the two renderers actually add --
  TyLvTextMargin on each side, the main column's small icon, and the sort glyph (reserved
  whether or not this column is currently sorted, so the width does not jump when it is).

  Measuring EVERY row is what Explorer does, but BGRA text measurement is far too slow for a
  100k-row virtual list, so the sample is capped. For any list that fits the cap -- which is
  every ordinary one -- the fit is exact. }
procedure TTyListView.AutoFitColumn(AColumn: Integer);
const
  TyLvAutoFitSample = 500;
var
  col: TTyColumn;
  bmp: TBGRABitmap;
  rowS, hdrS: TTyStyleSet;
  cnt, sample, i, item, w, bestDev, iconDev: Integer;
begin
  if FHeader = nil then Exit;
  if (AColumn < 0) or (AColumn >= FHeader.Columns.Count) then Exit;
  col := FHeader.Columns.Items[AColumn] as TTyColumn;
  if not (coResizable in col.Options) then Exit;

  SyncArrays;
  rowS := ActiveController.Model.ResolveStyle('TyTreeNode', '', []);
  hdrS := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', []);

  iconDev := 0;
  if (AColumn = FHeader.MainColumn) and (FSmallImages <> nil) then
    iconDev := ScaleI(TyLvSmallIcon) + ScaleI(2);

  bmp := TBGRABitmap.Create(1, 1);
  try
    bestDev := MeasureTextW(bmp, col.Text, hdrS);
    if hoShowSortGlyphs in FHeader.Options then
      Inc(bestDev, ScaleI(10));

    cnt := GetItemCount;
    sample := Min(cnt, TyLvAutoFitSample);
    for i := 0 to sample - 1 do
    begin
      item := DisplayToItem(i);          { display pos -> item index }
      if item < 0 then Continue;
      w := MeasureTextW(bmp, GetItemText(item, AColumn), rowS) + iconDev;
      if w > bestDev then bestDev := w;
    end;
  finally
    bmp.Free;
  end;

  { Width is LOGICAL; the setter clamps to the column's Min/MaxWidth. }
  col.Width := UnscaleI(bestDev) + 2 * TyLvTextMargin;
  UpdateScrollBars;
  Invalidate;
end;

{ Show the horizontal-split cursor while the pointer can grab a column divider. The
  predicate is GetHitPart, the SAME one MouseDown uses to start a resize, so what the
  cursor promises and what a click does cannot drift apart. }
procedure TTyListView.SetDividerCursor(AOn: Boolean);
begin
  if AOn = FCursorOverridden then Exit;
  if AOn then
  begin
    FSavedCursor := Cursor;
    Cursor := crHSplit;
  end
  else
    Cursor := FSavedCursor;
  FCursorOverridden := AOn;
end;

procedure TTyListView.UpdateHoverCursor(X, Y: Integer);
begin
  SetDividerCursor(GetHitPart(X, Y) = lhpDivider);
end;

procedure TTyListView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  m: TTyListMetrics;
  newW, pos, newHot: Integer;
begin
  inherited MouseMove(Shift, X, Y);

  if FResizing then
  begin
    { A stolen MouseUp would otherwise leave us dragging forever. }
    if not (ssLeft in Shift) then begin EndInteractions; Exit; end;
    newW := FResizeStartW + UnscaleI(X - FResizeStartX);   { device delta -> logical }
    (FHeader.Columns.Items[FResizeCol] as TTyColumn).Width := newW;   { clamps internally }
    UpdateScrollBars;
    Invalidate;
    Exit;
  end;

  if FMarquee then
  begin
    if not (ssLeft in Shift) then begin EndInteractions; Exit; end;
    FMarqueeCur := Point(X, Y);
    ApplyMarquee;
    Invalidate;
    Exit;
  end;

  UpdateHoverCursor(X, Y);

  if FHotTrack then
  begin
    m := CurrentMetrics;
    pos := TyListItemAt(Point(X, Y), GetItemCount, m, FOffsetX, FOffsetY);
    if pos >= 0 then newHot := DisplayToItem(pos) else newHot := -1;
    if newHot <> FHot then
    begin
      FHot := newHot;
      Invalidate;
    end;
  end;
end;

procedure TTyListView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FResizing then
  begin
    FResizing := False;
    MouseCapture := False;
    UpdateScrollBars;
    Invalidate;
  end;
  if FMarquee then
  begin
    FMarquee := False;
    MouseCapture := False;
    Invalidate;
  end;
end;

procedure TTyListView.MouseLeave;
begin
  inherited MouseLeave;
  SetDividerCursor(False);
  if FHot <> -1 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TTyListView.DblClick;
begin
  inherited DblClick;
  { DblClick carries no coordinates, so lean on what the press landed on. Without this a
    double-click in the header band -- including the auto-fit gesture -- activates whatever
    item happens to be focused. }
  if not (FPressHit in [lhpIcon, lhpLabel]) then Exit;
  if (FItemIndex >= 0) and Assigned(FOnItemActivate) then
    FOnItemActivate(Self, FItemIndex);
end;

{ ---------------------------------------------------------------------------
  Keyboard
  --------------------------------------------------------------------------- }

procedure TTyListView.KeyDown(var Key: Word; Shift: TShiftState);
var
  m: TTyListMetrics;
  cnt, curPos, newPos, newItem: Integer;
  navKey: TTyListNavKey;
  mapped: Boolean;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  cnt := GetItemCount;
  if cnt = 0 then Exit;
  SyncArrays;
  m := CurrentMetrics;

  if (Key = VK_A) and (ssCtrl in Shift) and FMultiSelect then
  begin
    SelectAll;
    Key := 0;
    Exit;
  end;
  if Key = VK_RETURN then
  begin
    if (FItemIndex >= 0) and Assigned(FOnItemActivate) then
      FOnItemActivate(Self, FItemIndex);
    Key := 0;
    Exit;
  end;
  if (Key = VK_SPACE) and FMultiSelect and (FItemIndex >= 0) then
  begin
    EnsureSelectedLen;
    if FItemIndex < Length(FSelected) then
      FSelected[FItemIndex] := not FSelected[FItemIndex];
    FAnchor := FItemIndex;
    Invalidate;
    DoChange;
    Key := 0;
    Exit;
  end;

  mapped := True;
  case Key of
    VK_LEFT:  navKey := lnLeft;
    VK_RIGHT: navKey := lnRight;
    VK_UP:    navKey := lnUp;
    VK_DOWN:  navKey := lnDown;
    VK_HOME:  navKey := lnHome;
    VK_END:   navKey := lnEnd;
    VK_PRIOR: navKey := lnPageUp;
    VK_NEXT:  navKey := lnPageDown;
  else
    mapped := False;
  end;
  if not mapped then Exit;   { leave the key unconsumed }

  curPos := ItemToDisplay(FItemIndex);   { item index -> display pos (-1 if none) }
  newPos := TyListNavigate(curPos, cnt, navKey, m);
  Key := 0;
  if newPos < 0 then Exit;
  newItem := DisplayToItem(newPos);       { display pos -> item index }
  if newItem < 0 then Exit;

  if FMultiSelect and (ssShift in Shift) then
  begin
    SelectRangeByDisplay(FAnchor, newItem);
    FItemIndex := newItem;
    Invalidate;
    DoChange;
    DoSelectItem(newItem);
  end
  else
    SetSingleSelection(newItem);
  ScrollIntoView(newItem);
end;

procedure TTyListView.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  cnt, startDisp, searchFrom, foundDisp, item: Integer;
begin
  inherited UTF8KeyPress(UTF8Key);
  if UTF8Key = '' then Exit;
  { ignore control chars (Enter, Tab, Esc …) }
  if (Length(UTF8Key) = 1) and (UTF8Key[1] < ' ') then Exit;
  cnt := GetItemCount;
  if cnt = 0 then Exit;
  SyncArrays;

  { restart the buffer once the timeout lapses }
  if MilliSecondsBetween(Now, FSearchTime) > FSearchTimeout then
    FSearchBuffer := '';
  FSearchTime := Now;
  FSearchBuffer := FSearchBuffer + UTF8Key;

  { search in DISPLAY order: the callback + returned index are display positions }
  startDisp := ItemToDisplay(FItemIndex);   { item index -> display pos }

  { A REFINING keystroke -- one that lengthens an existing buffer -- must be able to stay on
    the item the previous keystroke landed on. Type 'r', land on "Report"; type 'e', and "re"
    should keep "Report", not skip past it to "Resume". TyListPrefixMatch scans from
    AStartAfter + 1, so step the origin back one position to make the scan inclusive of the
    current row. A fresh single key keeps the exclusive origin, which is what makes repeating
    the same letter cycle through its matches. Same rule as TTyTreeView.DoIncrementalSearch. }
  searchFrom := startDisp;
  if (Length(FSearchBuffer) > Length(UTF8Key)) and (startDisp >= 0) then
    Dec(searchFrom);   { never below -1: that already means "scan from position 0" }

  foundDisp := TyListPrefixMatch(@GetDisplayText, cnt, searchFrom, FSearchBuffer);
  { the refined prefix matches nothing: fall back to cycling on the last key alone }
  if (foundDisp < 0) and (Length(FSearchBuffer) > Length(UTF8Key)) then
  begin
    FSearchBuffer := UTF8Key;
    foundDisp := TyListPrefixMatch(@GetDisplayText, cnt, startDisp, FSearchBuffer);
  end;
  if foundDisp >= 0 then
  begin
    item := DisplayToItem(foundDisp);   { display pos -> item index }
    if item >= 0 then
    begin
      SetSingleSelection(item);
      ScrollIntoView(item);
    end;
  end;
end;

function TTyListView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  m: TTyListMetrics;
  step: Integer;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  m := CurrentMetrics;
  if FViewStyle = lvsList then
  begin
    { column-major: the wheel scrolls horizontally }
    step := 3 * (m.CellW + m.HGap);
    if WheelDelta > 0 then Dec(FOffsetX, step) else Inc(FOffsetX, step);
  end
  else
  begin
    if FViewStyle = lvsReport then step := 3 * m.RowH
    else step := 3 * (m.CellH + m.VGap);
    if WheelDelta > 0 then Dec(FOffsetY, step) else Inc(FOffsetY, step);
  end;
  if FOffsetX < 0 then FOffsetX := 0;
  if FOffsetY < 0 then FOffsetY := 0;
  UpdateScrollBars;   { re-clamps to the content range }
  Invalidate;
  Result := True;
end;

initialization
  { Register for LFM streaming (mirrors tyControls.Columns' initialization block). }
  RegisterClass(TTyListItem);
  RegisterClass(TTyListItems);
  RegisterClass(TTyListView);

end.
