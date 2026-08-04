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
  never computes a cell rect by hand. Theming: the control owns its own key family
  (GetStyleTypeKey = 'TyListView'); see that method for the part list. }
interface
uses
  Classes, SysUtils, Types, Math, DateUtils, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ScrollBar, tyControls.Columns, tyControls.ImageCollection,
  tyControls.Edit, tyControls.ListView.Layout;

const
  { The RowHeight property's default, in logical px. Public because a published property's
    `default` directive needs a compile-time constant visible where the property is declared. }
  TyLvRowHeight = 22;
  { Row-checkbox edge length, in logical px (DPI-scaled at paint time). }
  TyLvCheckPx = 14;

type
  { Per-item state flags. lisChecked/lisCut are surfaced through GetItemState so a
    theme/renderer can react; checkboxes ARE drawn (RenderCheckBox); this note used to say they were not. }
  TTyListItemState  = (lisChecked, lisCut, lisDisabled);
  TTyListItemStates = set of TTyListItemState;

  TTyListView  = class;   { forward }
  TTyListItems = class;   { forward }

  { ===================================================================
    TTyListItem — one row of the built-in collection (non-virtual mode)
    =================================================================== }
  TTyListItem = class(TCollectionItem)
  private
    FCaption:    TCaption;
    FSubItems:   TStrings;
    FImageIndex: Integer;
    FData:       Pointer;
    FStates:     TTyListItemStates;
    FGroupIndex: Integer;
    procedure SetCaption(const AValue: TCaption);
    procedure SetSubItems(AValue: TStrings);
    procedure SetImageIndex(AValue: Integer);
    procedure SetStates(AValue: TTyListItemStates);
    procedure SetGroupIndex(AValue: Integer);
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
    property Caption:    TCaption  read FCaption    write SetCaption;
    { Columns 1..N (column 0 is Caption). }
    property SubItems:   TStrings read FSubItems  write SetSubItems;
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
    { Which group (index into TTyListView.Groups) owns this item, or -1 for the implicit
      headerless bucket. Only consulted when GroupView is on and the built-in collection is
      the data source; OwnerData routes through OnGetItemGroup instead. }
    property GroupIndex: Integer read FGroupIndex write SetGroupIndex default -1;
  end;

  { ===================================================================
    TTyListItems — the built-in item collection
    =================================================================== }
  { WHICH item the collection is telling us about, and what happened to it. Used only to
    reach the control (which republishes it as OnInsert / OnDeletion); the app never sees
    this type. FPC fires cnAdded AFTER the item joins the list and cnExtracting BEFORE it
    leaves (collect.inc:200-226), so AItem.Index is valid in both directions -- which is
    what makes an index-carrying notification possible at all. }
  TTyListItemsNotifyEvent = procedure(Sender: TObject; AItem: TCollectionItem;
    AAction: TCollectionNotification) of object;

  TTyListItems = class(TCollection)
  private
    FOwner:    TPersistent;
    FOnChange: TNotifyEvent;
    FOnItemNotify: TTyListItemsNotifyEvent;
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
    property OnItemNotify: TTyListItemsNotifyEvent read FOnItemNotify write FOnItemNotify;
  end;

  { ===================================================================
    TTyListGroup / TTyListGroups — the grouping model (SP2b)

    Groups are ALWAYS a real collection, even under OwnerData: only the items are
    virtualised, never the (always small) group list. A group is addressed by its GROUP
    index — its position in the collection — which is what GroupIndex / OnGetItemGroup /
    OnGroupCollapsed speak; it is never a display position.
    =================================================================== }
  TTyListGroup = class(TCollectionItem)
  private
    FCaption:   TCaption;
    FCollapsed: Boolean;
    procedure SetCaption(const AValue: TCaption);
    procedure SetCollapsed(AValue: Boolean);
  protected
    function GetDisplayName: string; override;
  public
    procedure Assign(ASource: TPersistent); override;
  published
    property Caption:   TCaption  read FCaption   write SetCaption;
    property Collapsed: Boolean read FCollapsed write SetCollapsed default False;
  end;

  TTyListGroups = class(TCollection)
  private
    FOwner:    TPersistent;
    FOnChange: TNotifyEvent;
    function GetItem(AIndex: Integer): TTyListGroup;
    procedure SetItem(AIndex: Integer; AValue: TTyListGroup);
  protected
    function GetOwner: TPersistent; override;
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TTyListGroup;
    property Items[AIndex: Integer]: TTyListGroup read GetItem write SetItem; default;
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

  { WHAT changed about an item. Mirrors LCL's TItemChange (comctrls.pp:1286) value for
    value, so a `case AChange of ctText/ctImage/ctState` lifted out of a TListView handler
    compiles here unedited. Without it OnChange could only say "something moved" and the
    host had to re-read the whole control to find out what.

    ctImage is declared for that parity but the BUILT-IN data paths never raise it: this
    control owns no per-item image mutator (an image is whatever the data source answers
    for GetItemImageIndex). A descendant that does own one raises it through the protected
    DoChange. LCL is in the same position off Windows, where the native notification it
    derives ctImage from never arrives. }
  TTyItemChange = (ctText, ctImage, ctState);

  { Selection notification. LCL: TLVSelectItemEvent (comctrls.pp:1323) = (Sender, Item,
    Selected); Item is an ITEM index here, as everywhere in this control.
    ASelected is what makes the event usable: it fires for BOTH directions, so a host can
    tell "row 3 was chosen" from "row 3 was abandoned". Without it the abandoned row was
    never reported at all and a host had to diff the selection itself. }
  TTyListSelectItemEvent = procedure(Sender: TObject; AIndex: Integer;
                                     ASelected: Boolean) of object;

  { Item-change notification / veto. LCL: TLVChangeEvent / TLVChangingEvent
    (comctrls.pp:1292 / 1294).
    AIndex is an ITEM index, or -1 for a bulk change with no single subject (Select All,
    Clear Selection, a rubber-band sweep, a MultiSelect collapse) — exactly LCL's
    `iItem < 0 -> Item = nil` in customlistview.inc:337.
    OnChanging runs BEFORE the change and vetoes it by clearing AAllowChange; the control
    then leaves the selection untouched and never raises OnChange/OnSelectItem. }
  { An item was inserted, or is ABOUT to be deleted. LCL: TLVDeletedEvent /
    TLVInsertEvent (comctrls.pp:1313/1320), published as OnDeletion / OnInsert.
    AIndex is an ITEM index, valid for the duration of the call.

    OnDeletion is the only moment at which an item's Data payload is still reachable and
    the row is still there. Without it a collection holding owned objects in Data leaked
    every one of them: TTyListItems is a TCollection whose Notify is protected and already
    consumed internally, so short of subclassing the collection there was no hook at all. }
  TTyListItemNotifyEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  TTyListChangeEvent   = procedure(Sender: TObject; AIndex: Integer;
                                   AChange: TTyItemChange) of object;
  TTyListChangingEvent = procedure(Sender: TObject; AIndex: Integer;
                                   AChange: TTyItemChange;
                                   var AAllowChange: Boolean) of object;

  { Grouping events (SP2b). OnGetItemGroup resolves an ITEM index to a GROUP index in
    OwnerData mode (var out-param, LCL convention; leave -1 for the implicit bucket).
    OnGroupCollapsed fires AFTER a header click toggled a group's Collapsed state and
    carries that GROUP index. }
  TTyListGetGroupEvent = procedure(Sender: TObject; AIndex: Integer;
                                   var AGroup: Integer) of object;
  TTyListGroupEvent    = procedure(Sender: TObject; AGroup: Integer) of object;

  { Inline-rename events. AIndex is an ITEM index. OnEditing can veto (AAllow := False);
    OnEdited may rewrite the committed text (var AText) and treats '' as "abandon". }
  TTyListEditingEvent  = procedure(Sender: TObject; AIndex: Integer;
                                   var AAllow: Boolean) of object;
  TTyListEditedEvent   = procedure(Sender: TObject; AIndex: Integer;
                                   var AText: string) of object;

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
    FRowHeight:         Integer;   { logical px; explicit override (see FRowHeightExplicit) }
    FRowHeightExplicit: Boolean;   { True once a host/.lfm sets RowHeight; False = follow the
                                     theme's --row-height token (density-aware: 22 classic / 32 modern) }
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
    FOnSelectItem:    TTyListSelectItemEvent;
    FOnChange:        TTyListChangeEvent;
    FOnChanging:      TTyListChangingEvent;
    FOnInsert:        TTyListItemNotifyEvent;
    FOnDeletion:      TTyListItemNotifyEvent;
    { checkboxes }
    FCheckboxes:      Boolean;
    FOnItemChecked:   TTyListItemEvent;
    { inline rename }
    FReadOnly:        Boolean;
    FEditor:          TTyEdit;
    { The item being edited. It is an ITEM index, never a display position, so an edit
      survives a re-sort (rule 9): the row moves, the index does not. -1 = not editing. }
    FEditItem:        Integer;
    { Re-entry guard: EndEdit hides the editor (which fires OnExit -> EndEdit again) and
      may SetFocus (another OnExit); without this the commit path recurses. }
    FEndingEdit:      Boolean;
    FOnEditing:       TTyListEditingEvent;
    FOnEdited:        TTyListEditedEvent;
    { grouping (SP2b) }
    FGroupView:       Boolean;
    FGroups:          TTyListGroups;
    { The vertical map cached once per order/layout pass; the ONLY geometry source in
      grouped mode. FGroupMap.Groups doubles as the per-group info array (Count / Collapsed /
      HasHeader), so RefreshGroupMap can re-derive the metric-dependent Tops from it without
      re-bucketing the items. }
    FGroupMap:        TTyListGroupMap;
    FOnGetItemGroup:  TTyListGetGroupEvent;
    FOnGroupCollapsed: TTyListGroupEvent;

    procedure ItemsCollectionChanged(Sender: TObject);
    procedure ItemsCollectionNotify(Sender: TObject; AItem: TCollectionItem;
      AAction: TCollectionNotification);
    function  GetColumns: TTyColumns;
    function  GetColumn(AIndex: Integer): TTyColumn;
    function  GetColumnCount: Integer;
    procedure HeaderChanged(Sender: TObject);
    procedure GroupsChanged(Sender: TObject);
    procedure VScrollChange(Sender: TObject);
    procedure HScrollChange(Sender: TObject);

    procedure SetOwnerData(AValue: Boolean);
    procedure SetItemCount(AValue: Integer);
    procedure SetViewStyle(AValue: TTyListViewStyle);
    function  GetRowHeight: Integer;
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
    procedure SetCheckboxes(AValue: Boolean);
    function  GetChecked(AIndex: Integer): Boolean;    { item index }
    procedure SetChecked(AIndex: Integer; AValue: Boolean);   { item index }
    procedure SetGroupView(AValue: Boolean);
    procedure SetGroups(AValue: TTyListGroups);

    { grouping helpers — all in DISPLAY / GROUP space internally, mapped at the boundary }
    function  UseGroupedLayout: Boolean;               { FGroupView and ViewStyle <> lvsList }
    function  GroupHeaderHeightPx: Integer;            { group-band height, device px }
    procedure BuildGroupedOrder;                       { buckets + per-bucket sort + FOrder/FRank/FGroupMap }
    procedure RefreshGroupMap;                         { re-derive FGroupMap.Tops from current metrics, O(G) }
    procedure MergeSortRange(var A: TTyIntArray; ALo, AHi: Integer; var ABuf: TTyIntArray);
    { The on-screen index-in-group window [AFirst, ALast] for group AGroup, bounded by the
      viewport (never the whole group). False = the group has nothing visible. }
    function  GroupVisibleItemRange(AGroup: Integer; const M: TTyListMetrics;
                out AFirst, ALast: Integer): Boolean;
    procedure RenderGrouped(P: TTyPainter; const M: TTyListMetrics);
    procedure RenderGroupHeader(P: TTyPainter; const M: TTyListMetrics; AGroup: Integer);
    procedure ToggleGroupCollapsed(AGroup: Integer);   { group index }

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
    { The selection DELTA machinery behind OnSelectItem. SnapshotSelection captures the
      EFFECTIVE selection (single mode: the focused item; multi mode: the set bits) as an
      ascending list of ITEM indices; FireSelectionDelta re-snapshots and raises
      DoSelectItem once per item whose state actually flipped — True for gained, False for
      lost. Comparing snapshots is the only way to report the LOST rows: the mutators
      overwrite the whole selection (ClearAllBits) and never see the individual bits go out.
      Both are no-ops when OnSelectItem is unassigned, so a million-row virtual list pays
      nothing at all unless the host opted in. }
    function  SnapshotSelection: TTyIntArray;
    procedure FireSelectionDelta(const ABefore: TTyIntArray);
    function  StatesFor(AItem: Integer): TTyStateSet;  { item index }

    { text accessor handed (as a callback) to the pure prefix-match loop. Its AIndex
      argument is a DISPLAY position so type-ahead follows the visible sort order. }
    function  GetDisplayText(ADisplayPos: Integer): string;

    { layout / metrics (all device pixels) }
    procedure FillMetrics(out AMetrics: TTyListMetrics; AViewW, AViewH: Integer);

    { compare + stable sort of FOrder }

    procedure MergeSortOrder(ALo, AHi: Integer);

    { rendering helpers }
    { Which list a column header's ImageIndex is resolved against — Header.Images when
      set, else SmallImages. See the body for why the fallback is the ported behaviour. }
    function  HeaderImageList: TTyVirtualImageList;
    procedure RenderHeader(P: TTyPainter; const M: TTyListMetrics; const AFrame: TTyStyleSet);
    procedure RenderGridLines(P: TTyPainter; const M: TTyListMetrics; const AFrame: TTyStyleSet);
    procedure RenderMarquee(P: TTyPainter; const AFrame: TTyStyleSet);
    procedure RenderReportRow(P: TTyPainter; AIndex: Integer; const ACell: TRect;
      const AStyle: TTyStyleSet);
    procedure RenderFlowCell(P: TTyPainter; AIndex: Integer; const ACell: TRect;
      const AStyle: TTyStyleSet);
    procedure DrawImage(P: TTyPainter; AList: TTyVirtualImageList;
      AImageIndex, AX, AY, ASizePx: Integer);
    { The single box-geometry source for the control: it computes the main-column sub-rect
      (report) or passes the whole cell (flow) into the pure TyListCheckRect. Paint and
      hit-test both call it. ACell is a client-coord cell rect. Empty rect = no box. }
    function  CheckRectForCell(const ACell: TRect): TRect;
    procedure RenderCheckBox(P: TTyPainter; const ABox: TRect; AChecked: Boolean);

    { inline rename }
    { Editor bounds for an ITEM index = that item's label rect, derived from TyListItemRect
      (report: the main column's text rect; flow: the cell's label rect). No separate geometry. }
    function  EditorBoundsFor(AIndex: Integer): TRect;   { item index }
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);

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
    { Virtual so a subclass whose ORDER is part of what it is (TTyShellListView sorts
      folders before files on raw values, not display strings) can implement it instead of
      claiming the published OnCompare slot. Claiming that slot meant an application which
      assigned OnCompare silently replaced the shell's ordering, with nothing to say so. }
    function  CompareItems(AItemA, AItemB: Integer): Integer; virtual;
    { Same reasoning for activation: a shell list navigates folders and fires
      OnFileActivate for files, which it used to do by owning OnItemActivate. }
    procedure DoItemActivate(AIndex: Integer); virtual;
    function  DisplayToItem(APos: Integer): Integer;   { display pos -> item index, -1 if out of range }
    function  ItemToDisplay(AItem: Integer): Integer;  { item index -> display pos, -1 if out of range }
    { How far a flow cell's icon+label shift right to clear the checkbox. lvsIcon overlays
      the box in the free top-left corner (not shifted); every other flow mode draws the
      icon at the left edge, where the box would otherwise sit on top of it. 0 when
      checkboxes are off or the box does not fit. }
    function  FlowCheckShift(const ACell: TRect): Integer;

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
    { The fifth reader, parallel to the four above: the RAW group index an item declares.
      OwnerData fires OnGetItemGroup; the collection reads GroupIndex. It returns exactly what
      the data says -- a value outside [0, Groups.Count-1], e.g. 99 or -1, is returned verbatim.
      Normalising an out-of-range value into the implicit bucket is the ORDER BUILDER's policy,
      not this accessor's, so a TTyShellListView override can just return its natural group id. }
    function GetItemGroup(AItemIndex: Integer): Integer; virtual;

    { Write the check state for an ITEM index. Collection mode writes lisChecked into
      Items[AIndex].States; OwnerData does NOTHING — the control caches no check state, the
      app mutates its own store from OnItemChecked. Reads always go through GetItemState, so
      both modes share a single read path. }
    procedure SetItemChecked(AIndex: Integer; AValue: Boolean); virtual;   { item index }
    { Commit an inline rename for an ITEM index. Fires OnEdited (app may rewrite / abandon).
      Collection mode writes Items[AIndex].Caption; OwnerData does NOTHING — the app owns the
      data and updates its store from OnEdited. }
    procedure CommitEdit(AIndex: Integer; const AText: string); virtual;   { item index }
    { The persistent inline editor, read-only to descendants. }
    property InlineEditor: TTyEdit read FEditor;

    { The item-change seams, mirroring LCL's protected Change / CanChange / DoSelectItem
      (comctrls.pp:1529-1531, customlistview.inc:193/208/701).

      They are PROTECTED VIRTUAL on purpose. A descendant that needs to react to a change
      overrides one of these; it must NOT assign OnChange / OnChanging / OnSelectItem on
      itself, because those slots belong to the APP — a library class that grabs one
      silently replaces whatever the host assigned, and the host gets no warning at all.
      TTyFileDialogForm is a host in exactly this sense: it assigns OnSelectItem on its own
      list, which is legitimate precisely because the control never consumes it.

      DoChange raises OnChange; AIndex is an ITEM index, or -1 for a bulk change with no
      single subject. CanChange raises OnChanging and returns False when the host vetoed;
      every selection mutator asks it BEFORE touching a bit. DoSelectItem raises
      OnSelectItem for one item that gained (ASelected) or lost the selection. }
    procedure DoChange(AIndex: Integer; AChange: TTyItemChange); virtual;
    function  CanChange(AIndex: Integer; AChange: TTyItemChange): Boolean; virtual;
    procedure DoSelectItem(AIndex: Integer; ASelected: Boolean); virtual;
    { Structural seams, same discipline: DoInsert raises OnInsert just after an item joined
      the built-in collection, DoDeletion raises OnDeletion just before one leaves it (and
      per item when the collection is cleared or the control is destroyed), so the row's
      Data payload is still reachable. Neither fires in OwnerData mode: there is no
      collection there and the app already owns the lifetime. LCL: comctrls.pp:1610/1613. }
    procedure DoInsert(AIndex: Integer); virtual;
    procedure DoDeletion(AIndex: Integer); virtual;

    function GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;

    { The per-item paint seam TreeView never had. ACell is client coords; AStyle the
      resolved 'TyListViewItem' style for AStates. }
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

    { The report columns, reachable WITHOUT the Header hop. `LV.Columns[0].Width := 120`
      and `LV.ColumnCount` are how every line of ported TListView column code is written
      (comctrls.pp:1582/:1664/:1665), and Header.Columns was the only spelling here.
      PUBLIC, not published, deliberately: Header already streams the collection, and a
      second published path to the same objects would write them into the .lfm twice. }
    property Columns: TTyColumns read GetColumns;
    property Column[AIndex: Integer]: TTyColumn read GetColumn;
    property ColumnCount: Integer read GetColumnCount;

    { Hit-testing / scrolling — ITEM indices in, ITEM indices out. }
    function  GetItemAt(X, Y: Integer): Integer;
    function  GetHitPart(X, Y: Integer): TTyListHitPart;
    procedure ScrollIntoView(AIndex: Integer);
    { Widen/narrow a column to fit its header caption and its cell text. Also bound to a
      double-click on the column's right divider. }
    procedure AutoFitColumn(AColumn: Integer);

    { Checkbox state — ITEM index. Reads lisChecked via GetItemState (one read path for
      both data modes); the writer ignores an out-of-range index silently. }
    property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;

    { Inline rename — all ITEM indices. }
    function  Editing: Boolean;
    procedure BeginEdit(AIndex: Integer);                                { item index }
    procedure EndEdit(ACommit: Boolean; ARestoreFocus: Boolean = False);

    property ItemIndex: Integer read GetItemIndex write SetItemIndex;
  published
    property ViewStyle: TTyListViewStyle read FViewStyle write SetViewStyle default lvsReport;
    { Report row height in logical px, DPI-scaled at paint time. Left unset it follows the
      theme's --row-height token, so a list gets denser rows at classic density (22) and
      roomier ones at modern density (32) automatically. Set it explicitly (a file dialog
      wants its own density) and that value wins and is streamed; the getter then returns
      what you set. Streamed only when explicitly set (stored FRowHeightExplicit). }
    property RowHeight: Integer read GetRowHeight write SetRowHeight stored FRowHeightExplicit;
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
    { Row-first checkboxes. A click on the box, or Space on the focused row, toggles the
      check without touching the selection. The box resolves this control's own
      'TyListViewCheckBox', so a file list's boxes can differ from a tree's. }
    property Checkboxes: Boolean read FCheckboxes write SetCheckboxes default False;
    { Inline rename is opt-in, like TTyTreeView's toEditable and UNLIKE LCL
      TListView.ReadOnly=False: a file panel must not enter rename on a stray F2. }
    property ReadOnly: Boolean read FReadOnly write FReadOnly default True;
    { Grouped view. When on (and ViewStyle <> lvsList, which cannot host group bands and so
      silently ignores it), items are partitioned into collapsible bands. The band resolves
      'TyListViewGroupHeader' -- its own key, NOT the report column-header band's. }
    property GroupView: Boolean read FGroupView write SetGroupView default False;
    property Groups: TTyListGroups read FGroups write SetGroups;

    property OnGetItemText:  TTyListGetTextEvent  read FOnGetItemText  write FOnGetItemText;
    property OnGetItemImage: TTyListGetImageEvent read FOnGetItemImage write FOnGetItemImage;
    property OnGetItemState: TTyListGetStateEvent read FOnGetItemState write FOnGetItemState;
    property OnCompare:      TTyListCompareEvent  read FOnCompare      write FOnCompare;
    property OnColumnClick:  TTyListColumnEvent   read FOnColumnClick  write FOnColumnClick;
    property OnItemActivate: TTyListItemEvent     read FOnItemActivate write FOnItemActivate;
    { Fires once for EVERY row whose selected state flipped — the chosen one with
      ASelected = True and each abandoned one with False. }
    property OnSelectItem:   TTyListSelectItemEvent read FOnSelectItem write FOnSelectItem;
    { What changed and how. AIndex = -1 means a bulk change (Select All / Clear Selection /
      marquee), matching LCL's nil Item. }
    property OnChange:       TTyListChangeEvent   read FOnChange       write FOnChange;
    { Runs before a selection change and can veto it (AAllowChange := False). The rename and
      checkbox paths keep their own vetoes (OnEditing / OnItemChecked) and are NOT routed
      through here, so nothing is double-vetoed. }
    property OnChanging:     TTyListChangingEvent read FOnChanging     write FOnChanging;
    property OnItemChecked:  TTyListItemEvent     read FOnItemChecked  write FOnItemChecked;
    { Fires just after a row joined the built-in collection. }
    property OnInsert:       TTyListItemNotifyEvent read FOnInsert   write FOnInsert;
    { Fires just BEFORE a row leaves it -- the only moment its Data payload is still
      reachable. An item collection holding owned objects had no hook to free them. }
    property OnDeletion:     TTyListItemNotifyEvent read FOnDeletion write FOnDeletion;
    property OnEditing:      TTyListEditingEvent  read FOnEditing      write FOnEditing;
    property OnEdited:       TTyListEditedEvent   read FOnEdited       write FOnEdited;
    property OnGetItemGroup:   TTyListGetGroupEvent read FOnGetItemGroup   write FOnGetItemGroup;
    property OnGroupCollapsed: TTyListGroupEvent    read FOnGroupCollapsed write FOnGroupCollapsed;

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
  { Column-header icon slot, in logical px. Both are theme tokens first
    ('--listview-header-icon-size' / '--listview-header-icon-gap'); these are only the
    values a theme that says nothing about them falls back to, and they are deliberately
    the small-icon edge and the text margin, so wiring a header icon changes nothing
    about a header that has none. }
  TyLvHeaderIcon    = TyLvSmallIcon;
  TyLvHeaderIconGap = TyLvTextMargin;
  { Group-header band height in logical px (DPI-scaled at paint time). There is no theme token
    for a band height, so this is a layout constant like TyLvRowHeight; the band's
    colours/font come from the 'TyListViewGroupHeader' style. }
  TyLvGroupHeaderH = 22;
  { Rubber-band translucency. The colour comes from the theme ('TyListViewMarquee'); see
    RenderMarquee. }
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
  FGroupIndex := -1;
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
    FGroupIndex := src.FGroupIndex;
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

procedure TTyListItem.SetCaption(const AValue: TCaption);
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

procedure TTyListItem.SetGroupIndex(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;
  if FGroupIndex = AValue then Exit;
  FGroupIndex := AValue;
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
  // Per-item first: the control turns it into OnDeletion while the row (and its Data)
  // still exists. FOnChange resizes the control's arrays and would invalidate the index.
  if Assigned(FOnItemNotify) then FOnItemNotify(Self, Item, Action);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyListItems.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if Assigned(FOnChange) then FOnChange(Self);
end;

{ ---------------------------------------------------------------------------
  TTyListGroup
  --------------------------------------------------------------------------- }

function TTyListGroup.GetDisplayName: string;
begin
  if FCaption <> '' then
    Result := FCaption
  else
    Result := inherited GetDisplayName;
end;

procedure TTyListGroup.Assign(ASource: TPersistent);
var
  src: TTyListGroup;
begin
  if ASource is TTyListGroup then
  begin
    src := TTyListGroup(ASource);
    FCaption   := src.FCaption;
    FCollapsed := src.FCollapsed;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

procedure TTyListGroup.SetCaption(const AValue: TCaption);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

procedure TTyListGroup.SetCollapsed(AValue: Boolean);
begin
  if FCollapsed = AValue then Exit;
  FCollapsed := AValue;
  Changed(False);
end;

{ ---------------------------------------------------------------------------
  TTyListGroups
  --------------------------------------------------------------------------- }

constructor TTyListGroups.Create(AOwner: TPersistent);
begin
  inherited Create(TTyListGroup);
  FOwner := AOwner;
end;

function TTyListGroups.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

function TTyListGroups.Add: TTyListGroup;
begin
  Result := TTyListGroup(inherited Add);
end;

function TTyListGroups.GetItem(AIndex: Integer): TTyListGroup;
begin
  Result := TTyListGroup(inherited Items[AIndex]);
end;

procedure TTyListGroups.SetItem(AIndex: Integer; AValue: TTyListGroup);
begin
  inherited Items[AIndex] := AValue;
end;

procedure TTyListGroups.Notify(Item: TCollectionItem; Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyListGroups.Update(Item: TCollectionItem);
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
  FItems.OnItemNotify := @ItemsCollectionNotify;

  FGroups := TTyListGroups.Create(Self);
  FGroups.OnChange := @GroupsChanged;
  FGroupView := False;

  FViewStyle         := lvsReport;
  FRowHeight         := TyLvRowHeight;   { fallback; unused while FRowHeightExplicit=False }
  FRowHeightExplicit := False;           { follow --row-height (density-aware) until set }
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

  { Two embedded scrollbars, eager + hidden + non-designable (see TreeView 1835).
    TabStop=False: a standalone TTyScrollBar is focusable (it owns arrow/page keys), but a
    bar living INSIDE a list must not be — dragging it would take focus off the list view,
    which would then lose its focus ring and its keyboard navigation mid-scroll. }
  FVScroll := TTyScrollBar.Create(Self);
  FVScroll.Parent            := Self;
  FVScroll.Kind              := sbVertical;
  FVScroll.TabStop           := False;
  FVScroll.AnimationsEnabled := False;
  FVScroll.OnChange          := @VScrollChange;
  FVScroll.ControlStyle      := FVScroll.ControlStyle + [csNoDesignVisible];
  FVScroll.Visible           := False;

  FHScroll := TTyScrollBar.Create(Self);
  FHScroll.Parent            := Self;
  FHScroll.Kind              := sbHorizontal;
  FHScroll.TabStop           := False;
  FHScroll.AnimationsEnabled := False;
  FHScroll.OnChange          := @HScrollChange;
  FHScroll.ControlStyle      := FHScroll.ControlStyle + [csNoDesignVisible];
  FHScroll.Visible           := False;

  FCheckboxes := False;
  FReadOnly   := True;    { rename is opt-in }
  FEditItem   := -1;

  { The persistent inline rename editor — hidden, non-tab-stop, parented to Self so it
    shares the list's client coordinate space and Controller (rule 3). Shown + positioned
    on demand by BeginEdit; dormant while ReadOnly. Rule 8: set csNoDesignVisible BEFORE
    Visible so the hidden editor never leaks into the IDE designer. }
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent      := Self;
  FEditor.TabStop     := False;
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];
  FEditor.Visible     := False;
  FEditor.OnKeyDown   := @EditorKeyDown;   { Enter commits, Esc cancels }
  FEditor.OnExit      := @EditorExit;      { focus loss commits Explorer-style }

  TabStop := True;
  Width   := 280;
  Height  := 180;

  RebuildOrder;
end;

destructor TTyListView.Destroy;
begin
  { Items go FIRST, and with OnItemNotify still armed: OnDeletion fires per row as the
    collection empties, and a control going away is exactly when a host holding owned
    objects in Data must free them. That means the handler can still call back into the
    control, so everything it might read -- the header above all -- has to outlive it. }
  FItems.OnChange := nil;
  FItems.Free;
  FItems := nil;
  FHeader.OnChange := nil;
  FHeader.Free;
  FGroups.OnChange := nil;
  FGroups.Free;
  { FVScroll / FHScroll owned by Self, freed by TComponent. }
  inherited Destroy;
end;

function TTyListView.GetStyleTypeKey: string;
begin
  { Its own key, not the tree's. This control is not a tree: it draws icon / tile / small-icon
    flow cells, a horizontally scrolling report column band, ruled grid lines, collapsible
    group bands and a rubber band -- parts a tree has no concept of. While it rendered from
    'TyTreeView' a skin could not make an Explorer-style file list read differently from an
    outline tree, and could not even tell the report's COLUMN header apart from a GROUP band,
    because both resolved the one literal 'TyTreeHeader'. Its parts are now:
      TyListView               the frame (this key)
      TyListViewItem           a row / flow cell, per state
      TyListViewHeader         the report column-header band
      TyListViewHeaderSection  one column-header cell
      TyListViewGroupHeader    the collapsible group band (was welded to the header band)
      TyListViewCheckBox       the row checkbox
      TyListViewLine           the grid lines   (previously had no token at all)
      TyListViewMarquee        the rubber band  (previously had no token at all) }
  Result := 'TyListView';
end;

procedure TTyListView.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  if FVScroll <> nil then FVScroll.Controller := AValue;
  if FHScroll <> nil then FHScroll.Controller := AValue;
  { Rule 3: push the controller down, else an inline editor inside a single-instance-themed
    list pops up wearing the global default skin. }
  if FEditor <> nil then FEditor.Controller := AValue;
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

function TTyListView.GetItemGroup(AItemIndex: Integer): Integer;
begin
  Result := -1;
  if FOwnerData then
  begin
    if Assigned(FOnGetItemGroup) then
      FOnGetItemGroup(Self, AItemIndex, Result);   { item index in, GROUP index out (var) }
    Exit;
  end;
  if (AItemIndex >= 0) and (AItemIndex < FItems.Count) then
    Result := FItems[AItemIndex].GroupIndex;
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
  if UseGroupedLayout then
  begin
    { Grouped: FOrder holds only visible items, FRank has -1 for collapsed/out-of-range. }
    BuildGroupedOrder;
    Exit;
  end;
  cnt := GetItemCount;
  SetLength(FOrder, cnt);
  SetLength(FRank, cnt);
  for i := 0 to cnt - 1 do
  begin
    FOrder[i] := i;   { display i shows item i }
    FRank[i]  := i;   { item i sits at display i }
  end;
end;

{ ---------------------------------------------------------------------------
  Grouping engine (SP2b)
  --------------------------------------------------------------------------- }

function TTyListView.UseGroupedLayout: Boolean;
begin
  { lvsList (column-major) cannot host group bands, so it falls back to the flat SP1 path. }
  Result := FGroupView and (FViewStyle <> lvsList);
end;

function TTyListView.GroupHeaderHeightPx: Integer;
begin
  Result := ScaleI(ActiveController.Metric('--listview-group-header-height', TyLvGroupHeaderH));
end;

{ Stable merge sort of a sub-array by the SAME comparator Sort uses (ties by item index, so
  it stays stable). ABuf is a caller-owned scratch buffer at least AHi+1 long. }
procedure TTyListView.MergeSortRange(var A: TTyIntArray; ALo, AHi: Integer; var ABuf: TTyIntArray);
var
  mid, i, j, k: Integer;
begin
  if ALo >= AHi then Exit;
  mid := (ALo + AHi) div 2;
  MergeSortRange(A, ALo, mid, ABuf);
  MergeSortRange(A, mid + 1, AHi, ABuf);
  i := ALo; j := mid + 1; k := ALo;
  while (i <= mid) and (j <= AHi) do
  begin
    if CompareItems(A[i], A[j]) <= 0 then
    begin
      ABuf[k] := A[i]; Inc(i);
    end
    else
    begin
      ABuf[k] := A[j]; Inc(j);
    end;
    Inc(k);
  end;
  while i <= mid do begin ABuf[k] := A[i]; Inc(i); Inc(k); end;
  while j <= AHi do begin ABuf[k] := A[j]; Inc(j); Inc(k); end;
  for k := ALo to AHi do
    A[k] := ABuf[k];
end;

procedure TTyListView.BuildGroupedOrder;
var
  cnt, gcnt, i, g, bucket, total, p, k, b, maxLen: Integer;
  itemBucket: TTyIntArray;         { item index -> bucket index (0..gcnt, gcnt = implicit) }
  fillPos:    TTyIntArray;         { running write cursor per bucket }
  buckets:    array of TTyIntArray;{ length gcnt+1; each holds ITEM indices in natural order }
  infoArray:  TTyListGroupInfoArray;
  buf:        TTyIntArray;
  m:          TTyListMetrics;
  collapsed:  Boolean;
begin
  { Explicit init of the managed locals (FPC hint 5091). }
  itemBucket := nil;
  fillPos := nil;
  buckets := nil;
  infoArray := nil;
  buf := nil;
  cnt  := GetItemCount;
  gcnt := FGroups.Count;

  { Pass 1: classify each item into a bucket (two-pass fill avoids O(n^2) append growth). }
  SetLength(itemBucket, cnt);
  SetLength(buckets, gcnt + 1);
  SetLength(fillPos, gcnt + 1);   { zero-filled }
  for i := 0 to cnt - 1 do
  begin
    g := GetItemGroup(i);                     { item index -> group index (or -1) }
    if (g < 0) or (g >= gcnt) then
      bucket := gcnt                          { implicit headerless bucket, after all real groups }
    else
      bucket := g;
    itemBucket[i] := bucket;
    Inc(fillPos[bucket]);
  end;
  for b := 0 to gcnt do
  begin
    SetLength(buckets[b], fillPos[b]);
    fillPos[b] := 0;
  end;
  { Pass 2: fill buckets in ascending item index = the group-local natural order. }
  for i := 0 to cnt - 1 do
  begin
    bucket := itemBucket[i];
    buckets[bucket][fillPos[bucket]] := i;
    Inc(fillPos[bucket]);
  end;

  { Per-bucket stable sort with the active comparator (only when a sort column is set). }
  if FSortColumn >= 0 then
  begin
    maxLen := 0;
    for b := 0 to gcnt do
      if Length(buckets[b]) > maxLen then maxLen := Length(buckets[b]);
    SetLength(buf, maxLen);
    for b := 0 to gcnt do
      if Length(buckets[b]) > 1 then
        MergeSortRange(buckets[b], 0, High(buckets[b]), buf);
  end;

  { Concatenate the NON-collapsed buckets into FOrder (display positions cover visible items
    only). The implicit bucket (b = gcnt) is never collapsible. }
  total := 0;
  for b := 0 to gcnt do
  begin
    collapsed := (b < gcnt) and FGroups[b].Collapsed;
    if not collapsed then Inc(total, Length(buckets[b]));
  end;
  SetLength(FOrder, total);
  p := 0;
  for b := 0 to gcnt do
  begin
    collapsed := (b < gcnt) and FGroups[b].Collapsed;
    if collapsed then Continue;
    for k := 0 to High(buckets[b]) do
    begin
      FOrder[p] := buckets[b][k];   { display p shows this item }
      Inc(p);
    end;
  end;

  { FRank: -1 everywhere (covers collapsed + out-of-range), then filled from FOrder. }
  SetLength(FRank, cnt);
  for i := 0 to cnt - 1 do
    FRank[i] := -1;
  for p := 0 to High(FOrder) do
    FRank[FOrder[p]] := p;         { item FOrder[p] lives at display p }

  { Info array parallels the buckets: real groups carry a header, the implicit bucket does not
    and is never collapsed. Cache the vertical map (the sole grouped geometry source). }
  SetLength(infoArray, gcnt + 1);
  for b := 0 to gcnt - 1 do
  begin
    infoArray[b].Count     := Length(buckets[b]);
    infoArray[b].Collapsed := FGroups[b].Collapsed;
    infoArray[b].HasHeader := True;
  end;
  infoArray[gcnt].Count     := Length(buckets[gcnt]);
  infoArray[gcnt].Collapsed := False;
  infoArray[gcnt].HasHeader := False;

  m := CurrentMetrics;
  FGroupMap := TyListBuildGroupMap(infoArray, m, GroupHeaderHeightPx);
end;

{ Re-derive the metric-dependent map (Tops) from the cached info array (Counts/Collapsed/
  HasHeader are metric-independent, so FOrder/FRank need not be rebuilt). O(G). Keeps grouped
  geometry correct after a resize or a scrollbar-visibility flip changed the metrics. }
procedure TTyListView.RefreshGroupMap;
var
  m: TTyListMetrics;
begin
  m := CurrentMetrics;
  FGroupMap := TyListBuildGroupMap(FGroupMap.Groups, m, GroupHeaderHeightPx);
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
  { Contract: judge staleness by FRank, not FOrder. FRank is always ItemCount long; FOrder is
    only the VISIBLE count under grouping (shorter whenever a group is collapsed), so testing
    it here would force a needless rebuild every pass once anything is collapsed. In the flat
    path the two lengths always move together, so this is behaviourally identical there. }
  if Length(FRank) <> cnt then
  begin
    RebuildOrder;
    if FAutoSort and (FSortColumn >= 0) then
      Sort;   { re-permutes FOrder + SyncRank }
  end
  else if UseGroupedLayout then
    RefreshGroupMap;   { metrics may have changed (resize / scrollbar flip); keep Tops fresh }
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
var
  before: TTyIntArray;
begin
  { Ask first: a vetoed change must leave the control exactly as it was. }
  if not CanChange(AItem, ctState) then Exit;
  before := SnapshotSelection;
  EnsureSelectedLen;
  ClearAllBits;
  if (AItem >= 0) and FMultiSelect and (AItem < Length(FSelected)) then
    FSelected[AItem] := True;
  FItemIndex := AItem;
  FAnchor    := AItem;
  Invalidate;
  { LCL order: Change first, then DoSelectItem (customlistview.inc:405-406). }
  DoChange(AItem, ctState);
  FireSelectionDelta(before);
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

procedure TTyListView.DoChange(AIndex: Integer; AChange: TTyItemChange);
begin
  if Assigned(FOnChange) then FOnChange(Self, AIndex, AChange);
end;

function TTyListView.CanChange(AIndex: Integer; AChange: TTyItemChange): Boolean;
begin
  { LCL's CanChange (customlistview.inc:208): default True, the host lowers it. Unlike LCL
    -- where the veto only ever reaches the Win32 widgetset -- this control is its own
    "widgetset", so the answer is honoured on every platform. }
  Result := True;
  if Assigned(FOnChanging) then
    FOnChanging(Self, AIndex, AChange, Result);
end;

procedure TTyListView.DoSelectItem(AIndex: Integer; ASelected: Boolean);
begin
  if Assigned(FOnSelectItem) then FOnSelectItem(Self, AIndex, ASelected);
end;

function TTyListView.SnapshotSelection: TTyIntArray;
var
  i, n, cnt: Integer;
begin
  Result := nil;
  { Nobody listening -> no scan and no allocation. This is what keeps a virtual list with a
    million rows from paying for a delta it would only throw away. }
  if not Assigned(FOnSelectItem) then Exit;
  cnt := GetItemCount;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    SetLength(Result, cnt);
    n := 0;
    for i := 0 to cnt - 1 do
      if (i < Length(FSelected)) and FSelected[i] then
      begin
        Result[n] := i;
        Inc(n);
      end;
    SetLength(Result, n);
  end
  else if (FItemIndex >= 0) and (FItemIndex < cnt) then
  begin
    { Single mode: the selection IS the focused item (see IsSelectedItem); the bit array is
      not consulted, so reading it here would report a stale multi-mode selection. }
    SetLength(Result, 1);
    Result[0] := FItemIndex;
  end;
end;

procedure TTyListView.FireSelectionDelta(const ABefore: TTyIntArray);
var
  after: TTyIntArray;
  a, b: Integer;
begin
  if not Assigned(FOnSelectItem) then Exit;
  after := SnapshotSelection;
  { Both lists are ascending, so one merge walk finds every difference in O(n) and reports
    the rows in item order. }
  a := 0;
  b := 0;
  while (a < Length(ABefore)) or (b < Length(after)) do
  begin
    if (b >= Length(after)) or
       ((a < Length(ABefore)) and (ABefore[a] < after[b])) then
    begin
      DoSelectItem(ABefore[a], False);   { was selected, is not: the abandoned row }
      Inc(a);
    end
    else if (a >= Length(ABefore)) or (after[b] < ABefore[a]) then
    begin
      DoSelectItem(after[b], True);      { newly selected }
      Inc(b);
    end
    else
    begin
      Inc(a);                            { in both: unchanged, stays silent }
      Inc(b);
    end;
  end;
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
  AMetrics.HGap := ScaleI(ActiveController.Metric('--listview-hgap', TyLvHGap));
  AMetrics.VGap := ScaleI(ActiveController.Metric('--listview-vgap', TyLvVGap));
  AMetrics.Pad  := ScaleI(ActiveController.Metric('--listview-cell-padding', TyLvPad));
  if FViewStyle in [lvsIcon, lvsTile] then icon := ActiveController.Metric('--listview-large-icon-size', TyLvLargeIcon) else icon := ActiveController.Metric('--listview-small-icon-size', TyLvSmallIcon);
  AMetrics.IconPx := ScaleI(icon);
  AMetrics.LabelH := ScaleI(ActiveController.Metric('--listview-label-height', TyLvLabelH));
  case FViewStyle of
    lvsIcon: AMetrics.LabelW := ScaleI(ActiveController.Metric('--listview-icon-label-width', TyLvIconLabelW));
    lvsTile: AMetrics.LabelW := ScaleI(ActiveController.Metric('--listview-tile-label-width', TyLvTileLabelW));
  else
    AMetrics.LabelW := ScaleI(ActiveController.Metric('--listview-small-label-width', TyLvSmallLabelW));
  end;
  AMetrics.RowH   := ScaleI(GetRowHeight);
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
  sb := ScaleI(ActiveController.Metric('--scrollbar-size', TyScrollbarSize));
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
  sb  := ScaleI(ActiveController.Metric('--scrollbar-size', TyScrollbarSize));
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
    { Grouped height comes from the group map (header bands + per-group bodies), rebuilt for
      THESE pass metrics from the stable info array so the two-pass convergence stays correct. }
    if UseGroupedLayout then
      ext.cy := TyListGroupContentHeight(TyListBuildGroupMap(FGroupMap.Groups, m, GroupHeaderHeightPx));
    needV := vertCap and (ext.cy > vh - m.HeaderH);
    needH := horzCap and (ext.cx > vw);
  end;

  vw := ClientWidth  - IfThen(needV, sb, 0);
  vh := ClientHeight - IfThen(needH, sb, 0);
  if vw < 0 then vw := 0;
  if vh < 0 then vh := 0;
  FillMetrics(m, vw, vh);
  ext := TyListContentExtent(cnt, m);
  if UseGroupedLayout then
    ext.cy := TyListGroupContentHeight(TyListBuildGroupMap(FGroupMap.Groups, m, GroupHeaderHeightPx));

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
  EndEdit(True);   { rule 4: the edited cell scrolls away — commit + close before it moves }
  FOffsetY := FVScroll.Position;
  Invalidate;
end;

procedure TTyListView.HScrollChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  EndEdit(True);   { rule 4 }
  FOffsetX := FHScroll.Position;
  Invalidate;
end;

{ ---------------------------------------------------------------------------
  Sorting
  --------------------------------------------------------------------------- }

procedure TTyListView.DoItemActivate(AIndex: Integer);
begin
  if Assigned(FOnItemActivate) then FOnItemActivate(Self, AIndex);
end;

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
  { Rule 4: rows move under a sort. Commit + close the editor first so it never hangs over a
    stale cell. (FEditItem is an item index, so a commit lands on the right row regardless.)
    EndEdit clears FEditItem before CommitEdit, so the caption write this triggers cannot
    recurse back into Sort. }
  EndEdit(True);
  if UseGroupedLayout then
  begin
    { Grouped: the order build already sorts each bucket by the same comparator. }
    BuildGroupedOrder;
    Invalidate;
    Exit;
  end;
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
  { Rule 5: if the row being edited vanished (Clear / shorter ItemCount / deletion), CANCEL the
    edit — never commit into a row that no longer exists. }
  if (FEditor <> nil) and (FEditItem >= 0) and (FEditItem >= cnt) then
    EndEdit(False);
  SetLength(FSelected, cnt);   { keep existing bits; new slots default False }
  RebuildOrder;                { identity order + rank }
  ClampIndex(FItemIndex);
  ClampIndex(FAnchor);
  ClampIndex(FHot);
  if FAutoSort and (FSortColumn >= 0) then
    Sort                       { rule 9: a sort commits the surviving edit (EndEdit inside Sort) }
  else if (FEditor <> nil) and (FEditItem >= 0) and (FEditItem < GetItemCount) then
    { No sort, but RebuildOrder may have moved the edited row: follow it (edit survives, rule 9). }
    FEditor.BoundsRect := EditorBoundsFor(FEditItem);
  Invalidate;
end;

procedure TTyListView.ItemsCollectionChanged(Sender: TObject);
begin
  if FOwnerData then Exit;     { the collection is dormant in virtual mode }
  ItemsChanged;
end;

procedure TTyListView.ItemsCollectionNotify(Sender: TObject; AItem: TCollectionItem;
  AAction: TCollectionNotification);
begin
  if FOwnerData then Exit;     { no collection lifetime to report in virtual mode }
  if AItem = nil then Exit;
  case AAction of
    cnAdded:      DoInsert(AItem.Index);
    { cnExtracting ONLY. Delete(i) fires cnDeleting and then, through the item's destructor,
      cnExtracting (collect.inc:391-398); Clear and the destructor go straight to the item's
      Free and fire cnExtracting alone (:362-365). Reacting to both would report every
      Delete twice and every Clear once -- an inconsistency the host cannot compensate for.
      cnExtracting is the one path every removal takes, and it still runs BEFORE the item
      leaves the list, which is what keeps the index and the Data payload valid. }
    cnExtracting: DoDeletion(AItem.Index);
  end;
end;

procedure TTyListView.DoInsert(AIndex: Integer);
begin
  if Assigned(FOnInsert) then FOnInsert(Self, AIndex);
end;

procedure TTyListView.DoDeletion(AIndex: Integer);
begin
  if Assigned(FOnDeletion) then FOnDeletion(Self, AIndex);
end;

function TTyListView.GetColumns: TTyColumns;
begin
  Result := FHeader.Columns;
end;

function TTyListView.GetColumn(AIndex: Integer): TTyColumn;
begin
  // Out of range is nil rather than an exception: `if LV.Column[i] <> nil` is how the
  // rest of this control's index-first surface is written.
  if (AIndex >= 0) and (AIndex < FHeader.Columns.Count) then
    Result := FHeader.Columns[AIndex]
  else
    Result := nil;
end;

function TTyListView.GetColumnCount: Integer;
begin
  Result := FHeader.Columns.Count;
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
  before: TTyIntArray;
begin
  if not FMultiSelect then Exit;
  EnsureSelectedLen;
  { Decide whether anything WOULD change before asking OnChanging: a Select All over an
    already-full selection is not a change and must not raise a veto prompt. }
  anyChanged := False;
  for i := 0 to High(FSelected) do
    if not FSelected[i] then begin anyChanged := True; Break; end;
  if not anyChanged then Exit;
  { -1: a bulk change has no single subject (LCL's nil Item). }
  if not CanChange(-1, ctState) then Exit;
  before := SnapshotSelection;
  for i := 0 to High(FSelected) do
    FSelected[i] := True;
  Invalidate;
  DoChange(-1, ctState);
  FireSelectionDelta(before);
end;

procedure TTyListView.ClearSelection;
var
  i: Integer;
  anyChanged: Boolean;
  before: TTyIntArray;
begin
  anyChanged := FItemIndex <> -1;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    for i := 0 to High(FSelected) do
      if FSelected[i] then begin anyChanged := True; Break; end;
  end;
  if not anyChanged then Exit;
  if not CanChange(-1, ctState) then Exit;
  before := SnapshotSelection;
  if FMultiSelect then
    for i := 0 to High(FSelected) do
      FSelected[i] := False;
  FItemIndex := -1;
  Invalidate;
  DoChange(-1, ctState);
  FireSelectionDelta(before);
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
var
  before: TTyIntArray;
begin
  if (AIndex < 0) or (AIndex >= GetItemCount) then Exit;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    if FSelected[AIndex] = AValue then Exit;
    if not CanChange(AIndex, ctState) then Exit;
    before := SnapshotSelection;
    FSelected[AIndex] := AValue;
    Invalidate;
    DoChange(AIndex, ctState);
    FireSelectionDelta(before);
  end
  else if AValue then
    SetSingleSelection(AIndex);
end;

{ ---------------------------------------------------------------------------
  Checkboxes
  --------------------------------------------------------------------------- }

procedure TTyListView.SetCheckboxes(AValue: Boolean);
begin
  if FCheckboxes = AValue then Exit;
  FCheckboxes := AValue;
  { Report mode only shifts the main column's icon+text at PAINT time; cell geometry and the
    content extent are unchanged, so a repaint is all that is needed (no UpdateScrollBars). }
  Invalidate;
end;

function TTyListView.GetChecked(AIndex: Integer): Boolean;
begin
  { The control does NOT own check state: read lisChecked through the single data path. }
  Result := lisChecked in GetItemState(AIndex);
end;

procedure TTyListView.SetChecked(AIndex: Integer; AValue: Boolean);
begin
  { Public writer: AIndex is an ITEM index. Out-of-range is silently ignored (never raises). }
  if (AIndex < 0) or (AIndex >= GetItemCount) then Exit;
  if GetChecked(AIndex) = AValue then Exit;
  SetItemChecked(AIndex, AValue);   { collection: writes lisChecked; owner-data: no-op }
  if Assigned(FOnItemChecked) then FOnItemChecked(Self, AIndex);   { item index }
  { A check IS item state, so it is an OnChange(ctState) as well as the dedicated
    OnItemChecked. Without this an app that listens to OnChange to keep a summary line in
    sync sees selection moves but never a tick. Deliberately NOT routed through CanChange:
    the checkbox path has its own gate (a host that wants to refuse a tick simply does not
    write Checked), and a second veto for the same action is a trap, not a feature. }
  DoChange(AIndex, ctState);
  Invalidate;
end;

procedure TTyListView.SetItemChecked(AIndex: Integer; AValue: Boolean);
var
  st: TTyListItemStates;
begin
  if FOwnerData then Exit;   { the app owns the state; it mutates its store from OnItemChecked }
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  st := FItems[AIndex].States;
  if AValue then Include(st, lisChecked) else Exclude(st, lisChecked);
  FItems[AIndex].States := st;
end;

{ ---------------------------------------------------------------------------
  Public API — hit-testing / scrolling
  --------------------------------------------------------------------------- }

function TTyListView.GetItemAt(X, Y: Integer): Integer;
var
  m: TTyListMetrics;
  pos, g, idx: Integer;
begin
  SyncArrays;
  m := CurrentMetrics;
  if UseGroupedLayout then
  begin
    { grouped hit -> (group, index-in-group); a header hit or a miss both yield -1 }
    if TyListGroupHitTest(FGroupMap, Point(X, Y), m, GroupHeaderHeightPx,
         FOffsetX, FOffsetY, g, idx) and (idx >= 0) then
      Result := DisplayToItem(TyListGroupDisplayPos(FGroupMap, g, idx))  { (g,idx)->display->item }
    else
      Result := -1;
    Exit;
  end;
  { display pos from the pure inverse, then map back to a stable item index }
  pos := TyListItemAt(Point(X, Y), GetItemCount, m, FOffsetX, FOffsetY);
  Result := DisplayToItem(pos);   { display pos -> item index (-1 stays -1) }
end;

function TTyListView.GetHitPart(X, Y: Integer): TTyListHitPart;
var
  m: TTyListMetrics;
  logX, logScroll, pos, g, idx: Integer;
  cell, chk: TRect;
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

  if UseGroupedLayout then
  begin
    { A group band reuses lhpHeader (rule 5 forbids adding lhpGroupHeader to the layout
      unit's enum): a hit with index-in-group = -1 is the band. MouseDown re-runs the same
      TyListGroupHitTest to get the group index for the collapse toggle, so no new enum value
      is needed to distinguish it. }
    if TyListGroupHitTest(FGroupMap, Point(X, Y), m, GroupHeaderHeightPx,
         FOffsetX, FOffsetY, g, idx) then
    begin
      if idx < 0 then
        Exit(lhpHeader);        { group header band }
      if FCheckboxes then
      begin
        cell := TyListGroupItemRect(FGroupMap, g, idx, m, GroupHeaderHeightPx, FOffsetX, FOffsetY);
        chk  := CheckRectForCell(cell);
        if (chk.Right > chk.Left) and PtInRect(chk, Point(X, Y)) then
          Exit(lhpCheck);
      end;
      Exit(lhpLabel);
    end;
    Exit(lhpNowhere);
  end;

  pos := TyListItemAt(Point(X, Y), GetItemCount, m, FOffsetX, FOffsetY);   { -> display pos }
  if pos < 0 then
    Exit(lhpNowhere);
  if FCheckboxes then
  begin
    { Same geometry the painter uses (CheckRectForCell -> TyListCheckRect): a hit inside the
      box is lhpCheck, so a click there toggles the check instead of selecting the row. }
    cell := TyListItemRect(pos, GetItemCount, m, FOffsetX, FOffsetY);
    chk  := CheckRectForCell(cell);
    if (chk.Right > chk.Left) and PtInRect(chk, Point(X, Y)) then
      Exit(lhpCheck);
  end;
  Result := lhpLabel;
end;

procedure TTyListView.ScrollIntoView(AIndex: Integer);
var
  m: TTyListMetrics;
  pos, regionH, gv, iv: Integer;
  rect0: TRect;
  vertCap, horzCap: Boolean;
begin
  SyncArrays;
  if (AIndex < 0) or (AIndex >= GetItemCount) then Exit;
  m := CurrentMetrics;
  pos := ItemToDisplay(AIndex);        { item index -> display pos }
  if pos < 0 then Exit;                { in a collapsed group (FRank = -1): silent no-op }
  { Cell at zero scroll = its content-space rect (plus HeaderH). }
  if UseGroupedLayout then
  begin
    if not TyListGroupOfDisplayPos(FGroupMap, pos, gv, iv) then Exit;   { display -> (g,idx) }
    rect0 := TyListGroupItemRect(FGroupMap, gv, iv, m, GroupHeaderHeightPx, 0, 0);
  end
  else
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
  Inline rename
  --------------------------------------------------------------------------- }

function TTyListView.Editing: Boolean;
begin
  Result := (FEditor <> nil) and (FEditItem >= 0) and FEditor.Visible;
end;

{ The editor's bounds for an ITEM index = the item's label rect, derived from the same
  TyListItemRect the painter uses (report: the main column's text rect after the checkbox +
  icon shifts; flow: the cell's label rect). No geometry is invented here. }
function TTyListView.EditorBoundsFor(AIndex: Integer): TRect;
var
  m: TTyListMetrics;
  pos, mainIdx, colLeft, colRight, cbShift, imgPx, ii, pad, ix, gPos, iPos: Integer;
  cell, chk: TRect;
  mainCol: TTyColumn;
begin
  Result := Rect(0, 0, 0, 0);
  m := CurrentMetrics;
  pos := ItemToDisplay(AIndex);   { item index -> display pos }
  if pos < 0 then Exit;
  if UseGroupedLayout then
  begin
    if not TyListGroupOfDisplayPos(FGroupMap, pos, gPos, iPos) then Exit;  { display -> (g,idx) }
    cell := TyListGroupItemRect(FGroupMap, gPos, iPos, m, GroupHeaderHeightPx, FOffsetX, FOffsetY);
  end
  else
    cell := TyListItemRect(pos, GetItemCount, m, FOffsetX, FOffsetY);

  if FViewStyle = lvsReport then
  begin
    mainIdx := FHeader.MainColumn;
    if (mainIdx < 0) or (mainIdx >= FHeader.Columns.Count) then Exit;
    mainCol := FHeader.Columns.Items[mainIdx] as TTyColumn;
    colLeft  := cell.Left + ScaleI(mainCol.Left);
    colRight := colLeft + ScaleI(mainCol.Width);
    cbShift := 0;
    if FCheckboxes then
    begin
      chk := CheckRectForCell(cell);
      if chk.Right > chk.Left then cbShift := ScaleI(ActiveController.Metric('--listview-check-size', TyLvCheckPx)) + ScaleI(ActiveController.Metric('--listview-cell-padding', TyLvPad));
    end;
    imgPx := ScaleI(ActiveController.Metric('--listview-small-icon-size', TyLvSmallIcon));
    ii := GetItemImageIndex(AIndex, mainIdx);
    if (FSmallImages <> nil) and (ii >= 0) then
      Result := Rect(colLeft + cbShift + ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)) + imgPx + ScaleI(2),
                     cell.Top, colRight - ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)), cell.Bottom)
    else
      Result := Rect(colLeft + cbShift + ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)),
                     cell.Top, colRight - ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)), cell.Bottom);
  end
  else
  begin
    pad := ScaleI(ActiveController.Metric('--listview-cell-padding', TyLvPad));
    if FViewStyle in [lvsIcon, lvsTile] then imgPx := ScaleI(ActiveController.Metric('--listview-large-icon-size', TyLvLargeIcon))
    else imgPx := ScaleI(ActiveController.Metric('--listview-small-icon-size', TyLvSmallIcon));
    case FViewStyle of
      lvsIcon:
        { icon on top, label below (mirrors RenderFlowCell) }
        Result := Rect(cell.Left + pad, cell.Top + 2 * pad + imgPx + pad,
                       cell.Right - pad, cell.Bottom - pad);
      lvsTile:
        begin
          { first text line, right of the icon (past the checkbox, if any) }
          ix := cell.Left + pad + FlowCheckShift(cell) + imgPx + 2 * pad;
          Result := Rect(ix, cell.Top + pad, cell.Right - pad,
                         cell.Top + pad + ScaleI(ActiveController.Metric('--listview-label-height', TyLvLabelH)));
        end;
    else
      begin
        { lvsSmallIcon / lvsList: single label right of the icon (past the checkbox, if any) }
        ix := cell.Left + pad + FlowCheckShift(cell) + imgPx + 2 * pad;
        Result := Rect(ix, cell.Top, cell.Right - pad, cell.Bottom);
      end;
    end;
  end;
end;

procedure TTyListView.BeginEdit(AIndex: Integer);
var
  allow: Boolean;
begin
  { Rule 2: the base constructor runs Resize before this subclass creates FEditor, so every
    editor-touching path guards against a nil editor. }
  if FEditor = nil then Exit;
  if FReadOnly then Exit;                          { opt-in, like toEditable }
  if (AIndex < 0) or (AIndex >= GetItemCount) then Exit;
  allow := True;
  if Assigned(FOnEditing) then FOnEditing(Self, AIndex, allow);   { item index; may veto }
  if not allow then Exit;
  if FEditItem = AIndex then Exit;
  if FEditItem >= 0 then EndEdit(True);            { commit a prior edit before starting a new one }

  FEditItem := AIndex;                             { rule 6/9: store the ITEM index }
  FEditor.Controller := Self.Controller;           { rule 3: themed like the list }
  FEditor.Text := GetItemText(AIndex, 0);          { column 0 = the caption }
  FEditor.BoundsRect := EditorBoundsFor(AIndex);
  FEditor.Visible := True;
  try
    if CanFocus and FEditor.CanFocus then FEditor.SetFocus;
  except
    { headless / test environments may reject focus }
  end;
  if FEditor.CanFocus then FEditor.SelectAll;
  Invalidate;
end;

procedure TTyListView.EndEdit(ACommit: Boolean; ARestoreFocus: Boolean);
var
  item: Integer;
  txt: string;
begin
  if FEditor = nil then Exit;          { rule 2 }
  if FEditItem < 0 then Exit;
  if FEndingEdit then Exit;            { re-entry guard: Visible:=False / SetFocus refire OnExit }
  FEndingEdit := True;
  try
    item := FEditItem;                 { rule 6/9: an ITEM index — stable across any re-sort }
    txt  := FEditor.Text;
    FEditItem := -1;
    FEditor.Visible := False;
    if ACommit then
    begin
      { Rule 6: re-confirm the row still exists after any async / modal boundary before
        committing into it. }
      if (item >= 0) and (item < GetItemCount) then
        CommitEdit(item, txt)
      else
        Invalidate;
    end
    else
      Invalidate;
    { Rule 7: a keyboard commit/cancel returns focus to the list; a focus-loss commit does
      NOT (focus is already elsewhere), so the caller passes ARestoreFocus accordingly. }
    if ARestoreFocus then
      try
        if CanFocus then SetFocus;
      except
      end;
  finally
    FEndingEdit := False;
  end;
end;

procedure TTyListView.CommitEdit(AIndex: Integer; const AText: string);
var
  s: string;
begin
  if (AIndex < 0) or (AIndex >= GetItemCount) then Exit;
  s := AText;
  if Assigned(FOnEdited) then FOnEdited(Self, AIndex, s);   { item index; app may rewrite text }
  if s = '' then Exit;                 { '' after the handler means "abandon" (per contract) }
  { Collection mode writes the caption; OwnerData does nothing — the app updated its own store
    inside OnEdited. Same single-writer discipline as SetItemChecked. }
  if not FOwnerData then
  begin
    if (AIndex >= 0) and (AIndex < FItems.Count) then
      FItems[AIndex].Caption := s;
  end;
  { The one place this control produces a TEXT change, and the reason OnChange carries a
    reason at all: a host filtering on ctText hears renames without also hearing every
    selection move. A descendant that overrides CommitEdit WITHOUT calling inherited (the
    shell view renames on disk instead) owns this notification itself. }
  DoChange(AIndex, ctText);
  Invalidate;
end;

procedure TTyListView.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN: begin EndEdit(True,  True); Key := 0; end;   { commit + return focus (rule 7) }
    VK_ESCAPE: begin EndEdit(False, True); Key := 0; end;   { cancel + return focus (rule 7) }
  end;
end;

procedure TTyListView.EditorExit(Sender: TObject);
begin
  { Rule 1: during form teardown the Items may already be freed — never commit into them. }
  if csDestroying in ComponentState then Exit;
  if FEditor = nil then Exit;   { rule 2 }
  { Rule 7: focus-loss commits but does NOT restore focus (it has already moved away). }
  if (FEditItem >= 0) and not FEndingEdit then EndEdit(True, False);
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

{ Effective report row height in logical px: an explicit RowHeight wins; otherwise follow
  the theme's --row-height token, which the density pack raises for modern density. Resolved
  live (not cached) so toggling Controller.Density re-heights the rows on the next layout. }
function TTyListView.GetRowHeight: Integer;
begin
  if FRowHeightExplicit then
    Result := FRowHeight
  else
    Result := ActiveController.Metric('--row-height', TyLvRowHeight);
end;

procedure TTyListView.SetRowHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  FRowHeightExplicit := True;   { even if the value equals the fallback, the host meant to pin it }
  if FRowHeight = AValue then Exit;
  FRowHeight := AValue;
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyListView.SetViewStyle(AValue: TTyListViewStyle);
begin
  if FViewStyle = AValue then Exit;
  EndEdit(True);   { rule 4: the cell geometry changes wholesale — commit + close first }
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
  before: TTyIntArray;
begin
  if FMultiSelect = AValue then Exit;
  EnsureSelectedLen;
  { Snapshot under the OLD mode: SnapshotSelection reads the bits in multi mode and the
    focused item in single mode, so collapsing to single is exactly where the difference
    (every row but the survivor drops out) has to be captured. No CanChange here — this is
    a property write, not an item change; a host that wants to refuse it just does not
    write the property. }
  before := SnapshotSelection;

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
  DoChange(-1, ctState);
  FireSelectionDelta(before);
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

procedure TTyListView.SetGroupView(AValue: Boolean);
begin
  if FGroupView = AValue then Exit;
  EndEdit(True);   { rule 4: the whole layout changes — commit + close the editor first }
  FGroupView := AValue;
  { The content extent changes wholesale; reset scroll so nothing is stranded off-content. }
  FOffsetX := 0;
  FOffsetY := 0;
  RebuildOrder;    { flat <-> grouped: FOrder/FRank lengths + FGroupMap all re-derive }
  ClampIndex(FItemIndex);
  ClampIndex(FAnchor);
  ClampIndex(FHot);
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyListView.SetGroups(AValue: TTyListGroups);
begin
  FGroups.Assign(AValue);   { fires GroupsChanged via the collection's OnChange }
end;

{ A group's caption/collapsed edit, or an add/remove, re-derives the order (item->group
  membership and the concat of expanded buckets both depend on it). }
procedure TTyListView.GroupsChanged(Sender: TObject);
begin
  if csLoading in ComponentState then Exit;
  if not UseGroupedLayout then
  begin
    { Groups edited while not actually grouping: nothing to reorder, just reflect a caption
      change should grouping later turn on. }
    Invalidate;
    Exit;
  end;
  RebuildOrder;
  ClampIndex(FItemIndex);
  ClampIndex(FAnchor);
  ClampIndex(FHot);
  UpdateScrollBars;
  Invalidate;
end;

{ Header-click collapse toggle. Setting Collapsed fires GroupsChanged, which rebuilds the
  order + map and repaints; then OnGroupCollapsed reports the GROUP index. A focused item that
  falls into the now-collapsed group keeps FItemIndex (ItemToDisplay becomes -1, so it is
  simply not visible) — the contract accepts this; focus is not moved. }
procedure TTyListView.ToggleGroupCollapsed(AGroup: Integer);
begin
  if (AGroup < 0) or (AGroup >= FGroups.Count) then Exit;
  FGroups[AGroup].Collapsed := not FGroups[AGroup].Collapsed;
  if Assigned(FOnGroupCollapsed) then FOnGroupCollapsed(Self, AGroup);   { group index }
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
  { Borrowed from the collection's render cache -- no per-icon allocation and no per-icon
    resample. This is the hot path: with HotTrack a mouse move repaints the whole control,
    so every visible icon comes through here. The bitmap is owned by the cache, not us. }
  bmp := AList.CachedIndex(AImageIndex, ASizePx);
  if bmp <> nil then
    P.Bitmap.PutImage(AX, AY, bmp, dmDrawWithTransparency);
end;

function TTyListView.CheckRectForCell(const ACell: TRect): TRect;
var
  sub: TRect;
  mainIdx: Integer;
  mainCol: TTyColumn;
begin
  Result := Rect(0, 0, 0, 0);
  if not FCheckboxes then Exit;
  if FViewStyle = lvsReport then
  begin
    { Report: the box lives in the MAIN COLUMN's sub-rect. The layout unit knows nothing
      about columns, so compute that sub-rect here and pass it to the pure function. }
    mainIdx := FHeader.MainColumn;
    if (mainIdx < 0) or (mainIdx >= FHeader.Columns.Count) then Exit;
    mainCol := FHeader.Columns.Items[mainIdx] as TTyColumn;
    if not (coVisible in mainCol.Options) then Exit;
    sub := Rect(ACell.Left + ScaleI(mainCol.Left), ACell.Top,
                ACell.Left + ScaleI(mainCol.Left) + ScaleI(mainCol.Width), ACell.Bottom);
  end
  else
    sub := ACell;   { flow: the whole cell }
  Result := TyListCheckRect(sub, FViewStyle, ScaleI(ActiveController.Metric('--listview-check-size', TyLvCheckPx)), ScaleI(ActiveController.Metric('--listview-cell-padding', TyLvPad)));
end;

function TTyListView.FlowCheckShift(const ACell: TRect): Integer;
var
  chk: TRect;
begin
  Result := 0;
  if (not FCheckboxes) or (FViewStyle = lvsIcon) then Exit;
  chk := CheckRectForCell(ACell);
  if chk.Right > chk.Left then
    Result := ScaleI(ActiveController.Metric('--listview-check-size', TyLvCheckPx)) + ScaleI(ActiveController.Metric('--listview-cell-padding', TyLvPad));
end;

{ Draw the box resolving this control's own 'TyListViewCheckBox' token ([tysActive] when
  checked, '' otherwise) — no literal colours. Mirrors the checkbox path in TTyTreeView, but
  a skin can now size/tint a file list's boxes without touching the tree's. }
procedure TTyListView.RenderCheckBox(P: TTyPainter; const ABox: TRect; AChecked: Boolean);
var
  cb, S: TTyStyleSet;
begin
  if (ABox.Right <= ABox.Left) or (ABox.Bottom <= ABox.Top) then Exit;
  S := CurrentStyle;
  if AChecked then
    cb := ActiveController.Model.ResolveStyle('TyListViewCheckBox', '', [tysActive])
  else
    cb := ActiveController.Model.ResolveStyle('TyListViewCheckBox', '', []);
  if tpBackground in cb.Present then
    P.FillBackground(ABox, cb.Background, cb.BorderRadius)
  else
    P.FillBackground(ABox, S.Background, 2);
  if tpBorderColor in cb.Present then
    P.StrokeBorder(ABox, cb.BorderRadius, cb.BorderWidth, cb.BorderColor)
  else
    P.StrokeBorder(ABox, 2, 1, S.BorderColor);
  if AChecked then
  begin
    if tpTextColor in cb.Present then
      P.DrawGlyph(ABox, tgCheck, cb.TextColor, 2)
    else
      P.DrawGlyph(ABox, tgCheck, S.TextColor, 2);
  end;
end;

procedure TTyListView.RenderReportRow(P: TTyPainter; AIndex: Integer; const ACell: TRect;
  const AStyle: TTyStyleSet);
var
  posIdx, colIdx, colLeft, colRight, textLeft, mainCol, imgPx, ii, cbShift: Integer;
  col: TTyColumn;
  txt: string;
  tc: TTyColor;
  tr, chk: TRect;
begin
  mainCol := FHeader.MainColumn;
  if tpTextColor in AStyle.Present then tc := AStyle.TextColor
  else tc := CurrentStyle.TextColor;
  imgPx := ScaleI(ActiveController.Metric('--listview-small-icon-size', TyLvSmallIcon));
  for posIdx := 0 to FHeader.Columns.Count - 1 do
  begin
    col := FHeader.Columns.ColumnByPosition(posIdx);
    if col = nil then Continue;
    if not (coVisible in col.Options) then Continue;
    colIdx := col.Index;
    { report cell rect Left = -FOffsetX; column x = that + Scale(col.Left) }
    colLeft  := ACell.Left + ScaleI(col.Left);
    colRight := colLeft + ScaleI(col.Width);
    textLeft := colLeft + ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin));
    if colIdx = mainCol then
    begin
      { When checkboxes are on the box occupies the main column's left; the icon+text shift
        right by CheckPx + Pad. The box rect comes from the single geometry source. }
      cbShift := 0;
      if FCheckboxes then
      begin
        chk := CheckRectForCell(ACell);
        if chk.Right > chk.Left then
        begin
          RenderCheckBox(P, chk, GetChecked(AIndex));   { AIndex is an item index }
          cbShift := ScaleI(ActiveController.Metric('--listview-check-size', TyLvCheckPx)) + ScaleI(ActiveController.Metric('--listview-cell-padding', TyLvPad));
        end;
      end;
      textLeft := colLeft + cbShift + ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin));
      ii := GetItemImageIndex(AIndex, colIdx);
      if (FSmallImages <> nil) and (ii >= 0) then
      begin
        DrawImage(P, FSmallImages, ii, colLeft + cbShift + ScaleI(2),
          ACell.Top + (ACell.Bottom - ACell.Top - imgPx) div 2, imgPx);
        textLeft := colLeft + cbShift + ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)) + imgPx + ScaleI(2);
      end;
    end;
    txt := GetItemText(AIndex, colIdx);
    tr := Rect(textLeft, ACell.Top, colRight - ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)), ACell.Bottom);
    if tr.Left < tr.Right then
      P.DrawText(tr, txt, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
        tc, col.Alignment, tlCenter, True);
  end;
