unit tyControls.ListGroupPanel;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ImgList,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ImageCollection,
  tyControls.ImageDraw;

const
  // Logical (96ppi) defaults. Header band matches the ExPanel caption band; item rows
  // match the ListBox row height so the two families read as one visual system.
  TyListGroupDefaultHeaderHeight = 26;
  TyListGroupDefaultItemHeight   = 24;
  // Chevron / icon / selected-pill metrics (logical px). Each is the fallback for the theme
  // metric token named below; a skin retunes the whole sider through them.
  TyListGroupDefaultChevronSize  = 14;   // >= ~12, or TyDrawGlyph's 4px/side inset smudges it
  TyListGroupDefaultIconSize     = 16;   // per-row icon slot
  TyListGroupDefaultIconGap      = 6;    // gap between the icon and the caption
  TyListGroupDefaultItemInset    = 6;    // the selected pill's inset from the row's edges
  TyListGroupDefaultItemIndent   = 16;   // child content's hierarchy step past the group header

  // Theme metric token names. Named constants (not string literals) so a typo cannot strand a
  // call site on the default. Heights: the token WINS when a theme sets it, else the published
  // HeaderHeight/ItemHeight property is the fallback — so a skin owns the sider's rhythm
  // ('40px airy' is a skin decision) while a single instance can still override.
  // Sider collapse (the AntD trigger): the icon-rail width when Collapsed, and the bottom
  // trigger band's height when ShowCollapseTrigger is on.
  TyListGroupDefaultCollapsedWidth = 48;
  TyListGroupDefaultTriggerHeight  = 28;
  TyListGroupHeaderHeightVar = '--listgroup-header-height';
  TyListGroupItemHeightVar   = '--listgroup-item-height';
  TyListGroupChevronSizeVar  = '--listgroup-chevron-size';
  TyListGroupCollapsedWidthVar = '--listgroup-collapsed-width';
  TyListGroupTriggerHeightVar  = '--listgroup-trigger-height';
  TyListGroupIconSizeVar     = '--listgroup-icon-size';
  TyListGroupIconGapVar      = '--listgroup-icon-gap';
  TyListGroupItemInsetVar    = '--listgroup-item-inset';
  TyListGroupItemIndentVar   = '--listgroup-item-indent';

type
  { The kind of thing a layout entry describes: a group header band, or one item row. }
  TTyListGroupPartKind = (lgpHeader, lgpItem);

  { One laid-out rectangle in CONTENT space (y measured from 0 at the top of the first
    header, growing downward; a scroll offset is applied by the control at paint/hit time).
    For a header, GroupIndex is the group and ItemIndex is -1; for an item, both are set. }
  TTyListGroupPart = record
    Kind: TTyListGroupPartKind;
    GroupIndex: Integer;
    ItemIndex: Integer;   // -1 for a header
    Rect: TRect;
  end;
  TTyListGroupParts = array of TTyListGroupPart;

  { A group's shape as the pure layout needs it: whether it is expanded and how many
    items it holds. The caller (the control / a test) fills one per group. }
  TTyListGroupShape = record
    Expanded: Boolean;
    ItemCount: Integer;
  end;
  TTyListGroupShapes = array of TTyListGroupShape;

  { The result of a hit test: what kind of part (if any) was hit and its indices.
    Hit=False when the point missed every part (e.g. below the last row). }
  TTyListGroupHit = record
    Hit: Boolean;
    Kind: TTyListGroupPartKind;
    GroupIndex: Integer;
    ItemIndex: Integer;   // -1 for a header hit
  end;

{ ---- PURE, headless-tested layout/hit-test (all in DEVICE pixels) ---- }

{ Build the ordered list of parts for AGroups stacked top-to-bottom in a AClientW-wide
  column: each group contributes ONE header (AHeaderH tall), then — only if that group is
  Expanded — AItemHeight-tall item rows, one per item. All rects are full-width [0..AClientW].
  Content y starts at 0 (no scroll applied here). An empty expanded group contributes only
  its header (no item rects). Returns the parts in visual (top-to-bottom) order. }
function TyListGroupLayout(const AGroups: TTyListGroupShapes;
  AHeaderH, AItemHeight, AClientW: Integer): TTyListGroupParts;

{ Total content height of a layout = bottom of the last part (0 for no groups). }
function TyListGroupContentHeight(const AParts: TTyListGroupParts): Integer;

{ Hit-test APt (already in CONTENT space — the caller adds the scroll offset back) against
  the parts. Returns the FIRST part whose rect contains APt. An item hit wins naturally
  because item rects never overlap their header. Miss -> Hit=False. }
function TyListGroupHitTest(const AParts: TTyListGroupParts; const APt: TPoint): TTyListGroupHit;

