unit tyControls.Cascader;
{$mode objfpc}{$H+}
{ TTyCascader — a cascading picker: a combo-like field that drops a MULTI-COLUMN panel.
  Picking in column N reveals column N+1 (the children of what was picked); picking a node
  with NO children is a complete selection — it commits and closes. The classic 省/市/区
  field.

  The gap it fills. TTyComboBox picks one row out of ONE flat list; TTyTreeView shows a
  hierarchy but is not a field. Neither expresses "pick a PATH through a hierarchy in a
  field-sized control", which is what an address / category / org-unit picker is.

  THE DATA MODEL — the part to read first. An option is a caption plus a (possibly empty)
  list of child options: TTyCascaderNode / TTyCascaderNodes, a plain TCollection tree.
  Deliberately NOT the TTyTreeView node model: that one is a virtual, column-aware,
  image-list-bound VIEW structure whose nodes exist to be painted by a tree and only make
  sense attached to one. A cascader option needs a caption, children, and (for AntD parity)
  an enabled flag — nothing else. A TCollection is the simplest structure that carries that
  AND is the one thing the Lazarus designer and the .lfm streamer already know how to edit
  and round-trip: nested collections stream recursively, so the whole option tree lives in
  the .lfm with no custom streaming code.

  THE VALUE is a PATH: TTyCascaderPath = array of Integer, one child index per level, so
  [1, 0, 3] means "root option 1, its child 0, that one's child 3". [] is "nothing
  selected". Text is those nodes' captions joined by Separator. EVERY rule about paths and
  columns is a free function at the top of this unit (plain ints / collections in, values
  out — no control, no handle, no theme), because those rules ARE this control's behaviour
  and they must be testable headlessly.

  DRAFT vs VALUE. The panel edits a DRAFT path; the field's Path only changes when a pick
  lands on a LEAF (Ant Design's rule). Browsing 华东 -> 浙江 and then dismissing the popup
  therefore leaves the committed value alone instead of stranding the field on a
  half-finished '华东 / 浙江'.

  typeKeys, and why there are three:
    'TyCascader'      — the closed FIELD: surface, border, focus ring, text, and the ink of
                        the drop chevron. Its own key rather than a borrowed 'TyComboBox'
                        because it is not one (its model is a tree, not a TStringList) and
                        every field control here owns its key by house convention.
    'TyCascaderPanel' — the floating multi-column PANEL. A different surface from the field:
                        it floats above the form, so a theme gives it its popup elevation
                        (radius / border / shadow), and its BORDER colour is what draws the
                        dividers between columns.
    'TyCascaderItem'  — one ROW in a column. Its :selected / :hover / :disabled states are
                        what make the panel read at all — exactly the TySegmented ->
                        TySegmentedItem relationship. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel, tyControls.Popup, tyControls.QtWS;

const
  { Built-in logical-px defaults (96-PPI baseline) for this control's metrics. A skin
    retunes each through its named theme metric below (the v3/C convention); these are only
    what a theme that sets none falls back to. Every call site scales them to device px.
    The button width IS TyFieldButtonWidth, so a cascader's chevron zone and a combo box's
    are the same width and the two fields line up in a form. }
  TyCascaderColumnWidth = 120;                    // one column's width
  TyCascaderRowHeight   = 24;                     // one option row's height
  TyCascaderExpandSize  = 12;                     // the '>' slot on a branch row, square
  TyCascaderExpandGap   = 4;                      // gap between a caption and its '>' slot
  TyCascaderButtonWidth = TyFieldButtonWidth;     // the field's drop-chevron zone

  { The metric token each constant backs. Named constants rather than inline literals
    because several call sites (geometry, measurement, the tests) must agree on the
    spelling — a typo in one would silently strand it on the default and the geometry would
    drift from the hit-test. }
  TyCascaderColumnWidthVar = '--cascader-column-width';
  TyCascaderRowHeightVar   = '--cascader-row-height';
  TyCascaderExpandSizeVar  = '--cascader-expand-size';
  TyCascaderExpandGapVar   = '--cascader-expand-gap';
  TyCascaderButtonWidthVar = '--cascader-button-width';

  { The default path joiner. A property default, not drawn text of the control's own — the
    control never invents a word, it only puts this between two captions the HOST supplied.
    ' / ' is Ant Design's, and it reads the same in Chinese and English. }
  TyCascaderSeparator = ' / ';

type
  { The value: one child index per level. [] = nothing selected. }
  TTyCascaderPath = array of Integer;

  TTyCascaderNodes = class;

  { One option: a caption, its children, and whether it can be picked.
    A node with NO children is a LEAF — picking it is a complete selection. }
  TTyCascaderNode = class(TCollectionItem)
  private
    FCaption: string;
    FChildren: TTyCascaderNodes;
    FEnabled: Boolean;
    FTag: NativeInt;
    procedure SetCaption(const AValue: string);
    procedure SetChildren(AValue: TTyCascaderNodes);
    procedure SetEnabled(AValue: Boolean);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(ASource: TPersistent); override;
    { True when this option ends a path: no children, so picking it commits.
      Nil-safe against the window during construction where FChildren is not built yet
      (TCollectionItem.Create notifies its collection BEFORE our constructor body runs, and
      that notification bubbles out to the control). }
    function IsLeaf: Boolean;
  published
    { The option's text. Drawn with the resolved TyCascaderItem style (never the LCL Font),
      and joined into the field's Text by the cascader's Separator. }
    property Caption: string read FCaption write SetCaption;
    { This option's sub-options. Empty => this is a leaf. A nested collection: the .lfm
      streams the whole tree recursively with no custom streaming code. }
    property Children: TTyCascaderNodes read FChildren write SetChildren;
    { False greys the row (TyCascaderItem:disabled) and makes it unpickable by mouse AND
      unreachable by the arrow keys, which step OVER it. Its children are unreachable with
      it — there is no path through an option you cannot pick. }
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    { Free for the host: a database id, a pointer-sized payload, anything. Never read here. }
    property Tag: NativeInt read FTag write FTag default 0;
  end;

  { An ordered list of options — the root list of a cascader, or one node's children.
    Every mutation anywhere in the tree bubbles up to the ROOT collection's OnChange (see
    DoNodesChanged), which is the single hook the control listens on. }
  TTyCascaderNodes = class(TCollection)
  private
    FOwner: TPersistent;      // the cascader (root list) or the parent node (a sub-list)
    FOnChange: TNotifyEvent;
    function GetNode(AIndex: Integer): TTyCascaderNode;
    procedure SetNode(AIndex: Integer; AValue: TTyCascaderNode);
  protected
    function GetOwner: TPersistent; override;
    procedure Update(AItem: TCollectionItem); override;
    procedure Notify(AItem: TCollectionItem; AAction: TCollectionNotification); override;
    { Bubble a change to the ROOT list and fire its OnChange there. A sub-list has no hook
      of its own: the control only ever wires the root, so a caption edited four levels down
      still reaches it. }
    procedure DoNodesChanged;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TTyCascaderNode;
    { Append a captioned option — the one-liner the code-built trees in the docs use. }
    function AddNode(const ACaption: string): TTyCascaderNode;
    property Items[AIndex: Integer]: TTyCascaderNode read GetNode write SetNode; default;
    { Wired by the control on the ROOT list only; a sub-list bubbles to it. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

{ --- pure rules: paths and columns ---------------------------------------------------- }

{ A by-value copy — the paths handed out and taken in are values, never aliases of the
  control's own array (a caller that mutated one in place would corrupt the selection). }
function TyCascaderCopyPath(const APath: TTyCascaderPath): TTyCascaderPath;

{ APath's first ALength entries. Clamped both ways (a negative length is [], a length past
  the end is the whole path), so callers never bounds-check first. }
function TyCascaderTruncatePath(const APath: TTyCascaderPath; ALength: Integer): TTyCascaderPath;

{ Entry-by-entry equality — the change test. Two paths of different lengths differ. }
function TyCascaderPathsEqual(const APathA, APathB: TTyCascaderPath): Boolean;

{ The column ANode's children form, or nil when it has none. nil (not an empty collection)
  is the single answer to "is this a leaf" and "is there a column after it", so a leaf and
  a branch-with-an-emptied-child-list can never read differently. }
function TyCascaderChildrenOf(ANode: TTyCascaderNode): TTyCascaderNodes;

{ The node APath's first ADepth entries select, or nil when they select nothing real (an
  index out of range, or a path that walks through a leaf). ADepth is clamped into
  [0, Length(APath)]; depth 0 selects the root LIST, which is not a node, so it answers nil. }
function TyCascaderNodeAt(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  ADepth: Integer): TTyCascaderNode;

{ APath truncated at the first entry that does not select a real, ENABLED node — the
  normaliser every path entering the control goes through. A path is never rejected and
  never clamped onto a neighbouring option: it is cut back to the prefix that is still true
  of the tree. (The house rule from TTyListBox.ItemIndex: an index that is not there means
  "not selected", not "the nearest one".) }
function TyCascaderValidPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): TTyCascaderPath;

{ The option list column AColumn shows: column 0 is the root list, column k is the children
  of the node at APath[0..k-1]. nil when that column does not exist — which is exactly how
  a caller learns the columns have run out. }
function TyCascaderColumnNodes(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  AColumn: Integer): TTyCascaderNodes;

{ How many columns APath reveals: the root column, plus one for every path entry whose node
  has children. 0 when there are no options at all. This is THE rule the panel's width comes
  from, and it stops at the first entry APath gets wrong, so an invalid path can only ever
  show fewer columns — never a broken one. }
function TyCascaderColumnCount(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Integer;

{ The row selected in column AColumn, or -1 for none. Column k's selection IS APath[k] —
  that identity is the whole reason the value is a path of indices. }
function TyCascaderSelectedInColumn(const APath: TTyCascaderPath; AColumn: Integer): Integer;

{ The most nodes any visible column holds — what the popup's height is measured against. }
function TyCascaderMaxColumnRows(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Integer;

{ What a pick of row AIndex in column AColumn does to APath: TRUNCATE to AColumn entries,
  then EXTEND with AIndex. That single rule covers every case — picking deeper extends,
  re-picking at a level drops everything to its right (you changed 省, so the 市 you had is
  no longer part of an answer), and re-picking the SAME row at a level still drops it (the
  user re-chose that level, which is a statement about the levels under it).
  A degenerate pick (no column, no row) returns APath unchanged. }
function TyCascaderPickPath(const APath: TTyCascaderPath; AColumn, AIndex: Integer): TTyCascaderPath;

{ True when APath selects a real node with no children — a COMPLETE selection, which is what
  the cascader commits and closes on. The empty path is never a leaf. }
function TyCascaderPathIsLeaf(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Boolean;

{ APath's captions joined by ASeparator ('华东 / 浙江 / 杭州'). A path that goes wrong joins
  the prefix it got right rather than raising — Text is drawn every paint and must never be
  the thing that takes the form down. }
function TyCascaderPathText(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  const ASeparator: string): string;

{ The inverse of TyCascaderPathText: resolve a joined caption path back to indices. False
  (and APath = []) when a segment matches no child at its level. Matching is case-SENSITIVE
  and takes the FIRST match — captions are data, and two siblings sharing one are the
  caller's ambiguity to resolve, not this function's to guess at. An empty AText resolves to
  the empty path (True): "" is a legitimate value, meaning nothing is selected. }
function TyCascaderPathFromText(ARoot: TTyCascaderNodes; const AText, ASeparator: string;
  out APath: TTyCascaderPath): Boolean;

{ --- pure rules: keyboard -------------------------------------------------------------- }

{ The row a step of ADelta from ACurrent lands on within ALevel, SKIPPING disabled options.
  Only ADelta's SIGN is read (one row per press). CLAMPED at both ends — no wrap: a column is
  a short list the user can see, so running off the end should stop, not teleport (the house
  rule from TTyCustomTabStrip / TTySegmented). From -1 the step ENTERS the column at the end
  it came from: down takes the first enabled row, up the last. -1 when the column has no
  enabled row to land on at all. }
function TyCascaderStepIndex(ALevel: TTyCascaderNodes; ACurrent, ADelta: Integer): Integer;

{ Step the selection in the DEEPEST visible column. Which column that is needs no cursor
  state: it is always TyCascaderColumnCount - 1, and it is already the right one in both
  shapes — with a branch selected, the deepest column is the fresh, unselected one the user
  is looking at; with a leaf selected, it is the column that leaf is in. }
function TyCascaderStepPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  ADelta: Integer): TTyCascaderPath;

{ Descend one level: land on the first enabled child of the currently-selected node. APath
  unchanged when it selects nothing, a leaf, or a branch whose children are all disabled. }
function TyCascaderEnterPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): TTyCascaderPath;

{ Back out one level (drop the last entry). The empty path stays empty. }
function TyCascaderLeavePath(const APath: TTyCascaderPath): TTyCascaderPath;

{ --- pure rules: geometry -------------------------------------------------------------- }

type
  { The geometry of the closed FIELD, in DEVICE px relative to the control rect's top-left.
    TextRect is where the joined path is drawn (empty => nothing fits); ButtonRect is the
    drop-chevron zone (empty => none). }
  TTyCascaderFieldLayout = record
    TextRect: TRect;
    ButtonRect: TRect;
  end;

  { The geometry of one option ROW, in DEVICE px in the PANEL's own space (unlike
    TyTagLayout's control-local rects — a row lives inside a column inside the panel, and
    carrying the origin through is what keeps the paint and the hit-test on one rect).
    CaptionRect is the option's text band; ExpandRect is the '>' slot (empty on a leaf, or
    when the row is too narrow to spare the room). }
  TTyCascaderRowLayout = record
    CaptionRect: TRect;
    ExpandRect: TRect;
  end;

{ Pure geometry for the closed field. All inputs/outputs are DEVICE px. The chevron zone
  hugs the right of the FULL rect and the text band stops at it — deliberately identical to
  TTyComboBox.RenderTo, so a cascader and a combo box sitting in the same form have their
  text on the same left edge and their chevrons in the same place. Padding that eats the
  whole field, or a zero size, leaves both rects empty rather than inverted. }
function TyCascaderFieldLayout(AClientWidth, AClientHeight, APadLeft, APadTop, APadRight,
  APadBottom, AButtonWidth: Integer): TTyCascaderFieldLayout;

{ Column AIndex's rect within a panel of (APanelWidth x APanelHeight) DEVICE px. Columns
  TILE left-to-right from the padded band's left edge, each exactly AColumnWidth wide, and a
  column that would overhang the band's right edge is CLIPPED to it (never drawn past the
  panel's own padding). An empty rect — never an inverted one — for a degenerate request: no
  columns, an index out of range, a zero-area panel, or padding that eats the whole panel. }
function TyCascaderColumnRect(APanelWidth, APanelHeight, AColumnCount, AColumnWidth,
  APadLeft, APadTop, APadRight, APadBottom, AIndex: Integer): TRect;

{ The column at panel-local device (X, Y), or -1 for none. The exact INVERSE of
  TyCascaderColumnRect (it scans that function's own rects), so the column the user clicks is
  the column that was painted there. The panel's padding gutter belongs to no column. }
function TyCascaderColumnAt(APanelWidth, APanelHeight, AColumnCount, AColumnWidth,
  APadLeft, APadTop, APadRight, APadBottom, X, Y: Integer): Integer;

{ The panel size that shows AColumnCount columns of AVisibleRows rows whole — the inverse of
  TyCascaderColumnRect: feed the result back in (same other arguments) and every column comes
  out exactly AColumnWidth wide and exactly AVisibleRows rows tall. DEVICE px throughout;
  this is what the popup is sized to. }
function TyCascaderPanelSize(AColumnCount, AColumnWidth, AVisibleRows, ARowHeight,
  APadLeft, APadTop, APadRight, APadBottom: Integer): TSize;

{ How many WHOLE rows a column AColumnHeight px tall shows. A partial row is not a row: it
  would be clipped mid-glyph and could not be safely clicked, so the column simply ends. }
function TyCascaderVisibleRows(AColumnHeight, ARowHeight: Integer): Integer;

{ Row AIndex's rect inside AColumnRect when the column is scrolled so AFirstRow is at the
  top. Empty when the row is scrolled out, or when it would only partly fit (see
  TyCascaderVisibleRows). }
function TyCascaderRowRect(const AColumnRect: TRect; ARowHeight, AFirstRow,
  AIndex: Integer): TRect;

{ The row at panel-local device (X, Y) within AColumnRect, or -1 for none. The exact INVERSE
  of TyCascaderRowRect: it computes the row arithmetically and then re-derives that row's
  rect to confirm, so a click in the sliver a partial row would have occupied answers -1
  rather than picking an option the user cannot see whole. }
function TyCascaderRowAt(const AColumnRect: TRect; ARowHeight, AFirstRow, ACount,
  X, Y: Integer): Integer;

{ AFirstRow clamped into the range that keeps the column's last row reachable and its first
  row from scrolling past the top: [0, max(0, ACount - AVisibleRows)]. A column that fits
  whole can only ever be at 0. }
function TyCascaderClampFirstRow(AFirstRow, ACount, AVisibleRows: Integer): Integer;

{ The top row that brings ARow into view with the LEAST movement: AFirstRow unchanged when
  ARow is already visible, ARow itself when it is above the band, and ARow at the band's
  bottom when it is below. Clamped like TyCascaderClampFirstRow. This is what the arrow keys
  scroll by — a click cannot land on a row that is not already visible, so the mouse never
  needs it. }
function TyCascaderScrollToShow(AFirstRow, ARow, ACount, AVisibleRows: Integer): Integer;

{ Pure geometry for one option row. The CAPTION wins the space, the reverse of TyTagLayout's
  rule and for the same reason read the other way round: a tag's x is its only affordance so
  it keeps the room, whereas a cascader row is clickable end to end and its '>' says only
  "there is more under here" — pure decoration. So a row too narrow for both drops the mark
  and keeps the words. }
function TyCascaderRowLayout(const ARowRect: TRect; AHasChildren: Boolean;
  APadLeft, APadRight, AGap, AExpandSize: Integer): TTyCascaderRowLayout;

{ The tokens a nested key draws its TEXT with: its own where the theme sets them, the
  parent surface's otherwise. The house degradation rule (no colour => inherit the parent's
  ink) extended to the font by the same logic — a theme that styles only TyCascaderPanel
  must still get legible, correctly-sized rows, and NEVER a hard-coded colour. Background
  and border are deliberately NOT inherited this way: a row with no background of its own
  must draw no chip. }
function TyCascaderInheritText(const AParent, AChild: TTyStyleSet): TTyStyleSet;

type
  { The multi-column panel a TTyCascader drops. INTERNAL: created by the field on first use
    and hosted in the dropdown popup — it is not a palette component and must not be
    registered as one (there is nothing to do with one on a form).

    It edits a DRAFT path (Path) over a REFERENCED option tree (Root, never owned) and fires
    OnPick after every user pick. The field decides what a pick MEANS — the panel only knows
    where the user clicked and what that does to a path.

    A WINDOWED control (TTyCustomControl): it is the popup's alClient content, and a graphic
    control cannot be a form's content (no handle). TabStop is deliberately False so the
    popup FORM keeps focus and its KeyPreview hook can route the keyboard, exactly as
    TTyComboBox routes Escape to its list. }
  TTyCascaderPanel = class(TTyCustomControl)
  private
    FRoot: TTyCascaderNodes;      // referenced, never owned
    FPath: TTyCascaderPath;       // the DRAFT
    FFirstRow: array of Integer;  // per-column scroll offset, index = column
    FHoverColumn: Integer;
    FHoverRow: Integer;
    FOnPick: TNotifyEvent;
    procedure SetRoot(AValue: TTyCascaderNodes);
    function GetPath: TTyCascaderPath;
    procedure SetPath(const AValue: TTyCascaderPath);
    function ColumnWidthPx(APPI: Integer): Integer;
    function RowHeightPx(APPI: Integer): Integer;
    { How many whole rows a column currently shows, from the panel's LIVE height. }
    function VisibleRowsNow: Integer;
    { Grow/clamp the per-column scroll array to the current column count. Called after every
      change that can add, drop or re-fill a column. }
    procedure SyncScroll;
    function FirstRowOf(AColumn: Integer): Integer;
    { Scroll column AColumn the least distance that puts row ARow in view. }
    procedure EnsureVisible(AColumn, ARow: Integer);
    { The resolved style of one row: 'TyCascaderItem' with the PANEL's StyleClass (so a
      variant reaches both keys) and the state of THAT row. }
    function RowStyle(AColumn, AIndex: Integer): TTyStyleSet;
    function RowStates(AColumn, AIndex: Integer): TTyStateSet;
    procedure SetHover(AColumn, AIndex: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    { When True the panel surface is painted with SQUARE corners (frame radius forced to 0).
      The field sets it on Wayland, where the popup window cannot be shape-masked, so a
      square paint matches the square window. Default False. (TTyListBox's flag, same rule.)
      A public FIELD, not a property, and first in this section: FPC requires fields to
      precede methods within one visibility block. }
    ForceSquareSurface: Boolean;
    constructor Create(AOwner: TComponent); override;
    { The option tree this panel shows. A REFERENCE to the field's Nodes — the panel never
      owns it and never frees it. }
    property Root: TTyCascaderNodes read FRoot write SetRoot;
    { The draft path. Assigning it re-lays the columns; it never fires OnPick (only a user
      pick does). Always normalised against Root. A VALUE: the getter hands out a copy, so a
      caller that mutates what it read cannot reach into the panel's own array (FPC dynamic
      arrays are reference-counted but NOT copy-on-write). }
    property Path: TTyCascaderPath read GetPath write SetPath;
    { Fires after a user pick (mouse or keyboard) changed the draft. Read Path for the new
      draft; the field commits it when it is a leaf. }
    property OnPick: TNotifyEvent read FOnPick write FOnPick;
    { How many columns the draft reveals. }
    function ColumnCount: Integer;
    { The panel size that shows every column with at most AMaxRows rows visible, DEVICE px
      at APPI — measured from the THEME (column width / row height metrics + the panel's own
      padding), which is what the field sizes the popup to. }
    function TyPanelSize(AMaxRows, APPI: Integer): TSize;
    { Column AColumn's rect in DEVICE px, panel-local — the exact rect the paint used and
      the hit-test measures against; empty when out of range. Exposed for tests. }
    function TyPanelColumnRect(AColumn: Integer): TRect;
    { Row AIndex of column AColumn in DEVICE px, panel-local; empty when scrolled out or out
      of range. Exposed for tests. }
    function TyPanelRowRect(AColumn, AIndex: Integer): TRect;
    { The (column, row) at panel-local device (X, Y); False for none. }
    function TyPanelHitTest(X, Y: Integer; out AColumn, AIndex: Integer): Boolean;
    { Apply a user pick of row AIndex in column AColumn: normalise, store, fire OnPick. A
      pick of a disabled option, or of a row that is not there, is inert. Public so the
      field's keyboard path and the tests can drive the same seam the mouse does. }
    procedure PickAt(AColumn, AIndex: Integer);
    { Keyboard edits of the draft. Each fires OnPick only when the draft actually moved. }
    procedure StepDraft(ADelta: Integer);
    procedure EnterDraft;
    procedure LeaveDraft;
    { True when the draft is a complete selection (a leaf) — what the field commits on. }
    function DraftIsLeaf: Boolean;
    { Scroll column AColumn so ARow-th option is at its top (clamped). }
    procedure ScrollColumnTo(AColumn, ARow: Integer);
    { The top row of column AColumn. Exposed for tests. }
    function TyPanelFirstRow(AColumn: Integer): Integer;
  end;

  { A combo-like field that drops a multi-column cascading panel. }
  TTyCascader = class(TTyCustomControl)
  private
    FNodes: TTyCascaderNodes;
    FPath: TTyCascaderPath;
    FSeparator: string;
    FDropDownRows: Integer;
    FOnChange: TNotifyEvent;
    FOnDropDown: TNotifyEvent;
    FOnCloseUp: TNotifyEvent;
    FPopup: TTyDropdownPopup;      // lazy; owns its form. Freed in Destroy
    FPanel: TTyCascaderPanel;      // owned by Self; parented into FPopup.Form
    procedure SetNodes(AValue: TTyCascaderNodes);
    procedure NodesChanged(Sender: TObject);
    function GetPath: TTyCascaderPath;
    procedure SetPath(const AValue: TTyCascaderPath);
    procedure SetSeparator(const AValue: string);
    procedure SetDropDownRows(AValue: Integer);
    function GetPathText: string;
    function ButtonWidthPx(APPI: Integer): Integer;
    procedure EnsurePopup;
    { Push the current tree / value / controller into the panel. Split from EnsurePopup so
      DropDownPanel can hand out a fully-seeded panel with no window in sight. }
    procedure SyncPanel;
    procedure PanelPick(Sender: TObject);
    procedure PopupClosed(Sender: TObject);
    procedure PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DeferredCloseUp(Data: PtrInt);
  protected
    { Guard: tick at the last close-up. Click reopens only when >200ms have passed — the
      click-while-open reopen race (TTyComboBox's, same mechanics). }
    FCloseUpTick: QWord;
    function GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;
    function LayoutFor(AWidth, AHeight, APPI: Integer): TTyCascaderFieldLayout;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoChange; virtual;
    procedure DoDropDown; virtual;
    procedure DoCloseUp; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Open / close the cascading panel. DropDown is inert with no options (TTyComboBox's
      rule: never show an empty popup). }
    procedure DropDown;
    procedure CloseUp;
    function DroppedDown: Boolean;
    { Clear the selection (Path := []). Fires OnChange when something was selected. }
    procedure Clear;
    { The node Path selects, or nil when nothing is. }
    function SelectedNode: TTyCascaderNode;
    { How many levels are selected. }
    function PathDepth: Integer;
    { Select by a joined caption path ('华东 / 浙江 / 杭州'). False — and the selection is
      left ALONE — when the text names no path in the tree; see TyCascaderPathFromText for
      the matching rule. }
    function SelectByText(const AText: string): Boolean;
    { The dropdown panel, created on first use. Public because it is a live object a host may
      want to reach (and because it is the seam the pick rules are tested through: the panel
      exists and is fully seeded without a window ever being shown). }
    function DropDownPanel: TTyCascaderPanel;
    { The field's text band / chevron zone in DEVICE px, (0,0)-local — the exact rects the
      paint used. Exposed for tests. }
    function TyCascaderTextRect: TRect;
    function TyCascaderButtonRect: TRect;
    { The selected path, as one child index per level. [] = nothing selected. Assigning a
      path NORMALISES it (see TyCascaderValidPath): a path that is not true of the current
      tree is cut back to the prefix that is, SILENTLY — it is not clamped onto a
      neighbouring option and it does not raise. Values, not aliases: what you get back is a
      copy, and what you assign is copied in (FPC dynamic arrays are reference-counted but
      NOT copy-on-write, so handing out FPath itself would let a caller edit the selection
      from behind the setter's back). }
    property Path: TTyCascaderPath read GetPath write SetPath;
    { The selected captions joined by Separator; '' when nothing is selected. READ-ONLY and
      derived — write SelectByText (or Path) instead. This deliberately shadows TControl.Text
      for the TTyCascader static type, the way TTyComboBox.Text already does; LCL code, which
      sees the control as a TControl, still gets the inherited Caption text. }
    property Text: string read GetPathText;
  published
    { The option tree. Editing it anywhere re-validates the selection SILENTLY (see
      NodesChanged) and re-lays an open panel. }
    property Nodes: TTyCascaderNodes read FNodes write SetNodes;
    { What Text puts between two captions. Default ' / '. }
    property Separator: string read FSeparator write SetSeparator;
    { Max rows visible in a column before it scrolls (mirrors TTyComboBox.DropDownCount; a
      count, not a look, which is why it is a property and the row HEIGHT is a theme metric).
      Clamped to at least 1. }
    property DropDownRows: Integer read FDropDownRows write SetDropDownRows default 8;
    { Fires whenever Path actually changes — by a leaf commit, or from code. Re-assigning the
      same path is not a change and stays silent. Browsing the panel does NOT fire it: the
      panel edits a draft, and only a LEAF pick commits (see the unit header). }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
    property OnCloseUp: TNotifyEvent read FOnCloseUp write FOnCloseUp;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

{ --- TTyCascaderNode ------------------------------------------------------------------ }

constructor TTyCascaderNode.Create(ACollection: TCollection);
begin
  // The inherited constructor links us into ACollection, which NOTIFIES it (cnAdded) and
  // bubbles out to the control — before this body runs. Everything reachable from that
  // notification must therefore survive FChildren still being nil: see IsLeaf.
  inherited Create(ACollection);
  FEnabled := True;
  FChildren := TTyCascaderNodes.Create(Self);
end;

destructor TTyCascaderNode.Destroy;
begin
  FreeAndNil(FChildren);
  inherited Destroy;
end;

procedure TTyCascaderNode.Assign(ASource: TPersistent);
begin
  if ASource is TTyCascaderNode then
  begin
    FCaption := TTyCascaderNode(ASource).Caption;
    FEnabled := TTyCascaderNode(ASource).Enabled;
    FTag := TTyCascaderNode(ASource).Tag;
    // The whole subtree, not a shared reference: two options that pointed at one child list
    // would free it twice and edit each other.
    FChildren.Assign(TTyCascaderNode(ASource).Children);
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

function TTyCascaderNode.GetDisplayName: string;
begin
  // What the IDE's collection editor lists. Never blank: an unnamed row is unclickable.
  Result := FCaption;
  if Result = '' then Result := inherited GetDisplayName;
end;

function TTyCascaderNode.IsLeaf: Boolean;
begin
  Result := (FChildren = nil) or (FChildren.Count = 0);
end;

procedure TTyCascaderNode.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);   // -> Collection.Update -> DoNodesChanged -> the control repaints
end;

procedure TTyCascaderNode.SetChildren(AValue: TTyCascaderNodes);
begin
  // Assign, never re-point: FChildren is ours to free, and the .lfm reader writes INTO the
  // existing collection through this setter.
  FChildren.Assign(AValue);
end;

procedure TTyCascaderNode.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then Exit;
  FEnabled := AValue;
  // More than a repaint: disabling an option can invalidate a path that runs through it.
  Changed(False);
end;

{ --- TTyCascaderNodes ----------------------------------------------------------------- }

constructor TTyCascaderNodes.Create(AOwner: TPersistent);
begin
  inherited Create(TTyCascaderNode);
  FOwner := AOwner;
end;

function TTyCascaderNodes.GetOwner: TPersistent;
begin
  // The cascader for the root list, the parent NODE for a sub-list. The streamer and the OI
  // both walk this, which is what makes a nested collection editable in the designer.
  Result := FOwner;
end;

function TTyCascaderNodes.GetNode(AIndex: Integer): TTyCascaderNode;
begin
  Result := TTyCascaderNode(inherited Items[AIndex]);
end;

procedure TTyCascaderNodes.SetNode(AIndex: Integer; AValue: TTyCascaderNode);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyCascaderNodes.Add: TTyCascaderNode;
begin
  Result := TTyCascaderNode(inherited Add);
end;

function TTyCascaderNodes.AddNode(const ACaption: string): TTyCascaderNode;
begin
  Result := Add;
  Result.Caption := ACaption;
end;

procedure TTyCascaderNodes.DoNodesChanged;
var
  up: TPersistent;
begin
  // Walk to the ROOT list and fire there. Only the root carries a hook (the control wires
  // exactly one), so a caption edited four levels down still reaches the repaint.
  up := FOwner;
  if up is TTyCascaderNode then
  begin
    if TTyCascaderNode(up).Collection is TTyCascaderNodes then
      TTyCascaderNodes(TTyCascaderNode(up).Collection).DoNodesChanged;
    Exit;
  end;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCascaderNodes.Update(AItem: TCollectionItem);
begin
  inherited Update(AItem);
  DoNodesChanged;   // a property of some node changed
end;

procedure TTyCascaderNodes.Notify(AItem: TCollectionItem; AAction: TCollectionNotification);
begin
  inherited Notify(AItem, AAction);
  DoNodesChanged;   // an option was added / removed
end;

{ --- pure rules: paths and columns ---------------------------------------------------- }

function TyCascaderCopyPath(const APath: TTyCascaderPath): TTyCascaderPath;
var
  i: Integer;
begin
  Result := nil;   // a managed result FPC cannot see SetLength initialise (hint 5093)
  SetLength(Result, Length(APath));
  for i := 0 to High(APath) do Result[i] := APath[i];
end;

function TyCascaderTruncatePath(const APath: TTyCascaderPath; ALength: Integer): TTyCascaderPath;
var
  i, n: Integer;
begin
  Result := nil;
  n := ALength;
  if n < 0 then n := 0;
  if n > Length(APath) then n := Length(APath);
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := APath[i];
end;

function TyCascaderPathsEqual(const APathA, APathB: TTyCascaderPath): Boolean;
var
  i: Integer;
begin
  Result := False;
  if Length(APathA) <> Length(APathB) then Exit;
  for i := 0 to High(APathA) do
    if APathA[i] <> APathB[i] then Exit;
  Result := True;
end;

function TyCascaderChildrenOf(ANode: TTyCascaderNode): TTyCascaderNodes;
begin
  Result := nil;
  if ANode = nil then Exit;
  if (ANode.Children <> nil) and (ANode.Children.Count > 0) then
    Result := ANode.Children;
end;

function TyCascaderNodeAt(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  ADepth: Integer): TTyCascaderNode;
var
  lvl: TTyCascaderNodes;
  i, d: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  d := ADepth;
  if d > Length(APath) then d := Length(APath);
  if d <= 0 then Exit;   // depth 0 selects the root LIST, which is not a node
  lvl := ARoot;
  for i := 0 to d - 1 do
  begin
    if lvl = nil then Exit(nil);
    if (APath[i] < 0) or (APath[i] >= lvl.Count) then Exit(nil);
    Result := lvl[APath[i]];
    lvl := TyCascaderChildrenOf(Result);
  end;
end;

function TyCascaderValidPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): TTyCascaderPath;
var
  lvl: TTyCascaderNodes;
  nd: TTyCascaderNode;
  i, n: Integer;
begin
  lvl := ARoot;
  n := 0;
  for i := 0 to High(APath) do
  begin
    if lvl = nil then Break;                                  // walked into a leaf
    if (APath[i] < 0) or (APath[i] >= lvl.Count) then Break;   // no such option
    nd := lvl[APath[i]];
    if not nd.Enabled then Break;   // there is no path THROUGH an option you cannot pick
    Inc(n);
    lvl := TyCascaderChildrenOf(nd);
  end;
  Result := TyCascaderTruncatePath(APath, n);
end;

function TyCascaderColumnNodes(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  AColumn: Integer): TTyCascaderNodes;
begin
  Result := nil;
  if AColumn < 0 then Exit;
  if AColumn = 0 then
  begin
    if (ARoot <> nil) and (ARoot.Count > 0) then Result := ARoot;
    Exit;
  end;
  if AColumn > Length(APath) then Exit;   // no path entry to open that column
  Result := TyCascaderChildrenOf(TyCascaderNodeAt(ARoot, APath, AColumn));
end;

function TyCascaderColumnCount(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Integer;
var
  k: Integer;
begin
  Result := 0;
  if (ARoot = nil) or (ARoot.Count = 0) then Exit;
  Result := 1;   // the root column always shows once there is anything to show
  for k := 1 to Length(APath) do
    // Stop at the first column that is not there: an invalid path can only ever reveal
    // FEWER columns, never a broken one.
    if TyCascaderColumnNodes(ARoot, APath, k) <> nil then Inc(Result) else Break;
end;

function TyCascaderSelectedInColumn(const APath: TTyCascaderPath; AColumn: Integer): Integer;
begin
  if (AColumn < 0) or (AColumn >= Length(APath)) then
    Result := -1
  else
    Result := APath[AColumn];
end;

function TyCascaderMaxColumnRows(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Integer;
var
  k, cols: Integer;
  lvl: TTyCascaderNodes;
begin
  Result := 0;
  cols := TyCascaderColumnCount(ARoot, APath);
  for k := 0 to cols - 1 do
  begin
    lvl := TyCascaderColumnNodes(ARoot, APath, k);
    if (lvl <> nil) and (lvl.Count > Result) then Result := lvl.Count;
  end;
end;

function TyCascaderPickPath(const APath: TTyCascaderPath; AColumn, AIndex: Integer): TTyCascaderPath;
var
  keep, i: Integer;
begin
  if (AColumn < 0) or (AIndex < 0) then
    Exit(TyCascaderCopyPath(APath));   // nothing was picked: the path is what it was
  keep := AColumn;
  if keep > Length(APath) then keep := Length(APath);
  SetLength(Result, keep + 1);
  for i := 0 to keep - 1 do Result[i] := APath[i];
  Result[keep] := AIndex;
end;

function TyCascaderPathIsLeaf(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): Boolean;
var
  nd: TTyCascaderNode;
begin
  Result := False;
  if Length(APath) = 0 then Exit;
  nd := TyCascaderNodeAt(ARoot, APath, Length(APath));
  Result := (nd <> nil) and (TyCascaderChildrenOf(nd) = nil);
end;

function TyCascaderPathText(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  const ASeparator: string): string;
var
  i: Integer;
  nd: TTyCascaderNode;
begin
  Result := '';
  for i := 1 to Length(APath) do
  begin
    nd := TyCascaderNodeAt(ARoot, APath, i);
    if nd = nil then Break;   // a path gone wrong joins the prefix it got right
    // Count the LEVELS, not the built string: an option whose caption is blank must still
    // take its place between two separators rather than vanish.
    if i > 1 then Result := Result + ASeparator;
    Result := Result + nd.Caption;
  end;
end;

function TyCascaderPathFromText(ARoot: TTyCascaderNodes; const AText, ASeparator: string;
  out APath: TTyCascaderPath): Boolean;
var
  lvl: TTyCascaderNodes;
  rest, seg: string;
  cut, i, hit, n: Integer;
begin
  SetLength(APath, 0);
  Result := AText = '';
  if Result then Exit;                     // '' = nothing selected, and that always resolves
  if ASeparator = '' then Exit(False);     // an empty joiner cannot be un-joined
  lvl := ARoot;
  rest := AText;
  n := 0;
  repeat
    if lvl = nil then Exit(False);         // more segments than the tree has levels
    cut := Pos(ASeparator, rest);
    if cut > 0 then
    begin
      seg := Copy(rest, 1, cut - 1);
      rest := Copy(rest, cut + Length(ASeparator), Length(rest));
    end
    else
    begin
      seg := rest;
      rest := '';
    end;
    hit := -1;
    for i := 0 to lvl.Count - 1 do
      if lvl[i].Caption = seg then begin hit := i; Break; end;   // first match wins
    if hit < 0 then
    begin
      SetLength(APath, 0);
      Exit(False);
    end;
    Inc(n);
    SetLength(APath, n);
    APath[n - 1] := hit;
    lvl := TyCascaderChildrenOf(lvl[hit]);
  until cut <= 0;
  Result := True;
end;

{ --- pure rules: keyboard -------------------------------------------------------------- }

function TyCascaderStepIndex(ALevel: TTyCascaderNodes; ACurrent, ADelta: Integer): Integer;

  function Landed(AIdx: Integer): Boolean;
  begin
    Result := (AIdx >= 0) and (AIdx < ALevel.Count) and ALevel[AIdx].Enabled;
  end;

var
  i, dir: Integer;
begin
  Result := -1;
  if ALevel = nil then Exit;
  if ALevel.Count = 0 then Exit;
  if ADelta = 0 then
  begin
    if Landed(ACurrent) then Result := ACurrent;
    Exit;
  end;
  if ADelta > 0 then dir := 1 else dir := -1;
  if (ACurrent < 0) or (ACurrent >= ALevel.Count) then
  begin
    // Entering the column from nowhere: land on the end the step is coming FROM, so down
    // starts at the top and up at the bottom.
    if dir > 0 then i := 0 else i := ALevel.Count - 1;
  end
  else
    i := ACurrent + dir;
  while (i >= 0) and (i < ALevel.Count) do
  begin
    if ALevel[i].Enabled then Exit(i);
    Inc(i, dir);   // step OVER a disabled option rather than stopping on it
  end;
  // Ran off the end: clamp — stay on the current option when it is one we could be on.
  if Landed(ACurrent) then Result := ACurrent;
end;

function TyCascaderStepPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath;
  ADelta: Integer): TTyCascaderPath;
var
  col, sel, nxt: Integer;
  lvl: TTyCascaderNodes;
begin
  Result := TyCascaderCopyPath(APath);
  col := TyCascaderColumnCount(ARoot, APath) - 1;
  if col < 0 then Exit;   // no options at all
  lvl := TyCascaderColumnNodes(ARoot, APath, col);
  sel := TyCascaderSelectedInColumn(APath, col);
  nxt := TyCascaderStepIndex(lvl, sel, ADelta);
  if (nxt < 0) or (nxt = sel) then Exit;   // nothing to land on / already there
  Result := TyCascaderPickPath(APath, col, nxt);
end;

function TyCascaderEnterPath(ARoot: TTyCascaderNodes; const APath: TTyCascaderPath): TTyCascaderPath;
var
  kids: TTyCascaderNodes;
  first: Integer;
begin
  Result := TyCascaderCopyPath(APath);
  if Length(APath) = 0 then Exit;   // nothing selected to descend INTO
  kids := TyCascaderChildrenOf(TyCascaderNodeAt(ARoot, APath, Length(APath)));
  if kids = nil then Exit;          // a leaf has nowhere to go
  first := TyCascaderStepIndex(kids, -1, 1);
  if first < 0 then Exit;           // every child disabled: the level is unreachable
  Result := TyCascaderPickPath(APath, Length(APath), first);
end;

function TyCascaderLeavePath(const APath: TTyCascaderPath): TTyCascaderPath;
begin
  Result := TyCascaderTruncatePath(APath, Length(APath) - 1);
end;

{ --- pure rules: geometry -------------------------------------------------------------- }

function TyCascaderFieldLayout(AClientWidth, AClientHeight, APadLeft, APadTop, APadRight,
  APadBottom, AButtonWidth: Integer): TTyCascaderFieldLayout;
var
  btnL, textL, textR, textT, textB: Integer;
begin
  Result.TextRect := Rect(0, 0, 0, 0);
  Result.ButtonRect := Rect(0, 0, 0, 0);
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;
  if AButtonWidth < 0 then AButtonWidth := 0;

  // The chevron zone hugs the right of the FULL rect (not of the padded band) and spans the
  // full height — TTyComboBox's zone, so the two fields' chevrons line up.
  btnL := AClientWidth - AButtonWidth;
  if btnL < 0 then btnL := 0;
  if AButtonWidth > 0 then
    Result.ButtonRect := Rect(btnL, 0, AClientWidth, AClientHeight);

  // The text band: padded, stopping AT the chevron zone. The right padding is deliberately
  // not applied here — the button zone IS the field's right inset, exactly as in
  // TTyComboBox, so text in the two fields ends on the same edge.
  textL := APadLeft;
  textR := btnL;
  textT := APadTop;
  textB := AClientHeight - APadBottom;
  if (textR > textL) and (textB > textT) then
    Result.TextRect := Rect(textL, textT, textR, textB);
end;

function TyCascaderColumnRect(APanelWidth, APanelHeight, AColumnCount, AColumnWidth,
  APadLeft, APadTop, APadRight, APadBottom, AIndex: Integer): TRect;
var
  bandL, bandR, bandT, bandB, colL, colR: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (AColumnCount <= 0) or (AIndex < 0) or (AIndex >= AColumnCount) then Exit;
  if (APanelWidth <= 0) or (APanelHeight <= 0) or (AColumnWidth <= 0) then Exit;
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;

  // The band: the panel inset by its themed padding on all four sides. Padding that eats the
  // whole panel leaves nothing to lay out (an empty rect, never an inverted one).
  bandL := APadLeft;
  bandR := APanelWidth - APadRight;
  bandT := APadTop;
  bandB := APanelHeight - APadBottom;
  if (bandR <= bandL) or (bandB <= bandT) then Exit;

  colL := bandL + AIndex * AColumnWidth;
  colR := colL + AColumnWidth;
  if colL >= bandR then Exit;                 // scrolled entirely off the band
  if colR > bandR then colR := bandR;         // the last column is clipped, never overhangs
  Result := Rect(colL, bandT, colR, bandB);
end;

function TyCascaderColumnAt(APanelWidth, APanelHeight, AColumnCount, AColumnWidth,
  APadLeft, APadTop, APadRight, APadBottom, X, Y: Integer): Integer;
var
  i: Integer;
  R: TRect;
begin
  Result := -1;
  for i := 0 to AColumnCount - 1 do
  begin
    R := TyCascaderColumnRect(APanelWidth, APanelHeight, AColumnCount, AColumnWidth,
      APadLeft, APadTop, APadRight, APadBottom, i);
    if (R.Right > R.Left) and (X >= R.Left) and (X < R.Right)
       and (Y >= R.Top) and (Y < R.Bottom) then
      Exit(i);
  end;
end;

function TyCascaderPanelSize(AColumnCount, AColumnWidth, AVisibleRows, ARowHeight,
  APadLeft, APadTop, APadRight, APadBottom: Integer): TSize;
begin
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;
  if AColumnCount < 0 then AColumnCount := 0;
  if AColumnWidth < 0 then AColumnWidth := 0;
  if AVisibleRows < 0 then AVisibleRows := 0;
  if ARowHeight < 0 then ARowHeight := 0;
  Result.cx := APadLeft + AColumnCount * AColumnWidth + APadRight;
  Result.cy := APadTop + AVisibleRows * ARowHeight + APadBottom;
  // A popup is a window: it must have somewhere to be, even in a degenerate theme.
  if Result.cx < 1 then Result.cx := 1;
  if Result.cy < 1 then Result.cy := 1;
end;

function TyCascaderVisibleRows(AColumnHeight, ARowHeight: Integer): Integer;
begin
  Result := 0;
  if (AColumnHeight <= 0) or (ARowHeight <= 0) then Exit;
  Result := AColumnHeight div ARowHeight;
end;

function TyCascaderRowRect(const AColumnRect: TRect; ARowHeight, AFirstRow,
  AIndex: Integer): TRect;
var
  t: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if ARowHeight <= 0 then Exit;
  if AIndex < AFirstRow then Exit;                             // scrolled off the top
  if (AColumnRect.Right <= AColumnRect.Left)
     or (AColumnRect.Bottom <= AColumnRect.Top) then Exit;
  t := AColumnRect.Top + (AIndex - AFirstRow) * ARowHeight;
  // A row only counts when it fits WHOLE: a half-drawn option is clipped mid-glyph and
  // cannot be safely clicked, so the column just ends before it.
  if t + ARowHeight > AColumnRect.Bottom then Exit;
  Result := Rect(AColumnRect.Left, t, AColumnRect.Right, t + ARowHeight);
end;

function TyCascaderRowAt(const AColumnRect: TRect; ARowHeight, AFirstRow, ACount,
  X, Y: Integer): Integer;
var
  idx: Integer;
  R: TRect;
begin
  Result := -1;
  if ARowHeight <= 0 then Exit;
  if (X < AColumnRect.Left) or (X >= AColumnRect.Right) then Exit;
  if (Y < AColumnRect.Top) or (Y >= AColumnRect.Bottom) then Exit;
  idx := AFirstRow + (Y - AColumnRect.Top) div ARowHeight;
  if (idx < 0) or (idx >= ACount) then Exit;
  // Re-derive the row's own rect to confirm: that keeps this function the exact inverse of
  // TyCascaderRowRect for free, including its "no partial rows" rule.
  R := TyCascaderRowRect(AColumnRect, ARowHeight, AFirstRow, idx);
  if R.Bottom <= R.Top then Exit;
  Result := idx;
end;

function TyCascaderClampFirstRow(AFirstRow, ACount, AVisibleRows: Integer): Integer;
var
  maxTop: Integer;
begin
  maxTop := ACount - AVisibleRows;
  if maxTop < 0 then maxTop := 0;   // the column fits whole: the only top is 0
  Result := AFirstRow;
  if Result > maxTop then Result := maxTop;
  if Result < 0 then Result := 0;
end;

function TyCascaderScrollToShow(AFirstRow, ARow, ACount, AVisibleRows: Integer): Integer;
begin
  Result := AFirstRow;
  if AVisibleRows > 0 then
  begin
    if ARow < Result then
      Result := ARow                             // above the band: bring it to the top
    else if ARow > Result + AVisibleRows - 1 then
      Result := ARow - AVisibleRows + 1;         // below it: bring it to the bottom
  end;
  Result := TyCascaderClampFirstRow(Result, ACount, AVisibleRows);
end;

function TyCascaderRowLayout(const ARowRect: TRect; AHasChildren: Boolean;
  APadLeft, APadRight, AGap, AExpandSize: Integer): TTyCascaderRowLayout;
var
  bandL, bandR, expL, expT, expB, rowH: Integer;
begin
  Result.CaptionRect := Rect(0, 0, 0, 0);
  Result.ExpandRect := Rect(0, 0, 0, 0);
  rowH := ARowRect.Bottom - ARowRect.Top;
  if (ARowRect.Right <= ARowRect.Left) or (rowH <= 0) then Exit;
  if APadLeft < 0 then APadLeft := 0;
  if APadRight < 0 then APadRight := 0;
  if AGap < 0 then AGap := 0;
  if AExpandSize < 0 then AExpandSize := 0;

  bandL := ARowRect.Left + APadLeft;
  bandR := ARowRect.Right - APadRight;
  if bandR <= bandL then Exit;   // padding ate the row

  if AHasChildren and (AExpandSize > 0) then
  begin
    expL := bandR - AExpandSize;
    // Only take the room when a caption band SURVIVES it: the words are the row's content
    // and the mark is decoration, so a narrow column drops the mark, not the option's name.
    if expL - AGap > bandL then
    begin
      expT := ARowRect.Top + (rowH - AExpandSize) div 2;
      if expT < ARowRect.Top then expT := ARowRect.Top;
      expB := expT + AExpandSize;
      if expB > ARowRect.Bottom then expB := ARowRect.Bottom;   // squash, never overflow
      Result.ExpandRect := Rect(expL, expT, bandR, expB);
      bandR := expL - AGap;
    end;
  end;
  Result.CaptionRect := Rect(bandL, ARowRect.Top, bandR, ARowRect.Bottom);
end;

function TyCascaderInheritText(const AParent, AChild: TTyStyleSet): TTyStyleSet;
begin
  Result := AChild;
  if not (tpTextColor in AChild.Present) then
  begin
    Result.TextColor := AParent.TextColor;
    if tpTextColor in AParent.Present then Include(Result.Present, tpTextColor);
  end;
  if not (tpFontName in AChild.Present) then
  begin
    Result.FontName := AParent.FontName;
    if tpFontName in AParent.Present then Include(Result.Present, tpFontName);
  end;
  if not (tpFontSize in AChild.Present) then
  begin
    Result.FontSize := AParent.FontSize;
    if tpFontSize in AParent.Present then Include(Result.Present, tpFontSize);
  end;
  if not (tpFontWeight in AChild.Present) then
  begin
    Result.FontWeight := AParent.FontWeight;
    if tpFontWeight in AParent.Present then Include(Result.Present, tpFontWeight);
  end;
end;

{ --- TTyCascaderPanel ----------------------------------------------------------------- }

constructor TTyCascaderPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRoot := nil;
  SetLength(FPath, 0);
  FHoverColumn := -1;
  FHoverRow := -1;
  ForceSquareSurface := False;
  // The popup FORM keeps focus so its KeyPreview hook can route the keyboard (the field
  // drives every key). TabStop also gates TTyCustomControl.MouseDown's auto-focus, so a
  // click on a row cannot steal activation mid-pick.
  TabStop := False;
end;

function TTyCascaderPanel.GetStyleTypeKey: string;
begin
  Result := 'TyCascaderPanel';
end;

procedure TTyCascaderPanel.SetRoot(AValue: TTyCascaderNodes);
begin
  if FRoot = AValue then Exit;
  FRoot := AValue;
  // A different tree invalidates the draft outright.
  FPath := TyCascaderValidPath(FRoot, FPath);
  SyncScroll;
  Invalidate;
end;

function TTyCascaderPanel.GetPath: TTyCascaderPath;
begin
  Result := TyCascaderCopyPath(FPath);
end;

procedure TTyCascaderPanel.SetPath(const AValue: TTyCascaderPath);
var
  norm: TTyCascaderPath;
begin
  norm := TyCascaderValidPath(FRoot, AValue);   // a fresh array: never an alias of AValue
  if TyCascaderPathsEqual(norm, FPath) then Exit;
  FPath := norm;
  SyncScroll;
  Invalidate;
end;

function TTyCascaderPanel.ColumnCount: Integer;
begin
  Result := TyCascaderColumnCount(FRoot, FPath);
end;

function TTyCascaderPanel.ColumnWidthPx(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := ActiveController.Metric(TyCascaderColumnWidthVar, TyCascaderColumnWidth);
  if Result < 0 then Result := 0;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the rects the hit-test measures are the rects the paint drew.
  Result := MulDiv(Result, APPI, 96);
end;

function TTyCascaderPanel.RowHeightPx(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := ActiveController.Metric(TyCascaderRowHeightVar, TyCascaderRowHeight);
  if Result < 1 then Result := 1;   // a zero-height row would divide by zero in the hit-test
  Result := MulDiv(Result, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyCascaderPanel.VisibleRowsNow: Integer;
var
  S: TTyStyleSet;
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  // Measured off the padded BAND, not the raw height: that is the band the columns get.
  Result := TyCascaderVisibleRows(
    ClientHeight - MulDiv(S.Padding.Top, ppi, 96) - MulDiv(S.Padding.Bottom, ppi, 96),
    RowHeightPx(ppi));
end;

procedure TTyCascaderPanel.SyncScroll;
var
  i, cols, cnt, vis: Integer;
  lvl: TTyCascaderNodes;
begin
  cols := ColumnCount;
  if Length(FFirstRow) < cols then
  begin
    i := Length(FFirstRow);
    SetLength(FFirstRow, cols);
    while i < cols do begin FFirstRow[i] := 0; Inc(i); end;
  end;
  // Re-clamp every column: a column that just got shorter (or a panel that just got taller)
  // must not stay scrolled past its own end, showing a blank band.
  vis := VisibleRowsNow;
  for i := 0 to cols - 1 do
  begin
    lvl := TyCascaderColumnNodes(FRoot, FPath, i);
    if lvl = nil then cnt := 0 else cnt := lvl.Count;
    FFirstRow[i] := TyCascaderClampFirstRow(FFirstRow[i], cnt, vis);
  end;
end;

procedure TTyCascaderPanel.EnsureVisible(AColumn, ARow: Integer);
var
  lvl: TTyCascaderNodes;
  cnt: Integer;
begin
  SyncScroll;
  if (AColumn < 0) or (AColumn >= Length(FFirstRow)) then Exit;
  lvl := TyCascaderColumnNodes(FRoot, FPath, AColumn);
  if lvl = nil then cnt := 0 else cnt := lvl.Count;
  ScrollColumnTo(AColumn,
    TyCascaderScrollToShow(FFirstRow[AColumn], ARow, cnt, VisibleRowsNow));
end;

function TTyCascaderPanel.FirstRowOf(AColumn: Integer): Integer;
begin
  if (AColumn < 0) or (AColumn >= Length(FFirstRow)) then
    Result := 0
  else
    Result := FFirstRow[AColumn];
end;

function TTyCascaderPanel.TyPanelFirstRow(AColumn: Integer): Integer;
begin
  Result := FirstRowOf(AColumn);
end;

procedure TTyCascaderPanel.ScrollColumnTo(AColumn, ARow: Integer);
var
  lvl: TTyCascaderNodes;
  cnt, want: Integer;
begin
  SyncScroll;
  if (AColumn < 0) or (AColumn >= Length(FFirstRow)) then Exit;
  lvl := TyCascaderColumnNodes(FRoot, FPath, AColumn);
  if lvl = nil then cnt := 0 else cnt := lvl.Count;
  want := TyCascaderClampFirstRow(ARow, cnt, VisibleRowsNow);
  if want = FFirstRow[AColumn] then Exit;
  FFirstRow[AColumn] := want;
  Invalidate;
end;

function TTyCascaderPanel.TyPanelSize(AMaxRows, APPI: Integer): TSize;
var
  S: TTyStyleSet;
  rows: Integer;
begin
  S := CurrentStyle;
  rows := TyCascaderMaxColumnRows(FRoot, FPath);
  if rows > AMaxRows then rows := AMaxRows;
  if rows < 1 then rows := 1;   // an empty panel is still a window
  Result := TyCascaderPanelSize(ColumnCount, ColumnWidthPx(APPI), rows, RowHeightPx(APPI),
    MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Top, APPI, 96),
    MulDiv(S.Padding.Right, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96));
end;

function TTyCascaderPanel.TyPanelColumnRect(AColumn: Integer): TRect;
var
  S: TTyStyleSet;
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  Result := TyCascaderColumnRect(ClientWidth, ClientHeight, ColumnCount,
    ColumnWidthPx(ppi), MulDiv(S.Padding.Left, ppi, 96), MulDiv(S.Padding.Top, ppi, 96),
    MulDiv(S.Padding.Right, ppi, 96), MulDiv(S.Padding.Bottom, ppi, 96), AColumn);
end;

function TTyCascaderPanel.TyPanelRowRect(AColumn, AIndex: Integer): TRect;
var
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  Result := TyCascaderRowRect(TyPanelColumnRect(AColumn), RowHeightPx(ppi),
    FirstRowOf(AColumn), AIndex);
end;

function TTyCascaderPanel.TyPanelHitTest(X, Y: Integer; out AColumn, AIndex: Integer): Boolean;
var
  S: TTyStyleSet;
  lvl: TTyCascaderNodes;
  ppi, cnt: Integer;
begin
  AColumn := -1;
  AIndex := -1;
  Result := False;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  AColumn := TyCascaderColumnAt(ClientWidth, ClientHeight, ColumnCount, ColumnWidthPx(ppi),
    MulDiv(S.Padding.Left, ppi, 96), MulDiv(S.Padding.Top, ppi, 96),
    MulDiv(S.Padding.Right, ppi, 96), MulDiv(S.Padding.Bottom, ppi, 96), X, Y);
  if AColumn < 0 then Exit;
  lvl := TyCascaderColumnNodes(FRoot, FPath, AColumn);
  if lvl = nil then cnt := 0 else cnt := lvl.Count;
  AIndex := TyCascaderRowAt(TyPanelColumnRect(AColumn), RowHeightPx(ppi),
    FirstRowOf(AColumn), cnt, X, Y);
  Result := AIndex >= 0;
end;

procedure TTyCascaderPanel.PickAt(AColumn, AIndex: Integer);
var
  lvl: TTyCascaderNodes;
  want: TTyCascaderPath;
begin
  lvl := TyCascaderColumnNodes(FRoot, FPath, AColumn);
  if lvl = nil then Exit;
  if (AIndex < 0) or (AIndex >= lvl.Count) then Exit;
  // A disabled option is not a choice: the click is inert, exactly as the arrow keys step
  // over it. (TyCascaderValidPath would cut it back anyway; refusing here means the draft
  // never flickers through a state the user cannot be in.)
  if not lvl[AIndex].Enabled then Exit;
  want := TyCascaderValidPath(FRoot, TyCascaderPickPath(FPath, AColumn, AIndex));
  if TyCascaderPathsEqual(want, FPath) then Exit;
  FPath := want;
  SyncScroll;
  Invalidate;
  if Assigned(FOnPick) then FOnPick(Self);
end;

procedure TTyCascaderPanel.StepDraft(ADelta: Integer);
var
  want: TTyCascaderPath;
begin
  want := TyCascaderStepPath(FRoot, FPath, ADelta);
  if TyCascaderPathsEqual(want, FPath) then Exit;
  FPath := want;
  SyncScroll;
  // Keep the option the keyboard just landed on in view — the one place scroll follows the
  // selection (a click can only ever land on a row that is already visible). The step always
  // lands in the path's LAST column, on the row that IS its last entry.
  EnsureVisible(High(want), want[High(want)]);
  Invalidate;
  // NO FOnPick here: the arrow keys BROWSE the draft, they do not commit. Committing is a
  // mouse leaf-pick (PickAt -> FOnPick) or Enter (the VK_RETURN branch, which commits
  // directly). Firing FOnPick on every keyboard landing made a single Down commit + close the
  // popup the instant the draft touched a leaf, so a user could never arrow to a sibling leaf.
end;

procedure TTyCascaderPanel.EnterDraft;
var
  want: TTyCascaderPath;
begin
  want := TyCascaderEnterPath(FRoot, FPath);
  if TyCascaderPathsEqual(want, FPath) then Exit;
  FPath := want;
  SyncScroll;
  Invalidate;
  // NO FOnPick: keyboard browsing, not a commit (see StepDraft).
end;

procedure TTyCascaderPanel.LeaveDraft;
var
  want: TTyCascaderPath;
begin
  want := TyCascaderLeavePath(FPath);
  if TyCascaderPathsEqual(want, FPath) then Exit;
  FPath := want;
  SyncScroll;
  Invalidate;
  // NO FOnPick: keyboard browsing, not a commit (see StepDraft).
end;

function TTyCascaderPanel.DraftIsLeaf: Boolean;
begin
  Result := TyCascaderPathIsLeaf(FRoot, FPath);
end;

function TTyCascaderPanel.RowStates(AColumn, AIndex: Integer): TTyStateSet;
var
  lvl: TTyCascaderNodes;
begin
  Result := [];
  if AIndex = TyCascaderSelectedInColumn(FPath, AColumn) then
    // The SAME resting state TTyButton.Down and TTySegmented's chip inject, so one
    // ':selected' theme rule styles all three.
    Include(Result, tysSelected);
  lvl := TyCascaderColumnNodes(FRoot, FPath, AColumn);
  if (not Enabled) or (lvl = nil) or (AIndex < 0) or (AIndex >= lvl.Count)
     or (not lvl[AIndex].Enabled) then
  begin
    { Disabled KEEPS :selected, TTySegmented's rule: a greyed-out row must still show that it
      is the one in force. The cascade does the rest — ResolveLayer applies :selected as the
      resting layer and :disabled LAST at the highest precedence, so the chip survives while
      the disabled ink wins over it. Hover is deliberately absent: a disabled row takes none. }
    Include(Result, tysDisabled);
    Exit;
  end;
  if (AColumn = FHoverColumn) and (AIndex = FHoverRow) then Include(Result, tysHover);
  if Result = [] then Include(Result, tysNormal);
end;

function TTyCascaderPanel.RowStyle(AColumn, AIndex: Integer): TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle('TyCascaderItem', StyleClass,
    RowStates(AColumn, AIndex));
end;

procedure TTyCascaderPanel.SetHover(AColumn, AIndex: Integer);
begin
  if (FHoverColumn = AColumn) and (FHoverRow = AIndex) then Exit;
  FHoverColumn := AColumn;
  FHoverRow := AIndex;
  Invalidate;
end;

procedure TTyCascaderPanel.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  c, r: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  // Pick on PRESS: a cascader column is a menu, and every menu in this library commits on
  // press. A press in the padding gutter hits nothing and is inert — it must not clear a
  // draft the user can see.
  if TyPanelHitTest(X, Y, c, r) then PickAt(c, r);
end;

procedure TTyCascaderPanel.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if TyPanelHitTest(X, Y, c, r) then SetHover(c, r) else SetHover(-1, -1);
end;

procedure TTyCascaderPanel.MouseLeave;
begin
  inherited MouseLeave;   // clears the panel's own hover
  SetHover(-1, -1);
end;

function TTyCascaderPanel.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  S: TTyStyleSet;
  P: TPoint;
  ppi, col, step: Integer;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  // MousePos is SCREEN px (the LCL contract); the geometry is panel-local.
  P := ScreenToClient(MousePos);
  S := CurrentStyle;
  col := TyCascaderColumnAt(ClientWidth, ClientHeight, ColumnCount, ColumnWidthPx(ppi),
    MulDiv(S.Padding.Left, ppi, 96), MulDiv(S.Padding.Top, ppi, 96),
    MulDiv(S.Padding.Right, ppi, 96), MulDiv(S.Padding.Bottom, ppi, 96), P.X, P.Y);
  if col < 0 then Exit;
  // The wheel scrolls the column UNDER THE POINTER, not "the panel": the columns scroll
  // independently, and only one of them is what the user is reading.
  if WheelDelta > 0 then step := -1 else step := 1;
  ScrollColumnTo(col, FirstRowOf(col) + step);
  Result := True;
end;

procedure TTyCascaderPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, rowS, txtS: TTyStyleSet;
  R, colR, rowR: TRect;
  Lay: TTyCascaderRowLayout;
  lvl: TTyCascaderNodes;
  divFill: TTyFill;
  // NOT 'top': Pascal is case-insensitive and this class inherits TControl.Top.
  cols, rowH, i, k, topRow, divW: Integer;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at ARect.Left/Top,
    // so a non-zero ARect origin would shift the whole panel.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // Wayland popup: the window cannot be shape-masked, so paint square corners to match it.
    // Per-corner Radius wins in TyEffectiveCorners, so zero it AND BorderRadius.
    if ForceSquareSurface then
    begin
      S.BorderRadius := 0;
      S.Radius := Default(TTyCorners);
    end;
    // The panel surface. DrawFrame fills the parent's opaque surface first, which a WINDOWED
    // control needs whatever the theme says; everything of OURS below is gated on the theme
    // having defined the key.
    DrawFrame(P, R, S);
    if not (tpBackground in S.Present) then
    begin
      // No TyCascaderPanel rule -> draw nothing at all. Degrade rather than invent a look.
      P.EndPaint;
      Exit;
    end;

    cols := ColumnCount;
    rowH := RowHeightPx(APPI);
    divFill := Default(TTyFill);
    divFill.Kind := tfkSolid;
    divFill.Color := S.BorderColor;
    divW := P.Scale(S.BorderWidth);
    if divW < 1 then divW := 1;

    for k := 0 to cols - 1 do
    begin
      colR := TyCascaderColumnRect(R.Right, R.Bottom, cols, ColumnWidthPx(APPI),
        MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Top, APPI, 96),
        MulDiv(S.Padding.Right, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96), k);
      if (colR.Right <= colR.Left) or (colR.Bottom <= colR.Top) then Continue;

      // The divider between two columns is drawn in the PANEL's own border colour, and only
      // when the theme gave the panel a visible border at all — a borderless popup gets
      // borderless columns. Never a hard-coded rule colour.
      if (k > 0) and TyBorderVisible(S) then
        P.FillBackground(Rect(colR.Left, colR.Top, colR.Left + divW, colR.Bottom), divFill, 0);

      lvl := TyCascaderColumnNodes(FRoot, FPath, k);
      if lvl = nil then Continue;
      topRow := FirstRowOf(k);
      for i := topRow to lvl.Count - 1 do
      begin
        rowR := TyCascaderRowRect(colR, rowH, topRow, i);
        if rowR.Bottom <= rowR.Top then Break;   // the column ran out of whole rows
        rowS := RowStyle(k, i);

        // The chip. An undefined TyCascaderItem key leaves no background -> no chip, and the
        // captions below still draw: a theme that fills only :selected / :hover gets the
        // classic "only the current option has a plate" for free, with no code branch.
        if tpBackground in rowS.Present then
          P.FillBackground(rowR, rowS.Background, TyEffectiveCorners(rowS));
        if TyBorderVisible(rowS) then
          P.StrokeBorder(rowR, TyEffectiveCorners(rowS), rowS.BorderWidth, rowS.BorderColor);

        txtS := TyCascaderInheritText(S, rowS);
        Lay := TyCascaderRowLayout(rowR, not lvl[i].IsLeaf,
          P.Scale(rowS.Padding.Left), P.Scale(rowS.Padding.Right),
          P.Scale(ActiveController.Metric(TyCascaderExpandGapVar, TyCascaderExpandGap)),
          P.Scale(ActiveController.Metric(TyCascaderExpandSizeVar, TyCascaderExpandSize)));

        // Left-aligned + ellipsised: an option wider than its column shows '内蒙古自治…',
        // not a glyph sheared at the clip edge. No mnemonic parsing — an option activates
        // nothing, so an '&' in a caption is literal text.
        if Lay.CaptionRect.Right > Lay.CaptionRect.Left then
          P.DrawText(Lay.CaptionRect, lvl[i].Caption, txtS.FontName, ResolveFontSize(txtS),
            txtS.FontWeight, txtS.TextColor, taLeftJustify, tlCenter, True);
        // The '>' takes the ROW's ink (its own key's colour, or the panel's) — with only
        // three typeKeys the mark is part of the option's text colour, so a disabled row's
        // mark greys with its words. v3/C5: theme-overridable (--glyph-chevron-right).
        if Lay.ExpandRect.Right > Lay.ExpandRect.Left then
          // Pad 1, not the default 4: ExpandRect is a slot already measured from
          // --cascader-expand-size, so that token must mean the CHEVRON's size (the
          // default pad would eat 9 logical px and leave a 3px smudge).
          TyDrawGlyph(P, ActiveController, Lay.ExpandRect, tgChevronRight, txtS.TextColor, 1, 1);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCascaderPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ --- TTyCascader ---------------------------------------------------------------------- }

constructor TTyCascader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNodes := TTyCascaderNodes.Create(Self);
  FNodes.OnChange := @NodesChanged;
  SetLength(FPath, 0);
  FSeparator := TyCascaderSeparator;
  FDropDownRows := 8;
  FPopup := nil;
  FPanel := nil;
  FCloseUpTick := 0;
  TabStop := True;
  // The same drop size as TTyComboBox: the two fields are meant to sit in one column.
  Width := 145;
  Height := TyDensityHeight(ActiveController, 26);
end;

destructor TTyCascader.Destroy;
begin
  // Cancel any queued async close so it cannot fire into a freed field.
  Application.RemoveAsyncCalls(Self);
  // The helper first (it owns its form; it only PARENTED the panel), then the panel, which
  // is ours.
  FreeAndNil(FPopup);
  FreeAndNil(FPanel);
  FNodes.OnChange := nil;   // the collection fires as it clears
  FreeAndNil(FNodes);
  inherited Destroy;
end;

function TTyCascader.GetStyleTypeKey: string;
begin
  Result := 'TyCascader';
end;

procedure TTyCascader.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  // Keep an already-created panel themed by the same controller; otherwise it would keep the
  // old one until the next DropDown.
  if FPanel <> nil then FPanel.Controller := AValue;
  if FPopup <> nil then FPopup.Controller := ActiveController;
end;

{ --- options / value ------------------------------------------------------------------ }

procedure TTyCascader.SetNodes(AValue: TTyCascaderNodes);
begin
  FNodes.Assign(AValue);   // fires NodesChanged
end;

procedure TTyCascader.NodesChanged(Sender: TObject);
var
  valid: TTyCascaderPath;
begin
  // A tree edit can strand the selection on an option that is gone. Re-validate it SILENTLY:
  // editing Nodes is the host's own action, not a user selection, so announcing it back
  // through OnChange would fire an event the host caused and did not ask about (TTySegmented's
  // rule for the same situation). The host reads Path after its own edit.
  valid := TyCascaderValidPath(FNodes, FPath);
  if not TyCascaderPathsEqual(valid, FPath) then FPath := valid;
  if FPanel <> nil then
  begin
    // An open panel is showing the tree that just changed: re-seed it or it keeps painting
    // options that no longer exist.
    FPanel.Root := FNodes;
    FPanel.Path := FPath;
  end;
  if not (csLoading in ComponentState) then Invalidate;
end;

function TTyCascader.GetPath: TTyCascaderPath;
begin
  Result := TyCascaderCopyPath(FPath);
end;

procedure TTyCascader.SetPath(const AValue: TTyCascaderPath);
var
  norm: TTyCascaderPath;
begin
  norm := TyCascaderValidPath(FNodes, AValue);   // a fresh array: never an alias of AValue
  if TyCascaderPathsEqual(norm, FPath) then Exit;
  FPath := norm;
  Invalidate;
  DoChange;
end;

procedure TTyCascader.SetSeparator(const AValue: string);
begin
  if FSeparator = AValue then Exit;
  FSeparator := AValue;
  Invalidate;   // the joined Text is what the field draws
end;

procedure TTyCascader.SetDropDownRows(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;   // a popup with no rows shows nothing (TTyComboBox's clamp)
  if FDropDownRows = AValue then Exit;
  FDropDownRows := AValue;
  // No live resize of an open popup: the height is settled at DropDown, and re-sizing a
  // window out from under a click is worse than waiting for the next open.
end;

function TTyCascader.GetPathText: string;
begin
  Result := TyCascaderPathText(FNodes, FPath, FSeparator);
end;

procedure TTyCascader.Clear;
var
  empty: TTyCascaderPath;
begin
  SetLength(empty, 0);
  Path := empty;   // -> SetPath: silent when nothing was selected, OnChange when it was
end;

function TTyCascader.SelectedNode: TTyCascaderNode;
begin
  Result := TyCascaderNodeAt(FNodes, FPath, Length(FPath));
end;

function TTyCascader.PathDepth: Integer;
begin
  Result := Length(FPath);
end;

function TTyCascader.SelectByText(const AText: string): Boolean;
var
  found: TTyCascaderPath;
begin
  Result := TyCascaderPathFromText(FNodes, AText, FSeparator, found);
  // Only touch the selection on a hit: a caller that mistypes a path must not silently lose
  // the value it had.
  if Result then Path := found;
end;

{ --- geometry ------------------------------------------------------------------------- }

function TTyCascader.ButtonWidthPx(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := ActiveController.Metric(TyCascaderButtonWidthVar, TyCascaderButtonWidth);
  if Result < 0 then Result := 0;
  Result := MulDiv(Result, APPI, 96);
end;

function TTyCascader.LayoutFor(AWidth, AHeight, APPI: Integer): TTyCascaderFieldLayout;
var
  S: TTyStyleSet;
begin
  if APPI <= 0 then APPI := 96;
  S := CurrentStyle;
  Result := TyCascaderFieldLayout(AWidth, AHeight,
    MulDiv(S.Padding.Left, APPI, 96), MulDiv(S.Padding.Top, APPI, 96),
    MulDiv(S.Padding.Right, APPI, 96), MulDiv(S.Padding.Bottom, APPI, 96),
    ButtonWidthPx(APPI));
end;

function TTyCascader.TyCascaderTextRect: TRect;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch).TextRect;
end;

function TTyCascader.TyCascaderButtonRect: TRect;
begin
  Result := LayoutFor(ClientWidth, ClientHeight, Font.PixelsPerInch).ButtonRect;
end;

{ --- the popup ------------------------------------------------------------------------ }

procedure TTyCascader.EnsurePopup;
begin
  if FPopup <> nil then Exit;
  // Neither of these touches a window handle: TTyDropdownPopup only constructs its TForm
  // object, and parenting the panel into it allocates nothing. That is what lets
  // DropDownPanel hand out a live, seeded panel headlessly.
  FPopup := TTyDropdownPopup.Create;
  FPopup.OnClose := @PopupClosed;
  FPanel := TTyCascaderPanel.Create(Self);
  FPanel.OnPick := @PanelPick;
  FPopup.SetContent(FPanel);
  FPopup.Form.KeyPreview := True;
  FPopup.Form.OnKeyDown := @PopupKeyDown;
end;

procedure TTyCascader.SyncPanel;
begin
  { ActiveController, not the raw published Controller: a field themed by the global default
    has Controller = nil, and handing nil to the popup helper makes ApplyRegion skip its
    background-colour set entirely — leaving the popup window on the OS default clBtnFace,
    which is DARK on a dark-mode OS. (The panel takes the raw value: nil there resolves to
    TyDefaultController by itself.)
    The helper still resolves that colour from 'TyListBox', not from ours — a hard-coding in
    tyControls.Popup. It does not show: the panel is alClient and paints its whole rect
    opaque, so the form colour can only ever appear in the gaps outside the panel's rounded
    corners, and those are exactly what ApplyRegion's window region cuts away. Where it
    cannot (Wayland, no XShape) ForceSquareSurface removes the gaps instead. }
  FPopup.Controller := ActiveController;
  FPanel.Controller := Controller;
  FPanel.ForceSquareSurface := TyQtIsWayland;
  FPanel.Root := FNodes;
  FPanel.Path := FPath;   // seed the DRAFT from the committed value
end;

function TTyCascader.DropDownPanel: TTyCascaderPanel;
begin
  EnsurePopup;
  SyncPanel;
  Result := FPanel;
end;

function TTyCascader.DroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

procedure TTyCascader.DropDown;
var
  S: TTyStyleSet;
  sz: TSize;
begin
  if (FNodes = nil) or (FNodes.Count = 0) then Exit;   // never show an empty popup
  EnsurePopup;
  FPopup.NoActivate := False;   // the panel's keys come through the form: it must activate
  SyncPanel;
  // The popup window's rounded region must match the panel's own themed fill.
  S := ActiveController.Model.ResolveStyle('TyCascaderPanel', StyleClass, []);
  FPopup.CornerRadiusLogical := S.BorderRadius;
  sz := FPanel.TyPanelSize(FDropDownRows, Font.PixelsPerInch);
  // Unlike a combo box's, the panel is WIDER than its field: pass the panel's own measured
  // width, not Width.
  FPopup.Popup(Self, sz.cx, sz.cy);
  DoDropDown;
end;

procedure TTyCascader.CloseUp;
begin
  if (FPopup <> nil) and FPopup.IsOpen then
  begin
    FPopup.Close;   // -> PopupClosed, which mirrors the tick and fires DoCloseUp
    Exit;
  end;
  // Not open (the headless path, or already closed): still record the tick and fire the
  // bookkeeping so the reopen guard behaves the same.
  FCloseUpTick := GetTickCount64;
  Invalidate;
  DoCloseUp;
end;

procedure TTyCascader.DeferredCloseUp(Data: PtrInt);
begin
  CloseUp;
end;

procedure TTyCascader.PopupClosed(Sender: TObject);
begin
  if FPopup <> nil then FCloseUpTick := FPopup.CloseUpTick;
  Invalidate;
  DoCloseUp;
end;

procedure TTyCascader.PanelPick(Sender: TObject);
begin
  // The panel edits a DRAFT. Only a LEAF is a complete answer: a branch pick just opened the
  // next column and the value stays what it was, so dismissing the popup mid-browse cannot
  // strand the field on a half-finished path.
  if not FPanel.DraftIsLeaf then Exit;
  Path := FPanel.Path;   // -> SetPath: OnChange, exactly once, only on a real change
  // Defer the close: hiding the popup synchronously here — still inside the panel's own
  // mouse handler — leaves LCL's click-completion focus path pointing at the now-hidden
  // form (EInvalidOperation 'Can not focus'). Next message cycle is soon enough.
  Application.QueueAsyncCall(@DeferredCloseUp, 0);
end;

procedure TTyCascader.PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { The panel is TabStop=False so the popup FORM holds focus; its KeyPreview routes every key
    here. That is deliberate — one keyboard, in the control that owns the value, rather than
    a second key handler on a panel that may or may not have been focused (the trap
    TTyComboBox's Escape handler already works around). }
  case Key of
    VK_ESCAPE:
      begin
        // Discard the draft: the panel is re-seeded from Path on the next DropDown.
        CloseUp;
        Key := 0;
      end;
    VK_DOWN:  begin FPanel.StepDraft(1);  Key := 0; end;
    VK_UP:    begin FPanel.StepDraft(-1); Key := 0; end;
    VK_RIGHT: begin FPanel.EnterDraft;    Key := 0; end;
    VK_LEFT:  begin FPanel.LeaveDraft;    Key := 0; end;
    VK_RETURN:
      begin
        // Enter commits — but only a complete answer. On a branch it is inert rather than
        // committing a half-path (the mouse cannot do that either).
        if FPanel.DraftIsLeaf then
        begin
          Path := FPanel.Path;
          CloseUp;
        end;
        Key := 0;
      end;
  end;
end;

{ --- input ---------------------------------------------------------------------------- }

procedure TTyCascader.Click;
begin
  if not Enabled then Exit;
  inherited Click;
  { Clicking the field while the popup is open fires the form's deactivate -> FPopup.Close ->
    PopupClosed BEFORE this handler runs, so DroppedDown is already False here and a naive
    toggle would immediately re-open. Suppress the reopen when a close-up happened within the
    last 200ms (TTyComboBox's guard, same mechanics). }
  if DroppedDown then
    CloseUp
  else if GetTickCount64 - FCloseUpTick > 200 then
    DropDown;
end;

procedure TTyCascader.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and DroppedDown then
  begin
    CloseUp;
    Key := 0;
    Exit;
  end;
  // Alt+Down / F4 toggle the dropdown — the platform's combo-field keyboard, which this
  // field should answer to as well.
  if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
  begin
    if DroppedDown then CloseUp else DropDown;
    Key := 0;
  end;
end;

procedure TTyCascader.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCascader.DoDropDown;
begin
  if Assigned(FOnDropDown) then FOnDropDown(Self);
end;

procedure TTyCascader.DoCloseUp;
begin
  if Assigned(FOnCloseUp) then FOnCloseUp(Self);
end;

{ --- painting ------------------------------------------------------------------------- }

procedure TTyCascader.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  Lay: TTyCascaderFieldLayout;
  shown: string;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at ARect.Left/Top,
    // so a non-zero ARect origin would shift the field.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    if not (tpBackground in S.Present) then
    begin
      // A theme that does not define TyCascader gets no field at all rather than a
      // hard-coded one. Degrade, never invent a colour.
      P.EndPaint;
      Exit;
    end;

    Lay := TyCascaderFieldLayout(R.Right, R.Bottom,
      P.Scale(S.Padding.Left), P.Scale(S.Padding.Top),
      P.Scale(S.Padding.Right), P.Scale(S.Padding.Bottom),
      P.Scale(ActiveController.Metric(TyCascaderButtonWidthVar, TyCascaderButtonWidth)));

    shown := GetPathText;
    if (shown <> '') and (Lay.TextRect.Right > Lay.TextRect.Left) then
      // Ellipsised: a field narrower than its path shows '华东 / 浙江 / 杭…', not a glyph
      // sheared at the clip edge.
      P.DrawText(Lay.TextRect, shown, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);

    // v3/C5: the dropdown indicator is theme-overridable (--glyph-dropdown, the token
    // TTyComboBox already uses — one theme rule retunes every field's chevron); else the
    // built-in chevron.
    if Lay.ButtonRect.Right > Lay.ButtonRect.Left then
      if not TyTryDrawGlyphOverride(P, ActiveController, Lay.ButtonRect, '--glyph-dropdown',
        S.TextColor) then
        P.DrawDropChevron(Lay.ButtonRect, S.TextColor);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCascader.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