end;

procedure TTyListView.RenderFlowCell(P: TTyPainter; AIndex: Integer; const ACell: TRect;
  const AStyle: TTyStyleSet);
var
  imgList: TTyVirtualImageList;
  imgPx, ii, pad, ix, iy, tx, cbShift: Integer;
  tc: TTyColor;
  lbl, sub: string;
  tr, chk: TRect;
begin
  if tpTextColor in AStyle.Present then tc := AStyle.TextColor
  else tc := CurrentStyle.TextColor;
  pad := ScaleI(ActiveController.Metric('--listview-cell-padding', TyLvPad));
  { The icon+label of every flow mode but lvsIcon shift right to make room for the box. }
  cbShift := FlowCheckShift(ACell);
  { Must agree with FillMetrics, which sizes the cell from the LARGE icon for both lvsIcon
    and lvsTile. Testing only lvsIcon here drew a 16px glyph inside a cell laid out for 48. }
  if FViewStyle in [lvsIcon, lvsTile] then
  begin
    imgList := FLargeImages; imgPx := ScaleI(ActiveController.Metric('--listview-large-icon-size', TyLvLargeIcon));
  end
  else
  begin
    imgList := FSmallImages; imgPx := ScaleI(ActiveController.Metric('--listview-small-icon-size', TyLvSmallIcon));
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
        ix := ACell.Left + pad + cbShift;
        iy := ACell.Top + (ACell.Bottom - ACell.Top - imgPx) div 2;
        DrawImage(P, imgList, ii, ix, iy, imgPx);
        tx  := ix + imgPx + 2 * pad;
        sub := GetItemText(AIndex, 1);
        tr := Rect(tx, ACell.Top + pad, ACell.Right - pad, ACell.Top + pad + ScaleI(ActiveController.Metric('--listview-label-height', TyLvLabelH)));
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
      ix := ACell.Left + pad + cbShift;
      iy := ACell.Top + (ACell.Bottom - ACell.Top - imgPx) div 2;
      DrawImage(P, imgList, ii, ix, iy, imgPx);
      tx := ix + imgPx + 2 * pad;
      tr := Rect(tx, ACell.Top, ACell.Right - pad, ACell.Bottom);
      if tr.Left < tr.Right then
        P.DrawText(tr, lbl, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
          tc, taLeftJustify, tlCenter, True);
    end;
  end;
  { Flow modes OVERLAY the box (top-left for lvsIcon, left-centre otherwise) and do NOT
    change the cell size; draw it last so it sits on top of the icon/label. }
  if FCheckboxes then
  begin
    chk := CheckRectForCell(ACell);
    if chk.Right > chk.Left then
      RenderCheckBox(P, chk, GetChecked(AIndex));   { AIndex is an item index }
  end;