type
  TTyListGroupPanel = class;

  { The sider's model: NESTED collections, matching how the sider is authored -- add
    Groups, then add each group's Items under it (real-machine feedback: the flat
    kind-per-row list read as "everything is an item"). Published and streamed, so the
    designer builds the sider in the Object Inspector: the Groups editor lists the
    groups; selecting one shows its properties, whose Items '...' opens that group's
    own items editor. The code-building API (AddGroup / AddItem / ...) delegates here. }
  TTyListGroup = class;
  TTyListGroups = class;

  TTyListGroupItem = class(TCollectionItem)
  private
    FCaption: string;
    FImageIndex: Integer;
    procedure SetCaption(const AValue: string);
    procedure SetImageIndex(AValue: Integer);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
  published
    property Caption: string read FCaption write SetCaption;
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
  end;

  TTyListGroupItems = class(TOwnedCollection)
  private
    FGroup: TTyListGroup;
    function GetItem(AIndex: Integer): TTyListGroupItem;
    procedure SetItem(AIndex: Integer; AValue: TTyListGroupItem);
  protected
    { Bubble every item change up through the owning group, so the panel re-clamps and
      repaints no matter which level the edit came in at. Update ONLY, never Notify:
      FPC fires Changed after both insert and remove so nothing is missed, and Update
      is gated by FUpdateCount -- which TCollection.Destroy raises, keeping teardown
      from walking half-destroyed groups (Notify has no such gate). }
    procedure Update(AItem: TCollectionItem); override;
  public
    constructor Create(AGroup: TTyListGroup);
    function Add: TTyListGroupItem;
    property Items[AIndex: Integer]: TTyListGroupItem read GetItem write SetItem; default;
    { The group these rows belong to -- how an item's editor walks back up the model. }
    property Group: TTyListGroup read FGroup;
  end;

  TTyListGroup = class(TCollectionItem)
  private
    FCaption: string;
    FImageIndex: Integer;
    FExpanded: Boolean;
    FItems: TTyListGroupItems;
    procedure SetCaption(const AValue: string);
    procedure SetImageIndex(AValue: Integer);
    procedure SetExpanded(AValue: Boolean);
    procedure SetItems(AValue: TTyListGroupItems);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(ASource: TPersistent); override;
  published
    property Caption: string read FCaption write SetCaption;
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
    { Whether the group starts open. The designer default is open (an authored sider
      should show its rows); the AddGroup facade keeps its historical default of closed. }
    property Expanded: Boolean read FExpanded write SetExpanded default True;
    { The group's own rows, edited in their own collection editor. }
    property Items: TTyListGroupItems read FItems write SetItems;
  end;

  TTyListGroups = class(TOwnedCollection)
  private
    FPanel: TTyListGroupPanel;
    function GetGroup(AIndex: Integer): TTyListGroup;
    procedure SetGroup(AIndex: Integer; AValue: TTyListGroup);
  protected
    { The funnel into the panel: ANY route into the model -- the Object Inspector, the
      .lfm reader, the facade, a direct property write -- re-clamps selection and scroll.
      Update ONLY (see TTyListGroupItems.Update). }
    procedure Update(AItem: TCollectionItem); override;
  public
    constructor Create(APanel: TTyListGroupPanel);
    function Add: TTyListGroup;
    property Groups[AIndex: Integer]: TTyListGroup read GetGroup write SetGroup; default;
  end;

  TTyListGroupToggleEvent = procedure(Sender: TObject; AGroupIndex: Integer) of object;
  TTyListGroupItemEvent = procedure(Sender: TObject; AGroupIndex, AItemIndex: Integer) of object;

  { TTyListGroupPanel — an Outlook-style grouped, expandable (accordion) list.

    A vertical stack of named GROUPS. Each group is a header band (caption + a chevron,
    reusing the ExPanel chevron geometry) that toggles the group open/closed. When open a
    group shows its ITEMS, one caption per row. Clicking a header toggles Expanded (and fires
    OnGroupToggle); clicking an item selects it (SelectedGroup/SelectedItem) and fires
    OnItemClick.

    SCROLLING: when the stacked content is taller than the control it is CLIPPED to the
    client and the mouse wheel pans it (FScrollOffset). This keeps the whole layout in the
    pure geometry functions (no embedded child scrollbar). Content shorter than the client
    pins the offset to 0.

    THEMING (its OWN typeKeys, so a theme can restyle the sider without touching the tree/list
    column headers — the old design borrowed TyTreeHeaderSection/TyListItem, which are shared
    with TreeView/ListView, and made this look literally unreachable):
      * the frame (background + border) is 'TyPanel' (GetStyleTypeKey);
      * each group header is 'TyListGroupHeader' — :hover, and :selected = the group is OPEN.
        It fills ONLY if the theme sets a background (a modern sider leaves it unfilled), draws
        a right-aligned chevron in its TextColor, and an optional group icon;
      * each item row is 'TyListGroupItem' (:hover / :active=selected). :active is drawn as a
        SOFT INSET ROUNDED pill (the control insets + rounds; the colour/radius are the style's),
        not a full-bleed bar. Rows carry an optional icon from Images.
    Sizes are theme metrics (--listgroup-header-height / -item-height / -chevron-size /
    -icon-size / -icon-gap / -item-inset), each falling back to a named constant / the published
    HeaderHeight/ItemHeight. All colours and sizes are theme-driven. }

  TTyListGroupPanel = class(TTyCustomControl)
  private
    FGroups: TTyListGroups;
    FImages: TCustomImageList;      // per-row icon source (nil = no icons); any list works
    FHeaderHeight: Integer;
    FItemHeight: Integer;
    FSelGroup: Integer;     // -1 = none
    FSelItem: Integer;      // -1 = none
    FHoverKind: TTyListGroupPartKind;
    FHoverGroup: Integer;   // -1 = none
    FHoverItem: Integer;    // -1 = none
    FScrollOffset: Integer; // device px content is shifted UP by (>=0)
    FCollapsed: Boolean;
    FShowCollapseTrigger: Boolean;
    FCollapsedWidth: Integer;      // logical px fallback for the width token
    FExpandedWidth: Integer;       // captured by a runtime collapse; 0 = never collapsed
    FOnGroupToggle: TTyListGroupToggleEvent;
    FOnItemClick: TTyListGroupItemEvent;
    FOnCollapsedChange: TNotifyEvent;
    procedure SetCollapsed(AValue: Boolean);
    procedure SetShowCollapseTrigger(AValue: Boolean);
    procedure SetCollapsedWidth(AValue: Integer);
    procedure SetGroups(AValue: TTyListGroups);
    { Any change to the group model: re-clamp selection, hover and scroll, repaint. }
    procedure GroupsChanged;
    { The rail width / the trigger band's height in device px (0 when the trigger is off). }
    function EffCollapsedWPx(APPI: Integer): Integer;
    function EffTriggerHPx(APPI: Integer): Integer;
    procedure SetHeaderHeight(AValue: Integer);
    procedure SetItemHeight(AValue: Integer);
    procedure SetImages(AValue: TCustomImageList);
    function ScaledHeaderHeight: Integer;
    function ScaledItemHeight: Integer;
    { Effective band heights in DEVICE px at APPI: the theme metric token when set, else the
      published property. The token WINS so airiness is a skin decision (see the const notes). }
    function EffHeaderHPx(APPI: Integer): Integer;
    function EffItemHPx(APPI: Integer): Integer;
    { Draw the AImages icon AIndex, sized to fit, left-aligned at AX, vertically centred in
      [ATop, ATop+ARowH); returns the x just past it (AX unchanged if nothing drawn). }
    function DrawRowIcon(P: TTyPainter; AX, ATop, ARowH, AIndex: Integer): Integer;
    { Build the pure shapes array from the live group model. }
    function BuildShapes: TTyListGroupShapes;
    { The device-space layout (content coords, no scroll applied), for the current client width. }
    function BuildLayout: TTyListGroupParts;
    function MaxScrollOffset: Integer;
    procedure ClampScroll;
    procedure SetSelGroup(AValue: Integer);
    procedure SetSelItem(AValue: Integer);
    procedure ClearHover;
    function GroupExpanded(AGroup: Integer): Boolean;
    procedure SetGroupExpanded(AGroup: Integer; AValue: Boolean);
    function GetGroupCaption(AGroup: Integer): string;
    procedure SetGroupCaption(AGroup: Integer; const AValue: string);
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Model mutation. }
    function AddGroup(const ACaption: string; AImageIndex: Integer = -1): Integer;
    function AddItem(AGroupIndex: Integer; const ACaption: string; AImageIndex: Integer = -1): Integer;
    procedure Clear;
    function GroupCount: Integer;
    function ItemCount(AGroupIndex: Integer): Integer;
    function ItemCaption(AGroupIndex, AItemIndex: Integer): string;
    function ItemImageIndex(AGroupIndex, AItemIndex: Integer): Integer;

    { Toggle a group's expand state (fires OnGroupToggle on a real change). }
    procedure ToggleGroup(AGroupIndex: Integer);
    { Select an item (fires OnItemClick on a real change). Pass (-1,-1) to clear. }
    procedure SelectItem(AGroupIndex, AItemIndex: Integer);

    { Per-group accessors. }
    property Expanded[AGroup: Integer]: Boolean read GroupExpanded write SetGroupExpanded;
    property GroupCaption[AGroup: Integer]: string read GetGroupCaption write SetGroupCaption;

    { The currently-selected item (both -1 when nothing is selected). }
    property SelectedGroup: Integer read FSelGroup write SetSelGroup;
    property SelectedItem: Integer read FSelItem write SetSelItem;

    { Current vertical scroll offset (device px, 0..MaxScrollOffset); wheel-driven. }
    property ScrollOffset: Integer read FScrollOffset;
  published
    { Sider collapse (QQ-group request). Collapsed narrows the panel to an icon rail
      (captions, group chevrons and hierarchy indent are dropped; icons stay clickable)
      and expanding restores the width the runtime collapse captured. ShowCollapseTrigger
      adds a full-width band along the bottom whose chevron toggles Collapsed — off by
      default, so existing siders keep their look. CollapsedWidth is the logical-px
      fallback for the --listgroup-collapsed-width token (the token wins, as with the
      band heights). A panel LOADED with Collapsed=True keeps its streamed width; the
      first runtime expand then leaves the width to the host until a collapse captures one. }
    property Collapsed: Boolean read FCollapsed write SetCollapsed default False;
    property ShowCollapseTrigger: Boolean read FShowCollapseTrigger
      write SetShowCollapseTrigger default False;
    property CollapsedWidth: Integer read FCollapsedWidth write SetCollapsedWidth
      default TyListGroupDefaultCollapsedWidth;
    property OnCollapsedChange: TNotifyEvent read FOnCollapsedChange write FOnCollapsedChange;
    { The sider's model, editable in the Object Inspector and streamed to the .lfm:
      groups first, each group's Items nested under it. }
    property Groups: TTyListGroups read FGroups write SetGroups;
    property HeaderHeight: Integer read FHeaderHeight write SetHeaderHeight
      default TyListGroupDefaultHeaderHeight;
    property ItemHeight: Integer read FItemHeight write SetItemHeight
      default TyListGroupDefaultItemHeight;
    { Icon source for the group headers and item rows (addressed by ImageIndex). nil = text
      only. Same facility TTyComboBoxEx uses. }
    property Images: TCustomImageList read FImages write SetImages;
    property OnGroupToggle: TTyListGroupToggleEvent read FOnGroupToggle write FOnGroupToggle;
    property OnItemClick: TTyListGroupItemEvent read FOnItemClick write FOnItemClick;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
  end;

implementation

{ ---- the group model ---- }

constructor TTyListGroupItem.Create(ACollection: TCollection);
begin
  { Fields BEFORE inherited: joining the collection fires Changed->Update, which walks
    the model -- everything a walker reads must already hold its default. }
  FImageIndex := -1;
  inherited Create(ACollection);
end;

procedure TTyListGroupItem.Assign(ASource: TPersistent);
begin
  if ASource is TTyListGroupItem then
  begin
    FCaption := TTyListGroupItem(ASource).FCaption;
    FImageIndex := TTyListGroupItem(ASource).FImageIndex;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

function TTyListGroupItem.GetDisplayName: string;
begin
  if FCaption <> '' then Result := FCaption else Result := inherited GetDisplayName;
end;

procedure TTyListGroupItem.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

procedure TTyListGroupItem.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  Changed(False);
end;

constructor TTyListGroupItems.Create(AGroup: TTyListGroup);
begin
  inherited Create(AGroup, TTyListGroupItem);
  FGroup := AGroup;
end;

function TTyListGroupItems.Add: TTyListGroupItem;
begin
  Result := TTyListGroupItem(inherited Add);
end;

function TTyListGroupItems.GetItem(AIndex: Integer): TTyListGroupItem;
begin
  Result := TTyListGroupItem(inherited Items[AIndex]);
end;

procedure TTyListGroupItems.SetItem(AIndex: Integer; AValue: TTyListGroupItem);
begin
  TTyListGroupItem(inherited Items[AIndex]).Assign(AValue);
end;

procedure TTyListGroupItems.Update(AItem: TCollectionItem);
begin
  inherited Update(AItem);
  if FGroup <> nil then FGroup.Changed(False);
end;

constructor TTyListGroup.Create(ACollection: TCollection);
begin
  { Fields BEFORE inherited: joining the collection fires Changed->Update, and the
    panel's layout walk reads Items/Expanded off every group -- including this one. }
  FImageIndex := -1;
  FExpanded := True;
  FItems := TTyListGroupItems.Create(Self);
  inherited Create(ACollection);
end;

destructor TTyListGroup.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TTyListGroup.Assign(ASource: TPersistent);
begin
  if ASource is TTyListGroup then
  begin
    FCaption := TTyListGroup(ASource).FCaption;
    FImageIndex := TTyListGroup(ASource).FImageIndex;
    FExpanded := TTyListGroup(ASource).FExpanded;
    FItems.Assign(TTyListGroup(ASource).FItems);
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

function TTyListGroup.GetDisplayName: string;
begin
  if FCaption <> '' then Result := FCaption else Result := inherited GetDisplayName;
end;

procedure TTyListGroup.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

procedure TTyListGroup.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  Changed(False);
end;

procedure TTyListGroup.SetExpanded(AValue: Boolean);
begin
  if FExpanded = AValue then Exit;
  FExpanded := AValue;
  Changed(False);
end;

procedure TTyListGroup.SetItems(AValue: TTyListGroupItems);
begin
  FItems.Assign(AValue);
end;

constructor TTyListGroups.Create(APanel: TTyListGroupPanel);
begin
  inherited Create(APanel, TTyListGroup);
  FPanel := APanel;
end;

function TTyListGroups.Add: TTyListGroup;
begin
  Result := TTyListGroup(inherited Add);
end;

function TTyListGroups.GetGroup(AIndex: Integer): TTyListGroup;
begin
  Result := TTyListGroup(inherited Items[AIndex]);
end;

procedure TTyListGroups.SetGroup(AIndex: Integer; AValue: TTyListGroup);
begin
  TTyListGroup(inherited Items[AIndex]).Assign(AValue);
end;

procedure TTyListGroups.Update(AItem: TCollectionItem);
begin
  inherited Update(AItem);
  if FPanel <> nil then FPanel.GroupsChanged;
end;

{ ---- pure geometry ---- }

function TyListGroupLayout(const AGroups: TTyListGroupShapes;
  AHeaderH, AItemHeight, AClientW: Integer): TTyListGroupParts;
var
  g, it, y, n, hh, ih: Integer;
begin
  Result := nil;
  hh := AHeaderH;  if hh < 1 then hh := 1;
  ih := AItemHeight;  if ih < 1 then ih := 1;
  // Count parts first so we can size the array once (header per group + items of expanded groups).
  n := 0;
  for g := 0 to High(AGroups) do
  begin
    Inc(n);   // the header
    if AGroups[g].Expanded and (AGroups[g].ItemCount > 0) then
      Inc(n, AGroups[g].ItemCount);
  end;
  SetLength(Result, n);
  y := 0;
  n := 0;
  for g := 0 to High(AGroups) do
  begin
    Result[n].Kind := lgpHeader;
    Result[n].GroupIndex := g;
    Result[n].ItemIndex := -1;
    Result[n].Rect := Rect(0, y, AClientW, y + hh);
    Inc(y, hh);
    Inc(n);
    if AGroups[g].Expanded then
      for it := 0 to AGroups[g].ItemCount - 1 do
      begin
        Result[n].Kind := lgpItem;
        Result[n].GroupIndex := g;
        Result[n].ItemIndex := it;
        Result[n].Rect := Rect(0, y, AClientW, y + ih);
        Inc(y, ih);
        Inc(n);
      end;
  end;
end;

function TyListGroupContentHeight(const AParts: TTyListGroupParts): Integer;
begin
  if Length(AParts) = 0 then
    Result := 0
  else
    Result := AParts[High(AParts)].Rect.Bottom;
end;

function TyListGroupHitTest(const AParts: TTyListGroupParts; const APt: TPoint): TTyListGroupHit;
var
  i: Integer;
begin
  Result := Default(TTyListGroupHit);
  Result.Hit := False;
  Result.GroupIndex := -1;
  Result.ItemIndex := -1;
  for i := 0 to High(AParts) do
    if PtInRect(AParts[i].Rect, APt) then
    begin
      Result.Hit := True;
      Result.Kind := AParts[i].Kind;
      Result.GroupIndex := AParts[i].GroupIndex;
      Result.ItemIndex := AParts[i].ItemIndex;
      Exit;
    end;
end;

{ ---- TTyListGroupPanel ---- }

constructor TTyListGroupPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHeaderHeight := TyListGroupDefaultHeaderHeight;
  FItemHeight := TyListGroupDefaultItemHeight;
  FSelGroup := -1;
  FSelItem := -1;
  FGroups := TTyListGroups.Create(Self);
  FHoverGroup := -1;
  FHoverItem := -1;
  FScrollOffset := 0;
  FCollapsedWidth := TyListGroupDefaultCollapsedWidth;
  TabStop := True;
  Width := 200;
  Height := 260;
end;

destructor TTyListGroupPanel.Destroy;
begin
  FGroups.Free;
  inherited Destroy;
end;

procedure TTyListGroupPanel.SetGroups(AValue: TTyListGroups);
begin
  FGroups.Assign(AValue);
end;

procedure TTyListGroupPanel.GroupsChanged;
begin
  if (FSelGroup >= GroupCount)
    or ((FSelGroup >= 0) and (FSelItem >= ItemCount(FSelGroup))) then
  begin
    FSelGroup := -1;
    FSelItem := -1;
  end;
  ClearHover;
  ClampScroll;
  Invalidate;
end;

function TTyListGroupPanel.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': it already owns its header/item keys; the box it sits in deserves the same reachability.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyListGroupPanel';
end;

{ ONE source of truth for the band heights. Hit-testing / scrolling (via BuildLayout) and the
  paint (RenderTo) MUST agree, or the mouse lands on a different row than the one drawn — and the
  error accumulates one row at a time downward. Both now read the theme metric (EffHeaderHPx /
  EffItemHPx); these just evaluate it at the control's own PPI, the PPI mouse coords are in.
  (The earlier bug: paint used the token, these still used FHeaderHeight/FItemHeight, so under a
  skin that sets --listgroup-item-height the two diverged.) }
function TTyListGroupPanel.ScaledHeaderHeight: Integer;
begin
  Result := EffHeaderHPx(Font.PixelsPerInch);
end;

function TTyListGroupPanel.ScaledItemHeight: Integer;
begin
  Result := EffItemHPx(Font.PixelsPerInch);
end;

function TTyListGroupPanel.BuildShapes: TTyListGroupShapes;
var
  g: Integer;
begin
  SetLength(Result, FGroups.Count);
  for g := 0 to FGroups.Count - 1 do
  begin
    Result[g].Expanded := FGroups[g].Expanded;
    Result[g].ItemCount := FGroups[g].Items.Count;
  end;
end;

function TTyListGroupPanel.BuildLayout: TTyListGroupParts;
begin
  Result := TyListGroupLayout(BuildShapes, ScaledHeaderHeight, ScaledItemHeight, Width);
end;

function TTyListGroupPanel.MaxScrollOffset: Integer;
var
  contentH, bw: Integer;
begin
  contentH := TyListGroupContentHeight(BuildLayout);
  // Content is painted inside the frame INTERIOR (inset by the border on top and bottom), so the
  // scrollable range is against the interior height, not the full Height — else the last row's
  // bottom stays hidden behind the border and can never be scrolled fully into view. The
  // collapse-trigger band comes off it too: rows never paint under the band, so the band's
  // height must be scrollable-past for the same reason.
  bw := MulDiv(CurrentStyle.BorderWidth, Font.PixelsPerInch, 96);
  Result := contentH - (Height - 2 * bw - EffTriggerHPx(Font.PixelsPerInch));
  if Result < 0 then Result := 0;
end;

procedure TTyListGroupPanel.ClampScroll;
var
  m: Integer;
begin
  m := MaxScrollOffset;
  if FScrollOffset > m then FScrollOffset := m;
  if FScrollOffset < 0 then FScrollOffset := 0;
end;

function TTyListGroupPanel.EffCollapsedWPx(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(TyListGroupCollapsedWidthVar, FCollapsedWidth),
    APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyListGroupPanel.EffTriggerHPx(APPI: Integer): Integer;
begin
  if not FShowCollapseTrigger then Exit(0);
  Result := MulDiv(ActiveController.Metric(TyListGroupTriggerHeightVar,
    TyListGroupDefaultTriggerHeight), APPI, 96);
  if Result < 0 then Result := 0;
end;

procedure TTyListGroupPanel.SetCollapsed(AValue: Boolean);
begin
  if FCollapsed = AValue then Exit;
  FCollapsed := AValue;
  { While streaming, only record the state: Width streams on its own (the .lfm holds the
    designed width), and juggling it mid-load would capture half-loaded geometry. }
  if not (csLoading in ComponentState) then
  begin
    if FCollapsed then
    begin
      FExpandedWidth := Width;
      Width := EffCollapsedWPx(Font.PixelsPerInch);
    end
    else if FExpandedWidth > 0 then
      Width := FExpandedWidth;
    ClearHover;
    ClampScroll;
    Invalidate;
    if Assigned(FOnCollapsedChange) then FOnCollapsedChange(Self);
  end;
end;

procedure TTyListGroupPanel.SetShowCollapseTrigger(AValue: Boolean);
begin
  if FShowCollapseTrigger = AValue then Exit;
  FShowCollapseTrigger := AValue;
  ClampScroll;    // the band changes the scroll viewport
  Invalidate;
end;

procedure TTyListGroupPanel.SetCollapsedWidth(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FCollapsedWidth = AValue then Exit;
  FCollapsedWidth := AValue;
  if FCollapsed and not (csLoading in ComponentState) then
    Width := EffCollapsedWPx(Font.PixelsPerInch);
end;

procedure TTyListGroupPanel.SetHeaderHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FHeaderHeight = AValue then Exit;
  FHeaderHeight := AValue;
  ClampScroll;
  Invalidate;
end;

procedure TTyListGroupPanel.SetItemHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FItemHeight = AValue then Exit;
  FItemHeight := AValue;
  ClampScroll;
  Invalidate;
end;

function TTyListGroupPanel.AddGroup(const ACaption: string; AImageIndex: Integer): Integer;
var
  g: TTyListGroup;
begin
  FGroups.BeginUpdate;
  try
    g := FGroups.Add;
    g.FCaption := ACaption;
    g.FImageIndex := AImageIndex;
    g.FExpanded := False;            // the facade's historical default: closed
  finally
    FGroups.EndUpdate;
  end;
  Result := g.Index;
end;

procedure TTyListGroupPanel.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyListGroupPanel.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then FImages := nil;
end;

function TTyListGroupPanel.EffHeaderHPx(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(TyListGroupHeaderHeightVar, FHeaderHeight), APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyListGroupPanel.EffItemHPx(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(TyListGroupItemHeightVar, FItemHeight), APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyListGroupPanel.DrawRowIcon(P: TTyPainter; AX, ATop, ARowH, AIndex: Integer): Integer;
var
  sz: Integer;
begin
  Result := AX;
  if (FImages = nil) or (AIndex < 0) or (AIndex >= TyImageCount(FImages)) then Exit;
  sz := P.Scale(ActiveController.Metric(TyListGroupIconSizeVar, TyListGroupDefaultIconSize));
  if sz < 1 then sz := 1;
  { In-layer, both branches: our list renders the vector at sz, a foreign list is materialised.
    APPI: this control composites at device px, so P's PPI is the device PPI. }
  TyBlitImage(P.Bitmap, FImages, AIndex, AX, ATop + (ARowH - sz) div 2, sz, P.Scale(96), False);
  Result := AX + sz + P.Scale(ActiveController.Metric(TyListGroupIconGapVar, TyListGroupDefaultIconGap));
end;

function TTyListGroupPanel.AddItem(AGroupIndex: Integer; const ACaption: string;
  AImageIndex: Integer): Integer;
var
  it: TTyListGroupItem;
begin
  if (AGroupIndex < 0) or (AGroupIndex >= FGroups.Count) then Exit(-1);
  FGroups.BeginUpdate;
  try
    it := FGroups[AGroupIndex].Items.Add;
    it.FCaption := ACaption;
    it.FImageIndex := AImageIndex;
  finally
    FGroups.EndUpdate;
  end;
  Result := it.Index;
end;

procedure TTyListGroupPanel.Clear;
begin
  FGroups.Clear;
  FSelGroup := -1;
  FSelItem := -1;
  FHoverGroup := -1;
  FHoverItem := -1;
  FScrollOffset := 0;
  Invalidate;
end;

function TTyListGroupPanel.GroupCount: Integer;
begin
  Result := FGroups.Count;
end;

function TTyListGroupPanel.ItemCount(AGroupIndex: Integer): Integer;
begin
  if (AGroupIndex < 0) or (AGroupIndex >= FGroups.Count) then Exit(0);
  Result := FGroups[AGroupIndex].Items.Count;
end;

function TTyListGroupPanel.ItemCaption(AGroupIndex, AItemIndex: Integer): string;
begin
  Result := '';
  if (AGroupIndex < 0) or (AGroupIndex >= FGroups.Count) then Exit;
  if (AItemIndex < 0) or (AItemIndex >= FGroups[AGroupIndex].Items.Count) then Exit;
  Result := FGroups[AGroupIndex].Items[AItemIndex].Caption;
end;

function TTyListGroupPanel.ItemImageIndex(AGroupIndex, AItemIndex: Integer): Integer;
begin
  Result := -1;
  if (AGroupIndex < 0) or (AGroupIndex >= FGroups.Count) then Exit;
  if (AItemIndex < 0) or (AItemIndex >= FGroups[AGroupIndex].Items.Count) then Exit;
  Result := FGroups[AGroupIndex].Items[AItemIndex].ImageIndex;
end;

function TTyListGroupPanel.GroupExpanded(AGroup: Integer): Boolean;
begin
  if (AGroup < 0) or (AGroup >= FGroups.Count) then Exit(False);
  Result := FGroups[AGroup].Expanded;
end;

procedure TTyListGroupPanel.SetGroupExpanded(AGroup: Integer; AValue: Boolean);
begin
  if (AGroup < 0) or (AGroup >= FGroups.Count) then Exit;
  if FGroups[AGroup].Expanded = AValue then Exit;
  FGroups[AGroup].FExpanded := AValue;  // direct: the repaint below covers it
  ClampScroll;
  Invalidate;
  if Assigned(FOnGroupToggle) then FOnGroupToggle(Self, AGroup);
end;

function TTyListGroupPanel.GetGroupCaption(AGroup: Integer): string;
begin
  Result := '';
  if (AGroup < 0) or (AGroup >= FGroups.Count) then Exit;
  Result := FGroups[AGroup].Caption;
end;

procedure TTyListGroupPanel.SetGroupCaption(AGroup: Integer; const AValue: string);
begin
  if (AGroup < 0) or (AGroup >= FGroups.Count) then Exit;
  FGroups[AGroup].Caption := AValue;    // the setter funnels the repaint
end;

procedure TTyListGroupPanel.ToggleGroup(AGroupIndex: Integer);
begin
  if (AGroupIndex < 0) or (AGroupIndex >= GroupCount) then Exit;
  SetGroupExpanded(AGroupIndex, not GroupExpanded(AGroupIndex));
end;

procedure TTyListGroupPanel.SelectItem(AGroupIndex, AItemIndex: Integer);
var
  valid: Boolean;
begin
  valid := (AGroupIndex >= 0) and (AGroupIndex < GroupCount)
    and (AItemIndex >= 0) and (AItemIndex < ItemCount(AGroupIndex));
  if not valid then
  begin
    AGroupIndex := -1;
    AItemIndex := -1;
  end;
  if (FSelGroup = AGroupIndex) and (FSelItem = AItemIndex) then Exit;
  FSelGroup := AGroupIndex;
  FSelItem := AItemIndex;
  Invalidate;
  if valid and Assigned(FOnItemClick) then FOnItemClick(Self, AGroupIndex, AItemIndex);
end;

procedure TTyListGroupPanel.SetSelGroup(AValue: Integer);
begin
  SelectItem(AValue, FSelItem);
end;

procedure TTyListGroupPanel.SetSelItem(AValue: Integer);
begin
  SelectItem(FSelGroup, AValue);
end;

procedure TTyListGroupPanel.ClearHover;
begin
  if (FHoverGroup <> -1) or (FHoverItem <> -1) then
  begin
    FHoverGroup := -1;
    FHoverItem := -1;
    Invalidate;
  end;
end;

procedure TTyListGroupPanel.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  parts: TTyListGroupParts;
  hit: TTyListGroupHit;
  bw: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  bw := MulDiv(CurrentStyle.BorderWidth, Font.PixelsPerInch, 96);
  // The collapse-trigger band claims the bottom strip before any row hit-testing.
  if FShowCollapseTrigger and (Y >= Height - bw - EffTriggerHPx(Font.PixelsPerInch))
    and (Y < Height - bw) then
  begin
    Collapsed := not Collapsed;
    try
      if CanFocus then SetFocus;
    except
      // headless / no-handle: ignore
    end;
    Exit;
  end;
  parts := BuildLayout;
  // Map device Y -> content Y: undo the top-border inset the paint adds, then add the scroll.
  hit := TyListGroupHitTest(parts, Point(X, Y - bw + FScrollOffset));
  if hit.Hit then
  begin
    if hit.Kind = lgpHeader then
      ToggleGroup(hit.GroupIndex)
    else
      SelectItem(hit.GroupIndex, hit.ItemIndex);
  end;
  try
    if CanFocus then SetFocus;
  except
    // headless / no-handle: ignore
  end;
end;

procedure TTyListGroupPanel.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  parts: TTyListGroupParts;
  hit: TTyListGroupHit;
  newKind: TTyListGroupPartKind;
  newGroup, newItem, bw: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  parts := BuildLayout;
  bw := MulDiv(CurrentStyle.BorderWidth, Font.PixelsPerInch, 96);
  hit := TyListGroupHitTest(parts, Point(X, Y - bw + FScrollOffset));
  if hit.Hit then
  begin
    newKind := hit.Kind;
    newGroup := hit.GroupIndex;
    newItem := hit.ItemIndex;
  end
  else
  begin
    newKind := lgpHeader;
    newGroup := -1;
    newItem := -1;
  end;
  if (newKind <> FHoverKind) or (newGroup <> FHoverGroup) or (newItem <> FHoverItem) then
  begin
    FHoverKind := newKind;
    FHoverGroup := newGroup;
    FHoverItem := newItem;
    Invalidate;
  end;
end;

procedure TTyListGroupPanel.MouseLeave;
begin
  inherited MouseLeave;
  ClearHover;
end;

function TTyListGroupPanel.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  step, m, old: Integer;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  m := MaxScrollOffset;
  if m <= 0 then Exit(False);   // nothing to scroll
  step := ScaledItemHeight * 3;
  old := FScrollOffset;
  if WheelDelta > 0 then
    Dec(FScrollOffset, step)
  else
    Inc(FScrollOffset, step);
  if FScrollOffset > m then FScrollOffset := m;
  if FScrollOffset < 0 then FScrollOffset := 0;
  if FScrollOffset <> old then Invalidate;
  Result := True;
end;

procedure TTyListGroupPanel.Resize;
begin
  inherited Resize;
  ClampScroll;
end;

procedure TTyListGroupPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, HdrStyle, ItemStyle: TTyStyleSet;
  R, partR, textR, chevRect, pillR: TRect;
  parts: TTyListGroupParts;
  i, hdrHPx, itemHPx, chevSize, insetPx, contentL, trigH, railIcon: Integer;
  states: TTyStateSet;
  kind: TTyGlyphKind;
  savedClip, trigR: TRect;
  cap: string;
  selected, hovered, leftSider: Boolean;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    BoxStyle := CurrentStyle;
    DrawFrame(P, R, BoxStyle);

    hdrHPx := EffHeaderHPx(APPI);
    itemHPx := EffItemHPx(APPI);
    chevSize := P.Scale(ActiveController.Metric(TyListGroupChevronSizeVar, TyListGroupDefaultChevronSize));
    insetPx := P.Scale(ActiveController.Metric(TyListGroupItemInsetVar, TyListGroupDefaultItemInset));
    if insetPx < 0 then insetPx := 0;

    // Recompute the layout in DEVICE space using APPI (RenderTo may be called with a test
    // PPI that differs from Font.PixelsPerInch), so paint geometry == the pure layout.
    parts := TyListGroupLayout(BuildShapes, hdrHPx, itemHPx, R.Right - R.Left);

    // Clip everything to the frame interior so scrolled content never paints over the border.
    // Rows additionally stop ABOVE the collapse-trigger band: it owns the bottom strip, and
    // MaxScrollOffset grants the same height back so the last row stays fully reachable.
    trigH := EffTriggerHPx(APPI);
    savedClip := P.Bitmap.ClipRect;
    P.Bitmap.ClipRect := Rect(R.Left + P.Scale(BoxStyle.BorderWidth),
      R.Top + P.Scale(BoxStyle.BorderWidth),
      R.Right - P.Scale(BoxStyle.BorderWidth),
      R.Bottom - P.Scale(BoxStyle.BorderWidth) - trigH);

    for i := 0 to High(parts) do
    begin
      // Inset content down past the top border (so the first row isn't clipped behind it), then
      // shift up by the scroll offset. Paired with MaxScrollOffset's interior-height range, both
      // the first row's top and the last row's bottom become fully reachable.
      partR := parts[i].Rect;
      OffsetRect(partR, 0, P.Scale(BoxStyle.BorderWidth) - FScrollOffset);
      // Skip parts entirely outside the visible band (the trigger strip is not row space).
      if (partR.Bottom <= R.Top) or (partR.Top >= R.Bottom - trigH) then Continue;

      if parts[i].Kind = lgpHeader then
      begin
        hovered := (FHoverGroup = parts[i].GroupIndex) and (FHoverItem = -1)
          and (FHoverKind = lgpHeader);
        states := [];
        if GroupExpanded(parts[i].GroupIndex) then Include(states, tysSelected)
        else if hovered then Include(states, tysHover)
        else Include(states, tysNormal);
        // Its OWN key, not the tree column header's: TyTreeHeaderSection is shared with
        // TreeView/ListView, so borrowing it made the sider un-restyleable. tysSelected = the
        // group is OPEN (a skin tints the open group accent through it).
        HdrStyle := ActiveController.Model.ResolveStyle('TyListGroupHeader', StyleClass, states);

        // Fill ONLY when the theme gives a background: a modern sider leaves the group row
        // unfilled (no grey band), so the absence of a bg must mean "no band", not a default.
        if tpBackground in HdrStyle.Present then
          P.FillBackground(partR, HdrStyle.Background, TyEffectiveCorners(HdrStyle));

        // Collapsed rail: the group header keeps its band and shows its icon centred —
        // no chevron, no caption (there is no room for either).
        if FCollapsed then
        begin
          railIcon := P.Scale(ActiveController.Metric(TyListGroupIconSizeVar, TyListGroupDefaultIconSize));
          DrawRowIcon(P, (partR.Left + partR.Right - railIcon) div 2, partR.Top,
            partR.Bottom - partR.Top, FGroups[parts[i].GroupIndex].ImageIndex);
          Continue;
        end;

        // Chevron on the RIGHT (Ant's placement), in a themed square slot. Down = expanded,
        // right = collapsed. Pad 1: chevRect is a slot already sized from a token, so the token
        // IS the mark's size — TyDrawGlyph's default 4px/side would leave an unreadable smudge.
        chevRect := Rect(partR.Right - P.Scale(HdrStyle.Padding.Right) - chevSize,
          partR.Top + (partR.Bottom - partR.Top - chevSize) div 2,
          partR.Right - P.Scale(HdrStyle.Padding.Right),
          partR.Top + (partR.Bottom - partR.Top - chevSize) div 2 + chevSize);
        if GroupExpanded(parts[i].GroupIndex) then kind := tgChevronDown else kind := tgChevronRight;
        TyDrawGlyph(P, ActiveController, chevRect, kind, HdrStyle.TextColor, 1, 1);

        // Optional group icon on the left, then the caption between icon and chevron.
        contentL := partR.Left + P.Scale(HdrStyle.Padding.Left);
        contentL := DrawRowIcon(P, contentL, partR.Top, partR.Bottom - partR.Top,
          FGroups[parts[i].GroupIndex].ImageIndex);
        cap := GetGroupCaption(parts[i].GroupIndex);
        if cap <> '' then
        begin
          textR := Rect(contentL, partR.Top, chevRect.Left - P.Scale(HdrStyle.Padding.Left),
            partR.Bottom);
          P.DrawText(textR, cap, HdrStyle.FontName, ResolveFontSize(HdrStyle),
            HdrStyle.FontWeight, HdrStyle.TextColor, taLeftJustify, tlCenter, True);
        end;
      end
      else
      begin
        // Item row.
        selected := (parts[i].GroupIndex = FSelGroup) and (parts[i].ItemIndex = FSelItem);
        hovered := (FHoverKind = lgpItem) and (FHoverGroup = parts[i].GroupIndex)
          and (FHoverItem = parts[i].ItemIndex);
        states := [];
        if selected then Include(states, tysActive)
        else if hovered then Include(states, tysHover)
        else Include(states, tysNormal);
        // Its OWN key (was TyListItem, shared with every list): so a selected item can be a
        // soft INSET ROUNDED pill instead of a full-bleed saturated bar.
        ItemStyle := ActiveController.Model.ResolveStyle('TyListGroupItem', StyleClass, states);

        // The pill: inset from the row's four edges (so it floats, not a full-width bar) and
        // rounded by the style's own border-radius. Inset/radius are theme-driven — that is the
        // single biggest difference from the old hard bar.
        pillR := Rect(partR.Left + insetPx, partR.Top + insetPx div 2,
          partR.Right - insetPx, partR.Bottom - insetPx div 2);
        if tpBackground in ItemStyle.Present then
          P.FillBackground(pillR, ItemStyle.Background, TyEffectiveCorners(ItemStyle));

        // Collapsed rail: the selection pill stays (narrow), the icon centres, and the
        // caption and hierarchy indent are dropped.
        if FCollapsed then
        begin
          railIcon := P.Scale(ActiveController.Metric(TyListGroupIconSizeVar, TyListGroupDefaultIconSize));
          DrawRowIcon(P, (partR.Left + partR.Right - railIcon) div 2, partR.Top,
            partR.Bottom - partR.Top, ItemImageIndex(parts[i].GroupIndex, parts[i].ItemIndex));
          Continue;
        end;

        // Content inside the pill: the caption's own padding + a HIERARCHY INDENT (a child sits
        // clearly deeper than its group header), then the optional icon, then the caption. The
        // indent is its own token — NOT the pill inset — so the step is tunable independently of
        // how far the pill floats off the edges.
        contentL := pillR.Left + P.Scale(ItemStyle.Padding.Left)
          + P.Scale(ActiveController.Metric(TyListGroupItemIndentVar, TyListGroupDefaultItemIndent));
        contentL := DrawRowIcon(P, contentL, partR.Top, partR.Bottom - partR.Top,
          ItemImageIndex(parts[i].GroupIndex, parts[i].ItemIndex));
        cap := ItemCaption(parts[i].GroupIndex, parts[i].ItemIndex);
        textR := Rect(contentL, partR.Top, pillR.Right - P.Scale(ItemStyle.Padding.Right),
          partR.Bottom);
        P.DrawText(textR, cap, ItemStyle.FontName, ResolveFontSize(ItemStyle),
          ItemStyle.FontWeight, ItemStyle.TextColor, taLeftJustify, tlCenter, True);
      end;
    end;

    // The collapse-trigger band, under the rows and inside the border. Dressed by the
    // group-header key (normal state) so a skin that tints headers tints the trigger with
    // them; the chevron points where a click will take the edge — away from the content
    // when expanded, back over it when collapsed — mirrored for a right-docked sider.
    if trigH > 0 then
    begin
      P.Bitmap.ClipRect := Rect(R.Left + P.Scale(BoxStyle.BorderWidth),
        R.Top + P.Scale(BoxStyle.BorderWidth),
        R.Right - P.Scale(BoxStyle.BorderWidth),
        R.Bottom - P.Scale(BoxStyle.BorderWidth));
      trigR := Rect(R.Left + P.Scale(BoxStyle.BorderWidth),
        R.Bottom - P.Scale(BoxStyle.BorderWidth) - trigH,
        R.Right - P.Scale(BoxStyle.BorderWidth),
        R.Bottom - P.Scale(BoxStyle.BorderWidth));
      HdrStyle := ActiveController.Model.ResolveStyle('TyListGroupHeader', StyleClass, [tysNormal]);
      if tpBackground in HdrStyle.Present then
        P.FillBackground(trigR, HdrStyle.Background, TyEffectiveCorners(HdrStyle));
      leftSider := Align <> alRight;
      if leftSider xor FCollapsed then kind := tgChevronLeft else kind := tgChevronRight;
      chevRect := Rect((trigR.Left + trigR.Right - chevSize) div 2,
        (trigR.Top + trigR.Bottom - chevSize) div 2,
        (trigR.Left + trigR.Right + chevSize) div 2,
        (trigR.Top + trigR.Bottom + chevSize) div 2);
      TyDrawGlyph(P, ActiveController, chevRect, kind, HdrStyle.TextColor, 1, 1);
    end;

    P.Bitmap.ClipRect := savedClip;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyListGroupPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