end;

procedure TTyListView.RenderItem(P: TTyPainter; AIndex: Integer; const ACell: TRect;
  const AStyle: TTyStyleSet; AStates: TTyStateSet);
begin
  { Highlight only selected / hovered cells (a resting TyListViewItem has no row fill). }
  if ((tysSelected in AStates) or (tysHover in AStates)) and (tpBackground in AStyle.Present) then
    P.FillBackground(ACell, AStyle.Background, 0);
  if FViewStyle = lvsReport then
    RenderReportRow(P, AIndex, ACell, AStyle)
  else
    RenderFlowCell(P, AIndex, ACell, AStyle);
end;

function TTyListView.HeaderImageList: TTyVirtualImageList;
begin
  { The header's OWN list when it has one, else the control's SmallImages.

    The fallback is not a convenience: Delphi and LCL resolve TListColumn.ImageIndex
    against the list view's SmallImages -- a TListView has no separate header list at all
    -- so this is the behaviour ported code expects, and one wired image list is enough
    for the ordinary case. Header.Images is the OVERRIDE, for a header that wants a set
    of its own; that is what TCustomHeaderControl.Images (comctrls.pp:4037) is.

    Once Header.Images is set it wins outright, even if it can draw nothing at the
    requested index -- an override that silently fell back would not be one. }
  Result := FHeader.Images;
  if Result = nil then Result := FSmallImages;
end;

procedure TTyListView.RenderHeader(P: TTyPainter; const M: TTyListMetrics;
  const AFrame: TTyStyleSet);
var
  hb, hs: TTyStyleSet;
  posIdx, colLeft, colRight, sortSz, textLeft, icoPx, icoGap: Integer;
  col: TTyColumn;
  cellR, tr, sortR: TRect;
  tc: TTyColor;
  useSec: Boolean;
  border: TBGRAPixel;
  icoList: TTyVirtualImageList;
begin
  { The REPORT column-header band and its cells. Distinct from the group band's key
    ('TyListViewGroupHeader'): the two used to share one literal, so a skin that wanted a flat
    column strip also got a flat group strip whether it wanted one or not. }
  hb := ActiveController.Model.ResolveStyle('TyListViewHeader', '', []);
  hs := ActiveController.Model.ResolveStyle('TyListViewHeaderSection', '', []);
  border := TyColorToBGRA(AFrame.BorderColor);

  { band background }
  if tpBackground in hb.Present then
    P.FillBackground(Rect(0, 0, M.ViewportW, M.HeaderH), hb.Background, 0)
  else if tpBackground in AFrame.Present then
    P.FillBackground(Rect(0, 0, M.ViewportW, M.HeaderH), AFrame.Background, 0);

  useSec := tpTextColor in hs.Present;
  if useSec then tc := hs.TextColor else tc := AFrame.TextColor;

  { The icon slot. Sized and spaced by theme tokens, not by the caption's margin: a skin
    that wants 20px header icons must not have to widen every caption inset to get them. }
  icoList := HeaderImageList;
  icoPx  := ScaleI(ActiveController.Metric('--listview-header-icon-size', TyLvHeaderIcon));
  icoGap := ScaleI(ActiveController.Metric('--listview-header-icon-gap', TyLvHeaderIconGap));

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

    textLeft := cellR.Left + ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin));
    { Column icon, left of the caption -- TTyColumn.ImageIndex (tyControls.Columns.pas:95),
      LCL's THeaderSection.ImageIndex (comctrls.pp:3991). The caption STEPS ASIDE for it:
      drawing the icon without moving textLeft would just stamp it over the first
      characters, which reads as a rendering fault rather than as an icon.
      Drawn through DrawImage -- the same borrowed-from-cache blit every item icon uses.
      Deliberately NOT TTyVirtualImageList.Draw: this path needs an explicit pixel SIZE,
      which Draw does not take (DrawIndex is the size-carrying form), and DrawImage is the
      allocation-free cache blit already on the hot path. Historical note, since the scar
      is still worth carrying: Draw's flag used to be AGhosted while LCL's carries Enabled
      in the same slot with the OPPOSITE sense, so a call written from LCL muscle memory
      compiled clean and inverted the result. Draw now matches LCL's order and polarity. }
    if (icoList <> nil) and (col.ImageIndex >= 0) and (icoPx > 0)
       and (textLeft + icoPx <= cellR.Right) then
    begin
      DrawImage(P, icoList, col.ImageIndex, textLeft,
        (M.HeaderH - icoPx) div 2, icoPx);
      Inc(textLeft, icoPx + icoGap);
    end;
    tr := Rect(textLeft, 0,
               cellR.Right - ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)) - sortSz, M.HeaderH);
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
      sortR := Rect(cellR.Right - sortSz - ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)), ScaleI(2),
                    cellR.Right - ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)), M.HeaderH - ScaleI(2));
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
  lineS: TTyStyleSet;
  border: TBGRAPixel;
begin
  { The rules have a token of their own now, so a report can be ruled in a colour that is NOT
    the frame's border -- the grid family already proves the shape with 'TyGridLine'
    (TTyCustomGrid.GridLineColor). Theme silent about it => the frame border, i.e. unchanged. }
  lineS := ActiveController.Model.ResolveStyle('TyListViewLine', '', []);
  if tpBackground in lineS.Present then
    border := TyColorToBGRA(lineS.Background.Color)
  else
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
  mq, sel: TTyStyleSet;
  acc: TTyColor;
  t: Integer;
begin
  box.Left   := FMarqueeStart.X; box.Right  := FMarqueeCur.X;
  box.Top    := FMarqueeStart.Y; box.Bottom := FMarqueeCur.Y;
  if box.Left > box.Right then begin t := box.Left; box.Left := box.Right; box.Right := t; end;
  if box.Top  > box.Bottom then begin t := box.Top; box.Top := box.Bottom; box.Bottom := t; end;
  { The band has a token of its own now ('TyListViewMarquee'), so a skin can give the rubber
    band a hue that is not the selection's -- it could not before. Silent theme => the old
    source, the selected row's fill, then the frame border: the fallback chain is what keeps
    this a themability change and not a repaint. }
  mq := ActiveController.Model.ResolveStyle('TyListViewMarquee', '', []);
  if tpBackground in mq.Present then acc := mq.Background.Color
  else
  begin
    sel := ActiveController.Model.ResolveStyle('TyListViewItem', '', [tysSelected]);
    if tpBackground in sel.Present then acc := sel.Background.Color
    else acc := AFrame.BorderColor;
  end;
  { The HUE is the theme's; only the translucency is fixed. The two alphas stay constants:
    a rubber band is a transient overlay, not a surface, and the style set has no alpha
    token -- the same deviation TTyOfficeListBox makes when it derives its header band from
    the text colour at a fixed alpha. A theme change still recolours the band. }
  P.Bitmap.FillRect(box.Left, box.Top, box.Right, box.Bottom,
    BGRA(TyRedOf(acc), TyGreenOf(acc), TyBlueOf(acc), TyLvMarqueeFillAlpha),
    dmDrawWithTransparency);
  P.Bitmap.Rectangle(box.Left, box.Top, box.Right, box.Bottom,
    BGRA(TyRedOf(acc), TyGreenOf(acc), TyBlueOf(acc), TyLvMarqueeEdgeAlpha),
    dmDrawWithTransparency);
end;

{ The on-screen index-in-group window, bounded by the viewport (never the whole group). It
  derives candidate rows arithmetically then the caller verifies each cell through
  TyListGroupItemRect — the same candidate-then-verify discipline the flat path uses, so no
  independent geometry is invented. False = the group contributes nothing on screen. }
function TTyListView.GroupVisibleItemRange(AGroup: Integer; const M: TTyListMetrics;
  out AFirst, ALast: Integer): Boolean;
var
  hh, bodyTopCy, regionH, visTop, visBottom, Tracks, PitchY,
  firstRow, lastRow, maxRow, delta, cnt: Integer;
begin
  AFirst := -1;
  ALast := -1;
  Result := False;
  if (AGroup < 0) or (AGroup >= Length(FGroupMap.Groups)) then Exit;
  if FGroupMap.Groups[AGroup].Collapsed then Exit;
  cnt := FGroupMap.Groups[AGroup].Count;
  if cnt <= 0 then Exit;

  if FGroupMap.Groups[AGroup].HasHeader then hh := GroupHeaderHeightPx else hh := 0;
  bodyTopCy := FGroupMap.Tops[AGroup] + hh;   { content Y of this group's body top }
  regionH := M.ViewportH - M.HeaderH;
  if regionH < 0 then regionH := 0;
  visTop := FOffsetY;
  visBottom := FOffsetY + regionH;            { exclusive }

  if M.ViewStyle = lvsReport then
  begin
    Tracks := 1;
    PitchY := M.RowH;
  end
  else
  begin
    Tracks := TyListTracks(M);
    PitchY := M.CellH + M.VGap;
  end;
  if PitchY <= 0 then
  begin
    { degenerate cell: fall back to the whole (bounded) group so nothing silently vanishes }
    AFirst := 0;
    ALast := cnt - 1;
    Exit(True);
  end;

  delta := visTop - bodyTopCy;
  if delta <= 0 then firstRow := 0 else firstRow := delta div PitchY;
  if visBottom - bodyTopCy <= 0 then Exit;    { body entirely below the viewport }
  lastRow := (visBottom - bodyTopCy - 1) div PitchY;
  if lastRow < 0 then Exit;
  maxRow := (cnt - 1) div Tracks;
  if lastRow > maxRow then lastRow := maxRow;
  if firstRow > maxRow then Exit;
  if firstRow > lastRow then Exit;

  AFirst := firstRow * Tracks;
  ALast := (lastRow + 1) * Tracks - 1;
  if ALast > cnt - 1 then ALast := cnt - 1;
  Result := True;
end;

{ One group's header band: the 'TyListViewGroupHeader' style, the caption with a
  ' (count)' suffix, and a collapse chevron (right = collapsed, down = expanded). The band is
  full-width and does not scroll horizontally; TyListGroupHeaderRect already folds in AScrollY. }
procedure TTyListView.RenderGroupHeader(P: TTyPainter; const M: TTyListMetrics; AGroup: Integer);
var
  band, tri, tr: TRect;
  hb, S: TTyStyleSet;
  tc: TTyColor;
  triSz: Integer;
  grp: TTyListGroup;
  cap: string;
begin
  band := TyListGroupHeaderRect(FGroupMap, AGroup, M, GroupHeaderHeightPx, FOffsetY);
  if (band.Bottom <= band.Top) or (band.Right <= band.Left) then Exit;
  S := CurrentStyle;
  { The GROUP band's own key. It used to resolve the same literal as the report's column
    header, so the two could never be styled apart -- inside one control. }
  hb := ActiveController.Model.ResolveStyle('TyListViewGroupHeader', '', []);

  if tpBackground in hb.Present then
    P.FillBackground(band, hb.Background, 0)
  else if tpBackground in S.Present then
    P.FillBackground(band, S.Background, 0);
  if tpTextColor in hb.Present then tc := hb.TextColor else tc := S.TextColor;

  grp := FGroups[AGroup];
  cap := grp.Caption + ' (' + IntToStr(FGroupMap.Groups[AGroup].Count) + ')';

  { collapse chevron, boxed at the band's left edge }
  triSz := band.Bottom - band.Top;
  tri := Rect(band.Left, band.Top, band.Left + triSz, band.Bottom);
  if grp.Collapsed then
    P.DrawGlyph(tri, tgChevronRight, tc, 1, 7)
  else
    P.DrawGlyph(tri, tgChevronDown, tc, 1, 7);

  tr := Rect(band.Left + triSz, band.Top, band.Right - ScaleI(ActiveController.Metric('--listview-text-margin', TyLvTextMargin)), band.Bottom);
  if tr.Left < tr.Right then
  begin
    if tpTextColor in hb.Present then
      P.DrawText(tr, cap, hb.FontName, ResolveFontSize(hb), hb.FontWeight,
        tc, taLeftJustify, tlCenter, True)
    else
      P.DrawText(tr, cap, S.FontName, ResolveFontSize(S), S.FontWeight,
        tc, taLeftJustify, tlCenter, True);
  end;
end;

{ Grouped item region: the visible group range, then per group its header band and its
  on-screen items. Every cell rect comes from TyListGroupItemRect (single geometry source);
  RenderItem is reused unchanged. }
procedure TTyListView.RenderGrouped(P: TTyPainter; const M: TTyListMetrics);
var
  gFirst, gLast, g, iFirst, iLast, i, pos, item: Integer;
  cell: TRect;
  states: TTyStateSet;
  rowStyle: TTyStyleSet;
begin
  if not TyListGroupVisibleRange(FGroupMap, M, FOffsetY, gFirst, gLast) then Exit;
  for g := gFirst to gLast do
  begin
    if FGroupMap.Groups[g].HasHeader then
      RenderGroupHeader(P, M, g);
    if FGroupMap.Groups[g].Collapsed then Continue;
    if not GroupVisibleItemRange(g, M, iFirst, iLast) then Continue;
    for i := iFirst to iLast do
    begin
      pos := FGroupMap.FirstVisible[g] + i;   { (group, index-in-group) -> display pos }
      item := DisplayToItem(pos);             { display pos -> item index }
      if item < 0 then Continue;
      cell := TyListGroupItemRect(FGroupMap, g, i, M, GroupHeaderHeightPx, FOffsetX, FOffsetY);
      states := StatesFor(item);
      rowStyle := ActiveController.Model.ResolveStyle('TyListViewItem', '', states);
      RenderItem(P, item, cell, rowStyle, states);
    end;
  end;
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

    if UseGroupedLayout then
      RenderGrouped(P, m)
    else
    begin
      if TyListVisibleRange(cnt, m, FOffsetX, FOffsetY, first, last) then
        for pos := first to last do
        begin
          item := DisplayToItem(pos);   { display pos -> item index }
          if item < 0 then Continue;
          cell := TyListItemRect(pos, cnt, m, FOffsetX, FOffsetY);
          states := StatesFor(item);
          rowStyle := ActiveController.Model.ResolveStyle('TyListViewItem', '', states);
          RenderItem(P, item, cell, rowStyle, states);
        end;

      if (FViewStyle = lvsReport) and FGridLines then
        RenderGridLines(P, m, S);
    end;

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
  { Rule 4: a resize moves cells. Commit + close the editor first. Rule 2: the base
    constructor calls Resize before FEditor exists, so EndEdit's own nil-guard covers that. }
  EndEdit(True);
  UpdateScrollBars;
end;

{ ---------------------------------------------------------------------------
  Mouse
  --------------------------------------------------------------------------- }

procedure TTyListView.ItemMouseSelect(AItem: Integer; Shift: TShiftState);
var
  before: TTyIntArray;
begin
  EnsureSelectedLen;
  if not FMultiSelect then
  begin
    SetSingleSelection(AItem);   { asks CanChange and fires the delta itself }
    Exit;
  end;
  if ssShift in Shift then
  begin
    if not CanChange(AItem, ctState) then Exit;
    before := SnapshotSelection;
    SelectRangeByDisplay(FAnchor, AItem);   { anchor stays; range via display order }
    FItemIndex := AItem;
    Invalidate;
    DoChange(AItem, ctState);
    { The range replaces the previous one wholesale, so the rows that fell out of it are
      reported as deselected -- which is exactly what a Shift-drag looks like to the user. }
    FireSelectionDelta(before);
  end
  else if ssCtrl in Shift then
  begin
    if not CanChange(AItem, ctState) then Exit;
    before := SnapshotSelection;
    if AItem < Length(FSelected) then
      FSelected[AItem] := not FSelected[AItem];
    FItemIndex := AItem;
    FAnchor := AItem;
    Invalidate;
    DoChange(AItem, ctState);
    { Ctrl+click on an already-selected row REMOVES it: the delta reports ASelected=False,
      which the old one-argument event could not express at all. }
    FireSelectionDelta(before);
  end
  else
    SetSingleSelection(AItem);
end;

procedure TTyListView.ApplyMarquee;
var
  box, cell: TRect;
  hits: TTyIntArray;
  before: TTyIntArray;
  m: TTyListMetrics;
  i, it, t, gFirst, gLast, g, iFirst, iLast, k, lastItem: Integer;
begin
  { A rubber-band sweep rewrites the whole selection on every mouse move, so it is a bulk
    change (-1) and the veto has to be honoured per move -- otherwise a host that refused
    the first move would silently get the rest. }
  if not CanChange(-1, ctState) then Exit;
  before := SnapshotSelection;
  box.Left := FMarqueeStart.X; box.Right := FMarqueeCur.X;
  box.Top := FMarqueeStart.Y; box.Bottom := FMarqueeCur.Y;
  if box.Left > box.Right then begin t := box.Left; box.Left := box.Right; box.Right := t; end;
  if box.Top > box.Bottom then begin t := box.Top; box.Top := box.Bottom; box.Bottom := t; end;
  m := CurrentMetrics;

  if UseGroupedLayout then
  begin
    { Grouped marquee walks only the ON-SCREEN items (visible group range x each group's
      visible item window), testing each cell (from the single geometry source) against the
      box. Selection stays keyed by item index; the last hit in display order takes focus,
      matching the flat path. }
    EnsureSelectedLen;
    ClearAllBits;
    lastItem := -1;
    if TyListGroupVisibleRange(FGroupMap, m, FOffsetY, gFirst, gLast) then
      for g := gFirst to gLast do
      begin
        if FGroupMap.Groups[g].Collapsed then Continue;
        if not GroupVisibleItemRange(g, m, iFirst, iLast) then Continue;
        for k := iFirst to iLast do
        begin
          cell := TyListGroupItemRect(FGroupMap, g, k, m, GroupHeaderHeightPx, FOffsetX, FOffsetY);
          if (cell.Left <= box.Right) and (cell.Right >= box.Left) and
             (cell.Top <= box.Bottom) and (cell.Bottom >= box.Top) then   { inclusive touch }
          begin
            it := DisplayToItem(FGroupMap.FirstVisible[g] + k);   { (g,k)->display->item }
            if (it >= 0) and (it < Length(FSelected)) then
            begin
              FSelected[it] := True;
              lastItem := it;
            end;
          end;
        end;
      end;
    if lastItem >= 0 then
      FItemIndex := lastItem;
    DoChange(-1, ctState);
    FireSelectionDelta(before);
    Exit;
  end;

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
  DoChange(-1, ctState);
  FireSelectionDelta(before);
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
  cnt, pos, item, logX, logScroll, dividerCol, clickCol, g, idx: Integer;
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

  { Grouped item area: same selection / check / marquee behaviour, but the hit and the header
    toggle go through the group map. }
  if UseGroupedLayout then
  begin
    if TyListGroupHitTest(FGroupMap, Point(X, Y), m, GroupHeaderHeightPx,
         FOffsetX, FOffsetY, g, idx) then
    begin
      if idx < 0 then
      begin
        { Group header band: toggle collapse (rebuilds order + map, fires OnGroupCollapsed). }
        ToggleGroupCollapsed(g);
        Exit;
      end;
      item := DisplayToItem(TyListGroupDisplayPos(FGroupMap, g, idx));  { (g,idx)->display->item }
      if item >= 0 then
      begin
        if FPressHit = lhpCheck then
        begin
          SetChecked(item, not GetChecked(item));   { item index; fires OnItemChecked + Invalidate }
          Exit;
        end;
        ItemMouseSelect(item, Shift);
      end;
    end
    else
    begin
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
    Exit;
  end;

  { Item area. }
  pos := TyListItemAt(Point(X, Y), cnt, m, FOffsetX, FOffsetY);   { -> display pos }
  if pos >= 0 then
  begin
    item := DisplayToItem(pos);   { display pos -> item index }
    if item >= 0 then
    begin
      if FPressHit = lhpCheck then
      begin
        { A click on the box toggles the check and returns WITHOUT touching the selection or
          the focus — straight Exit, never into the selection logic. }
        SetChecked(item, not GetChecked(item));   { item index; fires OnItemChecked + Invalidate }
        Exit;
      end;
      ItemMouseSelect(item, Shift);
    end;
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
  { Measure with the SAME styles the paint uses, or the fitted width misses the drawn text. }
  rowS := ActiveController.Model.ResolveStyle('TyListViewItem', '', []);
  hdrS := ActiveController.Model.ResolveStyle('TyListViewHeaderSection', '', []);

  iconDev := 0;
  if (AColumn = FHeader.MainColumn) and (FSmallImages <> nil) then
    iconDev := ScaleI(ActiveController.Metric('--listview-small-icon-size', TyLvSmallIcon)) + ScaleI(2);

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
  col.Width := UnscaleI(bestDev) + 2 * ActiveController.Metric('--listview-text-margin', TyLvTextMargin);
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
  if FItemIndex >= 0 then DoItemActivate(FItemIndex);
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
  before: TTyIntArray;   { selection snapshot for the OnSelectItem delta }
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  cnt := GetItemCount;
  if cnt = 0 then Exit;
  SyncArrays;
  m := CurrentMetrics;

  if (Key = VK_F2) and (Shift = []) and (FItemIndex >= 0) then
  begin
    { Rename on F2 only — no slow double-click, which would fight OnItemActivate's double-click.
      BeginEdit itself guards ReadOnly and the OnEditing veto. }
    BeginEdit(FItemIndex);   { item index }
    Key := 0;
    Exit;
  end;
  if (Key = VK_A) and (ssCtrl in Shift) and FMultiSelect then
  begin
    SelectAll;
    Key := 0;
    Exit;
  end;
  if Key = VK_RETURN then
  begin
    if FItemIndex >= 0 then DoItemActivate(FItemIndex);
    Key := 0;
    Exit;
  end;
  if (Key = VK_SPACE) and (FItemIndex >= 0) then
  begin
    { Checkboxes on: Space toggles the focused row's CHECK; Ctrl+Space still toggles the
      SELECTION (multi-select). Checkboxes off: Space keeps the original selection toggle. }
    if FCheckboxes and not (ssCtrl in Shift) then
    begin
      SetChecked(FItemIndex, not GetChecked(FItemIndex));   { item index }
      Key := 0;
      Exit;
    end;
    if FMultiSelect then
    begin
      EnsureSelectedLen;
      if CanChange(FItemIndex, ctState) then
      begin
        before := SnapshotSelection;
        if FItemIndex < Length(FSelected) then
          FSelected[FItemIndex] := not FSelected[FItemIndex];
        FAnchor := FItemIndex;
        Invalidate;
        DoChange(FItemIndex, ctState);
        FireSelectionDelta(before);
      end;
      { Consumed either way: a vetoed Space must not fall through to type-ahead and start
        searching for a row whose caption begins with a blank. }
      Key := 0;
      Exit;
    end;
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
  if UseGroupedLayout then
    newPos := TyListGroupNavigate(FGroupMap, curPos, navKey, m)   { grouped 2-D nav }
  else
    newPos := TyListNavigate(curPos, cnt, navKey, m);
  Key := 0;
  if newPos < 0 then Exit;
  newItem := DisplayToItem(newPos);       { display pos -> item index }
  if newItem < 0 then Exit;

  if FMultiSelect and (ssShift in Shift) then
  begin
    if not CanChange(newItem, ctState) then Exit;   { vetoed: focus and view stay put }
    before := SnapshotSelection;
    SelectRangeByDisplay(FAnchor, newItem);
    FItemIndex := newItem;
    Invalidate;
    DoChange(newItem, ctState);
    FireSelectionDelta(before);
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
  EndEdit(True);   { rule 4: wheel scroll moves the edited cell — commit + close first }
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
  RegisterClass(TTyListGroup);
  RegisterClass(TTyListGroups);
  RegisterClass(TTyListView);

end.
